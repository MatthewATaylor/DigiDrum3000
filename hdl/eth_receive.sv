`timescale 1ns / 1ps
`default_nettype none

module eth_receive
    (
        input  wire         eth_clk,
        input  wire         eth_rst_n,
        inout  wire         eth_crsdv,
        inout  wire   [1:0] eth_rxd,

        output logic [15:0] sample_period_offset,
        output logic [15:0] packet_rx_counter
    );

    localparam BITS_PER_CYCLE = 2;

    localparam PREAMBLE_BYTES  = 8;
    localparam PREAMBLE_CYCLES = PREAMBLE_BYTES * 8 / BITS_PER_CYCLE;

    localparam MAC_BYTES  = 6;
    localparam MAC_CYCLES = MAC_BYTES * 8 / BITS_PER_CYCLE;
    // Actual MAC address is 48'h02_DE_AD_BE_EF_67
    // Below is rearranged for receiving MS byte, LS bit first
    localparam [47:0] MAC_DST_ADDR = 48'h67_EF_BE_AD_DE_02;  // AAI address
   
    localparam SIZE_BYTES  = 2;
    localparam SIZE_CYCLES = SIZE_BYTES * 8 / BITS_PER_CYCLE;

    localparam PAD_BYTES    = 44;  // Payload padding (46 byte minimum payload size)
    localparam PAD_CYCLES   = PAD_BYTES * 8 / BITS_PER_CYCLE;

    localparam PAYLOAD_BYTES  = 2;
    localparam PAYLOAD_CYCLES = PAYLOAD_BYTES * 8 / BITS_PER_CYCLE;


    // Configure Ethernet PHY as 100Base-TX full-duplex
    assign eth_crsdv = eth_rst_n ? 1'bZ  : 1'b0;
    assign eth_rxd   = eth_rst_n ? 2'bZZ : 2'b11;


    enum {
        IDLE,
        PREAMBLE,  //  8 bytes (preamble + SFD)
        MAC_DST,   //  6 bytes
        MAC_SRC,   //  6 bytes
        SIZE,      //  2 bytes
        PAD,       // 44 bytes
        PAYLOAD,   //  2 bytes
        AWAIT_END
    } state;

    logic [$clog2(PAD_CYCLES)-1:0] cycle_counter;

    logic [47:0] mac_dst_received;
    logic [47:0] mac_dst_received_next;
    assign       mac_dst_received_next = {eth_rxd, mac_dst_received[47:2]};

    logic [15:0] payload_received;
    logic [15:0] payload_received_next;
    assign       payload_received_next = {eth_rxd, payload_received[15:2]};

    logic eth_crsdv_prev;

    always_ff @ (posedge eth_clk) begin
        if (~eth_rst_n) begin
            sample_period_offset <= 16'b0;
            packet_rx_counter <= 16'b0;

            state <= IDLE;
            cycle_counter <= 0;
            mac_dst_received <= 48'b0;
            payload_received <= 16'b0;
            eth_crsdv_prev <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    if (eth_crsdv && eth_rxd == 2'b01) begin
                        // We are beginning to receive the preamble of a frame
                        state <= PREAMBLE;
                        cycle_counter <= 1;
                    end
                end

                PREAMBLE: begin
                    if (cycle_counter >= PREAMBLE_CYCLES - 1) begin
                        state <= MAC_DST;
                        cycle_counter <= 0;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end

                MAC_DST: begin
                    if (cycle_counter >= MAC_CYCLES - 1) begin
                        if (mac_dst_received_next != MAC_DST_ADDR) begin
                            state <= IDLE;
                        end else begin
                            state <= MAC_SRC;
                        end
                        cycle_counter <= 0;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end

                    mac_dst_received <= mac_dst_received_next;
                end

                MAC_SRC: begin
                    if (cycle_counter >= MAC_CYCLES - 1) begin
                        state <= SIZE;
                        cycle_counter <= 0;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end

                SIZE: begin
                    if (cycle_counter >= SIZE_CYCLES - 1) begin
                        state <= PAD;
                        cycle_counter <= 0;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end

                PAD: begin
                    if (eth_rxd != 2'b00) begin
                        // Only accept all-zero padding to filter out unwanted packets.
                        state <= IDLE;
                    end else begin
                        if (cycle_counter >= PAD_CYCLES - 1) begin
                            state <= PAYLOAD;
                            cycle_counter <= 0;
                        end else begin
                            cycle_counter <= cycle_counter + 1;
                        end
                    end
                end

                PAYLOAD: begin
                    if (cycle_counter >= PAYLOAD_CYCLES - 1) begin
                        sample_period_offset <= {
                            payload_received_next[7:0],
                            payload_received_next[15:8]
                        };
                        packet_rx_counter <= packet_rx_counter + 1;

                        state <= AWAIT_END;
                        cycle_counter <= 0;
                        eth_crsdv_prev <= 1'b1;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end

                    payload_received <= payload_received_next;
                end

                AWAIT_END: begin
                    if (~eth_crsdv & ~eth_crsdv_prev) begin
                        // Two low crsdv bits in a row (no longer receiving data)
                        state <= IDLE;
                    end
                    eth_crsdv_prev <= eth_crsdv;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
