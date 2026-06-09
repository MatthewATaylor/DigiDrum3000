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
import matplotlib.pyplot as plt
import wave
import numpy as np
#from vicoco.vivado_runner import get_runner
test_file = os.path.basename(__file__).replace(".py","")


@cocotb.test()
async def test_a(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())
    dut.rst.value = 1
    dut.din_valid.value = 0
    dut.din.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    din32_str = '11011110101011011011111011101111'
    din32 = [int(bit) for bit in din32_str]
    print(din32)

    for i in range(16):
        bit0 = din32[i*2]
        bit1 = din32[i*2+1]

        dut.din.value = 2*bit1 + bit0
        dut.din_valid.value = 1

        await ClockCycles(dut.clk, 1)
        print(dut.dout.value)
        print(f'{int(dut.dout.value):x}')


    #for i in range(32):
    #    dut.din.value = din32[i]
    #    dut.din_valid.value = 1

    #    await ClockCycles(dut.clk, 1)
    #    print(dut.dout.value)
    #    print(f'{int(dut.dout.value):x}')


    dut.din_valid.value = 0

    await ClockCycles(dut.clk, 1)
    print(dut.dout.value)
    print(f'{int(dut.dout.value):x}')

    assert int(dut.dout.value) == 0x81da1a18

    #bits = ''
    #tx_bit_count = 0

    #for i in range(425):
    #    await ClockCycles(dut.eth_clk, 1)
    #    if dut.eth_txen.value:
    #        if tx_bit_count >= 64:
    #            # Skip preamble since that isn't used for CRC
    #            bits += str(int(dut.eth_txd.value[0])) + str(int(dut.eth_txd.value[1]))
    #        tx_bit_count += 2

    #data = bits[:len(bits)-32]
    #data_bytes = []
    #for byte_index in range(len(data)//8):
    #    byte = data[byte_index*8:byte_index*8+8]
    #    #byte = byte[::-1]
    #    if byte_index < 4:
    #        byte_complement = ''
    #        for bit in byte:
    #            if bit == '1':
    #                byte_complement += '0'
    #            else:
    #                byte_complement += '1'
    #        byte = byte_complement
    #    byte_int = int(byte, 2)
    #    data_bytes.append(byte_int)
    #print(bytearray(data_bytes).hex())

    #fcs = bits[len(bits)-32:]
    #fcs_bytes = []
    #for byte_index in range(len(fcs)//8):
    #    byte = fcs[byte_index*8:byte_index*8+8]
    #    fcs_bytes.append(int(byte, 2))
    #print(bytearray(fcs_bytes).hex())


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "crc32.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "crc32"
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

