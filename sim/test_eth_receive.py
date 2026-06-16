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


def bytes_to_bits(bytes_list):
    bits = []
    for byte in bytes_list:
        for i in range(8):
            bits.append((byte >> i) & 1)
    return bits


@cocotb.test()
async def test_a(dut):
    cocotb.start_soon(Clock(dut.eth_clk, 20, units="ns").start())
    dut.eth_rst_n.value = 0
    await ClockCycles(dut.eth_clk, 2)
    dut.eth_rst_n.value = 1
    dut.eth_crsdv.value = 0
    dut.eth_rxd.value = 0

    preamble = [1,0,1,0,1,0,1,0]*7 + [1,0,1,0,1,0,1,1]
    mac_dst = bytes_to_bits([0x02, 0xDE, 0xAD, 0xBE, 0xEF, 0x67])
    mac_src = [0]*6*8
    size = bytes_to_bits([0x88, 0xB5])
    pad = [0]*44*8
    payload = bytes_to_bits([0x12, 0x34])
    frame = preamble + mac_dst + mac_src + size + pad + payload

    await ClockCycles(dut.eth_clk, 8)

    for n in range(len(frame)//2):
        dut.eth_crsdv.value = 1
        dut.eth_rxd.value = frame[2*n] + 2*frame[2*n+1]
        await ClockCycles(dut.eth_clk, 1)

    dut.eth_crsdv.value = 0
    await ClockCycles(dut.eth_clk, 100)


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "eth_receive.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "eth_receive"
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

