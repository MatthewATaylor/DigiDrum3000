`timescale 1ns / 1ps
`default_nettype none

module dist_ram 
    #(
        parameter WIDTH=16,
        parameter DEPTH=64
    )
    (
        input  wire                      clk,
        input  wire  [$clog2(DEPTH)-1:0] addr,
        input  wire                      we,
        input  wire  [WIDTH-1:0]         din,
        output logic [WIDTH-1:0]         dout
    );

    logic [WIDTH-1:0] data [DEPTH-1:0];
    assign dout = data[addr];

    always_ff @(posedge clk) begin
        if (we) begin
            data[addr] <= din;
        end
    end

endmodule

`default_nettype wire
