
DEVICE=lp384
PACKAGE=qn32
PCF=uart384.pcf

#QUIET=-q

# RNG seed for nextpnr-ice40. Try different values if you have not fully utilized the FPGAs logic but get placement issues.
# Otherwise keep fixed to get a deterministic behavior.
# You can also use `-r` to try random values. The used seed is listed in the first line of nextpnr's output.
SEED=--seed=893263542
#SEED=-r
# the size-constrained LP384 seems to work better with `sa' placing algorithm. some designs don't work with the standard placer `heap', or at least not very well.
PLACER=--placer sa

TESTBENCHES=$(wildcard *_tb.v)
TESTS=$(TESTBENCHES:%.v=%.test)

.PHONY: all prog run_tests graphs clean randomness_test source_randomness

.PRECIOUS: %.json %.asc %.bin %.rpt

# source code grouped by feature:
ENTROPY_FILES = \
	verilog-buildingblocks/lattice_ice40/random.v \
	verilog-buildingblocks/lattice_ice40/ringoscillator.v \
	verilog-buildingblocks/binary_debias.v \
	verilog-buildingblocks/lfsr.v \
	verilog-buildingblocks/random.v \
	verilog-buildingblocks/spongent_hash.v \
	verilog-buildingblocks/randomized_spongent.v

PRESCALER_FILES = \
	verilog-buildingblocks/clock_prescaler.v

RESET_FILES = \
	verilog-buildingblocks/synchronous_reset_timer.v

BUTTON_FILES = \
	verilog-buildingblocks/lattice_ice40/debounced_button.v \
	verilog-buildingblocks/lattice_ice40/pullup_input.v \
	verilog-buildingblocks/lattice_ice40/tristate_output.v \
	verilog-buildingblocks/debouncer.v

UART_FILES = \
	verilog-buildingblocks/uart.v

SPI_FILES = \
	verilog-buildingblocks/simple_spi_master.v

TOPLEVEL_FILES = \
	blink.v \
	entropy_generator.v \
	ring_noise.v \
	uart_passthrough.v \
	variable_ringoscillator.v

# generic targets:
all: $(subst .v,.rpt,$(TOPLEVEL_FILES))

prog: top.bin
	iceprog $<

top.bin: entropy_generator.bin
	# currently selected "top" project -- only needed for `make prog`
	-rm -f top.bin
	ln -s $< top.bin

run_tests: $(TESTS)
	make -C verilog-buildingblocks run_tests
	@for test in $^; do \
		echo $$test; \
		./$$test; \
	done

clean:
	-rm -f *.json
	-rm -f *.asc
	-rm -f *.bin
	-rm -f *.rpt
	-rm -f *.dot
	-rm -f *.png
	-rm *_tb.test
	-rm *_tb.vcd

graphs: $(subst .v,.png,$(ENTROPY_FILES))	\
	$(subst .v,.png,$(PRESCALER_FILES))	\
	$(subst .v,.png,$(RESET_FILES))		\
	$(subst .v,.png,$(BUTTON_FILES))	\
	$(subst .v,.png,$(UART_FILES))		\
	$(subst .v,.png,$(TOPLEVEL_FILES))

randomness_test:
	# receive random data from device and do NIST SP800-90B entropy assessment tests.
	# usefull for entropy-generator configuration.
	# requires tools from NIST Entropy Assessment, see https://github.com/usnistgov/SP800-90B_EntropyAssessment
	socat -u file:/dev/ttyUSB0,b1000000,ignoreeof,cs8,raw,echo=0 STDOUT | dd bs=1000 count=1000 > random.raw
	ea_non_iid -i -a -v random.raw 8
	ea_iid -i -a -v random.raw 8
	ea_non_iid -c -a -v random.raw 8
	ea_iid -c -a -v random.raw 8

source_randomness:
	# usefull for entropy-generator configuration.
	# receive random data from device and pipe it into the kernel entropy pool.
	socat -u file:/dev/ttyUSB0,b1000000,ignoreeof,cs8,raw,echo=0 STDOUT | sudo tee /dev/random | pv > /dev/null

# specific projects:
BLINK_FILES = $(PRESCALER_FILES) blink.v

blink.json: $(BLINK_FILES)

blink.dot: $(BLINK_FILES)


ENTROPY_GENERATOR_FILES = $(RESET_FILES) $(ENTROPY_FILES) $(UART_FILES) entropy_generator.v

entropy_generator.json: $(ENTROPY_GENERATOR_FILES)

entropy_generator.dot: $(ENTROPY_GENERATOR_FILES)


RINGOSCILLATOR_FILES = $(RESET_FILES) $(ENTROPY_FILES) $(UART_FILES) ring_noise.v

ring_noise.json: $(RINGOSCILLATOR_FILES)

ring_noise.dot: $(RINGOSCILLATOR_FILES)


UART_PASSTHROUGH_FILES = $(PRESCALER_FILES) uart_passthrough.v

uart_passthrough.json: $(UART_PASSTHROUGH_FILES)

uart_passthrough.dot: $(UART_PASSTHROUGH_FILES)


VARIABLE_RINGOSCILLATOR_FILES = variable_ringoscillator.v $(ENTROPY_FILES) $(UART_FILES)

variable_ringoscillator.json: $(VARIABLE_RINGOSCILLATOR_FILES)

variable_ringoscillator.dot: $(VARIABLE_RINGOSCILLATOR_FILES)


RELAY_SPI_FILES = relay_spi.v $(UART_FILES) $(SPI_FILES) $(PRESCALER_FILES)

relay_spi.json: $(RELAY_SPI_FILES)

relay_spi.dot: $(RELAY_SPI_FILES)


# generic pattern rules
%.dot: %.v
	yosys -p '$(^:%.v=read_verilog %.v;) proc; opt_clean -purge; opt -fine -full -share_all; show -colors 1 -width -stretch -format dot -prefix $(subst .dot,,$(notdir $@))'
	# demux multiple graphs from one file:
	gvpr 'BEG_G { fname = sprintf("$(subst .dot,,$(notdir $@))__%s.dot",$$G.name); writeG($$G, fname); }' $(notdir $@)

%.png: %.dot
	# actually create PNGs for all the demuxed modules, not the parent file
	for F in $(subst .dot,,$(notdir $<))__*.dot  ; do $$F; dot -Tpng $$F > $$F.png; done;
	# and delete the parent file
	-rm $(notdir $<)

%_tb.test: %_tb.v %.v
	verilator +1800-2012ext+v --lint-only -Wall --bbox-unsup $<
	iverilog  -g2012 -Wall -Wno-timescale -o $@ $^

%.json: %.v
	yosys -Q $(QUIET) -p 'proc; opt_clean -purge; opt -fine -full -share_all; synth_ice40 -dff -abc2 -top $(subst .v,,$<) -json $@' $^

%.asc: %.json
	nextpnr-ice40 $(QUIET) $(SEED) $(PLACER) --ignore-loops --promote-logic --opt-timing --$(DEVICE) --package $(PACKAGE) --pcf $(PCF) --json $< --asc $@

%.bin: %.asc
	icepack $< $@

%.rpt: %.asc
	icetime -p $(PCF) -P $(PACKAGE) -d $(DEVICE) -r $@ -m -t $<
