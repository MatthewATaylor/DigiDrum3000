`timescale 1ns / 1ps
`default_nettype none

module dram_reader_audio
    #(
        parameter INSTRUMENT_COUNT
    )
    (
        input wire clk,
        input wire clk_dram_ctrl,
        input wire rst,
        input wire rst_dram_ctrl,

        input  wire   [23:0] addr_offsets         [INSTRUMENT_COUNT:0],
        input  wire          addr_offsets_valid,

        input  wire   [ 6:0] velocity           [INSTRUMENT_COUNT-1:0],

        output logic  [15:0] instrument_samples [INSTRUMENT_COUNT-1:0],
        output logic  [15:0] sample,
        output logic         sample_valid,

        input  wire          fifo_sender_axis_tvalid,
        output logic         fifo_sender_axis_tready,
        input  wire  [167:0] fifo_sender_axis_tdata,

        output logic  [13:0] sample_period
    );

    logic                        unstacker_chunk_axis_tvalid;
    logic [INSTRUMENT_COUNT-1:0] unstacker_chunk_axis_tready;
    logic [167:0]                unstacker_chunk_axis_tdata;
    
    logic         sample_axis_tvalid [INSTRUMENT_COUNT-1:0];
    logic         sample_axis_tready [INSTRUMENT_COUNT-1:0];
    logic [15:0]  sample_axis_tdata  [INSTRUMENT_COUNT-1:0];

    logic [23:0]  data_addr;
    assign data_addr = unstacker_chunk_axis_tdata[151:128];

    logic addr_offsets_valid_reg;
    always_ff @ (posedge clk) begin
        if (rst) begin
            addr_offsets_valid_reg <= 1'b0;
        end else begin
            addr_offsets_valid_reg <= addr_offsets_valid;
        end
    end

    logic [INSTRUMENT_COUNT-1:0] instr_one_hot;
    always_comb begin
        for (int i=0; i<INSTRUMENT_COUNT; i++) begin
            instr_one_hot[i] =
                addr_offsets_valid_reg &&
                (data_addr >= addr_offsets[i]) &&
                (data_addr < addr_offsets[i+1]);
        end
    end

    clockdomain_fifo #(
        .DEPTH(128), .WIDTH(168), .PROGFULL_DEPTH(12)
    ) dram_read_fifo (
        .sender_rst(rst_dram_ctrl),
        .sender_clk(clk_dram_ctrl),
        .sender_axis_tvalid(fifo_sender_axis_tvalid),
        .sender_axis_tready(fifo_sender_axis_tready),
        .sender_axis_tdata(fifo_sender_axis_tdata),
        .sender_axis_tlast(0),
        .sender_axis_prog_full(),

        .receiver_clk(clk),
        .receiver_axis_tvalid(unstacker_chunk_axis_tvalid),
        .receiver_axis_tready((unstacker_chunk_axis_tready & instr_one_hot) != 0),
        .receiver_axis_tdata(unstacker_chunk_axis_tdata),
        .receiver_axis_tlast(),
        .receiver_axis_prog_empty()
    );

    genvar i_unstack;
    generate
        for (i_unstack=0; i_unstack<INSTRUMENT_COUNT; ++i_unstack) begin
            unstacker dram_read_unstacker (
                .clk(clk),
                .rst(rst),

                .chunk_tvalid(unstacker_chunk_axis_tvalid & instr_one_hot[i_unstack]),
                .chunk_tready(unstacker_chunk_axis_tready[i_unstack]),
                .chunk_tdata(unstacker_chunk_axis_tdata[127:0]),
                .chunk_tlast(0),

                .pixel_tvalid(sample_axis_tvalid[i_unstack]),
                .pixel_tready(sample_axis_tready[i_unstack]),
                .pixel_tdata(sample_axis_tdata[i_unstack]),
                .pixel_tlast()
            );
        end
    endgenerate

    logic  scaler_ready_rst;
    assign scaler_ready_rst = sample_valid;

    logic [15:0] scaled_samples [INSTRUMENT_COUNT-1:0];
    genvar i_scale;
    generate
        for (i_scale=0; i_scale<INSTRUMENT_COUNT; ++i_scale) begin
            sample_scaler sample_scaler_i (
                .clk(clk),
                .rst(rst),
                .ready_rst(scaler_ready_rst),
                .velocity(velocity[i_scale]),
                .din(sample_axis_tdata[i_scale]),
                .din_valid(sample_axis_tvalid[i_scale]),
                .dout(scaled_samples[i_scale]),
                .din_ready(sample_axis_tready[i_scale])
             );
        end
    endgenerate

    logic [13:0] current_sample_period;
    logic [13:0] sample_period_hold;
    logic [13:0] sample_counter;
    logic [15:0] scaled_samples_hold [INSTRUMENT_COUNT-1:0];

    assign sample_period = current_sample_period;

    logic [16+INSTRUMENT_COUNT-2:0] sample_sum;
    always_comb begin
        sample_sum = 0;
        for (int i=0; i<INSTRUMENT_COUNT; ++i) begin
            sample_sum = $signed(sample_sum) + $signed(scaled_samples_hold[i]);
        end
    end

    logic [16+INSTRUMENT_COUNT-2:0] sample_clip_in;
    logic [15:0]                    sample_clip_out;
    clipper #(
        .WIDTH_FULL(16+INSTRUMENT_COUNT-1),
        .WIDTH_CLIP(16),
        .RIGHT_SHIFT(0)
    ) mix_clipper (
        .din(sample_clip_in),
        .dout(sample_clip_out)
    );

    always_ff @ (posedge clk) begin
        if (rst) begin
            sample <= 16'b0;
            sample_valid <= 1'b0;

            current_sample_period <= 14'd2500;
            sample_period_hold <= 14'd2500;
            sample_counter <= 14'd0;
            for (int i=0; i<INSTRUMENT_COUNT; ++i) begin
                scaled_samples_hold[i] <= 16'b0;
                instrument_samples[i] <= 16'b0;
            end
        end else begin
            if (unstacker_chunk_axis_tvalid) begin
                // New sample period from DRAM
                sample_period_hold <= unstacker_chunk_axis_tdata[165:152];
            end

            if (sample_counter >= current_sample_period - 1) begin
                sample_counter <= 14'd0;
                scaled_samples_hold <= scaled_samples;

                // Do not update current_sample_period in the middle of the
                // sampling period.
                current_sample_period <= sample_period_hold;
            end else begin
                sample_counter <= sample_counter + 14'd1;
            end

            if (sample_counter == 14'd0) begin
                sample_clip_in <= sample_sum;
            end else if (sample_counter == 14'd1) begin
                sample <= sample_clip_out;
                instrument_samples <= scaled_samples_hold;
                sample_valid <= 1'b1;
            end

            if (sample_valid) begin
                sample_valid <= 1'b0;
            end
        end
    end



    //sample_mixer #(
    //    .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    //) mixer (
    //    .clk(clk),
    //    .rst(rst),
    //    .sample_period_in(sample_period_to_mixer),
    //    .sample_period_out(sample_period),
    //    .velocity(velocity),
    //    .din(sample_axis_tdata),
    //    .din_valid(sample_axis_tvalid),
    //    .din_ready(sample_axis_tready),
    //    .dout(sample),
    //    .dout_valid(sample_valid)
    //);

endmodule

`default_nettype wire
