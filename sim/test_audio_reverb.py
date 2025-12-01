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
import wave
import numpy as np
#from vicoco.vivado_runner import get_runner
test_file = os.path.basename(__file__).replace(".py","")


SAMPLE_PERIOD = 2272


class AP:
    def __init__(self, delay_samples, fb):
        self.delay_samples = delay_samples
        self.buf = np.zeros(delay_samples, dtype=np.int32)  # 18-bit
        self.buf_index = 0
        self.fb = fb

    def process(self, sample):
        # Max gain of 5/3 w/o clipping
        # sample: 17-bit

        buf_out = self.buf[self.buf_index]
        out = np.int32(0)

        out_full = -np.int32(sample) + buf_out
        if out_full > 2**16-1:
            print('CLIP: AP out')
            out = 2**16-1
        elif out_full < -2**16:
            print('CLIP: AP out')
            out = -2**16
        else:
            out = out_full

        buf_next = np.int32(sample) + (buf_out >> self.fb)
        if buf_next > 2**17-1 or buf_next < -2**17:
            raise Exception('AP buf_next overflow')
        self.buf[self.buf_index] = buf_next

        self.buf_index += 1
        if self.buf_index >= self.delay_samples:
            self.buf_index = 0
        return out


class LBCF:
    def __init__(self, delay_samples, fb, damp):
        self.delay_samples = delay_samples
        self.buf = np.zeros(delay_samples, dtype=np.int32)  # 18-bit
        self.buf_index = 0
        self.fb = fb
        self.damp = damp
        self.lpf_out = np.int32(0)  # 24-bit

    def process(self, sample):
        # Max gain of 1 / (1-fb/1024) w/o clipping
        # sample: 16-bit

        out = self.buf[self.buf_index]

        lpf_next = (
            (out<<10) +
            (self.lpf_out-out) * self.damp  # 25x10 bit mult
        ) >> 10
        self.lpf_out = lpf_next

        buf_next = (
            (np.int64(sample)<<13) +
            (np.int64(self.lpf_out) * (self.fb + (895<<3)))  # 24x14 bit mult
        ) >> 13
        if buf_next > 2**17-1:
            print('CLIP: LBCF buf')
            self.buf[self.buf_index] = 2**17-1
        elif buf_next < -2**17:
            print('CLIP: LBCF buf')
            self.buf[self.buf_index] = -2**17
        else:
            self.buf[self.buf_index] = buf_next

        self.buf_index += 1
        if self.buf_index >= self.delay_samples:
            self.buf_index = 0
        return out


# User controls
POT_ROOM_SIZE = 1023
POT_FEEDBACK = 1023
POT_WET = 1023
STEREO = False  # True if reverb is last in effects chain

SPREAD = 23
FB_AP = 1
if POT_FEEDBACK == 1023:
    DAMP = 1
else:
    DAMP = 1023-POT_FEEDBACK
FB_LBCF = POT_ROOM_SIZE

# ap_delays = [
#     556,
#     441,
#     341,
#     225
# ]
ap_delays = [
    3,
    4,
    5,
    6
]
aps_l = [AP(delay       , FB_AP) for delay in ap_delays]
aps_r = [AP(delay+SPREAD, FB_AP) for delay in ap_delays]
aps = [aps_l, aps_r]

# lbcf_delays = [
#     1116,
#     1188,
#     1277,
#     1356,
#     1422,
#     1491,
#     1557,
#     1617
# ]
lbcf_delays = [
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12
]
lbcfs_l = [LBCF(delay       , FB_LBCF, DAMP) for delay in lbcf_delays]
lbcfs_r = [LBCF(delay+SPREAD, FB_LBCF, DAMP) for delay in lbcf_delays]
lbcfs = [lbcfs_l, lbcfs_r]


def process(sample):
    # Process sample in separate L/R channels

    lbcf_out_accum = np.int32(0)
    for lbcf in lbcfs[0]:
        lbcf_out_accum += lbcf.process(sample)

    apf_in = lbcf_out_accum >> 4
    for ap in aps[0]:
        apf_in = ap.process(apf_in)

    out_wet = apf_in >> 1

    out_l = np.int32(out_wet)
    xi = np.int32(sample)
    y_l = (POT_WET * (out_l-xi) + (xi<<10)) >> 10
    return y_l


def get_samples():
    SAMPLE_RATE = 44100
    with wave.open('../media/resampled/sd.wav') as wav_file:
        assert wav_file.getframerate() == SAMPLE_RATE
        nframes = wav_file.getnframes()
        frames = wav_file.readframes(nframes)
        x = np.frombuffer(frames, dtype='<i2')
    return x


@cocotb.test()
async def test_a(dut):
    SAMPLES = 200

    samples = get_samples()

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst.value = 1
    dut.pot_wet.value = POT_WET
    dut.pot_size.value = POT_ROOM_SIZE
    dut.pot_feedback.value = POT_FEEDBACK
    dut.is_stereo.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst.value = 0

    fig, ax = plt.subplots()
    n_in = []
    x = []
    n_out = []
    y = []
    y_expected = []

    next_y_expected = None

    for i in range(int(SAMPLES*SAMPLE_PERIOD)):
        if i % SAMPLE_PERIOD == 0:
            n = int(i / SAMPLE_PERIOD)
            sample = samples[n]
            dut.sample_in.value = int(sample)
            dut.sample_in_valid.value = 1
            n_in.append(i)
            x.append(sample)
            next_y_expected = process(sample)
        else:
            dut.sample_in_valid.value = 0

        if dut.sample_out_valid.value == 1:
            sample_l = dut.sample_out_l.value.signed_integer
            sample_r = dut.sample_out_r.value.signed_integer

            print(f'Sample #: {len(y)}, Recieved: {sample_l}, Expected: {next_y_expected}')

            n_out.append(i)
            y.append(sample_l)
            y_expected.append(next_y_expected)

            assert sample_l == next_y_expected
            assert sample_r == next_y_expected

        await ClockCycles(dut.clk, 1)

    ax.scatter(n_in, x, color='black', label='Input')
    ax.plot(n_out, y, marker='.', label='Output (HDL)')
    ax.plot(n_out, y_expected, marker='.', label='Output (Python, Fixed Point)')

    ax.set_xlabel('Cycle Count')
    ax.set_ylabel('Sample')
    ax.legend()
    fig.tight_layout()
    plt.show()


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "audio_reverb_stereo.sv"]
    sources += [proj_path / "hdl" / "audio_reverb.sv"]
    sources += [proj_path / "hdl" / "clipper.sv"]
    sources += [proj_path / "hdl" / "xilinx_single_port_ram_read_first.v"]
    build_test_args = ["-Wall"]
    parameters = {}
    hdl_toplevel = "audio_reverb_stereo"
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

