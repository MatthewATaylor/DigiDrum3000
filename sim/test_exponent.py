import random
import sys
import cocotb
import subprocess
from cocotb.triggers import Timer
import os
from pathlib import Path
import sys
from PIL import Image, ImageFilter
import math
from vicoco.vivado_runner import get_runner

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

from random import getrandbits


async def reset(rst, clk):
    """Helper function to issue a reset signal to our module"""
    rst.value = 1
    await ClockCycles(clk, 3)
    rst.value = 0
    await ClockCycles(clk, 2)


@cocotb.test()
async def test_exponent(dut):
    """Your simulation test!
    TODO: Flesh this out with value sets and print statements. Maybe even some assertions, as a treat.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    dut.in_valid.value = 0
    dut.in_value.value = 0
    # use helper function to assert reset signal

    await reset(dut.rst, dut.clk)
    true_vals = []
    output = []

    for j in range(0, 4096, 16):
        dut.in_value.value = j
        await FallingEdge(dut.clk)
        dut.in_valid.value = True
        await FallingEdge(dut.clk)
        dut.in_valid.value = False
        while not bool(dut.out_valid.value):
            await FallingEdge(dut.clk)
        output.append(int(dut.out_value.value))
        true_vals.append(int(2**8 * math.exp(-j * 2**-8)))

    for val, true_val in zip(output, true_vals):
        print(f"calculated: {val}, true: {true_val}")


def test_exponent_runner():
    """Run the star_noise runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "ip" / "cordic_sinhcosh_folded" / "cordic_sinhcosh_folded.xci",
        proj_path / "hdl" / "cordic_sinhcosh_folded_wrapper.sv",
        proj_path / "hdl" / "divider.sv",
        proj_path / "hdl" / "exponent.sv",
    ]
    build_test_args = ["-Wall"]
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="exponent",
        always=True,
        build_args=build_test_args,
        parameters={},
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="exponent",
        test_module="test_exponent",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_exponent_runner()
