#!/usr/bin/env python3
"""test_own_ocal.py - the own calibration area of our build (firmware/own/ocal.s, OWN_CAL_DESIGN.md
revision 3, emulator tests o01..o29 of its section 7.1), in the emulator.

Usage (from the repository root, after `make -C starter`, `make -C bootloader slot` and
`make -C firmware own` with the integration edits of ocal_integration.md applied):
    <python with unicorn 2.1.4> tests/test_own_ocal.py [case-name-prefix ...]
o01 also needs the build of the same tree without ocal.s (the commit before the integration, `make
own` there): OCAL_REF=<its firmware/build/own directory> in the environment; without it o01 fails
and says so.

Specification: OWN_CAL_DESIGN.md revision 3 (sections 1, 2, 4, 5, 7.1) with the choices of the
integration (capability bit CAP_OCAL, the MEASURE byte, O_OCAL: read from own.inc / cmd.s below,
not assumed), and the interface comments of firmware/own/ocal.s. Expected values come from those
texts (each case's docstring names the rule), from the slot model of the design (`model_*` below:
the rules of owncal/matrix_check.py, rule G1), from an independent reading of the record format in
Python (`ref_eval` / `ref_active`, design 1.3 step 1..3), or from the window sums the firmware
used (float64 recomputation). Nothing is taken from the firmware's own answer as its expectation.

Rigs:
  - DRig: our image in tests/meter_model.py flash mode 'app' without starter or slots (the
    test_own_save.py style), system memory with the test UID (test_own_control.OwnMeter), the
    eight area pages added to the pages application code may write (until meter_model.py has them,
    ocal_integration.md 10); functions and the command handlers called directly with SP =
    0x200163A8, request payloads at 0x2001E000, answers at 0x2001E401 (odd: the handlers store
    unaligned, as into CT_ANSB + 1). Every erase / program is logged by the model; a store
    outside the model's gate is a violation and ends the call.
  - Ctl: test_own_control.Ctl (mode 'app' with timing, IWDG, USB, the measurement path), the area
    filled through its `patch` hook before the start.

Watches:
  - m15 (o17): UC_HOOK_MEM_WRITE on the settings / calibration RAM 0x2000057C..0x2000118F and on
    OWN_STAGE, plus every store whose PC lies in ocal.s: it must lie in OWN_OCAL or the stack.
  - flash: every logged operation of every case lies in 0x08062000..0x08065FFF, and the settings
    copies A / B and the record pages are compared before and after the cases that write.
  The model has no read watch (unicorn read hooks are not used, meter_model.py header), so o22
  checks the section pointers and the walk's bound instead of the reads themselves.

RUN LIMIT: the cases are 29 runs of this file at most (one per prefix); o21 makes 674 commits in
one DRig (each a small record), o03 / o05 about 150 cut runs.
"""

import cmath
import math
import os
import re
import struct
import subprocess
import sys
import zlib

from unicorn import UC_HOOK_MEM_WRITE, UC_HOOK_CODE
from unicorn.arm_const import (UC_ARM_REG_SP, UC_ARM_REG_R1, UC_ARM_REG_R4, UC_ARM_REG_R5, UC_ARM_REG_PC,
                               UC_ARM_REG_R0)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import test_own_control as T  # noqa: E402
from test_own_control import Ctl, OwnMeter, check, UID, LSI, PERIOD_MIN, stretch_in  # noqa: E402
from meter_model import (SET_A, SET_B, REC0, REC_END, ERASE_CUTS, WORD_CUTS, REPO, APP, OWN_ELF, nm,  # noqa: E402
                         own_image)
from measure_model import DutSource, RANGE_OHM, GAIN  # noqa: E402
from test_own_measure import func_ranges  # noqa: E402

CASES = []
NOTES = []

# ---- constants of own.inc / cmd.s, read from the sources (the integration may move them) ----
OWN = os.path.join(REPO, 'firmware', 'own')


def _equ(name, path):
    m = re.search(r'^\s*\.equ\s+%s,\s*([^@\n]+)' % name, open(path).read(), re.M)
    if m is None:
        raise AssertionError('%s not defined in %s (integration edits applied?)' % (name, path))
    v = m.group(1).strip()
    s = re.fullmatch(r'1\s*<<\s*(\d+)', v)
    return 1 << int(s.group(1)) if s else int(v, 0)


INC = os.path.join(OWN, 'own.inc')
OCAL_BASE, OCAL_SLOT, OCAL_END = _equ('OCAL_BASE', INC), _equ('OCAL_SLOT', INC), _equ('OCAL_END', INC)
OWN_RAM = 0x20018000
OWN_OCAL = OWN_RAM + _equ('O_OCAL', INC)
OCAL_SIZE = _equ('OCAL_SIZE', INC)
OWN_STAGE = OWN_RAM + _equ('O_STAGE', INC)
OWN_MEAS = OWN_RAM + _equ('O_MEAS', INC)
OWN_CTL = OWN_RAM + _equ('O_CTL', INC)
OWN_SAVE = OWN_RAM + _equ('O_SAVE', INC)
CAP_OCAL = _equ('CAP_OCAL', INC)
MEASURE_SIZE = _equ('MEASURE_SIZE', os.path.join(OWN, 'cmd.s'))
OCAL_BYTE = MEASURE_SIZE - 1
OCAL_PAGES = frozenset(range(OCAL_BASE, OCAL_END, 0x800))

# ocal.s state offsets (ocal.s header)
OCS = dict(FLAGS=0x00, ACT=0x04, ASEQ=0x08, OSEQ=0x0C, PRES=0x1C, REJ=0x20, META=0x24, GAIN=0x28, CLIP=0x2C,
           SETTLE=0x30, MON=0x34, BIAS=0x38, TMAX=0x3C, GFREQ=0x40, MFREQ=0x44, LOCK=0x48, LOCKT=0x4C,
           XNEXT=0x50, XTOT=0x54, XCRC=0x58, XON=0x5C, TST=0x60, TKIND=0x64, TTICK=0x68, TCNT=0x6C,
           GFL=0x70, RFL=0x74, RST=0x78, KIND=0x7C, RAW=0xA0, TRACE=0xE0, STAGE=0x2E0)
OF = dict(ACTIVE=1, V0=2, V1=4, NEWER=8, UID=16, SECT=32, RETAKE=64, LOCK=128, XFER=256, TRACE=512)
MAGIC = 0x4C41434F
MAXS = 0xFFFFFFFE
S_OK, S_UNKNOWN, S_BAD, S_NOTNOW, S_BUSY, S_STORAGE, S_SAFETY, S_XCRC = range(8)
FL_OK, FL_GATE, FL_VERIFY = 0, 1, 5
OK2 = struct.pack('<H', 0x4F4B)
FREQS = (100, 120, 1000, 10000, 100000, 60)
LENS = {0: 32, 1: 1992, 2: 64, 3: 84, 4: 28, 5: 4}
GE = 332
NAN = 0x7FC00000

# vendor / control words
V_FREQ, V_LEVEL, V_SCREEN, V_RANGE, V_HOLD = 0x20001144, 0x20001138, 0x20001168, 0x2000114C, 0x200011A4
V_CAL_RUN, V_CAL_TYPE, V_TICK, V_Z, V_THETA = 0x200050E4, 0x200050E0, 0x20000480, 0x200050C4, 0x200050CC
V_C5, V_C6, V_C8 = 0x200011C5, 0x200011C6, 0x200011C8
V_MAX1, V_MIN1, V_MAX2, V_MIN2 = 0x200011CA, 0x200011CC, 0x200011D2, 0x200011D4
USR_TAB = 0x20000B20
CT_FLAGS, CT_J_ACTIVE, CT_J_CMD = OWN_CTL + 0x004, OWN_CTL + 0x0B0, OWN_CTL + 0x0B4
SAVE_FLAGS, SVO_OCAL = OWN_SAVE + 0x00, OWN_SAVE + 0x1C
CF_OFF, CF_OFF_WAIT = 0x02, 0x04
SF_REWRITE_A = 0x40
C_CALIBRATE, C_BOOT_BEGIN = 0x27, 0x85
MO = dict(SETL=0x0C, TSET=0x10, FREQ=0x14, LEVEL=0x18, BIAS=0x1C, SPEED=0x20, SCREEN=0x24, CODES=0x28,
          SEQ=0x2C, K=0x54, SUM=0x6C, TARM=0x08, N=0x3C)
SP_TOP = 0x200163A8
PAY, ANS = 0x2001E000, 0x2001E401
V_BLOCK = 0x2000057C

# commands for the Ctl rig (test_own_control's table, extended here when it lacks them)
T.C.update(OCAL_INFO=0x30, OCAL_READ=0x31, OCAL_WRITE=0x32, OCAL_ROLLBACK=0x33, OCAL_LOCK=0x34, OCAL_RAW=0x35,
           OCAL_TRACE=0x36, MONITOR=0x37)
T_COMMIT = 4.0          # tools/lc1020e.py T_SAVE for the last OCAL_WRITE chunk and OCAL_ROLLBACK (4.3)


def case(fn):
    CASES.append(fn)
    return fn


def u32(b, o=0):
    return struct.unpack_from('<I', b, o)[0]


def f2u(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def u2f(v):
    return struct.unpack('<f', struct.pack('<I', v & 0xFFFFFFFF))[0]


def f32(x):
    return u2f(f2u(x))


# ---------------------------------------------------------------- records (design 1.2)

def section(sid, body):
    return struct.pack('<HH', sid, len(body)) + body


def meta(t=1763769600, note=b'o-test'):
    return section(0, struct.pack('<I', t) + note.ljust(28, b'\0'))


def gain_entry(zm=0, zp=0, nm=0, np_=0, zeta=None, nu=None, pad=0):
    """One frequency of GAIN: masks, pad, zeta[32] (index 8 c8 + c6), nu[8]; factors default 1."""
    zeta = zeta or {}
    nu = nu or {}
    b = struct.pack('<IIBBH', zm, zp, nm, np_, pad)
    for k in range(32):
        z = zeta.get(k, 1 + 0j)
        b += struct.pack('<ff', z.real, z.imag)
    for k in range(8):
        z = nu.get(k, 1 + 0j)
        b += struct.pack('<ff', z.real, z.imag)
    assert len(b) == GE
    return b


def gain(entries):
    """GAIN section from {fi: entry bytes}; absent frequencies all masks 0."""
    return section(1, b''.join(entries.get(fi, gain_entry()) for fi in range(6)))


def clip(table=None):
    """CLIP from {(channel, code): (lo, hi)}, the rest 0 / 4095."""
    table = table or {}
    return section(2, b''.join(struct.pack('<HH', *table.get((ch, c), (0, 4095))) for ch in (0, 1) for c in range(8)))


def settle(table=None):
    """SETTLE from {(kind, fi): ms}, the rest the defaults 26 (kinds 0..4) / 5 (kinds 5, 6)."""
    table = table or {}
    return section(3, b''.join(struct.pack('<H', table.get((k, fi), 26 if k < 5 else 5))
                               for k in range(7) for fi in range(6)))


def monitor(kv):
    """MONITOR from {fi: kV}."""
    mask = sum(1 << fi for fi in kv)
    return section(4, struct.pack('<I', mask) + b''.join(struct.pack('<f', kv.get(fi, 0.0)) for fi in range(6)))


def bias(limit=4, pad=0):
    return section(5, struct.pack('<HH', limit, pad))


def record(body, seq, uid=UID, fmt=1, revoked=False, socrc=0, bad_crc=False):
    """A record as the meter writes it (design 1.2): header 0x38 bytes, revoke word, CRC-32 of bytes
    0x00..0x37 then 0x40..length-1 (zlib.crc32 = the reflected 0xEDB88320 CRC of save.s)."""
    L = 0x40 + len(body)
    h = struct.pack('<IHHII', MAGIC, fmt, 0x40, L, seq) + bytes(uid) + struct.pack('<I', socrc) + bytes(0x18)
    assert len(h) == 0x38
    crc = zlib.crc32(h + body) ^ (1 if bad_crc else 0)
    return h + struct.pack('<II', 0 if revoked else 0xFFFFFFFF, crc) + body


FOREIGN = bytes(range(0x30, 0x3C))


def ref_eval(img):
    """Design 1.3 step 1 on the bytes of a slot: None (no CRC-valid record) or the record's fields."""
    magic, fmt, hs, L, seq = struct.unpack_from('<IHHII', img, 0)
    if magic != MAGIC or hs != 0x40 or not 0x40 <= L <= 0x2000 or L % 4 or seq in (0, 0xFFFFFFFF):
        return None
    if zlib.crc32(img[:0x38] + img[0x40:L]) != u32(img, 0x3C):
        return None
    return dict(own=img[0x10:0x1C] == UID, force=u32(img, 0x38) == 0xFFFFFFFF, fmt=fmt, seq=seq, L=L)


def ref_active(s0, s1):
    """Design 1.3 steps 2..3: (active slot or None, OF_NEWER)."""
    ev = (ref_eval(s0), ref_eval(s1))
    c = [i for i in (0, 1) if ev[i] and ev[i]['own'] and ev[i]['force']]
    if not c:
        return None, False
    n = max(c, key=lambda i: (ev[i]['seq'], -i))
    return (n, False) if ev[n]['fmt'] == 1 else (None, True)


# the slot model of owncal/matrix_check.py (rule G1): a slot is None or (own, fmt, seq, revoked)
def model_load(s):
    c = [i for i in (0, 1) if s[i] and s[i][0] and not s[i][3]]
    if not c:
        return None, False
    n = max(c, key=lambda i: (s[i][2], -i))
    return (n, False) if s[n][1] == 1 else (None, True)


def model_target(s):
    a, _ = model_load(s)
    if a is not None:
        return 1 - a
    e = [i for i in (0, 1) if s[i] is None]
    if e:
        return e[0]
    for cls in (lambda r: not r[0], lambda r: r[0] and r[3]):
        m = [i for i in (0, 1) if cls(s[i])]
        if m:
            return min(m, key=lambda i: s[i][2])
    return 1 if s[0][2] >= s[1][2] else 0


def model_seq(s, T):
    v = [s[i][2] for i in (0, 1) if s[i]]
    q = (max(v) if v else 0) + 1
    if q <= MAXS:
        return q
    r = s[1 - T]
    if r and r[0] and not r[3] and r[2] == MAXS:
        return None
    return r[2] + 1 if r and r[2] < MAXS else 1


# ---------------------------------------------------------------- the direct rig

class DRig:
    """Our build in mode 'app' (no starter, no slots), the area as given, not yet loaded."""

    def __init__(self, s0=None, s1=None, timing=False):
        m = OwnMeter(slots=(), records=(), starter=False, flash_mode='app')
        m.load_own()
        m.app_pages = m.app_pages | OCAL_PAGES
        for i, img in enumerate((s0, s1)):
            if img is not None:
                m.put(OCAL_BASE + i * OCAL_SLOT, img)
        if timing:
            m.set_timing(lsi_hz=LSI)
        m.make()
        self.m, self.s = m, m.app_sym

    def put(self, i, img):
        """Slot i := img + 0xFF (flash bytes only; the next load sees them)."""
        self.m.flash[OCAL_BASE + i * OCAL_SLOT - 0x08000000:OCAL_BASE + (i + 1) * OCAL_SLOT - 0x08000000] = \
            img + b'\xff' * (OCAL_SLOT - len(img))

    def slot(self, i):
        return self.m.get(OCAL_BASE + i * OCAL_SLOT, OCAL_SLOT)

    def call(self, name, *args, r4=None, r5=None, expect_return=True):
        m = self.m
        m.uc.reg_write(UC_ARM_REG_SP, SP_TOP)
        if r4 is not None:
            m.uc.reg_write(UC_ARM_REG_R4, r4)
        if r5 is not None:
            m.uc.reg_write(UC_ARM_REG_R5, r5)
        r = m.call(self.s[name], *args)
        if expect_return:
            check(r is not None, '%s did not return: end %r, violations %r' % (name, m.st['end'], m.st['viol']))
            check(not m.st['viol'], '%s: violation %r' % (name, m.st['viol']))
        return r

    def rd(self, addr, n=4):
        data = bytes(self.m.uc.mem_read(addr, n))
        return struct.unpack('<I', data)[0] if n == 4 else data

    def wr(self, addr, v):
        self.m.uc.mem_write(addr, struct.pack('<I', v) if isinstance(v, int) else v)

    def ocs(self, name):
        return self.rd(OWN_OCAL + OCS[name])

    def load(self):
        self.call('ocal_load')

    def handler(self, name, payload=b'', expect_return=True):
        """A command handler with the cmd.s convention: (status, data) or None when cut."""
        self.wr(PAY, payload + b'\0')
        r = self.call(name, PAY, len(payload), ANS, expect_return=expect_return)
        if r is None:
            return None
        n = self.m.uc.reg_read(UC_ARM_REG_R1)
        return r, self.rd(ANS, n) if n else b''

    def write(self, body, chunk=480, crc=None, expect_return=True):
        """OCAL_WRITE in chunks; returns (status, data) of the first refused or the last chunk."""
        crc = zlib.crc32(body) if crc is None else crc
        off = 0
        while True:
            part = body[off:off + chunk]
            r = self.handler('h_ocal_write', OK2 + struct.pack('<HHI', off, len(body), crc) + part,
                             expect_return=expect_return)
            if r is None or r[0] != S_OK:
                return r
            off += len(part)
            if off >= len(body):
                return r
            check(r[1] == struct.pack('<H', off), 'next offset %r, expected %d' % (r[1], off))

    def ops(self):
        return self.m.flash_ops()

    def clear_log(self):
        del self.m.st['log'][:]

    def keep(self):
        """The bytes no ocal path may change: settings copies A / B, the record pages."""
        return self.m.get(SET_A, 0x1000), self.m.get(SET_B, 0x1000), self.m.get(REC0, REC_END - REC0)


def in_area(op):
    return OCAL_BASE <= op[1] < OCAL_END


def check_ops_in_area(rig, what):
    bad = [x for x in rig.m.st['log'] if x[0] in ('erase', 'word', 'erase-cut', 'word-cut') and not in_area(x)]
    check(not bad, '%s: flash operations outside the area: %r' % (what, bad[:4]))


def info(rig):
    """OCAL_INFO of a DRig as a dict (design 4.2 layout)."""
    st, d = rig.handler('h_ocal_info')
    check(st == S_OK and len(d) == 64, 'OCAL_INFO status %d, %d bytes' % (st, len(d)))
    fl, sl, fm, ln, sq, oq, cr, pr, gf, mf, rj, tm, pad, mt = struct.unpack_from('<IBBHIIIBBBBHHI', d, 0)
    return dict(flags=fl, slot=sl, fmt=fm, len=ln, seq=sq, oseq=oq, crc=cr, pres=pr, gfreq=gf, mfreq=mf, rej=rj,
                tmax=tm, pad=pad, mtime=mt, note=d[32:60], tail=d[60:64])


BODY_META = meta()                              # 36 bytes: the smallest body of these tests
SMALL = BODY_META + clip() + settle()           # 36 + 68 + 88 = 192 bytes, ids 0, 2, 3 ascending (2.4)


def ocal_patch(s0=None, s1=None):
    """Ctl patch: the area pages writable by application code, the slots as given."""
    def p(m):
        m.app_pages = m.app_pages | OCAL_PAGES
        for i, img in enumerate((s0, s1)):
            if img is not None:
                m.put(OCAL_BASE + i * OCAL_SLOT, img)
    return p


def ctl_ocs(rig, name):
    return rig.rd(OWN_OCAL + OCS[name])


def lower_cell(rig):
    """OCAL_LOCK payload of a cell next to the codes now with less gain (one code step down of c5,
    else c6, else c8), so the locked acquisitions do not saturate where the autoranged ones did not."""
    c = rig.rd(V_C5, 5)
    c5, c6, c8 = c[0], c[1], c[3]
    if c5 > 0:
        return bytes((c5 - 1, c6, c8))
    if c6 > 0:
        return bytes((c5, c6 - 1, c8))
    check(c8 > 0, 'no lower cell next to %r' % ((c5, c6, c8),))
    return bytes((c5, c6, c8 - 1))


# ---------------------------------------------------------------- o01

@case
def o01_erased_area_gives_the_stage_1_records():
    """Design 2.6 / o01 (F16): with the area erased, OCAL_INFO reports no record (flags 0, slot 0xFF,
    sequence 0) and the MEASURE records at 1, 2, 3, 4 s equal those of the build without ocal.s
    (OCAL_REF) in bytes 0..3 and 8..63, the float fields within 1e-6 relative (the time field 4..7 is
    the tick of the answer, set by the host's request time, so it is not compared), with byte
    OCAL_BYTE = 0 in ours. Hold on: the
    OCAL_RAW window number keeps rising (a record per window close, design 2.2) while |Z| / theta
    and the MEASURE value fields stay as they were."""
    ref = os.environ.get('OCAL_REF')
    check(ref and os.path.exists(os.path.join(ref, 'APP_OWN.bin')),
          'OCAL_REF (the build directory of the tree without ocal.s) not given or without APP_OWN.bin')
    rigs = []
    for path in (None, ref):
        def p(m, path=path):
            m.app_pages = m.app_pages | OCAL_PAGES
            if path is not None:                     # the image of the build without ocal.s, its symbols
                img, sym = own_image(os.path.join(path, 'APP_OWN.bin'), os.path.join(path, 'app_own.elf'))
                m.put(APP, b'\xff' * (OCAL_BASE - APP))
                m.put(APP, img)
                m.app_sym.clear()
                m.app_sym.update(sym)
        rigs.append(Ctl(source=DutSource('R', 1000.0), patch=p).up())
    ours, theirs = rigs
    inf = ours.ask_ok('OCAL_INFO', size=64)
    check(u32(inf, 0) == 0 and inf[4] == 0xFF and u32(inf, 8) == 0, 'OCAL_INFO of an erased area: %s' % inf.hex())
    # The records are taken at the same emulated times (1..4 s after the start), not by result number,
    # and compared field by field: emulated time is the instruction count (meter_model.py), so the
    # ocal calls of ours move the acquisition starts against the signal phase and the float32 window
    # sums differ in the last bits (2026-11-22, a noisy source made the noise samples fall into other
    # windows: |Z| 1000.012 / 999.990). The noiseless coherent source gives every window the same
    # samples; the floats (main and secondary value, |Z|, theta) agree within 1e-6 relative, every
    # other byte of 0..3 and 8..63 is equal.
    floats = (9, 25, 41, 45, 49 + 4, 57)            # f32 fields of 8..63 (PROTOCOL.md 6.2); 49 is u32
    recs = []
    for rig in rigs:
        got = []
        for _ in range(4):
            rig.run(1.0)
            got.append(rig.ask_ok('MEASURE'))
        recs.append(got)
    for a, b in zip(*recs):
        same = a[0:4] == b[0:4]
        for o in range(8, 64):
            if any(f <= o < f + 4 for f in floats):
                continue
            same = same and a[o] == b[o]
        for f in floats:
            x, y = struct.unpack_from('<f', a, f)[0], struct.unpack_from('<f', b, f)[0]
            same = same and (x == y or abs(x - y) <= 1e-6 * max(abs(x), abs(y)))
        check(same, 'MEASURE differs from the build without ocal.s:\n%s\n%s' % (a[:64].hex(), b[:64].hex()))
        check(len(a) == MEASURE_SIZE and a[OCAL_BYTE] == 0, 'OCAL byte %r' % a[OCAL_BYTE:])
    st, _ = ours.ask('HOLD', b'\x01')
    check(st == S_OK, 'HOLD on: status %d' % st)
    ours.run(0.5)
    z0, th0 = ours.rd(V_Z), ours.rd(V_THETA)
    w0 = u32(ours.ask_ok('OCAL_RAW', size=64), 0)
    m0 = ours.ask_ok('MEASURE')
    ours.run(3.0)
    w1 = u32(ours.ask_ok('OCAL_RAW', size=64), 0)
    m1 = ours.ask_ok('MEASURE')
    check(w1 >= w0 + 2, 'hold: OCAL_RAW windows %d -> %d' % (w0, w1))
    check(ours.rd(V_Z) == z0 and ours.rd(V_THETA) == th0 and m0[8:64] == m1[8:64],
          'hold: published values changed')
    NOTES.append('o01: 4 results equal, hold windows %d -> %d' % (w0, w1))
    return True


# ---------------------------------------------------------------- o02

@case
def o02_write_in_chunks_and_the_sequence():
    """Design 4.1 transfer rules / o02: an out-of-order chunk -> status 2, no data, the transfer as it
    was (OCS_XNEXT unchanged); a chunk at offset 0 restarts it; another total or CRC -> status 2; a
    wrong transfer CRC -> status 7 and 0 flash operations; then the good body three times: target
    rule 1.4 step 1 (b) slot 0 (both erased), sequence 1; (a) the other slot 1, sequence 2; (a)
    slot 0, sequence 3 (step 2: highest + 1). Answer: result 0, active slot, sequence (6 bytes)."""
    rig = DRig()
    rig.load()
    body, crc = SMALL, zlib.crc32(SMALL)
    st, d = rig.handler('h_ocal_write', OK2 + struct.pack('<HHI', 0, len(body), crc) + body[:100])
    check(st == S_OK and d == struct.pack('<H', 100), 'first chunk: %d %r' % (st, d))
    r = rig.handler('h_ocal_write', OK2 + struct.pack('<HHI', 50, len(body), crc) + body[50:100])
    check(r == (S_BAD, b'') and rig.ocs('XNEXT') == 100 and rig.ocs('XON') == 1, 'out of order: %r' % (r,))
    r = rig.handler('h_ocal_write', OK2 + struct.pack('<HHI', 100, len(body) + 4, crc) + body[100:])
    check(r == (S_BAD, b''), 'other total: %r' % (r,))
    r = rig.handler('h_ocal_write', OK2 + struct.pack('<HHI', 100, len(body), crc ^ 1) + body[100:])
    check(r == (S_BAD, b''), 'other CRC: %r' % (r,))
    r = rig.handler('h_ocal_write', OK2 + struct.pack('<HHI', 100, len(body), crc) + body[100:] + b'\0\0\0\0')
    check(r == (S_BAD, b''), 'chunk beyond the total: %r' % (r,))
    st, d = rig.handler('h_ocal_write', OK2 + struct.pack('<HHI', 0, len(body), crc) + body[:100])
    check(st == S_OK and d == struct.pack('<H', 100), 'restart at 0: %d %r' % (st, d))
    rig.clear_log()
    r = rig.write(body, chunk=100, crc=crc ^ 0x5A5A5A5A)
    check(r == (S_XCRC, b'') and not rig.ops(), 'transfer CRC wrong: %r, %d operations' % (r, len(rig.ops())))
    check(rig.handler('h_ocal_write', b'\x4b\x4e' + struct.pack('<HHI', 0, 192, crc) + body[:10]) == (S_BAD, b''),
          'wrong confirmation accepted')
    for n, (slot, seq) in enumerate(((0, 1), (1, 2), (0, 3))):
        r = rig.write(body, chunk=100)
        check(r == (S_OK, struct.pack('<BBI', 0, slot, seq)), 'write %d: %r, expected slot %d seq %d' % (n, r, slot, seq))
        check(rig.ocs('XON') == 0, 'transfer still open after the commit')
    check_ops_in_area(rig, 'o02')
    return True


# ---------------------------------------------------------------- o03

def two_records_rig():
    """Slot 0 own seq 1, slot 1 own seq 2 (active), both SMALL."""
    return DRig(record(SMALL, 1), record(SMALL, 2))


@case
def o03_power_cut_after_and_inside_every_flash_operation():
    """Design 1.4 "Cut at any point" / o03: the third write (target slot 0, sequence 3, previous
    active slot 1) replayed on a fresh flash and cut after every operation n (meter_model
    cut_after) and inside every operation (erase patterns unchanged / ff / mixed / first_half /
    second_half, word patterns unchanged / ff / mixed; the CRC word included). Expected after the
    next load: ref_active of the resulting flash (design 1.3 in Python), which must be slot 1 (the
    previous record) or slot 0 with sequence 3 (the new one), never none; no operation outside the
    area; copies A / B and the record pages unchanged."""
    ref = two_records_rig()
    ref.load()
    keep = ref.keep()
    ref.clear_log()
    r = ref.write(SMALL)
    check(r == (S_OK, struct.pack('<BBI', 0, 0, 3)), 'reference commit %r' % (r,))
    ops = list(ref.ops())
    crc_op = [k for k, x in enumerate(ops) if x[0] == 'word' and x[1] == OCAL_BASE + 0x3C]
    check(len(crc_op) == 1 and crc_op[0] == len(ops) - 1, 'the CRC word is not the last operation: %r' % ops[-3:])
    runs = 0
    for n in range(1, len(ops) + 1):
        x = ops[n - 1]
        pats = [None] + (list(ERASE_CUTS) if x[0] == 'erase' else list(WORD_CUTS))
        for pat in pats:
            rig = two_records_rig()
            rig.load()
            rig.m.cut_pattern = pat
            rig.m.st['cut_after'] = n
            rig.write(SMALL, expect_return=False)
            check_ops_in_area(rig, 'cut %d %s' % (n, pat))
            s0, s1 = rig.slot(0), rig.slot(1)
            exp, _ = ref_active(s0, s1)
            rig.m.make()
            rig.load()
            got = rig.ocs('ACT')
            check(got == (0xFF if exp is None else exp), 'cut %d/%d %s: active %d, expected %r' % (n, len(ops), pat, got, exp))
            check(exp in (0, 1), 'cut %d %s: no record active' % (n, pat))
            if exp == 0:
                check(ref_eval(s0)['seq'] == 3, 'cut %d %s: slot 0 active with sequence %d' % (n, pat, ref_eval(s0)['seq']))
            new_done = n > crc_op[0]                 # the CRC word (op crc_op + 1) completed
            if pat is None:
                check((exp == 0) == new_done, 'cut after op %d: active %r (CRC word op %d)' % (n, exp, crc_op[0] + 1))
            check(rig.keep() == keep, 'cut %d %s: settings copies or records changed' % (n, pat))
            runs += 1
    NOTES.append('o03: %d operations, %d cut runs' % (len(ops), runs))
    return True


# ---------------------------------------------------------------- o04

@case
def o04_stuck_bit_retry_then_status_5():
    """Design 1.4 step 8 / o04: a bit of T + 0x40 that stays 1 (meter_model stuck; the META header
    word 0x00200000 has bit 0 clear) makes flash_word fail its read-back (FL_VERIFY 5) in both
    attempts: 2 erases of slot 0 (one per attempt), status 5 with result 5, the active record
    (slot 1, sequence 2) unchanged and still active."""
    rig = two_records_rig()
    rig.load()
    rig.m.stuck[OCAL_BASE + 0x40] = 1
    rig.clear_log()
    r = rig.write(SMALL)
    check(r == (S_STORAGE, struct.pack('<BBI', FL_VERIFY, 1, 2)), 'stuck bit: %r' % (r,))
    er = [x for x in rig.ops() if x[0] == 'erase']
    check(er == [('erase', OCAL_BASE), ('erase', OCAL_BASE)], 'erases %r' % er)
    check(rig.slot(1)[:0x40 + len(SMALL)] == record(SMALL, 2), 'slot 1 changed')
    check(rig.ocs('ACT') == 1 and rig.ocs('ASEQ') == 2 and rig.rd(SVO_OCAL) == 0, 'state after status 5')
    return True


# ---------------------------------------------------------------- o05

@case
def o05_rollback_modes_order_cuts_and_the_next_target():
    """Design 1.5 / o05 (G2, G4): mode 0 programs the active record's revoke word (slot 1 + 0x38 = 0)
    and slot 0 becomes active (answer slot 0, sequence 1); a following write targets the revoked
    slot 1 (1.4 (a): slot 0 is active) with sequence 3. Mode 1 on two own format-1 records: the
    older (slot 0, sequence 1) revoked first, then slot 1; none active (answer slot 0xFF). A cut
    after the first revoke of mode 1 leaves slot 1 active (the state before, less its rollback
    copy); cuts inside each revoke word (unchanged / ff / mixed): ref_active of the flash. Mode 0
    with none active and mode 1 with nothing qualifying: status 3, no operation."""
    rig = two_records_rig()
    rig.load()
    rig.clear_log()
    r = rig.handler('h_ocal_rollback', OK2 + b'\x00')
    check(r[0] == S_OK and r[1][:5] == struct.pack('<BI', 0, 1), 'mode 0: %r' % (r,))
    check([x for x in rig.ops()] == [('word', OCAL_BASE + OCAL_SLOT + 0x38, 0)], 'mode 0 ops %r' % rig.ops())
    r = rig.write(SMALL)
    check(r == (S_OK, struct.pack('<BBI', 0, 1, 3)), 'write after rollback: %r' % (r,))
    rig = two_records_rig()
    rig.load()
    rig.clear_log()
    r = rig.handler('h_ocal_rollback', OK2 + b'\x01')
    check(r[0] == S_OK and r[1][0] == 0xFF, 'mode 1: %r' % (r,))
    check(rig.ops() == [('word', OCAL_BASE + 0x38, 0), ('word', OCAL_BASE + OCAL_SLOT + 0x38, 0)],
          'mode 1 order %r' % rig.ops())
    r = rig.handler('h_ocal_rollback', OK2 + b'\x01')
    check(r == (S_NOTNOW, b''), 'mode 1 with nothing qualifying: %r' % (r,))
    r = rig.handler('h_ocal_rollback', OK2 + b'\x00')
    check(r == (S_NOTNOW, b''), 'mode 0 with none active: %r' % (r,))
    runs = 0
    for mode, n_ops in ((0, 1), (1, 2)):
        for n in range(1, n_ops + 1):
            for pat in (None,) + tuple(WORD_CUTS):
                rig = two_records_rig()
                rig.load()
                rig.m.cut_pattern = pat
                rig.m.st['cut_after'] = n
                rig.handler('h_ocal_rollback', OK2 + bytes((mode,)), expect_return=False)
                check_ops_in_area(rig, 'rollback cut')
                exp, _ = ref_active(rig.slot(0), rig.slot(1))
                rig.m.make()
                rig.load()
                got = rig.ocs('ACT')
                check(got == (0xFF if exp is None else exp), 'mode %d cut %d %s: active %d expected %r' % (mode, n, pat, got, exp))
                if mode == 1 and n == 1 and pat is None:
                    check(exp == 1, 'mode 1 cut after the first revoke: active %r, expected slot 1' % exp)
                runs += 1
    NOTES.append('o05: %d rollback cut runs' % runs)
    return True


# ---------------------------------------------------------------- o06 / o07

@case
def o06_foreign_uid_records():
    """Design 1.3 step 2 / 1.4 (b), (a) / 1.5 mode 1 (F2, F5): a foreign record alone: no active
    record, OF_UID, the load writes nothing; the next write goes to the empty slot 1 (b) with
    sequence 6 (highest CRC-valid 5 + 1). A newer foreign record (slot 0, sequence 9) next to an own
    older one (slot 1, sequence 2): slot 1 active; the write overwrites slot 0 (a) with sequence 10;
    mode 1 on that state revokes slot 1 only."""
    rig = DRig(record(SMALL, 5, uid=FOREIGN))
    rig.clear_log()
    rig.load()
    i = info(rig)
    check(i['slot'] == 0xFF and i['flags'] & OF['UID'] and not rig.ops(), 'foreign alone: %r' % i)
    check(rig.write(SMALL) == (S_OK, struct.pack('<BBI', 0, 1, 6)), 'write next to a foreign record')
    rig = DRig(record(SMALL, 9, uid=FOREIGN), record(SMALL, 2))
    rig.load()
    check(rig.ocs('ACT') == 1 and rig.ocs('FLAGS') & OF['UID'], 'own record not active next to a foreign one')
    check(rig.write(SMALL) == (S_OK, struct.pack('<BBI', 0, 0, 10)), 'write over the foreign record')
    rig = DRig(record(SMALL, 9, uid=FOREIGN), record(SMALL, 2))
    rig.load()
    rig.clear_log()
    r = rig.handler('h_ocal_rollback', OK2 + b'\x01')
    check(r[0] == S_OK and rig.ops() == [('word', OCAL_BASE + OCAL_SLOT + 0x38, 0)], 'mode 1: %r %r' % (r, rig.ops()))
    check(u32(rig.slot(0), 0x38) == 0xFFFFFFFF, 'the foreign record was revoked')
    return True


@case
def o07_newer_format_2_record():
    """Design 1.3 step 3 / 1.4 (d) / 1.5 (o07): own format 2 sequence 5 (slot 0) newer than own
    format 1 sequence 3 (slot 1): none active, OF_NEWER; a write goes to slot 1 by (d) (lower
    sequence) with sequence 6, which is then active (6 > 5); mode 1 on the first state revokes
    slot 1 only (format 1)."""
    rig = DRig(record(SMALL, 5, fmt=2), record(SMALL, 3))
    rig.load()
    i = info(rig)
    check(i['slot'] == 0xFF and i['flags'] & OF['NEWER'], 'format 2 newer: %r' % i)
    check(rig.write(SMALL) == (S_OK, struct.pack('<BBI', 0, 1, 6)), 'write next to format 2')
    rig = DRig(record(SMALL, 5, fmt=2), record(SMALL, 3))
    rig.load()
    rig.clear_log()
    r = rig.handler('h_ocal_rollback', OK2 + b'\x01')
    check(r[0] == S_OK and rig.ops() == [('word', OCAL_BASE + OCAL_SLOT + 0x38, 0)], 'mode 1: %r' % (rig.ops(),))
    return True


# ---------------------------------------------------------------- o08 / o22 / o23

@case
def o08_unknown_id_and_wrong_length():
    """Design 1.3 step 4 (o08): sections META (0), CLIP (2) with 60 bytes instead of 64, SETTLE (3)
    correct, id 6 (8 bytes, unknown): present bits 0, 2, 3, 6 (0x4D); rejected bit 2; OF_SECT; the
    CLIP pointer the default ocal_def_clip, SETTLE pointing at slot 0 + 0x40 + 36 + 64 + 4 (META
    36 bytes, the 60-byte CLIP section 64, its header 4); T_max 40 (the table's 40 > 26)."""
    body = meta() + section(2, bytes(60)) + settle({(1, 2): 40}) + section(6, bytes(8))
    rig = DRig(record(body, 1))
    rig.load()
    i = info(rig)
    check(i['pres'] == 0x4D and i['rej'] == 0x04 and i['flags'] & OF['SECT'] and i['slot'] == 0, 'INFO %r' % i)
    check(rig.ocs('CLIP') == rig.s['ocal_def_clip'], 'CLIP pointer 0x%08X' % rig.ocs('CLIP'))
    check(rig.ocs('SETTLE') == OCAL_BASE + 0x40 + 36 + 64 + 4, 'SETTLE pointer 0x%08X' % rig.ocs('SETTLE'))
    check(rig.ocs('TMAX') == 40, 'T_max %d (the 40 of the table)' % rig.ocs('TMAX'))
    return True


@case
def o22_section_walk_bounds():
    """Design 1.3 step 4 (F3, o22): a section whose length runs past the record, and descending
    ids: the walk stops (OF_SECT), the sections before stay, nothing after is recorded. With a
    record length L that is a multiple of 4 and section lengths that are multiples of 4 a header
    cannot straddle the end (o + 4 <= L holds whenever o < L), so that variant has no record. The
    model has no read watch; checked instead: every section pointer lies in [slot + 0x44, slot + L)."""
    good = meta() + settle({(0, 0): 30})
    runs = [good + struct.pack('<HH', 4, 400) + bytes(8),             # MONITOR 400 bytes: past the end
            good + bias() + clip()]                                    # 5 then 2: descending
    for body in runs:
        rig = DRig(record(body, 1))
        rig.load()
        i = info(rig)
        check(i['flags'] & OF['SECT'] and i['pres'] & 0x09 == 0x09, 'walk: INFO %r' % i)
        check(rig.ocs('SETTLE') == OCAL_BASE + 0x40 + 36 + 4 and rig.ocs('META') == OCAL_BASE + 0x44,
              'sections before the stop not kept')
        L = 0x40 + len(body)
        for k in ('META', 'GAIN', 'CLIP', 'SETTLE', 'MON', 'BIAS'):
            p = rig.ocs(k)
            check(p == 0 or OCAL_BASE + 0x44 <= p < OCAL_BASE + L or p in (rig.s['ocal_def_clip'],
                  rig.s['ocal_def_settle'], rig.s['ocal_def_bias']), '%s pointer 0x%08X' % (k, p))
    # run 0 stops at MONITOR before any BIAS: the default; run 1 records BIAS (id 5) before the stop at CLIP
    for body, exp in ((runs[0], 'default'), (runs[1], OCAL_BASE + 0x40 + 36 + 88 + 4)):
        rig = DRig(record(body, 1))
        rig.load()
        want = rig.s['ocal_def_bias'] if exp == 'default' else exp
        check(rig.ocs('BIAS') == want and rig.ocs('CLIP') == rig.s['ocal_def_clip'],
              'BIAS 0x%08X (expected 0x%08X), CLIP 0x%08X' % (rig.ocs('BIAS'), want, rig.ocs('CLIP')))
    return True


@case
def o23_values_rejected_at_load():
    """Design 1.3 step 5 (F4, o23): CRC-valid records with SETTLE 65535 and 0, CLIP lo >= hi, a NaN
    and an infinite zeta with its bits set, kV 0 with its bit set: each section rejected (its bit),
    its default in use (CLIP / SETTLE pointers the defaults, GAIN / MONITOR 0), T_max 26. Then the
    record with all of them on the meter (Ctl): a reading of a 1 kohm resistor within 2 s, |Z|
    within 1 ohm (k32's tolerance), and no overload."""
    bad = [(3, settle({(2, 1): 65535})), (3, settle({(6, 0): 0})), (2, clip({(1, 4): (4000, 4000)})),
           (1, gain({2: gain_entry(zm=1, zp=1, zeta={0: complex(float('nan'), 0)})})),
           (1, gain({2: gain_entry(zm=2, zeta={1: complex(float('inf'), 0)})})), (4, monitor({3: 0.0}))]
    for sid, sec in bad:
        body = meta() + sec
        rig = DRig(record(body, 1))
        rig.load()
        i = info(rig)
        check(i['rej'] == 1 << sid and i['flags'] & OF['SECT'], 'section %d: INFO %r' % (sid, i))
        check(rig.ocs('TMAX') == 26 and rig.ocs('GAIN') == 0 and rig.ocs('MON') == 0
              and rig.ocs('CLIP') == rig.s['ocal_def_clip'] and rig.ocs('SETTLE') == rig.s['ocal_def_settle'],
              'section %d: defaults not in use' % sid)
    allbad = meta() + gain({2: gain_entry(zm=1, zp=1, nm=1, np_=1, zeta={0: complex(float('nan'), 0)})}) \
        + clip({(0, 0): (3000, 3000)}) + settle({(1, 2): 0}) + monitor({2: 0.0})
    rig = Ctl(usb=False, source=DutSource('R', 1000.0), patch=ocal_patch(record(allbad, 1))).up()
    t0 = rig.m.now()
    news = []
    rig.m.uc.hook_add(UC_HOOK_MEM_WRITE, lambda uc, a, ad, s, v, u: news.append(rig.m.now()) if v == 1 else None,
                      begin=0x20001200, end=0x20001203)
    rig.run(2.0)
    z = u2f(rig.rd(V_Z))
    check(news and news[0] - t0 <= 2.0 and abs(z - 1000.0) <= 1.0, 'reading %r after %r s' % (z, news[:1]))
    check(ctl_ocs(rig, 'REJ') == 0x1E, 'rejected 0x%X' % ctl_ocs(rig, 'REJ'))
    return True


# ---------------------------------------------------------------- o09

@case
def o09_every_value_rule_once():
    """Design 2.4 / o09: each rule violated once through OCAL_WRITE: status 2 with the section id and
    the entry index (3 bytes; index rules of ocal.s ocal_validate_section: GAIN 41 fi + k, CLIP 8 ch +
    code, SETTLE 6 kind + fi, MONITOR fi or 6 for mask bits above 5, BIAS 0 limit / 1 pad, 0xFFFF a
    structure fault), and 0 flash operations."""
    nan = float('nan')
    cases = [
        (gain({2: gain_entry(pad=1)}), 1, 41 * 2 + 40),
        (gain({0: gain_entry(zm=1 << 5, zeta={5: 2.5 + 0j})}), 1, 5),                 # |m| 6.25 > 4
        (gain({0: gain_entry(zp=1 << 7, zeta={7: 0.45 + 0j})}), 1, 7),                # 0.2025 < 0.25
        (gain({1: gain_entry(nm=1 << 3, nu={3: -1 + 0j})}), 1, 41 + 32 + 3),          # re <= 0
        (gain({4: gain_entry(zm=1, zeta={0: complex(1, nan)})}), 1, 41 * 4),          # NaN
        (gain({5: gain_entry(np_=1 << 6, nu={6: 0.5 + 0.9j})}), 1, 41 * 5 + 38),      # arg > 60 deg
        (clip({(0, 3): (0, 4096)}), 2, 3),
        (clip({(1, 1): (4000, 3000)}), 2, 9),
        (clip({(0, 0): (100, 3700)}), 2, 0),                                           # 3600: not > 3600
        (settle({(1, 1): 0}), 3, 7),
        (settle({(6, 5): 501}), 3, 41),
        (section(4, struct.pack('<I', 0x40) + bytes(24)), 4, 6),
        (monitor({2: 0.0}), 4, 2),
        (monitor({1: 2.0}), 4, 1),
        (bias(0), 5, 0),
        (bias(4, 1), 5, 1),
        (clip() + meta(), 0, 0xFFFF),                                                  # 2 then 0
        (section(3, bytes(80)), 3, 0xFFFF),                                            # SETTLE 80 bytes
    ]
    rig = DRig()
    rig.load()
    for body, sid, idx in cases:
        rig.clear_log()
        r = rig.write(body)
        check(r == (S_BAD, struct.pack('<BH', sid, idx)), 'rule %d / %d: %r' % (sid, idx, r))
        check(not rig.ops(), 'flash operations after a rejected body')
    check(rig.handler('h_ocal_write', OK2 + struct.pack('<HHI', 0, 4, 0) + bytes(4)) == (S_BAD, b''),
          'total 4 accepted')
    return True


# ---------------------------------------------------------------- o10 / o29 (gain)

def cell_bit(c8, c6):
    return 8 * c8 + c6


A5 = {c: cmath.rect(1.0 + 0.004 * c, math.radians(0.3 * c - 0.8)) for c in range(8)}
B86 = {(c8, c6): cmath.rect(1.0 + 0.003 * c8 - 0.002 * c6, math.radians(0.2 * c6 - 0.4 * c8)) for c8 in range(4)
       for c6 in range(8)}


class ErrSource(DutSource):
    """DutSource with complex front-end errors: V codes mid + k G[c5] Re(a[c5] v), I codes
    mid + k G[c6] R[c8] Re(v / (Z b[c8, c6])), so the stage-1 quotient is Z a b and zeta nu =
    1 / (a b) corrects it (zeta = 1 / b, nu = 1 / a). z = the terminal impedance, with residuals."""

    def __init__(self, zfun, **kw):
        super().__init__(kind='R', value=1.0, z=zfun, **kw)

    def samples(self, path, adc, channel, times):
        if adc in (3, 4):
            return super().samples(path, adc, channel, times)
        g = path.generator(times)
        c5, c6, c8 = path.front_end()
        f = path.frequency()
        if adc == 1:
            vals = [self.mid + self.k * GAIN[c5] * (A5[c5] * x).real for x in g]
        else:
            if f <= 0:
                return int(self.mid)
            zz = self.z(f)
            vals = [self.mid + self.k * GAIN[c6] * RANGE_OHM[c8] * (x / (zz * B86[(c8, c6)])).real for x in g]
        return [min(4095, max(0, int(round(v)))) for v in vals]


def full_gain(fi, drop_phase=None, drop_all=None):
    """GAIN calibrating every cell of fi with the injected errors; drop_phase = (c8, c6): that
    zeta's phase bit cleared; drop_all = (c8, c6): both its bits cleared."""
    zm = zp = 0xFFFFFFFF
    if drop_phase:
        zp &= ~(1 << cell_bit(*drop_phase))
    if drop_all:
        zm &= ~(1 << cell_bit(*drop_all))
        zp &= ~(1 << cell_bit(*drop_all))
    zeta = {cell_bit(c8, c6): 1 / B86[(c8, c6)] for c8 in range(4) for c6 in range(8)}
    nu = {c: 1 / A5[c] for c in range(8)}
    return gain({fi: gain_entry(zm, zp, 0xFF, 0xFF, zeta, nu)})


def z_terminal(r=1000.0, zs=0.03 + 2j * math.pi * 1000 * 20e-9, yo=2j * math.pi * 1000 * 2e-12):
    return lambda f: zs + 1 / (1 / r + yo)


def publishes(rig):
    """Hook at meas_tail: the window sums, K and the codes of every publish with |Z| / theta."""
    out = []
    m = rig.m

    def hit(uc, a, size, user):
        b = bytes(uc.mem_read(OWN_MEAS, 0x100))
        out.append(dict(sum=struct.unpack_from('<4f', b, MO['SUM']), k=struct.unpack_from('<f', b, MO['K'])[0],
                        codes=bytes(uc.mem_read(V_C5, 4)), z=u2f(u32(uc.mem_read(V_Z, 4))),
                        th=u2f(u32(uc.mem_read(V_THETA, 4)))))
    a = rig.s['meas_tail'] & ~1
    m.uc.hook_add(UC_HOOK_CODE, hit, begin=a, end=a)
    return out


@case
def o10_gain_correction_on_the_meter():
    """Design 2.1 / o10: ErrSource (injected zeta / nu errors, terminal residuals Zs = 30 mohm +
    j w 20 nH, Yo = j w 2 pF at 1 kHz) and a GAIN for 1 kHz (fi 2) with zeta = 1 / b, nu = 1 / a for
    every cell and all bits. Each publish: |Z|, theta equal |Zx|, arg Zx of the float64
    recomputation Zx = K zeta nu sum V' / sum I' of its window (the published value is |Zdut| of
    S4.1 with the default short 0 / open 1e12, i.e. Zx) within 1e-5 relative / 0.001 deg (float32
    arithmetic); against the terminal impedance within the ADC quantisation bound 0.3 / min(A_V,
    A_I) relative and the same in radians (the worst case of the deterministic rounding error of
    coherent 128-sample sines over the start phase, 0.235 / A, see the comment at qb; the earlier
    0.1 / A treated the rounding as random, which it is not: every window has the same codes), and
    MEASURE byte bit 0 set; meas_interp not called. Then two rigs with GAIN records of equal length:
    (A) fi 2 calibrated except the phase bit of the reached cell, (B) fi 3 only: their published words
    agree within 1e-6 (both take the stage-1 instructions; the instruction-count clock of the model
    shifts the acquisitions by the extra path length, so not bit for bit) and A's MEASURE byte has bit 1, B's none;
    meas_interp called at every publish. Screen 3 with type 0 (the raw value of the store): |Z| =
    |K zeta nu sum V' / sum I'|."""
    zt = z_terminal()
    rig = Ctl(source=ErrSource(zt), patch=ocal_patch(record(meta() + full_gain(2), 1))).up()
    pubs = publishes(rig)
    interp = []
    ia = rig.s['meas_interp'] & ~1
    rig.m.uc.hook_add(UC_HOOK_CODE, lambda uc, a, s, u: interp.append(1), begin=ia, end=ia)
    rig.run(4.0)
    check(len(pubs) >= 3, '%d publishes' % len(pubs))
    raw = rig.ask_ok('OCAL_RAW', size=64)
    av, ai = struct.unpack_from('<ff', raw, 32)
    # quantisation bound: the samples are coherent (128 per period at 1 kHz, the same codes in every
    # period), so the rounding error does not average out between windows; a float64 sweep of the
    # start phase (2000 steps) of two rounded 128-sample sines of 1050.87 / 1047.66 counts gives a
    # phase error of the DFT quotient up to 2.24e-4 rad (median 4.6e-5), i.e. 0.235 / A: 0.3 / A
    qb = 0.3 / min(av, ai)
    zd = zt(1000)
    for p in pubs[1:]:
        c5, c6, c8 = p['codes'][0], p['codes'][1], p['codes'][3]
        sv = complex(p['sum'][0], p['sum'][1])
        si = complex(p['sum'][2], p['sum'][3])
        zx = p['k'] * (1 / B86[(c8, c6)]) * (1 / A5[c5]) * sv / si
        check(abs(p['z'] / abs(zx) - 1) <= 1e-5 and abs(p['th'] - math.degrees(cmath.phase(zx))) <= 1e-3,
              'publish %r vs Zx %r' % ((p['z'], p['th']), zx))
        check(abs(p['z'] / abs(zd) - 1) <= qb and abs(math.radians(p['th']) - cmath.phase(zd)) <= qb,
              'publish %r vs Zterm %r (bound %g)' % ((p['z'], p['th']), zd, qb))
    check(not interp, 'meas_interp called %d times with the gain applied' % len(interp))
    d = rig.ask_ok('MEASURE')
    check(d[OCAL_BYTE] & 1, 'MEASURE OCAL byte 0x%02X' % d[OCAL_BYTE])
    codes = pubs[-1]['codes']
    cell = (codes[3], codes[1])
    words = []
    for rec_body, bit1 in ((meta() + full_gain(2, drop_phase=cell), 2), (meta() + full_gain(3), 0)):
        r2 = Ctl(source=ErrSource(zt), patch=ocal_patch(record(rec_body, 1))).up()
        p2 = publishes(r2)
        n2 = []
        r2.m.uc.hook_add(UC_HOOK_CODE, lambda uc, a, s, u: n2.append(1), begin=ia, end=ia)
        r2.run(4.0)
        words.append([(x['z'], x['th'], x['codes']) for x in p2[:4]])
        m2 = r2.ask_ok('MEASURE')
        check(m2[OCAL_BYTE] & 3 == bit1, 'OCAL byte 0x%02X, expected bits 0..1 = %d' % (m2[OCAL_BYTE], bit1))
        check(len(n2) >= len(p2) >= 3, 'meas_interp %d calls for %d publishes' % (len(n2), len(p2)))
    # Not bit-identical across the two rigs: emulated time is the instruction count (meter_model.py),
    # so A's longer ocal_gain path moves the acquisition starts against the signal phase and the
    # float32 window sums differ in the last bit (2026-11-22: 4th window n = 197 in both, sum Ii
    # 278062.4375 / 278062.40625). Same codes, |Z| and theta within 1e-6 relative (a few ulp).
    check(len(words[0]) == len(words[1]) and all(
        a[2] == b[2] and abs(a[0] / b[0] - 1) <= 1e-6 and abs(a[1] - b[1]) <= 1e-6 * max(1.0, abs(b[1]))
        for a, b in zip(*words)), 'stage-1 values differ: %r / %r' % tuple(words))
    rig.wr(V_CAL_TYPE, 0)
    rig.wr(V_SCREEN, 3)
    del pubs[:]
    rig.run(3.0)
    check(pubs, 'no publish on screen 3')
    p = pubs[-1]
    c5, c6, c8 = p['codes'][0], p['codes'][1], p['codes'][3]
    zx = p['k'] / B86[(c8, c6)] / A5[c5] * complex(*p['sum'][:2]) / complex(*p['sum'][2:])
    check(abs(p['z'] / abs(zx) - 1) <= 1e-5, 'screen 3 raw %r vs %r' % (p['z'], abs(zx)))
    return True


@case
def o29_info_masks_and_measure_bit_1():
    """Design 4.2 / 2.8 (o29): GAIN with fi 0 all bits, fi 1 zeta bits only (nu masks 0), fi 2 zeta
    magnitude bits only, fi 4 one complete cell (8 c8 + c6 = 9, c5 = 2): gain frequencies = fi 0 and 4
    (0x11); with a CLIP failing its rule: sections rejected 0x04, present 0x07. ocal_gain at fi 4
    with the codes c5 2, c6 1, c8 1 (the raw record's): applied (flags 1); with c6 2: present, not
    applied (flags 2, MEASURE byte bit 1 through ocal_meas_flags)."""
    g = gain({0: gain_entry(~0 & 0xFFFFFFFF, 0xFFFFFFFF, 0xFF, 0xFF), 1: gain_entry(0xFFFFFFFF, 0xFFFFFFFF, 0, 0),
              2: gain_entry(0xFFFFFFFF, 0, 0xFF, 0), 4: gain_entry(1 << 9, 1 << 9, 1 << 2, 1 << 2)})
    rig = DRig(record(meta() + g + clip({(0, 0): (0, 100)}), 1))
    rig.load()
    i = info(rig)
    check(i['gfreq'] == 0x11 and i['rej'] == 0x04 and i['pres'] == 0x07, 'INFO %r' % i)
    rig.wr(V_FREQ, 100000)
    for c6, flags in ((1, 1), (2, 2)):
        rig.wr(OWN_OCAL + OCS['RAW'] + 4, bytes((2, c6, 1, 0)))
        r = rig.call('ocal_gain')
        check(r == (flags & 1) and rig.ocs('GFL') == flags, 'c6 %d: r0 %d flags %d' % (c6, r, rig.ocs('GFL')))
    check(rig.call('ocal_meas_flags') & 3 == 2, 'MEASURE flags bit 1')
    return True


# ---------------------------------------------------------------- o11 / o28 (lock)

@case
def o11_lock_forces_codes_and_every_release():
    """Design 2.2 / o11: OCAL_LOCK 3 2 1 on screen 1: within 1 s the codes 0x200011C5 / C6 / C8 are 3,
    2, 1 and from then on no call of fn_0800b20c / fn_0800b000 (code breakpoints); a lock to c5 7,
    c6 0, c8 0 on 1 kohm saturates ADC1 (128 x the V amplitude) and publishes the overload set (|Z|
    1e10). Released (lock word 0) by: a physical key, KEY, a screen change (SCREEN 2), DTR clear,
    a calibration start (0x200050E4 = 1), 30 s without OCAL_LOCK / OCAL_RAW."""
    def locked_rig():
        rig = Ctl(source=DutSource('R', 1000.0), patch=ocal_patch()).up()
        rig.run(1.0)
        st, d = rig.ask('OCAL_LOCK', bytes((3, 2, 1)))
        check(st == S_OK and len(d) == 64, 'OCAL_LOCK: %d' % st)
        return rig
    rig = locked_rig()
    calls = []
    for fn in ('fn_0800b20c', 'fn_0800b000'):
        a = rig.s[fn] & ~1
        rig.m.uc.hook_add(UC_HOOK_CODE, lambda uc, ad, s, u, fn=fn: calls.append(fn), begin=a, end=a)
    rig.run(1.0)
    c = rig.rd(V_C5, 5)
    check((c[0], c[1], c[3]) == (3, 2, 1), 'codes %r' % c)
    del calls[:]
    rig.run(1.0)
    check(not calls, 'ranging calls while locked: %r' % calls[:4])
    check(rig.ask('OCAL_LOCK', bytes((7, 0, 0)))[0] == S_OK, 'lock 7 0 0')
    rig.run(2.0)
    check(rig.rd(V_Z) == 0x501502F9, 'no overload set: |Z| %r' % u2f(rig.rd(V_Z)))
    releases = [('physical key', lambda r: r.press(T.KEY_UP)),
                ('KEY', lambda r: r.ask('KEY', b'\x01')),
                ('SCREEN 2', lambda r: r.ask('SCREEN', b'\x02')),
                ('DTR clear', lambda r: (r.host.set_control_line_state(dtr=False), r.run(0.2))),
                ('calibration start', lambda r: (r.wr(V_CAL_RUN, 1), r.run(0.2))),
                ('30 s', lambda r: r.run(31.0))]
    for what, act in releases:
        rig = locked_rig()
        check(ctl_ocs(rig, 'LOCK') != 0, '%s: not locked' % what)
        act(rig)
        rig.run(0.2)
        check(ctl_ocs(rig, 'LOCK') == 0, '%s: lock not released' % what)
    return True


@case
def o28_lock_with_lcr_set_and_hold():
    """Design 2.2 (F14, o28): locked, LCR_SET frequency (id 2, index 3 = 10 kHz) answers status 0, the
    lock word stays and meas_change runs (kind 0: the restart of ds_freq wins the tie with kind 1,
    both 26 ms by default); LCR_SET range (id 5) answers status 3 and
    0x2000114C stays; HOLD on: OCAL_LOCK still allowed (status 0) and OCAL_RAW's window number rises
    while |Z| stays."""
    rig = Ctl(source=DutSource('R', 1000.0), patch=ocal_patch()).up()
    rig.run(1.0)
    # the cell next to the autoranged one (lower_cell), not a fixed (1, 1, 1): with 1 kohm at 10 kHz
    # that cell saturates both ADCs (2026-11-22: max 4095 / min 0 at every acquisition), so no
    # window closes and OCAL_RAW's number cannot rise under hold
    cell = lower_cell(rig)
    check(rig.ask('OCAL_LOCK', cell)[0] == S_OK, 'lock')
    kinds = []
    a = rig.s['meas_change'] & ~1
    rig.m.uc.hook_add(UC_HOOK_CODE, lambda uc, ad, s, u: kinds.append(uc.reg_read(UC_ARM_REG_R1)), begin=a, end=a)
    lock = ctl_ocs(rig, 'LOCK')
    st, _ = rig.ask('LCR_SET', b'\x02\x03')
    rig.run(0.5)
    # ds_freq (dset.s) stores the frequency and calls fn_08009f10, which clears the restart marker
    # 0x200011FC: meas_watch finds kind 0 (restart) and kind 1 (frequency), both SETTLE 26 by default,
    # and the first found wins the tie (meas_wkind): the settle runs as kind 0 with T 26
    check(st == S_OK and ctl_ocs(rig, 'LOCK') == lock and rig.rd(V_FREQ) == 10000 and 0 in kinds,
          'LCR_SET frequency: %d, frequency %d, kinds %r' % (st, rig.rd(V_FREQ), kinds))
    rng = rig.rd(V_RANGE)
    st, _ = rig.ask('LCR_SET', b'\x05\x02')
    check(st == S_NOTNOW and rig.rd(V_RANGE) == rng, 'LCR_SET range while locked: %d' % st)
    check(rig.ask('HOLD', b'\x01')[0] == S_OK, 'HOLD on')
    rig.run(0.5)
    z0 = rig.rd(V_Z)
    check(rig.ask('OCAL_LOCK', cell)[0] == S_OK, 'lock under hold')
    w0 = u32(rig.ask_ok('OCAL_RAW'), 0)
    rig.run(2.5)
    w1 = u32(rig.ask_ok('OCAL_RAW'), 0)
    check(w1 > w0 and rig.rd(V_Z) == z0, 'hold: windows %d -> %d, |Z| changed %r' % (w0, w1, rig.rd(V_Z) != z0))
    return True


# ---------------------------------------------------------------- o12 / o25 / o26 (settle)

@case
def o12_settle_120_ms_for_kind_6_and_the_t_max_bound():
    """Design 2.3 / o12: SETTLE[6][fi] = 120 for every fi. A code change by a lock: the first
    acquisition used afterwards (meas_win entry, MO_TARM) started at least 130 ms (T + 10, the tick
    step) after the change tick. T_max = 120 (OCS_TMAX). meas_change called directly with a
    deadline pending T_max + 10 = 130 ms ahead keeps it (new deadline now + 15 lies earlier); 131
    ahead counts as passed: the new deadline now + 15."""
    body = meta() + settle({(6, fi): 120 for fi in range(6)})
    rig = Ctl(source=DutSource('R', 1000.0), patch=ocal_patch(record(body, 1))).up()
    check(ctl_ocs(rig, 'TMAX') == 120, 'T_max %d' % ctl_ocs(rig, 'TMAX'))
    rig.run(1.0)
    ev = []
    a = rig.s['meas_change'] & ~1
    rig.m.uc.hook_add(UC_HOOK_CODE, lambda uc, ad, s, u: ev.append(('c', u32(uc.mem_read(V_TICK, 4)),
                      uc.reg_read(UC_ARM_REG_R0), uc.reg_read(UC_ARM_REG_R1))), begin=a, end=a)
    w = rig.s['meas_win'] & ~1
    rig.m.uc.hook_add(UC_HOOK_CODE, lambda uc, ad, s, u: ev.append(('w', u32(uc.mem_read(OWN_MEAS + MO['TARM'], 4)))),
                      begin=w, end=w)
    check(rig.ask('OCAL_LOCK', lower_cell(rig))[0] == S_OK, 'lock')
    rig.run(1.5)
    ch = [k for k, e in enumerate(ev) if e[0] == 'c' and e[3] == 6]
    check(ch and ev[ch[0]][2] == 120, 'kind-6 change %r' % [ev[k] for k in ch[:2]])
    used = [e for e in ev[ch[0] + 1:] if e[0] == 'w']
    check(used and used[0][1] - ev[ch[0]][1] >= 130, 'first used acquisition %r after the change at %d'
          % (used[:1], ev[ch[0]][1]))
    d = DRig(record(body, 1))
    d.load()
    for ahead, kept in ((130, True), (131, False)):
        d.wr(V_TICK, 100000)
        d.wr(OWN_MEAS + MO['SETL'], 1)
        d.wr(OWN_MEAS + MO['TSET'], 100000 + ahead)
        d.call('meas_change', 5, 6, r4=OWN_MEAS, r5=V_BLOCK)
        got = d.rd(OWN_MEAS + MO['TSET'])
        check(got == (100000 + ahead if kept else 100015), 'deadline %d ahead: TSET %d' % (ahead, got))
        check(d.rd(OWN_OCAL + OCS['KIND'], 1)[0] == 6, 'OCS_KIND not stored')
    return True


@case
def o25_settle_at_the_kind_6_sites_and_the_maximum_rule():
    """Design 2.3 (F7, o25): SETTLE[6][fi] = 120. meas_watch (called directly) with a frequency change
    (kind 1, 26 ms) and a code change (kind 6, 120 ms) in one pass: meas_change(120, 6); with
    SETTLE[1][2] = 200: meas_change(200, 1). On the meter: a resistor change 1 kohm -> 100 kohm makes
    the own ranging change codes: every meas_change of kind 6 has T 120; a short (1 mohm, ADC2
    saturated at every code) then 100 ohm (in band at the overload's codes): after the overload set the overload end is a kind-6 change
    with T 120 and the codes as before it (no code change)."""
    t6 = {(6, fi): 120 for fi in range(6)}
    t61 = dict(t6)
    t61[(1, 2)] = 200
    for table, exp in ((t6, (120, 6)), (t61, (200, 1))):
        d = DRig(record(meta() + settle(table), 1))
        d.load()
        d.wr(V_FREQ, 1000)
        d.wr(0x200011FC, 1)                                   # restart marker: no restart
        for k in ('LEVEL', 'BIAS', 'SPEED', 'SCREEN'):
            d.wr(OWN_MEAS + MO[k], d.rd(V_BLOCK + {'LEVEL': 0xBBC, 'BIAS': 0xBC0, 'SPEED': 0xBD4, 'SCREEN': 0xBEC}[k]))
        d.wr(OWN_MEAS + MO['FREQ'], 100)
        d.wr(OWN_MEAS + MO['CODES'], 0x00010203)
        seen = []
        a = d.s['meas_change'] & ~1
        d.m.uc.hook_add(UC_HOOK_CODE, lambda uc, ad, s, u: seen.append((uc.reg_read(UC_ARM_REG_R0),
                        uc.reg_read(UC_ARM_REG_R1))), begin=a, end=a)
        d.call('meas_watch', r4=OWN_MEAS, r5=V_BLOCK)
        check(seen == [exp], 'meas_watch: %r, expected %r' % (seen, exp))
    val = {'r': 1000.0}
    src = DutSource(z=lambda f: complex(val['r'], 0))
    body = meta() + settle({(6, fi): 120 for fi in range(6)})
    rig = Ctl(usb=False, source=src, patch=ocal_patch(record(body, 1))).up()
    rig.run(1.0)
    calls = []
    a = rig.s['meas_change'] & ~1
    rig.m.uc.hook_add(UC_HOOK_CODE, lambda uc, ad, s, u: calls.append((uc.reg_read(UC_ARM_REG_R0), uc.reg_read(UC_ARM_REG_R1),
                      bytes(uc.mem_read(V_C5, 4)))), begin=a, end=a)
    val['r'] = 100000.0
    rig.run(2.0)
    k6 = [c for c in calls if c[1] == 6]
    check(k6 and all(c[0] == 120 for c in k6), 'own ranging: %r' % calls[:6])
    val['r'] = 0.001
    rig.run(2.0)
    check(rig.rd(V_Z) == 0x501502F9, 'short: no overload set')
    del calls[:]
    before = rig.rd(V_C5, 5)
    # 100 ohm, not 1 kohm: at the overload's codes (all 0) a 1 kohm load is in band but the ranging
    # raises c6 at the first unsaturated acquisition, a kind-6 change with new codes that clears
    # MO_OVL (meas_acq .Lac_ranged), so .Lac_unsat never runs; with 100 ohm the codes stay 0 and
    # the overload end is reached (checked 2026-11-22: one call (120, 6) with codes 00000000)
    val['r'] = 100.0
    rig.run(1.0)
    k6 = [c for c in calls if c[1] == 6]
    check(k6 and all(c[0] == 120 for c in k6), 'after the short: %r' % calls[:4])
    # the overload end (meas_acq .Lac_unsat) changes no code: its call sees the codes of the overload;
    # an own ranging change has stored new codes before its call
    check(any(c[2] == before[:4] for c in k6), 'no kind-6 change with the codes of the overload: %r / %r'
          % (k6[:3], before[:4]))
    return True


@case
def o26_frequency_outside_the_list():
    """Design 2.3 / 5 (F8, o26): with a record whose SETTLE holds 77 everywhere, GAIN for every fi
    and MONITOR kV for every fi, and the frequency word 50 Hz: ocal_freq_index 0xFF, ocal_settle 26
    for kinds 0..4 and 5 for kinds 5, 6, ocal_kv 0, ocal_gain 0 with flags 0."""
    body = meta() + gain({fi: gain_entry(0xFFFFFFFF, 0xFFFFFFFF, 0xFF, 0xFF) for fi in range(6)}) \
        + settle({(k, fi): 77 for k in range(7) for fi in range(6)}) + monitor({fi: 0.001 for fi in range(6)})
    d = DRig(record(body, 1))
    d.load()
    d.wr(V_FREQ, 50)
    check(d.call('ocal_freq_index') == 0xFF, 'freq index')
    check([d.call('ocal_settle', k) for k in range(7)] == [26] * 5 + [5, 5], 'settle defaults')
    check(d.call('ocal_kv', 0xFF) == 0, 'kV outside the list')
    check(d.call('ocal_gain') == 0 and d.ocs('GFL') == 0, 'gain outside the list')
    d.wr(V_FREQ, 1000)
    check(d.call('ocal_settle', 1) == 77 and d.call('ocal_kv', 2) == 1, 'in the list')
    return True


# ---------------------------------------------------------------- o13 (clip)

@case
def o13_clip_limits():
    """Design 2.3 S4.5 / o13: with CLIP[0][0].hi = 3995 (lo 300) an acquisition with ADC1 max 4000
    counts is saturated (bit 0); with the defaults only max >= 4095 or min <= 0 count (stage 1),
    for both channels (ADC2 with code c6: CLIP[1][c6])."""
    d = DRig(record(meta() + clip({(0, 0): (300, 3995), (1, 2): (200, 3900)}), 1))
    e = DRig()
    for rig in (d, e):
        rig.load()
    rows = [  # (c5, c6, max1, min1, max2, min2, bits with the record, bits with the defaults)
        (0, 2, 4000, 400, 3000, 1000, 1, 0), (0, 2, 3990, 299, 3000, 1000, 1, 0), (0, 2, 3990, 301, 3901, 1000, 2, 0),
        (0, 2, 3990, 301, 3000, 200, 2, 0), (1, 1, 4095, 5, 3000, 1000, 1, 1), (1, 1, 4094, 0, 4095, 0, 3, 3),
        (1, 1, 4094, 1, 4094, 1, 0, 0)]
    for c5, c6, mx1, mn1, mx2, mn2, b_rec, b_def in rows:
        for rig, exp in ((d, b_rec), (e, b_def)):
            rig.wr(V_C5, bytes((c5, c6)))
            rig.wr(V_MAX1, struct.pack('<HH', mx1, mn1))
            rig.wr(V_MAX2, struct.pack('<HH', mx2, mn2))
            got = rig.call('ocal_clip')
            check(got == exp, 'codes %d/%d, %d %d %d %d: bits %d, expected %d' % (c5, c6, mx1, mn1, mx2, mn2, got, exp))
    return True


# ---------------------------------------------------------------- o14 (monitor)

@case
def o14_level_monitor():
    """Design 5 (F13, o14): without kV: V and I NaN, A_V,ref = A_V / G[c5] and A_I,ref = A_I /
    (G[c6] R[c8]) (|nu| = |zeta| = 1), flags bit 0 clear. With kV[2] = 1e-3 (1 kHz): V = kV A_V,ref,
    I = kV A_I,ref, and I = V / |Z| of the published reading within 1e-5 relative (|Z| = A_V ref R...
    the identity of section 5 in float32), without and with the gain applied (o10's source). A
    short (1 mohm): the overload set, all four NaN and flags bit 2."""
    for gain_body, src in ((b'', DutSource('R', 1000.0)), (full_gain(2), ErrSource(z_terminal()))):
        for kv in (None, 1e-3):
            body = meta() + gain_body + (monitor({2: kv}) if kv else b'')
            rig = Ctl(source=src, patch=ocal_patch(record(body, 1))).up()
            rig.run(3.0)
            d = rig.ask_ok('MONITOR', size=25)
            v, i, avr, air, fl, m1, m2, win = struct.unpack('<ffffBHHI', d)
            raw = rig.ask_ok('OCAL_RAW')
            mon = bytes(rig.rd(OWN_OCAL + 0x80, 0x20))
            c5, c6, c8 = mon[4], mon[5], mon[6]
            a_v, a_i, zze, znu = struct.unpack_from('<ffff', mon, 8)     # OCS_MAV, MAI, MZN, MNU
            exp_avr = f32(f32(a_v * znu) / GAIN[c5])
            exp_air = f32(a_i / f32(f32(GAIN[c6] * RANGE_OHM[c8]) * zze))
            check(f2u(avr) == f2u(exp_avr) and abs(air / exp_air - 1) <= 1e-6, 'refs %r %r vs %r %r' % (avr, air, exp_avr, exp_air))
            if kv is None:
                check(f2u(v) == NAN and f2u(i) == NAN and not fl & 1, 'no kV: %r %r flags %d' % (v, i, fl))
            else:
                z = u2f(rig.rd(V_Z))
                check(fl & 1 and abs(v / (kv * avr) - 1) <= 1e-6 and abs(i / (v / z) - 1) <= 1e-5,
                      'kV: V %r I %r |Z| %r' % (v, i, z))
            check(bool(fl & 2) == bool(gain_body), 'flags bit 1: %d' % fl)
            check(win == u32(mon, 0) and 1 <= win <= u32(raw, 0), 'window %d, snapshot %d, raw %d'
                  % (win, u32(mon, 0), u32(raw, 0)))
    rig = Ctl(source=DutSource('R', 0.001), patch=ocal_patch(record(meta() + monitor({2: 1e-3}), 1))).up()
    rig.run(3.0)
    v, i, avr, air, fl = struct.unpack_from('<ffffB', rig.ask_ok('MONITOR', size=25))
    check(rig.rd(V_Z) == 0x501502F9 and all(f2u(x) == NAN for x in (v, i, avr, air)) and fl & 4,
          'overload: %r %r %r %r flags %d' % (v, i, avr, air, fl))
    return True


# ---------------------------------------------------------------- o15 (trace)

@case
def o15_settle_trace():
    """Design 2.2 / o15: OCAL_TRACE arm (state 1), then a code change (lock) with SETTLE[6] = 40:
    the trace starts at that meas_change (state 2, kind 6, its tick), 32 entries with rising ticks,
    the ones before the deadline marked bit 0 (at least one: 40 ms is several acquisitions), the
    trace full (state 3); read in two answers (start 0: 31 entries, start 31: 1). The window is not
    fed by the marked entries: meas_add is not called between the change and the first unmarked
    entry's tick. SETTLE 40, not 120: at 1 kHz the model makes five acquisitions per 10-ms tick, so
    the 32 entries span 70 ms (2026-11-22: ticks +10..+70) and with 120 every entry was marked."""
    body = meta() + settle({(6, fi): 40 for fi in range(6)})
    rig = Ctl(source=DutSource('R', 1000.0), patch=ocal_patch(record(body, 1))).up()
    rig.run(1.0)
    st, d = rig.ask('OCAL_TRACE', b'\x01')
    check(st == S_OK and d[0] == 1, 'arm: %d %r' % (st, d[:8]))
    adds = []
    a = rig.s['meas_add'] & ~1
    rig.m.uc.hook_add(UC_HOOK_CODE, lambda uc, ad, s, u: adds.append(u32(uc.mem_read(V_TICK, 4))), begin=a, end=a)
    check(rig.ask('OCAL_LOCK', lower_cell(rig))[0] == S_OK, 'lock')
    for _ in range(100):
        rig.run(0.2)
        if ctl_ocs(rig, 'TST') == 3:
            break
    st, d0 = rig.ask('OCAL_TRACE', b'\x02\x00')
    st1, d1 = rig.ask('OCAL_TRACE', b'\x02\x1f')
    check(st == st1 == S_OK and d0[0] == 3 and d0[1] == 6 and d0[6] == 32 and d0[7] == 31 and d1[7] == 1,
          'trace headers %r %r' % (d0[:8], d1[:8]))
    tick0 = u32(d0, 2)
    ent = [struct.unpack_from('<IffBBBB', d0, 8 + 16 * k) for k in range(31)] + [struct.unpack_from('<IffBBBB', d1, 8)]
    ticks = [e[0] for e in ent]
    check(ticks == sorted(ticks) and ticks[0] >= tick0, 'ticks %r' % ticks[:4])
    marked = [e for e in ent if e[3] & 1]
    # a marked acquisition was armed before the deadline (change + 50 ms); its entry is written when
    # it is processed, at most two 10-ms ticks later at 1 kHz (128 samples in one period of 1 ms)
    check(marked and all(e[0] - tick0 < 70 for e in marked), 'marked entries %r' % [(e[0] - tick0, e[3]) for e in ent[:6]])
    check(any(not e[3] for e in ent), 'no unmarked entry: %r' % [(e[0] - tick0, e[3]) for e in ent])
    first_used = next(e[0] for e in ent if not e[3])
    check(not [t for t in adds if tick0 < t < first_used], 'meas_add during the settle: %r' % adds[:4])
    return True


# ---------------------------------------------------------------- o16 (never-brick)

@case
def o16_never_brick_with_the_area_and_a6():
    """Design 1.4 / 2.7 (F15, o16): tests/check_never_brick.py --app passes on the real build (the
    extended gate, A6 admitting ocal.s's defaults, OCAL_BASE and OCAL_END) and its planted controls
    report 0x08066004 and 0x08061FFC by A6 and the store to 0x08062000 from ocal.s by A5 (exit 0
    with every control "found")."""
    p = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'check_never_brick.py'), '--app'],
                       capture_output=True, text=True, timeout=600)
    out = p.stdout
    check(p.returncode == 0 and 'APP_OWN  OK' in out, 'check_never_brick --app:\n%s' % out[-2000:])
    for e in ('A6 flash address 0x08066004', 'A6 flash address 0x08061FFC', 'A5 store to flash 0x08062000 in ocal_planted'):
        check(re.search(r'control app %s\s+found' % re.escape(e), out), 'control %r not found' % e)
    return True


# ---------------------------------------------------------------- o17 (RAM write-watch)

OCAL_FUNCS = ('ocal_eval', 'ocal_scan', 'ocal_pick', 'ocal_target', 'ocal_nextseq', 'ocal_walk', 'ocal_load',
              'ocal_factor_ok', 'ocal_validate_section', 'ocal_validate', 'ocal_find', 'ocal_shopen_crc',
              'ocal_retake', 'ocal_flags', 'ocal_meas_flags', 'ocal_freq_index', 'ocal_settle', 'ocal_clip',
              'ocal_bias_limit', 'ocal_locked', 'ocal_gain_on', 'ocal_gain', 'ocal_kv', 'ocal_mon_get', 'ocal_raw',
              'ocal_sat_note', 'ocal_ovl_note', 'ocal_restart_take', 'ocal_trace_change', 'ocal_trace_on',
              'ocal_trace_add', 'ocal_unlock', 'ocal_step', 'ocal_cal_busy', 'ocal_busy', 'ocal_lock_ok',
              'ocal_revoke', 'ocal_write_rec', 'ocal_socrc_new', 'ocal_event', 'ocal_commit', 'h_ocal_info',
              'h_ocal_read', 'h_ocal_write', 'h_ocal_rollback', 'h_ocal_lock', 'h_ocal_raw', 'ocal_raw_copy',
              'h_ocal_trace')


@case
def o17_ram_write_watch():
    """Design 1.4 "What it never touches", m15 style (o17): from reset, through a session of every
    OCAL command (INFO, READ, WRITE of a GAIN + CLIP + SETTLE body, ROLLBACK 0, LOCK, RAW, TRACE
    arm / read, MONITOR) and 3 s of measurement: no store by code of ocal.s outside OWN_OCAL and the
    stack (0x20010000..0x200163A7, below the vendor stack top), no store at all to OWN_STAGE during
    the OCAL commands, and no store by ocal.s to 0x2000057C..0x2000118F."""
    r = func_ranges(nm(OWN_ELF))
    lo = min(r[f][0] for f in OCAL_FUNCS)
    hi = max(r[f][1] for f in OCAL_FUNCS)
    ansb = OWN_CTL + 0x8A0                           # ctl.inc CT_ANSB: status + 511 answer bytes
    rig = Ctl(source=DutSource('R', 1000.0), patch=ocal_patch())
    bad, stage = [], []

    def any_store(uc, acc, addr, size, value, user):
        pc = uc.reg_read(UC_ARM_REG_PC)
        if lo <= pc < hi and not (OWN_OCAL <= addr < OWN_OCAL + OCAL_SIZE or 0x20010000 <= addr < SP_TOP
                                  or ansb <= addr < ansb + 512):
            bad.append((pc, addr, size))
    rig.m.uc.hook_add(UC_HOOK_MEM_WRITE, any_store, begin=0x20000000, end=0x20023FFF)
    rig.up()
    rig.m.uc.hook_add(UC_HOOK_MEM_WRITE, lambda uc, a, ad, s, v, u: stage.append((uc.reg_read(UC_ARM_REG_PC), ad)),
                      begin=OWN_STAGE, end=OWN_STAGE + 0xC13)
    body = meta() + full_gain(2) + clip() + settle()
    crc = zlib.crc32(body)
    for off in range(0, len(body), 480):
        st, _ = rig.ask('OCAL_WRITE', OK2 + struct.pack('<HHI', off, len(body), crc) + body[off:off + 480], timeout=T_COMMIT)
        check(st == S_OK, 'OCAL_WRITE at %d: %d' % (off, st))
    for name, p in (('OCAL_INFO', b''), ('OCAL_READ', struct.pack('<BHH', 0, 0, 256)), ('OCAL_LOCK', b'\x01\x01\x01'),
                    ('OCAL_RAW', b''), ('OCAL_TRACE', b'\x01'), ('OCAL_TRACE', b'\x02\x00'), ('MONITOR', b''),
                    ('OCAL_LOCK', b'\xff\xff\xff')):
        check(rig.ask(name, p)[0] == S_OK, name)
    check(rig.ask('OCAL_ROLLBACK', OK2 + b'\x00', timeout=T_COMMIT)[0] == S_OK, 'rollback')
    rig.run(3.0)
    check(not bad, 'ocal.s stores outside OWN_OCAL / the stack: %r' % ['0x%08X->0x%08X/%d' % b for b in bad[:6]])
    check(not stage, 'OWN_STAGE written during the OCAL commands: %r' % stage[:4])
    return True


# ---------------------------------------------------------------- o18 (watchdog)

@case
def o18_watchdog_during_a_commit_with_retry():
    """Design 1.4 "Time" (o18): a commit of a GAIN + META record (0x40 + 36 + 1996 = 2096 bytes: 2
    pages) whose first body word has a stuck bit (o04), so both attempts erase 2 pages and fail:
    the longest stretch between two IWDG loads overlapping the request .. answer is below 0.67 s
    (the shortest period, LSI 60 kHz), no IWDG reset; status 5."""
    rig = Ctl(source=DutSource('R', 1000.0), patch=ocal_patch()).up()
    rig.m.stuck[OCAL_BASE + 0x40] = 1
    body = meta() + full_gain(2)
    crc = zlib.crc32(body)
    t0 = rig.m.now()
    st = None
    for off in range(0, len(body), 480):
        st, d = rig.ask('OCAL_WRITE', OK2 + struct.pack('<HHI', off, len(body), crc) + body[off:off + 480], timeout=T_COMMIT)
    t1 = rig.m.now()
    gap = stretch_in(rig.m, t0, t1)
    check(st == S_STORAGE and d[0] == FL_VERIFY, 'status %r %r' % (st, d))
    check(gap < PERIOD_MIN and not [e for e in rig.m.iwdg_log if e['kind'] == 'reset'], 'stretch %.3f s' % gap)
    er = [x for x in rig.m.flash_ops() if x[0] == 'erase']
    check(len(er) == 4, '%d erases (2 pages x 2 attempts)' % len(er))
    NOTES.append('o18: longest stretch %.3f s, commit %.3f s' % (gap, t1 - t0))
    return True


# ---------------------------------------------------------------- o19 (retake)

def short_entry(rig, value):
    """The user table's short magnitude of point 0 (100 Hz, level 0) := value (as a new store would)."""
    rig.wr(USR_TAB, struct.pack('<f', value))


@case
def o19_retake_flag():
    """Design 2.5 (F20, o19): after a write with GAIN, OF_RETAKE (stored CRC = the current one);
    a new short entry clears it. A write of the same GAIN + CLIP after that retake keeps the active
    record's stored CRC (the old one), so OF_RETAKE stays clear; the same write before a retake keeps
    it set."""
    g = meta() + full_gain(2)
    for retake_first, exp in ((True, 0), (False, OF['RETAKE'])):
        rig = DRig()
        rig.load()
        check(rig.write(g)[0] == S_OK, 'GAIN write')
        check(rig.call('ocal_flags') & OF['RETAKE'], 'OF_RETAKE not set after a GAIN write')
        if retake_first:
            short_entry(rig, 0.25)
            check(not rig.call('ocal_flags') & OF['RETAKE'], 'OF_RETAKE not cleared by a new short')
        check(rig.write(g + clip({(0, 0): (100, 4000)}))[0] == S_OK, 'GAIN + CLIP write')
        check(rig.call('ocal_flags') & OF['RETAKE'] == exp, 'retake_first %r: flags 0x%X' % (retake_first, rig.call('ocal_flags')))
    return True


# ---------------------------------------------------------------- o20 / o24 (refusals)

def open_last_chunk(rig, body):
    """All chunks but the last sent; returns the last chunk's payload."""
    crc = zlib.crc32(body)
    cut = len(body) - 8
    check(rig.handler('h_ocal_write', OK2 + struct.pack('<HHI', 0, len(body), crc) + body[:cut])[0] == S_OK, 'first chunk')
    return OK2 + struct.pack('<HHI', cut, len(body), crc) + body[cut:]


@case
def o20_refused_while_a_calibration_runs():
    """Design 4.3 refusal 2 (F6 a, o20): the last OCAL_WRITE chunk, OCAL_ROLLBACK and OCAL_LOCK answer
    status 6 while 0x200050E4 != 0, and while the CALIBRATE job is active (CT_J_ACTIVE 1, CT_J_CMD
    0x27) with 0x200050E4 still 0; no flash operation."""
    for setup in ((V_CAL_RUN, 1), (CT_J_ACTIVE, 1)):
        rig = two_records_rig()
        rig.load()
        rig.wr(V_SCREEN, 1)
        last = open_last_chunk(rig, SMALL)
        rig.wr(*setup)
        if setup[0] == CT_J_ACTIVE:
            rig.wr(CT_J_CMD, C_CALIBRATE)
        rig.clear_log()
        r = (rig.handler('h_ocal_write', last), rig.handler('h_ocal_rollback', OK2 + b'\x00'),
             rig.handler('h_ocal_lock', b'\x01\x01\x01'))
        check(all(x == (S_SAFETY, b'') for x in r) and not rig.ops(), '%r: %r' % (setup, r))
    return True


@case
def o24_refused_by_jobs_rewrite_and_power_off():
    """Design 4.3 refusals 1, 3, 4 (F6 b, c, o24): a BOOT_BEGIN job active -> 4; SF_REWRITE_A -> 4;
    powered-off mode (CF_OFF) and after the power-off path (CF_OFF_WAIT) -> 3; for the last chunk
    and the rollback; 0 flash operations; the transfer still open at the last chunk's offset."""
    for (addr, val), exp in (((CT_J_ACTIVE, 1), S_BUSY), ((SAVE_FLAGS, SF_REWRITE_A), S_BUSY),
                             ((CT_FLAGS, CF_OFF), S_NOTNOW), ((CT_FLAGS, CF_OFF_WAIT), S_NOTNOW)):
        rig = two_records_rig()
        rig.load()
        last = open_last_chunk(rig, SMALL)
        rig.wr(addr, val)
        if addr == CT_J_ACTIVE:
            rig.wr(CT_J_CMD, C_BOOT_BEGIN)
        rig.clear_log()
        r = (rig.handler('h_ocal_write', last), rig.handler('h_ocal_rollback', OK2 + b'\x01'))
        check(all(x == (exp, b'') for x in r) and not rig.ops(), '0x%08X=%d: %r' % (addr, val, r))
        check(rig.ocs('XON') == 1 and rig.ocs('XNEXT') == len(SMALL) - 8, 'transfer not open at its offset')
    return True


# ---------------------------------------------------------------- o21 (slot matrix)

def kinds():
    out = [None]
    for own in (True, False):
        for fmt in (1, 2):
            for rev in (False, True):
                for q in (1, 5, MAXS):
                    out.append((own, fmt, q, rev))
    return out


def slot_img(k, torn=False):
    if k is None:
        return record(BODY_META, 3, bad_crc=True) if torn else b''
    own, fmt, q, rev = k
    return record(BODY_META, q, uid=UID if own else FOREIGN, fmt=fmt, revoked=rev)


@case
def o21_slot_state_matrix():
    """Design 1.4 / 7.1 o21 (F18 a, G6): per slot 25 states (no CRC-valid record, and own / foreign x
    format 1 / 2 x sequence 1 / 5 / 0xFFFFFFFE x in force / revoked), 625 pairs; the pairs with an
    empty slot again with that slot torn (a record with a wrong CRC). Expected per pair from the
    model of owncal/matrix_check.py (rule G1; model_*): the active slot and OF_NEWER after the load,
    the write target and sequence (or status 3). Checked: load as the model; a META write answers
    status 0 with slot = target and sequence = the model's, or status 3 with no flash operation;
    after every commit the new record is active (P4); the target is never the active slot or the
    newest own in-force record (P1, P2); status 3 exactly in the pairs where the slot that is not
    the target holds an own in-force record with 0xFFFFFFFE (96 pairs)."""
    K = kinds()
    rig = DRig()
    refused = runs = 0
    for torn in (False, True):
        for k0 in K:
            for k1 in K:
                if torn and k0 is not None and k1 is not None:
                    continue
                s = [k0, k1]
                rig.put(0, slot_img(k0, torn))
                rig.put(1, slot_img(k1, torn))
                rig.wr(OWN_OCAL, bytes(OCAL_SIZE))
                rig.load()
                a, newer = model_load(s)
                got_a = rig.ocs('ACT')
                check(got_a == (0xFF if a is None else a) and bool(rig.ocs('FLAGS') & OF['NEWER']) == newer,
                      '%r: active %d newer %d, model %r %r' % (s, got_a, rig.ocs('FLAGS') & 8, a, newer))
                T_ = model_target(s)
                q = model_seq(s, T_)
                own_if = [i for i in (0, 1) if s[i] and s[i][0] and not s[i][3]]
                N = max(own_if, key=lambda i: (s[i][2], -i)) if own_if else None
                check(T_ != a and T_ != N, '%r: model target %d hits the active / newest' % (s, T_))
                rig.clear_log()
                r = rig.write(BODY_META)
                if q is None:
                    refused += not torn
                    o = s[1 - T_]
                    check(o and o[0] and not o[3] and o[2] == MAXS, '%r: refusal outside the G1 case' % s)
                    check(r == (S_NOTNOW, b'') and not rig.ops(), '%r: %r, expected status 3' % (s, r))
                else:
                    check(r == (S_OK, struct.pack('<BBI', 0, T_, q)), '%r: %r, expected slot %d seq %d' % (s, r, T_, q))
                    check(rig.ocs('ACT') == T_, '%r: not active after the commit' % s)
                check_ops_in_area(rig, 'o21')
                runs += 1
    check(refused == 96, '%d status-3 pairs, expected 96' % refused)
    NOTES.append('o21: %d pairs, %d refused' % (runs, refused))
    return True


# ---------------------------------------------------------------- o27 (65 / 66-byte records)

@case
def o27_measure_records_carry_the_ocal_byte():
    """Design 2.8 (F18 e, o27): MEASURE, LCR_SET and the MEASURE_STREAM frames carry MEASURE_SIZE
    bytes (cmd.s, 66 with the integration); INFO's capability word has CAP_OCAL. Noise 1 lsb: windows
    with equal bits are one result (ctl.s .Ld_meas), so a noiseless source streams no frame in mode 0."""
    rig = Ctl(source=DutSource('R', 1000.0, noise_lsb=1.0), patch=ocal_patch()).up()
    rig.run(1.5)
    check(u32(rig.ask_ok('INFO'), 1) & CAP_OCAL, 'CAP_OCAL not set')
    check(len(rig.ask_ok('MEASURE')) == MEASURE_SIZE, 'MEASURE size')
    st, d = rig.ask('LCR_SET', b'\x02\x02')
    check(st == S_OK and len(d) == MEASURE_SIZE, 'LCR_SET answer %d bytes' % len(d))
    check(rig.ask('MEASURE_STREAM', b'\x00\x00')[0] == S_OK, 'MEASURE_STREAM')
    fr = [f for f in rig.drain(3.0) if f['type'] == T.FR_STREAM and f['cmd'] == T.C['MEASURE']]
    check(fr and all(len(f['payload']) == MEASURE_SIZE for f in fr), 'stream frames %r' % [len(f['payload']) for f in fr])
    rig.ask('MEASURE_STREAM', b'\xff\xff')
    return True


def main():
    sel = sys.argv[1:]
    bad = run = 0
    for fn in CASES:
        if sel and not any(fn.__name__.startswith(p) for p in sel):
            continue
        run += 1
        try:
            ok = fn()
            msg = ''
        except AssertionError as e:
            ok, msg = False, str(e)
        except Exception as e:      # a failing case must not hide the others
            ok, msg = False, 'raised %r' % e
        print('%-52s %s %s' % (fn.__name__, 'ok' if ok else 'FAIL', msg), flush=True)
        bad += not ok
    for n in NOTES:
        print('  note:', n)
    print('%d tests, %d failed' % (run, bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
