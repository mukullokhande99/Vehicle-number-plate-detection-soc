`timescale 1ns/1ps
// Technology-neutral 2-read/1-write SRAM boundary.  Host accesses use the
// same one-outstanding transaction protocol as the local TCDM.  The second
// synchronous read port is reserved for the NPU, permitting model preload by
// the RISC-V core while inference is idle without adding chip pins.
module vision_mem_2r1w #(
  parameter int BYTES = 8 * 1024,
  localparam int WORDS = BYTES / 4,
  localparam int ADDR_W = (WORDS <= 1) ? 1 : $clog2(WORDS)
) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              host_valid,
  input  logic              host_write,
  input  logic [31:0]       host_addr,
  input  logic [31:0]       host_wdata,
  input  logic [3:0]        host_wstrb,
  output logic              host_ready,
  output logic [31:0]       host_rdata,
  input  logic              npu_rd_en,
  input  logic [ADDR_W-1:0] npu_rd_addr,
  output logic [31:0]       npu_rdata
);
  (* ram_style = "block" *) logic [31:0] mem [0:WORDS-1];
  logic pending;
  logic [ADDR_W-1:0] host_word_q;
  integer i;
  assign host_ready = pending;
  assign host_rdata = mem[host_word_q];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending <= 1'b0;
      host_word_q <= '0;
      npu_rdata <= 32'd0;
    end else begin
      if (pending)
        pending <= 1'b0;
      else if (host_valid) begin
        host_word_q <= host_addr[ADDR_W+1:2];
        if (host_write)
          for (i = 0; i < 4; i = i + 1)
            if (host_wstrb[i]) mem[host_addr[ADDR_W+1:2]][i*8 +: 8] <= host_wdata[i*8 +: 8];
        pending <= 1'b1;
      end
      if (npu_rd_en) npu_rdata <= mem[npu_rd_addr];
    end
  end
endmodule
