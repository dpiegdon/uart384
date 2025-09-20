#!/usr/bin/python3
""" Script to receive raw, high quality entropy data from a serial device
(baudrate=1000000) and pass it into the kernel for immediate use. """

import fcntl
import struct
import sys
import time
import serial


RNDADDENTROPY = 0x40085203      # for X86; may differ for other arch!


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise ValueError("Please give serial device to read from.")

    with serial.Serial(sys.argv[1], 1000000, timeout=1) as ser:
        with open("/dev/random", "wb") as rng:
            count = 0
            t = time.time()
            errors = 0

            while True:
                data = ser.read(32)
                len_bytes = len(data)
                len_bits = len_bytes * 8
                payload = struct.pack(f"ii{len_bytes}s", len_bits, len_bytes, data)
                fcntl.ioctl(rng, RNDADDENTROPY, payload)

                count += len_bytes
                now = time.time()
                if now-t > 1:
                    avg = int(count / (now-t))
                    print(f"{avg}b/s     ", end="\r")
                    count = 0
                    t = now
                    if avg < 10:
                        errors += 1
                    else:
                        errors = 0
                    if errors > 3:
                        raise IOError("No more data arriving")
