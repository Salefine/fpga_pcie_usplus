/****************************************************************************
 * @file    pcie_cc_if.v
 * @brief  
 * @author  weslie (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2026-03-18
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    weslie        |                        |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2026 welie
 * ***************************************************************************/

/**************************************************************************************************************************************************
 *               Completer Completion Descriptor Format
 *
 * 63                                                                   32 31                                                                   0                                                             
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+ 
 * |                               DW+1                                  | |                               DW+0                                  |
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |-------+7------| |-------+6------| |-------+5------| |-------+4------| |-------+3------| |-------+2------| |-------+1------| |-------+0------|                                                                                
 * |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0|                                              
 * |              Reuqest ID         | |R        |     Dword Count       | |R    |     Byte Count            | |    R      |AT | |R Address[6:0] |
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 *                                                                        95                                                                     64
 *                                                                         +---------------------------------------------------------------------+
 *                                                                         |                               DW+2                                  |
 *                                                                         +---------------------------------------------------------------------+
 *                                                                         |-------+11-----| |-------+10-----| |-------+9------| |-------+8------|
 *                                                                         |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0|    
 *                                                                         |F| Attr| TC |  | |           Completer ID          | |     Tag       |    
 *                                                                         +---------------------------------------------------------------------+                                                   
 *************************************************************************************************************************************************/

`timescale 1ns/1ps

module pcie_cc_if (

    input   wire            user_clk      ,
    input   wire            user_reset    ,

    input   wire    [6:0]   rdCpld_lowaddr   ,
    input   wire    [1:0]   rdCpld_addr_type ,
    input   wire    [12:0]  rdCpld_bytecnt   ,
    input   wire    [10:0]  rdCpld_dwLen     ,
    input   wire    [15:0]  rdCpld_reqid     ,
    input   wire    [7:0]   rdCpld_tag       ,
    input   wire    [15:0]  rdCpld_cplid     ,
    input   wire    [31:0]  rdCpld_data      ,
    input   wire    [2:0]   rdCpld_TC        ,
    input   wire    [2:0]   rdCpld_attr      ,
    input   wire    [2:0]   rdCpld_status    ,
    input   wire            rdCpld_valid     ,

    output reg  [511 : 0] s_axis_cc_tdata   ,
    output reg  [15 : 0]  s_axis_cc_tkeep   ,
    output reg            s_axis_cc_tlast   ,
    input  wire 		  s_axis_cc_tready  ,
    output reg  [80 : 0]  s_axis_cc_tuser   ,
    output reg            s_axis_cc_tvalid  
);

wire 	[1:0] 	cc_is_sop;
wire 	[1:0] 	cc_is_eop;
wire 	[3:0] 	cc_is_eop0_ptr;
assign cc_is_sop		=	2'd1;
assign cc_is_eop		=	2'd1;
assign cc_is_eop0_ptr	=	4'd3;


always @(posedge user_clk) begin
    if (user_reset) begin
        s_axis_cc_tdata <= 0;
    end
    else if (rdCpld_valid) begin
        s_axis_cc_tdata <= {
            384'd0                                                                                                      ,
            rdCpld_data                                                                                                 ,
            1'b0, rdCpld_attr, rdCpld_TC ,1'b0 , rdCpld_cplid[15:8], 8'd0  , rdCpld_tag                                 ,
            rdCpld_reqid , 5'b0 , rdCpld_dwLen , 3'b0 , rdCpld_bytecnt , 6'd0 , rdCpld_addr_type , 1'b0 , rdCpld_lowaddr
        };
    end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		s_axis_cc_tuser <= 0;
	end
	else if (s_axis_cc_tvalid == 1 && s_axis_cc_tready == 1) begin
		s_axis_cc_tuser <= 0;
	end
	else if (rdCpld_valid == 1) begin
		s_axis_cc_tuser <= { 69'd0,cc_is_eop0_ptr,cc_is_eop,4'd0,cc_is_sop};
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		s_axis_cc_tlast <= 0;
	end
	else if (s_axis_cc_tvalid == 1 && s_axis_cc_tready == 1) begin
		s_axis_cc_tlast <= 0;
	end
	else if (rdCpld_valid == 1) begin
		s_axis_cc_tlast <= 1;
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		s_axis_cc_tkeep <= 16'hffff;
	end
	else if (s_axis_cc_tvalid == 1 && s_axis_cc_tready == 1) begin
		s_axis_cc_tkeep <= 16'hffff;
	end
	else if (rdCpld_valid == 1) begin
		s_axis_cc_tkeep <= 16'h000f;
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		s_axis_cc_tvalid <= 0;
	end
	else if (s_axis_cc_tvalid == 1 && s_axis_cc_tready == 1) begin
		s_axis_cc_tvalid <= 0;
	end
	else if (rdCpld_valid == 1) begin
		s_axis_cc_tvalid <= 1;
	end
end

endmodule