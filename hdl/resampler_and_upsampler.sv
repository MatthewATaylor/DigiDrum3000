`timescale 1ns / 1ps
`default_nettype none

module resampler_and_upsampler
    (
        input wire clk,
        input wire rst,

        input  wire  [9:0] pitch,

        input  wire  [15:0] sample_in,
        input  wire         sample_in_valid,

        output logic [15:0] sample_out
    );

    logic [13:0] sample_period;
    pitch_to_sample_period p2sp (
        .clk(clk),
        .rst(rst),
        .pitch(pitch),
        .sample_period(sample_period)
    );

    logic [15:0] resample;
    logic        resample_valid;
    resampler resampler_i (
        .clk(clk),
        .rst(rst),
        .sample_period_in(sample_period),
        .sample_period_farrow_out(14'd568),
        .sample_in(sample_in),
        .sample_in_valid(sample_in_valid),
        .sample_out(resample),
        .sample_out_valid(resample_valid)
    );

    logic [15:0] sample_upsampled;
    upsampler upsampler_i (
        .clk(clk),
        .rst(rst),
        .sample_in(resample),
        .sample_in_valid(resample_valid),
        .sample_out(sample_out)
    );

endmodule

`default_nettype wire

