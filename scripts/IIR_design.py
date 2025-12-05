import pyaudio
import numpy as np
import math
import scipy.io
import samplerate
import matplotlib.pyplot as plt

SOFT_CLIP = 1
CHUNK = 1024
SAMPLE_RATE = int(4/(2272*10e-9))
FREQ = 440
SAMPLES_PER_CYCLE = SAMPLE_RATE / FREQ
DURATION = 5#1/FREQ * 3
HALF_CYCLE = int(SAMPLES_PER_CYCLE/2)
PI = math.pi
T = 1 / SAMPLE_RATE

sq = [-2**15] * HALF_CYCLE + [2**15-1] * HALF_CYCLE
sq *= int(DURATION / (1 / FREQ))

pa = pyaudio.PyAudio()
stream = pa.open(
    format=pyaudio.paInt16,
    channels=1,
    rate=int(SAMPLE_RATE/4),
    output=True
)

x = np.array(sq, dtype=np.int16)

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


def ladder_fixed(x):
    # Ladder filter but fixed point
    y = np.zeros(len(x), dtype=np.int16)
    s = [0, 0, 0, 0]
    k = 800
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
        if u > 2**15-1:
            print('CLIP: u')
            u = 2**15-1
        elif u < -2**15:
            print('CLIP: u')
            u = -2**15

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
    return y


def ladder_fixed_small(x):
    # Ladder filter but fixed point
    # Maintain smaller int sizes
    y = np.zeros(len(x), dtype=np.int16)
    s = [0, 0, 0, 0]
    k = 750
    for i in range(0, len(x)):
        pot_cutoff = int(1024 * i / len(x))
        g_x1024 = pot_cutoff

        S_x1024_4 = (
            (s[0]<<10) * (g_x1024)**3 +  # 26 + 30 bits
            (s[1]<<20) * (g_x1024)**2 +  # 36 + 20 bits
            (s[2]<<30) * (g_x1024)    +  # 46 + 10 bits
            (s[3]<<40)                   # 56      bits
        )  # 58 bits total

        if S_x1024_4 > 2**57-1 or S_x1024_4 < -2**57:
            raise Exception('OVERFLOW: S_x1024_4')

        G_x1024_4 = (g_x1024)**4

        # pot_quality / 256 = k
        kS = (k * S_x1024_4) >> 8
        kG = (k * G_x1024_4) >> 8

        u = ((int(x[i])<<40) - kS) // \
            ((1<<40)         + kG)

        # u = int(2**11 * math.tanh(u/2**11))
        if u > 2**15-1:
            print('CLIP: u')
            u = 2**15-1
        elif u < -2**15:
            print('CLIP: u')
            u = -2**15

        G_x1024 = (g_x1024<<10) // (1024 + g_x1024)

        for j in range(4):
            v_x1024 = G_x1024 * (u - s[j])
            u_x1024 = v_x1024 + (int(s[j])<<10)
            s[j] = int(u_x1024 + v_x1024) >> 10
            if s[j] > 2**15-1 or s[j] < -2**15:
                raise Exception('OVERFLOW: s[j]')
            u = u_x1024 >> 10
            if u > 2**15-1 or u < -2**15:
                raise Exception('OVERFLOW: u')

        # if out > 2000:
        #     out = 2000
        # elif out < -2000:
        #     out = -2000
        y[i] = u
    return y


def ladder_float_x4(x, pot_cutoff, pot_quality):
    # 4-pole VA transistor ladder filter (floating point)
    y = np.zeros(len(x), dtype=np.int16)
    s = [0, 0, 0, 0]
    k = pot_quality/256
    for i in range(0, len(x)):
        # t = i * T
        # wc = 2 * PI * 20000/DURATION * t
        # g = math.tan(wc * T / 2)
        g = pot_cutoff/1024/4
        g = i/len(x)/4
        S = g**3 * s[0] + g**2 * s[1] + g * s[2] + s[3]
        G = g**4
        u = (x[i] - k*S) / (1 + k*G)
        u = 2**15*math.tanh(3*u/2**15)
        # if u > 2**15-1:
        #     u = 2**15-1
        # elif u < -2**15:
        #     u = -2**15
        G = g / (1 + g)
        for j in range(4):
            v = G * (u - s[j])
            u = v + s[j]
            s[j] = u + v
        y[i] = u
    return y


def ladder_fixed_x4(x, pot_cutoff, pot_quality):
    # Ladder filter but fixed point, oversampled
    y = np.zeros(len(x), dtype=np.int16)
    s = [0, 0, 0, 0]
    k = pot_quality
    for i in range(0, len(x)):
        #pot_cutoff = int(1024 * i / len(x))
        #g_lsh12 = int(1024*math.tan(pot_cutoff/1024))  # g should be in [0, 0.25]
        g_lsh12 = pot_cutoff

        S_lsh28 = np.int64()
        S_lsh28 = (
            (s[0]>> 8) * (g_lsh12)**3 +  # 8  + 30 bits
            (s[1]<< 4) * (g_lsh12)**2 +  # 20 + 20 bits
            (s[2]<<16) * (g_lsh12)    +  # 32 + 10 bits
            (s[3]<<28)                   # 44      bits
        )  # 45 bits total

        if S_lsh28 > 2**44-1 or S_lsh28 < -2**44:
            raise Exception('OVERFLOW: S_lsh28')

        g4_lsh28 = ((g_lsh12)**4) >> 20

        # pot_quality / 256 = k
        kS_lsh36 = k * S_lsh28
        # kg_lsh36 = k * g4_lsh28

        # u = ((int(x[i])<<36) - kS_lsh36) // \
        #     (        (1<<36) + kg_lsh36)

        u = (int(x[i]) - int(kS_lsh36>>36))
        u = int(2**15 * math.tanh(3*u/2**15))
        # if u > 2**15-1:
        #     # print('CLIP: u')
        #     u = 2**15-1
        # elif u < -2**15:
        #     # print('CLIP: u')
        #     u = -2**15

        G_lsh12 = (g_lsh12<<12) // ((1<<12) + g_lsh12)

        for j in range(4):
            v_lsh12 = G_lsh12 * (u - s[j])
            u_lsh12 = v_lsh12 + (int(s[j])<<12)
            s[j] = int(u_lsh12 + v_lsh12) >> 12
            if s[j] > 2**15-1 or s[j] < -2**15:
                raise Exception('OVERFLOW: s[j]')
            u = u_lsh12 >> 12
            if u > 2**15-1 or u < -2**15:
                raise Exception('OVERFLOW: u')
        y[i] = u
    return y


def ladder_fixed_x4_opt(x, pot_cutoff, pot_quality):
    # Ladder filter but fixed point, oversampled
    y = np.zeros(len(x), dtype=np.int16)
    s = [0, 0, 0, 0]
    k = pot_quality
    for i in range(0, len(x)):
        pot_cutoff = int(1024 * i / len(x))
        #g_lsh12 = int(1024*math.tan(pot_cutoff/1024))  # g should be in [0, 0.25]
        g_lsh12 = pot_cutoff

        S = np.int64()
        S = (
            (s[0]>>12) * (g_lsh12)**3 +  # 4  + 30 bits
            (s[1]    ) * (g_lsh12)**2 +  # 16 + 20 bits
            (s[2]<<12) * (g_lsh12)    +  # 28 + 10 bits
            (s[3]<<24)                   # 40      bits
        ) # 41 bits total
        S_shift = int(S>>32)  # 9 bits

        if S_shift > 2**8-1 or S_shift < -2**8:
            raise Exception('OVERFLOW: S')

        # pot_quality / 256 = k
        kS = k * S_shift  # 19 bits
        u = int(x[i]) - kS
        u = int(2**15 * math.tanh(3*u/2**15))

        G_lsh12 = (g_lsh12<<12) // ((1<<12) + g_lsh12)

        for j in range(4):
            v_lsh12 = G_lsh12 * (u - s[j])
            u_lsh12 = v_lsh12 + (int(s[j])<<12)
            s[j] = int(u_lsh12 + v_lsh12) >> 12
            if s[j] > 2**15-1 or s[j] < -2**15:
                raise Exception('OVERFLOW: s[j]')
            u = u_lsh12 >> 12
            if u > 2**15-1 or u < -2**15:
                raise Exception('OVERFLOW: u')
        y[i] = u
    return y


# Below: x4 functions modified for simulation

def filter_step_float(x, s, pot_cutoff, pot_quality):
    k = pot_quality/256
    g = pot_cutoff/1024/4
    S = g**3 * s[0] + g**2 * s[1] + g * s[2] + s[3]
    G = g**4
    u = (x - k*S) / (1 + k*G)
    if not SOFT_CLIP:
        if u > 2**15-1:
            u = 2**15-1
        elif u < -2**15:
            u = -2**15
    else:
        u = 2**15*math.tanh(3*u/2**15)
    G = g / (1 + g)
    for j in range(4):
        v = G * (u - s[j])
        u = v + s[j]
        s[j] = u + v
    return u, s


def filter_step(x, s, pot_cutoff, pot_quality):
    k = np.int64(pot_quality)
    g_lsh12 = np.int64(pot_cutoff)

    for i in range(4):
        if i == 0:
            S = np.int64(s[3]<<24)
        elif i == 1:
            S += (s[2]<<12) * g_lsh12
        elif i == 2:
            S += s[1] * g_lsh12**2
        elif i == 3:
            S += (s[0]>>12) * g_lsh12**3

    S_shift = np.int64(S>>32)  # 9 bits

    if S_shift > 2**8-1 or S_shift < -2**8:
        raise Exception('OVERFLOW: S')

    # pot_quality / 256 = k
    kS = k * S_shift  # 19 bits
    u = int(x) - kS
    if not SOFT_CLIP:
        if u > 2**15-1:
            u = 2**15-1
        elif u < -2**15:
            u = -2**15
    else:
        u = int(2**15 * math.tanh(3*u/2**15))
    u = np.int64(u)
    G_lsh12 = np.int64()
    G_lsh12 = (g_lsh12<<12) // (np.int64(1<<12) + g_lsh12)

    for j in range(4):
        v_lsh12 = G_lsh12 * (u - s[j])
        u_lsh12 = v_lsh12 + (int(s[j])<<12)

        s[j] = (u_lsh12 + v_lsh12) >> 12
        if s[j] > 2**15-1 or s[j] < -2**15:
            raise Exception('OVERFLOW: s[j]')
        s[j] = np.int64(s[j])

        u = u_lsh12 >> 12
        if u > 2**15-1 or u < -2**15:
            raise Exception('OVERFLOW: u')

    return u, s


PLOT = False
POT_CUTOFF = 500
POT_QUALITY = 1023
x = np.array(x, dtype=np.int16)
n = np.linspace(0, len(x)-1, len(x))

s = [0,0,0,0]
s_float = [0,0,0,0]
y_fixed = np.zeros(len(x), dtype=np.int16)
y_float = np.zeros(len(x), dtype=np.int16)


for i, sample in enumerate(x):
    pot_cutoff = int(1024 * i/len(x))
    y_float[i], s_float = filter_step_float(sample, s_float, pot_cutoff, POT_QUALITY)
    y_fixed[i], s = filter_step(sample, s, pot_cutoff, POT_QUALITY)

if PLOT:
    fig, ax = plt.subplots()
    ax.scatter(n, x, color='black', label='Input')
    ax.plot(n, y_float, marker='.', label='Output (Floating Point)')
    ax.plot(n, y_fixed, marker='.', label='Output (Fixed Point)')
    ax.set_xlabel('Sample Number')
    ax.set_ylabel('Sample Value')
    ax.legend()
    fig.tight_layout()
    plt.show()
else:
    y = samplerate.resample(y_float, 1/4)
    y = np.array(y*0.1, dtype=np.int16)  # Save our ears
    stream.write(y.tobytes())
stream.close()
pa.terminate()

