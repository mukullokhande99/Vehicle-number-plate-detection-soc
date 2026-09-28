#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
RTL=(rtl/asic_mem_1rw.sv rtl/local_sram_slave.sv rtl/rv32i_core.sv rtl/boot_rom.sv rtl/qspi_camera_rx.sv rtl/rgb565_decimate2.sv rtl/vision_frame_store.sv rtl/vision_mem_2r1w.sv rtl/w4a8_dot8.sv rtl/int24_requantize.sv rtl/ctc_greedy_decoder.sv rtl/plate_ocr_model_core.sv rtl/plate_ocr_accel.sv rtl/plate_ocr_soc_top.sv)
iverilog -g2012 -I rtl -s tb_preproc -o build/tb_preproc.vvp "${RTL[@]}" tb/tb_preproc.sv
vvp build/tb_preproc.vvp
iverilog -g2012 -I rtl -s tb_w4a8 -o build/tb_w4a8.vvp "${RTL[@]}" tb/tb_w4a8.sv
vvp build/tb_w4a8.vvp
iverilog -g2012 -I rtl -s tb_vision_mem -o build/tb_vision_mem.vvp "${RTL[@]}" tb/tb_vision_mem.sv
vvp build/tb_vision_mem.vvp
iverilog -g2012 -I rtl -s tb_plate_ocr_control -o build/tb_control.vvp "${RTL[@]}" tb/tb_plate_ocr_control.sv
vvp build/tb_control.vvp
