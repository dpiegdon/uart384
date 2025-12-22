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

`include "verilog-buildingblocks/lattice_ice40/ringoscillator.v"
`include "verilog-buildingblocks/uart.v"

/* Variable delay ring oscillator.
 *
 * Ring oscillator with a configurable delay line
 * than can be changed via UART input:
 *    '['  decrease delay
 *    ']'  increase delay
 *    'r'  reset to shortest delay
 */
module variable_ringoscillator(
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

	parameter TAPS = 16;

	// variable delay ring oscillator
	wire out;
	ringoscillator_adjustable #(.MAX_TAPS(TAPS), .PREFIX_DELAYS(0), .TAP_DELAYS(1)) osci(out, tap, rst);
	reg [$clog2(TAPS-1)+1:0] tap = 0;

	// UART
	wire is_transmitting;
	wire uart_received;
	wire [7:0] uart_rxByte;
	reg tx_now = 1;
	wire [7:0] tx_byte = tap + 8'h21;
	uart #(.CLOCKFRQ(32_000_000), .BAUDRATE(500_000)) uart(
		.clk(clk),
		.rst(rst),
		.rx(uart_txd),
		.tx(uart_rxd),
		.transmit(!is_transmitting & tx_now),
		.tx_byte(tx_byte),
		.received(uart_received),
		.rx_byte(uart_rxByte),
		.is_receiving(),
		.is_transmitting(is_transmitting),
		.recv_error()
	);

	wire tap_up   = uart_received && (uart_rxByte == 8'h5D);	// ']'
	wire tap_down = uart_received && (uart_rxByte == 8'h5B);	// '['
	wire tap_rst  = uart_received && (uart_rxByte == 8'h72);	// 'r'
	reg rst = 1;

	always @(posedge clk) begin
		if(tap_up) begin
			rst <= 1;
			tap <= (tap == TAPS-1) ? 0 : tap+1;
			tx_now <= 1;
		end else if(tap_down) begin
			rst <= 1;
			tap <= (tap == 0) ? TAPS-1 : tap-1;
			tx_now <= 1;
		end else if(tap_rst) begin
			rst <= 1;
			tap <= 0;
			tx_now <= 1;
		end else begin
			rst <= 0;
			tx_now <= 0;
		end
	end

	reg uart_counter = 0;
	always @(posedge uart_received) begin
		uart_counter <= !uart_counter;
	end

	assign SPI_SDO_led1_red = uart_counter;

	assign gpio2 = clk;
	assign gpio4 = out;
endmodule
