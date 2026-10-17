//! Offline workload probe. Input firmware, saves, screenshots and audio stay local.
//! Usage: workload_probe PACKAGE FLASH|- EVENTS|- OUTPUT_DIR SECONDS
//! Events: guest milliseconds, key|encoder, numeric id, down(1)/up(0) or delta.
use fm1_core::{Bus, Cpu};
use fm1_soc::{machine, Action, Board, Soc};
use std::{
    env, fs,
    path::Path,
    time::{Duration, Instant},
};
const RAM: usize = 1 << 20;
fn hash(bytes: impl IntoIterator<Item = u8>) -> u64 {
    bytes.into_iter().fold(0xcbf29ce484222325, |h, b| {
        (h ^ b as u64).wrapping_mul(0x100000001b3)
    })
}
fn snapshot(soc: &Soc, output: &Path, label: &str) {
    let mut ppm = format!("P6\n240 240\n255\n").into_bytes();
    for &p in soc.lcd.fb.iter().take(240 * 240) {
        let p = p as u32;
        ppm.extend_from_slice(&[
            (((p >> 11) & 31) * 255 / 31) as u8,
            (((p >> 5) & 63) * 255 / 63) as u8,
            ((p & 31) * 255 / 31) as u8,
        ]);
    }
    fs::write(output.join(format!("{label}.ppm")), ppm).unwrap();
}
fn main() {
    let args: Vec<_> = env::args().collect();
    assert_eq!(args.len(), 6, "PACKAGE FLASH|- EVENTS|- OUTPUT_DIR SECONDS");
    let bytes = fs::read(&args[1]).unwrap();
    let fw = fm1_soc::stock_from_package(&bytes, None).unwrap();
    assert_eq!(fw.board, Board::Fm1);
    let output = Path::new(&args[4]);
    fs::create_dir_all(output).unwrap();
    let mut soc = Soc::new(RAM, fw.xip);
    soc.periph.hz = 240_000_000;
    soc.periph.skip_idle = true;
    let mut cpu = Cpu::new(fw.entry);
    cpu.jit_on = false;
    cpu.user = true;
    let params = 0x01c0_0000 + 0x7fc00;
    soc.write32(params, params + 0x40);
    cpu.regs[0] = fm1_soc::stock_boot(&mut soc, &fw.flash, params, fw.board);
    if args[2] != "-" {
        let flash = fs::read(&args[2]).unwrap();
        assert_eq!(flash.len(), soc.flash.mem.len());
        soc.flash.mem = flash;
    }
    soc.periph.apply(&Action::Adc { ch: 4, value: 716 });
    let events = if args[3] == "-" {
        String::new()
    } else {
        fs::read_to_string(&args[3]).unwrap()
    };
    let events: Vec<_> = events
        .lines()
        .filter(|l| !l.trim().is_empty() && !l.starts_with('#'))
        .map(|l| {
            let t: Vec<_> = l.split_whitespace().collect();
            assert_eq!(t.len(), 4);
            (
                t[0].parse::<u64>().unwrap(),
                t[1].to_owned(),
                t[2].parse::<u8>().unwrap(),
                t[3].parse::<i32>().unwrap(),
            )
        })
        .collect();
    assert!(events.windows(2).all(|w| w[0].0 <= w[1].0));
    let mut event = 0;
    let seconds = args[5].parse::<u64>().unwrap();
    let mut cpu1 = None;
    let mut tick = false;
    let mut pcm = Vec::<u8>::new();
    let start = Instant::now();
    let mut window_start = start;
    let mut c0_time = Duration::ZERO;
    let mut window_c0 = Duration::ZERO;
    let mut last_frames = 0;
    let mut last_insn = 0;
    let mut last_insn1 = 0;
    let mut last_ms = 0;
    let mut report_at = 5_000;
    while soc.periph.ms() < seconds * 1000 {
        while event < events.len() && events[event].0 <= soc.periph.ms() {
            let (ms, kind, id, value) = &events[event];
            match kind.as_str() {
                "key" => soc.periph.apply(&Action::Key {
                    id: *id,
                    down: *value != 0,
                }),
                "encoder" => soc.periph.apply(&Action::Enc {
                    enc: *id,
                    clicks: *value,
                }),
                _ => panic!("unknown event"),
            };
            snapshot(&soc, output, &format!("event-{ms}-{event}"));
            event += 1;
        }
        machine::run_dual(&mut cpu1, &mut soc, 20_000, RAM, false, |soc, n| {
            let t = Instant::now();
            let r = machine::run_blocks(&mut cpu, soc, n, &mut tick);
            c0_time += t.elapsed();
            r
        })
        .unwrap();
        for s in soc.periph.audio.drain(..) {
            pcm.extend_from_slice(&s.to_le_bytes());
        }
        if soc.periph.ms() >= report_at {
            let now = Instant::now();
            let frames = pcm.len() / 4;
            let insn1 = cpu1.as_ref().map(|c| c.insn_count).unwrap_or(0);
            let wall = (now - window_start).as_secs_f64();
            let audio = (frames - last_frames) as f64 / 44100.;
            println!("guest_ms={} wall={:.6} audio={:.6} ratio={:.6} c0wall={:.6} c1other={:.6} c0insn={} c1insn={} guest_audio_ratio={:.6}",soc.periph.ms(),wall,audio,wall/audio,(c0_time-window_c0).as_secs_f64(),wall-(c0_time-window_c0).as_secs_f64(),cpu.insn_count-last_insn,insn1-last_insn1,(soc.periph.ms()-last_ms) as f64/1000./audio);
            snapshot(&soc, output, &format!("guest-{}", report_at));
            window_start = now;
            window_c0 = c0_time;
            last_frames = frames;
            last_insn = cpu.insn_count;
            last_insn1 = insn1;
            last_ms = soc.periph.ms();
            report_at += 5_000;
        }
    }
    let mut wav = Vec::new();
    let len = pcm.len() as u32;
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&(36 + len).to_le_bytes());
    wav.extend_from_slice(b"WAVEfmt ");
    wav.extend_from_slice(&16u32.to_le_bytes());
    wav.extend_from_slice(&1u16.to_le_bytes());
    wav.extend_from_slice(&2u16.to_le_bytes());
    wav.extend_from_slice(&44100u32.to_le_bytes());
    wav.extend_from_slice(&176400u32.to_le_bytes());
    wav.extend_from_slice(&4u16.to_le_bytes());
    wav.extend_from_slice(&16u16.to_le_bytes());
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&len.to_le_bytes());
    wav.extend_from_slice(&pcm);
    fs::write(output.join("output.wav"), wav).unwrap();
    fs::write(output.join("cpu0-blocks.jsonl"), cpu.static_kernel_blocks()).unwrap();
    if let Some(c) = cpu1 {
        fs::write(output.join("cpu1-blocks.jsonl"), c.static_kernel_blocks()).unwrap();
    }
    println!(
        "totalwall={:.6} frames={} pcm={:016x} lcd={:016x} flash={:016x} guestcycles={}",
        start.elapsed().as_secs_f64(),
        pcm.len() / 4,
        hash(pcm),
        hash(soc.lcd.fb.iter().flat_map(|p| p.to_le_bytes())),
        hash(soc.flash.mem.iter().copied()),
        soc.periph.cycles
    );
}
