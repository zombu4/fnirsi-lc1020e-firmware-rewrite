#!/usr/bin/env python3
"""test_own_dset.py - the direct changes of SCREEN, LCR_SET, HOLD, SETTINGS_SET and COMPARE_SET
(firmware/own/dset.s, DIRECT_SET_DESIGN.md revision 2), in the emulator.

Usage (from the repository root, after `make -C starter`, `make -C bootloader slot` and
`make -C firmware own`):
    <python with unicorn 2.1.4> tests/test_own_dset.py [case-name-prefix ...]

Rig: tests/test_own_control.py Ctl (meter_model in flash mode 'app' with timing, KeyPad, MeasurePath,
UsbDevice / UsbHost), imported, not changed, with three additions of this file:
  - Flat: the device under test gives ADC1 and ADC2 the constant mid code 2048 (DutSource otherwise:
    ADC3 mid-scale, ADC4 the 4.0 V supply). With a signal the results depend on the time grid of the
    sampling (measure_model: every sample is the generator at its time), so two runs of the same
    change at different times differ in the result words, the sample buffers 0x20005A38.., the
    FFT work areas and the displayed value (run 2026-11-21, scratchpad dimpl/exp1: 1769 words and
    1705 pixels between two key-path runs 37 ms apart). With Flat the results are the same at
    every time (dimpl/exp2: two key-path runs 37 ms apart differ in no pixel), so a key-path run and
    a direct run can be compared word by word.
  - FbPanel: the panel's memory (320 x 240 RGB565) built from the writes of fn_08009e30 /
    fn_08014f9c to the command port 0x6001FFFE and the data port 0x60020000 (2A x1 hi, lo, x2 hi,
    lo; 2B y the same; 2C then the pixels row-major in the window), as test_own_control.Panel reads
    them, kept as one bytearray instead of a list of every flush.
  - Probe: a write hook on the peripheral ranges MMIO (TIM2 / TIM3, TIM6, DAC, GPIOB / GPIOC, TIM1,
    DMA1 / DMA2, ADC1..ADC3) that logs (address, value), and a code hook at 0x080281D0 (the bl of
    ctl_loop in the main loop, own/ctl.s header) that ends the emulator slice there (meter_model
    stop_req), so a capture is taken at the start of a main-loop pass: no GUI call is in flight then
    (a capture in the middle of a call finds stack-record chains such as 0x2000049C, fn_080207f4,
    pointing into the stack).

Comparison of a direct change with the key path (critique 8 of DIRECT_SET_DESIGN.md revision 1):
from one snapshot of the whole machine (test_own_control.Snapshot) the key path runs (KEY presses
until the value is reached, as the old jobs pressed) and, after a restore, the direct command; each
is followed by SETTLE s, then captured at the first main-loop pass after the same number of
measurement results since the measurement restart (capture()):
  - all vendor RAM 0x20000000..0x20017FFF word by word, except: the stack 0x2001424C..0x200163A7
    (between the end of the GUI heap 0x2000824C + 0xC000, fn_08022c94, and the initial SP
    0x200163A8); the tick words TICK_WORDS and the timer records' tick words (each written by a
    timer routine, the writer measured by a write hook, dimpl/exp3); the heap history counters
    HEAP_COUNTERS; the drawing scratch DRAW_BUF, DRAW_AREA, IMAGE_REC (the drawing is compared on
    the panel); the MASKED handshake byte; the unused tail of the DAC sine table (entries from the
    count the frequency uses, ram_diff); and the GUI heap, which is compared by its block walk
    instead (heap_walk: the same used blocks, and their words equal; free blocks hold stale data
    and free-list links of the allocation history). A word that differs must be on the case's
    list of expected differences (KEY_ONLY: the key path's own words; plus the case's 2.4 entries);
  - the panel memory, pixel by pixel (catches a missing redraw);
  - the last value written to every logged peripheral register (DMA, ADC, DAC, timers, GPIOB /
    GPIOC: fn_08008350, fn_0800b164) except TIM2, and no write at all to TIM2 0x40000000..
    (the beep fn_08008120) in the direct run;
  - the direct run: no KEY event (code of source 1 or any), status 0, the longest watchdog stretch
    below 0.67 s (test_own_control.PERIOD_MIN; k29's measure).
"""

import os
import struct
import sys
import time

from unicorn import UC_HOOK_MEM_WRITE, UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_PC, UC_ARM_REG_R6

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_own_control as T  # noqa: E402
from test_own_control import (Ctl, Snapshot, check, f32, stretch_in, PERIOD_MIN, OWN_CTL,  # noqa: E402
                              CT_FLAGS, S_OK, S_BAD_ARG, S_NOT_NOW, S_BUSY, S_SAFETY, FR_EVENT, E_KEY,
                              E_SETTING, V_BLOCK, BLK, V_SCREEN, V_FUNC, V_SECONDARY, V_FREQ, V_LEVEL,
                              V_BIAS, V_RANGE, V_SPEED, V_CIRCUIT, V_BRIGHT, V_HOLD, V_MENU, V_DIALOG,
                              V_MAIN_ROW, V_CAL_RUN, V_KEY_CODE, MEASURE_SIZE, STATE_SIZE, COMPARE_SIZE)
V_CAL_TYPE = 0x200050E0                          # own.inc: 0 short, 11 open
from measure_model import DutSource  # noqa: E402

CASES = []
NOTES = []

# ---- addresses (own.inc, ctl.inc, DIRECT_SET_DESIGN.md section 1) ----
VRAM_LO, VRAM_N = 0x20000000, 0x18000           # vendor RAM below our area 0x20018000
STACK = (0x2001424C, 0x200163A8)
CF_OFF_WAIT = 0x04
CT_MEAS_SEQ = 0x03C                             # ctl.inc: new measurement results seen (ev_detect)
CT_DS_OP = 0x0E8
V_CMP_TYPE, V_NOMINAL, V_TOLERANCE, V_SCALE = 0x20001178, 0x20001184, 0x20001188, 0x2000119C
V_WARN = (0x2000116C, 0x20001170, 0x20001174)
V_VOLUME, V_OFFTIME = 0x20001160, 0x20001164
V_PREV_SCREEN, V_EDIT, V_SEL, V_DIGIT = 0x200011BC, 0x2000000C, 0x200011B4, 0x200011B8
V_HEAP_USE = 0x200004F4                         # GUI heap bytes in use (fn_08022b50 / fn_08022c68)
TIM3_CCDAT = 0x40000434                         # fn_08009e60: TIM3 compare (9 x value) x 4 below 100
MAIN_CALL = 0x080281D0                          # bl ctl_loop (own/ctl.s header)
SETTLE = 0.3                                    # s after the answer before the capture

# words written by timer routines (writers measured with a write hook, dimpl/exp3, 2026-11-21)
TICK_WORDS = {0x20000000: 'fn_0802a720 (SysTick) counter', 0x20000004: 'fn_0802a720 counter',
              0x20005104: 'fn_0802a720 counter', 0x20005108: 'fn_0802a720 counter',
              0x2000510C: 'fn_0802a720 counter', 0x20005110: 'fn_0802a720 counter (V_CMP_DUE)',
              0x20005114: 'fn_0802a720 counter (V_SWEEP_ON)',
              0x2000120C: 'fn_0802a720 no-reading counter (cleared by fn_08009f10, fn_0800a068)',
              0x20000480: 'GUI tick (+10 per SysTick, fn_080277a0)',
              0x20000484: 'timer walk block fn_08027830 (+0 .. +4 flags)',
              0x20000488: 'timer walk block fn_08027830', 0x2000048C: 'timer walk start tick',
              0x20000490: 'timer walk busy ticks', 0x20000494: 'timer walk counter',
              0x200004D8: 'timer walk current record',
              0x200001D4: 'fn_0800a7ec ring index / flag bytes: one call every 50 SysTicks (V_CMP_DUE) in '
                          'screen 2 (measure_33.s 842-862); measured 2026-11-21, SCREEN 2 -> 1: 1 after the '
                          'key path (its 1100 ms press in screen 2), 2 after the direct change',
              0x2000599C: 'fn_0800a7ec 3-entry float ring, entry 0', 0x200059A0: 'its entry 1',
              0x200059A4: 'its entry 2',
              0x20000010: 'fn_0800bd5c counter: +1 per call (once a second, V_SWEEP_ON) in screen 3 up to 5 '
                          '(app_02.s 722-728); measured 2026-11-21, SCREEN 1 -> 3: 0 after the key path '
                          '(its 1100 ms press), 1 after the direct change (screen 3 entered earlier)',
              0x200011F4: 'own/meas.s: the accepted count of the open window, which closes by time (T_win '
                          'since the previous close, meas_add), so it depends on when the acquisitions came, '
                          'not on how many came since the restart; measured 2026-11-22 (Func 1 -> 0): 0x33 '
                          'after the key path, 0x34 after the direct change'}
# the GUI heap's counters: fn_08022b50 adds the requested size to 0x200004F4 (maximum in 0x200004F8),
# fn_08022c68 subtracts the block's size word and stores 0 when that is not smaller (guilib_29.s
# 1982-1986, guilib_30.s 173-178): a count of the history, not of the live blocks (measured
# 2026-11-21, speed 0 -> 2: 0x90 after the key path, 0x2C8 after the direct change with the same
# allocations and frees at the end of both runs, dimpl/exp6). The live blocks are compared by
# heap_walk instead.
HEAP_COUNTERS = {0x200004F4: 'GUI heap history counter', 0x200004F8: 'its maximum'}
HEAP = (0x2000824C, 0xC000)                     # fn_08022c94: fn_08027a20(0x2000824C, 0xC000)
# scratch of the drawing, whose result is compared on the panel instead: the draw buffer
# 0x20006700 (0xC80 pixels, own.inc V_DRAW_BUF: it holds the last rectangle drawn) and the area sum
# 0x200004B4 of the redraw fn_08028e1c (cleared at its start, gui header); measured 2026-11-21
# (circuit 1 -> 0): both differ when one capture follows a redraw and the other does not.
DRAW_BUF = (0x20006700, 0x20006700 + 0xC80 * 2)
DRAW_AREA = 0x200004B4
# the image record 0x200080B0..0x200080D7 (0x28 bytes): fn_080218d4 (gui_19.s 2081) clears and
# fills it for every image drawn (source +4, header +0x14 by fn_08021278); writers measured
# 2026-11-21 (dimpl/exp3: clear_bytes, fn_080218d4, fn_08021278); after circuit 1 -> 0 it held
# the source 0x080422BC after the key path and 0x08034110 after the direct change (the last
# image drawn), with the panel the same pixel for pixel.
IMAGE_REC = (0x200080B0, 0x200080D8)
# the three 8-byte glyph caches 0x20000444..0x2000045B of the fonts (font record word +0x14,
# rodata_01.s 212 / 341, rodata_04.s 494): the last glyph looked up in each font; measured
# 2026-11-21 (SCREEN 3 -> 1 entered from 2): 0x2000044C 0x47 / 0x6E after the key path / the
# direct change, the panel equal.
GLYPH_CACHE = (0x20000444, 0x2000045C)
# the amber covers of fmt.s own_row_draw: a glyph object of row r (word GLYPHS + 32 r + 4 i, i 0..6)
# gets its cover (a child object, fn_08023678, with its style keys) at its first marked draw, and the
# cover stays, hidden, when the row is drawn unmarked again (fmt.s: "covers made once"). A key path
# through a marked intermediate value therefore leaves covers that a direct change to an unmarked
# value never makes. Run of 2026-11-24 (d01a Func 0 -> 2 through 1 with the flat source, scratchpad
# dsdiag/func3.py): 6 covers of row 1, all hidden, 42 heap blocks (glyph attribute block, cover and
# style blocks) only in the key path's capture, none only in the direct one, 0x20000460 (the count
# of fn_0802318c's data blocks, gui_21.s 403-410) higher by 2 per cover (writers LR 0x0802346D in
# fn_08023678 and 0x08025E3F in the style set), the panel equal. key_only_covers() finds them and
# compare() allows exactly that and nothing more.
GLYPHS = 0x200059A8
OBJ_ATTR, OBJ_FLAGS = 0x08, 0x1C                 # fmt.s: attribute block word, flag word (bit 0 hidden)
DATA_COUNT = 0x20000460
COVER_DATA_BLOCKS = 2
# The glyph slots keep their pointers when a screen without the rows is shown (Run of 2026-11-24,
# d03 / d05: a slot word pointing below the RAM); a pointer is followed only into the GUI heap.
# The unit picture of row 1 (object pointer at 0x20000220, ui_41.s fn_0800d294): its image is set
# (fn_08021c14) only by the cases that show it (R / X with a unit index 4..7, theta), and the other
# cases hide it (fn_08023050) and leave the last image. Every path that shows it sets the image first
# (R / X: index 0 hides it, 4..7 set the image, fmt.s fmt_scale names 5..7 as the ohm indices;
# theta sets it before its formatter), so a hidden unit picture's image words
# are what an earlier, unseen value left. Run of 2026-11-24 (d01a Func 0 -> 2, d01c secondary 4 ->
# 2, scratchpad dsdiag/func4.py): hidden in both, words +0x14 +0x18 (rectangle), +0x24 (image),
# +0x2C +0x30 +0x34 (image size and header) d_08036cd8 / d_08040a28, the panel equal. compare()
# leaves those six words out only while the picture is hidden in both captures.
UNIT_PIC = 0x20000220
UNIT_PIC_IMAGE_WORDS = (0x14, 0x18, 0x24, 0x2C, 0x30, 0x34)
TIMER_TICK_STORE = 0x78                        # fn_08027830 + 0x78: str r0, [r6, #4] (the record's
                                                # last run tick, guilib_30.s 780..; writer measured)
# words only the key path writes (expected differences of every direct change, 2.4 item 6)
KEY_ONLY = {0x20001190: 'busy halfword (long presses 1, the 0xFF release 0)',
            0x20001192: 'event code (injected events)', 0x20001194: 'event mask (injected events)',
            0x20001196: 'key scan counter'}
MMIO = ((0x40000000, 0x40000800), (0x40001000, 0x40001400), (0x40007400, 0x40007800),
        (0x40010C00, 0x40011400), (0x40012C00, 0x40013000), (0x40020000, 0x40020500),
        (0x40020800, 0x40021000), (0x40021800, 0x40021C00))
BEEP = (0x40000000, 0x40000400)                 # TIM2, fn_08008120
# TIM1 registers whose written value depends on what the stack held before the call: fn_08007e7c
# (measure_32.s 334-374, called by fn_08009f10 through fn_08007bdc) passes fn_0800c504 a record at
# sp + 0x10 of which only halfwords 0, 1, 3, 4 are written; fn_0800c504 (periph_35.s 1107-1113) ors
# halfwords 2 and 5 into CCEN (+0x20) and 6, 7 into CTRL2 (+0x04). Measured 2026-11-21 (speed 0 ->
# 1): CTRL2 written 0 after the key path, 0x31920 after the direct change (the stack below the
# caller differs).
# The same for TIM3 CTRL1: fn_08009e60 (lcd_31.s 483-545, the backlight) writes only halfwords
# 0, 2, 4, 6 of the record at sp for fn_0800c590, which sets bits 0x800..0x8000 of CTRL1 from its
# bytes 9..14 (periph_35.s 1195-1206). Measured 2026-11-21 (brightness in the menu): CTRL1 0xE881
# after the key path, 0x7881 after the direct change. The compare TIM3 + 0x34 stays compared.
STACK_DEPENDENT = {0x40012C04: 'TIM1 CTRL2 from stack halfwords 6, 7', 0x40012C20: 'TIM1 CCEN from 2, 5',
                   0x40000400: 'TIM3 CTRL1 bits 11..15 from stack bytes 9..14',
                   # not state: the DMA flag clear registers INTCLR (write 1 to clear, read 0;
                   # measure_model header, manual 8.5): their last value only says which flag was
                   # cleared last (measured 2026-11-21, frequency 120 -> 100: 0x20000 / 0x200)
                   0x40020004: 'DMA1 INTCLR (command register)', 0x40020404: 'DMA2 INTCLR (command register)'}
KEY_BIT = {0x0004: 2, 0x0008: 3, 0x0010: 4, 0x0020: 5, 0x0040: 6, 0x0080: 7, 0x0100: 8, 0x0200: 9,
           0x0400: 10, 0x0800: 11, 0x1000: 12, 0x2000: 13}
LONG = 1100                                     # ctl.inc LONG_MS
LEVELS = (0x3DCCCCCD, 0x3E99999A, 0x3F19999A)   # ctl.s tab_level
BIASES = (0x00000000, 0x3F000000)               # ctl.s tab_bias
FREQS = (100, 120, 1000, 10000, 100000, 60)     # ctl.s tab_freq (index 5 = 60 Hz, the key cycle's
                                                # sixth value, MEASUREMENT_FIX_DESIGN.md S2.12)
# LCR_SET settings: id -> (word, key mask, hold, values)
LCR = {0: (V_FUNC, 0x0200, 0, (0, 1, 2, 3, 4)), 1: (V_SECONDARY, 0x0040, 0, (0, 1, 2, 3, 4)),
       2: (V_FREQ, 0x2000, 0, FREQS), 3: (V_LEVEL, 0x0800, 0, LEVELS), 4: (V_BIAS, 0x0100, 0, BIASES),
       5: (V_RANGE, 0x0080, 0, (0, 1, 2, 3, 4)), 6: (V_SPEED, 0x1000, 0, (0, 1, 2)),
       7: (V_CIRCUIT, 0x1000, LONG, (0, 1, 2))}


def case(fn):
    CASES.append(fn)
    return fn


# ---------------------------------------------------------------- rig additions

class Flat(DutSource):
    """ADC1 / ADC2 at the constant mid code: results independent of the time grid."""

    def samples(self, path, adc, channel, times):
        if adc in (1, 2):
            return 2048
        return super().samples(path, adc, channel, times)


class FbPanel:
    """Panel memory from the command / data port writes (test_own_control.Panel's decoding)."""

    def __init__(self):
        self.cmd = None
        self.args = []
        self.win = [0, 0, 319, 239]
        self.pos = 0
        self.fb = bytearray(320 * 240 * 2)

    def write(self, addr, value):
        value &= 0xFFFF
        if addr == 0x6001FFFE:
            self.cmd = value & 0xFF
            self.args = []
            self.pos = 0
            return
        if self.cmd in (0x2A, 0x2B):
            self.args.append(value & 0xFF)
            if len(self.args) == 4:
                lo = self.args[0] << 8 | self.args[1]
                hi = self.args[2] << 8 | self.args[3]
                if self.cmd == 0x2A:
                    self.win[0], self.win[2] = lo, hi
                else:
                    self.win[1], self.win[3] = lo, hi
        elif self.cmd == 0x2C:
            x1, y1, x2, y2 = self.win
            w = x2 - x1 + 1
            x, y = x1 + self.pos % w, y1 + self.pos // w
            self.pos += 1
            if 0 <= x < 320 and 0 <= y < 240:
                struct.pack_into('<H', self.fb, 2 * (320 * y + x), value)


class Probe:
    """Peripheral writes of the window (address, value), the main-loop pass stop flag and the time of
    the last call of fn_08009f10 (the measurement restart)."""

    def __init__(self):
        self.mmio = []
        self.at_call = False
        self.f10 = -1.0
        self.results = 0                # publishes (stores of 1 to 0x20001200, own/meas.s
                                        # meas_tail) since the window's start or the last
                                        # fn_08009f10
        self.timer_words = set()        # every address fn_08027830 + 0x78 stored a tick to


def make_rig(**kw):
    """A rig with Flat, FbPanel and Probe, run to the main loop with the host enumerated, 0.3 s on."""
    rig = Ctl(panel=True, source=Flat(), **kw)
    rig.m.panel = FbPanel()
    p = rig.probe = Probe()
    m = rig.m

    def mm(uc, acc, a, size, v, u):
        p.mmio.append((a, v))
    for lo, hi in MMIO:
        m.uc.hook_add(UC_HOOK_MEM_WRITE, mm, begin=lo, end=hi - 1)

    def call(uc, a, size, u):
        p.at_call = True
        m.tm['stop_req'] = True          # meter_model: the slice ends at the next block (ctl_loop)
    m.uc.hook_add(UC_HOOK_CODE, call, begin=MAIN_CALL, end=MAIN_CALL)

    def f10(uc, a, size, u):
        p.f10 = m.now()
        p.results = 0

    def result(uc, acc, a, size, value, u):
        if value == 1:
            p.results += 1
    m.uc.hook_add(UC_HOOK_MEM_WRITE, result, begin=0x20001200, end=0x20001203)
    f = rig.s['fn_08009f10'] & ~1
    m.uc.hook_add(UC_HOOK_CODE, f10, begin=f, end=f)

    def tick_store(uc, a, size, u):
        p.timer_words.add(uc.reg_read(UC_ARM_REG_R6) + 4)
    f = (rig.s['fn_08027830'] & ~1) + TIMER_TICK_STORE
    m.uc.hook_add(UC_HOOK_CODE, tick_store, begin=f, end=f)
    rig.up()
    rig.run(0.3)
    to_pass(rig)
    return rig


def to_pass(rig):
    """Run on to the start of the next main-loop pass (PC at ctl_loop, no GUI call in flight)."""
    p, loop = rig.probe, rig.s['ctl_loop'] & ~1
    p.at_call = False

    def until(m):
        if p.at_call:
            if m.uc.reg_read(UC_ARM_REG_PC) & ~1 == loop:
                return True
            p.at_call = False           # an interrupt was entered there: the next pass
        return False
    end = rig.m.run_for(seconds=3.0, until=until)
    check(end is None and p.at_call, 'no main-loop pass within 3 s: end %r, violations %r'
          % (end, rig.m.st['viol']))


def window(rig):
    """Start of a measured window: empty logs, the time."""
    rig.probe.mmio[:] = []
    rig.host.frames[:] = []
    rig.probe.results = 0
    return rig.m.now()


def capture(rig, t0, ref=None):
    """The capture at the first main-loop pass after a result of the measurement (a publish: the store
    of 1 to 0x20001200 in own/meas.s meas_tail; the display changes only there, and the windows close
    by time, so an alignment by acquisitions left one run before and one after a publish, measured
    2026-11-22: a GUI object word 1 / 0, d01f):
    ref None (the key path): SETTLE s on, then the next result, then the pass. Else (the direct
    change): the run until as many results have come since the window's start or the last
    fn_08009f10 (the measurement restart, which own_measure sees and resets its window for) as in
    ref, then the pass: both captures stand at the same point of the measurement
    (a capture at the same time alone left the indices one result apart, measured 2026-11-21:
    13 / 14, and the restart request byte 0x200011C4 set in one run only). When none comes within
    1.2 s (a window period at speed 0 and its display update) of the key path's
    SETTLE, both captures are taken at the same time after the window's start instead. Returns
    RAM, panel memory, peripheral writes, frames, the longest watchdog stretch, the alignment and
    the timer records' tick words."""
    p = rig.probe
    if ref is None:
        rig.run(SETTLE)
        s0 = rig.rd(OWN_CTL + CT_MEAS_SEQ)      # a whole averaged result after SETTLE (ctl.s
        rig.m.run_for(seconds=1.5, until=lambda m: rig.rd(OWN_CTL + CT_MEAS_SEQ) != s0)   # ev_detect)
        n0 = p.results
        end = rig.m.run_for(seconds=1.2, until=lambda m: p.results != n0)
        check(end is None, 'key path run ended: %r' % end)
        want = p.results if p.results != n0 else None
    else:
        want = ref['results']
        if want is None:
            left = t0 + ref['t_rel'] - rig.m.now()
            if left > 0:
                rig.run(left)
        else:
            end = rig.m.run_for(seconds=ref['t_rel'] + 1.0, until=lambda m: p.results >= want)
            check(end is None and p.results == want, 'direct run: %d results, the key path %d'
                  % (p.results, want))
    to_pass(rig)
    check(want is None or p.results == want, 'a result between the last one and the pass (%r / %r)'
          % (p.results, want))
    t1 = rig.m.now()
    c = dict(ram=bytes(rig.m.uc.mem_read(VRAM_LO, VRAM_N)), fb=bytes(rig.m.panel.fb),
             mmio=list(rig.probe.mmio), stretch=stretch_in(rig.m, t0, t1), results=want,
             t_rel=t1 - t0, timer_words=set(rig.probe.timer_words), pod=dict(rig.m.st['pod']))
    c['frames'] = list(rig.host.frames) + rig.drain(0.02)
    return c


def word(c, a):
    return struct.unpack_from('<I', c['ram'], a - VRAM_LO)[0]


# bytes of a word left out of the compare (the mask keeps the compared bits): the byte 0x200011C4,
# the acquisition handshake: the main loop sets it after a result, the DMA interrupt fn_080085d0
# clears it at the end of a DAC period (periph_34.s 878; own.inc V_MEAS_RESTART); at a pass start
# it depends on the time between the two, measured 2026-11-21 (speed 0 -> 2 and 1 -> 2: 0 after the
# key path, 1 after the direct change at the same result count); the gain bytes 0x200011C5 /
# 0x200011C6 and 0x200011C7 of the word stay compared.
MASKED = {0x200011C4: 0xFFFFFF00}


def ram_diff(a, b, timer_words=()):
    """Addresses of the differing words outside the stack, TICK_WORDS, HEAP_COUNTERS, the drawing
    scratch (DRAW_BUF, DRAW_AREA), the timer records' tick words and the MASKED bits."""
    out = []
    ra, rb = a['ram'], b['ram']
    if ra == rb:
        return out
    # the DAC sine table 0x20005120 (room for 180 halfwords): own_dac_setup (own/meas.s) writes n
    # entries (36 from 100 kHz, 150 at 120 Hz, else 180) and DMA2 ch3 plays those n (count n,
    # circular); the entries from n on are left from an earlier frequency, which the key path and the
    # direct change pass differently (measured 2026-11-22, 120 -> 100000 Hz: the key path's tail from
    # the 10 kHz table, the direct change's from the 120 Hz one). Compared up to n only, n from the
    # frequency word of both captures (equal, else the word itself differs).
    f = struct.unpack_from('<I', ra, 0x20001144 - VRAM_LO)[0]
    n_dac = 36 if f >= 100000 else 150 if f == 120 else 180
    dac_tail = (0x20005120 + 2 * n_dac, 0x20005120 + 2 * 180)
    for o in range(0, VRAM_N, 64):
        if ra[o:o + 64] == rb[o:o + 64]:
            continue
        for k in range(o, o + 64, 4):
            ad = VRAM_LO + k
            if (ra[k:k + 4] != rb[k:k + 4] and not STACK[0] <= ad < STACK[1] and ad not in TICK_WORDS
                    and ad not in HEAP_COUNTERS and ad not in timer_words and ad != DRAW_AREA
                    and not DRAW_BUF[0] <= ad < DRAW_BUF[1] and not IMAGE_REC[0] <= ad < IMAGE_REC[1]
                    and not GLYPH_CACHE[0] <= ad < GLYPH_CACHE[1]
                    and not dac_tail[0] <= ad < dac_tail[1]
                    and not HEAP[0] <= ad < HEAP[0] + HEAP[1]):
                if ad in MASKED:
                    x, y = struct.unpack_from('<I', ra, k)[0], struct.unpack_from('<I', rb, k)[0]
                    if (x ^ y) & MASKED[ad] == 0:
                        continue
                out.append(ad)
    return out


def heap_walk(c):
    """The used blocks [(address, size)] of the GUI heap in the capture. Layout from the code:
    fn_08027a20 puts the first block at base + 0x53C (fn_0802799e: size word at r1 = (r2 - 8) & ~3
    with bit 0 set, the block header at r1 - 4, a 0-size end block with word 2); a block's size
    word is at header + 4, bit 0 = free (fn_08027a3c loops when it frees a free block), bits 2..
    the size; the next header is header + size + 4. The walk must end on the end block exactly at
    base + size - 8 (checked: a layout read wrongly would not land there)."""
    base, n = HEAP
    hdr = base + 0x53C - 4
    end = base + n - 8
    used = []
    while True:
        check(hdr <= end, 'heap walk past the end: 0x%08X' % hdr)
        sw = word(c, hdr + 4)
        size = sw & ~3
        if size == 0:
            break
        if not sw & 1:
            used.append((hdr + 8, size))
        hdr = hdr + size + 4
    check(hdr == end, 'heap walk ended at 0x%08X, not at the end block 0x%08X' % (hdr, end))
    return used


def px_diff(a, b):
    fa, fb = a['fb'], b['fb']
    return sum(1 for i in range(0, len(fa), 2) if fa[i:i + 2] != fb[i:i + 2]) if fa != fb else 0


def gpio_set_clear(a):
    """The GPIO set / clear registers (+0x10 PBSC, +0x14 PBC of the ports 0x40010800..): their
    last value is a command; the output state they leave is compared instead (meter_model 'pod')."""
    return 0x40010800 <= a < 0x40012000 and (a & 0x3FF) in (0x10, 0x14)


def mmio_last(c):
    last = {}
    for a, v in c['mmio']:
        if not BEEP[0] <= a < BEEP[1] and a not in STACK_DEPENDENT and not gpio_set_clear(a):
            last[a] = v
    return last


def beeps(c):
    return [(a, v) for a, v in c['mmio'] if BEEP[0] <= a < BEEP[1]]


def key_events(c):
    return [f for f in c['frames'] if f['type'] == FR_EVENT and f['cmd'] == E_KEY]


def press(rig, mask, hold=0):
    st, s = rig.ask('KEY', struct.pack('<BH', KEY_BIT[mask], hold))
    check(st == S_OK, 'KEY 0x%04X hold %d: status %d' % (mask, hold, st))


def in_heap(p):
    return HEAP[0] <= p < HEAP[0] + HEAP[1] - 4 and not p & 3


def cover_of(c, g):
    """The cover of glyph object g in capture c (fmt.s row_cover_of: the first child), or 0; every
    pointer on the way is followed only into the GUI heap (UNIT_PIC comment)."""
    at = word(c, g + OBJ_ATTR) if in_heap(g) else 0
    if not in_heap(at) or not word(c, at + 4) or not in_heap(word(c, at)):
        return 0
    cr = word(c, word(c, at))
    return cr if in_heap(cr) else 0


def key_only_covers(ref, direct):
    """[(glyph, its attribute block, cover)] of the glyphs (the same object in both captures) that have
    a cover in the key path's capture and none in the direct one (GLYPHS comment)."""
    out = []
    for row in (0, 1):
        for i in range(7):
            a = GLYPHS + 32 * row + 4 * i
            g = word(ref, a)
            if not g or word(direct, a) != g:
                continue
            cr = cover_of(ref, g)
            if cr and not cover_of(direct, g):
                out.append((g, word(ref, g + OBJ_ATTR), cr))
    return out


def cover_blocks_out(what, ref, direct, hr, hd, covers):
    """Checks the key-path-only covers: each hidden, 0x20000460 higher by COVER_DATA_BLOCKS per cover,
    no used block only in the direct capture, and the blocks only in the key path's capture exactly
    those reached from the covers' attribute blocks and objects by pointers (within those blocks).
    Returns hr without them."""
    for g, at, cr in covers:
        check(word(ref, cr + OBJ_FLAGS) & 1, '%s: cover 0x%08X of glyph 0x%08X shown' % (what, cr, g))
    n = word(ref, DATA_COUNT) - word(direct, DATA_COUNT)
    check(n == COVER_DATA_BLOCKS * len(covers), '%s: 0x%08X higher by %d for %d covers'
          % (what, DATA_COUNT, n, len(covers)))
    only, extra = set(hr) - set(hd), set(hd) - set(hr)
    check(not extra, '%s: %d used heap blocks only in the direct capture' % (what, len(extra)))

    def inside(q):
        return [(b, z) for b, z in only if b <= q < b + z]
    reach, todo = set(), [blk for g, at, cr in covers for p in (at, cr) for blk in inside(p)]
    while todo:
        b, z = todo.pop()
        if (b, z) in reach:
            continue
        reach.add((b, z))
        for w in range(b, b + z - z % 4, 4):
            todo.extend(inside(word(ref, w)))
    check(reach == only, '%s: %d heap blocks only in the key path, %d of them reached from its %d covers'
          % (what, len(only), len(reach), len(covers)))
    NOTES.append('%s: %d covers only after the key path (%d heap blocks, all hidden)'
                 % (what, len(covers), len(reach)))
    return [x for x in hr if x not in reach]


def compare(what, ref, direct, expected=()):
    """ref / direct: the two captures. expected: {address: reason} of the case (2.4). Checks the
    comparison of the file header; returns the differing words (all allowed)."""
    allowed = dict(KEY_ONLY)
    allowed.update(dict(expected))
    covers = key_only_covers(ref, direct)
    if covers:
        allowed[DATA_COUNT] = 'data blocks of the covers only the key path made (GLYPHS comment)'
    diff = ram_diff(ref, direct, ref['timer_words'] | direct['timer_words'])
    bad = [a for a in diff if a not in allowed]
    check(not bad, '%s: RAM words differ from the key path: %s' % (
        what, ', '.join('0x%08X %08X/%08X' % (a, word(ref, a), word(direct, a)) for a in bad[:16])))
    hr, hd = heap_walk(ref), heap_walk(direct)
    tw = ref['timer_words'] | direct['timer_words']        # timer records live in the heap
    if covers:
        hr = cover_blocks_out(what, ref, direct, hr, hd, covers)
        tw = tw | {g + OBJ_ATTR for g, at, cr in covers}    # the glyph's attribute block word
    u = word(ref, UNIT_PIC)
    if (u == word(direct, UNIT_PIC) and in_heap(u) and word(ref, u + OBJ_FLAGS) & 1
            and word(direct, u + OBJ_FLAGS) & 1):
        uw = {u + o for o in UNIT_PIC_IMAGE_WORDS}
        if any(word(ref, w) != word(direct, w) for w in uw):
            NOTES.append('%s: image words of the hidden unit picture differ (UNIT_PIC comment)' % what)
        tw = tw | uw
    check(hr == hd, '%s: GUI heap blocks differ: %d / %d used, %d / %d bytes' % (
        what, len(hr), len(hd), sum(s for a, s in hr), sum(s for a, s in hd)))
    objs = [k[1] for k in allowed if isinstance(k, tuple) and k[0] == 'obj']
    for o in objs:              # an expected object: its heap block and the blocks its words point
        p = word(ref, o)        # to (its data block +8, fn_0802318c, gui_21.s 403-410, and the like)
        blk = [(a, s) for a, s in hr if a <= p < a + s]
        for a, s in blk:
            ptrs = [word(ref, w) for w in range(a, a + s - s % 4, 4)]
            blk2 = [(b, z) for b, z in hr if any(b <= q < b + z for q in ptrs)]
            for b, z in blk + blk2:
                tw = tw | set(range(b, b + z, 4))
    live = [w for a, s in hr for w in range(a, a + s - s % 4, 4)
            if w not in tw and ref['ram'][w - VRAM_LO:w - VRAM_LO + 4] != direct['ram'][w - VRAM_LO:w - VRAM_LO + 4]]
    if ('heap', 'layout') in allowed and live:  # 20-byte layout records of hidden objects: linked
        NOTES.append('%s: %d heap words of hidden-object layout records differ (allowed: %s)' % (
            what, len(live), allowed[('heap', 'layout')]))
        live = []                               # from list nodes, not from the objects
    check(not live, '%s: words of used GUI heap blocks differ: %s' % (
        what, ', '.join('0x%08X %08X/%08X' % (w, word(ref, w), word(direct, w)) for w in live[:8])))
    n = px_diff(ref, direct)
    check(n == 0, '%s: %d pixels differ from the key path' % (what, n))
    lr, ld = mmio_last(ref), mmio_last(direct)
    regs = [a for a in sorted(set(lr) | set(ld)) if lr.get(a) != ld.get(a)]
    check(not regs, '%s: peripheral registers differ: %s' % (what, ', '.join(
        '0x%08X %r/%r' % (a, lr.get(a), ld.get(a)) for a in regs[:12])))
    pmask = {k[1]: k[2] for k in allowed if isinstance(k, tuple) and k[0] == 'pod'}
    pod = [port for port in sorted(set(ref['pod']) | set(direct['pod']))
           if (ref['pod'].get(port, 0) ^ direct['pod'].get(port, 0)) & ~pmask.get(port, 0)]
    check(not pod, '%s: GPIO outputs differ: %s' % (what, ', '.join(
        '0x%08X %r/%r' % (q, ref['pod'].get(q), direct['pod'].get(q)) for q in pod)))
    check(not beeps(direct), '%s: TIM2 (beep) written by the direct change: %r' % (what, beeps(direct)[:4]))
    check(not key_events(direct), '%s: KEY events in the direct run' % what)
    check(direct['stretch'] < PERIOD_MIN, '%s: watchdog stretch %.3f s' % (what, direct['stretch']))
    return diff


# ---------------------------------------------------------------- states

_BASE = {}


def base():
    """The machine after the start-up (measure screen), cached for the run: (rig, Snapshot)."""
    if 'snap' not in _BASE:
        rig = make_rig()
        _BASE['rig'], _BASE['snap'] = rig, Snapshot(rig)
    snap = _BASE['snap']
    snap.restore()
    return snap.rig


def at(steps):
    """A state: the base, then the presses steps [(mask, hold)], then the run to a pass; a Snapshot."""
    rig = base()
    for mask, hold in steps:
        press(rig, mask, hold)
    rig.run(0.2)
    to_pass(rig)
    return Snapshot(rig)


def reach(rig, addr, mask, hold, target, limit=8):
    """Key path: press until the word at addr is target (as the old jobs did)."""
    n = 0
    while rig.rd(addr) != target:
        check(n < limit, 'key path: 0x%08X not at 0x%X after %d presses (now 0x%X)'
              % (addr, target, n, rig.rd(addr)))
        press(rig, mask, hold)
        n += 1
    return n


def pair(snap, what, ref_fn, cmd, payload, expected=(), answer=None):
    """Key path ref_fn(rig) and the direct command from snap; compare(); returns (ref, direct, data)."""
    snap.restore()
    rig = snap.rig
    t0 = window(rig)
    ref_fn(rig)
    ref = capture(rig, t0)
    snap.restore()
    t0 = window(rig)
    st, data = rig.ask(cmd, payload)
    check(st == S_OK, '%s: %s status %d' % (what, cmd, st))
    if answer is not None:
        check(len(data) == answer, '%s: %s answer of %d bytes' % (what, cmd, len(data)))
    direct = capture(rig, t0, ref)
    diff = compare(what, ref, direct, expected)
    return ref, direct, diff


# ---------------------------------------------------------------- LCR_SET

def lcr_states(lid, prep=None):
    """{value: Snapshot} for every value the setting's key reaches from the base (after prep(rig))."""
    addr, mask, hold, values = LCR[lid]
    out = {}
    rig = base()
    if prep is not None:
        prep(rig)
    for _ in range(len(values) + 1):
        rig.run(0.2)
        to_pass(rig)
        v = rig.rd(addr)
        if v in out:
            break
        out[v] = Snapshot(rig)
        press(rig, mask, hold)
    return out


def lcr_pairs(lid, states, targets, what, expected_of=lambda s, t: ()):
    addr, mask, hold, values = LCR[lid]
    runs = 0
    for s, snap in sorted(states.items()):
        for t in targets:
            if t == s:
                continue
            w = '%s %r -> %r' % (what, s, t)
            ref, direct, diff = pair(snap, w, lambda r: reach(r, addr, mask, hold, t), 'LCR_SET',
                                     bytes([lid, values.index(t)]), expected_of(s, t), MEASURE_SIZE)
            check(word(direct, addr) == t, '%s: the direct change left 0x%X' % (w, word(direct, addr)))
            if diff:
                NOTES.append('%s: expected differences %s' % (w, ' '.join('0x%08X' % a for a in diff)))
            runs += 2
    return runs


# The second row's unit picture 0x20000220 left hidden with an earlier image by a key path through
# intermediate values (2.4 item 5): compare() leaves its image words out (UNIT_PIC comment at the top;
# it replaces the earlier rule of 2026-11-21 that allowed the object only for paths through theta,
# which missed paths through R, Run of 2026-11-24: Func 0 -> 2, secondary 4 -> 2).


def passes_theta(s, t):
    """The key path's presses (+1, wrap at 5) from s to t go through 4 (Z / theta) before t."""
    path, v = [], s
    while v != t:
        v = (v + 1) % 5
        path.append(v)
    return 4 in path[:-1]


def _lcr_case(lid, name):
    addr, mask, hold, values = LCR[lid]
    states = lcr_states(lid)
    check(sorted(states) == sorted(values), '%s: key path reached %r of %r' % (name, sorted(states), values))
    exp = lambda s, t: {}
    if lid == 5:
        # range: with the flat source (no signal) the ADC gain bytes 0x200011C5 / 0x200011C6 of the
        # word 0x200011C4 step on about every 0.5 s once the range is fixed (fn_0800b000 /
        # fn_0800b20c windows never met), and no result comes to align on (measured 2026-11-21,
        # dimpl/exp10: range 0 -> 3, C6 3, 2, 1, 0, 7 after the key path, 4, 6, 5, 4, 3 after the
        # direct change); their phase follows the time since the range left AUTO, which the key
        # path's presses through the other ranges set earlier
        # and the gain pins they drive (measure_model front_end: PC0..PC2 for 0x200011C5, PA1..PA3
        # for 0x200011C6; the range pins PC3 / PA0 stay compared)
        exp = lambda s, t: {0x200011C4: 'ADC gain bytes hunting without a signal (flat source)',
                            ('pod', 0x40011000, 0x0007): 'gain pins PC0..PC2',
                            ('pod', 0x40010800, 0x000E): 'gain pins PA1..PA3'}
    runs = lcr_pairs(lid, states, values, name, exp)
    NOTES.append('d01 %s: %d start values, %d runs' % (name, len(states), runs))
    return True


@case
def d01a_lcr_func_measure_screen():
    """LCR_SET Func, screen 1: every start value x every other value against the key path (key
    0x200; 2.3 / critique 6: AUTO touches only the Func picture)."""
    return _lcr_case(0, 'Func')


@case
def d01b_lcr_func_compare_screen():
    """LCR_SET Func in screen 2 (long 0x400 first): starts R / C / L (the key path forces Func 0 and
    4 to 1 there), targets 1..3. R from C or L: the key path passes Func 4 (secondary theta, the
    screen-2 rule then Func 1), the direct change takes the R branch (secondary X): 0x200011E8
    differs (DIRECT_SET_DESIGN.md 2.4 item 3)."""
    states = lcr_states(0, lambda r: press(r, 0x0400, LONG))
    check(sorted(states) == [1, 2, 3], 'screen 2 Func values %r' % sorted(states))
    # the second row's objects the compare screen hides (fn_0800d50c, ui_42.s 17-18: 0x200001F8 with
    # the secondary picture 0x200001EC under it, the eight digits 0x200059C8..0x200059E4, the unit
    # picture 0x20000220) are drawn for theta by the key path, for X by the direct change; measured
    # 2026-11-21 (dimpl/exp9): only these objects' heap blocks and 0x200011E8 differ, the panel not
    row2 = {('obj', a): '2.4 item 3: hidden second-row object' for a in [0x200001EC, 0x20000220]
            + list(range(0x200059C8, 0x200059E8, 4))}
    # and their 20-byte layout records (x offset of the digits, linked from neighbouring list nodes,
    # not from the objects; measured 2026-11-21, dimpl/exp9: words 0x8, x, 0x1E, 0x70009, ...)
    row2[('heap', 'layout')] = '2.4 item 3: layout records of the hidden second row'
    exp = lambda s, t: (({V_SECONDARY: '2.4 item 3: secondary of the R branch'} if t == 1 else {})
                        | (row2 if passes_theta(s, t) else {}))
    runs = lcr_pairs(0, states, (1, 2, 3), 'Func screen 2', exp)
    NOTES.append('d01b: %d runs' % runs)
    return True


@case
def d01c_lcr_secondary():
    return _lcr_case(1, 'secondary')


@case
def d01d_lcr_frequency():
    return _lcr_case(2, 'frequency')


@case
def d01e_lcr_level():
    """LCR_SET level with bias 0 (all three values) and with bias 0.5 V (0.1 / 0.3; 0.6 is refused,
    d02)."""
    runs = 0
    for b, want, name in ((BIASES[0], LEVELS, 'level, bias 0'), (BIASES[1], LEVELS[:2], 'level, bias 0.5')):
        states = lcr_states(3, lambda r: reach(r, V_BIAS, 0x0100, 0, b))
        check(sorted(states) == sorted(want), '%s: the key path reached %r' % (name, sorted(states)))
        runs += lcr_pairs(3, states, want, name)
    NOTES.append('d01e: %d runs' % runs)
    return True


@case
def d01f_lcr_bias():
    """LCR_SET bias from every level: 0 -> 0.5 V at 0.1 / 0.3 / 0.6 V (0.6 V becomes 0.3 V, the key
    path's fn_0800d940 mode 2), 0.5 -> 0 V at 0.1 / 0.3 V."""
    runs = 0
    for lvl in LEVELS:
        for b0 in BIASES:
            if b0 and lvl == LEVELS[2]:
                continue                        # 0.6 V with 0.5 V bias: not reachable
            rig = base()
            reach(rig, V_BIAS, 0x0100, 0, 0)
            reach(rig, V_LEVEL, 0x0800, 0, lvl)
            reach(rig, V_BIAS, 0x0100, 0, b0)
            check(rig.rd(V_LEVEL) == lvl, 'bias state: level 0x%X' % rig.rd(V_LEVEL))
            rig.run(0.2)
            to_pass(rig)
            snap = Snapshot(rig)
            t = BIASES[1] if b0 == 0 else 0
            w = 'bias 0x%X -> 0x%X at level 0x%X' % (b0, t, lvl)
            ref, direct, diff = pair(snap, w, lambda r: reach(r, V_BIAS, 0x0100, 0, t), 'LCR_SET',
                                     bytes([4, BIASES.index(t)]), (), MEASURE_SIZE)
            want_lvl = LEVELS[1] if t and lvl == LEVELS[2] else lvl
            check(word(direct, V_LEVEL) == want_lvl, '%s: level 0x%X' % (w, word(direct, V_LEVEL)))
            runs += 2
    NOTES.append('d01f: %d runs' % runs)
    return True


@case
def d01g_lcr_range():
    return _lcr_case(5, 'range')


@case
def d01h_lcr_speed():
    return _lcr_case(6, 'speed')


@case
def d01i_lcr_circuit():
    """LCR_SET circuit mode against long presses of key 0x1000 (1100 ms each)."""
    return _lcr_case(7, 'circuit')


# ---------------------------------------------------------------- HOLD

@case
def d01j_hold():
    """HOLD on / off in screens 1 and 2 against key 0x400 (app_01.s 475-486: the HOLD object shown /
    hidden, 0x200011C4 = 1 at off)."""
    runs = 0
    for steps, name in (((), 'screen 1'), (((0x0400, LONG),), 'screen 2')):
        s_off = at(steps)
        check(s_off.rig.rd(V_HOLD) == 0, '%s: hold at the start' % name)
        pair(s_off, 'HOLD on, ' + name, lambda r: reach(r, V_HOLD, 0x0400, 0, 1), 'HOLD', b'\x01',
             (), STATE_SIZE)
        s_off.restore()
        press(s_off.rig, 0x0400)
        s_off.rig.run(0.2)
        to_pass(s_off.rig)
        s_on = Snapshot(s_off.rig)
        pair(s_on, 'HOLD off, ' + name, lambda r: reach(r, V_HOLD, 0x0400, 0, 0), 'HOLD', b'\x00',
             (), STATE_SIZE)
        runs += 4
    NOTES.append('d01j: %d runs' % runs)
    return True


# ---------------------------------------------------------------- refusals

# every word a direct change writes itself (dset.s), checked unchanged after a refusal
DS_WORDS = (V_SCREEN, V_FUNC, V_SECONDARY, V_FREQ, V_LEVEL, V_BIAS, V_RANGE, V_SPEED, V_CIRCUIT, V_HOLD,
            V_MENU, V_DIALOG, V_BRIGHT, V_VOLUME, V_OFFTIME, V_CMP_TYPE, V_NOMINAL, V_TOLERANCE, V_SCALE,
            V_PREV_SCREEN, V_SEL, V_DIGIT) + V_WARN


def refused(rig, cmd, payload, status, size, what):
    w0 = [rig.rd(a) for a in DS_WORDS] + [rig.rd8(V_MAIN_ROW), rig.rd8(V_EDIT)]
    st, d = rig.ask(cmd, payload)
    check(st == status, '%s: %s status %d, expected %d' % (what, cmd, st, status))
    check(len(d) == size, '%s: answer of %d bytes, expected the record (%d)' % (what, len(d), size))
    w1 = [rig.rd(a) for a in DS_WORDS] + [rig.rd8(V_MAIN_ROW), rig.rd8(V_EDIT)]
    ch = ['0x%08X' % a for a, x, y in zip(DS_WORDS + (V_MAIN_ROW, V_EDIT), w0, w1) if x != y]
    check(not ch, '%s: words changed: %s' % (what, ch))
    check(rig.rd(OWN_CTL + CT_DS_OP) == 0, '%s: a direct change stayed pending' % what)


@case
def d02_refusals():
    """Refusals of ds_check (DIRECT_SET_DESIGN.md 2.2), nothing changed, the record in the answer:
    screen word 0 (written into RAM: the chooser is never reached in our build), CF_OFF_WAIT (the
    power-off path ran), a calibration running (0x200050E4 written 1), LCR_SET / HOLD in screen 3,
    Func 0 / 4 in screen 2, level 0.6 V with the bias at the key path's compare limit (bias bits
    0x3DCCCCCD refused; 0x3DCCCCCC: the key path reaches 0.6 V and so does the direct change), and the
    arguments (status 2, no data)."""
    every = (('SCREEN', b'\x02', STATE_SIZE), ('LCR_SET', b'\x06\x00', MEASURE_SIZE),
             ('HOLD', b'\x01', STATE_SIZE), ('SET_SET', struct.pack('<BH', 1, 30), STATE_SIZE),
             ('COMPARE_SET', struct.pack('<ffBBB', 47.0, 2.0, 1, 1, 1), COMPARE_SIZE))
    rig = base()
    for name, flag_word, value, status in (('screen 0', V_SCREEN, 0, S_NOT_NOW),
                                           ('calibration running', V_CAL_RUN, 1, S_SAFETY)):
        old = rig.rd(flag_word)
        rig.wr(flag_word, value)
        for cmd, p, size in every:
            refused(rig, cmd, p, status, size, '%s, %s' % (name, cmd))
        rig.wr(flag_word, old)
    fl = rig.rd(OWN_CTL + CT_FLAGS)
    rig.wr(OWN_CTL + CT_FLAGS, fl | CF_OFF_WAIT)
    for cmd, p, size in every:
        refused(rig, cmd, p, S_NOT_NOW, size, 'CF_OFF_WAIT, %s' % cmd)
    rig.wr(OWN_CTL + CT_FLAGS, fl)
    for cmd, p in (('SCREEN', b''), ('SCREEN', b'\x00'), ('SCREEN', b'\x04'), ('LCR_SET', b'\x08\x00'),
                   ('LCR_SET', b'\x03\x03'), ('LCR_SET', b'\x00'), ('HOLD', b'\x02'),
                   ('SET_SET', struct.pack('<BH', 0, 15)), ('COMPARE_SET', struct.pack('<ffBBB', 0.0005, 1, 0, 0, 0)),
                   ('COMPARE_SET', struct.pack('<ffBBB', 1.0, 100.0, 0, 0, 0)),
                   ('COMPARE_SET', struct.pack('<ffBB', 1.0, 1.0, 0, 0))):
        st, d = rig.ask(cmd, p)
        check(st == S_BAD_ARG and not d, '%s %s: status %d, %d bytes' % (cmd, p.hex(), st, len(d)))
    # screen 3: LCR_SET and HOLD refused
    s3 = at(((0x0008, LONG),))
    r = s3.rig
    check(r.rd(V_SCREEN) == 3, 'settings screen not reached')
    refused(r, 'LCR_SET', b'\x06\x00', S_NOT_NOW, MEASURE_SIZE, 'LCR_SET in screen 3')
    refused(r, 'HOLD', b'\x01', S_NOT_NOW, STATE_SIZE, 'HOLD in screen 3')
    # Func 0 / 4 in screen 2
    s2 = at(((0x0400, LONG),))
    for v in (0, 4):
        refused(s2.rig, 'LCR_SET', bytes([0, v]), S_NOT_NOW, MEASURE_SIZE, 'Func %d in screen 2' % v)
    # level 0.6 V and the bias limit of the key path's compare (ui_42.s .L0800d9f6)
    s = at(())
    r = s.rig
    reach(r, V_BIAS, 0x0100, 0, 0)
    reach(r, V_LEVEL, 0x0800, 0, LEVELS[1])
    r.run(0.2)
    to_pass(r)
    for bits, ok in ((0x3DCCCCCD, False), (0x3DCCCCCC, True), (BIASES[1], False)):
        snap = Snapshot(r)
        r.wr(V_BIAS, bits)
        if ok:
            snap2 = Snapshot(r)
            pair(snap2, 'level 0.6 V at bias 0x%08X' % bits, lambda q: reach(q, V_LEVEL, 0x0800, 0, LEVELS[2], 2),
                 'LCR_SET', b'\x03\x02', (), MEASURE_SIZE)
        else:
            refused(r, 'LCR_SET', b'\x03\x02', S_NOT_NOW, MEASURE_SIZE, 'level 0.6 V at bias 0x%08X' % bits)
            n = 0
            while n < 4:                         # the key path never reaches 0.6 V there
                press(r, 0x0800)
                check(r.rd(V_LEVEL) != LEVELS[2], 'key path reached 0.6 V at bias 0x%08X' % bits)
                n += 1
        snap.restore()
    return True


# ---------------------------------------------------------------- SCREEN

def nav_dialog(rig, item, edit=False):
    """Screen 3 (long 8), the menu item (key 0x20 steps over the visible items 0, 2..6), key 8
    (the dialog), with edit: key 8 again (the sorting dialog's row 0 being edited). Items 5 and 6:
    physical keys (test_own_control.nav_settings), as before revision 10 of MEASUREMENT_FIX_DESIGN (when
    key_refused refused an injected key 8 on item 5); the state reached is the same."""
    if item in (5, 6):
        T.nav_settings(rig, item, dialog=True)
        return
    press(rig, 0x0008, LONG)
    for _ in range(item - 1 if item else 0):
        press(rig, 0x0020)
    press(rig, 0x0008)
    if edit:
        press(rig, 0x0008)


def first_result():
    """Screen 1 at the first main-loop pass after the first published result of the start-up (a store
    of 1 to 0x20001200, own/meas.s meas_tail; Probe.results), a Snapshot. The state at(()) stands
    before it: there the display words 0x200050B8..0x200050C4 still hold the start-up 0 (emulator
    diagnostic 2026-11-23: 0 at that snapshot, the first result 1e10 stored 48 ms later by
    0x080544F6..0x08054506). From there the key path (a long press, 1.1 s) builds screen 2 after
    that result and draws "0L", the direct change builds it at once and draws 0.0000 with the
    marker of fmt.s (0 lies outside the accuracy table), whose amber covers (own_row_draw, six GUI
    objects with data blocks) put 0x20000460 at 0x42 against 0x36 and the heap pointers
    0x20000204..0x20000218 apart. Each path shows the values it finds; the comparison needs both
    to find the same ones."""
    rig = base()
    rig.probe.results = 0
    end = rig.m.run_for(seconds=1.2, until=lambda m: rig.probe.results > 0)   # a window period at
    check(end is None and rig.probe.results > 0, 'no result within 1.2 s of the start-up: %r' % end)
    to_pass(rig)                                                              # speed 0 (capture())
    check(rig.rd(V_SCREEN) == 1, 'first result state: screen %d' % rig.rd(V_SCREEN))
    return Snapshot(rig)


def screen_ref(target):
    """Key path of the old SCREEN job (own/ctl.s OP_SCREEN): long 8 from screen 3 until it is left
    (one press per dialog layer), long 0x400 between 1 and 2, long 8 into 3."""
    def run(r):
        n = 0
        while r.rd(V_SCREEN) != target:
            check(n < 6, 'screen key path: screen %d after %d presses' % (r.rd(V_SCREEN), n))
            s = r.rd(V_SCREEN)
            press(r, 0x0008 if s == 3 or target == 3 else 0x0400, LONG)
            n += 1
    return run


@case
def d03_screen_pairs_and_dialogs():
    """SCREEN between all screens (3 -> 1 / 2 with 0x200011BC = 1 and = 2) and from screen 3 with the
    sorting dialog open (item 0) and with its row being edited (the byte 0x2000000C), against the
    key path; the restore dialog (item 6): status 6, nothing changed; the calibration dialog (item 5) with
    no calibration running (MEASUREMENT_FIX_DESIGN revision 10 item 4): status 0, the target screen, the
    dialog closed, no calibration started, the calibration type as before."""
    runs = 0
    s1 = first_result()
    s2 = at(((0x0400, LONG),))
    s3a = at(((0x0008, LONG),))                              # from 1: 0x200011BC = 1
    s3b = at(((0x0400, LONG), (0x0008, LONG)))              # from 2: 0x200011BC = 2
    for snap, want in ((s3a, 1), (s3b, 2)):
        snap.restore()
        check(snap.rig.rd(V_SCREEN) == 3 and snap.rig.rd(V_PREV_SCREEN) == want,
              'screen 3 state: screen %d, 0x200011BC %d' % (snap.rig.rd(V_SCREEN), snap.rig.rd(V_PREV_SCREEN)))
    cases = [(s1, 'screen 1', 2), (s1, 'screen 1', 3), (s2, 'screen 2', 1), (s2, 'screen 2', 3),
             (s3a, 'screen 3 from 1', 1), (s3a, 'screen 3 from 1', 2), (s3b, 'screen 3 from 2', 1),
             (s3b, 'screen 3 from 2', 2)]
    rig = base()
    nav_dialog(rig, 0)
    rig.run(0.2)
    to_pass(rig)
    check(rig.rd(V_DIALOG) == 1 and rig.rd(V_MENU) == 0, 'sorting dialog not open')
    sd = Snapshot(rig)
    press(rig, 0x0008)
    rig.run(0.2)
    to_pass(rig)
    check(rig.rd8(V_EDIT) == 1, 'sorting row not being edited')
    se = Snapshot(rig)
    cases += [(sd, 'sorting dialog', 1), (sd, 'sorting dialog', 2), (se, 'sorting row edited', 1),
              (se, 'sorting row edited', 2)]
    for snap, name, t in cases:
        snap.restore()
        w = 'SCREEN %s -> %d' % (name, t)
        exp = {}
        if snap.rig.rd(V_SCREEN) == 3 and snap.rig.rd(V_PREV_SCREEN) != t:
            # the key path leaves to 0x200011BC's screen first and builds the target after it
            # (one screen build more); 0x20000460 counts the data blocks fn_0802318c ever created
            # (+1 each, never decreased, gui_21.s 403-410)
            exp = {0x20000460: 'count of the data blocks created: one screen build more by the key path'}
        if snap.rig.rd(V_SCREEN) == 3 and snap.rig.rd(V_DIALOG) == 1:
            # the key path closes the dialog with its redraws (piece 0x08009AA2: fn_0800f294(0, 0)
            # and the title), which the direct change leaves out (2.3); measured 2026-11-21: the
            # count 0x20000460 one higher after the key path
            exp = {0x20000460: 'count of the data blocks created: the dialog-closing redraws of the key path'}
        ref, direct, diff = pair(snap, w, screen_ref(t), 'SCREEN', bytes([t]), exp, STATE_SIZE)
        if diff:
            NOTES.append('%s: expected differences %s' % (w, ' '.join('0x%08X' % a for a in diff)))
        NOTES.append('%s: stretch %.0f ms' % (w, direct['stretch'] * 1e3))
        runs += 2
    rig = base()
    nav_dialog(rig, 6)
    rig.run(0.2)
    to_pass(rig)
    check(rig.rd(V_DIALOG) == 1 and rig.rd(V_MENU) == 6, 'dialog of item 6 not open')
    for t in (1, 2):
        refused(rig, 'SCREEN', bytes([t]), S_SAFETY, STATE_SIZE, 'SCREEN from the item 6 dialog')
        check(rig.rd(V_SCREEN) == 3 and rig.rd(V_DIALOG) == 1, 'item 6 dialog left')
    for t in (1, 2):
        rig = base()
        nav_dialog(rig, 5)
        rig.run(0.2)
        to_pass(rig)
        check(rig.rd(V_DIALOG) == 1 and rig.rd(V_MENU) == 5 and rig.rd(V_CAL_RUN) == 0,
              'dialog of item 5 not open, or a calibration runs (input)')
        typ = rig.rd(V_CAL_TYPE)
        st, s = rig.ask('SCREEN', bytes([t]))
        check(st == S_OK and len(s) == STATE_SIZE and rig.rd(V_SCREEN) == t and rig.rd(V_DIALOG) == 0,
              'SCREEN %d from the item 5 dialog: status %d screen %d dialog %d' % (t, st, rig.rd(V_SCREEN),
                                                                                rig.rd(V_DIALOG)))
        check(rig.rd(V_CAL_RUN) == 0 and rig.rd(V_CAL_TYPE) == typ, 'SCREEN %d from the item 5 dialog: running %d '
              'type %d (was %d)' % (t, rig.rd(V_CAL_RUN), rig.rd(V_CAL_TYPE), typ))
        runs += 1
    NOTES.append('d03: %d runs' % runs)
    return True


@case
def d04_screen_round_trips_heap():
    """50 round trips SCREEN 1 -> 3 -> 1 and 50 of 1 -> 2 -> 1: the GUI heap's used blocks (heap_walk
    at the start of a main-loop pass; the word 0x200004F4 counts the history, not the live heap,
    HEAP_COUNTERS) after each round trip are as many and as large as before the first (no object
    left behind)."""
    def live(r):
        to_pass(r)
        u = heap_walk(dict(ram=bytes(r.m.uc.mem_read(VRAM_LO, VRAM_N))))
        return len(u), sum(s for a, s in u)
    rig = base()
    # one warm-up round trip via 3 and via 2 first: the glyphs of a rebuilt measure screen get the
    # amber covers of fmt.s own_row_draw (one child object per glyph, made at the glyph's first
    # marked draw, MEASUREMENT_FIX_DESIGN.md S2.1) at other draws than the glyphs of the first build;
    # they belong to live objects and are freed with them, and from then on every round trip gives
    # the same heap
    for t in (3, 1, 2, 1):
        st, s = rig.ask('SCREEN', bytes([t]))
        check(st == S_OK and rig.rd(V_SCREEN) == t, 'warm-up via %d: status %d' % (t, st))
    u0 = live(rig)
    for mid in (3, 2):
        for k in range(50):
            for t in (mid, 1):
                st, s = rig.ask('SCREEN', bytes([t]))
                check(st == S_OK and rig.rd(V_SCREEN) == t, 'round trip %d via %d: status %d' % (k, mid, st))
            u = live(rig)
            check(u == u0, 'round trip %d via %d: heap blocks / bytes in use %r, before %r' % (k, mid, u, u0))
    NOTES.append('d04: %d heap blocks, %d bytes in use before and after 2 x 50 round trips' % u0)
    return True


# ---------------------------------------------------------------- SETTINGS_SET

def tim3(rig):
    return rig.rd(TIM3_CCDAT)


@case
def d05_settings_set():
    """SETTINGS_SET in screens 1 and 2: the word, the screen stays, brightness: the TIM3 compare
    (9 x value) x 4 (fn_08009e60, lcd_31.s 483); in screen 3 on the menu item against the key path
    (key 4 / 0x10 on items 2..4, fn_0800f5e8), and the warn words with the sorting dialog open and
    a row being edited against key 4 / 0x10 there."""
    runs = 0
    for steps, name in (((), 'screen 1'), (((0x0400, LONG),), 'screen 2')):
        snap = at(steps)
        for sid, addr, vals in ((0, V_BRIGHT, (10, 50, 90)), (1, V_VOLUME, (20, 100)), (2, V_OFFTIME, (0, 3)),
                                (3, V_WARN[0], (0, 1)), (4, V_WARN[1], (0, 1)), (5, V_WARN[2], (0, 1))):
            for v in vals:
                snap.restore()
                rig = snap.rig
                scr = rig.rd(V_SCREEN)
                st, s = rig.ask('SET_SET', struct.pack('<BH', sid, v))
                check(st == S_OK and len(s) == STATE_SIZE and rig.rd(addr) == v and rig.rd(V_SCREEN) == scr,
                      '%s id %d = %d: status %d value %d screen %d' % (name, sid, v, st, rig.rd(addr), rig.rd(V_SCREEN)))
                if sid == 0:
                    check(tim3(rig) == 9 * v * 4, '%s brightness %d: TIM3 compare %d' % (name, v, tim3(rig)))
                runs += 1
    # screen 3, menu items 2..4: one key press against the direct value
    for sid, item, addr in ((0, 2, V_BRIGHT), (1, 3, V_VOLUME), (2, 4, V_OFFTIME)):
        rig = base()
        press(rig, 0x0008, LONG)
        for _ in range(item - 1):
            press(rig, 0x0020)
        rig.run(0.2)
        to_pass(rig)
        snap = Snapshot(rig)
        cur = rig.rd(addr)
        up = cur < (100 if sid < 2 else 3)
        t = cur + (10 if sid < 2 else 1) * (1 if up else -1)
        pair(snap, 'SET_SET id %d in the menu' % sid, lambda r: press(r, 0x0004 if up else 0x0010), 'SET_SET',
             struct.pack('<BH', sid, t), (), STATE_SIZE)
        runs += 2
    # sorting dialog, row being edited: rows 2..4 = warn type / sound / LED (fn_0800f5e8 item 0)
    for sid in (3, 4, 5):
        rig = base()
        nav_dialog(rig, 0)
        for _ in range(sid - 1):
            press(rig, 0x0004)                  # row 0x200011B4 + 1
        press(rig, 0x0008)                      # edit the row
        rig.run(0.2)
        to_pass(rig)
        check(rig.rd(V_SEL) == sid - 1 and rig.rd8(V_EDIT) == 1, 'row %d not being edited' % (sid - 1))
        snap = Snapshot(rig)
        cur = rig.rd(V_WARN[sid - 3])
        pair(snap, 'SET_SET id %d in the sorting dialog' % sid,
             lambda r: press(r, 0x0010 if cur else 0x0004), 'SET_SET', struct.pack('<BH', sid, 1 - cur), (),
             STATE_SIZE)
        runs += 2
    NOTES.append('d05: %d runs' % runs)
    return True


# ---------------------------------------------------------------- COMPARE_SET

def f32_bits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def f32r(x):
    """x rounded to single precision (a product or quotient of two singles computed in double
    rounds once: double has more than 2 x 24 + 2 bits)."""
    return struct.unpack('<f', struct.pack('<f', x))[0]


def expect_compare(nominal, tol):
    """(scale index, nominal bits, tolerance bits) as DIRECT_SET_DESIGN.md 2.3 states them: the
    scale classes of fn_0800e4f8, count = nominal * 100 / scale (single multiply and divide, as
    nom_count) rounded to the integer (fn_080116a0; the test values are chosen with the quotient
    within 0.01 of an integer, checked, so the rounding mode is not in question), limited to
    100..99999, nominal = float(count) / 100 * scale; tolerance = float(tenths) / 10."""
    scales = (0.001, 1.0, 1000.0, 1e6)
    b = f32_bits(nominal)
    k = 0 if b < 0x3F800000 else 1 if b < 0x447A0000 else 2 if b < 0x49742400 else 3
    sc = f32r(scales[k])
    q = f32r(f32r(f32r(nominal) * 100.0) / sc)
    check(abs(q - round(q)) < 0.01, 'test value %r: quotient %r not near an integer' % (nominal, q))
    count = min(99999, max(100, int(round(q))))
    nom = f32r(f32r(float(count) / 100.0) * sc)
    tenths = min(999, int(f32r(f32r(f32r(tol) * 10.0) + 0.5)))
    return k, f32_bits(nom), f32_bits(f32r(float(tenths) / 10.0))


def screen2_texts(rig):
    """The texts of the compare screen's objects 0x20000204..0x20000218 (fn_0800d50c creates them,
    fn_0800f854 writes nominal, OK / NG and deviation): the text pointer at object + 0x24
    (gui_20.s fn_080222b8 reads it there), up to 16 bytes; a pointer outside RAM as its number."""
    out = []
    for a in range(0x20000204, 0x2000021C, 4):
        t = rig.rd(rig.rd(a) + 0x24)
        out.append(bytes(rig.m.uc.mem_read(t, 16)).split(b'\0')[0] if 0x20000000 <= t < 0x20018000 else t)
    return out


@case
def d06_compare_set():
    """COMPARE_SET in screens 1, 2 and 3 (sorting dialog open): the answer (COMPARE, 29 bytes), the
    nominal / tolerance bits (expect_compare), the scale word, the warn words, the screen stays; in
    screen 1 Func / 0x20001178 / the main row unchanged (2.4 item 1: no fn_0800e4f8); in the dialog
    the display equals the one a fresh build of the same values draws (long 8 closes it, key 8
    opens it again), pixel for pixel; in screen 2 the texts of the compare screen's objects equal
    those of a fresh build (SCREEN 1 then 2), pixel differences are noted (see the comment)."""
    vals = ((2200.0, 1.0, 1, 0, 1), (0.0472, 12.34, 0, 1, 0), (47e3, 0.05, 1, 1, 1), (3.3e6, 99.9, 0, 0, 0),
            (999.99, 5.0, 0, 0, 1))
    runs = 0
    for steps, name in (((), 'screen 1'), (((0x0400, LONG),), 'screen 2'), (None, 'sorting dialog')):
        if steps is None:
            rig = base()
            nav_dialog(rig, 0)
            rig.run(0.2)
            to_pass(rig)
            snap = Snapshot(rig)
        else:
            snap = at(steps)
        for nominal, tol, wt, ws, wl in vals:
            snap.restore()
            rig = snap.rig
            before = {a: rig.rd(a) for a in (V_SCREEN, V_FUNC, V_CMP_TYPE)}
            row0 = rig.rd8(V_MAIN_ROW)
            st, d = rig.ask('COMPARE_SET', struct.pack('<ffBBB', nominal, tol, wt, ws, wl))
            k, nb, tb = expect_compare(nominal, tol)
            w = '%s %r' % (name, (nominal, tol))
            check(st == S_OK and len(d) == COMPARE_SIZE, '%s: status %d, %d bytes' % (w, st, len(d)))
            got = (rig.rd(V_SCALE), rig.rd(V_NOMINAL), rig.rd(V_TOLERANCE), tuple(rig.rd(a) for a in V_WARN))
            check(got == (k, nb, tb, (wt, ws, wl)), '%s: scale / nominal / tolerance / warn %r, expected %r'
                  % (w, got, (k, nb, tb, (wt, ws, wl))))
            check(struct.unpack_from('<II', d, 1) == (nb, tb), '%s: answer nominal / tolerance' % w)
            check(rig.rd(V_SCREEN) == before[V_SCREEN], '%s: screen changed' % w)
            if steps == ():
                check(rig.rd(V_FUNC) == before[V_FUNC] and rig.rd(V_CMP_TYPE) == before[V_CMP_TYPE]
                      and rig.rd8(V_MAIN_ROW) == row0, '%s: Func / compare quantity / main row changed' % w)
            runs += 1
            if steps == ():
                continue
            rig.run(SETTLE)
            to_pass(rig)
            fb1 = bytes(rig.m.panel.fb)
            t1 = screen2_texts(rig) if steps else None
            if steps is None:
                press(rig, 0x0008, LONG)
                press(rig, 0x0008)
            else:
                rig.ask_ok('SCREEN', b'\x01')
                rig.ask_ok('SCREEN', b'\x02')
            rig.run(SETTLE)
            to_pass(rig)
            fb2 = bytes(rig.m.panel.fb)
            n = sum(1 for i in range(0, len(fb1), 2) if fb1[i:i + 2] != fb2[i:i + 2])
            if steps is None:
                check(n == 0, '%s: %d pixels differ from a fresh build of the same values' % (w, n))
            else:
                # compare screen: the texts of its objects against the fresh build; the pixels are
                # noted only: with the flat source the deviation is "-0.00" (from a NaN reading),
                # whose '-' the deviation font lacks (a box glyph), and the box's last row depends on
                # the label's redraw area (measured 2026-11-21: 14 pixels of one row, NOTES "Direct set")
                t2 = screen2_texts(rig)
                check(t1 == t2, '%s: compare screen texts %r, a fresh build %r' % (w, t1, t2))
                if n:
                    NOTES.append('%s: %d pixels differ from a fresh build (texts equal)' % (w, n))
    NOTES.append('d06: %d runs' % runs)
    return True


# ---------------------------------------------------------------- keys during a direct change

@case
def d07_keys_and_events():
    """A physical key held: the change waits (no ds_run while 0x20000008 != 0) and runs after the
    release, once the event of the release was handled (no ds_run in a pass with an event in the
    slot); a key held 2.5 s: status 4, nothing changed, no change later; the direct change sends
    SETTING_CHANGED for the word and no KEY event."""
    rig = base()
    rig.m.watch(rig.s['ds_run'], 'ds_run')
    rig.m.watch(rig.s['fn_08009614'], 'handler')
    snap = Snapshot(rig)
    sec0, sp0 = rig.rd(V_SECONDARY), rig.rd(V_SPEED)
    t = (sp0 + 1) % 3
    rig.keys.down |= 0x0040                     # secondary key held
    rig.run(0.05)
    rig.host.send(T.C['LCR_SET'], bytes([6, t]))
    rig.run(0.4)
    check(rig.rd(V_SPEED) == sp0, 'speed changed while a key is held')
    log0 = len(rig.m.st['log'])
    rig.keys.down &= ~0x0040
    f = None
    t_end = rig.m.now() + 2.0
    while f is None and rig.m.now() < t_end:
        for fr in rig.host.recv(timeout=0.05):
            if fr['type'] == T.FR_ANSWER:
                f = fr
    check(f is not None and f['payload'][0] == S_OK, 'answer after the release: %r' % (f and f['payload'][:1]))
    order = [e[1] for e in rig.m.st['log'][log0:] if e[0] == 'at' and e[1] in ('ds_run', 'handler')]
    check(order[:2] == ['handler', 'ds_run'], 'order after the release: %r' % order[:4])
    check(rig.rd(V_SPEED) == t and rig.rd(V_SECONDARY) == (sec0 + 1) % 5, 'speed %d secondary %d'
          % (rig.rd(V_SPEED), rig.rd(V_SECONDARY)))
    # held 2.5 s: status 4, nothing changed, nothing later
    snap.restore()
    rig = snap.rig
    rig.keys.down |= 0x0040
    rig.run(0.05)
    st, d = rig.ask('LCR_SET', bytes([6, t]), timeout=4.0)
    check(st == S_BUSY and len(d) == MEASURE_SIZE, 'key held: status %d' % st)
    check(rig.rd(OWN_CTL + CT_DS_OP) == 0 and rig.rd(V_SPEED) == sp0, 'key held: change pending / made')
    rig.keys.down &= ~0x0040
    rig.run(0.5)
    check(rig.rd(V_SPEED) == sp0, 'the dropped change ran after the release')
    # events of a direct change
    snap.restore()
    rig = snap.rig
    rig.host.frames[:] = []
    st, d = rig.ask('LCR_SET', bytes([6, t]))
    ev = [fr for fr in rig.host.frames + rig.drain(0.2) if fr['type'] == FR_EVENT]
    check(st == S_OK and not [fr for fr in ev if fr['cmd'] == E_KEY], 'KEY events of a direct change')
    sc = [struct.unpack_from('<HI', fr['payload']) for fr in ev if fr['cmd'] == E_SETTING]
    check((V_SPEED - V_BLOCK, t) in sc, 'SETTING_CHANGED of the speed word: %r' % sc)
    return True


def main():
    sel = sys.argv[1:]
    bad = run = 0
    for fn in CASES:
        if sel and not any(fn.__name__.startswith(p) for p in sel):
            continue
        run += 1
        t0 = time.time()
        try:
            ok = fn()
            msg = ''
        except AssertionError as e:
            ok, msg = False, str(e)
        except Exception as e:      # a failing case must not hide the others
            ok, msg = False, 'raised %r' % e
        print('%-52s %s %s (%.0f s)' % (fn.__name__, 'ok' if ok else 'FAIL', msg, time.time() - t0), flush=True)
        bad += not ok
    for n in NOTES:
        print('  note:', n)
    print('%d tests, %d failed' % (run, bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
