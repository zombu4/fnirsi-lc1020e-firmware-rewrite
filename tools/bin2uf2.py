#!/usr/bin/env python3
"""bin2uf2.py - turn an application image for 0x08006000 into a .uf2 for the LC1020E slot bootloader.

Usage:
    python3 -I tools/bin2uf2.py IMAGE.bin OUT.uf2

UF2 (the USB-drive flashing format): 512-byte blocks, one per 256 bytes of the image:
    +0   0x0A324655  magic 0             +4   0x9E5D5157  magic 1
    +8   flags 0x2000 (family ID present) | 0x8000 (extension tags present)
    +12  target address 0x08006000 + 256 * block number
    +16  payload size 256                +20  block number   +24  block count
    +28  family ID 0xC6B3602B (the LC1020E application; bootloader/src/slot.inc UF2_FAMILY)
    +32  256 payload bytes (the last block padded with 0xFF)
    +288 extension tag: size 12, type 0x45FB65 (word 0x45FB650C), image length, CRC-32 of the image
    +300 end of the tags (a zero word), then zero bytes
    +508 0x0AB16F30  end magic
The slot bootloader takes a block only with all of these fields; (block count, length, CRC-32) is the
transfer key, and it writes the vector page last, after the CRC-32 of the whole image matches.
The image must be 8..0x5C000 bytes with an initial SP in SRAM and an odd reset vector inside
0x08006000..0x08061FFF (the slot bootloader's application-start check).
"""
import struct, sys, zlib

BASE = 0x08006000
MAX = 0x5C000                      # 0x08006000..0x08061FFF
FAMILY = 0xC6B3602B
TAG = 0x45FB650C                   # size 12 | type 0x45FB65 << 8
FLAGS = 0x2000 | 0x8000
PAYLOAD = 256


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    image = open(sys.argv[1], 'rb').read()
    n = len(image)
    if not 8 <= n <= MAX:
        sys.exit('image size %d outside 8..0x%X' % (n, MAX))
    sp, reset = struct.unpack_from('<II', image, 0)
    if not 0x20000000 < sp <= 0x20024000:
        sys.exit('initial SP 0x%08X outside SRAM: not an image for 0x08006000' % sp)
    if not reset & 1 or not BASE <= (reset & ~1) < BASE + MAX:
        sys.exit('reset vector 0x%08X not odd or outside 0x08006000..0x08061FFF' % reset)
    crc = zlib.crc32(image)
    count = -(-n // PAYLOAD)
    out = bytearray()
    for i in range(count):
        data = image[i * PAYLOAD:(i + 1) * PAYLOAD]
        data += b'\xff' * (PAYLOAD - len(data))
        block = struct.pack('<8I', 0x0A324655, 0x9E5D5157, FLAGS, BASE + i * PAYLOAD, PAYLOAD, i, count, FAMILY)
        block += data + struct.pack('<4I', TAG, n, crc, 0)
        block += bytes(508 - len(block)) + struct.pack('<I', 0x0AB16F30)
        out += block
    open(sys.argv[2], 'wb').write(out)
    print('%s: %d blocks (%d bytes) for %d image bytes at 0x%08X, CRC-32 0x%08X, family 0x%08X'
          % (sys.argv[2], count, len(out), n, BASE, crc, FAMILY))


if __name__ == '__main__':
    main()
