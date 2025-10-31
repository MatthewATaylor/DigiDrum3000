module test_pattern_generator(
  input wire [1:0] pattern_select,
  input wire [10:0] h_count,
  input wire [9:0] v_count,
  output logic [7:0] pixel_red,
  output logic [7:0] pixel_green,
  output logic [7:0] pixel_blue
  );

    always_comb begin
        case (pattern_select)
            2'b00: begin
                pixel_red = 8'h68;
                pixel_green = 8'h00;
                pixel_blue = 8'hf2;
            end

            2'b01: begin
                if (v_count == 360 || h_count == 640) begin
                    pixel_red = 8'hff;
                    pixel_green = 8'hff;
                    pixel_blue = 8'hff;
                end else begin
                    pixel_red = 8'h00;
                    pixel_green = 8'h00;
                    pixel_blue = 8'h00;
                end
            end

            2'b10: begin
                pixel_red = h_count[7:0];
                pixel_green = h_count[7:0];
                pixel_blue = h_count[7:0];
            end

            2'b11: begin
                pixel_red = h_count[7:0];
                pixel_green = v_count[7:0];
                pixel_blue = h_count + v_count;
            end
        endcase
    end
endmodule
