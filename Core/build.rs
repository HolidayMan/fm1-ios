use std::{env, path::PathBuf, process::Command};
fn main() {
    println!("cargo:rustc-check-cfg=cfg(fm1_native_sloop)");
    println!("cargo:rerun-if-env-changed=FM1_NATIVE_SLOOP");
    println!("cargo:rerun-if-changed=native");
    let Some(source) = env::var_os("FM1_NATIVE_SLOOP") else {
        return;
    };
    let source_path = PathBuf::from(&source);
    for path in [
        source_path.join("firmware"),
        source_path.join("tools"),
        source_path.join("assets"),
        source_path.join("build/generated"),
        source_path.join(".git/HEAD"),
    ] {
        println!("cargo:rerun-if-changed={}", path.display());
    }
    let target = env::var("TARGET").unwrap();
    let sdk = if target == "aarch64-apple-darwin" {
        "macosx"
    } else if target == "aarch64-apple-ios-sim" {
        "iphonesimulator"
    } else if target == "aarch64-apple-ios" {
        "iphoneos"
    } else {
        panic!("unsupported native SLOOP target {target}")
    };
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("native-sloop");
    assert!(
        Command::new("python3")
            .args(["native/build.py", "--source"])
            .arg(source)
            .arg("--out")
            .arg(&out)
            .args(["--target", &target, "--sdk", sdk])
            .status()
            .expect("build pinned native SLOOP")
            .success(),
        "native SLOOP build failed; no silent fallback"
    );
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=fm1_native_sloop");
    println!("cargo:rustc-cfg=fm1_native_sloop");
}
