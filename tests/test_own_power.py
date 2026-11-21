#!/usr/bin/env python3
"""test_own_power.py - the automatic power-off of our application build (firmware/own/power.s), in the
emulator: Off Time (VENDOR_FIXES_DESIGN.md F2) and the low-voltage countdown (F3).

Usage (from the repository root, after `make -C starter`, `make -C bootloader slot` and
`make -C firmware own`):
    <python with unicorn 2.1.4> tests/test_own_power.py [case-name-prefix ...]

Rig: tests/test_own_control.py Ctl (meter_model in flash mode 'app' with timing, KeyPad, MeasurePath with
DutSource, UsbDevice / UsbHost), imported, not changed. Expected values come from the rules in the header
of firmware/own/power.s and the RAM words named per check.

Time. power.s times everything with the GUI tick 0x20000480 (+10 per SysTick, fn_080277a0), and the
model's SysTick counts the core clock in emulated time, so the tick follows emulated time whatever the
model's cycles per instruction (cpi) is. The Off Time cases need minutes of emulated time; at the
model's default cpi 5 one emulated second costs about 8 s here. Those cases therefore start at cpi 5 and,
once the main loop runs, continue at cpi 30 (slow_core: the emulated time stays continuous): the core
then executes 6 times fewer instructions per second. meter_model states that the manual gives no
instruction timing (cpi is the model's choice); the watchdog is checked at LSI 30 kHz in these cases
(the datasheet's lowest LSI, period 2501 * 16 / 30000 = 1.334 s; a main-loop pass with a redraw then
takes about 0.74 s, scaled from 0.49 s measured at cpi 20, tests run 2026-11-20). The low-voltage cases
run at cpi 5 and the default LSI 60 kHz of test_own_control.

Supply voltage: DutSource(supply_v) gives ADC4 channel 3 the code round(supply_v * 4095 / 6.6); the
DMA2 channel 8 (circular, ADC4 DAT 0x40021C4C) of MeasurePath writes it into 0x20005D38, and
fn_080092cc averages the 128 halfwords to the float 0x20005100 = mean * 6.6 / 4095. 3.0 V gives the code
1861 (2.9996 V, at or below the floor 3.2 V), 4.0 V the code 2482 (4.0003 V, above it).
"""

import os
import struct
import sys

from unicorn import UC_HOOK_MEM_WRITE, UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_PC, UC_ARM_REG_LR, UC_ARM_REG_R0, UC_ARM_REG_R1

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_own_control import (Ctl, check, block_with, copy_image, f32, stretch_in, OWN_CTL, CT_FLAGS,  # noqa: E402
                              CF_OFF, SAVE_COUNT, SAVE_STATUS, V_TICK, V_SCREEN, V_LOWV, V_SUPPLY)
from measure_model import DutSource  # noqa: E402

CASES = []
NOTES = []

# ---- own.inc / power.s ----
OWN_PWR = 0x20018000 + 0x5FE0
PW_FLAGS, PW_IDLE_T, PW_SEC_T, PW_ANS_SEEN, PW_LIVE, PW_REASON, PW_STARTS = (OWN_PWR + 4 * i for i in range(7))
PF_PRIMED, PF_REQ = 0x01, 0x02
PL_BG, PL_PANEL, PL_TRACK = 0x01, 0x02, 0x80
RS_OFFTIME, RS_LOWV = 1, 2
V_OFFTIME = 0x20001164
V_POPUP_BG, V_POPUP_PANEL = 0x20000290, 0x20000294
FN_POPUP = 0x0800CF68            # fn_0800cf68 (ui_41.s): r0 = build flag, r1 = number
FN_OBJ_DEL = 0x08023690          # fn_08023690 (gui_21.s): r0 = object
LR_VENDOR_DEL = 0x0800C7E3       # return address of the bl fn_08023690 at 0x0800C7DE (fn_0800c724)
LSI_SLOW = 30000
CPI_SLOW = 30
OFF5 = 300.0                     # Off Time 1: 5 min (power.s pwr_off_ms)
KEY_OK, KEY_0010, KEY_0400 = 0x0008, 0x0010, 0x0400


def case(fn):
    CASES.append(fn)
    return fn


def slow_core(rig, cpi=CPI_SLOW):
    """From here on the model core takes cpi cycles per instruction; the emulated time stays continuous
    (meter_model now() = t0 + icount * cpi / core + extra: t0 moved by the change)."""
    m = rig.m
    ic = m._icount_at(m.uc.reg_read(UC_ARM_REG_PC))
    m.tm['t0'] += ic * (m.timing['cpi'] - cpi) / m.timing['core']
    m.timing['cpi'] = float(cpi)


def tick(rig):
    return rig.rd(V_TICK)


def powered(rig):
    return rig.m.st['pa8'] != 0


def run_until_off(rig, seconds):
    """Run until PA8 is driven low (0x0800B274) or seconds pass; returns the emulated time or None."""
    end = rig.m.run_for(seconds=seconds, until=lambda mm: mm.st['pa8'] == 0)
    check(end is None, 'chip run ended %r (violations %r)' % (end, rig.m.st['viol']))
    return rig.m.now() if rig.m.st['pa8'] == 0 else None


def check_power_off(rig, saves, reason, what):
    """The power-off path of POWER_OFF ran: own_save wrote (count + 1, status 0), PA8 low, the reason
    word, and 1.2 s later (USB power in the model: the meter still runs) the powered-off mode CF_OFF."""
    check(rig.m.st['pa8'] == 0, '%s: PA8 not low' % what)
    check(rig.rd(PW_REASON) == reason, '%s: reason %d, expected %d' % (what, rig.rd(PW_REASON), reason))
    check(rig.rd(PW_STARTS) == 1, '%s: power_path called %d times' % (what, rig.rd(PW_STARTS)))
    check(rig.rd(SAVE_COUNT) == saves + 1 and rig.rd(SAVE_STATUS) == 0,
          '%s: save count %d (before %d), status 0x%X' % (what, rig.rd(SAVE_COUNT), saves, rig.rd(SAVE_STATUS)))
    rig.run(1.2)
    check(rig.rd(OWN_CTL + CT_FLAGS) & CF_OFF, '%s: powered-off mode not entered' % what)


def off_rig(offtime, usb=False):
    blk = block_with(**{'0x%08X' % V_OFFTIME: offtime})
    rig = Ctl(a=copy_image(blk, 2), b=copy_image(blk, 1), usb=usb, lsi=LSI_SLOW)
    rig.up()
    check(rig.rd(V_OFFTIME) == offtime, 'Off Time word %d, expected %d' % (rig.rd(V_OFFTIME), offtime))
    slow_core(rig)
    return rig


# ---------------------------------------------------------------- F2 Off Time

@case
def p1_off_time_5_min_key_at_4_min_resets():
    """Off Time 1 (5 min), no USB host: a physical key (0x0010, 60 ms) at 4 min restarts the idle time
    (PW_IDLE_T = the tick of its event); no power-off at 5 min after the start; the power-off path at 5 min
    after the key: requested on the first second of the grid with an idle time >= 300 s, then the save
    (about 0.75 s, test_own_control k09) and PA8 low: within 300.0 .. 303.0 s of the key's release."""
    rig = off_rig(1)
    t_start = rig.m.now()
    rig.run(240.0 - (rig.m.now() - t_start))
    check(powered(rig) and not rig.rd(PW_FLAGS) & PF_REQ, 'power-off before 4 min')
    idle0 = rig.rd(PW_IDLE_T)
    rig.press(KEY_0010, 60)                              # run 0.06 s held, then 0.1 s
    t_key = rig.m.now() - 0.1
    idle1 = rig.rd(PW_IDLE_T)
    check(idle1 > idle0 + 200000, 'the key did not restart the idle time (%d -> %d ms)' % (idle0, idle1))
    saves = rig.rd(SAVE_COUNT)
    rig.run(t_start + OFF5 + 20.0 - rig.m.now())         # past 5 min after the start
    check(powered(rig) and not rig.rd(PW_FLAGS) & PF_REQ, 'power-off at 5 min after the start')
    rig.run(t_key + OFF5 - 1.0 - rig.m.now())
    check(powered(rig), 'power-off before 5 min after the key')
    t_off = run_until_off(rig, 5.0)
    check(t_off is not None, 'no power-off within 5 min + 4 s after the key')
    dt = t_off - t_key
    check(OFF5 <= dt <= OFF5 + 3.0, 'PA8 low %.2f s after the key' % dt)
    check_power_off(rig, saves, RS_OFFTIME, 'Off Time')
    NOTES.append('p1: PA8 low %.2f s after the key; longest watchdog stretch %.3f s'
                 % (dt, stretch_in(rig.m, t_start, rig.m.now())))
    return True


@case
def p2_off_time_0_never_then_1_at_once():
    """Off Time 0: 5 min + 10 s idle without any power-off request (the idle time still counts:
    tick - PW_IDLE_T >= 300 s); then the word 0x20001164 written to 1 from outside (no activity):
    the next second requests the power-off, PA8 low within 3 s."""
    rig = off_rig(0)
    t_start = rig.m.now()
    rig.run(OFF5 + 10.0)
    idle = (tick(rig) - rig.rd(PW_IDLE_T)) / 1000.0
    check(powered(rig) and not rig.rd(PW_FLAGS) & PF_REQ, 'Off Time 0: power-off requested')
    check(idle >= OFF5, 'Off Time 0: idle time %.1f s' % idle)
    saves = rig.rd(SAVE_COUNT)
    rig.wr(V_OFFTIME, 1)
    t_set = rig.m.now()
    t_off = run_until_off(rig, 3.0)
    check(t_off is not None, 'Off Time 1 after %.1f s idle: no power-off within 3 s' % idle)
    check_power_off(rig, saves, RS_OFFTIME, 'Off Time 0 -> 1')
    NOTES.append('p2: idle %.1f s with Off Time 0; PA8 low %.2f s after the word became 1; stretch %.3f s'
                 % (idle, t_off - t_set, stretch_in(rig.m, t_start, rig.m.now())))
    return True


@case
def p3_dtr_holds_the_idle_time():
    """Off Time 1 with a host that enumerated and set DTR (UsbHost.enumerate): 5 min + 10 s without a
    request and without a power-off request, the idle tick taken every pass (tick - PW_IDLE_T below
    0.2 s); after SET_CONTROL_LINE_STATE with DTR 0 the idle time counts (3 s later at least 2.5 s)."""
    rig = off_rig(1, usb=True)
    rig.run(OFF5 + 10.0)
    lag = (tick(rig) - rig.rd(PW_IDLE_T)) / 1000.0
    check(powered(rig) and not rig.rd(PW_FLAGS) & PF_REQ, 'DTR set: power-off requested')
    check(lag < 0.2, 'DTR set: idle tick %.3f s old' % lag)
    rig.host.set_control_line_state(dtr=False)
    rig.run(3.0)
    lag = (tick(rig) - rig.rd(PW_IDLE_T)) / 1000.0
    check(lag >= 2.5, 'DTR clear: idle time %.3f s after 3 s' % lag)
    NOTES.append('p3: DTR clear, idle %.3f s after 3 s' % lag)
    return True


# ---------------------------------------------------------------- F3 low voltage

def lowv_rig():
    src = DutSource(supply_v=4.0)
    rig = Ctl(usb=False, source=src).up()
    rig.src = src
    m = rig.m
    rig.cnt_log, rig.pop_log, rig.del_log = [], [], []

    def cnt(uc, acc, addr, size, value, user):
        rig.cnt_log.append((m.now(), value))
    m.uc.hook_add(UC_HOOK_MEM_WRITE, cnt, begin=V_LOWV, end=V_LOWV + 3)

    def pop(uc, addr, size, user):
        rig.pop_log.append((m.now(), uc.reg_read(UC_ARM_REG_R0), uc.reg_read(UC_ARM_REG_R1)))
    m.uc.hook_add(UC_HOOK_CODE, pop, begin=FN_POPUP, end=FN_POPUP)

    def dele(uc, addr, size, user):
        rig.del_log.append((m.now(), uc.reg_read(UC_ARM_REG_R0), uc.reg_read(UC_ARM_REG_LR)))
    m.uc.hook_add(UC_HOOK_CODE, dele, begin=FN_OBJ_DEL, end=FN_OBJ_DEL)
    rig.done_log = []
    back = rig.s['own_obj_del_back'] & ~1                # fix.s: the deletion is carried out

    def done(uc, addr, size, user):
        rig.done_log.append((m.now(), uc.reg_read(UC_ARM_REG_R0)))
    m.uc.hook_add(UC_HOOK_CODE, done, begin=back, end=back)
    rig.step_log = []                                     # every pwr_step call (power.s), the countdown's clock

    def step(uc, addr, size, user):
        rig.step_log.append(m.now())
    m.uc.hook_add(UC_HOOK_CODE, step, begin=rig.s['pwr_step'] & ~1, end=rig.s['pwr_step'] & ~1)
    check(rig.rd(V_LOWV) == 0 and f32(rig.rd(V_SUPPLY)) > 3.9, 'start: countdown %d, supply %.3f V'
          % (rig.rd(V_LOWV), f32(rig.rd(V_SUPPLY))))
    return rig


def wait_count(rig, value, seconds):
    end = rig.m.run_for(seconds=seconds, until=lambda mm: rig.rd(V_LOWV) == value)
    check(end is None and rig.rd(V_LOWV) == value, 'countdown %d not reached (now %d, end %r)'
          % (value, rig.rd(V_LOWV), end))


@case
def p4_low_voltage_countdown_then_power_off():
    """Supply 3.0 V: within 1.1 s the popup built (fn_0800cf68(1, 10), 0x20005118 = 10, both objects
    tracked), then once a second 9, 8, .. 0 stored and shown (fn_0800cf68(0, n)), each on the 1 s grid
    of the first: stored by the first pwr_step call at or after its grid point (a redraw outside
    ctl_loop, fn_08012188 from the timer walk, can hold that call back; NOTES "STATE stream gaps"),
    never before it, and the grid does not drift; at 0 the power-off path (PA8 low within 2.5 s)."""
    rig = lowv_rig()
    saves = rig.rd(SAVE_COUNT)
    t0 = rig.m.now()
    rig.src.supply_v = 3.0
    t_off = run_until_off(rig, 15.0)
    check(t_off is not None, 'no power-off within 15 s at 3.0 V')
    vals = [v for _, v in rig.cnt_log]
    check(vals == list(range(10, -1, -1)), 'countdown values %r' % vals)
    times = [t for t, _ in rig.cnt_log]
    check(times[0] - t0 <= 1.1, 'popup %.3f s after the voltage drop' % (times[0] - t0))
    # pwr_step's grid counts on the GUI tick 0x20000480, +10 per SysTick (ctl.inc V_TICK): 10 ms
    # steps, so in model time a grid point lies up to one step before or after times[0] + k
    step = 0.010
    late = []
    for k, t in enumerate(times[1:], 1):
        grid = times[0] + k
        check(t >= grid - step, 'count %d stored %.3f s before its grid point' % (10 - k, grid - t))
        calls = [c for c in rig.step_log if c <= t]
        check(calls, 'count %d stored outside pwr_step' % (10 - k))
        # every call but the one that stored (the last entry before the store) is a missed one
        missed = [c for c in calls[:-1] if c >= grid + step]
        check(not missed, 'count %d: pwr_step ran %d time(s) between its grid point and the store'
              % (10 - k, len(missed)))
        late.append(t - grid)
    steps = [b - a for a, b in zip(times, times[1:])]
    calls = [(r0, r1) for _, r0, r1 in rig.pop_log]
    check(calls == [(1, 10)] + [(0, n) for n in range(9, -1, -1)], 'popup calls %r' % calls)
    check(f32(rig.rd(V_SUPPLY)) < 3.01, 'supply %.4f V' % f32(rig.rd(V_SUPPLY)))
    check(t_off - times[-1] <= 2.5, 'PA8 low %.3f s after the count reached 0' % (t_off - times[-1]))
    check(not rig.del_log, 'objects deleted: %r' % rig.del_log)
    check_power_off(rig, saves, RS_LOWV, 'low voltage')
    NOTES.append('p4: popup %.3f s after the drop, steps %.3f .. %.3f s, latest store %.3f s after its grid '
                 'point, PA8 low %.3f s after 0' % (times[0] - t0, min(steps), max(steps), max(late),
                                                     t_off - times[-1]))
    return True


@case
def p5_recovery_removes_the_popup():
    """(a) 3.0 V until the count is 7, then 4.0 V: the next second 0x20005118 = 0 and fn_08023690 for the
    background 0x20000290 then the panel 0x20000294 (as 0x0800C7D8..0x0800C7E8), nothing tracked, and
    no power-off in the 12 s that follow. (b) 3.0 V again: a new popup (fn_0800cf68(1, 10)); a long key
    0x400 (1.2 s: screen 1 -> 2, fn_08009614 deletes the measure screen with fn_08023690) takes the
    background along (PW_LIVE = track | panel); 4.0 V: only the panel is deleted, the freed background
    is not touched. (c) 3.0 V, a popup on screen 2, long key 0x400 (2 -> 1: the background goes with
    screen 2), then 4.0 V right after a step of pwr_step and a long OK whose event comes before the
    next step: the settings build (fn_0800d6e4 -> fn_0800c848 -> fn_0800c724, above 3.2 V with the
    countdown running) calls fn_08023690 for the freed background from 0x0800C7DE (return address
    0x0800C7E3), which fix.s does not carry out (own_obj_del_back not reached with it), and deletes the
    panel; 0x20005118 = 0."""
    rig = lowv_rig()
    rig.src.supply_v = 3.0
    wait_count(rig, 7, 6.0)
    bg, panel = rig.rd(V_POPUP_BG), rig.rd(V_POPUP_PANEL)
    check(bg and panel and rig.rd(PW_LIVE) == PL_TRACK | PL_BG | PL_PANEL,
          '(a) objects 0x%08X 0x%08X, PW_LIVE 0x%X' % (bg, panel, rig.rd(PW_LIVE)))
    n_del = len(rig.del_log)
    rig.src.supply_v = 4.0
    wait_count(rig, 0, 1.3)
    rig.run(0.05)
    dels = [o for _, o, _lr in rig.del_log[n_del:]]
    check(dels == [bg, panel], '(a) deleted %r, expected [0x%08X, 0x%08X]' % (['0x%08X' % o for o in dels], bg, panel))
    check(rig.rd(PW_LIVE) == 0, '(a) PW_LIVE 0x%X' % rig.rd(PW_LIVE))
    check(run_until_off(rig, 12.0) is None and not rig.rd(PW_FLAGS) & PF_REQ and rig.rd(V_LOWV) == 0,
          '(a) power-off or countdown after the recovery')
    n_pop = len(rig.pop_log)
    rig.src.supply_v = 3.0
    wait_count(rig, 10, 1.3)
    rig.run(0.05)                                        # 0x20005118 = 10 is stored before the build
    check([(r0, r1) for _, r0, r1 in rig.pop_log[n_pop:]] == [(1, 10)], '(b) popup calls %r' % rig.pop_log[n_pop:])
    bg, panel = rig.rd(V_POPUP_BG), rig.rd(V_POPUP_PANEL)
    check(rig.rd(V_SCREEN) == 1, '(b) screen %d before the key' % rig.rd(V_SCREEN))
    rig.press(KEY_0400, 1200)
    check(rig.rd(V_SCREEN) == 2, '(b) screen %d after the long key 0x400' % rig.rd(V_SCREEN))
    check(rig.rd(PW_LIVE) == PL_TRACK | PL_PANEL, '(b) PW_LIVE 0x%X after the screen change' % rig.rd(PW_LIVE))
    check(rig.rd(V_LOWV) != 0, '(b) countdown ended during the key')
    n_del = len(rig.del_log)
    rig.src.supply_v = 4.0
    wait_count(rig, 0, 1.3)
    rig.run(0.05)
    dels = [o for _, o, _lr in rig.del_log[n_del:]]
    check(dels == [panel], '(b) deleted %r, expected [0x%08X] (background 0x%08X freed with the screen)'
          % (['0x%08X' % o for o in dels], panel, bg))
    check(rig.rd(PW_LIVE) == 0 and powered(rig) and not rig.rd(PW_FLAGS) & PF_REQ, '(b) state after the recovery')
    # (c) the vendor's removal of a background that is gone
    rig.src.supply_v = 3.0
    wait_count(rig, 10, 1.3)
    rig.run(0.05)
    bg, panel = rig.rd(V_POPUP_BG), rig.rd(V_POPUP_PANEL)
    rig.press(KEY_0400, 1200)                            # screen 2 -> 1: the background goes with screen 2
    check(rig.rd(V_SCREEN) == 1 and rig.rd(PW_LIVE) == PL_TRACK | PL_PANEL,
          '(c) screen %d, PW_LIVE 0x%X after the key 0x400' % (rig.rd(V_SCREEN), rig.rd(PW_LIVE)))
    c = rig.rd(V_LOWV)
    check(c >= 4, '(c) countdown %d' % c)
    wait_count(rig, c - 1, 1.3)                          # a step of pwr_step (grid point T)
    rig.run(0.45)
    rig.keys.down |= KEY_OK                              # long OK: 0xFE about 1.0 s later, at T + 1.45
    wait_count(rig, c - 2, 1.0)                          # T + 1: pwr_step saw 3.0 V
    rig.src.supply_v = 4.0
    n_del, n_done = len(rig.del_log), len(rig.done_log)
    end = rig.m.run_for(seconds=0.8, until=lambda mm: rig.rd(V_SCREEN) == 3)
    rig.keys.down &= ~KEY_OK
    check(end is None, 'chip run ended %r (violations %r)' % (end, rig.m.st['viol']))
    rig.run(0.2)
    calls = [(o, lr) for _, o, lr in rig.del_log[n_del:]]
    done = [o for _, o in rig.done_log[n_done:]]
    check(rig.rd(V_SCREEN) == 3 and rig.rd(V_LOWV) == 0, '(c) screen %d, countdown %d after the long OK'
          % (rig.rd(V_SCREEN), rig.rd(V_LOWV)))
    check((bg, LR_VENDOR_DEL) in calls, '(c) 0x0800C724 did not remove the background: calls %r'
          % [('0x%08X' % o, '0x%08X' % lr) for o, lr in calls])
    check(bg not in done and panel in done, '(c) deletions carried out %r (background 0x%08X, panel 0x%08X)'
          % (['0x%08X' % o for o in done], bg, panel))
    rig.run(1.2)
    check(rig.rd(PW_LIVE) == 0 and powered(rig) and not rig.rd(PW_FLAGS) & PF_REQ and not rig.m.st['viol'],
          '(c) state after the recovery: PW_LIVE 0x%X, violations %r' % (rig.rd(PW_LIVE), rig.m.st['viol']))
    NOTES.append('p5: (a) deleted background and panel, (b) panel only, (c) the vendor removal of the freed '
                 'background not carried out, the panel deleted')
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
