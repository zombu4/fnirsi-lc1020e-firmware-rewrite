# install_bootloader.tcl - write the two-part bootloader over SWD (read protection must be off, L0).
#
# Images from tools/make_install.py in build/install/: BOOT_F.bin (slot F, 0x08069000), BOOT_A.bin
# (slot A, 0x0806F000), record.bin (first control record, 0x08068000), STARTER.bin (page 0).
# Order, so that a cut at any point leaves either the old start code or a complete new chain:
#   STAGE=slots   erase the record pages and the two slots, program slot F, slot A and the record,
#                 read them back into build/install/readback_*.bin (page 0 is not touched);
#   STAGE=starter after `tools/make_install.py --check` reported the slots identical: erase page 0,
#                 program the starter, read it back;
#   STAGE=clean   after the chain has started the application through slot A (an OK record for
#                 slot A in the record pages) and page 0 holds STARTER.bin: erase the pages of the
#                 vendor bootloader 0x08000800..0x08005FFF and check that they read 0xFF.
# Every erase and program address is checked against the list above before it is used; nothing at
# or above 0x0807F000 (settings / calibration) and no option byte is ever addressed. The core is
# halted with the watchdog stopped (DBG_CTRL bit 8) and the power latch PA8 is held (as program.tcl).
# Usage: cd swd && DAP_HOST=<probe-ip> DAP_PORT=4441 STAGE=slots openocd -f probe-cmsis-dap-tcp.cfg -f install_bootloader.tcl
swd newdap chip cpu -enable
dap create chip.dap -chain-position chip.cpu
target create chip.mem mem_ap -dap chip.dap -ap-num 0
init
set d ../build/install
set stage $::env(STAGE)
proc rd {a} { return [lindex [chip.mem read_memory $a 32 1] 0] }
proc wr {a v} { chip.mem write_memory $a 32 $v }
proc busy {} { while {[rd 0x4002200C] & 1} { after 2 } }
proc allowed {a} {
    # page-aligned erase / program targets of this script only
    if {$a >= 0x08068000 && $a < 0x08075000} { return 1 }
    if {$a >= 0x08000000 && $a < 0x08000800 && $::stage eq "starter"} { return 1 }
    if {$a >= 0x08000800 && $a < 0x08006000 && $::stage eq "clean"} { return 1 }
    return 0
}
proc erase_pages {from to} {
    for {set a $from} {$a < $to} {incr a 0x800} {
        if {![allowed $a]} { echo [format "refused erase 0x%08X" $a]; shutdown error }
        busy
        wr 0x40022010 0x2
        wr 0x40022014 $a
        wr 0x40022010 0x42
        busy
        set s [rd 0x4002200C]
        if {$s & 0x5C} { echo [format "erase error at 0x%08X STS 0x%08X" $a $s]; shutdown error }
        wr 0x4002200C 0xFC
    }
    wr 0x40022010 0x0
}
proc program {f a} {
    set end [expr {$a + [file size $f]}]
    if {![allowed $a] || ![allowed [expr {$end - 1}]]} { echo [format "refused program %s at 0x%08X" $f $a]; shutdown error }
    wr 0x40022010 0x1
    load_image $f $a bin
    busy
    set s [rd 0x4002200C]
    wr 0x40022010 0x0
    if {$s & 0x9C} { echo [format "program error %s STS 0x%08X" $f $s]; shutdown error }
    echo [format "programmed %s at 0x%08X (%d bytes)" $f $a [file size $f]]
}
if {$stage ne "slots" && $stage ne "starter" && $stage ne "clean"} { echo "STAGE must be slots, starter or clean"; shutdown error }
if {[rd 0x4002201C] & 2} { echo "read protection is on (L1): stop"; shutdown error }
wr 0xE0042004 [expr {[rd 0xE0042004] | 0x100}]
wr 0xE000EDF0 0xA05F0003
after 50
if {!([rd 0xE000EDF0] & 0x20000)} { echo "core not halted: stop"; shutdown error }
wr 0x40021018 [expr {[rd 0x40021018] | 4}]
wr 0x40010810 0x100
wr 0x40010804 [expr {([rd 0x40010804] & ~0xF) | 3}]
busy
wr 0x40022004 0x45670123
wr 0x40022004 0xCDEF89AB
if {[rd 0x40022010] & 0x80} { echo "FLASH_KEY unlock failed: stop"; shutdown error }
wr 0x4002200C 0xFC
if {$stage eq "slots"} {
    erase_pages 0x08068000 0x08075000
    program $d/BOOT_F.bin 0x08069000
    program $d/BOOT_A.bin 0x0806F000
    program $d/record.bin 0x08068000
    wr 0x40022010 0x80
    foreach {f a} [list BOOT_F.bin 0x08069000 BOOT_A.bin 0x0806F000 record.bin 0x08068000] {
        dump_image $d/readback_$f $a [file size $d/$f]
    }
} elseif {$stage eq "clean"} {
    # page 0 must hold the starter, the records an OK cell for slot A (word 0 0x4C520103)
    set n [expr {[file size $d/STARTER.bin] / 4}]
    set fh [open $d/STARTER.bin rb]; binary scan [read $fh] i* img; close $fh
    set fl [chip.mem read_memory 0x08000000 32 $n]
    for {set i 0} {$i < $n} {incr i} {
        if {([lindex $img $i] & 0xFFFFFFFF) != [lindex $fl $i]} { echo "page 0 is not STARTER.bin: stop"; shutdown error }
    }
    set ok 0
    foreach w [chip.mem read_memory 0x08068000 32 1024] {
        if {$w == 0x4C520103} { set ok 1 }
    }
    if {!$ok} { echo "no OK record for slot A: stop"; shutdown error }
    erase_pages 0x08000800 0x08006000
    wr 0x40022010 0x80
    for {set a 0x08000800} {$a < 0x08006000} {incr a 0x800} {
        foreach w [chip.mem read_memory $a 32 512] {
            if {$w != 0xFFFFFFFF} { echo [format "page 0x%08X not erased: stop" $a]; shutdown error }
        }
    }
    echo "0x08000800..0x08005FFF erased and read 0xFF"
} else {
    erase_pages 0x08000000 0x08000800
    program $d/STARTER.bin 0x08000000
    wr 0x40022010 0x80
    dump_image $d/readback_STARTER.bin 0x08000000 [file size $d/STARTER.bin]
}
echo "stage $stage done; check with tools/make_install.py --check"
shutdown
