`default_nettype none  // prevents system from inferring an undeclared logic (good practice)

//###############################
//  USE 2272 cycles per sample
//###############################

module top_level (
    input  wire         clk_100mhz,  //100 MHz onboard clock
    input  wire  [15:0] sw,          //all 16 input slide switches
    input  wire  [ 3:0] btn,         //all four momentary button switches
    output logic [15:0] led,         //16 green output LEDs (located right above switches)
    output logic [ 2:0] rgb0,        //RGB channels of RGB LED0
    output logic [ 2:0] rgb1,        //RGB channels of RGB LED1
    output logic        spkl,        // left line out port
    output logic        spkr         // right line out port
);

  //shut up those rgb LEDs for now (active high):
  assign rgb1 = 0;  //set to 0.
  assign rgb0 = 0;  //set to 0.
  assign led  = sw;

  //have btnd control system reset
  logic sys_rst;
  assign sys_rst = btn[0];

  logic spk_out;
  assign spkl = spk_out;
  assign spkr = spk_out;

  logic        sin_wave;
  logic        square_wave;
  logic        impulse_approx;  // same as square at very high frequency

  logic [ 3:0] wave_shift;
  logic [31:0] wave_period;
  logic [31:0] wave_frequency;
  logic [31:0] square_count;
  logic        square_state;

  logic        divider_busy;
  logic [31:0] divider_out;
  logic        divider_out_valid;
  divider my_divide (
      .clk(clk_100mhz),
      .rst(sys_rst),
      .dividend(32'd50_000_000),
      .divisor(wave_frequency),
      .data_in_valid(!divider_busy),
      .quotient(divider_out),
      .remainder(),
      .data_out_valid(divider_out_valid),
      .busy(divider_busy)
  );

  always_ff @(posedge clk_100mhz) begin
    wave_frequency <= {27'b0, 1'b1, sw[15:12]} << sw[11:8];
    wave_shift <= 4'hF - sw[7:4];
    wave_period <= divider_out_valid ? divider_out : wave_period;
  end

  counter wave_count (
      .clk(clk_100mhz),
      .rst(sys_rst),
      .period(wave_period),
      .count(square_count)
  );

  counter sampled_counter (
      .clk(clk_100mhz),
      .rst(sys_rst),
      .period(2272),
      .count(sample_cycle_count)
  );

  logic [15:0] sin_sample;
  logic [15:0] sin_upsample;
  logic [15:0] sample_out;
  logic [31:0] sample_cycle_count;

  always_ff @(posedge clk_100mhz) begin
    sample_out <= sw[2] ? $signed(sw[0] ? sin_sample : sin_upsample) >>> wave_shift : 0;
  end

  sin_gen my_sin_gen (
      .clk(clk_100mhz),
      .rst(sys_rst),
      // ideally 2^29 * 2pi * freq / cycles_per_sample
      .delta_angle(wave_frequency << 16),
      .get_next_sample(sample_cycle_count == 0),
      .current_sample(sin_sample)
  );

  upsampler my_upsample (
      .clk(clk_100mhz),
      .rst(sys_rst),
      .sample_in(sin_sample),
      .sample_in_valid(sample_cycle_count == 2),
      .sample_out(sin_upsample)
  );

  dlt_sig_dac_2nd_order ds_dac (
      .clk(clk_100mhz),
      .rst(sys_rst),
      .current_sample(sample_out),
      .audio_out(sin_wave)
  );

  always_ff @(posedge clk_100mhz) begin
    square_state <= (square_count == 0) ^ square_state;

    impulse_approx <= square_state && (square_count < 1000);
    square_wave <= square_state;
  end

  always_comb begin
    case (sw[1:0])
      2'b00:   spk_out = sw[2] ? square_wave : 0;
      2'b01:   spk_out = sw[2] ? impulse_approx : 0;
      default: spk_out = sin_wave;
    endcase
  end

endmodule  // top_level

`default_nettype wire
