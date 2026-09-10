/****************************************************************************
 * @file    sgdma_if_pcie.v
 * @brief  
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 1.1
 * @date    2026-03-18
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    zzhi          |                        |
 * |  2026-09-08   |   v1.1      |    zzhi          | sgdma_if_pcie_axis_rd desc端口更名 |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2026 zzhi
 * ***************************************************************************/

`resetall
`timescale 1ns/1ps
`default_nettype none

module sgdma_if_pcie_axis#(
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
    parameter OP_TABLE_SIZE = PCIE_TAG_COUNT
)(
    input   wire    clk ,
    input   wire    rst ,

    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]    tx_wr_req_tlp_hdr,
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0] tx_wr_req_tlp_seq,
    output  wire [TLP_DATA_WIDTH-1:0]  tx_wr_req_tlp_data,
    output  wire [TLP_STRB_WIDTH-1:0]  tx_wr_req_tlp_strb,
    output  wire [TLP_SEG_COUNT-1:0]   tx_wr_req_tlp_valid,
    output  wire [TLP_SEG_COUNT-1:0]   tx_wr_req_tlp_sop,
    output  wire [TLP_SEG_COUNT-1:0]   tx_wr_req_tlp_eop,
    input   wire                       tx_wr_req_tlp_ready,

    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_rd_req_tlp_hdr  ,
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_rd_req_tlp_seq  ,
    output  wire [TLP_SEG_COUNT-1:0]      tx_rd_req_tlp_valid,
    output  wire [TLP_SEG_COUNT-1:0]      tx_rd_req_tlp_sop  ,
    output  wire [TLP_SEG_COUNT-1:0]      tx_rd_req_tlp_eop  ,
    input   wire                          tx_rd_req_tlp_ready,    

    input  wire [TLP_DATA_WIDTH-1:0]              rx_cpl_tlp_data ,
    input  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0] rx_cpl_tlp_hdr  ,
    input  wire [TLP_SEG_COUNT*4-1:0]  rx_cpl_tlp_error,
    input  wire [TLP_SEG_COUNT-1:0]    rx_cpl_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]    rx_cpl_tlp_sop  ,
    input  wire [TLP_SEG_COUNT-1:0]    rx_cpl_tlp_eop  ,
    output wire                        rx_cpl_tlp_ready,

    input  wire [31 : 0] desc_wr_req_sglist_length  ,
    input  wire [PCIE_ADDR_WIDTH-1 : 0]  desc_wr_req_sglist_address ,
    input  wire desc_wr_req_sglist_start   ,
    input  wire desc_wr_req_sgdma_start    ,

    input  wire [31 : 0] desc_rd_req_sglist_length  ,
    input  wire [PCIE_ADDR_WIDTH-1 : 0]  desc_rd_req_sglist_address ,
    input  wire desc_rd_req_sglist_start   ,
    input  wire desc_rd_req_sgdma_start    ,


    output wire tx_wr_sglist_irq,
    output wire tx_rd_sglist_irq,
    input  wire [15: 0] requester_id        ,
    input  wire [2 : 0] MaxPayloadSize      ,
    input  wire [2 : 0] max_read_payloadSize,

    input  wire [TLP_DATA_WIDTH - 1 :0]      s_axis_tlp_tdata   ,
    input  wire [TLP_DATA_WIDTH / 8 - 1:0]   s_axis_tlp_tkeep   ,
    input  wire  s_axis_tlp_tvalid  ,
    input  wire  s_axis_tlp_tlast   ,
    output wire  s_axis_tlp_tready  ,

    output wire [TLP_DATA_WIDTH - 1 :0]      m_axis_tlp_tdata   ,
    output wire [TLP_DATA_WIDTH / 8 - 1:0]   m_axis_tlp_tkeep   ,
    output wire                              m_axis_tlp_tvalid  ,
    output wire                              m_axis_tlp_tlast   ,
    input  wire                              m_axis_tlp_tready  
);


initial begin
    if (TLP_SEG_COUNT != 1) begin
        $error("Error: TLP segment count must be 1 (instance %m)");
        $finish;
    end

    if (TLP_HDR_WIDTH != 128) begin
        $error("Error: TLP segment header width must be 128 (instance %m)");
        $finish;
    end

    if (TLP_STRB_WIDTH*32 != TLP_DATA_WIDTH) begin
        $error("Error: PCIe interface requires dword (32-bit) granularity (instance %m)");
        $finish;
    end

    if (PCIE_TAG_COUNT < 1 || PCIE_TAG_COUNT > 256) begin
        $error("Error: PCIe tag count must be between 1 and 256 (instance %m)");
        $finish;
    end
end

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



sgdma_if_pcie_axis_wr #(
    .TLP_DATA_WIDTH   	(TLP_DATA_WIDTH  ),
    .TLP_STRB_WIDTH   	(TLP_STRB_WIDTH  ),
    .TLP_HDR_WIDTH    	(TLP_HDR_WIDTH   ),
    .TLP_SEG_COUNT    	(TLP_SEG_COUNT   ),
    .PCIE_ADDR_WIDTH  	(PCIE_ADDR_WIDTH ),
    .TX_SEQ_NUM_COUNT 	(TX_SEQ_NUM_COUNT),
    .TX_SEQ_NUM_WIDTH 	(TX_SEQ_NUM_WIDTH)
)sgdma_axis_wr(
    .clk                        	(clk ),
    .rst                        	(rst ),

    .tx_wr_req_tlp_hdr          	(tx_wr_req_tlp_hdr   ),
    .tx_wr_req_tlp_seq          	(tx_wr_req_tlp_seq   ),
    .tx_wr_req_tlp_data         	(tx_wr_req_tlp_data  ),
    .tx_wr_req_tlp_strb         	(tx_wr_req_tlp_strb  ),
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

    .rx_cpl_tlp_data            	(rx_cpl0_tlp_data ),
    .rx_cpl_tlp_hdr             	(rx_cpl0_tlp_hdr  ),
    .rx_cpl_tlp_error           	(rx_cpl0_tlp_error),
    .rx_cpl_tlp_valid           	(rx_cpl0_tlp_valid),
    .rx_cpl_tlp_sop             	(rx_cpl0_tlp_sop  ),
    .rx_cpl_tlp_eop             	(rx_cpl0_tlp_eop  ),
    .rx_cpl_tlp_ready           	(rx_cpl0_tlp_ready),

    .desc_wr_req_sglist_length  	(desc_wr_req_sglist_length   ),
    .desc_wr_req_sglist_address 	(desc_wr_req_sglist_address  ),
    .desc_wr_req_sglist_start   	(desc_wr_req_sglist_start    ),
    .desc_wr_req_sgdma_start    	(desc_wr_req_sgdma_start     ),

    .tx_wr_sglist_irq           	(tx_wr_sglist_irq     ),
    .requester_id               	(requester_id         ),
    .MaxPayloadSize             	(MaxPayloadSize       ),
    .Max_read_PayloadSize       	(max_read_payloadSize ),

    .s_axis_tlp_tdata           	(s_axis_tlp_tdata ),
    .s_axis_tlp_tkeep           	(s_axis_tlp_tkeep ),
    .s_axis_tlp_tvalid          	(s_axis_tlp_tvalid),
    .s_axis_tlp_tlast           	(s_axis_tlp_tlast ),
    .s_axis_tlp_tready          	(s_axis_tlp_tready)
);


sgdma_if_pcie_axis_rd #(
    .TLP_DATA_WIDTH   	(TLP_DATA_WIDTH    ),
    .TLP_HDR_WIDTH    	(TLP_HDR_WIDTH     ),
    .TLP_SEG_COUNT    	(TLP_SEG_COUNT     ),
    .TX_SEQ_NUM_WIDTH 	(TX_SEQ_NUM_WIDTH  ),
    .PCIE_ADDR_WIDTH  	(PCIE_ADDR_WIDTH   ),
    .PCIE_TAG_COUNT   	(PCIE_TAG_COUNT    ),
    .OP_TABLE_SIZE    	(PCIE_TAG_COUNT    )
)sgdma_axis_rd(
    .clk                    	(clk  ),
    .rst                    	(rst  ),

    .tx_rd_req_tlp_hdr      	(tx_rd1_req_tlp_hdr   ),
    .tx_rd_req_tlp_seq      	(tx_rd1_req_tlp_seq   ),
    .tx_rd_req_tlp_valid    	(tx_rd1_req_tlp_valid ),
    .tx_rd_req_tlp_sop      	(tx_rd1_req_tlp_sop   ),
    .tx_rd_req_tlp_eop      	(tx_rd1_req_tlp_eop   ),
    .tx_rd_req_tlp_ready    	(tx_rd1_req_tlp_ready ),

    .rx_cpl_tlp_data        	(rx_cpl1_tlp_data  ),
    .rx_cpl_tlp_hdr         	(rx_cpl1_tlp_hdr   ),
    .rx_cpl_tlp_error       	(rx_cpl1_tlp_error ),
    .rx_cpl_tlp_valid       	(rx_cpl1_tlp_valid ),
    .rx_cpl_tlp_sop         	(rx_cpl1_tlp_sop   ),
    .rx_cpl_tlp_eop         	(rx_cpl1_tlp_eop   ),
    .rx_cpl_tlp_ready       	(rx_cpl1_tlp_ready ),

    .requester_id           	(requester_id            ),
    .max_read_payloadSize   	(max_read_payloadSize    ),
    .tx_rd_req_irq          	(tx_rd_sglist_irq),

    .desc_rd_req_sglist_length  (desc_rd_req_sglist_length   ),
    .desc_rd_req_sglist_address (desc_rd_req_sglist_address  ),
    .desc_rd_req_sglist_start   (desc_rd_req_sglist_start    ),
    .desc_rd_req_sgdma_start    (desc_rd_req_sgdma_start     ),

    .m_axis_tlp_tdata       	(m_axis_tlp_tdata        ),
    .m_axis_tlp_tkeep       	(m_axis_tlp_tkeep        ),
    .m_axis_tlp_tvalid      	(m_axis_tlp_tvalid       ),
    .m_axis_tlp_tlast       	(m_axis_tlp_tlast        ),
    .m_axis_tlp_tready      	(m_axis_tlp_tready       )
);

endmodule
`resetall