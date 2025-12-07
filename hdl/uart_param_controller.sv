`timescale 1ns / 1ps
`default_nettype none

module uart_param_controller
    (
        input wire clk,
        input wire rst,

        input wire en,
        input wire uart_din,

        output logic [9:0] volume,
        output logic [9:0] pitch,
        output logic [9:0] delay_wet,
        output logic [9:0] delay_rate,
        output logic [9:0] delay_feedback,
        output logic [9:0] reverb_wet,
        output logic [9:0] reverb_size,
        output logic [9:0] reverb_feedback,
        output logic [9:0] filter_quality,
        output logic [9:0] filter_cutoff,
        output logic [9:0] distortion_drive,
        output logic [9:0] crush_pressure,
        output logic       delay_rate_fast
    );

    logic [7:0] uart_dout;
    logic       uart_dout_valid;

    uart_receive #(
        .INPUT_CLOCK_FREQ(100000000),
        .BAUD_RATE(1500000)
    ) uart_receive_param_ctrl (
        .clk(clk),
        .rst(rst | ~en),
        .din(uart_din),
        .dout_valid(uart_dout_valid),
        .dout(uart_dout)
    );

    logic [5:0] uart_dout_hold;
    logic       uart_byte_num;

    logic [3:0] param_key;
    assign param_key = uart_dout_hold[5:2];

    logic [9:0] param_value;
    assign param_value = {uart_dout_hold[1:0], uart_dout};

    always_ff @ (posedge clk) begin
        if (rst | ~en) begin
            volume <= 10'd512;
            pitch <= 10'd512;
            delay_wet <= 10'd512;
            delay_rate <= 10'd512;
            delay_feedback <= 10'd512;
            reverb_wet <= 10'd512;
            reverb_size <= 10'd512;
            reverb_feedback <= 10'd512;
            filter_quality <= 10'd0;
            filter_cutoff <= 10'd1023;
            distortion_drive <= 10'd512;
            crush_pressure <= 10'd0;
            delay_rate_fast <= 1'b0;
       
            uart_dout_hold <= 8'b0;
            uart_byte_num <= 1'b0;
        end else begin
            if (uart_dout_valid) begin
                uart_byte_num <= ~uart_byte_num;
                if (uart_byte_num) begin
                    case (param_key)
                        4'd00: volume <= param_value;
                        4'd01: pitch <= param_value;
                        4'd02: delay_wet <= param_value;
                        4'd03: delay_rate <= param_value;
                        4'd04: delay_feedback <= param_value;
                        4'd05: reverb_wet <= param_value;
                        4'd06: reverb_size <= param_value;
                        4'd07: reverb_feedback <= param_value;
                        4'd08: filter_quality <= param_value;
                        4'd09: filter_cutoff <= param_value;
                        4'd10: distortion_drive <= param_value;
                        4'd11: crush_pressure <= param_value;
                        4'd12: delay_rate_fast <= param_value[9];
                    endcase
                end else begin
                    uart_dout_hold <= uart_dout[5:0];
                end
            end
        end
    end

endmodule

`default_nettype wire

