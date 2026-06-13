`timescale 1ns / 1ps
`default_nettype none

module audio_eth_transmit
    #(
        parameter PAYLOAD_CHANNELS  = 12,
        parameter PAYLOAD_SAMPLES   = 32,
        parameter PAYLOAD_BIT_DEPTH = 16
    )
    (
        input  wire clk,
        input  wire rst,
        input  wire [PAYLOAD_BIT_DEPTH*PAYLOAD_CHANNELS-1:0] sample_in,
        input  wire sample_in_valid,

        input  wire        eth_clk,
        input  wire        eth_rst_n,
        output logic       eth_txen,
        output logic [1:0] eth_txd
    );

    localparam SAMPLE_FIFO_WIDTH = PAYLOAD_BIT_DEPTH*PAYLOAD_CHANNELS;
    localparam BUFFER_WIDTH = SAMPLE_FIFO_WIDTH*PAYLOAD_SAMPLES;

    logic [BUFFER_WIDTH-1:0]            audio_buffer [1:0];
    logic [$clog2(PAYLOAD_SAMPLES)-1:0] sample_index;
    logic [1:0] buffer_full;     // Indicates if either buffer is full
    logic       buffer_filling;  // Indicates buffer currently being filled
    logic       buffer_valid;    // Trigger for eth_transmit

    logic [SAMPLE_FIFO_WIDTH-1:0] sample_fifo;
    logic                         sample_fifo_valid;

    clockdomain_fifo #(
        .DEPTH(16), .WIDTH(SAMPLE_FIFO_WIDTH), .PROGFULL_DEPTH(6)
    ) audio_buffer_fifo (
        .sender_rst(rst),
        .sender_clk(clk),
        .sender_axis_tvalid(sample_in_valid),
        .sender_axis_tready(),
        .sender_axis_tdata(sample_in),
        .sender_axis_tlast(1'b0),
        .sender_axis_prog_full(),

        .receiver_clk(eth_clk),
        .receiver_axis_tvalid(sample_fifo_valid),
        .receiver_axis_tready(1'b1),
        .receiver_axis_tdata(sample_fifo),
        .receiver_axis_tlast(),
        .receiver_axis_prog_empty()
    );

    eth_transmit #(
        .PAYLOAD_BUFFER_WIDTH(BUFFER_WIDTH)
    ) eth_transmit_i (
        .eth_clk(eth_clk),
        .eth_rst_n(eth_rst_n),
        .eth_txen(eth_txen),
        .eth_txd(eth_txd),

        .payload_buffer(audio_buffer[~buffer_filling]),
        .payload_buffer_valid(buffer_valid)
    );

    always_ff @ (posedge eth_clk) begin
        if (~eth_rst_n) begin
            buffer_full <= 2'b0;
            buffer_filling <= 1'b0;
            buffer_valid <= 1'b0;
            sample_index <= 0;
        end else begin
            if (sample_fifo_valid) begin
                audio_buffer[buffer_filling] <= {
                    sample_fifo,
                    audio_buffer[buffer_filling][BUFFER_WIDTH-1:SAMPLE_FIFO_WIDTH]
                };
                
                if (sample_index >= PAYLOAD_SAMPLES - 1) begin
                    buffer_full[buffer_filling] <= 1'b1;
                    buffer_full[~buffer_filling] <= 1'b0;
                    buffer_filling <= ~buffer_filling;
                    buffer_valid <= 1'b1;
                    sample_index <= 0;
                end else begin
                    sample_index <= sample_index + 1;
                end
            end

            if (buffer_valid) begin
                buffer_valid <= 1'b0;
            end
        end
    end
endmodule

`default_nettype wire
