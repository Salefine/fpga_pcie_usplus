/****************************************************************************
 * @file    tb_c2h_axis_to_tlp.v
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

`define CLOCK_PERIOD 4

module tb_dma_if_pcie_axis_wr();
// Width of PCIe AXI stream interfaces in bits
parameter AXIS_PCIE_DATA_WIDTH = 512                        ;
// PCIe AXI stream tkeep signal width (words per cycle)
parameter AXIS_PCIE_KEEP_WIDTH = (AXIS_PCIE_DATA_WIDTH/32)  ;
// PCIe AXI stream RQ tuser signal width
parameter AXIS_PCIE_RQ_USER_WIDTH = AXIS_PCIE_DATA_WIDTH < 512 ? 60 : 137;
// RQ interface TLP straddling
parameter RQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512;
// RQ sequence number width
parameter RQ_SEQ_NUM_WIDTH = AXIS_PCIE_RQ_USER_WIDTH == 60 ? 4 : 6;
// TLP data width
parameter TLP_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH;
// TLP strobe width
parameter TLP_STRB_WIDTH = TLP_DATA_WIDTH/32;
// TLP header width
parameter TLP_HDR_WIDTH = 128;
// TLP segment count
parameter TLP_SEG_COUNT = 1;
// TX sequence number count
parameter TX_SEQ_NUM_COUNT = AXIS_PCIE_DATA_WIDTH < 512 ? 1 : 2;
// TX sequence number width
parameter TX_SEQ_NUM_WIDTH = RQ_SEQ_NUM_WIDTH-1;

// output declaration of module C2H_BlockDMA_to_tlp
reg clk = 1;
reg rst = 1;
reg tx_wr_req_tlp_ready = 1;
reg [2:0]MaxPayloadSize      = 3'b010;

reg [31:0] tx_wr_req_length = 0;
reg [63:0] tx_wr_req_address= 0;
reg        tx_wr_req_start  = 0;

wire [AXIS_PCIE_DATA_WIDTH - 1 : 0]s_axis_tlp_tdata ;
wire [AXIS_PCIE_DATA_WIDTH/8 - 1 : 0]s_axis_tlp_tkeep ;
wire                               s_axis_tlp_tvalid;
wire                               s_axis_tlp_tlast ;

wire [TLP_DATA_WIDTH-1:0] tx_wr_req_tlp_data;
wire [TLP_STRB_WIDTH-1:0] tx_wr_req_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0] tx_wr_req_tlp_hdr;
wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0] tx_wr_req_tlp_seq;
wire [TLP_SEG_COUNT-1:0] tx_wr_req_tlp_valid;
wire [TLP_SEG_COUNT-1:0] tx_wr_req_tlp_sop;
wire [TLP_SEG_COUNT-1:0] tx_wr_req_tlp_eop;
wire s_axis_tlp_tready;

initial begin
    #(`CLOCK_PERIOD * 100);
    rst <= 0;
    #(`CLOCK_PERIOD * 100);
    @(posedge clk);
    tx_wr_req_address <= 64'h00000000_fcf00000;
    tx_wr_req_length  <= 32'h400000;
    tx_wr_req_start   <= 1;
    #(`CLOCK_PERIOD)
    @(posedge clk);
    tx_wr_req_start   <= 0;
    wait(tb_C2H_BlockDMA_to_tlp.tx_wr_req_tlp_sop);
    @(posedge clk);
    tx_wr_req_tlp_ready<=0;
    #(`CLOCK_PERIOD*20);
    tx_wr_req_tlp_ready<=1;
    
    wait(tb_C2H_BlockDMA_to_tlp.op_cycle_next == tb_C2H_BlockDMA_to_tlp.cycle_reg);
    #(`CLOCK_PERIOD * 100);
    @(posedge clk);
    tx_wr_req_address <= 64'h00000000_fcf00000;
    tx_wr_req_length  <= 32'h4000;
    tx_wr_req_start   <= 1;    
    wait(tb_C2H_BlockDMA_to_tlp.tx_wr_req_tlp_sop);
    @(posedge clk);
    tx_wr_req_tlp_ready<=0;
    #(`CLOCK_PERIOD*20);
    tx_wr_req_tlp_ready<=1;
    repeat(20)begin
        #(`CLOCK_PERIOD*1);
        tx_wr_req_tlp_ready<=0;
        #(`CLOCK_PERIOD * 4);
        tx_wr_req_tlp_ready<=1;
    end
    #(`CLOCK_PERIOD)
    @(posedge clk);
    tx_wr_req_start   <= 0;   

    #(`CLOCK_PERIOD * 500);
    @(posedge clk);
    tx_wr_req_address <= 64'h00000000_fcf00000;
    tx_wr_req_length  <= 32'd1;
    tx_wr_req_start   <= 1;    
    #(`CLOCK_PERIOD)
    @(posedge clk);
    tx_wr_req_start   <= 0;   

    #(`CLOCK_PERIOD * 100);
    @(posedge clk);
    tx_wr_req_address <= 64'h00000000_fcf00000;
    tx_wr_req_length  <= 32'h800;
    tx_wr_req_start   <= 1;    
    #(`CLOCK_PERIOD)
    @(posedge clk);
    tx_wr_req_start   <= 0; 
end

send_axis #(
    .STREAM_TDATA_WIDTH 	(512  ),
    .STREAM_TKEEP_WIDTH 	(64    )
)u_send_axis(
    .m_axis_aclk    	(clk     ),
    .m_axis_aresetn 	(~rst  ),
    .st_length      	(tx_wr_req_length       ),
    .st_start       	(tx_wr_req_start        ),
    .st_end         	(          ),
    .m_axis_tdata   	(s_axis_tlp_tdata    ),
    .m_axis_tkeep   	(s_axis_tlp_tkeep    ),
    .m_axis_tlast   	(s_axis_tlp_tlast    ),
    .m_axis_tvalid  	(s_axis_tlp_tvalid   ),
    .m_axis_tready  	(s_axis_tlp_tready   )
);

dma_if_pcie_axis_wr_v1 #(
    .TLP_DATA_WIDTH          	(TLP_DATA_WIDTH         ),
    .TLP_STRB_WIDTH          	(TLP_STRB_WIDTH     ),
    .TLP_HDR_WIDTH           	(TLP_HDR_WIDTH      ),
    .TLP_SEG_COUNT           	(TLP_SEG_COUNT      ),
    .TX_SEQ_NUM_COUNT        	(TX_SEQ_NUM_COUNT   ),
    .TX_SEQ_NUM_WIDTH        	(TX_SEQ_NUM_WIDTH   )
)tb_C2H_BlockDMA_to_tlp(
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
    
    .desc_wr_req_length    	(tx_wr_req_length     ),
    .desc_wr_req_address   	(tx_wr_req_address    ),
    .MaxPayloadSize      	(MaxPayloadSize       ),
    .desc_wr_req_start     	(tx_wr_req_start      ),
    .requester_id           (16'h0100),
    
    .s_axis_tlp_tdata    	(s_axis_tlp_tdata     ),
    .s_axis_tlp_tkeep    	(s_axis_tlp_tkeep     ),
    .s_axis_tlp_tvalid   	(s_axis_tlp_tvalid    ),
    .s_axis_tlp_tlast    	(s_axis_tlp_tlast     ),
    .s_axis_tlp_tready   	(s_axis_tlp_tready    )
);
//dma_if_pcie_axis_wr #(
//    .TLP_DATA_WIDTH          	(TLP_DATA_WIDTH         ),
//    .TLP_STRB_WIDTH          	(TLP_STRB_WIDTH     ),
//    .TLP_HDR_WIDTH           	(TLP_HDR_WIDTH      ),
//    .TLP_SEG_COUNT           	(TLP_SEG_COUNT      ),
//    .TX_SEQ_NUM_COUNT        	(TX_SEQ_NUM_COUNT   ),
//    .TX_SEQ_NUM_WIDTH        	(TX_SEQ_NUM_WIDTH   )
//)tb_C2H_BlockDMA_to_tlp(
//    .clk                 	(clk                  ),
//    .rst                 	(rst                  ),
//    .tx_wr_req_tlp_data  	(tx_wr_req_tlp_data   ),
//    .tx_wr_req_tlp_strb  	(tx_wr_req_tlp_strb   ),
//    .tx_wr_req_tlp_hdr   	(tx_wr_req_tlp_hdr    ),
//    .tx_wr_req_tlp_seq   	(tx_wr_req_tlp_seq    ),
//    .tx_wr_req_tlp_valid 	(tx_wr_req_tlp_valid  ),
//    .tx_wr_req_tlp_sop   	(tx_wr_req_tlp_sop    ),
//    .tx_wr_req_tlp_eop   	(tx_wr_req_tlp_eop    ),
//    .tx_wr_req_tlp_ready 	(tx_wr_req_tlp_ready  ),
    
//    .desc_wr_req_length    	(tx_wr_req_length     ),
//    .desc_wr_req_address   	(tx_wr_req_address    ),
//    .MaxPayloadSize      	(MaxPayloadSize       ),
//    .desc_wr_req_start     	(tx_wr_req_start      ),
//    .requester_id           (16'h0100),
    
//    .s_axis_tlp_tdata    	(s_axis_tlp_tdata     ),
//    .s_axis_tlp_tkeep    	(s_axis_tlp_tkeep     ),
//    .s_axis_tlp_tvalid   	(s_axis_tlp_tvalid    ),
//    .s_axis_tlp_tlast    	(s_axis_tlp_tlast     ),
//    .s_axis_tlp_tready   	(s_axis_tlp_tready    )
//);

always #(`CLOCK_PERIOD / 2) clk = ~clk;
endmodule
