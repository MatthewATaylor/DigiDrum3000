import pyaudio
import numpy as np
import math
import scipy.io
import wave


# Adapted from Freeverb
# https://github.com/sinshu/freeverb


class AP:
    def __init__(self, delay_samples, fb):
        self.delay_samples = delay_samples
        self.buf = np.zeros(delay_samples, dtype=np.int32)  # 18-bit
        self.buf_index = 0
        self.fb = fb

    def process(self, sample):
        # Max gain of 5/3 w/o clipping

        buf_out = self.buf[self.buf_index]
        out = np.int16(0)

        out_full = -np.int32(sample) + buf_out
        if out_full > 2**16-1:
            print('CLIP: AP out')
            out = 2**16-1
        elif out_full < -2**16:
            print('CLIP: AP out')
            out = -2**16
        else:
            out = out_full

        buf_next = np.int32(sample) + (buf_out >> self.fb)
        if buf_next > 2**17-1 or buf_next < -2**17:
            raise Exception('AP buf_next overflow')
        self.buf[self.buf_index] = buf_next

        self.buf_index += 1
        if self.buf_index >= self.delay_samples:
            self.buf_index = 0
        return out


class LBCF:
    def __init__(self, delay_samples, fb, damp):
        self.delay_samples = delay_samples
        self.buf = np.zeros(delay_samples, dtype=np.int32)  # 18-bit
        self.buf_index = 0
        self.fb = fb
        self.damp = damp
        self.lpf_out = np.int32(0)  # 25-bit

    def process(self, sample):
        # Max gain of 1 / (1-fb/1024) w/o clipping

        out = self.buf[self.buf_index]

        lpf_next = (
            (out<<10) +
            (self.lpf_out-out) * self.damp
        ) >> 10
        if lpf_next > 2**24-1:
            print('CLIP: LBCF lpf_out')
            self.lpf_out = 2**24-1
        elif lpf_next < -2**24:
            print('CLIP: LBCF lpf_out')
            self.lpf_out = -2**24
        else:
            self.lpf_out = lpf_next

        buf_next = (
            (np.int64(sample)<<13) +
            (np.int64(self.lpf_out) * (self.fb + (895<<3)))
        ) >> 13
        if buf_next > 2**17-1:
            print('CLIP: LBCF buf')
            self.buf[self.buf_index] = 2**17-1
        elif buf_next < -2**17:
            print('CLIP: LBCF buf')
            self.buf[self.buf_index] = -2**17
        else:
            self.buf[self.buf_index] = buf_next

        self.buf_index += 1
        if self.buf_index >= self.delay_samples:
            self.buf_index = 0
        return out


# User controls
POT_ROOM_SIZE = 700
POT_FEEDBACK = 500
POT_WET = 500
STEREO = True  # True if reverb is last in effects chain

SPREAD = 23
FB_AP = 1
DAMP = 1023-POT_FEEDBACK+1
FB_LBCF = POT_ROOM_SIZE

ap_delays = [
    556,
    441,
    341,
    225
]
aps_l = [AP(delay       , FB_AP) for delay in ap_delays]
aps_r = [AP(delay+SPREAD, FB_AP) for delay in ap_delays]
aps = [aps_l, aps_r]

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

    outs_lbcf = np.zeros(2, dtype=np.int32)  # 21-bit
    for i in range(len(lbcfs)):
        for lbcf in lbcfs[i]:
            outs_lbcf[i] += lbcf.process(sample)

    outs_ap = np.zeros(2, dtype=np.int32)  # 17-bit
    for i in range(len(aps)):
        outs_ap[i] = outs_lbcf[i] >> 4
        for ap in aps[i]:
            outs_ap[i] = ap.process(outs_ap[i])
        outs_ap[i] = outs_ap[i] >> 1

    return outs_ap  # 16-bit


SAMPLE_RATE = 44100
with wave.open('./media/resampled/sd.wav') as wav_file:
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
        y[2*i]   = xi
        y[2*i+1] = xi
    else:
        outs = process(xi)
        out_l = np.int32(outs[0])
        out_r = np.int32(outs[1])
        xi = np.int32(xi)
        if STEREO:
            y_l = (POT_WET * (out_l-xi) + (xi<<10)) >> 10
            y_r = (POT_WET * (out_r-xi) + (xi<<10)) >> 10
            y[2*i]   = y_l
            y[2*i+1] = y_r
        else:
            mono_out = (POT_WET * (((out_l + out_r)>>1)-xi) + (xi<<10)) >> 10
            y[2*i]   = mono_out
            y[2*i+1] = mono_out


stream.write(y.tobytes())
stream.close()
pa.terminate()

