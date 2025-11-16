`timescale 1ns / 1ps
`default_nettype none

module triangle_lfo
    (
        input wire clk,
        input wire rst,
        output logic [9:0] out
    );

    logic        increasing;
    logic [16:0] clk_counter;  // Sweep out 0 -> 1023 in ~0.7 s

    always_ff @ (posedge clk) begin
        if (rst) begin
            increasing <= 1;
            clk_counter <= 0;
            out <= 0;
        end else begin
            if (clk_counter == 0) begin
                if (increasing) begin
                    if (out == 1023) begin
                        out <= 1022;
                        increasing <= 0;
                    end else begin
                        out <= out + 1;
                    end
                end else begin
                    if (out == 0) begin
                        out <= 1;
                        increasing <= 1;
                    end else begin
                        out <= out - 1;
                    end
                end
            end
            clk_counter <= clk_counter + 1;
        end
    end

endmodule

`default_nettype wire
