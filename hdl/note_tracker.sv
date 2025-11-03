`timescale 1ns / 1ps  //
`default_nettype none

module note_tracker #(
    parameter INSTRUMENT_COUNT = 3,
    parameter [6:0] MIDI_KEYS[INSTRUMENT_COUNT-1:0] = {
      7'd36,  // bd
      7'd38,  // sd
      7'd46  // hh_opened
    }
) (
    input wire clk_100MHz,
    input wire clk_pixel,
    input wire rst,

    // on clk
    input wire midi_valid,
    input wire [6:0] midi_key,
    input wire [6:0] midi_velocity,

    // on clk_pixel
    input wire new_frame,
    output logic [6:0] inst_velocity[INSTRUMENT_COUNT-1:0]
);

  localparam [6:0] velocity_decay[INSTRUMENT_COUNT-1:0] = {
    7'h10,  // bd
    7'h07,  // sd
    7'h02  // hh_opened
  };

  logic [6:0] midi_key_clk_cross_pipe     [3:0];
  logic [6:0] midi_velocity_clk_cross_pipe[3:0];
  // sum encoded, i.e. switches when midi_valid is true
  logic       midi_valid_clk_cross_pipe   [3:0];

  // on pixel_clk
  logic       last_midi_valid;

  logic       midi_sig_valid_pixel;
  assign midi_sig_valid_pixel =
    midi_key_clk_cross_pipe[3] == midi_key_clk_cross_pipe[2] &&
    midi_velocity_clk_cross_pipe[3] == midi_velocity_clk_cross_pipe[2] &&
    midi_valid_clk_cross_pipe[3] != last_midi_valid && !new_frame;

  always_ff @(posedge clk_pixel) begin
    if (rst) begin
      last_midi_valid <= 0;
    end else begin
      last_midi_valid <= midi_valid_clk_cross_pipe[3];
    end
  end

  always_ff @(posedge clk_pixel) begin
    integer i;
    if (rst) begin
      for (i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
        inst_velocity[i] <= 0;
      end
    end else if (new_frame) begin
      for (i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
        inst_velocity[i] <= (inst_velocity[i] > velocity_decay[i])
          ? inst_velocity[i]-velocity_decay[i] : 0;
      end
    end else if (midi_sig_valid_pixel) begin
      for (i = 0; i < INSTRUMENT_COUNT; i = i + 1) begin
        inst_velocity[i] <= midi_key_clk_cross_pipe[3] == MIDI_KEYS[i]
          ? midi_velocity_clk_cross_pipe[3]
          : inst_velocity[i];
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

    end else begin
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
