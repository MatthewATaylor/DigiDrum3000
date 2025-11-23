import pyaudio
import numpy as np
import math
import scipy.io

CHUNK = 1024
SAMPLE_RATE = 44100
FREQ = 220
SAMPLES_PER_CYCLE = SAMPLE_RATE / FREQ
DURATION = 5
MAX = 2**15
AMPLITUDE = int(MAX * 0.05)
HALF_CYCLE = int(SAMPLES_PER_CYCLE/2)
PI = math.pi
T = 1 / SAMPLE_RATE

sq = [-AMPLITUDE] * HALF_CYCLE + [AMPLITUDE] * HALF_CYCLE
sq *= int(DURATION / (1 / FREQ))

pa = pyaudio.PyAudio()
stream = pa.open(
    format=pyaudio.paInt16,
    channels=1,
    rate=SAMPLE_RATE,
    output=True
)

x = np.array(sq, dtype=np.int16)
y = np.zeros(len(x), dtype=np.int16)
s = 0
for i in range(0, len(x)):
    t = i * T
    wc = 2 * PI * 10000/DURATION * t

    # Prewarped gain
    g = math.tan(wc * T / 2)

    # LPF with transposed trapezoidal integrator
    G = g / (1 + g)
    v = G * (x[i] - s)
    y[i] = v + s
    s = y[i] + v

stream.write(y.tobytes())
stream.close()
pa.terminate()

