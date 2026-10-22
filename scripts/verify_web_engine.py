#!/usr/bin/env python3
"""Verify the private, explicitly prepared experimental engine; never download it."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PIN = "d3f51e1b50fd90c5be186f592c52a04139faceb5fbefd41c248790e620620c87"
SOURCE_PIN = "dfd0c6c23a2b9b91450bbb2128e1c20ccbd14825f970263df3e457690c89c7d6"
ASSETS = ("index.html", "host.js", "engine-worker.js", "pcm-worklet.js", "engine.wasm")


def verify(root, bundle=False):
    assets = {}
    for name in ASSETS:
        path = root / name
        if not path.is_file():
            raise ValueError(f"Missing experimental engine asset {name}; prepare the pinned local engine explicitly.")
        assets[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    if assets["engine.wasm"] != PIN:
        raise ValueError("Experimental engine hash differs from the accepted module; refusing to package a replacement.")
    if any(root.rglob("*.fwsc")):
        raise ValueError("Firmware packages must never be bundled with the experimental engine.")
    report = {"module_sha256": PIN, "assets": assets, "firmware_bundled": False,
              "default_guest_clock_hz": 240_000_000, "allowed_guest_clock_mhz": [120,180,240,320,360], "input_sample_rate": 44100,
              "source": "Research/HeavyAcceleration/source-normalforward",
              "jit_wasm_rs_sha256": SOURCE_PIN,
              "private_build_receipt": "Research/HeavyAcceleration/trace-glue-reuse-normalforward-receipt.json"}
    if not bundle:
        provenance = ROOT / report["private_build_receipt"]
        if provenance.is_file():
            receipt = json.loads(provenance.read_text())
            if receipt["wasmSha256"] != PIN or receipt["source"]["source-normalforward/crates/fm1-core/src/jit_wasm.rs"] != SOURCE_PIN:
                raise ValueError("Private build receipt does not match the accepted module/source pins.")
            report["private_build_receipt_sha256"] = hashlib.sha256(provenance.read_bytes()).hexdigest()
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, help="Verify an already built app's resource root")
    parser.add_argument("--receipt", type=Path, help="Write a local asset receipt")
    args = parser.parse_args()
    try:
        report = verify(args.bundle or ROOT / "App/WebEngine", bundle=args.bundle is not None)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f"error: {error}\n")
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"Verified experimental WASM {PIN}; no firmware package bundled.")


if __name__ == "__main__":
    main()
