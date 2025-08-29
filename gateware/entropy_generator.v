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

	output wire led1,
	output wire led2,
	input  wire button,
	output wire SPI_SS);


	parameter ENABLE_ADDITIONAL_RINGOSCILLATORS = 0;
	parameter BAUDRATE = 1000000;


	/* pull SS high so we can safely use other SPI port signals */
	assign SPI_SS = 1;


	/* reset circuit */
	wire reset_in;
	wire rst;
	synchronous_reset_timer resetter(clk32m, rst, reset_in);


	/* random noise generators */
	generate
		/* optional ringoscillator outputs */
		if(ENABLE_ADDITIONAL_RINGOSCILLATORS) begin : extra_ringoscillators
			wire r_out_insane;
			ringoscillator #(.DELAY_LUTS(0)) ringosci_insane(r_out_insane);

			wire r_out_fast;
			ringoscillator #(.DELAY_LUTS(1)) ringosci_fast(r_out_fast);

			wire r_out_slow;
			ringoscillator #(.DELAY_LUTS(20)) ringosci_slow(r_out_slow);

			assign gpio5 = r_out_insane;
			assign gpio6 = r_out_fast;
			assign gpio7 = r_out_slow;
		end
	endgenerate

	wire [15:0] lfsr;
	wire word_ready;
	wire bit_ready;
	wire metastable;
	randomized_lfsr randomized_lfsr(clk32m, rst, bit_ready, word_ready, lfsr, metastable);

	assign gpio1 = metastable;


	/* UART implementation */
	wire is_transmitting;
	wire uart_received;
	wire [7:0] uart_rxByte;
	uart #(.CLOCKFRQ(32000000), .BAUDRATE(BAUDRATE) ) uart(
		.clk(clk32m),
		.rst(rst),
		.rx(uart_rxd),
		.tx(uart_txd),
		.transmit(!is_transmitting & word_ready),
		.tx_byte(lfsr[7:0]),
		.received(uart_received),
		.rx_byte(uart_rxByte),
		.is_receiving(),
		.is_transmitting(is_transmitting),
		.recv_error()
	);

	assign reset_in = uart_received && (uart_rxByte == 8'h72);
	assign gpio2 = lfsr[0];
	assign gpio3 = bit_ready;
	assign gpio4 = word_ready;


	/* debugging outputs */
	assign gpio8 = rst;
endmodule
