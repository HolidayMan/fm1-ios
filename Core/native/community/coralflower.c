/* SPDX-License-Identifier: GPL-3.0-only
 * PocketFM native boundary for CoralFlower v0.5 by FicusFicusov.
 * Reuses the release's complete portable firmware/audio/UI include order.
 * See coralflower.lock.json and coralflower_adapt.py for the exact derivation.
 * No binary CPU, JS, WebKit or WASM runtime participates in this engine. */
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include "felucca_core_api.h"

#if !defined(__clang__) || !defined(FEL_BSS_SECTION)
#error "CoralFlower must be compiled through the per-instance state rewrite"
#endif
#define CFL_PRAGMA(x) _Pragma(#x)
#define CFL_SECTIONS(b,d) CFL_PRAGMA(clang section bss=b data=d)
CFL_SECTIONS(FEL_BSS_SECTION, FEL_DATA_SECTION)
static uint8_t cfl_flash_loaded;
/* Host configuration cannot silently change the pinned instrument at runtime. */
#define getenv(name) ((char *)0)
#define CF_NATIVE_SERIAL 1
#define FELUCCA_VERSION "CoralFlower 0.5"
#include "../upstream/tools/emu/emu_fw.c"
#undef getenv

/* The release's headless clock: 1 ms input ticks, 15 ms UI, audio ISR every
 * 128 source frames. Display observation itself never advances device time. */
static uint32_t cfl_ms, cfl_last_ui, cfl_block_pos = EMU_BLOCK;
static uint64_t cfl_frames, cfl_render_calls, cfl_ui_frames;
static int16_t cfl_block[EMU_BLOCK * 2];
static uint8_t cfl_booted;
void FEL(init)(void)
{
    if (cfl_booted) return;
    emu_fw_options(NULL, 1, 0, 1);
    emu_hal.ready = 2;
    emu_fw_init(0);
    cfl_booted = 1;
}
static void cfl_next_block(void)
{
    for (;;) {
        uint32_t ms = cfl_ms++;
        emu_fw_tick(ms);
        if (ms == 0 || ms - cfl_last_ui >= 15u) {
            cfl_last_ui = ms;
            emu_fw_frame();
            cfl_ui_frames++;
        } else emu_fw_idle();
        if (cfl_frames + EMU_BLOCK <= (uint64_t)ms * EMU_FS / 1000u) {
            emu_fw_audio(cfl_block, EMU_BLOCK);
            cfl_frames += EMU_BLOCK;
            cfl_block_pos = 0;
            return;
        }
    }
}
uint32_t FEL(ctl)(void) { return EMU_BLOCK; }
uint32_t FEL(rate)(void) { return EMU_FS; }
void FEL(render)(int32_t *out, uint32_t frames)
{
    FEL(init)();
    cfl_render_calls++;
    for (uint32_t i=0; i<frames; i++) {
        if (cfl_block_pos == EMU_BLOCK) cfl_next_block();
        /* Native shared ABI stores Q15 * 2; Rust shifts once to signed Q15.
         * Source emu_fw_audio already applied its exact ISR OUT_SHIFT. */
        out[2*i] = (int32_t)cfl_block[2*cfl_block_pos] * 2;
        out[2*i+1] = (int32_t)cfl_block[2*cfl_block_pos+1] * 2;
        cfl_block_pos++;
    }
}
void FEL(draw)(uint16_t *out) { memcpy(out, emu_hal.lcd, sizeof emu_hal.lcd); }
void FEL(physical_key)(uint32_t id, int down)
{
    uint32_t bit;
    if (id>=41u) return;
    if (id<14u) {
        bit=1u<<id;
        if (down) {emu_hal.buttons_tap |= bit & ~emu_hal.buttons; emu_hal.buttons |= bit;}
        else emu_hal.buttons &= ~bit;
    } else {
        bit=1u<<(id-14u);
        if (down) {emu_hal.keys_tap |= bit & ~emu_hal.keys; emu_hal.keys |= bit;}
        else emu_hal.keys &= ~bit;
    }
}
void FEL(release_all)(void)
{
    emu_hal.buttons=emu_hal.buttons_tap=emu_hal.keys=emu_hal.keys_tap=0;
    memset((void *)emu_hal.enc,0,sizeof emu_hal.enc);
}
void FEL(physical_encoder)(uint32_t id,int32_t delta)
{
    if (id<7u) emu_hal.enc[id] += delta;
}
void FEL(volume)(uint32_t value) { emu_hal.master=(int32_t)(value>1023u?1023u:value); }
void FEL(physical_leds)(float *out)
{
    for (uint32_t id=0;id<41u;id++) {
        float v=0;
        for (uint32_t row=1;row<5u;row++) for (uint32_t col=0;col<EMU_NCOL;col++) {
            if (emu_keymap[row][col] != (int8_t)id) continue;
            uint8_t bit=(uint8_t)(1u<<row);
            v=(emu_hal.led[col]&bit)?0.086f:(emu_hal.led_mid[col]&bit)?0.008f:
              (emu_hal.led_dim[col]&bit)?0.001f:(emu_hal.led_faint[col]&bit)?0.0003f:0;
        }
        out[id]=v;
    }
}
void FEL(flash_load)(const uint8_t *data)
{
    memcpy(emu_flash,data,EMU_FLASH_SIZE);
    cfl_flash_loaded=1;
}
void FEL(flash_copy)(uint8_t *data) { memcpy(data,emu_flash,EMU_FLASH_SIZE); }
uint32_t FEL(workload_metrics)(uint64_t *out,uint32_t capacity)
{
    uint64_t v[16]={cfl_frames,cfl_render_calls,cfl_ui_frames,emu_flash_writes};
    uint32_t n=capacity<16u?capacity:16u;
    memcpy(out,v,n*sizeof *out);
    return n;
}
CFL_SECTIONS("", "")
