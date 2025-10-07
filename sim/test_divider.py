import random
import cocotb
from cocotb.triggers import Timer
import os
from pathlib import Path
import sys

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


async def test_divide(dut, dividend, divisor):
    await FallingEdge(dut.clk)

    dut.dividend.value = dividend
    dut.divisor.value = divisor
    dut.data_in_valid.value = 0b1
    await FallingEdge(dut.clk)
    dut.data_in_valid.value = 0b0

    await RisingEdge(dut.data_out_valid)
    await FallingEdge(dut.clk)
    assert dividend // divisor == dut.quotient.value
    assert dividend % divisor == dut.remainder.value


@cocotb.test()
async def test_divider(dut):
    """Your simulation test!
    TODO: Flesh this out with value sets and print statements. Maybe even some assertions, as a treat.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    dut.dividend.value = 0b101010
    dut.divisor.value = 0b0
    dut.data_in_valid.value = 0b0
    # use helper function to assert reset signal
    await reset(dut.rst, dut.clk)

    for i in range(100):
        dividend = random.randint(0, 2**32 - 1)
        divisor = int((random.randrange(0, 2**64 - 1) / 2**60) ** 8)
        await test_divide(dut, dividend, divisor)


def test_divider_runner():
    """Run the divider runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "divider.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="divider",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="divider",
        test_module="test_divider",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_divider_runner()
