`timescale 1ns / 1ps  //
`default_nettype none

module pedal_controller (
    input wire clk,
    input wire rst,

    input  wire  cipo,
    output logic copi,
    output logic dclk,
    output logic cs,

    output logic [9:0] value,
    output logic [1:0] pedal_index,
    output logic value_valid
);

  localparam CYCLES_PER_TRIGGER = 1200;

  logic [31:0] trigger_count;
  logic        spi_trigger;

  counter counter_8khz_trigger (
      .clk(clk),
      .rst(rst),
      .period(CYCLES_PER_TRIGGER),
      .count(trigger_count)
  );

  localparam ADC_DATA_WIDTH = 16;
  localparam ADC_DATA_CLK_PERIOD = 60;

  logic [ADC_DATA_WIDTH-1:0] spi_write_data;
  logic [ADC_DATA_WIDTH-1:0] spi_read_data;
  logic                      spi_read_data_valid;

  assign value_valid = spi_read_data_valid;
  assign value = spi_read_data[11:2];

  spi_con #(
      .DATA_WIDTH(ADC_DATA_WIDTH),
      .DATA_CLK_PERIOD(ADC_DATA_CLK_PERIOD)
  ) spi_con_pedal (
      .clk(clk),
      .rst(rst),
      .data_in(spi_write_data),
      .trigger(spi_trigger),
      .data_out(spi_read_data),
      .data_valid(spi_read_data_valid),
      .copi(copi),
      .cipo(cipo),
      .dclk(dclk),
      .cs(cs)
  );

  logic [1:0] next_pedal_index;
  assign next_pedal_index = pedal_index == 2'b11 ? 2'b00 : pedal_index + 2'b01;

  always_ff @(posedge clk) begin
    if (trigger_count == 'd1) begin  //once every 10us
      spi_write_data <= {3'bXXX, next_pedal_index, 11'bXXX_XXXX_XXXX};
      spi_trigger <= 1'b1;
      pedal_index <= next_pedal_index;
    end else begin
      spi_trigger <= 1'b0;
    end

    if (rst) begin
      spi_trigger <= 1'b0;
      spi_write_data <= 16'd0;
      pedal_index <= 2'b00;
    end
  end

endmodule  //pot_controller

`default_nettype wire
