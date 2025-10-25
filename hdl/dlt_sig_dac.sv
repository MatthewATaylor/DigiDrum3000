`default_nettype none

module dlt_sig_dac_1st_order (
    input wire clk,
    input wire rst,
    input wire [15:0] current_sample,
    output logic audio_out
);
  logic [23:0] noise_source;  // period of 16,777,215 at 100MHz repeats less than 20 times per second
  // -4 to 3.9999...
  logic [19:0] error_sum;
  logic [19:0] current_error;

  assign audio_out = error_sum[19] ? 0 : error_sum[18:0] >= 20'h20000 + noise_source[23:8];
  assign current_error = {3'b0 - {2'b0, audio_out}, 1'b0, ~current_sample[15], current_sample[14:0]} + 20'h02000;

  always_ff @(posedge clk) begin
    if (rst) begin
      noise_source <= 24'hFFFFFF;
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

module dlt_sig_dac_2nd_order (
    input wire clk,
    input wire rst,
    input wire [15:0] current_sample,
    output logic audio_out
);
  logic [23:0] noise_source;  // period of 16,777,215 at 100MHz repeats less than 20 times per second
  logic [15:0] noise_jumbled;
  logic [15:0] last_noise;
  logic [16:0] noise_combed;
  // -4 to 3.9999...
  logic [19:0] a_sum;
  logic [19:0] a_error;
  logic [19:0] b_sum;
  logic [19:0] b_error;
  logic [19:0] next_a_sum;
  logic [19:0] next_b_sum;

  // reduce doubling-like corilation
  assign noise_jumbled = {
    noise_source[22],
    noise_source[7],
    noise_source[2],
    noise_source[12],
    noise_source[16],
    noise_source[5],
    noise_source[20],
    noise_source[17],
    noise_source[1],
    noise_source[8],
    noise_source[11],
    noise_source[21],
    noise_source[3],
    noise_source[19],
    noise_source[10],
    noise_source[23]
  };

  assign noise_combed = noise_jumbled - last_noise;

  always_ff @(posedge clk) begin
    if (rst) begin
      noise_source <= 24'hFFFFFF;
      last_noise   <= 0;
    end else begin
      noise_source <= {
        noise_source[22] ^ noise_source[23],
        noise_source[21] ^ noise_source[23],
        noise_source[20:17],
        noise_source[16] ^ noise_source[23],
        noise_source[15:0],
        noise_source[23]
      };
      last_noise <= noise_jumbled;
    end

  end

  // dither to reduce possible harmonics
  assign audio_out = $signed(b_sum) >= $signed(noise_combed);
  assign a_error   = {3'b0 - {2'b0, audio_out}, 1'b0, ~current_sample[15], current_sample[14:0]} + 20'h02000;
  assign b_error = a_sum + a_error - (audio_out << 17);

  always_comb begin
    next_a_sum = a_sum + a_error;
    next_b_sum = b_sum + b_error;

    // need to model saturation to prevent overflow/underflow
    if (next_a_sum[19] && ~next_a_sum[18]) begin  // < -2
      next_a_sum = 20'hC0000;  // -2
    end else if (~next_a_sum[19] && next_a_sum[18]) begin  // > 2
      next_a_sum = 20'h40000;  // 2
    end

    if (next_b_sum[19] && ~next_b_sum[18]) begin  // < -2
      next_b_sum = 20'hC0000;  // -2
    end else if (~next_b_sum[19] && next_b_sum[18]) begin  // > 2
      next_b_sum = 20'h40000;  // 2
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      a_sum <= 0;
      b_sum <= 0;
    end else begin
      a_sum <= next_a_sum;
      b_sum <= next_b_sum;
    end
  end

endmodule

`default_nettype wire
