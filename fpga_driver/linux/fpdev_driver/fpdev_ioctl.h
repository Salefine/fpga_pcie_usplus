/****************************************************************************
 * @file    fpdev_ioctl.h
 * @brief  
 * @author  weslie (zzhi4832@gmail.com)
 * @version 1.0
 * @date    2025-01-22
 * 
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    weslie        |                        |
 * |---------------|-------------|------------------|------------------------|
 * 
 * @copyright Copyright (c) 2025 welie
 * ***************************************************************************/

#ifndef FPDEV_IOCTL_H_
#define FPDEV_IOCTL_H_

#include "fpdev_mod.h"

#ifdef __cplusplus
extern "C" {
#endif


struct fpga_t
{
	int fd;
	int id;
};
typedef struct fpga_t fpga_t;


fpga_t * fpga_open(int id);

void fpga_close(fpga_t * fpga);
void fpga_reset(fpga_t * fpga);

int fpga_reg_write(fpga_t * fpga,int offset , unsigned int val, int bar_id);
int fpga_reg_read(fpga_t * fpga,int offset , unsigned int *valptr, int bar_id);
int fpga_bl_c2h(fpga_t * fpga, unsigned int * c2h_dw_buffer, unsigned int c2h_dw_bufsize, long long timeout, long long sdram_address);
int fpga_bl_h2c(fpga_t * fpga, unsigned int * h2c_dw_buffer, unsigned int h2c_dw_bufsize, long long timeout, long long sdram_address);
int fpga_sg_c2h(fpga_t * fpga, unsigned int * c2h_dw_buffer, unsigned int c2h_dw_bufsize, long long timeout, long long sdram_address);
int fpga_sg_h2c(fpga_t * fpga, unsigned int * h2c_dw_buffer, unsigned int h2c_dw_bufsize, long long timeout, long long sdram_address);


#ifdef __cplusplus
}
#endif

#endif
