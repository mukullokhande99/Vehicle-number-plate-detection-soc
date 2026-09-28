`timescale 1ns/1ps
module tb_w4a8;
  logic signed [63:0] act;
  logic [31:0] weights;
  logic signed [23:0] acc_in, acc_out;
  logic clk=0, rst_n=0, clear, step_valid, step_last, done;
  logic [5:0] best_class;
  logic [63:0] text;
  logic [3:0] count;
  always #5 clk=~clk;
  w4a8_dot8 dot (.act_packed(act),.weight_packed(weights),.acc_in,.acc_out);
  ctc_greedy_decoder dec (.clk,.rst_n,.clear,.step_valid,.step_last,.best_class,.text_ascii(text),.char_count(count),.done);
  initial begin
    // [1,2,3,4,5,6,7,8] dot [1,-1,2,-2,3,-3,4,-4] = -10
    act = {8'sd8,8'sd7,8'sd6,8'sd5,8'sd4,8'sd3,8'sd2,8'sd1};
    weights = 32'hC4D3E2F1;
    acc_in = 24'sd0;
    #1;
    if (acc_out !== -24'sd10) $fatal(1,"4W8A dot product incorrect: %0d", acc_out);
    clear=1; step_valid=0; step_last=0; best_class=0;
    repeat(2) @(negedge clk); rst_n=1; @(negedge clk); clear=0;
    // 'A', repeated 'A' (collapsed), blank, '7'.
    @(negedge clk); step_valid=1; best_class=6'd11; step_last=0;
    @(negedge clk); best_class=6'd11;
    @(negedge clk); best_class=6'd0;
    @(negedge clk); best_class=6'd8; step_last=1;
    @(negedge clk); step_valid=0; step_last=0;
    if (!done || count != 2 || text[7:0] != "A" || text[15:8] != "7") $fatal(1,"CTC greedy decoder incorrect");
    $display("PASS: fixed 4W8A MAC and CTC decoder");
    $finish;
  end
endmodule
