
################################################################
# This is a generated script based on design: design_1
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2024.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source design_1_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# send_axi_s2mm, recv_axi_mm2s, send_axis

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xcvu5p-flvb2104-2-i
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name design_1

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:axi_bram_ctrl:4.1\
xilinx.com:ip:blk_mem_gen:8.4\
xilinx.com:ip:smartconnect:1.0\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
send_axi_s2mm\
recv_axi_mm2s\
send_axis\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set m_axis [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 m_axis ]


  # Create ports
  set clk [ create_bd_port -dir I -type clk -freq_hz 100000000 clk ]
  set rst_n [ create_bd_port -dir I -type rst rst_n ]
  set tx_length [ create_bd_port -dir I -from 31 -to 0 -type data tx_length ]
  set tx_start [ create_bd_port -dir I tx_start ]
  set tx_address [ create_bd_port -dir I -from 31 -to 0 tx_address ]
  set desc_rx_start [ create_bd_port -dir I desc_rx_start ]
  set desc_rx_length [ create_bd_port -dir I -from 31 -to 0 desc_rx_length ]
  set desc_rx_address [ create_bd_port -dir I -from 31 -to 0 desc_rx_address ]

  # Create instance: axi_bram_ctrl_0, and set properties
  set axi_bram_ctrl_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_0 ]

  # Create instance: axi_bram_ctrl_0_bram, and set properties
  set axi_bram_ctrl_0_bram [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 axi_bram_ctrl_0_bram ]
  set_property CONFIG.Memory_Type {True_Dual_Port_RAM} $axi_bram_ctrl_0_bram


  # Create instance: send_axi_s2mm_0, and set properties
  set block_name send_axi_s2mm
  set block_cell_name send_axi_s2mm_0
  if { [catch {set send_axi_s2mm_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $send_axi_s2mm_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property -dict [list \
    CONFIG.AXI_ADDR_WIDTH {32} \
    CONFIG.AXI_DATA_WIDTH {512} \
    CONFIG.AXI_ID_WIDTH {8} \
    CONFIG.AXI_MAX_BURST_LEN {64} \
    CONFIG.AXI_STRB_WIDTH {64} \
  ] $send_axi_s2mm_0


  # Create instance: recv_axi_mm2s_0, and set properties
  set block_name recv_axi_mm2s
  set block_cell_name recv_axi_mm2s_0
  if { [catch {set recv_axi_mm2s_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $recv_axi_mm2s_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property -dict [list \
    CONFIG.AXI_DATA_WIDTH {512} \
    CONFIG.AXI_MAX_BURST_LEN {64} \
    CONFIG.AXI_STRB_WIDTH {64} \
  ] $recv_axi_mm2s_0


  # Create instance: smartconnect_0, and set properties
  set smartconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0 ]

  # Create instance: send_axis_0, and set properties
  set block_name send_axis
  set block_cell_name send_axis_0
  if { [catch {set send_axis_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $send_axis_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property -dict [list \
    CONFIG.STREAM_TDATA_WIDTH {512} \
    CONFIG.STREAM_TKEEP_WIDTH {64} \
    CONFIG.STREAM_TOTAL_WIDTH {578} \
  ] $send_axis_0


  # Create interface connections
  connect_bd_intf_net -intf_net axi_bram_ctrl_0_BRAM_PORTA [get_bd_intf_pins axi_bram_ctrl_0_bram/BRAM_PORTA] [get_bd_intf_pins axi_bram_ctrl_0/BRAM_PORTA]
  connect_bd_intf_net -intf_net axi_bram_ctrl_0_BRAM_PORTB [get_bd_intf_pins axi_bram_ctrl_0_bram/BRAM_PORTB] [get_bd_intf_pins axi_bram_ctrl_0/BRAM_PORTB]
  connect_bd_intf_net -intf_net recv_axi_mm2s_0_M_AXI [get_bd_intf_pins recv_axi_mm2s_0/M_AXI] [get_bd_intf_pins smartconnect_0/S00_AXI]
  connect_bd_intf_net -intf_net recv_axi_mm2s_0_m_axis [get_bd_intf_ports m_axis] [get_bd_intf_pins recv_axi_mm2s_0/m_axis]
  connect_bd_intf_net -intf_net send_axi_s2mm_0_M_AXI [get_bd_intf_pins send_axi_s2mm_0/M_AXI] [get_bd_intf_pins smartconnect_0/S01_AXI]
  connect_bd_intf_net -intf_net send_axis_0_m_axis [get_bd_intf_pins send_axis_0/m_axis] [get_bd_intf_pins send_axi_s2mm_0/s_axis]
  connect_bd_intf_net -intf_net smartconnect_0_M00_AXI [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_pins axi_bram_ctrl_0/S_AXI]

  # Create port connections
  connect_bd_net -net clk_1  [get_bd_ports clk] \
  [get_bd_pins send_axis_0/m_axis_aclk] \
  [get_bd_pins recv_axi_mm2s_0/M_AXI_ACLK] \
  [get_bd_pins send_axi_s2mm_0/M_AXI_ACLK] \
  [get_bd_pins smartconnect_0/aclk] \
  [get_bd_pins axi_bram_ctrl_0/s_axi_aclk]
  connect_bd_net -net desc_rx_address_0_1  [get_bd_ports desc_rx_address] \
  [get_bd_pins recv_axi_mm2s_0/desc_rx_address]
  connect_bd_net -net desc_rx_length_0_1  [get_bd_ports desc_rx_length] \
  [get_bd_pins recv_axi_mm2s_0/desc_rx_length]
  connect_bd_net -net desc_rx_start_0_1  [get_bd_ports desc_rx_start] \
  [get_bd_pins recv_axi_mm2s_0/desc_rx_start]
  connect_bd_net -net desc_tx_address_0_1  [get_bd_ports tx_address] \
  [get_bd_pins send_axi_s2mm_0/desc_tx_address]
  connect_bd_net -net rst_n_1  [get_bd_ports rst_n] \
  [get_bd_pins send_axis_0/m_axis_aresetn] \
  [get_bd_pins recv_axi_mm2s_0/M_AXI_ARESETN] \
  [get_bd_pins send_axi_s2mm_0/M_AXI_ARESETN] \
  [get_bd_pins smartconnect_0/aresetn] \
  [get_bd_pins axi_bram_ctrl_0/s_axi_aresetn]
  connect_bd_net -net st_start_0_1  [get_bd_ports tx_start] \
  [get_bd_pins send_axis_0/st_start] \
  [get_bd_pins send_axi_s2mm_0/desc_tx_start]
  connect_bd_net -net tx_length_1  [get_bd_ports tx_length] \
  [get_bd_pins send_axis_0/st_length] \
  [get_bd_pins send_axi_s2mm_0/desc_tx_length]

  # Create address segments
  assign_bd_address -offset 0x80000000 -range 0x00400000 -target_address_space [get_bd_addr_spaces send_axi_s2mm_0/M_AXI] [get_bd_addr_segs axi_bram_ctrl_0/S_AXI/Mem0] -force
  assign_bd_address -offset 0x80000000 -range 0x00400000 -target_address_space [get_bd_addr_spaces recv_axi_mm2s_0/M_AXI] [get_bd_addr_segs axi_bram_ctrl_0/S_AXI/Mem0] -force


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


