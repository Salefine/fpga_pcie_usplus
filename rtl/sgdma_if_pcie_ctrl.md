# sgdma仲裁模块编写规范

## 1.代码接口

| clk  | 全局时钟输入         |
| ---- | -------------------- |
| rst  | 全局复位输入，高有效 |

mrd的tlp包接口如下：

| rx_rd_req_tlp_hdr   | tlp包的包头                                               |
| ------------------- | --------------------------------------------------------- |
| rx_rd_req_tlp_seq   | 序列号                                                    |
| rx_rd_req_tlp_valid | 包有效信号                                                |
| rx_rd_req_tlp_sop   | 帧开始标志                                                |
| rx_rd_req_tlp_eop   | 帧结束标志                                                |
| rx_rd_req_tlp_ready | ready反压信号，只有当valid和ready同时拉高时，这个包才有效 |



| tx_rd_req_tlp_hdr   | 仲裁后的输出的tlp包的包头                                    |
| ------------------- | ------------------------------------------------------------ |
| tx_rd_req_tlp_seq   | 仲裁后的输出的序列号                                         |
| tx_rd_req_tlp_valid | 仲裁后的输出的包有效信号                                     |
| tx_rd_req_tlp_sop   | 仲裁后的输出的帧开始标志                                     |
| tx_rd_req_tlp_eop   | 仲裁后的输出的帧结束标志                                     |
| tx_rd_req_tlp_ready | 仲裁后的输出的ready反压信号，只有当valid和ready同时拉高时，这个包才有效 |





返回的cpld包接口如下：

| rx_cpl_tlp_hdr   | 返回的cpld包的包头                                   |
| ---------------- | ---------------------------------------------------- |
| rx_cpl_tlp_data  | 返回的cpld的数据                                     |
| rx_cpl_tlp_error | 返回的cpld包是否有错                                 |
| rx_cpl_tlp_valid | 返回的cpld包的valid信号，和ready信号组成握手         |
| rx_cpl_tlp_ready | 反压信号，只有当valid和ready同时拉高时，这个包才有效 |
| rx_cpl_tlp_sop   | 帧开始标志                                           |
| rx_cpl_tlp_eop   | 帧结束标志                                           |



| tx_cpl_tlp_hdr   | 路由后的返回的cpld包的包头                                   |
| ---------------- | ------------------------------------------------------------ |
| tx_cpl_tlp_data  | 路由后的返回的cpld的数据                                     |
| tx_cpl_tlp_error | 路由后的返回的cpld包是否有错                                 |
| tx_cpl_tlp_valid | 路由后的返回的cpld包的valid信号，和ready信号组成握手         |
| tx_cpl_tlp_ready | 路由后的反压信号，只有当valid和ready同时拉高时，这个包才有效 |
| tx_cpl_tlp_sop   | 路由后的帧开始标志                                           |
| tx_cpl_tlp_eop   | 路由后的帧结束标志                                           |



参数接口如下：

| TLP_DATA_WIDTH   | 数据接口的位宽，可选64，128，256，512 |
| ---------------- | ------------------------------------- |
| TLP_HDR_WIDTH    | 包头的宽度，固定，128bit              |
| TLP_PORT_COUNT   | 输入的mrd包的数量，可选1，2，3，4，5  |
| TX_SEQ_NUM_WIDTH | pcie的序列号的宽度                    |

接口声明如下：

```verilog
/****************************************************************************
 * @file    sgdma_if_pcie_ctrl.v
 * @brief   PCIe TLP路由控制器 - 支持多端口读请求调度和完成包路由
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 2.0
 * @date    2026-03-18
 * 
 * @par 修改记录:
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |  2026-03-18   |   v1.0      |    zzhi          |   初始版本             |
 * |  2026-08-10   |   v2.0      |    zzhi          |   修复ready信号逻辑    |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2026 zzhi
 * ***************************************************************************/

`resetall
`timescale 1ns/1ps
`default_nettype none

module sgdma_if_pcie_ctrl #(
    parameter TLP_DATA_WIDTH = 512,
    parameter TLP_STRB_WIDTH = TLP_DATA_WIDTH/32,
    parameter TLP_HDR_WIDTH = 128,
    parameter TLP_PORT_COUNT = 2,
    parameter TX_SEQ_NUM_WIDTH = 6
)(
    input  wire                                   clk,
    input  wire                                   rst,

    // 读请求输入（从多个端口）
    input  wire [TLP_PORT_COUNT*TLP_HDR_WIDTH-1:0]    rx_rd_req_tlp_hdr,
    input  wire [TLP_PORT_COUNT*TX_SEQ_NUM_WIDTH-1:0] rx_rd_req_tlp_seq,
    input  wire [TLP_PORT_COUNT-1:0]   rx_rd_req_tlp_valid,
    input  wire [TLP_PORT_COUNT-1:0]   rx_rd_req_tlp_sop,
    input  wire [TLP_PORT_COUNT-1:0]   rx_rd_req_tlp_eop,
    output wire [TLP_PORT_COUNT-1:0]   rx_rd_req_tlp_ready,

    // 读请求输出（到PCIe IP）
    output wire [TLP_HDR_WIDTH-1:0]    tx_rd_req_tlp_hdr,
    output wire [TX_SEQ_NUM_WIDTH-1:0] tx_rd_req_tlp_seq,
    output wire  tx_rd_req_tlp_valid,
    output wire  tx_rd_req_tlp_sop,
    output wire  tx_rd_req_tlp_eop,
    input  wire  tx_rd_req_tlp_ready,

    // 完成包输入（从PCIe IP）
    input  wire [TLP_HDR_WIDTH-1:0]    rx_cpl_tlp_hdr,
    input  wire [TLP_DATA_WIDTH-1:0]   rx_cpl_tlp_data,
    input  wire [3:0]   rx_cpl_tlp_error,
    input  wire         rx_cpl_tlp_valid,
    input  wire         rx_cpl_tlp_sop,
    input  wire         rx_cpl_tlp_eop,
    output wire         rx_cpl_tlp_ready,

    // 完成包输出（到多个端口）
    output wire [TLP_PORT_COUNT*TLP_HDR_WIDTH-1:0]    tx_cpl_tlp_hdr,
    output wire [TLP_PORT_COUNT*TLP_DATA_WIDTH-1:0]   tx_cpl_tlp_data,
    output wire [TLP_PORT_COUNT*4-1:0] tx_cpl_tlp_error,
    output wire [TLP_PORT_COUNT-1:0]   tx_cpl_tlp_valid,
    output wire [TLP_PORT_COUNT-1:0]   tx_cpl_tlp_sop,
    output wire [TLP_PORT_COUNT-1:0]   tx_cpl_tlp_eop,
    input  wire [TLP_PORT_COUNT-1:0]   tx_cpl_tlp_ready
);



endmodule

`resetall
```



## 2. 设计要求

1. 能够同时仲裁n路的mrd包的输入，并且能够返回n路的cpld包。仲裁按照优先级来仲裁，即优先级从   rx_rd_req_tlp_valid[0]>rx_rd_req_tlp_valid[1]>......>rx_rd_req_tlp_valid[n]一次排列。可以通过控制rx_rd_req_tlp_ready来控制其余n-1路的数据使用

2. 由于输入的都是mrd包，所以返回的cpld包都需要按照mrd包申请的先后顺序一次返回，假设有2路mrd包同时进入，分别为a，b。其中a有4个mrd组成，每个mrd申请的长度512字节，b由3个mrd组成，每个申请的长度512字节。a走0通道，b走1通道，这样仲裁a->b->a->b->a->b->a。同时返回的cpld也应该遵循这个先后顺序。这里可以设置一个fifo用来记录申请的顺序，每个mrd包的通道号和长度存在fifo中，这样cpld的返回就可以根据fifo中记录的数据来做分发。

3. 当fifo的almost_full拉高时，rx_rd_req_tlp_ready应该拉低，不在接收任何个mrd包。

4. 当cpld返回了mrd的长度后，fifo中的数据应该读出。避免资源浪费

   

## 3. fifo逻辑

fifo的接口逻辑如下：其中xpm_fifo_sync是xilinx的原语。

```verilog
/****************************************************************************
 * @file    xpm_sync_fifo.v
 * @brief  
 * @author  weslie (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2025-01-22
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    weslie        |                        |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2025 welie
 * ***************************************************************************/

module xpm_sync_fifo#(
  //basic info
  parameter   WIDTH       =   512  ,		
  parameter   DEPTH       =   9    ,   	
  parameter   FIFO_TYPE   =   "std",
  parameter   FIFO_MEMORY =   "auto",
  parameter   PROG_FULL   = 10,
 
  parameter Asymmetric_Mode = 0,
  parameter WRITE_WIDTH_PARAM = 64,
  parameter READ_WIDTH_PARAM  = 32,

  parameter WRITE_WIDTH =
        Asymmetric_Mode ? WRITE_WIDTH_PARAM : WIDTH,

  parameter READ_WIDTH =
        Asymmetric_Mode ? READ_WIDTH_PARAM : WIDTH,
  //status flap 

  //---------+----------+-------------+--------------+---------------+-------------+-----------+-------+
  //bit map  | 15 14 13 |     12      |       11     |     10        |      9      |     8     | 7 6 5 |  
  //signal   |  3'b0    | data_valid  | almost_empty | rd_data_count | prog_empty  | underflow |  3'b0 |
  //---------+-----------------------------------------------------------------------------------------+
  //bit map  |   4              3            2               1             0  
  //signal   |wr_ack       almost_full  wr_data_count    prog_full      overflow
  //----------------------------------------------------------------------------------------------------+

  parameter   USER_ADV_FEATURES = "1f1f"
  
) (
  //clock and reset
  input                  	clk   ,
  input                  	rst   ,

  //fifo read and write signals
  input                  	wr_en ,
  input                  	rd_en ,
  input   [WRITE_WIDTH-1:0] 		data  ,
  output  [READ_WIDTH-1:0] 		dout  ,

  //status flag
  output  wire        		full  ,
  output  wire        		empty ,
  output  wire            almost_empty,
  output  wire		        almost_full ,
  output  wire            data_valid  ,
  output  wire            overflow    ,
  output  wire            prog_empty  ,
  output  wire            prog_full   ,
  output  wire[DEPTH : 0] rd_data_count,
  output  wire            underflow   ,
  output  wire            wr_ack      ,
  output  wire[DEPTH : 0] wr_data_count,
  output  wire            wr_rst_busy ,
  output  wire            rd_rst_busy
);

// +---------------------------------------------------------------------------------------------------------------------+
// | CASCADE_HEIGHT       | Integer            | Range: 0 - 64. Default value = 0.                                       |
// |---------------------------------------------------------------------------------------------------------------------|
// | 0- No Cascade Height, Allow Vivado Synthesis to choose.                                                             |
// | 1 or more - Vivado Synthesis sets the specified value as Cascade Height.                                            |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      CASCADE_HEIGHT      = 0;

// +---------------------------------------------------------------------------------------------------------------------+
// | DOUT_RESET_VALUE     | String             | Default value = 0.                                                      |
// |---------------------------------------------------------------------------------------------------------------------|
// | Reset value of read data path.                                                                                      |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      DOUT_RESET_VALUE    = "0";

// +---------------------------------------------------------------------------------------------------------------------+
// | ECC_MODE             | String             | Allowed values: no_ecc, en_ecc. Default value = no_ecc.                 |
// |---------------------------------------------------------------------------------------------------------------------|
// |                                                                                                                     |
// |   "no_ecc" - Disables ECC                                                                                           |
// |   "en_ecc" - Enables both ECC Encoder and Decoder                                                                   |
// |                                                                                                                     |
// | NOTE: ECC_MODE should be "no_ecc" if FIFO_MEMORY_TYPE is set to "auto". Violating this may result incorrect behavior.|
// +---------------------------------------------------------------------------------------------------------------------+
localparam      ECC_MODE          = (FIFO_MEMORY == "auto") ? "no_ecc" : "en_ecc";

// +---------------------------------------------------------------------------------------------------------------------+
// | FIFO_MEMORY_TYPE     | String             | Allowed values: auto, block, distributed, ultra. Default value = auto.  |
// |---------------------------------------------------------------------------------------------------------------------|
// | Designate the fifo memory primitive (resource type) to use-                                                         |
// |                                                                                                                     |
// |   "auto"- Allow Vivado Synthesis to choose                                                                          |
// |   "block"- Block RAM FIFO                                                                                           |
// |   "distributed"- Distributed RAM FIFO                                                                               |
// |   "ultra"- URAM FIFO                                                                                                |
// |                                                                                                                     |
// | NOTE: There may be a behavior mismatch if Block RAM or Ultra RAM specific features, like ECC or Asymmetry, are selected with FIFO_MEMORY_TYPE set to "auto".|
// +---------------------------------------------------------------------------------------------------------------------+
localparam      FIFO_MEMORY_TYPE  = FIFO_MEMORY;

// +---------------------------------------------------------------------------------------------------------------------+
// | FIFO_READ_LATENCY    | Integer            | Range: 0 - 100. Default value = 1.                                      |
// |---------------------------------------------------------------------------------------------------------------------|
// | Number of output register stages in the read data path                                                              |
// |                                                                                                                     |
// |   If READ_MODE = "fwft", then the only applicable value is 0                                                        |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      FIFO_READ_LATENCY = (FIFO_TYPE == "fwft") ? 0 : 1;

// +---------------------------------------------------------------------------------------------------------------------+
// | FIFO_WRITE_DEPTH     | Integer            | Range: 16 - 4194304. Default value = 2048.                              |
// |---------------------------------------------------------------------------------------------------------------------|
// | Defines the FIFO Write Depth, must be power of two                                                                  |
// |                                                                                                                     |
// |   In standard READ_MODE, the effective depth = FIFO_WRITE_DEPTH                                                     |
// |   In First-Word-Fall-Through READ_MODE, the effective depth = FIFO_WRITE_DEPTH+2                                    |
// |                                                                                                                     |
// | NOTE: The maximum FIFO size (width x depth) is limited to 150-Megabits.                                             |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      FIFO_WRITE_DEPTH  = 2**DEPTH;

// +---------------------------------------------------------------------------------------------------------------------+
// | FULL_RESET_VALUE     | Integer            | Range: 0 - 1. Default value = 0.                                        |
// |---------------------------------------------------------------------------------------------------------------------|
// | Sets full, almost_full and prog_full to FULL_RESET_VALUE during reset                                               |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      FULL_RESET_VALUE  = 0;

// +---------------------------------------------------------------------------------------------------------------------+
// | PROG_EMPTY_THRESH    | Integer            | Range: 3 - 4194304. Default value = 10.                                 |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specifies the minimum number of read words in the FIFO at or below which prog_empty is asserted.                    |
// |                                                                                                                     |
// |   Min_Value = 3 + (READ_MODE_VAL*2)                                                                                 |
// |   Max_Value = (FIFO_WRITE_DEPTH-3) - (READ_MODE_VAL*2)                                                              |
// |                                                                                                                     |
// | If READ_MODE = "std", then READ_MODE_VAL = 0; Otherwise READ_MODE_VAL = 1.                                          |
// | NOTE: The default threshold value is dependent on default FIFO_WRITE_DEPTH value. If FIFO_WRITE_DEPTH value is      |
// | changed, ensure the threshold value is within the valid range though the programmable flags are not used.           |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      PROG_EMPTY_THRESH = 10;

// +---------------------------------------------------------------------------------------------------------------------+
// | PROG_FULL_THRESH     | Integer            | Range: 3 - 4194301. Default value = 10.                                 |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specifies the maximum number of write words in the FIFO at or above which prog_full is asserted.                    |
// |                                                                                                                     |
// |   Min_Value = 3 + (READ_MODE_VAL*2*(FIFO_WRITE_DEPTH/FIFO_READ_DEPTH))                                              |
// |   Max_Value = (FIFO_WRITE_DEPTH-3) - (READ_MODE_VAL*2*(FIFO_WRITE_DEPTH/FIFO_READ_DEPTH))                           |
// |                                                                                                                     |
// | If READ_MODE = "std", then READ_MODE_VAL = 0; Otherwise READ_MODE_VAL = 1.                                          |
// | NOTE: The default threshold value is dependent on default FIFO_WRITE_DEPTH value. If FIFO_WRITE_DEPTH value is      |
// | changed, ensure the threshold value is within the valid range though the programmable flags are not used.           |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      PROG_FULL_THRESH  = PROG_FULL;

// +---------------------------------------------------------------------------------------------------------------------+
// | RD_DATA_COUNT_WIDTH  | Integer            | Range: 1 - 23. Default value = 1.                                       |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specifies the width of rd_data_count. To reflect the correct value, the width should be log2(FIFO_READ_DEPTH)+1.    |
// |                                                                                                                     |
// |   FIFO_READ_DEPTH = FIFO_WRITE_DEPTH*WRITE_DATA_WIDTH/READ_DATA_WIDTH                                               |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      RD_DATA_COUNT_WIDTH = DEPTH + 1;

// | READ_DATA_WIDTH      | Integer            | Range: 1 - 4096. Default value = 32.                                    |
// |---------------------------------------------------------------------------------------------------------------------|
// | Defines the width of the read data port, dout                                                                       |
// |                                                                                                                     |
// |   Write and read width aspect ratio must be 1:1, 1:2, 1:4, 1:8, 8:1, 4:1 and 2:1                                    |
// |   For example, if WRITE_DATA_WIDTH is 32, then the READ_DATA_WIDTH must be 32, 64,128, 256, 16, 8, 4.               |
// |                                                                                                                     |
// | NOTE:                                                                                                               |
// |                                                                                                                     |
// |   READ_DATA_WIDTH should be equal to WRITE_DATA_WIDTH if FIFO_MEMORY_TYPE is set to "auto". Violating this may result incorrect behavior. |
// |   The maximum FIFO size (width x depth) is limited to 150-Megabits.                                                 |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      READ_DATA_WIDTH     = READ_WIDTH;

// +---------------------------------------------------------------------------------------------------------------------+
// | READ_MODE            | String             | Allowed values: std, fwft. Default value = std.                         |
// |---------------------------------------------------------------------------------------------------------------------|
// |                                                                                                                     |
// |   "std"- standard read mode                                                                                         |
// |   "fwft"- First-Word-Fall-Through read mode                                                                         |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      READ_MODE           = FIFO_TYPE;

// +---------------------------------------------------------------------------------------------------------------------+
// | SIM_ASSERT_CHK       | Integer            | Range: 0 - 1. Default value = 0.                                        |
// |---------------------------------------------------------------------------------------------------------------------|
// | 0- Disable simulation message reporting. Messages related to potential misuse will not be reported.                 |
// | 1- Enable simulation message reporting. Messages related to potential misuse will be reported.                      |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      SIM_ASSERT_CHK      = 1;

// +---------------------------------------------------------------------------------------------------------------------+
// | USE_ADV_FEATURES     | String             | Default value = 0707.                                                   |
// |---------------------------------------------------------------------------------------------------------------------|
// | Enables data_valid, almost_empty, rd_data_count, prog_empty, underflow, wr_ack, almost_full, wr_data_count,         |
// | prog_full, overflow features.                                                                                       |
// |                                                                                                                     |
// |   Setting USE_ADV_FEATURES[0] to 1 enables overflow flag; Default value of this bit is 1                            |
// |   Setting USE_ADV_FEATURES[1] to 1 enables prog_full flag; Default value of this bit is 1                           |
// |   Setting USE_ADV_FEATURES[2] to 1 enables wr_data_count; Default value of this bit is 1                            |
// |   Setting USE_ADV_FEATURES[3] to 1 enables almost_full flag; Default value of this bit is 0                         |
// |   Setting USE_ADV_FEATURES[4] to 1 enables wr_ack flag; Default value of this bit is 0                              |
// |   Setting USE_ADV_FEATURES[8] to 1 enables underflow flag; Default value of this bit is 1                           |
// |   Setting USE_ADV_FEATURES[9] to 1 enables prog_empty flag; Default value of this bit is 1                          |
// |   Setting USE_ADV_FEATURES[10] to 1 enables rd_data_count; Default value of this bit is 1                           |
// |   Setting USE_ADV_FEATURES[11] to 1 enables almost_empty flag; Default value of this bit is 0                       |
// |   Setting USE_ADV_FEATURES[12] to 1 enables data_valid flag; Default value of this bit is 0                         |
// +---------------------------------------------------------------------------------------------------------------------+
localparam  USE_ADV_FEATURES = USER_ADV_FEATURES;

// +---------------------------------------------------------------------------------------------------------------------+
// | WAKEUP_TIME          | Integer            | Range: 0 - 2. Default value = 0.                                        |
// |---------------------------------------------------------------------------------------------------------------------|
// |                                                                                                                     |
// |   0 - Disable sleep                                                                                                 |
// |   2 - Use Sleep Pin                                                                                                 |
// |                                                                                                                     |
// | NOTE: WAKEUP_TIME should be 0 if FIFO_MEMORY_TYPE is set to "auto". Violating this may result incorrect behavior.   |
// +---------------------------------------------------------------------------------------------------------------------+
localparam    WAKEUP_TIME = (FIFO_MEMORY_TYPE == "auto") ? 0 : 2;

// +---------------------------------------------------------------------------------------------------------------------+
// | WRITE_DATA_WIDTH     | Integer            | Range: 1 - 4096. Default value = 32.                                    |
// |---------------------------------------------------------------------------------------------------------------------|
// | Defines the width of the write data port, din                                                                       |
// |                                                                                                                     |
// |   Write and read width aspect ratio must be 1:1, 1:2, 1:4, 1:8, 8:1, 4:1 and 2:1                                    |
// |   For example, if WRITE_DATA_WIDTH is 32, then the READ_DATA_WIDTH must be 32, 64,128, 256, 16, 8, 4.               |
// |                                                                                                                     |
// | NOTE:                                                                                                               |
// |                                                                                                                     |
// |   WRITE_DATA_WIDTH should be equal to READ_DATA_WIDTH if FIFO_MEMORY_TYPE is set to "auto". Violating this may result incorrect behavior.|
// |   The maximum FIFO size (width x depth) is limited to 150-Megabits.                                                 |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      WRITE_DATA_WIDTH    = WRITE_WIDTH;  

// +---------------------------------------------------------------------------------------------------------------------+
// | WR_DATA_COUNT_WIDTH  | Integer            | Range: 1 - 23. Default value = 1.                                       |
// |---------------------------------------------------------------------------------------------------------------------|
// | Specifies the width of wr_data_count. To reflect the correct value, the width should be log2(FIFO_WRITE_DEPTH)+1.   |
// +---------------------------------------------------------------------------------------------------------------------+
localparam      WR_DATA_COUNT_WIDTH = DEPTH + 1;




xpm_fifo_sync #(
      .CASCADE_HEIGHT       (CASCADE_HEIGHT      ),       
      .DOUT_RESET_VALUE     (DOUT_RESET_VALUE    ),    
      .ECC_MODE             (ECC_MODE            ),     
      .FIFO_MEMORY_TYPE     (FIFO_MEMORY_TYPE    ),
      .FIFO_READ_LATENCY    (FIFO_READ_LATENCY   ),   
      .FIFO_WRITE_DEPTH     (FIFO_WRITE_DEPTH    ),  
      .FULL_RESET_VALUE     (FULL_RESET_VALUE    ),     
      .PROG_EMPTY_THRESH    (PROG_EMPTY_THRESH   ),   
      .PROG_FULL_THRESH     (PROG_FULL_THRESH    ),   
      .RD_DATA_COUNT_WIDTH  (RD_DATA_COUNT_WIDTH ),  
      .READ_DATA_WIDTH      (READ_DATA_WIDTH     ),   
      .READ_MODE            (READ_MODE           ),        
      .SIM_ASSERT_CHK       (SIM_ASSERT_CHK      ),        
      .USE_ADV_FEATURES     (USE_ADV_FEATURES    ), 
      .WAKEUP_TIME          (WAKEUP_TIME         ),          
      .WRITE_DATA_WIDTH     (WRITE_DATA_WIDTH    ),     
      .WR_DATA_COUNT_WIDTH  (WR_DATA_COUNT_WIDTH )    
  )xpm_fifo_sync_inst (
      .almost_empty         (almost_empty ),   
      .almost_full          (almost_full  ),   
      .data_valid           (data_valid   ),      
      .dout                 (dout         ),      
      .empty                (empty        ),              
      .full                 (full         ),            
      .overflow             (overflow     ),    
      .prog_empty           (prog_empty   ),      
      .prog_full            (prog_full    ),       
      .rd_data_count        (rd_data_count), 
      .underflow            (underflow    ), 
      .wr_ack               (wr_ack       ),              
      .wr_data_count        (wr_data_count),         
      .din                  (data         ),              
      .rd_en                (rd_en        ),               
      .rst                  (rst          ),                  
      .wr_clk               (clk          ),              
      .wr_en                (wr_en        ),
      .sleep                (0            ), 
      .injectdbiterr        (1'b0         ),
      .injectsbiterr        (1'b0         ), 
      .rd_rst_busy          (rd_rst_busy  ),     
      .sbiterr              (),     
      .wr_rst_busy          (wr_rst_busy  ),     
      .dbiterr              ()              
   );
    
endmodule


```



## 4.testbench

仿真测试用例如下：

1.  读通道0读取内存空间0xcfcc0000里面的数据，长度为4KB。读通道1读取内存空间0xaffc0000里面的数据，长度为4KB。两者的valid同步拉高。
2.  读通道0读取内存空间0xcfcc0000里面的数据，长度为4KB。读通道1读取内存空间0xaffc0000里面的数据，长度为4KB。两者的valid间隔一个时钟周期同步拉高。
3.  读通道0读取内存空间0xcfcc0000里面的数据，长度为4KB。读通道1读取内存空间0xaffc0000里面的数据，长度为4KB。等通道0的cpld全部接收完成后通道1的valid再拉高。



