#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys


FMT_TYPE_MAP = {

    (0b000, 0b00000): "MRd32",
    (0b001, 0b00000): "MRd64",

    (0b010, 0b00000): "MWr32",
    (0b011, 0b00000): "MWr64",

    (0b000, 0b01010): "Cpl",
    (0b010, 0b01010): "CplD",
}


STATUS_MAP = {
    0b000: "SC (Successful Completion)",
    0b001: "UR (Unsupported Request)",
    0b010: "CRS (Configuration Retry Status)",
    0b100: "CA (Completer Abort)"
}


def get_bits(value, high, low):
    mask = (1 << (high - low + 1)) - 1
    return (value >> low) & mask


def hex_to_dw_list(hex_str):

    hex_str = hex_str.lower()
    hex_str = hex_str.replace("0x", "")
    hex_str = hex_str.replace("_", "")
    hex_str = hex_str.replace(" ", "")

    if len(hex_str) % 8 != 0:
        raise ValueError(
            "hex string length must be multiple of 8")

    dw_list = []

    for i in range(0, len(hex_str), 8):
        dw = int(hex_str[i:i + 8], 16)
        dw_list.append(dw)

    return dw_list


def dump_raw_dw(dw):

    print("\nRaw DW")
    print("-" * 72)

    for i, x in enumerate(dw):
        print(f"DW{i:<2}: 0x{x:08X}")


def decode_common_header(dw0):

    info = {}

    info["fmt"] = get_bits(dw0, 31, 29)
    info["type"] = get_bits(dw0, 28, 24)

    info["tc"] = get_bits(dw0, 22, 20)
    info["attr"] = get_bits(dw0, 13, 12)

    info["th"] = get_bits(dw0, 16, 16)
    info["td"] = get_bits(dw0, 15, 15)
    info["ep"] = get_bits(dw0, 14, 14)

    info["length"] = get_bits(dw0, 9, 0)

    return info


def print_common_header(info):

    print("\nCommon Header")
    print("-" * 72)

    print(f"{'FMT':24}: {info['fmt']:#05b}")
    print(f"{'TYPE':24}: {info['type']:#07b}")
    print(f"{'TC':24}: {info['tc']}")
    print(f"{'ATTR':24}: {info['attr']}")
    print(f"{'TH':24}: {info['th']}")
    print(f"{'TD':24}: {info['td']}")
    print(f"{'EP':24}: {info['ep']}")
    print(f"{'Length (DW)':24}: {info['length']}")


def parse_mrd(dw):

    hdr = decode_common_header(dw[0])

    requester_id = get_bits(dw[1], 31, 16)
    tag = get_bits(dw[1], 15, 8)

    last_be = get_bits(dw[1], 7, 4)
    first_be = get_bits(dw[1], 3, 0)

    if hdr["fmt"] == 0b000:

        tlp_name = "MRd32"

        addr = get_bits(dw[2], 31, 2) << 2

        header_dw = 3

    else:

        tlp_name = "MRd64"

        addr_hi = dw[2]
        addr_lo = get_bits(dw[3], 31, 2) << 2

        addr = (addr_hi << 32) | addr_lo

        header_dw = 4

    print("=" * 72)
    print(tlp_name)
    print("=" * 72)

    dump_raw_dw(dw)

    print_common_header(hdr)

    print("\nRequest Header")
    print("-" * 72)

    print(f"{'Requester ID':24}: 0x{requester_id:04X}")
    print(f"{'Tag':24}: 0x{tag:02X}")
    print(f"{'First DW BE':24}: 0x{first_be:X}")
    print(f"{'Last DW BE':24}: 0x{last_be:X}")
    print(f"{'Address':24}: 0x{addr:016X}")

    print("=" * 72)


def parse_mwr(dw):

    hdr = decode_common_header(dw[0])

    requester_id = get_bits(dw[1], 31, 16)
    tag = get_bits(dw[1], 15, 8)

    last_be = get_bits(dw[1], 7, 4)
    first_be = get_bits(dw[1], 3, 0)

    if hdr["fmt"] == 0b010:

        tlp_name = "MWr32"

        addr = get_bits(dw[2], 31, 2) << 2

        payload_start = 3

    else:

        tlp_name = "MWr64"

        addr_hi = dw[2]
        addr_lo = get_bits(dw[3], 31, 2) << 2

        addr = (addr_hi << 32) | addr_lo

        payload_start = 4

    payload = dw[payload_start:]

    print("=" * 72)
    print(tlp_name)
    print("=" * 72)

    dump_raw_dw(dw)

    print_common_header(hdr)

    print("\nRequest Header")
    print("-" * 72)

    print(f"{'Requester ID':24}: 0x{requester_id:04X}")
    print(f"{'Tag':24}: 0x{tag:02X}")
    print(f"{'First DW BE':24}: 0x{first_be:X}")
    print(f"{'Last DW BE':24}: 0x{last_be:X}")
    print(f"{'Address':24}: 0x{addr:016X}")

    print()

    print("Payload")
    print("-" * 72)

    for i, data in enumerate(payload):
        print(f"DW{i:<2}: 0x{data:08X}")

    expected_dw = hdr["length"]

    if len(payload) != expected_dw:
        print()
        print("WARNING:")
        print(
            f"Length field={expected_dw} DW, "
            f"Payload={len(payload)} DW")

    print("=" * 72)


def parse_completion(dw):

    hdr = decode_common_header(dw[0])

    tlp_name = FMT_TYPE_MAP.get(
        (hdr["fmt"], hdr["type"]),
        "Completion"
    )

    dw1 = dw[1]
    dw2 = dw[2]

    completer_id = get_bits(dw1, 31, 16)

    status = get_bits(dw1, 15, 13)

    bcm = get_bits(dw1, 12, 12)

    byte_count = get_bits(dw1, 11, 0)

    requester_id = get_bits(dw2, 31, 16)

    tag = get_bits(dw2, 15, 8)

    lower_addr = get_bits(dw2, 6, 0)

    payload_bytes = hdr["length"] * 4

    last_completion = byte_count <= payload_bytes

    print("=" * 72)
    print(tlp_name)
    print("=" * 72)

    dump_raw_dw(dw)

    print_common_header(hdr)

    print("\nCompletion Header")
    print("-" * 72)

    print(f"{'Completer ID':24}: 0x{completer_id:04X}")

    print(
        f"{'Completion Status':24}: "
        f"{STATUS_MAP.get(status,'UNKNOWN')}"
    )

    print(f"{'BCM':24}: {bcm}")

    print(f"{'Byte Count':24}: {byte_count}")

    print()

    print(f"{'Requester ID':24}: 0x{requester_id:04X}")
    print(f"{'Tag':24}: 0x{tag:02X}")
    print(f"{'Lower Address':24}: 0x{lower_addr:02X}")

    print()

    print(f"{'Payload Bytes':24}: {payload_bytes}")
    print(f"{'Last Completion':24}: {last_completion}")

    if hdr["fmt"] == 0b010:

        payload = dw[3:]

        print()

        print("Payload")
        print("-" * 72)

        for i, data in enumerate(payload):
            print(f"DW{i:<2}: 0x{data:08X}")

    print("=" * 72)


def parse_tlp(dw):

    fmt = get_bits(dw[0], 31, 29)
    typ = get_bits(dw[0], 28, 24)

    tlp_type = FMT_TYPE_MAP.get((fmt, typ))

    if tlp_type is None:

        print(
            f"Unsupported TLP "
            f"(FMT={fmt:#05b}, TYPE={typ:#07b})"
        )

        return

    if tlp_type.startswith("MRd"):
        parse_mrd(dw)

    elif tlp_type.startswith("MWr"):
        parse_mwr(dw)

    elif tlp_type.startswith("Cpl"):
        parse_completion(dw)


def main():

    if len(sys.argv) != 2:

        print()
        print("Usage:")
        print("python3 tlp_parser.py <tlp_hex>")
        print()

        print("Example:")
        print(
            "python3 tlp_parser.py "
            "600000020001000F0000000112345000"
            "DEADBEEFCAFEBABE"
        )

        sys.exit(1)

    tlp_hex = sys.argv[1]

    dw = hex_to_dw_list(tlp_hex)

    parse_tlp(dw)


if __name__ == "__main__":
    main()