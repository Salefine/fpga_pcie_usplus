/****************************************************************************
 * @file    tb_sgdma_if_pcie_axis_rd.sv
 * @brief   sgdma_if_pcie_axis_rd read SG-DMA module testbench,
 *          implemented strictly per tb_sgdma_if_pcie_axis_rd.md spec
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 2.1
 * @date    2026-09-02
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    zzhi          |                        |
 * |  2026-09-01   |   v1.1      |    zzhi          | add SG-list DMA tests  |
 * |  2026-09-02   |   v2.0      |    zzhi          | rewrite cases per spec |
 * |  2026-09-02   |   v2.1      |    zzhi          | English comments       |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @par Test content (per spec):
 *   Test 1: list @0xcfcc0000, length 256bit (2 entries):
 *     entry 1: seq 1, len 0x4000, addr 0xfcfc0000 (data: counter from 0, int unit)
 *     entry 2: seq 2, len 0x4000, addr 0xfcfd0000 (data: counter from 0, int unit)
 *     -> m_axis outputs 16384B + 16384B, dwords 0..4095 per segment, 2 data tlast
 *   Test 2: list @0xcfcc0000, length 384bit (3 entries):
 *     entry 1: seq 1, len 0x4000, addr 0xfcfc0000
 *     entry 2: seq 2, len 0x4000, addr 0xfcfd0000
 *     entry 3: seq 3, len 0x4009, addr 0xfcfe0000 (16393B, tail not dword aligned)
 *     -> m_axis outputs 16384B + 16384B + 16393B (last beat partial tkeep,
 *        checked byte by byte)
 * 
 * @par SG-list entry memory layout (little-endian, matches DUT decoding):
 *   dword0 = start address [31:0], dword1 = start address [63:32],
 *   dword2 = length (bytes),       dword3 = sequence number
 *   (DUT reads a 128b word: [63:0]=address, [95:64]=length, [127:96]=seq)
 * 
 * @par Verification mechanism:
 *   1. MRd monitor: checks fmt/type/requester/BE/tag increment, addresses
 *      advance contiguously per region, accumulates bytes/MRd count per region;
 *      BE rule: list reads (8/12dw) and full 128dw reads use F/F; the tail MRd
 *      of the 0x4009 segment covers 9B -> 3dw with first=F, last=0001
 *      (PCIe rounds up to a dword boundary)
 *   2. CplD responder: replies per MRd in order (fmt=101/type=01010, tag echo);
 *      list reads return entry content (little-endian packed), data reads
 *      return region counter dwords (value=(addr-region_base)/4, each region
 *      counts from 0, int unit); invalid CplD lanes filled with 0xDEADBEEF to
 *      verify DUT tkeep masking
 *   3. m_axis monitor discriminated by DUT FSM state and valid&ready
 *      handshake: RDRECV counts list bytes; ENDL samples data beats and
 *      compares in int (dword) units against the region counters (partial
 *      tail dword rounded up to one int), per-segment dword count,
 *      non-last beats keep tkeep all 1
 *   4. desc_tx_rddma_start is edge-detected inside the DUT: after the list
 *      tlast the DUT waits in RDRECV; TB asserts it as a 1-cycle pulse
 *      RDDMA_START_DELAY (10) cycles after tx_rd_req_irq
 *   5. End of task: DUT FSM must return to IDLE and m_axis_tvalid must be 0
 * ***************************************************************************/

`resetall
`timescale 1ns/1ps
`default_nettype none

`define CLOCK_PERIOD 4
module tb_sgdma_if_pcie_axis_rd();

// ---------------- Parameters ----------------
localparam TLP_DATA_WIDTH  = 512;
localparam TLP_HDR_WIDTH   = 128;
localparam TLP_SEG_COUNT   = 1;
localparam PCIE_ADDR_WIDTH = 64;
localparam TX_SEQ_NUM_WIDTH = 6;
localparam DW_PER_BEAT     = TLP_DATA_WIDTH/32;   // 16 dwords per beat

// DUT internal state encoding (see sgdma_if_pcie_axis_rd.v)
localparam [4:0] S_IDLE    = 5'b00001,
                 S_RDLIST  = 5'b00010,
                 S_RDRECV  = 5'b00100,
                 S_RDSTART = 5'b01000,
                 S_ENDL    = 5'b10000;

// ---------------- Test addresses and lengths (per spec) ----------------
// Regions: 0=list, 1=buffer A, 2=buffer B, 3=buffer C
localparam [63:0] LIST_ADDR  = 64'h0000_0000_cfcc_0000;  // shared by both tests
localparam [63:0] BUF_A_ADDR = 64'h0000_0000_fcfc_0000;
localparam [63:0] BUF_B_ADDR = 64'h0000_0000_fcfd_0000;
localparam [63:0] BUF_C_ADDR = 64'h0000_0000_fcfe_0000;
localparam [31:0] SEG_A_LEN  = 32'h4000;   // 16384B
localparam [31:0] SEG_B_LEN  = 32'h4000;   // 16384B
localparam [31:0] SEG_C_LEN  = 32'h4009;   // 16393B (tail not dword aligned)
localparam        LIST_BYTES_T1 = 32;      // 256bit = 2 entries x 16B
localparam        LIST_BYTES_T2 = 48;      // 384bit = 3 entries x 16B
localparam        RDDMA_START_DELAY = 10;  // cycles from irq to desc_tx_rddma_start

// SG-list entry: {seq[127:96], length bytes[95:64], start address[63:0]}
reg [127:0] t1_sg [0:1];
reg [127:0] t2_sg [0:2];
integer list_sel;          // responder list select: 0=test 1, 1=test 2

// ---------------- Clock / reset ----------------
// Clock toggles from t=0 immediately: measured to avoid XPM FIFO
// [EMPTY_CHECK S-4] reset-phase noise assertions
reg clk = 0;
reg rst = 1;
always #(`CLOCK_PERIOD/2) clk = ~clk;

// ---------------- DUT interface ----------------
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]    tx_rd_req_tlp_hdr;
wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0] tx_rd_req_tlp_seq;
wire [TLP_SEG_COUNT-1:0]                  tx_rd_req_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                  tx_rd_req_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                  tx_rd_req_tlp_eop;
reg  tx_rd_req_tlp_ready = 1'b1;

reg  [TLP_DATA_WIDTH-1:0]           rx_cpl_tlp_data = '0;
reg  [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0] rx_cpl_tlp_hdr = '0;
reg  [TLP_SEG_COUNT-1:0]            rx_cpl_tlp_valid = 1'b0;
reg  [TLP_SEG_COUNT-1:0]            rx_cpl_tlp_sop   = 1'b0;
reg  [TLP_SEG_COUNT-1:0]            rx_cpl_tlp_eop   = 1'b0;
reg  [TLP_SEG_COUNT*4-1:0]          rx_cpl_tlp_error = '0;
wire                                rx_cpl_tlp_ready;

reg  [15:0] requester_id        = 16'h0100;
reg  [2:0]  max_read_payloadSize = 3'b010;      // MRRS=512B
wire        tx_rd_req_irq;

wire [TLP_DATA_WIDTH-1:0]   m_axis_tlp_tdata;
wire [TLP_DATA_WIDTH/8-1:0] m_axis_tlp_tkeep;
wire                        m_axis_tlp_tvalid;
wire                        m_axis_tlp_tlast;
reg  m_axis_tlp_tready = 1'b1;

reg [31:0]           desc_tx_rdlist_length  = '0;
reg [PCIE_ADDR_WIDTH-1:0] desc_tx_rdlist_address = '0;
reg                  desc_tx_rdlist_start = '0;

// desc_tx_rddma_start is edge-detected inside the DUT: after the list has been
// fully received (tx_rd_req_irq pulsed) the DUT waits in RDRECV for this
// rising edge; TB asserts it RDDMA_START_DELAY cycles later as a 1-cycle pulse
reg desc_tx_rddma_start = 1'b0;

// ---------------- DUT instance ----------------
sgdma_if_pcie_axis_rd #(
    .TLP_DATA_WIDTH   (TLP_DATA_WIDTH),
    .TLP_HDR_WIDTH    (TLP_HDR_WIDTH),
    .TLP_SEG_COUNT    (TLP_SEG_COUNT),
    .TX_SEQ_NUM_WIDTH (TX_SEQ_NUM_WIDTH),
    .PCIE_ADDR_WIDTH  (PCIE_ADDR_WIDTH),
    .PCIE_TAG_COUNT   (32),
    .OP_TABLE_SIZE    (32)
) dut (
    .clk (clk),
    .rst (rst),

    .tx_rd_req_tlp_hdr  (tx_rd_req_tlp_hdr),
    .tx_rd_req_tlp_seq  (tx_rd_req_tlp_seq),
    .tx_rd_req_tlp_valid(tx_rd_req_tlp_valid),
    .tx_rd_req_tlp_sop  (tx_rd_req_tlp_sop),
    .tx_rd_req_tlp_eop  (tx_rd_req_tlp_eop),
    .tx_rd_req_tlp_ready(tx_rd_req_tlp_ready),

    .rx_cpl_tlp_data (rx_cpl_tlp_data),
    .rx_cpl_tlp_hdr  (rx_cpl_tlp_hdr),
    .rx_cpl_tlp_error(rx_cpl_tlp_error),
    .rx_cpl_tlp_valid(rx_cpl_tlp_valid),
    .rx_cpl_tlp_sop  (rx_cpl_tlp_sop),
    .rx_cpl_tlp_eop  (rx_cpl_tlp_eop),
    .rx_cpl_tlp_ready(rx_cpl_tlp_ready),

    .requester_id        (requester_id),
    .max_read_payloadSize(max_read_payloadSize),
    .tx_rd_req_irq       (tx_rd_req_irq),

    .desc_tx_rdlist_length (desc_tx_rdlist_length),
    .desc_tx_rdlist_address(desc_tx_rdlist_address),
    .desc_tx_rdlist_start  (desc_tx_rdlist_start),
    .desc_tx_rddma_start   (desc_tx_rddma_start),

    .m_axis_tlp_tdata  (m_axis_tlp_tdata),
    .m_axis_tlp_tkeep  (m_axis_tlp_tkeep),
    .m_axis_tlp_tvalid (m_axis_tlp_tvalid),
    .m_axis_tlp_tlast  (m_axis_tlp_tlast),
    .m_axis_tlp_tready (m_axis_tlp_tready)
);

// ---------------- Stats and checks ----------------
integer error_count = 0;

// Elaboration guard: the DUT must be compiled with the TB data width.
// A 256b DUT behind a 512b TB silently truncates every CplD beat to its low
// half (data shows up as interleaved/jumping counters) and leaves tkeep
// upper lanes undriven, so catch it here instead of chasing waveform ghosts.
initial begin
    if (dut.TLP_DATA_WIDTH != TLP_DATA_WIDTH) begin
        $display("FATAL: DUT TLP_DATA_WIDTH=%0d but TB TLP_DATA_WIDTH=%0d (stale snapshot or missing parameter override)",
                 dut.TLP_DATA_WIDTH, TLP_DATA_WIDTH);
        $fatal;
    end
end

task automatic chk(input cond, input string msg);
    begin
        if (cond !== 1'b1) begin
            error_count = error_count + 1;
            $display("[%0t] ERROR: %s", $time, msg);
        end
    end
endtask

// Interrupt sticky flag
reg rd_irq_seen = 0;
always @(posedge clk) begin
    if (rst)                    rd_irq_seen <= 0;
    else if (tx_rd_req_irq)     rd_irq_seen <= 1;
end

// ---------------- Region tracking (MRd monitor) ----------------
reg [63:0] region_base     [0:3];
reg [63:0] region_exp_addr [0:3];
integer    region_bytes    [0:3];
integer    region_mrds     [0:3];
integer    exp_tag = 0;               // tag increments from 0 within a descriptor

function automatic integer classify_region(input [63:0] a);
    begin
        classify_region = -1;
        if      (a >= LIST_ADDR  && a < LIST_ADDR  + 64'h100)     classify_region = 0;
        else if (a >= BUF_A_ADDR && a < BUF_A_ADDR + SEG_A_LEN)   classify_region = 1;
        else if (a >= BUF_B_ADDR && a < BUF_B_ADDR + SEG_B_LEN)   classify_region = 2;
        else if (a >= BUF_C_ADDR && a < BUF_C_ADDR + 64'h4200)    classify_region = 3;
    end
endfunction

integer m_r;
integer m_len_dw;
reg [63:0] m_addr;
reg [7:0]  m_tag;

always @(negedge clk) begin
    if (!rst && tx_rd_req_tlp_valid === 1'b1 && tx_rd_req_tlp_ready === 1'b1) begin
        chk(tx_rd_req_tlp_sop === 1'b1 && tx_rd_req_tlp_eop === 1'b1, "MRd should be a single-beat frame (sop=eop)");
        chk(tx_rd_req_tlp_hdr[127:125] === 3'b001,   "MRd fmt should be 001 (4DW no data)");
        chk(tx_rd_req_tlp_hdr[124:120] === 5'b00000, "MRd type should be 00000 (MemRd)");
        chk(tx_rd_req_tlp_hdr[95:80]   === requester_id, "MRd requester id mismatch");

        m_len_dw = (tx_rd_req_tlp_hdr[105:96] == 0) ? 1024 : tx_rd_req_tlp_hdr[105:96];
        m_tag    = tx_rd_req_tlp_hdr[79:72];
        m_addr   = {tx_rd_req_tlp_hdr[63:2], 2'b00};

        // BE rule: list reads (8/12dw) and full 128dw reads use F/F; the tail
        // MRd of the 0x4009 segment covers 9B -> 3dw with first=F, last=0001
        // (PCIe rounds the length up to a dword boundary)
        if (m_len_dw == 3) begin
            chk(tx_rd_req_tlp_hdr[71:68] === 4'h1 && tx_rd_req_tlp_hdr[67:64] === 4'hf,
                $sformatf("MRd BE error (tail read, len_dw=%0d), expect first=F last=1", m_len_dw));
        end
        else begin
            chk(tx_rd_req_tlp_hdr[71:68] === 4'hf && tx_rd_req_tlp_hdr[67:64] === 4'hf,
                $sformatf("MRd BE error (full read, len_dw=%0d), expect first=F last=F", m_len_dw));
        end

        // Tag sequence: increments from 0 within each descriptor (tag==0 is
        // treated as a new sequence start, allowing 32-tag wraparound)
        if (m_tag == 8'd0) begin
            exp_tag = 1;
        end
        else begin
            chk(m_tag == exp_tag[7:0],
                $sformatf("MRd tag jump: %02h expected %02h", m_tag, exp_tag[7:0]));
            exp_tag = m_tag + 1;
        end

        // Region ownership / address continuity / byte accumulation
        m_r = classify_region(m_addr);
        chk(m_r >= 0, $sformatf("MRd address out of range: %h", m_addr));
        if (m_r >= 0) begin
            chk(m_addr === region_exp_addr[m_r],
                $sformatf("MRd address not contiguous: %h expected %h", m_addr, region_exp_addr[m_r]));
            region_exp_addr[m_r] = m_addr + m_len_dw*4;
            region_bytes[m_r]    = region_bytes[m_r] + m_len_dw*4;
            region_mrds[m_r]     = region_mrds[m_r] + 1;
        end
    end
end

// ---------------- MRd capture queue ----------------
localparam Q_DEPTH = 64;
reg [TLP_HDR_WIDTH-1:0] mrd_q [0:Q_DEPTH-1];
integer mrd_q_wr = 0;
integer mrd_q_rd = 0;

always @(negedge clk) begin
    if (!rst && tx_rd_req_tlp_valid === 1'b1 && tx_rd_req_tlp_ready === 1'b1) begin
        if ((mrd_q_wr - mrd_q_rd) == Q_DEPTH) begin
            error_count = error_count + 1;
            $display("[%0t] ERROR: MRd queue overflow", $time);
        end
        else begin
            mrd_q[mrd_q_wr % Q_DEPTH] = tx_rd_req_tlp_hdr;
            mrd_q_wr = mrd_q_wr + 1;
        end
    end
end

// ---------------- CplD responder ----------------
// Replies to MRds in queue order; list reads return entry content
// (little-endian packed), data reads return region counter dwords
// (=(addr-base)/4, each region counts from 0, int unit)
reg [TLP_HDR_WIDTH-1:0] r_hdr;
reg [63:0] r_addr;
reg [7:0]  r_tag;
integer    r_len_dw, r_beats, r_b, r_w, r_rem_bytes, r_beat_dw;
integer    r_entry, r_dw_in_entry;
reg        r_is_sg;
integer    r_region;
reg [127:0] r_entry_val;
reg [63:0]  r_region_base;
reg [31:0]  r_dword_val;

// Drive one CplD beat (NBA takes effect after posedge, sampled next beat)
task automatic cpl_drive_beat(input integer b_idx);
    begin
        r_beat_dw   = r_len_dw - b_idx*DW_PER_BEAT;
        if (r_beat_dw > DW_PER_BEAT) r_beat_dw = DW_PER_BEAT;
        r_rem_bytes = r_len_dw*4 - b_idx*DW_PER_BEAT*4;

        rx_cpl_tlp_hdr <= '0;
        rx_cpl_tlp_hdr[127:125] <= 3'b101;             // fmt = CplD (with data)
        rx_cpl_tlp_hdr[124:120] <= 5'b01010;           // type = CplD
        rx_cpl_tlp_hdr[105:96]  <= r_beat_dw[9:0];     // Length(dw)
        rx_cpl_tlp_hdr[95:80]   <= 16'h0001;           // completer id
        rx_cpl_tlp_hdr[79:77]   <= 3'b000;             // SC
        rx_cpl_tlp_hdr[75:64]   <= r_rem_bytes[11:0];  // byte count
        rx_cpl_tlp_hdr[63:48]   <= requester_id;
        rx_cpl_tlp_hdr[47:40]   <= r_tag;
        rx_cpl_tlp_hdr[38:32]   <= (b_idx == 0) ? r_addr[6:2] : 7'd0;

        for (r_w = 0; r_w < DW_PER_BEAT; r_w = r_w + 1) begin
            if (r_w < r_beat_dw) begin
                if (r_is_sg) begin
                    // Entry little-endian packing: dword k = entry >> (32*k)
                    // (DUT read side: [63:0]=addr, [95:64]=len, [127:96]=seq)
                    r_entry       = (b_idx*DW_PER_BEAT + r_w) / 4;
                    r_dw_in_entry = (b_idx*DW_PER_BEAT + r_w) % 4;
                    if (list_sel == 0)
                        r_entry_val = (r_entry < 2) ? t1_sg[r_entry] : 128'd0;
                    else
                        r_entry_val = (r_entry < 3) ? t2_sg[r_entry] : 128'd0;
                    rx_cpl_tlp_data[r_w*32 +: 32] <= r_entry_val >> (32*r_dw_in_entry);
                end
                else begin
                    // Data phase: region counter, value = (addr - region_base)/4
                    r_dword_val = (r_addr + (b_idx*DW_PER_BEAT + r_w)*4 - r_region_base) >> 2;
                    rx_cpl_tlp_data[r_w*32 +: 32] <= r_dword_val;
                end
            end
            else begin
                // Fill invalid CplD lanes with junk to verify DUT tkeep masking
                rx_cpl_tlp_data[r_w*32 +: 32] <= 32'hDEAD_BEEF;
            end
        end

        rx_cpl_tlp_error <= 4'h0;
        rx_cpl_tlp_valid <= 1'b1;
        rx_cpl_tlp_sop   <= (b_idx == 0);
        rx_cpl_tlp_eop   <= (b_idx == r_beats - 1);
    end
endtask

initial begin : cpl_responder
    forever begin
        @(negedge clk);
        if (!rst && (mrd_q_wr != mrd_q_rd)) begin
            r_hdr    = mrd_q[mrd_q_rd % Q_DEPTH];
            mrd_q_rd = mrd_q_rd + 1;

            r_len_dw = (r_hdr[105:96] == 0) ? 1024 : r_hdr[105:96];
            r_tag    = r_hdr[79:72];
            r_addr   = {r_hdr[63:2], 2'b00};

            // Classify by address: list read / data read
            r_is_sg  = (r_addr == LIST_ADDR);
            r_region = classify_region(r_addr);
            r_region_base = region_base[r_region];

            r_beats = (r_len_dw + DW_PER_BEAT - 1) / DW_PER_BEAT;

            // Random response delay of 1~3 beats
            repeat (({$random} % 3) + 1) @(negedge clk);

            // Drive beat 0
            @(posedge clk);
            cpl_drive_beat(0);

            // Following beats: driven back-to-back on the posedge of the previous handshake
            for (r_b = 1; r_b < r_beats; r_b = r_b + 1) begin
                @(negedge clk);
                while (rx_cpl_tlp_ready !== 1'b1) @(negedge clk);
                @(posedge clk);
                cpl_drive_beat(r_b);
            end

            // Last beat handshake
            @(negedge clk);
            while (rx_cpl_tlp_ready !== 1'b1) @(negedge clk);
            @(posedge clk);
            rx_cpl_tlp_valid <= 1'b0;
            rx_cpl_tlp_sop   <= 1'b0;
            rx_cpl_tlp_eop   <= 1'b0;

            // CplD gap
            repeat (4) @(negedge clk);
        end
    end
end

// ---------------- m_axis monitor ----------------
// Discriminated by DUT FSM state, gated on valid&ready handshake:
//  - S_RDRECV: list-receive phase, count valid bytes (per tkeep lane) only
//  - S_ENDL  : data phase, sample beats with valid&ready both high and
//              compare in int (dword) units against the region counter;
//              each data segment counts dwords from 0 again (cleared on
//              tlast); the partial tail dword is rounded up to one int
integer ma_bytes     = 0;     // list-phase byte count (RDRECV beats)
reg [31:0] ma_seq   = 0;     // expected dword index in current segment
integer ma_seg      = 0;     // completed data segments
integer ma_seg_dw   = 0;     // dwords received in current segment
integer ma_total_dw = 0;     // total dwords in data phase (incl. partial tail)
integer ma_tlast_cnt = 0;
integer exp_seg_num  = 0;
integer exp_seg_dw   [0:3];   // expected dwords per data segment
integer exp_total_dw = 0;
integer ma_i;
reg [31:0] ma_dw;

always @(negedge clk) begin
    if (!rst && m_axis_tlp_tvalid === 1'b1 && m_axis_tlp_tready === 1'b1) begin

        // ---- list receive phase (RDRECV): count valid bytes only ----
        // NOTE: each dword owns 4 tkeep lanes (1 per byte), the first lane of
        // dword i is tkeep[i*4] (a previous [i*8] indexing skipped the high
        // half of every beat and mis-counted the list bytes)
        if (dut.sgdma_rd_state_reg === S_RDRECV) begin
            for (ma_i = 0; ma_i < DW_PER_BEAT; ma_i = ma_i + 1) begin
                if (m_axis_tlp_tkeep[ma_i*4] === 1'b1)
                    ma_bytes = ma_bytes + 4;
            end
            if (m_axis_tlp_tlast === 1'b1)
                ma_tlast_cnt = ma_tlast_cnt + 1;
        end

        // ---- data phase (ENDL): compare per int (dword) ----
        else if (dut.sgdma_rd_state_reg === S_ENDL) begin
            // non-last data beats must keep tkeep all 1 (only the segment
            // tail beat may be partial)
            if (m_axis_tlp_tlast !== 1'b1)
                chk(m_axis_tlp_tkeep === {(TLP_DATA_WIDTH/8){1'b1}},
                    "data phase non-last beat tkeep should be all 1");

            // int-granularity extraction: a dword is consumed when its first
            // lane tkeep[ma_i*4] is valid (partial tail dword rounds up to one
            // int); tdata slice index stays ma_i*32
            for (ma_i = 0; ma_i < DW_PER_BEAT; ma_i = ma_i + 1) begin
                if (m_axis_tlp_tkeep[ma_i*4] === 1'b1) begin
                    ma_dw = m_axis_tlp_tdata[ma_i*32 +: 32];
                    chk(ma_dw === ma_seq,
                        $sformatf("m_axis data error: dword[%0d]=%h expected %h",
                                  ma_seq, ma_dw, ma_seq));
                    ma_seq      = ma_seq + 1;   // partial tail dword rounds up to one int
                    ma_seg_dw   = ma_seg_dw + 1;
                    ma_total_dw = ma_total_dw + 1;
                end
            end

            if (m_axis_tlp_tlast === 1'b1) begin
                ma_tlast_cnt = ma_tlast_cnt + 1;
                chk(ma_seg < exp_seg_num, "more data segments than expected");
                if (ma_seg < exp_seg_num)
                    chk(ma_seg_dw === exp_seg_dw[ma_seg],
                        $sformatf("segment %0d dword count %0d expected %0d",
                                  ma_seg, ma_seg_dw, exp_seg_dw[ma_seg]));
                ma_seg    = ma_seg + 1;
                ma_seg_dw = 0;
                ma_seq    = 0;   // each segment restarts the counter from 0
            end
        end
    end
end

// ---------------- Debug probe (DUT FSM transitions) ----------------
reg [4:0] dbg_state = 0;
always @(negedge clk) begin
    if (!rst && dut.sgdma_rd_state_reg !== dbg_state) begin
        $display("[%0t] PROBE sgdma_rd_state %b -> %b", $time, dbg_state, dut.sgdma_rd_state_reg);
        dbg_state = dut.sgdma_rd_state_reg;
    end
end

// ---------------- Read DMA task ----------------
// use_c: 0=no buffer C segment (test 1), 1=with buffer C segment (test 2)
task automatic rd_task(input integer list_bytes,
                       input integer n_seg,
                       input integer use_c,
                       input string name);
    integer t;
    begin
        // Reset tracking state
        for (t = 0; t < 4; t = t + 1) begin
            region_bytes[t]    = 0;
            region_mrds[t]     = 0;
            region_exp_addr[t] = region_base[t];
        end
        exp_tag     = 0;
        exp_seg_num = n_seg;
        ma_bytes = 0; ma_seq = 0; ma_seg_dw = 0;
        ma_seg = 0; ma_tlast_cnt = 0; ma_total_dw = 0;
        rd_irq_seen = 0;

        // 1. Issue the list-read descriptor (single-beat pulse)
        @(posedge clk);
        desc_tx_rdlist_length  <= list_bytes;
        desc_tx_rdlist_address <= LIST_ADDR;
        desc_tx_rdlist_start   <= 1'b1;
        @(posedge clk);
        desc_tx_rdlist_start   <= 1'b0;

        // 2. Wait for the list-received interrupt
        t = 0;
        while (!rd_irq_seen && t < 5000) begin @(posedge clk); t = t + 1; end
        chk(rd_irq_seen, {name, ": timeout waiting for tx_rd_req_irq"});
        chk(ma_bytes === list_bytes,
            $sformatf("%s: list phase byte count %0d expected %0d", name, ma_bytes, list_bytes));

        // 3. Assert the read-DMA start several cycles after the irq (per spec
        //    the DUT waits in RDRECV for this rising edge)
        repeat (RDDMA_START_DELAY) @(posedge clk);
        desc_tx_rddma_start <= 1'b1;
        @(posedge clk);
        desc_tx_rddma_start <= 1'b0;

        // 4. Data phase: wait for all data segments to complete
        t = 0;
        while (ma_seg < exp_seg_num && t < 200000) begin @(posedge clk); t = t + 1; end
        chk(ma_seg === exp_seg_num, {name, ": timeout waiting for data segments"});
        chk(ma_total_dw === exp_total_dw,
            $sformatf("%s: total data dwords %0d expected %0d", name, ma_total_dw, exp_total_dw));
        chk(ma_tlast_cnt === exp_seg_num + 1,
            $sformatf("%s: tlast count %0d expected %0d (list 1 + data %0d)",
                      name, ma_tlast_cnt, exp_seg_num + 1, exp_seg_num));

        // 5. Wait for DUT to return to IDLE (implicit null-terminated list, tail empty entries popped)
        t = 0;
        while ((dut.sgdma_rd_state_reg !== S_IDLE) && (t < 5000)) begin @(posedge clk); t = t + 1; end
        chk(dut.sgdma_rd_state_reg === S_IDLE, {name, ": DUT did not return to IDLE"});
        chk(m_axis_tlp_tvalid === 1'b0, {name, ": m_axis_tvalid should be 0 when idle"});

        // 6. Region reconciliation
        chk(region_bytes[0] === list_bytes && region_mrds[0] === 1,
            $sformatf("%s: list read %0d bytes/%0d MRds, expected %0d/1",
                      name, region_bytes[0], region_mrds[0], list_bytes));
        chk(region_bytes[1] === SEG_A_LEN && region_mrds[1] === SEG_A_LEN/512,
            $sformatf("%s: buffer A read %0d bytes/%0d MRds, expected %0d/%0d",
                      name, region_bytes[1], region_mrds[1], SEG_A_LEN, SEG_A_LEN/512));
        chk(region_bytes[2] === SEG_B_LEN && region_mrds[2] === SEG_B_LEN/512,
            $sformatf("%s: buffer B read %0d bytes/%0d MRds, expected %0d/%0d",
                      name, region_bytes[2], region_mrds[2], SEG_B_LEN, SEG_B_LEN/512));
        if (use_c == 0)
            chk(region_bytes[3] === 0 && region_mrds[3] === 0,
                $sformatf("%s: buffer C should not be read (got %0d bytes/%0d MRds)",
                          name, region_bytes[3], region_mrds[3]));
        else
            // 0x4009=16393B: 32 full MRds (16384B) + tail MRd of 9B rounded up
            // to 3dw (12B) by PCIe dword alignment
            chk(region_bytes[3] === 16396 && region_mrds[3] === 33,
                $sformatf("%s: buffer C read %0d bytes/%0d MRds, expected 16396/33 (9B tail rounded to dw)",
                          name, region_bytes[3], region_mrds[3]));

        $display("[%0t] %s: done, %0d data segments", $time, name, n_seg);
    end
endtask

// ---------------- Main test sequence ----------------
integer i;

initial begin
    // Initialize SG-list content (per spec: {seq, length bytes, start addr})
    // Test 1: 2 entries = 16KB@0xfcfc0000 + 16KB@0xfcfd0000
    t1_sg[0] = {32'd1, SEG_A_LEN, BUF_A_ADDR};
    t1_sg[1] = {32'd2, SEG_B_LEN, BUF_B_ADDR};
    // Test 2: 3 entries = 16KB@0xfcfc0000 + 16KB@0xfcfd0000 + 16393B@0xfcfe0000
    t2_sg[0] = {32'd1, SEG_A_LEN, BUF_A_ADDR};
    t2_sg[1] = {32'd2, SEG_B_LEN, BUF_B_ADDR};
    t2_sg[2] = {32'd3, SEG_C_LEN, BUF_C_ADDR};

    // Initialize region bases and tracking
    region_base[0] = LIST_ADDR;
    region_base[1] = BUF_A_ADDR;
    region_base[2] = BUF_B_ADDR;
    region_base[3] = BUF_C_ADDR;
    for (i = 0; i < 4; i = i + 1) begin
        region_exp_addr[i] = region_base[i];
        region_bytes[i]    = 0;
        region_mrds[i]     = 0;
        exp_seg_dw[i]      = 0;
    end

    // Reset
    rst = 1;
    repeat (100) @(posedge clk);
    rst = 0;
    repeat (100) @(posedge clk);   // wait for XPM reset to complete

    // ================ Test 1: 256bit list (2 entries) ================
    $display("\n[T1] list @%h (32B): entry1 16KB@%h + entry2 16KB@%h",
             LIST_ADDR, BUF_A_ADDR, BUF_B_ADDR);
    list_sel = 0;
    exp_seg_dw[0] = SEG_A_LEN/4;                       // 4096 dwords
    exp_seg_dw[1] = SEG_B_LEN/4;                       // 4096 dwords
    exp_total_dw = SEG_A_LEN/4 + SEG_B_LEN/4;          // 4096+4096=8192
    rd_task(LIST_BYTES_T1, 2, 0, "T1");
    repeat (100) @(posedge clk);

    // ================ Test 2: 384bit list (3 entries) ================
    $display("\n[T2] list @%h (48B): entry1 16KB@%h + entry2 16KB@%h + entry3 16393B@%h",
             LIST_ADDR, BUF_A_ADDR, BUF_B_ADDR, BUF_C_ADDR);
    list_sel = 1;
    exp_seg_dw[0] = SEG_A_LEN/4;                       // 4096 dwords
    exp_seg_dw[1] = SEG_B_LEN/4;                       // 4096 dwords
    exp_seg_dw[2] = SEG_C_LEN/4 + 1;                   // 4098 full + 1 partial (rounded to int)
    exp_total_dw = SEG_A_LEN/4 + SEG_B_LEN/4 + 4099;   // 4096+4096+(4098 full+1 partial)
    rd_task(LIST_BYTES_T2, 3, 1, "T2");
    repeat (100) @(posedge clk);

    // ---------------- Summary ----------------
    $display("\n================ SUMMARY ================");
    $display("T1: 16KB@%h + 16KB@%h, m_axis dwords 0..4095 twice (each segment from 0)",
             BUF_A_ADDR, BUF_B_ADDR);
    $display("T2: 16KB@%h + 16KB@%h + 16393B@%h, last partial dword checked per byte",
             BUF_A_ADDR, BUF_B_ADDR, BUF_C_ADDR);
    if (error_count == 0)
        $display("RESULT: *** TEST PASSED ***");
    else
        $display("RESULT: *** TEST FAILED, %0d errors ***", error_count);
    $finish;
end

// ---------------- Global watchdog ----------------
initial begin
    #20_000_000;
    $display("[%0t] ERROR: global simulation timeout", $time);
    error_count = error_count + 1;
    $display("RESULT: *** TEST FAILED, %0d errors ***", error_count);
    $finish;
end

endmodule

`resetall
