`timescale 1ns / 1ps
`default_nettype none

module crc32
    (
        input  wire         clk,
        input  wire         rst,
        input  wire         din_valid,
        input  wire   [1:0] din,
        output logic [31:0] dout
    );

    // Receive two bits per clk cycle
    // First, combinationally compute result after inputting din LSb
    logic        xor_in_lsb;
    logic [31:0] result_lsb;
    always_comb begin
        xor_in_lsb     = din[0] ^ dout[31];
        result_lsb[0]  = xor_in_lsb;
        result_lsb[1]  = xor_in_lsb ^ dout[0];
        result_lsb[2]  = xor_in_lsb ^ dout[1];
        result_lsb[3]  = dout[2];
        result_lsb[4]  = xor_in_lsb ^ dout[3];
        result_lsb[5]  = xor_in_lsb ^ dout[4];
        result_lsb[6]  = dout[5];
        result_lsb[7]  = xor_in_lsb ^ dout[6];
        result_lsb[8]  = xor_in_lsb ^ dout[7];
        result_lsb[9]  = dout[8];
        result_lsb[10] = xor_in_lsb ^ dout[9];
        result_lsb[11] = xor_in_lsb ^ dout[10];
        result_lsb[12] = xor_in_lsb ^ dout[11];
        result_lsb[13] = dout[12];
        result_lsb[14] = dout[13];
        result_lsb[15] = dout[14];
        result_lsb[16] = xor_in_lsb ^ dout[15];
        result_lsb[17] = dout[16];
        result_lsb[18] = dout[17];
        result_lsb[19] = dout[18];
        result_lsb[20] = dout[19];
        result_lsb[21] = dout[20];
        result_lsb[22] = xor_in_lsb ^ dout[21];
        result_lsb[23] = xor_in_lsb ^ dout[22];
        result_lsb[24] = dout[23];
        result_lsb[25] = dout[24];
        result_lsb[26] = xor_in_lsb ^ dout[25];
        result_lsb[27] = dout[26];
        result_lsb[28] = dout[27];
        result_lsb[29] = dout[28];
        result_lsb[30] = dout[29];
        result_lsb[31] = dout[30];
    end


    // Second, compute result after inputting din MSb
    logic  xor_in_msb;
    assign xor_in_msb = din[1] ^ result_lsb[31];
    always_ff @ (posedge clk) begin
        if (rst) begin
            dout <= 32'hFFFF_FFFF;
        end else begin
            if (din_valid) begin
                dout[0]  <= xor_in_msb;
                dout[1]  <= xor_in_msb ^ result_lsb[0];
                dout[2]  <= xor_in_msb ^ result_lsb[1];
                dout[3]  <= result_lsb[2];
                dout[4]  <= xor_in_msb ^ result_lsb[3];
                dout[5]  <= xor_in_msb ^ result_lsb[4];
                dout[6]  <= result_lsb[5];
                dout[7]  <= xor_in_msb ^ result_lsb[6];
                dout[8]  <= xor_in_msb ^ result_lsb[7];
                dout[9]  <= result_lsb[8];
                dout[10] <= xor_in_msb ^ result_lsb[9];
                dout[11] <= xor_in_msb ^ result_lsb[10];
                dout[12] <= xor_in_msb ^ result_lsb[11];
                dout[13] <= result_lsb[12];
                dout[14] <= result_lsb[13];
                dout[15] <= result_lsb[14];
                dout[16] <= xor_in_msb ^ result_lsb[15];
                dout[17] <= result_lsb[16];
                dout[18] <= result_lsb[17];
                dout[19] <= result_lsb[18];
                dout[20] <= result_lsb[19];
                dout[21] <= result_lsb[20];
                dout[22] <= xor_in_msb ^ result_lsb[21];
                dout[23] <= xor_in_msb ^ result_lsb[22];
                dout[24] <= result_lsb[23];
                dout[25] <= result_lsb[24];
                dout[26] <= xor_in_msb ^ result_lsb[25];
                dout[27] <= result_lsb[26];
                dout[28] <= result_lsb[27];
                dout[29] <= result_lsb[28];
                dout[30] <= result_lsb[29];
                dout[31] <= result_lsb[30];
            end
        end
    end
endmodule

`default_nettype wire
