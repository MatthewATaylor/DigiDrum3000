
`timescale 1ns / 1ps
module cocotb_vivado_dump();
  initial begin
    $dumpfile("/home/fpga/worker_place/temp/temp/37cd26e1e63342eca0911942ed72b2c7/sim_build/sample_mixer.fst");
    $dumpvars(0,sample_mixer);
  end
endmodule
