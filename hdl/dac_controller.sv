`timescale 1ns / 1ps
`default_nettype none

module dac_controller
    #(
        parameter CLK_PERIOD = 1.0/120.0e6,
        parameter WORD_LEN = 24,
        parameter NUM_CHANNELS = 2
    )
    (
        input wire        clk,
        input wire        rst,
        input wire [15:0] sample_in_l,
        input wire [15:0] sample_in_r,
        input wire        sample_in_valid,

        output logic dac_copi,
        output logic dac_bclk,
        output logic dac_fsync
    );

    // WORD_LEN*NUM_CHANNELS bits per frame
    // For four bits, each bit is BIT_CYCLES+1 clk cycles
    // For the rest of the bits, each bit is BIT_CYCLES clk cycles
    localparam BIT_CYCLES = 52;
    localparam HALF_BIT_CYCLES = BIT_CYCLES/2;
    
    // Wait > 2 ms before clocking the DAC
    localparam INIT_CYCLES = int'(2.5e-3 / CLK_PERIOD);

    localparam FRAME_LEN = WORD_LEN*NUM_CHANNELS;

    enum {RST, IDLE, TX} state;

    logic           [FRAME_LEN-1:0] tx_data;
    logic [$clog2(INIT_CYCLES)-1:0] clk_counter;
    logic   [$clog2(FRAME_LEN)-1:0] bit_counter;
    
    logic  bit_cycles_addend;
    assign bit_cycles_addend =
        bit_counter == 8'd0  ||
        bit_counter == 8'd12 ||
        bit_counter == 8'd24 ||
        bit_counter == 8'd36;

    assign dac_bclk = (!rst) && (state != RST) && (clk_counter < HALF_BIT_CYCLES);

    always_ff @ (posedge clk) begin
        if (rst) begin
            dac_copi <= 1'b0;
            dac_fsync <= 1'b0;

            state <= RST;
            tx_data <= 0;
            clk_counter <= 0;
            bit_counter <= 0;
        end else begin
            case (state)
                RST: begin
                    if (clk_counter >= INIT_CYCLES-1) begin
                        state <= IDLE;
                        clk_counter <= 0;
                    end else begin
                        clk_counter <= clk_counter + 1;
                    end
                end

                IDLE: begin
                    if (sample_in_valid) begin
                        dac_copi <= sample_in_l[15];
                        dac_fsync <= 1'b1;
                        
                        state <= TX;
                        tx_data <= {sample_in_l, 8'b0, sample_in_r, 8'b0};
                        clk_counter <= 0;
                        bit_counter <= 0;
                    end else begin
                        if (clk_counter >= BIT_CYCLES-1 + bit_cycles_addend) begin
                            clk_counter <= 0;
                            if (bit_counter >= FRAME_LEN-1) begin
                                bit_counter <= 0;
                            end else begin
                                bit_counter <= bit_counter + 1;
                            end
                        end else begin
                            clk_counter <= clk_counter + 1;
                        end
                    end
                end

                TX: begin
                    if (clk_counter >= BIT_CYCLES-1 + bit_cycles_addend) begin
                        dac_fsync <= 1'b0;
                        dac_copi <= tx_data[FRAME_LEN-bit_counter-2];
                        clk_counter <= 0;
                        bit_counter <= bit_counter + 1;
                        if (bit_counter >= FRAME_LEN-2) begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_counter <= clk_counter + 1;
                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire
