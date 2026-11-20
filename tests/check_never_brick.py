#!/usr/bin/env python3
"""check_never_brick.py - static never-brick scan of the starter and the three slot bootloaders.

Usage (from the repository root, after `make -C starter`, `make -C bootloader` and
`make -C bootloader slot`):
    python3 -I tests/check_never_brick.py

Images: starter/build/STARTER.bin (at 0x08000000, ELF starter/build/starter.elf) and
bootloader/build/slot/BOOT_F/A/B.bin (header + image at 0x08069000 / 0x0806F000 / 0x08075000, ELFs
build/slot/<X>/boot.elf). Control: the stock build bootloader/build/BOOT.bin (boot.elf), which must
be reported where it differs, and planted copies of BOOT_A.bin that must fail.

Per image:
  W1  no 4-aligned word in 0x1FFFF000..0x1FFFFFFF (system memory top / option bytes)
  W2  no 4-aligned word 0x40022008 (FLASH_OPTKEY), 0x4002201C (OB), 0x40022020 (WRP)
  W3  no 4-aligned word in 0x0807F000..0x0807FFFF (settings / calibration page)
  W4  no 4-aligned word in 0x08000000..0x08005FFF; the starter: only its 16-word vector table
  D1  disassembly (arm-none-eabi-objdump -d of the ELF), register values followed inside each
      function from pc-relative literal loads, movw / movt / mov immediates and add / sub
      immediates: no constructed value of W1 / W2 / W3 / W4 (W4: slots only), and no store whose
      address is 0x40022008, 0x4002201C or 0x40022020
  D2  the routines that load or build a flash-controller address (0x40022000..0x400223FF) are
      exactly the listed ones (ALLOWED below), with the offsets they store to
Exit status 0 only when every image passes and every control is reported as expected.
"""
import os
import re
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OBJDUMP = 'arm-none-eabi-objdump'

FC_LO, FC_HI = 0x40022000, 0x40022400
BAD_FC = (0x40022008, 0x4002201C, 0x40022020)

# Routines allowed to hold a flash-controller address, from the sources:
# starter.s: start_slot (CTRL lock before the jump), append_record (CTRL lock after the record),
#   flash_unlock (KEY), flash_wait (STS), flash_erase / flash_word (CTRL, ADD)
# slot: fn_08000e14 (STS flags), fn_08000e24 (page erase), fn_08000e68 (STS state), fn_08000ea4
#   (LOCK), fn_08000eb4 (word program), fn_08000efc (KEY), fn_080020c4 and fn_08002598 (clock set-up:
#   flash access control register +0, wait states / prefetch), slot_10.s rec_append (CTRL lock),
#   rec_flash_unlock, rec_flash_wait, rec_flash_erase, rec_flash_word
ALLOWED_STARTER = {'start_slot', 'append_record', 'flash_unlock', 'flash_wait', 'flash_erase', 'flash_word'}
ALLOWED_SLOT = {'fn_08000e14', 'fn_08000e24', 'fn_08000e68', 'fn_08000ea4', 'fn_08000eb4', 'fn_08000efc',
                'fn_080020c4', 'fn_08002598', 'rec_append', 'rec_flash_unlock', 'rec_flash_wait',
                'rec_flash_erase', 'rec_flash_word'}


def classify(v, slot):
    out = []
    if 0x1FFFF000 <= v <= 0x1FFFFFFF:
        out.append('W1 system memory / option bytes')
    if v in BAD_FC:
        out.append('W2 flash option / protection register')
    if 0x0807F000 <= v <= 0x0807FFFF:
        out.append('W3 settings page')
    if slot and 0x08000000 <= v <= 0x08005FFF:
        out.append('W4 below the application area')
    return out


def word_scan(data, base, is_starter):
    bad = []
    for off in range(0, len(data) - 3, 4):
        v = struct.unpack_from('<I', data, off)[0]
        for c in classify(v, True):
            if c.startswith('W4') and is_starter and off < 0x40:
                continue                    # the starter's own vector table
            bad.append('%s: word 0x%08X at 0x%08X' % (c, v, base + off))
    return bad


REG = r'(r\d+|sl|fp|ip|sp|lr|pc)'
ALIAS = {'sl': 'r10', 'fp': 'r11', 'ip': 'r12'}


def reg(name):
    return ALIAS.get(name, name)


def imm(text):
    m = re.search(r'#(-?0x[0-9a-fA-F]+|-?\d+)', text)
    return None if m is None else int(m.group(1), 0) & 0xFFFFFFFF


def disasm_scan(elf, data, base, slot):
    """Returns (bad list, {function: set of flash-controller offsets stored, or 'held'})."""
    out = subprocess.run([OBJDUMP, '-d', '--no-show-raw-insn', elf], capture_output=True, text=True,
                         check=True).stdout
    bad, users = [], {}
    func, regs = None, {}

    def lit(addr):
        o = addr - base
        if 0 <= o <= len(data) - 4:
            return struct.unpack_from('<I', data, o)[0]
        return None

    def note(v, where, how):
        if v is None:
            return
        for c in classify(v, slot):
            bad.append('D1 %s: 0x%08X %s in %s at %s' % (c, v, how, func, where))
        if FC_LO <= v < FC_HI:
            users.setdefault(func, set()).add('held 0x%08X' % v)

    for line in out.splitlines():
        h = re.match(r'^([0-9a-f]{8}) <([^>]+)>:$', line)
        if h:
            func, regs = h.group(2), {}
            continue
        m = re.match(r'^\s+([0-9a-f]+):\s+(\S+)\s*(.*)$', line)
        if not m or func is None:
            continue
        where, mn, ops = m.group(1), m.group(2), m.group(3)
        ops_main = ops.split('@')[0].strip()
        if mn.startswith('.word') or mn.startswith('.short') or mn.startswith('.byte'):
            continue
        dst = re.match(REG, ops_main)
        rd = reg(dst.group(1)) if dst else None
        base_mn = mn.split('.')[0]
        if base_mn.startswith('ldr') and '[pc' in ops_main:
            c = re.search(r'@ \(?([0-9a-f]+)', ops)
            v = lit(int(c.group(1), 16)) if c else None
            if base_mn in ('ldr',):
                regs[rd] = v
                note(v, where, 'literal')
            else:
                regs.pop(rd, None)
            continue
        if base_mn in ('movw',):
            regs[rd] = imm(ops_main)
            note(regs[rd], where, 'movw')
            continue
        if base_mn in ('movt',):
            if regs.get(rd) is not None:
                regs[rd] = (regs[rd] & 0xFFFF) | (imm(ops_main) << 16 & 0xFFFFFFFF)
                note(regs[rd], where, 'movw/movt')
            continue
        if base_mn in ('mov', 'movs') and '#' in ops_main:
            regs[rd] = imm(ops_main)
            note(regs[rd], where, 'mov immediate')
            continue
        if base_mn in ('mvn', 'mvns') and '#' in ops_main:
            regs[rd] = ~imm(ops_main) & 0xFFFFFFFF
            note(regs[rd], where, 'mvn immediate')
            continue
        if base_mn in ('add', 'adds', 'sub', 'subs', 'addw', 'subw') and '#' in ops_main:
            parts = [p.strip() for p in ops_main.split(',')]
            src = reg(parts[1]) if len(parts) == 3 else rd
            k = imm(ops_main)
            v = regs.get(src)
            if v is not None and k is not None:
                v = (v + k if base_mn.startswith('add') else v - k) & 0xFFFFFFFF
                regs[rd] = v
                note(v, where, 'add / sub')
            else:
                regs.pop(rd, None)
            continue
        if base_mn.startswith('str') or base_mn.startswith('stm'):
            a = re.search(r'\[' + REG + r'(?:,\s*#(-?0x[0-9a-f]+|-?\d+))?\]', ops_main)
            b = None
            if a:
                rn, off = reg(a.group(1)), int(a.group(2), 0) if a.group(2) else 0
                b = regs.get(rn)
            elif base_mn.startswith('stm'):
                rn = reg(re.match(REG, ops_main).group(1))
                off, b = 0, regs.get(rn)
            if b is not None:
                ea = (b + off) & 0xFFFFFFFF
                if ea in BAD_FC:
                    bad.append('D1 store to 0x%08X in %s at %s' % (ea, func, where))
                if FC_LO <= ea < FC_HI:
                    users.setdefault(func, set()).add('store +0x%X' % (ea - FC_LO))
                if a and ops_main.rstrip().endswith('!'):
                    regs[rn] = ea
            continue
        if base_mn in ('bl', 'blx'):
            for r in ('r0', 'r1', 'r2', 'r3', 'r12', 'lr'):
                regs.pop(r, None)
            continue
        if base_mn.startswith('pop') or base_mn.startswith('ldm'):
            for r in re.findall(REG, ops_main):
                regs.pop(reg(r), None)
            continue
        if base_mn.startswith(('cmp', 'cmn', 'tst', 'teq', 'b', 'cb', 'it', 'nop', 'dsb', 'isb', 'dmb',
                               'cps', 'msr', 'push', 'svc', 'bkpt', 'wfi', 'wfe')):
            continue
        if rd is not None:
            regs.pop(rd, None)
    return bad, users


def check_image(name, binp, elf, base, is_starter):
    data = open(binp, 'rb').read()
    bad = word_scan(data, base, is_starter)
    code_base = base if is_starter or name.startswith('stock') else base + 0x200
    code = data if is_starter or name.startswith('stock') else data[0x200:]
    d_bad, users = disasm_scan(elf, code, code_base, not is_starter)
    bad += d_bad
    allowed = ALLOWED_STARTER if is_starter else ALLOWED_SLOT
    extra = sorted(set(users) - allowed)
    if extra:
        bad.append('D2 flash-controller address in routines outside the list: %s' % extra)
    return bad, users


def main():
    fails = 0
    imgs = [('STARTER', os.path.join(REPO, 'starter/build/STARTER.bin'), os.path.join(REPO, 'starter/build/starter.elf'),
             0x08000000, True)]
    for x, b in (('F', 0x08069000), ('A', 0x0806F000), ('B', 0x08075000)):
        imgs.append(('BOOT_%s' % x, os.path.join(REPO, 'bootloader/build/slot/BOOT_%s.bin' % x),
                     os.path.join(REPO, 'bootloader/build/slot/%s/boot.elf' % x), b, False))
    for name, binp, elf, base, st in imgs:
        bad, users = check_image(name, binp, elf, base, st)
        print('%-8s %s' % (name, 'OK' if not bad else 'FAIL'))
        for k in sorted(users):
            print('    flash controller: %-18s %s' % (k, ', '.join(sorted(users[k]))))
        for b in bad:
            print('    ' + b)
        fails += bool(bad)

    # control 1: the stock bootloader must be reported where it differs
    bad, users = check_image('stock', os.path.join(REPO, 'bootloader/build/BOOT.bin'),
                             os.path.join(REPO, 'bootloader/build/boot.elf'), 0x08000000, False)
    kinds = sorted(set(b.split(':')[0] for b in bad))
    print('control stock BOOT.bin: %d findings, kinds %s' % (len(bad), kinds))
    for b in bad[:6]:
        print('    ' + b)
    if not any(b.startswith('W4') for b in bad):
        print('    CONTROL FAIL: stock words below 0x08006000 not reported')
        fails += 1

    # control 2: planted words in a copy of BOOT_A.bin must each be found
    src = open(os.path.join(REPO, 'bootloader/build/slot/BOOT_A.bin'), 'rb').read()
    for v, kind in ((0x1FFFF800, 'W1'), (0x40022008, 'W2'), (0x0807F000, 'W3'), (0x08001234, 'W4')):
        d = bytearray(src)
        struct.pack_into('<I', d, 0x4000, v)
        found = [c for c in classify(v, True)] and word_scan(bytes(d), 0x0806F000, False)
        ok = any(f.startswith(kind) and ('0x%08X' % v) in f for f in found)
        print('control planted 0x%08X: %s' % (v, 'found' if ok else 'NOT FOUND'))
        fails += not ok
    # control 3: a store to FLASH_OPTKEY through base + offset, and a movw / movt option-byte address,
    # in a small assembled routine, must be found by the disassembly scan
    import tempfile
    d = tempfile.mkdtemp(prefix='nb_ctl_')
    s = os.path.join(d, 't.s')
    open(s, 'w').write('.syntax unified\n.thumb\n.text\n.global probe\n.thumb_func\nprobe:\n'
                       ' ldr r0, =0x40022000\n str r1, [r0, #8]\n movw r2, #0xF800\n movt r2, #0x1FFF\n'
                       ' bx lr\n.ltorg\n')
    subprocess.run(['arm-none-eabi-as', '-mcpu=cortex-m4', '-mthumb', '-o', s + '.o', s], check=True)
    subprocess.run(['arm-none-eabi-ld', '-Ttext=0x08070000', '-e', 'probe', '-o', s + '.elf', s + '.o'], check=True)
    subprocess.run(['arm-none-eabi-objcopy', '-O', 'binary', s + '.elf', s + '.bin'], check=True)
    cb, cu = disasm_scan(s + '.elf', open(s + '.bin', 'rb').read(), 0x08070000, True)
    ok3 = any('store to 0x40022008' in b for b in cb) and any('0x1FFFF800 movw/movt' in b for b in cb)
    print('control assembled store to 0x40022008 and movw/movt 0x1FFFF800: %s' % ('found' if ok3 else 'NOT FOUND %r' % cb))
    fails += not ok3
    print('%s' % ('never-brick check: PASS' if not fails else 'never-brick check: FAIL (%d)' % fails))
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
