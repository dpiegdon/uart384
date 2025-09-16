`default_nettype none

/* USB entropy generator.
 *
 * The FPGA is used in a feedback-loop configuration such that
 * a metastable state is used as entropy source.
 * This entropy is used to feed a linear feedback shift register,
 * and every so-and-so bits a character of random data from that
 * LFSR is output via UART to the host computer.
 *
 * The metastable state and a few other debugging signals are also
 * output on the GPIO headers.
 *
 * On linux systems you can improve your system entropy with that.
 * One simple variant is:
 *
 *	socat file:/dev/ttyACM0,b1000000,ignoreeof,cs8,raw STDOUT | sudo tee /dev/random | pv > /dev/null
 *
 * The UART can also receive data, but only the character 'r' is
 * recognized and triggers an internal reset.
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

	input  wire clk32m,

	output wire gpio1,
	output wire gpio2,
	output wire gpio3,
	output wire gpio4,
	output wire gpio5,
	output wire gpio6,
	output wire gpio7,
	output wire gpio8,

	output wire SPI_SDO_led1,
	output wire SPI_SCK_led2,
	input  wire SPI_SDI_button,
	output wire SPI_SS);

	/* pull SS high so we can safely use other SPI port signals */
	assign SPI_SS = 1;



	wire [7:0] rng_out;
	wire rng_valid;
	wire is_transmitting;

	/* source of good randomness */
	randomized_spongent rng(.clk(clk32m),
				.rst(0),
				.out(rng_out),
				.out_valid(rng_valid),
				.out_received(is_transmitting),
				.metastable());

	/* UART downstream */
	uart #(.CLOCKFRQ(32000000), .BAUDRATE(1000000) ) uart(
		.clk(clk32m),
		.rst(0),
		.rx(0),
		.tx(uart_rxd),
		.transmit(!is_transmitting & rng_valid),
		.tx_byte(rng_out),
		.received(),
		.rx_byte(),
		.is_receiving(),
		.is_transmitting(is_transmitting),
		.recv_error()
	);
endmodule
