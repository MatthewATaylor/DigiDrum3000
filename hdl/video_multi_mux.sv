`timescale 1ns / 1ps  //
`default_nettype none

module video_multi_mux (
    input wire clk,
    input wire rst,

    input wire [2:0] delay_src,
    input wire [2:0] output_src,
    input wire [2:0] crush_src,
    input wire [2:0] distortion_src,
    input wire [2:0] filter_src,
    input wire [2:0] reverb_src,

    input wire [10:0] h_count_from_base,
    input wire [ 9:0] v_count_from_base,
    input wire        active_draw_from_base,
    input wire [23:0] pixel_from_base,

    input wire [10:0] h_count_from_crush,
    input wire [ 9:0] v_count_from_crush,
    input wire        active_draw_from_crush,
    input wire [23:0] pixel_from_crush,

    input wire [10:0] h_count_from_distortion,
    input wire [ 9:0] v_count_from_distortion,
    input wire        active_draw_from_distortion,
    input wire [23:0] pixel_from_distortion,

    input wire [10:0] h_count_from_filter,
    input wire [ 9:0] v_count_from_filter,
    input wire        active_draw_from_filter,
    input wire [23:0] pixel_from_filter,

    input wire [10:0] h_count_from_reverb,
    input wire [ 9:0] v_count_from_reverb,
    input wire        active_draw_from_reverb,
    input wire [23:0] pixel_from_reverb,

    output logic [10:0] h_count_to_output,
    output logic [ 9:0] v_count_to_output,
    output logic        active_draw_to_output,
    output logic [23:0] pixel_to_output,

    output logic [10:0] h_count_to_crush,
    output logic [ 9:0] v_count_to_crush,
    output logic        active_draw_to_crush,
    output logic [23:0] pixel_to_crush,

    output logic [10:0] h_count_to_distortion,
    output logic [ 9:0] v_count_to_distortion,
    output logic        active_draw_to_distortion,
    output logic [23:0] pixel_to_distortion,

    output logic [10:0] h_count_to_filter,
    output logic [ 9:0] v_count_to_filter,
    output logic        active_draw_to_filter,
    output logic [23:0] pixel_to_filter,

    output logic [10:0] h_count_to_reverb,
    output logic [ 9:0] v_count_to_reverb,
    output logic        active_draw_to_reverb,
    output logic [23:0] pixel_to_reverb
);
  logic [ 2:0] true_output_src;
  logic [ 2:0] true_crush_src;
  logic [ 2:0] true_distortion_src;
  logic [ 2:0] true_filter_src;
  logic [ 2:0] true_reverb_src;

  logic [10:0] h_count_base;
  logic [ 9:0] v_count_base;
  logic        active_draw_base;
  logic [23:0] pixel_base;

  logic [10:0] h_count_crush;
  logic [ 9:0] v_count_crush;
  logic        active_draw_crush;
  logic [23:0] pixel_crush;

  logic [10:0] h_count_distortion;
  logic [ 9:0] v_count_distortion;
  logic        active_draw_distortion;
  logic [23:0] pixel_distortion;

  logic [10:0] h_count_filter;
  logic [ 9:0] v_count_filter;
  logic        active_draw_filter;
  logic [23:0] pixel_filter;

  logic [10:0] h_count_reverb;
  logic [ 9:0] v_count_reverb;
  logic        active_draw_reverb;
  logic [23:0] pixel_reverb;

  always_ff @(posedge clk) begin
    if (rst) begin
      true_output_src     <= 0;
      true_crush_src      <= 0;
      true_distortion_src <= 0;
      true_filter_src     <= 0;
      true_reverb_src     <= 0;
    end else begin
      true_output_src     <= output_src == 3'b001 ? delay_src : output_src;
      true_crush_src      <= crush_src == 3'b001 ? delay_src : crush_src;
      true_distortion_src <= distortion_src == 3'b001 ? delay_src : distortion_src;
      true_filter_src     <= filter_src == 3'b001 ? delay_src : filter_src;
      true_reverb_src     <= reverb_src == 3'b001 ? delay_src : reverb_src;
    end
  end

  always_ff @(posedge clk) begin
    h_count_base           <= h_count_from_base;
    v_count_base           <= v_count_from_base;
    active_draw_base       <= active_draw_from_base;
    pixel_base             <= pixel_from_base;

    h_count_crush          <= h_count_from_crush;
    v_count_crush          <= v_count_from_crush;
    active_draw_crush      <= active_draw_from_crush;
    pixel_crush            <= pixel_from_crush;

    h_count_distortion     <= h_count_from_distortion;
    v_count_distortion     <= v_count_from_distortion;
    active_draw_distortion <= active_draw_from_distortion;
    pixel_distortion       <= pixel_from_distortion;

    h_count_filter         <= h_count_from_filter;
    v_count_filter         <= v_count_from_filter;
    active_draw_filter     <= active_draw_from_filter;
    pixel_filter           <= pixel_from_filter;

    h_count_reverb         <= h_count_from_reverb;
    v_count_reverb         <= v_count_from_reverb;
    active_draw_reverb     <= active_draw_from_reverb;
    pixel_reverb           <= pixel_from_reverb;

    case (true_output_src)
      3'b000: begin
        h_count_to_output <= h_count_base;
        v_count_to_output <= v_count_base;
        active_draw_to_output <= active_draw_base;
        pixel_to_output <= pixel_base;
      end
      3'b010: begin
        h_count_to_output <= h_count_reverb;
        v_count_to_output <= v_count_reverb;
        active_draw_to_output <= active_draw_reverb;
        pixel_to_output <= pixel_reverb;
      end
      3'b011: begin
        h_count_to_output <= h_count_filter;
        v_count_to_output <= v_count_filter;
        active_draw_to_output <= active_draw_filter;
        pixel_to_output <= pixel_filter;
      end
      3'b100: begin
        h_count_to_output <= h_count_distortion;
        v_count_to_output <= v_count_distortion;
        active_draw_to_output <= active_draw_distortion;
        pixel_to_output <= pixel_distortion;
      end
      3'b101: begin
        h_count_to_output <= h_count_crush;
        v_count_to_output <= v_count_crush;
        active_draw_to_output <= active_draw_crush;
        pixel_to_output <= pixel_crush;
      end
      default: begin  // should never happen, i.e. don't care about behaviour
        h_count_to_output <= 11'hXXX;
        v_count_to_output <= 10'hXXX;
        active_draw_to_output <= 1'bX;
        pixel_to_output <= 24'hXXXXXX;
      end
    endcase

    case (true_reverb_src)
      3'b000: begin
        h_count_to_reverb <= h_count_base;
        v_count_to_reverb <= v_count_base;
        active_draw_to_reverb <= active_draw_base;
        pixel_to_reverb <= pixel_base;
      end
      3'b010: begin
        h_count_to_reverb <= h_count_reverb;
        v_count_to_reverb <= v_count_reverb;
        active_draw_to_reverb <= active_draw_reverb;
        pixel_to_reverb <= pixel_reverb;
      end
      3'b011: begin
        h_count_to_reverb <= h_count_filter;
        v_count_to_reverb <= v_count_filter;
        active_draw_to_reverb <= active_draw_filter;
        pixel_to_reverb <= pixel_filter;
      end
      3'b100: begin
        h_count_to_reverb <= h_count_distortion;
        v_count_to_reverb <= v_count_distortion;
        active_draw_to_reverb <= active_draw_distortion;
        pixel_to_reverb <= pixel_distortion;
      end
      3'b101: begin
        h_count_to_reverb <= h_count_crush;
        v_count_to_reverb <= v_count_crush;
        active_draw_to_reverb <= active_draw_crush;
        pixel_to_reverb <= pixel_crush;
      end
      default: begin  // should never happen, i.e. don't care about behaviour
        h_count_to_reverb <= 11'hXXX;
        v_count_to_reverb <= 10'hXXX;
        active_draw_to_reverb <= 1'bX;
        pixel_to_reverb <= 24'hXXXXXX;
      end
    endcase

    case (true_filter_src)
      3'b000: begin
        h_count_to_filter <= h_count_base;
        v_count_to_filter <= v_count_base;
        active_draw_to_filter <= active_draw_base;
        pixel_to_filter <= pixel_base;
      end
      3'b010: begin
        h_count_to_filter <= h_count_reverb;
        v_count_to_filter <= v_count_reverb;
        active_draw_to_filter <= active_draw_reverb;
        pixel_to_filter <= pixel_reverb;
      end
      3'b011: begin
        h_count_to_filter <= h_count_filter;
        v_count_to_filter <= v_count_filter;
        active_draw_to_filter <= active_draw_filter;
        pixel_to_filter <= pixel_filter;
      end
      3'b100: begin
        h_count_to_filter <= h_count_distortion;
        v_count_to_filter <= v_count_distortion;
        active_draw_to_filter <= active_draw_distortion;
        pixel_to_filter <= pixel_distortion;
      end
      3'b101: begin
        h_count_to_filter <= h_count_crush;
        v_count_to_filter <= v_count_crush;
        active_draw_to_filter <= active_draw_crush;
        pixel_to_filter <= pixel_crush;
      end
      default: begin  // should never happen, i.e. don't care about behaviour
        h_count_to_filter <= 11'hXXX;
        v_count_to_filter <= 10'hXXX;
        active_draw_to_filter <= 1'bX;
        pixel_to_filter <= 24'hXXXXXX;
      end
    endcase

    case (true_distortion_src)
      3'b000: begin
        h_count_to_distortion <= h_count_base;
        v_count_to_distortion <= v_count_base;
        active_draw_to_distortion <= active_draw_base;
        pixel_to_distortion <= pixel_base;
      end
      3'b010: begin
        h_count_to_distortion <= h_count_reverb;
        v_count_to_distortion <= v_count_reverb;
        active_draw_to_distortion <= active_draw_reverb;
        pixel_to_distortion <= pixel_reverb;
      end
      3'b011: begin
        h_count_to_distortion <= h_count_filter;
        v_count_to_distortion <= v_count_filter;
        active_draw_to_distortion <= active_draw_filter;
        pixel_to_distortion <= pixel_filter;
      end
      3'b100: begin
        h_count_to_distortion <= h_count_distortion;
        v_count_to_distortion <= v_count_distortion;
        active_draw_to_distortion <= active_draw_distortion;
        pixel_to_distortion <= pixel_distortion;
      end
      3'b101: begin
        h_count_to_distortion <= h_count_crush;
        v_count_to_distortion <= v_count_crush;
        active_draw_to_distortion <= active_draw_crush;
        pixel_to_distortion <= pixel_crush;
      end
      default: begin  // should never happen, i.e. don't care about behaviour
        h_count_to_distortion <= 11'hXXX;
        v_count_to_distortion <= 10'hXXX;
        active_draw_to_distortion <= 1'bX;
        pixel_to_distortion <= 24'hXXXXXX;
      end
    endcase

    case (true_crush_src)
      3'b000: begin
        h_count_to_crush <= h_count_base;
        v_count_to_crush <= v_count_base;
        active_draw_to_crush <= active_draw_base;
        pixel_to_crush <= pixel_base;
      end
      3'b010: begin
        h_count_to_crush <= h_count_reverb;
        v_count_to_crush <= v_count_reverb;
        active_draw_to_crush <= active_draw_reverb;
        pixel_to_crush <= pixel_reverb;
      end
      3'b011: begin
        h_count_to_crush <= h_count_filter;
        v_count_to_crush <= v_count_filter;
        active_draw_to_crush <= active_draw_filter;
        pixel_to_crush <= pixel_filter;
      end
      3'b100: begin
        h_count_to_crush <= h_count_distortion;
        v_count_to_crush <= v_count_distortion;
        active_draw_to_crush <= active_draw_distortion;
        pixel_to_crush <= pixel_distortion;
      end
      3'b101: begin
        h_count_to_crush <= h_count_crush;
        v_count_to_crush <= v_count_crush;
        active_draw_to_crush <= active_draw_crush;
        pixel_to_crush <= pixel_crush;
      end
      default: begin  // should never happen, i.e. don't care about behaviour
        h_count_to_crush <= 11'hXXX;
        v_count_to_crush <= 10'hXXX;
        active_draw_to_crush <= 1'bX;
        pixel_to_crush <= 24'hXXXXXX;
      end
    endcase
  end

endmodule

`default_nettype wire
