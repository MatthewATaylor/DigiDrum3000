`timescale 1ns / 1ps
`default_nettype none

module audio_multi_mux
    (
        input wire [2:0] delay_src,
        input wire [2:0] output_src,
        input wire [2:0] crush_src,
        input wire [2:0] distortion_src,
        input wire [2:0] filter_src,
        input wire [2:0] reverb_src,


        // Sources
        
        input wire [15:0] sample_from_base,
        input wire        valid_from_base,

        input wire [15:0] sample_from_crush,
        input wire        valid_from_crush,

        input wire [15:0] sample_from_distortion,
        input wire        valid_from_distortion,

        input wire [15:0] sample_from_filter,
        input wire        valid_from_filter,

        input wire [15:0] sample_l_from_reverb,
        input wire [15:0] sample_r_from_reverb,
        input wire        valid_from_reverb,

        input wire [15:0] sample_from_delay,
        input wire        valid_from_delay,


        // Destinations

        output logic [15:0] sample_l_to_output,
        output logic [15:0] sample_r_to_output,
        output logic        valid_to_output,

        output logic [15:0] sample_to_crush,
        output logic        valid_to_crush,

        output logic [15:0] sample_to_distortion,
        output logic        valid_to_distortion,

        output logic [15:0] sample_to_filter,
        output logic        valid_to_filter,

        output logic [15:0] sample_to_reverb,
        output logic        valid_to_reverb,

        output logic [15:0] sample_to_delay,
        output logic        valid_to_delay,


        output logic reverb_is_stereo
    );

    always_comb begin
        case (output_src)
            3'b000: begin
                sample_l_to_output = sample_from_base;
                sample_r_to_output = sample_from_base;
                valid_to_output = valid_from_base;
                reverb_is_stereo = 1'b0;
            end
            3'b010: begin
                sample_l_to_output = sample_l_from_reverb;
                sample_r_to_output = sample_r_from_reverb;
                valid_to_output = valid_from_reverb;
                reverb_is_stereo = 1'b1;
            end
            3'b011: begin
                sample_l_to_output = sample_from_filter;
                sample_r_to_output = sample_from_filter;
                valid_to_output = valid_from_filter;
                reverb_is_stereo = 1'b0;
            end
            3'b100: begin
                sample_l_to_output = sample_from_distortion;
                sample_r_to_output = sample_from_distortion;
                valid_to_output = valid_from_distortion;
                reverb_is_stereo = 1'b0;
            end
            3'b101: begin
                sample_l_to_output = sample_from_crush;
                sample_r_to_output = sample_from_crush;
                valid_to_output = valid_from_crush;
                reverb_is_stereo = 1'b0;
            end
            3'b001: begin
                sample_l_to_output = sample_from_delay;
                sample_r_to_output = sample_from_delay;
                valid_to_output = valid_from_delay;
                reverb_is_stereo = 1'b0;
            end
            default: begin
                sample_l_to_output = 16'h0;
                sample_r_to_output = 16'h0;
                valid_to_output = 1'b0;
                reverb_is_stereo = 1'b0;
            end
        endcase

        case (reverb_src)
            3'b000: begin
                sample_to_reverb = sample_from_base;
                valid_to_reverb = valid_from_base;
            end
            3'b010: begin
                sample_to_reverb = sample_l_from_reverb;
                valid_to_reverb = valid_from_reverb;
            end
            3'b011: begin
                sample_to_reverb = sample_from_filter;
                valid_to_reverb = valid_from_filter;
            end
            3'b100: begin
                sample_to_reverb = sample_from_distortion;
                valid_to_reverb = valid_from_distortion;
            end
            3'b101: begin
                sample_to_reverb = sample_from_crush;
                valid_to_reverb = valid_from_crush;
            end
            3'b001: begin
                sample_to_reverb = sample_from_delay;
                valid_to_reverb = valid_from_delay;
            end
            default: begin
                sample_to_reverb = 16'h0;
                valid_to_reverb = 1'b0;
            end
        endcase

        case (filter_src)
            3'b000: begin
                sample_to_filter = sample_from_base;
                valid_to_filter = valid_from_base;
            end
            3'b010: begin
                sample_to_filter = sample_l_from_reverb;
                valid_to_filter = valid_from_reverb;
            end
            3'b011: begin
                sample_to_filter = sample_from_filter;
                valid_to_filter = valid_from_filter;
            end
            3'b100: begin
                sample_to_filter = sample_from_distortion;
                valid_to_filter = valid_from_distortion;
            end
            3'b101: begin
                sample_to_filter = sample_from_crush;
                valid_to_filter = valid_from_crush;
            end
            3'b001: begin
                sample_to_filter = sample_from_delay;
                valid_to_filter = valid_from_delay;
            end
            default: begin
                sample_to_filter = 16'h0;
                valid_to_filter = 1'b0;
            end
        endcase

        case (distortion_src)
            3'b000: begin
                sample_to_distortion = sample_from_base;
                valid_to_distortion = valid_from_base;
            end
            3'b010: begin
                sample_to_distortion = sample_l_from_reverb;
                valid_to_distortion = valid_from_reverb;
            end
            3'b011: begin
                sample_to_distortion = sample_from_filter;
                valid_to_distortion = valid_from_filter;
            end
            3'b100: begin
                sample_to_distortion = sample_from_distortion;
                valid_to_distortion = valid_from_distortion;
            end
            3'b101: begin
                sample_to_distortion = sample_from_crush;
                valid_to_distortion = valid_from_crush;
            end
            3'b001: begin
                sample_to_distortion = sample_from_delay;
                valid_to_distortion = valid_from_delay;
            end
            default: begin
                sample_to_distortion = 16'h0;
                valid_to_distortion = 1'b0;
            end
        endcase

        case (crush_src)
            3'b000: begin
                sample_to_crush = sample_from_base;
                valid_to_crush = valid_from_base;
            end
            3'b010: begin
                sample_to_crush = sample_l_from_reverb;
                valid_to_crush = valid_from_reverb;
            end
            3'b011: begin
                sample_to_crush = sample_from_filter;
                valid_to_crush = valid_from_filter;
            end
            3'b100: begin
                sample_to_crush = sample_from_distortion;
                valid_to_crush = valid_from_distortion;
            end
            3'b101: begin
                sample_to_crush = sample_from_crush;
                valid_to_crush = valid_from_crush;
            end
            3'b001: begin
                sample_to_crush = sample_from_delay;
                valid_to_crush = valid_from_delay;
            end
            default: begin
                sample_to_crush = 16'h0;
                valid_to_crush = 1'b0;
            end
        endcase

        case (delay_src)
            3'b000: begin
                sample_to_delay = sample_from_base;
                valid_to_delay = valid_from_base;
            end
            3'b010: begin
                sample_to_delay = sample_l_from_reverb;
                valid_to_delay = valid_from_reverb;
            end
            3'b011: begin
                sample_to_delay = sample_from_filter;
                valid_to_delay = valid_from_filter;
            end
            3'b100: begin
                sample_to_delay = sample_from_distortion;
                valid_to_delay = valid_from_distortion;
            end
            3'b101: begin
                sample_to_delay = sample_from_crush;
                valid_to_delay = valid_from_crush;
            end
            3'b001: begin
                sample_to_delay = sample_from_delay;
                valid_to_delay = valid_from_delay;
            end
            default: begin
                sample_to_delay = 16'h0;
                valid_to_delay = 1'b0;
            end
        endcase
    end

endmodule

`default_nettype wire

