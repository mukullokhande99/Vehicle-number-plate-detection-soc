`timescale 1ns/1ps
// Deterministic 2x decimator and RGB565-to-luma conversion.  It is a
// synthesizable low-cost first-silicon ISP stage; replace with a filtered
// scaler only when image-quality measurements demonstrate the need.
module rgb565_decimate2 (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        in_valid,
  input  logic [15:0] in_rgb565,
  input  logic        in_sof,
  input  logic        in_eol,
  input  logic [15:0] in_w,
  input  logic [15:0] in_h,
  output logic        out_valid,
  output logic [7:0]  out_luma,
  output logic        out_sof,
  output logic        out_eol,
  output logic        out_frame_done
);
  logic [15:0] x_count, y_count;
  logic [7:0] r8, g8, b8;
  logic [15:0] y_weighted;

  always_comb begin
    r8 = {in_rgb565[15:11], in_rgb565[15:13]};
    g8 = {in_rgb565[10:5],  in_rgb565[10:9]};
    b8 = {in_rgb565[4:0],   in_rgb565[4:2]};
    // ITU-R BT.601 approximation: 0.299R + 0.587G + 0.114B.
    y_weighted = (16'(r8) * 16'd77) + (16'(g8) * 16'd150) + (16'(b8) * 16'd29);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      x_count <= 16'd0;
      y_count <= 16'd0;
      out_valid <= 1'b0;
      out_luma <= 8'd0;
      out_sof <= 1'b0;
      out_eol <= 1'b0;
      out_frame_done <= 1'b0;
    end else begin
      out_valid <= 1'b0;
      out_sof <= 1'b0;
      out_eol <= 1'b0;
      out_frame_done <= 1'b0;
      if (in_valid) begin
        if (in_sof) begin
          x_count <= 16'd0;
          y_count <= 16'd0;
        end
        if (x_count[0] && y_count[0]) begin
          out_valid <= 1'b1;
          out_luma  <= y_weighted[15:8];
          out_sof   <= (x_count == 16'd1) && (y_count == 16'd1);
          out_eol   <= (x_count == in_w - 16'd1);
          out_frame_done <= (x_count == in_w - 16'd1) && (y_count == in_h - 16'd1);
        end
        if (in_eol) begin
          x_count <= 16'd0;
          y_count <= y_count + 16'd1;
        end else begin
          x_count <= x_count + 16'd1;
        end
      end
    end
  end
endmodule
