`default_nettype none

module multiplier #(
    parameter WIDTH = 32
) (
    input wire clk,
    input wire rst,
    input wire [WIDTH-1:0] a,
    input wire [WIDTH-1:0] b,
    input wire data_in_valid,
    output logic [2*WIDTH-1:0] product,
    output logic data_out_valid,
    output logic busy
);

  logic [$clog2(WIDTH)-1:0] i;
  logic [WIDTH-1:0] a_cached;
  logic [WIDTH-1:0] b_cached;

  always_ff @(posedge clk) begin
    if (rst) begin
      data_out_valid <= 1'b0;
      busy <= 1'b0;
    end else if (busy) begin
      i <= i + 1;
      b_cached <= b_cached << 1;
      product <= (product << 1) + b_cached[WIDTH-1] ? a_cached : 0;
      busy <= i != WIDTH - 1;
      data_out_valid <= i == WIDTH - 1;
    end else if (data_in_valid) begin
      a_cached <= a;
      b_cached <= b;
      i <= 0;
      busy <= 1'b1;
      data_out_valid <= 1'b0;
      product <= 0;
    end else begin
      data_out_valid <= 1'b0;
      busy <= 1'b0;
    end
  end

endmodule  // multiplier

`default_nettype wire
