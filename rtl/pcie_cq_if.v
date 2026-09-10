/****************************************************************************
 * @file    pcie_cq_if.v
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

`timescale 1ns/1ps
/**************************************************************************************************************************************************
 *               Completer Request Descriptor Format
 *
 * 63                                                                   32 31                                                                   0                                                             
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+ 
 * |                               DW+1                                  | |                               DW+0                                  |
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |-------+7------| |-------+6------| |-------+5------| |-------+4------| |-------+3------| |-------+2------| |-------+1------| |-------+0------|                                                                                
 * |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0|                                              
 * |              												Address[63:2]																| AT |
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * 127                                                                   96 95                                                                   64
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |                                DW+3                                 | |                               DW+2                                  |
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+
 * |-------+15-----| |-------+14-----| |-------+13-----| |-------+12-----| |-------+11-----| |-------+10-----| |-------+9------| |-------+8------|
 * |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0| |7 6 5 4 3 2 1 0|    
 * |R|attr| |tc | bar aperture| |bar | |Target function| |     Tag       | |           Request id            | |R|Reqtype|     Dword Count       |    
 * +---------------------------------------------------------------------+ +---------------------------------------------------------------------+                                                   
 *************************************************************************************************************************************************/

module pcie_cq_if (

    input   wire    user_clk    ,
    input   wire    user_reset  ,

    input  wire [511 : 0] m_axis_cq_tdata   ,
    input  wire [15 : 0]  m_axis_cq_tkeep   ,
    input  wire           m_axis_cq_tlast   ,
    output reg            m_axis_cq_tready  ,
    input  wire [182 : 0] m_axis_cq_tuser   ,
    input  wire           m_axis_cq_tvalid  ,

    output reg  [31:0]    wrReq_data        ,
    output reg            wrReq_valid       ,
    output reg  [9:0]     wrReq_address     ,
    output reg  [10:0]    wrReq_dwLen       ,

    output reg            rdReq_valid       ,
    output reg  [9:0]     rdReq_address     ,
    output reg  [15:0]    rdReq_reqid       ,
    output reg  [7:0]     rdReq_tag         ,
    output reg  [10:0]    rdReq_dwLen       ,
    output reg  [2:0]     rdReq_TC          ,
    output reg  [1:0]     rdReq_addr_type   ,
    output reg  [2:0]     rdReq_attr        
);

/*************************************************************************
 *                 cq_interface
 *************************************************************************/
reg [1:0]   cq_fields_address_type  ;
reg [61:0]  cq_fields_address       ;
reg [10:0]  cq_fields_dword_count   ;
reg [3:0]   cq_fields_request_type  ;
reg [15:0]  cq_fields_requester_id  ;
reg [7:0]   cq_fields_tag           ;
reg [7:0]   cq_fields_function_id   ;
reg [2:0]   cq_fields_bar_id        ;
reg [5:0]   cq_fields_bar_aperture  ;
reg [2:0]   cq_fields_transaction_class;
reg [2:0]   cq_fields_attributes    ;
reg         cq_fields_reserved      ;

wire        cq_start_flag           ;
reg [1:0]   cq_start_flag_r         ;
reg [511:0] m_axis_cq_tdata_r       ;

/*************************************************************************/
//                 cq_interface
/*************************************************************************/
always @(posedge user_clk ) begin
	if (user_reset) begin
		m_axis_cq_tready <= 0;
	end
	else if (m_axis_cq_tready == 1 && m_axis_cq_tvalid == 1 && m_axis_cq_tlast == 1) begin
		m_axis_cq_tready <= 0;
	end
	else if (m_axis_cq_tready == 0 && m_axis_cq_tvalid == 1 && cq_start_flag_r == 2'b00) begin
		m_axis_cq_tready <= 1;
	end
end

assign cq_start_flag = m_axis_cq_tvalid & m_axis_cq_tready & m_axis_cq_tlast;



always @(posedge user_clk) begin
	if (user_reset) begin
		cq_start_flag_r <= 2'b00;
	end
	else begin
		cq_start_flag_r <= {cq_start_flag_r[0],cq_start_flag};
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		m_axis_cq_tdata_r <= 0;
	end
	else if (m_axis_cq_tvalid && m_axis_cq_tready && m_axis_cq_tlast) begin
		m_axis_cq_tdata_r <= m_axis_cq_tdata;
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_address_type <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_address_type <=m_axis_cq_tdata_r[1:0];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_address <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_address <=m_axis_cq_tdata_r[63:2];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_dword_count <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_dword_count <=m_axis_cq_tdata_r[74:64];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_request_type <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_request_type <=m_axis_cq_tdata_r[78:75];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_reserved <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_reserved <=m_axis_cq_tdata_r[79];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_requester_id <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_requester_id <=m_axis_cq_tdata_r[95:80];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_tag <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_tag <=m_axis_cq_tdata_r[103:96];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_function_id <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_function_id <=m_axis_cq_tdata_r[111:104];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_bar_id <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_bar_id <=m_axis_cq_tdata_r[114:112];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_bar_aperture <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_bar_aperture <=m_axis_cq_tdata_r[120:115];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_transaction_class <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_transaction_class <=m_axis_cq_tdata_r[123:121];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		cq_fields_attributes <= 0;
	end
	else if (cq_start_flag_r == 2'b01) begin
		cq_fields_attributes <=m_axis_cq_tdata_r[126:124];
	end
end



//wr
always @(posedge user_clk) begin
	if (user_reset) begin
		wrReq_valid <= 0;
	end
	else if (cq_start_flag_r == 2'b10 && cq_fields_request_type == 1) begin
		wrReq_valid <= 1;
	end
	else begin
		wrReq_valid <= 0;
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		wrReq_data <= 0;
	end
	else if (cq_start_flag_r == 2'b10  && cq_fields_request_type == 1) begin
		wrReq_data <= m_axis_cq_tdata_r[159:128];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		wrReq_address <= 0;
	end
	else if (cq_start_flag_r == 2'b10  && cq_fields_request_type == 1) begin
		wrReq_address <= cq_fields_address[9:0];
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		wrReq_dwLen <= 0;
	end
	else if (cq_start_flag_r == 2'b10  && cq_fields_request_type == 1) begin
		wrReq_dwLen <= cq_fields_dword_count;
	end
end

//rd
always @(posedge user_clk) begin
	if (user_reset) begin
		rdReq_valid <= 0;
	end
	else if (cq_start_flag_r == 2'b10  && cq_fields_request_type == 0) begin
		rdReq_valid <= 1;
	end
	else begin
		rdReq_valid <= 0;
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		rdReq_reqid <= 0;
	end
	else if (cq_start_flag_r == 2'b10  && cq_fields_request_type == 0) begin
		rdReq_reqid <= cq_fields_requester_id;
	end

end

always @(posedge user_clk) begin
	if (user_reset) begin
		rdReq_address <= 0;
	end
	else if (cq_start_flag_r == 2'b10  && cq_fields_request_type == 0) begin
		rdReq_address <= cq_fields_address[9:0];
	end

end

always @(posedge user_clk) begin
	if (user_reset) begin
		rdReq_tag <= 0;
	end
	else if (cq_start_flag_r == 2'b10  && cq_fields_request_type == 0) begin
		rdReq_tag <= cq_fields_tag;
	end

end

always @(posedge user_clk) begin
	if (user_reset) begin
		rdReq_dwLen <= 0;
	end
	else if (cq_start_flag_r == 2'b10  && cq_fields_request_type == 0) begin
		rdReq_dwLen <= cq_fields_dword_count;
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		rdReq_TC <= 0;
	end
	else if (cq_start_flag_r == 2'b10  && cq_fields_request_type == 0) begin
		rdReq_TC <= cq_fields_transaction_class;
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		rdReq_addr_type <= 0;
	end
	else if (cq_start_flag_r == 2'b10 && cq_fields_request_type == 0) begin
		rdReq_addr_type <= cq_fields_address_type;
	end
end

always @(posedge user_clk) begin
	if (user_reset) begin
		rdReq_attr <= 0;
	end
	else if (cq_start_flag_r == 2'b10 && cq_fields_request_type == 0) begin
		rdReq_attr <= cq_fields_attributes;
	end
end

endmodule
