# sgdma_if_pcie_axis模块仿真



## 仿真模块接口定义

```verilog
module sgdma_if_pcie_axis#(
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
    parameter TX_SEQ_NUM_WIDTH = 6,
    // PCIe tag count
    parameter PCIE_TAG_COUNT = 32,
    // Operation table size
    parameter OP_TABLE_SIZE = PCIE_TAG_COUNT
)(
    input   wire    clk ,
    input   wire    rst ,

    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]    tx_wr_req_tlp_hdr,
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0] tx_wr_req_tlp_seq,
    output  wire [TLP_DATA_WIDTH-1:0]  tx_wr_req_tlp_data,
    output  wire [TLP_STRB_WIDTH-1:0]  tx_wr_req_tlp_strb,
    output  wire [TLP_SEG_COUNT-1:0]   tx_wr_req_tlp_valid,
    output  wire [TLP_SEG_COUNT-1:0]   tx_wr_req_tlp_sop,
    output  wire [TLP_SEG_COUNT-1:0]   tx_wr_req_tlp_eop,
    input   wire                       tx_wr_req_tlp_ready,

    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_rd_req_tlp_hdr  ,
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_rd_req_tlp_seq  ,
    output  wire [TLP_SEG_COUNT-1:0]      tx_rd_req_tlp_valid,
    output  wire [TLP_SEG_COUNT-1:0]      tx_rd_req_tlp_sop  ,
    output  wire [TLP_SEG_COUNT-1:0]      tx_rd_req_tlp_eop  ,
    input   wire                          tx_rd_req_tlp_ready,    

    input  wire [TLP_DATA_WIDTH-1:0]              rx_cpl_tlp_data ,
    input  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0] rx_cpl_tlp_hdr  ,
    input  wire [TLP_SEG_COUNT*4-1:0]  rx_cpl_tlp_error,
    input  wire [TLP_SEG_COUNT-1:0]    rx_cpl_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]    rx_cpl_tlp_sop  ,
    input  wire [TLP_SEG_COUNT-1:0]    rx_cpl_tlp_eop  ,
    output wire                        rx_cpl_tlp_ready,

    input  wire [31 : 0] desc_wr_req_sglist_length  ,
    input  wire [PCIE_ADDR_WIDTH-1 : 0]  desc_wr_req_sglist_address ,
    input  wire desc_wr_req_sglist_start   ,
    input  wire desc_wr_req_sgdma_start    ,

    input  wire [31 : 0] desc_rd_req_sglist_length  ,
    input  wire [PCIE_ADDR_WIDTH-1 : 0]  desc_rd_req_sglist_address ,
    input  wire desc_rd_req_sglist_start   ,
    input  wire desc_rd_req_sgdma_start    ,


    output wire tx_wr_sglist_irq,
    output wire tx_rd_sglist_irq,
    input  wire [15: 0] requester_id        ,
    input  wire [2 : 0] MaxPayloadSize      ,
    input  wire [2 : 0] max_read_payloadSize,

    input  wire [TLP_DATA_WIDTH - 1 :0]      s_axis_tlp_tdata   ,
    input  wire [TLP_DATA_WIDTH / 8 - 1:0]   s_axis_tlp_tkeep   ,
    input  wire  s_axis_tlp_tvalid  ,
    input  wire  s_axis_tlp_tlast   ,
    output wire  s_axis_tlp_tready  ,

    output wire [TLP_DATA_WIDTH - 1 :0]      m_axis_tlp_tdata   ,
    output wire [TLP_DATA_WIDTH / 8 - 1:0]   m_axis_tlp_tkeep   ,
    output wire                              m_axis_tlp_tvalid  ,
    output wire                              m_axis_tlp_tlast   ,
    input  wire                              m_axis_tlp_tready  
);
```

整个模块的接口定义包括mwr包，tx_wr_req_tlp_*。mrd包的发送接口，tx_rd_req_tlp_*。 以及cpld包的接口rx_cpl_tlp_*。

同时也提供了启动dma的描述符接口

desc_wr_req_sglist_length：链表的长度，以字节为单位。 desc_wr_req_sglist_address链表存放的地址。desc_wr_req_sglist_start，读取C2H操作的链表开始信号。desc_wr_req_sgdma_start：写DMA开始信号。

H2C通道的描述符也是一样的，符合C2H通道描述符的定义。

s_axis_tlp_*代表C2H通道用户数据的输入。m_axis_tlp_*代表H2C通道的数据输出，满足axis协议。

链表entry结构如下：

​                  127：96                                                                     95：64                                                                       63：0

 number：记录这是第几个链表        记录此链表所映射的内存长度，即DMA最大客读取的长度          此段内存区域的起始地址



## 仿真测试用例

app用户数据的s_axis_tlp_*可以用*send_axis*模块来产生，模块接口如下：

```verilog
module send_axis#(
    parameter STREAM_TDATA_WIDTH = 512,
    parameter STREAM_TKEEP_WIDTH = STREAM_TDATA_WIDTH / 8,
    parameter FIFO_DEEPTH_WIDTH = 4,
    parameter STREAM_TOTAL_WIDTH = STREAM_TDATA_WIDTH + STREAM_TKEEP_WIDTH + 2
)(
    input  wire                                 m_axis_aclk,
    input  wire                                 m_axis_aresetn,

    input  wire [31:0]                          st_length, //发送的数据长度，以字节为单位
    input  wire                                 st_start,  //发送数据开始信号
    output wire                                 st_end,    //数据发送完成信号

    output wire [STREAM_TDATA_WIDTH-1:0]        m_axis_tdata,
    output wire [STREAM_TKEEP_WIDTH-1:0]        m_axis_tkeep,
    output wire                                 m_axis_tlast,
    output wire                                 m_axis_tvalid,
    input  wire                                 m_axis_tready
);
```

其中desc_wr_req_sgdma_start，desc_wr_req_sgdma_start信号应该在对应的tx_wr_sglist_irq，tx_rd_sglist_irq信号拉高后的4个时钟周期拉高一个时钟周期开启DMA

| 测试用例序号 | 功能                                                         | 预期结果                                                     |
| ------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| 1            | C2H操作，即desc_wr_req_sglist_*工作，向64bit内存写入12KB数据，链表记录3个entry，分别为<br>1. 长度4KB 起始地址0xcfce0000  2. 长度4KB 起始地址 0xfcfc0000 3. 长度4KB，起始地址0xa1000000<br>链表位于内存空间0xdcff0000中，长度48字节 | mwr包的输出应该以int为单位，逐次递增。                       |
| 2            | H2C操作，即desc_rd_req_sglist_*工作，从64bit内存地址读出数据，链表记录3个entry，分别为<br/>1. 长度4KB 起始地址0xcfce0000  2. 长度4KB 起始地址 0xfcfc0000 3. 长度4KB，起始地址0xa1000000<br>链表位于内存空间0xdcfc0000中，长度48字节 | 读出来的数据，应该以int为单位逐次递增，和mwr写入内存的数据保持一致 |
| 3            | C2H和H2C同时工作，即1和2同时工作                             | 读写的数据都应该逐次递增，且以int为单位。cpld比对的数据应该在sgdma_start信号拉高之后进行比对 |

