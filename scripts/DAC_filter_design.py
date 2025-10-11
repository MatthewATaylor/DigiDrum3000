import numpy as np
import matplotlib.pyplot as plt
import scipy.signal

sample_rate = 8 * 44100

filt_coeffs = scipy.signal.firwin(
    1024 * 2 - 1, 22050, width=1025, pass_zero="lowpass", fs=sample_rate, scale=True
)
filt_coeffs = scipy.signal.minimum_phase(filt_coeffs)
filt_coeffs = filt_coeffs

with open("DAC_filter_coeffs.txt", "w") as f:
    for i in range(8):
        for coeff in filt_coeffs[i::8]:
            if coeff < 0:
                f.write(f"{int(abs(coeff) * 2**15) ^ 0xFFFF - 1:04x}\n")
            else:
                f.write(f"{int(coeff * 2**15):04x}\n")
        f.write("\n")

for i in range(len(filt_coeffs)):
    if filt_coeffs[i] < 0:
        filt_coeffs[i] = 2**-15 * float(-int(abs(filt_coeffs[i]) * 2**15))
    else:
        filt_coeffs[i] = 2**-15 * float(int(filt_coeffs[i] * 2**15))
w, H = scipy.signal.freqz(filt_coeffs, worN=10000)
# w, H = scipy.signal.dfreqresp(filt, n=10000)

w = w * sample_rate / (2 * np.pi)


fig, (ax, ax2) = plt.subplots(2)
ax.loglog(w, np.abs(H))
ax.set_ybound(1e-5, 2)
ax.set_xbound(10000, sample_rate // 2)
ax2.plot(filt_coeffs)
plt.show()
