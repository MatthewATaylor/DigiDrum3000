import cocotb
import os
import sys
import math
import logging
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly,with_timeout
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner
import matplotlib.pyplot as plt
#from vicoco.vivado_runner import get_runner
test_file = os.path.basename(__file__).replace(".py","")


SAMPLE_PERIOD_IN = 2272/4
F = 5000
SIG_CYCLES = 6
DURATION_S = 1/F * SIG_CYCLES
CLOCK_CYCLES = int(DURATION_S / 10e-9)
SAMPLE_MAX = 2**15 - 1


@cocotb.test()
async def test_a(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    i_in = []
    x_list = []

    i_out = []
    y_list = []

    fig, ax = plt.subplots()

    for i in range(CLOCK_CYCLES):
        if i % SAMPLE_PERIOD_IN == 0:
            t = i * 10e-9
            x = int(SAMPLE_MAX * math.sin(2 * math.pi * F * t))
            dut.sample_in.value = x
            dut.sample_in_valid.value = 1

            i_in.append(i)
            x_list.append(x)
        else:
            dut.sample_in_valid.value = 0


        if dut.sample_out_valid.value == 1:
            y = dut.sample_out.value.signed_integer

            i_out.append(i)
            y_list.append(y)

            print(f'Received sample: {y} on clock cycle: {i}')

        await ClockCycles(dut.clk, 1)

    ax.plot(i_in, x_list, marker='.', label='Input')
    ax.plot(i_out, y_list, marker='.', label='Output')
    ax.set_xlabel('Clock Cycle')
    ax.set_ylabel('Sample Value')
    ax.legend()
    fig.suptitle(f'Input Frequency = {F} Hz')
    fig.tight_layout()

    plt.show()


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "downsampler.sv"]
    sources += [proj_path / "hdl" / "dist_ram.sv"]
    sources += [proj_path / "hdl" / "xilinx_single_port_ram_read_first.v"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "downsampler"
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=hdl_toplevel,
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel=hdl_toplevel,
        test_module=test_file,
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    is_runner()

