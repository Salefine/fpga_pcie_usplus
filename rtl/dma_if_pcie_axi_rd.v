/****************************************************************************
 * @file    dma_if_pcie_axis_rd.v
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


/******************************************************************************
 *                 Requester Request Descriptor Format (MRd, 4DW)
 *
 * 63                                                                   32 31                                                                   0
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |                               DW+1                                  | |                               DW+0                                  |
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |-------+7------| |-------+6------| |-------+5------| |-------+4------| |-------+3------| |-------+2------| |-------+1------| |-------+0------|
 * |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0|
 * |             Requester ID        | |  Tag          | LastBE | FirstBE|  R|AT|attr|EP|TD|TH|R|TC|R|Fmt/Type/Length|
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * 127                                                                  96 95                                                                   64
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |                               DW+3                                  | |                               DW+2                                  |
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |------ +15-----| |------ +14-----| |------ +13-----| |------ +12-----| |------ +11-----| |------ +10-----| |-------+9------| |-------+8------|
 * |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0|
 * |                                                                 Address[63:2]                                                           | PH |
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 *
 * Example (MRd, 512B, Tag=0x2A, Addr=0x00000000_FCF00000):
 *   DW0: 0x20000080   // FMT=001, TYPE=00000, LEN=0x080 (128DW)
 *   DW1: 0x00002AFF   // ReqID=0x0000, Tag=0x2A, LastBE=F, FirstBE=F
 *   DW2: 0x00000000
 *   DW3: 0xFCF00000
 *   Header[127:0] = 0x20000080_00002AFF_00000000_FCF00000
 *
 * CPLD header
 * +----------------++----------------++----------------++----------------+
 * | 7 6 5 4 3 2 1 0|| 7 6 5 4 3 2 1 0|| 7 6 5 4 3 2 1 0|| 7 6 5 4 3 2 1 0|
 * | |FMT| |  type  || R   TC  R     
 ******************************************************************************/   
 `resetall
 `timescale 1ns/1ps
 `default_nettype none
module dma_if_pcie_axi_rd#(

    parameter RELAX_ORDER_ENABLE  = 0,
    // TLP data width
    parameter TLP_DATA_WIDTH = 256,
    // TLP header width
    parameter TLP_HDR_WIDTH = 128,
    // TLP segment count
    parameter TLP_SEG_COUNT = 1,
    // TX sequence number width
    parameter TX_SEQ_NUM_WIDTH = 6,
    // PCIe address width
    parameter PCIE_ADDR_WIDTH = 64,
    // PCIe tag count
    parameter PCIE_TAG_COUNT = 32,
    // Operation table size
    parameter OP_TABLE_SIZE = PCIE_TAG_COUNT,

    // Width of AXI data bus in bits
    parameter AXI_DATA_WIDTH = 32,
    // Width of AXI address bus in bits
    parameter AXI_ADDR_WIDTH = 16,
    // Width of AXI wstrb (width of data bus in words)
    parameter AXI_STRB_WIDTH = (AXI_DATA_WIDTH/8),
    // Width of AXI ID signal
    parameter AXI_ID_WIDTH = 8,
    parameter USER_ID_ENABLE = 0,
    // Maximum AXI burst length to generate
    parameter AXI_MAX_BURST_LEN = 256,

    parameter AXIS_KEEP_ENABLE = 1,
    parameter AXIS_LAST_ENABLE = 1,
    parameter AXIS_ID_ENABLE   = 0,
    parameter AXIS_ID_WIDTH    = 8,
    parameter AXIS_DEST_ENABLE = 0,
    parameter AXIS_DEST_WIDTH  = 1,
    parameter AXIS_USER_ENABLE = 0,
    parameter AXIS_USER_WIDTH  = 1,
    parameter TAG_WIDTH        = 8
) (
    input   wire    clk ,
    input   wire    rst ,
    /*
     * TLP input (read request from DMA)
     * such as :0x200000800000000000000000fcf00000
     */
    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_rd_req_tlp_hdr  ,
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_rd_req_tlp_seq  ,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_valid,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_sop  ,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_eop  ,
    input   wire                                          tx_rd_req_tlp_ready,

    /*
     * TLP input (completion)
     */
    input  wire [TLP_DATA_WIDTH-1:0]                     rx_cpl_tlp_data ,
    input  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        rx_cpl_tlp_hdr  ,
    input  wire [TLP_SEG_COUNT*4-1:0]                    rx_cpl_tlp_error,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_sop  ,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_eop  ,
    output wire                                          rx_cpl_tlp_ready,
    /*
     * Configuration
     */

    input  wire                  ext_tag_enable,
    input  wire [3 :0]           rcb_128b      ,
    input  wire [15:0]           requester_id  ,
    input  wire [2 : 0]          Max_read_PayloadSize     ,

    /*
     * AXI4-Stream input
     */
    input  wire [31 : 0]         desc_tx_rd_req_length         ,//bytes
    input  wire [PCIE_ADDR_WIDTH-1 : 0] desc_tx_rd_req_address        ,
    input  wire                  desc_tx_rd_req_start          ,
    input  wire [AXI_ADDR_WIDTH-1:0] desc_tx_rd_req_ramaddr,
    
    
    /*
     * AXI master interface
     */
    output wire [AXI_ID_WIDTH-1:0]       m_axi_awid,
    output wire [AXI_ADDR_WIDTH-1:0]     m_axi_awaddr,
    output wire [7:0]                    m_axi_awlen,
    output wire [2:0]                    m_axi_awsize,
    output wire [1:0]                    m_axi_awburst,
    output wire                          m_axi_awlock,
    output wire [3:0]                    m_axi_awcache,
    output wire [2:0]                    m_axi_awprot,
    output wire                          m_axi_awvalid,
    input  wire                          m_axi_awready,
    output wire [AXI_DATA_WIDTH-1:0]     m_axi_wdata,
    output wire [AXI_STRB_WIDTH-1:0]     m_axi_wstrb,
    output wire                          m_axi_wlast,
    output wire                          m_axi_wvalid,
    input  wire                          m_axi_wready,
    input  wire [AXI_ID_WIDTH-1:0]       m_axi_bid,
    input  wire [1:0]                    m_axi_bresp,
    input  wire                          m_axi_bvalid,
    output wire                          m_axi_bready

);

localparam AXIS_DATA_WIDTH = AXI_DATA_WIDTH;
localparam AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8;

wire [AXIS_DATA_WIDTH-1:0]s_axis_write_data_tdata  ;
wire [AXIS_KEEP_WIDTH-1:0]s_axis_write_data_tkeep  ;
wire s_axis_write_data_tvalid ;
wire s_axis_write_data_tready ;
wire s_axis_write_data_tlast  ;

wire [AXI_ADDR_WIDTH-1:0] s_axis_write_desc_addr = desc_tx_rd_req_ramaddr;
wire [TAG_WIDTH-1:0] s_axis_write_desc_tag = 'b0;
wire [31:0] s_axis_write_desc_len = desc_tx_rd_req_length;
reg s_axis_write_desc_valid = 0; wire s_axis_write_desc_ready;
reg desc_rd_req_start_reg = 0;

always @(posedge clk) begin
  if (rst) begin
    s_axis_write_desc_valid <= 'b0;
    desc_rd_req_start_reg <= 'b0;
  end
  else if (s_axis_write_desc_valid & s_axis_write_desc_ready) begin
    s_axis_write_desc_valid <= 'b0;
  end
  else if (desc_tx_rd_req_start && (~desc_rd_req_start_reg)) begin
    s_axis_write_desc_valid <= 'b1;
  end
  desc_rd_req_start_reg <= desc_tx_rd_req_start;
end


axi_dma_wr #(
  .AXI_DATA_WIDTH    	(AXI_DATA_WIDTH  ),
  .AXI_ADDR_WIDTH    	(AXI_ADDR_WIDTH  ),
  .AXI_STRB_WIDTH    	(AXI_STRB_WIDTH  ),
  .AXI_ID_WIDTH      	(AXI_ID_WIDTH    ),
  .AXI_MAX_BURST_LEN 	(AXI_MAX_BURST_LEN),
  .AXIS_DATA_WIDTH   	(AXIS_DATA_WIDTH ),
  .AXIS_KEEP_ENABLE  	(AXIS_KEEP_ENABLE),
  .AXIS_KEEP_WIDTH   	(AXIS_KEEP_WIDTH ),
  .AXIS_LAST_ENABLE  	(AXIS_LAST_ENABLE),
  .AXIS_ID_ENABLE    	(AXIS_ID_ENABLE ),
  .AXIS_ID_WIDTH     	(AXIS_ID_WIDTH   ),
  .AXIS_DEST_ENABLE  	(AXIS_DEST_ENABLE),
  .AXIS_DEST_WIDTH   	(AXIS_DEST_WIDTH),
  .AXIS_USER_ENABLE  	(AXIS_USER_ENABLE),
  .AXIS_USER_WIDTH   	(AXIS_USER_WIDTH),
  .LEN_WIDTH         	(32             ),
  .TAG_WIDTH         	(TAG_WIDTH       ),
  .ENABLE_SG         	(0               ),
  .ENABLE_UNALIGNED  	(0               )
)dma_axi_wr(
  .clk                            	(clk ),
  .rst                            	(rst ),
  .s_axis_write_desc_addr         	(s_axis_write_desc_addr  ),
  .s_axis_write_desc_len          	(s_axis_write_desc_len   ),
  .s_axis_write_desc_tag          	(s_axis_write_desc_tag   ),
  .s_axis_write_desc_valid        	(s_axis_write_desc_valid ),
  .s_axis_write_desc_ready        	(s_axis_write_desc_ready ),

  .m_axis_write_desc_status_len   	(),
  .m_axis_write_desc_status_tag   	(),
  .m_axis_write_desc_status_id    	(),
  .m_axis_write_desc_status_dest  	(),
  .m_axis_write_desc_status_user  	(),
  .m_axis_write_desc_status_error 	(),
  .m_axis_write_desc_status_valid 	(),

  .s_axis_write_data_tdata        	(s_axis_write_data_tdata  ),
  .s_axis_write_data_tkeep        	(s_axis_write_data_tkeep  ),
  .s_axis_write_data_tvalid       	(s_axis_write_data_tvalid ),
  .s_axis_write_data_tready       	(s_axis_write_data_tready ),
  .s_axis_write_data_tlast        	(s_axis_write_data_tlast  ),
  .s_axis_write_data_tid          	('b0),
  .s_axis_write_data_tdest        	('b0),
  .s_axis_write_data_tuser        	('b0),

  .m_axi_awid                     	(m_axi_awid    ),
  .m_axi_awaddr                   	(m_axi_awaddr  ),
  .m_axi_awlen                    	(m_axi_awlen   ),
  .m_axi_awsize                   	(m_axi_awsize  ),
  .m_axi_awburst                  	(m_axi_awburst ),
  .m_axi_awlock                   	(m_axi_awlock  ),
  .m_axi_awcache                  	(m_axi_awcache ),
  .m_axi_awprot                   	(m_axi_awprot  ),
  .m_axi_awvalid                  	(m_axi_awvalid ),
  .m_axi_awready                  	(m_axi_awready ),
  .m_axi_wdata                    	(m_axi_wdata   ),
  .m_axi_wstrb                    	(m_axi_wstrb   ),
  .m_axi_wlast                    	(m_axi_wlast   ),
  .m_axi_wvalid                   	(m_axi_wvalid  ),
  .m_axi_wready                   	(m_axi_wready  ),
  .m_axi_bid                      	(m_axi_bid     ),
  .m_axi_bresp                    	(m_axi_bresp   ),
  .m_axi_bvalid                   	(m_axi_bvalid  ),
  .m_axi_bready                   	(m_axi_bready  ),
  .enable                         	(1'b1          )
);


dma_if_pcie_axis_rd_v1 #(
  .TLP_DATA_WIDTH   	(TLP_DATA_WIDTH),
  .TLP_HDR_WIDTH    	(TLP_HDR_WIDTH),
  .TLP_SEG_COUNT    	(TLP_SEG_COUNT),
  .TX_SEQ_NUM_WIDTH 	(TX_SEQ_NUM_WIDTH),
  .PCIE_ADDR_WIDTH  	(PCIE_ADDR_WIDTH),
  .PCIE_TAG_COUNT   	(PCIE_TAG_COUNT),
  .OP_TABLE_SIZE    	(OP_TABLE_SIZE)
)pcie_axis_rd(
  .clk                    	(clk                     ),
  .rst                    	(rst                     ),
  .tx_rd_req_tlp_hdr      	(tx_rd_req_tlp_hdr       ),
  .tx_rd_req_tlp_seq      	(tx_rd_req_tlp_seq       ),
  .tx_rd_req_tlp_valid    	(tx_rd_req_tlp_valid     ),
  .tx_rd_req_tlp_sop      	(tx_rd_req_tlp_sop       ),
  .tx_rd_req_tlp_eop      	(tx_rd_req_tlp_eop       ),
  .tx_rd_req_tlp_ready    	(tx_rd_req_tlp_ready     ),
  .rx_cpl_tlp_data        	(rx_cpl_tlp_data         ),
  .rx_cpl_tlp_hdr         	(rx_cpl_tlp_hdr          ),
  .rx_cpl_tlp_error       	(rx_cpl_tlp_error        ),
  .rx_cpl_tlp_valid       	(rx_cpl_tlp_valid        ),
  .rx_cpl_tlp_sop         	(rx_cpl_tlp_sop          ),
  .rx_cpl_tlp_eop         	(rx_cpl_tlp_eop          ),
  .rx_cpl_tlp_ready       	(rx_cpl_tlp_ready        ),
  .ext_tag_enable         	(ext_tag_enable          ),
  .rcb_128b               	(rcb_128b                ),
  .requester_id           	(requester_id            ),
  .Max_read_PayloadSize   	(Max_read_PayloadSize    ),
  .desc_tx_rd_req_length  	(desc_tx_rd_req_length   ),
  .desc_tx_rd_req_address 	(desc_tx_rd_req_address  ),
  .desc_tx_rd_req_start   	(desc_tx_rd_req_start    ),

  .m_axis_tlp_tdata       	(s_axis_write_data_tdata ),
  .m_axis_tlp_tkeep       	(s_axis_write_data_tkeep ),
  .m_axis_tlp_tvalid      	(s_axis_write_data_tvalid),
  .m_axis_tlp_tlast       	(s_axis_write_data_tlast ),
  .m_axis_tlp_tready      	(s_axis_write_data_tready)
);


endmodule
`resetall