/****************************************************************************
 * @file    tb_pcie_tlp_mux.v
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
`define CLK_PERIOD 10

module tb_pcie_tlp_mux;

// Width of PCIe AXI stream interfaces in bits
parameter AXIS_PCIE_DATA_WIDTH = 512                        ;
// PCIe AXI stream tkeep signal width (words per cycle)
parameter AXIS_PCIE_KEEP_WIDTH = (AXIS_PCIE_DATA_WIDTH/8)  ;
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

localparam PORTS = 2;

reg clk = 0;
reg rst = 1;

reg [2:0] MaxPayloadSize = 3'b010;
reg [PORTS-1:0] pause = 'b0;
wire [PORTS*TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]  sel_tlp_seq;
wire [PORTS*TLP_SEG_COUNT-1:0]                    sel_tlp_seq_valid;

reg [31:0] tx_wr_req_length0=32'h4000, tx_wr_req_length1 = 32'h4000;
reg [63:0] tx_wr_req_address0=64'h0000_0000_0000_0000, tx_wr_req_address1 = 64'h0000_0000_0000_0000;
reg tx_wr_req_start0=0, tx_wr_req_start1=0;

wire [AXIS_PCIE_DATA_WIDTH-1:0] s_axis_tlp_tdata0, s_axis_tlp_tdata1;
wire [AXIS_PCIE_KEEP_WIDTH-1:0] s_axis_tlp_tkeep0, s_axis_tlp_tkeep1;
wire s_axis_tlp_tlast0, s_axis_tlp_tlast1;
wire s_axis_tlp_tvalid0, s_axis_tlp_tvalid1;
wire s_axis_tlp_tready0, s_axis_tlp_tready1;

wire [TLP_DATA_WIDTH-1:0] tx_wr_req_tlp_data0, tx_wr_req_tlp_data1;
wire [TLP_STRB_WIDTH-1:0] tx_wr_req_tlp_strb0, tx_wr_req_tlp_strb1;
wire [TLP_HDR_WIDTH-1:0] tx_wr_req_tlp_hdr0, tx_wr_req_tlp_hdr1;
wire [TX_SEQ_NUM_WIDTH-1:0] tx_wr_req_tlp_seq0, tx_wr_req_tlp_seq1;
wire tx_wr_req_tlp_valid0, tx_wr_req_tlp_valid1;
wire tx_wr_req_tlp_sop0, tx_wr_req_tlp_sop1;
wire tx_wr_req_tlp_eop0, tx_wr_req_tlp_eop1;
wire tx_wr_req_tlp_ready0, tx_wr_req_tlp_ready1;

wire [TLP_DATA_WIDTH-1:0] tx_wr_req_tlp_data;
wire [TLP_STRB_WIDTH-1:0] tx_wr_req_tlp_strb;
wire [TLP_HDR_WIDTH-1:0] tx_wr_req_tlp_hdr;
wire [TX_SEQ_NUM_WIDTH-1:0] tx_wr_req_tlp_seq;
wire tx_wr_req_tlp_valid;
wire tx_wr_req_tlp_sop;
wire tx_wr_req_tlp_eop;
wire tx_wr_req_tlp_ready = 1'b1;

initial begin 
    #(`CLK_PERIOD * 600);
    @(posedge clk);
    rst <= 0;
    #(`CLK_PERIOD * 10);
    @(posedge clk);
    tx_wr_req_start0 <= 1;
    tx_wr_req_start1 <= 1;
    #(`CLK_PERIOD );
    @(posedge clk);
    tx_wr_req_start0 <= 0;
    tx_wr_req_start1 <= 0;
end

send_axis #(
    .STREAM_TDATA_WIDTH 	(512  ),
    .STREAM_TKEEP_WIDTH 	(64    )
)u_send_axis0(
    .m_axis_aclk    	(clk     ),
    .m_axis_aresetn 	(~rst  ),
    .st_length      	(tx_wr_req_length0),
    .st_start       	(tx_wr_req_start0 ),
    .st_end         	(          ),
    .m_axis_tdata   	(s_axis_tlp_tdata0    ),
    .m_axis_tkeep   	(s_axis_tlp_tkeep0    ),
    .m_axis_tlast   	(s_axis_tlp_tlast0    ),
    .m_axis_tvalid  	(s_axis_tlp_tvalid0   ),
    .m_axis_tready  	(s_axis_tlp_tready0   )
);

dma_if_pcie_axis_wr_v1 #(
    .TLP_DATA_WIDTH          	(TLP_DATA_WIDTH     ),
    .TLP_STRB_WIDTH          	(TLP_STRB_WIDTH     ),
    .TLP_HDR_WIDTH           	(TLP_HDR_WIDTH      ),
    .TLP_SEG_COUNT           	(TLP_SEG_COUNT      ),
    .TX_SEQ_NUM_COUNT        	(TX_SEQ_NUM_COUNT   ),
    .TX_SEQ_NUM_WIDTH        	(TX_SEQ_NUM_WIDTH   )
)tb_C2H_BlockDMA_to_tlp0(
    .clk                 	(clk),
    .rst                 	(rst),
    .tx_wr_req_tlp_data  	(tx_wr_req_tlp_data0   ),
    .tx_wr_req_tlp_strb  	(tx_wr_req_tlp_strb0   ),
    .tx_wr_req_tlp_hdr   	(tx_wr_req_tlp_hdr0    ),
    .tx_wr_req_tlp_seq   	(tx_wr_req_tlp_seq0    ),
    .tx_wr_req_tlp_valid 	(tx_wr_req_tlp_valid0  ),
    .tx_wr_req_tlp_sop   	(tx_wr_req_tlp_sop0    ),
    .tx_wr_req_tlp_eop   	(tx_wr_req_tlp_eop0    ),
    .tx_wr_req_tlp_ready 	(tx_wr_req_tlp_ready0  ),
    
    .desc_wr_req_length    	(tx_wr_req_length0     ),
    .desc_wr_req_address   	(tx_wr_req_address0    ),
    .MaxPayloadSize      	(MaxPayloadSize       ),
    .desc_wr_req_start     	(tx_wr_req_start0      ),
    .requester_id           (16'h0100),
    
    .s_axis_tlp_tdata    	(s_axis_tlp_tdata0     ),
    .s_axis_tlp_tkeep    	(s_axis_tlp_tkeep0     ),
    .s_axis_tlp_tvalid   	(s_axis_tlp_tvalid0    ),
    .s_axis_tlp_tlast    	(s_axis_tlp_tlast0     ),
    .s_axis_tlp_tready   	(s_axis_tlp_tready0    )
);

send_axis #(
    .STREAM_TDATA_WIDTH 	(512  ),
    .STREAM_TKEEP_WIDTH 	(64    )
)u_send_axis(
    .m_axis_aclk    	(clk     ),
    .m_axis_aresetn 	(~rst  ),
    .st_length      	(tx_wr_req_length1       ),
    .st_start       	(tx_wr_req_start1        ),
    .st_end         	(          ),
    .m_axis_tdata   	(s_axis_tlp_tdata1    ),
    .m_axis_tkeep   	(s_axis_tlp_tkeep1    ),
    .m_axis_tlast   	(s_axis_tlp_tlast1    ),
    .m_axis_tvalid  	(s_axis_tlp_tvalid1   ),
    .m_axis_tready  	(s_axis_tlp_tready1   )
);

dma_if_pcie_axis_wr_v1 #(
    .TLP_DATA_WIDTH          	(TLP_DATA_WIDTH     ),
    .TLP_STRB_WIDTH          	(TLP_STRB_WIDTH     ),
    .TLP_HDR_WIDTH           	(TLP_HDR_WIDTH      ),
    .TLP_SEG_COUNT           	(TLP_SEG_COUNT      ),
    .TX_SEQ_NUM_COUNT        	(TX_SEQ_NUM_COUNT   ),
    .TX_SEQ_NUM_WIDTH        	(TX_SEQ_NUM_WIDTH   )
)tb_C2H_BlockDMA_to_tlp(
    .clk                 	(clk),
    .rst                 	(rst),
    .tx_wr_req_tlp_data  	(tx_wr_req_tlp_data1   ),
    .tx_wr_req_tlp_strb  	(tx_wr_req_tlp_strb1   ),
    .tx_wr_req_tlp_hdr   	(tx_wr_req_tlp_hdr1    ),
    .tx_wr_req_tlp_seq   	(tx_wr_req_tlp_seq1    ),
    .tx_wr_req_tlp_valid 	(tx_wr_req_tlp_valid1  ),
    .tx_wr_req_tlp_sop   	(tx_wr_req_tlp_sop1    ),
    .tx_wr_req_tlp_eop   	(tx_wr_req_tlp_eop1    ),
    .tx_wr_req_tlp_ready 	(tx_wr_req_tlp_ready1  ),
    
    .desc_wr_req_length    	(tx_wr_req_length1     ),
    .desc_wr_req_address   	(tx_wr_req_address1    ),
    .MaxPayloadSize      	(MaxPayloadSize       ),
    .desc_wr_req_start     	(tx_wr_req_start1      ),
    .requester_id           (16'h0100),
    
    .s_axis_tlp_tdata    	(s_axis_tlp_tdata1     ),
    .s_axis_tlp_tkeep    	(s_axis_tlp_tkeep1     ),
    .s_axis_tlp_tvalid   	(s_axis_tlp_tvalid1    ),
    .s_axis_tlp_tlast    	(s_axis_tlp_tlast1     ),
    .s_axis_tlp_tready   	(s_axis_tlp_tready1    )
);

pcie_tlp_mux #(
    .PORTS                (PORTS),
    .TLP_DATA_WIDTH       (TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH       (TLP_STRB_WIDTH),
    .TLP_HDR_WIDTH        (TLP_HDR_WIDTH),
    .SEQ_NUM_WIDTH        (TX_SEQ_NUM_WIDTH),
    .TLP_SEG_COUNT        (TLP_SEG_COUNT),
    .ARB_TYPE_ROUND_ROBIN (1),
    .ARB_LSB_HIGH_PRIORITY(1)
)u_pcie_tlp_mux(
    .clk(clk),
    .rst(rst),    
    .in_tlp_data    ({tx_wr_req_tlp_data1 , tx_wr_req_tlp_data0}),
    .in_tlp_strb    ({tx_wr_req_tlp_strb1 , tx_wr_req_tlp_strb0}),
    .in_tlp_hdr     ({tx_wr_req_tlp_hdr1  , tx_wr_req_tlp_hdr0 }),
    .in_tlp_seq     ({tx_wr_req_tlp_seq1  , tx_wr_req_tlp_seq0 }),
    .in_tlp_bar_id  (),
    .in_tlp_func_num(),
    .in_tlp_error   (),
    .in_tlp_valid   ({tx_wr_req_tlp_valid1, tx_wr_req_tlp_valid0}),
    .in_tlp_sop     ({tx_wr_req_tlp_sop1  , tx_wr_req_tlp_sop0  }),
    .in_tlp_eop     ({tx_wr_req_tlp_eop1  , tx_wr_req_tlp_eop0  }),
    .in_tlp_ready   ({tx_wr_req_tlp_ready1, tx_wr_req_tlp_ready0}),
    /*
     * TLP output
     */
    .out_tlp_data  (tx_wr_req_tlp_data  ),
    .out_tlp_strb  (tx_wr_req_tlp_strb  ),
    .out_tlp_hdr   (tx_wr_req_tlp_hdr   ),
    .out_tlp_seq   (tx_wr_req_tlp_seq   ),
    .out_tlp_bar_id(),
    .out_tlp_func_num(),
    .out_tlp_error (),
    .out_tlp_valid (tx_wr_req_tlp_valid ),
    .out_tlp_sop   (tx_wr_req_tlp_sop   ),
    .out_tlp_eop   (tx_wr_req_tlp_eop   ),
    .out_tlp_ready (tx_wr_req_tlp_ready ),

    /*
     * Control
     */
    .pause(pause),

    /*
     * Status
     */
    .sel_tlp_seq(sel_tlp_seq),
    .sel_tlp_seq_valid(sel_tlp_seq_valid)    
);

always #(`CLK_PERIOD/2) clk = ~clk;

endmodule