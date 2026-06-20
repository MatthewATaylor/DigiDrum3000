import cocotb
import os
import sys
import math
import logging
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly,with_timeout
from cocotb.utils import get_sim_time as gst
from cocotb_tools.runner import get_runner
from cocotb.types import LogicArray
import matplotlib.pyplot as plt
import wave
import numpy as np
#from vicoco.vivado_runner import get_runner
test_file = os.path.basename(__file__).replace(".py","")


#@cocotb.test()
#async def test_a(dut):
#    cocotb.start_soon(Clock(dut.eth_clk, 20, units="ns").start())
#    dut.eth_rst_n.value = 0
#    await ClockCycles(dut.eth_clk, 2)
#    dut.eth_rst_n.value = 1
#
#    bits = ''
#    tx_bit_count = 0
#
#    for trial in range(3):
#        for i in range(422):
#            await ClockCycles(dut.eth_clk, 1)
#            if dut.eth_txen.value:
#                if tx_bit_count >= 64:
#                    # Skip preamble since that isn't used for CRC
#                    bits += str(int(dut.eth_txd.value[0])) + str(int(dut.eth_txd.value[1]))
#                tx_bit_count += 2
#
#        data = bits[:len(bits)-32]
#        data_bytes = []
#        for byte_index in range(len(data)//8):
#            byte = data[byte_index*8:byte_index*8+8]
#            byte = byte[::-1]
#            #if byte_index < 4:
#            #    byte_complement = ''
#            #    for bit in byte:
#            #        if bit == '1':
#            #            byte_complement += '0'
#            #        else:
#            #            byte_complement += '1'
#            #    byte = byte_complement
#            byte_int = int(byte, 2)
#            data_bytes.append(byte_int)
#        print(bytearray(data_bytes).hex())
#
#        fcs = bits[len(bits)-32:]
#        print(fcs)
#        #fcs = fcs[::-1]
#        fcs_bytes = []
#        for byte_index in range(len(fcs)//8):
#            byte = fcs[byte_index*8:byte_index*8+8]
#            fcs_bytes.append(int(byte, 2))
#        print(bytearray(fcs_bytes).hex())


@cocotb.test()
async def test_b(dut):
    cocotb.start_soon(Clock(dut.eth_clk, 20, units="ns").start())
    dut.eth_rst_n.value = 0
    dut.sample_valid_debug.value = 0
    dut.sample_resampled.value = 0
    await ClockCycles(dut.eth_clk, 2)
    dut.eth_rst_n.value = 1
    for i in range(4000):
        await ClockCycles(dut.eth_clk, 1)
        dut.sample_valid_debug.value = 1
        dut.sample_resampled.value = LogicArray("00000000"*26 + "10110011"*2 + "00011100"*2 + "11111111"*2)
        await ClockCycles(dut.eth_clk, 1)
        dut.sample_valid_debug.value = 0
        await ClockCycles(dut.eth_clk, 30)


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "audio_eth_transmit_debug.sv"]
    sources += [proj_path / "hdl" / "eth_transmit.sv"]
    sources += [proj_path / "hdl" / "crc32.sv"]
    sources += [proj_path / "hdl" / "xilinx_single_port_ram_read_first.v"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "audio_eth_transmit_debug"
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=hdl_toplevel,
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel=hdl_toplevel,
        test_module=test_file,
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    is_runner()

