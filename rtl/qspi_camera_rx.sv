`timescale 1ns/1ps
// Generic Quad-SPI pixel ingress.  It intentionally owns only the electrical
// QSPI read phase: sensor reset/configuration remains on the camera I2C pins.
// A board-specific controller may prepend a sensor command/address sequence;
// this block starts at the first RGB565 nibble and captures 640x480 pixels.
module qspi_camera_rx (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic [15:0] clk_div,
  input  logic [15:0] frame_w,
  input  logic [15:0] frame_h,
  input  logic [3:0]  qspi_dq_i,
  output logic        qspi_sclk,
  output logic        qspi_cs_n,
  output logic        qspi_dq_oe,
  output logic [3:0]  qspi_dq_o,
  output logic        busy,
  output logic        pixel_valid,
  output logic [15:0] pixel_rgb565,
  output logic        pixel_sof,
  output logic        pixel_eol,
  output logic        frame_done
);
  logic [15:0] div_count;
  logic        phase;
  logic [1:0]  nibble_count;
  logic [15:0] pixel_shift;
  logic [15:0] x_count, y_count;

  assign qspi_dq_oe = 1'b0;
  assign qspi_dq_o  = 4'b0000;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      qspi_sclk   <= 1'b0;
      qspi_cs_n   <= 1'b1;
      busy        <= 1'b0;
      div_count   <= 16'd0;
      phase       <= 1'b0;
      nibble_count<= 2'd0;
      pixel_shift <= 16'd0;
      x_count     <= 16'd0;
      y_count     <= 16'd0;
      pixel_valid <= 1'b0;
      pixel_rgb565<= 16'd0;
      pixel_sof   <= 1'b0;
      pixel_eol   <= 1'b0;
      frame_done  <= 1'b0;
    end else begin
      pixel_valid <= 1'b0;
      pixel_sof   <= 1'b0;
      pixel_eol   <= 1'b0;
      frame_done  <= 1'b0;
      if (!busy) begin
        qspi_sclk <= 1'b0;
        qspi_cs_n <= 1'b1;
        if (start) begin
          busy         <= 1'b1;
          qspi_cs_n    <= 1'b0;
          div_count    <= 16'd0;
          phase        <= 1'b0;
          nibble_count <= 2'd0;
          x_count      <= 16'd0;
          y_count      <= 16'd0;
        end
      end else if (div_count == ((clk_div == 16'd0) ? 16'd1 : clk_div)) begin
        div_count <= 16'd0;
        phase <= ~phase;
        qspi_sclk <= ~qspi_sclk;
        // Sample on generated rising edge.  Four QSPI nibbles form RGB565.
        if (!phase) begin
          pixel_shift <= {pixel_shift[11:0], qspi_dq_i};
          if (nibble_count == 2'd3) begin
            pixel_rgb565 <= {pixel_shift[11:0], qspi_dq_i};
            pixel_valid  <= 1'b1;
            pixel_sof    <= (x_count == 16'd0) && (y_count == 16'd0);
            pixel_eol    <= (x_count == frame_w - 16'd1);
            nibble_count <= 2'd0;
            if (x_count == frame_w - 16'd1) begin
              x_count <= 16'd0;
              if (y_count == frame_h - 16'd1) begin
                y_count    <= 16'd0;
                busy       <= 1'b0;
                qspi_cs_n  <= 1'b1;
                frame_done <= 1'b1;
              end else begin
                y_count <= y_count + 16'd1;
              end
            end else begin
              x_count <= x_count + 16'd1;
            end
          end else begin
            nibble_count <= nibble_count + 2'd1;
          end
        end
      end else begin
        div_count <= div_count + 16'd1;
      end
    end
  end
endmodule
