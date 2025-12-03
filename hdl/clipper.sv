`timescale 1ns / 1ps
`default_nettype none

module clipper
    #(
        parameter WIDTH_FULL,
        parameter WIDTH_CLIP,
        parameter RIGHT_SHIFT
    )
    (
        input  wire  [WIDTH_FULL-1:0] din,
        output logic [WIDTH_CLIP-1:0] dout
    );

    localparam OUT_INDEX_MAX = RIGHT_SHIFT+WIDTH_CLIP-1;

    always_comb begin
        if ($signed(din[WIDTH_FULL-1:OUT_INDEX_MAX]) < -2'sd1) begin
            dout = {1'b1, {WIDTH_CLIP-1{1'b0}}};
        end else if ($signed(din[WIDTH_FULL-1:OUT_INDEX_MAX]) > 2'sd0) begin
            dout = {1'b0, {WIDTH_CLIP-1{1'b1}}};
        end else begin
            dout = din[OUT_INDEX_MAX:RIGHT_SHIFT];
        end
    end

endmodule

`default_nettype wire

