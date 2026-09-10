/****************************************************************************
 * @file    dma_rx_rd_irq.v
 * @brief  
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 1.1
 * @date    2026-09-04
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    zzhi          |                        |
 * | 2026-09-04    |   v1.1      |    zzhi          | fix: cycle_reg跨传输累计致done IRQ提前/瞬时触发, IDLE态清零 |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2026 zzhi
 * ***************************************************************************/

 `resetall
 `timescale 1ns/1ps
 `default_nettype none

module dma_rx_rd_irq#(
    parameter AXIS_PCIE_DATA_WIDTH      = 512,
    parameter AXIS_PCIE_KEEP_WIDTH      = (AXIS_PCIE_DATA_WIDTH/32),
    parameter AXIS_PCIE_RC_USER_WIDTH   = AXIS_PCIE_DATA_WIDTH < 512 ? 75 : 161
)(
    input wire clk,
    input wire rst,

    input  wire [AXIS_PCIE_DATA_WIDTH - 1:0]  s_axis_rc_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]    s_axis_rc_tkeep,
    // input  wire                               s_axis_rc_tlast,
    input  wire                               s_axis_rc_tready,
    input  wire [AXIS_PCIE_RC_USER_WIDTH-1:0] s_axis_rc_tuser,
    input  wire                               s_axis_rc_tvalid,

    input  wire [31:0] tx_rd_length,
    input  wire [2:0] cfg_max_read_payload,
    input  wire tx_rd_start,
    output wire tx_rd_irq
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

localparam  [0:0]   RD_STATE_IDLE = 1'b0, 
                    RD_STATE_START= 1'b1;
localparam  BYTE_EN_WIDTH = AXIS_PCIE_KEEP_WIDTH * 4;

integer i;
reg [0:0] rd_state_reg , rd_state_next;
reg [31:0] tx_rd_length_reg = 0, tx_rd_length_next;
reg tx_rd_start_reg = 0, tx_rd_start_next;
(* MARK_DEBUG="true" *)reg [31:0] cycle_reg = 0, cycle_next;
reg tx_rd_irq_reg = 0, tx_rd_irq_next;

wire [12:0]byte_count =  s_axis_rc_tdata[28 : 16]; //128bit header
wire [9:0] dword_count = s_axis_rc_tdata[42 : 32];

assign tx_rd_irq = tx_rd_irq_reg;
generate 
    if (AXIS_PCIE_DATA_WIDTH == 512) begin
        wire [3:0]is_rc_sop = s_axis_rc_tuser[BYTE_EN_WIDTH + 3 : BYTE_EN_WIDTH];
        wire [9:0] sof0_dw = s_axis_rc_tdata[42 : 32]   << 2;//128bit
        wire [9:0] sof1_dw = s_axis_rc_tdata[170 : 160] << 2;
        wire [9:0] sof2_dw = s_axis_rc_tdata[298 : 288] << 2;
        wire [9:0] sof3_dw = s_axis_rc_tdata[426 : 416] << 2;
        wire [9:0] sof_dw[0:3]; // = {sof3_dw , sof2_dw , sof1_dw , sof0_dw};
        
        wire [1:0] is_sop0_ptr = s_axis_rc_tuser[69 : 68];
        wire [1:0] is_sop1_ptr = s_axis_rc_tuser[71 : 70];
        wire [1:0] is_sop2_ptr = s_axis_rc_tuser[73 : 72];
        wire [1:0] is_sop3_ptr = s_axis_rc_tuser[75 : 74];
        wire [1:0] is_sop_ptr[0:3] ;

        assign sof_dw[0] = sof0_dw;
        assign sof_dw[1] = sof1_dw;
        assign sof_dw[2] = sof2_dw;
        assign sof_dw[3] = sof3_dw;
        assign is_sop_ptr[0] =  is_sop0_ptr;
        assign is_sop_ptr[1] =  is_sop1_ptr;
        assign is_sop_ptr[2] =  is_sop2_ptr;
        assign is_sop_ptr[3] =  is_sop3_ptr;

        always @(*) begin
          tx_rd_length_next = tx_rd_length_reg;
          tx_rd_start_next = tx_rd_start_reg;
          rd_state_next = rd_state_reg;
          cycle_next = cycle_reg;
          tx_rd_irq_next = tx_rd_irq_reg;
          case (rd_state_reg)
            RD_STATE_IDLE : begin
                tx_rd_length_next = tx_rd_length;
                tx_rd_irq_next = 'b0;
                tx_rd_start_next = tx_rd_start;
                cycle_next = 'b0;
                if (tx_rd_start_next && (~tx_rd_start_reg)) begin
                    rd_state_next = RD_STATE_START;
                end
            end

            RD_STATE_START : begin
                if (s_axis_rc_tready && s_axis_rc_tvalid) begin
                    if (is_rc_sop == 4'b0001) begin
                        cycle_next = cycle_reg + sof_dw[is_sop_ptr[0]];
                    end
                    else if (is_rc_sop == 4'b0011) begin
                        cycle_next = cycle_reg + sof_dw[is_sop_ptr[0]] + sof_dw[is_sop_ptr[1]];
                    end
                    else if (is_rc_sop == 4'b0111) begin
                        cycle_next = cycle_reg + sof_dw[is_sop_ptr[0]] + sof_dw[is_sop_ptr[1]] + sof_dw[is_sop_ptr[2]];
                    end
                    else if (is_rc_sop == 4'b1111) begin
                        cycle_next = cycle_reg + sof_dw[is_sop_ptr[0]] + sof_dw[is_sop_ptr[1]] + sof_dw[is_sop_ptr[2]] + sof_dw[is_sop_ptr[3]];
                    end
                end

                if ((cycle_reg >= tx_rd_length_reg) && (cycle_reg > 0)) begin
                    tx_rd_irq_next = 1;
                    rd_state_next = RD_STATE_IDLE;
                end
            end
            default:begin
                
            end 
          endcase
        end

    end
    else if (AXIS_PCIE_DATA_WIDTH == 64) begin
        always @(*) begin
          tx_rd_length_next = tx_rd_length_reg;
          tx_rd_start_next = tx_rd_start_reg;
          rd_state_next = rd_state_reg;
          cycle_next = cycle_reg;
          tx_rd_irq_next = tx_rd_irq_reg;
      
          case (rd_state_reg)
              RD_STATE_IDLE : begin
                  tx_rd_length_next = tx_rd_length;
                  tx_rd_irq_next = 'b0;
                  tx_rd_start_next = tx_rd_start;
                  cycle_next = 'b0;
                  if (tx_rd_start_next && (~tx_rd_start_reg)) begin
                      rd_state_next = RD_STATE_START;
                  end
              end
      
              RD_STATE_START : begin
                  if (s_axis_rc_tready && s_axis_rc_tvalid) begin
                      for (i = 0; i < 8 ; i = i + 1) begin
                          cycle_next = cycle_reg + 1'b1;
                      end
                  end
      
                  if ((cycle_reg >= tx_rd_length_reg) && (cycle_reg > 0)) begin
                      tx_rd_irq_next = 1;
                      rd_state_next = RD_STATE_IDLE;
                  end
              end
      
              default: begin
              end
          endcase
      end
    end
    else if(AXIS_PCIE_DATA_WIDTH == 128 || AXIS_PCIE_DATA_WIDTH == 256)begin

      wire is_rc_sof1 = s_axis_rc_tuser[BYTE_EN_WIDTH];
      wire is_rc_sof2 = s_axis_rc_tuser[BYTE_EN_WIDTH + 1];
      wire [9:0] dword_straddle = s_axis_rc_tdata[170 : 160];

      always @(*) begin
          tx_rd_length_next = tx_rd_length_reg;
          tx_rd_start_next = tx_rd_start_reg;
          rd_state_next = rd_state_reg;
          cycle_next = cycle_reg;
          tx_rd_irq_next = tx_rd_irq_reg;
      
          case (rd_state_reg) 
              RD_STATE_IDLE : begin
                  tx_rd_length_next = tx_rd_length;
                  tx_rd_irq_next = 'b0;
                  tx_rd_start_next = tx_rd_start;
                  cycle_next = 'b0;
                  if (tx_rd_start_next && (~tx_rd_start_reg)) begin
                      rd_state_next = RD_STATE_START;
                  end
              end
      
              RD_STATE_START : begin
                  if (s_axis_rc_tready && s_axis_rc_tvalid) begin
                      if (is_rc_sof1 && is_rc_sof2) begin
                          cycle_next = dword_count + dword_straddle + cycle_reg;
                      end
                      else if (is_rc_sof1) begin
                          cycle_next = cycle_reg + dword_count;
                      end
                  end
      
                  if ((cycle_reg >= tx_rd_length_reg) && (cycle_reg > 0)) begin
                      tx_rd_irq_next = 1;
                      rd_state_next = RD_STATE_IDLE;
                  end
              end
      
              default: begin
              end
          endcase
      end
  
    end
endgenerate

always @(posedge clk) begin
    if (rst) begin
        tx_rd_length_reg <= 'b0;
        tx_rd_start_reg <= 'b0;
        rd_state_reg <= RD_STATE_IDLE;
        cycle_reg <= 'b0;
        tx_rd_irq_reg <= 'b0;
    end
    else begin
        tx_rd_length_reg <= tx_rd_length_next;
        tx_rd_start_reg <= tx_rd_start_next;
        rd_state_reg <= rd_state_next;
        cycle_reg <= cycle_next;
        if (tx_rd_irq_reg) begin
            tx_rd_irq_reg <= 'b0;
        end
        else if (tx_rd_irq_next) begin
            tx_rd_irq_reg <= 1'b1;
        end      
    end
end


endmodule //moduleName
 `resetall