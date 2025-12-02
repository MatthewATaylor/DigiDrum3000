import cocotb
import os
import sys
import math
import logging
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly,with_timeout
from cocotb.utils import get_sim_time as gst
#from cocotb.runner import get_runner
import wave
import numpy as np
from vicoco.vivado_runner import get_runner
test_file = os.path.basename(__file__).replace(".py","")


@cocotb.test()
async def test_a(dut):
    phases_in_float = np.linspace(-np.pi/4, np.pi/4, 100)
    phases_in_fixed = np.zeros(len(phases_in_float), dtype=np.int16)
    for i, phase in enumerate(phases_in_float):
        phases_in_fixed[i] = np.int16(phase * 2**13)

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    for i, phase in enumerate(phases_in_fixed):
        dut.phase_valid.value = 1
        dut.phase.value = int(phase)

        await ClockCycles(dut.clk, 1)
        while dut.dout_valid == 0:
            dut.phase_valid.value = 0
            await ClockCycles(dut.clk, 1)

        sinh = dut.sinh.value.signed_integer
        cosh = dut.cosh.value.signed_integer

        sinh_expected = int(math.sinh(phase / 2**13) * 2**14)
        cosh_expected = int(math.cosh(phase / 2**13) * 2**14)

        print(f'sinh | received: {sinh}, expected: {sinh_expected}')
        print(f'cosh | received: {cosh}, expected: {cosh_expected}')
        print()


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    #sim = os.getenv("SIM", "icarus")
    sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "cordic_sinh_cosh_wrapper.sv"]
    sources += [proj_path / "ip" / "cordic_sinh_cosh" / "cordic_sinh_cosh.xci"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "cordic_sinh_cosh_wrapper"
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    #runner = get_runner('vivado', xilinx_root='/opt/Xilinx/2025.1/Vivado/')
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

