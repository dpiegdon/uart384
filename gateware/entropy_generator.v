`default_nettype none

/* USB entropy generator.
 *
 * The FPGA is used in a feedback-loop configuration such that
 * a metastable state is used as entropy source.
 * This entropy is used to feed a hashing algorithm and then
 * output via UART to the host computer.
 *
 * The metastable state and other debugging signals are also
 * output on the GPIO headers.
 *
 * On linux systems you can improve your system entropy with that.
 * One simple variant is:
 *
 *	socat file:/dev/ttyACM0,b1000000,ignoreeof,cs8,raw,echo=0 STDOUT | sudo tee /dev/random | pv > /dev/null
 */
module entropy_generator(
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

	/* pull SS high so we can safely use other SPI port signals */
	assign SPI_SS = 1;

	/* source of good randomness */
	wire [7:0] rng_out;
	wire rng_valid;
	wire out_received;
	wire metastable;
	randomized_spongent #(.SBOX_DOUBLETIME(1)) rng(
				.clk(clk),
				.rst(0),
				.out(rng_out),
				.out_valid(rng_valid),
				.out_received(out_received),
				.metastable(metastable));

	/* UART downstream */
	wire is_transmitting;
	wire do_transmit;
	wire [7:0] tx_byte;
	uart #(.CLOCKFRQ(32000000), .BAUDRATE(1000000) ) uart(
		.clk(clk),
		.rst(0),
		.rx(0),
		.tx(uart_rxd),
		.transmit(do_transmit),
		.tx_byte(tx_byte),
		.received(),
		.rx_byte(),
		.is_receiving(),
		.is_transmitting(is_transmitting),
		.recv_error()
	);

	/* statemachine for relaying output */
	assign out_received = is_transmitting;
	assign do_transmit = !is_transmitting & rng_valid;
	assign tx_byte = rng_out;

	/* debugging output */
	assign SPI_SDO_led1_red = 0;
	assign SPI_SCK_led2_green = is_transmitting;

	assign gpio1 = out_received;		assign gpio2 = rng_valid;
	assign gpio3 = SPI_SDI_button;		assign gpio4 = is_transmitting;
	assign gpio5 = uart_txd;		assign gpio6 = uart_rxd;
	assign gpio7 = clk;			assign gpio8 = metastable;
endmodule
