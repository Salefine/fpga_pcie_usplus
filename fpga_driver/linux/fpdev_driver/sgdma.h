/****************************************************************************
 * @file    sgdma.h
 * @brief  
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2025-01-22
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

#ifndef _SGDMA_H_
#define _SGDMA_H_

#ifdef __KERNEL__
#include <linux/dma-mapping.h>
#endif

#include <linux/scatterlist.h>

struct fpga_pdev;

//1. 
struct fdev_sgdma
{
    /* 用户空间 */
    void __user *user_buf;     // 用户缓冲区地址
    size_t len;               // 总数据长度

    /* GUP相关 */
    struct page **pages;      // 锁定的页数组
    int npages;               // 页数量

    /* SG表 */
    struct scatterlist *sgl;  // SG表起始地址
    int nents;                // SG表项数（原始）
    int mapped_nents;         // DMA映射后的表项数

    /* DMA映射 */
    struct device *dev;       // 设备（用于DMA API）
    #ifdef __KERNEL__
    enum dma_data_direction dir; // DMA方向
                                 // DMA_TO_DEVICE / DMA_FROM_DEVICE
    #endif

    /* 状态 */
    int mapped;               // 是否已经dma_map_sg
};

#define SG_NUM_MAX                  512 * 4096
#define SGDMA_LIST_BUFFER_SIZE      8*1024


struct fdev_sgdma *get_sg_list(struct fpga_pdev *fpdev, void *sg_buf, unsigned long userdata, 
    unsigned long long length, enum dma_data_direction dir);


void free_sg_buf(struct fpga_pdev *fpdev, struct fdev_sgdma * sg_map) ;    

int sg_c2h(struct fpga_pdev *fpdev, unsigned int * c2h_buffer, 
    unsigned int c2h_bufsize, unsigned long long timeout, unsigned long long c2h_sdram_addr);


int sg_h2c(struct fpga_pdev *fpdev, unsigned int * h2c_buffer, 
     unsigned int h2c_bufsize, unsigned long long timeout,unsigned long long h2c_sdram_addr);    


int  allocate_sglistdma(struct pci_dev *pdev, struct fpga_pdev *fpdev);

#endif
 