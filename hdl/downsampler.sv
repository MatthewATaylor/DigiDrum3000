`timescale 1ns / 1ps
`default_nettype none

`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else  /* ! SYNTHESIS */
`define FPATH(X) `"../data/X`"
`endif  /* ! SYNTHESIS */

// Polyphase 4:1 downsampler
module downsampler
    (
        input  wire         clk,
        input  wire         rst,
        input  wire  [15:0] sample_in,
        input  wire         sample_in_valid,  // Expects valid every 2272/4 clock cycles
        output logic [15:0] sample_out,
        output logic        sample_out_valid
    );

    localparam TAPS = 512;
    localparam BANKS = TAPS/4;
    localparam BUFFER_DEPTH = TAPS;
    
    logic [$clog2(TAPS)-1:0]  buf_addr;
    logic                     buf_we;
    logic [15:0]              buf_din;
    logic [15:0]              buf_dout;
    logic [$clog2(TAPS)-1:0]  buf_start;

    logic [43:0]              accum;

    logic [1:0]               sample_in_counter;

    logic [$clog2(TAPS)-1:0]  filter_index;
    logic [17:0]              filter_data;

    logic [1:0]               coeff_counter;
    logic [$clog2(BANKS)-1:0] bank_counter;
    logic [$clog2(BANKS)-1:0] bank_counter_buf [1:0];


    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_in_counter <= 0;
            buf_we <= 0;
            buf_din <= 0;
            buf_addr <= 0;
            buf_start <= 0;

            `ifndef SYNTHESIS
                for (int i=0; i<TAPS; i++) begin
                    sample_buffer.data[i] <= 0;
                end
            `endif
        end else begin
            if (sample_in_valid) begin
                sample_in_counter <= sample_in_counter + 1;
                buf_we <= 1;
                buf_din <= sample_in;
                buf_addr <= buf_start;
                buf_start <= buf_start - 1;
            end else begin
                buf_we <= 0;
                buf_addr <= buf_start + ({2'b0, bank_counter_buf[0]} << 2);
            end
        end
    end


    logic is_computing;
    
    logic [33:0] product;
    assign product = $signed(filter_data) * $signed(buf_dout);

    always_ff @ (posedge clk) begin
        if (rst) begin
            is_computing <= 0;
            accum <= 0;
            sample_out_valid <= 0;
        end else begin
            if (!is_computing) begin
                if (bank_counter_buf[1] == 0) begin
                    is_computing <= 1;
                    if (sample_in_counter == 1) begin
                        accum <= $signed(product);
                    end else begin
                        accum <= $signed(accum) + $signed(product);
                    end
                end
            end else begin
                if (bank_counter_buf[1] == BANKS-1) begin
                    is_computing <= 0;
                    if (sample_in_counter == 0) begin
                        sample_out_valid <= 1;
                    end
                end
                accum <= $signed(accum) + $signed(product);
            end

            if (sample_out_valid) begin
                sample_out_valid <= 0;
            end
        end
    end


    // Filter coefficient read requester
    
    logic [1:0] coeff_counter_inc;
    assign coeff_counter_inc = coeff_counter + 1;
    
    logic [7:0] bank_counter_inc;
    assign bank_counter_inc = bank_counter + 1;
    
    always_ff @ (posedge clk) begin
        if (rst) begin
            coeff_counter <= 0;
            filter_index <= 0;
            bank_counter <= 0;
            bank_counter_buf[0] <= 0;
            bank_counter_buf[1] <= 0;
        end else begin
            if (sample_in_valid) begin
                coeff_counter <= coeff_counter_inc;
                filter_index <= coeff_counter_inc;
                bank_counter <= 0;
            end else begin
                if (bank_counter < BANKS-1) begin
                    bank_counter <= bank_counter_inc;
                end
                filter_index <= ({2'b0, bank_counter_inc} << 2) + coeff_counter;
            end

            bank_counter_buf[0] <= bank_counter;
            bank_counter_buf[1] <= bank_counter_buf[0];
        end
    end


    // Output clipper
    always_comb begin
        if ($signed(accum[43:34]) < -3'sd1) begin
            sample_out = 16'h8000;
        end else if ($signed(accum[43:34]) > 3'sd0) begin
            sample_out = 16'h7FFF;
        end else begin
            sample_out = accum[34:19];
        end
    end


    dist_ram #(
        .WIDTH(16),
        .DEPTH(TAPS)
    ) sample_buffer (
        .clk(clk),
        .addr(buf_addr),
        .we(buf_we),
        .din(buf_din),
        .dout(buf_dout)
    );


    // 2 cycle delay
    xilinx_single_port_ram_read_first #(
        .RAM_WIDTH(18),
        .RAM_DEPTH(TAPS),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
        .INIT_FILE(
            `FPATH(downsampler_filter_coeffs.mem)
        )
    ) filter_bram (
        .addra(filter_index),
        .dina(0),
        .clka(clk),
        .wea(0),
        .ena(1),
        .rsta(rst),
        .regcea(1),
        .douta(filter_data)
    );

endmodule

`default_nettype wire
