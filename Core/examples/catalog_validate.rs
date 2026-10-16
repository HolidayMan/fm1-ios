use fm1_ios_core::*;
use std::{env,fs};
fn main() {
    let mut failed = 0;
    for path in env::args().skip(1) {
        let bytes = fs::read(&path).unwrap();
        let mut error = [0u8;512];
        let machine = unsafe { instrument_create(bytes.as_ptr(),bytes.len(),error.as_mut_ptr(),error.len()) };
        if machine.is_null() {
            failed += 1;
            println!("REJECTED {}: {}",path,String::from_utf8_lossy(&error).trim_end_matches('\0'));
        } else {
            unsafe { instrument_destroy(machine) };
            println!("VALID PACKAGE {}",path);
        }
    }
    assert_eq!(failed,0,"one or more catalogue packages were rejected");
}
