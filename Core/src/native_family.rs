//! Exact package/source pins select separate compiled firmware implementations.
use super::native_sloop::Api;
#[cfg(fm1_native_family)]
mod felucca {
    use super::Api;
    extern "C" {
        fn fel_state_size() -> u64;
        fn fel_state_init(state: *mut u8) -> i32;
        fn fel_bind(state: *mut u8);
        fn fel_init();
        fn fel_ctl() -> u32;
        fn fel_rate() -> u32;
        fn fel_render(out: *mut i32, frames: u32);
        fn fel_draw(out: *mut u16);
        fn fel_physical_key(id: u32, down: i32);
        fn fel_release_all();
        fn fel_physical_encoder(id: u32, delta: i32);
        fn fel_physical_leds(out: *mut f32);
        fn fel_volume(value: u32);
        fn fel_flash_load(bytes: *const u8);
        fn fel_flash_copy(bytes: *mut u8);
        fn fel_workload_metrics(out: *mut u64, capacity: u32) -> u32;
    }
    pub const API: Api = Api {
        kind: 3,
        flash_size: 1048576,
        alignment: 16,
        state_size: fel_state_size,
        state_init: fel_state_init,
        bind: fel_bind,
        init: fel_init,
        ctl: fel_ctl,
        rate: fel_rate,
        render: fel_render,
        draw: fel_draw,
        key: fel_physical_key,
        release_all: fel_release_all,
        encoder: fel_physical_encoder,
        leds: fel_physical_leds,
        volume: fel_volume,
        flash_load: fel_flash_load,
        flash_copy: fel_flash_copy,
        metrics: fel_workload_metrics,
        destroy: None,
    };
}
#[cfg(fm1_native_family)]
mod x0x {
    use super::Api;
    extern "C" {
        fn x0x_state_size() -> u64;
        fn x0x_state_init(state: *mut u8) -> i32;
        fn x0x_bind(state: *mut u8);
        fn x0x_init();
        fn x0x_ctl() -> u32;
        fn x0x_rate() -> u32;
        fn x0x_render(out: *mut i32, frames: u32);
        fn x0x_draw(out: *mut u16);
        fn x0x_physical_key(id: u32, down: i32);
        fn x0x_release_all();
        fn x0x_physical_encoder(id: u32, delta: i32);
        fn x0x_physical_leds(out: *mut f32);
        fn x0x_volume(value: u32);
        fn x0x_flash_load(bytes: *const u8);
        fn x0x_flash_copy(bytes: *mut u8);
        fn x0x_workload_metrics(out: *mut u64, capacity: u32) -> u32;
    }
    pub const API: Api = Api {
        kind: 4,
        flash_size: 1048576,
        alignment: 16,
        state_size: x0x_state_size,
        state_init: x0x_state_init,
        bind: x0x_bind,
        init: x0x_init,
        ctl: x0x_ctl,
        rate: x0x_rate,
        render: x0x_render,
        draw: x0x_draw,
        key: x0x_physical_key,
        release_all: x0x_release_all,
        encoder: x0x_physical_encoder,
        leds: x0x_physical_leds,
        volume: x0x_volume,
        flash_load: x0x_flash_load,
        flash_copy: x0x_flash_copy,
        metrics: x0x_workload_metrics,
        destroy: None,
    };
}
#[cfg(fm1_native_family)]
mod melodee {
    use super::Api;
    extern "C" {
        fn mel_state_size() -> u64;
        fn mel_state_init(state: *mut u8) -> i32;
        fn mel_bind(state: *mut u8);
        fn mel_init();
        fn mel_ctl() -> u32;
        fn mel_rate() -> u32;
        fn mel_render(out: *mut i32, frames: u32);
        fn mel_draw(out: *mut u16);
        fn mel_physical_key(id: u32, down: i32);
        fn mel_release_all();
        fn mel_physical_encoder(id: u32, delta: i32);
        fn mel_physical_leds(out: *mut f32);
        fn mel_volume(value: u32);
        fn mel_flash_load(bytes: *const u8);
        fn mel_flash_copy(bytes: *mut u8);
        fn mel_workload_metrics(out: *mut u64, capacity: u32) -> u32;
    }
    pub const API: Api = Api {
        kind: 5,
        flash_size: 1048576,
        alignment: 16,
        state_size: mel_state_size,
        state_init: mel_state_init,
        bind: mel_bind,
        init: mel_init,
        ctl: mel_ctl,
        rate: mel_rate,
        render: mel_render,
        draw: mel_draw,
        key: mel_physical_key,
        release_all: mel_release_all,
        encoder: mel_physical_encoder,
        leds: mel_physical_leds,
        volume: mel_volume,
        flash_load: mel_flash_load,
        flash_copy: mel_flash_copy,
        metrics: mel_workload_metrics,
        destroy: None,
    };
}
#[cfg(fm1_native_official_preview)]
mod official {
    use super::Api;
    extern "C" {
        fn ofp_state_size() -> u64;
        fn ofp_state_init(state: *mut u8) -> i32;
        fn ofp_bind(state: *mut u8);
        fn ofp_init();
        fn ofp_ctl() -> u32;
        fn ofp_rate() -> u32;
        fn ofp_render(out: *mut i32, frames: u32);
        fn ofp_draw(out: *mut u16);
        fn ofp_physical_key(id: u32, down: i32);
        fn ofp_release_all();
        fn ofp_physical_encoder(id: u32, delta: i32);
        fn ofp_physical_leds(out: *mut f32);
        fn ofp_volume(value: u32);
        fn ofp_flash_load(bytes: *const u8);
        fn ofp_flash_copy(bytes: *mut u8);
        fn ofp_workload_metrics(out: *mut u64, capacity: u32) -> u32;
        fn ofp_destroy();
    }
    pub const API: Api = Api {
        kind: 6,
        flash_size: 536576,
        alignment: 64,
        state_size: ofp_state_size,
        state_init: ofp_state_init,
        bind: ofp_bind,
        init: ofp_init,
        ctl: ofp_ctl,
        rate: ofp_rate,
        render: ofp_render,
        draw: ofp_draw,
        key: ofp_physical_key,
        release_all: ofp_release_all,
        encoder: ofp_physical_encoder,
        leds: ofp_physical_leds,
        volume: ofp_volume,
        flash_load: ofp_flash_load,
        flash_copy: ofp_flash_copy,
        metrics: ofp_workload_metrics,
        destroy: Some(ofp_destroy),
    };
}
#[cfg(fm1_native_skiff)]
mod skiff {
    use super::Api;
    extern "C" {
        fn skf_state_size() -> u64;
        fn skf_state_init(state: *mut u8) -> i32;
        fn skf_bind(state: *mut u8);
        fn skf_init();
        fn skf_ctl() -> u32;
        fn skf_rate() -> u32;
        fn skf_render(out: *mut i32, frames: u32);
        fn skf_draw(out: *mut u16);
        fn skf_physical_key(id: u32, down: i32);
        fn skf_release_all();
        fn skf_physical_encoder(id: u32, delta: i32);
        fn skf_physical_leds(out: *mut f32);
        fn skf_volume(value: u32);
        fn skf_flash_load(bytes: *const u8);
        fn skf_flash_copy(bytes: *mut u8);
        fn skf_workload_metrics(out: *mut u64, capacity: u32) -> u32;
    }
    pub const API: Api = Api {
        kind: 7,
        flash_size: 1048576,
        alignment: 16,
        state_size: skf_state_size,
        state_init: skf_state_init,
        bind: skf_bind,
        init: skf_init,
        ctl: skf_ctl,
        rate: skf_rate,
        render: skf_render,
        draw: skf_draw,
        key: skf_physical_key,
        release_all: skf_release_all,
        encoder: skf_physical_encoder,
        leds: skf_physical_leds,
        volume: skf_volume,
        flash_load: skf_flash_load,
        flash_copy: skf_flash_copy,
        metrics: skf_workload_metrics,
        destroy: None,
    };
}
#[cfg(fm1_native_expansion)]
mod fomni {
    use super::Api;
    extern "C" {
        fn omf_state_size() -> u64;
        fn omf_state_init(state: *mut u8) -> i32;
        fn omf_bind(state: *mut u8);
        fn omf_init();
        fn omf_ctl() -> u32;
        fn omf_rate() -> u32;
        fn omf_render(out: *mut i32, frames: u32);
        fn omf_draw(out: *mut u16);
        fn omf_physical_key(id: u32, down: i32);
        fn omf_release_all();
        fn omf_physical_encoder(id: u32, delta: i32);
        fn omf_physical_leds(out: *mut f32);
        fn omf_volume(value: u32);
        fn omf_flash_load(bytes: *const u8);
        fn omf_flash_copy(bytes: *mut u8);
        fn omf_workload_metrics(out: *mut u64, capacity: u32) -> u32;
    }
    pub const API: Api = Api {
        kind: 8,
        flash_size: 1048576,
        alignment: 16,
        state_size: omf_state_size,
        state_init: omf_state_init,
        bind: omf_bind,
        init: omf_init,
        ctl: omf_ctl,
        rate: omf_rate,
        render: omf_render,
        draw: omf_draw,
        key: omf_physical_key,
        release_all: omf_release_all,
        encoder: omf_physical_encoder,
        leds: omf_physical_leds,
        volume: omf_volume,
        flash_load: omf_flash_load,
        flash_copy: omf_flash_copy,
        metrics: omf_workload_metrics,
        destroy: None,
    };
}
#[cfg(fm1_native_expansion)]
mod jangada {
    use super::Api;
    extern "C" {
        fn jng_state_size() -> u64;
        fn jng_state_init(state: *mut u8) -> i32;
        fn jng_bind(state: *mut u8);
        fn jng_init();
        fn jng_ctl() -> u32;
        fn jng_rate() -> u32;
        fn jng_render(out: *mut i32, frames: u32);
        fn jng_draw(out: *mut u16);
        fn jng_physical_key(id: u32, down: i32);
        fn jng_release_all();
        fn jng_physical_encoder(id: u32, delta: i32);
        fn jng_physical_leds(out: *mut f32);
        fn jng_volume(value: u32);
        fn jng_flash_load(bytes: *const u8);
        fn jng_flash_copy(bytes: *mut u8);
        fn jng_workload_metrics(out: *mut u64, capacity: u32) -> u32;
    }
    pub const API: Api = Api {
        kind: 9,
        flash_size: 1048576,
        alignment: 16,
        state_size: jng_state_size,
        state_init: jng_state_init,
        bind: jng_bind,
        init: jng_init,
        ctl: jng_ctl,
        rate: jng_rate,
        render: jng_render,
        draw: jng_draw,
        key: jng_physical_key,
        release_all: jng_release_all,
        encoder: jng_physical_encoder,
        leds: jng_physical_leds,
        volume: jng_volume,
        flash_load: jng_flash_load,
        flash_copy: jng_flash_copy,
        metrics: jng_workload_metrics,
        destroy: None,
    };
}
pub(super) fn for_package(bytes: &[u8]) -> Option<Api> {
    for_digest(super::sha256::digest(bytes), bytes.len())
}
pub(super) fn for_digest(digest: [u8; 32], len: usize) -> Option<Api> {
    #[cfg(fm1_native_sloop)]
    if (len == 0 || len == 610035)
        && digest
            == [
                251, 105, 180, 49, 23, 144, 235, 126, 192, 148, 152, 190, 22, 174, 43, 113, 189,
                104, 24, 64, 226, 33, 192, 216, 207, 219, 38, 251, 95, 154, 41, 40,
            ]
    {
        return Some(super::native_sloop::SLOOP);
    }
    #[cfg(fm1_native_family)]
    if (len == 0 || len == 610090)
        && digest
            == [
                223, 243, 163, 143, 126, 91, 152, 51, 225, 90, 186, 50, 37, 88, 201, 72, 94, 158,
                66, 46, 63, 248, 19, 198, 22, 201, 27, 53, 132, 162, 217, 9,
            ]
    {
        return Some(felucca::API);
    }
    #[cfg(fm1_native_family)]
    if (len == 0 || len == 609684)
        && digest
            == [
                160, 194, 157, 235, 147, 12, 101, 241, 212, 11, 86, 145, 183, 214, 115, 248, 97,
                65, 139, 67, 139, 126, 101, 2, 124, 185, 198, 113, 230, 244, 79, 91,
            ]
    {
        return Some(x0x::API);
    }
    #[cfg(fm1_native_family)]
    if (len == 0 || len == 610545)
        && digest
            == [
                161, 143, 64, 214, 248, 200, 8, 123, 37, 241, 21, 171, 17, 40, 111, 133, 199, 240,
                67, 131, 222, 131, 98, 39, 196, 99, 198, 206, 71, 69, 206, 32,
            ]
    {
        return Some(melodee::API);
    }
    #[cfg(fm1_native_official_preview)]
    if (len == 0 || len == OFFICIAL_PREVIEW_PACKAGE_SIZE)
        && digest == OFFICIAL_PREVIEW_PACKAGE_SHA256
    {
        return Some(official::API);
    }
    #[cfg(fm1_native_expansion)]
    if (len == 0 || len == 609661)
        && digest
            == [
                113, 250, 131, 4, 185, 27, 255, 137, 7, 139, 253, 39, 233, 129, 237, 40, 202, 79,
                13, 60, 95, 64, 110, 143, 219, 90, 42, 178, 64, 251, 219, 181,
            ]
    {
        return Some(fomni::API);
    }
    #[cfg(fm1_native_expansion)]
    if (len == 0 || len == 610133)
        && digest
            == [
                195, 130, 227, 52, 5, 123, 209, 7, 41, 73, 64, 228, 86, 229, 193, 20, 7, 84, 145,
                123, 161, 82, 161, 149, 138, 243, 170, 22, 150, 51, 53, 136,
            ]
    {
        return Some(jangada::API);
    }
    #[cfg(fm1_native_skiff)]
    if (len == 0 || len == 610337)
        && digest
            == [
                6, 34, 167, 82, 232, 48, 71, 119, 192, 66, 204, 234, 7, 50, 186, 2, 62, 20, 19,
                186, 166, 219, 200, 114, 69, 118, 226, 236, 118, 222, 2, 224,
            ]
    {
        return Some(skiff::API);
    }
    None
}

#[cfg(all(test, fm1_native_family))]
mod tests {
    use super::*;
    use crate::native_sloop::Native;
    fn api(kind: u32) -> Api {
        match kind {
            3 => felucca::API,
            4 => x0x::API,
            5 => melodee::API,
            #[cfg(fm1_native_skiff)]
            7 => skiff::API,
            #[cfg(fm1_native_expansion)]
            8 => fomni::API,
            #[cfg(fm1_native_expansion)]
            9 => jangada::API,
            _ => panic!("kind"),
        }
    }
    fn kinds() -> Vec<u32> {
        let mut kinds = vec![3, 4, 5];
        #[cfg(fm1_native_skiff)]
        kinds.push(7);
        #[cfg(fm1_native_expansion)]
        kinds.extend([8, 9]);
        kinds
    }
    fn run(m: &mut Native, frames: usize) -> Vec<f32> {
        let mut out = Vec::with_capacity(frames * 2);
        let mut done = 0;
        for count in [1usize, 31, 257, 513].into_iter().cycle() {
            let n = count.min(frames - done);
            let mut b = vec![0.; n * 2];
            assert_eq!(m.render(&mut b), n);
            assert!(b.iter().all(|x| x.is_finite() && x.abs() <= 1.));
            out.extend(b);
            done += n;
            if done == frames {
                break;
            }
        }
        out
    }
    #[test]
    fn source_firmwares_sound_draw_and_roundtrip_complete_flash() {
        for kind in kinds() {
            let mut blank = vec![0xff; 1 << 20];
            blank[123] = kind as u8;
            let mut m = Native::with_api(&blank, api(kind)).unwrap();
            assert_eq!(m.kind(), kind);
            // Skiff's real boot splash suppresses keys for 400 ms; wait before input.
            run(&mut m, 22050);
            // Every note is exercised, including the drum-first X0X power-on page.
            for k in 14..41 {
                m.key(k, true);
            }
            let audio = run(&mut m, 44100);
            assert!(
                audio.iter().filter(|v| **v != 0.).count() > 100,
                "native {kind} must synthesize real PCM"
            );
            let mut screen = vec![0u32; 240 * 240];
            let mut leds = vec![0.; 41];
            unsafe {
                m.snapshot(screen.as_mut_ptr(), leds.as_mut_ptr());
            }
            assert!(
                screen.windows(2).any(|p| p[0] != p[1]),
                "native {kind} display"
            );
            m.release_all();
            run(&mut m, 44100);
            let mut flash = vec![0; 1 << 20];
            unsafe {
                assert_eq!(m.flash(flash.as_mut_ptr(), flash.len()), 1 << 20);
            }
            assert_eq!(flash[123], kind as u8, "unrelated firmware byte retained");
            assert!(!m.restore(&flash[..1024]));
            assert!(m.restore(&flash));
            let mut after = vec![0; flash.len()];
            unsafe {
                m.flash(after.as_mut_ptr(), after.len());
            }
            assert_eq!(
                flash, after,
                "complete raw flash must survive fresh instance restore"
            );
        }
    }
    #[test]
    fn source_instances_remain_independent_when_interleaved() {
        for kind in kinds() {
            let blank = vec![0xff; 1 << 20];
            let mut a = Native::with_api(&blank, api(kind)).unwrap();
            let mut b = Native::with_api(&blank, api(kind)).unwrap();
            let mut reference = Native::with_api(&blank, api(kind)).unwrap();
            run(&mut a, 22050);
            run(&mut b, 22050);
            run(&mut reference, 22050);
            // X0X's black keys trigger drums; its white keys edit steps.
            let first_key = if kind == 4 { 15 } else { 21 };
            let second_key = if kind == 4 { 17 } else { 26 };
            a.key(first_key, true);
            reference.key(first_key, true);
            b.key(second_key, true);
            let mut nonzero = 0;
            for _ in 0..20 {
                let expected = run(&mut reference, 513);
                nonzero += expected.iter().filter(|v| **v != 0.).count();
                run(&mut b, 257);
                assert_eq!(
                    run(&mut a, 513),
                    expected,
                    "native {kind} instance state leak"
                );
            }
            assert!(
                nonzero > 100,
                "native {kind}: isolation must compare real sound, not silence"
            );
        }
    }
    #[cfg(fm1_native_expansion)]
    #[test]
    fn new_source_projects_autosave_and_restore_the_edited_logical_state() {
        fn signature(m: &mut Native) -> u64 {
            let mut values = [0u64; 16];
            unsafe {
                m.metrics(values.as_mut_ptr(), 16);
            }
            values[12]
        }
        for kind in [8, 9] {
            let mut blank = vec![255; 1 << 20];
            blank[123] = 77;
            let mut original = Native::with_api(&blank, api(kind)).unwrap();
            run(&mut original, 1024);
            let initial = signature(&mut original);
            original.encoder(6, 1); // Physical PRESETS, one actual firmware edit.
            run(&mut original, 44100 * 30); // Original quiet/gap autosave policy.
            let edited = signature(&mut original);
            assert_ne!(
                initial, edited,
                "native {kind}: the physical knob must change the project"
            );
            let mut flash = vec![0; 1 << 20];
            unsafe {
                original.flash(flash.as_mut_ptr(), flash.len());
            }
            assert_ne!(flash, blank, "upstream storage must commit a real object");
            assert_eq!(flash[123], 77, "unrelated flash area survives the commit");
            drop(original);
            let mut reopened = Native::with_api(&flash, api(kind)).unwrap();
            run(&mut reopened, 1024);
            assert_eq!(
                signature(&mut reopened),
                edited,
                "native {kind}: edited project must reload semantically"
            );
        }
    }
    #[test]
    fn catalogue_native_hash_lookup_is_exact_and_rejects_renamed_content() {
        let root = std::path::PathBuf::from(
            std::env::var_os("FM1_NATIVE_FAMILY").expect("configured native source root"),
        );
        let mut cases = vec![
            (3, root.join("felucca-1.6.1.fwsc")),
            (4, root.join("x0x-1.1.0.fwsc")),
            (5, root.join("melodee-1.4.5.fwsc")),
        ];
        #[cfg(fm1_native_expansion)]
        {
            let extra = std::path::PathBuf::from(std::env::var_os("FM1_NATIVE_EXPANSION").unwrap());
            cases.extend([
                (8, extra.join("fomni-0.4.fwsc")),
                (9, extra.join("jangada-1.0.1.fwsc")),
            ]);
        }
        #[cfg(fm1_native_skiff)]
        {
            let extra = std::path::PathBuf::from(std::env::var_os("FM1_NATIVE_SKIFF").unwrap());
            cases.push((7, extra.parent().unwrap().join("skiff-1.4.fwsc")));
        }
        for (kind, path) in cases {
            let mut package = std::fs::read(path).unwrap();
            assert_eq!(for_package(&package).unwrap().kind, kind);
            let m = crate::Instrument::load(&package).unwrap();
            assert_eq!(unsafe { crate::instrument_native_kind(&m) }, kind);
            package[100] ^= 1;
            assert!(for_package(&package).is_none());
        }
    }
}

#[cfg(fm1_native_official_preview)]
const OFFICIAL_PREVIEW_PACKAGE_SIZE: usize = 492084;
#[cfg(fm1_native_official_preview)]
const OFFICIAL_PREVIEW_PACKAGE_SHA256: [u8; 32] = [
    126, 123, 109, 38, 1, 99, 205, 249, 215, 22, 247, 250, 180, 79, 25, 190, 96, 14, 222, 255, 205,
    57, 13, 231, 67, 112, 184, 60, 145, 127, 208, 198,
];
