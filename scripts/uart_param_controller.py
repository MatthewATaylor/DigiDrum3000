import rtmidi
import rtmidi.midiutil
import serial


# Create virtual MIDI port with:
# sudo modprobe snd_virmidi midi_devs=1


CONTROLLER_COUNT = 13
MIDI_CONTROLLER_MIN = 14


ser = None
ser = serial.Serial('/dev/ttyUSB1', 1500000)


def uart_write(ser, param_key, param_value):
    # param_key:    4-bit [0,   12]
    # param_value: 10-bit [0, 1023]
    byte1 = bytes([int((param_key << 2) + (param_value >> 8))])
    byte2 = bytes([int(param_value & 0b1111_1111)])
    if ser is not None:
        ser.write(byte1)
        ser.write(byte2)
    print(f'uart_write byte1={byte1.hex()}, byte2={byte2.hex()}')
    print(f'uart_write param_key={param_key}, param_value={param_value}')


rtmidi.midiutil.list_input_ports()
midi_in, midi_port_name = rtmidi.midiutil.open_midiinput()
print(f'Opened: {midi_port_name}')
print(f'API: {rtmidi.get_api_display_name(midi_in.get_current_api())}')


cc_msb_controller = None
cc_msb_value = None
while True:
    event = midi_in.get_message()
    if event is not None:
        msg, dt = event
        if msg[0] == 176:
            # CC message on channel 1
            if msg[1] >= MIDI_CONTROLLER_MIN and msg[1] < MIDI_CONTROLLER_MIN + CONTROLLER_COUNT:
                # MSB
                cc_msb_controller = msg[1]
                cc_msb_value = msg[2]
            elif cc_msb_controller is not None:
                if msg[1] == cc_msb_controller + 32:
                    # LSB
                    cc_lsb_value = msg[2]

                    # MSB and LSB are 7-bit
                    # Use together to form a 10-bit value
                    param_value = (cc_msb_value << 3) + (cc_lsb_value >> 4)

                    param_key = cc_msb_controller - MIDI_CONTROLLER_MIN

                    uart_write(ser, param_key, param_value)

