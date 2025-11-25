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
# s = 0
# for i in range(0, len(x)):
#     t = i * T
#     wc = 2 * PI * 10000/DURATION * t
# 
#     # Prewarped gain
#     g = math.tan(wc * T / 2)
# 
#     # LPF with transposed trapezoidal integrator
#     G = g / (1 + g)
#     v = G * (x[i] - s)
#     y[i] = v + s
#     s = y[i] + v


# 4-pole VA transistor ladder filter
# s = [0, 0, 0, 0]
# k = 2
# for i in range(0, len(x)):
#     t = i * T
#     wc = 2 * PI * 20000/DURATION * t
#     g = math.tan(wc * T / 2)
#     S = g**3 * s[0] + g**2 * s[1] + g * s[2] + s[3]
#     G = g**4
#     u = (x[i] - k*S) / (1 + k*G)
# 
#     for j in range(4):
#         G = g / (1 + g)
#         v = G * (u - s[j])
#         u = v + s[j]
#         s[j] = u + v
# 
#     y[i] = u


# Ladder filter but fixed point
s = [0, 0, 0, 0]
k = 900
for i in range(0, len(x)):
    pot_cutoff = int(1024 * i / len(x))
    g_x1024 = pot_cutoff

    S_x1024_4 = (
        s[0] * (g_x1024)**3 +  # 16 + 31 bits
        s[1] * (g_x1024)**2 +  # 26 + 21 bits
        s[2] * (g_x1024)    +  # 36 + 11 bits
        s[3]                   # 46      bits
    ) << 10
    G_x1024_4 = (g_x1024)**4

    # pot_quality / 256 = k
    kS = (k * S_x1024_4) >> 8
    kG = (k * G_x1024_4) >> 8

    u = ((int(x[i])<<40) - kS) // \
        ((1<<40)         + kG)

    # u = int(2**11 * math.tanh(u/2**11))
    if u > AMPLITUDE:
        u = AMPLITUDE
    elif u < -AMPLITUDE:
        u = -AMPLITUDE

    G_x1024 = (g_x1024<<10) // (1024 + g_x1024)

    for j in range(4):
        v = G_x1024 * (u - s[j])
        u = v + (int(s[j])<<10)
        s[j] = int(u + v) >> 10

    out = int(u) >> 40
    # if out > 2000:
    #     out = 2000
    # elif out < -2000:
    #     out = -2000
    y[i] = out


stream.write(y.tobytes())
stream.close()
pa.terminate()

