#!/usr/bin/env python3
"""Opt-in, Release-only three-firmware benchmark on the explicitly named FM1 simulator.

All packages, saved-state snapshots, reports and build products stay ignored/local.
No physical-device tools are used. No benchmark runs with --prepare-only.
"""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "com.local.fm1.instrument"
DEFAULT_STATE = ROOT / "Research/Performance/simulator-baseline-70b25ce-state"


def command(args, log=None, check=True):
    if log:
        with log.open("a") as output:
            result = subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    else:
        result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if check and result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}); see {log or 'tool output'}")
    return result.stdout if not log else result.returncode


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def local_path(value, parent):
    path = Path(value).resolve()
    if not path.is_relative_to(parent.resolve()):
        raise ValueError(f"Path must stay inside {parent}")
    return path


def snapshot(path, simulator):
    value = json.loads((path / "manifest.json").read_text())
    if value["formatVersion"] != 1 or value["simulatorID"] != simulator:
        raise ValueError("Snapshot must belong to the explicitly requested simulator")
    if {x["key"] for x in value["fixtures"]} != {"stock", "felucca", "sloop"}:
        raise ValueError("Snapshot must contain the three fixed benchmark releases")
    for fixture in value["fixtures"]:
        for name in (fixture["id"], fixture["package"], fixture.get("flash")):
            if name and (Path(name).name != name or name in (".", "..") or "\\" in name):
                raise ValueError("Snapshot contains an invalid filename")
        if digest(path / fixture["package"]) != fixture["sha256"]:
            raise ValueError("Snapshot package digest mismatch")
        if fixture["flash"]:
            if digest(path / fixture["flash"]) != fixture["flashSHA256"]:
                raise ValueError("Snapshot flash digest mismatch")
        elif fixture["flashSHA256"] != "absent":
            raise ValueError("Missing flash requires an explicit absence marker")
    return value


def build(label, reuse, stress, rust_archive=None, pgo_training=False, saved_sequencer=None):
    folder = local_path(reuse, ROOT / "build") if reuse else ROOT / "build" / f"PerformanceSimulator-{label}"
    manifest = folder / "performance-build.json"
    if reuse:
        info = json.loads(manifest.read_text())
        if stress and not info.get("supportsAudioStress", False):
            raise ValueError("Frozen bundle predates the stress harness; prepare a new Release bundle")
        if saved_sequencer and (not info.get("supportsSavedSequencerStress", False) or not info.get("supportsNativeWorkloadMetrics", False)):
            raise ValueError("Frozen bundle predates the saved-sequencer workload verification")
        if pgo_training and not info.get("pgoTraining", False):
            raise ValueError("Frozen bundle does not contain the instrumented LLVM runtime")
        if info["configuration"] != "Release":
            raise ValueError("Only a frozen Release test build can be reused")
    else:
        if folder.exists():
            raise ValueError("Run label already has a build; choose a new label or --reuse it")
        folder.mkdir(parents=True)
        log = folder / "build.log"
        archive = folder / "Rust/libfm1_ios_core.a"
        archive.parent.mkdir()
        if rust_archive:
            supplied=Path(rust_archive).resolve(strict=True)
            if not any(supplied.is_relative_to(ROOT / p) for p in ("build", "Research")):
                raise ValueError("External Rust archive must be frozen inside ignored build/ or Research/")
            shutil.copyfile(supplied, archive)
        else:
            command(["cargo", "build", "-p", "fm1-ios-core", "--release", "--target", "aarch64-apple-ios-sim"], log)
            shutil.copyfile(ROOT / "target/aarch64-apple-ios-sim/release/libfm1_ios_core.a", archive)
        # A private project copy makes the frozen Rust path unambiguous, including
        # Xcode's conditional sdk setting, without changing the shipping project.
        source=folder / "Source"
        source.mkdir()
        for name in ("App", "FM1Tests", "FM1UITests", "FM1.xcodeproj"):
            shutil.copytree(ROOT / name, source / name)
        project=source / "FM1.xcodeproj/project.pbxproj"
        contents=project.read_text().replace('"$(SRCROOT)/target/aarch64-apple-ios-sim/release"', f'"{archive.parent}"')
        if pgo_training:
            if not rust_archive:
                raise ValueError("PGO training requires an explicitly instrumented --rust-archive")
            sysroot=Path(command(["rustc", "--print", "sysroot"]).strip())
            runtimes=list((sysroot / "lib/rustlib/aarch64-apple-ios-sim/lib").glob("libprofiler_builtins-*.rlib"))
            if len(runtimes) != 1:
                raise ValueError("Matching Rust LLVM profiler runtime is unavailable")
            runtime=folder / "Rust/libprofiler_builtins.rlib"
            shutil.copyfile(runtimes[0],runtime)
            flags=['-lfm1_ios_core','-liconv',str(runtime),'-Wl,-export_dynamic']
            flags += ['-Wl,-u,___llvm_profile_'+name for name in ('write_file','set_filename','reset_counters')]
            replacement='OTHER_LDFLAGS = ('+', '.join('"'+f+'"' for f in flags)+');'
            original='OTHER_LDFLAGS = ("-lfm1_ios_core", "-liconv");'
            if contents.count(original) != 2:
                raise ValueError("Unexpected app linker settings; refusing to change unrelated targets")
            contents=contents.replace(original,replacement)
        project.write_text(contents)
        command(["xcodebuild", "-project", str(source / "FM1.xcodeproj"), "-scheme", "FM1", "-configuration", "Release",
                 "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(folder),
                 "ENABLE_TESTABILITY=YES", "CODE_SIGNING_ALLOWED=NO", "build-for-testing"], log)
        info = {"revision": command(["git", "rev-parse", "HEAD"]).strip(), "configuration": "Release",
                "sourceTreeDirty": bool(command(["git", "status", "--porcelain"]).strip()),
                "supportsAudioStress": (ROOT / "FM1Tests/AudioStressTests.swift").exists(),
                "supportsSavedSequencerStress": "testSloopSavedSequencerStress" in (ROOT / "FM1Tests/AudioStressTests.swift").read_text(),
                "supportsNativeWorkloadMetrics": "NativeWorkloadDiagnostics" in (ROOT / "App/Instrument.swift").read_text(),
                "appVersion": plistlib.loads((ROOT / "App/Info.plist").read_bytes())["CFBundleShortVersionString"],
                "appBuild": plistlib.loads((ROOT / "App/Info.plist").read_bytes())["CFBundleVersion"],
                "pgoTraining":pgo_training,
                "rustArchiveSHA256": digest(archive),
                "appExecutableSHA256": digest(folder / "Build/Products/Release-iphonesimulator/FM1.app/FM1"),
                "testExecutableSHA256": digest(folder / "Build/Products/Release-iphonesimulator/FM1.app/PlugIns/FM1Tests.xctest/FM1Tests")}
        manifest.write_text(json.dumps(info, indent=2) + "\n")
    app = folder / "Build/Products/Release-iphonesimulator/FM1.app"
    if (digest(app / "FM1") != info["appExecutableSHA256"] or
            digest(app / "PlugIns/FM1Tests.xctest/FM1Tests") != info["testExecutableSHA256"]):
        raise ValueError("Frozen app or test executable has changed")
    specs = list((folder / "Build/Products").glob("FM1_*.xctestrun"))
    if len(specs) != 1:
        raise ValueError("Expected one generated FM1 xctestrun")
    spec = plistlib.loads(specs[0].read_bytes())
    spec["FM1Tests"].setdefault("EnvironmentVariables", {}).update({
        "FM1_RUN_SIMULATOR_PERFORMANCE": "0" if stress or saved_sequencer else "1",
        "FM1_RUN_AUDIO_STRESS": "1" if stress else "0",
        "FM1_RUN_SAVED_SEQUENCER_STRESS": "1" if saved_sequencer else "0",
        "FM1_BENCHMARK_REVISION": info["revision"],
        "FM1_WRITE_LLVM_PROFILE":"1" if pgo_training else "0",
        "FM1_BENCHMARK_RUN": label})
    if saved_sequencer:
        spec["FM1Tests"]["EnvironmentVariables"].update({
            "FM1_SAVED_SEQUENCER_FLASH_SHA256": saved_sequencer["sha256"],
            "FM1_SAVED_SEQUENCER_SECONDS": str(saved_sequencer["seconds"]),
            "FM1_SAVED_SEQUENCER_TEMPO_BPM": str(saved_sequencer["tempo"]),
            "FM1_SAVED_SEQUENCER_REQUIRE_MAX_WORKLOAD": "1" if saved_sequencer["requireMaxWorkload"] else "0"})
    run_spec = specs[0].with_name(f"Performance-{label}.xctestrun")
    run_spec.write_bytes(plistlib.dumps(spec))
    return folder, app, run_spec, info


def restore_fixture(directory, state, manifest, backup):
    targets = {fixture["id"] + suffix for fixture in manifest["fixtures"] for suffix in (".fwsc", ".flash")}
    names = {fixture["name"] for fixture in manifest["fixtures"]}
    hashes = {fixture["sha256"] for fixture in manifest["fixtures"]}
    for package in directory.glob("*.fwsc"):
        if package.stem.split(" · ")[0] in names or digest(package) in hashes:
            targets.update((package.name, package.with_suffix(".flash").name))
    backup.mkdir()
    for name in targets:
        source = directory / name
        if source.exists():
            shutil.copyfile(source, backup / name)
    # Record targets before mutation so cleanup also handles an interrupted copy.
    (backup / "targets.json").write_text(json.dumps(sorted(targets)))
    for name in targets:
        (directory / name).unlink(missing_ok=True)
    for fixture in manifest["fixtures"]:
        shutil.copyfile(state / fixture["package"], directory / (fixture["id"] + ".fwsc"))
        if fixture["flash"]:
            shutil.copyfile(state / fixture["flash"], directory / (fixture["id"] + ".flash"))


def restore_previous(directory, backup):
    targets = json.loads((backup / "targets.json").read_text())
    for name in targets:
        (directory / name).unlink(missing_ok=True)
        if (backup / name).exists():
            shutil.copyfile(backup / name, directory / name)



def backup_app_state(container, backup):
    backup.mkdir()
    for source, name in ((container / "Documents", "Documents"), (container / "Library/Preferences", "Preferences")):
        if source.exists():
            shutil.copytree(source, backup / name)


def restore_app_state(container, backup):
    for name, target in (("Documents", container / "Documents"), ("Preferences", container / "Library/Preferences")):
        if target.exists():
            shutil.rmtree(target)
        source = backup / name
        if source.exists():
            shutil.copytree(source, target)
            before = {str(p.relative_to(source)):digest(p) for p in source.rglob("*") if p.is_file()}
            after = {str(p.relative_to(target)):digest(p) for p in target.rglob("*") if p.is_file()}
            if before != after:
                raise RuntimeError("Prior simulator app-state restore failed byte verification")


def current_container(simulator):
    # XCTest may reinstall the app and relocate its data container even with
    # test-without-building. Resolve again after testing, never reuse that path.
    path=Path(command(["xcrun", "simctl", "get_app_container", simulator, BUNDLE, "data"]).strip())
    expected=Path.home() / "Library/Developer/CoreSimulator/Devices" / simulator / "data/Containers/Data/Application"
    if not path.is_relative_to(expected) or not path.is_dir():
        raise ValueError("Simulator returned an unexpected app data-container path")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("simulator_id", help="Explicit UUID of the dedicated FM1 iPhone 12 simulator")
    parser.add_argument("run_label", help="Unique lowercase artifact label")
    parser.add_argument("--reuse", help="Reuse a frozen Release derived-data folder inside build/")
    parser.add_argument("--snapshot", default=str(DEFAULT_STATE), help="Ignored fixture-state folder inside Research/")
    parser.add_argument("--prepare-only", action="store_true", help="Build/freeze only; do not boot or run the simulator")
    parser.add_argument("--stress", action="store_true", help="Run separate opt-in 5s warmup +60s one-key/three-key/control stress; preserve the 25s comparison")
    parser.add_argument("--saved-sequencer-flash", help="Opt-in saved-loop test using this explicit copied flash inside Research/; never reads a phone")
    parser.add_argument("--require-max-workload", action="store_true", help="Require all four native tracks, eight synth/six drum voices and all effect configuration flags")
    parser.add_argument("--saved-sequencer-seconds", type=float, default=30, help="Saved-loop measured duration, 30–300 seconds; last 15s add 8Hz pad attacks")
    parser.add_argument("--saved-sequencer-tempo", type=int, default=90, help="Tempo metadata of the explicit hash-pinned saved-loop fixture")
    parser.add_argument("--rust-archive", help="Use an explicit frozen Rust archive inside build/ or Research/ (no shared Rust build)")
    parser.add_argument("--pgo-training", action="store_true", help="Test-only matching LLVM runtime and explicit profile flush; requires instrumented Rust archive")
    parser.add_argument("--post-diagnostics", action="store_true", help="After measurements, run focused model, geometry and audio checks before shutdown")
    parser.add_argument("--settle-seconds", type=float, default=15, help="Wait after boot/install before measurements")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,79}", args.run_label):
        parser.error("run_label must contain 1–80 lowercase letters, digits or hyphens")
    if not 0 <= args.settle_seconds <= 300:
        parser.error("settle-seconds must be between 0 and 300")
    state = local_path(args.snapshot, ROOT / "Research")
    fixture_state = snapshot(state, args.simulator_id)
    inventory = json.loads(command(["xcrun", "simctl", "list", "devices", "available", "--json"]))
    devices = [d for group in inventory["devices"].values() for d in group if d["udid"] == args.simulator_id]
    if len(devices) != 1 or devices[0]["name"] != fixture_state["simulatorName"] or not devices[0]["name"].startswith("FM1"):
        raise ValueError("Only the dedicated, explicitly named FM1 simulator is allowed")
    if args.reuse and args.rust_archive:
        parser.error("--reuse and --rust-archive cannot be combined")
    if args.stress and args.pgo_training:
        parser.error("PGO training uses the three original25s scenarios")
    saved_sequencer = None
    if args.require_max_workload and not args.saved_sequencer_flash:
        parser.error("--require-max-workload requires --saved-sequencer-flash")
    if args.saved_sequencer_flash:
        if args.stress or args.pgo_training:
            parser.error("Saved sequencer is a separate scenario from sustained-note stress and PGO")
        if not 30 <= args.saved_sequencer_seconds <= 300 or not 20 <= args.saved_sequencer_tempo <= 400:
            parser.error("Saved sequencer duration must be 30–300s and tempo metadata 20–400 BPM")
        flash = local_path(args.saved_sequencer_flash, ROOT / "Research")
        if not flash.is_file() or not 1 <= flash.stat().st_size <= 4 * 1024 * 1024:
            parser.error("Saved sequencer flash must be an existing file up to 4 MiB")
        saved_sequencer = {"path":flash,"sha256":digest(flash),"seconds":args.saved_sequencer_seconds,"tempo":args.saved_sequencer_tempo,"requireMaxWorkload":args.require_max_workload}
    folder, app, spec, info = build(args.run_label, args.reuse, args.stress, args.rust_archive, args.pgo_training, saved_sequencer)
    print(f"Frozen Release build ready: {folder}", flush=True)
    if args.prepare_only:
        return 0
    reports = ROOT / "Research/Performance" / args.run_label
    if reports.exists():
        raise ValueError("Report label already exists; use a new run label")
    reports.mkdir(parents=True)
    result = folder / f"{args.run_label}.xcresult"
    if result.exists():
        raise ValueError("Result bundle already exists")
    backup, directory = reports / "simulator-before-run", None
    profile_directory=None
    full_backup=None
    try:
        if devices[0]["state"] != "Booted":
            command(["xcrun", "simctl", "boot", args.simulator_id])
        command(["xcrun", "simctl", "bootstatus", args.simulator_id, "-b"])
        command(["xcrun", "simctl", "terminate", args.simulator_id, BUNDLE], check=False)
        command(["xcrun", "simctl", "install", args.simulator_id, str(app)])
        container = current_container(args.simulator_id)
        directory = container / "Documents/Firmwares"
        directory.mkdir(parents=True, exist_ok=True)
        if saved_sequencer:
            # Preserve the entire app Documents and preferences, including unrelated
            # packages/saves and the selected firmware. XCTest can relocate these.
            candidate_backup = reports / "app-state-before-run"
            backup_app_state(container, candidate_backup)
            full_backup = candidate_backup
        if saved_sequencer:
            fixture = next(x for x in fixture_state["fixtures"] if x["key"] == "sloop")
            isolated = container / "Documents/PerformanceFixtures" / args.run_label
            isolated.mkdir(parents=True, exist_ok=False)
            shutil.copyfile(state / fixture["package"], isolated / (fixture["id"] + ".fwsc"))
            shutil.copyfile(saved_sequencer["path"], isolated / (fixture["id"] + ".flash"))
            if digest(isolated / (fixture["id"] + ".flash")) != saved_sequencer["sha256"]:
                raise ValueError("Copied saved-sequencer flash digest mismatch")
            value = plistlib.loads(spec.read_bytes())
            value["FM1Tests"]["EnvironmentVariables"]["FM1_SEQUENCER_FIXTURE_DIRECTORY"] = str(isolated.relative_to(container))
            spec.write_bytes(plistlib.dumps(value))
        else:
            restore_fixture(directory, state, fixture_state, backup)
        if args.pgo_training:
            profiles=container / "Documents/PGO"
            if profiles.exists():
                shutil.copytree(profiles,reports / "previous-pgo-profiles")
            profile_directory=profiles
            if profiles.exists():
                shutil.rmtree(profiles)
            profiles.mkdir()
            value=plistlib.loads(spec.read_bytes())
            value["FM1Tests"]["EnvironmentVariables"]["LLVM_PROFILE_FILE"]=str(profiles / "%p.profraw")
            spec.write_bytes(plistlib.dumps(value))
        time.sleep(args.settle_seconds)
        test_class = "AudioStressTests/testSloopSavedSequencerStress" if saved_sequencer else ("AudioStressTests" if args.stress else "DevicePerformanceTests")
        print(f"Measurement window: saved sequencer {saved_sequencer['seconds']}s, last 15s add 8Hz attacks." if saved_sequencer else ("Measurement window: three 65-second stress scenarios." if args.stress else
              "Measurement window: only the three unchanged 25-second sustained-note tests."), flush=True)
        status = command(["xcodebuild", "test-without-building", "-xctestrun", str(spec), "-destination",
                          f"platform=iOS Simulator,id={args.simulator_id}", "-resultBundlePath", str(result),
                          "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never", f"-only-testing:FM1Tests/{test_class}"], reports / "test.log", check=False)
        container=current_container(args.simulator_id)
        directory=container / "Documents/Firmwares"
        summary = {"build": info, "snapshot": str(state.relative_to(ROOT)), "simulatorID": args.simulator_id, "testsExitCode": status, "mode": "saved-sequencer" if saved_sequencer else ("stress" if args.stress else "comparison25"), "reports": {}}
        for key in (("sloop",) if saved_sequencer else ("stock", "felucca", "sloop")):
            prefix = "Stress" if args.stress or saved_sequencer else "Performance"
            suffix = "-saved-sequencer" if saved_sequencer else ""
            report_directory = container / ("Documents/PerformanceFixtures" if saved_sequencer else "Documents")
            report = json.loads((report_directory / f"{prefix}-{key}{suffix}.json").read_text())
            fixture = next(x for x in fixture_state["fixtures"] if x["key"] == key)
            expected_flash = saved_sequencer["sha256"] if saved_sequencer else fixture["flashSHA256"]
            if (report.get("benchmarkRun") != args.run_label or report.get("benchmarkPlatform") != "iOS Simulator" or
                    report.get("firmware") != fixture["id"] or report.get("benchmarkFirmwareSHA256") != fixture["sha256"] or
                    report.get("benchmarkInitialFlashSHA256") != expected_flash):
                raise ValueError(f"Missing, stale or mismatched {key} benchmark report")
            (reports / f"{key}.json").write_text(json.dumps(report, indent=2) + "\n")
            if args.stress or saved_sequencer:
                window = report["steadyWindow"]
                summary["reports"][key] = {"mean": window["meanRenderRatio"], "recentP95AtEnd": window["recentP95AtEnd"],
                    "missingCoreFrames": window["missingCoreFrames"], "missingOutputFrames": window["outputUnderrunFrames"],
                    "requestedOutputFrames": window["requestedOutputFrames"], "zeroShortages": window["zeroShortages"],
                    "meanMeetsHeadroomTarget": window["meanMeetsHeadroomTarget"], "recentP95BelowBudget": window["recentP95BelowBudget"]}
            else:
                summary["reports"][key] = {"mean": report["renderRatioMean"], "p95": report["renderRatioP95"],
                    "missingCoreFrames": report["missingFrames"], "missingOutputFrames": report["outputUnderrunFrames"],
                    "requestedOutputFrames": report["outputFrames"]}
        (reports / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        if args.pgo_training:
            profiles=container / "Documents/PGO"
            for key in ("stock", "felucca", "sloop"):
                if not list(profiles.glob(key+"-*.profraw")):
                    raise ValueError(f"Missing explicitly flushed LLVM profile for {key}")
            shutil.copytree(profiles,reports / "llvm-profiles")
        print(json.dumps(summary["reports"], indent=2), flush=True)
        if args.post_diagnostics:
            print("Quiet measurement window finished; running ordinary diagnostics checks.",flush=True)
            value=plistlib.loads(spec.read_bytes())
            value["FM1Tests"]["EnvironmentVariables"].update(FM1_RUN_SIMULATOR_PERFORMANCE="0",FM1_RUN_AUDIO_STRESS="0",FM1_RUN_SAVED_SEQUENCER_STRESS="0",FM1_WRITE_LLVM_PROFILE="0")
            diagnostic_spec=spec.with_name(f"Diagnostics-{args.run_label}.xctestrun")
            diagnostic_spec.write_bytes(plistlib.dumps(value))
            diagnostic_status=command(["xcodebuild","test-without-building","-xctestrun",str(diagnostic_spec),
                "-destination",f"platform=iOS Simulator,id={args.simulator_id}","-resultBundlePath",str(folder / f"{args.run_label}-diagnostics.xcresult"),
                "-parallel-testing-enabled","NO","-collect-test-diagnostics","never","-only-testing:FM1Tests/AudioMetricsTests",
                "-only-testing:FM1Tests/AudioRingTests","-only-testing:FM1Tests/AudioStressWindowTests",
                "-only-testing:FM1Tests/FM1Tests","-only-testing:FM1Tests/FirmwareSelectionTests",
                "-only-testing:FM1Tests/PanelGeometryTests"],reports / "diagnostics.log",check=False)
            summary["diagnosticsTestsExitCode"]=diagnostic_status
            (reports / "summary.json").write_text(json.dumps(summary,indent=2)+"\n")
            status=status or diagnostic_status
        return status
    finally:
        resolution_error=None
        if directory:
            try:
                directory=current_container(args.simulator_id) / "Documents/Firmwares"
                if profile_directory:
                    profile_directory=directory.parent / "PGO"
            except (OSError,RuntimeError,ValueError) as error:
                resolution_error=error
        command(["xcrun", "simctl", "terminate", args.simulator_id, BUNDLE], check=False)
        command(["xcrun", "simctl", "shutdown", args.simulator_id], check=False)
        final = json.loads(command(["xcrun", "simctl", "list", "devices", "available", "--json"]))
        stopped = any(d["udid"] == args.simulator_id and d["state"] == "Shutdown" for group in final["devices"].values() for d in group)
        if not stopped:
            raise RuntimeError("Simulator did not stop; previous-state backup retained for recovery")
        if resolution_error:
            raise RuntimeError(f"Unable to locate the current simulator app container; backup retained: {resolution_error}")
        if directory and (backup / "targets.json").exists():
            restore_previous(directory, backup)
        if full_backup:
            restore_app_state(directory.parent.parent, full_backup)
            (reports / "app-state-restored.json").write_text(json.dumps({"documentsAndPreferencesRestored":True,"verifiedFileBytes":True}) + "\n")
        if profile_directory:
            if profile_directory.exists():
                shutil.rmtree(profile_directory)
            if (reports / "previous-pgo-profiles").exists():
                shutil.copytree(reports / "previous-pgo-profiles",profile_directory)
        print("Dedicated simulator stopped; previous simulator firmware/save files restored.", flush=True)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(f"Benchmark error: {error}", file=sys.stderr)
        sys.exit(1)
