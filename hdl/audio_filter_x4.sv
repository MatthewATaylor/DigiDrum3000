`timescale 1ns / 1ps
`default_nettype none

// 4-pole transistor ladder model
// See "The Art of VA Filter Design" by Vadim Zavalishin

module audio_filter_x4
  #(
    parameter SOFT_CLIP=1
  )
  (
    input wire clk,
    input wire rst,

    input wire    [9:0] pot_cutoff,
    input wire    [9:0] pot_quality,

    input wire   [15:0] sample_in,
    input wire          sample_in_valid,

    output logic [15:0] sample_out,
    output logic        sample_out_valid
  );

  // State indicators
  enum {IDLE, S_MAC, G_MULT, KS_MULT, TANH_DIV_INIT, TANH_DIV, LPF_LOOP} state;
  enum {V_MULT_PRE, V_MULT, U_SUM, S_STORE, LPF_OUT} lpf_loop_state;
  logic  [1:0] s_mult_iter;
  logic  [1:0] lpf_loop_iter;

  logic [30:0] mult_a;
  logic [15:0] mult_b;
  logic [41:0] mult_out;
  assign mult_out = $signed(mult_a) * $signed(mult_b);

  logic [15:0] x;
  logic [15:0] u;
  logic [15:0] s [3:0];
  logic [ 9:0] g;
  logic [29:0] g_pow;
  logic [40:0] S;
  logic [37:0] S_mult;
  logic [25:0] kS;
  logic [ 9:0] G;
  logic [26:0] v_lsh12;
  logic [28:0] u_lsh12;

  logic [29:0] uv_sum;
  assign uv_sum = $signed(u_lsh12) + $signed(v_lsh12);

  logic [15:0] next_u;
  assign next_u = $signed(u_lsh12) >>> 12;

  logic [19:0] u_sub;
  assign u_sub = $signed(x) - ($signed(kS) >>> 8);
  logic [15:0] u_clip;
  clipper #(
    .WIDTH_FULL(20),
    .WIDTH_CLIP(16),
    .RIGHT_SHIFT(0)
  ) u_clipper (
    .din(u_sub),
    .dout(u_clip)
  );

  logic        tanh_in_valid;
  logic [15:0] tanh_out;
  logic        tanh_out_valid;
  logic        tanh_out_valid_hold;
  tanh_approx tanh_fb (
    .clk(clk),
    .rst(rst),
    .din(u_clip),
    .din_valid(tanh_in_valid),
    .dout(tanh_out),
    .dout_valid(tanh_out_valid)
  );

  logic [21:0] G_dividend;
  logic [12:0] G_divisor;
  logic        G_div_in_valid;
  logic [21:0] G_quotient;      // Keep 10 LSBs
  logic        G_div_out_valid;
  logic        G_div_out_valid_hold;
  divider #(
    .WIDTH(22)
  ) G_div (
    .clk(clk),
    .rst(rst),
    .dividend(G_dividend),
    .divisor(G_divisor),
    .data_in_valid(G_div_in_valid),
    .quotient(G_quotient),
    .remainder(),
    .data_out_valid(G_div_out_valid),
    .busy()
  );

  always_ff @ (posedge clk) begin
    if (rst) begin
      sample_out <= 0;
      sample_out_valid <= 0;

      state <= IDLE;
      lpf_loop_state <= V_MULT_PRE;
      s_mult_iter <= 0;
      lpf_loop_iter <= 0;

      mult_a <= 0;
      mult_b <= 0;

      x <= 0;
      u <= 0;
      for (int i=0; i<4; i++) begin
        s[i] <= 0;
      end
      g <= 0;
      S <= 0;
      S_mult <= 0;
      kS <= 0;
      G <= 0;
      v_lsh12 <= 0;
      u_lsh12 <= 0;

      tanh_in_valid <= 0;
      tanh_out_valid_hold <= 0;

      G_dividend <= 0;
      G_divisor <= 0;
      G_div_in_valid <= 0;
      G_div_out_valid_hold <= 0;
       
      G_div_in_valid <= 0;
    end else begin
      case (state)
        IDLE: begin
          sample_out_valid <= 0;
          if (sample_in_valid) begin
            x <= sample_in;
            g <= pot_cutoff;
            g_pow <= pot_cutoff;
            S <= $signed({24'b0, s[3]} << 24);
            state <= S_MAC;
            s_mult_iter <= 0;
          end
        end

        // Cycle between S_MAC and G_MULT to mult/accum feedback term
        S_MAC: begin
          // From IDLE, G_MULT
          case (s_mult_iter)
            2'b00: begin
              mult_a <= $signed({12'b0, s[2]} << 12);
              mult_b <= g_pow;  // g
              state <= G_MULT;
            end
            2'b01: begin
              S <= $signed(S) + $signed(S_mult);
              g_pow <= mult_out;
              mult_a <= mult_out;  // g**2
              mult_b <= $signed(s[1]);
              state <= G_MULT;
            end
            2'b10: begin
              S <= $signed(S) + $signed(S_mult);
              mult_a <= mult_out;  // g**3
              mult_b <= $signed(s[0][15:12]);
              state <= G_MULT;
            end
            2'b11: begin
              S <= $signed(S) + $signed(S_mult);
              state <= KS_MULT;
            end
          endcase
          s_mult_iter <= s_mult_iter + 1;
        end
        G_MULT: begin
          // From S_MAC
          S_mult <= mult_out;
          mult_a <= g_pow;
          mult_b <= g;
          state <= S_MAC;
        end

        KS_MULT: begin
          // From S_MAC
          mult_a <= $signed(S[40:25]);
          mult_b <= pot_quality;
          state <= TANH_DIV_INIT;
        end

        TANH_DIV_INIT: begin
          // From KS_MULT
          kS <= mult_out;
          G_dividend <= {12'b0, g} << 12;
          G_divisor <= 13'd4096 + g;
          G_div_in_valid <= 1;
          tanh_in_valid <= 1;
          state <= TANH_DIV;
        end

        TANH_DIV: begin
          // From TANH_DIV_INIT
          tanh_in_valid <= 0;
          G_div_in_valid <= 0;

          if (G_div_out_valid) begin
            G <= G_quotient[9:0];
          end

          // tanh has the greater latency
          if (tanh_out_valid) begin
            if (SOFT_CLIP == 1) begin
              u <= tanh_out;
            end else begin
              u <= u_clip;
            end
            state <= LPF_LOOP;
            lpf_loop_state <= V_MULT_PRE;
            lpf_loop_iter <= 0;
          end
        end

        // Calculate output of each 1-pole LPF
        LPF_LOOP: begin
          // From TANH_DIV
          case (lpf_loop_state)
            V_MULT_PRE: begin
              mult_a <= $signed(u) - $signed(s[lpf_loop_iter]);
              mult_b <= G;
              lpf_loop_state <= V_MULT;
            end

            V_MULT: begin
              v_lsh12 <= mult_out;
              lpf_loop_state <= U_SUM;
            end

            U_SUM: begin
              u_lsh12 <=
                $signed(v_lsh12) +
                $signed({12'b0, s[lpf_loop_iter]} << 12);
              lpf_loop_state <= S_STORE;
            end

            S_STORE: begin
              s[lpf_loop_iter] <= $signed(uv_sum) >>> 12;
              lpf_loop_state <= LPF_OUT;
            end

            LPF_OUT: begin
              if (lpf_loop_iter == 3) begin
                sample_out <= next_u;
                sample_out_valid <= 1;
                state <= IDLE;
              end else begin
                u <= next_u;
                lpf_loop_iter <= lpf_loop_iter + 1;
                lpf_loop_state <= V_MULT_PRE;
              end
            end
          endcase
        end
      endcase
    end
  end
endmodule

`default_nettype wire

