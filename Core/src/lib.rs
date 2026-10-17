//! Instance-based, interpreter-only C ABI. The host serializes all calls per instance.
//! CPU and peripheral implementation: Joakim Eriksson, MIT (Vendor/LICENSE-fm1-emu).
use fm1_core::{Bus, Cpu};
use fm1_soc::{machine, Action, Board, Soc};
use std::{
    collections::VecDeque,
    panic::{catch_unwind, AssertUnwindSafe},
};
const RAM: usize = 1 << 20;
const MAX_PACKAGE: usize = 4 << 20;
struct Interpreter {
    cpu: Cpu,
    cpu1: Option<Cpu>,
    soc: Soc,
    tick: bool,
    audio: VecDeque<i16>,
    halted: bool,
}
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
#[cfg(fm1_native_sloop)]
mod native_sloop;
#[cfg(any(fm1_native_sloop, test))]
mod sha256;
#[allow(private_interfaces)]
pub enum Instrument {
    Interpreter(Interpreter),
    #[cfg(fm1_native_sloop)]
    Native(native_sloop::Native),
}
impl Instrument {
    fn load(bytes: &[u8]) -> Result<Self, String> {
        #[cfg(fm1_native_sloop)]
        if std::env::var_os("FM1_FORCE_INTERPRETER").is_none()
            && bytes.len() == 610035
            && sha256::digest(bytes)
                == [
                    0x7c, 0x9d, 0x26, 0x9d, 0x15, 0xd1, 0xc1, 0xa4, 0x8e, 0x0e, 0xba, 0xda, 0x7f,
                    0xfa, 0x2c, 0x2a, 0xa1, 0x96, 0xc1, 0x9d, 0x51, 0x05, 0x6f, 0xd3, 0xf7, 0x60,
                    0xd3, 0x22, 0x32, 0x2b, 0x33, 0x5f,
                ]
        {
            let fw = fm1_soc::stock_from_package(bytes, None)?;
            return native_sloop::Native::new(&fw.flash).map(Self::Native);
        }
        Interpreter::load(bytes).map(Self::Interpreter)
    }
    pub fn static_kernel_blocks(&self) -> String {
        match self {
            Self::Interpreter(m) => m.static_kernel_blocks(),
            #[cfg(fm1_native_sloop)]
            Self::Native(_) => String::new(),
        }
    }
    fn render(&mut self, out: &mut [f32], budget: u32) -> usize {
        match self {
            Self::Interpreter(m) => m.render(out, budget),
            #[cfg(fm1_native_sloop)]
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
/// Execution backend: 0 absent, 1 interpreted binary, 2 exact pinned source-native SLOOP.
#[no_mangle]
pub unsafe extern "C" fn instrument_backend(m: *const Instrument) -> u32 {
    match m.as_ref() {
        None => 0,
        Some(Instrument::Interpreter(_)) => 1,
        #[cfg(fm1_native_sloop)]
        Some(Instrument::Native(_)) => 2,
    }
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
    #[cfg(fm1_native_sloop)]
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
            Instrument::Interpreter(m) => {
                if id < 41 {
                    m.soc.periph.apply(&Action::Key { id: id as u8, down });
                }
            }
            #[cfg(fm1_native_sloop)]
            Instrument::Native(m) => m.key(id, down),
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn instrument_encoder(m: *mut Instrument, id: u32, delta: i32) {
    if let Some(m) = m.as_mut() {
        match m {
            Instrument::Interpreter(m) => {
                if id < 7 {
                    m.soc.periph.apply(&Action::Enc {
                        enc: id as u8,
                        clicks: delta.clamp(-32, 32),
                    });
                }
            }
            #[cfg(fm1_native_sloop)]
            Instrument::Native(m) => m.encoder(id, delta),
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn instrument_volume(m: *mut Instrument, value: u32) {
    if let Some(m) = m.as_mut() {
        match m {
            Instrument::Interpreter(m) => m.soc.periph.apply(&Action::Adc {
                ch: 4,
                value: value.min(1023) as u16,
            }),
            #[cfg(fm1_native_sloop)]
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
    #[cfg(fm1_native_sloop)]
    if let Instrument::Native(m) = m {
        return m.snapshot(pixels, leds);
    }
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
#[no_mangle]
pub unsafe extern "C" fn instrument_flash(m: *mut Instrument, out: *mut u8, len: usize) -> usize {
    let Some(m) = m.as_mut() else {
        return 0;
    };
    #[cfg(fm1_native_sloop)]
    if let Instrument::Native(m) = m {
        return m.flash(out, len);
    }
    let Instrument::Interpreter(m) = m else {
        unreachable!()
    };
    let n = m.soc.flash.mem.len();
    if !out.is_null() && len == n {
        std::ptr::copy_nonoverlapping(m.soc.flash.mem.as_ptr(), out, n);
    }
    n
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
    if data.is_null() || len != RAM {
        return false;
    }
    #[cfg(fm1_native_sloop)]
    if let Instrument::Native(m) = m {
        return m.restore(std::slice::from_raw_parts(data, len));
    }
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
#[cfg(test)]
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
