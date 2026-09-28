`timescale 1ns/1ps
module tb_preproc;
  logic clk=0, rst_n=0, in_valid, in_sof, in_eol;
  logic [15:0] in_rgb;
  logic out_valid, out_sof, out_eol, out_done;
  logic [7:0] out_luma;
  logic saw_valid, saw_sof, saw_eol, saw_done;
  logic [7:0] sampled_luma;
  integer i;
  always #5 clk=~clk;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      saw_valid <= 0; saw_sof <= 0; saw_eol <= 0; saw_done <= 0; sampled_luma <= 0;
    end else if (out_valid) begin
      saw_valid <= 1; saw_sof <= out_sof; saw_eol <= out_eol; saw_done <= out_done; sampled_luma <= out_luma;
    end
  end
  rgb565_decimate2 dut (.clk,.rst_n,.in_valid,.in_rgb565(in_rgb),.in_sof,.in_eol,.in_w(16'd2),.in_h(16'd2),.out_valid,.out_luma,.out_sof,.out_eol,.out_frame_done(out_done));
  initial begin
    in_valid=0; in_sof=0; in_eol=0; in_rgb=0;
    repeat(2) @(negedge clk); rst_n=1;
    for(i=0;i<4;i=i+1) begin
      @(negedge clk); in_valid=1; in_rgb=16'hFFFF; in_sof=(i==0); in_eol=(i==1 || i==3);
    end
    @(negedge clk); in_valid=0; in_sof=0; in_eol=0;
    @(negedge clk);
    $display("preproc flags valid=%0b sof=%0b eol=%0b done=%0b luma=%0d", saw_valid, saw_sof, saw_eol, saw_done, sampled_luma);
    if (!saw_valid || !saw_sof || !saw_eol || !saw_done || sampled_luma < 8'd250) $fatal(1,"2x decimation/luma conversion failed");
    $display("PASS: RGB565 luma and decimation");
    $finish;
  end
endmodule
