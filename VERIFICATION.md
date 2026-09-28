# Verification status

Verified with Icarus Verilog and Yosys:

- RGB565-to-luma conversion and 2x decimation
- fixed signed `INT8 x INT4` eight-lane MAC arithmetic
- CTC greedy repeat-collapse and ASCII conversion
- CPU-write/NPU-read dual-port access to the packed model SRAM
- deterministic PTQ-export smoke test: 16,384 W4 SRAM words and 2,048
  quantization SRAM words, with matching `POCR`/`PLT1` header words
- exact 76,800-pixel frame accounting and fail-closed transaction behavior
- top-level hierarchy and structural check

The warnings from the open-source tools concern constant-select sensitivity and
top-level tri-state pad modelling.  They are not structural errors.  Production
implementation replaces behavioural SRAMs with foundry macros and attaches the
technology I/O pad ring.

Functional plate/OCR accuracy verification remains blocked on the required
trained W4A8 detector and recognizer parameter sets, calibration tables, and
golden input/output vectors.  `docs/plateocr_v1_model.md` and
`tools/pack_plateocr_w4.py` define the frozen image layout, but the custom
dataset PTQ export itself is still required. Those artefacts are not present in
the original MNIST project and cannot be inferred from RTL alone.
