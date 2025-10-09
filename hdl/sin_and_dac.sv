`default_nettype none

// purely for testbenching with cocotb
module sin_and_dac (
    input wire clk,
    input wire rst,
    input wire [29:0] delta_angle,  // 0 to 1.9999...
    input wire get_next_sample,
    output logic audio_out
);
  logic [15:0] current_sample;

  sin_gen my_sin (
      .clk(clk),
      .rst(rst),
      .delta_angle(delta_angle),
      .get_next_sample(get_next_sample),
      .current_sample(current_sample)
  );

  dlt_sig_dac_1st_order my_dac (
      .clk(clk),
      .rst(rst),
      .current_sample(current_sample),
      .audio_out(audio_out)
  );
endmodule

`default_nettype wire
