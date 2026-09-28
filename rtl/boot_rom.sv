`timescale 1ns/1ps
// ASIC ROM boundary.  The production wrapper replaces this module with a
// foundry ROM macro containing signed boot firmware.  Returning ADDI x0,x0,0
// makes the RTL deterministic without relying on $readmemh.
module boot_rom (
  input  logic        clk,
  input  logic        valid,
  input  logic [31:0] addr,
  output logic        ready,
  output logic [31:0] rdata
);
  always_ff @(posedge clk) begin
    ready <= valid;
    rdata <= 32'h0000_0013;
  end
endmodule
