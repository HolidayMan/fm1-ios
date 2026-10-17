//! Local-only ABI workload: PACKAGE FLASH|- EVENTS|- OUTPUT_DIR SECONDS.
//! Event times follow delivered audio frames (not wall time), as firmware transport does.
use fm1_ios_core::*;
use std::{env, fs, path::Path, time::Instant};
fn hash(bytes: impl IntoIterator<Item = u8>) -> u64 {
    bytes.into_iter().fold(0xcbf29ce484222325, |h, b| {
        (h ^ b as u64).wrapping_mul(0x100000001b3)
    })
}
fn main() {
    unsafe {
        let a: Vec<_> = env::args().collect();
        assert_eq!(a.len(), 6);
        let package = fs::read(&a[1]).unwrap();
        let mut err = [0u8; 512];
        let m = instrument_create(package.as_ptr(), package.len(), err.as_mut_ptr(), 512);
        assert!(!m.is_null(), "{}", String::from_utf8_lossy(&err));
        if a[2] != "-" {
            let flash = fs::read(&a[2]).unwrap();
            assert!(instrument_restore(m, flash.as_ptr(), flash.len()));
        }
        let events = if a[3] == "-" {
            String::new()
        } else {
            fs::read_to_string(&a[3]).unwrap()
        };
        let events: Vec<_> = events
            .lines()
            .filter(|l| !l.is_empty() && !l.starts_with('#'))
            .map(|l| {
                let t: Vec<_> = l.split_whitespace().collect();
                (
                    t[0].parse::<u64>().unwrap(),
                    t[1].to_owned(),
                    t[2].parse::<u32>().unwrap(),
                    t[3].parse::<i32>().unwrap(),
                )
            })
            .collect();
        let mut event = 0;
        let out = Path::new(&a[4]);
        fs::create_dir_all(out).unwrap();
        let mut pcm = Vec::new();
        let mut frames = 0usize;
        let mut audio = [0f32; 1024];
        let mut pixels = vec![0u32; 240 * 240];
        let mut leds = [0f32; 41];
        let seconds = a[5].parse::<usize>().unwrap();
        let mut next_report = 44100 * 5;
        let mut window = Instant::now();
        let mut peak = 0f32;
        let mut render_seconds = 0.;
        let mut total_render = 0.;
        let started = Instant::now();
        println!("backend={}", instrument_backend(m));
        while frames < 44100 * seconds {
            let ms = frames as u64 * 1000 / 44100;
            while event < events.len() && events[event].0 <= ms {
                let (_, kind, id, value) = &events[event];
                match kind.as_str() {
                    "key" => instrument_key(m, *id, *value != 0),
                    "encoder" => instrument_encoder(m, *id, *value),
                    "volume" => instrument_volume(m, (*value).max(0) as u32),
                    _ => panic!("unknown event"),
                };
                event += 1;
            }
            let t = Instant::now();
            let n = instrument_render(m, audio.as_mut_ptr(), 512);
            render_seconds += t.elapsed().as_secs_f64();
            if n != 512 {
                println!("core_shortage audio_frame={frames} missing={}", 512 - n);
            }
            frames += 512;
            for &s in &audio {
                peak = peak.max(s.abs());
                pcm.extend_from_slice(&((s * 32768.) as i16).to_le_bytes());
            }
            if frames >= next_report {
                let _ = instrument_snapshot(m, pixels.as_mut_ptr(), leds.as_mut_ptr());
                let mut ppm = b"P6\n240 240\n255\n".to_vec();
                for &p in &pixels {
                    ppm.extend_from_slice(&[
                        (p & 255) as u8,
                        ((p >> 8) & 255) as u8,
                        ((p >> 16) & 255) as u8,
                    ]);
                }
                fs::write(
                    out.join(format!("audio-{}.ppm", frames * 1000 / 44100)),
                    ppm,
                )
                .unwrap();
                println!(
                    "audio_seconds={:.6} render={:.6} windowwall={:.6} peak={:.6} lcd={:016x}",
                    frames as f64 / 44100.,
                    render_seconds,
                    window.elapsed().as_secs_f64(),
                    peak,
                    hash(pixels.iter().flat_map(|p| p.to_le_bytes()))
                );
                total_render += render_seconds;
                render_seconds = 0.;
                window = Instant::now();
                next_report += 44100 * 5;
            }
        }
        let mut flash = vec![0u8; instrument_flash(m, std::ptr::null_mut(), 0)];
        instrument_flash(m, flash.as_mut_ptr(), flash.len());
        fs::write(out.join("final.flash"), &flash).unwrap();
        fs::write(out.join("pcm-s16le.raw"), &pcm).unwrap();
        println!(
            "frames={frames} wall={:.6} render={:.6} pcm={:016x} flash={:016x}",
            started.elapsed().as_secs_f64(),
            total_render + render_seconds,
            hash(pcm),
            hash(flash)
        );
        let mut metrics = [0u64; 16];
        let count = instrument_workload_metrics(m, metrics.as_mut_ptr(), 16);
        println!("native_workload={:?}", &metrics[..count as usize]);
        instrument_destroy(m);
    }
}
