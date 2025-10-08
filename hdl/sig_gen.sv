`default_nettype none

// delays by 3 (or more at very high angular frequencies) samples
// to reduce cycle delay
module sin_gen (
    input wire clk,
    input wire rst,
    input wire [29:0] delta_angle,  // 0 to 1.9999...
    input wire get_next_sample,
    output logic [15:0] current_sample
);
  logic        is_negative;
  logic        last_is_negative;
  logic [30:0] current_angle;
  logic [31:0] next_angle;
  logic        next_angle_overflow;
  logic        next_angle_ready;
  logic [31:0] pi;
  logic [15:0] next_sample;

  logic [15:0] cordic_out;
  logic        cordic_busy;
  logic        cordic_out_valid;

  CORDIC_sin cordic (
      .clk(clk),
      .rst(rst),
      .angle_in(current_angle[30:7]),
      .input_valid(get_next_sample && !cordic_busy),
      .out(cordic_out),
      .out_valid(cordic_out_valid),
      .busy(cordic_busy)
  );

  assign next_angle_overflow = ((next_angle > {1'b0, pi[31:1]}) && next_angle[31] == 0);

  always_ff @(posedge clk) begin
    if (rst) begin
      current_angle <= 32'b0;
      next_angle <= 32'b0;
      next_angle_ready <= 1'b0;
      current_sample <= 16'b0;
      next_sample <= 16'b0;
      is_negative <= 1'b0;
      last_is_negative <= 1'b0;
      pi <= 32'h6487ED51;
    end else begin
      if (get_next_sample) begin
        next_angle <= {current_angle[30], current_angle} + {2'b0, delta_angle};
        next_angle_ready <= 1'b1;
        current_sample <= last_is_negative ? -next_sample : next_sample;
      end else begin
        next_angle_ready <= 1'b0;
      end

      if (next_angle_ready) begin
        current_angle <= next_angle_overflow ? next_angle - pi : next_angle;
        is_negative <= next_angle_overflow ? !is_negative : is_negative;
        last_is_negative <= is_negative;
      end

      if (cordic_out_valid) begin
        next_sample <= cordic_out;
      end
    end
  end

endmodule  // sin_gen

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
  // "signed" for arithmetic shift
  logic signed [23:0] x;
  logic signed [23:0] y;
  logic        [23:0] angle_error;
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
      // INFO: most likely to cause timing violation (runtime shift + add)
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
