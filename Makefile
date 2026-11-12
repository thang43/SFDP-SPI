IVERILOG ?= /opt/homebrew/bin/iverilog
VVP ?= /opt/homebrew/bin/vvp
SURFER ?= /opt/homebrew/bin/surfer

.PHONY: test lint waves clean test-uart waves-uart test-sfdp lint-sfdp demo-sfdp waves-sfdp test-all

test: build/tb_counter.vvp
	$(VVP) $<

build/tb_counter.vvp: rtl/counter.sv tb/tb_counter.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_counter -o $@ $^

lint:
	$(IVERILOG) -g2012 -Wall -t null -s tb_counter rtl/counter.sv tb/tb_counter.sv

waves: test
	$(SURFER) build/smoke.vcd

build/tb_uart_rx.vvp: rtl/uart_rx.sv tb/tb_uart_rx.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_uart_rx -o $@ $^

test-uart: build/tb_uart_rx.vvp
	$(VVP) $<
	$(IVERILOG) -g2012 -Wall -s tb_uart_rx -Ptb_uart_rx.CLKS_PER_BIT=434 -o build/tb_uart_rx_434.vvp rtl/uart_rx.sv tb/tb_uart_rx.sv
	$(VVP) build/tb_uart_rx_434.vvp

waves-uart: test-uart
	$(SURFER) build/uart_rx.vcd

SFDP_RTL = rtl/spi_sfdp_reader.sv rtl/sfdp_discovery.sv
SFDP_MODEL = tb/spi_sfdp_flash_model.sv

test-sfdp:
	mkdir -p build
	@set -e; for divider in 1 3 4; do \
		$(IVERILOG) -g2012 -Wall -s tb_spi_sfdp_reader -Ptb_spi_sfdp_reader.HALF_CYCLES=$$divider -o build/tb_spi_sfdp_reader_$$divider.vvp rtl/spi_sfdp_reader.sv $(SFDP_MODEL) tb/tb_spi_sfdp_reader.sv; \
		$(VVP) build/tb_spi_sfdp_reader_$$divider.vvp; \
		$(IVERILOG) -g2012 -Wall -s tb_sfdp_discovery -Ptb_sfdp_discovery.HALF_CYCLES=$$divider -o build/tb_sfdp_discovery_$$divider.vvp $(SFDP_RTL) $(SFDP_MODEL) tb/tb_sfdp_discovery.sv; \
		$(VVP) build/tb_sfdp_discovery_$$divider.vvp; \
	done

lint-sfdp:
	$(IVERILOG) -g2012 -Wall -DSYNTHESIS -t null -s sfdp_discovery $(SFDP_RTL)

build/tb_sfdp_discovery.vvp: $(SFDP_RTL) $(SFDP_MODEL) tb/tb_sfdp_discovery.sv
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_sfdp_discovery -o $@ $^

demo-sfdp: build/tb_sfdp_discovery.vvp
	$(VVP) $< +demo +waves

waves-sfdp: demo-sfdp
	$(SURFER) --command-file sfdp_waveforms.sucl build/sfdp_discovery.vcd

test-all: test test-uart test-sfdp lint-sfdp

clean:
	rm -f build/tb_counter.vvp build/smoke.vcd build/tb_uart_rx.vvp build/tb_uart_rx_434.vvp build/uart_rx.vcd
	rm -f build/tb_spi_sfdp_reader_*.vvp build/tb_sfdp_discovery*.vvp build/spi_sfdp_reader.vcd build/sfdp_discovery.vcd
