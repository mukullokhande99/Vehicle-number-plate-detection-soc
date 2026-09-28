`timescale 1ns/1ps
`include "vision_defs.svh"
// Memory-mapped vision control plane and frame ingress ownership.  The NPU
// data path is deliberately decoupled through a stable result interface: the
// generated, trained detector/OCR netlist replaces plate_ocr_model_core
// without changing SoC, DMA, camera, result, or interrupt RTL.
module plate_ocr_accel (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        cfg_valid,
  input  logic        cfg_write,
  input  logic [15:0] cfg_addr,
  input  logic [31:0] cfg_wdata,
  output logic        cfg_ready,
  output logic [31:0] cfg_rdata,
  output logic        cfg_error,

  output logic        capture_start,
  output logic [15:0] qspi_div,
  input  logic        capture_busy,
  input  logic        capture_done,
  input  logic        det_pixel_valid,
  input  logic [7:0]  det_pixel_luma,
  input  logic        det_frame_done,
  output logic        frame_wr_en,
  output logic [16:0] frame_wr_addr,
  output logic [7:0]  frame_wr_data,

  // Generated model core result interface.
  output logic        model_start,
  output logic [31:0] model_id,
  input  logic        model_busy,
  input  logic        model_done,
  input  logic        model_error,
  input  logic        det_valid,
  input  logic [15:0] det_x,
  input  logic [15:0] det_y,
  input  logic [15:0] det_w,
  input  logic [15:0] det_h,
  input  logic [15:0] det_score,
  input  logic [63:0] ocr_text,
  input  logic [3:0]  ocr_count,
  output logic        irq_done
);
  typedef enum logic [2:0] {S_IDLE, S_CAPTURE, S_MODEL, S_DONE, S_ERROR} state_t;
  state_t state;
  logic [16:0] frame_count;
  logic [31:0] frame_checksum;
  logic [15:0] score_threshold;
  logic [15:0] box_x, box_y, box_w, box_h, box_score;
  logic [63:0] text_data;
  logic [3:0] text_count;
  logic start_pulse;

  assign cfg_ready = cfg_valid;
  assign cfg_error = 1'b0;
  assign capture_start = start_pulse;
  assign model_start = (state == S_MODEL) && !model_busy && !model_done;
  assign irq_done = (state == S_DONE) || (state == S_ERROR);

  always_comb begin
    cfg_rdata = 32'd0;
    case (cfg_addr)
      `REG_CONTROL:      cfg_rdata = {29'd0, state == S_ERROR, state == S_DONE, state != S_IDLE};
      `REG_STATUS:       cfg_rdata = {8'd0, text_count, det_valid, model_error, capture_busy, 14'd0, state};
      `REG_QSPI_DIV:     cfg_rdata = {16'd0, qspi_div};
      `REG_SCORE_THRESH: cfg_rdata = {16'd0, score_threshold};
      `REG_BOX_XY:       cfg_rdata = {box_y, box_x};
      `REG_BOX_WH:       cfg_rdata = {box_h, box_w};
      `REG_SCORE:        cfg_rdata = {16'd0, box_score};
      `REG_TEXT_COUNT:   cfg_rdata = {28'd0, text_count};
      `REG_TEXT_DATA:    cfg_rdata = text_data[31:0];
      (`REG_TEXT_DATA + 16'd4): cfg_rdata = text_data[63:32];
      `REG_FRAME_CSUM:   cfg_rdata = frame_checksum;
      `REG_MODEL_ID:     cfg_rdata = model_id;
      default:           cfg_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      start_pulse <= 1'b0;
      qspi_div <= 16'd2;
      score_threshold <= 16'd32768;
      model_id <= `PLATEOCR_MODEL_ID;
      frame_count <= 17'd0;
      frame_checksum <= 32'd0;
      frame_wr_en <= 1'b0;
      frame_wr_addr <= 17'd0;
      frame_wr_data <= 8'd0;
      box_x <= 16'd0; box_y <= 16'd0; box_w <= 16'd0; box_h <= 16'd0; box_score <= 16'd0;
      text_data <= 64'd0;
      text_count <= 4'd0;
    end else begin
      start_pulse <= 1'b0;
      frame_wr_en <= 1'b0;
      if (cfg_valid && cfg_write) begin
        case (cfg_addr)
          `REG_CONTROL: begin
            if (cfg_wdata[1]) begin
              state <= S_IDLE;
              box_x <= 16'd0; box_y <= 16'd0; box_w <= 16'd0; box_h <= 16'd0; box_score <= 16'd0;
              text_data <= 64'd0; text_count <= 4'd0;
            end
            if (cfg_wdata[0] && state == S_IDLE) begin
              start_pulse <= 1'b1;
              state <= S_CAPTURE;
              frame_count <= 17'd0;
              frame_checksum <= 32'd0;
            end
          end
          `REG_QSPI_DIV:     qspi_div <= cfg_wdata[15:0];
          `REG_SCORE_THRESH: score_threshold <= cfg_wdata[15:0];
          `REG_MODEL_ID:     model_id <= cfg_wdata;
          default: ;
        endcase
      end

      if (state == S_CAPTURE && det_pixel_valid) begin
        frame_wr_en   <= 1'b1;
        frame_wr_addr <= frame_count;
        frame_wr_data <= det_pixel_luma;
        frame_count   <= frame_count + 17'd1;
        frame_checksum <= {frame_checksum[30:0], frame_checksum[31]} ^ {24'd0, det_pixel_luma};
      end
      if (state == S_CAPTURE && (capture_done || det_frame_done)) begin
        // A partial/overflow frame is an integration fault, not an inference.
        state <= ((frame_count + (det_pixel_valid ? 17'd1 : 17'd0)) == `DET_PIXELS) ? S_MODEL : S_ERROR;
      end
      if (state == S_MODEL && model_done) begin
        if (model_error) begin
          state <= S_ERROR;
        end else begin
          box_x <= det_x; box_y <= det_y; box_w <= det_w; box_h <= det_h; box_score <= det_score;
          text_data <= ocr_text;
          text_count <= ocr_count;
          state <= S_DONE;
        end
      end
    end
  end
endmodule
