`timescale 1ns / 1ps
`default_nettype none

module eth_transmit
    #(
        parameter PAYLOAD_BUFFER_WIDTH
    )
    (
        input  wire        eth_clk,
        input  wire        eth_rst_n,
        output logic       eth_txen,
        output logic [1:0] eth_txd,

        input  wire  [PAYLOAD_BUFFER_WIDTH-1:0] payload_buffer,
        input  wire                             payload_buffer_valid,

        output logic [15:0] packet_tx_counter
    );

    localparam BITS_PER_CYCLE = 2;

    localparam PREAMBLE_BYTES  = 7;
    localparam PREAMBLE_CYCLES = PREAMBLE_BYTES * 8 / BITS_PER_CYCLE + 3;  // 3 SFD cycles

    localparam        MAC_BYTES    = 6;
    localparam        MAC_CYCLES   = MAC_BYTES * 8 / BITS_PER_CYCLE;
    // Actual MAC address is 48'h02_DE_AD_BE_EF_67
    // Below is rearranged to transmit MS byte first
    localparam [47:0] MAC_SRC_ADDR = 48'h67_EF_BE_AD_DE_02;  // AAI address
   
    localparam SIZE_BYTES  = 2;
    localparam SIZE_CYCLES = SIZE_BYTES * 8 / BITS_PER_CYCLE;

    localparam [15:0] PAYLOAD_BYTES      = PAYLOAD_BUFFER_WIDTH / 8;
    localparam [15:0] PAYLOAD_BYTES_MSBF = {PAYLOAD_BYTES[7:0], PAYLOAD_BYTES[15:8]};
    localparam        PAYLOAD_CYCLES     = PAYLOAD_BYTES * 8 / BITS_PER_CYCLE;

    localparam FCS_BYTES  = 4;
    localparam FCS_CYCLES = FCS_BYTES * 8 / BITS_PER_CYCLE;

    localparam IPG_BYTES  = 12;
    localparam IPG_CYCLES = IPG_BYTES * 8 / BITS_PER_CYCLE;

    localparam INIT_COMPLEMENT_CYCLES = 16;

    enum {
        IDLE,
        PREAMBLE,  // 7 bytes
        SFD,       // 1 byte
        MAC_DST,   // 6 bytes
        MAC_SRC,   // 6 bytes
        SIZE,      // 2 bytes
        PAYLOAD,   // 1024 bytes (16 channels * 32 samples * 2 bytes/sample)
        FCS        // 4 bytes
    } state;

    // 1050 bytes total = 8400 bits = 84 us @ 100 Mbps
    // 32 samples @ 44100 ksps = 726 us

    logic [$clog2(PAYLOAD_CYCLES)-1:0] cycle_counter;

    logic [$clog2(PAYLOAD_BYTES*8)-1:0] data_index_lsb;
    assign data_index_lsb = (cycle_counter+1) << 1;

    // Send next eth_txd value to crc32.
    // This avoids waiting 1 extra clock cycle at the end of crc calculation.
    logic [1:0] eth_txd_next;

    logic        crc_en;
    logic [31:0] crc_dout;
    logic [31:0] crc_dout_complement;
    assign crc_dout_complement = ~crc_dout;

    always_ff @ (posedge eth_clk) begin
        if (~eth_rst_n) begin
            state <= IDLE;
            cycle_counter <= 0;
            crc_en <= 0;
            eth_txen <= 0;
            eth_txd <= 2'b00;
            eth_txd_next <= 2'b00;
            packet_tx_counter <= 16'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (cycle_counter >= IPG_CYCLES - 1 && payload_buffer_valid) begin
                        state <= PREAMBLE;
                        cycle_counter <= 0;
                        eth_txd_next <= 2'b01;
                        packet_tx_counter <= packet_tx_counter + 16'b1;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end

                    eth_txd <= eth_txd_next;
                end

                PREAMBLE: begin
                    if (cycle_counter >= PREAMBLE_CYCLES - 1) begin
                        state <= SFD;
                        cycle_counter <= 0;
                        eth_txd_next <= 2'b11;
                    end else begin
                        eth_txen <= 1;
                        cycle_counter <= cycle_counter + 1;
                    end

                    eth_txd <= eth_txd_next;
                end

                SFD: begin
                    state <= MAC_DST;
                    eth_txd_next <= 2'b11;  // Broadcast address
                    crc_en <= 1;

                    eth_txd <= eth_txd_next;
                end

                MAC_DST: begin
                    if (cycle_counter >= MAC_CYCLES - 1) begin
                        state <= MAC_SRC;
                        cycle_counter <= 0;
                        eth_txd_next <= MAC_SRC_ADDR[1:0];
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end

                    eth_txd <= eth_txd_next;
                end

                MAC_SRC: begin
                    if (cycle_counter >= MAC_CYCLES - 1) begin
                        state <= SIZE;
                        cycle_counter <= 0;
                        eth_txd_next <= PAYLOAD_BYTES_MSBF[1:0];
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                        eth_txd_next <= {
                            MAC_SRC_ADDR[data_index_lsb+1],
                            MAC_SRC_ADDR[data_index_lsb]
                        };
                    end

                    eth_txd <= eth_txd_next;
                end

                SIZE: begin
                    if (cycle_counter >= SIZE_CYCLES - 1) begin
                        state <= PAYLOAD;
                        cycle_counter <= 0;
                        eth_txd_next <= payload_buffer[1:0];
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                        eth_txd_next <= {
                            PAYLOAD_BYTES_MSBF[data_index_lsb+1],
                            PAYLOAD_BYTES_MSBF[data_index_lsb]
                        };
                    end

                    eth_txd <= eth_txd_next;
                end

                PAYLOAD: begin
                    if (cycle_counter >= PAYLOAD_CYCLES - 1) begin
                        state <= FCS;
                        crc_en <= 0;
                        cycle_counter <= 0;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                        eth_txd_next <= {
                            payload_buffer[data_index_lsb+1],
                            payload_buffer[data_index_lsb]
                        };
                    end

                    eth_txd <= eth_txd_next;
                end

                FCS: begin
                    if (cycle_counter >= FCS_CYCLES) begin
                        state <= IDLE;
                        cycle_counter <= 0;
                        eth_txd <= 2'b00;
                        eth_txd_next <= 2'b00;
                        eth_txen <= 0;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                        eth_txd <= {
                            crc_dout_complement[32-data_index_lsb],
                            crc_dout_complement[33-data_index_lsb]
                        };
                    end
                end
            endcase
        end
    end

    crc32 crc32_i (
        .clk(eth_clk),
        .rst(~eth_rst_n | ~eth_txen),  // Reset at end of frame
        .din_valid(crc_en),
        .din(eth_txd_next),
        .dout(crc_dout)
    );

endmodule

`default_nettype wire
