create_ip -name ila -vendor xilinx.com -library ip  -module_name pcie_core_axis_ila
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {18} \
  CONFIG.C_PROBE0_WIDTH {512} \
  CONFIG.C_PROBE12_WIDTH {512} \
  CONFIG.C_PROBE13_WIDTH {16} \
  CONFIG.C_PROBE14_WIDTH {161} \
  CONFIG.C_PROBE1_WIDTH {16} \
  CONFIG.C_PROBE2_WIDTH {183} \
  CONFIG.C_PROBE6_WIDTH {512} \
  CONFIG.C_PROBE7_WIDTH {16} \
  CONFIG.C_PROBE8_WIDTH {137} \
  CONFIG.Component_Name {pcie_core_axis_ila} \
] [get_ips pcie_core_axis_ila]

create_ip -name ila -vendor xilinx.com -library ip  -module_name pcie_tlp_ila
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {23} \
  CONFIG.C_PROBE0_WIDTH {512} \
  CONFIG.C_PROBE14_WIDTH {512} \
  CONFIG.C_PROBE15_WIDTH {128} \
  CONFIG.C_PROBE16_WIDTH {16} \
  CONFIG.C_PROBE1_WIDTH {128} \
  CONFIG.C_PROBE2_WIDTH {16} \
  CONFIG.C_PROBE3_WIDTH {6} \
  CONFIG.C_PROBE8_WIDTH {128} \
  CONFIG.C_PROBE9_WIDTH {6} \
  CONFIG.C_PROBE21_WIDTH {32} \
  CONFIG.Component_Name {pcie_tlp_ila} \
] [get_ips pcie_tlp_ila]

create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_0
set_property -dict [list \
  CONFIG.C0.DDR4_AxiSelection {true} \
  CONFIG.C0.DDR4_DataWidth {64} \
  CONFIG.C0.DDR4_InputClockPeriod {3332} \
  CONFIG.C0.DDR4_Mem_Add_Map {ROW_BANK_COLUMN} \
  CONFIG.C0.DDR4_MemoryPart {MT40A512M16LY-075} \
  CONFIG.C0.DDR4_TimePeriod {833} \
] [get_ips ddr4_0]

create_ip -name axi_clock_converter -vendor xilinx.com -library ip -module_name pcie_to_mifg_if
set_property -dict [list \
  CONFIG.AWUSER_WIDTH {0} \
  CONFIG.DATA_WIDTH {512} \
] [get_ips pcie_to_mifg_if]