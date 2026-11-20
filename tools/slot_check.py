#!/usr/bin/env python3
"""slot_check.py - build checks of the slot bootloader images (bootloader/Makefile, make slot).

Usage:
    python3 -I tools/slot_check.py STOCK.elf SLOT_INC [--rwdata RWDATA.bin] BASE:SLOT.elf:BOOT_X.bin ...

STOCK.elf  the stock build (make check), linked at 0x08000000
SLOT_INC   bootloader/src/slot.inc (DRIVE_SECTORS is read from it)
RWDATA     the stock bootloader's initial RAM image 0x20000000..0x2000021F, unpacked from a dump
           (not part of the repository); with it the typed RAM image is compared
BASE       slot base address; SLOT.elf the linked slot image; BOOT_X.bin header + image

Checks, per slot image:
 1. every function symbol of the stock build keeps its address modulo 4 (relative to the link
    base: 0x08000000 for the stock image, BASE + 0x200 for the slot image) or is absent from the
    slot build (the units it replaces);
 2. no 4-aligned word of BOOT_X.bin lies in 0x08000000..0x08005FFF (the stock bootloader area);
 3. the image after the header is at most 0x5E00 bytes and the header length matches;
 4. (--rwdata) the typed RAM image (symbol ram_image, 0x220 bytes) equals RWDATA, except that
    every word of RWDATA inside 0x08000000..0x08005FFF (there must be 39) is the slot address of
    the same code or data (nearest stock symbol plus offset, moved to that symbol in the slot
    build) and the total-sector field (bytes 0x27..0x28) is DRIVE_SECTORS.
Exit status 1 on the first failing image, with every failure listed.
"""
import re, struct, subprocess, sys

NM = 'arm-none-eabi-nm'
LO, HI = 0x08000000, 0x08006000
ROOM = 0x5E00
RAM_SIZE = 0x220


def symbols(elf):
    out = subprocess.run([NM, elf], capture_output=True, text=True, check=True).stdout
    syms = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] in 'TtDdRrAa' and not parts[2].startswith('$'):
            syms[parts[2]] = (int(parts[0], 16), parts[1])
    return syms


def main():
    args = sys.argv[1:]
    rwdata = None
    if '--rwdata' in args:
        i = args.index('--rwdata')
        rwdata = open(args[i + 1], 'rb').read()
        del args[i:i + 2]
    if len(args) < 3:
        sys.exit(__doc__)
    stock = symbols(args[0])
    m = re.search(r'\.equ\s+DRIVE_SECTORS,\s*(\d+)', open(args[1]).read())
    if not m:
        sys.exit('DRIVE_SECTORS not found in %s' % args[1])
    sectors = int(m.group(1))
    funcs = {n: v for n, (v, t) in stock.items() if t in 'Tt'}
    # global symbols only: a local alias (vectors.s unused_vector) names other code in the slot build
    by_addr = sorted((v, n) for n, (v, t) in stock.items() if LO <= v < HI and t.isupper())
    if rwdata is not None and len(rwdata) != RAM_SIZE:
        sys.exit('RWDATA is %d bytes, not 0x%X' % (len(rwdata), RAM_SIZE))
    bad = 0
    for spec in args[2:]:
        base_s, elf, boot = spec.split(':')
        base = int(base_s, 0)
        link = base + 0x200
        slot = symbols(elf)
        blob = open(boot, 'rb').read()
        image = blob[0x200:]
        errors = []
        # 1. address modulo 4
        moved = 0
        for name, v in sorted(funcs.items()):
            if name not in slot:
                continue
            sv = slot[name][0]
            if (sv - link) % 4 != (v - LO) % 4:
                errors.append('%s: stock 0x%08X, slot 0x%08X: other address modulo 4' % (name, v, sv))
            moved += 1
        # 2. no word in the stock bootloader area
        for off in range(0, len(blob) - 3, 4):
            w = struct.unpack_from('<I', blob, off)[0]
            if LO <= w < HI:
                errors.append('word 0x%08X at 0x%08X lies in 0x08000000..0x08005FFF' % (w, base + off))
        # 3. size and header length
        n = struct.unpack_from('<I', blob, 4)[0]
        if len(image) > ROOM or n != len(image):
            errors.append('image %d bytes, header length %d, room 0x%X' % (len(image), n, ROOM))
        # 4. typed RAM image
        ram_note = 'RAM image not compared (no --rwdata)'
        if rwdata is not None:
            if 'ram_image' not in slot:
                errors.append('symbol ram_image missing')
            else:
                a = slot['ram_image'][0] - link
                typed = image[a:a + RAM_SIZE]
                want = bytearray(rwdata)
                ptrs = 0
                for off in range(0, RAM_SIZE, 4):
                    v = struct.unpack_from('<I', rwdata, off)[0]
                    if not LO <= v < HI:
                        continue
                    ptrs += 1
                    sv, sn = max((x for x in by_addr if x[0] <= v), default=(None, None))
                    if sn is None or sn not in slot:
                        errors.append('RAM word +0x%03X = 0x%08X: no stock symbol at or below it '
                                      'in the slot build' % (off, v))
                        continue
                    struct.pack_into('<I', want, off, slot[sn][0] + (v - sv))
                struct.pack_into('<H', want, 0x27, sectors)
                if ptrs != 39:
                    errors.append('RWDATA holds %d flash pointers, expected 39' % ptrs)
                for off in range(0, RAM_SIZE, 4):
                    if typed[off:off + 4] != want[off:off + 4]:
                        errors.append('RAM image +0x%03X: typed %s, expected %s'
                                      % (off, typed[off:off + 4].hex(), want[off:off + 4].hex()))
                ram_note = 'RAM image = RWDATA with %d pointers moved, sector count %d' % (ptrs, sectors)
        if errors:
            bad = 1
            print('%s: FAIL' % boot)
            for e in errors:
                print('  ' + e)
        else:
            print('%s: OK (%d bytes after the header, room 0x%X; %d functions at their address '
                  'modulo 4; no word in 0x08000000..0x08005FFF; %s)'
                  % (boot, len(image), ROOM, moved, ram_note))
    sys.exit(bad)


if __name__ == '__main__':
    main()
