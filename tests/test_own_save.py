#!/usr/bin/env python3
"""test_own_save.py - the settings / calibration storage of our application build (firmware/own/save.s).

Usage (from the repository root, after `make -C firmware own`):
    <python with unicorn 2.1.4> tests/test_own_save.py [case-name-prefix ...]

Specification: SETTINGS_SAVE_DESIGN.md revision 4 ("Save", "Load at start-up", "Held saves", "Tests")
and the interface comments of firmware/own/save.s and own.inc. The functions of the built image
(firmware/build/own/APP_OWN.bin at 0x08006000, symbols from app_own.elf) are called directly through
tests/meter_model.py in flash mode 'app' (the four settings pages are flash with controller semantics,
the application area is code; every other page is outside the gate of the model, so a stray write
is a violation of the model as well as of the test). Each call runs with SP = 0x200163A8 (the vendor
stack top, own.inc V_STACK_TOP); save.s uses at most 72 bytes of stack (its header).

Test data: settings blocks of 0xC14 bytes made by block(tag) below, never random: marker 0x12345678 at
0x000 and 0xC10 (own.inc BLK_MARKER), byte i (4 <= i < 0xC10) = (31 i + 7 tag) & 0xFF, and the four
words 0x200..0x20F = 0xFFFFFFFF (an erased value inside the block: flash_word leaves such a word as
it is, save.s "A word that already holds the value is left as it is"). Two tags give different
calibration tables (block offsets 0x04..0xB43). A copy in flash: the block, 0xFF up to 0xFF8, the
sequence at +0xFF8 and the CRC-32 (zlib.crc32 = the reflected 0xEDB88320 CRC of save.s
own_crc32_update) of the block bytes and the 4 sequence bytes at +0xFFC; copy A in the vendor
format has 0xFFFFFFFF in both trailer words (save.s header).

The expected result of a load is computed by ref_load() from the rules in the header of save.s
own_load (which follows SETTINGS_SAVE_DESIGN.md "Load at start-up"); the load-combination case checks
ref_load against the expectation written out per case, so a mistake in ref_load shows there.
"""
import struct
import sys
import zlib

from unicorn.arm_const import UC_ARM_REG_SP

from meter_model import Meter, SET_A, SET_B, PAGE, SETTINGS_PAGES, SLOTS, REC0, REC1, ERASE_CUTS, WORD_CUTS

CASES = []
NOTES = []

# own.inc
V_BLOCK, BLK = 0x2000057C, 0xC14
MARK_END, MARKER = 0xC10, 0x12345678
CAL_LO, CAL_END = 0x04, 0xB44
LANG_SET, LANGUAGE = 0xBC4, 0xBE0        # own.inc BLK_LANG_SET / BLK_LANGUAGE
TRL_SEQ, TRL_CRC, SET_SIZE = 0xFF8, 0xFFC, 0x1000
OWN_RAM = 0x20018000
OWN_STAGE = OWN_RAM + 0x2400
OWN_SAVE = OWN_RAM + 0x3020
FLAGS, STATUS, COUNT, LOADED, GATE = (OWN_SAVE + o for o in (0x00, 0x04, 0x08, 0x0C, 0x10))
OWN_INJECTED = OWN_RAM + 0x3120          # OWN_CTL + CTO_INJECTED
SP_TOP = 0x200163A8
SF_HELD, SF_DIFFERS, SF_NOVALID, SF_FAILED = 0x01, 0x02, 0x04, 0x08
SF_A_ONLY, SF_A_DAMAGED, SF_REWRITE_A, SF_RESTART = 0x10, 0x20, 0x40, 0x80
SV_OK, SV_HELD, SV_REFUSED, SV_MARK, SV_ERASE, SV_PROGRAM, SV_VERIFY, SV_BADBLOCK, SV_BADCOPY = range(9)
STEP_MARK, STEP_ERASE, STEP_PROGRAM, STEP_VERIFY, STEP_CHECK = 0x41, 0x42, 0x43, 0x44, 0x01
COPY_NONE, COPY_A, COPY_B = 0, 1, 2
FL_OK, FL_GATE, FL_NOT_ERASED = 0, 1, 2
SLOT_A, SLOT_B, SLOT_F = SLOTS[1], SLOTS[2], SLOTS[0]
PATTERNS = ('unchanged', 'ff', 'mixed')  # the cut patterns meter_model defines for erase and word alike
IWDG_PERIOD_MIN = 0.67                   # SETTINGS_SAVE_DESIGN.md "Held saves": every bound uses 0.67 s
FEED_BOUND = 0.12                        # design "Save" 5: about 120 ms between two feeds
RAM_CODE, RAM_VT = 0x2001F000, 0x2001F800  # above our RAM (ends 0x2001E000), below the no-init words
CORE_HZ_1MS = 144_000_000 // 1000        # meter_model CORE_HZ: SysTick reload of 1 ms


def case(fn):
    CASES.append(fn)
    return fn


def check(cond, text):
    if not cond:
        raise AssertionError(text)


def status(result, step=0, copy=0):
    """own_save_status layout (own.inc): result | step << 8 | copy << 16."""
    return result | step << 8 | copy << 16


def block(tag):
    """A test block: pattern bytes, both markers, an erased-value run at 0x200; the first-start flag
    (0xBC4) and the language word (0xBE0) 1, as save.s set_english stores them in every copy and in
    RAM (English only: a copy with other values is loaded and written with 1 / 1, test_own_lang.py)."""
    b = bytearray((31 * i + 7 * tag) & 0xFF for i in range(BLK))
    struct.pack_into('<I', b, 0, MARKER)
    struct.pack_into('<I', b, MARK_END, MARKER)
    b[0x200:0x210] = b'\xff' * 16
    struct.pack_into('<I', b, LANG_SET, 1)
    struct.pack_into('<I', b, LANGUAGE, 1)
    return bytes(b)


def copy_image(blk, seq=None, crc=None):
    """One copy (0x1000 bytes): block, 0xFF, trailer; seq None: vendor format (trailer 0xFF)."""
    img = bytearray(blk + b'\xff' * (SET_SIZE - len(blk)))
    if seq is not None:
        if crc is None:
            crc = zlib.crc32(blk + struct.pack('<I', seq))
        struct.pack_into('<II', img, TRL_SEQ, seq, crc)
    return bytes(img)


def w32(img, off):
    return struct.unpack_from('<I', img, off)[0]


def copy_state(img):
    """(markers, blank trailer, CRC matches, sequence) of one copy (save.s copy_check)."""
    markers = w32(img, 0) == MARKER and w32(img, MARK_END) == MARKER
    seq, crc = w32(img, TRL_SEQ), w32(img, TRL_CRC)
    blank = seq == 0xFFFFFFFF and crc == 0xFFFFFFFF
    crc_ok = markers and zlib.crc32(img[:BLK] + img[TRL_SEQ:TRL_SEQ + 4]) == crc
    return markers, blank, crc_ok, seq


def ref_load(a, b):
    """Expected (loaded copy, own_save_flags) of own_load for the copy images a (A) and b (B),
    from the header of save.s own_load."""
    am, ablank, acrc, aseq = copy_state(a)
    bm, bblank, bcrc, bseq = copy_state(b)
    a_valid = am and (ablank or acrc)
    a_vendor = am and ablank
    seq_a = aseq if a_valid and not a_vendor else 0
    b_valid = bcrc
    flags = 0
    if a_valid:
        loaded = COPY_A
        if b_valid:
            if not a_vendor and bseq > seq_a:
                loaded = COPY_B
                flags |= SF_A_ONLY
            if a[CAL_LO:CAL_END] != b[CAL_LO:CAL_END]:
                flags |= SF_DIFFERS
    elif b_valid:
        loaded = COPY_B
        flags |= SF_A_ONLY
        if w32(a, 0) == 0xFFFFFFFF:
            flags |= SF_REWRITE_A
        elif am:
            flags |= SF_HELD | SF_A_DAMAGED
    else:
        loaded = COPY_NONE
        flags = SF_HELD | SF_NOVALID
    return loaded, flags


class Rig:
    """Our build in flash mode 'app', copies A / B as given (None: erased), not yet loaded."""

    def __init__(self, a=None, b=None, boot_target=None, lsi=None):
        m = Meter(slots=(), records=(), starter=False, flash_mode='app', boot_target=boot_target)
        m.load_own()
        self.m, self.s = m, m.app_sym
        if a is not None:
            m.put(SET_A, a)
        if b is not None:
            m.put(SET_B, b)
        if lsi is not None:
            m.set_timing(lsi_hz=lsi)
        m.make()

    def call(self, name, *args, expect_return=True):
        m = self.m
        m.uc.reg_write(UC_ARM_REG_SP, SP_TOP)
        r = m.call(self.s[name], *args)
        if expect_return:
            check(r is not None, '%s did not return: end %r, violations %r' % (name, m.st['end'], m.st['viol']))
            check(not m.st['viol'], '%s: violation %r' % (name, m.st['viol']))
        return r

    def rd(self, addr, n=4):
        data = bytes(self.m.uc.mem_read(addr, n))
        return struct.unpack('<I', data)[0] if n == 4 else data

    def wr(self, addr, data):
        self.m.uc.mem_write(addr, data if isinstance(data, bytes) else struct.pack('<I', data))

    def load(self):
        """As the vendor start does: zero fill of the block (0x2000057C, 0x4BA4 bytes; only the
        block matters here), then own_load."""
        self.wr(V_BLOCK, bytes(BLK))
        self.call('own_load')

    def ram_block(self):
        return self.rd(V_BLOCK, BLK)

    def flags(self):
        return self.rd(FLAGS)

    def status(self):
        return self.rd(STATUS)

    def copy(self, base):
        return self.m.get(base, SET_SIZE)

    def ops(self):
        return self.m.flash_ops()

    def clear_log(self):
        del self.m.st['log'][:]


def in_copy(addr, base):
    return base <= addr < base + SET_SIZE


def valid_copy(img, blk, seq):
    return img == copy_image(blk, seq)


# ---------------------------------------------------------------- load combinations

@case
def s01_every_load_combination():
    """Every combination of SETTINGS_SAVE_DESIGN.md "Load": expected values written out from the
    header of save.s own_load; ref_load must agree with each."""
    b1, b2 = block(1), block(2)
    erased = b'\xff' * SET_SIZE
    damaged = bytearray(copy_image(b1, 5))
    damaged[0x300] ^= 0x01                       # both markers kept, CRC no longer matches
    damaged = bytes(damaged)
    no_end_marker = bytearray(copy_image(b1, 5))
    struct.pack_into('<I', no_end_marker, MARK_END, 0xFFFFFFFF)   # cut while programming
    no_end_marker = bytes(no_end_marker)
    first_ff = bytearray(copy_image(b1, 5))
    first_ff[0:0x800] = b'\xff' * 0x800          # first page erased: "looks interrupted"
    first_ff = bytes(first_ff)
    b_markers_bad_crc = copy_image(b2, 9, crc=0x12345678)
    b_vendor = copy_image(b2)                    # B never has the vendor format: invalid
    combos = [
        # name, A, B, loaded, flags, RAM block from
        ('A seq 5 > B seq 4', copy_image(b1, 5), copy_image(b1, 4), COPY_A, 0, b1),
        ('A seq 4 < B seq 5', copy_image(b1, 4), copy_image(b1, 5), COPY_B, SF_A_ONLY, b1),
        ('equal sequences -> A', copy_image(b1, 7), copy_image(b2, 7), COPY_A, SF_DIFFERS, b1),
        ('A newer, tables differ', copy_image(b1, 8), copy_image(b2, 7), COPY_A, SF_DIFFERS, b1),
        ('B newer, tables differ', copy_image(b1, 7), copy_image(b2, 8), COPY_B, SF_A_ONLY | SF_DIFFERS, b2),
        ('A vendor, B valid newer', copy_image(b1), copy_image(b1, 9), COPY_A, 0, b1),
        ('A vendor, B differs', copy_image(b1), copy_image(b2, 9), COPY_A, SF_DIFFERS, b1),
        ('A vendor, B erased', copy_image(b1), erased, COPY_A, 0, b1),
        ('A valid, B erased', copy_image(b1, 3), erased, COPY_A, 0, b1),
        ('A valid, B markers CRC wrong', copy_image(b1, 3), b_markers_bad_crc, COPY_A, 0, b1),
        ('A valid, B vendor format', copy_image(b1, 3), b_vendor, COPY_A, 0, b1),
        ('A erased, B valid', erased, copy_image(b2, 4), COPY_B, SF_A_ONLY | SF_REWRITE_A, b2),
        ('A first page erased, B valid', first_ff, copy_image(b2, 4), COPY_B, SF_A_ONLY | SF_REWRITE_A, b2),
        ('A damaged with markers, B valid', damaged, copy_image(b2, 4), COPY_B,
         SF_A_ONLY | SF_HELD | SF_A_DAMAGED, b2),
        ('A without end marker, B valid', no_end_marker, copy_image(b2, 4), COPY_B, SF_A_ONLY, b2),
        ('neither: both erased', erased, erased, COPY_NONE, SF_HELD | SF_NOVALID, None),
        ('neither: A damaged, B bad CRC', damaged, b_markers_bad_crc, COPY_NONE, SF_HELD | SF_NOVALID, None),
    ]
    for name, a, b, loaded, flags, src in combos:
        check(ref_load(a, b) == (loaded, flags), '%s: ref_load %r, written expectation %r'
              % (name, ref_load(a, b), (loaded, flags)))
        rig = Rig(a, b)
        rig.wr(GATE, SLOT_A)                         # own_load closes the BOOT gate
        rig.wr(STATUS, 0x55)                         # and clears the status
        rig.load()
        check(not rig.ops(), '%s: own_load wrote flash %r' % (name, rig.ops()[:3]))
        got = (rig.rd(LOADED), rig.flags())
        check(got == (loaded, flags), '%s: loaded / flags %r, expected %r' % (name, got, (loaded, flags)))
        check(rig.rd(GATE) == 0 and rig.status() == 0, '%s: gate %r status %r' % (name, rig.rd(GATE), rig.status()))
        if src is None:
            check(rig.ram_block() == bytes(BLK), '%s: RAM block not left zero with word 0 = 0' % name)
        else:
            check(rig.ram_block() == src, '%s: RAM block is not the loaded copy' % name)
    return True


# ---------------------------------------------------------------- a normal save

def loaded_rig(a, b, **kw):
    rig = Rig(a, b, **kw)
    rig.load()
    return rig


@case
def s02_save_writes_b_then_a():
    b1, b2 = block(1), block(2)
    rig = loaded_rig(copy_image(b1, 5), copy_image(b1, 4))
    check(rig.flags() == 0, 'flags after load 0x%X' % rig.flags())
    rig.wr(V_BLOCK, b2)
    rig.clear_log()
    r = rig.call('own_save')
    check(r == SV_OK and rig.status() == SV_OK and rig.rd(COUNT) == 1, 'status %r / %r count %r'
          % (r, rig.status(), rig.rd(COUNT)))
    ops = rig.ops()
    erases = [x[1] for x in ops if x[0] == 'erase']
    check(erases == [SET_B, SET_B + PAGE, SET_A, SET_A + PAGE], 'erase order %r' % [hex(e) for e in erases])
    last_b = max(k for k, x in enumerate(ops) if in_copy(x[1], SET_B))
    first_a = min(k for k, x in enumerate(ops) if in_copy(x[1], SET_A))
    check(last_b < first_a, 'A touched before B was finished')
    for base in (SET_B, SET_A):
        words = [x for x in ops if x[0] == 'word' and in_copy(x[1], base)]
        check(words[0][1] == base + TRL_SEQ and words[-1][1] == base + TRL_CRC,
              'copy 0x%08X: trailer sequence first, CRC last: %r %r' % (base, words[0], words[-1]))
        addrs = [x[1] for x in words[1:-1]]
        check(addrs == sorted(addrs), 'copy 0x%08X: block not in ascending order' % base)
        check(base + 0x200 not in addrs, 'copy 0x%08X: an erased-value word was programmed' % base)
        check(valid_copy(rig.copy(base), b2, 6), 'copy 0x%08X is not block 2 with sequence 6' % base)
    check(rig.flags() == 0, 'flags after the save 0x%X' % rig.flags())
    return True


# ---------------------------------------------------------------- power cut after every operation

def replay(pages, ops, n, pat):
    """Flash of the four settings pages after ops[:n] completed and ops[n] cut with pattern pat
    (meter_model ERASE_CUTS / WORD_CUTS); n = len(ops): no cut."""
    fl = {p: bytearray(pages[p]) for p in SETTINGS_PAGES}

    def page_of(a):
        return a & ~(PAGE - 1)
    for x in ops[:n]:
        if x[0] == 'erase':
            fl[x[1]][:] = b'\xff' * PAGE
        else:
            struct.pack_into('<I', fl[page_of(x[1])], x[1] - page_of(x[1]), x[2])
    if n < len(ops):
        x = ops[n]
        if x[0] == 'erase':
            fl[x[1]][:] = ERASE_CUTS[pat](bytes(fl[x[1]]))
        else:
            p = fl[page_of(x[1])]
            o = x[1] - page_of(x[1])
            struct.pack_into('<I', p, o, WORD_CUTS[pat](struct.unpack_from('<I', p, o)[0], x[2]) & 0xFFFFFFFF)
    return {p: bytes(fl[p]) for p in SETTINGS_PAGES}


def pages_of(m):
    return {p: m.get(p, PAGE) for p in SETTINGS_PAGES}


def ab(pages):
    return pages[SET_A] + pages[SET_A + PAGE], pages[SET_B] + pages[SET_B + PAGE]


CUT_SCENARIOS = [
    # name, A, B, block saved; sequences follow from the save rules (highest valid + 1)
    ('A and B valid (B, then A)', lambda: copy_image(block(1), 5), lambda: copy_image(block(1), 4), 2),
    ('A vendor format, B erased (B, mark, A)', lambda: copy_image(block(1)), lambda: b'\xff' * SET_SIZE, 2),
    ('B loaded, A erased (A only)', lambda: b'\xff' * SET_SIZE, lambda: copy_image(block(1), 3), 2),
]


@case
def s03_power_cut_after_every_flash_operation():
    """For each scenario: the operation log of one complete save; then every operation n cut in the
    middle with each pattern of PATTERNS (and the state after the last one): the next own_load must
    find a valid copy holding either the block before the save or the saved block, and its result
    must equal ref_load of that flash. A cut during an operation followed by nothing is the same
    flash as a cut in the middle of the next one with pattern 'unchanged', so 'after every
    operation' is covered as well."""
    loader = Rig()                               # one made chip; its settings pages are mmio over
    total = 0                                    # m.flash, so they are replaced in place
    for name, mk_a, mk_b, tag in CUT_SCENARIOS:
        rig = loaded_rig(mk_a(), mk_b())
        old = rig.ram_block()
        new = block(tag)
        rig.wr(V_BLOCK, new)
        before = pages_of(rig.m)
        rig.clear_log()
        check(rig.call('own_save') == SV_OK, '%s: the uncut save failed: 0x%X' % (name, rig.status()))
        ops = list(rig.ops())
        check(replay(before, ops, len(ops), None) == pages_of(rig.m), '%s: replay of the log differs' % name)
        for n in range(len(ops) + 1):
            for pat in (PATTERNS if n < len(ops) else (None,)):
                pages = replay(before, ops, n, pat)
                for p in SETTINGS_PAGES:
                    loader.m.flash[p - 0x08000000:p - 0x08000000 + PAGE] = pages[p]
                loader.clear_log()
                loader.load()
                a, b = ab(pages)
                exp = ref_load(a, b)
                got = (loader.rd(LOADED), loader.flags())
                what = '%s: cut in op %d of %d (%r, %s)' % (name, n, len(ops), ops[n] if n < len(ops) else 'none', pat)
                check(got == exp, '%s: loaded / flags %r, ref_load %r' % (what, got, exp))
                check(exp[0] != COPY_NONE, '%s: no valid copy left' % what)
                check(loader.ram_block() in (old, new), '%s: loaded block is neither the old nor the new' % what)
                total += 1
        NOTES.append('s03 %s: %d flash operations' % (name, len(ops)))
    NOTES.append('s03: %d loads after cuts' % total)
    return True


@case
def s04_real_cut_matches_replay():
    """The replay of s03 against the model's own cut (Meter.cut_pattern, run(cut_after)) for every
    erase, the first and the last operation of each copy, with each pattern."""
    for name, mk_a, mk_b, tag in CUT_SCENARIOS:
        ref = loaded_rig(mk_a(), mk_b())
        ref.wr(V_BLOCK, block(tag))
        before = pages_of(ref.m)
        ref.clear_log()
        ref.call('own_save')
        ops = list(ref.ops())
        picks = {k for k, x in enumerate(ops) if x[0] == 'erase'}
        for base in (SET_A, SET_B):
            ks = [k for k, x in enumerate(ops) if in_copy(x[1], base)]
            if ks:
                picks |= {ks[0], ks[-1]}
        for n in sorted(picks):
            for pat in PATTERNS:
                rig = loaded_rig(mk_a(), mk_b())
                rig.wr(V_BLOCK, block(tag))
                rig.m.cut_pattern = pat
                rig.m.st['cut_after'] = n + 1
                rig.call('own_save', expect_return=False)
                check(rig.m.st['end'] == 'cut', '%s op %d %s: end %r' % (name, n, pat, rig.m.st['end']))
                check(pages_of(rig.m) == replay(before, ops, n, pat), '%s op %d %s: model cut differs from replay'
                      % (name, n, pat))
    return True


@case
def s05_save_after_a_cut_recovers():
    """After a cut in any erase (each pattern): load, save_resume, then an ordinary save; afterwards
    a load finds the newest block (the second save's) and no flag but SF_A_ONLY / SF_DIFFERS."""
    for name, mk_a, mk_b, tag in CUT_SCENARIOS:
        ref = loaded_rig(mk_a(), mk_b())
        ref.wr(V_BLOCK, block(tag))
        before = pages_of(ref.m)
        ref.clear_log()
        ref.call('own_save')
        ops = list(ref.ops())
        for n in [k for k, x in enumerate(ops) if x[0] == 'erase']:
            for pat in PATTERNS:
                pages = replay(before, ops, n, pat)
                a, b = ab(pages)
                rig = loaded_rig(a, b)
                held = rig.flags() & SF_HELD
                rig.call('save_resume')
                rig.wr(V_BLOCK, block(9))
                r = rig.call('own_save')
                what = '%s erase op %d %s' % (name, n, pat)
                if held:
                    check(r == SV_HELD, '%s: held after load, own_save %r' % (what, r))
                    continue
                check(r == SV_OK, '%s: second save 0x%X' % (what, rig.status()))
                again = loaded_rig(rig.copy(SET_A), rig.copy(SET_B))
                check(again.ram_block() == block(9), '%s: newest block not loaded' % what)
                check(not again.flags() & ~(SF_A_ONLY | SF_DIFFERS), '%s: flags 0x%X' % (what, again.flags()))
    return True


# ---------------------------------------------------------------- stuck bits, erase failure

def zero_bit(v):
    """Lowest bit that is 0 in v: stuck at 1 there, the word cannot be programmed to v."""
    check(v != 0xFFFFFFFF, 'word is erased')
    return ~v & (v + 1) & 0xFFFFFFFF


@case
def s06_stuck_bit_in_b():
    b1, b2 = block(1), block(2)
    rig = loaded_rig(copy_image(b1, 5), copy_image(b1, 4))
    rig.m.stuck[SET_B + 0x100] = zero_bit(w32(b2, 0x100))
    rig.wr(V_BLOCK, b2)
    rig.clear_log()
    r = rig.call('own_save')
    # flash_word reads back -> FL_VERIFY, write_copy: SV_PROGRAM | STEP_PROGRAM, retried once from
    # (b), save_stage adds COPY_B; A is not touched (design "Save" 4)
    check(r == status(SV_PROGRAM, STEP_PROGRAM, COPY_B), 'status 0x%X' % r)
    check(rig.flags() & SF_FAILED, 'SF_FAILED not set: 0x%X' % rig.flags())
    ops = rig.ops()
    check(not [x for x in ops if in_copy(x[1], SET_A)], 'copy A touched: %r' % [x for x in ops if in_copy(x[1], SET_A)][:3])
    erases = [x[1] for x in ops if x[0] == 'erase']
    check(erases == [SET_B, SET_B + PAGE] * 2, 'B erases %r (one retry from (b))' % [hex(e) for e in erases])
    again = loaded_rig(rig.copy(SET_A), rig.copy(SET_B))
    check(again.rd(LOADED) == COPY_A and again.ram_block() == b1 and again.flags() == 0,
          'after the failed save: loaded %d flags 0x%X' % (again.rd(LOADED), again.flags()))
    return True


@case
def s07_stuck_bit_in_a():
    b1, b2 = block(1), block(2)
    rig = loaded_rig(copy_image(b1, 5), copy_image(b1, 4))
    rig.m.stuck[SET_A + 0x100] = zero_bit(w32(b2, 0x100))
    rig.wr(V_BLOCK, b2)
    rig.clear_log()
    r = rig.call('own_save')
    check(r == status(SV_PROGRAM, STEP_PROGRAM, COPY_A), 'status 0x%X' % r)
    check(rig.flags() & SF_FAILED, 'SF_FAILED not set')
    check(valid_copy(rig.copy(SET_B), b2, 6), 'B does not hold the new block with sequence 6')
    erases = [x[1] for x in rig.ops() if x[0] == 'erase']
    check(erases == [SET_B, SET_B + PAGE] + [SET_A, SET_A + PAGE] * 2, 'erases %r' % [hex(e) for e in erases])
    # A: block programmed up to the stuck word (its marker at 0 present, the end marker not),
    # first word not 0xFFFFFFFF: "cut while it was being programmed" -> B, A only, no hold
    again = loaded_rig(rig.copy(SET_A), rig.copy(SET_B))
    check(again.rd(LOADED) == COPY_B and again.flags() == SF_A_ONLY and again.ram_block() == b2,
          'after: loaded %d flags 0x%X' % (again.rd(LOADED), again.flags()))
    return True


@case
def s08_erase_failure_in_b():
    b1, b2 = block(1), block(2)
    rig = loaded_rig(copy_image(b1, 5), copy_image(b1, 4))
    rig.m.erase_fail.add(SET_B)                  # the erase leaves word 0 = 0 (meter_model)
    rig.wr(V_BLOCK, b2)
    rig.clear_log()
    r = rig.call('own_save')
    check(r == status(SV_ERASE, STEP_ERASE, COPY_B), 'status 0x%X' % r)
    erases = [x[1] for x in rig.ops() if x[0] == 'erase']
    check(erases == [SET_B, SET_B], 'erases %r' % [hex(e) for e in erases])
    check(rig.copy(SET_A) == copy_image(b1, 5), 'A changed')
    return True


# ---------------------------------------------------------------- trailer mark

@case
def s09_trailer_mark_failure_stops_before_any_erase():
    b1, b2 = block(1), block(2)
    rig = loaded_rig(copy_image(b1), b'\xff' * SET_SIZE)      # A vendor format, B erased
    check(rig.flags() == 0 and rig.rd(LOADED) == COPY_A, 'load: flags 0x%X' % rig.flags())
    # new sequence = 0 (vendor A) + 1 = 1; bit 1 stuck: the mark reads back 3
    rig.m.stuck[SET_A + TRL_SEQ] = 0x2
    rig.wr(V_BLOCK, b2)
    rig.clear_log()
    r = rig.call('own_save')
    check(r == status(SV_MARK, STEP_MARK, COPY_A), 'status 0x%X' % r)
    a_ops = [x for x in rig.ops() if in_copy(x[1], SET_A)]
    check(a_ops == [('word', SET_A + TRL_SEQ, 1)], 'copy A operations %r (only the mark)' % a_ops)
    check(rig.copy(SET_A)[:BLK] == b1, 'A block changed')
    check(valid_copy(rig.copy(SET_B), b2, 1), 'B (written first) is not block 2 with sequence 1')
    # the next load: A has both markers, trailer 3 / 0xFFFFFFFF (CRC wrong) -> held, B loaded
    again = loaded_rig(rig.copy(SET_A), rig.copy(SET_B))
    check(again.flags() == SF_A_ONLY | SF_HELD | SF_A_DAMAGED and again.rd(LOADED) == COPY_B,
          'after: flags 0x%X loaded %d' % (again.flags(), again.rd(LOADED)))
    return True


@case
def s10_first_save_on_vendor_format():
    """V1.1's copy A, B erased: B, then the mark, then A (design "Save" 4 (a))."""
    b1, b2 = block(1), block(2)
    rig = loaded_rig(copy_image(b1), b'\xff' * SET_SIZE)
    rig.wr(V_BLOCK, b2)
    rig.clear_log()
    check(rig.call('own_save') == SV_OK, 'status 0x%X' % rig.status())
    ops = rig.ops()
    a_first = next(x for x in ops if in_copy(x[1], SET_A))
    check(a_first == ('word', SET_A + TRL_SEQ, 1), 'first A operation %r, expected the mark' % (a_first,))
    for base in (SET_A, SET_B):
        check(valid_copy(rig.copy(base), b2, 1), 'copy 0x%08X' % base)
    return True


# ---------------------------------------------------------------- held saves and the guard

@case
def s11_held_saves():
    b1, b2 = block(1), block(2)
    erased = b'\xff' * SET_SIZE
    damaged = bytearray(copy_image(b1, 5))
    damaged[0x300] ^= 1
    for name, a, b, flags in (('neither valid', erased, erased, SF_HELD | SF_NOVALID),
                              ('A damaged with markers', bytes(damaged), copy_image(b2, 4),
                               SF_HELD | SF_A_DAMAGED | SF_A_ONLY)):
        rig = loaded_rig(a, b)
        check(rig.flags() == flags, '%s: flags 0x%X' % (name, rig.flags()))
        rig.wr(V_BLOCK, b2)                     # e.g. the defaults 0x0800B4C8(1) wrote
        rig.clear_log()
        r = rig.call('own_save')
        check(r == SV_HELD and rig.status() == SV_HELD and rig.rd(COUNT) == 1, '%s: status %r' % (name, r))
        check(not rig.ops(), '%s: wrote %r' % (name, rig.ops()[:3]))
        check(rig.copy(SET_A) == a and rig.copy(SET_B) == b, '%s: flash changed' % name)
        check(rig.flags() == flags, '%s: flags changed to 0x%X' % (name, rig.flags()))
    # A interrupted: not held, ordinary saves write A only
    rig = loaded_rig(erased, copy_image(b1, 4))
    rig.wr(V_BLOCK, b2)
    rig.clear_log()
    check(rig.call('own_save') == SV_OK, 'interrupted A: status 0x%X' % rig.status())
    check(not [x for x in rig.ops() if in_copy(x[1], SET_B)], 'interrupted A: B touched')
    check(valid_copy(rig.copy(SET_A), b2, 5), 'interrupted A: A not block 2 with sequence 5')
    check(not rig.flags() & SF_REWRITE_A, 'SF_REWRITE_A not cleared by the save')
    return True


@case
def s12_guard_refuses():
    b1 = block(1)
    rig = loaded_rig(copy_image(b1, 5), copy_image(b1, 4))
    rig.wr(OWN_INJECTED, 1)
    rig.wr(V_BLOCK, block(2))
    rig.clear_log()
    r = rig.call('own_save')
    check(r == SV_REFUSED and rig.status() == SV_REFUSED, 'status %r' % r)
    check(not rig.ops() and rig.flags() == 0, 'wrote %r flags 0x%X' % (rig.ops()[:2], rig.flags()))
    return True


# ---------------------------------------------------------------- recovery functions

@case
def s13_save_resume():
    b1 = block(1)
    rig = loaded_rig(b'\xff' * SET_SIZE, copy_image(b1, 4))
    check(rig.flags() == SF_A_ONLY | SF_REWRITE_A, 'flags 0x%X' % rig.flags())
    rig.clear_log()
    r = rig.call('save_resume')
    check(r == SV_OK and rig.rd(COUNT) == 1, 'status 0x%X' % r)
    check(valid_copy(rig.copy(SET_A), b1, 4), 'A not rewritten from B with B\'s sequence')
    check(not [x for x in rig.ops() if in_copy(x[1], SET_B)], 'B touched')
    check(rig.flags() == SF_A_ONLY, 'flags 0x%X (only SF_REWRITE_A cleared, save.s save_resume)' % rig.flags())
    check(rig.call('save_resume') == 0xFFFFFFFF and rig.rd(COUNT) == 1, 'second call did something')
    again = loaded_rig(rig.copy(SET_A), rig.copy(SET_B))
    check(again.rd(LOADED) == COPY_A and again.flags() == 0, 'equal sequences: loaded %d flags 0x%X'
          % (again.rd(LOADED), again.flags()))
    return True


@case
def s14_accept_b():
    b1, b2 = block(1), block(2)
    damaged = bytearray(copy_image(b1, 5))
    damaged[0x300] ^= 1
    rig = loaded_rig(copy_image(b1, 5), copy_image(b1, 4))
    check(rig.call('save_accept_b') == SV_REFUSED and not rig.ops(), 'not damaged: not refused')
    rig = loaded_rig(bytes(damaged), copy_image(b2, 4))
    rig.clear_log()
    r = rig.call('save_accept_b')
    check(r == SV_OK, 'status 0x%X' % r)
    check(valid_copy(rig.copy(SET_A), b2, 4), 'A not rewritten from B')
    check(rig.flags() == SF_A_ONLY, 'flags 0x%X' % rig.flags())
    rig.wr(V_BLOCK, block(3))
    check(rig.call('own_save') == SV_OK, 'save after accept_b: 0x%X' % rig.status())
    return True


@case
def s15_accept_defaults():
    erased = b'\xff' * SET_SIZE
    rig = loaded_rig(copy_image(block(1), 5), erased)
    check(rig.call('save_accept_defaults') == SV_REFUSED, 'with a valid copy: not refused')
    rig = loaded_rig(erased, erased)
    rig.clear_log()
    r = rig.call('save_accept_defaults')        # RAM block: word 0 = 0 after the load
    check(r == status(SV_BADBLOCK, STEP_CHECK) and not rig.ops(), 'no markers: 0x%X' % r)
    defaults = block(4)
    rig.wr(V_BLOCK, defaults)
    r = rig.call('save_accept_defaults')
    check(r == SV_OK, 'status 0x%X' % r)
    for base in (SET_B, SET_A):
        check(valid_copy(rig.copy(base), defaults, 1), 'copy 0x%08X' % base)
    check(rig.flags() == 0, 'flags 0x%X' % rig.flags())
    return True


@case
def s16_write_block():
    erased = b'\xff' * SET_SIZE
    host = block(5)
    rig = loaded_rig(erased, erased)
    rig.wr(OWN_STAGE, host)
    rig.clear_log()
    r = rig.call('save_write_block', zlib.crc32(host) ^ 1)
    check(r == status(SV_BADBLOCK, STEP_CHECK) and not rig.ops(), 'wrong CRC: 0x%X' % r)
    bad = bytearray(host)
    struct.pack_into('<I', bad, MARK_END, 0)
    rig.wr(OWN_STAGE, bytes(bad))
    r = rig.call('save_write_block', zlib.crc32(bytes(bad)))
    check(r == status(SV_BADBLOCK, STEP_CHECK) and not rig.ops(), 'no end marker: 0x%X' % r)
    rig.wr(OWN_STAGE, host)
    r = rig.call('save_write_block', zlib.crc32(host))
    check(r == SV_OK, 'status 0x%X' % r)
    for base in (SET_B, SET_A):
        check(valid_copy(rig.copy(base), host, 1), 'copy 0x%08X' % base)
    check(rig.flags() == SF_RESTART, 'flags 0x%X' % rig.flags())
    rig.clear_log()
    check(rig.call('own_save') == SV_HELD and not rig.ops(), 'restart pending: save not held')
    return True


@case
def s17_restore_b_and_accept_a():
    b1, b2 = block(1), block(2)
    # A loaded (newer), B differs
    rig = loaded_rig(copy_image(b1, 8), copy_image(b2, 7))
    check(rig.flags() == SF_DIFFERS, 'flags 0x%X' % rig.flags())
    rig.clear_log()
    r = rig.call('save_restore_b')
    check(r == SV_OK and valid_copy(rig.copy(SET_A), b2, 7), 'restore_b: 0x%X' % r)
    check(not [x for x in rig.ops() if in_copy(x[1], SET_B)], 'restore_b touched B')
    check(rig.flags() == SF_RESTART, 'restore_b flags 0x%X' % rig.flags())
    rig = loaded_rig(copy_image(b1, 8), copy_image(b2, 7))
    rig.clear_log()
    r = rig.call('save_accept_a')
    check(r == SV_OK and valid_copy(rig.copy(SET_B), b1, 8), 'accept_a: 0x%X' % r)
    check(not [x for x in rig.ops() if in_copy(x[1], SET_A)], 'accept_a touched A')
    check(rig.flags() == 0, 'accept_a flags 0x%X (A was loaded: no restart)' % rig.flags())
    # B loaded (A invalid without hold): accept_a has no valid A
    rig = loaded_rig(b'\xff' * SET_SIZE, copy_image(b2, 7))
    check(rig.call('save_accept_a') == status(SV_BADCOPY, STEP_CHECK), 'accept_a without valid A')
    # refusals: neither flag, or held
    rig = loaded_rig(copy_image(b1, 8), copy_image(b1, 7))
    check(rig.call('save_restore_b') == SV_REFUSED and rig.call('save_accept_a') == SV_REFUSED, 'no flag: not refused')
    damaged = bytearray(copy_image(b1, 5))
    damaged[0x300] ^= 1
    rig = loaded_rig(bytes(damaged), copy_image(b2, 4))
    rig.clear_log()
    check(rig.call('save_restore_b') == SV_REFUSED and rig.call('save_accept_a') == SV_REFUSED and not rig.ops(),
          'held: not refused')
    # restore_b with B gone bad after the load
    rig = loaded_rig(copy_image(b1, 8), copy_image(b2, 7))
    rig.m.flash[SET_B + 0x300 - 0x08000000] ^= 1
    check(rig.call('save_restore_b') == status(SV_BADCOPY, STEP_CHECK), 'restore_b without valid B')
    # accept_a with A in the vendor format: sequence highest valid + 1
    rig = loaded_rig(copy_image(b1), copy_image(b2, 7))
    check(rig.call('save_accept_a') == SV_OK and valid_copy(rig.copy(SET_B), b1, 8), 'accept_a vendor A')
    return True


# ---------------------------------------------------------------- flash primitives and the gate

@case
def s18_flash_gate():
    rig = Rig(boot_target='A')
    outside = [0x08000000, 0x08006000, 0x08061FFC, 0x08065FFC, 0x08067000, 0x08067FFC, SLOT_F,
               SLOT_A, SLOT_B, REC0, REC1 + PAGE - 4, 0x0807EFFC, 0x08080000, 0x1FFFF800, 0x20000000]
    for a in outside:
        r = rig.call('flash_word', a, 0x12345678)
        check(r == FL_GATE and not rig.ops(), 'flash_word 0x%08X: %r %r' % (a, r, rig.ops()))
        r = rig.call('flash_erase_page', a & ~(PAGE - 1))
        check(r == FL_GATE and not rig.ops(), 'flash_erase_page 0x%08X: %r' % (a, r))
    check(rig.call('flash_erase_page', SET_B + 4) == FL_GATE, 'misaligned page accepted')
    check(rig.call('flash_word', SET_B + 2, 0) == FL_GATE, 'misaligned word accepted')
    check(rig.call('flash_erase_page', SET_B + PAGE) == FL_OK and rig.ops() == [('erase', SET_B + PAGE)], 'B page 2')
    rig.clear_log()
    check(rig.call('flash_word', SET_B + PAGE, 0x11) == FL_OK and rig.ops() == [('word', SET_B + PAGE, 0x11)], 'word')
    rig.clear_log()
    check(rig.call('flash_word', SET_B + PAGE, 0x11) == FL_OK and not rig.ops(), 'same value programmed again')
    check(rig.call('flash_word', SET_B + PAGE, 0x22) == FL_NOT_ERASED and not rig.ops(), 'not erased: programmed')
    # BOOT part: only while opened, only slot A and the record pages
    check(rig.call('flash_boot_gate', SLOT_A) == FL_OK and rig.rd(GATE) == SLOT_A, 'gate A')
    for a, ok in ((SLOT_A, True), (SLOT_A + 0x5800, True), (REC0, True), (REC1, True), (SLOT_B, False),
                  (SLOT_F, False), (0x08006000, False)):
        rig.clear_log()
        r = rig.call('flash_erase_page', a)
        check((r == FL_OK) == ok and bool(rig.ops()) == ok, 'gate A, erase 0x%08X: %r %r' % (a, r, rig.ops()))
    check(rig.call('flash_boot_gate', SLOT_F) == FL_GATE and rig.rd(GATE) == 0, 'slot F opened the gate')
    rig.clear_log()
    check(rig.call('flash_erase_page', SLOT_A) == FL_GATE and not rig.ops(), 'closed gate erased slot A')
    check(rig.call('flash_boot_gate', 0) == FL_OK and rig.rd(GATE) == 0, 'close')
    return True


# ---------------------------------------------------------------- interrupt during a save

def thumb(*hws):
    return b''.join(struct.pack('<H', h) for h in hws)


# SysTick handler in RAM at RAM_CODE + 0x100 (4-aligned):
#   ldr r0, [pc, #8] (0x4802: literal at +12); ldr r1, [r0] (0x6801); adds r1, #1 (0x3101);
#   str r1, [r0] (0x6001); bx lr (0x4770); nop (0xBF00); .word V_BLOCK + 0x100
INC_HANDLER = thumb(0x4802, 0x6801, 0x3101, 0x6001, 0x4770, 0xBF00) + struct.pack('<I', V_BLOCK + 0x100)
# IWDG start as V1.1 0x08010178 does it (own.inc): at RAM_CODE
#   ldr r0,[pc,#20] (0x4805: base); ldr r1,[pc,#24] (0x4906: 0x5555); str r1,[r0] (0x6001);
#   movs r1,#2 (0x2102); str r1,[r0,#4] (0x6041); ldr r1,[pc,#20] (0x4905: 0x9C4);
#   str r1,[r0,#8] (0x6081); ldr r1,[pc,#20] (0x4905: 0xAAAA); str r1,[r0] (0x6001);
#   ldr r1,[pc,#20] (0x4905: 0xCCCC); str r1,[r0] (0x6001); bx lr (0x4770); literals at +24
IWDG_START = (thumb(0x4805, 0x4906, 0x6001, 0x2102, 0x6041, 0x4905, 0x6081, 0x4905, 0x6001, 0x4905,
                    0x6001, 0x4770) + struct.pack('<5I', 0x40003000, 0x5555, 0x9C4, 0xAAAA, 0xCCCC))


@case
def s19_interrupt_changes_live_block_during_save():
    b1 = block(1)
    rig = loaded_rig(copy_image(b1, 5), copy_image(b1, 4), lsi=60000)
    m = rig.m
    rig.wr(RAM_CODE + 0x100, INC_HANDLER)
    vt = bytearray(0x40)
    struct.pack_into('<I', vt, 4 * 15, (RAM_CODE + 0x100) | 1)
    rig.wr(RAM_VT, bytes(vt))
    m.scs[0xE000ED08] = RAM_VT                   # VTOR (meter_model reads the vector from there)
    # SysTick every 1 ms, processor clock, interrupt on (CSR 7); set in the model's SysTick state
    m.tm['st'].update(csr=7, rvr=CORE_HZ_1MS - 1, v0=0, t_ref=m.now(), done=0)
    v0 = w32(rig.ram_block(), 0x100)
    rig.clear_log()
    r = rig.call('own_save')
    check(r == SV_OK, 'status 0x%X' % r)
    staged = rig.rd(OWN_STAGE, BLK)
    ticks = m.tm['irq_count'].get(15, 0)
    v1 = w32(rig.ram_block(), 0x100)
    check(ticks > 0 and v1 != w32(staged, 0x100), 'no interrupt changed the live block during the save (%d)' % ticks)
    check(v0 <= w32(staged, 0x100) <= v1, 'snapshot word 0x%X outside %X..%X' % (w32(staged, 0x100), v0, v1))
    seq = 6
    for base in (SET_A, SET_B):
        check(valid_copy(rig.copy(base), staged, seq), 'copy 0x%08X is not the snapshot' % base)
    NOTES.append('s19: %d SysTick interrupts during the save; live word moved %d -> %d' % (ticks, v0, v1))
    return True


# ---------------------------------------------------------------- watchdog stretch of a whole save

def feeds_between(m, t0, t1):
    return [e for e in m.iwdg_log if e['kind'] == 'feed' and t0 <= e['t'] <= t1]


@case
def s20_watchdog_stretch_of_whole_saves():
    """IWDG started as V1.1 does (0x08010178); own_load, then saves with LSI 60 kHz (the shortest
    period 2501 * 16 / 60000 s): longest stretch between two counter loads below 0.12 s (design
    "Save" 5) and so below 0.67 s; the 16 feeds of a two-copy save: flash_erase_page feeds before
    and after each of the 4 erases, write_copy after the words at block offsets 0x400, 0x800, 0xC00
    (r5 a multiple of 0x400) and after the last word, per copy."""
    b1 = block(1)
    out = []
    for name, stuck in (('two copies', None), ('stuck bit in A (retry)', SET_A + 0x100)):
        rig = Rig(copy_image(b1, 5), copy_image(b1, 4), lsi=60000)
        m = rig.m
        rig.wr(RAM_CODE, IWDG_START)
        m.uc.reg_write(UC_ARM_REG_SP, SP_TOP)
        check(m.call(RAM_CODE) is not None, '%s: IWDG start routine: end %r' % (name, m.st['end']))
        check(m.tm['iw']['running'], '%s: IWDG not started' % name)
        rig.load()
        b2 = block(2)
        if stuck:
            m.stuck[stuck] = zero_bit(w32(b2, 0x100))
        rig.wr(V_BLOCK, b2)
        t0 = m.now()
        r = rig.call('own_save')
        t1 = m.now()
        check(r == (SV_OK if not stuck else status(SV_PROGRAM, STEP_PROGRAM, COPY_A)), '%s: status 0x%X' % (name, r))
        check(not [e for e in m.iwdg_log if e['kind'] == 'reset'], '%s: IWDG reset' % name)
        st = m.iwdg_stretch()
        longest = st['longest']['seconds']
        check(longest < FEED_BOUND and longest < IWDG_PERIOD_MIN, '%s: longest stretch %.4f s' % (name, longest))
        n = len(feeds_between(m, t0, t1))
        if not stuck:
            check(n == 16, '%s: %d feeds during the save, expected 16' % (name, n))
        out.append('%s %.1f ms (%d instructions), %d feeds, save %.3f s'
                   % (name, longest * 1e3, st['longest']['insns'], n, t1 - t0))
    NOTES.append('s20: ' + '; '.join(out))
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
            ok, msg = False, 'raised %r' % e
        print('%-52s %s %s' % (fn.__name__, 'ok' if ok else 'FAIL', msg), flush=True)
        bad += not ok
    for n in NOTES:
        print('  note:', n)
    print('%d tests, %d failed' % (run, bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
