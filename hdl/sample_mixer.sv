`timescale 1ns / 1ps
`default_nettype none


module sample_mixer
    #(
        parameter INSTRUMENT_COUNT
    )
    (
        input  wire         clk,
        input  wire         rst,
        input  wire  [13:0] sample_period_in,
        output logic [13:0] sample_period_out,
        input  wire  [ 6:0] velocity  [INSTRUMENT_COUNT-1:0],
        input  wire  [15:0] din       [INSTRUMENT_COUNT-1:0],
        input  wire         din_valid [INSTRUMENT_COUNT-1:0],
        output logic        din_ready,
        output logic [15:0] dout,
        output logic        dout_valid
    );


    // Note: We need to give as much time between asserting din_ready and
    // reading from the unstacker so that it can acquire samples.


    // For INSTRUMENT_COUNT cylces before sample_period_out, add together
    // instrument samples after scaling by velocity. Output at the end.
    logic [13:0] sample_counter;
    logic [13:0] instr_index;
    assign       instr_index = sample_period_out - sample_counter - 14'd3;


    logic [22:0] din_vel_mult;
    logic  [6:0] velocity_offset;
    assign       velocity_offset = velocity[instr_index] - 7'd64;
    always_comb begin
        if (velocity[instr_index] <= 7'd73) begin
            // Scale by velocity * 0.25 (after bit shift below)
            din_vel_mult =
                $signed(din[instr_index]) *
                $signed({1'b0, velocity[instr_index]});
        end else begin
            // Scale by velocity * 2 (after bit shift below)
            din_vel_mult =
                $signed(din[instr_index]) *
                $signed({1'b0, velocity_offset});
        end
    end

    logic [15:0] din_vel_mult_shift;
    logic        din_valid_buf;
    always_ff @ (posedge clk) begin
        if (rst) begin
            din_vel_mult_shift <= 0;
            din_valid_buf <= 0;
        end else begin
            if (velocity[instr_index] <= 7'd73) begin
                din_vel_mult_shift <= $signed(din_vel_mult) >>> 9;
            end else begin
                din_vel_mult_shift <= $signed(din_vel_mult) >>> 6;
            end
            din_valid_buf <= din_valid[instr_index];
        end
    end

    logic [16:0] next_sum;
    assign       next_sum = $signed(dout) + $signed(din_vel_mult_shift);
    logic [15:0] next_sum_clip;
    clipper #(
        .WIDTH_FULL(17),
        .WIDTH_CLIP(16),
        .RIGHT_SHIFT(0)
    ) mix_clipper (
        .din(next_sum),
        .dout(next_sum_clip)
    );


    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_period_out <= sample_period_in;
            sample_counter <= 0;
            din_ready <= 1;
            dout <= 0;
            dout_valid <= 0;
        end else begin
            if (sample_counter >= sample_period_out-1) begin
                sample_counter <= 0;
                din_ready <= 1;
                dout <= 0;
                sample_period_out <= sample_period_in;  // Only change sample_period at end of cycle
            end else begin
                sample_counter <= sample_counter + 1;
            end

            if (sample_counter > sample_period_out-INSTRUMENT_COUNT-1 && sample_counter <= sample_period_out-2) begin
                // 1 cycle delay to perform multiplication
                // din_valid_buf is delayed din_valid[instr_index]
                if (din_valid_buf) begin
                    dout <= next_sum_clip;
                end
            end
            if (sample_counter == sample_period_out-2) begin
                dout_valid <= 1;
            end

            if (dout_valid) begin
                dout_valid <= 0;
            end
            if (din_ready) begin
                din_ready <= 0;
            end
        end
    end

endmodule

`default_nettype wire
