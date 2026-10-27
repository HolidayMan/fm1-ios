#!/usr/bin/env python3
"""Host semantic regression for the exact CoralFlower adapter and portable source.

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

FLASH = 1 << 20
ARGS = None
LIB = None


class Instance:
    def __init__(self, flash=None):
        self.owner = C.create_string_buffer(LIB.cfl_state_size() + 15)
        self.address = (C.addressof(self.owner) + 15) & ~15
        assert LIB.cfl_state_init(self.address) == 1
        self.bind()
        if flash is not None:
            assert len(flash) == FLASH
            data = (C.c_uint8 * FLASH).from_buffer_copy(flash)
            LIB.cfl_flash_load(data)
        LIB.cfl_init()

    def bind(self):
        LIB.cfl_bind(self.address)

    def render(self, frames=128):
        self.bind()
        out = (C.c_int32 * (frames * 2))()
        LIB.cfl_render(out, frames)
        return bytes(out)

    def advance(self, seconds):
        for _ in range(round(seconds * 44100 / 128)):
            self.render()

    def key(self, key, down):
        self.bind(); LIB.cfl_physical_key(key, int(down))

    def encoder(self, knob, delta):
        self.bind(); LIB.cfl_physical_encoder(knob, delta)

    def release(self):
        self.bind(); LIB.cfl_release_all()

    def lcd(self):
        self.bind()
        out = (C.c_uint16 * (240 * 240))()
        LIB.cfl_draw(out)
        return bytes(out)

    def flash(self):
        self.bind()
        out = (C.c_uint8 * FLASH)()
        LIB.cfl_flash_copy(out)
        return bytes(out)

    def metrics(self):
        self.bind()
        out = (C.c_uint64 * 16)()
        assert LIB.cfl_workload_metrics(out, 16) == 16
        return tuple(out)

    def dump(self):
        self.bind()
        libc = C.CDLL(None)
        libc.fflush(None)
        with tempfile.TemporaryFile() as f:
            saved = os.dup(1)
            try:
                os.dup2(f.fileno(), 1)
                LIB.cfl_emu_fw_dump()
                libc.fflush(None)
            finally:
                os.dup2(saved, 1); os.close(saved)
            f.seek(0)
            return f.read().decode(errors='replace')


class CoralFlowerTests(unittest.TestCase):
    def test_boot_lcd_note_and_release(self):
        a = Instance()
        a.advance(.15)
        self.assertGreater(len(set(a.lcd())), 4)
        a.key(14, True)
        data = (C.c_int32 * 88200).from_buffer_copy(a.render(44100))
        self.assertGreater(max(map(abs, data)), 100)
        self.assertIn('chord: F sounding 1', a.dump())
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
            inst.key(14, True)
        for i in range(120):
            pa = a.render()
            unrelated.key(14 + i % 27, True)
            unrelated.encoder(1, 1)
            unrelated.render()
            unrelated.release()
            self.assertEqual(pa, b.render())
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
        self.assertNotIn('sounds: chord ORGAN (FM)', changed)
        raw = a.flash()
        self.assertNotEqual(raw, bytes([255]) * FLASH)
        self.assertGreater(a.metrics()[3], 0)
        b = Instance(raw)
        self.assertEqual(b.flash(), raw, 'Power-on must not rewrite the retained NOR image')
        restored = b.dump()
        self.assertIn('settings: loaded', restored)
        self.assertIn('octave 1', restored)
        sound = re.search(r'  sounds: (.*)', changed).group(1)
        self.assertIn('  sounds: ' + sound, restored)
        a.key(2, True); a.advance(.03); a.key(2, False); a.advance(.03)
        self.assertIn('screen EFFECTS', a.dump())

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
        for block in range(300):
            if block in (20, 90):
                a.key(14, True); ref.web_keys(1)
            if block in (70, 150):
                a.release(); ref.web_keys(0); ref.web_buttons(0)
            if block == 90:
                a.key(15, True); ref.web_keys(3)
            if block == 180:
                a.key(2, True); ref.web_buttons(1)  # FX label -> matrix2
            if block == 195:
                a.key(2, False); ref.web_buttons(0)
            if block == 210:
                a.encoder(0, 1); ref.web_enc(0, 1)
            actual = (C.c_int32 * 256).from_buffer_copy(a.render())
            ref.web_render(128)
            left, right = ref.web_out_l(), ref.web_out_r()
            for i in range(128):
                self.assertEqual(actual[2*i], round(left[i] * 65536), (block, i, 'L'))
                self.assertEqual(actual[2*i+1], round(right[i] * 65536), (block, i, 'R'))
            self.assertEqual(a.lcd(), C.string_at(ref.web_fb(), 240 * 240 * 2), block)
        self.assertEqual(a.flash(), C.string_at(ref.web_flash(), FLASH))


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--library', type=Path, required=True)
    p.add_argument('--reference', type=Path)
    ARGS, rest = p.parse_known_args()
    LIB = C.CDLL(str(ARGS.library.resolve()))
    LIB.cfl_state_size.restype = C.c_uint64
    LIB.cfl_state_init.argtypes = [C.c_void_p]
    LIB.cfl_bind.argtypes = [C.c_void_p]
    unittest.main(argv=[__file__] + rest)
