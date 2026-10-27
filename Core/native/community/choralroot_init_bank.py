"""Derive ChoralRoot's original INIT-only CZ/P5 banks without factory payloads.

The ignored build copy changes; saved/imported user patch formats stay upstream.
Only allowlisted generated resources enter the compiled include directory.
"""
import hashlib
from pathlib import Path
import shutil
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from melodee_init_bank import function, replace, audit_object, EXCLUDED

HEADER='''/* SPDX-License-Identifier: GPL-3.0-only
 * PocketFM original INIT bank. No Casio/Sequential factory program bytes. */
#ifndef POCKETFM_CHORALROOT_INIT_BANK_H
#define POCKETFM_CHORALROOT_INIT_BANK_H
#define CZ_FACTORY_N 0u
#define CZ_FACTORY_BANKS 0u
#define CZ_FACTORY_PRESETS(X)
#endif
'''

def derive(upstream, resources, source, descriptor, verify=True):
    policy=descriptor['derived_soundset'];base=Path(upstream)/'firmware/src'
    for name,want in policy['upstream_files_sha256'].items():
        if hashlib.sha256((base/name).read_bytes()).hexdigest()!=want:
            raise ValueError('ChoralRoot INIT source pin changed: '+name)
    p=base/'eng_cz.c';s=p.read_text()
    s=replace(s,'#include "melodee_cz1.h"','#include "choralroot_init_bank.h"')
    s=function(s,'static void cz_factory_bank(uint32_t k, uint8_t *dst)',
               '(void)k; for (uint32_t i=0;i<16u;i++) cz_patch_init(dst+i*CZ_BYTES);')
    s=function(s,'static void cz_factory_tone(uint32_t k, uint8_t *raw)',
               '(void)k; cz_patch_init(raw); /* Original INIT, no ROM lookup. */')
    p.write_text(s)
    p=base/'cz_patch.h';s=p.read_text()
    s=replace(s,'memset(b + 128, \' \', 16); memcpy(b + 128, "INIT", 4);',
              'b[23] = 0xE7; memcpy(b + 71, b + 14, 57);\n    memset(b + 128, \' \', 16); memcpy(b + 128, "POCKET CZ INIT", 14);')
    p.write_text(s)
    p=base/'prophet_patch.c';s=p.read_text()
    s=replace(s,'p->raw[P5_RELEASE_FILTER] = p->raw[P5_RELEASE_AMP] = 35;',
              'p->raw[P5_RELEASE_FILTER] = p->raw[P5_RELEASE_AMP] = 28;')
    s=replace(s,'p->raw[P5_LEVEL_A] = p->raw[P5_CUTOFF] = 127;',
              'p->raw[P5_LEVEL_A] = 112; p->raw[P5_CUTOFF] = 120;')
    s=replace(s,'memcpy(p->raw + P5_NAME, "INIT PROPHET", 12);',
              'memcpy(p->raw + P5_NAME, "POCKET P5 INIT", 14);')
    p.write_text(s)
    resources=Path(resources);resources.mkdir(parents=True,exist_ok=True)
    for name in descriptor['generated_headers_sha256']:
        if name in EXCLUDED:raise ValueError('Excluded factory resource in allowlist')
        shutil.copy2(Path(source)/'build/gen'/name,resources/name)
    (resources/'choralroot_init_bank.h').write_text(HEADER)
    if any((resources/name).exists() for name in EXCLUDED):
        raise ValueError('Excluded ChoralRoot factory data entered compiled resources')
    actual={n:hashlib.sha256((base/n).read_bytes()).hexdigest() for n in policy['upstream_files_sha256']}
    actual['choralroot_init_bank.h']=hashlib.sha256(HEADER.encode()).hexdigest()
    if verify and actual!=policy['derived_files_sha256']:
        raise ValueError('ChoralRoot INIT derived source/resource hashes differ')
    return actual
