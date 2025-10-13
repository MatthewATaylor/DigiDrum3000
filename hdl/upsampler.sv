`default_nettype none

//##############################################################
//  USE 2264 cycles per sample -> 283 cycles per sample
//##############################################################

module upsampler (
    input wire clk,
    input wire rst,
    input wire [15:0] sample_in,
    input wire sample_in_valid,  // expected to be pulsed high every 2264 cycles
    output logic [15:0] sample_out  // 8x upsampled, held output
);

  logic [15:0] sample_buffer [127:0]

  xilinx_single_port_ram_read_first #(
      .RAM_WIDTH(16),  // Specify RAM data width
      .RAM_DEPTH(1024),  // Specify RAM depth (number of entries)
      .RAM_PERFORMANCE("HIGH_PERFORMANCE"),  // "HIGH_PERFORMANCE" or "LOW_LATENCY"
      .INIT_FILE(
      `FPATH(image2.mem)
      )  // Specify name/location of RAM initialization file if using one (leave blank if not)
  ) image_BROM (
      .addra(image_addr),  // Address bus, width determined from RAM_DEPTH
      .dina(0),  // RAM input data, width determined from RAM_WIDTH
      .clka(pixel_clk),  // Clock
      .wea(0),  // Write enable
      .ena(1),  // RAM Enable, for additional power savings, disable port when not in use
      .rsta(rst),  // Output reset (does not affect memory contents)
      .regcea(1),  // Output register enable
      .douta(palette_addr)  // RAM output data, width determined from RAM_WIDTH
  );
endmodule

`default_nettype wire
