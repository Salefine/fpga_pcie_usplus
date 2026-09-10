/****************************************************************************
 * @file    dma_if_pcie_axis_rd.v
 * @brief  
 * @author  Salefine (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2026-03-18
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    Salefine      |                        |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2026 welie
 * ***************************************************************************/


/******************************************************************************
 *                 Requester Request Descriptor Format (MRd, 4DW)
 *
 * 63                                                                   32 31                                                                   0
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |                               DW+1                                  | |                               DW+0                                  |
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |-------+7------| |-------+6------| |-------+5------| |-------+4------| |-------+3------| |-------+2------| |-------+1------| |-------+0------|
 * |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0|
 * |             Requester ID        | |  Tag          | LastBE | FirstBE|  R|AT|attr|EP|TD|TH|R|TC|R|Fmt/Type/Length|
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * 127                                                                  96 95                                                                   64
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |                               DW+3                                  | |                               DW+2                                  |
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |------ +15-----| |------ +14-----| |------ +13-----| |------ +12-----| |------ +11-----| |------ +10-----| |-------+9------| |-------+8------|
 * |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0|
 * |                                                                 Address[63:2]                                                           | PH |
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 *
 * Example (MRd, 512B, Tag=0x2A, Addr=0x00000000_FCF00000):
 *   DW0: 0x20000080   // FMT=001, TYPE=00000, LEN=0x080 (128DW)
 *   DW1: 0x00002AFF   // ReqID=0x0000, Tag=0x2A, LastBE=F, FirstBE=F
 *   DW2: 0x00000000
 *   DW3: 0xFCF00000
 *   Header[127:0] = 0x20000080_00002AFF_00000000_FCF00000
 *
 * CPLD header
 * +----------------++----------------++----------------++----------------+
 * | 7 6 5 4 3 2 1 0|| 7 6 5 4 3 2 1 0|| 7 6 5 4 3 2 1 0|| 7 6 5 4 3 2 1 0|
 * | |FMT| |  type  || R   TC  R     
 ******************************************************************************/   
 `resetall
 `timescale 1ns/1ps
 `default_nettype none
module dma_if_pcie_axis_rd_v1#(
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
) (
    input   wire    clk ,
    input   wire    rst ,
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
    input  wire [15:0]           requester_id  ,
    input  wire [2 : 0]          Max_read_PayloadSize     ,
    output wire                  tx_rd_req_irq,

    /*
     * AXI4-Stream input
     */
    input  wire [31 : 0]         desc_tx_rd_req_length         ,//bytes
    input  wire [PCIE_ADDR_WIDTH-1 : 0] desc_tx_rd_req_address        ,
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

localparam TLP_DATA_WIDTH_BYTES = TLP_DATA_WIDTH/8;
localparam TLP_DATA_WIDTH_DWORDS = TLP_DATA_WIDTH/32;
localparam OFFSET_WIDTH = $clog2(TLP_DATA_WIDTH_BYTES);
localparam OP_TAG_WIDTH = $clog2(OP_TABLE_SIZE);
localparam PCIE_TAG_WIDTH = $clog2(PCIE_TAG_COUNT);
localparam OP_TABLE_READ_COUNT_WIDTH = PCIE_TAG_WIDTH+1;
localparam INIT_COUNT_WIDTH = PCIE_TAG_WIDTH > OP_TAG_WIDTH ? PCIE_TAG_WIDTH : OP_TAG_WIDTH;
localparam CPLD_TOTAL_WIDTH = TLP_DATA_WIDTH + TLP_DATA_WIDTH/8 + 2;
localparam CPLD_FIFO_DEPTH = 4;
localparam OUTPUT_FIFO_ADDR_WIDTH = 6;

localparam [2:0]
    TLP_FMT_3DW = 3'b000,
    TLP_FMT_4DW = 3'b001,
    TLP_FMT_3DW_DATA = 3'b010,
    TLP_FMT_4DW_DATA = 3'b011,
    TLP_FMT_PREFIX = 3'b100;

localparam [2:0]
    CPL_STATUS_SC  = 3'b000, // successful completion
    CPL_STATUS_UR  = 3'b001, // unsupported request
    CPL_STATUS_CRS = 3'b010, // configuration request retry status
    CPL_STATUS_CA  = 3'b100; // completer abort

localparam [3:0]
    PCIE_ERROR_NONE = 4'd0,
    PCIE_ERROR_POISONED = 4'd1,
    PCIE_ERROR_BAD_STATUS = 4'd2,
    PCIE_ERROR_MISMATCH = 4'd3,
    PCIE_ERROR_INVALID_LEN = 4'd4,
    PCIE_ERROR_INVALID_ADDR = 4'd5,
    PCIE_ERROR_INVALID_TAG = 4'd6,
    PCIE_ERROR_FLR = 4'd8,
    PCIE_ERROR_TIMEOUT = 4'd15;

localparam [0:0]
    REQ_STATE_IDLE = 1'd0,
    REQ_STATE_START = 1'd1;

localparam [0:0]
    RECV_STATE_IDLE = 1'd0,
    RECV_STATE_START = 1'd1;

localparam [0:0]
    TR_STATE_IDLE = 1'd0,
    TR_STATE_START = 1'd1;

integer i;

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

reg [0:0] req_state_reg  = REQ_STATE_IDLE, req_state_next;
reg [0:0] recv_state_reg = RECV_STATE_IDLE, recv_state_next;

reg [PCIE_ADDR_WIDTH-1 : 0] desc_tx_rd_req_address_reg = 0, desc_tx_rd_req_address_next;
reg [31 : 0]         desc_tx_rd_req_length_reg = 0, desc_tx_rd_req_length_next;
reg desc_tx_rd_req_start_reg = 0, desc_tx_rd_req_start_next;
reg [31 : 0] tr_cycle_reg = 0, tr_cycle_next;
reg [31:0] op_cycle_reg = 0, op_cycle_next;
reg [3 :0] byte_cycle_reg =0, byte_cycle_next;
reg [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]    tx_rd_req_tlp_hdr_reg = 0 , tx_rd_req_tlp_hdr_next;
reg [TLP_SEG_COUNT-1:0]                  tx_rd_req_tlp_valid_reg=0 , tx_rd_req_tlp_valid_next;
reg [TLP_SEG_COUNT-1:0]                  tx_rd_req_tlp_sop_reg = 0 , tx_rd_req_tlp_sop_next;
reg [TLP_SEG_COUNT-1:0]                  tx_rd_req_tlp_eop_reg = 0 , tx_rd_req_tlp_eop_next;
reg [PCIE_ADDR_WIDTH - 1 : 0] tlp_address_reg = 0, tlp_address_next;
reg [9:0] tag_idx_length_reg = 0 , tag_idx_length_next; 
reg tx_rd_req_irq_reg = 0, tx_rd_req_irq_next;
//-----------------Salefine modify @ 2026-6-8 start
reg [3:0] req_first_be ,req_last_be;
//-----------------Salefine modify @ 2026-6-8 end

reg tag_valid_reg = 0, tag_valid_next;
reg [OP_TAG_WIDTH-1:0] op_tag_fifo_wr_tag = 0;
reg op_tag_fifo_we = 0;
reg op_tag_fifo_rd = 0; reg [PCIE_TAG_WIDTH - 1 : 0] op_tag_fifo_rdptr = 0;
reg [OP_TAG_WIDTH+3:0] tag_table_info[0 : PCIE_TAG_COUNT - 1];
// reg [OP_TAG_WIDTH - 1 : 0] op_tag_wr_ptr = 0 , op_tag_rd_ptr = 0;

reg [2:0] rx_cpl_tlp_hdr_fmt;
reg [4:0] rx_cpl_tlp_hdr_type;
reg [2:0] rx_cpl_tlp_hdr_tc;
reg rx_cpl_tlp_hdr_ln;
reg rx_cpl_tlp_hdr_th;
reg rx_cpl_tlp_hdr_td;
reg rx_cpl_tlp_hdr_ep;
reg [2:0] rx_cpl_tlp_hdr_attr;
reg [1:0] rx_cpl_tlp_hdr_at;
reg [10:0] rx_cpl_tlp_hdr_length;
reg [15:0] rx_cpl_tlp_hdr_completer_id;
reg [2:0] rx_cpl_tlp_hdr_cpl_status;
reg rx_cpl_tlp_hdr_bcm;
reg [12:0] rx_cpl_tlp_hdr_byte_count;
reg [15:0] rx_cpl_tlp_hdr_requester_id;
reg [9:0] rx_cpl_tlp_hdr_tag;
reg [6:0] rx_cpl_tlp_hdr_lower_addr;

wire [OP_TAG_WIDTH - 1 : 0] op_tag_fifo_rd_tag;
wire op_tag_fifo_full; 
wire [15:0] mrrs_shift = 16'h7 + Max_read_PayloadSize;

assign tx_rd_req_tlp_hdr = tx_rd_req_tlp_hdr_reg;
assign tx_rd_req_tlp_seq = 0;
assign tx_rd_req_tlp_valid = tx_rd_req_tlp_valid_reg;
assign tx_rd_req_tlp_sop = tx_rd_req_tlp_sop_reg;
assign tx_rd_req_tlp_eop = tx_rd_req_tlp_eop_reg;

//
reg[PCIE_TAG_COUNT-1 : 0] cpld_data_fifo_wr_en_reg = 0, cpld_data_fifo_wr_en_next;
reg[PCIE_TAG_COUNT-1 : 0] cpld_data_fifo_rd_en_reg = 0, cpld_data_fifo_rd_en_next;
reg[TLP_DATA_WIDTH - 1 :0 ] cpld_data_fifo_din_reg[0:PCIE_TAG_COUNT-1];
reg[TLP_DATA_WIDTH - 1 :0 ] cpld_data_fifo_din_next[0:PCIE_TAG_COUNT-1];
reg rx_cpl_tlp_ready_reg = 0, rx_cpl_tlp_ready_next;
reg[31 :0] cpl_tr_cycle_reg = 0, cpl_tr_cycle_next;
reg[31 :0] cpl_op_cycle_reg = 0, cpl_op_cycle_next;
reg[31 :0] rx_last_cyclr_reg = 0, rx_last_cyclr_next;
reg[7:0]   cycle_reg = 0, cycle_next;

wire[PCIE_TAG_COUNT-1 : 0] cpld_data_fifo_empty;
wire[TLP_DATA_WIDTH - 1 :0 ] cpld_data_fifo_dout[0:PCIE_TAG_COUNT-1];
//wire [CPLD_FIFO_DEPTH :0 ] cpld_data_fifo_wr_data_count[0:PCIE_TAG_COUNT-1];

wire [TLP_DATA_WIDTH_BYTES-1:0] axis_tkeep_init = (desc_tx_rd_req_length_reg[OFFSET_WIDTH-1:0] == 'b0) ? {TLP_DATA_WIDTH_BYTES{1'b1}} :
                                                 (1 << desc_tx_rd_req_length_reg[OFFSET_WIDTH-1:0]) - 1'b1;

assign rx_cpl_tlp_ready = rx_cpl_tlp_ready_reg;
assign tx_rd_req_irq = tx_rd_req_irq_reg;

/*
 * 1. generate mrd packet, tag id from fifo, if fifo is full, next do not alloct tag.
 */

always @(*)begin

    req_state_next = req_state_reg;
    desc_tx_rd_req_address_next = desc_tx_rd_req_address_reg;
    desc_tx_rd_req_length_next = desc_tx_rd_req_length_reg;
    desc_tx_rd_req_start_next = desc_tx_rd_req_start_reg;

    tr_cycle_next = tr_cycle_reg;
    op_cycle_next = op_cycle_reg;
    byte_cycle_next = byte_cycle_reg;

    tag_valid_next = tag_valid_reg;
    tag_idx_length_next = tag_idx_length_reg;

    tlp_address_next = tlp_address_reg;

    tx_rd_req_tlp_valid_next = 0;
    tx_rd_req_tlp_sop_next = 0;
    tx_rd_req_tlp_eop_next = 0;
    tx_rd_req_tlp_hdr_next = 0;

    case (req_state_reg)
        REQ_STATE_IDLE : begin 
            op_cycle_next = 0;
            tr_cycle_next = 0;
            byte_cycle_next = 0;
            tag_valid_next = 0;
            desc_tx_rd_req_start_next = desc_tx_rd_req_start;
            if (desc_tx_rd_req_start && (~desc_tx_rd_req_start_reg)) begin
                desc_tx_rd_req_length_next= desc_tx_rd_req_length;
                desc_tx_rd_req_address_next= desc_tx_rd_req_address;
                tr_cycle_next =((desc_tx_rd_req_length_next >> mrrs_shift) +|(desc_tx_rd_req_length_next & ((32'd1 << mrrs_shift) - 1)));
                tlp_address_next = desc_tx_rd_req_address_next;
                req_state_next = REQ_STATE_START;
            end
        end

        REQ_STATE_START : begin

            tag_valid_next = 1;
            desc_tx_rd_req_start_next = 0;

            if(tx_rd_req_tlp_ready && tx_rd_req_tlp_valid)begin
                op_cycle_next = op_cycle_reg + 1;
                tlp_address_next = tlp_address_reg + (32'd128 << Max_read_PayloadSize);
                tx_rd_req_tlp_valid_next = 0;
                tx_rd_req_tlp_eop_next = 0;
                tx_rd_req_tlp_sop_next = 0;
                tx_rd_req_tlp_hdr_next = 0;
                tag_valid_next = 0;
                if (op_cycle_next == tr_cycle_reg) begin
                    req_state_next = REQ_STATE_IDLE;
                end
            end
            else if (op_tag_fifo_we) begin
                tx_rd_req_tlp_valid_next = 1;
                tx_rd_req_tlp_sop_next   = 1;
                tx_rd_req_tlp_eop_next   = 1;
                tag_valid_next = 0;
                if (op_cycle_next == tr_cycle_reg - 1) begin
                    //-----------------zzhi modify @ 2026-6-26 start
                    // byte_cycle_next = desc_tx_rd_req_length_reg[8:OFFSET_WIDTH]  + (desc_tx_rd_req_length_reg[OFFSET_WIDTH-1:0] != 0);
                    // if (byte_cycle_next == 0) begin
                    //     byte_cycle_next = (32'd128 << Max_read_PayloadSize) >> OFFSET_WIDTH;
                    // end
                    // tag_idx_length_next = desc_tx_rd_req_length_reg[8:2]+ (desc_tx_rd_req_length_reg[1:0] != 0);  
                    // if (tag_idx_length_next == 0) begin
                    //     tag_idx_length_next = (TLP_DATA_WIDTH_BYTES >> 2) << (3'h5 - Max_read_PayloadSize);
                    // end  
                    //-----------------zzhi modify @ 2026-6-26 end

                    //-----------------zzhi modify @ 2026-6-26 start
                    if (Max_read_PayloadSize == 3'b000) begin
                        tag_idx_length_next = ~|desc_tx_rd_req_length_reg[6:0] ? 10'd32 : desc_tx_rd_req_length_reg[6:2] + |desc_tx_rd_req_length_reg[1:0];
                        byte_cycle_next = desc_tx_rd_req_length_reg[OFFSET_WIDTH:OFFSET_WIDTH]  + (desc_tx_rd_req_length_reg[OFFSET_WIDTH-1:0] != 0);
                    end         
                    else if (Max_read_PayloadSize == 3'b001) begin
                        tag_idx_length_next = ~|desc_tx_rd_req_length_reg[7:0] ? 10'd64 : desc_tx_rd_req_length_reg[7:2] + |desc_tx_rd_req_length_reg[1:0];
                        byte_cycle_next = desc_tx_rd_req_length_reg[7:OFFSET_WIDTH]  + (desc_tx_rd_req_length_reg[OFFSET_WIDTH-1:0] != 0);
                    end     
                    else if (Max_read_PayloadSize == 3'b010) begin
                        tag_idx_length_next = ~|desc_tx_rd_req_length_reg[8:0] ? 10'd128 : desc_tx_rd_req_length_reg[8:2] + |desc_tx_rd_req_length_reg[1:0];
                        byte_cycle_next = desc_tx_rd_req_length_reg[8:OFFSET_WIDTH]  + (desc_tx_rd_req_length_reg[OFFSET_WIDTH-1:0] != 0);
                    end         
                    else if (Max_read_PayloadSize == 3'b011) begin
                        tag_idx_length_next = ~|desc_tx_rd_req_length_reg[9:0] ? 10'd256 : desc_tx_rd_req_length_reg[9:2] + |desc_tx_rd_req_length_reg[1:0];
                        byte_cycle_next = desc_tx_rd_req_length_reg[9:OFFSET_WIDTH]  + (desc_tx_rd_req_length_reg[OFFSET_WIDTH-1:0] != 0);
                    end   

                    if (byte_cycle_next == 0) begin
                        byte_cycle_next = (32'd128 << Max_read_PayloadSize) >> OFFSET_WIDTH;
                    end

                    //-----------------zzhi modify @ 2026-6-26 end      
                end
                else begin
                    byte_cycle_next = (32'd128 << Max_read_PayloadSize) >> OFFSET_WIDTH;
                    tag_idx_length_next = (TLP_DATA_WIDTH_BYTES >> 2) << (3'h5 - Max_read_PayloadSize);
                end

                req_first_be = 4'b1111 << desc_tx_rd_req_address_reg[1:0];
                req_last_be =  4'b1111 >> (3 - ((desc_tx_rd_req_address_reg[1:0] + (op_cycle_reg == (tr_cycle_reg-1) ? desc_tx_rd_req_length_reg[1:0] : 0) - 1) & 3));

                tx_rd_req_tlp_hdr_next[127:125] = TLP_FMT_4DW     ; //fmt 
                tx_rd_req_tlp_hdr_next[124:120] = 5'b00000    ; //type
                tx_rd_req_tlp_hdr_next[119]     = 1'b0            ; //t9
                tx_rd_req_tlp_hdr_next[118:116] = 3'b0            ; //tc
                tx_rd_req_tlp_hdr_next[115]     = 1'b0            ; //t8
                tx_rd_req_tlp_hdr_next[114]     = 1'b0            ; //a2
                tx_rd_req_tlp_hdr_next[113]     = 1'b0            ; //r
                tx_rd_req_tlp_hdr_next[112]     = 1'b0            ; //th
                tx_rd_req_tlp_hdr_next[111]     = 1'b0            ; //td
                tx_rd_req_tlp_hdr_next[110]     = 1'b0            ; //ep
                tx_rd_req_tlp_hdr_next[109:108] = 2'b0            ; //attr
                tx_rd_req_tlp_hdr_next[107:106] = 2'b0            ; //at
                tx_rd_req_tlp_hdr_next[105:96]  = tag_idx_length_next; //length
                tx_rd_req_tlp_hdr_next[95:80]   = requester_id    ; //request id
                tx_rd_req_tlp_hdr_next[79:72]   = op_tag_fifo_wr_tag   ; //tag
                //-----------------zzhi modify @ 2026-6-8 start
                tx_rd_req_tlp_hdr_next[71:68]   = (tag_idx_length_next == 1) ? 4'b0000 : req_last_be; // 
                tx_rd_req_tlp_hdr_next[67:64]   = (tag_idx_length_next == 1) ? req_first_be & req_last_be : req_first_be; //
                //-----------------zzhi modify @ 2026-6-8 end
                tx_rd_req_tlp_hdr_next[63:2]    = tlp_address_reg[63:2]; //address
                tx_rd_req_tlp_hdr_next[1:0]     = 2'b00;

            end
        end
        default: begin end
    endcase
end

always @(posedge clk)begin
    if (rst) begin
        req_state_reg <= REQ_STATE_IDLE;
        desc_tx_rd_req_address_reg <= 0;
        desc_tx_rd_req_length_reg <= 0;
        desc_tx_rd_req_start_reg <= 0;
        tx_rd_req_tlp_hdr_reg <= 0;
        op_cycle_reg <= 0;
        tr_cycle_reg <= 0;
        tag_idx_length_reg <= 0;
        tag_valid_reg <= 0;
        tx_rd_req_tlp_hdr_reg <= 0;
        tx_rd_req_tlp_valid_reg <= 0;
        tx_rd_req_tlp_sop_reg <= 0;
        tx_rd_req_tlp_eop_reg <= 0;    
        tlp_address_reg <= 0;
        byte_cycle_reg <= 0;
        for (i = 0; i < PCIE_TAG_COUNT; i = i + 1) begin
            tag_table_info[i] <= 0;
        end
    end
    else begin
        req_state_reg <= req_state_next;
        desc_tx_rd_req_address_reg <= desc_tx_rd_req_address_next;
        desc_tx_rd_req_length_reg <= desc_tx_rd_req_length_next;
        desc_tx_rd_req_start_reg <= desc_tx_rd_req_start_next;
        tx_rd_req_tlp_hdr_reg <= tx_rd_req_tlp_hdr_next;
        op_cycle_reg <= op_cycle_next;
        tr_cycle_reg <= tr_cycle_next;
        tag_valid_reg <= tag_valid_next;
        tag_idx_length_reg <= tag_idx_length_next;
        tx_rd_req_tlp_hdr_reg <= tx_rd_req_tlp_hdr_next;
        tx_rd_req_tlp_valid_reg <= tx_rd_req_tlp_valid_next;
        tx_rd_req_tlp_sop_reg <= tx_rd_req_tlp_sop_next;
        tx_rd_req_tlp_eop_reg <= tx_rd_req_tlp_eop_next;
        tlp_address_reg <= tlp_address_next;
        byte_cycle_reg <= byte_cycle_next;

        if (op_tag_fifo_we) begin
            tag_table_info[op_tag_fifo_wr_tag][PCIE_TAG_WIDTH-1:0] <= op_tag_fifo_wr_tag;
            tag_table_info[op_tag_fifo_wr_tag][PCIE_TAG_WIDTH+3:PCIE_TAG_WIDTH] <= byte_cycle_next;
        end

        if(op_tag_fifo_rd)begin
            tag_table_info[op_tag_fifo_rdptr] <= 0;
        end
    end
end

always @(posedge clk)begin    
    if(rst)begin
        op_tag_fifo_we <= 0;
    end
    else if(op_tag_fifo_we)begin
        op_tag_fifo_we <= 0;
    end
    else if((tag_valid_next) && !op_tag_fifo_full)begin
        op_tag_fifo_we <= 1;
    end
end

always @(posedge clk)begin    
    if(rst)begin
        op_tag_fifo_wr_tag <= 0;
    end
    else if(req_state_reg == REQ_STATE_IDLE)begin
        op_tag_fifo_wr_tag <= 0;
    end
    else if(op_tag_fifo_we)begin
        op_tag_fifo_wr_tag <= op_tag_fifo_wr_tag + 1;
    end
end


always @(posedge clk) begin
    if (rst) begin
        op_tag_fifo_rd <= 0;
        op_tag_fifo_rdptr <= 0;
    end
    else if((req_state_reg == REQ_STATE_IDLE) && (req_state_reg != req_state_next))begin
        op_tag_fifo_rdptr <= 0;
    end
    else if(op_tag_fifo_rd)begin
        op_tag_fifo_rd <= 0;
        op_tag_fifo_rdptr <= op_tag_fifo_rdptr + 1'b1;
    end
    else if(cpld_data_fifo_rd_en_reg[op_tag_fifo_rdptr] && (cycle_next == tag_table_info[op_tag_fifo_rdptr][PCIE_TAG_WIDTH+3:PCIE_TAG_WIDTH]))begin
        op_tag_fifo_rd <= 1;
        op_tag_fifo_rdptr <= op_tag_fifo_rdptr;
    end
end

xpm_sync_fifo #(
    .WIDTH             	(PCIE_TAG_WIDTH     ),
    .DEPTH             	(PCIE_TAG_WIDTH     ),
    .FIFO_TYPE         	("std"    ),
    .FIFO_MEMORY       	("auto"   ),
    .USER_ADV_FEATURES 	("1f1f"   )
)op_tag_fifo(
    .clk           	(clk),
    .rst           	(rst),
    .wr_en         	(op_tag_fifo_we),
    .rd_en         	(op_tag_fifo_rd),
    .data          	(op_tag_fifo_wr_tag),
    .dout          	(op_tag_fifo_rd_tag),
    .full          	(op_tag_fifo_full),
    .empty         	(),
    .almost_empty  	(),
    .almost_full   	(),
    .rd_data_count 	(),
    .wr_data_count 	()
);

/*
 * 2. Cache cpld data to 32 fifo and ananlysis cpld hdr
 */

always @(*) begin
    // TLP header parsing
    // DW 0
    rx_cpl_tlp_hdr_fmt = rx_cpl_tlp_hdr[127:125]; // fmt
    rx_cpl_tlp_hdr_type = rx_cpl_tlp_hdr[124:120]; // type
    rx_cpl_tlp_hdr_tag[9] = rx_cpl_tlp_hdr[119]; // T9
    rx_cpl_tlp_hdr_tc = rx_cpl_tlp_hdr[118:116]; // TC
    rx_cpl_tlp_hdr_tag[8] = rx_cpl_tlp_hdr[115]; // T8
    rx_cpl_tlp_hdr_attr[2] = rx_cpl_tlp_hdr[114]; // attr
    rx_cpl_tlp_hdr_ln = rx_cpl_tlp_hdr[113]; // LN
    rx_cpl_tlp_hdr_th = rx_cpl_tlp_hdr[112]; // TH
    rx_cpl_tlp_hdr_td = rx_cpl_tlp_hdr[111]; // TD
    rx_cpl_tlp_hdr_ep = rx_cpl_tlp_hdr[110]; // EP
    rx_cpl_tlp_hdr_attr[1:0] = rx_cpl_tlp_hdr[109:108]; // attr
    rx_cpl_tlp_hdr_at = rx_cpl_tlp_hdr[107:106]; // AT
    rx_cpl_tlp_hdr_length = {rx_cpl_tlp_hdr[105:96] == 0, rx_cpl_tlp_hdr[105:96]}; // length
    // DW 1
    rx_cpl_tlp_hdr_completer_id = rx_cpl_tlp_hdr[95:80]; // completer ID
    rx_cpl_tlp_hdr_cpl_status = rx_cpl_tlp_hdr[79:77]; // completion status
    rx_cpl_tlp_hdr_bcm = rx_cpl_tlp_hdr[76]; // BCM
    
    rx_cpl_tlp_hdr_byte_count= {rx_cpl_tlp_hdr[75:64] == 0, rx_cpl_tlp_hdr[75:64]}; // byte count
    // DW 2
    rx_cpl_tlp_hdr_requester_id = rx_cpl_tlp_hdr[63:48]; // requester ID
    rx_cpl_tlp_hdr_tag[7:0] = rx_cpl_tlp_hdr[47:40]; // tag
    rx_cpl_tlp_hdr_lower_addr = rx_cpl_tlp_hdr[38:32]; // lower address

    rx_cpl_tlp_ready_next = rx_cpl_tlp_ready_reg;
    recv_state_next = recv_state_reg;
    cpl_tr_cycle_next = cpl_tr_cycle_reg;
    cpl_op_cycle_next = cpl_op_cycle_reg;
    
    rx_last_cyclr_next = rx_last_cyclr_reg;
    tx_rd_req_irq_next = 0;

    cpld_data_fifo_wr_en_next = 0;
    for(i = 0; i < PCIE_TAG_COUNT; i = i + 1)begin
        cpld_data_fifo_din_next[i] = 0;
    end
    

    case (recv_state_reg)
        RECV_STATE_IDLE: begin
            cpl_tr_cycle_next = 0;
            cpl_op_cycle_next = 0;
            rx_cpl_tlp_ready_next = 0;
            if(desc_tx_rd_req_start_reg && (~desc_tx_rd_req_start_next))begin
                //how many clock cycle are trans need
                cpl_tr_cycle_next = desc_tx_rd_req_length_next[31:OFFSET_WIDTH] + (desc_tx_rd_req_length_next[OFFSET_WIDTH-1:0] == 0 ? 1'b0 : 1'b1) ;
                //last mrd packet how many clock cycles are trans need
                rx_last_cyclr_next = desc_tx_rd_req_length_next[8 : 6] + ((desc_tx_rd_req_length_next[5:0] == 0) ? 1'b0 : 1'b1);

                recv_state_next = RECV_STATE_START;
            end            
        end

        RECV_STATE_START : begin
            rx_cpl_tlp_ready_next = 1;

            //1. Control state machine by estimate op_cycle and tr_cycle
            if(rx_cpl_tlp_valid & rx_cpl_tlp_ready)begin
                cpld_data_fifo_wr_en_next[rx_cpl_tlp_hdr_tag[PCIE_TAG_WIDTH-1:0]] = 1;
                cpld_data_fifo_din_next[rx_cpl_tlp_hdr_tag[PCIE_TAG_WIDTH-1:0]] = rx_cpl_tlp_data;
                cpl_op_cycle_next = cpl_op_cycle_next + 1;
                if (cpl_op_cycle_next == cpl_tr_cycle_next) begin
                    recv_state_next = RECV_STATE_IDLE;
                    tx_rd_req_irq_next = 1;
                end
            end    
        end
        default: begin
            
        end
    endcase
end


genvar t;
generate 
    for(t = 0; t < PCIE_TAG_COUNT; t = t + 1)begin:cpld_fifo
        xpm_sync_fifo #(
            .WIDTH             	(TLP_DATA_WIDTH  ),
            .DEPTH             	(CPLD_FIFO_DEPTH ),
            .FIFO_TYPE         	("fwft"    ),
            .FIFO_MEMORY       	("auto"   ),
            .USER_ADV_FEATURES 	("1f1f"   )
        )cpld_data_fifo(
            .clk           	(clk),
            .rst           	(rst),
            .wr_en         	(cpld_data_fifo_wr_en_reg[t]),
            .rd_en         	(cpld_data_fifo_rd_en_reg[t]),
            .data          	(cpld_data_fifo_din_reg[t]  ),
            .dout          	(cpld_data_fifo_dout[t]     ),
            .full          	(),
            .empty         	(cpld_data_fifo_empty[t]),
            .almost_empty  	(),
            .almost_full   	(),
            .rd_data_count 	(),
            .wr_data_count 	()
        );
    end
endgenerate

always @(posedge clk) begin
    if(rst)begin
        rx_cpl_tlp_ready_reg <= 0;
        recv_state_reg <= RECV_STATE_IDLE;
        cpld_data_fifo_wr_en_reg <= 0;
        for (i = 0; i < PCIE_TAG_COUNT; i = i + 1) begin
            cpld_data_fifo_din_reg[i] <= 0;
        end
        rx_last_cyclr_reg <= 0;
        cpl_tr_cycle_reg <= 0;
        cpl_op_cycle_reg <= 0;
        tx_rd_req_irq_reg <= 0;
    end
    else begin
        rx_cpl_tlp_ready_reg <= rx_cpl_tlp_ready_next;
        cpld_data_fifo_wr_en_reg <= cpld_data_fifo_wr_en_next;
        for (i = 0; i < PCIE_TAG_COUNT; i = i + 1) begin
            cpld_data_fifo_din_reg[i] <= cpld_data_fifo_din_next[i];
        end
        recv_state_reg <= recv_state_next;
        rx_last_cyclr_reg <= rx_last_cyclr_next;
        cpl_tr_cycle_reg <= cpl_tr_cycle_next;
        cpl_op_cycle_reg <= cpl_op_cycle_next;
        tx_rd_req_irq_reg <= tx_rd_req_irq_next;
    end
end

/*
 * 3. read axis from cpld fifo
 */

reg [TLP_DATA_WIDTH - 1 :0]      m_axis_tlp_tdata_init   ;
reg [TLP_DATA_WIDTH / 8 - 1:0]   m_axis_tlp_tkeep_init   ;
reg                              m_axis_tlp_tlast_init   ;
wire m_axis_tlp_tready_init ;
reg m_axis_tlp_tvalid_init;

reg [TLP_DATA_WIDTH - 1 :0]      m_axis_tlp_tdata_reg   ;
reg [TLP_DATA_WIDTH / 8 - 1:0]   m_axis_tlp_tkeep_reg   ;
reg                              m_axis_tlp_tvalid_reg  ;
reg                              m_axis_tlp_tlast_reg   ;


reg [0:0] tr_state_reg  = TR_STATE_IDLE, tr_state_next;
reg [31:0] output_cycle_reg = 0, output_cycle_next;


always @(*) begin
    tr_state_next = tr_state_reg;
    output_cycle_next = output_cycle_reg;
    cycle_next = cycle_reg;

    m_axis_tlp_tdata_init = 0;
    m_axis_tlp_tlast_init = 'b0;
    m_axis_tlp_tkeep_init = 'b0;
    m_axis_tlp_tvalid_init = 'b0;

    cpld_data_fifo_rd_en_next = 'b0;
    case (tr_state_reg)
        TR_STATE_IDLE : begin
            output_cycle_next = 'b0;
            cycle_next = 'b0;

            if (desc_tx_rd_req_start && (~desc_tx_rd_req_start_reg)) begin 
                tr_state_next = TR_STATE_START;
                output_cycle_next = desc_tx_rd_req_length_next[31 : OFFSET_WIDTH] + (desc_tx_rd_req_length_next[OFFSET_WIDTH - 1: 0] != 0);
            end
        end 

        TR_STATE_START : begin
            cpld_data_fifo_rd_en_next[op_tag_fifo_rdptr] = m_axis_tlp_tready_init  & (~cpld_data_fifo_empty[op_tag_fifo_rdptr]);
            if (cpld_data_fifo_rd_en_reg[op_tag_fifo_rdptr] & (~cpld_data_fifo_empty[op_tag_fifo_rdptr])) begin
                cycle_next = cycle_reg + 1'b1;
                output_cycle_next = output_cycle_reg - 1'b1;

                m_axis_tlp_tvalid_init = 1'b1;
                m_axis_tlp_tdata_init = cpld_data_fifo_dout[op_tag_fifo_rdptr];
                m_axis_tlp_tkeep_init = (output_cycle_next == 'b0) ? axis_tkeep_init : {TLP_DATA_WIDTH_BYTES{1'b1}};
                m_axis_tlp_tlast_init = (output_cycle_next == 0);
            end

            if (output_cycle_next == 'b0) begin
                tr_state_next = TR_STATE_IDLE;
            end
        end
        default: begin 

        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        tr_state_reg <= TR_STATE_IDLE;

        output_cycle_reg <= 'b0;
        cycle_reg <= 'b0;
        cpld_data_fifo_rd_en_reg <= 'b0;
    end
    else begin
        tr_state_reg <= tr_state_next;

        output_cycle_reg <= output_cycle_next;
        if (cycle_next == tag_table_info[op_tag_fifo_rdptr][PCIE_TAG_WIDTH+3:PCIE_TAG_WIDTH])begin
            cycle_reg <= 0;
        end
        else begin
            cycle_reg <= cycle_next;
        end
        cpld_data_fifo_rd_en_reg <= cpld_data_fifo_rd_en_next;
    end
end

(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [TLP_DATA_WIDTH-1:0] out_fifo_tdata[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [TLP_DATA_WIDTH_BYTES - 1:0]out_fifo_tkeep[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [0:0]out_fifo_tlast[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];

reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_wr_ptr_reg = 0;
reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_rd_ptr_reg = 0;
reg out_fifo_half_full_reg = 1'b0;

wire out_fifo_full = out_fifo_wr_ptr_reg == (out_fifo_rd_ptr_reg ^ {1'b1, {OUTPUT_FIFO_ADDR_WIDTH{1'b0}}});
wire out_fifo_empty = out_fifo_wr_ptr_reg == out_fifo_rd_ptr_reg;

assign m_axis_tlp_tdata = m_axis_tlp_tdata_reg;
assign m_axis_tlp_tkeep = m_axis_tlp_tkeep_reg;
assign m_axis_tlp_tlast = m_axis_tlp_tlast_reg;
assign m_axis_tlp_tvalid= m_axis_tlp_tvalid_reg;
assign m_axis_tlp_tready_init = !out_fifo_half_full_reg;

always @(posedge clk) begin
    m_axis_tlp_tvalid_reg <= m_axis_tlp_tvalid_reg && !m_axis_tlp_tready;
    out_fifo_half_full_reg <= $unsigned(out_fifo_wr_ptr_reg - out_fifo_rd_ptr_reg) >= 2**(OUTPUT_FIFO_ADDR_WIDTH-1);

    if (!out_fifo_full && m_axis_tlp_tvalid_init) begin
        out_fifo_tdata[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tlp_tdata_init;
        out_fifo_tkeep[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tlp_tkeep_init;
        out_fifo_tlast[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_tlp_tlast_init;
        out_fifo_wr_ptr_reg <= out_fifo_wr_ptr_reg + 1;
    end

    if (!out_fifo_empty &&(!m_axis_tlp_tvalid_reg || m_axis_tlp_tready)) begin
        m_axis_tlp_tdata_reg <= out_fifo_tdata[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        m_axis_tlp_tkeep_reg <= out_fifo_tkeep[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        m_axis_tlp_tlast_reg <= out_fifo_tlast[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        m_axis_tlp_tvalid_reg <= 1'b1;
        out_fifo_rd_ptr_reg <= out_fifo_rd_ptr_reg + 1;
    end

    if (rst) begin
        out_fifo_wr_ptr_reg <= 0;
        out_fifo_rd_ptr_reg <= 0;
        m_axis_tlp_tvalid_reg <= 1'b0;     
        m_axis_tlp_tlast_reg <= 'b0;
        m_axis_tlp_tdata_reg <= 'b0;   
        m_axis_tlp_tkeep_reg <= 'b0;
    end
end

endmodule
`resetall