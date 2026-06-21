# DigiDrum3000

A real-time FPGA drum sampler, audio effects processor, and audio interface. Visit the [project webpage](https://matthewalantaylor.net/fpga-drums.html) for more information, including a selection of audio demos.

## Branches
- **nexys_a7:** Most recent revision of the project, compatibile with the Nexys A7 FPGA development board (AMD Artix-7). Includes Ethernet audio interface functionality and expression pedal control.
- **urbana:** Original project designed for the Real Digital Urbana FPGA development board (AMD Spartan-7). Developed as the final project for MIT's 6.2050 (Digital Systems Laboratory I). Includes audio visualization functionality.

## Feature Overview (nexys\_a7)
- Drum set audio samples (16-bit, 48 ksps) loaded over UART and stored in DRAM
- MIDI interface for audio sample triggering via an electronic drum set
- Audio effects
  - Pitch shift (resampling)
  - Delay
  - Stereo reverb (Freeverb)
  - Resonant low-pass filter (4-pole transistor ladder filter model)
  - Distortion (tanh)
  - Bit crush
- PCB with patch bay and knobs for controlling effects parameters
- PCB with line-level audio output (TAD5242 DAC) and expression pedal inputs
- UART interface for effects parameter automation in a digital audio workstation
- Audio recording over Ethernet with up to 12 channels of 16-bit samples at 48 ksps.
- 1.5 ms maximum audio latency (from received MIDI message to audio output)
- Extensive testing with cocotb

## Operation
1. Build
```
vivado -mode batch -source build.tcl -tclargs outputDir=<OUTPUT DIRECTORY>
```
2. Program
```
openFPGALoader -b <BOARD_NAME> <OUTPUT DIRECTORY>/final.bit
```
3. Load audio samples
```
python scripts/send_wav.py
```
4. (Optional) Run UART effects parameter controller. Create a new virtual MIDI port if one does not already exist.
```
python scripts/uart_param_controller.py
```
5. (Optional) Run Ethernet audio receiver (requires Linux with PipeWire).
```
cd ethernet_audio_interface
make
./build/ethernet_audio_interface
```

