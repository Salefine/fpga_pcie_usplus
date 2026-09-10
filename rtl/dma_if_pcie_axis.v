/****************************************************************************
 * @file    dma_if_pcie_axis.v
 * @brief  
 * @author  weslie (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2026-03-18
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    weslie        |                        |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2026 welie
 * ***************************************************************************/

`timescale 1ns/1ps

module dma_if_pcie_axis#(
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
    parameter PCIE_TAG_COUNT = 32    
) (
    input   wire    clk ,
    input   wire    rst ,
    /*
     * TLP input (write request from DMA)
     * such as :0x60000020000001_7_f_0000000080000000
     */
    output  wire [TLP_DATA_WIDTH-1:0]                     tx_wr_req_tlp_data,
    output  wire [TLP_STRB_WIDTH-1:0]                     tx_wr_req_tlp_strb,
    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_wr_req_tlp_hdr,
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_wr_req_tlp_seq,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_valid,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_sop,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_eop,
    input   wire                                          tx_wr_req_tlp_ready,
    /*
     * AXI4-Stream input
     */
    input  wire [31 : 0]                 desc_wr_req_length  ,//bytes
    input  wire [PCIE_ADDR_WIDTH-1 : 0]  desc_wr_req_address ,
    input  wire                          desc_wr_req_start   ,

    /*
     * Configuration
     */
    input  wire [15: 0]    requester_id        ,
    input  wire [2 : 0]    MaxPayloadSize      ,


    input  wire [TLP_DATA_WIDTH - 1 :0]      s_axis_tlp_tdata   ,
    input  wire [TLP_DATA_WIDTH / 8 - 1:0]   s_axis_tlp_tkeep   ,
    input  wire                              s_axis_tlp_tvalid  ,
    input  wire                              s_axis_tlp_tlast   ,
    output wire                              s_axis_tlp_tready  ,

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
    input  wire [2 : 0]          Max_read_PayloadSize     ,
    output wire tx_rd_req_irq,

    /*
     * AXI4-Stream input
     */
    input  wire [31 : 0]         desc_tx_rd_req_length         ,//bytes
    input  wire [63 : 0]         desc_tx_rd_req_address        ,
    input  wire                  desc_tx_rd_req_start          ,
    
    
    /*
     * AXI4-Stream output
     */
    output wire [TLP_DATA_WIDTH - 1 :0]      m_axis_tlp_tdata   ,
    output wire [TLP_DATA_WIDTH / 8 - 1:0]   m_axis_tlp_tkeep   ,
    output wire                              m_axis_tlp_tvalid  ,
    output wire                              m_axis_tlp_tlast   ,
    input  wire                              m_axis_tlp_tready      
);



dma_if_pcie_axis_wr_v1 #(
    .TLP_DATA_WIDTH   	(TLP_DATA_WIDTH  ),
    .TLP_STRB_WIDTH   	(TLP_STRB_WIDTH  ),
    .TLP_HDR_WIDTH    	(TLP_HDR_WIDTH   ),
    .TLP_SEG_COUNT    	(TLP_SEG_COUNT   ),
    .PCIE_ADDR_WIDTH  	(PCIE_ADDR_WIDTH ),
    .TX_SEQ_NUM_COUNT 	(TX_SEQ_NUM_COUNT),
    .TX_SEQ_NUM_WIDTH 	(TX_SEQ_NUM_WIDTH)
)dma_if_wr(
    .clk                 	(clk                  ),
    .rst                 	(rst                  ),
    .tx_wr_req_tlp_data  	(tx_wr_req_tlp_data   ),
    .tx_wr_req_tlp_strb  	(tx_wr_req_tlp_strb   ),
    .tx_wr_req_tlp_hdr   	(tx_wr_req_tlp_hdr    ),
    .tx_wr_req_tlp_seq   	(tx_wr_req_tlp_seq    ),
    .tx_wr_req_tlp_valid 	(tx_wr_req_tlp_valid  ),
    .tx_wr_req_tlp_sop   	(tx_wr_req_tlp_sop    ),
    .tx_wr_req_tlp_eop   	(tx_wr_req_tlp_eop    ),
    .tx_wr_req_tlp_ready 	(tx_wr_req_tlp_ready  ),
    .desc_wr_req_length  	(desc_wr_req_length   ),
    .desc_wr_req_address 	(desc_wr_req_address  ),
    .desc_wr_req_start   	(desc_wr_req_start    ),
    .requester_id        	(requester_id         ),
    .MaxPayloadSize      	(MaxPayloadSize       ),
    .s_axis_tlp_tdata    	(s_axis_tlp_tdata     ),
    .s_axis_tlp_tkeep    	(s_axis_tlp_tkeep     ),
    .s_axis_tlp_tvalid   	(s_axis_tlp_tvalid    ),
    .s_axis_tlp_tlast    	(s_axis_tlp_tlast     ),
    .s_axis_tlp_tready   	(s_axis_tlp_tready    )
);



dma_if_pcie_axis_rd_v1 #(
    .TLP_DATA_WIDTH     	(TLP_DATA_WIDTH     ),
    .TLP_HDR_WIDTH      	(TLP_HDR_WIDTH      ),
    .TLP_SEG_COUNT      	(TLP_SEG_COUNT      ),
    .TX_SEQ_NUM_WIDTH   	(TX_SEQ_NUM_WIDTH   ),
    .PCIE_TAG_COUNT     	(PCIE_TAG_COUNT     )
)dma_if_rd(
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
    .tx_rd_req_irq              (tx_rd_req_irq           ),
    .rcb_128b               	(rcb_128b                ),
    .requester_id           	(requester_id            ),
    .Max_read_PayloadSize   	(Max_read_PayloadSize    ),
    .desc_tx_rd_req_length  	(desc_tx_rd_req_length   ),
    .desc_tx_rd_req_address 	(desc_tx_rd_req_address  ),
    .desc_tx_rd_req_start   	(desc_tx_rd_req_start    ),
    .m_axis_tlp_tdata       	(m_axis_tlp_tdata        ),
    .m_axis_tlp_tkeep       	(m_axis_tlp_tkeep        ),
    .m_axis_tlp_tvalid      	(m_axis_tlp_tvalid       ),
    .m_axis_tlp_tlast       	(m_axis_tlp_tlast        ),
    .m_axis_tlp_tready      	(m_axis_tlp_tready       )
);


endmodule