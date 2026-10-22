/* SPDX-License-Identifier: GPL-3.0-only
 * Jangada native bridge, adapted from the pinned Felucca wrapper and Jangada host tests.
 * Actual application/DSP/UI/storage sources are compiled; hardware-only paths are omitted. */
/* felucca_core.c -- Felucca 1.0 (engines/felucca/upstream, GPL-3.0-only, Leo Kuroshita /
 * Hügelton Instruments), the whole firmware, as a library the plugin can drive: a virtual
 * FM-1 running Felucca, with its sound, sequencer, screen, front panel, projects, user
 * presets, FM6 patch bank and editor protocol.
 *
 * Felucca is built as one compilation unit whose state is all file-level statics (some static inside
 * functions). It is compiled once (CMakeLists.txt fm1_core), and fel_state.py moves every such
 * variable, marked by the section pragma below, into one block of state that each instance owns:
 * felucca_core.h's bind() points the code at an instance's block before it runs. So each instance
 * is its own synth, from the state as the program started (state_init()), with one copy of the
 * code for them all. That needs Clang (the section pragma, and its IR); see fel_state.py for what
 * it handles, and docs/ADDING-A-FIRMWARE.md for what a firmware or an update must keep to.
 *
 * The firmware's own sources are included unchanged, in the order felucca.c includes them,
 * the way its host tests (upstream/tests/ui_test.c, editor_test.c, backup_test.c) build
 * them. What touches hardware is replaced below: the panel's buttons, keys and knobs and
 * the screen are the plugin's, and the flash is RAM. Never built: the update and boot
 * loader paths (ota.c, the boot loader's request): nothing here acts on them. */
#include <stdint.h>
#include <stddef.h>
#include <string.h>   /* Felucca's code past libc.c uses the C library's memcpy and memset */

#ifndef FEL_PREFIX
#error "FEL_PREFIX names this copy (felucca_core.h)"
#endif
#include "felucca_core_api.h"

/* the firmware's globals that are not static: one per copy (in one unit, so renaming
 * persist_t's member "panel" along with them changes nothing) */
#define bootguard FEL(bootguard)
#define panel FEL(panel)
#define settings FEL(settings)
#define proj_slot FEL(proj_slot)

#if !defined(__clang__) || !defined(FEL_BSS_SECTION)
#error "the firmware cores are built with Clang through fel_state.py (CMakeLists.txt fm1_core)"
#endif
/* every writable variable from here to the pragma's end below (the firmware's, some static inside
 * functions, and this file's own) carries this pragma's mark: fel_state.py moves each marked one
 * into the state each instance owns (engines/felucca/fel_state.py, felucca_core.h) */
#define FEL_PRAGMA(x) _Pragma(#x)
#define FEL_SECTIONS(b, d) FEL_PRAGMA(clang section bss = b data = d)
FEL_SECTIONS(FEL_BSS_SECTION, FEL_DATA_SECTION)

#define __attribute__(x)
#define FELUCCA_OTA 1                    /* the editor's SysEx plumbing in usb.c (not ota.c: never built) */
#define FELUCCA_FLASH 1                  /* projects, user presets and their FM6 patches in "flash" (RAM below) */
#define FELUCCA_VERSION "v1.0.1"
/* the user sample slots USR1..3: empty, and never written (the plugin takes no samples yet), so
 * one array of zeros for every copy (felucca_shared.c, written by CMakeLists.txt) rather than
 * 240 KB of each one's state */
#define HOST_FLASH_SIZE 0x100000u
static uint8_t host_flash[HOST_FLASH_SIZE];
static uint32_t host_master = 716;
static uint64_t host_metrics[16];
#define SMP_USER_XIP(k) ((const uint8_t *)(host_flash + (SMP_USER_BASE + (k) * SMP_USER_SIZE)))
static uint8_t host_sample_byte(uint32_t off);
#define memset FEL(memset)
#define memcpy FEL(memcpy)
#define memcmp FEL(memcmp)
#include "felucca_tables.h"
#include "../upstream/firmware/src/libc.c"
#undef memset
#undef memcpy
#undef memcmp
static struct { volatile uint32_t notes, buttons; } fm1_in;
#include "../upstream/firmware/src/core.h"
#include "../upstream/firmware/src/engines.c"
static uint8_t host_sample_byte(uint32_t off) { if(off & 0x80000000u) { off &= 0x7fffffffu; return off<HOST_FLASH_SIZE?host_flash[off]:0; } return off<sizeof SMP_DATA?SMP_DATA[off]:0; }
#include "../upstream/firmware/src/mod.c"
#include "../upstream/firmware/src/drums.c"
#include "../upstream/firmware/src/params.c"
#include "../upstream/firmware/src/voice.c"
#include "../upstream/firmware/src/slicer.c"
#include "../upstream/firmware/src/fx.c"
static void fm1_delay_ms(uint32_t ms) { (void)ms; }
#include "../upstream/firmware/src/usb.c"
/* what goes out (the editor's replies and pushes): usb.c's queue holds 64 packets, less than one
 * reply; while it waits for room (ota_idle), its packets move on to this one, which the plugin
 * takes between audio blocks (FEL(midi_out)) */
#define FEL_OUTQ 8192u
static uint32_t fel_out[FEL_OUTQ], fel_out_r, fel_out_w;
static void fel_out_drain(void)   /* full (nobody takes them): the oldest go, the sender never waits */
{
    while (so_r != so_w) {
        if (fel_out_w - fel_out_r >= FEL_OUTQ)
            fel_out_r++;
        fel_out[fel_out_w++ % FEL_OUTQ] = sx_out_q[so_r++ % SXQ];
    }
}
/* time that passes while the main loop waits for something the device's interrupts would do
 * (the clock is the audio's, which cannot run meanwhile): counted on, so fm1_ms never goes back */
static uint32_t fel_wait_ms;
static uint32_t ota_now_ms(void) { return fm1_ms; }   /* usb.c's SysEx sender waits on these */
static void ota_idle(void)
{
    fel_out_drain();
    if (so_w - so_r >= SXQ) {            /* still full: its 200 ms run out */
        fel_wait_ms++;
        fm1_ms++;
    }
}
#include "../upstream/firmware/src/midi_uart.c"
#include "../upstream/firmware/src/seq.c"


/* ---- the hardware, as Felucca's host tests replace it (tests/ui_test.c) ----------------------- */
#define FM1_NCOL 11u
/* key id at (physical column, packed row bit), -1 = none: hal/fm1_input.h's, for the LEDs
 * (ui_input.c led_pos_init finds each key's LED by it) */
static const int8_t FM1_KEYMAP[6][FM1_NCOL] = {
    {-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    { 5, 11,  4, 10,  3,  9,  2,  8, -1, -1, -1},
    {34, 35, 36, 37, 38, 40, 39, 13,  7,  6, 12},
    {23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33},
    { 0,  1, 15, 14, 17, 16, 19, 18, 20, 21, 22},
    {-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
};
static uint8_t fm1_led[FM1_NCOL], fm1_led_dim[FM1_NCOL];   /* lit, and the idle glow: read by FEL(leds) */
/* (1.1) the breathing LEDs and a steady mid level (the DRUM grid's beats): FEL(leds) shows both dim */
static uint8_t fm1_led_breath[FM1_NCOL], fm1_led_bg[FM1_NCOL];
static uint16_t fm1_led_bg_ns;
static void fm1_led_key(uint32_t id,int on) {(void)id;(void)on;}
static void fm1_led_dim_level(uint32_t lo) { (void)lo; }
/* (1.1, hal/fm1_led_anim.h) the power-on sweep and the idle animation: none here, the UI's LEDs at once */
static void fm1_led_anim_start(uint32_t glow) { (void)glow; }
static int fm1_led_anim_on(void) { return 0; }
static void fm1_led_idle_start(uint32_t glow) { (void)glow; }
static int fm1_led_idle_on(void) { return 0; }
static void fm1_led_anim_stop(void) {}
#define FM1_TICKS_PER_US 1u
static uint32_t host_ticks, host_pressed, host_notes;
static int32_t host_enc[7];
static uint32_t fm1_ticks(void) { return host_ticks; }
static uint32_t fm1_input_edges(int x) { uint32_t p = host_pressed; (void)x; host_pressed = 0; return p; }
static uint32_t fm1_input_note_edges(void) { uint32_t n = host_notes; host_notes = 0; return n; }
static int32_t fm1_enc_take(uint32_t e) { int32_t s = host_enc[e % 7u]; host_enc[e % 7u] = 0; return s; }
/* fed while the main loop waits for the audio side: ed_flash_stop waits for the transport to
 * stop, which the next audio block would do. Do it here, as Felucca's editor test does, and let
 * the time pass */
static void seq_stop(void);
static void fm1_wdt_feed(void)
{
    if (transport_req == 2u) {
        seq_stop();
        transport_req = 0;
    }
    fel_wait_ms++;
    fm1_ms++;
}
static void fm1_irq_off(void) {}
static void fm1_irq_on(void) {}
static uint16_t host_screen[240 * 240];   /* RGB565, as the LCD takes it (big endian) */
static void lcd_fill(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint16_t c)
{
    uint32_t i, j;
    for (j = 0; j < h && y + j < 240u; j++)
        for (i = 0; i < w && x + i < 240u; i++)
            host_screen[(y + j) * 240u + x + i] = (uint16_t)((c >> 8) | (c << 8));
}
static void lcd_sync(void) {}
static void lcd_power(uint32_t on) { (void)on; }   /* (1.1.5: MENU > SCREEN OFF's backlight, as its host tests stub it) */
static void lcd_wake_now(void) {}
#define SCOPE_N 512u                     /* audio.c's (not built): the HOME oscilloscope, fed in FEL(render) */
static int16_t scope_buf[SCOPE_N];
static uint32_t scope_w;
static void lcd_blit(uint32_t x, uint32_t y, uint32_t w, uint32_t h, const uint16_t *p)
{
    uint32_t i, j;
    for (j = 0; j < h && y + j < 240u; j++)
        for (i = 0; i < w && x + i < 240u; i++)
            host_screen[(y + j) * 240u + x + i] = p[j * w + i];
}
static struct { uint32_t stage, page, home, ui_frames; } felucca_dbg;
#include "../upstream/firmware/src/gfx.c"
#include "../upstream/firmware/src/panel.c"
#include "../upstream/firmware/src/ui.c"
#include "../upstream/firmware/src/icons.c"
#include "../upstream/firmware/src/ui_draw.c"
/* HOME > PANEL calibrates the device's button matrix: the plugin's panel has none (its buttons
 * go by label), and the setup waits for real buttons, holding up the audio. It says so instead. */
static void fel_panel_setup(void) { ui_message("PANEL: ON THE FM-1"); }
#define panel_setup() fel_panel_setup()
#include "../upstream/firmware/src/ui_menu.c"
#undef panel_setup
#include "../upstream/firmware/src/ui_input.c"

/* Full physical NOR image: source storage keeps its original A/B maps and CRCs. */
static uint8_t flash_ok = 1;
static int st_read(uint32_t off, void *dst, uint32_t n) {
    if (off > HOST_FLASH_SIZE || n > HOST_FLASH_SIZE - off) return -1;
    memcpy(dst, host_flash + off, n); return 0;
}
static int st_erase(uint32_t off) {
    off &= ~4095u; if (off > HOST_FLASH_SIZE - 4096u) return -8;
    memset(host_flash + off, 0xFF, 4096); return 0;
}
static int st_prog(uint32_t off, const void *src, uint32_t n) {
    if (off > HOST_FLASH_SIZE || n > HOST_FLASH_SIZE - off) return -8;
    const uint8_t *p = src; for (uint32_t i=0;i<n;i++) host_flash[off+i] &= p[i]; return 0;
}
static uint32_t irq_save(void) { return 0; }
static void irq_restore(uint32_t f) { (void)f; }
static uint32_t fl_jedec_ram(void) { return 0x856014u; }   /* the expected part: flash_ok */
static void fl_plain_window_init(void) {}
#define FL_FAR(fn) (fn)
static void audio_silence(void) {}
static void fl_inval(uint32_t off, uint32_t n) { (void)off; (void)n; }
static int fl_erase4k(uint32_t off, uint32_t *took) { (void)off; *took = 0; return -1; }   /* no user samples yet */
static int fl_write(uint32_t off, const void *p, uint32_t n) { (void)off; (void)p; (void)n; return -1; }
#include "../upstream/firmware/src/storage.c"
#include "../upstream/firmware/src/upreset.c"
#include "../upstream/firmware/src/project.c"
#include "../upstream/firmware/src/fm6_bank.c"
#include "../upstream/firmware/src/editor.c"

/* ---- from main.c (not built: the device's boot) --------------------------------------------- */
/* power-on: the parts with their default sounds (TRK_DEF); the sequencers empty */
static void felucca_init(void)
{
    uint32_t i;
    fm6_init();                                 /* Jangada: every track the FM6 init voice */
    for (i = 0; i < G_SETTINGS; i++)            /* (from G_SETTINGS: the FM-1's settings, kept: panel.c) */
        song.g[i] = GP[i].def;
    for (i = 0; i < NTRK; i++) {
        track_t *t = &trk[i];
        track_defaults(t);
        if (i < NPART) {
            set_engine_raw(t, TRK_DEF[i][0]);
            apply_preset_to(t, TRK_DEF[i][1]);   /* with its sends */
            t->engine = t->eng_req;
        }
        track_defaults_steps(t);              /* the sequencers start empty */
    }
    song.sel = 0;
    song.solo = 0;                              /* (Jangada: also NEW PROJECT, ui_menu.c) */
    song.rec = 0;
    song.master_q12 = 2048;
    ui.home = 1;
    ui.force = 1;
}

/* the plugin's own per-instance state, in the copy's sections with Felucca's (so it goes with
 * it when an instance's state is saved and put back): the audio rendered (the clock), when the
 * main loop last ran, and when the editor was last served */
static uint64_t fel_frames;
static uint32_t fel_main_ms;
static uint64_t fel_served_at;

#undef __attribute__                     /* Felucca's code is done: attributes mean something again */
#pragma clang section bss = "" data = ""

/* ---- the API ------------------------------------------------------------------------------ */

static void fel_clock(void)
{
    const uint64_t us = fel_frames * 1000000u / FS + (uint64_t)fel_wait_ms * 1000u;
    fm1_ms = (uint32_t)(us / 1000u);
    host_ticks = (uint32_t)us;
}

/* the editor protocol's waiting frame, if any. A frame that is not the editor's (M-VAVE's identity
 * query or reply, another firmware's SysEx) is left waiting by ed_service, for ota_service (the
 * updater's handshake) to take on the device; nothing here does, so it is dropped: else it would
 * hold the one frame slot and every editor request after it would be dropped (seen in the app,
 * whose MIDI input can be the FM-1's own port) */
static void fel_editor(void)
{
    ed_service();
    if (sx_ready)
        ota_frame_done();
}

/* one pass of main.c's loop, without what is the device's own (the watchdog, USB, the update and
 * boot loader requests, the LEDs and the screen, drawn when the plugin asks) */
static void fel_main_pass(void)
{
    usb.uboot_req = 0;                   /* the boot loader key or an update command: never acted on */
    usb.ota_req = 0;
    fel_editor();                        /* the editor protocol */
    ui_input();
    song.master_q12 = (host_master * host_master) >> 8;
    ui_leds();
    ui_draw();
    autosave_tick();
}

void FEL(init)(void)   /* main.c fm1_main, up to its loop: the stored settings and objects, then the parts */
{
    fel_frames = 0;
    fel_wait_ms = 0;
    fel_main_ms = 0;
    fel_clock();
    persist_boot();
    fm6_bank_boot();
    settings_init();
    panel_init();
    felucca_init();
    autosave_resume();
    usb.config = 1;                      /* as a computer that has set the device up: the editor may reply */
}


uint32_t FEL(ctl)(void) {return CTL;}
uint32_t FEL(rate)(void) {return FS;}
void FEL(render)(int32_t *out,uint32_t frames) {
    for(uint32_t i=0;i+CTL<=frames;i+=CTL) {
        if(fm1_ms-fel_main_ms>=16u) {fel_main_ms=fm1_ms;fel_main_pass();}
        mix_block(out+2u*i,CTL);
        for(uint32_t k=0;k<CTL;k++) {
            if(k&1u)scope_buf[scope_w++&(SCOPE_N-1u)]=(int16_t)out[2u*(i+k)];
            for(uint32_t c=0;c<2;c++){int32_t v=out[2u*(i+k)+c];host_metrics[4]+=v!=0;out[2u*(i+k)+c]=(int32_t)((int64_t)v*2);}
        }
        uint32_t voices=0;
        for(uint32_t t=0;t<NPART;t++)for(uint32_t v=0;v<NVOICE;v++)if(trk[t].v[v].active){voices++;host_metrics[7]|=1u<<t;}
        if(voices>host_metrics[1])host_metrics[1]=voices;
        host_metrics[0]+=CTL;fel_frames+=CTL;fel_clock();
    }
}
void FEL(draw)(uint16_t *out){memcpy(out,host_screen,sizeof host_screen);}
void FEL(physical_key)(uint32_t id,int down) {
    if(id<14u){uint32_t bit=1u<<id;if(down){if(!(fm1_in.buttons&bit))host_pressed|=bit;fm1_in.buttons|=bit;}else fm1_in.buttons&=~bit;}
    else if(id<41u){uint32_t bit=1u<<(id-14u);if(down){if(!(fm1_in.notes&bit))host_notes|=bit;fm1_in.notes|=bit;}else fm1_in.notes&=~bit;}
}
void FEL(release_all)(void){fm1_in.buttons=fm1_in.notes=host_pressed=host_notes=0;}
void FEL(physical_encoder)(uint32_t id,int32_t delta){if(id<7u)host_enc[id]+=delta;}
void FEL(physical_leds)(float *out){
    for(uint32_t id=0;id<41u;id++){float v=0;
        for(uint32_t p=0;p<FM1_NCOL;p++)for(uint32_t r=1;r<5u;r++)if(FM1_KEYMAP[r][p]==(int8_t)id)
            v=(fm1_led[p]&(1u<<r))?95.f/1100.f:(fm1_led_breath[p]&(1u<<r))?8.f/1100.f:(fm1_led_bg[p]&(1u<<r))?(float)fm1_led_bg_ns/1100.f:(fm1_led_dim[p]&(1u<<r))?4.f/1100.f:0;
        out[id]=v;
    }
}
void FEL(volume)(uint32_t v){host_master=v>1023u?1023u:v;}
void FEL(flash_load)(const uint8_t *p){memcpy(host_flash,p,HOST_FLASH_SIZE);}
void FEL(flash_copy)(uint8_t *p){memcpy(p,host_flash,HOST_FLASH_SIZE);}
uint32_t FEL(workload_metrics)(uint64_t *p,uint32_t cap){project_t current;proj_capture(&current);host_metrics[12]=current.sum;uint32_t n=cap<16u?cap:16u;memcpy(p,host_metrics,n*sizeof *p);return n;}
