`timescale 1ns/1ps
`include "vision_defs.svh"
// Functional-chip top level: 32 signal pads.
//   2 clock/reset + 6 camera QSPI + 2 camera I2C + 6 boot/model-flash QSPI
//   + 2 UART + 8 GPIO + 1 external IRQ + 5 JTAG = 32.
// Power, ground, ESD, analog PLL, and package-specific pads are intentionally
// not RTL ports and must be added by the physical-integration owner.
module plate_ocr_soc_top (
  input  logic       sys_clk,
  input  logic       rst_n,

  output logic       cam_qspi_sclk,
  output logic       cam_qspi_cs_n,
  inout  wire [3:0]  cam_qspi_dq,
  inout  wire        cam_i2c_scl,
  inout  wire        cam_i2c_sda,

  output logic       flash_qspi_sclk,
  output logic       flash_qspi_cs_n,
  inout  wire [3:0]  flash_qspi_dq,
  output logic       uart_tx,
  input  logic       uart_rx,
  inout  wire [7:0]  gpio,
  input  logic       ext_irq,

  input  logic       jtag_tck,
  input  logic       jtag_tms,
  input  logic       jtag_tdi,
  output logic       jtag_tdo,
  input  logic       jtag_trst_n
);
  logic imem_valid, imem_ready;
  logic [31:0] imem_addr, imem_rdata;
  logic d_valid, d_write, d_ready, vision_sel, sram_sel, vision_ready, sram_ready;
  logic wmem_sel, qparam_sel, roi_sel, scratch_sel, result_sel;
  logic wmem_ready, qparam_ready, roi_ready, scratch_ready, result_ready;
  logic [31:0] d_addr, d_wdata, d_rdata, vision_rdata, sram_rdata;
  logic [31:0] wmem_rdata, qparam_rdata, roi_rdata, scratch_rdata, result_rdata;
  logic [3:0] d_wstrb;

  logic capture_start, capture_busy, capture_done;
  logic [15:0] qspi_div;
  logic pixel_valid, pixel_sof, pixel_eol;
  logic [15:0] pixel_rgb565;
  logic luma_valid, luma_sof, luma_eol, luma_done;
  logic [7:0] luma;
  logic cam_dq_oe;
  logic [3:0] cam_dq_o;
  logic frame_wr_en;
  logic [16:0] frame_wr_addr;
  logic [7:0] frame_wr_data;
  logic vision_irq;
  logic model_start, model_busy, model_done, model_error;
  logic det_valid;
  logic [15:0] det_x, det_y, det_w, det_h, det_score;
  logic [63:0] ocr_text;
  logic [3:0] ocr_count;
  logic [31:0] model_id;
  logic weight_rd_en, qparam_rd_en;
  logic [13:0] weight_rd_addr;
  logic [10:0] qparam_rd_addr;
  logic [31:0] weight_npu_rdata, qparam_npu_rdata;

  assign vision_sel = (d_addr & `VISION_MASK) == `VISION_BASE;
  assign sram_sel = (d_addr & `SRAM_MASK) == `SRAM_BASE;
  assign wmem_sel = (d_addr & `VISION_MASK) == `W4_MEM_BASE;
  assign qparam_sel = (d_addr & `VISION_MASK) == `QPARAM_MEM_BASE;
  assign roi_sel = (d_addr & `VISION_MASK) == `OCR_ROI_BASE;
  assign scratch_sel = (d_addr & `VISION_MASK) == `VISION_SCR_BASE;
  assign result_sel = (d_addr & `VISION_MASK) == `VISION_RES_BASE;
  assign d_ready = vision_sel ? vision_ready : sram_sel ? sram_ready :
                   wmem_sel ? wmem_ready : qparam_sel ? qparam_ready :
                   roi_sel ? roi_ready : scratch_sel ? scratch_ready :
                   result_sel ? result_ready : d_valid;
  assign d_rdata = vision_sel ? vision_rdata : sram_sel ? sram_rdata :
                   wmem_sel ? wmem_rdata : qparam_sel ? qparam_rdata :
                   roi_sel ? roi_rdata : scratch_sel ? scratch_rdata :
                   result_sel ? result_rdata : 32'd0;
  assign cam_qspi_dq = cam_dq_oe ? cam_dq_o : 4'bz;
  assign cam_i2c_scl = 1'bz;
  assign cam_i2c_sda = 1'bz;
  assign flash_qspi_sclk = 1'b0;
  assign flash_qspi_cs_n = 1'b1;
  assign flash_qspi_dq = 4'bz;
  assign gpio = 8'bz;
  assign uart_tx = 1'b1;
  assign jtag_tdo = 1'b0;

  rv32i_core u_cpu (
    .clk(sys_clk), .rst_n, .irq(ext_irq | vision_irq),
    .imem_valid, .imem_addr, .imem_ready, .imem_rdata,
    .dmem_valid(d_valid), .dmem_write(d_write), .dmem_addr(d_addr),
    .dmem_wdata(d_wdata), .dmem_wstrb(d_wstrb), .dmem_ready(d_ready), .dmem_rdata(d_rdata)
  );
  boot_rom u_boot_rom (.clk(sys_clk), .valid(imem_valid), .addr(imem_addr), .ready(imem_ready), .rdata(imem_rdata));
  local_sram_slave #(.BYTES(32 * 1024)) u_tcdm (
    .clk(sys_clk), .rst_n, .req_valid(d_valid && sram_sel), .req_write(d_write), .req_addr(d_addr),
    .req_wdata(d_wdata), .req_wstrb(d_wstrb), .req_ready(sram_ready), .req_rdata(sram_rdata)
  );
  qspi_camera_rx u_camera_rx (
    .clk(sys_clk), .rst_n, .start(capture_start), .clk_div(qspi_div), .frame_w(`CAM_W), .frame_h(`CAM_H),
    .qspi_dq_i(cam_qspi_dq), .qspi_sclk(cam_qspi_sclk), .qspi_cs_n(cam_qspi_cs_n), .qspi_dq_oe(cam_dq_oe), .qspi_dq_o(cam_dq_o),
    .busy(capture_busy), .pixel_valid, .pixel_rgb565, .pixel_sof, .pixel_eol, .frame_done(capture_done)
  );
  rgb565_decimate2 u_preproc (
    .clk(sys_clk), .rst_n, .in_valid(pixel_valid), .in_rgb565(pixel_rgb565), .in_sof(pixel_sof), .in_eol(pixel_eol), .in_w(`CAM_W), .in_h(`CAM_H),
    .out_valid(luma_valid), .out_luma(luma), .out_sof(luma_sof), .out_eol(luma_eol), .out_frame_done(luma_done)
  );
  vision_frame_store u_frame_store (
    .clk(sys_clk), .wr_en(frame_wr_en), .wr_addr(frame_wr_addr), .wr_data(frame_wr_data), .rd_en(1'b0), .rd_addr('0), .rd_data()
  );
  vision_mem_2r1w #(.BYTES(`W4_MEM_BYTES)) u_w4_model_mem (
    .clk(sys_clk), .rst_n, .host_valid(d_valid && wmem_sel), .host_write(d_write), .host_addr(d_addr - `W4_MEM_BASE),
    .host_wdata(d_wdata), .host_wstrb(d_wstrb), .host_ready(wmem_ready), .host_rdata(wmem_rdata),
    .npu_rd_en(weight_rd_en), .npu_rd_addr(weight_rd_addr), .npu_rdata(weight_npu_rdata)
  );
  vision_mem_2r1w #(.BYTES(`QPARAM_BYTES)) u_qparam_mem (
    .clk(sys_clk), .rst_n, .host_valid(d_valid && qparam_sel), .host_write(d_write), .host_addr(d_addr - `QPARAM_MEM_BASE),
    .host_wdata(d_wdata), .host_wstrb(d_wstrb), .host_ready(qparam_ready), .host_rdata(qparam_rdata),
    .npu_rd_en(qparam_rd_en), .npu_rd_addr(qparam_rd_addr), .npu_rdata(qparam_npu_rdata)
  );
  vision_mem_2r1w #(.BYTES(`OCR_ROI_BYTES)) u_ocr_roi_mem (
    .clk(sys_clk), .rst_n, .host_valid(d_valid && roi_sel), .host_write(d_write), .host_addr(d_addr - `OCR_ROI_BASE),
    .host_wdata(d_wdata), .host_wstrb(d_wstrb), .host_ready(roi_ready), .host_rdata(roi_rdata), .npu_rd_en(1'b0), .npu_rd_addr('0), .npu_rdata()
  );
  vision_mem_2r1w #(.BYTES(`VISION_SCR_BYTES)) u_line_tensor_mem (
    .clk(sys_clk), .rst_n, .host_valid(d_valid && scratch_sel), .host_write(d_write), .host_addr(d_addr - `VISION_SCR_BASE),
    .host_wdata(d_wdata), .host_wstrb(d_wstrb), .host_ready(scratch_ready), .host_rdata(scratch_rdata), .npu_rd_en(1'b0), .npu_rd_addr('0), .npu_rdata()
  );
  vision_mem_2r1w #(.BYTES(`VISION_RES_BYTES)) u_result_mem (
    .clk(sys_clk), .rst_n, .host_valid(d_valid && result_sel), .host_write(d_write), .host_addr(d_addr - `VISION_RES_BASE),
    .host_wdata(d_wdata), .host_wstrb(d_wstrb), .host_ready(result_ready), .host_rdata(result_rdata), .npu_rd_en(1'b0), .npu_rd_addr('0), .npu_rdata()
  );
  plate_ocr_accel u_vision_ctrl (
    .clk(sys_clk), .rst_n, .cfg_valid(d_valid && vision_sel), .cfg_write(d_write), .cfg_addr(d_addr[15:0]), .cfg_wdata(d_wdata),
    .cfg_ready(vision_ready), .cfg_rdata(vision_rdata), .cfg_error(), .capture_start, .qspi_div, .capture_busy, .capture_done,
    .det_pixel_valid(luma_valid), .det_pixel_luma(luma), .det_frame_done(luma_done), .frame_wr_en, .frame_wr_addr, .frame_wr_data,
    .model_start, .model_id, .model_busy, .model_done, .model_error, .det_valid, .det_x, .det_y, .det_w, .det_h, .det_score, .ocr_text, .ocr_count,
    .irq_done(vision_irq)
  );
  plate_ocr_model_core u_model_core (
    .clk(sys_clk), .rst_n, .start(model_start), .model_id(model_id), .weight_rd_en, .weight_rd_addr, .weight_rdata(weight_npu_rdata),
    .qparam_rd_en, .qparam_rd_addr, .qparam_rdata(qparam_npu_rdata), .busy(model_busy), .done(model_done), .error(model_error),
    .det_valid, .det_x, .det_y, .det_w, .det_h, .det_score, .ocr_text, .ocr_count
  );
endmodule
