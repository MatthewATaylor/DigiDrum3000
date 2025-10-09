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
async def test_sin_and_dac(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    dut.delta_angle.value = 0b0
    dut.get_next_sample.value = 0b0
    # use helper function to assert reset signal
    await reset(dut.rst, dut.clk)
    samples = []
    sample_rate = 8 * 44100
    dac_rate_ratio = 100_000_000 // sample_rate
    N = 2**12 * dac_rate_ratio
    frequency = 8000
    delta_angle = 2 * math.pi * frequency / sample_rate
    sample_rate *= dac_rate_ratio

    print("\n\n\n NOTICE: THIS WILL TAKE A WHILE TO RUN \n\n")

    dut.delta_angle.value = int(delta_angle * 2**29)
    for i in range(2):
        await FallingEdge(dut.clk)
        dut.get_next_sample.value = 0b1
        await FallingEdge(dut.clk)
        dut.get_next_sample.value = 0b0
        await ClockCycles(dut.clk, 30)

    await FallingEdge(dut.clk)
    for i in range(N // dac_rate_ratio):
        dut.get_next_sample.value = 0b1
        await FallingEdge(dut.clk)
        dut.get_next_sample.value = 0b0
        if dut.audio_out.value == 0:
            samples.append(-1.0)
        else:
            samples.append(1.0)
        for j in range(dac_rate_ratio - 1):
            await FallingEdge(dut.clk)
            if dut.audio_out.value == 0:
                samples.append(-1.0)
            else:
                samples.append(1.0)

    # xf = np.linspace(0.0, 1.0 / (2.0 / sample_rate), N // 2)
    window = scipy.signal.windows.flattop(N, sym=False)
    # samples = np.multiply(samples, window)
    # fft = scipy.fftpack.fft(samples)
    fig, (ax1, ax2) = plt.subplots(2)
    # ax1.semilogy(xf, 2.0 / N * np.abs(fft[: N // 2]))
    ax1.magnitude_spectrum(samples, Fs=sample_rate, window=window, scale="dB")
    ax1.set_ybound(-120, 1)
    ax1.set_xbound(0, 20000)
    # ax2.loglog(xf, 2.0 / N * np.abs(fft[: N // 2]))
    ax2.magnitude_spectrum(samples, Fs=sample_rate, window=window, scale="dB")
    ax2.set_xscale("log")
    ax2.set_ybound(-120, 1)
    ax2.set_xbound(20, sample_rate // 2)
    plt.show()


def test_sin_and_dac_runner():
    """Run the sin_and_dac runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "dlt_sig_dac.sv",
        proj_path / "hdl" / "sin_and_dac.sv",
        proj_path / "hdl" / "sig_gen.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="sin_and_dac",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="sin_and_dac",
        test_module="test_sin_and_dac",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_sin_and_dac_runner()
