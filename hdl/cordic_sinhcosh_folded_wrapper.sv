`timescale 1ns / 1ps  //
`default_nettype none

module cordic_sinhcosh_folded_wrapper (
    input  wire         aclk,
    input  wire         s_axis_phase_tvalid,
    output logic        s_axis_phase_tready,
    input  wire  [15:0] s_axis_phase_tdata,
    output logic        m_axis_dout_tvalid,
    output logic [31:0] m_axis_dout_tdata
);
  cordic_sinhcosh_folded my_cordic (
      .aclk               (aclk),                 // input  wire        aclk
      .s_axis_phase_tvalid(s_axis_phase_tvalid),  // input  wire        s_axis_phase_tvalid
      .s_axis_phase_tready(s_axis_phase_tready),  // output wire        s_axis_phase_tready
      .s_axis_phase_tdata (s_axis_phase_tdata),   // input  wire [15:0] s_axis_phase_tdata
      .m_axis_dout_tvalid (m_axis_dout_tvalid),   // output wire        m_axis_dout_tvalid
      .m_axis_dout_tdata  (m_axis_dout_tdata)     // output wire [31:0] m_axis_dout_tdata
  );

endmodule

`default_nettype wire
