`timescale 1ns / 1ps  //
`default_nettype none

module video_processor #(
    parameter INSTRUMENT_COUNT = 3
) (
    input wire clk_100MHz,
    input wire clk_pixel,
    input wire rst,

    // clk_100MHz
    input wire [6:0] midi_key,
    input wire [6:0] midi_velocity,
    input wire       midi_valid,
    //input wire [2:0] effect_sources [5:0],
    //input wire [9:0] effect_parameters [10:0],
    //input wire [15:0] upsampled_audio_ouput,

    // clk_pixel
    //input wire [15:0] dram_read_data,
    //output logic dram_read_active_draw,
    //output logic [10:0] dram_read_h_count,
    //output logic [9:0] dram_read_v_count,
    //output logic draw_write_valid,
    //output logic [15:0] dram_write_data,
    //output logic dram_write_last,

    output logic [23:0] pixel_to_hdmi,
    output logic        active_draw_to_hdmi,
    output logic        v_sync_to_hdmi,
    output logic        h_sync_to_hdmi
);


  logic [10:0] sig_gen_h_count;
  logic [ 9:0] sig_gen_v_count;
  logic        sig_gen_active_draw;
  logic        sig_gen_new_frame;

  video_sig_gen_basic my_sig_gen (
      .clk(clk_pixel),
      .rst(rst),

      .h_count(sig_gen_h_count),
      .v_count(sig_gen_v_count),
      .active_draw(sig_gen_active_draw),
      .new_frame(sig_gen_new_frame)
  );

  logic [6:0] inst_velocity[INSTRUMENT_COUNT-1:0];
  note_tracker #(
      .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
  ) my_note_tracker (
      .clk_100MHz(clk_100MHz),
      .clk_pixel(clk_pixel),
      .rst(rst),

      .midi_valid(midi_valid),
      .midi_key(midi_key),
      .midi_velocity(midi_velocity),

      .new_frame(sig_gen_new_frame),
      .inst_velocity(inst_velocity)
  );

  logic [7:0] dry_intensity;
  dry_gen my_dry_gen (
      .clk(clk_pixel),
      .rst(rst),

      .active_draw(sig_gen_active_draw),
      .h_count(sig_gen_h_count),
      .v_count(sig_gen_v_count),
      .inst_velocity(inst_velocity),

      .intensity(dry_intensity)
  );

  gui_render_and_overlay my_gui (
      .clk(clk_pixel),
      .rst(rst),
      .h_count_in(sig_gen_h_count),
      .v_count_in(sig_gen_v_count),
      .pixel_in({dry_intensity, dry_intensity, dry_intensity}),
      .active_draw_in(sig_gen_active_draw),

      .pixel_to_hdmi(pixel_to_hdmi),
      .h_sync_to_hdmi(h_sync_to_hdmi),
      .v_sync_to_hdmi(v_sync_to_hdmi),
      .active_draw_to_hdmi(active_draw_to_hdmi)
  );

endmodule

`default_nettype wire
