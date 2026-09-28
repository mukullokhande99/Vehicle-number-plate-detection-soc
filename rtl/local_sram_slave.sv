`timescale 1ns/1ps
// One-outstanding-request local SRAM slave with byte writes.  The registered
// request boundary is compatible with a synchronous compiled SRAM; replace
// the behavioural array during physical implementation.
module local_sram_slave #(
  parameter int BYTES = 32 * 1024,
  localparam int WORDS = BYTES / 4,
  localparam int ADDR_W = (WORDS <= 1) ? 1 : $clog2(WORDS)
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req_valid,
  input  logic        req_write,
  input  logic [31:0] req_addr,
  input  logic [31:0] req_wdata,
  input  logic [3:0]  req_wstrb,
  output logic        req_ready,
  output logic [31:0] req_rdata
);
  (* ram_style = "block" *) logic [31:0] mem [0:WORDS-1];
  logic pending;
  logic [ADDR_W-1:0] word_addr_q;
  integer i;

  assign req_ready = pending;
  assign req_rdata = mem[word_addr_q];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending <= 1'b0;
      word_addr_q <= '0;
    end else if (pending) begin
      // The master holds its request until this cycle's ready indication.
      pending <= 1'b0;
    end else if (req_valid) begin
      word_addr_q <= req_addr[ADDR_W+1:2];
      if (req_write) begin
        for (i = 0; i < 4; i = i + 1)
          if (req_wstrb[i]) mem[req_addr[ADDR_W+1:2]][i*8 +: 8] <= req_wdata[i*8 +: 8];
      end
      pending <= 1'b1;
    end
  end
endmodule
