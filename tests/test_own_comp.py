#!/usr/bin/env python3
"""test_own_comp.py - stage 4 of our build's measurement core (firmware/own/meas.s meas_comp, meas_cz,
meas_bias_wait; S4.1 with S4.2 option (K), S4.4; the cases m40..m45 and the
cases revision 7 adds), in the emulator.

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
RUN LIMIT: one run of this file per case prefix, 8 cases.
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
    degree of the true part (the emulator's own phase offset of about 0.12 degree on 1 kohm,
    is inside it). The factory table holds the defaults, so the match
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
    (within one window); the case checks first that its midpoints at every pair of consecutive closes up to
    that publish differ by more than 4 counts on at least one channel (never steady by the firmware's own
    rule). Before the change publishes come at the window rate.
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
            # the input's property, by the firmware's criterion (meas_bias_wait: steady when both midpoints
            # at a close differ from those at the close before by at most BIAS_LIM = 4 counts): every
            # close up to the first publish is inside the wait (MF_BIASP != 0 at its entry), and every
            # consecutive pair of them differs by more than 4 counts on at least one channel
            check(i >= 1 and all(c[3] != 0 for c in cl[:i + 1]),
                  '%s: closes outside the wait before the first publish %r' % (what, cl[:i + 1]))
            for j in range(1, i + 1):
                check(abs(cl[j][1] - cl[j - 1][1]) > 4 or abs(cl[j][2] - cl[j - 1][2]) > 4,
                      '%s: the source was steady between the closes at %.3f and %.3f s: %r'
                      % (what, cl[j - 1][0], cl[j][0], cl[j - 1:j + 1]))
            check(30.0 <= t_first - t_b <= 32.0, '%s: the first publish %.3f s after the change' % (what, t_first - t_b))
        NOTES.append('m46 %s: first publish %.2f s after the change, %d closes waited' % (what, t_first - t_b, i))
        rig.watch.check(what='m46 %s' % what)
    return True

# ---------------------------------------------------------------- m48 the sign of |Z| (revision 10 item 5)

@case
def m48_magnitude_never_negative():
    """Revision 10 item 5 (the meter, 2026-11-23: MEASURE |Z| -8.86881e-05 ohm, theta 105.42 deg, shorted leads
    before the short calibration): the stage-1 chain on screen 1 (every entry's short phase -400, so meas_comp
    returns 0) with a short entry of 0.5 ohm, the references b_k at their nominal values and a part of 0.32 + j
    0.24 ohm (0.4 ohm at 36.87 degrees, so arg Zbar is far from 0 and theta -+ 180 is one-sided).
    The part is not smaller: the model's source is ideal (DutSource: the DUT gets the whole generator
    voltage), so with K_SHORT = 7 counts per volt the current channel at its lowest gain and range (c6 0, c8
    0, 100 ohm) has p-p 1186 / |Z| counts (V p-p 1518 at c5 7 = 128 x 11.86, the trace of 2026-11-23: V
    1289..2807; I = V x 100 / |Z|): 0.25 ohm gives 4744, clipped to 0..4095 at every acquisition, so after
    the overload set (S1.5, published once) nothing is published, as designed; 0.4 ohm gives 2965 (traced:
    I 566..3530), inside the band 1500..3600, so the codes hold at c5 7 / c6 0 / c8 0.
    Input checks: |Zdut| below the short entry; every acquisition the window saw after 1 s unsaturated by
    the firmware's criterion (ocal_clip with the default limits: a code 0 or 4095 is saturation) on both
    channels; no overload / no-reading set after 1 s; per window |Zbar| - t0 < 0 (the chain's value below
    0). Expected per publish: |Z| >= 0, |Z| =
    |d| with d = the decade interpolation of |Zbar| - t0 (below b1: d / b1 * 0.01), theta = arg Zbar - 180
    for arg Zbar > 0, else + 180; Rs = d cos(arg Zbar), Xs = d sin(arg Zbar) (the chain's complex value,
    unchanged); bounds of the module docstring (1e-4 relative, 0.01 degree)."""
    z = [0.5] + NOMINAL + [u32f(F_OPENDEF)]
    th = [-400.0] + [0.0] * 10 + [0.0]
    blk = block_with_entry(z, th)
    zdut = complex(0.32, 0.24)
    check(abs(zdut) < 0.5, 'm48: the part %.6g is not below the short entry (input)' % abs(zdut))
    rig = own_rig(DutSource(z=lambda f: zdut, counts_per_volt=M.K_SHORT), block=blk)
    rig.run(4.0)
    acqs = [a for a in rig.probe.acqs if a['t'] > 1.0]
    check(acqs and all(0 < min(a[c]) and max(a[c]) < 4095 for a in acqs for c in ('v', 'i')),
          'm48: %d acquisitions after 1 s, a saturated one among them (input)' % len(acqs))
    sets = [p['t'] for p in rig.probe.pubs if p['t'] > 1.0 and is_set(p)]
    check(not sets, 'm48: the overload / no-reading set at %r' % sets)
    pubs = rig.probe.normal(1.0)
    check(len(pubs) >= 3, 'm48: %d publishes' % len(pubs))
    ent = [0.0] + [f32(v) for v in NOMINAL] + [0.0]
    for p in pubs:
        zb = zbar_of(p)
        d0 = abs(zb) - f32(0.5)
        check(d0 < 0, 'm48: |Zbar| %.6g is not below the short entry (input)' % abs(zb))
        d = interp64(ent, d0)
        a = deg(zb)
        t_exp = a - 180.0 if a > 0 else a + 180.0
        gz, gt, rs, xs = (u32f(p[k]) for k in ('Z', 'TH', 'RS', 'XS'))
        check(gz >= 0 and abs(gz - abs(d)) <= 1e-4 * abs(d) and abs(gt - t_exp) <= 0.01,
              'm48: |Z| %.7g theta %.5f, expected %.7g / %.5f' % (gz, gt, abs(d), t_exp))
        check(abs(rs - d * math.cos(math.radians(a))) <= 1e-4 * abs(d)
              and abs(xs - d * math.sin(math.radians(a))) <= 1e-4 * abs(d),
              'm48: Rs %.7g Xs %.7g, expected %.7g / %.7g' % (rs, xs, d * math.cos(math.radians(a)),
                                                            d * math.sin(math.radians(a))))
    rig.watch.check(what='m48')
    NOTES.append('m48: %d publishes, the last |Z| %.6g theta %.3f' % (len(pubs), u32f(pubs[-1]['Z']),
                                                                      u32f(pubs[-1]['TH'])))
    return True


# ---------------------------------------------------------------- m49 60 Hz and the 100 Hz entry

def open_at(blk, fis, t11, th11):
    """blk with the open words (type 11, |Z| and theta) of the entries of the frequency indices fis replaced."""
    b = bytearray(blk)
    for fi in fis:
        for li in range(3):
            off = 0x5A4 + 0x90 * fi + 0x30 * li + 4 * 11
            struct.pack_into('<f', b, off, t11)
            struct.pack_into('<f', b, off + 0x2D0, th11)
    return bytes(b)


@case
def m49_sixty_hertz_takes_the_100_hz_entry():
    """S2.12 with revision 11 (an open point stored "not resolved", 1e10 / +400): at 60 Hz
    (LCR_SET frequency index 5) meas_comp reads the 100 Hz entry of the level. (a) the 100 Hz entries (fi 0,
    three levels) hold the fixture, the other twelve the fixture with the open "not resolved": every publish at
    60 Hz equals the specification with the 100 Hz entry, and the DUT 10000 - j5000 ohm is recovered within 1e-3
    and 0.2 degree (m40's bounds); (b) the 100 Hz entries "not resolved", the other twelve the fixture: every
    publish equals the short-only specification of the 100 Hz entry (check_pubs, 1e-4); input check per
    publish: expect() of the same window with the 100 Hz entry of (a) (the open used) differs from it by more
    than 2e-4, twice that bound, so the match tells the two apart (2026-11-23: the first version compared with
    the DUT, by a value without the decade interpolation; the firmware's short-only value lay 1.2e-4 from
    the DUT). Input check: open_usable of the two entries differs."""
    zd = complex(10000.0, -5000.0)                    # 10x m40: the open moves |Z| by about 1.5e-3
    full = fixture_block()
    z100o = struct.unpack_from('<12f', full, 0x5A4)
    th100o = struct.unpack_from('<12f', full, 0x5A4 + 0x2D0)
    for what, blk in (('a', open_at(full, (1, 2, 3, 4), 1e10, 400.0)), ('b', open_at(full, (0,), 1e10, 400.0))):
        z100 = struct.unpack_from('<12f', blk, 0x5A4)
        th100 = struct.unpack_from('<12f', blk, 0x5A4 + 0x2D0)
        z1k = struct.unpack_from('<12f', blk, 0x5A4 + 0x90 * 2)
        th1k = struct.unpack_from('<12f', blk, 0x5A4 + 0x90 * 2 + 0x2D0)
        u100 = open_usable([f32(v) for v in z100], [f32(v) for v in th100]) is not None
        u1k = open_usable([f32(v) for v in z1k], [f32(v) for v in th1k]) is not None
        check(u100 != u1k and u100 == (what == 'a'), 'm49 %s: open usable at 100 Hz %r, 1 kHz %r (input)' % (
            what, u100, u1k))
        rig = own_rig(fixture_src(zd), block=blk, usb=True)
        rig.ask_ok('LCR_SET', bytes([2, 5]))
        check(rig.rd(M.V_FREQ) == 60, 'm49 %s: frequency %d' % (what, rig.rd(M.V_FREQ)))
        t0 = rig.m.now()
        rig.run(4.0)
        pubs = check_pubs(rig, z100, th100, 'm49 %s' % what, since=t0 + 1.5)
        gz = u32f(pubs[-1]['Z'])
        gt = u32f(pubs[-1]['TH'])
        if what == 'a':
            check(abs(gz - abs(zd)) <= 1e-3 * abs(zd) and abs(gt - deg(zd)) <= 0.2,
                  'm49 a: %.6g at %.4f, the DUT %.6g at %.4f' % (gz, gt, abs(zd), deg(zd)))
        else:
            for p in pubs:
                e = expect(zbar_of(p), z100o, th100o)
                check(e is not None and e != 'ovl' and abs(e[0] - u32f(p['Z'])) > 2e-4 * abs(e[0]),
                      'm49 b: the value with the open %r is within 2e-4 of the publish %.7g (input)' % (
                          e, u32f(p['Z'])))
        rig.watch.check(what='m49 %s' % what)
        NOTES.append('m49 %s: %d publishes at 60 Hz, the last |Z| %.7g theta %.4f' % (what, len(pubs), gz, gt))
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
