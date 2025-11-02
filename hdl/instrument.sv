`timescale 1ns / 1ps
`default_nettype none

module instrument
    #(
        parameter [6:0] MIDI_KEY
    )
    (
        input wire clk,
        input wire rst,

        input wire   [13:0] sample_period,
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

    logic [16:0] sample_counter;
    logic [16:0] sample_period_x8;
    assign sample_period_x8 = {3'b0, sample_period} << 3;

    always_ff @ (posedge clk) begin
        if (rst) begin
            state <= SETUP;
            addr_start_hold <= 0;
            addr_stop_hold <= 0;
            trigger_hold <= 0;
            sample_counter <= 0;

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

                NOTE_OFF: begin
                    if (valid_trigger) begin
                        addr <= addr_start_hold;
                        addr_valid <= 1;
                        sample_counter <= 0;
                        state <= NOTE_ON;
                    end
                end

                NOTE_ON: begin
                    // Trigger during NOTE_ON: Hold high until next sample.
                    // DRAM receiver expects at most one sample per instrument
                    //  during sample period.

                    if (valid_trigger) begin
                        trigger_hold <= 1;
                    end
                    
                    if (sample_counter == sample_period_x8 - 1) begin
                        if (valid_trigger | trigger_hold) begin
                            addr <= addr_start_hold;
                            addr_valid <= 1;
                            sample_counter <= 0;
                            trigger_hold <= 0;
                        end else if (addr == addr_stop_hold - 1) begin
                            state <= NOTE_OFF;
                        end else begin
                            sample_counter <= 0;
                            addr <= addr + 1;
                            addr_valid <= 1;
                        end
                    end else begin
                        sample_counter <= sample_counter + 1;
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
