"""Narrow, checked adaptation of a copied ChoralRoot v0.27 portable host.

Only the ignored build copy changes. DSP, UI, settings, NOR operations, original
storage layouts and engine feature flags remain upstream's. Calls run serially
on the native worker, rather than the desktop emulator's three threads.
"""
from pathlib import Path


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit('ChoralRoot portable-host anchor changed: ' + old[:70])
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
    end = s.index('#define ST_READS_COUNTED 1', begin)
    s = s[:begin] + '''static void emu_flash_open(void)
{
    if (!chr_flash_loaded) memset(emu_flash, 255, sizeof emu_flash);
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
        raise SystemExit('ChoralRoot desktop profiler anchors changed')
    s=s.replace('#ifdef __APPLE__', '#if defined(__APPLE__) && !defined(CF_NATIVE_SERIAL)')
    s=replace_once(s, '#if !defined(__EMSCRIPTEN__)', '#if !defined(__EMSCRIPTEN__) && !defined(CF_NATIVE_SERIAL)')
    p.write_text(s)
    p = upstream / 'tools/emu/emu_fw.c'
    s = replace_once(p.read_text(), '#include <os/lock.h>', '/* Serial native worker: no desktop lock. */')
    s = replace_once(s, '#include <pthread.h>', '/* No emulator threads. */')
    s = replace_once(s, '    atexit(emu_fw_exit);', '    /* The owning native instance controls its lifetime. */')
    s = replace_once(s, '    cr_update_poll();', '    /* Device-only update/reboot gesture is unavailable on the host. */')
    p.write_text(s)
    p = upstream / 'tools/emu/emu_firmware.h'
    s = p.read_text()
    # Firmware-only restart hooks must never exit the owning mobile process.
    import re
    for name,args,body in [('CRB_STUB_GO','w','((void)(w))'),('CRB_UBOOT_GO','','((void)0)'),('CR_REBOOT','','((void)0)')]:
        pattern=r'^#define '+name+r'\('+args+r'\)(?:[^\n]*\\\n)*[^\n]*'
        s,n=re.subn(pattern, '#define '+name+'('+args+') '+body,s,flags=re.MULTILINE)
        if n!=1:raise SystemExit('ChoralRoot restart anchor changed: '+name)
    p.write_text(s)
