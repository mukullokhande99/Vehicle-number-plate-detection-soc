`ifndef VISION_DEFS_SVH
`define VISION_DEFS_SVH

// Fixed deployment geometry.  The ingress is VGA RGB565; the detector sees
// one luma sample for every 2x2 source block.  OCR operates on a rectified
// 192x64 grayscale region selected by the detector.
`define CAM_W             16'd640
`define CAM_H             16'd480
`define DET_W             16'd320
`define DET_H             16'd240
`define DET_PIXELS        32'd76800
`define OCR_W             16'd192
`define OCR_H             16'd64
`define OCR_MAX_CHARS     8

`define VISION_BASE       32'h4000_0000
`define VISION_MASK       32'hFFFF_0000
`define W4_MEM_BASE       32'h4010_0000
`define QPARAM_MEM_BASE   32'h4011_0000
`define OCR_ROI_BASE      32'h4012_0000
`define VISION_SCR_BASE   32'h4013_0000
`define VISION_RES_BASE   32'h4014_0000
`define SRAM_BASE         32'h2000_0000
`define SRAM_MASK         32'hFFFF_8000

`define W4_MEM_BYTES      (64 * 1024)
`define QPARAM_BYTES      (8 * 1024)
`define OCR_ROI_BYTES     (12 * 1024)
`define VISION_SCR_BYTES  (24 * 1024)
`define VISION_RES_BYTES  (8 * 1024)
`define VISION_TOTAL_BYTES (96 * 1024 + `W4_MEM_BYTES + `QPARAM_BYTES + `OCR_ROI_BYTES + `VISION_SCR_BYTES + `VISION_RES_BYTES)

// First four W4-memory words are the model image header.
// SRAM words are little-endian: byte stream "POCR" is word 0x52434F50.
`define PLATEOCR_MAGIC    32'h5243_4F50 // byte stream "POCR"
`define PLATEOCR_MODEL_ID 32'h3154_4C50 // byte stream "PLT1"
`define PLATEOCR_FORMAT   32'h0408_0001 // W4A8, layout revision 1

`define REG_CONTROL       16'h0000
`define REG_STATUS        16'h0004
`define REG_QSPI_DIV      16'h0008
`define REG_SCORE_THRESH  16'h000C
`define REG_BOX_XY        16'h0010
`define REG_BOX_WH        16'h0014
`define REG_SCORE         16'h0018
`define REG_TEXT_COUNT    16'h001C
`define REG_TEXT_DATA     16'h0020
`define REG_FRAME_CSUM    16'h0024
`define REG_MODEL_ID      16'h0028

`endif
