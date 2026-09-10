/****************************************************************************
 * @file    tb_pcie_core.v
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

`define     CLOCK_PERIOD 4 
`define     REQ_MRD;
`define     REQ_MWR
module tb_fpga_core();

// Width of PCIe AXI stream interfaces in bits
parameter AXIS_PCIE_DATA_WIDTH = 512;
// PCIe AXI stream tkeep signal width (words per cycle)
parameter AXIS_PCIE_KEEP_WIDTH = (AXIS_PCIE_DATA_WIDTH/32);
parameter AXIS_PCIE_RC_USER_WIDTH   = AXIS_PCIE_DATA_WIDTH < 512 ? 75 : 161;
parameter AXIS_PCIE_RQ_USER_WIDTH   = AXIS_PCIE_DATA_WIDTH < 512 ? 60 : 137;
parameter AXIS_PCIE_CQ_USER_WIDTH   = AXIS_PCIE_DATA_WIDTH < 512 ? 85 : 183;
parameter AXIS_PCIE_CC_USER_WIDTH   = AXIS_PCIE_DATA_WIDTH < 512 ? 33 : 81;
// RQ interface TLP straddling
parameter RQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512;
// RQ sequence number width
parameter RQ_SEQ_NUM_WIDTH = AXIS_PCIE_RQ_USER_WIDTH == 60 ? 4 : 6;
// TLP data width
parameter TLP_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH;
// TLP strobe width
parameter TLP_STRB_WIDTH = TLP_DATA_WIDTH/32;
// TLP header width
parameter TLP_HDR_WIDTH = 128;
// TLP segment count
parameter TLP_SEG_COUNT = 1;
// TX sequence number count
parameter TX_SEQ_NUM_COUNT = AXIS_PCIE_DATA_WIDTH < 512 ? 1 : 2;
// TX sequence number width
parameter TX_SEQ_NUM_WIDTH = RQ_SEQ_NUM_WIDTH-1;

parameter MSI_COUNT     = 1;
parameter USER_MSI_IRQ  = 1;

parameter SDRAM_DEEPTH = 10;
parameter C_M_AXI_ADDR_WIDTH = 32;
parameter C_M_AXI_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH;

parameter AXIL_CTRL_ADDR_WIDTH = 32;

reg     clk=0;
reg     rst=1;


wire [AXIS_PCIE_DATA_WIDTH-1:0]    m_axis_rq_tdata      ;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    m_axis_rq_tkeep      ;
wire                               m_axis_rq_tlast      ;
reg                                m_axis_rq_tready = 1 ;
wire [AXIS_PCIE_RQ_USER_WIDTH-1:0] m_axis_rq_tuser      ;
wire                               m_axis_rq_tvalid     ;

reg [AXIS_PCIE_DATA_WIDTH-1:0]    s_axis_rc_tdata = 0;
reg [AXIS_PCIE_KEEP_WIDTH-1:0]    s_axis_rc_tkeep = 0;
reg                               s_axis_rc_tlast = 0;
wire                              s_axis_rc_tready;
reg [AXIS_PCIE_RC_USER_WIDTH-1:0] s_axis_rc_tuser  = 0;
reg                               s_axis_rc_tvalid = 0;

reg [AXIS_PCIE_DATA_WIDTH-1:0]    s_axis_cq_tdata = 0;
reg [AXIS_PCIE_KEEP_WIDTH-1:0]    s_axis_cq_tkeep = 0;
reg                               s_axis_cq_tlast = 0;
wire                               s_axis_cq_tready ;
reg [AXIS_PCIE_CQ_USER_WIDTH-1:0] s_axis_cq_tuser  =0;
reg                               s_axis_cq_tvalid =0;

wire [AXIS_PCIE_DATA_WIDTH-1:0]    m_axis_cc_tdata ;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    m_axis_cc_tkeep ;
wire                               m_axis_cc_tlast ;
reg                                m_axis_cc_tready = 1;
wire [AXIS_PCIE_CC_USER_WIDTH-1:0] m_axis_cc_tuser ;
wire                               m_axis_cc_tvalid;

reg [2:0]                         cfg_max_payload = 3'b010;
reg [2:0]                         cfg_max_read_req= 3'b010;
reg [3:0]                         cfg_rcb_status  = 1;
reg [7:0]  tx_fc_ph_av  = 8'hFF;
reg [11:0] tx_fc_pd_av  = 12'hFFF;
reg [7:0]  tx_fc_nph_av = 8'hFF;
reg [11:0] tx_fc_npd_av = 12'hFFF;

reg [7:0]                                    cfg_fc_ph = 8'h7f;
reg [11:0]                                   cfg_fc_pd = 12'h800;
reg [7:0]                                    cfg_fc_nph = 8'h7f;
reg [11:0]                                   cfg_fc_npd= 12'h800;
reg [7:0]                                    cfg_fc_cplh= 8'h7f;
reg [11:0]                                   cfg_fc_cpld=12'h800;

reg [RQ_SEQ_NUM_WIDTH-1:0]                   s_axis_rq_seq_num_0  = 0;
reg                                          s_axis_rq_seq_num_valid_0 = 0;
reg [RQ_SEQ_NUM_WIDTH-1:0]                   s_axis_rq_seq_num_1 = 0;
reg                                          s_axis_rq_seq_num_valid_1 = 0;

reg [3:0]                         cfg_interrupt_msi_enable = 1;
reg [7:0]                         cfg_interrupt_msi_vf_enable = 0;
reg [11:0]                        cfg_interrupt_msi_mmenable = 12'h0;
reg                               cfg_interrupt_msi_mask_update = 0;
reg [31:0]                        cfg_interrupt_msi_data = 0;
wire [3:0]                        cfg_interrupt_msi_select = 0;
wire [31:0]                       cfg_interrupt_msi_int;
wire [31:0]                       cfg_interrupt_msi_pending_status;
wire                              cfg_interrupt_msi_pending_status_data_enable;
wire [3:0]                        cfg_interrupt_msi_pending_status_function_num;
wire [7:0]                        cfg_interrupt_msi_function_number;
wire [2:0]                        cfg_interrupt_msi_attr;
wire                              cfg_interrupt_msi_tph_present;
wire [1:0]                        cfg_interrupt_msi_tph_type;
wire [8:0]                        cfg_interrupt_msi_tph_st_tag;
reg                               cfg_interrupt_msi_sent = 0;
reg                               cfg_interrupt_msi_fail = 0;

wire [9:0]                        cfg_mgmt_addr;
wire [7:0]                        cfg_mgmt_function_number;
wire                              cfg_mgmt_write;
wire [31:0]                       cfg_mgmt_write_data;
wire [3:0]                        cfg_mgmt_byte_enable;
wire                              cfg_mgmt_read;
reg [31:0]                        cfg_mgmt_read_data = 0;
reg                               cfg_mgmt_read_write_done = 0;
wire [2:0]                        cfg_fc_sel;

reg [29:0] msi_irq = 0;


wire                             M_AXI_ARID      ;
wire [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI_ARADDR    ;
wire [7 : 0]                     M_AXI_ARLEN     ;
wire [2 : 0]                     M_AXI_ARSIZE    ;
wire [1 : 0]                     M_AXI_ARBURST   ;
wire                             M_AXI_ARLOCK    ;
wire [3 : 0]                     M_AXI_ARCACHE   ;
wire [2 : 0]                     M_AXI_ARPROT    ;
// wire [3 : 0]                     M_AXI_ARQOS     ;
wire                             M_AXI_ARVALID   ;
reg                              M_AXI_ARREADY   = 1;

reg                              M_AXI_RID       = 0;
reg [C_M_AXI_DATA_WIDTH-1 : 0]   M_AXI_RDATA     = 0;
reg [1 : 0]                      M_AXI_RRESP     = 0;
reg                              M_AXI_RLAST     = 0;
reg                              M_AXI_RVALID    = 0;
wire                             M_AXI_RREADY    ;

wire [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI_AWADDR ;
wire           M_AXI_AWID   ;
wire [7 : 0]   M_AXI_AWLEN  ;
wire [2 : 0]   M_AXI_AWSIZE ;
wire [1 : 0]   M_AXI_AWBURST;
wire           M_AXI_AWLOCK ;
wire [3 : 0]   M_AXI_AWCACHE;
wire [2 : 0]   M_AXI_AWPROT ;
// wire [3 : 0]   M_AXI_AWQOS  ;
wire           M_AXI_AWVALID;
reg            M_AXI_AWREADY = 1;

wire [C_M_AXI_DATA_WIDTH-1 : 0]  M_AXI_WDATA;
wire [C_M_AXI_DATA_WIDTH/8-1 : 0]M_AXI_WSTRB;
wire                             M_AXI_WLAST;
wire                             M_AXI_WVALID;
reg                              M_AXI_WREADY = 1;

reg            M_AXI_BID = 0;
reg [1 : 0]    M_AXI_BRESP = 0;
reg            M_AXI_BVALID = 0;
wire           M_AXI_BREADY;

// wire     M_AXI_WUSER;
// reg      M_AXI_BUSER = 0;
// wire     M_AXI_AWUSER ;
// reg      M_AXI_RUSER     = 0;
// wire     M_AXI_ARUSER    ;

wire [C_M_AXI_DATA_WIDTH - 1 : 0]   S_AXIS_DMA_TDATA ;
wire [C_M_AXI_DATA_WIDTH/8- 1 : 0]  S_AXIS_DMA_TKEEP ;
wire                                S_AXIS_DMA_TVALID;     
wire                                S_AXIS_DMA_TLAST ;
wire                                S_AXIS_DMA_TREADY;               
wire [C_M_AXI_DATA_WIDTH - 1 : 0]   M_AXIS_DMA_TDATA ;
wire [C_M_AXI_DATA_WIDTH/8- 1 : 0]  M_AXIS_DMA_TKEEP ;
wire                                M_AXIS_DMA_TVALID;     
wire                                M_AXIS_DMA_TLAST ;
wire                                M_AXIS_DMA_TREADY;    

reg [31:0] st_length = 0;
reg st_start  = 0;

integer  fd;

initial begin
    fd = $fopen("tx_wr_req_tlp.txt", "w");
    if (fd == 0) begin
        $display("open file failed");
        $finish;
    end
end

// always @(posedge clk)begin
//     if (tb_fpga_core.tb_fpga_core.dma_if_axis.dma_if_axis.dma_if_wr.tx_wr_req_tlp_valid  && tb_fpga_core.tb_fpga_core.dma_if_axis.dma_if_axis.dma_if_wr.tx_wr_req_tlp_ready) begin
//         $fwrite(fd, "%08x\n", tb_fpga_core.tb_fpga_core.dma_if_axis.dma_if_axis.dma_if_wr.tx_wr_req_tlp_data);
//     end
// end

`ifdef REQ_MWR

initial begin
    #(`CLOCK_PERIOD * 1000);
    rst <= 0;

    /*
     * 1. Vertify host to pcie's bar space ead and write
     */
    #(`CLOCK_PERIOD * 100); //0x0 block dma low address 
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fcf00000105800000000080100000000fcf00000;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0;    
    #(`CLOCK_PERIOD * 2); //0x4 block dma high address 
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000105800000000080100000000fcf00004;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0; 

    #(`CLOCK_PERIOD * 2); //0xc dma length, 4MB
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040_0000_105800000000080100000000fcf0000c;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;

    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0; 

    #(`CLOCK_PERIOD * 2); // fpga sdram's low address
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000105800000000080100000000fcf0002c;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0;

    #(`CLOCK_PERIOD * 2); //fpga sdram's high address
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000105800000000080100000000fcf00028;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0;

    #(`CLOCK_PERIOD * 2); //0x8 dma start 
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001105800000000080100000000fcf00008;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    st_length <= 32'h400000;
    st_start  <= 1;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0;   
    st_length <= 32'h0;
    st_start  <= 0;
    #(`CLOCK_PERIOD * 80);
    //wait(tb_fpga_core.dma_if_axis.dma_if_axis.dma_if_wr.tx_wr_req_tlp_sop)
    wait(tb_fpga_core.dma_if_axi_full.dma_if_axi.dma_if_axi_wr.pcie_axis_wr.tx_wr_req_tlp_sop)
    @(posedge clk);
    m_axis_rq_tready <= 0;
    #(`CLOCK_PERIOD * 800);
    @(posedge clk);
    m_axis_rq_tready <= 1;
    repeat(600)begin
//        wait(tb_fpga_core.dma_if_axis.dma_if_axis.dma_if_wr.tx_wr_req_tlp_sop)
        @(posedge clk);
        m_axis_rq_tready <= 0;
        #(`CLOCK_PERIOD * 2);
        @(posedge clk);
        m_axis_rq_tready <= 1;
//        #(`CLOCK_PERIOD * 1);
    end
    wait(cfg_interrupt_msi_int[0])
    cfg_interrupt_msi_sent <= 1; 
    #(`CLOCK_PERIOD );
    cfg_interrupt_msi_sent <= 0; 
    #(`CLOCK_PERIOD * 800);

    /*
     * 2. device to host , mwr , address = 0x00000000, length = 0x6dc = 1756
     */
    #(`CLOCK_PERIOD * 2); //0xc dma length, 0xffff
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000_0000_8000_105800000000080100000000fcf0000c;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0; 
    #(`CLOCK_PERIOD * 2); //0x8 dma start 
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001105800000000080100000000fcf00008;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    st_length <= 32'h8000;
    st_start  <= 1;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0; 
    st_length <= 32'h0;
    st_start  <= 0;   
     repeat(16)begin
//        wait(tb_fpga_core.dma_if_axis.dma_if_axis.dma_if_wr.tx_wr_req_tlp_sop)
        @(posedge clk);
        m_axis_rq_tready <= 0;
        #(`CLOCK_PERIOD * 2);
        @(posedge clk);
        m_axis_rq_tready <= 1;
//        #(`CLOCK_PERIOD * 1);
    end   
    wait(cfg_interrupt_msi_int[0]);
    $display("cfg_interrupt_msi_int is %x", cfg_interrupt_msi_int);
    cfg_interrupt_msi_sent <= 1; 
    #(`CLOCK_PERIOD );
    cfg_interrupt_msi_sent <= 0; 
    #(`CLOCK_PERIOD * 800);
    /*
     * 3. device to host , mwr , address = 0x00000000, length = 1751
     */
    #(`CLOCK_PERIOD * 2); 
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000_0000_06d7_105800000000080100000000fcf0000c;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0; 
    #(`CLOCK_PERIOD * 2); //0x8 dma start 
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001105800000000080100000000fcf00008;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    st_length <= 32'h06d7;
    st_start  <= 1;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0; 
    st_length <= 32'h0;
    st_start  <= 0;
    wait(cfg_interrupt_msi_int[0])
    cfg_interrupt_msi_sent <= 1; 
    #(`CLOCK_PERIOD );
    cfg_interrupt_msi_sent <= 0; 
    #(`CLOCK_PERIOD * 800);

    /*
     * 3. device to host , mwr , address = 0x00000000, length = 1
     */
    #(`CLOCK_PERIOD * 2); 
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000_0000_0001_105800000000080100000000fcf0000c;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0; 
    #(`CLOCK_PERIOD * 2); //0x8 dma start 
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001105800000000080100000000fcf00008;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    st_length <= 32'h01;
    st_start  <= 1;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0; 
    st_length <= 32'h00;
    st_start  <= 0;
    wait(cfg_interrupt_msi_int[0])
    cfg_interrupt_msi_sent <= 1; 
    #(`CLOCK_PERIOD );
    cfg_interrupt_msi_sent <= 0; 
    #(`CLOCK_PERIOD * 800);
`endif

`ifdef REQ_MRD
    /*
     *3. vertify mrd
     */
    #(`CLOCK_PERIOD * 100); //0x4 block dma low address 
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fcf00000105800000000080100000000fcf10010;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h0000000000000000000000044100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0;    
    #(`CLOCK_PERIOD * 2); //0x5 block dma high address 
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000105800000000080100000000fcf10014;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h0000000000000000000000044100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0; 

    #(`CLOCK_PERIOD * 2); //0xc dma length, 4KB
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000_1000_105800000000080100000000fcf1001c;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h0000000000000000000000044100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0; 

    #(`CLOCK_PERIOD * 2); // fpga sdram's low address
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000105800000000080100000000fcf10030;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h0000000000000000000000044100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0;

    #(`CLOCK_PERIOD * 2); //fpga sdram's high address
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000105800000000080100000000fcf10034;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0;

    #(`CLOCK_PERIOD * 2); //0x8 dma start 
    @(posedge clk);
    s_axis_cq_tvalid <= 1;
    s_axis_cq_tdata <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001105800000000080100000000fcf10018;
    s_axis_cq_tkeep <= 16'hffff;
    s_axis_cq_tlast <= 1;
    s_axis_cq_tuser <= 183'h44100000000000f0000000f;
    wait(s_axis_cq_tvalid & s_axis_cq_tready);
    @(posedge clk);
    s_axis_cq_tvalid <= 0;
    s_axis_cq_tdata <= 0;
    s_axis_cq_tkeep <= 0;
    s_axis_cq_tlast <= 0;
    s_axis_cq_tuser <= 0;    
    #(`CLOCK_PERIOD * 2);

    #(`CLOCK_PERIOD * 200);

    @(posedge clk);
    s_axis_rc_tvalid <= 1;
    s_axis_rc_tdata  <= 512'h0000000d0000000c0000000b0000000a000000090000000800000007000000060000000500000004000000030000000200000001000009000100002002000000;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;
    s_axis_rc_tkeep  <= 16'hffff;
    s_axis_rc_tlast  <= 0;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000001d0000001c0000001b0000001a000000190000001800000017000000160000001500000014000000130000001200000011000000100000000f0000000e;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h00000000000000000000000000000000000000000000000000000000000000000000002100000001800109002000004a00000000000000200000001f0000001e;
    s_axis_rc_tuser  <= 161'h00000000000000000000210000000000000000fff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000002d0000002c0000002b0000002a000000290000002800000027000000260000002500000024000000230000002200000021000009000100002001800080;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000003d0000003c0000003b0000003a000000390000003800000037000000360000003500000034000000330000003200000031000000300000002f0000002e;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff; 

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);

    s_axis_rc_tdata  <= 512'h00000049000000480000004700000046000000450000004400000043000000420000004100000900010000200100010000000000000000400000003f0000003e;
    s_axis_rc_tuser  <= 161'h0000000000000000000021011fffffffff0000fff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000590000005800000057000000560000005500000054000000530000005200000051000000500000004f0000004e0000004d0000004c0000004b0000004a;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000650000006400000063000000620000006100000900010000204080018000000000000000600000005f0000005e0000005d0000005c0000005b0000005a;
    s_axis_rc_tuser  <= 161'h0000000000000000000061021fffff0000fffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000007500000074000000730000007200000071000000700000006f0000006e0000006d0000006c0000006b0000006a00000069000000680000006700000066;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;   

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000008100000901010000200200020000000000000000800000007f0000007e0000007d0000007c0000007b0000007a00000079000000780000007700000076;
    s_axis_rc_tuser  <= 161'h00000000000000000000a1031f0000fffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h00000091000000900000008f0000008e0000008d0000008c0000008b0000008a0000008900000088000000870000008600000085000000840000008300000082;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;    

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h00000000000000a00000009f0000009e0000009d0000009c0000009b0000009a0000009900000098000000970000009600000095000000940000009300000092;
    s_axis_rc_tuser  <= 161'h00000000000000000000e10000fffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000ad000000ac000000ab000000aa000000a9000000a8000000a7000000a6000000a5000000a4000000a3000000a2000000a1000009010100002001800280;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000bd000000bc000000bb000000ba000000b9000000b8000000b7000000b6000000b5000000b4000000b3000000b2000000b1000000b0000000af000000ae;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000c5000000c4000000c3000000c2000000c10000090101000020010003000000008900000088000000870000008600000000000000c0000000bf000000be;
    s_axis_rc_tuser  <= 161'h0000000000000000000021021fffff00000000fff;   
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000d5000000d4000000d3000000d2000000d1000000d0000000cf000000ce000000cd000000cc000000cb000000ca000000c9000000c8000000c7000000c6;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000e100000901010000204080038000000000000000e0000000df000000de000000dd000000dc000000db000000da000000d9000000d8000000d7000000d6;
    s_axis_rc_tuser  <= 161'h00000000000000000000a1031f0000fffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000f1000000f0000000ef000000ee000000ed000000ec000000eb000000ea000000e9000000e8000000e7000000e6000000e5000000e4000000e3000000e2;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000000000000100000000ff000000fe000000fd000000fc000000fb000000fa000000f9000000f8000000f7000000f6000000f5000000f4000000f3000000f2;
    s_axis_rc_tuser  <= 161'h00000000000000000000e10000fffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000010d0000010c0000010b0000010a000001090000010800000107000001060000010500000104000001030000010200000101000009020100002002000400;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;   
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000011d0000011c0000011b0000011a000001190000011800000117000001160000011500000114000001130000011200000111000001100000010f0000010e;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h00000125000001240000012300000122000001210000090201000020018004800000012100020001800109002000004a00000000000001200000011f0000011e;
    s_axis_rc_tuser  <= 161'h0000000000000000000021021fffff00000000fff;   

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000013500000134000001330000013200000131000001300000012f0000012e0000012d0000012c0000012b0000012a00000129000001280000012700000126;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000014100000902010000200100050000000000000001400000013f0000013e0000013d0000013c0000013b0000013a00000139000001380000013700000136;
    s_axis_rc_tuser  <= 161'h00000000000000000000a1031f0000fffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h00000151000001500000014f0000014e0000014d0000014c0000014b0000014a0000014900000148000001470000014600000145000001440000014300000142;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h00000000000001600000015f0000015e0000015d0000015c0000015b0000015a0000015900000158000001570000015600000155000001540000015300000152;
    s_axis_rc_tuser  <= 161'h00000000000000000000e10000fffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000016d0000016c0000016b0000016a000001690000016800000167000001660000016500000164000001630000016200000161000009020100002040800580;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;   

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000017d0000017c0000017b0000017a000001790000017800000177000001760000017500000174000001730000017200000171000001700000016f0000016e;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h00000185000001840000018300000182000001810000090301000020020006000000014900000148000001470000014600000000000001800000017f0000017e;
    s_axis_rc_tuser  <= 161'h0000000000000000000021021fffff00000000fff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000019500000194000001930000019200000191000001900000018f0000018e0000018d0000018c0000018b0000018a00000189000001880000018700000186;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;   
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000001a100000903010000200180068000000000000001a00000019f0000019e0000019d0000019c0000019b0000019a00000199000001980000019700000196;
    s_axis_rc_tuser  <= 161'h00000000000000000000a1031f0000fffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000001b1000001b0000001af000001ae000001ad000001ac000001ab000001aa000001a9000001a8000001a7000001a6000001a5000001a4000001a3000001a2;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h00000000000001c0000001bf000001be000001bd000001bc000001bb000001ba000001b9000001b8000001b7000001b6000001b5000001b4000001b3000001b2;
    s_axis_rc_tuser  <= 161'h00000000000000000000e10000fffffffffffffff; 

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000001cd000001cc000001cb000001ca000001c9000001c8000001c7000001c6000001c5000001c4000001c3000001c2000001c1000009030100002001000700;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000001dd000001dc000001db000001da000001d9000001d8000001d7000001d6000001d5000001d4000001d3000001d2000001d1000001d0000001cf000001ce;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000000000000000000000000000000000000000000000000000000000000000000001e100030001800009002000004a00000000000001e0000001df000001de;
    s_axis_rc_tuser  <= 161'h00000000000000000000210000000000000000fff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000001ed000001ec000001eb000001ea000001e9000001e8000001e7000001e6000001e5000001e4000001e3000001e2000001e1000009030100002040800780;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;   
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000001fd000001fc000001fb000001fa000001f9000001f8000001f7000001f6000001f5000001f4000001f3000001f2000001f1000001f0000001ef000001ee;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000020900000208000002070000020600000205000002040000020300000202000002010000090401000020020008000000000000000200000001ff000001fe;
    s_axis_rc_tuser  <= 161'h0000000000000000000021011fffffffff0000fff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000002190000021800000217000002160000021500000214000002130000021200000211000002100000020f0000020e0000020d0000020c0000020b0000020a;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000002250000022400000223000002220000022100000904010000200180088000000000000002200000021f0000021e0000021d0000021c0000021b0000021a;
    s_axis_rc_tuser  <= 161'h0000000000000000000061021fffff0000fffffff;   

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000023500000234000002330000023200000231000002300000022f0000022e0000022d0000022c0000022b0000022a00000229000002280000022700000226;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000020900000208000002070000020600000000000002400000023f0000023e0000023d0000023c0000023b0000023a00000239000002380000023700000236;
    s_axis_rc_tuser  <= 161'h00000000000000000000a100000000fffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000024d0000024c0000024b0000024a000002490000024800000247000002460000024500000244000002430000024200000241000009040100002001000900;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000025d0000025c0000025b0000025a000002590000025800000257000002560000025500000254000002530000025200000251000002500000024f0000024e;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;   
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h00000269000002680000026700000266000002650000026400000263000002620000026100000904010000204080098000000000000002600000025f0000025e;
    s_axis_rc_tuser  <= 161'h0000000000000000000021011fffffffff0000fff;

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000002790000027800000277000002760000027500000274000002730000027200000271000002700000026f0000026e0000026d0000026c0000026b0000026a;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000002800000027f0000027e0000027d0000027c0000027b0000027a;
    s_axis_rc_tuser  <= 161'h0000000000000000000061000000000000fffffff;

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000028d0000028c0000028b0000028a000002890000028800000287000002860000028500000284000002830000028200000281000009050100002002000a00;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;   
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000029d0000029c0000029b0000029a000002990000029800000297000002960000029500000294000002930000029200000291000002900000028f0000028e;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000002a9000002a8000002a7000002a6000002a5000002a4000002a3000002a2000002a1000009050100002001800a8000000000000002a00000029f0000029e;
    s_axis_rc_tuser  <= 161'h0000000000000000000021011fffffffff0000fff;  

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000002b9000002b8000002b7000002b6000002b5000002b4000002b3000002b2000002b1000002b0000002af000002ae000002ad000002ac000002ab000002aa;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000002c5000002c4000002c3000002c2000002c1000009050100002001000b0000000000000002c0000002bf000002be000002bd000002bc000002bb000002ba;
    s_axis_rc_tuser  <= 161'h0000000000000000000061021fffff0000fffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000002d5000002d4000002d3000002d2000002d1000002d0000002cf000002ce000002cd000002cc000002cb000002ca000002c9000002c8000002c7000002c6;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000002e1000009050100002040800b8000000000000002e0000002df000002de000002dd000002dc000002db000002da000002d9000002d8000002d7000002d6;
    s_axis_rc_tuser  <= 161'h00000000000000000000a1031f0000fffffffffff;   
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000002f1000002f0000002ef000002ee000002ed000002ec000002eb000002ea000002e9000002e8000002e7000002e6000002e5000002e4000002e3000002e2;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000000000000300000002ff000002fe000002fd000002fc000002fb000002fa000002f9000002f8000002f7000002f6000002f5000002f4000002f3000002f2;
    s_axis_rc_tuser  <= 161'h00000000000000000000e10000fffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000030d0000030c0000030b0000030a000003090000030800000307000003060000030500000304000003030000030200000301000009060100002002000c00;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000031d0000031c0000031b0000031a000003190000031800000317000003160000031500000314000003130000031200000311000003100000030f0000030e;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;    

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000003290000032800000327000003260000032500000324000003230000032200000321000009060100002001800c8000000000000003200000031f0000031e;
    s_axis_rc_tuser  <= 161'h0000000000000000000021011fffffffff0000fff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000003390000033800000337000003360000033500000334000003330000033200000331000003300000032f0000032e0000032d0000032c0000032b0000032a;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000003400000033f0000033e0000033d0000033c0000033b0000033a;
    s_axis_rc_tuser  <= 161'h0000000000000000000061000000000000fffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000034d0000034c0000034b0000034a000003490000034800000347000003460000034500000344000003430000034200000341000009060100002001000d00;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;   
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000035d0000035c0000035b0000035a000003590000035800000357000003560000035500000354000003530000035200000351000003500000034f0000034e;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000003690000036800000367000003660000036500000364000003630000036200000361000009060100002040800d8000000000000003600000035f0000035e;
    s_axis_rc_tuser  <= 161'h0000000000000000000021011fffffffff0000fff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000003790000037800000377000003760000037500000374000003730000037200000371000003700000036f0000036e0000036d0000036c0000036b0000036a;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000003800000037f0000037e0000037d0000037c0000037b0000037a;
    s_axis_rc_tuser  <= 161'h0000000000000000000061000000000000fffffff; 
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000038d0000038c0000038b0000038a000003890000038800000387000003860000038500000384000003830000038200000381000009070100002002000e00;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000; 
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0000039d0000039c0000039b0000039a000003990000039800000397000003960000039500000394000003930000039200000391000003900000038f0000038e;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000003a9000003a8000003a7000003a6000003a5000003a4000003a3000003a2000003a1000009070100002001800e8000000000000003a00000039f0000039e;
    s_axis_rc_tuser  <= 161'h0000000000000000000021011fffffffff0000fff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000003b9000003b8000003b7000003b6000003b5000003b4000003b3000003b2000003b1000003b0000003af000003ae000003ad000003ac000003ab000003aa;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff; 
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000000000000000000000000000000000000000000000000000000000000000000000000000003c0000003bf000003be000003bd000003bc000003bb000003ba;
    s_axis_rc_tuser  <= 161'h0000000000000000000061000000000000fffffff; 

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000003cd000003cc000003cb000003ca000003c9000003c8000003c7000003c6000003c5000003c4000003c3000003c2000003c1000009070100002001000f00;
    s_axis_rc_tuser  <= 161'h0000000000000000000000001fffffffffffff000;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000003dd000003dc000003db000003da000003d9000003d8000003d7000003d6000003d5000003d4000003d3000003d2000003d1000003d0000003cf000003ce;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff; 
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000003e9000003e8000003e7000003e6000003e5000003e4000003e3000003e2000003e1000009070100002040800f8000000000000003e0000003df000003de;
    s_axis_rc_tuser  <= 161'h0000000000000000000021011fffffffff0000fff; 

    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h000003f9000003f8000003f7000003f6000003f5000003f4000003f3000003f2000003f1000003f0000003ef000003ee000003ed000003ec000003eb000003ea;
    s_axis_rc_tuser  <= 161'h0000000000000000000000000ffffffffffffffff;    
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h00000000000000000000000000000000000000000000000000000000000000000000000000000400000003ff000003fe000003fd000003fc000003fb000003fa;
    s_axis_rc_tuser  <= 161'h0000000000000000000061000000000000fffffff; 
    wait(s_axis_rc_tvalid & s_axis_rc_tready);
    @(posedge clk);
    s_axis_rc_tdata  <= 512'h0;
    s_axis_rc_tuser  <= 161'h0; 
    s_axis_rc_tvalid <= 0;
    cfg_interrupt_msi_sent <= 1;
`endif

    $stop;
end




send_axis #(
    .STREAM_TDATA_WIDTH 	(512  )
)axis_generate(
    .m_axis_aclk    	(clk   ),
    .m_axis_aresetn 	(~rst  ),
    .st_length      	(st_length       ),
    .st_start       	(st_start        ),
    .st_end         	(st_end          ),
    .m_axis_tdata   	(S_AXIS_DMA_TDATA    ),
    .m_axis_tkeep   	(S_AXIS_DMA_TKEEP    ),
    .m_axis_tlast   	(S_AXIS_DMA_TLAST    ),
    .m_axis_tvalid  	(S_AXIS_DMA_TVALID   ),
    .m_axis_tready  	(S_AXIS_DMA_TREADY   )
);


fpga_core #(
    .AXIS_PCIE_DATA_WIDTH       (AXIS_PCIE_DATA_WIDTH),
    .RQ_SEQ_NUM_ENABLE          (1  ),
    .PCIE_TAG_COUNT             (32 ),

    .BAR_ADDRESS_MODE           (32 ),

    .PF0_BAR0_ENABLE            (1  ),
    .PF0_BAR0_SCALE             (1024),
    .PF0_BAR0_SIZE              (2  ),

    .PF0_BAR1_ENABLE            (1  ),
    .PF0_BAR1_SCALE             (1024),
    .PF0_BAR1_SIZE              (2),

    .MSI_COUNT                  (1),
    // .USER_MSI_IRQ               (USER_MSI_IRQ_EX),

    .DMA_INTERFACE_MODE         ("AXI_MEMORY_MAP"),
    .AXI_ADDR_WIDTH             (C_M_AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH               (8),
    .AXI_DATA_WIDTH             (C_M_AXI_DATA_WIDTH),

    .AXIL_CTRL_ADDR_WIDTH       (32)
//    .DEBUG_CORE(0)

)tb_fpga_core(
    .clk                                           	(clk  ),
    .rst                                           	(rst  ),

//    .M_AXI_ACLK                                    (clk        ),
//    .M_AXI_ARESETN                                 (~rst     ),

    .M_AXI_ARID              (M_AXI_ARID        ),
    .M_AXI_ARADDR            (M_AXI_ARADDR      ),
    .M_AXI_ARLEN             (M_AXI_ARLEN       ),
    .M_AXI_ARSIZE            (M_AXI_ARSIZE      ),
    .M_AXI_ARBURST           (M_AXI_ARBURST     ),
    .M_AXI_ARLOCK            (M_AXI_ARLOCK      ),
    .M_AXI_ARCACHE           (M_AXI_ARCACHE     ),
    .M_AXI_ARPROT            (M_AXI_ARPROT      ),
    .M_AXI_ARQOS             (M_AXI_ARQOS       ),
    .M_AXI_ARVALID           (M_AXI_ARVALID     ),
    .M_AXI_ARREADY           (M_AXI_ARREADY     ),
    .M_AXI_RID               (M_AXI_RID         ),
    .M_AXI_RDATA             (M_AXI_RDATA       ),
    .M_AXI_RRESP             (M_AXI_RRESP       ),
    .M_AXI_RLAST             (M_AXI_RLAST       ),
    .M_AXI_RVALID            (M_AXI_RVALID      ),
    .M_AXI_RREADY            (M_AXI_RREADY      ),
    .M_AXI_AWID              (M_AXI_AWID        ),
    .M_AXI_AWADDR            (M_AXI_AWADDR      ),
    .M_AXI_AWLEN             (M_AXI_AWLEN       ),
    .M_AXI_AWSIZE            (M_AXI_AWSIZE      ),
    .M_AXI_AWBURST           (M_AXI_AWBURST     ),
    .M_AXI_AWLOCK            (M_AXI_AWLOCK      ),
    .M_AXI_AWCACHE           (M_AXI_AWCACHE     ),
    .M_AXI_AWPROT            (M_AXI_AWPROT      ),
    .M_AXI_AWQOS             (M_AXI_AWQOS       ),
    .M_AXI_AWVALID           (M_AXI_AWVALID     ),
    .M_AXI_AWREADY           (M_AXI_AWREADY     ),
    .M_AXI_WDATA             (M_AXI_WDATA       ),
    .M_AXI_WSTRB             (M_AXI_WSTRB       ),
    .M_AXI_WLAST             (M_AXI_WLAST       ),
    .M_AXI_WVALID            (M_AXI_WVALID      ),
    .M_AXI_WREADY            (M_AXI_WREADY      ),
    .M_AXI_BID               (M_AXI_BID         ),
    .M_AXI_BRESP             (M_AXI_BRESP       ),
    .M_AXI_BVALID            (M_AXI_BVALID      ),
    .M_AXI_BREADY            (M_AXI_BREADY      ),

    .S_AXIS_DMA_TDATA        (S_AXIS_DMA_TDATA  ),
    .S_AXIS_DMA_TKEEP        (S_AXIS_DMA_TKEEP  ),
    .S_AXIS_DMA_TVALID       (S_AXIS_DMA_TVALID ),     
    .S_AXIS_DMA_TLAST        (S_AXIS_DMA_TLAST  ),
    .S_AXIS_DMA_TREADY       (S_AXIS_DMA_TREADY ),               
    .M_AXIS_DMA_TDATA        (M_AXIS_DMA_TDATA  ),
    .M_AXIS_DMA_TKEEP        (M_AXIS_DMA_TKEEP  ),
    .M_AXIS_DMA_TVALID       (M_AXIS_DMA_TVALID ),     
    .M_AXIS_DMA_TLAST        (M_AXIS_DMA_TLAST  ),
    .M_AXIS_DMA_TREADY       (1'b1 ), 

    .m_axis_rq_tdata                               	(m_axis_rq_tdata   ),
    .m_axis_rq_tkeep                               	(m_axis_rq_tkeep   ),
    .m_axis_rq_tlast                               	(m_axis_rq_tlast   ),
    .m_axis_rq_tready                              	(m_axis_rq_tready  ),
    .m_axis_rq_tuser                               	(m_axis_rq_tuser   ),
    .m_axis_rq_tvalid                              	(m_axis_rq_tvalid  ),

    .s_axis_rc_tdata                               	(s_axis_rc_tdata     ),
    .s_axis_rc_tkeep                               	(s_axis_rc_tkeep     ),
    .s_axis_rc_tlast                               	(s_axis_rc_tlast     ),
    .s_axis_rc_tready                              	(s_axis_rc_tready    ),
    .s_axis_rc_tuser                               	(s_axis_rc_tuser     ),
    .s_axis_rc_tvalid                              	(s_axis_rc_tvalid    ),

    .s_axis_cq_tdata                               	(s_axis_cq_tdata     ),
    .s_axis_cq_tkeep                               	(s_axis_cq_tkeep     ),
    .s_axis_cq_tlast                               	(s_axis_cq_tlast     ),
    .s_axis_cq_tready                              	(s_axis_cq_tready    ),
    .s_axis_cq_tuser                               	(s_axis_cq_tuser     ),
    .s_axis_cq_tvalid                              	(s_axis_cq_tvalid    ),

    .m_axis_cc_tdata                               	(m_axis_cc_tdata     ),
    .m_axis_cc_tkeep                               	(m_axis_cc_tkeep     ),
    .m_axis_cc_tlast                               	(m_axis_cc_tlast     ),
    .m_axis_cc_tready                              	(m_axis_cc_tready    ),
    .m_axis_cc_tuser                               	(m_axis_cc_tuser     ),
    .m_axis_cc_tvalid                              	(m_axis_cc_tvalid    ),

    .s_axis_rq_seq_num_0                           	(s_axis_rq_seq_num_0         ),
    .s_axis_rq_seq_num_valid_0                     	(s_axis_rq_seq_num_valid_0   ),
    .s_axis_rq_seq_num_1                           	(s_axis_rq_seq_num_1         ),
    .s_axis_rq_seq_num_valid_1                     	(s_axis_rq_seq_num_valid_1   ),

    .cfg_max_payload                               	(cfg_max_payload      ),
    .cfg_max_read_req                              	(cfg_max_read_req     ),
    .cfg_rcb_status                                	(cfg_rcb_status       ),

    .cfg_mgmt_addr                                 	(cfg_mgmt_addr               ),
    .cfg_mgmt_function_number                      	(cfg_mgmt_function_number    ),
    .cfg_mgmt_write                                	(cfg_mgmt_write              ),
    .cfg_mgmt_write_data                           	(cfg_mgmt_write_data         ),
    .cfg_mgmt_byte_enable                          	(cfg_mgmt_byte_enable        ),
    .cfg_mgmt_read                                 	(cfg_mgmt_read               ),
    .cfg_mgmt_read_data                            	(cfg_mgmt_read_data          ),
    .cfg_mgmt_read_write_done                      	(cfg_mgmt_read_write_done    ),
    .cfg_bus_number                                 (8'h00),

    .cfg_fc_ph                                     	(cfg_fc_ph        ),
    .cfg_fc_pd                                     	(cfg_fc_pd        ),
    .cfg_fc_nph                                    	(cfg_fc_nph       ),
    .cfg_fc_npd                                    	(cfg_fc_npd       ),
    .cfg_fc_cplh                                   	(cfg_fc_cplh      ),
    .cfg_fc_cpld                                   	(cfg_fc_cpld      ),
    .cfg_fc_sel                                    	(cfg_fc_sel       ),

    .cfg_interrupt_msi_function_number             	(cfg_interrupt_msi_function_number              ),
    .cfg_interrupt_msi_attr                        	(cfg_interrupt_msi_attr                         ),
    .cfg_interrupt_msi_tph_present                 	(cfg_interrupt_msi_tph_present                  ),
    .cfg_interrupt_msi_tph_type                    	(cfg_interrupt_msi_tph_type                     ),
    .cfg_interrupt_msi_tph_st_tag                  	(cfg_interrupt_msi_tph_st_tag                   ),
    .cfg_interrupt_msi_enable                      	(cfg_interrupt_msi_enable                       ),
    .cfg_interrupt_msi_vf_enable                   	(cfg_interrupt_msi_vf_enable                    ),
    .cfg_interrupt_msi_mmenable                    	(cfg_interrupt_msi_mmenable                     ),
    .cfg_interrupt_msi_mask_update                 	(cfg_interrupt_msi_mask_update                  ),
    .cfg_interrupt_msi_data                        	(cfg_interrupt_msi_data                         ),
    .cfg_interrupt_msi_select                      	(cfg_interrupt_msi_select                       ),
    .cfg_interrupt_msi_int                         	(cfg_interrupt_msi_int                          ),
    .cfg_interrupt_msi_pending_status              	(cfg_interrupt_msi_pending_status               ),
    .cfg_interrupt_msi_pending_status_data_enable  	(cfg_interrupt_msi_pending_status_data_enable   ),
    .cfg_interrupt_msi_pending_status_function_num 	(cfg_interrupt_msi_pending_status_function_num  ),
    .cfg_interrupt_msi_sent                        	(cfg_interrupt_msi_sent                         ),
    .cfg_interrupt_msi_fail                        	(cfg_interrupt_msi_fail                         ),
    .msi_irq                                        (msi_irq),

    .status_error_cor                              	(status_error_cor                               ),
    .status_error_uncor                            	(status_error_uncor                             )
);

/*
 * 
 */


axi_ram #(
    .DATA_WIDTH       	(AXIS_PCIE_DATA_WIDTH),
    .ADDR_WIDTH       	(16),
    .ID_WIDTH         	(1),
    .PIPELINE_OUTPUT  	(0)
)tb_axi_ram(
    .clk           	(clk            ),
    .rst           	(rst            ),

    .s_axi_awid    	(M_AXI_AWID     ),
    .s_axi_awaddr  	(M_AXI_AWADDR  ),
    .s_axi_awlen   	(M_AXI_AWLEN    ),
    .s_axi_awsize  	(M_AXI_AWSIZE   ),
    .s_axi_awburst 	(M_AXI_AWBURST  ),
    .s_axi_awlock  	(M_AXI_AWLOCK   ),
    .s_axi_awcache 	(M_AXI_AWCACHE  ),
    .s_axi_awprot  	(M_AXI_AWPROT   ),
    .s_axi_awvalid 	(M_AXI_AWVALID  ),
    .s_axi_awready 	(M_AXI_AWREADY  ),

    .s_axi_wdata   	(M_AXI_WDATA    ),
    .s_axi_wstrb   	(M_AXI_WSTRB    ),
    .s_axi_wlast   	(M_AXI_WLAST    ),
    .s_axi_wvalid  	(M_AXI_WVALID   ),
    .s_axi_wready  	(M_AXI_WREADY   ),

    .s_axi_bid     	(M_AXI_BID      ),
    .s_axi_bresp   	(M_AXI_BRESP    ),
    .s_axi_bvalid  	(M_AXI_BVALID   ),
    .s_axi_bready  	(M_AXI_BREADY   ),

    .s_axi_arid    	(M_AXI_ARID     ),
    .s_axi_araddr  	(M_AXI_ARADDR   ),
    .s_axi_arlen   	(M_AXI_ARLEN    ),
    .s_axi_arsize  	(M_AXI_ARSIZE   ),
    .s_axi_arburst 	(M_AXI_ARBURST  ),
    .s_axi_arlock  	(M_AXI_ARLOCK   ),
    .s_axi_arcache 	(M_AXI_ARCACHE  ),
    .s_axi_arprot  	(M_AXI_ARPROT   ),
    .s_axi_arvalid 	(M_AXI_ARVALID  ),
    .s_axi_arready 	(M_AXI_ARREADY  ),

    .s_axi_rid     	(M_AXI_RID      ),
    .s_axi_rdata   	(M_AXI_RDATA    ),
    .s_axi_rresp   	(M_AXI_RRESP    ),
    .s_axi_rlast   	(M_AXI_RLAST    ),
    .s_axi_rvalid  	(M_AXI_RVALID   ),
    .s_axi_rready  	(M_AXI_RREADY   )
);


always #(`CLOCK_PERIOD / 2) clk = ~clk;

endmodule