#!/usr/bin/env python3
"""Private, isolated Rust PGO experiment; never changes the shipping build.

Training and use must have the same target, source and compiler. Host profiles
do not match target-dependent Rust symbols in iOS builds. This runner currently
trains the native macOS smoke executable only; it does not train an iOS app.
Reserve a quiet host window before either command: both execute all fixtures.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
HOST_TARGET = "aarch64-apple-darwin"
CPU_FLAGS = "-Ctarget-cpu=apple-a7 -Ztune-cpu=apple-a14"
FIRMWARES = ("stock", "felucca", "sloop")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_files() -> dict[str, str]:
    paths = [ROOT / "Cargo.toml", ROOT / "Cargo.lock"]
    for directory in (ROOT / "Core", ROOT / "Vendor"):
        paths.extend(p for p in directory.rglob("*")
                     if p.is_file() and not {"target", ".git", "__pycache__"}.intersection(p.relative_to(directory).parts))
    if any(p.is_symlink() for p in paths):
        raise RuntimeError("Source symlinks are unsupported; use an ordinary local checkout")
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)}


def source_hash(files: dict[str, str]) -> str:
    return hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()


def output(command: list[str]) -> str:
    return subprocess.check_output(command, text=True, cwd=ROOT).strip()


def save(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def build(folder: Path, variant: str, flags: str) -> None:
    env = os.environ.copy()
    env.update(CARGO_TARGET_DIR=str(folder / "targets" / variant), RUSTFLAGS=flags)
    with (folder / f"build-{variant}.log").open("w") as log:
        subprocess.run(["cargo", "build", "--release", "--target", HOST_TARGET,
                        "--example", "firmware_smoke"], cwd=folder / "source", env=env,
                       stdout=log, stderr=subprocess.STDOUT, check=True)


def measure(folder: Path, variant: str) -> list[dict]:
    binary = folder / "targets" / variant / HOST_TARGET / "release/examples/firmware_smoke"
    env = os.environ.copy()
    if variant == "generate":
        env["LLVM_PROFILE_FILE"] = str(folder / "profiles/%m-%p.profraw")
    rows = []
    for firmware in FIRMWARES:
        fixture = folder / "fixtures" / f"{firmware}.fwsc"
        started = time.monotonic()
        run = subprocess.run([str(binary), str(fixture)], cwd=folder / "source", env=env,
                             text=True, capture_output=True, check=True)
        elapsed = time.monotonic() - started
        (folder / f"{variant}-{firmware}.log").write_text(run.stdout + run.stderr)
        hashes = re.search(r"pcm=([0-9a-f]+) lcd=([0-9a-f]+) flash=([0-9a-f]+)", run.stdout)
        timing = re.search(r"wall=([0-9.]+)s", run.stdout)
        if hashes is None or timing is None:
            raise RuntimeError(f"Missing smoke evidence: {variant}/{firmware}")
        rows.append(dict(firmware=firmware, variant=variant, wall=float(timing[1]),
                         processWall=elapsed, fingerprints=list(hashes.groups()),
                         wavSHA256=digest(Path(str(fixture) + ".wav"))))
        print(json.dumps(rows[-1]), flush=True)
    save(folder / f"{variant}-results.json", rows)
    return rows


def require_matching_rows(reference: list[dict], candidate: list[dict]) -> None:
    for old, new in zip(reference, candidate, strict=True):
        if any(old[key] != new[key] for key in ("firmware", "fingerprints", "wavSHA256")):
            raise RuntimeError(f"Deterministic output differs for {new['firmware']}")


def train(args: argparse.Namespace) -> None:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", args.label):
        raise RuntimeError("Use a simple unique label containing letters, digits, dot, underscore or dash")
    folder = ROOT / "Research/Performance" / f"PGO-{args.label}"
    if folder.exists():
        raise RuntimeError(f"Refusing to overwrite an experiment: {folder}")
    compiler = output(["rustc", "--version", "--verbose"])
    if "host: " + HOST_TARGET not in compiler:
        raise RuntimeError("This harness trains aarch64-apple-darwin only")
    sysroot = Path(output(["rustc", "--print", "sysroot"]))
    profdata = sysroot / "lib/rustlib" / HOST_TARGET / "bin/llvm-profdata"
    if not profdata.is_file():
        raise RuntimeError("Matching llvm-profdata missing; install rustup component llvm-tools-preview first")
    files = source_files()
    folder.mkdir(parents=True)
    (folder / "fixtures").mkdir()
    (folder / "profiles").mkdir()
    for relative in files:
        destination = folder / "source" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, destination)
        if digest(destination) != files[relative]:
            raise RuntimeError("Source changed while freezing; retry once edits are complete")
    if source_files() != files:
        raise RuntimeError("Source changed while freezing; retry once edits are complete")
    # Only the smoke wall formatter changes; record both source and harness hash.
    smoke = folder / "source/Core/examples/firmware_smoke.rs"
    smoke.write_text(smoke.read_text().replace("wall={:.2}s", "wall={:.6}s"))
    fixture_hashes = {}
    for firmware in FIRMWARES:
        fixture = Path(getattr(args, firmware)).expanduser().resolve(strict=True)
        destination = folder / "fixtures" / f"{firmware}.fwsc"
        shutil.copy2(fixture, destination)
        fixture_hashes[firmware] = digest(destination)
    manifest = dict(sourceRevision=output(["git", "rev-parse", "HEAD"]), sourceSHA256=source_hash(files),
                    sourceFiles=files, smokeHarnessSHA256=digest(smoke), rustc=compiler,
                    llvmProfdata=output([str(profdata), "--version"]), target=HOST_TARGET,
                    cpuFlags=CPU_FLAGS, fixtureSHA256=fixture_hashes,
                    runsPerFirmware=1, requestedBlocks=900, framesPerBlock=512,
                    key21PressBlock=400, key21ReleaseBlock=700,
                    shippingChanges=False, status="training-incomplete")
    save(folder / "manifest.json", manifest)
    build(folder, "baseline", CPU_FLAGS)
    reference = measure(folder, "baseline")
    generate = CPU_FLAGS + f" -Cprofile-generate={folder / 'profiles'}"
    build(folder, "generate", generate)
    require_matching_rows(reference, measure(folder, "generate"))
    raw = sorted((folder / "profiles").glob("*.profraw"))
    if len(raw) != 3:
        raise RuntimeError(f"Expected three fresh training processes/profiles, found {len(raw)}")
    profile = folder / "merged.profdata"
    subprocess.run([str(profdata), "merge", "-o", str(profile), *map(str, raw)], check=True)
    manifest.update(status="trained", generateFlags=generate, mergedProfileSHA256=digest(profile))
    save(folder / "manifest.json", manifest)
    print(f"Trained all three equally: {folder}", flush=True)


def use(args: argparse.Namespace) -> None:
    folder = Path(args.profile_dir).expanduser().resolve(strict=True)
    if not folder.is_relative_to(ROOT / "Research/Performance"):
        raise RuntimeError("Profile directory must remain in this checkout's ignored Research/Performance")
    manifest = json.loads((folder / "manifest.json").read_text())
    profile = folder / "merged.profdata"
    if manifest.get("status") != "trained" or not profile.is_file():
        raise RuntimeError("Completed training profile is missing; there is no non-PGO fallback")
    if digest(profile) != manifest["mergedProfileSHA256"]:
        raise RuntimeError("Training profile hash changed")
    if args.target != manifest["target"]:
        raise RuntimeError("Profile target mismatch: host Rust profiles do not map iOS symbols; train on the intended target")
    if source_hash(source_files()) != manifest["sourceSHA256"]:
        raise RuntimeError("Source changed since training; retrain on this candidate before using PGO")
    for relative, expected in manifest["sourceFiles"].items():
        if relative == "Core/examples/firmware_smoke.rs":
            expected = manifest["smokeHarnessSHA256"]
        if digest(folder / "source" / relative) != expected:
            raise RuntimeError("Frozen training source changed; preserve this evidence and retrain")
    for firmware, expected in manifest["fixtureSHA256"].items():
        if digest(folder / "fixtures" / f"{firmware}.fwsc") != expected:
            raise RuntimeError("Frozen fixture changed; preserve this evidence and retrain")
    if output(["rustc", "--version", "--verbose"]) != manifest["rustc"]:
        raise RuntimeError("Compiler changed since training; retrain using the current compiler")
    if (folder / "pgo-results.json").exists():
        raise RuntimeError("PGO results already exist; preserve this experiment and use a new training label")
    flags = CPU_FLAGS + f" -Cprofile-use={profile} -Cllvm-args=-pgo-warn-missing-function"
    build(folder, "pgo", flags)
    require_matching_rows(json.loads((folder / "baseline-results.json").read_text()), measure(folder, "pgo"))
    log = (folder / "build-pgo.log").read_text()
    save(folder / "use-manifest.json", dict(target=args.target, flags=flags,
         sourceSHA256=manifest["sourceSHA256"], mergedProfileSHA256=digest(profile),
         missingProfileWarnings=log.count("no profile data available"),
         hashMismatchWarnings=len(re.findall("hash mismatch", log, re.I)),
         fingerprintsMatch=True, shippingChanges=False))
    print("PGO measured; review all missing-profile warnings and repeat in reverse order before accepting a gain.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    training = sub.add_parser("train", help="freeze source, build baseline/generator, run each fixture once and merge")
    training.add_argument("label")
    for firmware in FIRMWARES:
        training.add_argument("--" + firmware, required=True, help="local private .fwsc fixture")
    using = sub.add_parser("use", help="validate source/profile, build PGO, run and compare all three fixtures")
    using.add_argument("profile_dir")
    using.add_argument("--target", default=HOST_TARGET)
    args = parser.parse_args()
    try:
        (train if args.action == "train" else use)(args)
    except (RuntimeError, OSError, subprocess.CalledProcessError, ValueError) as error:
        parser.exit(1, f"PGO experiment failed: {error}\n")


if __name__ == "__main__":
    main()
