/****************************************************************************
 * @file    sgdma_if_pcie_axi_wr.v
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
`default_nettype none

module sgdma_if_pcie_axi_wr #(
    // TLP data width
    parameter TLP_DATA_WIDTH = 256,
    // TLP strobe width
    parameter TLP_STRB_WIDTH = TLP_DATA_WIDTH/32,
    // TLP header width
    parameter TLP_HDR_WIDTH = 128,
    // TLP segment count
    parameter TLP_SEG_COUNT = 1,
    // PCIe address width
    parameter PCIE_ADDR_WIDTH = 64,
    // TX sequence number count
    parameter TX_SEQ_NUM_COUNT = 1,
    // TX sequence number width
    parameter TX_SEQ_NUM_WIDTH = 6  ,

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
)(
    input   wire    clk ,
    input   wire    rst ,
    //1.
    output  wire [TLP_DATA_WIDTH-1:0]                     tx_wr_req_tlp_data,
    output  wire [TLP_STRB_WIDTH-1:0]                     tx_wr_req_tlp_strb,
    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_wr_req_tlp_hdr,
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_wr_req_tlp_seq,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_valid,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_sop,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_eop,
    input   wire                                          tx_wr_req_tlp_ready,

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

    input  wire [31 : 0] desc_wr_req_sglist_length  ,
    input  wire [PCIE_ADDR_WIDTH-1 : 0]  desc_wr_req_sglist_address ,
    input  wire desc_wr_req_sglist_start   ,
    input  wire desc_wr_req_sgdma_start    ,
    input  wire [31 : 0] desc_wr_req_sgdma_length   ,
    input  wire [AXI_ADDR_WIDTH-1:0] desc_wr_req_sgdma_ramaddr  ,
    
    output wire            tx_wr_sglist_irq    ,
    input  wire [15: 0]    requester_id        ,
    input  wire [2 : 0]    MaxPayloadSize      ,
    input  wire [2 : 0]    max_read_payloadSize,

    output wire [AXI_ID_WIDTH-1:0]       m_axi_arid,
    output wire [AXI_ADDR_WIDTH-1:0]     m_axi_araddr,
    output wire [7:0]                    m_axi_arlen,
    output wire [2:0]                    m_axi_arsize,
    output wire [1:0]                    m_axi_arburst,
    output wire                          m_axi_arlock,
    output wire [3:0]                    m_axi_arcache,
    output wire [2:0]                    m_axi_arprot,
    output wire                          m_axi_arvalid,
    input  wire                          m_axi_arready,
    input  wire [AXI_ID_WIDTH-1:0]       m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0]     m_axi_rdata,
    input  wire [1:0]                    m_axi_rresp,
    input  wire                          m_axi_rlast,
    input  wire                          m_axi_rvalid,
    output wire                          m_axi_rready
);

localparam AXIS_DATA_WIDTH = AXI_DATA_WIDTH;
localparam AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8;

wire [AXIS_DATA_WIDTH-1:0]m_axis_read_data_tdata ;
wire [AXIS_KEEP_WIDTH-1:0]m_axis_read_data_tkeep ;
wire m_axis_read_data_tvalid;
wire m_axis_read_data_tlast ;
wire m_axis_read_data_tready;
wire [AXI_ADDR_WIDTH-1:0] s_axis_read_desc_addr = desc_wr_req_sgdma_ramaddr;
wire [31:0] s_axis_read_desc_len = desc_wr_req_sgdma_length;

reg s_axis_read_desc_valid = 0; 
wire s_axis_read_desc_ready;
reg desc_wr_req_start_reg = 0;

always @(posedge clk) begin
  if (rst) begin
    s_axis_read_desc_valid <= 'b0;
    desc_wr_req_start_reg <= 'b0;
  end
  else if (s_axis_read_desc_valid & s_axis_read_desc_ready) begin
    s_axis_read_desc_valid <= 'b0;
  end
  else if (desc_wr_req_sgdma_start && (~desc_wr_req_start_reg)) begin
    s_axis_read_desc_valid <= 'b1;
  end
  desc_wr_req_start_reg <= desc_wr_req_sgdma_start;
end

axi_dma_rd #(
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
)dma_axi_rd(
  .clk                           	(clk ),
  .rst                           	(rst ),

  .s_axis_read_desc_addr         	(s_axis_read_desc_addr ),
  .s_axis_read_desc_len          	(s_axis_read_desc_len  ),
  .s_axis_read_desc_tag          	('b0),
  .s_axis_read_desc_id           	('b0),
  .s_axis_read_desc_dest         	('b0),
  .s_axis_read_desc_user         	('b0),
  .s_axis_read_desc_valid        	(s_axis_read_desc_valid ),
  .s_axis_read_desc_ready        	(s_axis_read_desc_ready ),

  .m_axis_read_desc_status_tag   	(),
  .m_axis_read_desc_status_error 	(),
  .m_axis_read_desc_status_valid 	(),

  .m_axis_read_data_tdata        	(m_axis_read_data_tdata  ),
  .m_axis_read_data_tkeep        	(m_axis_read_data_tkeep  ),
  .m_axis_read_data_tvalid       	(m_axis_read_data_tvalid ),
  .m_axis_read_data_tready       	(m_axis_read_data_tready ),
  .m_axis_read_data_tlast        	(m_axis_read_data_tlast  ),
  .m_axis_read_data_tid          	(),
  .m_axis_read_data_tdest        	(),
  .m_axis_read_data_tuser        	(),

  .m_axi_arid    (m_axi_arid      ),
  .m_axi_araddr  (m_axi_araddr    ),
  .m_axi_arlen   (m_axi_arlen     ),
  .m_axi_arsize  (m_axi_arsize    ),
  .m_axi_arburst (m_axi_arburst   ),
  .m_axi_arlock  (m_axi_arlock    ),
  .m_axi_arcache (m_axi_arcache   ),
  .m_axi_arprot  (m_axi_arprot    ),
  .m_axi_arvalid (m_axi_arvalid   ),
  .m_axi_arready (m_axi_arready   ),
  .m_axi_rid     (m_axi_rid       ),
  .m_axi_rdata   (m_axi_rdata     ),
  .m_axi_rresp   (m_axi_rresp     ),
  .m_axi_rlast   (m_axi_rlast     ),
  .m_axi_rvalid  (m_axi_rvalid    ),
  .m_axi_rready  (m_axi_rready    ),
  .enable        (1'b1            )
);

sgdma_if_pcie_axis_wr #(
    .TLP_DATA_WIDTH   	(TLP_DATA_WIDTH   	),
    .TLP_STRB_WIDTH   	(TLP_STRB_WIDTH   	),
    .TLP_HDR_WIDTH    	(TLP_HDR_WIDTH    	),
    .TLP_SEG_COUNT    	(TLP_SEG_COUNT    	),
    .PCIE_ADDR_WIDTH  	(PCIE_ADDR_WIDTH  	),
    .TX_SEQ_NUM_COUNT 	(TX_SEQ_NUM_COUNT 	),
    .TX_SEQ_NUM_WIDTH 	(TX_SEQ_NUM_WIDTH 	)
)u_sgdma_if_pcie_axis_wr(
    .clk                  (clk),
    .rst                  (rst),
    .tx_wr_req_tlp_hdr    (tx_wr_req_tlp_hdr    ),
    .tx_wr_req_tlp_seq    (tx_wr_req_tlp_seq    ),
    .tx_wr_req_tlp_data   (tx_wr_req_tlp_data   ),
    .tx_wr_req_tlp_strb   (tx_wr_req_tlp_strb   ),
    .tx_wr_req_tlp_valid  (tx_wr_req_tlp_valid  ),
    .tx_wr_req_tlp_sop    (tx_wr_req_tlp_sop    ),
    .tx_wr_req_tlp_eop    (tx_wr_req_tlp_eop    ),
    .tx_wr_req_tlp_ready  (tx_wr_req_tlp_ready  ),
    .tx_rd_req_tlp_hdr    (tx_rd_req_tlp_hdr    ),
    .tx_rd_req_tlp_seq    (tx_rd_req_tlp_seq    ),
    .tx_rd_req_tlp_valid  (tx_rd_req_tlp_valid  ),
    .tx_rd_req_tlp_sop    (tx_rd_req_tlp_sop    ),
    .tx_rd_req_tlp_eop    (tx_rd_req_tlp_eop    ),
    .tx_rd_req_tlp_ready  (tx_rd_req_tlp_ready  ),
    .rx_cpl_tlp_data      (rx_cpl_tlp_data      ),
    .rx_cpl_tlp_hdr       (rx_cpl_tlp_hdr       ),
    .rx_cpl_tlp_error     (rx_cpl_tlp_error     ),
    .rx_cpl_tlp_valid     (rx_cpl_tlp_valid     ),
    .rx_cpl_tlp_sop       (rx_cpl_tlp_sop       ),
    .rx_cpl_tlp_eop       (rx_cpl_tlp_eop       ),
    .rx_cpl_tlp_ready     (rx_cpl_tlp_ready     ),

    .desc_wr_req_sglist_length  	(desc_wr_req_sglist_length   ),
    .desc_wr_req_sglist_address 	(desc_wr_req_sglist_address  ),
    .desc_wr_req_sglist_start   	(desc_wr_req_sglist_start    ),
    .desc_wr_req_sgdma_start    	(desc_wr_req_sgdma_start     ),

    .tx_wr_sglist_irq           	(tx_wr_sglist_irq     ),
    .requester_id               	(requester_id         ),
    .MaxPayloadSize             	(MaxPayloadSize       ),
    .Max_read_PayloadSize       	(max_read_payloadSize ),
    
    .s_axis_tlp_tdata           	(m_axis_read_data_tdata),
    .s_axis_tlp_tkeep           	(m_axis_read_data_tkeep),
    .s_axis_tlp_tvalid          	(m_axis_read_data_tvalid),
    .s_axis_tlp_tlast           	(m_axis_read_data_tlast),
    .s_axis_tlp_tready          	(m_axis_read_data_tready)
);

endmodule

`resetall