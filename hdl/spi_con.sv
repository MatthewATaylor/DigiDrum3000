`default_nettype none

module spi_con #(
    parameter DATA_WIDTH = 8,
    parameter DATA_CLK_PERIOD = 100
) (
    input  wire                   clk,        //system clock (100 MHz)
    input  wire                   rst,        //reset in signal
    input  wire  [DATA_WIDTH-1:0] data_in,    //data to send
    input  wire                   trigger,    //start a transaction
    output logic [DATA_WIDTH-1:0] data_out,   //data received!
    output logic                  data_valid, //high when output data is present.

    output logic copi,  //(Controller-Out-Peripheral-In)
    input  wire  cipo,  //(Controller-In-Peripheral-Out)
    output logic dclk,  //(Data Clock)
    output logic cs     //(Chip Select)

);
  //your code here
  localparam DATA_CLK_HALF_PERIOD = DATA_CLK_PERIOD >> 1;

  logic [                  DATA_WIDTH-1:0] data_buf;
  logic [$clog2(DATA_CLK_HALF_PERIOD)-1:0] dclk_count;
  logic [          $clog2(DATA_WIDTH)-1:0] bits_sent;

  assign data_out = data_buf;

  always_ff @(posedge clk) begin
    if (rst) begin
      dclk       <= 0;
      cs         <= 1'b1;
      copi       <= 0;
      data_valid <= 0;  // in case of rst directly after finishing a transaction

    end else if (~cs) begin
      if (dclk_count == DATA_CLK_HALF_PERIOD - 1) begin
        dclk_count <= 0;
        dclk       <= ~dclk;
        if (dclk) begin  // falling edge of dclk
          copi      <= data_buf[DATA_WIDTH-1];
          bits_sent <= bits_sent + 1;
          if (bits_sent == DATA_WIDTH - 1) begin  // last falling edge
            cs         <= 1'b1;
            data_valid <= 1'b1;
          end
        end else begin  // rising edge of dclk
          data_buf <= {data_buf[DATA_WIDTH-2:0], cipo};
        end
      end else begin
        dclk_count <= dclk_count + 1;
      end

    end else if (trigger) begin
      data_valid <= 0;
      data_buf   <= data_in;
      cs         <= 0;
      copi       <= data_in[DATA_WIDTH-1];
      dclk_count <= 0;
      bits_sent  <= 0;

    end else begin
      data_valid <= 0;
    end
  end
endmodule

`default_nettype wire
