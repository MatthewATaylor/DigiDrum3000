import wave
import serial
import os

import numpy as np
import samplerate

samples = [
    'bd',
    'sd',
    't1',
    't2',
    't3',
    'hh_opened',
    'hh_closed',
    'hh_pedal',
    'cc',
    'rc',
]

SERIAL_PORTNAME = '/dev/ttyUSB1'
BAUD = 1500000
SAMPLE_RATE_IN = 48000
SAMPLE_RATE_OUT = 44100
SAMPLE_DIR = './media/'
RESAMPLED_DIR = SAMPLE_DIR+'resampled/'

def send_wav(ser=None):
    total_num_samples = 0
    for sample_name in samples:
        # Find wav file corresponding to sample name
        media_files = os.listdir(SAMPLE_DIR)
        sample_filename = None
        for media_file in media_files:
            if f'[{sample_name}]' in media_file:
                sample_filename = media_file
                break
        assert sample_filename is not None, f'No matching file for sample name: {sample_name}'

        filename = SAMPLE_DIR + sample_filename
        with wave.open(filename,"rb") as wav_file:
            # assert wav_file.getnchannels() == 2, 'Incorrect number of channels; re-format your WAV file!'
            nchannels = wav_file.getnchannels()
            assert wav_file.getsampwidth() == 2, 'Incorrect sample byte-width; re-format your WAV file!'
            assert wav_file.getframerate() == SAMPLE_RATE_IN, 'Incorrect sample rate; re-format your WAV file!'

            nframes = wav_file.getnframes()
            frames = wav_file.readframes(nframes)

            # Each frame consists of four bytes [LSB C1] [MSB C1] [LSB C2] [MSB C2]
            wav_samples = np.frombuffer(frames, dtype='<i2')  # 16-bit little endian byte order
            if nchannels == 2:
                wav_samples = wav_samples[0::2]  # Discard one channel
            wav_samples = samplerate.resample(wav_samples, SAMPLE_RATE_OUT/SAMPLE_RATE_IN)
            wav_samples = wav_samples.astype('<i2')

            # Pad samples with zeros (each DRAM read/write is 16*8=128 bits)
            wav_samples_remainder = len(wav_samples) % 8
            if wav_samples_remainder != 0:
                padding_samples = 8 - wav_samples_remainder
                padded_wav_samples = np.concatenate((
                    wav_samples,
                    np.zeros(padding_samples, dtype='<i2')
                ))
            else:
                padded_wav_samples = wav_samples

            # Save the resulting data to a new wav file
            with wave.open(f'{RESAMPLED_DIR+sample_name}.wav', 'wb') as wav_write_file:
                wav_write_file.setnchannels(1)
                wav_write_file.setsampwidth(2)
                wav_write_file.setframerate(SAMPLE_RATE_OUT)
                wav_write_file.writeframes(padded_wav_samples.tobytes())

            # num_samples <= 331161 -> store in 3 bytes
            num_samples = len(padded_wav_samples)
            total_num_samples += num_samples
            num_samples_bytes = num_samples.to_bytes(3, 'little')
            print(f'{sample_name} num samples: {num_samples} = hex:{num_samples_bytes.hex()}')

            # Prepend each set of sample data with the number of samples
            data_to_transmit = num_samples_bytes + padded_wav_samples.tobytes()

            print(padded_wav_samples[0:2])
            print(data_to_transmit[0:7].hex())

            if ser is not None:
                print(f'Sending sample {sample_name} over serial port...')
                ser.write(data_to_transmit)

            print()
    print(f'Total bits of sample data sent: {total_num_samples*16}')

if __name__ == '__main__':
    ser = None
    print(f'Opening serial port {SERIAL_PORTNAME}\n')
    ser = serial.Serial(SERIAL_PORTNAME, BAUD)
    send_wav(ser)

