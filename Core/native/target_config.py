"""Explicit Apple/Android native build configuration; never downloads toolchains."""
import os
from pathlib import Path
import subprocess

TRIPLES = {
    'aarch64-apple-darwin': 'arm64-apple-macos11.0',
    'aarch64-apple-ios': 'arm64-apple-ios17.0',
    'aarch64-apple-ios-sim': 'arm64-apple-ios17.0-simulator',
    'aarch64-linux-android': 'aarch64-linux-android26',
    'x86_64-linux-android': 'x86_64-linux-android26',
}

class Toolchain:
    def __init__(self, target, sdk, llvm=False):
        self.triple = TRIPLES[target]
        self.android = target.endswith('-android')
        host_llvm = Path(os.environ.get('FM1_NATIVE_LLVM_BIN', '/opt/homebrew/opt/llvm/bin')).resolve()
        self.link = host_llvm / 'llvm-link'
        if self.android:
            if sdk != 'android':
                raise SystemExit('Android target requires --sdk android')
            ndk = os.environ.get('ANDROID_NDK_HOME') or os.environ.get('ANDROID_NDK_ROOT')
            if not ndk:
                raise SystemExit('Android native engines require explicit ANDROID_NDK_HOME')
            prebuilt = Path(ndk) / 'toolchains/llvm/prebuilt'
            hosts = sorted(prebuilt.glob('*'))
            if len(hosts) != 1:
                raise SystemExit('Expected one NDK host toolchain under ' + str(prebuilt))
            self.cc = hosts[0] / 'bin/clang'
            # LLVM-link must understand the compiler IR. The selected host LLVM
            # compiler can target the exact NDK sysroot without linking host libc.
            if llvm:
                self.cc = host_llvm / 'clang'
            self.flags = ['--sysroot=' + str(hosts[0] / 'sysroot'), '-fPIC']
            self.ar = [str(hosts[0] / 'bin/llvm-ar')]
            self.bss, self.data = '.felbss', '.feldata'
        else:
            expected = {'aarch64-apple-darwin':'macosx', 'aarch64-apple-ios':'iphoneos', 'aarch64-apple-ios-sim':'iphonesimulator'}[target]
            if sdk != expected:
                raise SystemExit('Native target and Apple SDK do not match')
            self.cc = host_llvm / 'clang' if llvm else subprocess.check_output(['xcrun','--sdk',sdk,'--find','clang'], text=True).strip()
            root = subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'], text=True).strip()
            self.flags = ['-isysroot', root]
            self.ar = ['xcrun','ar']
            self.bss, self.data = '__DATA,__felbss', '__DATA,__feldata'
        if not Path(self.cc).is_file():
            raise SystemExit('Missing native compiler: ' + str(self.cc))
        if llvm and not self.link.is_file():
            raise SystemExit('Missing explicit host LLVM linker: ' + str(self.link))

    @property
    def sections(self):
        return ['-DFEL_BSS_SECTION="'+self.bss+'"', '-DFEL_DATA_SECTION="'+self.data+'"']

    def adapt_wrapper(self, path):
        if self.android:
            path.write_text(path.read_text().replace('__DATA,__skfbss', '.skfbss').replace('__DATA,__skfdata', '.skfdata'))
