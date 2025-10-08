import random
import cocotb
from cocotb.triggers import Timer
import os
from pathlib import Path
import sys
import matplotlib.pyplot as plt
import scipy.fftpack
import numpy as np
import math

from cocotb.clock import Clock
from cocotb.triggers import (
    Timer,
    ClockCycles,
    RisingEdge,
    FallingEdge,
    ReadOnly,
    ReadWrite,
    with_timeout,
    First,
    Join,
)
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner

from random import getrandbits


async def reset(rst, clk):
    """Helper function to issue a reset signal to our module"""
    rst.value = 1
    await ClockCycles(clk, 3)
    rst.value = 0
    await ClockCycles(clk, 2)


@cocotb.test()
async def test_delta_sigma(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    dut.current_sample.value = 0b0
    # use helper function to assert reset signal
    await reset(dut.rst, dut.clk)
    samples = []
    sample_rate = 44100
    dac_rate_ratio = 64
    N = 2048 * dac_rate_ratio
    freq = 8000
    angle = 0
    delta_angle = 2 * math.pi * freq / sample_rate
    sample_rate *= dac_rate_ratio

    await FallingEdge(dut.clk)
    for i in range(N // dac_rate_ratio):
        dut.current_sample.value = int(2**15 * math.sin(angle))
        for j in range(dac_rate_ratio):
            await FallingEdge(dut.clk)
            if dut.audio_out.value == 0:
                samples.append(-1.0)
            else:
                samples.append(1.0)
        angle += delta_angle
        if angle > 2 * math.pi:
            angle -= 2 * math.pi

    xf = np.linspace(0.0, 1.0 / (2.0 / sample_rate), N // 2)
    fft = scipy.fftpack.fft(samples)
    fig, ax = plt.subplots()
    ax.semilogy(xf, 2.0 / N * np.abs(fft[: N // 2]))
    ax.set_ybound(1 / 100000, 1)
    ax.set_xbound(0, 20000)
    plt.show()


def test_delta_sigma_runner():
    """Run the delta_sigma runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "dlt_sig_dac.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="dlt_sig_dac_1st_order",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="dlt_sig_dac_1st_order",
        test_module="test_delta_sigma",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_delta_sigma_runner()
