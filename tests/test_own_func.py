#!/usr/bin/env python3
"""test_own_func.py - the instrument functions of our build (MEASUREMENT_FIX_DESIGN.md revision 6: stage 2
S2.1..S2.7, S2.9; stage 2F S2.12 (60 Hz); stage 2G S2.8; firmware/own/fmt.s, cmp.s and the stage-2 parts
of meas.s), in the emulator. Cases f20..f29 are the design's 5.1 lists m20..m28 and the F60 list; the
save cases s06..s09 of the design are test_own_save.py s21..s25.

Usage (from the repository root, after `make -C firmware` (build/app.elf for the V1.1 control) and
`make -C firmware own`):
    <python with unicorn 2.1.4> tests/test_own_func.py [case-name-prefix ...]

Rigs: test_own_measure.own_rig (test_own_control.Ctl with the measurement path, the m15 table watch and
the probe, imported, not changed) and test_own_measure.VRig (V1.1). Most checks call the functions of
the built image directly in a stopped rig (fcall below: the CPU context is saved and restored around the
call, the arguments in r0..r3 / s0, text buffers at 0x20014400, above the heap end 0x2001424C and far
below the stack in use, as test_own_measure m03 places its array); the cases that need the main loop
(the host record, hold, the compare screen with a part inserted and removed, 60 Hz) run it.

Expected values: every formatted text below is derived by hand from the vendor format thresholds of the
ui_42.s headers (0x0800E028, 0x0800DB24, 0x0800DE2C, 0x0800DD44) and the rules of fmt.s: OL above the
measurement range, one decimal less above 19,999 counts, a '-' for a negative X; a negative value by its
quantity (MEASUREMENT_FIX_DESIGN revision 14 rule 1): series R, parallel C, series L, |Z| and D the text
of 0, parallel R, series C, parallel L and Q OL, series / parallel by the word 0x200011EC (V_SERPAR, set
by every case that calls the R / C / L wrappers); OL for every text at 60 / 100 / 120 Hz with |Z|
0x200050C4 above 1e7 (rule 2, V_Z set by those cases); the accuracy table
of fmt.s fmt_spec (design S2.1); the AUTO thresholds 10 / 11 / 9 degrees (D3); series / parallel at
1 k / 10 k / 3162.28 ohm (D4); the compare rules of the cmp.s header. RUN LIMIT: one run of this file
per case prefix, 12 cases.
"""

import os
import struct
import sys

from unicorn import UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_S0, UC_ARM_REG_S22, \
    UC_ARM_REG_LR

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_own_measure as M  # noqa: E402
from test_own_measure import (own_rig, VRig, TDut, mo, tap, settings_item, wait_until,  # noqa: E402
                              V_FREQ, V_LEVEL, V_BIAS, V_RANGE, V_SPEED, V_CIRCUIT, V_SCREEN, V_HOLD,
                              V_CAL_RUN, KEY_OK, KEY_HOLD, MAIN_LOOP, u32f, f2u)
from test_own_control import check, S_OK  # noqa: E402
from measure_model import DutSource, TIM1, TIM6  # noqa: E402

CASES = []
NOTES = []

OWN_FUNC = 0x20018000 + 0x5DE0
MF = dict(MARK=0x00, ROW0=0x04, ROW1=0x08, SP=0x0C, AUTO=0x10, HOLDP=0x14, HL=0x18, PSEQ=0x30, TMODE=0x34,
          TLO=0x38, THI=0x3C, TLET=0x40, SKIND=0x44, SVAL=0x48, TOLW=0x4C, RES=0x50, DEV=0x54, EMODE=0x58,
          ELO=0x5C, EHI=0x60, PREV=0x64, PVSEQ=0x68, PVOK=0x6C, LED=0x70, BEEPN=0x74, BEEPT=0x78, BEEPS=0x7C)
CR_NONE, CR_IN, CR_HI, CR_LO, CR_SEC, CR_OUT, CR_UNST = range(7)
V_FUNC, V_SECONDARY, V_MAIN_ROW, V_CMP_TYPE = 0x20001148, 0x200011E8, 0x200011E4, 0x20001178
V_NOMINAL, V_TOLERANCE, V_DISP_A8, V_KEY_BUSY = 0x20001184, 0x20001188, 0x200011A8, 0x20001190
V_SIGN_MODE, V_PASS, V_FAIL, V_DEV = 0x20001198, 0x200050F0, 0x200050F4, 0x200050D8
V_R, V_Z, V_TH, V_CS, V_L, V_CMPV, V_D, V_Q, V_RS = (0x200050B8, 0x200050C4, 0x200050CC, 0x200050A8, 0x200050C0,
                                                    0x200050DC, 0x200050D4, 0x200050D0, 0x200050A0)
V_C, V_X, V_SERPAR, V_NO_READ_CNT = 0x200050BC, 0x200050C8, 0x200011EC, 0x2000120C
OBJS = 0x200001D4                     # +0 ring index, +1 latch, +0x14 AUTO picture, +0x38 / +0x3C counters,
                                      # +0x40 result text, +0x44 deviation text
GLYPHS = 0x200059A8
TXT, UNIT, IDX = 0x20014400, 0x20014410, 0x20014418
S_BAD_ARG, S_NOT_NOW = 2, 3
GPIOB, TIM2 = 0x40010C00, 0x40000000


def case(fn):
    CASES.append(fn)
    return fn


# ---------------------------------------------------------------- direct calls

def fcall(rig, name, *regs, s0=None, s22=None):
    """name(r0..r3) with s0 / s22 set, in the stopped rig; the CPU context restored afterwards; returns r0."""
    uc = rig.m.uc
    ctx = uc.context_save()
    if s0 is not None:
        uc.reg_write(UC_ARM_REG_S0, f2u(s0))
    if s22 is not None:
        uc.reg_write(UC_ARM_REG_S22, f2u(s22))
    r = rig.m.call(rig.s[name], *regs)
    end = rig.m.st['end']
    uc.context_restore(ctx)
    check(end == 'return', '%s did not return: %r' % (name, end))
    rig.m.st['end'] = None                                    # the chip runs on (meter_model run_for)
    return r


def fcall_bits(rig, name, bits):
    """name(TXT, UNIT, IDX) with s0 = the raw float bits (Inf, NaN), context restored."""
    uc = rig.m.uc
    ctx = uc.context_save()
    uc.reg_write(UC_ARM_REG_S0, bits)
    rig.m.call(rig.s[name], TXT, UNIT, IDX)
    end = rig.m.st['end']
    uc.context_restore(ctx)
    check(end == 'return', '%s did not return: %r' % (name, end))
    rig.m.st['end'] = None


def cstr(rig, addr, n=16):
    b = rig.rd(addr, n)
    return b.split(b'\x00')[0].decode('latin-1')


def fmt(rig, name, v, freq=None):
    """One formatter call: (text, unit text, unit index, MF_MARK)."""
    if freq is not None:
        rig.wr(V_FREQ, freq)
    rig.wr(TXT, bytes(32))
    rig.wr(OWN_FUNC + MF['MARK'], 0x55)
    fcall(rig, name, TXT, UNIT, IDX, s0=v)
    return cstr(rig, TXT), cstr(rig, UNIT, 8), rig.rd(IDX), rig.rd(OWN_FUNC + MF['MARK'])


def mf(rig, k):
    return rig.rd(OWN_FUNC + MF[k])


def mff(rig, k):
    return u32f(rig.rd(OWN_FUNC + MF[k]))


def wf(rig, addr, x):
    rig.wr(addr, f2u(x))


def entry_hook(rig, name, regs=(UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2)):
    """A list that collects (time, r0, r1, r2) at every entry of the function."""
    out = []
    a = rig.s[name] & ~1

    def hook(uc, addr, size, user):
        out.append((rig.m.now(),) + tuple(uc.reg_read(r) for r in regs))
    rig.m.uc.hook_add(UC_HOOK_CODE, hook, begin=a, end=a)
    return out


_BASE = []


def base_rig():
    """One rig of our build on screen 1 (R 1 kohm, 1 kHz), up to the main loop, shared by the
    direct-call cases (they never resume it)."""
    if not _BASE:
        _BASE.append(own_rig(DutSource('R', 1000.0)))
    return _BASE[0]


# ---------------------------------------------------------------- f20 OL and the specified range

@case
def f20_ol_and_marker():
    """m20 (S2.1): values just inside and just outside every limit of the measurement range (OL) and of
    the accuracy table (marker) per frequency column; |Z| goes through the R row (own_fmt_r), X through
    own_fmt_x with the R limits (S2.2 revision 13: a negative R is 0, so the OL of a negative magnitude
    above the range is X's; a negative series R beyond it is 0 and marked); |Z| through own_fmt_z (the R
    row); 60 Hz has no column (always marked); NaN / Inf are OL. Inputs written first: |Z| 0x200050C4 =
    1000 ohm (so rule 2 of revision 14, |Z| above 1e7 at 60 / 100 / 120 Hz, acts on no row here; f31 tests
    it) and 0x200011EC = 0 (series: a negative R is 0). own_row_draw colours the seven glyphs of the row
    with key 0x47 / 0x48 when marked and switches it off again (fn_080265dc / fn_080265f4)."""
    rig = base_rig()
    check(mf(rig, 'TMODE') == 0, 'tolerance mode %d after the start' % mf(rig, 'TMODE'))
    wf(rig, V_Z, 1000.0)
    rig.wr(V_SERPAR, 0)
    rig.wr(V_MAIN_ROW, bytes([1]))                            # main row R: fmt_dq's C / L rule (f31 c) off
    # (formatter, value, frequency, OL expected, marker expected)
    rows = [
        ('own_fmt_r', 1.0e7, 1000, False, False), ('own_fmt_r', 1.0001e7, 1000, True, False),
        ('own_fmt_r', 0.01, 100, False, False), ('own_fmt_r', 0.0099, 100, False, True),
        ('own_fmt_r', 0.01, 120, False, False), ('own_fmt_r', 1.0e7, 120, False, False),
        ('own_fmt_r', 1.0e6, 10000, False, False), ('own_fmt_r', 1.0001e6, 10000, False, True),
        ('own_fmt_r', 1.0e6, 100000, False, False), ('own_fmt_r', 1.0001e6, 100000, False, True),
        ('own_fmt_r', 1000.0, 60, False, True), ('own_fmt_x', -1.0001e7, 1000, True, False),
        ('own_fmt_x', -1.0e7, 1000, False, False), ('own_fmt_r', -1.0001e7, 1000, False, True),
        ('own_fmt_z', 1.0e7, 1000, False, False), ('own_fmt_z', 1.0001e7, 1000, True, False),
        ('own_fmt_c', 1.0e8, 1000, False, False), ('own_fmt_c', 1.0001e8, 1000, True, False),
        ('own_fmt_c', 1000.0, 100, False, False), ('own_fmt_c', 999.0, 100, False, True),
        ('own_fmt_c', 0.001, 1000, False, False), ('own_fmt_c', 0.00099, 1000, False, True),
        ('own_fmt_c', 1.0e6, 10000, False, False), ('own_fmt_c', 1.0001e6, 10000, False, True),
        ('own_fmt_c', 0.001, 100000, False, False), ('own_fmt_c', 1.0001e6, 100000, False, True),
        ('own_fmt_l', 1.0e8, 1000, False, False), ('own_fmt_l', 1.0001e8, 1000, True, False),
        ('own_fmt_l', 10.0, 100, False, False), ('own_fmt_l', 9.99, 100, False, True),
        ('own_fmt_l', 1.0, 1000, False, False), ('own_fmt_l', 0.999, 1000, False, True),
        ('own_fmt_l', 1.0e6, 10000, False, False), ('own_fmt_l', 1.0001e6, 100000, False, True),
    ]
    for name, v, f, ol, mark in rows:
        t, u, i, mk = fmt(rig, name, v, f)
        what = '%s(%g) at %d Hz' % (name, v, f)
        check((t == '0L  ') == ol, '%s: text %r, OL expected %r' % (what, t, ol))
        if ol:
            check(u == '' and i == 0 and mk == 0, '%s: OL with unit %r index %d marker %d' % (what, u, i, mk))
        else:
            check(mk == int(mark), '%s: marker %d, expected %d' % (what, mk, mark))
    for bits in (0x7F800000, 0xFF800000, 0x7FC00000):
        rig.wr(TXT, bytes(16))
        fcall_bits(rig, 'own_fmt_r', bits)
        check(cstr(rig, TXT) == '0L  ', 'own_fmt_r(0x%08X): %r, not OL' % (bits, cstr(rig, TXT)))
    # theta and D / Q never carry the marker
    for name, v in (('own_fmt_th', -45.0), ('own_fmt_d', 0.5), ('own_fmt_q', 0.5)):
        t, u, i, mk = fmt(rig, name, v, 60)
        check(mk == 0, '%s at 60 Hz: marker %d' % (name, mk))
    # the row marker (fmt.s own_row_draw): one amber multiply cover per glyph, no image recolour
    rig.wr(V_FREQ, 1000)
    c47 = entry_hook(rig, 'fn_080265dc')
    c48 = entry_hook(rig, 'fn_080265f4')
    hide = entry_hook(rig, 'fn_08023050', (UC_ARM_REG_R0, UC_ARM_REG_R1))
    show = entry_hook(rig, 'fn_08023558', (UC_ARM_REG_R0, UC_ARM_REG_R1))
    made = entry_hook(rig, 'fn_08023678', (UC_ARM_REG_R0,))
    amber = fcall(rig, 'rgb_to_565_0801d792', 0xFD, 0xD0, 0x1B) & 0xFFFF
    objs = [rig.rd(GLYPHS + 4 * i) for i in range(7)]
    check(all(objs), 'row 0 glyph objects %r' % [hex(o) for o in objs])
    # the shared rig stops at the main loop just after its first row-0 draw, of the value 0 ohm
    # (marked: below 10 mohm), so covers can exist; an unmarked draw first hides any
    rig.wr(TXT, b'-1.2345\x00')
    rig.wr(OWN_FUNC + MF['MARK'], 0)
    fcall(rig, 'own_row_draw', 0, TXT)
    del hide[:], show[:], made[:]
    before = [cover(rig, g) for g in objs]
    check(mf(rig, 'ROW0') == 0 and all(n == 0 or (n == 1 and rig.rd(c + 0x1C) & 1) for n, c in before),
          'row 0 before the marker: MF_ROW0 %d, children %r' % (mf(rig, 'ROW0'), before))
    rig.wr(TXT, b'-1.2345\x00')
    rig.wr(OWN_FUNC + MF['MARK'], 1)
    fcall(rig, 'own_row_draw', 0, TXT)
    cov = [cover(rig, g) for g in objs]
    check([m[1] for m in made] == [g for g, (n, c) in zip(objs, before) if not n] and all(n == 1 for n, c in cov)
          and all(c == c0 for (n, c), (n0, c0) in zip(cov, before) if n0), 'covers made %r, children %r, before %r'
          % (made, cov, before))
    for g, (n, c) in zip(objs, cov):
        size = tuple(fcall(rig, 'fn_08024bac', c, 0, k) & 0xFFFF for k in (1, 4))
        wh = rig.rd(g + 0x2C)                                 # halfwords +0x2C width, +0x2E height
        check(size == (wh & 0xFFFF, wh >> 16), 'cover 0x%X size %r, glyph image 0x%08X' % (c, size, wh))
        style = tuple(fcall(rig, 'fn_08024bac', c, 0, k) & 0xFFFF for k in (0x20, 0x21, 0x0B, 0x32, 0x67))
        check(style == (amber, 0xFF, 0, 0, 3) and not rig.rd(c + 0x1C) & 1,
              'cover 0x%X: keys 0x20 0x21 0x0B 0x32 0x67 %r, flags 0x%X' % (c, style, rig.rd(c + 0x1C)))
    check(not c47 and not c48, 'image recolour keys set: %r %r' % (c47, c48))
    check(mf(rig, 'ROW0') == 1 and mf(rig, 'MARK') == 0, 'MF_ROW0 %d, MF_MARK %d' % (mf(rig, 'ROW0'), mf(rig, 'MARK')))
    check([(o, m) for _, o, m in show] == [(c, 1) for (n, c), (n0, c0) in zip(cov, before) if n0],
          'shown again %r (the hidden covers of before)' % show)
    del show[:]
    fcall(rig, 'own_row_draw', 0, TXT)                        # MF_MARK 0 now: covers hidden
    check([(o, m) for _, o, m in hide] == [(c, 1) for n, c in cov] and all(rig.rd(c + 0x1C) & 1 for n, c in cov),
          'hide calls %r' % hide)
    check(mf(rig, 'ROW0') == 0, 'MF_ROW0 %d after the switch-off' % mf(rig, 'ROW0'))
    del hide[:]
    fcall(rig, 'own_row_draw', 0, TXT)
    check(not hide and not show, 'unmarked row touched again: %r %r' % (hide, show))
    rig.wr(OWN_FUNC + MF['MARK'], 1)
    fcall(rig, 'own_row_draw', 0, TXT)                        # marked again: the same covers shown
    check(len(made) == sum(not n for n, c in before) and [cover(rig, g) for g in objs] == cov
          and [(o, m) for _, o, m in show] == [(c, 1) for n, c in cov], 'second marker: made %d, shown %r'
          % (len(made), show))
    # 6 characters: place 6 shows the blank image d_08036040 (fn_0800d14c index 13), its cover is hidden
    rig.wr(TXT, b'1.2345\x00')
    rig.wr(OWN_FUNC + MF['MARK'], 1)
    fcall(rig, 'own_row_draw', 0, TXT)
    check(rig.rd(objs[6] + 0x24) == rig.s['d_08036040'] and rig.rd(cov[6][1] + 0x1C) & 1
          and not any(rig.rd(c + 0x1C) & 1 for n, c in cov[:6]), 'blank place: image 0x%X, cover flags %r'
          % (rig.rd(objs[6] + 0x24), [rig.rd(c + 0x1C) & 1 for n, c in cov]))
    fcall(rig, 'own_row_draw', 0, TXT)                        # MF_MARK 0: leave the shared rig unmarked
    NOTES.append('f20: %d limit rows, NaN / +-Inf OL, 7 covers (%d made here, amber 0x%04X), hidden and shown '
                 'again, none over the blank image' % (len(rows), len(made), amber))
    rig.watch.check(what='f20')
    return True


def cover(rig, g):
    """(child count, child 0) of object g: word [g + 8] = attribute block, children list +0, count +4
    (fn_080233c4, fn_08023da4); (0, 0) without a block or a child."""
    blk = rig.rd(g + 8)
    if not blk:
        return (0, 0)
    n = rig.rd(blk + 4)
    return (n, rig.rd(rig.rd(blk)) if n else 0)


# ---------------------------------------------------------------- f21 signs (formatter part)

@case
def f21_signs():
    """m21 (S2.2; MEASUREMENT_FIX_DESIGN revision 14 rule 1, which corrects revision 13's "every negative
    is 0"): a negative value by its quantity, with 0x200011EC = 0 (series) and = 1 (parallel): series R
    (main row and secondary R), parallel C and series L are the vendor formatter's text of 0 (marked);
    parallel R, series C and parallel L are OL ("0L  ", unit empty, index 0, not marked); D is 0 and Q OL
    in both modes (never marked); X and theta negative get one '-' (X through own_fmt_x, the
    wrapper of the X call 0x0800D32A, with or without 0x20001198 = 2; own_fmt_r ignores that word); the
    secondary R takes 0x200050B8 (own_fmt_rs ignores the s0 its caller made absolute); every text fits 7
    characters; then the host record: Func R on z = -1 + j100 ohm at 1 kHz (TDut as m10; series, the
    record's byte 40 = 0, input check), the MEASURE main text equals the text the display drew on row 0, is
    the 0 of R, and the value field keeps the negative R."""
    rig = base_rig()
    wf(rig, V_Z, 1000.0)                                      # rule 2 off (1 kHz anyway)
    rig.wr(V_MAIN_ROW, bytes([1]))                            # main row R: fmt_dq's C / L rule (f31 c) off
    # Expected texts, from the ui_42.s headers:
    # - R below 0 -> 0: fn_0800e028 on +0.0: bits 0 < 0x40ffff97 -> "%0.4f" -> "0.0000", unit ce a9, index 5;
    # - C below 0 -> 0: fn_0800db24 on +0.0: bits 0 not above 0xbb03126f (no OL), 0 < 0x3f4ccccd -> 0 * 1000
    #   with "%0.1f" -> "0.0", unit "pF", index 1 (also for -6.9163e6 nF, which unsigned would be 6.916 mF);
    # - both 0 counts (fmt_reduce keeps them) and marked: 0 lies below the 1 kHz lower limits 10 mohm / 1 pF;
    # - L below 0 -> 0: fn_0800de2c on +0.0: below 80 (0x42a00000) -> "%0.1f" -> "0.0", unit "uH", index 3;
    #   marked (0 below the 1 kHz lower limit 1 uH);
    # - D below 0 -> 0: fn_0800dd44 on +0.0: below 10 (0x41200000) -> "%0.4f" -> "0.0000", unit empty,
    #   index 0; never marked (no accuracy-table entry);
    # - OL (fmt.s .Lfc_ol): "0L  ", the 5th byte 0 (fmt() cleared the rest), unit text empty, index 0,
    #   MF_MARK 0;
    # - X -12.3456: |X| in [7.99995 (0x40ffff97), 79.9995) -> "%0.3f" "12.346", 12,346 counts, '-';
    #   X -0.0001: < 7.99995 -> "%0.4f" "0.0001", '-' -> "-0.0001".
    zero_r, zero_c, zero_l = ('0.0000', '\xce\xa9', 5, 1), ('0.0', 'pF', 1, 1), ('0.0', 'uH', 3, 1)
    zero_dq, ol = ('0.0000', '', 0, 0), ('0L  ', '', 0, 0)
    # (series / parallel word, formatter, value, expected)
    rows = []
    for sp in (0, 1):
        r, c, l_ = (zero_r, ol, zero_l) if sp == 0 else (ol, zero_c, ol)
        rows += [(sp, 'own_fmt_r', -1.5, r), (sp, 'own_fmt_c', -0.0005, c), (sp, 'own_fmt_r', -79.999, r),
                 (sp, 'own_fmt_c', -0.799, c), (sp, 'own_fmt_r', -0.0001, r), (sp, 'own_fmt_c', -6.9163e6, c),
                 (sp, 'own_fmt_l', -100.0, l_), (sp, 'own_fmt_l', -79.9, l_), (sp, 'own_fmt_l', -2.0e6, l_),
                 (sp, 'own_fmt_d', -0.0123, zero_dq), (sp, 'own_fmt_d', -2000.0, zero_dq),
                 (sp, 'own_fmt_q', -0.0123, ol), (sp, 'own_fmt_q', -2000.0, ol),
                 (sp, 'own_fmt_z', -1.5, zero_r)]
    for sp, name, v, (want, wunit, widx, wmk) in rows:
        rig.wr(V_SERPAR, sp)
        t, u, i, mk = fmt(rig, name, v, 1000)
        raw = rig.rd(TXT, 8)
        check(t == want and u == wunit and i == widx and mk == wmk and raw == t.encode() + bytes(8 - len(t)),
              '%s(%g) with 0x200011EC = %d: %r %r index %d marker %d (8 bytes %s), expected %r %r %d marker %d'
              % (name, v, sp, t, u, i, mk, raw.hex(), want, wunit, widx, wmk))
    rig.wr(V_SERPAR, 0)
    for name, v, want in (('own_fmt_x', -12.3456, '-12.346'), ('own_fmt_x', -0.0001, '-0.0001'),
                          ('own_fmt_th', -45.0, '-45.00')):
        t = fmt(rig, name, v, 1000)[0]
        check(t == want and len(t) <= 7, '%s(%g): %r, expected %r' % (name, v, t, want))
    rig.wr(V_SIGN_MODE, 2)                                    # as the X row sets it around its call
    tx = fmt(rig, 'own_fmt_x', -12.3456, 1000)[0]
    tr = fmt(rig, 'own_fmt_r', -12.3456, 1000)[0]
    rig.wr(V_SIGN_MODE, 0)
    check(tx == '-12.346' and tr == '0.0000', 'with 0x20001198 = 2: X %r (one sign), R %r (0)' % (tx, tr))
    wf(rig, V_R, -0.05)
    t = fmt(rig, 'own_fmt_rs', 0.05, 1000)[0]
    check(t == '0.0000', 'secondary R -0.05 from 0x200050B8 (series): %r' % t)
    rig.wr(V_SERPAR, 1)
    t = fmt(rig, 'own_fmt_rs', 0.05, 1000)[0]
    rig.wr(V_SERPAR, 0)
    check(t == '0L  ', 'secondary R -0.05 from 0x200050B8 (parallel): %r' % t)
    wf(rig, V_R, 0.0123)
    t = fmt(rig, 'own_fmt_rs', 0.05, 1000)[0]
    check(t == '0.0123', 'secondary R 0.0123 from 0x200050B8 (s0 0.05): %r' % t)
    rig.watch.check(what='f21 formatters')
    # the host record against the display
    z = complex(-1, 100)
    hr = own_rig(DutSource(z=lambda f, zz=z: zz, counts_per_volt=4095 / 3.3), usb=True)
    rows0 = []
    a = hr.s['own_row_draw'] & ~1

    def rowdraw(uc, addr, size, user):
        if uc.reg_read(UC_ARM_REG_R0) == 0:
            rows0.append(bytes(uc.mem_read(uc.reg_read(UC_ARM_REG_R1), 8)).split(b'\x00')[0])
    hr.m.uc.hook_add(UC_HOOK_CODE, rowdraw, begin=a, end=a)
    hr.ask_ok('LCR_SET', bytes([0, 1]))                      # Func R: main row R, secondary X
    hr.run(2.0)
    d = hr.ask_ok('MEASURE', size=M.T.MEASURE_SIZE)
    check(d[40] == 0, 'MEASURE series / parallel %d (input: |Z| about 100 ohm is series, S2.6)' % d[40])
    text = d[16:24].split(b'\x00')[0]
    check(d[8] == 1 and rows0 and text == rows0[-1], 'MEASURE main row %d text %r, display %r' % (d[8], text, rows0[-1:]))
    value = struct.unpack_from('<f', d, 9)[0]
    check(text == b'0.0000' and value < 0 and list(d[13:16]) == [1, 4, 0],
          'negative R: text %r, value %r, unit / decimals / validity %r (expected 0.0000, the signed value, '
          '1 4 0)' % (text, value, list(d[13:16])))
    # bit 0: the 0 shown lies below 10 mohm (marked); bit 1: X about 100 ohm lies in the 1 kHz column
    check(d[64] == 1, 'marker byte %d for R about -1 ohm (shown 0) and X about 100 ohm at 1 kHz' % d[64])
    NOTES.append('f21: R of z = -1 + j100 shown %r on the display and in MEASURE' % text)
    hr.watch.check(what='f21 record')
    return True


# ---------------------------------------------------------------- f22 D / Q at the extremes

@case
def f22_dq_extremes():
    """m22 (S2.3 / S1.8): D or Q of +Inf (Xs = 0 for D, Rs = 0 for Q) is "0L" (fn_0800dd44's own OL at
    1e5 and above), 0 is "0.0000", through both wrappers own_fmt_d and own_fmt_q (the frequency word
    1000: rule 2 of revision 14 does not act)."""
    rig = base_rig()
    rig.wr(V_FREQ, 1000)
    rig.wr(V_MAIN_ROW, bytes([1]))                            # main row R: fmt_dq's C / L rule (f31 c) off
    for name in ('own_fmt_d', 'own_fmt_q'):
        rig.wr(TXT, bytes(16))
        fcall_bits(rig, name, 0x7F800000)
        check(cstr(rig, TXT) == '0L  ', '%s(+Inf): %r' % (name, cstr(rig, TXT)))
        t = fmt(rig, name, 0.0)[0]
        check(t == '0.0000', '%s(0): %r' % (name, t))
    rig.watch.check(what='f22')
    return True


# ---------------------------------------------------------------- f23 digits

@case
def f23_digits():
    """m23 (S2.4, D5): 19,999 / 20,000 counts in each vendor format range: the text keeps its decimals at
    19,999 and drops one at 20,000 (in the unit the vendor formatter chose); D through own_fmt_d, Q through
    own_fmt_q (the same vendor formatter and S2.4 rule; positive values, so the revision-14 sign rule and
    the series / parallel word do not act; 1 kHz, so rule 2 does not act; main row R, so the revision-15
    rule of fmt_dq does not act)."""
    rig = base_rig()
    rig.wr(V_MAIN_ROW, bytes([1]))
    rows = [('own_fmt_r', 1.9999, '1.9999'), ('own_fmt_r', 2.0, '2.000'), ('own_fmt_r', 19.999, '19.999'),
            ('own_fmt_r', 20.0, '20.00'), ('own_fmt_r', 199.99, '199.99'), ('own_fmt_r', 200.0, '200.0'),
            ('own_fmt_r', 1999.9, '1.9999'), ('own_fmt_r', 2000.0, '2.000'),
            ('own_fmt_c', 1.9999, '1.9999'), ('own_fmt_c', 2.0, '2.000'), ('own_fmt_c', 20.0, '20.00'),
            ('own_fmt_c', 200.0, '200.0'), ('own_fmt_c', 2000.0, '2.000'),
            ('own_fmt_l', 199.99, '199.99'), ('own_fmt_l', 200.0, '200.0'), ('own_fmt_l', 2000.0, '2.000'),
            ('own_fmt_l', 2.0e6, '2.000'),
            ('own_fmt_d', 1.9999, '1.9999'), ('own_fmt_d', 2.0, '2.000'), ('own_fmt_d', 9.9999, '10.000'),
            ('own_fmt_d', 20.0, '20.00'), ('own_fmt_d', 200.0, '200.0'), ('own_fmt_d', 2000.0, '2000'),
            ('own_fmt_d', 20000.0, '20000'),
            ('own_fmt_q', 1.9999, '1.9999'), ('own_fmt_q', 2.0, '2.000'), ('own_fmt_q', 20.0, '20.00'),
            ('own_fmt_q', 20000.0, '20000')]
    for name, v, want in rows:
        t = fmt(rig, name, v, 1000)[0]
        check(t == want, '%s(%g): %r, expected %r' % (name, v, t, want))
    # revision 12 (MEASUREMENT_FIX_DESIGN S2.4): C in the vendor's "%0.1f" uF range above 19,999 counts goes
    # to mF with 3 decimals (a text without '.' lies over the unit picture, fn_0800d14c), and no byte of the
    # vendor's longer text is left after the terminating 0 (fmt() clears the buffer, the vendor writes it);
    # the negative C of this list (-6.9163e6 nF) is OL in series and 0 in parallel since revision 14 (rule
    # 1) and is a row of f21
    units = [('own_fmt_c', 1.9999e6, '1999.9', 'uF', 3), ('own_fmt_c', 2.0e6, '2.000', 'mF', 4),
             ('own_fmt_c', 6.9163e6, '6.916', 'mF', 4), ('own_fmt_c', 7.9999e6, '8.000', 'mF', 4),
             ('own_fmt_c', 8.0e6, '8.00', 'mF', 4),
             ('own_fmt_d', 2000.0, '2000', '', None), ('own_fmt_q', 7000.0, '7000', '', None)]
    for name, v, want, wunit, widx in units:
        t, u, i, _ = fmt(rig, name, v, 1000)
        raw = rig.rd(TXT, 8)
        check(t == want and raw == t.encode() + bytes(8 - len(t)),
              '%s(%g): %r (8 bytes %s), expected %r and zeros' % (name, v, t, raw.hex(), want))
        if widx is not None:
            check(u == wunit and i == widx, '%s(%g): unit %r index %d, expected %r %d' % (name, v, u, i, wunit, widx))
    NOTES.append('f23: %d texts at 19,999 / 20,000 counts, %d unit / padding rows' % (len(rows), len(units)))
    rig.watch.check(what='f23')
    return True


# ---------------------------------------------------------------- f24 AUTO

@case
def f24_auto():
    """m24 (S2.5, D3): a theta sweep down and up through -T / +T: R -> C only below -11, C -> R only above
    -9; R -> L only above 11, L -> R only below 9; undecided decides with T alone; C or L without its
    validity window goes to R; the -400 set keeps the class; the main row / secondary / picture follow
    (R 1 / 4 theta, C 2 / 2, L 3 / 3); a frequency change in the running rig resets the class."""
    rig = base_rig()
    pics = entry_hook(rig, 'fn_08021c14')
    wf(rig, V_CS, 10.0)                       # 10 nF: inside 0.5 pF .. 0.2 F
    wf(rig, V_L, 1000.0)                      # 1 mH: inside 0.5 uH .. 1e8 uH
    rig.wr(V_FUNC, 0)

    def step(th, cls=None):
        if cls is not None:
            rig.wr(OWN_FUNC + MF['AUTO'], cls)
        wf(rig, V_TH, th)
        fcall(rig, 'own_auto_class')
        return mf(rig, 'AUTO')
    seq = [(None, 0.0, 1), (None, -10.5, 1), (None, -11.5, 2), (None, -9.5, 2), (None, -8.5, 1),
           (None, 10.5, 1), (None, 11.5, 3), (None, 9.5, 3), (None, 8.5, 1),
           (0, -10.5, 2), (0, 10.5, 3), (0, 9.9, 1), (2, 50.0, 1), (3, -50.0, 1), (2, -400.0, 2), (0, -400.0, 1)]
    for cls, th, want in seq:
        got = step(th, cls)
        check(got == want, 'theta %.1f from class %r: class %d, expected %d' % (th, cls, got, want))
    sec = {1: 4, 2: 2, 3: 3}
    for cls_from, th, want in ((1, -11.5, 2), (2, 0.0, 1), (1, 11.5, 3)):
        del pics[:]
        step(th, cls_from)
        check(rig.rd8(V_MAIN_ROW) == want and rig.rd(V_SECONDARY) == sec[want], 'class %d: main %d secondary %d'
              % (want, rig.rd8(V_MAIN_ROW), rig.rd(V_SECONDARY)))
        pic = {1: 'd_0803d2fc', 2: 'd_0803d3d4', 3: 'd_0803d584'}[want]
        check(pics and pics[-1][2] == rig.s[pic], 'class %d: picture %r' % (want, pics[-1:]))
    wf(rig, V_CS, 1.0e-4)                     # 0.1 pF: C not valid
    check(step(-30.0, 2) == 1 and step(-30.0, 1) == 1, 'C without its validity window')
    rig.watch.check(what='f24 direct')
    # the reset at a setting change, in a running rig
    r2 = own_rig(DutSource('R', 1000.0))
    r2.run(1.5)
    check(mo(r2, 'SEQ') > 0 and r2.rd(OWN_FUNC + MF['AUTO']) == 1, 'AUTO class %d after the first windows'
          % r2.rd(OWN_FUNC + MF['AUTO']))
    r2.wr(V_FREQ, 10000)
    r2.run(0.03)
    check(r2.rd(OWN_FUNC + MF['AUTO']) == 0 and r2.rd(OWN_FUNC + MF['SP']) == 0,
          'after the frequency change: AUTO %d, series / parallel %d' % (r2.rd(OWN_FUNC + MF['AUTO']), r2.rd(OWN_FUNC + MF['SP'])))
    r2.watch.check(what='f24 reset')
    return True


# ---------------------------------------------------------------- f25 series / parallel

@case
def f25_serpar():
    """m25 (S2.6, D4): meas_serpar on a |Z| sweep up and down through 1 k / 10 k: series stays up to
    10 k, parallel stays down to 1 k; undecided: series up to 3162.28, parallel above."""
    rig = base_rig()

    def sp(z, state=None):
        if state is not None:
            rig.wr(OWN_FUNC + MF['SP'], state)
        return fcall(rig, 'meas_serpar', s22=z), mf(rig, 'SP')
    want = [(0, 3000.0, 0), (0, 3200.0, 1)]
    for st, z, par in want:
        r, s = sp(z, st)
        check(r == par and s == 2 - (par == 0), 'undecided, |Z| %.0f: %d (state %d)' % (z, r, s))
    rig.wr(OWN_FUNC + MF['SP'], 1)
    up = [(500.0, 0), (5000.0, 0), (9999.0, 0), (10001.0, 1), (20000.0, 1)]
    down = [(9999.0, 1), (1001.0, 1), (999.0, 0), (500.0, 0), (9999.0, 0)]
    for z, par in up + down:
        r, s = sp(z)
        check(r == par, '|Z| %.0f: %s, expected %s' % (z, 'parallel' if r else 'series', 'parallel' if par else 'series'))
    rig.watch.check(what='f25')
    return True


# ---------------------------------------------------------------- f26 hold

@case
def f26_hold():
    """m26 (S2.7, D1 / D2): under hold the output words stay and windows keep closing (MO_SEQ); each of
    frequency, level, bias, range, speed and circuit ends hold (ds_hold(0) from meas_hold: the HOLD object
    hidden, the restart request); Func and secondary do not."""
    rig = own_rig(DutSource('R', 1000.0))
    rig.run(1.5)
    check(rig.probe.normal(), 'f26: no window before hold')
    offs = entry_hook(rig, 'ds_hold', regs=(UC_ARM_REG_R0, UC_ARM_REG_LR))
    fcall(rig, 'ds_hold', 1)
    check(rig.rd(V_HOLD) == 1, 'hold not set')
    words = {k: rig.rd(a) for k, a in M.WORDS.items()}
    seq0, npub = mo(rig, 'SEQ'), len(rig.probe.pubs)
    rig.run(1.2)
    check(mo(rig, 'SEQ') >= seq0 + 2, 'windows under hold: %d -> %d' % (seq0, mo(rig, 'SEQ')))
    check(len(rig.probe.pubs) == npub, 'published under hold')
    check({k: rig.rd(a) for k, a in M.WORDS.items()} == words, 'output words changed under hold')
    check(mf(rig, 'HOLDP') == 1, 'hold not latched')
    ends = []
    changes = [('frequency', V_FREQ, 10000), ('level', V_LEVEL, 0x3E99999A), ('bias', V_BIAS, 0x3F000000),
               ('range', V_RANGE, 1), ('speed', V_SPEED, 2), ('circuit', V_CIRCUIT, 1)]
    for name, addr, v in changes:
        if rig.rd(V_HOLD) == 0:
            fcall(rig, 'ds_hold', 1)
        rig.run(0.05)
        check(mf(rig, 'HOLDP') == 1, '%s: hold not latched' % name)
        old = rig.rd(addr)
        del offs[:]
        rig.wr(addr, v)
        rig.run(0.05)
        check(rig.rd(V_HOLD) == 0, '%s change: hold stays' % name)
        lo, hi = M.func_ranges(rig.s)['meas_hold']
        check(any(r0 == 0 and lo <= (lr & ~1) < hi for _, r0, lr in offs), '%s: ds_hold(0) not from meas_hold %r'
              % (name, offs))
        rig.wr(addr, old)
        rig.run(0.05)
        ends.append(name)
    fcall(rig, 'ds_hold', 1)
    rig.run(0.05)
    for name, addr, v in (('Func', V_FUNC, 1), ('secondary', V_SECONDARY, 3)):
        old = rig.rd(addr)
        rig.wr(addr, v)
        rig.run(0.05)
        check(rig.rd(V_HOLD) == 1, '%s change ended hold' % name)
        rig.wr(addr, old)
    NOTES.append('f26: windows under hold %d -> %d, hold ended by %s' % (seq0, mo(rig, 'SEQ'), ', '.join(ends)))
    rig.watch.check(what='f26')
    return True


# ---------------------------------------------------------------- f27 compare judgement, f28 tolerance

def judge(rig, v, nom=1000.0, z=None, th=0.0, prev=None, consecutive=True, latch=1, freq=1000):
    """own_cmp_judge on crafted words (screen 2 rig stopped): compare value v, nominal, |Z| (default v),
    theta, the previous publish (prev, None: no valid previous); returns MF_RES."""
    rig.wr(V_FREQ, freq)
    wf(rig, V_CMPV, v)
    wf(rig, V_NOMINAL, nom)
    wf(rig, V_Z, abs(v) if z is None else z)
    wf(rig, V_TH, th)
    rig.wr(OBJS + 1, bytes([latch]))
    seq = mf(rig, 'PSEQ')
    if prev is None:
        rig.wr(OWN_FUNC + MF['PVOK'], 0)
    else:
        rig.wr(OWN_FUNC + MF['PVOK'], 1)
        wf(rig, OWN_FUNC + MF['PREV'], prev)
        rig.wr(OWN_FUNC + MF['PVSEQ'], (seq - (1 if consecutive else 2)) & 0xFFFFFFFF)
    fcall(rig, 'own_cmp_judge')
    return mf(rig, 'RES')


def tol(rig, mode, lo=0, hi=0, letter=b'\x00', skind=0, sval=0.0, n=15):
    p = struct.pack('<BiicBf', mode, lo, hi, letter, skind, sval)[:n]
    rig.wr(TXT, p + bytes(16))
    return fcall(rig, 'own_tol_set', TXT, n)


@case
def f27_compare():
    """m27 (S2.8): on screen 2 with nominal 1000 ohm, 5 %, WarnType 0 (alarm on NG), sound and LED on (the
    block defaults): a 1 kohm part is counted once (pass), shown "---" until two windows agree, then "IN";
    removed (no current: the no-reading set) it shows "---" and the latch clears; a 1.2 kohm part is
    counted as fail with the alarm: LED PB13 high / PB12 low held, two beeps of 200 ms with 150 ms
    between them stepped by own_cmp_step while the main loop runs; counters saturate at 999; long key
    0x100 resets them once per hold; out of range above the presence limit; nothing NaN."""
    marks = [1e9, 1e9]                                        # removal, second insertion (emulated s)

    def zt(f, t):
        return 1000.0 if t < marks[0] else 1e15 if t < marks[1] else 1200.0
    rig = own_rig(TDut(zt, counts_per_volt=4095 / 3.3), usb=True)
    texts = entry_hook(rig, 'fn_080228d0')
    # the LED and beeper calls of cmp.s only (the vendor's key beep fn_08008120 also reaches
    # fn_0800c6ec): kept when the return address lies in cmp_led, cmp_alarm or own_cmp_step
    rngs = [M.func_ranges(rig.s)[n] for n in ('cmp_led', 'cmp_alarm', 'own_cmp_step')]
    regs = (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_LR)
    leds_all = entry_hook(rig, 'fn_08008350', regs=regs)
    beeps_all = entry_hook(rig, 'fn_0800c6ec', regs=regs)

    class Own(list):
        """A view of the entries whose LR lies in cmp.s (time, r0, r1, r2)."""
        def __init__(self, src):
            super().__init__()
            self.src = src

        def __iter__(self):
            return iter([x[:4] for x in self.src if any(lo <= (x[4] & ~1) < hi for lo, hi in rngs)])

        def __delitem__(self, k):
            del self.src[k]
    leds, beeps = Own(leds_all), Own(beeps_all)
    loops = []
    rig.m.uc.hook_add(UC_HOOK_CODE, lambda uc, a, s, u: loops.append(rig.m.now()), begin=MAIN_LOOP, end=MAIN_LOOP)
    p0, f0 = rig.rd(V_PASS), rig.rd(V_FAIL)                  # screen 1: nothing judged yet
    t0 = rig.m.now()
    marks[0] = t0 + 4.5
    marks[1] = marks[0] + 4.0
    rig.press(KEY_HOLD, 1200)                                 # long 0x400: screen 1 -> 2
    check(rig.rd(V_SCREEN) == 2, 'screen %d' % rig.rd(V_SCREEN))
    st, d = rig.ask('TOL_SET', struct.pack('<BiicBf', 0, 0, 0, b'\x00', 0, 0.0))
    check(st == S_OK and len(d) == M.T.COMPARE_SIZE, 'TOLERANCE_SET mode 0: status %d, %d bytes' % (st, len(d)))
    st, d = rig.ask('TOL_SET', b'\x01\x00')
    check(st == S_BAD_ARG and len(d) == M.T.COMPARE_SIZE, 'short TOLERANCE_SET: status %d, %d bytes' % (st, len(d)))
    obj_res, obj_fail = rig.rd(OBJS + 0x40), rig.rd(OBJS + 0x3C)
    rig.run(marks[0] - rig.m.now())
    check(rig.rd(V_PASS) == p0 + 1 and rig.rd(V_FAIL) == f0, 'insertion 1: pass %d -> %d, fail %d -> %d'
          % (p0, rig.rd(V_PASS), f0, rig.rd(V_FAIL)))
    res_txt = [cstr(rig, r2) for t, r0, r1, r2 in texts if r0 == obj_res and t > t0]
    check(res_txt and res_txt[0] == '---' and res_txt[-1] == 'IN', 'result texts %r' % res_txt)
    check(mf(rig, 'RES') == CR_IN and rig.rd8(OBJS + 1) == 1, 'result %d latch %d' % (mf(rig, 'RES'), rig.rd8(OBJS + 1)))
    check(not [x for x in leds if x[0] > t0] and not [x for x in beeps if x[0] > t0], 'alarm on IN with WarnType 0')
    rig.run(marks[1] - rig.m.now())
    check(mf(rig, 'RES') == CR_NONE and rig.rd8(OBJS + 1) == 0, 'removed: result %d latch %d' % (mf(rig, 'RES'), rig.rd8(OBJS + 1)))
    del leds[:], beeps[:], loops[:]
    t2 = rig.m.now()
    rig.run(3.5)
    check(rig.rd(V_FAIL) == f0 + 1 and rig.rd(V_PASS) == p0 + 1, 'insertion 2: fail %d pass %d' % (rig.rd(V_FAIL), rig.rd(V_PASS)))
    check(mf(rig, 'RES') == CR_HI, 'insertion 2: result %d' % mf(rig, 'RES'))
    lv = [(r1, r2) for _, r0, r1, r2 in leds if r0 == GPIOB and r1 in (0x1000, 0x2000)]
    check(lv == [(0x2000, 1), (0x1000, 0)], 'LED writes %r (PB13 high, PB12 low expected, held)' % lv)
    bp = [(t, r1) for t, r0, r1, _ in beeps if r0 == TIM2]
    vol = rig.rd16(0x20001160)
    check([v for _, v in bp] == [vol, 0, vol, 0], 'beeper writes %r (volume %d)' % (bp, vol))
    on1, off1, on2, off2 = [t for t, _ in bp]
    # tick 10 ms, and a step waits for the next pass of ctl_loop: a pass with the publish's display
    # update takes about 0.12 s in the model (design revision 5 item 10)
    check(0.195 <= off1 - on1 <= 0.34 and 0.145 <= on2 - off1 <= 0.29 and 0.195 <= off2 - on2 <= 0.34,
          'beep times %.3f / %.3f / %.3f s' % (off1 - on1, on2 - off1, off2 - on2))
    passes = [t for t in loops if on1 < t < off2]
    check(len(passes) >= 3, 'main loop passes during the beeps: %d' % len(passes))
    fail_txt = [r2 for t, r0, r1, r2 in texts if r0 == obj_fail and t > t2]
    check(fail_txt and fail_txt[-1] == f0 + 1, 'fail counter text %r' % fail_txt)
    # direct checks in the stopped rig: saturation, the reset key, out of range, NaN
    rig.wr(V_FAIL, 999)
    check(judge(rig, 1200.0, prev=1200.0, latch=0) == CR_HI and rig.rd(V_FAIL) == 999, 'fail at 999: %d' % rig.rd(V_FAIL))
    rig.wr(V_PASS, 999)
    check(judge(rig, 1000.0, prev=1000.0, latch=0) == CR_IN and rig.rd(V_PASS) == 999, 'pass at 999: %d' % rig.rd(V_PASS))
    rig.wr(V_KEY_BUSY, bytes(2))
    fcall(rig, 'own_cmp_key', 0xFE, 0x200)
    check(rig.rd(V_PASS) == 999, 'mask 0x200 reset the counters')
    fcall(rig, 'own_cmp_key', 0xFE, 0x100)
    check(rig.rd(V_PASS) == 0 and rig.rd(V_FAIL) == 0 and rig.rd16(V_KEY_BUSY) == 1, 'reset: %d / %d busy %d'
          % (rig.rd(V_PASS), rig.rd(V_FAIL), rig.rd16(V_KEY_BUSY)))
    rig.wr(V_PASS, 5)
    fcall(rig, 'own_cmp_key', 0xFE, 0x100)
    check(rig.rd(V_PASS) == 5, 'a second reset in the same hold')
    check(judge(rig, 5.0e5, freq=100000) == CR_OUT, '500 kohm at 100 kHz: not "out of range"')
    check(judge(rig, 1.0e10, z=1.0e10, th=-400.0) == CR_NONE, 'the -400 set: not "no part"')
    check(judge(rig, 5.0e7, freq=1000) == CR_NONE, '50 Mohm (above the measurement range): not "no part"')
    for k in ('DEV', 'ELO', 'EHI', 'PREV'):
        b = mf(rig, k)
        check(not ((b & 0x7F800000) == 0x7F800000 and b & 0x7FFFFF), 'MF_%s NaN' % k)
    NOTES.append('f27: beeps %.3f / %.3f / %.3f s with %d main-loop passes, counts pass %d fail %d'
                 % (off1 - on1, on2 - off1, off2 - on2, len(passes), p0 + 1, f0 + 1))
    rig.watch.check(what='f27')
    return True


@case
def f28_tolerance():
    """m28 (S2.9, D7): % limits (asymmetric), presets (Z, C as % and as pF below a 10 pF nominal), the pF
    mode only for C, the refusals, the secondary limit, stability (min(band / 4, 0.1 %) between consecutive
    publishes), the return to mode 0 when 0x20001188 changes; own_tol_set writes nothing outside OWN_FUNC
    and no flash; after a start the mode is 0 (own RAM is cleared by own_start), 0x20001188 is the saved
    block's word."""
    rig = base_rig()
    blk0 = rig.rd(0x2000057C, 0xC14)
    rig.wr(V_SCREEN, 2)                                      # the judgement runs on screen 2 only; with the
                                                             # latch 1 (judge) it counts nothing, so the
                                                             # screen-2 counter objects are not used
    ops0 = len(rig.flash_ops())
    rig.wr(V_CMP_TYPE, 1)
    check(tol(rig, 1, -500, 1000) == S_OK, 'mode 1 refused')
    for v, want in ((1080.0, CR_IN), (1120.0, CR_HI), (940.0, CR_LO), (950.0, CR_IN)):
        got = judge(rig, v, prev=v)
        check(got == want, 'mode -5 / +10 %%, v %.0f: %d, expected %d' % (v, got, want))
    check(abs(mff(rig, 'DEV') + 5.0) < 1e-4 and mf(rig, 'EMODE') == 1, 'deviation %r mode %d' % (mff(rig, 'DEV'), mf(rig, 'EMODE')))
    check(tol(rig, 3, letter=b'Z') == S_OK, 'letter Z refused')
    for v, want in ((1700.0, CR_IN), (1900.0, CR_HI), (790.0, CR_LO)):
        check(judge(rig, v, prev=v) == want, 'Z, v %.0f' % v)
    rig.wr(V_CMP_TYPE, 2)
    check(tol(rig, 3, letter=b'C') == S_OK, 'letter C refused')
    for v, want in ((0.0052, CR_IN), (0.0053, CR_HI), (0.0047, CR_LO)):
        got = judge(rig, v, nom=0.005, prev=v)
        check(got == want and mf(rig, 'EMODE') == 2, 'C at 5 pF, v %.4f nF: %d mode %d' % (v, got, mf(rig, 'EMODE')))
    for v, want in ((100.2, CR_IN), (100.3, CR_HI)):
        got = judge(rig, v, nom=100.0, prev=v)
        check(got == want and mf(rig, 'EMODE') == 1, 'C at 100 nF, v %.1f: %d mode %d' % (v, got, mf(rig, 'EMODE')))
    check(tol(rig, 2, -50, 50) == S_OK, 'pF mode for C refused')
    check(judge(rig, 0.0104, nom=0.010, prev=0.0104) == CR_IN and judge(rig, 0.0106, nom=0.010, prev=0.0106) == CR_HI,
          'pF mode +-0.5 pF')
    rig.wr(V_CMP_TYPE, 1)
    check(tol(rig, 2, -50, 50) == S_NOT_NOW, 'pF mode for R not refused')
    for p, what in (((1, 100, -100), 'lower above upper'), ((5,), 'mode 5'), ((3, 0, 0, b'A'), 'letter A'),
                    ((1, -10000, 100), 'lower below -99.99 %'), ((1, 0, 99991), 'upper above 999.9 %'),
                    ((0, 0, 0, b'\x00', 4), 'secondary kind 4'), ((0, 0, 0, b'\x00', 1, -1.0), 'negative limit')):
        check(tol(rig, *p) == S_BAD_ARG, '%s accepted' % what)
    check(tol(rig, 0, n=14) == S_BAD_ARG, '14 bytes accepted')
    # the secondary limit: D max 0.01
    check(tol(rig, 0, 0, 0, b'\x00', 1, 0.01) == S_OK, 'secondary D refused')
    wf(rig, V_D, 0.005)
    check(judge(rig, 1000.0, prev=1000.0) == CR_IN, 'D 0.005 under 0.01')
    wf(rig, V_D, 0.02)
    check(judge(rig, 1000.0, prev=1000.0) == CR_SEC, 'D 0.02 over 0.01')
    check(tol(rig, 0, 0, 0, b'\x00', 3, 5.0) == S_OK, 'secondary ESR refused')
    wf(rig, V_RS, 6.0)
    check(judge(rig, 1000.0, prev=1000.0) == CR_SEC, 'ESR 6 over 5')
    check(tol(rig, 0) == S_OK, 'mode 0 refused')
    # stability: 5 % -> min(1.25 %, 0.1 %) = 0.1 % of v
    check(judge(rig, 1000.5, prev=1000.0) == CR_IN, '0.05 % apart: not stable')
    check(judge(rig, 1002.0, prev=1000.0) == CR_UNST, '0.2 % apart: stable')
    check(judge(rig, 1000.0, prev=1000.0, consecutive=False) == CR_UNST, 'publishes not consecutive: stable')
    check(judge(rig, 1000.0) == CR_UNST, 'no previous publish: stable')
    # a change of 0x20001188 returns to mode 0
    check(tol(rig, 1, -100, 100) == S_OK and mf(rig, 'TMODE') == 1, 'mode 1')
    wf(rig, V_TOLERANCE, 2.0)
    judge(rig, 1000.0, prev=1000.0)
    check(mf(rig, 'TMODE') == 0 and mf(rig, 'EMODE') == 0 and mff(rig, 'EHI') == 2.0, 'mode %d after the vendor '
          'tolerance changed (limit %r)' % (mf(rig, 'TMODE'), mff(rig, 'EHI')))
    wf(rig, V_TOLERANCE, 5.0)
    # nothing written outside OWN_FUNC by own_tol_set (the block keeps its bytes except the words the
    # judge calls above wrote themselves: compare value, |Z|, theta, nominal, tolerance, D, Rs, counters)
    blk1 = rig.rd(0x2000057C, 0xC14)
    diff = [i for i in range(0, 0xC14, 4) if blk0[i:i + 4] != blk1[i:i + 4]]
    allowed = {a - 0x2000057C for a in (V_NOMINAL, V_TOLERANCE, V_CMP_TYPE, V_FREQ, V_SCREEN)}
    check(set(diff) <= allowed, 'block words written: %r' % [hex(0x2000057C + i) for i in diff if i not in allowed])
    check(len(rig.flash_ops()) == ops0, 'flash written')
    n = fcall(rig, 'rec_compare', TXT)
    rec = rig.rd(TXT, n)
    check(n == M.T.COMPARE_SIZE and rec[30] == 0 and rec[40] == mf(rig, 'RES'), 'COMPARE record %d bytes: %r' % (n, rec))
    NOTES.append('f28: modes 1 / 3 (Z, C % and pF) / 2, refusals, secondary D / ESR, stability, mode 0 on a '
                 'tolerance change')
    rig.watch.check(what='f28')
    return True


# ---------------------------------------------------------------- f29 60 Hz

@case
def f29_sixty_hertz():
    """F60 list (S2.12): LCR_SET frequency index 5 sets 60 Hz; TIM1 AR 18749, TIM6 AR 7999 and 150 DAC
    entries, the generator at 60 Hz; every calibration pointer lookup at 60 Hz asks for 100 Hz; the
    LCR_TABLES frequency list has 6 entries, index 5 = 60 "60Hz"; MEASURE reports 60 Hz and the marker
    (no accuracy column); at speed 2 every window holds at least 3 acquisitions; fn_0800a030 returns
    110,000,000 for 60 / 100 / 120 / 1000, 11,000,000 for 10 kHz, 1,100,000 for 100 kHz (V1.1 returns
    1,100,000 for 60: the control); the frequency key cycles 60 -> 100 -> 120 -> 1k -> 10k -> 100k -> 60
    and back, an unknown word and step 0 stay, fn_08009f10 after every step; the calibration start on
    screen 3 sets 100 Hz before any store."""
    rig = own_rig(DutSource('R', 1000.0), usb=True, freq=100)
    lut = entry_hook(rig, 'fn_080090a4')
    lst = rig.ask_ok('LCR_TABLES', b'\x02')
    check(len(lst) > 2 and lst[0] == 2 and lst[1] == 6 and lst[2] == 1, 'frequency list header %r' % lst[:8])
    check(struct.pack('<I', 60) + b'60Hz\x00' in lst, 'frequency list without 60 / "60Hz": %r' % lst)
    rig.ask_ok('LCR_SET', bytes([2, 5]))
    check(rig.rd(V_FREQ) == 60, 'LCR_SET index 5: frequency %d' % rig.rd(V_FREQ))
    t0 = rig.m.now()
    rig.run(2.0)
    check(rig.meas.tim[TIM1].reg(0x2C) == 18749, 'TIM1 AR %d' % rig.meas.tim[TIM1].reg(0x2C))
    check(rig.meas.tim[TIM6].reg(0x2C) == 7999 and rig.meas.dma[1][2].init == 150, 'TIM6 AR %d, DAC table %d'
          % (rig.meas.tim[TIM6].reg(0x2C), rig.meas.dma[1][2].init))
    check(abs(rig.meas.frequency() - 60.0) <= 6e-8, 'generator %.9f Hz' % rig.meas.frequency())
    at60 = [x for x in lut if x[0] > t0]
    check(at60 and all(r0 == 100 for _, r0, _, _ in at60), 'calibration lookups at 60 Hz %r' % at60[:4])
    pubs = rig.probe.normal(t0 + 0.5)
    check(pubs and all(p['n'] >= 3 for p in pubs), '60 Hz windows N %r' % [p['n'] for p in pubs])
    d = rig.ask_ok('MEASURE', size=M.T.MEASURE_SIZE)
    check(struct.unpack_from('<I', d, 49)[0] == 60 and d[64] & 1, 'MEASURE frequency %d marker %d'
          % (struct.unpack_from('<I', d, 49)[0], d[64]))
    rig.ask_ok('LCR_SET', bytes([6, 2]))                      # speed 2: T_win 250 ms
    t1 = rig.m.now()
    rig.run(2.0)
    fast = rig.probe.normal(t1 + 0.3)
    check(len(fast) >= 4 and all(p['n'] >= 3 for p in fast), 'speed 2 at 60 Hz: N %r' % [p['n'] for p in fast])
    ns = sorted({p['n'] for p in fast})
    # the calibration start on screen 3 (menu item 5): 100 Hz before any store
    stores = []
    a_bb64 = rig.s['fn_0800bb64'] & ~1
    rig.m.uc.hook_add(UC_HOOK_CODE, lambda uc, a, s, u: stores.append(rig.rd(V_FREQ)), begin=a_bb64, end=a_bb64)
    settings_item(rig, 5)
    tap(rig, KEY_OK)
    tap(rig, KEY_OK)
    wait_until(rig, lambda: rig.rd(V_CAL_RUN) != 0, 3.0, 'calibration start')
    check(rig.rd(V_FREQ) == 100, 'calibration start: frequency %d' % rig.rd(V_FREQ))
    rig.run(2.0)
    check(60 not in stores, 'fn_0800bb64 entered at 60 Hz: %r' % stores)
    # fn_0800a030 and the key cycle, direct
    want = {60: 110000000, 100: 110000000, 120: 110000000, 1000: 110000000, 10000: 11000000, 100000: 1100000}
    for f, w in want.items():
        rig.wr(V_FREQ, f)
        check(fcall(rig, 'fn_0800a030') == w, 'fn_0800a030 at %d Hz: %d' % (f, fcall(rig, 'fn_0800a030')))
    cyc = [60, 100, 120, 1000, 10000, 100000]
    f10 = entry_hook(rig, 'fn_08009f10')
    rig.wr(V_DISP_A8, 0)
    for i, f in enumerate(cyc):
        for step, w in ((1, cyc[(i + 1) % 6]), (-1, cyc[(i - 1) % 6]), (0, f)):
            rig.wr(V_FREQ, f)
            n0 = len(f10)
            fcall(rig, 'fn_0800d940', step & 0xFFFFFFFF)
            check(rig.rd(V_FREQ) == w and len(f10) == n0 + 1, 'key step %d from %d: %d (fn_08009f10 %d)'
                  % (step, f, rig.rd(V_FREQ), len(f10) - n0))
    rig.wr(V_FREQ, 50)
    fcall(rig, 'fn_0800d940', 1)
    check(rig.rd(V_FREQ) == 50, 'unknown word changed to %d' % rig.rd(V_FREQ))
    rig.watch.check(what='f29')
    vr = VRig(DutSource('R', 1000.0))
    vr.wr(V_FREQ, 60)
    r = vr.m.call(vr.s['fn_0800a030'])
    check(r == 1100000, 'V1.1 fn_0800a030 at 60 Hz: %r' % r)
    NOTES.append('f29: %d windows at 60 Hz speed 1, N %r at speed 2 (%d windows), V1.1 OL limit at 60 Hz %d'
                 % (len(pubs), ns, len(fast), r))
    return True


# ---------------------------------------------------------------- f30 the marked value on the panel

def glyph_image(rig, src):
    """This test's own decoding of an indexed image (rodata_01.s: descriptor word 0 = cf bits 0..4, width
    bits 10..20, height bits 21..31, word 2 = data; the data is the palette of 4-byte entries b, g, r, a,
    then the pixel indices row by row, cf 10: 256 entries, 8 bits; cf 9: 16 entries, 4 bits, high nibble
    first, rows padded to a byte; fn_080214b4, fn_080215f4 with rgb_to_565_0801d942(r, g, b)).
    Returns (width, height, {(x, y): RGB565, or None where the alpha is 0})."""
    hdr, data = rig.rd(src), rig.rd(src + 8)
    cf, w, h = hdr & 0x1F, (hdr >> 10) & 0x7FF, hdr >> 21
    check(cf in (9, 10), 'image 0x%X: colour format %d' % (src, cf))
    bits = 8 if cf == 10 else 4
    pal = rig.rd(data, 4 << bits)
    rowb = (w * bits + 7) // 8
    idx = rig.rd(data + (4 << bits), rowb * h)
    out = {}
    for y in range(h):
        for x in range(w):
            k = idx[y * rowb + x] if bits == 8 else (idx[y * rowb + x // 2] >> (4 - 4 * (x & 1))) & 0xF
            b, g, r, a = pal[4 * k:4 * k + 4]
            check(a in (0, 0xFF), 'image 0x%X pixel %r: alpha 0x%02X (the check assumes 0 or 0xFF)' % (src, (x, y), a))
            out[(x, y)] = None if a == 0 else (r >> 3) << 11 | (g >> 2) << 5 | b >> 3
    return w, h, out


def mul565(s, d):
    """fn_08014a9a (gfx_04.s): red (s >> 11)(d >> 11) >> 5, green ((s >> 5) & 63)((d >> 5) & 63) >> 6,
    blue (s & 31)(d & 31) >> 5."""
    return (((s >> 11) * (d >> 11)) >> 5) << 11 | (((s >> 5 & 63) * (d >> 5 & 63)) >> 6) << 5 | ((s & 31) * (d & 31)) >> 5


@case
def f30_marked_value_amber_digits():
    """Meter 2026-11-22: a marked main value (60 Hz) was drawn as solid amber blocks. Panel model of
    test_own_control.py: R 1 kohm, started at 100 Hz (a stored 60 is loaded as 100: save.s load_fix, design
    D60-a), LCR_SET frequency index 5 (60 Hz: marked), index 2 (1 kHz, inside the
    accuracy table: unmarked), then index 5 again. After each, the run goes on until
    the last row-0 draw (own_row_draw r0 = 0) lies 0.1 s back, and the panel memory of the logged flushes
    (fb_replay) is compared, on the rectangle of each of the 7 row-0 glyph objects (halfwords +0x14 x1,
    +0x16 y1; size = the image's), with this test's decoding of the glyph's image (word +0x24): unmarked
    the image's pixel (the root's background colour rgb_to_565_0801d7c2(0, 0, 0) where its alpha is 0),
    marked that value multiplied by amber rgb_to_565_0801d792(0xFD, 0xD0, 0x1B) by fn_08014a9a. A glyph
    showing the blank image d_08036040 (alpha 0, the places after the text) has no cover shown, and the
    panel under it (the unit picture) is the same marked as unmarked. Also: MF_ROW0 1 / 0 / 1, each
    other glyph's one cover shown when marked and hidden when not, the same covers the third time, at
    least 4 glyphs with white pixels compared each time."""
    blk = M.settings(freq=100)
    rig = M.T.Ctl(a=M.T.copy_image(blk, 2), b=M.T.copy_image(blk, 1), usb=True, source=DutSource('R', 1000.0),
                  panel=True)
    rig.up()
    draws = entry_hook(rig, 'own_row_draw', (UC_ARM_REG_R0,))
    amber = fcall(rig, 'rgb_to_565_0801d792', 0xFD, 0xD0, 0x1B) & 0xFFFF
    bg = fcall(rig, 'rgb_to_565_0801d7c2', 0, 0, 0) & 0xFFFF
    seen, blanks = [], []
    for step, (fi, marked) in enumerate(((5, True), (2, False), (5, True))):
        rig.ask_ok('LCR_SET', bytes([2, fi]))
        check(rig.rd(V_FREQ) == (60 if fi == 5 else 1000), 'step %d: frequency %d' % (step, rig.rd(V_FREQ)))
        rig.run(2.0)
        for _ in range(40):
            row0 = [t for t, r0 in draws if r0 == 0]
            check(row0, 'step %d: no row-0 draw' % step)
            if rig.m.now() - row0[-1] >= 0.1:
                break
            rig.run(0.05)
        else:
            check(False, 'step %d: row 0 drawn within 0.1 s for 2 s' % step)
        check(mf(rig, 'ROW0') == int(marked), 'step %d: MF_ROW0 %d' % (step, mf(rig, 'ROW0')))
        fb = M.T.fb_replay(rig.m.panel.flushes)
        objs = [rig.rd(GLYPHS + 4 * i) for i in range(7)]
        covers = [cover(rig, g) for g in objs]
        if marked:
            check(all(n == 1 and not rig.rd(c + 0x1C) & 1 for (n, c), g in zip(covers, objs)
                      if rig.rd(g + 0x24) != rig.s['d_08036040']), 'step %d covers %r' % (step, covers))
        else:
            check(all(n == 0 or rig.rd(c + 0x1C) & 1 for n, c in covers), 'step %d covers %r' % (step, covers))
        seen.append(covers)
        bad, compared, white, blank = [], 0, 0, {}
        for g, (n, c) in zip(objs, covers):
            w, h, img = glyph_image(rig, rig.rd(g + 0x24))
            x1, y1, x2, y2 = struct.unpack('<hhhh', rig.rd(g + 0x14, 8))
            check((x2 - x1 + 1, y2 - y1 + 1) == (w, h), 'glyph 0x%X rectangle %r, image %d x %d' % (g, (x1, y1, x2, y2), w, h))
            if rig.rd(g + 0x24) == rig.s['d_08036040']:
                # the blank image (alpha 0): no cover shown; what lies under it (the unit picture)
                # is compared between the steps below
                check(n == 0 or rig.rd(c + 0x1C) & 1, 'step %d: cover shown over the blank glyph 0x%X' % (step, g))
                blank.update({(x1 + x, y1 + y): fb.get((x1 + x, y1 + y)) for (x, y) in img})
                continue
            top = max(img[p] or 0 for p in img)
            white += top == 0xFFFF
            for (x, y), v in img.items():
                if not (0 <= x1 + x < 320 and 0 <= y1 + y < 240):
                    continue
                want = bg if v is None else v
                if marked:
                    want = mul565(amber, want)
                got = fb.get((x1 + x, y1 + y))
                compared += 1
                if got != want:
                    bad.append(((x1 + x, y1 + y), got, want))
        check(not bad, 'step %d: %d of %d pixels differ, first %r' % (step, len(bad), compared, bad[:4]))
        check(white >= 4, 'step %d: %d glyphs with white pixels' % (step, white))
        blanks.append(blank)
        NOTES.append('f30 step %d (%s): %d glyph pixels as expected, %d glyphs with white 0xFFFF -> 0x%04X, %d '
                     'blank-glyph pixels' % (step, 'marked' if marked else 'unmarked', compared, white,
                                             mul565(amber, 0xFFFF), len(blank)))
    check(seen[2] == seen[0], 'covers of the third step %r, first %r' % (seen[2], seen[0]))
    for k in (0, 2):
        same = set(blanks[k]) & set(blanks[1])
        diff = [(p, blanks[k][p], blanks[1][p]) for p in sorted(same) if blanks[k][p] != blanks[1][p]]
        check(not diff, 'under the blank glyph, step %d against step 1: %d of %d differ, first %r'
              % (k, len(diff), len(same), diff[:4]))
        NOTES.append('f30: under the blank glyph %d pixels of step %d as unmarked' % (len(same), k))
    return True


# ---------------------------------------------------------------- f31 revision 14 through the rows and the record

BUF = 0x20014440                      # rec_measure's 66 bytes, after the text buffers of fmt() (0x20014400..1F)


@case
def f31_low_frequency_ol_and_call_sites():
    """MEASUREMENT_FIX_DESIGN revision 14 through the display rows (fn_0800d3d8 row 0 by the byte 0x200011E4,
    fn_0800d294 row 1 by the word 0x200011E8, called directly in the stopped base rig; the text taken at the
    entry of own_row_draw, r1) and the host record (rec_measure called directly into BUF, hold 0x200011A4 and
    the no-reading counter 0x2000120C written 0 first, so validity 1 can only come from "0L"):
    (a) rule 2: at 60, 100 and 120 Hz with |Z| 0x200050C4 = 1.0001e7 (above fmt_spec's 1e7) every text of
        main rows 1..4 and secondary rows 0..4 is "0L  " and unmarked (MF_ROW0 / MF_ROW1 0 after the draw),
        and every value block of rec_measure has validity 1, text "0L  " and unit code 0, the marker byte 0.
        With |Z| = 1.0e7 (not above) at the same frequencies, and at 1 kHz with |Z| = 2e7, every text is the
        one the same wrapper gives for the same word at 1 kHz with |Z| 1000 (the reference, through fmt(),
        which only the rule could change), and the record's texts equal the display's. The other words hold
        values inside the measurement range (input check: no reference text of them is "0L  "), so only rule
        2 can make them OL: R 5000, C 0.1 nF, L 1000 uH, X -5000, theta -89, D 0.01, Q 100. Row 4 shows
        |Z| itself: 1e7 is inside the R row's range; 2e7 at 1 kHz is OL by S2.1 (fmt_hard), as its
        reference.
    (b) rule 1 at the call sites, at 1 kHz with |Z| 1000 (except row 4), 0x200011EC = 0 and = 1: main row 1
        R -5 (series "0.0000", parallel OL), 2 C -0.5 nF (series OL, parallel "0.0"), 3 L -100 uH (series
        "0.0", parallel OL), 4 |Z| = -5 (0x200050C4 itself: "0.0000" in both modes, so the `addw` at
        0x0800D406 hands own_fmt_rz the |Z| word); secondary 0 R -5 (as main 1), 1 X -12.3456 ("-12.346"),
        2 D -0.5 ("0.0000" in both, `addw` at 0x0800D340), 3 Q -0.5 (OL in both, `addw` at 0x0800D34C);
        the secondary rows drawn with main row 1 (R), so (c) cannot change them; rec_measure's text equals
        the display's and its validity is 1 exactly for OL; its value field keeps the negative word.
        Expected texts as derived in f21 (ui_42.s headers).
    (c) revision 15 (fmt_dq), at 1 kHz with |Z| 1000, D 0.5 and Q 1.5 published (alone "0.5000" / "1.5000",
        fn_0800dd44 "%0.4f" below 10): with main row 2 (C) or 3 (L) whose text is 0, D is "0L  " and Q
        "0.0000"; otherwise D and Q as alone. Main values, both modes: C -0.5 nF (series OL, parallel "0.0"),
        C 4e-5 nF (0.04 pF: "0.0" in both, a positive value below the last place), C 0.1 nF ("100.0" pF);
        L -100 uH (series "0.0", parallel OL), L 0.04 uH ("0.0" in both), L 1000 uH (not 0); main row 1 R
        -5 in series ("0.0000") leaves D and Q as alone (the rule is C and L only). The main text is checked
        first (input check), then rows 2 and 3 of the secondary and rec_measure (main, 2) and (main, 3)."""
    rig = base_rig()
    seen = []
    a = rig.s['own_row_draw'] & ~1

    def rowdraw(uc, addr, size, user):
        seen.append((uc.reg_read(UC_ARM_REG_R0),
                     bytes(uc.mem_read(uc.reg_read(UC_ARM_REG_R1), 8)).split(b'\x00')[0].decode('latin-1')))
    h = rig.m.uc.hook_add(UC_HOOK_CODE, rowdraw, begin=a, end=a)

    def draw(row, sel):
        """(text, MF_ROW of the row after the draw) of row `row` with the selector sel."""
        del seen[:]
        if row == 0:
            rig.wr(V_MAIN_ROW, bytes([sel]))
            fcall(rig, 'fn_0800d3d8')
        else:
            rig.wr(V_SECONDARY, sel)
            fcall(rig, 'fn_0800d294')
        check(len(seen) == 1 and seen[0][0] == row, 'row %d selector %d: own_row_draw calls %r' % (row, sel, seen))
        return seen[0][1], mf(rig, 'ROW0' if row == 0 else 'ROW1')

    def record(main, sec):
        """rec_measure with main row `main` and secondary `sec`: (record, (text, unit, validity) main, secondary)."""
        rig.wr(V_MAIN_ROW, bytes([main]))
        rig.wr(V_SECONDARY, sec)
        rig.wr(V_HOLD, 0)
        rig.wr(V_NO_READ_CNT, 0)
        rig.wr(BUF, bytes(66))
        fcall(rig, 'rec_measure', BUF)
        d = rig.rd(BUF, 66)

        def blk(o):
            return d[o + 7:o + 15].split(b'\x00')[0].decode('latin-1'), d[o + 4], d[o + 6]
        return d, blk(9), blk(25)

    pairs = [(1, 0), (2, 1), (3, 2), (4, 3), (1, 4)]          # every main row and every secondary once
    mains = {1: ('own_fmt_r', V_R), 2: ('own_fmt_c', V_C), 3: ('own_fmt_l', V_L), 4: ('own_fmt_z', V_Z)}
    secs = {0: ('own_fmt_r', V_R), 1: ('own_fmt_x', V_X), 2: ('own_fmt_d', V_D), 3: ('own_fmt_q', V_Q),
            4: ('own_fmt_th', V_TH)}
    # (a) rule 2
    vals = {V_R: 5000.0, V_C: 0.1, V_L: 1000.0, V_X: -5000.0, V_TH: -89.0, V_D: 0.01, V_Q: 100.0}
    rig.wr(V_SERPAR, 0)
    for w, v in vals.items():
        wf(rig, w, v)
    wf(rig, V_Z, 1000.0)
    ref = {(0, m): fmt(rig, n, vals[w], 1000)[0] for m, (n, w) in mains.items() if m != 4}
    ref.update({(1, s): fmt(rig, n, vals[w], 1000)[0] for s, (n, w) in secs.items()})
    check(all(t != '0L  ' for t in ref.values()), 'f31: reference texts %r (input: none OL)' % ref)
    steps = [(f, 1.0001e7, True) for f in (60, 100, 120)] + [(f, 1.0e7, False) for f in (60, 100, 120)] + \
        [(1000, 2.0e7, False)]
    for f, z, ol in steps:
        wf(rig, V_Z, z)
        ref[(0, 4)] = fmt(rig, 'own_fmt_z', z, 1000)[0]       # |Z| row: the word itself (fmt sets 1 kHz)
        wf(rig, V_Z, z)
        rig.wr(V_FREQ, f)
        shown = {}
        for row, sels in ((0, mains), (1, secs)):
            for sel in sels:
                t, rowmark = draw(row, sel)
                shown[(row, sel)] = t
                if ol:
                    check(t == '0L  ' and rowmark == 0, 'f31 %d Hz |Z| %g: row %d selector %d %r, MF_ROW %d (expected '
                          'OL, unmarked)' % (f, z, row, sel, t, rowmark))
                else:
                    check(t == ref[(row, sel)], 'f31 %d Hz |Z| %g: row %d selector %d %r, expected %r' % (
                        f, z, row, sel, t, ref[(row, sel)]))
        for m, s in pairs:
            d, bm, bs = record(m, s)
            if ol:
                check(bm == ('0L  ', 0, 1) and bs == ('0L  ', 0, 1) and d[64] == 0,
                      'f31 %d Hz |Z| %g: record main %d %r secondary %d %r markers %d (expected OL, unit 0, '
                      'validity 1)' % (f, z, m, bm, s, bs, d[64]))
            else:
                check(bm[0] == shown[(0, m)] and bs[0] == shown[(1, s)] and bm[2] == int(bm[0] == '0L  ')
                      and bs[2] == int(bs[0] == '0L  '), 'f31 %d Hz |Z| %g: record main %d %r secondary %d %r, '
                      'display %r / %r' % (f, z, m, bm, s, bs, shown[(0, m)], shown[(1, s)]))
    # (b) rule 1 at the call sites
    zero_r, zero_c, zero_l, ol_t = '0.0000', '0.0', '0.0', '0L  '
    neg = {V_R: -5.0, V_C: -0.5, V_L: -100.0, V_X: -12.3456, V_TH: -45.0, V_D: -0.5, V_Q: -0.5}
    for w, v in neg.items():
        wf(rig, w, v)
    rig.wr(V_FREQ, 1000)
    for sp in (0, 1):
        rig.wr(V_SERPAR, sp)
        wf(rig, V_Z, 1000.0)
        want = {(0, 1): zero_r if sp == 0 else ol_t, (0, 2): ol_t if sp == 0 else zero_c,
                (0, 3): zero_l if sp == 0 else ol_t, (1, 0): zero_r if sp == 0 else ol_t, (1, 1): '-12.346',
                (1, 2): '0.0000', (1, 3): ol_t}
        shown = {}
        for (row, sel), w_ in sorted(want.items()):
            if row == 1:
                rig.wr(V_MAIN_ROW, bytes([1]))                # main R: the revision 15 rule off
            t, _ = draw(row, sel)
            shown[(row, sel)] = t
            check(t == w_, 'f31 0x200011EC = %d: row %d selector %d %r, expected %r' % (sp, row, sel, t, w_))
        for m, s in ((1, 0), (2, 1), (3, 1), (1, 2), (1, 3)):
            d, bm, bs = record(m, s)
            check(bm[0] == shown[(0, m)] and bm[2] == int(bm[0] == ol_t) and bs[0] == shown[(1, s)]
                  and bs[2] == int(bs[0] == ol_t), 'f31 0x200011EC = %d: record main %d %r secondary %d %r, display '
                  '%r / %r' % (sp, m, bm, s, bs, shown[(0, m)], shown[(1, s)]))
            check(struct.unpack_from('<f', d, 9)[0] == u32f(f2u(neg[mains[m][1]])) and d[40] == sp,
                  'f31: record value %r, series / parallel %d' % (struct.unpack_from('<f', d, 9)[0], d[40]))
        wf(rig, V_Z, -5.0)                                    # row 4: the |Z| word itself, below 0
        t, _ = draw(0, 4)
        d, bm, _ = record(4, 1)
        check(t == zero_r and bm[0] == zero_r and bm[2] == 0, 'f31 0x200011EC = %d: |Z| -5 shown %r, record %r '
              '(expected 0.0000: own_fmt_z, not R)' % (sp, t, bm))
    # (c) revision 15: D and Q beside a C or L shown as 0
    wf(rig, V_Z, 1000.0)
    wf(rig, V_D, 0.5)
    wf(rig, V_Q, 1.5)
    wf(rig, V_R, -5.0)
    n_c = 0
    for sp in (0, 1):
        rig.wr(V_SERPAR, sp)
        # (main row, value word, value, expected main text)
        cases = [(2, V_C, -0.5, ol_t if sp == 0 else zero_c), (2, V_C, 4e-5, zero_c), (2, V_C, 0.1, '100.0'),
                 (3, V_L, -100.0, zero_l if sp == 0 else ol_t), (3, V_L, 0.04, zero_l), (3, V_L, 1000.0, None),
                 (1, V_R, -5.0, zero_r if sp == 0 else ol_t)]
        for m, w, v, wmain in cases:
            wf(rig, w, v)
            tm, _ = draw(0, m)
            check(wmain is None and tm not in ('0.0', ol_t) or tm == wmain,
                  'f31 c 0x200011EC = %d: main %d value %g shown %r, expected %r (input check)' % (sp, m, v, tm, wmain))
            zero = m in (2, 3) and tm == '0.0'
            wd, wq = ('0L  ', '0.0000') if zero else ('0.5000', '1.5000')
            td, _ = draw(1, 2)
            tq, _ = draw(1, 3)
            check(td == wd and tq == wq, 'f31 c 0x200011EC = %d: main %d %r: D %r Q %r, expected %r %r' % (
                sp, m, tm, td, tq, wd, wq))
            for s, ws in ((2, wd), (3, wq)):
                d, bm, bs = record(m, s)
                check(bm[0] == tm and bs[0] == ws and bs[2] == int(ws == ol_t),
                      'f31 c 0x200011EC = %d: record main %d %r secondary %d %r, expected %r / %r' % (
                          sp, m, bm, s, bs, tm, ws))
            n_c += 1
    rig.m.uc.hook_del(h)
    rig.wr(V_SERPAR, 0)
    wf(rig, V_Z, 1000.0)
    NOTES.append('f31: %d rule-2 steps, rule 1 in both modes through fn_0800d3d8 / fn_0800d294 and rec_measure, '
                 '%d revision-15 cases' % (len(steps), n_c))
    rig.watch.check(what='f31')
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
        print('%-52s %s %s' % (fn.__name__, 'ok' if ok else 'FAIL', msg), flush=True)
        bad += not ok
    for n in NOTES:
        print('  note:', n)
    print('%d tests, %d failed' % (run, bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
