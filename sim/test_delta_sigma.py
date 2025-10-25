import random
import cocotb
from cocotb.triggers import Timer
import os
from pathlib import Path
import sys
import matplotlib.pyplot as plt
import matplotlib.mlab as pltlab
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

from scipy.signal import fir_filter_design


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

    level = "-1"
    while int(level) < 1 or int(level) > 5:
        print("\n---------- enter detail level (1-5) ----------")
        print(">", end="")
        level = input()

    vol = "-1"
    while int(vol) < 1 or int(vol) > 5:
        print("\n---------- enter volume (1-5) ----------")
        print(">", end="")
        vol = input()

    samples = []
    angle = 0
    sample_rate = 16 * 44100
    dac_rate_ratio = 100_000_000 // sample_rate
    N = 2 ** (6 + 2 * int(level)) * dac_rate_ratio
    frequency = 4000
    delta_angle = 2 * math.pi * frequency / sample_rate
    sample_rate *= dac_rate_ratio
    gain = 16 ** (int(vol) - 5)

    if int(level) > 4:
        print("\n\n\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        print("WARNING: THIS WILL TAKE A LOOOOONG TIME TO RUN")
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n")
    elif int(level) > 2:
        print("\n\n\nNOTICE: THIS WILL TAKE A WHILE TO RUN \n\n")

    await FallingEdge(dut.clk)
    for i in range(N // dac_rate_ratio):
        dut.current_sample.value = int(gain * 2**15 * math.sin(angle))
        for j in range(dac_rate_ratio):
            await FallingEdge(dut.clk)
            if dut.audio_out.value == 0:
                if len(samples) > 0 and samples[-1] > 0:
                    samples.append(-0.9)
                else:
                    samples.append(-1.0)
            else:
                samples.append(1.0)
        angle += delta_angle
        if angle > 2 * math.pi:
            angle -= 2 * math.pi

    # complete cycle of sin wave
    while abs(angle) > delta_angle / 2:
        print(f"[completing cycle] current angle: {angle}")
        N += dac_rate_ratio
        dut.current_sample.value = int(gain * 2**15 * math.sin(angle))
        for j in range(dac_rate_ratio):
            await FallingEdge(dut.clk)
            if dut.audio_out.value == 0:
                if samples[-1] > 0:
                    samples.append(-0.9)
                else:
                    samples.append(-1.0)
            else:
                samples.append(1.0)
        angle += delta_angle
        if angle > 2 * math.pi:
            angle -= 2 * math.pi
    print(f"end angle: {angle * 180 / math.pi} degrees")

    # scale so signal is at -0dB
    samples = [10 ** (14.5 / 20) * i for i in samples]
    dc = np.mean(samples)
    samples = [sample - dc for sample in samples]
    window = scipy.signal.windows.flattop(N, sym=False)
    filter = scipy.signal.butter(1, 28000, fs=sample_rate, output="sos")
    filtered = scipy.signal.sosfilt(filter, samples)

    fft = scipy.fftpack.fft(filtered * window)
    sample_mags = 2.0 / N * np.abs(fft[: N // 2])
    fft_freq = scipy.fftpack.fftfreq(len(samples))

    cutoff = 0
    cutoff_1M = 0
    # zero out fundemental
    for i in range(len(fft)):
        if (
            fft_freq[i] >= frequency / sample_rate
            and fft_freq[i - 1] < frequency / sample_rate
        ):
            print(f"freq: {fft_freq[i]}")
            fundemental_index = i
            if abs(fft_freq[i] - frequency / sample_rate) > abs(
                fft_freq[i - 1] - frequency / sample_rate
            ):
                fundemental_index = i - 1
            for j in range(-4, 5):
                sample_mags[fundemental_index + j] = 0

        if fft_freq[i] >= 20000 / sample_rate and fft_freq[i - 1] < 20000 / sample_rate:
            cutoff = i
        if (
            fft_freq[i] >= 1000000 / sample_rate
            and fft_freq[i - 1] < 1000000 / sample_rate
        ):
            cutoff_1M = i

    THDN = math.sqrt(np.sum(np.square(sample_mags)))
    THDN_audio = math.sqrt(np.sum(np.square(sample_mags[:cutoff])))
    THDN_100k = math.sqrt(np.sum(np.square(sample_mags[:cutoff_1M])))
    print(f"total THDN: {THDN}  ({20 * math.log10(THDN)}dB)")
    print(f"<1MHz THDN: {THDN_100k}  ({20 * math.log10(THDN_100k)}dB)")
    print(f"audio THDN: {THDN_audio}  ({20 * math.log10(THDN_audio)}dB)")

    fig, (ax1, ax2) = plt.subplots(2)
    ax1.magnitude_spectrum(samples, Fs=sample_rate, window=window, scale="dB")
    ax1.set_ybound(-140, 1)
    ax1.set_xbound(0, 20000)
    ax1.set_title("Audio Range")
    ax2.magnitude_spectrum(samples, Fs=sample_rate, window=window, scale="dB")
    ax2.magnitude_spectrum(filtered, Fs=sample_rate, window=window, scale="dB")
    ax2.legend(["direct dac output", "analog filtered"])
    ax2.set_xscale("log")
    ax2.set_ybound(-180, 1)
    ax2.set_xbound(100, sample_rate // 2)
    ax2.set_title("Full Range)")
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
    order = "-1"
    while int(order) < 1 or int(order) > 2:
        print("\n---------- enter DAC order (1-2) ----------")
        print(">", end="")
        order = input()

    if int(order) == 2:
        runner.build(
            sources=sources,
            hdl_toplevel="dlt_sig_dac_2nd_order",
            always=True,
            build_args=build_test_args,
            parameters=parameters,
            timescale=("1ns", "1ps"),
            waves=True,
        )
        run_test_args = []
        runner.test(
            hdl_toplevel="dlt_sig_dac_2nd_order",
            test_module="test_delta_sigma",
            test_args=run_test_args,
            waves=True,
        )
    else:
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
