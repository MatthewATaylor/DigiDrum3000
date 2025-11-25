`timescale 1ns / 1ps  //
`default_nettype none

module line_buffer #(
    parameter HRES = 1280,
    parameter VRES = 720,
    parameter KERNEL_SIZE = 3
) (
    input wire clk,  //system clock
    input wire rst,  //system reset

    input wire [10:0] h_count_in,    //current h_count being read
    input wire [ 9:0] v_count_in,    //current v_count being read
    input wire [17:0] pixel_data_in, //incoming pixel

    output logic [KERNEL_SIZE-1:0][17:0] line_buffer_out,  //output pixels of data
    output logic [10:0] h_count_out,  //current h_count being read
    output logic [9:0] v_count_out  //current v_count being read
);
  localparam INDEX_SIZE = $clog2(KERNEL_SIZE + 1);
  localparam V_OFFSET = (KERNEL_SIZE + 1) / 2;
  localparam FULL_V = VRES + 30;

  logic [INDEX_SIZE-1:0] bram_index;
  logic [INDEX_SIZE-1:0] last_bram_index;
  logic [INDEX_SIZE-1:0] bram_index_pipeline[1:0];
  logic [KERNEL_SIZE:0] bram_wea;
  logic [INDEX_SIZE-1:0] out_mux_index[KERNEL_SIZE-1:0];
  logic [17:0] bram_out[KERNEL_SIZE:0];
  logic [10:0] h_count_pipeline[1:0];
  logic [9:0] v_count_pipeline[1:0];
  logic [9:0] current_v_count;

  assign h_count_out = h_count_pipeline[1];
  assign bram_wea = {{KERNEL_SIZE{1'b0}}, h_count_in < HRES} << bram_index;

  always_comb begin
    if (v_count_pipeline[1] < V_OFFSET) begin
      v_count_out = v_count_pipeline[1] + (FULL_V - V_OFFSET);
    end else begin
      v_count_out = v_count_pipeline[1] - V_OFFSET;
    end
  end

  always_comb begin
    if (h_count_in < HRES && (v_count_in != current_v_count)) begin
      if (last_bram_index == KERNEL_SIZE) begin
        bram_index = 0;
      end else begin
        bram_index = last_bram_index + 1;
      end
    end else begin
      bram_index = last_bram_index;
    end
  end

  always_comb begin
    integer i;
    for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
      if (bram_index_pipeline[1] > (KERNEL_SIZE - i - 1)) begin
        out_mux_index[i] = bram_index_pipeline[1] + (i + 1) - (KERNEL_SIZE + 1);
      end else begin
        out_mux_index[i] = bram_index_pipeline[1] + (i + 1);
      end
      line_buffer_out[i] = bram_out[out_mux_index[i]];
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      last_bram_index <= 0;
      current_v_count <= 0;

      bram_index_pipeline[0] <= 0;
      bram_index_pipeline[1] <= 0;

      h_count_pipeline[0] <= 0;
      h_count_pipeline[1] <= 0;

      v_count_pipeline[0] <= 0;
      v_count_pipeline[1] <= 0;

    end else begin
      last_bram_index <= bram_index;
      current_v_count <= h_count_in < HRES ? v_count_in : current_v_count;

      bram_index_pipeline[0] <= bram_index;
      bram_index_pipeline[1] <= bram_index_pipeline[0];

      h_count_pipeline[0] <= h_count_in;
      h_count_pipeline[1] <= h_count_pipeline[0];

      v_count_pipeline[0] <= v_count_in;
      v_count_pipeline[1] <= v_count_pipeline[0];
    end
  end

  // to help you get started, here's a bram instantiation.
  // you'll want to create one BRAM for each row in the kernel, plus one more to
  // buffer incoming data from the wire:
  generate
    genvar i;
    for (i = 0; i <= KERNEL_SIZE; i = i + 1) begin
      xilinx_true_dual_port_read_first_1_clock_ram #(
          .RAM_WIDTH(18),
          .RAM_DEPTH(HRES),
          .RAM_PERFORMANCE("HIGH_PERFORMANCE")
      ) line_buffer_ram (
          .clka(clk),  // Clock
          //writing port:
          .addra(h_count_in),  // Port A address bus,
          .dina(v_count_in < VRES ? pixel_data_in : 0),  // Port A RAM input data
          .wea(bram_wea[i]),  // Port A write enable
          //reading port:
          .addrb(h_count_in),  // Port B address bus,
          .doutb(bram_out[i]),  // Port B RAM output data,
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
    end
  endgenerate

endmodule


`default_nettype wire
