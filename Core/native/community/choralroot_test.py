#!/usr/bin/env python3
"""Host semantic regression for the exact ChoralRoot adapter and portable source.

Both libraries contain native machine code. The optional reference is the
upstream serial headless C translation unit, not a WASM runtime.
"""
import argparse
import ctypes as C
from pathlib import Path
import re
import tempfile
import os
import unittest
import hashlib,json,subprocess,sys

FLASH = 1 << 20
ARGS = None
LIB = None


class Instance:
    def __init__(self, flash=None):
        self.owner = C.create_string_buffer(LIB.chr_state_size() + 15)
        self.address = (C.addressof(self.owner) + 15) & ~15
        assert LIB.chr_state_init(self.address) == 1
        self.bind()
        if flash is not None:
            assert len(flash) == FLASH
            data = (C.c_uint8 * FLASH).from_buffer_copy(flash)
            LIB.chr_flash_load(data)
        LIB.chr_init()

    def bind(self):
        LIB.chr_bind(self.address)

    def render(self, frames=128):
        self.bind()
        out = (C.c_int32 * (frames * 2))()
        LIB.chr_render(out, frames)
        return bytes(out)

    def advance(self, seconds):
        for _ in range(round(seconds * 44100 / 128)):
            self.render()

    def key(self, key, down):
        self.bind(); LIB.chr_physical_key(key, int(down))

    def encoder(self, knob, delta):
        self.bind(); LIB.chr_physical_encoder(knob, delta)

    def release(self):
        self.bind(); LIB.chr_release_all()

    def lcd(self):
        self.bind()
        out = (C.c_uint16 * (240 * 240))()
        LIB.chr_draw(out)
        return bytes(out)

    def flash(self):
        self.bind()
        out = (C.c_uint8 * FLASH)()
        LIB.chr_flash_copy(out)
        return bytes(out)

    def metrics(self):
        self.bind()
        out = (C.c_uint64 * 16)()
        assert LIB.chr_workload_metrics(out, 16) == 16
        return tuple(out)

    def dump(self):
        self.bind()
        libc = C.CDLL(None)
        libc.fflush(None)
        with tempfile.TemporaryFile() as f:
            saved = os.dup(1)
            try:
                os.dup2(f.fileno(), 1)
                LIB.chr_emu_fw_dump()
                libc.fflush(None)
            finally:
                os.dup2(saved, 1); os.close(saved)
            f.seek(0)
            return f.read().decode(errors='replace')


class ChoralRootTests(unittest.TestCase):
    def test_boot_lcd_note_and_release(self):
        a = Instance()
        a.advance(.15)
        self.assertGreater(len(set(a.lcd())), 4)
        a.key(21, True)
        data = (C.c_int32 * 88200).from_buffer_copy(a.render(44100))
        self.assertGreater(max(map(abs, data)), 100)
        self.assertIn('sounding 1', a.dump())
        a.release(); a.advance(3)
        self.assertIn('sounding 0', a.dump())
        self.assertGreater(a.metrics()[0], 44100)

    def test_observations_do_not_advance_clock(self):
        a = Instance(); a.advance(.1)
        before = a.metrics()
        image = a.lcd()
        for _ in range(5):
            self.assertEqual(a.lcd(), image)
            a.flash()
        self.assertEqual(a.metrics(), before)

    def test_independent_instances_pcm_lcd_and_flash(self):
        a, b, unrelated = Instance(), Instance(), Instance()
        for inst in (a, b):
            inst.advance(.2)
            inst.key(21, True)
        for i in range(120):
            pa = a.render()
            unrelated.key(14 + i % 27, True)
            unrelated.encoder(1, 1)
            unrelated.render()
            unrelated.release()
            self.assertEqual(pa, b.render())
        self.assertGreater(sum(v!=0 for v in (C.c_int32*256).from_buffer_copy(pa)),100)
        self.assertEqual(a.lcd(), b.lcd())
        self.assertEqual(a.flash(), b.flash())
        self.assertNotEqual(a.lcd(), unrelated.lcd())

    def test_physical_controls_and_original_settings_roundtrip(self):
        a = Instance(); a.advance(.15)
        # Measured physical matrix: 1=OCT+, 8=HOME; encoder6=PRESETS.
        a.key(1, True); a.advance(.03); a.key(1, False)
        a.encoder(6, 1); a.advance(1.5)
        changed = a.dump()
        self.assertIn('octave 1', changed)
        self.assertIn('part 0:', changed)
        # v0.27 deliberately requires holding SAVE for manual sound/octave settings.
        a.advance(2); a.key(9,True); a.advance(1.5); a.key(9,False); a.advance(.1)
        raw = a.flash()
        self.assertTrue(any(v!=255 for v in raw), "Hold SAVE must persist settings")
        self.assertGreater(a.metrics()[3], 0)
        b = Instance(raw)
        self.assertTrue(b.flash()==raw, 'Power-on must not rewrite the retained NOR image')
        restored = b.dump()
        self.assertIn('(record: current)', restored)
        self.assertIn('octave 1', restored)
        sound = re.search(r'  part 0: (.*?), voices', changed).group(1)
        self.assertIn('  part 0: ' + sound, restored)
        image=a.lcd()
        a.key(2, True); a.advance(.03); a.key(2, False); a.advance(.03)
        self.assertNotEqual(a.lcd(),image)

    def test_major_chord_runs_multiple_actual_dsp_voices(self):
        a=Instance();a.advance(.2);a.key(19,True);a.advance(.02);a.key(23,True)
        data=(C.c_int32*22050).from_buffer_copy(a.render(11025))
        self.assertGreater(max(map(abs,data)),100)
        self.assertGreaterEqual(a.metrics()[1],3)
        self.assertGreater(a.metrics()[4],100)

    def test_init_only_cz_p5_sound_and_private_user_tones_reopen(self):
        a=Instance();a.advance(.2)
        self.assertEqual(LIB.chr_test_init_counts(),1)
        saved=[]
        for engine in (0,1):
            a.bind();self.assertEqual(LIB.chr_test_sound(engine),1)
            a.advance(.03);a.key(23,True)
            data=(C.c_int32*22050).from_buffer_copy(a.render(11025))
            self.assertGreater(max(map(abs,data)),100,engine)
            a.release();a.advance(.1)
            a.bind();initial=(C.c_uint8*1024)();initial_n=LIB.chr_test_user_bytes(engine,initial)
            a.bind();self.assertEqual(LIB.chr_test_user_store(engine),1)
            raw=(C.c_uint8*1024)();n=LIB.chr_test_user_bytes(engine,raw)
            self.assertEqual(n,144 if engine==0 else 138)
            self.assertNotEqual(bytes(raw[:n]),bytes(initial[:initial_n]),'Private edit must differ from INIT')
            saved.append(bytes(raw[:n]))
        a.advance(.2);flash=a.flash();b=Instance(flash);b.advance(.2)
        # A genuinely new process cannot retain any hidden RAM from the writer.
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp);(path/'private.flash').write_bytes(flash)
            expected=[hashlib.sha256(data).hexdigest() for data in saved]
            subprocess.run([sys.executable,__file__,'--library',str(ARGS.library.resolve()),
                '--reopen',str(path/'private.flash'),'--expected',json.dumps(expected)],check=True)
        for engine in (0,1):
            b.bind();self.assertEqual(LIB.chr_test_user_load(engine),1)
            raw=(C.c_uint8*1024)();n=LIB.chr_test_user_bytes(engine,raw)
            self.assertEqual(bytes(raw[:n]),saved[engine],engine)

    def test_pcm_lcd_and_nor_equal_upstream_serial_portable_host(self):
        if not ARGS.reference:
            self.skipTest('Pass --reference for exact portable-source parity')
        ref = C.CDLL(str(ARGS.reference.resolve()))
        ref.web_out_l.restype = C.POINTER(C.c_float)
        ref.web_out_r.restype = C.POINTER(C.c_float)
        ref.web_fb.restype = C.POINTER(C.c_uint16)
        ref.web_flash.restype = C.POINTER(C.c_uint8)
        ref.web_boot()
        a = Instance()
        nonzero=0
        for block in range(300):
            if block in (20, 90):
                a.key(21, True); ref.web_keys(128)
            if block in (70, 150):
                a.release(); ref.web_keys(0); ref.web_buttons(0)
            if block == 90:
                a.key(22, True); ref.web_keys(384)
            if block == 180:
                a.key(2, True); ref.web_buttons(1)  # FX label -> matrix2
            if block == 195:
                a.key(2, False); ref.web_buttons(0)
            if block == 210:
                a.encoder(0, 1); ref.web_enc(0, 1)
            actual = (C.c_int32 * 256).from_buffer_copy(a.render())
            nonzero+=sum(v!=0 for v in actual)
            ref.web_render(128)
            left, right = ref.web_out_l(), ref.web_out_r()
            for i in range(128):
                self.assertEqual(actual[2*i], round(left[i] * 65536), (block, i, 'L'))
                self.assertEqual(actual[2*i+1], round(right[i] * 65536), (block, i, 'R'))
            self.assertEqual(a.lcd(), C.string_at(ref.web_fb(), 240 * 240 * 2), block)
        self.assertGreater(nonzero,100, "PCM parity must exercise audible root notes")
        self.assertEqual(a.flash(), C.string_at(ref.web_flash(), FLASH))


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--library', type=Path, required=True)
    p.add_argument('--reference', type=Path)
    p.add_argument('--reopen',type=Path)
    p.add_argument('--expected')
    ARGS, rest = p.parse_known_args()
    LIB = C.CDLL(str(ARGS.library.resolve()))
    LIB.chr_state_size.restype = C.c_uint64
    LIB.chr_state_init.argtypes = [C.c_void_p]
    LIB.chr_bind.argtypes = [C.c_void_p]
    if ARGS.reopen:
        inst=Instance(ARGS.reopen.read_bytes());inst.advance(.2)
        expected=json.loads(ARGS.expected)
        for engine in (0,1):
            inst.bind();assert LIB.chr_test_user_load(engine)==1
            raw=(C.c_uint8*1024)();n=LIB.chr_test_user_bytes(engine,raw)
            assert hashlib.sha256(bytes(raw[:n])).hexdigest()==expected[engine]
        print('Fresh-process private CZ/P5 tone reopen passed')
    else:unittest.main(argv=[__file__] + rest)
