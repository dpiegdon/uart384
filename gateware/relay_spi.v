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
`include "verilog-buildingblocks/lattice_ice40/io_pad_ice40.v"
`include "verilog-buildingblocks/simple_spi_master.v"
`include "verilog-buildingblocks/uart.v"

/* UART-to-SPI/GPIO interfacing gateware.
 *
 * This gateware provides a UART interface with:
 * - configuration mode (RTS HIGH):
 *   - for each pin GPIO1..8 and on-board SPI SS, SCK, SDI, SDO:
 *     - select pin function
 *   - for function SPI: SPI configuration of
 *     - ACTIVE_LOW
 *     - CPOL
 *     - CPHA
 *     - MSB_FIRST
 *     - CLK_DIV (0..15; 0 maps to 2MHz SPI clock)
 *   - for function GPIO output: set output value
 *   - for function GPIO input: read back input value
 * - SPI tunnel mode (RTS LOW):
 *   - perform a single SPI transfer:
 *     - CS is low exactly as long as RTS is low
 *     - bytes received on UART are sent on SPI
 *     - bytes received on SPI are returned on UART.
 * 
 * UART signal description:
 * - RTS is used to switch between tunnel and configuration mode:
 *   - HIGH: configuration mode
 *   - LOW:  SPI tunnel transfer mode: set chipselect active
 * - DCD is used to indicate that the channel was successfully activated
 *   when RTS was set to LOW.
 *   - HIGH: configuration mode active
 *   - LOW:  tunnel mode active
 * - RI is used to indicate that the SPI channel is currently idle
 *   (i.e. more bytes may be sent via UART).
 *   - HIGH: idle
 *   - LOW:  busy
 *
 * Configuration mode:
 * UART commands are two-byte register interface messages:
 * - 1st byte is the register # to addres
 *   - high nibble is ignored: {4'xxxx, 4'address}
 *   - address 0 is the addressing register itself, so this TRUNCATES the
 *     UART command and expects another address as the next byte
 *   - a response is sent, depending on the register addressed:
 *     - readable registers immediately return their current value (but still
 *       need a 2nd dummy byte to finish the command)
 *     - non-readable registers return 8'h00
 * - 2nd byte is the byte to write to the specified register (for write-registers),
 *   or a dummy byte that will be ignored (for read-registers)
 *   - a response of 8'h00 is always returned
 *
 * The following registers exist:
 * - REGI_ADDR_MUX_PAD_y_x
 *   - read/writeable -- allows read-mask-set-write operations in one command
 *   - for y,x in [ (A2,A1), (A4,A3), (A6,A5), (A8,A7), (B2,B1), (B4,B3) ]
 *   - selects function for pads n and m,
 *     n is high nibble, m is low nibble
 *   - depending on mux-choices, each can be 3 bits (padA*) or 2 bits (padB*) wide:
 *     ({1'x, 3'funcAn, 1'x, 3'funcAm}) or ({2'x, 2'funcBn, 2'x, 2'funcBm})
 *   - NOTE: for available functions (pad-specific!)
 *           see io_pad_ice40 padA1..padA8 and padB1..padB4
 * - REGI_ADDR_GPIO_WRITE_A
 *   - read/writeable -- allows read-mask-set-write operations in one command
 *   - sets the GPIO-A output values ({8'gpio-a})
 * - REGI_ADDR_GPIO_WRITE_B
 *   - read/writeable -- allows read-mask-set-write operations in one command
 *   - sets the GPIO-B output values (in lower nibble: {4'xxxx, 4'gpio-b})
 * - REGI_ADDR_GPIO_READ_A
 *   - readable, responds with GPIO-A input values ({8'gpio-a})
 * - REGI_ADDR_GPIO_READ_B
 *   - readable, responds with GPIO-B input values (in lower nibble: {4'xxxx, 4'gpio-b})
 * - REGI_ADDR_SPI_CTRL
 *   - read/writeable -- allows read-mask-set-write operations in one command
 *   - sets the SPI configuration word
 *     ({1'spi_cs_active_low, 1'spi_cpol, 1'spi_cpha, 1'spi_msb_first, 4'spi_clk_div})
 * - REGI_ADDR_VERSION
 *   - readable, responds with register interface version `REGI_VERSION`.
 *
 * To recover from potential sync loss you can
 * - either shortly enter tunnel mode and leave it again. (via RTS)
 * - or send a byte with 4'x0 as lower nibble (e.g. '@'), with the risk of
 *   sending some unknown command with this as 2nd byte.
 * Then the next byte received will always be interpreted as register address.
 *
 * SPI tunnel mode:
 * As described above, SPI CS is active while tunnel mode is on,
 * bytes are interchanged between SPI and UART.
 * Tunnel mode is enabled iff. RTS iw low.
 */
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

	inout  wire gpio1,
	inout  wire gpio2,
	inout  wire gpio3,
	inout  wire gpio4,
	inout  wire gpio5,
	inout  wire gpio6,
	inout  wire gpio7,
	inout  wire gpio8,

	inout  wire SPI_SDO_led1_red,
	inout  wire SPI_SCK_led2_green,
	inout  wire SPI_SDI_button,
	inout  wire SPI_SS);

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
	wire [7:0] uart_data_rx;
	reg [7:0] uart_data_tx;
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
	reg [7:0] spi_configuration_word;
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
		.spi_clk(func_spi_sck),
		.spi_miso(func_spi_sdi),
		.spi_mosi(func_spi_sdo));
	assign func_spi_ss = spi_cs ^ spi_cs_active_low;

	// IO pads
	reg [2:0] padA1func = 0;
	reg [2:0] padA2func = 0;
	reg [2:0] padA3func = 0;
	reg [2:0] padA4func = 0;
	reg [2:0] padA5func = 0;
	reg [2:0] padA6func = 0;
	reg [2:0] padA7func = 0;
	reg [2:0] padA8func = 0;
	reg [1:0] padB1func = 0;  // start as GPIO input so button-press cannot create a short.
	reg [1:0] padB2func = 3;  // start red LED as tunnel-active indicator.
	reg [1:0] padB3func = 3;  // start green LED as SPI-xfer-idle indicator.
	reg [1:0] padB4func = 3;  // start SS pulled high so we can't interfere with onboard flash.

	wire [8:0] mux_func_spi_sdi;

	wire [11:0] func_gpio_receive;
	wire        func_spi_sdi = |mux_func_spi_sdi;
	wire        func_spi_sdo;
	wire        func_spi_sck;
	wire        func_spi_ss;
	reg  [11:0] func_gpio_transmit = 0;

	// control/data plane selection:
	wire tunnel_active     = uart_rts == 0;
	wire tunnel_alert      = 0;
	assign uart_dcd        = !tunnel_active;
	assign uart_ri         = spi_xfer_idle;

	/* IO pad declarations and their selectable functions.
	 * Functions index is COUNTED FROM THE RIGHT TO THE LEFT.
	 * To select a function, write the corresponding
	 * index fron the right (0-indexed) into the function register.
	 * NON-EXISTING FUNCTIONS DON'T COUNT.
	 *                                             /---- IO pin ----\  /func.reg\  /----------------------- output functions -----------------------\  /------------- input functions -------------\  */
	io_pad_ice40 #(.TXCOUNT(4), .RXCOUNT(2)) padA1(gpio1,               padA1func, {func_spi_ss,  func_spi_sck, func_spi_sdo, func_gpio_transmit[ 0]}, {mux_func_spi_sdi[ 0], func_gpio_receive[ 0]});
	io_pad_ice40 #(.TXCOUNT(4), .RXCOUNT(2)) padA2(gpio2,               padA2func, {func_spi_ss,  func_spi_sck, func_spi_sdo, func_gpio_transmit[ 1]}, {mux_func_spi_sdi[ 1], func_gpio_receive[ 1]});
	io_pad_ice40 #(.TXCOUNT(4), .RXCOUNT(2)) padA3(gpio3,               padA3func, {func_spi_ss,  func_spi_sck, func_spi_sdo, func_gpio_transmit[ 2]}, {mux_func_spi_sdi[ 2], func_gpio_receive[ 2]});
	io_pad_ice40 #(.TXCOUNT(4), .RXCOUNT(2)) padA4(gpio4,               padA4func, {func_spi_ss,  func_spi_sck, func_spi_sdo, func_gpio_transmit[ 3]}, {mux_func_spi_sdi[ 3], func_gpio_receive[ 3]});
	io_pad_ice40 #(.TXCOUNT(4), .RXCOUNT(2)) padA5(gpio5,               padA5func, {func_spi_ss,  func_spi_sck, func_spi_sdo, func_gpio_transmit[ 4]}, {mux_func_spi_sdi[ 4], func_gpio_receive[ 4]});
	io_pad_ice40 #(.TXCOUNT(4), .RXCOUNT(2)) padA6(gpio6,               padA6func, {func_spi_ss,  func_spi_sck, func_spi_sdo, func_gpio_transmit[ 5]}, {mux_func_spi_sdi[ 5], func_gpio_receive[ 5]});
	io_pad_ice40 #(.TXCOUNT(4), .RXCOUNT(2)) padA7(gpio7,               padA7func, {func_spi_ss,  func_spi_sck, func_spi_sdo, func_gpio_transmit[ 6]}, {mux_func_spi_sdi[ 6], func_gpio_receive[ 6]});
	io_pad_ice40 #(.TXCOUNT(4), .RXCOUNT(2)) padA8(gpio8,               padA8func, {func_spi_ss,  func_spi_sck, func_spi_sdo, func_gpio_transmit[ 7]}, {mux_func_spi_sdi[ 7], func_gpio_receive[ 7]});
	io_pad_ice40 #(.TXCOUNT(1), .RXCOUNT(2)) padB1(SPI_SDI_button,      padB1func,                                           {func_gpio_transmit[ 8]}, {mux_func_spi_sdi[ 8], func_gpio_receive[ 8]});
	io_pad_ice40 #(.TXCOUNT(3), .RXCOUNT(1)) padB2(SPI_SDO_led1_red,    padB2func,              {tunnel_active, func_spi_sdo, func_gpio_transmit[ 9]},                       {func_gpio_receive[ 9]});
	io_pad_ice40 #(.TXCOUNT(3), .RXCOUNT(1)) padB3(SPI_SCK_led2_green,  padB3func,              {spi_xfer_idle, func_spi_sck, func_gpio_transmit[10]},                       {func_gpio_receive[10]});
	io_pad_ice40 #(.TXCOUNT(3), .RXCOUNT(1)) padB4(SPI_SS,              padB4func,              {         1'b1,  func_spi_ss, func_gpio_transmit[11]},                       {func_gpio_receive[11]});

	// register&tunnel statemachine
	localparam REGI_VERSION            = 2;	// register interface version
	localparam REGI_ADDR_ADDRESS       = 'h0;
	localparam REGI_ADDR_MUX_PAD_A2_A1 = 'h1;
	localparam REGI_ADDR_MUX_PAD_A4_A3 = 'h2;
	localparam REGI_ADDR_MUX_PAD_A6_A5 = 'h3;
	localparam REGI_ADDR_MUX_PAD_A8_A7 = 'h4;
	localparam REGI_ADDR_MUX_PAD_B2_B1 = 'h5;
	localparam REGI_ADDR_MUX_PAD_B4_B3 = 'h6;
	localparam REGI_ADDR_GPIO_READ_A   = 'h8;
	localparam REGI_ADDR_GPIO_READ_B   = 'h9;
	localparam REGI_ADDR_GPIO_WRITE_A  = 'hA;
	localparam REGI_ADDR_GPIO_WRITE_B  = 'hB;
	localparam REGI_ADDR_SPI_CTRL      = 'hC;
	localparam REGI_ADDR_VERSION       = 'hF;
	reg [3:0] regi_state = REGI_ADDR_ADDRESS;

	always @(posedge slow_clk) begin
		uart_tx_trigger <= 0;
		spi_xfer_word_trigger <= 0;
		if (tunnel_active) begin
			if (uart_rx_completed && spi_xfer_idle) begin
				spi_xfer_word_trigger <= 1;
			end
			if (spi_xfer_word_completed) begin
				uart_data_tx = spi_data_rx;
				uart_tx_trigger <= 1;
			end
			regi_state <= REGI_ADDR_ADDRESS;
		end else begin
			if (uart_rx_completed) begin
				uart_tx_trigger <= 1;
				if (regi_state == REGI_ADDR_ADDRESS) begin
					regi_state <= uart_data_rx[3:0];
					case (uart_data_rx[3:0])
						/* respond to address with values of readable registers */
						REGI_ADDR_MUX_PAD_A2_A1: uart_data_tx <= {1'h0, padA2func, 1'h0, padA1func};
						REGI_ADDR_MUX_PAD_A4_A3: uart_data_tx <= {1'h0, padA4func, 1'h0, padA3func};
						REGI_ADDR_MUX_PAD_A6_A5: uart_data_tx <= {1'h0, padA6func, 1'h0, padA5func};
						REGI_ADDR_MUX_PAD_A8_A7: uart_data_tx <= {1'h0, padA8func, 1'h0, padA7func};
						REGI_ADDR_MUX_PAD_B2_B1: uart_data_tx <= {2'h0, padB2func, 2'h0, padB1func};
						REGI_ADDR_MUX_PAD_B4_B3: uart_data_tx <= {2'h0, padB4func, 2'h0, padB3func};
						REGI_ADDR_GPIO_READ_A:   uart_data_tx <= func_gpio_receive[7:0];
						REGI_ADDR_GPIO_READ_B:   uart_data_tx <= {4'h0, func_gpio_receive[11:8]};
						REGI_ADDR_GPIO_WRITE_A:  uart_data_tx <= func_gpio_transmit[7:0];
						REGI_ADDR_GPIO_WRITE_B:  uart_data_tx <= {4'h0, func_gpio_transmit[11:8]};
						REGI_ADDR_SPI_CTRL:      uart_data_tx <= spi_configuration_word;
						REGI_ADDR_VERSION:       uart_data_tx <= REGI_VERSION;
						default:                 uart_data_tx <= 8'h0;
					endcase
				end else begin
					regi_state <= REGI_ADDR_ADDRESS;
					uart_data_tx <= 0;
					case (regi_state)
						/* write values for writeable registers */
						REGI_ADDR_MUX_PAD_A2_A1: {padA2func, padA1func}   <= {uart_data_rx[6:4], uart_data_rx[2:0]};
						REGI_ADDR_MUX_PAD_A4_A3: {padA4func, padA3func}   <= {uart_data_rx[6:4], uart_data_rx[2:0]};
						REGI_ADDR_MUX_PAD_A6_A5: {padA6func, padA5func}   <= {uart_data_rx[6:4], uart_data_rx[2:0]};
						REGI_ADDR_MUX_PAD_A8_A7: {padA8func, padA7func}   <= {uart_data_rx[6:4], uart_data_rx[2:0]};
						REGI_ADDR_MUX_PAD_B2_B1: {padB2func, padB1func}   <= {uart_data_rx[5:4], uart_data_rx[1:0]};
						REGI_ADDR_MUX_PAD_B4_B3: {padB4func, padB3func}   <= {uart_data_rx[5:4], uart_data_rx[1:0]};
						REGI_ADDR_GPIO_WRITE_A:  func_gpio_transmit[7:0]  <= uart_data_rx;
						REGI_ADDR_GPIO_WRITE_B:  func_gpio_transmit[11:8] <= uart_data_rx[3:0];
						REGI_ADDR_SPI_CTRL:      spi_configuration_word   <= uart_data_rx;
					endcase
				end
			end
		end
	end
endmodule
