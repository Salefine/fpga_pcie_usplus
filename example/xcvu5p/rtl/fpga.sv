/****************************************************************************
 * @file    fpga.v
 * @brief  
 * @author  weslie (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2025-01-22
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    weslie        |  Support 100Gbps       |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2025 welie
 * ***************************************************************************/

 `resetall
 `timescale 1ns/1ps
 `default_nettype none

`include "../../../rtl/sg_block_dma.vh"

module fpga(
    input   wire    pcie_sys_clk_p  , 
  	input   wire    pcie_sys_clk_n  , 
  	input   wire    pcie_sys_rst_n  , 

	output  wire    [15 : 0]  	pcie_txp ,
  	output  wire    [15 : 0]  	pcie_txn ,
  	input   wire    [15 : 0]  	pcie_rxp ,
  	input   wire    [15 : 0]  	pcie_rxn ,

    input  wire             c0_sys_clk_p ,
    input  wire             c0_sys_clk_n ,
    output wire             ddr4_c0_act_n,
    output wire[16:0]       ddr4_c0_adr  ,
    output wire[1:0]        ddr4_c0_ba   ,
    output wire[0:0]        ddr4_c0_bg   ,
    output wire[0:0]        ddr4_c0_cke  ,
    output wire[0:0]        ddr4_c0_odt  ,
    output wire[0:0]        ddr4_c0_cs_n ,
    output wire[0:0]        ddr4_c0_ck_t ,
    output wire[0:0]        ddr4_c0_ck_c ,
    output wire             ddr4_c0_reset_n ,
    inout  wire [7:0]       ddr4_c0_dm_dbi_n,
    inout  wire [63:0]      ddr4_c0_dq   ,
    inout  wire [7:0]       ddr4_c0_dqs_t,
    inout  wire [7:0]       ddr4_c0_dqs_c
);

localparam AXIS_PCIE_DATA_WIDTH = 512;
localparam AXIS_PCIE_KEEP_WIDTH = (AXIS_PCIE_DATA_WIDTH/32);
localparam AXIS_PCIE_RC_USER_WIDTH = AXIS_PCIE_DATA_WIDTH < 512 ? 75 : 161;
localparam AXIS_PCIE_RQ_USER_WIDTH = AXIS_PCIE_DATA_WIDTH < 512 ? 62 : 137;
localparam AXIS_PCIE_CQ_USER_WIDTH = AXIS_PCIE_DATA_WIDTH < 512 ? 85 : 183;
localparam AXIS_PCIE_CC_USER_WIDTH = AXIS_PCIE_DATA_WIDTH < 512 ? 33 : 81;
localparam RC_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 256;
localparam RQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512;
localparam CQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512;
localparam CC_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512;

localparam RQ_SEQ_NUM_WIDTH = AXIS_PCIE_RQ_USER_WIDTH == 60 ? 4 : 6;
localparam RQ_SEQ_NUM_ENABLE = 1;

localparam PCIE_TAG_COUNT = 32;
localparam BAR0_APERTURE = 24;
localparam BAR2_APERTURE = 24;
localparam BAR4_APERTURE = 16;

localparam MSI_ENABLE = 1;

localparam AXI_ADDRESS_WIDTH = 32;
localparam BAR_NUMBERS       = 2;
localparam BAR_ADDRESS_MODE  = 64;


localparam C_M_AXI_ADDR_WIDTH	= AXI_ADDRESS_WIDTH;
localparam C_M_AXI_DATA_WIDTH	= AXIS_PCIE_DATA_WIDTH;
localparam C_M_AXI_ID_WIDTH	    = 4;
localparam C_M_AXI_AWUSER_WIDTH	= 1;
localparam C_M_AXI_ARUSER_WIDTH	= 1;
localparam C_M_AXI_WUSER_WIDTH	= 1;
localparam C_M_AXI_RUSER_WIDTH	= 1;
localparam C_M_AXI_BUSER_WIDTH	= 1;

localparam DMA_INTERFACE_MODE = "AXI_MEMORY_MAP";//AXI4-Stream
//localparam DMA_INTERFACE_MODE = "AXI4-Stream";//AXI4-Stream
localparam DMA_MODE = "Scatter_Gather";

// Clock and reset
wire pcie_user_clk;
wire pcie_user_reset;

wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_rq_tdata;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_rq_tkeep;
wire                               axis_rq_tlast;
wire                               axis_rq_tready;
wire [AXIS_PCIE_RQ_USER_WIDTH-1:0] axis_rq_tuser;
wire                               axis_rq_tvalid;

wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_rc_tdata;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_rc_tkeep;
wire                               axis_rc_tlast;
wire                               axis_rc_tready;
wire [AXIS_PCIE_RC_USER_WIDTH-1:0] axis_rc_tuser;
wire                               axis_rc_tvalid;

wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_cq_tdata;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_cq_tkeep;
wire                               axis_cq_tlast;
wire                               axis_cq_tready;
wire [AXIS_PCIE_CQ_USER_WIDTH-1:0] axis_cq_tuser;
wire                               axis_cq_tvalid;

wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_cc_tdata;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_cc_tkeep;
wire                               axis_cc_tlast;
wire                               axis_cc_tready;
wire [AXIS_PCIE_CC_USER_WIDTH-1:0] axis_cc_tuser;
wire                               axis_cc_tvalid;

`MARK_DEBUG wire [RQ_SEQ_NUM_WIDTH-1:0]        pcie_rq_seq_num0;
`MARK_DEBUG wire                               pcie_rq_seq_num_vld0;
`MARK_DEBUG wire [RQ_SEQ_NUM_WIDTH-1:0]        pcie_rq_seq_num1;
`MARK_DEBUG wire                               pcie_rq_seq_num_vld1;

wire [2:0] cfg_max_payload;
wire [2:0] cfg_max_read_req;
wire [3:0] cfg_rcb_status;

wire [9:0]  cfg_mgmt_addr;
wire [7:0]  cfg_mgmt_function_number;
wire        cfg_mgmt_write;
wire [31:0] cfg_mgmt_write_data;
wire [3:0]  cfg_mgmt_byte_enable;
wire        cfg_mgmt_read;
wire [31:0] cfg_mgmt_read_data;
wire        cfg_mgmt_read_write_done;

wire [7:0]  cfg_bus_number;

`MARK_DEBUG wire [7:0]  cfg_fc_ph;
`MARK_DEBUG wire [11:0] cfg_fc_pd;
`MARK_DEBUG wire [7:0]  cfg_fc_nph;
`MARK_DEBUG wire [11:0] cfg_fc_npd;
`MARK_DEBUG wire [7:0]  cfg_fc_cplh;
`MARK_DEBUG wire [11:0] cfg_fc_cpld;
`MARK_DEBUG wire [2:0]  cfg_fc_sel;


wire [3:0]   cfg_interrupt_msix_enable;
wire [3:0]   cfg_interrupt_msix_mask;
wire [251:0] cfg_interrupt_msix_vf_enable;
wire [251:0] cfg_interrupt_msix_vf_mask;
wire [63:0]  cfg_interrupt_msix_address;
wire [31:0]  cfg_interrupt_msix_data;
wire         cfg_interrupt_msix_int;
wire [1:0]   cfg_interrupt_msix_vec_pending;
wire         cfg_interrupt_msix_vec_pending_status;
wire         cfg_interrupt_msix_sent;
wire         cfg_interrupt_msix_fail;
wire [7:0]   cfg_interrupt_msi_function_number;



wire [3 : 0] cfg_interrupt_msi_enable  ;
wire [11 : 0] cfg_interrupt_msi_mmenable;
wire cfg_interrupt_msi_mask_update  ;
wire [31 : 0] cfg_interrupt_msi_data;
wire [1 : 0] cfg_interrupt_msi_select;
wire [31 : 0] cfg_interrupt_msi_int;
wire [31 : 0] cfg_interrupt_msi_pending_status;
wire cfg_interrupt_msi_pending_status_data_enable;
wire [1 : 0] cfg_interrupt_msi_pending_status_function_num;
wire cfg_interrupt_msi_sent;
wire cfg_interrupt_msi_fail;
localparam integer USER_MSI_IRQ_EX = 4;
localparam integer IRQ_SOURCES_EX  = 4 + USER_MSI_IRQ_EX;

wire [USER_MSI_IRQ_EX-1:0] user_msi_irq;
wire [IRQ_SOURCES_EX-1:0]  dma_msi_channel_ready_nc;

assign user_msi_irq = {USER_MSI_IRQ_EX{1'b0}};

wire [2 : 0] cfg_interrupt_msi_attr;
wire cfg_interrupt_msi_tph_present;
wire [1 : 0] cfg_interrupt_msi_tph_type;
wire [7 : 0] cfg_interrupt_msi_tph_st_tag;


wire status_error_cor;
wire status_error_uncor;

wire pcie_sys_clk;
wire pcie_sys_clk_gt;
wire c0_ddr4_ui_clk;
wire c0_ddr4_ui_clk_sync_rst;
wire c0_ddr4_aresetn = ~c0_ddr4_ui_clk_sync_rst;
/*
 * axi mamory map interface
 */
 


wire [C_M_AXI_ID_WIDTH-1 : 0]        S_AXI_ARID     ;
wire [C_M_AXI_ADDR_WIDTH-1 : 0]      S_AXI_ARADDR   ;
wire [7 : 0]                         S_AXI_ARLEN    ;
wire [2 : 0]                         S_AXI_ARSIZE   ;
wire [1 : 0]                         S_AXI_ARBURST  ;
wire                                 S_AXI_ARVALID  ;
wire                                 S_AXI_ARREADY  ;
wire [C_M_AXI_ID_WIDTH-1 : 0]        S_AXI_RID      ;
wire [C_M_AXI_DATA_WIDTH-1 : 0]      S_AXI_RDATA    ;
wire                                 S_AXI_RLAST    ;
wire                                 S_AXI_RVALID   ;
wire                                 S_AXI_RREADY   ;
wire [C_M_AXI_ID_WIDTH-1 : 0]        S_AXI_AWID     ;
wire [C_M_AXI_ADDR_WIDTH-1 : 0]      S_AXI_AWADDR   ;
wire [7 : 0]                         S_AXI_AWLEN    ;
wire [2 : 0]                         S_AXI_AWSIZE   ;
wire [1 : 0]                         S_AXI_AWBURST  ;
wire                                 S_AXI_AWVALID  ;
wire                                 S_AXI_AWREADY  ;
wire [AXIS_PCIE_DATA_WIDTH-1 : 0]    S_AXI_WDATA    ;
wire [AXIS_PCIE_DATA_WIDTH/8-1 : 0]  S_AXI_WSTRB    ;
wire                                 S_AXI_WLAST    ;
wire                                 S_AXI_WVALID   ;
wire                                 S_AXI_WREADY   ;
wire [C_M_AXI_ID_WIDTH-1 : 0]        S_AXI_BID      ;
wire                                 S_AXI_BVALID   ;
wire                                 S_AXI_BREADY   ;
wire [1 : 0]                         S_AXI_RRESP    ;
wire                                 S_AXI_ARLOCK   ;
wire [3 : 0]                         S_AXI_ARCACHE  ;
wire [2 : 0]                         S_AXI_ARPROT   ;
wire [3 : 0]                         S_AXI_ARQOS    ;
wire [C_M_AXI_ARUSER_WIDTH-1 : 0]    S_AXI_ARUSER   ;
wire [C_M_AXI_RUSER_WIDTH-1 : 0]     S_AXI_RUSER    ;
wire                                 S_AXI_AWLOCK   ;
wire [3 : 0]                         S_AXI_AWCACHE  ;
wire [2 : 0]                         S_AXI_AWPROT   ;
wire [3 : 0]                         S_AXI_AWQOS    ;
wire [C_M_AXI_AWUSER_WIDTH-1 : 0]    S_AXI_AWUSER   ;
wire [C_M_AXI_WUSER_WIDTH-1 : 0]     S_AXI_WUSER    ;
wire [1 : 0]                         S_AXI_BRESP    ;
wire [C_M_AXI_BUSER_WIDTH-1 : 0]     S_AXI_BUSER    ;

wire [C_M_AXI_ID_WIDTH-1 : 0]        M_AXI_ARID     ;
wire [C_M_AXI_ADDR_WIDTH-1 : 0]      M_AXI_ARADDR   ;
wire [7 : 0]                         M_AXI_ARLEN    ;
wire [2 : 0]                         M_AXI_ARSIZE   ;
wire [1 : 0]                         M_AXI_ARBURST  ;
wire                                 M_AXI_ARVALID  ;
wire                                 M_AXI_ARREADY  ;
wire [C_M_AXI_ID_WIDTH-1 : 0]        M_AXI_RID      ;
wire [C_M_AXI_DATA_WIDTH-1 : 0]      M_AXI_RDATA    ;
wire                                 M_AXI_RLAST    ;
wire                                 M_AXI_RVALID   ;
wire                                 M_AXI_RREADY   ;
wire [C_M_AXI_ID_WIDTH-1 : 0]        M_AXI_AWID     ;
wire [C_M_AXI_ADDR_WIDTH-1 : 0]      M_AXI_AWADDR   ;
wire [7 : 0]                         M_AXI_AWLEN    ;
wire [2 : 0]                         M_AXI_AWSIZE   ;
wire [1 : 0]                         M_AXI_AWBURST  ;
wire                                 M_AXI_AWVALID  ;
wire                                 M_AXI_AWREADY  ;
wire [AXIS_PCIE_DATA_WIDTH-1 : 0]    M_AXI_WDATA    ;
wire [AXIS_PCIE_DATA_WIDTH/8-1 : 0]  M_AXI_WSTRB    ;
wire                                 M_AXI_WLAST    ;
wire                                 M_AXI_WVALID   ;
wire                                 M_AXI_WREADY   ;
wire [C_M_AXI_ID_WIDTH-1 : 0]        M_AXI_BID      ;
wire                                 M_AXI_BVALID   ;
wire                                 M_AXI_BREADY   ;
wire [1 : 0]                         M_AXI_RRESP    ;
wire                                 M_AXI_ARLOCK   ;
wire [3 : 0]                         M_AXI_ARCACHE  ;
wire [2 : 0]                         M_AXI_ARPROT   ;
wire [3 : 0]                         M_AXI_ARQOS    ;
wire [C_M_AXI_ARUSER_WIDTH-1 : 0]    M_AXI_ARUSER   ;
wire [C_M_AXI_RUSER_WIDTH-1 : 0]     M_AXI_RUSER    ;
wire                                 M_AXI_AWLOCK   ;
wire [3 : 0]                         M_AXI_AWCACHE  ;
wire [2 : 0]                         M_AXI_AWPROT   ;
wire [3 : 0]                         M_AXI_AWQOS    ;
wire [C_M_AXI_AWUSER_WIDTH-1 : 0]    M_AXI_AWUSER   ;
wire [C_M_AXI_WUSER_WIDTH-1 : 0]     M_AXI_WUSER    ;
wire [1 : 0]                         M_AXI_BRESP    ;
wire [C_M_AXI_BUSER_WIDTH-1 : 0]     M_AXI_BUSER    ;

wire [3:0] M_AXI_AWREGION = 4'b0;
wire [3:0] M_AXI_ARREGION = 4'b0;
wire [3:0] S_AXI_AWREGION ;
wire [3:0] S_AXI_ARREGION ;

wire [C_M_AXI_DATA_WIDTH - 1 : 0]     S_AXIS_DMA_TDATA;
wire [C_M_AXI_DATA_WIDTH/8- 1 : 0]    S_AXIS_DMA_TKEEP;
wire                              S_AXIS_DMA_TVALID;     
wire                              S_AXIS_DMA_TLAST;
wire                              S_AXIS_DMA_TREADY;               
wire [C_M_AXI_DATA_WIDTH - 1 : 0]     M_AXIS_DMA_TDATA;
wire [C_M_AXI_DATA_WIDTH/8- 1 : 0]    M_AXIS_DMA_TKEEP;
wire                              M_AXIS_DMA_TVALID;     
wire                              M_AXIS_DMA_TLAST;
wire                              M_AXIS_DMA_TREADY = 1;    

wire st_end;

IBUFDS_GTE4 #(
    .REFCLK_HROW_CK_SEL(2'b00)
)
ibufds_gte4_pcie_mgt_refclk_inst (
    .I             (pcie_sys_clk_p),
    .IB            (pcie_sys_clk_n),
    .CEB           (1'b0),
    .O             (pcie_sys_clk_gt),
    .ODIV2         (pcie_sys_clk)
);

pcie4_uscale_plus_0 pcie_core (
    .pci_exp_txn(pcie_txn),
    .pci_exp_txp(pcie_txp),
    .pci_exp_rxn(pcie_rxn),
    .pci_exp_rxp(pcie_rxp),
    .user_clk(pcie_user_clk),
    .user_reset(pcie_user_reset),
    .user_lnk_up(),

    .s_axis_rq_tdata(axis_rq_tdata),
    .s_axis_rq_tkeep(axis_rq_tkeep),
    .s_axis_rq_tlast(axis_rq_tlast),
    .s_axis_rq_tready(axis_rq_tready),
    .s_axis_rq_tuser(axis_rq_tuser),
    .s_axis_rq_tvalid(axis_rq_tvalid),

    .m_axis_rc_tdata(axis_rc_tdata),
    .m_axis_rc_tkeep(axis_rc_tkeep),
    .m_axis_rc_tlast(axis_rc_tlast),
    .m_axis_rc_tready(axis_rc_tready),
    .m_axis_rc_tuser(axis_rc_tuser),
    .m_axis_rc_tvalid(axis_rc_tvalid),

    .m_axis_cq_tdata(axis_cq_tdata),
    .m_axis_cq_tkeep(axis_cq_tkeep),
    .m_axis_cq_tlast(axis_cq_tlast),
    .m_axis_cq_tready(axis_cq_tready),
    .m_axis_cq_tuser(axis_cq_tuser),
    .m_axis_cq_tvalid(axis_cq_tvalid),

    .s_axis_cc_tdata(axis_cc_tdata),
    .s_axis_cc_tkeep(axis_cc_tkeep),
    .s_axis_cc_tlast(axis_cc_tlast),
    .s_axis_cc_tready(axis_cc_tready),
    .s_axis_cc_tuser(axis_cc_tuser),
    .s_axis_cc_tvalid(axis_cc_tvalid),

    .pcie_rq_seq_num0(pcie_rq_seq_num0),
    .pcie_rq_seq_num_vld0(pcie_rq_seq_num_vld0),
    .pcie_rq_seq_num1(pcie_rq_seq_num1),
    .pcie_rq_seq_num_vld1(pcie_rq_seq_num_vld1),
    .pcie_rq_tag0(),
    .pcie_rq_tag1(),
    .pcie_rq_tag_av(),
    .pcie_rq_tag_vld0(),
    .pcie_rq_tag_vld1(),

    .pcie_tfc_nph_av(),
    .pcie_tfc_npd_av(),

    .pcie_cq_np_req(1'b1),
    .pcie_cq_np_req_count(),

    .cfg_phy_link_down(),
    .cfg_phy_link_status(),
    .cfg_negotiated_width(),
    .cfg_current_speed(),
    .cfg_max_payload(cfg_max_payload),
    .cfg_max_read_req(cfg_max_read_req),
    .cfg_function_status(),
    .cfg_function_power_state(),
    .cfg_vf_status(),
    .cfg_vf_power_state(),
    .cfg_link_power_state(),

    .cfg_mgmt_addr(cfg_mgmt_addr),
    .cfg_mgmt_function_number(cfg_mgmt_function_number),
    .cfg_mgmt_write(cfg_mgmt_write),
    .cfg_mgmt_write_data(cfg_mgmt_write_data),
    .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
    .cfg_mgmt_read(cfg_mgmt_read),
    .cfg_mgmt_read_data(cfg_mgmt_read_data),
    .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done),
    .cfg_mgmt_debug_access(1'b0),

    .cfg_err_cor_out(),
    .cfg_err_nonfatal_out(),
    .cfg_err_fatal_out(),
    .cfg_local_error_valid(),
    .cfg_local_error_out(),
    .cfg_ltssm_state(),
    .cfg_rx_pm_state(),
    .cfg_tx_pm_state(),
    .cfg_rcb_status(cfg_rcb_status),
    .cfg_obff_enable(),
    .cfg_pl_status_change(),
    .cfg_tph_requester_enable(),
    .cfg_tph_st_mode(),
    .cfg_vf_tph_requester_enable(),
    .cfg_vf_tph_st_mode(),

    .cfg_msg_received(),
    .cfg_msg_received_data(),
    .cfg_msg_received_type(),
    .cfg_msg_transmit(1'b0),
    .cfg_msg_transmit_type(3'd0),
    .cfg_msg_transmit_data(32'd0),
    .cfg_msg_transmit_done(),

    .cfg_fc_ph(cfg_fc_ph),
    .cfg_fc_pd(cfg_fc_pd),
    .cfg_fc_nph(cfg_fc_nph),
    .cfg_fc_npd(cfg_fc_npd),
    .cfg_fc_cplh(cfg_fc_cplh),
    .cfg_fc_cpld(cfg_fc_cpld),
    .cfg_fc_sel(cfg_fc_sel),

    .cfg_dsn(64'd0),

    .cfg_bus_number(cfg_bus_number),

    .cfg_power_state_change_ack(1'b1),
    .cfg_power_state_change_interrupt(),

    .cfg_err_cor_in(status_error_cor),
    .cfg_err_uncor_in(status_error_uncor),
    .cfg_flr_in_process(),
    .cfg_flr_done(4'd0),
    .cfg_vf_flr_in_process(),
    .cfg_vf_flr_func_num(8'd0),
    .cfg_vf_flr_done(8'd0),

    .cfg_link_training_enable(1'b1),

    .cfg_interrupt_int(4'd0),
    .cfg_interrupt_pending(4'd0),
    .cfg_interrupt_sent(),
    

//   .cfg_interrupt_msix_enable(cfg_interrupt_msix_enable),
//   .cfg_interrupt_msix_mask(cfg_interrupt_msix_mask),
//   .cfg_interrupt_msix_vf_enable(cfg_interrupt_msix_vf_enable),
//   .cfg_interrupt_msix_vf_mask(cfg_interrupt_msix_vf_mask),
//   .cfg_interrupt_msix_address(cfg_interrupt_msix_address),
//   .cfg_interrupt_msix_data(cfg_interrupt_msix_data),
//   .cfg_interrupt_msix_int(cfg_interrupt_msix_int),
//   .cfg_interrupt_msix_vec_pending(cfg_interrupt_msix_vec_pending),
//   .cfg_interrupt_msix_vec_pending_status(cfg_interrupt_msix_vec_pending_status),
//   .cfg_interrupt_msi_sent(cfg_interrupt_msix_sent),
//   .cfg_interrupt_msi_fail(cfg_interrupt_msix_fail),
//   .cfg_interrupt_msi_function_number(cfg_interrupt_msi_function_number),



  .cfg_interrupt_msi_enable(cfg_interrupt_msi_enable),                                             
  .cfg_interrupt_msi_mmenable(cfg_interrupt_msi_mmenable),                                        
  .cfg_interrupt_msi_mask_update(cfg_interrupt_msi_mask_update),                                  
  .cfg_interrupt_msi_data(cfg_interrupt_msi_data),                                                 
  .cfg_interrupt_msi_select(cfg_interrupt_msi_select),                                             
  .cfg_interrupt_msi_int(cfg_interrupt_msi_int),                                                  
  .cfg_interrupt_msi_pending_status(cfg_interrupt_msi_pending_status),                             
  .cfg_interrupt_msi_pending_status_data_enable(cfg_interrupt_msi_pending_status_data_enable),     
  .cfg_interrupt_msi_pending_status_function_num(cfg_interrupt_msi_pending_status_function_num),   
  .cfg_interrupt_msi_sent(cfg_interrupt_msi_sent),                                                 
  .cfg_interrupt_msi_fail(cfg_interrupt_msi_fail),                                                 
  .cfg_interrupt_msi_attr(cfg_interrupt_msi_attr),                                                 
  .cfg_interrupt_msi_tph_present(cfg_interrupt_msi_tph_present),                                   
  .cfg_interrupt_msi_tph_type(cfg_interrupt_msi_tph_type),                                         
  .cfg_interrupt_msi_tph_st_tag(cfg_interrupt_msi_tph_st_tag),                                     
  .cfg_interrupt_msi_function_number(cfg_interrupt_msi_function_number),      
                    
 
    
    .cfg_pm_aspm_l1_entry_reject(1'b0),
    .cfg_pm_aspm_tx_l0s_entry_disable(1'b0),

    .cfg_hot_reset_out(),

    .cfg_config_space_enable(1'b1),
    .cfg_req_pm_transition_l23_ready(1'b0),
    .cfg_hot_reset_in(1'b0),

    .cfg_ds_port_number(8'd0),
    .cfg_ds_bus_number(8'd0),
    .cfg_ds_device_number(5'd0),

    .sys_clk(pcie_sys_clk),
    .sys_clk_gt(pcie_sys_clk_gt),
    .sys_reset(pcie_sys_rst_n),

    .phy_rdy_out()
);



fpga_core #(
    .AXIS_PCIE_DATA_WIDTH       (AXIS_PCIE_DATA_WIDTH),
    .RQ_SEQ_NUM_ENABLE          (1  ),
    .PCIE_TAG_COUNT             (PCIE_TAG_COUNT ),

    .BAR_ADDRESS_MODE           (32 ),
    .PCIe_to_AXI_Lite_Interface (0),
    .PF0_BAR0_ENABLE(1),
    .PF0_BAR1_ENABLE(1),
    .PF0_BAR2_ENABLE(0),
    .PF0_BAR3_ENABLE(0),
    .PF0_BAR4_ENABLE(0),
    .PF0_BAR5_ENABLE(0),

    .MSI_COUNT                  (1),
    .USER_MSI_IRQ               (USER_MSI_IRQ_EX),

    .DMA_INTERFACE_MODE         (DMA_INTERFACE_MODE),
    .DMA_MODE                   (DMA_MODE),
    .AXI_ADDR_WIDTH             (C_M_AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH               (C_M_AXI_ID_WIDTH),
    .AXI_DATA_WIDTH             (C_M_AXI_DATA_WIDTH),

    .AXIL_CTRL_ADDR_WIDTH       (32)
)PFDMA_core(
    .clk  	(pcie_user_clk  ),
    .rst  	(pcie_user_reset),

    .M_AXI_ARID        (M_AXI_ARID        ),
    .M_AXI_ARADDR      (M_AXI_ARADDR      ),
    .M_AXI_ARLEN       (M_AXI_ARLEN       ),
    .M_AXI_ARSIZE      (M_AXI_ARSIZE      ),
    .M_AXI_ARBURST     (M_AXI_ARBURST     ),
    .M_AXI_ARLOCK      (M_AXI_ARLOCK      ),
    .M_AXI_ARCACHE     (M_AXI_ARCACHE     ),
    .M_AXI_ARPROT      (M_AXI_ARPROT      ),
    .M_AXI_ARQOS       (M_AXI_ARQOS       ),
    .M_AXI_ARVALID     (M_AXI_ARVALID     ),
    .M_AXI_ARREADY     (M_AXI_ARREADY     ),
    .M_AXI_RID         (M_AXI_RID         ),
    .M_AXI_RDATA       (M_AXI_RDATA       ),
    .M_AXI_RRESP       (M_AXI_RRESP       ),
    .M_AXI_RLAST       (M_AXI_RLAST       ),
    .M_AXI_RVALID      (M_AXI_RVALID      ),
    .M_AXI_RREADY      (M_AXI_RREADY      ),
    .M_AXI_AWID        (M_AXI_AWID        ),
    .M_AXI_AWADDR      (M_AXI_AWADDR      ),
    .M_AXI_AWLEN       (M_AXI_AWLEN       ),
    .M_AXI_AWSIZE      (M_AXI_AWSIZE      ),
    .M_AXI_AWBURST     (M_AXI_AWBURST     ),
    .M_AXI_AWLOCK      (M_AXI_AWLOCK      ),
    .M_AXI_AWCACHE     (M_AXI_AWCACHE     ),
    .M_AXI_AWPROT      (M_AXI_AWPROT      ),
    .M_AXI_AWQOS       (M_AXI_AWQOS       ),
    .M_AXI_AWVALID     (M_AXI_AWVALID     ),
    .M_AXI_AWREADY     (M_AXI_AWREADY     ),
    .M_AXI_WDATA       (M_AXI_WDATA       ),
    .M_AXI_WSTRB       (M_AXI_WSTRB       ),
    .M_AXI_WLAST       (M_AXI_WLAST       ),
    .M_AXI_WVALID      (M_AXI_WVALID      ),
    .M_AXI_WREADY      (M_AXI_WREADY      ),
    .M_AXI_BID         (M_AXI_BID         ),
    .M_AXI_BRESP       (M_AXI_BRESP       ),
    .M_AXI_BVALID      (M_AXI_BVALID      ),
    .M_AXI_BREADY      (M_AXI_BREADY      ),

    .S_AXIS_DMA_TDATA  (S_AXIS_DMA_TDATA  ),
    .S_AXIS_DMA_TKEEP  (S_AXIS_DMA_TKEEP  ),
    .S_AXIS_DMA_TVALID (S_AXIS_DMA_TVALID ),     
    .S_AXIS_DMA_TLAST  (S_AXIS_DMA_TLAST  ),
    .S_AXIS_DMA_TREADY (S_AXIS_DMA_TREADY ),               
    .M_AXIS_DMA_TDATA  (M_AXIS_DMA_TDATA  ),
    .M_AXIS_DMA_TKEEP  (M_AXIS_DMA_TKEEP  ),
    .M_AXIS_DMA_TVALID (M_AXIS_DMA_TVALID ),     
    .M_AXIS_DMA_TLAST  (M_AXIS_DMA_TLAST  ),
    .M_AXIS_DMA_TREADY (M_AXIS_DMA_TREADY ), 

    .M_AXI_Lite_AWADDR  (),
    .M_AXI_Lite_AWPROT  (),
    .M_AXI_Lite_AWVALID (),
    .M_AXI_Lite_AWREADY (),
    .M_AXI_Lite_WDATA   (),
    .M_AXI_Lite_WSTRB   (),
    .M_AXI_Lite_WVALID  (),
    .M_AXI_Lite_WREADY  (),
    .M_AXI_Lite_BRESP   (),
    .M_AXI_Lite_BVALID  (),
    .M_AXI_Lite_BREADY  (),
    .M_AXI_Lite_ARADDR  (),
    .M_AXI_Lite_ARPROT  (),
    .M_AXI_Lite_ARVALID (),
    .M_AXI_Lite_ARREADY (),
    .M_AXI_Lite_RDATA   (),
    .M_AXI_Lite_RRESP   (),
    .M_AXI_Lite_RVALID  (),
    .M_AXI_Lite_RREADY  (),

    .m_axis_rq_tdata    (axis_rq_tdata       ),
    .m_axis_rq_tkeep    (axis_rq_tkeep       ),
    .m_axis_rq_tlast    (axis_rq_tlast       ),
    .m_axis_rq_tready   (axis_rq_tready      ),
    .m_axis_rq_tuser    (axis_rq_tuser       ),
    .m_axis_rq_tvalid   (axis_rq_tvalid      ),
    .s_axis_rc_tdata    (axis_rc_tdata       ),
    .s_axis_rc_tkeep    (axis_rc_tkeep       ),
    .s_axis_rc_tlast    (axis_rc_tlast       ),
    .s_axis_rc_tready   (axis_rc_tready      ),
    .s_axis_rc_tuser    (axis_rc_tuser       ),
    .s_axis_rc_tvalid   (axis_rc_tvalid      ),
    .s_axis_cq_tdata    (axis_cq_tdata       ),
    .s_axis_cq_tkeep    (axis_cq_tkeep       ),
    .s_axis_cq_tlast    (axis_cq_tlast       ),
    .s_axis_cq_tready   (axis_cq_tready      ),
    .s_axis_cq_tuser    (axis_cq_tuser       ),
    .s_axis_cq_tvalid   (axis_cq_tvalid      ),
    .m_axis_cc_tdata    (axis_cc_tdata       ),
    .m_axis_cc_tkeep    (axis_cc_tkeep       ),
    .m_axis_cc_tlast    (axis_cc_tlast       ),
    .m_axis_cc_tready   (axis_cc_tready      ),
    .m_axis_cc_tuser    (axis_cc_tuser       ),
    .m_axis_cc_tvalid   (axis_cc_tvalid      ),
    .s_axis_rq_seq_num_0         (pcie_rq_seq_num0),
    .s_axis_rq_seq_num_valid_0   (pcie_rq_seq_num_vld0),
    .s_axis_rq_seq_num_1         (pcie_rq_seq_num1),
    .s_axis_rq_seq_num_valid_1   (pcie_rq_seq_num_vld1),

    .cfg_max_payload      	(cfg_max_payload   ),
    .cfg_max_read_req     	(cfg_max_read_req  ),
    .cfg_rcb_status       	(cfg_rcb_status    ),
    .cfg_bus_number         (cfg_bus_number),

    .cfg_mgmt_addr             	(cfg_mgmt_addr              ),
    .cfg_mgmt_function_number  	(cfg_mgmt_function_number   ),
    .cfg_mgmt_write            	(cfg_mgmt_write             ),
    .cfg_mgmt_write_data       	(cfg_mgmt_write_data        ),
    .cfg_mgmt_byte_enable      	(cfg_mgmt_byte_enable       ),
    .cfg_mgmt_read             	(cfg_mgmt_read              ),
    .cfg_mgmt_read_data        	(cfg_mgmt_read_data         ),
    .cfg_mgmt_read_write_done  	(cfg_mgmt_read_write_done   ),

    .cfg_fc_ph      	(cfg_fc_ph      ),
    .cfg_fc_pd      	(cfg_fc_pd      ),
    .cfg_fc_nph     	(cfg_fc_nph     ),
    .cfg_fc_npd     	(cfg_fc_npd     ),
    .cfg_fc_cplh    	(cfg_fc_cplh    ),
    .cfg_fc_cpld    	(cfg_fc_cpld    ),
    .cfg_fc_sel     	(cfg_fc_sel     ),

    .cfg_interrupt_msix_enable             	(cfg_interrupt_msix_enable              ),
    .cfg_interrupt_msix_mask               	(cfg_interrupt_msix_mask                ),
    .cfg_interrupt_msix_vf_enable          	(cfg_interrupt_msix_vf_enable           ),
    .cfg_interrupt_msix_vf_mask            	(cfg_interrupt_msix_vf_mask             ),
    .cfg_interrupt_msix_address            	(cfg_interrupt_msix_address             ),
    .cfg_interrupt_msix_data               	(cfg_interrupt_msix_data                ),
    .cfg_interrupt_msix_int                	(cfg_interrupt_msix_int                 ),
    .cfg_interrupt_msix_vec_pending        	(cfg_interrupt_msix_vec_pending         ),
    .cfg_interrupt_msix_vec_pending_status 	(cfg_interrupt_msix_vec_pending_status  ),
    .cfg_interrupt_msix_sent               	(cfg_interrupt_msix_sent                ),
    .cfg_interrupt_msix_fail               	(cfg_interrupt_msix_fail                ),
    .cfg_interrupt_msi_function_number     	(cfg_interrupt_msi_function_number      ),
    
    .cfg_interrupt_msi_enable       (cfg_interrupt_msi_enable),
    .cfg_interrupt_msi_mmenable     (cfg_interrupt_msi_mmenable),
    .cfg_interrupt_msi_mask_update  (cfg_interrupt_msi_mask_update),
    .cfg_interrupt_msi_data         (cfg_interrupt_msi_data),
    .cfg_interrupt_msi_select       (cfg_interrupt_msi_select),
    .cfg_interrupt_msi_int          (cfg_interrupt_msi_int),
    .cfg_interrupt_msi_pending_status(cfg_interrupt_msi_pending_status),
    .cfg_interrupt_msi_pending_status_data_enable(cfg_interrupt_msi_pending_status_data_enable),
    .cfg_interrupt_msi_pending_status_function_num(cfg_interrupt_msi_pending_status_function_num),
    .cfg_interrupt_msi_sent         (cfg_interrupt_msi_sent),
    .cfg_interrupt_msi_fail         (cfg_interrupt_msi_fail),
    .cfg_interrupt_msi_attr         (cfg_interrupt_msi_attr),
    .cfg_interrupt_msi_tph_present  (cfg_interrupt_msi_tph_present),
    .cfg_interrupt_msi_tph_type     (cfg_interrupt_msi_tph_type),
    .cfg_interrupt_msi_tph_st_tag   (cfg_interrupt_msi_tph_st_tag),

    .msi_irq                        (user_msi_irq),
  
    .status_error_cor                      	(status_error_cor                       ),
    .status_error_uncor                    	(status_error_uncor                     )
);



send_axis #(
    .STREAM_TDATA_WIDTH 	(AXIS_PCIE_DATA_WIDTH  )
)axis_generate(
    .m_axis_aclk    	(pcie_user_clk   ),
    .m_axis_aresetn 	(~pcie_user_reset),
    .st_length      	(PFDMA_core.C2H_SgDMA_length         ),
    .st_start       	(PFDMA_core.C2H_SgDMA_Start          ),
    .st_end (st_end),
    .m_axis_tdata   	(S_AXIS_DMA_TDATA    ),
    .m_axis_tkeep   	(S_AXIS_DMA_TKEEP    ),
    .m_axis_tlast   	(S_AXIS_DMA_TLAST    ),
    .m_axis_tvalid  	(S_AXIS_DMA_TVALID   ),
    .m_axis_tready  	(S_AXIS_DMA_TREADY   )
);


        

    
pcie_to_mifg_if clock_convert_if (
    .s_axi_aclk       (pcie_user_clk      ),          
    .s_axi_aresetn    (~pcie_user_reset   ),    
    .s_axi_awaddr     (M_AXI_AWADDR   ),      
    .s_axi_awlen      (M_AXI_AWLEN    ),        
    .s_axi_awsize     (M_AXI_AWSIZE   ),      
    .s_axi_awburst    (M_AXI_AWBURST  ),    
    .s_axi_awlock     (M_AXI_AWLOCK   ),      
    .s_axi_awcache    (M_AXI_AWCACHE  ),    
    .s_axi_awid       (M_AXI_AWID     ),
    .s_axi_bid        (M_AXI_BID      ),
    .s_axi_awprot     (M_AXI_AWPROT   ),      
    .s_axi_awregion   (M_AXI_AWREGION ),  
    .s_axi_awqos      (M_AXI_AWQOS    ),        
    .s_axi_awvalid    (M_AXI_AWVALID  ),    
    .s_axi_awready    (M_AXI_AWREADY  ),    
    .s_axi_wdata      (M_AXI_WDATA    ),        
    .s_axi_wstrb      (M_AXI_WSTRB    ),        
    .s_axi_wlast      (M_AXI_WLAST    ),        
    .s_axi_wvalid     (M_AXI_WVALID   ),      
    .s_axi_wready     (M_AXI_WREADY   ),      
    .s_axi_bresp      (M_AXI_BRESP    ),        
    .s_axi_bvalid     (M_AXI_BVALID   ),      
    .s_axi_bready     (M_AXI_BREADY   ),      
    .s_axi_araddr     (M_AXI_ARADDR   ),      
    .s_axi_arlen      (M_AXI_ARLEN    ),        
    .s_axi_arsize     (M_AXI_ARSIZE   ),      
    .s_axi_arburst    (M_AXI_ARBURST  ),    
    .s_axi_arlock     (M_AXI_ARLOCK   ),      
    .s_axi_arcache    (M_AXI_ARCACHE  ),    
    .s_axi_arprot     (M_AXI_ARPROT   ),      
    .s_axi_arregion   (M_AXI_ARREGION ),  
    .s_axi_arqos      (M_AXI_ARQOS    ),        
    .s_axi_arvalid    (M_AXI_ARVALID  ),    
    .s_axi_arready    (M_AXI_ARREADY  ),    
    .s_axi_arid       (M_AXI_ARID     ),
    .s_axi_rid        (M_AXI_RID      ),
    .s_axi_rdata      (M_AXI_RDATA    ),        
    .s_axi_rresp      (M_AXI_RRESP    ),        
    .s_axi_rlast      (M_AXI_RLAST    ),        
    .s_axi_rvalid     (M_AXI_RVALID   ),      
    .s_axi_rready     (M_AXI_RREADY   ), 
    .m_axi_aclk       (c0_ddr4_ui_clk     ),          
    .m_axi_aresetn    (c0_ddr4_aresetn    ),   
    .m_axi_awaddr     (S_AXI_AWADDR   ),      
    .m_axi_awlen      (S_AXI_AWLEN    ),        
    .m_axi_awsize     (S_AXI_AWSIZE   ),      
    .m_axi_awburst    (S_AXI_AWBURST  ),    
    .m_axi_awlock     (S_AXI_AWLOCK   ),      
    .m_axi_awcache    (S_AXI_AWCACHE  ),    
    .m_axi_awprot     (S_AXI_AWPROT   ),      
    .m_axi_awregion   (S_AXI_AWREGION ),  
    .m_axi_awqos      (S_AXI_AWQOS    ),        
    .m_axi_awvalid    (S_AXI_AWVALID  ),    
    .m_axi_awid       (S_AXI_AWID     ),
    .m_axi_bid        (S_AXI_BID      ),
    .m_axi_awready    (S_AXI_AWREADY  ),    
    .m_axi_wdata      (S_AXI_WDATA    ),        
    .m_axi_wstrb      (S_AXI_WSTRB    ),        
    .m_axi_wlast      (S_AXI_WLAST    ),        
    .m_axi_wvalid     (S_AXI_WVALID   ),      
    .m_axi_wready     (S_AXI_WREADY   ),      
    .m_axi_bresp      (S_AXI_BRESP    ),       
    .m_axi_bvalid     (S_AXI_BVALID   ),      
    .m_axi_bready     (S_AXI_BREADY   ),      
    .m_axi_araddr     (S_AXI_ARADDR   ),      
    .m_axi_arlen      (S_AXI_ARLEN    ),        
    .m_axi_arsize     (S_AXI_ARSIZE   ),      
    .m_axi_arburst    (S_AXI_ARBURST  ),    
    .m_axi_arlock     (S_AXI_ARLOCK   ),      
    .m_axi_arcache    (S_AXI_ARCACHE  ),    
    .m_axi_arprot     (S_AXI_ARPROT   ),      
    .m_axi_arregion   (S_AXI_ARREGION ),  
    .m_axi_arqos      (S_AXI_ARQOS    ),        
    .m_axi_arid       (S_AXI_ARID     ),
    .m_axi_rid        (S_AXI_RID      ),
    .m_axi_arvalid    (S_AXI_ARVALID  ),    
    .m_axi_arready    (S_AXI_ARREADY  ),    
    .m_axi_rdata      (S_AXI_RDATA    ),        
    .m_axi_rresp      (S_AXI_RRESP    ),        
    .m_axi_rlast      (S_AXI_RLAST    ),        
    .m_axi_rvalid     (S_AXI_RVALID   ),      
    .m_axi_rready     (S_AXI_RREADY   )      
);

    
ddr4_0 sdram (
    .c0_init_calib_complete   (),    
    .dbg_clk                  (),                                                        
    .dbg_bus                  (),      
    .c0_sys_clk_p             (c0_sys_clk_p          ),                        
    .c0_sys_clk_n             (c0_sys_clk_n          ),                              
    .c0_ddr4_adr              (ddr4_c0_adr           ),                          
    .c0_ddr4_ba               (ddr4_c0_ba            ),                            
    .c0_ddr4_cke              (ddr4_c0_cke           ),                          
    .c0_ddr4_cs_n             (ddr4_c0_cs_n          ),                        
    .c0_ddr4_dm_dbi_n         (ddr4_c0_dm_dbi_n      ),                
    .c0_ddr4_dq               (ddr4_c0_dq            ),                            
    .c0_ddr4_dqs_c            (ddr4_c0_dqs_c         ),                      
    .c0_ddr4_dqs_t            (ddr4_c0_dqs_t         ),                      
    .c0_ddr4_odt              (ddr4_c0_odt           ),                          
    .c0_ddr4_bg               (ddr4_c0_bg            ),                            
    .c0_ddr4_reset_n          (ddr4_c0_reset_n       ),                  
    .c0_ddr4_act_n            (ddr4_c0_act_n         ),                      
    .c0_ddr4_ck_c             (ddr4_c0_ck_c          ),                        
    .c0_ddr4_ck_t             (ddr4_c0_ck_t          ),     
    .c0_ddr4_ui_clk           (c0_ddr4_ui_clk         ),                    
    .c0_ddr4_ui_clk_sync_rst  (c0_ddr4_ui_clk_sync_rst),  
    .c0_ddr4_aresetn          (c0_ddr4_aresetn),    
    .c0_ddr4_s_axi_awid       (S_AXI_AWID    ),            
    .c0_ddr4_s_axi_awaddr     (S_AXI_AWADDR  ),        
    .c0_ddr4_s_axi_awlen      (S_AXI_AWLEN   ),          
    .c0_ddr4_s_axi_awsize     (S_AXI_AWSIZE  ),        
    .c0_ddr4_s_axi_awburst    (S_AXI_AWBURST ),      
    .c0_ddr4_s_axi_awlock     (S_AXI_AWLOCK  ),        
    .c0_ddr4_s_axi_awcache    (S_AXI_AWCACHE ),      
    .c0_ddr4_s_axi_awprot     (S_AXI_AWPROT  ),   
    .c0_ddr4_s_axi_awqos      (S_AXI_AWQOS   ),          
    .c0_ddr4_s_axi_awvalid    (S_AXI_AWVALID ),      
    .c0_ddr4_s_axi_awready    (S_AXI_AWREADY ),      
    .c0_ddr4_s_axi_wdata      (S_AXI_WDATA   ),          
    .c0_ddr4_s_axi_wstrb      (S_AXI_WSTRB   ),          
    .c0_ddr4_s_axi_wlast      (S_AXI_WLAST   ),          
    .c0_ddr4_s_axi_wvalid     (S_AXI_WVALID  ),        
    .c0_ddr4_s_axi_wready     (S_AXI_WREADY  ),        
    .c0_ddr4_s_axi_bready     (S_AXI_BREADY  ),        
    .c0_ddr4_s_axi_bid        (S_AXI_BID     ),              
    .c0_ddr4_s_axi_bresp      (S_AXI_BRESP   ),          
    .c0_ddr4_s_axi_bvalid     (S_AXI_BVALID  ),     
    .c0_ddr4_s_axi_arid       (S_AXI_ARID    ),            
    .c0_ddr4_s_axi_araddr     (S_AXI_ARADDR  ),        
    .c0_ddr4_s_axi_arlen      (S_AXI_ARLEN   ),          
    .c0_ddr4_s_axi_arsize     (S_AXI_ARSIZE  ),        
    .c0_ddr4_s_axi_arburst    (S_AXI_ARBURST ),      
    .c0_ddr4_s_axi_arlock     (S_AXI_ARLOCK  ),        
    .c0_ddr4_s_axi_arcache    (S_AXI_ARCACHE ),    
    .c0_ddr4_s_axi_arprot     (S_AXI_ARPROT  ),        
    .c0_ddr4_s_axi_arqos      (S_AXI_ARQOS   ),          
    .c0_ddr4_s_axi_arvalid    (S_AXI_ARVALID ),      
    .c0_ddr4_s_axi_arready    (S_AXI_ARREADY ),      
    .c0_ddr4_s_axi_rready     (S_AXI_RREADY  ),        
    .c0_ddr4_s_axi_rlast      (S_AXI_RLAST   ),          
    .c0_ddr4_s_axi_rvalid     (S_AXI_RVALID  ),        
    .c0_ddr4_s_axi_rresp      (S_AXI_RRESP   ),          
    .c0_ddr4_s_axi_rid        (S_AXI_RID     ),              
    .c0_ddr4_s_axi_rdata      (S_AXI_RDATA   ),   
    .sys_rst                  (1'b0)    
);                              
    

endmodule
`resetall