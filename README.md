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

SPI-over-UART tunnel
--------------------

`gateware/relay_spi.v`

Talk to an SPI device connected to the stick, via UART. SPI parameters
are configurable (speed, CPOL, CPHA, MSB first), and SPI transfers are
triggered via RTS line. This variant talks to the onboard program flash,
enabling re-flashing of the device via UART. But as it takes 50% of the
tiny FPGAs logic, it's not really feasible as a bootloader; this is just
an experiment in what is doable with the board.

See `gateware/tools/spi_device.py` for general SPI command abstraction,
and `gateware/tools/flashtool.py` as an example tool to work with the
onboard (or any other) serial flash.

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
