module tm_choice (
  input wire [7:0] d,
  output logic [8:0] q_m);
    
    logic [3:0] num_ones;

    always_comb begin
        num_ones = 0;
        foreach (d[i]) begin
            num_ones += d[i];
        end

        q_m[0] = d[0];
        if (num_ones > 4 || (num_ones == 4 && ~d[0])) begin
            for (integer i = 1; i < 8; i = i + 1) begin
                q_m[i] = ~(d[i] ^ q_m[i-1]);
            end
            q_m[8] = 0;
        end else begin
            for (integer i = 1; i < 8; i = i + 1) begin
                q_m[i] = d[i] ^ q_m[i-1];
            end
            q_m[8] = 1;
        end
    end
endmodule
