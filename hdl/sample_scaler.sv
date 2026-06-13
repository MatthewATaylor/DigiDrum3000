`timescale 1ns / 1ps
`default_nettype none

// Scale sample received from DRAM by its corresponding velocity

module sample_scaler
    (
        input  wire         clk,
        input  wire         rst,
        input  wire         ready_rst,
        input  wire  [ 6:0] velocity,
        input  wire  [15:0] din,
        input  wire         din_valid,
        output logic [15:0] dout,
        output logic        din_ready
    );

    enum {IDLE, SHIFT} state;

    logic [22:0] din_vel_mult;
    logic  [6:0] velocity_offset;
    assign       velocity_offset = velocity - 7'd64;
    always_comb begin
        if (velocity <= 7'd73) begin
            // Scale by velocity * 0.25 (after bit shift below)
            din_vel_mult =
                $signed(din) *
                $signed({1'b0, velocity});
        end else begin
            // Scale by velocity * 2 (after bit shift below)
            din_vel_mult =
                $signed(din) *
                $signed({1'b0, velocity_offset});
        end
    end

    logic [22:0] din_vel_mult_reg;
    logic [ 6:0] velocity_hold;
    logic [15:0] din_vel_mult_shift;
    always_ff @ (posedge clk) begin
        if (rst) begin
            dout <= 16'b0;
            din_ready <= 1'b1;
            
            state <= IDLE;
            
            din_vel_mult_reg <= 22'b0;
            velocity_hold <= 7'b0;
            din_vel_mult_shift <= 16'b0;
        end else begin
            if (ready_rst) begin
                din_ready <= 1'b1;
            end

            case (state)
                IDLE: begin
                    if (din_valid & din_ready) begin
                        din_ready <= 1'b0;
                        din_vel_mult_reg <= din_vel_mult;
                        velocity_hold <= velocity;
                        state <= SHIFT;
                    end
                end

                SHIFT: begin
                    if (velocity_hold <= 7'd73) begin
                        dout <= $signed(din_vel_mult_reg) >>> 9;
                    end else begin
                        dout <= $signed(din_vel_mult_reg) >>> 6;
                    end
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
