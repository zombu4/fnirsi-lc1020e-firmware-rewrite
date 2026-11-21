#!/usr/bin/env python3
"""test_uf2.py - the slot bootloader's UF2 update path by direct calls, in the emulator.

Usage (from the repository root, after `make -C starter` and `make -C bootloader slot`):
    <python with unicorn 2.1.4> tests/test_uf2.py

The test makes a real .uf2 with tools/bin2uf2.py from vendor/LC1020E_V1.1_250702.bin (309,080 bytes,
1208 blocks) in a temporary folder. Slot A (build/slot/BOOT_A.bin at 0x0806F000) is started at its
own reset vector and stopped at `main` (start-up code, clocks and RAM image done), then uf2_init()
and uf2_sector(r0 = drive offset, r1 = 0x800-byte buffer at 0x20010000, r2 = 0x800) are called
directly, four 512-byte parts per sector. Before every transfer the application area
0x08006000..0x08061FFF holds 0x00 in every byte (an old programmed image: every page must be erased
before it is programmed, or the flash model reports PGERR). Flash / peripheral model:
tests/meter_model.py. State words (bootloader/src/slot.inc): 0x20002140 state (0 idle, 1 receiving,
2 written, 3 failed), +4 error, +8 block count, +0xC length, +0x10 CRC, +0x14 blocks taken;
completion byte 0x20000274 = 2.

Expected flash after a complete transfer of an image of L bytes: pages 0 .. (L - 1) / 0x800 of the
application area hold the image, then 0xFF to the end of its last page; every other page of the
area keeps its old bytes (0x00). Every erase / programmed word lies in 0x08006000..0x08061FFF.
"""
import os
import struct
import subprocess
import sys
import tempfile
import zlib

from meter_model import Meter, cell, APP, APP_END, PAGE, REC0, REC_END, SLOTS, VENDOR_APP, BIN2UF2, ST_OK

U = 0x20002140
BOOT_STATE = 0x20000274
BUF = 0x20010000
FAMILY = 0xC6B3602B
TAG = 0x45FB650C
CASES = []
NOTES = []
SLOT = 1          # slot A


def case(fn):
    CASES.append(fn)
    return fn


def check(cond, text):
    if not cond:
        raise AssertionError(text)


def make_uf2(image):
    d = tempfile.mkdtemp(prefix='lc1020e_uf2_')
    src, out = os.path.join(d, 'app.bin'), os.path.join(d, 'app.uf2')
    open(src, 'wb').write(image)
    subprocess.run([sys.executable, '-I', BIN2UF2, src, out], check=True, capture_output=True)
    data = open(out, 'rb').read()
    return [data[i:i + 512] for i in range(0, len(data), 512)]


def block(n, count, payload, length, crc, target=None, family=FAMILY, flags=0xA000, size=256,
          tag=TAG, end=0x0AB16F30):
    """One UF2 block in the layout of tools/bin2uf2.py with every field selectable."""
    if target is None:
        target = APP + 256 * n
    b = struct.pack('<8I', 0x0A324655, 0x9E5D5157, flags, target, size, n, count, family)
    b += payload[:256].ljust(256, b'\xff') + struct.pack('<4I', tag, length, crc, 0)
    return b + bytes(508 - len(b)) + struct.pack('<I', end)


def with_field(blk, offset, value):
    b = bytearray(blk)
    struct.pack_into('<I', b, offset, value)
    return bytes(b)


class Rig:
    """Slot A started up to main; the application area filled with 0x00."""

    def __init__(self, old=b'\x00'):
        self.m = Meter(slots=('F', 'A', 'B'), records=[(REC0, cell(1, ST_OK, 1))], starter=False)
        m = self.m
        m.put(APP, old * (APP_END - APP))
        self.initial = bytes(m.flash)
        m.make()
        self.sym = m.sym[SLOT]
        m.watch(self.sym['main'], 'main', stop=True)
        vec = SLOTS[SLOT] + 0x200
        sp, pc = struct.unpack_from('<II', m.flash, vec - 0x08000000)
        end = m.go(pc, sp=sp)
        check(end == 'at main', 'slot A start-up ended %r' % end)
        del m.st['log'][:]
        r = m.call(self.sym['uf2_init'])
        check(r is not None, 'uf2_init did not return: %r' % m.st['end'])
        self.sectors = 0

    def sector(self, data, offset=None):
        m = self.m
        data = data.ljust(0x800, b'\x00')
        m.uc.mem_write(BUF, data)
        if offset is None:
            offset = 0x8000 + 0x800 * self.sectors
        self.sectors += 1
        r = m.call(self.sym['uf2_sector'], offset, BUF, 0x800)
        check(r == 0x800, 'uf2_sector returned %r (end %r, viol %r)' % (r, m.st['end'], m.st['viol']))
        check(not m.st['viol'], 'violation %r' % m.st['viol'])

    def send(self, parts):
        for i in range(0, len(parts), 4):
            self.sector(b''.join(parts[i:i + 4]))

    def u(self, off):
        return struct.unpack('<I', bytes(self.m.uc.mem_read(U + off, 4)))[0]

    def state(self):
        return self.u(0), self.u(4), self.u(0x14)

    def done_byte(self):
        return bytes(self.m.uc.mem_read(BOOT_STATE, 1))[0]

    def ops(self):
        return self.m.flash_ops()

    def app(self, n=APP_END - APP):
        return self.m.get(APP, n)

    def in_area(self):
        for op in self.ops():
            check(APP <= op[1] < APP_END, 'flash op outside the application area %r' % (op,))
        check(not [x for x in self.m.st['log'] if x[0] == 'pgerr'], 'PGERR %r'
              % [x for x in self.m.st['log'] if x[0] == 'pgerr'][:3])


def expected_area(image, old=b'\x00'):
    pages = (len(image) + PAGE - 1) // PAGE
    body = image + b'\xff' * (pages * PAGE - len(image))
    return body + old * (APP_END - APP - len(body))


def complete_ok(rig, image, what):
    st = rig.state()
    check(st[0] == 2 and st[2] == (len(image) + 255) // 256, '%s: state %r' % (what, st))
    check(rig.done_byte() == 2, '%s: 0x20000274 = %d' % (what, rig.done_byte()))
    got = rig.app()
    exp = expected_area(image)
    if got != exp:
        k = next(i for i in range(len(exp)) if got[i] != exp[i])
        raise AssertionError('%s: flash differs first at 0x%08X: 0x%02X, expected 0x%02X'
                             % (what, APP + k, got[k], exp[k]))
    rig.in_area()


def not_complete(rig, what, state=None):
    st = rig.state()
    if state is not None:
        check(st[0] == state, '%s: state %r, expected %d' % (what, st, state))
    check(st[0] != 2, '%s: state written' % what)
    check(rig.done_byte() != 2, '%s: completion byte set' % what)
    check(rig.m.word(APP) == 0xFFFFFFFF and rig.m.word(APP + 4) == 0xFFFFFFFF or
          (rig.m.word(APP) == 0 and not rig.ops()), '%s: vector words 0x%08X 0x%08X' %
          (what, rig.m.word(APP), rig.m.word(APP + 4)))


def perm(n, k=769):
    return [(i * k) % n for i in range(n)]


IMAGE = open(VENDOR_APP, 'rb').read()
BLOCKS = make_uf2(IMAGE)
N = len(BLOCKS)
CRC = zlib.crc32(IMAGE)


@case
def u01_in_order_and_cut_property():
    rig = Rig()
    rig.send(BLOCKS[:-4])
    not_complete(rig, 'before the last sector', state=1)
    rig.send(BLOCKS[-4:])
    complete_ok(rig, IMAGE, 'in order')
    ops = rig.ops()
    check(ops[0] == ('erase', APP), 'first op %r' % (ops[0],))
    progs_app0 = [k for k, x in enumerate(ops) if x[0] == 'word' and x[1] == APP]
    check(progs_app0 == [len(ops) - 1], 'word 0x08006000 programmed at ops %r of %d' % (progs_app0, len(ops)))
    vec_ops = [k for k, x in enumerate(ops) if x[0] == 'word' and x[1] < APP + PAGE]
    other = [k for k, x in enumerate(ops) if x[0] == 'word' and x[1] >= APP + PAGE]
    check(min(vec_ops) > max(other), 'vector page words not last')
    addrs = [ops[k][1] for k in vec_ops]
    check(addrs == sorted(addrs, reverse=True), 'vector page not written last word first')
    check(ops[-2] == ('word', APP + 4, struct.unpack_from('<I', IMAGE, 4)[0]), 'op before last %r' % (ops[-2],))
    erases = [x[1] for x in ops if x[0] == 'erase']
    check(erases == [APP + PAGE * i for i in range(151)], 'erases %d, not pages 0..150 once each' % len(erases))
    NOTES.append('u01: %d flash ops (151 erases); word 0x08006000 is the last op; ops before it leave '
                 'it erased (a cut at any of the %d earlier ops leaves 0x08006000 erased)' % (len(ops), len(ops) - 1))
    global INORDER_OPS, INORDER_INITIAL
    INORDER_OPS, INORDER_INITIAL = ops, rig.initial
    return True


@case
def u02_reversed():
    rig = Rig()
    rig.send(BLOCKS[::-1])
    complete_ok(rig, IMAGE, 'reversed')
    return True


@case
def u03_shuffled():
    rig = Rig()
    rig.send([BLOCKS[i] for i in perm(N)])
    complete_ok(rig, IMAGE, 'shuffled')
    return True


def junk_parts():
    apple = struct.pack('>II', 0x00051607, 0x00020000) + b'Mac OS X        ' + bytes(490)
    fat = b'\xeb\x3c\x90MSDOS5.0' + bytes(498) + b'\x55\xaa'
    dirent = b'APP     UF2 \x20' + bytes(19) + b'._APP   UF2 \x20' + bytes(467)
    lcg, x = bytearray(), 12345
    for _ in range(512):
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        lcg.append(x >> 16 & 0xFF)
    bad_end = with_field(BLOCKS[10], 508, 0)
    bad_m1 = with_field(BLOCKS[11], 4, 0)
    parts = [apple[:512], fat[:510].ljust(510, b'\x00') + b'\x55\xaa', dirent, bytes(lcg), b'\xff' * 512,
             bytes(512), bad_end, bad_m1]
    check(all(len(p) == 512 for p in parts), 'junk part not 512 bytes')
    return parts


@case
def u04_mixed_with_non_uf2_data():
    rig = Rig()
    junk = junk_parts()
    parts = []
    for k, i in enumerate(perm(N, 5)):
        parts.append(BLOCKS[i])
        if k % 3 == 0:
            parts.append(junk[k % len(junk)])
    # whole junk sectors as well, and a sector with an odd split: 2 blocks + 2 junk
    rig.sector(b''.join(junk[:4]))
    rig.send(parts)
    rig.sector(b''.join(junk[4:]))
    complete_ok(rig, IMAGE, 'mixed')
    return True


@case
def u05_repeated_blocks():
    rig = Rig()
    parts = []
    for i in range(N):
        parts += [BLOCKS[i], BLOCKS[i]]
        if i % 97 == 0:
            parts += [BLOCKS[0]] * 3
    # same key, other payload, sent after the originals (all in the first half): must be skipped
    alt = [block(i, N, b'\x11' * 256, len(IMAGE), CRC) for i in (0, 1, 9, 100, 500)]
    rig.send(parts[:len(parts) // 2])
    rig.send(alt)
    rig.send(parts[len(parts) // 2:])
    complete_ok(rig, IMAGE, 'repeated')
    return True


@case
def u06_second_file_interleaved():
    other = bytearray(IMAGE[:0x10000])
    other[0x9000] ^= 0xFF
    other = bytes(other)
    ob = make_uf2(other)
    rig = Rig()
    parts = []
    for i in range(max(N, len(ob))):
        if i < N:
            parts.append(BLOCKS[i])
        if i < len(ob):
            parts.append(ob[i])
    rig.send(parts)
    not_complete(rig, 'interleaved block by block', state=1)
    # first half of V1.1, then the whole other file: the other file completes
    rig2 = Rig()
    rig2.send(BLOCKS[:N // 2])
    rig2.send(ob)
    st = rig2.state()
    check(st[0] == 2 and st[2] == len(ob), 'other file after half of V1.1: state %r' % (st,))
    got = rig2.app(len(other))
    check(got == other, 'other file not in flash')
    rig2.in_area()
    # interleaved stream, then V1.1 alone: V1.1 completes
    rig.send(BLOCKS)
    complete_ok(rig, IMAGE, 'V1.1 after the interleaved stream')
    NOTES.append('u06: block-by-block interleaving of two files restarts the transfer at every change '
                 'of key; neither completes, 0x08006000 stays erased (state 1)')
    return True


def refused(parts, what):
    rig = Rig()
    rig.send(parts)
    st = rig.state()
    check(st[0] == 0 and not rig.ops(), '%s: state %r, ops %r' % (what, st, rig.ops()[:3]))
    check(rig.m.word(APP) == 0, '%s: application area touched' % what)
    return rig


@case
def u07_wrong_family():
    refused([with_field(b, 28, FAMILY ^ 1) for b in BLOCKS[:64]], 'family')
    refused([with_field(b, 28, 0) for b in BLOCKS[8:72]], 'family 0')
    return True


@case
def u08_payload_not_256():
    for size in (0, 252, 255, 257, 476, 512):
        refused([with_field(b, 16, size) for b in BLOCKS[:16]], 'payload %d' % size)
    return True


@case
def u09_target_outside_area_or_not_matching():
    L, c = len(IMAGE), CRC
    tests = [
        ('target 0x08062000 (n 1472, count 1473)', [block(1472, 1473, b'\0' * 256, 1473 * 256, 0)]),
        ('target 0x08005F00 for block 0', [block(0, N, IMAGE[:256], L, c, target=0x08005F00)]),
        ('target 0x08005FFC', [block(0, N, IMAGE[:256], L, c, target=0x08005FFC)]),
        ('target 0x08000000', [block(0, N, IMAGE[:256], L, c, target=0x08000000)]),
        ('target 0x08068000 record page', [block(5, N, IMAGE[:256], L, c, target=0x08068000)]),
        ('target 0x08069000 slot F', [block(5, N, IMAGE[:256], L, c, target=0x08069000)]),
        ('target 0x0806F200 slot A image', [block(5, N, IMAGE[:256], L, c, target=0x0806F200)]),
        ('target 0x08006080 unaligned', [block(0, N, IMAGE[:256], L, c, target=0x08006080)]),
        ('target 0x08061F00 for block 5', [block(5, N, IMAGE[:256], L, c, target=0x08061F00)]),
        ('block number = count', [block(N, N, IMAGE[:256], L, c)]),
        ('block number 0xFFFFFFFF', [block(0xFFFFFFFF, N, IMAGE[:256], L, c, target=APP - 256)]),
        ('count 0', [block(0, 0, IMAGE[:256], L, c)]),
        ('count 1473', [block(0, 1473, IMAGE[:256], 1473 * 256, c)]),
    ]
    for name, parts in tests:
        refused(parts, name)
    return True


@case
def u10_settings_page_and_flag_rules():
    L, c = len(IMAGE), CRC
    n_set = (0x0807F000 - APP) // 256
    tests = [
        ('settings page, own block number', [block(n_set, n_set + 1, b'\0' * 256, (n_set + 1) * 256, 0)]),
        ('settings page 0x0807FF00', [block(n_set + 15, n_set + 16, b'\0' * 256, (n_set + 16) * 256, 0)]),
        ('settings page target for block 5', [block(5, N, IMAGE[:256], L, c, target=0x0807F000)]),
        ('flag 0x1 not main flash', [block(0, N, IMAGE[:256], L, c, flags=0xA001)]),
        ('flag 0x1000 file container', [block(0, N, IMAGE[:256], L, c, flags=0xB000)]),
        ('no family flag', [block(0, N, IMAGE[:256], L, c, flags=0x8000)]),
        ('no tag flag', [block(0, N, IMAGE[:256], L, c, flags=0x2000)]),
        ('wrong tag word', [block(0, N, IMAGE[:256], L, c, tag=0x45FB6510)]),
        ('length 0', [block(0, N, IMAGE[:256], 0, c)]),
        ('count != (L + 255) / 256', [block(0, N + 1, IMAGE[:256], L, c)]),
        ('length 0xFFFFFFFF', [block(0, N, IMAGE[:256], 0xFFFFFFFF, c)]),
        ('length 0xFFFFFF01', [block(0, 1, IMAGE[:256], 0xFFFFFF01, c)]),
        ('end magic wrong', [block(0, N, IMAGE[:256], L, c, end=0)]),
    ]
    for name, parts in tests:
        refused(parts, name)
    return True


@case
def u11_crc_mismatch():
    bad = list(BLOCKS)
    b = bytearray(bad[100])
    b[32 + 7] ^= 0x01               # payload changed, key (length, CRC) unchanged
    bad[100] = bytes(b)
    rig = Rig()
    rig.send(bad)
    st = rig.state()
    check(st[0] == 3 and st[1] == 3, 'state %r, expected failed / error 3' % (st,))
    not_complete(rig, 'CRC mismatch', state=3)
    rig.in_area()
    rig.send(BLOCKS[:8])                # failed is final until reset
    check(rig.state()[0] == 3 and rig.m.word(APP) == 0xFFFFFFFF, 'blocks taken after failure')
    return True


@case
def u12_cut_short_then_missing_block():
    rig = Rig()
    rig.send(BLOCKS[:600] + BLOCKS[601:])
    not_complete(rig, 'one block missing', state=1)
    check(rig.state()[2] == N - 1, 'count %r' % (rig.state(),))
    rig.send([BLOCKS[600]])
    complete_ok(rig, IMAGE, 'missing block sent last')
    n = len(rig.ops())
    other = make_uf2(IMAGE[:0x1000])
    rig.send(other)                    # after completion: ignored
    check(len(rig.ops()) == n and rig.state()[0] == 2, 'blocks taken after completion')
    return True


@case
def u13_flash_faults():
    out = []
    def zero_bit(off):              # a bit that is 0 in the image word at off: stuck at 1 it fails
        w = struct.unpack_from('<I', IMAGE, off)[0]
        check(w != 0xFFFFFFFF, 'image word at 0x%X is erased' % off)
        return (~w & (w + 1)) & 0xFFFFFFFF or 1 << next(i for i in range(32) if not w >> i & 1)

    for name, setup, err in (('stuck bit in page 10', lambda m: m.stuck.update({APP + 10 * PAGE + 0x40: zero_bit(10 * PAGE + 0x40)}), 2),
                             ('erase failure of page 20', lambda m: m.erase_fail.add(APP + 20 * PAGE), 1),
                             ('erase failure of the vector page', lambda m: m.erase_fail.add(APP), 1),
                             ('stuck bit in the vector page', lambda m: m.stuck.update({APP + 0x100: zero_bit(0x100)}), 4)):
        rig = Rig()
        setup(rig.m)
        rig.send(BLOCKS)
        st = rig.state()
        out.append((name, st, hex(rig.m.word(APP))))
        check(st[0] == 3 and st[1] == err, '%s: state %r, expected error %d' % (name, st, err))
        check(rig.done_byte() != 2, '%s: completion byte' % name)
        if name != 'erase failure of the vector page':
            check(rig.m.word(APP) == 0xFFFFFFFF and rig.m.word(APP + 4) == 0xFFFFFFFF,
                  '%s: vector words 0x%08X' % (name, rig.m.word(APP)))
        rig.in_area()
    NOTES.append('u13: %r' % out)
    return True


GATE = [(0x08000000, 8), (0x08005FFC, 8), (0x08006000, 0), (0x08006004, 0), (0x08061FFC, 0),
        (0x08062000, 8), (0x08067FFC, 8), (0x08068000, 0), (0x08068FFC, 0), (0x08069000, 8),
        (0x0806F000, 8), (0x0807EFFC, 8), (0x0807F000, 8), (0x0807FFFC, 8), (0x08080000, 8),
        (0x1FFFF800, 8), (0x20000000, 8), (0xFFFFFFFC, 8)]


@case
def u14_flash_gate_every_boundary():
    rig = Rig()
    m, s = rig.m, rig.sym
    for addr, exp in GATE:
        r = m.call(s['flash_gate'], addr)
        check(r == exp, 'flash_gate(0x%08X) = %r, expected %d' % (addr, r, exp))
    for addr, exp in GATE:
        del m.st['log'][:]
        m.call(s['fn_08000efc'])
        m.call(s['fn_08000e24'], addr)
        m.call(s['fn_08000ea4'])
        ops = m.flash_ops()
        if exp == 0:
            check(ops == [('erase', addr & ~(PAGE - 1))] and not m.st['viol'], 'erase 0x%08X: %r %r' % (addr, ops, m.st['viol']))
        else:
            check(ops == [] and not m.st['viol'], 'erase 0x%08X refused expected: %r %r' % (addr, ops, m.st['viol']))
        del m.st['log'][:]
        m.call(s['fn_08000efc'])
        r = m.call(s['fn_08000eb4'], addr, 0x12345678)
        m.call(s['fn_08000ea4'])
        ops = m.flash_ops()
        if exp == 0:
            check(r == 6 and ops == [('word', addr, 0x12345678)], 'word 0x%08X: r %r ops %r' % (addr, r, ops))
        else:
            check(r == 8 and ops == [] and not m.st['viol'], 'word 0x%08X: r %r ops %r %r' % (addr, r, ops, m.st['viol']))
    return True


@case
def u15_power_cut_then_start():
    """Flash replayed from u01's operation log up to each sampled cut, then a start through the
    starter (records: OK A): before the last operation the slot must refuse the application and
    enter update mode; after all operations V1.1's reset vector must be reached."""
    ops, init = INORDER_OPS, INORDER_INITIAL
    blk_last = {}
    for k, x in enumerate(ops):
        if x[0] == 'word' and x[1] >= APP + PAGE:
            blk_last[(x[1] - APP) // 256] = k
    cuts = sorted(set([blk_last[b] for b in range(8, 24)] + [blk_last[b] for b in range(50, N, 50)] +
                      [0, 1] + [len(ops) - 1 - j for j in (512, 300, 100, 2, 1)]))
    reset = struct.unpack_from('<I', IMAGE, 4)[0] & ~1
    from meter_model import Meter as M
    results = []
    for n in cuts + [len(ops)]:
        m = M(records=[(REC0, cell(1, ST_OK, 1))])
        m.flash[:] = init
        s = open(os.path.join(os.path.dirname(BIN2UF2), '..', 'starter', 'build', 'STARTER.bin'), 'rb').read()
        m.flash[0:len(s)] = s
        for x in ops[:n]:
            if x[0] == 'erase':
                m.put(x[1], b'\xff' * PAGE)
            else:
                m.put(x[1], struct.pack('<I', x[2]))
        end = m.boot()
        check(not m.st['viol'], 'cut %d: %r' % (n, m.st['viol']))
        if n < len(ops):
            check(end == 'at slot1 update_loop', 'cut after op %d of %d: end %r' % (n, len(ops), end))
        else:
            check(end == 'app' and m.st['app_pc'] == reset, 'complete: end %r' % end)
        results.append(n)
    NOTES.append('u15: %d starts after cuts at ops %s..%s: update mode; complete: V1.1 reset 0x%08X'
                 % (len(results) - 1, cuts[0], cuts[-1], reset))
    return True


class TimedRig(Rig):
    """Rig with the timing model (meter_model set_timing, LSI 60 kHz: the shortest watchdog period
    2501 * 16 / 60000 = 0.667 s) and a trial start: records INSTALL A, TRIAL A, so slot_trial_wdg
    (slot_10.s; main's first call, called here directly after the stop at `main`) starts the IWDG
    and every slot_feed of the update path reloads it."""

    def __init__(self, lsi=60000, starter=False):
        self.m = Meter(slots=('F', 'A', 'B'), records=[(REC0, cell(1, 1, 1)), (REC0 + 16, cell(1, 2, 2))],
                       starter=starter)
        m = self.m
        m.put(APP, b'\x00' * (APP_END - APP))
        self.initial = bytes(m.flash)
        m.set_timing(lsi_hz=lsi)
        m.make()
        self.sym = m.sym[SLOT]
        m.watch(self.sym['main'], 'main', stop=True)
        vec = SLOTS[SLOT] + 0x200
        sp, pc = struct.unpack_from('<II', m.flash, vec - 0x08000000)
        end = m.go(pc, sp=sp)
        check(end == 'at main', 'slot A start-up ended %r' % end)
        del m.st['log'][:]
        check(m.call(self.sym['slot_trial_wdg']) is not None, 'slot_trial_wdg: %r' % m.st['end'])
        check(m.tm['iw']['running'], 'slot_trial_wdg did not start the IWDG')
        r = m.call(self.sym['uf2_init'])
        check(r is not None, 'uf2_init did not return: %r' % m.st['end'])
        self.sectors = 0


@case
def u16_update_path_feeds_the_watchdog():
    """A whole update (every sector of the V1.1 .uf2 in order, the CRC and vector page of uf2_finish,
    then slot_finish up to the starter's reset entry, which its soft restart slot_soft_restart
    branches to through word 0x00000004 of the boot space) under a running IWDG: no IWDG reset and
    the longest stretch between two counter loads below 0.67 s (USB_CONTROL_DESIGN.md section 6 (e)).
    The state the soft restart leaves is checked by test_chain.py (soft_restart_state). The time
    between two uf2_sector calls is 0 here (direct calls); on the meter the update-mode loop between
    them feeds as well (system_05.s main, slot_feed in every pass)."""
    rig = TimedRig(starter=True)
    m = rig.m
    m.watch(m.starter_sym['reset'], 'starter reset', stop=True)
    rig.send(BLOCKS)
    complete_ok(rig, IMAGE, 'timed update')
    check(m.call(rig.sym['slot_finish']) is None and m.st['end'] == 'at starter reset',
          'slot_finish end %r' % m.st['end'])
    kinds = [e['kind'] for e in m.iwdg_log]
    check('reset' not in kinds, 'IWDG reset during the update')
    st = m.iwdg_stretch()
    longest = st['longest']
    check(longest is not None and longest['seconds'] < 0.67, 'longest stretch %r' % longest)
    NOTES.append('u16: %d feeds; longest stretch %.1f ms (%d instructions) between 0x%08X and 0x%08X'
                 % (kinds.count('feed'), longest['seconds'] * 1e3, longest['insns'],
                    longest['begin']['pc'] or 0, longest['end']['pc'] or 0))
    return True


def main():
    bad = 0
    for fn in CASES:
        try:
            ok = fn()
            msg = ''
        except AssertionError as e:
            ok, msg = False, str(e)
        except Exception as e:      # a failing case must not hide the others
            ok, msg = False, 'raised %r' % e
        print('%-44s %s %s' % (fn.__name__, 'ok' if ok else 'FAIL', msg), flush=True)
        bad += not ok
    for n in NOTES:
        print('  note:', n)
    print('%d tests, %d failed' % (len(CASES), bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
