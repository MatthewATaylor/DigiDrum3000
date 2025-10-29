`timescale 1ns / 1ps
`default_nettype none

module debouncer_trig
    #(
        parameter CLK_PERIOD_NS = 10,
        parameter DEBOUNCE_TIME_MS = 5
    )
    (
        input wire clk,
        input wire rst,
        input wire dirty,
        output logic clean
    );
    
    parameter COUNTER_MAX = int'($ceil(DEBOUNCE_TIME_MS*1_000_000/CLK_PERIOD_NS));
    parameter COUNTER_SIZE = $clog2(COUNTER_MAX);
    
    logic [COUNTER_SIZE-1:0] counter;
    logic current;
    logic old_dirty;

    always_ff @(posedge clk)begin
        if (rst)begin
            counter <= 0;
            clean <= 0;
            current <= 0;
            old_dirty <= dirty;
        end else begin
            if (counter == COUNTER_MAX-1) begin
                current <= old_dirty;
                if (!current && old_dirty) begin
                    clean <= 1;
                end
                counter <= 0;
            end else if (dirty == old_dirty) begin
                counter <= counter + 1;
            end else begin
                counter <= 0;
            end
            old_dirty <= dirty;

            if (clean) begin
                clean <= 0;
            end
        end
    end
endmodule

`default_nettype wire

