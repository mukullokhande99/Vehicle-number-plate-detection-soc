`timescale 1ns/1ps
// Per-output-channel requantization.  The compiler supplies the signed Q1.15
// multiplier and non-negative right shift.  Saturation creates an INT8 tensor.
module int24_requantize (
  input  logic signed [23:0] acc,
  input  logic signed [15:0] multiplier_q15,
  input  logic [4:0]         rshift,
  output logic signed [7:0]  y
);
  logic signed [39:0] product;
  logic signed [39:0] shifted;
  always_comb begin
    product = acc * multiplier_q15;
    shifted = product >>> (15 + rshift);
    if (shifted > 40'sd127)
      y = 8'sd127;
    else if (shifted < -40'sd128)
      y = -8'sd128;
    else
      y = shifted[7:0];
  end
endmodule
