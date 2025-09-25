#!/usr/bin/python3
""" Script to talk to an SPI device via UART tunnel """

import sys
import time
import serial

class SpiDevice():
    """ Encapsulation of SPI channel over UART """
    def __init__(self, serialdevice:str,
                 cpol:bool, cpha:bool, msb_first:bool=True, cs_active_low:bool=True, clkdiv=4,
                 verbose=False):
        self.verbose = verbose
        self.dev = serial.Serial(sys.argv[1], 500000, timeout=.1, rtscts=False, dsrdtr=False)
        self.configure(cpol, cpha, msb_first, cs_active_low, clkdiv)

    def _rw1(self, outchar):
        """ send a single char and return a single response char """
        self.dev.write(outchar)
        response = self.dev.read(1)
        if self.verbose:
            print(f"{outchar} -> {response}")
        return response

    def _await_ri(self, value):
        """ await that RI line goes to @value """
        while self.dev.ri != value:
            time.sleep(0.001)

    def _await_dcd(self, value):
        """ await that DCD line goes to @value """
        while self.dev.cd != value:
            time.sleep(0.001)

    def configure(self, cpol:bool, cpha:bool, msb_first:bool, cs_active_low:bool, clkdiv):
        """ set SPI configuration """
        cfg = (  int(cs_active_low)<<7
               | int(cpol)<<6
               | int(cpha)<<5
               | int(msb_first)<<4
               | (clkdiv & 0xf))
        if self.verbose:
            print("cfg")
        self.dev.rts = False  # deassert CS, we're in configuration mode
        self._await_dcd(False)
        self._rw1(cfg.to_bytes())

    def transceive(self, data:bytes):
        """ do a full SPI transmit/receive cycle,
        send @data and return received result """
        if self.verbose:
            print("xmit")
        self.dev.rts = True  # assert CS
        self._await_dcd(True)
        result = b''
        for w in data:
            w = w.to_bytes()
            self._await_ri(False)
            r = self._rw1(w)
            result += r
        self.dev.rts = False  # deassert CS
        return result


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise ValueError("Please give serial device to read from.")

    dev = SpiDevice(sys.argv[1], False, False, verbose=False)

    # communicate with program flash on devboard:

    # release internal flash from deep power
    print("RDI", dev.transceive(b'\xab'))
    # read manufacturer ID/device id
    print("RDID", dev.transceive(b'\x90' + b'\x00'*5))
    # read identification string
    print("REMS", dev.transceive(b'\x9f' + b'\x00'*3))
    # read unique ID
    print("RUID", dev.transceive(b'\x4b' + b'\x00'*4 + b'\x00'*(128//8)))
    # write enable
    #print("WREN", dev.transceive(b'\x06'))
    # chip erase
    #print("CE", dev.transceive(b'\x60'))
