/****************************************************************************
 * @file    fpga_ctrl.c
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

#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <fcntl.h>
#include "fpdev_ioctl.h"
#include <string.h>


fpga_t * fpga_open(int id) 
{
	fpga_t * fpga;

	// Allocate space for the fpga_dev
	fpga = (fpga_t *)malloc(sizeof(fpga_t));
	if (fpga == NULL)
		return NULL;
	fpga->id = id;	

	// Open the device file.
	fpga->fd = open("/dev/"DEVICE_NAME, O_RDWR | O_SYNC);
	if (fpga->fd < 0) {
		free(fpga); 
		return NULL;
	}
	
	return fpga;
}

void fpga_close(fpga_t * fpga) 
{
	// Close the device file.
	close(fpga->fd);
	free(fpga);
}

int fpga_reg_write(fpga_t * fpga,int offset , unsigned int val, int bar_id){
	fpga_iodev io;
	io.id = fpga->id;
	io.regaddr = offset;
	io.regdata = val;
	io.bar_id = bar_id;
	return ioctl(fpga->fd, IOCTL_WR_REG, &io);
}

int fpga_reg_read(fpga_t * fpga,int offset , unsigned int *valptr, int bar_id){
	fpga_iodev io;
	io.id = fpga->id;
	io.regaddr = offset;
	io.bar_id = bar_id;
	ioctl(fpga->fd, IOCTL_RD_REG, &io);
	*valptr = io.regdata;
	return 0;
}


void fpga_reset(fpga_t * fpga)
{
	printf("fpga_reset: id=%d\n", fpga->id);
}

int fpga_bl_c2h(fpga_t * fpga, unsigned int * c2h_byte_buffer, unsigned int c2h_byte_bufsize, long long timeout, long long sdram_address){
	fpga_iodev io;
	memset(&io, 0, sizeof(io));
	io.id = fpga->id;
	io.timeout = timeout;
	io.c2h_byte_buf = c2h_byte_buffer;
	io.c2h_byte_bufsize = c2h_byte_bufsize;
  io.c2h_sdram_addr = sdram_address;
	return ioctl(fpga->fd, IOCTL_BL_WR, &io);
}

int fpga_bl_h2c(fpga_t * fpga, unsigned int * h2c_byte_buffer, unsigned int h2c_byte_bufsize, long long timeout, long long sdram_address){
	fpga_iodev io;
	memset(&io, 0, sizeof(io));
	io.id = fpga->id;
	io.timeout = timeout;
	io.h2c_byte_buf = h2c_byte_buffer;
	io.h2c_byte_bufsize = h2c_byte_bufsize;
    io.h2c_sdram_addr = sdram_address;
	return ioctl(fpga->fd, IOCTL_BL_RD, &io);
}

int fpga_sg_c2h(fpga_t * fpga, unsigned int * c2h_byte_buffer, unsigned int c2h_byte_bufsize, long long timeout, long long sdram_address){
	fpga_iodev io;
	memset(&io, 0, sizeof(io));
	io.id = fpga->id;
	io.timeout = timeout;
	io.c2h_byte_buf = c2h_byte_buffer;
	io.c2h_byte_bufsize = c2h_byte_bufsize;
    io.c2h_sdram_addr = sdram_address;
	return ioctl(fpga->fd, IOCTL_SG_WR, &io);
}

int fpga_sg_h2c(fpga_t * fpga, unsigned int * h2c_byte_buffer, unsigned int h2c_byte_bufsize, long long timeout, long long sdram_address){
	fpga_iodev io;
	memset(&io, 0, sizeof(io));
	io.id = fpga->id;
	io.timeout = timeout;
	io.h2c_byte_buf = h2c_byte_buffer;
	io.h2c_byte_bufsize = h2c_byte_bufsize;
    io.h2c_sdram_addr = sdram_address;
	return ioctl(fpga->fd, IOCTL_SG_RD, &io);
}