
create_ip -name pcie4_uscale_plus -vendor xilinx.com -library ip -module_name pcie4_uscale_plus_0

set_property -dict [list \
    CONFIG.PL_LINK_CAP_MAX_LINK_SPEED {8.0_GT/s} \
    CONFIG.pcie_blk_locn {X1Y0} \
    CONFIG.PL_LINK_CAP_MAX_LINK_WIDTH {X16} \
    CONFIG.AXISTEN_IF_EXT_512_CQ_STRADDLE {true} \
    CONFIG.AXISTEN_IF_EXT_512_RQ_STRADDLE {true} \
    CONFIG.AXISTEN_IF_EXT_512_RC_4TLP_STRADDLE {true} \
    CONFIG.axisten_if_enable_client_tag {true} \
    CONFIG.axisten_if_width {512_bit} \
    CONFIG.extended_tag_field {true} \
    CONFIG.pf0_dev_cap_max_payload {1024_bytes} \
    CONFIG.axisten_freq {250} \
    CONFIG.PF0_CLASS_CODE {058000} \
    CONFIG.PF0_DEVICE_ID {0001} \
    CONFIG.PF0_SUBSYSTEM_ID {9076} \
    CONFIG.PF0_SUBSYSTEM_VENDOR_ID {10ee} \
    CONFIG.pf0_bar0_64bit {false} \
    CONFIG.pf0_bar0_scale {Kilobytes} \
    CONFIG.pf0_bar0_size {2} \
    CONFIG.pf0_bar1_enabled {true} \
    CONFIG.pf0_bar1_64bit {false} \
    CONFIG.pf0_bar1_scale {Kilobytes} \
    CONFIG.pf0_bar1_size {64} \
    CONFIG.pf0_bar4_64bit {false} \
    CONFIG.pf0_bar4_enabled {false} \
    CONFIG.pf0_msi_enabled {true} \
    CONFIG.pf0_msix_enabled {false} \
    CONFIG.PF0_DEVICE_ID {903f} \
    CONFIG.mode_selection {Advanced} \
    CONFIG.vendor_id {10ee} \
] [get_ips pcie4_uscale_plus_0]
