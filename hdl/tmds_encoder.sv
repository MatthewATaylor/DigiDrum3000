`timescale 1ns / 1ps
`default_nettype none

module tmds_encoder(
  input wire clk,
  input wire rst,
  input wire [7:0] video_data,  // video data (red, green or blue)
  input wire [1:0] control, //for blue set to {vs,hs}, else will be 0
  input wire video_enable,  // video data enable, to choose between control or video signal
  output logic [9:0] tmds
);

    logic [8:0] q_m;
    logic [4:0] tally;
    logic [3:0] n1;
    logic [3:0] n0;

    tm_choice mtm(
        .d(video_data),
        .q_m(q_m)
    );

    always_comb begin
        n1 = 0;
        n0 = 0;
        for (integer i = 0; i < 8; i = i + 1) begin
            n1 += q_m[i];
            n0 += ~q_m[i];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            tmds <= 0;
            tally <= 0;
        end else begin
            if (video_enable) begin
                if (tally == 0 || n1 == n0) begin
                    tmds[9] <= ~q_m[8];
                    tmds[8] <= q_m[8];
                    tmds[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                    if (q_m[8] == 0) begin
                        tally <= tally + n0 - n1;
                    end else begin
                        tally <= tally + n1 - n0;
                    end
                end else begin
                    if ((tally[4] == 0 && n1 > n0) || (tally[4] == 1 && n0 > n1)) begin
                        tmds[9] <= 1;
                        tmds[8] <= q_m[8];
                        tmds[7:0] <= ~q_m[7:0];
                        tally <= tally + (q_m[8] << 1) + n0 - n1;
                    end else begin
                        tmds[9] <= 0;
                        tmds[8] <= q_m[8];
                        tmds[7:0] <= q_m[7:0];
                        tally <= tally - (q_m[8] ? 2'b00 : 2'b10) + n1 - n0;
                    end
                end
            end else begin
                tally <= 0;
                case (control)
                    2'b00: tmds <= 10'b1101010100;
                    2'b01: tmds <= 10'b0010101011;
                    2'b10: tmds <= 10'b0101010100;
                    2'b11: tmds <= 10'b1010101011;
                endcase
            end
        end
    end

endmodule //end tmds_encoder
`default_nettype wire
