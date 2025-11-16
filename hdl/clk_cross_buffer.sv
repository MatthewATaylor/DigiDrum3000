`timescale 1ns / 1ps  //
`default_nettype none

module clk_cross_buffer (
    input wire clk_pixel,
    input wire rst,
    input wire new_frame,

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

    output logic [9:0] volume_on_pixel_clk,
    output logic [9:0] pitch_on_pixel_clk,
    output logic [9:0] delay_wet_on_pixel_clk,
    output logic [9:0] delay_rate_on_pixel_clk,
    output logic [9:0] delay_feedback_on_pixel_clk,
    output logic [9:0] reverb_wet_on_pixel_clk,
    output logic [9:0] reverb_size_on_pixel_clk,
    output logic [9:0] reverb_feedback_on_pixel_clk,
    output logic [9:0] filter_quality_on_pixel_clk,
    output logic [9:0] filter_cutoff_on_pixel_clk,
    output logic [9:0] distortion_drive_on_pixel_clk,
    output logic [9:0] crush_pressure_on_pixel_clk
);


  logic [9:0] volume_pipe[1:0];
  logic [9:0] pitch_pipe[1:0];
  logic [9:0] delay_wet_pipe[1:0];
  logic [9:0] delay_rate_pipe[1:0];
  logic [9:0] delay_feedback_pipe[1:0];
  logic [9:0] reverb_wet_pipe[1:0];
  logic [9:0] reverb_size_pipe[1:0];
  logic [9:0] reverb_feedback_pipe[1:0];
  logic [9:0] filter_quality_pipe[1:0];
  logic [9:0] filter_cutoff_pipe[1:0];
  logic [9:0] distortion_drive_pipe[1:0];
  logic [9:0] crush_pressure_pipe[1:0];

  always_ff @(posedge clk_pixel) begin
    volume_pipe[0]           <= volume_on_clk;
    pitch_pipe[0]            <= pitch_on_clk;
    delay_wet_pipe[0]        <= delay_wet_on_clk;
    delay_rate_pipe[0]       <= delay_rate_on_clk;
    delay_feedback_pipe[0]   <= delay_feedback_on_clk;
    reverb_wet_pipe[0]       <= reverb_wet_on_clk;
    reverb_size_pipe[0]      <= reverb_size_on_clk;
    reverb_feedback_pipe[0]  <= reverb_feedback_on_clk;
    filter_quality_pipe[0]   <= filter_quality_on_clk;
    filter_cutoff_pipe[0]    <= filter_cutoff_on_clk;
    distortion_drive_pipe[0] <= distortion_drive_on_clk;
    crush_pressure_pipe[0]   <= crush_pressure_on_clk;

    volume_pipe[1]           <= volume_pipe[0];
    pitch_pipe[1]            <= pitch_pipe[0];
    delay_wet_pipe[1]        <= delay_wet_pipe[0];
    delay_rate_pipe[1]       <= delay_rate_pipe[0];
    delay_feedback_pipe[1]   <= delay_feedback_pipe[0];
    reverb_wet_pipe[1]       <= reverb_wet_pipe[0];
    reverb_size_pipe[1]      <= reverb_size_pipe[0];
    reverb_feedback_pipe[1]  <= reverb_feedback_pipe[0];
    filter_quality_pipe[1]   <= filter_quality_pipe[0];
    filter_cutoff_pipe[1]    <= filter_cutoff_pipe[0];
    distortion_drive_pipe[1] <= distortion_drive_pipe[0];
    crush_pressure_pipe[1]   <= crush_pressure_pipe[0];

    if (new_frame) begin
      volume_on_pixel_clk           <= volume_pipe[1];
      pitch_on_pixel_clk            <= pitch_pipe[1];
      delay_wet_on_pixel_clk        <= delay_wet_pipe[1];
      delay_rate_on_pixel_clk       <= delay_rate_pipe[1];
      delay_feedback_on_pixel_clk   <= delay_feedback_pipe[1];
      reverb_wet_on_pixel_clk       <= reverb_wet_pipe[1];
      reverb_size_on_pixel_clk      <= reverb_size_pipe[1];
      reverb_feedback_on_pixel_clk  <= reverb_feedback_pipe[1];
      filter_quality_on_pixel_clk   <= filter_quality_pipe[1];
      filter_cutoff_on_pixel_clk    <= filter_cutoff_pipe[1];
      distortion_drive_on_pixel_clk <= distortion_drive_pipe[1];
      crush_pressure_on_pixel_clk   <= crush_pressure_pipe[1];
    end

  end
endmodule  // clk_cross_buffer

`default_nettype none
