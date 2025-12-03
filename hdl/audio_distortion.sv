`timescale 1ns / 1ps
`default_nettype none

module audio_distortion
    (
        input wire clk,
        input wire rst,

        input wire [9:0] pot_drive,

        input wire [15:0] sample_in,
        input wire        sample_in_valid,

        output logic [15:0] sample_out,
        output logic        sample_out_valid
    );

    enum {IDLE, SAMPLE_CLIP} state;

    logic [25:0] sample_scaled;
    logic [15:0] sample_clipped;
    
    logic [15:0] tanh_in;
    logic        tanh_in_valid;

    always_ff @ (posedge clk) begin
        if (rst) begin
            state <= IDLE;
            sample_scaled <= 0;
            tanh_in <= 0;
            tanh_in_valid <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tanh_in_valid <= 0;
                    if (sample_in_valid) begin
                        sample_scaled <=
                            $signed(sample_in) *
                            $signed({1'b0, pot_drive});
                        state <= SAMPLE_CLIP;
                    end
                end

                SAMPLE_CLIP: begin
                    tanh_in <= sample_clipped;
                    tanh_in_valid <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

    clipper #(
        .WIDTH_FULL(26),
        .WIDTH_CLIP(16),
        .RIGHT_SHIFT(7)  // Max input gain of 2**(10-7) = 8
    ) driven_input_clipper (
        .din(sample_scaled),
        .dout(sample_clipped)
    );

    tanh_approx tanh_i (
        .clk(clk),
        .rst(rst),
        .din(tanh_in),
        .din_valid(tanh_in_valid),
        .dout(sample_out),
        .dout_valid(sample_out_valid)
    );

endmodule

`default_nettype wire

