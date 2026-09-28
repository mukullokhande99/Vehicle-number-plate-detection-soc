`timescale 1ns/1ps
`include "vision_defs.svh"
module tb_plate_ocr_control;
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;
  logic cfg_valid, cfg_write;
  logic [15:0] cfg_addr;
  logic [31:0] cfg_wdata, cfg_rdata;
  logic capture_start, capture_busy, capture_done;
  logic pix_valid, pix_done, frame_wr_en, model_start, model_busy, model_done, model_error, det_valid, irq_done;
  logic [7:0] pix_luma, frame_wr_data;
  logic [15:0] qspi_div, det_x, det_y, det_w, det_h, det_score;
  logic [16:0] frame_wr_addr;
  logic [31:0] model_id;
  logic [63:0] text;
  logic [3:0] text_count;
  integer i;

  plate_ocr_accel dut (
    .clk, .rst_n, .cfg_valid, .cfg_write, .cfg_addr, .cfg_wdata, .cfg_ready(), .cfg_rdata, .cfg_error(),
    .capture_start, .qspi_div, .capture_busy, .capture_done, .det_pixel_valid(pix_valid), .det_pixel_luma(pix_luma), .det_frame_done(pix_done),
    .frame_wr_en, .frame_wr_addr, .frame_wr_data, .model_start, .model_id, .model_busy, .model_done, .model_error,
    .det_valid, .det_x, .det_y, .det_w, .det_h, .det_score, .ocr_text(text), .ocr_count(text_count), .irq_done
  );
  plate_ocr_model_core model (
    .clk, .rst_n, .start(model_start), .model_id, .busy(model_busy), .done(model_done), .error(model_error),
    .det_valid, .det_x, .det_y, .det_w, .det_h, .det_score, .ocr_text(text), .ocr_count(text_count)
  );
  task automatic write_reg(input logic [15:0] a, input logic [31:0] d);
    begin
      @(negedge clk); cfg_valid=1'b1; cfg_write=1'b1; cfg_addr=a; cfg_wdata=d;
      @(negedge clk); cfg_valid=1'b0; cfg_write=1'b0;
    end
  endtask
  initial begin
    cfg_valid=0; cfg_write=0; cfg_addr=0; cfg_wdata=0; capture_busy=0; capture_done=0; pix_valid=0; pix_done=0; pix_luma=8'h55;
    repeat (3) @(negedge clk); rst_n=1'b1;
    write_reg(`REG_CONTROL, 32'h1);
    if (!capture_start) $fatal(1, "capture start was not asserted");
    for (i=0; i<76800; i=i+1) begin
      @(negedge clk);
      pix_valid=1'b1; pix_done=(i==76799); pix_luma=i[7:0];
    end
    @(negedge clk); pix_valid=0; pix_done=0;
    repeat (14) @(negedge clk);
    if (!irq_done || !model_error) $fatal(1, "missing-model path did not terminate safely");
    $display("PASS: frame capture accounting and fail-closed model interface");
    $finish;
  end
endmodule
