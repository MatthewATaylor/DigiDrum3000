`timescale 1ns / 1ps  //
`default_nettype none

module video_filter (
    input wire clk,
    input wire rst,

    input wire [10:0] h_count_in,
    input wire [ 9:0] v_count_in,
    input wire        active_draw_in,
    input wire [23:0] pixel_in,

    input wire [9:0] cutoff,
    input wire [9:0] quality,

    output logic [10:0]      h_count_out,
    output logic [ 9:0]      v_count_out,
    output logic             active_draw_out,
    output logic [23:0]      pixel_out,
    output logic [ 4:0][7:0] gaussian_coeffs_view  // for vicoco access
);
  assign gaussian_coeffs_view = gaussian_coeffs;

  logic [1:0] dither;
  dither_gen #(
      .WIDTH(1)
  ) my_dither (
      .a  (h_count_in[0]),
      .b  (v_count_in[0]),
      .out(dither)
  );

  logic [10:0] last_h_count_in;
  logic [ 9:0] last_v_count_in;
  logic        last_active_draw_in;
  logic [17:0] pixel_in_6bit;

  logic [ 9:0] r_in_intermediate;
  logic [ 9:0] g_in_intermediate;
  logic [ 9:0] b_in_intermediate;

  always_comb begin
    r_in_intermediate = $signed({1'b0, pixel_in[23:16]}) + $signed(dither);
    g_in_intermediate = $signed({1'b0, pixel_in[15:8]}) + $signed(dither);
    b_in_intermediate = $signed({1'b0, pixel_in[7:0]}) + $signed(dither);

    r_in_intermediate = $signed(r_in_intermediate) < 10'sd0 ? 0 :
        r_in_intermediate > 10'h0FF ? 10'h0FF : r_in_intermediate;
    g_in_intermediate = $signed(g_in_intermediate) < 10'sd0 ? 0 :
        g_in_intermediate > 10'h0FF ? 10'h0FF : g_in_intermediate;
    b_in_intermediate = $signed(b_in_intermediate) < 10'sd0 ? 0 :
        b_in_intermediate > 10'h0FF ? 10'h0FF : b_in_intermediate;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      last_h_count_in <= 0;
      last_v_count_in <= 0;
      last_active_draw_in <= 0;
      pixel_in_6bit <= 0;
    end else begin
      last_h_count_in <= h_count_in;
      last_v_count_in <= v_count_in;
      last_active_draw_in <= active_draw_in;
      pixel_in_6bit <= {r_in_intermediate[7:2], g_in_intermediate[7:2], b_in_intermediate[7:2]};
    end
  end

  assign active_draw_out = h_count_out < 11'd1280 && v_count_out < 10'd720;

  logic [8:0][17:0] line_buffer_out;
  logic [10:0] buffer_h_count;
  logic [9:0] buffer_v_count;
  logic buffer_data_valid;

  line_buffer #(
      .KERNEL_SIZE(9)
  ) my_buffer (
      .clk(clk),
      .rst(rst),

      .h_count_in(last_h_count_in),
      .v_count_in(last_v_count_in),
      .pixel_data_in(pixel_in_6bit),

      .h_count_out(buffer_h_count),
      .v_count_out(buffer_v_count),
      .line_buffer_out(line_buffer_out)
  );

  logic [ 4:0][ 7:0] gaussian_coeffs;

  logic [ 8:0][13:0] r_vertical_gaussian_products;
  logic [ 8:0][13:0] g_vertical_gaussian_products;
  logic [ 8:0][13:0] b_vertical_gaussian_products;
  logic [ 2:0][13:0] r_vertical_gaussian_partial_sum;
  logic [ 2:0][13:0] g_vertical_gaussian_partial_sum;
  logic [ 2:0][13:0] b_vertical_gaussian_partial_sum;
  logic [13:0]       r_vertical_gaussian_sum;
  logic [13:0]       g_vertical_gaussian_sum;
  logic [13:0]       b_vertical_gaussian_sum;

  logic [ 8:0][ 7:0] r_horizontal_buffer;
  logic [ 8:0][ 7:0] g_horizontal_buffer;
  logic [ 8:0][ 7:0] b_horizontal_buffer;
  logic [ 8:0][15:0] r_horizontal_gaussian_products;
  logic [ 8:0][15:0] g_horizontal_gaussian_products;
  logic [ 8:0][15:0] b_horizontal_gaussian_products;
  logic [ 2:0][15:0] r_horizontal_gaussian_partial_sum;
  logic [ 2:0][15:0] g_horizontal_gaussian_partial_sum;
  logic [ 2:0][15:0] b_horizontal_gaussian_partial_sum;
  logic [15:0]       r_horizontal_gaussian_sum;
  logic [15:0]       g_horizontal_gaussian_sum;
  logic [15:0]       b_horizontal_gaussian_sum;

  //assign gaussian_coeffs[0] = 8'h48;
  //assign gaussian_coeffs[1] = 8'h38;
  //assign gaussian_coeffs[2] = 8'h1B;
  //assign gaussian_coeffs[3] = 8'h08;
  //assign gaussian_coeffs[4] = 8'h01;

  always_comb begin
    r_vertical_gaussian_sum   = 0;
    g_vertical_gaussian_sum   = 0;
    b_vertical_gaussian_sum   = 0;
    r_horizontal_gaussian_sum = 0;
    g_horizontal_gaussian_sum = 0;
    b_horizontal_gaussian_sum = 0;
    for (integer i = 0; i < 3; i += 1) begin
      r_vertical_gaussian_sum += r_vertical_gaussian_partial_sum[i];
      g_vertical_gaussian_sum += g_vertical_gaussian_partial_sum[i];
      b_vertical_gaussian_sum += b_vertical_gaussian_partial_sum[i];
      r_horizontal_gaussian_sum += r_horizontal_gaussian_partial_sum[i];
      g_horizontal_gaussian_sum += g_horizontal_gaussian_partial_sum[i];
      b_horizontal_gaussian_sum += b_horizontal_gaussian_partial_sum[i];
    end
    if (buffer_h_count >= 11'd1280) begin
      r_vertical_gaussian_sum = 0;
      g_vertical_gaussian_sum = 0;
      b_vertical_gaussian_sum = 0;
    end
  end

  logic [10:0] h_count_pipe[6:0];
  logic [ 9:0] v_count_pipe[6:0];

  always_ff @(posedge clk) begin
    if (rst) begin
      for (integer i = 0; i < 7; i += 1) begin
        h_count_pipe[i] <= 0;
        v_count_pipe[i] <= 0;
      end
      h_count_out <= 0;
      v_count_out <= 0;
    end else begin
      h_count_pipe[0] <= buffer_h_count;
      v_count_pipe[0] <= buffer_v_count;
      for (integer i = 0; i < 6; i += 1) begin
        h_count_pipe[i+1] <= h_count_pipe[i];
        v_count_pipe[i+1] <= v_count_pipe[i];
      end
      h_count_out <= h_count_pipe[6];
      v_count_out <= v_count_pipe[6];
    end
  end
  // tmp only exists because of iverilog bug (https://github.com/steveicarus/iverilog/issues/521)
  logic [17:0] tmp;
  always_ff @(posedge clk) begin
    integer coeff_i;
    for (integer i = 0; i < 9; i += 1) begin
      coeff_i = i < 5 ? 4 - i : i - 4;
      tmp = line_buffer_out[i];
      r_vertical_gaussian_products[i]   <= tmp[17:12] * gaussian_coeffs[coeff_i];
      g_vertical_gaussian_products[i]   <= tmp[11:6] * gaussian_coeffs[coeff_i];
      b_vertical_gaussian_products[i]   <= tmp[5:0] * gaussian_coeffs[coeff_i];

      r_horizontal_gaussian_products[i] <= r_horizontal_buffer[i] * gaussian_coeffs[coeff_i];
      g_horizontal_gaussian_products[i] <= g_horizontal_buffer[i] * gaussian_coeffs[coeff_i];
      b_horizontal_gaussian_products[i] <= b_horizontal_buffer[i] * gaussian_coeffs[coeff_i];
    end
    for (integer i = 0; i < 3; i += 1) begin
      r_vertical_gaussian_partial_sum[i]   <=   r_vertical_gaussian_products[3*i+0] +  r_vertical_gaussian_products[3*i+1] +   r_vertical_gaussian_products[3*i+2];
      g_vertical_gaussian_partial_sum[i]   <=   g_vertical_gaussian_products[3*i+0] +  g_vertical_gaussian_products[3*i+1] +   g_vertical_gaussian_products[3*i+2];
      b_vertical_gaussian_partial_sum[i]   <=   b_vertical_gaussian_products[3*i+0] +  b_vertical_gaussian_products[3*i+1] +   b_vertical_gaussian_products[3*i+2];
      r_horizontal_gaussian_partial_sum[i] <= r_horizontal_gaussian_products[3*i+0] +r_horizontal_gaussian_products[3*i+1] + r_horizontal_gaussian_products[3*i+2];
      g_horizontal_gaussian_partial_sum[i] <= g_horizontal_gaussian_products[3*i+0] +g_horizontal_gaussian_products[3*i+1] + g_horizontal_gaussian_products[3*i+2];
      b_horizontal_gaussian_partial_sum[i] <= b_horizontal_gaussian_products[3*i+0] +b_horizontal_gaussian_products[3*i+1] + b_horizontal_gaussian_products[3*i+2];
    end

    r_horizontal_buffer[0] <= r_vertical_gaussian_sum[13:6];
    g_horizontal_buffer[0] <= g_vertical_gaussian_sum[13:6];
    b_horizontal_buffer[0] <= b_vertical_gaussian_sum[13:6];
    pixel_out <= {
      r_horizontal_gaussian_sum[15:8],
      g_horizontal_gaussian_sum[15:8],
      b_horizontal_gaussian_sum[15:8]
    };

    for (integer i = 0; i < 8; i += 1) begin
      r_horizontal_buffer[i+1] <= r_horizontal_buffer[i];
      g_horizontal_buffer[i+1] <= g_horizontal_buffer[i];
      b_horizontal_buffer[i+1] <= b_horizontal_buffer[i];
    end
  end

  enum {
    USING_COEFFS,
    CALCULATING_EXPONENTS,
    SCALING_COEFFS
  } state;

  logic [11:0] sum;
  logic [2:0] coeff_pos;
  logic [10:0] exponent_mult;

  logic exp_in_valid;
  logic [12:0] exp_in_value;
  logic exp_out_valid;
  logic [7:0] exp_out_value;

  exponent my_exp (
      .clk(clk),
      .rst(rst),
      .in_valid(exp_in_valid),
      .in_value(exp_in_value),
      .out_valid(exp_out_valid),
      .out_value(exp_out_value)
  );

  logic [15:0] dividend;
  logic        div_in_valid;
  logic [15:0] quotient;
  logic        div_out_valid;
  logic        div_busy;

  divider #(
      .WIDTH(16)
  ) my_div (
      .clk(clk),
      .rst(rst),
      .dividend(dividend),
      .divisor({4'h0, sum}),
      .data_in_valid(div_in_valid),
      .quotient(quotient),
      .remainder(),
      .data_out_valid(div_out_valid),
      .busy(div_busy)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= USING_COEFFS;
    end else if (state == USING_COEFFS && h_count_out == 1280 && v_count_out == 720) begin
      state <= CALCULATING_EXPONENTS;
    end else if (state == CALCULATING_EXPONENTS && exp_out_valid && coeff_pos[2]) begin
      state <= SCALING_COEFFS;
    end else if (state == SCALING_COEFFS && div_out_valid && coeff_pos[2]) begin
      state <= USING_COEFFS;
    end
  end

  always_ff @(posedge clk) begin
    exponent_mult <= 11'h080 + (cutoff >> 1);
    unique case (state)
      USING_COEFFS: begin
        if (h_count_out == 1280 && v_count_out == 720) begin
          coeff_pos <= 3'b001;
          gaussian_coeffs[0] <= 8'hFF;
          sum <= 12'h100;
          exp_in_valid <= 1'b1;
          exp_in_value <= exponent_mult;
        end else begin
          exp_in_valid <= 0;
        end
      end
      CALCULATING_EXPONENTS: begin
        if (exp_out_valid) begin
          sum <= sum + (exp_out_value << 1);
          gaussian_coeffs[coeff_pos] <= exp_out_value;
          if (coeff_pos[2]) begin
            coeff_pos <= 3'b000;
          end else begin
            coeff_pos <= coeff_pos + 1;
            exp_in_valid <= 1'b1;
            exp_in_value <= ({4'h0, exponent_mult} * (coeff_pos + 1));
          end
        end else begin
          exp_in_valid <= 0;
        end

      end
      SCALING_COEFFS: begin
        if (div_out_valid) begin
          gaussian_coeffs[coeff_pos] <= quotient;
          coeff_pos <= coeff_pos + 1;
          div_in_valid <= 0;
        end else if (!div_busy && !div_in_valid) begin
          dividend <= {gaussian_coeffs[coeff_pos], 8'h00};
          div_in_valid <= 1'b1;
        end else begin
          div_in_valid <= 0;
        end
      end
    endcase
  end
endmodule  // video_filter

`default_nettype wire
