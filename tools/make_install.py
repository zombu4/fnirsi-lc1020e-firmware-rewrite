#!/usr/bin/env python3
"""make_install.py - prepare and check the images swd/install_bootloader.tcl writes, or check its read-back.

Usage (from the repository root, after `make -C starter` and the slot builds of bootloader/):
    python3 -I tools/make_install.py           writes build/install/*.bin and prints their SHA-256
    python3 -I tools/make_install.py --check   compares build/install/readback_*.bin with them

Images and addresses (two-part bootloader layout):
    STARTER.bin    0x08000000  page 0 (starter/build/STARTER.bin, at most 0x800 bytes)
    BOOT_F.bin     0x08069000  slot F (bootloader/build/slot/BOOT_F.bin)
    BOOT_A.bin     0x0806F000  slot A (bootloader/build/slot/BOOT_A.bin)
    record.bin     0x08068000  first control record: INSTALL for slot A, sequence 1
Each slot image is checked the way the starter checks it at reset (magic, header CRC-32, link
address = slot + 0x200, length 8..0x5E00 and a multiple of 4, image CRC-32, initial SP inside SRAM,
reset vector odd and inside the image); any failure stops.
"""
import hashlib
import os
import struct
import sys
import zlib

OUT = 'build/install'
SLOTS = {'BOOT_F.bin': 0x08069000, 'BOOT_A.bin': 0x0806F000}
ROOM = 0x5E00
ST_INSTALL = 1


def slot_ok(name, img, base):
    if len(img) < 0x208:
        return 'too short'
    magic, length, icrc, version, link = struct.unpack_from('<IIIII', img, 0)
    if magic != 0x544F4C53:
        return 'magic 0x%08X' % magic
    if zlib.crc32(img[:28]) != struct.unpack_from('<I', img, 28)[0]:
        return 'header CRC'
    if link != base + 0x200:
        return 'link address 0x%08X' % link
    if not 8 <= length <= ROOM or length % 4 or 0x200 + length > len(img):
        return 'length 0x%X' % length
    body = img[0x200:0x200 + length]
    if zlib.crc32(body) != icrc:
        return 'image CRC'
    sp, pc = struct.unpack_from('<II', body, 0)
    if not 0x20000000 < sp <= 0x20024000:
        return 'SP 0x%08X' % sp
    if not pc & 1 or not link <= (pc & ~1) < link + length:
        return 'reset vector 0x%08X' % pc
    return None


def images():
    out = {}
    starter = open('starter/build/STARTER.bin', 'rb').read()
    if len(starter) > 0x800 or len(starter) % 4:
        sys.exit('STARTER.bin: %d bytes (must fit page 0 and be a multiple of 4)' % len(starter))
    sp, pc = struct.unpack_from('<II', starter, 0)
    if not 0x20000000 < sp <= 0x20024000 or not pc & 1 or (pc & ~1) >= 0x08000800:
        sys.exit('STARTER.bin: vector table SP 0x%08X reset 0x%08X' % (sp, pc))
    out['STARTER.bin'] = starter
    for name, base in SLOTS.items():
        img = open(os.path.join('bootloader/build/slot', name), 'rb').read()
        why = slot_ok(name, img, base)
        if why:
            sys.exit('%s: %s' % (name, why))
        length = struct.unpack_from('<I', img, 4)[0]
        img = img[:0x200 + length]
        out[name] = img + b'\xff' * (-len(img) % 4)
    version = struct.unpack_from('<I', out['BOOT_A.bin'], 12)[0]
    w = struct.pack('<III', 0x4C520000 | 1 << 8 | ST_INSTALL, version, 1)
    out['record.bin'] = w + struct.pack('<I', zlib.crc32(w))
    return out


def main():
    ims = images()
    if '--check' in sys.argv:
        bad = 0
        for k, v in ims.items():
            p = os.path.join(OUT, 'readback_' + k)
            ok = os.path.exists(p) and open(p, 'rb').read() == v
            bad += not ok
            print('%-12s %6d bytes  %s' % (k, len(v), 'read back identical' if ok else 'MISMATCH'))
        sys.exit(1 if bad else 0)
    os.makedirs(OUT, exist_ok=True)
    for k, v in ims.items():
        open(os.path.join(OUT, k), 'wb').write(v)
        print('%-12s %6d bytes  sha256 %s' % (k, len(v), hashlib.sha256(v).hexdigest()))


if __name__ == '__main__':
    main()
