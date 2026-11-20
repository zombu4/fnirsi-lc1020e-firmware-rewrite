#!/usr/bin/env python3
"""iap_write.py - install an application image through the LC1020E update drive.

Usage (no sudo; meter in update mode, drive "LC1020E-IAP" attached):
    python3 -I tools/iap_write.py IMAGE.uf2 [8.3 NAME, default LC1020E.UF2]   slot bootloader
    python3 -I tools/iap_write.py IMAGE.bin [8.3 NAME, default LC1020E.BIN]   vendor bootloader

The file type selects the bootloader it is for, and the drive must show that bootloader's geometry
(boot sector read first); a .bin is refused on the slot bootloader's drive and a .uf2 on the vendor's.
Raw sector access goes through the root helper tools/iap_raw.py, installed as
/usr/local/libexec/iap_raw_lc1020e.py by tools/install_sudo_rule.sh.

Slot bootloader (bootloader/, make slot): drive of 512 sectors of 2048 bytes (FAT12: 496 clusters),
Ready.TXT in cluster 2. Every written 512-byte part that is an LC1020E UF2 block (tools/bin2uf2.py)
is programmed, wherever it lies; directory and FAT writes are ignored. The .uf2 is written as one
file: FAT12 chain from cluster 3, root entry, data from LBA 17. When every block has arrived and the
image CRC-32 matches, the bootloader writes the vector page, waits 1000 ms and resets.

Vendor bootloader (what it does with writes, from the disassembly of its dump at 0x08000000), drive
of 196 sectors:
- 0x08003D5C dispatches a write by byte offset: 0 (boot sector), 0x3000 / 0x3800 (FATs) ignored,
  0x4000 (root) -> 0x08003B10 (takes the file entry, copy at 0x20000230), and only offsets >= 0x8800
  -> 0x08003C60. So cluster 2 (offset 0x8000..0x87FF, LBA 16) is never programmed.
- 0x08003C60: name extension "BIN" / "bin" (else the first two data words must look like SP 0x2xxxxxxx
  and reset 0x08xxxxxx); programs the data of successive writes from 0x08006000 (word 0x2000026C),
  whatever their LBA, counting bytes in 0x20000270, the last write cut to the file size; when the
  count reaches the size: state 2 (byte 0x20000274), the main loop waits 1000 ms and calls 0x0800203C.
- Start-up 0x08003E30: up key PC7 (GPIOC 0x40011000 mask 0x80) high and (word 0x08006000 &
  0x2FFE0000) == 0x20000000 -> start the application (0x08001120).
So the .bin goes to clusters 3.. (LBA 17..), as a host does that has already put something in
cluster 2, and its data is written once, in order, after the root entry.
"""
import os, struct, subprocess, sys, tempfile, time

HELPER = ['sudo', '-n', '/opt/homebrew/bin/python3', '-I', '/usr/local/libexec/iap_raw_lc1020e.py']
SECT = 2048
FIRST_CLUSTER = 3                      # vendor: data offset 0x8800, the first one 0x08003C60 receives
DATA0_LBA = 16                         # cluster 2
GEOM_VENDOR = dict(bps=2048, spc=1, rsv=6, nfat=2, nroot=512, totsec=196, media=0xF8, spf=1)
GEOM_SLOT = dict(GEOM_VENDOR, totsec=512)   # bootloader/src/slot.inc DRIVE_SECTORS
MAX_SIZE = 0x5C000                     # vendor: word [0x2000025C], checked at 0x08003CD8
UF2_BLOCKS = 1472                      # slot: 0x5C000 / 256 (UF2_MAX_BLOCKS)


def helper(*args):
    r = subprocess.run(HELPER + list(args), capture_output=True, text=True)
    if r.returncode:
        sys.exit('helper %s failed: %s%s' % (args[0], r.stdout, r.stderr))
    return r.stdout.strip()


def geometry(v):
    return dict(bps=struct.unpack_from('<H', v, 11)[0], spc=v[13], rsv=struct.unpack_from('<H', v, 14)[0],
                nfat=v[16], nroot=struct.unpack_from('<H', v, 17)[0], totsec=struct.unpack_from('<H', v, 19)[0],
                media=v[21], spf=struct.unpack_from('<H', v, 22)[0])


def entry(n83, cluster, size):
    stem, _, ext = n83.partition('.')
    t = time.localtime()
    dtime = (t.tm_hour << 11) | (t.tm_min << 5) | (t.tm_sec // 2)
    ddate = ((t.tm_year - 1980) << 9) | (t.tm_mon << 5) | t.tm_mday
    ent = bytearray(32)
    ent[0:11] = (stem.ljust(8) + ext).encode()
    ent[11] = 0x20
    struct.pack_into('<HHHHHHHI', ent, 14, dtime, ddate, ddate, 0, dtime, ddate, cluster, size)
    return ent


def fat12_set(fat, k, value):
    o = k * 3 // 2
    if k & 1:
        fat[o] = (fat[o] & 0x0F) | ((value << 4) & 0xF0)
        fat[o + 1] = (value >> 4) & 0xFF
    else:
        fat[o] = value & 0xFF
        fat[o + 1] = (fat[o + 1] & 0xF0) | ((value >> 8) & 0x0F)


def check_uf2(payload):
    if not payload or len(payload) % 512:
        sys.exit('a .uf2 is a non-empty multiple of 512 bytes')
    count = len(payload) // 512
    first = struct.unpack_from('<8I', payload, 0)
    if first[0] != 0x0A324655 or first[1] != 0x9E5D5157 or first[7] != 0xC6B3602B:
        sys.exit('not an LC1020E .uf2 (magic / family ID 0xC6B3602B); make it with tools/bin2uf2.py')
    if first[6] != count or not 1 <= count <= UF2_BLOCKS:
        sys.exit('block count %d in the file, %d blocks present (at most %d)' % (first[6], count, UF2_BLOCKS))


def main():
    image = os.path.abspath(sys.argv[1])
    payload = open(image, 'rb').read()
    uf2 = image.lower().endswith('.uf2')
    if not uf2 and not image.lower().endswith('.bin'):
        sys.exit('IMAGE must be a .uf2 (slot bootloader) or a .bin (vendor bootloader)')
    ext_want = 'UF2' if uf2 else 'BIN'
    n83 = (sys.argv[2] if len(sys.argv) > 2 else 'LC1020E.' + ext_want).upper()
    stem, _, ext = n83.partition('.')
    if not stem or len(stem) > 8 or ext != ext_want or not stem.isalnum():
        sys.exit('name must be 8.3 with extension %s: %r' % (ext_want, n83))
    if uf2:
        check_uf2(payload)
        geom = GEOM_SLOT
    else:
        if not 0 < len(payload) <= MAX_SIZE:
            sys.exit('image size %d outside 1..0x%X' % (len(payload), MAX_SIZE))
        geom = GEOM_VENDOR
    nclus = -(-len(payload) // SECT)
    if FIRST_CLUSTER + nclus - 1 > geom['totsec'] - DATA0_LBA + 1:
        sys.exit('image does not fit the drive')
    with tempfile.TemporaryDirectory() as td:
        vol = os.path.join(td, 'vol.img')
        helper('read', vol)
        v = open(vol, 'rb').read()
        g = geometry(v)
        if g != geom:
            other = 'vendor' if g == GEOM_VENDOR else 'slot' if g == GEOM_SLOT else None
            sys.exit('volume is not the %s bootloader\'s layout: %r%s'
                     % ('slot' if uf2 else 'vendor', g, ' (it is the %s bootloader\'s drive)' % other if other else ''))
        root = (geom['rsv'] + geom['nfat'] * geom['spf']) * SECT
        e0, e1 = v[root:root + 32], v[root + 32:root + 64]
        if e0[:11] != b'Ready   TXT' or e1[:11] != b'LC1020E-IAP' or e1[11] != 0x08:
            sys.exit('root entries 0 / 1 are not Ready.TXT and the label')
        fat = bytearray(SECT)
        if uf2:
            # FAT12 (496 clusters): entries 0 / 1, cluster 2 = Ready.TXT (end of chain), file from 3
            fat12_set(fat, 0, 0xFF8)
            fat12_set(fat, 1, 0xFFF)
            fat12_set(fat, 2, 0xFFF)
            for i in range(nclus):
                c = FIRST_CLUSTER + i
                fat12_set(fat, c, 0xFFF if i == nclus - 1 else c + 1)
        else:
            fat[0:4] = b'\xf8\xff\xff\xff'
            struct.pack_into('<H', fat, 4, 0xFFFF)          # cluster 2: in use (what a host put there)
            for i in range(nclus):
                c = FIRST_CLUSTER + i
                struct.pack_into('<H', fat, 2 * c, 0xFFFF if i == nclus - 1 else c + 1)
        rootsec = bytearray(SECT)
        rootsec[0:32], rootsec[32:64], rootsec[64:96] = e0, e1, entry(n83, FIRST_CLUSTER, len(payload))
        body = payload + bytes(nclus * SECT - len(payload))
        files = {}
        for name, blob in (('fat', fat), ('root', rootsec), ('data', body)):
            files[name] = os.path.join(td, name + '.bin')
            open(files[name], 'wb').write(blob)
        print(helper('write', str(geom['rsv']), files['fat']))
        print(helper('write', str(geom['rsv'] + 1), files['fat']))
        print(helper('write', str(root // SECT), files['root']))
        print(helper('write', str(DATA0_LBA + FIRST_CLUSTER - 2), files['data']))
    print('written %s (%d bytes) as %s at cluster %d (LBA %d); the bootloader starts it after 1 s when done'
          % (image, len(payload), n83, FIRST_CLUSTER, DATA0_LBA + FIRST_CLUSTER - 2))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main()
