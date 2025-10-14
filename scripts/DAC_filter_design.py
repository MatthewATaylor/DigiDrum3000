import numpy as np
import matplotlib.pyplot as plt
import scipy.signal
import random as rand
import math


over_rate = 16
sample_rate = over_rate * 44100


def find_gain(frequency, filt_coeffs):
    N = 8000
    delta_angle = 2 * math.pi * frequency / sample_rate
    angle = 0
    test_tone = []

    for i in range(N):
        if (i + over_rate // 2) % over_rate == 0:
            test_tone.append(over_rate * math.sin(angle))
        else:
            test_tone.append(0)
        angle += delta_angle
        if angle > 2 * math.pi:
            angle -= 2 * math.pi
    while abs(angle) > delta_angle * (over_rate // 2):
        N += over_rate
        for j in range(over_rate // 2):
            test_tone.append(0)
        test_tone.append(over_rate * math.sin(angle))
        for j in range((over_rate - 1) // 2):
            test_tone.append(0)
        angle += over_rate * delta_angle
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


# 63.8 us latency
# -80dB alias frequencies
# -0.3dB worst pass band attentuation
filt_coeffs = scipy.signal.firwin(
    700 * 2 - 1, 21025, width=6100, pass_zero="lowpass", fs=sample_rate, scale=True
)
# filt_coeffs = scipy.signal.firls(
#    512 * 2 - 1,
#    [[0, 20000], [24000, sample_rate / 2]],
#    [[1, 1], [0, 0]],
#    fs=sample_rate,
# )
filt_coeffs = scipy.signal.minimum_phase(filt_coeffs)
print(len(filt_coeffs))

with open("DAC_filter_coeffs.txt", "w") as f:
    for i in range(over_rate):
        for coeff in filt_coeffs[i::over_rate]:
            if coeff < 0:
                f.write(f"{int(abs(coeff) * 2**19) ^ 0xFFFF - 1:04x}\n")
            else:
                f.write(f"{int(coeff * 2**19):04x}\n")

for i in range(len(filt_coeffs)):
    if filt_coeffs[i] < 0:
        filt_coeffs[i] = 2**-19 * float(-int(abs(filt_coeffs[i]) * 2**19))
    else:
        filt_coeffs[i] = 2**-19 * float(int(filt_coeffs[i] * 2**19))
w, H = scipy.signal.freqz(filt_coeffs, worN=10000)

max_gain = 0
for freq in [20, 80, 200, 1000, 8000, 14000, 20000]:
    max_gain = max(max_gain, find_gain(freq, filt_coeffs))

print(f"alias gain: {max_gain:.4}  ({20 * math.log10(max_gain):.3}dB)")


w = w * sample_rate / (2 * np.pi)

fig, (ax, ax2) = plt.subplots(2)
ax.loglog(w, np.abs(H))
ax.set_ybound(1e-5, 2)
ax.set_xbound(10000, sample_rate // 2)
ax2.plot(filt_coeffs)
plt.show()
