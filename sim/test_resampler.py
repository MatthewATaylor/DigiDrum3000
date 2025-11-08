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
#from vicoco.vivado_runner import get_runner
test_file = os.path.basename(__file__).replace(".py","")


SAMPLE_PERIOD_OUT = 2272/4
SAMPLE_MAX = 2**15-1
DELAY_SCALE = 4
M = 2**DELAY_SCALE


def get_farrow(x, d):
        left_sum = x[3] - (6*x[0] - (3*x[1] + 2*x[0]))
        top_sum_2 = int(d) * (3*(x[1]-x[2]) + (x[3]-x[0]))
        top_sum = int(d) * (M*3*(x[0]+x[2]) - M*6*x[1] + top_sum_2)
        return int(M**3 * 6*x[1] + int(d) * (-M**2 * left_sum + top_sum))


@cocotb.test()
async def test_static_d(dut):
    return
    SAMPLE_PERIOD_IN = SAMPLE_PERIOD_OUT
    SECONDS_PER_SAMPLE = SAMPLE_PERIOD_IN*10e-9
    SAMPLES_PER_CYCLE = 23
    F = 1 / (SAMPLES_PER_CYCLE * SECONDS_PER_SAMPLE)
    CYCLES = 2

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.sample_period.value = SAMPLE_PERIOD_IN
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    fig, ax = plt.subplots()
    x_buf = [0,0,0,0,0]
    d_buf = [0,0]

    d_range = range(0, M, int(M/4))
    for d in d_range:
        print(
            f'\n' + \
            f'############################################\n' + \
            f'Delay = {d}                                 \n' + \
            f'############################################\n'
        )

        n_in = []
        x = []
        n_out = []
        y = []

        dut.delay_debug.value = d
        dut.delay_debug_valid.value = 1

        for i in range(int(CYCLES*SAMPLES_PER_CYCLE*SAMPLE_PERIOD_IN)):
            d_buf = [d] + [d_buf[0]]

            sample_write = False
            if i % SAMPLE_PERIOD_IN == 0:
                n = i / SAMPLE_PERIOD_IN
                t = n * SECONDS_PER_SAMPLE
                sample = int(SAMPLE_MAX * math.sin(2 * math.pi * F * t))
                dut.sample_in.value = sample
                dut.sample_in_valid.value = 1

                x_buf = [sample] + x_buf[:-1]
                n_in.append(i)
                x.append(sample)

                sample_write = True
            else:
                dut.sample_in_valid.value = 0

            if dut.sample_out_valid.value == 1:
                sample = dut.sample_out.value.signed_integer

                n_out.append(i)
                y.append(sample)

            await ClockCycles(dut.clk, 1)

            farrow_valid = dut.farrow_out_valid.value
            if farrow_valid == 1:
                farrow_dut = dut.farrow_out.value.signed_integer
                farrow_expected = get_farrow(x_buf[1:], d_buf[-1])
                print(f'farrow_out: received={farrow_dut}, expected={farrow_expected}')
                assert farrow_dut == farrow_expected
        if d == d_range[0]:
            ax.scatter(n_in, x, color='black', label='Input')
        ax.plot(n_out, y, marker='.', label=f'Delay = {d/M}')

    ax.set_xlabel('Cycle Count')
    ax.set_ylabel('Sample')
    ax.legend()
    fig.suptitle('Variable Delay')
    fig.tight_layout()
    plt.show()


@cocotb.test()
async def test_sample_period_sweep(dut):
    return
    F = 1000

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.delay_debug_valid.value = 0
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    fig, ax = plt.subplots()

    n_in = []
    x = []
    n_out = []
    y = []

    sample_period_start = 2272*4
    sample_period_stop = 2272/4
    clock_cycles = 79123
    setup_cycles = int(clock_cycles/2)
    sample_period_step = (sample_period_stop-sample_period_start) / clock_cycles
    sample_period_float = sample_period_start
    last_sample_cycle = 0
    for i in range(2*clock_cycles+setup_cycles):
        sample_period_in = int(sample_period_float)
        dut.sample_period.value = sample_period_in
        seconds_per_sample = sample_period_in * 10.0e-9
        samples_per_cycle = 1/F / seconds_per_sample

        if i - last_sample_cycle >= sample_period_in:
            last_sample_cycle = i
            n = i / sample_period_in
            t = n * seconds_per_sample
            sample = int(SAMPLE_MAX * math.sin(2 * math.pi * F * t))
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

        if i >= setup_cycles:
            if i >= setup_cycles+clock_cycles:
                sample_period_float -= sample_period_step
            else:
                sample_period_float += sample_period_step

    ax.scatter(n_in, x, color='black', label='Input')
    ax.plot(n_out, y, marker='.', label='Output')

    ax.set_xlabel('Cycle Count')
    ax.set_ylabel('Sample')
    ax.legend()
    fig.suptitle(f'Input Sample Rate Sweep ({F} Hz Signal)')
    fig.tight_layout()
    plt.show()


@cocotb.test()
async def test_variable_d(dut):
    F = 1000
    CYCLES = 2

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.delay_debug_valid.value = 0
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    fig, ax = plt.subplots()

    # sample_periods = [2272*4, 2272*2.37, 2272, 2272/1.89, 2272/4]
    # sample_periods = [2272*4, 2272*2.37, 2272, 2272/1.89, 2272/4]
    sample_periods = [2272*3.14159]
    for sample_period_in in sample_periods:
        sample_rate_in = 1 / (sample_period_in * 10e-9)
        print(
            f'\n' + \
            f'############################################\n' + \
            f'Input Sample Rate = {int(sample_rate_in)} Hz\n' + \
            f'############################################\n'
        )

        sample_period_in = int(sample_period_in)
        dut.sample_period.value = sample_period_in
        seconds_per_sample = sample_period_in * 10e-9
        samples_per_cycle = 1/F / seconds_per_sample

        n_in = []
        x = []
        n_out = []
        y = []

        for i in range(int(CYCLES*samples_per_cycle*sample_period_in)):
            if i % sample_period_in == 0:
                n = i / sample_period_in
                t = n * seconds_per_sample
                sample = int(SAMPLE_MAX * math.sin(2 * math.pi * F * t))
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

        ax.plot(n_out, y, marker='.', label=f'{int(sample_rate_in)} sps')

    ax.set_xlabel('Cycle Count')
    ax.set_ylabel('Sample')
    ax.legend()
    fig.suptitle(f'Variable Input Sample Rate ({F} Hz Signal)')
    fig.tight_layout()
    plt.show()


@cocotb.test()
async def test_variable_f(dut):
    return
    SAMPLE_PERIOD_IN = int(2272/4)
    SECONDS_PER_SAMPLE = SAMPLE_PERIOD_IN * 10e-9

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.delay_debug_valid.value = 0
    dut.sample_period.value = SAMPLE_PERIOD_IN
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    f_powers = range(8)
    f_list = [800 * 2**f_power for f_power in f_powers]
    for f in f_list:
        fig, ax = plt.subplots()

        print(
            f'\n' + \
            f'############################################\n' + \
            f'Input Frequency = {f} Hz                    \n' + \
            f'############################################\n'
        )

        samples_per_cycle = 1/f / SECONDS_PER_SAMPLE

        n_in = []
        x = []
        n_out = []
        y = []

        #for i in range(int(CYCLES*SAMPLES_PER_CYCLE*SAMPLE_PERIOD_IN)):
        for i in range(int(400*SAMPLE_PERIOD_IN)):
            if i % SAMPLE_PERIOD_IN == 0:
                n = i / SAMPLE_PERIOD_IN
                t = n * SECONDS_PER_SAMPLE
                sample = int(SAMPLE_MAX * math.sin(2 * math.pi * f * t))
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
    sources = [proj_path / "hdl" / "resampler.sv"]
    sources += [proj_path / "hdl" / "divider.sv"]
    build_test_args = ["-Wall"]
    parameters = {'SAMPLE_PERIOD_OUT': SAMPLE_PERIOD_OUT}
    hdl_toplevel = "resampler"
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

