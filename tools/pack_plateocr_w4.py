#!/usr/bin/env python3
"""Build the fixed 64-KiB PlateOCR-4W8A-v1 model SRAM image.

Inputs are already packed signed-INT4 byte streams from the PTQ exporter:
low nibble is the first weight, high nibble is the second.  The script only
constructs the on-chip image/header; it intentionally does not quantize or
train a model.
"""
import argparse
import binascii
from pathlib import Path

SIZE = 64 * 1024
MAGIC = b"POCR"
MODEL_ID = b"PLT1"
FORMAT = (0x04080001).to_bytes(4, "little")
HEADER_BYTES = 16


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--detector-w4", type=Path, required=True)
    p.add_argument("--recognizer-w4", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    detector = args.detector_w4.read_bytes()
    recognizer = args.recognizer_w4.read_bytes()
    payload = detector + recognizer
    if len(payload) + HEADER_BYTES > SIZE:
        raise SystemExit(f"packed model is {len(payload)} bytes; 65520-byte payload limit exceeded")
    crc = binascii.crc32(payload) & 0xFFFFFFFF
    image = bytearray(SIZE)
    image[0:4] = MAGIC
    image[4:8] = MODEL_ID
    image[8:12] = FORMAT
    image[12:16] = crc.to_bytes(4, "little")
    image[HEADER_BYTES:HEADER_BYTES + len(payload)] = payload
    args.output.write_bytes(image)
    print(f"wrote {args.output}: detector={len(detector)} B recognizer={len(recognizer)} B crc=0x{crc:08X}")


if __name__ == "__main__":
    main()
