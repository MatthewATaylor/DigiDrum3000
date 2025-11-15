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


SAMPLE_PERIOD_OUT = 2272/4
SAMPLE_MAX = 2**15*0.2
DELAY_SCALE = 4
M = 2**DELAY_SCALE


def square(theta):
    if math.sin(theta) > 0:
        return 1
    else:
        return -1


@cocotb.test()
async def test_sample_period_sweep_dynamic_f(dut):
    return
    F = 220

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    pitch_start = 0
    pitch_stop = 1024
    clock_cycles = 79123*8
    setup_cycles = int(clock_cycles/2)
    pitch_step = (pitch_stop-pitch_start) / clock_cycles
    pitch_float = pitch_start
    last_sample_cycle = 0
    last_sample_print = 0
    for i in range(2*clock_cycles+setup_cycles):
        sample_period_in = int(9088 / 2**(pitch_float/256))
        f = F * 2272 / sample_period_in
        dut.sample_period.value = sample_period_in
        seconds_per_sample = sample_period_in * 10.0e-9

        if i - last_sample_cycle >= sample_period_in:
            last_sample_cycle = i
            n = i / sample_period_in
            t = n * seconds_per_sample
            sample = int(SAMPLE_MAX * square(2 * math.pi * f * t))
            dut.sample_in.value = sample
            dut.sample_in_valid.value = 1
        else:
            dut.sample_in_valid.value = 0

        if i - last_sample_print > 2272:
            sample = dut.sample_out.value.signed_integer
            print(f'Sample value: {sample}')

        await ClockCycles(dut.clk, 1)

        if i >= setup_cycles:
            if i >= setup_cycles+clock_cycles:
                pitch_float -= pitch_step
            else:
                pitch_float += pitch_step


@cocotb.test()
async def test_sample_period_sweep_wav(dut):
    samples = None
    with wave.open('../media/resampled/sq.wav', mode='rb') as wav:
        nframes = wav.getnframes()
        frames = wav.readframes(nframes)
        samples = np.frombuffer(frames, dtype='<h')

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    pitch_start = 0
    pitch_stop = 1024
    clock_cycles = 79123*32
    pitch_step = (pitch_stop-pitch_start) / clock_cycles
    pitch_float = pitch_start
    last_sample_cycle = 0
    sample_index = 0
    last_print_cycle = 0
    for i in range(clock_cycles):
        sample_period_in = int(9088 / 2**(pitch_float/256))
        dut.pitch.value = int(pitch_float)

        if i - last_sample_cycle >= sample_period_in:
            last_sample_cycle = i
            if sample_index >= 10:
                sample = int(samples[sample_index-10])
            else:
                sample = 0
            dut.sample_in.value = sample
            dut.sample_in_valid.value = 1
            sample_index += 1
        else:
            dut.sample_in_valid.value = 0

        if i - last_print_cycle >= 2272:
            last_print_cycle = i
            sample = dut.sample_out.value.signed_integer
            print(f'Sample value: {sample}')

        await ClockCycles(dut.clk, 1)

        pitch_float += pitch_step


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "farrow_upsampler.sv"]
    sources += [proj_path / "hdl" / "upsampler.sv"]
    sources += [proj_path / "hdl" / "resampler.sv"]
    sources += [proj_path / "hdl" / "resampler_and_upsampler.sv"]
    sources += [proj_path / "hdl" / "downsampler.sv"]
    sources += [proj_path / "hdl" / "dist_ram.sv"]
    sources += [proj_path / "hdl" / "xilinx_single_port_ram_read_first.v"]
    sources += [proj_path / "hdl" / "divider.sv"]
    sources += [proj_path / "hdl" / "pitch_to_sample_period.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "resampler_and_upsampler"
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

