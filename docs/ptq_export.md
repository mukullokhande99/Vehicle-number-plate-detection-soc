# PTQ CSV and SRAM export

After FP32 training on the custom plate dataset, fold batch normalization and
save the tensors as an `.npz` checkpoint using the keys in
`tools/plateocr_v1_order.json`. Then run:

```bash
python3 tools/export_plateocr_w4.py \
  --checkpoint plateocr_fp32_folded.npz --out export_w4a8
```

The exporter writes:

- `weights_int4.csv`: every FP32 weight, its signed INT4 value, byte address,
  and low/high nibble position;
- `layers.csv` and `quant_params.csv`: packed-W4 offsets, per-channel Q2.14
  scales, and INT32 bias offsets; the actual biases reside after weights in
  the 64 KiB W4 model image;
- `model_w4_sram.txt`: exactly 16,384 eight-hex-digit words for the 64 KiB
  `0x4010_0000` SRAM;
- `qparam_sram.txt`: exactly 2,048 words for the 8 KiB `0x4011_0000` SRAM.

The first two W4 SRAM text lines are `52434F50` (`POCR`) and `31544C50`
(`PLT1`). The CPU must write these 32-bit words in ascending address order.
This convention matches `vision_mem_2r1w.sv`: byte 0 is `wdata[7:0]`.

Use `make_demo_plateocr_npz.py` only to verify the export path; it creates
random weights and is not an inference model.
