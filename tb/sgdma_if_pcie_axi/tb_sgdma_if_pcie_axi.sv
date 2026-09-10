/****************************************************************************
 * @file    tb_sgdma_if_pcie_axi.sv
 * @brief   sgdma_if_pcie_axi 模块 testbench - AXI内存映射版C2H写DMA + H2C读DMA回环
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2026-09-07
 *
 * @par 修改记录:
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |  2026-09-07   |   v1.0      |    zzhi          | 按tb_sgdma_if_pcie_axis.md规范实现, |
 * |               |             |                  | s_axis/m_axis替换为AXI4主接口内存模型 |
 * |---------------|-------------|------------------|------------------------|
 *
 * @par 验证内容 (按md测试用例, AXIS接口替换为AXI内存映射接口):
 * ___________________________________________________________________________
 * | 编号 | 测试项                                                          |
 * |------|-----------------------------------------------------------------|
 * | T1   | H2C读DMA先行: 链表3entry(4KB@0xcfce0000/0xfcfc0000/0xa1000000),  |
 * |      | 共12KB, 链表@0xdcfc0000(48字节); 等待H2C完成后数据以AXI格式     |
 * |      | 存入回环RAM@0x00100000, 核对RAM内为递增int 0..3071              |
 * | T2   | C2H写DMA回读: 从T1写入的同一AXI RAM取读出, 链表@0xdcff0000指向  |
 * |      | 主机regions B(0x2cfce0000/...); 检查mwr以int为单位逐次递增,      |
 * |      | 且按链表顺序写入对应主机区域(与H2C写入AXI RAM的数据一致)         |
 * | T3   | C2H和H2C同时工作(不同主机区域/不同AXI区域保证确定性):            |
 * |      | ctrl的mrd多路仲裁并发工作, 读写数据仍逐int递增,                   |
 * |      | AXI侧数据比对在sgdma_start拉高之后进行                            |
 * |------|-----------------------------------------------------------------|
 *
 * @par 平台模型:
 *   1. 关联数组模拟64bit主机内存(dword粒度), mwr写入/mrd读出均经过该内存
 *   2. 关联数组模拟32bit AXI内存(dword粒度), C2H数据源/H2C数据落盘
 *   3. mrd应答器: 捕获进程队列化mrd, 应答进程按发出顺序原序回CplD
 *      (与sgdma_if_pcie_ctrl按发出顺序路由的语义匹配), 单CplD回满mrd长度,
 *      tag/requester id原样回显
 *   4. AXI读从机: 队列化AR, 原序回R突起(rlast收尾), 数据取自AXI内存
 *   5. AXI写从机: AW入队, W拍按wstrb写入AXI内存并逐int比对, wlast后回B
 *   6. 链表entry(16字节): [63:0]起始地址, [95:64]长度(字节), [127:96]序号
 *      (全0为终止符)
 * ***************************************************************************/

`timescale 1ns/1ps

module tb_sgdma_if_pcie_axi;

// ---------------- 参数 ----------------
parameter TLP_DATA_WIDTH   = 512;
parameter TLP_STRB_WIDTH   = TLP_DATA_WIDTH/32;
parameter TLP_HDR_WIDTH    = 128;
parameter TLP_SEG_COUNT    = 1;
parameter PCIE_ADDR_WIDTH  = 64;
parameter TX_SEQ_NUM_COUNT = 1;
parameter TX_SEQ_NUM_WIDTH = 6;
parameter PCIE_TAG_COUNT   = 32;
parameter OP_TABLE_SIZE    = PCIE_TAG_COUNT;

parameter AXI_DATA_WIDTH   = 512;
parameter AXI_STRB_WIDTH   = AXI_DATA_WIDTH/8;
parameter AXI_ADDR_WIDTH   = 32;
parameter AXI_ID_WIDTH     = 8;

localparam DW_PER_BEAT = TLP_DATA_WIDTH/32;      // 每拍16个dword
localparam AXI_DW_PER_BEAT = AXI_DATA_WIDTH/32;  // AXI每拍16个dword

// 测试内存布局: H2C先搬运主机数据入AXI RAM, C2H再从同一AXI RAM读出回主机
localparam [63:0] REGION0_ADDR   = 64'h0000_0000_cfce_0000;  // H2C源区域(预载递增int)
localparam [63:0] REGION1_ADDR   = 64'h0000_0000_fcfc_0000;
localparam [63:0] REGION2_ADDR   = 64'h0000_0000_a100_0000;
localparam [63:0] REGION0_B      = 64'h0000_0002_cfce_0000;  // T2 C2H回读目标区域
localparam [63:0] REGION1_B      = 64'h0000_0002_fcfc_0000;
localparam [63:0] REGION2_B      = 64'h0000_0002_a100_0000;
localparam [63:0] REGION0_C      = 64'h0000_0004_cfce_0000;  // T3并发 C2H目标区域
localparam [63:0] REGION1_C      = 64'h0000_0004_fcfc_0000;
localparam [63:0] REGION2_C      = 64'h0000_0004_a100_0000;

localparam [63:0] RD_SGLIST_ADDR = 64'h0000_0000_dcfc_0000;   // T1 H2C链表(regions A)
localparam [63:0] WR_SGLIST_ADDR = 64'h0000_0000_dcff_0000;   // T2 C2H链表(regions B)
localparam [63:0] RD_SGLIST_T3   = 64'h0000_0000_dcfc_1000;   // T3 H2C链表(regions A)
localparam [63:0] WR_SGLIST_T3   = 64'h0000_0000_dcff_1000;   // T3 C2H链表(regions C)

// AXI内存布局: AXI_RAM为回环RAM(T1 H2C写入, T2 C2H读出); T3用独立源/目的
localparam [31:0] AXI_RAM_ADDR   = 32'h0010_0000;   // 回环AXI RAM
localparam [31:0] AXI_SRC_T3     = 32'h0020_0000;   // T3 C2H AXI源(预载)
localparam [31:0] AXI_DST_T3     = 32'h0030_0000;   // T3 H2C AXI目的

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

// ---------------- DUT连线: Mwr输出(到主机内存模型) ----------------
wire [TLP_HDR_WIDTH-1:0]    tx_wr_req_tlp_hdr;
wire [TX_SEQ_NUM_WIDTH-1:0] tx_wr_req_tlp_seq;
wire [TLP_DATA_WIDTH-1:0]   tx_wr_req_tlp_data;
wire [TLP_STRB_WIDTH-1:0]   tx_wr_req_tlp_strb;
wire                        tx_wr_req_tlp_valid;
wire                        tx_wr_req_tlp_sop;
wire                        tx_wr_req_tlp_eop;
reg                         tx_wr_req_tlp_ready = 1'b1;

// ---------------- DUT连线: Mrd输出(到主机内存模型) ----------------
wire [TLP_HDR_WIDTH-1:0]    tx_rd_req_tlp_hdr;
wire [TX_SEQ_NUM_WIDTH-1:0] tx_rd_req_tlp_seq;
wire                        tx_rd_req_tlp_valid;
wire                        tx_rd_req_tlp_sop;
wire                        tx_rd_req_tlp_eop;
reg                         tx_rd_req_tlp_ready = 1'b1;

// ---------------- DUT连线: CplD输入(主机内存模型应答) ----------------
reg  [TLP_HDR_WIDTH-1:0]  rx_cpl_tlp_hdr   = '0;
reg  [TLP_DATA_WIDTH-1:0] rx_cpl_tlp_data  = '0;
reg  [3:0]                rx_cpl_tlp_error = '0;
reg                       rx_cpl_tlp_valid = 1'b0;
reg                       rx_cpl_tlp_sop   = 1'b0;
reg                       rx_cpl_tlp_eop   = 1'b0;
wire                      rx_cpl_tlp_ready;

// ---------------- DUT连线: C2H(H2C见下)描述符 ----------------
reg  [31:0]                desc_wr_req_sglist_length  = '0;
reg  [PCIE_ADDR_WIDTH-1:0] desc_wr_req_sglist_address = '0;
reg                        desc_wr_req_sglist_start   = 1'b0;
reg  [AXI_ADDR_WIDTH-1:0]  desc_wr_req_sgdma_ramaddr  = '0;
reg  [31:0]                desc_wr_req_sgdma_length   = '0;
reg                        desc_wr_req_sgdma_start    = 1'b0;

// ---------------- DUT连线: H2C描述符 ----------------
reg  [31:0]                desc_rd_sglist_req_length  = '0;
reg  [PCIE_ADDR_WIDTH-1:0] desc_rd_sglist_req_address = '0;
reg                        desc_rd_sglist_req_start   = 1'b0;
reg  [AXI_ADDR_WIDTH-1:0]  desc_rd_sgdma_ram_addr     = '0;
reg  [31:0]                desc_rd_sgdma_req_length   = '0;
reg                        desc_rd_sgdma_req_start    = 1'b0;

wire tx_wr_sglist_irq;     // C2H链表取回完成
wire tx_rd_req_irq;        // H2C链表取回完成

reg  [15:0] requester_id        = 16'h0100;
reg  [2:0]  MaxPayloadSize      = 3'b010;        // 512字节
reg  [2:0]  max_read_payloadSize = 3'b010;       // 512字节
reg         ext_tag_enable       = 1'b0;
reg  [3:0]  rcb_128b             = 4'h3;

// ---------------- DUT连线: AXI读主接口(C2H数据源, m_axi_ar/r) ----------------
wire [AXI_ID_WIDTH-1:0]   m_axi_arid;
wire [AXI_ADDR_WIDTH-1:0] m_axi_araddr;
wire [7:0]                m_axi_arlen;
wire [2:0]                m_axi_arsize;
wire [1:0]                m_axi_arburst;
wire                      m_axi_arlock;
wire [3:0]                m_axi_arcache;
wire [2:0]                m_axi_arprot;
wire                      m_axi_arvalid;
reg                       m_axi_arready = 1'b0;
// R通道由从机任务驱动
reg  [AXI_ID_WIDTH-1:0]   m_axi_rid    = '0;
reg  [AXI_DATA_WIDTH-1:0] m_axi_rdata  = '0;
reg  [1:0]                m_axi_rresp  = 2'b00;
reg                       m_axi_rlast  = 1'b0;
reg                       m_axi_rvalid = 1'b0;
wire                      m_axi_rready;

// ---------------- DUT连线: AXI写主接口(H2C数据落盘, m_axi_aw/w/b) ----------------
wire [AXI_ID_WIDTH-1:0]   m_axi_awid;
wire [AXI_ADDR_WIDTH-1:0] m_axi_awaddr;
wire [7:0]                m_axi_awlen;
wire [2:0]                m_axi_awsize;
wire [1:0]                m_axi_awburst;
wire                      m_axi_awlock;
wire [3:0]                m_axi_awcache;
wire [2:0]                m_axi_awprot;
wire                      m_axi_awvalid;
reg                       m_axi_awready = 1'b0;
wire [AXI_DATA_WIDTH-1:0] m_axi_wdata;
wire [AXI_STRB_WIDTH-1:0] m_axi_wstrb;
wire                      m_axi_wlast;
wire                      m_axi_wvalid;
reg                       m_axi_wready = 1'b0;
reg  [AXI_ID_WIDTH-1:0]   m_axi_bid   = '0;
reg  [1:0]                m_axi_bresp = 2'b00;
reg                       m_axi_bvalid = 1'b0;
wire                      m_axi_bready;

// ---------------- DUT 例化 ----------------
sgdma_if_pcie_axi #(
    .TLP_DATA_WIDTH    (TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH    (TLP_STRB_WIDTH),
    .TLP_HDR_WIDTH     (TLP_HDR_WIDTH),
    .TLP_SEG_COUNT     (TLP_SEG_COUNT),
    .PCIE_ADDR_WIDTH   (PCIE_ADDR_WIDTH),
    .TX_SEQ_NUM_COUNT  (TX_SEQ_NUM_COUNT),
    .TX_SEQ_NUM_WIDTH  (TX_SEQ_NUM_WIDTH),
    .PCIE_TAG_COUNT    (PCIE_TAG_COUNT),
    .OP_TABLE_SIZE     (OP_TABLE_SIZE),
    .AXI_DATA_WIDTH    (AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH    (AXI_ADDR_WIDTH),
    .AXI_STRB_WIDTH    (AXI_STRB_WIDTH),
    .AXI_ID_WIDTH      (AXI_ID_WIDTH),
    .AXI_MAX_BURST_LEN (256)
) dut (
    .clk                     (clk),
    .rst                     (rst),

    .tx_wr_req_tlp_data      (tx_wr_req_tlp_data),
    .tx_wr_req_tlp_strb      (tx_wr_req_tlp_strb),
    .tx_wr_req_tlp_hdr       (tx_wr_req_tlp_hdr),
    .tx_wr_req_tlp_seq       (tx_wr_req_tlp_seq),
    .tx_wr_req_tlp_valid     (tx_wr_req_tlp_valid),
    .tx_wr_req_tlp_sop       (tx_wr_req_tlp_sop),
    .tx_wr_req_tlp_eop       (tx_wr_req_tlp_eop),
    .tx_wr_req_tlp_ready     (tx_wr_req_tlp_ready),

    .desc_wr_req_sglist_length   (desc_wr_req_sglist_length),
    .desc_wr_req_sglist_address  (desc_wr_req_sglist_address),
    .desc_wr_req_sglist_start    (desc_wr_req_sglist_start),
    .desc_wr_req_sgdma_ramaddr   (desc_wr_req_sgdma_ramaddr),
    .desc_wr_req_sgdma_length    (desc_wr_req_sgdma_length),
    .desc_wr_req_sgdma_start     (desc_wr_req_sgdma_start),

    .requester_id            (requester_id),
    .MaxPayloadSize          (MaxPayloadSize),
    .tx_wr_sglist_irq        (tx_wr_sglist_irq),

    .m_axi_arid              (m_axi_arid),
    .m_axi_araddr            (m_axi_araddr),
    .m_axi_arlen             (m_axi_arlen),
    .m_axi_arsize            (m_axi_arsize),
    .m_axi_arburst           (m_axi_arburst),
    .m_axi_arlock            (m_axi_arlock),
    .m_axi_arcache           (m_axi_arcache),
    .m_axi_arprot            (m_axi_arprot),
    .m_axi_arvalid           (m_axi_arvalid),
    .m_axi_arready           (m_axi_arready),
    .m_axi_rid               (m_axi_rid),
    .m_axi_rdata             (m_axi_rdata),
    .m_axi_rresp             (m_axi_rresp),
    .m_axi_rlast             (m_axi_rlast),
    .m_axi_rvalid            (m_axi_rvalid),
    .m_axi_rready            (m_axi_rready),

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

    .ext_tag_enable          (ext_tag_enable),
    .rcb_128b                (rcb_128b),
    .max_read_payloadSize    (max_read_payloadSize),
    .tx_rd_req_irq           (tx_rd_req_irq),

    .desc_rd_sglist_req_length   (desc_rd_sglist_req_length),
    .desc_rd_sglist_req_address  (desc_rd_sglist_req_address),
    .desc_rd_sglist_req_start    (desc_rd_sglist_req_start),
    .desc_rd_sgdma_ram_addr      (desc_rd_sgdma_ram_addr),
    .desc_rd_sgdma_req_length    (desc_rd_sgdma_req_length),
    .desc_rd_sgdma_req_start     (desc_rd_sgdma_req_start),

    .m_axi_awid              (m_axi_awid),
    .m_axi_awaddr            (m_axi_awaddr),
    .m_axi_awlen             (m_axi_awlen),
    .m_axi_awsize            (m_axi_awsize),
    .m_axi_awburst           (m_axi_awburst),
    .m_axi_awlock            (m_axi_awlock),
    .m_axi_awcache           (m_axi_awcache),
    .m_axi_awprot            (m_axi_awprot),
    .m_axi_awvalid           (m_axi_awvalid),
    .m_axi_awready           (m_axi_awready),
    .m_axi_wdata             (m_axi_wdata),
    .m_axi_wstrb             (m_axi_wstrb),
    .m_axi_wlast             (m_axi_wlast),
    .m_axi_wvalid            (m_axi_wvalid),
    .m_axi_wready            (m_axi_wready),
    .m_axi_bid               (m_axi_bid),
    .m_axi_bresp             (m_axi_bresp),
    .m_axi_bvalid            (m_axi_bvalid),
    .m_axi_bready            (m_axi_bready)
);

// ---------------- 统计 ----------------
integer error_count = 0;
integer mrd_cnt = 0;          // 已应答mrd数
integer mwr_tlp_cnt = 0;      // 已收到mwr TLP数(每测试复位)
integer wr_dw_total = 0;      // mwr累计dword数(每测试复位)
integer rd_dw_total = 0;      // AXI W侧累计dword数(每测试复位)
integer rd_wlast_cnt = 0;     // W通道wlast次数(每测试复位)
integer b_resp_cnt = 0;       // B响应握手次数
integer mem_miss_cnt = 0;     // 主机内存读未命中数
integer axi_miss_cnt = 0;     // AXI内存读未命中数

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

// ---------------- 主机内存模型 (dword粒度) ----------------
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

// ---------------- AXI内存模型 (dword粒度, 32bit地址) ----------------
reg [31:0] axi_mem [bit [31:0]];

function [31:0] axi_mem_read(input [31:0] a);
    begin
        if (axi_mem.exists({a[31:2], 2'b00})) begin
            axi_mem_read = axi_mem[{a[31:2], 2'b00}];
        end
        else begin
            axi_mem_read = 32'hcafe_beef;
            axi_miss_cnt = axi_miss_cnt + 1;
        end
    end
endfunction

function axi_mem_write(input [31:0] a, input [31:0] d);
    begin
        axi_mem[{a[31:2], 2'b00}] = d;
    end
endfunction

// AXI区域预载: 递增int 0..ndw-1
task seed_axi_region(input [31:0] base, input integer ndw);
    integer k;
    begin
        for (k = 0; k < ndw; k = k + 1)
            axi_mem_write(base + 32'd4*k, k[31:0]);
    end
endtask

// ---------------- 链表预载 ----------------
// entry(16字节) = {[127:96]序号, [95:64]长度, [63:0]起始地址}
// 内存dword序(地址递增): 地址低32bit, 地址高32bit, 长度, 序号
task sglist_write3(input [63:0] base,
                   input [63:0] r0, input [63:0] r1, input [63:0] r2);
    integer k;
    reg [63:0] eaddr;
    begin
        for (k = 0; k < ENTRY_NUM; k = k + 1) begin
            case (k % 3)
                0: eaddr = r0;
                1: eaddr = r1;
                2: eaddr = r2;
            endcase
            mem_write(base + 64'd16*k       , eaddr[31:0]);
            mem_write(base + 64'd16*k + 64'd4, eaddr[63:32]);
            mem_write(base + 64'd16*k + 64'd8, ENTRY_SIZE[31:0]);
            mem_write(base + 64'd16*k + 64'd12, (k+1));        // 序号非零(全0为终止符)
        end
    end
endtask

// 主机区域预载: 按entry映射存放递增int 0..TOTAL_DW-1 (H2C源数据)
task seed_host_regions(input [63:0] r0, input [63:0] r1, input [63:0] r2);
    integer k;
    reg [63:0] base;
    begin
        for (k = 0; k < TOTAL_DW; k = k + 1) begin
            case (k / (ENTRY_SIZE/4))
                0: base = r0;
                1: base = r1;
                2: base = r2;
            endcase
            mem_write(base + 64'd4*(k % (ENTRY_SIZE/4)), k[31:0]);
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
// 按mrd请求长度回单条CplD(可多拍), 数据取自主机内存模型
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

// ---------------- mwr监视: 写主机内存 + int递增检查 ----------------
// strb为dword有效位, sop拍解析头, 按序写入内存模型
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
            if (mwr_tlp_cnt <= 12)
                $display("[%0t] MWR TLP#%0d base=%h first_dw=%h", $time, mwr_tlp_cnt,
                         mwr_base, tx_wr_req_tlp_data[31:0]);
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

// ================= AXI读从机 (服务m_axi_ar/r, C2H数据源) =================
localparam ARQDEPTH = 8;
reg [AXI_ID_WIDTH-1:0]   arq_id   [0:ARQDEPTH-1];
reg [AXI_ADDR_WIDTH-1:0] arq_addr [0:ARQDEPTH-1];
reg [7:0]                arq_len  [0:ARQDEPTH-1];
integer arq_wr = 0;
integer arq_rd = 0;
reg ar_busy = 0;                 // R突起发送中, 暂停接收新AR

// AR捕获(negedge采样握手拍) + arready生成
always @(*) m_axi_arready = !rst && !ar_busy && (arq_wr - arq_rd < ARQDEPTH-1);

always @(negedge clk) begin
    if (!rst && (m_axi_arvalid === 1'b1) && (m_axi_arready === 1'b1)) begin
        arq_id  [arq_wr % ARQDEPTH] = m_axi_arid;
        arq_addr[arq_wr % ARQDEPTH] = m_axi_araddr;
        arq_len [arq_wr % ARQDEPTH] = m_axi_arlen;
        arq_wr = arq_wr + 1;
        $display("[%0t] AR  #%0d addr=%h len=%0d", $time, arq_wr, m_axi_araddr, m_axi_arlen);
    end
end

// R突起发送任务: 回arlen+1拍, 数据取自AXI内存, rlast收尾
task automatic axi_send_r_burst(input [AXI_ID_WIDTH-1:0] aid,
                                input [AXI_ADDR_WIDTH-1:0] aaddr,
                                input [7:0] alen);
    integer beats, b, k, g;
    begin
        beats = alen + 1;

        // 驱动第0拍
        @(posedge clk);
        m_axi_rid   <= aid;
        m_axi_rresp <= 2'b00;
        for (k = 0; k < AXI_DW_PER_BEAT; k = k + 1)
            m_axi_rdata[k*32 +: 32] <= axi_mem_read(aaddr + 32'd4*k);
        m_axi_rvalid <= 1'b1;
        m_axi_rlast  <= (beats == 1);

        b = 0;
        while (b + 1 < beats) begin
            @(negedge clk);
            while (m_axi_rready !== 1'b1) @(negedge clk);
            @(posedge clk);                                     // 本拍握手完成
            b = b + 1;
            for (k = 0; k < AXI_DW_PER_BEAT; k = k + 1) begin
                g = b*AXI_DW_PER_BEAT + k;
                m_axi_rdata[k*32 +: 32] <= axi_mem_read(aaddr + 32'd4*g);
            end
            m_axi_rlast <= (b == beats - 1);
        end

        // 最后一拍握手
        @(negedge clk);
        while (m_axi_rready !== 1'b1) @(negedge clk);
        @(posedge clk);                                         // 本拍握手完成
        m_axi_rvalid <= 1'b0;
        m_axi_rlast  <= 1'b0;
    end
endtask

// AR应答进程(严格按发出顺序)
initial begin
    forever begin
        @(negedge clk);
        if (!rst && (arq_rd != arq_wr)) begin
            ar_busy = 1'b1;
            $display("[%0t] R  serve #%0d addr=%h beats=%0d", $time, arq_rd+1,
                     arq_addr[arq_rd % ARQDEPTH], arq_len[arq_rd % ARQDEPTH] + 1);
            axi_send_r_burst(arq_id[arq_rd % ARQDEPTH], arq_addr[arq_rd % ARQDEPTH],
                             arq_len[arq_rd % ARQDEPTH]);
            arq_rd = arq_rd + 1;
            ar_busy = 1'b0;
        end
    end
end

// ================= AXI写从机 (服务m_axi_aw/w/b, H2C数据落盘) =================
localparam AWQDEPTH = 8;
reg [AXI_ID_WIDTH-1:0]   awq_id   [0:AWQDEPTH-1];
reg [AXI_ADDR_WIDTH-1:0] awq_addr [0:AWQDEPTH-1];
reg [7:0]                awq_len  [0:AWQDEPTH-1];
integer awq_wr = 0;
integer awq_rd = 0;      // 已完成wlast的突起指针(B应答推进)
integer awq_cur = 0;     // 正在接收W拍的突起指针
integer w_beat_cnt = 0;  // 当前突起内已收W拍数

// B应答队列: wlast后入队
reg [AXI_ID_WIDTH-1:0] bq_id [0:AWQDEPTH-1];
integer bq_wr = 0;
integer bq_rd = 0;

always @(*) m_axi_awready = !rst && (awq_wr - awq_rd < AWQDEPTH-1);
always @(*) m_axi_wready  = !rst && (awq_wr != awq_cur);       // AW已捕获才收W拍

// AW捕获
always @(negedge clk) begin
    if (!rst && (m_axi_awvalid === 1'b1) && (m_axi_awready === 1'b1)) begin
        awq_id  [awq_wr % AWQDEPTH] = m_axi_awid;
        awq_addr[awq_wr % AWQDEPTH] = m_axi_awaddr;
        awq_len [awq_wr % AWQDEPTH] = m_axi_awlen;
        awq_wr = awq_wr + 1;
    end
end

// ---------------- H2C数据采集: W拍写AXI内存 + int递增检查 ----------------
// md用例2: 写入数据以int为单位逐次递增, 与mwr写入主机内存的数据一致;
// AXI侧比对在sgdma_start(desc_rd_sgdma_req_start)拉高之后进行
// (rd引擎内部流在链表取回阶段有valid泄漏, 但axi_dma_wr空闲时tready=0不会消费,
//  W拍只会在sgdma_start之后出现, rd_data_phase仅作防御性门控)
reg [31:0] wr_dw;
integer rd_k;
reg rd_data_phase = 0;         // sgdma_start之后进入数据接收阶段

always @(posedge clk) begin
    if (rst) begin
        rd_data_phase <= 1'b0;
    end
    else if (desc_rd_sgdma_req_start === 1'b1) begin
        rd_data_phase <= 1'b1;
    end
end

always @(negedge clk) begin
    if (!rst && (rd_data_phase === 1'b1)
             && (m_axi_wvalid === 1'b1) && (m_axi_wready === 1'b1)) begin
        chk(m_axi_wstrb === {AXI_STRB_WIDTH{1'b1}}, "W beat partial strb (expect full 64B)");
        for (rd_k = 0; rd_k < AXI_DW_PER_BEAT; rd_k = rd_k + 1) begin
            if (m_axi_wstrb[rd_k*4 +: 4] === 4'hF) begin
                wr_dw = m_axi_wdata[rd_k*32 +: 32];
                chk(wr_dw === rd_dw_total[31:0],
                    $sformatf("AXI W int pattern mismatch: dw=%0h expect %0d", wr_dw, rd_dw_total));
                axi_mem_write(awq_addr[awq_cur % AWQDEPTH] + 32'd4*w_beat_cnt*AXI_DW_PER_BEAT
                              + 32'd4*rd_k, wr_dw);
                rd_dw_total = rd_dw_total + 1;
            end
        end

        w_beat_cnt = w_beat_cnt + 1;
        if (m_axi_wlast === 1'b1) begin
            chk(w_beat_cnt == awq_len[awq_cur % AWQDEPTH] + 1, "W burst beat count vs awlen mismatch");
            rd_wlast_cnt = rd_wlast_cnt + 1;
            bq_id[bq_wr % AWQDEPTH] = awq_id[awq_cur % AWQDEPTH];
            bq_wr = bq_wr + 1;
            awq_cur = awq_cur + 1;
            w_beat_cnt = 0;
        end
    end
end

// B应答进程
task automatic axi_send_b(input [AXI_ID_WIDTH-1:0] bid_v);
    begin
        @(posedge clk);
        m_axi_bid   <= bid_v;
        m_axi_bresp <= 2'b00;
        m_axi_bvalid <= 1'b1;
        @(negedge clk);
        while (m_axi_bready !== 1'b1) @(negedge clk);
        @(posedge clk);                                         // 握手完成
        m_axi_bvalid <= 1'b0;
    end
endtask

initial begin
    forever begin
        @(negedge clk);
        if (!rst && (bq_rd != bq_wr)) begin
            axi_send_b(bq_id[bq_rd % AWQDEPTH]);
            bq_rd = bq_rd + 1;
            b_resp_cnt = b_resp_cnt + 1;
        end
    end
end

// ---------------- debug: axi_dma_rd描述符加载/AR发起监视 ----------------
reg dbg_descv_q = 0;
reg dbg_st_q = 0;
always @(negedge clk) begin
    if (!rst) begin
        // wrapper desc_valid 上升沿
        if (dut.sgdma_axi_wr.s_axis_read_desc_valid === 1'b1 && !dbg_descv_q)
            $display("[%0t] DBG wrap desc_valid RISE ready=%b", $time,
                     dut.sgdma_axi_wr.s_axis_read_desc_ready);
        dbg_descv_q <= (dut.sgdma_axi_wr.s_axis_read_desc_valid === 1'b1);

        // axi_dma_rd 描述符握手
        if (dut.sgdma_axi_wr.dma_axi_rd.s_axis_read_desc_valid === 1'b1
         && dut.sgdma_axi_wr.dma_axi_rd.s_axis_read_desc_ready === 1'b1)
            $display("[%0t] DBG axird DESC LOAD addr=%h len=%0d", $time,
                     dut.sgdma_axi_wr.dma_axi_rd.s_axis_read_desc_addr,
                     dut.sgdma_axi_wr.dma_axi_rd.s_axis_read_desc_len);

        // axi_dma_rd AXI状态机 IDLE->START
        if (dut.sgdma_axi_wr.dma_axi_rd.axi_state_reg === 1'd1 && !dbg_st_q)
            $display("[%0t] DBG axird START addr_reg=%h op=%0d", $time,
                     dut.sgdma_axi_wr.dma_axi_rd.addr_reg,
                     dut.sgdma_axi_wr.dma_axi_rd.op_word_count_reg);
        dbg_st_q <= (dut.sgdma_axi_wr.dma_axi_rd.axi_state_reg === 1'd1);
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
        while ((tx_rd_req_irq !== 1'b1) && (t < max_cycles)) begin
            @(posedge clk);
            t = t + 1;
        end
        chk(tx_rd_req_irq === 1'b1,
            $sformatf("T2: tx_rd_req_irq timeout (waited %0d cycles)", t));
    end
endtask

task automatic wait_wr_drain(input integer max_cycles);
    integer t;
    begin
        t = 0;
        while ((wr_dw_total != TOTAL_DW) && (t < max_cycles)) begin
            @(posedge clk);
            t = t + 1;
        end
        chk(wr_dw_total == TOTAL_DW,
            $sformatf("T1: write DMA drain timeout (wr_dw=%0d)", wr_dw_total));
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

// ---------------- 区域核对任务 ----------------
task check_host_regions(input [63:0] r0, input [63:0] r1, input [63:0] r2,
                        input string tag);
    integer k;
    reg [63:0] base;
    begin
        for (k = 0; k < TOTAL_DW; k = k + 1) begin
            case (k / (ENTRY_SIZE/4))
                0: base = r0;
                1: base = r1;
                2: base = r2;
            endcase
            chk(mem_read(base + 64'd4*(k % (ENTRY_SIZE/4))) === k[31:0],
                $sformatf("%s: region data mismatch @%h idx=%0d", tag, base, k));
        end
    end
endtask

task check_axi_region(input [31:0] abase, input string tag);
    integer k;
    begin
        for (k = 0; k < TOTAL_DW; k = k + 1)
            chk(axi_mem_read(abase + 32'd4*k) === k[31:0],
                $sformatf("%s: axi data mismatch @%h idx=%0d got=%h", tag, abase, k,
                          axi_mem_read(abase + 32'd4*k)));
    end
endtask

// ---------------- 主测试序列 ----------------
integer k;

initial begin
    rst = 1;
    repeat (16) @(posedge clk);
    rst = 0;
    repeat (32) @(posedge clk);       // 等待xpm复位完成

    // ======== 链表/主机源数据/AXI源数据预载 ========
    sglist_write3(RD_SGLIST_ADDR, REGION0_ADDR, REGION1_ADDR, REGION2_ADDR);   // H2C读regions A
    sglist_write3(WR_SGLIST_ADDR, REGION0_B,    REGION1_B,    REGION2_B   );   // C2H写regions B
    sglist_write3(RD_SGLIST_T3,   REGION0_ADDR, REGION1_ADDR, REGION2_ADDR);   // T3 H2C读regions A
    sglist_write3(WR_SGLIST_T3,   REGION0_C,    REGION1_C,    REGION2_C   );   // T3 C2H写regions C
    seed_host_regions(REGION0_ADDR, REGION1_ADDR, REGION2_ADDR);  // H2C源: 递增int 0..3071
    seed_axi_region(AXI_SRC_T3, TOTAL_DW);                        // T3 C2H源: 递增int 0..3071
    $display("\nMemory model: rd sglist @%h (host->AXI), wr sglist @%h (AXI->host), %0d entries x %0d bytes",
             RD_SGLIST_ADDR, WR_SGLIST_ADDR, ENTRY_NUM, ENTRY_SIZE);

    // ======== T1: H2C读DMA先行 (md用例2, 主机 -> AXI RAM) ========
    $display("\n[T1] H2C read DMA: host regions -> AXI RAM %h, %0d bytes via %0d entries",
             AXI_RAM_ADDR, TOTAL_BYTES, ENTRY_NUM);

    // 1. 启动H2C链表读取(链表@0xdcfc0000, 48字节), 同时给出AXI目的地址/长度
    @(posedge clk);
    desc_rd_sglist_req_address <= RD_SGLIST_ADDR;
    desc_rd_sglist_req_length  <= SGLIST_BYTES;
    desc_rd_sgdma_ram_addr     <= AXI_RAM_ADDR;
    desc_rd_sgdma_req_length   <= TOTAL_BYTES;
    desc_rd_sglist_req_start   <= 1'b1;
    @(posedge clk);
    desc_rd_sglist_req_start   <= 1'b0;

    // 2. 等待链表取回完成irq
    wait_rd_irq(10000);

    // 3. sgdma_start在irq拉高后隔4拍脉冲: 触发axi_dma_wr写描述符 + sgdma读引擎
    repeat (IRQ_TO_START_DELAY) @(posedge clk);
    desc_rd_sgdma_req_start <= 1'b1;
    @(posedge clk);
    desc_rd_sgdma_req_start <= 1'b0;

    // 4. 等待12KB全部经AXI W通道写入AXI RAM (读写测试分开: 先等H2C完成)
    wait_rd_drain(200000);

    // 5. 检查总量: 12KB按4KB边界分3个AW突起(wlast/B各3次), int递增已在W监视核对
    chk(rd_wlast_cnt == ENTRY_NUM, "T1: W burst(wlast) count mismatch (expect 3 x 4KB)");
    $display("[T1] mrd answered=%0d, AXI W dwords=%0d, wlast=%0d, B resp=%0d",
             mrd_cnt, rd_dw_total, rd_wlast_cnt, b_resp_cnt);

    // 6. 等H2C完成后核对: 数据以AXI格式存在RAM中(递增int 0..3071)
    check_axi_region(AXI_RAM_ADDR, "T1");
    $display("[T1] AXI RAM region check done: %h .. %h",
             AXI_RAM_ADDR, AXI_RAM_ADDR + TOTAL_BYTES-1);

    // ======== T2: C2H写DMA回读 (md用例1, 从T1写入的AXI RAM取读出) ========
    $display("\n[T2] C2H write DMA: AXI RAM %h -> host regions B, %0d bytes via %0d entries",
             AXI_RAM_ADDR, TOTAL_BYTES, ENTRY_NUM);

    // 1. 启动C2H链表读取(链表@0xdcff0000, 48字节, 指向regions B), AXI源=同一块回环RAM
    @(posedge clk);
    desc_wr_req_sglist_address <= WR_SGLIST_ADDR;
    desc_wr_req_sglist_length  <= SGLIST_BYTES;
    desc_wr_req_sgdma_ramaddr  <= AXI_RAM_ADDR;
    desc_wr_req_sgdma_length   <= TOTAL_BYTES;
    desc_wr_req_sglist_start   <= 1'b1;
    @(posedge clk);
    desc_wr_req_sglist_start   <= 1'b0;

    // 2. 等待链表取回完成irq
    wait_wr_irq(10000);

    // 3. sgdma_start在irq拉高后隔4拍脉冲: 触发axi_dma_rd读描述符 + sgdma写引擎
    repeat (IRQ_TO_START_DELAY) @(posedge clk);
    desc_wr_req_sgdma_start <= 1'b1;
    @(posedge clk);
    desc_wr_req_sgdma_start <= 1'b0;

    // 4. 等待12KB全部经mwr写入主机regions B
    wait_wr_drain(200000);

    // 5. 检查总量与mwr TLP数 (int递增已在mwr监视核对)
    chk(mwr_tlp_cnt == TOTAL_BYTES/512, "T2: mwr TLP count mismatch (expect 24 x 512B)");
    $display("[T2] mwr TLPs=%0d, dwords=%0d, mrd=%0d, host mem miss=%0d",
             mwr_tlp_cnt, wr_dw_total, mrd_cnt, mem_miss_cnt);

    // 6. 核对主机regions B: C2H从AXI RAM读出的数据与H2C写入的一致(递增int 0..3071)
    check_host_regions(REGION0_B, REGION1_B, REGION2_B, "T2");
    $display("[T2] region check done: 0x%h/0x%h/0x%h each %0d ints",
             REGION0_B, REGION1_B, REGION2_B, ENTRY_SIZE/4);

    // ======== T3: C2H和H2C同时工作 (md用例3) ========
    $display("\n[T3] concurrent C2H+H2C: AXI src %h -> host regions C,", AXI_SRC_T3);
    $display("     host regions A -> AXI dst %h (disjoint regions for determinism)", AXI_DST_T3);

    wr_dw_total = 0;                 // 每测试复位模式计数器
    mwr_tlp_cnt = 0;
    rd_dw_total = 0;
    rd_wlast_cnt = 0;

    // 1. 同时启动两通道链表读取 (ctrl的mrd多路仲裁并发调度)
    @(posedge clk);
    desc_wr_req_sglist_address <= WR_SGLIST_T3;
    desc_wr_req_sglist_length  <= SGLIST_BYTES;
    desc_wr_req_sgdma_ramaddr  <= AXI_SRC_T3;
    desc_wr_req_sgdma_length   <= TOTAL_BYTES;
    desc_wr_req_sglist_start   <= 1'b1;

    desc_rd_sglist_req_address <= RD_SGLIST_T3;
    desc_rd_sglist_req_length  <= SGLIST_BYTES;
    desc_rd_sgdma_ram_addr     <= AXI_DST_T3;
    desc_rd_sgdma_req_length   <= TOTAL_BYTES;
    desc_rd_sglist_req_start   <= 1'b1;
    @(posedge clk);
    desc_wr_req_sglist_start <= 1'b0;
    desc_rd_sglist_req_start <= 1'b0;

    // 2. 等待两通道链表取回完成irq
    fork
        wait_wr_irq(10000);
        wait_rd_irq(10000);
    join

    // 3. 两个sgdma_start均在各自irq后隔4拍脉冲 (此处两通道irq几乎同时到)
    fork
        begin
            repeat (IRQ_TO_START_DELAY) @(posedge clk);
            desc_wr_req_sgdma_start <= 1'b1;
            @(posedge clk);
            desc_wr_req_sgdma_start <= 1'b0;
        end
        begin
            repeat (IRQ_TO_START_DELAY) @(posedge clk);
            desc_rd_sgdma_req_start <= 1'b1;
            @(posedge clk);
            desc_rd_sgdma_req_start <= 1'b0;
        end
    join

    // 4. 等待两方向数据全部搬运完成
    fork
        wait_wr_drain(200000);
        wait_rd_drain(200000);
    join

    // 5. 检查总量
    chk(mwr_tlp_cnt == TOTAL_BYTES/512, "T3: mwr TLP count mismatch (expect 24 x 512B)");
    chk(rd_wlast_cnt == ENTRY_NUM, "T3: W burst(wlast) count mismatch (expect 3 x 4KB)");
    $display("[T3] mwr TLPs=%0d, C2H dwords=%0d, H2C dwords=%0d, mrd=%0d, B resp=%0d",
             mwr_tlp_cnt, wr_dw_total, rd_dw_total, mrd_cnt, b_resp_cnt);

    // 6. 区域核对: 主机regions C + AXI目的区域均存放递增int 0..3071
    check_host_regions(REGION0_C, REGION1_C, REGION2_C, "T3");
    check_axi_region(AXI_DST_T3, "T3");
    $display("[T3] region check done");

    // ======== 汇总 ========
    $display("\n================ SUMMARY ================");
    $display("mrd answered     : %0d (2 wr sglist + 2 rd sglist + 48 data)", mrd_cnt);
    $display("mwr TLPs         : %0d x2 tests (T2/T3 C2H)", mwr_tlp_cnt);
    $display("H2C dwords       : %0d x2 tests (T1/T3 host->AXI)", rd_dw_total);
    $display("C2H dwords       : %0d x2 tests (T2/T3 AXI->host)", wr_dw_total);
    $display("B responses      : %0d", b_resp_cnt);
    $display("host mem miss    : %0d, axi mem miss: %0d", mem_miss_cnt, axi_miss_cnt);
    if (error_count == 0)
        $display("RESULT: *** TEST PASSED ***");
    else
        $display("RESULT: *** TEST FAILED, %0d errors ***", error_count);
    $finish;
end

// ---------------- 看门狗 ----------------
initial begin
    #2000000;                                         // 2ms
    $display("[%0t] FATAL: global watchdog timeout", $time);
    $display("RESULT: *** TEST FAILED (timeout) ***");
    $finish;
end

endmodule
