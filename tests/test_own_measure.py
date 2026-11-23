#!/usr/bin/env python3
"""test_own_measure.py - the measurement core of our build (firmware/own/meas.s, MEASUREMENT_FIX_DESIGN.md
revision 4, stage 1: S1.1..S1.9, tests of section 5.1), in the emulator.

Usage (from the repository root, after `make -C starter`, `make -C bootloader slot`, `make -C firmware`
(build/app.elf: the vendor build V1.1, byte-identical by `make check`) and `make -C firmware own`):
    <python with unicorn 2.1.4> tests/test_own_measure.py [case-name-prefix ...]

Rigs:
  - our build: tests/test_own_control.py Ctl (meter_model flash mode 'app' with timing, KeyPad,
    MeasurePath, UsbDevice / UsbHost), imported, not changed; usb=False unless a case talks to the host;
  - the vendor build V1.1 (VRig below): vendor/LC1020E_V1.1_250702.bin at 0x08006000 in the same chip model
    with KeyPad, MeasurePath and UsbDevice, the settings copy at 0x0807F000 (V1.1 copies 0xC14 bytes from
    there, copy_flash_block_to_ram), symbols from firmware/build/app.elf.
The settings come from test_own_control.block_with() (the block 0x0800B4C8(1) writes on a first start:
short entries 0, breakpoints 0.01 .. 1e7, so the decade interpolation is the identity up to float
rounding) with the words a case names; copy A holds it (sequence 2), copy B the same (sequence 1).

Signal sources (test side, measure_model.DutSource extended as the design's "Model extensions" ask):
  - DutSource: a device under test, z(f) (measure_model.py);
  - TDut: z(f, t), a part that changes at a time; per-channel adc mid (mid_v / mid_i, "adc_mid per
    channel"); a function that may replace the ADC2 codes;
  - AmpSource: the codes set in counts: V = mid + A_V0 * g5(c5) * Re(gn(t)), I = mid + A_I0 * g6(c6) *
    (R[c8] / 100) * Re(gn(t) exp(-j theta)), gn = the generator's analytic signal normalised to 1 (so
    the published Z is 100 * A_V0 / A_I0 * exp(j theta) ohm with the vendor gain tables), g5(c) = 2^c,
    g6(c) = (2 (1 + gain_err))^c ("gain_err, a per-code factor on G[c6]"), uniform noise +- noise_lsb
    on both channels (fixed pseudo-random sequence, as DutSource).

Probes (hooks of this file, Probe below), each record with the emulated time:
  - publishes: our build: the store of 1 to 0x20001200 in meas_tail (every output word is written by
    then); the vendor build: its bl fn_0800f854 at 0x0800A794 (the end of fn_0800a068's publish);
    the output words, 0x200011F4 (the window's N) and the O_MEAS state (sums, K, class, first tick);
  - acquisitions used (our build): the entry of meas_win (after step 3): both buffers, MO_X, MO_SIG,
    MO_S1, the codes, G;
  - additions to the window: the entry of meas_add (the slot: V, I, Zm; the reference channel, K, the
    class); meas_reset clears the list (so a publish carries exactly its window's additions);
  - re-arms: own_dma_rearm for DMA1 channel 1 (G after it); own re-arm requests: meas_arm;
  - m15, the factory-table write-watch (TableWatch), armed from reset in every case: a
    UC_HOOK_MEM_WRITE on 0x20000580..0x20000B1F and one on the user table 0x20000B20..0x200010BF, each
    write with PC, LR, address and size; the expected writers of the design's 5.1 m15, plus one the
    design's list lacks (found by this watch, recorded in its revision 5): at reset __scatterload's
    region-table entry 1 (0x0804F190, 0x2000057C, 0x15E2C, zero_fill_words) clears 0x2000057C..
    0x200163A7 before main, RAM only, before own_load.

Expected values come from the specification text, the DUT model (z) or the captured buffers (float64
recomputation), each named per check. RUN LIMIT: the cases are 18 runs of this file at most (one per
case prefix); the cases themselves start at most a few rigs each.
"""

import cmath
import math
import os
import struct
import sys
import zlib

from unicorn import UC_HOOK_MEM_WRITE, UC_HOOK_CODE
from unicorn.arm_const import (UC_ARM_REG_PC, UC_ARM_REG_LR, UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R6,
                               UC_ARM_REG_SP)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_own_control as T  # noqa: E402
from test_own_control import Ctl, KeyPad, check, f32, block_with, copy_image  # noqa: E402
from meter_model import Meter, VENDOR_APP, SET_A, SET_B, nm, REPO  # noqa: E402
from measure_model import MeasurePath, DutSource, TIM1, TIM6, RANGE_OHM, GAIN  # noqa: E402
from usb_host import UsbDevice  # noqa: E402

CASES = []
NOTES = []
V11_ELF = os.path.join(REPO, 'firmware', 'build', 'app.elf')

# ---- own.inc / meas.s ----
OWN_MEAS = 0x20018000 + 0x5EE0
MO = dict(G=0x00, GEXP=0x04, TARM=0x08, SETL=0x0C, TSET=0x10, CODES=0x28, SEQ=0x2C, CLS=0x30, OVL=0x34,
          CLSN=0x38, N=0x3C, PH=0x40, ST=0x44, REF=0x48, DROP=0x4C, TFIRST=0x50, K=0x54, ZREF=0x58, MU=0x60,
          M2=0x68, SUM=0x6C, KAH=0x7C, BUF=0x8C, X=0xD4, SIG=0xEC, S1=0xF4, FL=0xFC)
# ---- vendor RAM words (own.inc, meas.s) ----
V_BLOCK, BLK = 0x2000057C, 0xC14
V_LEVEL, V_BIAS, V_FREQ, V_RANGE, V_SPEED, V_CIRCUIT = 0x20001138, 0x2000113C, 0x20001144, 0x2000114C, 0x20001150, 0x20001154
V_SCREEN, V_CMP_TYPE, V_HOLD, V_FACTORY, V_MENU, V_DIALOG = 0x20001168, 0x20001178, 0x200011A4, 0x200011C0, 0x200011A8, 0x200011AC
V_C4, V_C5, V_C6, V_C8 = 0x200011C4, 0x200011C5, 0x200011C6, 0x200011C8
V_RING, V_MARK, V_NEW, V_NR, V_NRCNT = 0x200011F4, 0x200011FC, 0x20001200, 0x20001208, 0x2000120C
V_SERPAR, V_TICK, V_CAL_TYPE, V_CAL_RUN, V_KEY_CODE = 0x200011EC, 0x20000480, 0x200050E0, 0x200050E4, 0x20001192
V_BUF_V, V_BUF_I = 0x20005A38, 0x20005B38
FAC_LO, FAC_HI = 0x20000580, 0x20000B20          # factory table [lo, hi)
USR_LO, USR_HI = 0x20000B20, 0x200010C0          # user table [lo, hi)
WORDS = dict(ZRAW=0x20005090, THRAW=0x20005094, XS=0x20005098, XP=0x2000509C, RS=0x200050A0, RP=0x200050A4,
             CS=0x200050A8, CP=0x200050AC, LS=0x200050B0, LP=0x200050B4, R=0x200050B8, C=0x200050BC,
             L=0x200050C0, Z=0x200050C4, X=0x200050C8, TH=0x200050CC, Q=0x200050D0, D=0x200050D4,
             CMPV=0x200050DC)
OUT = ('Z', 'X', 'TH', 'R', 'C', 'L', 'Q', 'D', 'RS', 'XS', 'RP', 'XP', 'CS', 'CP', 'LS', 'LP')
F_1E10, F_M400, F_INF = 0x501502F9, 0xC3C80000, 0x7F800000
KEY_OK, KEY_DOWN, KEY_4, KEY_HOLD, KEY_FUNC, KEY_PC11, KEY_PE0 = 0x0008, 0x0020, 0x0004, 0x0400, 0x0200, 0x0040, 0x2000
VENDOR_PUBLISH = 0x0800A794       # fn_0800a068: bl fn_0800f854 (measure_33.s .L0800a794)
MAIN_LOOP = 0x080281C8            # system_40.s .L080281c8
FREQS = (100, 120, 1000, 10000, 100000)


def case(fn):
    CASES.append(fn)
    return fn


def u32f(v):
    return struct.unpack('<f', struct.pack('<I', v & 0xFFFFFFFF))[0]


def f2u(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def kbin(f):
    """The DFT bin of S1.2: k = 1 below 10 kHz, 4 below 100 kHz, else 16 (fn_08007e7c's thresholds)."""
    return 1 if f < 10000 else 4 if f < 100000 else 16


def dft64(x, k):
    """S1.2 in float64 on the 128 codes: X of (x - mean) at bin k, sigma^2 of the residual / 125."""
    m = sum(x) / 128.0
    X = sum((x[n] - m) * cmath.exp(-2j * math.pi * k * n / 128) for n in range(128))
    e = [(x[n] - m) - (X * cmath.exp(2j * math.pi * k * n / 128)).real / 64 for n in range(128)]
    return X, sum(v * v for v in e) / 125.0


def window_z(adds):
    """K * sum(V u) / sum(I u) in float64 from the additions of one window (S1.3, u of the reference)."""
    sv = si = 0j
    for a in adds:
        r = a['v'] if a['ref'] == 0 else a['i']
        u = 1 if abs(r) == 0 else r.conjugate() / abs(r)
        sv += a['v'] * u
        si += a['i'] * u
    return adds[-1]['k'] * sv / si


def interp64(entry, s):
    """The decade interpolation of fn_0800a068 (measure_33.s .L0800a376..) in float64; entry = the 12
    floats of the table entry (short, b1..b10, open)."""
    b = entry[1:11]
    if s < b[0]:
        return s / b[0] * 0.01
    for k in range(1, 10):
        if k == 9 or s < b[k]:
            base = 0.01 * 10 ** (k - 1)
            return (s - b[k - 1]) * 9 * base / (b[k] - b[k - 1]) + base
    raise AssertionError('unreachable')


def entry_addr(freq, level_bits):
    """fn_080090a4: the user-table entry of a frequency and a level (measure_32.s header)."""
    i = FREQS.index(freq) if freq in FREQS else None
    if i is None:
        return 0x20000B20
    j = 0 if level_bits < 0x3E4CCCCD else 1 if level_bits < 0x3F000000 else 2
    return 0x2000057C + 0x90 * i + 0x30 * j + 0x5A4


# ---------------------------------------------------------------- sources

class TDut(DutSource):
    """DutSource with z(f, t) (zt), per-channel adc mid (mid_v, mid_i) and an optional replacement of the
    ADC2 codes (i_codes(times) -> list or int)."""

    def __init__(self, zt, mid_v=2048.0, mid_i=2048.0, i_codes=None, **kw):
        super().__init__(kind='R', value=1.0, **kw)
        self.zt, self.mid_v, self.mid_i, self.i_codes = zt, mid_v, mid_i, i_codes

    def z(self, f):
        return complex(self.zt(f, 0.0))

    def samples(self, path, adc, channel, times):
        if adc in (3, 4):
            return super().samples(path, adc, channel, times)
        if adc == 2 and self.i_codes is not None:
            return self.i_codes(times)
        g = path.generator(times)
        c5, c6, c8 = path.front_end()
        f = path.frequency()
        if adc == 1:
            vals = [self.mid_v + self.k * GAIN[c5] * x.real for x in g]
        else:
            if f <= 0:
                return int(self.mid_i)
            vals = [self.mid_i + self.k * GAIN[c6] * RANGE_OHM[c8] * (x / complex(self.zt(f, t))).real
                    for x, t in zip(g, times)]
        if self.noise:
            vals = [v + self._noise() for v in vals]
        return [int(round(v)) for v in vals]


class AmpSource(DutSource):
    """Codes set in counts (module docstring); a_i0 / theta may be functions of the time."""

    def __init__(self, a_v0, a_i0, theta_deg, noise_lsb=0.0, gain_err=0.0, adc3=2048):
        super().__init__(kind='R', value=1.0, noise_lsb=noise_lsb, adc3=adc3)
        self.a_v0, self.a_i0, self.theta, self.gain_err = a_v0, a_i0, theta_deg, gain_err

    def samples(self, path, adc, channel, times):
        if adc in (3, 4):
            return super().samples(path, adc, channel, times)
        g = path.generator(times)
        c5, c6, c8 = path.front_end()
        amp = abs(g[0]) if g and abs(g[0]) > 0 else 0.0
        if amp == 0.0:
            return 2048
        out = []
        for x, t in zip(g, times):
            gn = x / amp
            if adc == 1:
                v = 2048.0 + self.a_v0 * 2 ** c5 * gn.real
            else:
                a = self.a_i0(t) if callable(self.a_i0) else self.a_i0
                th = self.theta(t) if callable(self.theta) else self.theta
                v = 2048.0 + a * (2 * (1 + self.gain_err)) ** c6 * RANGE_OHM[c8] / 100.0 * \
                    (gn * cmath.exp(-1j * math.radians(th))).real
            if self.noise:
                v += self._noise()
            out.append(int(round(v)))
        return out


# ---------------------------------------------------------------- rigs

def settings(**words):
    """A settings block from block_with() with the given words (name -> value, names of this file)."""
    names = dict(freq=V_FREQ, level=V_LEVEL, speed=V_SPEED, range=V_RANGE, circuit=V_CIRCUIT)
    return block_with(**{'0x%08x' % names[k]: v for k, v in words.items()})


def own_rig(source, block=None, usb=False, keys_at_start=0, **words):
    """Our build with the settings block (block or settings(**words)) in copies A and B, the table watch
    and the probe armed from reset, run to the main loop."""
    blk = block if block is not None else settings(**words)
    rig = Ctl(a=copy_image(blk, 2), b=copy_image(blk, 1), usb=usb, source=source)
    rig.block = blk
    rig.vendor = False
    rig.watch = TableWatch(rig)
    rig.probe = Probe(rig)
    if keys_at_start:
        start_keys(rig, keys_at_start)
    rig.up()
    return rig


def start_keys(rig, mask):
    """Keys held at power-on (system_40.s 486-504: PC11 -> 0x200011C0 = 1, PE6 and PE0 -> 2), released
    once the start-up has read them; a hold toggled by the release of key 0x400 is switched off again."""
    rig.keys.down = mask
    end = rig.m.run_for(seconds=5.0, until=lambda m: rig.rd(V_FACTORY) != 0)
    check(end is None and rig.rd(V_FACTORY) != 0, 'factory mode not entered: %r' % end)
    rig.keys.down = 0


class VRig:
    """The vendor build V1.1 in the same chip model (module docstring)."""

    def __init__(self, source, block=None, keys_at_start=0, **words):
        blk = block if block is not None else settings(**words)
        m = Meter(slots=(), records=(), starter=False, flash_mode='app', app=open(VENDOR_APP, 'rb').read())
        m.put(SET_A, copy_image(blk, 2))
        m.put(SET_B, copy_image(blk, 1))
        m.set_timing(lsi_hz=T.LSI, cpi=5)
        self.m, self.s, self.block, self.vendor = m, nm(V11_ELF), blk, True
        self.keys = m.attach(KeyPad())
        self.meas = m.attach(MeasurePath(source))
        UsbDevice(m)
        m.start_app()
        self.watch = TableWatch(self)
        self.probe = Probe(self)
        self.loop_seen = False

        def loop(uc, a, size, u):
            self.loop_seen = True
        m.uc.hook_add(UC_HOOK_CODE, loop, begin=MAIN_LOOP, end=MAIN_LOOP)
        if keys_at_start:
            start_keys(self, keys_at_start)
        end = m.run_for(seconds=8.0, until=lambda mm: self.loop_seen)
        check(end is None and self.loop_seen, 'V1.1: main loop not reached (%r, %r)' % (end, m.st['viol']))

    def rd(self, addr, n=4):
        data = bytes(self.m.uc.mem_read(addr, n))
        return struct.unpack('<I', data)[0] if n == 4 else data

    def rd8(self, addr):
        return self.rd(addr, 1)[0]

    def rd16(self, addr):
        return struct.unpack('<H', self.rd(addr, 2))[0]

    def wr(self, addr, v):
        self.m.uc.mem_write(addr, struct.pack('<I', v) if isinstance(v, int) else v)

    def run(self, seconds):
        end = self.m.run_for(seconds)
        check(end is None, 'V1.1 run ended %r (violations %r)' % (end, self.m.st['viol']))

    def run_end(self, seconds):
        """The run for `seconds`; returns its end reason (None while the chip still runs), no check:
        for controls where V1.1 is known to stop (the re-arm race of fn_080085d0, NOTES "Measurement
        path in the emulator": a channel enabled at TXNUM 0, then fn_08007efc waits and the IWDG resets)."""
        return self.m.run_for(seconds)

    def press(self, mask, ms=60):
        self.keys.down |= mask
        self.run(ms / 1000.0)
        self.keys.down &= ~mask
        self.run(0.1)


def fl(rig, addr):
    return u32f(rig.rd(addr))


def mo(rig, name):
    return rig.rd(OWN_MEAS + MO[name])


def mof(rig, name, i=0):
    return u32f(rig.rd(OWN_MEAS + MO[name] + 4 * i))


def tap(rig, mask, ms=60):
    """A press, then the run until the handler consumed the event (test_own_lang.py tap)."""
    rig.press(mask, ms)
    end = rig.m.run_for(seconds=3.0, until=lambda mm: rig.rd16(V_KEY_CODE) == 0)
    check(end is None and rig.rd16(V_KEY_CODE) == 0, 'key 0x%X: event not consumed within 3 s' % mask)
    rig.run(0.05)


def settings_item(rig, item):
    """Long key 8 (settings screen), then key 0x20 until the menu word 0x200011A8 is item (our build hides
    item 1, the vendor build shows it: the count of presses differs, the word is the same)."""
    tap(rig, KEY_OK, 1200)
    check(rig.rd(V_SCREEN) == 3, 'settings screen not reached: screen %d' % rig.rd(V_SCREEN))
    for _ in range(8):
        if rig.rd(V_MENU) == item:
            return
        tap(rig, KEY_DOWN)
    check(rig.rd(V_MENU) == item, 'menu item %d not reached (%d)' % (item, rig.rd(V_MENU)))


def wait_until(rig, cond, seconds, what):
    end = rig.m.run_for(seconds=seconds, until=lambda mm: cond())
    check(end is None and cond(), '%s: not within %.1f s (end %r)' % (what, seconds, end))


# ---------------------------------------------------------------- probes

def func_ranges(sym):
    """{name: (start, end)} of every fn_* / named function, end = the next symbol address above."""
    addrs = sorted(set(v & ~1 for k, v in sym.items() if 0x08006000 <= (v & ~1) < 0x08062000))
    out = {}
    for name, v in sym.items():
        a = v & ~1
        if not 0x08006000 <= a < 0x08062000:
            continue
        nxt = [b for b in addrs if b > a]
        out[name] = (a, nxt[0] if nxt else a + 2)
    return out


class TableWatch:
    """m15: every write to the factory table and the user table (MEASUREMENT_FIX_DESIGN.md 5.1 m15)."""

    def __init__(self, rig):
        self.rig, m, s = rig, rig.m, rig.s
        self.fac, self.usr = [], []
        r = func_ranges(s)
        self.fill = (s['fill_bytes_08007100'] & ~1, (s['fill_bytes_08007100'] & ~1) + 0x0E)
        self.copy = (s['copy_bytes_080070dc'] & ~1, s['fill_bytes_08007100'] & ~1)
        self.zfill = r['zero_fill_words']            # region-table entry 1 handler (runtime_38.s)
        self.scatter = r['__scatterload']
        self.b4c8 = r['fn_0800b4c8']
        self.bb64 = r['fn_0800bb64']
        self.bcd8 = r['fn_0800bcd8']
        self.snap = r.get('cal_snap')               # own/cal.s: the 30 entries written back (stage 3)
        self.load_str = None
        if 'own_load' in s:
            lo, hi = r['own_load']
            code = bytes(m.uc.mem_read(lo, hi - lo))
            for i in range(0, len(code) - 3, 2):
                if code[i:i + 4] == bytes.fromhex('41f8043b'):       # str r3, [r1], #4 (.Ll_cp_word)
                    self.load_str = lo + i
            check(self.load_str is not None, 'own_load copy store not found')

        def rec(lst):
            def hook(uc, acc, addr, size, value, user):
                lst.append((m.now(), uc.reg_read(UC_ARM_REG_PC), uc.reg_read(UC_ARM_REG_LR), addr, size))
            return hook
        m.uc.hook_add(UC_HOOK_MEM_WRITE, rec(self.fac), begin=FAC_LO, end=FAC_HI - 1)
        m.uc.hook_add(UC_HOOK_MEM_WRITE, rec(self.usr), begin=USR_LO, end=USR_HI - 1)

    def kind(self, pc, lr):
        inr = lambda a, rg: rg[0] <= (a & ~1) < rg[1]
        if inr(pc, self.zfill) and inr(lr, self.scatter):
            return 'scatter-zero'                    # reset: region-table entry 1 clears 0x2000057C..0x200163A7
        if inr(pc, self.fill) and (lr & ~1) == 0x08028030:
            return 'startup-fill'                    # system_40.s 446: bl zero_bytes (LR 0x08028031)
        if self.load_str is not None and pc == self.load_str:
            return 'own_load'
        if (inr(pc, self.fill) or inr(pc, self.copy)) and inr(lr, self.b4c8):
            return 'b4c8'
        if inr(pc, self.b4c8):
            return 'b4c8-store'
        if inr(pc, self.bb64):
            return 'bb64'
        if self.snap is not None and inr(pc, self.snap):
            return 'cal-restore'
        if (inr(pc, self.fill) or inr(pc, self.copy)) and inr(lr, self.bcd8):
            return 'bcd8-copy'
        return 'other'

    def check(self, restore=False, what=''):
        """The writers of the factory table: the start-up fill and own_load (and fn_0800b4c8's copies when
        restore); of the user table also fn_0800bb64 and own/cal.s cal_snap (the sweep writes back the
        entries it kept when a store fails, stage 3); the factory table equal to the loaded copy."""
        ok_f = {'scatter-zero', 'startup-fill', 'own_load'} | ({'b4c8'} if restore else set())
        bad = [(t, hex(pc), hex(lr), hex(a), n) for t, pc, lr, a, n in self.fac if self.kind(pc, lr) not in ok_f]
        check(not bad, '%s m15: unexpected writers of the factory table %r' % (what, bad[:5]))
        bad = [(t, hex(pc), hex(lr), hex(a), n) for t, pc, lr, a, n in self.usr
               if self.kind(pc, lr) not in ok_f | {'bb64', 'cal-restore'}]
        check(not bad, '%s m15: unexpected writers of the user table %r' % (what, bad[:5]))
        now = self.rig.rd(FAC_LO, FAC_HI - FAC_LO)
        check(now == self.rig.block[4:0x5A4], '%s m15: the factory table differs from the loaded copy' % what)
        NOTES.append('%s m15: %d factory-table writes (%s), %d user-table writes' % (
            what, len(self.fac), ', '.join(sorted({self.kind(p, l) for _, p, l, _, _ in self.fac})), len(self.usr)))


class Probe:
    """Publishes, acquisitions, additions, resets, re-arms (module docstring)."""

    def __init__(self, rig):
        self.rig, m, s = rig, rig.m, rig.s
        self.pubs, self.acqs, self.adds, self.resets, self.rearms, self.arms = [], [], [], [], [], []
        self.f10, self.changes = [], []
        self.cur = []
        self.on_publish_entry = None          # callable(rig) at the entry of meas_publish
        self.capture = True

        def words():
            d = {k: rig.rd(a) for k, a in WORDS.items()}
            d['t'] = m.now()
            d['serpar'] = rig.rd(V_SERPAR)
            d['n'] = rig.rd(V_RING)
            d['codes'] = (rig.rd8(V_C5), rig.rd8(V_C6), rig.rd8(V_C8))
            return d
        if rig.vendor:
            def vpub(uc, a, size, u):
                self.pubs.append(words())
            m.uc.hook_add(UC_HOOK_CODE, vpub, begin=VENDOR_PUBLISH, end=VENDOR_PUBLISH)
        else:
            def pub(uc, acc, addr, size, value, user):
                if value != 1:
                    return
                d = words()
                d['sum'] = [mof(rig, 'SUM', i) for i in range(4)]
                d['k'] = mof(rig, 'K')
                d['cls'] = mo(rig, 'CLS')
                d['tfirst'] = mo(rig, 'TFIRST')
                d['tick'] = rig.rd(V_TICK)
                d['adds'] = list(self.cur)
                d['screen'] = rig.rd(V_SCREEN)
                self.pubs.append(d)
            m.uc.hook_add(UC_HOOK_MEM_WRITE, pub, begin=V_NEW, end=V_NEW + 3)

            def acq(uc, a, size, u):
                if not self.capture:
                    return
                self.acqs.append(dict(
                    t=m.now(), g=mo(rig, 'G'), tick=rig.rd(V_TICK),
                    v=list(struct.unpack('<128h', rig.rd(V_BUF_V, 256))),
                    i=list(struct.unpack('<128h', rig.rd(V_BUF_I, 256))),
                    x=[mof(rig, 'X', j) for j in range(4)], sig=(mof(rig, 'SIG'), mof(rig, 'SIG', 1)),
                    s1=struct.unpack('<ii', rig.rd(OWN_MEAS + MO['S1'], 8)),
                    codes=(rig.rd8(V_C5), rig.rd8(V_C6), rig.rd8(V_C8)), freq=rig.rd(V_FREQ)))
            m.uc.hook_add(UC_HOOK_CODE, acq, begin=s['meas_win'] & ~1, end=s['meas_win'] & ~1)

            def add(uc, a, size, u):
                p = uc.reg_read(UC_ARM_REG_R0)
                f = struct.unpack('<6f', rig.rd(p, 24))
                d = dict(t=m.now(), v=complex(f[0], f[1]), i=complex(f[2], f[3]), z=complex(f[4], f[5]),
                         ref=mo(rig, 'REF'), k=mof(rig, 'K'), cls=mo(rig, 'CLS'))
                self.cur.append(d)
                self.adds.append(d)
            m.uc.hook_add(UC_HOOK_CODE, add, begin=s['meas_add'] & ~1, end=s['meas_add'] & ~1)

            def reset(uc, a, size, u):
                self.cur = []
                self.resets.append(m.now())
            m.uc.hook_add(UC_HOOK_CODE, reset, begin=s['meas_reset'] & ~1, end=s['meas_reset'] & ~1)

            def rearm(uc, a, size, u):
                if uc.reg_read(UC_ARM_REG_R0) == 0x40020008:
                    self.rearms.append((m.now(), (mo(rig, 'G') + 1) & 0xFFFFFFFF))
            m.uc.hook_add(UC_HOOK_CODE, rearm, begin=s['own_dma_rearm'] & ~1, end=s['own_dma_rearm'] & ~1)

            def arm(uc, a, size, u):
                self.arms.append((m.now(), mo(rig, 'G')))       # G_exp becomes G + 1
            m.uc.hook_add(UC_HOOK_CODE, arm, begin=s['meas_arm'] & ~1, end=s['meas_arm'] & ~1)

            def change(uc, a, size, u):
                self.changes.append(m.now())
            m.uc.hook_add(UC_HOOK_CODE, change, begin=s['meas_change'] & ~1, end=s['meas_change'] & ~1)

            def pubentry(uc, a, size, u):
                if self.on_publish_entry is not None:
                    self.on_publish_entry(rig)
            m.uc.hook_add(UC_HOOK_CODE, pubentry, begin=s['meas_publish'] & ~1, end=s['meas_publish'] & ~1)

        def f10(uc, a, size, u):
            self.f10.append(m.now())
        m.uc.hook_add(UC_HOOK_CODE, f10, begin=s['fn_08009f10'] & ~1, end=s['fn_08009f10'] & ~1)

    def rearm_time(self, g):
        for t, gg in reversed(self.rearms):
            if gg == g:
                return t
        return None

    def acq_interval(self):
        """The median time between two used acquisitions."""
        d = sorted(b['t'] - a['t'] for a, b in zip(self.acqs, self.acqs[1:]))
        return d[len(d) // 2] if d else 0.0

    def normal(self, since=0.0):
        """The publishes after `since` that are not the 1e10 / -400 set."""
        return [p for p in self.pubs if p['t'] > since and p['TH'] != F_M400]


def no_nan(p, what):
    for k in OUT:
        v = p[k]
        check(not ((v & 0x7F800000) == 0x7F800000 and v & 0x7FFFFF), '%s: %s is NaN (0x%08X)' % (what, k, v))


def is_set(p):
    """The overload / no-reading set (measure_33.s 0x0800a712)."""
    return p['TH'] == F_M400 and all(p[k] == F_1E10 for k in ('Z', 'X', 'R', 'C', 'L', 'D', 'Q'))


# ---------------------------------------------------------------- m01 timing

@case
def m01_timing():
    """S1.1: TIM1 AR = 144e6 / (k f) - 1 (k = 128 / 32 / 8) at all five frequencies; TIM6 AR and the DAC
    table length (DMA2 ch3 count) by fn_08008814's formula AR = 72e6 / f / n - 1 with n = 150 at 120 Hz
    (AR 3999, exactly 120 Hz), otherwise the vendor's n (180 below 100 kHz, 36 above): the same TIM6 and
    table as the vendor build at the other frequencies; the generator frequency of the model is f."""
    for f in FREQS:
        rig = own_rig(DutSource('R', 1000.0), freq=f)
        rig.run(0.2)
        k = 128 if f < 10000 else 32 if f < 100000 else 8
        ar1 = rig.meas.tim[TIM1].reg(0x2C)
        check(ar1 == 144000000 // (k * f) - 1, '%d Hz: TIM1 AR %d, expected %d' % (f, ar1, 144000000 // (k * f) - 1))
        n = 150 if f == 120 else 180 if f < 100000 else 36
        ar6 = rig.meas.tim[TIM6].reg(0x2C)
        check(ar6 == 72000000 // f // n - 1, '%d Hz: TIM6 AR %d, expected %d' % (f, ar6, 72000000 // f // n - 1))
        check(rig.meas.dma[1][2].init == n, '%d Hz: DAC table %d entries, expected %d' % (f, rig.meas.dma[1][2].init, n))
        if f != 120:
            nv = 180 if f < 100000 else 36
            check(ar6 == 72000000 // f // nv - 1 and n == nv, '%d Hz: TIM6 / table differ from the vendor formula' % f)
        check(abs(rig.meas.frequency() - f) <= 1e-9 * f, '%d Hz: generator %.9f Hz' % (f, rig.meas.frequency()))
        rig.watch.check(what='m01 %d Hz' % f)
    return True


# ---------------------------------------------------------------- m02 coherence

def quant_bound(acqs):
    """Worst-case 12-bit bound of a window value (relative, and the same in radians): a quantisation
    error of at most 0.5 count per sample moves a bin by at most 64 counts against |X| = 64 A, so V / I
    moves by at most 1 / A_V + 1 / A_I (A = half the p-p of the smallest buffer used)."""
    av = min((max(a['v']) - min(a['v'])) / 2.0 for a in acqs)
    ai = min((max(a['i']) - min(a['i'])) / 2.0 for a in acqs)
    return 1.0 / av + 1.0 / ai


@case
def m02_coherence():
    """S1.1 / V3: C 10 nF at 100 kHz and L 10 mH at 10 kHz, no noise, the model's ideal sine source:
    every published |Z| / theta (after the first two windows) within the 12-bit bound of z(f) (the model's
    own value: both ADCs sample the same generator at the same TIM1 instants, so V / I = z); the vendor
    build on the same input deviates by more than that bound (the V3 leakage), which proves the case sees it
    (at 10 kHz; at 100 kHz V1.1 stops in this model by its re-arm race, recorded as a note)."""
    for src, f in ((DutSource('C', 10e-9), 100000), (DutSource('L', 10e-3), 10000)):
        z = src.z(f)
        rig = own_rig(src, freq=f)
        rig.run(4.0)
        pubs = rig.probe.normal()[2:]
        check(len(pubs) >= 3, '%d Hz: %d windows' % (f, len(pubs)))
        acqs = [a for a in rig.probe.acqs if a['t'] > pubs[0]['t'] - 1.0]
        b = quant_bound(acqs)
        worst = 0.0
        for p in pubs:
            ez = abs(u32f(p['Z']) / abs(z) - 1)
            et = abs(math.radians(u32f(p['TH'])) - cmath.phase(z))
            worst = max(worst, ez, et)
            check(ez <= b and et <= b, '%d Hz: |Z| %.4f (%.4f), theta %.4f (%.4f): errors %.2e / %.2e, bound %.2e'
                  % (f, u32f(p['Z']), abs(z), u32f(p['TH']), math.degrees(cmath.phase(z)), ez, et, b))
        rig.watch.check(what='m02 %d Hz' % f)
        vr = VRig(src, freq=f)
        end = vr.run_end(4.0)
        vp = vr.probe.pubs[2:]
        if f == 100000 and end is not None:
            # V1.1 at 100 kHz: the DAC period (10 us) is far below the acquisition time (160 us), and its
            # re-arm race stops the measurement; the control of this case is the 10 kHz part
            NOTES.append('m02 %d Hz: own worst error %.2e (bound %.2e, %d windows); V1.1 run ended %r at %.3f s '
                         'after %d windows (no V3 control at 100 kHz)' % (f, worst, b, len(pubs), end, vr.m.now(), len(vr.probe.pubs)))
            continue
        check(end is None, 'V1.1 %d Hz: run ended %r' % (f, end))
        check(len(vp) >= 2, 'V1.1 %d Hz: %d windows' % (f, len(vp)))
        ve = max(max(abs(u32f(p['Z']) / abs(z) - 1), abs(math.radians(u32f(p['TH'])) - cmath.phase(z))) for p in vp)
        check(ve > b, 'V1.1 %d Hz: error %.2e not above the bound %.2e' % (f, ve, b))
        NOTES.append('m02 %d Hz: own worst error %.2e (bound %.2e, %d windows), V1.1 %.2e' % (f, worst, b, len(pubs), ve))
    return True


# ---------------------------------------------------------------- m03 DFT

def vendor_bin(rig, x, k):
    """fn_080069dc(d_0804fcec, array, 0, 1) on the 128 codes (real part, imaginary 0.0, as fn_0800a068
    fills sp+0x208), run in the stopped rig on an array at 0x20014300 (above the heap end 0x2001424C, far
    below the stack in use); returns bin k."""
    arr = 0x20014300
    rig.wr(arr, b''.join(struct.pack('<ff', float(v), 0.0) for v in x))
    rig.m.call(rig.s['fn_080069dc'], rig.s['d_0804fcec'], arr, 0, 1)
    check(rig.m.st['end'] == 'return', 'fn_080069dc did not return: %r' % rig.m.st['end'])
    re, im = struct.unpack('<ff', rig.rd(arr + 8 * k, 8))
    return complex(re, im)


@case
def m03_dft():
    """S1.2 at k = 1 / 4 / 16 (1 kHz, 10 kHz, 100 kHz, R 1 kohm, both channels in band 1500..3600 p-p):
    for captured buffers the own bin equals the vendor fn_080069dc bin within B = 2^-16 sum|x|; S1 equals
    the integer sum; sigma^2 >= 0 in every acquisition and within 1e-4 count^2 + 2e-5 sigma^2 of the float64
    residual (the design's 1e-4 is the model's bound for noise up to 1 count; a buffer with a large residual
    (an acquisition out of band, the 100 kHz DAC images) adds the float32 summation error of 128 rounded
    squares, at most 128 * 2^-24 = 7.6e-6 of the sum, and the rounding of each residual term)."""
    for f in (1000, 10000, 100000):
        k = kbin(f)
        rig = own_rig(DutSource('R', 1000.0, noise_lsb=1.0), freq=f)
        rig.run(1.0)
        acqs = rig.probe.acqs
        check(acqs, '%d Hz: no acquisition used' % f)
        inband = []
        for a in acqs:
            for ch, x, s1, sig in (('V', a['v'], a['s1'][0], a['sig'][0]), ('I', a['i'], a['s1'][1], a['sig'][1])):
                check(s1 == sum(x), '%d Hz %s: S1 %d, sum %d' % (f, ch, s1, sum(x)))
                check(sig >= 0.0, '%d Hz %s: sigma^2 %r' % (f, ch, sig))
                X64, s64 = dft64(x, k)
                check(abs(sig - s64) <= 1e-4 + 2e-5 * s64, '%d Hz %s: sigma^2 %.6f, float64 %.6f' % (f, ch, sig, s64))
            if all(1500 <= max(b) - min(b) <= 3600 for b in (a['v'], a['i'])):
                inband.append(a)
        check(len(inband) >= 4, '%d Hz: %d in-band acquisitions' % (f, len(inband)))
        worst = 0.0
        for a in inband[:4]:
            for x, own in ((a['v'], complex(a['x'][0], a['x'][1])), (a['i'], complex(a['x'][2], a['x'][3]))):
                vb = vendor_bin(rig, x, k)
                B = 2.0 ** -16 * sum(abs(v) for v in x)
                worst = max(worst, abs(own - vb) / B)
                check(abs(own - vb) <= B, '%d Hz: own bin %r, vendor %r, B %.3f' % (f, own, vb, B))
        NOTES.append('m03 %d Hz: %d acquisitions checked (S1, sigma^2), 8 bins against fn_080069dc, worst |d| / B %.3f'
                     % (f, len(acqs), worst))
        rig.watch.check(what='m03 %d Hz' % f)
    return True


# ---------------------------------------------------------------- m04 complex estimate

def check_windows(rig, what, rel=1e-4):
    """Every normal publish equals K sum(V u) / sum(I u) recomputed in float64 from its additions
    (|Z| relative rel, theta within rel radians); every addition's V / I is the float64 bin of a used
    buffer within B; no output word NaN. Returns the publishes checked."""
    bins = {}

    def used(t):
        """float64 bins of the acquisitions used in the 3 s before t (an addition comes from the current
        acquisition or from a slot held since)."""
        out = []
        for j, a in enumerate(rig.probe.acqs):
            if t - 3.0 <= a['t'] <= t:
                if j not in bins:
                    bins[j] = (dft64(a['v'], kbin(a['freq']))[0], dft64(a['i'], kbin(a['freq']))[0],
                               2.0 ** -16 * sum(abs(v) for v in a['v']), 2.0 ** -16 * sum(abs(v) for v in a['i']))
                out.append(bins[j])
        return out
    out = []
    for p in rig.probe.pubs:
        no_nan(p, what)
        if is_set(p) or not p['adds']:
            continue
        zb = window_z(p['adds'])
        check(abs(u32f(p['Z']) / abs(zb) - 1) <= rel, '%s: |Z| %.6g, recomputed %.6g' % (what, u32f(p['Z']), abs(zb)))
        dth = abs(math.radians(u32f(p['TH'])) - cmath.phase(zb))
        check(min(dth, 2 * math.pi - dth) <= rel, '%s: theta %.5f, recomputed %.5f' % (
            what, u32f(p['TH']), math.degrees(cmath.phase(zb))))
        for ad in p['adds']:
            check(any(abs(ad['v'] - bv) <= max(bvb, 1e-3) + 1e-6 * abs(bv) and abs(ad['i'] - bi) <= max(bib, 1e-3) + 1e-6 * abs(bi)
                      for bv, bi, bvb, bib in used(ad['t'])),
                  '%s: an addition (V %r, I %r) is no used buffer' % (what, ad['v'], ad['i']))
        out.append(p)
    return out


@case
def m04_complex_estimate():
    """S1.3: (a) noise on a 0.1 ohm part and on an open: each window recomputed from its buffers, theta and
    |Z| from the same samples, nothing NaN; (b) ADC2 at code 0 (saturated): the 1e10 / -400 set, never NaN;
    (c) noise-free: a sine on both channels is resolved, a constant ADC2 noise-limited (the no-reading
    set), sigma^2 >= 0 always; (d) |V| ~ |I| (1000 counts each, ratio 1.00 and 1.05, theta -60 deg, S/N
    50 by the design's 8 A / sigma, sigma = noise_lsb / sqrt 3 for the uniform noise): the mean theta
    error over 40 windows within 0.15 deg, and every window recomputed; (e) a forced non-finite Zbar
    (sum I' = 1e-30, sum V' = 1e10 written at the publish entry) publishes the overload set, no Inf."""
    # (a) the model's source is ideal (I = k G6 R8 v / z): with the default k a 0.1 ohm part saturates ADC2
    # even at c6 = 0 / range 100 ohm (about 1e6 counts, the overload set, measured 2026-11-22); k = 1.5
    # counts per volt puts I at about 1270 counts there and V at about 163 counts at c5 = 7 (the weak
    # channel of a short)
    for name, src in (('0.1 ohm', DutSource('R', 0.1, counts_per_volt=1.5, noise_lsb=2.0)),
                      ('open', DutSource('R', 1e12, noise_lsb=2.0))):
        rig = own_rig(src)
        rig.run(2.5)
        got = check_windows(rig, 'm04 (a) %s' % name)
        check(len(got) >= 2 or (name == 'open' and rig.probe.pubs), 'm04 (a) %s: %d windows' % (name, len(got)))
        NOTES.append('m04 (a) %s: %d windows recomputed, last |Z| %.6g theta %.3f, N %s' % (
            name, len(got), u32f(rig.probe.pubs[-1]['Z']), u32f(rig.probe.pubs[-1]['TH']),
            [p['n'] for p in rig.probe.pubs[-3:]]))
        rig.watch.check(what='m04 (a) %s' % name)
    # (b)
    rig = own_rig(TDut(lambda f, t: 1000.0, i_codes=lambda times: 0))
    rig.run(1.5)
    check(rig.probe.pubs and all(is_set(p) for p in rig.probe.pubs[-2:]), 'm04 (b): no 1e10 / -400 set')
    for p in rig.probe.pubs:
        no_nan(p, 'm04 (b)')
    rig.watch.check(what='m04 (b)')
    # (c)
    rig = own_rig(DutSource('R', 1000.0))
    rig.run(1.5)
    check(all(a['sig'][0] >= 0 and a['sig'][1] >= 0 for a in rig.probe.acqs), 'm04 (c): sigma^2 < 0')
    pubs = rig.probe.normal()
    check(pubs and all(p['cls'] == 1 for p in pubs), 'm04 (c) sine: classes %r' % [p['cls'] for p in pubs])
    for p in rig.probe.pubs:
        no_nan(p, 'm04 (c) sine')
    rig.watch.check(what='m04 (c) sine')
    rig = own_rig(TDut(lambda f, t: 1000.0, i_codes=lambda times: 2048))
    rig.run(1.5)
    check(all(a['sig'][0] >= 0 and a['sig'][1] >= 0 for a in rig.probe.acqs), 'm04 (c) constant: sigma^2 < 0')
    check(rig.probe.pubs and all(p['cls'] == 0 and is_set(p) for p in rig.probe.pubs),
          'm04 (c) constant: %r' % [(p['cls'], hex(p['TH'])) for p in rig.probe.pubs])
    for p in rig.probe.pubs:
        no_nan(p, 'm04 (c) constant')
    rig.watch.check(what='m04 (c) constant')
    # (d)
    for ratio in (1.00, 1.05):
        src = AmpSource(1000.0, 125.0 / ratio, -60.0, noise_lsb=160.0 * math.sqrt(3))
        rig = own_rig(src, speed=2)
        n = 0
        while len(rig.probe.normal()) < 42 and n < 40:
            rig.run(0.5)
            n += 1
        pubs = rig.probe.normal()[2:42]
        check(len(pubs) == 40, 'm04 (d) %.2f: %d windows' % (ratio, len(pubs)))
        err = sum(u32f(p['TH']) + 60.0 for p in pubs) / len(pubs)
        ns = [p['n'] for p in pubs]
        check(abs(err) <= 0.15, 'm04 (d) %.2f: mean theta error %.3f deg' % (ratio, err))
        check_windows(rig, 'm04 (d) %.2f' % ratio)
        a = rig.probe.acqs[-1]
        NOTES.append('m04 (d) ratio %.2f: mean theta error %+.4f deg over 40 windows, N %d..%d, codes %r, |V| / |I| %.3f'
                     % (ratio, err, min(ns), max(ns), a['codes'], abs(complex(a['x'][0], a['x'][1])) / abs(complex(a['x'][2], a['x'][3]))))
        rig.watch.check(what='m04 (d) %.2f' % ratio)
    # (e)
    rig = own_rig(DutSource('R', 1000.0))
    rig.run(1.0)
    done = []

    def force(r):
        if done:
            return
        done.append(r.m.now())
        r.wr(OWN_MEAS + MO['SUM'], struct.pack('<4f', 1e10, 0.0, 1e-30, 0.0))
    rig.probe.on_publish_entry = force
    rig.run(1.0)
    check(done, 'm04 (e): no publish')
    after = [p for p in rig.probe.pubs if p['t'] >= done[0]]
    check(after and is_set(after[0]), 'm04 (e): the forced window is not the overload set: %r' % (after[:1],))
    # the words the overload set writes are finite (a normal window of a pure R has Xs = 0 exactly
    # and so Cs, Xp, Lp, D infinite: the S1.8 rule, shown "0L")
    p = after[0]
    check(all((p[k] & 0x7F800000) != 0x7F800000 for k in ('Z', 'X', 'TH', 'R', 'C', 'L', 'D', 'Q')),
          'm04 (e): Inf in the forced publish %r' % {k: hex(p[k]) for k in OUT})
    rig.watch.check(what='m04 (e)')
    return True


# ---------------------------------------------------------------- m05 outliers and part change

@case
def m05_outliers_and_part_change():
    """S1.3: one outlier acquisition at the complex distance of a 3x |Z| (2 |Z|: Z -> -Z for the samples of
    exactly one acquisition, from its re-arm to the next; a 3x |Z| itself takes ADC2 out of band, p-p
    / 3 < 1500, and the ranging, not the outlier rule, discards it: measured 2026-11-22) is not added
    and the window publishes the part; 1.0 -> 1.2 kohm in the
    middle of a window: each publish is one part (within 0.2 %), none of one acquisition, the first
    1.2 kohm window complete (N >= 3, T_win long); 1.000 -> 1.005 kohm (below the 1 % floor): at most one
    window between the two values; part -> open -> part: no window mixes the classes; an open at 100 Hz
    with S/N about 1..2 publishes at the T_win rate."""
    # one outlier
    win = {}
    src = TDut(lambda f, t: -1000.0 if win.get('a', 9e9) <= t < win.get('b', 9e9) else 1000.0, noise_lsb=0.5)
    rig = own_rig(src)
    rig.run(1.5)
    r0 = len(rig.probe.rearms)
    rig.m.run_for(seconds=1.0, until=lambda mm: len(rig.probe.rearms) >= r0 + 5)
    win['a'] = rig.probe.rearms[-1][0]
    rig.m.run_for(seconds=1.0, until=lambda mm: len(rig.probe.rearms) >= r0 + 6)
    win['b'] = rig.probe.rearms[-1][0]
    rig.run(1.5)
    big = [ad for ad in rig.probe.adds if abs(ad['z'] - 1000.0) > 500.0]
    check(not big, 'm05 outlier: added %r' % big)
    hit = [a for a in rig.probe.acqs if a['g'] == rig.probe.rearms[r0 + 4][1]] if len(rig.probe.rearms) > r0 + 4 else []
    check(hit, 'm05 outlier: the outlier acquisition was never processed')
    for p in rig.probe.normal(win['a']):
        check(abs(u32f(p['Z']) / 1000.0 - 1) < 2e-3, 'm05 outlier: window |Z| %.3f' % u32f(p['Z']))
    rig.watch.check(what='m05 outlier')
    # 1.0 -> 1.2 kohm
    sw = {}
    rig = own_rig(TDut(lambda f, t: 1200.0 if t >= sw.get('t', 9e9) else 1000.0, noise_lsb=0.5))
    rig.run(1.5)
    p0 = rig.probe.pubs[-1]
    sw['t'] = p0['t'] + 0.25                      # speed 1: T_win 0.5 s; the switch in the middle
    rig.run(3.0)
    for p in rig.probe.normal(1.0):
        z = u32f(p['Z'])
        check(abs(z / 1000.0 - 1) < 2e-3 or abs(z / 1200.0 - 1) < 2e-3, 'm05 step: a mixed window |Z| %.3f' % z)
        check(p['n'] >= 3, 'm05 step: a window of %d' % p['n'])
    first = [p for p in rig.probe.normal(sw['t']) if abs(u32f(p['Z']) / 1200.0 - 1) < 2e-3]
    check(first and first[0]['n'] >= 3 and (first[0]['tick'] - first[0]['tfirst']) >= 500,
          'm05 step: first 1.2 kohm window %r' % ({k: first[0][k] for k in ('n', 'tick', 'tfirst')} if first else None))
    rig.watch.check(what='m05 step')
    # 1.000 -> 1.005 kohm
    sw = {}
    rig = own_rig(TDut(lambda f, t: 1005.0 if t >= sw.get('t', 9e9) else 1000.0, noise_lsb=0.5))
    rig.run(1.5)
    sw['t'] = rig.probe.pubs[-1]['t'] + 0.25
    rig.run(3.0)
    zs = [u32f(p['Z']) for p in rig.probe.normal(1.0)]
    between = [z for z in zs if 1000.0 * 1.001 < z < 1005.0 * 0.999]
    check(len(between) <= 1, 'm05 small step: %d windows between the values %r' % (len(between), zs))
    check(abs(zs[-1] / 1005.0 - 1) < 1e-3, 'm05 small step: last |Z| %.3f' % zs[-1])
    rig.watch.check(what='m05 small step')
    # part -> open -> part
    sw = {}
    rig = own_rig(TDut(lambda f, t: 1e12 if sw.get('a', 9e9) <= t < sw.get('b', 9e9) else 1000.0, noise_lsb=1.0))
    rig.run(1.5)
    sw['a'] = rig.m.now() + 0.1
    sw['b'] = sw['a'] + 2.0
    rig.run(4.0)
    for p in rig.probe.pubs:
        if p['adds']:
            cls = {ad['cls'] for ad in p['adds']}
            check(len(cls) == 1, 'm05 open: a window of both classes')
            ts = [ad['t'] for ad in p['adds']]
            part = [sw['a'] <= t < sw['b'] for t in ts]
            check(all(part) or not any(part), 'm05 open: a window across a class change')
    check(any(p['cls'] == 0 for p in rig.probe.pubs) and rig.probe.normal(sw['b'] + 0.5), 'm05 open: classes not both seen')
    rig.watch.check(what='m05 open')
    # noise-limited open at 100 Hz: I amplitude 0.3 count at code 7 / range 100 kohm, noise +-3 (sigma 1.73)
    rig = own_rig(DutSource('R', 4.5e10, noise_lsb=3.0), freq=100)
    rig.run(4.0)
    ts = [p['t'] for p in rig.probe.pubs if p['t'] > 1.5]
    gaps = [b - a for a, b in zip(ts, ts[1:])]
    lim = 0.5 + 0.011 + 2 * rig.probe.acq_interval()  # as p01: timed from the previous close
    check(len(gaps) >= 3 and all(0.489 <= g <= lim for g in gaps), 'm05 100 Hz open: window gaps %r (limit %.3f)' % (gaps, lim))
    check(all(p['cls'] == 0 for p in rig.probe.pubs if p['t'] > 1.5), 'm05 100 Hz open: not noise-limited')
    NOTES.append('m05 100 Hz open: %d windows, gaps %.3f..%.3f s, N %r' % (len(ts), min(gaps), max(gaps),
                 [p['n'] for p in rig.probe.pubs[-3:]]))
    rig.watch.check(what='m05 100 Hz open')
    return True


# ---------------------------------------------------------------- m06 settle

@case
def m06_settle():
    """S1.4: a gain change (byte 0x200011C5 written) and a frequency change (word 0x20001144 written, as a
    key or a host command changes it), each placed 0, 3 and 9.9 ms after a SysTick (the tick word
    0x20000480 moves): the window is reset at once and the first acquisition used afterwards was started
    (its re-arm) more than 10 ms (gain) / 30 ms (frequency) after the change. The writers of these words
    (the ranging calls, the key handlers, dset.s) run in the main loop, never inside own_measure, so the
    test writes at the first main-loop point after the placed time (a code hook at 0x080281D8, the
    instruction after bl own_measure); the offset reached is reported."""
    rig = own_rig(DutSource('R', 1000.0))
    rig.run(1.0)
    st = dict(at=None, kind=None, done=None)

    def at_loop(uc, a, size, u):
        if st['at'] is None or st['done'] is not None or rig.m.now() < st['at']:
            return
        if st['kind'] == 'gain':
            rig.wr(V_C5, bytes([rig.rd8(V_C5) ^ 1]))
        else:
            rig.wr(V_FREQ, 100 if rig.rd(V_FREQ) == 1000 else 1000)
        st['done'] = rig.m.now()
    rig.m.uc.hook_add(UC_HOOK_CODE, at_loop, begin=0x080281D8, end=0x080281D8)
    for kind, need in (('gain', 0.010), ('frequency', 0.030)):
        for off in (0.0, 0.003, 0.0099):
            t0 = rig.rd(V_TICK)
            wait_until(rig, lambda: rig.rd(V_TICK) != t0, 0.05, 'SysTick')
            ts = rig.m.now()
            st.update(at=ts + off, kind=kind, done=None)
            wait_until(rig, lambda: st['done'] is not None, 0.1, 'm06: the placed write')
            tw = st['done']
            st['at'] = None
            n0 = len(rig.probe.acqs)
            wait_until(rig, lambda: len(rig.probe.acqs) > n0, 1.0, 'm06 %s: an acquisition after the change' % kind)
            a = rig.probe.acqs[n0]
            tr = rig.probe.rearm_time(a['g'])
            check(tr is not None and tr - tw > need, 'm06 %s at +%.1f ms: first used acquisition started %.2f ms after'
                  % (kind, off * 1e3, (tr - tw) * 1e3 if tr is not None else -1))
            check(any(tw <= t <= a['t'] for t in rig.probe.changes), 'm06 %s: no change detected (meas_change)' % kind)
            NOTES.append('m06 %s placed +%.1f ms (written +%.3f ms) after a SysTick: first used acquisition started '
                         '%.2f ms later' % (kind, off * 1e3, (tw - ts) * 1e3, (tr - tw) * 1e3))
            if kind == 'gain':
                st.update(at=rig.m.now(), kind='gain', done=None)     # back to the gain the ranging chose
                wait_until(rig, lambda: st['done'] is not None, 0.1, 'm06: gain restored')
                st['at'] = None
            rig.run(0.2)
    rig.watch.check(what='m06')
    return True


# ---------------------------------------------------------------- m07 saturation

@case
def m07_saturation():
    """S1.5: ADC1 pushed to 4095 by its mid (3800) at a p-p of at most 3600: our build steps c5 down and at
    c5 = 0, after 3 saturated acquisitions, publishes the overload set; the vendor build publishes no
    such set. Under a forced range (0x2000114C = 4) with ADC2 saturated at c6 = 0 (fn_0800b000 returns 0
    with nothing changed) our build publishes the overload set too."""
    sw = {}
    k = 400.0 / 0.8467        # V amplitude about 400 counts at gain code 0: the generator amplitude is
    # 2047.5 * 0.6 / 2.34 DAC counts (fn_08008814) / 620 counts per volt (measure_model) = 0.8467 V

    class Sat(TDut):
        def samples(self, path, adc, channel, times):
            self.mid_v = 3800.0 if sw.get('t') is not None and times and times[0] >= sw['t'] else 2048.0
            return super().samples(path, adc, channel, times)
    for vendor in (False, True):
        sw.clear()
        src = Sat(lambda f, t: 1000.0, counts_per_volt=k)
        rig = VRig(src) if vendor else own_rig(src)
        rig.run(1.5)
        c5a = rig.rd8(V_C5)
        sw['t'] = rig.m.now()
        rig.run(1.5)
        sets = [p for p in rig.probe.pubs if p['t'] > sw['t'] and is_set(p)]
        if vendor:
            check(not sets, 'm07 V1.1: published the overload set')
            NOTES.append('m07 V1.1: c5 %d before, %d after the mid shift, no overload set' % (c5a, rig.rd8(V_C5)))
        else:
            check(c5a >= 1, 'm07: c5 %d before the shift (no step down possible)' % c5a)
            check(rig.rd8(V_C5) == 0 and sets, 'm07: c5 %d, %d overload sets' % (rig.rd8(V_C5), len(sets)))
            check(len(sets) == 1, 'm07: the overload set published %d times (once expected)' % len(sets))
            rig.watch.check(what='m07')
    rig = own_rig(DutSource('R', 1000.0), range=4)
    rig.run(2.0)
    check(rig.rd8(V_C6) == 0 and rig.rd8(V_C8) == 3, 'm07 forced range: c6 %d c8 %d' % (rig.rd8(V_C6), rig.rd8(V_C8)))
    check(any(is_set(p) for p in rig.probe.pubs), 'm07 forced range: no overload set')
    rig.watch.check(what='m07 forced range')
    return True


# ---------------------------------------------------------------- m08 hysteresis

def code_changes(rig, addr, t_from):
    """Changes of a code byte after t_from (UC_HOOK_MEM_WRITE log of this file's hook)."""
    return [x for x in rig.code_log if x[0] > t_from and x[1] == addr]


def log_codes(rig):
    rig.code_log = []
    last = {a: rig.rd8(a) for a in (V_C5, V_C6, V_C8)}

    def hook(uc, acc, addr, size, value, user):
        v = value & 0xFF
        if last.get(addr) != v:
            rig.code_log.append((rig.m.now(), addr, v))
            last[addr] = v
    rig.m.uc.hook_add(UC_HOOK_MEM_WRITE, hook, begin=V_C5, end=V_C8)


@case
def m08_hysteresis():
    """S1.6: gain_err +2 % per c6 code (a step of 2.04) and I at p-p 1490 at code 2 / 3040 at code 3
    (forced range 1 kohm): the vendor build (I band 1500..3000) toggles c6 (counted), our build (1500..3600)
    settles and publishes. Also without a forced range: in band with c6 >= 4 and c8 < 3 (the range steps
    up) and ADC3 p-p 400 > 250 with c8 > 0 (the range steps down): no limit cycle (no code change in the
    last 1.5 s of 3 s)."""
    a_i0 = 745.0 / (2.04 ** 2 * 10.0)
    res = {}
    for vendor in (False, True):
        src = AmpSource(1000.0, a_i0, 0.0, gain_err=0.02)
        rig = VRig(src, range=2) if vendor else own_rig(src, range=2)
        log_codes(rig)
        if vendor:
            rig.run_end(3.0)
        else:
            rig.run(3.0)
        at3 = [t for t, a, v in rig.code_log if a == V_C6 and v == 3]
        check(at3, 'm08 %s: c6 never 3' % ('V1.1' if vendor else 'own'))
        n = len(code_changes(rig, V_C6, at3[0]))      # changes after c6 first reached 3
        res[vendor] = n
        if vendor:
            # V1.1 toggles until its measurement stops (its re-arm race in this model, m02)
            check(n >= 10, 'm08 V1.1: c6 changed %d times after reaching 3 (a toggle expected)' % n)
        else:
            check(n == 0 and rig.rd8(V_C6) == 3, 'm08: c6 changed %d times, c6 %d' % (n, rig.rd8(V_C6)))
            check(len(rig.probe.normal(1.5)) >= 2, 'm08: %d windows' % len(rig.probe.normal(1.5)))
            ch = [x for x in rig.code_log if x[1] == V_C6]
            NOTES.append('m08: own c6 path %r' % [x[2] for x in ch])
            rig.watch.check(what='m08')
    NOTES.append('m08: c6 changes after c6 first reached 3: own %d, V1.1 %d' % (res[False], res[True]))
    # range up: in band at c6 = 5, c8 = 0 (I amplitude 1000 at code 5, range 100 ohm)
    rig = own_rig(AmpSource(1000.0, 1000.0 / 32, 0.0))
    log_codes(rig)
    rig.run(3.0)
    late = [x for x in rig.code_log if x[0] > 1.5]
    check(not late, 'm08 range up: code changes late %r' % late)
    NOTES.append('m08 range up: codes %r' % ((rig.rd8(V_C5), rig.rd8(V_C6), rig.rd8(V_C8)),))
    rig.watch.check(what='m08 range up')
    # range down by ADC3 p-p 400
    adc3 = lambda path, times: [int(round(2048 + 200 * math.sin(2 * math.pi * 1000 * t))) for t in times]
    rig = own_rig(AmpSource(1000.0, 125.0, 0.0, adc3=adc3))
    log_codes(rig)
    rig.run(3.0)
    late = [x for x in rig.code_log if x[0] > 1.5]
    check(not late and rig.rd8(V_C8) == 0, 'm08 ADC3: code changes late %r, c8 %d' % (late, rig.rd8(V_C8)))
    rig.watch.check(what='m08 ADC3')
    return True


# ---------------------------------------------------------------- m09 compare

def user_table_with(blk, freq, level_bits, scale):
    """The block with the user-table breakpoints of one entry multiplied by (1 + scale * k), k = 1..10
    (a synthetic table: the meter's own calibration data stays out of the repository)."""
    b = bytearray(blk)
    off = entry_addr(freq, level_bits) - V_BLOCK
    for k in range(1, 11):
        v = struct.unpack_from('<f', b, off + 4 * k)[0]
        struct.pack_into('<f', b, off + 4 * k, v * (1 + scale * k))
    return bytes(b)


@case
def m09_compare():
    """S1.7: a user table with non-identity breakpoints (1 kHz, 0.6 V entry, b_k scaled by 1 + 0.01 k):
    the compare value 0x200050DC on screen 2 equals R on screen 1 for the same part (1 kohm), and both are
    the interpolated value (not the raw |Zbar|)."""
    blk = user_table_with(settings(), 1000, 0x3F19999A, 0.01)
    rig = own_rig(DutSource('R', 1000.0), block=blk)
    rig.run(1.5)
    p1 = rig.probe.normal()[-1]
    zb = abs(window_z(p1['adds']))
    entry = struct.unpack('<12f', rig.rd(entry_addr(1000, 0x3F19999A), 48))
    want = interp64(entry, zb - entry[0])
    check(abs(u32f(p1['R']) / want - 1) < 1e-4, 'm09 screen 1: R %.4f, interpolated %.4f (raw %.4f)' % (u32f(p1['R']), want, zb))
    rig.press(KEY_HOLD, 1200)                         # long 0x400: screen 1 -> 2
    check(rig.rd(V_SCREEN) == 2, 'm09: screen %d' % rig.rd(V_SCREEN))
    t2 = rig.m.now()
    rig.run(1.5)
    p2 = [p for p in rig.probe.normal(t2) if p['screen'] == 2][-1]
    check(abs(u32f(p2['CMPV']) / u32f(p1['R']) - 1) < 2e-4, 'm09: compare value %.4f, screen-1 R %.4f'
          % (u32f(p2['CMPV']), u32f(p1['R'])))
    check(abs(u32f(p2['CMPV']) / zb - 1) > 1e-3, 'm09: the compare value is the raw value %.4f' % zb)
    NOTES.append('m09: screen 1 R %.4f, screen 2 compare %.4f, raw |Zbar| %.4f' % (u32f(p1['R']), u32f(p2['CMPV']), zb))
    rig.watch.check(what='m09')
    return True


# ---------------------------------------------------------------- m10 unfolded theta

@case
def m10_unfolded_theta():
    """S1.8: z = -1 + j100 ohm: theta 90.57 deg (not folded), Rs (0x200050A0, and R in series) about -1 ohm
    within the 12-bit bound, Q / D unsigned; z = -0.05 - j10 ohm: theta -90.29 deg, Rs about -0.05 ohm, D
    about 0.005 and positive. Forced windows (sums written at the publish entry): Re Zbar = 0 gives D = 0
    and Q = +Inf ("0L"), Im Zbar = 0 gives Q = 0 and D = +Inf; nothing NaN."""
    # the 10 ohm part with the model's default scale saturates ADC2 at c6 = 0 / range 100 ohm (the ideal
    # source, as in m04): 150 counts per volt puts I at about 1270 and V at about 1016 counts (c5 = 3)
    for z, k in ((complex(-1, 100), 4095 / 3.3), (complex(-0.05, -10), 150.0)):
        rig = own_rig(DutSource(z=lambda f, zz=z: zz, counts_per_volt=k))
        rig.run(2.0)
        pubs = rig.probe.normal()[1:]
        check(pubs, 'm10 %r: no window' % z)
        b = quant_bound([a for a in rig.probe.acqs if a['t'] > pubs[0]['t'] - 1.0])
        for p in pubs:
            th, rs = u32f(p['TH']), u32f(p['RS'])
            check(abs(math.radians(th) - cmath.phase(z)) <= b, 'm10 %r: theta %.4f, expected %.4f' % (z, th, math.degrees(cmath.phase(z))))
            check(abs(rs - z.real) <= 2 * abs(z) * b, 'm10 %r: Rs %.5f' % (z, rs))   # |Z| (d|Z| + d theta)
            check(rs < 0 and u32f(p['R']) == rs, 'm10 %r: Rs %.5f, R %.5f' % (z, rs, u32f(p['R'])))
            q, d = u32f(p['Q']), u32f(p['D'])
            check(q > 0 and d > 0 and abs(q * d - 1) < 1e-4, 'm10 %r: Q %.5g D %.5g' % (z, q, d))
            no_nan(p, 'm10')
        NOTES.append('m10 %r: theta %.4f, Rs %.5f, D %.5f (bound %.2e)' % (z, u32f(pubs[-1]['TH']), u32f(pubs[-1]['RS']),
                     u32f(pubs[-1]['D']), b))
        rig.watch.check(what='m10 %r' % z)
    for name, sums, q_want, d_want in (('Re Zbar = 0', (0.0, 1000.0, 10.0, 0.0), F_INF, 0),
                                       ('Im Zbar = 0', (1000.0, 0.0, 10.0, 0.0), 0, F_INF)):
        rig = own_rig(DutSource('R', 1000.0))
        rig.run(1.0)
        done = []

        def force(r, s=sums):
            if not done:
                done.append(r.m.now())
                r.wr(OWN_MEAS + MO['SUM'], struct.pack('<4f', *s))
        rig.probe.on_publish_entry = force
        rig.run(1.0)
        p = [p for p in rig.probe.pubs if p['t'] >= done[0]][0]
        check(p['Q'] == q_want and p['D'] == d_want, 'm10 %s: Q 0x%08X D 0x%08X' % (name, p['Q'], p['D']))
        no_nan(p, 'm10 %s' % name)
        rig.watch.check(what='m10 %s' % name)
    return True


# ---------------------------------------------------------------- m11 contract

def serpar_rule(zc, sp):
    """S2.6 (D4, stage 2): circuit auto with the state sp[0] (0 undecided, 1 series, 2 parallel): series
    goes parallel above 10 kohm, parallel goes series below 1 kohm, undecided decides at 3162.28 ohm
    (float32 constants of meas.s). Returns True for series and updates sp[0]."""
    s = sp[0]
    if s == 1:
        ser = not zc > 10000.0
    elif s == 2:
        ser = zc < 1000.0
    else:
        ser = not zc > struct.unpack('<f', struct.pack('<I', 0x4545A471))[0]
    sp[0] = 1 if ser else 2
    return ser


def expect_words(rig, p, sp=None):
    """Every output word of a publish from its sums and K (design section 2 / S1.8), float64; series /
    parallel by serpar_rule with the state list sp (one per run from its start: undecided)."""
    sv = complex(p['sum'][0], p['sum'][1])
    si = complex(p['sum'][2], p['sum'][3])
    zb = p['k'] * sv / si
    mag = abs(zb)
    th = math.degrees(cmath.phase(zb)) if mag else 0.0
    c, s = (zb.real / mag, zb.imag / mag) if mag else (1.0, 0.0)
    f = rig.rd(V_FREQ)
    entry = struct.unpack('<12f', rig.rd(entry_addr(f, rig.rd(V_LEVEL)), 48))
    zc = mag
    if not (p['screen'] == 3 and rig.rd(V_CAL_TYPE) == 0):
        zc = mag - entry[0]
        if p['screen'] != 3:
            zc = interp64(entry, zc)
    w = f * 6.2831855
    rs, xs = zc * c, zc * s
    rp = zc / c if c else math.copysign(math.inf, zc)
    xp = zc / s if s else math.copysign(math.inf, zc)
    e = dict(Z=zc, TH=th, RS=rs, XS=xs, RP=rp, XP=xp, CS=-1e9 / (w * xs) if xs else -math.copysign(math.inf, w * xs),
             CP=-1e9 / (w * xp), LS=xs * 1e6 / w, LP=xp * 1e6 / w,
             Q=0.0 if xs == 0 else math.inf if rs == 0 else abs(xs / rs),
             D=0.0 if rs == 0 else math.inf if xs == 0 else abs(rs / xs), X=xs)
    circ = rig.rd(V_CIRCUIT)
    ser = circ == 1 or (circ == 0 and serpar_rule(zc, sp if sp is not None else [0]))
    e['R'], e['C'], e['L'] = (rs, e['CS'], e['LS']) if ser else (rp, e['CP'], e['LP'])
    e['serpar'] = 0 if ser else 1
    return e


@case
def m11_contract():
    """Section 2 / S1.8: every output word against the formulas from the published sums (float64,
    relative 2e-5), 0x200050C8 = Xs in series and in parallel mode, series / parallel by the S2.6 rule of
    stage 2 (serpar_rule; R 1 kohm, C 100 nF, R 2 Mohm); the no-reading path (ranging that never settles: I at p-p 1400 on even
    and 3700 on odd c6 codes, forced range): the 1e10 / -400 set after 2 s once, then 0x20001208 = 0;
    MEASURE_DONE (event 0x95) once per window whose |Z| / theta bits changed (USB, DTR set)."""
    for src, name in ((DutSource('R', 1000.0, noise_lsb=0.5), 'R 1 kohm'), (DutSource('C', 100e-9, noise_lsb=0.5), 'C 100 nF'),
                      (DutSource('R', 2e6, noise_lsb=0.5), 'R 2 Mohm')):
        rig = own_rig(src)
        rig.run(2.0)
        pubs = rig.probe.normal()
        check(len(pubs) >= 2, 'm11 %s: %d windows' % (name, len(pubs)))
        sp = [0]
        for p in pubs:
            e = expect_words(rig, p, sp)
            for kk in ('Z', 'TH', 'RS', 'XS', 'RP', 'XP', 'CS', 'CP', 'LS', 'LP', 'Q', 'D', 'X', 'R', 'C', 'L'):
                got, want = u32f(p[kk]), e[kk]
                ok = (math.isinf(want) and got == want) or abs(got - want) <= 2e-5 * abs(want) + (1e-3 if kk == 'TH' else 1e-30)
                check(ok, 'm11 %s: %s %r, expected %r' % (name, kk, got, want))
            check(p['serpar'] == e['serpar'] and p['X'] == p['XS'], 'm11 %s: serpar %d X / Xs' % (name, p['serpar']))
        NOTES.append('m11 %s: %d windows, all words as the formulas, serpar %d' % (name, len(pubs), pubs[-1]['serpar']))
        rig.watch.check(what='m11 %s' % name)
    # no reading
    class Hunt(AmpSource):
        def samples(self, path, adc, channel, times):
            if adc == 2:
                c5, c6, c8 = path.front_end()
                self.a_i0 = (700.0 if c6 % 2 == 0 else 1850.0) / (2 ** c6 * RANGE_OHM[c8] / 100.0)
            return super().samples(path, adc, channel, times)
    rig = own_rig(Hunt(1000.0, 1.0, 0.0), range=2)
    rig.run(5.0)
    nr = [p for p in rig.probe.pubs if is_set(p)]
    check(1 <= len(nr) <= 3, 'm11 no reading: %d sets in 5 s' % len(nr))
    check(rig.rd(V_NR) == 0, 'm11 no reading: 0x20001208 = %d' % rig.rd(V_NR))
    gaps = [b['t'] - a['t'] for a, b in zip(nr, nr[1:])]
    check(all(g >= 2.0 for g in gaps), 'm11 no reading: sets %r s apart' % gaps)
    NOTES.append('m11 no reading: sets at %r s' % [round(p['t'], 3) for p in nr])
    rig.watch.check(what='m11 no reading')
    # MEASURE_DONE
    rig = own_rig(DutSource('R', 1000.0, noise_lsb=1.0), usb=True)
    rig.drain(0.1)
    t0 = rig.m.now()
    n0 = len(rig.probe.pubs)
    frames = rig.drain(3.0)
    ev = [f for f in frames if f['type'] == T.FR_EVENT and f['cmd'] == T.E_MEASURE]
    pubs = rig.probe.pubs[n0 - 1 if n0 else 0:]
    changed = sum(1 for a, b in zip(pubs, pubs[1:]) if (a['Z'], a['TH']) != (b['Z'], b['TH']) and b['t'] > t0)
    check(abs(len(ev) - changed) <= 1 and changed >= 3, 'm11 MEASURE_DONE: %d events, %d changed windows' % (len(ev), changed))
    rig.watch.check(what='m11 MEASURE_DONE')
    return True


# ---------------------------------------------------------------- m12 factory table

def sweep(rig, seconds=360.0):
    """Settings item 5 (calibration), key 8 (dialog), key 8 (start; the type 0x200050E0 is 0, the short),
    then the run until 0x200050E4 is 0 again (own/cal.s, stage 3: 15 points of 3 windows, at most
    20 s each, plus at most 30 s of the S4.4 bias wait after the start) and 1 s for its save."""
    settings_item(rig, 5)
    tap(rig, KEY_OK)
    check(rig.rd(V_DIALOG) != 0, 'calibration dialog not open')
    check(rig.rd(V_CAL_TYPE) == 0, 'calibration type %d' % rig.rd(V_CAL_TYPE))
    tap(rig, KEY_OK)
    check(rig.rd(V_CAL_RUN) != 0, 'calibration not started')
    wait_until(rig, lambda: rig.rd(V_CAL_RUN) == 0, seconds, 'calibration end')
    rig.run(1.0)


def menu_restore(rig):
    """Item 6, key 8 (dialog), key 8 (the restore box), key 4 (choice 1), key 8 (restore: fn_08009974 ->
    0x08009A5E; test_own_lang.py l02)."""
    settings_item(rig, 6)
    tap(rig, KEY_OK)
    tap(rig, KEY_OK)
    tap(rig, KEY_4)
    tap(rig, KEY_OK)
    rig.run(0.5)


def vendor_save_end(vr, end, what):
    """V1.1 saves through its own flash routines (fn_08008dc0: the word program store at 0x08008DEC,
    switched off in our build, periph_34.s): the chip model stops at its first word program, which is
    not followed by five NOPs (meter_model's rule of manual 3.2.1.4.2). The controls' subject (the
    writes into the factory table) comes before that save; any other end is a failure."""
    if end is None:
        return
    viol = vr.m.st['viol']
    check(end == 'violation' and viol and all('store at 0x08008DEC' in v and 'five NOPs' in v for v in viol),
          '%s: V1.1 run ended %r (%r)' % (what, end, viol[:3]))
    NOTES.append('%s: V1.1 stopped at its own save (%s)' % (what, viol[0]))


def vendor_menu_restore(vr):
    """menu_restore on V1.1: the last key 8 runs fn_0800b4c8 and then V1.1's save (vendor_save_end)."""
    settings_item(vr, 6)
    tap(vr, KEY_OK)
    tap(vr, KEY_OK)
    tap(vr, KEY_4)
    vr.keys.down |= KEY_OK
    end = vr.run_end(0.06)
    vr.keys.down &= ~KEY_OK
    if end is None:
        end = vr.run_end(1.0)
    vendor_save_end(vr, end, 'm12 (d) restore')


def factory_block():
    """A block whose factory table differs from the nominal defaults (every short entry 0.001 ohm) and
    whose user table differs from the factory table (every short entry 0.002 ohm): a restore that
    writes the defaults into the factory table, a copy of the user table over it and a mode-0 restore
    (user := factory) are each visible."""
    b = bytearray(settings())
    for i in range(5):
        for j in range(3):
            struct.pack_into('<f', b, 4 + 0x90 * i + 0x30 * j, 0.001)
            struct.pack_into('<f', b, 0x5A4 + 0x90 * i + 0x30 * j, 0.002)
    return bytes(b)


# a 0.5 ohm part with the model's default scale saturates ADC2 even at c6 = 0 / range 100 ohm (the
# ideal source); 7 counts per volt puts I at about 1186 counts there and V at about 759 counts at c5 = 7
K_SHORT = 7.0


@case
def m12_factory_table():
    """S1.9 / D17: (a) start-up with PC11 low (0x200011C0 = 1), screen 3, a 0.5 ohm part: the gate of
    fn_0800bd5c sets 2; a complete short sweep then leaves 0x20000580..0x20000B1F equal to the loaded
    block (the watch: no writer but the start-up ones). (b) z = -0.5 + j0.1 ohm on screen 3: 0x200011C0
    stays 1. (c) Factory mode 2 (PE6 and PE0 low), the menu restore: the factory table unchanged, the user
    table equal to it. (d) Control: (a) and (c) on the vendor build, where the factory table changes (the
    copy of fn_0800bcd8, the mode-1 defaults) and the watch records the writer. V1.1's complete sweep
    cannot run in this model (at its 100 kHz steps V1.1 stops by the IWDG, m02), so the control of (a)
    takes the gate on screen 3 as (a) does and then calls the sweep's last step fn_0800bcd8 (app_02.s,
    reached from fn_0800bd5c at step 45) directly."""
    blk = factory_block()
    # (a)
    rig = own_rig(DutSource('R', 0.5, counts_per_volt=K_SHORT), block=blk, keys_at_start=KEY_PC11)
    check(rig.rd(V_FACTORY) == 1, '(a) factory word %d' % rig.rd(V_FACTORY))
    sweep(rig)
    check(rig.rd(V_FACTORY) == 2, '(a): the gate did not set 2 (word %d)' % rig.rd(V_FACTORY))
    usr = rig.rd(USR_LO, USR_HI - USR_LO)
    check(usr != blk[0x5A4:0xB44], '(a): the sweep stored nothing in the user table')
    check(any(rig.watch.kind(pc, lr) == 'bb64' for _, pc, lr, _, _ in rig.watch.usr), '(a): no store of fn_0800bb64')
    rig.watch.check(what='m12 (a)')
    # (b)
    rig = own_rig(DutSource(z=lambda f: complex(-0.5, 0.1), counts_per_volt=K_SHORT), block=blk, keys_at_start=KEY_PC11)
    settings_item(rig, 0)
    rig.run(7.0)
    pubs = [p for p in rig.probe.pubs if p['screen'] == 3 and not is_set(p)]
    check(pubs and all(u32f(p['RS']) < 0 for p in pubs), '(b): Rs %r' % [u32f(p['RS']) for p in pubs])
    check(rig.rd(V_FACTORY) == 1, '(b): factory word %d' % rig.rd(V_FACTORY))
    rig.watch.check(what='m12 (b)')
    # (c)
    rig = own_rig(DutSource('R', 1000.0), block=blk, keys_at_start=KEY_HOLD | KEY_PE0)
    check(rig.rd(V_FACTORY) == 2, '(c) factory word %d' % rig.rd(V_FACTORY))
    rig.run(0.5)
    if rig.rd(V_HOLD):
        tap(rig, KEY_HOLD)
    menu_restore(rig)
    check(rig.rd(FAC_LO, FAC_HI - FAC_LO) == blk[4:0x5A4], '(c): the factory table changed')
    check(rig.rd(USR_LO, 0x5A0) == blk[4:0x5A4], '(c): the user table is not the factory table')
    check(any(rig.watch.kind(pc, lr) == 'b4c8' for _, pc, lr, _, _ in rig.watch.fac), '(c): the restore did not run')
    rig.watch.check(restore=True, what='m12 (c)')
    # (d)
    vr = VRig(DutSource('R', 0.5, counts_per_volt=K_SHORT), block=blk, keys_at_start=KEY_PC11)
    settings_item(vr, 0)
    wait_until(vr, lambda: vr.rd(V_FACTORY) == 2, 7.0, '(d) V1.1: the gate')
    vr.m.call(vr.s['fn_0800bcd8'])
    end = vr.m.st['end']
    vendor_save_end(vr, None if end == 'return' else end, 'm12 (d) fn_0800bcd8')
    check(vr.rd(FAC_LO, FAC_HI - FAC_LO) == blk[0x5A4:0xB44], '(d) V1.1: the factory table is not the user table')
    kinds = {vr.watch.kind(pc, lr) for _, pc, lr, _, _ in vr.watch.fac}
    check('bcd8-copy' in kinds, '(d) V1.1: the copy of fn_0800bcd8 not seen (%r)' % kinds)
    vr = VRig(DutSource('R', 1000.0), block=blk, keys_at_start=KEY_HOLD | KEY_PE0)
    vr.run(0.5)
    if vr.rd(V_HOLD):
        tap(vr, KEY_HOLD)
    vendor_menu_restore(vr)
    check(vr.rd(FAC_LO, FAC_HI - FAC_LO) != blk[4:0x5A4], '(d) V1.1 restore: the factory table did not change')
    kinds = {vr.watch.kind(pc, lr) for _, pc, lr, _, _ in vr.watch.fac}
    check(kinds & {'b4c8', 'b4c8-store'}, '(d) V1.1 restore: fn_0800b4c8 not seen (%r)' % kinds)
    NOTES.append('m12 (d) V1.1 writers of the factory table: sweep and restore %r' % sorted(kinds))
    return True


# ---------------------------------------------------------------- m13 restart

@case
def m13_restart():
    """S1.4 restart detection: the Func key (key 0x200, app_01.s: Func 0x20001148 + 1, then bl fn_08009f10
    at 0x08009700) restarts the measurement with every watched word unchanged: the window is reset and
    no acquisition used afterwards was started before the call."""
    rig = own_rig(DutSource('R', 1000.0))
    rig.run(1.0)
    for _ in range(2):
        n0 = len(rig.probe.f10)
        tap(rig, KEY_FUNC)
        check(len(rig.probe.f10) > n0, 'm13: fn_08009f10 not called by the Func key')
        tr = rig.probe.f10[-1]
        rig.run(1.0)
        used = [a for a in rig.probe.acqs if a['t'] > tr]
        check(used, 'm13: no acquisition after the restart')
        for a in used:
            t_re = rig.probe.rearm_time(a['g'])
            check(t_re is not None and t_re > tr, 'm13: an acquisition started before the restart was used')
        check(any(t >= tr for t in rig.probe.resets), 'm13: no window reset')
        for p in rig.probe.pubs:
            if p['t'] > tr and p['adds']:
                check(all(ad['t'] > tr for ad in p['adds']), 'm13: a window holds an addition from before the restart')
    rig.watch.check(what='m13')
    return True


# ---------------------------------------------------------------- m14 handshake

def step3_addr(rig):
    """The address after meas_acq's bl meas_dft (the step-3 load of G)."""
    lo, hi = func_ranges(rig.s)['meas_acq']
    code = bytes(rig.m.uc.mem_read(lo, hi - lo))
    tgt = rig.s['meas_dft'] & ~1
    for i in range(0, len(code) - 3, 2):
        h1, h2 = struct.unpack_from('<HH', code, i)
        if h1 >> 11 == 0x1E and h2 >> 14 == 3 and h2 & 0x1000:
            s = (h1 >> 10) & 1
            j1, j2 = (h2 >> 13) & 1, (h2 >> 11) & 1
            i1, i2 = 1 - (j1 ^ s), 1 - (j2 ^ s)
            off = (s << 24) | (i1 << 23) | (i2 << 22) | ((h1 & 0x3FF) << 12) | ((h2 & 0x7FF) << 1)
            if s:
                off -= 1 << 25
            if lo + i + 4 + off == tgt:
                return lo + i + 4
    raise AssertionError('bl meas_dft not found')


@case
def m14_handshake():
    """S1.4 handshake, traced by G (own_dma_rearm), meas_arm, meas_win and the DMA model: every used
    acquisition was started by exactly one re-arm after our own last request, and
    (a) a request byte 0x200011C4 = 1 forced at the start of the reads (meas_dft) at 10 kHz (a 400 us
        acquisition, DAC period 100 us): at the step-3 check the new acquisition still runs (DMA1 ch1
        TXNUM > 0): discarded (no meas_win); (b) the same at 100 kHz (160 us acquisition, 10 us DAC
        period): completed at the check (TXNUM 0, flags set), discarded (G changed); (c) the byte forced
        after a completed acquisition, before the next own_measure: G > G_exp, no meas_acq, a re-arm;
        (d) fn_08009f10 between two calls (m13); (e) wrap: G = 0xFFFFFFFE written before a restart, (a)
        and (c) repeated across 0xFFFFFFFF -> 0 with the same verdicts and acquisitions accepted after it;
        (f) from reset: the first own_measure on screen 1 takes the restart path and sets the request
        with G_exp = G + 1 before any acquisition is accepted."""
    def used_after_own_request(rig, what):
        for a in rig.probe.acqs:
            arms = [t for t, g in rig.probe.arms if t < a['t']]
            check(arms, '%s: an acquisition before any own request' % what)
            res = [t for t, g in rig.probe.rearms if arms[-1] < t < a['t']]
            check(len(res) == 1 and rig.probe.rearm_time(a['g']) == res[0],
                  '%s: %d re-arms between our request and the use' % (what, len(res)))

    def force_in_reads(rig, f, what):
        st3 = step3_addr(rig)
        state = dict(armed=False, forced=None, check=None)

        def at_dft(uc, a, size, u):
            if state['armed'] and state['forced'] is None:
                rig.wr(V_C4, bytes([1]))
                state['forced'] = (rig.m.now(), mo(rig, 'G'), len(rig.probe.acqs))
        rig.m.uc.hook_add(UC_HOOK_CODE, at_dft, begin=rig.s['meas_dft'] & ~1, end=rig.s['meas_dft'] & ~1)

        def at_st3(uc, a, size, u):
            if state['forced'] is not None and state['check'] is None:
                rig.meas.sync()
                ch = rig.meas.dma[0][0]
                state['check'] = (mo(rig, 'G'), ch.txnum, rig.meas.flags[0] & 0x20000002)
        rig.m.uc.hook_add(UC_HOOK_CODE, at_st3, begin=st3, end=st3)
        state['armed'] = True
        wait_until(rig, lambda: state['check'] is not None, 1.0, '%s: forced request' % what)
        tf, g0, n0 = state['forced']
        g1, txn, flg = state['check']
        rig.run(0.05)
        check(g1 != g0, '%s: no re-arm during the reads' % what)
        check(len(rig.probe.acqs) == n0 or rig.probe.acqs[n0]['g'] != g0, '%s: the acquisition was used' % what)
        return txn, flg

    # (a) 10 kHz
    rig = own_rig(DutSource('R', 1000.0), freq=10000)
    rig.run(1.0)
    txn, flg = force_in_reads(rig, 10000, 'm14 (a)')
    check(txn > 0, 'm14 (a): the re-armed acquisition was already complete at the check (TXNUM %d)' % txn)
    used_after_own_request(rig, 'm14 (a)')
    rig.watch.check(what='m14 (a)')
    # (b) 100 kHz
    rig = own_rig(DutSource('R', 1000.0), freq=100000)
    rig.run(1.0)
    txn, flg = force_in_reads(rig, 100000, 'm14 (b)')
    check(txn == 0 and flg == 0x20000002, 'm14 (b): at the check TXNUM %d flags 0x%X (complete expected)' % (txn, flg))
    used_after_own_request(rig, 'm14 (b)')
    rig.watch.check(what='m14 (b)')

    # (c) and (e) at 1 kHz
    def force_between(rig, what):
        # at the entry of own_measure (before its first instruction): our acquisition has completed and
        # this call has not seen it yet (a main-loop pass takes about 0.14 ms at 1 kHz, measured, so the
        # completion falls inside a pass and only this point lies between it and the call's step 1)
        ret = rig.s['own_measure'] & ~1
        state = dict(armed=False, done=None)

        def after(uc, a, size, u):
            if not state['armed'] or state['done'] is not None:
                return
            rig.meas.sync()
            if rig.rd8(V_C4) == 0 and rig.meas.dma[0][0].txnum == 0 and mo(rig, 'G') == mo(rig, 'GEXP'):
                rig.wr(V_C4, bytes([1]))
                state['done'] = (rig.m.now(), len(rig.probe.acqs), len(rig.probe.arms), mo(rig, 'G'))
        rig.m.uc.hook_add(UC_HOOK_CODE, after, begin=ret, end=ret)
        state['armed'] = True
        wait_until(rig, lambda: state['done'] is not None, 1.0, '%s: completed acquisition' % what)
        t, na, nr, g = state['done']
        wait_until(rig, lambda: len(rig.probe.arms) > nr, 0.5, '%s: re-arm' % what)
        check(all(a['g'] != g for a in rig.probe.acqs[na:]), '%s: the stale acquisition was used' % what)
        check(any(gg == (g + 1) & 0xFFFFFFFF for _, gg in rig.probe.rearms), '%s: the forced re-arm not seen' % what)

    rig = own_rig(DutSource('R', 1000.0))
    rig.run(1.0)
    force_between(rig, 'm14 (c)')
    rig.run(0.5)
    used_after_own_request(rig, 'm14 (c)')
    # (e) wrap: G written before a restart (the Func key: fn_08009f10); the restart path's request
    # sets G_exp = G + 1 = 0xFFFFFFFF, or 0 when the re-arm of the restart's own C4 = 1 (fn_08007bdc,
    # measure_32.s 240) is served before own_measure sees the restart (it counts G to 0xFFFFFFFF
    # first; which one comes first depends on the length of the key handler's pass). Both cross the
    # wrap 0xFFFFFFFF -> 0 at the next re-arms, which the checks after it require.
    na = len(rig.probe.arms)
    rig.wr(OWN_MEAS + MO['G'], 0xFFFFFFFE)
    tap(rig, KEY_FUNC)
    wrap_arms = [g for _, g in rig.probe.arms[na:na + 4]]
    check(wrap_arms and wrap_arms[0] in (0xFFFFFFFE, 0xFFFFFFFF), 'm14 (e): the restart request at G %r'
          % [hex(g) for g in wrap_arms])
    NOTES.append('m14 (e): the restart request at G 0x%08X (G_exp 0x%08X)' % (wrap_arms[0], (wrap_arms[0] + 1) & 0xFFFFFFFF))
    n0 = len(rig.probe.acqs)
    rig.run(0.5)
    check(mo(rig, 'G') < 0x1000 and len(rig.probe.acqs) > n0 + 5, 'm14 (e): G 0x%08X, %d acquisitions after the wrap'
          % (mo(rig, 'G'), len(rig.probe.acqs) - n0))
    force_between(rig, 'm14 (e) (c)')
    rig.wr(OWN_MEAS + MO['G'], 0xFFFFFFFE)
    tap(rig, KEY_FUNC)
    rig.run(0.1)
    force_between(rig, 'm14 (e) (c) at the wrap')
    n1 = len(rig.probe.acqs)
    rig.run(0.5)
    check(len(rig.probe.acqs) > n1 + 5 and rig.probe.normal(rig.m.now() - 0.6), 'm14 (e): measurement stopped after the wrap')
    rig.watch.check(what='m14 (c) (e)')
    # (e) with (a): 10 kHz across the wrap
    rig = own_rig(DutSource('R', 1000.0), freq=10000)
    rig.run(1.0)
    rig.wr(OWN_MEAS + MO['G'], 0xFFFFFFFE)
    tap(rig, KEY_FUNC)
    rig.run(0.05)
    txn, flg = force_in_reads(rig, 10000, 'm14 (e) (a)')
    check(txn > 0, 'm14 (e) (a): TXNUM %d' % txn)
    rig.run(0.5)
    check(len(rig.probe.acqs) > 5 and mo(rig, 'G') < 0x1000, 'm14 (e) (a): G 0x%08X' % mo(rig, 'G'))
    rig.watch.check(what='m14 (e) (a)')
    # (f) from reset
    blk = settings()
    rig = Ctl(a=copy_image(blk, 2), b=copy_image(blk, 1), usb=False, source=DutSource('R', 1000.0))
    rig.block, rig.vendor = blk, False
    rig.watch = TableWatch(rig)
    rig.probe = Probe(rig)
    first = []
    om = rig.s['own_measure'] & ~1

    def entry(uc, a, size, u):
        if not first and rig.rd(V_SCREEN) in (1, 2, 3):
            first.append((rig.m.now(), rig.rd(V_MARK), len(rig.probe.arms)))
    rig.m.uc.hook_add(UC_HOOK_CODE, entry, begin=om, end=om)
    rig.up()
    rig.run(0.5)
    check(first and first[0][1] == 0, 'm14 (f): first call %r (marker 0 expected)' % first)
    check(rig.probe.arms and rig.probe.arms[0][0] >= first[0][0] and first[0][2] == 0,
          'm14 (f): no own request in the first call')
    check(not rig.probe.acqs or rig.probe.acqs[0]['t'] > rig.probe.arms[0][0], 'm14 (f): an acquisition before our first request')
    used_after_own_request(rig, 'm14 (f)')
    rig.watch.check(what='m14 (f)')
    return True


# ---------------------------------------------------------------- m17 open terminals, noise-limited I

class OpenGauss(DutSource):
    """Open terminals as the meter showed them (2026-11-22, image 760aebc, 1 kHz 0.6 V): V the generator
    (p-p about 2100 at c5 = 0, DutSource's k), I = 2048 + Gaussian noise of RMS sigma23 * G[c6] / G[2] *
    R[c8] / R[3] counts (noise before the gain stage and the range resistor; the meter: c6 = 2, c8 = 3,
    residual sigma 410..633 counts, p-p 2035..2613), clipped to 0..4095. Gaussian by Box-Muller from a
    fixed linear congruential sequence (the same sequence in every run)."""

    def __init__(self, sigma23):
        super().__init__(kind='R', value=1e12)
        self.sigma23, self.s, self.spare = sigma23, 2463534242, None

    def gauss(self):
        if self.spare is not None:
            g, self.spare = self.spare, None
            return g
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        u1 = (self.s + 1) / 0x80000000
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        u2 = self.s / 0x80000000
        r = math.sqrt(-2.0 * math.log(u1))
        self.spare = r * math.sin(2 * math.pi * u2)
        return r * math.cos(2 * math.pi * u2)

    def i_codes(self, c6, c8, n):
        rms = self.sigma23 * GAIN[c6] / GAIN[2] * RANGE_OHM[c8] / RANGE_OHM[3]
        return [max(0, min(4095, int(round(2048 + rms * self.gauss())))) for _ in range(n)]

    def samples(self, path, adc, channel, times):
        if adc != 2:
            return super().samples(path, adc, channel, times)
        c5, c6, c8 = path.front_end()
        return self.i_codes(c6, c8, len(times))


def out_of_band(codes):
    """The ranging's criterion on one ADC2 acquisition (meas.s meas_acq, fn_0800b000): saturated (a code 0
    or 4095: p-p taken as 4095) or p-p below 1500 or above 3600."""
    pp = 4095 if max(codes) >= 4095 or min(codes) == 0 else max(codes) - min(codes)
    return pp < 1500 or pp > 3600


@case
def m17_open_noise():
    """Open terminals with a noise-limited I channel (OpenGauss, sigma 545 counts at c6 = 2, c8 = 3, 1 kHz,
    speed 0). Input property first, by the firmware's criterion (out_of_band) on 4000 acquisitions of the
    source at c6 = 2, c8 = 3: at least 1 % out of band (so a range step on a single acquisition resets the
    window more often than once per T_win = 1 s at about 500 acquisitions per second), at most 10 %
    (so three in a row are rare: below 0.1 %, and the band holds the channel at c6 = 2), at c6 = 3 at
    least 90 % and at c6 = 1 at least 50 % out of band (a step away from c6 = 2 is followed by a step
    back within a few acquisitions). Then the firmware (S1.6, meas.s meas_acq: the first and second
    out-of-band acquisition in a row are not ranged): codes 0x30200 (c5 0, c6 2, c8 3) at the end, and
    windows published (not the 1e10 set) after 3 s: at least 3 in the 5 s from 3 s to 8 s."""
    src = OpenGauss(545.0)
    probe_src = OpenGauss(545.0)
    probe_src.s = 987654321
    oob = [out_of_band(probe_src.i_codes(2, 3, 128)) for _ in range(4000)]
    p = sum(oob) / len(oob)
    runs3 = sum(1 for a, b, c in zip(oob, oob[1:], oob[2:]) if a and b and c) / (len(oob) - 2)
    up = sum(out_of_band(probe_src.i_codes(3, 3, 128)) for _ in range(500)) / 500
    dn = sum(out_of_band(probe_src.i_codes(1, 3, 128)) for _ in range(500)) / 500
    check(0.01 <= p <= 0.10 and runs3 <= 0.001 and up >= 0.9 and dn >= 0.5,
          'm17 input: out of band at c6 2: %.4f (3 in a row %.5f), at c6 3: %.3f, at c6 1: %.3f' % (p, runs3, up, dn))
    NOTES.append('m17 input: out of band at c6 = 2: %.2f %% (3 in a row %.3f %%), c6 = 3: %.1f %%, c6 = 1: %.1f %%'
                 % (100 * p, 100 * runs3, 100 * up, 100 * dn))
    rig = own_rig(src, freq=1000, speed=0)
    log_codes(rig)
    rig.run(8.0)
    codes = (rig.rd8(V_C5), rig.rd8(V_C6), rig.rd8(V_C8))
    pubs = [q for q in rig.probe.normal(3.0) if not is_set(q)]
    late = [x for x in rig.code_log if x[0] > 3.0]
    NOTES.append('m17: codes %r, %d windows after 3 s (SEQ %d), %d code changes and %d meas_change calls after '
                 '3 s, %d acquisitions used' % (codes, len(pubs), mo(rig, 'SEQ'), len(late),
                                                 len([t for t in rig.probe.changes if t > 3.0]), len(rig.probe.acqs)))
    check(codes == (0, 2, 3), 'm17: codes %r at the end (0, 2, 3 expected)' % (codes,))
    check(len(pubs) >= 3, 'm17: %d windows published from 3 s to 8 s (SEQ %d, %d code changes after 3 s)'
          % (len(pubs), mo(rig, 'SEQ'), len(late)))
    for q in pubs:
        no_nan(q, 'm17')
    rig.watch.check(what='m17')
    return True


# ---------------------------------------------------------------- m18 / m19 hunting I gain (S1.8)

class HuntNoise(OpenGauss):
    """Broadband I noise whose level drifts, as the meter showed it at open terminals (2026-11-22, image
    5ee0a86, 1 kHz: c6 between 3 and 2, I p-p 3549..3910 at c6 = 3 and 1843..2021 at c6 = 2, the ADC2
    buffer p-p 590..3638 over four reads: a noise level that moves). V the generator (DutSource), I =
    2048 + (a component: the DutSource current k G[c6] R[c8] Re(v / Z)) + Gaussian noise (OpenGauss's
    sequence) of RMS sigma(t) * G[c6] / G[2] * R[c8] / R[3], sigma(t) = s0 + sa sin(2 pi t / period) at the
    acquisition's first sample, clipped to 0..4095. The period (1.2 s) is a choice of this model: the
    meter's reads were 3 s apart and cannot show faster changes, and its MO_SEQ went 1 -> 2 in 30 s, so
    no in-band run there lasted a window (m17 closes windows on steady noise of this kind)."""

    def __init__(self, z_ohm=None, s0=300.0, sa=100.0, period=1.2):
        super().__init__(0.0)
        self.zc, self.s0, self.sa, self.period = z_ohm, s0, sa, period

    def sigma(self, t):
        return self.s0 + self.sa * math.sin(2 * math.pi * t / self.period)

    def pp(self, sigma23, c6, c8, n):
        """n acquisitions' ADC2 codes of the noise alone at level sigma23 (for the input checks)."""
        self.sigma23 = sigma23
        return [self.i_codes(c6, c8, 128) for _ in range(n)]

    def samples(self, path, adc, channel, times):
        if adc != 2:
            return DutSource.samples(self, path, adc, channel, times)
        c5, c6, c8 = path.front_end()
        f = path.frequency()
        rms = self.sigma(times[0]) * GAIN[c6] / GAIN[2] * RANGE_OHM[c8] / RANGE_OHM[3]
        coh = [0.0] * len(times)
        if self.zc is not None and f > 0:
            coh = [self.k * GAIN[c6] * RANGE_OHM[c8] * (x / complex(self.zc, 0.0)).real for x in path.generator(times)]
        return [max(0, min(4095, int(round(2048 + c + rms * self.gauss())))) for c in coh]


M18_T0, M18_END, M18_GAP = 4.0, 12.0, 2.5


def hunt_input(src, what):
    """The input property of m18, by the firmware's band criterion (out_of_band) on 400 acquisitions of a
    second source of the same model per point: at the lowest level (s0 - sa) c6 = 2 is out of band in at
    least 90 % (p-p below 1500: fn_0800b000 steps c6 up) and c6 = 3 in band in at least 90 %; at the
    highest (s0 + sa) c6 = 3 out of band in at least 90 % (above 3600: steps down) and c6 = 2 in band in at
    least 90 %. So the drift forces a step at both ends and the code stepped to holds in-band runs."""
    p = HuntNoise(s0=src.s0, sa=src.sa, period=src.period)
    p.s = 987654321
    frac = {}
    for lvl, name in ((src.s0 - src.sa, 'lo'), (src.s0 + src.sa, 'hi')):
        for c6 in (2, 3):
            frac[name, c6] = sum(map(out_of_band, p.pp(lvl, c6, 3, 400))) / 400.0
    check(frac['lo', 2] >= 0.9 and frac['lo', 3] <= 0.1 and frac['hi', 3] >= 0.9 and frac['hi', 2] <= 0.1,
          '%s input: out of band lo c6 2 / 3 %.3f / %.3f, hi c6 2 / 3 %.3f / %.3f'
          % (what, frac['lo', 2], frac['lo', 3], frac['hi', 2], frac['hi', 3]))
    return frac


def hunting(func):
    """S1.8 "No reading" (hunting longer than 2 s gives the no-reading set) with the I gain hunting at open
    terminals, Func `func` (word 0x20001148 from the settings), 1 kHz, speed 0 (T_win 1 s), range AUTO,
    source HuntNoise without a component.
    Input checked first: hunt_input; then from the run, after M18_T0: c5 and c8 unchanged (c8 = 3, the
    codes hunt_input assumes); every used acquisition's I noise-limited (float64 |X_I|^2 < 64 * 8^2 *
    max(sigma^2, 1/12), dft64 of the captured buffer: below the stay-resolved threshold of meas_win); c6
    changes at least 8 times, at least 6 of them with a used acquisition since the change before (a
    window started, then cut by an own range step: in-band runs between the steps).
    Expected, from M18_T0 to M18_END: the no-reading set published (is_set at the store of 1 to
    0x20001200) at least every M18_GAP seconds = the 2 s of S1.8 + 0.5 s (the steps that establish the
    hunting at its start, one display update); no output word NaN; every publish finite or the set."""
    blk = block_with(**{'0x%08x' % T.V_FUNC: func, '0x%08x' % V_FREQ: 1000, '0x%08x' % V_SPEED: 0})
    src = HuntNoise()
    frac = hunt_input(src, 'm18 Func %d' % func)
    rig = own_rig(src, block=blk)
    log_codes(rig)
    check(rig.rd(T.V_FUNC) == func, 'm18 Func %d: Func word %d after the start' % (func, rig.rd(T.V_FUNC)))
    rig.run(M18_END - rig.m.now())
    used = [a for a in rig.probe.acqs if a['t'] > M18_T0]
    check(len(used) >= 50, 'm18 Func %d input: %d used acquisitions after %.1f s' % (func, len(used), M18_T0))
    other = [x for x in rig.code_log if x[0] > M18_T0 and x[1] != V_C6]
    check(not other and rig.rd8(V_C8) == 3, 'm18 Func %d input: c5 / c8 changes %r, c8 %d' % (func, other, rig.rd8(V_C8)))
    for a in used:
        X, s2 = dft64(a['i'], 1)
        check(abs(X) ** 2 < 64 * 8 ** 2 * max(s2, 1 / 12.0),
              'm18 Func %d input: I resolved at t %.3f (|X|^2 %.4g, sigma^2 %.4g)' % (func, a['t'], abs(X) ** 2, s2))
    c6 = [t for t, ad, v in rig.code_log if ad == V_C6 and t > M18_T0]
    cut = sum(1 for t1, t2 in zip(c6, c6[1:]) if any(t1 < a['t'] < t2 for a in used))
    check(len(c6) >= 8 and cut >= 6, 'm18 Func %d input: c6 changes %d, with a used acquisition before %d'
          % (func, len(c6), cut))
    pubs = [p for p in rig.probe.pubs if p['t'] > M18_T0]
    sets = [p['t'] for p in pubs if is_set(p)]
    times = [M18_T0] + sets + [rig.m.now()]
    gaps = [b - a for a, b in zip(times, times[1:])]
    NOTES.append('m18 Func %d: %d publishes (%d the set), longest gap between sets %.2f s, c6 changes %d (%d '
                 'cut a window), input lo c6 2 / 3 %.2f / %.2f, hi %.2f / %.2f out of band'
                 % (func, len(pubs), len(sets), max(gaps), len(c6), cut, frac['lo', 2], frac['lo', 3],
                    frac['hi', 2], frac['hi', 3]))
    check(max(gaps) <= M18_GAP, 'm18 Func %d: no no-reading set for %.2f s (publishes %d after %.1f s, %d sets, '
          'MO_SEQ %d, 0x2000120C %d, MO_FL 0x%X)' % (func, max(gaps), len(pubs), M18_T0, len(sets), mo(rig, 'SEQ'),
                                                     rig.rd(V_NRCNT), mo(rig, 'FL')))
    for p in pubs:
        no_nan(p, 'm18 Func %d' % func)
        check(is_set(p) or (p['Z'] & 0x7F800000) != 0x7F800000, 'm18 Func %d: |Z| 0x%08X' % (func, p['Z']))
    rig.watch.check(what='m18 Func %d' % func)
    return True


@case
def m18a_hunting_auto():
    """hunting in Func 0 (AUTO)."""
    return hunting(0)


@case
def m18b_hunting_r():
    """hunting in Func 1."""
    return hunting(1)


@case
def m18c_hunting_c():
    """hunting in Func 2."""
    return hunting(2)


@case
def m18d_hunting_l():
    """hunting in Func 3."""
    return hunting(3)


@case
def m18e_hunting_z():
    """hunting in Func 4."""
    return hunting(4)


@case
def m19_noise_under_part():
    """The control of m18: a 10 kohm resistor with the same drifting noise (HuntNoise, z_ohm 10000), Func 0,
    1 kHz, speed 0, range AUTO. Input checked first, after M18_T0: the codes unchanged, and in every used
    acquisition the I bin |X_I| / 64 (the amplitude, dft64) at least 20 times the residual RMS sqrt(sigma^2)
    (the noise far below the signal) and I p-p within 1500..3600 (no band step). Expected, from M18_T0 to
    M18_END: no no-reading or overload set, normal publishes at least every T_win + 11 ms + 2 acquisition
    intervals (p01's bound), at least 7 of them, |Z| within 1 % of 10 kohm, no output word NaN; MO_FL bit 7
    (hunting) never set at a publish."""
    blk = block_with(**{'0x%08x' % V_FREQ: 1000, '0x%08x' % V_SPEED: 0})
    rig = own_rig(HuntNoise(z_ohm=10000.0), block=blk)
    log_codes(rig)
    hunt = []
    rig.probe.on_publish_entry = lambda r: hunt.append(mo(r, 'FL') & 0x80)
    rig.run(M18_END - rig.m.now())
    used = [a for a in rig.probe.acqs if a['t'] > M18_T0]
    late = [x for x in rig.code_log if x[0] > M18_T0]
    check(len(used) >= 50 and not late, 'm19 input: %d used acquisitions, code changes after %.1f s %r'
          % (len(used), M18_T0, late))
    snr = []
    for a in used:
        X, s2 = dft64(a['i'], 1)
        snr.append(abs(X) / 64 / math.sqrt(max(s2, 1 / 12.0)))
        pp = max(a['i']) - min(a['i'])
        check(1500 <= pp <= 3600, 'm19 input: I p-p %d at t %.3f' % (pp, a['t']))
    check(min(snr) >= 20, 'm19 input: smallest I amplitude / noise RMS %.1f' % min(snr))
    pubs = [p for p in rig.probe.pubs if p['t'] > M18_T0]
    times = [M18_T0] + [p['t'] for p in pubs] + [rig.m.now()]
    gaps = [b - a for a, b in zip(times, times[1:])]
    lim = 1.0 + 0.011 + 2 * rig.probe.acq_interval()
    zs = [u32f(p['Z']) for p in pubs]
    NOTES.append('m19: codes %r, %d publishes after %.1f s, longest gap %.3f s (limit %.3f), |Z| %.1f..%.1f, '
                 'smallest amplitude / noise %.0f' % ((rig.rd8(V_C5), rig.rd8(V_C6), rig.rd8(V_C8)), len(pubs), M18_T0,
                                                     max(gaps), lim, min(zs) if zs else 0, max(zs) if zs else 0, min(snr)))
    check(not any(is_set(p) for p in pubs), 'm19: %d no-reading / overload sets' % sum(map(is_set, pubs)))
    check(len(pubs) >= 7 and max(gaps) <= lim, 'm19: %d publishes, longest gap %.3f s' % (len(pubs), max(gaps)))
    for p, z in zip(pubs, zs):
        no_nan(p, 'm19')
        check(abs(z / 10000.0 - 1) <= 0.01, 'm19: |Z| %.2f at t %.3f' % (z, p['t']))
    check(not any(hunt), 'm19: MO_FL bit 7 set at %d of %d publish entries' % (sum(1 for h in hunt if h), len(hunt)))
    rig.watch.check(what='m19')
    return True


# ---------------------------------------------------------------- profile

@case
def p01_profile():
    """Main-loop pass time (mean over 2 s, hook at 0x080281C8) per frequency (100 Hz, 1 kHz, 100 kHz) in our
    build and in the vendor build (both in the emulator); windows per second at speed 0 / 1 / 2 (1 kHz):
    1 / 2 / 4, the gap between two windows within T_win - 11 ms .. T_win + 11 ms + 2 acquisition
    intervals (a window that follows a close is timed from it, meas_add; the tick word moves in steps
    of 10 ms; the closing acquisition comes at most one interval after T_win); the accepted count per
    window reported with the vendor's 0x200011F0."""
    out = []
    for f in (100, 1000, 100000):
        row = []
        for vendor in (False, True):
            rig = VRig(DutSource('R', 1000.0), freq=f) if vendor else own_rig(DutSource('R', 1000.0), freq=f)
            ts = []
            rig.m.uc.hook_add(UC_HOOK_CODE, lambda uc, a, s, u, l=ts, mm=rig.m: l.append(mm.now()), begin=MAIN_LOOP, end=MAIN_LOOP)
            if vendor:
                end = rig.run_end(2.0)
                if end is not None:
                    row.append('V1.1 ended %r at %.3f s' % (end, rig.m.now()))
                    continue
            else:
                rig.run(2.0)
            row.append('%.3f ms' % ((ts[-1] - ts[0]) / (len(ts) - 1) * 1e3))
            if not vendor:
                rig.watch.check(what='p01 %d Hz' % f)
        out.append('%d Hz %s / %s' % (f, row[0], row[1]))
    NOTES.append('p01 main-loop pass, own / V1.1: ' + ', '.join(out))
    for speed, twin in ((0, 1.0), (1, 0.5), (2, 0.25)):
        rig = own_rig(DutSource('R', 1000.0), speed=speed)
        rig.run(4.0)
        ts = [p['t'] for p in rig.probe.normal(1.0)]
        gaps = [b - a for a, b in zip(ts, ts[1:])]
        lim = twin + 0.011 + 2 * rig.probe.acq_interval()
        check(len(gaps) >= 2 and all(twin - 0.011 <= g <= lim for g in gaps), 'p01 speed %d: gaps %r (limit %.4f)'
              % (speed, gaps, lim))
        vr_count = {0: 0x1d6, 1: 0xfa}.get(speed, 0x5f)        # fn_08009f10 at 1 kHz
        NOTES.append('p01 speed %d: %d windows, gaps %.3f..%.3f s, N %r (V1.1 count 0x200011F0 %d)' % (
            speed, len(ts), min(gaps), max(gaps), sorted({p['n'] for p in rig.probe.normal(1.0)}), vr_count))
        rig.watch.check(what='p01 speed %d' % speed)
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
            import traceback
            traceback.print_exc()
            ok, msg = False, 'raised %r' % e
        print('%-40s %s %s' % (fn.__name__, 'ok' if ok else 'FAIL', msg), flush=True)
        bad += not ok
    for n in NOTES:
        print('  note:', n)
    print('%d tests, %d failed' % (run, bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
