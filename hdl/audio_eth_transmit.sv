`timescale 1ns / 1ps
`default_nettype none

module audio_eth_transmit
    #(
        parameter PAYLOAD_CHANNELS  = 16,
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
        output logic [1:0] eth_txd,
        inout  wire        eth_crsdv,
        inout  wire  [1:0] eth_rxd,

        input  wire sw_latency_timer
    );

    localparam        SAMPLE_FIFO_WIDTH = PAYLOAD_BIT_DEPTH*PAYLOAD_CHANNELS;
    localparam        BUFFER_WIDTH = SAMPLE_FIFO_WIDTH*PAYLOAD_SAMPLES;
    localparam [15:0] RESAMPLER_SP_IN = 16'd1042;

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

    logic [15:0] packet_tx_counter;
    eth_transmit #(
        .PAYLOAD_BUFFER_WIDTH(BUFFER_WIDTH)
    ) eth_transmit_i (
        .eth_clk(eth_clk),
        .eth_rst_n(eth_rst_n),
        .eth_txen(eth_txen),
        .eth_txd(eth_txd),

        .payload_buffer(audio_buffer[~buffer_filling]),
        .payload_buffer_valid(buffer_valid),

        .packet_tx_counter(packet_tx_counter)
    );

    logic [15:0] sample_period_offset;
    logic [15:0] packet_rx_counter;
    eth_receive eth_receive_i (
        .eth_clk(eth_clk),
        .eth_rst_n(eth_rst_n),
        .eth_crsdv(eth_crsdv),
        .eth_rxd(eth_rxd),

        .sample_period_offset(sample_period_offset),
        .packet_rx_counter(packet_rx_counter)
    );


    logic        latency_timer_running;
    logic [31:0] eth_latency_counter;
    logic [15:0] packet_rx_counter_prev;
    logic [15:0] packet_tx_counter_prev;
    always_ff @ (posedge eth_clk) begin
        if (~eth_rst_n) begin
            latency_timer_running <= 1'b0;
            eth_latency_counter <= 32'b0;
            packet_rx_counter_prev <= 16'b0;
            packet_tx_counter_prev <= 16'b0;
        end else begin
            if (latency_timer_running) begin
                if (packet_rx_counter != packet_rx_counter_prev) begin
                    latency_timer_running <= 1'b0;
                end else begin
                    eth_latency_counter <= eth_latency_counter + 32'b1;
                end
            end else begin
                if (packet_tx_counter != packet_tx_counter_prev && sw_latency_timer) begin
                    latency_timer_running <= 1'b1;
                    eth_latency_counter <= 32'b0;
                end
            end
            packet_rx_counter_prev <= packet_rx_counter;
            packet_tx_counter_prev <= packet_tx_counter;
        end
    end


    // Adaptive resampling for clock drift between FPGA and Ethernet audio receiver

    logic [SAMPLE_FIFO_WIDTH-1:0] sample_resampled;
    logic  [PAYLOAD_CHANNELS-1:0] sample_resampled_valid;
    genvar resampler_index;
    generate
        for (resampler_index=0; resampler_index<PAYLOAD_CHANNELS; ++resampler_index) begin
            resampler eth_resampler (
                .clk(eth_clk),
                .rst(~eth_rst_n),
                
                .sample_period_in(RESAMPLER_SP_IN),
                .sample_period_farrow_out((RESAMPLER_SP_IN>>2) + sample_period_offset),

                .sample_in(
                    sample_fifo[
                        PAYLOAD_BIT_DEPTH*(resampler_index+1)-1 : 
                        PAYLOAD_BIT_DEPTH*resampler_index
                    ]
                ),
                .sample_in_valid(sample_fifo_valid),

                .sample_out(
                    sample_resampled[
                        PAYLOAD_BIT_DEPTH*(resampler_index+1)-1 : 
                        PAYLOAD_BIT_DEPTH*resampler_index
                    ]
                ),
                .sample_out_valid(sample_resampled_valid[resampler_index])
            );
        end
    endgenerate


    //logic sample_resampled_valid;
    //resampler_shared #(
    //    .SAMPLE_COUNT(PAYLOAD_CHANNELS)
    //) resampler_shared_i (
    //    .clk(clk),
    //    .rst(rst),

    //    .sample_period_in(RESAMPLER_SP_IN),
    //    .sample_period_farrow_out((RESAMPLER_SP_IN>>2) + sample_period_offset),

    //    .sample_in(sample_fifo),
    //    .sample_in_valid(sample_fifo_valid),

    //    .sample_out(sample_resampled),
    //    .sample_out_valid(sample_resampled_valid)
    //);


    always_ff @ (posedge eth_clk) begin
        if (~eth_rst_n) begin
            buffer_full <= 2'b0;
            buffer_filling <= 1'b0;
            buffer_valid <= 1'b0;
            sample_index <= 0;
        end else begin
            if (sample_resampled_valid[0]) begin
                audio_buffer[buffer_filling] <= {
                    sample_resampled,
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
