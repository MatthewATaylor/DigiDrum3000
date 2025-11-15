`timescale 1ns / 1ps  //
`default_nettype none

// 6 cycle delay
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
  logic [ 7:0] period;
  logic [ 9:0] rate_cached;

  divider rate_div (
      .clk(clk),
      .rst(rst),
      .dividend(32'hFF),
      .divisor(rate < 4 ? 1 : (rate >> 2)),
      .data_in_valid(h_count == 80 && v_count == 721),
      .quotient(quotient),
      .remainder(),
      .data_out_valid(quotient_valid),
      .busy()
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      period <= 0;
      rate_cached <= 0;
    end else if (quotient_valid) begin
      period <= quotient;
      rate_cached <= rate;
    end
  end

  logic [7:0] requested_sample     [INSTRUMENT_COUNT-1:0];
  logic [5:0] request_address      [INSTRUMENT_COUNT-1:0];
  logic       pos_valid            [INSTRUMENT_COUNT-1:0];
  logic       last_pos_valid       [INSTRUMENT_COUNT-1:0];
  logic [7:0] feedbacked_sample    [INSTRUMENT_COUNT-1:0];
  logic [7:0] feedback_timer;
  logic       apply_feedback_decay;

  assign apply_feedback_decay = feedback_timer > period;

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
      feedback_timer <= 0;
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
      if (h_count == 63) begin
        feedback_timer <= apply_feedback_decay ? feedback_timer + 1 - period : feedback_timer + 1;
      end
    end else begin
      for (integer i = 0; i < INSTRUMENT_COUNT; i += 1) begin
        requested_sample[i] <= sample_buffer_out[i];
        last_pos_valid[i]   <= pos_valid[i];
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


  square_left #(
      .WIDTH(512),
      .CENTER_X(640),
      .CENTER_Y(450)
  ) bd_square (
      .clk(clk),
      .rst(rst),
      .h_count(h_count),
      .v_count(v_count),
      .delay_rate(rate_cached),
      .delay_period(period),
      .history_address(request_address[0]),
      .shape_valid(pos_valid[0])
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
      .delay_rate(rate_cached),
      .delay_period(period),
      .history_address(request_address[1]),
      .shape_valid(pos_valid[1])

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
      .delay_rate(rate_cached),
      .delay_period(period),
      .history_address(request_address[2]),
      .shape_valid(pos_valid[2])

  );
endmodule  // delay_gen

// 3 cycle delay
module square_left #(
    parameter WIDTH = 128,
    parameter CENTER_X = 400,
    parameter CENTER_Y = 400
) (
    input  wire         clk,
    input  wire         rst,
    input  wire  [10:0] h_count,
    input  wire  [ 9:0] v_count,
    input  wire  [ 9:0] delay_rate,
    input  wire  [ 7:0] delay_period,
    output logic [ 5:0] history_address,
    output logic        shape_valid
);
  localparam LEFT_EDGE_X = CENTER_X - WIDTH / 2;
  localparam TOP_EDGE_Y = CENTER_Y + WIDTH / 2;
  localparam BOTTOM_EDGE_Y = CENTER_Y - WIDTH / 2;

  // - figure out x offset from edge
  // - mulitply by delay_rate
  // - use upper bits for address and lower bits to determine shape_valid
  logic [ 8:0] x_offset;
  logic [15:0] rate_x_offset;

  always_ff @(posedge clk) begin
    if (rst) begin
      x_offset <= 0;
      rate_x_offset <= 0;
      history_address <= 0;
    end else begin
      if (v_count < TOP_EDGE_Y && v_count > BOTTOM_EDGE_Y && h_count < LEFT_EDGE_X) begin
        x_offset <= (LEFT_EDGE_X - h_count);
      end else begin
        x_offset <= 0;
      end
      rate_x_offset <= x_offset[8:1] * delay_rate[9:2];
      history_address <= ((rate_x_offset[15:10] + 1) * {8'h0, delay_period});
      shape_valid <= rate_x_offset[9];
    end
  end
endmodule  // square_left

`default_nettype wire
