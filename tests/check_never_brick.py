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

Application mode (our build, `make own` in firmware/):
    python3 -I tests/check_never_brick.py --app [APP_OWN.bin app_own.elf]
        (default firmware/build/own/APP_OWN.bin and app_own.elf, image at 0x08006000), then the
        application-mode controls
    python3 -I tests/check_never_brick.py --app-controls
        the controls only (a small assembled image with a planted save.s; no own build needed)
  The functions of save.s are found by symbol from the ELF: every label of firmware/own/save.s,
  local ones under the ELF's FILE symbol save.s / save.o, global ones by their .global name; each
  function's range runs from its symbol to the next symbol (objdump's grouping). A label of save.s
  missing from the ELF is a finding (A0).
  A1  no 4-aligned word and no constructed value in 0x1FFFF000..0x1FFFFFFF except the chip UID
      words 0x1FFFF7F0 / 0x1FFFF7F4 / 0x1FFFF7F8 (the serial number); no store there
  A2  no word / constructed value 0x40022008, 0x4002201C, 0x40022020 and no store to them (W2, D1)
  A3  the routines that load or build a flash-controller address are functions of save.s only
      (ALLOWED_OWN_EXTRA below names further ones by the owner's decision; it is empty)
  A4  every flash address (0x08000000..0x08080000) constructed in a save.s function, and every word
      of a save.s data label (up to the next symbol), lies in the gate: copy B 0x08066000..
      0x08067000, the record pages 0x08068000..0x08069000, slots A / B 0x0806F000..0x0807B000,
      copy A 0x0807F000..0x08080000, the own calibration area 0x08062000..0x08066000 (the end values are the exclusive bounds of save.s gate_ok),
      or is the address of a save.s symbol; so no page 0, application area or slot F target (only
      0x08069000 itself, REC_END, is accepted: it is the record pages' end bound)
  A5  no store to a constant flash address outside save.s; inside save.s only to the gate
  A6  every flash address (0x08000000..0x08080000) constructed in an own/ocal.s function, and every
      word of an ocal.s data label, lies in the own calibration area 0x08062000..0x08065FFF, or is
      0x08066000 (OCAL_END, the area's exclusive end bound), or is the address of an ocal.s or
      save.s symbol; A5 applies to ocal.s unchanged
  W3 / W4 do not apply (the settings pages are this mode's own targets; the application holds
  addresses of its own area).
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


def disasm_scan(elf, data, base, slot, keyed=False, collect=None, cls=None):
    """Returns (bad list, {function: set of flash-controller offsets stored, or 'held'}).
    keyed: functions are (name, address) instead of name; collect: a list that gets
    ('value', function, address, value, where, how) for every followed value and
    ('store', function, address, store address, where, mnemonic) for every store with a known base;
    cls: the classification of values (default classify)."""
    out = subprocess.run([OBJDUMP, '-d', '--no-show-raw-insn', elf], capture_output=True, text=True,
                         check=True).stdout
    bad, users = [], {}
    func, regs = None, {}
    fkey, faddr = None, None
    cls = classify if cls is None else cls

    def lit(addr):
        o = addr - base
        if 0 <= o <= len(data) - 4:
            return struct.unpack_from('<I', data, o)[0]
        return None

    def note(v, where, how):
        if v is None:
            return
        for c in cls(v, slot):
            bad.append('D1 %s: 0x%08X %s in %s at %s' % (c, v, how, func, where))
        if FC_LO <= v < FC_HI:
            users.setdefault(fkey, set()).add('held 0x%08X' % v)
        if collect is not None:
            collect.append(('value', func, faddr, v, where, how))

    for line in out.splitlines():
        h = re.match(r'^([0-9a-f]{8}) <([^>]+)>:$', line)
        if h:
            func, regs = h.group(2), {}
            faddr = int(h.group(1), 16)
            fkey = (func, faddr) if keyed else func
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
                    users.setdefault(fkey, set()).add('store +0x%X' % (ea - FC_LO))
                if collect is not None:
                    collect.append(('store', func, faddr, ea, where, mn))
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


# ---- application mode (our build) ----
SAVE_SRC = os.path.join(REPO, 'firmware', 'own', 'save.s')
OWN_BIN = os.path.join(REPO, 'firmware', 'build', 'own', 'APP_OWN.bin')
OWN_ELF = os.path.join(REPO, 'firmware', 'build', 'own', 'app_own.elf')
APP_BASE = 0x08006000
UID_WORDS = (0x1FFFF7F0, 0x1FFFF7F4, 0x1FFFF7F8)        # chip UID, 96 bits (own.inc CHIP_UID)
# Functions outside save.s allowed to hold a flash-controller address: {name: set of the
# 'store +0x..' / 'held 0x..' entries allowed}. Empty: only the owner can decide an entry.
ALLOWED_OWN_EXTRA = {
    # Owner's goal "nothing can brick the meter" (2026-11-20 decision): the vendor flash routines
    # stay in the image but are switched off in the own build (firmware/src/periph_34.s .ifdef OWN:
    # fn_08008d30 page erase and fn_08008dc0 word program return at once, fn_08008e04 unlock
    # returns at once, so FLASH_CTRL stays locked for every vendor routine); their remaining
    # helpers only clear status flags, read the status and set LOCK.
    'fn_08008d20': {'held 0x40022000', 'store +0xC'},       # FLASH_STS flag clear
    'fn_08008d30': {'held 0x40022000', 'store +0x10', 'store +0x14'},   # switched off
    'fn_08008d74': {'held 0x40022000'},                     # FLASH_STS read
    'fn_08008db0': {'held 0x40022000', 'store +0x10'},      # FLASH_CTRL LOCK
    'fn_08008dc0': {'held 0x40022000', 'store +0x10'},      # switched off
    # clock set-up: FLASH_AC (+0x0, wait states / prefetch) only
    'fn_0800ba4c': {'held 0x40022000', 'store +0x0'},
    'fn_0800c274': {'held 0x40022000', 'store +0x0'},
}
# Aligned words that look like system-memory addresses but are not accesses: the vendor data
# blocks of firmware/vendor_blobs.tsv (pixel / font data of V1.1, included by .incbin, never used
# as addresses by the code: the vendor image's own code holds no such literal) and the MEM_READ
# range table mem_ranges of own/cmd.s (range limits compared with the requested address).
A1_DATA_SYMBOLS = {'mem_ranges': 32}
# the gate of save.s gate_ok, each [lo, hi] with hi the exclusive end value of the range
APP_GATE = ((0x08062000, 0x08066000), (0x08066000, 0x08067000), (0x08068000, 0x08069000),
            (0x0806F000, 0x0807B000), (0x0807F000, 0x08080000))
OCAL_SRC = os.path.join(REPO, 'firmware', 'own', 'ocal.s')
OCAL_AREA = (0x08062000, 0x08066000)        # [lo, hi]: hi = OCAL_END, the exclusive end bound


def app_classify(v, slot=None):
    out = []
    if 0x1FFFF000 <= v <= 0x1FFFFFFF and v not in UID_WORDS:
        out.append('A1 system memory / option bytes')
    if v in BAD_FC:
        out.append('A2 flash option / protection register')
    return out


def in_flash(v):
    return 0x08000000 <= v <= 0x08080000


def in_gate(v):
    return any(lo <= v <= hi for lo, hi in APP_GATE)


def elf_symbols(elf):
    """readelf -s: list of (address, type, bind, name, file) for every named symbol in a section;
    file is the basename of the FILE symbol that precedes a local symbol (None for globals)."""
    out = subprocess.run(['arm-none-eabi-readelf', '-sW', elf], capture_output=True, text=True,
                         check=True).stdout
    syms, cur = [], None
    for line in out.splitlines():
        p = line.split()
        if len(p) < 8 or not p[0].endswith(':') or not p[0][:-1].isdigit():
            continue
        val, typ, bind, ndx, name = int(p[1], 16), p[3], p[4], p[6], p[7]
        if typ == 'FILE':
            cur = os.path.basename(name)
            continue
        if typ == 'SECTION' or name.startswith('$') or ndx in ('UND', 'ABS'):
            continue
        if typ == 'FUNC':
            val &= ~1
        syms.append((val, typ, bind, name, cur if bind == 'LOCAL' else None))
    return syms


def save_symbols(elf, src):
    """The labels of a module (save.s, ocal.s) in the ELF: ({name: (address, type)}, labels missing
    from the ELF). Local labels count under the FILE symbol <module>.s / <module>.o."""
    base = os.path.basename(src)[:-2]
    text = open(src).read()
    labels = set(re.findall(r'^([A-Za-z_][A-Za-z0-9_]*):', text, re.M))
    globs = set(re.findall(r'^\s*\.global\s+([A-Za-z_][A-Za-z0-9_]*)', text, re.M))
    found = {}
    for val, typ, bind, name, f in elf_symbols(elf):
        if name not in labels:
            continue
        if bind == 'LOCAL' and f in (base + '.s', base + '.o'):
            found[name] = (val, typ)
        elif bind == 'GLOBAL' and name in globs:
            found[name] = (val, typ)
    return found, sorted(labels - set(found))


def check_app(binp, elf, src=SAVE_SRC, base=APP_BASE, ocal_src=OCAL_SRC):
    """Application-mode scan; returns (findings, flash-controller users)."""
    data = open(binp, 'rb').read()
    bad = []
    a1_skip = []
    tsv = os.path.join(REPO, 'firmware', 'vendor_blobs.tsv')
    for line in open(tsv):
        f = line.split()
        if len(f) == 3 and not line.startswith('#') and f[0] != 'address':
            a1_skip.append((int(f[0], 16), int(f[0], 16) + int(f[1])))
    for a, t, b, n, fl in elf_symbols(elf):
        if n in A1_DATA_SYMBOLS:
            a1_skip.append((a, a + A1_DATA_SYMBOLS[n]))
    for off in range(0, len(data) - 3, 4):
        v = struct.unpack_from('<I', data, off)[0]
        a = base + off
        for c in app_classify(v):
            if c.startswith('A1') and any(lo <= a and a + 4 <= hi for lo, hi in a1_skip):
                continue
            bad.append('%s: word 0x%08X at 0x%08X' % (c, v, a))
    found, missing = save_symbols(elf, src)
    if missing:
        bad.append('A0 labels of %s missing from the ELF: %s' % (os.path.basename(src), missing))
    save_addr = {a for a, t in found.values()}
    ocal, o_missing = save_symbols(elf, ocal_src) if os.path.exists(ocal_src) else ({}, [])
    if o_missing:
        bad.append('A0 labels of %s missing from the ELF: %s' % (os.path.basename(ocal_src), o_missing))
    ocal_addr = {a for a, t in ocal.values()}
    own_syms = save_addr | ocal_addr

    def in_area(v):
        return OCAL_AREA[0] <= v <= OCAL_AREA[1]
    collect = []
    d_bad, users = disasm_scan(elf, data, base, True, keyed=True, collect=collect, cls=app_classify)
    bad += d_bad
    for (name, fa), how in sorted(users.items(), key=lambda x: x[0][1]):
        if fa in save_addr:
            continue
        if name in ALLOWED_OWN_EXTRA and how <= ALLOWED_OWN_EXTRA[name]:
            continue
        bad.append('A3 flash-controller address outside save.s: %s at 0x%08X (%s)'
                   % (name, fa, ', '.join(sorted(how))))
    for kind, name, fa, v, where, how in collect:
        mine = fa in save_addr
        if kind == 'store':
            if 0x1FFFF000 <= v <= 0x1FFFFFFF:
                bad.append('A1 store to 0x%08X in %s at %s' % (v, name, where))
            if in_flash(v) and (not mine or not in_gate(v)):
                bad.append('A5 store to flash 0x%08X in %s at %s' % (v, name, where))
        elif mine and in_flash(v) and not in_gate(v) and v not in save_addr:
            bad.append('A4 flash address 0x%08X (%s) in save.s %s at %s outside the gate' % (v, how, name, where))
        if kind != 'store' and fa in ocal_addr and in_flash(v) and not in_area(v) and v not in own_syms:
            bad.append('A6 flash address 0x%08X (%s) in ocal.s %s at %s outside the area' % (v, how, name, where))
    bounds = sorted({s[0] for s in elf_symbols(elf)} | {base + len(data)})
    for name, (a, typ) in sorted(found.items()):
        if typ == 'FUNC':
            continue
        end = next((b for b in bounds if b > a), base + len(data))
        for w in range(a, min(end, base + len(data)) - 3, 4):
            v = struct.unpack_from('<I', data, w - base)[0]
            if in_flash(v) and not in_gate(v) and v not in save_addr:
                bad.append('A4 word 0x%08X in save.s data %s at 0x%08X outside the gate' % (v, name, w))
    for name, (a, typ) in sorted(ocal.items()):
        if typ == 'FUNC':
            continue
        end = next((b for b in bounds if b > a), base + len(data))
        for w in range(a, min(end, base + len(data)) - 3, 4):
            v = struct.unpack_from('<I', data, w - base)[0]
            if in_flash(v) and not in_area(v) and v not in own_syms:
                bad.append('A6 word 0x%08X in ocal.s data %s at 0x%08X outside the area' % (v, name, w))
    return bad, users


def app_controls():
    """A planted image: other.s (first, at 0x08006000) and a control save.s; the findings must be
    exactly the planted ones. Returns the number of failures."""
    import tempfile
    d = tempfile.mkdtemp(prefix='nb_app_')
    other = os.path.join(d, 'other.s')
    save = os.path.join(d, 'save.s')
    head = '.syntax unified\n.thumb\n.text\n'
    open(other, 'w').write(head +
        '.global rogue\n.thumb_func\n.type rogue, %function\nrogue:\n'
        ' ldr r0, =0x40022000\n str r1, [r0, #4]\n ldr r2, =0x08070000\n str r1, [r2]\n bx lr\n.ltorg\n')
    ocal_s = os.path.join(d, 'ocal.s')
    open(ocal_s, 'w').write(head +
        '.global ocal_planted\n.thumb_func\n.type ocal_planted, %function\nocal_planted:\n'
        ' ldr r0, =0x08062000\n ldr r1, =0x08066000\n ldr r2, =0x08066004\n ldr r3, =0x08061FFC\n'
        ' ldr r2, =0x08062000\n str r1, [r2]\n bx lr\n.ltorg\n')
    open(save, 'w').write(head +
        '.global flash_word\n.thumb_func\n.type flash_word, %function\nflash_word:\n'
        ' ldr r0, =0x40022000\n str r1, [r0, #0x10]\n ldr r2, =0x0807F000\n ldr r2, =0x08069000\n'
        ' ldr r2, =0x08067000\n ldr r0, =0x1FFFF7F0\n ldr r1, =gate_ranges\n bx lr\n.ltorg\n'
        '.thumb_func\n.type bad_targets, %function\nbad_targets:\n'
        ' ldr r3, =0x08069800\n ldr r3, =0x08010000\n bx lr\n.ltorg\n'
        '.p2align 2\ngate_ranges:\n .word 0x08066000, 0x08067000, 0x1FFFF800\n')
    objs = []
    for s in (other, save, ocal_s):
        subprocess.run(['arm-none-eabi-as', '-mcpu=cortex-m4', '-mthumb', '-o', s[:-2] + '.o', s], check=True)
        objs.append(s[:-2] + '.o')
    elf, binp = os.path.join(d, 'ctl.elf'), os.path.join(d, 'ctl.bin')
    subprocess.run(['arm-none-eabi-ld', '-Ttext=0x%08X' % APP_BASE, '-e', 'rogue', '-o', elf] + objs, check=True)
    subprocess.run(['arm-none-eabi-objcopy', '-O', 'binary', elf, binp], check=True)
    bad, users = check_app(binp, elf, src=save, ocal_src=ocal_s)
    expect = ['A3 flash-controller address outside save.s: rogue',
              'A5 store to flash 0x08070000 in rogue',
              'A4 flash address 0x08069800',
              'A4 flash address 0x08010000',
              'A1 system memory / option bytes: word 0x1FFFF800',
              'A6 flash address 0x08066004',
              'A6 flash address 0x08061FFC',
              'A5 store to flash 0x08062000 in ocal_planted']
    fails = 0
    for e in expect:
        ok = sum(1 for b in bad if b.startswith(e)) == 1
        print('control app %-60s %s' % (e, 'found' if ok else 'NOT FOUND'))
        fails += not ok
    extra = [b for b in bad if not any(b.startswith(e) for e in expect)]
    if extra:
        print('    CONTROL FAIL: unexpected findings %r' % extra)
        fails += 1
    held = sorted('%s %s' % (k[0], sorted(v)) for k, v in users.items())
    print('control app flash-controller users: %s' % held)
    return fails


def main_app(argv):
    fails = 0
    if argv[0] == '--app':
        binp, elf = (argv[1], argv[2]) if len(argv) >= 3 else (OWN_BIN, OWN_ELF)
        for p in (binp, elf):
            if not os.path.exists(p):
                print('own build missing: %s' % p)
                sys.exit(1)
        bad, users = check_app(binp, elf)
        print('%-8s %s' % ('APP_OWN', 'OK' if not bad else 'FAIL'))
        for (name, fa) in sorted(users, key=lambda k: k[1]):
            print('    flash controller: %-24s 0x%08X %s' % (name, fa, ', '.join(sorted(users[(name, fa)]))))
        for b in bad:
            print('    ' + b)
        fails += bool(bad)
    fails += app_controls()
    print('never-brick application mode: %s' % ('PASS' if not fails else 'FAIL (%d)' % fails))
    sys.exit(1 if fails else 0)


def main():
    if len(sys.argv) > 1:
        if sys.argv[1] not in ('--app', '--app-controls'):
            print(__doc__)
            sys.exit(2)
        main_app(sys.argv[1:])
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
