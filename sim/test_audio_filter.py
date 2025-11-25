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


@cocotb.test()
async def test_variable_f(dut):
    SECONDS_PER_SAMPLE = SAMPLE_PERIOD * 10e-9
    CYCLES = 4

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst.value = 1
    dut.pot_cutoff.value = 400
    dut.pot_quality.value = 1023
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

        for i in range(int(CYCLES*samples_per_cycle*SAMPLE_PERIOD)):
            if i % SAMPLE_PERIOD == 0:
                n = i / SAMPLE_PERIOD
                t = n * SECONDS_PER_SAMPLE
                sample = int(SAMPLE_MAX * square(2 * math.pi * f * t))
                dut.sample_in.value = sample
                dut.sample_in_valid.value = 1

                n_in.append(i)
                x.append(sample)
            else:
                dut.sample_in_valid.value = 0

            if dut.sample_out_valid.value == 1:
                sample = dut.sample_out.value.signed_integer

                n_out.append(i)
                y.append(sample)

                print(f'Received sample: {sample}, cycle={i}')

            await ClockCycles(dut.clk, 1)

        ax.scatter(n_in, x, color='black', label='Input')
        ax.plot(n_out, y, marker='.', label='Output')

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

