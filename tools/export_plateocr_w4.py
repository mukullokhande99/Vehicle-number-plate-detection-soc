#!/usr/bin/env python3
"""Export a PlateOCR-4W8A-v1 PTQ checkpoint to CSV and SRAM text images.

Input is an ``.npz`` file whose keys are named in plateocr_v1_order.json.
Export FP32 tensors only after batch-normalisation folding.  Weight quantization
is symmetric signed INT4 per output channel; biases become INT32 using the
fixed representative-calibration activation scale.  The emitted word text is
little-endian and directly matches vision_mem_2r1w in the RTL.
"""
from __future__ import annotations

import argparse
import binascii
import csv
import json
import struct
from pathlib import Path

import numpy as np

W4_BYTES = 64 * 1024
QPARAM_BYTES = 8 * 1024
MAGIC = b"POCR"
MODEL_ID = b"PLT1"
FORMAT = 0x04080001


def words_to_txt(image: bytes, path: Path) -> None:
    if len(image) % 4:
        raise ValueError("SRAM image must be 32-bit word aligned")
    with path.open("w", encoding="ascii") as f:
        for offset in range(0, len(image), 4):
            f.write(f"{struct.unpack_from('<I', image, offset)[0]:08X}\n")


def quantize_per_channel(weight: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    if weight.ndim < 1:
        raise ValueError("weight tensor must have an output-channel dimension")
    rows = weight.reshape(weight.shape[0], -1).astype(np.float32)
    scale = np.max(np.abs(rows), axis=1) / 7.0
    scale = np.where(scale < 1.0e-12, 1.0, scale)
    q = np.clip(np.rint(rows / scale[:, None]), -8, 7).astype(np.int8)
    return q.reshape(weight.shape), scale.astype(np.float32)


def pack_int4(q: np.ndarray) -> bytes:
    flat = q.astype(np.int8, copy=False).reshape(-1)
    packed = bytearray((len(flat) + 1) // 2)
    for index, value in enumerate(flat):
        nibble = int(value) & 0xF
        if index & 1:
            packed[index // 2] |= nibble << 4
        else:
            packed[index // 2] = nibble
    return bytes(packed)


def load_npz(path: Path) -> dict[str, np.ndarray]:
    with np.load(path, allow_pickle=False) as ckpt:
        return {name: np.asarray(ckpt[name]) for name in ckpt.files}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", type=Path, required=True, help="FP32 folded-BN .npz checkpoint")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--order", type=Path, default=Path(__file__).with_name("plateocr_v1_order.json"))
    ap.add_argument("--activation-scale", type=float, default=None,
                    help="representative-dataset INT8 scale; overrides manifest")
    args = ap.parse_args()
    tensors = load_npz(args.checkpoint)
    manifest = json.loads(args.order.read_text())
    activation_scale = float(args.activation_scale or manifest.get("activation_scale", 1.0 / 128.0))
    if activation_scale <= 0:
        raise SystemExit("activation scale must be positive")
    args.out.mkdir(parents=True, exist_ok=True)

    payload = bytearray()
    layer_rows: list[dict[str, object]] = []
    qmeta: list[tuple[str, np.ndarray, np.ndarray]] = []
    weight_csv = args.out / "weights_int4.csv"
    with weight_csv.open("w", newline="", encoding="utf-8") as wf:
        writer = csv.writer(wf)
        writer.writerow(["layer", "flat_index", "float_weight", "int4", "packed_byte_offset", "nibble"])
        for layer in manifest["layers"]:
            name, wkey, bkey = layer["name"], layer["weight"], layer.get("bias")
            if wkey not in tensors:
                raise SystemExit(f"missing required tensor: {wkey}")
            weight = tensors[wkey].astype(np.float32)
            q, scales = quantize_per_channel(weight)
            bias = np.zeros(weight.shape[0], dtype=np.float32) if not bkey or bkey not in tensors else tensors[bkey].astype(np.float32).reshape(-1)
            if bias.size != weight.shape[0]:
                raise SystemExit(f"bias {bkey} does not match output channels of {wkey}")
            bias_i32 = np.rint(bias / (activation_scale * scales)).astype(np.int32)
            packed = pack_int4(q)
            if len(payload) & 3:
                payload.extend(b"\0" * (4 - (len(payload) & 3)))
            weight_offset = 16 + len(payload)
            payload.extend(packed)
            flat_f, flat_q = weight.reshape(-1), q.reshape(-1)
            for i, (fv, qv) in enumerate(zip(flat_f, flat_q, strict=True)):
                writer.writerow([name, i, f"{float(fv):.9g}", int(qv), weight_offset + i // 2, i & 1])
            layer_rows.append({"name": name, "weight_offset": weight_offset, "packed_bytes": len(packed),
                               "elements": q.size, "out_channels": weight.shape[0], "shape": "x".join(map(str, weight.shape))})
            qmeta.append((name, scales, bias_i32))

    # Keep INT32 biases beside packed weights in the 64 KiB model SRAM.  This
    # leaves the 8 KiB quant SRAM for per-channel Q2.14 scales and descriptors.
    for row, (_, _, bias_i32) in zip(layer_rows, qmeta, strict=True):
        if len(payload) & 3:
            payload.extend(b"\0" * (4 - (len(payload) & 3)))
        row["bias_offset"] = 16 + len(payload)
        for value in bias_i32:
            payload.extend(struct.pack("<i", int(value)))
    if len(payload) + 16 > W4_BYTES:
        raise SystemExit(f"packed weights need {len(payload) + 16} bytes; W4 SRAM is only {W4_BYTES} bytes")
    crc = binascii.crc32(payload) & 0xFFFFFFFF
    model = bytearray(W4_BYTES)
    model[0:4], model[4:8] = MAGIC, MODEL_ID
    struct.pack_into("<II", model, 8, FORMAT, crc)
    model[16:16 + len(payload)] = payload

    qparam = bytearray(QPARAM_BYTES)
    struct.pack_into("<II", qparam, 0, 0x52415051, len(layer_rows))  # byte stream "QPAR"
    cursor = 8 + 16 * len(layer_rows)
    for index, (row, (_, scales, bias_i32)) in enumerate(zip(layer_rows, qmeta, strict=True)):
        cursor = (cursor + 3) & ~3
        scale_offset = cursor
        # Q2.14 scales retain per-output-channel PTQ calibration while keeping
        # the fixed 8 KiB parameter SRAM large enough for both networks.
        scales_q14 = np.rint(scales * 16384.0).astype(np.int64)
        if np.any(scales_q14 < 1) or np.any(scales_q14 > 32767):
            raise SystemExit("weight scale cannot be represented in signed Q2.14; recalibrate or rescale the layer")
        for value in scales_q14: qparam[cursor:cursor + 2] = struct.pack("<h", int(value)); cursor += 2
        if cursor > QPARAM_BYTES:
            raise SystemExit("scales/descriptors exceed the fixed 8 KiB quantization SRAM")
        struct.pack_into("<4I", qparam, 8 + 16 * index, int(row["weight_offset"]), int(row["packed_bytes"]), scale_offset, int(row["bias_offset"]))
        row["scale_offset"] = scale_offset

    with (args.out / "layers.csv").open("w", newline="", encoding="utf-8") as lf:
        writer = csv.DictWriter(lf, fieldnames=list(layer_rows[0]))
        writer.writeheader(); writer.writerows(layer_rows)
    with (args.out / "quant_params.csv").open("w", newline="", encoding="utf-8") as qf:
        writer = csv.writer(qf); writer.writerow(["layer", "channel", "weight_scale", "weight_scale_q2_14", "bias_int32"])
        for name, scales, biases in qmeta:
            for ch, (scale, bias) in enumerate(zip(scales, biases, strict=True)):
                writer.writerow([name, ch, f"{float(scale):.9g}", int(round(float(scale) * 16384.0)), int(bias)])
    (args.out / "model_w4_sram.bin").write_bytes(model)
    (args.out / "qparam_sram.bin").write_bytes(qparam)
    words_to_txt(model, args.out / "model_w4_sram.txt")
    words_to_txt(qparam, args.out / "qparam_sram.txt")
    (args.out / "export_manifest.json").write_text(json.dumps({"format": FORMAT, "crc32": f"0x{crc:08X}", "activation_scale": activation_scale, "layers": layer_rows}, indent=2) + "\n")
    print(f"exported {len(layer_rows)} layers, {len(payload)} packed W4 bytes, crc=0x{crc:08X}")


if __name__ == "__main__":
    main()
