/****************************************************************************
 * @file    block_dma.c
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

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/uaccess.h>     // Ϊ�� copy_to_user, copy_from_user
#include <linux/slab.h>
#include <linux/wait.h>        // Ϊ�� DEFINE_WAIT, wait_event_interruptible_timeout
#include <linux/jiffies.h>     // Ϊ�� msecs_to_jiffies
#include <linux/atomic.h>      // Ϊ�� atomic_read, atomic_set
#include <linux/errno.h>       // Ϊ�� -ETIMEDOUT, -EFAULT �ȴ�����
#include <linux/device.h>      // Ϊ�� dev_info, dev_err
#include <linux/version.h>     // Ϊ�� LINUX_VERSION_CODE
#include "block_dma.h"
#include "fpdev_mod.h"

int  allocate_blockdma(struct pci_dev *pdev, struct fpga_pdev *fpdev)
{
	dma_addr_t hw_addr;
	struct device *dev = &pdev->dev;
 
	init_waitqueue_head(&fpdev->c2h_bl_waitq);
	init_waitqueue_head(&fpdev->h2c_bl_waitq);
 
	fpdev->blockdma_size = BLOCK_DMA_BUF_SIZE;
 
	/* allocate C2H buffer */
	fpdev->c2h_bl_dma_vaddr = dma_alloc_coherent(&pdev->dev,
							fpdev->blockdma_size,
							&hw_addr,
							GFP_KERNEL);
 
	if (!fpdev->c2h_bl_dma_vaddr) {
	 	dev_err(dev, "fpdev: allocate c2h dma buffer error\n");
		return -ENOMEM;
	}
 
	fpdev->c2h_bl_dma_hwaddr = hw_addr;
 	dev_info(dev, "fpdev: allocate c2h dma buffer %u bytes\n",
			fpdev->blockdma_size);
	/* allocate H2C buffer */
	fpdev->h2c_bl_dma_vaddr = dma_alloc_coherent(&pdev->dev,
							fpdev->blockdma_size,
							&hw_addr,
							GFP_KERNEL);
 
	if (!fpdev->h2c_bl_dma_vaddr) {
		dev_err(dev, "fpdev: allocate h2c dma buffer error\n");
		return -ENOMEM;
	}
 
	fpdev->h2c_bl_dma_hwaddr = hw_addr;
 
	dev_info(dev, "fpdev: allocate h2c dma buffer %u bytes\n",
			fpdev->blockdma_size);
 
	return 0;
}

void  free_blockdma(struct pci_dev *pdev,struct fpga_pdev *fpdev){
	struct device *dev = &pdev->dev;
	dev_info(dev, "fpdev: Start free block dma \n");
	if(fpdev->c2h_bl_dma_vaddr){
		dma_free_coherent(&pdev->dev, 
			fpdev->blockdma_size,
			fpdev->c2h_bl_dma_vaddr,
			fpdev->c2h_bl_dma_hwaddr
		);
		dev_info(dev, "fpdev: C2H has free \n");
	}
	if(fpdev->h2c_bl_dma_vaddr){
		dma_free_coherent(&pdev->dev, 
			fpdev->blockdma_size,
			fpdev->h2c_bl_dma_vaddr,
			fpdev->h2c_bl_dma_hwaddr
		);
		dev_info(dev, "fpdev: H2C has free \n");
	}	
}

int block_c2h(struct fpga_pdev *fpdev, unsigned int *c2h_buffer, 
    unsigned int c2h_bufsize, unsigned long long timeout, unsigned long long fpga_sdram_addr)
{
	dma_addr_t dma_addr = 0;
	unsigned int c2h_dma_status;
	long timeouto;
	int ret;
	struct device *dev = &fpdev->dev->dev;

	//write fpga sdram low 32bit address
	write_reg(fpdev, C2H_BLOCK_SDRAM_ADDR_LO, fpga_sdram_addr & 0xffffffff, 0);
	//write fpga sdram high 32bit address
	write_reg(fpdev, C2H_BLOCK_SDRAM_ADDR_HO, (fpga_sdram_addr >> 32) & 0xffffffff,0);
	//write length
	write_reg(fpdev, C2H_BLOCK_DMA_LENGTH, c2h_bufsize & 0xffffffff , 0);

	#ifdef STREAM_DMA
	#if LINUX_VERSION_CODE < KERNEL_VERSION(5,0,0)
		dma_addr = pci_map_single(fpdev->dev, fpdev->c2h_bl_dma_vaddr, 
								BLOCK_DMA_BUF_SIZE, PCI_DMA_FROMDEVICE);
	#else
		dma_addr = dma_map_single(&fpdev->dev->dev, fpdev->c2h_bl_dma_vaddr, 
								BLOCK_DMA_BUF_SIZE, DMA_FROM_DEVICE);
	#endif            
	#else
	dma_addr = fpdev->c2h_bl_dma_hwaddr;
	#endif	

	write_reg(fpdev, C2H_BLOCK_DMA_ADDR_LO, dma_addr & 0xffffffff , 0);
	write_reg(fpdev, C2H_BLOCK_DMA_ADDR_HO, (dma_addr >> 32) & 0xffffffff , 0);      
	//start dma
	write_reg(fpdev, C2H_BLOCK_DMA_START, 1 , 0);
	
	timeouto = msecs_to_jiffies(timeout);

	while (1){
		ret = wait_event_interruptible_timeout(fpdev->c2h_bl_waitq, (atomic_read(&fpdev->intr_c2h_status) != 0), timeouto);

		if(ret == -ERESTARTSYS){
			atomic_set(&fpdev->intr_c2h_status, 0);
			dev_info(dev, "fpdev: C2H interrupted by signal\n");
			#ifdef STREAM_DMA
			dma_unmap_single(&fpdev->dev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, DMA_FROM_DEVICE);
			#endif
			return -ERESTARTSYS;
		}

		if(ret == 0){
			atomic_set(&fpdev->intr_c2h_status, 0);
			dev_info(dev, "fpdev: C2H timed out\n");
			#ifdef STREAM_DMA
			dma_unmap_single(&fpdev->dev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, DMA_FROM_DEVICE);
			#endif
			return -ETIMEDOUT;
		}

		if(atomic_read(&fpdev->intr_c2h_status) != 0){
			c2h_dma_status = read_reg(fpdev, C2H_BLOCK_DMA_STATUS, 0);
			if(c2h_dma_status & 0x1){
				write_reg(fpdev, C2H_BLOCK_DMA_STATUS, 0, 0);
				#ifdef STREAM_DMA
				#if LINUX_VERSION_CODE < KERNEL_VERSION(5,0,0)
					dma_unmap_single(fpdev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, PCI_DMA_FROMDEVICE);
				#else
					dma_unmap_single(&fpdev->dev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, DMA_FROM_DEVICE);
				#endif
				#endif
				atomic_set(&fpdev->intr_c2h_status, 0);
				dev_info(dev, "fpdev: C2H completed\n");
				
				if(c2h_bufsize > BLOCK_DMA_BUF_SIZE){
					if(copy_to_user(c2h_buffer, (unsigned int *)fpdev->c2h_bl_dma_vaddr, c2h_bufsize)){
						dev_err(dev, "fpdev: dma copy_to_user error!\n");
					}
					return -EINVAL;
				}
				else {
					if(copy_to_user(c2h_buffer, (unsigned int *)fpdev->c2h_bl_dma_vaddr, c2h_bufsize)){
						dev_err(dev, "fpdev: dma copy_to_user error!\n");
					}
					return c2h_bufsize;
				}
			}
		}
	}
}


int block_h2c(struct fpga_pdev *fpdev, unsigned int *h2c_buffer, 
    unsigned int h2c_bufsize, unsigned long long timeout, unsigned long long fpga_sdram_addr){
	long timeouto;
	int ret;
	unsigned int h2c_dma_status;
	struct device *dev = &fpdev->dev->dev;
  dma_addr_t dma_addr;

	dev_info(dev, "Start H2C DMA\n");
	if(h2c_bufsize != 0){
		dev_info(dev, "fpdev: Move the data in user space to the kernel space\n");
		if(copy_from_user((unsigned int *)fpdev->h2c_bl_dma_vaddr, h2c_buffer, h2c_bufsize)){
			dev_err(dev, "fpdev: dma copy_to_user error! \n");
			return -EFAULT;
		}
	}
	else {
		dev_err(dev, "fpdev: h2c_bufsize must not be 0 \n");
		return -EINVAL;
	}
	#ifdef STREAM_DMA
	#if LINUX_VERSION_CODE < KERNEL_VERSION(5,0,0)
		dma_addr = pci_map_single(fpdev->dev, fpdev->h2c_bl_dma_vaddr, BLOCK_DMA_BUF_SIZE, PCI_DMA_TODEVICE);
	#else
		dma_addr = dma_map_single(&fpdev->dev->dev, fpdev->h2c_bl_dma_vaddr, BLOCK_DMA_BUF_SIZE, DMA_TO_DEVICE);

		if (dma_mapping_error(&fpdev->dev->dev, dma_addr)) {
			dev_err(dev, "fpdev: DMA mapping failed\n");
			return -EFAULT;
		}
	#endif
	#else
	dma_addr = fpdev->h2c_bl_dma_hwaddr;
	#endif	

	//host write register to fpga's bar dma address low address 
	write_reg(fpdev, H2C_BLOCK_DMA_ADDR_LO, dma_addr & 0xffffffff, 0);
	//host write register to fpga's bar dma address high address 
	write_reg(fpdev, H2C_BLOCK_DMA_ADDR_HO, (dma_addr >> 32) & 0xffffffff, 0);
	//host write register to fpga's bar ddr address low address 
	write_reg(fpdev, H2C_BLOCK_SDRAM_ADDR_LO, fpga_sdram_addr & 0xffffffff, 0);
	//host write register to fpga's bar ddr address high address 
	write_reg(fpdev, H2C_BLOCK_SDRAM_ADDR_HO, (fpga_sdram_addr >> 32) & 0xffffffff, 0); 
	//write length to bar
	write_reg(fpdev, H2C_BLOCK_DMA_LENGTH, h2c_bufsize & 0xffffffff, 0);   
	//start
	write_reg(fpdev, H2C_BLOCK_DMA_START, 0x1, 0);  

	timeouto = msecs_to_jiffies(timeout);
	while(1){
		ret = wait_event_interruptible_timeout(fpdev->h2c_bl_waitq, (atomic_read(&fpdev->intr_h2c_status) != 0), timeouto);
		if(ret == -ERESTARTSYS){
			atomic_set(&fpdev->intr_h2c_status, 0);
			dev_info(dev, "fpdev: H2C interrupted by signal\n");
			#ifdef STREAM_DMA
			dma_unmap_single(&fpdev->dev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, DMA_TO_DEVICE);
			#endif
			return -ERESTARTSYS;
		}

		if(ret == 0){
			atomic_set(&fpdev->intr_h2c_status, 0);
			dev_info(dev, "fpdev: H2C timed out\n");
			#ifdef STREAM_DMA
			dma_unmap_single(&fpdev->dev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, DMA_TO_DEVICE);
			#endif
			return -ETIMEDOUT;
		}

		if(atomic_read(&fpdev->intr_h2c_status) != 0){
			dev_info(dev, "fpdev: H2C DMA has done \n");
			h2c_dma_status = read_reg(fpdev, H2C_BLOCK_DMA_STATUS, 0);
			if(h2c_dma_status == 0x01){
				write_reg(fpdev, H2C_BLOCK_DMA_STATUS, 0 , 0);
				#ifdef STREAM_DMA
				#if LINUX_VERSION_CODE < KERNEL_VERSION(5,0,0)
					pci_unmap_single(fpdev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, PCI_DMA_TODEVICE);
				#else
					dma_unmap_single(&fpdev->dev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, DMA_TO_DEVICE);
				#endif
				#endif
				atomic_set(&fpdev->intr_h2c_status,0);
				#ifdef DEBUG
				dev_info(dev, "fpdev: clean h2c intr_h2c_status dma done \n");
				#endif
				return h2c_bufsize;
			}
		}
	}
}