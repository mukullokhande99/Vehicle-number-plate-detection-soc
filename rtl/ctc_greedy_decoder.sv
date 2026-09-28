`timescale 1ns/1ps
// CTC decoder fed by the recognizer's per-time-step argmax. Class 0 is blank,
// 1..10 map to '0'..'9', and 11..36 map to 'A'..'Z'. Repeated classes collapse.
module ctc_greedy_decoder (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        step_valid,
  input  logic        step_last,
  input  logic [5:0]  best_class,
  output logic [63:0] text_ascii,
  output logic [3:0]  char_count,
  output logic        done
);
  logic [5:0] previous_class;
  logic [7:0] ascii_char;
  function automatic [7:0] to_ascii(input logic [5:0] c);
    if (c >= 6'd1 && c <= 6'd10) to_ascii = 8'h30 + (c - 6'd1);
    else if (c >= 6'd11 && c <= 6'd36) to_ascii = 8'h41 + (c - 6'd11);
    else to_ascii = 8'h00;
  endfunction
  always_comb ascii_char = to_ascii(best_class);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      text_ascii <= 64'd0; char_count <= 4'd0; previous_class <= 6'd0; done <= 1'b0;
    end else begin
      done <= 1'b0;
      if (clear) begin
        text_ascii <= 64'd0; char_count <= 4'd0; previous_class <= 6'd0;
      end else if (step_valid) begin
        if ((best_class != 6'd0) && (best_class != previous_class) && (char_count < 4'd8)) begin
          text_ascii[char_count*8 +: 8] <= ascii_char;
          char_count <= char_count + 4'd1;
        end
        previous_class <= best_class;
        if (step_last) done <= 1'b1;
      end
    end
  end
endmodule
