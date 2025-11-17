`timescale 1ns / 1ps  //
`default_nettype none

// 7 cycle delay
module delay_gen #(
    parameter INSTRUMENT_COUNT = 3
) (
    input wire clk,
    input wire rst,

    input wire        active_draw,
    input wire [10:0] h_count,
    input wire [ 9:0] v_count,

    input wire [7:0] inst_intensity[INSTRUMENT_COUNT-1:0],
    input wire [9:0] feedback,
    input wire [9:0] rate,
    input wire [9:0] wet,

    output logic [7:0] intensity
);

  logic [31:0] quotient;
  logic        quotient_valid;
  logic [ 9:0] period;

  logic [10:0] pot_time;
  logic [15:0] delay_time;
  logic [ 9:0] rate_actual;

  // [1, 1024]
  assign pot_time   = rate > 10'h3E0 ? 11'd1024 - 10'h3E0 : 11'd1024 - rate;

  // [64 - 1, 1024*64 - 1] = [1.4 ms, 1.5 s] @ sp=2272
  assign delay_time = ({6'b0, pot_time} << 6) - 1;

  divider rate_div (
      .clk(clk),
      .rst(rst),
      .dividend(32'hFFF),
      .divisor(period < 4 ? 4 : period),
      .data_in_valid(h_count == 80 && v_count == 721),
      .quotient(quotient),
      .remainder(),
      .data_out_valid(quotient_valid),
      .busy()
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      period <= 0;
      rate_actual <= 0;
    end else begin
      // delay_time * 4 * (60 * 2272 / 100000000)->(~357/2^18)->(1>>10 + 1>>12 + 1>>13 + 1>>16 + 1>>18)
      period <= (delay_time >> 8) + (delay_time >> 10) + (delay_time >> 11) + (delay_time >> 14) + (delay_time >> 16);
      if (quotient_valid) begin
        rate_actual <= quotient;
      end
    end
  end

  logic [ 7:0] requested_sample        [INSTRUMENT_COUNT-1:0];
  logic [ 7:0] request_address         [INSTRUMENT_COUNT-1:0];
  logic        pos_valid               [INSTRUMENT_COUNT-1:0];
  logic        last_pos_valid          [INSTRUMENT_COUNT-1:0];
  logic [ 7:0] feedbacked_sample       [INSTRUMENT_COUNT-1:0];
  logic [ 7:0] half_x_dist             [INSTRUMENT_COUNT-1:0];
  logic [15:0] rate_x_offset           [INSTRUMENT_COUNT-1:0];

  logic [15:0] rate_times_h_count;
  logic [15:0] last_rate_times_h_count;
  logic        apply_feedback_decay;

  always_ff @(posedge clk) begin
    if (rst) begin
      rate_times_h_count <= 0;
      last_rate_times_h_count <= 0;
    end else begin
      rate_times_h_count <= rate_actual[9:2] * (h_count + 6'h2);
      last_rate_times_h_count <= rate_times_h_count;
    end
  end

  assign apply_feedback_decay = |h_count[5:0] && rate_times_h_count[15:8] > last_rate_times_h_count[15:8];

  logic [7:0] sample_buffer_in  [INSTRUMENT_COUNT-1:0];
  logic [7:0] sample_buffer_out [INSTRUMENT_COUNT-1:0];
  logic [5:0] sample_buffer_addr[INSTRUMENT_COUNT-1:0];
  logic       sample_buffer_we;

  generate
    genvar i;
    for (i = 0; i < INSTRUMENT_COUNT; i += 1) begin
      dist_ram #(
          .WIDTH(8),
          .DEPTH(64)
      ) sample_history (
          .clk (clk),
          .addr(sample_buffer_addr[i]),
          .we  (sample_buffer_we),
          .din (sample_buffer_in[i]),
          .dout(sample_buffer_out[i])
      );

      assign sample_buffer_in[i] = h_count == 0 ? (inst_intensity[i][7] ? inst_intensity[i][6:0] << 1 : 0) : feedbacked_sample[i];
      assign sample_buffer_addr[i] = v_count == 721 ? h_count : request_address[i];
    end
  endgenerate
  assign sample_buffer_we = h_count < 64 && v_count == 721;

  always_ff @(posedge clk) begin
    if (rst) begin
      for (integer i = 0; i < INSTRUMENT_COUNT; i += 1) begin
        feedbacked_sample[i] <= 0;
        requested_sample[i] <= 0;
        last_pos_valid[i] <= 0;
      end
    end else if (h_count < 64 && v_count == 721) begin
      for (integer i = 0; i < INSTRUMENT_COUNT; i += 1) begin
        feedbacked_sample[i] <= apply_feedback_decay ? (sample_buffer_out[i] * {8'h0, feedback[9:2]}) >> 8 : sample_buffer_out[i];
        requested_sample[i] <= 8'hXX;
        last_pos_valid[i] <= 8'hXX;
      end
    end else begin
      for (integer i = 0; i < INSTRUMENT_COUNT; i += 1) begin
        requested_sample[i] <= sample_buffer_out[i];
        last_pos_valid[i]   <= pos_valid[i] && request_address[i][7:6] == 2'b00;
      end
    end
  end

  logic [15+$clog2(INSTRUMENT_COUNT):0] intensity_sum;
  logic [7:0] unscaled_intensity;

  always_comb begin
    intensity_sum = 0;
    for (integer i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
      intensity_sum += last_pos_valid[i] ? requested_sample[i][7:0] : 0;
    end
    if (intensity_sum > 8'hFF) begin
      intensity_sum = 8'hFF;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      intensity <= 0;
      unscaled_intensity <= 0;
    end else begin
      intensity <= (unscaled_intensity * {8'h0, wet[9:2]}) >> 8;
      unscaled_intensity <= intensity_sum;
    end
  end

  always_ff @(posedge clk) begin
    for (integer i = 0; i < INSTRUMENT_COUNT; i += 1) begin
      if (rst) begin
        rate_x_offset[i]   <= 0;
        request_address[i] <= 0;
        pos_valid[i]       <= 0;
      end else begin
        rate_x_offset[i] <= half_x_dist[i] * rate_actual[9:2];
        request_address[i] <= ((rate_x_offset[i][15:10] + 1) * (|period[9:8] ? {6'h0, period[9:2], 2'h0} : {8'h0, period[7:0]})) >> 2;
        pos_valid[i] <= rate_x_offset[i][9];
      end
    end
  end


  square_left #(
      .WIDTH(512),
      .CENTER_X(640),
      .CENTER_Y(450)
  ) bd_square (
      .clk(clk),
      .rst(rst),
      .h_count(h_count),
      .v_count(v_count),
      .half_x_dist(half_x_dist[0])
  );

  square_left #(
      .WIDTH   (192),
      .CENTER_X(450),
      .CENTER_Y(250)
  ) sd_square (
      .clk(clk),
      .rst(rst),
      .h_count(h_count),
      .v_count(v_count),
      .half_x_dist(half_x_dist[1])
  );

  square_left #(
      .WIDTH   (128),
      .CENTER_X(800),
      .CENTER_Y(200)
  ) open_hh_square (
      .clk(clk),
      .rst(rst),
      .h_count(h_count),
      .v_count(v_count),
      .half_x_dist(half_x_dist[2])
  );
endmodule  // delay_gen

// 2 cycle delay
module square_left #(
    parameter WIDTH = 128,
    parameter CENTER_X = 400,
    parameter CENTER_Y = 400
) (
    input  wire         clk,
    input  wire         rst,
    input  wire  [10:0] h_count,
    input  wire  [ 9:0] v_count,
    output logic [ 7:0] half_x_dist
);
  localparam LEFT_EDGE_X = CENTER_X - WIDTH / 2;
  localparam BOTTOM_EDGE_Y = CENTER_Y + WIDTH / 2;
  localparam TOP_EDGE_Y = CENTER_Y - WIDTH / 2;

  logic [7:0] next_half_x_dist;

  always_ff @(posedge clk) begin
    if (rst) begin
      half_x_dist <= 0;
    end else begin
      half_x_dist <= next_half_x_dist;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      next_half_x_dist <= 0;
    end else if (v_count >= TOP_EDGE_Y && v_count < BOTTOM_EDGE_Y && h_count < LEFT_EDGE_X) begin
      next_half_x_dist <= (LEFT_EDGE_X - h_count) >> 1;
    end else begin
      next_half_x_dist <= 0;
    end
  end
endmodule  // square_left

`default_nettype wire
