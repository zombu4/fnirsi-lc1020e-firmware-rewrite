# program.tcl - after L1 -> L0 (swd/unprotect.tcl and a reset): write the dumped images back over SWD
# and read them back for verification (GUIDE.md section 8).
# Images (built by tools/make_restore.py into build/restore/): boot_08000000.bin (the vendor
# bootloader dump up to its last non-0xFF word), app_08006000.bin (vendor V1.1 file),
# settings_0807F000.bin (the settings / calibration dump, 0xC14 bytes). Every size is a multiple of 4
# (main flash takes 32-bit writes only, manual 3.2.1.4.2).
# Steps: IWDG_STOP (DBG_CTRL bit 8), halt the core (checked); latch the power (PA8, as the dumper); refuse unless FLASH_OB shows L0 (bit 1
# clear) and every target word reads 0xFFFFFFFF (mass-erased); unlock FLASH_KEY; CTRL = PG; load the
# three images; CTRL = LOCK; check STS for PGERR / WRPERR; read the three regions back into
# build/restore/readback_*.bin (compared by tools/make_restore.py --check).
# Usage: cd swd && DAP_HOST=<probe-ip> DAP_PORT=4441 openocd -f probe-cmsis-dap-tcp.cfg -f program.tcl
swd newdap chip cpu -enable
dap create chip.dap -chain-position chip.cpu
target create chip.mem mem_ap -dap chip.dap -ap-num 0
init
set d ../build/restore
proc rd {a} { return [lindex [chip.mem read_memory $a 32 1] 0] }
proc wr {a v} { chip.mem write_memory $a 32 $v }
wr 0xE0042004 [expr {[rd 0xE0042004] | 0x100}]
wr 0xE000EDF0 0xA05F0003
after 50
if {!([rd 0xE000EDF0] & 0x20000)} { echo "core not halted: stop"; shutdown error }
wr 0x40021018 [expr {[rd 0x40021018] | 4}]
wr 0x40010810 0x100
wr 0x40010804 [expr {([rd 0x40010804] & ~0xF) | 2}]
echo [format "halted DHCSR 0x%08X, latched PH_CFG 0x%08X, FLASH_OB 0x%08X" [rd 0xE000EDF0] [rd 0x40010804] [rd 0x4002201C]]
if {[rd 0x4002201C] & 2} { echo "read protection still L1: stop"; shutdown error }
set images [list [list $d/boot_08000000.bin 0x08000000] [list $d/app_08006000.bin 0x08006000] [list $d/settings_0807F000.bin 0x0807F000]]
foreach im $images {
    lassign $im f a
    set n [expr {[file size $f] / 4}]
    for {set i 0} {$i < $n} {incr i 4096} {
        set k [expr {$n - $i}]
        if {$k > 4096} { set k 4096 }
        foreach x [chip.mem read_memory [expr {$a + 4 * $i}] 32 $k] {
            if {$x != 0xFFFFFFFF} { echo [format "not erased at %s: stop" $f]; shutdown error }
        }
    }
}
echo "all target areas erased"
while {[rd 0x4002200C] & 1} { after 10 }
wr 0x40022004 0x45670123
wr 0x40022004 0xCDEF89AB
if {[rd 0x40022010] & 0x80} { echo "FLASH_KEY unlock failed: stop"; shutdown error }
wr 0x4002200C 0xFC
wr 0x40022010 0x1
foreach im $images {
    lassign $im f a
    load_image $f $a bin
    while {[rd 0x4002200C] & 1} { after 10 }
    set s [rd 0x4002200C]
    echo [format "%s at 0x%08X: STS 0x%08X" $f $a $s]
    if {$s & 0x9C} { wr 0x40022010 0x80; echo "programming error: stop"; shutdown error }
}
wr 0x40022010 0x80
foreach im $images {
    lassign $im f a
    dump_image $d/readback_[file tail $f] $a [file size $f]
}
echo "programmed and read back"
shutdown
