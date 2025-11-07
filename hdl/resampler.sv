`timescale 1ns / 1ps
`default_nettype none

module resampler
    #(
        parameter SAMPLE_PERIOD_OUT = 2272
    )
    (
        input wire clk,
        input wire rst,

        input  wire  [13:0] sample_period,

        input  wire  [15:0] sample_in,
        input  wire         sample_in_valid,

        output logic [15:0] sample_out,
        output logic        sample_out_valid,

        input  wire   [4:0] delay_debug,
        input  wire         delay_debug_valid
    );

    localparam DELAY_SCALE = 2;
    localparam DELAY_DIV_SCALE = 8;
    localparam DELAY_WIDTH = DELAY_SCALE + 1;
    localparam SAMPLE_WIDTH = 25;
    localparam FARROW_DIVISOR = 6 * (1<<DELAY_SCALE)**3;

    logic [$clog2(SAMPLE_PERIOD_OUT)-1:0] sample_out_counter;
  

    // delay manager
    logic [14+DELAY_WIDTH+DELAY_DIV_SCALE-1:0] div_delay_quotient;
    logic                                      div_delay_out_valid;
    logic                                      prev_div_delay_out_valid;
    logic [DELAY_WIDTH-1:0]                    delay;
    logic [DELAY_WIDTH-1:0]                    prev_delay;
    logic [14+DELAY_WIDTH+DELAY_DIV_SCALE-1:0] delay_full;
    logic [14+DELAY_WIDTH+DELAY_DIV_SCALE-1:0] delay_quotient_sum;
    logic [14+DELAY_WIDTH+DELAY_DIV_SCALE-1:0] delay_quotient_sum_shifted;
    always_comb begin
        delay_quotient_sum = delay_full + div_delay_quotient;
        delay_quotient_sum_shifted = delay_quotient_sum >> DELAY_DIV_SCALE;
    end
    always_ff @ (posedge clk) begin
        if (rst) begin
            delay <= 0;
            delay_full <= 0;
            prev_delay <= 0;
        end else begin
            if (delay_debug_valid) begin
                delay <= delay_debug;
                prev_delay <= delay;
            end else begin
                if (div_delay_out_valid) begin
                    delay_full <= delay_quotient_sum;
                    delay <= {1'b0,delay_quotient_sum_shifted[DELAY_SCALE-1:0]};
                    prev_delay <= delay;
                end
            end
            prev_div_delay_out_valid <= div_delay_out_valid;
        end
    end


    // sample_in manager
    logic [SAMPLE_WIDTH-1:0] x_buf [3:0];   // Delayed input samples
    logic [1:0]  sample_in_valid_buf;       // Use for timing Farrow division start
    logic        sample_in_valid_reg;       // Use for timing Farrow pipeline
    logic [13:0] sample_period_prev;
    logic [13:0] sample_period_error;       // Account for dynamic sample_period
    always_ff @ (posedge clk) begin
        if (rst) begin
            for (int i=0; i<4; i++) begin
                x_buf[i] <= 0;
            end
            sample_in_valid_buf <= 0;
            sample_in_valid_reg <= 0;
            // sample_period_prev <= 0;
            // sample_period_error <= 0;
        end else begin
            if (sample_in_valid) begin
                x_buf[3] <= x_buf[2];
                x_buf[2] <= x_buf[1];
                x_buf[1] <= x_buf[0];
                x_buf[0] <= {{(SAMPLE_WIDTH-16){sample_in[15]}}, sample_in};
                
                if (sample_out_valid) begin
                    sample_in_valid_buf <= {1'b1, 1'b0}; 
                end else begin
                    sample_in_valid_buf[0] <= 1;
                end

                // sample_period_prev <= sample_period;
                // sample_period_error <= sample_period - sample_period_prev;
            end else if (sample_out_valid) begin
                sample_in_valid_buf <= {sample_in_valid_buf[0], 1'b0};
                
                // Only apply error correction once per div_delay operation
                // sample_period_error <= 0;
            end
            sample_in_valid_reg <= sample_in_valid;
        end
    end


    logic                                  div_farrow_in_valid;
    logic                                  div_farrow_out_valid;
    logic [SAMPLE_WIDTH+DELAY_WIDTH*3-1:0] div_farrow_dividend;
    logic [SAMPLE_WIDTH+DELAY_WIDTH*3-1:0] div_farrow_quotient;
    logic [15:0]                           div_farrow_quotient_signed;


    // 3rd order Farrow structure
    // See Vesa Valimaki dissertation chapter 3, 1995
    // "Discrete-Time Modeling of Acoustic Tubes Using Fractional Delay Filters"
    // Note: The block diagram on p102 has the wrong sign on one of the adders
    logic [SAMPLE_WIDTH-1:0]               x [3:0];
    logic [ DELAY_WIDTH-1:0]               delay_hold;
    logic [SAMPLE_WIDTH-1:0]               left_sum;
    logic [SAMPLE_WIDTH-1:0]               x1mx2;
    assign                                 x1mx2 = x[1] - x[2];
    logic [SAMPLE_WIDTH+DELAY_WIDTH-1:0]   top_sum_2;
    logic [SAMPLE_WIDTH-1:0]               x0px2;
    assign                                 x0px2 = x[0] + x[2];
    logic [SAMPLE_WIDTH-1:0]               d2_factor_pre;
    logic [SAMPLE_WIDTH+DELAY_WIDTH*2-1:0] top_sum;
    logic [SAMPLE_WIDTH+DELAY_WIDTH*3-1:0] farrow_out;
    logic [1:0]                            farrow_counter;
    logic [3:0]                            farrow_out_valid;
    logic                                  farrow_inputs_valid;
    logic                                  div_farrow_ready;
    assign farrow_inputs_valid =
        prev_div_delay_out_valid ||
        (sample_in_valid_reg && div_farrow_ready);
    always_ff @ (posedge clk) begin
        if (rst) begin
            for (int i=0; i<4; i++) begin
                x[i] <= 0;
            end
            delay_hold <= 0;

            top_sum_2 <= 0;
            d2_factor_pre <= 0;
            top_sum <= 0;
            left_sum <= 0;
            farrow_out <= 0;

            farrow_counter <= 0;
            farrow_out_valid <= 0;
        end else begin
            farrow_out_valid <= {
                farrow_out_valid[2:0],
                farrow_inputs_valid
            };

            if (farrow_inputs_valid || farrow_counter < 3) begin
                // Run for four clock cycles every time after delay or
                // x is updated.
                // Cycle 0
                if (farrow_inputs_valid) begin
                    // Hold signals that may change in the middle of
                    // calculation.
                    for (int i=0; i<4; i++) begin
                        x[i] <= x_buf[i];
                    end
                    delay_hold <= delay;
                    farrow_counter <= 0;
                end else begin
                    farrow_counter <= farrow_counter + 1;
                end

                // Cycle 1
                top_sum_2 <=
                    $signed(delay_hold) *
                    $signed((x1mx2<<1) + x1mx2 + (x[3] - x[0]));
                d2_factor_pre <=
                    ($signed((x0px2<<1) + x0px2) <<< DELAY_SCALE) -
                    ($signed(((x[1]<<2) + (x[1]<<1))) <<< DELAY_SCALE);

                // Cycle 2
                top_sum <=
                    $signed(delay_hold) * (
                        $signed(top_sum_2) +
                        $signed(d2_factor_pre)
                    );
                left_sum <= x[3] - (
                    (x[0]<<2) + (x[0]<<1) - (
                        (x[1]<<1) + x[1] + (x[0]<<1)
                    )
                );

                // Cycle 3
                farrow_out <=
                    $signed(delay_hold) *
                    ($signed(top_sum) - $signed(left_sum << (DELAY_SCALE<<1))) +
                    $signed(
                        ((x[1]<<2) + (x[1]<<1)) <<
                        ((DELAY_SCALE<<1) + DELAY_SCALE)
                    );
            end
        end
    end
    always_comb begin
        if (farrow_out[SAMPLE_WIDTH+DELAY_WIDTH*3-1]) begin
            div_farrow_dividend = ~farrow_out + 1;
        end else begin
            div_farrow_dividend = farrow_out;
        end
    end


    // div_farrow input manager
    logic div_farrow_sign;
    always_ff @ (posedge clk) begin
        if (rst) begin
            div_farrow_sign <= 0;
            div_farrow_in_valid <= 0;
            div_farrow_ready <= 0;
        end else begin
            if (delay < prev_delay) begin
                // When delay wraps around, we need to wait for a sample
                //  only if a sample was not input between the last two
                //  sample_out_valids
                
                if (sample_in_valid_buf[1] | sample_in_valid_buf[0]) begin
                    if (farrow_out_valid[3]) begin
                        div_farrow_in_valid <= 1;
                        div_farrow_ready <= 0;
                    end
                end else begin
                    if (farrow_out_valid[3]) begin
                        if (div_farrow_ready) begin
                            div_farrow_in_valid <= 1;
                            div_farrow_ready <= 0;
                        end else begin
                            div_farrow_ready <= 1;
                        end
                    end
                end
            end else begin
                if (farrow_out_valid[3]) begin
                    div_farrow_in_valid <= 1;
                    div_farrow_ready <= 0;
                end
            end

            if (div_farrow_in_valid) begin
                div_farrow_sign <= farrow_out[SAMPLE_WIDTH+DELAY_WIDTH*3-1];
                div_farrow_in_valid <= 0;
            end
        end
    end


    // div_farrow output manager
    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_out <= 0;
            sample_out_valid <= 0;
            div_farrow_quotient_signed <= 0;
            sample_period_prev <= 0;
        end else begin
            if (div_farrow_out_valid) begin
                if (div_farrow_sign) begin
                    if (div_farrow_quotient > 16'h8000) begin
                        div_farrow_quotient_signed <= 16'h8000;
                    end else begin
                        div_farrow_quotient_signed <= ~div_farrow_quotient + 1;
                    end
                end else begin
                    if (div_farrow_quotient > 16'h8000) begin
                        div_farrow_quotient_signed <= 16'h7FFF;
                    end else begin
                        div_farrow_quotient_signed <= div_farrow_quotient;
                    end
                end
            end

            if (sample_out_counter == SAMPLE_PERIOD_OUT-1) begin
                sample_out <= div_farrow_quotient_signed;
                sample_out_valid <= 1;
            end

            if (sample_out_valid) begin
                sample_out_valid <= 0;
                sample_period_prev <= sample_period;
            end
        end
    end


    logic [13:0] div_delay_divisor;
    always_comb begin
        sample_period_error = sample_period - sample_period_prev;
        div_delay_divisor = sample_period + sample_period_error;
    end


    // Compute sampling ratio with scaling to raise precision
    divider #(
        .WIDTH(14+DELAY_WIDTH+DELAY_DIV_SCALE)
    ) div_delay (
        .clk(clk),
        .rst(rst),
        .dividend(SAMPLE_PERIOD_OUT<<(DELAY_SCALE+DELAY_DIV_SCALE)),
        .divisor(div_delay_divisor),
        .data_in_valid(sample_out_valid),
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
        .data_in_valid(div_farrow_in_valid),
        .quotient(div_farrow_quotient),
        .remainder(),
        .data_out_valid(div_farrow_out_valid),
        .busy()
    );


    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_out_counter <= 0;
        end else begin
            if (sample_out_counter == SAMPLE_PERIOD_OUT-1) begin
                sample_out_counter <= 0;
            end else begin
                sample_out_counter <= sample_out_counter + 1;
            end
        end
    end
endmodule 

`default_nettype wire
