`timescale 1ns / 1ps
`default_nettype none

// Allow sample rate to span 4 full octaves.
//  10 bits provides approx 256 pot steps per octave
//  = approx 5 cents per LSB of 'pitch'
// 
// This translates to 9088 cycles/sample to 568 cycles/sample
//  = 11 kHz to 176 kHz sample rate
// 
// Compute 9088 / 2**(pitch/256)
//  9088 / 2**floor(pitch/256) has the right value every 256 pitch steps.
//  Do linear interpolation between these points.

module pitch_to_sample_period
    (
        input  wire         clk,
        input  wire         rst,
        input  wire  [9:0]  pitch,         // From 10-bit ADC
        output logic [13:0] sample_period  // cycles/sample
    );

    logic [9:0]  pitch_reg [1:0];

    logic [20:0] pitch_lerp_1;
    
    logic [10:0] pitch_plus_128;
    logic [7:0]  pitch_lerp_2_mod;
    logic [7:0]  pitch_lerp_2_abs;
    logic [20:0] pitch_lerp_2;

    logic [10:0] pitch_plus_64;
    logic [6:0]  pitch_lerp_3_mod;
    logic [6:0]  pitch_lerp_3_abs;
    logic [20:0] pitch_lerp_3;

    always_comb begin
        pitch_lerp_1 = {13'b0, pitch_reg[0][7:0]} * 21'd4544;

        pitch_plus_128 = {1'b0, pitch_reg[0]} + 10'd128;
        pitch_lerp_2_mod = pitch_plus_128[7:0] - 8'd128;
        pitch_lerp_2_abs = pitch_lerp_2_mod[7] ? 
            (~pitch_lerp_2_mod + 1) : 
            pitch_lerp_2_mod;
        pitch_lerp_2 = {13'b0, pitch_lerp_2_abs} * 21'd826;

        pitch_plus_64 = {1'b0, pitch_reg[0]} + 10'd64;
        pitch_lerp_3_mod = pitch_plus_64[6:0] - 8'd64;
        pitch_lerp_3_abs = pitch_lerp_3_mod[6] ? 
            (~pitch_lerp_3_mod + 1) : 
            pitch_lerp_3_mod;
        pitch_lerp_3 = {14'b0, pitch_lerp_3_abs} * 21'd367;
    end


    // 3 clock cycles

    logic [20:0] pitch_lerp_1_reg;
    logic [20:0] pitch_lerp_2_reg;
    logic [20:0] pitch_lerp_3_reg;

    always_ff @ (posedge clk) begin
        if (rst) begin
            pitch_reg[0] <= 0;
            pitch_reg[1] <= 0;
            
            pitch_lerp_1_reg <= 0;
            pitch_lerp_2_reg <= 0;
            pitch_lerp_3_reg <= 0;

            sample_period <= 2272;
        end else begin
            pitch_reg[0] <= pitch;
            pitch_reg[1] <= pitch_reg[0];

            pitch_lerp_1_reg <= pitch_lerp_1;
            pitch_lerp_2_reg <= pitch_lerp_2;
            pitch_lerp_3_reg <= pitch_lerp_3;

            sample_period <=
                (
                    14'd9088 -
                    (
                        (
                            pitch_lerp_1_reg +
                            pitch_lerp_2_reg +
                            pitch_lerp_3_reg
                        ) >> 8
                    )
                ) >> (pitch_reg[1] >> 8);
        end
    end

endmodule

`default_nettype wire
