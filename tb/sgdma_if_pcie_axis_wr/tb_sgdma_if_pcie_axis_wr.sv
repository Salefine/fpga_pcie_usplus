/****************************************************************************
 * @file    tb_sgdma_if_pcie_axis_wr.v
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

`define CLOCK_PERIOD 4

module tb_sgdma_if_pcie_axis_wr();

localparam TLP_DATA_WIDTH = 512;
localparam TLP_STRB_WIDTH = TLP_DATA_WIDTH/32;
localparam TLP_HDR_WIDTH = 128;
localparam TLP_SEG_COUNT = 1;
localparam PCIE_ADDR_WIDTH = 64;
localparam TX_SEQ_NUM_COUNT = 1;
localparam TX_SEQ_NUM_WIDTH = 6 ;   

reg clk = 0;
reg rst = 1;

wire [TLP_DATA_WIDTH-1:0]                 tx_wr_req_tlp_data;
wire [TLP_STRB_WIDTH-1:0]                 tx_wr_req_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]    tx_wr_req_tlp_hdr;
wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0] tx_wr_req_tlp_seq;
wire [TLP_SEG_COUNT-1:0]                  tx_wr_req_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                  tx_wr_req_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                  tx_wr_req_tlp_eop;
reg  tx_wr_req_tlp_ready = 0;

reg [31 : 0] desc_wr_req_sglist_length  = 'b0;
reg [PCIE_ADDR_WIDTH-1 : 0]  desc_wr_req_sglist_address ='b0;
reg desc_wr_req_sglist_start   ='b0;
reg desc_wr_req_sgdma_start    ='b0;

reg [2 : 0] max_read_payloadSize = 3'b010;
reg [15: 0]    requester_id        = 16'h0100;
reg [2 : 0]    MaxPayloadSize      = 3'b010;

wire tx_wr_sglist_irq;

wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_rd_req_tlp_hdr  ;
wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_rd_req_tlp_seq  ;
wire [TLP_SEG_COUNT-1:0]      tx_rd_req_tlp_valid;
wire [TLP_SEG_COUNT-1:0]      tx_rd_req_tlp_sop  ;
wire [TLP_SEG_COUNT-1:0]      tx_rd_req_tlp_eop  ;
reg  tx_rd_req_tlp_ready = 1'b1;    

wire [TLP_DATA_WIDTH - 1 : 0]s_axis_tlp_tdata ;
wire [TLP_DATA_WIDTH/8 - 1 : 0]s_axis_tlp_tkeep ;
wire s_axis_tlp_tvalid;
wire s_axis_tlp_tlast ;
wire s_axis_tlp_tready;

reg [TLP_DATA_WIDTH-1:0] rx_cpl_tlp_data = '0;
reg [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0] rx_cpl_tlp_hdr = '0;
reg [TLP_SEG_COUNT*4-1:0] rx_cpl_tlp_error = '0;
reg [TLP_SEG_COUNT-1:0] rx_cpl_tlp_valid = '0;
reg [TLP_SEG_COUNT-1:0] rx_cpl_tlp_sop = '0;
reg [TLP_SEG_COUNT-1:0] rx_cpl_tlp_eop = '0;
wire rx_cpl_tlp_ready;

reg [31:0] sglist_num = 'b0;
reg [63:0] sglist_addr = 'b0;

integer write_req_count;
integer write_sop_count;
integer write_eop_count;

task automatic sglist_rd;
    input  [31:0] length;
    input  [PCIE_ADDR_WIDTH-1:0] address;
begin
    #(`CLOCK_PERIOD);
    @(posedge clk);
    desc_wr_req_sglist_length  <= length;
    desc_wr_req_sglist_address <= address;
    desc_wr_req_sglist_start   <= 1'b1;
    @(posedge clk);
    desc_wr_req_sglist_start <= 'b0;
end
endtask

task automatic sgdma_cpld;
    input  [TLP_HDR_WIDTH-1:0] mrd_hdr;
    input  mrd_valid;
    input  sglist;
begin
    integer beat_idx;
    integer word_idx;
    integer payload_bytes;
    integer beats;
    reg [9:0] mrd_length;
    reg [11:0] byte_count;
    reg [7:0] tag;
    reg [1:0] lower_addr;
    reg [63:0] addr = 64'hcfc00000;

    if (!mrd_valid) begin
        rx_cpl_tlp_valid <= 1'b0;
        rx_cpl_tlp_sop   <= 1'b0;
        rx_cpl_tlp_eop   <= 1'b0;
        rx_cpl_tlp_hdr   <= 'b0;
        rx_cpl_tlp_data  <= 'b0;
    end

    mrd_length    = mrd_hdr[105:96];
    payload_bytes = mrd_length * 4;
    byte_count    = (payload_bytes < 128) ? payload_bytes[11:0] : 12'h080;
    // Completion header tag must match the tag allocated in the MRd request.
    // In the outbound MRd header, the tag field is [79:72], not [47:40].
    tag           = mrd_hdr[79:72];
    lower_addr    = 2'b00;
    beats         = (payload_bytes + (TLP_DATA_WIDTH/8) - 1) / (TLP_DATA_WIDTH/8);

    for (beat_idx = 0; beat_idx < beats; beat_idx = beat_idx + 1) begin
        while (rx_cpl_tlp_ready !== 1'b1) begin
            @(posedge clk);
        end

        rx_cpl_tlp_hdr <= '0;
        rx_cpl_tlp_hdr[105:96] <= mrd_length;
        rx_cpl_tlp_hdr[75:64]  <= byte_count;
        rx_cpl_tlp_hdr[47:40]  <= tag;
        rx_cpl_tlp_hdr[33:32]  <= lower_addr;

        if(sglist)begin
            //1.
            for(word_idx = 0; word_idx < TLP_DATA_WIDTH/128; word_idx = word_idx + 1)begin
                rx_cpl_tlp_data[word_idx * 128 +: 64] <= addr + 
                                    (beat_idx+1) * (word_idx+1) * (mrd_length << 2);
                rx_cpl_tlp_data[word_idx * 128 + 64 +: 32] <= 32'h4000;
                rx_cpl_tlp_data[word_idx * 128 + 96 +: 32] <= (beat_idx+1) * (word_idx+1);
            end
        end
        else begin
            for (word_idx = 0; word_idx < TLP_DATA_WIDTH/32; word_idx = word_idx + 1) begin
                rx_cpl_tlp_data[32*word_idx +: 32] <= 32'h00000000 + beat_idx*16 + word_idx;
            end
        end

        rx_cpl_tlp_error <= '0;
        rx_cpl_tlp_valid <= 1'b1;
        rx_cpl_tlp_sop   <= (beat_idx == 0);
        rx_cpl_tlp_eop   <= (beat_idx == beats - 1);
        @(posedge clk);
    end

    rx_cpl_tlp_valid <= 1'b0;
    rx_cpl_tlp_sop   <= 1'b0;
    rx_cpl_tlp_eop   <= 1'b0;
end
endtask

task automatic wait_for_write_tlp;
    input integer max_cycles;
begin
    integer cycle;
    write_req_count = 0;
    write_sop_count = 0;
    write_eop_count = 0;

    for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
        @(posedge clk);
        if (tx_wr_req_tlp_valid[0] && tx_wr_req_tlp_ready) begin
            write_req_count = write_req_count + 1;
            if (tx_wr_req_tlp_sop[0]) begin
                write_sop_count = write_sop_count + 1;
            end
            if (tx_wr_req_tlp_eop[0]) begin
                write_eop_count = write_eop_count + 1;
                break;
            end
        end
    end

    if (write_req_count == 0) begin
        $display("ERROR: SGDMA write test failed: no write TLP observed");
        $fatal;
    end
end
endtask

initial begin
    #(`CLOCK_PERIOD * 100);
    @(posedge clk);
    rst <= 0;
    sglist_num <= 32'd2;
    sglist_addr <= 63'hcfc00000;
    #(`CLOCK_PERIOD);
    @(posedge clk);
    tx_wr_req_tlp_ready <= 1'b1;

    sglist_rd(sglist_num * 16, sglist_addr);
    wait(tb_sgdma_axis_wr.tx_rd_req_tlp_valid[0]);

    sgdma_cpld(tb_sgdma_axis_wr.tx_rd_req_tlp_hdr, tb_sgdma_axis_wr.tx_rd_req_tlp_valid[0], 1);
    wait(tb_sgdma_axis_wr.tx_wr_sglist_irq);
    @(posedge clk);

    desc_wr_req_sgdma_start <= 1'b1;
    #(`CLOCK_PERIOD);
    desc_wr_req_sgdma_start <= 1'b0;

    wait_for_write_tlp(2000);

    if (write_sop_count == 0) begin
        $display("ERROR: SGDMA write test failed: no SOP TLP observed");
        $fatal;
    end

    if (write_eop_count == 0) begin
        $display("ERROR: SGDMA write test failed: no EOP TLP observed");
        $fatal;
    end

    $display("SGDMA write test passed: %0d write beats, %0d SOP, %0d EOP", write_req_count, write_sop_count, write_eop_count);
    #(`CLOCK_PERIOD * 800);
    $finish;
end


send_axis #(
    .STREAM_TDATA_WIDTH 	(TLP_DATA_WIDTH  ),
    .STREAM_TKEEP_WIDTH 	(TLP_DATA_WIDTH/8)
)u_send_axis(
    .m_axis_aclk    	(clk ),
    .m_axis_aresetn 	(~rst),
    .st_length      	(32'h4000 * sglist_num),
    .st_start       	(tb_sgdma_axis_wr.desc_wr_req_sgdma_start),
    .st_end         	(),
    .m_axis_tdata   	(s_axis_tlp_tdata ),
    .m_axis_tkeep   	(s_axis_tlp_tkeep ),
    .m_axis_tlast   	(s_axis_tlp_tlast ),
    .m_axis_tvalid  	(s_axis_tlp_tvalid),
    .m_axis_tready  	(s_axis_tlp_tready)
);

sgdma_if_pcie_axis_wr #(
    .TLP_DATA_WIDTH   	(TLP_DATA_WIDTH  ),
    .TLP_STRB_WIDTH   	(TLP_STRB_WIDTH  ),
    .TLP_HDR_WIDTH    	(TLP_HDR_WIDTH   ),
    .TLP_SEG_COUNT    	(TLP_SEG_COUNT   ),
    .PCIE_ADDR_WIDTH  	(PCIE_ADDR_WIDTH ),
    .TX_SEQ_NUM_COUNT 	(TX_SEQ_NUM_COUNT),
    .TX_SEQ_NUM_WIDTH 	(TX_SEQ_NUM_WIDTH)
)tb_sgdma_axis_wr(
    .clk(clk),
    .rst(rst),

    .tx_wr_req_tlp_data  (tx_wr_req_tlp_data  ),
    .tx_wr_req_tlp_strb  (tx_wr_req_tlp_strb  ),
    .tx_wr_req_tlp_hdr   (tx_wr_req_tlp_hdr   ),
    .tx_wr_req_tlp_seq   (tx_wr_req_tlp_seq   ),
    .tx_wr_req_tlp_valid (tx_wr_req_tlp_valid ),
    .tx_wr_req_tlp_sop   (tx_wr_req_tlp_sop   ),
    .tx_wr_req_tlp_eop   (tx_wr_req_tlp_eop   ),
    .tx_wr_req_tlp_ready (tx_wr_req_tlp_ready ),

    .desc_wr_req_sglist_length  	(desc_wr_req_sglist_length   ),
    .desc_wr_req_sglist_address 	(desc_wr_req_sglist_address  ),
    .desc_wr_req_sglist_start   	(desc_wr_req_sglist_start    ),
    .desc_wr_req_sgdma_start    	(desc_wr_req_sgdma_start     ),

    .tx_wr_sglist_irq     (tx_wr_sglist_irq     ),
    .requester_id         (requester_id         ),
    .MaxPayloadSize       (MaxPayloadSize       ),
    .Max_read_PayloadSize (max_read_payloadSize ),

    .s_axis_tlp_tdata   (s_axis_tlp_tdata  ),
    .s_axis_tlp_tkeep   (s_axis_tlp_tkeep  ),
    .s_axis_tlp_tvalid  (s_axis_tlp_tvalid ),
    .s_axis_tlp_tlast   (s_axis_tlp_tlast  ),
    .s_axis_tlp_tready  (s_axis_tlp_tready ),

    .tx_rd_req_tlp_hdr    (tx_rd_req_tlp_hdr   ),
    .tx_rd_req_tlp_seq    (tx_rd_req_tlp_seq   ),
    .tx_rd_req_tlp_valid  (tx_rd_req_tlp_valid ),
    .tx_rd_req_tlp_sop    (tx_rd_req_tlp_sop   ),
    .tx_rd_req_tlp_eop    (tx_rd_req_tlp_eop   ),
    .tx_rd_req_tlp_ready  (tx_rd_req_tlp_ready ),

    .rx_cpl_tlp_data   (rx_cpl_tlp_data  ),
    .rx_cpl_tlp_hdr    (rx_cpl_tlp_hdr   ),
    .rx_cpl_tlp_error  (rx_cpl_tlp_error ),
    .rx_cpl_tlp_valid  (rx_cpl_tlp_valid ),
    .rx_cpl_tlp_sop    (rx_cpl_tlp_sop   ),
    .rx_cpl_tlp_eop    (rx_cpl_tlp_eop   ),
    .rx_cpl_tlp_ready  (rx_cpl_tlp_ready )
);

always #(`CLOCK_PERIOD/2) clk = ~clk;

endmodule
`resetall