`timescale 1ns / 1ps  //
`default_nettype none

// lossless version of following:
// Y =   r/2 + g/4 + b/2
// Co =  r         - b
// Cg = -r/2 + g   - b/2
module RGB_to_YCoCg_R (
    input wire clk,
    input wire rst,

    input wire [7:0] r,
    input wire [7:0] g,
    input wire [7:0] b,
    output logic [7:0] Y,
    output logic signed [8:0] Co,
    output logic signed [8:0] Cg
);
  logic [8:0] temp;

  logic [7:0] next_Y;
  logic signed [8:0] next_Co;
  logic signed [8:0] next_Cg;

  always_comb begin
    next_Co = {1'b0, r} - {1'b0, b};
    temp = {1'b0, b} + $signed(next_Co >>> 1);
    next_Cg = {1'b0, g} - temp;
    next_Y = temp + $signed(next_Cg >>> 1);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      Y  <= 0;
      Co <= 0;
      Cg <= 0;
    end else begin
      Y  <= next_Y;
      Co <= next_Co;
      Cg <= next_Cg;
    end
  end
endmodule

module YCoCg_R_to_RGB (
    input wire clk,
    input wire rst,

    input wire [7:0] Y,
    input wire signed [8:0] Co,
    input wire signed [8:0] Cg,
    output logic [7:0] r,
    output logic [7:0] g,
    output logic [7:0] b
);
  logic signed [8:0] temp;
  logic signed [9:0] r_unbounded;
  logic signed [9:0] g_unbounded;
  logic signed [9:0] b_unbounded;

  always_comb begin
    temp = Y + $signed(Cg >>> 1);
    g_unbounded = Cg + temp;
    b_unbounded = temp - $signed(Co >>> 1);
    r_unbounded = b_unbounded + Co;

  end

  always_ff @(posedge clk) begin
    if (rst) begin
      r <= 0;
      g <= 0;
      b <= 0;
    end else begin
      r <= r_unbounded[9] ? 0 : r_unbounded[8] ? 8'hFF : r_unbounded[7:0];
      g <= g_unbounded[9] ? 0 : g_unbounded[8] ? 8'hFF : g_unbounded[7:0];
      b <= b_unbounded[9] ? 0 : b_unbounded[8] ? 8'hFF : b_unbounded[7:0];
    end
  end
endmodule

`default_nettype wire
