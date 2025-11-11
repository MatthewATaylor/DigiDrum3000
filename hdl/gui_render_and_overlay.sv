`timescale 1ns / 1ps  //
`default_nettype none

module gui_render_and_overlay #(
    parameter ACTIVE_H_PIXELS = 1280,
    parameter H_FRONT_PORCH = 110,
    parameter H_SYNC_WIDTH = 40,
    parameter H_BACK_PORCH = 220,
    parameter ACTIVE_LINES = 720,
    parameter V_FRONT_PORCH = 5,
    parameter V_SYNC_WIDTH = 5,
    parameter V_BACK_PORCH = 20
) (
    input wire clk,
    input wire rst,
    input wire [10:0] h_count_in,
    input wire [9:0] v_count_in,
    input wire [23:0] pixel_in,
    input wire active_draw_in,
    //input wire [15:0] upsampled_audio_output,

    output logic [23:0] pixel_to_hdmi,
    output logic active_draw_to_hdmi,
    output logic h_sync_to_hdmi,
    output logic v_sync_to_hdmi
);

  localparam TOTAL_PIXELS = ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH + H_BACK_PORCH;
  localparam TOTAL_LINES = ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH;

  assign h_sync_to_hdmi = h_count_in > (ACTIVE_H_PIXELS + H_FRONT_PORCH - 1) && h_count_in < (TOTAL_PIXELS - H_BACK_PORCH);
  assign v_sync_to_hdmi = v_count_in > (ACTIVE_LINES + V_FRONT_PORCH - 1) && v_count_in < (TOTAL_LINES - V_BACK_PORCH);
  assign active_draw_to_hdmi = active_draw_in;
  assign pixel_to_hdmi = pixel_in;

endmodule  // gui_render_and_overlay

`default_nettype wire
