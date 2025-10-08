import random
import cocotb
from cocotb.triggers import Timer
import os
from pathlib import Path
import sys
import test_sin_gen_response

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


@cocotb.test()
async def test_sin_gen(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    dut.delta_angle.value = 0b0
    dut.get_next_sample.value = 0b0
    # use helper function to assert reset signal
    await reset(dut.rst, dut.clk)

    dut.delta_angle.value = 0x0FFFFFF
    for i in range(200):
        await FallingEdge(dut.clk)
        dut.get_next_sample.value = 0b1
        await FallingEdge(dut.clk)
        dut.get_next_sample.value = 0b0
        if int(dut.current_sample.value) > 0x7FFF:
            out_val = -0x8000 + (int(dut.current_sample.value) ^ 0x8000)
        else:
            out_val = int(dut.current_sample.value)
        print(out_val * 2**-15)
        await ClockCycles(dut.clk, 100)


def test_sin_gen_runner():
    """Run the sin_gen runner. Boilerplate code"""
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
        hdl_toplevel="sin_gen",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="sin_gen",
        test_module="test_sin_gen_response",
        test_args=run_test_args,
        waves=True,
    )
    runner.test(
        hdl_toplevel="sin_gen",
        test_module="test_sin_gen",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_sin_gen_runner()
