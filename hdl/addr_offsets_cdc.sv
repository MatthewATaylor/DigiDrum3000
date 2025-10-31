`timescale 1ns / 1ps
`default_nettype none

module addr_offsets_cdc
    #(
        INSTRUMENT_COUNT
    )
    (
        input wire clk_sender,
        input wire clk_receiver,
        input wire rst_sender,
        input wire rst_receiver,

        input wire [23:0] addr_offset_in,
        input wire        addr_offset_in_valid,

        output logic [23:0] addr_offsets [INSTRUMENT_COUNT:0],
        output logic        addr_offsets_valid  // Maintained high
    );

    logic [$clog2(INSTRUMENT_COUNT+1)-1:0] instrument_counter;

    logic        fifo_out_valid;
    logic [23:0] fifo_out;

    always @ (posedge clk_receiver) begin
        if (rst_receiver) begin
            instrument_counter <= 0;
            for (int i=0; i<=INSTRUMENT_COUNT; i++) begin
                addr_offsets[i] <= 24'b0;
            end
            addr_offsets_valid <= 0;
        end else begin
            if (fifo_out_valid && instrument_counter < INSTRUMENT_COUNT) begin
                instrument_counter <= instrument_counter + 1;
                addr_offsets <= {fifo_out, addr_offsets[INSTRUMENT_COUNT:1]};
                if (instrument_counter == INSTRUMENT_COUNT-1) begin
                    addr_offsets_valid <= 1;
                end
            end
        end
    end

    clockdomain_fifo #(
        .DEPTH(16), .WIDTH(24), .PROGFULL_DEPTH(6)
    ) dram_write_fifo (
        .sender_rst(rst_sender),
        .sender_clk(clk_sender),
        .sender_axis_tvalid(addr_offset_in_valid),
        .sender_axis_tready(),
        .sender_axis_tdata(addr_offset_in),
        .sender_axis_tlast(),
        .sender_axis_prog_full(),

        .receiver_clk(clk_receiver),
        .receiver_axis_tvalid(fifo_out_valid),
        .receiver_axis_tready(1),
        .receiver_axis_tdata(fifo_out),
        .receiver_axis_tlast(),
        .receiver_axis_prog_empty()
    );
endmodule

`default_nettype wire

