<!-- vim: tw=72 fo+=a
-->

UART384 - FPGA devboard & USB-stick
===================================

<div>
	<img width="49%" alt="PCB-Rendering"
     src="https://github.com/dpiegdon/uart384/blob/main/docs/uart384_pcb_rendering2.png"/>
	<img width="49%" alt="PCB-Photo"
     src="https://github.com/dpiegdon/uart384/blob/main/docs/uart384_pcb_photo.jpg"/>
</div>

This is a mini-devboard for the Lattice iCE40LP384, the *BEST* 🔍 FPGA
ever!

Features:
- USB-stick form-factor
- USB is connected to Silabs CP2102 USB-to-UART bridge
- Tiny Lattice iCE40LP384 with connections:
  - 384 LUTs/FFs
  - UART
  - 2 LEDs
  - 1 push-button
  - 8 GPIOs on pinheader
  - 32MHz oscillator
- small flash for bitstream
- TC2050 connector (bottom side) for programming the flash

NOTE: device is not programmable via USB


Gateware
========

"Why?", you ask?

Mostly for fun and training; there are a few gateware options available in this repository:

Entropy generator
-----------------

`gateware/entropy_generator.v`

High quality entropy source using metastability from ringoscillators fed
into the spongent hash algorithm. 

This is one of the original reasons this board was created for: I wanted
a USB stick that generates cryptographically sound entropy that can be
used to enhance system entropy on linux.

`gateware/tools/seedrng.py` can be used to receive the entropy and
inject it directly into the kernel entropy pool.

SPI and GPIO over UART tunnel
-----------------------------

`gateware/relay_spi.v`

This variant allows complex muxing of SPI lines from an SPI master core
to all GPIO1..8 pins, as well as the internal program flash. All these
pins can also be muxed as GPIO input or output and controlled/sampled.
All that via a simple UART protocol.

This gives full control of inputs and outputs, as well as efficient SPI
communication via SPI core, in any configuration. The SPI core is used
for SPI transfer by pulling RTS down, then CS is automatically pulled
down and data is seemlessly interchanged between SPI and UART.

This e.g. allows reprogramming the internal flash, or external SPI
devices, including Lattice iCE40 FPGAs if GPIOs are used to trigger
their CRESET. Since CDONE can also be sampled, this also allows
programming any iCE40 FPGA in slave mode, fully replacing any other
needed programming board to flash/program a Lattice iCE40 FPGA. Note
that the FPGA is pretty much full, no further features will be added to
this gateware.

See `gateware/tools/spi_device.py` for general SPI command abstraction,
and `gateware/tools/flashtool.py` and `gateware/tools/spi_device.py` as
an example client to work with the onboard (or any other) serial flash.

Ring oscillator entropy generator
---------------------------------

`gateware/ring_noise.v`

Low quality entropy generator using metastability from ringoscillators
fed into a linear feedback shift register.

UART pass-through
-----------------

`gateware/uart_passthrough.v`

A simple example that only passes UART signals along to the GPIO header
and shows changes on RX/TX lines on the LEDs (with some timeout).

Variable delay ring oscillator
------------------------------

`gateware/variable_ringoscillator.v`

Experiments with a ringoscillator with a reconfigurable delay-line.
Delay can be changed at runtime via UART.

License
=======

The hardware (Schematic, PCB) is licensed under CERN-OHL-W v2.
See `cern_ohl_w_v2.txt`.

The software is licensed under LGPL v2.0, unless specified otherwise
in a subrepository. See `LGPLv2.0.txt`.
