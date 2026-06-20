`timescale 1ns / 1ps
`default_nettype none

module audio_eth_transmit_debug
    #(
        parameter PAYLOAD_CHANNELS = 16,
        parameter PAYLOAD_FRAMES = 32,
        parameter PAYLOAD_BIT_DEPTH = 16
    )
    (
        input  wire        eth_clk,
        input  wire        eth_rst_n,
        input  wire        sample_valid_debug,
        input  wire [16*16-1:0] sample_resampled,
        output logic       eth_txen,
        output logic [1:0] eth_txd,
        inout  wire        eth_crsdv,
        inout  wire  [1:0] eth_rxd
    );

    localparam        PAYLOAD_SAMPLES = PAYLOAD_CHANNELS*PAYLOAD_FRAMES;
    localparam        SAMPLE_FIFO_WIDTH = PAYLOAD_BIT_DEPTH*PAYLOAD_CHANNELS;
    localparam [15:0] RESAMPLER_SP_IN = 16'd1042;

    logic       buffer_filling;     // Indicates buffer currently being filled
    logic       buffer_filling_buf;
    logic       buffer_valid;       // Trigger for eth_transmit
    logic       buffer_valid_buf;

    logic [PAYLOAD_BIT_DEPTH-1:0] buffer_douts [1:0];

    logic [SAMPLE_FIFO_WIDTH-1:0] sample_fifo;
    logic                         sample_fifo_valid;

    logic                        [15:0] packet_tx_counter;
    logic [$clog2(PAYLOAD_SAMPLES)-1:0] buffer_addr_from_eth;
    eth_transmit #(
        .PAYLOAD_BUFFER_DEPTH(PAYLOAD_SAMPLES),
        .PAYLOAD_BIT_DEPTH(PAYLOAD_BIT_DEPTH)
    ) eth_transmit_i (
        .eth_clk(eth_clk),
        .eth_rst_n(eth_rst_n),
        .eth_txen(eth_txen),
        .eth_txd(eth_txd),

        .payload_buffer_addr(buffer_addr_from_eth),
        .payload_buffer_dout(buffer_douts[~buffer_filling]),
        .payload_buffer_valid(buffer_valid),

        .packet_tx_counter(packet_tx_counter)
    );

    logic                                 write_state;
    logic         [SAMPLE_FIFO_WIDTH-1:0] sample_resampled_hold;
    logic  [$clog2(PAYLOAD_CHANNELS)-1:0] channel_index;
    logic   [$clog2(PAYLOAD_SAMPLES)-1:0] buffer_write_addr;
    logic         [PAYLOAD_BIT_DEPTH-1:0] buffer_din;
    logic                           [1:0] buffer_wens;
    always_ff @ (posedge eth_clk) begin
        if (~eth_rst_n) begin
            buffer_filling <= 1'b0;
            buffer_filling_buf <= 1'b0;
            buffer_valid <= 1'b0;
            buffer_valid_buf <= 1'b0;

            write_state <= 1'b0;
            sample_resampled_hold <= 0;
            channel_index <= 0;
            buffer_write_addr <= PAYLOAD_SAMPLES-1;
            buffer_din <= 0;
            buffer_wens <= 2'b0;
        end else begin
            if (write_state) begin
                sample_resampled_hold <= sample_resampled_hold >> PAYLOAD_BIT_DEPTH;

                buffer_write_addr <= buffer_write_addr + 1;
                buffer_din <= sample_resampled_hold[PAYLOAD_BIT_DEPTH-1:0];
                
                if (channel_index >= PAYLOAD_CHANNELS-1) begin
                    // Finished writing current frame of samples
                    write_state <= 1'b0;
                end else begin
                    channel_index <= channel_index + 1;
                end

                if (buffer_write_addr >= PAYLOAD_SAMPLES-2) begin
                    // Entire buffer is written
                    buffer_valid_buf <= 1'b1;
                    buffer_filling_buf <= ~buffer_filling;
                end
            end else begin
                // Idle state (waiting for next frame of samples)
                if (sample_valid_debug) begin
                    write_state <= 1'b1;
                    sample_resampled_hold <= sample_resampled >> PAYLOAD_BIT_DEPTH;
                    channel_index <= 1;

                    buffer_write_addr <= buffer_write_addr + 1;
                    buffer_din <= sample_resampled[PAYLOAD_BIT_DEPTH-1:0];
                    buffer_wens[buffer_filling] <= 1'b1;
                    buffer_wens[~buffer_filling] <= 1'b0;
                end else begin
                    buffer_wens <= 2'b0;
                end
            end

            if (buffer_valid_buf) begin
                buffer_valid_buf <= 1'b0;
            end
            buffer_valid <= buffer_valid_buf;
            buffer_filling <= buffer_filling_buf;
        end
    end

    genvar buf_index;
    generate
        for (buf_index=0; buf_index<2; ++buf_index) begin
            xilinx_single_port_ram_read_first #(
                .RAM_WIDTH(PAYLOAD_BIT_DEPTH),
                .RAM_DEPTH(PAYLOAD_SAMPLES),
                .RAM_PERFORMANCE("HIGH_PERFORMANCE")
            ) eth_buffer_bram (
                .addra(buf_index == buffer_filling ? buffer_write_addr : buffer_addr_from_eth),
                .dina(buffer_din),
                .clka(eth_clk),
                .wea(buffer_wens[buf_index]),
                .ena(1'b1),
                .rsta(~eth_rst_n),
                .regcea(1'b1),
                .douta(buffer_douts[buf_index])
            );
        end
    endgenerate

endmodule

`default_nettype wire
