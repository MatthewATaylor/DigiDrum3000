`timescale 1ns / 1ps  //
`default_nettype none

// 3 cycle delay
module YCoCg_422_encoder (
    input wire clk,
    input wire rst,
    input wire h_count_lsb,
    input wire [23:0] pixel_in,
    output logic [15:0] dram_write_data
);

  logic [7:0] encoder_out_Y;
  logic [8:0] encoder_out_Co;
  logic [8:0] encoder_out_Cg;

  RGB_to_YCoCg_R my_YCoCg_encoder (
      .clk(clk),
      .rst(rst),
      .r  (pixel_in[23:16]),
      .g  (pixel_in[15:8]),
      .b  (pixel_in[7:0]),
      .Y  (encoder_out_Y),
      .Co (encoder_out_Co),
      .Cg (encoder_out_Cg)
  );

  logic [7:0] dram_color_data;

  logic [8:0] Co_buf;
  logic [8:0] Cg_buf;
  logic [8:0] Cg_buf2;
  logic [7:0] Y_buf;
  logic [7:0] Cg_422_buf;

  always_comb begin
    if (h_count_lsb) begin
      dram_color_data = ({Cg_buf2[8], Cg_buf2} + {Cg_buf[8], Cg_buf}) >> 2;
    end else begin
      dram_color_data = ({Co_buf[8], Co_buf} + {encoder_out_Co[8], encoder_out_Co}) >> 2;
    end
  end

  always_ff @(posedge clk) begin
    Co_buf <= encoder_out_Co;
    Cg_buf <= encoder_out_Cg;
    Cg_buf2 <= Cg_buf;
    Y_buf <= encoder_out_Y;
    dram_write_data <= {Y_buf, dram_color_data};
  end

endmodule  // YCoCg_422_encoder

// 6 cycle delay
module YCoCg_422_decoder (
    input wire clk,
    input wire rst,
    input wire h_count_lsb,
    input wire [15:0] dram_read_data,
    output logic [23:0] pixel_out
);

  logic [7:0] Y_buf;
  logic [7:0] Co_buf;
  logic [7:0] decoder_in_Y;
  logic [8:0] decoder_in_Co;
  logic [8:0] decoder_in_Cg;

  always_ff @(posedge clk) begin
    Y_buf <= dram_read_data[15:8];
    decoder_in_Y <= Y_buf;
    Co_buf <= dram_read_data[7:0];
    if (h_count_lsb) begin
      decoder_in_Co <= {Co_buf, 1'b0};
      decoder_in_Cg <= {dram_read_data[7:0], 1'b0};
    end
  end

  YCoCg_R_to_RGB my_YCoCg_decoder (
      .clk(clk),
      .rst(rst),
      .Y  (decoder_in_Y),
      .Co (decoder_in_Co),
      .Cg (decoder_in_Cg),
      .r  (pixel_out[23:16]),
      .g  (pixel_out[15:8]),
      .b  (pixel_out[7:0])
  );

endmodule  // YCoCg_422_decoder

module YCoCg_422_test (
    input wire clk,
    input wire rst,
    input wire h_count_lsb,
    input wire [23:0] pixel_in,
    output logic [23:0] pixel_out
);
  logic [15:0] encoded;

  YCoCg_422_encoder my_encoder (
      .clk(clk),
      .rst(rst),
      .h_count_lsb(h_count_lsb),
      .pixel_in(pixel_in),
      .dram_write_data(encoded)
  );

  YCoCg_422_decoder my_decoder (
      .clk(clk),
      .rst(rst),
      .h_count_lsb(~h_count_lsb),
      .dram_read_data(encoded),
      .pixel_out(pixel_out)
  );

endmodule  // YCoCg_422_test

`default_nettype wire

