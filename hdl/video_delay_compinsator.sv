`timescale 1ns / 1ps  //
`default_nettype none

module video_delay_compinsator (
    input wire clk,
    input wire rst,
    input wire [10:0] h_count_in,
    input wire [9:0] v_count_in,
    input wire active_draw_in,

    input wire [2:0] crush_src,
    input wire [2:0] distortion_src,
    input wire [2:0] filter_src,
    input wire [2:0] reverb_src,

    output logic [10:0] h_count_out,
    output logic [ 9:0] v_count_out,
    output logic        active_draw_out
);
  logic [10:0] h_offset;
  logic [ 9:0] v_offset;
  assign active_draw_out = h_count_out < 11'd1280 && v_count_out < 10'd720;

  logic h_wrap;
  logic v_wrap;
  assign h_wrap = (h_count_in + h_offset) >= 11'd1650;
  assign v_wrap = (v_count_in + h_wrap + v_offset) >= 10'd750;

  always_ff @(posedge clk) begin
    h_offset <= 12 +
      (crush_src != 3'b111) * 4 +
      (distortion_src != 3'b111) * 5 +
      (filter_src != 3'b111) * 15 +
      (reverb_src != 3'b111) * 9;
    v_offset <= (distortion_src != 3'b111) * 1 + (filter_src != 3'b111) * 5;
    h_count_out <= h_wrap ? h_count_in - 11'd1650 + h_offset : h_count_in + h_offset;
    v_count_out <= v_wrap ? v_count_in - 10'd750 + v_offset + h_wrap : v_count_in + v_offset + h_wrap;
  end

endmodule  // video_delay_compinsator

`default_nettype wire
