`timescale 1ns / 1ps  //
`default_nettype none

module note_tracker_midi #(
    parameter INSTRUMENT_COUNT = 10,
    parameter [6:0] MIDI_KEYS[INSTRUMENT_COUNT-1:0] = {
      7'd51,  // rc
      7'd49,  // cc
      7'd44,  // hh_pedal
      7'd42,  // hh_closed
      7'd46,  // hh_opened
      7'd43,  // t3
      7'd45,  // t2
      7'd48,  // t1
      7'd38,  // sd
      7'd36  // bd
    }
) (
    input wire clk_100MHz,
    input wire clk_pixel,
    input wire rst,

    // on clk
    input wire midi_valid,
    input wire [6:0] midi_key,
    input wire [6:0] midi_velocity,
    input wire [9:0] pitch,

    // on clk_pixel
    input wire new_frame,
    output logic [7:0] inst_intensity[INSTRUMENT_COUNT-1:0]
);

  localparam [7:0] velocity_base_decay[INSTRUMENT_COUNT-1:0] = {
    7'd04,  // rc
    7'd04,  // cc
    7'd20,  // hh_pedal
    7'd25,  // hh_closed
    7'd04,  // hh_opened
    7'd20,  // t3
    7'd20,  // t2
    7'd20,  // t1
    7'd10,  // sd
    7'd25  // bd
  };

  logic [15:0] velocity_decay[INSTRUMENT_COUNT-1:0];
  logic [15:0] inst_intensity_high_res[INSTRUMENT_COUNT-1:0];

  always_ff @(posedge clk_pixel) begin
    for (integer i = 0; i < INSTRUMENT_COUNT; i += 1) begin
      if (rst) begin
        inst_intensity[i] <= 0;
      end else if (new_frame) begin
        inst_intensity[i] = inst_intensity_high_res[i][15:8];
      end
    end
  end

  logic [6:0] midi_key_clk_cross_pipe     [3:0];
  logic [6:0] midi_velocity_clk_cross_pipe[3:0];
  // sum encoded, i.e. switches when midi_valid is true
  logic       midi_valid_clk_cross_pipe   [3:0];

  // on pixel_clk
  logic       last_midi_valid;

  logic       midi_sig_valid_pixel;
  logic       key_and_vel_valid;
  assign midi_sig_valid_pixel =
    midi_key_clk_cross_pipe[3] == midi_key_clk_cross_pipe[2] &&
    midi_velocity_clk_cross_pipe[3] == midi_velocity_clk_cross_pipe[2] &&
    midi_valid_clk_cross_pipe[3] != last_midi_valid && !new_frame;

  always_ff @(posedge clk_pixel) begin
    if (rst) begin
      last_midi_valid <= 0;
    end else if (midi_sig_valid_pixel) begin
      last_midi_valid <= midi_valid_clk_cross_pipe[3];
    end
  end

  always_ff @(posedge clk_pixel) begin
    integer i;
    if (rst) begin
      for (i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
        inst_intensity_high_res[i] <= 0;
      end
    end else if (new_frame) begin
      for (i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
        inst_intensity_high_res[i] <= (inst_intensity_high_res[i] > velocity_decay[i])
          ? inst_intensity_high_res[i]-velocity_decay[i] : 0;
      end
    end else if (midi_sig_valid_pixel) begin
      for (i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
        inst_intensity_high_res[i] <= midi_key_clk_cross_pipe[3] == MIDI_KEYS[i]
          ? {midi_velocity_clk_cross_pipe[3], 9'b0}
          : inst_intensity_high_res[i];
      end
    end
  end

  always_ff @(posedge clk_100MHz) begin
    if (rst) begin
      midi_valid_clk_cross_pipe[0] <= 0;
      midi_key_clk_cross_pipe[0] <= 0;
      midi_velocity_clk_cross_pipe[0] <= 0;
    end else if (midi_valid) begin
      midi_valid_clk_cross_pipe[0] <= midi_valid_clk_cross_pipe[0] ^ midi_valid;
      midi_key_clk_cross_pipe[0] <= midi_valid ? midi_key : midi_key_clk_cross_pipe[0];
      midi_velocity_clk_cross_pipe[0] <= midi_valid ? midi_velocity : midi_velocity_clk_cross_pipe[0];
    end
  end

  always_ff @(posedge clk_pixel) begin
    if (rst) begin
      midi_valid_clk_cross_pipe[1]    <= 0;
      midi_valid_clk_cross_pipe[2]    <= 0;
      midi_valid_clk_cross_pipe[3]    <= 0;
      midi_key_clk_cross_pipe[1]      <= 0;
      midi_key_clk_cross_pipe[2]      <= 0;
      midi_key_clk_cross_pipe[3]      <= 0;
      midi_velocity_clk_cross_pipe[1] <= 0;
      midi_velocity_clk_cross_pipe[2] <= 0;
      midi_velocity_clk_cross_pipe[3] <= 0;
      for (integer i = 0; i < INSTRUMENT_COUNT; i += 1) begin
        velocity_decay[i] <= 0;
      end

    end else begin
      for (integer i = 0; i < INSTRUMENT_COUNT; i += 1) begin
        velocity_decay[i] <= velocity_base_decay[i] * (pitch[9:2] - pitch[9:5] + 5'h1F);
      end

      midi_valid_clk_cross_pipe[1]    <= midi_valid_clk_cross_pipe[0];
      midi_valid_clk_cross_pipe[2]    <= midi_valid_clk_cross_pipe[1];
      midi_valid_clk_cross_pipe[3]    <= midi_valid_clk_cross_pipe[2];
      midi_key_clk_cross_pipe[1]      <= midi_key_clk_cross_pipe[0];
      midi_key_clk_cross_pipe[2]      <= midi_key_clk_cross_pipe[1];
      midi_key_clk_cross_pipe[3]      <= midi_key_clk_cross_pipe[2];
      midi_velocity_clk_cross_pipe[1] <= midi_velocity_clk_cross_pipe[0];
      midi_velocity_clk_cross_pipe[2] <= midi_velocity_clk_cross_pipe[1];
      midi_velocity_clk_cross_pipe[3] <= midi_velocity_clk_cross_pipe[2];
    end
  end
endmodule

`default_nettype wire
