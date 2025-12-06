`timescale 1ns / 1ps
`default_nettype none

module sample_loader
    #(
        INSTRUMENT_COUNT
    )
    (
        input  wire  clk_pixel,
        input  wire  rst_pixel,
        input  wire  uart_din,

        // Start address of each instrument + video (sent serially)
        output logic [23:0] addr_offset,
        output logic        addr_offset_valid,

        output logic        sample_axis_tvalid,
        output logic [15:0] sample_axis_tdata,
        output logic        sample_axis_tlast
    );

    logic        uart_dout_valid;
    logic [7:0]  uart_dout;

    logic [1:0]  sample_size_byte_num;
    logic [23:0] sample_size;
    logic        sample_byte_num;
    logic [23:0] sample_counter;
    logic [$clog2(INSTRUMENT_COUNT+1)-1:0] instrument_counter;

    logic [23:0] total_sample_counter;

    uart_receive #(
        .INPUT_CLOCK_FREQ(74250000),
        //.BAUD_RATE(115200)
        .BAUD_RATE(1500000)
    ) sample_load_uart (
        .clk(clk_pixel),
        .rst(rst_pixel),
        .din(uart_din),
        .dout_valid(uart_dout_valid),
        .dout(uart_dout)
    );

    always_ff @ (posedge clk_pixel) begin
        if (rst_pixel) begin
            sample_size_byte_num <= 0;
            sample_size <= 0;
            sample_byte_num <= 0;
            sample_counter <= 0;
            instrument_counter <= 0;

            total_sample_counter <= 0;
            
            addr_offset <= 0;
            addr_offset_valid <= 0;
            sample_axis_tvalid <= 0;
            sample_axis_tdata <= 0;
            sample_axis_tlast <= 0;
        end else begin
            if (uart_dout_valid && instrument_counter < INSTRUMENT_COUNT) begin
                if (sample_size_byte_num < 3) begin
                    // LSB first
                    sample_size <= {uart_dout, sample_size[23:8]};
                    sample_size_byte_num <= sample_size_byte_num + 1;

                    // Reset sample data registers
                    sample_byte_num <= 0;
                    sample_counter <= 0;
                end else begin
                    // Reading sample data
                    if (sample_byte_num) begin
                        // Second byte of sample (MSB)
                        sample_axis_tvalid <= 1;
                        sample_counter <= sample_counter + 1;
                        total_sample_counter <= total_sample_counter + 1;
                        if (sample_counter == sample_size - 1) begin
                            sample_size_byte_num <= 0;
                            instrument_counter <= instrument_counter + 1;
                            addr_offset <= (total_sample_counter + 1) >> 3;
                            addr_offset_valid <= 1;
                            if (instrument_counter == INSTRUMENT_COUNT - 1) begin
                                sample_axis_tlast <= 1;
                            end
                        end
                    end
                    sample_byte_num <= ~sample_byte_num;
                    sample_axis_tdata <= {uart_dout, sample_axis_tdata[15:8]};
                end
            end

            if (sample_axis_tvalid) begin
                sample_axis_tvalid <= 0;
            end
            if (sample_axis_tlast) begin
                sample_axis_tlast <= 0;
            end
            if (addr_offset_valid) begin
                addr_offset_valid <= 0;
            end
        end
    end
endmodule

`default_nettype wire
