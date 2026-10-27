# SPDX-License-Identifier: GPL-3.0-only
"""Keep serialized user-sample positions as offsets on 64-bit native hosts."""
import re

def adapt(upstream):
    path=upstream/'firmware/src/eng_sample.c';text=path.read_text()
    anchor='base = (uint32_t)(uintptr_t)(smp_user_xip(k) + SMP_USER_DATA) - (uint32_t)(uintptr_t)SMP_DATA;'
    if text.count(anchor)!=1:raise SystemExit('Hortator sample offset anchor differs')
    text=text.replace(anchor,'base = 0x80000000u | (SMP_USER_BASE + k * SMP_USER_SIZE + SMP_USER_DATA);')
    text,n=re.subn(r'SMP_DATA\[([^\]]+)\]',r'host_sample_byte(\1)',text)
    if n!=1:raise SystemExit('Hortator sample lookup differs')
    path.write_text(text)
