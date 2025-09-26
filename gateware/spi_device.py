#!/usr/bin/python3
""" Script to talk to an SPI device via UART tunnel """

import time
import serial
import struct


class SpiDevice():
    """ Encapsulation of SPI channel over UART """
    def __init__(self, serialdevice:str, baudrate:int,
                 cpol:bool, cpha:bool, msb_first:bool=True, cs_active_low:bool=True, clkdiv=4,
                 verbose:bool=False):
        self.verbose = verbose
        self.dev = serial.Serial(serialdevice, baudrate, timeout=.1, rtscts=False, dsrdtr=False)
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


class SerialFlashDevice(SpiDevice):
    """ Encapsulation of common commands of SPI serial flash chips """
    def __init__(self, serialdevice:str, baudrate:int, verbose:bool=False):
        super().__init__(serialdevice=serialdevice, baudrate=baudrate,
                         cpol=True, cpha=True, msb_first=True, cs_active_low=True, clkdiv=4,
                         verbose=verbose)

    _FUNCS = {# name             short cmdcode suffix-len  ret-start ret-len
              "read_status_lo": ("RDSRl",0x05, 1,          1,        1),
              "read_status_hi": ("RDSRh",0x35, 1,          1,        1),
              "write_enable":   ("WREN", 0x06, 0,          1,        0),
              "write_disable":  ("WRDI", 0x04, 0,          1,        0),
              "read_unique_id": ("RUID", 0x4b, 3+1+128//8, 1+3+1,    128//8),
              "chip_erase":     ("CE",   0x60, 0,          1,        0),
              "deep_power_down":("DP",   0xb9, 0,          1,        0),
              "release_from_deep_powerdown":
                                ("RDI",  0xab, 0,          1,        0),
              "read_manufacturer_device_id":
                                ("REMS", 0x90, 3+2,        4,        2),
              "read_identification":
                                ("RDID", 0x9f, 3,          1,        3),
             }

    _STATUSBITS = {#name   source attribute   bit
               "WIP":   ("read_status_lo", 0),
               "WEL":   ("read_status_lo", 1),
               "BP0":   ("read_status_lo", 2),
               "BP1":   ("read_status_lo", 3),
               "BP2":   ("read_status_lo", 4),
               "BP3":   ("read_status_lo", 5),
               "BP4":   ("read_status_lo", 6),
               "SRP0":  ("read_status_lo", 7),
               "SRP1":  ("read_status_hi", 0),
               "QE":    ("read_status_hi", 1),
               "LB":    ("read_status_hi", 2),
               # reserved: hi:3
               # reserved: hi:4
               "HPF":   ("read_status_hi", 5),
               "CMP":   ("read_status_hi", 6),
               "SUS":   ("read_status_hi", 7),
               }

    def __getattr__(self, attr):
        """ instantiate generic function from function-table """
        if attr in self._FUNCS:
            x = self._FUNCS[attr]
            def f():
                ret = self.transceive(x[1].to_bytes() + b'\x00' * x[2])
                return ret[x[3]:x[3]+x[4]]
            return f
        if attr in self._STATUSBITS:
            x = self._STATUSBITS[attr]
            (status,) = struct.unpack(">B", getattr(self, x[0])())
            return bool(status & (1 << x[1]))
        raise AttributeError(f"Unknown attribute: {attr}")

    @staticmethod
    def _to_adr(address:int):
        """ translate address to byte-format """
        return struct.pack(">I",address)[1:]

    def read_bytes(self, address:int, count:int):
        """ READ """
        return self.transceive(b'\x03' + self._to_adr(address) + b'\x00'*count)[4:]

    def read_serial_flash_discoverable_parameters(self, address:int=0, count:int=0x80):
        """ SFDP """
        return self.transceive(b'\x5a' + self._to_adr(address) + b'\x00'*count)[4:]

    def read_security_registers(self, address:int=0, count:int=0x400):
        """ RSR. only valid for 0x000..0x3ff? """
        return self.transceive(b'\x48' + self._to_adr(address) + b'\x00'*count)[4:]

    def page_program(self, address:int, data):
        """ PP """
        return self.transceive(b'\x02' + self._to_adr(address) + data)[4:]

    def await_write(self):
        """ await finishing of any write command """
        while self.WIP:
            time.sleep(0.02)
