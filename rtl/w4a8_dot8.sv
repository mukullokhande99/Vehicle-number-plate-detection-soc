`timescale 1ns/1ps
// Eight-lane fixed 4W8A dot product.  Each activation is signed INT8; each
// weight is a packed two's-complement INT4.  Accumulation is explicitly INT24.
module w4a8_dot8 (
  input  logic signed [63:0] act_packed,
  input  logic        [31:0] weight_packed,
  input  logic signed [23:0] acc_in,
  output logic signed [23:0] acc_out
);
  integer i;
  logic signed [7:0] a;
  logic signed [3:0] w;
  logic signed [31:0] sum;
  always_comb begin
    sum = acc_in;
    for (i = 0; i < 8; i = i + 1) begin
      a = act_packed[i*8 +: 8];
      w = weight_packed[i*4 +: 4];
      sum = sum + a * w;
    end
    // A well-formed layer compiler must prove this does not overflow INT24.
    acc_out = sum[23:0];
  end
endmodule
