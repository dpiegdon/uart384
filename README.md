<!-- vim: tw=72 fo+=a
-->

Lattice LP384 USB/UART stick
============================

<div>
	<img width="75%" alt="PCBRendering"
     src="https://github.com/dpiegdon/uart384/blob/main/docs/uart384_pcb_rendering2.png"/>
</div>

This is a mini-devboard for the Lattice iCE40LP384, the *BEST* FPGA ever!

Features:
- USB-stick form-factor
- USB is connected to Silabs CP2102 USB-to-UART bridge
- Lattice LP384 with connections:
  - UART
  - 2 LEDs
  - 1 push-button
  - 8 GPIOs on pinheader
  - 32M oscillator
- small flash for bitstream
- TC2050 connector (bottom side) for programming the flash

NOTE: device is not programmable via USB


Gateware
========

"Why?" do you ask?

Mostly for fun and training; there are a few gateware options available in this repository:

Entropy generator
-----------------

I want a mini board that generates cryptographically sound entropy
that can be used to enhance system entropy on linux.

UART pass-through
-----------------

A simple example that only passes UART signals along to the GPIO header
and shows changes on RX/TX lines on the LEDs (with some timeout).
