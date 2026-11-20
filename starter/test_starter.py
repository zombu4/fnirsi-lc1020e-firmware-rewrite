#!/usr/bin/env python3
"""Emulator test of the starter (Unicorn, Cortex-M4 Thumb).

Usage: python3 test_starter.py build/starter.elf   (needs the unicorn module and arm-none-eabi-nm)

Model: flash 0x08000000..0x0807FFFF; the record pages 0x08068000..0x08068FFF are an mmio region
with flash semantics (erased = 0xFF, a word is programmed only while CTRL.PG = 1 and the flash is
unlocked, programming a word that is not erased sets PGERR and changes nothing, page erase by
CTRL.PER + ADD + START, LOCK by CTRL bit 7, unlocked by KEY1 / KEY2); every CPU write to other flash
addresses is an error. GPIOA / RCC / SCB are plain memory, the order of writes to PBSC and to the
flash controller is logged. A start ends when the PC enters a slot image (that slot was started),
or the dead-end loop. Power cuts: the run is stopped right after the N-th flash operation (erase or
word), then the starter runs again on the flash as it is; the second start must reach a slot.
"""
import struct
import subprocess
import sys
import zlib

from unicorn import Uc, UcError, UC_ARCH_ARM, UC_MODE_THUMB, UC_MODE_MCLASS, UC_HOOK_CODE, UC_HOOK_MEM_WRITE
from unicorn.arm_const import UC_ARM_REG_PC, UC_ARM_REG_SP

FLASH, FLASH_SIZE = 0x08000000, 0x80000
REC0, REC1, PAGE = 0x08068000, 0x08068800, 0x800
SLOTS = [0x08069000, 0x0806F000, 0x08075000]
SRAM, SRAM_SIZE = 0x20000000, 0x24000
FLAG, FLAG_MAGIC = 0x20002020, 0x464C5446
FCTRL = 0x40022000
ST_INSTALL, ST_TRIAL, ST_OK = 1, 2, 3


def symbols(elf):
    out = subprocess.run(['arm-none-eabi-nm', elf], capture_output=True, text=True, check=True).stdout
    return {l.split()[2]: int(l.split()[0], 16) for l in out.splitlines() if len(l.split()) == 3}


def slot_image(base, version=1, bad=None):
    """Slot: header at base, image at base + 0x200 = vector table (SP, reset) + 'b .' loop."""
    img_addr = base + 0x200
    code = struct.pack('<II', 0x20003000, img_addr + 8 + 1) + bytes.fromhex('fee7') + b'\x00\x00'
    length = len(code)
    hdr = struct.pack('<IIIIIII', 0x544F4C53, length, zlib.crc32(code), version, img_addr, 0, 0)
    hdr += struct.pack('<I', zlib.crc32(hdr))
    hdr = bytearray(hdr)
    code = bytearray(code)
    if bad == 'magic':
        hdr[0] ^= 1
    elif bad == 'hcrc':
        hdr[28] ^= 1
    elif bad == 'icrc':
        code[9] ^= 1
    elif bad == 'link':
        struct.pack_into('<I', hdr, 16, img_addr + 4)
        struct.pack_into('<I', hdr, 28, zlib.crc32(bytes(hdr[:28])))
    return bytes(hdr), bytes(code)


def cell(slot, state, seq, version=1):
    w = struct.pack('<III', 0x4C520000 | slot << 8 | state, version, seq)
    return w + struct.pack('<I', zlib.crc32(w))


class Meter:
    def __init__(self, starter, rec=None, slots=('ok', 'ok', 'ok'), flag=False):
        self.flash = bytearray(b'\xff' * FLASH_SIZE)
        self.flash[0:len(starter)] = starter
        for i, s in enumerate(slots):
            if s is None:
                continue
            h, c = slot_image(SLOTS[i], bad=None if s == 'ok' else s)
            o = SLOTS[i] - FLASH
            self.flash[o:o + len(h)] = h
            self.flash[o + 0x200:o + 0x200 + len(c)] = c
        for addr, data in (rec or []):
            o = addr - FLASH
            self.flash[o:o + len(data)] = data
        self.flag = flag

    def run(self, cut_after=None, limit=3_000_000):
        """One start. Returns (result, info); result 'slot0..2', 'dead', 'cut' or 'error ...'."""
        uc = Uc(UC_ARCH_ARM, UC_MODE_THUMB | UC_MODE_MCLASS)
        uc.mem_map(FLASH, REC0 - FLASH)
        uc.mem_write(FLASH, bytes(self.flash[:REC0 - FLASH]))
        uc.mem_map(REC0 + 0x1000, FLASH + FLASH_SIZE - REC0 - 0x1000)
        uc.mem_write(REC0 + 0x1000, bytes(self.flash[REC0 + 0x1000 - FLASH:]))
        uc.mem_map(SRAM, SRAM_SIZE)
        if self.flag:
            uc.mem_write(FLAG, struct.pack('<I', FLAG_MAGIC))
        uc.mem_map(0x40000000, FCTRL - 0x40000000)
        uc.mem_map(FCTRL + 0x1000, 0x40030000 - FCTRL - 0x1000)
        uc.mem_map(0xE000E000, 0x1000)
        st = dict(locked=True, keyseq=0, ctrl=0x80, add=0, sts=0, ops=0, log=[], err=None, end=None)
        fl = self.flash

        def rec_read(uc_, off, size, user):
            return int.from_bytes(fl[REC0 - FLASH + off:REC0 - FLASH + off + size], 'little')

        def rec_write(uc_, off, size, value, user):
            if size != 4 or off % 4:
                st['err'] = 'non-word write to record page'
                uc_.emu_stop()
                return
            a = REC0 + off
            if st['locked'] or not st['ctrl'] & 1:
                st['err'] = 'record write without PG / unlock at 0x%08X' % a
                uc_.emu_stop()
                return
            o = a - FLASH
            old = int.from_bytes(fl[o:o + 4], 'little')
            if old != 0xFFFFFFFF:
                st['sts'] |= 4      # PGERR
            else:
                fl[o:o + 4] = struct.pack('<I', value)
            st['log'].append(('word', a, value))
            st['ops'] += 1
            if cut_after is not None and st['ops'] >= cut_after:
                st['end'] = 'cut'
                uc_.emu_stop()

        def fc_read(uc_, off, size, user):
            if off == 0x0C:
                return st['sts']
            if off == 0x10:
                return st['ctrl'] | (0x80 if st['locked'] else 0)
            return 0

        def fc_write(uc_, off, size, value, user):
            if off == 0x04:
                if st['keyseq'] == 0 and value == 0x45670123:
                    st['keyseq'] = 1
                elif st['keyseq'] == 1 and value == 0xCDEF89AB:
                    st['locked'] = False
                    st['keyseq'] = 0
                else:
                    st['keyseq'] = 0
            elif off == 0x08:
                st['err'] = 'FLASH_OPTKEY written'
                uc_.emu_stop()
            elif off == 0x0C:
                st['sts'] &= ~value
            elif off == 0x14:
                st['add'] = value
            elif off == 0x10:
                st['log'].append(('ctrl', value))
                if value & 0x80:
                    st['locked'] = True
                if value & 0x30 or value & 0x04:
                    st['err'] = 'option or mass erase bit set: 0x%X' % value
                    uc_.emu_stop()
                    return
                if value & 0x40 and value & 0x02:
                    if st['locked']:
                        st['err'] = 'erase while locked'
                        uc_.emu_stop()
                        return
                    a = st['add'] & ~(PAGE - 1)
                    if not REC0 <= a < REC0 + 2 * PAGE:
                        st['err'] = 'erase outside the record pages: 0x%08X' % a
                        uc_.emu_stop()
                        return
                    fl[a - FLASH:a - FLASH + PAGE] = b'\xff' * PAGE
                    st['log'].append(('erase', a))
                    st['ops'] += 1
                    if cut_after is not None and st['ops'] >= cut_after:
                        st['end'] = 'cut'
                        uc_.emu_stop()
                st['ctrl'] = value & ~0xC0

        uc.mmio_map(REC0, 0x1000, rec_read, None, rec_write, None)
        uc.mmio_map(FCTRL, 0x1000, fc_read, None, fc_write, None)

        def on_write(uc_, access, addr, size, value, user):
            if FLASH <= addr < FLASH + FLASH_SIZE and not REC0 <= addr < REC0 + 0x1000:
                st['err'] = 'CPU write to flash 0x%08X' % addr
                uc_.emu_stop()
            if addr == 0x40010810 and value & 0x100:
                st['log'].append(('pa8', 1))

        def on_code(uc_, addr, size, user):
            for i, b in enumerate(SLOTS):
                if b + 0x200 <= addr < b + 0x6000:
                    st['end'] = 'slot%d' % i
                    uc_.emu_stop()
                    return
            if addr == SYM['dead_end']:
                st['end'] = 'dead'
                uc_.emu_stop()

        uc.hook_add(UC_HOOK_MEM_WRITE, on_write)
        uc.hook_add(UC_HOOK_CODE, on_code)
        sp, pc = struct.unpack_from('<II', fl, 0)
        uc.reg_write(UC_ARM_REG_SP, sp)
        try:
            uc.emu_start(pc | 1, 0, count=limit)
        except UcError as e:
            st['err'] = 'emulation error %s at 0x%08X' % (e, uc.reg_read(UC_ARM_REG_PC))
        info = dict(st)
        info['vtor'] = struct.unpack('<I', bytes(uc.mem_read(0xE000ED08, 4)))[0]
        info['flag_after'] = struct.unpack('<I', bytes(uc.mem_read(FLAG, 4)))[0]
        info['msp'] = uc.reg_read(UC_ARM_REG_SP)
        if st['err']:
            return 'error ' + st['err'], info
        return st['end'] or 'timeout', info

    def records(self):
        out = []
        for a in range(REC0, REC0 + 2 * PAGE, 16):
            c = bytes(self.flash[a - FLASH:a - FLASH + 16])
            w0, ver, seq, crc = struct.unpack('<IIII', c)
            if zlib.crc32(c[:12]) == crc and w0 >> 16 == 0x4C52:
                out.append((a, (w0 >> 8) & 0xFF, w0 & 0xFF, seq))
        return out


CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def full_page(base, slot, state, first_seq):
    return [(base + 16 * i, cell(slot, state, first_seq + i)) for i in range(PAGE // 16)]


@case
def empty_records_starts_f():
    r, i = Meter(STARTER).run()
    return r == 'slot0' and i['vtor'] == SLOTS[0] + 0x200 and not [x for x in i['log'] if x[0] != 'pa8' and x[0] != 'ctrl']


@case
def empty_records_bad_f_dead_end():
    for bad in ('magic', 'hcrc', 'icrc', 'link'):
        r, i = Meter(STARTER, slots=(bad, 'ok', 'ok')).run()
        if r != 'dead':
            return False
    return True


@case
def install_a_records_trial_then_starts_a():
    m = Meter(STARTER, rec=[(REC0, cell(1, ST_INSTALL, 1))])
    r, i = m.run()
    recs = m.records()
    return r == 'slot1' and recs[-1][1:] == (1, ST_TRIAL, 2) and recs[-1][0] == REC0 + 16


@case
def ok_a_starts_a_without_write():
    m = Meter(STARTER, rec=[(REC0, cell(1, ST_INSTALL, 1)), (REC0 + 16, cell(1, ST_TRIAL, 2)), (REC0 + 32, cell(1, ST_OK, 3))])
    r, i = m.run()
    return r == 'slot1' and not [x for x in i['log'] if x[0] in ('word', 'erase')]


@case
def trial_b_falls_back_to_ok_a():
    m = Meter(STARTER, rec=[(REC0, cell(1, ST_OK, 3)), (REC0 + 16, cell(2, ST_INSTALL, 4)), (REC0 + 32, cell(2, ST_TRIAL, 5))])
    r, i = m.run()
    return r == 'slot1' and not [x for x in i['log'] if x[0] in ('word', 'erase')]


@case
def trial_without_ok_goes_to_f():
    m = Meter(STARTER, rec=[(REC0, cell(2, ST_INSTALL, 1)), (REC0 + 16, cell(2, ST_TRIAL, 2))])
    r, i = m.run()
    return r == 'slot0'


@case
def trial_fallback_skips_bad_header():
    m = Meter(STARTER, rec=[(REC0, cell(1, ST_OK, 3)), (REC0 + 16, cell(2, ST_TRIAL, 5))], slots=('ok', 'icrc', 'ok'))
    r, i = m.run()
    return r == 'slot0'


@case
def ok_but_bad_header_goes_to_f():
    for bad in ('magic', 'hcrc', 'icrc', 'link'):
        m = Meter(STARTER, rec=[(REC0, cell(1, ST_OK, 1))], slots=('ok', bad, 'ok'))
        r, i = m.run()
        if r != 'slot0':
            return False
    return True


@case
def fault_flag_goes_to_f_and_is_cleared():
    m = Meter(STARTER, rec=[(REC0, cell(1, ST_OK, 1))], flag=True)
    r, i = m.run()
    return r == 'slot0' and i['flag_after'] == 0


@case
def newest_over_both_pages():
    m = Meter(STARTER, rec=[(REC0, cell(1, ST_OK, 7)), (REC1, cell(2, ST_OK, 9))])
    r, i = m.run()
    return r == 'slot2'


@case
def torn_cell_is_skipped_not_reused():
    torn = cell(1, ST_INSTALL, 2)[:8] + b'\xff' * 8
    m = Meter(STARTER, rec=[(REC0, cell(1, ST_INSTALL, 1)), (REC0 + 16, torn)])
    r, i = m.run()
    recs = m.records()
    return r == 'slot1' and recs[-1][0] == REC0 + 32 and recs[-1][1:] == (1, ST_TRIAL, 2)


@case
def full_page_moves_to_other_page():
    rec = full_page(REC0, 1, ST_OK, 1)
    rec[-1] = (REC0 + PAGE - 16, cell(1, ST_INSTALL, PAGE // 16))
    rec.append((REC1, cell(2, ST_OK, 0x10)[:12] + b'\x00\x00\x00\x00'))   # garbage in the other page
    m = Meter(STARTER, rec=rec)
    r, i = m.run()
    recs = [x for x in m.records() if x[0] >= REC1]
    erased = ('erase', REC1) in i['log']
    return r == 'slot1' and erased and recs == [(REC1, 1, ST_TRIAL, PAGE // 16 + 1)]


@case
def pa8_before_any_flash_access_and_locked_at_jump():
    m = Meter(STARTER, rec=[(REC0, cell(1, ST_INSTALL, 1))])
    r, i = m.run()
    first_flash = next(k for k, x in enumerate(i['log']) if x[0] != 'pa8')
    pa8 = next(k for k, x in enumerate(i['log']) if x[0] == 'pa8')
    return r == 'slot1' and pa8 < first_flash and i['locked'] and i['msp'] == 0x20003000


@case
def power_cut_at_every_flash_operation():
    """INSTALL with a free cell, and INSTALL with a full page: cut after every operation."""
    setups = []
    setups.append([(REC0, cell(1, ST_INSTALL, 1))])
    full = full_page(REC0, 1, ST_OK, 1)
    full[-1] = (REC0 + PAGE - 16, cell(1, ST_INSTALL, PAGE // 16))
    setups.append(full)
    for rec in setups:
        n = 1
        while True:
            m = Meter(STARTER, rec=rec)
            r, i = m.run(cut_after=n)
            if r != 'cut':
                break
            r2, i2 = m.run()
            if not r2.startswith('slot'):
                print('    cut after op %d -> %s' % (n, r2))
                return False
            n += 1
        if n < 2:
            return False
    return True


def main():
    global STARTER, SYM
    elf = sys.argv[1]
    SYM = symbols(elf)
    binp = elf[:-len('starter.elf')] + 'STARTER.bin'
    STARTER = open(binp, 'rb').read()
    bad = 0
    for fn in CASES:
        try:
            ok = fn()
        except Exception as e:      # a failing case must not hide the others
            print('    %s raised %r' % (fn.__name__, e))
            ok = False
        print('%-48s %s' % (fn.__name__, 'ok' if ok else 'FAIL'))
        bad += not ok
    print('%d tests, %d failed' % (len(CASES), bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
