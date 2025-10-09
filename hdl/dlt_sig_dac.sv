`default_nettype none

module dlt_sig_dac_1st_order (
    input wire clk,
    input wire rst,
    input wire [15:0] current_sample,
    output wire audio_out
);
  logic [23:0] noise_source;  // period of 16,777,215 at 100MHz repeats less than 20 times per second
  logic [19:0] error_sum;
  logic [19:0] current_error;

  // dither to reduce possible harmonics
  assign audio_out = error_sum >= 20'h10000 + noise_source[15:0];
  assign current_error = {4'b0 - {3'b0, audio_out}, ~current_sample[15], current_sample[14:0]};

  always_ff @(posedge clk) begin
    if (rst) begin
      noise_source <= 'hFFFFFF;
      error_sum <= 0;
    end else begin
      noise_source <= {
        noise_source[22:0],
        noise_source[23] ^ noise_source[22] ^ noise_source[21] ^ noise_source[16]
      };
      error_sum <= error_sum + current_error;
    end
  end
endmodule  //dlt_sig_dac_1o
`default_nettype wire
