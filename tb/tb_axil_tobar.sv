/****************************************************************************
 * @file    tb_axil_tobar.v
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

`define CLOCK_PERIOD 2.5

module tb_axil_tobar();

// TLP data width
parameter TLP_DATA_WIDTH        = 512               ;
// TLP strobe width
parameter TLP_STRB_WIDTH        = TLP_DATA_WIDTH/32 ;
// TLP header width
parameter TLP_HDR_WIDTH         = 128               ;
// TLP segment count
parameter TLP_SEG_COUNT         = 1                 ;
// Width of AXI lite data bus in bits
parameter AXIL_DATA_WIDTH       = 32                ;
// Width of AXI lite address bus in bits
parameter AXIL_ADDR_WIDTH       = 64                ;
// Width of AXI lite wstrb (width of data bus in words)
parameter AXIL_STRB_WIDTH       = (AXIL_DATA_WIDTH/8);
// Force 64 bit address
parameter TLP_FORCE_64_BIT_ADDR = 0 ;

reg        clk  =   1;
reg        rst  =   1;

    /*
     * TLP input (request)
     */
reg [TLP_DATA_WIDTH-1:0]               rx_req_tlp_data  = 0;
reg [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]  rx_req_tlp_hdr   = 0;
reg [TLP_SEG_COUNT-1:0]                rx_req_tlp_valid = 0; 
reg [TLP_SEG_COUNT-1:0]                rx_req_tlp_sop   = 0; 
reg [TLP_SEG_COUNT-1:0]                rx_req_tlp_eop   = 0;
wire                                   rx_req_tlp_ready ;

    /*
     * TLP output (completion)
     */
wire [TLP_DATA_WIDTH-1:0]               tx_cpl_tlp_data;
wire [TLP_STRB_WIDTH-1:0]               tx_cpl_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]  tx_cpl_tlp_hdr;
wire [TLP_SEG_COUNT-1:0]                tx_cpl_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                tx_cpl_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                tx_cpl_tlp_eop;
reg                                     tx_cpl_tlp_ready = 1;
    /*
     * Configuration
     */
reg [15:0]                             completer_id   = 16'h0;

initial begin
    #(`CLOCK_PERIOD * 100);
    @(posedge clk);
    rst <= 0;
    #(`CLOCK_PERIOD);
    @(posedge clk);
    rx_req_tlp_data <= 512'h14;
    rx_req_tlp_hdr  <= 128'h60001001_0000000f_00000000_fcf00020;
    rx_req_tlp_valid<= 1;
    rx_req_tlp_sop  <= 1;
    rx_req_tlp_eop  <= 1;
    wait(rx_req_tlp_valid & rx_req_tlp_ready)
    @(posedge clk);
    rx_req_tlp_valid<= 0;
    rx_req_tlp_sop  <= 0;
    rx_req_tlp_eop  <= 0;
    #(`CLOCK_PERIOD * 20) ;
    @(posedge clk);
    // rx_req_tlp_data <= 512'h14;
    rx_req_tlp_hdr  <= 128'h20001001_0000220f_00000000_fcf00020;
    rx_req_tlp_valid<= 1;
    rx_req_tlp_sop  <= 1;
    rx_req_tlp_eop  <= 1;    
    wait(rx_req_tlp_valid & rx_req_tlp_ready)
    @(posedge clk);
    rx_req_tlp_valid<= 0;
    rx_req_tlp_sop  <= 0;
    rx_req_tlp_eop  <= 0;    
end

pcie_axil_tobar_master #(
    .TLP_DATA_WIDTH        	(TLP_DATA_WIDTH  ),
    .TLP_STRB_WIDTH        	(TLP_STRB_WIDTH   ),
    .TLP_HDR_WIDTH         	(TLP_HDR_WIDTH  ),
    .TLP_SEG_COUNT         	(1    ),
    .AXIL_DATA_WIDTH       	(AXIL_DATA_WIDTH   ),
    .AXIL_ADDR_WIDTH       	(AXIL_ADDR_WIDTH   ),
    .AXIL_STRB_WIDTH       	(AXIL_STRB_WIDTH    ),
    .TLP_FORCE_64_BIT_ADDR 	(0    )
)u_pcie_axil_tobar_master(
    .clk              	(clk               ),
    .rst              	(rst               ),
    .rx_req_tlp_data  	(rx_req_tlp_data   ),
    .rx_req_tlp_hdr   	(rx_req_tlp_hdr    ),
    .rx_req_tlp_valid 	(rx_req_tlp_valid  ),
    .rx_req_tlp_sop   	(rx_req_tlp_sop    ),
    .rx_req_tlp_eop   	(rx_req_tlp_eop    ),
    .rx_req_tlp_ready 	(rx_req_tlp_ready  ),
    .tx_cpl_tlp_data  	(tx_cpl_tlp_data   ),
    .tx_cpl_tlp_strb  	(tx_cpl_tlp_strb   ),
    .tx_cpl_tlp_hdr   	(tx_cpl_tlp_hdr    ),
    .tx_cpl_tlp_valid 	(tx_cpl_tlp_valid  ),
    .tx_cpl_tlp_sop   	(tx_cpl_tlp_sop    ),
    .tx_cpl_tlp_eop   	(tx_cpl_tlp_eop    ),
    .tx_cpl_tlp_ready 	(tx_cpl_tlp_ready  ),
    .completer_id     	(completer_id      )
);

always #(`CLOCK_PERIOD / 2) clk = ~clk;

endmodule