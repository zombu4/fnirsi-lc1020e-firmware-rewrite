#!/usr/bin/env python3
"""vendor_data.py - copy the vendor data blocks the application source includes out of your own V1.1 file.

Usage (from firmware/, as `make vendor-data IMAGE=<file>`):
    python3 -I ../tools/vendor_data.py <LC1020E_V1.1_250702.bin> vendor_blobs.tsv assets/vendor

The vendor update file LC1020E_V1.1_250702.bin (309080 bytes, linked at 0x08006000) is not part of this
repository.  For every row of vendor_blobs.tsv (address, length, SHA-256) the block is cut out of the
file, checked against its SHA-256 and written to assets/vendor/<address>.bin.  Any difference stops with
exit status 1 and writes nothing for that block.
"""
import hashlib, os, sys

BASE, SIZE = 0x08006000, 309080
if len(sys.argv) != 4:
    sys.exit(__doc__)
img = open(sys.argv[1], 'rb').read()
if len(img) != SIZE:
    sys.exit('%s: %d bytes, the V1.1 update file has %d' % (sys.argv[1], len(img), SIZE))
os.makedirs(sys.argv[3], exist_ok=True)
n = 0
for line in open(sys.argv[2]):
    if line.startswith('#') or line.startswith('address') or not line.strip():
        continue
    addr, length, sha = line.split()
    a, k = int(addr, 16), int(length)
    blob = img[a - BASE:a - BASE + k]
    if hashlib.sha256(blob).hexdigest() != sha:
        sys.exit('block 0x%s (%d bytes): SHA-256 differs; is this the V1.1 file?' % (addr, k))
    open(os.path.join(sys.argv[3], addr + '.bin'), 'wb').write(blob)
    n += 1
print('%d blocks OK in %s' % (n, sys.argv[3]))
