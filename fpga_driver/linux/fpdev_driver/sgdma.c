/****************************************************************************
 * @file    sgdma.c
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
 * | 2026-09-03    |   v1.1      |    zzhi          | fix sg dma wait gate atomic |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2025 zzhi
 * ***************************************************************************/

#include <linux/version.h>
#include "sgdma.h"
#include "fpdev_mod.h"


struct fdev_sgdma *get_sg_list(struct fpga_pdev *fpdev,
                               void *sg_buf,
                               unsigned long userdata,
                               unsigned long long length,
                               enum dma_data_direction dir)
{
    struct fdev_sgdma *sg_map = NULL;
    struct page **pages = NULL;
    struct scatterlist *sgl = NULL;
    struct scatterlist *sg;
    struct device *dev = &fpdev->dev->dev;

    unsigned long long num_pages_req = 0;
    unsigned long long len_rem = length;

    long num_pages = 0;
    int num_sg = 0;
    int i;

    unsigned int fp_offset;
    unsigned int hw_len;

    dma_addr_t hw_addr;

    unsigned long long len;

    unsigned int *sglist_buf_ptr = (unsigned int *)sg_buf;

    unsigned int gup_flags = FOLL_WRITE;

    /*
     * ---------------------------------------------------------
     * 1. 参数检查
     * ---------------------------------------------------------
     */
    if (fpdev == NULL || sg_buf == NULL || length == 0) {
        dev_err(dev, "fpdev: invalid parameter\n");
        return NULL;
    }

    /*
     * ---------------------------------------------------------
     * 2. 分配 fdev_sgdma
     * ---------------------------------------------------------
     */
    sg_map = kzalloc(sizeof(*sg_map), GFP_KERNEL);
    if (sg_map == NULL) {
        dev_err(dev,
                "fpdev: could not allocate memory for fdev_sgdma\n");
        return NULL;
    }

    /*
     * ---------------------------------------------------------
     * 3. 计算需要多少个 page
     * ---------------------------------------------------------
     */
    num_pages_req =
        ((userdata + length - 1) >> PAGE_SHIFT) -
        (userdata >> PAGE_SHIFT) + 1;

    dev_info(dev,
             "fpdev: userdata=0x%lx length=%llu num_pages_req=%llu\n",
             userdata,
             length,
             num_pages_req);

    /*
     * ---------------------------------------------------------
     * 4. 检查 page 数量
     * ---------------------------------------------------------
     */
    if (num_pages_req > SG_NUM_MAX) {
        dev_err(dev,
                "fpdev: required pages=%llu > SG_NUM_MAX=%u\n",
                num_pages_req,
                SG_NUM_MAX);

        kfree(sg_map);
        return NULL;
    }

    /*
     * ---------------------------------------------------------
     * 5. 分配 page 指针数组
     * ---------------------------------------------------------
     */
    pages = kvmalloc_array(num_pages_req,
                           sizeof(*pages),
                           GFP_KERNEL);

    if (pages == NULL) {
        dev_err(dev,
                "fpdev: could not allocate memory for pages array, "
                "size=%zu bytes\n",
                (size_t)num_pages_req * sizeof(*pages));

        kfree(sg_map);
        return NULL;
    }

    /*
     * ---------------------------------------------------------
     * 6. GUP 获取用户空间 page
     * ---------------------------------------------------------
     */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 8, 0)
    mmap_read_lock(current->mm);
#else
    down_read(&current->mm->mmap_sem);
#endif

#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 6, 0)

    num_pages = get_user_pages(current,
                               current->mm,
                               userdata,
                               num_pages_req,
                               1,
                               0,
                               pages,
                               NULL);

#elif LINUX_VERSION_CODE < KERNEL_VERSION(5, 6, 0)

    num_pages = get_user_pages(userdata,
                               num_pages_req,
                               FOLL_WRITE,
                               pages,
                               NULL);

#else

    num_pages = get_user_pages(userdata,
                               num_pages_req,
                               gup_flags,
                               pages,
                               NULL);

#endif

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 8, 0)
    mmap_read_unlock(current->mm);
#else
    up_read(&current->mm->mmap_sem);
#endif

    /*
     * ---------------------------------------------------------
     * 7. GUP 必须全部成功
     * ---------------------------------------------------------
     */
    if (num_pages != num_pages_req) {

        dev_err(dev,
                "fpdev: get_user_pages failed, "
                "requested=%llu pinned=%ld\n",
                num_pages_req,
                num_pages);

        /*
         * GUP 如果部分成功，已经成功 pin 的 page 必须释放
         */
        if (num_pages > 0) {
            for (i = 0; i < num_pages; i++)
                put_page(pages[i]);
        }

        kvfree(pages);
        kfree(sg_map);

        return NULL;
    }

    /*
     * ---------------------------------------------------------
     * 8. 分配 scatterlist
     *
     * 暂时保留原始设计。
     * 如果 num_pages 很大，后面建议改 sg_table。
     * ---------------------------------------------------------
     */
    dev_info(dev,
             "fpdev: allocate scatterlist, "
             "num_pages=%ld size=%zu bytes\n",
             num_pages,
             (size_t)num_pages * sizeof(*sgl));

    sgl = kvmalloc_array(num_pages,
                         sizeof(*sgl),
                         GFP_KERNEL);

    if (sgl == NULL) {

        dev_err(dev,
                "fpdev: could not allocate memory for scatterlist "
                "array, size=%zu bytes\n",
                (size_t)num_pages * sizeof(*sgl));

        for (i = 0; i < num_pages; i++)
            put_page(pages[i]);

        kvfree(pages);
        kfree(sg_map);

        return NULL;
    }

    /*
     * ---------------------------------------------------------
     * 9. 用户地址页偏移
     * ---------------------------------------------------------
     */
    fp_offset = userdata & ~PAGE_MASK;

    /*
     * 你当前 FPGA SGDMA 设计要求 buffer page aligned
     */
    if (fp_offset != 0) {

        dev_err(dev,
                "fpdev: usermemory not page aligned, "
                "offset=0x%x\n",
                fp_offset);

        for (i = 0; i < num_pages; i++)
            put_page(pages[i]);

        kvfree(pages);
        kvfree(sgl);
        kfree(sg_map);

        return NULL;
    }

    /*
     * ---------------------------------------------------------
     * 10. 初始化 scatterlist
     * ---------------------------------------------------------
     */
    sg_init_table(sgl, num_pages);

    for (i = 0; i < num_pages; i++) {

        len = (len_rem > PAGE_SIZE) ?
              PAGE_SIZE :
              len_rem;

        sg_set_page(&sgl[i],
                    pages[i],
                    len,
                    fp_offset);

        len_rem -= len;

        fp_offset = 0;

        if (len_rem == 0)
            break;
    }

    /*
     * ---------------------------------------------------------
     * 11. DMA mapping
     * ---------------------------------------------------------
     */
    num_sg = dma_map_sg(dev,
                        sgl,
                        num_pages,
                        dir);

    if (num_sg <= 0) {

        dev_err(dev,
                "fpdev: dma_map_sg failed, num_pages=%ld\n",
                num_pages);

        for (i = 0; i < num_pages; i++)
            put_page(pages[i]);

        kvfree(sgl);
        kvfree(pages);
        kfree(sg_map);

        return NULL;
    }

    dev_info(dev,
             "fpdev: dma_map_sg: original=%ld mapped=%d\n",
             num_pages,
             num_sg);

    /*
     * ---------------------------------------------------------
     * 12. 将 DMA address / length 写入 FPGA SG buffer
     * ---------------------------------------------------------
     */
    for_each_sg(sgl, sg, num_sg, i) {

        hw_addr = sg_dma_address(sg);
        hw_len  = sg_dma_len(sg);

        sglist_buf_ptr[i * 4 + 0] =
            lower_32_bits(hw_addr);

        sglist_buf_ptr[i * 4 + 1] =
            upper_32_bits(hw_addr);

        sglist_buf_ptr[i * 4 + 2] =
            hw_len;

        sglist_buf_ptr[i * 4 + 3] =
            i;
#ifdef DEBUG
        dev_info(dev,
                 "fpdev: SG[%d] addr=%pad len=%u\n",
                 i,
                 &hw_addr,
                 hw_len);
#endif
    }

    /*
     * ---------------------------------------------------------
     * 13. 保存 SGDMA 信息
     * ---------------------------------------------------------
     */
    sg_map->user_buf      = (void __user *)userdata;
    sg_map->len           = length;
    sg_map->pages         = pages;
    sg_map->npages        = num_pages;

    /*
     * 原始 SG entry 数量
     */
    sg_map->nents         = num_pages;

    /*
     * DMA mapping 后的 SG entry 数量
     */
    sg_map->mapped_nents  = num_sg;

    sg_map->sgl           = sgl;
    sg_map->dev           = dev;
    sg_map->dir           = dir;
    sg_map->mapped        = 1;

    return sg_map;
}


void free_sg_buf(struct fpga_pdev *fpdev,
                 struct fdev_sgdma *sg_map)
{
    int i;

    if (sg_map == NULL)
        return;

    /*
     * 1. DMA unmap
     *
     * dma_map_sg() 的输入是原始 SG 数量，
     * 所以 dma_unmap_sg() 也必须传原始 nents。
     */
    if (sg_map->sgl != NULL && sg_map->mapped) {

        dma_unmap_sg(&fpdev->dev->dev,
                     sg_map->sgl,
                     sg_map->nents,
                     sg_map->dir);

        sg_map->mapped = 0;
    }

    /*
     * 2. 释放 GUP pin 的 page
     */
    if (sg_map->pages != NULL && sg_map->npages > 0) {

        if (sg_map->dir == DMA_FROM_DEVICE) {

            /*
             * FPGA -> CPU
             *
             * DMA 写入用户空间内存，
             * 释放 page 前需要标记 dirty。
             */
            for (i = 0; i < sg_map->npages; i++) {

                if (!PageReserved(sg_map->pages[i]))
                    SetPageDirty(sg_map->pages[i]);

#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 6, 0)
                page_cache_release(sg_map->pages[i]);
#else
                put_page(sg_map->pages[i]);
#endif
            }

        } else {

            /*
             * CPU -> FPGA
             *
             * DMA 只读取用户空间内存，
             * 不需要 SetPageDirty()。
             */
            for (i = 0; i < sg_map->npages; i++) {

#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 6, 0)
                page_cache_release(sg_map->pages[i]);
#else
                put_page(sg_map->pages[i]);
#endif
            }
        }
    }

    /*
     * 3. 释放 page 指针数组
     *
     * get_sg_list() 使用的是 kvmalloc_array()
     */
    if (sg_map->pages != NULL) {
        kvfree(sg_map->pages);
        sg_map->pages = NULL;
    }

    /*
     * 4. 释放 scatterlist
     *
     * get_sg_list() 使用的是 kvmalloc_array()
     */
    if (sg_map->sgl != NULL) {
        kvfree(sg_map->sgl);
        sg_map->sgl = NULL;
    }

    /*
     * 5. 释放管理结构
     */
    kfree(sg_map);
}

int sg_c2h(struct fpga_pdev * fpdev, unsigned int * c2h_buffer, 
    unsigned int c2h_bufsize, unsigned long long timeout,unsigned long long fpga_sdram_addr){
    long timeouto;
    unsigned int Link_State;
    unsigned int sglist_length ;
    dma_addr_t dma_addr = 0;
    struct fdev_sgdma *sg_map;
    struct device *dev = &fpdev->dev->dev;
    int ret;
    dma_addr = fpdev->c2h_sg_dma_hwaddr;
    
    timeouto = msecs_to_jiffies(timeout);
    

    sg_map = get_sg_list(fpdev,
                        fpdev->c2h_sgl_dma_vaddr,
                        (unsigned long)c2h_buffer,
                        c2h_bufsize,
                        DMA_FROM_DEVICE);
    sglist_length= sg_map->mapped_nents << 4;
    dev_info(dev, "fpdev: sglist_length is [%u] bytes, sg_map->mapped_nents is [%d]\n",sglist_length,sg_map->mapped_nents);

    write_reg(fpdev, C2H_SG_LIST_ADDR_LO, dma_addr & 0xffffffff, 0);    
    write_reg(fpdev, C2H_SG_LIST_ADDR_HO, (dma_addr >> 32) & 0xffffffff, 0);
    write_reg(fpdev, C2H_SG_LIST_LENGTH  , sglist_length , 0);
    write_reg(fpdev, C2H_SG_LIST_START , 0x1, 0); //start read sg list
    
    write_reg(fpdev, C2H_SGDMA_LENGTH  , c2h_bufsize , 0);
    write_reg(fpdev, C2H_SGDMA_SDRAM_ADDR_LO, fpga_sdram_addr & 0xffffffff, 0);
    write_reg(fpdev, C2H_SGDMA_SDRAM_ADDR_HO, (fpga_sdram_addr >> 32) & 0xffffffff, 0);

    while (1)
    {
        ret = wait_event_interruptible_timeout(fpdev->c2h_sg_waitq, (atomic_read(&fpdev->intr_sgc2h_status) != 0x0), timeouto);
        if(ret == -ERESTARTSYS){
          atomic_set(&fpdev->intr_sgc2h_status, 0);
          #ifdef DEBUG
		      dev_info(dev, "fpdev: C2H interrupted by signal\n");
          #endif
		      free_sg_buf(fpdev, sg_map);
		      return -ERESTARTSYS;
        }

        if(ret == 0){
		    atomic_set(&fpdev->intr_sgc2h_status, 0);
            dev_info(dev, "fpdev: C2H timed out\n");
            free_sg_buf(fpdev, sg_map);
			return -ETIMEDOUT;
        }

        if (atomic_read(&fpdev->intr_sgc2h_status) != 0x0){
            Link_State = read_reg(fpdev, C2H_SG_LIST_STATUS, 0);

            if (Link_State == 0x1) //read sglist done
            {
		    	atomic_set(&fpdev->intr_sgc2h_status,0);
		    	#ifdef DEBUG
		    	dev_info(dev, "fpdev: clean c2h intr_c2h_status sglist done \n");
		    	#endif
		    	write_reg(fpdev, C2H_SG_LIST_STATUS, 0x0, 0);   
                write_reg(fpdev, C2H_SG_LIST_START, 0x2, 0);         
            }

            if (Link_State == 0x2)
            {
                write_reg(fpdev, C2H_SG_LIST_STATUS, 0,0); 
		    	#ifdef STREAM_DMA
		    	// using new DMA mapping API
		    	#if LINUX_VERSION_CODE < KERNEL_VERSION(5,0,0)
		    	    pci_unmap_single(fpdev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, PCI_DMA_FROMDEVICE);
		    	#else
		    		dma_unmap_single(&fpdev->dev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, DMA_FROM_DEVICE);
		    	#endif
		    	#endif
		    	atomic_set(&fpdev->intr_sgc2h_status,0);
		    	#ifdef DEBUG
		    	dev_info(dev, "fpdev: clean c2h intr_sgc2h_status sg dma done \n");
		    	#endif
                free_sg_buf(fpdev , sg_map);
                return c2h_bufsize;
            }
        }
    }
}

int sg_h2c(struct fpga_pdev * fpdev, unsigned int * h2c_buffer, 
    unsigned int h2c_bufsize, unsigned long long timeout,unsigned long long fpga_sdram_addr){
	  long timeouto;
    int ret;
    unsigned int Link_State;
    unsigned int sglist_length;
    dma_addr_t dma_addr;
    struct fdev_sgdma *sg_map;
    struct device *dev=&fpdev->dev->dev;    
    

    if (h2c_bufsize == 0)
    {
        dev_err(dev, "fpdev: dma SGH2C length = 0! \n");
        return -1;
    }
	// DMA 映射 (使用新 API)
    #ifdef STREAM_DMA
    #if LINUX_VERSION_CODE < KERNEL_VERSION(5,0,0)
        dma_addr = pci_map_single(fpdev->dev, fpdev->h2c_sgl_dma_vaddr, BLOCK_DMA_BUF_SIZE, PCI_DMA_FROMDEVICE);
    #else
        dma_addr = dma_map_single(&fpdev->dev->dev, fpdev->h2c_sgl_dma_vaddr, BLOCK_DMA_BUF_SIZE, DMA_FROM_DEVICE);
        // 检查 DMA 映射错误
    #endif
    #else
    dma_addr = fpdev->h2c_sg_dma_hwaddr;
    #endif    
    
    sg_map = get_sg_list(fpdev , fpdev->h2c_sgl_dma_vaddr , (unsigned long)h2c_buffer, h2c_bufsize , DMA_TO_DEVICE);

    sglist_length = sg_map->mapped_nents << 4;
    dev_info(dev, "fpdev: sglist_length is [%u] bytes, sg_map->mapped_nents is [%d]\n",sglist_length,sg_map->mapped_nents);

    write_reg(fpdev , H2C_SG_LIST_ADDR_HO, (dma_addr >> 32) & 0xffffffff,0);
    write_reg(fpdev , H2C_SG_LIST_ADDR_LO, dma_addr & 0xffffffff,0);
    write_reg(fpdev , H2C_SG_LIST_LENGTH, sglist_length & 0xffffffff,0);
    write_reg(fpdev , H2C_SG_LIST_START, 0x1,0); //start read sg list

    write_reg(fpdev , H2C_SGDMA_LENGTH, h2c_bufsize & 0xffffffff,0);
    write_reg(fpdev , H2C_SGDMA_SDRAM_ADDR_LO, fpga_sdram_addr & 0xffffffff,0);
    write_reg(fpdev , H2C_SGDMA_SDRAM_ADDR_HO, (fpga_sdram_addr >> 32) & 0xffffffff,0);
    

    dev_info(dev, "fpdev: start SGH2C DMA!");
    timeouto = msecs_to_jiffies(timeout);
    while (1)
    {
        ret = wait_event_interruptible_timeout(fpdev->h2c_sg_waitq, (atomic_read(&fpdev->intr_sgh2c_status) != 0x0), timeouto);
        if(ret == -ERESTARTSYS){
			atomic_set(&fpdev->intr_sgh2c_status, 0);
			dev_info(dev, "fpdev: H2C interrupted by signal\n");
			free_sg_buf(fpdev, sg_map);
			return -ERESTARTSYS;
		}

		if(ret == 0){
			atomic_set(&fpdev->intr_sgh2c_status, 0);
			dev_info(dev, "fpdev: H2C timed out\n");
			free_sg_buf(fpdev, sg_map);
			return -ETIMEDOUT;
		}
        if (atomic_read(&fpdev->intr_sgh2c_status) != 0x0)
        {
            Link_State = read_reg(fpdev , H2C_SG_LIST_STATUS,0);
            if (Link_State == 0x1) //read sg list done
            {
                atomic_set(&fpdev->intr_sgh2c_status,0);
		    	#ifdef DEBUG
		    	dev_info(dev, "fpdev: read h2c channel sglist done \n");
		    	#endif
		    	write_reg(fpdev, H2C_SG_LIST_STATUS, 0x0, 0);   
                write_reg(fpdev, H2C_SG_LIST_START, 0x2, 0);     
            }

            if (Link_State == 0x2) //read dma data done
            {
				// #ifdef STREAM_DMA
				// pci_unmap_single(sc->dev, dma_addr, BLOCK_DMA_BUF_SIZE, PCI_DMA_TODEVICE);
				// #endif
				#ifdef STREAM_DMA
            	#if LINUX_VERSION_CODE < KERNEL_VERSION(5,0,0)
                pci_unmap_single(fpdev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, PCI_DMA_FROMDEVICE);
            	#else
                dma_unmap_single(&fpdev->dev->dev, dma_addr, BLOCK_DMA_BUF_SIZE, DMA_FROM_DEVICE);
            	#endif
            	#endif
				atomic_set(&fpdev->intr_sgh2c_status,0);
				#ifdef DEBUG
				dev_info(dev, "fpdev: clean h2c intr_sgh2c_status dma done \n");
				#endif
				
				free_sg_buf(fpdev, sg_map);
				write_reg(fpdev, H2C_SG_LIST_STATUS, 0,0);
				return h2c_bufsize;                
            }
        } 
    }
}

int  allocate_sglistdma(struct pci_dev *pdev, struct fpga_pdev *fpdev)
{
	dma_addr_t hw_addr;
	struct device *dev = &pdev->dev;
 
	init_waitqueue_head(&fpdev->c2h_sg_waitq);
	init_waitqueue_head(&fpdev->h2c_sg_waitq);
 
	fpdev->sglist_block_size = SGDMA_LIST_BUFFER_SIZE;
 
	/* allocate C2H buffer */
	fpdev->c2h_sgl_dma_vaddr = dma_alloc_coherent(&pdev->dev,
							fpdev->sglist_block_size,
							&hw_addr,
							GFP_KERNEL);
 
	if (!fpdev->c2h_sgl_dma_vaddr) {
	 	dev_err(dev, "fpdev: allocate c2h dma buffer error\n");
		return -ENOMEM;
	}
 
	fpdev->c2h_sg_dma_hwaddr = hw_addr;
  	dev_info(dev, "fpdev: allocate sglist c2h dma phy addr is [%pad]and dma buffer is[%u] bytes\n",
			&fpdev->c2h_sg_dma_hwaddr, fpdev->sglist_block_size);
	/* allocate H2C buffer */
	fpdev->h2c_sgl_dma_vaddr = dma_alloc_coherent(&pdev->dev,
							fpdev->sglist_block_size,
							&hw_addr,
							GFP_KERNEL);
 
	if (!fpdev->h2c_sgl_dma_vaddr) {
		dev_err(dev, "fpdev: allocate h2c dma buffer error\n");
		return -ENOMEM;
	}
 
	fpdev->h2c_sg_dma_hwaddr = hw_addr;
 
	dev_info(dev, "fpdev: allocate sglist h2c dma phy addr is [%pad]and dma buffer is[%u] bytes\n",
			&fpdev->h2c_sg_dma_hwaddr, fpdev->sglist_block_size);
 
	return 0;
}