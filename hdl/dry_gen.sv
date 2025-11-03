`timescale 1ns / 1ps  //
`default_nettype none

// 2 cycle delay
module dry_gen #(
    parameter INSTRUMENT_COUNT = 3
) (
    input wire clk,
    input wire rst,

    input wire active_draw,
    input wire [10:0] h_count,
    input wire [9:0] v_count,

    input wire [6:0] inst_velocity[INSTRUMENT_COUNT-1:0],

    output logic [7:0] intensity
);
  logic [7:0] shape_intensities[INSTRUMENT_COUNT-1:0];

  logic [14+$clog2(INSTRUMENT_COUNT):0] intensity_sum;

  always_comb begin
    intensity_sum = 0;
    for (integer i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
      intensity_sum += inst_velocity[i] * shape_intensities[i];
    end
    if (intensity_sum > 15'h7FFF) begin
      intensity_sum = 15'h7FFF;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      intensity <= 0;
    end else begin
      intensity <= intensity_sum[14:7];
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
      .intensity(shape_intensities[2])
  );

  // snare drum
  circle_hollow #(
      .RADIUS  (128),
      .CENTER_X(450),
      .CENTER_Y(250)
  ) sd_circ (
      .clk(clk),
      .rst(rst),
      .h_count(h_count),
      .v_count(v_count),
      .intensity(shape_intensities[1])
  );

  // open high hat
  circle_hollow #(
      .RADIUS  (64),
      .CENTER_X(800),
      .CENTER_Y(200)
  ) open_hh_circ (
      .clk(clk),
      .rst(rst),
      .h_count(h_count),
      .v_count(v_count),
      .intensity(shape_intensities[0])
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

// 1 cycle of delay
module circle_hollow #(
    parameter RADIUS   = 128,  //assumed >= 16, best if power of 2
    parameter CENTER_X = 400,
    parameter CENTER_Y = 400
) (
    input wire clk,
    input wire rst,
    input wire [10:0] h_count,
    input wire [9:0] v_count,
    output logic [7:0] intensity
);
  localparam rad_sq = RADIUS * RADIUS;
  localparam sft = $clog2(rad_sq) - 8;

  logic [10:0] x_dist;
  logic [ 9:0] y_dist;
  logic [23:0] cur_rad_squared;

  always_comb begin
    if (cur_rad_squared >= rad_sq) begin
      intensity = 0;
    end else begin
      intensity = (cur_rad_squared >> sft) + (8'hFF - ((rad_sq - 1) >> sft));
    end
  end

  assign x_dist = h_count > CENTER_X ? h_count - CENTER_X : CENTER_X - h_count;
  assign y_dist = v_count > CENTER_Y ? v_count - CENTER_Y : CENTER_Y - v_count;
  always_ff @(posedge clk) begin
    if (rst) begin
      cur_rad_squared <= 0;
    end else begin
      cur_rad_squared <= x_dist * x_dist + y_dist * y_dist;  // might be pushing it
    end
  end

endmodule  // dry_gen

`default_nettype wire
