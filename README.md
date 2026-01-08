# DigiDrum3000

A real-time FPGA drum sampler, audio effects processor, and audio visualizer.

## Branches
- **main:** Original project designed for the Real Digital Urbana FPGA development board (AMD Spartan-7). Developed as the final project for MIT's 6.2050 (Digital Systems Laboratory I).
- **nexys4ddr:** Modified for compatibility with the Nexys 4 DDR FPGA development board (AMD Artix-7). Does not include audio visualization functionality.

## Feature Overview
- Drum set audio samples (16-bit, 44.1 ksps) loaded over UART and stored in DRAM
- MIDI interface for audio sample triggering via an electronic drum set
- Audio/video effects
  - Pitch shift
  - Delay
  - Stereo reverb
  - Resonant low-pass filter
  - Distortion
  - Bit crush
- Second order delta-sigma modulator
- PCB with patch bay and knobs for controlling effects parameters
- UART interface for effects parameter automation in a digital audio workstation
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

