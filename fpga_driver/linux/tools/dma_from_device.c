/****************************************************************************
 * @file    dma_from_device.c
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
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
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
		"Usage: %s -f <outfile> -a <fpga_sdram_addr> -s <total_bytes> [-t timeout_ms]\n"
		"  Reads total_bytes from FPGA SDRAM into outfile using block DMA.\n"
		"  Transfers larger than %u bytes are split into multiple DMA operations.\n",
		prog, (unsigned)BLOCK_DMA_BUF_SIZE);
}

int main(int argc, char **argv)
{
	const char *file_name = NULL;
	unsigned long long fpga_addr = 0;
	unsigned long long total_size = 0;
	unsigned long long timeout_ms = 5000;
	int id = 0;
	struct fpga_t *fpga = NULL;
	FILE *fp = NULL;
	unsigned char *chunk_buf = NULL;

	int opt;
	struct timespec t0, t1;
	double elapsed_sec;
	double bandwidth_MBps;

	while ((opt = getopt(argc, argv, "hf:a:s:t:")) != -1) {
		switch (opt) {
		case 'f':
			file_name = optarg;
			break;
		case 'a':
			fpga_addr = strtoull(optarg, NULL, 0);
			break;
		case 's':
			total_size = strtoull(optarg, NULL, 0);
			break;
		case 't':
			timeout_ms = strtoull(optarg, NULL, 0);
			break;
		case 'h':
		default:
			usage(argv[0]);
			return opt == 'h' ? 0 : 1;
		}
	}

	if (!file_name || total_size == 0) {
		usage(argv[0]);
		return 1;
	}

	fpga = fpga_open(id);
	if (fpga == NULL) {
		fprintf(stderr, "Cannot open FPGA %d (%s)\n", id, DEV_PATH);
		return 1;
	}

	fp = fopen(file_name, "wb");
	if (!fp) {
		perror("fopen output file");
		fpga_close(fpga);
		return 1;
	}

	chunk_buf = (unsigned char *)malloc(BLOCK_DMA_BUF_SIZE);
	if (!chunk_buf) {
		fprintf(stderr, "malloc chunk buffer failed\n");
		fclose(fp);
		fpga_close(fpga);
		return 1;
	}

	clock_gettime(CLOCK_MONOTONIC, &t0);

	for (unsigned long long done = 0; done < total_size; ) {
		unsigned int chunk =
		    (unsigned int)((total_size - done > (unsigned long long)BLOCK_DMA_BUF_SIZE)
				       ? (unsigned long long)BLOCK_DMA_BUF_SIZE
				       : (total_size - done));

		memset(chunk_buf, 0, chunk);

		int ret = fpga_bl_c2h(fpga, (unsigned int *)chunk_buf, chunk,
				      (long long)timeout_ms,
				      fpga_addr + done);
		if (ret < 0 || (unsigned int)ret != chunk) {
			fprintf(stderr, "DMA failed at offset %llu (chunk %u), ret=%d\n",
				done, chunk, ret);
			free(chunk_buf);
			fclose(fp);
			fpga_close(fpga);
			return 1;
		}

		if (fwrite(chunk_buf, 1, chunk, fp) != chunk) {
			perror("fwrite");
			free(chunk_buf);
			fclose(fp);
			fpga_close(fpga);
			return 1;
		}

		done += chunk;
	}

	clock_gettime(CLOCK_MONOTONIC, &t1);

	elapsed_sec = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
	if (elapsed_sec <= 0.0)
		elapsed_sec = 1e-9;

	bandwidth_MBps = ((double)total_size / (1024.0 * 1024.0)) / elapsed_sec;

	free(chunk_buf);
	fclose(fp);
	fpga_close(fpga);

	printf("DMA success: %llu bytes written to %s\n",
	       (unsigned long long)total_size, file_name);
	printf("DMA transfer size : %llu bytes\n", (unsigned long long)total_size);
	printf("DMA time          : %.6f sec\n", elapsed_sec);
	printf("DMA bandwidth     : %.2f MB/s\n", bandwidth_MBps);

	return 0;
}
