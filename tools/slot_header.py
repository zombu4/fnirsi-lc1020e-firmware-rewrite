#!/usr/bin/env python3
"""slot_header.py - put the 0x200-byte slot header in front of a linked slot bootloader image.

Usage:
    python3 -I tools/slot_header.py IMAGE.bin SLOT_BASE VERSION OUT.bin

IMAGE.bin is the raw image (objcopy -O binary) linked for SLOT_BASE + 0x200 (bootloader/link_slot.ld).
OUT.bin = header + image, to be written at SLOT_BASE.  Header layout (starter/starter.s):
    +0  magic "SLOT" 0x544F4C53     +4  image length       +8  CRC-32 of the image
    +12 version                     +16 link address (SLOT_BASE + 0x200)
    +20, +24 zero                   +28 CRC-32 of bytes 0..27
    +32..0x1FF 0xFF (left erased)
The image is refused unless it passes the starter's header check: length a multiple of 4 and
8..0x5E00 bytes, initial SP above 0x20000000 and at most 0x20024000, reset vector odd and inside the
image.
"""
import struct, sys, zlib

MAGIC = 0x544F4C53
ROOM = 0x5E00
SLOTS = (0x08069000, 0x0806F000, 0x08075000)
SRAM_LO, SRAM_HI = 0x20000000, 0x20024000


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    image = open(sys.argv[1], 'rb').read()
    base = int(sys.argv[2], 0)
    version = int(sys.argv[3], 0)
    if base not in SLOTS:
        sys.exit('slot base 0x%08X is not one of %s' % (base, ', '.join('0x%08X' % s for s in SLOTS)))
    if not 0 <= version <= 0xFFFFFFFF:
        sys.exit('version must fit 32 bits')
    n = len(image)
    if n % 4 or not 8 <= n <= ROOM:
        sys.exit('image length %d: must be a multiple of 4 and 8..0x%X bytes' % (n, ROOM))
    link = base + 0x200
    sp, reset = struct.unpack_from('<II', image, 0)
    if not SRAM_LO < sp <= SRAM_HI:
        sys.exit('initial SP 0x%08X outside SRAM' % sp)
    if not reset & 1 or not link <= (reset & ~1) < link + n:
        sys.exit('reset vector 0x%08X not odd or not inside the image' % reset)
    head = struct.pack('<7I', MAGIC, n, zlib.crc32(image), version, link, 0, 0)
    head += struct.pack('<I', zlib.crc32(head))
    out = head + b'\xff' * (0x200 - len(head)) + image
    open(sys.argv[4], 'wb').write(out)
    print('%s: %d bytes (header 0x200 + image %d = 0x%X, CRC-32 0x%08X), at 0x%08X, version %d'
          % (sys.argv[4], len(out), n, n, zlib.crc32(image), base, version))


if __name__ == '__main__':
    main()
