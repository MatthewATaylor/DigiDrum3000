`default_nettype none
module seven_segment_controller #(parameter COUNT_PERIOD = 100000)
  (input wire           clk,
   input wire           rst,
   input wire [31:0]    val,
   output logic[6:0]    cat,
   output logic[7:0]    an
  );
 
  logic [7:0]   segment_state;
  logic [31:0]  segment_counter;
  logic [3:0]   sel_values;
  logic [6:0]   led_out;
 
  assign sel_values =
    (val[3:0] & {4{segment_state[0]}}) |
    (val[7:4] & {4{segment_state[1]}}) |
    (val[11:8] & {4{segment_state[2]}}) |
    (val[15:12] & {4{segment_state[3]}}) |
    (val[19:16] & {4{segment_state[4]}}) |
    (val[23:20] & {4{segment_state[5]}}) |
    (val[27:24] & {4{segment_state[6]}}) |
    (val[31:28] & {4{segment_state[7]}});

  bto7s mbto7s (.x(sel_values), .s(led_out));
  assign cat = ~led_out; //<--note this inversion is needed
  assign an = ~segment_state; //note this inversion is needed
 
  always_ff @(posedge clk)begin
    if (rst)begin
      segment_state <= 8'b0000_0001;
      segment_counter <= 0;
    end else begin
      if (segment_counter == COUNT_PERIOD) begin
        segment_counter <= 0;
        segment_state <= {segment_state[6:0],segment_state[7]};
      end else begin
        segment_counter <= segment_counter +1;
      end
    end
  end
endmodule // seven_segment_controller
 
`default_nettype wire
