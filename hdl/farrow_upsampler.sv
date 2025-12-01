`timescale 1ns / 1ps
`default_nettype none

module farrow_upsampler
    (
        input wire clk,
        input wire rst,

        input  wire  [15:0] sample_period_in,
        input  wire  [15:0] sample_period_out,

        input  wire  [15:0] sample_in,
        input  wire         sample_in_valid,

        output logic [15:0] sample_out,
        output logic        sample_out_valid,

        input  wire   [4:0] delay_debug,
        input  wire         delay_debug_valid
    );

    localparam DELAY_SCALE = 4;
    localparam DELAY_WIDTH = DELAY_SCALE + 3;
    localparam SAMPLE_WIDTH = 16 + 3 + 3*DELAY_SCALE;
    localparam SAMPLE_PERIOD_WIDTH = 16;
    localparam FARROW_DIVISOR = 6 * (1<<DELAY_SCALE)**3;

    logic [SAMPLE_PERIOD_WIDTH-1:0] sample_out_counter;
    logic [SAMPLE_PERIOD_WIDTH-1:0] sample_delay_counter; 
    logic                           compute_trigger;
    assign compute_trigger = sample_out_counter >= sample_period_out - 1;

    // delay manager
    logic [SAMPLE_PERIOD_WIDTH+DELAY_SCALE-1:0] div_delay_quotient;
    logic                                       div_delay_out_valid;
    logic                                       prev_div_delay_out_valid;
    logic [DELAY_WIDTH-1:0]                     delay;
    always_ff @ (posedge clk) begin
        if (rst) begin
            delay <= 0;
            prev_div_delay_out_valid <= 0;
        end else begin
            if (delay_debug_valid) begin
                delay <= delay_debug;
            end else begin
                if (div_delay_out_valid) begin
                    delay <= {1'b0,div_delay_quotient[DELAY_SCALE+1:0]};
                end
            end
            prev_div_delay_out_valid <= div_delay_out_valid;
        end
    end


    // sample_in manager
    logic [SAMPLE_WIDTH-1:0]        x_buf [3:0];  // Delayed input samples
    logic [SAMPLE_WIDTH-1:0]        x     [3:0];  // Buffer for Farrow
    logic [SAMPLE_PERIOD_WIDTH-1:0] sample_period_hold;
    logic [SAMPLE_WIDTH-1:0]        sample_ext;
    assign sample_ext = {{(SAMPLE_WIDTH-16){sample_in[15]}}, sample_in};
    always_ff @ (posedge clk) begin
        if (rst) begin
            for (int i=0; i<4; i++) begin
                x_buf[i] <= 0;
            end
            for (int i=0; i<4; i++) begin
                x[i] <= 0;
            end
            sample_period_hold <= 0;
        end else begin
            if (sample_in_valid) begin
                x_buf[3] <= x_buf[2];
                x_buf[2] <= x_buf[1];
                x_buf[1] <= x_buf[0];
                x_buf[0] <= sample_ext;

                sample_period_hold <= sample_period_in;

                if (compute_trigger) begin
                    x[3] <= x_buf[2];
                    x[2] <= x_buf[1];
                    x[1] <= x_buf[0];
                    x[0] <= sample_ext;
                end
            end else begin
                if (compute_trigger) begin
                    for (int i=0; i<4; i++) begin
                        x[i] <= x_buf[i];
                    end
                end
            end
        end
    end


    logic [SAMPLE_WIDTH+DELAY_WIDTH*3-1:0] div_farrow_dividend;
    logic [SAMPLE_WIDTH+DELAY_WIDTH*3-1:0] div_farrow_quotient;


    // 3rd order Farrow structure
    // See Vesa Valimaki dissertation chapter 3.3, 1995
    // "Discrete-Time Modeling of Acoustic Tubes Using Fractional Delay Filters"
    // Note: The block diagram on p102 has the wrong sign on one of the adders

    enum {
        IDLE,

        MULT_1_PRE,
        MULT_1,
        MULT_1_POST,

        MULT_2_PRE,
        MULT_2,
        MULT_2_POST,

        MULT_3_PRE,
        MULT_3,
        MULT_3_POST,

        OUT
    } farrow_state;

    logic [SAMPLE_WIDTH-1:0] left_sum;
    logic [SAMPLE_WIDTH-1:0] left_sum_shift;

    logic [SAMPLE_WIDTH-1:0] x1mx2;
    assign                   x1mx2 = x[1] - x[2];
    logic [SAMPLE_WIDTH-1:0] d3_factor; 

    logic [SAMPLE_WIDTH-1:0] x0px2;
    assign                   x0px2 = x[0] + x[2];
    logic [SAMPLE_WIDTH-1:0] d2_factor_pre;

    logic [SAMPLE_WIDTH-1:0] farrow_out_addend;

    logic [SAMPLE_WIDTH+DELAY_WIDTH+1-1:0] top_sum_2;
    logic [SAMPLE_WIDTH+DELAY_WIDTH*2  :0] top_sum;
    logic [SAMPLE_WIDTH+DELAY_WIDTH*3+1:0] farrow_out;
    logic                                  farrow_out_valid;

    logic [SAMPLE_WIDTH+DELAY_WIDTH*2  :0] mult_a;
    logic              [DELAY_WIDTH  -1:0] mult_b;
    logic [SAMPLE_WIDTH+DELAY_WIDTH*3+1:0] mult_out;
    assign mult_out = $signed(mult_a) * $signed(mult_b);

    always_ff @ (posedge clk) begin
        if (rst) begin
            left_sum <= 0;
            left_sum_shift <= 0;
            d3_factor <= 0;
            d2_factor_pre <= 0;
            farrow_out_addend <= 0;

            top_sum_2 <= 0;
            top_sum <= 0;
            farrow_out <= 0;

            farrow_out_valid <= 0;
            farrow_state <= IDLE;

            mult_a <= 0;
            mult_b <= 0;
        end else begin
            case (farrow_state)
                IDLE: begin
                    farrow_out_valid <= 0;
                    if (prev_div_delay_out_valid) begin
                        mult_b <= $signed(delay);
                        d3_factor <= (x1mx2<<1) + x1mx2 + (x[3] - x[0]);
                        farrow_state <= MULT_1_PRE;
                    end
                end

                MULT_1_PRE: begin
                    mult_a <= $signed(d3_factor);
                    d2_factor_pre <= 
                        (
                            ((x0px2<<1) + x0px2) -
                            ((x[1]<<2) + (x[1]<<1))
                        ) <<< DELAY_SCALE;
                    left_sum <=
                        (x[0]<<2) + (x[0]<<1) - x[3] - (
                            (x[1]<<1) + x[1] + (x[0]<<1)
                        );
                    farrow_out_addend <= 
                        (((x[1])<<2) + (x[1]<<1)) <<
                        ((DELAY_SCALE<<1) + DELAY_SCALE);
                    farrow_state <= MULT_1;
                end
                MULT_1: begin
                    top_sum_2 <= mult_out;
                    left_sum_shift <= left_sum <<< (DELAY_SCALE<<1);
                    farrow_state <= MULT_1_POST;
                end
                MULT_1_POST: begin
                    top_sum_2 <= $signed(top_sum_2) + $signed(d2_factor_pre);
                    farrow_state <= MULT_2_PRE;
                end

                MULT_2_PRE: begin
                    mult_a <= $signed(top_sum_2);
                    farrow_state <= MULT_2;
                end
                MULT_2: begin
                    top_sum <= mult_out;
                    farrow_state <= MULT_2_POST;
                end
                MULT_2_POST: begin
                    top_sum <= $signed(top_sum) + $signed(left_sum_shift);
                    farrow_state <= MULT_3_PRE;
                end

                MULT_3_PRE: begin
                    mult_a <= $signed(top_sum);
                    farrow_state <= MULT_3;
                end
                MULT_3: begin
                    farrow_out <= mult_out;
                    farrow_state <= MULT_3_POST;
                end
                MULT_3_POST: begin
                    farrow_out <= $signed(farrow_out) + $signed(farrow_out_addend);
                    farrow_state <= OUT;
                end

                OUT: begin
                    // Take absolute value of farrow_out.
                    if (farrow_out[SAMPLE_WIDTH+DELAY_WIDTH*3-1]) begin
                        div_farrow_dividend <= ~farrow_out + 1;
                    end else begin
                        div_farrow_dividend <= farrow_out;
                    end
                    farrow_out_valid <= 1;
                    farrow_state <= IDLE;
                end
            endcase
        end
    end

    // Save sign of farrow_out to apply after div_farrow operation.
    logic div_farrow_sign;
    always_ff @ (posedge clk) begin
        if (rst) begin
            div_farrow_sign <= 0;
        end else begin
            if (farrow_out_valid) begin
                div_farrow_sign <= farrow_out[SAMPLE_WIDTH+DELAY_WIDTH*3-1];
            end
        end
    end


    // Clip output and apply sign
    always_comb begin
        if (div_farrow_sign) begin
            if (div_farrow_quotient > 16'h8000) begin
                sample_out = 16'h8000;
            end else begin
                sample_out = ~div_farrow_quotient + 1;
            end
        end else begin
            if (div_farrow_quotient > 16'h8000) begin
                sample_out = 16'h7FFF;
            end else begin
                sample_out = div_farrow_quotient;
            end
        end
    end


    // Catch edge case where sample_in_valid & compute_trigger
    logic [SAMPLE_PERIOD_WIDTH+DELAY_SCALE-1:0] div_delay_dividend;
    always_comb begin
        if (sample_in_valid) begin
            div_delay_dividend = 0;
        end else begin
            div_delay_dividend = {
                {DELAY_SCALE{1'b0}}, sample_delay_counter
            } << DELAY_SCALE;
        end
    end


    // Compute fractional delay relative to last sample input.
    divider #(
        .WIDTH(SAMPLE_PERIOD_WIDTH+DELAY_SCALE)
    ) div_delay (
        .clk(clk),
        .rst(rst),
        .dividend(div_delay_dividend),
        .divisor({{DELAY_SCALE{1'b0}}, sample_period_hold}),
        .data_in_valid(compute_trigger),
        .quotient(div_delay_quotient),
        .remainder(),
        .data_out_valid(div_delay_out_valid),
        .busy()
    );


    divider #(
        .WIDTH(SAMPLE_WIDTH+DELAY_WIDTH*3)
    ) div_farrow (
        .clk(clk),
        .rst(rst),
        .dividend(div_farrow_dividend),
        .divisor(FARROW_DIVISOR),
        .data_in_valid(farrow_out_valid),
        .quotient(div_farrow_quotient),
        .remainder(),
        .data_out_valid(sample_out_valid),
        .busy()
    );

    
    // sample_out_counter
    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_out_counter <= 0;
        end else begin
            if (sample_out_counter >= sample_period_out - 1) begin
                sample_out_counter <= 0;
            end else begin
                sample_out_counter <= sample_out_counter + 1;
            end
        end
    end


    // sample_delay_counter
    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_delay_counter <= 0;
        end else begin
            if (sample_in_valid) begin
                sample_delay_counter <= 0;
            end else begin
                sample_delay_counter <= sample_delay_counter + 1;
            end
        end
    end
endmodule 

`default_nettype wire
