import hashlib
import importlib.util
import json
import re
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('init_bank',ROOT/'Core/native/melodee_init_bank.py')
policy=importlib.util.module_from_spec(spec);spec.loader.exec_module(policy)
LOCK=next(x for x in json.loads((ROOT/'Core/native/family.lock.json').read_text())['firmwares'] if x['id']=='melodee')
SOURCE=ROOT/'Research/NativeFamilyOct22/melodee/firmware/src'

@unittest.skipUnless(SOURCE.exists(),'Pinned private prepared source required')
class MelodeeInitBankTests(unittest.TestCase):
    def stage(self,directory):
        base=Path(directory)/'upstream/firmware/src';base.mkdir(parents=True)
        for name in LOCK['derived_soundset']['upstream_files_sha256']:
            shutil.copy2(SOURCE/name,base/name)
        return base
    def test_derivation_does_not_compile_factory_data_and_retains_upstream(self):
        with tempfile.TemporaryDirectory() as directory:
            base=self.stage(directory);resources=Path(directory)/'resources'
            got=policy.derive(base.parents[1],resources,LOCK)
            self.assertEqual(got,LOCK['derived_soundset']['derived_files_sha256'])
            text=re.sub(r'/\*.*?\*/','', '\n'.join(path.read_text() for path in base.iterdir()),flags=re.S)
            for forbidden in ['#include "melodee_cz1.h"','#include "melodee_prophet_factory.h"','CZ_DICT','CZ_LZ','CZ_SHORT','P5_FPACK','P5_FBASE','P5_FWIDTH']:
                self.assertNotIn(forbidden,text)
            self.assertEqual([path.name for path in resources.iterdir()],['melodee_init_bank.h'])
            for name,want in LOCK['derived_soundset']['upstream_files_sha256'].items():
                self.assertEqual(hashlib.sha256((SOURCE/name).read_bytes()).hexdigest(),want)
    def test_compiled_object_gate_rejects_embedded_factory_payload(self):
        payload=bytes(range(144))
        expected={'bytes':len(payload),'prefix_sha256':hashlib.sha256(payload[:32]).hexdigest(),'sha256':hashlib.sha256(payload).hexdigest()}
        descriptor={'derived_soundset':{'excluded_payload_fingerprints':{'CZ_DICT':expected}}}
        with tempfile.TemporaryDirectory() as directory:
            object_file=Path(directory)/'object.o';object_file.write_bytes(b'object-prefix'+payload+b'object-suffix')
            with self.assertRaisesRegex(ValueError,'factory resource in compiled object'):
                policy.audit_object(object_file,descriptor)
    def test_changed_input_fails_instead_of_silently_applying_old_patch(self):
        with tempfile.TemporaryDirectory() as directory:
            base=self.stage(directory);(base/'eng_cz.c').write_text('changed')
            with self.assertRaisesRegex(ValueError,'upstream input changed'):
                policy.derive(base.parents[1],Path(directory)/'resources',LOCK)
    def test_excluded_generated_header_cannot_enter_compiled_resource_root(self):
        with tempfile.TemporaryDirectory() as directory:
            base=self.stage(directory);resources=Path(directory)/'resources';resources.mkdir()
            (resources/'melodee_cz1.h').write_text('excluded')
            with self.assertRaisesRegex(ValueError,'Excluded Melodee factory data'):
                policy.derive(base.parents[1],resources,LOCK)

if __name__=='__main__':unittest.main()
