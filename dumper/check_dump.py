#!/usr/bin/env python3
"""Check a dump read by swd/read_dump.tcl against the CRCs the dumper computed on the meter.

Usage: python3 -I check_dump.py DUMP_DIR [DUMP_DIR2]
DUMP_DIR holds result.bin, boot_08000000.bin, high_08068000.bin.  Each part's zlib CRC-32 must
equal the CRC in result.bin (computed by the meter from flash); with a second directory, all
files must be byte-identical between the two reads.  Exit status 0 only when everything matches.
"""
import os
import struct
import sys
import zlib


def main():
    d = sys.argv[1]
    res = open(os.path.join(d, "result.bin"), "rb").read()
    magic, crc_boot, crc_high, crc_upd, beat = struct.unpack_from("<5I", res, 0)
    ok = magic == 0x504D5544
    print("magic 0x%08X %s" % (magic, "ok" if ok else "FAIL"))
    for fn, size, want in (("boot_08000000.bin", 0x6000, crc_boot), ("high_08068000.bin", 0x18000, crc_high)):
        b = open(os.path.join(d, fn), "rb").read()
        good = len(b) == size and zlib.crc32(b) == want
        print("%s: %d bytes, crc 0x%08X, meter 0x%08X %s" % (fn, len(b), zlib.crc32(b), want, "ok" if good else "FAIL"))
        ok &= good
    # content checks (the CRCs and the copies come from the same CPU reads, so they cannot show
    # reads that returned constant data): the bootloader's vector table and the settings markers
    boot = open(os.path.join(d, "boot_08000000.bin"), "rb").read()
    high = open(os.path.join(d, "high_08068000.bin"), "rb").read()
    sp, rst = struct.unpack_from("<II", boot, 0)
    vt = 0x20000000 <= sp <= 0x20024000 and rst & 1 and 0x08000000 <= rst < 0x08006000
    print("bootloader SP 0x%08X reset 0x%08X: %s" % (sp, rst, "plausible" if vt else "FAIL"))
    ok &= bool(vt)
    # settings block 0x0807F000, 0xC14 bytes: main 0x08027FF4 checks its first word (RAM 0x2000057C)
    # and its last word (RAM 0x2000118C = flash 0x0807FC10) for 0x12345678
    m0, m1 = struct.unpack_from("<I", high, 0x17000)[0], struct.unpack_from("<I", high, 0x17C10)[0]
    mk = m0 == 0x12345678 and m1 == 0x12345678
    print("settings markers 0x0807F000 = 0x%08X, 0x0807FC10 = 0x%08X: %s" % (m0, m1, "ok" if mk else "FAIL"))
    ok &= mk
    print("crc of the update area 0x08006000..0x08067FFF on the meter: 0x%08X" % crc_upd)
    print("option bytes copy: %s" % res[0x20:0x30].hex(" "))
    if len(sys.argv) > 2:
        for fn in ("result.bin", "boot_08000000.bin", "high_08068000.bin"):
            a = open(os.path.join(d, fn), "rb").read()
            b = open(os.path.join(sys.argv[2], fn), "rb").read()
            same = a[:0x10] + a[0x14:] == b[:0x10] + b[0x14:] if fn == "result.bin" else a == b
            print("%s identical in both reads (heartbeat excluded): %s" % (fn, same))
            ok &= same
    print("ALL OK" if ok else "MISMATCH")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
