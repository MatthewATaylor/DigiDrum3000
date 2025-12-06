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
LATENCY = 15


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


def YCoCg_422_to_RGB(val1, val2):
    Y1 = val1 >> 8
    Y2 = val2 >> 8
    Co = val1 & 0xFF
    Cg = val2 & 0xFF
    if Co >> 7 == 1:
        Co = -(Co ^ 0xFF) - 1
    if Cg >> 7 == 1:
        Cg = -(Cg ^ 0xFF) - 1
    r1 = Y1 + Co - Cg
    g1 = Y1 + Cg
    b1 = Y1 - Co - Cg
    r2 = Y2 + Co - Cg
    g2 = Y2 + Cg
    b2 = Y2 - Co - Cg
    pixels = [r1, g1, b1, r2, g2, b2]
    for pixel in pixels:
        if pixel > 255:
            pixel = 255
        if pixel < 0:
            pixel = 0
    return ((pixels[0], pixels[1], pixels[2]), (pixels[3], pixels[4], pixels[5]))


async def drive_pixel(dut, pixel, image_through, index, last_data):
    await FallingEdge(dut.clk)
    if index >= LATENCY and dut.dram_write_valid.value:
        if (index + LATENCY) % 2 == 1:
            pixels = YCoCg_422_to_RGB(last_data[0], int(dut.dram_write_data.value))
            image_through.putpixel(
                ((index - LATENCY - 1) % WIDTH, (index - LATENCY) // WIDTH),
                pixels[0],
            )
            image_through.putpixel(
                ((index - LATENCY) % WIDTH, (index - LATENCY) // WIDTH),
                pixels[1],
            )
        last_data[0] = int(dut.dram_write_data.value)
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
    dut.active_draw_in.value = True
    dut.wet.value = 0x200
    dut.feedback.value = 0x200
    dut.size.value = 0
    dut.pixel_in.value = 0
    dut.dram_read_data.value = 0
    image_through = Image.new("RGB", (WIDTH, HEIGHT))
    test_pattern = Image.open("../sim/test_pattern.png")
    # use helper function to assert reset signal

    await reset(dut.rst, dut.clk)
    stored_data = [0]
    for i in range(WIDTH * HEIGHT + LATENCY):
        await drive_pixel(
            dut,
            test_pattern.getpixel((i % WIDTH, (i // WIDTH) % HEIGHT)),
            image_through,
            i,
            stored_data,
        )

    image_through.save("test_img.png")


def test_video_reverb_runner():
    """Run the star_noise runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v",
        proj_path / "hdl" / "video_reverb.sv",
        proj_path / "hdl" / "dither_gen.sv",
        proj_path / "hdl" / "line_buffer.sv",
        proj_path / "hdl" / "filter_3x3.sv",
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
