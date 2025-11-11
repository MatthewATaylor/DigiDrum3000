`timescale 1ns / 1ps  //
`default_nettype none

module pot_state (
    input wire clk,
    input wire rst,

    input wire [9:0] value,
    input wire [3:0] pot_index,
    input wire value_valid,

    output logic [9:0] volume,
    output logic [9:0] pitch,
    output logic [9:0] delay_wet,
    output logic [9:0] delay_rate,
    output logic [9:0] delay_feedback,
    output logic [9:0] reverb_wet,
    output logic [9:0] reverb_size,
    output logic [9:0] reverb_feedback,
    output logic [9:0] filter_quality,
    output logic [9:0] filter_cutoff,
    output logic [9:0] distortion_drive,
    output logic [9:0] crush_pressure
);
  always_ff @(posedge clk) begin
    if (rst) begin
      volume           <= 0;
      reverb_feedback  <= 0;
      pitch            <= 0;
      reverb_size      <= 0;
      crush_pressure   <= 0;
      reverb_wet       <= 0;
      distortion_drive <= 0;
      delay_feedback   <= 0;
      filter_cutoff    <= 0;
      delay_rate       <= 0;
      filter_quality   <= 0;
      delay_wet        <= 0;
    end else if (value_valid) begin
      // ternary expression is to remove jitter.
      // loses 1 representable vaule (10'h3FF) (~0.00141 bit loss)
      case (pot_index)
        4'd0:    volume           <= value > volume           ? value - 1 : value;
        4'd1:    reverb_feedback  <= value > reverb_feedback  ? value - 1 : value;
        4'd2:    pitch            <= value > pitch            ? value - 1 : value;
        4'd3:    reverb_size      <= value > reverb_size      ? value - 1 : value;
        4'd4:    crush_pressure   <= value > crush_pressure   ? value - 1 : value;
        4'd5:    reverb_wet       <= value > reverb_wet       ? value - 1 : value;
        4'd6:    distortion_drive <= value > distortion_drive ? value - 1 : value;
        4'd7:    delay_feedback   <= value > delay_feedback   ? value - 1 : value;
        4'd8:    filter_cutoff    <= value > filter_cutoff    ? value - 1 : value;
        4'd9:    delay_rate       <= value > delay_rate       ? value - 1 : value;
        4'd10:   filter_quality   <= value > filter_quality   ? value - 1 : value;
        default: delay_wet        <= value > delay_wet        ? value - 1 : value;
      endcase
    end
  end
endmodule  // pot_state

`default_nettype wire
