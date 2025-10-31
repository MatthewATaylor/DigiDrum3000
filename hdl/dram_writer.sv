`timescale 1ns / 1ps
`default_nettype none

module dram_writer
    #(
        INSTRUMENT_COUNT
    )
    (
        input wire clk,
        input wire clk_dram_ctrl,
        input wire clk_pixel,
        input wire rst,
        input wire rst_pixel,
        input wire uart_din,

        input  wire         sample_load_complete,
        output logic [23:0] addr_offsets [INSTRUMENT_COUNT:0],
        output logic        addr_offsets_valid,
        output logic        addr_offsets_valid_pixel,

        input  wire         pixel_valid,
        input  wire  [15:0] pixel_data,
        input  wire         pixel_last,

        output logic         fifo_receiver_axis_tvalid,
        input  wire          fifo_receiver_axis_tready,
        output logic [127:0] fifo_receiver_axis_tdata,
        output logic         fifo_receiver_axis_tlast
    );

    // Synchronize addr_offsets_valid to clk_pixel.
    // From 100 MHz to 74.25 MHz
    // TODO: Clean up addr_offsets_valid and sample_load_complete signals.
    logic addr_offsets_valid_buf [1:0];
    assign addr_offsets_valid_pixel = addr_offsets_valid_buf[0];
    always_ff @ (posedge clk_pixel) begin
        if (rst_pixel) begin
            for (int i=0; i<2; i++) begin
                addr_offsets_valid_buf[i] <= 0;
            end
        end else begin
            addr_offsets_valid_buf <= {addr_offsets_valid, addr_offsets_valid_buf[1]};
        end
    end

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
        .sender_rst(rst_pixel),
        .sender_clk(clk_pixel),
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

    logic video_en;
    assign video_en = addr_offsets_valid_pixel & sample_load_complete;
    
    logic video_en_reg;
    always_ff @ (posedge clk_pixel) begin
        if (rst_pixel) begin
            video_en_reg <= 0;
        end else begin
            if (video_en) begin
                video_en_reg <= 1;
            end
        end
    end

    logic        stacker_in_valid;
    logic [15:0] stacker_in_data;
    logic        stacker_in_last;
    always_comb begin
        if (video_en) begin
            stacker_in_valid = pixel_valid;
            stacker_in_data = pixel_data;
            stacker_in_last = pixel_last;
        end else begin
            stacker_in_valid = sample_axis_tvalid;
            stacker_in_data = sample_axis_tdata;
            stacker_in_last = sample_axis_tlast;
        end
    end

    stacker dram_write_stacker (
        .clk(clk_pixel),

        // One cycle reset on video enable.
        // Clears the stacker to synchronize with the (reset) video_sig_gen.
        .rst(rst_pixel | (video_en & ~video_en_reg)),
        
        .pixel_tvalid(stacker_in_valid),
        .pixel_tready(),
        .pixel_tdata(stacker_in_data),
        .pixel_tlast(stacker_in_last),
        
        .chunk_tvalid(stacker_chunk_axis_tvalid),
        .chunk_tready(stacker_chunk_axis_tready),
        .chunk_tdata(stacker_chunk_axis_tdata),
        .chunk_tlast(stacker_chunk_axis_tlast)
    );

    logic [23:0] addr_offset;
    logic        addr_offset_valid;

    sample_loader #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    ) sample_loader_i (
        .clk_pixel(clk_pixel),
        .rst_pixel(rst_pixel),
        .uart_din(uart_din),

        .addr_offset(addr_offset),
        .addr_offset_valid(addr_offset_valid),
        
        .sample_axis_tvalid(sample_axis_tvalid),
        .sample_axis_tdata(sample_axis_tdata),
        .sample_axis_tlast(sample_axis_tlast)
    );

    addr_offsets_cdc #(
        .INSTRUMENT_COUNT(INSTRUMENT_COUNT)
    ) addr_offsets_cdc_i (
        .clk_sender(clk_pixel),
        .clk_receiver(clk),
        .rst_sender(rst_pixel),
        .rst_receiver(rst),

        .addr_offset_in(addr_offset),
        .addr_offset_in_valid(addr_offset_valid),

        .addr_offsets(addr_offsets),
        .addr_offsets_valid(addr_offsets_valid)
    );

endmodule

`default_nettype wire
