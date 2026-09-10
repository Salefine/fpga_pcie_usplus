/****************************************************************************
 * @file    fpga_core.v
 * @brief  
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2026-03-18
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    zzhi          |                        |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2026 zzhi
 * ***************************************************************************/


`resetall
`timescale 1ns/1ps
`include "sg_block_dma.vh"
`default_nettype none

module fpga_core#(
    /*
     * pcie core parameter
     */
    parameter AXIS_PCIE_DATA_WIDTH      = 512,
    parameter RQ_SEQ_NUM_ENABLE         = 1,
    parameter PCIE_TAG_COUNT            = 256,
    parameter AXIS_PCIE_KEEP_WIDTH      = (AXIS_PCIE_DATA_WIDTH/32),
    parameter AXIS_PCIE_RC_USER_WIDTH   = AXIS_PCIE_DATA_WIDTH < 512 ? 75 : 161,
    parameter AXIS_PCIE_RQ_USER_WIDTH   = AXIS_PCIE_DATA_WIDTH < 512 ? 60 : 137,
    parameter AXIS_PCIE_CQ_USER_WIDTH   = AXIS_PCIE_DATA_WIDTH < 512 ? 85 : 183,
    parameter AXIS_PCIE_CC_USER_WIDTH   = AXIS_PCIE_DATA_WIDTH < 512 ? 33 : 81,
    parameter RC_STRADDLE               = AXIS_PCIE_DATA_WIDTH >= 256,
    parameter RQ_STRADDLE               = AXIS_PCIE_DATA_WIDTH >= 512,
    parameter CQ_STRADDLE               = AXIS_PCIE_DATA_WIDTH >= 512,
    parameter CC_STRADDLE               = AXIS_PCIE_DATA_WIDTH >= 512,
    parameter RQ_SEQ_NUM_WIDTH          = AXIS_PCIE_RQ_USER_WIDTH == 60 ? 4 : 6,

    /*
     * bar's config
     */
    parameter BAR_ADDRESS_MODE          = 32,
    parameter PCIe_to_AXI_Lite_Interface= 1,
    parameter PF0_BAR0_ENABLE           = 1,
    parameter PF0_BAR1_ENABLE           = 1,
    parameter PF0_BAR2_ENABLE           = 0,
    parameter PF0_BAR3_ENABLE           = 0,
    parameter PF0_BAR4_ENABLE           = 0, 
    parameter PF0_BAR5_ENABLE           = 0,

    /*
     * MSI_COUNT : PCIe function MSI vectors allocated by config (1..32).
     * USER_MSI_IRQ : user interrupt lines into dma_intr_queue (>=1). Total
     * request sources = 4 (block C2H/H2C + SG mm2s/s2mm) + USER_MSI_IRQ.
     */
    parameter MSI_COUNT                 = 1 ,
    parameter USER_MSI_IRQ              = 4 ,

    /*
     * user add logic for AXI bus
     */
    parameter DMA_MODE                  = "Scatter_Gather", //Block_DMA or Scather_Gather
    parameter DMA_INTERFACE_MODE        = "AXI4-Stream"    , // AXI_MEMORY_MAP or AXI4-Stream
    parameter Lane_Width                = "x16", //x16 x8 x4 x1
    parameter Maximum_Link_Speed        = "8.0GT/s", //8.0 GT/s, 5.0 GT/s,2.5 GT/s
    parameter AXI_DATA_WIDTH            = 512,
    parameter AXI_STRB_WIDTH            = AXI_DATA_WIDTH / 8,
    parameter AXI_MAX_BURST_LEN         = 64,
    parameter AXI_Clock_Frequency       = 250,
    parameter AXI_ADDR_WIDTH            = 32, //user modify
    parameter AXI_ID_WIDTH              = 8,

    /*
     * Bar to axi lite interface
     */
    parameter AXIL_CTRL_ADDR_WIDTH    = 32, //user modify
    parameter [AXIL_CTRL_ADDR_WIDTH-1:0]PCIe_to_AXI_Translation = 'h0,
    parameter AXIL_CTRL_DATA_WIDTH    = 32, // do not modify
    parameter AXIL_CTRL_STRB_WIDTH    = AXIL_CTRL_DATA_WIDTH / 8

//    parameter DEBUG_CORE = 1
)(
    /*
     * Clock: 250 MHz
     * Synchronous reset
     */
    input  wire    clk,
    input  wire    rst,

    /*
     * DMA interface for axi full
     */

	output wire [AXI_ID_WIDTH-1 : 0]        M_AXI_ARID      ,
	output wire [AXI_ADDR_WIDTH-1 : 0]      M_AXI_ARADDR    ,
	output wire [7 : 0]                     M_AXI_ARLEN     ,
	output wire [2 : 0]                     M_AXI_ARSIZE    ,
	output wire [1 : 0]                     M_AXI_ARBURST   ,
	output wire                             M_AXI_ARLOCK    ,
	output wire [3 : 0]                     M_AXI_ARCACHE   ,
	output wire [2 : 0]                     M_AXI_ARPROT    ,
	output wire [3 : 0]                     M_AXI_ARQOS     ,
	output wire                             M_AXI_ARVALID   ,
	input wire                              M_AXI_ARREADY   ,
	input wire [AXI_ID_WIDTH-1 : 0]         M_AXI_RID       ,
	input wire [AXI_DATA_WIDTH-1 : 0]       M_AXI_RDATA     ,
	input wire [1 : 0]                      M_AXI_RRESP     ,
	input wire                              M_AXI_RLAST     ,
	input wire                              M_AXI_RVALID    ,
	output wire                             M_AXI_RREADY    ,
	output wire [AXI_ID_WIDTH-1 : 0]        M_AXI_AWID   ,
	output wire [AXI_ADDR_WIDTH-1 : 0]      M_AXI_AWADDR ,
	output wire [7 : 0]                     M_AXI_AWLEN  ,
	output wire [2 : 0]                     M_AXI_AWSIZE ,
	output wire [1 : 0]                     M_AXI_AWBURST,
	output wire                             M_AXI_AWLOCK ,
	output wire [3 : 0]                     M_AXI_AWCACHE,
    output wire [2 : 0]                     M_AXI_AWPROT ,
    output wire [3 : 0]                     M_AXI_AWQOS  ,
	output wire                             M_AXI_AWVALID,
	input  wire                             M_AXI_AWREADY,
	output wire [AXI_DATA_WIDTH-1 : 0]      M_AXI_WDATA,
    output wire [AXI_DATA_WIDTH/8-1 : 0]    M_AXI_WSTRB,
    output wire                             M_AXI_WLAST,
	output wire                             M_AXI_WVALID,
	input wire                              M_AXI_WREADY,
	input wire [AXI_ID_WIDTH-1 : 0]         M_AXI_BID,
	input wire [1 : 0]                      M_AXI_BRESP,
	input wire                              M_AXI_BVALID,
	output wire                             M_AXI_BREADY,

    /*
     * DMA interface for axi stream
     */
    input wire [AXI_DATA_WIDTH - 1 : 0]     S_AXIS_DMA_TDATA,
    input wire [AXI_DATA_WIDTH/8- 1 : 0]    S_AXIS_DMA_TKEEP,
    input wire                              S_AXIS_DMA_TVALID,     
    input wire                              S_AXIS_DMA_TLAST,
    output wire                             S_AXIS_DMA_TREADY,               

    output wire [AXI_DATA_WIDTH - 1 : 0]    M_AXIS_DMA_TDATA,
    output wire [AXI_DATA_WIDTH/8- 1 : 0]   M_AXIS_DMA_TKEEP,
    output wire                             M_AXIS_DMA_TVALID,     
    output wire                             M_AXIS_DMA_TLAST,
    input  wire                             M_AXIS_DMA_TREADY,          

    /*
     * bar to axi lite interface
     */
    output wire [AXIL_CTRL_ADDR_WIDTH-1:0]  M_AXI_Lite_AWADDR  ,
    output wire [2:0]                       M_AXI_Lite_AWPROT  ,
    output wire                             M_AXI_Lite_AWVALID ,
    input  wire                             M_AXI_Lite_AWREADY ,
    output wire [AXIL_CTRL_DATA_WIDTH-1:0]  M_AXI_Lite_WDATA   ,
    output wire [AXIL_CTRL_STRB_WIDTH-1:0]  M_AXI_Lite_WSTRB   ,
    output wire                             M_AXI_Lite_WVALID  ,
    input  wire                             M_AXI_Lite_WREADY  ,
    input  wire [1:0]                       M_AXI_Lite_BRESP   ,
    input  wire                             M_AXI_Lite_BVALID  ,
    output wire                             M_AXI_Lite_BREADY  ,
    output wire [AXIL_CTRL_ADDR_WIDTH-1:0]  M_AXI_Lite_ARADDR  ,
    output wire [2:0]                       M_AXI_Lite_ARPROT  ,
    output wire                             M_AXI_Lite_ARVALID ,
    input  wire                             M_AXI_Lite_ARREADY ,
    input  wire [AXIL_CTRL_DATA_WIDTH-1:0]  M_AXI_Lite_RDATA   ,
    input  wire [1:0]                       M_AXI_Lite_RRESP   ,
    input  wire                             M_AXI_Lite_RVALID  ,
    output wire                             M_AXI_Lite_RREADY  ,

    /*
     * PCIe
     */
    output wire [AXIS_PCIE_DATA_WIDTH-1:0]    m_axis_rq_tdata,
    output wire [AXIS_PCIE_KEEP_WIDTH-1:0]    m_axis_rq_tkeep,
    output wire                               m_axis_rq_tlast,
    input  wire                               m_axis_rq_tready,
    output wire [AXIS_PCIE_RQ_USER_WIDTH-1:0] m_axis_rq_tuser,
    output wire                               m_axis_rq_tvalid,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]    s_axis_rc_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]    s_axis_rc_tkeep,
    input  wire                               s_axis_rc_tlast,
    output wire                               s_axis_rc_tready,
    input  wire [AXIS_PCIE_RC_USER_WIDTH-1:0] s_axis_rc_tuser,
    input  wire                               s_axis_rc_tvalid,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]    s_axis_cq_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]    s_axis_cq_tkeep,
    input  wire                               s_axis_cq_tlast,
    output wire                               s_axis_cq_tready,
    input  wire [AXIS_PCIE_CQ_USER_WIDTH-1:0] s_axis_cq_tuser,
    input  wire                               s_axis_cq_tvalid,

    output wire [AXIS_PCIE_DATA_WIDTH-1:0]    m_axis_cc_tdata,
    output wire [AXIS_PCIE_KEEP_WIDTH-1:0]    m_axis_cc_tkeep,
    output wire                               m_axis_cc_tlast,
    input  wire                               m_axis_cc_tready,
    output wire [AXIS_PCIE_CC_USER_WIDTH-1:0] m_axis_cc_tuser,
    output wire                               m_axis_cc_tvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_status:1.0 pcie4_cfg_status rq_seq_num0" *)
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]        s_axis_rq_seq_num_0,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_status:1.0 pcie4_cfg_status rq_seq_num_vld0" *)
    input  wire                               s_axis_rq_seq_num_valid_0,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_status:1.0 pcie4_cfg_status rq_seq_num1" *)
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]        s_axis_rq_seq_num_1,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_status:1.0 pcie4_cfg_status rq_seq_num_vld1" *)
    input  wire                               s_axis_rq_seq_num_valid_1,

    //max payload size 

    input  wire [2:0]                         cfg_max_payload ,

    input  wire [2:0]                         cfg_max_read_req,

    input  wire [3:0]                         cfg_rcb_status  ,

    input  wire [7:0]                         cfg_bus_number  ,

    //config management interface
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_mgmt:1.0 pcie4_cfg_mgmt ADDR" *)
    output wire [9:0]                         cfg_mgmt_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_mgmt:1.0 pcie4_cfg_mgmt FUNCTION_NUMBER" *)
    output wire [7:0]                         cfg_mgmt_function_number,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_mgmt:1.0 pcie4_cfg_mgmt WRITE_EN" *)
    output wire                               cfg_mgmt_write,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_mgmt:1.0 pcie4_cfg_mgmt WRITE_DATA" *)
    output wire [31:0]                        cfg_mgmt_write_data,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_mgmt:1.0 pcie4_cfg_mgmt BYTE_EN" *)
    output wire [3:0]                         cfg_mgmt_byte_enable,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_mgmt:1.0 pcie4_cfg_mgmt READ_EN" *)
    output wire                               cfg_mgmt_read,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_mgmt:1.0 pcie4_cfg_mgmt READ_DATA" *)
    input  wire [31:0]                        cfg_mgmt_read_data,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_mgmt:1.0 pcie4_cfg_mgmt READ_WRITE_DONE" *)
    input  wire                               cfg_mgmt_read_write_done,

    //flow control interface
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie_cfg_fc:1.0 pcie4_cfg_fc PH" *)
    input  wire [7:0]                         cfg_fc_ph,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie_cfg_fc:1.0 pcie4_cfg_fc PD" *)
    input  wire [11:0]                        cfg_fc_pd,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie_cfg_fc:1.0 pcie4_cfg_fc NPH" *)
    input  wire [7:0]                         cfg_fc_nph,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie_cfg_fc:1.0 pcie4_cfg_fc NPD" *)
    input  wire [11:0]                        cfg_fc_npd,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie_cfg_fc:1.0 pcie4_cfg_fc CPLH" *)
    input  wire [7:0]                         cfg_fc_cplh,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie_cfg_fc:1.0 pcie4_cfg_fc CPLD" *)
    input  wire [11:0]                        cfg_fc_cpld,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie_cfg_fc:1.0 pcie4_cfg_fc SEL" *)
    output wire [2:0]                         cfg_fc_sel,
    
    //interrupt for user
    input  wire [USER_MSI_IRQ - 1:0]          msi_irq,
    output wire [USER_MSI_IRQ - 1:0]          msi_irq_ack,

    //interrupt for msix
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msix:1.0 pcie4_cfg_external_msix enable" *)
    input  wire [3:0]                         cfg_interrupt_msix_enable,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msix:1.0 pcie4_cfg_external_msix mask" *)
    input  wire [3:0]                         cfg_interrupt_msix_mask,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msix:1.0 pcie4_cfg_external_msix vf_enable" *)
    input  wire [251:0]                       cfg_interrupt_msix_vf_enable,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msix:1.0 pcie4_cfg_external_msix vf_mask" *)
    input  wire [251:0]                       cfg_interrupt_msix_vf_mask,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msix:1.0 pcie4_cfg_external_msix address" *)
    output wire [63:0]                        cfg_interrupt_msix_address,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msix:1.0 pcie4_cfg_external_msix data" *)
    output wire [31:0]                        cfg_interrupt_msix_data,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msix:1.0 pcie4_cfg_external_msix int_vector" *)
    output wire                               cfg_interrupt_msix_int,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msix:1.0 pcie4_cfg_external_msix vec_pending" *)
    output wire [1:0]                         cfg_interrupt_msix_vec_pending,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_external_msix:1.0 pcie4_cfg_external_msix vec_pending_status" *)
    input  wire                               cfg_interrupt_msix_vec_pending_status,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_external_msix:1.0 pcie4_cfg_external_msix sent" *)
    input  wire                               cfg_interrupt_msix_sent,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie4_cfg_external_msix:1.0 pcie4_cfg_external_msix fail" *)
    input  wire                               cfg_interrupt_msix_fail,

    //interrupt for msi
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi attr" *)
    output wire [2:0]                         cfg_interrupt_msi_attr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi tph_present" *)
    output wire                               cfg_interrupt_msi_tph_present,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi tph_type" *)
    output wire [1:0]                         cfg_interrupt_msi_tph_type,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi tph_st_tag" *)
    output wire [8:0]                         cfg_interrupt_msi_tph_st_tag,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi enable" *)
    input  wire [3:0]                         cfg_interrupt_msi_enable,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi vf_enable" *)
    input  wire [7:0]                         cfg_interrupt_msi_vf_enable,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi mmenable" *)
    input  wire [11:0]                        cfg_interrupt_msi_mmenable,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi mask_update" *)
    input  wire                               cfg_interrupt_msi_mask_update,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi data" *)
    input  wire [31:0]                        cfg_interrupt_msi_data,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi select" *)
    output wire [3:0]                         cfg_interrupt_msi_select,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi int_vector" *)
    output wire [31:0]                        cfg_interrupt_msi_int,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi pending_status" *)
    output wire [31:0]                        cfg_interrupt_msi_pending_status,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi pending_status_data_enable" *)
    output wire                               cfg_interrupt_msi_pending_status_data_enable,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi pending_status_function_num" *)
    output wire [3:0]                         cfg_interrupt_msi_pending_status_function_num,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi sent" *)
    input  wire                               cfg_interrupt_msi_sent,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi fail" *)
    input  wire                               cfg_interrupt_msi_fail,
    (* X_INTERFACE_INFO = "xilinx.com:interface:pcie3_cfg_msi:1.0 cfg_interrupt_msi function_number" *)
    output wire [7:0]                         cfg_interrupt_msi_function_number,

    output wire                               status_error_cor,
    output wire                               status_error_uncor 
);

localparam TLP_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH;
localparam TLP_STRB_WIDTH = TLP_DATA_WIDTH/32;
localparam TLP_HDR_WIDTH = 128;
localparam TLP_SEG_COUNT = 1;
localparam TX_SEQ_NUM_COUNT = AXIS_PCIE_DATA_WIDTH < 512 ? 1 : 2;
localparam TX_SEQ_NUM_WIDTH = RQ_SEQ_NUM_WIDTH-1;
localparam TX_SEQ_NUM_ENABLE = RQ_SEQ_NUM_ENABLE;
localparam PF_COUNT = 1;
localparam VF_COUNT = 0;
localparam F_COUNT = PF_COUNT+VF_COUNT;
localparam PCIE_ADDR_WIDTH = 64;

localparam BAR_NUMBERS   = PF0_BAR0_ENABLE + PF0_BAR1_ENABLE + PF0_BAR2_ENABLE + PF0_BAR3_ENABLE + PF0_BAR4_ENABLE + PF0_BAR5_ENABLE;
localparam BAR_STRIDE    = (BAR_ADDRESS_MODE == 64) ? 2 : 1;
localparam FIFO_ENABLE = 0;
localparam BAR_BASE    = 0;
localparam BAR_IDS     = 0;

//-------------------------pcie core inteface--------------------------------//
wire [TLP_DATA_WIDTH-1:0]                     pcie_rx_req_tlp_data;
wire [TLP_STRB_WIDTH-1:0]                     pcie_rx_req_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        pcie_rx_req_tlp_hdr;
wire [TLP_SEG_COUNT*3-1:0]                    pcie_rx_req_tlp_bar_id;
wire [TLP_SEG_COUNT*8-1:0]                    pcie_rx_req_tlp_func_num;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_req_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_req_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_req_tlp_eop;
wire                                          pcie_rx_req_tlp_ready;

wire [TLP_DATA_WIDTH-1:0]                     pcie_rx_cpl_tlp_data;
wire [TLP_STRB_WIDTH-1:0]                     pcie_rx_cpl_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        pcie_rx_cpl_tlp_hdr;
wire [TLP_SEG_COUNT*4-1:0]                    pcie_rx_cpl_tlp_error;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_cpl_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_cpl_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_cpl_tlp_eop;
wire                                          pcie_rx_cpl_tlp_ready;

wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        pcie_tx_rd_req_tlp_hdr;
wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     pcie_tx_rd_req_tlp_seq;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_rd_req_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_rd_req_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_rd_req_tlp_eop;
wire                                          pcie_tx_rd_req_tlp_ready;

wire [TX_SEQ_NUM_COUNT*TX_SEQ_NUM_WIDTH-1:0]  axis_pcie_rd_req_tx_seq_num;
wire [TX_SEQ_NUM_COUNT-1:0]                   axis_pcie_rd_req_tx_seq_num_valid;

wire [TLP_DATA_WIDTH-1:0]                     pcie_tx_wr_req_tlp_data;
wire [TLP_STRB_WIDTH-1:0]                     pcie_tx_wr_req_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        pcie_tx_wr_req_tlp_hdr;
wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     pcie_tx_wr_req_tlp_seq;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_wr_req_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_wr_req_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_wr_req_tlp_eop;
wire                                          pcie_tx_wr_req_tlp_ready;

wire [TX_SEQ_NUM_COUNT*TX_SEQ_NUM_WIDTH-1:0]  axis_pcie_wr_req_tx_seq_num;
wire [TX_SEQ_NUM_COUNT-1:0]                   axis_pcie_wr_req_tx_seq_num_valid;

wire [TLP_DATA_WIDTH-1:0]                     pcie_tx_cpl_tlp_data;
wire [TLP_STRB_WIDTH-1:0]                     pcie_tx_cpl_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        pcie_tx_cpl_tlp_hdr;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_cpl_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_cpl_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_cpl_tlp_eop;
wire                                          pcie_tx_cpl_tlp_ready;

wire [31:0]     pcie_tx_msix_wr_req_tlp_data;
wire [3:0]      pcie_tx_msix_wr_req_tlp_strb;
wire [127:0]    pcie_tx_msix_wr_req_tlp_hdr;
wire            pcie_tx_msix_wr_req_tlp_valid;
wire            pcie_tx_msix_wr_req_tlp_sop;
wire            pcie_tx_msix_wr_req_tlp_eop;
wire            pcie_tx_msix_wr_req_tlp_ready;


wire [7 : 0]  bus_num = cfg_bus_number;
wire ext_tag_enable;

wire s_axis_rc_tvalid_int;
wire s_axis_rc_tready_int;

wire msix_enable;
wire msix_mask;

assign s_axis_rc_tvalid_int = s_axis_rc_tvalid ;
assign s_axis_rc_tready = s_axis_rc_tready_int ;

//-------------------------pcie bar to axi lite interface--------------------------------//
wire [TLP_DATA_WIDTH-1 : 0] user_rx_req_tlp_data;
wire [TLP_STRB_WIDTH-1 : 0] user_rx_req_tlp_strb;
wire [TLP_HDR_WIDTH -1 : 0] user_rx_req_tlp_hdr ;
wire [TLP_SEG_COUNT*3-1 : 0]user_rx_req_tlp_bar_id  ;
wire [TLP_SEG_COUNT*8-1 : 0]user_rx_req_tlp_func_num;
wire                        user_rx_req_tlp_valid;
wire                        user_rx_req_tlp_ready;
wire                        user_rx_req_tlp_sop  ;
wire                        user_rx_req_tlp_eop  ;

wire [TLP_DATA_WIDTH-1 : 0] ctrl_rx_req_tlp_data;
wire [TLP_STRB_WIDTH-1 : 0] ctrl_rx_req_tlp_strb;
wire [TLP_HDR_WIDTH -1 : 0] ctrl_rx_req_tlp_hdr ;
wire [TLP_SEG_COUNT*3-1 : 0]ctrl_rx_req_tlp_bar_id  ;
wire [TLP_SEG_COUNT*8-1 : 0]ctrl_rx_req_tlp_func_num;
wire                        ctrl_rx_req_tlp_valid;
wire                        ctrl_rx_req_tlp_ready;
wire                        ctrl_rx_req_tlp_sop  ;
wire                        ctrl_rx_req_tlp_eop  ;

wire [TLP_DATA_WIDTH-1:0]               user_tx_cpl_tlp_data;
wire [TLP_STRB_WIDTH-1:0]               user_tx_cpl_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]  user_tx_cpl_tlp_hdr;
wire [TLP_SEG_COUNT-1:0]                user_tx_cpl_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                user_tx_cpl_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                user_tx_cpl_tlp_eop;
wire                                    user_tx_cpl_tlp_ready;

wire [TLP_DATA_WIDTH-1:0]               ctrl_tx_cpl_tlp_data;
wire [TLP_STRB_WIDTH-1:0]               ctrl_tx_cpl_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]  ctrl_tx_cpl_tlp_hdr;
wire [TLP_SEG_COUNT-1:0]                ctrl_tx_cpl_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                ctrl_tx_cpl_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                ctrl_tx_cpl_tlp_eop;
wire                                    ctrl_tx_cpl_tlp_ready;

//---------------------------------bar's space register---------------------------------//

wire [31 : 0] C2H_DMA_SDRAM_LOW_ADDRESS ;
wire [31 : 0] C2H_DMA_SDRAM_HIGH_ADDRESS;
wire [31 : 0] H2C_DMA_SDRAM_LOW_ADDRESS ;
wire [31 : 0] H2C_DMA_SDRAM_HIGH_ADDRESS;
wire [31 : 0] C2HBlockDMA_low_address   ;
wire [31 : 0] C2HBlockDMA_high_address  ;
wire [31 : 0] C2HBlockDMA_length        ;
wire [31 : 0] C2HBlockDMA_Status        ;
wire [31 : 0] H2CBlockDMA_low_address   ;
wire [31 : 0] H2CBlockDMA_high_address  ;
wire [31 : 0] H2CBlockDMA_length        ;
wire [31 : 0] H2CBlockDMA_Status        ;
wire [31 : 0] H2CBlockDMA_Start         ;
wire [31 : 0] C2HBlockDMA_Start         ;

wire[31:0]       C2H_SgList_LOW_address		;
wire[31:0]       C2H_SgList_HIGH_address	;
wire[31:0]       C2H_SgList_length			;
wire             C2H_SgList_Start			;
wire             C2H_SgDMA_Start			;
wire[31:0]       C2H_SgDMA_length			;
wire[31:0]       C2H_SgSDRAM_LOW_address    ;
wire[31:0]       C2H_SgSDRAM_HIGH_address   ;
wire[31:0]       C2H_SgDMA_Status           ;

wire [31:0]       H2C_SgList_LOW_address    ;
wire [31:0]       H2C_SgList_HIGH_address   ;
wire [31:0]       H2C_SgList_length   ;
wire              H2C_SgList_Start			;
wire              H2C_SgDMA_Start			;
wire [31:0]       H2C_SgDMA_length			;
wire [31:0]       H2C_SgSDRAM_LOW_address   ;
wire [31:0]       H2C_SgSDRAM_HIGH_address  ;
wire [31:0]       H2C_SgDMA_Status          ;  

wire tx_wr_req_irq, tx_rd_req_irq;
wire tx_rd_sglist_irq, tx_wr_sglist_irq;
wire tx_sgdma_irq,rx_sgdma_irq;

wire [31:0] msi_irq_req = {26'h0, rx_sgdma_irq,tx_rd_sglist_irq,tx_sgdma_irq,tx_wr_sglist_irq,tx_rd_req_irq, tx_wr_req_irq};


assign C2HBlockDMA_Status = {30'b0,1'b0,tx_wr_req_irq};
assign H2CBlockDMA_Status = {30'b0,1'b0,tx_rd_req_irq};

assign C2H_SgDMA_Status = {30'b0,tx_sgdma_irq,tx_wr_sglist_irq};
assign H2C_SgDMA_Status = {30'b0,rx_sgdma_irq,tx_rd_sglist_irq};

//-------------------------------------------end--------------------------------------------//

/*
 * 1. pcie's core interface to fpga_core
 */
pcie_us_if #(
    .AXIS_PCIE_DATA_WIDTH   (AXIS_PCIE_DATA_WIDTH   ),
    .AXIS_PCIE_KEEP_WIDTH   (AXIS_PCIE_KEEP_WIDTH   ),
    .AXIS_PCIE_RC_USER_WIDTH(AXIS_PCIE_RC_USER_WIDTH),
    .AXIS_PCIE_RQ_USER_WIDTH(AXIS_PCIE_RQ_USER_WIDTH),
    .AXIS_PCIE_CQ_USER_WIDTH(AXIS_PCIE_CQ_USER_WIDTH),
    .AXIS_PCIE_CC_USER_WIDTH(AXIS_PCIE_CC_USER_WIDTH),
    .RC_STRADDLE            (RC_STRADDLE            ),
    .RQ_STRADDLE            (RQ_STRADDLE            ),
    .CQ_STRADDLE            (CQ_STRADDLE            ),
    .CC_STRADDLE            (CC_STRADDLE            ),
    .RQ_SEQ_NUM_WIDTH       (RQ_SEQ_NUM_WIDTH       ),
    .TLP_DATA_WIDTH         (TLP_DATA_WIDTH         ),
    .TLP_STRB_WIDTH         (TLP_STRB_WIDTH         ),
    .TLP_HDR_WIDTH          (TLP_HDR_WIDTH          ),
    .TLP_SEG_COUNT          (TLP_SEG_COUNT          ),
    .TX_SEQ_NUM_COUNT       (TX_SEQ_NUM_COUNT       ),
    .TX_SEQ_NUM_WIDTH       (TX_SEQ_NUM_WIDTH       ),
    .PF_COUNT               (1),
    .VF_COUNT               (0),
    .F_COUNT                (PF_COUNT+VF_COUNT      ),
    .READ_EXT_TAG_ENABLE    (1),
    .READ_MAX_READ_REQ_SIZE (1),
    .READ_MAX_PAYLOAD_SIZE  (1),
    .MSIX_ENABLE            (0),
    .MSI_COUNT              (MSI_COUNT),
    .MSI_ENABLE             (0)
)pcie_usplus_if(
    .clk(clk),
    .rst(rst),

    /*
     * AXI input (RC)
     */
    .s_axis_rc_tdata(s_axis_rc_tdata),
    .s_axis_rc_tkeep(s_axis_rc_tkeep),
    .s_axis_rc_tvalid(s_axis_rc_tvalid_int),
    .s_axis_rc_tready(s_axis_rc_tready_int),
    .s_axis_rc_tlast(s_axis_rc_tlast),
    .s_axis_rc_tuser(s_axis_rc_tuser),

    /*
     * AXI output (RQ)
     */
    .m_axis_rq_tdata(m_axis_rq_tdata),
    .m_axis_rq_tkeep(m_axis_rq_tkeep),
    .m_axis_rq_tvalid(m_axis_rq_tvalid),
    .m_axis_rq_tready(m_axis_rq_tready),
    .m_axis_rq_tlast(m_axis_rq_tlast),
    .m_axis_rq_tuser(m_axis_rq_tuser),

    /*
     * AXI input (CQ)
     */
    .s_axis_cq_tdata(s_axis_cq_tdata),
    .s_axis_cq_tkeep(s_axis_cq_tkeep),
    .s_axis_cq_tvalid(s_axis_cq_tvalid),
    .s_axis_cq_tready(s_axis_cq_tready),
    .s_axis_cq_tlast(s_axis_cq_tlast),
    .s_axis_cq_tuser(s_axis_cq_tuser),

    /*
     * AXI output (CC)
     */
    .m_axis_cc_tdata(m_axis_cc_tdata),
    .m_axis_cc_tkeep(m_axis_cc_tkeep),
    .m_axis_cc_tvalid(m_axis_cc_tvalid),
    .m_axis_cc_tready(m_axis_cc_tready),
    .m_axis_cc_tlast(m_axis_cc_tlast),
    .m_axis_cc_tuser(m_axis_cc_tuser),

    /*
     * Transmit sequence number input
     */
    .s_axis_rq_seq_num_0(s_axis_rq_seq_num_0),
    .s_axis_rq_seq_num_valid_0(s_axis_rq_seq_num_valid_0),
    .s_axis_rq_seq_num_1(s_axis_rq_seq_num_1),
    .s_axis_rq_seq_num_valid_1(s_axis_rq_seq_num_valid_1),

    /*
     * Configuration management interface
     */
    .cfg_mgmt_addr(cfg_mgmt_addr),
    .cfg_mgmt_function_number(cfg_mgmt_function_number),
    .cfg_mgmt_write(cfg_mgmt_write),
    .cfg_mgmt_write_data(cfg_mgmt_write_data),
    .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
    .cfg_mgmt_read(cfg_mgmt_read),
    .cfg_mgmt_read_data(cfg_mgmt_read_data),
    .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done),

    /*
     * Configuration status interface
     */
    .cfg_max_payload(cfg_max_payload),
    .cfg_max_read_req(cfg_max_read_req),

    /*
     * Configuration flow control interface
     */
    .cfg_fc_ph(cfg_fc_ph),
    .cfg_fc_pd(cfg_fc_pd),
    .cfg_fc_nph(cfg_fc_nph),
    .cfg_fc_npd(cfg_fc_npd),
    .cfg_fc_cplh(cfg_fc_cplh),
    .cfg_fc_cpld(cfg_fc_cpld),
    .cfg_fc_sel(cfg_fc_sel),

    /*
     * TLP output (request to BAR)
     */
    .rx_req_tlp_data(pcie_rx_req_tlp_data),
    .rx_req_tlp_strb(pcie_rx_req_tlp_strb),
    .rx_req_tlp_hdr(pcie_rx_req_tlp_hdr),
    .rx_req_tlp_bar_id(pcie_rx_req_tlp_bar_id),
    .rx_req_tlp_func_num(pcie_rx_req_tlp_func_num),
    .rx_req_tlp_valid(pcie_rx_req_tlp_valid),
    .rx_req_tlp_sop(pcie_rx_req_tlp_sop),
    .rx_req_tlp_eop(pcie_rx_req_tlp_eop),
    .rx_req_tlp_ready(pcie_rx_req_tlp_ready),

    /*
     * TLP output (completion to DMA)
     */
    .rx_cpl_tlp_data(pcie_rx_cpl_tlp_data),
    .rx_cpl_tlp_strb(pcie_rx_cpl_tlp_strb),
    .rx_cpl_tlp_hdr(pcie_rx_cpl_tlp_hdr),
    .rx_cpl_tlp_error(pcie_rx_cpl_tlp_error),
    .rx_cpl_tlp_valid(pcie_rx_cpl_tlp_valid),
    .rx_cpl_tlp_sop(pcie_rx_cpl_tlp_sop),
    .rx_cpl_tlp_eop(pcie_rx_cpl_tlp_eop),
    .rx_cpl_tlp_ready(pcie_rx_cpl_tlp_ready),

    /*
     * TLP input (read request from DMA)
     */
    .tx_rd_req_tlp_hdr(pcie_tx_rd_req_tlp_hdr),
    .tx_rd_req_tlp_seq(pcie_tx_rd_req_tlp_seq),
    .tx_rd_req_tlp_valid(pcie_tx_rd_req_tlp_valid),
    .tx_rd_req_tlp_sop(pcie_tx_rd_req_tlp_sop),
    .tx_rd_req_tlp_eop(pcie_tx_rd_req_tlp_eop),
    .tx_rd_req_tlp_ready(pcie_tx_rd_req_tlp_ready),

    /*
     * Transmit sequence number output (DMA read request)
     */
    .m_axis_rd_req_tx_seq_num(axis_pcie_rd_req_tx_seq_num),
    .m_axis_rd_req_tx_seq_num_valid(axis_pcie_rd_req_tx_seq_num_valid),

    /*
     * TLP input (write request from DMA)
     */
    .tx_wr_req_tlp_data(pcie_tx_wr_req_tlp_data),
    .tx_wr_req_tlp_strb(pcie_tx_wr_req_tlp_strb),
    .tx_wr_req_tlp_hdr(pcie_tx_wr_req_tlp_hdr),
    .tx_wr_req_tlp_seq(pcie_tx_wr_req_tlp_seq),
    .tx_wr_req_tlp_valid(pcie_tx_wr_req_tlp_valid),
    .tx_wr_req_tlp_sop(pcie_tx_wr_req_tlp_sop),
    .tx_wr_req_tlp_eop(pcie_tx_wr_req_tlp_eop),
    .tx_wr_req_tlp_ready(pcie_tx_wr_req_tlp_ready),

    /*
     * Transmit sequence number output (DMA write request)
     */
    .m_axis_wr_req_tx_seq_num(axis_pcie_wr_req_tx_seq_num),
    .m_axis_wr_req_tx_seq_num_valid(axis_pcie_wr_req_tx_seq_num_valid),

    /*
     * TLP input (completion from BAR)
     */
    .tx_cpl_tlp_data(pcie_tx_cpl_tlp_data),
    .tx_cpl_tlp_strb(pcie_tx_cpl_tlp_strb),
    .tx_cpl_tlp_hdr(pcie_tx_cpl_tlp_hdr),
    .tx_cpl_tlp_valid(pcie_tx_cpl_tlp_valid),
    .tx_cpl_tlp_sop(pcie_tx_cpl_tlp_sop),
    .tx_cpl_tlp_eop(pcie_tx_cpl_tlp_eop),
    .tx_cpl_tlp_ready(pcie_tx_cpl_tlp_ready),

    /*
     * TLP input (write request from MSI-X)
     */
    .tx_msix_wr_req_tlp_data(pcie_tx_msix_wr_req_tlp_data),
    .tx_msix_wr_req_tlp_strb(pcie_tx_msix_wr_req_tlp_strb),
    .tx_msix_wr_req_tlp_hdr(pcie_tx_msix_wr_req_tlp_hdr),
    .tx_msix_wr_req_tlp_valid(pcie_tx_msix_wr_req_tlp_valid),
    .tx_msix_wr_req_tlp_sop(pcie_tx_msix_wr_req_tlp_sop),
    .tx_msix_wr_req_tlp_eop(pcie_tx_msix_wr_req_tlp_eop),
    .tx_msix_wr_req_tlp_ready(pcie_tx_msix_wr_req_tlp_ready),

    /*
     * Configuration outputs
     */
    .ext_tag_enable(ext_tag_enable),
    .max_read_request_size(),
    .max_payload_size(),
    .msix_enable(msix_enable),
    .msix_mask(msix_mask),

    /*
     * MSI request inputs (same sources as dma_intr_queue)
     */
    .msi_irq()
);

/*
 * 2. The conversion from the pcie bar space to the axi lite 
 *    interface involves a total of 2 bar Spaces. It requires arbitration. 
 */

pcie_tlp_demux_bar #(
    .PORTS             (BAR_NUMBERS   ),
    .TLP_DATA_WIDTH    (TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH    (TLP_STRB_WIDTH),
    .TLP_HDR_WIDTH     (TLP_HDR_WIDTH ),
    .IN_TLP_SEG_COUNT  (TLP_SEG_COUNT ),
    .OUT_TLP_SEG_COUNT (TLP_SEG_COUNT ),
    .FIFO_ENABLE       (FIFO_ENABLE),
    .BAR_BASE          (BAR_BASE),
    .BAR_STRIDE        (BAR_STRIDE),
    .BAR_IDS           (BAR_IDS)
)pcie_tlp_demux_inst (
    .clk(clk),
    .rst(rst),

    /*
     * TLP input
     */
    .in_tlp_data    (pcie_rx_req_tlp_data  ),
    .in_tlp_strb    (pcie_rx_req_tlp_strb  ),
    .in_tlp_hdr     (pcie_rx_req_tlp_hdr   ),
    .in_tlp_bar_id  (pcie_rx_req_tlp_bar_id),
    .in_tlp_func_num(pcie_rx_req_tlp_func_num),
    .in_tlp_error   ('b0),
    .in_tlp_valid   (pcie_rx_req_tlp_valid ),
    .in_tlp_sop     (pcie_rx_req_tlp_sop   ),
    .in_tlp_eop     (pcie_rx_req_tlp_eop   ),
    .in_tlp_ready   (pcie_rx_req_tlp_ready ),

    /*
     * TLP output
     */
    .out_tlp_data     ({user_rx_req_tlp_data , ctrl_rx_req_tlp_data}),
    .out_tlp_strb     ({user_rx_req_tlp_strb , ctrl_rx_req_tlp_strb}),
    .out_tlp_hdr      ({user_rx_req_tlp_hdr  , ctrl_rx_req_tlp_hdr}),
    .out_tlp_bar_id   ({user_rx_req_tlp_bar_id, ctrl_rx_req_tlp_bar_id}),
    .out_tlp_func_num ({user_rx_req_tlp_func_num ,ctrl_rx_req_tlp_func_num}),
    .out_tlp_error(),
    .out_tlp_valid    ({user_rx_req_tlp_valid , ctrl_rx_req_tlp_valid}),
    .out_tlp_sop      ({user_rx_req_tlp_sop ,   ctrl_rx_req_tlp_sop}),
    .out_tlp_eop      ({user_rx_req_tlp_eop ,   ctrl_rx_req_tlp_eop}),
    .out_tlp_ready    ({user_rx_req_tlp_ready, ctrl_rx_req_tlp_ready}),

    /*
     * Control
     */
    .enable(1'b1),

    /*
     * Status
     */
    .fifo_half_full(),
    .fifo_watermark()
);


pcie_tlp_mux #(
    .PORTS(BAR_NUMBERS),
    .TLP_DATA_WIDTH(TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH(TLP_STRB_WIDTH),
    .TLP_HDR_WIDTH(TLP_HDR_WIDTH),
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .ARB_TYPE_ROUND_ROBIN(1),
    .ARB_LSB_HIGH_PRIORITY(1)
)pcie_tlp_mux_inst (
    .clk(clk),
    .rst(rst),

    /*
     * TLP input
     */
    .in_tlp_data( {user_tx_cpl_tlp_data,  ctrl_tx_cpl_tlp_data }),
    .in_tlp_strb( {user_tx_cpl_tlp_strb,  ctrl_tx_cpl_tlp_strb }),
    .in_tlp_hdr(  {user_tx_cpl_tlp_hdr ,  ctrl_tx_cpl_tlp_hdr  }),
    .in_tlp_seq('b0),
    .in_tlp_bar_id('b0),
    .in_tlp_func_num('b0),
    .in_tlp_error('b0),
    .in_tlp_valid({user_tx_cpl_tlp_valid,  ctrl_tx_cpl_tlp_valid}),
    .in_tlp_sop(  {user_tx_cpl_tlp_sop  ,  ctrl_tx_cpl_tlp_sop  }),
    .in_tlp_eop(  {user_tx_cpl_tlp_eop  ,  ctrl_tx_cpl_tlp_eop  }),
    .in_tlp_ready({user_tx_cpl_tlp_ready,  ctrl_tx_cpl_tlp_ready}),

    /*
     * TLP output
     */
    .out_tlp_data(pcie_tx_cpl_tlp_data),
    .out_tlp_strb(pcie_tx_cpl_tlp_strb),
    .out_tlp_hdr( pcie_tx_cpl_tlp_hdr),
    .out_tlp_seq(),
    .out_tlp_bar_id(),
    .out_tlp_func_num(),
    .out_tlp_error(),
    .out_tlp_valid(pcie_tx_cpl_tlp_valid),
    .out_tlp_sop  (pcie_tx_cpl_tlp_sop),
    .out_tlp_eop  (pcie_tx_cpl_tlp_eop),
    .out_tlp_ready(pcie_tx_cpl_tlp_ready),

    /*
     * Control
     */
    .pause('b0),

    /*
     * Status
     */
    .sel_tlp_seq(),
    .sel_tlp_seq_valid()
);

/*
 * 3.  dma's bar config
 */
pcie_axil_tobar_master #(
    .TLP_DATA_WIDTH        	(TLP_DATA_WIDTH  ),
    .TLP_STRB_WIDTH        	(TLP_STRB_WIDTH  ),
    .TLP_HDR_WIDTH         	(TLP_HDR_WIDTH   ),
    .TLP_SEG_COUNT         	(TLP_SEG_COUNT   ),
    .AXIL_DATA_WIDTH       	(AXIL_CTRL_DATA_WIDTH   ),
    .AXIL_ADDR_WIDTH       	(AXIL_CTRL_ADDR_WIDTH   ),
    .AXIL_STRB_WIDTH       	(AXIL_CTRL_STRB_WIDTH   ),
    .TLP_FORCE_64_BIT_ADDR 	(0    )
)axil_tobar_master(
    .clk                      	(clk ),
    .rst                      	(rst ),

    .rx_req_tlp_data          	(ctrl_rx_req_tlp_data      ),
    .rx_req_tlp_hdr           	(ctrl_rx_req_tlp_hdr       ),
    .rx_req_tlp_valid         	(ctrl_rx_req_tlp_valid     ),
    .rx_req_tlp_sop           	(ctrl_rx_req_tlp_sop       ),
    .rx_req_tlp_eop           	(ctrl_rx_req_tlp_eop       ),
    .rx_req_tlp_ready         	(ctrl_rx_req_tlp_ready     ),

    .tx_cpl_tlp_data          	(ctrl_tx_cpl_tlp_data       ),
    .tx_cpl_tlp_strb          	(ctrl_tx_cpl_tlp_strb       ),
    .tx_cpl_tlp_hdr           	(ctrl_tx_cpl_tlp_hdr        ),
    .tx_cpl_tlp_valid         	(ctrl_tx_cpl_tlp_valid      ),
    .tx_cpl_tlp_sop           	(ctrl_tx_cpl_tlp_sop        ),
    .tx_cpl_tlp_eop           	(ctrl_tx_cpl_tlp_eop        ),
    .tx_cpl_tlp_ready         	(ctrl_tx_cpl_tlp_ready      ),

    .completer_id             	({bus_num, 5'd0, 3'd0}     ),
    .C2HBlockDMA_low_address  	(C2HBlockDMA_low_address   ),
    .C2HBlockDMA_high_address 	(C2HBlockDMA_high_address  ),
    .C2HBlockDMA_length       	(C2HBlockDMA_length        ),
    .C2HBlockDMA_Start        	(C2HBlockDMA_Start         ),
    .C2HBlockDMA_Status       	(C2HBlockDMA_Status        ),
    .C2H_DMA_SDRAM_LOW_ADDRESS  (C2H_DMA_SDRAM_LOW_ADDRESS),
    .C2H_DMA_SDRAM_HIGH_ADDRESS (C2H_DMA_SDRAM_HIGH_ADDRESS),
    .H2CBlockDMA_low_address  	(H2CBlockDMA_low_address   ),
    .H2CBlockDMA_high_address 	(H2CBlockDMA_high_address  ),
    .H2CBlockDMA_length       	(H2CBlockDMA_length        ),
    .H2CBlockDMA_Start        	(H2CBlockDMA_Start         ),
    .H2CBlockDMA_Status       	(H2CBlockDMA_Status        ),
    .H2C_DMA_SDRAM_LOW_ADDRESS  (H2C_DMA_SDRAM_LOW_ADDRESS),
    .H2C_DMA_SDRAM_HIGH_ADDRESS (H2C_DMA_SDRAM_HIGH_ADDRESS),

    .C2H_SgList_LOW_address     (C2H_SgList_LOW_address      ),
    .C2H_SgList_HIGH_address    (C2H_SgList_HIGH_address     ),
    .C2H_SgList_length          (C2H_SgList_length            ),
    .C2H_SgList_Start           (C2H_SgList_Start            ),
    .C2H_SgDMA_Start            (C2H_SgDMA_Start             ),
    .C2H_SgDMA_length           (C2H_SgDMA_length            ),
    .C2H_SgSDRAM_LOW_address    (C2H_SgSDRAM_LOW_address     ),
    .C2H_SgSDRAM_HIGH_address   (C2H_SgSDRAM_HIGH_address    ),
    .C2H_SgDMA_Status           (C2H_SgDMA_Status            ),
    .H2C_SgList_LOW_address     (H2C_SgList_LOW_address      ),
    .H2C_SgList_HIGH_address    (H2C_SgList_HIGH_address     ),
    .H2C_SgList_length           (H2C_SgList_length            ),
    .H2C_SgList_Start           (H2C_SgList_Start            ),
    .H2C_SgDMA_Start            (H2C_SgDMA_Start             ),
    .H2C_SgDMA_length           (H2C_SgDMA_length            ),
    .H2C_SgSDRAM_LOW_address    (H2C_SgSDRAM_LOW_address     ),
    .H2C_SgSDRAM_HIGH_address   (H2C_SgSDRAM_HIGH_address    ),
    .H2C_SgDMA_Status           (H2C_SgDMA_Status            )
);

/*
 * 4. user's bar
 */

generate 
    if(PCIe_to_AXI_Lite_Interface == 1)begin:bar_to_userspace
        pcie_axil_master #(
            .TLP_DATA_WIDTH        	(AXIS_PCIE_DATA_WIDTH  ),
            .TLP_HDR_WIDTH         	(TLP_HDR_WIDTH     ),
            .TLP_SEG_COUNT         	(TLP_SEG_COUNT     ),
            .AXIL_DATA_WIDTH       	(AXIL_CTRL_DATA_WIDTH   ),
            .AXIL_ADDR_WIDTH       	(AXIL_CTRL_ADDR_WIDTH   ),
            .AXIL_STRB_WIDTH       	(AXIL_CTRL_STRB_WIDTH   ),
            .TLP_FORCE_64_BIT_ADDR 	(0    )
        )user_axil_master(
            .clk                	(clk                 ),
            .rst                	(rst                 ),
    
            .rx_req_tlp_data        (user_rx_req_tlp_data      ),
            .rx_req_tlp_hdr         (user_rx_req_tlp_hdr       ),
            .rx_req_tlp_valid       (user_rx_req_tlp_valid     ),
            .rx_req_tlp_sop         (user_rx_req_tlp_sop       ),
            .rx_req_tlp_eop         (user_rx_req_tlp_eop       ),
            .rx_req_tlp_ready       (user_rx_req_tlp_ready     ),
    
            .tx_cpl_tlp_data        (user_tx_cpl_tlp_data       ),
            .tx_cpl_tlp_strb        (user_tx_cpl_tlp_strb       ),
            .tx_cpl_tlp_hdr         (user_tx_cpl_tlp_hdr        ),
            .tx_cpl_tlp_valid       (user_tx_cpl_tlp_valid      ),
            .tx_cpl_tlp_sop         (user_tx_cpl_tlp_sop        ),
            .tx_cpl_tlp_eop         (user_tx_cpl_tlp_eop        ),
            .tx_cpl_tlp_ready       (user_tx_cpl_tlp_ready      ),
    
            .m_axil_awaddr      	(M_AXI_Lite_AWADDR       ),
            .m_axil_awprot      	(M_AXI_Lite_AWPROT       ),
            .m_axil_awvalid     	(M_AXI_Lite_AWVALID      ),
            .m_axil_awready     	(M_AXI_Lite_AWREADY      ),
            .m_axil_wdata       	(M_AXI_Lite_WDATA        ),
            .m_axil_wstrb       	(M_AXI_Lite_WSTRB        ),
            .m_axil_wvalid      	(M_AXI_Lite_WVALID       ),
            .m_axil_wready      	(M_AXI_Lite_WREADY       ),
            .m_axil_bresp       	(M_AXI_Lite_BRESP        ),
            .m_axil_bvalid      	(M_AXI_Lite_BVALID       ),
            .m_axil_bready      	(M_AXI_Lite_BREADY       ),
            .m_axil_araddr      	(M_AXI_Lite_ARADDR       ),
            .m_axil_arprot      	(M_AXI_Lite_ARPROT       ),
            .m_axil_arvalid     	(M_AXI_Lite_ARVALID      ),
            .m_axil_arready     	(M_AXI_Lite_ARREADY      ),
            .m_axil_rdata       	(M_AXI_Lite_RDATA        ),
            .m_axil_rresp       	(M_AXI_Lite_RRESP        ),
            .m_axil_rvalid      	(M_AXI_Lite_RVALID       ),
            .m_axil_rready      	(M_AXI_Lite_RREADY       ),
    
            .completer_id       	({bus_num, 5'd0, 3'd0}),
            .status_error_cor   	(status_error_cor    ),
            .status_error_uncor 	(status_error_uncor  )
        );
    end
else begin
    assign      M_AXI_Lite_AWADDR  = 'b0;
    assign      M_AXI_Lite_AWPROT  = 'b0;
    assign      M_AXI_Lite_AWVALID = 'b0;
    assign      M_AXI_Lite_WDATA   = 'b0;
    assign      M_AXI_Lite_WSTRB   = 'b0;
    assign      M_AXI_Lite_WVALID  = 'b0;
    assign      M_AXI_Lite_BREADY  = 0;
    assign      M_AXI_Lite_ARADDR  = 0;
    assign      M_AXI_Lite_ARPROT  = 0;
    assign      M_AXI_Lite_ARVALID = 0;
    assign      M_AXI_Lite_RREADY  = 0;
end
endgenerate

generate 
    if(DMA_MODE == "Scatter_Gather")begin:Scatter_Gather
        if(DMA_INTERFACE_MODE == "AXI4-Stream")begin:sgdma_axis
            sgdma_if_pcie_axis #(
                .TLP_DATA_WIDTH(TLP_DATA_WIDTH),
                .TLP_STRB_WIDTH(TLP_STRB_WIDTH),
                .TLP_HDR_WIDTH(TLP_HDR_WIDTH),
                .TLP_SEG_COUNT(TLP_SEG_COUNT),
                .PCIE_ADDR_WIDTH(PCIE_ADDR_WIDTH),
                .TX_SEQ_NUM_COUNT(TX_SEQ_NUM_COUNT),
                .TX_SEQ_NUM_WIDTH(TX_SEQ_NUM_WIDTH),
                .PCIE_TAG_COUNT(32),
                .OP_TABLE_SIZE(32)
            ) sgdma_if_axis (
                .clk(clk),
                .rst(rst),

                .tx_wr_req_tlp_data  	(pcie_tx_wr_req_tlp_data   ),
                .tx_wr_req_tlp_strb  	(pcie_tx_wr_req_tlp_strb   ),
                .tx_wr_req_tlp_hdr   	(pcie_tx_wr_req_tlp_hdr    ),
                .tx_wr_req_tlp_seq   	(pcie_tx_wr_req_tlp_seq    ),
                .tx_wr_req_tlp_valid 	(pcie_tx_wr_req_tlp_valid  ),
                .tx_wr_req_tlp_sop   	(pcie_tx_wr_req_tlp_sop    ),
                .tx_wr_req_tlp_eop   	(pcie_tx_wr_req_tlp_eop    ),
                .tx_wr_req_tlp_ready 	(pcie_tx_wr_req_tlp_ready  ),

                .tx_rd_req_tlp_hdr      (pcie_tx_rd_req_tlp_hdr),
                .tx_rd_req_tlp_seq      (pcie_tx_rd_req_tlp_seq),
                .tx_rd_req_tlp_valid    (pcie_tx_rd_req_tlp_valid),
                .tx_rd_req_tlp_sop      (pcie_tx_rd_req_tlp_sop),
                .tx_rd_req_tlp_eop      (pcie_tx_rd_req_tlp_eop),
                .tx_rd_req_tlp_ready    (pcie_tx_rd_req_tlp_ready),

                .rx_cpl_tlp_data        (pcie_rx_cpl_tlp_data),
                .rx_cpl_tlp_hdr         (pcie_rx_cpl_tlp_hdr),
                .rx_cpl_tlp_error       (pcie_rx_cpl_tlp_error),
                .rx_cpl_tlp_valid       (pcie_rx_cpl_tlp_valid),
                .rx_cpl_tlp_sop         (pcie_rx_cpl_tlp_sop),
                .rx_cpl_tlp_eop         (pcie_rx_cpl_tlp_eop),
                .rx_cpl_tlp_ready       (pcie_rx_cpl_tlp_ready),

                .desc_wr_req_sglist_length  (C2H_SgList_length),
                .desc_wr_req_sglist_address ({C2H_SgList_HIGH_address,C2H_SgList_LOW_address}),
                .desc_wr_req_sglist_start   (C2H_SgList_Start),
                .desc_wr_req_sgdma_start    (C2H_SgDMA_Start),
                .desc_rd_req_sglist_length  (H2C_SgList_length),
                .desc_rd_req_sglist_address ({H2C_SgList_HIGH_address,H2C_SgList_LOW_address}),
                .desc_rd_req_sglist_start   (H2C_SgList_Start),
                .desc_rd_req_sgdma_start    (H2C_SgDMA_Start),

                .tx_wr_sglist_irq(tx_wr_sglist_irq),
                .tx_rd_sglist_irq(tx_rd_sglist_irq),
                .requester_id({bus_num, 5'd0, 3'd0}),
                .MaxPayloadSize(cfg_max_payload),
                .max_read_payloadSize(cfg_max_read_req),

                .s_axis_tlp_tdata    	(S_AXIS_DMA_TDATA ),
                .s_axis_tlp_tkeep    	(S_AXIS_DMA_TKEEP ),
                .s_axis_tlp_tvalid   	(S_AXIS_DMA_TVALID),
                .s_axis_tlp_tlast    	(S_AXIS_DMA_TLAST ),
                .s_axis_tlp_tready   	(S_AXIS_DMA_TREADY),

                .m_axis_tlp_tdata       (M_AXIS_DMA_TDATA ),
                .m_axis_tlp_tkeep       (M_AXIS_DMA_TKEEP ),
                .m_axis_tlp_tvalid      (M_AXIS_DMA_TVALID),
                .m_axis_tlp_tlast       (M_AXIS_DMA_TLAST ),
                .m_axis_tlp_tready      (M_AXIS_DMA_TREADY)
            );
        end
        else if(DMA_INTERFACE_MODE == "AXI_MEMORY_MAP")begin:sgdma_axi
            sgdma_if_pcie_axi #(
                .TLP_DATA_WIDTH    	(TLP_DATA_WIDTH  ),
                .TLP_STRB_WIDTH    	(TLP_STRB_WIDTH  ),
                .TLP_HDR_WIDTH     	(TLP_HDR_WIDTH   ),
                .TLP_SEG_COUNT     	(TLP_SEG_COUNT   ),
                .PCIE_ADDR_WIDTH   	(PCIE_ADDR_WIDTH ),
                .TX_SEQ_NUM_COUNT  	(TX_SEQ_NUM_COUNT),
                .TX_SEQ_NUM_WIDTH  	(TX_SEQ_NUM_WIDTH),
                .PCIE_TAG_COUNT    	(PCIE_TAG_COUNT  ),
                .OP_TABLE_SIZE     	(PCIE_TAG_COUNT  ),
                .AXI_DATA_WIDTH    	(AXI_DATA_WIDTH  ),
                .AXI_ADDR_WIDTH    	(AXI_ADDR_WIDTH  ),
                .AXI_STRB_WIDTH    	(AXI_STRB_WIDTH  ),
                .AXI_ID_WIDTH      	(AXI_ID_WIDTH    ),
                .AXI_MAX_BURST_LEN 	(AXI_MAX_BURST_LEN)
            )sgdma_if_axi(
                .clk                    	(clk ),
                .rst                    	(rst ),
                /*
                 * dma write module interface fot axi full
                 */
                .tx_wr_req_tlp_data  	(pcie_tx_wr_req_tlp_data   ),
                .tx_wr_req_tlp_strb  	(pcie_tx_wr_req_tlp_strb   ),
                .tx_wr_req_tlp_hdr   	(pcie_tx_wr_req_tlp_hdr    ),
                .tx_wr_req_tlp_seq   	(pcie_tx_wr_req_tlp_seq    ),
                .tx_wr_req_tlp_valid 	(pcie_tx_wr_req_tlp_valid  ),
                .tx_wr_req_tlp_sop   	(pcie_tx_wr_req_tlp_sop    ),
                .tx_wr_req_tlp_eop   	(pcie_tx_wr_req_tlp_eop    ),
                .tx_wr_req_tlp_ready 	(pcie_tx_wr_req_tlp_ready  ),
                .MaxPayloadSize      	(cfg_max_payload       ),

                /*
                 * dma read module interface fot axi full
                 */
                .tx_rd_req_tlp_hdr      (pcie_tx_rd_req_tlp_hdr),
                .tx_rd_req_tlp_seq      (pcie_tx_rd_req_tlp_seq),
                .tx_rd_req_tlp_valid    (pcie_tx_rd_req_tlp_valid),
                .tx_rd_req_tlp_sop      (pcie_tx_rd_req_tlp_sop),
                .tx_rd_req_tlp_eop      (pcie_tx_rd_req_tlp_eop),
                .tx_rd_req_tlp_ready    (pcie_tx_rd_req_tlp_ready),
                .rx_cpl_tlp_data        (pcie_rx_cpl_tlp_data),
                .rx_cpl_tlp_hdr         (pcie_rx_cpl_tlp_hdr),
                .rx_cpl_tlp_error       (pcie_rx_cpl_tlp_error),
                .rx_cpl_tlp_valid       (pcie_rx_cpl_tlp_valid),
                .rx_cpl_tlp_sop         (pcie_rx_cpl_tlp_sop),
                .rx_cpl_tlp_eop         (pcie_rx_cpl_tlp_eop),
                .rx_cpl_tlp_ready       (pcie_rx_cpl_tlp_ready),

                .tx_wr_sglist_irq       (tx_wr_sglist_irq),
                .tx_rd_sglist_irq       (tx_rd_sglist_irq),
                .ext_tag_enable         (ext_tag_enable),
                .rcb_128b               (cfg_rcb_status[0]),
                .requester_id           ({bus_num, 5'd0, 3'd0}),
                .max_read_payloadSize   (cfg_max_read_req),

                /*
                 * Scatter-Gather DMA descriptor interface
                 */
                .desc_rd_req_sglist_length  (H2C_SgList_length),
                .desc_rd_req_sglist_address ({H2C_SgList_HIGH_address,H2C_SgList_LOW_address}),
                .desc_rd_req_sglist_start   (H2C_SgList_Start),
                .desc_rd_req_sgdma_start    (H2C_SgDMA_Start),
                .desc_rd_req_sgdma_ramaddr  ({H2C_SgSDRAM_HIGH_address,H2C_SgSDRAM_LOW_address}),
                .desc_rd_req_sgdma_length   (H2C_SgDMA_length),
                .desc_wr_req_sglist_length  (C2H_SgList_length),
                .desc_wr_req_sglist_address ({C2H_SgList_HIGH_address,C2H_SgList_LOW_address}),
                .desc_wr_req_sglist_start   (C2H_SgList_Start),
                .desc_wr_req_sgdma_start    (C2H_SgDMA_Start),
                .desc_wr_req_sgdma_ramaddr  ({C2H_SgSDRAM_HIGH_address,C2H_SgSDRAM_LOW_address}),
                .desc_wr_req_sgdma_length   (C2H_SgDMA_length),
                /*
                 * AXI4-FULL interface
                 */
                .m_axi_arid     (M_AXI_ARID    ),
                .m_axi_araddr   (M_AXI_ARADDR  ),
                .m_axi_arlen    (M_AXI_ARLEN   ),
                .m_axi_arsize   (M_AXI_ARSIZE  ),
                .m_axi_arburst  (M_AXI_ARBURST ),
                .m_axi_arlock   (M_AXI_ARLOCK  ),
                .m_axi_arcache  (M_AXI_ARCACHE ),
                .m_axi_arprot   (M_AXI_ARPROT  ),
                .m_axi_arvalid  (M_AXI_ARVALID ),
                .m_axi_arready  (M_AXI_ARREADY ),
                .m_axi_rid      (M_AXI_RID     ),
                .m_axi_rdata    (M_AXI_RDATA   ),
                .m_axi_rresp    (M_AXI_RRESP   ),
                .m_axi_rlast    (M_AXI_RLAST   ),
                .m_axi_rvalid   (M_AXI_RVALID  ),
                .m_axi_rready   (M_AXI_RREADY  ),
                .m_axi_awid     (M_AXI_AWID    ),
                .m_axi_awaddr   (M_AXI_AWADDR  ),
                .m_axi_awlen    (M_AXI_AWLEN   ),
                .m_axi_awsize   (M_AXI_AWSIZE  ),
                .m_axi_awburst  (M_AXI_AWBURST ),
                .m_axi_awlock   (M_AXI_AWLOCK  ),
                .m_axi_awcache  (M_AXI_AWCACHE ),
                .m_axi_awprot   (M_AXI_AWPROT  ),
                .m_axi_awvalid  (M_AXI_AWVALID ),
                .m_axi_awready  (M_AXI_AWREADY ),
                .m_axi_wdata    (M_AXI_WDATA   ),
                .m_axi_wstrb    (M_AXI_WSTRB   ),
                .m_axi_wlast    (M_AXI_WLAST   ),
                .m_axi_wvalid   (M_AXI_WVALID  ),
                .m_axi_wready   (M_AXI_WREADY  ),
                .m_axi_bid      (M_AXI_BID     ),
                .m_axi_bresp    (M_AXI_BRESP   ),
                .m_axi_bvalid   (M_AXI_BVALID  ),
                .m_axi_bready   (M_AXI_BREADY  )
            );

            assign S_AXIS_DMA_TREADY = 'b0;               
            assign M_AXIS_DMA_TDATA  = 'b0;
            assign M_AXIS_DMA_TKEEP  = 'b0;
            assign M_AXIS_DMA_TVALID = 'b0;     
            assign M_AXIS_DMA_TLAST  = 'b0;
        end
    end
    else if(DMA_MODE == "Block_DMA")begin:Block_DMA
        if(DMA_INTERFACE_MODE == "AXI4-Stream")begin:dma_if_axis
            dma_if_pcie_axis #(
                .TLP_DATA_WIDTH          	(AXIS_PCIE_DATA_WIDTH  ),
                .TLP_SEG_COUNT           	(TLP_SEG_COUNT         ),
                .TX_SEQ_NUM_COUNT        	(TX_SEQ_NUM_COUNT      ),
                .TX_SEQ_NUM_WIDTH        	(TX_SEQ_NUM_WIDTH      ),
                .PCIE_TAG_COUNT             (PCIE_TAG_COUNT        )
            )dma_if_axis(
                .clk                 	(clk),
                .rst                 	(rst),
                //write module
                .tx_wr_req_tlp_data  	(pcie_tx_wr_req_tlp_data   ),
                .tx_wr_req_tlp_strb  	(pcie_tx_wr_req_tlp_strb   ),
                .tx_wr_req_tlp_hdr   	(pcie_tx_wr_req_tlp_hdr    ),
                .tx_wr_req_tlp_seq   	(pcie_tx_wr_req_tlp_seq    ),
                .tx_wr_req_tlp_valid 	(pcie_tx_wr_req_tlp_valid  ),
                .tx_wr_req_tlp_sop   	(pcie_tx_wr_req_tlp_sop    ),
                .tx_wr_req_tlp_eop   	(pcie_tx_wr_req_tlp_eop    ),
                .tx_wr_req_tlp_ready 	(pcie_tx_wr_req_tlp_ready  ),
                .desc_wr_req_length    	(C2HBlockDMA_length     ),
                .desc_wr_req_address   	({C2HBlockDMA_high_address,C2HBlockDMA_low_address} ),
                .MaxPayloadSize      	(cfg_max_payload       ),
                .desc_wr_req_start     	(C2HBlockDMA_Start[0]      ),
                //read module
                .tx_rd_req_tlp_hdr      (pcie_tx_rd_req_tlp_hdr),
                .tx_rd_req_tlp_seq      (pcie_tx_rd_req_tlp_seq),
                .tx_rd_req_tlp_valid    (pcie_tx_rd_req_tlp_valid),
                .tx_rd_req_tlp_sop      (pcie_tx_rd_req_tlp_sop),
                .tx_rd_req_tlp_eop      (pcie_tx_rd_req_tlp_eop),
                .tx_rd_req_tlp_ready    (pcie_tx_rd_req_tlp_ready),

                .rx_cpl_tlp_data        (pcie_rx_cpl_tlp_data),
                .rx_cpl_tlp_hdr         (pcie_rx_cpl_tlp_hdr),
                .rx_cpl_tlp_error       (pcie_rx_cpl_tlp_error),
                .rx_cpl_tlp_valid       (pcie_rx_cpl_tlp_valid),
                .rx_cpl_tlp_sop         (pcie_rx_cpl_tlp_sop),
                .rx_cpl_tlp_eop         (pcie_rx_cpl_tlp_eop),
                .rx_cpl_tlp_ready       (pcie_rx_cpl_tlp_ready),

                .ext_tag_enable         (ext_tag_enable),
                .rcb_128b               (cfg_rcb_status[0]),
                .requester_id           ({bus_num, 5'd0, 3'd0}),
                // .tx_rd_req_irq          (tx_rd_req_irq),

                .desc_tx_rd_req_length  (H2CBlockDMA_length),
                .desc_tx_rd_req_address ({H2CBlockDMA_high_address, H2CBlockDMA_low_address}),
                .Max_read_PayloadSize   (cfg_max_read_req),
                .desc_tx_rd_req_start   (H2CBlockDMA_Start[0]),  

                /*
                 * AXI4_Stream interface
                 */
                .s_axis_tlp_tdata    	(S_AXIS_DMA_TDATA ),
                .s_axis_tlp_tkeep    	(S_AXIS_DMA_TKEEP ),
                .s_axis_tlp_tvalid   	(S_AXIS_DMA_TVALID),
                .s_axis_tlp_tlast    	(S_AXIS_DMA_TLAST ),
                .s_axis_tlp_tready   	(S_AXIS_DMA_TREADY),

                .m_axis_tlp_tdata       (M_AXIS_DMA_TDATA ),
                .m_axis_tlp_tkeep       (M_AXIS_DMA_TKEEP ),
                .m_axis_tlp_tvalid      (M_AXIS_DMA_TVALID),
                .m_axis_tlp_tlast       (M_AXIS_DMA_TLAST ),
                .m_axis_tlp_tready      (M_AXIS_DMA_TREADY)
            );
	        assign M_AXI_ARID      = 'b0;
	        assign M_AXI_ARADDR    = 'b0;
	        assign M_AXI_ARLEN     = 'b0;
	        assign M_AXI_ARSIZE    = 'b0;
	        assign M_AXI_ARBURST   = 'b0;
	        assign M_AXI_ARLOCK    = 'b0;
	        assign M_AXI_ARCACHE   = 'b0;
	        assign M_AXI_ARPROT    = 'b0;
	        assign M_AXI_ARQOS     = 'b0;
	        assign M_AXI_ARVALID   = 'b0;
	        assign M_AXI_RREADY    = 'b0;
	        assign M_AXI_AWID      = 'b0;
	        assign M_AXI_AWADDR    = 'b0;
	        assign M_AXI_AWLEN     = 'b0;
	        assign M_AXI_AWSIZE    = 'b0;
	        assign M_AXI_AWBURST   = 'b0;
	        assign M_AXI_AWLOCK    = 'b0;
	        assign M_AXI_AWCACHE   = 'b0;
            assign M_AXI_AWPROT    = 'b0;
            assign M_AXI_AWQOS     = 'b0;
	        assign M_AXI_AWVALID   = 'b0;
	        assign M_AXI_WDATA  = 'b0;
            assign M_AXI_WSTRB  = 'b0;
            assign M_AXI_WLAST  = 'b0;
	        assign M_AXI_WVALID = 'b0;
	        assign M_AXI_BREADY = 'b0;
        end
        else if(DMA_INTERFACE_MODE == "AXI_MEMORY_MAP")begin : dma_if_axi_full
            dma_if_pcie_axi #(
                .TLP_DATA_WIDTH    	(TLP_DATA_WIDTH  ),
                .TLP_STRB_WIDTH    	(TLP_STRB_WIDTH  ),
                .TLP_HDR_WIDTH     	(TLP_HDR_WIDTH   ),
                .TLP_SEG_COUNT     	(TLP_SEG_COUNT   ),
                .PCIE_ADDR_WIDTH   	(PCIE_ADDR_WIDTH ),
                .TX_SEQ_NUM_COUNT  	(TX_SEQ_NUM_COUNT),
                .TX_SEQ_NUM_WIDTH  	(TX_SEQ_NUM_WIDTH),
                .PCIE_TAG_COUNT    	(PCIE_TAG_COUNT  ),
                .OP_TABLE_SIZE     	(PCIE_TAG_COUNT  ),
                .AXI_DATA_WIDTH    	(AXI_DATA_WIDTH  ),
                .AXI_ADDR_WIDTH    	(AXI_ADDR_WIDTH  ),
                .AXI_STRB_WIDTH    	(AXI_STRB_WIDTH  ),
                .AXI_ID_WIDTH      	(AXI_ID_WIDTH    ),
                .AXI_MAX_BURST_LEN 	(AXI_MAX_BURST_LEN)
            )dma_if_axi(
                .clk                    	(clk ),
                .rst                    	(rst ),
                /*
                 * dma write module interface fot axi full
                 */
                .tx_wr_req_tlp_data  	(pcie_tx_wr_req_tlp_data   ),
                .tx_wr_req_tlp_strb  	(pcie_tx_wr_req_tlp_strb   ),
                .tx_wr_req_tlp_hdr   	(pcie_tx_wr_req_tlp_hdr    ),
                .tx_wr_req_tlp_seq   	(pcie_tx_wr_req_tlp_seq    ),
                .tx_wr_req_tlp_valid 	(pcie_tx_wr_req_tlp_valid  ),
                .tx_wr_req_tlp_sop   	(pcie_tx_wr_req_tlp_sop    ),
                .tx_wr_req_tlp_eop   	(pcie_tx_wr_req_tlp_eop    ),
                .tx_wr_req_tlp_ready 	(pcie_tx_wr_req_tlp_ready  ),
                .desc_wr_req_length    	(C2HBlockDMA_length     ),
                .desc_wr_req_address   	({C2HBlockDMA_high_address,C2HBlockDMA_low_address} ),
                .desc_wr_req_start     	(C2HBlockDMA_Start[0]      ),
                .desc_wr_ram_addr       ({C2H_DMA_SDRAM_HIGH_ADDRESS,C2H_DMA_SDRAM_LOW_ADDRESS}),
                .MaxPayloadSize      	(cfg_max_payload       ),

                /*
                 * dma read module interface fot axi full
                 */
                .tx_rd_req_tlp_hdr      (pcie_tx_rd_req_tlp_hdr),
                .tx_rd_req_tlp_seq      (pcie_tx_rd_req_tlp_seq),
                .tx_rd_req_tlp_valid    (pcie_tx_rd_req_tlp_valid),
                .tx_rd_req_tlp_sop      (pcie_tx_rd_req_tlp_sop),
                .tx_rd_req_tlp_eop      (pcie_tx_rd_req_tlp_eop),
                .tx_rd_req_tlp_ready    (pcie_tx_rd_req_tlp_ready),
                .rx_cpl_tlp_data        (pcie_rx_cpl_tlp_data),
                .rx_cpl_tlp_hdr         (pcie_rx_cpl_tlp_hdr),
                .rx_cpl_tlp_error       (pcie_rx_cpl_tlp_error),
                .rx_cpl_tlp_valid       (pcie_rx_cpl_tlp_valid),
                .rx_cpl_tlp_sop         (pcie_rx_cpl_tlp_sop),
                .rx_cpl_tlp_eop         (pcie_rx_cpl_tlp_eop),
                .rx_cpl_tlp_ready       (pcie_rx_cpl_tlp_ready),
                .ext_tag_enable         (ext_tag_enable),
                .rcb_128b               (cfg_rcb_status[0]),
                .requester_id           ({bus_num, 5'd0, 3'd0}),
                .desc_tx_rd_req_length  (H2CBlockDMA_length),
                .desc_rd_ram_addr       ({H2C_DMA_SDRAM_HIGH_ADDRESS,H2C_DMA_SDRAM_LOW_ADDRESS}),
                .desc_tx_rd_req_address ({H2CBlockDMA_high_address, H2CBlockDMA_low_address}),
                .desc_tx_rd_req_start   (H2CBlockDMA_Start[0]),  
                .Max_read_PayloadSize   (cfg_max_read_req),
                // .tx_rd_req_irq          (tx_rd_req_irq),

                /*
                 * AXI4-FULL interface
                 */
                .m_axi_arid     (M_AXI_ARID    ),
                .m_axi_araddr   (M_AXI_ARADDR  ),
                .m_axi_arlen    (M_AXI_ARLEN   ),
                .m_axi_arsize   (M_AXI_ARSIZE  ),
                .m_axi_arburst  (M_AXI_ARBURST ),
                .m_axi_arlock   (M_AXI_ARLOCK  ),
                .m_axi_arcache  (M_AXI_ARCACHE ),
                .m_axi_arprot   (M_AXI_ARPROT  ),
                .m_axi_arvalid  (M_AXI_ARVALID ),
                .m_axi_arready  (M_AXI_ARREADY ),
                .m_axi_rid      (M_AXI_RID     ),
                .m_axi_rdata    (M_AXI_RDATA   ),
                .m_axi_rresp    (M_AXI_RRESP   ),
                .m_axi_rlast    (M_AXI_RLAST   ),
                .m_axi_rvalid   (M_AXI_RVALID  ),
                .m_axi_rready   (M_AXI_RREADY  ),
                .m_axi_awid     (M_AXI_AWID    ),
                .m_axi_awaddr   (M_AXI_AWADDR  ),
                .m_axi_awlen    (M_AXI_AWLEN   ),
                .m_axi_awsize   (M_AXI_AWSIZE  ),
                .m_axi_awburst  (M_AXI_AWBURST ),
                .m_axi_awlock   (M_AXI_AWLOCK  ),
                .m_axi_awcache  (M_AXI_AWCACHE ),
                .m_axi_awprot   (M_AXI_AWPROT  ),
                .m_axi_awvalid  (M_AXI_AWVALID ),
                .m_axi_awready  (M_AXI_AWREADY ),
                .m_axi_wdata    (M_AXI_WDATA   ),
                .m_axi_wstrb    (M_AXI_WSTRB   ),
                .m_axi_wlast    (M_AXI_WLAST   ),
                .m_axi_wvalid   (M_AXI_WVALID  ),
                .m_axi_wready   (M_AXI_WREADY  ),
                .m_axi_bid      (M_AXI_BID     ),
                .m_axi_bresp    (M_AXI_BRESP   ),
                .m_axi_bvalid   (M_AXI_BVALID  ),
                .m_axi_bready   (M_AXI_BREADY  )
            );

            assign S_AXIS_DMA_TREADY = 'b0;               
            assign M_AXIS_DMA_TDATA  = 'b0;
            assign M_AXIS_DMA_TKEEP  = 'b0;
            assign M_AXIS_DMA_TVALID = 'b0;     
            assign M_AXIS_DMA_TLAST  = 'b0;
        end
    end
endgenerate


generate 
if(DMA_MODE=="Block_DMA")begin:block_irq
    dma_tx_wr_irq #(
        .AXIS_PCIE_DATA_WIDTH    	(AXIS_PCIE_DATA_WIDTH),
        .AXIS_PCIE_KEEP_WIDTH    	(AXIS_PCIE_KEEP_WIDTH),
        .AXIS_PCIE_RC_USER_WIDTH 	(AXIS_PCIE_RC_USER_WIDTH)
    )dma_wr_irq(
        .clk              	(clk ),
        .rst              	(rst ),
        .m_axis_rq_tkeep  	(m_axis_rq_tkeep),
        .m_axis_rq_tlast  	(m_axis_rq_tlast),
        .m_axis_rq_tready 	(m_axis_rq_tready),
        .m_axis_rq_tuser  	(m_axis_rq_tuser),
        .m_axis_rq_tvalid 	(m_axis_rq_tvalid),
        .tx_wr_length     	(C2HBlockDMA_length),
        .cfg_max_payload  	(cfg_max_payload),
        .tx_wr_start      	(C2HBlockDMA_Start),
        .tx_wr_irq        	(tx_wr_req_irq)
    );


    dma_rx_rd_irq #(
        .AXIS_PCIE_DATA_WIDTH    	(AXIS_PCIE_DATA_WIDTH),
        .AXIS_PCIE_KEEP_WIDTH    	(AXIS_PCIE_KEEP_WIDTH),
        .AXIS_PCIE_RC_USER_WIDTH 	(AXIS_PCIE_RC_USER_WIDTH)
    )dma_rd_irq(
        .clk                  	(clk),
        .rst                  	(rst),
        .s_axis_rc_tdata      	(s_axis_rc_tdata  ),
        .s_axis_rc_tkeep      	(s_axis_rc_tkeep  ),
        .s_axis_rc_tready     	(s_axis_rc_tready ),
        .s_axis_rc_tuser      	(s_axis_rc_tuser  ),
        .s_axis_rc_tvalid     	(s_axis_rc_tvalid ),
        .tx_rd_length         	(H2CBlockDMA_length),
        .cfg_max_read_payload 	(cfg_max_read_req),
        .tx_rd_start          	(H2CBlockDMA_Start[0]),
        .tx_rd_irq            	(tx_rd_req_irq)
    );

end
else if(DMA_MODE == "Scatter_Gather")begin:sgdma_irq
    dma_tx_wr_irq #(
        .AXIS_PCIE_DATA_WIDTH    	(AXIS_PCIE_DATA_WIDTH),
        .AXIS_PCIE_KEEP_WIDTH    	(AXIS_PCIE_KEEP_WIDTH),
        .AXIS_PCIE_RC_USER_WIDTH 	(AXIS_PCIE_RC_USER_WIDTH)
    )dma_wr_irq(
        .clk              	(clk ),
        .rst              	(rst ),
        .m_axis_rq_tkeep  	(m_axis_rq_tkeep),
        .m_axis_rq_tlast  	(m_axis_rq_tlast),
        .m_axis_rq_tready 	(m_axis_rq_tready),
        .m_axis_rq_tuser  	(m_axis_rq_tuser),
        .m_axis_rq_tvalid 	(m_axis_rq_tvalid),
        .tx_wr_length     	(C2H_SgDMA_length),
        .cfg_max_payload  	(cfg_max_payload),
        .tx_wr_start      	(C2H_SgDMA_Start),
        .tx_wr_irq        	(tx_sgdma_irq)
    );


    dma_rx_rd_irq #(
        .AXIS_PCIE_DATA_WIDTH    	(AXIS_PCIE_DATA_WIDTH),
        .AXIS_PCIE_KEEP_WIDTH    	(AXIS_PCIE_KEEP_WIDTH),
        .AXIS_PCIE_RC_USER_WIDTH 	(AXIS_PCIE_RC_USER_WIDTH)
    )dma_rd_irq(
        .clk                  	(clk),
        .rst                  	(rst),
        .s_axis_rc_tdata      	(s_axis_rc_tdata ),
        .s_axis_rc_tkeep      	(s_axis_rc_tkeep ),
        .s_axis_rc_tready     	(s_axis_rc_tready),
        .s_axis_rc_tuser      	(s_axis_rc_tuser ),
        .s_axis_rc_tvalid     	(s_axis_rc_tvalid),
        .tx_rd_length         	(H2C_SgDMA_length),
        .cfg_max_read_payload 	(cfg_max_read_req),
        .tx_rd_start          	(H2C_SgDMA_Start),
        .tx_rd_irq            	(rx_sgdma_irq)
    );

end
endgenerate



dma_intr_queue #(
    .MSI_COUNT    (MSI_COUNT),
    .USER_MSI_IRQ (USER_MSI_IRQ)
) irq_dma(
    .clk (clk),
    .rst (rst),
    .msi_irq_req(msi_irq_req),
    .msi_irq_ack(msi_irq_ack),
    .cfg_interrupt_msi_enable(cfg_interrupt_msi_enable),
    .cfg_interrupt_msi_vf_enable(cfg_interrupt_msi_vf_enable),
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
    .cfg_interrupt_msi_function_number(cfg_interrupt_msi_function_number)
);


//ila_0 ila_sgdma (
//	.clk(clk), // input wire clk
//	.probe0(pcie_tx_wr_req_tlp_data), // input wire [511:0]  probe0  
//	.probe1(pcie_tx_wr_req_tlp_hdr), // input wire [127:0]  probe1 
//	.probe2(pcie_tx_wr_req_tlp_seq), // input wire [5:0]  probe2 
//	.probe3(pcie_tx_wr_req_tlp_valid), // input wire [0:0]  probe3 
//	.probe4(pcie_tx_wr_req_tlp_sop), // input wire [0:0]  probe4 
//	.probe5(pcie_tx_wr_req_tlp_eop), // input wire [0:0]  probe5 
//	.probe6(pcie_tx_wr_req_tlp_ready), // input wire [0:0]  probe6 
//	.probe7(pcie_tx_rd_req_tlp_hdr), // input wire [127:0]  probe7 
//	.probe8(pcie_tx_rd_req_tlp_seq), // input wire [5:0]  probe8 
//	.probe9(pcie_tx_rd_req_tlp_valid), // input wire [0:0]  probe9 
//	.probe10(pcie_tx_rd_req_tlp_sop), // input wire [0:0]  probe10 
//	.probe11(pcie_tx_rd_req_tlp_eop), // input wire [0:0]  probe11 
//	.probe12(pcie_tx_rd_req_tlp_ready), // input wire [0:0]  probe12 
//	.probe13(pcie_rx_cpl_tlp_data), // input wire [511:0]  probe13 
//	.probe14(pcie_rx_cpl_tlp_hdr), // input wire [127:0]  probe14 
//	.probe15(pcie_rx_cpl_tlp_ready), // input wire [0:0]  probe15 
//	.probe16(pcie_rx_cpl_tlp_valid), // input wire [0:0]  probe16 
//	.probe17(pcie_rx_cpl_tlp_sop), // input wire [0:0]  probe17 
//	.probe18(pcie_rx_cpl_tlp_eop) // input wire [0:0]  probe18
//);


endmodule
`resetall