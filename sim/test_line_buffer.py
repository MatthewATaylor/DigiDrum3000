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


def reverse_bits(n, size):
    reversed_n = 0
    for i in range(size):
        reversed_n = (reversed_n << 1) | (n & 1)
        n >>= 1
    return reversed_n


def always_true(h, v):
    return True


async def test_line(
    dut,
    v_count,
    data_in,
    check_val=(always_true, always_true, always_true),
):
    check_val0, check_val1, check_val2 = check_val
    await FallingEdge(dut.clk)
    dut.h_count_in.value = 0
    dut.v_count_in.value = v_count
    dut.pixel_data_in.value = data_in(0)
    await FallingEdge(dut.clk)
    dut.h_count_in.value = 1
    dut.pixel_data_in.value = data_in(1)

    for h_count in range(2, 1280):
        await FallingEdge(dut.clk)
        assert check_val0(h_count - 2, dut.line_buffer_out.value & 0xFFFF)
        assert check_val1(h_count - 2, (dut.line_buffer_out.value >> 16) & 0xFFFF)
        assert check_val2(h_count - 2, (dut.line_buffer_out.value >> 32) & 0xFFFF)
        assert h_count - 2 == dut.h_count_out.value
        assert (v_count + 750 - 2) % 750 == dut.v_count_out.value
        dut.h_count_in.value = h_count
        dut.pixel_data_in.value = data_in(h_count)

    await FallingEdge(dut.clk)
    assert check_val0(1278, dut.line_buffer_out.value & 0xFFFF)
    assert check_val1(1278, (dut.line_buffer_out.value >> 16) & 0xFFFF)
    assert check_val2(1278, (dut.line_buffer_out.value >> 32) & 0xFFFF)
    assert 1278 == dut.h_count_out.value
    assert (v_count + 750 - 2) % 750 == dut.v_count_out.value

    await FallingEdge(dut.clk)
    assert check_val0(1279, dut.line_buffer_out.value & 0xFFFF)
    assert check_val1(1279, (dut.line_buffer_out.value >> 16) & 0xFFFF)
    assert check_val2(1279, (dut.line_buffer_out.value >> 32) & 0xFFFF)
    assert 1279 == dut.h_count_out.value
    assert (v_count + 750 - 2) % 750 == dut.v_count_out.value


@cocotb.test()
async def test_line_buffer(dut):
    """Your simulation test!
    TODO: Flesh this out with value sets and print statements. Maybe even some assertions, as a treat.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    h_count = 0
    v_count = 0
    dut.h_count_in.value = 0
    dut.v_count_in.value = 0
    dut.pixel_data_in.value = 0
    # use helper function to assert reset signal
    await reset(dut.rst, dut.clk)

    # test that line is correct
    await test_line(dut, 0, lambda h: h)
    await test_line(
        dut,
        1,
        lambda h: h + 10,
        check_val=(always_true, always_true, lambda h, v: h == v),
    )
    await test_line(
        dut,
        2,
        lambda h: h + 30,
        check_val=(always_true, lambda h, v: h == v, lambda h, v: h + 10 == v),
    )
    await test_line(
        dut,
        3,
        lambda h: h + 70,
        check_val=(
            lambda h, v: h == v,
            lambda h, v: h + 10 == v,
            lambda h, v: h + 30 == v,
        ),
    )


def test_line_buffer_runner():
    """Run the line_buffer runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "line_buffer.sv",
        proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v",
    ]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="line_buffer",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="line_buffer",
        test_module="test_line_buffer",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_line_buffer_runner()
