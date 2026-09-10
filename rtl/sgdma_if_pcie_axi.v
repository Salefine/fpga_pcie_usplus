/****************************************************************************
 * @file    sgdma_if_pcie.v
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

module sgdma_if_pcie_axi#(
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
    parameter TX_SEQ_NUM_WIDTH = 6,
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
    // Maximum AXI burst length to generate
    parameter AXI_MAX_BURST_LEN = 256,

    parameter AXIS_KEEP_ENABLE = 1,
    parameter AXIS_LAST_ENABLE = 0,
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

    input  wire [TLP_DATA_WIDTH-1:0]                     rx_cpl_tlp_data ,
    input  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        rx_cpl_tlp_hdr  ,
    input  wire [TLP_SEG_COUNT*4-1:0]                    rx_cpl_tlp_error,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_sop  ,
    input  wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_eop  ,
    output wire                                          rx_cpl_tlp_ready,


    input  wire [31 : 0]                 desc_wr_req_sglist_length  ,//bytes
    input  wire [PCIE_ADDR_WIDTH-1 : 0]  desc_wr_req_sglist_address ,
    input  wire                          desc_wr_req_sglist_start   ,
    input  wire [AXI_ADDR_WIDTH-1:0]     desc_wr_req_sgdma_ramaddr  , 
    input  wire [31:0]                   desc_wr_req_sgdma_length  ,//bytes
    input  wire                          desc_wr_req_sgdma_start   ,

    input  wire [31 : 0]                 desc_rd_req_sglist_length  ,//bytes
    input  wire [PCIE_ADDR_WIDTH-1 : 0]  desc_rd_req_sglist_address ,
    input  wire                          desc_rd_req_sglist_start   ,
    input  wire [AXI_ADDR_WIDTH-1:0]     desc_rd_req_sgdma_ramaddr  , 
    input wire [31:0]                    desc_rd_req_sgdma_length   ,//bytes
    input  wire                          desc_rd_req_sgdma_start    ,


    input  wire [15: 0] requester_id         ,
    input  wire [2 : 0] MaxPayloadSize       ,
    output wire         tx_wr_sglist_irq     ,
    input  wire         ext_tag_enable       ,
    input  wire [3 :0]  rcb_128b             ,
    input  wire [2 : 0] max_read_payloadSize ,
    output wire         tx_rd_sglist_irq        ,


    output wire [AXI_ID_WIDTH-1:0]       m_axi_arid   ,
    output wire [AXI_ADDR_WIDTH-1:0]     m_axi_araddr ,
    output wire [7:0]                    m_axi_arlen  ,
    output wire [2:0]                    m_axi_arsize ,
    output wire [1:0]                    m_axi_arburst,
    output wire                          m_axi_arlock ,
    output wire [3:0]                    m_axi_arcache,
    output wire [2:0]                    m_axi_arprot ,
    output wire                          m_axi_arvalid,
    input  wire                          m_axi_arready,
    input  wire [AXI_ID_WIDTH-1:0]       m_axi_rid    ,
    input  wire [AXI_DATA_WIDTH-1:0]     m_axi_rdata  ,
    input  wire [1:0]                    m_axi_rresp  ,
    input  wire                          m_axi_rlast  ,
    input  wire                          m_axi_rvalid ,
    output wire                          m_axi_rready ,    
    output wire [AXI_ID_WIDTH-1:0]       m_axi_awid   ,
    output wire [AXI_ADDR_WIDTH-1:0]     m_axi_awaddr ,
    output wire [7:0]                    m_axi_awlen  ,
    output wire [2:0]                    m_axi_awsize ,
    output wire [1:0]                    m_axi_awburst,
    output wire                          m_axi_awlock ,
    output wire [3:0]                    m_axi_awcache,
    output wire [2:0]                    m_axi_awprot ,
    output wire                          m_axi_awvalid,
    input  wire                          m_axi_awready,
    output wire [AXI_DATA_WIDTH-1:0]     m_axi_wdata  ,
    output wire [AXI_STRB_WIDTH-1:0]     m_axi_wstrb  ,
    output wire                          m_axi_wlast  ,
    output wire                          m_axi_wvalid ,
    input  wire                          m_axi_wready ,
    input  wire [AXI_ID_WIDTH-1:0]       m_axi_bid    ,
    input  wire [1:0]                    m_axi_bresp  ,
    input  wire                          m_axi_bvalid ,
    output wire                          m_axi_bready 
);

wire [TLP_HDR_WIDTH-1:0]     tx_rd0_req_tlp_hdr ,tx_rd1_req_tlp_hdr ;
wire [TX_SEQ_NUM_WIDTH-1:0]  tx_rd0_req_tlp_seq ,tx_rd1_req_tlp_seq ;
wire [0:0] tx_rd0_req_tlp_valid, tx_rd1_req_tlp_valid;
wire [0:0] tx_rd0_req_tlp_sop, tx_rd1_req_tlp_sop  ;
wire [0:0] tx_rd0_req_tlp_eop, tx_rd1_req_tlp_eop  ;
wire [0:0] tx_rd0_req_tlp_ready, tx_rd1_req_tlp_ready;

wire [TLP_HDR_WIDTH-1:0]     rx_cpl0_tlp_hdr ,rx_cpl1_tlp_hdr;
wire [TLP_DATA_WIDTH-1:0]  rx_cpl0_tlp_data,rx_cpl1_tlp_data;
wire [3:0] rx_cpl0_tlp_error,rx_cpl1_tlp_error;
wire [0:0] rx_cpl0_tlp_valid,rx_cpl1_tlp_valid;
wire [0:0] rx_cpl0_tlp_sop,rx_cpl1_tlp_sop  ;
wire [0:0] rx_cpl0_tlp_eop,rx_cpl1_tlp_eop  ;
wire [0:0] rx_cpl0_tlp_ready,rx_cpl1_tlp_ready;

sgdma_if_pcie_ctrl #(
    .TLP_DATA_WIDTH   	(TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH   	(TLP_STRB_WIDTH),
    .TLP_HDR_WIDTH    	(TLP_HDR_WIDTH),
    .TLP_PORT_COUNT    	(2),
    .TX_SEQ_NUM_WIDTH 	(TX_SEQ_NUM_WIDTH)
)sgdma_ctrl(
    .clk(clk),
    .rst(rst),

    .rx_rd_req_tlp_hdr   	({tx_rd0_req_tlp_hdr, tx_rd1_req_tlp_hdr}),
    .rx_rd_req_tlp_seq   	({tx_rd0_req_tlp_seq, tx_rd1_req_tlp_seq}),
    .rx_rd_req_tlp_valid 	({tx_rd0_req_tlp_valid, tx_rd1_req_tlp_valid}),
    .rx_rd_req_tlp_sop   	({tx_rd0_req_tlp_sop, tx_rd1_req_tlp_sop}),
    .rx_rd_req_tlp_eop   	({tx_rd0_req_tlp_eop, tx_rd1_req_tlp_eop}),
    .rx_rd_req_tlp_ready 	({tx_rd0_req_tlp_ready, tx_rd1_req_tlp_ready}),

    .tx_rd_req_tlp_hdr   	(tx_rd_req_tlp_hdr  ),
    .tx_rd_req_tlp_seq   	(tx_rd_req_tlp_seq  ),
    .tx_rd_req_tlp_valid 	(tx_rd_req_tlp_valid),
    .tx_rd_req_tlp_sop   	(tx_rd_req_tlp_sop  ),
    .tx_rd_req_tlp_eop   	(tx_rd_req_tlp_eop  ),
    .tx_rd_req_tlp_ready 	(tx_rd_req_tlp_ready),

    .rx_cpl_tlp_hdr      	(rx_cpl_tlp_hdr ),
    .rx_cpl_tlp_data     	(rx_cpl_tlp_data),
    .rx_cpl_tlp_error    	(rx_cpl_tlp_error),
    .rx_cpl_tlp_valid    	(rx_cpl_tlp_valid),
    .rx_cpl_tlp_sop      	(rx_cpl_tlp_sop),
    .rx_cpl_tlp_eop      	(rx_cpl_tlp_eop),
    .rx_cpl_tlp_ready    	(rx_cpl_tlp_ready),

    .tx_cpl_tlp_hdr      	({rx_cpl0_tlp_hdr, rx_cpl1_tlp_hdr}),
    .tx_cpl_tlp_data     	({rx_cpl0_tlp_data, rx_cpl1_tlp_data}),
    .tx_cpl_tlp_error    	({rx_cpl0_tlp_error, rx_cpl1_tlp_error}),
    .tx_cpl_tlp_valid    	({rx_cpl0_tlp_valid, rx_cpl1_tlp_valid}),
    .tx_cpl_tlp_sop      	({rx_cpl0_tlp_sop, rx_cpl1_tlp_sop}),
    .tx_cpl_tlp_eop      	({rx_cpl0_tlp_eop, rx_cpl1_tlp_eop}),
    .tx_cpl_tlp_ready    	({rx_cpl0_tlp_ready, rx_cpl1_tlp_ready})
);

sgdma_if_pcie_axi_wr #(
    .TLP_DATA_WIDTH    	(TLP_DATA_WIDTH    	),
    .TLP_STRB_WIDTH    	(TLP_STRB_WIDTH    	),
    .TLP_HDR_WIDTH     	(TLP_HDR_WIDTH     	),
    .TLP_SEG_COUNT     	(TLP_SEG_COUNT     	),
    .PCIE_ADDR_WIDTH   	(PCIE_ADDR_WIDTH   	),
    .TX_SEQ_NUM_COUNT  	(TX_SEQ_NUM_COUNT  	),
    .TX_SEQ_NUM_WIDTH  	(TX_SEQ_NUM_WIDTH  	),
    .AXI_DATA_WIDTH    	(AXI_DATA_WIDTH    	),
    .AXI_ADDR_WIDTH    	(AXI_ADDR_WIDTH    	),
    .AXI_STRB_WIDTH    	(AXI_STRB_WIDTH    	),
    .AXI_ID_WIDTH      	(AXI_ID_WIDTH      	),
    .TAG_WIDTH         	(TAG_WIDTH         	)
)sgdma_axi_wr(
    .clk                        	(clk ),
    .rst                        	(rst ),

    .tx_wr_req_tlp_data         	(tx_wr_req_tlp_data  ),
    .tx_wr_req_tlp_strb         	(tx_wr_req_tlp_strb  ),
    .tx_wr_req_tlp_hdr          	(tx_wr_req_tlp_hdr   ),
    .tx_wr_req_tlp_seq          	(tx_wr_req_tlp_seq   ),
    .tx_wr_req_tlp_valid        	(tx_wr_req_tlp_valid ),
    .tx_wr_req_tlp_sop          	(tx_wr_req_tlp_sop   ),
    .tx_wr_req_tlp_eop          	(tx_wr_req_tlp_eop   ),
    .tx_wr_req_tlp_ready        	(tx_wr_req_tlp_ready ),

    .tx_rd_req_tlp_hdr          	(tx_rd0_req_tlp_hdr   ),
    .tx_rd_req_tlp_seq          	(tx_rd0_req_tlp_seq   ),
    .tx_rd_req_tlp_valid        	(tx_rd0_req_tlp_valid ),
    .tx_rd_req_tlp_sop          	(tx_rd0_req_tlp_sop   ),
    .tx_rd_req_tlp_eop          	(tx_rd0_req_tlp_eop   ),
    .tx_rd_req_tlp_ready        	(tx_rd0_req_tlp_ready ),
    .rx_cpl_tlp_data            	(rx_cpl0_tlp_data     ),
    .rx_cpl_tlp_hdr             	(rx_cpl0_tlp_hdr      ),
    .rx_cpl_tlp_error           	(rx_cpl0_tlp_error    ),
    .rx_cpl_tlp_valid           	(rx_cpl0_tlp_valid    ),
    .rx_cpl_tlp_sop             	(rx_cpl0_tlp_sop      ),
    .rx_cpl_tlp_eop             	(rx_cpl0_tlp_eop      ),
    .rx_cpl_tlp_ready           	(rx_cpl0_tlp_ready    ),

    .desc_wr_req_sglist_length  	(desc_wr_req_sglist_length),
    .desc_wr_req_sglist_address 	(desc_wr_req_sglist_address),
    .desc_wr_req_sglist_start   	(desc_wr_req_sglist_start),
    .desc_wr_req_sgdma_start    	(desc_wr_req_sgdma_start),
    .desc_wr_req_sgdma_length   	(desc_wr_req_sgdma_length),
    .desc_wr_req_sgdma_ramaddr  	(desc_wr_req_sgdma_ramaddr),

    .tx_wr_sglist_irq           	(tx_wr_sglist_irq     ),
    .requester_id               	(requester_id         ),
    .MaxPayloadSize             	(MaxPayloadSize       ),
    .max_read_payloadSize       	(max_read_payloadSize ),

    .m_axi_arid                 	(m_axi_arid     ),
    .m_axi_araddr               	(m_axi_araddr   ),
    .m_axi_arlen                	(m_axi_arlen    ),
    .m_axi_arsize               	(m_axi_arsize   ),
    .m_axi_arburst              	(m_axi_arburst  ),
    .m_axi_arlock               	(m_axi_arlock   ),
    .m_axi_arcache              	(m_axi_arcache  ),
    .m_axi_arprot               	(m_axi_arprot   ),
    .m_axi_arvalid              	(m_axi_arvalid  ),
    .m_axi_arready              	(m_axi_arready  ),
    .m_axi_rid                  	(m_axi_rid      ),
    .m_axi_rdata                	(m_axi_rdata    ),
    .m_axi_rresp                	(m_axi_rresp    ),
    .m_axi_rlast                	(m_axi_rlast    ),
    .m_axi_rvalid               	(m_axi_rvalid   ),
    .m_axi_rready               	(m_axi_rready   )
);


sgdma_if_pcie_axi_rd #(
    .TLP_DATA_WIDTH     	(TLP_DATA_WIDTH     ),
    .TLP_HDR_WIDTH      	(TLP_HDR_WIDTH      ),
    .TLP_SEG_COUNT      	(TLP_SEG_COUNT      ),
    .TX_SEQ_NUM_WIDTH   	(TX_SEQ_NUM_WIDTH   ),
    .PCIE_ADDR_WIDTH    	(PCIE_ADDR_WIDTH    ),
    .PCIE_TAG_COUNT     	(PCIE_TAG_COUNT     ),
    .OP_TABLE_SIZE      	(OP_TABLE_SIZE      ),
    .AXI_DATA_WIDTH     	(AXI_DATA_WIDTH     ),
    .AXI_ADDR_WIDTH     	(AXI_ADDR_WIDTH     ),
    .AXI_STRB_WIDTH     	(AXI_STRB_WIDTH     ),
    .AXI_ID_WIDTH       	(AXI_ID_WIDTH       ),
    .AXI_MAX_BURST_LEN  	(AXI_MAX_BURST_LEN  )
)sgdma_axi_rd(
    .clk                          	(clk ),
    .rst                          	(rst ),

    .tx_rd_req_tlp_hdr            	(tx_rd1_req_tlp_hdr   ),
    .tx_rd_req_tlp_seq            	(tx_rd1_req_tlp_seq   ),
    .tx_rd_req_tlp_valid          	(tx_rd1_req_tlp_valid ),
    .tx_rd_req_tlp_sop            	(tx_rd1_req_tlp_sop   ),
    .tx_rd_req_tlp_eop            	(tx_rd1_req_tlp_eop   ),
    .tx_rd_req_tlp_ready          	(tx_rd1_req_tlp_ready ),
    .rx_cpl_tlp_data              	(rx_cpl1_tlp_data     ),
    .rx_cpl_tlp_hdr               	(rx_cpl1_tlp_hdr      ),
    .rx_cpl_tlp_error             	(rx_cpl1_tlp_error    ),
    .rx_cpl_tlp_valid             	(rx_cpl1_tlp_valid    ),
    .rx_cpl_tlp_sop               	(rx_cpl1_tlp_sop      ),
    .rx_cpl_tlp_eop               	(rx_cpl1_tlp_eop      ),
    .rx_cpl_tlp_ready             	(rx_cpl1_tlp_ready    ),

    .ext_tag_enable               	(ext_tag_enable       ),
    .rcb_128b                     	(rcb_128b             ),
    .requester_id                 	(requester_id         ),
    .max_read_payloadSize         	(max_read_payloadSize ),
    .tx_rd_sglist_irq             	(tx_rd_sglist_irq            ),

    .desc_rd_req_sglist_length      (desc_rd_req_sglist_length),
    .desc_rd_req_sglist_start       (desc_rd_req_sglist_start),
    .desc_rd_req_sglist_address    	(desc_rd_req_sglist_address),
    .desc_rd_req_sgdma_start     	(desc_rd_req_sgdma_start),
    .desc_rd_req_sgdma_length    	(desc_rd_req_sgdma_length),
    .desc_rd_req_sgdma_ramaddr   	(desc_rd_req_sgdma_ramaddr),

    .m_axi_awid                   	(m_axi_awid    ),
    .m_axi_awaddr                 	(m_axi_awaddr  ),
    .m_axi_awlen                  	(m_axi_awlen   ),
    .m_axi_awsize                 	(m_axi_awsize  ),
    .m_axi_awburst                	(m_axi_awburst ),
    .m_axi_awlock                 	(m_axi_awlock  ),
    .m_axi_awcache                	(m_axi_awcache ),
    .m_axi_awprot                 	(m_axi_awprot  ),
    .m_axi_awvalid                	(m_axi_awvalid ),
    .m_axi_awready                	(m_axi_awready ),
    .m_axi_wdata                  	(m_axi_wdata   ),
    .m_axi_wstrb                  	(m_axi_wstrb   ),
    .m_axi_wlast                  	(m_axi_wlast   ),
    .m_axi_wvalid                 	(m_axi_wvalid  ),
    .m_axi_wready                 	(m_axi_wready  ),
    .m_axi_bid                    	(m_axi_bid     ),
    .m_axi_bresp                  	(m_axi_bresp   ),
    .m_axi_bvalid                 	(m_axi_bvalid  ),
    .m_axi_bready                 	(m_axi_bready  )
);


endmodule //sgdma_if_pcie_axi#()
