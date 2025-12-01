import numpy as np
import matplotlib.pyplot as plt
import math

# Plot the frequency response of various Z-domain transfer functions

w_in = np.linspace(0, np.pi, 10000)

def H_ladder(z):
    POT_FC = 512
    POT_Q = 750

    G = POT_FC / 1024  # G = wc*T/2 -> cutoff: [0 Hz, 14 kHz]
    G = math.tan(G)  # Cutoff prewarping
    s = 1/G * (z-1) / (z+1)  # Bilinear transform (trapezoidal integrator)
    K = POT_Q / 256
    return 1 / (K + (1+s)**4)

freq_resp_ladder = np.abs(H_ladder(np.exp(1j*w_in)))
print(f'Ladder Max: {max(freq_resp_ladder)}')
print(f'Ladder Min: {min(freq_resp_ladder)}')

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
ax.plot(w_in, freq_resp_LBCF)
plt.show()
