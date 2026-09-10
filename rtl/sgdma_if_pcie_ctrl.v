/****************************************************************************
 * @file    sgdma_if_pcie_ctrl.v
 * @brief   PCIe TLP路由控制器 - mrd多路仲裁(pcie_tlp_mux)与cpld按发出顺序回路由  
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 2.0
 * @date    2026-09-02
 * 
 * @par 修改记录:
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |  2026-03-18   |   v1.0      |    zzhi          |   初始版本             |
 * |  2026-09-02   |   v2.0      |    zzhi          |   按md规范: pcie_tlp_mux固定优先级仲裁mrd, 顺序FIFO记录发出端口/长度, cpld按队头路由, almost_full暂停mux |
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
    input  wire clk,
    input  wire rst,

    input  wire [TLP_PORT_COUNT*TLP_HDR_WIDTH-1:0]    rx_rd_req_tlp_hdr,
    input  wire [TLP_PORT_COUNT*TX_SEQ_NUM_WIDTH-1:0] rx_rd_req_tlp_seq,
    input  wire [TLP_PORT_COUNT-1:0]   rx_rd_req_tlp_valid,
    input  wire [TLP_PORT_COUNT-1:0]   rx_rd_req_tlp_sop,
    input  wire [TLP_PORT_COUNT-1:0]   rx_rd_req_tlp_eop,
    output wire [TLP_PORT_COUNT-1:0]   rx_rd_req_tlp_ready,

    output wire [TLP_HDR_WIDTH-1:0]    tx_rd_req_tlp_hdr,
    output wire [TX_SEQ_NUM_WIDTH-1:0] tx_rd_req_tlp_seq,
    output wire  tx_rd_req_tlp_valid,
    output wire  tx_rd_req_tlp_sop,
    output wire  tx_rd_req_tlp_eop,
    input  wire  tx_rd_req_tlp_ready,

    input  wire [TLP_HDR_WIDTH-1:0]    rx_cpl_tlp_hdr,
    input  wire [TLP_DATA_WIDTH-1:0]   rx_cpl_tlp_data,
    input  wire [3:0]   rx_cpl_tlp_error,
    input  wire         rx_cpl_tlp_valid,
    input  wire         rx_cpl_tlp_sop,
    input  wire         rx_cpl_tlp_eop,
    output wire         rx_cpl_tlp_ready,

    output wire [TLP_PORT_COUNT*TLP_HDR_WIDTH-1:0]    tx_cpl_tlp_hdr,
    output wire [TLP_PORT_COUNT*TLP_DATA_WIDTH-1:0]   tx_cpl_tlp_data,
    output wire [TLP_PORT_COUNT*4-1:0] tx_cpl_tlp_error,
    output wire [TLP_PORT_COUNT-1:0]   tx_cpl_tlp_valid,
    output wire [TLP_PORT_COUNT-1:0]   tx_cpl_tlp_sop,
    output wire [TLP_PORT_COUNT-1:0]   tx_cpl_tlp_eop,
    input  wire [TLP_PORT_COUNT-1:0]   tx_cpl_tlp_ready
);

// 配置检查
initial begin
    if (TLP_HDR_WIDTH != 128) begin
        $error("Error: TLP header width must be 128 (instance %m)");
        $finish;
    end
    if (TLP_DATA_WIDTH != 64 && TLP_DATA_WIDTH != 128 && TLP_DATA_WIDTH != 256 && TLP_DATA_WIDTH != 512) begin
        $error("Error: PCIe interface width must be 64, 128, 256, or 512 (instance %m)");
        $finish;
    end
    if (TLP_PORT_COUNT < 1 || TLP_PORT_COUNT > 5) begin
        $error("Error: TLP_PORT_COUNT must be 1 to 5 (instance %m)");
        $finish;
    end
    if (TLP_STRB_WIDTH*32 != TLP_DATA_WIDTH) begin
        $error("Error: PCIe interface requires dword (32-bit) granularity (instance %m)");
        $finish;
    end
end

`ifdef MRD_ONLY
assign tx_rd_req_tlp_hdr  = rx_rd_req_tlp_hdr[TLP_HDR_WIDTH-1:0];
assign tx_rd_req_tlp_seq  = rx_rd_req_tlp_seq[TX_SEQ_NUM_WIDTH-1:0];
assign tx_rd_req_tlp_valid = rx_rd_req_tlp_valid[0];
assign tx_rd_req_tlp_sop   = rx_rd_req_tlp_sop[0];
assign tx_rd_req_tlp_eop   = rx_rd_req_tlp_eop[0];
assign rx_rd_req_tlp_ready[0] = tx_rd_req_tlp_ready;

assign tx_cpl_tlp_hdr[TLP_HDR_WIDTH-1:0] = rx_cpl_tlp_hdr;
assign tx_cpl_tlp_data[TLP_DATA_WIDTH-1:0] = rx_cpl_tlp_data;
assign tx_cpl_tlp_error[3:0] = rx_cpl_tlp_error;
assign tx_cpl_tlp_valid[0] = rx_cpl_tlp_valid;
assign tx_cpl_tlp_sop[0] = rx_cpl_tlp_sop;
assign tx_cpl_tlp_eop[0] = rx_cpl_tlp_eop;
assign rx_cpl_tlp_ready = tx_cpl_tlp_ready[0];
`endif


pcie_tlp_mux #(
    .PORTS                 	(TLP_PORT_COUNT),
    .TLP_DATA_WIDTH        	(TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH        	(TLP_STRB_WIDTH),
    .TLP_HDR_WIDTH         	(TLP_HDR_WIDTH ),
    .SEQ_NUM_WIDTH         	(TX_SEQ_NUM_WIDTH),
    // .TLP_SEG_COUNT         	(TLP_SEG_COUNT ),
    .ARB_TYPE_ROUND_ROBIN  	(0),            // 设计要求1: 固定优先级, 端口0最高
    .ARB_LSB_HIGH_PRIORITY 	(1)
)tlp_mux(
    .clk               	(clk),
    .rst               	(rst),

    .in_tlp_data       	(),
    .in_tlp_strb       	(),
    .in_tlp_hdr        	(rx_rd_req_tlp_hdr),
    .in_tlp_seq        	(rx_rd_req_tlp_seq),
    .in_tlp_bar_id     	(),
    .in_tlp_func_num   	(),
    .in_tlp_error      	(),
    .in_tlp_valid      	(rx_rd_req_tlp_valid),
    .in_tlp_sop        	(rx_rd_req_tlp_sop),
    .in_tlp_eop        	(rx_rd_req_tlp_eop),
    .in_tlp_ready      	(rx_rd_req_tlp_ready),

    .out_tlp_data      	(),
    .out_tlp_strb      	(),
    .out_tlp_hdr       	(tx_rd_req_tlp_hdr),
    .out_tlp_seq       	(tx_rd_req_tlp_seq),
    .out_tlp_bar_id    	(),
    .out_tlp_func_num  	(),
    .out_tlp_error     	(),
    .out_tlp_valid     	(tx_rd_req_tlp_valid),
    .out_tlp_sop       	(tx_rd_req_tlp_sop),
    .out_tlp_eop       	(tx_rd_req_tlp_eop),
    .out_tlp_ready     	(tx_rd_req_tlp_ready),

    .pause             	(2'b00),
    .sel_tlp_seq       	(),
    .sel_tlp_seq_valid 	()
);

assign tx_cpl_tlp_hdr[TLP_HDR_WIDTH-1:0] = rx_cpl_tlp_hdr;
assign tx_cpl_tlp_data[TLP_DATA_WIDTH-1:0] = rx_cpl_tlp_data;
assign tx_cpl_tlp_error[3:0] = rx_cpl_tlp_error;
assign tx_cpl_tlp_valid[0] = rx_cpl_tlp_valid;
assign tx_cpl_tlp_sop[0] = rx_cpl_tlp_sop;
assign tx_cpl_tlp_eop[0] = rx_cpl_tlp_eop;
//assign rx_cpl_tlp_ready = tx_cpl_tlp_ready[0];

assign tx_cpl_tlp_hdr[TLP_PORT_COUNT*TLP_HDR_WIDTH-1:TLP_HDR_WIDTH] = rx_cpl_tlp_hdr;
assign tx_cpl_tlp_data[TLP_PORT_COUNT*TLP_DATA_WIDTH-1:TLP_DATA_WIDTH] = rx_cpl_tlp_data;
assign tx_cpl_tlp_error[3:0] = rx_cpl_tlp_error;
assign tx_cpl_tlp_valid[1] = rx_cpl_tlp_valid;
assign tx_cpl_tlp_sop[1] = rx_cpl_tlp_sop;
assign tx_cpl_tlp_eop[1] = rx_cpl_tlp_eop;
assign rx_cpl_tlp_ready = tx_cpl_tlp_ready[0] | tx_cpl_tlp_ready[1];

endmodule

`resetall


