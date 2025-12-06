`timescale 1ns / 1ps  //
`default_nettype none

module filter_3x3 (
    input wire clk,
    input wire rst,

    input wire signed [2:0][2:0][7:0] coeffs,
    input wire [7:0] shift,

    input wire data_in_valid,
    input wire [23:0] pixel_data_in,
    input wire [10:0] h_count_in,
    input wire [9:0] v_count_in,

    output logic data_out_valid,
    output logic [23:0] pixel_data_out,
    output logic [10:0] h_count_out,
    output logic [9:0] v_count_out
);

  logic [1:0] dither;
  dither_gen #(
      .WIDTH(1)
  ) my_dither (
      .a  (h_count_in[0]),
      .b  (v_count_in[0]),
      .out(dither)
  );

  logic [10:0] last_h_count_in;
  logic [ 9:0] last_v_count_in;
  logic        last_active_draw_in;
  logic [17:0] pixel_in_6bit;

  logic [ 9:0] r_in_intermediate;
  logic [ 9:0] g_in_intermediate;
  logic [ 9:0] b_in_intermediate;

  always_comb begin
    r_in_intermediate = {1'b0, pixel_data_in[23:16]} + dither;
    g_in_intermediate = {1'b0, pixel_data_in[15:8]} + dither;
    b_in_intermediate = {1'b0, pixel_data_in[7:0]} + dither;

    r_in_intermediate = r_in_intermediate > 10'h0FF ? 10'h0FF : r_in_intermediate;
    g_in_intermediate = g_in_intermediate > 10'h0FF ? 10'h0FF : g_in_intermediate;
    b_in_intermediate = b_in_intermediate > 10'h0FF ? 10'h0FF : b_in_intermediate;
  end

  always_ff @(posedge clk) begin
    last_h_count_in <= h_count_in;
    last_v_count_in <= v_count_in;
    last_active_draw_in <= data_in_valid;
    pixel_in_6bit <= {r_in_intermediate[7:2], g_in_intermediate[7:2], b_in_intermediate[7:2]};
  end

  logic [ 2:0][17:0] buffer_line_out;
  logic              buffer_out_valid;
  logic [10:0]       buffer_out_h_count;
  logic [ 9:0]       buffer_out_v_count;

  assign buffer_out_valid = buffer_out_h_count < 11'd1280 && buffer_out_v_count < 10'd720;

  line_buffer m_lbuff (
      .clk(clk),
      .rst(rst),
      .pixel_data_in(pixel_in_6bit),
      .h_count_in(last_h_count_in),
      .v_count_in(last_v_count_in),
      .line_buffer_out(buffer_line_out),
      .h_count_out(buffer_out_h_count),
      .v_count_out(buffer_out_v_count)
  );

  localparam CONVOLVE_LATENCY = 4;
  logic [10:0] h_count_pipe[CONVOLVE_LATENCY-1:0];
  logic [9:0] v_count_pipe[CONVOLVE_LATENCY-1:0];
  logic valid_pipe[CONVOLVE_LATENCY-1:0];

  assign data_out_valid = valid_pipe[CONVOLVE_LATENCY-1];
  assign h_count_out = h_count_pipe[CONVOLVE_LATENCY-1];
  assign v_count_out = v_count_pipe[CONVOLVE_LATENCY-1];

  always_ff @(posedge clk) begin
    h_count_pipe[0] <= buffer_out_h_count;
    v_count_pipe[0] <= buffer_out_v_count;
    valid_pipe[0]   <= buffer_out_valid;
    for (integer i = 1; i < CONVOLVE_LATENCY; i += 1) begin
      h_count_pipe[i] <= h_count_pipe[i-1];
      v_count_pipe[i] <= v_count_pipe[i-1];
      valid_pipe[i]   <= valid_pipe[i-1];
    end
  end

  logic [2:0][2:0][17:0] cache;

  always_ff @(posedge clk) begin
    if (data_in_valid) begin
      cache[0][0] <= buffer_line_out[0];
      cache[1][0] <= buffer_line_out[1];
      cache[2][0] <= buffer_line_out[2];
    end else begin
      cache[0][0] <= 0;
      cache[1][0] <= 0;
      cache[2][0] <= 0;
    end
    cache[0][1] <= cache[0][0];
    cache[0][2] <= cache[0][1];
    cache[1][1] <= cache[1][0];
    cache[1][2] <= cache[1][1];
    cache[2][1] <= cache[2][0];
    cache[2][2] <= cache[2][1];
  end

  logic signed [15:0] r_sum;
  logic signed [15:0] g_sum;
  logic signed [15:0] b_sum;

  always_comb begin
    r_sum = 0;
    g_sum = 0;
    b_sum = 0;
    for (int dy = 0; dy < 3; dy = dy + 1) begin
      for (int dx = 0; dx < 3; dx = dx + 1) begin
        r_sum = r_sum + $signed(coeffs[2-dy][dx]) * $signed({1'b0, cache[dy][dx][17:12]});
        g_sum = g_sum + $signed(coeffs[2-dy][dx]) * $signed({1'b0, cache[dy][dx][11:6]});
        b_sum = b_sum + $signed(coeffs[2-dy][dx]) * $signed({1'b0, cache[dy][dx][5:0]});
      end
    end
  end

  logic signed [15:0] last_r_sum;
  logic signed [15:0] last_g_sum;
  logic signed [15:0] last_b_sum;

  always_ff @(posedge clk) begin
    last_r_sum <= r_sum;
    last_g_sum <= g_sum;
    last_b_sum <= b_sum;
  end

  logic signed [15:0] r_out;
  logic signed [15:0] g_out;
  logic signed [15:0] b_out;

  always_comb begin
    r_out = {last_r_sum, 2'b00} >>> shift;
    g_out = {last_g_sum, 2'b00} >>> shift;
    b_out = {last_b_sum, 2'b00} >>> shift;

    if (r_out < 16'sd0) begin
      r_out = 0;
    end else if (r_out > 16'sd255) begin
      r_out = 16'sd255;
    end

    if (g_out < 16'sd0) begin
      g_out = 0;
    end else if (g_out > 16'sd255) begin
      g_out = 16'sd255;
    end

    if (b_out < 16'sd0) begin
      b_out = 0;
    end else if (b_out > 16'sd255) begin
      b_out = 16'sd255;
    end
  end

  always_ff @(posedge clk) begin
    pixel_data_out <= {r_out[7:0], g_out[7:0], b_out[7:0]};
  end

endmodule

`default_nettype wire
