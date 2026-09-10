# sgdma_if_pcie_axis_rd仿真标准

## 模块接口声明

1.仿真模块sgdma_if_pcie_axis_rd.v，这个模块负责实现H2C的DMA操作。模块接口如下：

```verilog
module *sgdma_if_pcie_axis_rd*#(
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
  input  wire   clk ,
  input  wire   rst ,
    output  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]     tx_rd_req_tlp_hdr  , //mrd包的包头
    output  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]   tx_rd_req_tlp_seq  , //mrd包的序号，记录目前是第几个mrd包，可不用
    output  wire [TLP_SEG_COUNT-1:0]  tx_rd_req_tlp_valid,//mrd包的握手信号，valid，参考axis协议，只有valid和ready同时u拉高，此包才有效
    output  wire [TLP_SEG_COUNT-1:0]  tx_rd_req_tlp_sop  ,//sop信号，表明包开始
    output  wire [TLP_SEG_COUNT-1:0]  tx_rd_req_tlp_eop  ,//eop，表明包结束，像这种512bit的总线接口，发一个mrd包，往往sop和eop同时拉高
  input  wire            tx_rd_req_tlp_ready,//反压信号
    input  wire [TLP_DATA_WIDTH-1:0]           rx_cpl_tlp_data ,//返回的cpld的数据部分
    input  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]     rx_cpl_tlp_hdr  ,//cpld的包头
    input  wire [TLP_SEG_COUNT*4-1:0] rx_cpl_tlp_error,//error信号
  input  wire [TLP_SEG_COUNT-1:0]  rx_cpl_tlp_valid,
  input  wire [TLP_SEG_COUNT-1:0]  rx_cpl_tlp_sop  ,
  input  wire [TLP_SEG_COUNT-1:0]  rx_cpl_tlp_eop  ,
  output wire            rx_cpl_tlp_ready,//反压信号
    
    input  wire [15:0]  requester_id  ,//requester id用在mrd包中
    input  wire [2 : 0] max_read_payloadSize   ,//一个mrd包最大可读取的数据长度
  output wire     tx_rd_req_irq,//当链表读完之后，发送的中断信号，拉高一个时钟周期
    
    input  wire [31 : 0]     desc_tx_rdlist_length     ,//内存中保存的链表长度
    input  wire [PCIE_ADDR_WIDTH-1 : 0] desc_tx_rdlist_address,//链表在内存中的起始地址
  input  wire desc_tx_rdlist_start,//读链表开始信号
  input  wire desc_tx_rddma_start,//读DMA开始信号
    
    output wire [TLP_DATA_WIDTH - 1 :0]    m_axis_tlp_tdata  ,//输出的DMA数据，采用axis格式输出
  output wire [TLP_DATA_WIDTH / 8 - 1:0]  m_axis_tlp_tkeep  ,
  output wire                m_axis_tlp_tvalid  ,
  output wire                m_axis_tlp_tlast  ,
  input  wire                m_axis_tlp_tready  
);
```

整个源代码的实现思想如下：

```verilog
localparam  SGDMA_IDLE   = 5'b00001,
            SGDMA_RDLIST = 5'b00010,
            SGDMA_RDRECV = 5'b00100,
            SGDMA_RDSTART= 5'b01000,
            SGDMA_ENDL   = 5'b10000;

reg [4:0] sgdma_rd_state_reg, sgdma_rd_state_next;
```

定义的状态机，sgdma的H2C操作流程是先发送一个desc_tx_rdlist_length以及desc_tx_rdlist_address，等待desc_tx_rdlist_start的上升沿，此时状态机由SGDMA_IDLE变为SGDMA_RDLIST

然后调用以下模块去获取链表

```verilog
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
```

返回的链表通过cpld_rx_axis_*接口存入到fifo中。此时状态机由SGDMA_RDLIST变为SGDMA_RDRECV，当检测到cpld_rx_axis_tlast拉高时，表明链表已读取完毕，等待接收desc_tx_rddma_start的上升沿，此信号应在中断信号拉高后拉高，进入到SGDMA_RDSTART状态

```verilog
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

```

进入到SGDMA_RDSTART状态，此时fifo为非对称fifo，即64/128/256/512bit进入，但是是128bit输出。128bit的链表信息如下：

​                  127：96                                                                     95：64                                                                       63：0

 number：记录这是第几个链表        记录此链表所映射的内存长度，即DMA最大客读取的长度          此段内存区域的起始地址

由于是512bit进入的fifo，这里通过cpld_rx_axis_tkeep来判断链表元素的数量。假设低16bit全1，高48bit全0，那么此时写入fifo的高384bit全0，低128bit完整的写入到fifo中。

在进入SGDMA_RDSTART状态时，判断dma_rd_sglist_fifo_empty是否为空，不为空，那么继续读链表。为空的情况下需要判断链表长度中的长度元素是否为0，为0则进入到IDLE状态，否则进入到SGDMA_ENDL状态接收返回的用户数据并输入到m_axis_tlp_*中。

```verilog
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
                    if (dma_rd_sglist_fifo_rd_data != 0) begin
                        desc_rd_req_sglist_start_next = 1'b1;
                    end
                    else begin
                        desc_rd_req_sglist_start_next = 1'b0;
                    end
                end
                else begin
                    sgdma_rd_state_next = SGDMA_IDLE;
                end
            end
        end
```

## 仿真要求

测试用例1：

链表所在的内存空间地址：64bit 0xcfcc0000，链表长度256bit，链表信息如下：

| 数据                                 | 起始地址 64bit | 长度 32bit | 序号 32bit |
| ------------------------------------ | -------------- | ---------- | ---------- |
| 从0开始的计数器，依次累加，int为单位 | 0xfcfc0000     | 0x4000     | 1          |
| 从0开始的计数器，依次累加，int为单位 | 0xfcfd0000     | 0x4000     | 2          |



测试用例2：

链表所在的内存空间地址：64bit 0xcfcc0000，链表长度384bit，链表信息如下：

| 数据                                 | 起始地址 64bit | 长度 32bit | 序号 32bit |
| ------------------------------------ | -------------- | ---------- | ---------- |
| 从0开始的计数器，依次累加，int为单位 | 0xfcfc0000     | 0x4000     | 1          |
| 从0开始的计数器，依次累加，int为单位 | 0xfcfd0000     | 0x4000     | 2          |
| 从0开始的计数器，依次累加，int为单位 | 0xfcfe0000     | 0x4009     | 3          |





