`timescale 1ns / 1ps
`default_nettype none

// 4-pole transistor ladder model
// See "The Art of VA Filter Design" by Vadim Zavalishin
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


    // State indicators
    enum {IDLE, GS, DIV, LOOP} state;
    logic        gs_mult;
    logic  [1:0] gs_iter;
    logic        calc_v;
    logic  [1:0] loop_iter;


    // Registers for sequential logic
    logic [55:0] u;               // Input for each 1-pole LPF
    logic [45:0] s [3:0];         // 1-pole LPF states 
    logic [55:0] v;               // Intermediate calculation
    logic  [9:0] g_x1024;         // Cutoff parameter 
    logic [39:0] g_x1024_pow;     // Cumulative product of g_x1024  
    logic [48:0] S_x1024_4_acc;
    logic [47:0] S_x1024_4_mult;
    logic [49:0] kG_mult;
    logic [69:0] kS_mult;
    logic        u0_dividend_sign;
    logic        u0_valid_hold;
    logic        G_x1024_valid_hold;
    logic  [9:0] G_x1024;


    logic [55:0] x_shifted;
    assign       x_shifted = $signed(sample_in) << 40;
    
    logic [58:0] S_x1024_4;
    assign       S_x1024_4 = $signed(S_x1024_4_acc) << 10;

    // Scale G,S by feedback gain
    logic [41:0] kG;
    assign       kG = kG_mult >> 8;
    logic [61:0] kS;
    assign       kS = $signed(kS_mult) >>> 8;

    logic [55:0] next_u;
    assign       next_u = $signed(v) +
                          $signed({10'b0, s[loop_iter]} << 10);
    logic [45:0] next_s;
    assign       next_s = ($signed(next_u) + $signed(v)) >>> 10;

    // u0 is the input to the series combination of 1-pole LPFs
    // Take absolute value before dividing
    logic [62:0] u0_dividend_abs;
    logic [62:0] u0_dividend;
    always_comb begin
        u0_dividend = $signed(x_shifted) - $signed(kS);
        if (u0_dividend[62]) begin
            u0_dividend_abs = ~u0_dividend + 1;
        end else begin
            u0_dividend_abs = u0_dividend;
        end
    end


    // Dividers
    logic        div_in_valid;

    logic [62:0] u0;  // Only need 56 bits
    logic        u0_valid;
    divider #(
        .WIDTH(63)
    ) u0_div (
        .clk(clk),
        .rst(rst),
        .dividend(u0_dividend_abs),
        .divisor(41'h10000000000 + kG),     // pos
        .data_in_valid(div_in_valid),
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

            gs_iter <= 0;
            calc_v <= 1;
            loop_iter <= 0;
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

                        u0_dividend_sign <= u0_dividend[62];
                        div_in_valid <= 1;
                        state <= DIV;
                    end else begin
                        if (gs_mult) begin
                            g_x1024_pow <= g_x1024_pow * g_x1024;
                            case (gs_iter)
                                2'b00: begin
                                    S_x1024_4_mult <=
                                        $signed(s[2][35:0]) *
                                        $signed({1'b0, g_x1024_pow[9:0]});
                                end

                                2'b01: begin
                                    S_x1024_4_mult <=
                                        $signed(s[1][25:0]) *
                                        $signed({1'b0, g_x1024_pow[19:0]});
                                end

                                2'b10: begin
                                    S_x1024_4_mult <=
                                        $signed(s[0][15:0]) *
                                        $signed({1'b0, g_x1024_pow[29:0]});
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
                    if ((u0_valid || u0_valid_hold) &&
                        (G_x1024_valid || G_x1024_valid_hold)) begin
                        u0_valid_hold <= 0;
                        G_x1024_valid_hold <= 0;

                        // Clip and apply sign
                        // Possible improvement: soft clipping
                        if (u0_dividend_sign) begin
                            if (u0[62:15] > 0) begin
                                u <= 56'hFF_FFFF_FFFF_8000;
                            end else begin
                                u <= ~u0[55:0] + 1;
                            end
                        end else begin
                            if (u0[62:15] > 0) begin
                                u <= 56'h00_0000_0000_7FFF;
                            end else begin
                                u <= u0[55:0];
                            end
                        end

                        G_x1024 <= G_x1024_quotient[9:0];

                        state <= LOOP;
                        loop_iter <= 0;
                        calc_v <= 1;
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
                    // Calculate output of each 1-pole LPF over 4 clock cycles
                    if (calc_v) begin
                        v <= $signed({1'b0, G_x1024}) *
                            $signed($signed(u) - $signed(s[loop_iter]));
                    end else begin
                        if (loop_iter == 3) begin
                            sample_out <= $signed(next_u) >>> 40;
                            s[loop_iter] <= next_s;
                            
                            sample_out_valid <= 1;
                            state <= IDLE;
                        end else begin
                            u <= next_u;
                            s[loop_iter] <= next_s;
                            loop_iter <= loop_iter + 1;
                        end
                    end
                    calc_v <= !calc_v;
                end
            endcase
        end
    end
endmodule

`default_nettype wire

