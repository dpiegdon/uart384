`default_nettype none

module clocktests(
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

	parameter TAPS = 16;

	wire out;
	ringoscillator_adjustable #(.MAX_TAPS(TAPS), .PREFIX_DELAYS(0), .TAP_DELAYS(1)) osci(out, tap, rst);
	reg [$clog2(TAPS-1)+1:0] tap = 0;

	// UART
	wire is_transmitting;
	wire uart_received;
	wire [7:0] uart_rxByte;
	reg tx_now;
	wire tx_word = tap + 8'h21;
	uart #(.CLOCKFRQ(32000000), .BAUDRATE(1000000) ) uart(
		.clk(clk32m),
		.rst(0),
		.rx(uart_txd),
		.tx(uart_rxd),
		.transmit(!is_transmitting & tx_now),
		.tx_byte(0),
		.received(uart_received),
		.rx_byte(uart_rxByte),
		.is_receiving(),
		.is_transmitting(is_transmitting),
		.recv_error()
	);

	wire tap_up   = uart_received && (uart_rxByte == 8'h5D);
	wire tap_down = uart_received && (uart_rxByte == 8'h5B);
	wire tap_rst  = uart_received && (uart_rxByte == 8'h72);
	reg rst = 1;

	always @(posedge clk32m) begin
		if(tap_up) begin
			rst = 1;
			tap = tap+1;
			tx_now = 1;
		end else if(tap_down) begin
			rst = 1;
			tap = tap-1;
			tx_now = 1;
		end else if(tap_rst) begin
			rst = 1;
			tap = 0;
			tx_now = 1;
		end else begin
			rst = 0;
			tx_now = 0;
		end
	end

	reg uart_counter = 0;
	always @(posedge uart_received) begin
		uart_counter = !uart_counter;
	end

	assign led1 = uart_counter;

	assign gpio2 = clk32m;
	assign gpio4 = out;
endmodule
