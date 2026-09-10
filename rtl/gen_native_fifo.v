// /****************************************************************************
//  * @file    gen_native_fifo.v
//  * @brief  
//  * @author  weslie (zzhi4832@gmail.com)
//  * @version 1.0
//  * @date    2025-01-22
//  * 
//  * @par :
//  * ___________________________________________________________________________
//  * |    Date       |  Version    |       Author     |       Description      |
//  * |---------------|-------------|------------------|------------------------|
//  * |               |   v1.0      |    weslie        |  Support 100Gbps       |
//  * |---------------|-------------|------------------|------------------------|
//  * 
//  * @copyright Copyright (c) 2025 welie
//  * ***************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

/*
 * Generic FIFO
 *
 * Features:
 *  - Sync FIFO
 *  - Async FIFO
 *  - STD mode
 *  - FWFT mode
 *  - BRAM/URAM friendly
 *  - AXIS friendly
 *
 * FWFT implementation:
 *  - Internal FIFO always works in STD mode
 *  - Wrapper adds prefetch register
 */

module gen_native_fifo #(
    parameter FIFO_MODE = "sync",   // "sync" / "async"
    parameter FIFO_TYPE = "std",    // "std" / "fwft"
    parameter WIDTH     = 512,
    parameter DEPTH     = 10
)(
    input  wire                 clk,
    input  wire                 rd_clk,

    input  wire                 rst_n,

    input  wire                 wren,
    input  wire                 rden,

    input  wire [WIDTH-1:0]     data,

    output wire [WIDTH-1:0]     q,

    output wire                 full,
    output wire                 almost_full,
    output wire                 almost_empty,
    output wire                 empty
);

localparam FIFO_DEPTH = (1 << DEPTH);

wire [WIDTH-1:0] fifo_q;
wire fifo_empty;

wire fifo_wren;
wire fifo_rden;

/*
 * FWFT output control
 */

reg fwft_valid_reg = 0;

assign fifo_wren = wren;

/*
 * STD mode
 */

generate
if (FIFO_TYPE == "std") begin : std_mode

    assign fifo_rden = rden;

    assign q     = fifo_q;
    assign empty = fifo_empty;

end
else begin : fwft_mode

    /*
     * FWFT:
     *
     * When output register is empty
     * and FIFO has data,
     * automatically prefetch one word.
     *
     * Consumer:
     *   empty=0 => q valid
     */

    assign fifo_rden = !fifo_empty && (!fwft_valid_reg || rden);

    assign q     = fifo_q;
    assign empty = !fwft_valid_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            fwft_valid_reg <= 1'b0;
        end
        else begin
            if (fifo_rden) begin
                fwft_valid_reg <= 1'b1;
            end
            else if (rden && fwft_valid_reg) begin
                fwft_valid_reg <= 1'b0;
            end
        end
    end

end
endgenerate

/*
 * Internal FIFO
 *
 * Always STD FIFO
 */

generate

if (FIFO_MODE == "sync") begin : sync_fifo_inst

    logic_sync_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (DEPTH)
    )
    u_logic_sync_fifo (
        .clk         (clk),
        .rst         (~rst_n),

        .wren        (fifo_wren),
        .rden        (fifo_rden),

        .data        (data),
        .q           (fifo_q),

        .full        (full),
        .almost_full (almost_full),
        .almost_empty(almost_empty),
        .empty       (fifo_empty)
    );

end
else begin : async_fifo_inst

    logic_async_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (DEPTH)
    )
    u_logic_async_fifo (
        .wr_clk      (clk),
        .rd_clk      (rd_clk),

        .rst         (~rst_n),

        .wr_en       (fifo_wren),
        .rd_en       (fifo_rden),

        .wr_data     (data),
        .rd_data     (fifo_q),

        .full        (full),
        .empty       (fifo_empty)
    );

    assign almost_full = full;

end

endgenerate

endmodule


/*
 * ============================================================
 * Sync FIFO
 * ============================================================
 */

module logic_sync_fifo #(
    parameter WIDTH = 512,
    parameter DEPTH = 10
)(
    input  wire                 clk,
    input  wire                 rst,

    input  wire                 wren,
    input  wire                 rden,

    input  wire [WIDTH-1:0]     data,

    output wire [WIDTH-1:0]     q,

    output reg                  full,
    output reg                  almost_full,
    output reg                  almost_empty,
    output reg                  empty
);

localparam FIFO_DEPTH = (1 << DEPTH);

reg [DEPTH-1:0] wptr = 0;
reg [DEPTH-1:0] rptr = 0;

reg [DEPTH:0] count = 0;

wire wr_ack;
wire rd_ack;
wire [DEPTH:0] count_next;

assign wr_ack = wren && !full;
assign rd_ack = rden && !empty;
assign count_next = count + wr_ack - rd_ack;

/*
 * pointers
 */

always @(posedge clk) begin
    if (rst) begin
        wptr <= 0;
        rptr <= 0;
    end
    else begin

        if (wr_ack)
            wptr <= wptr + 1'b1;

        if (rd_ack)
            rptr <= rptr + 1'b1;
    end
end

/*
 * count
 */

always @(posedge clk) begin
    if (rst) begin
        count <= 0;
    end
    else begin
        count <= count_next;
    end
end

/*
 * flags
 */

always @(posedge clk) begin
    if (rst) begin
        full        <= 1'b0;
        almost_full <= 1'b0;
        almost_empty <= 1'b1;
        empty       <= 1'b1;
    end
    else begin
        full        <= (count_next == FIFO_DEPTH);
        almost_full <= (count_next >= FIFO_DEPTH-1);
        almost_empty <= (count_next <= 1);
        empty       <= (count_next == 0);
    end
end

/*
 * DPRAM
 */

logic_dpram #(
    .WIDTH (WIDTH),
    .DEPTH (DEPTH)
)
u_logic_dpram (
    .wrclk   (clk),
    .wren    (wr_ack),
    .wr_addr (wptr),
    .wr_data (data),

    .rdclk   (clk),
    .rden    (rd_ack),
    .rd_addr (rptr),
    .rd_data (q)
);

endmodule


/*
 * ============================================================
 * Async FIFO
 * ============================================================
 */

module logic_async_fifo #(
    parameter WIDTH = 512,
    parameter DEPTH = 10
)(
    input  wire                 wr_clk,
    input  wire                 rd_clk,

    input  wire                 rst,

    input  wire                 wr_en,
    input  wire                 rd_en,

    input  wire [WIDTH-1:0]     wr_data,

    output wire [WIDTH-1:0]     rd_data,

    output wire                 full,
    output wire                 empty
);

localparam PTR_W = DEPTH + 1;

reg [PTR_W-1:0] wr_ptr_bin = 0;
reg [PTR_W-1:0] rd_ptr_bin = 0;

wire [PTR_W-1:0] wr_ptr_gray;
wire [PTR_W-1:0] rd_ptr_gray;

wire wr_ack;
wire rd_ack;

assign wr_ack = wr_en && !full;
assign rd_ack = rd_en && !empty;

assign wr_ptr_gray = (wr_ptr_bin >> 1) ^ wr_ptr_bin;
assign rd_ptr_gray = (rd_ptr_bin >> 1) ^ rd_ptr_bin;

/*
 * sync gray pointers
 */

reg [PTR_W-1:0] rd_ptr_gray_sync1 = 0;
reg [PTR_W-1:0] rd_ptr_gray_sync2 = 0;

reg [PTR_W-1:0] wr_ptr_gray_sync1 = 0;
reg [PTR_W-1:0] wr_ptr_gray_sync2 = 0;

/*
 * write domain
 */

always @(posedge wr_clk) begin
    if (rst) begin
        wr_ptr_bin <= 0;

        rd_ptr_gray_sync1 <= 0;
        rd_ptr_gray_sync2 <= 0;
    end
    else begin

        rd_ptr_gray_sync1 <= rd_ptr_gray;
        rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;

        if (wr_ack)
            wr_ptr_bin <= wr_ptr_bin + 1'b1;
    end
end

/*
 * read domain
 */

always @(posedge rd_clk) begin
    if (rst) begin
        rd_ptr_bin <= 0;

        wr_ptr_gray_sync1 <= 0;
        wr_ptr_gray_sync2 <= 0;
    end
    else begin

        wr_ptr_gray_sync1 <= wr_ptr_gray;
        wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;

        if (rd_ack)
            rd_ptr_bin <= rd_ptr_bin + 1'b1;
    end
end

/*
 * full / empty
 */

assign empty =
    (rd_ptr_gray == wr_ptr_gray_sync2);

assign full =
    (
        ((wr_ptr_bin + 1'b1) >> 1 ^
         (wr_ptr_bin + 1'b1))
        ==
        {
            ~rd_ptr_gray_sync2[PTR_W-1:PTR_W-2],
             rd_ptr_gray_sync2[PTR_W-3:0]
        }
    );

/*
 * RAM
 */

logic_dpram #(
    .WIDTH (WIDTH),
    .DEPTH (DEPTH)
)
u_logic_dpram (
    .wrclk   (wr_clk),
    .wren    (wr_ack),
    .wr_addr (wr_ptr_bin[DEPTH-1:0]),
    .wr_data (wr_data),

    .rdclk   (rd_clk),
    .rden    (rd_ack),
    .rd_addr (rd_ptr_bin[DEPTH-1:0]),
    .rd_data (rd_data)
);

endmodule


/*
 * ============================================================
 * DPRAM
 * ============================================================
 */

module logic_dpram #(
    parameter WIDTH = 64,
    parameter DEPTH = 10
)(
    input  wire                 wrclk,
    input  wire                 wren,
    input  wire [DEPTH-1:0]     wr_addr,
    input  wire [WIDTH-1:0]     wr_data,

    input  wire                 rdclk,
    input  wire                 rden,
    input  wire [DEPTH-1:0]     rd_addr,

    output reg  [WIDTH-1:0]     rd_data
);

(* ram_style = "block" *)
reg [WIDTH-1:0] ram_mem [0:(1<<DEPTH)-1];

/*
 * write
 */

always @(posedge wrclk) begin
    if (wren)
        ram_mem[wr_addr] <= wr_data;
end

/*
 * synchronous read
 */

always @(posedge rdclk) begin
    if (rden)
        rd_data <= ram_mem[rd_addr];
end

endmodule

`default_nettype wire
