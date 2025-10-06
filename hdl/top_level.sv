`default_nettype none  // prevents system from inferring an undeclared logic (good practice)

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
  assign led  = btn;

  //have btnd control system reset
  logic sys_rst;
  assign sys_rst = btn[0];

  logic spk_out;
  assign spkl = spk_out;
  assign spkr = spk_out;

  logic square_wave;
  logic impulse_approx;

  logic [31:0] square_count;
  logic square_state;
  counter wave_count (
      .clk(clk_100mhz),
      .rst(sys_rst),
      .period(50000),
      .count(square_count)
  );

  always_ff @(posedge clk_100mhz) begin
    square_state <= (square_count == 0) ^ square_state;

    impulse_approx <= square_state && (square_count < 1000);  // impulse approximation
    square_wave <= square_state;
  end

  always_comb begin
    case (sw[0])
      1'b0: spk_out = square_wave;
      default: spk_out = impulse_approx;
    endcase
  end

endmodule  // top_level

`default_nettype wire
