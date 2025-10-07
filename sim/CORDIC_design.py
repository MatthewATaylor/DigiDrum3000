import math as math
import numpy as np

num_iterations = 20
theta_table = [math.atan2(1, 2**i) for i in range(num_iterations)]

output_mag = (2**16 - 1) / 2**16

x = 1.0
for i in range(num_iterations):
    x *= 1 / math.sqrt(1 + 2 ** (-2 * i))
x *= output_mag

x_fxp = np.int32(x * 2**30)
# after 10th [i = 9] value, can be calculated as 2**(30-i)-1
theta_fxp_table = [np.int32(theta * 2**30) for theta in theta_table[:10]]


def cordic_sin(angle: np.int32):
    """
    angle is 32 bit signed fixed point (-2 to 1.99...)
    angle in radians
    output is 16 bit signed fixed point (-1 to 0.999985)
    """
    x = x_fxp
    y = np.int32(0)
    i = np.uint8(0)
    for arc_tan in theta_table:
        arc_tan_fxp = np.int32(arc_tan * 2**30)
        clk_wise = angle < 0
        if clk_wise:
            angle += arc_tan_fxp
            x, y = x + (y >> i), y - (x >> i)
        else:
            angle -= arc_tan_fxp
            x, y = x - (y >> i), y + (x >> i)
        i += 1
    y_16b = ((y >> 14) + 1) >> 1
    # equivilent to simply inerpreting bottom 16 bits as new number
    if y_16b & 0x20000:
        y_16b = np.bitwise_not(np.int16(np.bitwise_not(y_16b)))
    else:
        y_16b = np.int16(y_16b)
    return y_16b


if __name__ == "__main__":
    # print values to be used in implimentation
    print("All values in hexadecimal unless specified otherwise")
    print(f"x_0: {x_fxp:X}   (signed 32'bXX.XXXXXX...)  ({float(x_fxp) * 2**-30:.9})")
    print("theta table (signed 32'bXX.XXXXX...):")
    for theta_fxp in theta_fxp_table:
        print(f"     {theta_fxp:08X}")

    # Print a table of computed sines and cosines, from -90° to +90°, in steps of 1°,
    # comparing against the available math routines.
    print("  x       sin(x)     diff. sine    incorrect (>0.5 lsb error)")
    for x in range(-90, 91, 1):
        sin_x = cordic_sin(np.int32(math.radians(x) * 2**30)) * 2**-15
        error = sin_x - output_mag * math.sin(math.radians(x))
        if abs(error) > 2**-16:
            print(f"{x:+05.1f}°  {sin_x:+.8f} ({error:+.8f}) XXXXXXXXXXXXXXXXXXXXXX")
        else:
            print(f"{x:+05.1f}°  {sin_x:+.8f} ({error:+.8f})")
