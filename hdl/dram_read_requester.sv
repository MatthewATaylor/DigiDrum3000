`timescale 1ns / 1ps
`default_nettype none

module dram_read_requester
    #(
        parameter INSTRUMENT_COUNT,
        parameter [6:0] MIDI_KEYS [0:INSTRUMENT_COUNT-1]
    )
    (
        input wire clk,
        input wire clk_dram_ctrl,
        input wire rst,
        input wire midi_din,

        input wire   [13:0]  sample_period,
        input wire           sample_load_complete,
        input wire   [23:0]  addr_offsets [INSTRUMENT_COUNT:0],
        input wire           addr_offsets_valid,

        output logic         fifo_receiver_axis_tvalid,
        input  wire          fifo_receiver_axis_tready,
        output logic [23:0]  fifo_receiver_axis_tdata,
        output logic         fifo_receiver_axis_tlast,
        
        input  wire  [2:0]   instr_trig_debug
    );

    logic [23:0] instr_addrs       [INSTRUMENT_COUNT-1:0];
    logic        instr_addr_valids [INSTRUMENT_COUNT-1:0];

    logic [23:0] fifo_instr_addr;
    logic        fifo_instr_addr_valid;

    logic [$clog2(INSTRUMENT_COUNT)-1:0] instr_addr_index;

    always_ff @ (posedge clk) begin
        if (rst) begin
            instr_addr_index <= 0;
            fifo_instr_addr <= 0;
            fifo_instr_addr_valid <= 0;
        end else begin
            // Cycle between instr_addrs, assuming FIFO always ready

            if (instr_addr_index == INSTRUMENT_COUNT-1) begin
                instr_addr_index <= 0;
            end else begin
                instr_addr_index <= instr_addr_index + 1;
            end

            fifo_instr_addr <= instr_addrs[instr_addr_index];
            fifo_instr_addr_valid <= instr_addr_valids[instr_addr_index];
        end
    end

    clockdomain_fifo #(
        .DEPTH(128), .WIDTH(38), .PROGFULL_DEPTH(12)
    ) dram_read_addr_fifo (
        .sender_rst(rst),
        .sender_clk(clk),
        .sender_axis_tvalid(fifo_instr_addr_valid),
        .sender_axis_tready(),
        .sender_axis_tdata({fifo_instr_addr, sample_period_hold}),
        .sender_axis_tlast(0),
        .sender_axis_prog_full(),

        .receiver_clk(clk_dram_ctrl),
        .receiver_axis_tvalid(fifo_receiver_axis_tvalid),
        .receiver_axis_tready(fifo_receiver_axis_tready),
        .receiver_axis_tdata(fifo_receiver_axis_tdata),
        .receiver_axis_tlast(fifo_receiver_axis_tlast),
        .receiver_axis_prog_empty()
    );

    logic midi_dout_valid;
    logic [6:0] midi_key;
    logic [6:0] midi_vel;

    midi_processor midi_proc (
        .clk(clk),
        .rst(rst),
        .din(midi_din),
        .dout_valid(midi_dout_valid),
        .key(midi_key),
        .velocity(midi_vel)
    );

    genvar i;
    generate
        for (i=0; i<INSTRUMENT_COUNT; i++) begin
            instrument #(
                .MIDI_KEY(MIDI_KEYS[i])
            ) instr (
                .clk(clk),
                .rst(rst),
               
                .sample_period(sample_period),
                //.trigger(midi_dout_valid),
                //.midi_key(midi_key),
                .trigger(instr_trig_debug[i]),
                .midi_key(MIDI_KEYS[i]),
                
                .setup_complete(sample_load_complete & addr_offsets_valid),
                .addr_start(addr_offsets[i]),
                .addr_stop(addr_offsets[i+1]),

                .addr(instr_addrs[i]),
                .addr_valid(instr_addr_valids[i]),
                .addr_ready(instr_addr_index==i)
            );
        end
    endgenerate

endmodule

`default_nettype wire
