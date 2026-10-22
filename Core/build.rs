use std::{env, path::PathBuf, process::Command};
fn main() {
    if env::var_os("CARGO_FEATURE_STORE_NATIVE").is_some() {
        assert!(
            env::var_os("CARGO_FEATURE_RESEARCH").is_none(),
            "store-native requires --no-default-features"
        );
        assert!(
            [
                "FM1_NATIVE_SLOOP",
                "FM1_NATIVE_FAMILY",
                "FM1_NATIVE_SKIFF",
                "FM1_NATIVE_EXPANSION",
                "FM1_NATIVE_OFFICIAL_PREVIEW"
            ]
            .iter()
            .any(|key| env::var_os(key).is_some()),
            "Store build requires prepared source-native engines; no interpreter fallback"
        );
    }
    for key in [
        "ANDROID_NDK_HOME",
        "ANDROID_NDK_ROOT",
        "FM1_NATIVE_LLVM_BIN",
    ] {
        println!("cargo:rerun-if-env-changed={key}");
    }
    println!("cargo:rustc-check-cfg=cfg(fm1_native_sloop)");
    println!("cargo:rustc-check-cfg=cfg(fm1_native_family)");
    println!("cargo:rustc-check-cfg=cfg(fm1_native_official_preview)");
    println!("cargo:rerun-if-env-changed=FM1_NATIVE_FAMILY");
    println!("cargo:rerun-if-env-changed=FM1_NATIVE_OFFICIAL_PREVIEW");
    println!("cargo:rustc-check-cfg=cfg(fm1_native_expansion)");
    println!("cargo:rustc-check-cfg=cfg(fm1_native_skiff)");
    build_extra(
        "FM1_NATIVE_EXPANSION",
        "expansion_build.py",
        "fm1_native_expansion",
    );
    build_extra("FM1_NATIVE_SKIFF", "skiff_build.py", "fm1_native_skiff");
    build_family();
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
    } else if target.ends_with("-linux-android") {
        "android"
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

fn build_family() {
    let target = env::var("TARGET").unwrap();
    let sdk = match target.as_str() {
        "aarch64-apple-darwin" => "macosx",
        "aarch64-apple-ios-sim" => "iphonesimulator",
        "aarch64-apple-ios" => "iphoneos",
        "aarch64-linux-android" | "x86_64-linux-android" => "android",
        _ => {
            if env::var_os("FM1_NATIVE_FAMILY").is_some()
                || env::var_os("FM1_NATIVE_OFFICIAL_PREVIEW").is_some()
            {
                panic!("unsupported native firmware target {target}")
            }
            return;
        }
    };
    if let Some(source) = env::var_os("FM1_NATIVE_FAMILY") {
        let root = PathBuf::from(&source);
        for kind in ["felucca", "x0x", "melodee"] {
            for part in [
                "firmware",
                "tools",
                "assets",
                "fonts",
                "web/fukiai.ttf",
                "build/gen",
                ".git/HEAD",
            ] {
                println!(
                    "cargo:rerun-if-changed={}",
                    root.join(kind).join(part).display()
                );
            }
        }
        let out = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("native-family");
        assert!(
            Command::new("python3")
                .args(["native/build_family.py", "--source"])
                .arg(source)
                .arg("--out")
                .arg(&out)
                .args(["--target", &target, "--sdk", sdk])
                .status()
                .expect("build pinned native family")
                .success(),
            "native family build failed; no silent fallback"
        );
        println!("cargo:rustc-link-search=native={}", out.display());
        println!("cargo:rustc-link-lib=static=fm1_native_family");
        println!("cargo:rustc-cfg=fm1_native_family");
    }
    if let Some(source) = env::var_os("FM1_NATIVE_OFFICIAL_PREVIEW") {
        println!(
            "cargo:rerun-if-changed={}",
            PathBuf::from(&source).display()
        );
        let out = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("native-official-preview");
        assert!(
            Command::new("python3")
                .args(["native/official_preview_build.py", "--source"])
                .arg(source)
                .arg("--out")
                .arg(&out)
                .args(["--target", &target, "--sdk", sdk])
                .status()
                .expect("build pinned official source preview")
                .success(),
            "official source preview build failed; no silent fallback"
        );
        println!("cargo:rustc-link-search=native={}", out.display());
        println!("cargo:rustc-link-lib=static=fm1_official_preview");
        println!("cargo:rustc-cfg=fm1_native_official_preview");
    }
}

fn build_extra(variable: &str, builder: &str, library: &str) {
    println!("cargo:rerun-if-env-changed={variable}");
    let Some(source) = env::var_os(variable) else {
        return;
    };
    let target = env::var("TARGET").unwrap();
    let sdk = match target.as_str() {
        "aarch64-apple-darwin" => "macosx",
        "aarch64-apple-ios-sim" => "iphonesimulator",
        "aarch64-apple-ios" => "iphoneos",
        "aarch64-linux-android" | "x86_64-linux-android" => "android",
        _ => panic!("unsupported native firmware target {target}"),
    };
    let root = PathBuf::from(&source);
    if variable == "FM1_NATIVE_EXPANSION" {
        for kind in ["fomni", "jangada"] {
            for part in [
                "firmware",
                "tools",
                "assets",
                "host",
                "web/words",
                "build/gen",
                ".git/HEAD",
            ] {
                println!(
                    "cargo:rerun-if-changed={}",
                    root.join(kind).join(part).display()
                );
            }
        }
    } else {
        println!("cargo:rerun-if-changed={}", root.display());
    }
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join(library);
    assert!(
        Command::new("python3")
            .arg(format!("native/{builder}"))
            .arg("--source")
            .arg(source)
            .arg("--out")
            .arg(&out)
            .args(["--target", &target, "--sdk", sdk])
            .status()
            .expect("build pinned native firmware")
            .success(),
        "native firmware build failed; no silent fallback"
    );
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static={library}");
    println!("cargo:rustc-cfg={library}");
}
