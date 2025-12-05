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


def tanh_approx_float(x):
    n = x*2**30 + x*2**31 + x**3
    d = 2**30 + x**2 + 2*x**2
    return n/d


def tanh_approx(x):
    x = np.int64(x)
    n = (x<<30) + (x<<31) + x**3
    d = (1<<30) + x**2 + ((x**2)<<1)
    n_sign = n < 0
    out = abs(n)//d
    if n_sign:
        out = -out
    return out


@cocotb.test()
async def test_a(dut):
    samples = np.linspace(-2**15, 2**15-1, 100)

    fig, ax = plt.subplots()
    y = []
    y_tanh = []
    y_expected = []

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    for sample in samples:
        sample = int(sample)

        dut.din_valid.value = 1
        dut.din.value = int(sample)

        await ClockCycles(dut.clk, 1)
        while dut.dout_valid == 0:
            dut.din_valid.value = 0
            await ClockCycles(dut.clk, 1)

        dout = dut.dout.value.signed_integer
        y.append(dout)

        dout_tanh = 2**15 * math.tanh(3 * sample / 2**15)
        y_tanh.append(dout_tanh)

        dout_expected = tanh_approx(sample)
        y_expected.append(dout_expected)

        print(f'Received: {dout}, Expected: {dout_expected}')
        assert dout == dout_expected

    ax.plot(samples, y_expected, label='Expected')
    ax.plot(samples, y, label='Actual')
    ax.plot(samples, y_tanh, color='black', linestyle='dashed', label='tanh')

    ax.set_xlabel('Input')
    ax.set_ylabel('Output')
    ax.legend()
    fig.tight_layout()
    plt.show()


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "tanh_approx.sv"]
    sources += [proj_path / "hdl" / "divider.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "tanh_approx"
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

