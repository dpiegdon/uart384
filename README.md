<!-- vim: tw=72 fo+=a
-->

Lattice LP384 USB/UART stick
============================

<div>
	<img width="75%" alt="PCBRendering"
	 src="https://github.com/dpiegdon/uart384/blob/main/docs/uart384_pcb_rendering.jpg"/>
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
--------

"Why?" do you ask?

Mostly for fun and training, but also because I want a mini board that
generates cryptographically sound entropy.

The FPGA can be used in a feedback-loop configuration such that a
metastable state is used as entropy source. This entropy is used to feed
a linear feedback shift register, and every so-and-so bits a character
of random data from that LFSR is output via UART to the host computer.

On linux systems you can improve your system entropy with that. One
simple variant is:

```
socat file:/dev/ttyACM0,b1000000,ignoreeof,cs8,raw STDOUT | sudo tee /dev/random | pv > /dev/null
```
