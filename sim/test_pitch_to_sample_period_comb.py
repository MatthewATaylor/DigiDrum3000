import cocotb
import os
import sys
from math import log
import logging
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly, with_timeout, NextTimeStep
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner
#from vicoco.vivado_runner import get_runner
import matplotlib.pyplot as plt
import numpy as np
test_file = os.path.basename(__file__).replace(".py","")


def pitch_to_sample_period(pitch):
    pitch_lerp_1 = (pitch % 256) * 4544
    pitch_lerp_2 = abs(((pitch + 128) % 256) - 128) * 826
    pitch_lerp_3 = abs(((pitch + 64) % 128) - 64) * 367
    sample_period_numerator = \
            9088 - \
            int((pitch_lerp_1 + pitch_lerp_2 + pitch_lerp_3) / 256)
    return int(sample_period_numerator >> int(pitch >> 8))


def pitch_to_sample_period_fp(pitch):
    return 9088 / 2**(pitch/256)


def delta_cents(sample_periods):
    fs = 1 / (sample_periods * 10e-9)
    return np.log2(fs[1:]/fs[:-1])*1200


@cocotb.test()
async def test_a(dut):
    sample_period_outs = []
    sample_period_fps = []
    pitch_values = range(1024)
    for pitch in pitch_values:
        sample_period = pitch_to_sample_period(pitch)
        dut.pitch.value = pitch
        await Timer(1, units="ns")
        sample_period_out = dut.sample_period.value.integer
        sample_period_outs.append(sample_period_out)
        sample_period_fps.append(pitch_to_sample_period_fp(pitch))
        print(f'pitch={pitch}, expect sample_period={sample_period}, got: {sample_period_out}')
        assert sample_period_out == sample_period

    fig, ax = plt.subplots(nrows=1, ncols=2, figsize=(8,4))
    sample_period_fps = np.array(sample_period_fps)
    sample_period_outs = np.array(sample_period_outs)
    fs_fps = 1 / (sample_period_fps*10e-9) / 1000
    fs_outs = 1 / (sample_period_outs*10e-9) / 1000
    ax0a = ax[0].plot(pitch_values, fs_fps, label='Ideal Output')
    ax0b = ax[0].plot(pitch_values, fs_outs, label='Actual Output')
    ax[0].set_ylabel('Sample Rate [kHz]')
    ax[0].set_xlabel('Pitch (10-bit ADC output)')
    ax0_twin = ax[0].twinx()
    ax1a = ax0_twin.plot(
        pitch_values,
        fs_outs-fs_fps,
        color='black', label='Error'
    )
    ax0_twin.set_ylabel('Error [kHz]')
    axs = ax0a+ax0b+ax1a
    labels = [axi.get_label() for axi in axs]
    ax[0].legend(axs, labels)
    ax[1].plot(pitch_values[:-1], delta_cents(sample_period_outs), color='black')
    ax[1].set_ylabel('Sample Rate Step Size [cents]')
    ax[1].set_xlabel('Pitch (10-bit ADC output)')
    fig.tight_layout()
    plt.show()


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "pitch_to_sample_period.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "pitch_to_sample_period"
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

