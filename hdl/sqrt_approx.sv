`timescale 1ns / 1ps  //
`default_nettype none

module sqrt_approx #(
    parameter WIDTH
) (
    input wire clk,
    input wire rst,
    input wire [WIDTH-1:0] d_in,
    output logic [(WIDTH+1)/2-1:0] d_out
);
  localparam CLZ_WIDTH = 1 << $clog2(WIDTH);
  localparam PAD_WIDTH = CLZ_WIDTH - WIDTH;

  logic [  $clog2(WIDTH):0] leading_zeros;
  logic [$clog2(WIDTH)-1:0] exp;
  assign exp = (WIDTH - leading_zeros) >> 1;

  count_leading_zeros #(CLZ_WIDTH) my_clz (
      .din ({d_in[WIDTH-1:1], 1'b1, {(PAD_WIDTH) {1'b0}}}),
      .dout(leading_zeros)
  );

  assign d_out = (({{(WIDTH) {1'b0}}, 1'b1} << exp) + (d_in >> exp)) >> 1;

endmodule  // sqrt_approx

module count_leading_zeros #(
    parameter WIDTH = 8  // pow of 2
) (
    input wire [WIDTH-1:0] din,
    output logic [$clog2(WIDTH):0] dout
);
  parameter OUT_WIDTH = $clog2(WIDTH) + 1;

  logic [(WIDTH/2)-1:0] lh_din;
  logic [(WIDTH/2)-1:0] rh_din;
  logic [$clog2(WIDTH)-1:0] lh_dout;
  logic [$clog2(WIDTH)-1:0] rh_dout;

  generate
    if (WIDTH == 2) begin
      assign dout = din[1] ? 2'b00 : din[0] ? 2'b01 : 2'b10;
    end else begin
      assign lh_din = din[WIDTH-1:WIDTH/2];
      assign rh_din = din[WIDTH/2-1:0];
      count_leading_zeros #(WIDTH / 2) lh_unset (
          .din (lh_din),
          .dout(lh_dout)
      );
      count_leading_zeros #(WIDTH / 2) rh_unset (
          .din (rh_din),
          .dout(rh_dout)
      );
      always_comb begin
        if (lh_dout[$clog2(WIDTH)-1] && rh_dout[$clog2(WIDTH)-1]) begin
          dout = {1'b1, {(OUT_WIDTH - 1) {1'b0}}};
        end else if (lh_dout[$clog2(WIDTH)-1]) begin
          dout = {2'b01, rh_dout[$clog2(WIDTH)-2:0]};
        end else begin
          dout = {2'b00, lh_dout[$clog2(WIDTH)-2:0]};
        end
      end
    end
  endgenerate
endmodule  //count_leading_zeros
