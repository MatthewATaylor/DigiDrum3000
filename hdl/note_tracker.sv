`timescale 1ns / 1ps  //
`default_nettype none

module note_tracker #(
    parameter INSTRUMENT_COUNT = 3
) (
    input wire clk_100MHz,
    input wire clk_pixel,
    input wire rst,

    // on clk_100MHz
    input wire [15:0] instrument_samples[INSTRUMENT_COUNT-1:0],

    // on clk_pixel
    input wire new_frame,
    output logic [7:0] max_sample_intensity[INSTRUMENT_COUNT-1:0]
);

  // sum encoded, i.e. new_frame pulse toggles this
  logic new_frame_pipe[2:0];
  // delay update until inst_intensity_pipe has stabilized
  logic new_frame_delayed[7:0];
  logic new_frame_clk_100MHz;
  logic [15:0] sample_unsigned[INSTRUMENT_COUNT-1:0];
  logic [15:0] running_max_inst_sample[INSTRUMENT_COUNT-1:0];
  logic [15:0] running_min_inst_sample[INSTRUMENT_COUNT-1:0];
  logic [15:0] running_max_intensity[INSTRUMENT_COUNT-1:0];
  logic [7:0] inst_intensity_cross_clk[INSTRUMENT_COUNT-1:0];

  assign new_frame_clk_100MHz = new_frame_pipe[2] != new_frame_pipe[1];

  always_comb begin
    for (integer i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
      sample_unsigned[i] = {~instrument_samples[i][15], instrument_samples[i][14:0]};
      running_max_intensity[i] = running_max_inst_sample[i] - running_min_inst_sample[i];
    end
  end

  always_ff @(posedge clk_pixel) begin
    for (integer i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
      if (rst) begin
        max_sample_intensity[i] <= 0;
      end else if (new_frame_delayed[7]) begin
        max_sample_intensity[i] <= inst_intensity_cross_clk[i];
      end
    end
  end

  always_ff @(posedge clk_100MHz) begin
    for (integer i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
      if (rst) begin
        inst_intensity_cross_clk[i] <= 0;
      end else if (new_frame_clk_100MHz) begin
        if (|running_max_intensity[i][15:13]) begin
          inst_intensity_cross_clk[i] <= 8'hFF;
        end else begin
          inst_intensity_cross_clk[i] <= running_max_intensity[i][12:5];
        end
      end
    end
  end

  // find the max peak over a frame [inaccurate below ~30Hz... should be fine]
  always_ff @(posedge clk_100MHz) begin
    integer i;
    if (rst || new_frame_clk_100MHz) begin
      for (i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
        running_max_inst_sample[i] <= 0;
        running_min_inst_sample[i] <= 16'hFFFF;
      end
    end else begin
      for (i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
        if (sample_unsigned[i] > running_max_inst_sample[i]) begin
          running_max_inst_sample[i] <= sample_unsigned[i];
        end
        if (sample_unsigned[i] < running_min_inst_sample[i]) begin
          running_min_inst_sample[i] <= sample_unsigned[i];
        end
      end
    end
  end

  always_ff @(posedge clk_pixel) begin
    if (rst) begin
      new_frame_pipe[0] <= 0;
      for (integer i = 0; i < 8; i = i + 1) begin
        new_frame_delayed[i] <= 0;
      end
    end else begin
      new_frame_pipe[0] <= new_frame ^ new_frame_pipe[0];
      new_frame_delayed[0] <= new_frame;
      for (integer i = 0; i < 7; i = i + 1) begin
        new_frame_delayed[i+1] <= new_frame_delayed[i];
      end
    end
  end

  always_ff @(posedge clk_100MHz) begin
    if (rst) begin
      new_frame_pipe[1] <= 0;
      new_frame_pipe[2] <= 0;
    end else begin
      new_frame_pipe[1] <= new_frame_pipe[0];
      new_frame_pipe[2] <= new_frame_pipe[1];
    end
  end


endmodule

`default_nettype wire
