#!/usr/bin/env bash
set -euo pipefail
yosys -q -p 'read_verilog -sv -nomem2reg -I rtl rtl/asic_mem_1rw.sv rtl/local_sram_slave.sv rtl/rv32i_core.sv rtl/boot_rom.sv rtl/qspi_camera_rx.sv rtl/rgb565_decimate2.sv rtl/vision_frame_store.sv rtl/vision_mem_2r1w.sv rtl/w4a8_dot8.sv rtl/int24_requantize.sv rtl/ctc_greedy_decoder.sv rtl/plate_ocr_model_core.sv rtl/plate_ocr_accel.sv rtl/plate_ocr_soc_top.sv; hierarchy -check -top plate_ocr_soc_top; proc; opt; check'
