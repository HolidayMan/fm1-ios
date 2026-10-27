#!/usr/bin/env python3
"""Check a synthetic retained NOR image's boot against untouched portable C."""
import argparse
import ctypes as C
import hashlib
from pathlib import Path


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--reference',type=Path,required=True)
    p.add_argument('--before',type=Path,required=True)
    p.add_argument('--after',type=Path,required=True)
    a=p.parse_args()
    raw=a.before.read_bytes();native=a.after.read_bytes()
    assert len(raw)==len(native)==1<<20
    ref=C.CDLL(str(a.reference.resolve()))
    ref.web_flash_stage.restype=C.POINTER(C.c_uint8)
    ref.web_flash.restype=C.POINTER(C.c_uint8)
    C.memmove(ref.web_flash_stage(),raw,len(raw))
    ref.web_flash_stage_len(len(raw));ref.web_boot()
    upstream=C.string_at(ref.web_flash(),len(raw))
    changed=[i for i,(x,y) in enumerate(zip(raw,native)) if x!=y]
    print('Boot changed bytes:',len(changed))
    print('Changed sectors:',[hex(n) for n in sorted({i&~4095 for i in changed})])
    print('Native boot equals untouched upstream portable boot:',native==upstream)
    print('After SHA256:',hashlib.sha256(native).hexdigest())
    assert native==upstream,'Original storage bookkeeping must match the upstream boot'
    ref.web_dump()


if __name__=='__main__':main()
