`default_nettype none

module sin_gen (
    input wire clk,
    input wire rst,
    input wire signed [30:0] delta_angle,  // -2 to  1.9999...
    input wire get_next_sample,
    output wire current_sample
);

endmodule

module CORDIC_sin (
    input  wire         clk,
    input  wire         rst,
    input  wire  [23:0] angle_in,
    input  wire         input_valid,
    output logic [15:0] out,
    output logic        out_valid,
    output logic        busy
);
  // 32 bit values stored as 2's compliment fixed-point numbers between -2 and 1.999...
  logic        [23:0] arc_tan_table  [7:0];
  logic        [23:0] arc_tan_approx;
  logic signed [23:0] x;
  logic signed [23:0] y;
  logic signed [23:0] angle_error;
  logic        [ 4:0] i;

  logic        [23:0] arc_tan;
  logic               clk_wise;

  assign out = (y[22:6] + 17'h00001) >> 1;

  assign arc_tan = i < 8 ? arc_tan_table[i[2:0]] : arc_tan_approx;
  assign clk_wise = angle_error[23];  // angle < 0

  always_ff @(posedge clk) begin
    if (rst) begin
      i <= 5'b0;
      x <= 24'h26DD12;
      y <= 24'b0;
      angle_error <= 24'b0;
      busy <= 1'b0;
      out_valid <= 1'b0;
      arc_tan_approx <= 24'h400000;
      arc_tan_table[0] <= 24'h3243F7;
      arc_tan_table[1] <= 24'h1DAC67;
      arc_tan_table[2] <= 24'h0FADBB;
      arc_tan_table[3] <= 24'h07F56F;
      arc_tan_table[4] <= 24'h03FEAB;
      arc_tan_table[5] <= 24'h01FFD5;
      arc_tan_table[6] <= 24'h00FFFB;
      arc_tan_table[7] <= 24'h007FFF;

    end else if (busy) begin
      i <= i + 1;
      // INFO: most likely to cause timing violation
      x <= clk_wise ? x + (y >>> i) : x - (y >>> i);
      y <= clk_wise ? y - (x >>> i) : y + (x >>> i);
      angle_error <= angle_error + (clk_wise ? arc_tan : -arc_tan);
      busy <= i < 19;
      out_valid <= i == 19;
      arc_tan_approx <= {1'b0, arc_tan_approx[23:1]};

    end else if (input_valid) begin
      i <= 5'b0;
      x <= 24'h26DD12;
      y <= 24'b0;
      angle_error <= angle_in;
      busy <= 1'b1;
      out_valid <= 1'b0;
      arc_tan_approx <= 24'h400000;

    end else begin  // idle state
      i <= 5'bXXXXX;
      x <= 24'hXXXXXX;
      y <= 24'hXXXXXX;
      angle_error <= 24'hXXXXXX;
      busy <= 1'b0;
      out_valid <= 1'b0;
      arc_tan_approx <= 24'hXXXXXX;
    end
  end

endmodule  //CORDIC_sin

`default_nettype wire
