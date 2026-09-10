/****************************************************************************
 * @file    pci_ids.h
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



#ifndef _PCI_IDS_H_
#define _PCI_IDS_H_

#include <linux/module.h>
#include <linux/pci.h>

static const struct pci_device_id fpdev_ids[] = {
    /** Gen 1 PF */
    /** PCIe lane width x1 */
    { PCI_DEVICE(0x10ee, 0x9011), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9111), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9211), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9311), },	/** PF 3 */
    /** PCIe lane width x2 */
    { PCI_DEVICE(0x10ee, 0x9012), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9112), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9212), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9312), },	/** PF 3 */
    /** PCIe lane width x4 */
    { PCI_DEVICE(0x10ee, 0x9014), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9114), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9214), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9314), },	/** PF 3 */
    /** PCIe lane width x8 */
    { PCI_DEVICE(0x10ee, 0x9018), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9118), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9218), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9318), },	/** PF 3 */
    /** PCIe lane width x16 */
    { PCI_DEVICE(0x10ee, 0x901f), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x911f), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x921f), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x931f), },	/** PF 3 */

    /** Gen 2 PF */
    /** PCIe lane width x1 */
    { PCI_DEVICE(0x10ee, 0x9021), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9121), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9221), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9321), },	/** PF 3 */
    /** PCIe lane width x2 */
    { PCI_DEVICE(0x10ee, 0x9022), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9122), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9222), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9322), },	/** PF 3 */
    /** PCIe lane width x4 */
    { PCI_DEVICE(0x10ee, 0x9024), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9124), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9224), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9324), },	/** PF 3 */
    /** PCIe lane width x8 */
    { PCI_DEVICE(0x10ee, 0x9028), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9128), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9228), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9328), },	/** PF 3 */
    /** PCIe lane width x16 */
    { PCI_DEVICE(0x10ee, 0x902f), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x912f), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x922f), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x932f), },	/** PF 3 */

    /** Gen 3 PF */
    /** PCIe lane width x1 */
    { PCI_DEVICE(0x10ee, 0x9031), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9131), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9231), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9331), },	/** PF 3 */
    /** PCIe lane width x2 */
    { PCI_DEVICE(0x10ee, 0x9032), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9132), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9232), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9332), },	/** PF 3 */
    /** PCIe lane width x4 */
    { PCI_DEVICE(0x10ee, 0x9034), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9134), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9234), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9334), },	/** PF 3 */
    /** PCIe lane width x8 */
    { PCI_DEVICE(0x10ee, 0x9038), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9138), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9238), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9338), },	/** PF 3 */
    /** PCIe lane width x16 */
    { PCI_DEVICE(0x10ee, 0x903f), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x913f), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x923f), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x933f), },	/** PF 3 */
    /* { PCI_DEVICE(0x10ee, 0x6a9f), }, */       /** PF 0 */
    { PCI_DEVICE(0x10ee, 0x6aa0), },	/** PF 1 */

    /** Gen 4 PF */
    /** PCIe lane width x1 */
    { PCI_DEVICE(0x10ee, 0x9041), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9141), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9241), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9341), },	/** PF 3 */
    /** PCIe lane width x2 */
    { PCI_DEVICE(0x10ee, 0x9042), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9142), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9242), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9342), },	/** PF 3 */
    /** PCIe lane width x4 */
    { PCI_DEVICE(0x10ee, 0x9044), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9144), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9244), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9344), },	/** PF 3 */
    /** PCIe lane width x8 */
    { PCI_DEVICE(0x10ee, 0x9048), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0x9148), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0x9248), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0x9348), },	/** PF 3 */

    /** Gen 1 PF */
    /** PCIe lane width x1 */
    { PCI_DEVICE(0x10ee, 0xb011), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb111), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb211), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb311), },	/** PF 3 */
    /** PCIe lane width x2 */
    { PCI_DEVICE(0x10ee, 0xb012), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb112), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb212), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb312), },	/** PF 3 */
    /** PCIe lane width x4 */
    { PCI_DEVICE(0x10ee, 0xb014), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb114), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb214), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb314), },	/** PF 3 */
    /** PCIe lane width x8 */
    { PCI_DEVICE(0x10ee, 0xb018), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb118), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb218), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb318), },	/** PF 3 */
    /** PCIe lane width x16 */
    { PCI_DEVICE(0x10ee, 0xb01f), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb11f), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb21f), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb31f), },	/** PF 3 */
    
    /** Gen 2 PF */
    /** PCIe lane width x1 */
    { PCI_DEVICE(0x10ee, 0xb021), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb121), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb221), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb321), },	/** PF 3 */
    /** PCIe lane width x2 */
    { PCI_DEVICE(0x10ee, 0xb022), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb122), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb222), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb322), },	/** PF 3 */
    /** PCIe lane width x4 */
    { PCI_DEVICE(0x10ee, 0xb024), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb124), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb224), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb324), },	/** PF 3 */
    /** PCIe lane width x8 */
    { PCI_DEVICE(0x10ee, 0xb028), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb128), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb228), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb328), },	/** PF 3 */
    /** PCIe lane width x16 */
    { PCI_DEVICE(0x10ee, 0xb02f), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb12f), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb22f), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb32f), },	/** PF 3 */
    /** Gen 3 PF */
    /** PCIe lane width x1 */
    { PCI_DEVICE(0x10ee, 0xb031), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb131), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb231), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb331), },	/** PF 3 */
    /** PCIe lane width x2 */
    { PCI_DEVICE(0x10ee, 0xb032), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb132), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb232), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb332), },	/** PF 3 */
    /** PCIe lane width x4 */
    { PCI_DEVICE(0x10ee, 0xb034), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb134), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb234), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb334), },	/** PF 3 */
    /** PCIe lane width x8 */
    { PCI_DEVICE(0x10ee, 0xb038), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb138), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb238), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb338), },	/** PF 3 */
    /** PCIe lane width x16 */
    { PCI_DEVICE(0x10ee, 0xb03f), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb13f), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb23f), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb33f), },	/** PF 3 */
    /** Gen 4 PF */
    /** PCIe lane width x1 */
    { PCI_DEVICE(0x10ee, 0xb041), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb141), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb241), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb341), },	/** PF 3 */
    /** PCIe lane width x2 */
    { PCI_DEVICE(0x10ee, 0xb042), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb142), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb242), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb342), },	/** PF 3 */
    /** PCIe lane width x4 */
    { PCI_DEVICE(0x10ee, 0xb044), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb144), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb244), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb344), },	/** PF 3 */
    /** PCIe lane width x8 */
    { PCI_DEVICE(0x10ee, 0xb048), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb148), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb248), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb348), },	/** PF 3 */
    /** Gen 5 PF */
    /** PCIe lane width x8 */
    { PCI_DEVICE(0x10ee, 0xb058), },	/** PF 0 */
    { PCI_DEVICE(0x10ee, 0xb158), },	/** PF 1 */
    { PCI_DEVICE(0x10ee, 0xb258), },	/** PF 2 */
    { PCI_DEVICE(0x10ee, 0xb358), },	/** PF 3 */
    { 0, }
};

//MODULE_DEVICE_TABLE(pci, fpdev_ids);

#endif
