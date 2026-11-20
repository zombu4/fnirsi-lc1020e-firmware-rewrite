#!/usr/bin/env python3
"""test_chain.py - the boot chain starter -> slot bootloader -> application, in the emulator.

Usage (from the repository root, after `make -C starter` and `make -C bootloader slot`):
    <python with unicorn 2.1.4> tests/test_chain.py

Flash: build/STARTER.bin at 0x08000000, build/slot/BOOT_F/A/B.bin at 0x08069000 / 0x0806F000 /
0x08075000, control records as each case says, and an application stub at 0x08006000 (vector table:
SP 0x20010000, reset 0x08006101). Peripheral and flash model: tests/meter_model.py. A start ends when
the CPU fetches from the application area (the application was started), when the slot reaches its
update-mode main loop (fn_08001150, after the USB start), at a system reset, at the starter's dead
end, or at a power cut. Every case also requires: no violation of the flash model (no store to code
flash, no option-byte register, nothing in 0x0807F000..0x0807FFFF), and every erase / programmed word
inside the record pages 0x08068000..0x08068FFF (the chain never writes the application area).
"""
import struct
import sys

from meter_model import (Meter, cell, app_stub, APP, REC0, REC1, REC_END, PAGE, SLOTS, FLAG,
                         FLAG_MAGIC, ST_INSTALL, ST_TRIAL, ST_OK)

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


def main():
    bad = 0
    for fn in CASES:
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
    print('%d tests, %d failed' % (len(CASES), bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
