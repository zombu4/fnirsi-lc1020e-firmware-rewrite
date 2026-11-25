#!/usr/bin/env python3
"""test_own_cal.py - the calibration sweep of our build (firmware/own/cal.s, stage 3), in the emulator.

Usage (from the repository root, after `make -C firmware own`):
    <python with unicorn 2.1.4> tests/test_own_cal.py [case-name-prefix ...]

Rig: tests/test_own_measure.py own_rig (our build, TableWatch m15 and the Probe armed from reset, the settings
block in copies A and B). This file adds CalProbe: the entries of cal_point (r0 = the point), cal_commit and
cal_abort / cal_fail, and every write of the step word 0x200050E8.

The expected result of a point comes from the specification of cal.s applied to the windows the probe saw
published on screen 3 between the point's cal_point and the next (expect_point). Short and reference points:
a no-reading / overload set or a non-finite window empties the held windows; the last 3 held are judged: the
median |Z| (signed compare) and the theta of the same window, accepted when every |Zi| <= 2 |Zm| and 2 |Zi| >=
|Zm|. The stored table entries must equal these bit for bit (fn_0800bb64 copies the words). Open points (type
11, revisions 10 and 11): such a window is skipped and the others kept; the first 7
usable windows (or all of them when the point's 20 s ended it first) give the open admittances Y_i = 1 / (Zo_i
- Zs), Zo_i = (|Z|_i + |t0|) e^(j theta_i), Zs = |t0| e^(j theta0) from the point's short entry (open_rule,
float64 from the float32 words). Resolved (n >= 2, n (n - 1) |Ybar|^2 / sum |Y_i - Ybar|^2 above the 0.999
quantile of F(2, 2n - 2)): the entry is |Zo| - |t0| and arg Zo of Zo = 1 / Ybar + Zs, within 1e-5 relative of
|Zo| and 0.01 degree [J: float32 sums of 7 terms and the vendor's single-precision sine / cosine]; else |Z|
1e10, theta +400 ("not resolved") bit for bit. A set whose ratio lies within 1e-3 of the limit may give
either (float32 against float64 at the edge). Revision 14: a resolved mean with
|Zo| >= 1e5 is kept only when Ybar = G + jB has B >= |G|, B > 0 and B <= 2 pi f 50 pF (the gate; else
"not resolved", kind 'gate'; a gate margin within 1e-6 of 0 may give either); after the 15th point every 100 /
120 Hz point "not resolved" is filled from the first resolved source (stored words) of FSRC: B_src = -Im D /
|D|^2 of D = Zo_src - Zs_src, B_low = B_src f_low / f_src, Zo_low = Zs_low - j / B_low (open_fill), matched as
a resolved entry.

Sources: measure_model.DutSource / test_own_measure.TDut; the counts per volt are chosen per case so that both
channels lie in band at a range and gain code the ranging reaches (the model's source is ideal; revision 5 row
18). RUN LIMIT: one run of this file per case prefix, 23 cases.
"""

import cmath
import math
import os
import struct
import sys

from unicorn import UC_HOOK_CODE, UC_HOOK_MEM_WRITE
from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_R1

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_own_measure as M  # noqa: E402
from test_own_measure import (own_rig, settings_item, tap, wait_until, TDut, is_set, u32f, f2u, USR_LO,  # noqa: E402
                              V_FREQ, V_LEVEL, V_BIAS, V_SPEED, V_SCREEN, V_MENU, V_DIALOG, V_CAL_TYPE,
                              V_CAL_RUN, KEY_OK, KEY_4, F_M400, F_1E10)
from test_own_control import (check, block_with, OK2, C, S_OK, S_NOT_NOW, S_SAFETY, SAVE_COUNT, E_CAL,  # noqa: E402
                              E_SAVE, E_SETTING, KEY_POWER, OWN_CAL, CAO_ON, CAO_REC, CAO_SFREQ, CAO_SLEVEL,
                              CAO_SBIAS, CAO_SSPEED, CAO_REL, V_CAL_WORK, host_timeout, BLK, V_BLOCK, fb_replay,
                              f1_draw)
from meter_model import SET_A, SET_B  # noqa: E402
from measure_model import DutSource  # noqa: E402
from usb_host import FR_ANSWER, FR_EVENT  # noqa: E402

CASES = []
NOTES = M.NOTES

# ---- own.inc OWN_CAL (cal.s) ----
CAO_PT, CAO_NW, CAO_TPT, CAO_FAILP, CAO_WHY, CAO_STYPE, CAO_WIN = 0x04, 0x08, 0x14, 0x20, 0x24, 0x3C, 0x40
CAO_NO, CAO_RES, CAO_OWIN = 0x0C, 0x58, 0x1C0
CA_NO_OPEN, CA_POINT_S = 7, 20.0                  # cal.s: usable windows that end an open point; CA_POINT_MS
R_NONE, R_STALL, R_TIME, R_OPEN, R_CHECK, R_SPREAD, R_ABORT = range(7)
V_CAL_STEP, V_CAL_STATUS = 0x200050E8, 0x200050EC
V_STAT_TXT, V_TYPE_TXT, V_STAT_NAMES, V_TYPE_NAMES, V_LANGUAGE = 0x20005960, 0x20005958, 0x200000FC, 0x2000009C, 0x2000115C
F_P400 = 0x43C80000
FREQS = (100, 120, 1000, 10000, 100000)
LEVELS = (0x3DCCCCCD, 0x3E99999A, 0x3F19999A)
NAMES = ['%s %sV' % (fs, lv) for fs in ('100', '120', '1k', '10k', '100k') for lv in ('0.1', '0.3', '0.6')]
TIM1_CTRL1 = 0x40012C00
# the settings before a sweep in the cases that check the restore (D10): 1 kHz, 0.3 V, speed 1, bias 0.5 V,
# and a pattern in 0x200010C0..0x20001137 (the vendor start zero-fills it)
PRE = {'0x%08x' % V_FREQ: 1000, '0x%08x' % V_LEVEL: 0x3E99999A, '0x%08x' % V_SPEED: 1, '0x%08x' % V_BIAS: 0x3F000000}
REL_PATTERN = bytes((7 * k + 3) & 0xFF for k in range(0x78))


def case(fn):
    CASES.append(fn)
    return fn


def pre_block(**extra):
    """block_with() with PRE, the 0x200010C0 pattern and extra words (address text -> value)."""
    words = dict(PRE)
    words.update(extra)
    b = bytearray(block_with(**words))
    b[V_CAL_WORK - V_BLOCK:V_CAL_WORK - V_BLOCK + 0x78] = REL_PATTERN
    return bytes(b)


def short_src():
    """c1's short z = 0.005 + j 2 pi f 78 nH, scaled by 10 (0.05 ohm + 780 nH: 0.05..0.49 ohm
    over the five frequencies, below the 0.9 ohm store check), so that the voltage channel keeps at least
    about 17 counts of amplitude at c5 = 7 and 0.1 V with 0.94 counts per volt, while the current channel
    stays in band at 100 ohm and a gain code the ranging reaches."""
    return DutSource(z=lambda f: complex(0.05, 2 * math.pi * f * 780e-9), counts_per_volt=0.94)


def entry(p, typ=0):
    """User-table address of point p (fi = p / 3, li = p mod 3) and type: 0x20000B20 + 0x90 fi + 0x30 li + 4 t."""
    return USR_LO + 0x90 * (p // 3) + 0x30 * (p % 3) + 4 * typ


def table(rig):
    return rig.rd(USR_LO, 0x5A0)


def cstr(rig, addr, n=48):
    b = rig.rd(addr, n)
    return b[:b.index(0)] if 0 in b else b


def obj_text(rig, word):
    """The text of the object in the word (fn_080228d0 keeps the built string at object + 0x24)."""
    o = rig.rd(word)
    check(o != 0, 'object word 0x%08X is 0' % word)
    return cstr(rig, rig.rd(o + 0x24))


class CalProbe:
    """cal_point (t, point), cal_commit / cal_fail / cal_abort times, writes of the step word."""

    def __init__(self, rig):
        m, s = rig.m, rig.s
        self.points, self.commits, self.fails, self.aborts, self.steps = [], [], [], [], []
        self.on_point = None

        def point(uc, a, size, u):
            p = uc.reg_read(UC_ARM_REG_R0)
            self.points.append((m.now(), p))
            if self.on_point is not None:
                self.on_point(rig, p)
        m.uc.hook_add(UC_HOOK_CODE, point, begin=s['cal_point'] & ~1, end=s['cal_point'] & ~1)
        for name, lst in (('cal_commit', self.commits), ('cal_fail', self.fails), ('cal_abort', self.aborts)):
            def hook(uc, a, size, u, lst=lst):
                lst.append(m.now())
            m.uc.hook_add(UC_HOOK_CODE, hook, begin=s[name] & ~1, end=s[name] & ~1)

        def step(uc, acc, addr, size, value, user):
            self.steps.append((m.now(), value))
        m.uc.hook_add(UC_HOOK_MEM_WRITE, step, begin=V_CAL_STEP, end=V_CAL_STEP + 3)
        # the end of cal_finish: its last instruction, the pop after `bl cal_text_status` at cal_save_ret
        # (cal.s; app_own.elf 0x0804F7B4 bl, 0x0804F7B8 pop). cal_finish stores CAO_ON = 0 before own_save,
        # whose page erases take 100 ms each in the model (meter_model T_ERASE), so CAO_ON = 0 alone does
        # not mean the save and the finish text are done (2026-11-23: c01 read "15/15", c22 saves 0 -> 0)
        self.finished, self.fin_block = [], None

        def fin(uc, a, size, u):
            self.finished.append(m.now())
            self.fin_block = bytes(uc.mem_read(M.V_BLOCK, M.BLK))   # the RAM block own_save has just saved
        a = (s['cal_save_ret'] & ~1) + 4
        m.uc.hook_add(UC_HOOK_CODE, fin, begin=a, end=a)


def cal_rig(source, block=None, usb=False, keys_at_start=0, panel=False):
    rig = own_rig(source, block=block, usb=usb, keys_at_start=keys_at_start, panel=panel)
    rig.cal = CalProbe(rig)
    return rig


def open_dialog(rig, typ=0):
    """Settings item 5, key 8 (the dialog), keys 4 until the type (outside factory mode it toggles 0 / 11)."""
    settings_item(rig, 5)
    tap(rig, KEY_OK)
    check(rig.rd(V_DIALOG) != 0, 'calibration dialog not open')
    for _ in range(12):
        if rig.rd(V_CAL_TYPE) == typ:
            break
        tap(rig, KEY_4)
    check(rig.rd(V_CAL_TYPE) == typ, 'calibration type %d, wanted %d' % (rig.rd(V_CAL_TYPE), typ))
    rig.run(0.1)                                     # one idle pass under the guard: cal_record


def start(rig, typ=0):
    open_dialog(rig, typ)
    tap(rig, KEY_OK)
    check(rig.rd(V_CAL_RUN) != 0, 'calibration not started')


def wait_point(rig, p, seconds=120.0):
    wait_until(rig, lambda: any(q == p for _, q in rig.cal.points), seconds, 'point %d reached' % p)


def wait_end(rig, seconds=360.0):                # CAL_LIMIT_MS (ctl.inc): 15 x 20 s + 30 s bias wait + 30 s
    # a finish (status 2) ends at the end of cal_finish, after own_save (CalProbe.finished); a fail or an
    # abort has no save between its CAO_ON = 0 and its text
    n0 = len(rig.cal.finished)
    wait_until(rig, lambda: rig.rd(V_CAL_RUN) == 0 and rig.rd(OWN_CAL + CAO_ON) == 0 and (
        rig.rd(V_CAL_STATUS) != 2 or len(rig.cal.finished) > n0), seconds, 'sweep end')
    # cal_fail stores CAO_ON = 0 before its last call, cal_text_fail (cal.s), and the condition is
    # polled between emulation slices, so it can be seen inside cal_fail (2026-11-22, the build
    # without ocal.s: c14 read the point text "10/15" instead of "Fail 10/15"); 0.2 s more lets
    # the call end
    rig.run(0.2)


def windows_of(rig, p, since=0.0):
    """The publishes on screen 3 between the last cal_point(p) after `since` and the next cal_point, commit,
    fail or abort."""
    starts = [t for t, q in rig.cal.points if q == p and t >= since]
    check(starts, 'point %d never set' % p)
    t0 = starts[-1]
    ends = [t for t, _ in rig.cal.points if t > t0] + [t for t in rig.cal.commits + rig.cal.fails + rig.cal.aborts
                                                       if t > t0]
    t1 = min(ends) if ends else float('inf')
    return [w for w in rig.probe.pubs if t0 < w['t'] <= t1 and w['screen'] == 3], t0


def finite(bits):
    return (bits & 0x7F800000) != 0x7F800000


def usable(w):
    """cal.s cal_usable: not the no-reading / overload set (theta -400 or |Z| 1e10), both words finite."""
    return not (w['TH'] == F_M400 or w['Z'] == F_1E10 or not finite(w['Z']) or not finite(w['TH']))


def f_quantile(n, alpha=1e-3):
    """The 1 - alpha quantile x of F(2, m), m = 2n - 2: P(F(2, m) > x) = (1 + 2x / m)^(-m / 2) = alpha."""
    m = 2 * n - 2
    return (m / 2) * (alpha ** (-2 / m) - 1)


GATE_C = 50e-12                 # cal.s cal_cmax / (2 pi): the gate's 50 pF (revision 14)
GATE_EDGE = 1e-6                # a gate margin (relative) this close to 0 may go either way (float32)
FSRC = ((6, 9, 7, 8), (7, 10, 6, 8), (8, 11, 6, 7))     # cal.s cal_fsrc: the fill's sources by level index


def short_zs(t0, th0):
    """Zs of a short entry as meas_comp / cal.s cal_zs form it: |t0| e^(j theta0), or |t0| when theta0 is not a
    finite angle within +-180 (meas_angok)."""
    a0 = abs(t0)
    return a0 * cmath.exp(1j * math.radians(th0)) if math.isfinite(th0) and abs(th0) <= 180 else complex(a0, 0)


def open_rule(zth, t0, th0, f):
    """cal.s cal_ores (revisions 11 and 14) in float64 for windows zth = [(|Z|, theta)] (floats of the published
    words), the short entry t0 / th0 and the point's frequency f: ('nr', None, q) not resolved by the F test
    (or n < 2, or a window at Zs), ('gate', None, q) resolved by the F test with |Zo| >= 1e5 but no lead stray
    (B < |G| or B above 2 pi f 50 pF: "not resolved" too), or (kind, (|Zo| - |t0|, arg Zo in degrees), q)
    with kind 'res' or 'edge' (q = n (n - 1) |Ybar|^2 / (x S) within 1e-3 of 1, |Zo| within 1e-6 of 1e5, or a
    gate margin within GATE_EDGE: the value or "not resolved"). A mean with |Zo| below 1e5 is returned as it
    is (cal_accept then fails the sweep, reason 3)."""
    n = len(zth)
    if n < 2:
        return 'nr', None, None
    a0 = abs(t0)
    zs = short_zs(t0, th0)
    ys = []
    for z, th in zth:
        d = (z + a0) * cmath.exp(1j * math.radians(th)) - zs
        if d == 0:
            return 'nr', None, None
        ys.append(1 / d)
    yb = sum(ys) / n
    s = sum(abs(y - yb) ** 2 for y in ys)
    lim = f_quantile(n) / (n * (n - 1)) * s
    q = abs(yb) ** 2 / lim if lim > 0 else (math.inf if yb != 0 else 0.0)
    if q < 1 - 1e-3:
        return 'nr', None, q
    zo = 1 / yb + zs
    edge = q <= 1 + 1e-3
    if abs(zo) >= 1e5 * (1 + GATE_EDGE):
        bmax = 2 * math.pi * f * GATE_C
        m = min((yb.imag - abs(yb.real)) / abs(yb), (bmax - yb.imag) / bmax)   # B >= |G|, B <= 2 pi f 50 pF
        if m < -GATE_EDGE:
            return 'gate', None, q
        edge = edge or m <= GATE_EDGE
    elif abs(zo) > 1e5 * (1 - GATE_EDGE):
        edge = True                                   # at 1e5: the gate may or may not apply
    return ('edge' if edge else 'res'), (abs(zo) - a0, math.degrees(cmath.phase(zo))), q


def open_fill(src_words, src_short, low_short, f_src, f_low):
    """cal.s cal_ofill for one target in float64: the source's stored words (|Z| bits, theta bits) and short
    entries (t0, theta0) of source and target: ('res', (|Zo_low| - |t0_low|, arg Zo_low), inf), or ('nr', None,
    None) when B_low is not above 0."""
    zs = short_zs(*src_short)
    zo = (u32f(src_words[0]) + abs(src_short[0])) * cmath.exp(1j * math.radians(u32f(src_words[1])))
    d = zo - zs
    b_low = -d.imag / abs(d) ** 2 * f_low / f_src
    if not b_low > 0:
        return 'nr', None, None
    zl = short_zs(*low_short) - 1j / b_low
    return 'res', (abs(zl) - abs(low_short[0]), math.degrees(cmath.phase(zl))), math.inf


def fill_expect(words, shorts, p):
    """The fill of target p (0..5) from the stored words {point: (|Z| bits, theta bits)} and shorts {point: (t0,
    theta0)}: (rule, the source point or None)."""
    for s in FSRC[p % 3]:
        if words[s][1] != F_P400:
            return open_fill(words[s], shorts[s], shorts[p], FREQS[s // 3], FREQS[p // 3]), s
    return ('nr', None, None), None


def open_match(got_z, got_t, rule, t0, what):
    """The stored words got_z / got_t against open_rule's or open_fill's result (module docstring bounds)."""
    kind, val, q = rule
    nr = got_z == F_1E10 and got_t == F_P400
    if kind in ('nr', 'gate'):
        check(nr, '%s: stored %08X / %08X, the rule gives "not resolved" (q %r)' % (what, got_z, got_t, q))
        return
    if kind == 'edge' and nr:
        return
    zo, gz = val[0] + abs(t0), u32f(got_z) + abs(t0)
    dt = (u32f(got_t) - val[1] + 180.0) % 360.0 - 180.0
    check(abs(gz - zo) <= 1e-5 * abs(zo) and abs(dt) <= 0.01, '%s: stored %.7g / %.5f, the rule gives %.7g / %.5f '
          '(%s, q %.4g)' % (what, u32f(got_z), u32f(got_t), val[0], val[1], kind, q))


def expect_point(wins, typ, short=None, f=None):
    """(|Z| bits, theta bits, the windows used) the specification of cal.s gives for the windows of one point,
    or None when they give no result. An open point (type 11) always gives one: (open_rule's result, None,
    the windows used), short = (t0, theta0) of the point's short entry (revision 11), f its frequency (the
    gate of revision 14). The fill of revision 14 is not part of it (check_sweep_result applies it)."""
    if typ == 11:
        used = [w for w in wins if usable(w)][:CA_NO_OPEN]
        t0, th0 = short if short is not None else (0.0, 0.0)
        check(f is not None, 'expect_point: an open point needs its frequency (revision 14 gate)')
        return open_rule([(u32f(w['Z']), u32f(w['TH'])) for w in used], t0, th0, f), None, used
    held, nt = [], 0
    for w in wins:
        z, th = w['Z'], w['TH']
        if th == F_M400 or z == F_1E10 or not finite(z) or not finite(th):
            held = []
            continue
        held = (held + [w])[-3:]
        nt += 1
        if len(held) < 3:
            continue
        zs = [u32f(h['Z']) for h in held]
        z0, z1, z2 = zs
        if z0 <= z1:
            m = 1 if z1 <= z2 else 2 if z0 <= z2 else 0
        else:
            m = 0 if z0 <= z2 else 2 if z1 <= z2 else 1
        a = abs(zs[m])
        if all(abs(z) <= 2 * a and 2 * abs(z) >= a for z in zs):
            return held[m]['Z'], held[m]['TH'], held
    return None


def check_sweep_result(rig, typ, before, what, since=0.0):
    """Every point's stored |Z| and theta entry equal expect_point of its windows, each window used only of
    acquisitions after the point's fn_08009f10 (cal_point), the other types' entries unchanged; no store before
    the commit (fn_0800bb64's writes all after the last point's last window). An open sweep (type 11): points
    6..14 and every point the rule resolves by open_match of its own rule; a 100 / 120 Hz point (0..5) whose
    rule is 'nr' / 'gate' by the fill from the stored words (fill_expect); one whose rule is 'edge' by either
    its own value or the fill (revision 14). Returns the table after the sweep."""
    after = table(rig)
    last_win = 0.0
    rules, shorts, words = {}, {}, {}
    for p in range(15):
        wins, t0 = windows_of(rig, p, since)
        s0 = struct.unpack_from('<f', before, entry(p, 0) - USR_LO)[0]      # the short entry (not stored by an
        s0t = struct.unpack_from('<f', before, entry(p, 0) - USR_LO + 0x2D0)[0]  # open sweep: as before it)
        exp = expect_point(wins, typ, (s0, s0t), FREQS[p // 3])
        check(exp is not None, '%s: point %d: the windows give no result (%d windows)' % (what, p, len(wins)))
        zb, tb, used = exp
        got_z = struct.unpack_from('<I', after, entry(p, typ) - USR_LO)[0]
        got_t = struct.unpack_from('<I', after, entry(p, typ) - USR_LO + 0x2D0)[0]
        if typ == 11:
            rules[p], shorts[p], words[p] = zb, (s0, s0t), (got_z, got_t)
        else:
            check(got_z == zb and got_t == tb, '%s: point %d stored %08X / %08X, expected %08X / %08X (%r)' % (
                what, p, got_z, got_t, zb, tb, [(hex(w['Z']), hex(w['TH'])) for w in wins[-4:]]))
        for w in used:
            check(all(a['t'] > t0 for a in w['adds']), '%s: point %d: a window holds an acquisition from before '
                  'its fn_08009f10' % (what, p))
        if used:                                     # an open "not resolved" uses no window
            last_win = max(last_win, used[-1]['t'])
    if typ == 11:
        for p in range(15):
            rule, gz, gt = rules[p], words[p][0], words[p][1]
            label = '%s: point %d' % (what, p)
            if p >= 6 or rule[0] == 'res':
                open_match(gz, gt, rule, shorts[p][0], label)
                continue
            fill, src = fill_expect(words, shorts, p)
            if rule[0] in ('nr', 'gate'):
                open_match(gz, gt, fill, shorts[p][0], '%s (filled from %r)' % (label, src))
                continue
            try:                                     # 'edge': its own value, else the fill
                open_match(gz, gt, ('res',) + rule[1:], shorts[p][0], label)
            except AssertionError:
                open_match(gz, gt, fill, shorts[p][0], '%s (edge; filled from %r)' % (label, src))
    for p in range(15):
        for t in range(12):
            if t == typ:
                continue
            for off in (0, 0x2D0):
                a = entry(p, t) - USR_LO + off
                check(after[a:a + 4] == before[a:a + 4], '%s: type %d of point %d changed' % (what, t, p))
    bb = [t for t, pc, lr, a, n in rig.watch.usr if rig.watch.kind(pc, lr) == 'bb64']
    check(bb and min(bb) > last_win, '%s: a store before the end of the windows (%r, last window %.3f)' % (
        what, bb[:3], last_win))
    return after


def check_restored(rig, what, typ=0):
    """Frequency, level, speed, bias, type and 0x200010C0.. as before the sweep."""
    check(rig.rd(V_FREQ) == 1000 and rig.rd(V_LEVEL) == 0x3E99999A and rig.rd(V_SPEED) == 1
          and rig.rd(V_BIAS) == 0x3F000000, '%s: settings %d / %08X / %d / %08X not restored' % (
              what, rig.rd(V_FREQ), rig.rd(V_LEVEL), rig.rd(V_SPEED), rig.rd(V_BIAS)))
    check(rig.rd(V_CAL_TYPE) == typ, '%s: type %d, wanted %d' % (what, rig.rd(V_CAL_TYPE), typ))
    check(rig.rd(V_CAL_WORK, 0x78) == REL_PATTERN, '%s: 0x200010C0.. not restored' % what)


def check_nothing_stored(rig, before, saves0, what):
    check(table(rig) == before, '%s: the user table changed' % what)
    check(rig.rd(SAVE_COUNT) == saves0, '%s: a save ran (%d -> %d)' % (what, saves0, rig.rd(SAVE_COUNT)))


def ask_async(rig, name, payload):
    return rig.host.send(C[name], payload)


def wait_answer(rig, seq, name, seconds):
    t_end = rig.m.now() + seconds
    while rig.m.now() < t_end:
        for f in rig.host.recv(timeout=0.05):
            if f['type'] == FR_ANSWER and f['seq'] == seq and f['cmd'] == C[name]:
                p = f['payload']
                return p[0], p[1:]
            rig.host.frames.append(f)
    raise AssertionError('%s: no answer within %.0f s' % (name, seconds))


# ---------------------------------------------------------------- c1 / c4 / c6 / c12 / c15

@case
def c01_short_sweep_host():
    """c1 / c4 (with the false-window unit, c12): a short sweep started
    by CALIBRATE from 1 kHz / 0.3 V / speed 1 / bias 0.5 V. Every stored entry is the median window of its point
    (theta of that window) and no window holds an acquisition from before the point's restart; no store before
    the end; the answer status 0 with calibration status 2, 8 bytes, no failed point; the step word rises
    through 3 (p + 1) to 45 and the CALIBRATION events follow it; one SAVE_RESULT; the progress text "n/15" with
    the frequency and level, the finish text the vendor's status-2 text; D10: the settings restored before the
    save (copy A holds the RAM block); the factory table and the m15 watch."""
    rig = cal_rig(short_src(), block=pre_block(), usb=True)
    rig.run(1.0)
    before, saves0 = table(rig), rig.rd(SAVE_COUNT)
    seen = {}

    def on_point(r, p):
        seen[p] = None
    rig.cal.on_point = on_point
    check(rig.rd(V_SCREEN) == 1, 'c1: the rig does not start on screen 1 (%d)' % rig.rd(V_SCREEN))
    seq = ask_async(rig, 'CALIBRATE', b'\x00' + OK2)
    wait_point(rig, 7, 120.0)
    rig.run(0.2)
    txt = obj_text(rig, V_STAT_TXT)
    check(txt == b'8/15\n' + NAMES[7].encode(), 'c1: progress text %r' % txt)
    # the finish text while the dialog is still open: cal_finish sets status 2 and the text in one call,
    # the job's long key 8 (1100 ms) that closes the dialog starts in a later pass (revision 10 item 4)
    wait_until(rig, lambda: rig.cal.finished, 360.0, 'c1: the end of cal_finish')
    check(rig.rd(V_CAL_STATUS) == 2, 'c1: status %d at the end of cal_finish' % rig.rd(V_CAL_STATUS))
    rig.run(0.05)
    check(rig.rd(V_DIALOG) != 0, 'c1: the dialog closed within 0.05 s of the end of cal_finish')
    lang = rig.rd(V_LANGUAGE)
    fin = cstr(rig, rig.rd(V_STAT_NAMES + 4 * (4 * lang + 2)))
    check(obj_text(rig, V_STAT_TXT) == fin, 'c1: finish text %r, vendor %r' % (obj_text(rig, V_STAT_TXT), fin))
    st, d = wait_answer(rig, seq, 'CALIBRATE', host_timeout(C['CALIBRATE']))
    check(st == S_OK and len(d) == 8, 'c1: answer status %d, %d bytes %s' % (st, len(d), d.hex()))
    check(d[0] == 2 and d[1] == 0 and d[6] == 0xFF and d[7] == R_NONE, 'c1: answer %s' % d.hex())
    check(rig.rd(V_CAL_STATUS) == 2, 'c1: status %d' % rig.rd(V_CAL_STATUS))
    check_sweep_result(rig, 0, before, 'c1')
    steps = [v for _, v in rig.cal.steps]
    check(all(b >= a for a, b in zip(steps, steps[1:])), 'c1: step word not rising %r' % steps[:60])
    check(all(3 * (p + 1) in steps for p in range(15)) and steps[-1] == 45, 'c1: steps %r' % sorted(set(steps)))
    evs = [f['payload'] for f in rig.host.frames if f['type'] == FR_EVENT and f['cmd'] == E_CAL]
    ev_steps = [e[1] for e in evs]
    check(ev_steps and all(b >= a for a, b in zip(ev_steps, ev_steps[1:])) and evs[-1][0] == 2,
          'c1: CALIBRATION events %r' % [e.hex() for e in evs][-6:])
    saves = [f for f in rig.host.frames if f['type'] == FR_EVENT and f['cmd'] == E_SAVE]
    check(len(saves) == 1 and rig.rd(SAVE_COUNT) == saves0 + 1, 'c1: %d SAVE_RESULT events, count %d -> %d' % (
        len(saves), saves0, rig.rd(SAVE_COUNT)))
    check(rig.rd(V_DIALOG) == 0 and rig.rd(V_SCREEN) == 1, 'c1: after the answer dialog %d screen %d, expected '
          'the dialog closed and screen 1 (the screen found)' % (rig.rd(V_DIALOG), rig.rd(V_SCREEN)))
    check_restored(rig, 'c1')
    # copy A holds the block as cal_finish saved it (the restored settings); revision 10 item 4 closes the
    # dialog and returns to the screen found after that save, which changes the screen word 0x20001168
    # (inside the block) in RAM only: the words that differ afterwards are listed, not compared
    blk = rig.cal.fin_block
    check(rig.m.get(SET_A, BLK) == blk, 'c1: copy A does not hold the block of the end of cal_finish')
    now = rig.rd(V_BLOCK, BLK)
    NOTES.append('c1: block words changed after the save: %s' % ', '.join(
        '0x%08X %08X->%08X' % (V_BLOCK + i, struct.unpack_from('<I', blk, i)[0], struct.unpack_from('<I', now, i)[0])
        for i in range(0, BLK, 4) if blk[i:i + 4] != now[i:i + 4]))
    rig.watch.check(what='c1')
    NOTES.append('c1: sweep %.1f s emulated (CALIBRATE to the finish), %d windows' % (
        rig.cal.commits[0] - rig.cal.points[0][0], len([w for w in rig.probe.pubs if w['screen'] == 3])))
    return True


# ---------------------------------------------------------------- c2 part jump inside a point

@case
def c02_jump_inside_a_point():
    """c2: the short reads 3x for 0.3 s inside point 4. The stored entry of point 4
    is the median of 3 agreeing windows (expect_point) and within 1e-3 of the windows of the true part: the
    jump's windows are not used."""
    base = short_src()
    jump = {'t': None}

    def zt(f, t):
        z = base.z(f)
        a = jump['t']
        return 3 * z if a is not None and a <= t < a + 0.3 else z
    src = TDut(zt, counts_per_volt=0.94)
    rig = cal_rig(src, block=pre_block())
    rig.run(1.0)
    before = table(rig)

    def on_point(r, p):
        if p == 4:
            jump['t'] = r.m.now() + 1.5
    rig.cal.on_point = on_point
    start(rig)
    wait_end(rig)
    check(rig.rd(V_CAL_STATUS) == 2, 'c2: status %d (reason %d at point %d)' % (
        rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY), rig.rd(OWN_CAL + CAO_FAILP)))
    check_sweep_result(rig, 0, before, 'c2')
    wins, _ = windows_of(rig, 4)
    a = jump['t']
    clean = [u32f(w['Z']) for w in wins if not is_set(w) and all(not (a <= x['t'] < a + 0.3) for x in w['adds'])]
    stored = u32f(rig.rd(entry(4)))
    check(clean and abs(stored - sorted(clean)[len(clean) // 2]) <= 1e-3 * stored,
          'c2: stored %.6g against clean windows %r' % (stored, clean))
    rig.watch.check(what='c2')
    return True


# ---------------------------------------------------------------- c3 stall, time limit, spread

@case
def c03_stall_and_limits():
    """c3: (a) TIM1 stopped in point 7 (no conversion, no re-arm
    of DMA1 channel 1): status 3 within 1.5 s plus a pass, reason stall at point 7, nothing stored or saved, the
    settings restored. (b) / (c) the point limit: CAO_TPT moved 21 s back with fewer than 3 windows held gives
    the reason "time", with 3 held "spread"."""
    rig = cal_rig(short_src(), block=pre_block())
    rig.run(1.0)
    before, saves0 = table(rig), rig.rd(SAVE_COUNT)
    start(rig)
    wait_point(rig, 7)
    rig.run(0.5)
    t_stop = rig.m.now()
    rig.meas.write(rig.m, TIM1_CTRL1, 4, 0)          # CEN = 0: the CC3 trigger of the three ADCs stops
    wait_until(rig, lambda: rig.rd(V_CAL_RUN) == 0, 4.0, 'c3 (a): the stall fail')
    t_fail = rig.cal.fails[-1]
    check(rig.rd(V_CAL_STATUS) == 3 and rig.rd(OWN_CAL + CAO_WHY) == R_STALL and rig.rd(OWN_CAL + CAO_FAILP) == 7,
          'c3 (a): status %d reason %d point %d' % (rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY),
                                                   rig.rd(OWN_CAL + CAO_FAILP)))
    check(1.5 <= t_fail - t_stop <= 2.0, 'c3 (a): the fail %.3f s after the stop' % (t_fail - t_stop))
    rig.run(0.5)
    check_nothing_stored(rig, before, saves0, 'c3 (a)')
    check_restored(rig, 'c3 (a)')
    check(obj_text(rig, V_STAT_TXT) == b'Fail 8/15\nno signal', 'c3 (a): text %r' % obj_text(rig, V_STAT_TXT))
    rig.watch.check(what='c3 (a)')
    for what, nw, why in (('c3 (b)', 1, R_TIME), ('c3 (c)', 3, R_SPREAD)):
        rig = cal_rig(short_src(), block=pre_block())
        rig.run(1.0)
        before, saves0 = table(rig), rig.rd(SAVE_COUNT)
        start(rig)
        wait_point(rig, 3)
        rig.run(0.3)
        rig.wr(OWN_CAL + CAO_NW, nw)
        # the step word with it: cal_same compares 0x200050E8 with cal_expect = 3 CAO_PT + min(CAO_NW,
        # 2) (cal.s), and a mismatch is the vendor start run again (from point 0, item 2), so NW
        # alone restarted the sweep (2026-11-22: no fail within 1 s)
        rig.wr(V_CAL_STEP, 3 * rig.rd(OWN_CAL + CAO_PT) + min(nw, 2))
        rig.wr(OWN_CAL + CAO_TPT, (rig.rd(M.V_TICK) - 21000) & 0xFFFFFFFF)
        wait_until(rig, lambda: rig.rd(V_CAL_RUN) == 0, 1.0, what)
        check(rig.rd(V_CAL_STATUS) == 3 and rig.rd(OWN_CAL + CAO_WHY) == why and rig.rd(OWN_CAL + CAO_FAILP) == 3,
              '%s: status %d reason %d point %d' % (what, rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY),
                                                   rig.rd(OWN_CAL + CAO_FAILP)))
        rig.run(0.3)
        check_nothing_stored(rig, before, saves0, what)
        check_restored(rig, what)
        rig.watch.check(what=what)
    return True


# ---------------------------------------------------------------- c5 abort by a type key

@case
def c05_type_key_abort():
    """c5: CALIBRATE, then a physical key 4 during point 4 (the vendor clears
    0x200050E4 / E8 / EC and changes the type): the type restored to 0 and its dialog text set again, status 0,
    nothing stored or saved, the settings restored, OP_WAITCAL answers status 3 after 1 s."""
    rig = cal_rig(short_src(), block=pre_block(), usb=True)
    rig.run(1.0)
    before, saves0 = table(rig), rig.rd(SAVE_COUNT)
    seq = ask_async(rig, 'CALIBRATE', b'\x00' + OK2)
    wait_point(rig, 4, 60.0)
    rig.run(0.5)
    tap(rig, KEY_4)
    wait_until(rig, lambda: rig.rd(OWN_CAL + CAO_ON) == 0, 1.0, 'c5: the abort')
    rig.run(0.1)
    # the type text while the dialog is open (OP_WAITCAL waits 1000 ms after the running word went to 0
    # before the job closes the dialog, revision 10 item 4)
    check(rig.rd(V_DIALOG) != 0, 'c5: the dialog closed within 0.1 s of the abort')
    lang = rig.rd(V_LANGUAGE)
    name0 = cstr(rig, rig.rd(V_TYPE_NAMES + 4 * (12 * lang + 0)))
    check(obj_text(rig, V_TYPE_TXT) == name0, 'c5: type text %r, type 0 is %r' % (obj_text(rig, V_TYPE_TXT), name0))
    st, d = wait_answer(rig, seq, 'CALIBRATE', 10.0)
    check(st == S_NOT_NOW and d[0] == 0, 'c5: answer status %d, data %s' % (st, d.hex()))
    check(rig.rd(V_CAL_RUN) == 0 and rig.rd(V_CAL_STEP) == 0 and rig.rd(V_CAL_STATUS) == 0, 'c5: E4 / E8 / EC')
    check(rig.rd(OWN_CAL + CAO_WHY) == R_ABORT and rig.rd(OWN_CAL + CAO_FAILP) == 4, 'c5: reason / point')
    check(rig.rd(V_DIALOG) == 0 and rig.rd(V_SCREEN) == 1, 'c5: after the answer dialog %d screen %d' % (
        rig.rd(V_DIALOG), rig.rd(V_SCREEN)))
    check_nothing_stored(rig, before, saves0, 'c5')
    check_restored(rig, 'c5')
    rig.watch.check(what='c5')
    return True


# ---------------------------------------------------------------- c7 the vendor's store check

@case
def c07_store_check_fails():
    """c7: the vendor check of fn_0800bb64 fails at the store of point 5: a 2 ohm "short" (types 0..2
    at 0.9 ohm or above go to its 50 % test) against old short entries of 2 ohm at points
    0..4 (they pass) and 0 at 5..14 (fails). Status 3, reason "check" at point 5, the entries points 0..4
    were stored with written back (cal_snap): the user table as before, no save, the settings restored, the
    fail text; m15: the user table's writers are fn_0800bb64 and cal_snap."""
    b = bytearray(pre_block())
    for p in range(5):
        struct.pack_into('<f', b, entry(p) - V_BLOCK, 2.0)
    rig = cal_rig(DutSource('R', 2.0, counts_per_volt=20.0), block=bytes(b))
    rig.run(1.0)
    before, saves0 = table(rig), rig.rd(SAVE_COUNT)
    start(rig)
    wait_end(rig)
    check(rig.rd(V_CAL_STATUS) == 3 and rig.rd(OWN_CAL + CAO_WHY) == R_CHECK and rig.rd(OWN_CAL + CAO_FAILP) == 5,
          'c7: status %d reason %d point %d' % (rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY),
                                               rig.rd(OWN_CAL + CAO_FAILP)))
    kinds = [rig.watch.kind(pc, lr) for _, pc, lr, _, _ in rig.watch.usr]
    check(kinds.count('bb64') >= 10 and 'cal-restore' in kinds, 'c7: writers %r' % sorted(set(kinds)))
    check_nothing_stored(rig, before, saves0, 'c7')
    check_restored(rig, 'c7')
    check(obj_text(rig, V_STAT_TXT) == b'Fail 6/15\ncheck', 'c7: text %r' % obj_text(rig, V_STAT_TXT))
    rig.watch.check(what='c7')
    return True


# ---------------------------------------------------------------- c8 the no-reading path

@case
def c08_no_reading_windows():
    """Critique items 1 / 11 (the 1208 path): no current on ADC2 (mid-scale codes) for 3 s inside point 2: the
    no-reading set is published at least once and never used; the point completes from the windows after it;
    no stored entry is 1e10 or -400."""
    base = short_src()
    gap = {'t': None}
    src = TDut(lambda f, t: base.z(f), counts_per_volt=0.94)
    plain = TDut.samples

    def samples(path, adc, channel, times):
        a = gap['t']
        if adc == 2 and a is not None and any(a <= t < a + 3.0 for t in times):
            return [2048] * len(times)
        return plain(src, path, adc, channel, times)
    src.samples = samples
    rig = cal_rig(src, block=pre_block())
    rig.run(1.0)
    before = table(rig)

    def on_point(r, p):
        if p == 2:
            gap['t'] = r.m.now() + 0.8
    rig.cal.on_point = on_point
    start(rig)
    wait_end(rig)
    check(rig.rd(V_CAL_STATUS) == 2, 'c8: status %d (reason %d)' % (rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY)))
    wins, _ = windows_of(rig, 2)
    check(any(is_set(w) for w in wins), 'c8: no no-reading publish inside point 2')
    after = check_sweep_result(rig, 0, before, 'c8')
    for p in range(15):
        z, th = struct.unpack_from('<II', after, entry(p) - USR_LO)[0], struct.unpack_from('<I', after, entry(p) - USR_LO + 0x2D0)[0]
        check(z != F_1E10 and th != F_M400, 'c8: point %d stored the no-reading set' % p)
    rig.watch.check(what='c8')
    return True


# ---------------------------------------------------------------- c9 key-8 restart

@case
def c09_key8_restart():
    """Critique item 2: a physical key 8 during point 5 runs the vendor start again (100 Hz / 0.1 V, step 0,
    fn_08009f10): the sweep begins again at point 0 without a new recording (the recorded settings stay those
    of before the first start), completes, stores the windows after the second start, restores the settings."""
    rig = cal_rig(short_src(), block=pre_block())
    rig.run(1.0)
    before = table(rig)
    start(rig)
    wait_point(rig, 5)
    rig.run(0.5)
    tap(rig, KEY_OK)
    t_restart = rig.m.now()
    check(rig.rd(OWN_CAL + CAO_SFREQ) == 1000 and rig.rd(OWN_CAL + CAO_SSPEED) == 1
          and rig.rd(OWN_CAL + CAO_SBIAS) == 0x3F000000, 'c9: the recording changed at the restart')
    wait_end(rig)
    zeros = [t for t, p in rig.cal.points if p == 0]
    check(len(zeros) == 2 and zeros[1] >= t_restart - 0.2, 'c9: point 0 set at %r' % zeros)
    check(rig.rd(V_CAL_STATUS) == 2, 'c9: status %d (reason %d at point %d)' % (
        rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY), rig.rd(OWN_CAL + CAO_FAILP)))
    check_sweep_result(rig, 0, before, 'c9', since=zeros[1])
    check_restored(rig, 'c9')
    rig.watch.check(what='c9')
    return True


# ---------------------------------------------------------------- c10 long key 8 closes the dialog

@case
def c10_dialog_closed():
    """Critique item 3: a long key 8 during point 3 closes the dialog without clearing 0x200050E4: the guard is
    lost, so 0x200050E4 / E8 / EC = 0, reason abort at point 3, nothing stored or saved, the settings restored."""
    rig = cal_rig(short_src(), block=pre_block())
    rig.run(1.0)
    before, saves0 = table(rig), rig.rd(SAVE_COUNT)
    start(rig)
    wait_point(rig, 3)
    rig.run(0.5)
    rig.press(KEY_OK, 1200)
    wait_until(rig, lambda: rig.rd(OWN_CAL + CAO_ON) == 0, 3.0, 'c10: the end')
    check(rig.rd(V_DIALOG) == 0 or rig.rd(V_SCREEN) != 3 or rig.rd(V_MENU) != 5, 'c10: the dialog is still open')
    check(rig.rd(V_CAL_RUN) == 0 and rig.rd(V_CAL_STEP) == 0 and rig.rd(V_CAL_STATUS) == 0, 'c10: E4 / E8 / EC')
    check(rig.rd(OWN_CAL + CAO_WHY) == R_ABORT and rig.rd(OWN_CAL + CAO_FAILP) == 3, 'c10: reason / point')
    check_nothing_stored(rig, before, saves0, 'c10')
    check_restored(rig, 'c10')
    rig.watch.check(what='c10')
    return True


# ---------------------------------------------------------------- c11 power key mid-sweep

@case
def c11_power_key_mid_sweep():
    """Critique item 4: the power key during point 6 saves and powers off: both copies hold the old calibration
    table and the settings of before the sweep (save.s stage_cal_fix), not the sweep's 100 Hz / 0.1 V / speed 0
    / bias 0 / zeroed 0x200010C0."""
    blk = pre_block()
    rig = cal_rig(short_src(), block=blk)
    rig.run(1.0)
    start(rig)
    wait_point(rig, 6)
    rig.run(0.5)
    rig.press(KEY_POWER, 1300)
    t_end = rig.m.now() + 2.0
    while rig.m.st['pa8'] != 0 and rig.m.now() < t_end:
        rig.run(0.01)
    check(rig.m.st['pa8'] == 0, 'c11: no power-off')
    for base, name in ((SET_A, 'A'), (SET_B, 'B')):
        got = rig.m.get(base, BLK)
        check(got[0x04:0xB44] == blk[0x04:0xB44], 'c11: copy %s: calibration tables changed' % name)
        for addr in (V_FREQ, V_LEVEL, V_SPEED, V_BIAS):
            o = addr - V_BLOCK
            check(got[o:o + 4] == blk[o:o + 4], 'c11: copy %s: word 0x%08X %s, before %s' % (
                name, addr, got[o:o + 4].hex(), blk[o:o + 4].hex()))
        o = V_CAL_WORK - V_BLOCK
        check(got[o:o + 0x78] == REL_PATTERN, 'c11: copy %s: 0x200010C0.. not the recorded bytes' % name)
    rig.watch.check(what='c11')
    return True


# ---------------------------------------------------------------- c13 noise-limited open

@case
def c13_noise_limited_open():
    """Critique item 11: an open (type 11) of 5e7 ohm with noise +-400 counts on both channels, so that the
    current channel is noise-limited at every point: the sweep completes, every point stored by the open rule
    of revision 11 (open_rule over its first 7 usable windows or those its 20 s gave: the resolved mean, else
    "not resolved" 1e10 / +400), every |Zo| >= 1e5."""
    rig = cal_rig(DutSource('R', 5e7, noise_lsb=400.0), block=pre_block())
    rig.run(1.0)
    before = table(rig)
    start(rig, typ=11)
    wait_end(rig)
    check(rig.rd(V_CAL_STATUS) == 2, 'c13: status %d (reason %d at %d)' % (
        rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY), rig.rd(OWN_CAL + CAO_FAILP)))
    after = check_sweep_result(rig, 11, before, 'c13')
    unres = 0
    for p in range(15):
        z = struct.unpack_from('<f', after, entry(p, 11) - USR_LO)[0]
        t0 = struct.unpack_from('<f', after, entry(p, 0) - USR_LO)[0]
        unres += struct.unpack_from('<I', after, entry(p, 11) - USR_LO + 0x2D0)[0] == F_P400
        check(z + t0 >= 1e5, 'c13: point %d |Zo| %.4g' % (p, z + t0))
    NOTES.append('c13: %d of 15 open points stored "not resolved"' % unres)
    check_restored(rig, 'c13', typ=11)
    rig.watch.check(what='c13')
    return True


# ---------------------------------------------------------------- c14 open below 100 kohm

@case
def c14_open_below_100k():
    """Stage 3 "open validity": an open of 1 Mohm that reads 50 kohm at 10 kHz fails the sweep at point
    9 (10 kHz / 0.1 V) with the reason "open low": nothing stored or saved, the settings restored, the text."""
    src = DutSource(z=lambda f: complex(5e4 if f == 10000 else 1e6, 0.0))
    rig = cal_rig(src, block=pre_block())
    rig.run(1.0)
    before, saves0 = table(rig), rig.rd(SAVE_COUNT)
    start(rig, typ=11)
    wait_end(rig)
    check(rig.rd(V_CAL_STATUS) == 3 and rig.rd(OWN_CAL + CAO_WHY) == R_OPEN and rig.rd(OWN_CAL + CAO_FAILP) == 9,
          'c14: status %d reason %d point %d' % (rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY),
                                                rig.rd(OWN_CAL + CAO_FAILP)))
    check_nothing_stored(rig, before, saves0, 'c14')
    check_restored(rig, 'c14', typ=11)
    check(obj_text(rig, V_STAT_TXT) == b'Fail 10/15\nopen low', 'c14: text %r' % obj_text(rig, V_STAT_TXT))
    rig.watch.check(what='c14')
    return True


# ---------------------------------------------------------------- c15 factory mode

@case
def c15_factory_mode_finish():
    """Stage 3 / S1.9: in factory mode (PC11 at the start, the gate of fn_0800bd5c sets 2 on screen 3) a
    complete short sweep stores into the user table only: the factory table stays the loaded one (m15)."""
    rig = cal_rig(DutSource('R', 0.5, counts_per_volt=M.K_SHORT), block=M.factory_block(), keys_at_start=M.KEY_PC11)
    start(rig)
    wait_end(rig)
    check(rig.rd(M.V_FACTORY) == 2, 'c15: factory word %d' % rig.rd(M.V_FACTORY))
    check(rig.rd(V_CAL_STATUS) == 2, 'c15: status %d (reason %d)' % (rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY)))
    rig.watch.check(what='c15')
    return True


# ---------------------------------------------------------------- u1 cal_judge

@case
def u01_judge_unit():
    """cal_judge (median of 3 by a signed compare, agreement |Zi| <= 2 |Zm| and 2 |Zi| >= |Zm|) on chosen
    triples, called directly on a rig at the main loop (the rig is not run afterwards)."""
    rig = own_rig(DutSource())
    win = OWN_CAL + CAO_WIN
    cases = [((1.0, 2.0, 3.0), 1, 1), ((3.0, 1.0, 2.0), 2, 1), ((2.0, 3.0, 1.0), 0, 1), ((3.0, 2.0, 1.0), 1, 1),
             ((1.0, 1.0, 1.0), 1, 1), ((1.0, 2.0, 4.0), 1, 1), ((1.0, 2.0, 4.0001), 1, 0), ((0.9999, 2.0, 4.0), 1, 0),
             ((5.0, 0.01, 0.012), 2, 0), ((-1.0, -2.0, -1.5), 2, 1), ((0.0, 0.0, 0.0), 1, 1), ((0.0, 0.0, 1e-9), 1, 0)]
    for zs, m_exp, a_exp in cases:
        for i, z in enumerate(zs):
            rig.wr(win + 8 * i, f2u(z))
            rig.wr(win + 8 * i + 4, f2u(10.0 * i))
        r0 = rig.m.call(rig.s['cal_judge'])
        r1 = rig.m.uc.reg_read(UC_ARM_REG_R1)
        check(r0 == m_exp and r1 == a_exp, 'u1: %r -> median %r agree %r, expected %d / %d' % (zs, r0, r1, m_exp, a_exp))
    return True

# ---------------------------------------------------------------- revision 10 (2026-11-23)

def gap_source(z, gaps):
    """TDut of the impedance z(f) whose current channel (ADC2) reads mid-scale (2048, no current) at the times
    t with gaps(t) true (c08's method)."""
    src = TDut(lambda f, t: z(f))
    plain = TDut.samples

    def samples(path, adc, channel, times):
        if adc == 2 and any(gaps(t) for t in times):
            return [2048] * len(times)
        return plain(src, path, adc, channel, times)
    src.samples = samples
    return src


def point_span(rig, p):
    """(t0, t1) of the last cal_point(p) and of the next cal_point / commit / fail / abort after it."""
    starts = [t for t, q in rig.cal.points if q == p]
    check(starts, 'point %d never set' % p)
    t0 = starts[-1]
    ends = [t for t, _ in rig.cal.points if t > t0] + [t for t in rig.cal.commits + rig.cal.fails + rig.cal.aborts
                                                       if t > t0]
    check(ends, 'point %d never ended' % p)
    return t0, min(ends)


@case
def c16_open_point_keeps_its_windows():
    """Revision 10 item 1 (the meter, 2026-11-23: the open failed at point 13, 100 kHz / 0.3 V, reason 2, while
    the measure screen there gave 34 results in 30 s, 2 of them the no-reading set): an open of 1 Mohm whose
    current channel reads mid-scale for 3 s twice inside point 13 (1.5 .. 4.5 s and 6.5 .. 9.5 s after its
    cal_point). Input checks: point 13 has at least 2 no-reading publishes and a usable window before the
    first of them. Expected: the sweep finishes; point 13 ends within its 20 s (plus 0.5 s for the pass); its
    result is expect_point's (open_rule over the first 7 usable windows) and uses the window from before the
    first gap (no restart); every point stored by expect_point."""
    t13 = {'t': None}

    def gaps(t):
        a = t13['t']
        return a is not None and (a + 1.5 <= t < a + 4.5 or a + 6.5 <= t < a + 9.5)
    rig = cal_rig(gap_source(lambda f: complex(1e6, 0.0), gaps), block=pre_block())
    rig.run(1.0)
    before = table(rig)

    def on_point(r, p):
        if p == 13:
            t13['t'] = r.m.now()
    rig.cal.on_point = on_point
    start(rig, typ=11)
    wait_end(rig)
    check(rig.rd(V_CAL_STATUS) == 2, 'c16: status %d (reason %d at point %d)' % (
        rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY), rig.rd(OWN_CAL + CAO_FAILP)))
    wins, t0 = windows_of(rig, 13)
    sets = [w for w in wins if is_set(w)]
    check(len(sets) >= 2, 'c16: %d no-reading publishes inside point 13 (input)' % len(sets))
    first_set = min(w['t'] for w in sets)
    early = [w for w in wins if usable(w) and w['t'] < first_set]
    check(early, 'c16: no usable window before the first no-reading publish (input)')
    t0, t1 = point_span(rig, 13)
    check(t1 - t0 <= CA_POINT_S + 0.5, 'c16: point 13 took %.2f s' % (t1 - t0))
    exp = expect_point(wins, 11, None, FREQS[13 // 3])     # the windows used (exp[2]) need no short entry
    check(early[0] in exp[2], 'c16: the window before the gap was not used (a restart)')
    check_sweep_result(rig, 11, before, 'c16')
    NOTES.append('c16: point 13 %.2f s, %d publishes, %d no-reading, %d used' % (
        t1 - t0, len(wins), len(sets), len(exp[2])))
    rig.watch.check(what='c16')
    return True


@case
def c17_open_point_without_a_window():
    """Revision 10 item 1: an open of 1 Mohm whose current channel reads mid-scale through all of point 4
    (120 Hz / 0.3 V). Input check: every publish inside point 4 is the no-reading set, at least one. Expected:
    point 4 ends at its 20-s limit (20.0 .. 20.5 s after its cal_point) with "not resolved", |Z| 1e10 and
    theta +400, stored; the sweep goes on and finishes (status 2), every other point by expect_point."""
    on = {'v': False}
    rig = cal_rig(gap_source(lambda f: complex(1e6, 0.0), lambda t: on['v']), block=pre_block())
    rig.run(1.0)
    before = table(rig)

    def on_point(r, p):
        on['v'] = p == 4
    rig.cal.on_point = on_point
    start(rig, typ=11)
    wait_end(rig)
    check(rig.rd(V_CAL_STATUS) == 2, 'c17: status %d (reason %d at point %d)' % (
        rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY), rig.rd(OWN_CAL + CAO_FAILP)))
    wins, _ = windows_of(rig, 4)
    check(wins and all(is_set(w) for w in wins), 'c17: point 4 publishes %r (input: all the no-reading set)' % (
        [(hex(w['Z']), hex(w['TH'])) for w in wins[:6]]))
    t0, t1 = point_span(rig, 4)
    check(CA_POINT_S <= t1 - t0 <= CA_POINT_S + 0.5, 'c17: point 4 took %.2f s' % (t1 - t0))
    after = check_sweep_result(rig, 11, before, 'c17')
    z, th = struct.unpack_from('<I', after, entry(4, 11) - USR_LO)[0], struct.unpack_from(
        '<I', after, entry(4, 11) - USR_LO + 0x2D0)[0]
    check(z == F_1E10 and th == F_P400, 'c17: point 4 stored %08X / %08X' % (z, th))
    rig.watch.check(what='c17')
    return True


@case
def c18_open_time_limit_takes_its_windows():
    """Revisions 10 / 11, the limit path of an open point: in point 3 (120 Hz / 0.1 V) three windows are planted
    in CAO_OWIN (|Z| 6.6315e7 x 1.00 / 1.01 / 0.99 at theta -89.6, -89.8, -89.7; the step word with them) and
    CAO_TPT moved 21 s back. Revision 14: the open must be a lead stray to be kept (the gate), so the source and
    the planted windows are one: below 500 Hz the admittance 1e-10 S + j 2 pi f 20 pF (at 120 Hz 1.508e-8 S at
    +89.6 degrees, |Z| 6.63e7 ohm at -89.6: a window the DUT publishes between the planting and cal_oend agrees
    with the planted three), from 500 Hz 1 Mohm (points 6.. are not reached before the case ends). Input checks
    at the entry of cal_oend for point 3: CAO_NO below 7 (the limit, not the 7th window) with the planted three
    first, and open_rule gives "resolved" for what CAO_OWIN holds there (C about 20 pF, below the gate's 50 pF;
    arg Ybar about +89.7, inside +45 .. +135). Expected: the result of point 3 (CAO_RES) is open_rule's mean of
    those windows (open_match), the sweep goes on to point 4, no fail."""
    w = 2 * math.pi
    rig = cal_rig(DutSource(z=lambda f: 1 / complex(1e-10, w * f * 20e-12) if f < 500 else complex(1e6, 0.0)),
                  block=pre_block())
    rig.run(1.0)
    start(rig, typ=11)
    wait_point(rig, 3)
    rig.run(0.3)
    seen = []

    def at_oend(uc, a, size, u):
        n = rig.rd(OWN_CAL + CAO_NO)
        seen.append((rig.rd(OWN_CAL + CAO_PT), n, [(rig.rd(OWN_CAL + CAO_OWIN + 8 * i),
                                                    rig.rd(OWN_CAL + CAO_OWIN + 8 * i + 4)) for i in range(n)]))
    a = rig.s['cal_oend'] & ~1
    rig.m.uc.hook_add(UC_HOOK_CODE, at_oend, begin=a, end=a)
    planted = [(f2u(6.6315e7), f2u(-89.6)), (f2u(6.6315e7 * 1.01), f2u(-89.8)), (f2u(6.6315e7 * 0.99), f2u(-89.7))]
    for i, (z, th) in enumerate(planted):
        rig.wr(OWN_CAL + CAO_OWIN + 8 * i, z)
        rig.wr(OWN_CAL + CAO_OWIN + 8 * i + 4, th)
    rig.wr(OWN_CAL + CAO_NO, 3)
    rig.wr(V_CAL_STEP, 3 * 3 + 2)                    # cal_expect: 3 CAO_PT + min(CAO_NO, 2) (cal_same)
    rig.wr(OWN_CAL + CAO_TPT, (rig.rd(M.V_TICK) - 21000) & 0xFFFFFFFF)
    wait_until(rig, lambda: any(s[0] == 3 for s in seen), 1.0, 'c18: cal_oend of point 3')
    _, n, held = [s for s in seen if s[0] == 3][0]
    check(n < CA_NO_OPEN and held[:3] == planted, 'c18: at cal_oend %d windows %r (input)' % (n, held))
    t0, th0 = u32f(rig.rd(entry(3, 0))), u32f(rig.rd(entry(3, 0) + 0x2D0))
    rule = open_rule([(u32f(z), u32f(th)) for z, th in held], t0, th0, FREQS[1])
    check(rule[0] == 'res', 'c18: the rule gives %r for %r (input: resolved)' % (rule, held))
    rig.run(0.3)
    got = (rig.rd(OWN_CAL + CAO_RES + 8 * 3), rig.rd(OWN_CAL + CAO_RES + 8 * 3 + 4))
    open_match(got[0], got[1], rule, t0, 'c18: result')
    check(any(q == 4 for _, q in rig.cal.points) and not rig.cal.fails, 'c18: point 4 not reached or a fail')
    rig.watch.check(what='c18')
    return True


@case
def c19_menu_and_host_run_the_same_sweep():
    """Revision 10 item 2: the same short (short_src) from the same settings (pre_block), started once by the
    meter's keys (settings item 5, key 8, key 8) and once by CALIBRATE. Both finish (status 2), each stores
    expect_point of its own windows at every point (check_sweep_result) and restores the settings; the
    recordings of cal.s are the same; at every point both stored entries lie in the set of |Z| and theta the
    model gives for that point's frequency, level and the gain codes of the stored window, over every sampling
    phase, and they differ by no more than the two sets allow.
    Why a set and not a fixed bound: the sampling is coherent (meas.s S1.1: 128 samples = 1, 4 or 16 periods,
    M = 128, 32 or 8 samples per period), so in one run every acquisition after a restart sees the same
    sample phases p + 2 pi m / M and every window is the same; only the phase p, fixed at the restart, differs
    between runs. A window is the bin of one period: theta = arg(XV / XI), |Z| = R[c8] G[c6] / G[c5]
    |XV / XI| (measure_model.DutSource), XV = sum round(mid + Av cos(p + 2 pi m / M)) e^(-j 2 pi m / M),
    XI the same with Ai and p - arg z, Av = k G[c5] |c|, Ai = k G[c6] R[c8] |c| / |z|, |c| the generator's
    amplitude (measure_model._gen_epoch). The rounding makes theta and |Z| piecewise constant in p with a
    period of 2 pi / M; model_set enumerates every interval between two rounding steps exactly. Emulator
    diagnostic 2026-11-23 (short_src, 0.1 V, speed 0, restarts at varied moments): the windows 0.0700899 /
    43.9171, 0.0706564 / 43.9944, 0.070006 / 44.4643 (codes 7, 2, 0, 10 kHz) and 0.0699521 / 44.1516
    (7, 3, 0) are model values to 1e-6 of |Z| and 1e-4 degree, as are 0.05028097 / 5.59428 (1 kHz) and
    0.4975671 / 84.95387 (100 kHz, 7, 2, 1); at 10 kHz the set spans 43.662 .. 45.195 degree and 0.069250 ..
    0.070681 ohm. The first run of this case stored 0.070006 / 44.464 (menu) and 0.0700899 / 43.917 (host)
    at point 9, two values of that set; the former bounds 0.5 degree and 1e-2 [J] were narrower than the set.
    Margins of the membership: 1e-5 of |Z| and 1e-3 degree (the firmware's float32 values agreed with the
    model within 1e-6 and 1e-4 in that diagnostic). Input checks of the model: no sample at the clip (Av, Ai
    + 0.5 below the distance of mid to 0 and 4095), the ADC sample period 1 / (M f) at the window, the gain
    codes of the window equal the GPIO outputs."""
    import cmath
    import measure_model as MM

    def model_set(src, a, f, ts, fn, codes):
        """(|Z| min, |Z| max, theta min, theta max) over every sampling phase (docstring)."""
        nm = 128 // (1 if fn < 10000 else 4 if fn < 100000 else 16)
        check(abs(ts * f * nm - 1) < 1e-6, 'c19 %d Hz: ADC period %r s is not 1 / (%d f), f %r' % (fn, ts, nm, f))
        c5, c6, c8 = codes
        z = src.z(f)
        av = src.k * MM.GAIN[c5] * a
        ai = src.k * MM.GAIN[c6] * MM.RANGE_OHM[c8] * a / abs(z)
        check(max(av, ai) + 0.5 < min(src.mid, 4095 - src.mid), 'c19 %d Hz: amplitudes %.1f / %.1f reach the clip'
              % (fn, av, ai))
        ph = [2 * math.pi * m / nm for m in range(nm)]
        ex = [cmath.exp(-1j * x) for x in ph]
        az = cmath.phase(z)
        cuts = [0.0, 2 * math.pi / nm]
        for amp, off in ((av, 0.0), (ai, -az)):
            for x in ph:
                for q in range(int(math.floor(src.mid - amp)), int(math.ceil(src.mid + amp)) + 1):
                    c = (q + 0.5 - src.mid) / amp
                    if -1.0 <= c <= 1.0:
                        for y in (math.acos(c), -math.acos(c)):
                            cuts.append((y - x - off) % (2 * math.pi) % (2 * math.pi / nm))
        cuts = sorted(set(cuts))
        kz = MM.RANGE_OHM[c8] * MM.GAIN[c6] / MM.GAIN[c5]
        zs, ts_ = [], []
        for lo, hi in zip(cuts, cuts[1:]):
            if hi - lo < 1e-15:
                continue
            p = (lo + hi) / 2
            xv = xi = 0j
            for x, e in zip(ph, ex):
                xv += int(round(src.mid + av * math.cos(p + x))) * e
                xi += int(round(src.mid + ai * math.cos(p - az + x))) * e
            r = xv / xi
            zs.append(kz * abs(r))
            ts_.append(math.degrees(cmath.phase(r)))
        return min(zs), max(zs), min(ts_), max(ts_)

    res = {}
    for how in ('menu', 'host'):
        src = short_src()
        rig = cal_rig(src, block=pre_block(), usb=how == 'host')
        gens = []                                    # (t, |c|, f, ADC period, GPIO codes) at every publish

        def at_publish(r, gens=gens):
            e, g = r.meas._gen_epoch(), r.meas._adc_grid(0)
            gens.append((r.m.now(), abs(e['c']) if e else 0.0, e['freq'] if e else 0.0, g[1] if g else 0.0,
                         r.meas.front_end()))
        rig.probe.on_publish_entry = at_publish
        rig.run(1.0)
        before = table(rig)
        if how == 'menu':
            start(rig)
        else:
            ask_async(rig, 'CALIBRATE', b'\x00' + OK2)
            wait_until(rig, lambda: rig.rd(OWN_CAL + CAO_ON) != 0, 30.0, 'c19 host: the start')
        wait_end(rig)
        check(rig.rd(V_CAL_STATUS) == 2, 'c19 %s: status %d (reason %d at point %d)' % (
            how, rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY), rig.rd(OWN_CAL + CAO_FAILP)))
        after = check_sweep_result(rig, 0, before, 'c19 %s' % how)
        check_restored(rig, 'c19 %s' % how)
        rec = [rig.rd(OWN_CAL + o) for o in (CAO_SFREQ, CAO_SLEVEL, CAO_SBIAS, CAO_SSPEED)] + [
            rig.rd(OWN_CAL + CAO_REL, 0x78)]
        sets = []
        for p in range(15):
            wins, _ = windows_of(rig, p)
            zb, tb, used = expect_point(wins, 0)
            w = [u for u in used if u['Z'] == zb and u['TH'] == tb][0]
            g = [x for x in gens if x[0] <= w['t']][-1]
            check(g[4] == w['codes'], 'c19 %s point %d: codes %r in RAM, %r at the GPIO' % (how, p, w['codes'], g[4]))
            s = model_set(src, g[1], g[2], g[3], FREQS[p // 3], w['codes'])
            z, t = u32f(zb), u32f(tb)
            check(s[0] * (1 - 1e-5) <= z <= s[1] * (1 + 1e-5) and s[2] - 1e-3 <= t <= s[3] + 1e-3,
                  'c19 %s point %d: stored %.7g / %.5f outside the model set %.7g .. %.7g / %.5f .. %.5f (codes %r)'
                  % (how, p, z, t, s[0], s[1], s[2], s[3], w['codes']))
            sets.append((z, t, s, w['codes']))
        res[how] = (after, rec, sets)
        rig.watch.check(what='c19 %s' % how)
    check(res['menu'][1] == res['host'][1], 'c19: the recordings differ')
    for p in range(15):
        (zm, tm, sm, cm), (zh, th, sh, ch) = res['menu'][2][p], res['host'][2][p]
        zb = max(sm[1] - sh[0], sh[1] - sm[0]) + 1e-5 * (sm[1] + sh[1])
        tb = max(sm[3] - sh[2], sh[3] - sm[2]) + 2e-3
        check(abs(zm - zh) <= zb and abs(tm - th) <= tb, 'c19: point %d menu %.7g / %.5f, host %.7g / %.5f, '
              'allowed %.3g / %.4f' % (p, zm, tm, zh, th, zb, tb))
        NOTES.append('c19 point %d: menu %.7g / %.4f (codes %r), host %.7g / %.4f (%r), model theta %.4f .. %.4f'
                     % (p, zm, tm, cm, zh, th, ch, min(sm[2], sh[2]), max(sm[3], sh[3])))
    return True


@case
def c20_open_fail_restores_what_the_start_found():
    """Revision 10 items 3 and 4, the meter's sequence (2026-11-23): settings 1 kHz, 0.6 V, speed 0, bias 0
    and a pattern at 0x200010C0 (input check in RAM before the request), the meter on screen 1, CALIBRATE type
    11, an open that reads 50 kohm at 100 kHz, so the sweep fails "open low" at point 12. Expected: answer
    status 3 with calibration status 3, type 11, point 12, reason 3; frequency, level, speed, bias, type and
    the 0x200010C0 bytes as before; no SETTING_CHANGED of the speed word (0x0BD4) at all (0 before, 0 from
    the start, 0 after); the last frequency / level events carry 1000 / 0.6 V; nothing stored or saved; the
    dialog closed and screen 1 again when the answer comes.
    The source selects 100 kHz by f > 5e4 (between the sweep's 10 kHz and 100 kHz), not by f == 100000: the
    model's generator frequency is 1 / (n x period) in float64, 100000.00000000001 at the word 100000 (diagnostic
    run of 2026-11-23; 10000.0 exactly at 10 kHz, so c14's f == 10000 matched), so the equality
    never held and every point read 1 Mohm: the sweep finished (answer 020b00000000ff00). Input check, by
    cal_accept's criterion, before the answer is judged: point 12 published usable windows on screen 3, and
    each has |Z| + the point's short entry below 1e5 (so the resolved mean of revision 11 has too: the source is
    noise-free)."""
    words = {'0x%08x' % V_FREQ: 1000, '0x%08x' % V_LEVEL: 0x3F19999A, '0x%08x' % V_SPEED: 0,
             '0x%08x' % V_BIAS: 0}
    b = bytearray(block_with(**words))
    b[V_CAL_WORK - V_BLOCK:V_CAL_WORK - V_BLOCK + 0x78] = REL_PATTERN
    rig = cal_rig(DutSource(z=lambda f: complex(5e4 if f > 5e4 else 1e6, 0.0)), block=bytes(b), usb=True)
    rig.run(1.0)
    pre = (rig.rd(V_FREQ), rig.rd(V_LEVEL), rig.rd(V_SPEED), rig.rd(V_BIAS), rig.rd(V_SCREEN))
    check(pre == (1000, 0x3F19999A, 0, 0, 1) and rig.rd(V_CAL_WORK, 0x78) == REL_PATTERN,
          'c20: the state before %r (input)' % (pre,))
    before, saves0 = table(rig), rig.rd(SAVE_COUNT)
    seq = ask_async(rig, 'CALIBRATE', b'\x0b' + OK2)
    st, d = wait_answer(rig, seq, 'CALIBRATE', host_timeout(C['CALIBRATE']))
    t0 = struct.unpack_from('<f', before, entry(12) - USR_LO)[0]
    w12 = [u32f(w['Z']) + t0 for w in windows_of(rig, 12)[0] if usable(w)]
    check(w12 and all(z < 1e5 for z in w12), 'c20: point 12 |Z| + short %r (input)' % w12)
    check(st == S_NOT_NOW and len(d) == 8 and d[0] == 3 and d[1] == 11 and d[6] == 12 and d[7] == R_OPEN,
          'c20: answer status %d, %s' % (st, d.hex()))
    got = (rig.rd(V_FREQ), rig.rd(V_LEVEL), rig.rd(V_SPEED), rig.rd(V_BIAS), rig.rd(V_CAL_TYPE))
    check(got == (1000, 0x3F19999A, 0, 0, 11) and rig.rd(V_CAL_WORK, 0x78) == REL_PATTERN,
          'c20: after the fail %r' % (got,))
    ev = [struct.unpack_from('<HI', f['payload']) for f in rig.host.frames
          if f['type'] == FR_EVENT and f['cmd'] == E_SETTING and len(f['payload']) >= 6]
    check(not [v for i, v in ev if i == V_SPEED - V_BLOCK], 'c20: speed events %r' % (
        [v for i, v in ev if i == V_SPEED - V_BLOCK],))
    last = {i: v for i, v in ev}
    check(last.get(V_FREQ - V_BLOCK) == 1000 and last.get(V_LEVEL - V_BLOCK) == 0x3F19999A,
          'c20: last frequency / level events %r / %r' % (last.get(V_FREQ - V_BLOCK), last.get(V_LEVEL - V_BLOCK)))
    check(rig.rd(V_DIALOG) == 0 and rig.rd(V_SCREEN) == 1, 'c20: dialog %d screen %d after the answer' % (
        rig.rd(V_DIALOG), rig.rd(V_SCREEN)))
    check_nothing_stored(rig, before, saves0, 'c20')
    rig.watch.check(what='c20')
    return True


def line_ink(rig, text):
    """[(advance, {(x, y): level})] per character of text in F1 (f1_draw with the levels 0..3 as colours, each
    glyph at x = 0 of its own pattern, line top 0)."""
    out = []
    for ch in text:
        g = {}
        adv = f1_draw(rig, g, 0, 0, ch, (0, 1, 2, 3))
        out.append((adv, g))
    return out


def glyph_at(fb, g, ox, oy):
    """The glyph pattern g drawn at (ox, oy) in the panel memory fb: every level-3 pixel one colour, at least
    80 % of the level-0 pixels another (a neighbour's box may reach into its box; levels 1 / 2 are blends)."""
    full = [p for p, v in g.items() if v == 3]
    empty = [p for p, v in g.items() if v == 0]
    c3 = fb.get((ox + full[0][0], oy + full[0][1]))
    if c3 is None or any(fb.get((ox + x, oy + y)) != c3 for x, y in full):
        return False
    other = sum(1 for x, y in empty if fb.get((ox + x, oy + y)) not in (None, c3))
    return other >= 0.8 * len(empty)


def find_text(rig, fb, text):
    """Offsets (ox, oy) at which the panel memory shows text as one line: its first glyph matches there and
    each next glyph on the same row at the pen position +-3 pixels (the font's kerning, which f1_draw does not
    apply)."""
    ink = line_ink(rig, text)
    first = next(i for i, (_, g) in enumerate(ink) if any(v == 3 for v in g.values()))
    adv0, g0 = ink[first]
    fx, fy = next(p for p, v in g0.items() if v == 3)
    hits = []
    for (x, y) in list(fb):
        ox, oy = x - fx, y - fy
        if not glyph_at(fb, g0, ox, oy):
            continue
        pen, ok = ox + adv0, True
        for adv, g in ink[first + 1:]:
            if not any(v == 3 for v in g.values()):
                pen += adv                           # a space
                continue
            at = [px for px in range(pen - 3, pen + 4) if glyph_at(fb, g, px, oy)]
            if not at:
                ok = False
                break
            pen = at[0] + adv
        if ok:
            hits.append((ox, oy))
    return hits


@case
def c21_progress_and_fail_text_on_the_panel():
    """Revision 10 item 6 (the owner, 2026-11-23: the dialog counted to 12, then showed 3, 4, 5): a short sweep
    with the panel model; the panel log is cleared at every cal_point, so the replay holds what was drawn
    since. 0.5 s after cal_point(12): the status object's string is "13/15\n100k 0.1V" (the number and the
    formatter) and both lines are on the panel whole, every glyph from the leading "1" on (the text object and
    the font). Then TIM1 stopped (c3's stall): the fail text "Fail 13/15\nno signal" and both of its lines on
    the panel. The F1 widths of every line cal.s prints are at most 75 pixels (below the 80 of panel D)."""
    rig = cal_rig(short_src(), block=pre_block(), panel=True)
    rig.run(1.0)

    def on_point(r, p):
        r.m.panel.flushes.clear()
    rig.cal.on_point = on_point
    for t in [b'%d/15' % n for n in (1, 9, 15)] + [b'Fail %d/15' % n for n in (1, 15)] + [n.encode() for n in NAMES] + [
            b'no signal', b'time limit', b'open low', b'check', b'spread', b'aborted']:
        w = sum(a for a, _ in line_ink(rig, t.decode()))
        check(w <= 75, 'c21: %r is %d pixels wide in F1' % (t, w))
    start(rig)
    wait_point(rig, 12, 240.0)
    rig.run(0.5)
    txt = obj_text(rig, V_STAT_TXT)
    check(txt == b'13/15\n100k 0.1V', 'c21: progress string %r' % txt)
    fb = fb_replay(rig.m.panel.flushes)
    for line in ('13/15', '100k 0.1V'):
        hits = find_text(rig, fb, line)
        check(hits, 'c21: %r found %d times on the panel (%d pixels drawn)' % (line, len(hits), len(fb)))
    rig.m.panel.flushes.clear()
    rig.meas.write(rig.m, TIM1_CTRL1, 4, 0)          # CEN = 0: the stall (c3 (a))
    wait_until(rig, lambda: rig.rd(V_CAL_RUN) == 0, 4.0, 'c21: the stall fail')
    rig.run(0.5)
    txt = obj_text(rig, V_STAT_TXT)
    check(txt == b'Fail 13/15\nno signal', 'c21: fail string %r' % txt)
    fb = fb_replay(rig.m.panel.flushes)
    for line in ('Fail 13/15', 'no signal'):
        hits = find_text(rig, fb, line)
        check(hits, 'c21: %r found %d times on the panel (%d pixels drawn)' % (line, len(hits), len(fb)))
    return True


def host_to_item(rig, item):
    """With the injected keys of KEY: long key 8 (settings) from screen 1, then key 0x20 to the item."""
    if rig.rd(V_SCREEN) != 3:
        st, _ = rig.ask('KEY', struct.pack('<BH', 3, 1200), timeout=25.0)
        check(st == S_OK and rig.rd(V_SCREEN) == 3, 'KEY long 8: status %d screen %d' % (st, rig.rd(V_SCREEN)))
    for _ in range(8):
        if rig.rd(V_MENU) == item:
            return
        st, _ = rig.ask('KEY', bytes([5]), timeout=25.0)
        check(st == S_OK, 'KEY 0x20: status %d' % st)
    check(rig.rd(V_MENU) == item, 'menu item %d not reached (%d)' % (item, rig.rd(V_MENU)))


@case
def c22_host_drives_the_calibration_menu():
    """Revision 10 item 4: with KEY and SCREEN only. Item 5: key 8 opens the dialog (status 0, nothing runs);
    SCREEN 1 from it closes it (status 0, screen 1); again to the dialog, key 8 starts the calibration
    (status 0, 0x200050E4 = 1, the sweep of cal.s in progress). While it runs KEY, SCREEN and LCR_SET answer
    6 and it goes on; it finishes (status 2), saves once and restores the settings as one started by the
    meter's keys. Then the dialog closed with long key 8, item 6: key 8 opens the restore-defaults dialog, key
    8 there and SCREEN answer 6 (the confirmation stays the meter's)."""
    rig = cal_rig(short_src(), block=pre_block(), usb=True)
    rig.run(1.0)
    saves0 = rig.rd(SAVE_COUNT)
    host_to_item(rig, 5)
    st, _ = rig.ask('KEY', bytes([3]), timeout=25.0)
    check(st == S_OK and rig.rd(V_DIALOG) != 0 and rig.rd(V_CAL_RUN) == 0, 'c22: key 8 on item 5: status %d '
          'dialog %d running %d' % (st, rig.rd(V_DIALOG), rig.rd(V_CAL_RUN)))
    st, _ = rig.ask('SCREEN', b'\x01')
    check(st == S_OK and rig.rd(V_SCREEN) == 1 and rig.rd(V_DIALOG) == 0 and rig.rd(V_CAL_RUN) == 0,
          'c22: SCREEN 1 from the dialog: status %d screen %d dialog %d' % (st, rig.rd(V_SCREEN), rig.rd(V_DIALOG)))
    host_to_item(rig, 5)
    st, _ = rig.ask('KEY', bytes([3]), timeout=25.0)
    check(st == S_OK and rig.rd(V_DIALOG) != 0, 'c22: the dialog again: status %d' % st)
    st, _ = rig.ask('KEY', bytes([3]), timeout=25.0)
    check(st == S_OK and rig.rd(V_CAL_RUN) != 0, 'c22: key 8 in the dialog: status %d running %d' % (
        st, rig.rd(V_CAL_RUN)))
    rig.run(0.3)
    check(rig.rd(OWN_CAL + CAO_ON) == 1, 'c22: no sweep of cal.s in progress')
    for cmd, p in (('KEY', bytes([2])), ('SCREEN', b'\x01'), ('LCR_SET', b'\x06\x00')):
        st, _ = rig.ask(cmd, p, timeout=25.0)
        check(st == S_SAFETY, 'c22: %s while it runs: status %d' % (cmd, st))
    check(rig.rd(V_CAL_RUN) != 0 and rig.rd(OWN_CAL + CAO_ON) == 1, 'c22: a refused request ended the sweep')
    wait_end(rig)
    check(rig.rd(V_CAL_STATUS) == 2, 'c22: status %d (reason %d at point %d)' % (
        rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY), rig.rd(OWN_CAL + CAO_FAILP)))
    check(rig.rd(SAVE_COUNT) == saves0 + 1, 'c22: saves %d -> %d' % (saves0, rig.rd(SAVE_COUNT)))
    check_restored(rig, 'c22')
    st, _ = rig.ask('KEY', struct.pack('<BH', 3, 1200), timeout=25.0)
    check(st == S_OK and rig.rd(V_DIALOG) == 0 and rig.rd(V_SCREEN) == 3, 'c22: long 8 in the finished dialog: '
          'status %d dialog %d screen %d' % (st, rig.rd(V_DIALOG), rig.rd(V_SCREEN)))
    host_to_item(rig, 6)
    st, _ = rig.ask('KEY', bytes([3]), timeout=25.0)
    check(st == S_OK and rig.rd(V_DIALOG) != 0, 'c22: key 8 on item 6: status %d dialog %d' % (st, rig.rd(V_DIALOG)))
    for cmd, p in (('KEY', bytes([3])), ('SCREEN', b'\x01')):
        st, _ = rig.ask(cmd, p, timeout=25.0)
        check(st == S_SAFETY and rig.rd(V_DIALOG) != 0 and rig.rd(V_SCREEN) == 3,
              'c22: %s in the restore-defaults dialog: status %d' % (cmd, st))
    rig.watch.check(what='c22')
    return True


def windows_of_admittances(ys, t0, th0):
    """The screen-3 windows (|Z| = |Zo| - |t0|, theta = arg Zo) of open admittances ys: Zo = 1 / Y + Zs."""
    zs = abs(t0) * cmath.exp(1j * math.radians(th0))
    out = []
    for y in ys:
        zo = 1 / y + zs
        out.append((abs(zo) - abs(t0), math.degrees(cmath.phase(zo))))
    return out


# The open sweep of 2026-11-23 (leads open, 0.3 V, the table of backup 20261123-191801-pre-opensweep): per
# frequency the point, its short entry (t0, theta0) and the first 7 readings after the first, turned back into
# the screen-3 windows of an open calibration through the stored table (computed outside this file:
# |Zdut| from the decade interpolation inverted, Y = 1 / Zdut + Yo, Zo = 1 / Y + Zs), with the result the
# revision-11 rule gives (revision 11) and the revision-14 gate after it: the 1 kHz set's
# mean is G -2.909e-10 S, B 1.372e-8 S, arg Ybar +91.215 degrees (the gate applied to that set): B >= |G| and C
# 2.18 pF, so the gate keeps it ('res'; the first revision-14 gate, G >= 0, refused this real stray); 10 kHz
# +85.909 degrees, C 1.954 pF and 100 kHz +73.675 degrees, C 1.982 pF pass
METER_OPEN = [
    (100, 1, 0.000395802, -171.588, [(5.93615e+07, -141.579), (5.59751e+07, 171.7), (7.59358e+07, -56.4039),
                                     (8.86626e+07, -53.7679), (5.24748e+07, 71.9602), (1.48162e+08, 58.1453),
                                     (3.28581e+07, -149.559)], 'nr'),
    (120, 4, 0.000582478, -169.428, [(3.30139e+07, -122.469), (3.88472e+07, 137.39), (2.84043e+07, 115.825),
                                     (3.14367e+07, 115.817), (4.18069e+07, 165.027), (2.54455e+07, -169.213),
                                     (2.52606e+07, 169.914)], 'nr'),
    (1000, 7, 0.000982688, 117.938, [(6.82662e+07, -81.7466), (8.26089e+07, -90.8729), (7.99421e+07, -83.6597),
                                     (7.20266e+07, -78.9729), (7.79838e+07, -109.604), (6.99867e+07, -101.67),
                                     (5.77064e+07, -92.6438)], 'res'),
    (10000, 10, 0.00887205, 80.9322, [(8.09306e+06, -85.997), (8.2361e+06, -86.9464), (8.1528e+06, -86.6762),
                                      (7.873e+06, -85.4812), (8.13495e+06, -85.875), (8.25829e+06, -84.8955),
                                      (8.13118e+06, -85.5052)], 'res'),
    (100000, 13, 0.084615, 78.1223, [(771237, -73.6766), (771252, -73.6653), (769827, -73.6642),
                                     (771032, -73.6771), (770573, -73.7128), (770309, -73.6144),
                                     (771391, -73.7179)], 'res'),
]


@case
def u02_open_rule_unit():
    """cal_ores (revision 11: the vector mean of the open admittances when resolved by the F test, else "not
    resolved" 1e10 / +400; revision 14: kept only as a lead stray, B >= |G|, B > 0, B <= 2 pi f 50 pF, when
    |Zo| >= 1e5) called directly on a rig at the main loop, with the point's short entry written into the RAM
    table, on sets of 0..7 windows with the expected kind written out: none and one window (not resolved), three
    equal windows (resolved, the sum of squares 0; at 10 kHz arg Ybar +88 degrees, C 1.99 pF), a 2 pF stray at
    10 kHz with G 5e-9 S (the stored 10 kHz opens of three backups: G 5.2e-9 .. 1.32e-8 S, read
    from the backups) and a scatter of 3e-9 S (resolved; without G its mean lay at +89.999 degrees, on the
    gate's edge), the same stray at 100 Hz (1.26e-9 S) with a scatter of 2e-8 S spread around it (not
    resolved), METER_OPEN, and the gate sets, each three equal windows (S = 0, resolved by the F test) at
    point 4 (120 Hz, 0.3 V) with METER_OPEN's short entry there: the stored 120 Hz opens of backup
    20261123-233542 at 0.1 V (Y = -2.87e-7 + j2.92e-8 S, arg Ybar +174.2, C 38.8 pF: B < |G|) and of backup
    20261123-204351 at 0.3 V (Y = 3.9e-8 - j2.78e-8 S: B < 0), 60 pF with G 1e-10 S (above 50 pF), all
    'gate'; 20 pF with G 1e-10 S (arg Ybar +89.6, below 50 pF: 'res'); 20 pF with G -1e-10 S (arg Ybar +90.4,
    B >= |G|: 'res', a noise-negative G of a real stray); and 50 kohm resistive at 10 kHz (point
    10; |Zo| below 1e5: returned as it is, 'res', for cal_accept's open-low fail). Input check: open_rule gives
    the written kind for every set (not 'edge'). Expected: open_match."""
    rig = own_rig(DutSource())
    w = 2 * math.pi
    y10k = 5e-9 + 1j * w * 1e4 * 2e-12
    y100 = 1j * w * 100 * 2e-12
    t120, th120 = METER_OPEN[1][2], METER_OPEN[1][3]
    sets = [('none', 1, 0.0004, -170.0, [], 'nr'),
            ('one', 10, 0.009, 81.0, [(8.0e6, -88.0)], 'nr'),
            ('equal', 10, 0.009, 81.0, [(8.0e6, -88.0)] * 3, 'res'),
            ('stray 10 kHz', 10, 0.009, 81.0, windows_of_admittances(
                [y10k + 3e-9 * cmath.exp(1j * math.radians(103.0 * i)) for i in range(7)], 0.009, 81.0), 'res'),
            ('noise 100 Hz', 1, 0.0004, -170.0, windows_of_admittances(
                [y100 + 2e-8 * cmath.exp(1j * math.radians(17.0 + 360.0 * i / 7)) for i in range(7)],
                0.0004, -170.0), 'nr')]
    sets += [('meter %d Hz' % f, p, t0, th0, wins, kind) for f, p, t0, th0, wins, kind in METER_OPEN]
    for what, y, kind in (('120 Hz open of 2026-11-23 23:35, 0.1 V', complex(-2.87e-7, 2.92e-8), 'gate'),
                          ('120 Hz open of 2026-11-23 20:43, 0.3 V', complex(3.9e-8, -2.78e-8), 'gate'),
                          ('60 pF at 120 Hz', complex(1e-10, w * 120 * 60e-12), 'gate'),
                          ('20 pF at 120 Hz', complex(1e-10, w * 120 * 20e-12), 'res'),
                          ('20 pF at 120 Hz, G below 0', complex(-1e-10, w * 120 * 20e-12), 'res')):
        sets.append((what, 4, t120, th120, windows_of_admittances([y] * 3, t120, th120), kind))
    sets.append(('50 kohm at 10 kHz', 10, 0.009, 81.0, windows_of_admittances([complex(2e-5, 0)] * 3, 0.009, 81.0),
                 'res'))
    for what, p, t0, th0, wins, kind in sets:
        t0f, th0f = u32f(f2u(t0)), u32f(f2u(th0))
        wf = [(u32f(f2u(z)), u32f(f2u(th))) for z, th in wins]
        rule = open_rule(wf, t0f, th0f, FREQS[p // 3])
        check(rule[0] == kind, 'u2 %s: the rule gives %r, written %s (input)' % (what, rule, kind))
        rig.wr(entry(p, 0), f2u(t0))
        rig.wr(entry(p, 0) + 0x2D0, f2u(th0))
        rig.wr(OWN_CAL + CAO_PT, p)
        for i, (z, th) in enumerate(wins):
            rig.wr(OWN_CAL + CAO_OWIN + 8 * i, f2u(z))
            rig.wr(OWN_CAL + CAO_OWIN + 8 * i + 4, f2u(th))
        rig.wr(OWN_CAL + CAO_NO, len(wins))
        r0 = rig.m.call(rig.s['cal_ores'])
        r1 = rig.m.uc.reg_read(UC_ARM_REG_R1)
        open_match(r0, r1, rule, t0f, 'u2 %s' % what)
        NOTES.append('u2 %s: %s, q %s, stored %.6g / %.4f' % (what, rule[0], 'none' if rule[2] is None else
                                                              '%.4g' % rule[2], u32f(r0), u32f(r1)))
    return True


@case
def u03_open_fill_unit():
    """cal_ofill (revision 14 rule 3 b) called directly on a rig at the main loop, with the 15 results in CAO_RES
    and the short entries of points 0..11 written into the RAM table. A resolved source result is the stored form
    of Y = G + j 2 pi f C over its short: Zo = 1 / Y + Zs, words |Zo| - |t0| and arg Zo (windows_of_admittances);
    "not resolved" is 1e10 / +400.
    Set A: sources 6 (1 kHz 0.1 V) 2.0 pF with G 1e-9 S, 9 (10 kHz 0.1 V) 2.5 pF, 10 (10 kHz 0.3 V) 3.0 pF with
    G 5e-9 S, 12..14 (100 kHz) 1.8 pF; 7, 8, 11 not resolved; targets 0, 1, 2, 4, 5 not resolved, 3 (120 Hz,
    0.1 V) a resolved 20 pF open. Expected by cal_fsrc: 0 from 6 (2.0 pF), 1 from 10 (7 not resolved), 2 from 6
    (8 and 11 not resolved), 3 kept bit for bit, 4 from 10, 5 from 6; G dropped. By hand: Zo_low = Zs_low - j /
    (2 pi f_low C) with Zs of milliohms, so |Zo_low| - |t0| is 1 / (2 pi f_low C) and arg Zo_low -90 degrees:
    0 and 2: 1 / (2 pi 100 Hz 2e-12 F) = 7.957747e8 ohm; 1: 1 / (2 pi 100 3e-12) = 5.305165e8; 4: 1 / (2 pi
    120 3e-12) = 4.420971e8; 5: 1 / (2 pi 120 2e-12) = 6.631456e8 (input check: open_fill of the planted float32
    words within 1e-6 relative of these and 1e-4 degree of -90). Point 2's short has theta0 +400 (not an angle:
    Zs = |t0|, the other path of cal_zs). Set B: every source 6..11 not resolved: the targets stay 1e10 / +400
    bit for bit. Both sets: points 3 and 6..14 unchanged bit for bit. Expected: open_match (module bounds)."""
    rig = own_rig(DutSource())
    w = 2 * math.pi
    shorts = {p: (0.0004 + 0.0001 * p, -170.0 if p < 6 else (118.0 if p < 9 else 81.0)) for p in range(12)}
    shorts[2] = (0.0006, 400.0)
    nr = (F_1E10, F_P400)

    def stored(p, c, g=0.0):
        t0, th0 = shorts.get(p, (0.08, 78.0))
        (z, th), = windows_of_admittances([complex(g, w * FREQS[p // 3] * c)], t0, th0)
        return f2u(z), f2u(th)
    hand = {0: 7.957747e8, 1: 5.305165e8, 2: 7.957747e8, 4: 4.420971e8, 5: 6.631456e8}
    base = {p: nr for p in range(15)}
    base[3] = stored(3, 20e-12, 1e-10)
    base.update({12: stored(12, 1.8e-12), 13: stored(13, 1.8e-12), 14: stored(14, 1.8e-12)})
    set_a = dict(base)
    set_a.update({6: stored(6, 2.0e-12, 1e-9), 9: stored(9, 2.5e-12), 10: stored(10, 3.0e-12, 5e-9)})
    src_a = {0: 6, 1: 10, 2: 6, 4: 10, 5: 6}
    for p, (t0, th0) in shorts.items():
        rig.wr(entry(p, 0), f2u(t0))
        rig.wr(entry(p, 0) + 0x2D0, f2u(th0))
    sh = {p: (u32f(f2u(t0)), u32f(f2u(th0))) for p, (t0, th0) in shorts.items()}
    for what, res, srcs in (('A', set_a, src_a), ('B', base, {})):
        for p in range(15):
            rig.wr(OWN_CAL + CAO_RES + 8 * p, res[p][0])
            rig.wr(OWN_CAL + CAO_RES + 8 * p + 4, res[p][1])
        rig.m.call(rig.s['cal_ofill'])
        got = {p: (rig.rd(OWN_CAL + CAO_RES + 8 * p), rig.rd(OWN_CAL + CAO_RES + 8 * p + 4)) for p in range(15)}
        for p in [3] + list(range(6, 15)):
            check(got[p] == res[p], 'u3 %s: point %d changed %08X / %08X -> %08X / %08X' % (
                what, p, res[p][0], res[p][1], got[p][0], got[p][1]))
        for p in (0, 1, 2, 4, 5):
            rule, src = fill_expect(res, sh, p)
            check(src == srcs.get(p), 'u3 %s: point %d fill source %r, expected %r (input)' % (what, p, src,
                                                                                            srcs.get(p)))
            if src is not None:
                zv, tv = rule[1]
                check(abs(zv - hand[p]) <= 1e-6 * hand[p] and abs(tv + 90.0) <= 1e-4,
                      'u3 %s: point %d fill %.7g / %.6f, by hand %.7g / -90 (input)' % (what, p, zv, tv, hand[p]))
            open_match(got[p][0], got[p][1], rule, sh[p][0], 'u3 %s: point %d' % (what, p))
            NOTES.append('u3 %s: point %d from %r: %.7g / %.5f' % (what, p, src, u32f(got[p][0]), u32f(got[p][1])))
    return True


def open_c23():
    """c23's open: 100 Hz (f < 110) 40 pF with G 2e-8 S (arg Y +51.5 degrees, |Z| 3.11e7 ohm); 120 Hz (110 .. 500)
    3e7 ohm at -170 degrees (its admittance at +170: G < 0, no lead stray, coherent: the model has no noise);
    1 kHz and 10 kHz (500 .. 5e4) 40 pF with G 2e-8 S (+85.45 degrees, 3.97e6 ohm; +89.54 degrees, 3.98e5 ohm);
    100 kHz (above 5e4, c20's note on the model's 100 kHz word) 1 Mohm resistive (refused by the gate, |Zo| >=
    1e5, so no open-low fail)."""
    w = 2 * math.pi

    def z(f):
        if f < 110 or 500 <= f < 5e4:
            return 1 / complex(2e-8, w * f * 40e-12)
        if f < 500:
            return 3e7 * cmath.exp(1j * math.radians(-170.0))
        return complex(1e6, 0.0)
    return DutSource(z=z)


@case
def c23_open_gate_and_fill():
    """Revision 14 on a whole open sweep (open_c23). Input checks (open_rule of each point's windows with its
    short entry): the three 120 Hz points are 'gate' (the F test resolves them, the gate refuses them) and the
    three 1 kHz points 'res'. Expected: the sweep finishes (status 2) with one save (SAVE_COUNT + 1); every point
    by check_sweep_result (the fill included); each 120 Hz point filled from the 1 kHz point of its level
    (fill_expect's source 6 + level, its stored theta not +400), |Zo| - |t0| within 1e-2 of 1 / (2 pi 120 Hz 40
    pF) = 3.315728e7 ohm [J: the model's 12-bit codes of the 1 kHz windows] and theta within 0.1 degree of
    -90; the 100 kHz points "not resolved" (refused by the gate, not filled: only 100 / 120 Hz are)."""
    rig = cal_rig(open_c23(), block=pre_block())
    rig.run(1.0)
    before, saves0 = table(rig), rig.rd(SAVE_COUNT)
    start(rig, typ=11)
    wait_end(rig)
    check(rig.rd(V_CAL_STATUS) == 2, 'c23: status %d (reason %d at %d)' % (
        rig.rd(V_CAL_STATUS), rig.rd(OWN_CAL + CAO_WHY), rig.rd(OWN_CAL + CAO_FAILP)))
    check(rig.rd(SAVE_COUNT) == saves0 + 1, 'c23: saves %d -> %d' % (saves0, rig.rd(SAVE_COUNT)))
    kinds = {}
    for p in range(15):
        wins, _ = windows_of(rig, p)
        s0 = struct.unpack_from('<f', before, entry(p, 0) - USR_LO)[0]
        s0t = struct.unpack_from('<f', before, entry(p, 0) - USR_LO + 0x2D0)[0]
        kinds[p] = expect_point(wins, 11, (s0, s0t), FREQS[p // 3])[0][0]
    check(all(kinds[p] == 'gate' for p in (3, 4, 5)) and all(kinds[p] == 'res' for p in (6, 7, 8)),
          'c23: rule kinds %r (input: 120 Hz gate, 1 kHz resolved)' % kinds)
    after = check_sweep_result(rig, 11, before, 'c23')
    words = {p: (struct.unpack_from('<I', after, entry(p, 11) - USR_LO)[0],
                 struct.unpack_from('<I', after, entry(p, 11) - USR_LO + 0x2D0)[0]) for p in range(15)}
    shorts = {p: (struct.unpack_from('<f', before, entry(p, 0) - USR_LO)[0],
                  struct.unpack_from('<f', before, entry(p, 0) - USR_LO + 0x2D0)[0]) for p in range(15)}
    hand = 1 / (2 * math.pi * 120 * 40e-12)
    for p in (3, 4, 5):
        _, src = fill_expect(words, shorts, p)
        z, th = u32f(words[p][0]), u32f(words[p][1])
        check(src == 6 + p % 3 and words[p][1] != F_P400 and abs(z - hand) <= 1e-2 * hand and abs(th + 90.0) <= 0.1,
              'c23: point %d stored %.7g / %.4f from %r, expected the fill of point %d, %.7g / -90' % (
                  p, z, th, src, 6 + p % 3, hand))
    check(all(words[p] == (F_1E10, F_P400) for p in (12, 13, 14)), 'c23: 100 kHz words %r' % (
        [(hex(a), hex(b)) for a, b in (words[p] for p in (12, 13, 14))],))
    NOTES.append('c23: kinds %s' % ' '.join('%d:%s' % (p, kinds[p]) for p in range(15)))
    check_restored(rig, 'c23', typ=11)
    rig.watch.check(what='c23')
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
