`default_nettype none

module dlt_sig_dac_1st_order (
    input wire clk,
    input wire rst,
    input wire [15:0] current_sample,
    output wire to_audio
);
  logic [17:0] error_sum;
  logic [17:0] current_error;

  assign to_audio = error_sum >= 18'h10000;
  assign current_error = {to_audio, to_audio, ~current_sample[15], current_sample[14:0]};

  always_ff @(posedge clk) begin
    error_sum <= error_sum + current_error;
  end
endmodule  //dlt_sig_dac_1o

`default_nettype wire
