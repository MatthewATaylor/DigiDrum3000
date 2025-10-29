`timescale 1ns / 1ps
`default_nettype none

module sample_mixer
    #(
        parameter INSTRUMENT_COUNT,
        parameter SAMPLE_PERIOD = 2272
    )
    (
        input wire          clk,
        input wire          rst,
        input wire   [15:0] din       [INSTRUMENT_COUNT-1:0],
        input wire          din_valid [INSTRUMENT_COUNT-1:0],
        output logic        din_ready [INSTRUMENT_COUNT-1:0],
        output logic [15:0] dout,
        output logic        dout_valid
    );

    logic prev_rst;  // Assert din_ready when ~rst & prev_rst
    logic [$clog2(SAMPLE_PERIOD)-1:0] sample_counter;

    logic [$clog2(INSTRUMENT_COUNT)-1:0] instr_counter;
    always_ff @ (posedge clk) begin
        if (rst) begin
            instr_counter <= 0;
        end else begin
            if (instr_counter == INSTRUMENT_COUNT-1) begin
                instr_counter <= 0;
            end else begin
                instr_counter <= instr_counter + 1;
            end
        end
    end

    logic [15:0] next_sum;
    assign next_sum = dout + din[instr_counter];

    logic handshake;
    assign handshake = din_valid[instr_counter] & din_ready[instr_counter];

    // The active instrument has din_ready set to active_din_ready
    // Inactive instruments have din_ready set to zero
    logic active_din_ready [INSTRUMENT_COUNT-1:0];
    always_comb begin
        for (int i=0; i<INSTRUMENT_COUNT; i++) begin
            if (i == instr_counter) begin
                din_ready[i] = active_din_ready[i];
            end else begin
                din_ready[i] = 0;
            end
        end
    end

    always_ff @ (posedge clk) begin
        if (rst) begin
            for (int i=0; i<INSTRUMENT_COUNT; i++) begin
                active_din_ready[i] <= 0;
            end
            dout <= 0;
            dout_valid <= 0;

            sample_counter <= 0;
        end else begin
            if (sample_counter == SAMPLE_PERIOD-1) begin
                sample_counter <= 0;
                dout_valid <= 1;
            end else begin
                sample_counter <= sample_counter + 1;
            end

            if (sample_counter == 0) begin
                if (handshake) begin
                    dout <= din[instr_counter];
                end else begin
                    dout <= 0;
                end
            end else begin
                if (handshake) begin
                    if (~next_sum[15] & din[instr_counter][15] & dout[15]) begin
                        // Underflow (negative + negative -> positive)
                        dout <= 16'h8000;
                    end else if (next_sum[15] & ~din[instr_counter][15] & ~dout[15]) begin
                        // Overflow (positive + positive -> negative)
                        dout <= 16'h7fff;
                    end else begin
                        dout <= next_sum;
                    end
                end
            end

            if (dout_valid) begin
                dout_valid <= 0;
            end

            if (sample_counter == SAMPLE_PERIOD-1 || prev_rst) begin
                for (int i=0; i<INSTRUMENT_COUNT; i++) begin
                    active_din_ready[i] <= 1;
                end
            end else if (din_valid[instr_counter]) begin
                active_din_ready[instr_counter] <= 0;
            end
        end

        prev_rst <= rst;
    end
endmodule
`default_nettype wire
