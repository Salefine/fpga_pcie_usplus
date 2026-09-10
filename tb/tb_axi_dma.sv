/****************************************************************************
 * @file    tb_axi_dma.sv
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

`timescale 1ns/1ps
`define CLOCK_PERIOD 10
//`define BLOCK_DMA
module tb_axi_dma();

localparam AXI_ID_WIDTH = 8;
localparam AXI_ADDR_WIDTH = 32;
localparam AXI_DATA_WIDTH = 512;
localparam AXI_MAX_BURST_LEN = 64;
localparam AXIS_KEEP_ENABLE = 1;
localparam AXIS_LAST_ENABLE =1;
localparam AXIS_ID_ENABLE = 0;
localparam AXIS_ID_WIDTH = 8;
localparam AXIS_DEST_ENABLE = 0;
localparam AXIS_DEST_WIDTH = 8;
localparam AXIS_USER_ENABLE = 0;
localparam AXIS_USER_WIDTH = 8;
localparam LEN_WIDTH = 32;
localparam TAG_WIDTH = 8;

localparam AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
localparam AXIS_DATA_WIDTH = AXI_DATA_WIDTH;
localparam AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8;

reg clk = 0;
reg rst = 1;

//write desc
reg [AXI_ADDR_WIDTH-1:0]s_axis_write_desc_addr = 0;
reg [LEN_WIDTH-1:0]s_axis_write_desc_len = 0;
reg s_axis_write_desc_valid = 0;
reg [TAG_WIDTH-1:0]s_axis_write_desc_tag = 0;
wire s_axis_write_desc_ready;

//write data
wire [AXI_DATA_WIDTH-1:0] s_axis_write_data_tdata;
wire [AXI_STRB_WIDTH-1:0] s_axis_write_data_tkeep;
wire s_axis_write_data_tlast;
wire s_axis_write_data_tvalid;
wire s_axis_write_data_tready;

//read desc
reg [AXI_ADDR_WIDTH-1:0]s_axis_read_desc_addr ;         
reg [LEN_WIDTH-1:0]s_axis_read_desc_len  ;         
reg [TAG_WIDTH-1:0]s_axis_read_desc_tag  ;         
reg [AXI_ID_WIDTH-1:0]s_axis_read_desc_id   ;         
reg [AXIS_DEST_WIDTH-1:0]s_axis_read_desc_dest ;         
reg [AXIS_USER_WIDTH-1:0]s_axis_read_desc_user ;         
reg   s_axis_read_desc_valid;         
wire  s_axis_read_desc_ready;         

//read data
reg  m_axis_read_data_tready   ;
wire [AXI_DATA_WIDTH-1:0]m_axis_read_data_tdata    ;
wire [AXIS_KEEP_WIDTH-1:0]m_axis_read_data_tkeep    ;
wire [0:0]m_axis_read_data_tvalid   ;
wire [0:0]m_axis_read_data_tlast    ;
wire [AXI_ID_WIDTH-1:0]m_axis_read_data_tid      ;
wire [AXIS_DEST_WIDTH-1:0]m_axis_read_data_tdest    ;
wire [AXIS_USER_WIDTH-1:0]m_axis_read_data_tuser    ;

//axi full
wire [AXI_ID_WIDTH-1:0]     m_axi_awid;
wire [AXI_ADDR_WIDTH-1:0]   m_axi_awaddr;
wire [7:0]                  m_axi_awlen;
wire [2:0]                  m_axi_awsize;
wire [1:0]                  m_axi_awburst;
wire                        m_axi_awlock;
wire [3:0]                  m_axi_awcache;
wire [2:0]                  m_axi_awprot;
wire                        m_axi_awvalid;
wire [AXI_DATA_WIDTH-1:0]   m_axi_wdata;
wire [AXI_STRB_WIDTH-1:0]   m_axi_wstrb;
wire                        m_axi_wlast;
wire                        m_axi_wvalid;
wire                        m_axi_bready;
wire [AXI_ID_WIDTH-1:0]     m_axi_arid;
wire [AXI_ADDR_WIDTH-1:0]   m_axi_araddr;
wire [7:0]                  m_axi_arlen;
wire [2:0]                  m_axi_arsize;
wire [1:0]                  m_axi_arburst;
wire                        m_axi_arlock;
wire [3:0]                  m_axi_arcache;
wire [2:0]                  m_axi_arprot;
wire                        m_axi_arvalid;
wire                        m_axi_rready;

wire read_enable = 1;
wire write_enable = 1;

initial begin

end

send_axis #(
    .STREAM_TDATA_WIDTH 	(AXI_DATA_WIDTH    ),
    .STREAM_TKEEP_WIDTH 	(AXI_STRB_WIDTH    ),
    .FIFO_DEEPTH_WIDTH  	(4    )
)u_send_axis(
    .m_axis_aclk    	(clk   ),
    .m_axis_aresetn 	(~rst  ),
    .st_length      	(),
    .st_start       	(),
    .st_end         	(),
    .m_axis_tdata   	(s_axis_write_data_tdata    ),
    .m_axis_tkeep   	(s_axis_write_data_tkeep    ),
    .m_axis_tlast   	(s_axis_write_data_tlast    ),
    .m_axis_tvalid  	(s_axis_write_data_tvalid   ),
    .m_axis_tready  	(s_axis_write_data_tready   )
);


axi_dma #(
    .AXI_DATA_WIDTH    	(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH    	(AXI_ADDR_WIDTH),
    .AXI_STRB_WIDTH    	(AXI_STRB_WIDTH),
    .AXI_ID_WIDTH      	(AXI_ID_WIDTH),
    .AXI_MAX_BURST_LEN 	(AXI_MAX_BURST_LEN),
    .AXIS_DATA_WIDTH   	(AXIS_DATA_WIDTH),
    .AXIS_KEEP_ENABLE  	(AXIS_KEEP_ENABLE),
    .AXIS_KEEP_WIDTH   	(AXIS_KEEP_WIDTH),
    .AXIS_LAST_ENABLE  	(AXIS_LAST_ENABLE),
    .AXIS_ID_ENABLE    	(AXIS_ID_ENABLE),
    .AXIS_ID_WIDTH     	(AXIS_ID_WIDTH),
    .AXIS_DEST_ENABLE  	(AXIS_DEST_ENABLE),
    .AXIS_DEST_WIDTH   	(AXIS_DEST_WIDTH),
    .AXIS_USER_ENABLE  	(AXIS_USER_ENABLE),
    .AXIS_USER_WIDTH   	(AXIS_USER_WIDTH),
    .LEN_WIDTH         	(LEN_WIDTH),
    .TAG_WIDTH         	(TAG_WIDTH),
    .ENABLE_SG         	(0               ),
    .ENABLE_UNALIGNED  	(0               )
)u_axi_dma(
    .clk                            	(clk                             ),
    .rst                            	(rst                             ),

    .s_axis_read_desc_addr          	(s_axis_read_desc_addr           ),
    .s_axis_read_desc_len           	(s_axis_read_desc_len            ),
    .s_axis_read_desc_tag           	(s_axis_read_desc_tag            ),
    .s_axis_read_desc_id            	(s_axis_read_desc_id             ),
    .s_axis_read_desc_dest          	(s_axis_read_desc_dest           ),
    .s_axis_read_desc_user          	(s_axis_read_desc_user           ),
    .s_axis_read_desc_valid         	(s_axis_read_desc_valid          ),
    .s_axis_read_desc_ready         	(s_axis_read_desc_ready          ),

    .m_axis_read_desc_status_tag    	(m_axis_read_desc_status_tag     ),
    .m_axis_read_desc_status_error  	(m_axis_read_desc_status_error   ),
    .m_axis_read_desc_status_valid  	(m_axis_read_desc_status_valid   ),

    .m_axis_read_data_tdata         	(m_axis_read_data_tdata          ),
    .m_axis_read_data_tkeep         	(m_axis_read_data_tkeep          ),
    .m_axis_read_data_tvalid        	(m_axis_read_data_tvalid         ),
    .m_axis_read_data_tready        	(m_axis_read_data_tready         ),
    .m_axis_read_data_tlast         	(m_axis_read_data_tlast          ),
    .m_axis_read_data_tid           	(m_axis_read_data_tid            ),
    .m_axis_read_data_tdest         	(m_axis_read_data_tdest          ),
    .m_axis_read_data_tuser         	(m_axis_read_data_tuser          ),

    .s_axis_write_desc_addr         	(s_axis_write_desc_addr          ),
    .s_axis_write_desc_len          	(s_axis_write_desc_len           ),
    .s_axis_write_desc_tag          	(s_axis_write_desc_tag           ),
    .s_axis_write_desc_valid        	(s_axis_write_desc_valid         ),
    .s_axis_write_desc_ready        	(s_axis_write_desc_ready         ),

    .m_axis_write_desc_status_len   	(m_axis_write_desc_status_len    ),
    .m_axis_write_desc_status_tag   	(m_axis_write_desc_status_tag    ),
    .m_axis_write_desc_status_id    	(m_axis_write_desc_status_id     ),
    .m_axis_write_desc_status_dest  	(m_axis_write_desc_status_dest   ),
    .m_axis_write_desc_status_user  	(m_axis_write_desc_status_user   ),
    .m_axis_write_desc_status_error 	(m_axis_write_desc_status_error  ),
    .m_axis_write_desc_status_valid 	(m_axis_write_desc_status_valid  ),

    .s_axis_write_data_tdata        	(s_axis_write_data_tdata         ),
    .s_axis_write_data_tkeep        	(s_axis_write_data_tkeep         ),
    .s_axis_write_data_tvalid       	(s_axis_write_data_tvalid        ),
    .s_axis_write_data_tready       	(s_axis_write_data_tready        ),
    .s_axis_write_data_tlast        	(s_axis_write_data_tlast         ),
    .s_axis_write_data_tid          	(s_axis_write_data_tid           ),
    .s_axis_write_data_tdest        	(s_axis_write_data_tdest         ),
    .s_axis_write_data_tuser        	(s_axis_write_data_tuser         ),

    .m_axi_awid                     	(m_axi_awid                      ),
    .m_axi_awaddr                   	(m_axi_awaddr                    ),
    .m_axi_awlen                    	(m_axi_awlen                     ),
    .m_axi_awsize                   	(m_axi_awsize                    ),
    .m_axi_awburst                  	(m_axi_awburst                   ),
    .m_axi_awlock                   	(m_axi_awlock                    ),
    .m_axi_awcache                  	(m_axi_awcache                   ),
    .m_axi_awprot                   	(m_axi_awprot                    ),
    .m_axi_awvalid                  	(m_axi_awvalid                   ),
    .m_axi_awready                  	(m_axi_awready                   ),
    .m_axi_wdata                    	(m_axi_wdata                     ),
    .m_axi_wstrb                    	(m_axi_wstrb                     ),
    .m_axi_wlast                    	(m_axi_wlast                     ),
    .m_axi_wvalid                   	(m_axi_wvalid                    ),
    .m_axi_wready                   	(m_axi_wready                    ),
    .m_axi_bid                      	(m_axi_bid                       ),
    .m_axi_bresp                    	(m_axi_bresp                     ),
    .m_axi_bvalid                   	(m_axi_bvalid                    ),
    .m_axi_bready                   	(m_axi_bready                    ),
    .m_axi_arid                     	(m_axi_arid                      ),
    .m_axi_araddr                   	(m_axi_araddr                    ),
    .m_axi_arlen                    	(m_axi_arlen                     ),
    .m_axi_arsize                   	(m_axi_arsize                    ),
    .m_axi_arburst                  	(m_axi_arburst                   ),
    .m_axi_arlock                   	(m_axi_arlock                    ),
    .m_axi_arcache                  	(m_axi_arcache                   ),
    .m_axi_arprot                   	(m_axi_arprot                    ),
    .m_axi_arvalid                  	(m_axi_arvalid                   ),
    .m_axi_arready                  	(m_axi_arready                   ),
    .m_axi_rid                      	(m_axi_rid                       ),
    .m_axi_rdata                    	(m_axi_rdata                     ),
    .m_axi_rresp                    	(m_axi_rresp                     ),
    .m_axi_rlast                    	(m_axi_rlast                     ),
    .m_axi_rvalid                   	(m_axi_rvalid                    ),
    .m_axi_rready                   	(m_axi_rready                    ),

    .read_enable                    	(read_enable                     ),
    .write_enable                   	(write_enable                    )
);



axi_ram #(
    .DATA_WIDTH      	(AXI_DATA_WIDTH),
    .ADDR_WIDTH      	(AXI_ADDR_WIDTH),
    .STRB_WIDTH      	(AXI_STRB_WIDTH),
    .ID_WIDTH        	(AXI_ID_WIDTH),
    .PIPELINE_OUTPUT 	(0)
)u_axi_ram(
    .clk           	(clk            ),
    .rst           	(rst            ),
    .s_axi_awid    	(m_axi_awid     ),
    .s_axi_awaddr  	(m_axi_awaddr   ),
    .s_axi_awlen   	(m_axi_awlen    ),
    .s_axi_awsize  	(m_axi_awsize   ),
    .s_axi_awburst 	(m_axi_awburst  ),
    .s_axi_awlock  	(m_axi_awlock   ),
    .s_axi_awcache 	(m_axi_awcache  ),
    .s_axi_awprot  	(m_axi_awprot   ),
    .s_axi_awvalid 	(m_axi_awvalid  ),
    .s_axi_awready 	(m_axi_awready  ),
    .s_axi_wdata   	(m_axi_wdata    ),
    .s_axi_wstrb   	(m_axi_wstrb    ),
    .s_axi_wlast   	(m_axi_wlast    ),
    .s_axi_wvalid  	(m_axi_wvalid   ),
    .s_axi_wready  	(m_axi_wready   ),
    .s_axi_bid     	(m_axi_bid      ),
    .s_axi_bresp   	(m_axi_bresp    ),
    .s_axi_bvalid  	(m_axi_bvalid   ),
    .s_axi_bready  	(m_axi_bready   ),
    .s_axi_arid    	(m_axi_arid     ),
    .s_axi_araddr  	(m_axi_araddr   ),
    .s_axi_arlen   	(m_axi_arlen    ),
    .s_axi_arsize  	(m_axi_arsize   ),
    .s_axi_arburst 	(m_axi_arburst  ),
    .s_axi_arlock  	(m_axi_arlock   ),
    .s_axi_arcache 	(m_axi_arcache  ),
    .s_axi_arprot  	(m_axi_arprot   ),
    .s_axi_arvalid 	(m_axi_arvalid  ),
    .s_axi_arready 	(m_axi_arready  ),
    .s_axi_rid     	(m_axi_rid      ),
    .s_axi_rdata   	(m_axi_rdata    ),
    .s_axi_rresp   	(m_axi_rresp    ),
    .s_axi_rlast   	(m_axi_rlast    ),
    .s_axi_rvalid  	(m_axi_rvalid   ),
    .s_axi_rready  	(m_axi_rready   )
);


always #(`CLOCK_PERIOD/2) clk = ~clk;

endmodule
