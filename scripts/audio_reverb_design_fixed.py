import pyaudio
import numpy as np
import math
import scipy.io
import wave


class AP:
    def __init__(self, delay_samples, fb):
        self.delay_samples = delay_samples
        self.buf = np.zeros(delay_samples)
        self.buf_index = 0
        self.fb = fb

    def process(self, sample):
        buf_out = self.buf[self.buf_index]
        out = -sample + buf_out
        self.buf[self.buf_index] = sample + (buf_out * self.fb)
        self.buf_index += 1
        if self.buf_index >= self.delay_samples:
            self.buf_index = 0
        return out


class LBCF:
    def __init__(self, delay_samples, fb, damp):
        self.delay_samples = delay_samples
        self.buf = np.zeros(delay_samples)
        self.buf_index = 0
        self.fb = fb
        self.damp = damp
        self.lpf_out = 0

    def process(self, sample):
        out = self.buf[self.buf_index]
        self.lpf_out = out * (1-self.damp) + self.lpf_out * self.damp
        self.buf[self.buf_index] = sample + self.lpf_out * self.fb
        self.buf_index += 1
        if self.buf_index >= self.delay_samples:
            self.buf_index = 0
        return out


SPREAD = 23

FB_AP = 0.5
ap_delays = [
    556,
    441,
    341,
    225
]
aps_l = [AP(delay       , FB_AP) for delay in ap_delays]
aps_r = [AP(delay+SPREAD, FB_AP) for delay in ap_delays]
aps = [aps_l, aps_r]

DAMP = 0.5
FB_LBCF = 0.99
lbcf_delays = [
    1116,
    1188,
    1277,
    1356,
    1422,
    1491,
    1557,
    1617
]
lbcfs_l = [LBCF(delay       , FB_LBCF, DAMP) for delay in lbcf_delays]
lbcfs_r = [LBCF(delay+SPREAD, FB_LBCF, DAMP) for delay in lbcf_delays]
lbcfs = [lbcfs_l, lbcfs_r]


def process(sample):
    # Process sample in separate L/R channels

    outs = [0,0]

    for i in range(len(lbcfs)):
        for lbcf in lbcfs[i]:
            outs[i] += lbcf.process(sample)

    for i in range(len(aps)):
        for ap in aps[i]:
            outs[i] = ap.process(outs[i])

    return outs


SAMPLE_RATE = 44100
with wave.open('./media/resampled/hh_opened.wav') as wav_file:
    assert wav_file.getframerate() == SAMPLE_RATE
    nframes = wav_file.getnframes()
    frames = wav_file.readframes(nframes)
    x = np.frombuffer(frames, dtype='<i2')


pa = pyaudio.PyAudio()
stream = pa.open(
    format=pyaudio.paInt16,
    channels=2,
    rate=SAMPLE_RATE,
    output=True
)


y = np.zeros(8*len(x), dtype=np.int16)
for i in range(4*len(x)):
    xi = x[i%len(x)]
    if i < 2*len(x):
        y[2*i]   = xi*0.5
        y[2*i+1] = xi*0.5
    else:
        outs = process(xi * 0.015)
        out_l = outs[0]
        out_r = outs[1]
        wet = 0.5
        mono = False
        if mono:
            mono_out = wet * (out_l + out_r) + (1-wet) * xi
            y[2*i]   = mono_out
            y[2*i+1] = mono_out
        else:
            y[2*i]   = wet * 2*out_l + (1-wet) * xi
            y[2*i+1] = wet * 2*out_r + (1-wet) * xi


stream.write(y.tobytes())
stream.close()
pa.terminate()

