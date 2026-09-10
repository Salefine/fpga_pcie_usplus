/****************************************************************************
 * @file    dma_intr_queue.v
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


`timescale 1ns/1ps

module dma_intr_queue #(
    parameter MSI_COUNT    = 1,
    parameter USER_MSI_IRQ = 28
) (
    input  wire                      clk,
    input  wire                      rst,

    input  wire [USER_MSI_IRQ + 1 : 0] msi_irq_req,
    output reg  [USER_MSI_IRQ + 1 : 0] msi_irq_ack,

    input  wire [3:0]                cfg_interrupt_msi_enable,
    input  wire [7:0]                cfg_interrupt_msi_vf_enable,
    input  wire [11:0]               cfg_interrupt_msi_mmenable,
    input  wire                      cfg_interrupt_msi_mask_update,
    input  wire [31:0]               cfg_interrupt_msi_data,
    output wire [3:0]                cfg_interrupt_msi_select,
    output wire [31:0]               cfg_interrupt_msi_int,
    output wire [31:0]               cfg_interrupt_msi_pending_status,
    output wire                      cfg_interrupt_msi_pending_status_data_enable,
    output wire [3:0]                cfg_interrupt_msi_pending_status_function_num,
    output wire [7:0]                cfg_interrupt_msi_function_number,
    input  wire                      cfg_interrupt_msi_sent,
    input  wire                      cfg_interrupt_msi_fail,
    output wire [2:0]                cfg_interrupt_msi_attr,
    output wire                      cfg_interrupt_msi_tph_present,
    output wire [1:0]                cfg_interrupt_msi_tph_type,
    output wire [8:0]                cfg_interrupt_msi_tph_st_tag
);

wire cfg_interrupt_msi_function_number_int;
wire  msi_irq_init;

assign msi_irq_init = |msi_irq_req;


pcie_us_msi #(
    .MSI_COUNT(MSI_COUNT)
) pcie_msi_irq (
    .clk                                           (clk),
    .rst                                           (rst),
    .msi_irq                                       (msi_irq_init),
    .cfg_interrupt_msi_enable                      (cfg_interrupt_msi_enable),
    .cfg_interrupt_msi_vf_enable                   (cfg_interrupt_msi_vf_enable),
    .cfg_interrupt_msi_mmenable                    (cfg_interrupt_msi_mmenable),
    .cfg_interrupt_msi_mask_update                 (cfg_interrupt_msi_mask_update),
    .cfg_interrupt_msi_data                        (cfg_interrupt_msi_data),
    .cfg_interrupt_msi_select                      (cfg_interrupt_msi_select),
    .cfg_interrupt_msi_int                         (cfg_interrupt_msi_int),
    .cfg_interrupt_msi_pending_status              (cfg_interrupt_msi_pending_status),
    .cfg_interrupt_msi_pending_status_data_enable  (cfg_interrupt_msi_pending_status_data_enable),
    .cfg_interrupt_msi_pending_status_function_num (cfg_interrupt_msi_pending_status_function_num),
    .cfg_interrupt_msi_sent                        (cfg_interrupt_msi_sent),
    .cfg_interrupt_msi_fail                        (cfg_interrupt_msi_fail),
    .cfg_interrupt_msi_attr                        (cfg_interrupt_msi_attr),
    .cfg_interrupt_msi_tph_present                 (cfg_interrupt_msi_tph_present),
    .cfg_interrupt_msi_tph_type                    (cfg_interrupt_msi_tph_type),
    .cfg_interrupt_msi_tph_st_tag                  (cfg_interrupt_msi_tph_st_tag),
    .cfg_interrupt_msi_function_number             (cfg_interrupt_msi_function_number_int)
);

assign cfg_interrupt_msi_function_number = {4'b0, cfg_interrupt_msi_function_number_int};

endmodule