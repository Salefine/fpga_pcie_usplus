/******************************************************************************
 * @file    fpdev_mod.c
 * @brief   PCIe FPGA DMA Linux kernel driver
 * @author  zzhi (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2025-01-22
 *
 * @copyright Copyright (c) 2025 zzhi
 *
 * This driver provides:
 *   1. PCIe device enumeration and BAR mapping
 *   2. MSI interrupt handling
 *   3. Block DMA and SG DMA interfaces
 *   4. Character device interface for user-space applications
 *   5. Register read/write through ioctl
 ******************************************************************************/

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/version.h>
#include <linux/mm.h>
#include <linux/device.h>
#include <linux/err.h>
#include <linux/io.h>
#include <linux/fs.h>
#include <linux/pci.h>
#include <linux/interrupt.h>
#include <linux/sched.h>
#include <linux/atomic.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(4,11,0)
#include <linux/sched/signal.h>
#endif

#include <linux/rwsem.h>
#include <linux/dma-mapping.h>
#include <linux/pagemap.h>
#include <linux/slab.h>
#include <asm/uaccess.h>
#include <asm/div64.h>
#include <asm/io.h>
#include <linux/cdev.h>

#include "fpdev_mod.h"


MODULE_LICENSE("Dual BSD/GPL");
MODULE_DESCRIPTION("PCIe driver for fpga_dma, Linux (2.6.27+)");
MODULE_AUTHOR("zzhi");


/*
 * Global FPGA device table.
 *
 * Each detected FPGA PCIe device is assigned a software ID and stored
 * in this table. The ID is later used by ioctl handlers to locate the
 * corresponding FPGA device.
 */
static struct fpga_pdev *fpga_devices[NUM_FPGAS];

/*
 * Indicates whether an FPGA device ID is currently in use.
 *
 * atomic_t is used because the device ID may be accessed from different
 * execution contexts.
 */
static atomic_t used_fpgas[NUM_FPGAS];


/*
 * Character device information.
 */
static dev_t devt;
static struct cdev fpga_cdev;
static struct class *fpga_class;


/******************************************************************************
 * PCIe BAR Enumeration
 *
 * This function reads the PCI resource information of all six possible BARs.
 * It does not map the BARs; it only prints their address range and flags.
 ******************************************************************************/
static int enumerate_bars(struct fpga_pdev **fpdev,
                          struct pci_dev *pdev)
{
    struct device *dev = &pdev->dev;
    resource_size_t bar_start, bar_end;
    unsigned long bar_flags;
    int i;

    for (i = 0; i < 6; i++) {

        bar_start = pci_resource_start(pdev, i);

        if (bar_start) {
            bar_end = pci_resource_end(pdev, i);
            bar_flags = pci_resource_flags(pdev, i);
        }

        dev_info(dev,
                 "BAR[%d] 0x%08llx-0x%08llx flags 0x%08lx",
                 i,
                 bar_start,
                 bar_end,
                 bar_flags);
    }

    return 0;
}


/******************************************************************************
 * PCIe BAR Mapping
 *
 * Map each valid PCIe BAR into kernel virtual address space.
 *
 * PCIe BAR:
 *     PCIe physical/resource address
 *             |
 *             | pci_ioremap_bar()
 *             v
 *     Kernel virtual address
 *
 * The returned address is used with ioread32()/iowrite32() to access
 * FPGA registers.
 ******************************************************************************/
static int map_bars(struct pci_dev *pdev,
                    struct fpga_pdev *fpdev)
{
    struct device *dev = &pdev->dev;
    int i;

    for (i = 0; i < 6; i++) {

        resource_size_t bar_start = pci_resource_start(pdev, i);
        resource_size_t bar_end   = pci_resource_end(pdev, i);
        resource_size_t bar_len   = bar_end - bar_start + 1;

        fpdev->bar_len[i] = bar_len;

        /*
         * BAR is not implemented or has no valid resource.
         */
        if (!bar_start || !bar_end) {
            fpdev->bar_len[i] = 0;
            continue;
        }

        if (bar_len < 1) {
            dev_info(dev,
                     "fpdev: pcie's bar memory is less than 1 byte");
            continue;
        }

        /*
         * Convert the PCIe BAR resource into a kernel virtual address.
         *
         * The returned pointer must NOT be dereferenced directly.
         * It should only be accessed through MMIO helpers such as
         * ioread32()/iowrite32().
         */
        fpdev->bar[i] = pci_ioremap_bar(pdev, i);

        if (!fpdev->bar[i]) {
            dev_err(dev,
                    "fpdev: Cannot map bar[%d]", i);
            return -ENOMEM;
        }

        dev_info(dev,
                 "fpdev: BAR[%d] mapped at 0x%p, with length %llu",
                 i,
                 fpdev->bar[i],
                 (unsigned long long)bar_len);
    }

    return 0;
}


/******************************************************************************
 * Release PCIe BAR mappings.
 *
 * This function is called during driver removal or probe failure cleanup.
 ******************************************************************************/
static int free_bars(struct pci_dev *pdev,
                     struct fpga_pdev *fpdev)
{
    struct device *dev = &pdev->dev;
    int i;

    for (i = 0; i < 6; i++) {

        if (fpdev->bar[i]) {

            /*
             * Release the kernel virtual mapping created by
             * pci_ioremap_bar().
             */
            pci_iounmap(pdev, fpdev->bar[i]);

            fpdev->bar[i] = NULL;

            dev_info(dev,
                     "fpdev: Unmap bar[%d]", i);
        }
    }

    return 0;
}


/******************************************************************************
 * FPGA Register Write
 *
 * @param fpdev    FPGA device private structure
 * @param offset   Register offset in DWORDs
 * @param wdata    Data to be written
 * @param bar_id   BAR containing the register
 *
 * Actual byte offset:
 *
 *     byte_offset = offset << 2
 *
 * because one register is 32 bits = 4 bytes.
 ******************************************************************************/
void write_reg(struct fpga_pdev **fpdev,
               int offset,
               unsigned int wdata,
               int bar_id)
{
    struct device *dev = &fpdev->dev->dev;

    /*
     * iowrite32() performs a 32-bit MMIO write to the FPGA.
     */
    iowrite32(wdata,
              fpdev->bar[bar_id] + (offset << 2));

    dev_info(dev,
             "fpdev: write register bar[%d] at [%p], data is [0x%x]",
             bar_id,
             fpdev->bar[bar_id],
             wdata);
}


/******************************************************************************
 * FPGA Register Read
 *
 * Read a 32-bit FPGA register through PCIe BAR MMIO.
 ******************************************************************************/
unsigned int read_reg(struct fpga_pdev **fpdev,
                      int offset,
                      int bar_id)
{
    struct device *dev = &fpdev->dev->dev;
    unsigned int rdata;

    /*
     * ioread32() performs a 32-bit MMIO read from the FPGA.
     */
    rdata = ioread32(fpdev->bar[bar_id] + (offset << 2));

    dev_info(dev,
             "fpdev: read register bar[%d] at [%p], data is [0x%x]",
             bar_id,
             fpdev->bar[bar_id],
             rdata);

    return rdata;
}


/******************************************************************************
 * Character Device ioctl Handler
 *
 * User space communicates with the driver through ioctl().
 *
 * ioctl flow:
 *
 *     User application
 *          |
 *          | ioctl()
 *          v
 *     fpga_ioctl()
 *          |
 *          +---- Block H2C
 *          +---- Block C2H
 *          +---- SG H2C
 *          +---- SG C2H
 *          +---- Register Read
 *          +---- Register Write
 *
 * User-space parameters are copied into kernel memory using
 * copy_from_user().
 ******************************************************************************/
static long fpga_ioctl(struct file *filp,
                       unsigned int ioctlnum,
                       unsigned long ioctlparam)
{
    int rc;
    fpga_iodev io;
    struct fpga_pdev *fpdev =
        filp ? filp->private_data : NULL;

    struct device *dev =
        fpdev ? &fpdev->dev->dev : NULL;

    pr_info("fpdev: start fpga_ioctl\n");

    switch (ioctlnum) {

    /*
     * Block DMA: C2H
     *
     * FPGA -> Host
     */
    case IOCTL_BL_WR:

        rc = copy_from_user(&io,
                             (void __user *)ioctlparam,
                             sizeof(fpga_iodev));

        if (rc) {
            dev_err(dev,
                    "fpdev: Cannot get data from user space\n");
            return -EFAULT;
        }

        return block_c2h(fpga_devices[io.id],
                         io.c2h_byte_buf,
                         io.c2h_byte_bufsize,
                         io.timeout,
                         io.c2h_sdram_addr);


    /*
     * Block DMA: H2C
     *
     * Host -> FPGA
     */
    case IOCTL_BL_RD:

        rc = copy_from_user(&io,
                            (void __user *)ioctlparam,
                            sizeof(fpga_iodev));

        if (rc) {
            dev_err(dev,
                    "fpdev: Cannot get data from user space\n");
            return -EFAULT;
        }

        return block_h2c(fpga_devices[io.id],
                         io.h2c_byte_buf,
                         io.h2c_byte_bufsize,
                         io.timeout,
                         io.h2c_sdram_addr);


    /*
     * Scatter-Gather DMA: C2H
     *
     * FPGA -> Host.
     * The SG DMA engine can transfer data from FPGA memory into
     * non-contiguous host memory buffers.
     */
    case IOCTL_SG_WR:

        rc = copy_from_user(&io,
                            (void __user *)ioctlparam,
                            sizeof(fpga_iodev));

        if (rc) {
            dev_err(dev,
                    "fpdev: Cannot get data from user space\n");
            return -EFAULT;
        }

        return sg_c2h(fpga_devices[io.id],
                      io.c2h_byte_buf,
                      io.c2h_byte_bufsize,
                      io.timeout,
                      io.c2h_sdram_addr);


    /*
     * Scatter-Gather DMA: H2C
     *
     * Host -> FPGA.
     */
    case IOCTL_SG_RD:

        rc = copy_from_user(&io,
                            (void __user *)ioctlparam,
                            sizeof(fpga_iodev));

        if (rc) {
            dev_err(dev,
                    "fpdev: Cannot get data from user space\n");
            return -EFAULT;
        }

        return sg_h2c(fpga_devices[io.id],
                      io.h2c_byte_buf,
                      io.h2c_byte_bufsize,
                      io.timeout,
                      io.h2c_sdram_addr);


    /*
     * FPGA register write.
     */
    case IOCTL_WR_REG:

        rc = copy_from_user(&io,
                            (void __user *)ioctlparam,
                            sizeof(fpga_iodev));

        if (rc) {
            dev_err(dev,
                    "fpdev: cannot read ioctl user parameter.\n");
            return -EFAULT;
        }

        write_reg(fpga_devices[io.id],
                  io.regaddr,
                  io.regdata,
                  io.bar_id);

        return 0;


    /*
     * FPGA register read.
     *
     * The read value is copied back to user space using
     * copy_to_user().
     */
    case IOCTL_RD_REG:

        rc = copy_from_user(&io,
                            (void __user *)ioctlparam,
                            sizeof(fpga_iodev));

        if (rc) {
            dev_err(dev,
                    "fpdev: cannot read ioctl user parameter.\n");
            return -EFAULT;
        }

        io.regdata = read_reg(fpga_devices[io.id],
                              io.regaddr,
                              io.bar_id);

        rc = copy_to_user((void __user *)ioctlparam,
                          &io,
                          sizeof(fpga_iodev));

        if (rc) {
            dev_err(dev,
                    "fpdev: cannot writeback register data.\n");
            return -EFAULT;
        }

        return 0;
    }

    return 0;
}


/*
 * Character device file operations.
 *
 * Currently this driver exposes ioctl() as the main user-space interface.
 */
static const struct file_operations fpga_fops = {
    .owner = THIS_MODULE,
    .unlocked_ioctl = fpga_ioctl,
};


/******************************************************************************
 * Interrupt Status Processing
 *
 * The FPGA DMA engine reports completion/error status through registers.
 * The interrupt handler reads those registers and wakes the corresponding
 * wait queue.
 *
 * IRQ context should do as little work as possible. Therefore, the handler
 * mainly:
 *
 *     1. Read DMA status
 *     2. Store status atomically
 *     3. Wake up waiting processes
 ******************************************************************************/
static inline void process_irq(struct fpga_pdev *fpdev,
                               unsigned int c2h_intr_status,
                               unsigned int h2c_intr_status,
                               unsigned int sg_c2h_status,
                               unsigned int sg_h2c_status)
{
    pr_info("c2h_intr_status is %u, h2c inter status is %u\n",
            c2h_intr_status,
            h2c_intr_status);

    /*
     * Save the latest interrupt status.
     */
    atomic_set(&fpdev->intr_c2h_status,
               c2h_intr_status);

    atomic_set(&fpdev->intr_h2c_status,
               h2c_intr_status);

    atomic_set(&fpdev->intr_sgc2h_status,
               sg_c2h_status);

    atomic_set(&fpdev->intr_sgh2c_status,
               sg_h2c_status);


    /*
     * Wake up processes waiting for block C2H DMA completion.
     */
    if (c2h_intr_status == 0x01) {

        dev_info(&fpdev->dev->dev,
                 "wake up block dma c2h wait queue\n");

        wake_up(&fpdev->c2h_bl_waitq);
    }


    /*
     * Wake up processes waiting for block H2C DMA completion.
     */
    if (h2c_intr_status == 0x01) {

        dev_info(&fpdev->dev->dev,
                 "wake up block dma h2c wait queue\n");

        wake_up(&fpdev->h2c_bl_waitq);
    }


    /*
     * SG C2H status:
     *
     * 0x01 / 0x02 are treated as completion or error conditions
     * according to the FPGA DMA status definition.
     */
    if ((sg_c2h_status == 0x01) ||
        (sg_c2h_status == 0x02)) {

        dev_info(&fpdev->dev->dev,
                 "wake up sg dma c2h wait queue [%x]\n",
                 sg_c2h_status);

        wake_up(&fpdev->c2h_sg_waitq);
    }


    /*
     * SG H2C status.
     */
    if ((sg_h2c_status == 0x01) ||
        (sg_h2c_status == 0x02)) {

        dev_info(&fpdev->dev->dev,
                 "wake up sg dma h2c wait queue [%x]\n",
                 sg_h2c_status);

        wake_up(&fpdev->h2c_sg_waitq);
    }
}


/******************************************************************************
 * PCIe MSI Interrupt Handler
 *
 * The FPGA generates an MSI interrupt when a DMA operation reaches a
 * corresponding completion/status condition.
 *
 * Interrupt flow:
 *
 *     FPGA DMA engine
 *           |
 *           | MSI
 *           v
 *     fpga_irq_handler()
 *           |
 *           +--> read C2H status
 *           +--> read H2C status
 *           +--> read SG C2H status
 *           +--> read SG H2C status
 *           |
 *           v
 *     process_irq()
 *           |
 *           v
 *     wake_up()
 *           |
 *           v
 *     blocked user process continues
 ******************************************************************************/
static irqreturn_t fpga_irq_handler(int irq, void *dev_id)
{
    unsigned int bl_c2h_status;
    unsigned int bl_h2c_status;
    unsigned int sglist_c2h_status;
    unsigned int sglist_h2c_status;

    struct fpga_pdev *fpdev;

    fpdev = (struct fpga_pdev *)dev_id;

    if (fpdev == NULL)
        return IRQ_NONE;

    dev_info(&fpdev->dev->dev,
             "fpdev: irq[%d] triggered\n",
             irq);


    /*
     * Read DMA status registers from FPGA through BAR0.
     */
    bl_c2h_status =
        read_reg(fpdev,
                 C2H_BLOCK_DMA_STATUS,
                 0);

    dev_info(&fpdev->dev->dev,
             "fpdev: bl_c2h_status[%x]\n",
             bl_c2h_status);


    bl_h2c_status =
        read_reg(fpdev,
                 H2C_BLOCK_DMA_STATUS,
                 0);

    dev_info(&fpdev->dev->dev,
             "fpdev: bl_h2c_status[%x]\n",
             bl_h2c_status);


    sglist_c2h_status =
        read_reg(fpdev,
                 C2H_SG_LIST_STATUS,
                 0);

    dev_info(&fpdev->dev->dev,
             "fpdev: sglist_c2h_status[%x]\n",
             sglist_c2h_status);


    sglist_h2c_status =
        read_reg(fpdev,
                 H2C_SG_LIST_STATUS,
                 0);

    dev_info(&fpdev->dev->dev,
             "fpdev: sglist_h2c_status[%x]\n",
             sglist_h2c_status);


    /*
     * Process all DMA interrupt sources.
     */
    process_irq(fpdev,
                bl_c2h_status,
                bl_h2c_status,
                sglist_c2h_status,
                sglist_h2c_status);

    return IRQ_HANDLED;
}


/******************************************************************************
 * PCIe Probe Function
 *
 * Called by the PCI core when a matching FPGA PCIe device is detected.
 *
 * Initialization sequence:
 *
 *     1. Enable PCI device
 *     2. Enable PCI bus mastering
 *     3. Configure DMA address mask
 *     4. Allocate driver private structure
 *     5. Request PCI BAR regions
 *     6. Map BARs
 *     7. Allocate MSI interrupt vector
 *     8. Register interrupt handler
 *     9. Initialize DMA engines
 *    10. Register character device
 *    11. Store driver private data
 ******************************************************************************/
static int fpga_probe(struct pci_dev *pdev,
                      const struct pci_device_id *id)
{
    struct device *dev = &pdev->dev;
    struct fpga_pdev *fpdev;

    int error;
    int ret;
    int vec_cnt;
    int irq_tmp;
    int i;

    dev_info(dev,
             "fpdev: Start pcie dma probe\n");

    dev_info(dev,
             DRIVER_NAME " probe");

    dev_info(dev,
             " Vendor: 0x%04x",
             pdev->vendor);

    dev_info(dev,
             " Device: 0x%04x",
             pdev->device);

    dev_info(dev,
             " Subsystem vendor: 0x%04x",
             pdev->subsystem_vendor);

    dev_info(dev,
             " Subsystem device: 0x%04x",
             pdev->subsystem_device);

    dev_info(dev,
             " Class: 0x%06x",
             pdev->class);


    /*
     * Print PCI bus/device/function information.
     */
    dev_info(dev,
             " PCI ID: %04x:%02x:%02x.%d",
             pci_domain_nr(pdev->bus),
             pdev->bus->number,
             PCI_SLOT(pdev->devfn),
             PCI_FUNC(pdev->devfn));


    /**************************************************************************
     * 1. Enable PCI device
     **************************************************************************/
    error = pci_enable_device(pdev);

    if (error < 0) {

        dev_err(dev,
                "fpdev: pci_enable_device failed with error %d\n",
                error);

        return -ENODEV;
    }

    /*
     * Enable PCI bus mastering.
     *
     * Without bus mastering, the FPGA cannot initiate PCIe DMA transactions.
     */
    pci_set_master(pdev);


    /**************************************************************************
     * 2. Configure DMA address mask
     *
     * The driver requests a 64-bit DMA address space.
     **************************************************************************/
    error = dma_set_mask(&pdev->dev,
                         DMA_BIT_MASK(64));

    if (!error)
        error = dma_set_coherent_mask(&pdev->dev,
                                      DMA_BIT_MASK(64));

    if (error) {

        dev_err(dev,
                "fpdev: dma_set_coherent_mask failed with error %d\n",
                error);

        goto fail_disable_device;
    }


    /*
     * Allow the DMA mapping layer to merge adjacent physical pages into
     * larger DMA segments.
     *
     * Here the maximum DMA segment size is configured to 4 MB.
     */
    dma_set_max_seg_size(&pdev->dev,
                         4u * 1024u * 1024u);


    /**************************************************************************
     * 3. Allocate driver private data
     **************************************************************************/
    fpdev = kzalloc(sizeof(struct fpga_pdev),
                    GFP_KERNEL);

    if (!fpdev) {

        dev_err(dev,
                "fpdev: kzalloc failed\n");

        error = -ENOMEM;

        goto fail_disable_device;
    }

    fpdev->dev = pdev;

    snprintf(fpdev->name,
             sizeof(fpdev->name),
             "fpga_pdev%d",
             pdev->devfn);

    fpdev->vendor_id = pdev->vendor;
    fpdev->device_id = pdev->device;

    dev_info(dev,
             "fpdev: Found FPGA device: %s",
             fpdev->name);

    dev_info(dev,
             "fpdev: Vendor: 0x%04x, Device: 0x%04x",
             fpdev->vendor_id,
             fpdev->device_id);


    /**************************************************************************
     * 4. Request PCI BAR regions
     *
     * This reserves the BAR address space for this driver.
     **************************************************************************/
    error = pci_request_regions(pdev,
                                fpdev->name);

    if (error < 0) {

        dev_err(dev,
                "fpdev: pci_request_regions failed with error %d\n",
                error);

        goto fail_free_fpdev;
    }


    /*
     * Display BAR resource information.
     */
    enumerate_bars(fpdev, pdev);


    /*
     * Map all valid BARs into kernel virtual address space.
     */
    ret = map_bars(pdev, fpdev);

    if (ret < 0) {

        dev_err(dev,
                "fpdev: map_bars failed with error %d\n",
                ret);

        goto fail_release_regions;
    }


    /**************************************************************************
     * 5. Setup MSI interrupt
     **************************************************************************/

    /*
     * Query the number of MSI vectors supported by the device.
     */
    vec_cnt = pci_msi_vec_count(pdev);

    if (vec_cnt < 0) {

        dev_err(dev,
                "fpdev: pci_msi_vec_count failed with error %d\n",
                vec_cnt);

        goto fail_release_regions;
    }


#if LINUX_VERSION_CODE >= KERNEL_VERSION(4,11,0)

    /*
     * Allocate one MSI interrupt vector.
     */
    error = pci_alloc_irq_vectors(pdev,
                                  1,
                                  1,
                                  PCI_IRQ_MSI);

    dev_info(dev,
             "fpdev: allocate %d irq start0\n",
             error);

#else

    error = pci_enable_msi_range(pdev, 1, 1);

    dev_info(dev,
             "fpdev: allocate %d irq start1\n",
             error);

#endif

    if (error < 0)
        goto fail_irq;


    /**************************************************************************
     * 6. Register interrupt handler
     **************************************************************************/

    /*
     * Get the Linux IRQ number corresponding to MSI vector 0.
     */
    irq_tmp = pci_irq_vector(pdev, 0);

    /*
     * Register the ISR.
     *
     * fpdev is passed as dev_id and will be returned to the ISR when
     * an interrupt occurs.
     */
    error = request_irq(irq_tmp,
                        fpga_irq_handler,
                        0,
                        fpdev->name,
                        fpdev);

    if (error < 0)
        goto fail_irq_vectors;


    /**************************************************************************
     * 7. Initialize DMA engines
     *
     * Allocate and initialize the resources required by block DMA and
     * scatter-gather DMA.
     **************************************************************************/
    ret = allocate_blockdma(pdev, fpdev);

    if (ret < 0) {

        dev_err(dev,
                "fpdev: allocate_blockdma failed with error %d\n",
                ret);

        goto fail_irq_vectors;
    }


    ret = allocate_sglistdma(pdev, fpdev);

    if (ret < 0) {

        dev_err(dev,
                "fpdev: allocate_sgdma failed with error %d\n",
                ret);

        goto fail_irq_vectors;
    }


    /**************************************************************************
     * 8. Register character device
     *
     * This exposes /dev/<DEVICE_NAME> to user space.
     **************************************************************************/

    /*
     * Allocate a major/minor device number.
     */
    error = alloc_chrdev_region(&devt,
                                0,
                                NUM_FPGAS,
                                DEVICE_NAME);

    if (error < 0) {

        dev_info(dev,
                 "register_chrdev failed\n");

        goto fail_irq_vectors;
    }


    /*
     * Initialize character device and associate file operations.
     */
    cdev_init(&fpga_cdev,
              &fpga_fops);


    /*
     * Add character device to the kernel.
     */
    ret = cdev_add(&fpga_cdev,
                   devt,
                   1);

    if (ret) {

        dev_err(dev,
                "cdev_add failed with error %d\n",
                ret);

        goto fail_alloc_chr;
    }


    /*
     * Create device class.
     *
     * The class is used by udev to create the device node automatically.
     */
    fpga_class = class_create(THIS_MODULE,
                              DEVICE_NAME);

    if (IS_ERR(fpga_class)) {

        ret = PTR_ERR(fpga_class);

        dev_err(dev,
                "class_create failed with error %d\n",
                ret);

        cdev_del(&fpga_cdev);

        goto fail_alloc_chr;
    }


    /*
     * Create /dev/DEVICE_NAME.
     */
    if (device_create(fpga_class,
                      NULL,
                      devt,
                      NULL,
                      DEVICE_NAME) == NULL) {

        dev_err(dev,
                "device_create failed\n");

        class_destroy(fpga_class);
        cdev_del(&fpga_cdev);

        goto fail_alloc_chr;
    }


    dev_info(dev,
             "fpdev: FPGA device %s registered successfully\n",
             fpdev->name);


    /**************************************************************************
     * 9. Save driver private data
     **************************************************************************/

    /*
     * Associate fpdev with the PCI device.
     *
     * Later, fpga_remove() can retrieve it using pci_get_drvdata().
     */
    pci_set_drvdata(pdev,
                    fpdev);

    fpdev->dev = pdev;


    /*
     * Allocate a software FPGA ID.
     */
    fpdev->id = -1;

    for (i = 0; i < NUM_FPGAS; i++) {

        /*
         * Atomically test and claim an unused FPGA ID.
         */
        if (!atomic_xchg(&used_fpgas[i], 1)) {

            fpdev->id = i;
            fpga_devices[i] = fpdev;

            break;
        }
    }


    if (fpdev->id == -1) {

        dev_err(dev,
                "fpdev: No available FPGA device ID\n");
    }
    else {

        dev_info(dev,
                 "fpdev: FPGA device ID %d assigned\n",
                 fpdev->id);
    }


    return 0;


/******************************************************************************
 * Probe error handling
 *
 * Every resource allocated during probe must be released in reverse order.
 ******************************************************************************/

fail_disable_device:

    pci_disable_device(pdev);

    return error;


fail_free_fpdev:

    kfree(fpdev);

    pci_disable_device(pdev);

    return error;


fail_release_regions:

    free_bars(pdev, fpdev);

    pci_release_regions(pdev);

    kfree(fpdev);

    pci_disable_device(pdev);

    return error;


fail_irq:

#if LINUX_VERSION_CODE >= KERNEL_VERSION(4,11,0)
    pci_free_irq_vectors(pdev);
#else
    pci_disable_msi(pdev);
#endif

    free_bars(pdev, fpdev);
    pci_release_regions(pdev);
    kfree(fpdev);
    pci_disable_device(pdev);

    return error;


fail_irq_vectors:

    pci_free_irq_vectors(pdev);

    free_bars(pdev, fpdev);
    pci_release_regions(pdev);
    kfree(fpdev);
    pci_disable_device(pdev);

    return error;


fail_alloc_chr:

    unregister_chrdev_region(devt,
                             NUM_FPGAS);

    pci_free_irq_vectors(pdev);

    free_bars(pdev, fpdev);

    pci_release_regions(pdev);

    kfree(fpdev);

    pci_disable_device(pdev);

    return error;
}


/******************************************************************************
 * PCIe Device Remove
 *
 * Called when:
 *
 *     - Driver is unloaded
 *     - PCIe device is removed
 *     - Driver is unbound from the device
 *
 * All resources allocated by fpga_probe() must be released here.
 ******************************************************************************/
static void fpga_remove(struct pci_dev *pdev)
{
    struct device *dev = &pdev->dev;
    struct fpga_pdev *fpdev;

    dev_info(dev,
             "fpdev: Start remove pci driver\n");


    /*
     * Retrieve driver private data stored by pci_set_drvdata().
     */
    fpdev = pci_get_drvdata(pdev);

    if (fpdev != NULL) {

        pci_set_drvdata(pdev, NULL);


        /*
         * Release the FPGA software ID.
         */
        if (fpdev->id >= 0 &&
            fpdev->id < NUM_FPGAS) {

            atomic_set(&used_fpgas[fpdev->id], 0);

            fpga_devices[fpdev->id] = NULL;
        }


        /*
         * Release interrupt resources.
         */
        free_irq(pdev->irq, fpdev);

        pci_free_irq_vectors(pdev);


        /*
         * Disable MSI.
         */
        pci_disable_msi(pdev);


        /*
         * Unmap BARs and release PCI regions.
         */
        free_bars(pdev, fpdev);

        pci_release_regions(pdev);


        /*
         * Release driver private memory.
         */
        kfree(fpdev);


        /*
         * Disable PCI device.
         */
        pci_disable_device(pdev);


        /*
         * Remove character device from user space.
         */
        device_destroy(fpga_class,
                        devt);

        class_destroy(fpga_class);

        cdev_del(&fpga_cdev);

        unregister_chrdev_region(devt,
                                 NUM_FPGAS);

        dev_info(dev,
                 "fpdev: FPGA device removed successfully\n");
    }
}


/******************************************************************************
 * PCI Driver Definition
 *
 * The PCI core uses this structure to connect the driver's probe/remove
 * callbacks with the corresponding FPGA PCIe device.
 ******************************************************************************