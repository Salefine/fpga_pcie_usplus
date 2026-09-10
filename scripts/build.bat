:: ============================================================
:: FPGA PCIe Stack Project Generator for Windows
:: This batch script sets up the environment for generating FPGA PCIe stack projects.
:: It checks for necessary tools, sets environment variables, and provides instructions for usage.
:: ============================================================


@echo off
echo ============================================
echo FPGA PCIe Stack Project Generator
echo Vivado Version: 2022.2
echo ============================================

:: ================= 用户配置 =================
@REM set VIVADO_DIR=C:/tools/xilinx24.2/Vivado/2024.2/bin
@REM set PRJ_DIR=E:/AMD_Ultrascale_Flow/fpga_pcie_usplus/example/xcvu5p/fpga
set VIVADO_DIR=D:/tools/xilinx2024.2/Vivado/2024.2/bin
set PRJ_DIR=F:/AMD_Ultrascale_Flow/fpga_pcie_usplus/example/xcvu5p/fpga
set PRJ_NAME=fpga
set PART=xcvu5p-flvb2104-2-i
:: ============================================

:: 检查 Vivado
if not exist "%VIVADO_DIR%/vivado.bat" (
    echo ERROR: Vivado not found!
    pause
    exit /b 1
)

:: 创建工程目录（如不存在）
if not exist "%PRJ_DIR%" (
    mkdir "%PRJ_DIR%"
)

cd /d "%PRJ_DIR%"

:: 生成 Tcl 文件
set TCL_FILE=generate_project.tcl

echo puts "Creating project..." > %TCL_FILE%
echo create_project %PRJ_NAME% %PRJ_DIR% -part %PART% -force >> %TCL_FILE%


::add design source files into project
::
echo puts "Adding RTL files..." >> %TCL_FILE%
echo add_files -fileset sources_1 -norecurse { >> %TCL_FILE%
echo ../../../rtl/dma_if_pcie_axi.v >> %TCL_FILE%
echo ../../../rtl/dma_if_pcie_axi_rd.v >> %TCL_FILE%
echo ../../../rtl/dma_if_pcie_axi_wr.v >> %TCL_FILE%
echo ../../../rtl/dma_if_pcie_axis.v >> %TCL_FILE%
echo ../../../rtl/axi_dma_wr.v >> %TCL_FILE%
echo ../../../rtl/axi_dma_rd.v >> %TCL_FILE%
echo ../../../rtl/dma_if_pcie_axis_wr_v1.v >> %TCL_FILE%
echo ../../../rtl/dma_if_pcie_axis_rd_v1.v >> %TCL_FILE%
echo ../../../rtl/sg_block_dma.vh >> %TCL_FILE%
echo ../../../rtl/fpga_core.v >> %TCL_FILE%
echo ../../../rtl/pcie_axil_tobar_master.v >> %TCL_FILE%
echo ../../../rtl/pcie_bar_register.v >> %TCL_FILE%
echo ../../../rtl/pcie_tlp_fifo_raw.v >> %TCL_FILE%
echo ../../../rtl/pcie_tlp_fifo.v >> %TCL_FILE%
echo ../../../rtl/pcie_us_cfg.v >> %TCL_FILE%
echo ../../../rtl/pcie_us_if_cc.v >> %TCL_FILE%
echo ../../../rtl/pcie_us_if_cq.v >> %TCL_FILE%
echo ../../../rtl/pcie_us_if_rq.v >> %TCL_FILE%
echo ../../../rtl/pcie_us_if_rc.v >> %TCL_FILE%
echo ../../../rtl/pcie_us_if.v >> %TCL_FILE%
echo ../../../rtl/priority_encoder.v >> %TCL_FILE%
echo ../../../rtl/arbiter.v >> %TCL_FILE%
echo ../../../rtl/pcie_us_msi.v >> %TCL_FILE%
echo ../../../rtl/dma_tx_wr_irq.v >> %TCL_FILE%
echo ../../../rtl/dma_rx_rd_irq.v >> %TCL_FILE%
echo ../../../rtl/send_axis.v >> %TCL_FILE%
echo ../../../rtl/pcie_axil_master.v >> %TCL_FILE%
echo ../../../rtl/pcie_tlp_demux_bar.v >> %TCL_FILE%
echo ../../../rtl/pcie_tlp_demux.v >> %TCL_FILE%
echo ../../../rtl/pcie_tlp_mux.v >> %TCL_FILE%
echo ../../../rtl/sgdma_if_pcie_axis_wr.v >> %TCL_FILE%
echo ../../../rtl/sgdma_if_pcie_axis_rd.v >> %TCL_FILE%
echo ../../../rtl/sgdma_if_pcie_axis.v >> %TCL_FILE%
echo ../../../rtl/sgdma_if_pcie_axi_wr.v >> %TCL_FILE%
echo ../../../rtl/sgdma_if_pcie_axi_rd.v >> %TCL_FILE%
echo ../../../rtl/sgdma_if_pcie_axi.v >> %TCL_FILE%
echo ../../../rtl/sgdma_if_pcie_ctrl.v >> %TCL_FILE%
echo ../../../rtl/dma_intr_queue.v >> %TCL_FILE%
echo ../../../rtl/axi_ram.v >> %TCL_FILE%
echo ../../../rtl/xpm_sync_fifo.v >> %TCL_FILE%
echo ../rtl/fpga.sv >> %TCL_FILE%
echo } >> %TCL_FILE%


echo puts "Updating compile order..." >> %TCL_FILE%
echo update_compile_order -fileset sources_1 >> %TCL_FILE%

echo puts "Adding CONSTRAINTS files..." >> %TCL_FILE%
echo add_files -fileset constrs_1 -norecurse { >> %TCL_FILE%
echo ../fpga.xdc >> %TCL_FILE%  
echo } >> %TCL_FILE%

echo puts "Adding SIMULATION files..." >> %TCL_FILE%
echo add_files -fileset sim_1 -norecurse { >> %TCL_FILE%
echo ../../../tb/tb_fpga_core.sv >> %TCL_FILE%   
echo ../../../tb/tb_dma_if_pcie_axis_rd.sv >> %TCL_FILE%   
echo ../../../tb/tb_dma_if_pcie_axis_wr.sv >> %TCL_FILE%   
echo ../../../tb/tb_xpm_sync_fifo.sv >> %TCL_FILE%   
echo ../../../tb/tb_axi_dma.sv >> %TCL_FILE%   
echo } >> %TCL_FILE%

echo set_property top tb_fpga_core [get_filesets sim_1] >> %TCL_FILE%

echo puts "Setting top module..." >> %TCL_FILE%
echo set_property top fpga [get_filesets sources_1] >> %TCL_FILE%

echo source ../ip/pcie4_usplus_gen3x16.tcl >> %TCL_FILE%
echo source ../ip/pcie_core_axis_ila.tcl >> %TCL_FILE%

echo puts "Saving project..." >> %TCL_FILE%

call "%VIVADO_DIR%/vivado.bat" -mode batch -source %TCL_FILE%

echo ============================================
echo Project generation finished.
echo ============================================

pause
