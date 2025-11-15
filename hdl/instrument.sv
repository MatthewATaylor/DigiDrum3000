`timescale 1ns / 1ps
`default_nettype none

module instrument
    #(
        parameter [6:0] MIDI_KEY
    )
    (
        input wire clk,
        input wire rst,

        input wire   [16:0] sample_counter,
        input wire          trigger,
        input wire   [6:0]  midi_key,

        input wire          setup_complete,
        input wire   [23:0] addr_start,
        input wire   [23:0] addr_stop,  // Exclusive

        output logic [23:0] addr,
        output logic        addr_valid,
        
        // Assume addr_ready is asserted at least once every sample_period_x8
        // (i.e. addr not guaranteed to be held at constant value while
        //  addr_valid is asserted)
        input wire          addr_ready  
    );

    enum {SETUP, NOTE_OFF, NOTE_ON} state;

    logic [23:0] addr_start_hold;
    logic [23:0] addr_stop_hold;

    logic trigger_hold;
    logic valid_trigger;
    assign valid_trigger = trigger && (midi_key == MIDI_KEY);

    always_ff @ (posedge clk) begin
        if (rst) begin
            state <= SETUP;
            addr_start_hold <= 0;
            addr_stop_hold <= 0;
            trigger_hold <= 0;

            addr <= 0;
            addr_valid <= 0;
        end else begin
            case (state)
                SETUP: begin
                    if (setup_complete) begin
                        addr_start_hold <= addr_start;
                        addr_stop_hold <= addr_stop;
                        state <= NOTE_OFF;
                    end
                end

                // Only assert addr_valid when sample_counter == 0.
                // This ensures sample_mixer can properly mix instruments
                //  together.

                NOTE_OFF: begin
                    if (valid_trigger) begin
                        if (sample_counter == 0) begin
                            addr_valid <= 1;
                        end else begin
                            trigger_hold <= 1;
                        end
                        addr <= addr_start_hold;
                        state <= NOTE_ON;
                    end
                end

                NOTE_ON: begin
                    if (sample_counter == 0) begin
                        if (valid_trigger || trigger_hold) begin
                            addr <= addr_start_hold;
                            addr_valid <= 1;
                            trigger_hold <= 0;
                        end else if (addr == addr_stop_hold - 1) begin
                            state <= NOTE_OFF;
                        end else begin
                            addr <= addr + 1;
                            addr_valid <= 1;
                        end
                    end else begin
                        if (valid_trigger) begin
                            trigger_hold <= 1;
                        end
                    end
                end
            endcase

            if (addr_valid & addr_ready) begin
                addr_valid <= 0;
            end
        end
    end

endmodule
`default_nettype wire
