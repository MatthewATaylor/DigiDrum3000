`timescale 1ns / 1ps
`default_nettype none

module audio_filter
    (
        input wire clk,
        input wire rst,

        input wire [9:0] pot_cutoff,
        input wire [9:0] pot_quality,

        input wire [15:0] sample_in,
        input wire        sample_in_valid,

        output logic [15:0] sample_out,
        output logic        sample_out_valid
    );

    enum {IDLE, DIV, LOOP} state;

    logic [55:0] x_shifted;

    // 1-pole LPF states
    logic [45:0] s [3:0];

    // Cutoff parameter
    logic  [9:0] g_x1024;
    
    logic [19:0] g_x1024_2;
    logic [29:0] g_x1024_3;
    logic [39:0] g_x1024_4;
    
    logic [49:0] S_x1024_4_mult;
    logic [59:0] S_x1024_4;

    logic [49:0] kG_mult;
    logic [41:0] kG;
    logic [70:0] kS_mult;
    logic [62:0] kS;

    logic [63:0] u0_dividend;
    logic [63:0] u0_dividend_abs;

    assign x_shifted = $signed(sample_in) << 40;

    // Possible improvements:
    //  Convert linear pot_cutoff to exponential
    //  Perform prewarp on g_x1024
    assign g_x1024 = pot_cutoff;

    assign g_x1024_2 = g_x1024   * g_x1024;
    assign g_x1024_3 = g_x1024_2 * g_x1024;
    assign g_x1024_4 = g_x1024_3 * g_x1024;

    assign S_x1024_4_mult =
        $signed(s[0][15:0]) * $signed({1'b0, g_x1024_3}) +
        $signed(s[1][25:0]) * $signed({1'b0, g_x1024_2}) +
        $signed(s[2][35:0]) * $signed({1'b0, g_x1024}) +
        $signed(s[3]);
    assign S_x1024_4 = $signed(S_x1024_4_mult) << 10;

    // Scale G,S by feedback gain
    assign kG_mult = pot_quality * g_x1024_4;
    assign kG = kG_mult >> 8;
    assign kS_mult =
        $signed({1'b0, pot_quality}) *
        $signed(S_x1024_4);
    assign kS = $signed(kS_mult) >>> 8;

    assign u0_dividend = $signed(x_shifted) - $signed(kS);
    always_comb begin
        if (u0_dividend[63]) begin
            u0_dividend_abs = ~u0_dividend + 1;
        end else begin
            u0_dividend_abs = u0_dividend;
        end
    end

    logic [63:0] u0;  // Only need 56 bits
    logic        u0_valid;
    divider #(
        .WIDTH(64)
    ) u0_div (
        .clk(clk),
        .rst(rst),
        .dividend(u0_dividend_abs),
        .divisor(41'h10000000000 + kG),     // pos
        .data_in_valid(sample_in_valid),
        .quotient(u0),
        .remainder(),
        .data_out_valid(u0_valid),
        .busy()
    );

    logic [20:0] G_x1024_quotient;  // Only need 10 bits
    logic        G_x1024_valid;
    divider #(
        .WIDTH(20)
    ) G_div (
        .clk(clk),
        .rst(rst),
        .dividend({10'b0, g_x1024} << 10),  // pos
        .divisor(11'd1024 + g_x1024),       // pos
        .data_in_valid(sample_in_valid),
        .quotient(G_x1024_quotient),
        .remainder(),
        .data_out_valid(G_x1024_valid),
        .busy()
    );

    // Input for each 1-pole LPF
    logic [55:0] u;

    logic        u0_dividend_sign;
    logic        u0_valid_hold;
    logic        G_x1024_valid_hold;
    logic  [9:0] G_x1024;
    logic  [1:0] loop_iter;

    // Intermediate calculation
    logic [55:0] v;
    assign       v = $signed({1'b0, G_x1024}) *
                     $signed($signed(u) - $signed(s[loop_iter]));

    logic [55:0] next_u;
    assign       next_u = $signed(v) +
                          $signed({10'b0, s[loop_iter]} << 10);

    logic [45:0] next_s;
    assign       next_s = ($signed(next_u) + $signed(v)) >>> 10;

    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_out <= 0;
            sample_out_valid <= 0;

            u <= 0;
            
            for (int i=0; i<4; i++) begin
                s[i] <= 0;
            end
            
            u0_dividend_sign <= 0;
            u0_valid_hold <= 0;
            G_x1024_valid_hold <= 0;
            G_x1024 <= 0;
            loop_iter <= 0;
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    sample_out_valid <= 0;
                    if (sample_in_valid) begin
                        u0_dividend_sign <= u0_dividend[63];
                        state <= DIV;
                    end
                end

                DIV: begin
                    if ((u0_valid || u0_valid_hold) &&
                        (G_x1024_valid || G_x1024_valid_hold)) begin
                        u0_valid_hold <= 0;
                        G_x1024_valid_hold <= 0;

                        // Clip and apply sign
                        // Possible improvement: soft clipping
                        if (u0_dividend_sign) begin
                            if (u0[63:15] > 0) begin
                                u <= 56'hFF_FFFF_FFFF_8000;
                            end else begin
                                u <= ~u0[55:0] + 1;
                            end
                        end else begin
                            if (u0[63:15] > 0) begin
                                u <= 56'h00_0000_0000_7FFF;
                            end else begin
                                u <= u0[55:0];
                            end
                        end

                        G_x1024 <= G_x1024_quotient[9:0];

                        state <= LOOP;
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
                    if (loop_iter == 3) begin
                        sample_out <= $signed(next_u) >>> 40;
                        s[loop_iter] <= next_s;
                        loop_iter <= 0;
                        
                        sample_out_valid <= 1;
                        state <= IDLE;
                    end else begin
                        u <= next_u;
                        s[loop_iter] <= next_s;
                        loop_iter <= loop_iter + 1;
                    end
                end
            endcase
        end
    end
endmodule

`default_nettype wire

