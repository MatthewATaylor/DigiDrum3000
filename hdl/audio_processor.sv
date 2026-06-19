`timescale 1ns / 1ps
`default_nettype none

module audio_processor
    #(
        parameter INSTRUMENT_COUNT
    )
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

        input  wire  [15:0] instrument_samples [INSTRUMENT_COUNT-1:0],
        input  wire  [15:0] sample_from_dram,
        input  wire         valid_from_dram,

        output logic [15:0] sample_out_l,
        output logic [15:0] sample_out_r,
        output logic [15:0] instrument_samples_out [INSTRUMENT_COUNT-1:0],
        output logic        sample_out_valid,
        output logic        sample_out_valid_base,

        input  wire  [16*4-1:0] ext_samples_in
    );

    logic [15:0] sample_from_resampler;
    logic        valid_from_resampler;
    resampler resampler_i (
        .clk(clk),
        .rst(rst),
        .sample_period_in(sample_period_dram_out),
        .sample_period_farrow_out(14'd625),
        .sample_in(sample_from_dram),
        .sample_in_valid(valid_from_dram),
        .sample_out(sample_from_resampler),
        .sample_out_valid(valid_from_resampler)
    );

    logic [19:0] sample_from_resampler_plus_ext;
    logic [15:0] sample_from_base;
    logic        valid_from_base;
    clipper #(
        .WIDTH_FULL(20),
        .WIDTH_CLIP(16),
        .RIGHT_SHIFT(0)
    ) clipper_resampler_ext (
        .din(sample_from_resampler_plus_ext),
        .dout(sample_from_base)
    );
    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_from_resampler_plus_ext <= 20'b0;
        end else begin
            if (valid_from_resampler) begin
                sample_from_resampler_plus_ext <=
                    $signed(sample_from_resampler) +
                    $signed(ext_samples_in[63:48]) +
                    $signed(ext_samples_in[47:32]) +
                    $signed(ext_samples_in[31:16]) +
                    $signed(ext_samples_in[15: 0]);
                valid_from_base <= 1'b1;
            end else begin
                valid_from_base <= 1'b0;
            end
        end
    end

    assign sample_out_valid_base = valid_from_base;

    // Resample instrument_samples for dry recording of each instrument
    genvar resampler_index;
    generate
        for (resampler_index=0; resampler_index<INSTRUMENT_COUNT; ++resampler_index) begin
            resampler resampler_dry (
                .clk(clk),
                .rst(rst),
                .sample_period_in(sample_period_dram_out),
                .sample_period_farrow_out(14'd625),
                .sample_in(instrument_samples[resampler_index]),
                .sample_in_valid(valid_from_dram),
                .sample_out(instrument_samples_out[resampler_index]),
                .sample_out_valid()
            );
        end
    endgenerate
    //logic [16*INSTRUMENT_COUNT-1:0] instrument_samples_packed;
    //logic [16*INSTRUMENT_COUNT-1:0] instrument_samples_out_packed;
    //genvar instr_index;
    //generate
    //    for (instr_index=0; instr_index<INSTRUMENT_COUNT; ++instr_index) begin
    //        assign instrument_samples_packed[16*(instr_index+1)-1 : 16*instr_index] =
    //            instrument_samples[instr_index];
    //        assign instrument_samples_out[instr_index] =
    //            instrument_samples_out_packed[16*(instr_index+1)-1 : 16*instr_index];
    //    end
    //endgenerate
    //resampler_shared #(
    //    .SAMPLE_COUNT(INSTRUMENT_COUNT)
    //) resampler_shared_i (
    //    .clk(clk),
    //    .rst(rst),
    //    .sample_period_in(sample_period_dram_out),
    //    .sample_period_farrow_out(14'd625),
    //    .sample_in(instrument_samples_packed),
    //    .sample_in_valid(valid_from_dram),
    //    .sample_out(instrument_samples_out_packed),
    //    .sample_out_valid()
    //);

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

    //assign reverb_is_stereo = 1;
    //assign sample_to_reverb = sample_from_base;
    //assign valid_to_reverb = valid_from_base;

    //assign sample_out_l = sample_l_from_reverb;
    //assign sample_out_r = sample_r_from_reverb;
    //assign sample_out_valid = valid_from_reverb;

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


        .sample_l_to_output(sample_out_l),
        .sample_r_to_output(sample_out_r),
        .valid_to_output(sample_out_valid),

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
