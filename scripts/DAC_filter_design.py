import numpy as np
import matplotlib.pyplot as plt
import scipy.signal
import random as rand
import math

sample_rate = 8 * 44100


def find_gain(frequency, filt_coeffs):
    N = 8000
    delta_angle = 2 * math.pi * frequency / sample_rate
    angle = 0
    test_tone = []

    for i in range(N):
        if (i + 4) % 8 == 0:
            test_tone.append(8 * math.sin(angle))
        else:
            test_tone.append(0)
        angle += delta_angle
        if angle > 2 * math.pi:
            angle -= 2 * math.pi
    while abs(angle) > delta_angle * 4:
        N += 8
        for j in range(4):
            test_tone.append(0)
        test_tone.append(8 * math.sin(angle))
        for j in range(3):
            test_tone.append(0)
        angle += 8 * delta_angle
        if angle > 2 * math.pi:
            angle -= 2 * math.pi

    test_tone = scipy.signal.lfilter(filt_coeffs, 1, test_tone)

    window = scipy.signal.windows.flattop(N, sym=False)
    fft = scipy.fftpack.fft(test_tone * window)
    sample_mags = 2.0 / N * np.abs(fft[: N // 2])
    fft_freq = scipy.fftpack.fftfreq(len(test_tone))

    cutoff = 0
    # zero out fundemental
    for i in range(len(fft)):
        if (
            fft_freq[i] >= frequency / sample_rate
            and fft_freq[i - 1] < frequency / sample_rate
        ):
            fundemental_index = i
            if abs(fft_freq[i] - frequency / sample_rate) > abs(
                fft_freq[i - 1] - frequency / sample_rate
            ):
                fundemental_index = i - 1
            for j in range(-4, 5):
                sample_mags[fundemental_index + j] = 0

        if fft_freq[i] >= 20000 / sample_rate and fft_freq[i - 1] < 20000 / sample_rate:
            cutoff = i

    return math.sqrt(np.sum(np.square(sample_mags[cutoff:])))


# ~4 sample delay
filt_coeffs = scipy.signal.firwin(
    1024 * 2 - 1, 21050, width=6500, pass_zero="lowpass", fs=sample_rate, scale=True
)
filt_coeffs = scipy.signal.minimum_phase(filt_coeffs)
filt_coeffs = filt_coeffs[:512]

with open("DAC_filter_coeffs.txt", "w") as f:
    for i in range(8):
        for coeff in filt_coeffs[i::8]:
            if coeff < 0:
                f.write(f"{int(abs(coeff) * 2**15) ^ 0xFFFF - 1:04x}\n")
            else:
                f.write(f"{int(coeff * 2**15):04x}\n")

for i in range(len(filt_coeffs)):
    if filt_coeffs[i] < 0:
        filt_coeffs[i] = 2**-15 * float(-int(abs(filt_coeffs[i]) * 2**15))
    else:
        filt_coeffs[i] = 2**-15 * float(int(filt_coeffs[i] * 2**15))
w, H = scipy.signal.freqz(filt_coeffs, worN=10000)

max_gain = 0
for freq in [80, 200, 1000, 8000, 18000]:
    max_gain = max(max_gain, find_gain(freq, filt_coeffs))

print(f"alias gain: {max_gain:.4}  ({20 * math.log10(max_gain):.3}dB)")


w = w * sample_rate / (2 * np.pi)

fig, (ax, ax2) = plt.subplots(2)
ax.loglog(w, np.abs(H))
ax.set_ybound(1e-5, 2)
ax.set_xbound(10000, sample_rate // 2)
ax2.semilogy(abs(filt_coeffs))
plt.show()
