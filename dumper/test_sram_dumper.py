#!/usr/bin/env python3
"""Emulator test of sram_dumper.bin (Unicorn, Cortex-M4 Thumb).

Usage: python3 test_sram_dumper.py SRAM_DUMPER_BIN   (needs the unicorn module)

Flash 0x08000000..0x0807FFFF is filled with deterministic bytes (SHA-256 chain), the dumper is
placed at 0x08006000, option bytes and GPIOA_PH_CFG get known values.  Run from the reset
vector until the SRAM wait loop has counted the heartbeat to 3.  Checks:
  - the copies at 0x20001000 / 0x20007000 equal flash, the option-byte copy equals 0x1FFFF800..
  - the three CRCs equal zlib.crc32 of the flash parts, result word 0 = "DUMP"
  - VTOR = 0x20000000, the SRAM vector table points at the SRAM fault entry, pc runs in SRAM
  - PA8: PBSC gets 0x100 before PH_CFG makes pin 8 an output; PH_CFG bits 31:4 unchanged,
    bits 3:0 = 0b0010; RCC_APB2PCLKEN bit 2 set, its other bits unchanged
  - every IWDG_KEY write is 0xAAAA; no write to flash, option bytes or the flash controller
"""
import hashlib
import struct
import sys
import zlib

from unicorn import Uc, UcError, UC_ARCH_ARM, UC_MODE_THUMB, UC_MODE_MCLASS, UC_HOOK_MEM_WRITE, UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_PC, UC_ARM_REG_SP

FLASH, FLASH_SIZE = 0x08000000, 0x80000
APP = 0x08006000
SRAM, SRAM_SIZE = 0x20000000, 0x24000
RESULT = 0x2001F000
OPT = bytes.fromhex("a55a00ff11ee22dd")  # 0x1FFFF800.. test pattern (8 halfword pairs)
OPT = OPT + bytes.fromhex("33cc44bb55aa6699")
PH_CFG_INIT = 0x88800004 | 0x00000040   # port A reset value plus a nibble on pin 9 and pin 8 = input
APB2_INIT = 0x00000201


def fill(n, seed):
    out = bytearray()
    h = hashlib.sha256(seed).digest()
    while len(out) < n:
        out += h
        h = hashlib.sha256(h).digest()
    return bytes(out[:n])


def main():
    dumper = open(sys.argv[1], "rb").read()
    flash = bytearray(fill(FLASH_SIZE, b"lc1020e flash"))
    flash[APP - FLASH:APP - FLASH + len(dumper)] = dumper
    flash = bytes(flash)

    uc = Uc(UC_ARCH_ARM, UC_MODE_THUMB | UC_MODE_MCLASS)
    uc.mem_map(FLASH, FLASH_SIZE)
    uc.mem_write(FLASH, flash)
    uc.mem_map(0x1FFFF000, 0x1000)
    uc.mem_write(0x1FFFF800, OPT)
    uc.mem_map(SRAM, SRAM_SIZE)
    uc.mem_map(0x40000000, 0x30000)
    uc.mem_write(0x40010804, struct.pack("<I", PH_CFG_INIT))
    uc.mem_write(0x40021018, struct.pack("<I", APB2_INIT))
    uc.mem_map(0xE000E000, 0x1000)

    events, errors = [], []
    state = {"pc_in_sram": False}

    def on_write(uc_, access, addr, size, value, user):
        if FLASH <= addr < FLASH + FLASH_SIZE or 0x1FFFF000 <= addr < 0x20000000 or 0x40022000 <= addr < 0x40022400:
            errors.append("write to 0x%08X" % addr)
        if addr == 0x40003000:
            if value != 0xAAAA:
                errors.append("IWDG_KEY write 0x%X" % value)
        elif addr in (0x40010804, 0x40010810, 0x40021018, 0xE000ED08):
            events.append((addr, value))

    def on_code(uc_, addr, size, user):
        if SRAM <= addr < SRAM + 0x1000:
            state["pc_in_sram"] = True
            if struct.unpack("<I", uc_.mem_read(RESULT + 16, 4))[0] >= 3:
                uc_.emu_stop()

    uc.hook_add(UC_HOOK_MEM_WRITE, on_write)
    uc.hook_add(UC_HOOK_CODE, on_code)
    sp, pc = struct.unpack_from("<II", flash, APP - FLASH)
    uc.reg_write(UC_ARM_REG_SP, sp)
    try:
        uc.emu_start(pc | 1, 0, count=60_000_000)
    except UcError as e:
        errors.append("emulation error %s at pc 0x%08X" % (e, uc.reg_read(UC_ARM_REG_PC)))

    rd = lambda a, n: bytes(uc.mem_read(a, n))
    w = lambda a: struct.unpack("<I", rd(a, 4))[0]
    checks = [
        ("pc ends in SRAM", state["pc_in_sram"]),
        ("copy of 0x08000000..0x08005FFF", rd(0x20001000, 0x6000) == flash[0:0x6000]),
        ("copy of 0x08068000..0x0807FFFF", rd(0x20007000, 0x18000) == flash[0x68000:0x80000]),
        ("option bytes copy", rd(RESULT + 0x20, 16) == OPT),
        ("magic DUMP", w(RESULT) == 0x504D5544),
        ("crc boot", w(RESULT + 4) == zlib.crc32(flash[0:0x6000])),
        ("crc high", w(RESULT + 8) == zlib.crc32(flash[0x68000:0x80000])),
        ("crc update area", w(RESULT + 12) == zlib.crc32(flash[0x6000:0x68000])),
        ("heartbeat >= 3", w(RESULT + 16) >= 3),
        ("VTOR = 0x20000000", w(0xE000ED08) == 0x20000000),
        ("SRAM vector 0 = 0x20001000", w(0x20000000) == 0x20001000),
        ("SRAM vectors 1..15 equal, odd, in SRAM code",
         len({w(0x20000000 + 4 * i) for i in range(1, 16)}) == 1 and (w(0x20000004) & 1) == 1
         and 0x20000040 <= w(0x20000004) < 0x20000080),
        ("APB2 = init | 4", w(0x40021018) == APB2_INIT | 4),
        ("PH_CFG = init with bits 3:0 = 2", w(0x40010804) == (PH_CFG_INIT & ~0xF) | 2),
    ]
    order = [a for a, v in events if a in (0x40010804, 0x40010810)]
    checks.append(("PBSC 0x100 before PH_CFG write",
                   (0x40010810, 0x100) in events and order and order[0] == 0x40010810))
    checks.append(("no forbidden writes", not errors))
    bad = 0
    for name, ok in checks:
        print("%-46s %s" % (name, "ok" if ok else "FAIL"))
        bad += not ok
    for e in errors[:10]:
        print("  " + e)
    print("%d checks, %d failed" % (len(checks), bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
