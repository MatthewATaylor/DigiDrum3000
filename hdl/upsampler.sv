`default_nettype none

`ifdef SYNTHESIS
`define FPATH(X) X
`else
`define FPATH(X) {"../data/", X}
`endif

// ~70us delay
module upsampler #(
    parameter RATIO,
    parameter VOLUME_EN,
    parameter FILTER_FILE,
    parameter FILTER_TAPS,
    parameter FILTER_SCALE
) (
    input  wire         clk,
    input  wire         rst,
    input  wire  [15:0] sample_in,
    input  wire         sample_in_valid,// expected to be pulsed high every 2272 cycles
    input  wire   [9:0] volume,
    output logic [15:0] sample_out,     // upsampled by RATIO, held output
    output logic        sample_out_valid// unused by DAC
);
  localparam BUFFER_DEPTH  = FILTER_TAPS/RATIO;
  localparam BUFFER_ADDR_W = $clog2(BUFFER_DEPTH);
  localparam BUFFER_DELAY  = 4;
  localparam OUTPUT_PERIOD = 2272/RATIO;
  localparam OUTPUT_SHIFT  = FILTER_SCALE - $clog2(RATIO) + VOLUME_EN*2;

  logic              [15:0] sample_buffer_out;
  logic              [15:0] sample_buffer_out_reg;
  logic              [15:0] sample_buffer_in;
  logic                     sample_buffer_we;
  logic [BUFFER_ADDR_W-1:0] sample_buffer_addr;

  dist_ram #(
    .WIDTH(16),
    .DEPTH(BUFFER_DEPTH)
  ) sample_buffer_lutram (
      .clk (clk),
      .addr(sample_buffer_addr),
      .we  (sample_buffer_we),
      .din (sample_buffer_in),
      .dout(sample_buffer_out)
  );

  logic         [BUFFER_ADDR_W-1:0] buffer_start;
  logic         [BUFFER_ADDR_W-1:0] sample_index;
  logic [$clog2(        RATIO)-1:0] upsample_index;
  logic [$clog2(  FILTER_TAPS)-1:0] filter_index;
  logic [$clog2(OUTPUT_PERIOD)-1:0] sample_timer;

  assign sample_index = sample_timer[BUFFER_ADDR_W-1:0];
  assign filter_index = {sample_index, upsample_index};

  logic signed [17:0] filter_data;
  logic signed [17:0] filter_data_reg;
  logic signed [33:0] filter_mult;
  logic signed [47:0] accum;
  logic signed [47:0] accumulator_next;

  logic        [15:0] volume_mult;

  always_ff @(posedge clk) begin
    if (rst || VOLUME_EN == 0) begin
      volume_mult <= 0;
    end else begin
      volume_mult <= (|volume[9:7] ? {9'h1, volume[6:0]} << volume[9:7] : {volume[6:0], 1'b0}) >> 1;
    end
  end

  always_comb begin
    if (sample_in_valid) begin
      sample_buffer_we   = 1'b1;
      sample_buffer_addr = buffer_start - 1;
      sample_buffer_in   = sample_in;
    end else begin
      sample_buffer_we   = 1'b0;
      sample_buffer_addr = buffer_start + sample_index - 2;
      sample_buffer_in   = 16'hXXXX;
    end
  end

  always_comb begin
    if (sample_timer <= BUFFER_DEPTH+BUFFER_DELAY-1) begin
      accumulator_next = accum + filter_mult;
    end else if (VOLUME_EN == 1) begin
      accumulator_next = $signed(accum[34:10]) * $signed({1'b0, volume_mult});
    end
  end

  logic next_upsample;
  assign next_upsample = sample_timer == OUTPUT_PERIOD-1;
  // 2 cycle delay
  xilinx_single_port_ram_read_first #(
      .RAM_WIDTH(18),  // Specify RAM data width
      .RAM_DEPTH(FILTER_TAPS),  // Specify RAM depth (number of entries)
      .RAM_PERFORMANCE("HIGH_PERFORMANCE"),  // "HIGH_PERFORMANCE" or "LOW_LATENCY"
      // Specify name/location of RAM initialization file if using one (leave blank if not)
      .INIT_FILE(
        `FPATH(FILTER_FILE)
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
  clipper #(
    .WIDTH_FULL(48),
    .WIDTH_CLIP(16),
    .RIGHT_SHIFT(OUTPUT_SHIFT)
  ) output_clipper (
    .din(accum),
    .dout(next_sample_out)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      sample_out <= 0;
      sample_out_valid <= 0;
    end else if (sample_timer == BUFFER_DEPTH+BUFFER_DELAY+1) begin
      sample_out <= next_sample_out;
      sample_out_valid <= 1;
    end else begin
      sample_out_valid <= 0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst || sample_in_valid || next_upsample) begin
      accum <= 0;
      sample_timer <= 0;
    end else begin
      accum <= sample_timer < BUFFER_DELAY ? accum : accumulator_next;
      sample_timer <= sample_timer + 1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      buffer_start   <= 0;
      upsample_index <= 0;
`ifndef SYNTHESIS
      for (int i = 0; i < BUFFER_DEPTH; i++) begin
        sample_buffer_lutram.data[i] <= 0;
      end
`endif
    end else begin
      if (sample_in_valid) begin
        upsample_index <= 0;
        buffer_start   <= buffer_start - 1;
      end else if (next_upsample) begin
        upsample_index <= upsample_index + 1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      sample_buffer_out_reg <= 0;
      filter_mult <= 0;
      filter_data_reg <= 0;
    end else begin
      filter_data_reg <= filter_data;
      sample_buffer_out_reg <= sample_buffer_out;
      filter_mult <= filter_data_reg * $signed(sample_buffer_out_reg);
    end
  end
endmodule

`default_nettype wire
