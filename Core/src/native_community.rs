//! Public fingerprints select only signed, source-compiled community engines.
//! ABI declarations are generated from the same verified descriptor as the C archive.
include!(concat!(env!("OUT_DIR"), "/community_registry.rs"));

#[cfg(test)]
mod tests {
    use super::*;
    use crate::native_sloop::Native;
    use std::{env, path::PathBuf};
    fn package(filename: &str) -> Vec<u8> {
        std::fs::read(PathBuf::from(env::var_os("FM1_NATIVE_COMMUNITY").unwrap()).join(filename))
            .unwrap()
    }
    fn api(bytes: &[u8]) -> crate::native_sloop::Api {
        for_digest(crate::sha256::digest(bytes), bytes.len()).unwrap()
    }
    fn render(m: &mut Native, frames: usize) -> Vec<f32> {
        let mut out = Vec::new();
        let mut left = frames;
        for chunk in [1usize, 31, 257, 513].into_iter().cycle() {
            let n = left.min(chunk);
            let mut b = vec![0.; n * 2];
            assert_eq!(m.render(&mut b), n);
            assert!(b.iter().all(|v| v.is_finite() && v.abs() <= 1.));
            out.extend(b);
            left -= n;
            if left == 0 {
                break;
            }
        }
        out
    }
    fn audition(m: &mut Native, kind: u32) -> Vec<f32> {
        render(m, 88200);
        if kind == 15 {
            m.key(8, true);
            render(m, 2048);
            m.key(8, false);
            render(m, 2048);
        }
        for key in 14..41 {
            m.key(key, true);
        }
        let mut audio = render(m, 44100);
        if !audio.iter().any(|v| v.abs() > 0.0001) {
            m.key(12, true);
            render(m, 1024);
            m.key(12, false);
            audio = render(m, 44100);
        }
        assert!(
            audio.iter().filter(|v| v.abs() > 0.0001).count() > 100,
            "kind{kind} must synthesize real PCM"
        );
        audio
    }
    #[test]
    fn exact_packages_route_and_changed_packages_are_rejected() {
        for &(kind, file) in FIXTURES {
            let mut bytes = package(file);
            let digest = crate::sha256::digest(&bytes);
            assert_eq!(for_digest(digest, bytes.len()).unwrap().kind, kind);
            assert_eq!(for_digest(digest, 0).unwrap().kind, kind);
            assert!(for_digest(digest, bytes.len() - 1).is_none());
            let m = crate::Instrument::load(&bytes).unwrap();
            assert_eq!(unsafe { crate::instrument_native_kind(&m) }, kind);
            bytes[100] ^= 1;
            assert!(for_digest(crate::sha256::digest(&bytes), bytes.len()).is_none());
            #[cfg(feature = "store-native")]
            assert!(crate::Instrument::load(&bytes).is_err());
        }
    }
    #[test]
    fn whole_firmwares_draw_sound_and_roundtrip_owned_flash() {
        for &(kind, file) in FIXTURES {
            let bytes = package(file);
            let mut flash = vec![255; 1 << 20];
            flash[123] = kind as u8;
            let mut m = Native::with_api(&flash, api(&bytes)).unwrap();
            audition(&mut m, kind);
            let mut pixels = vec![0u32; 240 * 240];
            let mut leds = [0.; 41];
            unsafe {
                m.snapshot(pixels.as_mut_ptr(), leds.as_mut_ptr());
            }
            assert!(
                pixels.windows(2).any(|p| p[0] != p[1]),
                "kind{kind} must draw LCD"
            );
            m.release_all();
            render(&mut m, 44100);
            unsafe {
                assert_eq!(m.flash(flash.as_mut_ptr(), flash.len()), flash.len());
            }
            assert_eq!(flash[123], kind as u8);
            assert!(!m.restore(&flash[..1024]));
            assert!(m.restore(&flash));
            let mut copy = vec![0; flash.len()];
            unsafe {
                m.flash(copy.as_mut_ptr(), copy.len());
            }
            assert_eq!(copy, flash);
        }
    }
    #[test]
    fn mutable_dsp_and_controls_are_isolated_between_instances() {
        for &(kind, file) in FIXTURES {
            let bytes = package(file);
            let blank = vec![255; 1 << 20];
            let a = api(&bytes);
            let mut first = Native::with_api(&blank, a).unwrap();
            let mut neighbor = Native::with_api(&blank, a).unwrap();
            let mut reference = Native::with_api(&blank, a).unwrap();
            audition(&mut first, kind);
            audition(&mut neighbor, kind);
            audition(&mut reference, kind);
            assert_eq!(
                render(&mut neighbor, 4096),
                render(&mut reference, 4096),
                "kind{kind}"
            );
            first.encoder(2, 7);
            first.key(14, true);
            render(&mut first, 8192);
            assert_eq!(
                render(&mut neighbor, 8192),
                render(&mut reference, 8192),
                "kind{kind} shared mutable state"
            );
        }
    }
}
