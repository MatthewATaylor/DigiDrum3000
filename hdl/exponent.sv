`timescale 1ns / 1ps  //
`default_nettype none

module exponent (  // e to the power of negative input
    input wire clk,
    input wire rst,
    input wire in_valid,
    input wire [12:0] in_value,  // unsigned fixed point: ____.________
    output logic out_valid,
    output logic [7:0] out_value  // unsigned fixed point: 0.________
);

  logic [15:0] quotient;
  logic [15:0] remainder;
  logic        div_out_valid;

  divider #(
      .WIDTH(16)
  ) my_div (
      .clk(clk),
      .rst(rst),
      .dividend({in_value, 3'b0}),
      .divisor(16'h058B),  // roughly ln(2)*2^12
      .data_in_valid(in_valid),
      .quotient(quotient),
      .remainder(remainder),
      .data_out_valid(div_out_valid),
      .busy()
  );

  logic [ 5:0] shft;
  logic [11:0] cordic_input;  // signed fixed point ___._________
  logic        cordic_in_valid;

  always_ff @(posedge clk) begin
    if (div_out_valid) begin
      shft <= quotient[5:0];
      cordic_input <= {3'h0, remainder[10:2]};
      cordic_in_valid <= 1'b1;
    end else begin
      cordic_input <= 16'hXXXX;
      cordic_in_valid <= 0;
    end
  end


  logic [31:0] cordic_out;
  logic        cordic_out_valid;

  // actually 12-bit, has padding
  cordic_sinhcosh_folded_wrapper my_cordic (
      .aclk               (clk),                   // input  wire        aclk
      .s_axis_phase_tvalid(cordic_in_valid),       // input  wire        s_axis_phase_tvalid
      .s_axis_phase_tready(),                      // output wire        s_axis_phase_tready
      .s_axis_phase_tdata ({4'hX, cordic_input}),  // input  wire [15:0] s_axis_phase_tdata
      .m_axis_dout_tvalid (cordic_out_valid),      // output wire        m_axis_dout_tvalid
      .m_axis_dout_tdata  (cordic_out)             // output wire [31:0] m_axis_dout_tdata
  );

  logic [11:0] sinh;
  logic [11:0] cosh;
  assign sinh = cordic_out[27:16];  // signed fixed point __.__________
  assign cosh = cordic_out[11:0];  // unsigned fixed point __.__________

  always_ff @(posedge clk) begin
    if (cordic_out_valid) begin
      out_valid <= 1'b1;
      out_value <= |shft[5:3] ? 8'h0 : (cosh - sinh) >> (2 + shft[2:0]);
    end else begin
      out_valid <= 0;
    end
  end
endmodule

`default_nettype wire
