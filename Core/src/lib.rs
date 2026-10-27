//! Instance-based native/research C ABI. The host serializes all calls per instance.
//! CPU and peripheral implementation: Joakim Eriksson, MIT (Vendor/LICENSE-fm1-emu).
#[cfg(feature = "research")]
use fm1_core::{Bus, Cpu};
#[cfg(feature = "research")]
use fm1_soc::{machine, Action, Board, Soc};
#[cfg(feature = "research")]
use std::collections::VecDeque;
use std::panic::{catch_unwind, AssertUnwindSafe};
#[cfg(all(feature = "research", feature = "store-native"))]
compile_error!("Store builds must disable default research features.");
#[cfg(not(any(feature = "research", feature = "store-native")))]
compile_error!("Select research or store-native explicitly.");
// Reuse the audited package decoder as data parsing only, without depending on
// the CPU, SoC, ISA or interpreter crates in the store dependency graph.
#[cfg(feature = "store-native")]
#[path = "../../Vendor/fm1-soc/src/fwsc.rs"]
#[allow(dead_code)]
mod package_data;
mod project_io;
const RAM: usize = 1 << 20;
const MAX_PACKAGE: usize = 4 << 20;
#[cfg(feature = "research")]
struct Interpreter {
    cpu: Cpu,
    cpu1: Option<Cpu>,
    soc: Soc,
    tick: bool,
    audio: VecDeque<i16>,
    halted: bool,
}
#[cfg(feature = "research")]
impl Interpreter {
    /// Offline profiling tool output; contains firmware-derived decoded instructions.
    /// Keep generated files local and ignored, just like the input firmware package.
    pub fn static_kernel_blocks(&self) -> String {
        self.cpu.static_kernel_blocks()
    }
    fn load(bytes: &[u8]) -> Result<Self, String> {
        if !(960..=MAX_PACKAGE).contains(&bytes.len()) {
            return Err("Package size is invalid (960 bytes to 4 MiB).".into());
        }
        let fw = fm1_soc::stock_from_package(bytes, None)?;
        if fw.board != Board::Fm1 {
            return Err("This package targets SMK-37, not FM-1.".into());
        }
        let mut soc = Soc::new(RAM, fw.xip);
        soc.periph.hz = 240_000_000;
        soc.periph.skip_idle = true;
        let mut cpu = Cpu::new(fw.entry);
        cpu.jit_on = false; // No executable-memory/JIT entitlement on iOS.
        cpu.user = true;
        let params = 0x01c0_0000 + 0x7fc00;
        soc.write32(params, params + 0x40);
        cpu.regs[0] = fm1_soc::stock_boot(&mut soc, &fw.flash, params, fw.board);
        soc.periph.apply(&Action::Adc { ch: 4, value: 720 });
        Ok(Self {
            cpu,
            cpu1: None,
            soc,
            tick: false,
            audio: VecDeque::new(),
            halted: false,
        })
    }
    fn render(&mut self, out: &mut [f32], budget: u32) -> usize {
        out.fill(0.0);
        if self.halted {
            return 0;
        }
        let mut spent = 0;
        while self.audio.len() < out.len() && spent < budget {
            let Self {
                cpu,
                cpu1,
                soc,
                tick,
                ..
            } = self;
            if machine::run_dual(cpu1, soc, 20_000, RAM, false, |s, n| {
                machine::run_blocks(cpu, s, n, tick)
            })
            .is_err()
            {
                self.halted = true;
                self.audio.clear();
                return 0;
            }
            spent += 20_000;
            self.audio.extend(self.soc.periph.audio.drain(..));
            // Bound retained audio even if an unexpected firmware produces oversized chunks.
            if self.audio.len() > 65536 {
                self.audio.truncate(65536);
            }
        }
        let count = out.len().min(self.audio.len());
        for s in out.iter_mut().take(count) {
            *s = self.audio.pop_front().unwrap() as f32 / 32768.0;
        }
        count / 2
    }
}
#[cfg(fm1_native_community)]
mod native_community;
#[cfg(any(
    fm1_native_sloop,
    fm1_native_family,
    fm1_native_official_preview,
    fm1_native_expansion,
    fm1_native_skiff,
    fm1_native_community
))]
mod native_family;
#[cfg(any(
    fm1_native_sloop,
    fm1_native_family,
    fm1_native_official_preview,
    fm1_native_expansion,
    fm1_native_skiff,
    fm1_native_community
))]
mod native_sloop;
#[cfg(any(
    fm1_native_sloop,
    fm1_native_family,
    fm1_native_official_preview,
    fm1_native_expansion,
    fm1_native_skiff,
    fm1_native_community,
    test
))]
mod sha256;
#[allow(private_interfaces)]
pub enum Instrument {
    #[cfg(feature = "research")]
    Interpreter(Interpreter),
    #[cfg(any(
        fm1_native_sloop,
        fm1_native_family,
        fm1_native_official_preview,
        fm1_native_expansion,
        fm1_native_skiff,
        fm1_native_community
    ))]
    Native(native_sloop::Native),
}
impl Instrument {
    fn load(bytes: &[u8]) -> Result<Self, String> {
        #[cfg(any(
            fm1_native_sloop,
            fm1_native_family,
            fm1_native_official_preview,
            fm1_native_expansion,
            fm1_native_skiff,
            fm1_native_community
        ))]
        if cfg!(feature = "store-native") || std::env::var_os("FM1_FORCE_INTERPRETER").is_none() {
            if let Some(api) = native_family::for_package(bytes) {
                // Melodee's derived INIT soundset must never seed its NOR from
                // the hardware package, which contains excluded factory data.
                // Its application/DSP are source-compiled; only user saves may
                // subsequently restore musical data. The official portable
                // preview likewise owns a separate logical store.
                if matches!(api.kind, 5 | 6 | 11..=16) {
                    return native_sloop::Native::with_api(&vec![0xff; api.flash_size], api)
                        .map(Self::Native);
                }
                #[cfg(feature = "research")]
                let flash = fm1_soc::stock_from_package(bytes, None)?.flash;
                #[cfg(feature = "store-native")]
                let flash = {
                    let unpacked = package_data::unpack(bytes)?;
                    let mut flash = package_data::full_flash(&unpacked.raw, RAM);
                    if let Some(usr) = package_data::usr_offset(&unpacked) {
                        package_data::usr_fill_defaults(&mut flash, usr);
                    }
                    flash
                };
                return native_sloop::Native::with_api(&flash, api).map(Self::Native);
            }
        }
        #[cfg(feature = "research")]
        {
            Interpreter::load(bytes).map(Self::Interpreter)
        }
        #[cfg(feature = "store-native")]
        {
            Err("This instrument is not included in this signed application.".into())
        }
    }
    #[cfg(feature = "research")]
    pub fn static_kernel_blocks(&self) -> String {
        match self {
            Self::Interpreter(m) => m.static_kernel_blocks(),
            #[cfg(any(
                fm1_native_sloop,
                fm1_native_family,
                fm1_native_official_preview,
                fm1_native_expansion,
                fm1_native_skiff,
                fm1_native_community
            ))]
            Self::Native(_) => String::new(),
        }
    }
    fn render(&mut self, out: &mut [f32], budget: u32) -> usize {
        match self {
            #[cfg(feature = "research")]
            Self::Interpreter(m) => m.render(out, budget),
            #[cfg(any(
                fm1_native_sloop,
                fm1_native_family,
                fm1_native_official_preview,
                fm1_native_expansion,
                fm1_native_skiff,
                fm1_native_community
            ))]
            Self::Native(m) => m.render(out),
        }
    }
}
unsafe fn error_text(error: *mut u8, cap: usize, text: &str) {
    if !error.is_null() && cap > 0 {
        let n = text.len().min(cap - 1);
        std::ptr::copy_nonoverlapping(text.as_ptr(), error, n);
        *error.add(n) = 0;
    }
}
// A signed, read-only Mach-O section survives distribution symbol stripping.
// A volatile host policy read keeps the section live through linker dead stripping.
#[cfg(feature = "store-native")]
#[used]
#[link_section = "__TEXT,__fm1_policy"]
static BUILD_POLICY: [u8; 27] = *b"FM1_BUILD_POLICY_V1:NATIVE\0";
#[cfg(feature = "research")]
#[used]
#[link_section = "__TEXT,__fm1_policy"]
static BUILD_POLICY: [u8; 29] = *b"FM1_BUILD_POLICY_V1:RESEARCH\0";
/// Build boundary exposed for host verification; immutable at compilation.
#[no_mangle]
pub extern "C" fn instrument_research_enabled() -> bool {
    unsafe { std::ptr::read_volatile(BUILD_POLICY.as_ptr().add(20)) != b'N' }
}
/// Execution backend: 0 absent, 1 interpreted binary, 2 exact pinned source-native engine.
#[no_mangle]
pub unsafe extern "C" fn instrument_backend(m: *const Instrument) -> u32 {
    match m.as_ref() {
        None => 0,
        #[cfg(feature = "research")]
        Some(Instrument::Interpreter(_)) => 1,
        #[cfg(any(
            fm1_native_sloop,
            fm1_native_family,
            fm1_native_official_preview,
            fm1_native_expansion,
            fm1_native_skiff,
            fm1_native_community
        ))]
        Some(Instrument::Native(_)) => 2,
    }
}
/// Source-native kind linked into this build, selected by exact package hash.
/// 0 unavailable; 2 SLOOP; 3 Felucca; 4 X0X; 5 Melodee; 6 official portable preview.
#[no_mangle]
pub unsafe extern "C" fn instrument_native_kind_for_fwsc(data: *const u8, len: usize) -> u32 {
    if data.is_null() || !(960..=MAX_PACKAGE).contains(&len) {
        return 0;
    }
    #[cfg(any(
        fm1_native_sloop,
        fm1_native_family,
        fm1_native_official_preview,
        fm1_native_expansion,
        fm1_native_skiff,
        fm1_native_community
    ))]
    if let Some(api) = native_family::for_package(std::slice::from_raw_parts(data, len)) {
        return api.kind;
    }
    0
}
/// Catalogue-only lookup: accepts 64 hexadecimal SHA-256 ASCII bytes, without file I/O.
#[no_mangle]
pub unsafe extern "C" fn instrument_native_kind_for_sha256(data: *const u8, len: usize) -> u32 {
    if data.is_null() || len != 64 {
        return 0;
    }
    let mut digest = [0u8; 32];
    fn hex(v: u8) -> Option<u8> {
        match v {
            b'0'..=b'9' => Some(v - b'0'),
            b'a'..=b'f' => Some(v - b'a' + 10),
            b'A'..=b'F' => Some(v - b'A' + 10),
            _ => None,
        }
    }
    for (i, pair) in std::slice::from_raw_parts(data, len)
        .chunks_exact(2)
        .enumerate()
    {
        let (Some(a), Some(b)) = (hex(pair[0]), hex(pair[1])) else {
            return 0;
        };
        digest[i] = a * 16 + b;
    }
    #[cfg(any(
        fm1_native_sloop,
        fm1_native_family,
        fm1_native_official_preview,
        fm1_native_expansion,
        fm1_native_skiff,
        fm1_native_community
    ))]
    if let Some(api) = native_family::for_digest(digest, 0) {
        return api.kind;
    }
    0
}
#[no_mangle]
pub unsafe extern "C" fn instrument_native_kind(m: *const Instrument) -> u32 {
    #[cfg(any(
        fm1_native_sloop,
        fm1_native_family,
        fm1_native_official_preview,
        fm1_native_expansion,
        fm1_native_skiff,
        fm1_native_community
    ))]
    if let Some(Instrument::Native(m)) = m.as_ref() {
        return m.kind();
    }
    0
}
/// Optional native workload proof counters (16 u64 values); zero for interpreter/absent.
#[no_mangle]
pub unsafe extern "C" fn instrument_workload_metrics(
    m: *mut Instrument,
    out: *mut u64,
    capacity: u32,
) -> u32 {
    if out.is_null() {
        return 0;
    }
    #[cfg(any(
        fm1_native_sloop,
        fm1_native_family,
        fm1_native_official_preview,
        fm1_native_expansion,
        fm1_native_skiff,
        fm1_native_community
    ))]
    if let Some(Instrument::Native(m)) = m.as_mut() {
        return m.metrics(out, capacity.min(16));
    }
    0
}
/// Borrowed package bytes. Returns an owned instance or null, with a readable error.
#[no_mangle]
pub unsafe extern "C" fn instrument_create(
    data: *const u8,
    len: usize,
    error: *mut u8,
    cap: usize,
) -> *mut Instrument {
    if data.is_null() || len > MAX_PACKAGE {
        error_text(error, cap, "Invalid firmware data.");
        return std::ptr::null_mut();
    }
    match catch_unwind(|| Instrument::load(std::slice::from_raw_parts(data, len))) {
        Ok(Ok(m)) => Box::into_raw(Box::new(m)),
        Ok(Err(e)) => {
            error_text(error, cap, &e);
            std::ptr::null_mut()
        }
        Err(_) => {
            error_text(error, cap, "Damaged or unsupported firmware package.");
            std::ptr::null_mut()
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn instrument_destroy(m: *mut Instrument) {
    if !m.is_null() {
        drop(Box::from_raw(m));
    }
}
#[no_mangle]
pub unsafe extern "C" fn instrument_render(
    m: *mut Instrument,
    out: *mut f32,
    frames: usize,
) -> usize {
    if m.is_null() || out.is_null() || frames > 2048 {
        return 0;
    }
    let m = &mut *m;
    let samples = std::slice::from_raw_parts_mut(out, frames * 2);
    match catch_unwind(AssertUnwindSafe(|| m.render(samples, 4_000_000))) {
        Ok(n) => n,
        Err(_) => {
            #[cfg(feature = "research")]
            if let Instrument::Interpreter(m) = m {
                m.halted = true;
            }
            samples.fill(0.0);
            0
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn instrument_key(m: *mut Instrument, id: u32, down: bool) {
    if let Some(m) = m.as_mut() {
        match m {
            #[cfg(feature = "research")]
            Instrument::Interpreter(m) => {
                if id < 41 {
                    m.soc.periph.apply(&Action::Key { id: id as u8, down });
                }
            }
            #[cfg(any(
                fm1_native_sloop,
                fm1_native_family,
                fm1_native_official_preview,
                fm1_native_expansion,
                fm1_native_skiff,
                fm1_native_community
            ))]
            Instrument::Native(m) => m.key(id, down),
        }
    }
}
/// Host suspension: release held inputs and cancel native edges not yet rendered.
#[no_mangle]
pub unsafe extern "C" fn instrument_release_all(m: *mut Instrument) {
    if let Some(m) = m.as_mut() {
        match m {
            #[cfg(feature = "research")]
            Instrument::Interpreter(m) => {
                for id in 0..41 {
                    m.soc.periph.apply(&Action::Key { id, down: false });
                }
            }
            #[cfg(any(
                fm1_native_sloop,
                fm1_native_family,
                fm1_native_official_preview,
                fm1_native_expansion,
                fm1_native_skiff,
                fm1_native_community
            ))]
            Instrument::Native(m) => m.release_all(),
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn instrument_encoder(m: *mut Instrument, id: u32, delta: i32) {
    if let Some(m) = m.as_mut() {
        match m {
            #[cfg(feature = "research")]
            Instrument::Interpreter(m) => {
                if id < 7 {
                    m.soc.periph.apply(&Action::Enc {
                        enc: id as u8,
                        clicks: delta.clamp(-32, 32),
                    });
                }
            }
            #[cfg(any(
                fm1_native_sloop,
                fm1_native_family,
                fm1_native_official_preview,
                fm1_native_expansion,
                fm1_native_skiff,
                fm1_native_community
            ))]
            Instrument::Native(m) => m.encoder(id, delta),
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn instrument_volume(m: *mut Instrument, value: u32) {
    if let Some(m) = m.as_mut() {
        match m {
            #[cfg(feature = "research")]
            Instrument::Interpreter(m) => m.soc.periph.apply(&Action::Adc {
                ch: 4,
                value: value.min(1023) as u16,
            }),
            #[cfg(any(
                fm1_native_sloop,
                fm1_native_family,
                fm1_native_official_preview,
                fm1_native_expansion,
                fm1_native_skiff,
                fm1_native_community
            ))]
            Instrument::Native(m) => m.volume(value),
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn instrument_snapshot(
    m: *mut Instrument,
    pixels: *mut u32,
    leds: *mut f32,
) -> u32 {
    let Some(m) = m.as_mut() else {
        return 0;
    };
    #[cfg(any(
        fm1_native_sloop,
        fm1_native_family,
        fm1_native_official_preview,
        fm1_native_expansion,
        fm1_native_skiff,
        fm1_native_community
    ))]
    if let Instrument::Native(m) = m {
        return m.snapshot(pixels, leds);
    }
    #[cfg(feature = "research")]
    {
        let Instrument::Interpreter(m) = m else {
            unreachable!()
        };
        if !pixels.is_null() {
            for (i, &p) in m.soc.lcd.fb.iter().take(240 * 240).enumerate() {
                let p = p as u32;
                let r = ((p >> 11) & 31) * 255 / 31;
                let g = ((p >> 5) & 63) * 255 / 63;
                let b = (p & 31) * 255 / 31;
                *pixels.add(i) = 0xff000000 | (b << 16) | (g << 8) | r;
            }
        }
        if !leds.is_null() {
            let l = m.soc.periph.led_take();
            std::ptr::copy_nonoverlapping(l.as_ptr(), leds, 41);
        }
        if m.halted {
            2
        } else {
            1
        }
    }
    #[cfg(feature = "store-native")]
    {
        unreachable!("Store instruments are compiled native engines")
    }
}
#[no_mangle]
pub unsafe extern "C" fn instrument_flash(m: *mut Instrument, out: *mut u8, len: usize) -> usize {
    let Some(m) = m.as_mut() else {
        return 0;
    };
    #[cfg(any(
        fm1_native_sloop,
        fm1_native_family,
        fm1_native_official_preview,
        fm1_native_expansion,
        fm1_native_skiff,
        fm1_native_community
    ))]
    if let Instrument::Native(m) = m {
        return m.flash(out, len);
    }
    #[cfg(feature = "research")]
    {
        let Instrument::Interpreter(m) = m else {
            unreachable!()
        };
        let n = m.soc.flash.mem.len();
        if !out.is_null() && len == n {
            std::ptr::copy_nonoverlapping(m.soc.flash.mem.as_ptr(), out, n);
        }
        n
    }
    #[cfg(feature = "store-native")]
    {
        unreachable!("Store instruments are compiled native engines")
    }
}
#[no_mangle]
pub unsafe extern "C" fn instrument_restore(
    m: *mut Instrument,
    data: *const u8,
    len: usize,
) -> bool {
    let Some(m) = m.as_mut() else {
        return false;
    };
    // Source backends own different store formats. Bound the borrowed slice,
    // then let the active backend validate its exact length before mutation.
    if data.is_null() || len == 0 || len > RAM {
        return false;
    }
    #[cfg(any(
        fm1_native_sloop,
        fm1_native_family,
        fm1_native_official_preview,
        fm1_native_expansion,
        fm1_native_skiff,
        fm1_native_community
    ))]
    if let Instrument::Native(m) = m {
        return m.restore(std::slice::from_raw_parts(data, len));
    }
    #[cfg(feature = "research")]
    {
        let Instrument::Interpreter(m) = m else {
            unreachable!()
        };
        if len != m.soc.flash.mem.len() {
            return false;
        }
        m.soc
            .flash
            .mem
            .copy_from_slice(std::slice::from_raw_parts(data, len));
        true
    }
    #[cfg(feature = "store-native")]
    {
        unreachable!("Store instruments are compiled native engines")
    }
}
#[cfg(all(test, feature = "research"))]
mod tests {
    use super::*;
    #[test]
    fn malformed_packages_fail_without_unwinding_abi() {
        for n in [0, 959, 960, 1024, 4096, 65536] {
            let bytes = vec![0xa5; n];
            let mut err = [0u8; 256];
            let p = unsafe { instrument_create(bytes.as_ptr(), n, err.as_mut_ptr(), 256) };
            assert!(p.is_null());
            assert_ne!(err[0], 0);
        }
    }
    #[test]
    fn oversize_is_rejected_before_dereference() {
        let mut err = [0u8; 256];
        assert!(unsafe {
            instrument_create(std::ptr::null(), MAX_PACKAGE + 1, err.as_mut_ptr(), 256)
        }
        .is_null());
    }
}

#[cfg(all(test, fm1_native_sloop, fm1_native_family, fm1_native_official_preview))]
mod native_public_abi_tests {
    use super::*;
    #[cfg(fm1_native_expansion)]
    #[test]
    fn fomni_public_physical_knobs_edit_the_correct_stored_parameters() {
        fn crc(bytes: &[u8]) -> u32 {
            let mut value = !0u32;
            for byte in bytes {
                value ^= *byte as u32;
                for _ in 0..8 {
                    value = (value >> 1) ^ if value & 1 != 0 { 0xedb88320 } else { 0 };
                }
            }
            !value
        }
        fn project(flash: &[u8]) -> ([i16; 16], u32) {
            let word = |p: usize| u32::from_le_bytes(flash[p..p + 4].try_into().unwrap());
            let mut candidates = Vec::new();
            for offset in [0xfc000usize, 0xfd000] {
                let length = word(offset + 12) as usize;
                if word(offset) != 0x30583058
                    || length != 80
                    || word(offset + 28) != crc(&flash[offset..offset + 28])
                {
                    continue;
                }
                let bytes = &flash[offset + 256..offset + 256 + length];
                if word(offset + 16) != crc(bytes) || bytes[..4] != 0x494e4d4fu32.to_le_bytes() {
                    continue;
                }
                let mut values = [0i16; 16];
                for (index, value) in values.iter_mut().enumerate() {
                    *value = i16::from_le_bytes(
                        bytes[8 + index * 2..10 + index * 2].try_into().unwrap(),
                    );
                }
                candidates.push((word(offset + 8), values, crc(bytes)));
            }
            let (_, values, checksum) = candidates
                .into_iter()
                .max_by_key(|c| c.0)
                .expect("valid original A/B project with header and payload CRC");
            (values, checksum)
        }
        unsafe fn tick(instance: *mut Instrument, frames: usize) {
            let mut audio = [0f32; 1024];
            for _ in (0..frames).step_by(512) {
                assert_eq!(instrument_render(instance, audio.as_mut_ptr(), 512), 512);
            }
        }
        let root = std::path::PathBuf::from(std::env::var_os("FM1_NATIVE_EXPANSION").unwrap());
        let bytes = std::fs::read(root.join("fomni-0.4.fwsc")).unwrap();
        unsafe {
            let mut error = [0u8; 256];
            let instance =
                instrument_create(bytes.as_ptr(), bytes.len(), error.as_mut_ptr(), error.len());
            assert!(!instance.is_null());
            assert_eq!(instrument_native_kind(instance), 8);
            let blank = vec![255; RAM];
            assert!(instrument_restore(instance, blank.as_ptr(), RAM));
            tick(instance, 22050);
            // Physical IDs come from the app panel: SELECT, ALGORITHM, KNOB1..4, PRESETS.
            let mut expected = [80, 45, 50, 60, 0, 116, 70, 1, 30, 55, 0, 25, 0, 0, 60, 1];
            let mut saved = vec![0u8; RAM];
            let mut checksum = 0;
            for (physical, parameter) in [(0, 5), (1, 4), (2, 0), (3, 1), (4, 2), (5, 3), (6, 12)] {
                instrument_encoder(instance, physical, 1);
                tick(instance, 44100 * 30);
                expected[parameter] += 1;
                instrument_flash(instance, saved.as_mut_ptr(), RAM);
                let (actual, sum) = project(&saved);
                checksum = sum;
                assert_eq!(
                    actual, expected,
                    "physical encoder {physical} must change only its source-defined parameter"
                );
            }
            instrument_destroy(instance);
            let reopened =
                instrument_create(bytes.as_ptr(), bytes.len(), error.as_mut_ptr(), error.len());
            assert!(!reopened.is_null());
            assert!(instrument_restore(reopened, saved.as_ptr(), RAM));
            tick(reopened, 1024);
            let mut metrics = [0u64; 16];
            instrument_workload_metrics(reopened, metrics.as_mut_ptr(), 16);
            assert_eq!(
                metrics[12], checksum as u64,
                "public restore must reload the edited working project"
            );
            instrument_destroy(reopened);
        }
    }
    #[test]
    fn all_linked_native_engines_reopen_their_own_public_abi_flash_format() {
        let family = std::path::PathBuf::from(std::env::var_os("FM1_NATIVE_FAMILY").unwrap());
        let sloop = std::path::PathBuf::from(std::env::var_os("FM1_NATIVE_SLOOP").unwrap());
        let official =
            std::path::PathBuf::from(std::env::var_os("FM1_NATIVE_OFFICIAL_PREVIEW").unwrap());
        let mut cases = vec![
            (2, sloop.join("docs/firmware/sloop-2.8.fwsc"), RAM),
            (3, family.join("felucca-1.6.1.fwsc"), RAM),
            (4, family.join("x0x-1.1.0.fwsc"), RAM),
            (5, family.join("melodee-1.4.5.fwsc"), RAM),
            (
                6,
                official.parent().unwrap().join("FM1-Open-V14.fwsc"),
                536576,
            ),
        ];
        #[cfg(fm1_native_expansion)]
        {
            let root = std::path::PathBuf::from(std::env::var_os("FM1_NATIVE_EXPANSION").unwrap());
            cases.extend([
                (8, root.join("fomni-0.4.fwsc"), RAM),
                (9, root.join("jangada-1.0.1.fwsc"), RAM),
            ]);
        }
        #[cfg(fm1_native_skiff)]
        {
            let root = std::path::PathBuf::from(std::env::var_os("FM1_NATIVE_SKIFF").unwrap());
            cases.push((7, root.parent().unwrap().join("skiff-1.4.fwsc"), RAM));
        }
        for (kind, path, expected_size) in cases {
            let bytes = std::fs::read(path).unwrap();
            let mut error = [0u8; 256];
            unsafe {
                let first = instrument_create(bytes.as_ptr(), bytes.len(), error.as_mut_ptr(), 256);
                assert!(!first.is_null());
                assert_eq!(instrument_native_kind(first), kind);
                assert_eq!(
                    instrument_native_kind_for_fwsc(bytes.as_ptr(), bytes.len()),
                    kind
                );
                let mut audio = [0.; 1024];
                assert_eq!(instrument_render(first, audio.as_mut_ptr(), 512), 512);
                for _ in 0..44 {
                    instrument_render(first, audio.as_mut_ptr(), 512);
                }
                let first_key = if kind == 4 { 15 } else { 21 }; // X0X black-key drum trigger.
                instrument_key(first, first_key, true);
                let mut nonzero = 0;
                for _ in 0..87 {
                    instrument_render(first, audio.as_mut_ptr(), 512);
                    nonzero += audio.iter().filter(|v| **v != 0.).count();
                }
                assert!(
                    nonzero > 100,
                    "native {kind}: public ABI must synthesize actual PCM after boot"
                );
                instrument_key(first, first_key, false);
                let len = instrument_flash(first, std::ptr::null_mut(), 0);
                assert_eq!(len, expected_size);
                let mut saved = vec![0; len];
                assert_eq!(instrument_flash(first, saved.as_mut_ptr(), len), len);
                if kind == 5 {
                    assert!(saved[..0x93000].iter().all(|byte| *byte == 0xff),
                        "derived Melodee must not copy package instructions/factory data into native NOR");
                }
                instrument_destroy(first);
                let reopened =
                    instrument_create(bytes.as_ptr(), bytes.len(), error.as_mut_ptr(), 256);
                assert!(!reopened.is_null());
                assert!(!instrument_restore(reopened, saved.as_ptr(), len - 1));
                assert!(
                    instrument_restore(reopened, saved.as_ptr(), len),
                    "native kind {kind} public ABI restore"
                );
                let mut check = vec![0; len];
                assert_eq!(instrument_flash(reopened, check.as_mut_ptr(), len), len);
                assert_eq!(saved, check);
                instrument_key(reopened, 21, true);
                assert_eq!(instrument_render(reopened, audio.as_mut_ptr(), 512), 512);
                instrument_key(reopened, 21, false);
                instrument_destroy(reopened);
            }
        }
    }
}

#[cfg(all(test, feature = "store-native"))]
mod store_boundary_tests {
    use super::*;
    #[test]
    fn store_rejects_unlisted_packages_at_the_abi() {
        assert!(!instrument_research_enabled());
        for size in [0, 959, 960, 1024, 65536, MAX_PACKAGE] {
            let package = vec![0xa5; size];
            let mut error = [0u8; 256];
            let machine = unsafe {
                instrument_create(package.as_ptr(), size, error.as_mut_ptr(), error.len())
            };
            assert!(machine.is_null());
            assert_ne!(error[0], 0);
        }
    }
}
