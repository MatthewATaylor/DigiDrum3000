`timescale 1ns / 1ps
`default_nettype none

module audio_filter_oversampled
    (
        input wire clk,
        input wire rst,

        input wire [9:0] pot_cutoff,
        input wire [9:0] pot_quality,

        input wire [15:0] sample_in,
        input wire        sample_in_valid,

        output logic [15:0] sample_out,
        output logic        sample_out_valid
    );

    logic [15:0] upsampler_out;
    logic        upsampler_out_valid;
    upsampler #(
        .RATIO(4),
        .VOLUME_EN(0),
        .FILTER_FILE("x4_filter_coeffs.mem"),
        .FILTER_TAPS(512),
        .FILTER_SCALE(19)
    ) upsampler_i (
        .clk(clk),
        .rst(rst),
        .sample_in(sample_in),
        .sample_in_valid(sample_in_valid),
        .volume(10'b0),
        .sample_out(upsampler_out),
        .sample_out_valid(upsampler_out_valid)
    );

    logic [15:0] lpf_out;
    logic        lpf_out_valid;
    audio_filter_x4 #(
        .SOFT_CLIP(1)
    ) lpf (
        .clk(clk),
        .rst(rst),
        .pot_cutoff(pot_cutoff),
        .pot_quality(pot_quality),
        .sample_in(upsampler_out),
        .sample_in_valid(upsampler_out_valid),
        .sample_out(lpf_out),
        .sample_out_valid(lpf_out_valid)
    );

    downsampler downsampler_i (
        .clk(clk),
        .rst(rst),
        .sample_in(lpf_out),
        .sample_in_valid(lpf_out_valid),
        .sample_out(sample_out),
        .sample_out_valid(sample_out_valid)
    );

endmodule

`default_nettype wire

