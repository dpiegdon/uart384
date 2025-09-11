
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

