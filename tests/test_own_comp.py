#!/usr/bin/env python3
"""test_own_comp.py - stage 4 of our build's measurement core (firmware/own/meas.s meas_comp, meas_cz,
meas_bias_wait; MEASUREMENT_FIX_DESIGN.md S4.1 with S4.2 option (K), S4.4; design 5.1 "Stage 4" m40..m45 and
the cases revision 7 adds), in the emulator.

Usage (from the repository root, after `make -C firmware own`):
    <python with unicorn 2.1.4> tests/test_own_comp.py [case-name-prefix ...]

Rig: tests/test_own_measure.py own_rig (TableWatch m15 and the Probe armed from reset). The expected values
come from the specification, computed here in float64 from the window the probe captured at the publish
(Zbar = K sum V' / sum I', S1.3): comp(Zm) = (Zm - Zs) / (1 - (Zm - Zs) Yo), Yo = 1 / (Zo - Zs), Zs = |t0|
e^(j theta0), Zo = (t11 + |t0|) e^(j theta11), short only when the open is unusable; b'_k = |comp((b_k + |t0|)
e^(j theta_k))|; |Z|c = the decade interpolation of |Zdut| against b'_k; theta = arg Zdut. The firmware
computes in float32 with the vendor's single-precision sine / cosine: the bound is 1e-4 relative for |Z| and
0.01 degree for theta [J: float32 rounding of the 10 reference compensations and the interpolation].

The fixture (fixture_block): the same at all 15 entries of the user table, Zs = 0.2 ohm at 30 degrees, Zo =
2 Mohm at -80 degrees, and the 10 references N_k = 0.01 * 10^(k-1) ohm as a meter would have stored them
through that fixture (b_k = |Zm_k| - |t0|, theta_k = arg Zm_k, Zm_k = Zs + N_k / (1 + N_k Yo)). The factory
table keeps the defaults, so a result that matches the fixture's expectation used the user table (m44).
RUN LIMIT: one run of this file per case prefix, 7 cases.
"""

import cmath
import math
import os
import struct
import sys

from unicorn import UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_S16, UC_ARM_REG_S17

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_own_measure as M  # noqa: E402
from test_own_measure import own_rig, settings_item, TDut, is_set, u32f, f2u, interp64, USR_LO, V_BIAS, V_TICK  # noqa: E402
from test_own_control import check, block_with  # noqa: E402
from measure_model import DutSource, GAIN, RANGE_OHM  # noqa: E402

CASES = []
NOTES = M.NOTES
V_BLOCK = 0x2000057C
F_OPENDEF, F_1E10, F_M400, F_P400 = 0x5368D4A5, 0x501502F9, 0xC3C80000, 0x43C80000
ZS = cmath.rect(0.2, math.radians(30.0))
ZO = cmath.rect(2e6, math.radians(-80.0))
NOMINAL = [0.01 * 10 ** (k - 1) for k in range(1, 11)]
OWN_FUNC = 0x20018000 + 0x5DE0
MF_BIASP = 0x80
V_MID_V, V_MID_I = 0x200011D0, 0x200011D8


def case(fn):
    CASES.append(fn)
    return fn


def cis(deg):
    return cmath.exp(1j * math.radians(deg))


def deg(z):
    return math.degrees(cmath.phase(z))


def entry_words(t0, th0, t11, th11, refs):
    """The 12 |Z| floats and 12 theta floats of one entry (short, b1..b10, open)."""
    z = [t0] + [b for b, _ in refs] + [t11]
    th = [th0] + [t for _, t in refs] + [th11]
    return z, th


def fixture_refs(zs, zo):
    yo = 1 / (zo - zs)
    out = []
    for n in NOMINAL:
        zm = zs + n / (1 + n * yo)
        out.append((abs(zm) - abs(zs), deg(zm)))
    return out


def block_with_entry(z, th, base=None):
    """block_with() whose 15 user-table entries all hold the 12 |Z| words z and the 12 theta words th."""
    b = bytearray(base if base is not None else block_with())
    for fi in range(5):
        for li in range(3):
            off = 0x5A4 + 0x90 * fi + 0x30 * li
            for t in range(12):
                struct.pack_into('<f', b, off + 4 * t, z[t])
                struct.pack_into('<f', b, off + 0x2D0 + 4 * t, th[t])
    return bytes(b)


def fixture_block(t11=None, th11=None):
    refs = fixture_refs(ZS, ZO)
    z, th = entry_words(abs(ZS), deg(ZS), abs(ZO) - abs(ZS) if t11 is None else t11,
                        deg(ZO) if th11 is None else th11, refs)
    return block_with_entry(z, th)


def f32(x):
    return u32f(f2u(x))


def open_usable(z, th):
    t0, t11, th11 = abs(z[0]), z[11], th[11]
    if f2u(t11) == F_OPENDEF and f2u(th11) == 0:
        return None
    if f2u(t11) == F_1E10 or not math.isfinite(t11) or not math.isfinite(th11) or abs(th11) > 180:
        return None
    if t11 + t0 < 1e5:
        return None
    return (t11 + t0) * cis(th11)


def expect(zbar, z, th):
    """(|Z|c, theta) of the specification for one window, or None for the stage-1 fallback, or 'ovl'."""
    z = [f32(v) for v in z]
    th = [f32(v) for v in th]
    t0 = abs(z[0])
    zs = t0 * cis(th[0])
    zo = open_usable(z, th)
    yo = None if zo is None else 1 / (zo - zs)

    def comp(zm):
        d = zm - zs
        if yo is None:
            return d
        w = 1 - d * yo
        if abs(w) ** 2 < 1e-12:
            return 'ovl'
        return d / w
    bp = []
    for k in range(1, 11):
        c = comp((z[k] + t0) * cis(th[k]))
        if c == 'ovl':
            return None
        bp.append(abs(c))
        if len(bp) > 1 and bp[-1] <= bp[-2]:
            return None
    zd = comp(zbar)
    if zd == 'ovl':
        return 'ovl'
    return interp64([0.0] + bp + [0.0], abs(zd)), deg(zd)


def zbar_of(p):
    s = p['sum']
    return p['k'] * complex(s[0], s[1]) / complex(s[2], s[3])


def fixture_src(zd):
    """A DUT zd seen through the fixture: Zm = Zs + zd / (1 + zd Yo) (the inverse of comp)."""
    yo = 1 / (ZO - ZS)
    return DutSource(z=lambda f: ZS + zd / (1 + zd * yo))


def check_pubs(rig, z, th, what, n_min=3, since=1.0):
    """Every normal publish after `since` s matches expect() within the bounds of the module docstring."""
    pubs = rig.probe.normal(since)
    check(len(pubs) >= n_min, '%s: %d publishes' % (what, len(pubs)))
    for p in pubs:
        e = expect(zbar_of(p), z, th)
        check(e is not None and e != 'ovl', '%s: the specification gives %r' % (what, e))
        zc, tc = e
        gz, gt = u32f(p['Z']), u32f(p['TH'])
        check(abs(gz - zc) <= 1e-4 * abs(zc) and abs(gt - tc) <= 0.01, '%s: |Z| %.7g theta %.5f, expected %.7g / %.5f'
              % (what, gz, gt, zc, tc))
    return pubs


# ---------------------------------------------------------------- m40 / m44

@case
def m40_fixture_recovered():
    """m40 / m44: a DUT 1000 - j500 ohm (1 kHz, 0.6 V) through the fixture: every publish equals the
    specification's value from its own window; and Zdut is recovered: |Z| within 1e-3 and theta within 0.2
    degree of the true part (the emulator's own phase offset of about 0.12 degree on 1 kohm, NOTES
    "Measurement path in the emulator", is inside it). The factory table holds the defaults, so the match
    proves the user table was used (m44)."""
    zd = complex(1000.0, -500.0)
    blk = fixture_block()
    z, th = struct.unpack_from('<12f', blk, 0x5A4), struct.unpack_from('<12f', blk, 0x5A4 + 0x2D0)
    rig = own_rig(fixture_src(zd), block=blk)
    rig.run(5.0)
    pubs = check_pubs(rig, z, th, 'm40')
    last = pubs[-1]
    gz, gt = u32f(last['Z']), u32f(last['TH'])
    check(abs(gz - abs(zd)) <= 1e-3 * abs(zd) and abs(gt - deg(zd)) <= 0.2,
          'm40: recovered %.6g at %.4f, the part %.6g at %.4f' % (gz, gt, abs(zd), deg(zd)))
    rig.watch.check(what='m40')
    NOTES.append('m40: |Z| %.6g theta %.4f for %.6g at %.4f' % (gz, gt, abs(zd), deg(zd)))
    return True


# ---------------------------------------------------------------- m41 open unusable

@case
def m41_open_unusable_short_only():
    """m41: each of the four unusable opens (the default 1e12 at 0 degrees, the no-reading 1e10 / -400, "not
    resolved" +400, 50 kohm below 1e5) gives the short-only compensation Zdut = Zm - Zs with the breakpoints
    compensated the same way: every publish equals the specification's short-only value."""
    for what, t11, th11 in (('default', u32f(F_OPENDEF), 0.0), ('no reading', 1e10, -400.0),
                            ('not resolved', 2e6, 400.0), ('below 1e5', 5e4, -80.0)):
        blk = fixture_block(t11=t11, th11=th11)
        z, th = struct.unpack_from('<12f', blk, 0x5A4), struct.unpack_from('<12f', blk, 0x5A4 + 0x2D0)
        check(open_usable([f32(v) for v in z], [f32(v) for v in th]) is None, 'm41 %s: the open is usable' % what)
        rig = own_rig(DutSource('R', 1000.0), block=blk)
        rig.run(4.0)
        check_pubs(rig, z, th, 'm41 %s' % what)
        rig.watch.check(what='m41 %s' % what)
    return True


# ---------------------------------------------------------------- m42 (K)

@case
def m42_reference_reads_nominal():
    """m42 (S4.2 (K)): the 100 ohm reference N_5 through the fixture reads its nominal: |Z| within 1e-3 of 100
    ohm (b'_5 = 100 by construction, so the interpolation maps it onto the decade value 100)."""
    blk = fixture_block()
    rig = own_rig(fixture_src(complex(100.0, 0.0)), block=blk)
    rig.run(5.0)
    pubs = rig.probe.normal(1.0)
    check(len(pubs) >= 3, 'm42: %d publishes' % len(pubs))
    for p in pubs:
        check(abs(u32f(p['Z']) - 100.0) <= 0.1, 'm42: %.6g ohm' % u32f(p['Z']))
    rig.watch.check(what='m42')
    return True


# ---------------------------------------------------------------- m45 screen 3

@case
def m45_screen3_not_compensated():
    """m45 (S4.1 "screens 1 and 2 only"): on screen 3 the published |Z| is the raw |Zbar| (calibration type 0)
    and theta its uncompensated angle, the stage-1 values that fn_0800bb64 stores; the same window on screen
    1 would have published the compensated value, which differs."""
    # 20 kohm - j 10 kohm, not 1 kohm - j 500 ohm: through this fixture (Zs 0.2 ohm at 30 deg, Zo 2 Mohm
    # at -80 deg) the compensation of 1 kohm - j 500 ohm changes |Z| by 2.3e-4 and theta by 0.017 deg,
    # below this case's own "differs" limits (1e-3, 0.05 deg); 20 kohm - j 10 kohm changes them by
    # 6.7e-3 and 0.51 deg (float64, 2026-11-22)
    zd = complex(20000.0, -10000.0)
    blk = fixture_block()
    z, th = struct.unpack_from('<12f', blk, 0x5A4), struct.unpack_from('<12f', blk, 0x5A4 + 0x2D0)
    rig = own_rig(fixture_src(zd), block=blk)
    settings_item(rig, 0)
    t3 = rig.m.now()
    rig.run(5.0)
    pubs = [p for p in rig.probe.normal(t3 + 1.0) if p['screen'] == 3]
    check(len(pubs) >= 3, 'm45: %d publishes on screen 3' % len(pubs))
    for p in pubs:
        zb = zbar_of(p)
        gz, gt = u32f(p['Z']), u32f(p['TH'])
        check(abs(gz - abs(zb)) <= 1e-5 * abs(zb) and abs(gt - deg(zb)) <= 1e-3,
              'm45: %.7g / %.5f, raw %.7g / %.5f' % (gz, gt, abs(zb), deg(zb)))
        zc, tc = expect(zb, z, th)
        check(abs(zc - gz) > 1e-3 * gz or abs(tc - gt) > 0.05, 'm45: the compensation would not differ')
    rig.watch.check(what='m45')
    return True


# ---------------------------------------------------------------- m47 the guard

@case
def m47_guard_overload():
    """S4.1 guard: the window's Zbar set to Zo itself at the entry of meas_comp (s16 / s17), so 1 - (Zm - Zs)
    Yo is 0 within float32 rounding (|W| < 1e-6): the overload set is published, never Inf or NaN."""
    blk = fixture_block()
    rig = own_rig(DutSource('R', 1000.0), block=blk)
    zo = (f32(abs(ZO) - abs(ZS)) + f32(abs(ZS))) * cis(f32(deg(ZO)))
    hits = []

    def force(uc, a, size, u):
        uc.reg_write(UC_ARM_REG_S16, f2u(zo.real))
        uc.reg_write(UC_ARM_REG_S17, f2u(zo.imag))
        hits.append(rig.m.now())
    rig.m.uc.hook_add(UC_HOOK_CODE, force, begin=rig.s['meas_comp'] & ~1, end=rig.s['meas_comp'] & ~1)
    rig.run(4.0)
    pubs = [p for p in rig.probe.pubs if p['t'] > (hits[0] if hits else 1e9)]
    check(hits and pubs and all(is_set(p) for p in pubs), 'm47: %d forced, publishes %r' % (
        len(hits), [(hex(p['Z']), hex(p['TH'])) for p in pubs[:4]]))
    for p in pubs:
        M.no_nan(p, 'm47')
    rig.watch.check(what='m47')
    return True


# ---------------------------------------------------------------- m46 S4.4 bias transient

class MidDut(TDut):
    """TDut whose ADC1 / ADC2 midpoints move by mid(t) counts (a DC transient after a bias change)."""

    def __init__(self, zt, mid, **kw):
        super().__init__(zt, **kw)
        self.mid = mid

    def samples(self, path, adc, channel, times):
        out = super().samples(path, adc, channel, times)
        if adc not in (1, 2) or isinstance(out, int):
            return out
        return [max(0, min(4095, int(round(v + self.mid(t))))) for v, t in zip(out, times)]


@case
def m46_bias_transient():
    """S4.4: after a bias change (0x2000113C 0 -> 0.5 written at t_b) the DC midpoints decay by 150 e^(-(t -
    t_b) / tau) counts (150 keeps a 3600 p-p signal off the rails). tau = 1 s: no publish until the
    midpoints at two consecutive window closes differ by
    at most 4 counts on both channels, then publishing resumes. A midpoint that never becomes steady (a
    sawtooth of 40 counts per s, period 1.37 s, 0..54.8 counts): the first publish comes at the 30-s bound
    (within one window). Before the change publishes come at the window rate.
    The second source was an exponential with tau = 1000 s, which moves 150 / 1000 = 0.15 counts per s,
    well below 4 counts between two closes: steady at once (2026-11-22: first publish 1.044 s after the
    change); the sawtooth moves 20 counts per 0.5 s and jumps back at its period."""
    for tau, what in ((1.0, 'tau 1 s'), (1000.0, 'never steady')):
        tb = {'t': None}

        def mid(t, tau=tau):
            a = tb['t']
            if a is None or t < a:
                return 0.0
            if tau > 10:
                return 40.0 * ((t - a) % 1.37)
            return 150.0 * math.exp(-(t - a) / tau)
        rig = own_rig(MidDut(lambda f, t: complex(1000.0, 0.0), mid))
        closes = []

        def at_wait(uc, a, size, u):
            closes.append((rig.m.now(), rig.rd16(V_MID_V), rig.rd16(V_MID_I), rig.rd(OWN_FUNC + MF_BIASP)))
        rig.m.uc.hook_add(UC_HOOK_CODE, at_wait, begin=rig.s['meas_bias_wait'] & ~1, end=rig.s['meas_bias_wait'] & ~1)
        rig.run(3.0)
        check(len(rig.probe.normal(1.0)) >= 2, '%s: no publishes before the change' % what)
        tb['t'] = rig.m.now()
        rig.wr(V_BIAS, 0x3F000000)
        rig.run(40.0 if tau > 10 else 12.0)
        t_b = tb['t']
        after = [p for p in rig.probe.pubs if p['t'] > t_b]
        check(after, '%s: no publish after the change' % what)
        t_first = after[0]['t']
        cl = [c for c in closes if c[0] > t_b]
        first_close = [i for i, c in enumerate(cl) if c[0] <= t_first]
        check(first_close, '%s: no window close before the first publish' % what)
        i = first_close[-1]
        if tau < 10:
            check(i >= 1 and abs(cl[i][1] - cl[i - 1][1]) <= 4 and abs(cl[i][2] - cl[i - 1][2]) <= 4,
                  '%s: the first publish at a close that is not steady %r' % (what, cl[max(0, i - 1):i + 1]))
            for j in range(1, i):
                check(abs(cl[j][1] - cl[j - 1][1]) > 4 or abs(cl[j][2] - cl[j - 1][2]) > 4,
                      '%s: a steady close at %.3f was not published' % (what, cl[j][0]))
            check(t_first - t_b > 2.0, '%s: published %.3f s after the change' % (what, t_first - t_b))
        else:
            check(30.0 <= t_first - t_b <= 32.0, '%s: the first publish %.3f s after the change' % (what, t_first - t_b))
        NOTES.append('m46 %s: first publish %.2f s after the change, %d closes waited' % (what, t_first - t_b, i))
        rig.watch.check(what='m46 %s' % what)
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
