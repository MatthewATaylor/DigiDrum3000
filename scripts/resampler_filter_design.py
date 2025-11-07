import numpy as np
import matplotlib.pyplot as plt
import math

FS_IN = 2000
FS_OUT = 2000
SECONDS_PER_SAMPLE = FS_IN * 10e-9
F = 1000 #* FS_OUT / FS_IN
PI = math.pi
DELAY_SCALE = 2
M = 2**DELAY_SCALE


def farrow_delay_3(x, d):
    print(f'd={d}')
    y = []

    for i in range(len(x)):
        i_in = i
        x0 = x[i_in]
        x1 = 0
        x2 = 0
        x3 = 0

        if i_in >= 1:
            x1 = x[i_in-1]
        if i_in >= 2:
            x2 = x[i_in-2]
        if i_in >= 3:
            x3 = x[i_in-3]

        left_sum = x3 - (6*x2 - (3*x1 + 2*x0))
        top_sum_2 = int(d) * (3*(x1-x2) + (x3-x0))
        top_sum = int(d) * (M*3*(x0+x2) - M*6*x1 + top_sum_2)
        y.append((M**3 * 6*x1 + int(d) * (-M**2 * left_sum + top_sum)) // (6 * M**3))

    return y


def farrow_resample_3(x, fs_in, fs_out):
    n_resampled = []
    y = []

    d = 0

    out_len = int(len(x)*fs_out/fs_in)
    for i in range(out_len):
        # i_in = int(i * fs_in/fs_out)
        i_in = int(i * fs_in/fs_out)
        # if abs(d) < 1:
        #     i_in = i_in-1
        # if d < -0.99:
        #     i_in = i_in-1
        # if i_in >= len(x):
        #     i_in = len(x)-1
        x0 = x[i_in]
        x1 = 0
        x2 = 0
        x3 = 0

        if i_in >= 1:
            x1 = x[i_in-1]
        if i_in >= 2:
            x2 = x[i_in-2]
        if i_in >= 3:
            x3 = x[i_in-3]

        left_sum = x3 - (6*x2 - (3*x1 + 2*x0))
        top_sum_2 = int(d) * (3*(x1-x2) + (x3-x0))
        top_sum = int(d) * (M*3*(x0+x2) - M*6*x1 + top_sum_2)
        y.append((M**3 * 6*x1 + int(d) * (-M**2 * left_sum + top_sum)) // (6 * M**3))

        n_resampled.append(i*fs_in/fs_out)

        # quotient = int(M*fs_in/fs_out)
        quotient = int(M*fs_out/fs_in)
        d = (d - quotient) & (M-1)
        d = M*1
        print(d)


    return n_resampled, y


# n = np.arange(start=0, stop=int(3/F/SECONDS_PER_SAMPLE), step=1)
# x = 30000 * np.sin(2 * PI * F * n * SECONDS_PER_SAMPLE)
# 
# fig, ax = plt.subplots(figsize=(4,4))
# ax.scatter(n, x/30000, color='black')
# # for fs_in in range(569, 9088, 888):
# #     n_resampled, y = farrow_resample_3(x, fs_in, FS_OUT)
# #     ax.plot(n_resampled, y, marker='.')
# # n_resampled, y = farrow_resample_3(x, FS_IN, FS_OUT)
# # ax.plot(n_resampled, np.array(y)/30000, marker='.')
# # for d in np.arange(-4*M, 4*M, 8*M/10):
# for d in np.arange(-4, 4, 1):
#     y = farrow_delay_3(x, d)
#     ax.plot(n, np.array(y)/30000, marker='.')
# ax.set_xlabel('Sample Number')
# fig.tight_layout()
# plt.show()

n = range(10)
x = []
y = []
for i in n:
    ratio = 2272/5283
    x.append(ratio*i - int(ratio*i))

    div_delay_quotient = int(ratio * 2**8 * 2**4)
    delay_quotient_sum = div_delay_quotient * i
    delay_quotient_sum_shifted = int(delay_quotient_sum >> 8)
    delay = delay_quotient_sum_shifted & 0b1111
    y.append(delay/2**4)

print(x)
print(y)

