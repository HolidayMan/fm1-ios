//! Local-only source-native workload: PACKAGE SECONDS. Uses fresh firmware, never an owner save.
use fm1_ios_core::*;
use std::{ffi::CStr, fs, time::Instant};
#[cfg(fm1_native_family)]
extern "C" {
    fn fel_midi(p: u32);
    fn mel_midi(p: u32);
    fn fel_set_engine(t: u32, e: u32);
    fn mel_set_engine(t: u32, e: u32);
    fn fel_nengines() -> u32;
    fn mel_nengines() -> u32;
    fn fel_engine_name(e: u32) -> *const std::ffi::c_char;
    fn mel_engine_name(e: u32) -> *const std::ffi::c_char;
    fn engine_drum(kit: i32, voice: i32, vel: f32);
    fn engine_bass_on(part: i32, note: i32, accent: i32, slide: i32);
    fn engine_brk_live(key: i32, down: i32);
}
fn main() {
    #[cfg(not(fm1_native_family))]
    panic!("Requires explicitly built FM1_NATIVE_FAMILY");
    #[cfg(fm1_native_family)]
    unsafe {
        let args: Vec<_> = std::env::args().collect();
        let package = fs::read(&args[1]).unwrap();
        let seconds = args
            .get(2)
            .map(|s| s.parse::<usize>().unwrap())
            .unwrap_or(30);
        let mut error = [0u8; 512];
        let m = instrument_create(package.as_ptr(), package.len(), error.as_mut_ptr(), 512);
        assert!(!m.is_null());
        let kind = instrument_native_kind(m);
        assert!((3..=5).contains(&kind));
        let mut audio = [0f32; 1024];
        assert_eq!(instrument_render(m, audio.as_mut_ptr(), 512), 512);
        if kind != 4 {
            let (count, name, set): (
                unsafe extern "C" fn() -> u32,
                unsafe extern "C" fn(u32) -> *const std::ffi::c_char,
                unsafe extern "C" fn(u32, u32),
            ) = if kind == 3 {
                (fel_nengines, fel_engine_name, fel_set_engine)
            } else {
                (mel_nengines, mel_engine_name, mel_set_engine)
            };
            let engine = (0..count())
                .find(|&e| CStr::from_ptr(name(e)).to_bytes() == b"FM6")
                .expect("real FM6 engine");
            for track in 0..4 {
                set(track, engine);
            }
        }
        let mut frames = 0;
        let mut nonzero = 0u64;
        let mut peak = 0f32;
        let mut sum = 0f64;
        let mut render_seconds = 0f64;
        let started = Instant::now();
        let mut trigger_at = 0;
        while frames < 44100 * seconds {
            if frames >= trigger_at {
                if kind == 4 {
                    for kit in 0..2 {
                        for voice in 0..11 {
                            engine_drum(kit, voice, 0.8);
                        }
                    }
                    for p in 0..2 {
                        engine_bass_on(p, 48 + 12 * p, 1, 0);
                    }
                    engine_brk_live(0, 1);
                } else {
                    let midi = if kind == 3 { fel_midi } else { mel_midi };
                    let notes = if kind == 3 { 2 } else { 4 };
                    for ch in 0..4 {
                        for i in 0..notes {
                            let note = 48 + i;
                            midi(0x08 | ((0x80 + ch) << 8) | (note << 16));
                            midi(0x09 | ((0x90 + ch) << 8) | (note << 16) | (100 << 24));
                        }
                    }
                }
                trigger_at += 4410;
            }
            let begin = Instant::now();
            assert_eq!(instrument_render(m, audio.as_mut_ptr(), 512), 512);
            render_seconds += begin.elapsed().as_secs_f64();
            for &v in &audio {
                assert!(v.is_finite());
                nonzero += u64::from(v != 0.);
                peak = peak.max(v.abs());
                sum += (v as f64) * (v as f64);
            }
            frames += 512;
        }
        let mut metrics = [0u64; 16];
        assert_eq!(instrument_workload_metrics(m, metrics.as_mut_ptr(), 16), 16);
        assert!(nonzero > 1000);
        assert_eq!(metrics[13], 0);
        println!("{{\"native_kind\":{kind},\"audio_seconds\":{},\"render_seconds\":{render_seconds},\"wall_seconds\":{},\"budget_ratio\":{},\"nonzero_samples\":{nonzero},\"peak\":{peak},\"rms\":{},\"metrics\":{:?}}}",frames as f64/44100.,started.elapsed().as_secs_f64(),render_seconds/(frames as f64/44100.),(sum/(frames*2)as f64).sqrt(),metrics);
        instrument_destroy(m);
    }
}
