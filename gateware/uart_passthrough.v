`default_nettype none

/* Simple USB UART pass-through.
 *
 * This only connects the lines, does nothing to the signals.
 * Should be baudrate-agnostic.
 * LEDs are used to indicate traffic on RX and TX lines (active low).
 */
module uart_passthrough(
	output wire uart_rxd,
	input  wire uart_txd,
	input  wire uart_rts,
	output wire uart_cts,
	output wire uart_dsr,
	input  wire uart_dtr,
	output wire uart_dcd,
	output wire uart_ri,

	input  wire clk32m,

	input  wire gpio1,
	output wire gpio2,
	output wire gpio3,
	input  wire gpio4,
	input  wire gpio5,
	output wire gpio6,
	input  wire gpio7,
	input  wire gpio8,

	output wire led1,
	output wire led2,
	input  wire button,
	output wire SPI_SS);

	parameter LED_TIMEOUT = 25;


	/* pull SS high so we can safely use other SPI port signals */
	assign SPI_SS = 1;


	/* internal timing reference (ca. 122Hz) */
	reg [17:0] clk_prescaled;
	clock_prescaler #(.WIDTH(18)) clk_prescaler(clk32m, clk_prescaled, 0);
	wire clk = clk_prescaled[17];


	/* pass-through of UART signals */
	assign uart_rxd = gpio1;
	assign gpio2    = uart_txd;
	assign gpio3    = uart_rts;
	assign uart_cts = gpio4;
	assign uart_dsr = gpio5;
	assign gpio6    = uart_dtr;
	assign uart_dcd = gpio7;
	assign uart_ri  = gpio8;


	/* drive RX and TX LEDs based on last signals on those lines */
	reg [7:0] txd_led_timeout = 0;
	reg [7:0] rxd_led_timeout = 0;

	wire txd_timed_out = (txd_led_timeout == 0);
	wire rxd_timed_out = (rxd_led_timeout == 0);

	assign led1 = txd_timed_out;
	assign led2 = rxd_timed_out;

	always @(negedge uart_txd, posedge clk) begin
		if(uart_txd == 0) begin
			txd_led_timeout = LED_TIMEOUT;
		end else begin
			txd_led_timeout = txd_timed_out ? 0 : txd_led_timeout - 1;
		end
	end

	always @(negedge uart_rxd, posedge clk) begin
		if(uart_rxd == 0) begin
			rxd_led_timeout = LED_TIMEOUT;
		end else begin
			rxd_led_timeout = rxd_timed_out ? 0 : rxd_led_timeout - 1;
		end
	end
endmodule
