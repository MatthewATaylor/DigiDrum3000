`timescale 1ns / 1ps  //
`default_nettype none

module video_reverb (
    input wire clk,
    input wire rst,

    input wire [10:0] h_count_in,
    input wire [ 9:0] v_count_in,
    input wire        active_draw_in,
    input wire [23:0] pixel_in,

    input wire [9:0] wet,
    input wire [9:0] feedback,
    input wire [9:0] size,

    output logic [10:0] h_count_out,
    output logic [ 9:0] v_count_out,
    output logic        active_draw_out,
    output logic [23:0] pixel_out,

    input  wire  [15:0] dram_read_data,
    output logic [10:0] dram_read_h_count,
    output logic [ 9:0] dram_read_v_count,
    output logic        dram_read_active_draw,

    output logic [15:0] dram_write_data,
    output logic        dram_write_valid,
    output logic        dram_write_tlast
);
  localparam VSPEED = 2;
  always_ff @(posedge clk) begin
    dram_read_h_count <= h_count_in;
    dram_read_v_count <= v_count_in >= (750 - VSPEED) ? v_count_in - (750 - VSPEED) : v_count_in + VSPEED;
    dram_read_active_draw <= h_count_in < 1280 && (v_count_in < (720 - VSPEED) || v_count_in >= (750 - VSPEED));
  end

  localparam INPUT_LATENCY = 5;

  logic [10:0] h_count_in_pipe[INPUT_LATENCY-1:0];
  logic [9:0] v_count_in_pipe[INPUT_LATENCY-1:0];
  logic active_draw_in_pipe[INPUT_LATENCY-1:0];
  logic [23:0] pixel_in_pipe[INPUT_LATENCY-1:0];

  always_ff @(posedge clk) begin
    h_count_in_pipe[0]     <= h_count_in;
    v_count_in_pipe[0]     <= v_count_in;
    active_draw_in_pipe[0] <= active_draw_in;
    pixel_in_pipe[0]       <= pixel_in;
    for (integer i = 1; i < INPUT_LATENCY; i += 1) begin
      h_count_in_pipe[i]     <= h_count_in_pipe[i-1];
      v_count_in_pipe[i]     <= v_count_in_pipe[i-1];
      active_draw_in_pipe[i] <= active_draw_in_pipe[i-1];
      pixel_in_pipe[i]       <= pixel_in_pipe[i-1];
    end
  end

  logic [23:0] pixel_from_feedback;

  YCoCg_422_decoder my_decoder (
      .clk(clk),
      .rst(rst),
      .h_count_lsb(h_count_in[0]),
      .dram_read_data(dram_read_data),
      .pixel_out(pixel_from_feedback)
  );

  logic [23:0] pixel_to_feedback;

  video_reverb_combiner my_combiner (
      .clk(clk),
      .rst(rst),

      .h_count_in(h_count_in_pipe[INPUT_LATENCY-1]),
      .v_count_in(v_count_in_pipe[INPUT_LATENCY-1]),
      .active_draw_in(active_draw_in_pipe[INPUT_LATENCY-1]),
      .pixel_in(pixel_in_pipe[INPUT_LATENCY-1]),
      .pixel_from_feedback(pixel_from_feedback),

      .wet(wet),
      .feedback(feedback),

      .h_count_out(h_count_out),
      .v_count_out(v_count_out),
      .active_draw_out(active_draw_out),
      .pixel_out(pixel_out),
      .pixel_to_feedback(pixel_to_feedback)
  );

  localparam signed [2:0][2:0][7:0] GAUSS_COEFFS = {
    {8'sd1, 8'sd2, 8'sd1}, {8'sd2, 8'sd4, 8'sd2}, {8'sd1, 8'sd2, 8'sd1}
  };
  localparam [7:0] GAUSS_SHFT = 8'd4;

  logic [23:0] feedback_pixel_blurred;
  logic [10:0] h_count_blurred;
  logic [ 9:0] v_count_blurred;
  logic        active_draw_blurred;

  filter_3x3 my_filter_3x3 (
      .clk(clk),
      .rst(rst),
      .coeffs(GAUSS_COEFFS),
      .shift(GAUSS_SHFT),

      .data_in_valid(active_draw_out),
      .pixel_data_in(pixel_to_feedback),
      .h_count_in(h_count_out),
      .v_count_in(v_count_out),

      .data_out_valid(active_draw_blurred),
      .h_count_out(h_count_blurred),
      .v_count_out(v_count_blurred),
      .pixel_data_out(feedback_pixel_blurred)
  );

  YCoCg_422_encoder my_encoder (
      .clk(clk),
      .rst(rst),
      .h_count_lsb(h_count_blurred[0]),
      .pixel_in(feedback_pixel_blurred),
      .dram_write_data(dram_write_data)
  );

  reverb_dram_timer my_dram_timer (
      .clk(clk),
      .rst(rst),
      .h_count_in(h_count_blurred),
      .v_count_in(v_count_blurred),
      .active_draw_in(active_draw_blurred),
      .dram_write_valid(dram_write_valid),
      .dram_write_tlast(dram_write_tlast)
  );

endmodule  // video_reverb

// rough outline:
// pixel_out = wet * from_feedback + pixel_in
// to_feedback = feedback * from_feedback + pixel_in
module video_reverb_combiner (
    input wire clk,
    input wire rst,

    input wire [10:0] h_count_in,
    input wire [ 9:0] v_count_in,
    input wire        active_draw_in,
    input wire [23:0] pixel_in,
    input wire [23:0] pixel_from_feedback,

    input wire [9:0] wet,
    input wire [9:0] feedback,

    output logic [10:0] h_count_out,
    output logic [ 9:0] v_count_out,
    output logic        active_draw_out,
    output logic [23:0] pixel_out,
    output logic [23:0] pixel_to_feedback
);

  logic [10:0] last_h_count;
  logic [ 9:0] last_v_count;
  logic        last_active_draw;
  logic [23:0] last_pixel_in;

  logic [15:0] wet_r;
  logic [15:0] wet_g;
  logic [15:0] wet_b;
  logic [15:0] fed_r;
  logic [15:0] fed_g;
  logic [15:0] fed_b;

  logic [ 7:0] out_r;
  logic [ 7:0] out_g;
  logic [ 7:0] out_b;
  logic [ 7:0] to_feed_r;
  logic [ 7:0] to_feed_g;
  logic [ 7:0] to_feed_b;

  assign pixel_out = {out_r, out_g, out_b};
  assign pixel_to_feedback = {to_feed_r, to_feed_g, to_feed_b};

  always_ff @(posedge clk) begin
    last_h_count <= h_count_in;
    last_v_count <= v_count_in;
    last_active_draw <= active_draw_in;
    last_pixel_in <= pixel_in;

    h_count_out <= last_h_count;
    v_count_out <= last_v_count;
    active_draw_out <= last_active_draw;

    wet_r <= {8'h00, wet[9:2]} * pixel_from_feedback[23:16];
    wet_g <= {8'h00, wet[9:2]} * pixel_from_feedback[15:8];
    wet_b <= {8'h00, wet[9:2]} * pixel_from_feedback[7:0];

    fed_r <= {10'h003, feedback[9:4]} * pixel_from_feedback[23:16];
    fed_g <= {10'h003, feedback[9:4]} * pixel_from_feedback[15:8];
    fed_b <= {10'h003, feedback[9:4]} * pixel_from_feedback[7:0];

    out_r <= wet_r[15:8] > last_pixel_in[23:16] ? wet_r[15:8] : last_pixel_in[23:16];
    out_g <= wet_g[15:8] > last_pixel_in[15:8] ? wet_g[15:8] : last_pixel_in[15:8];
    out_b <= wet_b[15:8] > last_pixel_in[7:0] ? wet_b[15:8] : last_pixel_in[7:0];

    to_feed_r <= fed_r[15:8] > last_pixel_in[23:16] ? fed_r[15:8] : last_pixel_in[23:16];
    to_feed_g <= fed_g[15:8] > last_pixel_in[15:8] ? fed_g[15:8] : last_pixel_in[15:8];
    to_feed_b <= fed_b[15:8] > last_pixel_in[7:0] ? fed_b[15:8] : last_pixel_in[7:0];
  end
endmodule  // video_reverb_combiner

// behaves like 3 cycle delay
module reverb_dram_timer (
    input  wire         clk,
    input  wire         rst,
    input  wire  [10:0] h_count_in,
    input  wire  [ 9:0] v_count_in,
    input  wire         active_draw_in,
    output logic        dram_write_valid,
    output logic        dram_write_tlast
);

  logic [2:0] active_draw_pipe;
  assign dram_write_valid = active_draw_pipe[2];

  always_ff @(posedge clk) begin
    dram_write_tlast <= v_count_in == 10'd719 && h_count_in == 11'd1281;
    active_draw_pipe <= {active_draw_pipe[1:0], active_draw_in};
  end

endmodule  // reverb_dram_timer

`default_nettype wire
