`timescale 1ns / 1ps
`default_nettype none

module resampler
    (
        input wire clk,
        input wire rst,

        input  wire  [13:0] sample_period,
        input  wire  [15:0] sample_in,
        input  wire         sample_in_valid,

        output logic [15:0] sample_out,
        output logic        sample_out_valid
    );

    logic [15:0] farrow_upsample;
    logic        farrow_upsample_valid;
    farrow_upsampler farrow (
        .clk(clk),
        .rst(rst),

        .sample_period(sample_period),
        
        .sample_in(sample_in),
        .sample_in_valid(sample_in_valid),

        .sample_out(farrow_upsample),
        .sample_out_valid(farrow_upsample_valid),

        .delay_debug(),
        .delay_debug_valid(0)
    );

    downsampler downsampler_i (
        .clk(clk),
        .rst(rst),

        .sample_in(farrow_upsample),
        .sample_in_valid(farrow_upsample_valid),

        .sample_out(sample_out),
        .sample_out_valid(sample_out_valid)
    );

endmodule
`default_nettype wire
