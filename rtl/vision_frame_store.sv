`timescale 1ns/1ps
// 320x240 byte frame store.  Bind this interface to a 96-KiB compiled SRAM
// macro at implementation; this behavioural definition has the same 1R1W
// synchronous contract and contains no FPGA initialization dependency.
module vision_frame_store #(
  parameter int DEPTH = 76800,
  localparam int ADDR_W = $clog2(DEPTH)
) (
  input  logic              clk,
  input  logic              wr_en,
  input  logic [ADDR_W-1:0] wr_addr,
  input  logic [7:0]        wr_data,
  input  logic              rd_en,
  input  logic [ADDR_W-1:0] rd_addr,
  output logic [7:0]        rd_data
);
  logic [7:0] mem [0:DEPTH-1];
  always_ff @(posedge clk) begin
    if (wr_en) mem[wr_addr] <= wr_data;
    if (rd_en) rd_data <= mem[rd_addr];
  end
endmodule
