#!/usr/bin/env python3
"""iap_raw.py - raw sector access to the LC1020E update drive; the only part that runs as root.

Installed root-owned as /usr/local/libexec/iap_raw_lc1020e.py by tools/install_sudo_rule.sh
(macOS); everything else (what to write, in which order) lives in non-root
scripts that call it, so this file does not change when the procedure changes.

    sudo -n /opt/homebrew/bin/python3 -I /usr/local/libexec/iap_raw_lc1020e.py read OUT
    sudo -n /opt/homebrew/bin/python3 -I /usr/local/libexec/iap_raw_lc1020e.py write LBA FILE [CHUNK]

read: the whole drive -> OUT (chowned to the sudo user).  write: FILE (a non-empty multiple of 2048
bytes, inside the drive) to sectors LBA.., in pwrite calls of CHUNK bytes (default the whole file;
the kernel splits a call into SCSI WRITE commands of its maximum transfer size).
Refuses unless exactly one external physical disk is named "LC1020E-IAP" and it is at most 1 MiB.
The drive is unmounted before each access.
"""
import os, plistlib, subprocess, sys

SECT = 2048
LABEL = 'LC1020E-IAP'
MAXSEC = 512            # 1 MiB of 2048-byte sectors
if os.geteuid() != 0:
    sys.exit('run with sudo: the raw device needs root')
args = sys.argv[1:]
if not args or args[0] not in ('read', 'write'):
    sys.exit(__doc__)


def plist(cmd):
    return plistlib.loads(subprocess.run(cmd, capture_output=True, check=True).stdout)


cands = []
for d in plist(['diskutil', 'list', '-plist', 'external', 'physical']).get('AllDisksAndPartitions', []):
    info = plist(['diskutil', 'info', '-plist', '/dev/' + d['DeviceIdentifier']])
    if info.get('VolumeName') == LABEL or d.get('VolumeName') == LABEL:
        cands.append((d['DeviceIdentifier'], info.get('TotalSize', 0)))
if len(cands) != 1:
    sys.exit('need exactly one attached disk named %s, found %r' % (LABEL, cands))
ident, size = cands[0]
if not (0 < size <= MAXSEC * SECT):
    sys.exit('refusing: /dev/%s is %d bytes' % (ident, size))
dev, raw = '/dev/' + ident, '/dev/r' + ident
subprocess.run(['diskutil', 'unmountDisk', 'force', dev], check=True, capture_output=True)

if args[0] == 'read':
    if len(args) != 2:
        sys.exit('usage: read OUT')
    out = os.path.abspath(args[1])
    fd = os.open(raw, os.O_RDONLY)
    try:
        data = bytearray()
        while True:
            b = os.read(fd, 64 * SECT)
            if not b:
                break
            data += b
            if len(data) > MAXSEC * SECT:
                sys.exit('drive larger than expected')
    finally:
        os.close(fd)
    with open(out, 'wb') as f:
        f.write(data)
    os.chown(out, int(os.environ.get('SUDO_UID', '0')), int(os.environ.get('SUDO_GID', '0')))
    print('read %d bytes from %s to %s' % (len(data), dev, out))
else:
    if len(args) not in (3, 4):
        sys.exit('usage: write LBA FILE [CHUNK]')
    lba = int(args[1], 0)
    blob = open(os.path.abspath(args[2]), 'rb').read()
    chunk = int(args[3], 0) if len(args) == 4 else len(blob)
    if not blob or len(blob) % SECT or lba < 0 or (lba * SECT + len(blob)) > size:
        sys.exit('write: FILE must be a non-empty multiple of %d bytes inside the drive' % SECT)
    if chunk <= 0 or chunk % SECT:
        sys.exit('write: CHUNK must be a positive multiple of %d' % SECT)
    fd = os.open(raw, os.O_WRONLY)
    try:
        calls = 0
        for o in range(0, len(blob), chunk):
            part = blob[o:o + chunk]
            if os.pwrite(fd, part, lba * SECT + o) != len(part):
                sys.exit('short write at byte %d' % o)
            calls += 1
    finally:
        os.close(fd)
    subprocess.run(['sync'])
    print('wrote %d sectors at LBA %d in %d calls of up to %d bytes' % (len(blob) // SECT, lba, calls, chunk))
