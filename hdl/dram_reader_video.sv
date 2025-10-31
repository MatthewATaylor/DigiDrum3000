`timescale 1ns / 1ps
`default_nettype none

module dram_reader_video
    (
        input wire clk_pixel,
        input wire clk_dram_ctrl,
        input wire rst_pixel,
        input wire rst_dram_ctrl,

        input wire [10:0] h_count_hdmi,
        input wire [9:0]  v_count_hdmi,
        input wire        active_draw_hdmi,

        output logic [15:0]  pixel,

        input  wire          fifo_sender_axis_tvalid,
        output logic         fifo_sender_axis_tready,
        input  wire  [127:0] fifo_sender_axis_tdata,
        input  wire          fifo_sender_axis_tlast,
        output logic         fifo_sender_axis_af
    );

    localparam H_COUNT_MAX = 1279;
    localparam V_COUNT_MAX = 719;

    logic         unstacker_chunk_axis_tvalid;
    logic         unstacker_chunk_axis_tready;
    logic [127:0] unstacker_chunk_axis_tdata;
    logic         unstacker_chunk_axis_tlast;

    clockdomain_fifo #(
        .DEPTH(128), .WIDTH(128), .PROGFULL_DEPTH(12)
    ) dram_read_fifo (
        .sender_rst(rst_dram_ctrl),
        .sender_clk(clk_dram_ctrl),
        .sender_axis_tvalid(fifo_sender_axis_tvalid),
        .sender_axis_tready(fifo_sender_axis_tready),
        .sender_axis_tdata(fifo_sender_axis_tdata),
        .sender_axis_tlast(fifo_sender_axis_tlast),
        .sender_axis_prog_full(fifo_sender_axis_af),

        .receiver_clk(clk_pixel),
        .receiver_axis_tvalid(unstacker_chunk_axis_tvalid),
        .receiver_axis_tready(unstacker_chunk_axis_tready),
        .receiver_axis_tdata(unstacker_chunk_axis_tdata),
        .receiver_axis_tlast(unstacker_chunk_axis_tlast),
        .receiver_axis_prog_empty()
    );

    logic        pixel_tvalid;
    logic        pixel_tready;
    logic [15:0] pixel_tdata;
    logic        pixel_tlast;

    unstacker dram_read_unstacker (
        .clk(clk_pixel),
        .rst(rst_pixel),

        .chunk_tvalid(unstacker_chunk_axis_tvalid),
        .chunk_tready(unstacker_chunk_axis_tready),
        .chunk_tdata(unstacker_chunk_axis_tdata),
        .chunk_tlast(unstacker_chunk_axis_tlast),

        .pixel_tvalid(pixel_tvalid),
        .pixel_tready(pixel_tready),
        .pixel_tdata(pixel_tdata),
        .pixel_tlast(pixel_tlast)
    );

    always_comb begin
        if (pixel_tlast) begin
            pixel_tready = (h_count_hdmi == H_COUNT_MAX) && (v_count_hdmi == V_COUNT_MAX);
        end else begin
            pixel_tready = active_draw_hdmi;
        end
    end

    assign pixel = pixel_tvalid ? pixel_tdata : 16'b11111_000000_00000;

endmodule

`default_nettype wire
