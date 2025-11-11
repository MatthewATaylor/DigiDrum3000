`timescale 1ns / 1ps  //
`default_nettype none

module pcb_interface (
    input wire clk,
    input wire rst,

    inout wire dry_pin,
    inout wire crush_pin,
    inout wire distortion_pin,
    inout wire filter_pin,
    inout wire reverb_pin,
    inout wire delay_pin,

    output logic [2:0] output_src,
    output logic [2:0] crush_src,
    output logic [2:0] distortion_src,
    output logic [2:0] filter_src,
    output logic [2:0] reverb_src,
    output logic [2:0] delay_src,

    input  wire  cipo,
    output logic copi,
    output logic dclk,
    output logic cs0,
    output logic cs1,

    output logic [9:0] volume,
    output logic [9:0] pitch,
    output logic [9:0] delay_wet,
    output logic [9:0] delay_rate,
    output logic [9:0] delay_feedback,
    output logic [9:0] reverb_wet,
    output logic [9:0] reverb_size,
    output logic [9:0] reverb_feedback,
    output logic [9:0] filter_quality,
    output logic [9:0] filter_cutoff,
    output logic [9:0] distortion_drive,
    output logic [9:0] crush_pressure
);

  logic dry_val;
  logic crush_val;
  logic distortion_val;
  logic filter_val;
  logic reverb_val;
  logic delay_val;

  assign dry_pin        = dry_val ? 1'bZ : 1'b0;
  assign crush_pin      = crush_val ? 1'bZ : 1'b0;
  assign distortion_pin = distortion_val ? 1'bZ : 1'b0;
  assign filter_pin     = filter_val ? 1'bZ : 1'b0;
  assign reverb_pin     = reverb_val ? 1'bZ : 1'b0;
  assign delay_pin      = delay_val ? 1'bZ : 1'b0;

  patch_reconstructor my_reconstructor (
      .clk(clk),
      .rst(rst),

      .dry(dry_val),
      .crush_val(crush_val),
      .distortion_val(distortion_val),
      .filter_val(filter_val),
      .reverb_val(reverb_val),
      .delay_val(delay_val),

      .crush(crush_pin),
      .distortion(distortion_pin),
      .filter(filter_pin),
      .reverb(reverb_pin),
      .delay(delay_pin),

      .output_src(output_src),
      .crush_src(crush_src),
      .distortion_src(distortion_src),
      .filter_src(filter_src),
      .reverb_src(reverb_src),
      .delay_src(delay_src)
  );

  logic [9:0] value;
  logic [3:0] pot_index;
  logic value_valid;

  pot_controller my_pot_con (
      .clk(clk),
      .rst(rst),

      .cipo(cipo),
      .copi(copi),
      .dclk(dclk),
      .cs0 (cs0),
      .cs1 (cs1),

      .value(value),
      .pot_index(pot_index),
      .value_valid(value_valid)
  );

  pot_state my_pot_state (
      .clk(clk),
      .rst(rst),

      .value(value),
      .pot_index(pot_index),
      .value_valid(value_valid),

      .volume(volume),
      .pitch(pitch),
      .delay_wet(delay_wet),
      .delay_rate(delay_rate),
      .delay_feedback(delay_feedback),
      .reverb_wet(reverb_wet),
      .reverb_size(reverb_size),
      .reverb_feedback(reverb_feedback),
      .filter_quality(filter_quality),
      .filter_cutoff(filter_cutoff),
      .distortion_drive(distortion_drive),
      .crush_pressure(crush_pressure)
  );

endmodule  // pcb_interface

`default_nettype wire
