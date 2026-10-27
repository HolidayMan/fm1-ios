"""Fail-closed gates for the pinned ChoralRoot INIT derivation."""
import hashlib,importlib.util,json,sys,tempfile,unittest
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]/'Core/native/community'
sys.path.insert(0,str(HERE))
import choralroot_init_bank as policy

class ChoralRootINITPolicyTests(unittest.TestCase):
    def test_preparation_never_executes_factory_generators(self):
        d=json.loads((HERE/'choralroot.lock.json').read_text())
        self.assertFalse(any('gen_cz1_factory' in str(c) or 'gen_prophet_factory' in str(c) for c in d['generate_commands']))
        self.assertTrue(policy.EXCLUDED.isdisjoint(d['generated_headers_sha256']))
        self.assertEqual(d['kind'],17)
        self.assertEqual(d['source_subdir'],'upstream-choralroot')
        self.assertEqual(len(d['derived_soundset']['excluded_payload_fingerprints']),6)
        self.assertIn('#define FELUCCA_P5_FACTORY 0',(HERE/'choralroot.c').read_text())
    def test_factory_object_payload_rejected_without_original_assets(self):
        data=bytes(range(96));record={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'prefix_sha256':hashlib.sha256(data[:32]).hexdigest()}
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'output.o';p.write_bytes(b'safe'+data+b'tail')
            with self.assertRaises(ValueError):policy.audit_object(p,{'derived_soundset':{'excluded_payload_fingerprints':{'CZ_FACTORY_LZ4':record}}})
            p.write_bytes(b'original INIT-only code')
            policy.audit_object(p,{'derived_soundset':{'excluded_payload_fingerprints':{'CZ_FACTORY_LZ4':record}}})
    def test_derivation_rejects_changed_source_before_patching(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'firmware/src').mkdir(parents=True);p=root/'firmware/src/eng_cz.c';p.write_text('changed source')
            d={'derived_soundset':{'upstream_files_sha256':{'eng_cz.c':'0'*64}}}
            with self.assertRaisesRegex(ValueError,'source pin changed'):policy.derive(root,root/'res',root,d)
            self.assertEqual(p.read_text(),'changed source')
            self.assertFalse((root/'res').exists())
if __name__=='__main__':unittest.main()
