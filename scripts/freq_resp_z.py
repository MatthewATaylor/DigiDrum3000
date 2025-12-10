import numpy as np
import matplotlib.pyplot as plt
import math

# Plot the frequency response of various Z-domain transfer functions

# SAMPLE_RATE = 1 / (2272 * 10e-9)
SAMPLE_RATE = 4 / (2272 * 10e-9)

f_in = np.logspace(2, 4, 10000)
w_in_unnormal = f_in * 2*np.pi
w_in = f_in / (SAMPLE_RATE/2) * np.pi


def H_ladder_x4(z, pot_fc, pot_q):
    wc = pot_fc / 1024 / 4 * SAMPLE_RATE*2
    s = 2*SAMPLE_RATE * (z-1) / (z+1)  # Bilinear transform (trapezoidal integrator)
    K = pot_q / 256 * 3/2  # HDL implementation scales tanh input by 3 and pot_q by 1/2
    return 1 / (K + (1+s/wc)**4)


def H_ladder(z, pot_fc, pot_q):
    G = pot_fc / 1024  # G = wc*T/2 -> cutoff: [0 Hz, 14 kHz]
    # G = math.tan(G)  # Cutoff prewarping
    s = 1/G * (z-1) / (z+1)  # Bilinear transform (trapezoidal integrator)
    K = pot_q / 256
    return 1 / (K + (1+s)**4)

def H_LPF_BT(z):
    # Each 1-pole LPF used in the ladder filter
    POT_FC = 512
    G = POT_FC / 1024
    G = math.tan(G)
    s = 1/G * (z-1) / (z+1)
    return 1 / (1+s)

freq_resp_LPF_BT = np.abs(H_LPF_BT(np.exp(1j*w_in)))
print(f'LPF BT Max: {max(freq_resp_LPF_BT)}')
print(f'LPF BT Min: {min(freq_resp_LPF_BT)}')

def H_LPF(z):
    # LPF used in feedback loop of reverb comb filters
    DAMP = 512/1024
    return (1 - DAMP) / (1 - DAMP/z)

freq_resp_LPF = np.abs(H_LPF(np.exp(1j*w_in)))
print(f'LPF Max: {max(freq_resp_LPF)}')
print(f'LPF Min: {min(freq_resp_LPF)}')

def H_LBCF(z):
    # Low-pass feedback comb filter
    N = 100
    FB = 0.75
    LPF_MAX = 1
    return z**(-N) / (1 - FB*LPF_MAX * z**(-N))

freq_resp_LBCF = np.abs(H_LBCF(np.exp(1j*w_in)))
print(f'LBCF Max: {max(freq_resp_LBCF)}')
print(f'LBCF Min: {min(freq_resp_LBCF)}')

def H_AP(z):
    # All-pass filter approximation
    # Is actually series combination of feedback/feedforward comb filters
    N = 100
    FB = 0.5
    return (-1 + (1+FB) * z**(-N)) / (1 - FB * z**(-N))

freq_resp_AP = np.abs(H_AP(np.exp(1j*w_in)))
print(f'AP Max: {max(freq_resp_AP)}')
print(f'AP Min: {min(freq_resp_AP)}')


fig, ax = plt.subplots()
fc = 1000
wc = 2*np.pi*fc
pot_fc = wc * 1024 * 4 / SAMPLE_RATE / 2
print(pot_fc)
for pot_q in [0, 768]:
    freq_resp_ladder = np.abs(
        H_ladder_x4(
            np.exp(1j*w_in_unnormal/SAMPLE_RATE),
            pot_fc=pot_fc,
            pot_q=pot_q
        )
    )
    freq_resp_ladder_db = 20 * np.log10(freq_resp_ladder)
    ax.plot(f_in, freq_resp_ladder_db, label=f'k={int(pot_q/256*3/2)}')
ax.set_ylim([-60, 60])
ax.set_xscale('log')
ax.set_xlabel('Frequency [Hz]')
ax.set_ylabel('Magnitude [dB]')
ax.legend()
fig.tight_layout()
plt.show()
