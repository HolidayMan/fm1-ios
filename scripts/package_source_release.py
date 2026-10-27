#!/usr/bin/env python3
"""Package reviewed source plus an exact public-upstream acquisition manifest.

No network, build, upload, signing material, ignored Research files or Git history
is copied. Upstream engine sources are acquired separately at the recorded commits
using docs/source-release.md; their full source is not duplicated in this archive.
"""
import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[1]
ROOT_FILES = {".gitignore", "AGENTS.md", "README.md", "LICENSE", "NOTICE", "Cargo.toml", "Cargo.lock"}
SOURCE_DIRS = {"App", "Core", "Vendor", "Tests", "FM1Tests", "FM1UITests", "scripts"}
SOURCE_SUFFIXES = {".swift", ".rs", ".c", ".h", ".inc", ".def", ".py", ".sh", ".toml",
                   ".json", ".md", ".txt", ".plist", ".xcprivacy", ".png"}
BUILD_DOCS = {"docs/source-release.md", "docs/store26-rights-audit.md",
              "docs/native-store-build.md",
              "docs/native-sloop.md", "docs/native-family.md", "docs/native-expansion.md",
              "docs/native-official-preview.md", "docs/native-skiff.md", "docs/native-community.md", "docs/app-icon.md"}
FORBIDDEN_PARTS = {".git", "Research", "target", "build", "build-device", "__pycache__",
                   "xcuserdata", "WebEngine", "sdk/lib", "cz1-factory", "prophet5-factory"}
FORBIDDEN_SUFFIXES = {".fwsc", ".wasm", ".bin", ".a", ".o", ".dylib", ".syx", ".fxp",
                      ".p8", ".p12", ".pem", ".key", ".mobileprovision", ".ipa", ".flash",
                      ".wav", ".pcm", ".log", ".xcuserstate"}
PRIVATE_KEY = re.compile(rb"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----")


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.PIPE)


def selected(name):
    path = Path(name)
    if path.is_absolute() or ".." in path.parts or any(part in FORBIDDEN_PARTS for part in path.parts):
        # Preserve original asset provenance README notices, never those assets.
        return name in {"Core/native/licenses/melodee/assets/cz1-factory/README.md",
                        "Core/native/licenses/melodee/assets/prophet5-factory/README.md"}
    if path.suffix.lower() in FORBIDDEN_SUFFIXES or path.name.startswith(".env"):
        return False
    if name in ROOT_FILES or name in BUILD_DOCS:
        return True
    if path.parts[0] == "FM1.xcodeproj":
        return name == "FM1.xcodeproj/project.pbxproj" or (
            name.startswith("FM1.xcodeproj/xcshareddata/xcschemes/") and path.suffix == ".xcscheme")
    if path.parts[0] not in SOURCE_DIRS:
        return False
    return path.suffix in SOURCE_SUFFIXES or path.name.startswith(("LICENSE", "NOTICE", "THIRD-PARTY"))


def sources(root):
    names = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard").decode().split("\0")
    result = {}
    for name in sorted(set(filter(None, names))):
        if not selected(name):
            continue
        file = root / name
        if file.is_symlink() or not file.resolve().is_relative_to(root.resolve()):
            raise ValueError("Selected source contains a symlink or escapes the source root: " + name)
        if not file.is_file():
            continue  # A removed tracked file is absent from this source snapshot.
        data = file.read_bytes()
        if PRIVATE_KEY.search(data):
            raise ValueError("Private-key material detected in selected source: " + name)
        result[name] = data
    required = {"LICENSE", "NOTICE", "App/Info.plist", "Cargo.toml", "Cargo.lock", "Core/build.rs",
                "scripts/build.sh", "scripts/build_core.sh", "scripts/generate_project.py",
                "scripts/audit_store_artifact.py", "scripts/package_source_release.py",
                "Core/native/melodee_init_bank.py", "docs/source-release.md"}
    missing = required - result.keys()
    if missing:
        raise ValueError("Required source files are missing: " + ", ".join(sorted(missing)))
    return result


def upstream_record(identity, descriptor, lock_name):
    repository, commit = descriptor["source"].removesuffix(".git"), descriptor["commit"]
    if not re.fullmatch(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Upstream must be an explicit public GitHub source URL: " + identity)
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Upstream source commit must be immutable: " + identity)
    result = {"id": identity, "repository": repository, "commit": commit,
              "source_url": repository + "/tree/" + commit,
              "source_archive_url": repository + "/archive/" + commit + ".tar.gz",
              "lock_file": lock_name, "source_acquisition": "separate pinned Git checkout"}
    for key in ["tag", "generated_headers_sha256", "notices_sha256", "submodules", "submodule_sources", "derived_soundset", "additional_source_notices", "asset_grant_evidence"]:
        if key in descriptor:
            result[key] = descriptor[key]
    if identity == "felucca":
        result["submodule_sources"] = {"firmware/engines": "https://github.com/hugelton/Felucca-Engines"}
    return result


def manifest(root, files):
    def read(name):
        return json.loads(files[name])
    native = "Core/native/"
    upstream = read(native + "upstream.lock.json")
    family = read(native + "family.lock.json")
    expansion = read(native + "expansion.lock.json")
    records = [upstream_record("sloop", upstream["sloop"], native + "upstream.lock.json")]
    records += [upstream_record(d["id"], d, native + "family.lock.json") for d in family["firmwares"]]
    records += [upstream_record(d["id"], d, native + "expansion.lock.json") for d in expansion["firmwares"]]
    records += [upstream_record(d["id"], d, native + "community/community.lock.json") for d in read(native + "community/community.lock.json")["firmwares"]]
    records += [upstream_record("skiff", read(native + "skiff.lock.json"), native + "skiff.lock.json"),
                upstream_record("fm1-open", read(native + "official_preview.lock.json"), native + "official_preview.lock.json")]
    wrapper = upstream_record("virtual-fm1-wrapper-origin", upstream["wrapper_origin"], native + "upstream.lock.json")
    wrapper["source_acquisition"] = "adapted source and state tooling included under Core/native"
    wrapper["origin_files"] = upstream["wrapper_origin"]["files"]
    records.append(wrapper)
    app = plistlib.loads(files["App/Info.plist"])
    return {"schema_version": 1, "product": app["CFBundleDisplayName"],
            "version": app["CFBundleShortVersionString"], "build": app["CFBundleVersion"],
            "git_commit": git(root, "rev-parse", "HEAD").decode().strip(),
            "working_tree_modified": bool(git(root, "status", "--porcelain", "--untracked-files=normal")),
            "scope": "native consumer source snapshot plus exact public-upstream acquisition route",
            "upstream_source_copies_included": False,
            "build_instructions": "docs/source-release.md", "upstreams": records,
            "files": {name: {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                      for name, data in sorted(files.items())}}


def tar_bytes(files, release_manifest):
    prefix = f"PocketFM-{release_manifest['version']}-{release_manifest['build']}-source"
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", prefix):
        raise ValueError("Invalid version/build for source archive name")
    payload = dict(files, **{"SOURCE-MANIFEST.json": (json.dumps(release_manifest, indent=2, sort_keys=True) + "\n").encode()})
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb", filename="", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
            for name, data in sorted(payload.items()):
                entry = tarfile.TarInfo(prefix + "/" + name)
                entry.size = len(data)
                entry.mode = 0o755 if Path(name).suffix in {".py", ".sh"} else 0o644
                entry.mtime = entry.uid = entry.gid = 0
                entry.uname = entry.gname = ""
                archive.addfile(entry, io.BytesIO(data))
    return buffer.getvalue()


def package(root, output):
    files = sources(root)
    release_manifest = manifest(root, files)
    archive = tar_bytes(files, release_manifest)
    digest = hashlib.sha256(archive).hexdigest()
    output = output.expanduser().resolve()
    if not output.name.endswith(".tar.gz"):
        raise ValueError("Source archive output must end in .tar.gz")
    products = {output: archive,
                output.with_name(output.name + ".sha256"): (digest + "  " + output.name + "\n").encode(),
                output.with_name(output.name + ".manifest.json"): (json.dumps(release_manifest, indent=2, sort_keys=True) + "\n").encode()}
    if any(path.exists() for path in products):
        raise ValueError("Source archive and sidecars must be new files")
    output.parent.mkdir(parents=True, exist_ok=True)
    created = []
    try:
        with tempfile.TemporaryDirectory(prefix=".source-package-", dir=output.parent) as temp:
            for number, (destination, data) in enumerate(products.items()):
                stage = Path(temp) / str(number)
                stage.write_bytes(data)
                os.chmod(stage, 0o644)
                os.link(stage, destination)  # Exclusive creation, never replace an existing release.
                created.append(destination)
    except BaseException:
        for path in created:
            path.unlink()
        raise
    return {"file_count": len(files), "archive_bytes": len(archive), "archive_sha256": digest,
            "upstream_source_copies_included": False, "published": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        print(json.dumps(package(ROOT, args.output), indent=2))
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # No credential/config/key files are opened; do not echo subprocess diagnostics.
        print("Source package failed: " + (str(error) if isinstance(error, ValueError) else "local file/Git operation failed"))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
