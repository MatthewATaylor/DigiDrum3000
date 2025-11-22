`timescale 1ns / 1ps  //
`default_nettype none

// 2 cycle latency
module video_distortion (
    input wire clk,
    input wire rst,

    input wire [10:0] h_count_in,
    input wire [ 9:0] v_count_in,
    input wire        active_draw_in,
    input wire [23:0] pixel_in,
    input wire [ 9:0] drive,

    output logic [10:0] h_count_out,
    output logic [ 9:0] v_count_out,
    output logic        active_draw_out,
    output logic [23:0] pixel_out
);
  logic [31:0] noise_gen;
  logic signed [7:0] noise_scrambled;
  assign noise_scrambled = {
    noise_gen[0],
    noise_gen[5],
    noise_gen[3],
    noise_gen[7],
    noise_gen[1],
    noise_gen[4],
    noise_gen[6],
    noise_gen[2]
  };

  always_ff @(posedge clk) begin
    if (rst) begin
      noise_gen <= 32'hFFFF_FFFF;
    end else if (h_count_in == 11'd1280) begin
      noise_gen <= (noise_gen << 1) ^ (noise_gen[31] * 32'b0000_0100_1100_0001_0001_1101_1011_0111);
    end
  end

  logic [10:0] last_h_count;
  logic [ 9:0] last_v_count;

  logic [10:0] write_addr;
  logic [10:0] read_addr;
  logic [11:0] read_offset;
  logic        write_active;

  assign write_addr   = h_count_in;
  assign write_active = active_draw_in;

  logic [23:0] a1_read_pixel;
  logic [23:0] a2_read_pixel;
  logic [23:0] b1_read_pixel;
  logic [23:0] b2_read_pixel;

  logic [ 1:0] read_addr_pipe;

  assign pixel_out = v_count_out[0]
      ? (read_addr_pipe[1] ? a2_read_pixel : a1_read_pixel)
      : (read_addr_pipe[1] ? b2_read_pixel : b1_read_pixel);
  assign active_draw_out = h_count_out <= 11'd1280 && v_count_out <= 10'd720;

  logic signed [11:0] naive_read_addr;
  always_comb begin
    naive_read_addr = h_count_in + read_offset;
    if ($signed(naive_read_addr) < $signed(0)) begin
      read_addr = naive_read_addr + 11'd1280;
    end else if (naive_read_addr >= 11'd1280) begin
      read_addr = naive_read_addr - 11'd1280;
    end else begin
      read_addr = naive_read_addr;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      read_offset <= 0;
      last_v_count <= 0;
      last_h_count <= 0;
      h_count_out <= 0;
      v_count_out <= 0;
      read_addr_pipe <= 0;
    end else begin
      if (h_count_in == 11'd1280) begin
        read_offset <= drive[9:8] == 0
        ? (noise_scrambled * $signed({8'h0, drive[8:1]})) >>>  10
        : (noise_scrambled * $signed({9'h1, drive[7:1]})) >>> (11 - drive[9:8]);
      end
      last_v_count <= v_count_in == 0 ? 10'd749 : v_count_in - 10'd1;
      last_h_count <= h_count_in;
      h_count_out <= last_h_count;
      v_count_out <= last_v_count;
      read_addr_pipe <= {read_addr_pipe[0], read_addr[10]};
    end
  end

  logic [23:0] to_write;
  logic        a1_write_enable;
  logic        a2_write_enable;
  logic        b1_write_enable;
  logic        b2_write_enable;

  assign a1_write_enable = v_count_in[0] & write_active & (!write_addr[10]);
  assign a2_write_enable = v_count_in[0] & write_active & write_addr[10];
  assign b1_write_enable = (!v_count_in[0]) & write_active & (!write_addr[10]);
  assign b2_write_enable = (!v_count_in[0]) & write_active & write_addr[10];

  xilinx_true_dual_port_read_first_1_clock_ram #(
      .RAM_WIDTH(24),
      .RAM_DEPTH(1024),
      .RAM_PERFORMANCE("HIGH_PERFORMANCE")
  ) my_bram_a1 (
      .clka(clk),  // Clock
      //writing port:
      .addra(write_addr[9:0]),  // Port A address bus,
      .dina(pixel_in),  // Port A RAM input data
      .wea(a1_write_enable),  // Port A write enable
      //reading port:
      .addrb(read_addr[9:0]),  // Port B address bus,
      .doutb(a1_read_pixel),  // Port B RAM output data,
      .douta(),  // Port A RAM output data, width determined from RAM_WIDTH
      .dinb(0),  // Port B RAM input data, width determined from RAM_WIDTH
      .web(1'b0),  // Port B write enable
      .ena(1'b1),  // Port A RAM Enable
      .enb(1'b1),  // Port B RAM Enable,
      .rsta(1'b0),  // Port A output reset
      .rstb(1'b0),  // Port B output reset
      .regcea(1'b1),  // Port A output register enable
      .regceb(1'b1)  // Port B output register enable
  );

  xilinx_true_dual_port_read_first_1_clock_ram #(
      .RAM_WIDTH(24),
      .RAM_DEPTH(1024),
      .RAM_PERFORMANCE("HIGH_PERFORMANCE")
  ) my_bram_a2 (
      .clka(clk),  // Clock
      //writing port:
      .addra(write_addr[9:0]),  // Port A address bus,
      .dina(pixel_in),  // Port A RAM input data
      .wea(a2_write_enable),  // Port A write enable
      //reading port:
      .addrb(read_addr[9:0]),  // Port B address bus,
      .doutb(a2_read_pixel),  // Port B RAM output data,
      .douta(),  // Port A RAM output data, width determined from RAM_WIDTH
      .dinb(0),  // Port B RAM input data, width determined from RAM_WIDTH
      .web(1'b0),  // Port B write enable
      .ena(1'b1),  // Port A RAM Enable
      .enb(1'b1),  // Port B RAM Enable,
      .rsta(1'b0),  // Port A output reset
      .rstb(1'b0),  // Port B output reset
      .regcea(1'b1),  // Port A output register enable
      .regceb(1'b1)  // Port B output register enable
  );

  xilinx_true_dual_port_read_first_1_clock_ram #(
      .RAM_WIDTH(24),
      .RAM_DEPTH(1024),
      .RAM_PERFORMANCE("HIGH_PERFORMANCE")
  ) my_bram_b1 (
      .clka(clk),  // Clock
      //writing port:
      .addra(write_addr[9:0]),  // Port A address bus,
      .dina(pixel_in),  // Port A RAM input data
      .wea(b1_write_enable),  // Port A write enable
      //reading port:
      .addrb(read_addr[9:0]),  // Port B address bus,
      .doutb(b1_read_pixel),  // Port B RAM output data,
      .douta(),  // Port A RAM output data, width determined from RAM_WIDTH
      .dinb(pixel_in),  // Port B RAM input data, width determined from RAM_WIDTH
      .web(1'b0),  // Port B write enable
      .ena(1'b1),  // Port A RAM Enable
      .enb(1'b1),  // Port B RAM Enable,
      .rsta(1'b0),  // Port A output reset
      .rstb(1'b0),  // Port B output reset
      .regcea(1'b1),  // Port A output register enable
      .regceb(1'b1)  // Port B output register enable
  );

  xilinx_true_dual_port_read_first_1_clock_ram #(
      .RAM_WIDTH(24),
      .RAM_DEPTH(1024),
      .RAM_PERFORMANCE("HIGH_PERFORMANCE")
  ) my_bram_b2 (
      .clka(clk),  // Clock
      //writing port:
      .addra(write_addr[9:0]),  // Port A address bus,
      .dina(pixel_in),  // Port A RAM input data
      .wea(b2_write_enable),  // Port A write enable
      //reading port:
      .addrb(read_addr[9:0]),  // Port B address bus,
      .doutb(b2_read_pixel),  // Port B RAM output data,
      .douta(),  // Port A RAM output data, width determined from RAM_WIDTH
      .dinb(0),  // Port B RAM input data, width determined from RAM_WIDTH
      .web(1'b0),  // Port B write enable
      .ena(1'b1),  // Port A RAM Enable
      .enb(1'b1),  // Port B RAM Enable,
      .rsta(1'b0),  // Port A output reset
      .rstb(1'b0),  // Port B output reset
      .regcea(1'b1),  // Port A output register enable
      .regceb(1'b1)  // Port B output register enable
  );
endmodule

`default_nettype wire
