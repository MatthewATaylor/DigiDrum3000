import numpy as np
import matplotlib.pyplot as plt
import scipy.fftpack
import scipy.signal

# Number of samplepoints
N = 25000
# sample rate
R = 500000.0
# sample spacing
T = 1.0 / R
x = np.linspace(0.0, N * T, N)
y = scipy.signal.square(2000.0 * 2.0 * np.pi * x, 0.02)
low_pass = scipy.signal.butter(1, 35000, "lp", fs=R, output="sos")
low_pass2 = scipy.signal.butter(1, 25000, "lp", fs=R, output="sos")
low_pass3 = scipy.signal.butter(1, 20000, "lp", fs=R, output="sos")
# low_pass = scipy.signal.cheby1(1, 3, 25000, "lp", fs=R / 2, output="sos")
# low_pass = scipy.signal.bessel(1, 25000, "low", fs=R / 2, output="sos")
y2 = scipy.signal.sosfilt(low_pass, y)
y3 = scipy.signal.sosfilt(low_pass2, y)
y4 = scipy.signal.sosfilt(low_pass3, y)
yf = scipy.fftpack.fft(y)
y2f = scipy.fftpack.fft(y2)
y3f = scipy.fftpack.fft(y3)
y4f = scipy.fftpack.fft(y4)
xf = np.linspace(0.0, 1.0 / (2.0 * T), N // 2)

fig, ax = plt.subplots()
ax.semilogy(xf, 2.0 / N * np.abs(yf[: N // 2]))
ax.semilogy(xf, 2.0 / N * np.abs(y2f[: N // 2]))
ax.semilogy(xf, 2.0 / N * np.abs(y3f[: N // 2]))
ax.semilogy(xf, 2.0 / N * np.abs(y4f[: N // 2]))
ax.set_ybound(1 / 1000, 1)
plt.show()
