`timescale 1ns / 1ps
`default_nettype none

module midi_processor
    (
        input wire clk,
        input wire rst,
        input wire din,
        output logic dout_valid,
        output logic [6:0] key,
        output logic [6:0] velocity
    );

    localparam NOTE_ON_CH10 = 8'b10011001;

    logic uart_dout_valid;
    logic [7:0] uart_dout;

    logic is_reading_data;
    logic data_byte_index;
    logic [15:0] data_bytes;

    assign key = data_bytes[14:8];
    assign velocity = data_bytes[6:0];

    always_ff @ (posedge clk) begin
        if (rst) begin
            dout_valid <= 0;

            is_reading_data <= 0;
            data_byte_index <= 0;
            data_bytes <= 0;
        end else begin
            if (uart_dout_valid) begin
                if (uart_dout[7]) begin
                    // Status byte
                    data_byte_index <= 0;
                    if (uart_dout == NOTE_ON_CH10) begin
                        is_reading_data <= 1;
                    end else begin
                        is_reading_data <= 0;
                    end
                end else if (is_reading_data) begin
                    // Data byte
                    data_byte_index <= ~data_byte_index;
                    data_bytes <= {data_bytes[7:0], uart_dout};
                    if (data_byte_index == 1) begin
                        dout_valid <= 1;
                    end
                end
            end
            if (dout_valid) begin
                dout_valid <= 0;
            end
        end
    end

    uart_receive #(
        .BAUD_RATE(31250)
    ) uart_midi (
        .clk(clk),
        .rst(rst),
        .din(din),
        .dout_valid(uart_dout_valid),
        .dout(uart_dout)
    );
endmodule
`default_nettype wire
