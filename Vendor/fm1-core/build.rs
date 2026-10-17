use std::{env, fs, path::PathBuf, process::Command};
fn output(command: &mut Command) -> String {
    let result = command.output().expect("run Apple compiler tool");
    assert!(result.status.success(), "tool failed: {}", String::from_utf8_lossy(&result.stderr));
    String::from_utf8(result.stdout).unwrap().trim().to_owned()
}
fn main() {
    println!("cargo:rustc-check-cfg=cfg(fm1_threaded)");
    for file in ["build.rs", "src/threaded/ops.def", "src/threaded/engine.c", "src/threaded/engine.h", "src/threaded.rs", "tools/generate_static_kernels.py"] {
        println!("cargo:rerun-if-changed={file}");
    }
    println!("cargo:rerun-if-env-changed=FM1_STATIC_KERNELS");
    println!("cargo:rerun-if-env-changed=FM1_C_SANITIZE");
    let target = env::var("TARGET").unwrap();
    if !target.contains("apple-darwin") && !target.contains("apple-ios") { return; }
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    if let Some(path)=env::var_os("FM1_STATIC_KERNELS") {
        println!("cargo:rerun-if-changed={}",PathBuf::from(&path).display());
        let path=PathBuf::from(path);
        println!("cargo:rerun-if-changed={}",path.with_extension("manifest.json").display());
        let status=Command::new("python3").arg("tools/generate_static_kernels.py").arg("--verify").arg(&path)
            .status().expect("verify generated kernels with Python standard library");
        assert!(status.success(),"static kernels are missing, corrupt, or stale; regenerate before building");
        fs::copy(path,out.join("static_kernels.inc")).expect("copy local static kernels");
    } else {
        fs::write(out.join("static_kernels.inc"),"Fm1ThreadKernel fm1_threaded_bind(uint32_t pc,const Fm1ThreadOp *ops,const uint8_t *meta,uint32_t length) {(void)pc;(void)ops;(void)meta;(void)length;return NULL;}\nuint32_t fm1_threaded_kernel_count(void){return 0;}\nFm1ThreadKernel fm1_threaded_kernel_info(uint32_t i,uint32_t *pc,const Fm1ThreadOp **ops,const uint8_t **meta,uint32_t *length){(void)i;(void)pc;(void)ops;(void)meta;(void)length;return NULL;}\n").unwrap();
    }
    let tags = fs::read_to_string("src/threaded/ops.def").unwrap().lines().enumerate()
        .map(|(i,line)| format!("pub const {}: u8 = {i};\n", line.strip_prefix("OP(").unwrap().strip_suffix(')').unwrap())).collect::<String>();
    fs::write(out.join("thread_tags.rs"), tags).unwrap();
    let simulator = target.ends_with("-sim") || target.starts_with("x86_64-apple-ios");
    let sdk = if target.contains("apple-darwin") { "macosx" } else if simulator { "iphonesimulator" } else { "iphoneos" };
    let clang = output(Command::new("xcrun").args(["--sdk",sdk,"--find","clang"]));
    let sysroot = output(Command::new("xcrun").args(["--sdk",sdk,"--show-sdk-path"]));
    let arch = if target.starts_with("aarch64") { "arm64" } else { "x86_64" };
    let triple = if sdk == "macosx" { format!("{arch}-apple-macos11.0") }
        else { format!("{arch}-apple-ios17.0{}", if simulator { "-simulator" } else { "" }) };
    let object = out.join("fm1_threaded.o");
    let mut compiler=Command::new(clang);
    if env::var_os("FM1_C_SANITIZE").is_some(){compiler.args(["-fsanitize=address,undefined","-fno-omit-frame-pointer"]);}
    let status = compiler.args(["-target",&triple,"-isysroot",&sysroot,"-O3","-std=gnu11",
        "-fno-strict-aliasing","-fvisibility=hidden","-Wall","-Wextra","-Werror","-c","src/threaded/engine.c","-o"])
        .arg(&object).arg("-I").arg(&out).status().expect("compile static threaded interpreter");
    assert!(status.success(), "threaded interpreter C compilation failed");
    let archive = out.join("libfm1_threaded.a");
    let status = Command::new("xcrun").args(["ar","crs"]).arg(&archive).arg(&object).status().unwrap();
    assert!(status.success(), "archive static interpreter");
    println!("cargo:rustc-link-search=native={}",out.display());
    println!("cargo:rustc-link-lib=static=fm1_threaded");
    println!("cargo:rustc-cfg=fm1_threaded");
}
