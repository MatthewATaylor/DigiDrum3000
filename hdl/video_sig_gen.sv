module video_sig_gen
#(
  parameter ACTIVE_H_PIXELS = 1280,
  parameter H_FRONT_PORCH = 110,
  parameter H_SYNC_WIDTH = 40,
  parameter H_BACK_PORCH = 220,
  parameter ACTIVE_LINES = 720,
  parameter V_FRONT_PORCH = 5,
  parameter V_SYNC_WIDTH = 5,
  parameter V_BACK_PORCH = 20,
  parameter FPS = 60)
(
  input wire pixel_clk,
  input wire rst,
  output logic [$clog2(TOTAL_PIXELS)-1:0] h_count,
  output logic [$clog2(TOTAL_LINES)-1:0] v_count,
  output logic v_sync, //vertical sync out
  output logic h_sync, //horizontal sync out
  output logic active_draw,
  output logic new_frame, //single cycle enable signal
  output logic [5:0] frame_count); //frame

    localparam TOTAL_PIXELS = ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH + H_BACK_PORCH;
    localparam TOTAL_LINES = ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH;

    logic [$clog2(TOTAL_PIXELS)-1:0] next_hcount;
    logic [$clog2(TOTAL_LINES)-1:0] next_vcount;

    always @(posedge pixel_clk) begin
        if (rst) begin
            h_count <= 0;
            v_count <= 0;
            v_sync <= 0;
            h_sync <= 0;
            active_draw <= 0;
            new_frame <= 0;
            frame_count <= 0;

            next_hcount <= 1;
            next_vcount <= 1;
        end else begin
            h_count <= next_hcount;
            v_count <= next_vcount;

            if (next_hcount < TOTAL_PIXELS - 1) begin
                next_hcount <= next_hcount + 1;
            end else begin
                next_hcount <= 0;
                if (next_vcount < TOTAL_LINES - 1) begin
                    next_vcount <= next_vcount + 1;
                end else begin
                    next_vcount <= 0;
                end
            end

            if (next_hcount < ACTIVE_H_PIXELS && next_vcount < ACTIVE_LINES) begin
                active_draw <= 1;
                h_sync <= 0;
                v_sync <= 0;
            end else begin
                active_draw <= 0;

                if (next_hcount >= ACTIVE_H_PIXELS + H_FRONT_PORCH &&
                    next_hcount < ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH) begin
                    h_sync <= 1;
                end else begin
                    h_sync <= 0;
                end

                if (next_vcount >= ACTIVE_LINES + V_FRONT_PORCH &&
                    next_vcount < ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH) begin
                    v_sync <= 1;
                end else begin
                    v_sync <= 0;
                end
            end

            if (next_hcount == ACTIVE_H_PIXELS && next_vcount == ACTIVE_LINES - 1) begin
                new_frame <= 1;
                if (frame_count < FPS - 1) begin
                    frame_count <= frame_count + 1;
                end else begin
                    frame_count <= 0;
                end
            end else begin
                new_frame <= 0;
            end
        end
    end
endmodule
