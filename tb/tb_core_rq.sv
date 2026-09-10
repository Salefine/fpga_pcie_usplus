/****************************************************************************
 * @file    tb_core_rq.v
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

`define     CLOCK_PERIOD 4 

module tb_core_rq();
// Width of PCIe AXI stream interfaces in bits
parameter AXIS_PCIE_DATA_WIDTH = 256    ;
// PCIe AXI stream tkeep signal width (words per cycle)
parameter AXIS_PCIE_KEEP_WIDTH = (AXIS_PCIE_DATA_WIDTH/32);
// PCIe AXI stream RC tuser signal width
parameter AXIS_PCIE_RC_USER_WIDTH = AXIS_PCIE_DATA_WIDTH < 512 ? 75 : 161;
// PCIe AXI stream RQ tuser signal width
parameter AXIS_PCIE_RQ_USER_WIDTH = AXIS_PCIE_DATA_WIDTH < 512 ? 60 : 137;
// PCIe AXI stream CQ tuser signal width
parameter AXIS_PCIE_CQ_USER_WIDTH = AXIS_PCIE_DATA_WIDTH < 512 ? 85 : 183;
// PCIe AXI stream CC tuser signal width
parameter AXIS_PCIE_CC_USER_WIDTH = AXIS_PCIE_DATA_WIDTH < 512 ? 33 : 81;
// RC interface TLP straddling
parameter RC_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 256;
// RQ interface TLP straddling
parameter RQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512;
// CQ interface TLP straddling
parameter CQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512;
// CC interface TLP straddling
parameter CC_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512;
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



reg     clk = 1;
reg     rst = 1;

wire  [TLP_DATA_WIDTH - 1 : 0] m_axis_rq_tdata;
wire  [TLP_STRB_WIDTH - 1 : 0] m_axis_rq_tkeep;
wire                           m_axis_rq_tvalid;
wire                           m_axis_rq_tlast;
reg                            m_axis_rq_tready = 1;
wire [AXIS_PCIE_RQ_USER_WIDTH-1:0]m_axis_rq_tuser;

reg [RQ_SEQ_NUM_WIDTH-1:0]                   s_axis_rq_seq_num_0  = 0;
reg                                          s_axis_rq_seq_num_valid_0 = 0;
reg [RQ_SEQ_NUM_WIDTH-1:0]                   s_axis_rq_seq_num_1 = 0;
reg                                          s_axis_rq_seq_num_valid_1 = 0;

    /*
     * TLP input (read request from DMA)
     */
    reg [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_rd_req_tlp_hdr   = 0;
    reg [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_rd_req_tlp_seq   = 0;
    reg [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_valid = 0;
    reg [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_sop   = 0;
    reg [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_eop   = 0;
     wire                                        tx_rd_req_tlp_ready;

    /*
     * Transmit sequence number output (DMA read request)
     */
    wire [TX_SEQ_NUM_COUNT*TX_SEQ_NUM_WIDTH-1:0]  m_axis_rd_req_tx_seq_num;
    wire [TX_SEQ_NUM_COUNT-1:0]                   m_axis_rd_req_tx_seq_num_valid;

    /*
     * TLP input (write request from DMA)
     */
    reg [TLP_DATA_WIDTH-1:0]                     tx_wr_req_tlp_data  = 0;
    reg [TLP_STRB_WIDTH-1:0]                     tx_wr_req_tlp_strb  = 0;
    reg [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_wr_req_tlp_hdr   = 0;
    reg [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_wr_req_tlp_seq   = 0;
    reg [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_valid = 0;
    reg [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_sop   = 0;
    reg [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_eop   = 0;
    wire                                         tx_wr_req_tlp_ready;

    /*
     * Transmit sequence number output (DMA write request)
     */
    wire [TX_SEQ_NUM_COUNT*TX_SEQ_NUM_WIDTH-1:0]  m_axis_wr_req_tx_seq_num;
    wire [TX_SEQ_NUM_COUNT-1:0]                   m_axis_wr_req_tx_seq_num_valid;

    /*
     * Flow control
     */
// flow control
reg [7:0]  tx_fc_ph_av  = 8'hFF;
reg [11:0] tx_fc_pd_av  = 12'hFFF;
reg [7:0]  tx_fc_nph_av = 8'hFF;
reg [11:0] tx_fc_npd_av = 12'hFFF;

    /*
     * Configuration
     */
    reg [2:0]       max_payload_size = 3'b010;

initial begin
    #(`CLOCK_PERIOD * 100);
    @(posedge clk);
    rst <= 0;
    #(`CLOCK_PERIOD * 100);
    @(posedge clk);
    tx_wr_req_tlp_data <={8{64'h0123456789abcdef}};
    tx_wr_req_tlp_hdr  <= 128'h600000200000017F0000000080000000;
    tx_wr_req_tlp_strb <= 16'hffff;
    tx_wr_req_tlp_seq  <= 1;
    tx_wr_req_tlp_valid<= 1;
    tx_wr_req_tlp_sop  <= 1;
    tx_wr_req_tlp_eop  <= 0;
    // wait(tx_wr_req_tlp_valid & tx_wr_req_tlp_ready)
    //send 1023 bytes
    @(posedge clk);
    tx_wr_req_tlp_data <= {8{64'hfedcba9876543210}}; //64bytes 
    tx_wr_req_tlp_hdr  <= 128'h600000200000017F0000000080000000;
    tx_wr_req_tlp_strb <= 16'h7fff;
    tx_wr_req_tlp_seq  <= 1;
    tx_wr_req_tlp_valid<= 1;
    tx_wr_req_tlp_sop  <= 0;
    tx_wr_req_tlp_eop  <= 1;
    @(posedge clk);
    tx_wr_req_tlp_hdr <= 128'h600000010000017F00000000FCF00000;
    tx_wr_req_tlp_data <= {8{64'h7766554433221100}}; //64bytes 
    tx_wr_req_tlp_strb <= 16'h3;
    tx_wr_req_tlp_seq  <= 2;
    tx_wr_req_tlp_valid<= 1;
    tx_wr_req_tlp_sop  <= 1;
    tx_wr_req_tlp_eop  <= 1;
    // wait(tx_wr_req_tlp_valid & tx_wr_req_tlp_ready)
    @(posedge clk);
    tx_wr_req_tlp_data <= {32{16'h0}};
    tx_wr_req_tlp_hdr  <= 128'h0;
    tx_wr_req_tlp_strb <= 16'h0;
    tx_wr_req_tlp_seq  <= 0;
    tx_wr_req_tlp_valid<= 0;
    tx_wr_req_tlp_sop  <= 0;
    tx_wr_req_tlp_eop  <= 0;
end

pcie_us_if_rq #(
    .AXIS_PCIE_DATA_WIDTH(AXIS_PCIE_DATA_WIDTH),
    .AXIS_PCIE_KEEP_WIDTH(AXIS_PCIE_KEEP_WIDTH),
    .AXIS_PCIE_RQ_USER_WIDTH(AXIS_PCIE_RQ_USER_WIDTH),
    .RQ_STRADDLE(RQ_STRADDLE),
    .RQ_SEQ_NUM_WIDTH(RQ_SEQ_NUM_WIDTH),
    .TLP_DATA_WIDTH(TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH(TLP_STRB_WIDTH),
    .TLP_HDR_WIDTH(TLP_HDR_WIDTH),
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TX_SEQ_NUM_COUNT(TX_SEQ_NUM_COUNT),
    .TX_SEQ_NUM_WIDTH(TX_SEQ_NUM_WIDTH)
)
pcie_us_if_rq_inst
(
    .clk(clk),
    .rst(rst),

    /*
     * AXI output (RQ)
     */
    .m_axis_rq_tdata(m_axis_rq_tdata),
    .m_axis_rq_tkeep(m_axis_rq_tkeep),
    .m_axis_rq_tvalid(m_axis_rq_tvalid),
    .m_axis_rq_tready(m_axis_rq_tready),
    .m_axis_rq_tlast(m_axis_rq_tlast),
    .m_axis_rq_tuser(m_axis_rq_tuser),

    /*
     * Transmit sequence number input
     */
    .s_axis_rq_seq_num_0(s_axis_rq_seq_num_0),
    .s_axis_rq_seq_num_valid_0(s_axis_rq_seq_num_valid_0),
    .s_axis_rq_seq_num_1(s_axis_rq_seq_num_1),
    .s_axis_rq_seq_num_valid_1(s_axis_rq_seq_num_valid_1),

    /*
     * TLP input (read request from DMA)
     */
    .tx_rd_req_tlp_hdr(tx_rd_req_tlp_hdr),
    .tx_rd_req_tlp_seq(tx_rd_req_tlp_seq),
    .tx_rd_req_tlp_valid(tx_rd_req_tlp_valid),
    .tx_rd_req_tlp_sop(tx_rd_req_tlp_sop),
    .tx_rd_req_tlp_eop(tx_rd_req_tlp_eop),
    .tx_rd_req_tlp_ready(tx_rd_req_tlp_ready),

    /*
     * Transmit sequence number output (DMA read request)
     */
    .m_axis_rd_req_tx_seq_num(m_axis_rd_req_tx_seq_num),
    .m_axis_rd_req_tx_seq_num_valid(m_axis_rd_req_tx_seq_num_valid),

    /*
     * TLP input (write request from DMA)
     */
    .tx_wr_req_tlp_data(tx_wr_req_tlp_data),
    .tx_wr_req_tlp_strb(tx_wr_req_tlp_strb),
    .tx_wr_req_tlp_hdr(tx_wr_req_tlp_hdr),
    .tx_wr_req_tlp_seq(tx_wr_req_tlp_seq),
    .tx_wr_req_tlp_valid(tx_wr_req_tlp_valid),
    .tx_wr_req_tlp_sop(tx_wr_req_tlp_sop),
    .tx_wr_req_tlp_eop(tx_wr_req_tlp_eop),
    .tx_wr_req_tlp_ready(tx_wr_req_tlp_ready),

    /*
     * Transmit sequence number output (DMA write request)
     */
    .m_axis_wr_req_tx_seq_num(m_axis_wr_req_tx_seq_num),
    .m_axis_wr_req_tx_seq_num_valid(m_axis_wr_req_tx_seq_num_valid),

    /*
     * Flow control
     */
    .tx_fc_ph_av(tx_fc_ph_av),
    .tx_fc_pd_av(tx_fc_pd_av),
    .tx_fc_nph_av(tx_fc_nph_av),
    .tx_fc_npd_av(tx_fc_npd_av),

    /*
     * Configuration
     */
    .max_payload_size(max_payload_size)
);

always #(`CLOCK_PERIOD/2) clk  = ~clk;

endmodule