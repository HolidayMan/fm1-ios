#!/usr/bin/env python3
"""Derive PocketFM's Melodee INIT soundset without proprietary factory data.

Only build copies change. Upstream and excluded generated resource hashes stay
pinned for provenance. The compiled resource directory never receives either
Casio/Sequential generated header. Existing user/imported wire data stay valid.
"""
import hashlib
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
EXCLUDED = {'melodee_cz1.h', 'melodee_prophet_factory.h'}
HEADER = '''/* SPDX-License-Identifier: GPL-3.0-only
 * PocketFM original INIT soundset. No Casio/Sequential factory program data.
 * Zero additional factory entries: each engine offers its single INIT program.
 */
#ifndef POCKETFM_MELODEE_INIT_BANK_H
#define POCKETFM_MELODEE_INIT_BANK_H
#define FM1_MELODEE_INIT_BANK 1
#define CZ_FACTORY_N 0u
#define P5_FACTORY_N 0u
#endif
'''


def function(text, signature, body):
    if text.count(signature) != 1:
        raise ValueError('Melodee INIT function anchor changed: ' + signature)
    at = text.index(signature)
    start = text.index('{', at)
    depth, end = 1, start + 1
    while depth:
        if text[end] == '{': depth += 1
        if text[end] == '}': depth -= 1
        end += 1
    return text[:start] + '{\n' + body.strip() + '\n}' + text[end:]


def replace(text, old, new, count=1):
    if text.count(old) != count:
        raise ValueError('Melodee INIT source anchor changed: ' + old[:90])
    return text.replace(old, new)


def derive(upstream, resources, descriptor, verify=True):
    """Patch a freshly copied firmware tree and emit only licensed resources."""
    policy = descriptor['derived_soundset']
    base = Path(upstream) / 'firmware/src'
    for name, expected in policy['upstream_files_sha256'].items():
        if hashlib.sha256((base / name).read_bytes()).hexdigest() != expected:
            raise ValueError('Melodee INIT upstream input changed: ' + name)
    p = base / 'eng_cz.c'; s = p.read_text()
    s = replace(s, '#include "melodee_cz1.h"', '#include "melodee_init_bank.h"')
    s = function(s, 'static void cz_factory(uint32_t k, uint8_t *raw)',
                 '(void)k; cz_patch_init(raw); /* Only original INIT; no ROM lookup. */')
    s = function(s, 'static void cz_preset_make(uint32_t k, preset_t *pr, char *name)', '''
    (void)k;
    pr->e[7] = CZ_NATIVE;
    pr->env[1] = 70; pr->env[2] = 127; pr->env[3] = 60;
    str_cpy(name, "POCKET CZ INIT", 21);
''')
    p.write_text(s)
    p = base / 'eng_prophet_test.c'; s = p.read_text()
    s = replace(s, '#include "melodee_prophet_factory.h"', '#include "melodee_init_bank.h"')
    s = function(s, 'static void p5_factory(uint32_t k,p5_patch_t *p)',
                 '(void)k; p5_patch_init(p); /* Only original INIT; no ROM lookup. */')
    s = function(s, 'static void p5_preset_make(uint32_t k,preset_t *pr,char *name)', '''
    (void)k; pr->env[2] = 127;
    str_cpy(name, "POCKET P5 INIT", 21);
''')
    p.write_text(s)
    p = base / 'prophet_user.c';p.write_text(replace(p.read_text(), '#include "melodee_prophet_factory.h"', '#include "melodee_init_bank.h"'))
    p = base / 'browse.c';s=p.read_text()
    s,n=re.subn(r'\[ENGI_CZ\] = "[A-Z]+",[^\n]*', '[ENGI_CZ] = "O", /* PocketFM CZ INIT only */', s)
    if n != 1: raise ValueError('Melodee CZ category anchor changed')
    s,n=re.subn(r'\[ENGI_PROPHET\] =[^\n]*\n\s*"[A-Z]+"\n\s*"[A-Z]+",', '[ENGI_PROPHET] = "O", /* PocketFM P5 INIT only */', s)
    if n != 1: raise ValueError('Melodee Prophet category anchor changed')
    p.write_text(s)
    # These start from public technical INIT encodings, never factory-ROM data.
    # Distinct original envelope settings and names identify this derived bank.
    p = base / 'cz_patch.h';s=p.read_text()
    s=replace(s, 'memset(b + 128, \' \', 16); memcpy(b + 128, "INIT", 4);', '''
    b[23] = 0xE7; /* Original short-release INIT envelope. */
    memcpy(b + 71, b + 14, 57);
    memset(b + 128, ' ', 16); memcpy(b + 128, "POCKET CZ INIT", 14);''')
    p.write_text(s)
    p = base / 'prophet_patch.c';s=p.read_text()
    s=replace(s, 'p->raw[P5_RELEASE_FILTER] = p->raw[P5_RELEASE_AMP] = 35;', 'p->raw[P5_RELEASE_FILTER] = p->raw[P5_RELEASE_AMP] = 28;')
    s=replace(s, 'p->raw[P5_LEVEL_A] = p->raw[P5_CUTOFF] = 127;', 'p->raw[P5_LEVEL_A] = 112; p->raw[P5_CUTOFF] = 120;')
    s=replace(s, 'memcpy(p->raw + P5_NAME, "INIT PROPHET", 12);', 'memcpy(p->raw + P5_NAME, "POCKET P5 INIT", 14);')
    p.write_text(s)
    resources = Path(resources);resources.mkdir(parents=True, exist_ok=True)
    (resources / 'melodee_init_bank.h').write_text(HEADER)
    actual = {name: hashlib.sha256((base / name).read_bytes()).hexdigest()
              for name in policy['upstream_files_sha256']}
    actual['melodee_init_bank.h'] = hashlib.sha256(HEADER.encode()).hexdigest()
    if verify and actual != policy['derived_files_sha256']:
        raise ValueError('Melodee INIT derived resource/source hash mismatch')
    # A dependency can never find the excluded data through this include root.
    if any((resources / name).exists() for name in EXCLUDED):
        raise ValueError('Excluded Melodee factory data entered compiled resources')
    return actual


def audit_object(object_path, descriptor):
    """Hash-only payload gate: reproduction never needs the excluded ROM data."""
    binary = Path(object_path).read_bytes()
    fingerprints = descriptor['derived_soundset']['excluded_payload_fingerprints']
    prefixes = {value['prefix_sha256']: name for name, value in fingerprints.items()}
    for name in fingerprints:
        if name.encode() in binary:
            raise ValueError('Excluded Melodee factory resource in compiled object: ' + name)
    # One scan for all payloads. Only candidate windows with a matching 32-byte
    # prefix fingerprint require hashing the full packed payload.
    for offset in range(max(0, len(binary) - 31)):
        name = prefixes.get(hashlib.sha256(binary[offset:offset+32]).hexdigest())
        if name:
            expected = fingerprints[name]
            payload = binary[offset:offset+expected['bytes']]
            if hashlib.sha256(payload).hexdigest() == expected['sha256']:
                raise ValueError('Excluded Melodee factory resource in compiled object: ' + name)
    return {name: dict(expected, absent=True) for name, expected in fingerprints.items()}
