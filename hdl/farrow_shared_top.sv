`timescale 1ns / 1ps
`default_nettype none

module farrow_shared_top
    #(
        parameter SAMPLE_COUNT
    )
    (
        input wire clk,
        input wire rst,

        input  wire  [15:0] sample_period_in,
        input  wire  [15:0] sample_period_out,

        input  wire  [16*SAMPLE_COUNT-1:0] sample_in,
        input  wire                        sample_in_valid,

        output logic [16*SAMPLE_COUNT-1:0] sample_out,
        output logic                       sample_out_valid,

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


    logic [SAMPLE_PERIOD_WIDTH-1:0] sample_period_hold;
    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_period_hold <= 0;
        end else begin
            if (sample_in_valid) begin
                sample_period_hold <= sample_period_in;
            end
        end
    end


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


    logic [SAMPLE_COUNT-1:0] sample_out_valids;
    assign                   sample_out_valid = sample_out_valids[0];
    genvar farrow_index;
    generate
        for (farrow_index=0; farrow_index<SAMPLE_COUNT; ++farrow_index) begin
            farrow_shared #(
                .DELAY_SCALE(DELAY_SCALE),
                .DELAY_WIDTH(DELAY_WIDTH),
                .SAMPLE_WIDTH(SAMPLE_WIDTH),
                .SAMPLE_PERIOD_WIDTH(SAMPLE_PERIOD_WIDTH),
                .FARROW_DIVISOR(FARROW_DIVISOR)
            ) farrow_shared_i (
                .clk(clk),
                .rst(rst),

                .sample_period_hold(sample_period_hold),
                
                .sample_in(sample_in[16*(farrow_index+1)-1 : 16*farrow_index]),
                .sample_in_valid(sample_in_valid),

                .sample_out(sample_out[16*(farrow_index+1)-1 : 16*farrow_index]),
                .sample_out_valid(sample_out_valids[farrow_index]),

                .prev_div_delay_out_valid(prev_div_delay_out_valid),
                .compute_trigger(compute_trigger),
                .delay(delay)
            );
        end
    endgenerate
endmodule 

`default_nettype wire
