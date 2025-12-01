`timescale 1ns / 1ps
`default_nettype none

module audio_reverb_stereo
    (
        input wire clk,
        input wire rst,

        input wire [9:0] pot_wet,
        input wire [9:0] pot_size,
        input wire [9:0] pot_feedback,
        input wire       is_stereo,

        input wire [15:0] sample_in,
        input wire        sample_in_valid,

        output logic [15:0] sample_out_l,
        output logic [15:0] sample_out_r,
        output logic        sample_out_valid
    );

    logic [15:0] reverb_out_l;
    logic        reverb_out_l_valid;
    audio_reverb #(
        .CHANNEL(0)
    ) reverb_l (
        .clk(clk),
        .rst(rst),
        .pot_wet(pot_wet),
        .pot_size(pot_size),
        .pot_feedback(pot_feedback),
        .sample_in(sample_in),
        .sample_in_valid(sample_in_valid),
        .sample_out(reverb_out_l),
        .sample_out_valid(reverb_out_l_valid)
    );

    logic [15:0] reverb_out_r;
    logic        reverb_out_r_valid;
    audio_reverb #(
        .CHANNEL(1)
    ) reverb_r (
        .clk(clk),
        .rst(rst),
        .pot_wet(pot_wet),
        .pot_size(pot_size),
        .pot_feedback(pot_feedback),
        .sample_in(sample_in),
        .sample_in_valid(sample_in_valid),
        .sample_out(reverb_out_r),
        .sample_out_valid(reverb_out_r_valid)
    );

    logic [15:0] mono_out;
    assign mono_out = $signed(
        {reverb_out_l[15], reverb_out_l} +
        {reverb_out_r[15], reverb_out_r}
    ) >>> 1;

    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_out_l <= 0;
            sample_out_r <= 0;
            sample_out_valid <= 0;
        end else begin
            // Assume L/R valid signals are the same
            if (reverb_out_l_valid) begin
                if (is_stereo) begin
                    sample_out_l <= reverb_out_l;
                    sample_out_r <= reverb_out_r;
                end else begin
                    sample_out_l <= mono_out;
                    sample_out_r <= mono_out;
                end
            end
            sample_out_valid <= reverb_out_l_valid;
        end
    end

endmodule

`default_nettype wire

