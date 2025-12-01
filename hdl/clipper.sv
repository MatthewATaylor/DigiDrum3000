`timescale 1ns / 1ps
`default_nettype none

module clipper
    #(
        parameter WIDTH_FULL,
        parameter WIDTH_CLIP
    )
    (
        input  wire  [WIDTH_FULL-1:0] din,
        output logic [WIDTH_CLIP-1:0] dout
    );

    logic [WIDTH_FULL-WIDTH_CLIP:0] comparison_bits;

    always_comb begin
        comparison_bits = din[WIDTH_FULL-1:WIDTH_CLIP-1];
        if ($signed(comparison_bits) < -2'sd1) begin
            dout = {1'b1, {WIDTH_CLIP-1{1'b0}}};
        end else if ($signed(comparison_bits) > 2'sd0) begin
            dout = {1'b0, {WIDTH_CLIP-1{1'b1}}};
        end else begin
            dout = din[WIDTH_CLIP-1:0];
        end
    end

endmodule

`default_nettype wire

