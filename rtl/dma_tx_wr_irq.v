/****************************************************************************
 * @file    dma_tx_wr_irq.v
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

 `resetall
 `timescale 1ns/1ps
 `default_nettype none

module dma_tx_wr_irq#(
    parameter AXIS_PCIE_DATA_WIDTH      = 512,
    parameter AXIS_PCIE_KEEP_WIDTH      = (AXIS_PCIE_DATA_WIDTH/32),
    parameter AXIS_PCIE_RC_USER_WIDTH   = AXIS_PCIE_DATA_WIDTH < 512 ? 75 : 161,
    parameter AXIS_PCIE_RQ_USER_WIDTH   = AXIS_PCIE_DATA_WIDTH < 512 ? 60 : 137
)(
    input wire  clk,
    input wire  rst,

    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]    m_axis_rq_tkeep,
    input  wire                               m_axis_rq_tlast,
    input  wire                               m_axis_rq_tready,
    input wire [AXIS_PCIE_RQ_USER_WIDTH-1:0]  m_axis_rq_tuser,
    input wire                                m_axis_rq_tvalid,

    input  wire [31:0] tx_wr_length,
    input  wire [2:0] cfg_max_payload,
    input  wire tx_wr_start,
    output wire tx_wr_irq
);

initial begin
    if (AXIS_PCIE_DATA_WIDTH != 64 && AXIS_PCIE_DATA_WIDTH != 128 && AXIS_PCIE_DATA_WIDTH != 256 && AXIS_PCIE_DATA_WIDTH != 512) begin
        $error("Error: PCIe interface width must be 64, 128, 256, or 512 (instance %m)");
        $finish;
    end

    if (AXIS_PCIE_KEEP_WIDTH * 32 != AXIS_PCIE_DATA_WIDTH) begin
        $error("Error: PCIe interface requires dword (32-bit) granularity (instance %m)");
        $finish;
    end
end

localparam TX_WR_STATE_IDLE = 1'b0,TX_WR_STATE_START = 1'b1;
localparam TX_RD_STATE_IDLE = 1'b0,TX_RD_STATE_START = 1'b1;

reg [0:0] tx_wr_state_reg, tx_wr_state_next;
reg [31:0] tx_wr_length_reg = 0, tx_wr_length_next;
reg tx_wr_start_reg = 0, tx_wr_start_next;
(* MARK_DEBUG="true" *)reg [31:0]irq_cycle_reg = 0,irq_cycle_next;
(* MARK_DEBUG="true" *)reg tx_wr_irq_reg = 0, tx_wr_irq_next;


assign tx_wr_irq = tx_wr_irq_reg;


generate 
    if(AXIS_PCIE_DATA_WIDTH == 512)begin
        wire [1:0] is_rq_sop = m_axis_rq_tuser[21:20];
        wire [1:0] is_rq_sop0_ptr = m_axis_rq_tuser[23:22];
        wire [1:0] is_rq_sop1_ptr = m_axis_rq_tuser[25:24];
        wire [1:0] is_rq_eop = m_axis_rq_tuser[27:26];
        wire [4:0] is_rq_eop0_ptr = {1'b0, m_axis_rq_tuser[31:28]};
        wire [4:0] is_rq_eop1_ptr = {1'b0, m_axis_rq_tuser[35:32]};

        always @(*) begin
            tx_wr_state_next = tx_wr_state_reg;
            tx_wr_start_next = tx_wr_start_reg;
            tx_wr_length_next = tx_wr_length_reg;
            irq_cycle_next = irq_cycle_reg;
            tx_wr_irq_next = tx_wr_irq_reg;

            case (tx_wr_state_reg)
                TX_WR_STATE_IDLE: begin
                    tx_wr_start_next = tx_wr_start;
                    tx_wr_length_next = 'b0;
                    irq_cycle_next = 'b0;
                    tx_wr_irq_next = 'b0;
                    if (tx_wr_start_next && (~tx_wr_start_reg)) begin
                        tx_wr_length_next = tx_wr_length;
                        tx_wr_state_next = TX_WR_STATE_START;
                    end
                end

                TX_WR_STATE_START : begin
                    if (m_axis_rq_tvalid & m_axis_rq_tready) begin
                        if(is_rq_sop == 2'b00)begin //no frame start
                            if (is_rq_eop == 2'b00) begin //no frame end
                                irq_cycle_next = irq_cycle_reg + 7'd64;
                            end
                            else if (is_rq_eop == 2'b01)begin // 1 frame end
                                irq_cycle_next = irq_cycle_reg + ((is_rq_eop0_ptr + 1'b1) << 2);
                            end
                        end
                        else if(is_rq_sop == 2'b01)begin //only 1 frame start
                            //frame start @ 0
                            if (is_rq_sop0_ptr == 2'b00) begin
                                if (is_rq_eop == 2'b01) begin
                                    irq_cycle_next = irq_cycle_reg + ((is_rq_eop0_ptr - 5'd3) << 2 );
                                end
                                else if (is_rq_eop == 2'b00) begin
                                    irq_cycle_next = irq_cycle_reg + 6'd48;
                                end
                            end

                            //frame start @ 32
                            else if (is_rq_sop0_ptr == 2'b10) begin
                                if (is_rq_eop == 2'b01) begin
                                    irq_cycle_next = irq_cycle_reg + ((is_rq_eop0_ptr + 1'b1) << 2) + 5'd16;
                                end
                                else if(is_rq_eop == 2'b11)begin
                                    irq_cycle_next = irq_cycle_reg + ((is_rq_eop0_ptr + 1'b1) << 2) + ((is_rq_eop1_ptr - 5'd11) << 2);
                                end
                            end
                        end
                        else if(is_rq_sop == 2'b11)begin //2 frame start
                            if(is_rq_eop == 2'b01)begin
                                irq_cycle_next = irq_cycle_reg + ((is_rq_eop0_ptr - 5'd3) << 2) + 5'd16;
                            end
                            else if(is_rq_eop == 2'b11)begin
                                irq_cycle_next = irq_cycle_reg + ((is_rq_eop0_ptr - 5'd3) << 2) + ((is_rq_eop1_ptr - 5'd11) << 2);
                            end
                        end
                    end

                    tx_wr_irq_next = (irq_cycle_next >= tx_wr_length_reg);
                    if (tx_wr_irq_next) begin
                        tx_wr_state_next = TX_WR_STATE_IDLE;
                    end
                end
                default: begin
                end
            endcase
        end

        always @(posedge clk)begin
            if (rst) begin
                tx_wr_state_reg <= TX_WR_STATE_IDLE;
                tx_wr_start_reg <= 'b0;
                tx_wr_length_reg <= 'b0;
                irq_cycle_reg <= 'b0;
                tx_wr_irq_reg <= 'b0;
            end
            else begin
                tx_wr_state_reg <= tx_wr_state_next;
                tx_wr_start_reg <= tx_wr_start_next;
                tx_wr_length_reg <= tx_wr_length_next;
                irq_cycle_reg <= irq_cycle_next;
                if (tx_wr_irq_reg) begin
                    tx_wr_irq_reg <= 'b0;
                end
                else if (tx_wr_irq_next) begin
                    tx_wr_irq_reg <= 1'b1;
                end
            end
        end

    end
    else begin
        always @(*) begin
            tx_wr_state_next = tx_wr_state_reg;
            tx_wr_start_next = tx_wr_start_reg;
            tx_wr_length_next = tx_wr_length_reg;
            irq_cycle_next = irq_cycle_reg;
            tx_wr_irq_next = tx_wr_irq_reg;

            case (tx_wr_state_reg)
                TX_WR_STATE_IDLE : begin
                    tx_wr_start_next = tx_wr_start;
                    tx_wr_length_next = 'b0;
                    irq_cycle_next = 'b0;
                    tx_wr_irq_next = 'b0;
                    if (tx_wr_start_next && (~tx_wr_start_reg)) begin
                        tx_wr_length_next = tx_wr_length;
                        tx_wr_state_next = TX_WR_STATE_START;
                    end                    
                end

                TX_WR_STATE_START : begin
                    if (m_axis_rq_tready && m_axis_rq_tvalid && m_axis_rq_tlast) begin
                        irq_cycle_next = irq_cycle_reg + cfg_max_payload;
                    end
                    
                    tx_wr_irq_next = (irq_cycle_next >= tx_wr_length_reg);
                    if (tx_wr_irq_next) begin
                        tx_wr_state_next = TX_WR_STATE_IDLE;
                    end
                end
                default: begin
                    
                end
            endcase
        end

        always @(posedge clk) begin
            if (rst) begin
                tx_wr_state_reg <= TX_WR_STATE_IDLE;
                tx_wr_start_reg <= 'b0;
                tx_wr_length_reg <= 'b0;
                irq_cycle_reg <= 'b0;
                tx_wr_irq_reg <= 'b0;
            end
            else begin
                tx_wr_state_reg <= tx_wr_state_next;
                tx_wr_start_reg <= tx_wr_start_next;
                tx_wr_length_reg <= tx_wr_length_next;
                irq_cycle_reg <= irq_cycle_next;
                if (tx_wr_irq_reg) begin
                    tx_wr_irq_reg <= 'b0;
                end
                else if (tx_wr_irq_next) begin
                    tx_wr_irq_reg <= 1'b1;
                end      
            end
        end
    end
endgenerate


endmodule //dma_tx_wr_irq
 `resetall
