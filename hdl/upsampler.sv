`default_nettype none

`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else  /* ! SYNTHESIS */
`define FPATH(X) `"../data/X`"
`endif  /* ! SYNTHESIS */

//##############################################################
//  USE 2272 cycles per sample -> 142 cycles per sample
//##############################################################

// ~70us delay
module upsampler (
    input wire clk,
    input wire rst,
    input wire [15:0] sample_in,
    input wire sample_in_valid,  // expected to be pulsed high every 2272 cycles
    output logic [15:0] sample_out  // 16x upsampled, held output
);

  //logic [15:0] sample_buffer  [63:0];
  logic [15:0] sample_buffer_out;
  logic [15:0] sample_buffer_in;
  logic sample_buffer_we;
  logic [5:0] sample_buffer_addr;

  dist_ram sample_buffer_lutram (
      .clk (clk),
      .addr(sample_buffer_addr),
      .we  (sample_buffer_we),
      .din (sample_buffer_in),
      .dout(sample_buffer_out)
  );

  logic [5:0] buffer_start;
  logic [5:0] sample_index;
  logic [3:0] upsample_index;
  logic [9:0] filter_index;
  logic [7:0] sample_timer;

  assign sample_index = sample_timer[5:0];
  assign filter_index = {sample_index, upsample_index};

  logic signed [17:0] filter_data;
  logic signed [47:0] accum;
  logic signed [47:0] accumulator_next;

  always_comb begin
    if (sample_in_valid) begin
      sample_buffer_we   = 1'b1;
      sample_buffer_addr = buffer_start - 6'h1;
      sample_buffer_in   = sample_in;
    end else begin
      sample_buffer_we   = 1'b0;
      sample_buffer_addr = buffer_start + sample_index - 6'd2;
      sample_buffer_in   = 16'hXXXX;
    end
  end

  assign accumulator_next = accum + (filter_data * $signed(sample_buffer_out));

  logic next_upsample;
  assign next_upsample = sample_timer == 141;
  // 2 cycle delay
  xilinx_single_port_ram_read_first #(
      .RAM_WIDTH(18),  // Specify RAM data width
      .RAM_DEPTH(1024),  // Specify RAM depth (number of entries)
      .RAM_PERFORMANCE("HIGH_PERFORMANCE"),  // "HIGH_PERFORMANCE" or "LOW_LATENCY"
      // Specify name/location of RAM initialization file if using one (leave blank if not)
      .INIT_FILE(
      `FPATH(DAC_filter_coeffs.mem)
      )
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

  logic [15:0] next_sample_out;
  always_comb begin
    if ($signed(accum[47:32]) < -15'sd1) begin
      next_sample_out = 16'h8000;
    end else if ($signed(accum[47:32]) > 15'sd0) begin
      next_sample_out = 16'h7FFF;
    end else begin
      next_sample_out = accum[32:17];
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      sample_out <= 0;
    end else if (sample_timer == 66) begin
      sample_out <= next_sample_out;
    end
  end

  always_ff @(posedge clk) begin
    if (rst || sample_in_valid || next_upsample) begin
      accum <= 0;
      sample_timer <= 0;

    end else begin
      accum <= sample_timer < 8'd2 ? accum : accumulator_next;
      sample_timer <= sample_timer + 8'h1;
    end

  end

  always_ff @(posedge clk) begin
    if (rst) begin
      buffer_start   <= 0;
      upsample_index <= 0;

    end else begin
      if (sample_in_valid) begin
        upsample_index <= 0;
        buffer_start   <= buffer_start - 6'h1;

      end else if (next_upsample) begin
        upsample_index <= upsample_index + 4'h1;
      end
    end
  end
endmodule

module dist_ram (
    input wire clk,
    input wire [5:0] addr,
    input wire we,
    input wire [15:0] din,
    output logic [15:0] dout
);

  logic [15:0] data[63:0];
  assign dout = data[addr];

  always_ff @(posedge clk) begin
    if (we) begin
      data[addr] <= din;
    end
  end
endmodule

`default_nettype wire
