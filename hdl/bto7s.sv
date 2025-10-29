module bto7s(
        input wire [3:0]   x,
        output logic [6:0] s);
    logic [15:0] num;
    assign num[0] = ~x[3] && ~x[2] && ~x[1] && ~x[0];
    assign num[1] = ~x[3] && ~x[2] && ~x[1] && x[0];
    assign num[2] = x == 4'd2;
    assign num[3] = x == 4'd3;
    assign num[4] = x == 4'd4;
    assign num[5] = x == 4'd5;
    assign num[6] = x == 4'd6;
    assign num[7] = x == 4'd7;
    assign num[8] = x == 4'd8;
    assign num[9] = x == 4'd9;
    assign num[10] = x == 4'd10;
    assign num[11] = x == 4'd11;
    assign num[12] = x == 4'd12;
    assign num[13] = x == 4'd13;
    assign num[14] = x == 4'd14;
    assign num[15] = x == 4'd15;

    assign s[0] = num[0] || num[2] || num[3] || num[5] || num[6] || num[7] || num[8] || num[9] || num[10] || num[12] || num[14] || num[15];
    assign s[1] = num[0] || num[1] || num[2] || num[3] || num[4] || num[7] || num[8] || num[9] || num[10] || num[13];
    assign s[2] = num[0] || num[1] || num[3] || num[4] || num[5] || num[6] || num[7] || num[8] || num[9] || num[10] || num[11] || num[13];
    assign s[3] = num[0] || num[2] || num[3] || num[5] || num[6] || num[8] || num[9] || num[11] || num[12] || num[13] || num[14];
    assign s[4] = num[0] || num[2] || num[6] || num[8] || num[10] || num[11] || num[12] || num[13] || num[14] || num[15];
    assign s[5] = num[0] || num[4] || num[5] || num[6] || num[8] || num[9] || num[10] || num[11] || num[12] || num[14] || num[15];
    assign s[6] = num[2] || num[3] || num[4] || num[5] || num[6] || num[8] || num[9] || num[10] || num[11] || num[13] || num[14] || num[15];
endmodule

