`timescale 1ns/1ps
`include "vision_defs.svh"
// PlateOCR-4W8A-v1 control boundary.  It validates the packed model image
// header before the fixed detector/recognizer micro-schedule is allowed to run.
// The implementation fails closed until a PTQ-generated model image and the
// layer executor are integrated; it never fabricates a vehicle plate result.
module plate_ocr_model_core (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic [31:0] model_id,
  output logic        weight_rd_en,
  output logic [13:0] weight_rd_addr,
  input  logic [31:0] weight_rdata,
  output logic        qparam_rd_en,
  output logic [10:0] qparam_rd_addr,
  input  logic [31:0] qparam_rdata,
  output logic        busy,
  output logic        done,
  output logic        error,
  output logic        det_valid,
  output logic [15:0] det_x,
  output logic [15:0] det_y,
  output logic [15:0] det_w,
  output logic [15:0] det_h,
  output logic [15:0] det_score,
  output logic [63:0] ocr_text,
  output logic [3:0]  ocr_count
);
  typedef enum logic [3:0] {S_IDLE, S_REQ0, S_CHK0, S_REQ1, S_CHK1,
                            S_REQ2, S_CHK2, S_REQ3, S_CHK3, S_FAIL} state_t;
  state_t state;
  always_comb begin
    weight_rd_en = 1'b0;
    weight_rd_addr = 14'd0;
    qparam_rd_en = 1'b0;
    qparam_rd_addr = 11'd0;
    case (state)
      S_REQ0: begin weight_rd_en = 1'b1; weight_rd_addr = 14'd0; end
      S_REQ1: begin weight_rd_en = 1'b1; weight_rd_addr = 14'd1; end
      S_REQ2: begin weight_rd_en = 1'b1; weight_rd_addr = 14'd2; end
      S_REQ3: begin weight_rd_en = 1'b1; weight_rd_addr = 14'd3; end
      default: ;
    endcase
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; busy <= 1'b0; done <= 1'b0; error <= 1'b0;
      det_valid <= 1'b0; det_x <= '0; det_y <= '0; det_w <= '0; det_h <= '0; det_score <= '0;
      ocr_text <= '0; ocr_count <= '0;
    end else begin
      done <= 1'b0;
      if (start && state == S_IDLE) begin
        busy <= 1'b1;
        error <= 1'b0;
        state <= S_REQ0;
      end else begin
        case (state)
          S_REQ0: state <= S_CHK0;
          S_CHK0: state <= (weight_rdata === `PLATEOCR_MAGIC) ? S_REQ1 : S_FAIL;
          S_REQ1: state <= S_CHK1;
          S_CHK1: state <= (weight_rdata === model_id) ? S_REQ2 : S_FAIL;
          S_REQ2: state <= S_CHK2;
          S_CHK2: state <= (weight_rdata === `PLATEOCR_FORMAT) ? S_REQ3 : S_FAIL;
          S_REQ3: state <= S_CHK3;
          // Descriptor CRC of zero is invalid, catching erased SRAM/flash.
          S_CHK3: state <= S_FAIL;
          S_FAIL: begin
            busy <= 1'b0;
            done <= 1'b1;
            error <= 1'b1;
            det_valid <= 1'b0;
            state <= S_IDLE;
          end
          default: ;
        endcase
      end
    end
  end
endmodule
