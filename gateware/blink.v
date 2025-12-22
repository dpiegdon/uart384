/*
This file is part of the UART384 software & gateware
(c) 2025 by David R. Piegdon <dgit@piegdon.de>

The UART384 software & gateware is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

The UART384 software & gateware is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with the UART384 software & gateware. If not, see <https://www.gnu.org/licenses/>.
*/

`default_nettype none

`include "verilog-buildingblocks/clock_prescaler.v"

module blink(
	output wire uart_rxd,
	input  wire uart_txd,
	input  wire uart_rts,
	output wire uart_cts,
	output wire uart_dsr,
	input  wire uart_dtr,
	output wire uart_dcd,
	output wire uart_ri,

	input  wire clk,

	output wire gpio1,
	output wire gpio2,
	output wire gpio3,
	output wire gpio4,
	output wire gpio5,
	output wire gpio6,
	output wire gpio7,
	output wire gpio8,

	output wire SPI_SDO_led1_red,
	output wire SPI_SCK_led2_green,
	input  wire SPI_SDI_button,
	output wire SPI_SS);

	localparam WIDTH=25;

	reg [WIDTH-1:0] pclk;
	clock_prescaler #(.WIDTH(WIDTH)) clk_prescaler(clk, pclk, 0);

	assign SPI_SCK_led2_green = pclk[WIDTH-1];
	assign SPI_SDO_led1_red   = pclk[WIDTH-2];
	assign gpio8              = pclk[WIDTH-3];
	assign gpio7              = pclk[WIDTH-4];
	assign gpio6              = pclk[WIDTH-5];
	assign gpio5              = pclk[WIDTH-6];
	assign gpio4              = pclk[WIDTH-7];
	assign gpio3              = pclk[WIDTH-8];
	assign gpio2              = pclk[WIDTH-9];
	assign gpio1              = pclk[WIDTH-10];
endmodule
