`timescale 1ns / 1ps
`default_nettype none

module audio_crush
    (
        input wire clk,
        input wire rst,

        input wire [9:0] pot_crush,

        input wire [15:0] sample_in,
        input wire        sample_in_valid,

        output logic [15:0] sample_out,
        output logic        sample_out_valid
    );

    logic [4:0]  sample_counter;
    logic [15:0] sample_mask;

    // Input gain and clip
    logic [22:0] sample_in_shifted;
    logic [15:0] sample_in_clipped;
    always_comb begin
        sample_in_shifted = $signed(sample_in) << pot_crush[9:7];
        if ($signed(sample_in_shifted[22:15]) < -8'sd1) begin
            sample_in_clipped = 16'h8000;
        end else if ($signed(sample_in_shifted[22:15]) > 8'sd0) begin
            sample_in_clipped = 16'h7FFF;
        end else begin
            sample_in_clipped = sample_in_shifted[15:0];
        end
    end

    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_out <= 0;
            sample_out_valid <= 0;
            sample_counter <= 0;
            sample_mask <= 0;
        end else begin
            sample_mask <= 16'hFFFF << {pot_crush[9:7], 1'b0};

            if (sample_in_valid) begin
                sample_out_valid <= 1;
                // Sample and hold downsampling (up to 32x)
                // No anti-aliasing because who needs that
                if (sample_counter >= pot_crush[9:5]) begin
                    sample_counter <= 0;
                    // Signed bit crush
                    if (sample_in[15]) begin
                        sample_out <= sample_in_clipped | ~sample_mask;
                    end else begin
                        sample_out <= sample_in_clipped & sample_mask;
                    end
                end else begin
                    sample_counter <= sample_counter + 1;
                end
            end else begin
                sample_out_valid <= 0;
            end
        end
    end

endmodule

`default_nettype wire
 
