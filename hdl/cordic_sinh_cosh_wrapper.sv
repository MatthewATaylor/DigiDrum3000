`timescale 1ns / 1ps
`default_nettype none

module cordic_sinh_cosh_wrapper
    (
        input  wire         clk,
        input  wire         rst,

        input  wire         phase_valid,
        input  wire  [15:0] phase,  // sign, 2 int, 13 frac [-pi/4, pi/4]

        output logic        dout_valid,
        output logic [15:0] sinh,   // sign, 1 int, 14 frac [-2, 2)
        output logic [15:0] cosh    // sign, 1 int, 14 frac [1, 2)
    );

    logic [31:0] dout;
    assign sinh = dout[31:16];
    assign cosh = dout[15: 0];

    cordic_sinh_cosh cordic_sinh_cosh_i (
        .aclk(clk),
        .s_axis_phase_tvalid(phase_valid),
        .s_axis_phase_tdata(phase),
        .m_axis_dout_tvalid(dout_valid),
        .m_axis_dout_tdata(dout)
    );

endmodule

`default_nettype wire

