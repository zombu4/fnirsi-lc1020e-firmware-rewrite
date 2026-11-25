"""meter_model.py - emulator model of the LC1020E (N32G455) for the bootloader and application tests.

Used by test_chain.py, test_uf2.py and the tests of our application build (Unicorn 2.1.4,
Cortex-M4 Thumb). Not a test by itself.

Two flash modes (Meter(flash_mode=...)); 'boot' is the default and is the model the bootloader tests
were written against, unchanged:

flash_mode 'boot' - memory map:
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

flash_mode 'app' (our application build):
  page 0, the application area 0x08006000..0x08061FFF and every slot that is not the BOOT target are
  plain memory (they execute; any CPU write is a violation). Everything else is flash with
  controller semantics (mmio), and who may erase / program what depends on the code that does it
  (the PC of the store, exact in unicorn's mmio callbacks):
    - code in the application area: exactly the four settings pages 0x08066000, 0x08066800,
      0x0807F000, 0x0807F800, the eight pages of the own calibration area 0x08062000..0x08065FFF
      and, only when the test names one (Meter(boot_target='A' or 'B')),
      that slot's twelve pages and the record pages 0x08068000 / 0x08068800;
    - code in page 0 or a slot (starter, slot bootloader): the record pages only (in this mode the
      application area is not writable, so the UF2 path is tested in mode 'boot');
    - code anywhere else (SRAM): every flash operation is a violation.
  Strict hardware rules of this mode (N32G45x user manual 3.2.5.2.5): CTRL.SMPSEL = 1 (SMP2) at a
  word program of the application, any of the interrupt enables ECERRITE / EOPITE / FERRITE /
  ERRITE, OPTWE, PG with PER, START without PER, or a reserved CTRL bit: violation (not modelled,
  none is written); a wrong KEY sequence leaves the controller locked until the next reset
  ("After an unsuccessful unlocking operation, this bit cannot be changed until the next system
  reset"; mode 'boot' keeps its retry); a word program from the application area must be followed
  by five NOP instructions (manual 3.2.1.4.2, read as "after every programmed word", as save.s
  flash_word does).

Both modes:
  Power cut: run(cut_after=n) stops right after the n-th flash operation (erase or programmed
  word); the flash keeps its state, SRAM is not kept unless keep_ram=True. With Meter.cut_pattern
  set, the n-th operation is instead cut in the middle and stops the run ('cut'): the datasheet
  and the manual do not say what an interrupted erase or program leaves, so the test chooses the
  worst cases: erase 'unchanged' (the old bytes), 'ff' (all 0xFF), 'mixed' (even words 0xFF, odd
  words old), 'first_half' / 'second_half' (that half 0xFF, the other half old), or a function
  f(old_bytes) -> new_bytes; word program 'unchanged' / 'ff' (the word stays 0xFFFFFFFF),
  'mixed' (only the upper halfword's zero bits programmed), or f(old, new) -> word. Logged as
  ('erase-cut', page, pattern) / ('word-cut', address, value, pattern).
  0x00000000..0x0007FFFF  Boot alias: main flash as mapped above, at address - 0x08000000 (manual
                          3.1.3 "Boot from Main Flash: Main flash memory is mapped to the boot space
                          (0x0000_0000) ... accessible in two address areas, 0x0000_0000 or
                          0x0800_0000"; the meter boots from main flash: the starter runs at power-on).
                          Reads and fetches as at 0x08xxxxxx;
                          any CPU store through the alias is a violation (the manual does not say
                          what such a store does). The run's stop address is NO_UNTIL (odd), so a
                          branch to 0x00000000 executes there as on the meter.
  0x20000000..0x20023FFF  SRAM (144 KiB), plain memory
  0x40000000..0x4002FFFF  peripherals (mmio), a register file with these behaviours:
                          RCC_CTRL 0x40021000 reads bit 17 = bit 16 (HSE ready) and bit 25 = bit 24
                          (PLL ready); RCC_CFG 0x40021004 reads SWS (bits 3:2) = SW (bits 1:0);
                          opt-in RCC rules (Meter attributes, defaults keep the lines above;
                          revision 17): pll_locks False: bit 25 never
                          reads 1; pll_lock_reads n > 0: after a write that sets PLLEN (bit 24,
                          0 -> 1), bit 25 reads 0 for the next n reads of RCC_CTRL, then as above
                          (SWS is not affected by it); sws_stuck 0..3: SWS reads that value; rcc_switch_reads n > 0:
                          after a write that changes SW, SWS keeps the old source for n reads of
                          RCC_CFG, and a switch to the PLL happens only while bit 25 reads 1
                          (manual 6.2.7); rcc_strict: a write to RCC_CTRL that clears PLLEN (bit 24)
                          or HSEEN (bit 16) while SWS reads PLL (manual 6.3.2: "cannot be cleared"),
                          or a write to RCC_CFG that changes its PLL bits 27, 21:16 while PLLEN is 1
                          (6.2.4, "can only be written when the PLL is disabled"), is a violation
                          (these rules apply only while no attached device takes RCC_CTRL);
                          TIM7 CNT 0x40001424 always reads 0x7FFF, so every delay of fn_08003224
                          (count up to 1000) ends at its first poll; USART1 STS 0x40013800 reads
                          0xC0 (TXE, TC); GPIOC PID 0x40011008: bit 7 = PC7 (key: 1 not pressed,
                          0 pressed), bit 6 = PC6 (1, so the update-mode wait for PC6 ends);
                          GPIOA PBSC 0x40010810 / PBC 0x40010814 bit 8 drive the PA8 latch (logged);
                          GPIOA..G (0x40010800 + 0x400 n) POD +0x0C: the output data, reset values
                          0xA000 (A), 0x0010 (B), 0 (manual 7.3.5), written directly or through PBSC
                          +0x10 (bits 15:0 set, 31:16 clear, set wins, 7.3.6) and PBC +0x14 (bits
                          15:0 clear, 7.3.7); Meter.gpio_out(port base) reads it (PBSC / PBC read
                          back as written, not modelled further);
                          flash controller 0x40022000: KEY +4, OPTKEY +8 (any write: violation),
                          STS +0xC, CTRL +0x10 (OPTPG / OPTER / MER: violation), ADD +0x14,
                          OB +0x1C / WRP +0x20 (any write: violation); attached device models
                          (Meter.attach, e.g. tests/usb_host.py UsbDevice) take their addresses
                          before this register file
  0x60000000.., 0xA0000000  FSMC (display) plain memory
  0xE000E000..0xE000EFFF  SCS (mmio): SysTick CTRL reads COUNTFLAG set; AIRCR 0xE000ED0C write with
                          key 0x05FA and SYSRESETREQ = system reset (logged, run stops); VTOR 0xE000ED08 stored
No UC_HOOK_MEM_READ is used (unicorn 2.1.4 skips an instruction after a call that follows an IT
block when a read hook exists; 2C53T project finding): peripherals and flash are mmio callbacks.
Without timing (the default) interrupts are not delivered (SysTick is configured by the slot but
never fires) and the IWDG registers are plain words.

A code fetch from the application area while it is mmio (mode 'boot') ends the run with
UC_ERR_FETCH_PROT and PC = the fetched address: that is how "the application was started" is
observed.

Timing (Meter.set_timing(lsi_hz=...), before make / boot; off by default, so the bootloader tests
run exactly as before):
  Time base. Emulated time = instructions executed x cycles per instruction / core clock, plus the
  datasheet's maximum duration of every flash operation (N32G455 datasheet table 4-21: 32-bit
  program 225 us, page erase 100 ms). Core clock 144 MHz (the application's SysTick reload word
  144000000 / 100 at 0x200002B0 and the PLL 144 MHz). Instructions are
  counted exactly: a UC_HOOK_BLOCK hook decodes the Thumb instruction lengths of every translated
  block (a halfword whose top five bits are 0b11101, 0b11110 or 0b11111 starts a 32-bit
  instruction) and the count is corrected to the PC wherever a run stops inside a block (the hook
  is C, tests/blockcount.c, built with cc on first use; "native block hook" below). Cycles per
  instruction: default 5 (the manual gives no instruction timing; FLASH_AC LATENCY must be 4 at
  128..144 MHz, manual 3.2.5.2.1, so one flash access takes 1 + 4 cycles; counting every
  instruction as one such access is the strict choice for the watchdog claims: emulated time runs
  slower than an ideal 1-cycle core). Waits on TIM7 (always 0x7FFF) take no emulated time; the
  application feeds the IWDG after every one of them (fn_08011c68 -> fn_08009390).
  Interrupts. A model NVIC: ISER / ICER / ISPR / ICPR / IABR, IPR (4 priority bits, manual "16
  programmable priority levels (4-bit interrupt priority level is used)"), SHPR, ICSR (PENDSV /
  PENDST set and clear, VECTACTIVE, VECTPENDING), AIRCR PRIGROUP, STIR; SysTick (CSR / RVR / CVR
  / CALIB 18000, manual 2.1.1) counting the core clock in emulated time, exception 15 at every 1 to
  0 transition while TICKINT is set. Device models assert IRQ lines (level: pending while asserted
  and not active, as the Cortex-M4 does for level-sensitive interrupts). The run is cut into slices
  (set_timing(slice_insns=...)) that end at every timed event (SysTick transition, IWDG expiry,
  device events such as the USB frame start) and at the next block after a write that can change
  the interrupt state (NVIC, SysTick, a device register): the pending exception with the best
  priority that beats the execution priority (PRIMASK, BASEPRI, the active exceptions) is entered
  there: the 8-word frame (26 words when CONTROL.FPCA is set: S0..S15, FPSCR, the reserved word;
  written at once, the same stack room as lazy stacking) on MSP with 8-byte alignment (xPSR bit
  9), LR = EXC_RETURN, PC = vector (VTOR, 0 aliased to 0x08000000). Unicorn runs an IT block as one
  step, so no slice ends inside one. The handler's return to EXC_RETURN (unicorn stops with
  UC_ERR_EXCEPTION at 0xFFFFFFF8 / 0xFFFFFFE8) is unstacked by the model; SP must then equal the
  frame address. Unicorn itself stays in thread mode (IPSR reads 0 in a handler). Clearing PRIMASK
  (cpsie) is seen at the end of the slice (at most slice_insns instructions later). A thread on
  PSP, an NMI, SysTick CLKSOURCE 0: the run stops with reason 'model ...' (not modelled).
  IWDG (manual 16): KEY 0x40003000 (0x5555 unlocks PREDIV / RELV, any other key value locks them
  again, 0xAAAA reloads, 0xCCCC starts), PREDIV +4 (/4 .. /256), RELV +8, STS +0xC (PVU bit 0,
  CRVU bit 1). The counter counts down from the start at LSI (set_timing(lsi_hz): 30000..60000,
  datasheet fLSI min 30 / typ 40 / max 60 kHz) / prescaler; RL + 1 ticks after the last load
  (Table 16-1: RL 0 gives one tick) the chip resets: the run ends with reason 'iwdg', RCC_CTRLSTS
  IWDGRSTF (bit 29) is set for the next start, and the IWDG is stopped at the next start (a system
  reset sets every register to its reset value, manual 6.1.2) unless
  set_timing(iwdg_survives_reset=True) (then it keeps running: after an AIRCR reset from where it
  stood, after its own reset from RL). Meter.starts() restarts the chip after 'iwdg' / 'reset'
  ends as the hardware does (a hook may look at each end first).
  Strict choices where the manual is silent or contradicts itself: 0xAAAA on a stopped IWDG starts
  it (16.4.1 says so, the key table says 0xCCCC; set_timing(aaaa_starts=False) for the other
  reading); 0xCCCC starts from the counter as it stands (0xFFF after reset, RL after a 0xAAAA of a
  stopped IWDG with aaaa_starts False), never longer than the manual's 0xFFF; a PREDIV / RELV write
  takes effect iwdg_sync_lsi (default 5) LSI periods later (PVU / CRVU set until then; the manual
  gives no duration), a second write while the bit is set is ignored (16.5.3 / 16.5.4), a reload
  while CRVU is set loads the smaller of the old and the new RL; a write to PREDIV / RELV without
  0x5555 is ignored and logged; a reserved bit written 1, a write to STS or a byte access:
  violation. Meter.iwdg_stretch() gives the longest stretch between two counter loads (start or
  reload; a stretch that ended in the IWDG reset counts too), in seconds and instructions, with
  the PCs of both ends; Meter.iwdg_log lists every load, reset and stop.
  RCC_CTRLSTS 0x40021024: power-on value 0x0C000003 (manual 6.3.11), reset flags kept across
  starts (IWDGRSTF after 'iwdg', SFTRSTF after 'reset'), RMRSTF (bit 24) clears them, LSIRD reads
  LSIEN or a running IWDG (manual: the IWDG forces the LSI on).
  A flash operation that the IWDG reset interrupts (the counter expires within its duration) is
  cut as above (Meter.cut_pattern, 'mixed' when none is set) and the run ends 'iwdg'.
"""
import ctypes
import hashlib
import math
import os
import platform
import struct
import subprocess
import tempfile
import weakref
import zlib

from unicorn import (Uc, UcError, UC_ARCH_ARM, UC_MODE_THUMB, UC_MODE_MCLASS, UC_HOOK_CODE,
                     UC_HOOK_MEM_WRITE, UC_HOOK_BLOCK, UC_ERR_FETCH_PROT, UC_ERR_EXCEPTION)
from unicorn.unicorn_py3.unicorn import uclib as _uclib, uc_hook_h as _uc_hook_h
from unicorn import arm_const
from unicorn.arm_const import (UC_ARM_REG_PC, UC_ARM_REG_SP, UC_ARM_REG_MSP, UC_ARM_REG_PRIMASK,
                               UC_ARM_REG_LR, UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2,
                               UC_ARM_REG_R3, UC_ARM_REG_R12, UC_ARM_REG_XPSR, UC_ARM_REG_CONTROL,
                               UC_ARM_REG_BASEPRI, UC_ARM_REG_FPSCR)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
STARTER_ELF = os.path.join(REPO, 'starter', 'build', 'starter.elf')
STARTER_BIN = os.path.join(REPO, 'starter', 'build', 'STARTER.bin')
SLOT_DIR = os.path.join(REPO, 'bootloader', 'build', 'slot')
VENDOR_APP = os.path.join(REPO, 'vendor', 'LC1020E_V1.1_250702.bin')
BIN2UF2 = os.path.join(REPO, 'tools', 'bin2uf2.py')
# our application build (`make own` in firmware/): the image and its ELF the tests load
OWN_BIN = os.path.join(REPO, 'firmware', 'build', 'own', 'APP_OWN.bin')
OWN_ELF = os.path.join(REPO, 'firmware', 'build', 'own', 'app_own.elf')

FLASH, FLASH_SIZE = 0x08000000, 0x80000
APP, APP_END = 0x08006000, 0x08062000
REC0, REC1, REC_END, PAGE = 0x08068000, 0x08068800, 0x08069000, 0x800
SLOTS = (0x08069000, 0x0806F000, 0x08075000)
SLOT_NAMES = ('F', 'A', 'B')
SLOT_SIZE = 0x6000
SLOTS_END = 0x0807B000
SETTINGS = 0x0807F000
SET_A, SET_B = 0x0807F000, 0x08066000
SETTINGS_PAGES = (0x08066000, 0x08066800, 0x0807F000, 0x0807F800)
OCAL_PAGES = tuple(range(0x08062000, 0x08066000, 0x800))   # own calibration area
SRAM, SRAM_SIZE = 0x20000000, 0x24000
FLAG, FLAG_MAGIC = 0x2001FFF0, 0x464C5446
FC = 0x40022000
ST_INSTALL, ST_TRIAL, ST_OK = 1, 2, 3
RET = 0x30000000          # return address of direct calls: a 'b .' outside the meter's map
# emu_start's stop address: odd, so no Thumb PC ever equals it (with 0, a branch to the boot alias
# address 0x00000000 stopped the run with UC_ERR_EXCEPTION although the meter executes there)
NO_UNTIL = 0xFFFFFFFF

# timing model
CORE_HZ = 144_000_000
CPI_DEFAULT = 5
T_PROG, T_ERASE = 225e-6, 100e-3          # datasheet table 4-21, maxima
LSI_MIN, LSI_MAX = 30000, 60000           # datasheet fLSI
IWDG = 0x40003000
RCC_CTRLSTS = 0x40021024
CTRLSTS_POR = 0x0C000003                  # manual 6.3.11 reset value
IWDGRSTF, SFTRSTF, RMRSTF = 1 << 29, 1 << 28, 1 << 24
RST_FLAGS = 0xFEB80000                    # bits 31..25, 23, 21..19
EXC_SYSTICK, EXC_PENDSV = 15, 14
GPIO_A, GPIO_END = 0x40010800, 0x40012400   # GPIOA..GPIOG, 0x400 each (manual memory map)
GPIO_POD_RESET = {0: 0xA000, 1: 0x0010}       # manual 7.3.5
S_REGS = [getattr(arm_const, 'UC_ARM_REG_S%d' % i) for i in range(16)]


# ---- native block hook (tests/blockcount.c) ----
# The instruction counter of the time base (module docstring, "Instructions are counted exactly")
# runs as a C hook: blockcount.c is the Python block hook it replaced, rule for rule, so no Python
# runs per executed block. Built once per source text and machine with the C compiler ($CC, else cc)
# into the temporary directory and loaded with ctypes; the unicorn functions it calls are passed as
# pointers of the library the unicorn binding loaded. Its state is live only inside the emu_start of
# a slice (Meter._run); between slices Meter.tm holds 'icount', 'blk' and 'stop_req' as before.
BC_SRC = os.path.join(HERE, 'blockcount.c')


class BcState(ctypes.Structure):
    """The head of blockcount.c's bc_state (same field order)."""
    _fields_ = [('icount', ctypes.c_int64), ('stop_req', ctypes.c_int32), ('blk_valid', ctypes.c_int32),
                ('blk_addr', ctypes.c_uint64), ('blk_size', ctypes.c_uint64), ('blk_base', ctypes.c_int64),
                ('blk', ctypes.c_void_p), ('blocks', ctypes.c_uint64), ('mem_read', ctypes.c_void_p),
                ('emu_stop', ctypes.c_void_p), ('reg_read', ctypes.c_void_p)]


_BC = []


def _bc_lib():
    if _BC:
        return _BC[0]
    if UC_ARM_REG_PC != 11:
        raise RuntimeError('blockcount.c reads register 11 as the PC; this unicorn has UC_ARM_REG_PC %d'
                           % UC_ARM_REG_PC)
    src = open(BC_SRC, 'rb').read()
    tag = hashlib.sha256(src + platform.machine().encode() + platform.system().encode()).hexdigest()[:16]
    d = os.path.join(tempfile.gettempdir(), 'meter_model_native')
    os.makedirs(d, exist_ok=True)
    so = os.path.join(d, 'blockcount-%s.so' % tag)
    if not os.path.exists(so):
        tmp = '%s.%d.tmp' % (so, os.getpid())
        r = subprocess.run([os.environ.get('CC', 'cc'), '-O2', '-shared', '-fPIC', '-o', tmp, BC_SRC],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError('building %s failed:\n%s%s' % (BC_SRC, r.stdout, r.stderr))
        os.replace(tmp, so)          # atomic: parallel test processes may build it at the same time
    lib = ctypes.CDLL(so)
    lib.bc_new.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    lib.bc_new.restype = ctypes.POINTER(BcState)
    lib.bc_free.argtypes = [ctypes.c_void_p]
    lib.bc_free.restype = None
    lib.bc_icount_at.argtypes = [ctypes.c_void_p, ctypes.c_uint64]
    lib.bc_icount_at.restype = ctypes.c_int64
    lib.bc_icount_pc.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    lib.bc_icount_pc.restype = ctypes.c_int64
    _BC.append(lib)
    return lib


_RBUF, _WBUF = ctypes.c_uint64(), ctypes.c_uint64()
_RREF, _WREF = ctypes.byref(_RBUF), ctypes.byref(_WBUF)


def _rr(uch, reg):
    """Uc.reg_read(reg) for a core register (not a coprocessor or Q register): the binding's own call,
    uc_reg_read into a zeroed 64-bit word, without its per-call register class selection."""
    _RBUF.value = 0
    err = _uclib.uc_reg_read(uch, reg, _RREF)
    if err:
        raise UcError(err, reg)
    return _RBUF.value


def _rw(uch, reg, value):
    """Uc.reg_write(reg, value) for a core register: uc_reg_write of the value as a 64-bit word, as
    the binding passes it."""
    _WBUF.value = value
    err = _uclib.uc_reg_write(uch, reg, _WREF)
    if err:
        raise UcError(err, reg)


class _Tm(dict):
    """Meter.tm. While a slice runs (live), a write of 'stop_req' (Meter.irq_check, a test's hook)
    also reaches the native hook, which takes it at the next block."""
    __slots__ = ('bc', 'live')

    def __setitem__(self, k, v):
        dict.__setitem__(self, k, v)
        if k == 'stop_req' and self.live:
            self.bc.stop_req = 1 if v else 0


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


def own_image(bin_path=OWN_BIN, elf_path=OWN_ELF):
    """Our application build: (image bytes for 0x08006000, symbols of its ELF)."""
    for p in (bin_path, elf_path):
        if not os.path.exists(p):
            raise FileNotFoundError('own build missing: %s (make own in firmware/)' % p)
    return open(bin_path, 'rb').read(), nm(elf_path)


def thumb_offsets(code):
    """Offsets of the instructions in a block of Thumb code (16- and 32-bit encodings)."""
    offs, i = [], 0
    while i + 1 < len(code):
        offs.append(i)
        hw = code[i] | code[i + 1] << 8
        i += 4 if hw >> 11 in (0x1D, 0x1E, 0x1F) else 2
    return offs


def _nop_len(code, i):
    """Length of a NOP at code[i] (0xBF00, or NOP.W 0xF3AF 0x8000), 0 when there is none."""
    if code[i:i + 2] == b'\x00\xbf':
        return 2
    if code[i:i + 4] == b'\xaf\xf3\x00\x80':
        return 4
    return 0


ERASE_CUTS = {
    'unchanged': lambda old: bytes(old),
    'ff': lambda old: b'\xff' * len(old),
    'mixed': lambda old: b''.join(b'\xff' * 4 if (k // 4) % 2 == 0 else bytes(old[k:k + 4])
                                  for k in range(0, len(old), 4)),
    'first_half': lambda old: b'\xff' * (len(old) // 2) + bytes(old[len(old) // 2:]),
    'second_half': lambda old: bytes(old[:len(old) // 2]) + b'\xff' * (len(old) - len(old) // 2),
}
WORD_CUTS = {
    'unchanged': lambda old, new: old,
    'ff': lambda old, new: old,
    'mixed': lambda old, new: old & (new | 0x0000FFFF),
}


class Meter:
    def __init__(self, slots=('F', 'A', 'B'), records=(), app=None, starter=True, flash_mode='boot',
                 boot_target=None):
        if flash_mode not in ('boot', 'app'):
            raise ValueError('flash_mode %r' % flash_mode)
        if boot_target not in (None, 'A', 'B') or (boot_target and flash_mode != 'app'):
            raise ValueError('boot_target %r (slot A or B, mode app only)' % boot_target)
        self.flash_mode = flash_mode
        self.boot_target = boot_target
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
        self.app_sym = {}
        self.ram = bytes(SRAM_SIZE)
        self.key_pressed = False
        self.stuck = {}            # word address -> bits that stay 1 when programmed
        self.erase_fail = set()    # page bases whose erase leaves word 0 = 0
        self.cut_pattern = None    # how the cut_after-th operation is left (module docstring)
        self.pll_locks = True      # opt-in RCC rules (module docstring, RCC_CTRL / RCC_CFG)
        self.sws_stuck = None
        self.rcc_switch_reads = 0
        self.rcc_strict = False
        self.pll_lock_reads = 0    # 0: PLLRDF follows PLLEN at once (the rule before revision 17)
        self.devices = []          # attached peripheral models (attach())
        self.timing = None
        self.uc = None
        self.tm = None
        pages = set(SETTINGS_PAGES) | set(OCAL_PAGES)
        if boot_target:
            s = SLOTS[SLOT_NAMES.index(boot_target)]
            pages |= set(range(s, s + SLOT_SIZE, PAGE)) | {REC0, REC1}
        self.app_pages = frozenset(pages)

    def put(self, addr, data):
        self.flash[addr - FLASH:addr - FLASH + len(data)] = data

    def get(self, addr, n):
        return bytes(self.flash[addr - FLASH:addr - FLASH + n])

    def word(self, addr):
        return struct.unpack('<I', self.get(addr, 4))[0]

    def load_own(self, bin_path=OWN_BIN, elf_path=OWN_ELF):
        """Put our application build at 0x08006000; its symbols in self.app_sym. Returns the image."""
        img, self.app_sym = own_image(bin_path, elf_path)
        if len(img) > APP_END - APP:
            raise ValueError('own image %d bytes, more than the application area' % len(img))
        self.put(APP, img)
        return img

    def records(self):
        out = []
        for a in range(REC0, REC_END, 16):
            c = self.get(a, 16)
            w0, ver, seq, crc = struct.unpack('<IIII', c)
            if zlib.crc32(c[:12]) == crc and w0 >> 16 == 0x4C52:
                out.append((a, (w0 >> 8) & 0xFF, w0 & 0xFF, seq))
        return out

    def gpio_out(self, port):
        """The output data word POD of a GPIO port (base address) as the code has written it."""
        return self.st['pod'][port]

    def attach(self, dev):
        """Attach a peripheral model: dev.ranges [(lo, hi)), dev.read(m, a, size) -> value,
        dev.write(m, a, size, value); optional dev.reset(m) (at every start, after the chip model is
        made), dev.irqs(m) (asserted IRQ numbers), dev.next_event(m, now) (emulated time of its next
        event or None), dev.tick(m, now) (called at every slice end)."""
        self.devices.append(dev)
        return dev

    def set_timing(self, lsi_hz, core_hz=CORE_HZ, cpi=CPI_DEFAULT, slice_insns=1000, iwdg_sync_lsi=5,
                   aaaa_starts=True, iwdg_survives_reset=False):
        """Switch on the time base, interrupts, SysTick, IWDG and RCC_CTRLSTS (module docstring).
        Call before make() / boot(); the emulated clock starts at 0 (power-on)."""
        if not LSI_MIN <= lsi_hz <= LSI_MAX:
            raise ValueError('LSI %r Hz outside the datasheet range 30..60 kHz' % lsi_hz)
        self.timing = dict(lsi=float(lsi_hz), core=float(core_hz), cpi=float(cpi), slice=int(slice_insns),
                           sync=float(iwdg_sync_lsi), aaaa_starts=aaaa_starts, survives=iwdg_survives_reset)
        self.clock = 0.0           # emulated seconds at the start of the current start
        self.icount_total = 0      # instructions of all finished starts
        self.ctrlsts = CTRLSTS_POR
        self.iwdg_carry = None
        self.iwdg_log = []
        self.start_no = 0

    # ---- one emulator instance (one start of the chip) ----
    def make(self, keep_ram=False):
        uc = Uc(UC_ARCH_ARM, UC_MODE_THUMB | UC_MODE_MCLASS)
        fl = self.flash
        st = dict(locked=True, keyseq=0, ctrl=0, add=0, sts=0, ops=0, log=[], viol=[], end=None,
                  cut_after=None, regs={}, pa8=None, aircr=False, key_dead=False,
                  pod={GPIO_A + 0x400 * n: GPIO_POD_RESET.get(n, 0) for n in range(7)},
                  sws=0, sw_lag=0,          # SCLKSTS after a reset: HSI (manual 6.2.7)
                  pll_wait=0)               # RCC_CTRL reads left with PLLRDF 0 (pll_lock_reads)
        self.st = st
        self.uc = uc
        if self.flash_mode == 'boot':
            plain = [(FLASH, FLASH + PAGE), (SLOTS[0], SLOTS_END)]
            mm = [(FLASH + PAGE, SLOTS[0]), (SLOTS_END, FLASH + FLASH_SIZE)]
        else:
            plain = [(FLASH, FLASH + PAGE), (APP, APP_END)]
            mm = [(FLASH + PAGE, APP), (APP_END, SLOTS[0])]
            for s, name in zip(SLOTS, SLOT_NAMES):
                (mm if name == self.boot_target else plain).append((s, s + SLOT_SIZE))
            mm.append((SLOTS_END, FLASH + FLASH_SIZE))
        for lo, hi in plain:
            uc.mem_map(lo, hi - lo)
            uc.mem_write(lo, bytes(fl[lo - FLASH:hi - FLASH]))
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
        self._stop, self.violation = stop, viol

        def op_done(entry):
            st['log'].append(entry)
            st['ops'] += 1
            st['sts'] |= 0x20                      # EOP
            if st['cut_after'] is not None and st['ops'] >= st['cut_after']:
                stop('cut')
        self._op_done = op_done

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
                if self.flash_mode == 'boot':
                    if a >= SETTINGS:
                        viol('program in the settings page 0x%08X' % a)
                        return
                else:
                    why = self._gate(a, 'program')
                    if why:
                        viol(why)
                        return
                o = a - FLASH
                old = int.from_bytes(fl[o:o + 4], 'little')
                if old != 0xFFFFFFFF:
                    st['sts'] |= 4                 # PGERR, word unchanged
                    st['log'].append(('pgerr', a, value))
                    return
                new = value | self.stuck.get(a, 0)
                self._program(a, old, new, value)
            return wr

        for lo, hi in mm:
            uc.mmio_map(lo, hi - lo, fl_read(lo), None, fl_write(lo), None)

        def code_write(uc_, access, addr, size, value, user):
            viol('CPU store to code flash 0x%08X' % addr)
        for lo, hi in plain:
            uc.hook_add(UC_HOOK_MEM_WRITE, code_write, begin=lo, end=hi - 1)

        # Boot space alias 0x00000000..0x0007FFFF = main flash (module docstring "Boot alias"): the
        # plain parts as copies of the same bytes (they never change during a run: any CPU store to
        # them is a violation), the controller parts read live from the flash; any CPU store
        # through the alias is a violation.
        def alias_write(uc_, access, addr, size, value, user):
            viol('CPU store to the boot alias 0x%08X' % addr)

        def alias_mm_write(lo):
            def wr(uc_, off, size, value, user):
                viol('CPU store to the boot alias 0x%08X' % (lo - FLASH + off))
            return wr
        for lo, hi in plain:
            uc.mem_map(lo - FLASH, hi - lo)
            uc.mem_write(lo - FLASH, bytes(fl[lo - FLASH:hi - FLASH]))
            uc.hook_add(UC_HOOK_MEM_WRITE, alias_write, begin=lo - FLASH, end=hi - FLASH - 1)
        for lo, hi in mm:
            uc.mmio_map(lo - FLASH, hi - lo, fl_read(lo), None, alias_mm_write(lo), None)

        regs = st['regs']

        def rcc_sws(read):
            """SCLKSTS (RCC_CFG bits 3:2) by the RCC rules of the module docstring; read: one read
            of RCC_CFG (it counts down rcc_switch_reads)."""
            sw = regs.get(0x40021004, 0) & 3
            if self.sws_stuck is not None:
                return self.sws_stuck
            if not self.rcc_switch_reads and self.pll_locks:
                return sw
            if st['sws'] != sw:
                ready = sw != 2 or (self.pll_locks and regs.get(0x40021000, 0) >> 24 & 1)
                if ready:
                    if st['sw_lag'] > 0:
                        if read:
                            st['sw_lag'] -= 1
                    else:
                        st['sws'] = sw
            return st['sws']

        def p_read(uc_, off, size, user):
            a = 0x40000000 + off
            for d in self.devices:
                for lo, hi in d.ranges:
                    if lo <= a < hi:
                        return d.read(self, a, size) & ((1 << (8 * size)) - 1)
            if FC <= a < FC + 0x400:
                r = a - FC
                if r == 0x0C:
                    return st['sts']
                if r == 0x10:
                    return st['ctrl'] | (0x80 if st['locked'] else 0)
                if r == 0x14:
                    return st['add']
                return regs.get(a, 0)
            if self.timing and IWDG <= a < IWDG + 0x400:
                return self._iw_read(a, size) & ((1 << (8 * size)) - 1)
            v = regs.get(a & ~3, 0)
            if GPIO_A <= a < GPIO_END and a & 0x3FC == 0x0C:
                v = st['pod'][a & ~0x3FF]
            if a == 0x40021000:
                v |= ((v >> 16) & 1) << 17 | ((v >> 24) & 1) << 25
                if not self.pll_locks:
                    v &= ~(1 << 25)
                elif v >> 24 & 1 and st['pll_wait'] > 0:
                    st['pll_wait'] -= 1
                    v &= ~(1 << 25)
            elif a == 0x40021004:
                v = (v & ~0xC) | (rcc_sws(True) << 2)
            elif a == 0x40001424:
                v = 0x7FFF
            elif a == 0x40013800:
                v = 0xC0
            elif a == 0x40011008:
                v = (0 if self.key_pressed else 0x80) | 0x40
            elif self.timing and a & ~3 == RCC_CTRLSTS:
                lsi_on = self.ctrlsts & 1 or self.tm['iw']['running']
                v = (self.ctrlsts & ~2) | (2 if lsi_on else 0)
            if a & 3:
                v >>= 8 * (a & 3)
            return v & ((1 << (8 * size)) - 1)

        def p_write(uc_, off, size, value, user):
            a = 0x40000000 + off
            for d in self.devices:
                for lo, hi in d.ranges:
                    if lo <= a < hi:
                        d.write(self, a, size, value)
                        return
            if FC <= a < FC + 0x400:
                r = a - FC
                if r == 0x04:
                    if not st['locked']:
                        st['log'].append(('key-while-unlocked', value))
                    if st['key_dead']:
                        st['log'].append(('key-after-wrong-sequence', value))
                    elif st['keyseq'] == 0 and value == 0x45670123:
                        st['keyseq'] = 1
                    elif st['keyseq'] == 1 and value == 0xCDEF89AB:
                        st['locked'] = False
                        st['keyseq'] = 0
                    else:
                        st['keyseq'] = 0
                        if self.flash_mode == 'app' and st['locked']:
                            st['key_dead'] = True      # manual 3.2.5.2.5: locked until reset
                            st['log'].append(('key-wrong-sequence', value))
                elif r in (0x08, 0x1C, 0x20):
                    viol('flash controller register +0x%X written (0x%08X)' % (r, value))
                elif r == 0x0C:
                    st['sts'] &= ~value
                elif r == 0x14:
                    st['add'] = value
                elif r == 0x10 and self.flash_mode == 'app':
                    self._ctrl_app(value)
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
                        self._erase(pg)
                    st['ctrl'] = value & 0x3F & ~0x40
                else:
                    regs[a] = value
                return
            if self.timing and IWDG <= a < IWDG + 0x400:
                self._iw_write(a, size, value)
                return
            if self.timing and a & ~3 == RCC_CTRLSTS:
                if size != 4:
                    viol('RCC_CTRLSTS written with %d bytes' % size)
                    return
                if value & RMRSTF:
                    self.ctrlsts &= ~RST_FLAGS
                self.ctrlsts = (self.ctrlsts & ~1) | (value & 1)
                return
            if a in (0x40021000, 0x40021004) and size == 4:        # RCC rules (module docstring)
                old = regs.get(a, 0)
                if a == 0x40021004:
                    if (value ^ old) & 3:
                        st['sw_lag'] = self.rcc_switch_reads
                    if self.rcc_strict and regs.get(0x40021000, 0) >> 24 & 1 and (value ^ old) & 0x083F0000:
                        viol('RCC_CFG PLL bits changed 0x%08X -> 0x%08X while PLLEN is 1' % (old, value))
                        return
                else:
                    if self.rcc_strict and old & ~value & 0x01010000 and rcc_sws(False) == 2:
                        viol('RCC_CTRL 0x%08X -> 0x%08X clears PLLEN / HSEEN while SCLKSTS reads PLL' % (old, value))
                        return
                    if value & ~old & 1 << 24:
                        st['pll_wait'] = self.pll_lock_reads
            if GPIO_A <= a < GPIO_END and 0x0C <= a & 0x3FF < 0x18:
                port, r = a & ~0x3FF, a & 0x3FF
                w = value << 8 * (r & 3)
                if r & ~3 == 0x0C:
                    st['pod'][port] = (st['pod'][port] & ~(((1 << 8 * size) - 1) << 8 * (r & 3)) | w) & 0xFFFF
                elif r & ~3 == 0x10:
                    st['pod'][port] = ((st['pod'][port] & ~(w >> 16)) | w) & 0xFFFF
                else:
                    st['pod'][port] &= ~w & 0xFFFF
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
            if self.timing:
                r = self._scs_read(a, size)
                if r is not None:
                    return r & ((1 << (8 * size)) - 1)
            v = scs.get(a & ~3, 0)
            if a == 0xE000E010:
                v |= 1 << 16
            if a & 3:
                v >>= 8 * (a & 3)
            return v & ((1 << (8 * size)) - 1)

        def s_write(uc_, off, size, value, user):
            a = 0xE000E000 + off
            # AIRCR: register key 0x05FA in bits 31..16 and SYSRESETREQ (bit 2); the other bits
            # (PRIGROUP 10..8, as system_reset keeps them) do not matter for the reset
            if a == 0xE000ED0C and value >> 16 == 0x05FA and value & 4:
                st['log'].append(('reset',))
                stop('reset')
            if self.timing and self._scs_write(a, size, value):
                return
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
        if self.timing:
            self._tm_make(uc)
        for d in self.devices:
            if hasattr(d, 'reset'):
                d.reset(self)
        return uc

    # ---- flash operations shared by both modes ----
    def _gate(self, a, what):
        """Mode 'app': None when the code doing the operation may touch the page of a, else the text."""
        pc = self.uc.reg_read(UC_ARM_REG_PC)
        pg = a & ~(PAGE - 1)
        if APP <= pc < APP_END:
            if pg in self.app_pages:
                return None
            return '%s of 0x%08X outside the application gate (code at 0x%08X)' % (what, a, pc)
        if FLASH <= pc < FLASH + PAGE or SLOTS[0] <= pc < SLOTS_END:
            if pg in (REC0, REC1):
                return None
            return '%s of 0x%08X by bootloader code at 0x%08X outside the record pages' % (what, a, pc)
        return '%s of 0x%08X by code at 0x%08X outside the flash images' % (what, a, pc)

    def _ctrl_app(self, value):
        """FLASH_CTRL write in mode 'app' (manual 3.2.5.2.5)."""
        st = self.st
        if value & 0x234:
            self.violation('CTRL option / mass erase / OPTWE bit: 0x%X' % value)
            return
        if value & 0x3C00:
            self.violation('CTRL interrupt enable (not modelled): 0x%X' % value)
            return
        if value & ~0x3FFF or value & 0x8:
            self.violation('CTRL reserved bit: 0x%X' % value)
            return
        if value & 0x80:
            st['locked'] = True
        if st['locked'] and value & 0x43 and not value & 0x80:
            self.violation('CTRL PG/PER/START while locked: 0x%X' % value)
            return
        if value & 0x01 and value & 0x02:
            self.violation('CTRL PG and PER together: 0x%X' % value)
            return
        if value & 0x40 and not value & 0x02 and not st['locked']:
            self.violation('CTRL START without PER: 0x%X' % value)
            return
        if value & 0x40 and value & 0x02 and not st['locked']:
            pg = st['add'] & ~(PAGE - 1)
            if not FLASH <= pg < FLASH + FLASH_SIZE:
                self.violation('erase outside flash 0x%08X' % pg)
                return
            why = self._gate(pg, 'erase')
            if why:
                self.violation(why)
                return
            self._erase(pg)
        st['ctrl'] = value & 0x103

    def _cut_here(self):
        st = self.st
        return (self.cut_pattern is not None and st['cut_after'] is not None
                and st['ops'] + 1 >= st['cut_after'])

    def _iwdg_cuts(self, dur):
        """Timing: books the operation's duration; True when the IWDG expires within it."""
        if not self.timing:
            return False
        now = self.now()
        self._iw_sync(now)
        if self.tm['iw']['running']:
            t_exp = self._iw_expiry(now)
            if t_exp <= now + dur:
                self.tm['extra'] += max(0.0, t_exp - now)
                return True
        self.tm['extra'] += dur
        return False

    def _erase(self, pg):
        st, fl = self.st, self.flash
        o = pg - FLASH
        cut = self._cut_here()
        dead = self._iwdg_cuts(T_ERASE)
        if cut or dead:
            pat = self.cut_pattern if self.cut_pattern is not None else 'mixed'
            f = ERASE_CUTS[pat] if isinstance(pat, str) else pat
            fl[o:o + PAGE] = f(bytes(fl[o:o + PAGE]))
            st['ops'] += 1
            st['log'].append(('erase-cut', pg, pat if isinstance(pat, str) else 'function'))
            self._end_by(dead and not cut)
            return
        fl[o:o + PAGE] = b'\xff' * PAGE
        if pg in self.erase_fail:
            fl[o:o + 4] = bytes(4)
        self._op_done(('erase', pg))

    def _program(self, a, old, new, value):
        st, fl = self.st, self.flash
        o = a - FLASH
        if self.flash_mode == 'app':
            pc = self.uc.reg_read(UC_ARM_REG_PC)
            if APP <= pc < APP_END:
                if st['ctrl'] & 0x100:
                    self.violation('word program with SMPSEL 1 (SMP2) at 0x%08X' % a)
                    return
                code = bytes(self.uc.mem_read(pc, 32))
                i = thumb_offsets(code)[1]
                for _ in range(5):
                    n = _nop_len(code, i)
                    if not n:
                        self.violation('word program at 0x%08X (store at 0x%08X) not followed by five NOPs '
                                       '(manual 3.2.1.4.2)' % (a, pc))
                        return
                    i += n
        cut = self._cut_here()
        dead = self._iwdg_cuts(T_PROG)
        if cut or dead:
            pat = self.cut_pattern if self.cut_pattern is not None else 'mixed'
            f = WORD_CUTS[pat] if isinstance(pat, str) else pat
            fl[o:o + 4] = struct.pack('<I', f(old, new) & 0xFFFFFFFF)
            st['ops'] += 1
            st['log'].append(('word-cut', a, value, pat if isinstance(pat, str) else 'function'))
            self._end_by(dead and not cut)
            return
        fl[o:o + 4] = struct.pack('<I', new)
        self._op_done(('word', a, value))

    def _end_by(self, iwdg):
        if iwdg:
            self._iw_log('reset', self.now())
            self._stop('iwdg')
        else:
            self._stop('cut')

    # ---- timing: time base, interrupts, SysTick, IWDG ----
    def _tm_make(self, uc):
        lib = _bc_lib()
        bcp = lib.bc_new(ctypes.cast(_uclib.uc_mem_read, ctypes.c_void_p),
                         ctypes.cast(_uclib.uc_emu_stop, ctypes.c_void_p),
                         ctypes.cast(_uclib.uc_reg_read, ctypes.c_void_p))
        weakref.finalize(uc, lib.bc_free, ctypes.cast(bcp, ctypes.c_void_p))
        self.bc = bc = bcp.contents
        self._bc_at = lib.bc_icount_at
        self._bc_pc = lib.bc_icount_pc
        self._bc_ptr = ctypes.cast(bcp, ctypes.c_void_p)
        self._uch = uc._uch
        tm = _Tm(icount=0, blk=None, extra=0.0, t0=self.clock, stop_req=False, active=[], excret=[],
                 pend=set(), en=set(), irq_count={}, prigroup=0)
        tm.bc, tm.live = bc, False
        tm['st'] = dict(csr=0, rvr=0, v0=0, t_ref=self.clock, done=0)
        iw = dict(running=False, unlocked=False, pr=0, rl=0xFFF, pr_pend=None, rl_pend=None, cnt=0xFFF,
                  load_t=self.clock, load_val=0xFFF, div=4)
        tm['iw'] = iw
        self.tm = tm
        self.start_no += 1
        carry, self.iwdg_carry = self.iwdg_carry, None
        if carry is not None:
            iw.update(running=True, pr=carry['pr'], rl=carry['rl'], div=4 << min(carry['pr'], 6),
                      load_t=self.clock, load_val=carry['left_ticks'])
            self._iw_log('carried', self.clock)
        h = _uc_hook_h()
        err = _uclib.uc_hook_add(uc._uch, ctypes.byref(h), UC_HOOK_BLOCK,
                                 ctypes.cast(lib.bc_block, ctypes.c_void_p), self._bc_ptr,
                                 ctypes.c_uint64(1), ctypes.c_uint64(0))
        if err:
            raise UcError(err)

    def _icount_at(self, pc):
        if self.tm.live:
            return self._bc_at(self._bc_ptr, pc)
        return self.tm['icount']            # between slices nothing is booked (tm['blk'] is None)

    def now(self):
        """Emulated seconds since power-on (timing only)."""
        t, tm = self.timing, self.tm
        ic = self._bc_pc(self._bc_ptr, self._uch) if tm.live else tm['icount']
        return tm['t0'] + ic * t['cpi'] / t['core'] + tm['extra']

    def icount(self):
        """Instructions since power-on (timing only)."""
        return self.icount_total + self._icount_at(_rr(self._uch, UC_ARM_REG_PC))

    def irq_check(self):
        """A register write that may change an interrupt line: end the slice at the next block."""
        if self.tm is not None:
            self.tm['stop_req'] = True

    def _settle(self):
        tm = self.tm
        if tm.live:                         # end of a slice: the count back from the native hook
            tm.live = False
            bc = self.bc
            tm['icount'] = self._bc_at(self._bc_ptr, _rr(self._uch, UC_ARM_REG_PC))
            tm['stop_req'] = bool(bc.stop_req)
            bc.blk_valid = 0
        tm['blk'] = None

    def _end(self, reason):
        if self.st['end'] is None:
            self.st['end'] = reason

    def _next_event(self, now):
        ev = []
        if self.tm['iw']['running']:
            ev.append(self._iw_expiry(now))
        n = self._st_next()
        if n is not None:
            ev.append(n)
        for d in self.devices:
            if hasattr(d, 'next_event'):
                x = d.next_event(self, now)
                if x is not None:
                    ev.append(x)
        return min(ev) if ev else None

    def _events(self):
        now = self.now()
        self._iw_sync(now)
        if self.tm['iw']['running'] and now >= self._iw_expiry(now):
            self._iw_log('reset', now)
            self._end('iwdg')
            return
        self._st_events(now)
        for d in self.devices:
            if hasattr(d, 'tick'):
                d.tick(self, now)
                if self.st['end'] is not None:
                    return

    def _run(self, pc, budget=None, until_t=None, until=None):
        """Timing loop: slices, events, interrupts. Returns when the run ends, the instruction budget
        is used (end 'timeout'), the emulated time until_t is reached or until(m) is true (None)."""
        uc, st, tm, t, uch = self.uc, self.st, self.tm, self.timing, self._uch
        done = 0
        _rw(uch, UC_ARM_REG_PC, pc | 1)
        while st['end'] is None:
            if until is not None and until(self):
                return None
            now = self.now()
            if until_t is not None and now >= until_t:
                return None
            if budget is not None and done >= budget:
                self._end('timeout')
                break
            n = t['slice']
            nxt = self._next_event(now)
            if until_t is not None:
                nxt = until_t if nxt is None else min(nxt, until_t)
            if nxt is not None:
                n = min(n, max(1, math.ceil((nxt - now) * t['core'] / t['cpi'])))
            if budget is not None:
                n = min(n, budget - done)
            tm['stop_req'] = False
            bc = self.bc
            if tm.live:
                # a hook's exception left the last slice unsettled: the count and the booked block
                # stay as the hook left them (as tm did with the Python hook)
                ic0 = bc.icount
                bc.stop_req = 0
            else:
                ic0 = tm['icount']          # the native hook takes over the count for the slice
                bc.icount, bc.stop_req, bc.blk_valid = ic0, 0, 0
                tm.live = True
            try:
                uc.emu_start(_rr(uch, UC_ARM_REG_PC) | 1, NO_UNTIL, count=n)
            except UcError as e:
                p = _rr(uch, UC_ARM_REG_PC)
                self._settle()
                if e.errno == UC_ERR_EXCEPTION and p >= 0xFFFFFFE0 and st['end'] is None:
                    self._exc_return(p)
                elif e.errno == UC_ERR_FETCH_PROT and APP <= p < APP_END and st['end'] is None:
                    st['end'] = 'app'
                    st['app_pc'] = p
                elif st['end'] is None:
                    st['end'] = 'emu error %s at 0x%08X' % (e, p)
            self._settle()
            done += tm['icount'] - ic0
            if st['end'] is not None:
                break
            self._events()
            if st['end'] is not None:
                break
            self._irq()
        return st['end']

    def _epilogue(self):
        uc, st = self.uc, self.st
        st['vtor'] = self.scs.get(0xE000ED08, 0)
        st['primask'] = uc.reg_read(UC_ARM_REG_PRIMASK)
        st['msp'] = uc.reg_read(UC_ARM_REG_MSP)
        self.ram = bytes(uc.mem_read(SRAM, SRAM_SIZE))

    def _finish_start(self):
        """Timing: book the end of a run (clock, instruction total, reset flags, IWDG across a reset)."""
        st, tm = self.st, self.tm
        now = self.now()
        self._settle()
        self.icount_total += tm['icount']
        tm['icount'] = 0
        tm['t0'], tm['extra'] = now, 0.0
        self.clock = now
        iw = tm['iw']
        if st['end'] == 'iwdg':
            self.ctrlsts |= IWDGRSTF
        elif st['end'] == 'reset':
            self.ctrlsts |= SFTRSTF
        if st['end'] in ('iwdg', 'reset') and iw['running']:
            self._iw_sync(now)
            if self.timing['survives']:
                left = iw['rl'] if st['end'] == 'iwdg' else max(0.0, self._iw_count(now))
                self.iwdg_carry = dict(pr=iw['pr'], rl=iw['rl'], left_ticks=left)
            else:
                self._iw_log('stopped', now)
            iw['running'] = False

    # NVIC / SCB / SysTick registers (timing only); None / False: not handled here
    def _prio(self, exc):
        if exc >= 16:
            a = 0xE000E400 + exc - 16
        elif exc >= 4:
            a = 0xE000ED18 + exc - 4
        else:
            return -1
        return (self.scs.get(a & ~3, 0) >> 8 * (a & 3)) & 0xF0

    def _scs_read(self, a, size):
        tm, scs = self.tm, self.scs
        w = a & ~3
        sh = 8 * (a & 3)
        if 0xE000E010 <= w <= 0xE000E01C:
            return self._st_read(w) >> sh
        if 0xE000E100 <= w < 0xE000E120 or 0xE000E180 <= w < 0xE000E1A0:
            base = (w & 0x1F) * 8
            return sum(1 << i for i in range(32) if base + i + 16 in tm['en']) >> sh
        if 0xE000E200 <= w < 0xE000E220 or 0xE000E280 <= w < 0xE000E2A0:
            base = (w & 0x1F) * 8
            return sum(1 << i for i in range(32) if base + i + 16 in tm['pend']) >> sh
        if 0xE000E300 <= w < 0xE000E320:
            base = (w & 0x1F) * 8
            return sum(1 << i for i in range(32) if base + i + 16 in tm['active']) >> sh
        if 0xE000E400 <= w < 0xE000E4F0 or 0xE000ED18 <= w <= 0xE000ED20:
            return (scs.get(w, 0) & 0xF0F0F0F0) >> sh
        if w == 0xE000ED04:
            v = tm['active'][-1] if tm['active'] else 0
            pend = sorted(tm['pend'])
            if pend:
                v |= (pend[0] & 0x1FF) << 12
                if any(p >= 16 for p in pend):
                    v |= 1 << 22
            if EXC_SYSTICK in tm['pend']:
                v |= 1 << 26
            if EXC_PENDSV in tm['pend']:
                v |= 1 << 28
            return v >> sh
        return None

    def _scs_write(self, a, size, value):
        tm = self.tm
        w = a & ~3
        if size != 4 and not (0xE000E400 <= w < 0xE000E4F0 or 0xE000ED18 <= w <= 0xE000ED20):
            if 0xE000E010 <= w <= 0xE000E01C or 0xE000E100 <= w < 0xE000E320 or w == 0xE000ED04:
                self.violation('SCS register 0x%08X written with %d bytes' % (a, size))
                return True
            return False
        if 0xE000E010 <= w <= 0xE000E01C:
            self._st_write(w, value)
            self.irq_check()
            return True
        if 0xE000E100 <= w < 0xE000E2A0:
            base = (w & 0x1F) * 8
            bits = {base + i + 16 for i in range(32) if value >> i & 1}
            if w < 0xE000E120:
                tm['en'] |= bits
            elif 0xE000E180 <= w < 0xE000E1A0:
                tm['en'] -= bits
            elif 0xE000E200 <= w < 0xE000E220:
                tm['pend'] |= bits
            elif 0xE000E280 <= w < 0xE000E2A0:
                tm['pend'] -= bits
            else:
                return False
            self.irq_check()
            return True
        if w == 0xE000ED04:
            if value & 1 << 31:
                self._stop('model: NMIPENDSET not modelled')
                return True
            if value & 1 << 28:
                tm['pend'].add(EXC_PENDSV)
            if value & 1 << 27:
                tm['pend'].discard(EXC_PENDSV)
            if value & 1 << 26:
                tm['pend'].add(EXC_SYSTICK)
            if value & 1 << 25:
                tm['pend'].discard(EXC_SYSTICK)
            self.irq_check()
            return True
        if w == 0xE000ED0C and value >> 16 == 0x05FA:
            tm['prigroup'] = (value >> 8) & 7
            return False
        if w == 0xE000EF00:
            tm['pend'].add(16 + (value & 0x1FF))
            self.irq_check()
            return True
        if 0xE000E400 <= w < 0xE000E4F0 or 0xE000ED18 <= w <= 0xE000ED20:
            self.irq_check()
            return False                           # stored by s_write, masked on read
        return False

    def _st_count(self, now):
        """SysTick: (number of 1 -> 0 transitions since t_ref, current value)."""
        s = self.tm['st']
        rvr = s['rvr'] & 0xFFFFFF
        k = int((now - s['t_ref']) * self.timing['core'])
        v0 = s['v0']
        if k <= 0:
            return 0, v0
        if v0 > 0 and k < v0:
            return 0, v0 - k
        if rvr == 0:
            return (1 if v0 > 0 else 0), 0
        first = v0 if v0 > 0 else rvr + 1
        n = 1 + (k - first) // (rvr + 1)
        into = (k - first) % (rvr + 1)
        return n, (0 if into == 0 else rvr + 1 - into)

    def _st_next(self):
        s = self.tm['st']
        if not s['csr'] & 1:
            return None
        rvr = s['rvr'] & 0xFFFFFF
        v0 = s['v0']
        if rvr == 0 and (v0 == 0 or s['done'] >= 1):
            return None
        first = v0 if v0 > 0 else rvr + 1
        k = first + s['done'] * (rvr + 1)
        return s['t_ref'] + k / self.timing['core']

    def _st_events(self, now):
        s = self.tm['st']
        if not s['csr'] & 1:
            return
        n, _ = self._st_count(now)
        if n > s['done']:
            s['done'] = n
            s['csr'] |= 1 << 16
            if s['csr'] & 2:
                self.tm['pend'].add(EXC_SYSTICK)

    def _st_rebase(self, now):
        s = self.tm['st']
        if s['csr'] & 1:
            self._st_events(now)
            s['v0'] = self._st_count(now)[1]
        s['t_ref'], s['done'] = now, 0

    def _st_read(self, w):
        s = self.tm['st']
        now = self.now()
        self._st_events(now)
        if w == 0xE000E010:
            v = s['csr']
            s['csr'] &= ~(1 << 16)
            return v
        if w == 0xE000E014:
            return s['rvr']
        if w == 0xE000E018:
            return self._st_count(now)[1] if s['csr'] & 1 else s['v0']
        return 18000                               # CALIB, manual 2.1.1

    def _st_write(self, w, value):
        s = self.tm['st']
        now = self.now()
        if w == 0xE000E010:
            if value & 1 and not value & 4:
                self._stop('model: SysTick CLKSOURCE 0 (reference clock) not modelled')
                return
            if value & 1 and not s['csr'] & 1:
                s['t_ref'], s['done'] = now, 0
            elif not value & 1 and s['csr'] & 1:
                self._st_rebase(now)
            s['csr'] = (s['csr'] & 1 << 16) | (value & 7)
        elif w == 0xE000E014:
            self._st_rebase(now)
            s['rvr'] = value & 0xFFFFFF
        elif w == 0xE000E018:
            s['v0'], s['t_ref'], s['done'] = 0, now, 0
            s['csr'] &= ~(1 << 16)

    def _group(self, prio):
        g = self.tm['prigroup']
        return prio & ~((1 << (g + 1)) - 1) & 0xFF if prio >= 0 else prio

    def _irq(self):
        uc, tm, uch = self.uc, self.tm, self._uch
        for d in self.devices:
            if hasattr(d, 'irqs'):
                for n in d.irqs(self):
                    if 16 + n not in tm['active']:
                        tm['pend'].add(16 + n)
        cand = [e for e in tm['pend'] if e < 16 or e in tm['en']]
        if not cand:
            return
        cur = min((self._group(self._prio(e)) for e in tm['active']), default=256)
        if _rr(uch, UC_ARM_REG_PRIMASK) & 1:
            cur = min(cur, 0)
        bp = _rr(uch, UC_ARM_REG_BASEPRI) & 0xF0
        if bp:
            cur = min(cur, self._group(bp))
        best = min(cand, key=lambda e: (self._group(self._prio(e)), self._prio(e), e))
        if self._group(self._prio(best)) < cur:
            self._enter(best)

    def _vector(self, exc):
        vtor = self.scs.get(0xE000ED08, 0) & 0xFFFFFF80
        a = vtor + 4 * exc
        if a < 0x00080000:
            a += FLASH
        if FLASH <= a < FLASH + FLASH_SIZE:
            return struct.unpack_from('<I', self.flash, a - FLASH)[0]
        return struct.unpack('<I', bytes(self.uc.mem_read(a, 4)))[0]

    def _enter(self, exc):
        uc, tm, uch = self.uc, self.tm, self._uch
        control = _rr(uch, UC_ARM_REG_CONTROL)
        if control & 2:
            self._end('model: exception entry from a thread on PSP not modelled')
            return
        fp = bool(control & 4)
        regs = [_rr(uch, r) for r in (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3,
                                         UC_ARM_REG_R12, UC_ARM_REG_LR)]
        ret = _rr(uch, UC_ARM_REG_PC) & ~1
        xpsr = _rr(uch, UC_ARM_REG_XPSR)
        if xpsr & 0x0600FC00:
            self._end('model: exception entry inside an IT block (xPSR 0x%08X)' % xpsr)
            return
        sp = _rr(uch, UC_ARM_REG_MSP)
        size = 0x68 if fp else 0x20
        align = (sp >> 2) & 1
        frame = (sp - size) & ~(4 if align else 0)
        if frame < SRAM:
            self.st['viol'].append('exception stack frame at 0x%08X below SRAM' % frame)
            self._end('violation')
            return
        ipsr = tm['active'][-1] if tm['active'] else 0
        sx = (xpsr & 0xFF0FFC00 & ~(1 << 9)) | (1 << 24) | (align << 9) | ipsr
        words = regs + [ret, sx]
        if fp:
            words += [_rr(uch, r) for r in S_REGS] + [_rr(uch, UC_ARM_REG_FPSCR), 0]
        nested = bool(tm['active'])
        excret = (0xFFFFFFE1 if fp else 0xFFFFFFF1) if nested else (0xFFFFFFE9 if fp else 0xFFFFFFF9)
        vec = self._vector(exc)
        if not vec & 1:
            self.st['viol'].append('vector %d = 0x%08X without the Thumb bit' % (exc, vec))
            self._end('violation')
            return
        uc.mem_write(frame, struct.pack('<%dI' % len(words), *[w & 0xFFFFFFFF for w in words]))
        _rw(uch, UC_ARM_REG_MSP, frame)
        _rw(uch, UC_ARM_REG_SP, frame)
        _rw(uch, UC_ARM_REG_LR, excret)
        if fp:
            _rw(uch, UC_ARM_REG_CONTROL, control & ~4)
        _rw(uch, UC_ARM_REG_PC, vec)
        tm['pend'].discard(exc)
        tm['active'].append(exc)
        tm['excret'].append((excret, frame, fp))
        tm['irq_count'][exc] = tm['irq_count'].get(exc, 0) + 1
        tm['blk'] = None

    def _exc_return(self, p):
        uc, tm, uch = self.uc, self.tm, self._uch
        if not tm['active']:
            self._end('emu error: EXC_RETURN 0x%08X in thread mode' % p)
            return
        excret, frame, fp = tm['excret'][-1]
        if (p | 1) != excret:
            self.st['viol'].append('EXC_RETURN 0x%08X, entry gave 0x%08X' % (p | 1, excret))
            self._end('violation')
            return
        sp = _rr(uch, UC_ARM_REG_MSP)
        if sp != frame:
            self.st['viol'].append('exception return with SP 0x%08X, frame at 0x%08X' % (sp, frame))
            self._end('violation')
            return
        n = 26 if fp else 8
        w = struct.unpack('<%dI' % n, bytes(uc.mem_read(sp, 4 * n)))
        for r, v in zip((UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3, UC_ARM_REG_R12,
                         UC_ARM_REG_LR), w[:6]):
            _rw(uch, r, v)
        if fp:
            for r, v in zip(S_REGS, w[8:24]):
                _rw(uch, r, v)
            _rw(uch, UC_ARM_REG_FPSCR, w[24])
            _rw(uch, UC_ARM_REG_CONTROL, _rr(uch, UC_ARM_REG_CONTROL) | 4)
        sp += 4 * n + (4 if w[7] >> 9 & 1 else 0)
        _rw(uch, UC_ARM_REG_XPSR, (w[7] & 0xF80F0000) | (1 << 24))
        _rw(uch, UC_ARM_REG_MSP, sp)
        _rw(uch, UC_ARM_REG_SP, sp)
        _rw(uch, UC_ARM_REG_PC, w[6] | 1)
        tm['active'].pop()
        tm['excret'].pop()
        tm['blk'] = None

    # IWDG (manual 16.5)
    def _iw_log(self, kind, t, pc=None):
        self.iwdg_log.append(dict(kind=kind, t=t, start=self.start_no, pc=pc, insn=self.icount()))

    def _iw_sync(self, now):
        iw = self.tm['iw']
        p = iw['pr_pend']
        if p is not None and p[1] <= now:
            if iw['running']:
                iw['load_val'] = self._iw_count(p[1])
                iw['load_t'] = p[1]
            iw['pr'] = p[0]
            iw['div'] = 4 << min(p[0], 6)
            iw['pr_pend'] = None
        r = iw['rl_pend']
        if r is not None and r[1] <= now:
            iw['rl'] = r[0]
            iw['rl_pend'] = None

    def _iw_count(self, t):
        iw = self.tm['iw']
        return iw['load_val'] - (t - iw['load_t']) * self.timing['lsi'] / iw['div']

    def _iw_expiry(self, now):
        """Time of the reset: RL + 1 ticks after the load (Table 16-1: RL 0 -> one tick)."""
        iw, lsi = self.tm['iw'], self.timing['lsi']
        t_exp = iw['load_t'] + (iw['load_val'] + 1) * iw['div'] / lsi
        p = iw['pr_pend']
        if p is not None and p[1] < t_exp:
            left = iw['load_val'] + 1 - (p[1] - iw['load_t']) * lsi / iw['div']
            t_exp = p[1] + left * (4 << min(p[0], 6)) / lsi
        return t_exp

    def _iw_read(self, a, size):
        if size == 1:
            self.violation('IWDG register 0x%08X read with 1 byte' % a)
            return 0
        now = self.now()
        self._iw_sync(now)
        iw = self.tm['iw']
        r = a - IWDG
        v = 0
        if r == 4:
            v = iw['pr']
        elif r == 8:
            v = iw['rl']
        elif r == 0xC:
            v = (1 if iw['pr_pend'] else 0) | (2 if iw['rl_pend'] else 0)
        elif r != 0:
            self.violation('IWDG reserved address 0x%08X read' % a)
        return v

    def _iw_write(self, a, size, value):
        if size == 1:
            self.violation('IWDG register 0x%08X written with 1 byte' % a)
            return
        now = self.now()
        self._iw_sync(now)
        iw, t = self.tm['iw'], self.timing
        pc = self.uc.reg_read(UC_ARM_REG_PC)
        r = a - IWDG
        if r == 0:
            if value & ~0xFFFF:
                self.violation('IWDG_KEY reserved bits: 0x%08X' % value)
                return
            key = value & 0xFFFF
            iw['unlocked'] = key == 0x5555
            rl_now = iw['rl'] if iw['rl_pend'] is None else min(iw['rl'], iw['rl_pend'][0])
            if key == 0xAAAA:
                if iw['running']:
                    iw['load_t'], iw['load_val'] = now, rl_now
                    self._iw_log('feed', now, pc)
                elif t['aaaa_starts']:
                    iw['running'] = True
                    iw['load_t'], iw['load_val'] = now, rl_now
                    self._iw_log('start', now, pc)
                else:
                    iw['cnt'] = rl_now
                    self._iw_log('feed-stopped', now, pc)
            elif key == 0xCCCC:
                if not iw['running']:
                    iw['running'] = True
                    iw['load_t'], iw['load_val'] = now, iw['cnt']
                    self._iw_log('start', now, pc)
            elif key != 0x5555:
                self.st['log'].append(('iwdg-key', key))
            return
        if r in (4, 8):
            mask = 7 if r == 4 else 0xFFF
            if value & ~mask:
                self.violation('IWDG +%d reserved bits: 0x%08X' % (r, value))
                return
            if not iw['unlocked']:
                self.st['log'].append(('iwdg-protected-write', r, value))
                return
            name = 'pr_pend' if r == 4 else 'rl_pend'
            if iw[name] is not None:
                self.st['log'].append(('iwdg-write-while-updating', r, value))
                return
            iw[name] = (value, now + t['sync'] / t['lsi'])
            return
        self.violation('IWDG register 0x%08X written (0x%08X)' % (a, value))

    def iwdg_stretch(self):
        """Longest stretch between two counter loads (start / reload) of a running IWDG over all starts
        so far, a stretch that ended in the IWDG reset included: dict(longest, open). longest:
        dict(seconds, insns, begin, end) with the two iwdg_log entries (kind, t, start, pc, insn) or
        None; open: the stretch from the last load to now while the IWDG still runs, or None."""
        best, last = None, None
        for e in self.iwdg_log:
            k = e['kind']
            if k in ('start', 'feed', 'reset'):
                if last is not None:
                    d = dict(seconds=e['t'] - last['t'], insns=e['insn'] - last['insn'], begin=last, end=e)
                    if best is None or d['seconds'] > best['seconds']:
                        best = d
                last = e if k != 'reset' or self.timing['survives'] else None
            elif k == 'stopped':
                last = None
        open_ = None
        if last is not None and self.tm is not None and self.tm['iw']['running']:
            open_ = dict(seconds=self.now() - last['t'], insns=self.icount() - last['insn'], begin=last)
        return dict(longest=best, open=open_)

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
        if self.timing:
            self._run(pc, budget=count)
            if st['end'] is None:
                st['end'] = 'timeout'
            self._epilogue()
            self._finish_start()
            return st['end']
        try:
            uc.emu_start(pc | 1, NO_UNTIL, count=count)
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

    def start(self, pc, sp=None):
        """Timing: set the made chip to run at pc (and SP) without running it; run_for() drives it."""
        if not self.timing:
            raise RuntimeError('start() / run_for() need set_timing()')
        if sp is not None:
            self.uc.reg_write(UC_ARM_REG_SP, sp)
        self.uc.reg_write(UC_ARM_REG_PC, pc | 1)
        self.st['end'] = None

    def halt(self, reason='halt'):
        """Timing: end the started chip's run here, booked as run_for() books an end (SRAM kept in
        self.ram, clock, reset flags: 'iwdg' sets IWDGRSTF, 'reset' SFTRSTF, any other reason none),
        so that the next make(keep_ram=True) / start_app(keep_ram=True) starts with this SRAM, as a
        reset that keeps it. Returns the reason."""
        if not self.timing:
            raise RuntimeError('halt() needs set_timing()')
        if self.st['end'] is None:
            self.st['end'] = reason
            self._epilogue()
            self._finish_start()
        return self.st['end']

    def start_app(self, keep_ram=False):
        """Timing: a start directly at the application's reset vector (no chain), not yet run."""
        self.make(keep_ram=keep_ram)
        sp, pc = struct.unpack_from('<II', self.flash, APP - FLASH)
        self.start(pc, sp)

    def run_for(self, seconds=None, until=None, max_insns=None):
        """Timing: continue the started chip for `seconds` of emulated time, or until until(m) is true,
        or for max_insns instructions. Returns the end reason, None while the chip still runs. When
        the run ends, it is booked (SRAM kept in self.ram, clock, reset flags) as go() does."""
        st = self.st
        if st['end'] is not None:
            return st['end']
        t_end = None if seconds is None else self.now() + seconds
        self._run(self.uc.reg_read(UC_ARM_REG_PC), budget=max_insns, until_t=t_end, until=until)
        if st['end'] == 'timeout' and max_insns is not None:
            st['end'] = None
        if st['end'] is not None:
            self._epilogue()
            self._finish_start()
        return st['end']

    def call(self, addr, *args, count=200_000_000):
        """Direct call of a function of the running image; returns r0 (None when it did not return)."""
        uc, st = self.uc, self.st
        regs = (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3)
        for r, v in zip(regs, args):
            uc.reg_write(r, v & 0xFFFFFFFF)
        uc.reg_write(UC_ARM_REG_LR, RET | 1)
        st['end'] = None
        if self.timing:
            self._run(addr, budget=count)
        else:
            try:
                uc.emu_start(addr | 1, NO_UNTIL, count=count)
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

    def starts(self, n=4, hook=None, keep_ram=True, **kw):
        """Up to n starts through boot(): after an end 'iwdg' or 'reset' the chip starts again, as the
        hardware does (hook(m, end) runs first and may change the meter; it returns False to stop).
        The first start is power-on (SRAM cleared); later ones keep SRAM when keep_ram (the manual
        does not state whether main SRAM survives a reset; tests choose). Returns the list of ends."""
        ends = []
        for k in range(n):
            end = self.boot(keep_ram=keep_ram and k > 0, **kw)
            ends.append(end)
            if end not in ('iwdg', 'reset'):
                break
            if hook is not None and hook(self, end) is False:
                break
        return ends

    def events(self):
        return [x[1] for x in self.st['log'] if x[0] == 'at']

    def flash_ops(self):
        return [x for x in self.st['log'] if x[0] in ('word', 'erase')]
