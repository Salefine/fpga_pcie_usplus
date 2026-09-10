/****************************************************************************
 * @file    reg_rw.c
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
#include <string.h>
#include <fcntl.h>
#include<sys/mman.h>
#include<unistd.h>
#include<sys/types.h>
#include<sys/stat.h>
#include <stdlib.h>
#include <signal.h>
#include <pthread.h>
#include "fpdev_ioctl.h"
#include "fpdev_mod.h"
#include <malloc.h>

struct fpga_info
{
    int id;
    unsigned int sendlen;
};

typedef struct fpga_info fpga_info;

int main(int argc , char** argv){
    char option;
    int id_str;
    int  id;
    struct fpga_t * fpga;
    fpga_iodev io;
    int status;
    id = 0;

    option = argv[1][0];

    if (strcmp(argv[1],"r") == 0)
    {
        if (argc < 3)
        {
            printf("Usage: ./reg_rw r bar_id offset \n");
            return -1;
        }
        id_str = atoi(argv[2]);
        if (id_str >= 6)
        {
            printf("bar id is not correct \r\n");
            return -1;
        }
        
        
        fpga = fpga_open(id);

        if (fpga == NULL)
        {
            printf("Can not found FPGA %d \n", id_str);
            return -1;
        }
        io.id = id;
        io.regaddr = strtoul(argv[3], NULL ,0);

        status = fpga_reg_read(fpga, io.regaddr, &(io.regdata) , id_str);
        printf("read bar's reg addr = 0x%x ! data is 0x%x\n",io.regaddr,io.regdata);
        if (status != 0)
        {
            printf("read reg is fail\n");
        }
        fpga_close(fpga);
    }
    else if (strcmp(argv[1],"w") == 0)
    {
        if (argc < 4)
        {
            printf("Usage: ./reg_rw w bar_id offset data\n");
            return -1;
        }      
        id_str = atoi(argv[2]);
        if (id_str >= 6)
        {
            printf("bar id is not correct \r\n");
            return -1;
        }

        fpga = fpga_open(id);
        if (fpga == NULL)
        {
            printf("Can not found FPGA %d \n", id);
            return -1;
        }
        io.id = id;
        io.regaddr = strtoul(argv[3], NULL ,0);
        io.regdata = strtoul(argv[4], NULL, 0);    
        status = fpga_reg_write(fpga, io.regaddr, io.regdata, id_str);    
        printf("write bar's reg addr = 0x%x ! data is 0x%x\n",io.regaddr,io.regdata);
        if (status != 0)
        {
            printf("write reg is fail\n");
        }
        fpga_close(fpga); 
    }
    else {
        printf("The chachter is not correct\r\n");
        return -1;
    }
    
}
