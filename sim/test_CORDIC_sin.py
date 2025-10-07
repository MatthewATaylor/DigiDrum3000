import random
import cocotb
from cocotb.triggers import Timer
import os
from pathlib import Path
import sys
import numpy as np
import math
from CORDIC_design import cordic_sin

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


async def test_angle(dut, angle):
    await FallingEdge(dut.clk)
    dut.angle_in.value = angle
    dut.input_valid.value = 0b1
    await FallingEdge(dut.clk)
    dut.input_valid.value = 0b0
    await RisingEdge(dut.out_valid)
    await FallingEdge(dut.clk)

    if int(dut.out.value) > 0x7FFF:
        out_val = -0x8000 + (int(dut.out.value) ^ 0x8000)
    else:
        out_val = int(dut.out.value)
    module_out = float(out_val) * 2**-15
    python_design_out = float(cordic_sin(np.int32(angle))) * 2**-15
    assert module_out == python_design_out, (
        f"incorrect module output: {int(dut.out.value):X}\nshould have been: {cordic_sin(np.int32(angle)):X}"
    )


@cocotb.test()
async def test_CORDIC_sin(dut):
    """Your simulation test!
    TODO: Flesh this out with value sets and print statements. Maybe even some assertions, as a treat.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    dut.angle_in.value = 0b101010
    dut.input_valid.value = 0b0
    # use helper function to assert reset signal
    await reset(dut.rst, dut.clk)

    await test_angle(dut, 0x3AAAAAAA)

    for x in range(-90, 91, 1):
        angle = int(math.radians(x) * 2**30)
        await test_angle(dut, angle)


def test_CORDIC_sin_runner():
    """Run the CORDIC_sin runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "sig_gen.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="CORDIC_sin",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="CORDIC_sin",
        test_module="test_CORDIC_sin",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_CORDIC_sin_runner()
