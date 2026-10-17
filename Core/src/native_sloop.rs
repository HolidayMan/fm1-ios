//! Pinned source-native SLOOP execution; calls remain on the instance's serial worker.
use std::{
    alloc::{alloc_zeroed, dealloc, Layout},
    collections::VecDeque,
};
const FLASH: usize = 1 << 20;
const KEY_TRANSITION_CAPACITY: usize = 256;
#[derive(Clone, Copy)]
struct KeyTransition {
    id: u32,
    down: bool,
}
extern "C" {
    fn slp_state_size() -> u64;
    fn slp_state_init(state: *mut u8) -> i32;
    fn slp_bind(state: *mut u8);
    fn slp_init();
    fn slp_ctl() -> u32;
    fn slp_rate() -> u32;
    fn slp_render(out: *mut i32, frames: u32);
    fn slp_draw(out: *mut u16);
    fn slp_physical_key(id: u32, down: i32);
    fn slp_release_all();
    fn slp_physical_encoder(id: u32, delta: i32);
    fn slp_physical_leds(out: *mut f32);
    fn slp_volume(value: u32);
    fn slp_flash_load(bytes: *const u8);
    fn slp_flash_copy(bytes: *mut u8);
    fn slp_workload_metrics(out: *mut u64, capacity: u32) -> u32;
}

pub(super) struct Native {
    state: *mut u8,
    layout: Layout,
    initialized: bool,
    volume: u32,
    audio: VecDeque<i32>,
    block: Vec<i32>,
    pixels: Vec<u16>,
    key_transitions: VecDeque<KeyTransition>,
    desired_keys: u32,
    key_transition_drops: u64,
    key_queue_high_water: u64,
}
impl Native {
    pub fn new(flash: &[u8]) -> Result<Self, String> {
        if flash.len() != FLASH {
            return Err("Native SLOOP requires a complete 1 MiB flash image.".into());
        }
        let size = usize::try_from(unsafe { slp_state_size() })
            .map_err(|_| "Native SLOOP state size overflow")?;
        let layout =
            Layout::from_size_align(size, 16).map_err(|_| "Native SLOOP state layout invalid")?;
        let state = unsafe { alloc_zeroed(layout) };
        if state.is_null() {
            return Err("Cannot allocate native SLOOP state.".into());
        }
        if unsafe { slp_state_init(state) } == 0 {
            unsafe { dealloc(state, layout) };
            return Err("Native SLOOP state layout mismatch.".into());
        }
        unsafe {
            slp_bind(state);
            slp_flash_load(flash.as_ptr());
        }
        let ctl = unsafe { slp_ctl() } as usize;
        if ctl == 0 || ctl > 2048 || unsafe { slp_rate() } != 44100 {
            unsafe { dealloc(state, layout) };
            return Err("Native SLOOP audio format mismatch.".into());
        }
        Ok(Self {
            state,
            layout,
            initialized: false,
            volume: 716,
            audio: VecDeque::new(),
            block: vec![0; ctl * 2],
            pixels: vec![0; 240 * 240],
            key_transitions: VecDeque::with_capacity(KEY_TRANSITION_CAPACITY),
            desired_keys: 0,
            key_transition_drops: 0,
            key_queue_high_water: 0,
        })
    }
    fn bind(&self) {
        unsafe { slp_bind(self.state) }
    }
    fn start(&mut self) {
        self.bind();
        if !self.initialized {
            unsafe {
                slp_init();
                slp_volume(self.volume)
            };
            self.initialized = true;
        }
    }
    pub fn render(&mut self, out: &mut [f32]) -> usize {
        self.start();
        while self.audio.len() < out.len() {
            self.apply_key_transitions();
            unsafe { slp_render(self.block.as_mut_ptr(), (self.block.len() / 2) as u32) };
            self.audio.extend(self.block.iter().copied());
        }
        for value in out.iter_mut() {
            // audio.c writes Q15 << 7; the original SoC extracts signed upper 16 bits.
            *value = (self.audio.pop_front().unwrap() >> 1).clamp(-32768, 32767) as f32 / 32768.;
        }
        out.len() / 2
    }
    /// Preserve opposite edges that arrive between host audio chunks. Different
    /// keys coalesce into one CTL block, while the same key changes at most once
    /// per block. This adds at most one firmware CTL to an ordinary quick tap.
    fn apply_key_transitions(&mut self) {
        let mut changed = 0u32;
        while let Some(event) = self.key_transitions.front().copied() {
            let bit = 1u32 << (event.id - 14);
            if changed & bit != 0 {
                break;
            }
            self.key_transitions.pop_front();
            changed |= bit;
            unsafe {
                slp_physical_key(event.id, i32::from(event.down));
            }
        }
    }
    fn make_key_queue_room(&mut self) {
        if self.key_transitions.len() < KEY_TRANSITION_CAPACITY {
            return;
        }
        // Overload cannot retain an unbounded event stream. Remove one complete
        // cycle of a key (net state unchanged), account for both dropped edges,
        // and always accept the latest release so no key can remain stuck.
        let mut first = [usize::MAX; 27];
        for (index, event) in self.key_transitions.iter().enumerate() {
            let key = (event.id - 14) as usize;
            if first[key] != usize::MAX {
                self.key_transitions.remove(index);
                self.key_transitions.remove(first[key]);
                self.key_transition_drops += 2;
                return;
            }
            first[key] = index;
        }
        unreachable!("full key queue must contain a complete opposite-edge pair");
    }
    pub fn key(&mut self, id: u32, down: bool) {
        self.start();
        if id < 14 {
            unsafe {
                slp_physical_key(id, i32::from(down));
            }
            return;
        }
        if id >= 41 {
            return;
        }
        let bit = 1u32 << (id - 14);
        if (self.desired_keys & bit != 0) == down {
            return;
        }
        self.make_key_queue_room();
        if down {
            self.desired_keys |= bit;
        } else {
            self.desired_keys &= !bit;
        }
        self.key_transitions.push_back(KeyTransition { id, down });
        self.key_queue_high_water = self
            .key_queue_high_water
            .max(self.key_transitions.len() as u64);
    }
    pub fn encoder(&mut self, id: u32, delta: i32) {
        self.start();
        if id < 7 {
            unsafe { slp_physical_encoder(id, delta.clamp(-32, 32)) }
        }
    }
    pub fn release_all(&mut self) {
        self.key_transitions.clear();
        self.desired_keys = 0;
        // A never-started instance has no physical state to release. Avoid booting
        // a just-loaded firmware merely because the host is suspending it.
        if self.initialized {
            self.bind();
            unsafe { slp_release_all() }
        }
    }
    pub fn volume(&mut self, value: u32) {
        self.volume = value.min(1023);
        if self.initialized {
            self.bind();
            unsafe { slp_volume(self.volume) }
        }
    }
    pub unsafe fn snapshot(&mut self, pixels: *mut u32, leds: *mut f32) -> u32 {
        self.start();
        slp_draw(self.pixels.as_mut_ptr());
        if !pixels.is_null() {
            for (i, &p) in self.pixels.iter().enumerate() {
                let p = u16::from_be(p) as u32;
                let r = ((p >> 11) & 31) * 255 / 31;
                let g = ((p >> 5) & 63) * 255 / 63;
                let b = (p & 31) * 255 / 31;
                *pixels.add(i) = 0xff000000 | (b << 16) | (g << 8) | r;
            }
        }
        if !leds.is_null() {
            slp_physical_leds(leds);
        }
        1
    }
    pub unsafe fn flash(&mut self, out: *mut u8, len: usize) -> usize {
        self.bind();
        if !out.is_null() && len == FLASH {
            slp_flash_copy(out);
        }
        FLASH
    }
    pub unsafe fn metrics(&mut self, out: *mut u64, capacity: u32) -> u32 {
        self.bind();
        let n = slp_workload_metrics(out, capacity);
        if n > 13 {
            *out.add(13) = self.key_transition_drops;
        }
        if n > 14 {
            *out.add(14) = self.key_queue_high_water;
        }
        if n > 15 {
            *out.add(15) = self.key_transitions.len() as u64;
        }
        n
    }
    pub fn restore(&mut self, bytes: &[u8]) -> bool {
        // New clean state reloads every persisted object and sample on its first use.
        // Failure leaves the previous instance intact.
        match Self::new(bytes) {
            Ok(mut next) => {
                next.volume = self.volume;
                std::mem::swap(self, &mut next);
                true
            }
            Err(_) => false,
        }
    }
}
impl Drop for Native {
    fn drop(&mut self) {
        unsafe { dealloc(self.state, self.layout) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    extern "C" {
        fn slp_set_engine(track: u32, engine: u32);
        fn slp_param_set(track: u32, id: u32, value: i32);
        fn slp_pe0() -> u32;
        fn slp_ui_frames() -> u32;
        fn slp_selected() -> u32;
        fn slp_playing() -> i32;
        fn slp_armed() -> u32;
        fn slp_object_get(id: u32, bytes: *mut u8, len: u32) -> i32;
    }
    fn blank() -> Vec<u8> {
        vec![0xff; FLASH]
    }
    fn render_chunks(m: &mut Native, chunks: &[usize], frames: usize) -> Vec<f32> {
        let mut out = Vec::new();
        let mut i = 0;
        while out.len() < frames * 2 {
            let n = chunks[i % chunks.len()].min(frames - out.len() / 2);
            let mut block = vec![0.; n * 2];
            assert_eq!(m.render(&mut block), n);
            out.extend(block);
            i += 1;
        }
        out
    }
    #[test]
    fn fifo_and_instance_state_match_across_arbitrary_host_chunks() {
        let flash = blank();
        let mut a = Native::new(&flash).unwrap();
        let mut b = Native::new(&flash).unwrap();
        a.key(21, true);
        b.key(21, true);
        let expected = render_chunks(&mut a, &[512], 44100);
        // C firmware CTL is independent of host buffer size. Interleaving instances
        // also proves one instance's active binding does not mutate its neighbor.
        let actual = render_chunks(&mut b, &[1, 31, 32, 33, 511, 512, 513, 2048], 44100);
        assert_eq!(actual, expected);
        assert!(actual.iter().any(|s| s.abs() > 0.001));
        a.key(21, false);
        let tail_a = render_chunks(&mut a, &[31, 33], 4096);
        b.key(21, false);
        let tail_b = render_chunks(&mut b, &[2048], 4096);
        assert_eq!(tail_a, tail_b);
    }
    #[test]
    fn full_flash_round_trip_restore_and_invalid_length_are_safe() {
        let mut flash = blank();
        for (i, b) in flash.iter_mut().enumerate() {
            if !(0x80000..0xa0000).contains(&i) {
                *b = (i.wrapping_mul(37) >> 8) as u8;
            }
        }
        let mut m = Native::new(&flash).unwrap();
        let mut got = vec![0; FLASH];
        unsafe { m.flash(got.as_mut_ptr(), FLASH) };
        assert_eq!(got, flash);
        assert!(!m.restore(&flash[..FLASH - 1]));
        unsafe { m.flash(got.as_mut_ptr(), FLASH) };
        assert_eq!(got, flash);
        m.key(21, true);
        render_chunks(&mut m, &[512], 4096);
        // Restore after use must discard all DSP and FIFO state and reload persisted input.
        assert!(m.restore(&flash));
        unsafe { m.flash(got.as_mut_ptr(), FLASH) };
        assert_eq!(got, flash);
        let mut fresh = Native::new(&flash).unwrap();
        fresh.key(21, true);
        m.key(21, true);
        assert_eq!(
            render_chunks(&mut m, &[31, 512], 4096),
            render_chunks(&mut fresh, &[512], 4096)
        );
    }
    fn user_sample(slot: usize) -> Vec<u8> {
        let mut flash = blank();
        let at = if slot < 3 {
            0xa0000 + slot * 0x14000
        } else {
            0xe7000
        };
        let mut h = vec![0u8; 512];
        h[0..4].copy_from_slice(&0x504d5346u32.to_le_bytes());
        h[4..6].copy_from_slice(&1u16.to_le_bytes());
        h[6] = 1;
        h[8..16].copy_from_slice(b"TESTKIT\0");
        h[16..20].copy_from_slice(&4096u32.to_le_bytes());
        let z = &mut h[32..60];
        for (off, value) in [(0, 0u32), (4, 8192), (8, 0), (12, 8191), (16, 65536)] {
            z[off..off + 4].copy_from_slice(&value.to_le_bytes());
        }
        z[20..22].copy_from_slice(&(60i16 * 16).to_le_bytes());
        z[25] = 0;
        z[26] = 127;
        z[27] = 1;
        flash[at..at + 512].copy_from_slice(&h);
        for i in 0..4096 {
            flash[at + 512 + i] = if i % 64 < 32 { 0x77 } else { 0xff };
        }
        flash
    }
    #[test]
    fn all_four_user_sample_slots_play_from_owned_flash_without_pointer_truncation() {
        let mut reference = None;
        for slot in 0..4 {
            let flash = user_sample(slot);
            let mut m = Native::new(&flash).unwrap();
            m.start();
            unsafe {
                slp_set_engine(0, 4);
                slp_param_set(0, slp_pe0(), 8 + slot as i32)
            };
            // Finish the source firmware's fade into the selected SAMPLE engine.
            render_chunks(&mut m, &[512], 4096);
            m.key(21, true);
            let audio = render_chunks(&mut m, &[1, 31, 512], 22050);
            assert!(
                audio.iter().any(|s| s.abs() > 0.001),
                "USR{} must sound, peak={}",
                slot + 1,
                audio.iter().map(|s| s.abs()).fold(0.0f32, f32::max)
            );
            if let Some(ref previous) = reference {
                assert_eq!(
                    &audio, previous,
                    "identical slot payloads must sound the same"
                );
            } else {
                reference = Some(audio);
            }
            let mut got = vec![0; FLASH];
            unsafe { m.flash(got.as_mut_ptr(), FLASH) };
            for range in [0xa0000..0xdc000, 0xe7000..0xfb000] {
                assert_eq!(&got[range.clone()], &flash[range]);
            }
        }
    }
    #[test]
    fn master_zero_silences_output_after_firmware_adc_smoothing() {
        let mut m = Native::new(&blank()).unwrap();
        m.key(21, true);
        let before = render_chunks(&mut m, &[512], 22050);
        assert!(before.iter().any(|x| x.abs() > 0.001));
        m.volume(0);
        render_chunks(&mut m, &[512], 88200);
        let after = render_chunks(&mut m, &[512], 44100);
        assert!(after.iter().all(|x| *x == 0.));
    }
    fn press(m: &mut Native, id: u32) {
        m.key(id, true);
        render_chunks(m, &[512], 6615);
        m.key(id, false);
        render_chunks(m, &[512], 1024);
    }
    #[test]
    fn five_drum_hits_record_loop_and_reopen_from_raw_flash() {
        let mut m = Native::new(&blank()).unwrap();
        for _ in 0..3 {
            m.encoder(1, 1);
            render_chunks(&mut m, &[512], 2205);
        }
        m.bind();
        assert_eq!(unsafe { slp_selected() }, 3);
        press(&mut m, 13);
        for id in [14, 16, 18, 20, 21] {
            press(&mut m, id);
            render_chunks(&mut m, &[512], 8820);
        }
        press(&mut m, 13);
        render_chunks(&mut m, &[512], 132300);
        m.bind();
        assert_ne!(unsafe { slp_playing() }, 0);
        assert_eq!(unsafe { slp_armed() }, 0);
        let loop_audio = render_chunks(&mut m, &[512], 44100);
        assert!(loop_audio.iter().any(|s| s.abs() > 0.001));
        press(&mut m, 12);
        render_chunks(&mut m, &[512], 1_323_000);
        m.bind();
        assert_eq!(unsafe { slp_playing() }, 0);
        let mut project = vec![0u8; 65536];
        let n = unsafe { slp_object_get(0, project.as_mut_ptr(), project.len() as u32) };
        assert!(n > 0);
        project.truncate(n as usize);
        let mut flash = vec![0; FLASH];
        unsafe { m.flash(flash.as_mut_ptr(), FLASH) };
        let mut next = Native::new(&flash).unwrap();
        next.start();
        assert_eq!(unsafe { slp_selected() }, 3);
        let mut reopened = vec![0u8; 65536];
        let n2 = unsafe { slp_object_get(0, reopened.as_mut_ptr(), reopened.len() as u32) };
        assert_eq!(n2, n);
        reopened.truncate(n2 as usize);
        assert_eq!(reopened, project);
        press(&mut next, 12);
        let again = render_chunks(&mut next, &[512], 44100);
        assert!(again.iter().any(|s| s.abs() > 0.001));
    }
    fn led_snapshot(m: &mut Native) -> [f32; 41] {
        let mut leds = [0.; 41];
        unsafe { m.snapshot(std::ptr::null_mut(), leds.as_mut_ptr()) };
        leds
    }
    #[test]
    fn firmware_ui_clock_advances_with_audio_and_snapshot_is_read_only() {
        let mut m = Native::new(&blank()).unwrap();
        m.start();
        let first = unsafe { slp_ui_frames() };
        for _ in 0..20 {
            led_snapshot(&mut m);
        }
        assert_eq!(
            unsafe { slp_ui_frames() },
            first,
            "snapshots cannot stretch or accelerate UI timers"
        );
        render_chunks(&mut m, &[512], 44100);
        let after = unsafe { slp_ui_frames() };
        assert!(
            (59..=64).contains(&(after - first)),
            "firmware UI must run about60Hz; got{} frames",
            after - first
        );
        for _ in 0..20 {
            led_snapshot(&mut m);
        }
        assert_eq!(unsafe { slp_ui_frames() }, after);
    }
    #[test]
    fn physical_key_leds_preserve_mapping_dim_guides_and_audio_timed_hit_decay() {
        let mut m = Native::new(&blank()).unwrap();
        for _ in 0..3 {
            m.encoder(1, 1);
            render_chunks(&mut m, &[512], 2205);
        }
        let idle = led_snapshot(&mut m);
        for id in [14usize, 21, 28, 35] {
            assert!(
                idle[id] > 0. && idle[id] < 0.01,
                "drum guide{id} must be dim, got{}",
                idle[id]
            );
        }
        for id in 14..41 {
            m.key(id, true);
            render_chunks(&mut m, &[512], 1024);
            let down = led_snapshot(&mut m);
            assert!(
                down[id as usize] > 0.08,
                "physical key{id} must light while held"
            );
            m.key(id, false);
            render_chunks(&mut m, &[512], 8820);
            let up = led_snapshot(&mut m);
            assert!(
                up[id as usize] < 0.01,
                "physical key{id} hit light must expire from audio time"
            );
        }
    }
    #[test]
    fn short_taps_and_repeated_edges_survive_one_host_audio_batch() {
        let mut m = Native::new(&blank()).unwrap();
        // A 5ms host tap can place both edges before the next 512-frame render.
        m.key(21, true);
        m.key(21, false);
        assert_eq!(m.key_transitions.len(), 2);
        let short = render_chunks(&mut m, &[512], 4096);
        assert!(
            short.iter().any(|v| *v != 0.),
            "a quick tap must start a voice"
        );
        assert!(m.key_transitions.is_empty());
        assert_eq!(m.desired_keys, 0);
        for _ in 0..32 {
            m.key(21, true);
            m.key(21, false);
        }
        assert_eq!(m.key_transitions.len(), 64);
        let repeated = render_chunks(&mut m, &[512], 4096);
        assert!(repeated.iter().any(|v| *v != 0.));
        assert!(m.key_transitions.is_empty());
        render_chunks(&mut m, &[512], 44100);
        assert!(led_snapshot(&mut m)[21] < 0.01);
        assert_eq!(m.key_transition_drops, 0);
    }
    #[test]
    fn simultaneous_keys_coalesce_and_release_all_clears_held_notes() {
        let mut m = Native::new(&blank()).unwrap();
        m.start();
        unsafe {
            slp_param_set(0, 37, 0);
            slp_param_set(0, 17, 0);
            slp_param_set(0, 3, 127);
        }
        m.key(21, true);
        m.key(25, true);
        m.apply_key_transitions();
        assert!(m.key_transitions.is_empty());
        let audio = render_chunks(&mut m, &[512], 1024);
        assert!(audio.iter().any(|v| *v != 0.));
        let mut metrics = [0u64; 16];
        unsafe { m.metrics(metrics.as_mut_ptr(), 16) };
        assert!(metrics[1] >= 2, "two keys must sound as one chord");
        for id in 14..41 {
            m.key(id, false);
        }
        render_chunks(&mut m, &[512], 44100);
        assert_eq!(m.desired_keys, 0);
        assert!(m.key_transitions.is_empty());
        let leds = led_snapshot(&mut m);
        assert!(leds[21] < 0.01 && leds[25] < 0.01);
    }
    #[test]
    fn key_transition_queue_is_bounded_and_overload_preserves_final_releases() {
        let mut m = Native::new(&blank()).unwrap();
        for _ in 0..1000 {
            m.key(21, true);
            m.key(21, false);
            assert!(m.key_transitions.len() <= KEY_TRANSITION_CAPACITY);
        }
        assert_eq!(m.key_queue_high_water, KEY_TRANSITION_CAPACITY as u64);
        assert!(m.key_transition_drops > 0);
        assert_eq!(m.desired_keys, 0);
        render_chunks(&mut m, &[512], 44100);
        assert!(m.key_transitions.is_empty());
        assert!(led_snapshot(&mut m)[21] < 0.01);
        let mut metrics = [0u64; 16];
        unsafe { m.metrics(metrics.as_mut_ptr(), 16) };
        assert_eq!(metrics[13], m.key_transition_drops);
        assert_eq!(metrics[15], 0);
    }
    #[test]
    fn pause_cancels_unrendered_note_and_button_edges_before_resume() {
        let mut m = Native::new(&blank()).unwrap();
        m.key(21, true);
        m.key(12, true);
        m.key(13, true);
        m.release_all();
        assert!(m.key_transitions.is_empty());
        assert_eq!(m.desired_keys, 0);
        let resumed = render_chunks(&mut m, &[512], 44100);
        assert!(
            resumed.iter().all(|v| *v == 0.),
            "resume cannot replay an old tap"
        );
        assert_eq!(unsafe { slp_playing() }, 0);
        assert_eq!(unsafe { slp_armed() }, 0);
        assert!(led_snapshot(&mut m)[21] < 0.01);
        m.key(21, true);
        m.key(21, false);
        assert!(render_chunks(&mut m, &[512], 4096).iter().any(|v| *v != 0.));
    }
    #[test]
    fn pause_releases_sounding_notes_with_the_ordinary_release_tail() {
        let mut a = Native::new(&blank()).unwrap();
        let mut b = Native::new(&blank()).unwrap();
        a.key(21, true);
        b.key(21, true);
        assert_eq!(
            render_chunks(&mut a, &[512], 22050),
            render_chunks(&mut b, &[512], 22050)
        );
        a.release_all();
        b.key(21, false);
        assert_eq!(
            render_chunks(&mut a, &[512], 44100),
            render_chunks(&mut b, &[512], 44100)
        );
        assert!(led_snapshot(&mut a)[21] < 0.01);
    }
}
