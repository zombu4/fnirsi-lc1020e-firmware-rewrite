"""meter_model.py - emulator model of the LC1020E (N32G455) for the bootloader tests.

Used by test_chain.py and test_uf2.py (Unicorn 2.1.4, Cortex-M4 Thumb). Not a test by itself.

Memory map of the model:
  0x08000000..0x080007FF  page 0 (starter), plain memory: any CPU write is a violation
  0x08000800..0x08068FFF  flash with controller semantics (mmio): reads give the flash bytes;
                          a word is programmed only by a 32-bit store while the controller is
                          unlocked and CTRL.PG = 1; a store to a word that is not 0xFFFFFFFF sets
                          PGERR (STS bit 2) and changes nothing; page erase by CTRL.PER + ADD +
                          CTRL.START; every erase and every programmed word is logged with its
                          address ('erase', page) / ('word', address, value)
  0x08069000..0x0807AFFF  slot F / A / B, plain memory (the slots run in place): any CPU write is a
                          violation
  0x0807B000..0x0807FFFF  flash with controller semantics (mmio) like above; the settings page
                          0x0807F000..0x0807FFFF is watched: any erase or program there is a violation
  0x20000000..0x20023FFF  SRAM (144 KiB), plain memory
  0x40000000..0x4002FFFF  peripherals (mmio), a register file with these behaviours:
                          RCC_CTRL 0x40021000 reads bit 17 = bit 16 (HSE ready) and bit 25 = bit 24
                          (PLL ready); RCC_CFG 0x40021004 reads SWS (bits 3:2) = SW (bits 1:0);
                          TIM7 CNT 0x40001424 always reads 0x7FFF, so every delay of fn_08003224
                          (count up to 1000) ends at its first poll; USART1 STS 0x40013800 reads
                          0xC0 (TXE, TC); GPIOC PID 0x40011008: bit 7 = PC7 (key: 1 not pressed,
                          0 pressed), bit 6 = PC6 (1, so the update-mode wait for PC6 ends);
                          GPIOA PBSC 0x40010810 / PBC 0x40010814 bit 8 drive the PA8 latch (logged);
                          flash controller 0x40022000: KEY +4, OPTKEY +8 (any write: violation),
                          STS +0xC, CTRL +0x10 (OPTPG / OPTER / MER: violation), ADD +0x14,
                          OB +0x1C / WRP +0x20 (any write: violation)
  0x60000000.., 0xA0000000  FSMC (display) plain memory
  0xE000E000..0xE000EFFF  SCS (mmio): SysTick CTRL reads COUNTFLAG set; AIRCR 0xE000ED0C write of
                          0x05FA0004 = system reset (logged, run stops); VTOR 0xE000ED08 stored
No UC_HOOK_MEM_READ is used (unicorn 2.1.4 skips an instruction after a call that follows an IT
block when a read hook exists; 2C53T project finding): peripherals and flash are mmio callbacks.
Interrupts are not delivered (SysTick is configured by the slot but never fires).

A code fetch from the application area (mmio, not executable) ends the run with UC_ERR_FETCH_PROT
and PC = the fetched address: that is how "the application was started" is observed.
Power cut: run(cut_after=n) stops right after the n-th flash operation (erase or programmed
word); the flash keeps its state, SRAM is not kept unless keep_ram=True.
"""
import os
import struct
import subprocess
import zlib

from unicorn import (Uc, UcError, UC_ARCH_ARM, UC_MODE_THUMB, UC_MODE_MCLASS, UC_HOOK_CODE,
                     UC_HOOK_MEM_WRITE, UC_ERR_FETCH_PROT)
from unicorn.arm_const import (UC_ARM_REG_PC, UC_ARM_REG_SP, UC_ARM_REG_MSP, UC_ARM_REG_PRIMASK,
                               UC_ARM_REG_LR, UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2,
                               UC_ARM_REG_R3)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
STARTER_ELF = os.path.join(REPO, 'starter', 'build', 'starter.elf')
STARTER_BIN = os.path.join(REPO, 'starter', 'build', 'STARTER.bin')
SLOT_DIR = os.path.join(REPO, 'bootloader', 'build', 'slot')
VENDOR_APP = os.path.join(REPO, 'vendor', 'LC1020E_V1.1_250702.bin')
BIN2UF2 = os.path.join(REPO, 'tools', 'bin2uf2.py')

FLASH, FLASH_SIZE = 0x08000000, 0x80000
APP, APP_END = 0x08006000, 0x08062000
REC0, REC1, REC_END, PAGE = 0x08068000, 0x08068800, 0x08069000, 0x800
SLOTS = (0x08069000, 0x0806F000, 0x08075000)
SLOT_NAMES = ('F', 'A', 'B')
SLOTS_END = 0x0807B000
SETTINGS = 0x0807F000
SRAM, SRAM_SIZE = 0x20000000, 0x24000
FLAG, FLAG_MAGIC = 0x2001FFF0, 0x464C5446
FC = 0x40022000
ST_INSTALL, ST_TRIAL, ST_OK = 1, 2, 3
RET = 0x30000000          # return address of direct calls: a 'b .' outside the meter's map


def nm(elf):
    out = subprocess.run(['arm-none-eabi-nm', elf], capture_output=True, text=True, check=True).stdout
    sym = {}
    for line in out.splitlines():
        p = line.split()
        if len(p) == 3:
            sym.setdefault(p[2], int(p[0], 16))
    return sym


def cell(slot, state, seq, version=1):
    w = struct.pack('<III', 0x4C520000 | slot << 8 | state, version, seq)
    return w + struct.pack('<I', zlib.crc32(w))


def app_stub(sp=0x20010000, reset=APP + 0x101):
    """Application vector page: SP, reset vector, the rest of the 0x200 bytes 'b .' halfwords."""
    return struct.pack('<II', sp, reset) + b'\xfe\xe7' * 0xFC


class Meter:
    def __init__(self, slots=('F', 'A', 'B'), records=(), app=None, starter=True):
        self.flash = bytearray(b'\xff' * FLASH_SIZE)
        self.sym = {}
        if starter:
            s = open(STARTER_BIN, 'rb').read()
            self.flash[0:len(s)] = s
            self.starter_sym = nm(STARTER_ELF)
        for i, name in enumerate(slots):
            if name is None:
                continue
            img = open(os.path.join(SLOT_DIR, 'BOOT_%s.bin' % name), 'rb').read()
            self.put(SLOTS[i], img)
            self.sym[i] = nm(os.path.join(SLOT_DIR, name, 'boot.elf'))
        for addr, data in records:
            self.put(addr, data)
        if app is not None:
            self.put(APP, app)
        self.ram = bytes(SRAM_SIZE)
        self.key_pressed = False
        self.stuck = {}            # word address -> bits that stay 1 when programmed
        self.erase_fail = set()    # page bases whose erase leaves word 0 = 0
        self.uc = None

    def put(self, addr, data):
        self.flash[addr - FLASH:addr - FLASH + len(data)] = data

    def get(self, addr, n):
        return bytes(self.flash[addr - FLASH:addr - FLASH + n])

    def word(self, addr):
        return struct.unpack('<I', self.get(addr, 4))[0]

    def records(self):
        out = []
        for a in range(REC0, REC_END, 16):
            c = self.get(a, 16)
            w0, ver, seq, crc = struct.unpack('<IIII', c)
            if zlib.crc32(c[:12]) == crc and w0 >> 16 == 0x4C52:
                out.append((a, (w0 >> 8) & 0xFF, w0 & 0xFF, seq))
        return out

    # ---- one emulator instance (one start of the chip) ----
    def make(self, keep_ram=False):
        uc = Uc(UC_ARCH_ARM, UC_MODE_THUMB | UC_MODE_MCLASS)
        fl = self.flash
        st = dict(locked=True, keyseq=0, ctrl=0, add=0, sts=0, ops=0, log=[], viol=[], end=None,
                  cut_after=None, regs={}, pa8=None, aircr=False)
        self.st = st
        uc.mem_map(FLASH, PAGE)
        uc.mem_write(FLASH, bytes(fl[0:PAGE]))
        uc.mem_map(SLOTS[0], SLOTS_END - SLOTS[0])
        uc.mem_write(SLOTS[0], bytes(fl[SLOTS[0] - FLASH:SLOTS_END - FLASH]))
        uc.mem_map(SRAM, SRAM_SIZE)
        uc.mem_write(SRAM, self.ram if keep_ram else bytes(SRAM_SIZE))
        uc.mem_map(0x60000000, 0x40000)
        uc.mem_map(0xA0000000, 0x1000)
        uc.mem_map(RET, 0x1000)
        uc.mem_write(RET, b'\xfe\xe7' * 8)

        def stop(reason):
            if st['end'] is None:
                st['end'] = reason
            uc.emu_stop()

        def viol(text):
            st['viol'].append(text)
            stop('violation')

        def op_done(entry):
            st['log'].append(entry)
            st['ops'] += 1
            st['sts'] |= 0x20                      # EOP
            if st['cut_after'] is not None and st['ops'] >= st['cut_after']:
                stop('cut')

        def fl_read(base):
            def rd(uc_, off, size, user):
                o = base - FLASH + off
                return int.from_bytes(fl[o:o + size], 'little')
            return rd

        def fl_write(base):
            def wr(uc_, off, size, value, user):
                a = base + off
                if size != 4 or a % 4:
                    viol('non-word store %d bytes to flash 0x%08X' % (size, a))
                    return
                if st['locked'] or not st['ctrl'] & 1:
                    viol('store to flash 0x%08X without unlock / PG' % a)
                    return
                if a >= SETTINGS:
                    viol('program in the settings page 0x%08X' % a)
                    return
                o = a - FLASH
                old = int.from_bytes(fl[o:o + 4], 'little')
                if old != 0xFFFFFFFF:
                    st['sts'] |= 4                 # PGERR, word unchanged
                    st['log'].append(('pgerr', a, value))
                    return
                new = value | self.stuck.get(a, 0)
                fl[o:o + 4] = struct.pack('<I', new)
                op_done(('word', a, value))
            return wr

        for lo, hi in ((FLASH + PAGE, SLOTS[0]), (SLOTS_END, FLASH + FLASH_SIZE)):
            uc.mmio_map(lo, hi - lo, fl_read(lo), None, fl_write(lo), None)

        def code_write(uc_, access, addr, size, value, user):
            viol('CPU store to code flash 0x%08X' % addr)
        uc.hook_add(UC_HOOK_MEM_WRITE, code_write, begin=FLASH, end=FLASH + PAGE - 1)
        uc.hook_add(UC_HOOK_MEM_WRITE, code_write, begin=SLOTS[0], end=SLOTS_END - 1)

        regs = st['regs']

        def p_read(uc_, off, size, user):
            a = 0x40000000 + off
            if FC <= a < FC + 0x400:
                r = a - FC
                if r == 0x0C:
                    return st['sts']
                if r == 0x10:
                    return st['ctrl'] | (0x80 if st['locked'] else 0)
                if r == 0x14:
                    return st['add']
                return regs.get(a, 0)
            v = regs.get(a & ~3, 0)
            if a == 0x40021000:
                v |= ((v >> 16) & 1) << 17 | ((v >> 24) & 1) << 25
            elif a == 0x40021004:
                v = (v & ~0xC) | ((v & 3) << 2)
            elif a == 0x40001424:
                v = 0x7FFF
            elif a == 0x40013800:
                v = 0xC0
            elif a == 0x40011008:
                v = (0 if self.key_pressed else 0x80) | 0x40
            if a & 3:
                v >>= 8 * (a & 3)
            return v & ((1 << (8 * size)) - 1)

        def p_write(uc_, off, size, value, user):
            a = 0x40000000 + off
            if FC <= a < FC + 0x400:
                r = a - FC
                if r == 0x04:
                    if not st['locked']:
                        st['log'].append(('key-while-unlocked', value))
                    if st['keyseq'] == 0 and value == 0x45670123:
                        st['keyseq'] = 1
                    elif st['keyseq'] == 1 and value == 0xCDEF89AB:
                        st['locked'] = False
                        st['keyseq'] = 0
                    else:
                        st['keyseq'] = 0
                elif r in (0x08, 0x1C, 0x20):
                    viol('flash controller register +0x%X written (0x%08X)' % (r, value))
                elif r == 0x0C:
                    st['sts'] &= ~value
                elif r == 0x14:
                    st['add'] = value
                elif r == 0x10:
                    if value & 0x34:
                        viol('CTRL option / mass erase bit: 0x%X' % value)
                        return
                    if value & 0x80:
                        st['locked'] = True
                    if st['locked'] and value & 0x43 and not value & 0x80:
                        viol('CTRL PG/PER/START while locked: 0x%X' % value)
                        return
                    if value & 0x40 and value & 0x02 and not st['locked']:
                        pg = st['add'] & ~(PAGE - 1)
                        if not FLASH <= pg < FLASH + FLASH_SIZE:
                            viol('erase outside flash 0x%08X' % pg)
                            return
                        if pg < FLASH + PAGE or SLOTS[0] <= pg < SLOTS_END:
                            viol('erase of code flash 0x%08X' % pg)
                            return
                        if pg >= SETTINGS:
                            viol('erase of the settings page 0x%08X' % pg)
                            return
                        fl[pg - FLASH:pg - FLASH + PAGE] = b'\xff' * PAGE
                        if pg in self.erase_fail:
                            fl[pg - FLASH:pg - FLASH + 4] = bytes(4)
                        op_done(('erase', pg))
                    st['ctrl'] = value & 0x3F & ~0x40
                else:
                    regs[a] = value
                return
            if a == 0x40010810 and value & 0x100:
                st['pa8'] = 1
                st['log'].append(('pa8', 1))
            if a == 0x40010814 and value & 0x100:
                st['pa8'] = 0
                st['log'].append(('pa8', 0))
            if a == 0x40010810 and value & 0x1000000:
                st['pa8'] = 0
                st['log'].append(('pa8', 0))
            if size == 4:
                regs[a] = value
            else:
                b = a & ~3
                sh = 8 * (a & 3)
                m = ((1 << (8 * size)) - 1) << sh
                regs[b] = (regs.get(b, 0) & ~m) | ((value << sh) & m)

        uc.mmio_map(0x40000000, 0x30000, p_read, None, p_write, None)

        def bb_read(uc_, off, size, user):
            reg = 0x40000000 + (off // 32 & ~3)
            bit = (off // 4) % 32
            return (p_read(uc_, reg - 0x40000000, 4, None) >> bit) & 1

        def bb_write(uc_, off, size, value, user):
            reg = 0x40000000 + (off // 32 & ~3)
            bit = (off // 4) % 32
            v = p_read(uc_, reg - 0x40000000, 4, None)
            v = (v | 1 << bit) if value & 1 else (v & ~(1 << bit))
            p_write(uc_, reg - 0x40000000, 4, v, None)

        uc.mmio_map(0x42000000, 0x30000 * 32, bb_read, None, bb_write, None)   # peripheral bit-band

        scs = {}

        def s_read(uc_, off, size, user):
            a = 0xE000E000 + off
            v = scs.get(a & ~3, 0)
            if a == 0xE000E010:
                v |= 1 << 16
            if a & 3:
                v >>= 8 * (a & 3)
            return v & ((1 << (8 * size)) - 1)

        def s_write(uc_, off, size, value, user):
            a = 0xE000E000 + off
            if a == 0xE000ED0C and value == 0x05FA0004:
                st['log'].append(('reset',))
                stop('reset')
            if size == 4:
                scs[a] = value
            else:
                b = a & ~3
                sh = 8 * (a & 3)
                m = ((1 << (8 * size)) - 1) << sh
                scs[b] = (scs.get(b, 0) & ~m) | ((value << sh) & m)
        uc.mmio_map(0xE000E000, 0x1000, s_read, None, s_write, None)
        self.scs = scs

        def at_ret(uc_, addr, size, user):
            stop('return')
        uc.hook_add(UC_HOOK_CODE, at_ret, begin=RET, end=RET + 1)
        self.uc = uc
        return uc

    def watch(self, addr, name, stop=False):
        """Log ('at', name) whenever the instruction at addr runs; stop the run there if stop."""
        st = self.st

        def hit(uc_, a, size, user):
            st['log'].append(('at', name))
            if stop:
                if st['end'] is None:
                    st['end'] = 'at ' + name
                uc_.emu_stop()
        self.uc.hook_add(UC_HOOK_CODE, hit, begin=addr & ~1, end=addr & ~1)

    def go(self, pc, sp=None, count=60_000_000):
        uc, st = self.uc, self.st
        if sp is not None:
            uc.reg_write(UC_ARM_REG_SP, sp)
        try:
            uc.emu_start(pc | 1, 0, count=count)
        except UcError as e:
            p = uc.reg_read(UC_ARM_REG_PC)
            if e.errno == UC_ERR_FETCH_PROT and APP <= p < APP_END and st['end'] is None:
                st['end'] = 'app'
                st['app_pc'] = p
            elif st['end'] is None:
                st['end'] = 'emu error %s at 0x%08X' % (e, p)
        if st['end'] is None:
            st['end'] = 'timeout'
        st['vtor'] = self.scs.get(0xE000ED08, 0)
        st['primask'] = uc.reg_read(UC_ARM_REG_PRIMASK)
        st['msp'] = uc.reg_read(UC_ARM_REG_MSP)
        self.ram = bytes(uc.mem_read(SRAM, SRAM_SIZE))
        return st['end']

    def call(self, addr, *args, count=200_000_000):
        """Direct call of a function of the running image; returns r0 (None when it did not return)."""
        uc, st = self.uc, self.st
        regs = (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3)
        for r, v in zip(regs, args):
            uc.reg_write(r, v & 0xFFFFFFFF)
        uc.reg_write(UC_ARM_REG_LR, RET | 1)
        st['end'] = None
        try:
            uc.emu_start(addr | 1, 0, count=count)
        except UcError as e:
            st['end'] = 'emu error %s at 0x%08X' % (e, uc.reg_read(UC_ARM_REG_PC))
        if st['end'] != 'return':
            return None
        return uc.reg_read(UC_ARM_REG_R0)

    def boot(self, cut_after=None, keep_ram=False, stops=(), count=60_000_000):
        """One start from the starter's reset vector. stops: extra (slot, symbol) stop points."""
        self.make(keep_ram=keep_ram)
        self.st['cut_after'] = cut_after
        for i, sym in self.sym.items():
            self.watch(sym['reset_handler'], 'slot%d reset' % i)
            self.watch(sym['slot_app_start'], 'slot%d app_start' % i)
            self.watch(sym['slot_confirm'], 'slot%d confirm' % i)
            self.watch(sym['uf2_init'], 'slot%d uf2_init' % i)
            self.watch(sym['fn_08002c10'], 'slot%d usb_start' % i)
            self.watch(sym['fn_08001150'], 'slot%d update_loop' % i, stop=True)
            self.watch(sym['rec_append'], 'slot%d rec_append' % i)
        if hasattr(self, 'starter_sym'):
            self.watch(self.starter_sym['dead_end'], 'starter dead_end', stop=True)
        for i, s in stops:
            self.watch(self.sym[i][s], 'slot%d %s' % (i, s), stop=True)
        sp, pc = struct.unpack_from('<II', self.flash, 0)
        return self.go(pc, sp=sp, count=count)

    def events(self):
        return [x[1] for x in self.st['log'] if x[0] == 'at']

    def flash_ops(self):
        return [x for x in self.st['log'] if x[0] in ('word', 'erase')]
