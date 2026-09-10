`timescale 1ns / 1ps

module tb_gen_native_fifo;

parameter WIDTH = 32;
parameter DEPTH = 4;

reg clk = 0;
reg rd_clk = 0;
reg rst_n = 0;

reg wren = 0;
reg rden = 0;

reg  [WIDTH-1:0] data = 0;

wire [WIDTH-1:0] q;

wire full;
wire almost_full;
wire empty;
integer i;
integer j;
/*
 * DUT
 */

gen_native_fifo #(
    .FIFO_MODE ("sync"),
    .FIFO_TYPE ("std"), // "std" / "fwft"
    .WIDTH     (WIDTH),
    .DEPTH     (DEPTH)
)
dut (
    .clk          (clk),
    .rd_clk       (rd_clk),

    .rst_n        (rst_n),

    .wren         (wren),
    .rden         (rden),

    .data         (data),

    .q            (q),

    .full         (full),
    .almost_full  (almost_full),
    .empty        (empty)
);

/*
 * clock
 */

always #5 clk = ~clk;

always #5 rd_clk = ~rd_clk;

/*
 * write task
 */

task fifo_write;
    input [WIDTH-1:0] din;
begin

    @(posedge clk);

    while (full) begin
        @(posedge clk);
    end

    wren <= 1'b1;
    data <= din;

    @(posedge clk);

    wren <= 1'b0;
    data <= 0;

    $display("[%0t] WRITE : %h", $time, din);

end
endtask

/*
 * read task
 */

task fifo_read;
begin

    @(posedge clk);

    while (empty) begin
        @(posedge clk);
    end

    rden <= 1'b1;

    @(posedge clk);

    rden <= 1'b0;

    $display("[%0t] READ  : %h", $time, q);

end
endtask

/*
 * monitor
 */

always @(posedge clk) begin
    $display(
        "[%0t] full=%0d almost_full=%0d empty=%0d wren=%0d rden=%0d data=%h q=%h",
        $time,
        full,
        almost_full,
        empty,
        wren,
        rden,
        data,
        q
    );
end

/*
 * main test
 */

initial begin

    $display("=================================================");
    $display("FIFO TEST START");
    $display("=================================================");

    /*
     * reset
     */

    rst_n = 0;

    wren = 0;
    rden = 0;
    data = 0;

    repeat(10) @(posedge clk);

    rst_n = 1;

    repeat(5) @(posedge clk);

    /*
     * basic write
     */

    fifo_write(32'h11111111);
    fifo_write(32'h22222222);
    fifo_write(32'h33333333);
    fifo_write(32'h44444444);

    repeat(5) @(posedge clk);

    /*
     * basic read
     */

    fifo_read();
    fifo_read();
    fifo_read();
    fifo_read();

    repeat(5) @(posedge clk);

    /*
     * continuous write
     */

    $display("=================================================");
    $display("CONTINUOUS WRITE");
    $display("=================================================");

    repeat(8) begin
        fifo_write($random);
    end

    repeat(5) @(posedge clk);

    /*
     * continuous read
     */

    $display("=================================================");
    $display("CONTINUOUS READ");
    $display("=================================================");

    repeat(8) begin
        fifo_read();
    end

    repeat(5) @(posedge clk);

    /*
     * simultaneous read/write
     */

    $display("=================================================");
    $display("SIMULTANEOUS RD/WR");
    $display("=================================================");

    fork

        begin
            

            for (i = 0; i < 16; i = i + 1) begin
                fifo_write(i);
            end
        end

        begin
            

            repeat(5) @(posedge clk);

            for (j = 0; j < 16; j = j + 1) begin
                fifo_read();
            end
        end

    join

    repeat(10) @(posedge clk);

    /*
     * FWFT behavior
     */

    $display("=================================================");
    $display("FWFT CHECK");
    $display("=================================================");

    fifo_write(32'hdeadbeef);

    @(posedge clk);

    $display(
        "[%0t] FWFT CHECK: empty=%0d q=%h",
        $time,
        empty,
        q
    );

    /*
     * read after fwft
     */

    fifo_read();

    repeat(10) @(posedge clk);

    $display("=================================================");
    $display("FIFO TEST PASS");
    $display("=================================================");

    $finish;

end

/*
 * waveform
 */

initial begin

    $dumpfile("tb_gen_native_fifo.vcd");
    $dumpvars(0, tb_gen_native_fifo);

end

endmodule