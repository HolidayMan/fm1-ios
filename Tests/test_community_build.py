"""Fail-closed source/resource validation for the opt-in community build pipeline."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

NATIVE=Path(__file__).resolve().parents[1]/'Core/native'
sys.path.insert(0,str(NATIVE/'community'))
spec=importlib.util.spec_from_file_location('community_build',NATIVE/'community/build.py')
build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)

class CommunityBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.source=Path(self.temp.name)
        for folder in ['tools','build/gen']:(self.source/folder).mkdir(parents=True)
        (self.source/'tools/gen.py').write_text('print("trusted")\n')
        (self.source/'LICENSE').write_text('fixture notice\n')
        (self.source/'build/gen/resource.h').write_text('/* deterministic resource */\n')
        def git(*args):return subprocess.check_output(['git','-C',str(self.source),*args],stderr=subprocess.DEVNULL,text=True).strip()
        git('init','-q');git('add','tools','LICENSE');git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','fixture')
        self.d={'id':'fixture','commit':git('rev-parse','HEAD'),'input_dirs':['tools'],'inputs':build.inputs(self.source,['tools']),
                'generated_headers_sha256':{'resource.h':hashlib.sha256((self.source/'build/gen/resource.h').read_bytes()).hexdigest()},
                'notices_sha256':{'LICENSE':hashlib.sha256((self.source/'LICENSE').read_bytes()).hexdigest()}}
    def test_valid_source_is_checked_before_generated_headers_exist(self):
        (self.source/'build/gen/resource.h').unlink()
        build.verify(self.source,self.d,generated=False)
        with self.assertRaises(SystemExit):build.verify(self.source,self.d)
    def test_tampered_generator_and_extra_source_rejected(self):
        (self.source/'tools/gen.py').write_text('raise RuntimeError("untrusted")\n')
        with self.assertRaises(subprocess.CalledProcessError):build.verify(self.source,self.d,generated=False)
        (self.source/'tools/gen.py').write_text('print("trusted")\n')
        (self.source/'tools/extra.c').write_text('int injected;\n')
        with self.assertRaises(SystemExit):build.verify(self.source,self.d,generated=False)
    def test_generated_header_tampering_rejected(self):
        (self.source/'build/gen/resource.h').write_text('/* altered */\n')
        with self.assertRaises(SystemExit):build.verify(self.source,self.d)
    def test_bytecode_is_never_a_reproducibility_input(self):
        (self.source/'tools/__pycache__').mkdir();(self.source/'tools/__pycache__/gen.cpython.pyc').write_bytes(b'nonportable')
        self.assertEqual(build.inputs(self.source,['tools']),self.d['inputs'])
    def test_curated_ids_fingerprints_and_abi_prefixes_are_unique(self):
        ds=json.loads((NATIVE/'community/community.lock.json').read_text())['firmwares']
        for key in ['id','kind','prefix']:
            self.assertEqual(len({d[key] for d in ds}),6)
        self.assertEqual({d['kind'] for d in ds},set(range(11,17)))
        self.assertEqual(len({d['package']['sha256'] for d in ds}),6)
        for d in ds:
            self.assertEqual(len(bytes.fromhex(d['package']['sha256'])),32)
            self.assertFalse(any('__pycache__' in p or p.endswith('.pyc') for p in d['inputs']))

if __name__=='__main__':unittest.main()
