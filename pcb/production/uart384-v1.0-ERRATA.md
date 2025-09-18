
v1.0 PCB Errata
===============

#1: Wrong SPI flash footprint
-----------------------------

[x] Fixed in main branch / v1.1~

Footprint for SPI flash (SOIC-8 150mil) mismatches partnumber AT25DF256-XMHN-T (TSSOP).

Valid replacement parts for SOIC-8 150mil footprint:

SPI flash (type 25) with

- 128KBit or more
- *150mil* SOIC-8 or SOP-8
- 3.3V

E.g.:

- AT25DF256-SSHN
- GD25QxxCTIG (for any number xx)

#2: SPI SS pullup missing
-------------------------

[x] Fixed in main branch / v1.1~

For some flash memory and some electrical circumstances the flash will need a pullup on the SS lines,
otherwise programming of the first bytes of every page can fail, resulting in the FPGA refusing the stored the bitstream.

Fix: add a 10K pull-up as can e.g. be seen in the ICEstick schematic.
