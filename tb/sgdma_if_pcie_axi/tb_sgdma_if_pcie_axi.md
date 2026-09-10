# sgdma_if_pcie_axi模块仿真

> 本文档规格与 `tb_sgdma_if_pcie_axis.md` 一致，仅将用户侧 **AXI4-Stream 接口替换为 AXI4 内存映射主接口**：
> C2H 通道的数据源由 `send_axis` + `s_axis_tlp_*` 替换为 **AXI 读主接口 `m_axi_ar/r`**（内部经 `axi_dma_rd`）；
> H2C 通道的数据输出由 `m_axis_tlp_*` 替换为 **AXI 写主接口 `m_axi_aw/w/b`**（内部经 `axi_dma_wr`）。

## 仿真模块接口定义

```verilog
module sgdma_if_pcie_axi#(
    parameter TLP_DATA_WIDTH = 512,
    parameter TLP_STRB_WIDTH = TLP_DATA_WIDTH/32,
    parameter TLP_HDR_WIDTH = 128,
    parameter TLP_SEG_COUNT = 1,
    parameter PCIE_ADDR_WIDTH = 64,
    parameter TX_SEQ_NUM_COUNT = 1,
    parameter TX_SEQ_NUM_WIDTH = 6,
    parameter PCIE_TAG_COUNT = 32,
    parameter OP_TABLE_SIZE = PCIE_TAG_COUNT,
    parameter AXI_DATA_WIDTH = 512,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_STRB_WIDTH = (AXI_DATA_WIDTH/8),
    parameter AXI_ID_WIDTH = 8,
    parameter AXI_MAX_BURST_LEN = 256
)(
    input   wire    clk ,
    input   wire    rst ,

    // Mwr TLP输出(到主机)
    output  wire [TLP_DATA_WIDTH-1:0]                     tx_wr_req_tlp_data,
    output  wire [TLP_STRB_WIDTH-1:0]                     tx_wr_req_tlp_strb,
    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_wr_req_tlp_hdr,
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_wr_req_tlp_seq,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_valid,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_sop,
    output  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_eop,
    input   wire                                          tx_wr_req_tlp_ready,

    // C2H描述符: 链表 + AXI源地址/长度
    input  wire [31 : 0]                 desc_wr_req_sglist_length  ,//bytes
    input  wire [PCIE_ADDR_WIDTH-1 : 0]  desc_wr_req_sglist_address ,
    input  wire                          desc_wr_req_sglist_start   ,
    input  wire [AXI_ADDR_WIDTH-1:0]     desc_wr_req_sgdma_ramaddr  ,
    input  wire [31:0]                   desc_wr_req_sgdma_length  ,//bytes
    input  wire                          desc_wr_req_sgdma_start   ,

    input  wire [15: 0]    requester_id        ,
    input  wire [2 : 0]    MaxPayloadSize      ,
    output wire            tx_wr_sglist_irq    ,

    // AXI4读主接口(C2H数据源)
    output wire [AXI_ID_WIDTH-1:0]       m_axi_arid,  ... (araddr/arlen/arsize/arburst/
                                                          arlock/arcache/arprot/arvalid)
    input  wire                          m_axi_arready,
    input  wire [AXI_ID_WIDTH-1:0]       m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0]     m_axi_rdata, ... (rresp/rlast/rvalid)
    output wire                          m_axi_rready,

    // Mrd TLP输出(链表取回+H2C数据读, 经ctrl多路仲裁)
    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_rd_req_tlp_hdr  , ...
    input   wire                                          tx_rd_req_tlp_ready,

    // CplD TLP输入(主机应答)
    input  wire [TLP_DATA_WIDTH-1:0]                     rx_cpl_tlp_data , ...

    input  wire         ext_tag_enable,
    input  wire [3 :0]  rcb_128b      ,
    input  wire [2 : 0] max_read_payloadSize     ,
    output wire         tx_rd_req_irq            ,   // H2C链表取回完成

    // H2C描述符: 链表 + AXI目的地址/长度
    input  wire [31 : 0]         desc_rd_sglist_req_length  ,//bytes
    input  wire [PCIE_ADDR_WIDTH-1 : 0] desc_rd_sglist_req_address,
    input  wire                  desc_rd_sglist_req_start   ,
    input  wire [AXI_ADDR_WIDTH-1:0]     desc_rd_sgdma_ram_addr,
    input  wire [31:0]                   desc_rd_sgdma_req_length ,//bytes
    input  wire                  desc_rd_sgdma_req_start    ,

    // AXI4写主接口(H2C数据落盘)
    output wire [AXI_ID_WIDTH-1:0]       m_axi_awid,  ... (awaddr/awlen/awsize/awburst/
                                                          awlock/awcache/awprot/awvalid)
    input  wire                          m_axi_awready,
    output wire [AXI_DATA_WIDTH-1:0]     m_axi_wdata,
    output wire [AXI_STRB_WIDTH-1:0]     m_axi_wstrb, ... (wlast/wvalid)
    input  wire                          m_axi_wready,
    input  wire [AXI_ID_WIDTH-1:0]       m_axi_bid, ... (bresp/bvalid)
    output wire                          m_axi_bready
);
```

整个模块的接口包括mwr包 `tx_wr_req_tlp_*`、mrd包发送接口 `tx_rd_req_tlp_*`（两引擎的mrd经 `sgdma_if_pcie_ctrl` 固定优先级多路仲裁合并）、cpld包接口 `rx_cpl_tlp_*`。

同时提供启动DMA的描述符接口：

- `desc_wr_req_sglist_length`：C2H链表长度（字节）。`desc_wr_req_sglist_address`：链表存放地址。`desc_wr_req_sglist_start`：读取C2H链表开始信号。`desc_wr_req_sgdma_start`：写DMA开始信号，**同一脉冲同时触发 `axi_dma_rd` 读描述符（AXI源 `desc_wr_req_sgdma_ramaddr`/`desc_wr_req_sgdma_length`）与sgdma写引擎**。
- H2C通道描述符 `desc_rd_sglist_req_*` / `desc_rd_sgdma_*` 定义对称，`desc_rd_sgdma_req_start` 同时触发 `axi_dma_wr` 写描述符与sgdma读引擎。

链表entry结构（16字节）不变：

| 127：96 | 95：64 | 63：0 |
| --- | --- | --- |
| number：链表序号（全0为终止符） | 此段内存映射长度（字节） | 此段内存区域起始地址 |

## 仿真测试用例

C2H通道用户数据的AXI读侧由TB的**AXI读从机内存模型**产生（递增int），替代原 `send_axis`；H2C通道数据由**AXI写从机内存模型**落盘并比对，替代原 `m_axis_tlp_*` 采集。

其中 `desc_wr_req_sgdma_start`、`desc_rd_sgdma_req_start` 应该在对应的 `tx_wr_sglist_irq`、`tx_rd_req_irq` 信号拉高后的4个时钟周期拉高一个时钟周期开启DMA。

| 测试用例序号 | 功能 | 预期结果 |
| ------------ | ---- | -------- |
| 1 | H2C操作先行（读写测试分开）：主机regions(0xcfce0000/0xfcfc0000/0xa1000000)预载递增int，desc_rd_sglist_req_*工作，链表3个entry各4KB共12KB，链表位于内存空间0xdcfc0000中，长度48字节，AXI目的地址0x00100000 | 等待H2C完成后，数据以AXI格式存在RAM中：AXI W通道写入的数据以int为单位逐次递增，AXI RAM 0x00100000..0x00102fff存放递增int 0..3071，wlast/B响应扗3次（4KB边界分3个AW突起） |
| 2 | C2H取读出：从T1写入的同一AXI RAM(0x00100000)取读出，desc_wr_req_sglist_*工作，链表3个entry各4KB指向主机regions B(0x2cfce0000/0x2fcfc0000/0x2a1000000)，链表位于0xdcff0000 | mwr包的输出应该以int为单位逐次递增，且按链表顺序写入对应主机区域，与H2C写入AXI RAM的数据保持一致 |
| 3 | C2H和H2C同时工作，即1和2同时工作（主机/AXI区域取不相交集合保证确定性：C2H源AXI 0x00200000预载→写主机regions C(0x4cfce0000/...)，H2C读主机regions A→AXI目的0x00300000） | 读写的数据都应该逐次递增，且以int为单位。两引擎mrd经ctrl并发仲裁，AXI侧比对的数据应该在sgdma_start信号拉高之后进行比对 |

> **RTL修复记录 (2026-09-07, sgdma_if_pcie_axi_rd.v v1.1)**：原集成中 H2C 侧 `axi_dma_wr` 按单tlast包语义工作，而上游 `sgdma_if_pcie_axis_rd` 每4KB entry打一拍tlast，导致第1个entry后写描述符提前完成（awlen=63单突起后停住），剩余entry数据无法落盘。修复为长度驱动（实例化参数 `AXIS_LAST_ENABLE=0`），不破坏AXIS变体每entry一拍tlast的设计。

## 平台模型

1. 关联数组 `pcie_mem[bit[63:0]]` 按 dword 对齐模拟主机内存；mwr写入/mrd读出均经过该内存
2. 关联数组 `axi_mem[bit[31:0]]` 按 dword 对齐模拟AXI内存（C2H源/H2C目的）
3. mrd应答器：捕获进程队列化mrd，应答进程按发出顺序原序回CplD（与ctrl按发出顺序路由的语义匹配），单CplD回满mrd长度
4. AXI读从机：AR入队原序应答R突起（rlast收尾），数据取自 `axi_mem`
5. AXI写从机：AW入队，W拍按wstrb写入 `axi_mem` 并逐int比对，wlast后回B响应
6. rd引擎内部AXIS流在链表取回阶段有valid泄漏，但 `axi_dma_wr` 空闲时 `s_axis_write_data_tready=0` 不会误消费；W拍比对仍按约定仅在sgdma_start之后进行
