import random
import sys
import subprocess
import os
from pathlib import Path
import sys
from PIL import Image, ImageFilter
import math
from random import getrandbits


def clamp(val, floor, ceil):
    if val > ceil:
        return ceil
    if val < floor:
        return floor
    return val


def reverse(width, a):
    out = 0
    for i in range(width):
        out <<= 1
        out |= a & 1
        a >>= 1
    return out


def interleave(a, b):
    out = 0
    i = 0
    while a > 0 or b > 0:
        out |= (a & 1) << (2 * i)
        out |= (b & 1) << (2 * i + 1)
        a >>= 1
        b >>= 1
        i += 1
    return out


def M(width, i, j):
    return reverse(width, interleave(i ^ j, j))


def image_rend(intensity):
    test_image = Image.new("RGB", (128, 128))

    for i in range(128):
        for j in range(128):
            m_i = i % 16
            m_j = j % 16
            m = M(8, m_i, m_j)
            y = 64 + intensity / 2
            co = (95 - intensity / 4) * math.sin(
                ((i + j + intensity * 2) % 1024 + m / 256) * math.pi / 512
            )
            cg = (95 - intensity / 4) * math.sin(
                ((i - 2 * j + intensity * 2) % 1024 + m / 256) * math.pi / 512
            )
            r, g, b = (
                int(y + co - cg + m / 256),
                int(y + cg + m / 256),
                int(y - co - cg + m / 256),
            )
            r, g, b = (clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255))
            test_image.putpixel((i, j), (r, g, b))

    return test_image


if __name__ == "__main__":
    # set all inputs to 0
    images = []
    for i in range(255, -1, -2):
        image = image_rend(i)
        images.append(image)

    images[0].save(
        "sim_build/vid.gif",
        save_all=True,
        append_images=images[1:],
        optimize=False,
        duration=1000 / 60,
        loop=0,
    )

    subprocess.run(["pix", os.path.curdir + "/sim_build/vid.gif"])
