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

/* Relay an SPI channel over UART.
 * Both configuration of the channel
 * (SPI CPOL, CPHA, CS active high/low, MSB first/last)
 * and transfers via the channel are fully encapsulated
 * in an UART line.
 * UART RTS is used to indicate:
 *  - HIGH: configuration mode
 *  - LOW:  transfer mode: set chipselect active, transfer mode
 *
 * In configuration mode each received byte is interpreted
 * as configuration: {ACTIVE_LOW, CPOL, CPHA, MSB_FIRST, CLK_DIV[4]}
 *
 * In transer mode, the chipselect automatically is activated with RTS.
 * Each received byte is transmitted via SPI, each response byte
 * received is returned via UART. To release chipselect, release RTS.
 *
 * RI is used to indicate that the SPI channel is currently idle
 * (i.e. more bytes may be sent via UART).
 * DCD is used to indicate that the channel was successfully activated
 * when RTS was set to LOW.
 *
 * See the accompanying python script for a simple implementation
 * of the UART side to talk to the onboard program flash.
 */
`define CONNECT_TO_ONBOARD_FLASH
module relay_spi(
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

	localparam CLOCK_PSC_WIDTH = 4;
	localparam SPI_CLK_DIV_WIDTH = 4;
	localparam SLOW_FREQ = 32_000_000 / 2**(CLOCK_PSC_WIDTH-1);

	// internal slow clock
	wire [CLOCK_PSC_WIDTH-1:0] clk_psc;
	wire slow_clk = clk_psc[CLOCK_PSC_WIDTH-1];
	clock_prescaler #(.WIDTH(CLOCK_PSC_WIDTH)) clock_psc(clk, clk_psc, 0);

	// UART
	wire uart_is_receiving;
	wire uart_is_transmitting;
	wire uart_rx_completed;
	wire [7:0] uart_data_tx;
	wire [7:0] uart_data_rx;
	reg uart_tx_trigger = 0;
	uart #(.CLOCKFRQ(SLOW_FREQ), .BAUDRATE(500_000)) uart(
		.clk(slow_clk),
		.rst(0),
		.rx(uart_txd),
		.tx(uart_rxd),
		.transmit(!uart_is_transmitting & uart_tx_trigger),
		.tx_byte(uart_data_tx),
		.received(uart_rx_completed),
		.rx_byte(uart_data_rx),
		.is_receiving(uart_is_receiving),
		.is_transmitting(uart_is_transmitting),
		.recv_error()
	);

	// SPI configuration
	wire spi_cs_active_low;
	wire spi_cpol;
	wire spi_cpha;
	wire spi_msb_first;
	wire [SPI_CLK_DIV_WIDTH-1:0] spi_clk_div;
	reg [7:0] spi_configuration_word = 8'b1_0_0_0_0100;
	assign {spi_cs_active_low, spi_cpol, spi_cpha, spi_msb_first, spi_clk_div} = spi_configuration_word;

	// SPI
	wire spi_xfer_idle;
	reg spi_xfer_word_trigger = 0;
	wire spi_xfer_word_completed;
	wire [7:0] spi_data_rx;
	wire spi_cs;
	simple_spi_master #(.PRESCALER_WIDTH(SPI_CLK_DIV_WIDTH)) spi(
		.system_clk(slow_clk),
		.clk_div(spi_clk_div),
		.cpol(spi_cpol),
		.cpha(spi_cpha),
		.msb_first(spi_msb_first),
		.xfer_enable(tunnel_active),
		.xfer_idle(spi_xfer_idle),
		.xfer_word_trigger(spi_xfer_word_trigger),
		.xfer_word_completed(spi_xfer_word_completed),
		.data_tx(uart_data_rx),
		.data_rx(spi_data_rx),
		.spi_cs(spi_cs),
`ifdef CONNECT_TO_ONBOARD_FLASH
		.spi_clk(SPI_SCK_led2_green),
		.spi_miso(SPI_SDI_button),
		.spi_mosi(SPI_SDO_led1_red));
	assign SPI_SS = spi_cs ^ spi_cs_active_low;
`else
		.spi_clk(gpio4),
		.spi_miso(gpio6),
		.spi_mosi(gpio8));
	assign gpio2 = spi_cs ^ spi_cs_active_low;
`endif

	// control/data plane selection:
	wire tunnel_active     = uart_rts == 0;
	wire tunnel_alert      = 0;
	assign uart_dcd        = !tunnel_active;
	assign uart_ri         = spi_xfer_idle;

	assign uart_data_tx = tunnel_active ? spi_data_rx : spi_configuration_word;

	always @(posedge slow_clk) begin
		uart_tx_trigger <= 0;
		spi_xfer_word_trigger <= 0;
		if (tunnel_active) begin
			if (uart_rx_completed && spi_xfer_idle) begin
				spi_xfer_word_trigger <= 1;
			end
			if (spi_xfer_word_completed) begin
				uart_tx_trigger <= 1;
			end
		end else begin
			if (uart_rx_completed) begin
				spi_configuration_word <= uart_data_rx;
				uart_tx_trigger <= 1;
			end
		end
	end

endmodule
