import random
import cocotb
from cocotb.triggers import Timer
import os
from pathlib import Path
import sys
import matplotlib.pyplot as plt
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


BIT_WIDTH = 13


@cocotb.test()
async def test_sqrt_approx(dut):
    """Your simulation test!
    TODO: Flesh this out with value sets and print statements. Maybe even some assertions, as a treat.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    dut.d_in.value = 0b0
    vals = []
    true_vals = []
    # use helper function to assert reset signal
    await reset(dut.rst, dut.clk)

    await FallingEdge(dut.clk)
    for i in range(2**BIT_WIDTH):
        dut.d_in.value = i
        await FallingEdge(dut.clk)
        vals.append(int(dut.d_out.value))
        true_vals.append(math.sqrt(i))

    fig, ax = plt.subplots()
    ax.plot(vals)
    ax.plot(true_vals)
    plt.show()


def test_sqrt_approx_runner():
    """Run the sqrt_approx runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "sqrt_approx.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {"WIDTH": BIT_WIDTH}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="sqrt_approx",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="sqrt_approx",
        test_module="test_sqrt_approx",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_sqrt_approx_runner()
