`timescale 1ns / 1ps  //
`default_nettype none

module dither_gen #(
    parameter WIDTH
) (
    input  wire  [  WIDTH-1:0] a,
    input  wire  [  WIDTH-1:0] b,
    output logic [2*WIDTH-1:0] out
);
  logic [2*WIDTH-1:0] reverse_out;

  bit_interleave #(WIDTH) my_interleave (
      .a  (a ^ b),
      .b  (b),
      .out(reverse_out)
  );

  bit_reverse #(2 * WIDTH) my_reverse (
      .in (reverse_out),
      .out(out)
  );
endmodule  // dither_gen

module bit_interleave #(
    parameter WIDTH
) (
    input  wire  [  WIDTH-1:0] a,
    input  wire  [  WIDTH-1:0] b,
    output logic [2*WIDTH-1:0] out
);
  always_comb begin
    for (integer i = 0; i < WIDTH; i += 1) begin
      out[2*i]   = a[i];
      out[2*i+1] = b[i];
    end
  end
endmodule  // bit_interleave

module bit_reverse #(
    parameter WIDTH
) (
    input  wire  [WIDTH-1:0] in,
    output logic [WIDTH-1:0] out
);
  always_comb begin
    for (integer i = 0; i < WIDTH; i += 1) begin
      out[i] = in[WIDTH-1-i];
    end
  end
endmodule


`default_nettype wire
