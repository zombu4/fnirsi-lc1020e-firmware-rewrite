#!/usr/bin/env python3
"""lc1020e.py - host library and command-line tool for the USB control channel of the FNIRSI LC1020E
firmware rewrite. The protocol is specified in PROTOCOL.md (protocol version 1).

Requirements: Python 3.8 or later, the standard library and pyserial (only for talking to a meter;
--selftest runs without it).

Library:
    from lc1020e import Meter
    with Meter() as m:                      # first port with VID 0x19F5 / PID 0x1020, or Meter('/dev/...')
        print(m.info())
        print(m.measure())
        for ev in m.events(timeout=10):
            print(ev)

Command line (python3 -I tools/lc1020e.py --help):
    info, ping, state, stream, events, key, screen, measure, set, compare, tolerance, hold, calibrate,
    settings,
    cal-read, backup, restore-block, screenshot, mem, battery, factory-mode, update,
    boot-status, boot-update, power-off, reset; --selftest checks the CRCs, the frame encoder and
    parser, the record decoders and the PNG writer without a meter.
"""

import argparse
import collections
import os
import struct
import sys
import time
import zlib
from array import array
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

# ----------------------------------------------------------------------------------------------
# Protocol constants (PROTOCOL.md)
# ----------------------------------------------------------------------------------------------

VID = 0x19F5
PID = 0x1020
PROTOCOL_VERSION = 1

SYNC = 0xA5
T_REQUEST, T_ANSWER, T_STREAM, T_EVENT = 1, 2, 3, 4
MAX_PAYLOAD = 512
LEN_MIN, LEN_MAX = 3, 515

CONFIRM_OK = 0x4F4B            # bytes 4B 4F
CONFIRM_POWER_OFF = 0x4F46     # bytes 46 4F

C = dict(
    INFO=0x00, PING=0x01, RESET=0x02, BATTERY=0x03, POWER_OFF=0x05, FACTORY_MODE=0x06,
    STATE=0x10, STREAM=0x11, SCREEN=0x12, KEY=0x13,
    LCR_TABLES=0x20, LCR_SET=0x21, MEASURE=0x22, MEASURE_STREAM=0x23, COMPARE=0x24,
    COMPARE_SET=0x25, HOLD=0x26, CALIBRATE=0x27, TOLERANCE_SET=0x28,
    SETTINGS_TABLES=0x50, SETTINGS_SET=0x51, SETTINGS_SAVE=0x52, CAL_READ=0x53,
    RESTORE_DEFAULTS=0x54, SETTINGS_RESTORE_B=0x55, SETTINGS_ACCEPT_A=0x56,
    SETTINGS_WRITE_BLOCK=0x57, SETTINGS_ACCEPT_B=0x59,
    SETTINGS_ACCEPT_DEFAULTS=0x5A, SCREENSHOT=0x60, MEM_READ=0xF0,
    OCAL_INFO=0x30, OCAL_READ=0x31, OCAL_WRITE=0x32, OCAL_ROLLBACK=0x33, OCAL_LOCK=0x34,
    OCAL_RAW=0x35, OCAL_TRACE=0x36, MONITOR=0x37,
    UPDATE_MODE=0x84, BOOT_BEGIN=0x85, BOOT_DATA=0x86, BOOT_END=0x87, BOOT_INSTALL=0x88,
    BOOT_STATUS=0x89)
CMD_NAME = {v: k for k, v in C.items()}

E = dict(KEY=0x90, SCREEN_CHANGED=0x91, SETTING_CHANGED=0x93, POWERED_OFF=0x94,
         MEASURE_DONE=0x95, SAVE_RESULT=0x96, CALIBRATION=0x97, OCAL_CHANGED=0x98)
EVENT_NAME = {v: k for k, v in E.items()}

STATUS_NAME = {0: 'OK', 1: 'unknown command', 2: 'bad length or argument', 3: 'not allowed now',
               4: 'busy', 5: 'storage error', 6: 'refused for safety',
               7: 'CRC or length mismatch of transferred data'}

# Answer time limits in seconds: the firmware's own limit of the command plus a margin for the
# transfer and the main-loop pass (PROTOCOL.md "Timing").
T_FAST = 1.5
T_SAVE = 4.0                    # one save: up to 1.5 s inside one main-loop pass
T_DIRECT = 4.0                  # a direct change (capability bit 21): at most 2000 ms in the meter
TIMEOUT = {
    C['SCREEN']: 23.0, C['LCR_SET']: 23.0, C['HOLD']: 23.0, C['SETTINGS_SET']: 23.0,
    C['COMPARE_SET']: 63.0, C['CALIBRATE']: 366.0,
    C['BOOT_BEGIN']: 13.0, C['BOOT_INSTALL']: 4.0,
    C['SETTINGS_SAVE']: T_SAVE, C['RESTORE_DEFAULTS']: T_SAVE, C['SETTINGS_RESTORE_B']: T_SAVE,
    C['SETTINGS_ACCEPT_A']: T_SAVE, C['SETTINGS_ACCEPT_B']: T_SAVE,
    C['SETTINGS_ACCEPT_DEFAULTS']: T_SAVE, C['SETTINGS_WRITE_BLOCK']: T_SAVE,
    C['OCAL_WRITE']: T_SAVE, C['OCAL_ROLLBACK']: T_SAVE,      # one commit in the pass: up to 1.0 s
}
# The commands a firmware with capability bit 21 sets directly (PROTOCOL.md 4.1, 14); a firmware
# without the bit runs them as key jobs with the times of TIMEOUT.
CAP_DIRECT = 21
DIRECT = (C['SCREEN'], C['LCR_SET'], C['HOLD'], C['SETTINGS_SET'], C['COMPARE_SET'])
# Capability bit 25: the calibration sweep of firmware/own/cal.s (limit 360 s, so 366 s); a firmware
# without it runs the vendor's 45-s sweep (limit 120 s, so 126 s).
CAP_CAL3 = 25
T_CAL_OLD = 126.0
# Capability bit 26: the own calibration area (firmware/own/ocal.s, OWN_CAL_DESIGN.md revision 3):
# OCAL_* and MONITOR, event OCAL_CHANGED, MEASURE byte 65.
CAP_OCAL = 26
OCAL_FLAGS = ['active', 'slot 0 valid', 'slot 1 valid', 'newer format', 'foreign UID',
              'section rejected', 'retake short/open', 'lock', 'transfer open', 'trace']


def timeout_for(cmd, payload=b'', capabilities=None):
    """Answer time of a command in seconds: the firmware's limit plus a margin (PROTOCOL.md 4.3).
    capabilities: the INFO capability word, None while it is not known (the long times then)."""
    if cmd == C['KEY']:
        hold = struct.unpack_from('<H', payload, 1)[0] if len(payload) >= 3 else 0
        return 23.0 + hold / 1000.0
    if cmd in DIRECT and capabilities is not None and capabilities >> CAP_DIRECT & 1:
        return T_DIRECT
    if cmd == C['CALIBRATE'] and capabilities is not None and not capabilities >> CAP_CAL3 & 1:
        return T_CAL_OLD
    return TIMEOUT.get(cmd, T_FAST)

# Screens, keys, records
SCREEN_NAME = {1: 'measure', 2: 'compare', 3: 'settings'}      # screen 0 (the vendor's language
                                                                # chooser) is never shown
KEY_NAME = {0: 'power', 1: 'up', 3: 'ok'}
STATE_FLAGS = ['hold', 'compare screen', 'DTR', 'power off requested', 'save failed',
               'backup differs', 'calibration running', 'factory mode', 'saves held',
               'restart pending', 'powered-off mode']
MAIN_NAME = {1: 'R', 2: 'C', 3: 'L', 4: 'Z'}
SECONDARY_NAME = {0: 'R', 1: 'X', 2: 'D', 3: 'Q', 4: 'theta'}
UNIT_NAME = {0: '', 1: 'ohm', 2: 'kohm', 3: 'Mohm', 4: 'pF', 5: 'nF', 6: 'uF', 7: 'mF',
             8: 'uH', 9: 'mH', 10: 'H', 11: 'deg'}
VALIDITY_NAME = {0: 'valid', 1: 'overload', 2: 'no reading', 3: 'held'}
CIRCUIT_NAME = {0: 'auto', 1: 'series', 2: 'parallel'}

# Settings storage
SAVE_FLAGS = {0x01: 'saves held', 0x02: 'backup differs', 0x04: 'no valid copy at load',
              0x08: 'last save failed', 0x10: 'copy B loaded (saves write A only)',
              0x20: 'copy A damaged', 0x40: 'rewrite of A pending', 0x80: 'restart pending'}
SF_RESTART = 0x80
SAVE_RESULT = {0: 'OK', 1: 'held', 2: 'refused', 3: 'trailer mark failed', 4: 'erase failed',
               5: 'program failed', 6: 'verify failed', 7: 'bad block', 8: 'source copy invalid',
               9: 'unchanged (nothing written)'}
# compare results of the COMPARE tail (byte 40) and the tolerance modes (bytes 29 / 30)
COMPARE_RESULT = {0: '---', 1: 'IN', 2: 'HI', 3: 'LO', 4: 'secondary limit', 5: 'out of range',
                  6: '--- (not stable)'}
TOL_MODE = {0: 'vendor +-%', 1: '% limits', 2: 'pF limits', 3: 'letter'}
SEC_LIMIT = {0: 'none', 1: 'D max', 2: 'Q min', 3: 'ESR max'}
SAVE_STEP = {0: '', 0x01: 'check', 0x41: 'mark', 0x42: 'erase', 0x43: 'program', 0x44: 'verify'}
SAVE_COPY = {0: '', 1: 'A', 2: 'B'}
FLASH_RESULT = {0: 'OK', 1: 'outside the gate', 2: 'word not erased', 3: 'controller locked',
                4: 'flash error flag', 5: 'read-back differs', 6: 'page not blank'}
UPDATE_RESULT = {0: 'none', 1: 'OK', 2: 'image check failed', 3: 'programming failed'}
CAL_STATUS = {0: 'start', 1: 'busy', 2: 'finish', 3: 'fail'}
# CALIBRATE answer byte 7 (capability bit 25, firmware/own/cal.s CAL_R_*)
# (reasons 2 and 5 end short and reference points only: an open point ends at its limit with the windows it
# has, MEASUREMENT_FIX_DESIGN revision 10)
CAL_REASON = {0: 'none', 1: 'no acquisition for 1.5 s', 2: 'point time limit, fewer than 3 windows',
              3: 'open below 100 kohm', 4: 'the store check of the table', 5: 'point time limit, 3 windows not agreeing',
              6: 'ended by a key, the dialog closed or the screen left'}
RECORD_STATE = {0: 'none', 1: 'INSTALL', 2: 'TRIAL', 3: 'OK'}

BLOCK_SIZE = 0xC14
BLOCK_MARKER = 0x12345678
COPY_SIZE = 0x1000
COPY_BASE = {0: 0x0807F000, 1: 0x08066000}

# Slots and the update drive
SLOT_BASE = {0: 0x08069000, 1: 0x0806F000, 2: 0x08075000}
SLOT_NAME = {0: 'F', 1: 'A', 2: 'B', 0xFF: 'unknown'}
SLOT_SIZE = 0x6000
SLOT_ROOM = 0x5E00
SLOT_FILE_MIN = 0x208
HDR_MAGIC = 0x544F4C53
SRAM_LO, SRAM_HI = 0x20000000, 0x20024000
UF2_MAGIC0, UF2_MAGIC1, UF2_MAGIC_END = 0x0A324655, 0x9E5D5157, 0x0AB16F30
UF2_FAMILY = 0xC6B3602B
APP_BASE, APP_END = 0x08006000, 0x08062000
DRIVE_LABEL = 'LC1020E-IAP'
DRIVE_FILE = 'LC1020E.UF2'

SCR_W, SCR_H, SCR_BANDS, SCR_ROWS = 320, 240, 24, 10
SCR_RESULT = {0: 'done', 1: 'no room', 2: 'no refresh'}

CAPS = ['STATE / STREAM', 'SCREEN', 'KEY', 'LCR_TABLES / LCR_SET', 'MEASURE / MEASURE_STREAM',
        'COMPARE / COMPARE_SET', 'HOLD', 'CALIBRATE', 'SETTINGS_*', 'CAL_READ', 'SCREENSHOT',
        'MEM_READ', 'events', 'UPDATE_MODE', 'BOOT_*', 'BATTERY', 'POWER_OFF', 'RESTORE_DEFAULTS',
        'settings recovery', 'FACTORY_MODE',
        'SETUP_LANGUAGE (not used, English only)', 'direct set',   # bit 20 clear, bit 21
        '60 Hz (frequency index 5)', 'TOLERANCE_SET / COMPARE tail',
        'MEASURE markers / save result unchanged',                 # bits 22..24
        'calibration sweep of cal.s',                              # bit 25
        'own calibration area (OCAL_*, MONITOR)']                  # bit 26


# ----------------------------------------------------------------------------------------------
# CRCs, frames, parser
# ----------------------------------------------------------------------------------------------

def crc16(data, crc=0xFFFF):
    """CRC-16/CCITT-FALSE: polynomial 0x1021, initial 0xFFFF, no reflection, no final XOR."""
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def crc32(data):
    """CRC-32 of the firmware (reflected, polynomial 0xEDB88320, initial and final XOR 0xFFFFFFFF)."""
    return zlib.crc32(data) & 0xFFFFFFFF


def encode_frame(ftype, seq, cmd, payload=b''):
    payload = bytes(payload)
    if len(payload) > MAX_PAYLOAD:
        raise ValueError('payload of %d bytes: at most %d' % (len(payload), MAX_PAYLOAD))
    body = struct.pack('<HBBB', len(payload) + 3, seq & 0xFF, ftype, cmd & 0xFF) + payload
    return bytes([SYNC]) + body + struct.pack('<H', crc16(body))


@dataclass
class Frame:
    type: int
    seq: int
    cmd: int
    payload: bytes


class FrameParser:
    """Byte stream -> frames. A byte that does not start a frame with a valid length and CRC is
    skipped and the search for the next 0xA5 starts at the byte after it."""

    def __init__(self):
        self.buf = bytearray()
        self.skipped = 0
        self.bad_crc = 0

    def feed(self, data):
        self.buf += data
        out = []
        buf = self.buf
        while True:
            i = buf.find(SYNC)
            if i < 0:
                self.skipped += len(buf)
                del buf[:]
                break
            if i:
                self.skipped += i
                del buf[:i]
            if len(buf) < 3:
                break
            n = buf[1] | buf[2] << 8
            if not LEN_MIN <= n <= LEN_MAX:
                self.skipped += 1
                del buf[:1]
                continue
            if len(buf) < n + 5:
                # incomplete: a false 0xA5 (e.g. opened in the middle of a frame) must not hold
                # back a complete valid frame that follows it
                j = self._later_frame(1)
                if j < 0:
                    break
                self.skipped += j
                del buf[:j]
                continue
            body = bytes(buf[1:3 + n])
            got = buf[3 + n] | buf[4 + n] << 8
            if crc16(body) != got:
                self.bad_crc += 1
                self.skipped += 1
                del buf[:1]
                continue
            out.append(Frame(body[3], body[2], body[4], body[5:]))
            del buf[:n + 5]
        return out

    def _later_frame(self, start):
        """Index of the first 0xA5 at or after start that begins a complete frame with a valid
        length and CRC, or -1."""
        buf = self.buf
        j = buf.find(SYNC, start)
        while j >= 0:
            if j + 3 <= len(buf):
                n = buf[j + 1] | buf[j + 2] << 8
                if LEN_MIN <= n <= LEN_MAX and j + n + 5 <= len(buf) and \
                        crc16(bytes(buf[j + 1:j + 3 + n])) == (buf[j + 3 + n] | buf[j + 4 + n] << 8):
                    return j
            j = buf.find(SYNC, j + 1)
        return -1


# ----------------------------------------------------------------------------------------------
# Records and answers
# ----------------------------------------------------------------------------------------------

def _f32(u):
    return struct.unpack('<f', struct.pack('<I', u & 0xFFFFFFFF))[0]


def _text(b):
    return b.decode('ascii', 'backslashreplace')


def _zstr(data, pos):
    """Zero-terminated text at pos -> (bytes, position after the zero); a text cut by the end of
    the answer ends there."""
    end = data.find(b'\0', pos)
    if end < 0:
        return bytes(data[pos:]), len(data)
    return bytes(data[pos:end]), end + 1


def flag_names(value, names):
    if isinstance(names, dict):
        return [n for bit, n in names.items() if value & bit]
    return [n for i, n in enumerate(names) if value >> i & 1]


@dataclass
class Info:
    protocol: int
    capabilities: int
    firmware: str
    uid: bytes
    running_slot: int
    slot_version: int
    app_size: int
    update_result: int
    raw: bytes = field(repr=False, default=b'')
    SIZE = 46

    @classmethod
    def parse(cls, d):
        if len(d) < cls.SIZE:
            raise MeterError('INFO answer of %d bytes, expected %d' % (len(d), cls.SIZE))
        p, caps, fw, uid, slot, ver, size, res = struct.unpack_from('<BI16s12sBIII', d)
        return cls(p, caps, fw.rstrip(b'\0').decode('ascii', 'replace'), uid, slot, ver, size,
                   res, bytes(d))

    def has(self, bit):
        return bool(self.capabilities >> bit & 1)


@dataclass
class State:
    screen: int
    flags: int
    func: int
    main_row: int
    secondary: int
    frequency: int
    level: float
    bias: float
    range: int
    speed: int
    circuit: int
    cursor: int
    dialog: int
    menu_item: int
    language: int
    dropped: int
    save_status: int
    time: int
    raw: bytes = field(repr=False, default=b'')
    SIZE = 32

    @classmethod
    def parse(cls, d):
        if len(d) < cls.SIZE:
            raise MeterError('STATE record of %d bytes, expected %d' % (len(d), cls.SIZE))
        v = struct.unpack_from('<BHBBBIffBBBBBBBHBI', d)
        return cls(*v, raw=bytes(d[:cls.SIZE]))

    def flag(self, name):
        return bool(self.flags >> STATE_FLAGS.index(name) & 1)


@dataclass
class Value:
    value: float
    unit: int
    decimals: int
    validity: int
    text: str
    SIZE = 15

    @classmethod
    def parse(cls, d, pos):
        v, unit, dec, val, txt = struct.unpack_from('<fBBB8s', d, pos)
        return cls(v, unit, dec, val, txt.rstrip(b'\0').decode('ascii', 'replace'))

    def __str__(self):
        if self.validity in (1, 2):
            return '%s (%s)' % (self.text or '-', VALIDITY_NAME[self.validity])
        s = '%s %s' % (self.text, UNIT_NAME.get(self.unit, '?%d' % self.unit))
        return s.strip() + (' (held)' if self.validity == 3 else '')


@dataclass
class Measure:
    result: int
    time: int
    main_row: int
    main: Value
    secondary_kind: int
    secondary: Value
    parallel: int
    z: float
    theta: float
    frequency: int
    level: float
    bias: float
    range: int
    speed: int
    circuit: int
    raw: bytes = field(repr=False, default=b'')
    markers: int = 0     # byte 64 (capability bit 24): bit 0 main, bit 1 secondary outside the
                         # accuracy table; 0 for a 64-byte record of older firmware
    ocal: int = 0        # byte 65 (capability bit 26): bit 0 gain applied, bit 1 GAIN for the
                         # frequency but not this cell, bit 2 lock, bit 3 retake short / open
    SIZE = 64

    @classmethod
    def parse(cls, d):
        if len(d) < cls.SIZE:
            raise MeterError('MEASURE record of %d bytes, expected %d' % (len(d), cls.SIZE))
        res, t, mrow = struct.unpack_from('<IIB', d, 0)
        main = Value.parse(d, 9)
        skind = d[24]
        sec = Value.parse(d, 25)
        par, z, th, fq, lv, bs, rg, sp, ci = struct.unpack_from('<BffIffBBB', d, 40)
        mk = d[64] if len(d) > 64 else 0
        oc = d[65] if len(d) > 65 else 0
        return cls(res, t, mrow, main, skind, sec, par, z, th, fq, lv, bs, rg, sp, ci,
                   bytes(d[:min(len(d), 66)]), mk, oc)


@dataclass
class Compare:
    quantity: int
    nominal: float
    tolerance: float
    deviation: float
    ok: int
    passed: int
    failed: int
    value: float
    warn_type: int
    warn_sound: int
    warn_led: int
    raw: bytes = field(repr=False, default=b'')
    tail: tuple = None   # bytes 29..49 (capability bit 23): (mode in force, mode set, letter,
                         # lower, upper, result, signed deviation, secondary kind, secondary value);
                         # None for a 29-byte record of older firmware
    SIZE = 29
    TAIL_SIZE = 50

    @classmethod
    def parse(cls, d):
        if len(d) < cls.SIZE:
            raise MeterError('COMPARE record of %d bytes, expected %d' % (len(d), cls.SIZE))
        tail = (struct.unpack_from('<BBBffBfBf', d, 29) if len(d) >= cls.TAIL_SIZE else None)
        n = cls.TAIL_SIZE if tail is not None else cls.SIZE
        return cls(*struct.unpack_from('<BfffBIIfBBB', d), raw=bytes(d[:n]), tail=tail)


@dataclass
class Battery:
    volts: float
    level: int
    low_popup: int


@dataclass
class SaveResult:
    status: int          # answer status (0 OK, 3, 5, 7)
    save_status: int     # result | step << 8 | copy << 16
    flags: int
    restart: bool        # the meter restarts after this answer

    @property
    def result(self):
        return self.save_status & 0xFF

    def describe(self):
        r = SAVE_RESULT.get(self.result, '?%d' % self.result)
        step = SAVE_STEP.get(self.save_status >> 8 & 0xFF, '')
        copy = SAVE_COPY.get(self.save_status >> 16 & 0xFF, '')
        s = 'save %s' % r
        if step:
            s += ', step %s' % step
        if copy:
            s += ', copy %s' % copy
        fl = flag_names(self.flags, SAVE_FLAGS)
        return s + '; flags 0x%02X %s' % (self.flags, ', '.join(fl) if fl else '(none)') + \
            ('; the meter restarts' if self.restart else '')


@dataclass
class CalResult:
    status: int
    cal_status: int
    cal_type: int
    save_status: int
    fail_point: int = 0xFF          # capability bit 25: the point 0..14 that failed, 0xFF none
    fail_reason: int = 0            # CAL_REASON


@dataclass
class OcalInfo:
    """OCAL_INFO (64 bytes, PROTOCOL.md 16.2)."""
    flags: int
    slot: int
    format: int
    length: int
    sequence: int
    other_sequence: int
    crc: int
    present: int
    gain_freqs: int
    monitor_freqs: int
    rejected: int
    t_max: int
    meta_time: int
    meta_note: str

    @classmethod
    def parse(cls, d):
        if len(d) < 64:
            raise MeterError('OCAL_INFO of %d bytes, expected 64' % len(d))
        fl, sl, fm, ln, sq, oq, cr, pr, gf, mf, rj, tm, _, mt = struct.unpack_from('<IBBHIIIBBBBHHI', d, 0)
        return cls(fl, sl, fm, ln, sq, oq, cr, pr, gf, mf, rj, tm, mt, _text(d[32:60]))


@dataclass
class OcalRaw:
    """OCAL_RAW / OCAL_LOCK answer (64 bytes, PROTOCOL.md 16.3)."""
    window: int
    c5: int
    c6: int
    c8: int
    lock: int
    frequency: int
    level: float
    bias: float
    n: int
    cls_: int
    flags: int
    z_re: float
    z_im: float
    a_v: float
    a_i: float
    sig2_v: float
    sig2_i: float
    adc1: tuple
    adc2: tuple

    @classmethod
    def parse(cls, d):
        if len(d) < 64:
            raise MeterError('OCAL_RAW of %d bytes, expected 64' % len(d))
        v = struct.unpack_from('<IBBBBIffHBBffffffHHHHHH', d, 0)
        return cls(*v[:17], tuple(v[17:20]), tuple(v[20:23]))


@dataclass
class Monitor:
    """MONITOR (25 bytes, PROTOCOL.md 16.5)."""
    v: float
    i: float
    a_v_ref: float
    a_i_ref: float
    flags: int
    mid1: int
    mid2: int
    window: int

    @classmethod
    def parse(cls, d):
        if len(d) < 25:
            raise MeterError('MONITOR of %d bytes, expected 25' % len(d))
        return cls(*struct.unpack_from('<ffffBHHI', d, 0))


@dataclass
class UpdateMode:
    status: int
    next_slot: int
    next_version: int
    running_slot: int


@dataclass
class SlotInfo:
    version: int
    length: int
    crc: int
    ok: int


@dataclass
class BootStatus:
    slots: List[SlotInfo]
    newest_slot: int
    newest_state: int
    newest_sequence: int
    next_slot: int
    free_slot: int
    SIZE = 47

    @classmethod
    def parse(cls, d):
        if len(d) < cls.SIZE:
            raise MeterError('BOOT_STATUS answer of %d bytes, expected %d' % (len(d), cls.SIZE))
        slots = [SlotInfo(*struct.unpack_from('<IIIB', d, 13 * i)) for i in range(3)]
        ns, st, seq, nxt, free = struct.unpack_from('<BBIBB', d, 39)
        return cls(slots, ns, st, seq, nxt, free)


@dataclass
class LcrList:
    id: int
    value_type: int      # 0 index, 1 u32, 2 f32
    name: bytes          # English (the firmware is English only)
    unit: bytes
    entries: List[Tuple[object, bytes]]
    count: int

    @classmethod
    def parse(cls, d):
        lid, count, vtype = d[0], d[1], d[2]
        name, pos = _zstr(d, 3)
        unit, pos = _zstr(d, pos)
        entries = []
        while pos + 4 <= len(d) and len(entries) < count:
            (u,) = struct.unpack_from('<I', d, pos)
            pos += 4
            text, pos = _zstr(d, pos)
            entries.append((_f32(u) if vtype == 2 else u, text))
        return cls(lid, vtype, name, unit, entries, count)


@dataclass
class Setting:
    id: int
    kind: int            # 0 choices, 1 range
    current: int
    min: int
    max: int
    step: int
    name: bytes
    choices: List[bytes]

    @classmethod
    def parse(cls, d):
        sid, kind, cur, lo, hi, step = struct.unpack_from('<BBIIII', d)
        name, pos = _zstr(d, 18)
        count = d[pos] if pos < len(d) else 0
        pos += 1
        choices = []
        while pos < len(d) and len(choices) < count:
            text, pos = _zstr(d, pos)
            choices.append(text)
        return cls(sid, kind, cur, lo, hi, step, name, choices)


@dataclass
class Event:
    cmd: int
    seq: int
    fields: Dict[str, object]

    @property
    def name(self):
        return EVENT_NAME.get(self.cmd, '0x%02X' % self.cmd)

    @classmethod
    def parse(cls, f):
        p, c = f.payload, f.cmd
        try:
            if c == E['KEY']:
                mask, code, src = struct.unpack_from('<HBB', p)
                fl = dict(mask=mask, code=code, source='injected' if src else 'physical')
            elif c == E['SCREEN_CHANGED']:
                fl = dict(screen=p[0], previous=p[1])
            elif c == E['SETTING_CHANGED']:
                sid, val = struct.unpack_from('<HI', p)
                fl = dict(id=sid, value=val)
            elif c == E['POWERED_OFF']:
                fl = {}
            elif c == E['MEASURE_DONE']:
                fl = dict(result=struct.unpack_from('<I', p)[0])
            elif c == E['SAVE_RESULT']:
                st, flags = struct.unpack_from('<II', p)
                fl = dict(save_status=st, flags=flags)
            elif c == E['CALIBRATION']:
                fl = dict(status=p[0], step=p[1], type=p[2])
            else:
                fl = dict(payload=bytes(p))
        except (struct.error, IndexError):
            fl = dict(payload=bytes(p), malformed=True)
        return cls(c, f.seq, fl)

    def __str__(self):
        fl = self.fields
        if self.cmd == E['KEY']:
            code = {1: 'short', 0xFE: 'held', 0xFF: 'released'}.get(fl['code'], fl['code'])
            return 'KEY mask 0x%04X %s (%s)' % (fl['mask'], code, fl['source'])
        if self.cmd == E['SETTING_CHANGED']:
            if fl['id'] == 0xFFFE:
                return 'SETTING_CHANGED calibration tables: %d words' % fl['value']
            return 'SETTING_CHANGED id 0x%04X value 0x%08X (%d)' % (fl['id'], fl['value'], fl['value'])
        if self.cmd == E['SAVE_RESULT']:
            return 'SAVE_RESULT ' + SaveResult(0, fl['save_status'], fl['flags'], False).describe()
        return '%s %s' % (self.name, ' '.join('%s=%s' % kv for kv in fl.items()))


# ----------------------------------------------------------------------------------------------
# Errors
# ----------------------------------------------------------------------------------------------

class MeterError(Exception):
    pass


class StatusError(MeterError):
    """An answer with a status other than 0. `record` is the decoded data that came with it, if
    any (job commands answer their record also with an error status)."""

    def __init__(self, cmd, status, data=b'', record=None):
        self.cmd, self.status, self.data, self.record = cmd, status, bytes(data), record
        super().__init__('%s: status %d (%s)' % (CMD_NAME.get(cmd, '0x%02X' % cmd), status,
                                                 STATUS_NAME.get(status, '?')))


class AnswerTimeout(MeterError):
    pass


# ----------------------------------------------------------------------------------------------
# PNG writer (zlib only)
# ----------------------------------------------------------------------------------------------

def png_bytes(width, height, rgb):
    """rgb = width * height * 3 bytes, row-major -> PNG file bytes (8-bit RGB, filter 0)."""
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + \
            struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF)
    stride = width * 3
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += rgb[y * stride:(y + 1) * stride]
    return (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))


def rgb565_to_rgb(pixels):
    out = bytearray(len(pixels) * 3)
    for i, v in enumerate(pixels):
        r, g, b = v >> 11 & 0x1F, v >> 5 & 0x3F, v & 0x1F
        out[3 * i] = r << 3 | r >> 2
        out[3 * i + 1] = g << 2 | g >> 4
        out[3 * i + 2] = b << 3 | b >> 2
    return out


# ----------------------------------------------------------------------------------------------
# Files: UF2, slot files, settings copies
# ----------------------------------------------------------------------------------------------

def check_uf2(data):
    """Checks an application .uf2 for the slot bootloader. Returns the number of blocks."""
    if not data or len(data) % 512:
        raise MeterError('UF2 file length %d is not a multiple of 512' % len(data))
    n = len(data) // 512
    for i in range(n):
        m0, m1, flags, addr, size, num, total, family = struct.unpack_from('<8I', data, 512 * i)
        (mend,) = struct.unpack_from('<I', data, 512 * i + 508)
        if (m0, m1, mend) != (UF2_MAGIC0, UF2_MAGIC1, UF2_MAGIC_END):
            raise MeterError('block %d: not a UF2 block' % i)
        if not flags & 0x2000 or family != UF2_FAMILY:
            raise MeterError('block %d: family 0x%08X is not the LC1020E application (0x%08X)'
                             % (i, family, UF2_FAMILY))
        if size != 256 or addr % 256 or not APP_BASE <= addr < APP_END:
            raise MeterError('block %d: target 0x%08X / %d bytes outside the application area'
                             % (i, addr, size))
    return n


def check_slot_file(data, base):
    """The checks of BOOT_BEGIN and BOOT_END on the host, for a slot file to be written at base.
    Returns the header version."""
    if len(data) < SLOT_FILE_MIN or len(data) > SLOT_SIZE or len(data) % 4:
        raise MeterError('slot file of %d bytes: must be 0x%X..0x%X bytes and a multiple of 4'
                         % (len(data), SLOT_FILE_MIN, SLOT_SIZE))
    magic, length, icrc, version, link = struct.unpack_from('<5I', data, 0)
    (hcrc,) = struct.unpack_from('<I', data, 28)
    if magic != HDR_MAGIC:
        raise MeterError('slot file: no "SLOT" header')
    if crc32(data[:28]) != hcrc:
        raise MeterError('slot file: header CRC-32 does not match')
    if link != base + 0x200:
        raise MeterError('slot file is linked for 0x%08X; the free slot needs 0x%08X'
                         % (link, base + 0x200))
    if length < 8 or length > SLOT_ROOM or length % 4 or 0x200 + length > len(data):
        raise MeterError('slot file: image length 0x%X does not fit' % length)
    image = data[0x200:0x200 + length]
    if crc32(image) != icrc:
        raise MeterError('slot file: image CRC-32 does not match')
    sp, reset = struct.unpack_from('<II', image, 0)
    if not SRAM_LO < sp <= SRAM_HI:
        raise MeterError('slot file: initial SP 0x%08X outside RAM' % sp)
    if not reset & 1 or not link <= (reset & ~1) < link + length:
        raise MeterError('slot file: reset vector 0x%08X outside the image' % reset)
    return version


def check_copy(copy):
    """A settings copy (0x1000 bytes as CAL_READ gives it) -> (valid, description)."""
    first, last = struct.unpack_from('<I', copy, 0)[0], struct.unpack_from('<I', copy, 0xC10)[0]
    seq, crc = struct.unpack_from('<II', copy, 0xFF8)
    if first != BLOCK_MARKER or last != BLOCK_MARKER:
        return False, 'markers missing (0x%08X, 0x%08X)' % (first, last)
    if seq == 0xFFFFFFFF and crc == 0xFFFFFFFF:
        return True, 'valid, vendor format (no trailer)'
    if zlib.crc32(copy[0xFF8:0xFFC], zlib.crc32(copy[:BLOCK_SIZE])) & 0xFFFFFFFF != crc:
        return False, 'both markers, trailer CRC-32 wrong (sequence %d)' % seq
    return True, 'valid, sequence %d' % seq


# ----------------------------------------------------------------------------------------------
# The meter
# ----------------------------------------------------------------------------------------------

def _serial():
    try:
        import serial
        import serial.tools.list_ports
    except ImportError:
        raise MeterError('pyserial is needed: python3 -m pip install pyserial')
    return serial


def find_ports(serial_number=None):
    """Device paths of the meters on USB (VID 0x19F5, PID 0x1020)."""
    serial = _serial()
    out = []
    for p in serial.tools.list_ports.comports():
        if p.vid == VID and p.pid == PID and (serial_number is None or p.serial_number == serial_number):
            out.append(p)
    # macOS lists a CDC device as /dev/cu.* and /dev/tty.*; the cu.* node does not wait for carrier
    out.sort(key=lambda p: (not p.device.startswith('/dev/cu.'), p.device))
    return out


class Meter:
    def __init__(self, port=None, connect=True):
        self.port = port
        self.serial_number = None
        self._ser = None
        self._seq = 0
        self._parser = FrameParser()
        self._queue = collections.deque(maxlen=65536)
        self.stale_answers = 0
        self.capabilities = None        # INFO capability word, known after info()
        if connect:
            self.open()

    # -- connection ---------------------------------------------------------------------------
    def open(self):
        serial = _serial()
        if self.port is None:
            ports = find_ports(self.serial_number)
            if not ports:
                raise MeterError('no LC1020E (USB %04X:%04X) found' % (VID, PID))
            self.port = ports[0].device
            self.serial_number = ports[0].serial_number
        self._ser = serial.Serial(self.port, 115200, timeout=0.05, write_timeout=2.0)
        self._ser.dtr = True
        self._ser.reset_input_buffer()
        self._parser = FrameParser()
        if self.serial_number is None:
            for p in find_ports():
                if p.device == self.port:
                    self.serial_number = p.serial_number
        return self

    def close(self):
        if self._ser is not None:
            try:
                self._ser.close()
            except OSError:
                pass
            self._ser = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def wait_gone(self, timeout=5.0):
        """Waits until the meter's port has left the bus (after a reset). Returns True if it did."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not find_ports(self.serial_number):
                return True
            time.sleep(0.1)
        return False

    def reconnect(self, timeout=60.0, gone_timeout=5.0):
        """After a reset: close, wait for the port to go and come back, open it again."""
        self.close()
        self.wait_gone(gone_timeout)
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            ports = find_ports(self.serial_number)
            if ports:
                self.port = ports[0].device
                try:
                    return self.open()
                except Exception as e:      # the port node can exist before it can be opened
                    last = e
            time.sleep(0.2)
        raise MeterError('the meter did not come back within %.0f s%s'
                         % (timeout, ' (%s)' % last if last else ''))

    # -- frames -------------------------------------------------------------------------------
    def _pump(self, timeout):
        self._ser.timeout = max(0.001, timeout)
        n = self._ser.in_waiting
        data = self._ser.read(n if n else 1)
        if data:
            for f in self._parser.feed(data):
                self._queue.append(f)

    def timeout_for(self, cmd, payload=b''):
        return timeout_for(cmd, payload, self.capabilities)

    def request(self, cmd, payload=b'', timeout=None, on_frame=None):
        """Sends one request and returns (status, data) of its answer. Stream and event frames
        that arrive meanwhile stay queued for frames() / events() unless on_frame takes them."""
        if self._ser is None:
            raise MeterError('port not open')
        self._seq = (self._seq + 1) & 0xFF
        seq = self._seq
        self._ser.write(encode_frame(T_REQUEST, seq, cmd, payload))
        deadline = time.monotonic() + (timeout if timeout is not None else
                                       self.timeout_for(cmd, payload))
        while True:
            keep = collections.deque(maxlen=self._queue.maxlen)
            answer = None
            while self._queue:
                f = self._queue.popleft()
                if f.type == T_ANSWER:
                    if answer is None and f.seq == seq and f.cmd == cmd and f.payload:
                        answer = f
                    else:
                        self.stale_answers += 1
                elif on_frame is not None and f.type in (T_STREAM, T_EVENT):
                    on_frame(f)
                else:
                    keep.append(f)
            self._queue = keep
            if answer is not None:
                return answer.payload[0], bytes(answer.payload[1:])
            left = deadline - time.monotonic()
            if left <= 0:
                raise AnswerTimeout('%s: no answer' % CMD_NAME.get(cmd, '0x%02X' % cmd))
            self._pump(min(left, 0.1))

    def _ok(self, cmd, payload=b'', parse=None, **kw):
        status, data = self.request(cmd, payload, **kw)
        if status:
            rec = None
            if parse is not None and data:
                try:
                    rec = parse(data)
                except Exception:
                    rec = None
            raise StatusError(cmd, status, data, rec)
        return parse(data) if parse is not None else data

    def frames(self, timeout=None, types=(T_STREAM, T_EVENT)):
        """Yields stream / event frames as they arrive; ends after timeout seconds (None: never)."""
        deadline = None if timeout is None else time.monotonic() + timeout
        while True:
            while self._queue:
                f = self._queue.popleft()
                if f.type in types:
                    yield f
            if deadline is not None and time.monotonic() >= deadline:
                return
            self._pump(0.1 if deadline is None else max(0.0, min(0.1, deadline - time.monotonic())))

    def events(self, timeout=None):
        for f in self.frames(timeout, (T_EVENT,)):
            yield Event.parse(f)

    def stream_records(self, timeout=None):
        """Yields State / Measure records of the stream frames (cmd 0x10 / 0x22)."""
        for f in self.frames(timeout, (T_STREAM,)):
            if f.cmd == C['STATE']:
                yield State.parse(f.payload)
            elif f.cmd == C['MEASURE']:
                yield Measure.parse(f.payload)

    # -- 4.1 device ---------------------------------------------------------------------------
    def info(self):
        i = self._ok(C['INFO'], parse=Info.parse)
        self.capabilities = i.capabilities      # answer times of the direct commands (bit 21)
        return i

    def ping(self, data=b''):
        return self._ok(C['PING'], data)

    def reset(self):
        self._ok(C['RESET'])

    def battery(self):
        return self._ok(C['BATTERY'], parse=lambda d: Battery(*struct.unpack_from('<fBB', d)))

    def power_off(self):
        self._ok(C['POWER_OFF'], struct.pack('<H', CONFIRM_POWER_OFF))

    def factory_mode(self):
        return self._ok(C['FACTORY_MODE'])[0]

    # -- 4.2 state and keys -------------------------------------------------------------------
    def state(self):
        return self._ok(C['STATE'], parse=State.parse)

    def stream(self, period_ms):
        self._ok(C['STREAM'], struct.pack('<H', period_ms))

    def screen(self, screen):
        return self._ok(C['SCREEN'], bytes([screen]), parse=State.parse)

    def key(self, bit, hold_ms=0):
        if not 0 <= bit <= 13:
            raise ValueError('key bit 0..13')
        return self._ok(C['KEY'], struct.pack('<BH', bit, hold_ms), parse=State.parse)

    # -- 4.3 measurement ----------------------------------------------------------------------
    def lcr_tables(self, list_id=None):
        if list_id is None:
            return self._ok(C['LCR_TABLES'])[0]
        return self._ok(C['LCR_TABLES'], bytes([list_id]), parse=LcrList.parse)

    def lcr_set(self, setting, index):
        return self._ok(C['LCR_SET'], bytes([setting, index]), parse=Measure.parse)

    def measure(self):
        return self._ok(C['MEASURE'], parse=Measure.parse)

    def measure_stream(self, period):
        """period: 0 every new result, 0xFFFF stop, else milliseconds."""
        self._ok(C['MEASURE_STREAM'], struct.pack('<H', period))

    def compare(self):
        return self._ok(C['COMPARE'], parse=Compare.parse)

    def compare_set(self, nominal, tolerance, warn_type, warn_sound, warn_led):
        return self._ok(C['COMPARE_SET'], struct.pack('<ffBBB', nominal, tolerance, warn_type,
                                                       warn_sound, warn_led), parse=Compare.parse)

    def tolerance_set(self, mode, lower=0, upper=0, letter=b'\x00', sec_kind=0, sec_value=0.0):
        """TOLERANCE_SET (capability bit 23, PROTOCOL.md 5.3): mode 0 vendor +-%, 1 lower / upper in
        0.01 %, 2 lower / upper in 0.01 pF (compare quantity C), 3 an IEC 60062 letter; the
        secondary limit 0 none, 1 D max, 2 Q min, 3 ESR max. RAM only."""
        return self._ok(C['TOLERANCE_SET'], struct.pack('<BiicBf', mode, lower, upper, letter,
                                                         sec_kind, sec_value), parse=Compare.parse)

    def hold(self, on):
        return self._ok(C['HOLD'], bytes([1 if on else 0]), parse=State.parse)

    def calibrate(self, cal_type, on_frame=None):
        def parse(d):
            st, ty, sv = struct.unpack_from('<BBI', d)
            if len(d) >= 8:                 # capability bit 25: the failed point and its reason
                return CalResult(0, st, ty, sv, d[6], d[7])
            return CalResult(0, st, ty, sv)
        status, data = self.request(C['CALIBRATE'], struct.pack('<BH', cal_type, CONFIRM_OK),
                                    on_frame=on_frame)
        if len(data) >= 6:
            r = parse(data)
            r.status = status
        else:
            r = None
        if status:
            raise StatusError(C['CALIBRATE'], status, data, r)
        return r

    # -- 4.4 settings and storage -------------------------------------------------------------
    def settings_tables(self, setting=None):
        if setting is None:
            return self._ok(C['SETTINGS_TABLES'])[0]
        return self._ok(C['SETTINGS_TABLES'], bytes([setting]), parse=Setting.parse)

    def settings_set(self, setting, value):
        return self._ok(C['SETTINGS_SET'], struct.pack('<BH', setting, value), parse=State.parse)

    def _save(self, cmd, payload, restarts_on_ok=False):
        status, data = self.request(cmd, payload)
        if len(data) < 8:
            raise StatusError(cmd, status, data)
        st, flags = struct.unpack_from('<II', data)
        restart = bool(flags & SF_RESTART) or (restarts_on_ok and (st & 0xFF) == 0)
        r = SaveResult(status, st, flags, restart)
        if status:
            raise StatusError(cmd, status, data, r)
        return r

    def settings_save(self):
        return self._save(C['SETTINGS_SAVE'], struct.pack('<H', CONFIRM_OK))

    def restore_defaults(self):
        return self._save(C['RESTORE_DEFAULTS'], struct.pack('<H', CONFIRM_OK))

    def settings_restore_b(self):
        return self._save(C['SETTINGS_RESTORE_B'], struct.pack('<H', CONFIRM_OK), True)

    def settings_accept_a(self):
        return self._save(C['SETTINGS_ACCEPT_A'], struct.pack('<H', CONFIRM_OK))

    def settings_accept_b(self):
        return self._save(C['SETTINGS_ACCEPT_B'], struct.pack('<H', CONFIRM_OK))

    def settings_accept_defaults(self):
        return self._save(C['SETTINGS_ACCEPT_DEFAULTS'], struct.pack('<H', CONFIRM_OK))

    def write_block(self, block, chunk=500):
        """SETTINGS_WRITE_BLOCK of a whole 0xC14-byte block. Returns the SaveResult of the last
        chunk (on success the meter restarts after it)."""
        block = bytes(block)
        if len(block) != BLOCK_SIZE:
            raise ValueError('block of %d bytes, expected 0x%X' % (len(block), BLOCK_SIZE))
        if struct.unpack_from('<I', block, 0)[0] != BLOCK_MARKER or \
                struct.unpack_from('<I', block, 0xC10)[0] != BLOCK_MARKER:
            raise MeterError('block markers missing: the meter would refuse it (status 7)')
        crc = crc32(block)
        off = 0
        while True:
            part = block[off:off + chunk]
            head = struct.pack('<HHHI', CONFIRM_OK, off, BLOCK_SIZE, crc)
            if off + len(part) < BLOCK_SIZE:
                nxt = self._ok(C['SETTINGS_WRITE_BLOCK'], head + part)
                (got,) = struct.unpack_from('<H', nxt)
                if got != off + len(part):
                    raise MeterError('WRITE_BLOCK: meter expects offset %d, sent %d'
                                     % (got, off + len(part)))
                off = got
            else:
                return self._save(C['SETTINGS_WRITE_BLOCK'], head + part, True)

    def ocal_info(self):
        return OcalInfo.parse(self._ok(C['OCAL_INFO']))

    def ocal_read(self, slot, offset, length):
        return self._ok(C['OCAL_READ'], struct.pack('<BHH', slot, offset, length))

    def ocal_slots(self):
        """Both slots of the area, 2 x 0x2000 bytes (64 reads of 256 each)."""
        return b''.join(self.ocal_read(s, o, 256) for s in (0, 1) for o in range(0, 0x2000, 256))

    def ocal_write(self, body, chunk=500):
        """OCAL_WRITE of a body (sections of PROTOCOL.md 16.1); returns (result, slot, sequence).
        Status 2 with 3 data bytes raises StatusError with the section id and entry index."""
        if len(body) % 4 or not 8 <= len(body) <= 0x9C0:
            raise MeterError('body of %d bytes: 8..0x9C0, a multiple of 4' % len(body))
        crc = crc32(body)
        off = 0
        while True:
            part = body[off:off + chunk]
            st, d = self.request(C['OCAL_WRITE'], struct.pack('<HHHI', CONFIRM_OK, off, len(body), crc) + part)
            if st != 0:
                raise StatusError(C['OCAL_WRITE'], st, d)
            off += len(part)
            if off == len(body):
                return struct.unpack_from('<BBI', d, 0)
            if struct.unpack_from('<H', d, 0)[0] != off:
                raise MeterError('OCAL_WRITE: meter expects offset %d, sent up to %d' % (d[0] | d[1] << 8, off))

    def ocal_rollback(self, mode):
        d = self._ok(C['OCAL_ROLLBACK'], struct.pack('<HB', CONFIRM_OK, mode))
        return struct.unpack_from('<BII', d, 0)

    def ocal_lock(self, c5, c6, c8):
        return OcalRaw.parse(self._ok(C['OCAL_LOCK'], bytes((c5, c6, c8))))

    def ocal_release(self):
        return OcalRaw.parse(self._ok(C['OCAL_LOCK'], b'\xff\xff\xff'))

    def ocal_raw(self):
        return OcalRaw.parse(self._ok(C['OCAL_RAW']))

    def ocal_trace(self, op, start=0):
        d = self._ok(C['OCAL_TRACE'], bytes((op, start)))
        st, kind, tick, count, n = struct.unpack_from('<BBIBB', d, 0)
        ent = [struct.unpack_from('<IffBBBB', d, 8 + 16 * k) for k in range(n)]
        return st, kind, tick, count, ent

    def monitor(self):
        return Monitor.parse(self._ok(C['MONITOR']))

    def cal_read(self, copy, offset, length):
        return self._ok(C['CAL_READ'], struct.pack('<BHH', copy, offset, length))

    def read_copy(self, copy):
        """The whole 0x1000 bytes of settings copy 0 (A) or 1 (B)."""
        return b''.join(self.cal_read(copy, off, 256) for off in range(0, COPY_SIZE, 256))

    # -- screenshot and diagnostics -----------------------------------------------------------
    def _capture(self, band, pixels, have, inactivity=3.5):
        """One SCREENSHOT command (band 0..23 or 0xFF): pixel frames into pixels / have.
        Returns {band: end result} of the end frames received."""
        status, data = self.request(C['SCREENSHOT'], bytes([band]))
        if status:
            raise StatusError(C['SCREENSHOT'], status, data)
        w, h, fmt, count = struct.unpack_from('<HHBB', data)
        if (w, h, fmt) != (SCR_W, SCR_H, 0):
            raise MeterError('screenshot format %dx%d / %d not known' % (w, h, fmt))
        expected = set(range(SCR_BANDS)) if band == 0xFF else {band}
        if len(expected) != count:
            raise MeterError('screenshot: %d bands announced, %d expected' % (count, len(expected)))
        results = {}
        last = time.monotonic()
        while set(results) != expected:
            got = False
            keep = collections.deque(maxlen=self._queue.maxlen)
            while self._queue:
                f = self._queue.popleft()
                if f.type != T_STREAM or f.cmd != C['SCREENSHOT']:
                    keep.append(f)
                    continue
                got = True
                b, off, x1, y1, x2, y2 = struct.unpack_from('<BHhhhh', f.payload)
                if off == 0xFFFF:
                    results[b] = f.payload[11] if len(f.payload) > 11 else 0xFF
                    continue
                pix = array('H')
                pix.frombytes(bytes(f.payload[11:11 + (len(f.payload) - 11) // 2 * 2]))
                if sys.byteorder != 'little':
                    pix.byteswap()
                wd = x2 - x1 + 1
                if wd <= 0:
                    continue
                for k, v in enumerate(pix):
                    i = off + k
                    x, y = x1 + i % wd, y1 + i // wd
                    if 0 <= x < SCR_W and 0 <= y < SCR_H and y <= y2:
                        pixels[y * SCR_W + x] = v
                        have[y * SCR_W + x] = 1
            self._queue = keep
            now = time.monotonic()
            if got:
                last = now
            elif now - last > inactivity:
                break               # the capture stopped without its end frame
            self._pump(0.05)
        return results

    def screenshot(self, path=None, retries=3):
        """The screen as 320 x 240 RGB565 values (array 'H', row-major); written as PNG to path.
        Bands that end with result 1 or 2, lack their end frame or are incomplete are requested
        again one by one (retries rounds)."""
        pixels = array('H', [0]) * (SCR_W * SCR_H)
        have = bytearray(SCR_W * SCR_H)
        results = self._capture(0xFF, pixels, have)

        def band_ok(b):
            rows = have[b * SCR_ROWS * SCR_W:(b + 1) * SCR_ROWS * SCR_W]
            return results.get(b) == 0 and all(rows)
        for _ in range(retries):
            todo = [b for b in range(SCR_BANDS) if not band_ok(b)]
            if not todo:
                break
            for b in todo:
                results.update(self._capture(b, pixels, have))
        bad = [b for b in range(SCR_BANDS) if not band_ok(b)]
        if bad:
            raise MeterError('screenshot: bands %s incomplete (results %s)'
                             % (bad, {b: SCR_RESULT.get(results.get(b), results.get(b)) for b in bad}))
        if path:
            with open(path, 'wb') as f:
                f.write(png_bytes(SCR_W, SCR_H, rgb565_to_rgb(pixels)))
        return pixels

    def mem_read(self, address, length):
        return self._ok(C['MEM_READ'], struct.pack('<IH', address, length))

    # -- updates ------------------------------------------------------------------------------
    def update_mode(self):
        status, data = self.request(C['UPDATE_MODE'])
        if len(data) < 6:
            raise StatusError(C['UPDATE_MODE'], status, data)
        r = UpdateMode(status, *struct.unpack_from('<BIB', data))
        if status:
            raise StatusError(C['UPDATE_MODE'], status, data, r)
        return r

    def boot_status(self):
        return self._ok(C['BOOT_STATUS'], parse=BootStatus.parse)

    def boot_begin(self, slot, length, crc):
        self._ok(C['BOOT_BEGIN'], struct.pack('<BII', slot, length, crc))

    def boot_data(self, offset, chunk):
        status, data = self.request(C['BOOT_DATA'], struct.pack('<I', offset) + bytes(chunk))
        if status:
            if status == 5 and len(data) >= 5:
                res, at = struct.unpack_from('<BI', data)
                raise StatusError(C['BOOT_DATA'], status, data,
                                  'flash %s at file offset 0x%X' % (FLASH_RESULT.get(res, res), at))
            raise StatusError(C['BOOT_DATA'], status, data)

    def boot_end(self):
        return struct.unpack('<I', self._ok(C['BOOT_END'])[:4])[0]

    def boot_install(self):
        self._ok(C['BOOT_INSTALL'])

    def update(self, uf2_path, drive=None, log=print, drive_timeout=60.0, port_timeout=120.0):
        """Application update: UPDATE_MODE, the .uf2 copied onto the update drive as a file, the
        port waited for, INFO checked (last update result 1). Returns the new Info."""
        with open(uf2_path, 'rb') as f:
            data = f.read()
        blocks = check_uf2(data)
        if drive is None:
            if sys.platform != 'darwin':
                raise MeterError('give the mount point of the update drive (drive=...)')
            drive = os.path.join('/Volumes', DRIVE_LABEL)
        before = self.info()
        log('running: %s, slot %s (version %d)' % (before.firmware, SLOT_NAME.get(before.running_slot,
            before.running_slot), before.slot_version))
        um = self.update_mode()
        log('update mode: slot %s (version %d) starts next'
            % (SLOT_NAME.get(um.next_slot, um.next_slot), um.next_version))
        self.close()
        deadline = time.monotonic() + drive_timeout
        while not _is_update_drive(drive):
            if time.monotonic() > deadline:
                raise MeterError('update drive %s did not appear within %.0f s'
                                 % (drive, drive_timeout))
            time.sleep(0.5)
        target = os.path.join(drive, DRIVE_FILE)
        log('copying %d UF2 blocks to %s' % (blocks, target))
        # A plain open / write: no extended attributes, so macOS writes no "._" companion file.
        try:
            with open(target, 'wb') as g:
                g.write(data)
                g.flush()
                try:
                    import fcntl
                    fcntl.fcntl(g.fileno(), fcntl.F_FULLFSYNC)      # macOS: through the drive cache
                except (ImportError, AttributeError, OSError):
                    os.fsync(g.fileno())
        except OSError as e:
            # the bootloader resets 1 s after the last block; INFO below decides
            log('note: %s (the drive may have gone after the last block)' % e)
        self.port = None
        deadline = time.monotonic() + port_timeout
        while not find_ports(self.serial_number):
            if time.monotonic() > deadline:
                raise MeterError('the meter did not come back within %.0f s (it stays in update '
                                 'mode after a failed update: copy the file again)' % port_timeout)
            time.sleep(0.5)
        self.reconnect(timeout=30.0, gone_timeout=0.0)
        after = self.info()
        if after.update_result != 1:
            raise MeterError('INFO after the update: last update result %d (%s)' % (
                after.update_result, UPDATE_RESULT.get(after.update_result, '?')))
        log('updated: %s, application %d bytes' % (after.firmware, after.app_size))
        return after

    def boot_update(self, slot_path, log=print):
        """Bootloader slot update through BOOT_*: the free slot that BOOT_STATUS names, only with
        a slot file linked for it. Returns (BootStatus, Info) after the meter has restarted."""
        with open(slot_path, 'rb') as f:
            data = f.read()
        st = self.boot_status()
        free = st.free_slot
        if free not in (1, 2):
            raise MeterError('BOOT_STATUS names no free slot (%d)' % free)
        version = check_slot_file(data, SLOT_BASE[free])
        crc = crc32(data)
        log('free slot %s at 0x%08X: %d bytes, version %d, CRC-32 0x%08X'
            % (SLOT_NAME[free], SLOT_BASE[free], len(data), version, crc))
        self.boot_begin(free, len(data), crc)
        for off in range(0, len(data), 256):
            self.boot_data(off, data[off:off + 256])
        got = self.boot_end()
        if got != version:
            raise MeterError('BOOT_END reports version %d, file has %d' % (got, version))
        log('slot %s written and checked; installing' % SLOT_NAME[free])
        self.boot_install()
        self.reconnect()
        after = self.boot_status()
        info = self.info()
        started = info.running_slot == free or (info.running_slot == 0xFF and
                                                after.newest_slot == free and after.newest_state == 3)
        if not started:
            raise MeterError('after the install slot %s runs (newest record: slot %s %s)' % (
                SLOT_NAME.get(info.running_slot, info.running_slot),
                SLOT_NAME.get(after.newest_slot, after.newest_slot),
                RECORD_STATE.get(after.newest_state, after.newest_state)))
        log('slot %s runs; newest record %s' % (SLOT_NAME[free],
                                                RECORD_STATE.get(after.newest_state, '?')))
        return after, info


def _is_update_drive(path):
    try:
        return os.path.isdir(path) and any(n.lower() == 'ready.txt' for n in os.listdir(path))
    except OSError:
        return False


# ----------------------------------------------------------------------------------------------
# Command line
# ----------------------------------------------------------------------------------------------

def _num(s):
    return int(s, 0)


def parse_key(s):
    names = {v: k for k, v in KEY_NAME.items()}
    if s.lower() in names:
        return names[s.lower()]
    if s.lower().startswith('0x'):
        m = int(s, 16)
        if m == 0 or m & (m - 1) or m > 0x2000:
            raise argparse.ArgumentTypeError('a key mask has one bit of 0x0001..0x2000')
        return m.bit_length() - 1
    b = int(s)
    if not 0 <= b <= 13:
        raise argparse.ArgumentTypeError('key bit 0..13')
    return b


def fmt_state(s):
    fl = flag_names(s.flags, STATE_FLAGS)
    lines = ['screen %d (%s), flags 0x%04X %s' % (s.screen, SCREEN_NAME.get(s.screen, '?'), s.flags,
                                                 ', '.join(fl) if fl else ''),
             'Func %d, main row %s, secondary %s, %d Hz, level %.3g V, bias %.3g V, range %d, '
             'speed %d, circuit %s' % (s.func, MAIN_NAME.get(s.main_row, s.main_row),
                                       SECONDARY_NAME.get(s.secondary, s.secondary), s.frequency,
                                       s.level, s.bias, s.range, s.speed,
                                       CIRCUIT_NAME.get(s.circuit, s.circuit)),
             'cursor %d, dialog %d, menu item %d, language %d, dropped %d, save status %d, '
             'time %d' % (s.cursor, s.dialog, s.menu_item, s.language, s.dropped, s.save_status,
                          s.time)]
    return '\n'.join(lines)


def fmt_measure(m):
    um = ' (unspecified)'
    return ('#%d t=%d  %s = %s%s   %s = %s%s   |Z| %.6g ohm  theta %.4g deg  %s  %d Hz %.3g V bias '
            '%.3g V range %d speed %d' % (
                m.result, m.time, MAIN_NAME.get(m.main_row, m.main_row), m.main,
                um if m.markers & 1 else '', SECONDARY_NAME.get(m.secondary_kind, m.secondary_kind),
                m.secondary, um if m.markers & 2 else '', m.z, m.theta,
                'parallel' if m.parallel else 'series', m.frequency, m.level, m.bias, m.range,
                m.speed))


def fmt_compare(c):
    s = ('quantity %s, nominal %.6g, tolerance %.3g %%, deviation %.4g %% %s, pass %d, fail %d, '
         'value %.6g, warn type %d, sound %d, LED %d' % (
             {1: 'R', 2: 'C', 3: 'L'}.get(c.quantity, c.quantity), c.nominal, c.tolerance,
             c.deviation, 'OK' if c.ok else 'NG', c.passed, c.failed, c.value, c.warn_type,
             c.warn_sound, c.warn_led))
    if c.tail is not None:
        em, tm, let, lo, hi, res, dev, sk, sv = c.tail
        unit = 'pF' if em == 2 else '%'
        s += ('; mode %s%s, limits %.4g .. %.4g %s, result %s, deviation %+.4g %s, secondary %s%s' % (
            TOL_MODE.get(tm, tm), ' %s' % chr(let) if tm == 3 else '', lo, hi, unit,
            COMPARE_RESULT.get(res, res), dev, unit, SEC_LIMIT.get(sk, sk),
            ' %.4g' % sv if sk else ''))
    return s


def fmt_info(i):
    caps = [n for b, n in enumerate(CAPS) if i.has(b)]
    return '\n'.join([
        'firmware %s, protocol %d, UID %s' % (i.firmware, i.protocol, i.uid.hex().upper()),
        'running slot %s, slot bootloader version %d, application %d bytes, last update %s'
        % (SLOT_NAME.get(i.running_slot, i.running_slot), i.slot_version, i.app_size,
           UPDATE_RESULT.get(i.update_result, i.update_result)),
        'capabilities 0x%08X: %s' % (i.capabilities, ', '.join(caps))])


def print_record(rec):
    if isinstance(rec, State):
        print(fmt_state(rec))
    elif isinstance(rec, Measure):
        print(fmt_measure(rec))
    elif isinstance(rec, Compare):
        print(fmt_compare(rec))
    elif isinstance(rec, SaveResult):
        print(rec.describe())
    elif isinstance(rec, tuple):
        for r in rec:
            print_record(r)
    elif rec is not None:
        print(rec)


def need_yes(a, what):
    if not a.yes:
        sys.exit('%s: add --yes to confirm' % what)


def cmd_main(a, m):
    c = a.command
    if c == 'info':
        print(fmt_info(m.info()))
    elif c == 'ping':
        data = bytes.fromhex(a.hex) if a.hex else b''
        t = time.monotonic()
        back = m.ping(data)
        print('%s in %.1f ms' % ('echo OK' if back == data else 'echo differs', 1000 * (time.monotonic() - t)))
    elif c == 'state':
        print(fmt_state(m.state()))
    elif c == 'stream':
        if a.measure is not None:
            m.measure_stream(a.measure)
        m.stream(a.period)
        try:
            for f in m.frames(a.seconds):
                if f.type == T_EVENT:
                    print('event', Event.parse(f))
                elif f.cmd == C['STATE']:
                    print(fmt_state(State.parse(f.payload)))
                elif f.cmd == C['MEASURE']:
                    print(fmt_measure(Measure.parse(f.payload)))
        finally:
            m.stream(0)
            if a.measure is not None:
                m.measure_stream(0xFFFF)
    elif c == 'events':
        for ev in m.events(a.seconds):
            print(ev)
    elif c == 'key':
        print(fmt_state(m.key(a.key, a.hold)))
    elif c == 'screen':
        print(fmt_state(m.screen(a.screen)))
    elif c == 'measure':
        print(fmt_measure(m.measure()))
    elif c == 'set':
        if a.list or a.setting is None:
            for lid in range(m.lcr_tables()):
                t = m.lcr_tables(lid)
                print('%d %s [%s]: %s' % (lid, _text(t.name), _text(t.unit), ', '.join(
                    '%d=%s' % (i, _text(e[1])) for i, e in enumerate(t.entries))))
        else:
            if a.index is None:
                sys.exit('set: give SETTING INDEX (list with --list)')
            print(fmt_measure(m.lcr_set(a.setting, a.index)))
    elif c == 'compare':
        given = [a.nominal, a.tolerance, a.warn_type, a.warn_sound, a.warn_led]
        if all(v is None for v in given):
            print(fmt_compare(m.compare()))
        else:
            cur = m.compare()
            r = m.compare_set(cur.nominal if a.nominal is None else a.nominal,
                              cur.tolerance if a.tolerance is None else a.tolerance,
                              cur.warn_type if a.warn_type is None else a.warn_type,
                              cur.warn_sound if a.warn_sound is None else a.warn_sound,
                              cur.warn_led if a.warn_led is None else a.warn_led)
            print(fmt_compare(r))
    elif c == 'tolerance':
        print(fmt_compare(m.tolerance_set(a.mode, a.lower, a.upper, a.letter.encode()[:1] or b'\x00',
                                          a.secondary, a.secondary_value)))
    elif c == 'hold':
        print(fmt_state(m.hold(a.on == 'on')))
    elif c == 'calibrate':
        need_yes(a, 'calibrate')
        r = m.calibrate(a.type, on_frame=lambda f: print('event', Event.parse(f))
                        if f.type == T_EVENT else None)
        print('calibration %s, type %d; %s' % (CAL_STATUS.get(r.cal_status, r.cal_status),
                                               r.cal_type, SaveResult(0, r.save_status, 0, False).describe()))
        if r.fail_point != 0xFF:
            print('ended at point %d of 15: %s' % (r.fail_point + 1, CAL_REASON.get(r.fail_reason, r.fail_reason)))
    elif c == 'settings':
        settings_cmd(a, m)
    elif c == 'cal-read':
        data = m.cal_read(a.copy, a.offset, a.length)
        if a.output:
            with open(a.output, 'wb') as f:
                f.write(data)
        else:
            print(data.hex())
    elif c == 'backup':
        copies = [m.read_copy(0), m.read_copy(1)]
        with open(a.file, 'wb') as f:
            f.write(copies[0] + copies[1])
        for n, cp in zip('AB', copies):
            print('copy %s (0x%08X): %s' % (n, COPY_BASE['AB'.index(n)], check_copy(cp)[1]))
        print('%s: %d bytes (copy A then copy B, 0x1000 each)' % (a.file, 2 * COPY_SIZE))
    elif c == 'ocal-info':
        print(m.ocal_info())
    elif c == 'ocal-backup':
        data = m.ocal_slots()
        uid = m.info().uid.hex().upper()
        path = os.path.join(a.dir, 'LC1020E-%s-%s.ocal' % (uid, time.strftime('%Y%m%d-%H%M%S')))
        with open(path, 'wb') as f:
            f.write(data)
        print('%s: %d bytes' % (path, len(data)))
    elif c == 'ocal-write':
        need_yes(a, 'write the own calibration area')
        with open(a.file, 'rb') as f:
            body = f.read()
        print('result %d slot %d sequence %d' % m.ocal_write(body))
    elif c == 'ocal-rollback':
        need_yes(a, 'revoke calibration records')
        print('slot %d sequence %d flags 0x%X' % m.ocal_rollback(a.mode))
    elif c == 'lock':
        print(m.ocal_release() if a.codes == ['release'] else m.ocal_lock(*(int(x) for x in a.codes)))
    elif c == 'raw':
        print(m.ocal_raw())
    elif c == 'trace':
        op = {'disarm': 0, 'arm': 1, 'read': 2}[a.op]
        if op != 2:
            print(m.ocal_trace(op)[:4])
        else:
            st, kind, tick, count, ent = m.ocal_trace(2, 0)
            ent += m.ocal_trace(2, 31)[4] if count > 31 else []
            print('state %d kind %d tick %d count %d' % (st, kind, tick, count))
            for e in ent:
                print('  %10d  %.6g %+.6g j  flags %d  codes %d %d %d' % e)
    elif c == 'monitor':
        print(m.monitor())
    elif c == 'restore-block':
        need_yes(a, 'restore-block')
        with open(a.file, 'rb') as f:
            data = f.read()
        if len(data) == 2 * COPY_SIZE:
            cp = data[:COPY_SIZE] if a.copy == 'A' else data[COPY_SIZE:]
            ok, why = check_copy(cp)
            print('copy %s in the backup: %s' % (a.copy, why))
            if not ok and not a.force:
                sys.exit('refused: that copy is not valid (--force sends it anyway)')
            block = cp[:BLOCK_SIZE]
        elif len(data) == BLOCK_SIZE:
            block = data
        else:
            sys.exit('%s: %d bytes; expected a backup (0x2000) or a block (0x%X)'
                     % (a.file, len(data), BLOCK_SIZE))
        r = m.write_block(block)
        print(r.describe())
        if r.restart:
            m.reconnect()
            print(fmt_state(m.state()))
    elif c == 'screenshot':
        t = time.monotonic()
        m.screenshot(a.file)
        print('%s written (%.1f s)' % (a.file, time.monotonic() - t))
    elif c == 'mem':
        out = bytearray()
        addr, left = a.address, a.length
        while left:
            n = min(256, left)
            out += m.mem_read(addr, n)
            addr += n
            left -= n
        if a.output:
            with open(a.output, 'wb') as f:
                f.write(out)
        else:
            for i in range(0, len(out), 16):
                print('%08X  %s' % (a.address + i, out[i:i + 16].hex(' ')))
    elif c == 'battery':
        b = m.battery()
        print('%.3f V, icon level %d, low-voltage popup %s' % (b.volts, b.level,
                                                               'shown' if b.low_popup else 'no'))
    elif c == 'factory-mode':
        print('factory mode word: %d' % m.factory_mode())
    elif c == 'update':
        need_yes(a, 'update')
        m.update(a.file, drive=a.drive)
    elif c == 'boot-status':
        st = m.boot_status()
        for i, s in enumerate(st.slots):
            print('slot %s 0x%08X: version %d, length %d, CRC-32 0x%08X, header %s'
                  % (SLOT_NAME[i], SLOT_BASE[i], s.version, s.length, s.crc,
                     'OK' if s.ok else 'fails'))
        print('newest record: slot %s %s sequence %d; next start: slot %s; free slot: %s'
              % (SLOT_NAME.get(st.newest_slot, st.newest_slot),
                 RECORD_STATE.get(st.newest_state, st.newest_state), st.newest_sequence,
                 SLOT_NAME.get(st.next_slot, st.next_slot), SLOT_NAME.get(st.free_slot, st.free_slot)))
    elif c == 'boot-update':
        need_yes(a, 'boot-update')
        m.boot_update(a.file)
    elif c == 'power-off':
        need_yes(a, 'power-off')
        m.power_off()
        print('power-off path started')
    elif c == 'reset':
        m.reset()
        if a.wait:
            m.reconnect()
            print(fmt_info(m.info()))


def settings_cmd(a, m):
    act = a.action
    if act == 'list':
        for sid in range(m.settings_tables()):
            s = m.settings_tables(sid)
            name = _text(s.name)
            if s.kind == 0:
                ch = ', '.join('%d=%s' % (s.min + i * s.step, _text(t))
                               for i, t in enumerate(s.choices))
                print('%d %s = %d  [%s]' % (sid, name, s.current, ch))
            else:
                print('%d %s = %d  [%d..%d step %d]' % (sid, name, s.current, s.min, s.max, s.step))
        return
    if act == 'set':
        if a.id is None or a.value is None:
            sys.exit('settings set ID VALUE')
        print(fmt_state(m.settings_set(a.id, a.value)))
        return
    need_yes(a, 'settings ' + act)
    fn = {'save': m.settings_save, 'restore-defaults': m.restore_defaults,
          'restore-b': m.settings_restore_b, 'accept-a': m.settings_accept_a,
          'accept-b': m.settings_accept_b, 'accept-defaults': m.settings_accept_defaults}[act]
    r = fn()
    print(r.describe())
    if r.restart:
        m.reconnect()
        print(fmt_state(m.state()))


def build_parser():
    p = argparse.ArgumentParser(description='FNIRSI LC1020E control channel (PROTOCOL.md)')
    p.add_argument('--port', help='serial port (default: the first USB 19F5:1020 device)')
    p.add_argument('--selftest', action='store_true', help='check CRCs, frames, decoders, PNG')
    sp = p.add_subparsers(dest='command')
    sp.add_parser('info', help='INFO')
    x = sp.add_parser('ping', help='PING')
    x.add_argument('hex', nargs='?', help='bytes to echo, hex')
    sp.add_parser('state', help='STATE record')
    x = sp.add_parser('stream', help='STATE stream (and MEASURE stream) for a while')
    x.add_argument('period', type=_num, help='STATE period in ms (0: none)')
    x.add_argument('--measure', type=_num, help='MEASURE_STREAM period (0 every result, else ms)')
    x.add_argument('--seconds', type=float, default=10.0)
    x = sp.add_parser('events', help='print events')
    x.add_argument('--seconds', type=float, default=None)
    x = sp.add_parser('key', help='KEY: one key press through the meter')
    x.add_argument('key', type=parse_key, help='bit 0..13, mask 0x0001..0x2000, power, up or ok')
    x.add_argument('--hold', type=_num, default=0, help='hold time in ms (0: short press)')
    x = sp.add_parser('screen', help='SCREEN: 1 measure, 2 compare, 3 settings')
    x.add_argument('screen', type=_num, choices=(1, 2, 3))
    sp.add_parser('measure', help='MEASURE record')
    x = sp.add_parser('set', help='LCR_SET (or --list: LCR_TABLES)')
    x.add_argument('setting', type=_num, nargs='?', help='0 Func, 1 secondary, 2 frequency, 3 level, '
                   '4 bias, 5 range, 6 speed, 7 circuit mode')
    x.add_argument('index', type=_num, nargs='?', help='value index')
    x.add_argument('--list', action='store_true')
    x = sp.add_parser('compare', help='COMPARE, or COMPARE_SET with any of the options')
    x.add_argument('--nominal', type=float)
    x.add_argument('--tolerance', type=float)
    x.add_argument('--warn-type', type=_num, choices=(0, 1))
    x.add_argument('--warn-sound', type=_num, choices=(0, 1))
    x.add_argument('--warn-led', type=_num, choices=(0, 1))
    x = sp.add_parser('tolerance', help='TOLERANCE_SET (RAM only): mode 0 vendor +-%%, 1 lower / upper '
                      'in 0.01 %%, 2 lower / upper in 0.01 pF (C only), 3 --letter B C D F G J K M Z')
    x.add_argument('mode', type=_num, choices=(0, 1, 2, 3))
    x.add_argument('--lower', type=_num, default=0)
    x.add_argument('--upper', type=_num, default=0)
    x.add_argument('--letter', default='')
    x.add_argument('--secondary', type=_num, choices=(0, 1, 2, 3), default=0,
                   help='0 none, 1 D max, 2 Q min, 3 ESR max')
    x.add_argument('--secondary-value', type=float, default=0.0)
    x = sp.add_parser('hold', help='HOLD on / off')
    x.add_argument('on', choices=('on', 'off'))
    x = sp.add_parser('calibrate', help='CALIBRATE: 0 short, 11 open (1..10 factory mode only)')
    x.add_argument('type', type=_num)
    x.add_argument('--yes', action='store_true')
    x = sp.add_parser('settings', help='SETTINGS_* and the storage commands')
    x.add_argument('action', choices=('list', 'set', 'save', 'restore-defaults', 'restore-b',
                                      'accept-a', 'accept-b', 'accept-defaults'))
    x.add_argument('id', type=_num, nargs='?')
    x.add_argument('value', type=_num, nargs='?')
    x.add_argument('--yes', action='store_true')
    x = sp.add_parser('cal-read', help='CAL_READ: copy 0 (A) / 1 (B), offset, length <= 256')
    x.add_argument('copy', type=_num, choices=(0, 1))
    x.add_argument('offset', type=_num)
    x.add_argument('length', type=_num)
    x.add_argument('-o', '--output')
    x = sp.add_parser('backup', help='both settings copies (CAL_READ) into one file')
    x.add_argument('file')
    sp.add_parser('ocal-info', help='OCAL_INFO')
    x = sp.add_parser('ocal-backup', help='both slots of the own calibration area into DIR/LC1020E-<UID>-<date>.ocal')
    x.add_argument('dir')
    x = sp.add_parser('ocal-write', help='OCAL_WRITE of a body file (typed yes)')
    x.add_argument('file')
    x.add_argument('--yes', action='store_true')
    x = sp.add_parser('ocal-rollback', help='OCAL_ROLLBACK: 0 the active record, 1 every own record')
    x.add_argument('mode', type=int, choices=(0, 1))
    x.add_argument('--yes', action='store_true')
    x = sp.add_parser('lock', help='OCAL_LOCK C5 C6 C8, or "release"')
    x.add_argument('codes', nargs='+')
    sp.add_parser('raw', help='OCAL_RAW')
    x = sp.add_parser('trace', help='OCAL_TRACE arm | read | disarm')
    x.add_argument('op', choices=('arm', 'read', 'disarm'))
    sp.add_parser('monitor', help='MONITOR')
    x = sp.add_parser('restore-block', help='SETTINGS_WRITE_BLOCK from a backup or block file')
    x.add_argument('file')
    x.add_argument('--copy', choices=('A', 'B'), default='A', help='copy of a backup file')
    x.add_argument('--force', action='store_true', help='send a copy whose CRC does not match')
    x.add_argument('--yes', action='store_true')
    x = sp.add_parser('screenshot', help='SCREENSHOT into a PNG file')
    x.add_argument('file')
    x = sp.add_parser('mem', help='MEM_READ (split into reads of 256 bytes)')
    x.add_argument('address', type=_num)
    x.add_argument('length', type=_num)
    x.add_argument('-o', '--output')
    sp.add_parser('battery', help='BATTERY')
    sp.add_parser('factory-mode', help='FACTORY_MODE')
    x = sp.add_parser('update', help='application update with a .uf2')
    x.add_argument('file')
    x.add_argument('--drive', help='mount point of the update drive (default /Volumes/%s)' % DRIVE_LABEL)
    x.add_argument('--yes', action='store_true')
    sp.add_parser('boot-status', help='BOOT_STATUS')
    x = sp.add_parser('boot-update', help='bootloader slot update with a slot file')
    x.add_argument('file')
    x.add_argument('--yes', action='store_true')
    x = sp.add_parser('power-off', help='POWER_OFF')
    x.add_argument('--yes', action='store_true')
    x = sp.add_parser('reset', help='RESET')
    x.add_argument('--wait', action='store_true', help='wait for the port and print INFO')
    return p


# ----------------------------------------------------------------------------------------------
# Self-test (no meter)
# ----------------------------------------------------------------------------------------------

def selftest():
    fails = []

    def check(name, cond):
        print('%-52s %s' % (name, 'ok' if cond else 'FAIL'))
        if not cond:
            fails.append(name)

    check('CRC-16/CCITT-FALSE("123456789") = 0x29B1', crc16(b'123456789') == 0x29B1)
    check('CRC-32("123456789") = 0xCBF43926', crc32(b'123456789') == 0xCBF43926)
    fr = encode_frame(T_REQUEST, 1, C['INFO'])
    check('INFO request = a5 03 00 01 01 00 + CRC', fr[:6] == bytes.fromhex('a50300010100')
          and len(fr) == 8 and struct.unpack('<H', fr[6:])[0] == crc16(fr[1:6]))
    good = encode_frame(T_ANSWER, 7, C['PING'], b'\x00abc')
    bad = bytearray(good)
    bad[-1] ^= 0xFF
    junk = bytes([0x00, SYNC, 0xFF, 0xFF, SYNC, 0x02, 0x00])     # bad length, short length
    ps = FrameParser()
    out = []
    stream = junk + bytes(bad) + good + encode_frame(T_EVENT, 9, E['POWERED_OFF'])
    for i in range(0, len(stream), 3):                          # fed in pieces
        out += ps.feed(stream[i:i + 3])
    check('parser: resync, bad CRC dropped, two frames', [(f.type, f.seq, f.cmd, f.payload)
          for f in out] == [(T_ANSWER, 7, C['PING'], b'\x00abc'), (T_EVENT, 9, E['POWERED_OFF'], b'')]
          and ps.bad_crc == 1)
    big = encode_frame(T_STREAM, 0, C['SCREENSHOT'], bytes(range(256)) * 2)
    check('512-byte payload frame round trip', FrameParser().feed(big)[0].payload == bytes(range(256)) * 2)
    try:
        encode_frame(T_REQUEST, 0, 0, bytes(513))
        check('513-byte payload refused', False)
    except ValueError:
        check('513-byte payload refused', True)
    st = State.parse(struct.pack('<BHBBBIffBBBBBBBHBI', 1, 0x0005, 2, 2, 1, 1000, 0.6, 0.5, 0, 1,
                                 0, 0, 0, 0xFF, 1, 3, 0, 123456))
    check('STATE decoder (32 bytes)', st.screen == 1 and st.flag('hold') and st.flag('DTR') and
          st.frequency == 1000 and abs(st.level - 0.6) < 1e-6 and st.dropped == 3 and st.time == 123456)
    vb = struct.pack('<fBBB8s', 4.7, 5, 2, 0, b'4.70')
    ms = Measure.parse(struct.pack('<IIB', 9, 77, 2) + vb + b'\x02' +
                       struct.pack('<fBBB8s', 0.012, 0, 3, 0, b'0.012') +
                       struct.pack('<BffIffBBB', 0, 3386.0, -89.5, 1000, 0.6, 0.0, 0, 1, 0))
    check('MEASURE decoder (64 bytes)', ms.result == 9 and ms.main.unit == 5 and ms.main.text == '4.70'
          and ms.secondary.decimals == 3 and ms.frequency == 1000 and ms.speed == 1)
    check('MEASURE 64 bytes: no markers', ms.markers == 0)
    ms2 = Measure.parse(ms.raw + b'\x03')
    check('MEASURE decoder (65 bytes, markers)', ms2.markers == 3 and ms2.frequency == 1000)
    cp = Compare.parse(struct.pack('<BfffBIIfBBB', 1, 1000.0, 5.0, 1.5, 1, 10, 2, 1015.0, 0, 1, 1))
    check('COMPARE decoder (29 bytes)', cp.ok == 1 and cp.passed == 10 and cp.warn_led == 1
          and cp.tail is None)
    cp2 = Compare.parse(cp.raw + struct.pack('<BBBffBfBf', 1, 3, ord('Z'), -20.0, 80.0, 1, 1.5, 1, 0.01))
    check('COMPARE decoder (50 bytes, tail)', cp2.tail[1] == 3 and cp2.tail[2] == ord('Z')
          and cp2.tail[5] == 1 and abs(cp2.tail[6] - 1.5) < 1e-6 and cp2.tail[7] == 1)
    inf = Info.parse(struct.pack('<BI16s12sBIII', 1, 0x0FFFFF, b'LC1020E V1.1 OWN', bytes(12), 1, 2,
                                 300000, 1))
    check('INFO decoder (46 bytes)', inf.has(19) and not inf.has(20) and inf.firmware ==
          'LC1020E V1.1 OWN' and inf.running_slot == 1)
    bs = BootStatus.parse(b''.join(struct.pack('<IIIB', 2, 0x4C68, 0x1234, 1) for _ in range(3)) +
                          struct.pack('<BBIBB', 1, 3, 5, 1, 2))
    check('BOOT_STATUS decoder (47 bytes)', bs.free_slot == 2 and bs.newest_state == 3 and
          bs.slots[2].length == 0x4C68)
    lst = LcrList.parse(bytes([2, 5, 1]) + b'FREQ\0Hz\0' + b''.join(
        struct.pack('<I', v) + t + b'\0' for v, t in
        ((100, b'100Hz'), (120, b'120Hz'), (1000, b'1kHz'), (10000, b'10kHz'), (100000, b'100kHz'))))
    check('LCR_TABLES decoder', lst.count == 5 and lst.entries[4] == (100000, b'100kHz') and
          lst.name == b'FREQ' and lst.unit == b'Hz')
    se = Setting.parse(struct.pack('<BBIIII', 0, 1, 50, 10, 100, 10) + b'Brightness\0\0')
    check('SETTINGS_TABLES decoder', se.kind == 1 and se.max == 100 and se.name == b'Brightness'
          and se.choices == [])
    so = Setting.parse(struct.pack('<BBIIII', 2, 0, 1, 0, 3, 1) + b'Off Time\0\x04NO\0005min\00015min\00030min\0')
    check('SETTINGS_TABLES decoder (choices)', so.choices == [b'NO', b'5min', b'15min', b'30min'])
    ev = Event.parse(Frame(T_EVENT, 3, E['SETTING_CHANGED'], struct.pack('<HI', 0xBC8, 1000)))
    check('SETTING_CHANGED decoder', ev.fields == dict(id=0xBC8, value=1000))
    png = png_bytes(2, 2, rgb565_to_rgb(array('H', [0xF800, 0x07E0, 0x001F, 0xFFFF])))
    ihdr_ok = png[:8] == b'\x89PNG\r\n\x1a\n' and png[12:16] == b'IHDR'
    n = struct.unpack('>I', png[33:37])[0]
    idat = png[41:41 + n]
    crc_ok = struct.unpack('>I', png[41 + n:45 + n])[0] == zlib.crc32(png[37:41 + n]) & 0xFFFFFFFF
    check('PNG writer (chunks, CRCs, pixel data)', ihdr_ok and crc_ok and zlib.decompress(idat) ==
          b'\x00\xff\x00\x00\x00\xff\x00' + b'\x00\x00\x00\xff\xff\xff\xff')
    ps2 = FrameParser()
    late = ps2.feed(bytes([SYNC, 0xF4, 0x01, 0x10]) + encode_frame(T_ANSWER, 4, C['STATE'], b'\x03'))
    check('parser: false sync does not hold back a frame', len(late) == 1 and late[0].seq == 4)
    copy = bytearray(b'\xff' * COPY_SIZE)
    copy[0:4] = copy[0xC10:0xC14] = struct.pack('<I', BLOCK_MARKER)
    check('settings copy: vendor format valid', check_copy(bytes(copy))[0])
    copy[0xFF8:0xFFC] = struct.pack('<I', 7)
    copy[0xFFC:0x1000] = struct.pack('<I', zlib.crc32(bytes(copy[0xFF8:0xFFC]),
                                                      zlib.crc32(bytes(copy[:BLOCK_SIZE]))) & 0xFFFFFFFF)
    check('settings copy: trailer CRC valid', check_copy(bytes(copy)) == (True, 'valid, sequence 7'))
    image = struct.pack('<II', 0x20002800, SLOT_BASE[1] + 0x200 + 9) + bytes(8)
    hdr = struct.pack('<5I', HDR_MAGIC, len(image), crc32(image), 2, SLOT_BASE[1] + 0x200) + bytes(8)
    hdr += struct.pack('<I', crc32(hdr))
    slot = hdr + b'\xff' * (0x200 - 32) + image
    check('slot file for A accepted at A', check_slot_file(slot, SLOT_BASE[1]) == 2)
    try:
        check_slot_file(slot, SLOT_BASE[2])
        check('slot file for A refused at B', False)
    except MeterError:
        check('slot file for A refused at B', True)

    print('\nworked examples (PROTOCOL.md):')
    examples = [
        ('INFO request, seq 0x01', encode_frame(T_REQUEST, 0x01, C['INFO'])),
        ('PING request 01 02 03, seq 0x02', encode_frame(T_REQUEST, 0x02, C['PING'], b'\x01\x02\x03')),
        ('PING answer, seq 0x02', encode_frame(T_ANSWER, 0x02, C['PING'], b'\x00\x01\x02\x03')),
        ('STATE request, seq 0x03', encode_frame(T_REQUEST, 0x03, C['STATE'])),
        ('KEY bit 10 short, seq 0x04', encode_frame(T_REQUEST, 0x04, C['KEY'], struct.pack('<BH', 10, 0))),
        ('KEY bit 3 hold 1500 ms, seq 0x05', encode_frame(T_REQUEST, 0x05, C['KEY'], struct.pack('<BH', 3, 1500))),
        ('STREAM 1000 ms, seq 0x06', encode_frame(T_REQUEST, 0x06, C['STREAM'], struct.pack('<H', 1000))),
        ('MEASURE_STREAM every result, seq 0x07', encode_frame(T_REQUEST, 0x07, C['MEASURE_STREAM'], b'\x00\x00')),
        ('SETTINGS_SAVE, seq 0x08', encode_frame(T_REQUEST, 0x08, C['SETTINGS_SAVE'], struct.pack('<H', CONFIRM_OK))),
        ('CAL_READ A 0x000 256, seq 0x09', encode_frame(T_REQUEST, 0x09, C['CAL_READ'], struct.pack('<BHH', 0, 0, 256))),
        ('CALIBRATE short, seq 0x0A', encode_frame(T_REQUEST, 0x0A, C['CALIBRATE'], struct.pack('<BH', 0, CONFIRM_OK))),
        ('POWER_OFF, seq 0x0B', encode_frame(T_REQUEST, 0x0B, C['POWER_OFF'], struct.pack('<H', CONFIRM_POWER_OFF))),
        ('SCREENSHOT all bands, seq 0x0C', encode_frame(T_REQUEST, 0x0C, C['SCREENSHOT'], b'\xff')),
        ('unknown command 0x7F answer, seq 0x0D', encode_frame(T_ANSWER, 0x0D, 0x7F, b'\x01')),
        ('SCREEN_CHANGED 2 <- 1 event, seq 0x00', encode_frame(T_EVENT, 0x00, E['SCREEN_CHANGED'], b'\x02\x01')),
    ]
    for name, f in examples:
        print('  %-40s %s' % (name, f.hex(' ')))
    print('\n%d failed' % len(fails))
    return 1 if fails else 0


def main(argv=None):
    p = build_parser()
    a = p.parse_args(argv)
    if a.selftest:
        return selftest()
    if not a.command:
        p.print_help()
        return 2
    try:
        with Meter(a.port) as m:
            cmd_main(a, m)
    except StatusError as e:
        print('error:', e, file=sys.stderr)
        if e.record is not None:
            print_record(e.record)
        return 1
    except MeterError as e:
        print('error:', e, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
