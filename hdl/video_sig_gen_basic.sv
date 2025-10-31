`timescale 1ns / 1ps  //
`default_nettype none

module video_sig_gen_basic #(
    parameter ACTIVE_H_PIXELS = 1280,
    parameter H_FRONT_PORCH   = 110,
    parameter H_SYNC_WIDTH    = 40,
    parameter H_BACK_PORCH    = 220,
    parameter ACTIVE_LINES    = 720,
    parameter V_FRONT_PORCH   = 5,
    parameter V_SYNC_WIDTH    = 5,
    parameter V_BACK_PORCH    = 20,
    parameter FPS             = 60
) (
    input  wire                             pixel_clk,
    input  wire                             rst,
    output logic [$clog2(TOTAL_PIXELS)-1:0] h_count,
    output logic [ $clog2(TOTAL_LINES)-1:0] v_count,
    output logic                            active_draw,
    output logic                            new_frame     //single cycle enable signal
);

  localparam TOTAL_PIXELS = ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH + H_BACK_PORCH;
  localparam TOTAL_LINES = ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH;

  logic [$clog2(TOTAL_PIXELS)-1:0] next_h_count;
  logic [ $clog2(TOTAL_LINES)-1:0] next_v_count;

  assign active_draw = (v_count < ACTIVE_LINES) && (h_count < ACTIVE_H_PIXELS);
  assign new_frame   = v_count == (ACTIVE_LINES - 1) && h_count == ACTIVE_H_PIXELS;

  always_comb begin
    if (h_count == TOTAL_PIXELS - 1) begin
      next_h_count = 0;
      next_v_count = (v_count == TOTAL_LINES - 1) ? 0 : v_count + 1;
    end else begin
      next_h_count = h_count + 1;
      next_v_count = v_count;
    end

    if (rst) begin
      next_v_count = 0;
      next_h_count = 0;
    end
  end

  always_ff @(posedge pixel_clk) begin
    h_count <= next_h_count;
    v_count <= next_v_count;
  end

endmodule  // video_sig_gen

`default_nettype wire
