`default_nettype none

module dlt_sig_dac_1st_order (
    input wire clk,
    input wire rst,
    input wire [15:0] current_sample,
    output logic audio_out
);
  logic [23:0] noise_source;  // period of 16,777,215 at 100MHz repeats less than 20 times per second
  logic [19:0] error_sum;
  logic [19:0] current_error;

  // dither to reduce possible harmonics
  assign audio_out = error_sum >= 20'h20000 + noise_source[23:8];
  assign current_error = {
    3'b0 - {2'b0, audio_out}, 2'b00 + {1'b0, ~current_sample[15]}, current_sample[14:0]
  };

  always_ff @(posedge clk) begin
    if (rst) begin
      noise_source <= 'hFFFFFF;
      error_sum <= 0;
    end else begin
      noise_source <= {
        noise_source[22] ^ noise_source[23],
        noise_source[21] ^ noise_source[23],
        noise_source[20:17],
        noise_source[16] ^ noise_source[23],
        noise_source[15:0],
        noise_source[23]
      };
      error_sum <= error_sum + current_error;
    end
  end
endmodule  //dlt_sig_dac_1o
`default_nettype wire
