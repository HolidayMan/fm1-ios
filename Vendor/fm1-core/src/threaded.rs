//! A static computed-goto interpreter for plain operations. The C engine may only
//! touch registers and explicitly opted-in, side-effect-free memory before the next
//! bus event. Every other operation returns to the original Rust interpreter.
use super::{Base, BOp, Bus, Cond, Cpu, Fast, Op};
mod tag { include!(concat!(env!("OUT_DIR"), "/thread_tags.rs")); }
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct ThreadOp { tag: u8, a: u8, b: u8, c: u8, imm: u32, aux: u32, next: u32 }
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub(super) struct ThreadBlock { pub pc: u32, pub start: u32, pub len: u32, pub hot: u32,
    pub kernel:Option<unsafe extern "C" fn(*mut std::ffi::c_void)->u64> }
#[repr(C)]
struct State {
    regs: *mut u32, flags: *mut u32, sp: *mut u32, rets: *mut u32,
    ram: *mut u8, ram_code: *const u8, xip: *const u8,
    ops: *const ThreadOp, blocks: *const ThreadBlock, map: *const u32,
    ram_base: u32, ram_len: u32, xip_base: u32, xip_len: u32, map_mask: u32, block_count: u32,
    pc: u32, block: u32, index: u32, retired: u32, budget: u32, max_ops: u32, status: u32,
    cpu:*mut Cpu, bus:*mut std::ffi::c_void, helper:unsafe extern "C" fn(*mut State)->u32,
    ticks_spent:u32,prepaid:u32,limit:u32,panic:*mut std::ffi::c_void,
}
extern "C" {
    fn fm1_threaded_run(state: *mut State);
    fn fm1_threaded_kernel_count()->u32;
    #[cfg(test)] fn fm1_threaded_kernel_info(i:u32,pc:*mut u32,ops:*mut *const ThreadOp,meta:*mut *const u8,length:*mut u32)->Option<unsafe extern "C" fn(*mut std::ffi::c_void)->u64>;
    fn fm1_threaded_bind(pc:u32,ops:*const ThreadOp,meta:*const u8,length:u32)->Option<unsafe extern "C" fn(*mut std::ffi::c_void)->u64>;
    #[cfg(test)] fn fm1_threaded_layout() -> u64;
    #[cfg(test)] fn fm1_threaded_offsets(length:*mut u32)->*const u32;
}
fn condition(c: Cond) -> Option<u8> {
    Some(match c { Cond::Eq=>0, Cond::Ne=>1, Cond::LtU=>2, Cond::GtU=>3, Cond::LeU=>4,
        Cond::GeU=>5, Cond::LtS=>6, Cond::GtS=>7, Cond::LeS=>8, Cond::GeS=>9, _=>return None })
}
fn operation(o: Op) -> u8 {
    match o { Op::Add=>0,Op::Sub=>1,Op::RSub=>2,Op::And=>3,Op::AndNot=>4,Op::Or=>5,
        Op::Xor=>6,Op::Mul=>7,Op::Shl=>8,Op::Shr=>9,Op::Sar=>10 }
}
fn base(b: Base) -> Option<u8> { match b { Base::Sp=>Some(16),Base::Reg(r) if r<16=>Some(r),_=>None } }
fn width(w: u8, signed: bool) -> u8 { (if w == 1 {1} else if w == 2 {2} else {4}) | if signed {8} else {0} }
impl ThreadOp {
    pub(super) fn compile(op: BOp, next: u32) -> Self {
        let none = Self { next, ..Self::default() };
        if op.careful || (op.pair_head && !op.glue) { return none; }
        let (t,a,b,c,imm,aux) = match op.fast {
            Fast::Nop => (tag::NOP,0,0,0,0,0),
            Fast::Mov {d,s} => (tag::MOV,d&15,s&15,0,0,0),
            Fast::MovI {d,v} => (tag::MOVI,d&15,0,0,v,0),
            Fast::AddRI {d,s,v} => (tag::ADDI,d&15,s&15,0,v,0),
            Fast::AddRR {d,a,b} => (tag::ADDR,d&15,a&15,b&15,0,0),
            Fast::SubRR {d,a,b} => (tag::SUBR,d&15,a&15,b&15,0,0),
            Fast::AndI {d,s,v} => (tag::ANDI,d&15,s&15,0,v,0),
            Fast::AndBit {d,s,r} => (tag::ANDBIT,d&15,s&15,r&15,0,0),
            Fast::ShlR {d,a,b} => (tag::SHLR,d&15,a&15,b&15,0,0),
            Fast::ShrR {d,a,b} => (tag::SHRR,d&15,a&15,b&15,0,0),
            Fast::ShrI {d,s,n} => (tag::SHRI,d&15,s&15,0,(n&31) as u32,0),
            Fast::MulI {d,s,v} => (tag::MULI,d&15,s&15,0,v,0),
            Fast::ShlI {d,s,n} => (tag::SHLI,d&15,s&15,0,(n&31) as u32,0),
            Fast::SarI {d,s,n} => (tag::SARI,d&15,s&15,0,(n&31) as u32,0),
            Fast::Alu3 {d,a,b,op} => (tag::ALUR,d&15,a&15,b&15,operation(op) as u32,0),
            Fast::Alu2 {d,b,op} => (tag::ALUR,d&15,d&15,b&15,operation(op) as u32,0),
            Fast::Alu3I {d,a,v,op} => (tag::ALUI,d&15,a&15,operation(op),v,0),
            Fast::Alu2I {d,v,op} => (tag::ALUI,d&15,d&15,operation(op),v,0),
            Fast::A4 {d,s,op,rk:0,rv} => (tag::ALUR,d&15,s&15,rv as u8&15,operation(op) as u32,0),
            Fast::A4 {d,s,op,rk:1,rv} => (tag::ALUI,d&15,s&15,operation(op),rv,0),
            Fast::Ld {d,b,off,w,signed} => { let Some(b)=base(b) else{return none}; (tag::LOAD,d&15,b,width(w,signed),off,0) },
            Fast::LdW {d,b,off} => (tag::LOAD,d&15,b&15,4,off,0),
            Fast::LdWSp {d,off} => (tag::LOAD,d&15,16,4,off,0),
            Fast::LdBu {d,b,off} => (tag::LOAD,d&15,b&15,1,off,0),
            Fast::LdIdx {d,b,i,sh,w,signed} if sh<32 => (tag::LOADIDX,d&15,b&15,i&15,sh as u32 | ((width(w,signed) as u32)<<8),0),
            Fast::St {s,b,off,w} => { let Some(b)=base(b) else{return none}; (tag::STORE,s&15,b,width(w,false),off,0) },
            Fast::StW {s,b,off} => (tag::STORE,s&15,b&15,4,off,0),
            Fast::StWSp {s,off} => (tag::STORE,s&15,16,4,off,0),
            Fast::StIdx {s,b,i,sh,w} if sh<32 => (tag::STOREIDX,s&15,b&15,i&15,sh as u32 | ((width(w,false) as u32)<<8),0),
            Fast::StPost {s,b,w,inc} => (tag::STOREPOST,s&15,b&15,width(w,false),inc,0),
            Fast::BrIEq {a,v,target} => (tag::BRI,a&15,0,0,v,target),
            Fast::BrINe {a,v,target} => (tag::BRI,a&15,0,1,v,target),
            Fast::BrI {a,v,cond,target} => { let Some(c)=condition(cond) else{return none}; (tag::BRI,a&15,0,c,v,target) },
            Fast::BrR {a,b,cond,target} => { let Some(c)=condition(cond) else{return none}; (tag::BRR,a&15,b&15,c,0,target) },
            Fast::BitBr {r,mk,ne,mv,target} => (tag::BITBR,r&15,mk,ne as u8,mv,target),
            Fast::DecBr {r,cond,v,target} => { let Some(c)=condition(cond) else{return none}; (tag::DECBR,r&15,0,c,v,target) },
            Fast::Goto {target} => (tag::GOTO,0,0,0,0,target),
            Fast::Call {target} => (tag::CALL,0,0,0,0,target),
            Fast::Rts => (tag::RTS,0,0,0,0,0),
            Fast::PushRet => (tag::PUSHRET,0,0,0,0,0),
            Fast::PopRet => (tag::POPRET,0,0,0,0,0),
            Fast::PopRets => (tag::POPRETS,0,0,0,0,0),
            Fast::BitExt {d,s,p,l,signed} => (tag::BITEXT,d&15,s&15,u8::from(signed),(p&31) as u32,(l&31) as u32),
            Fast::PushRets {n} if n<16 => (tag::PUSH,0,0,0,n as u32,0),
            Fast::PopPc {n} if n<16 => (tag::POP,0,0,0,n as u32,0),
            Fast::SpAdd {v} => (tag::SPADD,0,0,0,v,0),
            Fast::SpFromR {s} => (tag::SPFROM,s&15,0,0,0,0),
            Fast::RFromSp {d,v} => (tag::RFROMSP,d&15,0,0,v,0),
            Fast::IfBlk {a,rk,fam:2,alt,has_else:false,rv,then_d,..} => (tag::IFBIT,a&15,rk,alt as u8,rv,next.wrapping_add(then_d as u32)),
            Fast::IfBlk {a,rk,fam,alt,has_else:false,rv,then_d,..} => {
                let Some(c)=condition(super::cond_of_fam(fam as u64,alt)) else{return none};
                (tag::IFCMP,a&15,rk,c,rv,next.wrapping_add(then_d as u32))
            },
            Fast::MemA4 {b,off,op:Op::Add,rk:1,rv} => (tag::MEMADDI,b&15,0,0,rv,off as u32),
            Fast::SetIe{..}|Fast::IcfgRd{..}|Fast::IcfgWr{..}|Fast::FOp{..}|Fast::Ext{..}|Fast::BitIns{..}|Fast::MinMax{..}|Fast::Div{..}
                |Fast::Un{..}|Fast::Mov2{..}|Fast::Mov2I{..}|Fast::LdPost{..}
                |Fast::LdPre{..}|Fast::LdPostR{..} => (tag::RUST,0,0,0,0,0),
            _ => return none,
        };
        Self {tag:t,a,b,c,imm,aux,next}
    }
    pub(super) fn supported(&self) -> bool { self.tag != tag::EXIT }
}
pub(super) fn available()->bool {unsafe{fm1_threaded_kernel_count()!=0}}
pub(super) fn metadata(op:&BOp)->u8 {
    op.len | (u8::from(op.careful)<<3) | (u8::from(op.pair_head)<<4) | (u8::from(op.glue)<<5)
}
pub(super) fn bind(pc:u32,ops:&[ThreadOp],original:&[BOp])->Option<unsafe extern "C" fn(*mut std::ffi::c_void)->u64> {
    if !(0x0200_0000..0x0400_0000).contains(&pc) || ops.is_empty() {return None;}
    let meta=original.iter().map(metadata).collect::<Vec<_>>();
    // The generated lookup compares every descriptor and byte of metadata before
    // returning ordinary, build-time linked machine code. No runtime code is emitted.
    unsafe{fm1_threaded_bind(pc,ops.as_ptr(),meta.as_ptr(),ops.len() as u32)}
}
pub(super) fn export(cpu:&Cpu)->String {
    use std::fmt::Write;
    let mut out=String::new();
    for (id,&(pc,start,len)) in cpu.blocks.iter().enumerate() {
        if !(0x0200_0000..0x0400_0000).contains(&pc) || len==0 {continue;}
        let _=write!(out,"{{\"pc\":{pc},\"id\":{id},\"ops\":[");
        for i in 0..len {
            let op=cpu.thread_ops[(start+i) as usize];
            if i!=0 {out.push(',');}
            let _=write!(out,"[{},{},{},{},{},{},{}]",op.tag,op.a,op.b,op.c,op.imm,op.aux,op.next);
        }
        out.push_str("],\"meta\":[");
        for i in 0..len {if i!=0{out.push(',');}let _=write!(out,"{}",metadata(&cpu.bops[(start+i) as usize]));}
        out.push_str("]}\n");
    }
    out
}
pub(super) struct Outcome { pub retired:u32, pub pc:u32, pub block:usize, pub index:u32, pub partial:bool }
/// No architectural or cache references survive this call. The bus's direct memory
/// view must stay stable until return, exactly as for its existing inline JIT paths.
pub(super) fn run<B:Bus>(cpu:&mut Cpu,bus:&mut B,block:usize,pc:u32,budget:u32,prepaid:bool,max_count:u32)->Option<Outcome> {
    // Static kernels bind only XIP. RAM-heavy routines are faster in the original
    // interpreter than repeatedly entering C and returning for unsupported tails.
    if !(0x0200_0000..0x0400_0000).contains(&pc) { return None; }
    if cpu.thread_blocks.get(block)?.hot == 0 { return None; }
    let room = bus.tick_room().saturating_add(u64::from(prepaid)).min(max_count as u64).min(u32::MAX as u64) as u32;
    if room == 0 { return None; }
    let mem = bus.thread_mem()?;
    let cpu_ptr=cpu as *mut Cpu;
    let mut state = State { regs:unsafe{std::ptr::addr_of_mut!((*cpu_ptr).regs).cast()},
        flags:unsafe{std::ptr::addr_of_mut!((*cpu_ptr).flags)},sp:unsafe{std::ptr::addr_of_mut!((*cpu_ptr).sp)},rets:unsafe{std::ptr::addr_of_mut!((*cpu_ptr).rets)},
        ram:mem.ram,ram_code:mem.ram_code,xip:mem.xip,ops:unsafe{(*cpu_ptr).thread_ops.as_ptr()},blocks:unsafe{(*cpu_ptr).thread_blocks.as_ptr()},map:unsafe{(*cpu_ptr).bmap.as_ptr()},
        ram_base:mem.ram_base,ram_len:mem.ram_len,xip_base:mem.xip_base,xip_len:mem.xip_len,
        map_mask:unsafe{((*cpu_ptr).bmap.len()-1) as u32},block_count:unsafe{(*cpu_ptr).thread_blocks.len() as u32},
        pc,block:block as u32,index:0,retired:0,budget,max_ops:room,status:0,
        cpu:cpu_ptr,bus:(bus as *mut B).cast(),helper:plain_helper::<B>,ticks_spent:0,prepaid:u32::from(prepaid),limit:room,panic:std::ptr::null_mut() };
    // SAFETY: repr(C) layouts are checked by a cross-language test. Descriptors and
    // map indices were built together, contain only generated tags/register indexes,
    // and remain allocated while C runs. CPU pointers name distinct architectural
    // fields; C only calls the plain-op helper below, which cannot change caches. Memory is an explicit Bus opt-in;
    // direct stores reject code words. The helper synchronizes ticks before MMIO and
    // refreshes the remaining room; RAM blocks leave C before invoking any helper.
    unsafe { fm1_threaded_run(&mut state); }
    if !state.panic.is_null() {
        // Unwind only after leaving the non-unwinding C ABI; Core's existing
        // render boundary catches this and halts the malformed firmware cleanly.
        let payload=unsafe{Box::from_raw(state.panic.cast::<Box<dyn std::any::Any+Send>>())};
        std::panic::resume_unwind(*payload);
    }
    if state.retired != 0 { bus.add_ticks((state.retired - u32::from(prepaid) - state.ticks_spent) as u64); }
    Some(Outcome {retired:state.retired,pc:state.pc,block:state.block as usize,index:state.index,partial:state.status != 0})
}
// Only plain operations arrive here; C retains raw pointers, not Rust references. Flush
// their precise instruction tick before the reference implementation can touch MMIO.
unsafe extern "C" fn plain_helper<B:Bus>(state:*mut State)->u32 {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe{plain_helper_inner::<B>(&mut *state)})) {
        Ok(pc)=>pc,
        Err(payload)=>{unsafe{(*state).panic=Box::into_raw(Box::new(payload)).cast();} 0},
    }
}
unsafe fn plain_helper_inner<B:Bus>(state:&mut State)->u32 {
    let cpu=unsafe{&mut *state.cpu};
    let bus=unsafe{&mut *state.bus.cast::<B>()};
    let ticks=state.retired+1-state.prepaid;
    bus.add_ticks((ticks-state.ticks_spent) as u64);
    state.ticks_spent=ticks;
    let fast=cpu.bops[state.index as usize].fast;
    let next=cpu.thread_ops[state.index as usize].next;
    let pc=cpu.exec_fast(bus,&fast,next).unwrap_or(next);
    state.max_ops=(state.retired as u64+1+bus.tick_room()).min(state.limit as u64) as u32;
    // Refresh pointers after the exclusive Rust reborrow. The C loop reloads its
    // architectural locals before resuming; cache allocations never change here.
    let cpu_ptr=cpu as *mut Cpu;
    state.regs=unsafe{std::ptr::addr_of_mut!((*cpu_ptr).regs).cast()};
    state.flags=unsafe{std::ptr::addr_of_mut!((*cpu_ptr).flags)};
    state.sp=unsafe{std::ptr::addr_of_mut!((*cpu_ptr).sp)};
    state.rets=unsafe{std::ptr::addr_of_mut!((*cpu_ptr).rets)};
    if let Some(mem)=bus.thread_mem() {
        state.ram=mem.ram;state.ram_code=mem.ram_code;state.xip=mem.xip;
        state.ram_base=mem.ram_base;state.ram_len=mem.ram_len;state.xip_base=mem.xip_base;state.xip_len=mem.xip_len;
    } else {state.max_ops=state.retired+1;}
    pc
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn c_and_rust_descriptor_layouts_match() {
        let expected=((std::mem::size_of::<State>() as u64)<<32)|((std::mem::size_of::<ThreadBlock>() as u64)<<16)|std::mem::size_of::<ThreadOp>() as u64;
        assert_eq!(unsafe{fm1_threaded_layout()},expected);
        let expected=[std::mem::offset_of!(State,regs) as u32,std::mem::offset_of!(State,flags) as u32,std::mem::offset_of!(State,sp) as u32,std::mem::offset_of!(State,rets) as u32,std::mem::offset_of!(State,ram) as u32,std::mem::offset_of!(State,ram_code) as u32,std::mem::offset_of!(State,xip) as u32,std::mem::offset_of!(State,ops) as u32,std::mem::offset_of!(State,blocks) as u32,std::mem::offset_of!(State,map) as u32,std::mem::offset_of!(State,ram_base) as u32,std::mem::offset_of!(State,ram_len) as u32,std::mem::offset_of!(State,xip_base) as u32,std::mem::offset_of!(State,xip_len) as u32,std::mem::offset_of!(State,map_mask) as u32,std::mem::offset_of!(State,block_count) as u32,std::mem::offset_of!(State,pc) as u32,std::mem::offset_of!(State,block) as u32,std::mem::offset_of!(State,index) as u32,std::mem::offset_of!(State,retired) as u32,std::mem::offset_of!(State,budget) as u32,std::mem::offset_of!(State,max_ops) as u32,std::mem::offset_of!(State,status) as u32,std::mem::offset_of!(State,cpu) as u32,std::mem::offset_of!(State,bus) as u32,std::mem::offset_of!(State,helper) as u32,std::mem::offset_of!(State,ticks_spent) as u32,std::mem::offset_of!(State,prepaid) as u32,std::mem::offset_of!(State,limit) as u32,std::mem::offset_of!(State,panic) as u32];
        let mut count=0;
        let offsets=unsafe{fm1_threaded_offsets(&mut count)};
        assert_eq!(count as usize,expected.len());
        assert_eq!(unsafe{std::slice::from_raw_parts(offsets,count as usize)},expected);
    }
}

#[cfg(test)]
mod differential {
    use super::*;
    use crate::{AddBranch,JitMem};
    const PC:u32=0x0200_0000;
    const RAM:u32=0x1000;
    #[derive(Clone)]
    struct Memory {
        ram:Vec<u8>, code:Vec<u8>, xip:Vec<u8>, cycles:u64, due:u64, version:u64,
        events:Vec<(u64,bool,u32,u32)>, pending:bool,
    }
    impl Memory {
        fn new(due:u64)->Self { Self {ram:(0..512).map(|i|i as u8).collect(),code:vec![0;129],xip:vec![0;1024],cycles:1,due,version:0,events:vec![],pending:false} }
        fn store(&mut self,a:u32,v:u32,w:usize) {
            let o=a.wrapping_sub(RAM) as usize;
            if o+w<=self.ram.len() && (w!=2 || a&1==0) {
                if self.code[o>>2]!=0 {self.version+=1;}
                self.ram[o..o+w].copy_from_slice(&v.to_le_bytes()[..w]);
            } else { self.events.push((self.cycles,true,a,v)); self.due=self.cycles; }
        }
    }
    impl Bus for Memory {
        fn read8(&mut self,a:u32)->u8 {
            let o=a.wrapping_sub(RAM) as usize;
            if o<self.ram.len(){self.ram[o]} else {(self.read32(a&!3)>>((a&3)*8)) as u8}
        }
        fn read16(&mut self,a:u32)->u16 {(self.read32(a&!3)>>((a&2)*8)) as u16}
        fn read32(&mut self,a:u32)->u32 {
            assert_ne!(a,0xdead_beef,"malformed guest memory access");
            let o=a.wrapping_sub(RAM) as usize;
            if o+4<=self.ram.len(){return u32::from_le_bytes(self.ram[o..o+4].try_into().unwrap());}
            let o=a.wrapping_sub(PC) as usize;
            if o+4<=self.xip.len(){return u32::from_le_bytes(self.xip[o..o+4].try_into().unwrap());}
            self.events.push((self.cycles,false,a,4)); 0x8000_0000|self.cycles as u32
        }
        fn write8(&mut self,a:u32,v:u8){self.store(a,v as u32,1)}
        fn write16(&mut self,a:u32,v:u16){self.store(a,v as u32,2)}
        fn write32(&mut self,a:u32,v:u32){self.store(a,v,4)}
        fn tick(&mut self)->bool{self.cycles+=1;self.cycles>=self.due}
        fn tick_room(&self)->u64{self.due.saturating_sub(self.cycles+1)}
        fn add_ticks(&mut self,n:u64){self.cycles+=n;}
        fn irq_window(&mut self){if self.pending{self.due=self.cycles;}}
        fn code_writes(&self)->Option<u64>{Some(self.version)}
        fn jit_mem(&mut self)->Option<JitMem>{Some(JitMem{ram:self.ram.as_mut_ptr(),ram_base:RAM,ram_len:self.ram.len() as u32,ram_code:self.code.as_ptr(),xip:self.xip.as_ptr(),xip_base:PC,xip_len:self.xip.len() as u32})}
        fn thread_mem(&mut self)->Option<JitMem>{self.jit_mem()}
    }
    fn install(cpu:&mut Cpu,program:&[(u32,Vec<(Fast,u8)>)]) {
        cpu.bmap=vec![0;512];
        for (pc,ops) in program {
            let start=cpu.bops.len() as u32;let mut p=*pc;
            for &(fast,len) in ops {
                let op=BOp{fast,len,careful:false,pair_head:false,glue:false};p+=len as u32;
                cpu.bops.push(op);cpu.thread_ops.push(ThreadOp::compile(op,p));
            }
            let len=ops.len() as u32;
            cpu.blocks.push((*pc,start,len));
            cpu.bpairs.push(AddBranch::from_ops(&cpu.bops[start as usize..]));
            cpu.bbytes.push(None);cpu.bver.push(0);
            cpu.thread_blocks.push(ThreadBlock{pc:*pc,start,len,hot:u32::from(len>0&&cpu.thread_ops[start as usize].supported()),kernel:None});
            cpu.bmap[(*pc>>1) as usize&511]=cpu.blocks.len() as u32;
        }
    }
    fn same(a:&Cpu,b:&Cpu,ma:&Memory,mb:&Memory) {
        assert_eq!((a.regs,a.flags,a.sp,a.rets,a.pc,a.insn_count,a.ie),(b.regs,b.flags,b.sp,b.rets,b.pc,b.insn_count,b.ie));
        assert_eq!((&ma.ram,&ma.events,ma.cycles,ma.due,ma.version),(&mb.ram,&mb.events,mb.cycles,mb.due,mb.version));
    }
    #[test]
    fn threaded_chains_match_rust_at_every_budget_tick_mmio_and_code_store_boundary() {
        let program=vec![
            (PC,vec![(Fast::MovI{d:2,v:RAM},2),(Fast::AddRI{d:0,s:0,v:1},2),
                (Fast::StW{s:0,b:2,off:4},4),(Fast::Call{target:PC+64},4)]),
            (PC+64,vec![(Fast::LdW{d:1,b:2,off:4},4),(Fast::AddRR{d:1,a:1,b:0},2),(Fast::Rts,2)]),
            (PC+12,vec![(Fast::LdW{d:3,b:4,off:0},4),(Fast::SetIe{on:true},2),(Fast::BrINe{a:0,v:9,target:PC},4)]),
            (PC+22,vec![(Fast::Goto{target:PC},2)]),
        ];
        for budget in 1..40 {for due in 2..45 {for address in [RAM,0x4000_0000] {for code in [false,true] {for pending in [false,true] {
            let make=|disabled|{let mut cpu=Cpu::new(PC);cpu.no_threaded=disabled;cpu.regs[4]=address;cpu.sp=RAM+256;install(&mut cpu,&program);
                let mut mem=Memory::new(due);mem.code[1]=u8::from(code);mem.pending=pending;(cpu,mem)};
            let (mut a,mut ma)=make(false);let (mut b,mut mb)=make(true);
            let ra=a.run_fast(&mut ma,budget).unwrap();let rb=b.run_fast(&mut mb,budget).unwrap();
            assert_eq!(ra,rb,"budget={budget} due={due} address={address:x} code={code}");same(&a,&b,&ma,&mb);
        }}}}}
    }
    #[test]
    fn ram_blocks_leave_architecture_and_ticks_to_the_rust_interpreter() {
        let mut cpu=Cpu::new(RAM);cpu.no_threaded=false;cpu.regs[0]=123;
        install(&mut cpu,&[(RAM,vec![(Fast::AddRI{d:0,s:0,v:1},2),(Fast::Goto{target:RAM},2)])]);
        let mut mem=Memory::new(100);
        assert!(run(&mut cpu,&mut mem,0,RAM,20,true,100).is_none());
        assert_eq!(cpu.regs[0],123);assert_eq!(mem.cycles,1);assert!(mem.events.is_empty());
    }
    #[test]
    fn generated_kernels_match_generic_dispatch_and_exact_descriptor_guards() {
        let count=unsafe{fm1_threaded_kernel_count()};
        if std::env::var_os("FM1_STATIC_KERNELS").is_some(){assert!(count>0,"requested static kernels must be linked");}
        if count==0{return;}
        let mut infos=Vec::new();
        for i in 0..count {
            let (mut pc,mut length)=(0,0);let mut ops=std::ptr::null();let mut meta=std::ptr::null();
            let kernel=unsafe{fm1_threaded_kernel_info(i,&mut pc,&mut ops,&mut meta,&mut length)}.unwrap();
            infos.push((pc,unsafe{std::slice::from_raw_parts(ops,length as usize)}.to_vec(),
                unsafe{std::slice::from_raw_parts(meta,length as usize)}.to_vec(),kernel));
        }
        for (pc,ops,meta,kernel) in &infos {
            let bound=unsafe{fm1_threaded_bind(*pc,ops.as_ptr(),meta.as_ptr(),ops.len() as u32)}.unwrap();
            assert_eq!(bound as usize,*kernel as usize);
            assert!(unsafe{fm1_threaded_bind(*pc,ops.as_ptr(),meta.as_ptr(),0)}.is_none());
            assert!(unsafe{fm1_threaded_bind(*pc^0x8000_0000,ops.as_ptr(),meta.as_ptr(),ops.len() as u32)}.is_none());
            for byte in 0..ops.len()*16 {
                let mut changed=ops.clone();
                unsafe{*changed.as_mut_ptr().cast::<u8>().add(byte)^=0x80;}
                let expected=infos.iter().find(|(p,o,m,_)|p==pc&&o==&changed&&m==meta).map(|x|x.3 as usize);
                let actual=unsafe{fm1_threaded_bind(*pc,changed.as_ptr(),meta.as_ptr(),changed.len() as u32)}.map(|f|f as usize);
                assert_eq!(actual,expected,"descriptor byte {byte} at {pc:x}");
            }
            for byte in 0..meta.len() {
                let mut changed=meta.clone();changed[byte]^=0x80;
                assert!(unsafe{fm1_threaded_bind(*pc,ops.as_ptr(),changed.as_ptr(),ops.len() as u32)}.is_none());
            }
            for seed in 0..96u32 {
                let make=|| {
                    let mut cpu=Cpu::new(*pc);let mut mem=Memory::new(1000);
                    let mut random=seed+1;
                    for r in &mut cpu.regs {random^=random<<13;random^=random>>17;random^=random<<5;
                        *r=match seed%4 {0=>random,1=>RAM+(random%480),2=>RAM+((random%120)*4),_=>PC+(random%1000)};}
                    cpu.flags=seed&15;cpu.sp=RAM+(seed*4)%500;cpu.rets=seed.wrapping_mul(1234567);
                    if seed&8!=0 {for i in (0..mem.code.len()).step_by(3){mem.code[i]=1;}}
                    cpu.thread_ops=ops.clone();cpu.bmap=vec![0];
                    cpu.thread_blocks=vec![ThreadBlock{pc:*pc,start:0,len:ops.len() as u32,hot:1,kernel:None}];
                    (cpu,mem)
                };
                let (mut a,mut ma)=make();let (mut b,mut mb)=make();
                let mut sa=test_state(&mut a,&mut ma,*pc,ops.len() as u32);
                let result=unsafe{kernel((&mut sa as *mut State).cast())};
                let retired=(result>>32) as u32;assert!(retired<=ops.len() as u32);
                let mut sb=test_state(&mut b,&mut mb,*pc,retired);
                unsafe{fm1_threaded_run(&mut sb);}
                assert!(sb.panic.is_null(),"generic dispatcher unexpectedly passed kernel prefix");
                assert_eq!((retired,result as u32),(sb.retired,sb.pc),"pc={pc:x} seed={seed}");
                same(&a,&b,&ma,&mb);
                if seed<12 && seed%8<4 {
                    let len=ops.len() as u32;
                    for limit in [0,1,len-1,len,len+1] {for budget in [1,len-1,len] {
                        let (mut a,mut ma)=make();let (mut b,mut mb)=make();
                        a.thread_blocks[0].kernel=Some(*kernel);
                        let mut sa=test_state(&mut a,&mut ma,*pc,limit);
                        let mut sb=test_state(&mut b,&mut mb,*pc,limit);
                        sa.budget=budget;sb.budget=budget;
                        unsafe{fm1_threaded_run(&mut sa);fm1_threaded_run(&mut sb);}
                        assert_eq!((sa.retired,sa.pc,sa.index,sa.status,sa.panic.is_null()),
                            (sb.retired,sb.pc,sb.index,sb.status,sb.panic.is_null()),
                            "entry pc={pc:x} seed={seed} limit={limit} budget={budget}");
                        same(&a,&b,&ma,&mb);
                    }}
                }
            }
        }
        eprintln!("validated {count} generated kernels, every descriptor byte, metadata, and 96 architectural states each");
    }
    unsafe extern "C" fn unexpected_helper(s:*mut State)->u32 {
        unsafe{(*s).panic=std::ptr::dangling_mut();}0
    }
    fn test_state(cpu:&mut Cpu,mem:&mut Memory,pc:u32,limit:u32)->State {
        let view=mem.thread_mem().unwrap();let c=cpu as *mut Cpu;
        State {regs:unsafe{std::ptr::addr_of_mut!((*c).regs).cast()},flags:unsafe{std::ptr::addr_of_mut!((*c).flags)},
            sp:unsafe{std::ptr::addr_of_mut!((*c).sp)},rets:unsafe{std::ptr::addr_of_mut!((*c).rets)},
            ram:view.ram,ram_code:view.ram_code,xip:view.xip,ops:unsafe{(*c).thread_ops.as_ptr()},
            blocks:unsafe{(*c).thread_blocks.as_ptr()},map:unsafe{(*c).bmap.as_ptr()},
            ram_base:view.ram_base,ram_len:view.ram_len,xip_base:view.xip_base,xip_len:view.xip_len,map_mask:0,block_count:1,
            pc,block:0,index:0,retired:0,budget:limit,max_ops:limit,status:0,cpu:c,bus:(mem as *mut Memory).cast(),
            helper:unexpected_helper,ticks_spent:0,prepaid:0,limit,panic:std::ptr::null_mut()}
    }
    #[test]
    fn helper_panics_unwind_only_after_returning_from_c() {
        let mut cpu=Cpu::new(PC);cpu.no_threaded=false;cpu.regs[4]=0xdead_beef;
        install(&mut cpu,&[(PC,vec![(Fast::Nop,2),(Fast::LdW{d:0,b:4,off:0},4)])]);
        let mut mem=Memory::new(100);
        let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||cpu.run_fast(&mut mem,10)));
        assert!(result.is_err());assert_eq!(mem.cycles,2,"faulting instruction tick is spent exactly once");
    }
    #[test]
    fn glued_pairs_preserve_irq_hold_and_existing_careful_states() {
        let program=vec![(PC,vec![(Fast::Nop,2),(Fast::MovI{d:1,v:19},2),
            (Fast::LdW{d:2,b:4,off:0},4),(Fast::Goto{target:PC},2)])];
        for budget in 1..25 {for due in 2..25 {for address in [RAM,0x4000_0000] {for mode in 0..5 {
            let make=|disabled| {
                let mut cpu=Cpu::new(PC);cpu.no_threaded=disabled;cpu.regs[4]=address;install(&mut cpu,&program);
                cpu.bops[1].pair_head=true;cpu.bops[1].glue=true;
                cpu.thread_ops[1]=ThreadOp::compile(cpu.bops[1],PC+4);
                match mode {
                    1=>{let old=cpu.regs;let mut new=old;new[12]=123;cpu.pair_pending=Some((old,new));},
                    2=>cpu.pred_skips.push((PC+32,PC+40)),
                    3=>{cpu.rep_start=PC;cpu.rep_end=PC+32;cpu.rep_count=2;},
                    4=>cpu.hold_irq=1,
                    _=>{},
                }
                (cpu,Memory::new(due))
            };
            let (mut a,mut ma)=make(false);let (mut b,mut mb)=make(true);
            assert_eq!(a.run_fast(&mut ma,budget).unwrap(),b.run_fast(&mut mb,budget).unwrap(),"budget={budget} due={due} mode={mode}");
            same(&a,&b,&ma,&mb);
            assert_eq!((a.hold_irq,a.pair_pending,&a.pred_skips,a.rep_start,a.rep_end,a.rep_count),
                (b.hold_irq,b.pair_pending,&b.pred_skips,b.rep_start,b.rep_end,b.rep_count));
            if mode==0 && due==3 && budget>=1 {assert_eq!(a.hold_irq,1,"due between glued head and tail");}
        }}}}
    }
    #[test]
    fn each_supported_opcode_matches_reference_with_aliases_overflow_and_memory_edges() {
        let mut covered=[false;256];
        for seed in [0u32,1,31,32,0x7fff_ffff,0x8000_0000,u32::MAX,RAM,RAM+1,RAM+509,PC,PC+1021] {
          for d in [0u8,1,2,15] {
            let mut ops=vec![Fast::Nop,Fast::Mov{d,s:1},Fast::MovI{d,v:seed},Fast::AddRI{d,s:1,v:seed},
                Fast::AddRR{d,a:1,b:2},Fast::SubRR{d,a:1,b:2},Fast::AndI{d,s:1,v:seed},Fast::AndBit{d,s:1,r:2},
                Fast::ShlR{d,a:1,b:2},Fast::ShrR{d,a:1,b:2},Fast::ShrI{d,s:1,n:seed as u8},Fast::MulI{d,s:1,v:seed},
                Fast::ShlI{d,s:1,n:seed as u8},Fast::SarI{d,s:1,n:seed as u8},Fast::Goto{target:seed},Fast::Call{target:seed},Fast::Rts,
                Fast::PushRets{n:d},Fast::PopPc{n:d},Fast::SpAdd{v:seed},Fast::SpFromR{s:d},Fast::RFromSp{d,v:seed},
                Fast::MemA4{b:1,off:0,op:Op::Add,rk:1,rv:seed},Fast::PushRet,Fast::PopRet,Fast::PopRets,Fast::Un{d,s:1,k:0},Fast::FOp{d,a:1,b:2,op:0}];
            for p in [0,1,31,32,255] {for l in [0,1,31,32,255] {for signed in [false,true] {ops.push(Fast::BitExt{d,s:1,p,l,signed});}}}
            for alu in [Op::Add,Op::Sub,Op::RSub,Op::And,Op::AndNot,Op::Or,Op::Xor,Op::Mul,Op::Shl,Op::Shr,Op::Sar] {
                ops.extend([Fast::Alu3{d,a:1,b:2,op:alu},Fast::Alu3I{d,a:1,v:seed,op:alu}]);
            }
            for c in [Cond::Eq,Cond::Ne,Cond::LtU,Cond::GtU,Cond::LeU,Cond::GeU,Cond::LtS,Cond::GtS,Cond::LeS,Cond::GeS] {
                ops.extend([Fast::BrI{a:1,v:seed,cond:c,target:seed},Fast::BrR{a:1,b:2,cond:c,target:seed},Fast::DecBr{r:d,cond:c,v:seed,target:seed}]);
            }
            for rk in 0..3 {for alt in [false,true] {
                ops.push(Fast::BitBr{r:d,mk:rk,ne:alt,mv:seed,target:seed});
                for fam in [0,1,2,4,5,6] {ops.push(Fast::IfBlk{a:d,rk,fam,alt,has_else:false,rv:seed,then_d:8,else_d:0});}
            }}
            for w in [1,2,4] {for signed in [false,true] {
                ops.extend([Fast::Ld{d,b:Base::Reg(1),off:0,w,signed},Fast::Ld{d,b:Base::Sp,off:0,w,signed},
                    Fast::LdIdx{d,b:1,i:2,sh:0,w,signed},Fast::StIdx{s:d,b:1,i:2,sh:0,w},Fast::St{s:d,b:Base::Reg(1),off:0,w},Fast::StPost{s:d,b:1,w,inc:seed}]);
            }}
            for fast in ops {
                let make=||{let mut cpu=Cpu::new(PC);for i in 0..16{cpu.regs[i]=seed.wrapping_add(i as u32);}cpu.regs[1]=seed;cpu.regs[2]=0;
                    cpu.flags=15;cpu.sp=RAM+256;cpu.rets=PC+64;install(&mut cpu,&[(PC,vec![(fast,4)])]);(cpu,Memory::new(100))};
                let (mut a,mut ma)=make();let (mut b,mut mb)=make();
                let tag=a.thread_ops[0].tag;assert_ne!(tag,tag::EXIT,"{fast:?}");
                let result=run(&mut a,&mut ma,0,PC,1,true,100).unwrap();
                let actual=if result.retired==0 {assert!(result.partial);same(&a,&b,&ma,&mb);a.exec_fast(&mut ma,&fast,PC+4).unwrap_or(PC+4)}
                    else {assert_eq!(result.retired,1);covered[tag as usize]=true;result.pc};
                let expected=b.exec_fast(&mut mb,&fast,PC+4).unwrap_or(PC+4);
                assert_eq!(actual,expected,"{fast:?} seed={seed:x}");same(&a,&b,&ma,&mb);
            }
          }
        }
        for tag in tag::NOP..=tag::RUST {assert!(covered[tag as usize],"opcode tag {tag} never executed by C");}
    }
}
