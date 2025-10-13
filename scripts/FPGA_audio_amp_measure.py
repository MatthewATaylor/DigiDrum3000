import math

###############################
# USE 2264 cycles per sample
###############################

# MATCHES 1st ORDER FILTER WITH -3dB CUTOFF AT 28kHz

for exp in range(16):
    for mant in range(4):
        mant <<= 2
        val = (0b10000 | mant) << exp
        sample_rate = 44100
        val *= 2**-13  # delta_angle
        freq = (sample_rate * val) / (2.0 * math.pi)
        if freq > 1000.0:
            print(f"{(mant << 4 | exp):08b} | {freq / 1000.0:>3.4}  kHz:")
        else:
            print(f"{(mant << 4 | exp):08b} | {freq:>3.4}  Hz:")


# MEASUREMENTS:
# 13.71 Hz:  -7 dB
# 17.14 Hz:  -6 dB
# 20.56 Hz:  -6 dB
# 23.99 Hz:  -6 dB
# 27.42 Hz:  -5 dB
# 34.27 Hz:  -5 dB
# 41.13 Hz:  -5 dB
# 47.98 Hz:  -5 dB
# 54.83 Hz:  -5 dB
# 68.54 Hz:  -5 dB
# 82.25 Hz:  -5 dB
# 95.97 Hz:  -5 dB
# 109.7 Hz:  -5 dB
# 137.1 Hz:  -5 dB
# 164.5 Hz:  -5 dB
# 191.9 Hz:  -5 dB
# 219.3 Hz:  -5 dB
# 274.2 Hz:  -5 dB
# 329.0 Hz:  -5 dB
# 383.8 Hz:  -5 dB
# 438.7 Hz:  -5 dB
# 548.3 Hz:  -5 dB
# 658.0 Hz:  -5 dB
# 767.7 Hz:  -5 dB
# 877.3 Hz:  -5 dB
# 1.097 kHz: -5 dB
# 1.316 kHz: -5 dB
# 1.535 kHz: -5 dB
# 1.755 kHz: -5 dB
# 2.193 kHz: -5 dB
# 2.632 kHz: -5 dB
# 3.071 kHz: -5 dB
# 3.509 kHz: -5 dB
# 4.387 kHz: -5 dB
# 5.264 kHz: -5 dB
# 6.141 kHz: -5 dB
# 7.019 kHz: -5 dB
# 8.773 kHz: -5 dB
# 10.53 kHz: -5 dB
# 12.28 kHz: -5 dB
# 14.04 kHz: -6 dB
# 17.55 kHz: -6 dB
# 21.06 kHz: -7 dB
# 24.57 kHz: -7 dB
# 28.07 kHz: -8 dB
# 35.09 kHz: -9 dB
# 42.11 kHz: -10dB
# 49.13 kHz: -11dB
# 56.15 kHz: -13dB
# 70.19 kHz: -15dB
# 84.22 kHz: -17dB
# 98.26 kHz: -18dB
