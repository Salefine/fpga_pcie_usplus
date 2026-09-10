/****************************************************************************
 * @file    dma_to_device.c
 * @brief  C2H (device -> host) DMA dump; splits transfers > BLOCK_DMA_BUF_SIZE.
 * @author  weslie (zzhi4832@gmail.com)
 * @version 1.1
 * @date    2025-01-22
 *
 * @par :
 * ___________________________________________________________________________
 * |    Date       |  Version    |       Author     |       Description      |
 * |---------------|-------------|------------------|------------------------|
 * |               |   v1.0      |    weslie        |                        |
 * |               |   v1.1      |    weslie        | multi-chunk > 4MB      |
 * |---------------|-------------|------------------|------------------------|
 *
 * @copyright Copyright (c) 2025 welie
 * ***************************************************************************/

 #include <stdio.h>
 #include <stdlib.h>
 #include <string.h>
 #include <fcntl.h>
 #include <unistd.h>
 #include <sys/stat.h>
 #include <getopt.h>
 #include <time.h>
 
 #include "fpdev_ioctl.h"
 #include "fpdev_mod.h"
 
 #ifndef BLOCK_DMA_BUF_SIZE
 #define BLOCK_DMA_BUF_SIZE (4u * 1024u * 1024u)
 #endif
 
 #define DEV_PATH "/dev/fpga_dma"
 
 static void usage(const char *prog)
 {
     fprintf(stderr,
         "Usage: %s -f <infile> -a <fpga_addr> -s <total_bytes> [-t timeout_ms]\n"
         "\n"
         "Host to FPGA DMA transfer test.\n"
         "\n"
         "Options:\n"
         "  -f    input file\n"
         "  -a    FPGA DDR address\n"
         "  -s    transfer size in bytes\n"
         "  -t    timeout in ms (default: 5000)\n"
         "\n"
         "Large transfers are automatically split into %u-byte DMA blocks.\n",
         prog,
         (unsigned)BLOCK_DMA_BUF_SIZE);
 }
 
 int main(int argc, char **argv)
 {
     char *file_name = NULL;
 
     unsigned long long fpga_addr = 0;
     unsigned int total_size = 0;
     unsigned long long timeout_ms = 5000;
 
     int id = 0;
     int opt;
     int ret;
 
     FILE *fp = NULL;
     struct fpga_t *fpga = NULL;
 
     unsigned char *chunk_buf = NULL;
 
     struct timespec t0, t1;
 
     double elapsed_sec;
     double bandwidth_MBps;
 
     while ((opt = getopt(argc, argv, "f:a:s:t:")) != -1) {
         switch (opt) {
 
         case 'f':
             file_name = optarg;
             break;
 
         case 'a':
             fpga_addr = strtoull(optarg, NULL, 0);
             break;
 
         case 's':
             total_size = strtoul(optarg, NULL, 0);
             break;
 
         case 't':
             timeout_ms = strtoull(optarg, NULL, 0);
             break;
 
         default:
             usage(argv[0]);
             return -1;
         }
     }
 
     if (!file_name || total_size == 0) {
         usage(argv[0]);
         return -1;
     }
 
     fpga = fpga_open(id);
     if (fpga == NULL) {
         fprintf(stderr, "Cannot open FPGA %d (%s)\n", id, DEV_PATH);
         return -1;
     }
 
     fp = fopen(file_name, "rb");
     if (!fp) {
         perror("fopen");
         fpga_close(fpga);
         return -1;
     }
 
     chunk_buf = (unsigned char *)malloc(BLOCK_DMA_BUF_SIZE);
     if (!chunk_buf) {
         fprintf(stderr, "malloc failed\n");
         fclose(fp);
         fpga_close(fpga);
         return -1;
     }
 
     clock_gettime(CLOCK_MONOTONIC, &t0);
 
     for (unsigned long long done = 0; done < total_size; ) {
 
         unsigned int chunk;
 
         if ((total_size - done) > BLOCK_DMA_BUF_SIZE)
             chunk = BLOCK_DMA_BUF_SIZE;
         else
             chunk = total_size - done;
 
         size_t rd = fread(chunk_buf, 1, chunk, fp);
 
         if (rd != chunk) {
             fprintf(stderr,
                     "fread failed at offset %llu, expect=%u actual=%zu\n",
                     done,
                     chunk,
                     rd);
 
             free(chunk_buf);
             fclose(fp);
             fpga_close(fpga);
             return -1;
         }
 
         ret = fpga_bl_h2c(fpga,
                           (unsigned int *)chunk_buf,
                           chunk,
                           (long long)timeout_ms,
                           fpga_addr + done);
 
         if (ret < 0 || (unsigned int)ret != chunk) {
 
             fprintf(stderr,
                     "DMA failed at offset %llu, chunk=%u, ret=%d\n",
                     done,
                     chunk,
                     ret);
 
             free(chunk_buf);
             fclose(fp);
             fpga_close(fpga);
             return -1;
         }
 
         done += chunk;
     }
 
     clock_gettime(CLOCK_MONOTONIC, &t1);
 
     elapsed_sec =
         (t1.tv_sec - t0.tv_sec) +
         (t1.tv_nsec - t0.tv_nsec) / 1e9;
 
     if (elapsed_sec <= 0.0)
         elapsed_sec = 1e-9;
 
     bandwidth_MBps =
         ((double)total_size / (1024.0 * 1024.0)) / elapsed_sec;
 
     free(chunk_buf);
 
     fclose(fp);
 
     fpga_close(fpga);
 
     printf("\n");
     printf("H2C DMA SUCCESS\n");
     printf("File             : %s\n", file_name);
     printf("FPGA Address     : 0x%016llx\n", fpga_addr);
     printf("Transfer Size    : %u bytes\n", total_size);
     printf("DMA Time         : %.6f sec\n", elapsed_sec);
     printf("DMA Bandwidth    : %.2f MB/s\n", bandwidth_MBps);
 
     return 0;
 }