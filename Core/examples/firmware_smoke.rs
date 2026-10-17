use fm1_ios_core::*;
use std::{env,fs,time::Instant};
fn digest(bytes: impl IntoIterator<Item=u8>) -> u64 {
    bytes.into_iter().fold(0xcbf29ce484222325, |h, b| (h ^ b as u64).wrapping_mul(0x100000001b3))
}
fn main(){
    for path in env::args().skip(1){
        let bytes=fs::read(&path).unwrap();let mut err=[0u8;512];
        let m=unsafe{instrument_create(bytes.as_ptr(),bytes.len(),err.as_mut_ptr(),err.len())};
        assert!(!m.is_null(),"{}: {}",path,String::from_utf8_lossy(&err));
        let start=Instant::now();let mut audio=[0f32;1024];let mut peak=0f32;let mut energy=0f64;let mut frames=0;
        let mut pcm=Vec::new();
        for block in 0..900 {
            if block==400 {unsafe{instrument_key(m,21,true)}} // middle C
            if block==700 {unsafe{instrument_key(m,21,false)}}
            let n=unsafe{instrument_render(m,audio.as_mut_ptr(),512)};frames+=n;
            if block>=400 {for &s in &audio {peak=peak.max(s.abs());energy+=(s as f64).powi(2);pcm.extend_from_slice(&((s*32767.0) as i16).to_le_bytes());}}
        }
        let mut pixels=vec![0u32;240*240];let mut leds=[0f32;41];
        let state=unsafe{instrument_snapshot(m,pixels.as_mut_ptr(),leds.as_mut_ptr())};
        let changes=pixels.iter().filter(|&&p|p!=0xff000000).count();
        let n=unsafe{instrument_flash(m,std::ptr::null_mut(),0)};let mut flash=vec![0u8;n];unsafe{instrument_flash(m,flash.as_mut_ptr(),n);}
        let lcd_hash=digest(pixels.iter().flat_map(|p|p.to_le_bytes()));
        let flash_hash=digest(flash.iter().copied());
        assert!(unsafe{instrument_restore(m,flash.as_ptr(),n)});
        if let Ok(directory)=env::var("FM1_KERNEL_EXPORT") {
            let name=std::path::Path::new(&path).file_stem().unwrap().to_string_lossy();
            fs::create_dir_all(&directory).unwrap();
            fs::write(std::path::Path::new(&directory).join(format!("{name}.jsonl")),unsafe{&*m}.static_kernel_blocks()).unwrap();
        }
        unsafe{instrument_destroy(m)};
        let elapsed=start.elapsed().as_secs_f64();
        println!("{}: state={} nonblack={} frames={} peak={:.4} energy={:.3} wall={:.2}s audio={:.2}s ratio={:.2}x",path,state,changes,frames,peak,energy,elapsed,frames as f64/44100.0,frames as f64/44100.0/elapsed);
        println!("  deterministic fingerprints: pcm={:016x} lcd={lcd_hash:016x} flash={flash_hash:016x}",digest(pcm.iter().copied()));
        assert_eq!(state,1,"firmware halted");assert!(changes>100,"display blank");assert!(peak>0.001,"no note audio");
        let mut wav=Vec::new();let len=pcm.len() as u32;
        wav.extend_from_slice(b"RIFF");wav.extend_from_slice(&(36+len).to_le_bytes());wav.extend_from_slice(b"WAVEfmt ");wav.extend_from_slice(&16u32.to_le_bytes());wav.extend_from_slice(&1u16.to_le_bytes());wav.extend_from_slice(&2u16.to_le_bytes());wav.extend_from_slice(&44100u32.to_le_bytes());wav.extend_from_slice(&176400u32.to_le_bytes());wav.extend_from_slice(&4u16.to_le_bytes());wav.extend_from_slice(&16u16.to_le_bytes());wav.extend_from_slice(b"data");wav.extend_from_slice(&len.to_le_bytes());wav.extend(pcm);
        fs::write(format!("{}.wav",path),wav).unwrap();
    }
}
