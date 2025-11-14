`timescale 1ns / 1ps  //
`default_nettype none

module video_processor #(
    parameter INSTRUMENT_COUNT = 3
) (
    input wire clk_100MHz,
    input wire clk_pixel,
    input wire rst,

    // clk_100MHz
    input wire [15:0] instrument_samples[INSTRUMENT_COUNT-1:0],
    //input wire [2:0] effect_sources [5:0],
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
  logic [9:0] volume_on_pixel_clk;
  logic [9:0] pitch_on_pixel_clk;
  logic [9:0] delay_wet_on_pixel_clk;
  logic [9:0] delay_rate_on_pixel_clk;
  logic [9:0] delay_feedback_on_pixel_clk;
  logic [9:0] reverb_wet_on_pixel_clk;
  logic [9:0] reverb_size_on_pixel_clk;
  logic [9:0] reverb_feedback_on_pixel_clk;
  logic [9:0] filter_quality_on_pixel_clk;
  logic [9:0] filter_cutoff_on_pixel_clk;
  logic [9:0] distortion_drive_on_pixel_clk;
  logic [9:0] crush_pressure_on_pixel_clk;

  clk_cross_buffer my_buf (
      .clk_pixel(clk_pixel),
      .rst      (rst),

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
      .crush_pressure_on_pixel_clk  (crush_pressure_on_pixel_clk)
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

  logic [7:0] inst_sample_intensity[INSTRUMENT_COUNT-1:0];
  note_tracker #(
      .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
  ) my_note_tracker (
      .clk_100MHz(clk_100MHz),
      .clk_pixel(clk_pixel),
      .rst(rst),

      .instrument_samples(instrument_samples),

      .new_frame(sig_gen_new_frame),
      .max_sample_intensity(inst_sample_intensity)
  );

  logic [7:0] dry_intensity;
  logic [7:0] dry_intensity_pipe;
  logic [7:0] delay_intensity;
  logic [7:0] total_intensity;

  dry_gen my_dry_gen (
      .clk(clk_pixel),
      .rst(rst),

      .active_draw(sig_gen_active_draw),
      .h_count(sig_gen_h_count),
      .v_count(sig_gen_v_count),
      .inst_intensity(inst_sample_intensity),

      .intensity(dry_intensity)
  );

  delay_gen my_delay_gen (
      .clk(clk_pixel),
      .rst(rst),

      .active_draw(sig_gen_active_draw),
      .h_count(sig_gen_h_count),
      .v_count(sig_gen_v_count),
      .inst_intensity(inst_sample_intensity),

      .wet(delay_wet_on_pixel_clk),
      .rate(delay_rate_on_pixel_clk),
      .feedback(delay_feedback_on_pixel_clk),

      .intensity(delay_intensity)
  );

  always_ff @(posedge clk_pixel) begin
    if (rst) begin
      dry_intensity_pipe <= 0;
      total_intensity <= 0;
    end else begin
      dry_intensity_pipe <= dry_intensity;
      total_intensity <= dry_intensity_pipe ^ delay_intensity;
    end
  end

  gui_render_and_overlay my_gui (
      .clk(clk_pixel),
      .rst(rst),
      .h_count_in(sig_gen_h_count),
      .v_count_in(sig_gen_v_count),
      .pixel_in({total_intensity, total_intensity, total_intensity}),
      .active_draw_in(sig_gen_active_draw),

      .pixel_to_hdmi(pixel_to_hdmi),
      .h_sync_to_hdmi(h_sync_to_hdmi),
      .v_sync_to_hdmi(v_sync_to_hdmi),
      .active_draw_to_hdmi(active_draw_to_hdmi)
  );

endmodule

`default_nettype wire
