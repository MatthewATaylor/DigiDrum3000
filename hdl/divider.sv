`timescale 1ns / 1ps  //
`default_nettype none

module divider #(
    parameter WIDTH = 32
) (
    input wire clk,
    input wire rst,
    input wire [WIDTH-1:0] dividend,
    input wire [WIDTH-1:0] divisor,
    input wire data_in_valid,
    output logic [WIDTH-1:0] quotient,
    output logic [WIDTH-1:0] remainder,
    output logic data_out_valid,
    output logic busy
);

  logic [$clog2(WIDTH)-1:0] i;
  logic                     divisor_fits;
  logic [      WIDTH*2-1:0] running_divisor;

  assign divisor_fits = running_divisor[WIDTH-1:0] <= remainder
                      && running_divisor[2*WIDTH-1:WIDTH] == 0;

  always_ff @(posedge clk) begin
    if (rst) begin
      quotient <= 0;
      remainder <= 0;
      data_out_valid <= 1'b0;
      busy <= 1'b0;
      i <= 0;
    end else if (busy) begin
      i <= i + 1;
      busy <= i != WIDTH - 1;
      data_out_valid <= i == WIDTH - 1;
      remainder <= divisor_fits ? remainder - running_divisor[WIDTH-1:0] : remainder;
      quotient <= {quotient[WIDTH-2:0], divisor_fits};
      running_divisor <= running_divisor >> 1;
    end else if (data_in_valid) begin
      i <= 0;
      busy <= 1'b1;
      data_out_valid <= 1'b0;
      remainder <= dividend;
      quotient <= 0;
      running_divisor <= divisor << WIDTH - 1;
    end else begin
      data_out_valid <= 1'b0;
      busy <= 1'b0;
    end
  end

endmodule  // divider

`default_nettype wire
