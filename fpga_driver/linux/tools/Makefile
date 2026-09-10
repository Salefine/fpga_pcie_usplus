# ================= Compiler =================
CC = gcc
CFLAGS = -g -I/usr/local/include
LDFLAGS = -L/usr/local/lib -lzzhiDMA -lpthread

# ================= Targets =================
TARGETS = reg_rw dma_from_device dma_to_device sgdma_from_device sgdma_to_device

# ================= Sources =================
SRCS_reg_rw = reg_rw.c
SRCS_dma_from_device = dma_from_device.c
SRCS_dma_to_device = dma_to_device.c
SRCS_sgdma_from_device = sgdma_from_device.c
SRCS_sgdma_to_device = sgdma_to_device.c

OBJS_reg_rw = $(SRCS_reg_rw:.c=.o)
OBJS_dma_from_device = $(SRCS_dma_from_device:.c=.o)
OBJS_dma_to_device = $(SRCS_dma_to_device:.c=.o)
OBJS_sgdma_from_device = $(SRCS_sgdma_from_device:.c=.o)
OBJS_sgdma_to_device = $(SRCS_sgdma_to_device:.c=.o)

# ================= All =================
all: $(TARGETS)

# ================= Build each app =================
reg_rw: $(OBJS_reg_rw)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

dma_from_device: $(OBJS_dma_from_device)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

dma_to_device: $(OBJS_dma_to_device)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

sgdma_from_device: $(OBJS_sgdma_from_device)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

sgdma_to_device: $(OBJS_sgdma_to_device)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

# ================= Compile rule =================
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# ================= Clean =================
clean:
	rm -f *.o $(TARGETS)