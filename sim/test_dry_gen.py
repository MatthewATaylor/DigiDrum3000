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
from cocotb.runner import get_runner

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


async def drive_pixel(dut, i, image):
    await FallingEdge(dut.clk)
    to_write = dut.intensity.value
    dut.h_count.value = i % 64
    dut.v_count.value = i // 64
    dut.noise_source.value = random.randint(0, 255)
    if i >= 3:
        image.putpixel(((i - 3) % 64, (i - 3) // 64), (to_write, to_write, to_write))


async def image_rend(dut, intensity):
    dut.h_count.value = 0
    dut.v_count.value = 0
    dut.noise_source.value = 0
    dut.inst_intensity = intensity
    # use helper function to assert reset signal
    await reset(dut.rst, dut.clk)

    test_image = Image.new("RGB", (64, 64))

    await FallingEdge(dut.clk)
    for i in range(64 * 64 + 3):
        await drive_pixel(dut, i, test_image)

    return test_image


@cocotb.test()
async def test_dry_gen(dut):
    """Your simulation test!
    TODO: Flesh this out with value sets and print statements. Maybe even some assertions, as a treat.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # set all inputs to 0
    images = []
    for i in range(255, -1, -8):
        image = await image_rend(dut, i)
        images.append(image)

    images[0].save(
        "vid.gif",
        save_all=True,
        append_images=images[1:],
        optimize=False,
        duration=32,
        loop=0,
    )

    print(os.path.curdir)
    subprocess.run(["pix", os.path.curdir + "/vid.gif"])


def test_dry_gen_runner():
    """Run the star_noise runner. Boilerplate code"""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "dry_gen.sv",
    ]
    build_test_args = ["-Wall"]
    if len(sys.argv) <= 1:
        top_level = "star_noise"
        parameters = {"WIDTH_POW": 5, "HEIGHT_POW": 4, "CENTER_X": 32, "CENTER_Y": 32}
    elif sys.argv[1] == "circle_hollow":
        top_level = "circle_hollow"
        parameters = {"RADIUS": 32, "CENTER_X": 32, "CENTER_Y": 32}
    elif sys.argv[1] == "square_noise":
        top_level = "square_noise"
        parameters = {"WIDTH": 64, "CENTER_X": 32, "CENTER_Y": 32}
    elif sys.argv[1] == "X_noise":
        top_level = "X_noise"
        parameters = {"WIDTH": 64, "CENTER_X": 32, "CENTER_Y": 32}
    elif sys.argv[1] == "X_hollow":
        top_level = "X_hollow"
        parameters = {"WIDTH": 64, "CENTER_X": 32, "CENTER_Y": 32}
    elif sys.argv[1] == "hex_hollow":
        top_level = "hex_hollow"
        parameters = {"HEIGHT": 64, "CENTER_X": 32, "CENTER_Y": 32}
    elif sys.argv[1] == "slit_noise":
        top_level = "slit_noise"
        parameters = {"WIDTH_POW": 5, "CENTER_X": 32, "CENTER_Y": 32}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=top_level,
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel=top_level,
        test_module="test_dry_gen",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    test_dry_gen_runner()
