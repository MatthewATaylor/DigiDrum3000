import cocotb
import os
import sys
from math import log
import logging
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly,with_timeout
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner
#from vicoco.vivado_runner import get_runner
test_file = os.path.basename(__file__).replace(".py","")


INSTRUMENT_COUNT = 3
SAMPLE_PERIOD = 20


async def run_unstacker(dut, samples, instr_index):
    sample_index = 0

    dut.din[instr_index].value = int(samples[sample_index])
    dut.din_valid[instr_index].value = 1

    for i in range(SAMPLE_PERIOD*len(samples)):
        if dut.din_ready[instr_index].value == 1:
            sample_index += 1
            if sample_index < len(samples):
                dut.din[instr_index].value = int(samples[sample_index])
            else:
                dut.din_valid[instr_index].value = 0
        await ClockCycles(dut.clk, 1)

@cocotb.test()
async def test_a(dut):
    dut.din.value = [0] * INSTRUMENT_COUNT
    dut.din_valid.value = [0] * INSTRUMENT_COUNT

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    # await ClockCycles(dut.clk, SAMPLE_PERIOD)

    # Row: instrument (i.e. values stored in unstacker)
    # Col: samples to sum during a sample period
    #   Positive inputs, no clipping
    #   Positive inputs, clipping
    #   Negative inputs, no clipping
    #   Negative inputs, clipping
    #   Zeros
    sample_sets = [
        [5e3, 2e4, -1e3, -1e4, 0],
        [6e3, 2e4, -2e3, -2e4, 0],
        [7e3, 2e4, -3e3, -2e4, 0]
    ]
    expected_douts = [sum(x) for x in zip(*sample_sets)]
    for i, dout in enumerate(expected_douts):
        if dout > 2**15 - 1:
            expected_douts[i] = 2**15 - 1
        elif dout < -2**15:
            expected_douts[i] = -2**15
        expected_douts[i] = int(expected_douts[i])

    for i in range(INSTRUMENT_COUNT):
        cocotb.start_soon(run_unstacker(dut, sample_sets[i], i))

    await ClockCycles(dut.clk, 1)
    for test_index in range(len(sample_sets[0])):
        for i in range(SAMPLE_PERIOD):
            await ClockCycles(dut.clk, 1)

        print(f'Reading result from sample set number: {test_index}')
        print(f'Expected result: {expected_douts[test_index]}')
        print(f'Received: {dut.dout.value.signed_integer}')

        assert dut.dout_valid.value == 1
        assert dut.dout.value.signed_integer == expected_douts[test_index]


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "sample_mixer.sv"]
    build_test_args = ["-Wall"]
    parameters = {
        'SAMPLE_PERIOD': SAMPLE_PERIOD,
        'INSTRUMENT_COUNT': INSTRUMENT_COUNT
    }
    hdl_toplevel = "sample_mixer"
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

