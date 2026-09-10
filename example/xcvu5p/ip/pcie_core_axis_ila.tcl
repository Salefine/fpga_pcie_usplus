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
  CONFIG.ID_WIDTH {4} \
  CONFIG.DATA_WIDTH {512} \
] [get_ips pcie_to_mifg_if]