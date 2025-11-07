`timescale 1ns / 1ps  //
`default_nettype none

// 4 cycle delay
module dry_gen #(
    parameter INSTRUMENT_COUNT = 3
) (
    input wire clk,
    input wire rst,

    input wire active_draw,
    input wire [10:0] h_count,
    input wire [9:0] v_count,

    input wire [7:0] inst_intensity[INSTRUMENT_COUNT-1:0],

    output logic [7:0] intensity
);
  logic [ 7:0] shape_intensities[INSTRUMENT_COUNT-1:0];
  logic [31:0] noise_gen;
  logic [ 7:0] noise_scrambled;
  assign noise_scrambled = {
    noise_gen[0],
    noise_gen[5],
    noise_gen[3],
    noise_gen[7],
    noise_gen[1],
    noise_gen[4],
    noise_gen[6],
    noise_gen[2]
  };

  always_ff @(posedge clk) begin
    if (rst) begin
      noise_gen <= 32'hFFFF_FFFF;
    end else begin
      noise_gen <= (noise_gen << 1) ^ (noise_gen[31] * 32'b0000_0100_1100_0001_0001_1101_1011_0111);
    end
  end

  logic [15+$clog2(INSTRUMENT_COUNT):0] intensity_sum;

  always_comb begin
    intensity_sum = 0;
    for (integer i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
      intensity_sum += shape_intensities[i];
    end
    if (intensity_sum > 8'hFF) begin
      intensity_sum = 8'hFF;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      intensity <= 0;
    end else begin
      intensity <= intensity_sum;
    end
  end

  // bass drum
  circle_hollow #(
      .RADIUS  (256),
      .CENTER_X(640),
      .CENTER_Y(450)
  ) bd_circ (
      .clk(clk),
      .rst(rst),
      .h_count(h_count),
      .v_count(v_count),
      .inst_intensity(inst_intensity[0]),
      .intensity(shape_intensities[0])
  );

  // snare drum
  square_noise #(
      .WIDTH   (192),
      .CENTER_X(450),
      .CENTER_Y(250)
  ) sd_square (
      .clk(clk),
      .rst(rst),
      .h_count(h_count),
      .v_count(v_count),
      .noise_source(noise_scrambled),
      .inst_intensity(inst_intensity[1]),
      .intensity(shape_intensities[1])
  );

  // open high hat
  star_noise #(
      .WIDTH_POW ($clog2(256)),
      .HEIGHT_POW($clog2(128)),
      .CENTER_X  (800),
      .CENTER_Y  (200)
  ) open_hh_star (
      .clk(clk),
      .rst(rst),
      .h_count(h_count),
      .v_count(v_count),
      .noise_source(noise_scrambled),
      .inst_intensity(inst_intensity[2]),
      .intensity(shape_intensities[2])
  );

  generate
    genvar i;
    for (i = 3; i < INSTRUMENT_COUNT; i = i + 1) begin
      circle_hollow #(
          .RADIUS  (64),
          .CENTER_X(100 * i + 200),
          .CENTER_Y(100)
      ) gen_circ (
          .clk(clk),
          .rst(rst),
          .h_count(h_count),
          .v_count(v_count),
          .intensity(shape_intensities[i])
      );
    end
  endgenerate

endmodule

// 3 cycles of delay
module square_noise #(
    parameter WIDTH = 128,
    parameter CENTER_X = 400,
    parameter CENTER_Y = 400
) (
    input  wire         clk,
    input  wire         rst,
    input  wire  [10:0] h_count,
    input  wire  [ 9:0] v_count,
    input  wire  [ 7:0] noise_source,
    input  wire  [ 7:0] inst_intensity,
    output logic [ 7:0] intensity
);
  localparam SHFT = 9 - $clog2(WIDTH);

  logic [10:0] x_dist;
  logic [ 9:0] y_dist;
  logic [ 7:0] pre_noise_intensity;
  logic [ 7:0] unscaled_intensity;
  logic [ 7:0] scaled_intensity;
  assign x_dist = h_count > CENTER_X ? h_count - CENTER_X : CENTER_X - h_count;
  assign y_dist = v_count > CENTER_Y ? v_count - CENTER_Y : CENTER_Y - v_count;

  always_comb begin
    pre_noise_intensity = x_dist < y_dist ? y_dist : x_dist;
    pre_noise_intensity = (pre_noise_intensity << SHFT) + (8'hFF - (((WIDTH >> 1) - 1) << SHFT));
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      intensity <= 0;
      scaled_intensity <= 0;
    end else begin
      intensity <= scaled_intensity;
      scaled_intensity <= (inst_intensity * {8'b0, unscaled_intensity}) >> 8;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      unscaled_intensity <= 0;
    end else if (x_dist < (WIDTH >> 1) && y_dist < (WIDTH >> 1)) begin
      unscaled_intensity <= pre_noise_intensity > noise_source ? pre_noise_intensity : (noise_source);
    end else begin
      unscaled_intensity <= 0;
    end
  end


endmodule

// 128 - x*x*y*y>>(4MIN_POW-4-14) + |x|>>WIDTH_POW-9 + |y|>>HEIGHT_POW-9 + noise
// 3 cycles of delay
module star_noise #(
    parameter WIDTH_POW  = $clog2(256),
    parameter HEIGHT_POW = $clog2(128),
    parameter CENTER_X   = 400,
    parameter CENTER_Y   = 400
) (
    input  wire         clk,
    input  wire         rst,
    input  wire  [10:0] h_count,
    input  wire  [ 9:0] v_count,
    input  wire  [ 7:0] noise_source,
    input  wire  [ 7:0] inst_intensity,
    output logic [ 7:0] intensity
);
  localparam MIN_POW = (WIDTH_POW < HEIGHT_POW ? WIDTH_POW : HEIGHT_POW);
  localparam X_SHFT = 9 - WIDTH_POW;
  localparam Y_SHFT = 9 - HEIGHT_POW;
  localparam XXYY_SHFT = 4 * MIN_POW - 16;

  logic [10:0] x_dist;
  logic [ 9:0] y_dist;
  logic [10:0] last_x_dist;
  logic [ 9:0] last_last_x_dist;
  logic [16:0] x_squared;
  logic [16:0] y_squared;

  logic [ 7:0] next_intensity;
  logic [31:0] xxyy;
  logic [31:0] sum;

  always_comb begin
    sum = noise_source + (inst_intensity << 1) - 9'h100 - (last_last_x_dist << X_SHFT) - (y_dist << Y_SHFT) - (xxyy >> XXYY_SHFT);

    if (sum[31] || last_last_x_dist >= (1 << (WIDTH_POW)) || y_dist >= (1 << (HEIGHT_POW))) begin
      next_intensity = 0;
    end else begin
      next_intensity = sum[8] ? 8'hFF : sum[7:0];
    end
  end

  assign x_dist = h_count > CENTER_X ? h_count - CENTER_X : CENTER_X - h_count;
  assign y_dist = v_count > CENTER_Y ? v_count - CENTER_Y : CENTER_Y - v_count;

  always_ff @(posedge clk) begin
    if (rst) begin
      intensity        <= 0;
      xxyy             <= 0;
      x_squared        <= 0;
      y_squared        <= 0;
      last_x_dist      <= 0;
      last_last_x_dist <= 0;
    end else begin
      intensity        <= next_intensity;
      xxyy             <= x_squared * y_squared;
      x_squared        <= x_dist[7:0] * x_dist[7:0];
      y_squared        <= y_dist[7:0] * y_dist[7:0];
      last_x_dist      <= x_dist;
      last_last_x_dist <= last_x_dist;
    end
  end
endmodule

// 3 cycles of delay
module circle_hollow #(
    parameter RADIUS   = 128,  //assumed >= 16, best if power of 2
    parameter CENTER_X = 400,
    parameter CENTER_Y = 400
) (
    input  wire         clk,
    input  wire         rst,
    input  wire  [10:0] h_count,
    input  wire  [ 9:0] v_count,
    input  wire  [ 7:0] inst_intensity,
    input  wire  [ 7:0] noise_source,
    output logic [ 7:0] intensity
);
  localparam RAD_SQ = RADIUS * RADIUS;
  localparam SHFT = $clog2(RAD_SQ) - 8;

  logic [10:0] x_dist;
  logic [ 9:0] y_dist;
  logic [10:0] last_x_dist;
  logic [ 9:0] last_y_dist;
  logic [16:0] cur_rad_squared;
  logic [ 7:0] unscaled_intensity;

  always_ff @(posedge clk) begin
    if (rst || (last_x_dist >= RADIUS || last_y_dist >= RADIUS || cur_rad_squared >= RAD_SQ)) begin
      unscaled_intensity <= 0;
    end else begin
      unscaled_intensity <= (cur_rad_squared >> SHFT) + (8'hFF - ((RAD_SQ - 1) >> SHFT));
    end
  end

  assign x_dist = h_count > CENTER_X ? h_count - CENTER_X : CENTER_X - h_count;
  assign y_dist = v_count > CENTER_Y ? v_count - CENTER_Y : CENTER_Y - v_count;

  always_ff @(posedge clk) begin
    if (rst) begin
      cur_rad_squared <= 0;
      intensity <= 0;
      last_x_dist <= 0;
      last_y_dist <= 0;
    end else begin
      cur_rad_squared <= x_dist[7:0] * x_dist[7:0] + y_dist[7:0] * y_dist[7:0];  // might be pushing it
      intensity <= (unscaled_intensity * {8'b0, inst_intensity}) >> 8;
      last_x_dist <= x_dist;
      last_y_dist <= y_dist;
    end
  end

endmodule  // dry_gen

`default_nettype wire
