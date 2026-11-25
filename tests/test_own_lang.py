#!/usr/bin/env python3
"""test_own_lang.py - English only in our application build, in the emulator.

Usage (from the repository root, after `make -C starter`, `make -C bootloader slot` and
`make -C firmware own`):
    <python with unicorn 2.1.4> tests/test_own_lang.py [case-name-prefix ...]

Specification: LANGUAGE_DESIGN.md revision 2 (section 4 lists these tests), PACKING_DESIGN.md revision
2 (section 6: l07, l08, l09) and the interface comments of firmware/own/lang.s (own_menu), own/save.s
(set_english, own_save, own_load, stage_seal) and src/rodata_04.s (ram_image). The rig (meter model,
key pad, measurement path, USB host) is the one of test_own_control.py; expected values come from the
design, from the vendor image vendor/LC1020E_V1.1_250702.bin and from the RAM words the code reads
(named per check).

Freed ranges (LANGUAGE_DESIGN.md 3, the 18 pieces of 10538 bytes): the CJK tails of the fonts
0x0802ce5c (glyphs 76..125) and 0x0802f0d8 (glyphs 69..111): bitmaps, glyph entries, code lists, the
two kerning class maps; the Chinese speed icons 0x0803C410..0x0803CBB3; the seven Chinese string
runs. Our build packs the data (each freed range reduced to its size mod 4 bytes of 0xFF): a data
address of V1.1 is found in our build through its label d_<address> (the ELF symbols, rig.s) or
through the piece map of check_pack.py. Calls are logged with code hooks at function entries (r0..r3
and the return address); a call belongs to own_menu when its return address lies between own_menu
and the next symbol of the image.
"""

import signal
import struct
import sys
import zlib

from unicorn import UC_HOOK_CODE, UC_HOOK_MEM_READ
from unicorn.arm_const import (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3, UC_ARM_REG_LR,
                               UC_ARM_REG_PC)

import check_pack as P
import test_own_control as T
from test_own_control import (Ctl, KeyPad, check, copy_image, block_with, OK2, S_OK, S_UNKNOWN, S_BAD_ARG,
                              V_BLOCK, BLK, V_LANG_SET, V_LANGUAGE, V_SCREEN, V_MENU, V_DIALOG, V_BRIGHT,
                              V_FACTORY, V_CAL_RUN, SAVE_FLAGS, SF_HELD, KEY_OK, KEY_UP, C, INFO_SIZE,
                              watch_restart, check_restart, REQ_RESTART)
from meter_model import Meter, SET_A, SET_B, APP, VENDOR_APP, OWN_BIN, own_image
from measure_model import MeasurePath, DutSource
from usb_host import UsbDevice

CASES = []
NOTES = []

KEY_ADD, KEY_UP4, KEY_DOWN10 = 0x0020, 0x0004, 0x0010     # 0x20: menu +1, 2: menu -1 (fn_08009974);
#                                                          4 / 0x10: value up / down (fn_0800f5e8)
V_VOLUME, V_OFFTIME = 0x20001160, 0x20001164
V_EDIT, V_SEL = 0x2000000C, 0x200011B4
V_NOMINAL = 0x20001184
OFF_LANG_SET, OFF_LANGUAGE = V_LANG_SET - V_BLOCK, V_LANGUAGE - V_BLOCK      # 0xBC4, 0xBE0
ROWS, LABELS, VALUES = 0x200058F0, 0x20005904, 0x20005918                   # fn_0800f294 r6 / r9 / r8
# pictures and fonts by their labels (V1.1 addresses 0x0804BBF8, 0x0804A5BC, 0x0804BD24, 0x0804BDA4,
# 0x0802CE5C, 0x0802F0D8 and the bitmap blocks 0x0802AFD8, 0x0802CE78); rig.s gives our addresses
PIC_SEL, PIC_ROW, PIC_ARROW, PIC_BAR = 'd_0804bbf8', 'd_0804a5bc', 'd_0804bd24', 'd_0804bda4'
F1, F2 = 'd_0802ce5c', 'd_0802f0d8'
F1_BITMAPS, F2_BITMAPS = 'd_0802afd8', 'd_0802ce78'
F1_ENTRIES = 'd_0802c2a4'               # glyph entries of F1; 0..75 (0x260 bytes) kept
# per-language pointer tables {row 0 address: words per row} and the 18 freed ranges (check_pack.py)
TABLES, FREED = P.TABLES, P.FREED
ENTRY_BRANCH = 0x0800F294              # b.w own_menu (4 bytes; the target follows from the symbol)
VISIBLE = [0, 2, 3, 4, 5, 6]


def case(fn):
    CASES.append(fn)
    return fn


def w32(b, off):
    return struct.unpack_from('<I', b, off)[0]


def raw(rig, addr, n):
    return bytes(rig.m.uc.mem_read(addr, n))


def text_at(rig, addr, n=48):
    b = raw(rig, addr, n)
    return b[:b.index(0)] if 0 in b else b


def english(blk):
    """The block with the first-start flag and the language word 1 (save.s set_english)."""
    b = bytearray(blk)
    struct.pack_into('<I', b, OFF_LANG_SET, 1)
    struct.pack_into('<I', b, OFF_LANGUAGE, 1)
    return bytes(b)


def chinese_block():
    """The default block with first-start flag 0 and language 0 (V1.1 before its chooser ran)."""
    return block_with(lang_set=0, **{'0x2000115c': 0})


def copy_ok(img):
    """(markers, trailer CRC matches) of a copy image (save.s header)."""
    markers = w32(img, 0) == 0x12345678 and w32(img, 0xC10) == 0x12345678
    seq, crc = w32(img, 0xFF8), w32(img, 0xFFC)
    return markers and zlib.crc32(img[:BLK] + struct.pack('<I', seq)) == crc


def check_english_copies(rig, what):
    for base in (SET_A, SET_B):
        img = rig.m.get(base, 0x1000)
        check(copy_ok(img), '%s: copy 0x%08X not valid' % (what, base))
        check(w32(img, OFF_LANG_SET) == 1 and w32(img, OFF_LANGUAGE) == 1, '%s: copy 0x%08X flag %d language %d'
              % (what, base, w32(img, OFF_LANG_SET), w32(img, OFF_LANGUAGE)))


def check_english_ram(rig, what):
    check(rig.rd(V_LANG_SET) == 1 and rig.rd(V_LANGUAGE) == 1, '%s: RAM flag %d language %d'
          % (what, rig.rd(V_LANG_SET), rig.rd(V_LANGUAGE)))


class Calls:
    """Code hooks at function entries: per name the list of (r0, r1, r2, r3, lr)."""
    REGS = (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3, UC_ARM_REG_LR)

    def __init__(self, rig, names):
        self.log = {n: [] for n in names}
        for n in names:
            a = rig.s[n] & ~1

            def hit(uc, addr, size, user, n=n):
                self.log[n].append(tuple(uc.reg_read(r) for r in self.REGS))
            rig.m.uc.hook_add(UC_HOOK_CODE, hit, begin=a, end=a)
        lo = rig.s['own_menu'] & ~1
        self.menu = (lo, min(v for v in rig.s.values() if v > lo + 1))

    def clear(self):
        for v in self.log.values():
            del v[:]

    def in_menu(self, name):
        lo, hi = self.menu
        return [c for c in self.log[name] if lo <= (c[4] & ~1) < hi]


def menu_calls(rig):
    return Calls(rig, ('own_menu', 'fn_080228d0', 'fn_08021c14', 'fn_08023558', 'fn_0802122c', 'fn_08021f5c'))


def tap(rig, mask, ms=60):
    """A physical press (rig.press), then the run until the meter's handler consumed the event (the
    event word 0x20001192 back to 0, at most 3 s): a settings redraw takes several hundred ms of one
    main-loop pass, and a press that arrives while the event slot is still full is not posted."""
    rig.press(mask, ms)
    end = rig.m.run_for(seconds=3.0, until=lambda mm: rig.rd16(T.V_KEY_CODE) == 0)
    check(end is None and rig.rd16(T.V_KEY_CODE) == 0, 'key 0x%X: event not consumed within 3 s' % mask)
    rig.run(0.05)


def goto_item(rig, n):
    """Keys 0x20 / 2 until the menu item is n (at most 6 presses, else the case fails)."""
    for _ in range(6):
        cur = rig.rd(V_MENU)
        if cur == n:
            return
        check(cur in VISIBLE and rig.rd(V_DIALOG) == 0, 'goto item %d: item %d dialog %d' % (n, cur, rig.rd(V_DIALOG)))
        tap(rig, KEY_ADD if VISIBLE.index(cur) < VISIBLE.index(n) else KEY_UP)
    check(rig.rd(V_MENU) == n, 'goto item %d: item %d after 6 presses' % (n, rig.rd(V_MENU)))


def enter_settings(rig):
    tap(rig,KEY_OK, 1200)                          # long 8: settings screen
    check(rig.rd(V_SCREEN) == 3, 'settings screen not reached: screen %d' % rig.rd(V_SCREEN))


def check_redraw(rig, calls, what):
    """The last own_menu run: rows, labels, highlight and values of the visible list (lang.s)."""
    item = rig.rd(V_MENU)
    check(item in VISIBLE, '%s: menu item %d' % (what, item))
    rows = [rig.rd(ROWS + 4 * i) for i in range(5)]
    labels = [rig.rd(LABELS + 4 * i) for i in range(5)]
    page = [6] if item == 6 else [0, 2, 3, 4, 5]
    lab = [(c[0], text_at(rig, c[1])) for c in calls.in_menu('fn_080228d0') if c[0] in labels]
    want = [(labels[r], text_at(rig, rig.rd(0x20000078 + 4 * n))) for r, n in enumerate(page)]
    check(lab == want, '%s: labels %r, expected %r' % (what, lab, want))
    names = [t for _, t in lab]
    expect_names = [b'Sorting', b'Brightness', b'Volume', b'Off Time', b'Calibration'] if item != 6 else [b'System']
    check(names == expect_names, '%s: label texts %r' % (what, names))
    shown = [c[0] for c in calls.in_menu('fn_08023558')]
    check(shown == rows[:len(page)], '%s: rows shown %r, expected the first %d' % (what, shown, len(page)))
    pic_sel, pic_row, pic_arrow, pic_bar = (rig.s[n] for n in (PIC_SEL, PIC_ROW, PIC_ARROW, PIC_BAR))
    pics = [(c[0], c[1]) for c in calls.in_menu('fn_08021c14') if c[0] in rows]
    want_pics = [(rows[r], pic_sel if n == item else pic_row) for r, n in enumerate(page)]
    check(pics == want_pics, '%s: row pictures %r' % (what, [(hex(a), hex(b)) for a, b in pics]))
    other = [c[1] for c in calls.in_menu('fn_08021c14') if c[0] not in rows]
    if item == 6:
        check(other == [pic_arrow], '%s: value pictures %r' % (what, [hex(x) for x in other]))
        check(not [c for c in calls.in_menu('fn_080228d0') if c[0] not in labels], '%s: off time text on page 2' % what)
    else:
        bars = rig.rd(V_BRIGHT) // 10 + rig.rd(V_VOLUME) // 10
        check(other.count(pic_arrow) == 2 and other.count(pic_bar) == bars and len(other) == 2 + bars,
              '%s: value pictures %r, expected 2 arrows and %d bars' % (what, [hex(x) for x in other], bars))
        off = [text_at(rig, c[1]) for c in calls.in_menu('fn_080228d0') if c[0] not in labels]
        want_off = text_at(rig, rig.rd(0x20000184 + 4 * rig.rd(V_OFFTIME)))
        check(off == [want_off], '%s: off time text %r, expected %r' % (what, off, want_off))


# ---------------------------------------------------------------- language words

@case
def l01_chinese_block_starts_english():
    """A block with language 0 and first-start flag 0 in both copies: our build starts on the measure
    screen with 1 / 1 in RAM (own_load), every table's row 0 equals its row 1 (ram_image), and the
    load writes no flash."""
    blk = chinese_block()
    rig = Ctl(a=copy_image(blk, 2), b=copy_image(blk, 1)).up()
    check(rig.rd(V_SCREEN) == 1, 'screen %d, expected the measure screen' % rig.rd(V_SCREEN))
    check_english_ram(rig, 'start')
    for base in (SET_A, SET_B):
        check(rig.m.get(base, BLK) == blk, 'copy 0x%08X changed by the start' % base)
    for base, n in TABLES.items():
        r0, r1 = raw(rig, base, 4 * n), raw(rig, base + 4 * n, 4 * n)
        check(r0 == r1, 'table 0x%08X: row 0 differs from row 1' % base)
        for k in range(n):
            if w32(r1, 4 * k) == 0:            # 0x20000054: words 7 and 8 of each row are 0
                continue
            t = text_at(rig, w32(r1, 4 * k))
            check(t and all(c < 0x80 for c in t.replace('Ω'.encode(), b'')),
                  'table 0x%08X word %d: %r is not an English text' % (base, k, t))
    s = rig.ask_ok('STATE', size=T.STATE_SIZE)
    check(s[0] == 1 and s[24] == 1, 'STATE screen %d language %d' % (s[0], s[24]))
    return True


@case
def l02_every_restore_path_stores_english():
    """USB RESTORE_DEFAULTS, the menu restore (item 6, dialog, restore box) and the start-up with no
    valid copy (then SETTINGS_ACCEPT_DEFAULTS): 1 / 1 in RAM and in both copies, no chooser."""
    blk = chinese_block()
    rig = Ctl(a=copy_image(blk, 2), b=copy_image(blk, 1)).up()
    st, d = rig.ask('RESTORE_DEF', OK2, timeout=5.0)
    check(st == S_OK, 'RESTORE_DEFAULTS status %d' % st)
    rig.run(0.5)
    check(rig.rd(V_SCREEN) == 1, 'RESTORE_DEFAULTS: screen %d' % rig.rd(V_SCREEN))
    check_english_ram(rig, 'RESTORE_DEFAULTS')
    check_english_copies(rig, 'RESTORE_DEFAULTS')
    # the menu: item 6 (five presses of 0x20), key 8 (dialog), key 8 (restore box: byte
    # 0x2000000C = 1, 0x200011B4 = 0), key 4 (0x200011B4 = 1), key 8 (fn_0800b4c8 through
    # own_restore_guard, fn_08009974 / fn_0800f5e8)
    rig = Ctl(a=copy_image(blk, 2), b=copy_image(blk, 1)).up()
    n_ops = len(rig.flash_ops())
    enter_settings(rig)
    for _ in range(5):
        tap(rig,KEY_ADD)
    check(rig.rd(V_MENU) == 6, 'menu restore: item %d' % rig.rd(V_MENU))
    tap(rig,KEY_OK)
    tap(rig,KEY_OK)
    tap(rig,KEY_UP4)
    check(rig.rd(V_DIALOG) == 1 and rig.rd8(V_EDIT) == 1 and rig.rd(V_SEL) == 1, 'restore box: dialog %d byte %d sel %d'
          % (rig.rd(V_DIALOG), rig.rd8(V_EDIT), rig.rd(V_SEL)))
    tap(rig,KEY_OK)
    rig.run(0.5)
    check(len(rig.flash_ops()) > n_ops, 'menu restore wrote nothing')
    check(rig.rd(V_SCREEN) == 1, 'menu restore: screen %d' % rig.rd(V_SCREEN))
    check_english_ram(rig, 'menu restore')
    check_english_copies(rig, 'menu restore')
    # start-up without a valid copy: 0x0800B4C8(1) writes language 0, flag 0; its save is held
    erased = b'\xff' * 0x1000
    rig = Ctl(a=erased, b=erased).up()
    check(rig.rd(SAVE_FLAGS) & SF_HELD and rig.rd(V_SCREEN) == 1, 'no valid copy: flags 0x%X screen %d'
          % (rig.rd(SAVE_FLAGS), rig.rd(V_SCREEN)))
    check_english_ram(rig, 'no valid copy')
    check(rig.m.get(SET_A, 4) == b'\xff' * 4 and rig.m.get(SET_B, 4) == b'\xff' * 4, 'held save wrote a copy')
    st, d = rig.ask('ACCEPT_DEF', OK2, timeout=5.0)
    check(st == S_OK, 'ACCEPT_DEFAULTS status %d' % st)
    check_english_copies(rig, 'ACCEPT_DEFAULTS')
    return True


@case
def l03_write_block_with_chinese_words():
    """SETTINGS_WRITE_BLOCK of a block with 0 / 0: both copies hold the host block with 1 / 1 (valid
    CRC over the stored bytes), the restarted application 1 / 1 on the measure screen; then V1.1 run
    on our copy A starts English on its measure screen."""
    erased = b'\xff' * 0x1000
    rig = Ctl(a=erased, b=erased).up()
    host = block_with(lang_set=0, **{'0x2000115c': 0, '0x20001158': 70})
    crc = zlib.crc32(host)
    hits = watch_restart(rig)
    off = 0
    while off < BLK:
        n = min(400, BLK - off)
        st, d = rig.ask('WRITE_BLOCK', OK2 + struct.pack('<HHI', off, BLK, crc) + host[off:off + n], timeout=5.0)
        off += n
    check(st == S_OK, 'last chunk: status %d' % st)
    check_restart(rig, hits, REQ_RESTART, 'WRITE_BLOCK')
    for base in (SET_A, SET_B):
        check(rig.m.get(base, BLK) == english(host), 'copy 0x%08X is not the host block with 1 / 1' % base)
    check_english_copies(rig, 'WRITE_BLOCK')
    check_english_ram(rig, 'after the restart')
    check(rig.rd(0x20001158) == 70 and rig.rd(V_SCREEN) == 1, 'restarted: brightness %d screen %d'
          % (rig.rd(0x20001158), rig.rd(V_SCREEN)))
    a = rig.m.get(SET_A, 0x1000)
    # V1.1 (vendor/LC1020E_V1.1_250702.bin) on that copy A: 0x08014B74 copies 0xC14 bytes from
    # 0x0807F000; with 0x20001140 = 1 it skips the chooser 0x080281F8 (screen 0)
    m = Meter(slots=(), records=(), starter=False, flash_mode='app', app=open(VENDOR_APP, 'rb').read())
    m.put(SET_A, a)
    m.set_timing(lsi_hz=T.LSI)
    m.attach(KeyPad())
    m.attach(MeasurePath(DutSource()))
    UsbDevice(m)
    m.start_app()
    end = m.run_for(seconds=3.0)
    check(end is None, 'V1.1 run ended %r (violations %r)' % (end, m.st['viol']))
    rd = lambda addr: struct.unpack('<I', bytes(m.uc.mem_read(addr, 4)))[0]
    check(rd(V_SCREEN) == 1 and rd(V_LANGUAGE) == 1 and rd(V_LANG_SET) == 1,
          'V1.1 on our copy A: screen %d language %d flag %d' % (rd(V_SCREEN), rd(V_LANGUAGE), rd(V_LANG_SET)))
    return True


# ---------------------------------------------------------------- the menu

@case
def l04_menu_six_items():
    """own_menu: 0 -> 2 -> 3 -> 4 -> 5 -> 6, clamped at 6; back to 0, clamped at 0; every redraw with
    the labels, the highlight, the shown rows and the values of the visible list; page 2 holds item 6
    alone; items 2, 3, 4 change their value with key 4; items 0, 5, 6 open their dialog (title of the
    item) and the long key 8 closes it."""
    rig = Ctl().up()
    calls = menu_calls(rig)
    enter_settings(rig)
    check(rig.rd(V_MENU) == 0, 'settings entered on item %d' % rig.rd(V_MENU))
    seq = []
    for key, want in [(KEY_ADD, n) for n in (2, 3, 4, 5, 6, 6)] + [(KEY_UP, n) for n in (5, 4, 3, 2, 0, 0)]:
        calls.clear()
        tap(rig,key)
        seq.append(rig.rd(V_MENU))
        check(len(calls.log['own_menu']) >= 1, 'key 0x%X: own_menu not run' % key)
        check_redraw(rig, calls, 'key 0x%X to item %d' % (key, want))
    want_seq = [2, 3, 4, 5, 6, 6, 5, 4, 3, 2, 0, 0]
    check(seq == want_seq, 'menu items %r, expected %r' % (seq, want_seq))
    # values: items 2 / 3 / 4, key 4 (fn_0800f5e8), shown at the next redraw
    for steps, addr, delta in ((1, V_BRIGHT, 10), (2, V_VOLUME, 10), (3, V_OFFTIME, 1)):
        goto_item(rig, VISIBLE[steps])
        v0 = rig.rd(addr)
        if (addr == V_OFFTIME and v0 >= 3) or (addr != V_OFFTIME and v0 > 90):
            tap(rig,KEY_DOWN10)
            v0 = rig.rd(addr)
        calls.clear()
        tap(rig,KEY_UP4)
        check(rig.rd(addr) == v0 + delta, 'item %d: 0x%08X %d -> %d' % (VISIBLE[steps], addr, v0, rig.rd(addr)))
        check_redraw(rig, calls, 'item %d after key 4' % VISIBLE[steps])
    # dialogs of items 0, 5, 6: title "%s%s" with the item's label (0x08009974, 0x20000078 + 4 n)
    for n in (0, 5, 6):
        goto_item(rig, n)
        calls.clear()
        tap(rig,KEY_OK)
        check(rig.rd(V_DIALOG) == 1 and rig.rd(V_MENU) == n and rig.rd(V_CAL_RUN) == 0,
              'item %d: dialog %d item %d cal %d' % (n, rig.rd(V_DIALOG), rig.rd(V_MENU), rig.rd(V_CAL_RUN)))
        titles = [text_at(rig, c[2]) for c in calls.log['fn_080228d0'] if text_at(rig, c[1]) == b'%s%s']
        want = text_at(rig, rig.rd(0x20000078 + 4 * n))
        check(want in titles, 'item %d: dialog title %r not among %r' % (n, want, titles))
        tap(rig,KEY_OK, 1200)
        check(rig.rd(V_DIALOG) == 0 and rig.rd(V_SCREEN) == 3 and rig.rd(V_MENU) == n,
              'item %d: dialog not closed (dialog %d screen %d)' % (n, rig.rd(V_DIALOG), rig.rd(V_SCREEN)))
    return True


@case
def l05_settings_set_ids_and_jobs():
    """SETTINGS_TABLES: 6 ids with English names; SETTINGS_SET for every id; SETUP_LANGUAGE answers
    status 1 and INFO has capability bit 20 clear (bit 21, the direct changes, set); COMPARE_SET sets the
    nominal (directly, no dialog); CALIBRATE
    reaches item 5's dialog and starts the calibration."""
    rig = Ctl().up()
    info = rig.ask_ok('INFO', size=INFO_SIZE)
    caps = struct.unpack_from('<I', info, 1)[0]
    check(caps == 0x0FEFFFFF and not caps >> 20 & 1, 'capabilities 0x%X' % caps)   # bits 22..24:
                                                     # MEASUREMENT_FIX_DESIGN.md stage 2 (revision 6),
                                                     # bit 25 the stage-3 sweep (revision 7), bit 26
                                                     # the own calibration area (ocal.s), bit 27 the
                                                     # start-up diagnostics (boot.s, revision 17)
    for p in (b'', b'\x00', b'\x01'):
        st, d = rig.ask('SETUP_LANGUAGE', p)
        check(st == S_UNKNOWN and not d, 'SETUP_LANGUAGE %r: status %d data %r' % (p, st, d))
    check(rig.ask_ok('SET_TABLES', size=1)[0] == 6, 'settings count')
    names = [b'Brightness', b'Volume', b'Off Time', b'Warn', b'Volume', b'LED']
    choices = {2: [b'NO', b'5min', b'15min', b'30min'], 3: [b'NG', b'OK']}
    addrs = [V_BRIGHT, V_VOLUME, V_OFFTIME, 0x2000116C, 0x20001170, 0x20001174]
    for i in range(6):
        d = rig.ask_ok('SET_TABLES', bytes([i]))
        lo, hi, step = struct.unpack_from('<III', d, 6)
        name = d[18:d.index(0, 18)]
        pos = d.index(0, 18) + 1
        n = d[pos]
        texts = d[pos + 1:].split(b'\0')[:n]
        check(d[0] == i and name == names[i] and texts == choices.get(i, []),
              'setting %d: name %r choices %r' % (i, name, texts))
        cur = rig.rd(addrs[i])
        want = lo + step if cur != lo + step else lo
        st, s = rig.ask('SET_SET', struct.pack('<BH', i, want), timeout=25.0)
        check(st == S_OK and rig.rd(addrs[i]) == want, 'SET_SET %d: status %d value %d, wanted %d'
              % (i, st, rig.rd(addrs[i]), want))
    check(rig.ask('SET_TABLES', b'\x06')[0] == S_BAD_ARG and rig.ask('SET_SET', struct.pack('<BH', 6, 0))[0] == S_BAD_ARG,
          'id 6 accepted')
    lcr = rig.ask_ok('LCR_TABLES', b'\x02')
    name, rest = lcr[3:].split(b'\0', 1)
    check(name == b'FREQ' and rest.startswith(b'Hz\0'), 'LCR list 2: name %r unit %r' % (name, rest[:3]))
    st, d = rig.ask('COMPARE_SET', struct.pack('<ffBBB', 2200.0, 1.0, 0, 0, 0))
    check(st == S_OK and abs(T.f32(rig.rd(V_NOMINAL)) - 2200.0) < 0.5, 'COMPARE_SET: status %d nominal %r'
          % (st, T.f32(rig.rd(V_NOMINAL))))
    rig.host.send(C['CALIBRATE'], b'\x00' + OK2)
    end = rig.m.run_for(seconds=30.0, until=lambda mm: rig.rd(V_CAL_RUN) != 0)
    check(end is None and rig.rd(V_CAL_RUN) != 0, 'CALIBRATE: calibration not started')
    check(rig.rd(V_SCREEN) == 3 and rig.rd(V_MENU) == 5 and rig.rd(V_DIALOG) == 1,
          'CALIBRATE: screen %d item %d dialog %d' % (rig.rd(V_SCREEN), rig.rd(V_MENU), rig.rd(V_DIALOG)))
    return True


@case
def l06_factory_suffix_and_omega():
    """Factory mode (0x200011C0 = 2): the settings title and a dialog title end in "(FACT)"; the glyph
    lookups of both fonts give U+03A9 its glyph (F1 75, F2 68) and no glyph to a CJK code point; the
    compare screen asks for U+03A9."""
    rig = Ctl().up()
    calls = Calls(rig, ('fn_080228d0', 'fn_08020968'))
    rig.wr(V_FACTORY, 2)
    tap(rig,0x0400, 1200)                          # compare screen (long 0x400)
    rig.run(0.5)
    check(rig.rd(V_SCREEN) == 2, 'compare screen not reached')
    letters = {c[2] for c in calls.log['fn_08020968']}
    check(0x3A9 in letters, 'U+03A9 not drawn on the compare screen (letters %r)' % sorted(letters)[:20])
    check(not [x for x in letters if 0x3000 <= x < 0xA000], 'CJK letters asked for: %r' % sorted(letters))
    tap(rig,0x0400, 1200)
    calls.clear()
    enter_settings(rig)
    tap(rig,KEY_OK)
    fact = [(text_at(rig, c[2]), text_at(rig, c[3])) for c in calls.log['fn_080228d0'] if text_at(rig, c[1]) == b'%s%s']
    check((b'SETTING', b'(FACT)') in fact and (b'Sorting', b'(FACT)') in fact, 'titles %r' % fact)
    fn_bitmap = rig.s['fn_08020894']
    f1, f2 = rig.s[F1], rig.s[F2]
    got = [rig.m.call(fn_bitmap, f1, 0x3A9), rig.m.call(fn_bitmap, f2, 0x3A9),
           rig.m.call(fn_bitmap, f1, 0x6D4B), rig.m.call(fn_bitmap, f2, 0x4E2D)]
    check(got == [rig.s[F1_BITMAPS] + 0x707, rig.s[F2_BITMAPS] + 0x9A6, 0, 0],
          'bitmaps of U+03A9 (F1, F2), U+6D4B (F1), U+4E2D (F2): %r' % [hex(x) if x is not None else None for x in got])
    return True


# ---------------------------------------------------------------- the freed bytes

@case
def l07_freed_bytes_never_read():
    """Every flash data read lands inside a kept piece: in our build the data 0x0802AE94..d_08051530
    is the kept pieces of V1.1 and the bytes left of the 18 freed ranges (check_pack.py PieceMap), so
    a read hook over those left bytes and over the typed RAM image (read only by copy_init at reset)
    sees no read through the measure screen, the compare screen, every settings item, the dialogs of
    items 0, 5, 6, the restore box and factory mode; a hook over a kept range of the same font data
    (F1 entries 0..75) sees reads (the hook works)."""
    rig = Ctl().up()
    reads, control = [], [0]
    pm = P.PieceMap()

    def hit(uc, access, addr, size, value, user):
        reads.append((addr, uc.reg_read(UC_ARM_REG_PC)))

    def ctl(uc, access, addr, size, value, user):
        control[0] += 1
    left = 0
    for a, b in FREED:
        r = (b - a + 1) % 4
        if r:
            at = pm.remainder_at(a)
            rig.m.uc.hook_add(UC_HOOK_MEM_READ, hit, begin=at, end=at + r - 1)
            left += r
    check(left == 14, 'bytes left of the freed ranges: %d' % left)
    img = rig.s['d_08051530']
    rig.m.uc.hook_add(UC_HOOK_MEM_READ, hit, begin=img, end=img + P.RAM_IMAGE_SIZE - 1)
    rig.m.uc.hook_add(UC_HOOK_MEM_READ, ctl, begin=rig.s[F1_ENTRIES], end=rig.s[F1_ENTRIES] + 0x25F)
    rig.wr(V_FACTORY, 2)
    rig.run(1.0)
    tap(rig,0x0400, 1200)
    rig.run(1.0)
    tap(rig,0x0400, 1200)
    enter_settings(rig)
    for n in VISIBLE:
        goto_item(rig, n)
        if n in (0, 5, 6):
            tap(rig, KEY_OK)
            check(rig.rd(V_DIALOG) == 1, 'item %d: dialog not open' % n)
            if n == 6:
                tap(rig, KEY_OK)                    # the restore box (byte 0x2000000C = 1)
                tap(rig, KEY_OK)                    # 0x200011B4 = 0: the box closes
            tap(rig, KEY_OK, 1200)
            check(rig.rd(V_DIALOG) == 0 and rig.rd(V_SCREEN) == 3, 'item %d: dialog not closed' % n)
    rig.run(0.5)
    check(control[0] > 0, 'control range never read: the read hook does not fire')
    check(not reads, '%d reads outside the kept pieces, first (address, pc) %r'
          % (len(reads), [(hex(a), hex(p)) for a, p in reads[:8]]))
    NOTES.append('l07: %d reads of the kept F1 entries, 0 of the bytes left of the freed ranges and of the '
                 'typed RAM image' % control[0])
    return True


@case
def l08_image_bytes():
    """APP_OWN.bin against V1.1 through the piece map: tests/check_pack.py checks P0 and C1..C4
    (every kept byte at its mapped address with its V1.1 value, the pointer words relocated, no raw
    address left, the typed RAM image, the bytes left of the freed ranges); here also the entry branch
    of fn_0800f294 (one of its listed sites) goes to own_menu."""
    NOTES.extend('l08: ' + n for n in P.run())
    o = open(OWN_BIN, 'rb').read()
    sym = own_image()[1]
    hw1, hw2 = struct.unpack_from('<HH', o, ENTRY_BRANCH - APP)
    check(hw1 >> 11 == 0x1E and hw2 >> 14 == 2 and hw2 >> 12 & 1, 'fn_0800f294 entry is not a b.w: %04x %04x' % (hw1, hw2))
    s = (hw1 >> 10) & 1
    j1, j2 = (hw2 >> 13) & 1, (hw2 >> 11) & 1
    i1, i2 = 1 - (j1 ^ s), 1 - (j2 ^ s)
    off = (s << 24 | i1 << 23 | i2 << 22 | (hw1 & 0x3FF) << 12 | (hw2 & 0x7FF) << 1)
    off -= (1 << 25) if s else 0
    target = ENTRY_BRANCH + 4 + off
    check(target == sym['own_menu'] & ~1, 'b.w target 0x%08X, own_menu 0x%08X' % (target, sym['own_menu']))
    check(any(a == ENTRY_BRANCH for a, _, _ in P.PATCHES), 'entry branch not a listed site')
    NOTES.append('l08: b.w at 0x0800F294 -> 0x%08X' % target)
    return True


@case
def l09_reset_path_ram_image():
    """Reset path of our build (PACKING_DESIGN.md 6): RAM 0x20000000..0x200163A7 filled with a
    pattern, the chip started at the reset vector and stopped at fn_08006260 (the call after
    __scatterload, 0x08007864). Then 0x20000000..0x2000057B equals the expected initial RAM image
    (check_pack.expected_ram: the unpacked V1.1 image, row 0 := row 1, flash words mapped; also the
    typed image in flash) and 0x2000057C..0x200163A7 is zero (region table entry 1)."""
    top = 0x200163A8                                   # initial SP set by fn_08006258
    pattern = {a: (a * 0x9E3779B1 | 1) & 0xFFFFFFFF for a in range(0x20000000, top, 4)}
    rig = Ctl(ram=pattern)
    m = rig.m
    m.watch(rig.s['fn_08006260'], 'fn_08006260', stop=True)
    end = m.run_for(1.0)
    check(end == 'at fn_08006260', 'reset path: end %r (violations %r)' % (end, m.st['viol']))
    want = P.expected_ram(rig.s)
    img = rig.s['d_08051530']
    check(m.get(img, P.RAM_IMAGE_SIZE) == want, 'typed image in flash differs from the expected image')
    got = m.ram[:P.RAM_IMAGE_SIZE]
    diff = [0x20000000 + i for i in range(0, P.RAM_IMAGE_SIZE, 4) if got[i:i + 4] != want[i:i + 4]]
    check(not diff, 'RAM image: %d words differ, first %r' % (len(diff), [hex(a) for a in diff[:8]]))
    zero = m.ram[P.RAM_IMAGE_SIZE:top - 0x20000000]
    nz = [0x20000000 + P.RAM_IMAGE_SIZE + i for i in range(0, len(zero), 4) if zero[i:i + 4] != bytes(4)]
    check(len(zero) == 0x15E2C and not nz, 'zero region: %d words not zero, first %r' % (len(nz), [hex(a) for a in nz[:8]]))
    NOTES.append('l09: reset to fn_08006260: 0x57C image bytes as expected, 0x15E2C bytes zero')
    return True


CASE_LIMIT_S = 900


class CaseTimeout(Exception):
    pass


def _alarm(signum, frame):
    raise CaseTimeout()


def main():
    signal.signal(signal.SIGALRM, _alarm)
    sel = sys.argv[1:]
    bad = run = 0
    for fn in CASES:
        if sel and not any(fn.__name__.startswith(p) for p in sel):
            continue
        run += 1
        signal.alarm(CASE_LIMIT_S)  # a case that does not end within its wall-clock limit fails
        try:
            ok = fn()
            msg = ''
        except AssertionError as e:
            ok, msg = False, str(e)
        except CaseTimeout:
            ok, msg = False, 'wall-clock limit of %d s passed' % CASE_LIMIT_S
        except Exception as e:      # a failing case must not hide the others
            ok, msg = False, 'raised %r' % e
        print('%-52s %s %s' % (fn.__name__, 'ok' if ok else 'FAIL', msg), flush=True)
        bad += not ok
    for n in NOTES + T.NOTES:
        print('  note:', n)
    print('%d tests, %d failed' % (run, bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
