/****************************************************************************
 * @file    tb_sgdma_if_pcie_axis.sv
 * @brief   sgdma_if_pcie_axis 模块 testbench - C2H写DMA + H2C读DMA内存回环
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 1.3
 * @date    2026-09-02
 * 
 * @par 修改记录:
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |  2026-09-02   |   v1.0      |    zzhi          |   按tb_sgdma_if_pcie_axis.md规范实现 |
 * |  2026-09-02   |   v1.1      |    zzhi          |   sgdma_start时序修改: 对应irq拉高后4个时钟周期单拍脉冲开启DMA |
 * |  2026-09-02   |   v1.2      |    zzhi          |   修复wait_level条件按值拷贝导致irq脉冲被漏采, sgdma_start迟迟不拉高 |
 * |  2026-09-02   |   v1.3      |    zzhi          |   m_axis仅在sgdma_start后采集: 链表取回阶段valid直通泄漏不参与对账 |
 * |---------------|-------------|------------------|------------------------|
 *
 * @par 验证内容 (按md测试用例):
 * ___________________________________________________________________________
 * | 编号 | 测试项                                                          |
 * |------|-----------------------------------------------------------------|
 * | T1   | C2H写DMA: 链表3entry(4KB@0xcfce0000/0xfcfc0000/0xa1000000),     |
 * |      | 共12KB, 链表存放于0xdcff0000(48字节);                           |
 * |      | 检查mwr数据以int为单位逐次递增, 且按链表顺序写入对应内存区域      |
 * | T2   | H2C读DMA: 同一3entry链表(链表存放于0xdcfc0000);                  |
 * |      | 检查m_axis读出数据以int为单位逐次递增, 与mwr写入内存的数据一致   |
 * |------|-----------------------------------------------------------------|
 *
 * @par 平台模型:
 *   1. 关联数组模拟64bit主机内存(dword粒度), mwr写入/mrd读出均经过该内存
 *   2. mrd应答器: 捕获进程队列化mrd, 应答进程按发出顺序原序回CplD
 *      (与sgdma_if_pcie_ctrl按发出顺序路由的语义匹配), 单CplD回满mrd长度,
 *      tag/requester id原样回显
 *   3. send_axis产生递增int数据流(0,1,2,...)作为C2H用户数据
 *   4. 链表entry(16字节): [63:0]起始地址, [95:64]长度(字节), [127:96]序号
 * ***************************************************************************/

`timescale 1ns/1ps

module tb_sgdma_if_pcie_axis;

// ---------------- 参数 ----------------
parameter TLP_DATA_WIDTH   = 512;
parameter TLP_STRB_WIDTH   = TLP_DATA_WIDTH/32;
parameter TLP_HDR_WIDTH    = 128;
parameter TLP_SEG_COUNT    = 1;
parameter PCIE_ADDR_WIDTH  = 64;
parameter TX_SEQ_NUM_WIDTH = 6;

localparam DW_PER_BEAT = TLP_DATA_WIDTH/32;      // 每拍16个dword

// 测试内存布局 (按md测试用例)
localparam [63:0] REGION0_ADDR  = 64'h0000_0000_cfce_0000;
localparam [63:0] REGION1_ADDR  = 64'h0000_0000_fcfc_0000;
localparam [63:0] REGION2_ADDR  = 64'h0000_0000_a100_0000;
localparam [63:0] WR_SGLIST_ADDR = 64'h0000_0000_dcff_0000;   // T1链表存放地址
localparam [63:0] RD_SGLIST_ADDR = 64'h0000_0000_dcfc_0000;   // T2链表存放地址
localparam ENTRY_NUM   = 3;
localparam ENTRY_SIZE  = 4096;                   // 字节
localparam TOTAL_BYTES = ENTRY_NUM*ENTRY_SIZE;   // 12KB
localparam TOTAL_DW    = TOTAL_BYTES/4;          // 3072个int
localparam SGLIST_BYTES = ENTRY_NUM*16;          // 48字节
localparam IRQ_TO_START_DELAY = 4;               // irq拉高后延迟的时钟周期数

// ---------------- 时钟复位 ----------------
reg clk = 0;
reg rst = 1;

always #2 clk = ~clk;                            // 250MHz

// ---------------- DUT 连线 ----------------
// mwr输出(到主机内存模型)
wire [TLP_HDR_WIDTH-1:0]    tx_wr_req_tlp_hdr;
wire [TX_SEQ_NUM_WIDTH-1:0] tx_wr_req_tlp_seq;
wire [TLP_DATA_WIDTH-1:0]   tx_wr_req_tlp_data;
wire [TLP_STRB_WIDTH-1:0]   tx_wr_req_tlp_strb;
wire                        tx_wr_req_tlp_valid;
wire                        tx_wr_req_tlp_sop;
wire                        tx_wr_req_tlp_eop;
reg                         tx_wr_req_tlp_ready = 1'b1;

// mrd输出(到主机内存模型)
wire [TLP_HDR_WIDTH-1:0]    tx_rd_req_tlp_hdr;
wire [TX_SEQ_NUM_WIDTH-1:0] tx_rd_req_tlp_seq;
wire                        tx_rd_req_tlp_valid;
wire                        tx_rd_req_tlp_sop;
wire                        tx_rd_req_tlp_eop;
reg                         tx_rd_req_tlp_ready = 1'b1;

// cpld输入(主机内存模型应答)
reg  [TLP_HDR_WIDTH-1:0]  rx_cpl_tlp_hdr   = '0;
reg  [TLP_DATA_WIDTH-1:0] rx_cpl_tlp_data  = '0;
reg  [3:0]                rx_cpl_tlp_error = '0;
reg                       rx_cpl_tlp_valid = 1'b0;
reg                       rx_cpl_tlp_sop   = 1'b0;
reg                       rx_cpl_tlp_eop   = 1'b0;
wire                      rx_cpl_tlp_ready;

// 描述符接口
reg  [31:0]           desc_wr_req_sglist_length  = '0;
reg  [PCIE_ADDR_WIDTH-1:0] desc_wr_req_sglist_address = '0;
reg                   desc_wr_req_sglist_start   = 1'b0;
reg                   desc_wr_req_sgdma_start    = 1'b0;

reg  [31:0]           desc_rd_req_sglist_length  = '0;
reg  [PCIE_ADDR_WIDTH-1:0] desc_rd_req_sglist_address = '0;
reg                   desc_rd_req_sglist_start   = 1'b0;
reg                   desc_rd_req_sgdma_start    = 1'b0;

wire tx_wr_sglist_irq;
wire tx_rd_sglist_irq;

reg  [15:0] requester_id        = 16'h0100;
reg  [2:0]  MaxPayloadSize      = 3'b010;        // 512字节
reg  [2:0]  max_read_payloadSize = 3'b010;       // 512字节

// C2H用户数据(send_axis驱动)
wire [TLP_DATA_WIDTH-1:0]   s_axis_tlp_tdata;
wire [TLP_DATA_WIDTH/8-1:0] s_axis_tlp_tkeep;
wire                        s_axis_tlp_tvalid;
wire                        s_axis_tlp_tlast;
wire                        s_axis_tlp_tready;
reg  [31:0]                 st_length = '0;
reg                         st_start  = 1'b0;
wire                        st_end;

// H2C数据输出(采集校验)
wire [TLP_DATA_WIDTH-1:0]   m_axis_tlp_tdata;
wire [TLP_DATA_WIDTH/8-1:0] m_axis_tlp_tkeep;
wire                        m_axis_tlp_tvalid;
wire                        m_axis_tlp_tlast;
reg                         m_axis_tlp_tready = 1'b1;

// ---------------- DUT 例化 ----------------
sgdma_if_pcie_axis #(
    .TLP_DATA_WIDTH    (TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH    (TLP_STRB_WIDTH),
    .TLP_HDR_WIDTH     (TLP_HDR_WIDTH),
    .TLP_SEG_COUNT     (TLP_SEG_COUNT),
    .PCIE_ADDR_WIDTH   (PCIE_ADDR_WIDTH),
    .TX_SEQ_NUM_WIDTH  (TX_SEQ_NUM_WIDTH)
) dut (
    .clk                     (clk),
    .rst                     (rst),

    .tx_wr_req_tlp_hdr       (tx_wr_req_tlp_hdr),
    .tx_wr_req_tlp_seq       (tx_wr_req_tlp_seq),
    .tx_wr_req_tlp_data      (tx_wr_req_tlp_data),
    .tx_wr_req_tlp_strb      (tx_wr_req_tlp_strb),
    .tx_wr_req_tlp_valid     (tx_wr_req_tlp_valid),
    .tx_wr_req_tlp_sop       (tx_wr_req_tlp_sop),
    .tx_wr_req_tlp_eop       (tx_wr_req_tlp_eop),
    .tx_wr_req_tlp_ready     (tx_wr_req_tlp_ready),

    .tx_rd_req_tlp_hdr       (tx_rd_req_tlp_hdr),
    .tx_rd_req_tlp_seq       (tx_rd_req_tlp_seq),
    .tx_rd_req_tlp_valid     (tx_rd_req_tlp_valid),
    .tx_rd_req_tlp_sop       (tx_rd_req_tlp_sop),
    .tx_rd_req_tlp_eop       (tx_rd_req_tlp_eop),
    .tx_rd_req_tlp_ready     (tx_rd_req_tlp_ready),

    .rx_cpl_tlp_data         (rx_cpl_tlp_data),
    .rx_cpl_tlp_hdr          (rx_cpl_tlp_hdr),
    .rx_cpl_tlp_error        (rx_cpl_tlp_error),
    .rx_cpl_tlp_valid        (rx_cpl_tlp_valid),
    .rx_cpl_tlp_sop          (rx_cpl_tlp_sop),
    .rx_cpl_tlp_eop          (rx_cpl_tlp_eop),
    .rx_cpl_tlp_ready        (rx_cpl_tlp_ready),

    .desc_wr_req_sglist_length   (desc_wr_req_sglist_length),
    .desc_wr_req_sglist_address  (desc_wr_req_sglist_address),
    .desc_wr_req_sglist_start    (desc_wr_req_sglist_start),
    .desc_wr_req_sgdma_start     (desc_wr_req_sgdma_start),

    .desc_rd_req_sglist_length   (desc_rd_req_sglist_length),
    .desc_rd_req_sglist_address  (desc_rd_req_sglist_address),
    .desc_rd_req_sglist_start    (desc_rd_req_sglist_start),
    .desc_rd_req_sgdma_start     (desc_rd_req_sgdma_start),

    .tx_wr_sglist_irq        (tx_wr_sglist_irq),
    .tx_rd_sglist_irq        (tx_rd_sglist_irq),
    .requester_id            (requester_id),
    .MaxPayloadSize          (MaxPayloadSize),
    .max_read_payloadSize    (max_read_payloadSize),

    .s_axis_tlp_tdata        (s_axis_tlp_tdata),
    .s_axis_tlp_tkeep        (s_axis_tlp_tkeep),
    .s_axis_tlp_tvalid       (s_axis_tlp_tvalid),
    .s_axis_tlp_tlast        (s_axis_tlp_tlast),
    .s_axis_tlp_tready       (s_axis_tlp_tready),

    .m_axis_tlp_tdata        (m_axis_tlp_tdata),
    .m_axis_tlp_tkeep        (m_axis_tlp_tkeep),
    .m_axis_tlp_tvalid       (m_axis_tlp_tvalid),
    .m_axis_tlp_tlast        (m_axis_tlp_tlast),
    .m_axis_tlp_tready       (m_axis_tlp_tready)
);

// ---------------- send_axis 例化 (C2H用户数据源) ----------------
send_axis #(
    .STREAM_TDATA_WIDTH (TLP_DATA_WIDTH),
    .STREAM_TKEEP_WIDTH (TLP_DATA_WIDTH/8)
) send_axis_inst (
    .m_axis_aclk    (clk),
    .m_axis_aresetn (~rst),

    .st_length      (st_length),
    .st_start       (st_start),
    .st_end         (st_end),

    .m_axis_tdata   (s_axis_tlp_tdata),
    .m_axis_tkeep   (s_axis_tlp_tkeep),
    .m_axis_tlast   (s_axis_tlp_tlast),
    .m_axis_tvalid  (s_axis_tlp_tvalid),
    .m_axis_tready  (s_axis_tlp_tready)
);

// ---------------- 统计 ----------------
integer error_count = 0;
integer mrd_cnt = 0;          // 已应答mrd数
integer mwr_tlp_cnt = 0;      // 已收到mwr TLP数
integer wr_dw_total = 0;      // mwr累计dword数
integer rd_dw_total = 0;      // m_axis累计dword数
integer rd_tlast_cnt = 0;     // m_axis tlast次数(每entry一次)
integer mem_miss_cnt = 0;     // 内存读未命中数
integer wr_stream_done = 0;   // send_axis发送完成标志

// ---------------- 检查任务 ----------------
task chk(input cond, input string msg);
    begin
        if (cond !== 1'b1) begin
            error_count = error_count + 1;
            $display("[%0t] ERROR: %s (mrd=%0d mwr=%0d wr_dw=%0d rd_dw=%0d)",
                     $time, msg, mrd_cnt, mwr_tlp_cnt, wr_dw_total, rd_dw_total);
        end
    end
endtask

// ---------------- 主机内存模型 ----------------
// dword粒度, 按dword对齐字节地址索引
reg [31:0] pcie_mem [bit [63:0]];

function [31:0] mem_read(input [63:0] a);
    begin
        if (pcie_mem.exists({a[63:2], 2'b00})) begin
            mem_read = pcie_mem[{a[63:2], 2'b00}];
        end
        else begin
            mem_read = 32'hdead_beef;
            mem_miss_cnt = mem_miss_cnt + 1;
        end
    end
endfunction

function mem_write(input [63:0] a, input [31:0] d);
    begin
        pcie_mem[{a[63:2], 2'b00}] = d;
    end
endfunction

// 链表预载: entry(16字节) = {[127:96]序号, [95:64]长度, [63:0]起始地址}
// 内存dword序(地址递增): 地址低32bit, 地址高32bit, 长度, 序号
task sglist_write(input [63:0] base);
    integer k;
    reg [63:0] eaddr;
    begin
        for (k = 0; k < ENTRY_NUM; k = k + 1) begin
            case (k % 3)
                0: eaddr = REGION0_ADDR;
                1: eaddr = REGION1_ADDR;
                2: eaddr = REGION2_ADDR;
            endcase
            mem_write(base + 64'd16*k       , eaddr[31:0]);
            mem_write(base + 64'd16*k + 64'd4, eaddr[63:32]);
            mem_write(base + 64'd16*k + 64'd8, ENTRY_SIZE[31:0]);
            mem_write(base + 64'd16*k + 64'd12, (k+1));        // 序号非零(全0为终止符)
        end
    end
endtask

// ---------------- mrd捕获队列 ----------------
// 应答进程可能正忙于上一笔CplD, 单拍valid必须先入队缓存
localparam QDEPTH = 64;
reg [7:0]  mrdq_tag  [0:QDEPTH-1];
reg [31:0] mrdq_len  [0:QDEPTH-1];    // 长度(dw)
reg [63:0] mrdq_addr [0:QDEPTH-1];
reg [15:0] mrdq_rid  [0:QDEPTH-1];
integer mrdq_wr = 0;
integer mrdq_rd = 0;

// mrd捕获: MRd为单拍TLP(fmt=001), 握手拍采样入队
always @(negedge clk) begin
    if (!rst && (tx_rd_req_tlp_valid === 1'b1) && (tx_rd_req_tlp_ready === 1'b1)) begin
        chk(tx_rd_req_tlp_sop === 1'b1 && tx_rd_req_tlp_eop === 1'b1, "mrd not single beat");
        chk(tx_rd_req_tlp_hdr[127:125] === 3'b001, "mrd fmt mismatch");
        chk(tx_rd_req_tlp_hdr[124:120] === 5'b00000, "mrd type mismatch");
        chk(mrdq_wr - mrdq_rd < QDEPTH, "mrd queue overflow");

        mrdq_tag [mrdq_wr % QDEPTH] = tx_rd_req_tlp_hdr[79:72];
        mrdq_len [mrdq_wr % QDEPTH] = (tx_rd_req_tlp_hdr[105:96] == 10'd0) ? 32'd1024
                                                    : {22'd0, tx_rd_req_tlp_hdr[105:96]};
        mrdq_addr[mrdq_wr % QDEPTH] = {tx_rd_req_tlp_hdr[63:2], 2'b00};
        mrdq_rid [mrdq_wr % QDEPTH] = tx_rd_req_tlp_hdr[95:80];
        mrdq_wr = mrdq_wr + 1;
        mrd_cnt = mrd_cnt + 1;
    end
end

// ---------------- CplD发送任务 ----------------
// 按mrd请求长度回单条CplD(可多拍), 数据取自内存模型
// 握手方式: negedge读取ready(即下一posedge采样值), 握手拍NBA直接驱动下一拍
task automatic send_cpl_tlp(input [63:0] addr, input integer len_dw,
                            input [7:0] tag, input [15:0] req_id);
    integer beats, b, k, g;
    begin
        beats = (len_dw + DW_PER_BEAT - 1) / DW_PER_BEAT;

        // 驱动第0拍
        @(posedge clk);
        rx_cpl_tlp_hdr <= '0;
        rx_cpl_tlp_hdr[127:125] <= 3'b101;                     // fmt = CplD
        rx_cpl_tlp_hdr[124:120] <= 5'b01010;                   // type = CplD
        rx_cpl_tlp_hdr[95:80]   <= 16'h0001;                   // completer id
        rx_cpl_tlp_hdr[79:77]   <= 3'b000;                     // status = SC
        rx_cpl_tlp_hdr[75:64]   <= (len_dw*4 >= 4096) ? 12'd0 : len_dw*4;   // byte count
        rx_cpl_tlp_hdr[63:48]   <= req_id;                     // requester id回显
        rx_cpl_tlp_hdr[47:40]   <= tag;                        // tag回显
        rx_cpl_tlp_hdr[38:32]   <= addr[6:2];                  // lower address

        for (k = 0; k < DW_PER_BEAT; k = k + 1)
            rx_cpl_tlp_data[k*32 +: 32] <= mem_read(addr + 64'd4*k);
        rx_cpl_tlp_error <= 4'h0;
        rx_cpl_tlp_valid <= 1'b1;
        rx_cpl_tlp_sop   <= 1'b1;
        rx_cpl_tlp_eop   <= (beats == 1);

        // 中间各拍: 上一拍握手posedge的NBA驱动, 背靠背
        b = 0;
        while (b + 1 < beats) begin
            @(negedge clk);
            while (rx_cpl_tlp_ready !== 1'b1) @(negedge clk);
            @(posedge clk);                                     // 本拍握手完成
            b = b + 1;
            for (k = 0; k < DW_PER_BEAT; k = k + 1) begin
                g = b*DW_PER_BEAT + k;
                rx_cpl_tlp_data[k*32 +: 32] <= (g < len_dw) ? mem_read(addr + 64'd4*g) : 32'h0;
            end
            rx_cpl_tlp_sop <= 1'b0;
            rx_cpl_tlp_eop <= (b == beats - 1);
        end

        // 最后一拍握手
        @(negedge clk);
        while (rx_cpl_tlp_ready !== 1'b1) @(negedge clk);
        @(posedge clk);                                         // 本拍握手完成
        rx_cpl_tlp_valid <= 1'b0;
        rx_cpl_tlp_sop   <= 1'b0;
        rx_cpl_tlp_eop   <= 1'b0;
    end
endtask

// ---------------- mrd应答进程(严格按发出顺序) ----------------
initial begin
    forever begin
        @(negedge clk);
        if (!rst && (mrdq_rd != mrdq_wr)) begin
            send_cpl_tlp(mrdq_addr[mrdq_rd % QDEPTH], mrdq_len[mrdq_rd % QDEPTH],
                         mrdq_tag [mrdq_rd % QDEPTH], mrdq_rid [mrdq_rd % QDEPTH]);
            mrdq_rd = mrdq_rd + 1;
        end
    end
end

// ---------------- mwr监视: 写内存 + int递增检查 ----------------
// strb为dword有效位(由s_axis tkeep派生), sop拍解析头, 按序写入内存模型
integer mwr_beat_dw;
reg [63:0] mwr_base;
reg [31:0] mwr_dw;
integer mwr_k;

always @(negedge clk) begin
    if (!rst && (tx_wr_req_tlp_valid === 1'b1) && (tx_wr_req_tlp_ready === 1'b1)) begin
        if (tx_wr_req_tlp_sop === 1'b1) begin
            chk(tx_wr_req_tlp_hdr[127:125] === 3'b011, "mwr fmt mismatch");
            chk(tx_wr_req_tlp_hdr[124:120] === 5'b00000, "mwr type mismatch");
            mwr_base    = {tx_wr_req_tlp_hdr[63:2], 2'b00};
            mwr_beat_dw = 0;
            mwr_tlp_cnt = mwr_tlp_cnt + 1;
        end

        for (mwr_k = 0; mwr_k < DW_PER_BEAT; mwr_k = mwr_k + 1) begin
            if (tx_wr_req_tlp_strb[mwr_k] === 1'b1) begin
                mwr_dw = tx_wr_req_tlp_data[mwr_k*32 +: 32];
                // md用例1: mwr数据以int为单位逐次递增
                chk(mwr_dw === wr_dw_total[31:0],
                    $sformatf("mwr int pattern mismatch: dw=%0h expect %0d", mwr_dw, wr_dw_total));
                mem_write(mwr_base + 64'd4*mwr_beat_dw, mwr_dw);
                wr_dw_total  = wr_dw_total + 1;
                mwr_beat_dw  = mwr_beat_dw + 1;
            end
        end
    end
end

// ---------------- H2C数据采集: int递增检查 ----------------
// md用例2: 读出数据以int为单位逐次递增, 与mwr写入内存的数据一致
// 注意: rd引擎的m_axis是cpld_rx_axis的直通镜像, 链表取回阶段(SGDMA_RDRECV)
// 链表CplD数据也会出现在m_axis上(valid泄漏), 按设计约定仅在sgdma_start
// 之后采集校验: 第一个512bit拍为int 0x0~0xf, 第二拍为0x10~0x1f, 依次递增
reg [31:0] rd_dw;
integer rd_k;
reg rd_data_phase = 0;         // sgdma_start之后进入数据接收阶段

always @(posedge clk) begin
    if (rst) begin
        rd_data_phase <= 1'b0;
    end
    else if (desc_rd_req_sgdma_start === 1'b1) begin
        rd_data_phase <= 1'b1;
    end
end

always @(negedge clk) begin
    if (!rst && (rd_data_phase === 1'b1)
             && (m_axis_tlp_tvalid === 1'b1) && (m_axis_tlp_tready === 1'b1)) begin
        for (rd_k = 0; rd_k < DW_PER_BEAT; rd_k = rd_k + 1) begin
            if (m_axis_tlp_tkeep[rd_k*4 +: 4] === 4'hF) begin
                rd_dw = m_axis_tlp_tdata[rd_k*32 +: 32];
                chk(rd_dw === rd_dw_total[31:0],
                    $sformatf("m_axis int pattern mismatch: dw=%0h expect %0d", rd_dw, rd_dw_total));
                rd_dw_total = rd_dw_total + 1;
            end
        end
        if (m_axis_tlp_tlast === 1'b1) begin
            rd_tlast_cnt = rd_tlast_cnt + 1;
        end
    end
end

// send_axis发送完成脉冲锁存
always @(posedge clk) begin
    if (rst) begin
        wr_stream_done <= 1'b0;
    end
    else if (st_end === 1'b1) begin
        wr_stream_done <= 1'b1;
    end
end

// ---------------- 等待辅助任务 ----------------
// 注意: 等待条件不能以input传入(input在调用时按值拷贝, 之后不再更新),
// 必须在任务体内直接读取live信号/变量, 否则会漏采单拍脉冲
task automatic wait_wr_irq(input integer max_cycles);
    integer t;
    begin
        t = 0;
        while ((tx_wr_sglist_irq !== 1'b1) && (t < max_cycles)) begin
            @(posedge clk);
            t = t + 1;
        end
        chk(tx_wr_sglist_irq === 1'b1,
            $sformatf("T1: tx_wr_sglist_irq timeout (waited %0d cycles)", t));
    end
endtask

task automatic wait_rd_irq(input integer max_cycles);
    integer t;
    begin
        t = 0;
        while ((tx_rd_sglist_irq !== 1'b1) && (t < max_cycles)) begin
            @(posedge clk);
            t = t + 1;
        end
        chk(tx_rd_sglist_irq === 1'b1,
            $sformatf("T2: tx_rd_sglist_irq timeout (waited %0d cycles)", t));
    end
endtask

task automatic wait_wr_drain(input integer max_cycles);
    integer t;
    begin
        t = 0;
        while (((wr_dw_total != TOTAL_DW) || (wr_stream_done !== 1'b1)) && (t < max_cycles)) begin
            @(posedge clk);
            t = t + 1;
        end
        chk((wr_dw_total == TOTAL_DW) && (wr_stream_done === 1'b1),
            $sformatf("T1: write DMA drain timeout (wr_dw=%0d stream_done=%0d)",
                      wr_dw_total, wr_stream_done));
    end
endtask

task automatic wait_rd_drain(input integer max_cycles);
    integer t;
    begin
        t = 0;
        while ((rd_dw_total != TOTAL_DW) && (t < max_cycles)) begin
            @(posedge clk);
            t = t + 1;
        end
        chk(rd_dw_total == TOTAL_DW,
            $sformatf("T2: read DMA drain timeout (rd_dw=%0d)", rd_dw_total));
    end
endtask

// ---------------- 主测试序列 ----------------
integer k;
reg [63:0] base;

initial begin
    rst = 1;
    repeat (16) @(posedge clk);
    rst = 0;
    repeat (32) @(posedge clk);       // 等待xpm复位完成

    // ======== 链表预载到主机内存 ========
    sglist_write(WR_SGLIST_ADDR);
    sglist_write(RD_SGLIST_ADDR);
    $display("\nMemory model: wr sglist @%h, rd sglist @%h, %0d entries x %0d bytes",
             WR_SGLIST_ADDR, RD_SGLIST_ADDR, ENTRY_NUM, ENTRY_SIZE);

    // ======== T1: C2H写DMA (md用例1) ========
    $display("\n[T1] C2H write DMA: %0d bytes via %0d entries", TOTAL_BYTES, ENTRY_NUM);

    // 1. 启动链表读取: 链表位于0xdcff0000, 长度48字节
    @(posedge clk);
    desc_wr_req_sglist_address <= WR_SGLIST_ADDR;
    desc_wr_req_sglist_length  <= SGLIST_BYTES;
    desc_wr_req_sglist_start   <= 1'b1;
    @(posedge clk);
    desc_wr_req_sglist_start   <= 1'b0;

    // 2. 等待链表取回完成irq
    wait_wr_irq(10000);

    // 3. 启动用户数据流(递增int); sgdma_start在irq拉高后隔4个时钟周期
    //    拉高一个时钟周期开启写DMA(新要求)
    fork
        begin
            @(posedge clk);
            st_length <= TOTAL_BYTES;
            st_start  <= 1'b1;
            @(posedge clk);
            st_start  <= 1'b0;
        end
        begin
            repeat (IRQ_TO_START_DELAY) @(posedge clk);
            desc_wr_req_sgdma_start <= 1'b1;
            @(posedge clk);
            desc_wr_req_sgdma_start <= 1'b0;
        end
    join

    // 4. 等待12KB全部写入内存
    wait_wr_drain(200000);

    // 5. 检查总量与mwr TLP数
    chk(wr_dw_total == TOTAL_DW, "T1: mwr total dword count mismatch");
    chk(mwr_tlp_cnt == TOTAL_BYTES/512, "T1: mwr TLP count mismatch (expect 24 x 512B)");
    $display("[T1] mwr TLPs=%0d, dwords=%0d, mem read miss=%0d",
             mwr_tlp_cnt, wr_dw_total, mem_miss_cnt);

    // 6. 按链表顺序核对内存: 3个区域依次存放递增int 0..3071
    for (k = 0; k < TOTAL_DW; k = k + 1) begin
        case (k / (ENTRY_SIZE/4))
            0: base = REGION0_ADDR;
            1: base = REGION1_ADDR;
            2: base = REGION2_ADDR;
        endcase
        chk(mem_read(base + 64'd4*(k % (ENTRY_SIZE/4))) === k[31:0],
            $sformatf("T1: region data mismatch @%h idx=%0d", base, k));
    end
    $display("[T1] region check done: 0x%h/0x%h/0x%h each %0d ints",
             REGION0_ADDR, REGION1_ADDR, REGION2_ADDR, ENTRY_SIZE/4);

    // ======== T2: H2C读DMA (md用例2) ========
    $display("\n[T2] H2C read DMA: %0d bytes via %0d entries", TOTAL_BYTES, ENTRY_NUM);

    // 1. 启动链表读取: 链表位于0xdcfc0000, 长度48字节
    @(posedge clk);
    desc_rd_req_sglist_address <= RD_SGLIST_ADDR;
    desc_rd_req_sglist_length  <= SGLIST_BYTES;
    desc_rd_req_sglist_start   <= 1'b1;
    @(posedge clk);
    desc_rd_req_sglist_start   <= 1'b0;

    // 2. 等待链表取回完成irq
    wait_rd_irq(10000);

    // 3. sgdma_start在irq拉高后隔4个时钟周期拉高一个时钟周期开启读DMA(新要求)
    repeat (IRQ_TO_START_DELAY) @(posedge clk);
    desc_rd_req_sgdma_start <= 1'b1;
    @(posedge clk);
    desc_rd_req_sgdma_start <= 1'b0;

    // 4. 等待12KB全部从m_axis读出
    wait_rd_drain(200000);

    // 5. 检查总量 (int递增已在采集进程中逐拍核对)
    chk(rd_dw_total == TOTAL_DW, "T2: m_axis total dword count mismatch");
    chk(rd_tlast_cnt == ENTRY_NUM, "T2: m_axis tlast count mismatch (expect 1 per entry)");
    $display("[T2] mrd answered=%0d, m_axis dwords=%0d, tlast=%0d, mem read miss=%0d",
             mrd_cnt, rd_dw_total, rd_tlast_cnt, mem_miss_cnt);

    // ======== 汇总 ========
    $display("\n================ SUMMARY ================");
    $display("mrd answered     : %0d (1 wr sglist + 1 rd sglist + 24 data)", mrd_cnt);
    $display("mwr TLPs         : %0d", mwr_tlp_cnt);
    $display("C2H dwords wrote : %0d", wr_dw_total);
    $display("H2C dwords read  : %0d", rd_dw_total);
    $display("mem read miss    : %0d", mem_miss_cnt);
    if (error_count == 0)
        $display("RESULT: *** TEST PASSED ***");
    else
        $display("RESULT: *** TEST FAILED, %0d errors ***", error_count);
    $finish;
end

// ---------------- 看门狗 ----------------
initial begin
    #80000;                                          // 800us
    $display("[%0t] FATAL: global watchdog timeout", $time);
    $display("RESULT: *** TEST FAILED (timeout) ***");
    $finish;
end

endmodule
