`timescale 1ns / 1ps
`default_nettype none

module uart_receive
    #(
        parameter INPUT_CLOCK_FREQ=100000000,
        parameter BAUD_RATE=31250
    )
    (
        input wire clk,
        input wire rst,
        input wire din,
        output logic dout_valid,
        output logic [7:0] dout
    );

    // MIDI: async interface at 31.25 kbps, start bit = 0, stop bit = 1, LSB first

    localparam BAUD_BIT_PERIOD = int'(INPUT_CLOCK_FREQ / BAUD_RATE) - 1;
    localparam BAUD_BIT_PERIOD_HALF = int'((BAUD_BIT_PERIOD) / 2);
    localparam BAUD_BIT_PERIOD_75 = int'(3 * (BAUD_BIT_PERIOD) / 4);

    enum {IDLE, START, DATA, STOP, TRANSMIT} state, next_state;

    logic [31:0] clk_counter;
    logic [7:0] data_reg;
    logic [2:0] data_reg_counter;

    always_ff @(posedge clk) begin
        if (rst) begin
            dout_valid <= 0;
            dout <= 0;

            state <= IDLE;
            next_state <= IDLE;
            clk_counter <= 0;
            data_reg <= 0;
            data_reg_counter <= 0;
        end else begin
            case (state)
                IDLE: begin
                    dout_valid <= 0;
                    if (!din) begin
                        state <= START;
                    end
                end

                START: begin
                    if (clk_counter <= BAUD_BIT_PERIOD_HALF) begin
                        if (!din) begin
                            next_state <= DATA;
                            data_reg_counter <= 0;
                            data_reg <= 0;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end

                DATA: begin
                    if (clk_counter == BAUD_BIT_PERIOD_HALF) begin
                        if (data_reg_counter == 7) begin
                            next_state <= STOP;
                        end else begin
                            data_reg_counter <= data_reg_counter + 1;
                        end
                        data_reg <= {din, data_reg[7:1]};
                    end
                end

                STOP: begin
                    if (clk_counter >= BAUD_BIT_PERIOD_HALF && clk_counter <= BAUD_BIT_PERIOD) begin
                        if (din) begin
                            state <= TRANSMIT;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end

                TRANSMIT: begin
                    dout <= data_reg;
                    dout_valid <= 1;
                    state <= IDLE;
                end
            endcase

            if (state == IDLE) begin
                clk_counter <= 0;
            end else begin
                if (clk_counter == BAUD_BIT_PERIOD) begin
                    state <= next_state;
                    clk_counter <= 0;
                end else begin
                    clk_counter <= clk_counter + 1;
                end
            end
        end
    end
endmodule
`default_nettype wire
