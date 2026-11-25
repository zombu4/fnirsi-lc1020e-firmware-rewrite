#!/usr/bin/env python3
"""check_pack.py - static check of the packed data of our application build.

Usage (from the repository root, after `make -C firmware vendor-data IMAGE=...` and
`make -C firmware own`):
    python3 -I tests/check_pack.py

Specification: PACKING_DESIGN.md revision 2, section 6, checks 1 to 4. Inputs: the vendor
application vendor/LC1020E_V1.1_250702.bin (V1.1, at 0x08006000), our build
firmware/build/own/APP_OWN.bin with app_own.elf and app_own.map, the objects
firmware/build/own/src/*.o and firmware/build/own/mod/*.o, and the vendor block
firmware/assets/vendor/08051530.bin (the packed initial RAM image).

The piece map: our build keeps V1.1 0x08006000..0x0805152F in order and reduces each of the 18
freed ranges of LANGUAGE_DESIGN.md section 3 to (its size mod 4) bytes of 0xFF; the packed RAM
image 0x08051530..0x08051757 is replaced by the typed image d_08051530. So a kept V1.1 address a
sits at map(a) = a - (sum of size - size mod 4 over the freed ranges below a). The map is checked
against the ELF first (P0: every d_<address> label of a kept address sits at map(address)).

Pointer words come from `arm-none-eabi-objdump -r` of the objects (R_ARM_ABS32 and R_ARM_REL32,
with their symbols), placed through the input-section addresses of app_own.map.

  P0  every label d_<a> (a in 0x0802AE94..0x0805152F, outside the freed ranges) is at map(a)
  C1  every V1.1 byte of 0x08006000..0x0805152F outside the freed ranges sits at map(old) with
      its V1.1 value, except the listed .ifdef OWN sites (PATCHES) and the pointer words: an
      ABS32 word holds map(V1.1 value) and V1.1 value + (S_own - S_v11) of its symbol S, a REL32
      word the V1.1 distance moved by S_own - S_v11 (pc-relative: the code does not move)
  C2  every 4-aligned V1.1 word of 0x08006000..0x0805152F (outside the freed ranges) whose value
      lies in 0x0802B703..0x08051757 is a relocated word of our build or on DATA_WORDS
  C3  the typed RAM image (0x57C bytes at d_08051530) equals the unpacked vendor image (the
      __decompress format, 0x08007954..0x080079A8) with row 0 := row 1 of the 17 per-language
      tables, except that each flash word holds map(V1.1 value); the region table entry 0 names
      d_08051530, 0x20000000, 0x57C and copy_init_addr
  C4  each freed range left (size mod 4) bytes of 0xFF; the free block from own_image_end to
      0x08062000 is reported
Exit status 0 only when every check passes. check() raises AssertionError; run() returns the
notes (test_own_lang.py l08 calls it).
"""

import hashlib
import os
import re
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
FW = os.path.join(REPO, 'firmware')
VENDOR_APP = os.path.join(REPO, 'vendor', 'LC1020E_V1.1_250702.bin')
V11_ELF = os.path.join(FW, 'build', 'app.elf')
OWN_BIN = os.path.join(FW, 'build', 'own', 'APP_OWN.bin')
OWN_ELF = os.path.join(FW, 'build', 'own', 'app_own.elf')
OWN_MAP = os.path.join(FW, 'build', 'own', 'app_own.map')
PACKED_RAM = os.path.join(FW, 'assets', 'vendor', '08051530.bin')
OBJDUMP = 'arm-none-eabi-objdump'
NM = 'arm-none-eabi-nm'

APP = 0x08006000
APP_END = 0x08062000            # bootloader/src/slot.inc APP_END
CODE_END = 0x0802AE94           # link_own.ld: the vendor code ends here
DATA_END = 0x08051530           # V1.1: region table end = start of the packed RAM image
V11_END = 0x08051758            # V1.1 image end
TABLE = 0x08051510              # region table d_08051510
RAM_IMAGE_SIZE = 0x57C
RAM_IMAGE_SHA256 = '1fda84d6edcc3e8f6535c6351bf73e576655cb3405b312ba23fd2e815185217d'  # NOTES.md
FIRST_FREED = 0x0802B703

# LANGUAGE_DESIGN.md section 3: the 18 freed ranges (first, last), 10538 bytes
FREED = [(0x0802B703, 0x0802C2A3), (0x0802C504, 0x0802C693), (0x0802C69C, 0x0802C6FF), (0x0802C7D8, 0x0802C809),
         (0x0802C856, 0x0802C887), (0x0802D84F, 0x0802E78F), (0x0802E9B8, 0x0802EB0F), (0x0802EB1C, 0x0802EB71),
         (0x0802EC1D, 0x0802EC47), (0x0802EC8D, 0x0802ECB7), (0x0803C410, 0x0803CBB3),
         (0x080510E0, 0x080510EB), (0x08051100, 0x0805110F), (0x08051268, 0x080512D7), (0x080512E8, 0x08051413),
         (0x0805144C, 0x080514BB), (0x080514DC, 0x080514EB), (0x08051500, 0x0805150F)]

# the per-language pointer tables of the initial RAM image {row 0 address: words per row}
# (LANGUAGE_DESIGN.md section 3; row 1 follows row 0)
TABLES = {0x20000024: 1, 0x2000002C: 1, 0x20000034: 1, 0x2000003C: 1, 0x20000044: 1, 0x20000054: 9,
          0x2000009C: 12, 0x200000FC: 4, 0x2000011C: 5, 0x20000144: 2, 0x20000154: 2, 0x20000164: 2,
          0x20000174: 4, 0x20000194: 2, 0x20000224: 4, 0x20000258: 6, 0x200002A8: 1}

# .ifdef OWN sites outside the data pointers (V1.1 address, length, what): bytes that differ from
# V1.1 by design. Each is a same-size change at a fixed code address or a patched data field.
PATCHES = [
    # the hook sites of the earlier stages (vectors.s, periph_34.s, app_01.s, app_02.s, measure_33.s,
    # ui_42.s, gui_21.s, gui_24.s, gui_25.s, system_40.s)
    (0x08006090, 4, 'hook'), (0x080060E8, 4, 'hook'), (0x08008210, 4, 'hook'), (0x080085F0, 4, 'hook'),
    (0x080085FC, 4, 'hook'), (0x08008608, 4, 'hook'), (0x08008D30, 4, 'hook'), (0x08008DC0, 4, 'hook'),
    (0x08008E04, 2, 'hook'), (0x08009474, 4, 'hook'), (0x08009A68, 4, 'hook'), (0x0800A8A0, 2, 'hook'),
    (0x0800B5C0, 4, 'hook'), (0x0800BD1A, 4, 'hook'), (0x0800D922, 4, 'hook'), (0x08023690, 4, 'hook'),
    (0x0802636A, 4, 'hook'), (0x08026A3C, 4, 'hook'), (0x08028018, 4, 'hook'), (0x08028030, 4, 'hook'),
    (0x080281D0, 4, 'hook'),
    (0x0800F294, 4, 'b.w own_menu at the entry of fn_0800f294'),
    # VENDOR_FIXES_DESIGN.md F8 / F9: the battery icon tail call, the logo entry
    (0x0800C862, 4, 'b.w own_batt_icon for the tail b.w fn_0800c724 of fn_0800c848'),
    (0x0800CE54, 4, 'b.w own_logo at the entry of fn_0800ce54'),
    # MEASUREMENT_FIX_DESIGN.md stage 1: S1.1 timer / DAC set-up calls, the measurement core call,
    # S1.6 the I-channel upper limit, S1.9 the factory-table protection
    (0x08007C00, 4, 'bl own_tim1_setup for bl fn_08007e7c'), (0x08008808, 4, 'bl own_dac_setup for bl fn_08008814'),
    (0x08009F20, 4, 'bl own_dac_setup for bl fn_08008814'), (0x080281D4, 4, 'bl own_measure for bl fn_0800a068'),
    (0x0800B072, 4, 'movw r1, #0xe10 for movw r1, #0xbb8'), (0x0800BD0A, 2, 'b.n for bne.n .L0800bd1a'),
    (0x08009A64, 2, 'nop.n for beq.n .L08009a82'),
    (0x0800860C, 28, 'the enables of fn_080085d0 as b.w own_dma_enable, 7 nop.n (V / I together)'),
    # MEASUREMENT_FIX_DESIGN.md stages 2 / 2F / 2G (revision 6): the formatter calls and row draws
    # (S2.1, S2.2, S2.4), the AUTO block and the compare block of fn_0800f854 (S2.5, S2.8, S2.9),
    # the frequency key, the 60 Hz OL group (S2.12), the vendor compare call (S2.8)
    (0x0800D2E4, 4, 'bl own_fmt_rs for bl fn_0800e028'), (0x0800D32A, 4, 'bl own_fmt_x for bl fn_0800e028'),
    (0x0800D356, 4, 'bl own_fmt_dqs for bl fn_0800dd44'), (0x0800D378, 4, 'bl own_fmt_th for bl fn_0800dfc4'),
    (0x0800D380, 4, 'bl own_row_draw for bl fn_0800d14c'), (0x0800D43C, 4, 'bl own_fmt_rz for bl fn_0800e028'),
    (0x0800D452, 4, 'bl own_fmt_c for bl fn_0800db24'), (0x0800D48C, 4, 'bl own_fmt_l for bl fn_0800de2c'),
    (0x0800D4B8, 4, 'bl own_row_draw for bl fn_0800d14c'),
    # MEASUREMENT_FIX_DESIGN.md revision 14: the value-word address for the two shared formatter calls
    # (r3 instead of s0)
    (0x0800D340, 4, 'addw r3, r5, #0x358 for vldr s0, [r5, #0x358] (D)'),
    (0x0800D34C, 4, 'addw r3, r5, #0x354 for vldr s0, [r5, #0x354] (Q)'),
    (0x0800D406, 4, 'addw r3, r0, #0x348 for vldr s0, [r0, #0x348] (|Z|)'),
    (0x0800D432, 4, 'addw r3, r0, #0x33c for vldr s0, [r0, #0x33c] (R)'),
    (0x0800F874, 0x78, 'bl own_auto_class, b.n, nop.n, the kept .L0800f8d6 b.n (AUTO block)'),
    (0x0800F8FC, 0x108, 'bl own_cmp_show, b.n, nop.n, the kept .L0800f94a b.n (compare block)'),
    (0x0800D97A, 4, 'b.w own_freq_step for ldr r1 / movs r5'), (0x0800A03A, 2, 'bls.n for beq.n .L0800a050'),
    (0x080281E2, 4, 'nop.w for bl fn_0800a7ec'),
    # MEASUREMENT_FIX_DESIGN.md stage 3 (revision 7): the vendor sweep's running test (own/cal.s runs it)
    (0x0800BDBA, 4, 'movs.n r0, #0 / nop.n for ldr.w r0, [r1, #0xb68]'),
    # LANGUAGE_DESIGN.md: the factory suffix, the menu toggle, the font counts
    (0x08009B08, 12, 'factory suffix "(FACT)"'), (0x0800D844, 12, 'factory suffix "(FACT)"'),
    (0x0800F78E, 4, 'nop.w for str.w r0, [r4, #0xbe0]'), (0x0800F796, 4, 'nop.w for str.w r5, [r4, #0xbe0]'),
    (0x0802C788, 2, 'F1 range 6 code count'), (0x0802EBD4, 2, 'F2 range 4 code count'),
    # the region table: entry 0 handler (copy_init_addr), entry 1 source (image_end)
    (0x0805151C, 4, 'region table entry 0 handler'), (0x08051520, 4, 'region table entry 1 source'),
    # MEASUREMENT_FIX_DESIGN.md revision 17: the reset handler's clock call (17.1), the bounded clock
    # waits of fn_0800ba4c and its cbz as cmp / beq.n / nop, the start-up stage calls of the main
    # function (17.2), the secondary-key mark at the dispatch (17.4); 0x08028030 and 0x08009474 above
    (0x0800628C, 4, 'own_reset for fn_0800c274 (Reset_Handler literal)'),
    (0x0800BA8C, 6, 'cmp r1, #0 / beq.n / nop for ldrb.w r1, [sp] / cbz r1'),
    (0x0800BAD6, 6, 'bl own_pll_wait / beq.n for the PLLRDF wait'),
    (0x0800BAEC, 10, 'bl own_sw_wait / beq.n / nop.w for the SCLKSTS wait'),
    (0x0802817C, 4, 'bl own_stg_814c'), (0x08028180, 4, 'bl own_stg_lcd'), (0x0802818A, 4, 'bl own_stg_logo'),
    (0x0802818E, 4, 'bl own_stg_b0d8'), (0x08028192, 4, 'bl own_stg_87d4'), (0x08028196, 4, 'bl own_stg_8024'),
    (0x0802819A, 4, 'bl own_stg_first for ldr.w r0, [r4, #0xbc4]'),
    (0x080097B8, 4, 'bl own_sec_key for ldr.w r0, [r4, #0xc6c]'),
]
# the speed icon pool words (V1.1 address, V1.1 target of our build): pointer words whose target
# differs by design (LANGUAGE_DESIGN.md 3)
POOL_RETARGET = {0x08009954: 0x08040F10, 0x0800995C: 0x08041184, 0x08009964: 0x08040C9C,
                 0x0800CE00: 0x08040F10, 0x0800CE08: 0x08041184, 0x0800CE14: 0x08040C9C}
# the expected bytes of the patched fields whose value is fixed (checked as they are)
PATCH_BYTES = {0x08009B08: b'(FACT)' + bytes(6), 0x0800D844: b'(FACT)' + bytes(6),
               0x0800F78E: bytes.fromhex('aff30080'), 0x0800F796: bytes.fromhex('aff30080'),
               0x0802C788: struct.pack('<H', 1), 0x0802EBD4: struct.pack('<H', 1),
               # MEASUREMENT_FIX_DESIGN.md S1.6 (movw T3, imm16 0x0E10), S1.9 (b.n T2 offset 12, nop.n)
               0x0800B072: bytes.fromhex('40f61061'), 0x0800BD0A: struct.pack('<H', 0xE006),
               0x08009A64: struct.pack('<H', 0xBF00),
               # stage 2F / 2G: bls.n T1 (cond 9, the offset 9 of the beq.n it replaces), nop.w
               0x0800A03A: struct.pack('<H', 0xD909), 0x080281E2: bytes.fromhex('aff30080'),
               # stage 3: movs T1 r0, #0 (0x2000), nop T1 (0xBF00)
               0x0800BDBA: struct.pack('<HH', 0x2000, 0xBF00),
               # revision 14: addw T4 (0xF200 | i << 10 | Rn, imm3 << 12 | Rd << 8 | imm8; imm12 0x358 /
               # 0x354 / 0x348 / 0x33C: i 0, imm3 3, Rd r3)
               0x0800D340: struct.pack('<HH', 0xF205, 0x3358), 0x0800D34C: struct.pack('<HH', 0xF205, 0x3354),
               0x0800D406: struct.pack('<HH', 0xF200, 0x3348), 0x0800D432: struct.pack('<HH', 0xF200, 0x333C)}

# 4-aligned V1.1 words with a value in 0x0802B703..0x08051757 that are data, not addresses
# (RESOURCE_FACTS.md 1b, 2f): V1.1 address -> what
DATA_WORDS = {
    # 32-bit Thumb-2 instructions with Rd = r8 (objdump of build/app.elf)
    0x08006C1C: 'add.w r8, r5, r3',
    0x0800E508: 'mov.w r8, #3',
    0x08012EB0: 'add.w r8, r8, #4',
    0x08013AF8: 'add.w r8, sp, #4',
    0x0801A618: 'sub.w r8, r5, #4',
    0x0801A72C: 'bfi r8, r3, #0, #5',
    0x0801EB58: 'mov.w r8, #3',
    0x080298A8: 'mla r8, ip, r4, r0',
    # literals and tables that are numbers
    0x0800BB10: 'system_40.s literal 0x08040000: RCC_CFG bits ORed in at 0x0800BAC8',
    0x0802AEE4: 'byte table 1, 2, 4, 8, .. (d_0802aee4)',
    # pixel bytes (RESOURCE_FACTS.md 1b)
    0x0803A5C0: 'pixel bytes of the image 0x0803b15c (data 0x0803a120..)',
    0x0803B0F0: 'pixel bytes of the image 0x0803b15c (data 0x0803a120..)',
    0x0803B608: 'pixel bytes of the image 0x0803c1a4 (data 0x0803b168..)',
    0x0803C138: 'pixel bytes of the image 0x0803c1a4 (data 0x0803b168..)',
}


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def nm(elf):
    out = subprocess.run([NM, elf], capture_output=True, text=True, check=True).stdout
    sym = {}
    for line in out.splitlines():
        p = line.split()
        if len(p) == 3:
            sym.setdefault(p[2], int(p[0], 16))
    return sym


def w32(b, off):
    return struct.unpack_from('<I', b, off)[0]


class PieceMap:
    """V1.1 address -> address in our build, from the freed list (module docstring)."""

    def __init__(self):
        self.freed = sorted(FREED)
        self.kept = []                       # (V1.1 first, V1.1 end, our first)
        shift, a = 0, APP
        for f, l in self.freed:
            self.kept.append((a, f, a - shift))
            n = l - f + 1
            shift += n - n % 4
            a = l + 1
        self.kept.append((a, DATA_END, a - shift))
        self.total_shift = shift

    def __call__(self, old):
        for a, e, n in self.kept:
            if a <= old < e:
                return n + old - a
        return None

    def inverse(self, new):
        for a, e, n in self.kept:
            if n <= new < n + e - a:
                return a + new - n
        return None

    def remainder_at(self, f):
        """Our address of the (size mod 4) bytes left of the freed range starting at f."""
        for a, e, n in self.kept:
            if e == f:
                return n + e - a
        raise KeyError(hex(f))


def unpack(data, size):
    """The __decompress format (0x08007954..0x080079A8): token; literal count token & 7 (0: next
    byte), copies count - 1 bytes; run token >> 4 (0: next byte); bit 3: offset byte, run + 2 bytes
    from dst - offset, else run zero bytes; while dst < dst + size."""
    out, src = bytearray(), 0
    while len(out) < size:
        tok = data[src]; src += 1
        lit = tok & 7
        if lit == 0:
            lit = data[src]; src += 1
        run = tok >> 4
        if run == 0:
            run = data[src]; src += 1
        out += data[src:src + lit - 1]
        src += lit - 1
        if tok & 8:
            off = data[src]; src += 1
            p = len(out) - off
            for _ in range(run + 2):
                out.append(out[p]); p += 1
        else:
            out += bytes(run)
    return bytes(out)


def map_value(x, so, pm):
    """Our value of a V1.1 flash word x (so: symbols of our build): code (and the vector table)
    does not move, the packed image start and the image end are their labels, data words map."""
    if APP <= x < CODE_END:
        return x
    if x == DATA_END:
        return so['d_08051530']
    if x == V11_END:
        return so['image_end']
    return pm(x)


def expected_ram(so, pm=None):
    """The initial RAM image our build must produce (C3): the vendor block 08051530.bin unpacked,
    row 0 := row 1 of the 17 tables, each flash word mapped."""
    pm = pm or PieceMap()
    v = open(VENDOR_APP, 'rb').read()
    packed = open(PACKED_RAM, 'rb').read()
    check(packed == v[DATA_END - APP:DATA_END - APP + len(packed)], 'C3: 08051530.bin differs from V1.1')
    ram = bytearray(unpack(packed, RAM_IMAGE_SIZE))
    check(len(ram) == RAM_IMAGE_SIZE and hashlib.sha256(ram).hexdigest() == RAM_IMAGE_SHA256,
          'C3: unpacked V1.1 image: %d bytes, sha256 %s' % (len(ram), hashlib.sha256(ram).hexdigest()))
    for base, n in TABLES.items():
        off = base - 0x20000000
        ram[off:off + 4 * n] = ram[off + 4 * n:off + 8 * n]
    for off in range(0, RAM_IMAGE_SIZE, 4):
        x = w32(ram, off)
        if APP <= x < APP_END:
            want = map_value(x, so, pm)
            check(want is not None, 'C3: 0x%08X = 0x%08X lies in a freed range' % (0x20000000 + off, x))
            struct.pack_into('<I', ram, off, want)
    return bytes(ram)


def input_sections(map_path):
    """{(object path, section name): address} from the linker map."""
    text = open(map_path).read()
    sec = {}
    for m in re.finditer(r'^ (\.[^\s*]+)\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+(\S+\.o)$', text, re.M):
        name, addr, size, obj = m.group(1), int(m.group(2), 16), int(m.group(3), 16), m.group(4)
        if size:
            sec[(obj, name)] = addr
    return sec


def relocations(sections):
    """[(address in our build, type, symbol)] of every R_ARM_ABS32 / R_ARM_REL32 of the objects."""
    out = []
    objs = sorted({o for o, _ in sections})
    for obj in objs:
        dump = subprocess.run([OBJDUMP, '-r', os.path.join(FW, obj)], capture_output=True, text=True,
                              check=True).stdout
        name = None
        for line in dump.splitlines():
            m = re.match(r'RELOCATION RECORDS FOR \[(.+)\]:', line)
            if m:
                name = m.group(1)
                continue
            m = re.match(r'([0-9a-f]{8}) (R_ARM_ABS32|R_ARM_REL32)\s+(\S+)', line)
            if m and name is not None:
                base = sections.get((obj, name))
                check(base is not None, '%s: section %s not in the map' % (obj, name))
                sym = re.sub(r'[+-]0x[0-9a-f]+$', '', m.group(3))
                out.append((base + int(m.group(1), 16), m.group(2), sym))
    return out


def run():
    notes = []
    v = open(VENDOR_APP, 'rb').read()
    o = open(OWN_BIN, 'rb').read()
    so, sv = nm(OWN_ELF), nm(V11_ELF)
    pm = PieceMap()
    check(len(v) == V11_END - APP, 'V1.1 size %d' % len(v))
    check(sum(l - f + 1 for f, l in FREED) == 10538 and pm.total_shift == 10524,
          'freed list: %d bytes, shift %d' % (sum(l - f + 1 for f, l in FREED), pm.total_shift))
    check(so['own_image_end'] == APP + len(o), 'own_image_end 0x%08X, image end 0x%08X'
          % (so['own_image_end'], APP + len(o)))

    def vword(a):
        return w32(v, a - APP)

    def oword(a):
        return w32(o, a - APP)

    def in_freed(a):
        return any(f <= a <= l for f, l in FREED)

    # P0: the labels against the map
    labels = 0
    for name, addr in so.items():
        m = re.fullmatch(r'd_(0[0-9a-f]{7})', name)
        if not m:
            continue
        old = int(m.group(1), 16)
        if CODE_END <= old < DATA_END and not in_freed(old):
            check(addr == pm(old), 'P0: %s at 0x%08X, map 0x%08X' % (name, addr, pm(old)))
            labels += 1
    check(so['d_08051510'] == pm(TABLE) and so['d_08051530'] == pm(TABLE) + 32,
          'P0: region table 0x%08X, image 0x%08X' % (so['d_08051510'], so['d_08051530']))
    notes.append('P0: %d labels at map(address)' % labels)

    # pointer words of our build in the mapped part
    sections = input_sections(OWN_MAP)
    relocs = relocations(sections)
    own_start = so['d_08051530']
    ptr = {}                                  # our address -> (type, symbol)
    for addr, typ, sym in relocs:
        if APP <= addr < own_start:
            check(addr % 4 == 0, 'relocated word at unaligned 0x%08X' % addr)
            ptr[addr] = (typ, sym)

    # C1
    patched = set()
    for a, n, what in PATCHES:
        patched |= set(range(a, a + n))
    for a, want in PATCH_BYTES.items():
        check(o[pm(a) - APP:pm(a) - APP + len(want)] == want, 'C1: %s at 0x%08X' % (hex(a), pm(a)))
    n_abs = n_rel = 0
    covered = set()
    for new, (typ, sym) in sorted(ptr.items()):
        old = pm.inverse(new)
        check(old is not None, 'C1: relocated word at 0x%08X outside the mapped pieces' % new)
        covered |= set(range(old, old + 4))
        if old in patched:
            continue
        vv, ov = vword(old), oword(new)
        if typ == 'R_ARM_REL32':
            check(sym in sv and sym in so, 'C1: REL32 0x%08X symbol %s' % (old, sym))
            check(ov == (vv + so[sym] - sv[sym]) & 0xFFFFFFFF, 'C1: REL32 at 0x%08X (V1.1 0x%08X) holds 0x%08X, '
                  'V1.1 0x%08X moved by %d' % (new, old, ov, vv, so[sym] - sv[sym]))
            n_rel += 1
            continue
        if old in POOL_RETARGET:
            check(ov == pm(POOL_RETARGET[old]), 'C1: pool word 0x%08X holds 0x%08X' % (old, ov))
            n_abs += 1
            continue
        want = map_value(vv, so, pm)
        check(want is not None, 'C1: ABS32 at 0x%08X: V1.1 value 0x%08X lies in a freed range' % (old, vv))
        check(ov == want, 'C1: ABS32 at 0x%08X (V1.1 0x%08X, %s) holds 0x%08X, map(0x%08X) = 0x%08X'
              % (new, old, sym, ov, vv, want))
        if sym in sv and sym in so:
            check(ov == (vv + so[sym] - sv[sym]) & 0xFFFFFFFF, 'C1: ABS32 at 0x%08X: symbol %s moved by %d'
                  % (new, sym, so[sym] - sv[sym]))
        n_abs += 1
    bad = []
    for a, e, n in pm.kept:
        for old in range(a, e):
            if old in covered or old in patched:
                continue
            if v[old - APP] != o[n + old - a - APP]:
                bad.append(old)
    check(not bad, 'C1: %d bytes differ from V1.1, first V1.1 addresses %r' % (len(bad), [hex(x) for x in bad[:8]]))
    notes.append('C1: %d kept bytes, %d ABS32 and %d REL32 words checked, %d patched sites'
                 % (sum(e - a for a, e, _ in pm.kept), n_abs, n_rel, len(PATCHES)))

    # C2
    raw = []
    for a in range(APP, DATA_END, 4):
        if any(in_freed(x) for x in range(a, a + 4)):
            continue
        x = vword(a)
        if FIRST_FREED <= x < V11_END and pm(a) not in ptr and a not in DATA_WORDS:
            raw.append((a, x))
    check(not raw, 'C2: %d raw words with an address value, first %r'
          % (len(raw), [(hex(a), hex(x)) for a, x in raw[:8]]))
    for a in DATA_WORDS:
        check(FIRST_FREED <= vword(a) < V11_END and pm(a) not in ptr and o[pm(a) - APP:pm(a) - APP + 4] == v[a - APP:a - APP + 4],
              'C2: data word 0x%08X not as listed' % a)
    notes.append('C2: no raw address word; %d data words listed' % len(DATA_WORDS))

    # C3
    want = expected_ram(so, pm)
    img = so['d_08051530']
    typed = o[img - APP:img - APP + RAM_IMAGE_SIZE]
    check(len(typed) == RAM_IMAGE_SIZE, 'C3: typed image cut short')
    flash = 0
    for off in range(0, RAM_IMAGE_SIZE, 4):
        x, y = w32(want, off), w32(typed, off)
        check(y == x, 'C3: 0x%08X holds 0x%08X, expected 0x%08X' % (0x20000000 + off, y, x))
        flash += APP <= x < APP_END
    tab = so['d_08051510']
    check(struct.unpack_from('<4I', o, tab - APP) == (img, 0x20000000, RAM_IMAGE_SIZE, so['copy_init_addr']),
          'C3: region table entry 0 %r' % [hex(x) for x in struct.unpack_from('<4I', o, tab - APP)])
    check(struct.unpack_from('<4I', o, tab + 16 - APP) == (so['image_end'], 0x2000057C, 0x15E2C,
                                                            sv['zero_fill_words_addr']),
          'C3: region table entry 1 %r' % [hex(x) for x in struct.unpack_from('<4I', o, tab + 16 - APP)])
    check(so['image_end'] == img + RAM_IMAGE_SIZE, 'C3: image_end 0x%08X' % so['image_end'])
    notes.append('C3: typed RAM image at 0x%08X equals the unpacked V1.1 image (row 0 := row 1), %d flash words '
                 'mapped' % (img, flash))

    # C4
    left = 0
    for f, l in FREED:
        r = (l - f + 1) % 4
        at = pm.remainder_at(f)
        check(o[at - APP:at - APP + r] == b'\xff' * r, 'C4: remainder of 0x%08X at 0x%08X' % (f, at))
        left += r
    check(left == 14, 'C4: %d bytes left of the freed ranges' % left)
    end = so['own_image_end']
    notes.append('C4: 14 bytes of 0xFF left of 10538 freed; free block 0x%08X..0x%08X, %d bytes'
                 % (end, APP_END - 1, APP_END - end))
    return notes


def main():
    try:
        notes = run()
    except AssertionError as e:
        print('check_pack: FAIL %s' % e)
        sys.exit(1)
    for n in notes:
        print('  ' + n)
    print('check_pack: OK')


if __name__ == '__main__':
    main()
