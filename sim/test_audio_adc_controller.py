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
        dut.adc_cipo.value = 0
        await ClockCycles(dut.clk, 2)
        dut.rst.value = 0

        adc_data = [1,0,1,1]*32
        adc_data_counter = 0
        bclk_prev = 0
        for n in range(40000):
            await ClockCycles(dut.clk, 1)
            if dut.adc_bclk.value == 1 and bclk_prev == 0:
                dut.adc_cipo.value = adc_data[adc_data_counter]
                if adc_data_counter == 127:
                    adc_data_counter = 0
                else:
                    adc_data_counter += 1
            bclk_prev = dut.adc_bclk.value


        await ClockCycles(dut.clk, 1)


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "audio_adc_controller.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "audio_adc_controller"
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

