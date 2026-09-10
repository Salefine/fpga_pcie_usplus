/****************************************************************************
 * @file    block_dma.h
 * @brief  
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2026-07-16
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    zzhi          |                        |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2025 zzhi
 * ***************************************************************************/


#include <linux/pci.h>
#include <linux/dma-mapping.h>
#define BLOCK_DMA_BUF_SIZE 4*1024*1024

struct fpga_pdev ;

int  allocate_blockdma(struct pci_dev *dev,struct fpga_pdev *fpdev);

void  free_blockdma(struct pci_dev *dev,struct fpga_pdev *fpdev);

int block_c2h(struct fpga_pdev *fpdev, unsigned int *c2h_buffer, 
    unsigned int c2h_bufsize, unsigned long long timeout, unsigned long long fpga_sdram_addr);

int block_h2c(struct fpga_pdev *fpdev, unsigned int *h2c_buffer, 
    unsigned int h2c_bufsize, unsigned long long timeout, unsigned long long fpga_sdram_addr);