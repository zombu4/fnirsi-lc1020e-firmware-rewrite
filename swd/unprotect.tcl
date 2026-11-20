# unprotect.tcl - read protection L1 -> L0 over SWD. IRREVERSIBLE for the flash contents: the chip
# erases all of main flash when RDP1 is rewritten to 0xA5 (user manual V3.5.0 p.58). Run only after
# the backup of GUIDE.md section 5 or 6 exists and has been verified (GUIDE.md section 7).
#
# Sequence (manual 3.2.1.3 / 3.2.1.4.3, Table 3-3; FLASH base 0x40022000: KEY +0x04, OPTKEY +0x08,
# STS +0x0C (BUSY bit 0, PGERR bit 2, WRPERR bit 4, EOP bit 5), CTRL +0x10 (OPTPG bit 4, OPTER bit 5,
# START bit 6, LOCK bit 7, OPTWE bit 9), OB +0x1C):
#   KEY1, KEY2 -> FLASH_KEY; KEY1, KEY2 -> FLASH_OPTKEY (OPTWE must read 1);
#   CTRL = OPTWE | OPTER, then | START; wait BUSY = 0; CTRL = OPTWE;
#   CTRL = OPTWE | OPTPG; word 0x00FF00A5 -> 0x1FFFF800 (RDP1 0xA5, USER 0xFF; complements by the
#   chip); wait BUSY = 0 (the automatic mass erase runs here); CTRL = 0 | LOCK.
# Never written: 0x1FFFF804..0x1FFFF813 (Data, WRP, RDP2 / L2). All other option bytes read 0xFF
# on the meter = the erased value. Only a mem_ap target; the core is halted
# first so that no code runs from flash during the change.
# Usage: cd swd && DAP_HOST=<probe-ip> DAP_PORT=4441 CONFIRM=L1-TO-L0 openocd -f probe-cmsis-dap-tcp.cfg -f unprotect.tcl
if {![info exists ::env(CONFIRM)] || $::env(CONFIRM) ne "L1-TO-L0"} { echo "set CONFIRM=L1-TO-L0"; shutdown error }
swd newdap chip cpu -enable
dap create chip.dap -chain-position chip.cpu
target create chip.mem mem_ap -dap chip.dap -ap-num 0
init
proc rd {a} { return [lindex [chip.mem read_memory $a 32 1] 0] }
proc wr {a v} { chip.mem write_memory $a 32 $v }
proc busywait {ms} {
    set t0 [clock milliseconds]
    while {[expr {[rd 0x4002200C] & 1}]} {
        if {[clock milliseconds] - $t0 > $ms} { error "BUSY still set after $ms ms" }
        after 20
    }
    return [rd 0x4002200C]
}
echo [format "before: OB 0x%08X  0x1FFFF800 0x%08X  0x1FFFF810 0x%08X" [rd 0x4002201C] [rd 0x1FFFF800] [rd 0x1FFFF810]]
# accepted states: as dumped, or all 0xFF (an option erase done by an interrupted earlier run)
set o0 [rd 0x1FFFF800]; set o4 [rd 0x1FFFF810]
if {!(($o0 == 0x00FF00FF && $o4 == 0x00FFFF00) || ($o0 == 0xFFFFFFFF && $o4 == 0xFFFFFFFF))} { echo "option bytes not as dumped: stop"; shutdown error }
# stop the independent watchdog while the core is halted (DBG_CTRL 0xE0042004 bit 8 IWDG_STOP; V1.1
# starts it with a period of about 1 s), then halt the core
wr 0xE0042004 [expr {[rd 0xE0042004] | 0x100}]
wr 0xE000EDF0 0xA05F0003
after 50
set h [rd 0xE000EDF0]
echo [format "DBG_CTRL 0x%08X DHCSR 0x%08X" [rd 0xE0042004] $h]
if {!($h & 0x20000)} { echo "core not halted: stop"; shutdown error }
busywait 1000
wr 0x40022004 0x45670123
wr 0x40022004 0xCDEF89AB
wr 0x40022008 0x45670123
wr 0x40022008 0xCDEF89AB
set c [rd 0x40022010]
echo [format "CTRL after keys 0x%08X" $c]
if {($c & 0x80) || !($c & 0x200)} { echo "unlock failed (LOCK set or OPTWE clear): stop, nothing erased"; shutdown error }
wr 0x4002200C 0xFC
wr 0x40022010 0x220
wr 0x40022010 0x260
set s [busywait 5000]
echo [format "option erase done: STS 0x%08X  0x1FFFF800 0x%08X" $s [rd 0x1FFFF800]]
if {($s & 0x5C) || [rd 0x1FFFF800] != 0xFFFFFFFF} { wr 0x40022010 0x80; echo "option erase not verified: stop before programming"; shutdown error }
wr 0x40022010 0x200
wr 0x4002200C 0xFC
wr 0x40022010 0x210
wr 0x1FFFF800 0x00FF00A5
set s [busywait 60000]
wr 0x40022010 0x80
set o0 [rd 0x1FFFF800]
echo [format "RDP written: STS 0x%08X  0x1FFFF800 0x%08X (expect 0x00FF5AA5)" $s $o0]
if {($s & 0x5C) || $o0 != 0x00FF5AA5} { echo "RDP word not as expected: do not reset; investigate"; shutdown error }
echo "now reset the chip (power cycle or AIRCR) to load L0; then swd/program.tcl"
shutdown
