`timescale 1ns/1ps
// Technology-neutral single-port SRAM contract.  Replace with the selected
// foundry macro wrapper for physical implementation; do not change users.
module asic_mem_1rw #(
  parameter int DATA_W = 8,
  parameter int DEPTH  = 256,
  localparam int ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
  input  logic              clk,
  input  logic              en,
  input  logic              we,
  input  logic [ADDR_W-1:0] addr,
  input  logic [DATA_W-1:0] wdata,
  output logic [DATA_W-1:0] rdata
);
  logic [DATA_W-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (en) begin
      if (we) mem[addr] <= wdata;
      rdata <= mem[addr];
    end
  end
endmodule
