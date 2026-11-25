#!/usr/bin/env python3
"""test_own_control.py - the USB control channel of our application build, in the emulator.

Usage (from the repository root, after `make -C starter`, `make -C bootloader slot` and
`make -C firmware own`):
    <python with unicorn 2.1.4> tests/test_own_control.py [case-name-prefix ...] [--key BIT] [--hold 0|1100] [--fresh]
k30 (the guard sweep: every key x short / hold x every state, the costly part) is one case per state,
k30a..k30l (prefix k30 selects all, k30c one state); --key / --hold narrow it to one key bit and / or
one hold time. Each case builds and navigates one rig for its state, snapshots the whole machine
(class Snapshot) and restores it before every key run; --fresh builds a new rig from power-on for every
run instead (the slow reference). k30 prints one 'k30rec' line per run (state, bit, hold, answer status,
refused, check values) in both modes.

Specification: the requirements and decisions of the USB control channel (never brick, never lose the
calibration, the IWDG period 0.67..1.33 s, own RAM 0x20018000..0x2001DFFF, every confirming command takes
the u16 0x4F4B, the soft restart through the request word 0x2001FFF4) and of the settings save (copies
A and B, saves held while no copy is valid or A is damaged, the trailer mark read back before any erase),
and the interface comments of firmware/own/ctl.s, cmd.s, usb.s, screen.s, save.s, own.inc, ctl.inc.
Expected values come from those rules or from the RAM words the code reads (named per check).

Model: tests/meter_model.py in flash mode 'app' with timing (core 144 MHz, the IWDG at the LSI each
case names, NVIC, SysTick), tests/usb_host.py (UsbDevice on the chip side, UsbHost driving it), and
these test-side device models:
  - OwnMeter maps system memory 0x1FFF0000..0x1FFFFFFF (meter_model maps none, but usb_start and
    INFO read the chip UID 0x1FFFF7F0 and MEM_READ admits 0x1FFF0000..0x1FFF3FFF and
    0x1FFFF000..0x1FFFF811): a fixed test pattern, byte k = (13 k + 5) & 0xFF, with the test UID
    bytes 0x10..0x1B at 0x1FFFF7F0; any store there is a violation.
  - KeyPad: the GPIO input words (PID, +8) of ports A, B, C, E as fn_080094a0 reads them (app_01.s:
    a key reads 0 when pressed, except PB7 = bit 0x200, which reads 1 when pressed); every other pin
    reads 0 (not stated anywhere; no test depends on it).
  - MeasurePath (tests/measure_model.py): DMA1 / DMA2, ADC1..ADC4, TIM1, TIM6 and the DAC as the
    measurement uses them, with a device under test on the front end (Ctl(source=...); default
    DutSource(): a 1 kohm resistor, supply 4.0 V), so the measurement runs and its results update.
  - Panel (only where a case asks for it): the writes of fn_08009e30 / fn_08014f9c to the command
    port 0x6001FFFE and the data port 0x60020000 (2A x1 hi, lo, x2 hi, lo; 2B y the same; 2C then
    the pixels row-major in the window), logged per 2C burst.
  - The named-save gate (k30, k31): any erase or word program outside an own_save call from a named
    call site is a violation, so the run stops at the first one.
The application runs with the copies A / B made from the block the firmware itself builds on a
first start (default_block(): erased copies -> own_load finds none, 0x0800B4C8(1) writes the
defaults into RAM, its save is held), with the first-start flag 0x20001140 (block 0xBC4) set to 1.
Our build is English only (the language chooser and the Chinese texts are removed; tests/test_own_lang.py): own_load and own_save keep the
first-start flag and the language word at 1, so screen 0 (the language chooser) is never reached, and
the settings menu shows the vendor items 0, 2, 3, 4, 5, 6 (own_menu).
"""

import collections
import functools
import os
import random
import struct
import sys
import time
import types
import zlib

from unicorn import UC_HOOK_MEM_WRITE, UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_SP, UC_ARM_REG_LR, UC_ARM_REG_PC, UC_ARM_REG_R0, UC_ARM_REG_R1

from meter_model import (Meter, cell, SET_A, SET_B, PAGE, SLOTS, SLOT_SIZE, SLOT_DIR, REC0, REC1, REC_END,
                         ST_INSTALL, ST_TRIAL, ST_OK, ERASE_CUTS, WORD_CUTS, APP, RET, OWN_ELF, nm)
from measure_model import MeasurePath, DutSource
from usb_host import UsbDevice, UsbHost, UsbError, FR_STREAM, FR_EVENT, FR_ANSWER, make_frame, crc16

CASES = []
NOTES = []
OPTS = {'state': None, 'key': None, 'hold': None, 'fresh': False}

# ---- own.inc / ctl.inc / cmd.s ----
V_BLOCK, BLK = 0x2000057C, 0xC14
OWN_RAM = 0x20018000
OWN_STAGE = OWN_RAM + 0x2400
OWN_SAVE = OWN_RAM + 0x3020
SAVE_FLAGS, SAVE_STATUS, SAVE_COUNT = OWN_SAVE, OWN_SAVE + 4, OWN_SAVE + 8
OWN_USB = OWN_RAM + 0x3060
UO_RESERVE, UO_STARTED = 0x19, 0x1B
OWN_SCREEN = OWN_RAM + 0x30E0
OWN_CTL = OWN_RAM + 0x3120
CT_FLAGS, CT_DROPPED, CT_HAND_SLOT, CT_RESULT = 0x004, 0x024, 0x07C, 0x084
CT_I_MASK, CT_I_POSTED = 0x094, 0x0A8
CF_PRIMED, CF_OFF = 0x01, 0x02
V_KEYS_DOWN, V_KEY_CODE, V_KEY_MASK, V_KEY_TICKS = 0x20000008, 0x20001192, 0x20001194, 0x20001196
V_LANG_SET, V_LANGUAGE, V_SCREEN = 0x20001140, 0x2000115C, 0x20001168
V_FREQ, V_LEVEL, V_BIAS, V_FUNC, V_RANGE, V_SPEED, V_CIRCUIT = (0x20001144, 0x20001138, 0x2000113C, 0x20001148,
                                                               0x2000114C, 0x20001150, 0x20001154)
V_BRIGHT, V_HOLD, V_MENU, V_DIALOG = 0x20001158, 0x200011A4, 0x200011A8, 0x200011AC
V_FACTORY, V_MAIN_ROW, V_SECONDARY = 0x200011C0, 0x200011E4, 0x200011E8
V_Z, V_THETA, V_SUPPLY, V_LOWV = 0x200050C4, 0x200050CC, 0x20005100, 0x20005118
V_CAL_RUN, V_SWEEP_ON = 0x200050E4, 0x20005114
V_TICK = 0x20000480
REQ_WORD, REQ_MAGIC = 0x2001FFF4, 0x55504454
HANDOVER_WORD, HANDOVER_TAG = 0x2001FFF8, 0x534C0000
RESULT_WORD, RESULT_OK = 0x2001FFFC, 0x555201FE
SP_TOP = 0x200163A8
S_OK, S_UNKNOWN, S_BAD_ARG, S_NOT_NOW, S_BUSY, S_STORAGE, S_SAFETY, S_XFER_CRC = range(8)
SF_HELD, SF_RESTART = 0x01, 0x80
C = dict(INFO=0x00, PING=0x01, RESET=0x02, BATTERY=0x03, POWER_OFF=0x05, FACTORY_MODE=0x06, STATE=0x10,
         STREAM=0x11, SCREEN=0x12, KEY=0x13, LCR_TABLES=0x20, LCR_SET=0x21, MEASURE=0x22, MEASURE_STREAM=0x23,
         COMPARE=0x24, COMPARE_SET=0x25, HOLD=0x26, CALIBRATE=0x27, TOL_SET=0x28,
         OCAL_INFO=0x30, OCAL_READ=0x31, OCAL_WRITE=0x32, OCAL_ROLLBACK=0x33, OCAL_LOCK=0x34, OCAL_RAW=0x35,
         OCAL_TRACE=0x36, MONITOR=0x37, SET_TABLES=0x50, SET_SET=0x51,
         SET_SAVE=0x52, CAL_READ=0x53, RESTORE_DEF=0x54, RESTORE_B=0x55, ACCEPT_A=0x56, WRITE_BLOCK=0x57,
         SETUP_LANGUAGE=0x58, ACCEPT_B=0x59, ACCEPT_DEF=0x5A, SCREENSHOT=0x60, MEM_READ=0xF0,
         UPDATE_MODE=0x84, BOOT_BEGIN=0x85, BOOT_DATA=0x86, BOOT_END=0x87, BOOT_INSTALL=0x88, BOOT_STATUS=0x89)
E_KEY, E_SCREEN, E_SETTING, E_POWERED_OFF, E_MEASURE, E_SAVE, E_CAL = 0x90, 0x91, 0x93, 0x94, 0x95, 0x96, 0x97
OK2, OFF2 = struct.pack('<H', 0x4F4B), struct.pack('<H', 0x4F46)
CAPS_ALL, INFO_SIZE, STATE_SIZE, MEASURE_SIZE, COMPARE_SIZE = 0x0FEFFFFF, 58, 32, 66, 50   # bit 20 clear,
                                     # bit 21 direct set, bits 22..24 the stage-2 features
                                     # (60 Hz, tolerance modes, MEASURE marker byte 64 / SV_SAME), bit 25
                                     # the stage-3 sweep (own/cal.s), bit 26 the own calibration area
                                     # (own/ocal.s), bit 27 the start-up diagnostics (own/boot.s, INFO
                                     # 46..57, revision 17); MEASURE 64 + 2, COMPARE 29 + 21
# own.inc (revision 17, safe clock start-up and start-up diagnostics): no-init progress words, stages, clock flags; ctl.inc
# CT_RSTF; own.inc O_FUNC + MF_SECPICK; RCC (manual 6.3.2, 6.3.3, 6.3.11)
BOOT_PREV, BOOT_PROG, BOOT_TAG = 0x2001FFE8, 0x2001FFEC, 0x5350
STG_RESET, STG_CLOCK, STG_GPIO, STG_START, STG_LOAD, STG_CA2C, STG_C86C, STG_LOOP = 1, 2, 3, 4, 5, 12, 13, 14
CLKF_HSI, CLKF_PLL, CLKF_SW = 0x01, 0x02, 0x04
CT_RSTF = 0x08C
OWN_FUNC = OWN_RAM + 0x5DE0
MF_SECPICK = OWN_FUNC + 0x9C
RCC_CTRL, RCC_CFG = 0x40021000, 0x40021004
PLLEN = 1 << 24
APB_PRES = 0x3F00                # RCC_CFG APB2PRES 13:11, APB1PRES 10:8 (manual 6.3.3); fn_0800ba4c ors 0x2000 and
                                 # 0x500, own_pll_wait / own_sw_wait clear them on their timeouts (own.inc
                                 # RCC_APB2_DIV2, RCC_APB1_DIV4; fn_0800c274's mask 0xF8FFC000 cleared 13:8)
CT_OFF_T, CF_OFF_WAIT = 0x078, 0x04      # ctl.inc: tick of the power-off note, its flag in CT_FLAGS
V_KEY_BUSY = 0x20001190                  # own.inc: hold busy halfword (fn_08009400 0x08009468)
IWDGRSTF, PORRSTF, RST_FLAGS = 1 << 29, 1 << 27, 0xFEB80000
KEY_POWER, KEY_UP, KEY_OK = 0x0001, 0x0002, 0x0008
LSI = 60000                      # the shortest period, 2501 * 16 / 60000 s, for every watchdog check
PERIOD_MIN = 0.67                # the shortest IWDG period (the period is 0.67..1.33 s): the bound for every stretch
SYSMEM = 0x1FFF0000
UID = bytes(range(0x10, 0x1C))
POWER_OFF_LR = 0x08009479        # return address of the bl own_save at 0x08009474 (app_01.s; a same-size
                                 # hook keeps the address)
# return address of the bl own_save of the calibration finish: own/cal.s cal_finish (the label cal_save_ret
# after the bl; the vendor's bl at 0x0800BD1A is no longer reached in our build, stage 3)
CAL_FINISH_LR = (nm(OWN_ELF)['cal_save_ret'] & ~1) | 1

# GPIO of fn_080094a0 (app_01.s header): key bit -> (port base, pin mask)
KEY_PINS = {0x0001: (0x40011000, 0x40), 0x0002: (0x40011000, 0x80), 0x0004: (0x40011000, 0x100),
            0x0008: (0x40011000, 0x200), 0x0010: (0x40011000, 0x400), 0x0020: (0x40010800, 0x8000),
            0x0040: (0x40011000, 0x800), 0x0080: (0x40011000, 0x1000), 0x0100: (0x40010C00, 0x20),
            0x0200: (0x40010C00, 0x80), 0x0400: (0x40011800, 0x40), 0x0800: (0x40010C00, 0x100),
            0x1000: (0x40010C00, 0x200), 0x2000: (0x40011800, 0x01)}
ACTIVE_HIGH = 0x0200


def case(fn):
    CASES.append(fn)
    return fn


def check(cond, text):
    if not cond:
        raise AssertionError(text)


# ---------------------------------------------------------------- device models of this test

class KeyPad:
    def __init__(self):
        self.down = 0
        self.ranges = [(base + 8, base + 12) for base in sorted({p for p, _ in KEY_PINS.values()})]

    def read(self, m, a, size):
        base = a - 8
        v = 0
        for bit, (port, pin) in KEY_PINS.items():
            if port != base:
                continue
            pressed = bool(self.down & bit)
            level = pressed if bit == ACTIVE_HIGH else not pressed
            if level:
                v |= pin
        return v >> 8 * (a & 3)

    def write(self, m, a, size, value):
        m.violation('GPIO input register 0x%08X written' % a)


class Panel:
    """ST7789-type command / data ports as fn_08009e30 and fn_08014f9c use them."""

    def __init__(self):
        self.cmd = None
        self.args = []
        self.win = [0, 0, 319, 239]
        self.flushes = []          # [x1, y1, x2, y2, pixels]
        self.cur = None

    def write(self, addr, value):
        value &= 0xFFFF
        if addr == 0x6001FFFE:
            self.cmd = value & 0xFF
            self.args = []
            if self.cmd == 0x2C:
                self.cur = list(self.win) + [[]]
                self.flushes.append(self.cur)
            else:
                self.cur = None
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
        elif self.cmd == 0x2C and self.cur is not None:
            self.cur[4].append(value)


class OwnMeter(Meter):
    """Meter with system memory, the optional panel and the optional named-save gate."""
    panel = None
    named = None                   # set of own_save return addresses that may write flash, or None

    def make(self, keep_ram=False):
        uc = super().make(keep_ram)
        img = bytearray((13 * k + 5) & 0xFF for k in range(0x10000))
        img[0xF7F0:0xF7FC] = UID
        self.sysmem = bytes(img)
        uc.mem_map(SYSMEM, 0x10000)
        uc.mem_write(SYSMEM, self.sysmem)

        def sys_write(uc_, access, addr, size, value, user):
            self.violation('store to system memory 0x%08X' % addr)
        uc.hook_add(UC_HOOK_MEM_WRITE, sys_write, begin=SYSMEM, end=SYSMEM + 0xFFFF)
        if self.panel is not None:
            def lcd(uc_, access, addr, size, value, user):
                self.panel.write(addr, value)
            uc.hook_add(UC_HOOK_MEM_WRITE, lcd, begin=0x6001FFFE, end=0x60020001)
        self.in_named = False
        if self.named is not None and self.app_sym:
            def enter(uc_, addr, size, user):
                if uc_.reg_read(UC_ARM_REG_LR) in self.named:
                    self.in_named = True
            uc.hook_add(UC_HOOK_CODE, enter, begin=self.app_sym['own_save'], end=self.app_sym['own_save'])
            for lr in self.named:
                def leave(uc_, addr, size, user):
                    self.in_named = False
                uc.hook_add(UC_HOOK_CODE, leave, begin=lr & ~1, end=lr & ~1)
        return uc

    def _erase(self, pg):
        if self.named is not None and not self.in_named:
            self.violation('erase of 0x%08X outside a named save' % pg)
            return
        super()._erase(pg)

    def _program(self, a, old, new, value):
        if self.named is not None and not self.in_named:
            self.violation('word program of 0x%08X outside a named save' % a)
            return
        super()._program(a, old, new, value)


# ---------------------------------------------------------------- settings copies

def copy_image(blk, seq):
    img = bytearray(blk + b'\xff' * (0x1000 - len(blk)))
    struct.pack_into('<II', img, 0xFF8, seq, zlib.crc32(blk + struct.pack('<I', seq)))
    return bytes(img)


_DEFAULT = {}


def default_block():
    """The block 0x0800B4C8(1) writes on a start with no valid copy (read from RAM once the main
    loop runs), cached for the run."""
    if 'blk' not in _DEFAULT:
        rig = Ctl(a=b'\xff' * 0x1000, b=b'\xff' * 0x1000, usb=False)
        rig.to_main_loop()
        blk = rig.rd(V_BLOCK, BLK)
        check(struct.unpack_from('<I', blk, 0)[0] == 0x12345678 and struct.unpack_from('<I', blk, 0xC10)[0] == 0x12345678,
              'default block without markers')
        _DEFAULT['blk'] = blk
    return _DEFAULT['blk']


def block_with(lang_set=1, **words):
    b = bytearray(default_block())
    struct.pack_into('<I', b, V_LANG_SET - V_BLOCK, lang_set)
    for addr, v in words.items():
        struct.pack_into('<I', b, int(addr, 16) - V_BLOCK, v)
    return bytes(b)


# ---------------------------------------------------------------- the rig

def _load_host_library():
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools', 'lc1020e.py')
    spec = importlib.util.spec_from_file_location('lc1020e_host', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_HOST = _load_host_library()


def host_timeout(cmd, payload=b''):
    """Answer time of a command as the host library computes it for this firmware (timeout_for
    with the INFO capability word CAPS_ALL: bit 21, the direct commands wait T_DIRECT)."""
    return _HOST.timeout_for(cmd, payload, CAPS_ALL)


# ---------------------------------------------------------------- whole-machine snapshot (k30)

class Snapshot:
    """A complete copy of the emulated machine reachable from `roots` (the Ctl rig): the unicorn CPU
    context, the bytes of every RAM-like region, and a shallow copy of the contents of every mutable
    Python object reachable from the roots (instance dicts, dict, list, set, bytearray, deque, Random,
    closure cells of every function reachable, including the callbacks unicorn holds). restore()
    writes each saved content back INTO THE SAME OBJECT, so every closure and unicorn hook keeps
    pointing at live state; objects created after the snapshot are simply dropped. verify() compares
    the live state with the saved one and returns the list of differences (empty when restored)."""

    RAM_REGIONS = ((0x20000000, 0x24000), (0x60000000, 0x40000), (0xA0000000, 0x1000), (RET, 0x1000),
                   (SYSMEM, 0x10000))          # the regions that are plain memory, not MMIO or code flash
    ATOMS = (int, float, complex, str, bytes, bool, type(None), range, type, type(os), type(len))

    def __init__(self, rig):
        self.rig = rig
        self.uc = rig.m.uc
        self.objs = []                    # (object, kind, saved contents), in discovery order
        self.seen = set()
        self.keep = []
        for r in (rig, self.uc._callbacks, self.uc._mmio_callbacks):
            self._walk(r)
        self.ctx = self.uc.context_save()
        self.mem = [(lo, bytes(self.uc.mem_read(lo, n))) for lo, n in self.RAM_REGIONS]

    def _walk(self, root):
        todo = [root]
        while todo:
            o = todo.pop()
            if isinstance(o, self.ATOMS) or id(o) in self.seen or o is self.uc:
                continue
            self.seen.add(id(o))
            self.keep.append(o)
            kids = self._record(o)
            todo.extend(kids)

    def _record(self, o):
        """Record o's contents when it is a mutable container; return the objects it refers to."""
        if isinstance(o, dict):
            self.objs.append((o, 'dict', dict(o)))
            return list(o.keys()) + list(o.values())
        if isinstance(o, list):
            self.objs.append((o, 'list', list(o)))
            return list(o)
        if isinstance(o, set):
            self.objs.append((o, 'set', set(o)))
            return list(o)
        if isinstance(o, bytearray):
            self.objs.append((o, 'bytearray', bytes(o)))
            return []
        if isinstance(o, collections.deque):
            self.objs.append((o, 'deque', list(o)))
            return list(o)
        if isinstance(o, random.Random):
            self.objs.append((o, 'random', o.getstate()))
            return []
        if isinstance(o, (tuple, frozenset)):
            return list(o)
        if isinstance(o, types.CellType):
            try:
                v = o.cell_contents
            except ValueError:
                self.objs.append((o, 'cell', _EMPTY))
                return []
            self.objs.append((o, 'cell', v))
            return [v]
        if isinstance(o, types.FunctionType):
            kids = list(o.__closure__ or ())
            kids += list(o.__defaults__ or ()) + list((o.__kwdefaults__ or {}).values())
            return kids
        if isinstance(o, types.MethodType):
            return [o.__self__, o.__func__]
        if isinstance(o, (types.ModuleType, types.BuiltinFunctionType)):
            return []
        if isinstance(o, functools.partial):
            return [o.func] + list(o.args) + list((o.keywords or {}).values())
        if hasattr(o, '__dict__') and not hasattr(o, '__slots__'):
            d = o.__dict__
            self.objs.append((o, 'obj', dict(d)))
            return list(d.values())
        raise TypeError('snapshot: no rule for %s object %r' % (type(o).__name__, o))

    def restore(self):
        self.uc.context_restore(self.ctx)
        for lo, data in self.mem:
            self.uc.mem_write(lo, data)
        for o, kind, saved in self.objs:
            if kind == 'dict':
                o.clear()
                o.update(saved)
            elif kind == 'obj':
                o.__dict__.clear()
                o.__dict__.update(saved)
            elif kind == 'list':
                o[:] = saved
            elif kind == 'set':
                o.clear()
                o.update(saved)
            elif kind == 'bytearray':
                o[:] = saved
            elif kind == 'deque':
                o.clear()
                o.extend(saved)
            elif kind == 'random':
                o.setstate(saved)
            elif kind == 'cell' and saved is not _EMPTY:
                o.cell_contents = saved

    def verify(self):
        """Differences between the live state and the snapshot (after restore() this is empty)."""
        bad = []
        for lo, data in self.mem:
            if bytes(self.uc.mem_read(lo, len(data))) != data:
                bad.append('memory 0x%08X' % lo)
        for o, kind, saved in self.objs:
            if kind in ('dict', 'obj'):
                cur = o if kind == 'dict' else o.__dict__
                same = list(cur) == list(saved) and all(cur[k] is saved[k] or cur[k] == saved[k] for k in saved)
            elif kind == 'cell':
                try:
                    same = saved is not _EMPTY and o.cell_contents is saved
                except ValueError:
                    same = saved is _EMPTY
            elif kind == 'random':
                same = o.getstate() == saved
            elif kind == 'bytearray':
                same = bytes(o) == saved
            else:
                same = (list(o) if kind in ('list', 'deque') else set(o)) == saved
            if not same:
                bad.append('%s %s' % (kind, type(o).__name__))
        again = Snapshot(self.rig)
        if {id(x) for x in again.keep} != self.seen:
            bad.append('reachable object set changed')
        return bad


_EMPTY = object()


class Ctl:
    """Our build in mode 'app' with timing, KeyPad, UsbDevice and UsbHost.
    chain: start through starter and slot (records as given) instead of the reset vector."""

    def __init__(self, a=None, b=None, records=((REC0, cell(1, ST_OK, 1)),), chain=False, lsi=LSI,
                 core_hz=144_000_000, boot_target=None, usb=True, panel=False, named=None, ram=None,
                 devices=(), slots=('F', 'A', 'B'), patch=None, cpi=5, source=None):
        m = OwnMeter(slots=slots, records=list(records), starter=True, flash_mode='app', boot_target=boot_target)
        m.load_own()
        self.m, self.s = m, m.app_sym
        if a is None or b is None:
            blk = block_with()
            a = copy_image(blk, 2) if a is None else a
            b = copy_image(blk, 1) if b is None else b
        m.put(SET_A, a)
        m.put(SET_B, b)
        if patch:
            patch(m)
        m.panel = Panel() if panel else None
        m.named = named
        m.set_timing(lsi_hz=lsi, core_hz=core_hz, cpi=cpi)
        self.keys = m.attach(KeyPad())
        self.meas = self.adc = m.attach(MeasurePath(source if source is not None else DutSource()))
        for d in devices:
            m.attach(d)
        self.dev = UsbDevice(m)
        self.host = UsbHost(m, self.dev)
        if ram:
            r = bytearray(m.ram)
            for addr, v in ram.items():
                struct.pack_into('<I', r, addr - 0x20000000, v)
            m.ram = bytes(r)
        self.chain = chain
        self.start(keep_ram=bool(ram))
        self.usb = usb

    def start(self, keep_ram=True):
        m = self.m
        if self.chain:
            m.make(keep_ram=keep_ram)
            sp, pc = struct.unpack_from('<II', m.flash, 0)
            m.start(pc, sp)
        else:
            m.start_app(keep_ram=keep_ram)
        self.host = UsbHost(m, self.dev)

    # memory
    def rd(self, addr, n=4):
        data = bytes(self.m.uc.mem_read(addr, n))
        return struct.unpack('<I', data)[0] if n == 4 else data

    def rd8(self, addr):
        return self.rd(addr, 1)[0]

    def rd16(self, addr):
        return struct.unpack('<H', self.rd(addr, 2))[0]

    def wr(self, addr, v):
        self.m.uc.mem_write(addr, struct.pack('<I', v) if isinstance(v, int) else v)

    # time
    def run(self, seconds):
        end = self.m.run_for(seconds)
        check(end is None, 'chip run ended %r (violations %r)' % (end, self.m.st['viol']))

    def to_main_loop(self, timeout=5.0):
        end = self.m.run_for(seconds=timeout, until=lambda mm: self.rd(OWN_CTL + CT_FLAGS) & CF_PRIMED)
        check(end is None and self.rd(OWN_CTL + CT_FLAGS) & CF_PRIMED,
              'main loop not reached: end %r, violations %r' % (end, self.m.st['viol']))

    def up(self):
        """Main loop, then the host enumerates (DTR set)."""
        self.to_main_loop()
        if self.usb:
            self.info = self.host.enumerate()
        return self

    # physical keys
    def press(self, mask, ms=60):
        self.keys.down |= mask
        self.run(ms / 1000.0)
        self.keys.down &= ~mask
        self.run(0.1)

    # frames
    def ask(self, name, payload=b'', timeout=None):
        """timeout None: the answer time of the command from the host library tools/lc1020e.py
        (the firmware's own limit plus a margin, PROTOCOL.md 4.3), the same a companion uses."""
        if timeout is None:
            timeout = host_timeout(C[name], payload)
        f = self.host.request(C[name], payload, timeout=timeout)
        p = f['payload']
        check(len(p) >= 1, '%s: answer without status' % name)
        return p[0], p[1:]

    def ask_ok(self, name, payload=b'', timeout=None, size=None):
        st, data = self.ask(name, payload, timeout)
        check(st == S_OK, '%s: status %d' % (name, st))
        if size is not None:
            check(len(data) == size, '%s: %d data bytes, expected %d' % (name, len(data), size))
        return data

    def drain(self, seconds=0.05):
        out = []
        t_end = self.m.now() + seconds
        while self.m.now() < t_end:
            out += self.host.recv(timeout=t_end - self.m.now())
        return out

    def flash_ops(self):
        return self.m.flash_ops()


def f32(x):
    return struct.unpack('<f', struct.pack('<I', x))[0]


def stretch_in(m, t0, t1):
    """Longest gap between two consecutive IWDG counter loads (start / feed / reset) whose interval
    overlaps [t0, t1] (meter_model iwdg_log)."""
    loads = [e['t'] for e in m.iwdg_log if e['kind'] in ('start', 'feed', 'reset')]
    best = 0.0
    for x, y in zip(loads, loads[1:]):
        if y >= t0 and x <= t1:
            best = max(best, y - x)
    after = [t for t in loads if t <= t1]
    if after and m.tm['iw']['running']:
        best = max(best, t1 - after[-1])
    return best


# ---------------------------------------------------------------- enumeration and descriptors

@case
def k01_enumeration_and_descriptors():
    """Also: USB is started by ctl_loop's first pass, not before (the port appears only when
    requests are served; on a meter the start-up before the main loop took 2 s)."""
    rig = Ctl()
    rig.m.watch(rig.s['usb_start'], 'usb_start')
    rig.m.watch(rig.s['ctl_loop'], 'ctl_loop')
    rig.up()
    ev = [e for e in rig.m.events() if e in ('usb_start', 'ctl_loop')]
    check(ev[:2] == ['ctl_loop', 'usb_start'], 'start order %r' % ev[:4])
    info = rig.info
    d = info['device']
    check(d['bcdUSB'] == 0x0200 and d['cls'] == 0x02 and d['subclass'] == 0 and d['protocol'] == 0,
          'device class %r' % d)
    check(d['vid'] == 0x19F5 and d['pid'] == 0x1020 and d['mps0'] == 64 and d['bcdDevice'] == 0x0100
          and d['configs'] == 1, 'device %r' % d)
    s = info['strings']
    serial = ''.join('%02X' % x for x in UID)
    check(s.get(1) == 'FNIRSI' and s.get(2) == 'LC1020E' and s.get(3) == serial, 'strings %r' % s)
    check(info['lang'] == 0x0409, 'language 0x%04X' % info['lang'])
    cfg = info['config']
    check(cfg['config']['total'] == 67 and cfg['config']['attributes'] == 0xC0 and cfg['config']['max_power'] == 0x32
          and cfg['config']['value'] == 1, 'configuration %r' % cfg['config'])
    i0, i1 = cfg['interfaces']
    check((i0['cls'], i0['subclass'], i0['protocol']) == (2, 2, 1), 'interface 0 %r' % i0)
    check(i0['functional'] == [bytes([5, 0x24, 0, 0x10, 0x01]), bytes([5, 0x24, 1, 0, 1]), bytes([4, 0x24, 2, 2]),
                               bytes([5, 0x24, 6, 0, 1])], 'functional descriptors %r' % i0['functional'])
    check(i0['endpoints'] == [dict(address=0x83, attributes=3, max_packet=16, interval=16)], 'EP 0x83 %r' % i0['endpoints'])
    check(i1['cls'] == 0x0A and i1['endpoints'] == [dict(address=0x81, attributes=2, max_packet=64, interval=0),
                                                     dict(address=0x02, attributes=2, max_packet=64, interval=0)],
          'interface 1 %r' % i1)
    h = rig.host
    # line coding: 115200 8N1 until set (usb.s), then the value set; GET_STATUS device: self powered
    check(h.get_line_coding() == struct.pack('<IBBB', 115200, 0, 0, 8), 'line coding')
    lc = h.set_line_coding(9600, 2, 1, 7)
    check(h.get_line_coding() == lc, 'line coding not stored')
    check(h.control_in(0x80, 0, 0, 0, 2) == b'\x01\x00', 'GET_STATUS device')
    check(h.control_in(0x80, 8, 0, 0, 1) == b'\x01', 'GET_CONFIGURATION')
    # unsupported: device qualifier and string 4 STALL (usb.s rq_get_descriptor)
    for dt, idx in ((6, 0), (3, 4)):
        try:
            h.get_descriptor(dt, idx, 10)
            raise AssertionError('descriptor %d/%d not stalled' % (dt, idx))
        except UsbError:
            pass
    check(not rig.m.st['viol'], 'violations %r' % rig.m.st['viol'])
    return True


# ---------------------------------------------------------------- device commands

@case
def k02_info_ping_unknown():
    rig = Ctl(chain=True, ram={RESULT_WORD: RESULT_OK}).up()
    d = rig.ask_ok('INFO', size=INFO_SIZE)
    ver, caps = d[0], struct.unpack_from('<I', d, 1)[0]
    check(ver == 1 and caps == CAPS_ALL, 'version %d caps 0x%X' % (ver, caps))
    check(d[5:21] == b'LC1020E V1.1 OWN' and d[21:33] == UID, 'text %r uid %r' % (d[5:21], d[21:33]))
    slot_hdr = struct.unpack_from('<I', rig.m.flash, SLOTS[1] + 12 - 0x08000000)[0]
    size = rig.s['own_image_end'] - APP
    check(d[33] == 1 and struct.unpack_from('<III', d, 34) == (slot_hdr, size, 1),
          'slot %d / version, size, result %r' % (d[33], struct.unpack_from('<III', d, 34)))
    # bytes 46..57 (capability bit 27): power-on SRAM (no progress word of a previous start: 0), this
    # start at the main loop, RCC_CTRLSTS as read: the model's power-on value 0x0C000003 (manual
    # 6.3.11: PORRSTF, PINRSTF, LSIRD, LSIEN), its flags cleared by own_start afterwards
    prev, prog, rst = struct.unpack_from('<III', d, 46)
    check(prev == 0 and prog == BOOT_TAG << 16 | STG_LOOP and rst == 0x0C000003,
          'diagnostics 0x%08X 0x%08X 0x%08X' % (prev, prog, rst))
    check(rig.m.ctrlsts & RST_FLAGS == 0, 'RCC_CTRLSTS flags not cleared: 0x%08X' % rig.m.ctrlsts)
    # INFO read the update result: the word is cleared now (own_start kept it, 17.3)
    check(rig.rd(HANDOVER_WORD) == 0 and rig.rd(RESULT_WORD) == 0 and rig.rd(REQ_WORD) == 0, 'no-init words not cleared')
    check(rig.ask_ok('PING', b'abc') == b'abc', 'PING 3')
    big = bytes((7 * i) & 0xFF for i in range(511))
    check(rig.ask_ok('PING', big) == big, 'PING 511')
    st, data = rig.ask('PING', big + b'x')
    check(st == S_BAD_ARG and not data, 'PING 512: %d' % st)
    for cmd in (0x04, 0x7F, 0x80, 0x83, 0xFF):
        f = rig.host.request(cmd, b'')
        check(f['payload'] == bytes([S_UNKNOWN]), 'cmd 0x%02X: %r' % (cmd, f['payload']))
    return True


@case
def k03_start_without_slot_handover():
    """Also (revision 17): a result word with a wrong complement (0x55520100) is no result and is
    cleared by own_start (17.3); a progress word without the tag 0x5350 is reported as 0 (17.2)."""
    rig = Ctl(ram={HANDOVER_WORD: 0x12345678, REQ_WORD: REQ_MAGIC, RESULT_WORD: 0x55520100,
                   BOOT_PROG: 0x12340005}).up()
    check(rig.rd(RESULT_WORD) == 0, 'foreign result word kept: 0x%08X' % rig.rd(RESULT_WORD))
    d = rig.ask_ok('INFO', size=INFO_SIZE)
    check(d[33] == 0xFF and struct.unpack_from('<I', d, 34)[0] == 0, 'unknown slot: %d' % d[33])
    check(struct.unpack_from('<I', d, 42)[0] == 0, 'result without a result word')
    check(struct.unpack_from('<I', d, 46)[0] == 0, 'foreign progress word reported 0x%08X'
          % struct.unpack_from('<I', d, 46)[0])
    check(rig.rd(REQ_WORD) == 0 and rig.rd(HANDOVER_WORD) == 0, 'no-init words not cleared')
    return True


@case
def k04_battery_factory_state():
    rig = Ctl().up()
    d = rig.ask_ok('BATTERY', size=6)
    sup = struct.unpack_from('<I', d, 0)[0]
    check(sup == rig.rd(V_SUPPLY), 'supply bits 0x%08X, RAM 0x%08X' % (sup, rig.rd(V_SUPPLY)))
    # cmd.s h_battery: count thresholds from the lowest while the bits compare above (signed, ble)
    signed = sup - (1 << 32) if sup & 0x80000000 else sup
    level = 0
    for t in (0x4059999A, 0x40666666, 0x40733333, 0x40800000):
        if signed <= t:
            break
        level += 1
    check(d[4] == level and d[5] == (1 if rig.rd(V_LOWV) else 0), 'level %d popup %d' % (d[4], d[5]))
    check(rig.ask_ok('FACTORY_MODE', size=1)[0] == rig.rd(V_FACTORY) & 0xFF, 'factory mode')
    s = rig.ask_ok('STATE', size=STATE_SIZE)
    check(s[0] == rig.rd(V_SCREEN) & 0xFF == 1, 'screen %d' % s[0])
    flags = struct.unpack_from('<H', s, 1)[0]
    check(flags & 0x004 and not flags & (0x010 | 0x100 | 0x200 | 0x400), 'flags 0x%X' % flags)
    check(s[3] == rig.rd(V_FUNC) & 0xFF and s[4] == rig.rd8(V_MAIN_ROW) and s[5] == rig.rd(V_SECONDARY) & 0xFF,
          'func / rows %r' % list(s[3:6]))
    check(struct.unpack_from('<III', s, 6) == (rig.rd(V_FREQ), rig.rd(V_LEVEL), rig.rd(V_BIAS)), 'freq / level / bias')
    check(list(s[18:21]) == [rig.rd(V_RANGE) & 0xFF, rig.rd(V_SPEED) & 0xFF, rig.rd(V_CIRCUIT) & 0xFF], 'range / speed')
    check(s[22] == rig.rd(V_DIALOG) & 0xFF and s[23] == 0xFF and s[24] == rig.rd(V_LANGUAGE) & 0xFF, 'dialog / menu')
    check(s[27] == rig.rd(SAVE_STATUS) & 0xFF, 'save status')
    t = struct.unpack_from('<I', s, 28)[0]
    check(t <= rig.rd(V_TICK), 'time %d after tick %d' % (t, rig.rd(V_TICK)))
    return True


@case
def k05_measure_compare_records():
    rig = Ctl().up()
    d = rig.ask_ok('MEASURE', size=MEASURE_SIZE)
    check(d[8] == rig.rd8(V_MAIN_ROW), 'main row %d' % d[8])
    for off in (9, 25):
        unit, dec, valid = d[off + 4], d[off + 5], d[off + 6]
        text = d[off + 7:off + 15]
        check(unit <= 12 and valid <= 3 and dec <= 9, 'value block at %d: unit %d dec %d valid %d' % (off, unit, dec, valid))
        check(all(32 <= c < 127 for c in text.rstrip(b'\x00')), 'text %r' % text)
    # layout (cmd.s header): 0 number, 4 time, 8 main row, 9 value block (15), 24 secondary, 25 value
    # block, 40 series / parallel, 41 |Z|, 45 theta, 49 frequency, 53 level, 57 bias, 61 range,
    # 62 speed, 63 circuit mode
    check(d[24] == rig.rd(V_SECONDARY) & 0xFF and d[40] == rig.rd8(0x200011EC), 'secondary %d / serpar %d' % (d[24], d[40]))
    check(struct.unpack_from('<III', d, 49) == (rig.rd(V_FREQ), rig.rd(V_LEVEL), rig.rd(V_BIAS)), 'frequency / level / bias')
    check(list(d[61:64]) == [rig.rd(V_RANGE) & 0xFF, rig.rd(V_SPEED) & 0xFF, rig.rd(V_CIRCUIT) & 0xFF], 'range / speed')
    c = rig.ask_ok('COMPARE', size=COMPARE_SIZE)
    check(c[0] == rig.rd(0x20001178) & 0xFF and struct.unpack_from('<II', c, 1) == (rig.rd(0x20001184), rig.rd(0x20001188)),
          'compare quantity / nominal / tolerance')
    check(struct.unpack_from('<II', c, 14) == (rig.rd(0x200050F0), rig.rd(0x200050F4)), 'counters')
    return True


@case
def k06_tables():
    rig = Ctl().up()
    check(rig.ask_ok('LCR_TABLES', size=1)[0] == 8, 'LCR list count')
    for i in range(8):
        d = rig.ask_ok('LCR_TABLES', bytes([i]))
        check(d[0] == i and d[1] >= 1 and d[2] <= 2, 'LCR list %d head %r' % (i, d[:3]))
    check(rig.ask('LCR_TABLES', b'\x08')[0] == S_BAD_ARG, 'LCR list 8 accepted')
    check(rig.ask_ok('SET_TABLES', size=1)[0] == 6, 'settings count')
    for i in range(6):
        d = rig.ask_ok('SET_TABLES', bytes([i]))
        check(d[0] == i and d[1] in (0, 1), 'setting %d head %r' % (i, d[:2]))
    check(rig.ask('SET_TABLES', b'\x06')[0] == S_BAD_ARG, 'setting 6 accepted')
    return True


@case
def k07_settings_set_ram_only_and_save():
    rig = Ctl().up()
    d = rig.ask_ok('SET_TABLES', b'\x00')                # brightness (cmd.s h_set_set ids 0..2)
    cur, lo, hi, step = struct.unpack_from('<IIII', d, 2)
    want = lo + step if cur != lo + step else lo
    check(lo <= want <= hi, 'brightness range %d..%d step %d' % (lo, hi, step))
    n_ops = len(rig.flash_ops())
    st, s = rig.ask('SET_SET', struct.pack('<BH', 0, want), timeout=25.0)
    check(st == S_OK and rig.rd(V_BRIGHT) == want, 'SET_SET status %d brightness %d' % (st, rig.rd(V_BRIGHT)))
    check(len(rig.flash_ops()) == n_ops, 'SETTINGS_SET wrote flash')
    check(rig.ask('SET_SET', struct.pack('<BH', 0, hi + step))[0] == S_BAD_ARG, 'above max accepted')
    check(rig.ask('SET_SET', struct.pack('<BH', 9, 0))[0] == S_BAD_ARG, 'id 9 accepted')
    check(rig.ask('SET_SAVE', b'\x00\x00')[0] == S_BAD_ARG, 'save without confirmation')
    d = rig.ask_ok('SET_SAVE', OK2, timeout=5.0, size=8)
    check(struct.unpack_from('<II', d) == (0, rig.rd(SAVE_FLAGS)), 'save answer %r' % (struct.unpack_from('<II', d),))
    blk = rig.rd(V_BLOCK, BLK)
    for base in (SET_A, SET_B):
        check(rig.m.get(base, BLK) == blk, 'copy 0x%08X does not hold the RAM block' % base)
    return True


@case
def k08_cal_read_mem_read():
    rig = Ctl().up()
    for copy_, base in ((0, SET_A), (1, SET_B)):
        for off, ln in ((0, 256), (0xF00, 256), (0xFFC, 4), (0x123, 7)):
            d = rig.ask_ok('CAL_READ', struct.pack('<BHH', copy_, off, ln), size=ln)
            check(d == rig.m.get(base + off, ln), 'CAL_READ %d 0x%X+%d' % (copy_, off, ln))
    for p in (struct.pack('<BHH', 0, 0, 0), struct.pack('<BHH', 0, 0, 257), struct.pack('<BHH', 0, 0xF01, 256),
              struct.pack('<BHH', 2, 0, 4), b'\x00\x00\x00\x04'):
        check(rig.ask('CAL_READ', p)[0] == S_BAD_ARG, 'CAL_READ %s accepted' % p.hex())
    img = rig.m.get(APP, 256)
    good = [(APP, 256, img), (0x0807FFFC, 4, rig.m.get(0x0807FFFC, 4)), (SYSMEM, 16, rig.m.sysmem[:16]),
            (0x1FFF3FF0, 16, rig.m.sysmem[0x3FF0:0x4000]), (0x1FFFF800, 18, rig.m.sysmem[0xF800:0xF812]),
            (0x1FFFF7F0, 12, UID), (0x2001FFF0, 16, rig.rd(0x2001FFF0, 16))]
    for addr, ln, exp in good:
        d = rig.ask_ok('MEM_READ', struct.pack('<IH', addr, ln), size=ln)
        if addr != 0x2001FFF0:
            check(d == exp, 'MEM_READ 0x%08X: %s' % (addr, d[:8].hex()))
    for addr, ln in ((0x0807FFFC, 8), (0x1FFF3FF8, 16), (0x1FFF4000, 4), (0x1FFFF80C, 8), (0x2001FFF8, 16),
                     (0x20020000, 4), (0x40022000, 4), (0x60000000, 4), (0xFFFFFFF0, 32), (APP, 0), (APP, 257)):
        check(rig.ask('MEM_READ', struct.pack('<IH', addr, ln))[0] == S_BAD_ARG, 'MEM_READ 0x%08X+%d accepted' % (addr, ln))
    check(rig.ask('MEM_READ', b'\x00\x60\x00\x08\x10')[0] == S_BAD_ARG, 'short MEM_READ accepted')
    return True


WDG_ON = 0x20002228              # bootloader/src/slot.inc: 1 when the slot feeds a running IWDG
REQ_RESTART = 0x52535452         # "RSTR" (own.inc)


def watch_restart(rig):
    """Hooks for ctl.s soft_restart (a branch to the starter's reset entry, not a reset, in the same
    run): each entry of the starter (emulated time, request word, log length), the passes of
    ctl_loop that follow the next own_start (the restarted application's main loop) and the passes
    of slot A's update-mode loop (fn_08001150)."""
    m = rig.m
    hits = dict(starter=[], own_start=0, loop=0, update=0)

    def starter(uc, a, size, user):
        hits['starter'].append(dict(t=m.now(), req=struct.unpack('<I', bytes(uc.mem_read(REQ_WORD, 4)))[0],
                                    log=len(m.st['log'])))

    def own(uc, a, size, user):
        hits['own_start'] += 1

    def loop(uc, a, size, user):
        if hits['own_start']:
            hits['loop'] += 1

    def update(uc, a, size, user):
        hits['update'] += 1
    for sym, fn in ((m.starter_sym['reset'], starter), (rig.s['own_start'], own), (rig.s['ctl_loop'], loop),
                    (m.sym[1]['fn_08001150'], update)):
        m.uc.hook_add(UC_HOOK_CODE, fn, begin=sym & ~1, end=sym & ~1)
    hits['log0'] = len(m.st['log'])
    return hits


def check_restart(rig, hits, req, what, timeout=3.0, done='loop'):
    """The soft restart reached the starter once with the request word req, PA8 was never driven low
    after the action and the starter drove it high again, no system reset, no IWDG reset, and then
    hits[done] counts: the application's main loop runs again ('loop') or the slot's update-mode
    loop runs ('update'). The IWDG stretch over the restart (from the feed of
    soft_restart to the next load) stays below PERIOD_MIN; NOTES gets its instruction count, the
    modelled time (144 MHz, 5 cycles per instruction: the PLL stays the system clock through the
    starter) and, as a bound, the time of the same count at 8 MHz (the HSI, on which the slot runs
    from its fn_08002598 to the PLL switch of fn_080020c4)."""
    m = rig.m
    end = m.run_for(seconds=timeout, until=lambda mm: hits[done] > 0)
    log = m.st['log']
    check(end is None and hits[done], '%s: %s loop not reached: end %r, violations %r'
          % (what, done, end, m.st['viol']))
    check(('reset',) not in log, '%s: system reset' % what)
    check(len(hits['starter']) == 1, '%s: starter entered %d times' % (what, len(hits['starter'])))
    h = hits['starter'][0]
    check(h['req'] == req, '%s: request word 0x%08X at the starter entry' % (what, h['req']))
    check(('pa8', 0) not in log[hits['log0']:], '%s: PA8 driven low' % what)
    check(('pa8', 1) in log[h['log']:] and m.st['pa8'] == 1, '%s: PA8 not driven high by the starter' % what)
    check(not [e for e in m.iwdg_log if e['kind'] == 'reset'], '%s: IWDG reset' % what)
    loads = [e for e in m.iwdg_log if e['kind'] in ('start', 'feed')]
    before = [e for e in loads if e['t'] <= h['t']][-1]
    after = [e for e in loads if e['t'] > h['t']][0]
    gap = after['t'] - before['t']
    check(gap < PERIOD_MIN, '%s: %.4f s without a feed over the restart' % (what, gap))
    n = after['insn'] - before['insn']
    NOTES.append('%s: feed 0x%08X -> 0x%08X over the restart: %d instructions, %.4f s modelled, %.4f s at '
                 '8 MHz x 5 cycles' % (what, before['pc'] or 0, after['pc'] or 0, n, gap, n * 5 / 8e6))
    return h


def stop_at_starter(rig, what):
    """After BOOT_INSTALL (slot B mmio in mode 'app', so the trial runs in another meter): the run stops
    at the starter's reset entry reached by soft_restart: no system reset, PA8 never driven low, the
    request word RSTR in RAM (rig.m.ram holds the SRAM at the stop)."""
    m = rig.m
    log0 = len(m.st['log'])
    m.watch(m.starter_sym['reset'], 'starter reset', stop=True)
    end = m.run_for(1.0)
    check(end == 'at starter reset', '%s: end %r, expected the soft restart' % (what, end))
    check(('reset',) not in m.st['log'] and ('pa8', 0) not in m.st['log'][log0:], '%s: reset or PA8 low' % what)
    req = struct.unpack_from('<I', m.ram, REQ_WORD - 0x20000000)[0]
    check(req == REQ_RESTART, '%s: request word 0x%08X' % (what, req))


@case
def k09_reset_and_power_off():
    rig = Ctl().up()
    hits = watch_restart(rig)                            # before the request: the restart follows it
    check(rig.ask('RESET')[0] == S_OK, 'RESET status')
    check_restart(rig, hits, REQ_RESTART, 'RESET')
    rig = Ctl().up()
    check(rig.ask('POWER_OFF', b'\x00\x00')[0] == S_BAD_ARG and rig.ask('POWER_OFF', OK2)[0] == S_BAD_ARG,
          'POWER_OFF with a wrong confirmation')
    saves = rig.rd(SAVE_COUNT)
    ops0 = len(rig.flash_ops())
    same = rig.rd(0x2000057C, 0xC14) == rig.m.get(0x0807F000, 0xC14) == rig.m.get(0x08066000, 0xC14)
    check(rig.ask('POWER_OFF', OFF2)[0] == S_OK, 'POWER_OFF status')
    # the path from 0x08009452: own_save writes both copies (2 page erases and about 0xC14 / 4 words
    # each: 4 x T_ERASE 100 ms + 1550 x T_PROG 225 us of meter_model = 0.75 s), fn_08008120(200),
    # then 0x0800B274 sets PA8 low; with the block unchanged in both copies the save writes nothing
    # and reports SV_SAME 9 (S2.10: the save is skipped when A and B already hold the staged block)
    rig.run(1.5)
    check(rig.m.st['pa8'] == 0, 'PA8 not low after POWER_OFF')
    want = 9 if same else 0
    check(rig.rd(SAVE_COUNT) == saves + 1 and rig.rd(SAVE_STATUS) == want,
          'the power-off save did not run as expected: status %d, expected %d' % (rig.rd(SAVE_STATUS), want))
    check((len(rig.flash_ops()) == ops0) == same, 'power-off save: flash written %d operations, block unchanged %r'
          % (len(rig.flash_ops()) - ops0, same))
    rig.run(1.2)                                         # OFF_WAIT_MS 1000: powered-off mode
    check(rig.rd(OWN_CTL + CT_FLAGS) & CF_OFF, 'powered-off mode not entered')
    ev = [f for f in rig.drain(0.1) if f['type'] == FR_EVENT and f['cmd'] == E_POWERED_OFF]
    check(ev, 'no POWERED_OFF event')
    s = rig.ask_ok('STATE', size=STATE_SIZE)
    check(struct.unpack_from('<H', s, 1)[0] & 0x400, 'STATE powered-off flag')
    check(rig.ask('POWER_OFF', OFF2)[0] == S_NOT_NOW, 'POWER_OFF in powered-off mode')
    hits = watch_restart(rig)
    rig.keys.down |= KEY_POWER                           # the power key restarts the meter (key_step)
    end = rig.m.run_for(seconds=1.5, until=lambda mm: hits['starter'])
    check(end is None and hits['starter'], 'power key in powered-off mode: no restart, end %r' % end)
    rig.keys.down &= ~KEY_POWER                          # released once the starter runs
    check_restart(rig, hits, REQ_RESTART, 'power key in powered-off mode')
    return True


# ---------------------------------------------------------------- frames, ring, streams

@case
def k10_bad_crc_overlong_and_split_frames():
    rig = Ctl().up()
    h = rig.host
    good = make_frame(0x40, 1, C['PING'], b'good')
    bad = bytearray(make_frame(0x41, 1, C['PING'], b'bad'))
    bad[-1] ^= 0xFF
    overlong = bytes([0xA5]) + struct.pack('<H', 516) + bytes([0x42, 1, 1])
    short = bytes([0xA5]) + struct.pack('<H', 2)
    answer = make_frame(0x43, 2, C['PING'], b'answer')             # type 2 from the host: dropped
    h.bulk_out(bytes(bad) + overlong + short + answer + b'\x00\x11' + good)
    got = []
    t_end = rig.m.now() + 1.0
    while rig.m.now() < t_end and not got:
        got = [f for f in h.recv(0.05) if f['type'] == FR_ANSWER]
    check(len(got) == 1 and got[0]['seq'] == 0x40 and got[0]['payload'] == b'\x00good', 'answers %r' % got)
    check(not [f for f in rig.drain(0.2) if f['type'] == FR_ANSWER], 'an answer to a dropped frame')
    # one frame split over many OUT packets with pauses: still one request
    f = make_frame(0x44, 1, C['PING'], bytes(range(200)))
    for i in range(0, len(f), 7):
        h.bulk_out(f[i:i + 7])
        rig.run(0.003)
    got = [x for x in rig.drain(0.3) if x['type'] == FR_ANSWER]
    check(len(got) == 1 and got[0]['payload'] == b'\x00' + bytes(range(200)), 'split frame %r' % got[:1])
    return True


@case
def k11_rx_ring_full_nak_nothing_lost():
    """24 PING frames of 60 payload bytes (68 bytes each, 1632 bytes) in one burst: more than the
    1 KiB RX ring, so EP2 must NAK (usb.s ep2_arm: VALID only with 64 bytes free) and every request
    must be answered once, in order, with its own bytes."""
    rig = Ctl().up()
    h, dev = rig.host, rig.dev
    naks = []
    orig = dev.host_out

    def counting(m, addr, epnum, data, pid):
        r = orig(m, addr, epnum, data, pid)
        if epnum == 2 and r == 'NAK':
            naks.append(m.now())
        return r
    dev.host_out = counting
    frames = [make_frame(i, 1, C['PING'], bytes([i]) * 60) for i in range(24)]
    h.bulk_out(b''.join(frames), timeout=5.0)
    got = []
    t_end = rig.m.now() + 5.0
    while rig.m.now() < t_end and len(got) < 24:
        got += [f for f in h.recv(0.05) if f['type'] == FR_ANSWER]
    dev.host_out = orig
    check(naks, 'EP2 never NAKed: the burst fitted the ring')
    check([f['seq'] for f in got] == list(range(24)), 'answers %r' % [f['seq'] for f in got])
    check(all(f['payload'] == b'\x00' + bytes([f['seq']]) * 60 for f in got), 'answer bytes differ')
    NOTES.append('k11: EP2 NAKed %d times' % len(naks))
    return True


@case
def k12_state_and_measure_stream_framing():
    rig = Ctl().up()
    check(rig.ask('STREAM', b'\x05')[0] == S_BAD_ARG, 'STREAM with one byte')
    rig.ask_ok('STREAM', struct.pack('<H', 50))
    frames = rig.drain(1.0)
    rig.ask_ok('STREAM', struct.pack('<H', 0))
    st = [f for f in frames if f['type'] == FR_STREAM and f['cmd'] == C['STATE']]
    check(18 <= len(st) <= 21, '%d STATE stream frames in 1 s at 50 ms' % len(st))
    check(all(len(f['payload']) == STATE_SIZE for f in st), 'STATE stream payload sizes')
    times = [struct.unpack_from('<I', f['payload'], 28)[0] for f in st]
    # stream_step keeps the period grid (ctl.s: the next point is the last one + the period, so a
    # late record is followed by a sooner one and the average rate is kept; PROTOCOL.md section 11):
    # every record lies on its grid point, at most 20 ms (two GUI ticks) after it
    base = min(t - 50 * i for i, t in enumerate(times))
    late = [t - 50 * i - base for i, t in enumerate(times)]
    check(all(0 <= d <= 20 for d in late), 'STATE stream records behind the 50 ms grid by %r ms (times %r)'
          % (late, times))
    running = [f for f in frames if f['type'] in (FR_STREAM, FR_EVENT)]
    seqs = [f['seq'] for f in running]
    check(all((b - a) & 0xFF == 1 for a, b in zip(seqs, seqs[1:])), 'stream / event seq not consecutive %r' % seqs)
    rest = [f for f in rig.drain(0.3) if f['type'] == FR_STREAM and f['cmd'] == C['STATE']]
    check(len(rest) <= 1, 'STATE stream still running after STREAM 0: %d' % len(rest))
    rig.ask_ok('MEASURE_STREAM', struct.pack('<H', 100))
    frames = rig.drain(1.0)
    rig.ask_ok('MEASURE_STREAM', struct.pack('<H', 0xFFFF))
    ms = [f for f in frames if f['type'] == FR_STREAM and f['cmd'] == C['MEASURE']]
    check(8 <= len(ms) <= 11 and all(len(f['payload']) == MEASURE_SIZE for f in ms),
          '%d MEASURE stream frames in 1 s at 100 ms' % len(ms))
    rest = [f for f in rig.drain(0.3) if f['type'] == FR_STREAM and f['cmd'] == C['MEASURE']]
    check(len(rest) <= 1, 'MEASURE stream still running after 0xFFFF')
    rig.ask_ok('MEASURE_STREAM', struct.pack('<H', 0))              # every new result
    frames = rig.drain(1.0)
    rig.ask_ok('MEASURE_STREAM', struct.pack('<H', 0xFFFF))
    ms = [f for f in frames if f['type'] == FR_STREAM and f['cmd'] == C['MEASURE']]
    nums = [struct.unpack_from('<I', f['payload'], 0)[0] for f in ms]
    check(nums == sorted(set(nums)), 'result numbers of mode 0 not increasing %r' % nums)
    NOTES.append('k12: MEASURE_STREAM mode 0 gave %d frames in 1 s (results of the measurement model)' % len(ms))
    return True


@case
def k13_events_key_screen_setting():
    rig = Ctl().up()
    rig.drain(0.1)
    rig.press(0x0400, 1200)                              # long key 0x400: screen 1 -> 2 (V1.1 key behaviour)
    ev = [f for f in rig.drain(0.3) if f['type'] == FR_EVENT]
    keys = [f for f in ev if f['cmd'] == E_KEY]
    scr = [f for f in ev if f['cmd'] == E_SCREEN]
    check(keys and all(struct.unpack_from('<H', f['payload'])[0] == 0x0400 and f['payload'][3] == 0 for f in keys),
          'KEY events %r' % [f['payload'].hex() for f in keys])
    check(scr and scr[-1]['payload'][:2] == bytes([2, 1]), 'SCREEN_CHANGED %r' % [f['payload'].hex() for f in scr])
    setting = [f for f in ev if f['cmd'] == E_SETTING and struct.unpack_from('<H', f['payload'])[0] == V_SCREEN - V_BLOCK]
    check(setting and struct.unpack_from('<I', setting[-1]['payload'], 2)[0] == 2, 'SETTING_CHANGED of the screen word')
    rig.host.set_control_line_state(dtr=False, rts=False)
    rig.drain(0.05)
    rig.press(0x0400, 1200)
    check(not [f for f in rig.drain(0.3) if f['type'] == FR_EVENT], 'events without DTR')
    return True


# ---------------------------------------------------------------- key injection

@case
def k14_key_command_and_refusals():
    rig = Ctl().up()
    for p in (b'', b'\x0e', b'\xff\x00\x00'):
        check(rig.ask('KEY', p)[0] == S_BAD_ARG, 'KEY %s accepted' % p.hex())
    st, s = rig.ask('KEY', struct.pack('<BH', 10, 1200), timeout=25.0)      # long 0x400: screen 2
    check(st == S_OK and s[0] == 2 and rig.rd(V_SCREEN) == 2, 'KEY long 0x400: status %d screen %d' % (st, rig.rd(V_SCREEN)))
    st, s = rig.ask('KEY', struct.pack('<BH', 0, 1200), timeout=25.0)       # hold of the power key
    check(st == S_SAFETY and rig.m.st['pa8'] != 0, 'power hold: status %d' % st)
    # a block with the first-start flag 0 (V1.1 would show its chooser, screen 0): our build starts
    # on the measure screen (own_load sets the flag), and an injected key is accepted there
    rig = Ctl(a=copy_image(block_with(lang_set=0), 2), b=copy_image(block_with(lang_set=0), 1)).up()
    check(rig.rd(V_SCREEN) == 1 and rig.rd(V_LANG_SET) == 1, 'flag-0 block: screen %d flag %d'
          % (rig.rd(V_SCREEN), rig.rd(V_LANG_SET)))
    st, s = rig.ask('KEY', bytes([1]), timeout=25.0)
    check(st == S_OK, 'flag-0 block: key bit 1 status %d' % st)
    return True


def thumb(*hws):
    return b''.join(struct.pack('<H', h) for h in hws)


RAM_CODE, RAM_VT = 0x2001F000, 0x2001F800
# SysTick handler in RAM calling the vendor key scan: push {lr}; ldr r0, [pc, #4] (literal at +8);
# blx r0; pop {pc}; .word fn_080094a0 | 1   (0xB500, 0x4801, 0x4780, 0xBD00)
SCAN_STUB = (0xB500, 0x4801, 0x4780, 0xBD00)


@case
def k15_key_injection_race_systick_between_every_instruction():
    """post_try(code 0xFF, r1 = 0: the IS_RELEASE path, which posts while a physical key may be down)
    with the vendor key scan fn_080094a0 entered as SysTick before each of its instructions in turn.
    Producer states: (release) a physical key 0x0004 was down for 5 scans and is now up, so the scan
    posts code 1 with mask 4; (hold) the key is still down with the counter at 150, so the scan posts
    0xFE with mask 4. The slot pair (0x20001192, 0x20001194) must always be one producer's whole
    pair, never a mix; CT_I_POSTED records a post only when the slot was empty at the check."""
    m = OwnMeter(slots=(), records=(), starter=False, flash_mode='app')
    m.load_own()
    s = m.app_sym
    m.set_timing(lsi_hz=LSI)
    keys = m.attach(KeyPad())
    m.make()
    uc = m.uc
    uc.mem_write(RAM_CODE, thumb(*SCAN_STUB) + struct.pack('<I', s['fn_080094a0'] | 1))
    vt = bytearray(0x40)
    struct.pack_into('<I', vt, 4 * 15, RAM_CODE | 1)
    uc.mem_write(RAM_VT, bytes(vt))
    m.scs[0xE000ED08] = RAM_VT
    INJ, PHYS = 0x0400, 0x0004

    def setup(kind):
        keys.down = PHYS if kind == 'hold' else 0
        uc.mem_write(V_KEYS_DOWN, struct.pack('<H', PHYS))
        uc.mem_write(V_KEY_TICKS, struct.pack('<H', 150 if kind == 'hold' else 5))
        uc.mem_write(V_KEY_CODE, b'\x00\x00\x00\x00')
        uc.mem_write(OWN_CTL + CT_I_MASK, struct.pack('<I', INJ))
        uc.mem_write(OWN_CTL + CT_I_POSTED, bytes(4))
        m.tm['irq_count'].clear()
        m.tm['pend'].clear()
        uc.reg_write(UC_ARM_REG_SP, SP_TOP)
        uc.reg_write(UC_ARM_REG_LR, RET | 1)
        uc.reg_write(UC_ARM_REG_R0, 0xFF)
        uc.reg_write(UC_ARM_REG_R1, 0)
        m.st['end'] = None

    def finish():
        m.st['end'] = None
        m._run(uc.reg_read(UC_ARM_REG_PC), budget=200000)
        check(m.st['end'] == 'return', 'end %r' % m.st['end'])
        if 15 in m.tm['pend']:                       # still pending at the return: deliver it now
            m.st['end'] = None
            m._irq()
            m._run(uc.reg_read(UC_ARM_REG_PC), budget=200000)
            check(m.st['end'] == 'return', 'late interrupt: end %r' % m.st['end'])

    def pair():
        code, mask = struct.unpack('<HH', bytes(uc.mem_read(V_KEY_CODE, 4)))
        return code, mask
    out = {}
    for kind, phys_code in (('release', 1), ('hold', 0xFE)):
        setup(kind)
        i0 = m.icount()
        m._run(s['post_try'], budget=200000)
        check(m.st['end'] == 'return', 'clean call: end %r' % m.st['end'])
        n = m.icount() - i0
        check(pair() == (0xFF, INJ), '%s: clean call posted %r' % (kind, pair()))
        for k in range(n):
            setup(kind)
            m._run(s['post_try'], budget=k)          # k instructions of post_try
            m.st['end'] = None
            m.tm['pend'].add(15)                     # SysTick pending before instruction k
            m._irq()
            finish()
            got, posted = pair(), struct.unpack('<I', bytes(uc.mem_read(OWN_CTL + CT_I_POSTED, 4)))[0]
            what = '%s, SysTick before instruction %d of %d' % (kind, k, n)
            check(m.tm['irq_count'].get(15, 0) == 1, '%s: SysTick entered %d times' % (what, m.tm['irq_count'].get(15, 0)))
            check(got in ((phys_code, PHYS), (0xFF, INJ)), '%s: slot pair %r mixes the producers' % (what, got))
            check(got == (phys_code, PHYS), '%s: the scan after the post left %r' % (what, got))
            check(posted in (0, 0xFF), '%s: CT_I_POSTED 0x%X' % (what, posted))
        out[kind] = n
    NOTES.append('k15: post_try %r instructions, SysTick before each' % out)
    return True


# ---------------------------------------------------------------- screenshot

def shot_frames(frames, band=None):
    px = [f for f in frames if f['type'] == FR_STREAM and f['cmd'] == C['SCREENSHOT']]
    out = []
    for f in px:
        p = f['payload']
        b, off, x1, y1, x2, y2 = struct.unpack_from('<BHHHHH', p, 0)
        if band is not None and b != band:
            continue
        out.append(dict(band=b, off=off, rect=(x1, y1, x2, y2), data=p[11:]))
    return out


def check_band(rig, frames, band):
    y0 = 10 * band
    fr = shot_frames(frames, band)
    ends = [f for f in fr if f['off'] == 0xFFFF]
    check(len(ends) == 1 and ends[0]['rect'] == (0, y0, 319, y0 + 9) and len(ends[0]['data']) == 1,
          'band %d end frames %r' % (band, [(f['rect'], f['data']) for f in ends]))
    res = ends[0]['data'][0]
    covered = {y: set() for y in range(y0, y0 + 10)}     # x positions received per row
    for f in fr:
        if f['off'] == 0xFFFF:
            continue
        x1, y1, x2, y2 = f['rect']
        w = x2 - x1 + 1
        check(y0 <= y1 <= y2 <= y0 + 9 and 0 <= x1 <= x2 <= 319, 'band %d frame rect %r' % (band, f['rect']))
        n = len(f['data']) // 2
        check(len(f['data']) % 2 == 0 and 1 <= n <= 240, 'band %d frame of %d bytes' % (band, len(f['data'])))
        pix = struct.unpack('<%dH' % n, f['data'])
        match = False
        for fx1, fy1, fx2, fy2, fp in rig.m.panel.flushes:
            if fx1 != x1 or fx2 != x2 or fy1 > y1 or fy2 < y2:
                continue
            ok = True
            for j in range(n):
                k = f['off'] + j
                x, y = x1 + k % w, y1 + k // w
                idx = (y - fy1) * w + (x - fx1)
                if idx >= len(fp) or fp[idx] != pix[j]:
                    ok = False
                    break
            if ok:
                match = True
                break
        check(match, 'band %d frame %r offset %d: no panel flush with these pixels' % (band, f['rect'], f['off']))
        for j in range(n):
            k = f['off'] + j
            covered[y1 + k // w].add(x1 + k % w)
    if res == 0:
        short = [y for y, xs in covered.items() if len(xs) != 320]
        check(not short, 'band %d reported done, rows not complete: %r' % (band, short))
    return res


@case
def k16_screenshot_one_band_and_all():
    rig = Ctl(panel=True).up()
    rig.host.set_control_line_state(dtr=False, rts=False)
    check(rig.ask('SCREENSHOT', b'\x05')[0] == S_NOT_NOW, 'screenshot without DTR')
    rig.host.set_control_line_state(dtr=True, rts=True)
    check(rig.ask('SCREENSHOT', b'\x18')[0] == S_BAD_ARG, 'band 24 accepted')
    rig.m.panel.flushes.clear()
    d = rig.ask_ok('SCREENSHOT', b'\x05', size=6)
    check(struct.unpack('<HHBB', d) == (320, 240, 0, 1), 'answer %r' % (struct.unpack('<HHBB', d),))
    frames = rig.drain(1.5)
    check(check_band(rig, frames, 5) == 0, 'band 5 not done')
    check(rig.rd8(OWN_SCREEN) == 0 and rig.rd8(OWN_USB + UO_RESERVE) == 0, 'capture not ended')
    rig.m.panel.flushes.clear()
    rig.ask_ok('STREAM', struct.pack('<H', 20))
    d = rig.ask_ok('SCREENSHOT', b'', size=6)
    check(d[5] == 24, 'bands %d' % d[5])
    frames = rig.drain(12.0)
    rig.ask_ok('STREAM', struct.pack('<H', 0))
    results = [check_band(rig, frames, b) for b in range(24)]
    check(all(r == 0 for r in results), 'band results %r' % results)
    # no STATE stream frame between the first and the last screenshot frame (streams pause)
    idx = [k for k, f in enumerate(frames) if f['type'] == FR_STREAM and f['cmd'] == C['SCREENSHOT']]
    between = [f for f in frames[idx[0]:idx[-1]] if f['type'] == FR_STREAM and f['cmd'] == C['STATE']]
    check(not between, '%d STATE stream frames during the capture' % len(between))
    NOTES.append('k16: 24 bands in %d frames' % len(idx))
    return True


@case
def k17_screenshot_host_stops_reading():
    """The host stops reading after the answer: the TX ring cannot drain, the capture stops after
    SCR_T_ROOM = 2000 GUI ticks (screen.s) without an end frame; the main loop keeps running and the
    watchdog is never starved (LSI 60 kHz); afterwards the host reads again and is answered."""
    rig = Ctl(panel=True).up()
    m = rig.m
    passes = []
    m.watch(rig.s['ctl_loop'], 'ctl_loop')
    rig.ask_ok('SCREENSHOT', b'', size=6)
    t0 = m.now()
    n0 = m.events().count('ctl_loop')
    rig.run(3.5)
    n1 = m.events().count('ctl_loop')
    check(n1 - n0 > 100, 'main loop passes during 3.5 s: %d' % (n1 - n0))
    check(rig.rd8(OWN_SCREEN) == 0 and rig.rd8(OWN_USB + UO_RESERVE) == 0, 'capture still running after 3.5 s')
    s = stretch_in(m, t0, m.now())
    check(s < PERIOD_MIN, 'longest watchdog stretch %.3f s while the host did not read' % s)
    rig.drain(1.0)
    check(rig.ask_ok('PING', b'again') == b'again', 'no answer after the host read again')
    passes.append(n1 - n0)
    NOTES.append('k17: %d passes in 3.5 s without reading, longest stretch %.1f ms' % (n1 - n0, s * 1e3))
    return True


# ---------------------------------------------------------------- USB interrupt lines, clock

@case
def k18_exti18_cleared_by_irq42():
    rig = Ctl().up()
    m, dev = rig.m, rig.dev
    check(16 + 42 in m.tm['en'] and 16 + 20 in m.tm['en'], 'IRQ 20 / 42 not enabled: %r' % sorted(m.tm['en']))
    dev.exti['imask'] |= 1 << 18
    dev.exti['pend'] |= 1 << 18
    m.irq_check()
    rig.run(0.02)
    check(not dev.exti['pend'] & (1 << 18), 'EXTI pending bit 18 not cleared')
    check([x for x in dev.log if x[0] == 'exti18-cleared'], 'no clear logged')
    check(m.tm['irq_count'].get(16 + 42, 0) >= 1, 'IRQ 42 not entered')
    check(rig.ask_ok('PING', b'x') == b'x', 'channel after IRQ 42')
    return True


class HseFails:
    """RCC_CTRL 0x40021000: HSE never ready (bit 17 reads 0); PLL ready (bit 25) follows PLL on
    (bit 24) as in meter_model; writes kept."""
    ranges = [(0x40021000, 0x40021004)]

    def __init__(self):
        self.v = 0

    def read(self, m, a, size):
        v = (self.v & ~(1 << 17)) | ((self.v >> 24) & 1) << 25
        return v >> 8 * (a & 3)

    def write(self, m, a, size, value):
        sh = 8 * (a & 3)
        mask = ((1 << 8 * size) - 1) << sh
        self.v = (self.v & ~mask) | ((value << sh) & mask)


@case
def k19_hse_failure_no_usb_start():
    """fn_0800ba4c: HSE not ready after 0x8000 polls -> the branch 0x0800BAF8, no PLL, the core
    stays on the HSI (8 MHz). Our build latches the power at once (own_pa8_level: PA8 high while
    SCLKSTS is not the PLL; fix F4, a clean power-off instead of the vendor's endless IWDG restarts) and ends in xtal_fault (k33), so ctl_loop,
    which starts USB, is never reached: no USBEN, no pull-up over 3 s from the reset vector, PA8
    high. Then usb_start is called directly in that HSI state: it returns 1 (SCLKSTS is not the
    PLL) and starts nothing.
    Not checked: the word 0x200002B0 (fn_0800ba4c stores 8000000 at 0x0800BAFE before the
    scatter-load __decompress / zero fill at 0x08007974 / 0x0800799A rewrite it to 144000000)."""
    # cycles per instruction 1: meter_model counts 1 + FLASH_AC LATENCY cycles per instruction; on
    # this path LATENCY keeps its reset value 0 (manual 3.2.5.2.1, reset 0x00000030; fn_0800c274
    # only ors 0x90, the LATENCY write of fn_0800ba4c is on the HSE-ready path)
    rig = Ctl(core_hz=8_000_000, devices=(HseFails(),), usb=False, cpi=1)
    m, dev = rig.m, rig.dev
    m.watch(0x0800BAF8, 'hse fallback')
    m.watch(rig.s['usb_start'], 'usb_start')
    end = m.run_for(3.0)
    NOTES.append('k19: end %r at %.3f s' % (end, m.now()))
    check('hse fallback' in m.events(), 'events %r' % m.events())
    check('usb_start' not in m.events(), 'usb_start reached on the HSE-failure path: %r' % m.events())
    pa8 = [e[1] for e in m.st['log'] if e[0] == 'pa8']    # V1.1: 0 at 0x08008210, 1 only after the wait
    check(pa8 and 0 not in pa8 and m.st['pa8'] == 1, 'PA8 levels driven %r, now %r' % (pa8, m.st['pa8']))
    check(m.st['regs'].get(0x40021004, 0) & 3 != 2, 'system clock switched to the PLL')  # SWS = SW in the model
    r = m.call(rig.s['usb_start'])
    check(r == 1, 'usb_start on the HSI returned %r (end %r)' % (r, m.st['end']))
    check(not m.st['regs'].get(0x4002101C, 0) & (1 << 23), 'USBEN set')
    check(not dev.pullup and not [x for x in dev.log if x[0] in ('usben', 'pullup')], 'USB started: %r' % dev.log)
    check(rig.rd8(OWN_USB + UO_STARTED) == 0, 'UO_STARTED set')
    check(not m.st['viol'], 'violations %r' % m.st['viol'])
    return True


# ---------------------------------------------------------------- settings commands

@case
def k20_restore_defaults_and_recovery_refusals():
    rig = Ctl().up()
    check(rig.ask('RESTORE_DEF', b'\x00\x00')[0] == S_BAD_ARG, 'without confirmation')
    for name in ('RESTORE_B', 'ACCEPT_A', 'ACCEPT_B', 'ACCEPT_DEF'):
        st, d = rig.ask(name, OK2, timeout=5.0)
        check(st == S_NOT_NOW and len(d) == 8, '%s in the normal state: status %d' % (name, st))
        check(rig.ask(name, b'\x00\x00')[0] == S_BAD_ARG, '%s without confirmation' % name)
    st, d = rig.ask('RESTORE_DEF', OK2, timeout=5.0)
    check(st == S_OK, 'RESTORE_DEFAULTS status %d' % st)
    check(rig.rd(V_LANG_SET) == 1 and rig.rd(V_LANGUAGE) == 1,     # V1.1 leaves the flag 0; our own_save
          'first-start flag %d language %d after the defaults' % (rig.rd(V_LANG_SET), rig.rd(V_LANGUAGE)))
    # the screen state word 0x20001168 (block offset 0xBEC) lies inside the saved block (vendor
    # layout): 0x0800B4C8 zero-fills the block and saves with it 0, the screen is set back to 1
    # only after the save; every other word must equal the saved copies
    blk = bytearray(rig.rd(V_BLOCK, BLK))
    blk[0xBEC:0xBF0] = b'\x00\x00\x00\x00'
    check(rig.m.get(SET_A, BLK) == blk and rig.m.get(SET_B, BLK) == blk, 'defaults not saved to both copies')
    # held saves: RESTORE_DEFAULTS and CALIBRATE refused
    erased = b'\xff' * 0x1000
    rig = Ctl(a=erased, b=erased).up()
    check(rig.rd(SAVE_FLAGS) & SF_HELD, 'saves not held without a valid copy')
    check(rig.ask('RESTORE_DEF', OK2)[0] == S_NOT_NOW, 'RESTORE_DEFAULTS while held')
    check(rig.ask('CALIBRATE', b'\x00' + OK2)[0] == S_NOT_NOW, 'CALIBRATE while held')
    check(rig.ask('SET_SAVE', OK2, timeout=5.0)[0] == S_NOT_NOW, 'SETTINGS_SAVE while held')
    check(rig.ask('CALIBRATE', b'\x05' + OK2)[0] == S_BAD_ARG, 'CALIBRATE type 5 outside factory mode')
    check(rig.ask('CALIBRATE', b'\x00\x00\x00')[0] == S_BAD_ARG, 'CALIBRATE without confirmation')
    st, d = rig.ask('ACCEPT_DEF', OK2, timeout=5.0)
    check(st == S_OK and not rig.rd(SAVE_FLAGS) & SF_HELD, 'ACCEPT_DEFAULTS: status %d flags 0x%X'
          % (st, rig.rd(SAVE_FLAGS)))
    return True


@case
def k21_write_block_then_restart():
    erased = b'\xff' * 0x1000
    rig = Ctl(a=erased, b=erased).up()
    host = block_with(**{'0x20001158': 70})
    crc = zlib.crc32(host)
    st, d = rig.ask('WRITE_BLOCK', OK2 + struct.pack('<HHI', 8, BLK, crc) + host[:8])
    check(st == S_BAD_ARG, 'first chunk at offset 8 accepted: %d' % st)
    hits = watch_restart(rig)                            # before the last chunk: the restart follows it
    off = 0
    while off < BLK:
        n = min(400, BLK - off)
        st, d = rig.ask('WRITE_BLOCK', OK2 + struct.pack('<HHI', off, BLK, crc) + host[off:off + n], timeout=5.0)
        off += n
        if off < BLK:
            check(st == S_OK and struct.unpack('<H', d)[0] == off, 'chunk to 0x%X: %d %r' % (off, st, d))
    check(st == S_OK and len(d) == 8, 'last chunk: status %d' % st)
    check_restart(rig, hits, REQ_RESTART, 'WRITE_BLOCK')
    for base in (SET_A, SET_B):
        check(rig.m.get(base, BLK) == host, 'copy 0x%08X is not the host block' % base)
    check(rig.rd(0x20001158) == 70, 'restarted application: 0x20001158 = %d, not the host block value 70'
          % rig.rd(0x20001158))
    # a wrong transfer CRC: status 7, nothing written
    rig = Ctl(a=erased, b=erased).up()
    off, st = 0, None
    while off < BLK:
        n = min(400, BLK - off)
        st, d = rig.ask('WRITE_BLOCK', OK2 + struct.pack('<HHI', off, BLK, crc ^ 1) + host[off:off + n], timeout=5.0)
        off += n
    check(st == S_XFER_CRC and rig.m.get(SET_A, 4) == b'\xff' * 4, 'wrong CRC: status %d' % st)
    return True


@case
def k22_setup_language():
    """English only (the language chooser and the Chinese texts are removed): SETUP_LANGUAGE has no handler, status 1 for any payload, also
    with a block whose first-start flag and language are 0 (it starts on the measure screen)."""
    blk0 = block_with(lang_set=0, **{'0x2000115c': 0})
    rig = Ctl(a=copy_image(blk0, 2), b=copy_image(blk0, 1)).up()
    check(rig.rd(V_SCREEN) == 1 and rig.rd(V_LANG_SET) == 1 and rig.rd(V_LANGUAGE) == 1,
          'screen %d flag %d language %d' % (rig.rd(V_SCREEN), rig.rd(V_LANG_SET), rig.rd(V_LANGUAGE)))
    for p in (b'', b'\x00', b'\x01', b'\x02'):
        st, d = rig.ask('SETUP_LANGUAGE', p)
        check(st == S_UNKNOWN and not d, 'SETUP_LANGUAGE %r: status %d' % (p, st))
    return True


# ---------------------------------------------------------------- updates

def patch_version(slot_index, version):
    """Header word +12 of a slot set to version, header CRC (+28 over bytes 0..27) recomputed: the
    starter's header_ok still accepts it (its image CRC covers only the image)."""
    def p(m):
        base = SLOTS[slot_index] - 0x08000000
        struct.pack_into('<I', m.flash, base + 12, version)
        struct.pack_into('<I', m.flash, base + 28, zlib.crc32(bytes(m.flash[base:base + 28])))
    return p


@case
def k23_update_mode_refused_on_version_1_slots():
    for slot, recs in ((1, ((REC0, cell(1, ST_OK, 1)),)), (0, ())):
        rig = Ctl(records=recs, patch=patch_version(slot, 1)).up()
        st, d = rig.ask('UPDATE_MODE')
        check(st == S_SAFETY and d[0] == slot and struct.unpack_from('<I', d, 1)[0] == 1,
              'slot %d version 1: status %d data %r' % (slot, st, d.hex()))
        rig.run(1.0)
        check(rig.rd(REQ_WORD) == 0, 'request word written')
        # RESET is refused the same way (a version-1 slot does not feed the watchdog after a
        # soft restart), with no data and no restart word
        st, d = rig.ask('RESET')
        check(st == S_SAFETY and d == b'', 'RESET on slot %d version 1: status %d data %r' % (slot, st, d.hex()))
        rig.run(1.0)
        check(rig.rd(REQ_WORD) == 0, 'restart word written after a refused RESET')
    return True


@case
def k24_update_mode_version_2_enters_update_mode():
    rig = Ctl(chain=True).up()
    hits = watch_restart(rig)                        # before the request: the restart follows it
    st, d = rig.ask('UPDATE_MODE')
    check(st == S_OK and d[0] == 1 and struct.unpack_from('<I', d, 1)[0] >= 2 and d[5] == 1,
          'status %d data %r' % (st, d.hex()))
    check_restart(rig, hits, REQ_MAGIC, 'UPDATE_MODE', done='update')
    check(rig.rd(REQ_WORD) == 0, 'request word not cleared by the slot')
    check(rig.rd(WDG_ON) == 3, 'slot WDG_ON %d after UPDT' % rig.rd(WDG_ON))
    rig.run(1.5)                                     # update mode: the slot feeds the running IWDG
    check(not [e for e in rig.m.iwdg_log if e['kind'] == 'reset'], 'IWDG reset in update mode')
    return True


def slot_file(name):
    return open('%s/BOOT_%s.bin' % (SLOT_DIR, name), 'rb').read()


def boot_status(rig):
    d = rig.ask_ok('BOOT_STATUS', size=47)
    slots = [struct.unpack_from('<IIIB', d, 13 * k) for k in range(3)]
    return dict(slots=slots, newest=(d[39], d[40], struct.unpack_from('<I', d, 41)[0]), next=d[45], free=d[46])


def boot_write(rig, slot, data, crc=None, chunk=256):
    st, d = rig.ask('BOOT_BEGIN', struct.pack('<BII', slot, len(data), zlib.crc32(data) if crc is None else crc),
                    timeout=15.0)
    check(st == S_OK, 'BOOT_BEGIN status %d' % st)
    for off in range(0, len(data), chunk):
        st, d = rig.ask('BOOT_DATA', struct.pack('<I', off) + data[off:off + chunk])
        check(st == S_OK, 'BOOT_DATA at 0x%X: status %d %r' % (off, st, d.hex()))
    return rig.ask('BOOT_END')


@case
def k25_boot_status_free_slot_and_refusals():
    tests = [('OK A', ((REC0, cell(1, ST_OK, 1)),), 2, 1),
             ('OK B', ((REC0, cell(2, ST_OK, 1)),), 1, 2),
             ('no record (F)', (), 1, 0),
             ('A on trial, not confirmed (F)', ((REC0, cell(1, ST_INSTALL, 1)), (REC0 + 16, cell(1, ST_TRIAL, 2))), 2, 0),
             ('OK F', ((REC0, cell(0, ST_OK, 1)),), 1, 0)]
    for name, recs, free, nxt in tests:
        rig = Ctl(records=recs).up()
        bs = boot_status(rig)
        check(bs['free'] == free and bs['next'] == nxt, '%s: free %d next %d' % (name, bs['free'], bs['next']))
        check(all(s[3] == 1 for s in bs['slots']), '%s: slot checks %r' % (name, bs['slots']))
        other = 3 - free
        data = slot_file('B' if free == 2 else 'A')
        check(rig.ask('BOOT_BEGIN', struct.pack('<BII', other, len(data), 0))[0] == S_NOT_NOW,
              '%s: BOOT_BEGIN of the slot that is not free accepted' % name)
        for p in (struct.pack('<BII', 0, len(data), 0), struct.pack('<BII', 3, len(data), 0),
                  struct.pack('<BII', free, 0x204, 0), struct.pack('<BII', free, 0x6004, 0),
                  struct.pack('<BII', free, 0x20A, 0), b'\x01\x00'):
            check(rig.ask('BOOT_BEGIN', p)[0] == S_BAD_ARG, '%s: BOOT_BEGIN %s accepted' % (name, p.hex()))
        # cmd.s h_boot_data checks offset + chunk against the length of BOOT_BEGIN (0 before any)
        # before the writer state, so a chunk before BOOT_BEGIN is a bad argument (2), not 3
        check(rig.ask('BOOT_DATA', struct.pack('<I', 0) + b'\x00' * 4)[0] == S_BAD_ARG, '%s: data before begin' % name)
        check(rig.ask('BOOT_END')[0] == S_NOT_NOW and rig.ask('BOOT_INSTALL')[0] == S_NOT_NOW, '%s: end / install' % name)
        check(not rig.flash_ops(), '%s: wrote flash %r' % (name, rig.flash_ops()[:3]))
    return True


@case
def k26_boot_write_install_trial_confirm():
    """OK A runs: BOOT_* writes BOOT_B.bin to the free slot B, BOOT_INSTALL appends INSTALL B and
    soft-restarts (stop_at_starter); the starter's run goes on in a meter whose slot B is code (mode
    'app' without the BOOT gate), with the RAM the soft restart leaves (request word RSTR): it trials
    B (starter: TRIAL), B starts the watchdog and confirms (OK B) and the application runs."""
    data = slot_file('B')
    rig = Ctl(boot_target='B').up()
    st, d = boot_write(rig, 2, data, crc=zlib.crc32(data) ^ 1)
    check(st == S_XFER_CRC, 'BOOT_END with a wrong file CRC: status %d' % st)
    check(rig.ask('BOOT_INSTALL')[0] == S_NOT_NOW, 'install after a failed check')
    st, d = boot_write(rig, 2, data)
    check(st == S_OK and struct.unpack('<I', d)[0] == struct.unpack_from('<I', data, 12)[0], 'BOOT_END %d %r' % (st, d))
    check(rig.m.get(SLOTS[2], len(data)) == data, 'slot B differs from the file')
    for op in rig.flash_ops():
        check(SLOTS[2] <= op[1] < SLOTS[2] + SLOT_SIZE or REC0 <= op[1] < REC_END, 'op outside the BOOT gate %r' % (op,))
    check(rig.ask('BOOT_INSTALL')[0] == S_OK, 'BOOT_INSTALL status')
    stop_at_starter(rig, 'BOOT_INSTALL')
    recs = [r[1:] for r in rig.m.records()]
    check(recs == [(1, ST_OK, 1), (2, ST_INSTALL, 2)], 'records %r' % recs)
    flash = bytes(rig.m.flash)
    nxt = Ctl(chain=True, usb=False, ram={REQ_WORD: REQ_RESTART})
    nxt.m.flash[:] = flash
    nxt.start(keep_ram=True)
    nxt.to_main_loop()
    recs = [r[1:] for r in nxt.m.records()]
    check(recs == [(1, ST_OK, 1), (2, ST_INSTALL, 2), (2, ST_TRIAL, 3), (2, ST_OK, 4)], 'after the trial: %r' % recs)
    check(nxt.rd(OWN_CTL + CT_HAND_SLOT) == 2, 'running slot %d' % nxt.rd(OWN_CTL + CT_HAND_SLOT))
    check('start' in [e['kind'] for e in nxt.m.iwdg_log], 'trial start without the watchdog')
    nxt.run(2.0)                                     # the application feeds: no reset
    return True


def hanging(data, sym):
    """BOOT_B.bin with its first instruction of fn_080009c0 (main's first call after slot_trial_wdg,
    system_05.s) replaced by `b .` (0xE7FE), image CRC (+8) and header CRC (+28) recomputed."""
    d = bytearray(data)
    off = (sym['fn_080009c0'] & ~1) - SLOTS[2]
    d[off:off + 2] = b'\xfe\xe7'
    ln = struct.unpack_from('<I', d, 4)[0]
    struct.pack_into('<I', d, 8, zlib.crc32(bytes(d[0x200:0x200 + ln])))
    struct.pack_into('<I', d, 28, zlib.crc32(bytes(d[:28])))
    return bytes(d)


def trial_after_install(recs, expect_slot):
    m0 = Ctl(records=recs, boot_target='B', usb=True)
    data = hanging(slot_file('B'), m0.m.sym[2])
    m0.up()
    st, d = boot_write(m0, 2, data)
    check(st == S_OK, 'BOOT_END of the hanging file: %d' % st)
    check(m0.ask('BOOT_INSTALL')[0] == S_OK, 'install')
    stop_at_starter(m0, 'install')
    flash = bytes(m0.m.flash)
    nxt = Ctl(records=recs, chain=True, usb=False, ram={REQ_WORD: REQ_RESTART})
    nxt.m.flash[:] = flash
    nxt.start(keep_ram=True)
    end = nxt.m.run_for(3.0)
    check(end == 'iwdg', 'hanging trial slot: end %r' % end)
    nxt.start(keep_ram=True)
    nxt.to_main_loop()
    check(nxt.rd(OWN_CTL + CT_HAND_SLOT) == expect_slot, 'rollback started slot %d' % nxt.rd(OWN_CTL + CT_HAND_SLOT))
    recs_after = [r[1:] for r in nxt.m.records()]
    check(recs_after[-1][:2] == (2, ST_TRIAL), 'records after the rollback %r' % recs_after)
    return recs_after


@case
def k27_boot_rollback_and_all_unconfirmed():
    r = trial_after_install(((REC0, cell(1, ST_OK, 1)),), expect_slot=1)
    NOTES.append('k27: rollback to A, records %r' % (r,))
    r = trial_after_install(((REC0, cell(1, ST_INSTALL, 1)), (REC0 + 16, cell(1, ST_TRIAL, 2))), expect_slot=0)
    NOTES.append('k27: all unconfirmed, rollback to F, records %r' % (r,))
    return True


@case
def k28_boot_power_cut_after_every_flash_operation():
    """The flash operations of a whole BOOT_BEGIN / DATA / END / INSTALL session (OK A running, slot
    B written), replayed onto the flash before it up to every operation; that operation cut in the
    middle ('mixed' for slot words, every pattern for erases and the record words). Every power-on
    start (meter_model mode 'boot': the application start ends the run) must start the application
    through A before the INSTALL record is complete, through B (after its trial) once it is."""
    data = slot_file('B')
    rig = Ctl(boot_target='B').up()
    before = bytes(rig.m.flash)
    del rig.m.st['log'][:]
    st, d = boot_write(rig, 2, data)
    check(st == S_OK and rig.ask('BOOT_INSTALL')[0] == S_OK, 'session failed')
    ops = list(rig.flash_ops())
    reset = struct.unpack_from('<I', rig.m.flash, APP + 4 - 0x08000000)[0] & ~1
    rec_ops = [k for k, x in enumerate(ops) if REC0 <= x[1] < REC_END]
    check(len(rec_ops) == 4, 'INSTALL record: %d operations, expected its four words' % len(rec_ops))
    count = 0
    m = Meter()                                      # one model (its starter / slot symbols); boot()
    for n in range(len(ops) + 1):                    # makes a fresh chip from m.flash each time
        x = ops[n] if n < len(ops) else None
        pats = [None] if x is None else (('unchanged', 'ff', 'mixed') if x[0] == 'erase' or n in rec_ops else ('mixed',))
        for pat in pats:
            fl = bytearray(before)
            for y in ops[:n]:
                o = y[1] - 0x08000000
                if y[0] == 'erase':
                    fl[o:o + PAGE] = b'\xff' * PAGE
                else:
                    struct.pack_into('<I', fl, o, y[2])
            if x is not None:
                o = x[1] - 0x08000000
                if x[0] == 'erase':
                    fl[o:o + PAGE] = ERASE_CUTS[pat](bytes(fl[o:o + PAGE]))
                else:
                    struct.pack_into('<I', fl, o, WORD_CUTS[pat](struct.unpack_from('<I', fl, o)[0], x[2]) & 0xFFFFFFFF)
            m.flash[:] = fl
            end = m.boot()
            what = 'cut in op %d of %d (%r, %s)' % (n, len(ops), x, pat)
            check(not m.st['viol'], '%s: violation %r' % (what, m.st['viol']))
            check(end == 'app' and m.st['app_pc'] == reset, '%s: end %r' % (what, end))
            installed = n > rec_ops[-1] if rec_ops else False
            exp = 'slot2 reset' if installed or (x is None) else 'slot1 reset'
            got = [e for e in m.events() if e.endswith(' reset')]
            check(got == [exp], '%s: started %r, expected %s' % (what, got, exp))
            count += 1
    NOTES.append('k28: %d flash operations, %d starts after cuts' % (len(ops), count))
    return True


# ---------------------------------------------------------------- watchdog stretch of every command

@case
def k29_watchdog_stretch_of_every_command():
    rig = Ctl(boot_target='B', panel=True).up()
    m = rig.m
    data = slot_file('B')
    plan = [('INFO', b''), ('PING', b'x' * 511), ('BATTERY', b''), ('FACTORY_MODE', b''), ('STATE', b''),
            ('STREAM', struct.pack('<H', 20)), ('STREAM', struct.pack('<H', 0)), ('SCREEN', b'\x02'),
            ('SCREEN', b'\x01'), ('KEY', bytes([10])), ('LCR_TABLES', b''), ('LCR_TABLES', b'\x02'),
            ('LCR_SET', b'\x02\x02'), ('MEASURE', b''), ('MEASURE_STREAM', struct.pack('<H', 50)),
            ('MEASURE_STREAM', struct.pack('<H', 0xFFFF)), ('COMPARE', b''),
            ('COMPARE_SET', struct.pack('<ffBBB', 2200.0, 1.0, 0, 0, 0)), ('HOLD', b'\x01'), ('HOLD', b'\x00'),
            ('SET_TABLES', b''), ('SET_TABLES', b'\x01'), ('SET_SET', struct.pack('<BH', 1, 50)),
            ('SET_SAVE', OK2), ('CAL_READ', struct.pack('<BHH', 1, 0, 256)), ('SCREENSHOT', b'\x00'),
            ('MEM_READ', struct.pack('<IH', APP, 256)), ('BOOT_STATUS', b''), ('CALIBRATE', b'\x05' + OK2),
            ('RESTORE_B', OK2), ('ACCEPT_A', OK2), ('ACCEPT_B', OK2), ('ACCEPT_DEF', OK2),
            ('BOOT_BEGIN', struct.pack('<BII', 2, len(data), zlib.crc32(data))),
            ('BOOT_DATA', struct.pack('<I', 0) + data[:256]), ('BOOT_END', b''), ('RESTORE_DEF', OK2)]
    out = []
    for name, p in plan:
        t0 = m.now()
        st, d = rig.ask(name, p)
        rig.drain(0.05)
        s = stretch_in(m, t0, m.now())
        out.append('%s %.1f' % (name, s * 1e3))
        check(s < PERIOD_MIN, '%s: longest watchdog stretch %.3f s' % (name, s))
    check(not [e for e in m.iwdg_log if e['kind'] == 'reset'], 'IWDG reset')
    NOTES.append('k29 longest stretch per command (ms): ' + ', '.join(out))
    return True


# ---------------------------------------------------------------- the guard sweep

def nav_settings(rig, item, dialog=False):
    """Settings screen, then the vendor menu item `item` (0, 2..6: own_menu shows no item 1, so item n
    is n - 1 presses of key 0x20 for n >= 2). After each press the run continues until the handler
    consumed the event (0x20001192 = 0): a settings redraw takes several hundred ms of one main-loop
    pass, and a press while the event slot is still full is not posted (test_own_lang.py tap)."""
    def tap(mask, ms=60):
        rig.press(mask, ms)
        rig.m.run_for(seconds=3.0, until=lambda mm: rig.rd16(V_KEY_CODE) == 0)
        check(rig.rd16(V_KEY_CODE) == 0, 'nav_settings: key 0x%X not consumed within 3 s' % mask)
    tap(KEY_OK, 1200)                                # long 8: settings (V1.1 key behaviour: key 8 long opens the settings screen)
    for _ in range(item - 1 if item else 0):
        tap(0x0020)                                  # next visible item (cmd.s add_menu: key 0x20)
    if dialog:
        tap(KEY_OK)


STATES = [
    # name, block first-start flag, navigation, check of the reached state, named save sites
    ('measure', 1, lambda r: None, lambda r: r.rd(V_SCREEN) == 1, {POWER_OFF_LR}),
    ('compare', 1, lambda r: r.press(0x0400, 1200), lambda r: r.rd(V_SCREEN) == 2, {POWER_OFF_LR}),
] + [('settings item %d' % i, 1, (lambda i: lambda r: nav_settings(r, i))(i),
      (lambda i: lambda r: r.rd(V_SCREEN) == 3 and r.rd(V_MENU) == i and r.rd(V_DIALOG) == 0)(i), {POWER_OFF_LR})
     for i in (0, 2, 3, 4, 5, 6)] + [
    ('settings item %d dialog' % i, 1, (lambda i: lambda r: nav_settings(r, i, dialog=True))(i),
     (lambda i: lambda r: r.rd(V_SCREEN) == 3 and r.rd(V_MENU) == i and r.rd(V_DIALOG) != 0)(i), {POWER_OFF_LR})
    for i in (0, 5, 6)] + [
    ('calibration running', 1, lambda r: (nav_settings(r, 5, dialog=True), r.press(KEY_OK)),
     lambda r: r.rd(V_CAL_RUN) != 0, {POWER_OFF_LR, CAL_FINISH_LR}),
]
# block words a key may change (the V1.1 user functions and settings): the settings, the screen word;
# never the markers, the calibration tables, the calibration work area 0x200010C0..0x20001137
# (block 0xB44..0xBBB), the first-start flag or the undocumented words 0x2000117C / 0x20001180
ALLOWED = {a - V_BLOCK for a in (V_LEVEL, V_BIAS, V_FREQ, V_FUNC, V_RANGE, V_SPEED, V_CIRCUIT, V_BRIGHT,
                                 V_LANGUAGE, 0x20001160, 0x20001164, V_SCREEN, 0x2000116C, 0x20001170,
                                 0x20001174, 0x20001178, 0x20001184, 0x20001188)}


def block_diff(a, b):
    return [o for o in range(0, BLK, 4) if a[o:o + 4] != b[o:o + 4]]


# own.inc OWN_CAL (cal.s): CAO_ON, CAO_REC, the recorded words and the 0x78 bytes of 0x200010C0
OWN_CAL = OWN_RAM + 0x5BE0
CAO_ON, CAO_REC, CAO_SFREQ, CAO_SLEVEL, CAO_SBIAS, CAO_SSPEED, CAO_REL = 0x00, 0x28, 0x2C, 0x30, 0x34, 0x38, 0x148
V_CAL_WORK = 0x200010C0


def cal_staged(rig, blk):
    """The block own_save stages while a sweep of own/cal.s runs (save.s stage_cal_fix): blk with the
    recorded frequency, level, bias and speed and the recorded 0x78 bytes at 0x200010C0; blk itself
    when no sweep runs or nothing is recorded."""
    if not rig.rd(OWN_CAL + CAO_ON) or not rig.rd(OWN_CAL + CAO_REC):
        return blk
    b = bytearray(blk)
    for addr, off in ((V_FREQ, CAO_SFREQ), (V_LEVEL, CAO_SLEVEL), (V_BIAS, CAO_SBIAS), (V_SPEED, CAO_SSPEED)):
        struct.pack_into('<I', b, addr - V_BLOCK, rig.rd(OWN_CAL + off))
    b[V_CAL_WORK - V_BLOCK:V_CAL_WORK - V_BLOCK + 0x78] = rig.rd(OWN_CAL + CAO_REL, 0x78)
    return bytes(b)


def _k30_guard(state):
    """Every key bit x (short, hold 1100 ms) in one state of STATES (the cases k30a..k30l, one per
    state, so a full pass spreads them over the cores; owner 2026-11-22, after the single case took
    more than 7200 s in a full pass), each from a fresh start: the
    state reached by physical keys (KeyPad), the KEY command, then at least 50 main-loop passes (and,
    once the calibration sweep fn_0800bd5c runs, at least 50 of its calls; it finishes at step 45),
    then a physical power-off (power key 1300 ms). Flash model: the named-save gate, so the run stops
    at the first erase or program outside own_save called from a named site (the power-off save,
    and in 'calibration running' the calibration finish). RAM block: no word outside ALLOWED changes
    between the KEY and the power-off; the copies after the power-off hold the block of that
    moment."""
    states = [s for s in STATES if s[0] == state]
    check(len(states) == 1, 'k30: no state %r in STATES' % state)
    bits = [b for b in range(14) if OPTS['key'] in (None, b)]
    holds = [h for h in (0, 1100) if OPTS['hold'] in (None, h)]
    count, refused = 0, 0

    def build(lang, nav, reached, named, what):
        """A rig from power-on, in the state: ready for the KEY command."""
        blk = block_with(lang_set=lang)
        rig = Ctl(a=copy_image(blk, 2), b=copy_image(blk, 1), named=named)
        rig.m.watch(rig.s['ctl_loop'], 'pass')
        rig.m.watch(rig.s['fn_0800bd5c'], 'sweep')
        rig.to_main_loop()
        nav(rig)
        check(reached(rig), '%s: state not reached (screen %d item %d dialog %d cal %d)'
              % (what, rig.rd(V_SCREEN), rig.rd(V_MENU), rig.rd(V_DIALOG), rig.rd(V_CAL_RUN)))
        rig.info = rig.host.enumerate()
        return rig, blk

    for name, lang, nav, reached, named in states:
        t_state, snap, verified = time.time(), None, False
        for bit in bits:
            for hold in holds:
                what = '%s, key bit %d %s' % (name, bit, 'hold' if hold else 'short')
                if OPTS['fresh']:
                    rig, blk = build(lang, nav, reached, named, what)
                else:
                    if snap is None:
                        rig, blk = build(lang, nav, reached, named, what)
                        snap = Snapshot(rig)
                    else:
                        snap.restore()
                        rig = snap.rig
                        if not verified:
                            verified = True
                            diff = snap.verify()
                            check(not diff, '%s: snapshot restore incomplete: %r' % (what, diff))
                m = rig.m
                b0 = rig.rd(V_BLOCK, BLK)
                cal0 = b0[0x04:0xB44]
                st, s = rig.ask('KEY', struct.pack('<BH', bit, hold), timeout=25.0)
                check(st in (S_OK, S_SAFETY, S_BUSY, S_NOT_NOW), '%s: status %d' % (what, st))
                refused += st == S_SAFETY
                p0, s0 = m.events().count('pass'), m.events().count('sweep')
                t_end = m.now() + 30.0
                while m.now() < t_end:
                    ev = m.events()
                    if ev.count('pass') - p0 >= 50 and (ev.count('sweep') == s0 or ev.count('sweep') - s0 >= 50):
                        break
                    rig.run(0.05)
                b1 = rig.rd(V_BLOCK, BLK)
                bad = [o for o in block_diff(b0, b1) if o not in ALLOWED]
                # revision 10 item 4 (remote control of the calibration menu): an injected key 8 in the calibration dialog starts
                # the calibration as the meter's key does; the start zero-fills 0x200010C0..0x20001137 (block
                # 0xB44..0xBBB, ui_44.s 0x0800F740) and its sweep (own/cal.s) runs
                started = name != 'calibration running' and rig.rd(V_CAL_RUN) != 0
                running = name == 'calibration running' or started
                if started:
                    check(all(0xB44 <= o < 0xBBC for o in bad), '%s: a calibration started by the key changed block '
                          'words outside the settings and 0x200010C0..: %r' % (what, [hex(o) for o in bad]))
                elif name != 'calibration running':
                    check(not bad, '%s: block words changed outside the settings: %r' % (what, [hex(o) for o in bad]))
                ev = m.events()
                passes, sweeps = ev.count('pass') - p0, ev.count('sweep') - s0
                rig.press(KEY_POWER, 1300)
                # the power-off path saves first, then drops PA8: measured 0.48 s after the release
                # (both builds), the save itself 0.77 s, 0.83 s with a retry (s20); wait for PA8 up to
                # 2 s after the release, more than twice the longest measured save
                t_off = m.now() + 1.9
                while m.st['pa8'] != 0 and m.now() < t_off:
                    rig.run(0.01)
                check(m.st['pa8'] == 0, '%s: no power-off' % what)
                check(not m.st['viol'], '%s: %r' % (what, m.st['viol']))
                blk_off = rig.rd(V_BLOCK, BLK)
                if running:
                    # a save during the sweep stages the settings of before it (own/save.s stage_cal_fix
                    # from the recording of own/cal.s): frequency, level, bias, speed, 0x200010C0..
                    blk_off = cal_staged(rig, blk_off)
                for base in (SET_A, SET_B):
                    got = m.get(base, BLK)
                    check(got == blk_off or got == blk, '%s: copy 0x%08X holds neither block' % (what, base))
                    if name != 'calibration running':
                        check(got[0x04:0xB44] == cal0, '%s: calibration tables of 0x%08X changed' % (what, base))
                count += 1
                # one record per run, the same in both modes: answer, refusal, loop passes and sweep calls
                # after the key, changed block words, the end time of the run, log length, CRCs of the RAM
                # block before / after the power-off and of both settings copies
                print('k30rec %s|%d|%d|st=%d|refused=%d|started=%d|passes=%d|sweeps=%d|bad=%d|pa8=%r|t=%.9f|log=%d|'
                      'b1=%08x|off=%08x|A=%08x|B=%08x' % (
                          name, bit, hold, st, st == S_SAFETY, started, passes, sweeps, len(bad), m.st['pa8'], m.now(),
                          len(m.st['log']), zlib.crc32(b1), zlib.crc32(blk_off), zlib.crc32(m.get(SET_A, BLK)),
                          zlib.crc32(m.get(SET_B, BLK))), flush=True)
        print('k30time %s|%s|%.1f s' % (name, 'fresh' if OPTS['fresh'] else 'snapshot', time.time() - t_state),
              flush=True)
    NOTES.append('k30 %s: %d runs, %d keys refused with status 6' % (state, count, refused))
    return True


# k30, one case per state of STATES (in its order): prefix k30 selects all twelve
@case
def k30a_guard_measure():
    """_k30_guard in the measure screen."""
    return _k30_guard('measure')


@case
def k30b_guard_compare():
    """_k30_guard in the compare screen."""
    return _k30_guard('compare')


@case
def k30c_guard_settings_item_0():
    """_k30_guard in the settings screen, item 0."""
    return _k30_guard('settings item 0')


@case
def k30d_guard_settings_item_2():
    """_k30_guard in the settings screen, item 2."""
    return _k30_guard('settings item 2')


@case
def k30e_guard_settings_item_3():
    """_k30_guard in the settings screen, item 3."""
    return _k30_guard('settings item 3')


@case
def k30f_guard_settings_item_4():
    """_k30_guard in the settings screen, item 4."""
    return _k30_guard('settings item 4')


@case
def k30g_guard_settings_item_5():
    """_k30_guard in the settings screen, item 5."""
    return _k30_guard('settings item 5')


@case
def k30h_guard_settings_item_6():
    """_k30_guard in the settings screen, item 6."""
    return _k30_guard('settings item 6')


@case
def k30i_guard_settings_item_0_dialog():
    """_k30_guard in the settings screen, item 0 with its dialog open."""
    return _k30_guard('settings item 0 dialog')


@case
def k30j_guard_settings_item_5_dialog():
    """_k30_guard in the settings screen, item 5 with its dialog open."""
    return _k30_guard('settings item 5 dialog')


@case
def k30k_guard_settings_item_6_dialog():
    """_k30_guard in the settings screen, item 6 with its dialog open."""
    return _k30_guard('settings item 6 dialog')


@case
def k30l_guard_calibration_running():
    """_k30_guard while the calibration sweep runs."""
    return _k30_guard('calibration running')


@case
def k31_trial_start_application_startup_stretch():
    """INSTALL A: the slot's trial watchdog runs through the application's start-up until the
    application's own feeds (own_start feeds when the hand-over bit 8 is set, then 0x08010178 and
    the main loop): no reset, longest stretch below 0.67 s, at 60 and 30 kHz."""
    out = []
    for lsi in (60000, 30000):
        rig = Ctl(records=((REC0, cell(1, ST_INSTALL, 1)),), chain=True, usb=False, lsi=lsi)
        rig.to_main_loop()
        rig.run(1.5)
        m = rig.m
        kinds = [e['kind'] for e in m.iwdg_log]
        check('reset' not in kinds and 'start' in kinds, 'LSI %d: IWDG log %r' % (lsi, kinds[:6]))
        s = m.iwdg_stretch()['longest']['seconds']
        check(s < PERIOD_MIN, 'LSI %d: longest stretch %.3f s' % (lsi, s))
        out.append('%d Hz: %.1f ms' % (lsi, s * 1e3))
    NOTES.append('k31: start-up stretch ' + ', '.join(out))
    return True


@case
def k32_measurement_of_a_1_kohm_resistor():
    """The measurement path (tests/measure_model.py) with DutSource R = 1 kohm at the default 1 kHz /
    0.6 V: fn_0800a068 sets the new-result word 0x20001200 (its result ring 0x200011F0 entries long,
    fn_08009f10) and copies |Z| / theta to 0x200050C4 / 0x200050CC; the displayed R 0x200050B8 is
    |Z| cos(theta) in series mode (|Z| below 1.1 Mohm, circuit mode auto). Expected from the DUT:
    |Z| = 1000 ohm, theta = 0; the tolerances (1 ohm, 0.5 degree) are this test's choice."""
    rig = Ctl(usb=False, source=DutSource('R', 1000.0)).up()
    m = rig.m
    news = []

    def hw(uc, acc, addr, size, value, user):
        if value == 1:
            news.append(m.now())
    m.uc.hook_add(UC_HOOK_MEM_WRITE, hw, begin=0x20001200, end=0x20001203)
    rig.run(3.0)
    z, th, r = (struct.unpack('<f', struct.pack('<I', rig.rd(a)))[0] for a in (V_Z, V_THETA, 0x200050B8))
    check(len(news) >= 3, '%d new results in 3 s' % len(news))
    check(abs(z - 1000.0) <= 1.0 and abs(th) <= 0.5 and abs(r - 1000.0) <= 1.0,
          '|Z| %.3f ohm, theta %.3f deg, R %.3f ohm' % (z, th, r))
    stalls = [e for e in rig.meas.log if e[0] == 'dma-enabled-at-txnum-0']
    check(not stalls, 'channels enabled at TXNUM 0: %r' % stalls)
    NOTES.append('k32: %d results in 3 s, |Z| %.3f ohm, theta %.3f deg, gains %d / %d, range %d' % (
        len(news), z, th, rig.rd8(0x200011C5), rig.rd8(0x200011C6), rig.rd8(0x200011C8)))
    return True


# ---------------------------------------------------------------- vendor fixes F4 / F9 (display)

def fb_replay(flushes):
    """Panel memory from the logged RAMWR windows (pixels fill the window row by row)."""
    fb = {}
    for x1, y1, x2, y2, px in flushes:
        w = x2 - x1 + 1
        for i, v in enumerate(px):
            fb[(x1 + i % w, y1 + i // w)] = v
    return fb


def f1_draw(rig, fb, x, top, text, shades):
    """Test's own rendering of text in font F1 (object d_0802ce5c) from the font data in the image,
    by the format the vendor font engine reads (font object, font record, ranges type 2 / 3, glyph entry, 2-bpp stream,
    top = line top + line height - base line - box height - y offset). Returns the pen x after it."""
    def rd(a, n):
        return bytes(rig.m.uc.mem_read(a, n))

    def u32(a):
        return struct.unpack('<I', rd(a, 4))[0]
    obj = rig.s['d_0802ce5c']
    lh, base = struct.unpack('<hh', rd(obj + 8, 4))
    rec = u32(obj + 0x10)
    bm, ent, rng = u32(rec), u32(rec + 4), u32(rec + 8)
    nr = struct.unpack('<H', rd(rec + 0x12, 2))[0] & 0x1FF
    for ch in text:
        c, gid = ord(ch), 0
        for k in range(nr):
            r = rng + 20 * k
            first = u32(r)
            ln, gbase = struct.unpack('<HH', rd(r + 4, 4))
            typ = struct.unpack('<H', rd(r + 0x12, 2))[0]
            if 0 <= c - first <= ln:
                if typ == 2:
                    gid = gbase + c - first
                elif typ == 3:
                    cnt = struct.unpack('<H', rd(r + 0x10, 2))[0]
                    codes = struct.unpack('<%dH' % cnt, rd(u32(r + 8), 2 * cnt))
                    gid = gbase + codes.index(c - first) if c - first in codes else 0
                break
        if not gid:
            continue
        e = ent + 8 * gid
        w0 = u32(e)
        bw, bh, ox, oy = struct.unpack('<BBbb', rd(e + 4, 4))
        if bw and bh:
            bits = rd(bm + (w0 & 0xFFFFF), (bw * bh * 2 + 7) // 8)
            y0 = top + lh - base - bh - oy
            for i in range(bw * bh):
                fb[(x + ox + i % bw, y0 + i // bw)] = shades[(bits[i >> 2] >> (6 - 2 * (i & 3))) & 3]
        x += ((w0 >> 20) + 8) >> 4
    return x


XT_WHITE = (0x0000, 0x52AA, 0xA554, 0xFFFF)
XT_RED = (0x0000, 0x5000, 0xA000, 0xF800)
XT_LINES = [(6, XT_RED, 'CRYSTAL FAULT'), (44, XT_WHITE, 'The 8 MHz crystal of the'),
            (63, XT_WHITE, 'microcontroller does not start.'), (82, XT_WHITE, 'Without it the meter cannot'),
            (101, XT_WHITE, 'measure or use USB.'), (139, XT_WHITE, 'Repair: resolder or replace the'),
            (158, XT_WHITE, '8 MHz crystal on pins PD0 and'), (177, XT_WHITE, 'PD1 of the microcontroller.'),
            (215, XT_WHITE, 'Switching off in ')]


@case
def k33_crystal_fault_screen_then_power_off():
    """Fix F4 (crystal failure): HSE never ready (HseFails), started through starter and slot A on
    trial (INSTALL A), so the slot's IWDG runs (hand-over bit 8) through the whole fault screen. The
    model core runs at 8 MHz, one cycle per instruction (as k19). Expected: xtal_fault reached with
    PA8 high; at the power-off (fn_0800b274) the panel shows the nine lines of xtal.s in F1 (this
    test's own rendering, f1_draw) with "1 s" after the last one and black everywhere else; 20
    clears of the 40 x 19 number area; 20 s (+-0.3 s) from the backlight on (fn_08009e60(100)) to
    fn_0800b274; no IWDG reset, also 1 s after it (the loop feeds); PA8 low at the end."""
    rig = Ctl(records=((REC0, cell(1, ST_INSTALL, 1)),), chain=True, usb=False, core_hz=8_000_000,
              devices=(HseFails(),), cpi=1, panel=True)
    m, p = rig.m, rig.m.panel
    marks = {}

    def at(name, cond=None):
        def f(uc, addr, size, user):
            if name not in marks and (cond is None or cond(uc)):
                marks[name] = (m.now(), m.st['pa8'], len(p.flushes))
        return f
    for name, cond in (('xtal_fault', None), ('fn_08009e60', lambda uc: uc.reg_read(UC_ARM_REG_R0) == 100),
                       ('fn_0800b274', None)):
        a = rig.s[name] & ~1
        m.uc.hook_add(UC_HOOK_CODE, at(name, cond), begin=a, end=a)
    end = m.run_for(seconds=120.0, until=lambda mm: 'fn_0800b274' in marks and mm.now() > marks['fn_0800b274'][0] + 1.0)
    check(end is None and 'fn_0800b274' in marks, 'run end %r, marks %r, violations %r' % (end, marks, m.st['viol']))
    check(marks['xtal_fault'][1] == 1, 'PA8 low at xtal_fault')
    kinds = [e['kind'] for e in m.iwdg_log]
    check('start' in kinds and 'reset' not in kinds, 'IWDG log kinds %r' % sorted(set(kinds)))
    want = {}
    x = 16
    for top, shades, text in XT_LINES:
        x = f1_draw(rig, want, 16, top, text, shades)
    f1_draw(rig, want, x, 215, '1 s', XT_WHITE)
    fb = fb_replay(p.flushes[:marks['fn_0800b274'][2]])
    bad = [(xy, fb.get(xy, 0), want.get(xy, 0)) for xy in ((i, j) for j in range(240) for i in range(320))
           if fb.get(xy, 0) != want.get(xy, 0)]
    check(not bad, '%d pixels differ, first %r' % (len(bad), bad[:4]))
    clears = [f for f in p.flushes if f[2] - f[0] == 39 and f[3] - f[1] == 18 and f[1] == 215]
    check(len(clears) == 20, '%d clears of the number area' % len(clears))
    dt = marks['fn_0800b274'][0] - marks['fn_08009e60'][0]
    check(19.7 <= dt <= 20.3, 'backlight on to power-off %.3f s' % dt)
    check(m.st['pa8'] == 0, 'PA8 not low at the end')
    check(not m.st['viol'], 'violations %r' % m.st['viol'])
    NOTES.append('k33: xtal_fault at %.3f s, backlight on at %.3f s, power-off %.3f s later' % (
        marks['xtal_fault'][0], marks['fn_08009e60'][0], dt))
    return True


def logo_compose(rig, pic, rows, table):
    """Test's own composition of the start-up word from the piece table in the image (logo.s format:
    count word, 8 bytes per piece), the brighter pixel staying (R + G / 2 + B). Returns
    {(column, row): colour} for the 244 columns."""
    mem = rig.m.uc
    n = struct.unpack('<I', bytes(mem.mem_read(table, 4)))[0]
    raw = bytes(mem.mem_read(table + 4, 8 * n))
    src = struct.unpack('<%dH' % (160 * rows), bytes(mem.mem_read(pic, 2 * 160 * rows)))

    def lum(c):
        return ((c >> 6) & 31) + (c >> 11) + (c & 31)
    out = {}
    for k in range(n):
        sx, sy, w, h, fl, dx, dy, rep = raw[8 * k:8 * k + 8]
        check(sx + w <= 160 and sy + h <= rows and dy + h <= rows and dx + w * rep <= 244,
              'piece %d %r outside the picture or the word' % (k, raw[8 * k:8 * k + 8]))
        for r in range(rep):
            for i in range(w):
                col = sx + (w - 1 - i if fl & 1 else i)
                for j in range(h):
                    c = src[col * rows + sy + j]
                    xy = (dx + r * w + i, dy + j)
                    if lum(c) > lum(out.get(xy, 0)):
                        out[xy] = c
    return out


@case
def k34_start_up_logo_fu_nirsi():
    """Fix F9 (start-up logo): own_logo (logo.s) draws the white word, the three drops and the blue
    word. Expected (panel model, the windows between own_logo and the GUI set-up fn_08021e98):
    244 one-column windows of 27 rows at x 38.., y 106 with this test's composition of the white
    table, then 244 of 28 rows at y 105 with the blue one; the drops' one-pixel windows (fn_08009ba0)
    between them at x 263..281, y 0..112; the start-up then reaches the main loop."""
    rig = Ctl(panel=True, usb=False)
    m, p = rig.m, rig.m.panel
    marks = {}
    for name in ('own_logo', 'fn_08021e98'):
        def f(uc, addr, size, user, name=name):
            marks.setdefault(name, len(p.flushes))
        a = rig.s[name] & ~1
        m.uc.hook_add(UC_HOOK_CODE, f, begin=a, end=a)
    rig.to_main_loop()
    check('own_logo' in marks and 'fn_08021e98' in marks, 'marks %r' % marks)
    fl = p.flushes[marks['own_logo']:marks['fn_08021e98']]
    cols = [f for f in fl if f[0] == f[2] and f[3] - f[1] + 1 in (27, 28)]
    check(len(cols) == 488, '%d one-column windows' % len(cols))
    for k0, rows, y, pic, table in ((0, 27, 106, 'd_08046c9c', 'logo_white'), (244, 28, 105, 'd_0804499c', 'logo_blue')):
        want = logo_compose(rig, rig.s[pic], rows, rig.s[table])
        for k in range(244):
            x1, y1, x2, y2, px = cols[k0 + k]
            check(x1 == 38 + k and y1 == y and y2 == y + rows - 1, '%s column %d: window %r' % (table, k, (x1, y1, x2, y2)))
            exp = [want.get((k, j), 0) for j in range(rows)]
            check(px == exp, '%s column %d: %r, expected %r' % (table, k, px, exp))
    first_blue = next(i for i, f in enumerate(fl) if f is cols[244])
    drops = [f for f in fl[:first_blue] if f[0] == f[2] and f[1] == f[3]]
    xs, ys = sorted({f[0] for f in drops}), sorted({f[1] for f in drops})
    check(drops and xs[0] == 263 and xs[-1] == 281 and ys[0] == 0 and ys[-1] == 112,
          'drop pixels x %r..%r, y %r..%r' % (xs[:1], xs[-1:], ys[:1], ys[-1:]))
    check(not m.st['viol'], 'violations %r' % m.st['viol'])
    return True


@case
def k35_setting_events_of_the_block_compare():
    """ev_detect compares the 0xC14-byte block 4 words at a time and falls back to the per-word
    compare for a group with a change (ctl.s). Words changed between two passes (the rig stopped):
    offset 0 (the first word), 4 / 8 / 0xC and 0xB40 (calibration tables 0x04..0xB43: one
    ID_CAL_TABLES event with the number 4), 0xB44 (the first word after them), 0xC00 / 0xC04 (two
    in one group), 0xC10 (the last word, the 773rd, outside every group of 4). Expected: one
    SETTING_CHANGED per non-table word with its new value, in the order of the offsets, and the
    ID_CAL_TABLES event with 4; the same again when the words are put back. The words are written with
    the rig stopped at the main loop's bl ctl_loop (0x080281D0, meter_model stop_req: the slice ends at
    the next block), so ev_detect sees all of them in one pass: a stop anywhere else can fall inside its
    block compare (2026-11-22, after the measurement core changed the instruction stream: 1 + 3 table
    words in two passes)."""
    rig = Ctl().up()
    words = (0x000, 0x004, 0x008, 0x00C, 0xB40, 0xB44, 0xC00, 0xC04, 0xC10)
    single = [o for o in words if not 0x04 <= o < 0xB44]
    rig.run(0.2)
    rig.drain(0.05)
    at = dict(arm=False, hit=False)

    def loop_call(uc, a, size, u):
        if at['arm']:
            at['hit'] = True
            rig.m.tm['stop_req'] = True
    rig.m.uc.hook_add(UC_HOOK_CODE, loop_call, begin=0x080281D0, end=0x080281D0)
    old = {o: rig.rd(V_BLOCK + o) for o in words}
    for step, vals in (('changed', {o: old[o] ^ 0x00010000 for o in words}), ('put back', old)):
        at.update(arm=True, hit=False)
        end = rig.m.run_for(seconds=2.0, until=lambda m: at['hit'])
        at['arm'] = False
        check(end is None and at['hit'], '%s: main loop not reached (%r)' % (step, end))
        for o, v in vals.items():
            rig.wr(V_BLOCK + o, v)
        ev = [f for f in rig.drain(0.3) if f['type'] == FR_EVENT and f['cmd'] == E_SETTING]
        got = [struct.unpack_from('<HI', f['payload']) for f in ev]
        mine = [g for g in got if g[0] in single or g[0] == 0xFFFE]
        want = [(o, vals[o]) for o in single] + [(0xFFFE, 4)]
        check(mine == want, '%s: events %r, expected %r' % (step, [(hex(a), hex(b)) for a, b in mine],
                                                             [(hex(a), hex(b)) for a, b in want]))
    check(not rig.m.st['viol'], 'violations %r' % rig.m.st['viol'])
    return True


# ---------------------------------------------------------------- revision 17 (safe clock start-up, start-up diagnostics)

def strict_rcc(m):
    """meter_model's opt-in RCC rules (module docstring): SCLKSTS follows SCLKSW only after 3 reads of
    RCC_CFG; PLLEN / HSEEN cleared while SCLKSTS reads PLL, or the PLL bits changed while PLLEN is 1:
    a violation."""
    m.rcc_strict = True
    m.rcc_switch_reads = 3


def prog(rig):
    return rig.rd(BOOT_PROG)


@case
def k36_clock_switch_order_strict_model():
    """17.1: (a) a start through starter and slot with strict_rcc: the slot leaves the PLL as the system
    clock (bootloader/src/board_02.s fn_080020c4), own_reset switches to the HSI alone and waits for
    SCLKSTS, so fn_0800c274 clears PLLEN only on the HSI: the main loop is reached without a violation,
    the progress word holds stage 14 and no clock flag, the core runs on the PLL again (SCLKSW and the
    model's SCLKSTS 2). (b) RESET from the main loop (the PLL runs): check_restart, no violation, the
    restarted start's BOOT_PREV is the first start's word. (c) Control, the V1.1 order: fn_0800c274
    called directly while the PLL drives the core is a violation (PLLEN cleared before the switch)."""
    rig = Ctl(chain=True, patch=strict_rcc).up()
    m = rig.m
    check(not m.st['viol'], 'start: violations %r' % m.st['viol'])
    check(prog(rig) == BOOT_TAG << 16 | STG_LOOP, 'start: progress word 0x%08X' % prog(rig))
    check(m.st['regs'].get(RCC_CFG, 0) & 3 == 2 and m.st['sws'] == 2, 'start: not on the PLL (SW %d, SWS %d)'
          % (m.st['regs'].get(RCC_CFG, 0) & 3, m.st['sws']))
    first = prog(rig)
    hits = watch_restart(rig)
    check(rig.ask('RESET')[0] == S_OK, 'RESET status')
    check_restart(rig, hits, REQ_RESTART, 'RESET with strict RCC rules')
    rig.run(0.2)
    check(not m.st['viol'], 'RESET: violations %r' % m.st['viol'])
    check(rig.rd(BOOT_PREV) == first and prog(rig) == BOOT_TAG << 16 | STG_LOOP,
          'RESET: BOOT_PREV 0x%08X, progress word 0x%08X' % (rig.rd(BOOT_PREV), prog(rig)))
    r = m.call(rig.s['fn_0800c274'])
    check(r is None and m.st['end'] == 'violation' and any('clears PLLEN' in v for v in m.st['viol']),
          'control: fn_0800c274 with the PLL running: end %r, violations %r' % (m.st['end'], m.st['viol']))
    return True


@case
def k37_hsi_switch_bound():
    """17.1: SCLKSTS stuck at PLL (sws_stuck 2) from the reset vector: own_reset's 0x8000 polls run out,
    flag CLKF_HSI; fn_0800c274 is not called, own_reset makes its CPACR and VTOR stores; the start goes
    on (SCLKSTS reads PLL, so no fault screen) to the main loop and INFO reports the flag. The start goes
    through starter and slot (as on the meter): the slot leaves the PLL as the system clock (k36), which
    the timeout path keeps; a start at the application's reset vector without the slot leaves RCC_CTRL at
    its reset value 0x1 (PLL off), where USBEN is a model violation (Run of 2026-11-24). SCLKSTS sticks
    from the entry of own_reset on, so the case tests the application's bound alone: stuck from power-on,
    slot version 2's own HSI wait (bootloader/src/board_02.s .Lslot_hsi, unbounded there) never ended
    (Run of 2026-11-24: PC in slot A, no application event); slot version 3 bounds it (test_chain c23)."""
    rig = Ctl(chain=True)
    m = rig.m

    def stick(uc, a, size, u):
        m.sws_stuck = 2
    m.uc.hook_add(UC_HOOK_CODE, stick, begin=rig.s['own_reset'] & ~1, end=rig.s['own_reset'] & ~1)
    m.watch(rig.s['fn_0800c274'], 'fn_0800c274')
    m.watch(rig.s['xtal_fault'], 'xtal_fault')
    rig.up()
    check('fn_0800c274' not in m.events() and 'xtal_fault' not in m.events(), 'events %r' % m.events())
    check(prog(rig) == BOOT_TAG << 16 | CLKF_HSI << 8 | STG_LOOP, 'progress word 0x%08X' % prog(rig))
    check(m.scs.get(0xE000ED08) == APP and m.scs.get(0xE000ED88, 0) & 0xF00000 == 0xF00000,
          'VTOR 0x%08X, CPACR 0x%08X' % (m.scs.get(0xE000ED08, 0), m.scs.get(0xE000ED88, 0)))
    d = rig.ask_ok('INFO', size=INFO_SIZE)
    check(struct.unpack_from('<I', d, 50)[0] == prog(rig), 'INFO progress word 0x%08X'
          % struct.unpack_from('<I', d, 50)[0])
    check(not m.st['viol'], 'violations %r' % m.st['viol'])
    return True


def clock_fault_rig(patch):
    """k19's rig (8 MHz core, 1 cycle per instruction, no USB) with a meter_model RCC rule; the run stops
    at xtal_fault (own_start's fault path)."""
    rig = Ctl(core_hz=8_000_000, usb=False, cpi=1, patch=patch)
    rig.m.watch(0x0800BAF8, 'hse fallback')
    rig.m.watch(rig.s['xtal_fault'], 'xtal_fault', stop=True)
    end = rig.m.run_for(3.0)
    check(end == 'at xtal_fault', 'end %r (events %r, violations %r)' % (end, rig.m.events(), rig.m.st['viol']))
    check('hse fallback' in rig.m.events(), 'the exit 0x0800BAF8 not taken: %r' % rig.m.events())
    pa8 = [e[1] for e in rig.m.st['log'] if e[0] == 'pa8']
    check(pa8 and 0 not in pa8, 'PA8 levels %r (own_pa8_level latches on the HSI)' % pa8)
    return rig


@case
def k38_pll_lock_bound():
    """17.1: the PLL never locks (pll_locks False): own_pll_wait's 0x8000 polls run out, PLLEN is cleared,
    flag CLKF_PLL, fn_0800ba4c leaves by 0x0800BAF8, SCLKSW stays HSI, and own_start ends in xtal_fault
    (stage 4: own_start entered)."""
    def nolock(m):
        m.pll_locks = False
    rig = clock_fault_rig(nolock)
    regs = rig.m.st['regs']
    check(prog(rig) == BOOT_TAG << 16 | CLKF_PLL << 8 | STG_START, 'progress word 0x%08X' % prog(rig))
    check(not regs.get(RCC_CTRL, 0) & PLLEN and regs.get(RCC_CFG, 0) & 3 == 0,
          'RCC_CTRL 0x%08X RCC_CFG 0x%08X' % (regs.get(RCC_CTRL, 0), regs.get(RCC_CFG, 0)))
    check(regs.get(RCC_CFG, 0) & APB_PRES == 0, 'APB prescalers left set: RCC_CFG 0x%08X' % regs.get(RCC_CFG, 0))
    return True


@case
def k39_pll_switch_bound():
    """17.1: SCLKSTS stuck at HSI (sws_stuck 0): own_reset's wait ends at once, the PLL locks, SCLKSW = PLL,
    own_sw_wait's 0x8000 polls run out: SCLKSW = HSI again, flag CLKF_SW, the exit 0x0800BAF8, and
    own_start ends in xtal_fault; the PLL stays enabled."""
    def hsi(m):
        m.sws_stuck = 0
    rig = clock_fault_rig(hsi)
    regs = rig.m.st['regs']
    check(prog(rig) == BOOT_TAG << 16 | CLKF_SW << 8 | STG_START, 'progress word 0x%08X' % prog(rig))
    check(regs.get(RCC_CTRL, 0) & PLLEN and regs.get(RCC_CFG, 0) & 3 == 0,
          'RCC_CTRL 0x%08X RCC_CFG 0x%08X' % (regs.get(RCC_CTRL, 0), regs.get(RCC_CFG, 0)))
    check(regs.get(RCC_CFG, 0) & APB_PRES == 0, 'APB prescalers left set: RCC_CFG 0x%08X' % regs.get(RCC_CFG, 0))
    return True


HANG_AFTER_IWDG = 0x080281BE      # the adr of "loop\n" after bl fn_08010178 at 0x080281BA (V1.1 address,
                                  # the port keeps it: link_own.ld)


@case
def k40_progress_word_and_reset_flags_over_an_iwdg_reset():
    """17.2: first start from power-on with `b .` at 0x080281BE (after the IWDG start fn_08010178): the
    IWDG resets the chip (end 'iwdg'); the SRAM it leaves holds BOOT_PREV 0 (power-on) and BOOT_PROG at
    stage 12 (0x20001140 is 1 in the test block: fn_0800ca2c, then fn_08008120, fn_08010178). Second
    start with that SRAM and the original code: every stage store of a normal start in order (a write
    hook on BOOT_PROG: the whole word with stage 1, then bytes 2, 3, 4, 5, 6..11, 12, 14), INFO
    reports the previous start's word (stage 12), this start's (stage 14) and RCC_CTRLSTS with IWDGRSTF
    and without PORRSTF (cleared by the first start's own_start), and the flags are cleared again."""
    orig = None

    def hang(m):
        nonlocal orig
        orig = m.get(HANG_AFTER_IWDG, 2)
        m.put(HANG_AFTER_IWDG, b'\xfe\xe7')
    rig = Ctl(usb=False, patch=hang)
    m = rig.m
    end = m.run_for(3.0)
    check(end == 'iwdg', 'hanging start: end %r' % end)
    ram = lambda a: struct.unpack_from('<I', m.ram, a - 0x20000000)[0]
    check(ram(BOOT_PREV) == 0 and ram(BOOT_PROG) == BOOT_TAG << 16 | STG_CA2C,
          'hanging start: BOOT_PREV 0x%08X BOOT_PROG 0x%08X' % (ram(BOOT_PREV), ram(BOOT_PROG)))
    check(m.ctrlsts & IWDGRSTF and not m.ctrlsts & PORRSTF, 'RCC_CTRLSTS 0x%08X after the IWDG reset' % m.ctrlsts)
    m.put(HANG_AFTER_IWDG, orig)
    rig.start(keep_ram=True)
    seen = []

    def wr(uc, access, addr, size, value, user):
        seen.append((addr, size, value))
    m.uc.hook_add(UC_HOOK_MEM_WRITE, wr, begin=BOOT_PREV, end=BOOT_PROG + 3)
    rig.usb = True
    rig.up()
    want = [(BOOT_PREV, 4, BOOT_TAG << 16 | STG_CA2C), (BOOT_PROG, 4, BOOT_TAG << 16 | STG_RESET)] + \
        [(BOOT_PROG, 1, s) for s in (STG_CLOCK, STG_GPIO, STG_START, STG_LOAD) + tuple(range(6, 12)) + (STG_CA2C, STG_LOOP)]
    check(seen == want, 'progress stores %r, expected %r' % (seen, want))
    d = rig.ask_ok('INFO', size=INFO_SIZE)
    prev, cur, rst = struct.unpack_from('<III', d, 46)
    check(prev == BOOT_TAG << 16 | STG_CA2C and cur == BOOT_TAG << 16 | STG_LOOP,
          'INFO progress 0x%08X / 0x%08X' % (prev, cur))
    check(rst & IWDGRSTF and not rst & PORRSTF and rig.rd(OWN_CTL + CT_RSTF) == rst,
          'INFO reset flags 0x%08X (CT_RSTF 0x%08X)' % (rst, rig.rd(OWN_CTL + CT_RSTF)))
    check(m.ctrlsts & RST_FLAGS == 0, 'flags not cleared: 0x%08X' % m.ctrlsts)
    check(not m.st['viol'], 'violations %r' % m.st['viol'])
    return True


@case
def k41_update_result_kept_until_info():
    """17.3: the result word RES_OK at the first start: own_start keeps it (the start reaches the main
    loop, no INFO is read); the chip restarts with that SRAM (meter_model halt, a reset that keeps it):
    INFO reports result 1 and the word is 0 afterwards; the next start reports 0."""
    rig = Ctl(ram={RESULT_WORD: RESULT_OK}, usb=False)
    rig.to_main_loop()
    check(rig.rd(RESULT_WORD) == RESULT_OK and rig.rd(OWN_CTL + CT_RESULT) == 1,
          'first start: word 0x%08X, CT_RESULT %d' % (rig.rd(RESULT_WORD), rig.rd(OWN_CTL + CT_RESULT)))
    rig.m.halt()
    rig.start(keep_ram=True)
    rig.usb = True
    rig.up()
    check(rig.rd(RESULT_WORD) == RESULT_OK, 'second start, before INFO: word 0x%08X' % rig.rd(RESULT_WORD))
    d = rig.ask_ok('INFO', size=INFO_SIZE)
    check(struct.unpack_from('<I', d, 42)[0] == 1 and rig.rd(RESULT_WORD) == 0,
          'second start: result %d, word 0x%08X' % (struct.unpack_from('<I', d, 42)[0], rig.rd(RESULT_WORD)))
    d = rig.ask_ok('INFO', size=INFO_SIZE)
    check(struct.unpack_from('<I', d, 42)[0] == 1, 'second INFO of the same start: result %d'
          % struct.unpack_from('<I', d, 42)[0])
    rig.m.halt()
    rig.start(keep_ram=True)
    rig.up()
    d = rig.ask_ok('INFO', size=INFO_SIZE)
    check(struct.unpack_from('<I', d, 42)[0] == 0, 'third start: result %d' % struct.unpack_from('<I', d, 42)[0])
    return True


def key_step_quiet_exit(rig):
    """Address of the `cpsie i` of key_step's empty-slot exit (ctl.s .Lk_quiet): the second cpsie i
    (0xB662) after key_step's entry (the first is the direct-change path before ds_run, the third the
    event path), each read from the image."""
    a = rig.s['key_step'] & ~1
    end = min(v & ~1 for k, v in rig.s.items() if isinstance(v, int) and (v & ~1) > a)
    hits = [x for x in range(a, end, 2) if rig.m.word(x) & 0xFFFF == 0xB662]
    check(len(hits) == 3, 'key_step: %d cpsie i, expected 3' % len(hits))
    return hits[1]


@case
def k42_press_after_the_read_of_an_empty_slot():
    """17.4 (a): a press (code 1, the secondary key 0x0040, physical) is stored into the slot right after
    key_step read it empty with PRIMASK set (a code hook at the empty-slot exit writes it, as the
    SysTick scan would): fn_08009400 is not called in that pass; the next pass reads it, sends KEY
    (mask 0x0040, code 1, source 0) and dispatches it: the secondary 0x200011E8 steps by one and stays
    (MF_SECPICK at the dispatch, own_sec_key), and the slot is empty afterwards."""
    rig = Ctl().up()
    m = rig.m
    rig.run(0.3)
    rig.drain(0.05)
    st = dict(arm=False, pass_=0, at=None, calls=[])

    def ks(uc, a, size, u):
        st['pass_'] += 1

    def quiet(uc, a, size, u):
        if st['arm']:
            st['arm'] = False
            st['at'] = st['pass_']
            uc.mem_write(V_KEY_CODE, struct.pack('<HH', 1, 0x0040))

    def disp(uc, a, size, u):
        st['calls'].append((st['pass_'], struct.unpack('<HH', bytes(uc.mem_read(V_KEY_CODE, 4)))))
    m.uc.hook_add(UC_HOOK_CODE, ks, begin=rig.s['key_step'] & ~1, end=rig.s['key_step'] & ~1)
    q = key_step_quiet_exit(rig)
    m.uc.hook_add(UC_HOOK_CODE, quiet, begin=q, end=q)
    m.uc.hook_add(UC_HOOK_CODE, disp, begin=rig.s['fn_08009400'] & ~1, end=rig.s['fn_08009400'] & ~1)
    sec0 = rig.rd(V_SECONDARY)
    st['arm'] = True
    end = m.run_for(seconds=1.0, until=lambda mm: st['calls'])
    check(end is None and st['at'] is not None and st['calls'], 'no dispatch: end %r, %r' % (end, st))
    check(st['calls'][0] == (st['at'] + 1, (1, 0x0040)), 'dispatch %r, the press stored in pass %r'
          % (st['calls'][0], st['at']))
    rig.run(0.5)
    keys = [f['payload'] for f in rig.drain(0.1) if f['type'] == FR_EVENT and f['cmd'] == E_KEY]
    check(struct.pack('<HBB', 0x0040, 1, 0) in keys, 'KEY events %r' % [k.hex() for k in keys])
    check(rig.rd(V_SECONDARY) == (sec0 + 1) % 5 and rig.rd16(V_KEY_CODE) == 0,
          'secondary %d -> %d, slot code %d' % (sec0, rig.rd(V_SECONDARY), rig.rd16(V_KEY_CODE)))
    check(rig.rd(MF_SECPICK) == 0, 'MF_SECPICK left at %d' % rig.rd(MF_SECPICK))
    check(not m.st['viol'], 'violations %r' % m.st['viol'])
    return True


@case
def k43_secondary_mark_follows_the_dispatched_event():
    """17.4: MF_SECPICK is 1 only inside the dispatch of the secondary key by fn_08009614 (own_sec_key at
    0x080097B8), as fn_08009614 read the slot, not as key_step read it. On screen 1 in AUTO (Func 0),
    three presses written into the slot between two passes, the second and third replaced at the entry
    of fn_08009400 (a code hook, as the scan could store a new event in that window):
    (1) 0x0040 dispatched as read: own_sec_key once, own_auto_class sees MF_SECPICK 1 during the
        dispatch, the secondary steps by one;
    (2) key_step reads 0x0040, fn_08009400 gets 0x0008: own_sec_key not reached, MF_SECPICK 0 at every
        own_auto_class call, the secondary unchanged;
    (3) key_step reads 0x0008, fn_08009400 gets 0x0040: own_sec_key once, MF_SECPICK 1 during it, the
        secondary steps by one.
    Outside the dispatches every own_auto_class call (the publishes, meas_tail) sees MF_SECPICK 0.
    The other key is mask 8 because fn_08009614 returns at once for code 1 with it (app_01.s 389,
    0x08009670 cmp r0, #8). Mask 2 is no neutral key: fn_0800d940(1) changes the setting under the
    cursor (app_01.s 415-420), AUTO restarts and stores its class's own secondary (Run of 2026-11-24:
    secondary 0 -> 4)."""
    blk = block_with(**{'0x20001148': 0})
    rig = Ctl(a=copy_image(blk, 2), b=copy_image(blk, 1)).up()
    m = rig.m
    rig.run(0.5)
    check(rig.rd(V_SCREEN) == 1 and rig.rd(V_FUNC) == 0, 'screen %d Func %d' % (rig.rd(V_SCREEN), rig.rd(V_FUNC)))
    st = dict(inside=False, replace=None, sec=0, auto=[], ret=None)

    def enter(uc, a, size, u):
        st['inside'] = True
        st['ret'] = uc.reg_read(UC_ARM_REG_LR) & ~1
        if st['replace'] is not None:
            uc.mem_write(V_KEY_CODE, struct.pack('<HH', 1, st['replace']))
            st['replace'] = None

    def leave(uc, a, size, u):
        if st['inside'] and a == st['ret']:
            st['inside'] = False

    def auto(uc, a, size, u):
        st['auto'].append((st['inside'], struct.unpack('<I', bytes(uc.mem_read(MF_SECPICK, 4)))[0]))

    def sec(uc, a, size, u):
        st['sec'] += 1
    m.uc.hook_add(UC_HOOK_CODE, enter, begin=rig.s['fn_08009400'] & ~1, end=rig.s['fn_08009400'] & ~1)
    ks = rig.s['key_step'] & ~1
    m.uc.hook_add(UC_HOOK_CODE, leave, begin=ks, end=ks + 0x200)
    m.uc.hook_add(UC_HOOK_CODE, auto, begin=rig.s['own_auto_class'] & ~1, end=rig.s['own_auto_class'] & ~1)
    m.uc.hook_add(UC_HOOK_CODE, sec, begin=rig.s['own_sec_key'] & ~1, end=rig.s['own_sec_key'] & ~1)
    for n, (read, sent, steps) in enumerate(((0x0040, None, 1), (0x0040, 0x0008, 0), (0x0008, 0x0040, 1)), 1):
        sec0, st['sec'], st['auto'] = rig.rd(V_SECONDARY), 0, []
        st['replace'] = sent
        rig.wr(V_KEY_CODE, struct.pack('<HH', 1, read))
        end = m.run_for(seconds=1.0, until=lambda mm: rig.rd16(V_KEY_CODE) == 0 and not st['inside'])
        check(end is None, 'press %d: end %r' % (n, end))
        rig.run(0.6)
        inside = [v for i, v in st['auto'] if i]
        outside = [v for i, v in st['auto'] if not i]
        check(st['sec'] == steps, 'press %d: own_sec_key reached %d times' % (n, st['sec']))
        check(all(v == steps for v in inside) and (inside or not steps),
              'press %d: MF_SECPICK in the dispatch %r' % (n, inside))
        check(not any(outside), 'press %d: MF_SECPICK outside the dispatch %r' % (n, outside))
        check(rig.rd(V_SECONDARY) == (sec0 + steps) % 5, 'press %d: secondary %d -> %d'
              % (n, sec0, rig.rd(V_SECONDARY)))
        check(rig.rd(MF_SECPICK) == 0, 'press %d: MF_SECPICK left at %d' % (n, rig.rd(MF_SECPICK)))
    check(not m.st['viol'], 'violations %r' % m.st['viol'])
    return True


@case
def k44_power_off_note_follows_the_dispatched_event():
    """17.4: the power-off note (CF_OFF_WAIT, CT_OFF_T) is set by own_off_save (ctl.s; the bl at 0x08009474),
    which is reached only when fn_08009400 itself read code 0xFE (0x08009404), mask 1 (0x08009452) and the
    busy halfword 0x20001190 = 0 (0x08009468), not from the event key_step read. On screen 1, two events
    written into the slot between two passes, each replaced at the entry of fn_08009400 (a code hook, as
    the scan could store a new event in that window; k43's rig pattern):
    (1) key_step reads 0xFE mask 1 (the power key held), fn_08009400 gets code 1 mask 8 (fn_08009614
        returns at once for it, app_01.s 0x08009670, k43): own_off_save not reached, CT_OFF_T not written,
        CF_OFF_WAIT clear; 1.2 s later (OFF_WAIT_MS 1000, off_step) no powered-off mode, PA8 not low;
    (2) key_step reads code 1 mask 8, fn_08009400 gets 0xFE mask 1 (0x20001190 still 0): own_off_save
        once, CT_OFF_T written once with the tick of that moment (ctl.s now: the word V_TICK; 10 less
        when a SysTick came between the load and the store), CF_OFF_WAIT
        set when key_step returns; the vendor path then drives PA8 low (fn_0800b274), and off_step enters
        the powered-off mode 1 s after the note (CF_OFF set, CF_OFF_WAIT cleared, ctl.s off_step)."""
    rig = Ctl().up()
    m = rig.m
    rig.run(0.5)
    check(rig.rd(V_SCREEN) == 1 and rig.rd16(V_KEY_BUSY) == 0 and not rig.rd(OWN_CTL + CT_FLAGS) & (CF_OFF_WAIT | CF_OFF),
          'start: screen %d, busy %d, flags 0x%X' % (rig.rd(V_SCREEN), rig.rd16(V_KEY_BUSY), rig.rd(OWN_CTL + CT_FLAGS)))
    st = dict(inside=False, replace=None, ret=None, off=0, offt=[])

    def enter(uc, a, size, u):
        st['inside'] = True
        st['ret'] = uc.reg_read(UC_ARM_REG_LR) & ~1
        if st['replace'] is not None:
            uc.mem_write(V_KEY_CODE, struct.pack('<HH', *st['replace']))
            st['replace'] = None

    def leave(uc, a, size, u):
        if st['inside'] and a == st['ret']:
            st['inside'] = False

    def off(uc, a, size, u):
        st['off'] += 1

    def offt(uc, access, addr, size, value, user):
        st['offt'].append((value, struct.unpack('<I', bytes(uc.mem_read(V_TICK, 4)))[0]))
    m.uc.hook_add(UC_HOOK_CODE, enter, begin=rig.s['fn_08009400'] & ~1, end=rig.s['fn_08009400'] & ~1)
    ks = rig.s['key_step'] & ~1
    m.uc.hook_add(UC_HOOK_CODE, leave, begin=ks, end=ks + 0x200)
    m.uc.hook_add(UC_HOOK_CODE, off, begin=rig.s['own_off_save'] & ~1, end=rig.s['own_off_save'] & ~1)
    m.uc.hook_add(UC_HOOK_MEM_WRITE, offt, begin=OWN_CTL + CT_OFF_T, end=OWN_CTL + CT_OFF_T + 3)

    def press(read, sent):
        st['replace'] = sent
        rig.wr(V_KEY_CODE, struct.pack('<HH', *read))
        end = m.run_for(seconds=2.0, until=lambda mm: rig.rd16(V_KEY_CODE) == 0 and not st['inside']
                        and st['replace'] is None)
        check(end is None, 'press %r -> %r: end %r' % (read, sent, end))

    press((0xFE, KEY_POWER), (1, 0x0008))                         # (1)
    check(st['off'] == 0 and not st['offt'] and not rig.rd(OWN_CTL + CT_FLAGS) & CF_OFF_WAIT,
          '(1): own_off_save %d, CT_OFF_T writes %r, flags 0x%X' % (st['off'], st['offt'], rig.rd(OWN_CTL + CT_FLAGS)))
    rig.run(1.2)
    check(not rig.rd(OWN_CTL + CT_FLAGS) & (CF_OFF | CF_OFF_WAIT) and m.st['pa8'] != 0,
          '(1): flags 0x%X, PA8 %r' % (rig.rd(OWN_CTL + CT_FLAGS), m.st['pa8']))
    check(rig.rd16(V_KEY_BUSY) == 0, '(1): busy halfword %d' % rig.rd16(V_KEY_BUSY))
    press((1, 0x0008), (0xFE, KEY_POWER))                         # (2)
    # the tick when CT_OFF_T is stored: the value now read, or 10 more when a SysTick (+10, ctl.inc V_TICK)
    # came between now's load and the store
    check(st['off'] == 1 and len(st['offt']) == 1 and st['offt'][0][1] - st['offt'][0][0] in (0, 10)
          and rig.rd(OWN_CTL + CT_OFF_T) == st['offt'][0][0] and rig.rd(OWN_CTL + CT_FLAGS) & CF_OFF_WAIT,
          '(2): own_off_save %d, CT_OFF_T writes (value, tick) %r, flags 0x%X'
          % (st['off'], st['offt'], rig.rd(OWN_CTL + CT_FLAGS)))
    check(m.st['pa8'] == 0, '(2): PA8 %r after the power-off path' % m.st['pa8'])
    rig.run(1.2)
    fl = rig.rd(OWN_CTL + CT_FLAGS)
    check(fl & CF_OFF and not fl & CF_OFF_WAIT and st['off'] == 1 and len(st['offt']) == 1,
          '(2) 1.2 s later: flags 0x%X, own_off_save %d, CT_OFF_T writes %r' % (fl, st['off'], st['offt']))
    check(not m.st['viol'], 'violations %r' % m.st['viol'])
    return True


PLL_LOCK_READS = 1000            # below CLK_POLLS 0x8000 (own.inc)


@case
def k45_pll_locks_after_polls_below_the_bound():
    """17.1: pll_lock_reads 1000 (meter_model: PLLRDF reads 0 for the first 1000 reads of RCC_CTRL after
    PLLEN is set): own_pll_wait polls on and the PLL locks below its bound: no clock flag, the HSE-failure
    exit 0x0800BAF8 and xtal_fault not reached, the main loop reached on the PLL with the prescalers of
    fn_0800ba4c (APB2 / 2, APB1 / 4). A code hook on own_pll_wait's loop head .Lpw_poll (own_pll_wait + 4,
    after the 4-byte mov.w r2, #0x8000; checked: the halfword there is 0x6801, ldr r1, [r0]) counts its
    polls: fn_0800ba4c sets PLLEN and calls own_pll_wait with no read of RCC_CTRL between (system_40.s),
    so reads 1..1000 give 0 and read 1001 gives the lock: 1001 polls, 1000 of them reached by the
    back-edge `bne .Lpw_poll`, and own_pll_wait entered once (the start at the reset vector: the slot's
    own PLL wait does not run)."""
    def slow(mm):
        mm.pll_lock_reads = PLL_LOCK_READS
    rig = Ctl(usb=False, patch=slow)
    m = rig.m
    pw = rig.s['own_pll_wait'] & ~1
    check(m.get(pw + 4, 2) == b'\x01\x68', 'own_pll_wait + 4: %s, expected ldr r1, [r0]' % m.get(pw + 4, 2).hex())
    st = dict(entry=0, polls=0)

    def entry(uc, a, size, u):
        st['entry'] += 1

    def poll(uc, a, size, u):
        st['polls'] += 1
    m.uc.hook_add(UC_HOOK_CODE, entry, begin=pw, end=pw)
    m.uc.hook_add(UC_HOOK_CODE, poll, begin=pw + 4, end=pw + 4)
    m.watch(0x0800BAF8, 'hse fallback')
    m.watch(rig.s['xtal_fault'], 'xtal_fault')
    rig.to_main_loop()
    check('hse fallback' not in m.events() and 'xtal_fault' not in m.events(), 'events %r' % m.events())
    check(prog(rig) == BOOT_TAG << 16 | STG_LOOP, 'progress word 0x%08X' % prog(rig))
    check(st['entry'] == 1 and st['polls'] == PLL_LOCK_READS + 1,
          'own_pll_wait entered %d times, %d polls (back-edges %d), expected 1 / %d'
          % (st['entry'], st['polls'], st['polls'] - st['entry'], PLL_LOCK_READS + 1))
    regs = m.st['regs']
    check(regs.get(RCC_CTRL, 0) & PLLEN and regs.get(RCC_CFG, 0) & 3 == 2
          and regs.get(RCC_CFG, 0) & APB_PRES == 0x2500,
          'RCC_CTRL 0x%08X RCC_CFG 0x%08X' % (regs.get(RCC_CTRL, 0), regs.get(RCC_CFG, 0)))
    check(not m.st['viol'], 'violations %r' % m.st['viol'])
    return True


# ---------------------------------------------------------------- settings recovery over USB (k46..k50)

# own.inc 390..397 (SF_*), 416..418 (COPY_*), 794 (SVO_LOADED 0x0C)
SF_DIFFERS, SF_A_ONLY, SF_A_DAMAGED = 0x02, 0x10, 0x20
COPY_A, COPY_B = 1, 2
SAVE_LOADED = OWN_SAVE + 0x0C
REC_USR0 = 0x20000B20            # block offset 0x5A4: the first word of the user table (inside 0x04..0xB43)
U_0125, U_025 = 0x3E000000, 0x3E800000   # float32 0.125 and 0.25 (IEEE 754 bits)
MARKER_BYTES = struct.pack('<I', 0x12345678)  # own.inc BLK_MARKER, block offsets 0 and 0xC10


def recovery_blocks():
    """Two blocks that differ only in the user table word 0x20000B20 (block offset 0x5A4, inside the
    calibration tables 0x04..0xB43 that own_load compares, save.s 1107..1121): A 0.125, B 0.25; the
    first-start flag and the language word 1 in both (save.s stage_seal 820 sets them to 1 in every
    copy written, so the copy written equals its source block byte for byte)."""
    blk_a = block_with(lang_set=1, **{'0x2000115c': 1, '0x20000b20': U_0125})
    blk_b = block_with(lang_set=1, **{'0x2000115c': 1, '0x20000b20': U_025})
    check(blk_a[0x04:0xB44] != blk_b[0x04:0xB44] and blk_a[:0x5A4] == blk_b[:0x5A4]
          and blk_a[0x5A8:] == blk_b[0x5A8:], 'recovery blocks: not one differing calibration word')
    return blk_a, blk_b


def recovery_rig(a, b, flags, loaded):
    """Ctl with copies a / b; checks the load state the case needs (own_load, save.s 1087..1186) and
    that the start wrote no flash (both copies still the images given); then the frames so far
    dropped and the operation log cleared."""
    rig = Ctl(a=a, b=b).up()
    check(rig.rd(SAVE_FLAGS) == flags and rig.rd(SAVE_LOADED) == loaded,
          'after the load: flags 0x%X loaded %d, expected 0x%X / %d'
          % (rig.rd(SAVE_FLAGS), rig.rd(SAVE_LOADED), flags, loaded))
    check(rig.m.get(SET_A, 0x1000) == a and rig.m.get(SET_B, 0x1000) == b, 'the start changed a copy')
    rig.drain(0.3)
    del rig.host.frames[:]
    del rig.m.st['log'][:]
    return rig


def recovery_ops(rig, hits, target, other, what):
    """The flash operations of the command (those before the restart's starter entry, if any): the two
    pages of target erased once each (write_copy, save.s 855..957: (b) erases both pages, one attempt
    when nothing fails), every word programmed inside target (trailer sequence, the 0x305 block words,
    the CRC word: 775), none in other."""
    end = hits['starter'][0]['log'] if hits['starter'] else len(rig.m.st['log'])
    ops = [x for x in rig.m.st['log'][:end] if x[0] in ('word', 'erase')]
    er = [x[1] for x in ops if x[0] == 'erase']
    wd = [x[1] for x in ops if x[0] == 'word']
    check(er == [target, target + PAGE], '%s: erases %r, expected the two pages of 0x%08X'
          % (what, ['0x%08X' % e for e in er], target))
    check(len(wd) == 2 + BLK // 4 and all(target <= w < target + 0x1000 for w in wd),
          '%s: %d words, outside 0x%08X: %r' % (what, len(wd), target,
                                                ['0x%08X' % w for w in wd if not target <= w < target + 0x1000][:4]))
    check(not [x for x in ops if other <= x[1] < other + 0x1000], '%s: copy 0x%08X touched' % (what, other))


def save_events(rig, seconds):
    """SAVE_RESULT (0x96) payloads among the frames read during the request and the next seconds."""
    fr = list(rig.host.frames) + rig.drain(seconds)
    return [f['payload'] for f in fr if f['type'] == FR_EVENT and f['cmd'] == E_SAVE]


@case
def k46_restore_b_with_a_loaded_then_restart():
    """SETTINGS_RESTORE_B (0x55) allowed: input A = blk_a seq 8, B = blk_b seq 7 (recovery_blocks):
    own_load takes A (both valid, sequence B 7 <= A 8: save.s 1103..1104) and sets SF_DIFFERS (the
    calibration words differ, 1107..1121): flags 0x02, loaded COPY_A, checked before the command.
    PROTOCOL.md 752 allows it (not held, flag 1). Expected:
    - answer status 0 (sv_map of SV_OK, cmd.s 240; PROTOCOL.md 717), 8 data bytes (save_answer, cmd.s
      1134): save status 0, save flags 0x80: save_restore_b clears SF_DIFFERS | SF_A_ONLY |
      SF_REWRITE_A and sets SF_RESTART because A was the loaded copy (save.s 1411..1418);
    - copy A = blk_b with B's sequence 7 (MODE_A, r1 = B's sequence, save.s 1405..1410; write_copy
      855..957: block, 0xFF, sequence, CRC-32 of block + sequence = copy_image), copy B unchanged;
      only A's two pages erased and programmed (recovery_ops);
    - the restart: h_restore_b sets r5 = 1 (cmd.s 1245..1251) and SF_RESTART is set, so ACT_RESET
      (cmd.s 1280..1291) -> soft_restart with REQ_RESTART after the answer (ctl.s act_step; PROTOCOL.md
      330 "After status 0 the meter restarts"); check_restart;
    - after it own_load sees equal sequences 7 / 7 and equal blocks: A loaded, flags 0 (save.s
      1103..1121), and RAM word 0x20000B20 = 0.25 (B's value; before the command it was A's 0.125)."""
    blk_a, blk_b = recovery_blocks()
    a, b = copy_image(blk_a, 8), copy_image(blk_b, 7)
    rig = recovery_rig(a, b, SF_DIFFERS, COPY_A)
    check(rig.rd(REC_USR0) == U_0125, 'RAM user word 0x%08X before the command, expected A\'s' % rig.rd(REC_USR0))
    hits = watch_restart(rig)
    st, d = rig.ask('RESTORE_B', OK2)
    check(st == S_OK and d == struct.pack('<II', 0, SF_RESTART), 'RESTORE_B: status %d data %s' % (st, d.hex()))
    check_restart(rig, hits, REQ_RESTART, 'RESTORE_B')
    recovery_ops(rig, hits, SET_A, SET_B, 'RESTORE_B')
    check(rig.m.get(SET_A, 0x1000) == copy_image(blk_b, 7), 'copy A is not blk_b with sequence 7')
    check(rig.m.get(SET_B, 0x1000) == b, 'copy B changed')
    check(rig.rd(SAVE_FLAGS) == 0 and rig.rd(SAVE_LOADED) == COPY_A,
          'after the restart: flags 0x%X loaded %d' % (rig.rd(SAVE_FLAGS), rig.rd(SAVE_LOADED)))
    check(rig.rd(REC_USR0) == U_025, 'after the restart: RAM user word 0x%08X, expected B\'s 0.25' % rig.rd(REC_USR0))
    return True


@case
def k47_accept_a_with_a_loaded_no_restart():
    """SETTINGS_ACCEPT_A (0x56) allowed, A loaded: input as k46 (A = blk_a seq 8, B = blk_b seq 7;
    flags SF_DIFFERS 0x02, COPY_A, save.s 1103..1121). PROTOCOL.md 753 allows it (not held, flag 1).
    Expected:
    - answer status 0, data save status 0, flags 0: save_accept_a clears SF_DIFFERS | SF_A_ONLY and
      sets SF_RESTART only when B was loaded (save.s 1456..1463; A was loaded here);
    - copy B = blk_a with A's sequence 8 (MODE_B, r1 = A's sequence, save.s 1450..1455; copy_image),
      copy A unchanged; only B's two pages erased and programmed (recovery_ops);
    - no restart: h_accept_a sets r5 = 0 (cmd.s 1253..1259) and SF_RESTART stays clear, so no ACT_RESET
      (cmd.s 1280..1291); 1.2 s after the answer (longer than ACT_LIMIT_MS 1000, ctl.inc 135, the bound
      of a pending action) the starter was not entered;
    - one SAVE_RESULT event (0x96, PROTOCOL.md 791: the save counter changed, finish, save.s 1020..1040)
      with save status 0 and flags 0 (ctl.s 1915..1931: own_save_status, own_save_flags);
    - RAM flags 0 and the RAM user word still A's 0.125 (nothing reloaded)."""
    blk_a, blk_b = recovery_blocks()
    a, b = copy_image(blk_a, 8), copy_image(blk_b, 7)
    rig = recovery_rig(a, b, SF_DIFFERS, COPY_A)
    hits = watch_restart(rig)
    st, d = rig.ask('ACCEPT_A', OK2)
    check(st == S_OK and d == struct.pack('<II', 0, 0), 'ACCEPT_A: status %d data %s' % (st, d.hex()))
    ev = save_events(rig, 1.2)
    check(not hits['starter'], 'ACCEPT_A with A loaded restarted the meter')
    check(ev == [struct.pack('<II', 0, 0)], 'SAVE_RESULT events %r' % [e.hex() for e in ev])
    recovery_ops(rig, hits, SET_B, SET_A, 'ACCEPT_A')
    check(rig.m.get(SET_B, 0x1000) == copy_image(blk_a, 8), 'copy B is not blk_a with sequence 8')
    check(rig.m.get(SET_A, 0x1000) == a, 'copy A changed')
    check(rig.rd(SAVE_FLAGS) == 0 and rig.rd(REC_USR0) == U_0125,
          'flags 0x%X, RAM user word 0x%08X' % (rig.rd(SAVE_FLAGS), rig.rd(REC_USR0)))
    return True


@case
def k48_accept_a_with_b_loaded_then_restart():
    """SETTINGS_ACCEPT_A (0x56) allowed, B loaded: input A = blk_a seq 7, B = blk_b seq 8: own_load
    takes B (sequence B 8 > A 7, save.s 1103..1106: SF_A_ONLY) and sets SF_DIFFERS (1107..1121):
    flags 0x12, COPY_B; RAM user word B's 0.25. PROTOCOL.md 753 allows it. Expected:
    - answer status 0, data save status 0, flags 0x80: SF_DIFFERS | SF_A_ONLY cleared, SF_RESTART set
      because B was the loaded copy (save.s 1456..1463);
    - copy B = blk_a with A's sequence 7 (save.s 1450..1455), copy A unchanged; only B written;
    - the restart: SF_RESTART set -> ACT_RESET (cmd.s 1280..1291; PROTOCOL.md 753 "restart when B was
      the loaded copy"); check_restart;
    - after it own_load: sequences 7 / 7, blocks equal: A loaded, flags 0, RAM user word 0.125."""
    blk_a, blk_b = recovery_blocks()
    a, b = copy_image(blk_a, 7), copy_image(blk_b, 8)
    rig = recovery_rig(a, b, SF_DIFFERS | SF_A_ONLY, COPY_B)
    check(rig.rd(REC_USR0) == U_025, 'RAM user word 0x%08X before the command, expected B\'s' % rig.rd(REC_USR0))
    hits = watch_restart(rig)
    st, d = rig.ask('ACCEPT_A', OK2)
    check(st == S_OK and d == struct.pack('<II', 0, SF_RESTART), 'ACCEPT_A: status %d data %s' % (st, d.hex()))
    check_restart(rig, hits, REQ_RESTART, 'ACCEPT_A')
    recovery_ops(rig, hits, SET_B, SET_A, 'ACCEPT_A')
    check(rig.m.get(SET_B, 0x1000) == copy_image(blk_a, 7), 'copy B is not blk_a with sequence 7')
    check(rig.m.get(SET_A, 0x1000) == a, 'copy A changed')
    check(rig.rd(SAVE_FLAGS) == 0 and rig.rd(SAVE_LOADED) == COPY_A and rig.rd(REC_USR0) == U_0125,
          'after the restart: flags 0x%X loaded %d RAM user word 0x%08X'
          % (rig.rd(SAVE_FLAGS), rig.rd(SAVE_LOADED), rig.rd(REC_USR0)))
    return True


@case
def k49_accept_b_with_a_damaged():
    """SETTINGS_ACCEPT_B (0x59) allowed: input A = blk_a seq 5 with byte 0x300 flipped (both markers
    kept, CRC wrong: copy_check, save.s 469..500; checked on the input), B = blk_b seq 4 valid:
    own_load takes B and, A's first word being the marker (not 0xFFFFFFFF) with both markers, sets
    SF_A_ONLY | SF_HELD | SF_A_DAMAGED (save.s 1122..1136): flags 0x31, COPY_B. PROTOCOL.md 754 allows
    it (flag 5). Expected:
    - answer status 0, data save status 0, flags 0x10: save_accept_b clears SF_HELD | SF_A_DAMAGED |
      SF_REWRITE_A and sets nothing (save.s 1299..1301); SF_A_ONLY stays (B is still the loaded copy);
    - copy A = blk_b with B's sequence 4 (MODE_A, r1 = B's sequence, save.s 1293..1298), copy B
      unchanged; only A's two pages written;
    - no restart: h_accept_b r5 = 0 (cmd.s 1261..1267), SF_RESTART clear; 1.2 s after the answer
      (ACT_LIMIT_MS 1000, ctl.inc 135) the starter was not entered;
    - one SAVE_RESULT event (0x96, PROTOCOL.md 791) with save status 0 and flags 0x10;
    - saves no longer held: SETTINGS_SAVE then answers status 0 with save result 0 or 9, not 1 (held)
      (own_save holds only with SF_HELD | SF_RESTART, save.s 1188..1235; PROTOCOL.md 717..727: 0 OK, 9
      unchanged, both status 0 by sv_map, cmd.s 240..262)."""
    blk_a, blk_b = recovery_blocks()
    damaged = bytearray(copy_image(blk_a, 5))
    damaged[0x300] ^= 1
    a, b = bytes(damaged), copy_image(blk_b, 4)
    check(a[:4] == MARKER_BYTES and a[0xC10:0xC14] == MARKER_BYTES
          and zlib.crc32(a[:BLK] + a[0xFF8:0xFFC]) != struct.unpack_from('<I', a, 0xFFC)[0]
          and a[0xFF8:0x1000] != b'\xff' * 8, 'input A: not both markers with a wrong CRC')
    rig = recovery_rig(a, b, SF_HELD | SF_A_ONLY | SF_A_DAMAGED, COPY_B)
    hits = watch_restart(rig)
    st, d = rig.ask('ACCEPT_B', OK2)
    check(st == S_OK and d == struct.pack('<II', 0, SF_A_ONLY), 'ACCEPT_B: status %d data %s' % (st, d.hex()))
    ev = save_events(rig, 1.2)
    check(not hits['starter'], 'ACCEPT_B restarted the meter')
    check(ev == [struct.pack('<II', 0, SF_A_ONLY)], 'SAVE_RESULT events %r' % [e.hex() for e in ev])
    recovery_ops(rig, hits, SET_A, SET_B, 'ACCEPT_B')
    check(rig.m.get(SET_A, 0x1000) == copy_image(blk_b, 4), 'copy A is not blk_b with sequence 4')
    check(rig.m.get(SET_B, 0x1000) == b, 'copy B changed')
    check(rig.rd(SAVE_FLAGS) == SF_A_ONLY, 'flags 0x%X' % rig.rd(SAVE_FLAGS))
    st, d = rig.ask('SET_SAVE', OK2)
    check(st == S_OK and len(d) == 8 and struct.unpack_from('<I', d)[0] & 0xFF in (0, 9),
          'SETTINGS_SAVE after ACCEPT_B: status %d data %s' % (st, d.hex()))
    return True


@case
def k50_restore_b_with_b_loaded_then_restart():
    """SETTINGS_RESTORE_B (0x55) allowed with B loaded: input as k48 (A = blk_a seq 7, B = blk_b seq 8;
    flags 0x12, COPY_B, save.s 1103..1121). Expected:
    - answer status 0, data save status 0, flags 0: SF_DIFFERS | SF_A_ONLY | SF_REWRITE_A cleared, no
      SF_RESTART (set only when A was the loaded copy, save.s 1411..1418: the RAM block is B's);
    - copy A = blk_b with B's sequence 8 (save.s 1405..1410), copy B unchanged; only A written;
    - the restart all the same: h_restore_b r5 = 1 restarts after every SV_OK (cmd.s 1245..1251,
      1280..1291; PROTOCOL.md 752 "restart after result 0"); check_restart;
    - after it own_load: sequences 8 / 8, blocks equal: A loaded, flags 0, RAM user word 0.25."""
    blk_a, blk_b = recovery_blocks()
    a, b = copy_image(blk_a, 7), copy_image(blk_b, 8)
    rig = recovery_rig(a, b, SF_DIFFERS | SF_A_ONLY, COPY_B)
    hits = watch_restart(rig)
    st, d = rig.ask('RESTORE_B', OK2)
    check(st == S_OK and d == struct.pack('<II', 0, 0), 'RESTORE_B: status %d data %s' % (st, d.hex()))
    check_restart(rig, hits, REQ_RESTART, 'RESTORE_B')
    recovery_ops(rig, hits, SET_A, SET_B, 'RESTORE_B')
    check(rig.m.get(SET_A, 0x1000) == copy_image(blk_b, 8), 'copy A is not blk_b with sequence 8')
    check(rig.m.get(SET_B, 0x1000) == b, 'copy B changed')
    check(rig.rd(SAVE_FLAGS) == 0 and rig.rd(SAVE_LOADED) == COPY_A and rig.rd(REC_USR0) == U_025,
          'after the restart: flags 0x%X loaded %d RAM user word 0x%08X'
          % (rig.rd(SAVE_FLAGS), rig.rd(SAVE_LOADED), rig.rd(REC_USR0)))
    return True


def main():
    args = sys.argv[1:]
    sel = []
    while args:
        a = args.pop(0)
        if a == '--key':
            OPTS['key'] = int(args.pop(0))
        elif a == '--hold':
            OPTS['hold'] = int(args.pop(0))
        elif a == '--fresh':
            OPTS['fresh'] = True
        else:
            sel.append(a)
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
