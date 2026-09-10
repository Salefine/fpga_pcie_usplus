#test for sgdma write
#author: zhi


import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.clock import Clock


async def start_clock(dut):
    """Start a 250 MHz clock (4 ns period) on `clk`."""
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())


async def reset_dut(dut, cycles=10):
    dut.rst.value = 1
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def sgdma_pcie_axis_wr(dut):
    """Simple functional smoke test for `sgdma_if_pcie_axis_wr`.

    This test drives a descriptor read request (sglist) into the DUT and
    waits for the DUT to issue a read request on `tx_rd_req_tlp_valid`.
    """
    await start_clock(dut)
    await reset_dut(dut)

    # configure IDs / sizes
    dut.requester_id.value = 0x0010
    dut.MaxPayloadSize.value = 0x2
    # module port is named `max_read_payloadSize`
    try:
        dut.max_read_payloadSize.value = 0x2
    except Exception:
        # some testbenches may expose a different name; ignore if missing
        pass

    # ensure ready is asserted so DUT can drive requests
    try:
        dut.tx_rd_req_tlp_ready.value = 1
    except Exception:
        pass

    # small wait
    await Timer(20, units="ns")

    # drive descriptor sglist start
    dut.desc_wr_req_sglist_length.value = 0x00800000
    dut.desc_wr_req_sglist_address.value = 0xcfc00000
    dut.desc_wr_req_sglist_start.value = 1
    await RisingEdge(dut.clk)
    dut.desc_wr_req_sglist_start.value = 0

    # wait for DUT to assert a read request
    timeout_cycles = 1000
    for cycle in range(timeout_cycles):
        await RisingEdge(dut.clk)
        try:
            if int(dut.tx_rd_req_tlp_valid.value) == 1:
                cocotb.log.info(f"tx_rd_req_tlp_valid asserted at cycle {cycle}")
                break
        except Exception:
            # if signal name differs or not present, continue polling
            pass
    else:
        raise AssertionError("Timeout waiting for tx_rd_req_tlp_valid from DUT")

    # keep the simulation running a short time to observe behavior
    await Timer(200, units="ns")


async def respond_read_completion(dut, address=0xcfc00000, length=0x1000, nums=1):
    """Respond to DUT read requests with a single CPL containing sglist entry."""
    # ensure ready
    try:
        dut.rx_cpl_tlp_ready.value = 1
    except Exception:
        pass

    # wait for a read request
    for _ in range(1000):
        await RisingEdge(dut.clk)
        try:
            if int(dut.tx_rd_req_tlp_valid.value) == 1:
                cocotb.log.info("Detected tx_rd_req_tlp_valid, sending completion")
                # construct tdata: {nums[31:0], length[31:0], address[63:0]} in lower 128 bits
                tdata = (nums << (64+32)) | (length << 64) | (address & ((1<<64)-1))
                dut.rx_cpl_tlp_data.value = tdata
                dut.rx_cpl_tlp_sop.value = 1
                dut.rx_cpl_tlp_eop.value = 1
                dut.rx_cpl_tlp_valid.value = 1
                await RisingEdge(dut.clk)
                dut.rx_cpl_tlp_valid.value = 0
                dut.rx_cpl_tlp_sop.value = 0
                dut.rx_cpl_tlp_eop.value = 0
                return
        except Exception:
            pass


async def feed_s_axis_data(dut, beats=8):
    """Feed `s_axis_tlp_*` stream when DUT is ready."""
    try:
        dut.s_axis_tlp_tkeep.value = (1 << (int(dut.s_axis_tlp_tdata._width // 8))) - 1
    except Exception:
        # ignore if keep width unknown
        pass

    sent = 0
    while sent < beats:
        await RisingEdge(dut.clk)
        try:
            if int(dut.s_axis_tlp_tready.value) == 1:
                # drive one beat
                dut.s_axis_tlp_tdata.value = sent + 1
                try:
                    # set tkeep to all ones sized to TLP_DATA_WIDTH/8
                    keep_width = int(dut.s_axis_tlp_tkeep._width)
                    dut.s_axis_tlp_tkeep.value = (1 << keep_width) - 1
                except Exception:
                    pass
                dut.s_axis_tlp_tvalid.value = 1
                dut.s_axis_tlp_tlast.value = 1 if (sent == beats-1) else 0
                await RisingEdge(dut.clk)
                # deassert valid until next ready
                dut.s_axis_tlp_tvalid.value = 0
                dut.s_axis_tlp_tlast.value = 0
                sent += 1
        except Exception:
            # signals missing? break
            break