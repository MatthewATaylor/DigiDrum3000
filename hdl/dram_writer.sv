`timescale 1ns / 1ps
`default_nettype none

module dram_writer
    #(
        INSTRUMENT_COUNT
    )
    (
        input wire clk,
        input wire clk_dram_ctrl,
        input wire rst,
        input wire uart_din,

        output logic [23:0] addr_starts [INSTRUMENT_COUNT:0],

        output logic         fifo_receiver_axis_tvalid,
        input  wire          fifo_receiver_axis_tready,
        output logic [127:0] fifo_receiver_axis_tdata,
        output logic         fifo_receiver_axis_tlast
    );

    logic         stacker_chunk_axis_tvalid;
    logic         stacker_chunk_axis_tready;
    logic [127:0] stacker_chunk_axis_tdata;
    logic         stacker_chunk_axis_tlast;
    
    logic        sample_axis_tvalid;
    logic [15:0] sample_axis_tdata;
    logic        sample_axis_tlast;

    clockdomain_fifo #(
        .DEPTH(128), .WIDTH(128), .PROGFULL_DEPTH(12)
    ) dram_write_fifo (
        .sender_rst(rst),
        .sender_clk(clk),
        .sender_axis_tvalid(stacker_chunk_axis_tvalid),
        .sender_axis_tready(stacker_chunk_axis_tready),
        .sender_axis_tdata(stacker_chunk_axis_tdata),
        .sender_axis_tlast(stacker_chunk_axis_tlast),
        .sender_axis_prog_full(),

        .receiver_clk(clk_dram_ctrl),
        .receiver_axis_tvalid(fifo_receiver_axis_tvalid),
        .receiver_axis_tready(fifo_receiver_axis_tready),
        .receiver_axis_tdata(fifo_receiver_axis_tdata),
        .receiver_axis_tlast(fifo_receiver_axis_tlast),
        .receiver_axis_prog_empty()
    );

    stacker dram_write_stacker (
        .clk(clk),
        .rst(rst),
        
        .pixel_tvalid(sample_axis_tvalid),
        .pixel_tready(),
        .pixel_tdata(sample_axis_tdata),
        .pixel_tlast(sample_axis_tlast),
        
        .chunk_tvalid(stacker_chunk_axis_tvalid),
        .chunk_tready(stacker_chunk_axis_tready),
        .chunk_tdata(stacker_chunk_axis_tdata),
        .chunk_tlast(stacker_chunk_axis_tlast)
    );

    sample_loader #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    ) sample_loader_i (
        .clk(clk),
        .rst(rst),
        .uart_din(uart_din),

        .addr_starts(addr_starts),
        
        .sample_axis_tvalid(sample_axis_tvalid),
        .sample_axis_tdata(sample_axis_tdata),
        .sample_axis_tlast(sample_axis_tlast)
    );

endmodule

`default_nettype wire
