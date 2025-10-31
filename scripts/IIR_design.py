import pyaudio
import numpy as np
import math
import scipy.io

CHUNK = 1024
# SAMPLE_RATE = 44100
SAMPLE_RATE = 48000
FREQ = 220
SAMPLES_PER_CYCLE = SAMPLE_RATE / FREQ
DURATION = 10
MAX = 2**15
# AMPLITUDE = int(MAX * 0.05)
AMPLITUDE = int(MAX * 0.2)
HALF_CYCLE = int(SAMPLES_PER_CYCLE/2)
PI = math.pi
T = 1 / SAMPLE_RATE

sq = [-AMPLITUDE] * HALF_CYCLE + [AMPLITUDE] * HALF_CYCLE
sq *= int(DURATION / (1 / FREQ))

# pa = pyaudio.PyAudio()
# stream = pa.open(
#     format=pyaudio.paInt16,
#     channels=1,
#     rate=44100,
#     output=True
# )

sq = np.array(sq, dtype=np.int16)
scipy.io.wavfile.write('./media/[sq].wav', SAMPLE_RATE, sq)
# prev_integ_in = 0  # sq[0]
# sq[0] = 0
# for i in range(1, len(sq)):
#     t = i * T
#     wc = 2 * PI * 10000/DURATION * t
#     integ_in = (sq[i] - sq[i-1])
#     sq[i] = sq[i-1] + 0.5 * (integ_in + prev_integ_in) * wc * T
#     prev_integ_in = integ_in

# stream.write(sq.tobytes())
# stream.close()
# pa.terminate()

