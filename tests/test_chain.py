#!/usr/bin/env python3
"""test_chain.py - the boot chain starter -> slot bootloader -> application, in the emulator.

Usage (from the repository root, after `make -C starter` and `make -C bootloader slot`):
    <python with unicorn 2.1.4> tests/test_chain.py [case-name-prefix ...]

Flash: build/STARTER.bin at 0x08000000, build/slot/BOOT_F/A/B.bin at 0x08069000 / 0x0806F000 /
0x08075000, control records as each case says, and an application stub at 0x08006000 (vector table:
SP 0x20010000, reset 0x08006101). Peripheral and flash model: tests/meter_model.py. A start ends when
the CPU fetches from the application area (the application was started), when the slot reaches its
update-mode main loop (fn_08001150, after the USB start), at a system reset, at the starter's dead
end, or at a power cut. The slot's soft restart after an update (slot_soft_restart) is a branch to
the starter in the same run, not an end. Every case also requires: no violation of the flash model (no store to code
flash, no option-byte register, nothing in 0x0807F000..0x0807FFFF), and every erase / programmed word
inside the record pages 0x08068000..0x08068FFF (the chain never writes the application area).
"""
import struct
import sys

from meter_model import (Meter, cell, app_stub, APP, REC0, REC1, REC_END, PAGE, SLOTS, FLAG,
                         FLAG_MAGIC, ST_INSTALL, ST_TRIAL, ST_OK, IWDGRSTF)

SP0 = 0x20010000
CASES = []
NOTES = []


def case(fn):
    CASES.append(fn)
    return fn


def check(cond, text):
    if not cond:
        raise AssertionError(text)


def clean(m, what):
    st = m.st
    check(not st['viol'], '%s: violation %s' % (what, st['viol']))
    for op in m.flash_ops():
        check(REC0 <= op[1] < REC_END, '%s: flash op outside the record pages %r' % (what, op))


def recs(m):
    return [r[1:] for r in m.records()]


def app_reached(m, what, sp=SP0):
    st = m.st
    check(st['end'] == 'app', '%s: end %r, expected the application start' % (what, st['end']))
    check(st['app_pc'] == APP + 0x100, '%s: application entered at 0x%08X' % (what, st['app_pc']))
    check(st['vtor'] == APP, '%s: VTOR 0x%08X' % (what, st['vtor']))
    check(st['primask'] == 0, '%s: PRIMASK %d' % (what, st['primask']))
    # the slot's own hand-over sets MSP from the table and uses no stack after it
    check(st['msp'] == sp, '%s: MSP 0x%08X, table SP 0x%08X' % (what, st['msp'], sp))
    check(st['locked'], '%s: flash not locked at the application start' % what)


def update_reached(m, slot, what):
    st = m.st
    check(st['end'] == 'at slot%d update_loop' % slot, '%s: end %r, expected slot %d update mode'
          % (what, st['end'], slot))
    ev = m.events()
    check('slot%d usb_start' % slot in ev, '%s: no USB start' % what)


def started(m):
    return [e for e in m.events() if e.endswith(' reset')]


def ok_after_usb(m, slot, what):
    """The OK record's four words are programmed after the slot's USB start (fn_08002c10)."""
    log = m.st['log']
    usb = next(k for k, x in enumerate(log) if x == ('at', 'slot%d usb_start' % slot))
    okw = 0x4C520000 | slot << 8 | ST_OK
    k_ok = next((k for k, x in enumerate(log) if x[0] == 'word' and x[2] == okw), None)
    check(k_ok is not None, '%s: no OK record written' % what)
    check(k_ok > usb, '%s: OK record before the USB start' % what)


@case
def c01_install_trial_ok_application():
    m = Meter(records=[(REC0, cell(1, ST_INSTALL, 1))], app=app_stub())
    m.boot()
    clean(m, 'start 1')
    app_reached(m, 'start 1')
    check(started(m) == ['slot1 reset'], 'started %r' % started(m))
    check(recs(m) == [(1, ST_INSTALL, 1), (1, ST_TRIAL, 2), (1, ST_OK, 3)], 'records %r' % recs(m))
    check([r[0] for r in m.records()] == [REC0, REC0 + 16, REC0 + 32], 'cells %r' % m.records())
    log = m.st['log']
    pa8 = log.index(('pa8', 1))
    first = next(k for k, x in enumerate(log) if x[0] in ('word', 'erase'))
    check(pa8 < first, 'PA8 after the first flash write')
    slot_start = log.index(('at', 'slot1 reset'))
    words = [k for k, x in enumerate(log) if x[0] == 'word']
    check(len(words) == 8 and all(k < slot_start for k in words[:4]) and all(k > slot_start for k in words[4:]),
          'TRIAL by the starter, OK by the slot: %r' % [log[k] for k in words])
    conf = log.index(('at', 'slot1 confirm'))
    check(conf > log.index(('at', 'slot1 app_start')) and words[4] > conf, 'OK not from slot_confirm')
    NOTES.append('c01: MSP at the application = table SP (0x%08X)' % m.st['msp'])
    # second start: OK is newest -> no record, application again
    m.boot()
    clean(m, 'start 2')
    app_reached(m, 'start 2')
    check(not m.flash_ops(), 'start 2 wrote %r' % m.flash_ops())
    check(started(m) == ['slot1 reset'], 'start 2 started %r' % started(m))
    # third start with the key pressed: update mode, no record (OK already newest)
    m.key_pressed = True
    m.boot()
    clean(m, 'start 3')
    update_reached(m, 1, 'start 3')
    check(not m.flash_ops(), 'start 3 wrote %r' % m.flash_ops())
    ev = m.events()
    check(ev.index('slot1 uf2_init') < ev.index('slot1 usb_start') < ev.index('slot1 confirm'), 'order %r' % ev)
    return True


@case
def c02_key_pressed_install_ok_after_usb_start():
    m = Meter(records=[(REC0, cell(1, ST_INSTALL, 1))], app=app_stub())
    m.key_pressed = True
    m.boot()
    clean(m, 'key')
    update_reached(m, 1, 'key')
    check(recs(m) == [(1, ST_INSTALL, 1), (1, ST_TRIAL, 2), (1, ST_OK, 3)], 'records %r' % recs(m))
    ok_after_usb(m, 1, 'key')
    check('slot1 app_start' not in m.events(), 'key pressed but slot_app_start ran')
    check(m.get(APP, 8) == app_stub()[:8], 'application area changed')
    return True


BAD_VECTORS = [
    ('erased', None),
    ('SP 0x20000000', app_stub(sp=0x20000000)),
    ('SP 0x1FFFFFFC', app_stub(sp=0x1FFFFFFC)),
    ('SP 0x20024004', app_stub(sp=0x20024004)),
    ('SP 0xFFFFFFFF', app_stub(sp=0xFFFFFFFF)),
    ('reset even', app_stub(reset=APP + 0x100)),
    ('reset 0x08005FFF', app_stub(reset=0x08005FFF)),
    ('reset 0x08000101', app_stub(reset=0x08000101)),
    ('reset 0x08062001', app_stub(reset=0x08062001)),
    ('reset 0x0806F201', app_stub(reset=0x0806F201)),
]


@case
def c03_bad_application_vectors_update_mode():
    for name, app in BAD_VECTORS:
        m = Meter(records=[(REC0, cell(1, ST_INSTALL, 1))], app=app)
        m.boot()
        clean(m, name)
        update_reached(m, 1, name)
        check(recs(m)[-1] == (1, ST_OK, 3), '%s: records %r' % (name, recs(m)))
        ok_after_usb(m, 1, name)
    return True


@case
def c04_vector_boundaries_accepted():
    """SP 0x20024000 (the upper limit) and reset 0x08061FFF are inside the checks."""
    out = []
    for name, sp, reset in (('reset 0x08061FFF', SP0, 0x08061FFF), ('reset 0x08006001', SP0, 0x08006001),
                            ('SP 0x20000004', 0x20000004, APP + 0x101), ('SP 0x20024000', 0x20024000, APP + 0x101)):
        m = Meter(records=[(REC0, cell(1, ST_OK, 1))], app=app_stub(sp=sp, reset=reset))
        m.boot()
        out.append((name, m.st['end'], m.st.get('app_pc')))
        check(not m.st['viol'], '%s: violation %s' % (name, m.st['viol']))
        check(m.st['end'] == 'app' and m.st['app_pc'] == reset & ~1,
              '%s: end %r (expected the application start at 0x%08X)' % (name, m.st['end'], reset & ~1))
    return True


@case
def c05_slot_a_header_broken_slot_f():
    for name, off in (('image CRC', 0x300), ('header magic', 0), ('header CRC', 28)):
        m = Meter(records=[(REC0, cell(1, ST_INSTALL, 1)), (REC0 + 16, cell(1, ST_TRIAL, 2)),
                           (REC0 + 32, cell(1, ST_OK, 3))], app=app_stub())
        m.flash[SLOTS[1] - 0x08000000 + off] ^= 0x01
        m.boot()
        clean(m, name)
        app_reached(m, name)
        check(started(m) == ['slot0 reset'], '%s: started %r' % (name, started(m)))
        check(not m.flash_ops(), '%s: wrote %r' % (name, m.flash_ops()))
    return True


@case
def c06_trial_without_ok_slot_f():
    m = Meter(records=[(REC0, cell(1, ST_INSTALL, 1)), (REC0 + 16, cell(1, ST_TRIAL, 2))], app=app_stub())
    m.boot()
    clean(m, 'trial A')
    app_reached(m, 'trial A')
    check(started(m) == ['slot0 reset'], 'started %r' % started(m))
    check(not m.flash_ops(), 'wrote %r' % m.flash_ops())
    return True


@case
def c07_trial_a_other_ok_slot_b():
    m = Meter(records=[(REC0, cell(2, ST_OK, 1)), (REC0 + 16, cell(1, ST_INSTALL, 2)),
                       (REC0 + 32, cell(1, ST_TRIAL, 3))], app=app_stub())
    m.boot()
    clean(m, 'trial A, OK B')
    app_reached(m, 'trial A, OK B')
    check(started(m) == ['slot2 reset'], 'started %r' % started(m))
    check(not m.flash_ops(), 'wrote %r' % m.flash_ops())
    return True


@case
def c08_install_f_confirms_f():
    m = Meter(records=[(REC0, cell(0, ST_INSTALL, 1))], app=app_stub())
    m.boot()
    clean(m, 'install F')
    app_reached(m, 'install F')
    check(started(m) == ['slot0 reset'], 'started %r' % started(m))
    check(recs(m) == [(0, ST_INSTALL, 1), (0, ST_TRIAL, 2), (0, ST_OK, 3)], 'records %r' % recs(m))
    return True


@case
def c09_slot_record_page_full_moves_to_other_page():
    rec = [(REC0 + 16 * i, cell(1, ST_OK, 1 + i)) for i in range(PAGE // 16 - 1)]
    rec.append((REC0 + PAGE - 16, cell(1, ST_INSTALL, PAGE // 16)))   # last cell: INSTALL A
    rec.append((REC1, b'\x00' * 16))                                 # garbage in the other page
    m = Meter(records=rec, app=app_stub())
    m.boot()
    clean(m, 'full page')
    app_reached(m, 'full page')
    upper = [r[1:] for r in m.records() if r[0] >= REC1]
    n = PAGE // 16
    check(upper == [(1, ST_TRIAL, n + 1), (1, ST_OK, n + 2)], 'REC1 records %r' % upper)
    erases = [x for x in m.flash_ops() if x[0] == 'erase']
    check(erases == [('erase', REC1)], 'erases %r' % erases)
    return True


@case
def c10_power_cut_after_every_flash_operation():
    """INSTALL A (application start and key-pressed update mode): cut after each of the 8 record
    words, then start again until the application or update mode is reached (at most 3 starts)."""
    for key in (False, True):
        n = 1
        while True:
            m = Meter(records=[(REC0, cell(1, ST_INSTALL, 1))], app=app_stub())
            m.key_pressed = key
            end = m.boot(cut_after=n)
            if end != 'cut':
                break
            check(not m.st['viol'], 'cut %d: %s' % (n, m.st['viol']))
            for k in range(3):
                end = m.boot()
                clean(m, 'after cut %d' % n)
                if end == 'app' or end.endswith('update_loop'):
                    break
            check(end == 'app' or end.endswith('update_loop'), 'key %s cut %d: end %r' % (key, n, end))
            if key:
                check(end.endswith('update_loop'), 'key %s cut %d: end %r' % (key, n, end))
            NOTES.append('c10 key=%s cut after op %d: next start %s, started %s, records %s'
                         % (key, n, end, started(m), recs(m)))
            n += 1
        check(n == 9, 'key %s: %d flash operations, expected 8' % (key, n - 1))
    return True


@case
def c11_slot_fault_sets_flag_next_start_slot_f():
    m = Meter(records=[(REC0, cell(1, ST_OK, 1))], app=app_stub())
    m.key_pressed = True
    m.boot()
    update_reached(m, 1, 'update A')
    m.call(m.sym[1]['slot_fault'])
    check(m.st['end'] == 'reset', 'slot_fault end %r' % m.st['end'])
    m.ram = bytes(m.uc.mem_read(0x20000000, 0x24000))
    check(struct.unpack_from('<I', m.ram, FLAG - 0x20000000)[0] == FLAG_MAGIC, 'flag not set')
    m.key_pressed = False
    m.boot(keep_ram=True)
    clean(m, 'after fault')
    app_reached(m, 'after fault')
    check(started(m) == ['slot0 reset'], 'started %r' % started(m))
    # the flag word lies inside the slot's stack (stock stack top 0x20002028), so RAM after the
    # start shows stack data there; the next warm start (RAM kept) must go to slot A again
    NOTES.append('c11: word 0x2001FFF0 at the application start of slot F: 0x%08X (stack data)'
                 % struct.unpack_from('<I', m.ram, FLAG - 0x20000000)[0])
    m.boot(keep_ram=True)
    clean(m, 'warm start')
    app_reached(m, 'warm start')
    check(started(m) == ['slot1 reset'], 'warm start after the fault start: started %r' % started(m))
    return True


@case
def c12_failed_record_word_written_again_in_next_cell():
    # one word of the TRIAL cell (starter) and one of the OK cell (slot) do not program as stored,
    # as the version word of the OK cell on a meter on 2026-11-20: each record is read back and
    # written again in the next free cell
    m = Meter(records=[(REC0, cell(1, ST_INSTALL, 1))], app=app_stub())
    m.stuck[REC0 + 0x14] = 0x100
    m.stuck[REC0 + 0x34] = 0x100
    m.boot()
    clean(m, 'start')
    app_reached(m, 'start')
    check(recs(m) == [(1, ST_INSTALL, 1), (1, ST_TRIAL, 2), (1, ST_OK, 3)], 'records %r' % recs(m))
    check([r[0] for r in m.records()] == [REC0, REC0 + 32, REC0 + 64], 'cells %r' % m.records())
    return True


# ---------------------------------------------------------------- slot bootloader version 2
# USB_CONTROL_DESIGN.md section 6 (a)..(e) and section 9; bootloader/src/slot_10.s (slot_key_check,
# slot_app_start, slot_finish, slot_soft_restart, slot_trial_wdg, slot_feed, slot_confirm) and
# system_05.s main; the no-init words of bootloader/src/slot.inc. Cases c13..c21 need the slots built
# with SLOT_VERSION 2 or later (version 3 keeps every feature of 2; bootloader/Makefile default 3).

REQ_WORD, REQ_MAGIC, REQ_RESTART = 0x2001FFF4, 0x55504454, 0x52535452
HANDOVER_WORD, HANDOVER_TAG = 0x2001FFF8, 0x534C0000
RESULT_WORD, RESULT_OK = 0x2001FFFC, 0x5552 << 16 | 1 << 8 | (~1 & 0xFF)    # 0x555201FE
WDG_ON = 0x20002228
BOOT_STATE = 0x20000274
IWDG_KEY, IWDG_PR, IWDG_RL = 0x40003000, 0x40003004, 0x40003008
LSI_FAST = 60000          # datasheet fLSI max: the shortest watchdog period 2501 * 16 / 60000 s
PERIOD_MIN = 0.67         # USB_CONTROL_DESIGN.md requirement 2 / section 6: the bound every claim uses


def ram_word(m, addr):
    return struct.unpack_from('<I', m.ram, addr - 0x20000000)[0]


def set_ram_word(m, addr, value):
    r = bytearray(m.ram)
    struct.pack_into('<I', r, addr - 0x20000000, value)
    m.ram = bytes(r)


class Tim7Stopped:
    """TIM7 CNT 0x40001424 reads 0 and ignores writes: every fn_08003224 delay (count up to its
    argument, bootloader/src/board_02.s) waits for ever: a hang of the code that waits on it."""
    ranges = [(0x40001424, 0x40001428)]

    def read(self, m, a, size):
        return 0

    def write(self, m, a, size, value):
        pass


class GpioC:
    """GPIOC PID 0x40011008 (fn_080007a4 reads the word at +8): bit 7 = PC7 (the up key, 0 pressed),
    bit 6 = PC6 (the power key, 0 held) held until the emulated time pc6_until (timing only)."""
    ranges = [(0x40011008, 0x4001100C)]

    def __init__(self, pc7_pressed, pc6_until=0.0):
        self.pc7_pressed, self.pc6_until = pc7_pressed, pc6_until

    def read(self, m, a, size):
        pc6 = 0 if m.timing and m.now() < self.pc6_until else 0x40
        return pc6 | (0 if self.pc7_pressed else 0x80)

    def write(self, m, a, size, value):
        pass


def iw_kinds(m, start=None):
    return [e['kind'] for e in m.iwdg_log if start is None or e['start'] == start]


@case
def c13_request_word_enters_update_mode_and_is_cleared():
    # slot_key_check: REQ_WORD read and cleared at every start; REQ_MAGIC acts as the key held
    for value, update in ((REQ_MAGIC, True), (REQ_MAGIC ^ 1, False), (0, False)):
        m = Meter(records=[(REC0, cell(1, ST_OK, 1))], app=app_stub())
        set_ram_word(m, REQ_WORD, value)
        m.boot(keep_ram=True)
        what = 'request word 0x%08X' % value
        clean(m, what)
        if update:
            update_reached(m, 1, what)
        else:
            app_reached(m, what)
        check(ram_word(m, REQ_WORD) == 0, '%s: not cleared (0x%08X)' % (what, ram_word(m, REQ_WORD)))
        check(not m.flash_ops(), '%s: wrote %r' % (what, m.flash_ops()))
    return True


@case
def c14_handover_word_slot_index_and_watchdog_bit():
    # slot_app_start: HANDOVER_TAG | WDG_ON << 8 | SLOT_INDEX; WDG_ON = 1 only after a trial start
    # (slot_trial_wdg: newest record TRIAL for this slot). Without timing the IWDG registers are plain
    # words (meter_model), so the writes of slot_trial_wdg stay visible in the register file.
    tests = [('OK A', [(REC0, cell(1, ST_OK, 1))], 'slot1 reset', HANDOVER_TAG | 1, False),
             ('INSTALL A (trial)', [(REC0, cell(1, ST_INSTALL, 1))], 'slot1 reset', HANDOVER_TAG | 0x100 | 1, True),
             ('OK B', [(REC0, cell(2, ST_OK, 1))], 'slot2 reset', HANDOVER_TAG | 2, False),
             ('INSTALL B (trial)', [(REC0, cell(2, ST_INSTALL, 1))], 'slot2 reset', HANDOVER_TAG | 0x100 | 2, True),
             ('OK F', [(REC0, cell(0, ST_OK, 1))], 'slot0 reset', HANDOVER_TAG | 0, False),
             ('no record', [], 'slot0 reset', HANDOVER_TAG | 0, False)]
    for name, rec, slot, word, wdg in tests:
        m = Meter(records=rec, app=app_stub())
        m.boot()
        clean(m, name)
        app_reached(m, name)
        check(started(m) == [slot], '%s: started %r' % (name, started(m)))
        check(ram_word(m, HANDOVER_WORD) == word, '%s: hand-over word 0x%08X, expected 0x%08X'
              % (name, ram_word(m, HANDOVER_WORD), word))
        regs = m.st['regs']
        if wdg:
            # last key write: the 0xAAAA of slot_feed in slot_app_start (after 0xCCCC of slot_trial_wdg)
            check(regs.get(IWDG_KEY) == 0xAAAA and regs.get(IWDG_PR) == 2 and regs.get(IWDG_RL) == 0x9C4,
                  '%s: IWDG registers %r' % (name, [hex(regs.get(a, 0)) for a in (IWDG_KEY, IWDG_PR, IWDG_RL)]))
        else:
            check(IWDG_KEY not in regs, '%s: IWDG key written 0x%X' % (name, regs.get(IWDG_KEY, 0)))
    # update mode: slot_app_start does not run, the word stays as it was
    m = Meter(records=[(REC0, cell(1, ST_OK, 1))], app=app_stub())
    m.key_pressed = True
    set_ram_word(m, HANDOVER_WORD, 0)
    m.boot(keep_ram=True)
    update_reached(m, 1, 'update mode')
    check(ram_word(m, HANDOVER_WORD) == 0, 'update mode wrote the hand-over word 0x%08X' % ram_word(m, HANDOVER_WORD))
    return True


def at_starter_entry(m):
    """Snapshot of the chip when the starter's reset entry runs next (hook added after the first start,
    so it records the entry through slot_soft_restart): request word, peripheral and SCS registers,
    PRIMASK, MSP, flash lock, length of the log at that moment."""
    from unicorn import UC_HOOK_CODE
    from unicorn.arm_const import UC_ARM_REG_PRIMASK, UC_ARM_REG_MSP
    snap = {}
    a = m.starter_sym['reset'] & ~1

    def hit(uc, addr, size, user):
        if snap:
            return
        snap.update(req=struct.unpack('<I', bytes(uc.mem_read(REQ_WORD, 4)))[0], regs=dict(m.st['regs']),
                    scs=dict(m.scs), primask=uc.reg_read(UC_ARM_REG_PRIMASK), msp=uc.reg_read(UC_ARM_REG_MSP),
                    locked=m.st['locked'], log_len=len(m.st['log']))
    m.uc.hook_add(UC_HOOK_CODE, hit, begin=a, end=a)
    return snap


def finish_update(m, what):
    """From the update-mode loop (the run stopped at fn_08001150): the stock state byte 0x20000274 = 2
    (what uf2_finish stores after a checked update), key released, the run goes on from the return
    address of `bl fn_08001150` (ldrb / cmp #2 / bl slot_finish). Returns the starter-entry snapshot;
    the run must end with the application start of the next slot start."""
    from unicorn.arm_const import UC_ARM_REG_LR
    snap = at_starter_entry(m)
    lr = m.uc.reg_read(UC_ARM_REG_LR)
    m.uc.mem_write(BOOT_STATE, b'\x02')
    m.key_pressed = False
    m.st['end'] = None
    m.go(lr & ~1)
    clean(m, what)
    check(snap, '%s: the starter was not entered again' % what)
    return snap


def soft_restart_state(m, snap, what):
    """slot_soft_restart (bootloader/src/slot_10.s) as the starter finds the chip: no system reset in
    the whole run, PA8 never driven low and driven high again by the starter, USB pull-up off, USB_CTRL
    = FRST | PD, USBEN cleared, NVIC ICER0..2 / ICPR0..2 all ones, SysTick CTRL 0, flash locked, SYSCLK
    switch bits still 10 (PLL), VTOR 0, MSP = the starter's table word 0x20002000, PRIMASK set."""
    log = m.st['log']
    check(('reset',) not in log, '%s: system reset in the run' % what)
    check(('pa8', 0) not in log, '%s: PA8 driven low' % what)
    check(('pa8', 1) in log[snap['log_len']:], '%s: the starter did not drive PA8 high again' % what)
    regs, scs = snap['regs'], snap['scs']
    check(not regs.get(0x40001820, 0) & (1 << 28), '%s: D+ pull-up on at the starter entry' % what)
    check(regs.get(0x40005C40) == 3, '%s: USB_CTRL 0x%X' % (what, regs.get(0x40005C40, -1)))
    check(not regs.get(0x4002101C, 0) & (1 << 23), '%s: USBEN still set' % what)
    for base in (0xE000E180, 0xE000E280):
        for k in range(3):
            check(scs.get(base + 4 * k) == 0xFFFFFFFF, '%s: 0x%08X = %r' % (what, base + 4 * k, scs.get(base + 4 * k)))
    check(scs.get(0xE000E010) == 0, '%s: SysTick CTRL %r' % (what, scs.get(0xE000E010)))
    check(snap['locked'], '%s: flash unlocked at the starter entry' % what)
    # the PLL stays the system clock (SCLKSW 10, set by the slot's fn_080020c4); the next slot start
    # switches to HSI first (board_02.s fn_08002598, slot build)
    check(regs.get(0x40021004, 0) & 3 == 2, '%s: RCC_CFG 0x%08X, SCLKSW not PLL' % (what, regs.get(0x40021004, 0)))
    check(scs.get(0xE000ED08) == 0, '%s: VTOR 0x%08X' % (what, scs.get(0xE000ED08, -1)))
    check(snap['msp'] == 0x20002000 and snap['primask'] == 1, '%s: MSP 0x%08X PRIMASK %d'
          % (what, snap['msp'], snap['primask']))


@case
def c15_update_finish_soft_restart_without_watchdog():
    """Update mode entered by the key at power-on (WDG_ON 0, no IWDG): state 2 -> slot_finish writes the
    result word and soft-restarts without a request word (REQ_WORD 0 at the starter entry); starter and
    slot start again in the same run and the application starts (hand-over bit 8 clear, no IWDG key
    written in the whole run); the result word survives (outside every region they clear)."""
    m = Meter(records=[(REC0, cell(1, ST_OK, 1))], app=app_stub())
    m.key_pressed = True
    m.boot()
    update_reached(m, 1, 'update mode')
    snap = finish_update(m, 'finish')
    soft_restart_state(m, snap, 'finish')
    check(snap['req'] == 0, 'request word 0x%08X at the starter entry, expected none' % snap['req'])
    app_reached(m, 'next start')
    check(started(m) == ['slot1 reset', 'slot1 reset'], 'started %r' % started(m))
    check(ram_word(m, RESULT_WORD) == RESULT_OK, 'result word 0x%08X, expected 0x%08X'
          % (ram_word(m, RESULT_WORD), RESULT_OK))
    check(ram_word(m, HANDOVER_WORD) == HANDOVER_TAG | 1, 'hand-over 0x%08X' % ram_word(m, HANDOVER_WORD))
    check(IWDG_KEY not in m.st['regs'], 'IWDG key written 0x%X' % m.st['regs'].get(IWDG_KEY, 0))
    check(not m.flash_ops(), 'wrote %r' % m.flash_ops())
    return True


@case
def c20_request_word_restart_and_update_set_wdg_on():
    """slot_key_check: RSTR (normal start) and UPDT (update mode) both set WDG_ON = 3 (bit 0 the IWDG
    runs, bit 1 soft restart) and feed once (IWDG key 0xAAAA; without timing the register file keeps
    the last key write), the word is cleared; only UPDT enters update mode. RSTR: application start
    with hand-over bits 8 and 9; any other value: WDG_ON 0, no IWDG key written."""
    for value, update, wdg in ((REQ_RESTART, False, 3), (REQ_MAGIC, True, 3), (REQ_RESTART ^ 1, False, 0),
                               (0, False, 0)):
        m = Meter(records=[(REC0, cell(1, ST_OK, 1))], app=app_stub())
        set_ram_word(m, REQ_WORD, value)
        m.boot(keep_ram=True)
        what = 'request word 0x%08X' % value
        clean(m, what)
        if update:
            update_reached(m, 1, what)
        else:
            app_reached(m, what)
            check(ram_word(m, HANDOVER_WORD) == HANDOVER_TAG | wdg << 8 | 1, '%s: hand-over 0x%08X'
                  % (what, ram_word(m, HANDOVER_WORD)))
        check(ram_word(m, REQ_WORD) == 0, '%s: not cleared (0x%08X)' % (what, ram_word(m, REQ_WORD)))
        check(ram_word(m, WDG_ON) == wdg, '%s: WDG_ON %d' % (what, ram_word(m, WDG_ON)))
        if wdg:
            check(m.st['regs'].get(IWDG_KEY) == 0xAAAA, '%s: IWDG key %r' % (what, m.st['regs'].get(IWDG_KEY)))
            check(IWDG_PR not in m.st['regs'], '%s: IWDG reprogrammed' % what)
        else:
            check(IWDG_KEY not in m.st['regs'], '%s: IWDG key written' % what)
        check(not m.flash_ops(), '%s: wrote %r' % (what, m.flash_ops()))
    return True


@case
def c21_update_finish_soft_restart_with_watchdog():
    """Update mode entered by the request word UPDT (the application's soft restart: WDG_ON 3): state 2
    -> slot_finish writes the result word and RSTR, soft-restarts (same chip state as c15 at the
    starter entry, REQ_WORD = RSTR there); the next slot start clears it, sets WDG_ON 3 and starts the
    application with hand-over bits 8 and 9 (the application then feeds its IWDG at once, ctl.s
    own_start, and keeps PA8 high, own_pa8_level)."""
    m = Meter(records=[(REC0, cell(1, ST_OK, 1))], app=app_stub())
    set_ram_word(m, REQ_WORD, REQ_MAGIC)
    m.boot(keep_ram=True)
    update_reached(m, 1, 'update mode')
    snap = finish_update(m, 'finish')
    soft_restart_state(m, snap, 'finish')
    check(snap['req'] == REQ_RESTART, 'request word 0x%08X at the starter entry, expected RSTR' % snap['req'])
    app_reached(m, 'next start')
    check(started(m) == ['slot1 reset', 'slot1 reset'], 'started %r' % started(m))
    check(ram_word(m, REQ_WORD) == 0 and ram_word(m, WDG_ON) == 3, 'request word 0x%08X, WDG_ON %d'
          % (ram_word(m, REQ_WORD), ram_word(m, WDG_ON)))
    check(ram_word(m, HANDOVER_WORD) == HANDOVER_TAG | 0x300 | 1, 'hand-over 0x%08X' % ram_word(m, HANDOVER_WORD))
    check(ram_word(m, RESULT_WORD) == RESULT_OK, 'result word 0x%08X' % ram_word(m, RESULT_WORD))
    check(not m.flash_ops(), 'wrote %r' % m.flash_ops())
    return True


@case
def c16_trial_slot_hangs_before_confirm_iwdg_reset_rollback():
    """INSTALL A: the starter appends TRIAL and starts A; A starts the watchdog (slot_trial_wdg) and
    then hangs in its first delay of update mode (key held, TIM7 stopped: fn_0800320e(100) in main,
    before slot_confirm). The IWDG resets the chip after RL + 1 ticks from the 0xAAAA reload: the
    model's expiry with PR / RL taking effect 5 LSI periods after their writes (meter_model
    iwdg_sync_lsi) is (5 + (2501 - 5 / 4) * 16) / LSI = 40001 / LSI, between 40000 / LSI and
    2501 * 16 / LSI. Next start (TIM7 normal, key up): TRIAL A newest -> no other OK slot -> F, which
    starts no watchdog and writes no record."""
    m = Meter(records=[(REC0, cell(1, ST_INSTALL, 1))], app=app_stub())
    m.set_timing(lsi_hz=LSI_FAST)
    tim = m.attach(Tim7Stopped())
    m.key_pressed = True
    first = {}

    def hook(mm, end):
        first['events'] = mm.events()
        first['records'] = recs(mm)
        first['ctrlsts'] = mm.ctrlsts
        mm.devices.remove(tim)
        mm.key_pressed = False
        return True
    ends = m.starts(n=2, hook=hook)
    check(ends == ['iwdg', 'app'], 'ends %r' % ends)
    check('slot1 reset' in first['events'] and 'slot1 confirm' not in first['events'],
          'start 1 events %r' % first['events'])
    check(first['records'] == [(1, ST_INSTALL, 1), (1, ST_TRIAL, 2)], 'start 1 records %r' % first['records'])
    # loads and the reset of start 1 (the model also logs 'stopped' when the chip restarts)
    log1 = [e for e in m.iwdg_log if e['start'] == 1 and e['kind'] in ('start', 'feed', 'reset')]
    check([e['kind'] for e in log1] == ['start', 'reset'], 'start 1 IWDG log %r' % [e['kind'] for e in log1])
    span = log1[1]['t'] - log1[0]['t']
    check(40000.0 / LSI_FAST <= span <= 2501 * 16.0 / LSI_FAST, 'reset %.6f s after the start' % span)
    check(first['ctrlsts'] & IWDGRSTF, 'RCC_CTRLSTS IWDGRSTF not set after the IWDG reset')
    clean(m, 'start 2')
    app_reached(m, 'start 2')
    check(started(m) == ['slot0 reset'], 'start 2 started %r' % started(m))
    check(recs(m) == [(1, ST_INSTALL, 1), (1, ST_TRIAL, 2)], 'start 2 records %r' % recs(m))
    check('start' not in iw_kinds(m, 2), 'start 2 started the IWDG: %r' % iw_kinds(m, 2))
    check(ram_word(m, HANDOVER_WORD) == HANDOVER_TAG | 0, 'hand-over word 0x%08X' % ram_word(m, HANDOVER_WORD))
    NOTES.append('c16: IWDG reset %.4f s after the trial start (LSI %d Hz)' % (span, LSI_FAST))
    return True


@case
def c17_trial_slot_confirms_no_reset():
    """INSTALL A with the watchdog model at 30 and 60 kHz: application start (slot_confirm, a feed,
    the hand-over word with bit 8) before any expiry; the application starts with the IWDG running
    and freshly fed (slot_app_start feeds after slot_confirm). With the key held: update mode, the
    OK record after the USB start, no reset either."""
    for lsi in (30000, LSI_FAST):
        for key in (False, True):
            what = 'LSI %d key %s' % (lsi, key)
            m = Meter(records=[(REC0, cell(1, ST_INSTALL, 1))], app=app_stub())
            m.set_timing(lsi_hz=lsi)
            m.key_pressed = key
            m.boot()
            clean(m, what)
            check('reset' not in iw_kinds(m), '%s: IWDG reset %r' % (what, iw_kinds(m)))
            check(iw_kinds(m).count('start') == 1, '%s: IWDG log %r' % (what, iw_kinds(m)))
            check(recs(m) == [(1, ST_INSTALL, 1), (1, ST_TRIAL, 2), (1, ST_OK, 3)], '%s: records %r' % (what, recs(m)))
            st = m.iwdg_stretch()
            check(st['longest'] is None or st['longest']['seconds'] < PERIOD_MIN, '%s: stretch %r' % (what, st['longest']))
            if key:
                update_reached(m, 1, what)
                ok_after_usb(m, 1, what)
            else:
                app_reached(m, what)
                check(m.tm['iw']['running'], '%s: IWDG not running at the application start' % what)
                check(st['open'] is not None and st['open']['seconds'] < 1e-3,
                      '%s: %r since the last feed at the application start' % (what, st['open']))
                check(ram_word(m, HANDOVER_WORD) == HANDOVER_TAG | 0x100 | 1, '%s: hand-over 0x%08X'
                      % (what, ram_word(m, HANDOVER_WORD)))
    return True


@case
def c18_power_key_held_longer_than_the_period_on_a_trial_start():
    """INSTALL A, key PC7 held (update mode), PC6 held for 1.0 s, longer than the period at 60 kHz
    (2501 * 16 / 60000 = 0.667 s): the wait for PC6 in main feeds (system_05.s .L08003ea4 slot_feed),
    so no reset; update mode is reached after PC6 is released."""
    m = Meter(records=[(REC0, cell(1, ST_INSTALL, 1))], app=app_stub())
    m.set_timing(lsi_hz=LSI_FAST)
    m.attach(GpioC(pc7_pressed=True, pc6_until=1.0))
    m.boot()
    clean(m, 'PC6 held')
    update_reached(m, 1, 'PC6 held')
    check('reset' not in iw_kinds(m), 'IWDG reset %r' % iw_kinds(m))
    check(m.clock >= 1.0, 'update mode reached at %.3f s, before PC6 was released' % m.clock)
    longest = m.iwdg_stretch()['longest']
    check(longest is not None and longest['seconds'] < PERIOD_MIN, 'longest stretch %r' % longest)
    NOTES.append('c18: update mode at %.3f s, longest stretch %.6f s' % (m.clock, longest['seconds']))
    return True


@case
def c19_starter_trial_append_fails_slot_starts_without_watchdog():
    """Documented case (USB_CONTROL_DESIGN.md section 6 (d)): the starter's TRIAL append fails three
    times (version word of the cells at 0x08068010 / 20 / 30 stuck: bit 8 stays 1, read back 0x101
    instead of 1), then starter.s goes on with `b start_slot`: the newest valid record stays INSTALL A,
    so slot A starts without the watchdog (WDG_ON 0, no IWDG key written) and confirms nothing."""
    m = Meter(records=[(REC0, cell(1, ST_INSTALL, 1))], app=app_stub())
    for k in (1, 2, 3):
        m.stuck[REC0 + 16 * k + 4] = 0x100
    m.boot()
    clean(m, 'TRIAL append failed')
    app_reached(m, 'TRIAL append failed')
    check(started(m) == ['slot1 reset'], 'started %r' % started(m))
    check(recs(m) == [(1, ST_INSTALL, 1)], 'records %r' % recs(m))
    check(len([x for x in m.flash_ops() if x[0] == 'word']) == 12, 'starter words %r' % m.flash_ops())
    check(ram_word(m, WDG_ON) == 0 and IWDG_KEY not in m.st['regs'], 'watchdog started')
    check(ram_word(m, HANDOVER_WORD) == HANDOVER_TAG | 1, 'hand-over 0x%08X' % ram_word(m, HANDOVER_WORD))
    check('slot1 confirm' in m.events() and not [x for x in m.flash_ops() if x[1] >= REC0 + 64],
          'slot_confirm wrote a record')
    NOTES.append('c19: documented: TRIAL append failed 3 times -> slot A started as INSTALL, no watchdog, no OK')
    return True


# ---------------------------------------------------------------- slot bootloader version 3
# The three clock waits of the slot's start-up code end after CLK_POLLS = 0x8000 reads
# (bootloader/src/slot.inc; board_02.s fn_08002598 .Lslot_hsi and the slot copy of fn_080020c4,
# .Lslot_pll, .Lslot_sw / .Lslot_back). The RCC rules are the opt-in ones of tests/meter_model.py
# (pll_locks, sws_stuck, rcc_switch_reads, pll_lock_reads, rcc_strict). Under the rules of c23..c25 a
# wait without a bound (slot version 2) never ends: the start would end 'timeout' after the
# instruction budget of boot() instead of reaching the application or update mode.

RCC_CTRL, RCC_CFG, FLASH_AC = 0x40021000, 0x40021004, 0x40022000
PLLEN, HSEEN, PLL_FIELDS = 1 << 24, 1 << 16, 0x083F0000
APB_DIVS = 0x2500          # RCC_CFG |= 0x2000 (APB2 / 2) and |= 0x500 (APB1 / 4), fn_080020c4
CLK_POLLS = 0x8000


def clock_start(setup, key, strict=True):
    """One start of OK A with the application stub, the RCC rules set by setup(m), the key as given;
    rcc_strict on unless strict is False. Returns the meter after the start (application or update
    mode reached, checked; no violation, no flash write)."""
    m = Meter(records=[(REC0, cell(1, ST_OK, 1))], app=app_stub())
    m.rcc_strict = strict
    setup(m)
    m.key_pressed = key
    m.boot()
    what = 'key %s' % key
    clean(m, what)
    if key:
        update_reached(m, 1, what)
    else:
        app_reached(m, what)
    check(started(m) == ['slot1 reset'], '%s: started %r' % (what, started(m)))
    check(not m.flash_ops(), '%s: wrote %r' % (what, m.flash_ops()))
    return m


@case
def c22_slot_headers_version_3():
    """Header word +12 of BOOT_F / A / B = 3 (bootloader/Makefile SLOT_VERSION, tools/slot_header.py).
    The starter's header_ok does not read it (starter/starter.s); the application's UPDATE_MODE and
    RESET require 2 or more and refuse 0xFFFFFFFF (firmware/own/cmd.s h_update_mode, h_reset)."""
    m = Meter(records=[], app=app_stub())
    got = [struct.unpack_from('<I', m.flash, base - 0x08000000 + 12)[0] for base in SLOTS]
    check(got == [3, 3, 3], 'header versions %r' % got)
    return True


@case
def c23_slot_hsi_switch_bound():
    """SCLKSTS stuck at 10 (sws_stuck 2: the PLL keeps running the core): fn_08002598's wait for
    SCLKSTS = 00 ends after CLK_POLLS reads and goes straight to the VTOR store: no RCC_CTRL store
    after HSIEN (no PLLEN / HSEEN clear, rcc_strict would report one), no FLASH_AC store (neither
    fn_08002598's |= 0x90 nor fn_080020c4's LATENCY stores, the only two writers, check_never_brick
    D2), RCC_CFG holds only the SCLKSW = 00 write. Application start and update mode both reached.
    The write is read-modify-write (ldr, bic #3, str): it carries the SCLKSTS bits 3:2 as read (10,
    the stuck PLL status: 0x8, Run of 2026-11-24), which the chip ignores (manual RCC_CFG, UM line
    6328: SCLKSTS "Set and cleared by hardware"); so the writable bits are compared (mask ~0xC)."""
    for key in (False, True):
        m = clock_start(lambda mm: setattr(mm, 'sws_stuck', 2), key)
        regs = m.st['regs']
        check(FLASH_AC not in regs, 'key %s: FLASH_AC written 0x%X' % (key, regs.get(FLASH_AC, 0)))
        check(regs.get(RCC_CTRL) == 1, 'key %s: RCC_CTRL 0x%08X, expected HSIEN only' % (key, regs.get(RCC_CTRL, 0)))
        if not key:
            check(regs.get(RCC_CFG, 0) & ~0xC == 0, 'RCC_CFG 0x%08X, expected 0 in the writable bits (SCLKSW = 00 only)'
                  % regs.get(RCC_CFG, 0))
    return True


@case
def c24_slot_pll_lock_bound():
    """The PLL never locks (pll_locks False): fn_080020c4's PLLRDF wait ends after CLK_POLLS reads,
    PLLEN is cleared, the APB prescaler bits 0x2500 are cleared, the HSE-failure exit returns; the
    core stays on the HSI (SCLKSW 00). HSEEN stays set, the PLL fields as written (PLLSRC HSE,
    0x08040000), FLASH_AC = 0x90 | LATENCY 4. Application start and update mode both reached (on the
    meter USB has no 48 MHz clock then: USBCLK comes from the PLL, manual 6.2.4)."""
    for key in (False, True):
        m = clock_start(lambda mm: setattr(mm, 'pll_locks', False), key)
        regs = m.st['regs']
        ctrl, cfg = regs.get(RCC_CTRL, 0), regs.get(RCC_CFG, 0)
        check(not ctrl & PLLEN and ctrl & HSEEN, 'key %s: RCC_CTRL 0x%08X' % (key, ctrl))
        check(cfg & 3 == 0 and not cfg & APB_DIVS and cfg & PLL_FIELDS == 0x08050000,
              'key %s: RCC_CFG 0x%08X' % (key, cfg))
        check(regs.get(FLASH_AC) == 0x94, 'key %s: FLASH_AC 0x%X' % (key, regs.get(FLASH_AC, 0)))
    return True


@case
def c25_slot_switch_to_pll_bound():
    """SCLKSTS stuck at 00 (sws_stuck 0: the switch to the PLL never happens): fn_080020c4's wait for
    SCLKSTS = 10 ends after CLK_POLLS reads, SCLKSW = 00 is written again, the wait back ends at its
    first read (SCLKSTS 00), the APB prescaler bits are cleared, the HSE-failure exit returns. The
    PLL stays enabled (nothing selects it). Application start and update mode both reached."""
    for key in (False, True):
        m = clock_start(lambda mm: setattr(mm, 'sws_stuck', 0), key)
        regs = m.st['regs']
        ctrl, cfg = regs.get(RCC_CTRL, 0), regs.get(RCC_CFG, 0)
        check(ctrl & PLLEN and ctrl & HSEEN, 'key %s: RCC_CTRL 0x%08X' % (key, ctrl))
        check(cfg & 3 == 0 and not cfg & APB_DIVS, 'key %s: RCC_CFG 0x%08X' % (key, cfg))
    return True


class RccCfgLate:
    """RCC_CFG 0x40021004 as a plain register, except SCLKSTS (bits 3:2): it reads SCLKSW until the
    first write that sets SCLKSW = 10; after that write the next `late` reads give 00 and every
    later read gives 10, whatever SCLKSW says (a switch to the PLL that completes just after the
    last poll of fn_080020c4's bounded wait and is not undone within the wait back)."""
    ranges = [(0x40021004, 0x40021008)]

    def __init__(self, late):
        self.value, self.late, self.armed, self.reads = 0, late, False, 0

    def read(self, m, a, size):
        if not self.armed:
            sws = self.value & 3
        else:
            self.reads += 1
            sws = 0 if self.reads <= self.late else 2
        return (self.value & ~0xC) | sws << 2

    def write(self, m, a, size, value):
        if size == 4:
            if value & 3 == 2 and self.value & 3 != 2:
                self.armed = True
            self.value = value


@case
def c26_slot_switch_late_prescalers_stay():
    """RccCfgLate with late = CLK_POLLS: the switch wait's CLK_POLLS reads give 00 (timeout), the
    reads after them give 10: SCLKSW = 00 is written, the wait back reads 10 CLK_POLLS times and runs
    out too, so the APB prescaler bits stay set (the PLL may run the core: PCLK2 <= 72 MHz, PCLK1 <=
    36 MHz need them, manual lines 6294 / 6302), then the HSE-failure exit. Reads of RCC_CFG after
    the arming write: CLK_POLLS (switch wait) + 1 (the read before SCLKSW = 00) + CLK_POLLS (wait back).
    rcc_strict is off: the device holds RCC_CFG, which the model's strict rules read from the register
    file."""
    dev = {}

    def setup(mm):
        dev['d'] = mm.attach(RccCfgLate(CLK_POLLS))
    m = clock_start(setup, False, strict=False)
    d = dev['d']
    check(d.value & 3 == 0 and d.value & APB_DIVS == APB_DIVS, 'RCC_CFG 0x%08X' % d.value)
    check(m.st['regs'].get(RCC_CTRL, 0) & PLLEN, 'PLLEN cleared')
    check(d.reads >= 2 * CLK_POLLS + 1, 'RCC_CFG reads after SCLKSW = 10: %d' % d.reads)
    NOTES.append('c26: RCC_CFG reads from SCLKSW = 10 to the application start: %d' % d.reads)
    return True


@case
def c27_slot_clock_slow_but_within_bounds():
    """The PLL locks after 1000 reads (pll_lock_reads) and the switch to it completes after 1000 reads
    (rcc_switch_reads), both far below CLK_POLLS: the normal path, the PLL runs the core (SCLKSW 10,
    PLLEN set, prescaler bits 0x2500 set), application start and update mode reached."""
    def setup(mm):
        mm.pll_lock_reads = 1000
        mm.rcc_switch_reads = 1000
    for key in (False, True):
        m = clock_start(setup, key)
        regs = m.st['regs']
        ctrl, cfg = regs.get(RCC_CTRL, 0), regs.get(RCC_CFG, 0)
        check(ctrl & PLLEN, 'key %s: RCC_CTRL 0x%08X' % (key, ctrl))
        check(cfg & 3 == 2 and cfg & APB_DIVS == APB_DIVS, 'key %s: RCC_CFG 0x%08X' % (key, cfg))
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
        print('%-52s %s %s' % (fn.__name__, 'ok' if ok else 'FAIL', msg))
        bad += not ok
    for n in NOTES:
        print('  note:', n)
    print('%d tests, %d failed' % (run, bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
