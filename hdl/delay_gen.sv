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


  circle_left_right #(
      .RADIUS  (256),
      .CENTER_X(640),
      .CENTER_Y(450)
  ) bd_cicrle (
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

  star_right #(
      .HEIGHT_POW(7),
      .CENTER_X  (800),
      .CENTER_Y  (200)
  ) open_hh_star (
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

// 2 cycle delay
module star_right #(
    // assumes that WIDTH_POW >= HEIGHT_POW >= 4
    parameter HEIGHT_POW = $clog2(128),
    parameter CENTER_X   = 400,
    parameter CENTER_Y   = 400
) (
    input  wire         clk,
    input  wire         rst,
    input  wire  [10:0] h_count,
    input  wire  [ 9:0] v_count,
    output logic [ 7:0] half_x_dist
);
  localparam Y_HIGH_CUTOFF = 1 << HEIGHT_POW - 1;
  localparam Y_MID_CUTOFF = 1 << HEIGHT_POW - 2;
  localparam Y_LOW_CUTOFF = 1 << HEIGHT_POW - 3;

  logic [10:0] x_dist_naive;
  logic [ 9:0] y_dist;
  logic [ 9:0] x_offset_from_y;
  logic        valid_pos;

  assign y_dist = v_count > CENTER_Y ? v_count - CENTER_Y : CENTER_Y - v_count;

  always_ff @(posedge clk) begin
    if (rst) begin
      valid_pos <= 0;
      x_dist_naive <= 0;
      x_offset_from_y <= 0;
      half_x_dist <= 0;
    end else begin
      valid_pos <= y_dist < Y_HIGH_CUTOFF && y_dist > Y_LOW_CUTOFF && h_count > CENTER_X;
      x_dist_naive <= h_count - CENTER_X;
      half_x_dist <= valid_pos && (x_dist_naive - x_offset_from_y < 11'h400) ? (x_dist_naive - x_offset_from_y) >> 1 : 0;
      if (y_dist > Y_MID_CUTOFF) begin
        x_offset_from_y <= ((1 << HEIGHT_POW - 1) - y_dist) >> 2;
      end else begin
        x_offset_from_y <= (1 << HEIGHT_POW - 2) - y_dist + (1 << HEIGHT_POW - 4);
      end
    end
  end

endmodule  // star_right

// 2 cycle delay
module star_left #(
    // assumes that WIDTH_POW >= HEIGHT_POW >= 4
    parameter HEIGHT_POW = $clog2(128),
    parameter CENTER_X   = 400,
    parameter CENTER_Y   = 400
) (
    input  wire         clk,
    input  wire         rst,
    input  wire  [10:0] h_count,
    input  wire  [ 9:0] v_count,
    output logic [ 7:0] half_x_dist
);
  localparam Y_HIGH_CUTOFF = 1 << HEIGHT_POW - 1;
  localparam Y_MID_CUTOFF = 1 << HEIGHT_POW - 2;
  localparam Y_LOW_CUTOFF = 1 << HEIGHT_POW - 3;

  logic [10:0] x_dist_naive;
  logic [ 9:0] y_dist;
  logic [ 9:0] x_offset_from_y;
  logic        valid_pos;

  assign y_dist = v_count > CENTER_Y ? v_count - CENTER_Y : CENTER_Y - v_count;

  always_ff @(posedge clk) begin
    if (rst) begin
      valid_pos <= 0;
      x_dist_naive <= 0;
      x_offset_from_y <= 0;
      half_x_dist <= 0;
    end else begin
      valid_pos <= y_dist < Y_HIGH_CUTOFF && y_dist > Y_LOW_CUTOFF && h_count < CENTER_X;
      x_dist_naive <= CENTER_X - h_count;
      half_x_dist <= valid_pos && (x_dist_naive - x_offset_from_y < 11'h400) ? (x_dist_naive - x_offset_from_y) >> 1 : 0;
      if (y_dist > Y_MID_CUTOFF) begin
        x_offset_from_y <= ((1 << HEIGHT_POW - 1) - y_dist) >> 2;
      end else begin
        x_offset_from_y <= (1 << HEIGHT_POW - 2) - y_dist + (1 << HEIGHT_POW - 4);
      end
    end
  end

endmodule  // star_left

// 2 cycle delay
module X_left #(
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
  localparam CORNER_CUTOFF = (WIDTH * 3) >> 4;
  localparam VALID_CUTOFF = (WIDTH * 5) >> 4;

  logic [10:0] x_dist_naive;
  logic [ 9:0] y_dist;
  logic [ 9:0] x_offset_from_y;
  logic        valid_pos;

  assign y_dist = v_count > CENTER_Y ? v_count - CENTER_Y : CENTER_Y - v_count;

  always_ff @(posedge clk) begin
    if (rst) begin
      x_dist_naive <= 0;
      half_x_dist <= 0;
      x_offset_from_y <= 0;
      valid_pos <= 0;
    end else begin
      x_offset_from_y <= y_dist < CORNER_CUTOFF ? y_dist : 2 * CORNER_CUTOFF - y_dist;
      x_dist_naive <= CENTER_X - h_count;
      valid_pos <= y_dist < VALID_CUTOFF && h_count < (CENTER_X - WIDTH / 8);
      half_x_dist <= (valid_pos && x_dist_naive > x_offset_from_y + WIDTH/8) ? (x_dist_naive - x_offset_from_y - WIDTH/8) >> 1 : 0;
    end
  end
endmodule  // X_left

// 2 cycle delay
module X_right #(
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
  localparam CORNER_CUTOFF = (WIDTH * 3) >> 4;
  localparam VALID_CUTOFF = (WIDTH * 5) >> 4;

  logic [10:0] x_dist_naive;
  logic [ 9:0] y_dist;
  logic [ 9:0] x_offset_from_y;
  logic        valid_pos;

  assign y_dist = v_count > CENTER_Y ? v_count - CENTER_Y : CENTER_Y - v_count;

  always_ff @(posedge clk) begin
    if (rst) begin
      x_dist_naive <= 0;
      half_x_dist <= 0;
      x_offset_from_y <= 0;
      valid_pos <= 0;
    end else begin
      x_offset_from_y <= y_dist < CORNER_CUTOFF ? y_dist : 2 * CORNER_CUTOFF - y_dist;
      x_dist_naive <= h_count - CENTER_X;
      valid_pos <= y_dist < VALID_CUTOFF && h_count > (CENTER_X + WIDTH / 8);
      half_x_dist <= (valid_pos && x_dist_naive > x_offset_from_y + WIDTH/8) ? (x_dist_naive - x_offset_from_y - WIDTH/8) >> 1 : 0;
    end
  end
endmodule  // X_right

// 2 cycle delay
module hex_right #(
    parameter HEIGHT   = 128,
    parameter CENTER_X = 400,
    parameter CENTER_Y = 400
) (
    input  wire         clk,
    input  wire         rst,
    input  wire  [10:0] h_count,
    input  wire  [ 9:0] v_count,
    output logic [ 7:0] half_x_dist
);
  localparam Y_CUTOFF = HEIGHT / 2;

  logic [10:0] x_dist_naive;
  logic [ 9:0] y_dist;
  logic [ 9:0] x_offset_from_y;
  logic        valid_pos;

  assign y_dist = v_count > CENTER_Y ? v_count - CENTER_Y : CENTER_Y - v_count;

  always_ff @(posedge clk) begin
    if (rst) begin
      x_dist_naive <= 0;
      half_x_dist <= 0;
      x_offset_from_y <= 0;
      valid_pos <= 0;
    end else begin
      x_offset_from_y <= (HEIGHT * 4) / 7 - (y_dist >> 1) - (y_dist >> 4);  // -9|y|/16 (almost 4/7)
      x_dist_naive <= h_count > CENTER_X ? h_count - CENTER_X : CENTER_X - h_count;
      valid_pos <= y_dist < Y_CUTOFF;
      half_x_dist <= (valid_pos && x_dist_naive > x_offset_from_y) ? (x_dist_naive - x_offset_from_y) >> 1 : 0;
    end
  end

endmodule  // hex_right

// 2 cycle delay
module slit_left_right #(
    parameter WIDTH_POW = $clog2(256),
    parameter CENTER_X  = 400,
    parameter CENTER_Y  = 400
) (
    input  wire         clk,
    input  wire         rst,
    input  wire  [10:0] h_count,
    input  wire  [ 9:0] v_count,
    output logic [ 7:0] half_x_dist
);
  localparam WIDTH = 1 << WIDTH_POW;
  localparam Y_CUTOFF = WIDTH / 5;

  logic [10:0] x_dist_naive;
  logic [ 9:0] y_dist;
  logic [ 9:0] x_offset_from_y;
  logic        valid_pos;

  assign y_dist = v_count > CENTER_Y ? v_count - CENTER_Y : CENTER_Y - v_count;

  always_ff @(posedge clk) begin
    if (rst) begin
      x_dist_naive <= 0;
      half_x_dist <= 0;
      x_offset_from_y <= 0;
      valid_pos <= 0;
    end else begin
      x_offset_from_y <= WIDTH / 2 - (y_dist << 1) - (y_dist >> 1);  // -5|y|/2
      x_dist_naive <= h_count > CENTER_X ? h_count - CENTER_X : CENTER_X - h_count;
      valid_pos <= y_dist < Y_CUTOFF;
      half_x_dist <= (valid_pos && x_dist_naive > x_offset_from_y) ? (x_dist_naive - x_offset_from_y) >> 1 : 0;
    end
  end
endmodule  // slit_left_right

// 2 cycle delay
module circle_left_right #(
    parameter RADIUS   = 64,
    parameter CENTER_X = 400,
    parameter CENTER_Y = 400
) (
    input  wire         clk,
    input  wire         rst,
    input  wire  [10:0] h_count,
    input  wire  [ 9:0] v_count,
    output logic [ 7:0] half_x_dist
);
  localparam LEFT_EDGE_X = CENTER_X - RADIUS;
  localparam RIGHT_EDGE_X = CENTER_X + RADIUS;
  localparam BOTTOM_EDGE_Y = CENTER_Y + ((RADIUS * 180) >> 8);
  localparam TOP_EDGE_Y = CENTER_Y - ((RADIUS * 180) >> 8);

  logic [10:0] x_dist_naive;
  logic [ 9:0] y_dist;
  logic        valid_pos;

  assign y_dist = v_count > CENTER_Y ? v_count - CENTER_Y : CENTER_Y - v_count;

  logic [15:0] rad_sq_minus_y_sq;
  logic [ 7:0] x_offset_from_y;

  always_ff @(posedge clk) begin
    if (rst) begin
      rad_sq_minus_y_sq <= 0;
      x_dist_naive <= 0;
      half_x_dist <= 0;
      valid_pos <= 0;
    end else begin
      x_dist_naive <= h_count > CENTER_X ? h_count - CENTER_X : CENTER_X - h_count;
      rad_sq_minus_y_sq <= (RADIUS * RADIUS - 1) - y_dist[7:0] * y_dist[7:0];
      valid_pos <= v_count < BOTTOM_EDGE_Y && v_count > TOP_EDGE_Y;
      half_x_dist <= (valid_pos && x_dist_naive > x_offset_from_y) ? (x_dist_naive - x_offset_from_y) >> 1 : 0;
    end
  end

  sqrt_approx #(
      .WIDTH(16)
  ) my_sqrt (
      .d_in (rad_sq_minus_y_sq),
      .d_out(x_offset_from_y)
  );
endmodule  // circle_left_right

`default_nettype wire
