
ARCH=ice40
DEVICE=lp384
PACKAGE=qn32
PCF=uart384.pcf

#QUIET=-q

# RNG seed for nextpnr-ice40. Try different values if you have not fully utilized the FPGAs logic but get placement issues.
# Otherwise keep fixed to get a deterministic behavior.
# You can also use `-r` to try random values. The used seed is listed in the output.
#SEED=--seed=774337092
#SEED=-r

TESTBENCHES=$(wildcard *_tb.v)
TESTS=$(TESTBENCHES:%.v=%.test)

.PHONY: all prog run_tests graphs clean

.PRECIOUS: %.json %.asc %.bin %.rpt

PROD_FILES= top.v \
	verilog-buildingblocks/binary_debias.v \
	verilog-buildingblocks/clock_prescaler.v \
	verilog-buildingblocks/lattice_$(ARCH)/random.v \
	verilog-buildingblocks/lattice_$(ARCH)/ringoscillator.v \
	verilog-buildingblocks/lattice_ice40/debounced_button.v \
	verilog-buildingblocks/lattice_ice40/pullup_input.v \
	verilog-buildingblocks/lattice_ice40/tristate_output.v \
	verilog-buildingblocks/lfsr.v \
	verilog-buildingblocks/random.v \
	verilog-buildingblocks/synchronous_reset_timer.v \
	verilog-buildingblocks/uart.v

all: top.rpt hwtest.rpt

prog: top.bin
	iceprog $<

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

graphs: $(subst .v,.png,$(PROD_FILES))

top.json: $(PROD_FILES)

top.dot: $(PROD_FILES)


%.dot: %.v
	yosys -p '$(^:%.v=read_verilog %.v;) proc; opt -fine -full -share_all; show -colors 1 -width -stretch -format dot -prefix $(subst .dot,,$@)'
	gvpr 'BEG_G { fname = sprintf("top__%s.dot",$$G.name); writeG($$G, fname); }' $@

%.png: %.dot
	for F in $(subst .dot,,$<)__*.dot ; do dot -Tpng $$F > $$F.png; done;

%_tb.test: %_tb.v %.v
	iverilog -o $@ $^

%.json: %.v
	yosys -Q $(QUIET) -p 'proc; opt_clean; opt -fine -full -share_all; synth_ice40 -dff -top $(subst .v,,$<) -json $@' $^

%.asc: %.json
	nextpnr-ice40 $(QUIET) $(SEED) --ignore-loops --promote-logic --opt-timing --$(DEVICE) --package $(PACKAGE) --pcf $(PCF) --json $< --asc $@

%.bin: %.asc
	icepack $< $@

%.rpt: %.asc
	icetime -p $(PCF) -P $(PACKAGE) -d $(DEVICE) -r $@ -m -t $<
