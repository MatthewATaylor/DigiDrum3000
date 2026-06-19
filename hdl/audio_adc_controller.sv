`timescale 1ns / 1ps
`default_nettype none

module audio_adc_controller
    #(
        parameter CLK_PERIOD = 1.0/120.0e6,
        parameter WORD_LEN = 32,
        parameter NUM_CHANNELS = 4
    )
    (
        input  wire  clk,
        input  wire  rst,

        input  wire  adc_cipo,
        output logic adc_bclk,
        output logic adc_fsync,
        output logic adc_shdnz,

        output logic [16*NUM_CHANNELS-1:0] samples_out
    );

    // 19.53125 clk cycles for every bclk cycle.
    // If we use 20 clk cycles, we end up with 60 excess cycles by end of frame.
    // There are 128 bits per frame, so use one less cycle every other bit.
    // That leaves us with 4-cycle deficit, so add back one cycle at start of each 32-bit sample.
    //     if      (bit_counter % 32 == 0) : cycles = 20
    //     else if (bit_counter %  2 == 0) : cycles = 19
    //     else                            : cycles = 20

    localparam BIT_CYCLES = 19;
    localparam HALF_BIT_CYCLES = 10;
    
    // Wait > 0.1 ms before clocking the DAC
    localparam INIT_CYCLES = int'(0.15e-3 / CLK_PERIOD);

    localparam FRAME_LEN = WORD_LEN*NUM_CHANNELS;

    enum {RST, RX} state;

    logic           [FRAME_LEN-1:0] rx_data;
    logic [$clog2(INIT_CYCLES)-1:0] clk_counter;
    logic   [$clog2(FRAME_LEN)-1:0] bit_counter;
    
    logic  bit_cycles_addend;
    always_comb begin
        if (bit_counter[4:0] == 5'b0 || bit_counter[0] == 1'b1) begin
            // bit_counter divisible by 32 or not divisible by 2
            bit_cycles_addend = 1'b1;
        end else begin
            bit_cycles_addend = 1'b0;
        end
    end

    assign adc_bclk = (!rst) && (state != RST) && (clk_counter < HALF_BIT_CYCLES);

    always_ff @ (posedge clk) begin
        if (rst) begin
            adc_fsync <= 1'b0;
            adc_shdnz <= 1'b0;
            samples_out <= 0;

            state <= RST;
            rx_data <= 0;
            clk_counter <= 0;
            bit_counter <= 0;
        end else begin
            case (state)
                RST: begin
                    if (clk_counter >= INIT_CYCLES-1) begin
                        adc_shdnz <= 1'b1;
                        adc_fsync <= 1'b1;
                        state <= RX;
                        clk_counter <= 0;
                        bit_counter <= 0;
                    end else begin
                        clk_counter <= clk_counter + 1;
                    end
                end

                RX: begin
                    if (clk_counter >= BIT_CYCLES-1 + bit_cycles_addend) begin
                        if (bit_counter >= FRAME_LEN-1) begin
                            adc_fsync <= 1'b1;
                            bit_counter <= 0;
                            samples_out <= {
                                rx_data[ 31: 16],
                                rx_data[ 63: 48],
                                rx_data[ 95: 80],
                                rx_data[127:112]
                            };
                        end else begin
                            adc_fsync <= 1'b0;
                            bit_counter <= bit_counter + 1;
                        end
                        clk_counter <= 0;
                    end else begin
                        if (clk_counter == HALF_BIT_CYCLES-1) begin
                            rx_data <= {rx_data[FRAME_LEN-2:0], adc_cipo};
                        end
                        clk_counter <= clk_counter + 1;
                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire
