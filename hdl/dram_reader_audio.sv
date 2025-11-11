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

        input  wire  [13:0]  sample_period,
        input  wire  [23:0]  addr_offsets [INSTRUMENT_COUNT:0],
        input  wire          addr_offsets_valid,
        output logic [15:0]  instrument_samples [INSTRUMENT_COUNT-1:0],
        output logic [15:0]  sample,
        output logic         sample_valid,

        input  wire          fifo_sender_axis_tvalid,
        output logic         fifo_sender_axis_tready,
        input  wire  [151:0] fifo_sender_axis_tdata
    );

    logic                        unstacker_chunk_axis_tvalid;
    logic [INSTRUMENT_COUNT-1:0] unstacker_chunk_axis_tready;
    logic [151:0]                unstacker_chunk_axis_tdata;
    
    logic         sample_axis_tvalid [INSTRUMENT_COUNT-1:0];
    logic         sample_axis_tready [INSTRUMENT_COUNT-1:0];
    logic [15:0]  sample_axis_tdata  [INSTRUMENT_COUNT-1:0];
    assign instrument_samples = sample_axis_tdata;

    logic [23:0]  data_addr;
    assign data_addr = unstacker_chunk_axis_tdata[151:128];
   
    logic [INSTRUMENT_COUNT-1:0] instr_one_hot;
    always_comb begin
        for (int i=0; i<INSTRUMENT_COUNT; i++) begin
            instr_one_hot[i] =
                addr_offsets_valid &&
                (data_addr >= addr_offsets[i]) &&
                (data_addr < addr_offsets[i+1]);
        end
    end

    clockdomain_fifo #(
        .DEPTH(128), .WIDTH(152), .PROGFULL_DEPTH(12)
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

    genvar i;
    generate
        for (i=0; i<INSTRUMENT_COUNT; i++) begin
            unstacker dram_read_unstacker (
                .clk(clk),
                .rst(rst),

                .chunk_tvalid(unstacker_chunk_axis_tvalid & instr_one_hot[i]),
                .chunk_tready(unstacker_chunk_axis_tready[i]),
                .chunk_tdata(unstacker_chunk_axis_tdata[127:0]),
                .chunk_tlast(0),

                .pixel_tvalid(sample_axis_tvalid[i]),
                .pixel_tready(sample_axis_tready[i]),
                .pixel_tdata(sample_axis_tdata[i]),
                .pixel_tlast()
            );
        end
    endgenerate

    sample_mixer #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    ) mixer (
        .clk(clk),
        .rst(rst),
        .sample_period(sample_period),
        .din(sample_axis_tdata),
        .din_valid(sample_axis_tvalid),
        .din_ready(sample_axis_tready),
        .dout(sample),
        .dout_valid(sample_valid)
    );

endmodule

`default_nettype wire
