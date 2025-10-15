`default_nettype none

//##############################################################
//  USE 2272 cycles per sample -> 142 cycles per sample
//##############################################################

module upsampler (
    input wire clk,
    input wire rst,
    input wire [15:0] sample_in,
    input wire sample_in_valid,  // expected to be pulsed high every 2272 cycles
    output logic [15:0] sample_out  // 16x upsampled, held output
);

  logic [15:0] sample_buffer  [63:0];
  logic [ 5:0] buffer_start;
  logic [ 5:0] sample_index;
  logic [ 3:0] upsample_index;
  logic [ 9:0] filter_index;
  logic [ 7:0] upsample_timer;
  assign filter_index = {sample_index, upsample_index};

  logic signed [15:0] sample_pipelined [1:0];
  logic signed [17:0] filter_data;
  logic signed [47:0] accum;
  logic signed [47:0] accumulator_next;
  assign accumulator_next = accum + (filter_data * sample_pipelined[1]);

  logic next_upsample;
  assign next_upsample = upsample_timer == 141;
  // 2 cycle delay
  xilinx_single_port_ram_read_first #(
      .RAM_WIDTH(18),  // Specify RAM data width
      .RAM_DEPTH(1024),  // Specify RAM depth (number of entries)
      .RAM_PERFORMANCE("HIGH_PERFORMANCE"),  // "HIGH_PERFORMANCE" or "LOW_LATENCY"
      // Specify name/location of RAM initialization file if using one (leave blank if not)
      .INIT_FILE(FPATH(DAC_filter_coeffs.mem))
  ) image_BROM (
      .addra(filter_index),  // Address bus, width determined from RAM_DEPTH
      .dina(0),  // RAM input data, width determined from RAM_WIDTH
      .clka(clk),  // Clock
      .wea(0),  // Write enable
      .ena(1),  // RAM Enable, for additional power savings, disable port when not in use
      .rsta(rst),  // Output reset (does not affect memory contents)
      .regcea(1),  // Output register enable
      .douta(filter_data)  // RAM output data, width determined from RAM_WIDTH
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      sample_out <= 0;
    end else if (upsample_timer == 66) begin
      sample_out <= accum[33:18];
    end
  end

  always_ff @(posedge clk) begin
    if (rst || sample_in_valid || next_upsample) begin
      accum <= 0;
      sample_pipelined[1] <= 0;
      sample_pipelined[0] <= 0;
      sample_index <= 0;
      upsample_timer <= 0;

    end else begin
      accum <= accumulator_next;
      sample_pipelined[1] <= sample_pipelined[0];
      sample_pipelined[0] <= sample_buffer[buffer_start+sample_index];
      sample_index <= sample_index + 6'h1;
      upsample_timer <= upsample_timer + 8'h1;
    end

  end

  always_ff @(posedge clk) begin
    if (rst) begin
      buffer_start   <= 0;
      upsample_index <= 0;

    end else begin
      if (sample_in_valid) begin
        upsample_index <= 0;
        buffer_start <= buffer_start - 6'h1;
        sample_buffer[buffer_start-6'h1] <= sample_in;

      end else if (next_upsample) begin
        upsample_index <= upsample_index + 4'h1;
      end
    end
  end
endmodule

`default_nettype wire
