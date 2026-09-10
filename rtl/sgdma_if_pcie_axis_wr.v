/****************************************************************************
 * @file    sgdma_if_pcie_axis_wr.v
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

module sgdma_if_pcie_axis_wr #(
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
    parameter TX_SEQ_NUM_WIDTH = 6    
)(
    input   wire    clk ,
    input   wire    rst ,
    //1.
    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]     tx_wr_req_tlp_hdr,
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]  tx_wr_req_tlp_seq,
    output  wire [TLP_DATA_WIDTH-1:0]  tx_wr_req_tlp_data,
    output  wire [TLP_STRB_WIDTH-1:0]  tx_wr_req_tlp_strb,
    output  wire [TLP_SEG_COUNT-1:0]   tx_wr_req_tlp_valid,
    output  wire [TLP_SEG_COUNT-1:0]   tx_wr_req_tlp_sop,
    output  wire [TLP_SEG_COUNT-1:0]   tx_wr_req_tlp_eop,
    input   wire                       tx_wr_req_tlp_ready,

    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_rd_req_tlp_hdr  ,
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_rd_req_tlp_seq  ,
    output  wire [TLP_SEG_COUNT-1:0] tx_rd_req_tlp_valid,
    output  wire [TLP_SEG_COUNT-1:0] tx_rd_req_tlp_sop  ,
    output  wire [TLP_SEG_COUNT-1:0] tx_rd_req_tlp_eop  ,
    input   wire                     tx_rd_req_tlp_ready,

    /*
     * TLP input (completion)
     */
    input  wire [TLP_DATA_WIDTH-1:0]               rx_cpl_tlp_data ,
    input  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]  rx_cpl_tlp_hdr  ,
    input  wire [TLP_SEG_COUNT*4-1:0] rx_cpl_tlp_error,
    input  wire [TLP_SEG_COUNT-1:0]   rx_cpl_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]   rx_cpl_tlp_sop  ,
    input  wire [TLP_SEG_COUNT-1:0]   rx_cpl_tlp_eop  ,
    output wire                       rx_cpl_tlp_ready,

    input  wire [31 : 0] desc_wr_req_sglist_length  ,
    input  wire [PCIE_ADDR_WIDTH-1 : 0]  desc_wr_req_sglist_address ,
    input  wire desc_wr_req_sglist_start   ,
    input  wire desc_wr_req_sgdma_start    ,
    
    output wire tx_wr_sglist_irq           ,
    input  wire [15: 0]    requester_id        ,
    input  wire [2 : 0]    MaxPayloadSize      ,

    input  wire            ext_tag_enable,
    input  wire [3 :0]     rcb_128b      ,
    input  wire [2 : 0]    Max_read_PayloadSize     ,

    input  wire [TLP_DATA_WIDTH - 1 :0]      s_axis_tlp_tdata   ,
    input  wire [TLP_DATA_WIDTH / 8 - 1:0]   s_axis_tlp_tkeep   ,
    input  wire  s_axis_tlp_tvalid  ,
    input  wire  s_axis_tlp_tlast   ,
    output wire  s_axis_tlp_tready 
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
end

localparam SGLIST_FIFO_DEPTH = 10;
localparam TLP_DATA_BYTES = TLP_DATA_WIDTH / 8;

localparam  SGDMA_IDLE   = 5'b00001,
            SGDMA_RDLIST = 5'b00010,
            SGDMA_RDRECV = 5'b00100,
            SGDMA_WRMEM  = 5'b01000,
            SGDMA_WREND  = 5'b10000;
integer i;
reg [4:0] sgdma_state_reg, sgdma_state_next;
reg desc_wr_req_sglist_start_reg = 0;
reg [31 : 0] desc_wr_req_sglist_length_reg = 'b0,  desc_wr_req_sglist_length_next;
reg [PCIE_ADDR_WIDTH-1 : 0]  desc_wr_req_sglist_address_reg ='b0, desc_wr_req_sglist_address_next;

reg [31:0]desc_tx_rd_req_length_init;
reg desc_tx_rd_req_start_init;
reg [PCIE_ADDR_WIDTH-1 : 0] desc_tx_rd_req_address_init;
reg dma_wr_sglist_fifo_rden_reg = 0, dma_wr_sglist_fifo_rden_next;

reg [31:0] desc_tx_wr_length_init, desc_tx_wr_length_reg = 0;
reg desc_tx_wr_start_init;
reg [PCIE_ADDR_WIDTH-1 : 0] desc_tx_wr_addr_init , desc_tx_wr_addr_reg = 0;

reg [31:0] sgdma_stage_count_reg = 'b0 , sgdma_stage_count_next;
reg sgdma_stage_done_reg = 'b0 , sgdma_stage_done_next;
reg dma_wr_sglist_fifo_wren ;
reg sglist_axis_tready_init ;
reg tx_wr_sglist_irq_reg = 0, tx_wr_sglist_irq_next;
reg [TLP_DATA_WIDTH-1:0] dma_wr_sglist_fifo_wdata;


wire [TLP_DATA_WIDTH-1:0] sglist_axis_tdata;
wire [TLP_DATA_WIDTH/8-1:0] sglist_axis_tkeep;
wire sglist_axis_tvalid;
wire sglist_axis_tlast;
wire dma_wr_sglist_fifo_alfull;
wire dma_wr_sglist_fifo_empty;
wire [63:0] dma_wr_sglist_fifo_address;
wire [31:0] dma_wr_sglist_fifo_length;
wire [31:0] dma_wr_sglist_fifo_nums;
wire dma_wr_sglist_fifo_rden = dma_wr_sglist_fifo_rden_reg;
wire [127:0] dma_wr_sglist_fifo_dout;
wire s_axis_tlp_tready_init;
wire tx_wr_req_tlp_done;


assign dma_wr_sglist_fifo_nums = dma_wr_sglist_fifo_dout[127:96];
assign dma_wr_sglist_fifo_length = dma_wr_sglist_fifo_dout[95:64];
assign dma_wr_sglist_fifo_address = dma_wr_sglist_fifo_dout[63:0];
assign tx_wr_sglist_irq = tx_wr_sglist_irq_reg;
assign s_axis_tlp_tready =  s_axis_tlp_tready_init & (~tx_wr_req_tlp_done);

dma_if_pcie_axis_rd_v1 #(
    .TLP_DATA_WIDTH   	(TLP_DATA_WIDTH  ),
    .TLP_HDR_WIDTH    	(TLP_HDR_WIDTH   ),
    .TLP_SEG_COUNT    	(TLP_SEG_COUNT   ),
    .TX_SEQ_NUM_WIDTH 	(TX_SEQ_NUM_WIDTH),
    .PCIE_ADDR_WIDTH  	(PCIE_ADDR_WIDTH ),
    .PCIE_TAG_COUNT   	(32              )
)sglist_rd_req(
    .clk                    	(clk),
    .rst                    	(rst),

    .tx_rd_req_tlp_hdr      	(tx_rd_req_tlp_hdr   ),
    .tx_rd_req_tlp_seq      	(tx_rd_req_tlp_seq   ),
    .tx_rd_req_tlp_valid    	(tx_rd_req_tlp_valid ),
    .tx_rd_req_tlp_sop      	(tx_rd_req_tlp_sop   ),
    .tx_rd_req_tlp_eop      	(tx_rd_req_tlp_eop   ),
    .tx_rd_req_tlp_ready    	(tx_rd_req_tlp_ready ),

    .rx_cpl_tlp_data        	(rx_cpl_tlp_data   ),
    .rx_cpl_tlp_hdr         	(rx_cpl_tlp_hdr    ),
    .rx_cpl_tlp_error       	(rx_cpl_tlp_error  ),
    .rx_cpl_tlp_valid       	(rx_cpl_tlp_valid  ),
    .rx_cpl_tlp_sop         	(rx_cpl_tlp_sop    ),
    .rx_cpl_tlp_eop         	(rx_cpl_tlp_eop    ),
    .rx_cpl_tlp_ready       	(rx_cpl_tlp_ready  ),

    .requester_id           	(requester_id        ),
    .Max_read_PayloadSize   	(Max_read_PayloadSize),

    .desc_tx_rd_req_length  	(desc_tx_rd_req_length_init),
    .desc_tx_rd_req_address 	(desc_tx_rd_req_address_init),
    .desc_tx_rd_req_start   	(desc_tx_rd_req_start_init),

    .m_axis_tlp_tdata       	(sglist_axis_tdata ),
    .m_axis_tlp_tkeep       	(sglist_axis_tkeep ),
    .m_axis_tlp_tvalid      	(sglist_axis_tvalid),
    .m_axis_tlp_tlast       	(sglist_axis_tlast ),
    .m_axis_tlp_tready      	(sglist_axis_tready_init)
);


always @ * begin
    for(i = 0; i < TLP_DATA_BYTES; i = i + 1)begin
        if(sglist_axis_tkeep[i])begin
            dma_wr_sglist_fifo_wdata[i*8+:8] = sglist_axis_tdata[i*8+:8];
        end
        else begin
            dma_wr_sglist_fifo_wdata[i*8+:8] = 0;
        end
    end
end


xpm_sync_fifo #(
    .WIDTH             	(TLP_DATA_WIDTH   ),
    .DEPTH             	(SGLIST_FIFO_DEPTH),
    .FIFO_TYPE         	("fwft"    ),
    .Asymmetric_Mode    (1),
    .WRITE_WIDTH_PARAM  (TLP_DATA_WIDTH),
    .READ_WIDTH_PARAM   (128),
    .FIFO_MEMORY       	("auto"   ),
    .USER_ADV_FEATURES 	("1f1f"   )
)dma_wr_sglist_fifo(
    .clk           	(clk),
    .rst           	(rst),
    .wr_en         	(dma_wr_sglist_fifo_wren),
    .rd_en         	(dma_wr_sglist_fifo_rden),
    .data          	(dma_wr_sglist_fifo_wdata),
    .dout          	(dma_wr_sglist_fifo_dout),
    .full          	(),
    .empty         	(dma_wr_sglist_fifo_empty),
    .almost_empty  	(),
    .almost_full   	(dma_wr_sglist_fifo_alfull),
    .rd_data_count 	(),
    .wr_data_count 	()
);



dma_if_pcie_axis_wr_v1 #(
    .TLP_DATA_WIDTH   	(TLP_DATA_WIDTH   ),
    .TLP_STRB_WIDTH   	(TLP_STRB_WIDTH   ),
    .TLP_HDR_WIDTH    	(TLP_HDR_WIDTH    ),
    .TLP_SEG_COUNT    	(TLP_SEG_COUNT    ),
    .PCIE_ADDR_WIDTH  	(PCIE_ADDR_WIDTH  ),
    .TX_SEQ_NUM_COUNT 	(TX_SEQ_NUM_COUNT ),
    .TX_SEQ_NUM_WIDTH 	(TX_SEQ_NUM_WIDTH )
)sgdma_wr(
    .clk                 	(clk),
    .rst                 	(rst),

    .tx_wr_req_tlp_data  	(tx_wr_req_tlp_data ),
    .tx_wr_req_tlp_strb  	(tx_wr_req_tlp_strb ),
    .tx_wr_req_tlp_hdr   	(tx_wr_req_tlp_hdr  ),
    .tx_wr_req_tlp_seq   	(tx_wr_req_tlp_seq  ),
    .tx_wr_req_tlp_valid 	(tx_wr_req_tlp_valid),
    .tx_wr_req_tlp_sop   	(tx_wr_req_tlp_sop  ),
    .tx_wr_req_tlp_eop   	(tx_wr_req_tlp_eop  ),
    .tx_wr_req_tlp_ready 	(tx_wr_req_tlp_ready),

    .desc_wr_req_length  	(desc_tx_wr_length_init),
    .desc_wr_req_address 	(desc_tx_wr_addr_init),
    .desc_wr_req_start   	(desc_tx_wr_start_init),

    .requester_id        	(requester_id  ),
    .MaxPayloadSize      	(MaxPayloadSize),
    .tx_wr_req_tlp_done     (tx_wr_req_tlp_done),

    .s_axis_tlp_tdata    	(s_axis_tlp_tdata  ),
    .s_axis_tlp_tkeep    	(s_axis_tlp_tkeep  ),
    .s_axis_tlp_tvalid   	(s_axis_tlp_tvalid ),
    .s_axis_tlp_tlast    	(s_axis_tlp_tlast  ),
    .s_axis_tlp_tready   	(s_axis_tlp_tready_init )
);


always @(*) begin
    sgdma_state_next = sgdma_state_reg;

    desc_wr_req_sglist_address_next = desc_wr_req_sglist_address_reg;
    desc_wr_req_sglist_length_next = desc_wr_req_sglist_length_reg;

    desc_tx_rd_req_address_init = 'b0;
    desc_tx_rd_req_length_init = 'b0;
    desc_tx_rd_req_start_init = 'b0;

    dma_wr_sglist_fifo_rden_next = dma_wr_sglist_fifo_rden_reg;

    desc_tx_wr_length_init = dma_wr_sglist_fifo_length;
    desc_tx_wr_start_init = 0;
    desc_tx_wr_addr_init = dma_wr_sglist_fifo_address;

    sgdma_stage_count_next = sgdma_stage_count_reg;
    sgdma_stage_done_next = sgdma_stage_done_reg;

    dma_wr_sglist_fifo_wren = sglist_axis_tvalid & sglist_axis_tready_init;

    tx_wr_sglist_irq_next = tx_wr_sglist_irq_reg;
    
    sglist_axis_tready_init = ~dma_wr_sglist_fifo_alfull;
    case (sgdma_state_reg)
        SGDMA_IDLE   : begin
            sgdma_stage_count_next = 'b0;
            sgdma_stage_done_next = 'b0;
            if (desc_wr_req_sglist_start && (~desc_wr_req_sglist_start_reg)) begin
                sgdma_state_next = SGDMA_RDLIST;
                desc_wr_req_sglist_address_next = desc_wr_req_sglist_address;
                desc_wr_req_sglist_length_next = desc_wr_req_sglist_length;
            end
        end

        SGDMA_RDLIST : begin
            desc_tx_rd_req_address_init = desc_wr_req_sglist_address_reg;
            desc_tx_rd_req_length_init = desc_wr_req_sglist_length_reg;
            desc_tx_rd_req_start_init = desc_wr_req_sglist_start_reg;

            if (desc_wr_req_sglist_start_reg) begin
                sgdma_state_next = SGDMA_RDRECV;
            end
        end

        SGDMA_RDRECV : begin
            if (sglist_axis_tlast && sglist_axis_tvalid && sglist_axis_tready_init) begin
                tx_wr_sglist_irq_next = 1'b1;
            end
            if (desc_wr_req_sgdma_start) begin
                sgdma_state_next = SGDMA_WRMEM;
            end
        end

        SGDMA_WRMEM  : begin
            if (dma_wr_sglist_fifo_rden_next) begin
                dma_wr_sglist_fifo_rden_next = 'b0;
                desc_tx_wr_start_init = 1'b0;
                sgdma_state_next = SGDMA_WREND;
            end
            else if(~dma_wr_sglist_fifo_empty)begin
                if(~|dma_wr_sglist_fifo_dout)begin
                    dma_wr_sglist_fifo_rden_next = 1'b1;
                end
                else begin 
                    dma_wr_sglist_fifo_rden_next = 1'b1;
                    desc_tx_wr_start_init = 1'b1;
                    desc_tx_wr_addr_init = dma_wr_sglist_fifo_address;
                end
            end
        end

        SGDMA_WREND  : begin
            if (sgdma_stage_count_reg >= desc_tx_wr_length_reg) begin
                sgdma_stage_done_next = 1'b1;
                if (dma_wr_sglist_fifo_empty) begin
                    sgdma_state_next = SGDMA_IDLE;
                end
                else begin
                    sgdma_stage_count_next = 'b0;
                    sgdma_stage_count_next = 'b0;
                    sgdma_state_next = SGDMA_WRMEM;
                end
            end
            else if (tx_wr_req_tlp_valid && tx_wr_req_tlp_ready) begin
                sgdma_stage_count_next = sgdma_stage_count_reg + TLP_DATA_BYTES;
            end
            else if(~|desc_tx_wr_length_reg)begin
                if(dma_wr_sglist_fifo_empty)begin
                    sgdma_state_next = SGDMA_IDLE;
                end
                else begin
                    sgdma_state_next = SGDMA_WRMEM;                
                end
            end
        end
        default:begin end 
    endcase
end


always @(posedge clk) begin
    if (rst) begin
        sgdma_state_reg <= SGDMA_IDLE;
        desc_wr_req_sglist_start_reg <= 'b0;
        desc_wr_req_sglist_address_reg <= 'b0;
        desc_wr_req_sglist_length_reg <= 'b0;

        dma_wr_sglist_fifo_rden_reg <= 'b0;
        sgdma_stage_count_reg <= 'b0;
        sgdma_stage_done_reg <= 'b0;

        tx_wr_sglist_irq_reg <= 'b0;
        
        desc_tx_wr_length_reg <= 'b0;
        desc_tx_wr_addr_reg <= 'b0;
        
    end
    else begin
        sgdma_state_reg <= sgdma_state_next;
        desc_wr_req_sglist_start_reg <= desc_wr_req_sglist_start;
        desc_wr_req_sglist_address_reg <= desc_wr_req_sglist_address_next;
        desc_wr_req_sglist_length_reg <= desc_wr_req_sglist_length_next;

        dma_wr_sglist_fifo_rden_reg <= dma_wr_sglist_fifo_rden_next;
        sgdma_stage_count_reg <= sgdma_stage_count_next;
        sgdma_stage_done_reg <= sgdma_stage_done_next;

        if (tx_wr_sglist_irq_reg) begin
            tx_wr_sglist_irq_reg <= 'b0;
        end
        else begin
            tx_wr_sglist_irq_reg <= tx_wr_sglist_irq_next;
        end
        
        if(dma_wr_sglist_fifo_rden)begin
            desc_tx_wr_length_reg <= desc_tx_wr_length_init;
            desc_tx_wr_addr_reg <= desc_tx_wr_addr_init;
        end 
        
    end
end

endmodule


`resetall