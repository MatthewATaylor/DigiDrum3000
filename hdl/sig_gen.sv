`default_nettype none

module CORDIC_sin (
    input  wire         clk,
    input  wire         rst,
    input  wire  [31:0] angle_in,
    input  wire         input_valid,
    output logic [15:0] out,
    output logic        out_valid,
    output logic        busy
);
  // 32 bit values stored as 2's compliment fixed-point numbers between -2 and 1.999...
  logic        [31:0] arc_tan_table  [9:0];
  logic        [31:0] arc_tan_approx;
  logic signed [31:0] x;
  logic signed [31:0] y;
  logic signed [31:0] angle_error;
  logic        [ 4:0] i;

  logic        [31:0] arc_tan;
  logic               clk_wise;

  assign out = (y[30:14] + 17'h00001) >> 1;

  assign arc_tan = i < 10 ? arc_tan_table[i] : arc_tan_approx;
  assign clk_wise = angle_error[31];  // angle < 0

  always_ff @(posedge clk) begin
    if (rst) begin
      i <= 5'b0;
      x <= 32'h26DD148C;
      y <= 32'b0;
      angle_error <= 32'b0;
      busy <= 1'b0;
      out_valid <= 1'b0;
      arc_tan_approx <= 32'h3FFFFFFF;
      arc_tan_table[0] <= 32'h3243F6A8;
      arc_tan_table[1] <= 32'h1DAC6705;
      arc_tan_table[2] <= 32'h0FADBAFC;
      arc_tan_table[3] <= 32'h07F56EA6;
      arc_tan_table[4] <= 32'h03FEAB76;
      arc_tan_table[5] <= 32'h01FFD55B;
      arc_tan_table[6] <= 32'h00FFFAAA;
      arc_tan_table[7] <= 32'h007FFF55;
      arc_tan_table[8] <= 32'h003FFFEA;
      arc_tan_table[9] <= 32'h001FFFFD;

    end else if (busy) begin
      i <= i + 1;
      // INFO: most likely to cause timing violation
      x <= clk_wise ? x + (y >>> i) : x - (y >>> i);
      y <= clk_wise ? y - (x >>> i) : y + (x >>> i);
      angle_error <= angle_error + (clk_wise ? arc_tan : -arc_tan);
      busy <= i < 19;
      out_valid <= i == 19;
      arc_tan_approx <= {1'b0, arc_tan_approx[31:1]};
      //arc_tan_table <= {arc_tan_table[0], arc_tan_table[9:1]};

    end else if (input_valid) begin
      i <= 5'b0;
      x <= 32'h26DD148C;
      y <= 32'b0;
      angle_error <= angle_in;
      busy <= 1'b1;
      out_valid <= 1'b0;
      arc_tan_approx <= 32'h3FFFFFFF;
      //arc_tan_table[0] <= 32'h3243F6A8;
      //arc_tan_table[1] <= 32'h1DAC6705;
      //arc_tan_table[2] <= 32'h0FADBAFC;
      //arc_tan_table[3] <= 32'h07F56EA6;
      //arc_tan_table[4] <= 32'h03FEAB76;
      //arc_tan_table[5] <= 32'h01FFD55B;
      //arc_tan_table[6] <= 32'h00FFFAAA;
      //arc_tan_table[7] <= 32'h007FFF55;
      //arc_tan_table[8] <= 32'h003FFFEA;
      //arc_tan_table[9] <= 32'h001FFFFD;

    end else begin  // idle state
      i <= 5'bXXXXX;
      x <= 32'hXXXXXXXX;
      y <= 32'hXXXXXXXX;
      angle_error <= 32'hXXXXXXXX;
      busy <= 1'b0;
      out_valid <= 1'b0;
      arc_tan_approx <= 32'hXXXXXXXX;
      // too lazy to make unspecified, chose what I thought wouldn't add latency
      //arc_tan_table <= {arc_tan_table[0], arc_tan_table[9:1]};
    end
  end

endmodule  //CORDIC_sin

`default_nettype wire
