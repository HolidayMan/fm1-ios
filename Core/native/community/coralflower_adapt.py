"""Narrow, checked adaptation of a copied CoralFlower v0.5 portable host.

Only the ignored build copy changes. DSP, UI, settings, NOR operations, original
storage layouts and engine feature flags remain upstream's. Calls run serially
on the native worker, rather than the desktop emulator's three threads.
"""
from pathlib import Path


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit('CoralFlower portable-host anchor changed: ' + old[:70])
    return text.replace(old, new)


def adapt(upstream):
    upstream = Path(upstream)
    p = upstream / 'tools/emu/emu_hal_fw.h'
    s = p.read_text()
    begin = s.index('static os_unfair_lock emu_cpu =')
    end = s.index('/* --------------------------------------------- keys, LEDs, knobs', begin)
    s = s[:begin] + '''/* Native worker serializes every call, including the two virtual ISRs.
 * A nesting counter retains the source's balanced critical-section structure. */
static uint32_t emu_cpu_depth;
static void fm1_irq_off(void) { emu_cpu_depth++; }
static int emu_cpu_try(void) { emu_cpu_depth++; return 1; }
static void fm1_irq_on(void) { if (emu_cpu_depth) emu_cpu_depth--; }

''' + s[end:]
    begin = s.index('static void emu_flash_open(void)')
    end = s.index('static int st_read(', begin)
    s = s[:begin] + '''static void emu_flash_open(void)
{
    if (!cfl_flash_loaded) memset(emu_flash, 255, sizeof emu_flash);
    flash_ok = 1;
}
static void emu_flash_sync(uint32_t off, uint32_t n)
{
    (void)off; (void)n;
    emu_flash_writes++;
}
''' + s[end:]
    p.write_text(s)
    # macOS-only instruction accounting has no libproc API on iOS. Use the
    # upstream host fallback (zero diagnostic counter); the source's serial
    # second-core job still runs immediately and the audio sample clock stays.
    p = upstream / 'firmware/src/cr_cpu1.h'
    s = p.read_text()
    if s.count('#ifdef __APPLE__') != 2:
        raise SystemExit('CoralFlower desktop profiler anchors changed')
    p.write_text(s.replace('#ifdef __APPLE__', '#if defined(__APPLE__) && !defined(CF_NATIVE_SERIAL)'))
    p = upstream / 'tools/emu/emu_fw.c'
    s = replace_once(p.read_text(), '#include <os/lock.h>', '/* Serial native worker: no desktop lock. */')
    s = replace_once(s, '#include <pthread.h>', '/* No emulator threads. */')
    s = replace_once(s, '    atexit(emu_fw_exit);', '    /* The owning native instance controls its lifetime. */')
    s = replace_once(s, '    cr_update_poll();', '    /* Device-only update/reboot gesture is unavailable on the host. */')
    p.write_text(s)
    p = upstream / 'tools/emu/emu_firmware.h'
    s = p.read_text()
    s = replace_once(s, '#define CRB_STUB_GO(w) do { printf("restart: stub request %08X\\n", (unsigned)(w)); fflush(stdout); exit(0); } while (0)', '#define CRB_STUB_GO(w) ((void)(w))')
    s = replace_once(s, '#define CRB_UBOOT_GO() do { printf("restart: ROM USB boot\\n"); fflush(stdout); exit(0); } while (0)', '#define CRB_UBOOT_GO() ((void)0)')
    p.write_text(s)
