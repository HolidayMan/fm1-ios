import importlib.util
import plistlib
import tempfile
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('store_audit', ROOT / 'scripts/audit_store_artifact.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class StoreArtifactBoundaryTests(unittest.TestCase):
    def test_native_bundle_and_required_reason_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            (app / 'PrivacyInfo.xcprivacy').write_bytes((ROOT / 'App/PrivacyInfo.xcprivacy').read_bytes())
            self.assertEqual(audit.audit_resources(app), [])
            self.assertEqual(audit.audit_binary('_instrument_research_enabled\n_instrument_create', '/System/Library/Frameworks/AVFAudio.framework/AVFAudio',audit.NATIVE_POLICY), [])

    def test_stripped_native_binary_uses_signed_policy_section(self):
        self.assertEqual(audit.audit_binary('', '', audit.NATIVE_POLICY), [])
        self.assertTrue(audit.audit_binary('', '', b'FM1_BUILD_POLICY_V1:RESEARCH\0'))
        self.assertTrue(audit.audit_binary('_instrument_research_enabled', '', None))

    def test_policy_reader_checks_signed_section_and_bounds(self):
        payload=audit.NATIVE_POLICY
        header=struct.pack('<8I',0xfeedfacf,0x100000c,0,2,1,152,0,0)
        segment=struct.pack('<II16sQQQQiiII',0x19,152,b'__TEXT',0,4096,0,4096,5,5,1,0)
        def image(start):
            section=struct.pack('<16s16sQQ8I',b'__fm1_policy',b'__TEXT',0,len(payload),start,0,0,0,0,0,0,0)
            return header+segment+section+payload
        with tempfile.TemporaryDirectory() as temporary:
            executable=Path(temporary)/'PocketFM'
            executable.write_bytes(image(184))
            self.assertEqual(audit.read_build_policy(executable),payload)
            executable.write_bytes(image(4096))
            with self.assertRaisesRegex(ValueError,'bounds'):
                audit.read_build_policy(executable)

    def test_nested_executable_assets_and_packages_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            (app / 'PrivacyInfo.xcprivacy').write_bytes((ROOT / 'App/PrivacyInfo.xcprivacy').read_bytes())
            for filename in ['engine.wasm', 'engine-worker.js', 'index.html', 'download.fwsc']:
                resource = app / 'Resources' / filename
                resource.parent.mkdir(exist_ok=True)
                resource.write_bytes(b'')
            self.assertEqual(len(audit.audit_resources(app)), 4)

    def test_research_symbols_and_frameworks_are_rejected_independently(self):
        for symbol in ['WebInstrumentEngine', 'WebEngineOrigin', 'WebEngineHosting', 'fm1_core', 'fm1_soc', 'fm1_isa', 'Interpreter']:
            self.assertTrue(audit.audit_binary('_instrument_research_enabled ' + symbol, '', audit.NATIVE_POLICY))
        self.assertTrue(audit.audit_binary('_instrument_research_enabled', '/System/Library/Frameworks/WebKit.framework/WebKit', audit.NATIVE_POLICY))
        self.assertTrue(audit.audit_binary('', ''))
        self.assertTrue(audit.audit_binary('', '/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore', audit.NATIVE_POLICY))

    def test_absent_or_incomplete_privacy_manifest_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            self.assertTrue(audit.audit_resources(app))
            (app / 'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps({}))
            self.assertTrue(audit.audit_resources(app))


if __name__ == '__main__':
    unittest.main()
