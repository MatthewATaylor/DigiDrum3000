`timescale 1ns / 1ps
`default_nettype none

module resampler_shared
    #(
        parameter SAMPLE_COUNT
    )
    (
        input wire clk,
        input wire rst,

        input  wire  [13:0] sample_period_in,
        input  wire  [13:0] sample_period_farrow_out,

        input  wire  [16*SAMPLE_COUNT-1:0] sample_in,
        input  wire                        sample_in_valid,

        output logic [16*SAMPLE_COUNT-1:0] sample_out,
        output logic                       sample_out_valid
    );

    logic [16*SAMPLE_COUNT-1:0] farrow_upsample;
    logic                       farrow_upsample_valid;
    farrow_shared_top #(
        .SAMPLE_COUNT(SAMPLE_COUNT)
    ) farrow (
        .clk(clk),
        .rst(rst),

        .sample_period_in({2'b0, sample_period_in}),
        .sample_period_out({2'b0, sample_period_farrow_out}),
        
        .sample_in(sample_in),
        .sample_in_valid(sample_in_valid),

        .sample_out(farrow_upsample),
        .sample_out_valid(farrow_upsample_valid),

        .delay_debug(),
        .delay_debug_valid(0)
    );

    logic [SAMPLE_COUNT-1:0] sample_out_valids;
    assign                   sample_out_valid = sample_out_valids[0];
    genvar downsampler_index;
    generate
        for (downsampler_index=0; downsampler_index<SAMPLE_COUNT; ++downsampler_index) begin
            downsampler downsampler_i (
                .clk(clk),
                .rst(rst),

                .sample_in(farrow_upsample[16*(downsampler_index+1)-1 : 16*downsampler_index]),
                .sample_in_valid(farrow_upsample_valid),

                .sample_out(sample_out[16*(downsampler_index+1)-1 : 16*downsampler_index]),
                .sample_out_valid(sample_out_valids[downsampler_index])
            );
        end
    endgenerate

endmodule
`default_nettype wire
