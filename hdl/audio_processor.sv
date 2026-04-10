`timescale 1ns / 1ps
`default_nettype none

module audio_processor
    (
        input wire clk,
        input wire rst,

        input wire [9:0] volume_on_clk,
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

        input wire delay_rate_fast_on_clk,

        input  wire  [13:0] sample_period_dram_out,

        input  wire  [15:0] sample_from_dram,
        input  wire         valid_from_dram,

        output logic spkl,
        output logic spkr
    );

    logic [15:0] sample_from_base;
    logic        valid_from_base;
    resampler resampler_i (
        .clk(clk),
        .rst(rst),
        .sample_period_in(sample_period_dram_out),
        .sample_period_farrow_out(14'd568),
        .sample_in(sample_from_dram),
        .sample_in_valid(valid_from_dram),
        .sample_out(sample_from_base),
        .sample_out_valid(valid_from_base)
    );

    logic [15:0] sample_to_delay;
    logic        valid_to_delay;
    logic [15:0] sample_from_delay;
    logic        valid_from_delay;
    audio_delay delay (
        .clk(clk),
        .rst(rst),
        .sw_delay_fast(delay_rate_fast_on_clk),
        .pot_wet(delay_wet_on_clk),
        .pot_rate(delay_rate_on_clk),
        .pot_feedback(delay_feedback_on_clk),
        .sample_in(sample_to_delay),
        .sample_in_valid(valid_to_delay),
        .sample_out(sample_from_delay),
        .sample_out_valid(valid_from_delay)
    );

    logic [15:0] sample_to_distortion;
    logic        valid_to_distortion;
    logic [15:0] sample_from_distortion;
    logic        valid_from_distortion;
    audio_distortion_oversampled distortion (
        .clk(clk),
        .rst(rst),
        .pot_drive(distortion_drive_on_clk),
        .sample_in(sample_to_distortion),
        .sample_in_valid(valid_to_distortion),
        .sample_out(sample_from_distortion),
        .sample_out_valid(valid_from_distortion)
    );

    logic [15:0] sample_to_crush;
    logic        valid_to_crush;
    logic [15:0] sample_from_crush;
    logic        valid_from_crush;
    audio_crush crush (
        .clk(clk),
        .rst(rst),
        .pot_crush(crush_pressure_on_clk),
        .sample_in(sample_to_crush),
        .sample_in_valid(valid_to_crush),
        .sample_out(sample_from_crush),
        .sample_out_valid(valid_from_crush)
    );

    logic [15:0] sample_to_filter;
    logic        valid_to_filter;
    logic [15:0] sample_from_filter;
    logic        valid_from_filter;
    audio_filter_oversampled filter (
        .clk(clk),
        .rst(rst),
        .pot_cutoff(filter_cutoff_on_clk),
        .pot_quality(filter_quality_on_clk),
        .sample_in(sample_to_filter),
        .sample_in_valid(valid_to_filter),
        .sample_out(sample_from_filter),
        .sample_out_valid(valid_from_filter)
    );

    logic        reverb_is_stereo;
    logic [15:0] sample_to_reverb;
    logic        valid_to_reverb;
    logic [15:0] sample_l_from_reverb;
    logic [15:0] sample_r_from_reverb;
    logic        valid_from_reverb;
    audio_reverb_stereo reverb (
        .clk(clk),
        .rst(rst),
        .pot_wet(reverb_wet_on_clk),
        .pot_size(reverb_size_on_clk),
        .pot_feedback(reverb_feedback_on_clk),
        .is_stereo(reverb_is_stereo),
        .sample_in(sample_to_reverb),
        .sample_in_valid(valid_to_reverb),
        .sample_out_l(sample_l_from_reverb),
        .sample_out_r(sample_r_from_reverb),
        .sample_out_valid(valid_from_reverb)
    );

    logic [15:0] sample_l_to_output;
    logic [15:0] sample_r_to_output;
    logic        valid_to_output;
    logic [15:0] upsampler_out_l;
    logic [15:0] upsampler_out_r;
    upsampler #(
        .RATIO(16),
        .VOLUME_EN(1),
        .FILTER_FILE("DAC_filter_coeffs.mem"),
        .FILTER_TAPS(1024),
        .FILTER_SCALE(21)
    ) upsampler_l (
        .clk(clk),
        .rst(rst),
        .sample_in(sample_l_to_output),
        .sample_in_valid(valid_to_output),
        .volume(volume_on_clk),
        .sample_out(upsampler_out_l),
        .sample_out_valid()
    );
    // upsampler #(
    //     .RATIO(16),
    //     .VOLUME_EN(1),
    //     .FILTER_FILE("DAC_filter_coeffs.mem"),
    //     .FILTER_TAPS(1024),
    //     .FILTER_SCALE(21)
    // ) upsampler_r (
    //     .clk(clk),
    //     .rst(rst),
    //     .sample_in(sample_r_to_output),
    //     .sample_in_valid(valid_to_output),
    //     .volume(volume_on_clk),
    //     .sample_out(upsampler_out_r),
    //     .sample_out_valid()
    // );

    logic dac_out_l;
    dlt_sig_dac_2nd_order dlt_sig_l (
        .clk(clk),
        .rst(rst),
        .current_sample(upsampler_out_l),
        .audio_out(dac_out_l)
    );
    // logic dac_out_r;
    // dlt_sig_dac_2nd_order dlt_sig_r (
    //     .clk(clk),
    //     .rst(rst),
    //     .current_sample(upsampler_out_r),
    //     .audio_out(dac_out_r)
    // );

    // This seems to help with noise
    always_ff @ (posedge clk) begin
        if (rst) begin
            spkl <= 0;
            spkr <= 0;
        end else begin
            spkl <= dac_out_l;
            spkr <= dac_out_l;
            // spkr <= dac_out_r;
        end
    end

    audio_multi_mux audio_multi_mux_i (
        .delay_src(delay_src_on_clk),
        .output_src(output_src_on_clk),
        .crush_src(crush_src_on_clk),
        .distortion_src(distortion_src_on_clk),
        .filter_src(filter_src_on_clk),
        .reverb_src(reverb_src_on_clk),


        .sample_from_base(sample_from_base),
        .valid_from_base(valid_from_base),

        .sample_from_crush(sample_from_crush),
        .valid_from_crush(valid_from_crush),

        .sample_from_distortion(sample_from_distortion),
        .valid_from_distortion(valid_from_distortion),

        .sample_from_filter(sample_from_filter),
        .valid_from_filter(valid_from_filter),

        .sample_l_from_reverb(sample_l_from_reverb),
        .sample_r_from_reverb(sample_r_from_reverb),
        .valid_from_reverb(valid_from_reverb),

        .sample_from_delay(sample_from_delay),
        .valid_from_delay(valid_from_delay),


        .sample_l_to_output(sample_l_to_output),
        .sample_r_to_output(sample_r_to_output),
        .valid_to_output(valid_to_output),

        .sample_to_crush(sample_to_crush),
        .valid_to_crush(valid_to_crush),

        .sample_to_distortion(sample_to_distortion),
        .valid_to_distortion(valid_to_distortion),

        .sample_to_filter(sample_to_filter),
        .valid_to_filter(valid_to_filter),

        .sample_to_reverb(sample_to_reverb),
        .valid_to_reverb(valid_to_reverb),

        .sample_to_delay(sample_to_delay),
        .valid_to_delay(valid_to_delay),


        .reverb_is_stereo(reverb_is_stereo)
    );

endmodule

`default_nettype wire
