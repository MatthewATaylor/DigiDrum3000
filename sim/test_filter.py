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


def clamp(x, low, high):
    if x < low:
        return low
    if x > high:
        return high
    return x


def rgb565_to_rgb8(rgb565):
    r = rgb565 >> 11
    g = (rgb565 >> 5) & 0x3F
    b = rgb565 & 0x1F
    return (r << 3, g << 2, b << 3)


def rgb8_to_rgb565(rgb8):
    r, g, b = rgb8
    r = r >> 3
    g = g >> 2
    b = b >> 3
    return (r << 11) | (g << 5) | b


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


IMAGE_WIDTH = 128


async def drive_pixel(dut, i, image):
    await FallingEdge(dut.clk)
    half_dist = dut.half_x_dist.value
    dut.h_count.value = i % IMAGE_WIDTH
    dut.v_count.value = i // IMAGE_WIDTH
    to_write = 31
    if int(half_dist) <= 2 and int(half_dist) > 0:
        to_write = 255
    if i >= 2:
        image.putpixel(
            ((i - 2) % IMAGE_WIDTH, (i - 2) // IMAGE_WIDTH),
            (to_write, to_write, to_write),
        )


@cocotb.test()
async def test_filter(dut):
    """Your simulation test!
    TODO: Flesh this out with value sets and print statements. Maybe even some assertions, as a treat.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    dut.h_count_in.value = 0
    dut.v_count_in.value = 0
    dut.active_draw_in.value = 0
    dut.cutoff.value = 0
    dut.quality.value = 0
    dut.pixel_in.value = 0
    # use helper function to assert reset signal

    for j in range(0, 1024, 127):
        dut.cutoff.value = j
        await reset(dut.rst, dut.clk)
        dut.v_count_in.value = 725
        dut.active_draw_in.value = False
        for i in range(1200, 1650, 1):
            await FallingEdge(dut.clk)
            dut.h_count_in.value = i
            dut.pixel_in.value = ((i % 16) == 0) * 0xFFFFFF
        coeffs = []
        for i in range(5):
            coeffs.append((dut.gaussian_coeffs_view.value >> (i * 8)) & 0xFF)
        print(f"cutoff: {dut.cutoff.value} coeffs:{coeffs}")


def test_filter_runner():
    """Run the star_noise runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v",
        proj_path / "ip" / "cordic_sinhcosh_folded" / "cordic_sinhcosh_folded.xci",
        proj_path / "hdl" / "cordic_sinhcosh_folded_wrapper.sv",
        proj_path / "hdl" / "divider.sv",
        proj_path / "hdl" / "exponent.sv",
        proj_path / "hdl" / "video_filter.sv",
        proj_path / "hdl" / "line_buffer.sv",
        proj_path / "hdl" / "dither_gen.sv",
    ]
    build_test_args = ["-Wall"]
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="video_filter",
        always=True,
        build_args=build_test_args,
        parameters={},
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="video_filter",
        test_module="test_filter",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_filter_runner()
