`timescale 1ns / 1ps
`default_nettype none

module sample_mixer
    #(
        parameter INSTRUMENT_COUNT
    )
    (
        input wire          clk,
        input wire          rst,
        input wire   [13:0] sample_period,
        input wire   [ 6:0] velocity  [INSTRUMENT_COUNT-1:0],
        input wire   [15:0] din       [INSTRUMENT_COUNT-1:0],
        input wire          din_valid [INSTRUMENT_COUNT-1:0],
        output logic        din_ready [INSTRUMENT_COUNT-1:0],
        output logic [15:0] dout,
        output logic        dout_valid
    );

    logic prev_rst;  // Assert din_ready when ~rst & prev_rst
    logic [13:0] sample_counter;

    // Index a particular instrument each clock cycle.
    // Look ahead one cycle for the multiplier.
    logic [$clog2(INSTRUMENT_COUNT)-1:0] instr_counter_next;
    logic [$clog2(INSTRUMENT_COUNT)-1:0] instr_counter;
    always_ff @ (posedge clk) begin
        if (rst) begin
            instr_counter_next <= 0;
            instr_counter <= INSTRUMENT_COUNT-1;
        end else begin
            if (instr_counter_next == INSTRUMENT_COUNT-1) begin
                instr_counter_next <= 0;
            end else begin
                instr_counter_next <= instr_counter_next + 1;
            end
            instr_counter <= instr_counter_next;
        end
    end

    logic [22:0] din_vel_mult;
    always_ff @ (posedge clk) begin
        if (rst) begin
            din_vel_mult <= 0;
        end else begin
            din_vel_mult <=
                $signed(din[instr_counter_next]) *
                $signed({1'b0, velocity[instr_counter_next]});
        end
    end

    logic [15:0] din_vel_mult_shift;
    assign din_vel_mult_shift = $signed(din_vel_mult) >>> 7;

    logic [16:0] next_sum;
    assign next_sum = $signed(dout) + $signed(din_vel_mult_shift);

    logic [15:0] next_sum_clip;
    clipper #(
        .WIDTH_FULL(17),
        .WIDTH_CLIP(16),
        .RIGHT_SHIFT(0)
    ) mix_clipper (
        .din(next_sum),
        .dout(next_sum_clip)
    );

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
            if (sample_counter >= sample_period-1) begin
                sample_counter <= 0;
                dout_valid <= 1;
            end else begin
                sample_counter <= sample_counter + 1;
            end

            if (sample_counter == 0) begin
                if (handshake) begin
                    dout <= din_vel_mult_shift;
                end else begin
                    dout <= 0;
                end
            end else begin
                if (handshake) begin
                    dout <= next_sum_clip;
                end
            end

            if (dout_valid) begin
                dout_valid <= 0;
            end

            if ((sample_counter >= sample_period-1) || prev_rst) begin
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
