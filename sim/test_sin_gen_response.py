import cocotb
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


async def reset(rst, clk):
    """Helper function to issue a reset signal to our module"""
    rst.value = 1
    await ClockCycles(clk, 3)
    rst.value = 0
    await ClockCycles(clk, 2)


@cocotb.test()
async def test_sin_gen_response(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    dut.delta_angle.value = 0b0
    dut.get_next_sample.value = 0b0
    # use helper function to assert reset signal
    await reset(dut.rst, dut.clk)
    samples = []
    N = 4096 * 4
    sample_rate = 44100
    freq = 7909
    dut.delta_angle.value = int(2**29 * 2 * math.pi * freq / sample_rate)

    for i in range(N):
        await FallingEdge(dut.clk)
        dut.get_next_sample.value = 0b1
        await FallingEdge(dut.clk)
        dut.get_next_sample.value = 0b0
        if int(dut.current_sample.value) > 0x7FFF:
            out_val = -0x8000 + (int(dut.current_sample.value) ^ 0x8000)
        else:
            out_val = int(dut.current_sample.value)
        samples.append(out_val * 2**-15)
        await ClockCycles(dut.clk, 25)

    xf = np.linspace(0.0, 1.0 / (2.0 / sample_rate), N // 2)
    fft = scipy.fftpack.fft(samples)
    fig, ax = plt.subplots()
    ax.semilogy(xf, 2.0 / N * np.abs(fft[: N // 2]))
    ax.set_ybound(1 / 100000, 1)
    plt.show()
