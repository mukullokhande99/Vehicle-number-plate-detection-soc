# PlateOCR-4W8A-v1 frozen network image

The accelerator accepts only the following fixed graph.  The compiler packs
two signed two's-complement INT4 weights per byte; activations are INT8 and
every dot-product accumulates in signed INT24 before a per-output-channel
requantize multiplier and right shift.

| Stage | Operator | Output tensor | Weight count |
|---|---|---:|---:|
| D0 | 3x3 conv, s2, 1->24 | 160x120x24 | 216 |
| D1 | DW3x3 s2 + PW, 24->40 | 80x60x40 | 1,176 |
| D2 | DW3x3 s2 + PW, 40->64 | 40x30x64 | 2,920 |
| D3 | DW3x3 s2 + PW, 64->96 | 20x15x96 | 6,720 |
| D4/D5 | DW3x3 s1 + PW, 96->96 | 20x15x96 | 20,160 |
| D6 | 1x1 detection head, 96->15 | 20x15x15 | 1,440 |
| R0-R3 | Conv/DS blocks, 1->16->32->48->64 | 12x4x64 | 6,128 |
| R4/R5 | GRU, input 64, hidden 64 | 12x64 | 49,536 |
| R6 | 1x1/linear CTC head, 64->37 | 12x37 | 2,368 |

The detector head represents three anchors per 20x15 cell and emits
`(tx, ty, tw, th, objectness)` for the single plate class.  Hardware NMS keeps
at most eight candidates; the highest-scoring ROI is bilinearly resized to
192x64 for recognition.  CTC class 0 is blank, 1-10 are digits, and 11-36 are
uppercase letters.

## Fixed memory image

| Region | Address | Size |
|---|---:|---:|
| Vision control | `0x4000_0000` | 64 KiB window |
| Packed W4 model image | `0x4010_0000` | 64 KiB |
| Q2.14 scales/descriptors | `0x4011_0000` | 8 KiB |
| OCR ROI SRAM | `0x4012_0000` | 12 KiB |
| Streaming line/tensor SRAM | `0x4013_0000` | 24 KiB |
| NMS/result/DMA scratch | `0x4014_0000` | 8 KiB |

Together with the 96 KiB detector-frame SRAM this is 212 KiB of dedicated
vision memory.  The 32 KiB RISC-V TCDM makes the implementation 244 KiB;
reserve a 256 KiB SRAM budget.

The W4 image contains packed weights followed by aligned INT32 biases. It begins
with byte stream `POCR`, byte stream model ID `PLT1`, the
format word `0x04080001`, and a compiler-generated descriptor CRC. SRAM text
words are little-endian, so the first two text lines are `52434F50` and
`31544C50`. The core validates these words before starting hardware execution.
