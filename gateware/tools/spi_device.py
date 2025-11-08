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

""" Script to talk to an SPI device via UART tunnel """

from collections.abc import Callable
import enum
import time
import struct

import serial


class Register(enum.Enum):
    """Registers that can be addressed"""
    MUX_PAD_A2_A1 = 0x1
    MUX_PAD_A4_A3 = 0x2
    MUX_PAD_A6_A5 = 0x3
    MUX_PAD_A8_A7 = 0x4
    MUX_PAD_B2_B1 = 0x5
    MUX_PAD_B4_B3 = 0x6
    GPIO_WRITE_A  = 0x8
    GPIO_WRITE_B  = 0x9
    GPIO_READ_A   = 0xA
    GPIO_READ_B   = 0xB
    SPI_CTRL      = 0xC
    VERSION       = 0xF


class Pad(enum.Enum):
    """List of all available IO Pads"""
    A1 = 1
    A2 = 2
    A3 = 3
    A4 = 4
    A5 = 5
    A6 = 6
    A7 = 7
    A8 = 8
    B1 = 9
    B2 = 10
    B3 = 11
    B4 = 12

    @property
    def bank_a(self) -> bool:
        """check if pin is in bank a"""
        return self in (self.A1, self.A2, self.A3, self.A4,
                        self.A5, self.A6, self.A7, self.A8)

    @property
    def bank_b(self) -> bool:
        """check if pin is in bank b"""
        return self in (self.B1, self.B2, self.B3, self.B4)

    @property
    def pin_number(self) -> int:
        """return pin number within this bank"""
        if self.bank_a:
            return self.value
        if self.bank_b:
            return self.value - self.B1.value + 1
        raise ValueError()


class PadFunc(enum.Enum):
    """List of all existing functions any pad can be muxed to"""
    GPIO_IN       = 0
    GPIO_OUT      = 1
    SPI_SS        = 2
    SPI_SCK       = 3
    SPI_SDO       = 4
    SPI_SDI       = 5
    TUNNEL_ACTIVE = 6
    SPI_XFER_IDLE = 7
    HIGH          = 8


SPI_FUNCTIONS = (PadFunc.SPI_SS, PadFunc.SPI_SCK, PadFunc.SPI_SDO, PadFunc.SPI_SDI)


PadFunctions = {
        Pad.A1: (PadFunc.GPIO_IN, PadFunc.SPI_SDI,
                 PadFunc.GPIO_OUT, PadFunc.SPI_SDO, PadFunc.SPI_SCK, PadFunc.SPI_SS),
        Pad.A2: (PadFunc.GPIO_IN, PadFunc.SPI_SDI,
                 PadFunc.GPIO_OUT, PadFunc.SPI_SDO, PadFunc.SPI_SCK, PadFunc.SPI_SS),
        Pad.A3: (PadFunc.GPIO_IN, PadFunc.SPI_SDI,
                 PadFunc.GPIO_OUT, PadFunc.SPI_SDO, PadFunc.SPI_SCK, PadFunc.SPI_SS),
        Pad.A4: (PadFunc.GPIO_IN, PadFunc.SPI_SDI,
                 PadFunc.GPIO_OUT, PadFunc.SPI_SDO, PadFunc.SPI_SCK, PadFunc.SPI_SS),
        Pad.A5: (PadFunc.GPIO_IN, PadFunc.SPI_SDI,
                 PadFunc.GPIO_OUT, PadFunc.SPI_SDO, PadFunc.SPI_SCK, PadFunc.SPI_SS),
        Pad.A6: (PadFunc.GPIO_IN, PadFunc.SPI_SDI,
                 PadFunc.GPIO_OUT, PadFunc.SPI_SDO, PadFunc.SPI_SCK, PadFunc.SPI_SS),
        Pad.A7: (PadFunc.GPIO_IN, PadFunc.SPI_SDI,
                 PadFunc.GPIO_OUT, PadFunc.SPI_SDO, PadFunc.SPI_SCK, PadFunc.SPI_SS),
        Pad.A8: (PadFunc.GPIO_IN, PadFunc.SPI_SDI,
                 PadFunc.GPIO_OUT, PadFunc.SPI_SDO, PadFunc.SPI_SCK, PadFunc.SPI_SS),
        Pad.B1: (PadFunc.GPIO_IN, PadFunc.SPI_SDI,
                 PadFunc.GPIO_OUT),
        Pad.B2: (PadFunc.GPIO_IN,
                 PadFunc.GPIO_OUT, PadFunc.SPI_SDO, PadFunc.TUNNEL_ACTIVE),
        Pad.B3: (PadFunc.GPIO_IN,
                 PadFunc.GPIO_OUT, PadFunc.SPI_SCK, PadFunc.SPI_XFER_IDLE),
        Pad.B4: (PadFunc.GPIO_IN,
                 PadFunc.GPIO_OUT, PadFunc.SPI_SS,  PadFunc.HIGH),
        }


class IoRelayDevice():
    """Encapsulation of an UART384 with the IO relay gateware "relay_spi"."""
    def __init__(self, serialdevice:str, baudrate:int, verbose:bool=False):
        self.verbose = verbose
        self.dev = serial.Serial(serialdevice, baudrate, timeout=.1, rtscts=False, dsrdtr=False)

    def _rw1(self, out: bytes) -> bytes:
        """Send a single byte and return a single response byte."""
        assert len(out) == 1
        self.dev.write(out)
        response = self.dev.read(1)
        if self.verbose:
            print(f"    _{ord(out):02x} -> {ord(response):02x}")
        assert len(response) == 1
        return response

    def _await_ri(self, value: bool):
        """Await that RI line goes to @value."""
        while self.dev.ri != value:
            time.sleep(0.001)

    def _await_dcd(self, value: bool):
        """Await that DCD line goes to @value."""
        while self.dev.cd != value:
            time.sleep(0.001)

    def tunnel(self, enable: bool):
        """Enter or leave tunnel mode"""
        if self.verbose and self.dev.rts != enable:
            print(f"  _{'ENTER' if enable else 'EXIT'} TUNNEL")
        self.dev.rts = enable
        self._await_dcd(enable)

    def register_read_write(self, address: Register, new_value_fun: Callable[[int], int]) -> tuple[int, int]:
        """Read register @address, pass read value to @new_value_fun,
        write its return value as new value of register.
        Returns tuple of (old value, new value) of register.
        @new_value_fun must either take an int and return an int,
        or may be None, then the value is not changed before sending"""
        self.tunnel(False)
        old_value = ord(self._rw1(address.to_bytes()))
        if new_value_fun is not None:
            new_value = new_value_fun(old_value)
        else:
            new_value = old_value
        self._rw1(new_value.to_bytes())
        return (old_value, new_value)

    def register_read_clear_set_write(self, address: Register, clear_mask: int, set_mask: int):
        """Read register @address, clear @clear_mask, set @set_mask,
        and write that result back to register @address.
        Returns tuple of (old value, new value) of register."""
        def _mask_fun(value: int) -> int:
            return (value & ~clear_mask) | set_mask
        return self.register_read_write(address, _mask_fun)

    def register_write(self, address: Register, value: int) -> int:
        """Read register @address, write @value as new byte,
        return original value of register. """
        self.tunnel(False)
        old_value = ord(self._rw1(address.value.to_bytes()))
        self._rw1(value.to_bytes())
        return old_value

    def register_read(self, address: Register) -> int:
        """Read register @address, send a dummy byte, return read value"""
        return self.register_write(address, 255)

    def mux_pad(self, pad: Pad, function: PadFunc):
        """Change @pad function to @function.
        Raises if pad doesn't exist of function is unavailable for that pad."""
        try:
            idx = PadFunctions[pad].index(function)
        except ValueError as e:
            raise ValueError(f"Function {function} not supported for pad {pad}") from e
        address = Register.MUX_PAD_A2_A1.value + (pad.value-1)//2
        high_nibble = 0 == pad.value % 2
        if self.verbose:
            print(f"MUX {pad} -> {function}, address {address}: "
                  f"{'high' if high_nibble else 'low'}-nibble := idx {idx}")
        def _fun(v: int) -> int:
            return (
                    (v & 0x0F | ((idx & 0xF) << 4))
                    if high_nibble else
                    (v & 0xF0 | ((idx & 0xF) << 0))
                    )
        self.register_read_write(address, _fun)

    def mux_pads(self, padfuncs: dict):
        """mux multiple pad functions as described by iterable padfuncs"""
        for pad, func in padfuncs.items():
            self.mux_pad(pad, func)

    # all A pads muxed to input
    MUX_SETTINGS_A_IN =   {Pad.A1: PadFunc.GPIO_IN,
                           Pad.A2: PadFunc.GPIO_IN,
                           Pad.A3: PadFunc.GPIO_IN,
                           Pad.A4: PadFunc.GPIO_IN,
                           Pad.A5: PadFunc.GPIO_IN,
                           Pad.A6: PadFunc.GPIO_IN,
                           Pad.A7: PadFunc.GPIO_IN,
                           Pad.A8: PadFunc.GPIO_IN}

    # configuration for programming another board via J1 (TC2050)
    MUX_SETTINGS_A_PROG = {Pad.A1: PadFunc.SPI_SDO,
                           Pad.A2: PadFunc.GPIO_IN,   # CDONE
                           Pad.A3: PadFunc.GPIO_OUT,  # CRESET
                           Pad.A4: PadFunc.GPIO_IN,   # AUX_B
                           Pad.A5: PadFunc.GPIO_IN,   # AUX_A
                           Pad.A6: PadFunc.SPI_SCK,
                           Pad.A7: PadFunc.SPI_SS,
                           Pad.A8: PadFunc.SPI_SDI}

    # all A pads muxed to a safe state
    MUX_SETTINGS_A_SAFE = MUX_SETTINGS_A_IN

    # all A pads muxed to output
    MUX_SETTINGS_A_OUT =  {Pad.A1: PadFunc.GPIO_OUT,
                           Pad.A2: PadFunc.GPIO_OUT,
                           Pad.A3: PadFunc.GPIO_OUT,
                           Pad.A4: PadFunc.GPIO_OUT,
                           Pad.A5: PadFunc.GPIO_OUT,
                           Pad.A6: PadFunc.GPIO_OUT,
                           Pad.A7: PadFunc.GPIO_OUT,
                           Pad.A8: PadFunc.GPIO_OUT}

    # all B pads muxed to input
    MUX_SETTINGS_B_IN =   {Pad.B1: PadFunc.GPIO_IN,
                           Pad.B2: PadFunc.GPIO_IN,
                           Pad.B3: PadFunc.GPIO_IN,
                           Pad.B4: PadFunc.GPIO_IN}

    # all B pads muxed to a safe state
    MUX_SETTINGS_B_SAFE = {Pad.B1: PadFunc.GPIO_IN,
                           Pad.B2: PadFunc.TUNNEL_ACTIVE,
                           Pad.B3: PadFunc.SPI_XFER_IDLE,
                           Pad.B4: PadFunc.HIGH}

    # configuration for programming the internal flash
    MUX_SETTINGS_B_SPI =  {Pad.B1: PadFunc.SPI_SDI,
                           Pad.B2: PadFunc.SPI_SDO,
                           Pad.B3: PadFunc.SPI_SCK,
                           Pad.B4: PadFunc.SPI_SS}

    # all B pads muxed to output
    MUX_SETTINGS_B_GPIO = {Pad.B1: PadFunc.GPIO_IN,
                           Pad.B2: PadFunc.GPIO_OUT,
                           Pad.B3: PadFunc.GPIO_OUT,
                           Pad.B4: PadFunc.GPIO_OUT}

    def mux_safe_state(self):
        """Mux all pads to a safe state:
        - GPIO A*: all inputs
        - GPIO B*: SS always high, use LEDs"""
        self.mux_pads(self.MUX_SETTINGS_A_SAFE)
        self.mux_pads(self.MUX_SETTINGS_B_SAFE)

    def mux_spi_internal(self):
        """Mux for internal SPI on port B, and inputs on port A"""
        self.mux_pads(self.MUX_SETTINGS_A_SAFE)
        self.mux_pads(self.MUX_SETTINGS_B_SPI)

    def mux_spi_external(self):
        """Mux for external SPI on port A,
        trigger CRESET,
        and safe state on port B"""
        self.mux_pads(self.MUX_SETTINGS_A_PROG)
        self.mux_pads(self.MUX_SETTINGS_B_SAFE)

    def gpo_clear_set(self, a_mask_clear: int=0, a_mask_set: int=0, b_mask_clear: int=0, b_mask_set: int=0) -> tuple[int, int]:
        """Mask and set GPIO output values.
        Returns a tuple with new values (new_a, new_b)"""
        _, new_a = self.register_read_clear_set_write(Register.GPIO_WRITE_A,
                                                      a_mask_clear, a_mask_set)
        _, new_b = self.register_read_clear_set_write(Register.GPIO_WRITE_B,
                                                      b_mask_clear, b_mask_set)
        return (new_a, new_b)

    def gpi_get(self) -> tuple[int, int]:
        """Return general purpose input values for port A and B
        as tuple (a:int, b:int) """
        return (self.register_read(Register.GPIO_READ_A),
                self.register_read(Register.GPIO_READ_B))

    def spi_configure(self, cpol:bool, cpha:bool, msb_first:bool, cs_active_low:bool, clkdiv:int):
        """ set SPI configuration """
        cfg = (  int(cs_active_low)<<7
               | int(cpol)<<6
               | int(cpha)<<5
               | int(msb_first)<<4
               | (clkdiv & 0xf))
        if self.verbose:
            print("  _CFG")
        self.register_write(Register.SPI_CTRL, cfg)

    def transceive(self, data: bytes) -> bytes:
        """ do a full SPI transmit/receive cycle,
        send @data and return received result """
        if self.verbose:
            print("  _XCEIVE")
        self.tunnel(True)
        result = b''
        for w in data:
            w = w.to_bytes()
            self._await_ri(False)
            r = self._rw1(w)
            result += r
        self.tunnel(False)
        return result


class SpiFlashDevice(IoRelayDevice):
    """ Encapsulation of common commands of SPI serial flash chips """
    def __init__(self, serialdevice:str, baudrate:int, internal:bool=True, verbose:bool=False):
        super().__init__(serialdevice=serialdevice, baudrate=baudrate, verbose=verbose)
        self.spi_configure(cpol=True, cpha=True, msb_first=True,
                           cs_active_low=True, clkdiv=4)
        if internal:
            self.mux_spi_internal()
        else:
            self.mux_spi_external()
            self.gpo_clear_set(a_mask_clear=0xff)

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
