`timescale 1ns / 1ps  //
`default_nettype none

// 3 cycle delay
module video_crush (
    input wire clk,
    input wire rst,

    input wire [10:0] h_count_in,
    input wire [ 9:0] v_count_in,
    input wire        active_draw_in,
    input wire [23:0] pixel_in,
    input wire [ 9:0] pressure,

    output logic [10:0] h_count_out,
    output logic [ 9:0] v_count_out,
    output logic        active_draw_out,
    output logic [23:0] pixel_out
);

  logic [7:0] dither;
  dither_gen #(
      .WIDTH(4)
  ) my_dither (
      .a  (h_count_out[4:1]),
      .b  (v_count_out[4:1]),
      .out(dither)
  );

  logic [ 7:0] scale_fact;
  logic [ 7:0] inverse_scale_fact;

  logic [31:0] quotient;
  logic        quotient_valid;
  logic [ 9:0] period;

  divider rate_div (
      .clk(clk),
      .rst(rst),
      .dividend(32'hFFF),
      .divisor(scale_fact),
      .data_in_valid(h_count_in == 80 && v_count_in == 721),
      .quotient(quotient),
      .remainder(),
      .data_out_valid(quotient_valid),
      .busy()
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      scale_fact <= 0;
      inverse_scale_fact <= 0;
    end else begin
      scale_fact <= {1'b1, -pressure[7:0]} >> (3'h1 + pressure[9:8]);
      if (quotient_valid) begin
        inverse_scale_fact <= quotient;
      end
    end
  end

  logic [15:0] r_scaled;
  logic [15:0] g_scaled;
  logic [15:0] b_scaled;

  logic [15:0] r_crushed;
  logic [15:0] g_crushed;
  logic [15:0] b_crushed;

  logic [10:0] last_h_count_in;
  logic [ 9:0] last_v_count_in;
  logic        last_active_draw_in;

  assign pixel_out = {r_crushed[7:0], g_crushed[7:0], b_crushed[7:0]};

  always_ff @(posedge clk) begin
    if (rst) begin
      h_count_out <= 0;
      v_count_out <= 0;
      active_draw_out <= 0;
      last_h_count_in <= 0;
      last_v_count_in <= 0;
      last_active_draw_in <= 0;

      r_scaled <= 0;
      g_scaled <= 0;
      b_scaled <= 0;
      r_crushed <= 0;
      g_crushed <= 0;
      b_crushed <= 0;
    end else begin
      last_h_count_in <= h_count_in;
      last_v_count_in <= v_count_in;
      last_active_draw_in <= active_draw_in;
      h_count_out <= last_h_count_in;
      v_count_out <= last_v_count_in;
      active_draw_out <= last_active_draw_in;
      r_scaled <= pixel_in[23:16] * scale_fact;
      g_scaled <= pixel_in[15:8] * scale_fact;
      b_scaled <= pixel_in[7:0] * scale_fact;
      r_crushed <= ((r_scaled[15:4] + dither) >> 8) * inverse_scale_fact;
      g_crushed <= ((g_scaled[15:4] + dither) >> 8) * inverse_scale_fact;
      b_crushed <= ((b_scaled[15:4] + dither) >> 8) * inverse_scale_fact;
    end
  end
endmodule  // video_crush

`default_nettype wire
