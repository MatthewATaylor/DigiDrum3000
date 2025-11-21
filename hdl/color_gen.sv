`timescale 1ns / 1ps  //
`default_nettype none

module color_gen (
    input wire clk,
    input wire rst,
    input wire [10:0] h_count,
    input wire [9:0] v_count,
    input wire [9:0] pitch,

    output logic [23:0] color  // {r, g, b}
);
  localparam PI = 16'b0110_0100_1000_0111;
  logic [15:0] gradient_offset;

  logic [10:0] h_count_lookahead;
  logic [ 9:0] v_count_lookahead;
  logic [18:0] Co_angle_uncorrected;
  logic [18:0] Cg_angle_uncorrected;
  logic [15:0] Co_angle;  // fixed point [-4, 3.999...], should only be -pi to pi
  logic [15:0] Cg_angle;  // fixed point [-4, 3.999...], should only be -pi to pi
  logic [15:0] Co_sin;  //fixed point [-2, 1.9999] (but only will be -1.0 to 1.0)
  logic [15:0] Cg_sin;  //fixed point [-2, 1.9999] (but only will be -1.0 to 1.0)

  // use h_count / v_count 50 cycles 'in the future' to hide latency
  // (not exact, just moves cutoff into blanking region)
  assign h_count_lookahead = h_count >= 11'd1600 ? h_count - 11'd1600 : h_count + 11'd50;
  assign v_count_lookahead = h_count >= 11'd1600 ? (v_count == 10'd749 ? 0 : v_count + 1) : v_count;

  logic [15:0] Y;
  logic [15:0] Co;
  logic [15:0] Cg;

  logic [ 7:0] C_mult;

  assign Y = 16'h4000 + (pitch << 5);
  assign C_mult = 8'h3F + ((pitch[9] ? ~pitch[8:0] : pitch[8:0]) >> 4);

  logic [17:0] r_unscaled;
  logic [17:0] g_unscaled;
  logic [17:0] b_unscaled;

  logic [7:0] dither;

  dither_gen #(4) my_dither (
      .a(h_count[3:0]),
      .b(v_count[3:0]),
      .out(dither)
  );

  logic [ 7:0] r;
  logic [ 7:0] g;
  logic [ 7:0] b;

  assign color = {r, g, b};

  always_ff @(posedge clk) begin
    if (rst) begin
      Co_angle_uncorrected <= 0;
      Cg_angle_uncorrected <= 0;
      Co_angle <= 0;
      Cg_angle <= 0;
      gradient_offset <= 0;
      Co <= 0;
      Cg <= 0;
      r_unscaled <= 0;
      g_unscaled <= 0;
      b_unscaled <= 0;
      r <= 0;
      g <= 0;
      b <= 0;
    end else begin
      Co_angle_uncorrected <= $signed({3'h0, h_count_lookahead, 4'h0})
        + $signed({3'h0, v_count_lookahead, 4'h0}) + $signed(gradient_offset);
      Cg_angle_uncorrected <= $signed({4'h0, h_count_lookahead, 3'h0})
        - $signed({3'h0, v_count_lookahead, 4'h0}) + $signed(gradient_offset);

      if ($signed(Co_angle_uncorrected) > $signed({1'b0, PI})) begin
        Co_angle <= Co_angle_uncorrected - {PI, 1'b0};
      end else if ($signed(Co_angle_uncorrected) < -$signed({1'b0, PI})) begin
        Co_angle <= Co_angle_uncorrected + {PI, 1'b0};
      end else begin
        Co_angle <= Co_angle_uncorrected;
      end
      if ($signed(Cg_angle_uncorrected) > $signed({1'b0, PI})) begin
        Cg_angle <= Cg_angle_uncorrected - {PI, 1'b0};
      end else if ($signed(Cg_angle_uncorrected) < -$signed({1'b0, PI})) begin
        Cg_angle <= Cg_angle_uncorrected + {PI, 1'b0};
      end else begin
        Cg_angle <= Cg_angle_uncorrected;
      end

      if (h_count == 1280 && v_count == 720) begin
        gradient_offset <= $signed(gradient_offset) > $signed({1'b0, PI}) ?
            gradient_offset - {PI, 1'b0} + 18'h40 : gradient_offset + 18'h40;
      end

      if (Co_sin[15:14] == 2'b01) begin
        Co <= $signed({1'b0, C_mult}) * $signed({1'b0, 7'h7F});
      end else if ($signed(Co_sin) < $signed(16'hC000)) begin
        Co <= $signed({1'b0, C_mult}) * $signed(8'h81);
      end else begin
        Co <= $signed({1'b0, C_mult}) * $signed(Co_sin[14:7]);
      end
      if (Cg_sin[15:14] == 2'b01) begin
        Cg <= $signed({1'b0, C_mult}) * $signed({1'b0, 7'h7F});
      end else if ($signed(Cg_sin) < $signed(16'hC000)) begin
        Cg <= $signed({1'b0, C_mult}) * $signed(8'h81);
      end else begin
        Cg <= $signed({1'b0, C_mult}) * $signed(Cg_sin[14:7]);
      end

      r_unscaled <= $signed({1'b0, Y}) + $signed(Co) - $signed(Cg) + $signed(dither);
      g_unscaled <= $signed({1'b0, Y}) + $signed(Cg) + $signed(dither << 2);
      b_unscaled <= $signed({1'b0, Y}) - $signed(Co) - $signed(Cg) + $signed(dither);

      r <= r_unscaled[17] ? 0 : r_unscaled[16] ? 8'hFF : r_unscaled[15:8];
      g <= g_unscaled[17] ? 0 : g_unscaled[16] ? 8'hFF : g_unscaled[15:8];
      b <= b_unscaled[17] ? 0 : b_unscaled[16] ? 8'hFF : b_unscaled[15:8];
    end
  end

  logic [31:0] Co_sincos;
  logic [31:0] Cg_sincos;
  assign Co_sin = Co_sincos[31:16];
  assign Cg_sin = Cg_sincos[31:16];

  cordic_sincos_pipelined Co_sin_pipelined (
      .aclk               (clk),
      .s_axis_phase_tvalid(1'b1),
      .s_axis_phase_tdata (Co_angle),  // signed 16 bit (13 mantissa), should be in [-pi, pi]
      .m_axis_dout_tvalid (),
      .m_axis_dout_tdata  (Co_sincos)  // {sin, cos}, each signed 16 bit (14 mantissa)
  );

  cordic_sincos_pipelined Cg_sin_pipelined (
      .aclk               (clk),
      .s_axis_phase_tvalid(1'b1),
      .s_axis_phase_tdata (Cg_angle),  // signed 16 bit (13 mantissa), should be in [-pi, pi]
      .m_axis_dout_tvalid (),
      .m_axis_dout_tdata  (Cg_sincos)  // {sin, cos}, each signed 16 bit (14 mantissa)
  );
endmodule  // color_gen

`default_nettype wire
