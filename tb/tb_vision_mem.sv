`timescale 1ns/1ps
module tb_vision_mem;
  logic clk=0, rst_n=0, host_valid, host_write, host_ready, npu_rd_en;
  logic [31:0] host_addr, host_wdata, host_rdata, npu_rdata;
  logic [3:0] host_wstrb;
  logic [3:0] npu_rd_addr;
  always #5 clk=~clk;
  vision_mem_2r1w #(.BYTES(64)) dut (
    .clk,.rst_n,.host_valid,.host_write,.host_addr,.host_wdata,.host_wstrb,.host_ready,.host_rdata,.npu_rd_en,.npu_rd_addr,.npu_rdata
  );
  initial begin
    host_valid=0;host_write=0;host_addr=0;host_wdata=0;host_wstrb=0;npu_rd_en=0;npu_rd_addr=0;
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); host_valid=1; host_write=1; host_addr=0; host_wdata=32'h504F4352; host_wstrb=4'hF;
    @(negedge clk); host_valid=0; host_write=0;
    if (!host_ready) $fatal(1,"host write did not acknowledge");
    @(negedge clk); npu_rd_en=1; npu_rd_addr=0;
    @(negedge clk); npu_rd_en=0;
    @(negedge clk);
    if (npu_rdata != 32'h504F4352) $fatal(1,"NPU port did not read packed model header");
    $display("PASS: model SRAM host write and NPU read port");
    $finish;
  end
endmodule
