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
  logic [23:0] noise_jumbled;
  logic [12:0] noise_tri;
  logic [17:0] scaled_input;
  // -8 to 7.9999...
  logic [23:0] a_sum;
  logic [23:0] a_error;
  logic [23:0] b_sum;
  logic [23:0] b_error;
  logic [23:0] next_a_sum;
  logic [23:0] next_b_sum;
  logic last_out;

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
    noise_source[10],
    noise_source[1],
    noise_source[8],
    noise_source[11],
    noise_source[21],
    noise_source[3],
    noise_source[19],
    noise_source[0],
    noise_source[15],
    noise_source[6],
    noise_source[14],
    noise_source[18],
    noise_source[4],
    noise_source[13],
    noise_source[9],
    noise_source[23]
  };

  // pseudo-independent subtraction generate triangular distribution
  // [important]
  assign noise_tri = noise_jumbled[11:0] - noise_jumbled[23:12];

  always_ff @(posedge clk) begin
    if (rst) begin
      noise_source <= 24'hFFFFFF;
    end else begin
      noise_source <= {
        noise_source[22] ^ noise_source[23],
        noise_source[21] ^ noise_source[23],
        noise_source[20:17],
        noise_source[16] ^ noise_source[23],
        noise_source[15:0],
        noise_source[23]
      };
    end

  end

  // 3/4 scaled to prevent saturation of summers
  assign scaled_input = $signed(current_sample) + ($signed(current_sample) <<< 1);

  // dither to reduce possible harmonics
  // last_out term accounts for unequal rise/fall times (only ever pulsed on
  // for 1 clock cycle)
  assign audio_out = !last_out && ($signed(b_sum) >= 0);  //$signed(noise_tri));
  assign a_error = {~scaled_input[17], scaled_input[16:0]} - (audio_out << 19);
  assign b_error = a_sum + a_error - (audio_out << 19);

  always_comb begin
    next_a_sum = a_sum + a_error;
    next_b_sum = b_sum + b_error;

    // [might not to with scaling] need to model saturation to prevent overflow/underflow
    if (next_a_sum[23] && ~next_a_sum[22]) begin  // < -8
      next_a_sum = 24'hC00000;  // -8
    end else if (~next_a_sum[23] && next_a_sum[22]) begin  // > 8
      next_a_sum = 24'h400000;  // 8
    end

    if (next_b_sum[23] && ~next_b_sum[22]) begin  // < -8
      next_b_sum = 24'hC00000;  // -8
    end else if (~next_b_sum[23] && next_b_sum[22]) begin  // > 8
      next_b_sum = 24'h400000;  // 8
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      a_sum <= 0;
      b_sum <= 0;
      last_out <= 0;
    end else begin
      last_out <= audio_out;
      a_sum <= next_a_sum;
      b_sum <= next_b_sum;
    end
  end

endmodule

`default_nettype wire
