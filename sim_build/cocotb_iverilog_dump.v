module cocotb_iverilog_dump();
initial begin
    $dumpfile("/home/mat/Documents/classes/62050/project/fpga/sim_build/midi_processor.fst");
    $dumpvars(0, midi_processor);
end
endmodule
