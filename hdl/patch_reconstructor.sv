`timescale 1ns / 1ps  //
`default_nettype none

module patch_reconstructor (
    input wire clk,
    input wire rst,

    output logic dry,
    output logic crush_val,
    output logic distortion_val,
    output logic filter_val,
    output logic reverb_val,
    output logic delay_val,
    input  wire  crush,
    input  wire  distortion,
    input  wire  filter,
    input  wire  reverb,
    input  wire  delay,

    output logic [2:0] output_src,
    output logic [2:0] crush_src,
    output logic [2:0] distortion_src,
    output logic [2:0] filter_src,
    output logic [2:0] reverb_src,
    output logic [2:0] delay_src
);

  enum {
    READING_PATCH,
    TRAVERSING_PATCH_PATH,
    REVERSING_PATH
  } state;

  logic [2:0] cur_patch;
  logic [2:0] cur_path_pos;
  logic [4:0] patch_connections[5:0];
  logic [4:0] patch_mask;
  logic [2:0] patch_path[5:0];
  logic [2:0] out_buffer[5:0];
  logic [7:0] read_timer;
  logic [2:0] patch_leading_ones;
  logic path_end_reached;

  // temp for debugging
  logic [4:0] cur_connection;
  assign cur_connection = patch_connections[cur_patch];
  logic [4:0] connection_mask;
  assign connection_mask = ((5'h1 << cur_patch));

  count_leading_ones my_clo (
      .din ({patch_connections[cur_patch] | patch_mask, 3'b0}),
      .dout(patch_leading_ones)
  );

  assign dry            = state != READING_PATCH || !(cur_patch == 3'b101);
  assign crush_val      = state != READING_PATCH || !(cur_patch == 3'b000);
  assign distortion_val = state != READING_PATCH || !(cur_patch == 3'b001);
  assign filter_val     = state != READING_PATCH || !(cur_patch == 3'b010);
  assign reverb_val     = state != READING_PATCH || !(cur_patch == 3'b011);
  assign delay_val      = state != READING_PATCH || !(cur_patch == 3'b100);

  always_ff @(posedge clk) begin
    if (rst) begin
      cur_patch        <= 3'h0;
      cur_path_pos     <= 3'b0;
      state            <= READING_PATCH;
      read_timer       <= 8'h0;
      patch_mask       <= 5'h0;
      path_end_reached <= 1'h0;
      output_src       <= 3'h0;
      crush_src        <= 3'h7;
      distortion_src   <= 3'h7;
      filter_src       <= 3'h7;
      reverb_src       <= 3'h7;
      delay_src        <= 3'h7;

    end else begin
      case (state)
        READING_PATCH: begin
          if (read_timer >= 8'hC0) begin
            patch_connections[cur_patch] <= {delay, reverb, filter, distortion, crush} | (5'h1 << cur_patch);
            read_timer <= 0;
            if (cur_patch == 3'b101) begin
              state        <= TRAVERSING_PATCH_PATH;
              cur_patch    <= 3'b101;
              cur_path_pos <= 3'b0;
              patch_mask   <= 5'b0;
            end else begin
              cur_patch <= cur_patch + 3'h1;
            end
          end else begin
            read_timer <= read_timer + 8'h1;
          end

        end
        TRAVERSING_PATCH_PATH: begin
          if (patch_leading_ones == 3'b101) begin  // reached end of current chain
            patch_path[cur_path_pos] <= cur_patch;
            if (cur_path_pos == 3'b101) begin
              cur_path_pos <= 3'h0;
              cur_patch <= 3'b101;
              path_end_reached <= 1'h0;
              state <= REVERSING_PATH;
              for (integer i = 0; i < 6; i = i + 1) begin
                out_buffer[i] <= 3'b111;
              end
            end else begin
              cur_path_pos <= cur_path_pos + 3'b001;
              cur_patch <= 3'b101;
              patch_mask <= patch_mask | (5'b00001 << cur_patch);
            end

          end else begin
            if (read_timer >= 8'hF) begin // just in case patch is changed during read -> invalid state -> infinite loop
              state      <= READING_PATCH;
              read_timer <= 8'h0;
              cur_patch  <= 3'b000;
            end else begin
              read_timer <= read_timer + 8'h1;
              cur_patch  <= 3'b100 - patch_leading_ones;
            end
          end

        end
        default: begin  //REVERSING_PATH
          if (path_end_reached) begin
            read_timer     <= 0;
            state          <= READING_PATCH;
            cur_patch      <= 0;
            output_src     <= out_buffer[3'b101];
            crush_src      <= out_buffer[3'b000];
            distortion_src <= out_buffer[3'b001];
            filter_src     <= out_buffer[3'b010];
            reverb_src     <= out_buffer[3'b011];
            delay_src      <= out_buffer[3'b100];
          end else begin
            cur_patch <= patch_path[cur_path_pos];
            cur_path_pos <= cur_path_pos + 1;
            path_end_reached <= patch_path[cur_path_pos] == 3'b101;
            out_buffer[cur_patch] <= 3'b101 - patch_path[cur_path_pos];
          end
        end
      endcase
    end
  end

endmodule

module count_leading_ones #(
    parameter WIDTH = 8  // pow of 2
) (
    input wire [WIDTH-1:0] din,
    output logic [$clog2(WIDTH):0] dout
);
  parameter OUT_WIDTH = $clog2(WIDTH) + 1;

  logic [(WIDTH/2)-1:0] lh_din;
  logic [(WIDTH/2)-1:0] rh_din;
  logic [$clog2(WIDTH)-1:0] lh_dout;
  logic [$clog2(WIDTH)-1:0] rh_dout;

  generate
    if (WIDTH == 2) begin
      assign dout = !din[1] ? 2'b00 : !din[0] ? 2'b01 : 2'b10;
    end else begin
      assign lh_din = din[WIDTH-1:WIDTH/2];
      assign rh_din = din[WIDTH/2-1:0];
      count_leading_ones #(WIDTH / 2) lh_unset (
          .din (lh_din),
          .dout(lh_dout)
      );
      count_leading_ones #(WIDTH / 2) rh_unset (
          .din (rh_din),
          .dout(rh_dout)
      );
      always_comb begin
        if (lh_dout[$clog2(WIDTH)-1] && rh_dout[$clog2(WIDTH)-1]) begin
          dout = {1'b1, {(OUT_WIDTH - 1) {1'b0}}};
        end else if (lh_dout[$clog2(WIDTH)-1]) begin
          dout = {2'b01, rh_dout[$clog2(WIDTH)-2:0]};
        end else begin
          dout = {2'b00, lh_dout[$clog2(WIDTH)-2:0]};
        end
      end
    end
  endgenerate
endmodule

`default_nettype wire
