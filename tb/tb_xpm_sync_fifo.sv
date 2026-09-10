/****************************************************************************
 * @file    tb_xpm_sync_fifo.v
 * @brief  
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2025-01-22
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    zzhi          | Support 100Gbps        |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2025 zzhi
 * ***************************************************************************/

`define CLOCK_PERIOD  100

 module tb_xpm_sync_fifo();

parameter WIDTH = 512 ;			//This is width
parameter DEPTH = 8 ;   		//This is depth
parameter FIFO_TYPE = "fwft" ;  //std or fwft


reg                  	clk  = 0;
reg                  	rst  = 1;
reg                  	wr_en= 0;
reg                  	rd_en= 0;
reg   [WIDTH-1:0] 		data = 0;
wire  [WIDTH-1:0] 		dout;
wire              		full;
wire              		empty;
wire					almost_full;


wire almost_empty;
xpm_sync_fifo #(
    .WIDTH         	(WIDTH   ),
    .DEPTH         	(DEPTH   ),
    .FIFO_TYPE     	(FIFO_TYPE),
    .FIFO_MEMORY   	("auto"  ),
    .USER_ADV_FEATURES("1f1f")
    )
u_xpm_sync_fifo(
    .clk           (clk          ),
    .rst        	(rst        ),
    .wr_en       	(wr_en        ),
    .rd_en       	(rd_en        ),
    .data        	(data         ),
    .dout          	(dout         ),
    .full        	(full         ),
    .empty       	(empty        ),
    .almost_empty   (almost_empty),
    .almost_full 	(almost_full  )
);

initial begin
    #(`CLOCK_PERIOD * 20) rst <= 0;
    #(`CLOCK_PERIOD * 20);
    while(~full) begin
        #(`CLOCK_PERIOD)begin
            @(posedge clk);
            wr_en <= 1;
            data <= data + 1'b1;
        end
    end
    #(`CLOCK_PERIOD)
    wr_en <= 0;
    #(`CLOCK_PERIOD * 20);
    while(~empty) begin
        #(`CLOCK_PERIOD )begin
        @(posedge clk);
            rd_en <= 1;
        end
        
    end
    #(`CLOCK_PERIOD)
    rd_en <= 0;
    #(`CLOCK_PERIOD * 20);
    $stop;
end

always #(`CLOCK_PERIOD / 2)  clk = ~clk;

endmodule