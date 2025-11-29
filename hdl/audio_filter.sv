`timescale 1ns / 1ps
`default_nettype none

// 4-pole transistor ladder model
// See "The Art of VA Filter Design" by Vadim Zavalishin
module audio_filter
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


  localparam SAMPLE_WIDTH = 16;
  localparam POT_WIDTH    = 10;
  localparam K_SHIFT      = 8;  // k should be [0, 4)
  localparam U0_DIV_WIDTH = SAMPLE_WIDTH + 5*POT_WIDTH - K_SHIFT + 3;


  // State indicators
  enum {IDLE, GS, DIV, LOOP} state;
  enum {V_DIFF, V_MULT, MAIN} loop_state;
  logic       gs_mult;
  logic [1:0] gs_iter;
  logic       calc_v;
  logic [1:0] loop_iter;


  // Registers for sequential logic
  logic [SAMPLE_WIDTH + 4*POT_WIDTH - 1:0] u;           // Input for each 1-pole LPF
  logic [SAMPLE_WIDTH + 3*POT_WIDTH - 1:0] s [3:0];     // 1-pole LPF states 
  logic [SAMPLE_WIDTH + 4*POT_WIDTH    :0] v;           // Intermediate calculation
  logic [                 POT_WIDTH - 1:0] g_x1024;     // Cutoff parameter 
  logic [               4*POT_WIDTH - 1:0] g_x1024_pow; // Cumulative product of g_x1024  
  logic [SAMPLE_WIDTH + 3*POT_WIDTH + 1:0] S_x1024_4_acc;
  logic [SAMPLE_WIDTH + 3*POT_WIDTH - 1:0] S_x1024_4_mult;

  logic [               5*POT_WIDTH           - 1:0] kG_mult;
  logic [SAMPLE_WIDTH + 5*POT_WIDTH - K_SHIFT + 1:0] kS_mult;

  logic                                    u0_dividend_sign;
  logic                                    u0_valid_hold;
  logic                                    G_x1024_valid_hold;
  logic [                 POT_WIDTH - 1:0] G_x1024;
  logic [SAMPLE_WIDTH + 3*POT_WIDTH    :0] u_s_diff;


  logic [SAMPLE_WIDTH + 4*POT_WIDTH - 1:0] x_shifted;
  assign x_shifted = $signed(sample_in) <<< (4*POT_WIDTH);
 
  // Orig. <<< POT_WIDTH
  logic [SAMPLE_WIDTH + 4*POT_WIDTH - K_SHIFT + 1:0] S_x1024_4;
  assign S_x1024_4 = $signed(S_x1024_4_acc) <<< (POT_WIDTH-K_SHIFT);

  // Scale G,S by feedback gain
  logic [5*POT_WIDTH - K_SHIFT - 1:0] kG;
  assign kG = kG_mult >> K_SHIFT;
  logic [SAMPLE_WIDTH + 5*POT_WIDTH - K_SHIFT + 1:0] kS;
  assign kS = $signed(kS_mult);  // Orig. >>> K_SHIFT

  // Some bits are truncated for this calculation.
  // Assume width of next_u can be same as u
  //  (clipped feedback)
  logic [SAMPLE_WIDTH + 4*POT_WIDTH - 1:0] next_u;
  assign next_u =
    $signed(v) +
    $signed({{POT_WIDTH{1'b0}}, s[loop_iter]} << POT_WIDTH);

  logic [SAMPLE_WIDTH + 4*POT_WIDTH + 1:0] next_s_sum;
  assign next_s_sum = $signed(next_u) + $signed(v);
  
  // Some bits are truncated for this calculation.
  // Assume width of next_s can be same as s
  //  (clipped feedback)
  logic [SAMPLE_WIDTH + 3*POT_WIDTH - 1:0] next_s;
  assign next_s = $signed(next_s_sum) >>> POT_WIDTH;

  // u0 is the input to the series combination of 1-pole LPFs
  // Take absolute value before dividing
  logic [U0_DIV_WIDTH - 1:0] u0_dividend_abs;
  logic [U0_DIV_WIDTH - 1:0] u0_dividend;
  always_comb begin
    u0_dividend = $signed(x_shifted) - $signed(kS);
    if (u0_dividend[U0_DIV_WIDTH - 1]) begin
      u0_dividend_abs = ~u0_dividend + 1;
    end else begin
      u0_dividend_abs = u0_dividend;
    end
  end


  logic div_in_valid;

  logic [U0_DIV_WIDTH - 1:0] u0;
  logic                      u0_valid;
  logic [U0_DIV_WIDTH - 1:0] u0_divisor;
  assign u0_divisor = {1'b1, {4*POT_WIDTH{1'b0}}} + kG;
  divider #(
    .WIDTH(U0_DIV_WIDTH)
  ) u0_div (
    .clk(clk),
    .rst(rst),
    .dividend(u0_dividend_abs),  // abs
    .divisor(u0_divisor),        // pos
    .data_in_valid(div_in_valid),
    .quotient(u0),
    .remainder(),
    .data_out_valid(u0_valid),
    .busy()
  );

  logic [2*POT_WIDTH:0] G_x1024_quotient;
  logic                 G_x1024_valid;
  logic [2*POT_WIDTH:0] G_dividend;
  assign G_dividend = {{POT_WIDTH{1'b0}}, g_x1024} << POT_WIDTH;
  logic [2*POT_WIDTH:0] G_divisor;
  assign G_divisor = 11'd1024 + g_x1024;
  divider #(
    .WIDTH(2*POT_WIDTH)
  ) G_div (
    .clk(clk),
    .rst(rst),
    .dividend(G_dividend),  // pos
    .divisor(G_divisor),    // pos
    .data_in_valid(div_in_valid),
    .quotient(G_x1024_quotient),
    .remainder(),
    .data_out_valid(G_x1024_valid),
    .busy()
  );


  always_ff @ (posedge clk) begin
    if (rst) begin
      sample_out <= 0;
      sample_out_valid <= 0;

      u <= 0;
      
      for (int i=0; i<4; i++) begin
        s[i] <= 0;
      end
       
      div_in_valid <= 0;

      u0_dividend_sign <= 0;
      u0_valid_hold <= 0;

      G_x1024_valid_hold <= 0;
      G_x1024 <= 0;

      g_x1024 <= 0;
      g_x1024_pow <= 0;
      S_x1024_4_mult <= 0;
      S_x1024_4_acc <= 0;
      kG_mult <= 0;
      kS_mult <= 0;
      u_s_diff <= 0;

      gs_iter <= 0;
      calc_v <= 1;
      loop_iter <= 0;
      loop_state <= V_DIFF;
      state <= IDLE;
    end else begin
      case (state)
        IDLE: begin
          // Possible improvements:
          //  Convert linear pot_cutoff to exponential
          //  Perform prewarp on g_x1024
          g_x1024 <= pot_cutoff;
          g_x1024_pow <= pot_cutoff;

          S_x1024_4_acc <= $signed(s[3]);

          sample_out_valid <= 0;
          if (sample_in_valid) begin
            state <= GS;
            gs_iter <= 0;
            gs_mult <= 1;
          end
        end
        
        GS: begin
          // Compute values needed before the divide
          // G: Overall gain of feedback loop
          // S: Overall offset of feedback loop
          if (gs_iter == 3) begin
            kG_mult <= pot_quality * g_x1024_pow;
            kS_mult <=
              $signed({1'b0, pot_quality}) *
              $signed(S_x1024_4);

            div_in_valid <= 1;
            state <= DIV;
          end else begin
            if (gs_mult) begin
              g_x1024_pow <= g_x1024_pow * g_x1024;
              case (gs_iter)
                2'b00: begin
                  S_x1024_4_mult <=
                    $signed(s[2][SAMPLE_WIDTH + 3*POT_WIDTH - 1:0]) *
                    $signed({1'b0, g_x1024_pow[POT_WIDTH - 1:0]});
                end

                2'b01: begin
                  S_x1024_4_mult <=
                    $signed(s[1][SAMPLE_WIDTH + 2*POT_WIDTH - 1:0]) *
                    $signed({1'b0, g_x1024_pow[2*POT_WIDTH - 1:0]});
                end

                2'b10: begin
                  S_x1024_4_mult <=
                    $signed(s[0][SAMPLE_WIDTH - 1:0]) *
                    $signed({1'b0, g_x1024_pow[3*POT_WIDTH - 1:0]});
                end
              endcase
            end else begin
              S_x1024_4_acc <=
                $signed(S_x1024_4_acc) +
                $signed(S_x1024_4_mult);
              gs_iter <= gs_iter + 1;
            end
            gs_mult <= !gs_mult;
          end
        end

        DIV: begin
          div_in_valid <= 0;
          u0_dividend_sign <= u0_dividend[U0_DIV_WIDTH - 1];
          if ((u0_valid || u0_valid_hold) &&
            (G_x1024_valid || G_x1024_valid_hold)) begin
            u0_valid_hold <= 0;
            G_x1024_valid_hold <= 0;

            // Clip and apply sign
            // Possible improvement: soft clipping
            if (u0_dividend_sign) begin
              if (u0[U0_DIV_WIDTH - 1:SAMPLE_WIDTH - 1] > 0) begin
                u <= {{4*POT_WIDTH{1'b1}}, 16'h8000};
              end else begin
                u <= ~u0[SAMPLE_WIDTH + 4*POT_WIDTH - 1:0] + 1;
              end
            end else begin
              if (u0[U0_DIV_WIDTH - 1:SAMPLE_WIDTH - 1] > 0) begin
                u <= {{4*POT_WIDTH{1'b0}}, 16'h7FFF};
              end else begin
                u <= u0[SAMPLE_WIDTH + 4*POT_WIDTH - 1:0];
              end
            end

            G_x1024 <= G_x1024_quotient[POT_WIDTH - 1:0];

            state <= LOOP;
            loop_state <= V_DIFF;
            loop_iter <= 0;
          end else begin
            if (u0_valid) begin
              u0_valid_hold <= 1;
            end
            if (G_x1024_valid) begin
              G_x1024_valid_hold <= 1;
            end
          end
        end

        LOOP: begin
          // Calculate output of each 1-pole LPF
          case (loop_state)
            V_DIFF: begin
              u_s_diff <=
                $signed(u[SAMPLE_WIDTH + 3*POT_WIDTH - 1:0]) -
                $signed(s[loop_iter]);
              loop_state <= V_MULT;
            end

            V_MULT: begin
              v <=
                $signed({1'b0, G_x1024}) *
                $signed(u_s_diff);
              loop_state <= MAIN;
            end

            MAIN: begin
              if (loop_iter == 3) begin
                sample_out <= $signed(next_u) >>> (4*POT_WIDTH);
                s[loop_iter] <= next_s;
                
                sample_out_valid <= 1;
                state <= IDLE;
              end else begin
                u <= next_u;
                s[loop_iter] <= next_s;
                loop_iter <= loop_iter + 1;
                loop_state <= V_DIFF;
              end
            end
          endcase
        end
      endcase
    end
  end
endmodule

`default_nettype wire

