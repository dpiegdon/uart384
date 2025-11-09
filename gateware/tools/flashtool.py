#!/usr/bin/python3

# This file is part of the UART384 software & gateware
# (c) 2025 by David R. Piegdon <dgit@piegdon.de>
#
# The UART384 software & gateware is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# The UART384 software & gateware is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with the UART384 software & gateware. If not, see <https://www.gnu.org/licenses/>.

"""Commandeer SPI serial flash via UART tunnel"""

import argparse
import logging

from spi_device import SpiFlashDevice

if __name__ == "__main__":
    p = argparse.ArgumentParser("uart2spi", "Commandeer SPI serial flash via UART tunnel")
    p.add_argument("device", help="serial device to use for SPI tunnel")
    p.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="increase verbosity level",
    )
    p.add_argument(
        "-i", "--ident", action="store_true", help="verbosely identify flash chip"
    )
    p.add_argument(
        "-r",
        "--read",
        type=int,
        default=None,
        help="read this much from flash (starting at address 0)",
    )
    p.add_argument(
        "-o",
        "--out",
        type=argparse.FileType('wb'),
        default='-',
        help="store read flash data to this file (default stdout)",
    )
    p.add_argument(
        "-w",
        "--write",
        type=argparse.FileType('rb'),
        default=None,
        help="erase, then store this file to flash",
    )
    p.add_argument(
        "-W",
        "--dont-validate-write",
        action="store_true",
        help="don't read back writes to validate",
    )
    p.add_argument(
        "-E",
        "--dont-erase",
        action="store_true",
        help="don't erase before writing new data",
    )
    p.add_argument("-e", "--erase", action="store_true", help="erase flash")
    p.add_argument(
        "-x",
        "--extra",
        action="store_true",
        help='''read additional memory areas:
                        serial flash discoverable parameters (SFDP)
                        and security registers''',
    )
    p.add_argument(
        "-s", "--status", action="store_true", help="read and print status register"
    )
    p.add_argument(
        "-t",
        "--tc2050",
        action="store_true",
        help="target the TC2050 port J3 instead of the internal flash",
    )

    args = p.parse_args()
    none_selected = (
        not args.ident
        and not args.read
        and not args.write
        and not args.erase
        and not args.extra
        and not args.status
    )
    if none_selected:
        p.error("nothing to do")
    if args.erase and args.dont_erase:
        p.error("cannot erase and not erase")

    logging.basicConfig(
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        level=logging.DEBUG if args.verbose else logging.INFO,
    )

    dev = SpiFlashDevice(
        serialdevice=args.device,
        baudrate=500_000,
        internal=not args.tc2050,
        verbose=args.verbose > 1,
    )

    dev.release_from_deep_powerdown()
    if args.ident:
        print("REMS", dev.read_manufacturer_device_id())
        print("RDID", dev.read_identification())
        print("RUID", dev.read_unique_id())

    if args.extra:
        print("SFDP", dev.read_serial_flash_discoverable_parameters())
        print("RSR ", dev.read_security_registers())

    if args.status:
        print("STATUS lo", dev.read_status_lo())
        print("STATUS hi", dev.read_status_hi())

    if args.read is not None:
        args.out.write(dev.read_bytes(0, args.read))

    if args.erase or args.write is not None:
        if not args.dont_erase:
            dev.write_enable()
            print("CHIP ERASE.")
            dev.chip_erase()
            dev.await_write()

        if args.write is not None:
            print("WRITING...")
            data = args.write.read()
            pages = ((i, data[i : i + 256]) for i in range(0, len(data), 256))
            for adr, page in pages:
                print(f"0x{adr:x}")
                dev.write_enable()
                dev.page_program(adr, page)
                dev.await_write()
            if not args.dont_validate_write:
                print("VALIDATING...")
                readback = dev.read_bytes(0, len(data))
                if readback != data:
                    raise IOError("Mismatch between input and data on flash")
            print("...DONE")

        dev.write_disable()

    dev.deep_power_down()
