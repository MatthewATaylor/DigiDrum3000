`timescale 1ns / 1ps  //
`default_nettype none

module video_processor #(
    parameter INSTRUMENT_COUNT = 3
) (
    input wire clk_100MHz,
    input wire clk_pixel,
    input wire rst,

    // clk_100MHz
    //input wire [15:0] instrument_samples[INSTRUMENT_COUNT-1:0],
    input wire midi_valid,
    input wire [6:0] midi_key,
    input wire [6:0] midi_velocity,
    //input wire [15:0] upsampled_audio_ouput,
    input wire [9:0] volume_on_clk,
    input wire [9:0] pitch_on_clk,
    input wire [9:0] delay_wet_on_clk,
    input wire [9:0] delay_rate_on_clk,
    input wire [9:0] delay_feedback_on_clk,
    input wire [9:0] reverb_wet_on_clk,
    input wire [9:0] reverb_size_on_clk,
    input wire [9:0] reverb_feedback_on_clk,
    input wire [9:0] filter_quality_on_clk,
    input wire [9:0] filter_cutoff_on_clk,
    input wire [9:0] distortion_drive_on_clk,
    input wire [9:0] crush_pressure_on_clk,

    input wire [2:0] output_src_on_clk,
    input wire [2:0] crush_src_on_clk,
    input wire [2:0] distortion_src_on_clk,
    input wire [2:0] filter_src_on_clk,
    input wire [2:0] reverb_src_on_clk,
    input wire [2:0] delay_src_on_clk,

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
  logic [ 9:0] volume_on_pixel_clk;
  logic [ 9:0] pitch_on_pixel_clk;
  logic [ 9:0] delay_wet_on_pixel_clk;
  logic [ 9:0] delay_rate_on_pixel_clk;
  logic [ 9:0] delay_feedback_on_pixel_clk;
  logic [ 9:0] reverb_wet_on_pixel_clk;
  logic [ 9:0] reverb_size_on_pixel_clk;
  logic [ 9:0] reverb_feedback_on_pixel_clk;
  logic [ 9:0] filter_quality_on_pixel_clk;
  logic [ 9:0] filter_cutoff_on_pixel_clk;
  logic [ 9:0] distortion_drive_on_pixel_clk;
  logic [ 9:0] crush_pressure_on_pixel_clk;

  logic [ 2:0] output_src_on_pixel_clk;
  logic [ 2:0] crush_src_on_pixel_clk;
  logic [ 2:0] distortion_src_on_pixel_clk;
  logic [ 2:0] filter_src_on_pixel_clk;
  logic [ 2:0] reverb_src_on_pixel_clk;
  logic [ 2:0] delay_src_on_pixel_clk;

  logic [10:0] sig_gen_h_count;
  logic [ 9:0] sig_gen_v_count;
  logic        sig_gen_active_draw;
  logic        sig_gen_new_frame;

  clk_cross_buffer my_buf (
      .clk_pixel(clk_pixel),
      .rst      (rst),
      .new_frame(sig_gen_new_frame),

      .volume_on_clk          (volume_on_clk),
      .pitch_on_clk           (pitch_on_clk),
      .delay_wet_on_clk       (delay_wet_on_clk),
      .delay_rate_on_clk      (delay_rate_on_clk),
      .delay_feedback_on_clk  (delay_feedback_on_clk),
      .reverb_wet_on_clk      (reverb_wet_on_clk),
      .reverb_size_on_clk     (reverb_size_on_clk),
      .reverb_feedback_on_clk (reverb_feedback_on_clk),
      .filter_quality_on_clk  (filter_quality_on_clk),
      .filter_cutoff_on_clk   (filter_cutoff_on_clk),
      .distortion_drive_on_clk(distortion_drive_on_clk),
      .crush_pressure_on_clk  (crush_pressure_on_clk),

      .output_src_on_clk    (output_src_on_clk),
      .crush_src_on_clk     (crush_src_on_clk),
      .distortion_src_on_clk(distortion_src_on_clk),
      .filter_src_on_clk    (filter_src_on_clk),
      .reverb_src_on_clk    (reverb_src_on_clk),
      .delay_src_on_clk     (delay_src_on_clk),

      .volume_on_pixel_clk          (volume_on_pixel_clk),
      .pitch_on_pixel_clk           (pitch_on_pixel_clk),
      .delay_wet_on_pixel_clk       (delay_wet_on_pixel_clk),
      .delay_rate_on_pixel_clk      (delay_rate_on_pixel_clk),
      .delay_feedback_on_pixel_clk  (delay_feedback_on_pixel_clk),
      .reverb_wet_on_pixel_clk      (reverb_wet_on_pixel_clk),
      .reverb_size_on_pixel_clk     (reverb_size_on_pixel_clk),
      .reverb_feedback_on_pixel_clk (reverb_feedback_on_pixel_clk),
      .filter_quality_on_pixel_clk  (filter_quality_on_pixel_clk),
      .filter_cutoff_on_pixel_clk   (filter_cutoff_on_pixel_clk),
      .distortion_drive_on_pixel_clk(distortion_drive_on_pixel_clk),
      .crush_pressure_on_pixel_clk  (crush_pressure_on_pixel_clk),

      .output_src_on_pixel_clk    (output_src_on_pixel_clk),
      .crush_src_on_pixel_clk     (crush_src_on_pixel_clk),
      .distortion_src_on_pixel_clk(distortion_src_on_pixel_clk),
      .filter_src_on_pixel_clk    (filter_src_on_pixel_clk),
      .reverb_src_on_pixel_clk    (reverb_src_on_pixel_clk),
      .delay_src_on_pixel_clk     (delay_src_on_pixel_clk)
  );

  video_sig_gen_basic my_sig_gen (
      .clk(clk_pixel),
      .rst(rst),

      .h_count(sig_gen_h_count),
      .v_count(sig_gen_v_count),
      .active_draw(sig_gen_active_draw),
      .new_frame(sig_gen_new_frame)
  );

  logic [7:0] inst_intensity[INSTRUMENT_COUNT-1:0];
  note_tracker_midi #(
      .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
  ) my_note_tracker (
      .clk_100MHz(clk_100MHz),
      .clk_pixel(clk_pixel),
      .rst(rst),

      .midi_key(midi_key),
      .midi_valid(midi_valid),
      .midi_velocity(midi_velocity),
      .pitch(pitch_on_pixel_clk),

      .new_frame(sig_gen_new_frame),
      .inst_intensity(inst_intensity)
  );

  logic [7:0] dry_intensity;
  logic [7:0] dry_intensity_pipe[2:0];
  logic [7:0] delay_intensity;

  dry_gen my_dry_gen (
      .clk(clk_pixel),
      .rst(rst),

      .active_draw(sig_gen_active_draw),
      .h_count(sig_gen_h_count),
      .v_count(sig_gen_v_count),
      .inst_intensity(inst_intensity),

      .intensity(dry_intensity)
  );

  delay_gen my_delay_gen (
      .clk(clk_pixel),
      .rst(rst),

      .active_draw(sig_gen_active_draw),
      .h_count(sig_gen_h_count),
      .v_count(sig_gen_v_count),
      .inst_intensity(inst_intensity),

      .wet(delay_wet_on_pixel_clk),
      .rate(delay_rate_on_pixel_clk),
      .feedback(delay_feedback_on_pixel_clk),

      .intensity(delay_intensity)
  );

  logic [23:0] pixel_color_from_color_gen;

  color_gen my_color (
      .clk(clk_pixel),
      .rst(rst),

      .h_count(sig_gen_h_count),
      .v_count(sig_gen_v_count),
      .pitch  (pitch_on_pixel_clk),

      .color(pixel_color_from_color_gen)
  );

  localparam BASE_GEN_PIPE_LENGTH = 7;
  logic [10:0] base_h_count_pipe[BASE_GEN_PIPE_LENGTH-1:0];
  logic [ 9:0] base_v_count_pipe[BASE_GEN_PIPE_LENGTH-1:0];

  always_ff @(posedge clk_pixel) begin
    if (rst) begin
      dry_intensity_pipe[0] <= 0;
      dry_intensity_pipe[1] <= 0;
      dry_intensity_pipe[2] <= 0;
      for (integer i = 0; i < BASE_GEN_PIPE_LENGTH; i += 1) begin
        base_h_count_pipe[i+1] <= 0;
        base_v_count_pipe[i+1] <= 0;
      end
    end else begin
      dry_intensity_pipe[0] <= dry_intensity;
      dry_intensity_pipe[1] <= dry_intensity_pipe[0];
      dry_intensity_pipe[2] <= dry_intensity_pipe[1];
      base_h_count_pipe[0]  <= sig_gen_h_count;
      base_v_count_pipe[0]  <= sig_gen_v_count;
      for (integer i = 0; i < BASE_GEN_PIPE_LENGTH - 1; i += 1) begin
        base_h_count_pipe[i+1] <= base_h_count_pipe[i];
        base_v_count_pipe[i+1] <= base_v_count_pipe[i];
      end
    end
  end

  logic [10:0] h_count_base;
  logic [ 9:0] v_count_base;
  logic        active_draw_base;
  logic [23:0] pixel_color_base;

  base_combiner my_combiner (
      .clk(clk_pixel),
      .rst(rst),
      .h_count_in(base_h_count_pipe[BASE_GEN_PIPE_LENGTH-1]),
      .v_count_in(base_v_count_pipe[BASE_GEN_PIPE_LENGTH-1]),
      .brightness_from_dry(dry_intensity_pipe[2]),
      .brightness_from_delay(delay_intensity),
      .pixel_color_in(pixel_color_from_color_gen),
      .delay_src(delay_src_on_pixel_clk),

      .h_count_out(h_count_base),
      .v_count_out(v_count_base),
      .active_draw_out(active_draw_base),
      .pixel_color_out(pixel_color_base)
  );

  gui_render_and_overlay my_gui (
      .clk(clk_pixel),
      .rst(rst),
      .h_count_in(h_count_base),
      .v_count_in(v_count_base),
      .pixel_in(pixel_color_base),
      .active_draw_in(active_draw_base),

      .pixel_to_hdmi(pixel_to_hdmi),
      .h_sync_to_hdmi(h_sync_to_hdmi),
      .v_sync_to_hdmi(v_sync_to_hdmi),
      .active_draw_to_hdmi(active_draw_to_hdmi)
  );

endmodule

`default_nettype wire
