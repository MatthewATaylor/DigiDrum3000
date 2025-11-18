`timescale 1ns / 1ps  //
`default_nettype none

module base_combiner (
    input wire        clk,
    input wire        rst,
    input wire [10:0] h_count_in,
    input wire [ 9:0] v_count_in,
    input wire [ 7:0] brightness_from_dry,
    input wire [ 7:0] brightness_from_delay,
    input wire [23:0] pixel_color_in,
    input wire [ 2:0] delay_src,

    output logic [10:0] h_count_out,
    output logic [ 9:0] v_count_out,
    output logic        active_draw_out,
    output logic [23:0] pixel_color_out
);
  logic [7:0] combined_brightness;
  logic [15:0] scaled_red;
  logic [15:0] scaled_green;
  logic [15:0] scaled_blue;

  logic [10:0] h_count_pipe[1:0];
  logic [10:0] v_count_pipe[1:0];

  assign h_count_out = h_count_pipe[1];
  assign v_count_out = v_count_pipe[1];
  assign active_draw_out = h_count_pipe[1] < 11'd1280 && v_count_pipe[1] < 11'd720;
  assign pixel_color_out = {scaled_red[15:8], scaled_green[15:8], scaled_blue[15:8]};

  always_ff @(posedge clk) begin
    if (rst) begin
      combined_brightness <= 0;
      scaled_red <= 0;
      scaled_green <= 0;
      scaled_blue <= 0;
      h_count_pipe[0] <= 0;
      h_count_pipe[1] <= 0;
      v_count_pipe[0] <= 0;
      v_count_pipe[1] <= 0;
    end else begin
      if (delay_src != 3'b111) begin
        combined_brightness <=
            brightness_from_dry > brightness_from_delay
          ? brightness_from_dry - brightness_from_delay
          : brightness_from_delay - brightness_from_dry;
      end else begin
        combined_brightness <= brightness_from_dry;
      end
      scaled_red <= {pixel_color_in[23:16], 8'h00};  //combined_brightness * pixel_color_in[23:16];
      scaled_green <= {pixel_color_in[15:8], 8'h00};  //combined_brightness * pixel_color_in[15:8];
      scaled_blue <= {pixel_color_in[7:0], 8'h00};  //combined_brightness * pixel_color_in[7:0];
      h_count_pipe[0] <= h_count_in;
      h_count_pipe[1] <= h_count_pipe[0];
      v_count_pipe[0] <= v_count_in;
      v_count_pipe[1] <= v_count_pipe[0];
    end
  end
endmodule  // base_combiner

`default_nettype wire
