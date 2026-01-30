`timescale 1ns / 1ps
`default_nettype none

module eth_transmit
    (
        input  wire        eth_clk,
        input  wire        eth_rst_n,
        output logic       eth_txen,
        output logic [1:0] eth_txd
    );

    localparam BITS_PER_CYCLE = 2;

    localparam PREAMBLE_BYTES  = 7;
    localparam PREAMBLE_CYCLES = PREAMBLE_BYTES * 8 / BITS_PER_CYCLE + 3;  // 3 SFD cycles

    localparam        MAC_BYTES    = 6;
    localparam        MAC_CYCLES   = MAC_BYTES * 8 / BITS_PER_CYCLE;
    localparam [47:0] MAC_SRC_ADDR = 48'h02_DE_AD_BE_EF_67;  // AAI address
   
    localparam SIZE_BYTES  = 2;
    localparam SIZE_CYCLES = SIZE_BYTES * 8 / BITS_PER_CYCLE;

    localparam        PAYLOAD_CHANNELS  = 1;//16;
    localparam        PAYLOAD_SAMPLES   = 32;
    localparam        PAYLOAD_BIT_DEPTH = 16;
    localparam [15:0] PAYLOAD_BYTES     = PAYLOAD_CHANNELS * PAYLOAD_SAMPLES * PAYLOAD_BIT_DEPTH;
    localparam        PAYLOAD_CYCLES    = PAYLOAD_BYTES * 8 / BITS_PER_CYCLE;

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
        PAYLOAD,   // 1024 bytes (16 channels * 32 samples * 16 bits)
        FCS        // 4 bytes
    } state;

    // 1050 bytes total = 8400 bits = 84 us @ 100 Mbps
    // 32 samples @ 44100 ksps = 726 us

    logic [$clog2(PAYLOAD_CYCLES)-1:0] cycle_counter;

    logic [$clog2(PAYLOAD_BYTES*8)-1:0] data_index_lsb;
    assign data_index_lsb = (cycle_counter+1) << 1;

    logic        crc_en;
    logic [31:0] crc_dout;
    logic [31:0] crc_dout_complement;
    assign crc_dout_complement = ~crc_dout;

    logic crc_xor_in;

    always_ff @ (posedge eth_clk) begin
        if (~eth_rst_n) begin
            state <= IDLE;
            cycle_counter <= 0;
            crc_en <= 0;
            crc_xor_in <= 1;
            eth_txen <= 0;
            eth_txd <= 2'b00;
        end else begin
            case (state)
                IDLE: begin
                    if (cycle_counter >= IPG_CYCLES - 1) begin
                        state <= PREAMBLE;
                        cycle_counter <= 0;
                        eth_txd <= 2'b01;
                        eth_txen <= 1;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end

                PREAMBLE: begin
                    if (cycle_counter >= PREAMBLE_CYCLES - 1) begin
                        state <= SFD;
                        cycle_counter <= 0;
                        eth_txd <= 2'b11;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end

                SFD: begin
                    state <= MAC_DST;
                    eth_txd <= 2'b11;  // Broadcast address
                    crc_en <= 1;
                    crc_xor_in <= 1;  // Take complement of first 32 bits
                end

                MAC_DST: begin
                    if (cycle_counter >= MAC_CYCLES - 1) begin
                        state <= MAC_SRC;
                        cycle_counter <= 0;
                        eth_txd <= MAC_SRC_ADDR[1:0];
                    end else begin
                        if (cycle_counter >= INIT_COMPLEMENT_CYCLES - 1) begin
                            crc_xor_in <= 0;
                        end
                        cycle_counter <= cycle_counter + 1;
                    end
                end

                MAC_SRC: begin
                    if (cycle_counter >= MAC_CYCLES - 1) begin
                        state <= SIZE;
                        cycle_counter <= 0;
                        eth_txd <= PAYLOAD_BYTES[1:0];
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                        eth_txd <= {
                            MAC_SRC_ADDR[data_index_lsb+1],
                            MAC_SRC_ADDR[data_index_lsb]
                        };
                    end
                end

                SIZE: begin
                    if (cycle_counter >= SIZE_CYCLES - 1) begin
                        state <= PAYLOAD;
                        cycle_counter <= 0;
                        eth_txd <= 2'b10;  // TODO: Replace with real data
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                        eth_txd <= {
                            PAYLOAD_BYTES[data_index_lsb+1],
                            PAYLOAD_BYTES[data_index_lsb]
                        };
                    end
                end

                PAYLOAD: begin
                    if (cycle_counter >= PAYLOAD_CYCLES - 1) begin
                        state <= FCS;
                        cycle_counter <= 0;
                        eth_txd <= {
                            crc_dout_complement[30],
                            crc_dout_complement[31]
                        };
                        crc_en <= 0;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                        eth_txd <= 2'b10;  // TODO: Replace with real data
                    end
                end

                FCS: begin
                    if (cycle_counter >= FCS_CYCLES - 1) begin
                        state <= IDLE;
                        cycle_counter <= 0;
                        eth_txd <= 2'b00;
                    end else begin
                        if (cycle_counter >= FCS_CYCLES - 2) begin
                            eth_txen <= 0;  // Deassert with last di-bit
                        end
                        cycle_counter <= cycle_counter + 1;
                        eth_txd <= {
                            crc_dout_complement[30-data_index_lsb],
                            crc_dout_complement[31-data_index_lsb]
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
        .din(eth_txd ^ {2{crc_xor_in}}),
        .dout(crc_dout)
    );

endmodule

`default_nettype wire
