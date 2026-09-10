#!/usr/bin/env python3
import struct

OUTPUT_FILE = "datafile_4MB.bin"
FILE_SIZE = 4 * 1024 * 1024   # 4MB
INT_SIZE = 4                  # int32 = 4 bytes

count = FILE_SIZE // INT_SIZE  # 一共写多少个 int

def main():
    with open(OUTPUT_FILE, "wb") as f:
        for i in range(count):
            # 32-bit unsigned int, little endian
            f.write(struct.pack("<I", i))

    print(f"Generated {OUTPUT_FILE}")
    print(f"Total ints: {count}")
    print(f"File size: {FILE_SIZE} bytes")

if __name__ == "__main__":
    main()