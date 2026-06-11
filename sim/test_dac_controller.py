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
    cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())

    for i in range(2):
        dut.rst.value = 1
        dut.sample_in_l.value = 0
        dut.sample_in_r.value = 0
        dut.sample_in_valid.value = 0
        await ClockCycles(dut.clk, 2)
        dut.rst.value = 0

        for n in range(20000):
            await ClockCycles(dut.clk, 1)
            if n % 2500 == 0:
                t = n / 120.0e6
                dut.sample_in_l.value = n//2500 #int(10e3 * np.sin(2*np.pi*5e3*t))
                dut.sample_in_r.value = n//2500+4 #int(10e3 * np.cos(2*np.pi*5e3*t))
                dut.sample_in_valid.value = 1
            else:
                dut.sample_in_valid.value = 0

        await ClockCycles(dut.clk, 1)


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "dac_controller.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "dac_controller"
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

