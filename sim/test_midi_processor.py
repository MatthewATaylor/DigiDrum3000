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


CLK_FREQ = 100e6
UART_BAUD = 31250
UART_PERIOD = int(CLK_FREQ / UART_BAUD)  # Number of clk cycles per UART bit

# LSB first
NOTE_ON_CH10 = [0,1,0,1,1,0,0,1]
NOTE_ON_CH09 = [1,0,0,1,1,0,0,1]
DATA32 = [0,0,0,0,0,1,0,0]
DATA12 = [0,0,1,1,0,0,0,0]
START  = [0]
STOP   = [1]


def bits_to_int(bits):
    bit_sum = 0
    for i, bit in enumerate(bits):
        bit_sum += bit * 2**i
    return bit_sum


def midi_list_to_msg(midi):
    msg = []
    for byte in midi:
        msg += START+byte+STOP
    return msg


async def write_uart(dut, messages):
    for msg in messages:
        for bit in msg:
            dut.din.value = bit
            await ClockCycles(dut.clk, UART_PERIOD)


@cocotb.test()
async def test_a(dut):
    messages = [
        [NOTE_ON_CH10,       DATA32, DATA12],
        [NOTE_ON_CH10,       DATA12, DATA32],
        [[1,1,1,1,1,1,1,1,], DATA32, DATA12],
        [NOTE_ON_CH09,       DATA32, DATA12],
    ]

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    cocotb.start_soon(write_uart(dut))

    expected_outs = [
        {'key': 32, 'velocity': 12},
        {'key': 12, 'velocity': 32},
        {'key': 32, 'velocity': 12},
        None
    ]

    for midi_list in messages:
        msg = midi_list_to_msg(midi_list)


    for i in range(2):
        dout_valid_received = False
        while True:
            await ClockCycles(dut.clk, 1)
            if (dut.dout_valid.value == 1):
                dout_valid_received = True
                assert dut.key.value == bits_to_int(NOTE)
                assert dut.velocity.value == bits_to_int(VELOCITY)
                break
        assert dout_valid_received


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "midi_processor.sv"]
    sources += [proj_path / "hdl" / "uart_receive.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "midi_processor"
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

