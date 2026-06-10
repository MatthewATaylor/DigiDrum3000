`timescale 1ns / 1ps
`default_nettype none

module square_wave
    #(
        parameter AMPLITUDE,
        parameter FREQUENCY,
        parameter CLK_PERIOD = 1.0/120.0e6,
        parameter SAMPLE_PERIOD = 2500
    )
    (
        input  wire         clk,
        input  wire         rst,
        output logic [15:0] sample_out,
        output logic        sample_out_valid
    );

    // Number of samples between square wave edges
    localparam PERIOD = int'(1.0/FREQUENCY / (2.0*SAMPLE_PERIOD*CLK_PERIOD));
    
    logic [$clog2(SAMPLE_PERIOD)-1:0] sample_period_counter;
    logic [$clog2(PERIOD)-1:0]        square_counter;

    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_out <= -AMPLITUDE;
            sample_out_valid <= 1'b0;

            sample_period_counter <= 0;
            square_counter <= 0;
        end else begin
            if (sample_period_counter >= SAMPLE_PERIOD-1) begin
                sample_period_counter <= 0;
                sample_out_valid <= 1'b1;
                if (square_counter >= PERIOD-1) begin
                    sample_out <= -sample_out;
                    square_counter <= 0;
                end else begin
                    square_counter <= square_counter + 1;
                end
            end else begin
                sample_period_counter <= sample_period_counter + 1;
            end

            if (sample_out_valid) begin
                sample_out_valid <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
