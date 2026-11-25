#!/usr/bin/env python3
"""ocal_fit.py - host-side gain fit of the own calibration area (the GAIN section
body) and the body builder for the OCAL_WRITE record.

Usage:
    python3 -I tools/ocal_fit.py RUNFILE [-o BODY] [--report FILE]

Python 3 standard library only (the repository uses no numpy: nothing in tools/ or tests/ imports it).
RUNFILE is read, the fit is done per frequency, the text report goes to standard output, BODY (-o)
receives the record body (sections META 0 .. BIAS 5, each {id u16, length u16} + body, ascending ids)
and FILE (--report) receives the report: JSON when its name ends in .json, else the text.

RUNFILE (JSON object):
    "resistors": {NAME: {"value": ohms, "uncertainty": relative 1-sigma of the DMM value}, ...}
        NAME is any string except "short" and "open"; value > 0, uncertainty > 0.
    "windows": [ one object per closed window:
        "fi"       frequency index 0..5 = 100, 120, 1000, 10000, 100000, 60 Hz
        "level"    excitation level index (integer >= 0; 0..2 on the meter)
        "c5","c6","c8"  gain codes: c5 V-gain 0..7, c6 I-gain 0..7, c8 range resistor 0..3
        "znom_re","znom_im"  the nominal-K quotient Z of the window (meter record, K = R[c8]*G[c6]/G[c5])
        "a_v","a_i"          amplitudes of the V and I channel in counts (> 0)
        "sigma2_v","sigma2_i"  noise variance of one quadrature component of the complex amplitude of
                             the V and I channel, in counts squared (>= 0)
        "autoranged"  true when the meter's autoranging chose this cell (3.3 step 2)
        "target"   a NAME of "resistors", or "short" / "open" (3.3 step 2a)
        "insertion" (short / open only, optional integer, default 0): which insertion of the bar
    ]
    "meta": {"time": u32, "note": "ASCII, at most 28 characters"}          optional
    "sections": optional constants of the other sections, written as given after the checks of 2.4:
        "clip": [[ [lo, hi] x 8 ] x 2]   "settle": [[u16 x 6] x 7]
        "monitor": {"mask": u32, "kv": [f x 6]}   "bias": u16

Model per frequency (3.3 step 3): log Znom = log Zx - log zeta[c8][c6] - log nu[c5] with complex logs;
the real part (ln |Znom|, "mag") and the imaginary part (arg Znom in radians, "pha") are two separate
real linear systems. Unknowns: zeta (index 8*c8 + c6), nu (c5; nu[g] = 1 where g = the reached c5
with the most resistor windows, the lowest c5 on a tie) and one Zx per resistor.

Window weight (stated formula): a quadrature component with noise variance s2 on an amplitude A has
the relative error variance s2 / A^2 in magnitude and the same in radians in phase; the quotient of V
by I adds both: var = sigma2_v / a_v^2 + sigma2_i / a_i^2, weight = 1 / var, the same for the mag and
the pha row of the window.

Anchors (3.2): magnitude rows for resistors of 100 ohm .. 100 kohm below 5 kHz and 100 ohm .. 10 kohm
at 10 kHz and 100 kHz (10 ohm never); phase rows for resistors up to 10 kohm below 5 kHz (no lower
limit) and 100 ohm .. 2 kohm at 10 kHz and 100 kHz. The anchor value is Z_anchor = Zs + 1 / (1/R + Yo):
ln |Z_anchor| and arg Z_anchor (which is the anchor phase 0 when Zs and Yo are absent).
Magnitude sigma = sqrt(u^2 + (dZs/R)^2) with u the resistor's relative uncertainty and dZs half the
largest distance between the insertion means of the short; phase sigma = sqrt(1e-4^2 + (w L/R)^2 +
(w R C)^2 + (dZs/R)^2) rad with the assumed parasitics L = 10 nH, C = 0.3 pF of 3.2 (the 1e-4 rad
floor is an engineering choice [J]). Weight = 1 / sigma^2.

Short and open: per frequency the windows of target "short" and "open" are referred back by the fitted
factor of the cell each was taken at: Zs = Znom_short * (zeta nu), Yo = (1 / Znom_open) / (zeta nu);
the means over all their windows are used. The first fit uses the readings as they are (factor 1), the
second fit uses the referred values and is the result ("the fit repeated once"); a cell whose factors
the first fit did not identify is not referred and is named in the report.

Numerical method: the rows are scaled by sqrt(weight), the columns to unit norm; Householder QR with
column pivoting (rank tolerance RANK_TOL = 1e-9 of the largest column norm) gives the basic solution,
the rank, an orthonormal basis of the null space (modified Gram-Schmidt, twice) and the leverages.
A factor is identified when its unit vector lies in the row space with the gauge fixed: the norm of its
row of the null-space basis is at most NULL_TOL = 1e-6. Mag bit and pha bit are set from the two
systems separately.

Checks (3.4): (a) anchor residual |r| / sigma <= 3 else the worst anchor is dropped and the fit
repeated; (b) residual ratio sqrt(sum w r^2 / sum (1 - h)) over the window rows (h = leverage) <= 3 for
the frequency and for each (frequency, level), mag and pha; (c) the bounds of 2.4 per factor: finite
float32, 0.25 <= re^2 + im^2 <= 4, re > 0, 4 re^2 >= re^2 + im^2; a factor outside clears both its
bits; (d) all-or-nothing: every autoranged cell of the resistor windows needs zeta mag, zeta pha,
nu mag and nu pha bits, there must be at least one autoranged cell; else the frequency gets all four
masks 0 and the failing cells / checks are named. (e) D14: the steps between neighbouring codes.

Output GAIN section: id 1, length 1992 (+4 header): per fi 0..5 zeta mag mask u32 (bit 8*c8 + c6),
zeta pha mask u32, nu mag mask u8 (bit c5), nu pha mask u8, pad u16 = 0, zeta[32] (re f32, im f32) at
8*c8 + c6, nu[8] (re, im); a factor without a bit is written (1.0, 0.0).
"""

import argparse
import json
import math
import struct
import sys

FREQ_HZ = (100.0, 120.0, 1000.0, 10000.0, 100000.0, 60.0)    # host list order of 1.2, fi 0..5
RANK_TOL = 1e-9          # QR: a pivot below this fraction of the first pivot ends the rank
NULL_TOL = 1e-6          # identifiability: norm of the null-space part of a factor's unit vector
RESID_K = 3.0            # 3.4: residual RMS at most 3 x the expected RMS
ANCHOR_K = 3.0           # 3.4: anchor residual at most 3 x its uncertainty
PARA_L = 10e-9           # assumed series inductance of a leaded resistor (3.2) [J]
PARA_C = 0.3e-12         # assumed parallel capacitance (3.2) [J]
PHASE_FLOOR = 1e-4       # radians, lowest phase anchor sigma [J]
LOW_MAG = (100.0, 1e5)   # magnitude anchors below 5 kHz, ohms
HIGH_MAG = (100.0, 1e4)  # magnitude anchors at 10 kHz and 100 kHz
LOW_PHA = (0.0, 1e4)     # phase anchors below 5 kHz
HIGH_PHA = (100.0, 2e3)  # phase anchors at 10 kHz and 100 kHz
BODY_MAX = 0xA00 - 0x40  # staging buffer of the meter minus the record header (2.4)
SEC_META, SEC_GAIN, SEC_CLIP, SEC_SETTLE, SEC_MONITOR, SEC_BIAS = 0, 1, 2, 3, 4, 5
GAIN_LEN = 6 * (12 + 32 * 8 + 8 * 8)       # 1992
COMPS = ('mag', 'pha')


# ---------------------------------------------------------------------------------------------
# numerics: weighted linear least squares by pivoted Householder QR
# ---------------------------------------------------------------------------------------------

class Sol(object):
    """Result of wls(): x, ident (per column: unit vector in the row space), rank, h (leverage per
    row), wr (weighted residual per row), nrows."""


def _back(cols, rank, rhs):
    """Solve R11 y = rhs for the upper triangle R11 held in cols[j][i] (i <= j < rank)."""
    y = [0.0] * rank
    for i in range(rank - 1, -1, -1):
        s = rhs[i]
        for j in range(i + 1, rank):
            s -= cols[j][i] * y[j]
        y[i] = s / cols[i][i]
    return y


def wls(rows, n):
    """Weighted least squares of rows = [([(col, coef), ...], rhs, weight), ...] over n unknowns.
    Rows are scaled by sqrt(weight), columns to unit norm, then Householder QR with column pivoting.
    Free (rank-deficient) unknowns are set 0 in the returned basic solution x; ident[j] is True when
    the unit vector of unknown j is in the row space (unique value). h[i] is the leverage of row i,
    wr[i] = sqrt(weight) * (rhs - A x) the weighted residual."""
    m = len(rows)
    cols = [[0.0] * m for _ in range(n)]
    b = [0.0] * m
    for i, (coef, rhs, wt) in enumerate(rows):
        s = math.sqrt(wt)
        for j, v in coef:
            cols[j][i] += s * v
        b[i] = s * rhs
    scale = []
    for j in range(n):
        nrm = math.sqrt(sum(v * v for v in cols[j]))
        if nrm > 0.0:
            cols[j] = [v / nrm for v in cols[j]]
        else:
            nrm = 1.0
        scale.append(nrm)
    scaled = [c[:] for c in cols]               # untouched copy, for the leverages
    perm = list(range(n))
    rank = 0
    first = 0.0
    for k in range(min(m, n)):
        best, bj = -1.0, k
        for j in range(k, n):
            s = sum(v * v for v in cols[j][k:])
            if s > best:
                best, bj = s, j
        nk = math.sqrt(best)
        if k == 0:
            first = nk
        if first <= 0.0 or nk <= RANK_TOL * first:
            break
        cols[k], cols[bj] = cols[bj], cols[k]
        perm[k], perm[bj] = perm[bj], perm[k]
        x = cols[k]
        alpha = -math.copysign(nk, x[k])
        v = x[k:]
        v[0] -= alpha
        vv = sum(t * t for t in v)
        cnt = len(v)
        for col in cols[k + 1:] + [b]:           # b is transformed with the columns
            d = 2.0 * sum(v[i] * col[k + i] for i in range(cnt)) / vv
            if d != 0.0:
                for i in range(cnt):
                    col[k + i] -= d * v[i]
        x[k] = alpha
        for i in range(k + 1, m):
            x[i] = 0.0
        rank += 1
    sol = Sol()
    sol.rank = rank
    sol.nrows = m
    yb = _back(cols, rank, b[:rank]) if rank else []
    sol.x = [0.0] * n
    for k in range(rank):
        sol.x[perm[k]] = yb[k] / scale[perm[k]]
    # null space: for each free unknown f the vector (-R11^-1 R12 e_f, e_f), orthonormalised
    basis = []
    for f in range(rank, n):
        zb = _back(cols, rank, [-cols[f][i] for i in range(rank)]) if rank else []
        v = zb + [0.0] * (n - rank)
        v[f] = 1.0
        for _ in range(2):
            for u in basis:
                d = sum(p * q for p, q in zip(u, v))
                v = [p - d * q for p, q in zip(v, u)]
        nv = math.sqrt(sum(t * t for t in v))
        basis.append([t / nv for t in v])
    sol.ident = [True] * n
    for k in range(n):
        if sum(u[k] * u[k] for u in basis) > NULL_TOL * NULL_TOL:
            sol.ident[perm[k]] = False
    # leverages: q = R11^-T a_i, h = |q|^2
    sol.h = []
    for i in range(m):
        q = []
        for j in range(rank):
            s = scaled[perm[j]][i]
            for t in range(j):
                s -= cols[j][t] * q[t]
            q.append(s / cols[j][j])
        sol.h.append(sum(t * t for t in q))
    sol.wr = []
    for coef, rhs, wt in rows:
        r = rhs - sum(sol.x[j] * v for j, v in coef)
        sol.wr.append(math.sqrt(wt) * r)
    return sol


# ---------------------------------------------------------------------------------------------
# factors, bounds, packing
# ---------------------------------------------------------------------------------------------

def _f32(x):
    """Round x to float32 (OverflowError when it does not fit)."""
    return struct.unpack('<f', struct.pack('<f', x))[0]


def factor_in_bounds(re, im):
    """The value rules of 2.4 for one factor: finite float32, 0.25 <= re^2 + im^2 <= 4, re > 0 and
    4 re^2 >= re^2 + im^2."""
    try:
        r, i = _f32(re), _f32(im)
    except (OverflowError, struct.error):
        return False
    if not (math.isfinite(r) and math.isfinite(i)):
        return False
    s = r * r + i * i
    return 0.25 <= s <= 4.0 and r > 0.0 and 4.0 * r * r >= s


def _cexp(lm, lp):
    """exp(lm) * (cos lp + j sin lp); an overflow gives an infinite real part (fails the bounds)."""
    try:
        m = math.exp(lm)
    except OverflowError:
        return complex(float('inf'), 0.0)
    return complex(m * math.cos(lp), m * math.sin(lp))


class Factors(object):
    """zeta[32] (index 8*c8 + c6), nu[8] and the four masks; default: all (1, 0), masks 0."""

    def __init__(self):
        self.zeta = [complex(1.0, 0.0) for _ in range(32)]
        self.nu = [complex(1.0, 0.0) for _ in range(8)]
        self.zmag = self.zpha = self.nmag = self.npha = 0

    def product(self, c8, c6, c5):
        """zeta * nu of the cell when all four bits are set, else None."""
        i = 8 * c8 + c6
        if (self.zmag >> i) & 1 and (self.zpha >> i) & 1 and (self.nmag >> c5) & 1 and (self.npha >> c5) & 1:
            return self.zeta[i] * self.nu[c5]
        return None

    def missing(self, c8, c6, c5):
        """Names of the bits the cell lacks."""
        i = 8 * c8 + c6
        out = []
        if not (self.zmag >> i) & 1:
            out.append('zeta magnitude')
        if not (self.zpha >> i) & 1:
            out.append('zeta phase')
        if not (self.nmag >> c5) & 1:
            out.append('nu magnitude')
        if not (self.npha >> c5) & 1:
            out.append('nu phase')
        return out


def gain_section(fits):
    """The GAIN section (id 1, length 1992) with its 4-byte header from fits, a dict fi -> FreqFit
    (absent frequencies get masks 0). A factor with neither bit is written (1.0, 0.0)."""
    body = b''
    for fi in range(6):
        ff = fits.get(fi)
        f = ff.out if ff is not None else Factors()
        body += struct.pack('<IIBBH', f.zmag, f.zpha, f.nmag, f.npha, 0)
        for i in range(32):
            z = f.zeta[i] if ((f.zmag | f.zpha) >> i) & 1 else complex(1.0, 0.0)
            body += struct.pack('<ff', z.real, z.imag)
        for c in range(8):
            z = f.nu[c] if ((f.nmag | f.npha) >> c) & 1 else complex(1.0, 0.0)
            body += struct.pack('<ff', z.real, z.imag)
    if len(body) != GAIN_LEN:
        raise ValueError('GAIN body is %d bytes, not %d' % (len(body), GAIN_LEN))
    return struct.pack('<HH', SEC_GAIN, GAIN_LEN) + body


def validate_gain_section(sec):
    """The GAIN rules of 2.4 on a packed section (with header): structure, pad 0, and for every
    factor with a bit set the bounds. Raises ValueError naming the frequency and factor."""
    if len(sec) != 4 + GAIN_LEN or struct.unpack_from('<HH', sec, 0) != (SEC_GAIN, GAIN_LEN):
        raise ValueError('GAIN section: wrong header or length')
    for fi in range(6):
        base = 4 + fi * 332
        zm, zp, nm, npa, pad = struct.unpack_from('<IIBBH', sec, base)
        if pad:
            raise ValueError('GAIN fi %d: pad is not 0' % fi)
        for i in range(32):
            if ((zm | zp) >> i) & 1:
                re, im = struct.unpack_from('<ff', sec, base + 12 + 8 * i)
                if not factor_in_bounds(re, im):
                    raise ValueError('GAIN fi %d: zeta[%d] (%g, %g) outside the bounds of 2.4' % (fi, i, re, im))
        for c in range(8):
            if ((nm | npa) >> c) & 1:
                re, im = struct.unpack_from('<ff', sec, base + 12 + 256 + 8 * c)
                if not factor_in_bounds(re, im):
                    raise ValueError('GAIN fi %d: nu[%d] (%g, %g) outside the bounds of 2.4' % (fi, c, re, im))


def _section(sid, body):
    """{id u16, length u16} + body."""
    return struct.pack('<HH', sid, len(body)) + body


def build_body(gain=None, meta=None, clip=None, settle=None, monitor=None, bias=None):
    """The record body: the sections given, ascending ids (1.2), each checked by the rules of 2.4.
    gain: the bytes of gain_section(); meta: (time u32, note str <= 28 ASCII); clip: [2][8] of (lo, hi);
    settle: [7][6] ms; monitor: (mask, [6 kV]); bias: u16 limit. A section left None is absent."""
    out = b''
    if meta is not None:
        t, note = meta
        raw = note.encode('ascii')
        if not 0 <= t <= 0xFFFFFFFF or len(raw) > 28:
            raise ValueError('META: time must be a u32 and the note at most 28 ASCII characters')
        out += _section(SEC_META, struct.pack('<I', t) + raw + b'\0' * (28 - len(raw)))
    if gain is not None:
        validate_gain_section(gain)
        out += gain
    if clip is not None:
        body = b''
        for ch in range(2):
            for g in range(8):
                lo, hi = clip[ch][g]
                if not (0 <= lo < hi <= 4095 and hi - lo > 3600):
                    raise ValueError('CLIP[%d][%d] (%d, %d): need hi <= 4095, lo < hi, hi - lo > 3600' % (ch, g, lo, hi))
                body += struct.pack('<HH', lo, hi)
        out += _section(SEC_CLIP, body)
    if settle is not None:
        body = b''
        for k in range(7):
            for f in range(6):
                v = settle[k][f]
                if not 1 <= v <= 500:
                    raise ValueError('SETTLE[%d][%d] = %d: need 1..500 ms' % (k, f, v))
                body += struct.pack('<H', v)
        out += _section(SEC_SETTLE, body)
    if monitor is not None:
        mask, kv = monitor
        if mask & ~0x3F or len(kv) != 6:
            raise ValueError('MONITOR: mask bits 0..5 only, six kV values')
        for f in range(6):
            if (mask >> f) & 1 and not (math.isfinite(kv[f]) and 1e-6 <= kv[f] <= 1.0):
                raise ValueError('MONITOR kV[%d] = %r: need 1e-6..1' % (f, kv[f]))
        out += _section(SEC_MONITOR, struct.pack('<I6f', mask, *kv))
    if bias is not None:
        if not 1 <= bias <= 4095:
            raise ValueError('BIAS limit %d: need 1..4095' % bias)
        out += _section(SEC_BIAS, struct.pack('<HH', bias, 0))
    if len(out) > BODY_MAX:
        raise ValueError('body of %d bytes exceeds the staging buffer room of %d' % (len(out), BODY_MAX))
    return out


# ---------------------------------------------------------------------------------------------
# run file
# ---------------------------------------------------------------------------------------------

class Win(object):
    """One window of the run file, validated."""

    def __init__(self, d, resistors):
        try:
            self.fi, self.level = int(d['fi']), int(d['level'])
            self.c5, self.c6, self.c8 = int(d['c5']), int(d['c6']), int(d['c8'])
            self.z = complex(float(d['znom_re']), float(d['znom_im']))
            self.av, self.ai = float(d['a_v']), float(d['a_i'])
            self.s2v, self.s2i = float(d['sigma2_v']), float(d['sigma2_i'])
            self.auto = bool(d.get('autoranged', False))
            self.target = d['target']
            self.ins = int(d.get('insertion', 0))
        except (KeyError, TypeError, ValueError) as e:
            raise ValueError('window %r: %s' % (d, e))
        if not (0 <= self.fi <= 5 and self.level >= 0 and 0 <= self.c5 <= 7 and 0 <= self.c6 <= 7
                and 0 <= self.c8 <= 3):
            raise ValueError('window %r: fi 0..5, level >= 0, c5 0..7, c6 0..7, c8 0..3' % (d,))
        vals = (self.z.real, self.z.imag, self.av, self.ai, self.s2v, self.s2i)
        if not all(math.isfinite(v) for v in vals) or self.av <= 0 or self.ai <= 0 or self.s2v < 0 or self.s2i < 0:
            raise ValueError('window %r: finite values, amplitudes > 0, variances >= 0' % (d,))
        if self.target not in ('short', 'open') and self.target not in resistors:
            raise ValueError('window %r: unknown target' % (d,))
        if self.target != 'short' and self.z == 0:
            raise ValueError('window %r: Znom is 0' % (d,))
        self.var = self.s2v / (self.av * self.av) + self.s2i / (self.ai * self.ai)
        if self.target not in ('short', 'open') and not self.var > 0.0:
            raise ValueError('window %r: zero variance gives no weight' % (d,))


def parse_run(run):
    """(resistors {name: (value, uncertainty)}, windows [Win]) from the run dict."""
    res = {}
    for name, r in run.get('resistors', {}).items():
        v, u = float(r['value']), float(r['uncertainty'])
        if name in ('short', 'open') or not (math.isfinite(v) and v > 0 and math.isfinite(u) and u > 0):
            raise ValueError('resistor %r: value > 0, uncertainty > 0, name not short / open' % name)
        res[name] = (v, u)
    return res, [Win(d, res) for d in run.get('windows', [])]


# ---------------------------------------------------------------------------------------------
# the fit of one frequency
# ---------------------------------------------------------------------------------------------

class FreqFit(object):
    """Result of one frequency: ok, reasons (why masks are 0), raw (identified Factors before the
    bounds), out (Factors written), pass1 (Factors of the first fit or None), the residual ratios,
    anchors, terminals, steps, failing cells, bound violations, ranks."""

    def __init__(self, fi):
        self.fi = fi
        self.ok = False
        self.reasons = []
        self.raw = Factors()
        self.out = Factors()
        self.pass1 = None
        self.resid = {}
        self.anchors = {}
        self.terminal = {}
        self.steps = {}
        self.bad_cells = []
        self.violations = []
        self.rank = {}
        self.nwin = 0


def _anchor_ok(r, lim):
    """r inside lim = (lo, hi) with a relative slack of 1e-9."""
    return lim[0] * (1 - 1e-9) <= r <= lim[1] * (1 + 1e-9)


def _anchors(fi, resistors, targets, zs, yo, dzs):
    """Anchor rows of 3.2 for the resistors in targets: {'mag': [...], 'pha': [...]} of dicts with
    target, value, sigma, dropped, resid."""
    hz = FREQ_HZ[fi]
    w = 2.0 * math.pi * hz
    high = hz >= 5000.0
    out = {'mag': [], 'pha': []}
    for t in sorted(targets):
        r, u = resistors[t]
        za = zs + 1.0 / (1.0 / r + yo)
        if za == 0:
            raise ValueError('anchor of %s is 0 ohm' % t)
        sm = math.sqrt(u * u + (dzs / r) ** 2)
        sp = math.sqrt(PHASE_FLOOR ** 2 + (w * PARA_L / r) ** 2 + (w * r * PARA_C) ** 2 + (dzs / r) ** 2)
        if _anchor_ok(r, HIGH_MAG if high else LOW_MAG):
            out['mag'].append({'target': t, 'value': math.log(abs(za)), 'sigma': sm, 'dropped': False, 'resid': None})
        if _anchor_ok(r, HIGH_PHA if high else LOW_PHA):
            out['pha'].append({'target': t, 'value': math.atan2(za.imag, za.real), 'sigma': sp, 'dropped': False, 'resid': None})
    return out


def _terminal(shorts, opens, factor_fn):
    """Zs, Yo, dZs and notes from the short / open windows, each referred back by factor_fn(window)
    (a complex zeta*nu or None = not identified, taken as 1)."""
    notes = []

    def fac(w):
        f = factor_fn(w)
        if f is None:
            notes.append('%s window cell c8=%d c6=%d c5=%d not referred (factor not identified)' % (w.target, w.c8, w.c6, w.c5))
            return complex(1.0, 0.0)
        return f
    zs, dzs = complex(0.0, 0.0), 0.0
    if shorts:
        ref = [(w.ins, w.z * fac(w)) for w in shorts]
        zs = sum(v for _, v in ref) / len(ref)
        means = []
        for ins in sorted({i for i, _ in ref}):
            vs = [v for i, v in ref if i == ins]
            means.append(sum(vs) / len(vs))
        dzs = max(abs(a - b) for a in means for b in means) / 2.0
    yo = complex(0.0, 0.0)
    if opens:
        ref = [(1.0 / w.z) / fac(w) for w in opens]
        yo = sum(ref) / len(ref)
    return zs, yo, dzs, notes


def _columns(res, gauge):
    """Unknown index per key: ('x', resistor), ('z', 8*c8 + c6), ('n', c5) for c5 != gauge."""
    cols = {}
    for w in res:
        keys = [('x', w.target), ('z', 8 * w.c8 + w.c6)]
        if w.c5 != gauge:
            keys.append(('n', w.c5))
        for k in keys:
            if k not in cols:
                cols[k] = len(cols)
    return cols


def _rows(comp, res, cols, gauge, anchors):
    """Window rows (in the order of res) followed by the active anchor rows."""
    rows = []
    for w in res:
        co = [(cols[('x', w.target)], 1.0), (cols[('z', 8 * w.c8 + w.c6)], -1.0)]
        if w.c5 != gauge:
            co.append((cols[('n', w.c5)], -1.0))
        v = math.log(abs(w.z)) if comp == 'mag' else math.atan2(w.z.imag, w.z.real)
        rows.append((co, v, 1.0 / w.var))
    for a in anchors:
        if not a['dropped']:
            rows.append(([(cols[('x', a['target'])], 1.0)], a['value'], 1.0 / (a['sigma'] ** 2)))
    return rows


def _solve_comp(comp, res, cols, gauge, anchors, reject):
    """Solve one component; with reject the worst anchor beyond ANCHOR_K sigma is dropped and the
    fit repeated until none is. Returns the Sol (rows: windows, then active anchors)."""
    while True:
        sol = wls(_rows(comp, res, cols, gauge, anchors), len(cols))
        active = [a for a in anchors if not a['dropped']]
        for k, a in enumerate(active):
            a['resid'] = sol.wr[len(res) + k]
        if not reject or not active:
            return sol
        worst = max(active, key=lambda a: abs(a['resid']))
        if abs(worst['resid']) <= ANCHOR_K:
            return sol
        worst['dropped'] = True


def _factors_from(cols, gauge, sols, c5s):
    """Raw Factors (identified values only) from the two solutions."""
    f = Factors()
    sm, sp = sols['mag'], sols['pha']
    for i in range(32):
        j = cols.get(('z', i))
        if j is None:
            continue
        mi, pi = sm.ident[j], sp.ident[j]
        f.zeta[i] = _cexp(sm.x[j] if mi else 0.0, sp.x[j] if pi else 0.0)
        f.zmag |= int(mi) << i
        f.zpha |= int(pi) << i
    for c in c5s:
        if c == gauge:
            f.nmag |= 1 << c
            f.npha |= 1 << c
            continue
        j = cols[('n', c)]
        mi, pi = sm.ident[j], sp.ident[j]
        f.nu[c] = _cexp(sm.x[j] if mi else 0.0, sp.x[j] if pi else 0.0)
        f.nmag |= int(mi) << c
        f.npha |= int(pi) << c
    return f


def _ratio(obs, exp):
    """sqrt(obs / exp) with the empty case defined: 0 when both vanish, infinity when only exp does."""
    if exp < 1e-6:
        return 0.0 if obs < 1e-6 else float('inf')
    return math.sqrt(obs / exp)


def _residuals(sols, res):
    """Residual ratios per component: {'all': r, 'levels': {level: r}} over the window rows."""
    out = {}
    for comp in COMPS:
        sol = sols[comp]
        acc = {}
        for k, w in enumerate(res):
            o = acc.setdefault(w.level, [0.0, 0.0])
            o[0] += sol.wr[k] ** 2
            o[1] += 1.0 - min(sol.h[k], 1.0)
        to = sum(a[0] for a in acc.values())
        te = sum(a[1] for a in acc.values())
        out[comp] = {'all': _ratio(to, te), 'levels': {l: _ratio(a[0], a[1]) for l, a in sorted(acc.items())}}
    return out


def _steps(f):
    """D14: steps between neighbouring codes of the identified factors (zeta along c6 and c8, nu along
    c5): largest |ln magnitude ratio| and largest phase difference in degrees."""
    pairs = []
    for c8 in range(4):
        for c6 in range(8):
            if c6 < 7:
                pairs.append((8 * c8 + c6, 8 * c8 + c6 + 1, 'z'))
            if c8 < 3:
                pairs.append((8 * c8 + c6, 8 * (c8 + 1) + c6, 'z'))
    pairs += [(c, c + 1, 'n') for c in range(7)]
    mags, phas = [], []
    for a, b, kind in pairs:
        if kind == 'z':
            ok = all((f.zmag >> i) & 1 and (f.zpha >> i) & 1 for i in (a, b))
            za, zb = f.zeta[a], f.zeta[b]
        else:
            ok = all((f.nmag >> i) & 1 and (f.npha >> i) & 1 for i in (a, b))
            za, zb = f.nu[a], f.nu[b]
        if ok:
            mags.append(abs(math.log(abs(zb) / abs(za))))
            q = zb / za
            phas.append(abs(math.degrees(math.atan2(q.imag, q.real))))
    mm, mp = (max(mags), max(phas)) if mags else (0.0, 0.0)
    return {'n': len(mags), 'max_mag': mm, 'max_phase_deg': mp,
            'little': bool(mags) and mm < 1e-3 and mp < 0.05}


def fit_frequency(fi, resistors, wins):
    """Fit one frequency (3.3 steps 3 to 5) from its windows; see the module docstring."""
    ff = FreqFit(fi)
    res = [w for w in wins if w.target not in ('short', 'open')]
    shorts = [w for w in wins if w.target == 'short']
    opens = [w for w in wins if w.target == 'open']
    ff.nwin = len(res)
    if not res:
        ff.reasons.append('no resistor windows')
        return ff
    count = {}
    for w in res:
        count[w.c5] = count.get(w.c5, 0) + 1
    gauge = min(count, key=lambda c: (-count[c], c))
    cols = _columns(res, gauge)
    c5s = sorted(count)
    targets = {w.target for w in res}
    if shorts or opens:
        zs, yo, dzs, notes = _terminal(shorts, opens, lambda w: 1.0 + 0j)
        anc = _anchors(fi, resistors, targets, zs, yo, dzs)
        sols = {c: _solve_comp(c, res, cols, gauge, anc[c], False) for c in COMPS}
        ff.pass1 = _factors_from(cols, gauge, sols, c5s)
        zs, yo, dzs, notes = _terminal(shorts, opens, lambda w: ff.pass1.product(w.c8, w.c6, w.c5))
        ff.terminal = {'zs': [zs.real, zs.imag], 'yo': [yo.real, yo.imag], 'dzs': dzs, 'notes': notes}
    else:
        zs = yo = complex(0.0, 0.0)
        dzs = 0.0
    anc = _anchors(fi, resistors, targets, zs, yo, dzs)
    sols = {c: _solve_comp(c, res, cols, gauge, anc[c], True) for c in COMPS}
    ff.anchors = {c: [dict(a) for a in anc[c]] for c in COMPS}
    ff.rank = {c: [sols[c].rank, len(cols)] for c in COMPS}
    ff.raw = _factors_from(cols, gauge, sols, c5s)
    ff.resid = _residuals(sols, res)
    ff.steps = _steps(ff.raw)
    # 2.4 bounds: a factor outside clears both its bits (value stays (1, 0))
    out = Factors()
    r = ff.raw
    for i in range(32):
        if not ((r.zmag | r.zpha) >> i) & 1:
            continue
        z = r.zeta[i]
        if factor_in_bounds(z.real, z.imag):
            out.zeta[i] = z
            out.zmag |= r.zmag & (1 << i)
            out.zpha |= r.zpha & (1 << i)
        else:
            ff.violations.append({'kind': 'zeta', 'index': i, 're': z.real, 'im': z.imag})
    for c in range(8):
        if not ((r.nmag | r.npha) >> c) & 1:
            continue
        z = r.nu[c]
        if factor_in_bounds(z.real, z.imag):
            out.nu[c] = z
            out.nmag |= r.nmag & (1 << c)
            out.npha |= r.npha & (1 << c)
        else:
            ff.violations.append({'kind': 'nu', 'index': c, 're': z.real, 'im': z.imag})
    # all-or-nothing (F12): residuals, then the autoranged cells
    for comp in COMPS:
        if ff.resid[comp]['all'] > RESID_K:
            ff.reasons.append('%s residual ratio %.3g > %g over the frequency' % (comp, ff.resid[comp]['all'], RESID_K))
        for lv, v in ff.resid[comp]['levels'].items():
            if v > RESID_K:
                ff.reasons.append('%s residual ratio %.3g > %g at level %d' % (comp, v, RESID_K, lv))
    autos = sorted({(w.c8, w.c6, w.c5) for w in res if w.auto})
    if not autos:
        ff.reasons.append('no autoranged cell in the run')
    for (c8, c6, c5) in autos:
        miss = out.missing(c8, c6, c5)
        if miss:
            ff.bad_cells.append({'cell': [c8, c6, c5], 'missing': miss})
            ff.reasons.append('autoranged cell c8=%d c6=%d c5=%d lacks %s' % (c8, c6, c5, ', '.join(miss)))
    ff.ok = not ff.reasons
    ff.out = out if ff.ok else Factors()
    return ff


class RunFit(object):
    """fits: dict fi -> FreqFit for the frequencies that have windows."""

    def __init__(self):
        self.fits = {}


def fit_run(run):
    """Fit every frequency of a run dict (see the module docstring)."""
    resistors, wins = parse_run(run)
    rf = RunFit()
    for fi in range(6):
        w = [x for x in wins if x.fi == fi]
        if w:
            rf.fits[fi] = fit_frequency(fi, resistors, w)
    return rf


# ---------------------------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------------------------

def _jf(x):
    """JSON-safe number: None for inf / nan, else x."""
    return None if isinstance(x, float) and not math.isfinite(x) else x


def report_dict(rf):
    """The report as a JSON-able dict, per frequency index."""
    out = {}
    for fi, ff in sorted(rf.fits.items()):
        out[str(fi)] = {
            'hz': FREQ_HZ[fi], 'ok': ff.ok, 'reasons': ff.reasons, 'resistor_windows': ff.nwin,
            'rank': ff.rank,
            'identified': {'zeta_mag': ff.raw.zmag, 'zeta_pha': ff.raw.zpha, 'nu_mag': ff.raw.nmag, 'nu_pha': ff.raw.npha},
            'written': {'zeta_mag': ff.out.zmag, 'zeta_pha': ff.out.zpha, 'nu_mag': ff.out.nmag, 'nu_pha': ff.out.npha},
            'residual_ratio': {c: {'all': _jf(ff.resid[c]['all']),
                                   'levels': {str(l): _jf(v) for l, v in ff.resid[c]['levels'].items()}}
                               for c in ff.resid},
            'anchors': {c: [{'target': a['target'], 'sigma': a['sigma'], 'dropped': a['dropped'],
                             'resid_sigma': _jf(a['resid'])} for a in ff.anchors[c]] for c in ff.anchors},
            'terminal': ff.terminal, 'steps': ff.steps, 'bad_cells': ff.bad_cells, 'bound_violations': ff.violations,
        }
    return out


def report_text(rf):
    """The report as text lines."""
    lines = []
    for fi, ff in sorted(rf.fits.items()):
        lines.append('fi %d (%g Hz): %s, %d resistor windows' % (fi, FREQ_HZ[fi], 'GAIN written' if ff.ok else 'masks 0', ff.nwin))
        for r in ff.reasons:
            lines.append('  blocked: ' + r)
        for c in ff.rank:
            lines.append('  %s system rank %d of %d unknowns; residual ratio %.3g; levels %s; anchors dropped %s'
                         % (c, ff.rank[c][0], ff.rank[c][1], ff.resid[c]['all'],
                            ', '.join('%d:%.3g' % (l, v) for l, v in ff.resid[c]['levels'].items()),
                            [a['target'] for a in ff.anchors[c] if a['dropped']] or 'none'))
        lines.append('  identified masks zeta mag %08X pha %08X, nu mag %02X pha %02X; written %08X %08X %02X %02X'
                     % (ff.raw.zmag, ff.raw.zpha, ff.raw.nmag, ff.raw.npha, ff.out.zmag, ff.out.zpha, ff.out.nmag, ff.out.npha))
        for v in ff.violations:
            lines.append('  bound violation: %s[%d] = (%g, %g), bits cleared' % (v['kind'], v['index'], v['re'], v['im']))
        if ff.terminal:
            lines.append('  Zs %s ohm, Yo %s S, dZs %g' % (ff.terminal['zs'], ff.terminal['yo'], ff.terminal['dzs']))
            for n in ff.terminal['notes']:
                lines.append('    ' + n)
        s = ff.steps
        lines.append('  D14 steps over %d neighbour pairs: max %.3g in magnitude, %.3g deg%s'
                     % (s['n'], s['max_mag'], s['max_phase_deg'], '; the correction changes little' if s['little'] else ''))
    return '\n'.join(lines)


# ---------------------------------------------------------------------------------------------
# command line
# ---------------------------------------------------------------------------------------------

def sections_from_run(run, gain):
    """Keyword arguments for build_body from the run's optional meta / sections and the GAIN bytes."""
    kw = {'gain': gain}
    if 'meta' in run:
        kw['meta'] = (int(run['meta']['time']), str(run['meta'].get('note', '')))
    s = run.get('sections', {})
    if 'clip' in s:
        kw['clip'] = s['clip']
    if 'settle' in s:
        kw['settle'] = s['settle']
    if 'monitor' in s:
        kw['monitor'] = (int(s['monitor']['mask']), [float(v) for v in s['monitor']['kv']])
    if 'bias' in s:
        kw['bias'] = int(s['bias'])
    return kw


def main(argv=None):
    """Command line entry; see the module docstring."""
    ap = argparse.ArgumentParser(description='gain fit of the own calibration area (body of OCAL_WRITE, PROTOCOL.md section 16)')
    ap.add_argument('runfile', metavar='RUNFILE')
    ap.add_argument('-o', metavar='BODY', help='write the record body here')
    ap.add_argument('--report', metavar='FILE', help='write the report here (JSON when the name ends in .json)')
    a = ap.parse_args(argv)
    with open(a.runfile) as fh:
        run = json.load(fh)
    rf = fit_run(run)
    text = report_text(rf)
    print(text)
    if a.o:
        body = build_body(**sections_from_run(run, gain_section(rf.fits)))
        with open(a.o, 'wb') as fh:
            fh.write(body)
        print('%s: %d bytes' % (a.o, len(body)))
    if a.report:
        with open(a.report, 'w') as fh:
            if a.report.endswith('.json'):
                json.dump(report_dict(rf), fh, indent=1, sort_keys=True)
            else:
                fh.write(text + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
