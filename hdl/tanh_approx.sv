`timescale 1ns / 1ps
`default_nettype none

// CORDIC sinh and cosh range of convergence only within [-pi/4, pi/4]
//  (but can extend range with lookup tables)
// In [-pi/4, pi/4] tanh is roughly linear, so we need a bigger range

// tanh approximation found here:
//  https://www.musicdsp.org/en/latest/Other/238-rational-tanh-approximation.html
// The [3/2] Pade approximant for tanh:
//  [3/2]_f = x*(15+x**2)/(15+6*x**2)
// The proposed approximation:
//  f(x) = x*(27+x**2)/(27+9*x**2)
// f(x) provides f(3)=1, f'(3)=0, f''(3)=0

// Scaled function: [(x<<30) + (x<<31) + x**3] / [(1<<30) + x**2 + (x**2<<1)]

module tanh_approx
    (
        input wire clk,
        input wire rst,

        input wire [15:0] din,
        input wire        din_valid,

        output logic [15:0] dout,
        output logic        dout_valid
    );

    enum {IDLE, MULT_1, MULT_2, DIVIDEND_SUM, DIVIDEND_ABS, DIV} state;

    logic [31:0] mult_a;
    logic [15:0] mult_b;
    logic [47:0] mult_out;
    assign mult_out = $signed(mult_a) * $signed(mult_b);

    logic [31:0] x2;
    logic [47:0] x3;

    logic [33:0] x2_ext;
    assign x2_ext = {{2{1'b0}}, x2};  // x2 is positive

    logic [48:0] x3_ext;
    assign x3_ext = {x3[47], x3};

    logic [48:0] x_ext;
    assign x_ext = {{33{mult_b[15]}}, mult_b};

    logic [48:0] x_shl30;
    assign x_shl30 = x_ext << 30;

    logic [48:0] x_shl31;
    assign x_shl31 = x_shl30 << 1;

    logic [48:0] dividend;
    logic        dividend_sign;
    logic [33:0] divisor;
    logic        div_in_valid;
    logic [48:0] quotient;
    logic        div_out_valid;

    always_ff @ (posedge clk) begin
        if (rst) begin
            state <= IDLE;

            mult_a <= 0;
            mult_b <= 0;

            x2 <= 0;
            x3 <= 0;

            dividend <= 0;
            dividend_sign <= 0;
            divisor <= 0;
            div_in_valid <= 0;

            dout <= 0;
            dout_valid <= 0;
        end else begin
            case (state)
                IDLE: begin
                    dout_valid <= 0;
                    if (din_valid) begin
                        mult_a <= $signed(din);
                        mult_b <= din;
                        state <= MULT_1;
                    end
                end

                MULT_1: begin
                    x2 <= mult_out;
                    mult_a <= mult_out;
                    state <= MULT_2;
                end

                MULT_2: begin
                    x3 <= mult_out;
                    divisor <=
                        {{3{1'b0}}, 1'b1, {30{1'b0}}} +
                        x2_ext + (x2_ext<<1);
                    state <= DIVIDEND_SUM;
                end

                DIVIDEND_SUM: begin
                    dividend <= x_shl30 + x_shl31 + x3_ext;
                    state <= DIVIDEND_ABS;
                end

                DIVIDEND_ABS: begin
                    if (dividend[48]) begin
                        dividend <= ~dividend + 1;
                    end
                    dividend_sign <= dividend[48];
                    div_in_valid <= 1;
                    state <= DIV;
                end

                DIV: begin
                    div_in_valid <= 0;
                    if (div_out_valid) begin
                        if (dividend_sign) begin
                            dout <= ~quotient[15:0] + 1;
                        end else begin
                            dout <= quotient[15:0];
                        end
                        dout_valid <= 1;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    divider #(
        .WIDTH(49)
    ) div (
        .clk(clk),
        .rst(rst),
        .dividend(dividend),
        .divisor({{15{1'b0}}, divisor}),
        .data_in_valid(div_in_valid),
        .quotient(quotient),
        .remainder(),
        .data_out_valid(div_out_valid),
        .busy()
    );

endmodule

`default_nettype wire

