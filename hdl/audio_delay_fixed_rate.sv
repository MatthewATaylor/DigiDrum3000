`timescale 1ns / 1ps
`default_nettype none

module audio_delay_fixed_rate
    (
        input wire clk,
        input wire rst,

        input wire [9:0] pot_wet,
        input wire [9:0] pot_rate,
        input wire [9:0] pot_feedback,

        input wire [15:0] sample_in,
        input wire        sample_in_valid,

        output logic [15:0] sample_out,
        output logic        sample_out_valid
    );

    localparam BRAM18_COUNT = 64;
    localparam BRAM18_DEPTH = 1024;
    localparam DELAY_DEPTH = BRAM18_COUNT * BRAM18_DEPTH;

    logic [15:0] bram_dout;
    logic [15:0] bram_din;

    logic [10:0]                    pot_time;
    logic [$clog2(DELAY_DEPTH)-1:0] delay_time;

    // [1, 1024]
    assign pot_time   = 11'd1024 - pot_rate;
    
    // [64 - 1, 1024*64 - 1] = [1.4 ms, 1.5 s] @ sp=2272
    assign delay_time = ({6'b0, pot_time} << 6) - 1;

    logic [$clog2(DELAY_DEPTH)-1:0] bram_wr_addr;
    logic [$clog2(DELAY_DEPTH)-1:0] bram_rd_addr;
    assign bram_rd_addr = bram_wr_addr - delay_time;

    logic [1:0]  sample_in_valid_buf;
    logic [15:0] sample_in_buf;

    always_ff @ (posedge clk) begin
        if (rst) begin
            bram_din <= 0;
            bram_wr_addr <= 0;
            sample_in_valid_buf <= 0;
            sample_in_buf <= 0;

            sample_out <= 0;
            sample_out_valid <= 0;
        end else begin
            if (sample_in_valid) begin
                sample_in_buf <= sample_in;
                bram_din <=
                    ($signed(sample_in) >>> 1) +
                    ($signed(sample_out) >>> 1);
                bram_wr_addr <= bram_wr_addr + 1;
            end

            if (sample_in_valid_buf[1]) begin
                sample_out_valid <= 1;
                sample_out <=
                    ($signed(sample_in_buf) >>> 1) +
                    ($signed(bram_dout) >>> 1);
            end

            sample_in_valid_buf <= {sample_in_valid_buf[0], sample_in_valid};

            if (sample_out_valid) begin
                sample_out_valid <= 0;
            end
        end
    end

    // 2 cycle delay
    // Port A: read
    // Port B: write
    xilinx_true_dual_port_read_first_2_clock_ram #(
        .RAM_WIDTH(18),
        .RAM_DEPTH(DELAY_DEPTH),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
        .INIT_FILE("")
    ) delay_bram (
        .addra(bram_rd_addr),
        .addrb(bram_wr_addr),
        .dina(),
        .dinb({2'b0, bram_din}),
        .clka(clk),
        .clkb(clk),
        .wea(1'b0),
        .web(1'b1),
        .ena(1'b1),
        .enb(1'b1),
        .rsta(rst),
        .rstb(rst),
        .regcea(1'b1),
        .regceb(1'b1),
        .douta({2'b0, bram_dout}),
        .doutb()
    );

endmodule

`default_nettype wire
 
