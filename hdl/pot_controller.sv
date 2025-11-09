`timescale 1ns / 1ps  //
`default_nettype none

module pot_controller (
    input wire clk,
    input wire rst,

    input  wire  cipo,
    output logic copi,
    output logic dclk,
    output logic cs0,
    output logic cs1,

    output logic [9:0] value,
    output logic [3:0] pot_index,
    output logic value_valid
);

  localparam CYCLES_PER_TRIGGER = 1000;

  logic cs;
  assign cs0 = pot_index[0] ? cs : 1'b1;
  assign cs1 = !pot_index[0] ? cs : 1'b1;

  logic [31:0] trigger_count;
  logic        spi_trigger;

  counter counter_8khz_trigger (
      .clk(clk),
      .rst(rst),
      .period(CYCLES_PER_TRIGGER),
      .count(trigger_count)
  );

  localparam ADC_DATA_WIDTH = 17;
  localparam ADC_DATA_CLK_PERIOD = 50;

  logic [ADC_DATA_WIDTH-1:0] spi_write_data;
  logic [ADC_DATA_WIDTH-1:0] spi_read_data;
  logic                      spi_read_data_valid;

  assign value_valid = spi_read_data_valid;
  assign value = spi_read_data;

  spi_con #(
      .DATA_WIDTH(ADC_DATA_WIDTH),
      .DATA_CLK_PERIOD(ADC_DATA_CLK_PERIOD)
  ) my_spi_con (
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

  logic [3:0] next_pot_index;
  assign next_pot_index = pot_index == 4'd11 ? 4'd0 : pot_index + 4'd1;

  always_ff @(posedge clk) begin
    if (trigger_count == 'd1) begin  //once every 10us
      spi_write_data <= {2'b11, next_pot_index[3:1], 12'hXXX};
      spi_trigger <= 1'b1;
      pot_index <= next_pot_index;
    end else begin
      spi_trigger <= 1'b0;
    end

    if (rst) begin
      spi_trigger <= 1'b0;
      spi_write_data <= 17'd0;
      pot_index <= 4'd0;
    end
  end

endmodule  //pot_controller

`default_nettype wire
