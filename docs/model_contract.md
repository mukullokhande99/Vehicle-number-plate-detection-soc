# Detector and OCR model contract

The fixed input contracts are 320x240 luma for the detector and a 192x64 luma
plate ROI for the recognizer.  The intended deployment is a **fixed W4A8**
anchor-free one-class plate detector followed by a W4A8 CTC recognizer with up
to eight Latin alphanumeric characters.  Each signed INT8 activation is
multiplied by a packed signed INT4 weight; all partial sums remain signed INT24
until per-channel requantization back to INT8.

`plate_ocr_model_core.sv` is intentionally a fail-closed integration boundary,
not fabricated machine-learning behaviour.  It reports `model_error` until it
is replaced by generated RTL plus signed, quantized parameter SRAM macros from
a trained model.  Therefore this package is synthesisable and verifies all
camera/ISP/SoC control semantics, but no claim of plate-detection or OCR
accuracy is made until trained parameters, calibration vectors, and a golden
reference are provided.

The replacement must retain the `start/busy/done/error` transaction and return
one bounding box `(x,y,w,h)`, a Q0.16 confidence, packed ASCII characters, and
the character count.  `w4a8_dot8.sv`, `int24_requantize.sv`, and
`ctc_greedy_decoder.sv` are the fixed arithmetic/decoder blocks to reuse in
that generated core.  This isolates the trained model revision from chip I/O,
RISC-V software, frame DMA, and physical SRAM integration.
