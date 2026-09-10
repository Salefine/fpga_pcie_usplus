/****************************************************************************
 * @file    dma_if_pcie_axis_wr.v
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

module dma_if_pcie_axis_wr_v1#(
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
    
    output wire tx_wr_req_tlp_done,

    input  wire [TLP_DATA_WIDTH - 1 :0]      s_axis_tlp_tdata   ,
    input  wire [TLP_DATA_WIDTH / 8 - 1:0]   s_axis_tlp_tkeep   ,
    input  wire                              s_axis_tlp_tvalid  ,
    input  wire                              s_axis_tlp_tlast   ,
    output wire                              s_axis_tlp_tready  
);


localparam  OUTPUT_FIFO_ADDR_WIDTH = 5;
localparam  TLP_DATA_WIDTH_BYTES = TLP_DATA_WIDTH/8;
localparam  TLP_DATA_WIDTH_DWORDS = TLP_DATA_WIDTH/32;
localparam  OFFSET_WIDTH = $clog2(TLP_DATA_WIDTH_BYTES);
localparam  TLP_ALL_WIDTH = TLP_DATA_WIDTH + TLP_STRB_WIDTH + TLP_HDR_WIDTH + TX_SEQ_NUM_WIDTH + 3;


localparam [2:0]
    TLP_FMT_3DW = 3'b000,
    TLP_FMT_4DW = 3'b001,
    TLP_FMT_3DW_DATA = 3'b010,
    TLP_FMT_4DW_DATA = 3'b011,
    TLP_FMT_PREFIX = 3'b100;

localparam  REQ_MEM_WRITE = 5'b00000;
localparam  REQ_STATE_IDLE = 1'b0 , REQ_STATE_START = 1'b1;

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

integer i;

/*
 * 1 .
 */
reg [0:0]req_state_reg, req_state_next;

reg [31:0] cycle_reg    = 'b0, cycle_next   ;
reg [31:0] op_cycle_reg = 'b0, op_cycle_next;
reg [31:0] tr_cycle_reg = 'b0, tr_cycle_next;

reg desc_wr_req_start_reg;
reg [PCIE_ADDR_WIDTH-1 : 0]  desc_wr_req_address_reg= 0, desc_wr_req_address_next;
reg [31 : 0]                 desc_wr_req_length_reg = 0, desc_wr_req_length_next;

reg [9:0] tx_wr_req_length_reg = 'b0, tx_wr_req_length_next;
reg [PCIE_ADDR_WIDTH-1:0] tx_wr_req_addr_reg = 'b0 ,tx_wr_req_addr_next;

wire [3:0] first_be = 4'b1111 << desc_wr_req_address_reg[1:0];
wire [3:0] last_be = 4'b1111 >> (3 - ((desc_wr_req_address_reg[1:0] + (tr_cycle_reg == 1 ? desc_wr_req_length_reg[1:0] : 0) - 1) & 3));

reg [TLP_SEG_COUNT-1:0]                  tx_wr_req_tlp_sop_init  ;
reg [TLP_SEG_COUNT-1:0]                  tx_wr_req_tlp_eop_init  ;
reg [TLP_DATA_WIDTH-1:0]                 tx_wr_req_tlp_data_init ;
reg [TLP_STRB_WIDTH-1:0]                 tx_wr_req_tlp_strb_init ;
reg [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]    tx_wr_req_tlp_hdr_init  ;
reg [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0] tx_wr_req_tlp_seq_init  ;
reg [TLP_SEG_COUNT-1:0]                  tx_wr_req_tlp_valid_init;
reg s_axis_tlp_tready_reg = 'b0, s_axis_tlp_tready_next;
wire tx_wr_req_tlp_ready_init;

assign s_axis_tlp_tready = s_axis_tlp_tready_reg;


always @(*) begin

    req_state_next = req_state_reg;

    cycle_next = cycle_reg;
    op_cycle_next = op_cycle_reg;
    tr_cycle_next = tr_cycle_reg;

    desc_wr_req_address_next = desc_wr_req_address_reg;
    desc_wr_req_length_next = desc_wr_req_length_reg;

    tx_wr_req_length_next = tx_wr_req_length_reg;
    tx_wr_req_addr_next = tx_wr_req_addr_reg;

    s_axis_tlp_tready_next = 'b0;

    tx_wr_req_tlp_sop_init = 'b0;
    tx_wr_req_tlp_eop_init = 'b0;
    tx_wr_req_tlp_data_init = s_axis_tlp_tdata;
    tx_wr_req_tlp_strb_init = 'b0;
    tx_wr_req_tlp_seq_init = 'b0;
    tx_wr_req_tlp_valid_init = 'b0;
    tx_wr_req_tlp_hdr_init = 'b0;

    case (req_state_reg)
        REQ_STATE_IDLE : begin
            cycle_next = 'b0;
            op_cycle_next = 'b0;
            tr_cycle_next = 'b0;

            if (desc_wr_req_start && (~desc_wr_req_start_reg)) begin
                desc_wr_req_length_next = desc_wr_req_length;
                tx_wr_req_addr_next = desc_wr_req_address;

                cycle_next = desc_wr_req_length_next[31 : OFFSET_WIDTH] + |(desc_wr_req_length_next[OFFSET_WIDTH-1:0]);
                if(MaxPayloadSize == 3'b000)begin
                    tr_cycle_next = desc_wr_req_length_next[31:7] + (desc_wr_req_length_next[6:0] != 0);
                end
                else if (MaxPayloadSize == 3'b001) begin
                    tr_cycle_next = desc_wr_req_length_next[31:8] + (desc_wr_req_length_next[7:0] != 0);
                end
                else if(MaxPayloadSize == 3'b010)begin
                    tr_cycle_next = desc_wr_req_length_next[31:9] + (desc_wr_req_length_next[8:0] != 0);
                end
                else if(MaxPayloadSize == 3'b011)begin
                    tr_cycle_next = desc_wr_req_length_next[31:10] + (desc_wr_req_length_next[9:0] != 0);
                end
                req_state_next = REQ_STATE_START;
            end
        end

        REQ_STATE_START : begin
            s_axis_tlp_tready_next = tx_wr_req_tlp_ready_init;
            
            if(s_axis_tlp_tvalid && s_axis_tlp_tready )begin
                op_cycle_next = op_cycle_reg + 1'b1;
                tx_wr_req_tlp_valid_init = 1'b1;
                tx_wr_req_tlp_data_init = s_axis_tlp_tdata;

                if (MaxPayloadSize == 3'b000) begin //max payload size is equal 128 bytes
                    tx_wr_req_tlp_sop_init = (op_cycle_next[6 - OFFSET_WIDTH : 0] == 1);
                    tx_wr_req_tlp_eop_init = (op_cycle_next[6 - OFFSET_WIDTH : 0] == 3'b0 && op_cycle_next[31 : 7 - OFFSET_WIDTH] != 0) || (op_cycle_next == cycle_reg);
                    tx_wr_req_tlp_seq_init = op_cycle_reg[6 - OFFSET_WIDTH + TX_SEQ_NUM_WIDTH : 7 - OFFSET_WIDTH];
                    for (i = 0; i < TLP_STRB_WIDTH ; i = i + 1) begin
                        tx_wr_req_tlp_strb_init[i] = (s_axis_tlp_tkeep[i * 4 +: 4] != 0);
                    end

                    if (tx_wr_req_tlp_eop_init) begin
                        tx_wr_req_addr_next = tx_wr_req_addr_reg + 10'd128;
                        tr_cycle_next = tr_cycle_reg - 1'b1;
                    end

                    if (tr_cycle_reg > 1'b1) begin
                        tx_wr_req_length_next = (10'd128 << MaxPayloadSize) >> 2;
                    end
                    else if(tr_cycle_reg == 1'b1)begin
                        tx_wr_req_length_next = desc_wr_req_length_reg[6 : 2] + (desc_wr_req_length_reg[1:0] != 0);
                        if (tx_wr_req_length_next == 0) begin
                            tx_wr_req_length_next = (10'd128 << MaxPayloadSize) >> 2;
                        end
                    end            
                end

                else if (MaxPayloadSize == 3'b001) begin
                    tx_wr_req_tlp_sop_init = op_cycle_next[7 - OFFSET_WIDTH : 0] == 3'b1;
                    tx_wr_req_tlp_eop_init = (op_cycle_next[7 - OFFSET_WIDTH : 0] == 3'b0 && op_cycle_next[31 : 8 - OFFSET_WIDTH] != 0) || (op_cycle_next == cycle_reg);
                    tx_wr_req_tlp_seq_init = op_cycle_reg[7 - OFFSET_WIDTH + TX_SEQ_NUM_WIDTH : 8 - OFFSET_WIDTH];
                    for (i = 0; i < TLP_STRB_WIDTH ; i = i + 1) begin
                        tx_wr_req_tlp_strb_init[i] = (s_axis_tlp_tkeep[i * 4 +: 4] != 0);
                    end

                    if (tx_wr_req_tlp_eop_init) begin
                        tx_wr_req_addr_next = tx_wr_req_addr_reg + 10'd256;
                        tr_cycle_next = tr_cycle_reg - 1'b1;
                    end

                    if (tr_cycle_reg > 1'b1) begin
                        tx_wr_req_length_next = (10'd128 << MaxPayloadSize) >> 2;
                    end
                    else if(tr_cycle_reg == 1'b1)begin
                        tx_wr_req_length_next = desc_wr_req_length_reg[7 : 2] + (desc_wr_req_length_reg[1:0] != 0);
                        if (tx_wr_req_length_next == 0) begin
                            tx_wr_req_length_next = (10'd128 << MaxPayloadSize) >> 2;
                        end
                    end               
                end

                else if(MaxPayloadSize == 3'b010)begin //max payload size is equal 512 byte
                    tx_wr_req_tlp_sop_init = op_cycle_next[8 - OFFSET_WIDTH : 0] == 1;
                    tx_wr_req_tlp_eop_init = (op_cycle_next[8 - OFFSET_WIDTH : 0] == 0 && op_cycle_next[31 : 9 - OFFSET_WIDTH] != 0) || (op_cycle_next == cycle_reg);
                    tx_wr_req_tlp_seq_init = op_cycle_reg[8 - OFFSET_WIDTH + TX_SEQ_NUM_WIDTH : 9 - OFFSET_WIDTH];
                    for (i = 0; i < TLP_STRB_WIDTH ; i = i + 1) begin
                        tx_wr_req_tlp_strb_init[i] = (s_axis_tlp_tkeep[i * 4 +: 4] != 0);
                    end

                    if (tx_wr_req_tlp_eop_init) begin
                        tx_wr_req_addr_next = tx_wr_req_addr_reg + 10'd512;
                        tr_cycle_next = tr_cycle_reg - 1'b1;
                    end

                    if (tr_cycle_reg > 1'b1) begin
                        tx_wr_req_length_next = (10'd128 << MaxPayloadSize) >> 2;
                    end
                    else if(tr_cycle_reg == 1'b1)begin
                        tx_wr_req_length_next = desc_wr_req_length_reg[8 : 2] + (desc_wr_req_length_reg[1:0] != 0);
                        if (tx_wr_req_length_next == 0) begin
                            tx_wr_req_length_next = (10'd128 << MaxPayloadSize) >> 2;
                        end
                    end
                end

                else if(MaxPayloadSize == 3'b011)begin
                    tx_wr_req_tlp_sop_init = op_cycle_next[9 - OFFSET_WIDTH : 0] == 1;
                    tx_wr_req_tlp_eop_init = (op_cycle_next[9 - OFFSET_WIDTH : 0] == 0 && op_cycle_next[31 : 10 - OFFSET_WIDTH] != 0) || (op_cycle_next == cycle_reg);
                    tx_wr_req_tlp_seq_init = op_cycle_reg[9 - OFFSET_WIDTH + TX_SEQ_NUM_WIDTH : 10 - OFFSET_WIDTH];
                    for (i = 0; i < TLP_STRB_WIDTH ; i = i + 1) begin
                        tx_wr_req_tlp_strb_init[i] = (s_axis_tlp_tkeep[i * 4 +: 4] != 0);
                    end

                    if (tx_wr_req_tlp_eop_init) begin
                        tx_wr_req_addr_next = tx_wr_req_addr_reg + 11'd1024;
                        tr_cycle_next = tr_cycle_reg - 1'b1;
                    end

                    if (tr_cycle_reg > 1'b1) begin
                        tx_wr_req_length_next = 'b0;
                    end
                    else if(tr_cycle_reg == 1'b1)begin
                        tx_wr_req_length_next = desc_wr_req_length_reg[9 : 2] + (desc_wr_req_length_reg[1:0] != 0);
                        if (tx_wr_req_length_next == 0) begin
                            tx_wr_req_length_next = 'b0;
                        end
                    end          
                end
            end
            
            tx_wr_req_tlp_hdr_init[127:125] = TLP_FMT_4DW_DATA; //fmt
            tx_wr_req_tlp_hdr_init[124:120] = REQ_MEM_WRITE   ; //type
            tx_wr_req_tlp_hdr_init[119]     = 1'b0            ; //t9
            tx_wr_req_tlp_hdr_init[118:116] = 3'b0            ; //tc
            tx_wr_req_tlp_hdr_init[115]     = 1'b0            ; //t8
            tx_wr_req_tlp_hdr_init[114]     = 1'b0            ; //a2
            tx_wr_req_tlp_hdr_init[113]     = 1'b0            ; //r
            tx_wr_req_tlp_hdr_init[112]     = 1'b0            ; //th
            tx_wr_req_tlp_hdr_init[111]     = 1'b0            ; //td
            tx_wr_req_tlp_hdr_init[110]     = 1'b0            ; //ep
            tx_wr_req_tlp_hdr_init[109:108] = 2'b0            ; //attr
            tx_wr_req_tlp_hdr_init[107:106] = 2'b0            ; //at
            tx_wr_req_tlp_hdr_init[105:96]  = tx_wr_req_length_next; //length
            tx_wr_req_tlp_hdr_init[95:80]   = requester_id    ; //request id
            tx_wr_req_tlp_hdr_init[79:72]   = 8'h0            ; //tag
            tx_wr_req_tlp_hdr_init[71:68]   = (tx_wr_req_length_next == 1) ? 4'b0000 : last_be; // last be
            tx_wr_req_tlp_hdr_init[67:64]   = (tx_wr_req_length_next == 1) ? first_be & last_be : first_be; //first be
            tx_wr_req_tlp_hdr_init[63:2]    = tx_wr_req_addr_reg[63:2]; //address
            tx_wr_req_tlp_hdr_init[1:0]     = 2'b00;  
            if (op_cycle_next == cycle_reg) begin
                req_state_next = REQ_STATE_IDLE;
            end
        end
        default: begin
            
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        req_state_reg <= REQ_STATE_IDLE;
        s_axis_tlp_tready_reg <= 'b0;
        cycle_reg <= 'b0;
        op_cycle_reg <= 'b0;
        tr_cycle_reg <= 'b0;

        desc_wr_req_address_reg <= 'b0;
        desc_wr_req_length_reg <= 'b0;
        desc_wr_req_start_reg <= 'b0;

        tx_wr_req_length_reg <= 'b0;
        tx_wr_req_addr_reg <= 'b0;
    end
    else begin
        req_state_reg <= req_state_next;
        s_axis_tlp_tready_reg <= s_axis_tlp_tready_next;
        cycle_reg <= cycle_next;
        op_cycle_reg <= op_cycle_next;
        tr_cycle_reg <= tr_cycle_next;
    
        desc_wr_req_address_reg <= desc_wr_req_address_next;
        desc_wr_req_length_reg <= desc_wr_req_length_next;
        desc_wr_req_start_reg <= desc_wr_req_start;

        tx_wr_req_length_reg <= tx_wr_req_length_next;
        tx_wr_req_addr_reg <= tx_wr_req_addr_next;
    end
end

/*
 * 2.
 */
reg [TLP_SEG_COUNT-1:0]                  tx_wr_req_tlp_sop_reg   = 'b0;//  ; 
reg [TLP_SEG_COUNT-1:0]                  tx_wr_req_tlp_eop_reg   = 'b0;//  ;
reg [TLP_DATA_WIDTH-1:0]                 tx_wr_req_tlp_data_reg  = 'b0;// ;
reg [TLP_STRB_WIDTH-1:0]                 tx_wr_req_tlp_strb_reg  = 'b0;// ;
reg [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]    tx_wr_req_tlp_hdr_reg   = 'b0;
reg [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0] tx_wr_req_tlp_seq_reg   = 'b0;//  ;
reg [TLP_SEG_COUNT-1:0]                  tx_wr_req_tlp_valid_reg = 'b0;

(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [TLP_DATA_WIDTH-1:0] out_fifo_wdata[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [TLP_HDR_WIDTH - 1:0]out_fifo_hdr[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [TX_SEQ_NUM_WIDTH - 1:0]out_fifo_seq[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg [TLP_STRB_WIDTH-1:0] out_fifo_wstrb[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg                      out_fifo_sop[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
reg                      out_fifo_eop[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];

reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_wr_ptr_reg = 0;
reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_rd_ptr_reg = 0;
reg out_fifo_half_full_reg = 1'b0;

wire out_fifo_full = out_fifo_wr_ptr_reg == (out_fifo_rd_ptr_reg ^ {1'b1, {OUTPUT_FIFO_ADDR_WIDTH{1'b0}}});
wire out_fifo_empty = out_fifo_wr_ptr_reg == out_fifo_rd_ptr_reg;

assign tx_wr_req_tlp_ready_init = !out_fifo_half_full_reg;

assign tx_wr_req_tlp_data = tx_wr_req_tlp_data_reg;
assign tx_wr_req_tlp_strb = tx_wr_req_tlp_strb_reg;
assign tx_wr_req_tlp_hdr  = tx_wr_req_tlp_hdr_reg;
assign tx_wr_req_tlp_seq  = tx_wr_req_tlp_seq_reg;
assign tx_wr_req_tlp_valid = tx_wr_req_tlp_valid_reg;
assign tx_wr_req_tlp_sop  = tx_wr_req_tlp_sop_reg;
assign tx_wr_req_tlp_eop  = tx_wr_req_tlp_eop_reg;

always @(posedge clk) begin
    tx_wr_req_tlp_valid_reg <= tx_wr_req_tlp_valid_reg && !tx_wr_req_tlp_ready;

    out_fifo_half_full_reg <= $unsigned(out_fifo_wr_ptr_reg - out_fifo_rd_ptr_reg) >= 2**(OUTPUT_FIFO_ADDR_WIDTH-1);

    if (!out_fifo_full && tx_wr_req_tlp_valid_init) begin
        out_fifo_wdata[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= tx_wr_req_tlp_data_init;
        out_fifo_wstrb[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= tx_wr_req_tlp_strb_init;
        out_fifo_hdr[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= tx_wr_req_tlp_hdr_init;
        out_fifo_sop[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= tx_wr_req_tlp_sop_init;
        out_fifo_eop[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= tx_wr_req_tlp_eop_init;
        out_fifo_seq[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= tx_wr_req_tlp_seq_init;        

        out_fifo_wr_ptr_reg <= out_fifo_wr_ptr_reg + 1;
    end

    if (!out_fifo_empty && (!tx_wr_req_tlp_valid_reg || tx_wr_req_tlp_ready)) begin
        tx_wr_req_tlp_data_reg <= out_fifo_wdata[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        tx_wr_req_tlp_strb_reg <= out_fifo_wstrb[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        tx_wr_req_tlp_hdr_reg <= out_fifo_hdr[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        tx_wr_req_tlp_seq_reg <= out_fifo_seq[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        tx_wr_req_tlp_sop_reg <= out_fifo_sop[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        tx_wr_req_tlp_eop_reg <= out_fifo_eop[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        tx_wr_req_tlp_valid_reg <= 1'b1;
        out_fifo_rd_ptr_reg <= out_fifo_rd_ptr_reg + 1;
    end

    if (rst) begin
        out_fifo_wr_ptr_reg <= 0;
        out_fifo_rd_ptr_reg <= 0;
        tx_wr_req_tlp_valid_reg <= 1'b0;
    end
end


//-------------------user modify @2026-7-31---------------------------//
reg [31:0] tr_bytes_reg = 'b0, tr_bytes_next;
assign tx_wr_req_tlp_done = (tr_bytes_reg >= desc_wr_req_length_reg && (tr_bytes_reg!=0)) ? 1'b1 : 1'b0;

always @(*)begin
    tr_bytes_next = tr_bytes_reg;
    if(desc_wr_req_start)begin
        tr_bytes_next = 0;
    end
//    else if(tr_bytes_reg >= desc_wr_req_length_reg && (tr_bytes_reg!=0))begin
//    end
    else if(s_axis_tlp_tvalid & s_axis_tlp_tready)begin
        tr_bytes_next = tr_bytes_reg + TLP_DATA_WIDTH_BYTES;
    end
end

always @(posedge clk)begin
    if(rst)begin
        tr_bytes_reg <= 'b0;
    end
    else begin
        tr_bytes_reg <= tr_bytes_next;
    end
end

endmodule
 `resetall