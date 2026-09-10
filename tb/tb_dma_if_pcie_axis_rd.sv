/****************************************************************************
 * @file    tb_dma_if_pcie_axis_rd.sv
 * @brief  Testbench for H2C_BlockDMA_rd_tlp - three DMA reads: 1 B, 4 KiB, 1755 B.
 *
 * m_axis_tlp_tkeep is per-byte valid (standard AXI tkeep).
 *
 * When rcb_128b=1 (128 B Read Completion Boundary), each MRd is answered with
 * multiple CPLD TLPs: each CPLD carries at most 128 B; Byte Count in the header
 * is the remaining bytes including this CPLD (PCIe base spec). Each CPLD EOP
 * can pulse tx_rd_dma_done, so the TB must ack_dma_done once per CPLD.
 *
 * Compile (from tb/):
 *   xvlog --sv ../../../rtl/xpm_sync_fifo.v ../../../rtl/H2C_BlockDMA_rd_tlp_v1.v \
 *         tb_H2C_BlockDMA_rd_tlp.sv
 *   xelab work.tb_H2C_BlockDMA_rd_tlp -debug typical
 *   xsim work.tb_H2C_BlockDMA_rd_tlp -runall
 *
 * @copyright Copyright (c) 2026 welie
 ****************************************************************************/

`timescale 1ns / 1ps

module tb_dma_if_pcie_axis_rd;

  localparam int TLP_DATA_WIDTH   = 512;
  localparam int TLP_HDR_WIDTH    = 128;
  localparam int TLP_SEG_COUNT    = 1;
  localparam int TX_SEQ_NUM_WIDTH = 6;
  localparam int AXIS_BYTES       = TLP_DATA_WIDTH / 8;

  logic clk;
  logic rst;

  logic [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0] tx_rd_req_tlp_hdr;
  logic [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0] tx_rd_req_tlp_seq;
  logic [TLP_SEG_COUNT-1:0] tx_rd_req_tlp_valid;
  logic [TLP_SEG_COUNT-1:0] tx_rd_req_tlp_sop;
  logic [TLP_SEG_COUNT-1:0] tx_rd_req_tlp_eop;
  logic tx_rd_req_tlp_ready;

  logic [TLP_DATA_WIDTH-1:0] rx_cpl_tlp_data;
  logic [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0] rx_cpl_tlp_hdr;
  logic [TLP_SEG_COUNT*4-1:0] rx_cpl_tlp_error;
  logic [TLP_SEG_COUNT-1:0] rx_cpl_tlp_valid;
  logic [TLP_SEG_COUNT-1:0] rx_cpl_tlp_sop;
  logic [TLP_SEG_COUNT-1:0] rx_cpl_tlp_eop;
  logic rx_cpl_tlp_ready;

  logic enable;
  logic ext_tag_enable;
  logic rcb_128b;
  logic [15:0] requester_id;

  logic [31:0] tx_rd_req_length;
  logic [63:0] tx_rd_req_address;
  logic [2:0] Max_read_PayloadSize;
  logic tx_rd_req_start;


  // logic tx_rd_dma_done;
  // logic tx_rd_dma_valid;
  // logic tx_rd_dma_ready;
  
  reg tx_rd_req_irq_sent = 1;

  logic [TLP_DATA_WIDTH-1:0] m_axis_tlp_tdata;
  // AXI byte strobes: one bit per data byte on m_axis_tlp_tdata.
  logic [TLP_DATA_WIDTH/8-1:0] m_axis_tlp_tkeep;
  logic m_axis_tlp_tvalid;
  logic m_axis_tlp_tlast;
  logic m_axis_tlp_tready;

  task automatic axis_random_backpressure();
  begin
      m_axis_tlp_tready <= 1'b1;
  
      forever begin
          @(posedge clk);
  
          if (m_axis_tlp_tvalid) begin
  
              if ($urandom_range(0,9)==0) begin
                  m_axis_tlp_tready <= 1'b0;
  
                  repeat($urandom_range(1,8))
                      @(posedge clk);
  
                  m_axis_tlp_tready <= 1'b1;
              end
  
          end
          else begin
              m_axis_tlp_tready <= 1'b1;
          end
      end
  end
  endtask

  // Every MRd handshake (DUT may pipeline several before first CPLD) - do not use
  // a single wait_mrd per user chunk or tags will be missed

  typedef struct packed {
    logic [7:0] tag;
    logic [9:0] len_dw;
  } mrd_obs_t;

  mailbox #(mrd_obs_t) mrd_mbx = new();

  // Vivado VRFC: no mailbox.put() inside always_ff (put uses scheduling); use plain always.
  always @(posedge clk) begin
    if (!rst) begin
      if (tx_rd_req_tlp_valid && tx_rd_req_tlp_ready && tx_rd_req_tlp_sop && tx_rd_req_tlp_eop)
        mrd_mbx.put(mrd_obs_t'{tx_rd_req_tlp_hdr[79:72], tx_rd_req_tlp_hdr[105:96]});
    end
  end

  dma_if_pcie_axis_rd_v1 #(
      .TLP_DATA_WIDTH(TLP_DATA_WIDTH),
      .TLP_HDR_WIDTH(TLP_HDR_WIDTH),
      .TLP_SEG_COUNT(TLP_SEG_COUNT),
      .PCIE_TAG_COUNT(32),
      .TX_SEQ_NUM_WIDTH(TX_SEQ_NUM_WIDTH)
  ) dut (
      .clk(clk),
      .rst(rst),
      .tx_rd_req_tlp_hdr(tx_rd_req_tlp_hdr),
      .tx_rd_req_tlp_seq(tx_rd_req_tlp_seq),
      .tx_rd_req_tlp_valid(tx_rd_req_tlp_valid),
      .tx_rd_req_tlp_sop(tx_rd_req_tlp_sop),
      .tx_rd_req_tlp_eop(tx_rd_req_tlp_eop),
      .tx_rd_req_tlp_ready(tx_rd_req_tlp_ready),
      .rx_cpl_tlp_data(rx_cpl_tlp_data),
      .rx_cpl_tlp_hdr(rx_cpl_tlp_hdr),
      .rx_cpl_tlp_error(rx_cpl_tlp_error),
      .rx_cpl_tlp_valid(rx_cpl_tlp_valid),
      .rx_cpl_tlp_sop(rx_cpl_tlp_sop),
      .rx_cpl_tlp_eop(rx_cpl_tlp_eop),
      .rx_cpl_tlp_ready(rx_cpl_tlp_ready),
      .ext_tag_enable(ext_tag_enable),
      .rcb_128b(rcb_128b),
      .requester_id(requester_id),
//      .max_read_request_size(max_read_request_size),
      .desc_tx_rd_req_length(tx_rd_req_length),
      .desc_tx_rd_req_address(tx_rd_req_address),
      .Max_read_PayloadSize(Max_read_PayloadSize),
      .desc_tx_rd_req_start(tx_rd_req_start),
      .m_axis_tlp_tdata(m_axis_tlp_tdata),
      .m_axis_tlp_tkeep(m_axis_tlp_tkeep),
      .m_axis_tlp_tvalid(m_axis_tlp_tvalid),
      .m_axis_tlp_tlast(m_axis_tlp_tlast),
      .m_axis_tlp_tready(m_axis_tlp_tready)
  );

  // Hierarchical: MRd accepted -> tag_table slot taken (same as TLP header tag field)
  // always @(posedge clk) begin
  //   if (!rst) begin
  //     if (dut.tx_rd_req_tlp_valid && dut.tx_rd_req_tlp_sop && dut.tx_rd_req_tlp_eop && dut.tx_rd_req_tlp_ready)
  //       $display("%0t TB [TAG ALLOC] tag=%0h  len_dw=%0d  seq=%0h",
  //                $time, dut.tx_rd_tag_length_next, dut.tx_rd_req_tlp_hdr[105:96], dut.tx_rd_req_tlp_seq);
  //   end
  // end

  // RTL clears tag_table when the corresponding FIFO is selected for ordered output.
//  always @(posedge clk) begin
//    if (!rst) begin
//      if (dut.tag_id_release_reg)
//        $display("%0t TB [TAG REL]   tag=%0h",
//                 $time, dut.rx_cpl_tlp_hdr_tag);
//    end
//  end

  localparam realtime CLK_HALF = 2.0;
  localparam int RCB_BYTES = 128;
  localparam bit OUT_OF_ORDER_TAG_RETURN = 1'b1;
  localparam int OOO_TAG_WINDOW = 8;
  initial clk = 1'b0;
  always #(CLK_HALF) clk = ~clk;

  typedef struct {
    logic [7:0] tag;
    logic [9:0] len_dw;
    int         take;
    int         mrd_i;
  } cpld_desc_t;

  function automatic [TLP_HDR_WIDTH-1:0] cpld_hdr(
      input logic [7:0] tag,
      input logic [9:0] length_dw,
      input logic [11:0] byte_count,
      input logic [1:0] lower_addr
  );
    cpld_hdr = '0;
    cpld_hdr[105:96] = length_dw;
    cpld_hdr[75:64] = byte_count;
    cpld_hdr[47:40] = tag;
    cpld_hdr[33:32] = lower_addr;
  endfunction

  task drive_idle_rx();
    rx_cpl_tlp_data  <= '0;
    rx_cpl_tlp_hdr   <= '0;
    rx_cpl_tlp_error <= '0;
    rx_cpl_tlp_valid <= '0;
    rx_cpl_tlp_sop   <= '0;
    rx_cpl_tlp_eop   <= '0;
  endtask

  task pulse_start();
    @(posedge clk);
    tx_rd_req_start <= 1'b1;
    @(posedge clk);
    tx_rd_req_start <= 1'b0;
  endtask

  // Send one CPLD TLP (possibly multiple AXI beats). PCIe Length=len_dw DW;
  // byte_count_sop = Byte Count field (bytes remaining including this CPLD).
  // slice_i distinguishes CPLD slices when one MRd is split for RCB.
  task send_cpld_multibeat(
      input logic [7:0] tag,
      input logic [9:0] len_dw,
      input int         byte_count_sop,
      input int         xfer_id,
      input int         mrd_index,
      input int         slice_i
  );
    int payload_bytes;
    int beats;
    int bi;
    begin
      payload_bytes = len_dw * 4;
      beats = (payload_bytes + AXIS_BYTES - 1) / AXIS_BYTES;

      for (bi = 0; bi < beats; bi = bi + 1) begin
        while (!rx_cpl_tlp_ready) @(posedge clk);

        // Repeat header on all beats so hdr[47:40] stays valid at EOP (debug / some RTL paths)
        rx_cpl_tlp_hdr <= cpld_hdr(tag, len_dw, byte_count_sop[11:0], 2'b00);

        for (int w = 0; w < TLP_DATA_WIDTH / 32; w++) begin
          rx_cpl_tlp_data[32*w+:32] <= 32'h0000_0000 + xfer_id * 32'h10000 +
              mrd_index * 32'h1000 + slice_i * 32'h100 + bi * 32'h10 + w;
        end

        rx_cpl_tlp_error <= '0;
        rx_cpl_tlp_valid <= 1'b1;
        rx_cpl_tlp_sop   <= (bi == 0);
        rx_cpl_tlp_eop   <= (bi == beats - 1);
        @(posedge clk);
      end

      drive_idle_rx();
    end
  endtask

  task send_mrd_completion(
      input logic [7:0] tag,
      input logic [9:0] len_dw,
      input int         take,
      input int         xfer_id,
      input int         mrd_i
  );
    int rem_bc;
    int chunk_b;
    int chunk_ldw;
    int slice_i;
    begin
      if (!rcb_128b) begin
        send_cpld_multibeat(tag, len_dw, take, xfer_id, mrd_i, 0);
      end else begin
        rem_bc  = take;
        slice_i = 0;

        while (rem_bc > 0) begin
          chunk_b   = (rem_bc < RCB_BYTES) ? rem_bc : RCB_BYTES;
          chunk_ldw = (chunk_b + 3) >> 2;

          send_cpld_multibeat(
            tag,
            chunk_ldw[9:0],
            rem_bc,
            xfer_id,
            mrd_i,
            slice_i
          );

          rem_bc  -= chunk_b;
          slice_i += 1;
        end
      end
    end
  endtask

task run_dma_read(input int nbytes, input logic [63:0] base_addr, input int xfer_id);
  int bytes_rem;
  mrd_obs_t pkt;
  logic [7:0] tag;
  logic [9:0] len_dw;
  int phys_b;
  int take;
  int mrd_i;
  int window_cnt;
  int send_i;
  int send_slot;
  mrd_obs_t junk;
  cpld_desc_t cpld_window[OOO_TAG_WINDOW];
begin
  bytes_rem = nbytes;
  mrd_i = 0;

  while (mrd_mbx.num() > 0) void'(mrd_mbx.try_get(junk));

  tx_rd_req_length  <= nbytes[31:0];
  tx_rd_req_address <= base_addr;

  $display("TB: xfer %0d start - %0d bytes @ %h", xfer_id, nbytes, base_addr);

  pulse_start();

  while (bytes_rem > 0) begin
    window_cnt = 0;

    while ((bytes_rem > 0) && (window_cnt < OOO_TAG_WINDOW)) begin
      mrd_mbx.get(pkt);

      tag    = pkt.tag;
      len_dw = pkt.len_dw;
      phys_b = len_dw * 4;
      take   = (bytes_rem < phys_b) ? bytes_rem : phys_b;

      cpld_window[window_cnt].tag    = tag;
      cpld_window[window_cnt].len_dw = len_dw;
      cpld_window[window_cnt].take   = take;
      cpld_window[window_cnt].mrd_i  = mrd_i;

      $display("TB: xfer %0d MRd #%0d tag=%h len_dw=%0d take=%0d bytes queued slot=%0d",
               xfer_id, mrd_i, tag, len_dw, take, window_cnt);

      bytes_rem -= take;
      mrd_i++;
      window_cnt++;
    end

    for (send_i = 0; send_i < window_cnt; send_i++) begin
      send_slot = OUT_OF_ORDER_TAG_RETURN ? (window_cnt - 1 - send_i) : send_i;

      $display("TB: xfer %0d CPLD return slot=%0d MRd #%0d tag=%h out_of_order=%0d",
               xfer_id,
               send_slot,
               cpld_window[send_slot].mrd_i,
               cpld_window[send_slot].tag,
               OUT_OF_ORDER_TAG_RETURN);

      send_mrd_completion(
        cpld_window[send_slot].tag,
        cpld_window[send_slot].len_dw,
        cpld_window[send_slot].take,
        xfer_id,
        cpld_window[send_slot].mrd_i
      );
    end
  end

  $display("TB: xfer %0d finished, total MRds=%0d", xfer_id, mrd_i);
  repeat (32) @(posedge clk);
end
endtask
  task tb_pulse_rst();
    mrd_obs_t junk;
    @(posedge clk);
    //rst <= 1'b1;
    drive_idle_rx();
    repeat (400) @(posedge clk);
    while (mrd_mbx.num() > 0) void'(mrd_mbx.try_get(junk));
    rst <= 1'b0;
    repeat (8) @(posedge clk);
  endtask

  initial begin
    rst = 1'b1;
    tx_rd_req_tlp_ready = 1'b1;
    m_axis_tlp_tready   = 1'b1;

    enable                = 1'b1;
    ext_tag_enable        = 1'b1;
    rcb_128b              = 1'b1;
    requester_id          = 16'h10EE;


    tx_rd_req_length      = '0;
    tx_rd_req_address     = 64'h0000_8000_0000;
    Max_read_PayloadSize  = 3'b010;
    tx_rd_req_start       = 1'b0;

    drive_idle_rx();

    repeat (8) @(posedge clk);
    rst = 1'b0;
    repeat (8) @(posedge clk);
    fork
        axis_random_backpressure();   // 推荐使用方法四
    join_none
    // 1) 1 byte
    run_dma_read(32'h1, 64'h0000_8000_0000, 0);
    tb_pulse_rst();
    // #(`CLK_HALF * 400);
    // 2) 4 KiB (4096 B). Max_read_PayloadSize=010 => 512 B/MRd => 8 MRds; rcb_128b=1 => 4 CPLDs/MRd.
    run_dma_read(32'h0000_ff70, 64'h0000_8000_0000, 1);
    tb_pulse_rst();
    run_dma_read(32'h0004_0000, 64'h0000_8000_0000, 1);
    tb_pulse_rst();
    run_dma_read(32'h0000_ffff, 64'h0000_8000_0000, 1);
    tb_pulse_rst();
    // #(`CLK_HALF * 400);
    // 3) 1755 B => four 512 B-class MRds last shorter; each MRd gets multiple 128 B CPLDs if rcb_128b.
    run_dma_read(1755, 64'h0000_8020_0000, 2);

    $display("TB: all three transfers done.");
    repeat (40) @(posedge clk);
    $finish;
  end



endmodule