#!/usr/bin/env python3
"""make_restore.py - build the images swd/program.tcl writes back after L1 -> L0, or check its read-back.

Usage (run from the repository root; your dumps are in dumps/, the vendor image in vendor/):
    python3 -I tools/make_restore.py          builds build/restore/*.bin from the verified dumps
    python3 -I tools/make_restore.py --check  compares build/restore/readback_*.bin with them

Sources (none is part of the repository): the bootloader read twice, dumps/boot_08000000_a.bin and
_b, and by the dumper, dumps/read1/ (GUIDE.md sections 5 and 6); the vendor application
vendor/LC1020E_V1.1_250702.bin; the settings read twice, dumps/settings_0807F000_a.bin and _b, and
their RAM copy dumps/settings_ram_2000057C.bin.  Every source pair is compared again here; any
difference stops.
"""
import hashlib, os, sys

OUT = 'build/restore'


def rd(p):
    return open(p, 'rb').read()


def images():
    a, b = rd('dumps/boot_08000000_a.bin'), rd('dumps/boot_08000000_b.bin')
    r1 = rd('dumps/read1/boot_08000000.bin')
    if not (a == b == r1):
        sys.exit('bootloader dumps differ')
    last = max(i for i in range(len(a)) if a[i] != 0xFF)
    boot = a[:(last + 4) & ~3]
    s_a, s_b = rd('dumps/settings_0807F000_a.bin'), rd('dumps/settings_0807F000_b.bin')
    if s_a != s_b or rd('dumps/read1/high_08068000.bin')[0x17000:] != s_a:
        sys.exit('settings dumps differ')
    if set(s_a[0xC14:]) != {0xFF}:
        sys.exit('settings page has data after 0xC14')
    settings = s_a[:0xC14]
    if rd('dumps/settings_ram_2000057C.bin') != settings:
        sys.exit('settings dump differs from the V1.1 RAM copy')
    if set(rd('dumps/read1/high_08068000.bin')[:0x17000]) != {0xFF}:
        sys.exit('drive area is not empty: it must be restored too')
    app = rd('vendor/LC1020E_V1.1_250702.bin')
    out = {'boot_08000000.bin': boot, 'app_08006000.bin': app, 'settings_0807F000.bin': settings}
    for k, v in out.items():
        if len(v) % 4:
            sys.exit('%s size %d is not a multiple of 4' % (k, len(v)))
    return out


def main():
    ims = images()
    if '--check' in sys.argv:
        bad = 0
        for k, v in ims.items():
            rb = rd(os.path.join(OUT, 'readback_' + k))
            ok = rb == v
            bad += not ok
            print('%-24s %6d bytes  %s' % (k, len(v), 'read back identical' if ok else 'MISMATCH'))
        sys.exit(1 if bad else 0)
    os.makedirs(OUT, exist_ok=True)
    for k, v in ims.items():
        open(os.path.join(OUT, k), 'wb').write(v)
        print('%-24s %6d bytes  sha256 %s' % (k, len(v), hashlib.sha256(v).hexdigest()))


if __name__ == '__main__':
    main()
