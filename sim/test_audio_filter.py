import cocotb
import os
import sys
import math
import logging
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly,with_timeout
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner
import matplotlib.pyplot as plt
import wave
import numpy as np
#from vicoco.vivado_runner import get_runner
test_file = os.path.basename(__file__).replace(".py","")


SAMPLE_PERIOD = 2272
SAMPLE_MAX = 2**15-1


def square(theta):
    if math.sin(theta) > 0:
        return 1
    else:
        return -1


def filter_step_float(x, s, pot_cutoff, pot_quality):
    g = pot_cutoff / 1024
    k = pot_quality / 256

    S = g**3 * s[0] + g**2 * s[1] + g * s[2] + s[3]
    G = g**4
    u = (x - k*S) / (1 + k*G)

    if u > 2**15-1:
        u = 2**15-1
    elif u < -2**15:
        u = -2**15

    G = g / (1 + g)

    for j in range(4):
        v = G * (u - s[j])
        u = v + s[j]
        s[j] = u + v

    return u, s


def filter_step(x, s, pot_cutoff, pot_quality):
    x = np.int64(x)
    s = np.array(s, dtype=np.int64)
    g_x1024 = np.int64(pot_cutoff)
    k = np.int64(pot_quality)

    # S_x1024_4 could be left shifted by 10 here, but this results in overflow.
    # Instead shift left 2 and do not shift right by 8 below.
    # This reduces precision, but is needed for direct comparison w/ HDL.
    # This change seems to have minimal effect.
    S_x1024_4 = np.int64(
        s[0] * (g_x1024)**3 +  # 16 + 30 bits
        s[1] * (g_x1024)**2 +  # 26 + 20 bits
        s[2] * (g_x1024)    +  # 36 + 10 bits
        s[3]                   # 46      bits
    ) << 2
    G_x1024_4 = g_x1024**4

    # pot_quality / 256 = actual k
    kS = np.int64(k * S_x1024_4)
    kG = np.int64(k * G_x1024_4) >> 8

    u_dividend = np.int64((x<<40) - kS)
    u_dividend_abs = np.abs(u_dividend)

    u = u_dividend_abs // np.int64((1<<40) + kG)

    if (u_dividend < 0):
        u = -u
    if u > 2**15-1:
        u = 2**15-1
    elif u < -2**15:
        u = -2**15

    G_x1024 = (g_x1024<<10) // (1024 + g_x1024)

    for j in range(4):
        v = np.int64(G_x1024 * (u - s[j]))
        u = np.int64(v + np.int64(s[j]<<10))
        s[j] = np.int64(u + v) >> 10

    return int(u >> 40), s


@cocotb.test()
async def test_variable_f(dut):
    SECONDS_PER_SAMPLE = SAMPLE_PERIOD * 10e-9
    CYCLES = 2

    CUTOFF = 200
    Q = 1023

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst.value = 1
    dut.pot_cutoff.value = CUTOFF
    dut.pot_quality.value = Q
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    f_list = [1000]
    for f in f_list:
        fig, ax = plt.subplots()

        samples_per_cycle = 1/f / SECONDS_PER_SAMPLE

        n_in = []
        x = []
        n_out = []
        y = []
        y_expected = []
        y_expected_float = []

        next_y_expected = None
        next_y_expected_float = None
        s = [0,0,0,0]
        s_float = [0,0,0,0]

        last_cycle_in = None
        for i in range(int(CYCLES*samples_per_cycle*SAMPLE_PERIOD)):
            if i % SAMPLE_PERIOD == 0:
                n = i / SAMPLE_PERIOD
                t = n * SECONDS_PER_SAMPLE
                sample = int(SAMPLE_MAX * square(2 * math.pi * f * t))
                dut.sample_in.value = sample
                dut.sample_in_valid.value = 1

                n_in.append(i)
                x.append(sample)

                next_y_expected, s = \
                    filter_step(sample, s, CUTOFF, Q)
                next_y_expected_float, s_float = \
                    filter_step_float(sample, s_float, CUTOFF, Q)

                last_cycle_in = i
            else:
                dut.sample_in_valid.value = 0

            if dut.sample_out_valid.value == 1:
                sample = dut.sample_out.value.signed_integer

                n_out.append(i)
                y.append(sample)
                y_expected.append(next_y_expected)
                y_expected_float.append(next_y_expected_float)

                print(f'Recieved: {sample}, Expected: {next_y_expected}, Float: {next_y_expected_float}, Latency: {i-last_cycle_in}')
                assert sample == next_y_expected

            await ClockCycles(dut.clk, 1)

        ax.scatter(n_in, x, color='black', label='Input')
        ax.plot(n_out, y, marker='.', label='Output (HDL)')
        ax.plot(n_out, y_expected, marker='.', label='Output (Python, Fixed Point)')
        ax.plot(n_out, y_expected_float, marker='.', label='Output (Python, Floating Point)')

        ax.set_xlabel('Cycle Count')
        ax.set_ylabel('Sample')
        ax.legend()
        fig.suptitle(f'Input Frequency = {f} Hz')
        fig.tight_layout()
        plt.show()


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "audio_filter.sv"]
    sources += [proj_path / "hdl" / "divider.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "audio_filter"
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

