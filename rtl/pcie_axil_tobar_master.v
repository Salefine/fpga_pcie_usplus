/****************************************************************************
 * @file    pcie_axil_tobar_master.v
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

module pcie_axil_tobar_master#(
    // TLP data width
    parameter TLP_DATA_WIDTH        = 256               ,
    // TLP strobe width
    parameter TLP_STRB_WIDTH        = TLP_DATA_WIDTH/32 ,
    // TLP header width
    parameter TLP_HDR_WIDTH         = 128               ,
    // TLP segment count
    parameter TLP_SEG_COUNT         = 1                 ,
    // Width of AXI lite data bus in bits
    parameter AXIL_DATA_WIDTH       = 32                ,
    // Width of AXI lite address bus in bits
    parameter AXIL_ADDR_WIDTH       = 64                ,
    // Width of AXI lite wstrb (width of data bus in words)
    parameter AXIL_STRB_WIDTH       = (AXIL_DATA_WIDTH/8),
    // Force 64 bit address
    parameter TLP_FORCE_64_BIT_ADDR = 0
) (
    input  wire                                    clk,
    input  wire                                    rst,

    /*
     * TLP input (request)
     */
    input  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]  rx_req_tlp_hdr,
    input  wire [TLP_DATA_WIDTH-1:0] rx_req_tlp_data,
    input  wire [TLP_SEG_COUNT-1:0]  rx_req_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]  rx_req_tlp_sop,
    input  wire [TLP_SEG_COUNT-1:0]  rx_req_tlp_eop,
    output wire                      rx_req_tlp_ready,

    /*
     * TLP output (completion)
     */
    output wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]  tx_cpl_tlp_hdr,
    output wire [TLP_DATA_WIDTH-1:0]   tx_cpl_tlp_data,
    output wire [TLP_STRB_WIDTH-1:0]   tx_cpl_tlp_strb,
    output wire [TLP_SEG_COUNT-1:0]    tx_cpl_tlp_valid,
    output wire [TLP_SEG_COUNT-1:0]    tx_cpl_tlp_sop,
    output wire [TLP_SEG_COUNT-1:0]    tx_cpl_tlp_eop,
    input  wire                        tx_cpl_tlp_ready,
    /*
     * Configuration
     */
    input  wire [15:0]                             completer_id    ,

    output  wire [31:0]   C2HBlockDMA_low_address     ,
    output  wire [31:0]   C2HBlockDMA_high_address    ,
    output  wire [31:0]   C2HBlockDMA_length          ,
    output  wire [31:0]   C2HBlockDMA_Start           ,
    input   wire [31:0]   C2HBlockDMA_Status          ,
    output  wire [31:0]   C2H_DMA_SDRAM_LOW_ADDRESS   ,
    output  wire [31:0]   C2H_DMA_SDRAM_HIGH_ADDRESS  ,

    output  wire [31:0]   H2CBlockDMA_low_address     ,
    output  wire [31:0]   H2CBlockDMA_high_address    ,
    output  wire [31:0]   H2CBlockDMA_length          ,
    output  wire [31:0]   H2CBlockDMA_Start           ,
    output  wire [31:0]   H2C_DMA_SDRAM_LOW_ADDRESS   ,
    output  wire [31:0]   H2C_DMA_SDRAM_HIGH_ADDRESS  ,
    input   wire [31:0]   H2CBlockDMA_Status          ,

	output wire[31:0]       C2H_SgList_LOW_address		,
	output wire[31:0]       C2H_SgList_HIGH_address		,
	output wire[31:0]       C2H_SgList_length			,
	output wire             C2H_SgList_Start			,
	output wire             C2H_SgDMA_Start			    ,
	output wire[31:0]       C2H_SgDMA_length			,
	output wire[31:0]       C2H_SgSDRAM_LOW_address		,
	output wire[31:0]       C2H_SgSDRAM_HIGH_address    ,
	input  wire[31:0]       C2H_SgDMA_Status            ,

	output wire[31:0]       H2C_SgList_LOW_address		,
	output wire[31:0]       H2C_SgList_HIGH_address		,
	output wire[31:0]       H2C_SgList_length			,
	output wire             H2C_SgList_Start			,
	output wire             H2C_SgDMA_Start			    ,
	output wire[31:0]       H2C_SgDMA_length			,
	output wire[31:0]       H2C_SgSDRAM_LOW_address		,
	output wire[31:0]       H2C_SgSDRAM_HIGH_address    ,
	input  wire[31:0]       H2C_SgDMA_Status            
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

    if (AXIL_DATA_WIDTH != 32) begin
        $error("Error: AXI lite interface width must be 32 (instance %m)");
        $finish;
    end

    if (AXIL_STRB_WIDTH * 8 != AXIL_DATA_WIDTH) begin
        $error("Error: AXI lite interface requires byte (8-bit) granularity (instance %m)");
        $finish;
    end
end

localparam [2:0]
    TLP_FMT_3DW = 3'b000,
    TLP_FMT_4DW = 3'b001,
    TLP_FMT_3DW_DATA = 3'b010,
    TLP_FMT_4DW_DATA = 3'b011,
    TLP_FMT_PREFIX = 3'b100;

localparam [3:0]
    REQ_MEM_READ = 4'b0000,
    REQ_MEM_WRITE = 4'b0001,
    REQ_IO_READ = 4'b0010,
    REQ_IO_WRITE = 4'b0011,
    REQ_MEM_FETCH_ADD = 4'b0100,
    REQ_MEM_SWAP = 4'b0101,
    REQ_MEM_CAS = 4'b0110,
    REQ_MEM_READ_LOCKED = 4'b0111,
    REQ_CFG_READ_0 = 4'b1000,
    REQ_CFG_READ_1 = 4'b1001,
    REQ_CFG_WRITE_0 = 4'b1010,
    REQ_CFG_WRITE_1 = 4'b1011,
    REQ_MSG = 4'b1100,
    REQ_MSG_VENDOR = 4'b1101,
    REQ_MSG_ATS = 4'b1110;

localparam [5:0] 
    M_BAR_IDLE    = 6'b000001,
    MWR_BAR_WADDR = 6'b000010,
    MWR_BAR_WDATA = 6'b000100,
    MWR_BAR_WEND  = 6'b001000,
    MRD_BAR_RADDR = 6'b010000,
    MRD_BAR_RDATA = 6'b100000;

/* ******************************************************
 * wire define 
 *******************************************************/    
wire    [2:0]                         tlp_fmt     ;
wire    [3:0]                         tlp_type    ;


/* ******************************************************
 * regisetr define 
 *******************************************************/   
(* MARK_DEBUG="true" *)reg [AXIL_ADDR_WIDTH-1:0]             m_axil_bar_awaddr  ;
wire[2:0]                             m_axil_bar_awprot  ;
(* MARK_DEBUG="true" *)reg                                   m_axil_bar_awvalid ;
wire                                  m_axil_bar_awready ;
(* MARK_DEBUG="true" *)reg [AXIL_DATA_WIDTH-1:0]             m_axil_bar_wdata   ;
reg [AXIL_STRB_WIDTH-1:0]             m_axil_bar_wstrb   ;
(* MARK_DEBUG="true" *)reg                                   m_axil_bar_wvalid  ;
wire                                  m_axil_bar_wready  ;
wire[1:0]                             m_axil_bar_bresp   ;
wire                                  m_axil_bar_bvalid  ;
reg                                   m_axil_bar_bready  ;
reg [AXIL_ADDR_WIDTH-1:0]             m_axil_bar_araddr  ;
wire[2:0]                             m_axil_bar_arprot  ;
reg                                   m_axil_bar_arvalid ;
wire                                  m_axil_bar_arready ;
wire[AXIL_DATA_WIDTH-1:0]             m_axil_bar_rdata   ;
wire[1:0]                             m_axil_bar_rresp   ;
wire                                  m_axil_bar_rvalid  ;
reg                                   m_axil_bar_rready  ;

reg     [15:0]                        requester_id   ;
reg     [7 :0]                        requester_tag  ;
reg     [63:0]                        requester_addr ;

reg [5:0]    m_state     ;
reg [5:0]    m_next_state;

reg [TLP_DATA_WIDTH - 1 : 0] tx_cpl_tlp_data_reg  ;
reg [TLP_STRB_WIDTH - 1 : 0] tx_cpl_tlp_strb_reg  ;
reg [TLP_HDR_WIDTH - 1 : 0]  tx_cpl_tlp_hdr_reg   ;
reg                          tx_cpl_tlp_valid_reg ;
reg                          tx_cpl_tlp_sop_reg   ;
reg                          tx_cpl_tlp_eop_reg   ;

reg                         rx_req_tlp_ready_reg;

assign m_axil_bar_awprot = 3'b010;
assign m_axil_bar_arprot = 3'b010;
assign tx_cpl_tlp_data = tx_cpl_tlp_data_reg;
assign tx_cpl_tlp_eop  = tx_cpl_tlp_eop_reg ;
assign tx_cpl_tlp_hdr  = tx_cpl_tlp_hdr_reg ;
assign tx_cpl_tlp_sop  = tx_cpl_tlp_sop_reg ;
assign tx_cpl_tlp_strb = tx_cpl_tlp_strb_reg;
assign tx_cpl_tlp_valid= tx_cpl_tlp_valid_reg;

assign  tlp_fmt  = rx_req_tlp_hdr[127:125];
assign  tlp_type = rx_req_tlp_hdr[124:120]; 
assign  rx_req_tlp_ready = rx_req_tlp_ready_reg;
// assign  rx_req_tlp_ready = (m_state == MWR_BAR_WADDR) || (m_state == MRD_BAR_RADDR) ? 1'b1 : 1'b0;
//assign  m_axil_awprot = 3'b010;

always @(posedge clk) begin
    if (rst) begin
        rx_req_tlp_ready_reg <= 0;
    end
    else if (rx_req_tlp_ready_reg & rx_req_tlp_valid ) begin
        rx_req_tlp_ready_reg <= 0;
    end
    else if (rx_req_tlp_valid & (m_state == M_BAR_IDLE)) begin
        rx_req_tlp_ready_reg <= 1;
    end
end

always @(posedge clk) begin
    if (rst) begin
        m_state <= M_BAR_IDLE;
    end
    else begin
        m_state <= m_next_state;
    end
end

always @(*) begin
    m_next_state = m_state;

    case (m_state)
        M_BAR_IDLE: begin // M_BAR_IDLE
            if (rx_req_tlp_valid & rx_req_tlp_ready) begin
                if (tlp_fmt == TLP_FMT_4DW)
                    m_next_state = MRD_BAR_RADDR;
                else if (tlp_fmt == TLP_FMT_4DW_DATA)
                    m_next_state = MWR_BAR_WADDR;
            end
        end

        MWR_BAR_WADDR: begin // MWR_BAR_WADDR
            if (m_axil_bar_awvalid && m_axil_bar_awready)
                m_next_state = MWR_BAR_WDATA;
        end

        MWR_BAR_WDATA: begin
            if (m_axil_bar_wvalid && m_axil_bar_wready)
                m_next_state = MWR_BAR_WEND;
        end

        MWR_BAR_WEND: begin
            if (m_axil_bar_bvalid & m_axil_bar_bready)
                m_next_state = M_BAR_IDLE;
        end

        MRD_BAR_RADDR: begin
            if (m_axil_bar_arvalid & m_axil_bar_arready)
                m_next_state = MRD_BAR_RDATA;
        end

        MRD_BAR_RDATA: begin
            if (m_axil_bar_rvalid & m_axil_bar_rready)
                m_next_state = M_BAR_IDLE;
        end

        default: m_next_state = M_BAR_IDLE;
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        requester_id  <= 0;
        requester_tag <= 0;
        requester_addr<= 0;
    end
    else if (rx_req_tlp_ready & rx_req_tlp_valid) begin
        requester_tag <= rx_req_tlp_hdr[79:72];
        requester_id  <= rx_req_tlp_hdr[95:80];
        requester_addr<= rx_req_tlp_hdr[63:0]; 
    end
end

always @(posedge clk) begin
    if (rst) begin
        m_axil_bar_awaddr <= 0;
    end
    else if (m_state == MWR_BAR_WADDR) begin
        m_axil_bar_awaddr <= {25'b0 , requester_addr[7:0]};
    end
end

always @(posedge clk) begin
    if (rst) begin
        m_axil_bar_awvalid <= 0;
    end
    else if (m_axil_bar_awvalid & m_axil_bar_awready) begin
        m_axil_bar_awvalid <= 0;
    end
    else if (m_state == MWR_BAR_WADDR) begin
        m_axil_bar_awvalid <= 1;
    end
end

always @(posedge clk) begin
    if (rst) begin
        m_axil_bar_wvalid <= 0;
    end
    else if (m_axil_bar_wvalid & m_axil_bar_wready) begin
        m_axil_bar_wvalid <= 0;
    end
    else if (m_state == MWR_BAR_WDATA) begin
        m_axil_bar_wvalid <= 1;
    end    
end

always @(posedge clk) begin
    if (rst) begin
        m_axil_bar_wdata <= 0;
    end
    else if (rx_req_tlp_ready & rx_req_tlp_valid) begin
        m_axil_bar_wdata <= rx_req_tlp_data[31:0];
    end
end

always @(posedge clk) begin
    if (rst) begin
        m_axil_bar_wstrb <= 0;
    end
    else if (rx_req_tlp_ready & rx_req_tlp_valid) begin
        m_axil_bar_wstrb <= 4'hf;
    end
end

always @(posedge clk) begin
    if (rst) begin
        m_axil_bar_bready <= 0;
    end
    else if (m_axil_bar_bvalid & m_axil_bar_bready) begin
        m_axil_bar_bready <= 0;
    end
    else if (m_axil_bar_bvalid) begin
        m_axil_bar_bready <= 1;
    end
end

always @(posedge clk) begin
    if (rst) begin
        m_axil_bar_arvalid <= 0;
    end
    else if (m_axil_bar_arvalid & m_axil_bar_arready) begin
        m_axil_bar_arvalid <= 0;
    end
    else if (m_state == MRD_BAR_RADDR) begin
        m_axil_bar_arvalid <= 1;
    end    
end

always @(posedge clk) begin
    if (rst) begin
        m_axil_bar_araddr <= 0;
    end
    else if (m_state == MRD_BAR_RADDR) begin
        m_axil_bar_araddr <= {25'b0 , requester_addr[7:0]};
    end
end

always @(posedge clk) begin
    if (rst) begin
        m_axil_bar_rready <= 0;
    end
    else if (m_axil_bar_rvalid & m_axil_bar_rready) begin
        m_axil_bar_rready <= 0;
    end
    else if(m_axil_bar_rvalid)begin
        m_axil_bar_rready <= 1;
    end
end

/*
 * cpld packet
 */
always @(posedge clk) begin
    if (rst) begin
        tx_cpl_tlp_valid_reg <= 0;
    end
    else if (tx_cpl_tlp_ready & tx_cpl_tlp_valid) begin
        tx_cpl_tlp_valid_reg <= 0;
    end
    else if (m_state == MRD_BAR_RDATA && (m_state != m_next_state)) begin
        tx_cpl_tlp_valid_reg <= 1;
    end
end

always @(posedge clk) begin
    if (rst) begin
        tx_cpl_tlp_data_reg <= 0;
    end
    else if(m_state == MRD_BAR_RDATA && (m_state != m_next_state))begin
        tx_cpl_tlp_data_reg <= m_axil_bar_rdata;
    end
end

always @(posedge clk) begin
    if (rst) begin
        tx_cpl_tlp_sop_reg <= 0;
    end
    else if (tx_cpl_tlp_ready & tx_cpl_tlp_valid)begin
        tx_cpl_tlp_sop_reg <= 0;
    end
    else if(m_state == MRD_BAR_RDATA && (m_state != m_next_state))begin
        tx_cpl_tlp_sop_reg <= 1;
    end

end

always @(posedge clk) begin
    if (rst) begin
        tx_cpl_tlp_eop_reg <= 0;
    end
    else if (tx_cpl_tlp_ready & tx_cpl_tlp_valid)begin
        tx_cpl_tlp_eop_reg <= 0;
    end
    else if(m_state == MRD_BAR_RDATA && (m_state != m_next_state))begin
        tx_cpl_tlp_eop_reg <= 1;
    end
end

always @(posedge clk) begin
    if (rst) begin
        tx_cpl_tlp_strb_reg <= 0;
    end
    else if(m_state == MRD_BAR_RDATA && (m_state != m_next_state))begin
        tx_cpl_tlp_strb_reg <= 16'h1;
    end
end

always @(posedge clk) begin
    if (rst) begin
        tx_cpl_tlp_hdr_reg <= 0;
    end
    else if (m_state == MRD_BAR_RDATA && (m_state != m_next_state)) begin
        tx_cpl_tlp_hdr_reg <= {
            //DW0
            TLP_FMT_3DW_DATA , //fmt          3bit
            5'b01010         , //type         5bit
            1'b0,
            3'b000           ,
            1'b0,
            1'b0,
            4'b0,
            2'b0,
            2'b00,
            10'd1,
            //DW1
            16'h0,   //completer id
            3'b0,    //status
            1'b0,    //bcm
            12'h4,   //byte count
            //DW2
            requester_id , //requester id
            requester_tag, //tag
            1'b0,          
            requester_addr[6:0], //low address
            //
            32'd0
        };
    end
end
/* *********************************************************
 * pcie bar register
 **********************************************************/

pcie_bar_register #(
    .C_S_AXI_DATA_WIDTH 	(32  ),
    .C_S_AXI_ADDR_WIDTH 	(AXIL_ADDR_WIDTH   ))
bar_register(
    .C2HBlockDMA_low_address  	(C2HBlockDMA_low_address   ),
    .C2HBlockDMA_high_address 	(C2HBlockDMA_high_address  ),
    .C2HBlockDMA_length       	(C2HBlockDMA_length        ),
    .C2HBlockDMA_Start        	(C2HBlockDMA_Start         ),
    .C2HBlockDMA_Status         (C2HBlockDMA_Status        ),
    .H2CBlockDMA_low_address  	(H2CBlockDMA_low_address   ),
    .H2CBlockDMA_high_address 	(H2CBlockDMA_high_address  ),
    .H2CBlockDMA_length       	(H2CBlockDMA_length        ),
    .H2CBlockDMA_Start        	(H2CBlockDMA_Start         ),
    .H2CBlockDMA_Status         (H2CBlockDMA_Status        ),
    .C2H_DMA_SDRAM_LOW_ADDRESS  (C2H_DMA_SDRAM_LOW_ADDRESS ),
    .C2H_DMA_SDRAM_HIGH_ADDRESS (C2H_DMA_SDRAM_HIGH_ADDRESS),
    .H2C_DMA_SDRAM_LOW_ADDRESS  (H2C_DMA_SDRAM_LOW_ADDRESS ),
    .H2C_DMA_SDRAM_HIGH_ADDRESS (H2C_DMA_SDRAM_HIGH_ADDRESS),

    .C2H_SgList_LOW_address     	(C2H_SgList_LOW_address      ),
    .C2H_SgList_HIGH_address    	(C2H_SgList_HIGH_address     ),
    .C2H_SgList_length           	(C2H_SgList_length            ),
    .C2H_SgList_Start           	(C2H_SgList_Start            ),
    .C2H_SgDMA_Start            	(C2H_SgDMA_Start             ),
    .C2H_SgDMA_length           	(C2H_SgDMA_length            ),
    .C2H_SGDMA_SDRAM_LOW_ADDRESS    (C2H_SgSDRAM_LOW_address     ),
    .C2H_SGDMA_SDRAM_HIGH_ADDRESS   (C2H_SgSDRAM_HIGH_address    ),
    .C2H_SgDMA_Status           	(C2H_SgDMA_Status            ),
    .H2C_SgList_LOW_address     	(H2C_SgList_LOW_address      ),
    .H2C_SgList_HIGH_address    	(H2C_SgList_HIGH_address     ),
    .H2C_SgList_length           	(H2C_SgList_length            ),
    .H2C_SgList_Start           	(H2C_SgList_Start            ),
    .H2C_SgDMA_Start            	(H2C_SgDMA_Start             ),
    .H2C_SgDMA_length           	(H2C_SgDMA_length            ),
    .H2C_SGDMA_SDRAM_LOW_ADDRESS    (H2C_SgSDRAM_LOW_address     ),
    .H2C_SGDMA_SDRAM_HIGH_ADDRESS   (H2C_SgSDRAM_HIGH_address    ),
    .H2C_SgDMA_Status           	(H2C_SgDMA_Status            ),

    .S_AXI_ACLK    (clk),
    .S_AXI_ARESETN (~rst),
    
    .S_AXI_AWADDR  (m_axil_bar_awaddr),
    .S_AXI_AWPROT  (m_axil_bar_awprot),
    .S_AXI_AWVALID (m_axil_bar_awvalid),
    .S_AXI_AWREADY (m_axil_bar_awready),
    
    .S_AXI_WDATA   (m_axil_bar_wdata),
    .S_AXI_WSTRB   (m_axil_bar_wstrb),
    .S_AXI_WVALID  (m_axil_bar_wvalid),
    .S_AXI_WREADY  (m_axil_bar_wready),
    
    .S_AXI_BRESP   (m_axil_bar_bresp),
    .S_AXI_BVALID  (m_axil_bar_bvalid),
    .S_AXI_BREADY  (m_axil_bar_bready),
    
    .S_AXI_ARADDR  (m_axil_bar_araddr),
    .S_AXI_ARPROT  (m_axil_bar_arprot),
    .S_AXI_ARVALID (m_axil_bar_arvalid),
    .S_AXI_ARREADY (m_axil_bar_arready),
    
    .S_AXI_RDATA   (m_axil_bar_rdata),
    .S_AXI_RRESP   (m_axil_bar_rresp),
    .S_AXI_RVALID  (m_axil_bar_rvalid),
    .S_AXI_RREADY  (m_axil_bar_rready)
);



endmodule