import random
import cocotb
from cocotb.triggers import Timer
import os
from pathlib import Path
import sys
import random

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


def reverse_bits(n, size):
    reversed_n = 0
    for i in range(size):
        reversed_n = (reversed_n << 1) | (n & 1)
        n >>= 1
    return reversed_n


async def inout_driver(dut, patch_state):
    """
    patch_state in form: {out_port: [downstream_port1, downstream_port2,...]}
    """
    while True:
        await FallingEdge(dut.clk)

        dut.crush.value = 1
        dut.distortion.value = 1
        dut.filter.value = 1
        dut.delay.value = 1
        dut.reverb.value = 1

        if dut.dry.value == 0:
            active_out = "dry"
        elif dut.crush_val.value == 0:
            active_out = "crush"
        elif dut.distortion_val.value == 0:
            active_out = "distortion"
        elif dut.filter_val.value == 0:
            active_out = "filter"
        elif dut.delay_val.value == 0:
            active_out = "delay"
        elif dut.reverb_val.value == 0:
            active_out = "reverb"
        else:
            continue

        getattr(dut, active_out).value = 0
        downstream = patch_state[active_out]
        if len(downstream):
            getattr(dut, downstream[0]).value = 0
            for patch in downstream[1:]:
                getattr(dut, patch).value = random.randint(0, 1)


async def test_patch_state(dut, patch_state):
    await reset(dut.rst, dut.clk)

    src_tags = {
        "dry": 0,
        "delay": 1,
        "reverb": 2,
        "filter": 3,
        "distortion": 4,
        "crush": 5,
    }

    target_values = {
        "output": 0,
        "crush": 7,
        "distortion": 7,
        "filter": 7,
        "delay": 7,
        "reverb": 7,
    }

    if len(patch_state["dry"]):
        target_values["output"] = src_tags[patch_state["dry"][-1]]
    for i in range(len(patch_state["dry"])):
        if i == 0:
            target_values[patch_state["dry"][0]] = src_tags["dry"]
        else:
            target_values[patch_state["dry"][i]] = src_tags[patch_state["dry"][i - 1]]

    await ClockCycles(dut.clk, 1300)
    await FallingEdge(dut.clk)
    assert dut.output_src.value == target_values["output"]
    assert dut.crush_src.value == target_values["crush"]
    assert dut.distortion_src.value == target_values["distortion"]
    assert dut.filter_src == target_values["filter"]
    assert dut.delay_src == target_values["delay"]
    assert dut.reverb_src == target_values["reverb"]


@cocotb.test()
async def test_patch_reconstructor(dut):
    """Your simulation test!
    TODO: Flesh this out with value sets and print statements. Maybe even some assertions, as a treat.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    patch_state = {
        "crush": ["reverb"],
        "distortion": ["delay", "filter"],
        "filter": [],
        "reverb": [],
        "delay": ["filter"],
        "dry": ["distortion", "delay", "filter"],
    }
    cocotb.start_soon(inout_driver(dut, patch_state))

    await test_patch_state(dut, patch_state)

    patch_state["crush"] = []
    patch_state["distortion"] = ["delay", "filter", "reverb", "crush"]
    patch_state["filter"] = ["reverb", "crush"]
    patch_state["reverb"] = ["crush"]
    patch_state["delay"] = ["filter", "reverb", "crush"]
    patch_state["dry"] = ["distortion", "delay", "filter", "reverb", "crush"]
    await test_patch_state(dut, patch_state)

    patch_state["crush"] = []
    patch_state["distortion"] = []
    patch_state["filter"] = []
    patch_state["reverb"] = []
    patch_state["delay"] = []
    patch_state["dry"] = []
    await test_patch_state(dut, patch_state)


def test_patch_reconstructor_runner():
    """Run the patch_reconstructor runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "patch_reconstructor.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="patch_reconstructor",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="patch_reconstructor",
        test_module="test_patch_reconstructor",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_patch_reconstructor_runner()
