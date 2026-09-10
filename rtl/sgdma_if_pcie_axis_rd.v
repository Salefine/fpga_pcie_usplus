/****************************************************************************
 * @file    sgdma_if_pcie_axis_rd.v
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
 * |  2026-09-08   |   v1.1      |    zzhi          | desc端口更名: desc_tx_rdlist_*→desc_rd_req_sglist_*, |
 * |               |             |                  | desc_tx_rddma_start→desc_rd_req_sgdma_start |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2026 zzhi
 * ***************************************************************************/

`resetall
`timescale 1ns/1ps
`default_nettype none

module sgdma_if_pcie_axis_rd#(
    // TLP data width
    parameter TLP_DATA_WIDTH = 256,
    // TLP header width
    parameter TLP_HDR_WIDTH = 128,
    // TLP segment count
    parameter TLP_SEG_COUNT = 1,
    // TX sequence number width
    parameter TX_SEQ_NUM_WIDTH = 6,
    // PCIe address width
    parameter PCIE_ADDR_WIDTH = 64,
    // PCIe tag count
    parameter PCIE_TAG_COUNT = 32,
    // Operation table size
    parameter OP_TABLE_SIZE = PCIE_TAG_COUNT
)(
    input   wire    clk ,
    input   wire    rst ,

    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_rd_req_tlp_hdr  ,
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_rd_req_tlp_seq  ,
    output  wire [TLP_SEG_COUNT-1:0]  tx_rd_req_tlp_valid,
    output  wire [TLP_SEG_COUNT-1:0]  tx_rd_req_tlp_sop  ,
    output  wire [TLP_SEG_COUNT-1:0]  tx_rd_req_tlp_eop  ,
    input   wire                      tx_rd_req_tlp_ready,


    input  wire [TLP_DATA_WIDTH-1:0]                     rx_cpl_tlp_data ,
    input  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        rx_cpl_tlp_hdr  ,
    input  wire [TLP_SEG_COUNT*4-1:0] rx_cpl_tlp_error,
    input  wire [TLP_SEG_COUNT-1:0]   rx_cpl_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]   rx_cpl_tlp_sop  ,
    input  wire [TLP_SEG_COUNT-1:0]   rx_cpl_tlp_eop  ,
    output wire                       rx_cpl_tlp_ready,

    input  wire [15:0]  requester_id  ,
    input  wire [2 : 0] max_read_payloadSize     ,
    output wire         tx_rd_req_irq,


    input  wire [31 : 0]         desc_rd_req_sglist_length         ,//bytes
    input  wire [PCIE_ADDR_WIDTH-1 : 0] desc_rd_req_sglist_address,
    input  wire desc_rd_req_sglist_start,
    input  wire desc_rd_req_sgdma_start,
    
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

    if (PCIE_TAG_COUNT < 1 || PCIE_TAG_COUNT > 256) begin
        $error("Error: PCIe tag count must be between 1 and 256 (instance %m)");
        $finish;
    end
end
integer i;
localparam TLP_DATA_BYTES = TLP_DATA_WIDTH / 8;
localparam SGLIST_FIFO_DEPTH = 9;
// SG-list FIFO is asymmetric (TLP_DATA_WIDTH write / 128b read), dout is 128b:
// entry format: seq[127:96] / length bytes[95:64] / start address[63:0]
localparam SGLIST_RD_WIDTH = 128;
localparam  SGDMA_IDLE   = 5'b00001,
            SGDMA_RDLIST = 5'b00010,
            SGDMA_RDRECV = 5'b00100,
            SGDMA_RDSTART= 5'b01000,
            SGDMA_ENDL   = 5'b10000;

(* MARK_DEBUG="true" *)reg [4:0] sgdma_rd_state_reg, sgdma_rd_state_next;
// set when the SG list has been fully received (tlast beat accepted);
// RDRECV then waits for the desc_rd_req_sgdma_start rising edge
reg sgdma_list_done_reg = 0, sgdma_list_done_next;

reg desc_rd_req_sglist_start_d_reg = 0, desc_rd_req_sglist_start_d_next;
reg desc_rd_req_sgdma_start_reg = 0, desc_rd_req_sgdma_start_next;
reg dma_rd_sglist_fifo_wr_en_reg = 0, dma_rd_sglist_fifo_wr_en_next;
reg [TLP_DATA_WIDTH-1:0] dma_rd_sglist_fifo_wr_data_reg = 0, dma_rd_sglist_fifo_wr_data_next;
reg  dma_rd_sglist_fifo_rd_en_reg = 0, dma_rd_sglist_fifo_rd_en_next;
reg tx_rd_req_irq_reg = 0, tx_rd_req_irq_next;
(* MARK_DEBUG="true" *)reg [31:0] desc_rd_req_sglist_length_reg = 0, desc_rd_req_sglist_length_next;
(* MARK_DEBUG="true" *)reg [PCIE_ADDR_WIDTH-1:0] desc_rd_req_sglist_address_reg = 0, desc_rd_req_sglist_address_next;
(* MARK_DEBUG="true" *)reg     desc_rd_req_sglist_start_reg = 0, desc_rd_req_sglist_start_next;

wire dma_rd_sglist_fifo_empty;
wire dma_rd_sglist_fifo_full,dma_rd_sglist_fifo_alfull;
// FIFO read-side width is READ_WIDTH_PARAM=128b; a wider declaration would
// leave the upper bits undriven (z) and the != 0 compare would evaluate to x
wire [SGLIST_RD_WIDTH-1:0] dma_rd_sglist_fifo_rd_data;

wire [TLP_DATA_WIDTH-1:0] cpld_rx_axis_tdata;
wire [TLP_DATA_WIDTH/8-1:0] cpld_rx_axis_tkeep;
wire cpld_rx_axis_tvalid;
wire cpld_rx_axis_tlast;
reg cpld_rx_axis_tready = 0;

assign tx_rd_req_irq = tx_rd_req_irq_reg;
assign m_axis_tlp_tdata   = (sgdma_rd_state_reg == SGDMA_ENDL) ? cpld_rx_axis_tdata : 'b0 ;
assign m_axis_tlp_tkeep   = (sgdma_rd_state_reg == SGDMA_ENDL) ? cpld_rx_axis_tkeep : 'b0 ;
assign m_axis_tlp_tvalid  = (sgdma_rd_state_reg == SGDMA_ENDL) ? cpld_rx_axis_tvalid: 'b0 ;
assign m_axis_tlp_tlast   = (sgdma_rd_state_reg == SGDMA_ENDL) ? cpld_rx_axis_tlast : 1'b0;

dma_if_pcie_axis_rd_v1 #(
    .TLP_DATA_WIDTH   	(TLP_DATA_WIDTH  ),
    .TLP_HDR_WIDTH    	(TLP_HDR_WIDTH   ),
    .TLP_SEG_COUNT    	(TLP_SEG_COUNT   ),
    .TX_SEQ_NUM_WIDTH 	(TX_SEQ_NUM_WIDTH),
    .PCIE_ADDR_WIDTH  	(PCIE_ADDR_WIDTH ),
    .PCIE_TAG_COUNT   	(PCIE_TAG_COUNT  ),
    .OP_TABLE_SIZE    	(PCIE_TAG_COUNT  )
)sgdma_list_rd(
    .clk  (clk),
    .rst  (rst),
    .tx_rd_req_tlp_hdr    (tx_rd_req_tlp_hdr  ),
    .tx_rd_req_tlp_seq    (tx_rd_req_tlp_seq  ),
    .tx_rd_req_tlp_valid  (tx_rd_req_tlp_valid),
    .tx_rd_req_tlp_sop    (tx_rd_req_tlp_sop  ),
    .tx_rd_req_tlp_eop    (tx_rd_req_tlp_eop  ),
    .tx_rd_req_tlp_ready  (tx_rd_req_tlp_ready),

    .rx_cpl_tlp_data     (rx_cpl_tlp_data   ),
    .rx_cpl_tlp_hdr      (rx_cpl_tlp_hdr    ),
    .rx_cpl_tlp_error    (rx_cpl_tlp_error  ),
    .rx_cpl_tlp_valid    (rx_cpl_tlp_valid  ),
    .rx_cpl_tlp_sop      (rx_cpl_tlp_sop    ),
    .rx_cpl_tlp_eop      (rx_cpl_tlp_eop    ),
    .rx_cpl_tlp_ready    (rx_cpl_tlp_ready  ),

    .ext_tag_enable    (),
    .tx_rd_req_irq     (),
    .rcb_128b          (),
    .requester_id      (requester_id   ),
    .Max_read_PayloadSize (max_read_payloadSize    ),

    .desc_tx_rd_req_length (desc_rd_req_sglist_length_reg),
    .desc_tx_rd_req_address(desc_rd_req_sglist_address_reg),
    .desc_tx_rd_req_start  (desc_rd_req_sglist_start_reg),

    .m_axis_tlp_tdata  (cpld_rx_axis_tdata),
    .m_axis_tlp_tkeep  (cpld_rx_axis_tkeep),
    .m_axis_tlp_tvalid (cpld_rx_axis_tvalid),
    .m_axis_tlp_tlast  (cpld_rx_axis_tlast),
    .m_axis_tlp_tready (cpld_rx_axis_tready)
);



xpm_sync_fifo #(
    .WIDTH             	(TLP_DATA_WIDTH   ),
    .DEPTH             	(SGLIST_FIFO_DEPTH),
    .FIFO_TYPE         	("fwft"    ),
    .Asymmetric_Mode    (1),
    .WRITE_WIDTH_PARAM  (TLP_DATA_WIDTH),
    .READ_WIDTH_PARAM   (128),
    .FIFO_MEMORY       	("auto"   ),
    .USER_ADV_FEATURES 	("1f1f"   )
)dma_rd_sglist_fifo(
    .clk           	(clk),
    .rst           	(rst),
    .wr_en         	(dma_rd_sglist_fifo_wr_en_reg),
    .rd_en         	(dma_rd_sglist_fifo_rd_en_reg),
    .data          	(dma_rd_sglist_fifo_wr_data_reg),
    .dout          	(dma_rd_sglist_fifo_rd_data),
    .full          	(dma_rd_sglist_fifo_full),
    .empty         	(dma_rd_sglist_fifo_empty),
    .almost_empty  	(),
    .almost_full   	(dma_rd_sglist_fifo_alfull),
    .rd_data_count 	(),
    .wr_data_count 	()
);


always @(*) begin
    sgdma_rd_state_next = sgdma_rd_state_reg;

    desc_rd_req_sglist_length_next = desc_rd_req_sglist_length_reg;
    desc_rd_req_sglist_address_next = desc_rd_req_sglist_address_reg;
    desc_rd_req_sglist_start_next = desc_rd_req_sglist_start_reg;
    sgdma_list_done_next = sgdma_list_done_reg;

    // wr_en must default to 0 (pulse); holding the old value would write the
    // same beat into the FIFO every cycle after RDRECV exits
    dma_rd_sglist_fifo_wr_en_next = 1'b0;
    dma_rd_sglist_fifo_wr_data_next = dma_rd_sglist_fifo_wr_data_reg;

    desc_rd_req_sgdma_start_next = desc_rd_req_sgdma_start;

    dma_rd_sglist_fifo_rd_en_next = 'b0;
    tx_rd_req_irq_next = 1'b0;

    cpld_rx_axis_tready = 'b0;
    desc_rd_req_sglist_start_d_next = desc_rd_req_sglist_start;
    case (sgdma_rd_state_reg)
        SGDMA_IDLE : begin
            if(desc_rd_req_sglist_start & (~desc_rd_req_sglist_start_d_reg))begin
                sgdma_rd_state_next = SGDMA_RDLIST;
            end
            else begin
                sgdma_rd_state_next = SGDMA_IDLE;
            end
        end

        SGDMA_RDLIST:begin
            if (desc_rd_req_sglist_start_reg) begin
                desc_rd_req_sglist_start_next = 1'b0;
                sgdma_rd_state_next = SGDMA_RDRECV;
            end
            else begin
                desc_rd_req_sglist_length_next = desc_rd_req_sglist_length;
                desc_rd_req_sglist_address_next = desc_rd_req_sglist_address;
                desc_rd_req_sglist_start_next = 1'b1;
            end
        end

        SGDMA_RDRECV:begin
            cpld_rx_axis_tready = ~dma_rd_sglist_fifo_alfull;
            dma_rd_sglist_fifo_wr_en_next = cpld_rx_axis_tvalid & cpld_rx_axis_tready;
            for(i = 0; i < TLP_DATA_BYTES; i = i + 1)begin
                if(cpld_rx_axis_tkeep[i])begin
                    dma_rd_sglist_fifo_wr_data_next[i*8+:8] = cpld_rx_axis_tdata[i*8+:8];
                end
                else begin
                    dma_rd_sglist_fifo_wr_data_next[i*8+:8] = 0;
                end
            end
            tx_rd_req_irq_next = cpld_rx_axis_tvalid & cpld_rx_axis_tready & cpld_rx_axis_tlast;

            // tlast beat accepted: the SG list has been fully received
            if (cpld_rx_axis_tvalid & cpld_rx_axis_tready & cpld_rx_axis_tlast) begin
                sgdma_list_done_next = 1'b1;
            end

            // list complete: wait for the read-DMA start rising edge, which may
            // arrive several cycles after the irq; the simultaneous case (edge
            // in the tlast beat itself) is also accepted
            if (desc_rd_req_sgdma_start & ~desc_rd_req_sgdma_start_reg) begin
                sgdma_list_done_next = 1'b0;
                sgdma_rd_state_next = SGDMA_RDSTART;
            end
        end

        SGDMA_RDSTART:begin
            if (dma_rd_sglist_fifo_rd_en_reg) begin
                desc_rd_req_sglist_start_next = 1'b0;
                sgdma_rd_state_next = SGDMA_ENDL;
            end
            else begin
                if (~dma_rd_sglist_fifo_empty) begin
                    dma_rd_sglist_fifo_rd_en_next = 1'b1;
                    desc_rd_req_sglist_length_next = dma_rd_sglist_fifo_rd_data[95:64];
                    desc_rd_req_sglist_address_next = dma_rd_sglist_fifo_rd_data[63:0];
                    if (dma_rd_sglist_fifo_rd_data != {SGLIST_RD_WIDTH{1'b0}}) begin
                        desc_rd_req_sglist_start_next = 1'b1;
                    end
                    else begin
                        desc_rd_req_sglist_start_next = 1'b0;
                    end
                end
                // right after RDRECV the last list beat may not have landed in
                // the FIFO yet (empty lags one cycle); hold until it completes
                else if (dma_rd_sglist_fifo_wr_en_reg) begin
                    sgdma_rd_state_next = SGDMA_RDSTART;
                end
                else begin
                    sgdma_rd_state_next = SGDMA_IDLE;
                end
            end
        end

        SGDMA_ENDL : begin
            cpld_rx_axis_tready = m_axis_tlp_tready;
            if (~|desc_rd_req_sglist_length_reg) begin
                sgdma_rd_state_next = SGDMA_RDSTART;
            end
            else begin
                if (cpld_rx_axis_tvalid & cpld_rx_axis_tready & cpld_rx_axis_tlast) begin
                    sgdma_rd_state_next = SGDMA_RDSTART;
                end
            end
        end
        default: begin
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        sgdma_rd_state_reg <= SGDMA_IDLE;
        sgdma_list_done_reg <= 1'b0;
        desc_rd_req_sglist_start_d_reg <= 'b0;
        desc_rd_req_sglist_length_reg <= 'b0;
        desc_rd_req_sglist_address_reg <= 'b0;
        desc_rd_req_sglist_start_reg <= 'b0;
        dma_rd_sglist_fifo_wr_en_reg <= 1'b0;
        dma_rd_sglist_fifo_wr_data_reg <= 'b0;
        desc_rd_req_sgdma_start_reg <= 'b0;
        dma_rd_sglist_fifo_rd_en_reg <= 1'b0;
        tx_rd_req_irq_reg <= 1'b0;
    end
    else begin
        sgdma_rd_state_reg <= sgdma_rd_state_next;
        sgdma_list_done_reg <= sgdma_list_done_next;
        desc_rd_req_sglist_start_d_reg <= desc_rd_req_sglist_start_d_next;
        desc_rd_req_sglist_length_reg <= desc_rd_req_sglist_length_next;
        desc_rd_req_sglist_address_reg <= desc_rd_req_sglist_address_next;
        desc_rd_req_sglist_start_reg <= desc_rd_req_sglist_start_next;
        dma_rd_sglist_fifo_wr_en_reg <= dma_rd_sglist_fifo_wr_en_next;
        dma_rd_sglist_fifo_wr_data_reg <= dma_rd_sglist_fifo_wr_data_next;
        desc_rd_req_sgdma_start_reg <= desc_rd_req_sgdma_start_next;
        dma_rd_sglist_fifo_rd_en_reg <= dma_rd_sglist_fifo_rd_en_next;
        tx_rd_req_irq_reg <= tx_rd_req_irq_next;
    end
end

endmodule

`resetall