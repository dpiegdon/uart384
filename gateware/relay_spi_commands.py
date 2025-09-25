#!/usr/bin/python3
""" Script to talk to an SPI device via UART tunnel """

import argparse
import sys
import time

from spi_device import SerialFlashDevice


if __name__ == "__main__":
    p = argparse.ArgumentParser("uart2spi",
                                "Execute SPI commands via UART tunnel")
    p.add_argument("device")
    p.add_argument("-v", "--verbose", action="store_true",
                   help="enable verbose mode, dump full SPI xfers")
    p.add_argument("-i", "--ident", action="store_true",
                   help="verbosely identify flash chip")
    p.add_argument("-r", "--read", type=int, default=None,
                   help="read this much from flash (starting at address 0)")
    p.add_argument("-o", "--out", type=argparse.FileType('wb'), default='-',
                   help="store read data to this file (default stdout)")
    p.add_argument("-w", "--write", type=argparse.FileType('rb'), default=None,
                   help="erase, then store this file to flash")
    p.add_argument("-e", "--erase", action="store_true",
                   help="erase flash")
    p.add_argument("-s", "--status", action="store_true",
                   help="read and print status register")

    args = p.parse_args()

    dev = SerialFlashDevice(args.device, 500_000, verbose=args.verbose)

    dev.release_from_deep_powerdown()
    if args.ident:
        print("REMS", dev.read_manufacturer_device_id())
        print("RDID", dev.read_identification())
        print("RUID", dev.read_unique_id())
        print("SFDP", dev.read_serial_flash_discoverable_parameters(0, 128))

    if args.read is not None:
        args.out.write(dev.read_bytes(0, args.read))

    if args.status:
        print(dev.read_status_lo())
        print(dev.read_status_hi())

    if args.erase or args.write is not None:
        dev.write_enable()
        dev.chip_erase()
        dev.await_write()

        if args.write is not None:
            data = args.write.read()
            pages = ((i, data[i:i+256]) for i in range(0, len(data), 256))
            for adr, page in pages:
                print(f"0x{adr:x}")
                dev.write_enable()
                dev.page_program(adr, page)
                dev.await_write()

        dev.write_disable()

    dev.deep_power_down()
