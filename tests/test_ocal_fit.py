#!/usr/bin/env python3
"""test_ocal_fit.py - tools/ocal_fit.py, the host-side gain fit of the own calibration area,
on synthetic data.

Usage (from the repository root):
    python3 -I tests/test_ocal_fit.py          (standard library only; no meter, no emulator)

Test data: one generator, synth(), builds the windows of a run from injected factors. Per window the
nominal-K quotient is Znom = Zx / (zeta[c8][c6] * nu[c5]) times exp(n_mag + j n_pha), n_mag and n_pha
drawn from rng = random.Random(1) (created once below) with the standard deviation SD that the fit's
own window weight gives: A_V = A_I = 2000 counts, sigma2 = 1 count^2 for both channels, so
var = 1/2000^2 + 1/2000^2 = 5e-7 and SD = 7.07e-4 (the formula of the ocal_fit.py docstring).
The default plan is the grid c8 0..3 x c6 0..3 x c5 0..3 for each of four resistors (100 ohm, 1 kohm,
10 kohm, 100 kohm; relative uncertainty 1e-3) at three levels, 768 windows at fi 2 (1 kHz). Every
zeta and nu is injected as 1 + u(-0.03, 0.03) in magnitude and u(-0.03, 0.03) rad in phase, nu[0] = 1
(the gauge of a balanced plan is the lowest c5, c5 = 0).

Tolerances. Each (c8, c6) zeta is seen in 4 c5 x 4 resistors x 3 levels = 48 windows and each cell
(c8, c6, c5) in 12, so the standard deviation of any fitted log factor or product is at most
SD / sqrt(12) = 2.0e-4 (a cell mean with the resistor values known is an unbiased estimator of
that variance; the fit uses all windows and the anchors, so it is not worse). The tolerance TOL = 2e-3
is ten of these standard deviations, for the magnitude (ln ratio) and for the phase (radians) of every
one of the 64 cells and 32 factors.
"""
import cmath
import contextlib
import io
import json
import math
import os
import random
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import ocal_fit as of

rng = random.Random(1)
AV = AI = 2000.0
S2 = 1.0
SD = math.sqrt(S2 / AV ** 2 + S2 / AI ** 2)
TOL = 2e-3


def err(a, b):
    """Largest of |ln |a/b|| and |arg(a/b)| (radians)."""
    q = a / b
    return max(abs(math.log(abs(q))), abs(cmath.phase(q)))


def draw_truth(c8s, c6s, c5s, nu0_one=True):
    """Injected factors: dicts zeta[(c8, c6)], nu[c5]."""
    zeta = {(c8, c6): cmath.rect(1 + rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03))
            for c8 in c8s for c6 in c6s}
    nu = {c5: cmath.rect(1 + rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03)) for c5 in c5s}
    if nu0_one:
        nu[0] = complex(1.0, 0.0)
    return zeta, nu


def mkwin(fi, lv, c8, c6, c5, z, target, auto=False, ins=0):
    """One window dict of the run file schema."""
    return {'fi': fi, 'level': lv, 'c5': c5, 'c6': c6, 'c8': c8, 'znom_re': z.real, 'znom_im': z.imag,
            'a_v': AV, 'a_i': AI, 'sigma2_v': S2, 'sigma2_i': S2, 'autoranged': auto,
            'target': target, 'insertion': ins}


def noisy(z):
    """z times exp(n_mag + j n_pha) with the standard deviation SD on both."""
    return z * cmath.exp(complex(rng.gauss(0.0, SD), rng.gauss(0.0, SD)))


def synth(fi=2, rvals=(100.0, 1000.0, 10000.0, 100000.0), c8s=range(4), c6s=range(4), c5s=range(4),
          levels=3, unc=1e-3, zeta=None, nu=None, nu0_one=True, auto=((1, 1, 1),), zx=None,
          level_fn=None, extra_c5=(), zeta_over=None):
    """A run dict from injected factors (returned with them as run['_zeta'], run['_nu'] removed by
    the caller before json). zx(R) = the terminal impedance of the resistor R (default R), level_fn(
    level, c8, c6, c5) a multiplicative level-dependent factor on Znom, extra_c5 repeats the windows
    of those c5 once more (moves the gauge)."""
    if zeta is None or nu is None:
        zeta, nu = draw_truth(c8s, c6s, c5s, nu0_one)
    if zeta_over:
        zeta = dict(zeta)
        zeta.update(zeta_over)
    resistors = {'R%g' % r: {'value': r, 'uncertainty': unc} for r in rvals}
    wins = []
    for r in rvals:
        zxr = zx(r) if zx else complex(r, 0.0)
        for lv in range(levels):
            for c8 in c8s:
                for c6 in c6s:
                    for c5 in c5s:
                        for rep in range(2 if c5 in extra_c5 else 1):
                            z = zxr / (zeta[(c8, c6)] * nu[c5])
                            if level_fn:
                                z *= level_fn(lv, c8, c6, c5)
                            wins.append(mkwin(fi, lv, c8, c6, c5, noisy(z), 'R%g' % r,
                                              auto=(c8, c6, c5) in auto))
    return {'resistors': resistors, 'windows': wins, '_zeta': zeta, '_nu': nu}


def fit(run):
    """fit_run on the run without the private truth keys."""
    r = {k: v for k, v in run.items() if not k.startswith('_')}
    return of.fit_run(r)


class WlsTest(unittest.TestCase):
    def test_exact_line_and_rank(self):
        # y = 2 + 3 t at four points: unique solution, both unknowns identified
        rows = [([(0, 1.0), (1, float(t))], 2.0 + 3.0 * t, 4.0) for t in range(4)]
        s = of.wls(rows, 2)
        self.assertEqual(s.rank, 2)
        self.assertAlmostEqual(s.x[0], 2.0, places=9)
        self.assertAlmostEqual(s.x[1], 3.0, places=9)
        self.assertEqual(s.ident, [True, True])
        self.assertAlmostEqual(sum(s.h), 2.0, places=9)        # trace of the hat matrix = rank

    def test_rank_deficient(self):
        # x0 - x1 = 1 twice and an unused x2: rank 1, nothing identified
        rows = [([(0, 1.0), (1, -1.0)], 1.0, 1.0), ([(0, 1.0), (1, -1.0)], 1.0, 1.0)]
        s = of.wls(rows, 3)
        self.assertEqual(s.rank, 1)
        self.assertEqual(s.ident, [False, False, False])
        self.assertAlmostEqual(s.x[0] - s.x[1], 1.0, places=9)

    def test_no_numpy(self):
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools', 'ocal_fit.py')) as fh:
            self.assertNotIn('import numpy', fh.read())


class FitTest(unittest.TestCase):
    def test_recovery(self):
        run = synth()
        f = fit(run).fits[2]
        self.assertTrue(f.ok, f.reasons)
        zm = sum(1 << (8 * c8 + c6) for c8 in range(4) for c6 in range(4))
        o = f.out
        self.assertEqual((o.zmag, o.zpha, o.nmag, o.npha), (zm, zm, 0xF, 0xF))
        zt, nt = run['_zeta'], run['_nu']
        for c8 in range(4):
            for c6 in range(4):
                self.assertLess(err(o.zeta[8 * c8 + c6], zt[(c8, c6)]), TOL)
                for c5 in range(4):
                    self.assertLess(err(o.zeta[8 * c8 + c6] * o.nu[c5], zt[(c8, c6)] * nt[c5]), TOL)
        for c5 in range(4):
            self.assertLess(err(o.nu[c5], nt[c5]), TOL)
        self.assertEqual(o.nu[0], complex(1.0, 0.0))

    def test_gauge(self):
        # c5 = 2 has twice the windows, so it is the gauge: nu[2] = 1 exactly, the others relative to it
        run = synth(nu0_one=False, extra_c5=(2,))
        f = fit(run).fits[2]
        self.assertTrue(f.ok, f.reasons)
        zt, nt = run['_zeta'], run['_nu']
        o = f.out
        self.assertEqual(o.nu[2], complex(1.0, 0.0))
        self.assertTrue((o.nmag >> 2) & 1 and (o.npha >> 2) & 1)
        for c5 in range(4):
            self.assertLess(err(o.nu[c5], nt[c5] / nt[2]), TOL)
        for c8 in range(4):
            for c6 in range(4):
                self.assertLess(err(o.zeta[8 * c8 + c6], zt[(c8, c6)] * nt[2]), TOL)

    def test_magnitude_bits_without_phase_anchor(self):
        # one 100 kohm resistor at 1 kHz: a magnitude anchor (up to 100 kohm) but no phase anchor
        # (up to 10 kohm), so zeta phase cannot be identified; nu phase can (differences at one zeta)
        f = fit(synth(rvals=(100000.0,))).fits[2]
        zm = sum(1 << (8 * c8 + c6) for c8 in range(4) for c6 in range(4))
        self.assertEqual((f.raw.zmag, f.raw.zpha, f.raw.nmag, f.raw.npha), (zm, 0, 0xF, 0xF))
        self.assertFalse(f.ok)
        self.assertTrue(any('zeta phase' in r for r in f.reasons), f.reasons)
        self.assertEqual((f.out.zmag, f.out.zpha, f.out.nmag, f.out.npha), (0, 0, 0, 0))

    def test_all_or_nothing_names_the_cell(self):
        run = synth()
        # a 1 Mohm part seen once at a cell nobody else reaches (c8 3, c6 5, c5 6): no anchor, three
        # unknowns in one row, so none of them is identified; the meter's autoranging chose that cell
        run['resistors']['Rodd'] = {'value': 1e6, 'uncertainty': 1e-3}
        run['windows'].append(mkwin(2, 0, 3, 5, 6, noisy(complex(1e6, 0.0)), 'Rodd', auto=True))
        r = fit(run)
        f = r.fits[2]
        self.assertFalse(f.ok)
        self.assertEqual((f.out.zmag, f.out.zpha, f.out.nmag, f.out.npha), (0, 0, 0, 0))
        self.assertEqual([c['cell'] for c in f.bad_cells], [[3, 5, 6]])
        self.assertEqual(len(f.bad_cells[0]['missing']), 4)
        self.assertTrue(any('c8=3 c6=5 c5=6' in x for x in f.reasons), f.reasons)
        self.assertTrue(f.raw.zmag & (1 << 9))                      # the rest was identified, just not written
        self.assertFalse(f.raw.zmag & (1 << (8 * 3 + 5)))
        sec = of.gain_section(r.fits)
        self.assertEqual(struct.unpack_from('<IIBBH', sec, 4 + 2 * 332), (0, 0, 0, 0, 0))

    def test_level_residual_blocks_the_frequency(self):
        # level 1 alone has a c6-dependent factor (up to 3 %): a separable zeta cannot absorb it for
        # one level of three, the level-1 residual is about 0.0126 against SD = 7e-4 (ratio ~ 18)
        run = synth(level_fn=lambda lv, c8, c6, c5: 1.0 / (1.0 + 0.01 * c6) if lv == 1 else 1.0)
        f = fit(run).fits[2]
        self.assertFalse(f.ok)
        self.assertGreater(f.resid['mag']['levels'][1], of.RESID_K)
        self.assertTrue(any('at level 1' in r for r in f.reasons), f.reasons)
        self.assertEqual((f.out.zmag, f.out.zpha, f.out.nmag, f.out.npha), (0, 0, 0, 0))

    def test_short_open_referral_and_refit(self):
        # 100 kHz, terminals with Zs = 0.2 ohm + 20 nH and Yo = j w 50 pF; the short and open are taken
        # at the cell (0, 1, 1) whose injected product zeta * nu is about 1.2 at 8.6 degrees; the
        # anchors are Z_anchor = Zs + 1 / (1 / R + Yo). Read as they are the open's admittance is wrong
        # by about 25 %, which moves the 10 kohm anchor by about 4 %; referred by the first fit's factor
        # the error is the first fit's error times the sensitivity of the anchors (about 0.03).
        w = 2 * math.pi * 1e5
        zs = complex(0.2, w * 20e-9)
        yo = complex(0.0, w * 50e-12)
        zeta, nu = draw_truth(range(4), range(4), range(4))
        zeta[(0, 1)] = cmath.rect(1.2, 0.15)
        run = synth(fi=4, rvals=(100.0, 1000.0, 10000.0), zeta=zeta, nu=nu,
                    zx=lambda r: zs + 1.0 / (1.0 / r + yo))
        p = zeta[(0, 1)] * nu[1]
        for lv in range(3):
            for k in range(4):
                run['windows'].append(mkwin(4, lv, 0, 1, 1, noisy(zs / p), 'short', ins=k % 2))
                run['windows'].append(mkwin(4, lv, 0, 1, 1, noisy(1.0 / (yo * p)), 'open'))
        f = fit(run).fits[4]
        self.assertTrue(f.ok, f.reasons)
        self.assertFalse([a for c in of.COMPS for a in f.anchors[c] if a['dropped']])

        def worst(fac):
            e = 0.0
            for c8 in range(4):
                for c6 in range(4):
                    for c5 in range(4):
                        pr = fac.product(c8, c6, c5)
                        self.assertIsNotNone(pr)
                        e = max(e, err(pr, zeta[(c8, c6)] * nu[c5]))
            return e
        e1, e2 = worst(f.pass1), worst(f.raw)
        self.assertGreater(e1, 4e-3)
        self.assertLess(e2, 1.5e-3)
        self.assertLess(3 * e2, e1)
        self.assertAlmostEqual(f.terminal['yo'][1], yo.imag, delta=0.05 * yo.imag)

    def test_bound_violation_clears_the_bits(self):
        # zeta (3, 3) injected as 3.0: |m|^2 = 9 > 4; it is no autoranged cell, so the frequency keeps
        # its other bits and only the bits of that factor are cleared
        run = synth(zeta_over={(3, 3): complex(3.0, 0.0)})
        f = fit(run).fits[2]
        self.assertTrue(f.ok, f.reasons)
        i = 8 * 3 + 3
        self.assertTrue((f.raw.zmag >> i) & 1 and (f.raw.zpha >> i) & 1)
        self.assertLess(abs(f.raw.zeta[i] / 3.0 - 1.0), TOL)
        self.assertFalse((f.out.zmag >> i) & 1)
        self.assertFalse((f.out.zpha >> i) & 1)
        self.assertEqual(f.out.zeta[i], complex(1.0, 0.0))
        self.assertEqual([(v['kind'], v['index']) for v in f.violations], [('zeta', i)])
        self.assertEqual(f.out.zmag, f.raw.zmag & ~(1 << i))

    def test_bounds_function(self):
        self.assertTrue(of.factor_in_bounds(1.0, 0.0))
        self.assertTrue(of.factor_in_bounds(0.6, 1.0))        # re^2 + im^2 = 1.36, 4 re^2 = 1.44
        self.assertFalse(of.factor_in_bounds(0.5, 1.0))       # 4 re^2 = 1 < 1.25 (angle beyond 60 degrees)
        self.assertFalse(of.factor_in_bounds(0.1, 0.1))       # below 0.25
        self.assertFalse(of.factor_in_bounds(2.5, 0.0))       # above 4
        self.assertFalse(of.factor_in_bounds(-1.0, 0.0))      # re <= 0
        self.assertFalse(of.factor_in_bounds(float('nan'), 0.0))
        self.assertFalse(of.factor_in_bounds(float('inf'), 0.0))
        self.assertTrue(of.factor_in_bounds(0.5, 0.0))        # exactly 0.25
        self.assertTrue(of.factor_in_bounds(2.0, 0.0))        # exactly 4


def sample_factors():
    """Factors with a few set bits for the layout tests."""
    f = of.Factors()
    f.zeta[11] = complex(1.25, 0.1)
    f.zmag = f.zpha = 1 << 11
    f.zeta[5] = complex(2.0, 0.0)               # no bit: must be written (1, 0)
    f.nu[4] = complex(0.9, -0.05)
    f.nmag = f.npha = 1 << 4
    f.nu[6] = complex(1.5, 0.0)                 # no bit
    return f


class LayoutTest(unittest.TestCase):
    def test_gain_section_layout(self):
        ff = of.FreqFit(2)
        ff.out = sample_factors()
        sec = of.gain_section({2: ff})
        self.assertEqual(len(sec), 1992 + 4)
        self.assertEqual(struct.unpack_from('<HH', sec, 0), (1, 1992))
        base = 4 + 2 * 332
        self.assertEqual(struct.unpack_from('<IIBBH', sec, base), (1 << 11, 1 << 11, 1 << 4, 1 << 4, 0))
        self.assertEqual(sec[base + 12 + 8 * 11:base + 12 + 8 * 12], struct.pack('<ff', 1.25, 0.1))
        self.assertEqual(sec[base + 12 + 8 * 5:base + 12 + 8 * 6], struct.pack('<ff', 1.0, 0.0))
        self.assertEqual(sec[base + 12 + 256 + 8 * 4:base + 12 + 256 + 8 * 5], struct.pack('<ff', 0.9, -0.05))
        self.assertEqual(sec[base + 12 + 256 + 8 * 6:base + 12 + 256 + 8 * 7], struct.pack('<ff', 1.0, 0.0))
        for fi in (0, 1, 3, 4, 5):                         # frequencies without a fit: masks 0, all (1, 0)
            b = 4 + fi * 332
            self.assertEqual(struct.unpack_from('<IIBBH', sec, b), (0, 0, 0, 0, 0))
            self.assertEqual(sec[b + 12:b + 332], struct.pack('<ff', 1.0, 0.0) * 40)
        of.validate_gain_section(sec)

    def test_build_body(self):
        ff = of.FreqFit(2)
        ff.out = sample_factors()
        sec = of.gain_section({2: ff})
        clip = [[(0, 4095)] * 8, [(10, 4000)] * 8]
        settle = [[26] * 6 for _ in range(7)]
        mon = (0x3F, [0.01, 0.02, 0.03, 0.04, 0.05, 0.06])
        body = of.build_body(gain=sec, meta=(1700000000, 'unit test'), clip=clip, settle=settle,
                             monitor=mon, bias=100)
        self.assertEqual(len(body), 36 + 1996 + 68 + 88 + 32 + 8)
        ids, lens, pos = [], [], 0
        while pos < len(body):
            sid, ln = struct.unpack_from('<HH', body, pos)
            ids.append(sid)
            lens.append(ln)
            if sid == 0:
                self.assertEqual(struct.unpack_from('<I', body, pos + 4)[0], 1700000000)
                self.assertEqual(body[pos + 8:pos + 8 + 28], b'unit test' + b'\0' * 19)
            if sid == 2:
                self.assertEqual(struct.unpack_from('<HH', body, pos + 4), (0, 4095))
                self.assertEqual(struct.unpack_from('<HH', body, pos + 4 + 32), (10, 4000))
            if sid == 4:
                self.assertEqual(struct.unpack_from('<I', body, pos + 4)[0], 0x3F)
            if sid == 5:
                self.assertEqual(struct.unpack_from('<HH', body, pos + 4), (100, 0))
            pos += 4 + ln
        self.assertEqual(pos, len(body))
        self.assertEqual(ids, [0, 1, 2, 3, 4, 5])
        self.assertEqual(lens, [32, 1992, 64, 84, 28, 4])
        self.assertEqual(of.build_body(), b'')
        self.assertEqual(of.build_body(bias=7), struct.pack('<HHHH', 5, 4, 7, 0))

    def test_build_body_refuses_what_2_4_refuses(self):
        ok_clip = [[(0, 4095)] * 8] * 2
        with self.assertRaises(ValueError):
            of.build_body(clip=[[(0, 3000)] * 8] * 2)
        with self.assertRaises(ValueError):
            of.build_body(settle=[[0] * 6 for _ in range(7)])
        with self.assertRaises(ValueError):
            of.build_body(monitor=(1, [2.0] * 6))
        with self.assertRaises(ValueError):
            of.build_body(monitor=(0x40, [0.1] * 6))
        with self.assertRaises(ValueError):
            of.build_body(bias=0)
        with self.assertRaises(ValueError):
            of.build_body(meta=(0, 'x' * 29))
        of.build_body(clip=ok_clip)
        sec = bytearray(of.gain_section({}))
        struct.pack_into('<I', sec, 4, 1)                   # fi 0 zeta magnitude bit 0 set ...
        struct.pack_into('<ff', sec, 4 + 12, 3.0, 0.0)      # ... on a factor of 3.0
        with self.assertRaises(ValueError):
            of.build_body(gain=bytes(sec))

    def test_command_line(self):
        run = synth()
        run = {k: v for k, v in run.items() if not k.startswith('_')}
        run['meta'] = {'time': 1700000000, 'note': 'cli'}
        run['sections'] = {'bias': 100}
        d = tempfile.mkdtemp(prefix='ocal_fit_')
        rf, bf, jf = [os.path.join(d, n) for n in ('run.json', 'body.bin', 'report.json')]
        with open(rf, 'w') as fh:
            json.dump(run, fh)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(of.main([rf, '-o', bf, '--report', jf]), 0)
        with open(bf, 'rb') as fh:
            body = fh.read()
        self.assertEqual(len(body), 36 + 1996 + 8)
        zm = sum(1 << (8 * c8 + c6) for c8 in range(4) for c6 in range(4))
        self.assertEqual(struct.unpack_from('<IIBBH', body, 36 + 4 + 2 * 332), (zm, zm, 0xF, 0xF, 0))
        with open(jf) as fh:
            rep = json.load(fh)
        self.assertTrue(rep['2']['ok'])
        self.assertIn('GAIN written', out.getvalue())


if __name__ == '__main__':
    unittest.main()
