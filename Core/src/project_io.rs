//! Typed, bounded file bridge for the exact compiled SLOOP source.
use super::*;
#[cfg(fm1_native_sloop)]
unsafe fn sloop<'a>(m: *mut Instrument) -> Option<&'a mut native_sloop::Native> {
    match m.as_mut()? {
        Instrument::Native(n) if n.kind() == 2 => Some(n),
        _ => None,
    }
}
macro_rules! read {
    ($name:ident,$method:ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $name(
            m: *mut Instrument,
            id: u32,
            out: *mut u8,
            capacity: usize,
        ) -> i32 {
            if out.is_null() || capacity > 65536 {
                return -1;
            }
            #[cfg(fm1_native_sloop)]
            if let Some(n) = sloop(m) {
                return catch_unwind(AssertUnwindSafe(|| n.$method(id, out, capacity as u32)))
                    .unwrap_or(-1);
            }
            -1
        }
    };
}
macro_rules! write {
    ($name:ident,$method:ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $name(
            m: *mut Instrument,
            id: u32,
            data: *const u8,
            len: usize,
        ) -> i32 {
            if data.is_null() || len > 65536 {
                return -1;
            }
            #[cfg(fm1_native_sloop)]
            if let Some(n) = sloop(m) {
                return catch_unwind(AssertUnwindSafe(|| n.$method(id, data, len as u32)))
                    .unwrap_or(-1);
            }
            -1
        }
    };
}
read!(instrument_sloop_object_read, file_object_read);
write!(instrument_sloop_object_write, file_object_write);
#[no_mangle]
pub unsafe extern "C" fn instrument_sloop_arrangement_read(
    m: *mut Instrument,
    out: *mut u8,
    capacity: usize,
) -> i32 {
    if out.is_null() || capacity < 43 || capacity > 256 {
        return -1;
    }
    #[cfg(fm1_native_sloop)]
    if let Some(n) = sloop(m) {
        return catch_unwind(AssertUnwindSafe(|| {
            n.file_arrangement_read(out, capacity as u32)
        }))
        .unwrap_or(-1);
    }
    -1
}
#[no_mangle]
pub unsafe extern "C" fn instrument_sloop_arrangement_write(
    m: *mut Instrument,
    data: *const u8,
    len: usize,
) -> i32 {
    if data.is_null() || !(13..=43).contains(&len) {
        return -1;
    }
    #[cfg(fm1_native_sloop)]
    if let Some(n) = sloop(m) {
        return catch_unwind(AssertUnwindSafe(|| {
            n.file_arrangement_write(data, len as u32)
        }))
        .unwrap_or(-1);
    }
    -1
}
#[no_mangle]
pub unsafe extern "C" fn instrument_sloop_sample_read(
    m: *mut Instrument,
    slot: u32,
    out: *mut u8,
    capacity: usize,
) -> i32 {
    if out.is_null() || capacity != 81920 {
        return -1;
    }
    #[cfg(fm1_native_sloop)]
    if let Some(n) = sloop(m) {
        return catch_unwind(AssertUnwindSafe(|| {
            n.file_sample_read(slot, out, capacity as u32)
        }))
        .unwrap_or(-1);
    }
    -1
}
#[no_mangle]
pub unsafe extern "C" fn instrument_sloop_sample_write(
    m: *mut Instrument,
    slot: u32,
    data: *const u8,
    len: usize,
) -> i32 {
    if data.is_null() || len != 81920 {
        return -1;
    }
    #[cfg(fm1_native_sloop)]
    if let Some(n) = sloop(m) {
        return catch_unwind(AssertUnwindSafe(|| {
            n.file_sample_write(slot, data, len as u32)
        }))
        .unwrap_or(-1);
    }
    -1
}
#[no_mangle]
pub unsafe extern "C" fn instrument_sloop_transport(m: *mut Instrument, play: bool) -> bool {
    #[cfg(fm1_native_sloop)]
    if let Some(n) = sloop(m) {
        return catch_unwind(AssertUnwindSafe(|| {
            n.file_transport(play);
            true
        }))
        .unwrap_or(false);
    }
    false
}

#[no_mangle]
pub unsafe extern "C" fn instrument_sloop_commit(m: *mut Instrument) -> i32 {
    #[cfg(fm1_native_sloop)]
    if let Some(n) = sloop(m) {
        return catch_unwind(AssertUnwindSafe(|| n.file_commit())).unwrap_or(-1);
    }
    -1
}

#[cfg(all(test, fm1_native_sloop))]
mod tests {
    use super::*;
    extern "C" {
        fn slp_global_set(id: u32, value: i32);
        fn slp_arr_do(op: u32, arg: u32) -> i32;
    }
    unsafe fn create() -> *mut Instrument {
        let source = std::path::PathBuf::from(std::env::var_os("FM1_NATIVE_SLOOP").unwrap());
        let package = std::fs::read(source.join("docs/firmware/sloop-2.8.fwsc")).unwrap();
        let mut error = [0u8; 512];
        let m = instrument_create(package.as_ptr(), package.len(), error.as_mut_ptr(), 512);
        assert!(!m.is_null(), "{}", String::from_utf8_lossy(&error));
        assert_eq!(instrument_native_kind(m), 2);
        m
    }
    unsafe fn object(m: *mut Instrument, id: u32) -> Vec<u8> {
        let mut bytes = vec![0; 65536];
        let n = instrument_sloop_object_read(m, id, bytes.as_mut_ptr(), bytes.len());
        assert!(n >= 0, "object{id}");
        bytes.truncate(n as usize);
        bytes
    }
    unsafe fn put(m: *mut Instrument, id: u32, bytes: &[u8]) {
        let empty = [0u8];
        let pointer = if bytes.is_empty() {
            empty.as_ptr()
        } else {
            bytes.as_ptr()
        };
        assert_eq!(
            instrument_sloop_object_write(m, id, pointer, bytes.len()),
            0,
            "object{id}"
        );
    }
    fn crc32(bytes: &[u8]) -> u32 {
        let mut crc = !0u32;
        for b in bytes {
            crc ^= *b as u32;
            for _ in 0..8 {
                crc = (crc >> 1) ^ (0xedb88320u32.wrapping_mul(crc & 1));
            }
        }
        !crc
    }
    #[test]
    fn typed_snapshot_retains_unsaved_loop_dirty_sections_and_durable_reopen() {
        unsafe {
            let m = create();
            let initial = object(m, 0);
            let mut baseline = vec![0; 1 << 20];
            assert_eq!(
                instrument_flash(m, baseline.as_mut_ptr(), baseline.len()),
                baseline.len()
            );
            slp_global_set(0, 137);
            assert_eq!(slp_arr_do(1, 0), 0); // A in RAM; no idle flash tick.
            slp_global_set(0, 149);
            let objects: Vec<Vec<u8>> = (0..12).map(|id| object(m, id)).collect();
            assert_ne!(objects[0], initial);
            assert_ne!(objects[2], initial);
            assert_ne!(objects[0], objects[2]);
            let mut unchanged = vec![0; 1 << 20];
            instrument_flash(m, unchanged.as_mut_ptr(), unchanged.len());
            assert_eq!(
                baseline, unchanged,
                "capture must not force-save or mutate the source"
            );
            let copy = create();
            assert!(instrument_restore(copy, baseline.as_ptr(), baseline.len()));
            assert!(instrument_sloop_transport(copy, false));
            for id in (1..12).chain([0]) {
                put(copy, id as u32, &objects[id]);
            }
            assert_eq!(instrument_sloop_commit(copy), 0);
            assert_eq!(object(copy, 0), objects[0]);
            assert_eq!(object(copy, 2), objects[2]);
            let mut saved = vec![0; 1 << 20];
            instrument_flash(copy, saved.as_mut_ptr(), saved.len());
            let reopened = create();
            assert!(instrument_restore(reopened, saved.as_ptr(), saved.len()));
            assert_eq!(object(reopened,0),objects[0],"typed working object must survive immediate relaunch, not a 20-second autosave wait");
            assert_eq!(object(reopened, 2), objects[2]);
            assert_eq!(
                object(m, 0),
                objects[0],
                "independent imports must not change the source instance"
            );
            instrument_destroy(reopened);
            instrument_destroy(copy);
            instrument_destroy(m);
        }
    }
    #[test]
    fn sample_slots_validate_crc_bounds_and_preserve_unrelated_bytes() {
        unsafe {
            let m = create();
            let _ = object(m, 0);
            let mut image = vec![255u8; 81920];
            image[0..512].fill(0);
            image[0..4].copy_from_slice(&0x504d5346u32.to_le_bytes());
            image[4..6].copy_from_slice(&1u16.to_le_bytes());
            image[6] = 1;
            image[16..20].copy_from_slice(&4u32.to_le_bytes());
            image[512..516].copy_from_slice(&[0x11, 0x22, 0x33, 0x44]);
            let crc = crc32(&image[512..516]);
            image[20..24].copy_from_slice(&crc.to_le_bytes());
            image[36..40].copy_from_slice(&8u32.to_le_bytes()); // zone.n
            image[44..48].copy_from_slice(&7u32.to_le_bytes()); // zone.le
            image[48..52].copy_from_slice(&32768u32.to_le_bytes());
            image[57] = 0;
            image[58] = 127;
            image[59] = 0;
            let mut before = vec![0; 1 << 20];
            instrument_flash(m, before.as_mut_ptr(), before.len());
            for slot in 0..4 {
                assert_eq!(
                    instrument_sloop_sample_write(m, slot, image.as_ptr(), image.len()),
                    0
                );
                let mut read = vec![0; 81920];
                assert_eq!(
                    instrument_sloop_sample_read(m, slot, read.as_mut_ptr(), read.len()),
                    81920
                );
                assert_eq!(read, image);
                let mut corrupt = image.clone();
                corrupt[513] ^= 1;
                assert_eq!(
                    instrument_sloop_sample_write(m, slot, corrupt.as_ptr(), corrupt.len()),
                    2
                );
                instrument_sloop_sample_read(m, slot, read.as_mut_ptr(), read.len());
                assert_eq!(read, image, "rejected writes must not mutate slots");
            }
            assert_eq!(
                instrument_sloop_sample_write(m, 4, image.as_ptr(), image.len()),
                1
            );
            assert_eq!(
                instrument_sloop_sample_write(m, 0, image.as_ptr(), 81919),
                -1
            );
            let mut after = vec![0; 1 << 20];
            instrument_flash(m, after.as_mut_ptr(), after.len());
            for i in 0..before.len() {
                if !((0xa0000..0xdc000).contains(&i) || (0xe7000..0xfb000).contains(&i)) {
                    assert_eq!(before[i], after[i], "byte {i:x}");
                }
            }
            instrument_destroy(m);
        }
    }
    #[test]
    fn empty_midi_object_clears_old_flash_map_and_survives_reopen() {
        unsafe {
            let source = create();
            let _ = object(source, 0);
            let mut map = vec![0u8; 40];
            map[32..].copy_from_slice(&[5, 2, 3, 10, 2, 0, 0, 0]);
            put(source, 10, &map);
            assert_eq!(object(source, 10), map);
            let mut baseline = vec![0; 1 << 20];
            instrument_flash(source, baseline.as_mut_ptr(), baseline.len());
            slp_global_set(33, 1); // G_CH1: ordinary live setting, no idle save.
            let mut pcm = vec![0f32; 1024];
            for _ in 0..4 {
                instrument_render(source, pcm.as_mut_ptr(), 512);
            }
            assert!(object(source, 10).is_empty());
            let mut still_old = vec![0; 1 << 20];
            instrument_flash(source, still_old.as_mut_ptr(), still_old.len());
            assert_eq!(still_old, baseline);
            let copy = create();
            assert!(instrument_restore(copy, baseline.as_ptr(), baseline.len()));
            assert_eq!(object(copy, 10), map);
            put(copy, 10, &[]);
            assert!(object(copy, 10).is_empty());
            let mut saved = vec![0; 1 << 20];
            instrument_flash(copy, saved.as_mut_ptr(), saved.len());
            let reopened = create();
            assert!(instrument_restore(reopened, saved.as_ptr(), saved.len()));
            assert!(object(reopened, 10).is_empty());
            instrument_destroy(source);
            instrument_destroy(copy);
            instrument_destroy(reopened);
        }
    }
    #[test]
    fn song_playback_capture_rejects_parked_loop_then_stop_restores_it() {
        unsafe {
            let m = create();
            let _ = object(m, 0);
            slp_global_set(0, 137);
            assert_eq!(slp_arr_do(1, 0), 0);
            slp_global_set(0, 149);
            let working = object(m, 0);
            let arrangement = [1u8, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1];
            assert_eq!(
                instrument_sloop_arrangement_write(m, arrangement.as_ptr(), arrangement.len()),
                0
            );
            assert!(instrument_sloop_transport(m, true));
            let mut pcm = vec![0f32; 1024];
            instrument_render(m, pcm.as_mut_ptr(), 512);
            let mut bytes = vec![0u8; 65536];
            assert_eq!(
                instrument_sloop_object_read(m, 0, bytes.as_mut_ptr(), bytes.len()),
                -1
            );
            assert!(instrument_sloop_transport(m, false));
            instrument_render(m, pcm.as_mut_ptr(), 512);
            assert_eq!(
                object(m, 0),
                working,
                "STOP must recover the underlying loop before capture"
            );
            instrument_destroy(m);
        }
    }
    #[test]
    fn malformed_and_unsupported_bridges_fail_without_dereferencing() {
        unsafe {
            assert_eq!(instrument_sloop_commit(std::ptr::null_mut()), -1);
            assert!(!instrument_sloop_transport(std::ptr::null_mut(), true));
            assert_eq!(
                instrument_sloop_object_write(std::ptr::null_mut(), 0, std::ptr::null(), 0),
                -1
            );
            let m = create();
            let original = object(m, 0);
            let bad = [0u8; 13];
            assert_ne!(
                instrument_sloop_arrangement_write(m, bad.as_ptr(), bad.len()),
                0
            );
            assert_eq!(object(m, 0), original);
            instrument_destroy(m);
        }
    }
}
