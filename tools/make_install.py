#!/usr/bin/env python3
"""make_install.py - prepare and check the images swd/install_bootloader.tcl writes, or check its read-back.

Usage (from the repository root, after `make -C starter` and the slot builds of bootloader/):
    python3 -I tools/make_install.py                         first install (STAGE=slots / starter):
                                                             writes build/install/*.bin, prints SHA-256
    python3 -I tools/make_install.py --check                 compares build/install/readback_*.bin
                                                             with them
    python3 -I tools/make_install.py --stage slot_a|slot_f   slot update: writes BOOT_A.bin or
                                                             BOOT_F.bin (feature version 2 or later)
    python3 -I tools/make_install.py --check --stage slot_a  readback_BOOT_A.bin identical, and in
                                                             readback_records.bin the newest record
                                                             (as the starter scans) INSTALL A with
                                                             the version of BOOT_A.bin
    python3 -I tools/make_install.py --check --stage slot_f  readback_BOOT_F.bin identical

Images and addresses (two-part bootloader layout):
    STARTER.bin    0x08000000  page 0 (starter/build/STARTER.bin, at most 0x800 bytes)
    BOOT_F.bin     0x08069000  slot F (bootloader/build/slot/BOOT_F.bin)
    BOOT_A.bin     0x0806F000  slot A (bootloader/build/slot/BOOT_A.bin)
    record.bin     0x08068000  first control record: INSTALL for slot A, sequence 1 (first install;
                               STAGE=slot_a appends its record on the meter, from the records there)
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
REC0 = 0x08068000
REC_TAG = 0x4C52
ST_INSTALL = 1
STATES = {1: 'INSTALL', 2: 'TRIAL', 3: 'OK'}
STAGES = {'slot_a': 'BOOT_A.bin', 'slot_f': 'BOOT_F.bin'}
MIN_VERSION = 2     # feature version of the slot images the slot update stages write


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


def slot_image(name):
    """The built slot image, checked as the starter checks it, cut to header + length."""
    base = SLOTS[name]
    img = open(os.path.join('bootloader/build/slot', name), 'rb').read()
    why = slot_ok(name, img, base)
    if why:
        sys.exit('%s: %s' % (name, why))
    length = struct.unpack_from('<I', img, 4)[0]
    img = img[:0x200 + length]
    return img + b'\xff' * (-len(img) % 4)


def images():
    out = {}
    starter = open('starter/build/STARTER.bin', 'rb').read()
    if len(starter) > 0x800 or len(starter) % 4:
        sys.exit('STARTER.bin: %d bytes (must fit page 0 and be a multiple of 4)' % len(starter))
    sp, pc = struct.unpack_from('<II', starter, 0)
    if not 0x20000000 < sp <= 0x20024000 or not pc & 1 or (pc & ~1) >= 0x08000800:
        sys.exit('STARTER.bin: vector table SP 0x%08X reset 0x%08X' % (sp, pc))
    out['STARTER.bin'] = starter
    for name in SLOTS:
        out[name] = slot_image(name)
    version = struct.unpack_from('<I', out['BOOT_A.bin'], 12)[0]
    w = struct.pack('<III', 0x4C520000 | 1 << 8 | ST_INSTALL, version, 1)
    out['record.bin'] = w + struct.pack('<I', zlib.crc32(w))
    return out


def stage_image(stage):
    """(name, image, version) of the slot image a slot update stage writes; version >= 2."""
    name = STAGES[stage]
    img = slot_image(name)
    version = struct.unpack_from('<I', img, 12)[0]
    if version < MIN_VERSION:
        sys.exit('%s: version %d, the stage %s needs %d or later' % (name, version, stage, MIN_VERSION))
    return name, img, version


def newest_record(pages):
    """starter.s scan_records on the 0x1000 bytes of the record pages: (slot, state, version,
    sequence, cell address) of the newest valid record (the lower slot on equal sequence
    numbers), or None when there is no valid record."""
    best = {}
    for off in range(0, len(pages), 16):
        w0, ver, seq, crc = struct.unpack_from('<IIII', pages, off)
        if w0 >> 16 != REC_TAG or zlib.crc32(pages[off:off + 12]) != crc:
            continue
        slot, state = (w0 >> 8) & 0xFF, w0 & 0xFF
        if slot >= 3 or not 1 <= state <= 3:
            continue
        if seq > best.get(slot, (0,))[0]:
            best[slot] = (seq, state, ver, REC0 + off)
    newest = None
    top = 0
    for slot in range(3):
        if slot in best and best[slot][0] > top:
            seq, state, ver, cell = best[slot]
            top = seq
            newest = (slot, state, ver, seq, cell)
    return newest


def check_stage(stage):
    """Read-back check of STAGE=slot_a / slot_f; returns the exit status."""
    name, img, version = stage_image(stage)
    p = os.path.join(OUT, 'readback_' + name)
    ok = os.path.exists(p) and open(p, 'rb').read() == img
    print('%-12s %6d bytes  version %d  %s' % (name, len(img), version,
                                                 'read back identical' if ok else 'MISMATCH'))
    bad = not ok
    if stage == 'slot_a':
        p = os.path.join(OUT, 'readback_records.bin')
        pages = open(p, 'rb').read() if os.path.exists(p) else b''
        if len(pages) != 0x1000:
            print('records      missing or not 0x1000 bytes: MISMATCH')
            return 1
        n = newest_record(pages)
        if n is None:
            print('records      no valid record: MISMATCH')
            return 1
        slot, state, ver, seq, cell = n
        good = slot == 1 and state == ST_INSTALL and ver == version
        print('records      newest %s slot %d version %d sequence %d at 0x%08X  %s'
              % (STATES[state], slot, ver, seq, cell, 'INSTALL A as written' if good else 'MISMATCH'))
        bad = bad or not good
    return 1 if bad else 0


def main():
    args = sys.argv[1:]
    stage = None
    if '--stage' in args:
        i = args.index('--stage')
        if i + 1 >= len(args) or args[i + 1] not in STAGES:
            sys.exit('--stage needs slot_a or slot_f')
        stage = args[i + 1]
        del args[i:i + 2]
    check = '--check' in args
    if stage:
        if check:
            sys.exit(check_stage(stage))
        name, img, version = stage_image(stage)
        os.makedirs(OUT, exist_ok=True)
        open(os.path.join(OUT, name), 'wb').write(img)
        print('%-12s %6d bytes  version %d  sha256 %s' % (name, len(img), version,
                                                           hashlib.sha256(img).hexdigest()))
        return
    ims = images()
    if check:
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
