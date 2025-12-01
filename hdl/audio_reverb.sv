`timescale 1ns / 1ps
`default_nettype none

// Adapted from Freeverb
// https://github.com/sinshu/freeverb

module audio_reverb
    #(
        parameter CHANNEL=0
    )
    (
        input wire clk,
        input wire rst,

        input wire [9:0] pot_wet,
        input wire [9:0] pot_size,
        input wire [9:0] pot_feedback,

        input wire [15:0] sample_in,
        input wire        sample_in_valid,

        output logic [15:0] sample_out,
        output logic        sample_out_valid
    );

    localparam LBCF_COUNT      = 8;
    localparam APF_COUNT       = 4;
    localparam BRAM_WIDTH      = 18;
    localparam BRAM_DEPTH      = CHANNEL ? 12863 : 12587;
    localparam BRAM_ADDR_WIDTH = $clog2(BRAM_DEPTH);
    localparam MULT_A_WIDTH    = 25;
    localparam MULT_B_WIDTH    = 14;
    localparam MULT_OUT_WIDTH  = MULT_A_WIDTH+MULT_B_WIDTH;

    enum {
        IDLE,
        
        LBCF_RD,
        LBCF_MULT_1_PRE,
        LBCF_MULT_1,
        LBCF_MULT_1_POST,
        LBCF_MULT_2_PRE,
        LBCF_MULT_2,
        LBCF_MULT_2_POST,
        LBCF_WR,

        APF_RD,
        APF_CALC,
        APF_WR,

        OUT
    } state;

    logic [15:0] sample_in_hold;

    logic      [BRAM_WIDTH-1:0] bram_dout;
    logic      [BRAM_WIDTH-1:0] bram_din;
    logic [BRAM_ADDR_WIDTH-1:0] bram_addr;
    logic                       bram_we;

    logic [1:0] bram_rd_counter;

    logic [0:LBCF_COUNT+APF_COUNT][BRAM_ADDR_WIDTH-1:0] bram_addr_offsets;
    logic [BRAM_ADDR_WIDTH-1:0] lbcf_pointers [LBCF_COUNT-1:0];
    logic [BRAM_ADDR_WIDTH-1:0] apf_pointers   [APF_COUNT-1:0];

    logic [$clog2(LBCF_COUNT)-1:0] lbcf_index;
    logic [$clog2( APF_COUNT)-1:0] apf_index;

    logic   [MULT_A_WIDTH-1:0] mult_a;
    logic   [MULT_B_WIDTH-1:0] mult_b;
    logic [MULT_OUT_WIDTH-1:0] mult_out_comb;
    logic [MULT_OUT_WIDTH-1:0] mult_out;
    assign mult_out_comb = $signed(mult_a) * $signed(mult_b);

    // iverilog does not support parameter arrays
    // Use shorter delays for sim
    always_comb begin
`ifdef SYNTHESIS
        if (CHANNEL == 0) begin
            bram_addr_offsets = {
                // LBCF
                BRAM_ADDR_WIDTH'('d0),
                BRAM_ADDR_WIDTH'('d1116),
                BRAM_ADDR_WIDTH'('d2304),
                BRAM_ADDR_WIDTH'('d3581),
                BRAM_ADDR_WIDTH'('d4937),
                BRAM_ADDR_WIDTH'('d6359),
                BRAM_ADDR_WIDTH'('d7850),
                BRAM_ADDR_WIDTH'('d9407),
                // APF
                BRAM_ADDR_WIDTH'('d11024),
                BRAM_ADDR_WIDTH'('d11580),
                BRAM_ADDR_WIDTH'('d12021),
                BRAM_ADDR_WIDTH'('d12362),
                // End
                BRAM_ADDR_WIDTH'('d12587)
            };
        end else begin
            bram_addr_offsets = {
                // LBCF
                BRAM_ADDR_WIDTH'('d0),
                BRAM_ADDR_WIDTH'('d1139),
                BRAM_ADDR_WIDTH'('d2350),
                BRAM_ADDR_WIDTH'('d3650),
                BRAM_ADDR_WIDTH'('d5029),
                BRAM_ADDR_WIDTH'('d6474),
                BRAM_ADDR_WIDTH'('d7988),
                BRAM_ADDR_WIDTH'('d9568),
                // APF
                BRAM_ADDR_WIDTH'('d11208),
                BRAM_ADDR_WIDTH'('d11787),
                BRAM_ADDR_WIDTH'('d12251),
                BRAM_ADDR_WIDTH'('d12615),
                // End
                BRAM_ADDR_WIDTH'('d12863)
            };
        end
`else
        bram_addr_offsets = {
            // LBCF
            BRAM_ADDR_WIDTH'('d0),
            BRAM_ADDR_WIDTH'('d5),
            BRAM_ADDR_WIDTH'('d11),
            BRAM_ADDR_WIDTH'('d18),
            BRAM_ADDR_WIDTH'('d26),
            BRAM_ADDR_WIDTH'('d35),
            BRAM_ADDR_WIDTH'('d45),
            BRAM_ADDR_WIDTH'('d56),
            // APF
            BRAM_ADDR_WIDTH'('d68),
            BRAM_ADDR_WIDTH'('d71),
            BRAM_ADDR_WIDTH'('d75),
            BRAM_ADDR_WIDTH'('d80),
            // End
            BRAM_ADDR_WIDTH'('d86)
        };
`endif
    end

    logic     [BRAM_WIDTH+ 2:0] lbcf_out_accum;
    logic   [MULT_A_WIDTH+ 8:0] lbcf_lpf_out_x1024;
    logic   [MULT_A_WIDTH- 2:0] lbcf_lpf_out_comb;
    logic   [MULT_A_WIDTH- 2:0] lbcf_lpf_out [LBCF_COUNT-1:0]; // Reg
    logic [MULT_OUT_WIDTH- 1:0] lbcf_buf_next_x8192;
    logic [MULT_OUT_WIDTH-14:0] lbcf_buf_next_full;
    logic     [BRAM_WIDTH- 1:0] lbcf_buf_next_clip;
    logic     [BRAM_WIDTH- 1:0] lbcf_buf_next;               // Reg
    always_comb begin
        // LBCF_MULT_1_POST
        lbcf_lpf_out_x1024 =
            $signed({{10{bram_dout[BRAM_WIDTH-1]}}, bram_dout} << 10) +
            $signed(mult_out);
        lbcf_lpf_out_comb = $signed(lbcf_lpf_out_x1024) >>> 10;

        // LBCF_MULT_2_POST
        lbcf_buf_next_x8192 =
            $signed({{13{sample_in_hold[15]}}, sample_in_hold} << 13) +
            $signed(mult_out);
        lbcf_buf_next_full = $signed(lbcf_buf_next_x8192) >>> 13;
    end

    logic [BRAM_WIDTH-2:0] apf_in;
    logic [BRAM_WIDTH-2:0] apf_in_next;
    logic   [BRAM_WIDTH:0] apf_out_full;
    logic [BRAM_WIDTH-2:0] apf_out_clip;
    logic [BRAM_WIDTH-1:0] apf_buf_next;
    always_comb begin
        // APF_CALC
        apf_out_full = $signed(bram_dout) - $signed(apf_in);

        // APF_WR
        apf_buf_next = $signed(apf_in) + ($signed(bram_dout) >>> 1);
    end

    logic [25:0] sample_out_x1024;
    logic [15:0] sample_out_comb;
    always_comb begin
        sample_out_x1024 =
            $signed({{10{sample_in_hold[15]}}, sample_in_hold} << 10) +
            $signed(mult_out);
        sample_out_comb = $signed(sample_out_x1024) >>> 10;
    end

    always_ff @ (posedge clk) begin
        if (rst) begin
            state <= IDLE;
            mult_a <= 0;
            mult_b <= 0;
            mult_out <= 0;
            sample_out <= 0;
            sample_out_valid <= 0;
            sample_in_hold <= 0;

            // BRAM resets
            bram_addr <= 0;
            bram_din <= 0;
            bram_we <= 0;
            bram_rd_counter <= 0;

            // LBCF resets
            for (int i=0; i<LBCF_COUNT; i++) begin
                lbcf_pointers[i] <= bram_addr_offsets[i];
                lbcf_lpf_out[i] <= 0;
            end
            lbcf_index <= 0;
            lbcf_out_accum <= 0;
            lbcf_buf_next <= 0;

            // APF resets
            for (int i=0; i<APF_COUNT; i++) begin
                apf_pointers[i] <= bram_addr_offsets[LBCF_COUNT+i];
            end
            apf_index <= 0;
            apf_in <= 0;
            apf_in_next <= 0;
        end else begin
            case (state)
                IDLE: begin
                    // From: rst or OUT
                    sample_out_valid <= 0;
                    if (sample_in_valid) begin
                        sample_in_hold <= sample_in;
                        state <= LBCF_RD;

                        // Reset LBCF registers
                        lbcf_index <= 0;
                        lbcf_out_accum <= 0;
                        bram_rd_counter <= 0;
                    end
                end

                // Read next sample from LBCF buffer
                // This will be the LBCF output for this time step
                LBCF_RD: begin
                    // From: IDLE or LBCF_WR
                    bram_we <= 0;
                    bram_addr <= lbcf_pointers[lbcf_index];
                    if (bram_rd_counter >= 2) begin
                        state <= LBCF_MULT_1_PRE;
                    end else begin
                        bram_rd_counter <= bram_rd_counter + 1;
                    end
                end

                // Compute feedback LPF output
                LBCF_MULT_1_PRE: begin
                    // From: LBCF_RD
                    mult_a <= $signed(lbcf_lpf_out[lbcf_index]) - $signed(bram_dout);
                    if (pot_feedback == 10'd1023) begin
                        mult_b <= MULT_B_WIDTH'('d1);
                    end else begin
                        mult_b <= {{MULT_B_WIDTH-10{1'b0}}, ~pot_feedback};
                    end
                    lbcf_out_accum <= $signed(lbcf_out_accum) + $signed(bram_dout);
                    state <= LBCF_MULT_1;
                end
                LBCF_MULT_1: begin
                    // From: LBCF_MULT_1_PRE
                    mult_out <= mult_out_comb;
                    state <= LBCF_MULT_1_POST;
                end
                LBCF_MULT_1_POST: begin
                    // From: LBCF_MULT_1
                    lbcf_lpf_out[lbcf_index] <= lbcf_lpf_out_comb;
                    state <= LBCF_MULT_2_PRE;
                end

                // Compute next LBCF buffer input
                LBCF_MULT_2_PRE: begin
                    // From: LBCF_MULT_1_POST
                    mult_a <= $signed(lbcf_lpf_out[lbcf_index]);

                    // pot_size offset keeps feedback gain ~[0.875, 1)
                    // (small room size sounds bad)
                    mult_b <= pot_size + 13'd7160;

                    state <= LBCF_MULT_2;
                end
                LBCF_MULT_2: begin
                    // From: LBCF_MULT_2_PRE
                    mult_out <= mult_out_comb;
                    state <= LBCF_MULT_2_POST;
                end
                LBCF_MULT_2_POST: begin
                    // From: LBCF_MULT_2
                    lbcf_buf_next <= lbcf_buf_next_clip;
                    state <= LBCF_WR;
                end

                // Write to LBCF buffer
                LBCF_WR: begin
                    // From: LBCF_MULT_2_POST
                    bram_we <= 1;
                    bram_din <= lbcf_buf_next;

                    if (lbcf_pointers[lbcf_index] >= bram_addr_offsets[lbcf_index+1]-1) begin
                        lbcf_pointers[lbcf_index] <= bram_addr_offsets[lbcf_index];
                    end else begin
                        lbcf_pointers[lbcf_index] <= lbcf_pointers[lbcf_index] + 1;
                    end

                    if (lbcf_index >= LBCF_COUNT-1) begin
                        apf_index <= 0;
                        state <= APF_RD;
                    end else begin
                        lbcf_index <= lbcf_index + 1;
                        state <= LBCF_RD;
                    end
                    bram_rd_counter <= 0;
                end

                // Read next sample from APF buffer
                APF_RD: begin
                    // From: LBCF_WR or APF_WR
                    bram_we <= 0;

                    bram_addr <= apf_pointers[apf_index];
                    if (bram_rd_counter >= 2) begin
                        state <= APF_CALC;
                    end else begin
                        bram_rd_counter <= bram_rd_counter + 1;
                    end

                    if (apf_index == 0) begin
                        // Sum of LBCF outputs fed into first APF
                        apf_in <= $signed(lbcf_out_accum) >>> 4;
                    end else begin
                        apf_in <= apf_in_next;
                    end
                end

                // Compute next APF buffer input
                APF_CALC: begin
                    // From: APF_RD
                    if (apf_index >= APF_COUNT-1) begin
                        // Wet/dry output mix multiply
                        mult_a <= ($signed(apf_out_clip) >>> 1) - $signed(sample_in_hold);
                        mult_b <= pot_wet;
                    end else begin
                        apf_in_next <= apf_out_clip;
                    end
                    state <= APF_WR;
                end

                // Write to APF buffer
                APF_WR: begin
                    // From: APF_CALC
                    bram_we <= 1;
                    bram_din <= apf_buf_next;

                    if (apf_pointers[apf_index] >= bram_addr_offsets[LBCF_COUNT+apf_index+1]-1) begin
                        apf_pointers[apf_index] <= bram_addr_offsets[LBCF_COUNT+apf_index];
                    end else begin
                        apf_pointers[apf_index] <= apf_pointers[apf_index] + 1;
                    end

                    if (apf_index >= APF_COUNT-1) begin
                        mult_out <= mult_out_comb;
                        state <= OUT;
                    end else begin
                        apf_index <= apf_index + 1;
                        bram_rd_counter <= 0;
                        state <= APF_RD;
                    end
                end

                // Output the wet/dry mixed sample
                OUT: begin
                    // From APF_WR
                    bram_we <= 0;
                    sample_out <= sample_out_comb;
                    sample_out_valid <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

    clipper #(
        .WIDTH_FULL(BRAM_WIDTH+1),
        .WIDTH_CLIP(BRAM_WIDTH-1)
    ) clipper_apf_out (
        .din(apf_out_full),
        .dout(apf_out_clip)
    );

    clipper #(
        .WIDTH_FULL(MULT_OUT_WIDTH-13),
        .WIDTH_CLIP(BRAM_WIDTH)
    ) clipper_lbcf_buf_next (
        .din(lbcf_buf_next_full),
        .dout(lbcf_buf_next_clip)
    );

    xilinx_single_port_ram_read_first #(
        .RAM_WIDTH(BRAM_WIDTH),
        .RAM_DEPTH(BRAM_DEPTH),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
        .INIT_FILE("")
    ) audio_delay_bram (
        .addra(bram_addr),
        .dina(bram_din),
        .clka(clk),
        .wea(bram_we),
        .ena(1'b1),
        .rsta(rst),
        .regcea(1'b1),
        .douta(bram_dout)
    );

endmodule

`default_nettype wire
 
