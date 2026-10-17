#!/usr/bin/env python3
"""Generate local, build-time C kernels from measured decoded XIP blocks.

Inputs and output contain firmware-derived instructions and belong in ignored
Research/ directories. Generated code is compiled and signed with the app; this
never emits or changes executable memory at runtime. Unknown blocks use the
ordinary interpreter. Bindings require complete descriptor and metadata equality.
"""
import argparse
import json
import hashlib
import subprocess
import sys
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def templates():
    names = [line.removeprefix("OP(").removesuffix(")")
             for line in (ROOT / "src/threaded/ops.def").read_text().splitlines()]
    source = (ROOT / "src/threaded/engine.c").read_text()
    matches = list(re.finditer(r"^    op_([A-Z]+):", source, re.M))
    result = {}
    for i, match in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else source.index("    at_stop:", match.end())
        result[match.group(1)] = source[match.end():end].strip()
    return names, result


def inputs(capture, profile, names, limit):
    weights = {}
    for line in Path(profile).read_text().splitlines():
        fields = line.split("\t")
        if fields[0] == "BLOCK":
            pc = int(fields[2], 16)
            weights[pc] = weights.get(pc, 0) + int(fields[4])
    candidates = {}
    for line in Path(capture).read_text().splitlines():
        block = json.loads(line)
        pc, ops, meta = block["pc"], block["ops"], block["meta"]
        assert 0x02000000 <= pc < 0x04000000
        assert 0 < len(ops) <= 33 and len(meta) == len(ops)
        for op in ops:
            assert len(op) == 7
            assert all(type(x) is int and 0 <= x <= (255 if i < 4 else 0xffffffff) for i, x in enumerate(op))
            assert op[0] < len(names)
        assert all(type(x) is int and 0 <= x < 64 for x in meta)
        prefix = next((i for i, op in enumerate(ops) if names[op[0]] in {"EXIT", "RUST"}), len(ops))
        if prefix < 2 or not weights.get(pc):
            continue
        key = (pc, tuple(map(tuple, ops)), tuple(meta))
        candidates[key] = (weights[pc] * prefix / len(ops), prefix)
    ranked = sorted(candidates.items(), key=lambda item: (-item[1][0], item[0]))[:limit]
    return [(key, value[1]) for key, value in ranked]


def generate(blocks, names, bodies):
    out = ["/* Local firmware-derived output. Generated at build time; do not publish. */",
           "#define KJUMP(target) return ((uint64_t)(index+1)<<32) | (uint32_t)(target)"]
    for n, ((pc, ops, meta), prefix) in enumerate(blocks):
        out.append(f"static const Fm1ThreadOp expected_{n}[] = {{")
        out.extend("    {" + ",".join(f"0x{x:x}u" for x in op) + "}," for op in ops)
        out.append("};")
        out.append(f"static const uint8_t meta_{n}[] = {{" + ",".join(map(str, meta)) + "};")
        out.append(f"static uint64_t kernel_{n}(Fm1ThreadState *s) {{")
        out.append("    uint32_t *r=s->regs,*flags=s->flags; (void)r;(void)flags;")
        current_pc = pc
        next_label = False
        for i in range(prefix):
            if next_label:
                out.append(f"k_{i}:;")
            name = names[ops[i][0]]
            body = bodies[name]
            next_label = "NEXT();" in body
            fallback = f"return ((uint64_t)index<<32)|0x{current_pc:x}u"
            body = body.replace("goto partial", fallback).replace("goto op_RUST", fallback)
            body = body.replace("NEXT();", f"goto k_{i+1};").replace("JUMP(", "KJUMP(")
            out.append("    {")
            out.append(f"        const uint32_t index={i}; const Fm1ThreadOp *op=&expected_{n}[{i}]; (void)index;(void)op;")
            out.append(body)
            out.append("    }")
            current_pc = ops[i][6]
        if next_label:
            out.append(f"k_{prefix}:;")
            out.append(f"    return ((uint64_t){prefix}<<32)|0x{current_pc:x}u;")
        out.append("}")
    out.extend(["#undef KJUMP", "typedef struct {uint32_t pc,length;const Fm1ThreadOp *ops;const uint8_t *meta;Fm1ThreadKernel kernel;} KernelEntry;",
                "static const KernelEntry kernels[] = {"])
    out.extend(f"    {{0x{key[0]:x}u,{len(key[1])},expected_{n},meta_{n},kernel_{n}}}," for n, (key, _) in enumerate(blocks))
    out.extend(["};", "Fm1ThreadKernel fm1_threaded_bind(uint32_t pc,const Fm1ThreadOp *ops,const uint8_t *meta,uint32_t length) {",
                "    size_t lo=0,hi=sizeof(kernels)/sizeof(kernels[0]);",
                "    while(lo<hi){size_t mid=lo+(hi-lo)/2;if(kernels[mid].pc<pc)lo=mid+1;else hi=mid;}",
                "    for(size_t i=lo;i<sizeof(kernels)/sizeof(kernels[0])&&kernels[i].pc==pc;i++) {",
                "        const KernelEntry *k=&kernels[i];",
                "        if(k->length==length&&!memcmp(k->ops,ops,length*sizeof(*ops))&&!memcmp(k->meta,meta,length))return k->kernel;",
                "    } return NULL;", "}",
                "uint32_t fm1_threaded_kernel_count(void) {return sizeof(kernels)/sizeof(kernels[0]);}",
                "Fm1ThreadKernel fm1_threaded_kernel_info(uint32_t i,uint32_t *pc,const Fm1ThreadOp **ops,const uint8_t **meta,uint32_t *length) {",
                "    if(i>=sizeof(kernels)/sizeof(kernels[0]))return NULL;const KernelEntry *k=&kernels[i];",
                "    *pc=k->pc;*ops=k->ops;*meta=k->meta;*length=k->length;return k->kernel;}"])
    return "\n".join(out) + "\n"


SOURCES = ["src/threaded/ops.def", "src/threaded/engine.c", "src/threaded/engine.h",
           "src/threaded.rs", "tools/generate_static_kernels.py", "build.rs"]

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def verify(header):
    header = Path(header).resolve()
    manifest = json.loads(header.with_suffix(".manifest.json").read_text())
    assert manifest["kernel_count"] > 0, "no kernels in manifest"
    assert digest(header) == manifest["header_sha256"], "generated header hash mismatch"
    for name in SOURCES:
        assert digest(ROOT / name) == manifest["sources"][name], f"stale generated kernels: {name} changed; regenerate"
    print(f"Verified {manifest['kernel_count']} static kernels: {header}")
    return manifest


def main():
    if len(sys.argv)==3 and sys.argv[1]=="--verify":
        verify(sys.argv[2]); return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", nargs=2, action="append", required=True, metavar=("CAPTURE_JSONL", "COUNTS_TSV"))
    parser.add_argument("--limit", type=int, default=256, help="maximum kernels per profile")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--firmware", type=Path, action="append", default=[])
    args = parser.parse_args()
    assert 1 <= args.limit <= 4096
    names, bodies = templates()
    selected = {}
    for capture, profile in args.input:
        selected.update(inputs(capture, profile, names, args.limit))
    blocks = sorted(selected.items())
    assert blocks, "no eligible measured XIP blocks"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(generate(blocks, names, bodies))
    manifest = {"version": 1, "kernel_count": len(blocks), "header_sha256": digest(args.output),
        "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "sources": {name: digest(ROOT/name) for name in SOURCES},
        "inputs": [{"path": str(Path(p).resolve()), "sha256": digest(p)} for pair in args.input for p in pair],
        "firmware": [{"path": str(p.resolve()), "sha256": digest(p)} for p in args.firmware]}
    args.output.with_suffix(".manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
    print(f"Generated {len(blocks)} guarded static kernels: {args.output}")


if __name__ == "__main__":
    main()
