#!/usr/bin/python3
""" Commandeer SPI serial flash via UART tunnel """

import argparse

from spi_device import SerialFlashDevice


if __name__ == "__main__":
    p = argparse.ArgumentParser("uart2spi",
                                "Commandeer SPI serial flash via UART tunnel")
    p.add_argument("device",
                   help="serial device to use for SPI tunnel")
    p.add_argument("-v", "--verbose",
                   action="store_true",
                   help="enable verbose mode, dump full SPI xfers")
    p.add_argument("-i", "--ident",
                   action="store_true",
                   help="verbosely identify flash chip")
    p.add_argument("-r", "--read",
                   type=int, default=None,
                   help="read this much from flash (starting at address 0)")
    p.add_argument("-o", "--out",
                   type=argparse.FileType('wb'), default='-',
                   help="store read flash data to this file (default stdout)")
    p.add_argument("-w", "--write",
                   type=argparse.FileType('rb'), default=None,
                   help="erase, then store this file to flash")
    p.add_argument("-W", "--dont-validate-write",
                   action="store_true",
                   help="don't read back writes to validate")
    p.add_argument("-E", "--dont-erase",
                   action="store_true",
                   help="don't erase before writing new data")
    p.add_argument("-e", "--erase",
                   action="store_true",
                   help="erase flash")
    p.add_argument("-x", "--extra",
                   action="store_true",
                   help='''read additional memory areas:
                        serial flash discoverable parameters (SFDP)
                        and security registers''')
    p.add_argument("-s", "--status",
                   action="store_true",
                   help="read and print status register")

    args = p.parse_args()
    none_selected = (    not args.ident and not args.read
                     and not args.write and not args.erase
                     and not args.extra and not args.status)
    if none_selected:
        p.error("nothing to do")
    if args.erase and args.dont_erase:
        p.error("cannot erase and not erase")

    dev = SerialFlashDevice(args.device, 500_000, verbose=args.verbose)

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
            pages = ((i, data[i:i+256]) for i in range(0, len(data), 256))
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
