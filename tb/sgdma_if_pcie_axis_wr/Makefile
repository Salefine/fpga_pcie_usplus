# Makefile to run cocotb test `sgdma_if_pcie_axis_wr`
# Usage: make SIM=iverilog

TOPLEVEL_LANG = verilog
PWD := $(shell pwd)
TOPLEVEL = sgdma_if_pcie_axis_wr
MODULE = sgdma_if_pcie_axis_wr
SIM ?= iverilog

# By default collect common RTL in ../../rtl; override VERILOG_SOURCES in environment if needed
VERILOG_SOURCES := $(wildcard ../../rtl/*.v) $(wildcard ../../rtl/*/*.v) $(wildcard ../../rtl/*.sv) $(wildcard ../../rtl/*/*.sv)

# Allow user to append additional sources via EXTRA_VERILOG
ifdef EXTRA_VERILOG
VERILOG_SOURCES += $(EXTRA_VERILOG)
endif

# Allow passing SIM options
SIM_ARGS ?=

# cocotb include
COCOTB_CONFIG := $(shell which cocotb-config 2>/dev/null || true)
ifeq ($(COCOTB_CONFIG),)
$(warning cocotb-config not found in PATH; ensure cocotb is installed and cocotb-config is available)
endif

# Include cocotb simulation Makefile (requires cocotb installed)
include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: list
list:
	@echo "TOPLEVEL      = $(TOPLEVEL)"
	@echo "MODULE        = $(MODULE)"
	@echo "SIM           = $(SIM)"
	@echo "VERILOG_SOURCES:"
	@for f in $(VERILOG_SOURCES); do echo "  $$f"; done

# Example usage notes
# To run with iverilog (default): make
# To run with verilator: make SIM=verilator
# To add extra source files: make EXTRA_VERILOG="../../rtl/some_file.sv"
