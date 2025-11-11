`timescale 1ns / 1ps
`default_nettype none

`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else  /* ! SYNTHESIS */
`define FPATH(X) `"../data/X`"
`endif  /* ! SYNTHESIS */

// Polyphase 4:1 downsampler
module downsampler_impossible
    (
        input  wire         clk,
        input  wire         rst,
        input  wire  [15:0] sample_in,
        input  wire         sample_in_valid,  // Expects valid every 2272/4 clock cycles
        output logic [15:0] sample_out,
        output logic        sample_out_valid
    );

    localparam TAPS = 1024;
    localparam BANKS = TAPS/4;
    localparam BUFFER_DEPTH = TAPS-4;

    logic [41:0] buffer [BUFFER_DEPTH-1:0];
    logic [43:0] accum;

    logic [15:0] sample_in_hold;
    logic [1:0]  sample_in_counter;

    logic [$clog2(TAPS)-1:0]   filter_index;
    logic [17:0]               filter_data;

    logic [1:0]                coeff_counter;
    logic [$clog2(BANKS)-1:0]  bank_counter;
    logic [$clog2(BANKS)-1:0]  bank_counter_buf [1:0];


    always_ff @ (posedge clk) begin
        if (rst) begin
            sample_in_counter <= 0;
            sample_in_hold <= 0;
        end else begin
            if (sample_in_valid) begin
                sample_in_hold <= sample_in;
                sample_in_counter <= sample_in_counter + 1;
            end
        end
    end


    logic is_computing;
    
    logic [33:0] product;
    assign product = $signed(filter_data) * $signed(sample_in_hold);
    
    logic [$clog2(TAPS)-1:0] buf_index;
    assign buf_index = {2'b0, bank_counter_buf[1]} << 2;
    
    always_ff @ (posedge clk) begin
        if (rst) begin
            // Uncomment for sim
            // for (int i=0; i<BUFFER_DEPTH; i++) begin
            //     buffer[i] <= 0;
            // end
            is_computing <= 0;
            accum <= 0;
            sample_out_valid <= 0;
        end else begin
            if (!is_computing) begin
                if (bank_counter_buf[1] == 0) begin
                    is_computing <= 1;
                    if (sample_in_counter == 1) begin
                        accum <=
                            $signed(product) +
                            $signed(buffer[0]);
                    end else begin
                        accum <=
                            $signed(accum) +
                            $signed(product) +
                            $signed(buffer[0]);
                        if (sample_in_counter == 0) begin
                            sample_out_valid <= 1;
                        end
                    end
                    for (int i=0; i<3; i++) begin
                        buffer[i] <= buffer[i+1];
                    end
                end
            end else begin
                if (bank_counter_buf[1] == BANKS-1) begin
                    is_computing <= 0;
                    buffer[BUFFER_DEPTH-1] <= $signed(product);
                end else begin
                    // if bank_counter_buf[1] == 1:
                    //     buffer[3] <= buffer[4] + product
                    //     buffer[4] <= buffer[5]
                    //     buffer[5] <= buffer[6]
                    //     buffer[6] <= buffer[7]
                    buffer[buf_index-1] <=
                        $signed(buffer[buf_index]) +
                        $signed(product);
                    for (int i=0; i<3; i++) begin
                        buffer[buf_index+i] <= buffer[buf_index+i+1];
                    end
                end
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


    // 2 cycle delay
    xilinx_single_port_ram_read_first #(
        .RAM_WIDTH(18),
        .RAM_DEPTH(1024),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
        .INIT_FILE(
            `FPATH(downsampler_filter_coeffs.mem)
        )
    ) bram (
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
