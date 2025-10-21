import numpy as np
import matplotlib.pyplot as plt
import scipy.signal
import random as rand
import math


over_rate = 16
sample_rate = over_rate * 44100


def find_nearest_index(frequencies, target_freq):
    index = None
    for i in range(len(frequencies) - 1):
        if frequencies[i] >= target_freq and frequencies[i - 1] < target_freq:
            if abs(frequencies[i] - target_freq) < abs(
                frequencies[i - 1] - target_freq
            ):
                index = i
            else:
                index = i - 1
    return index


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


def max_true_peak_gain(filt_coeffs):
    g_max = 0
    for i in range(over_rate):
        sum = 0
        for coeff in filt_coeffs[i::over_rate]:
            sum += abs(coeff)
        g_max = max(g_max, 16 * sum)
    return g_max


def peak_delay_microseconds(filt_coeffs):
    c_max = 0
    c_max_i = 0
    for i in range(len(filt_coeffs)):
        if filt_coeffs[i] > c_max:
            c_max = filt_coeffs[i]
            c_max_i = i
    delay_seconds = (c_max_i + 1) / sample_rate
    return 1_000_000 * delay_seconds


# 63.8 us latency
# -80dB alias frequencies
# -0.3dB worst pass band attentuation
filt_coeffs = scipy.signal.firwin(
    1078 * 2 - 1, 20800, width=4200, pass_zero="lowpass", fs=sample_rate, scale=True
)
# filt_coeffs = scipy.signal.firls(
#    512 * 2 - 1,
#    [[0, 20000], [24000, sample_rate / 2]],
#    [[1, 1], [0, 0]],
#    fs=sample_rate,
# )
filt_coeffs = scipy.signal.minimum_phase(filt_coeffs)
print(f"samples: {len(filt_coeffs)}")
filt_coeffs = filt_coeffs[:1024]

with open("DAC_filter_coeffs.txt", "w") as f:
    for coeff in filt_coeffs:
        if coeff < 0:
            f.write(f"{((int(abs(coeff) * 2**21) ^ 0x3FFFF) + 1) & 0x3FFFF:05x}\n")
        else:
            f.write(f"{int(coeff * 2**21):05x}\n")

for i in range(len(filt_coeffs)):
    if filt_coeffs[i] < 0:
        filt_coeffs[i] = 2**-21 * float(-int(abs(filt_coeffs[i]) * 2**21))
    else:
        filt_coeffs[i] = 2**-21 * float(int(filt_coeffs[i] * 2**21))
w, H = scipy.signal.freqz(filt_coeffs, worN=10000)

# max_gain = 0
# for freq in [20, 80, 200, 1000, 8000, 14000, 20000]:
#    max_gain = max(max_gain, find_gain(freq, filt_coeffs))

w = w * sample_rate / (2 * np.pi)
max_gain = max(abs(H[find_nearest_index(w, 24000) :]))

index_60dB = None
for i in range(len(H)):
    if np.abs(H[i]) < 1e-3:
        index_60dB = i
        break
print(f"-60dB point: {w[index_60dB]:.8}Hz")
print(f"20kHz rolloff: {20 * math.log10(abs(H[find_nearest_index(w, 20000)])):.3}dB")
print(f"max alias gain: {max_gain:.4}  ({20 * math.log10(max_gain):.3}dB)")
print(
    f"max true peak: x{max_true_peak_gain(filt_coeffs):.4} (+{20 * math.log10(max_true_peak_gain(filt_coeffs)):.3}dB)"
)
print(f"delay: {peak_delay_microseconds(filt_coeffs):.4}us")


fig, (ax, ax2, ax3) = plt.subplots(3)
ax.loglog(w, np.abs(H))
ax.set_ybound(3e-6, 2)
ax.set_xbound(10000, sample_rate // 2)
ax2.semilogx(w, np.angle(H))
ax2.set_xbound(20, 20000)
ax3.plot(filt_coeffs)
plt.show()
