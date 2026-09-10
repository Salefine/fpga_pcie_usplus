/**
 * @file    fdma_mod.h
 * @brief   FPGA PCIe DMA driver definitions and interfaces.
 *
 * This header file defines the common data structures, DMA register
 * addresses, device parameters, and ioctl interfaces used by the
 * FPGA PCIe DMA driver.
 *
 * The driver supports:
 *   - PCIe BAR access
 *   - Block DMA
 *   - Scatter-Gather DMA
 *   - Register read/write through ioctl
 *   - DMA interrupt status and wait queues
 *
 * @author  weslie (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2025-01-22
 *
 * @par Version History:
 * --------------------------------------------------------------------------
 * | Date       | Version | Author  | Description                           |
 * |------------|---------|---------|---------------------------------------|
 * |            | v1.0    | weslie  | Initial version                       |
 * --------------------------------------------------------------------------
 *
 * @copyright Copyright (c) 2025 weslie
 */

#ifndef _FDMA_MOD_H_
#define _FDMA_MOD_H_

/*
 * Kernel-space dependencies.
 *
 * These headers provide the PCIe device definition, DMA interfaces,
 * block DMA support, and PCI device ID definitions.
 */
#ifdef __KERNEL__

#include "sgdma.h"
#include "block_dma.h"
#include "pci_ids.h"

#endif


/* --------------------------------------------------------------------------
 * Driver and device definitions
 * -------------------------------------------------------------------------- */

/* Device node name created by the driver. */
#define DEVICE_NAME     "zzhiDMA"

/* PCI driver name. */
#define DRIVER_NAME     "fpdev"

/* Static major number used by ioctl definitions. */
#define MAJOR_NUM       100

/* Maximum number of FPGA devices supported by the driver. */
#define NUM_FPGAS       32

/* Xilinx PCI vendor ID. */
#define VENDOR_ID0      0x10EE


/* --------------------------------------------------------------------------
 * Block DMA register definitions
 *
 * Register offsets are expressed in 32-bit word units.
 * The actual byte offset is calculated as:
 *
 *     byte_offset = register_offset << 2
 *
 * C2H: FPGA/device -> Host
 * H2C: Host -> FPGA/device
 * -------------------------------------------------------------------------- */

/* ----------------------------- C2H Block DMA ---------------------------- */

/* Host buffer DMA address, lower 32 bits. */
#define C2H_BLOCK_DMA_ADDR_LO       0x00

/* Host buffer DMA address, upper 32 bits. */
#define C2H_BLOCK_DMA_ADDR_HO       0x01

/* Start C2H block DMA transfer. */
#define C2H_BLOCK_DMA_START         0x02

/* C2H block DMA transfer length. */
#define C2H_BLOCK_DMA_LENGTH        0x03

/* C2H block DMA status register. */
#define C2H_BLOCK_DMA_STATUS        0x08

/* FPGA/SDRAM destination address, lower 32 bits. */
#define C2H_BLOCK_SDRAM_ADDR_LO     0x0a

/* FPGA/SDRAM destination address, upper 32 bits. */
#define C2H_BLOCK_SDRAM_ADDR_HO     0x0b


/* ----------------------------- H2C Block DMA ---------------------------- */

/* Host buffer DMA address, lower 32 bits. */
#define H2C_BLOCK_DMA_ADDR_LO       0x04

/* Host buffer DMA address, upper 32 bits. */
#define H2C_BLOCK_DMA_ADDR_HO       0x05

/* Start H2C block DMA transfer. */
#define H2C_BLOCK_DMA_START         0x06

/* H2C block DMA transfer length. */
#define H2C_BLOCK_DMA_LENGTH        0x07

/* H2C block DMA status register. */
#define H2C_BLOCK_DMA_STATUS        0x09

/* FPGA/SDRAM source address, lower 32 bits. */
#define H2C_BLOCK_SDRAM_ADDR_LO     0x0c

/* FPGA/SDRAM source address, upper 32 bits. */
#define H2C_BLOCK_SDRAM_ADDR_HO     0x0d


/* --------------------------------------------------------------------------
 * Scatter-Gather DMA register definitions
 * -------------------------------------------------------------------------- */

/* ----------------------------- C2H SG DMA ------------------------------- */

/* SG descriptor/list buffer address, lower 32 bits. */
#define C2H_SG_LIST_ADDR_LO         0x0e

/* SG descriptor/list buffer address, upper 32 bits. */
#define C2H_SG_LIST_ADDR_HO         0x0f

/* Start C2H SG DMA operation. */
#define C2H_SG_LIST_START           0x10

/* Number/length of SG list entries. */
#define C2H_SG_LIST_LENGTH          0x11

/* C2H SG DMA status register. */
#define C2H_SG_LIST_STATUS          0x16

/* Total C2H SG DMA transfer length. */
#define C2H_SGDMA_LENGTH            0x18

/* FPGA/SDRAM destination address, lower 32 bits. */
#define C2H_SGDMA_SDRAM_ADDR_LO     0x1b

/* FPGA/SDRAM destination address, upper 32 bits. */
#define C2H_SGDMA_SDRAM_ADDR_HO     0x1a


/* ----------------------------- H2C SG DMA ------------------------------- */

/* SG descriptor/list buffer address, lower 32 bits. */
#define H2C_SG_LIST_ADDR_LO         0x12

/* SG descriptor/list buffer address, upper 32 bits. */
#define H2C_SG_LIST_ADDR_HO         0x13

/* H2C SG DMA status register. */
#define H2C_SG_LIST_STATUS          0x17

/* Start H2C SG DMA operation. */
#define H2C_SG_LIST_START           0x14

/* Number/length of SG list entries. */
#define H2C_SG_LIST_LENGTH          0x15

/* FPGA/SDRAM source address, lower 32 bits. */
#define H2C_SGDMA_SDRAM_ADDR_LO     0x1d

/* FPGA/SDRAM source address, upper 32 bits. */
#define H2C_SGDMA_SDRAM_ADDR_HO     0x1c

/* Total H2C SG DMA transfer length. */
#define H2C_SGDMA_LENGTH            0x19


/* --------------------------------------------------------------------------
 * Kernel-space FPGA device structure
 *
 * This structure stores the private state associated with one FPGA PCIe
 * device, including PCIe BAR mappings, DMA buffers, interrupt status,
 * and DMA wait queues.
 * -------------------------------------------------------------------------- */

#ifdef __KERNEL__

struct fpga_pdev {

    /* Associated PCIe device. */
    struct pci_dev *dev;

    /* ----------------------------------------------------------------------
     * PCIe BAR information
     * ---------------------------------------------------------------------- */

    /* Virtual addresses of mapped PCIe BARs. */
    void __iomem *bar[6];

    /* Size of each PCIe BAR. */
    resource_size_t bar_len[6];

    /* Driver-assigned FPGA device index. */
    int id;

    /* Device name used by the driver. */
    char name[16];

    /* PCI vendor and device IDs. */
    int vendor_id;
    int device_id;


    /* ----------------------------------------------------------------------
     * Block DMA resources
     * ---------------------------------------------------------------------- */

    /* Size of the block DMA buffer. */
    unsigned int blockdma_size;

    /* C2H DMA buffer physical/DMA address. */
    dma_addr_t c2h_bl_dma_hwaddr;

    /* C2H DMA buffer virtual address. */
    void *c2h_bl_dma_vaddr;

    /* C2H DMA buffer length. */
    unsigned int c2h_bl_dma_len;

    /* Wait queue used by C2H block DMA completion. */
    wait_queue_head_t c2h_bl_waitq;

    /* Wait queue used by H2C block DMA completion. */
    wait_queue_head_t h2c_bl_waitq;

    /* H2C DMA buffer physical/DMA address. */
    dma_addr_t h2c_bl_dma_hwaddr;

    /* H2C DMA buffer virtual address. */
    void *h2c_bl_dma_vaddr;

    /* H2C DMA buffer length. */
    unsigned int h2c_bl_dma_len;


    /* ----------------------------------------------------------------------
     * Block DMA interrupt status
     * ---------------------------------------------------------------------- */

    /* C2H block DMA interrupt/completion status. */
    atomic_t intr_c2h_status;

    /* H2C block DMA interrupt/completion status. */
    atomic_t intr_h2c_status;


    /* ----------------------------------------------------------------------
     * Scatter-Gather DMA resources
     * ---------------------------------------------------------------------- */

    /* C2H SG DMA interrupt/completion status. */
    atomic_t intr_sgc2h_status;

    /* H2C SG DMA interrupt/completion status. */
    atomic_t intr_sgh2c_status;

    /* C2H SG DMA hardware address. */
    dma_addr_t c2h_sg_dma_hwaddr;

    /* H2C SG DMA hardware address. */
    dma_addr_t h2c_sg_dma_hwaddr;

    /* Wait queue used by C2H SG DMA completion. */
    wait_queue_head_t c2h_sg_waitq;

    /* Wait queue used by H2C SG DMA completion. */
    wait_queue_head_t h2c_sg_waitq;

    /* Virtual address of the C2H SG descriptor/list buffer. */
    void *c2h_sgl_dma_vaddr;

    /* Virtual address of the H2C SG descriptor/list buffer. */
    void *h2c_sgl_dma_vaddr;

    /* Size of the SG descriptor/list buffer. */
    unsigned int sglist_block_size;
};


/* --------------------------------------------------------------------------
 * Register access functions
 * -------------------------------------------------------------------------- */

/**
 * @brief Write a 32-bit value to a PCIe BAR register.
 *
 * @param fpdev   FPGA device private data.
 * @param offset  Register offset in 32-bit word units.
 * @param wdata   Data to be written.
 * @param bar_id  BAR index.
 */
void write_reg(struct fpga_pdev *fpdev,
               int offset,
               unsigned int wdata,
               int bar_id);


/**
 * @brief Read a 32-bit value from a PCIe BAR register.
 *
 * @param fpdev   FPGA device private data.
 * @param offset  Register offset in 32-bit word units.
 * @param bar_id  BAR index.
 *
 * @return 32-bit register value.
 */
unsigned int read_reg(struct fpga_pdev *fpdev,
                      int offset,
                      int bar_id);

#endif /* __KERNEL__ */


/* --------------------------------------------------------------------------
 * User/kernel ioctl data structure
 *
 * This structure is shared between user space and kernel space.
 * It contains parameters required for register access and DMA transfers.
 * -------------------------------------------------------------------------- */

struct fpga_iodev {

    /* FPGA device index. */
    int id;

    /* PCIe BAR index used for register access. */
    int bar_id;

    /* Register address/offset. */
    int regaddr;

    /* Register data for read/write operations. */
    unsigned int regdata;

    /* DMA operation timeout. */
    unsigned long long timeout;


    /* ----------------------------------------------------------------------
     * C2H DMA parameters
     * ---------------------------------------------------------------------- */

    /* User-space destination buffer for C2H data. */
    unsigned int *c2h_byte_buf;

    /* C2H transfer size in bytes. */
    unsigned int c2h_byte_bufsize;

    /* FPGA/SDRAM source address for C2H transfer. */
    unsigned long long c2h_sdram_addr;


    /* ----------------------------------------------------------------------
     * H2C DMA parameters
     * ---------------------------------------------------------------------- */

    /* User-space source buffer for H2C data. */
    unsigned int *h2c_byte_buf;

    /* H2C transfer size in bytes. */
    unsigned int h2c_byte_bufsize;

    /* FPGA/SDRAM destination address for H2C transfer. */
    unsigned long long h2c_sdram_addr;
};


typedef struct fpga_iodev fpga_iodev;


/* --------------------------------------------------------------------------
 * IOCTL command definitions
 *
 * The IOCTL interface provides user-space access to:
 *   - FPGA register read/write
 *   - Block DMA
 *   - Scatter-Gather DMA
 * -------------------------------------------------------------------------- */

/* Write a register. */
#define IOCTL_WR_REG    _IOW(MAJOR_NUM, 2, fpga_iodev *)

/* Read a register. */
#define IOCTL_RD_REG    _IOR(MAJOR_NUM, 3, fpga_iodev *)

/* Start a block C2H DMA transfer. */
#define IOCTL_BL_WR     _IOW(MAJOR_NUM, 4, fpga_iodev *)

/* Start a block H2C DMA transfer. */
#define IOCTL_BL_RD     _IOR(MAJOR_NUM, 5, fpga_iodev *)

/* Start a Scatter-Gather C2H DMA transfer. */
#define IOCTL_SG_WR     _IOW(MAJOR_NUM, 6, fpga_iodev *)

/* Start a Scatter-Gather H2C DMA transfer. */
#define IOCTL_SG_RD     _IOR(MAJOR_NUM, 7, fpga_iodev *)


#endif /* _FDMA_MOD_H_ */