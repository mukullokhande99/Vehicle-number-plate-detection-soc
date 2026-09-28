# Repository file guide

This repository is the synthesizable **PlateOCR-4W8A-v1** SoC integration
package.  It implements the camera ingress, image pre-processing, RISC-V
control path, SRAM interfaces, W4A8 arithmetic primitives, CTC decoder, and
verification flow.  A trained detector/recognizer executor and its
custom-dataset PTQ parameters are intentionally external inputs; see
[`model_contract.md`](model_contract.md).

## Top-level files

| File | Purpose |
|---|---|
| `README.md` | Repository landing-page title and entry point. |
| `VERIFICATION.md` | Current test/synthesis status, known tool warnings, and the boundary between verified infrastructure and ML-accuracy verification. |
| `LICENSE` | Repository license. |
| `.gitignore` | Excludes simulator build output, Python caches, checkpoints, and generated model images/CSVs from source control. |

## `rtl/` — synthesizable SystemVerilog

| File | Purpose |
|---|---|
| `plate_ocr_soc_top.sv` | Chip-level integration top (`plate_ocr_soc_top`). Exposes the 32 functional pads: clock/reset, camera QSPI/I2C, flash QSPI, UART, GPIO, external interrupt, and JTAG. |
| `plate_ocr_accel.sv` | Memory-mapped vision control plane. Owns frame-write accounting, start/busy/done/error handling, result registers, and the stable interface toward the model core. |
| `plate_ocr_model_core.sv` | Fixed model-image validation and model-core transaction boundary. It validates `POCR`/`PLT1` header data and **fails closed** until the generated W4A8 detector/recognizer executor is integrated. It does not fabricate plate/OCR results. |
| `rv32i_core.sv` | Small in-order RV32I control CPU with explicit instruction/data request-response ports. The accelerator precision does not alter the CPU ISA or control path. |
| `boot_rom.sv` | Technology-neutral ROM boundary. Replace with the signed production boot-ROM macro/image for implementation. |
| `local_sram_slave.sv` | One-outstanding-request local SRAM/TCDM slave with byte writes. |
| `asic_mem_1rw.sv` | Generic synchronous single-port SRAM wrapper contract. Replace the behavioural implementation with a foundry macro wrapper. |
| `vision_mem_2r1w.sv` | Technology-neutral two-read/one-write model/q-parameter SRAM interface. CPU host access is one outstanding transaction; the second read port is reserved for the NPU. |
| `vision_frame_store.sv` | 320×240, 8-bit luma frame-store interface (96 KiB). |
| `qspi_camera_rx.sv` | Quad-SPI RGB565 pixel ingress from the first sensor pixel onward. Camera configuration is performed through the separate I2C pins. |
| `rgb565_decimate2.sv` | RGB565-to-luma conversion and deterministic 2× decimation, producing the 320×240 detector input from 640×480 capture. |
| `w4a8_dot8.sv` | Eight-lane signed INT8-activation × packed signed-INT4-weight dot product with explicit signed INT24 accumulation. |
| `int24_requantize.sv` | Per-output-channel INT24-to-INT8 requantizer using a signed multiplier, right shift, and saturation. |
| `ctc_greedy_decoder.sv` | CTC argmax decoder with repeat collapse. Class 0 is blank; classes 1–10 are digits and 11–36 are uppercase letters. |
| `vision_defs.svh` | Shared vision address, size, and configuration definitions. Include it instead of duplicating memory-map constants. |
| `filelist.f` | Ordered RTL source list for simulators or synthesis flows that accept file lists. |

## `tb/` — self-checking verification

| File | Coverage |
|---|---|
| `tb_preproc.sv` | RGB565 luma conversion and 2× decimation. |
| `tb_w4a8.sv` | Packed INT4/INT8 dot-product arithmetic, requantization behaviour, and CTC greedy decoding. |
| `tb_vision_mem.sv` | CPU host write and NPU read behaviour of the packed model SRAM interface. |
| `tb_plate_ocr_control.sv` | Frame-pixel accounting, control transactions, model-header validation, and fail-closed error behaviour. |

## `scripts/` — repeatable checks

| File | Command and result |
|---|---|
| `run_tb.sh` | Run `bash scripts/run_tb.sh` from the repository root. Compiles and runs all four Icarus Verilog testbenches into `build/`. |
| `run_synth_yosys.sh` | Run `bash scripts/run_synth_yosys.sh` from the repository root. Performs a Yosys hierarchy and structural check with `plate_ocr_soc_top` as top. |

## `tools/` — Python model-image preparation

| File | Purpose |
|---|---|
| `export_plateocr_w4.py` | Main post-training-quantization exporter. Reads a folded-BN FP32 `.npz` checkpoint, applies per-output-channel symmetric INT4 quantization, and creates the W4 model SRAM image, q-parameter SRAM image, CSV audit files, and manifest. |
| `make_demo_plateocr_npz.py` | Generates deterministic shape-correct random tensors to smoke-test the exporter. It is not a trained inference model. |
| `pack_plateocr_w4.py` | Packs separately prepared detector and recognizer INT4 payloads into the fixed 64 KiB W4 image, including its header and CRC. |
| `plateocr_v1_order.json` | Frozen checkpoint-key and layer ordering contract required by the exporter. |

The main export command is:

```bash
python3 tools/export_plateocr_w4.py \
  --checkpoint plateocr_fp32_folded.npz \
  --out export_w4a8
```

Important generated outputs are deliberately ignored by Git:

| Output | Hardware destination |
|---|---|
| `model_w4_sram.txt` / `.bin` | 64 KiB model SRAM at `0x4010_0000`; text form contains 16,384 little-endian 32-bit words. |
| `qparam_sram.txt` / `.bin` | 8 KiB q-parameter SRAM at `0x4011_0000`; text form contains 2,048 32-bit words. |
| `weights_int4.csv` | Per-weight FP32-to-INT4 audit trail, packed-byte address, and nibble location. |
| `layers.csv`, `quant_params.csv` | Layer layout, Q2.14 scales, and aligned INT32-bias placement metadata. |
| `export_manifest.json` | Export metadata and integrity information. |

## `docs/` — design contracts

| File | Purpose |
|---|---|
| `model_contract.md` | Integration contract for the generated detector/OCR core: 320×240 detector luma input, 192×64 recognition ROI, W4A8 arithmetic, stable result interface, and explicit fail-closed limitation. |
| `plateocr_v1_model.md` | Frozen network graph, per-stage tensor dimensions/weight counts, memory map, W4 image header format, and 256 KiB SRAM-budget rationale. |
| `ptq_export.md` | PTQ checkpoint prerequisites, exporter invocation, generated files, endianness, and SRAM preload convention. |
| `pinout.md` | Functional 32-signal-pad count and interface-level pin budget. Power, ground, ESD, PLL/analog, and final pad-ring details belong to physical integration. |
| `file_guide.md` | This file. |

## Recommended reading and execution order

1. Read [`plateocr_v1_model.md`](plateocr_v1_model.md) for the frozen graph and memory map.
2. Read [`model_contract.md`](model_contract.md) before replacing `plate_ocr_model_core.sv` with the generated trained-model executor.
3. Train and calibrate on the custom dataset, then follow [`ptq_export.md`](ptq_export.md).
4. Run `bash scripts/run_tb.sh` and `bash scripts/run_synth_yosys.sh` after RTL changes.
5. Before tapeout, replace all behavioural SRAM/ROM modules with characterized foundry wrappers; close lint, CDC/RDC, STA, DFT, power intent, physical implementation, and sign-off separately.
