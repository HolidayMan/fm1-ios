"""Synthetic archive/config checks. No real key, account, network or upload."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("testflight", Path(__file__).resolve().parents[1] / "scripts/testflight.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class TestFlightUploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        key = self.root / "AuthKey_SYNTHETIC1.p8"
        key.write_text("synthetic fixture: never a real private key")
        key.chmod(0o600)
        self.config = {"key_path": str(key), "key_id": "SYNTHETIC1",
                       "issuer_id": "12345678-1234-1234-1234-123456789abc", "team_id": "TESTTEAM01"}
        self.config_path = self.root / "appstore-connect.json"
        self.config_path.write_text(json.dumps(self.config))
        self.config_path.chmod(0o600)
        self.archive = self.root / "FM1.xcarchive"
        app = self.archive / "Products/Applications/FM1.app"
        app.mkdir(parents=True)
        current = plistlib.loads((helper.ROOT / "App/Info.plist").read_bytes())
        self.props = {"ApplicationPath": "Applications/FM1.app", "Team": self.config["team_id"],
                      "CFBundleIdentifier": helper.BUNDLE_ID,
                      "CFBundleShortVersionString": current["CFBundleShortVersionString"],
                      "CFBundleVersion": current["CFBundleVersion"]}
        (self.archive / "Info.plist").write_bytes(plistlib.dumps({"ApplicationProperties": self.props}))
        app_info = dict(self.props, CFBundleSupportedPlatforms=["iPhoneOS"])
        (app / "Info.plist").write_bytes(plistlib.dumps(app_info))
        self.options = self.root / "UploadOptions.internal.plist"
        self.options.write_bytes(plistlib.dumps({"method": "app-store-connect", "destination": "upload",
                                 "teamID": self.config["team_id"], "testFlightInternalTestingOnly": True,
                                 "manageAppVersionAndBuildNumber": False}))

    def test_upload_uses_explicit_key_authentication_and_redacts_log(self):
        config = helper.load_config(self.config_path)
        log = self.root / "upload.log"
        diagnostic = "\n".join(config.values()) + "\n" + config["issuer_id"].upper()
        with mock.patch.object(helper.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, diagnostic)) as run:
            with contextlib.redirect_stdout(io.StringIO()):
                helper.upload(config, self.archive, self.root / "export", log, self.options)
        args = run.call_args.args[0]
        self.assertEqual(args[0:2], ["xcodebuild", "-exportArchive"])
        for flag, field in [("-authenticationKeyPath", "key_path"), ("-authenticationKeyID", "key_id"),
                            ("-authenticationKeyIssuerID", "issuer_id")]:
            self.assertEqual(args[args.index(flag)+1], config[field])
        self.assertIn("-allowProvisioningUpdates", args)
        self.assertEqual(args[args.index("-exportOptionsPlist")+1], str(self.options.resolve()))
        self.assertEqual(log.stat().st_mode & 0o777, 0o600)
        self.assertTrue(all(value.lower() not in log.read_text().lower() for value in config.values()))

    def test_validation_does_not_read_key_contents_or_expose_metadata(self):
        original_text, original_bytes = Path.read_text, Path.read_bytes
        def text(path, *args, **kwargs):
            self.assertNotEqual(path.resolve(), Path(self.config["key_path"]).resolve())
            return original_text(path, *args, **kwargs)
        def binary(path, *args, **kwargs):
            self.assertNotEqual(path.resolve(), Path(self.config["key_path"]).resolve())
            return original_bytes(path, *args, **kwargs)
        output = io.StringIO()
        with mock.patch.object(Path, "read_text", text), mock.patch.object(Path, "read_bytes", binary), contextlib.redirect_stdout(output):
            self.assertEqual(helper.main(["--config", str(self.config_path), "validate-config"]), 0)
        self.assertTrue(all(value not in output.getvalue() for value in self.config.values()))

    def test_missing_key_and_insecure_modes_fail_before_subprocess(self):
        with mock.patch.object(helper.subprocess, "run") as run:
            for path in [self.config_path, Path(self.config["key_path"])]:
                path.chmod(0o644)
                with self.assertRaises(helper.ReleaseError):
                    helper.load_config(self.config_path)
                path.chmod(0o600)
            Path(self.config["key_path"]).unlink()
            with self.assertRaises(helper.ReleaseError):
                helper.load_config(self.config_path)
            run.assert_not_called()

    def test_missing_config_has_no_account_fallback(self):
        with mock.patch.object(helper.subprocess, "run") as run, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(helper.main(["--config", str(self.root / "missing.json"), "upload",
                                        "--archive", str(self.archive), "--export-path", str(self.root / "export"),
                                        "--log", str(self.root / "upload.log")]), 1)
            run.assert_not_called()

    def test_cli_defaults_to_private_manual_upload_options(self):
        expected = Path.home() / "Library/Application Support/FM1Release/UploadOptions.internal.plist"
        with mock.patch.object(helper, "load_config", return_value=self.config), mock.patch.object(helper, "upload") as upload:
            self.assertEqual(helper.main(["upload", "--archive", str(self.archive),
                                         "--export-path", str(self.root / "export"),
                                         "--log", str(self.root / "upload.log")]), 0)
        self.assertEqual(upload.call_args.args[-1], expected)
        self.assertEqual(upload.call_args.kwargs["distribution"], "internal")

    def test_cli_app_store_mode_selects_separate_private_options(self):
        expected = Path.home() / "Library/Application Support/FM1Release/UploadOptions.app-store.plist"
        for explicit_options in [False, True]:
            with self.subTest(explicit_options=explicit_options):
                args = ["upload", "--distribution", "app-store", "--archive", str(self.archive),
                        "--export-path", str(self.root / "export"), "--log", str(self.root / "upload.log")]
                if explicit_options:
                    args += ["--upload-options", str(self.options)]
                with mock.patch.object(helper, "load_config", return_value=self.config), mock.patch.object(helper, "upload") as upload:
                    self.assertEqual(helper.main(args), 0)
                self.assertEqual(upload.call_args.args[-1], self.options if explicit_options else expected)
                self.assertEqual(upload.call_args.kwargs["distribution"], "app-store")

    def test_wrong_archive_bundle_team_and_build_are_rejected(self):
        for key in ["CFBundleIdentifier", "Team", "CFBundleShortVersionString", "CFBundleVersion"]:
            with self.subTest(key=key):
                changed = dict(self.props)
                changed[key] = "wrong"
                (self.archive / "Info.plist").write_bytes(plistlib.dumps({"ApplicationProperties": changed}))
                with self.assertRaises(helper.ReleaseError):
                    helper.validate_archive(self.archive, self.config)

    def test_options_cannot_enable_external_distribution_or_renumbering(self):
        options = plistlib.loads(self.options.read_bytes())
        for key, value in [("destination", "export"), ("testFlightInternalTestingOnly", False),
                           ("manageAppVersionAndBuildNumber", True), ("teamID", "WRONGTEAM1")]:
            with self.subTest(key=key):
                self.options.write_bytes(plistlib.dumps(dict(options, **{key: value})))
                with self.assertRaises(helper.ReleaseError):
                    helper.validate_options(self.options, self.config)

    def test_app_store_options_need_explicit_mode_and_boolean_false_or_omission(self):
        base = plistlib.loads(self.options.read_bytes())
        for present, value in [(True, False), (False, None), (True, True),
                               (True, 0), (True, 1), (True, "false")]:
            with self.subTest(present=present, value=value):
                options = dict(base)
                if present:
                    options["testFlightInternalTestingOnly"] = value
                else:
                    del options["testFlightInternalTestingOnly"]
                self.options.write_bytes(plistlib.dumps(options))
                if present and value is True:
                    self.assertEqual(helper.validate_options(self.options, self.config), self.options.resolve())
                else:
                    with self.assertRaises(helper.ReleaseError):
                        helper.validate_options(self.options, self.config)
                if not present or value is False:
                    self.assertEqual(helper.validate_options(self.options, self.config, "app-store"), self.options.resolve())
                else:
                    with self.assertRaises(helper.ReleaseError):
                        helper.validate_options(self.options, self.config, "app-store")

    def test_app_store_options_keep_identity_numbering_and_upload_checks(self):
        base = plistlib.loads(self.options.read_bytes())
        base["testFlightInternalTestingOnly"] = False
        for key, value in [("destination", "export"), ("method", "development"),
                           ("manageAppVersionAndBuildNumber", True),
                           ("manageAppVersionAndBuildNumber", 0), ("teamID", "WRONGTEAM1")]:
            with self.subTest(key=key, value=value):
                self.options.write_bytes(plistlib.dumps(dict(base, **{key: value})))
                with self.assertRaises(helper.ReleaseError):
                    helper.validate_options(self.options, self.config, "app-store")

    def test_app_store_upload_preserves_manual_options_and_redacts_without_review(self):
        options = plistlib.loads(self.options.read_bytes())
        options.update(testFlightInternalTestingOnly=False, signingStyle="manual",
                       signingCertificate="Apple Distribution",
                       provisioningProfiles={helper.BUNDLE_ID: "Synthetic manual profile"})
        self.options.write_bytes(plistlib.dumps(options))
        original = self.options.read_bytes()
        log = self.root / "store-upload.log"
        output = io.StringIO()
        diagnostic = "\n".join(self.config.values())
        with mock.patch.object(helper.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, diagnostic)) as run:
            with contextlib.redirect_stdout(output):
                helper.upload(self.config, self.archive, self.root / "export", log, self.options, distribution="app-store")
        run.assert_called_once()
        self.assertEqual(self.options.read_bytes(), original)
        args = run.call_args.args[0]
        self.assertEqual(args[args.index("-exportOptionsPlist") + 1], str(self.options.resolve()))
        self.assertIn("does not submit App Review", output.getvalue())
        self.assertEqual(log.stat().st_mode & 0o777, 0o600)
        self.assertTrue(all(value.lower() not in log.read_text().lower() for value in self.config.values()))

    def test_invalid_distribution_and_store_options_fail_before_upload(self):
        options = plistlib.loads(self.options.read_bytes())
        options["testFlightInternalTestingOnly"] = False
        self.options.write_bytes(plistlib.dumps(options))
        for distribution in ["internal", "unknown"]:
            with self.subTest(distribution=distribution), mock.patch.object(helper.subprocess, "run") as run:
                log = self.root / "not-created.log"
                with self.assertRaises(helper.ReleaseError):
                    helper.upload(self.config, self.archive, self.root / "export", log, self.options, distribution=distribution)
                run.assert_not_called()
                self.assertFalse(log.exists())

    def test_failed_upload_is_not_retried_or_fallen_back(self):
        log = self.root / "failed.log"
        with mock.patch.object(helper.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, self.config["key_id"])) as run:
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(helper.ReleaseError):
                helper.upload(self.config, self.archive, self.root / "export", log, self.options)
        self.assertEqual(run.call_count, 1)
        self.assertNotIn(self.config["key_id"], log.read_text())


if __name__ == "__main__":
    unittest.main()
