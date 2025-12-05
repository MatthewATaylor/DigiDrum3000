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

WIDTH = 64
HEIGHT = 64
LATENCY = 10


def pixel_to_rgb(pixel):
    r = pixel >> 16
    g = (pixel >> 8) & 0xFF
    b = pixel & 0xFF
    return (r, g, b)


async def reset(rst, clk):
    """Helper function to issue a reset signal to our module"""
    rst.value = 1
    await ClockCycles(clk, 3)
    rst.value = 0
    await ClockCycles(clk, 2)


async def drive_pixel(dut, pixel, image_through, index):
    await FallingEdge(dut.clk)
    if index >= LATENCY:
        image_through.putpixel(
            ((index - LATENCY) % WIDTH, (index - LATENCY) // WIDTH),
            pixel_to_rgb(int(dut.dram_write_data.value)),
        )
    dut.pixel_in.value = (pixel[0] << 16) + (pixel[1] << 8) + pixel[2]
    dut.dram_read_data = (index % 2) * 0xFFFF
    dut.h_count_in.value = index % WIDTH
    dut.v_count_in.value = index // WIDTH


@cocotb.test()
async def test_video_reverb(dut):
    """Your simulation test!
    TODO: Flesh this out with value sets and print statements. Maybe even some assertions, as a treat.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    dut.h_count_in.value = 0
    dut.v_count_in.value = 0
    dut.active_draw_in.value = 0
    dut.wet.value = 0x200
    dut.feedback.value = 0x200
    dut.size.value = 0
    dut.pixel_in.value = 0
    dut.dram_read_data.value = 0
    image_through = Image.new("RGB", (WIDTH, HEIGHT))
    test_pattern = Image.open("../sim/test_pattern.png")
    # use helper function to assert reset signal

    await reset(dut.rst, dut.clk)
    for i in range(WIDTH * HEIGHT + LATENCY):
        await drive_pixel(
            dut,
            test_pattern.getpixel((i % WIDTH, (i // WIDTH) % HEIGHT)),
            image_through,
            i,
        )

    image_through.save("test_img.png")


def test_video_reverb_runner():
    """Run the star_noise runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "video_reverb.sv",
        proj_path / "hdl" / "YCoCg_R.sv",
        proj_path / "hdl" / "YCoCg_422.sv",
    ]
    build_test_args = ["-Wall"]
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="video_reverb",
        always=True,
        build_args=build_test_args,
        parameters={},
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="video_reverb",
        test_module="test_video_reverb",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_video_reverb_runner()
