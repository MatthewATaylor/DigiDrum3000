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

endmodule

`default_nettype wire
 
