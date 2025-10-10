import numpy as np
import matplotlib.pyplot as plt
import scipy.fftpack
import scipy.signal

sample_rate = 16 * 128 * 44100
tf = scipy.signal.TransferFunction([1, -1], [1], dt=1 / sample_rate)
w, H = scipy.signal.dfreqresp(tf, n=10000)

w = w * sample_rate / (2 * np.pi)

fig, ax = plt.subplots()
ax.loglog(w, np.abs(H.real + 1j * H.imag))
ax.set_ybound(1e-7, 10)
plt.show()
