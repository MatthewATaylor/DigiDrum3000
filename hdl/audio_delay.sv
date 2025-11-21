`timescale 1ns / 1ps
`default_nettype none

module audio_delay
    (
        input wire clk,
        input wire rst,

        input wire       sw_delay_fast,
        input wire [9:0] pot_wet,
        input wire [9:0] pot_rate,
        input wire [9:0] pot_feedback,

        input wire [15:0] sample_in,
        input wire        sample_in_valid,

        output logic [15:0] sample_out,
        output logic        sample_out_valid
    );

    localparam DELAY_DEPTH = 8 * 1024;
    localparam BASE_SAMPLE_PERIOD = 2272;

    logic [15:0] resampled_in;
    logic        resampled_in_valid;

    logic [15:0] delay_line_out;
    logic        delay_line_out_valid;

    logic [15:0] bram_dout;
    logic [15:0] bram_din;

    // sample_period: [2272/4, 2272*4]
    //   sw_delay_fast: [2.91 ms, 46.5 ms]
    //  !sw_delay_fast: [46.5 ms, 744 ms]
    // resampler_delay_in:
    //  farrow_upsampler in:   2272
    //  farrow_upsampler out: [2272/16, 2272]
    //  downsampler      out: [2272/4,  2272*4]
    // resampler_delay_out:
    //  farrow_upsampler in:  [2272/4,  2272*4],
    //  farrow_upsampler out:  2272/4
    //  downsampler      out:  2272
    logic [13:0] sample_period;
    pitch_to_sample_period p2sp_delay (
        .clk(clk),
        .rst(rst),
        .pitch(pot_rate),
        .sample_period(sample_period)
    );

    logic [$clog2(DELAY_DEPTH)-1:0] bram_wr_addr;
    logic [$clog2(DELAY_DEPTH)-1:0] bram_rd_addr;

    always_comb begin
        if (sw_delay_fast) begin
            bram_rd_addr = bram_wr_addr - 512;
        end else begin
            bram_rd_addr = bram_wr_addr + 1;
        end
    end

    logic [1:0]  sample_in_valid_buf;
    logic [15:0] sample_in_buf;
    logic [13:0] sample_period_buf;

    always_ff @ (posedge clk) begin
        if (rst) begin
            bram_din <= 0;
            bram_wr_addr <= 0;
            sample_in_valid_buf <= 0;
            sample_in_buf <= 0;
            sample_period_buf <= BASE_SAMPLE_PERIOD;
            delay_line_out_valid <= 0;
            delay_line_out <= 0;
        end else begin
            if (sample_in_valid) begin
                sample_period_buf <= sample_period;
            end

            if (resampled_in_valid) begin
                sample_in_buf <= resampled_in;
                bram_din <=
                    ($signed(resampled_in) >>> 1) +
                    ($signed(bram_dout) >>> 1);
                bram_wr_addr <= bram_wr_addr + 1;
            end

            if (sample_in_valid_buf[1]) begin
                delay_line_out_valid <= 1;
                delay_line_out <=
                    ($signed(sample_in_buf) >>> 1) +
                    ($signed(bram_dout) >>> 1);
            end

            sample_in_valid_buf <= {sample_in_valid_buf[0], resampled_in_valid};

            if (delay_line_out_valid) begin
                delay_line_out_valid <= 0;
            end
        end
    end

    resampler resampler_delay_in (
        .clk(clk),
        .rst(rst),
        
        .sample_period_in(BASE_SAMPLE_PERIOD),
        .sample_period_farrow_out(sample_period >> 2),

        .sample_in(sample_in),
        .sample_in_valid(sample_in_valid),

        .sample_out(resampled_in),
        .sample_out_valid(resampled_in_valid)
    );

    resampler resampler_delay_out (
        .clk(clk),
        .rst(rst),
        
        .sample_period_in(sample_period_buf),
        .sample_period_farrow_out(BASE_SAMPLE_PERIOD >> 2),

        .sample_in(delay_line_out),
        .sample_in_valid(delay_line_out_valid),

        .sample_out(sample_out),
        .sample_out_valid(sample_out_valid)
    );

    // 2 cycle delay
    // Port A: read
    // Port B: write
    xilinx_true_dual_port_read_first_2_clock_ram #(
        .RAM_WIDTH(16),
        .RAM_DEPTH(DELAY_DEPTH),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
        .INIT_FILE("")
    ) delay_bram (
        .addra(bram_rd_addr),
        .addrb(bram_wr_addr),
        .dina(),
        .dinb(bram_din),
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
        .douta(bram_dout),
        .doutb()
    );

endmodule

`default_nettype wire
 
