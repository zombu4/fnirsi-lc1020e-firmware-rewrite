#!/usr/bin/env python3
"""test_own_cal.py - the calibration sweep of our build (firmware/own/cal.s; MEASUREMENT_FIX_DESIGN.md stage 3:
CAL_SETTLE_DESIGN.md section 2 with every item of its critique, the cases of CAL_SETTLE 4.1 as the critique
amended them and the new ones it lists, design 5.1 "Stage 3"), in the emulator.

Usage (from the repository root, after `make -C firmware own`):
    <python with unicorn 2.1.4> tests/test_own_cal.py [case-name-prefix ...]

Rig: tests/test_own_measure.py own_rig (our build, TableWatch m15 and the Probe armed from reset, the settings
block in copies A and B). This file adds CalProbe: the entries of cal_point (r0 = the point), cal_commit and
cal_abort / cal_fail, and every write of the step word 0x200050E8.

The expected result of a point comes from the specification of cal.s applied to the windows the probe saw
published on screen 3 between the point's cal_point and the next (expect_point): a no-reading / overload set
or a non-finite window empties the held windows; the last 3 held are judged: the median |Z| (signed compare)
and the theta of the same window, accepted when every |Zi| <= 2 |Zm| and 2 |Zi| >= |Zm|; an open (type 11)
after 9 windows without that is accepted with theta +400 ("not resolved"). The stored table entries must equal
these bit for bit (fn_0800bb64 copies the words).

Sources: measure_model.DutSource / test_own_measure.TDut; the counts per volt are chosen per case so that both
channels lie in band at a range and gain code the ranging reaches (the model's source is ideal; revision 5 row
18). RUN LIMIT: one run of this file per case prefix, 17 cases.
"""

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
from test_own_control import (check, block_with, OK2, C, S_OK, S_NOT_NOW, SAVE_COUNT, E_CAL, E_SAVE,  # noqa: E402
                              KEY_POWER, OWN_CAL, CAO_ON, CAO_REC, CAO_SFREQ, CAO_SLEVEL, CAO_SBIAS, CAO_SSPEED,
                              CAO_REL, V_CAL_WORK, host_timeout, BLK, V_BLOCK)
from meter_model import SET_A, SET_B  # noqa: E402
from measure_model import DutSource  # noqa: E402
from usb_host import FR_ANSWER, FR_EVENT  # noqa: E402

CASES = []
NOTES = M.NOTES

# ---- own.inc OWN_CAL (cal.s) ----
CAO_PT, CAO_NW, CAO_TPT, CAO_FAILP, CAO_WHY, CAO_STYPE, CAO_WIN = 0x04, 0x08, 0x14, 0x20, 0x24, 0x3C, 0x40
R_NONE, R_STALL, R_TIME, R_OPEN, R_CHECK, R_SPREAD, R_ABORT = range(7)
V_CAL_STEP, V_CAL_STATUS = 0x200050E8, 0x200050EC
V_STAT_TXT, V_TYPE_TXT, V_STAT_NAMES, V_TYPE_NAMES, V_LANGUAGE = 0x20005960, 0x20005958, 0x200000FC, 0x2000009C, 0x2000115C
F_P400 = 0x43C80000
FREQS = (100, 120, 1000, 10000, 100000)
LEVELS = (0x3DCCCCCD, 0x3E99999A, 0x3F19999A)
NAMES = ['%s %sV' % (fs, lv) for fs in ('100Hz', '120Hz', '1kHz', '10kHz', '100kHz') for lv in ('0.1', '0.3', '0.6')]
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
    """CAL_SETTLE 4.1 c1's short z = 0.005 + j 2 pi f 78 nH, scaled by 10 (0.05 ohm + 780 nH: 0.05..0.49 ohm
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


def cal_rig(source, block=None, usb=False, keys_at_start=0):
    rig = own_rig(source, block=block, usb=usb, keys_at_start=keys_at_start)
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
    wait_until(rig, lambda: rig.rd(V_CAL_RUN) == 0 and rig.rd(OWN_CAL + CAO_ON) == 0, seconds, 'sweep end')
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


def expect_point(wins, typ):
    """(|Z| bits, theta bits, the 3 windows) the specification of cal.s gives for the windows of one point,
    or None when they give no result."""
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
        if typ == 11 and nt >= 9:
            return held[m]['Z'], F_P400, held
    return None


def check_sweep_result(rig, typ, before, what, since=0.0):
    """Every point's stored |Z| and theta entry equal expect_point of its windows, each window used only of
    acquisitions after the point's fn_08009f10 (cal_point), the other types' entries unchanged; no store before
    the commit (fn_0800bb64's writes all after the last point's last window)."""
    after = table(rig)
    last_win = 0.0
    for p in range(15):
        wins, t0 = windows_of(rig, p, since)
        exp = expect_point(wins, typ)
        check(exp is not None, '%s: point %d: the windows give no result (%d windows)' % (what, p, len(wins)))
        zb, tb, used = exp
        got_z = struct.unpack_from('<I', after, entry(p, typ) - USR_LO)[0]
        got_t = struct.unpack_from('<I', after, entry(p, typ) - USR_LO + 0x2D0)[0]
        check(got_z == zb and got_t == tb, '%s: point %d stored %08X / %08X, expected %08X / %08X (%r)' % (
            what, p, got_z, got_t, zb, tb, [(hex(w['Z']), hex(w['TH'])) for w in wins[-4:]]))
        for w in used:
            check(all(a['t'] > t0 for a in w['adds']), '%s: point %d: a window holds an acquisition from before '
                  'its fn_08009f10' % (what, p))
        last_win = max(last_win, used[-1]['t'])
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
    """D10 / critique items 5 and 7: frequency, level, speed, bias, type and 0x200010C0.. as before the sweep."""
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
    """CAL_SETTLE c1 / c4 (with critique items 6, 7 and 9 and the false-window unit, c12): a short sweep started
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
    seq = ask_async(rig, 'CALIBRATE', b'\x00' + OK2)
    wait_point(rig, 7, 120.0)
    rig.run(0.2)
    txt = obj_text(rig, V_STAT_TXT)
    check(txt == b'8/15\n' + NAMES[7].encode(), 'c1: progress text %r' % txt)
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
    lang = rig.rd(V_LANGUAGE)
    fin = cstr(rig, rig.rd(V_STAT_NAMES + 4 * (4 * lang + 2)))
    check(obj_text(rig, V_STAT_TXT) == fin, 'c1: finish text %r, vendor %r' % (obj_text(rig, V_STAT_TXT), fin))
    check_restored(rig, 'c1')
    blk = rig.rd(V_BLOCK, BLK)
    check(rig.m.get(SET_A, BLK) == blk, 'c1: copy A does not hold the block after the finish')
    rig.watch.check(what='c1')
    NOTES.append('c1: sweep %.1f s emulated (CALIBRATE to the finish), %d windows' % (
        rig.cal.commits[0] - rig.cal.points[0][0], len([w for w in rig.probe.pubs if w['screen'] == 3])))
    return True


# ---------------------------------------------------------------- c2 part jump inside a point

@case
def c02_jump_inside_a_point():
    """CAL_SETTLE c2 (critique item 9): the short reads 3x for 0.3 s inside point 4. The stored entry of point 4
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
    """CAL_SETTLE c3 as the critique changed it (item 8): (a) TIM1 stopped in point 7 (no conversion, no re-arm
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
    """CAL_SETTLE c5 (critique item 5): CALIBRATE, then a physical key 4 during point 4 (the vendor clears
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
    st, d = wait_answer(rig, seq, 'CALIBRATE', 5.0)
    check(st == S_NOT_NOW and d[0] == 0, 'c5: answer status %d, data %s' % (st, d.hex()))
    check(rig.rd(V_CAL_RUN) == 0 and rig.rd(V_CAL_STEP) == 0 and rig.rd(V_CAL_STATUS) == 0, 'c5: E4 / E8 / EC')
    check(rig.rd(OWN_CAL + CAO_WHY) == R_ABORT and rig.rd(OWN_CAL + CAO_FAILP) == 4, 'c5: reason / point')
    lang = rig.rd(V_LANGUAGE)
    name0 = cstr(rig, rig.rd(V_TYPE_NAMES + 4 * (12 * lang + 0)))
    check(obj_text(rig, V_TYPE_TXT) == name0, 'c5: type text %r, type 0 is %r' % (obj_text(rig, V_TYPE_TXT), name0))
    check_nothing_stored(rig, before, saves0, 'c5')
    check_restored(rig, 'c5')
    rig.watch.check(what='c5')
    return True


# ---------------------------------------------------------------- c7 the vendor's store check

@case
def c07_store_check_fails():
    """CAL_SETTLE c7: the vendor check of fn_0800bb64 fails at the store of point 5: a 2 ohm "short" (types 0..2
    at 0.9 ohm or above go to its 50 % test, critique item 10) against old short entries of 2 ohm at points
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
    current channel is noise-limited at every point: the sweep completes, every point stored by the rule
    (agreeing three, or "not resolved" with theta +400 after 9 windows), every |Zo| >= 1e5."""
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
    """Design stage 3 "open validity": an open of 1 Mohm that reads 50 kohm at 10 kHz fails the sweep at point
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
    """Design stage 3 / S1.9: in factory mode (PC11 at the start, the gate of fn_0800bd5c sets 2 on screen 3) a
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
