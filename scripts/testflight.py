#!/usr/bin/env python3
"""Upload a verified FM1 archive using a private App Store Connect API key."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import uuid


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = Path.home() / "Library/Application Support/FM1Release/appstore-connect.json"
DEFAULT_OPTIONS = Path.home() / "Library/Application Support/FM1Release/UploadOptions.internal.plist"
DEFAULT_STORE_OPTIONS = Path.home() / "Library/Application Support/FM1Release/UploadOptions.app-store.plist"
BUNDLE_ID = "com.local.fm1.instrument"


class ReleaseError(Exception):
    pass


def private_file(path, label):
    try:
        resolved = path.expanduser().resolve(strict=True)
        info = resolved.stat()
    except OSError:
        raise ReleaseError(f"{label} is missing or inaccessible.") from None
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        raise ReleaseError(f"{label} must be a regular file owned by the current user.")
    if info.st_mode & 0o077:
        raise ReleaseError(f"{label} must have owner-only permissions (chmod 600).")
    if resolved.is_relative_to(ROOT):
        raise ReleaseError(f"{label} must remain outside the repository.")
    return resolved


def load_config(path):
    path = private_file(path, "API configuration")
    try:
        config = json.loads(path.read_text())
    except (OSError, ValueError, UnicodeError):
        raise ReleaseError("API configuration is not readable JSON.") from None
    required = {"key_path", "key_id", "issuer_id", "team_id"}
    if not isinstance(config, dict) or set(config) != required:
        raise ReleaseError("API configuration needs exactly key_path, key_id, issuer_id and team_id.")
    if any(not isinstance(config[key], str) or not config[key] for key in required):
        raise ReleaseError("API configuration fields must be nonempty strings.")
    if any(not re.fullmatch(r"[A-Z0-9]{10}", config[key]) for key in ["key_id", "team_id"]):
        raise ReleaseError("API configuration has an invalid key or team identifier.")
    try:
        if str(uuid.UUID(config["issuer_id"])) != config["issuer_id"].lower():
            raise ValueError
    except ValueError:
        raise ReleaseError("API configuration has an invalid issuer identifier.") from None
    key = Path(config["key_path"]).expanduser()
    if not key.is_absolute():
        raise ReleaseError("API key path must be absolute.")
    # Verify metadata only. The helper never reads the private key's contents.
    config["key_path"] = str(private_file(key, "API key"))
    return config


def read_plist(path, label):
    try:
        result = plistlib.loads(path.read_bytes())
        if not isinstance(result, dict):
            raise ValueError
        return result
    except (OSError, ValueError, plistlib.InvalidFileException):
        raise ReleaseError(f"{label} is missing or invalid.") from None


def validate_archive(archive, config):
    archive = archive.expanduser().resolve()
    if archive.suffix != ".xcarchive" or not archive.is_dir():
        raise ReleaseError("Choose an existing .xcarchive directory.")
    info = read_plist(archive / "Info.plist", "Archive metadata")
    props = info.get("ApplicationProperties", {})
    if not isinstance(props, dict) or props.get("Team") != config["team_id"]:
        raise ReleaseError("Archive signing team does not match the configured team.")
    expected = read_plist(ROOT / "App/Info.plist", "Current app version")
    for field in ["CFBundleShortVersionString", "CFBundleVersion"]:
        if not expected.get(field) or props.get(field) != expected[field]:
            raise ReleaseError("Archive version/build does not match the current app sources.")
    if props.get("CFBundleIdentifier") != BUNDLE_ID:
        raise ReleaseError("Archive bundle identifier does not match FM1.")
    relative = props.get("ApplicationPath")
    if not isinstance(relative, str):
        raise ReleaseError("Archive has no application path.")
    app = (archive / "Products" / relative).resolve()
    if not app.is_relative_to(archive / "Products") or app.suffix != ".app":
        raise ReleaseError("Archive application path is invalid.")
    app_info = read_plist(app / "Info.plist", "Archived application metadata")
    for field in ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"]:
        if app_info.get(field) != props[field]:
            raise ReleaseError("Archived application identity differs from archive metadata.")
    if app_info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ReleaseError("Archive must contain an iOS device application.")
    return archive


def validate_options(path, config, distribution="internal"):
    if distribution not in {"internal", "app-store"}:
        raise ReleaseError("Choose internal or app-store distribution explicitly.")
    path = path.expanduser().resolve()
    options = read_plist(path, "Upload options")
    expected = {"method": "app-store-connect", "destination": "upload",
                "teamID": config["team_id"],
                "manageAppVersionAndBuildNumber": False}
    for key, value in expected.items():
        if type(options.get(key)) is not type(value) or options[key] != value:
            raise ReleaseError("Upload options must use App Store Connect upload, the configured team and fixed build numbering.")
    internal_only = options.get("testFlightInternalTestingOnly")
    if distribution == "internal":
        if internal_only is not True:
            raise ReleaseError("Internal upload options must enable internal-only testing.")
    elif "testFlightInternalTestingOnly" in options and internal_only is not False:
        raise ReleaseError("App Store upload options must omit or disable internal-only testing.")
    return path


def upload_command(config, archive, export_path, options):
    return ["xcodebuild", "-exportArchive", "-archivePath", str(archive),
            "-exportPath", str(export_path), "-exportOptionsPlist", str(options),
            "-authenticationKeyPath", config["key_path"],
            "-authenticationKeyID", config["key_id"],
            "-authenticationKeyIssuerID", config["issuer_id"],
            "-allowProvisioningUpdates"]


def redact(text, config):
    # Xcode can echo authentication arguments and team metadata in diagnostics.
    for value in sorted(config.values(), key=len, reverse=True):
        text = re.sub(re.escape(value), "<redacted>", text, flags=re.IGNORECASE)
    return text


def upload(config, archive, export_path, log, options, distribution="internal"):
    archive = validate_archive(archive, config)
    options = validate_options(options, config, distribution)
    export_path = export_path.expanduser().resolve()
    log = log.expanduser().resolve()
    if log.is_relative_to(archive) or export_path.is_relative_to(archive):
        raise ReleaseError("Export and log destinations must be outside the archive.")
    if log == Path(config["key_path"]) or export_path == Path(config["key_path"]):
        raise ReleaseError("Output destinations cannot replace the API key.")
    # An exclusive log avoids clobbering an earlier upload receipt or a private file.
    log.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except OSError:
        raise ReleaseError("Upload log must be a new writable file.") from None
    with os.fdopen(descriptor, "w") as output:
        scope = "internal TestFlight" if distribution == "internal" else "App Store-eligible distribution"
        print(f"Uploading for {scope} with the configured API key; authentication metadata is redacted.", flush=True)
        try:
            result = subprocess.run(upload_command(config, archive, export_path, options),
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, errors="replace", check=False)
        except OSError:
            output.write("Could not launch xcodebuild.\n")
            raise ReleaseError("Could not launch xcodebuild.") from None
        output.write(redact(result.stdout or "", config))
    if result.returncode:
        raise ReleaseError("Upload failed. Inspect the private redacted log; no account authentication fallback was attempted.")
    print("Upload command completed. Apple processing and distribution availability still need verification.")
    if distribution == "app-store":
        print("This command does not submit App Review or publish the app.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    commands = parser.add_subparsers(dest="action", required=True)
    commands.add_parser("validate-config", help="Check configuration/key metadata without reading the private key")
    send = commands.add_parser("upload", help="Export and upload an existing archive (internal TestFlight by default)")
    send.add_argument("--archive", type=Path, required=True)
    send.add_argument("--export-path", type=Path, required=True)
    send.add_argument("--log", type=Path, required=True)
    send.add_argument("--distribution", choices=["internal", "app-store"], default="internal",
                      help="App Store-eligible upload requires explicit app-store selection; no review submission")
    send.add_argument("--upload-options", type=Path)
    args = parser.parse_args(argv)
    try:
        config = load_config(args.config)
        if args.action == "validate-config":
            print(json.dumps({"valid": True, "authentication": "App Store Connect API key",
                              "key_id": "<redacted>", "issuer_id": "<redacted>",
                              "team_id": "<redacted>", "key_path": "<redacted>"}))
        else:
            options = args.upload_options or (DEFAULT_STORE_OPTIONS if args.distribution == "app-store" else DEFAULT_OPTIONS)
            upload(config, args.archive, args.export_path, args.log, options, distribution=args.distribution)
        return 0
    except ReleaseError as error:
        # ReleaseError strings never interpolate credentials or supplied paths.
        print(str(error), file=sys.stderr)
        return 1
    except OSError:
        print("Local release filesystem operation failed.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
