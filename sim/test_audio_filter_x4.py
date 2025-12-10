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


SAMPLE_PERIOD = 2272/4
SAMPLE_RATE = 1 / (SAMPLE_PERIOD*10e-9)
SOFT_CLIP = 0


def H_ladder_x4(z, pot_fc, pot_q):
    wc = pot_fc / 1024 / 4 * SAMPLE_RATE*2
    s = 2*SAMPLE_RATE * (z-1) / (z+1)  # Bilinear transform (trapezoidal integrator)
    K = pot_q / 256 * 1/2  # HDL implementation scales tanh input by 3 and pot_q by 1/2
    return 1 / (K + (1+s/wc)**4)


def square(theta):
    if math.sin(theta) > 0:
        return 2**15-1
    else:
        return -2**15


def tanh_approx_float(x):
    n = x*2**30 + x*2**31 + x**3
    d = 2**30 + x**2 + 2*x**2
    return n/d


def tanh_approx(x):
    x = np.int64(x)
    n = (x<<30) + (x<<31) + x**3
    d = (1<<30) + x**2 + ((x**2)<<1)
    n_sign = n < 0
    out = abs(n)//d
    if n_sign:
        out = -out
    return out


def filter_step_float(x, s, pot_cutoff, pot_quality):
    k = pot_quality/256/2
    g = pot_cutoff/1024/4
    S = g**3 * s[0] + g**2 * s[1] + g * s[2] + s[3]
    G = g**4
    u = (x - k*S) / (1 + k*G)
    if u > 2**15-1:
        u = 2**15-1
    elif u < -2**15:
        u = -2**15
    if SOFT_CLIP:
        u = tanh_approx_float(u)
        # u = 2**15*math.tanh(3*u/2**15)
    G = g / (1 + g)
    for j in range(4):
        v = G * (u - s[j])
        u = v + s[j]
        s[j] = u + v
    return u, s


def filter_step(x, s, pot_cutoff, pot_quality):
    k = np.int64(pot_quality)
    g_lsh12 = np.int64(pot_cutoff)

    for i in range(4):
        if i == 0:
            S = np.int64(s[3]<<24)
        elif i == 1:
            S += (s[2]<<12) * g_lsh12
        elif i == 2:
            S += s[1] * g_lsh12**2
        elif i == 3:
            S += (s[0]>>12) * g_lsh12**3

    S_shift = np.int64(S>>25)  # 16 bits

    if S_shift > 2**15-1 or S_shift < -2**15:
        raise Exception('OVERFLOW: S')

    # pot_quality / 256 = k
    kS = (k * S_shift) >> 8
    u = int(x) - kS
    if u > 2**15-1:
        raise Exception('CLIP')
        u = 2**15-1
    elif u < -2**15:
        raise Exception('CLIP')
        u = -2**15
    if SOFT_CLIP:
        u = tanh_approx(u)
        # u = int(2**15 * math.tanh(3*u/2**15))
    u = np.int64(u)
    G_lsh12 = np.int64()
    G_lsh12 = (g_lsh12<<12) // (np.int64(1<<12) + g_lsh12)

    for j in range(4):
        v_lsh12 = G_lsh12 * (u - s[j])
        u_lsh12 = v_lsh12 + (int(s[j])<<12)

        s[j] = (u_lsh12 + v_lsh12) >> 12
        if s[j] > 2**15-1 or s[j] < -2**15:
            raise Exception('OVERFLOW: s[j]')
        s[j] = np.int64(s[j])

        u = u_lsh12 >> 12
        if u > 2**15-1 or u < -2**15:
            raise Exception('OVERFLOW: u')

    return u, s


@cocotb.test()
async def test_variable_f(dut):
    SECONDS_PER_SAMPLE = SAMPLE_PERIOD * 10e-9
    CYCLES = 6
    AMPLITUDE = 2**13-1

    fc = 5000
    wc = 2*np.pi*fc
    pot_fc = int(wc * 1024 * 4 / SAMPLE_RATE / 2)

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    f_list_fine = np.logspace(3, 4, 1000)
    w_list_fine = f_list_fine * 2 * np.pi

    fig, ax = plt.subplots()
    q_list = [0, 512, 1023]
    for q in q_list:
        gains = []
        f_list = np.logspace(3, 4, 10)
        for f in f_list:
            dut.rst.value = 1
            dut.pot_cutoff.value = pot_fc
            dut.pot_quality.value = q
            await ClockCycles(dut.clk, 2)
            dut.rst.value = 0

            fig_inner, ax_inner = plt.subplots()

            print(f'Simulating F={f}...')
            samples_per_cycle = 1/f / SECONDS_PER_SAMPLE

            n_in = []
            x = []
            n_out = []
            y = []
            y_expected = []
            y_expected_float = []

            next_y_expected = None
            next_y_expected_float = None
            s = [0,0,0,0]
            s_float = [0,0,0,0]

            last_in_cycle = 0
            max_out = 0

            for i in range(int(CYCLES*samples_per_cycle*SAMPLE_PERIOD)):
                if i % SAMPLE_PERIOD == 0:
                    n = i / SAMPLE_PERIOD
                    t = n * SECONDS_PER_SAMPLE
                    sample = int(AMPLITUDE * math.sin(2 * math.pi * f * t))
                    dut.sample_in.value = sample
                    dut.sample_in_valid.value = 1

                    n_in.append(i)
                    x.append(sample)

                    next_y_expected, s = \
                        filter_step(sample, s, pot_fc, q)
                    next_y_expected_float, s_float = \
                        filter_step_float(sample, s_float, pot_fc, q)

                    last_in_cycle = i
                else:
                    dut.sample_in_valid.value = 0

                if dut.sample_out_valid.value == 1:
                    sample = dut.sample_out.value.signed_integer

                    n_out.append(i)
                    y.append(sample)
                    y_expected.append(next_y_expected)
                    y_expected_float.append(next_y_expected_float)

                    if i > samples_per_cycle*SAMPLE_PERIOD*5:
                        if abs(sample) > max_out:
                            max_out = abs(sample)

                    # print(f'Recieved: {sample}, Expected: {next_y_expected}, Float: {next_y_expected_float}, Latency: {i-last_in_cycle}')
                    assert sample == next_y_expected

                await ClockCycles(dut.clk, 1)

            gain = max_out / AMPLITUDE
            print(f'gain={gain}')
            gains.append(20 * np.log10(gain))

            ax_inner.scatter(n_in, x, color='black', label='Input')
            ax_inner.plot(n_out, y, marker='.', label='Output (HDL)')
            ax_inner.plot(n_out, y_expected, marker='.', label='Output (Python, Fixed Point)')
            ax_inner.plot(n_out, y_expected_float, marker='.', label='Output (Python, Floating Point)')

            ax_inner.set_xlabel('Cycle Count')
            ax_inner.set_ylabel('Sample')
            ax_inner.legend()
            fig_inner.suptitle(f'Input Frequency = {f} Hz')
            fig_inner.tight_layout()

        freq_resp_ladder = np.abs(
            H_ladder_x4(
                np.exp(1j*w_list_fine/SAMPLE_RATE),
                pot_fc=pot_fc,
                pot_q=q
            )
        )
        freq_resp_ladder_db = 20 * np.log10(freq_resp_ladder)
        lines = ax.plot(f_list_fine, freq_resp_ladder_db, label=f'k={int(round(q/256/2))}')
        plot_color = lines[0].get_color()
        ax.scatter(f_list, gains, color=plot_color)

    ax.set_xscale('log')
    ax.set_xlabel('Frequency [Hz]')
    ax.set_ylabel('Magnitude [dB]')
    ax.legend()
    fig.tight_layout()
    plt.show()


def is_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    #sim = os.getenv("SIM","vivado")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "audio_filter_x4.sv"]
    sources += [proj_path / "hdl" / "divider.sv"]
    sources += [proj_path / "hdl" / "tanh_approx.sv"]
    sources += [proj_path / "hdl" / "clipper.sv"]
    build_test_args = ["-Wall"]
    parameters = {'SOFT_CLIP': SOFT_CLIP}
    hdl_toplevel = "audio_filter_x4"
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

