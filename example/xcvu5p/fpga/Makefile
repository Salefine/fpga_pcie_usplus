# ============================================================
# FPGA PCIe Stack Project Makefile
# Linux + Vivado 2024.2
# ============================================================

SHELL := /bin/bash

VIVADO_HOME := /tools/xilinx24_2/Vivado/2024.2
VIVADO_BIN  := $(VIVADO_HOME)/bin/vivado

PRJ_NAME := fpga
PRJ_DIR  := .
PART     := xcvu5p-flvb2104-2-i

XPR_FILE := $(PRJ_NAME).xpr

TOP_MODULE := fpga
SIM_TOP    := tb_fpga_core


# ============================================================
# RTL FILES
# ============================================================

RTL_FILES := \
	../../../rtl/sg_block_dma.vh \
	../../../rtl/fpga_core.v \
	../../../rtl/dma_if_pcie_axis.v \
	../../../rtl/dma_if_pcie_axis_rd_v1.v \
	../../../rtl/dma_if_pcie_axis_wr_v1.v \
	../../../rtl/dma_if_pcie_axi.v \
	../../../rtl/dma_if_pcie_axi_rd.v \
	../../../rtl/dma_if_pcie_axi_wr.v \
	../../../rtl/pcie_axil_tobar_master.v \
	../../../rtl/pcie_bar_register.v \
	../../../rtl/pcie_tlp_fifo_raw.v \
	../../../rtl/pcie_tlp_fifo.v \
	../../../rtl/pcie_us_cfg.v \
	../../../rtl/pcie_us_if_cc.v \
	../../../rtl/pcie_us_if_cq.v \
	../../../rtl/pcie_us_if_rq.v \
	../../../rtl/pcie_us_if_rc.v \
	../../../rtl/pcie_us_if.v \
	../../../rtl/priority_encoder.v \
	../../../rtl/arbiter.v \
	../../../rtl/pcie_us_msi.v \
	../../../rtl/send_axis.v \
	../../../rtl/pcie_axil_master.v \
	../../../rtl/pcie_tlp_demux_bar.v \
	../../../rtl/pcie_tlp_demux.v \
	../../../rtl/pcie_tlp_mux.v \
	../../../rtl/axis_dma_channel_fifo.v \
	../../../rtl/dma_intr_queue.v \
	../../../rtl/axi_ram.v \
	../../../rtl/axi_dma_rd.v \
	../../../rtl/axi_dma_wr.v \
	../../../rtl/xpm_sync_fifo.v \
	../../../rtl/dma_tx_wr_irq.v \
	../../../rtl/dma_rx_rd_irq.v \
	../../../rtl/sgdma_if_pcie_axis.v \
	../../../rtl/sgdma_if_pcie_axis_rd.v \
	../../../rtl/sgdma_if_pcie_axis_wr.v \
	../../../rtl/sgdma_if_pcie_ctrl.v \
	../../../rtl/sgdma_if_pcie_axi.v \
	../../../rtl/sgdma_if_pcie_axi_rd.v \
	../../../rtl/sgdma_if_pcie_axi_wr.v \
	../rtl/fpga.sv


# ============================================================
# XDC FILES
# ============================================================

XDC_FILES := \
	../fpga.xdc


# ============================================================
# SIMULATION FILES
# ============================================================

SIM_FILES := \
	../../../tb/tb_dma_if_pcie_axis_wr.sv \
	../../../tb/tb_dma_if_pcie_axis_rd.sv \
	../../../tb/tb_xpm_sync_fifo.sv \
	../../../tb/tb_fpga_core.sv


# ============================================================
# TCL FILES
# ============================================================

GEN_TCL  := generate_project.tcl
SYN_TCL  := run_synth.tcl
IMPL_TCL := run_impl.tcl
BIT_TCL  := run_bit.tcl


# ============================================================
# DEFAULT TARGET
# ============================================================

.PHONY: all
all: make


# ============================================================
# CREATE PROJECT
# ============================================================

.PHONY: make
make:
	@echo "Generating Vivado project..."

	@echo 'create_project $(PRJ_NAME) $(PRJ_DIR) -part $(PART) -force' > $(GEN_TCL)

	@echo '' >> $(GEN_TCL)
	@echo 'add_files -fileset sources_1 {' >> $(GEN_TCL)
	@for f in $(RTL_FILES); do \
		echo "$$f" >> $(GEN_TCL); \
	done
	@echo '}' >> $(GEN_TCL)

	@echo '' >> $(GEN_TCL)
	@echo 'add_files -fileset constrs_1 {' >> $(GEN_TCL)
	@for f in $(XDC_FILES); do \
		echo "$$f" >> $(GEN_TCL); \
	done
	@echo '}' >> $(GEN_TCL)

	@echo '' >> $(GEN_TCL)
	@echo 'add_files -fileset sim_1 {' >> $(GEN_TCL)
	@for f in $(SIM_FILES); do \
		echo "$$f" >> $(GEN_TCL); \
	done
	@echo '}' >> $(GEN_TCL)

	@echo '' >> $(GEN_TCL)
	@echo 'set_property top $(TOP_MODULE) [get_filesets sources_1]' >> $(GEN_TCL)
	@echo 'set_property top $(SIM_TOP) [get_filesets sim_1]' >> $(GEN_TCL)

	@echo '' >> $(GEN_TCL)
	@echo 'source ../ip/pcie4_usplus_gen3x16.tcl' >> $(GEN_TCL)
	@echo 'source ../ip/pcie_core_axis_ila.tcl' >> $(GEN_TCL)

	@echo '' >> $(GEN_TCL)
	@echo 'update_compile_order -fileset sources_1' >> $(GEN_TCL)
	@echo 'exit' >> $(GEN_TCL)

	@$(VIVADO_BIN) -mode batch -source $(GEN_TCL)


# ============================================================
# SYNTHESIS
# ============================================================

.PHONY: synth
synth:
	@echo "Running synthesis..."

	@echo 'open_project $(XPR_FILE)' > $(SYN_TCL)
	@echo 'reset_run synth_1' >> $(SYN_TCL)
	@echo 'launch_runs synth_1 -jobs 8' >> $(SYN_TCL)
	@echo 'wait_on_run synth_1' >> $(SYN_TCL)
	@echo 'exit' >> $(SYN_TCL)

	@$(VIVADO_BIN) -mode batch -source $(SYN_TCL)


# ============================================================
# IMPLEMENTATION
# ============================================================

.PHONY: impl
impl:
	@echo "Running implementation..."

	@echo 'open_project $(XPR_FILE)' > $(IMPL_TCL)
	@echo 'launch_runs impl_1 -to_step write_bitstream -jobs 8' >> $(IMPL_TCL)
	@echo 'wait_on_run impl_1' >> $(IMPL_TCL)
	@echo 'exit' >> $(IMPL_TCL)

	@$(VIVADO_BIN) -mode batch -source $(IMPL_TCL)


# ============================================================
# OPEN VIVADO GUI
# ============================================================

.PHONY: fpga
fpga:
	@echo "Opening Vivado GUI..."
	@source $(VIVADO_HOME)/settings64.sh && $(VIVADO_BIN) $(XPR_FILE)


# ============================================================
# CLEAN
# ============================================================

.PHONY: clean
clean:
	find . -mindepth 1 ! -name Makefile -exec rm -rf {} +
	@echo "Clean done."