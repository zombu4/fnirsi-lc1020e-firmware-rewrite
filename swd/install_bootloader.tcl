# install_bootloader.tcl - write the two-part bootloader over SWD (read protection must be off, L0).
#
# Images from tools/make_install.py in build/install/: BOOT_F.bin (slot F, 0x08069000), BOOT_A.bin
# (slot A, 0x0806F000), record.bin (first control record, 0x08068000), STARTER.bin (page 0).
# First install, in this order, so that a cut at any point leaves either the old start code or a
# complete new chain:
#   STAGE=slots   erase the record pages and the two slots, program slot F, slot A and the record,
#                 read them back into build/install/readback_*.bin (page 0 is not touched);
#   STAGE=starter after `tools/make_install.py --check` reported the slots identical: erase page 0,
#                 program the starter, read it back;
#   STAGE=clean   after the chain has started the application through slot A (an OK record for
#                 slot A in the record pages) and page 0 holds STARTER.bin: erase the pages of the
#                 vendor bootloader 0x08000800..0x08005FFF and check that they read 0xFF.
# Slot updates on an installed chain (page 0 untouched):
#   STAGE=slot_a  BOOT_A.bin of feature version 2 or later (header word +12). Slot F must pass the
#                 starter's header check (every cut below leads to F) and a valid record must
#                 exist; then (1) INSTALL A appended to the records as starter/starter.s
#                 append_record does it, read back, the records scanned again (INSTALL A newest);
#                 (2) slot A erased, programmed, read back into readback_BOOT_A.bin, the record
#                 pages into readback_records.bin. A cut after (1) leaves INSTALL A with a damaged
#                 slot A: its header check fails and the starter starts F; a cut before (1)
#                 changes nothing. Gate: the record pages and slot A only.
#   STAGE=slot_f  BOOT_F.bin of feature version 2 or later; only when the newest record is OK for
#                 slot A with version 2 or later and slot A passes the starter's header check with
#                 that version in its header (the starter then starts A whatever F holds): slot F
#                 erased, programmed, read back into readback_BOOT_F.bin. No record (F is the
#                 fallback, never on trial). A cut leaves F damaged while A is confirmed and runs;
#                 the stage is repeated until F reads back identical. Gate: slot F only.
# Every erase and program address is checked against the gate of the stage before it is used;
# nothing at or above 0x0807F000 (settings / calibration), nothing in 0x08066000..0x08066FFF
# (settings copy B) and no option byte is ever addressed. The core is halted with the watchdog
# stopped (DBG_CTRL bit 8) and the power latch PA8 is held (as program.tcl).
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
    # page-aligned erase / program targets of each stage only
    if {$::stage eq "slots"} { return [expr {$a >= 0x08068000 && $a < 0x08075000}] }
    if {$::stage eq "starter"} { return [expr {$a >= 0x08000000 && $a < 0x08000800}] }
    if {$::stage eq "clean"} { return [expr {$a >= 0x08000800 && $a < 0x08006000}] }
    if {$::stage eq "slot_a"} {
        return [expr {($a >= 0x08068000 && $a < 0x08069000) || ($a >= 0x0806F000 && $a < 0x08075000)}]
    }
    if {$::stage eq "slot_f"} { return [expr {$a >= 0x08069000 && $a < 0x0806F000}] }
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
# one word (record cells): gate, PG, store, wait, PG off, flags checked and cleared
proc program_word {a v} {
    if {![allowed $a]} { echo [format "refused program 0x%08X" $a]; shutdown error }
    busy
    wr 0x40022010 0x1
    wr $a $v
    busy
    set s [rd 0x4002200C]
    wr 0x40022010 0x0
    wr 0x4002200C 0xFC
    if {$s & 0x9C} { echo [format "program error at 0x%08X STS 0x%08X" $a $s]; shutdown error }
}
# n words from a, in reads of at most 4096 words (as program.tcl)
proc read_words {a n} {
    set out {}
    while {$n > 0} {
        set k $n
        if {$k > 4096} { set k 4096 }
        set out [concat $out [chip.mem read_memory $a 32 $k]]
        incr a [expr {4 * $k}]
        incr n [expr {-$k}]
    }
    return $out
}
# the words of a file, unsigned
proc file_words {f} {
    set fh [open $f rb]; binary scan [read $fh] i* w; close $fh
    set out {}
    foreach x $w { lappend out [expr {$x & 0xFFFFFFFF}] }
    return $out
}
# CRC-32 (polynomial 0xEDB88320, reflected, initial and final XOR 0xFFFFFFFF, as starter.s crc32)
# of a list of words, the bytes of each word in memory order (little-endian)
set crctab {}
for {set n 0} {$n < 256} {incr n} {
    set c $n
    for {set k 0} {$k < 8} {incr k} {
        if {$c & 1} { set c [expr {($c >> 1) ^ 0xEDB88320}] } else { set c [expr {$c >> 1}] }
    }
    lappend crctab $c
}
proc crc32_words {words} {
    global crctab
    set c 0xFFFFFFFF
    foreach w $words {
        set w [expr {$w & 0xFFFFFFFF}]
        for {set s 0} {$s < 32} {incr s 8} {
            set c [expr {[lindex $crctab [expr {($c ^ ($w >> $s)) & 0xFF}]] ^ ($c >> 8)}]
        }
    }
    return [expr {$c ^ 0xFFFFFFFF}]
}
# starter.s header_ok: 1 when the slot at base may be started (magic, header CRC, link address =
# base + 0x200, 8 <= length <= 0x5E00 and a multiple of 4, image CRC, SP inside SRAM, reset
# vector odd and inside the image), else 0
proc header_ok {base} {
    set h [read_words $base 8]
    if {[lindex $h 0] != 0x544F4C53} { return 0 }
    if {[crc32_words [lrange $h 0 6]] != [lindex $h 7]} { return 0 }
    set img [expr {$base + 0x200}]
    if {[lindex $h 4] != $img} { return 0 }
    set n [lindex $h 1]
    if {$n < 8 || $n > 0x5E00 || ($n & 3)} { return 0 }
    set w [read_words $img [expr {$n / 4}]]
    if {[crc32_words $w] != [lindex $h 2]} { return 0 }
    set sp [lindex $w 0]
    if {$sp <= 0x20000000 || $sp > 0x20024000} { return 0 }
    set pc [lindex $w 1]
    if {!($pc & 1)} { return 0 }
    set pc [expr {$pc & ~1}]
    if {$pc < $img || $pc >= $img + $n} { return 0 }
    return 1
}
# starter.s scan_records: per slot the newest valid cell (tag 0x4C52 and CRC-32 of words 0..2,
# slot 0..2, state 1..3, highest sequence number, compared unsigned) in rseq / rstate / rver /
# rcell; returns the slot of the newest record over both pages (the lower slot on equal
# sequence numbers, as the starter), or -1 when there is none
proc scan_records {} {
    global rseq rstate rver rcell
    foreach s {0 1 2} { set rseq($s) 0; set rstate($s) 0; set rver($s) 0; set rcell($s) 0 }
    set w [read_words 0x08068000 1024]
    for {set i 0} {$i < 1024} {incr i 4} {
        set w0 [lindex $w $i]
        if {(($w0 >> 16) & 0xFFFF) != 0x4C52} { continue }
        if {[crc32_words [lrange $w $i [expr {$i + 2}]]] != [lindex $w [expr {$i + 3}]]} { continue }
        set slot [expr {($w0 >> 8) & 0xFF}]
        set st [expr {$w0 & 0xFF}]
        if {$slot >= 3 || $st < 1 || $st > 3} { continue }
        set seq [lindex $w [expr {$i + 2}]]
        if {$seq <= $rseq($slot)} { continue }
        set rseq($slot) $seq
        set rstate($slot) $st
        set rver($slot) [lindex $w [expr {$i + 1}]]
        set rcell($slot) [expr {0x08068000 + 4 * $i}]
    }
    set best 0
    set newest -1
    foreach s {0 1 2} { if {$rseq($s) > $best} { set best $rseq($s); set newest $s } }
    return $newest
}
# starter.s append_record (after scan_records found a record): cell = 0x4C52 << 16 | slot << 8 |
# state, version, sequence = highest + 1, CRC-32 of the three; written in the first cell above
# the last cell that is not all 0xFFFFFFFF in the page of the newest record; page full -> the
# other page erased and the record its first cell; read back, on a difference written again
# (three attempts). Returns the cell address, or 0 when all three read back different.
proc append_record {slot state version} {
    global rseq rcell
    set max 0
    set cell 0
    foreach s {0 1 2} { if {$rseq($s) > $max} { set max $rseq($s); set cell $rcell($s) } }
    set c [list [expr {0x4C520000 | ($slot << 8) | $state}] $version [expr {($max + 1) & 0xFFFFFFFF}]]
    lappend c [crc32_words $c]
    set page [expr {$cell & ~0x7FF}]
    for {set try 1} {$try <= 3} {incr try} {
        set w [read_words $page 512]
        set free $page
        for {set i 0} {$i < 512} {incr i 4} {
            set all [expr {[lindex $w $i] & [lindex $w [expr {$i + 1}]] & [lindex $w [expr {$i + 2}]] & [lindex $w [expr {$i + 3}]]}]
            if {$all != 0xFFFFFFFF} { set free [expr {$page + 4 * $i + 16}] }
        }
        if {$free >= $page + 0x800} {
            if {$page == 0x08068000} { set free 0x08068800 } else { set free 0x08068000 }
            erase_pages $free [expr {$free + 0x800}]
        }
        for {set k 0} {$k < 4} {incr k} { program_word [expr {$free + 4 * $k}] [lindex $c $k] }
        set back [read_words $free 4]
        set same 1
        for {set k 0} {$k < 4} {incr k} { if {[lindex $back $k] != [lindex $c $k]} { set same 0 } }
        if {$same} {
            echo [format "record %08X %08X %08X %08X at 0x%08X" [lindex $c 0] [lindex $c 1] [lindex $c 2] [lindex $c 3] $free]
            return $free
        }
        echo [format "record cell 0x%08X read back different (attempt %d of 3)" $free $try]
    }
    return 0
}
# a read-back file of an earlier run is removed before a stage writes a new one
proc drop {f} { if {[file exists $f]} { file delete $f } }
if {$stage ne "slots" && $stage ne "starter" && $stage ne "clean" && $stage ne "slot_a" && $stage ne "slot_f"} {
    echo "STAGE must be slots, starter, clean, slot_a or slot_f"; shutdown error
}
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
} elseif {$stage eq "slot_a"} {
    drop $d/readback_BOOT_A.bin
    drop $d/readback_records.bin
    set ver [lindex [file_words $d/BOOT_A.bin] 3]
    if {$ver < 2} { echo [format "BOOT_A.bin has version %d, not 2 or later: stop" $ver]; shutdown error }
    # (0) slot F as the starter checks it, and a record to append to
    if {![header_ok 0x08069000]} { echo "slot F fails the starter's header check: stop"; shutdown error }
    if {[scan_records] < 0} { echo "no valid record (a first install is STAGE=slots): stop"; shutdown error }
    # (1) INSTALL A (slot 1, state 1) with the version of the new image
    set cell [append_record 1 1 $ver]
    if {$cell == 0} { echo "INSTALL A not written after three attempts (slot A untouched): stop"; shutdown error }
    if {[scan_records] != 1 || $rstate(1) != 1 || $rver(1) != $ver || $rcell(1) != $cell} {
        echo "INSTALL A is not the newest record after the append (slot A untouched): stop"; shutdown error
    }
    # (2) slot A
    erase_pages 0x0806F000 0x08075000
    program $d/BOOT_A.bin 0x0806F000
    wr 0x40022010 0x80
    dump_image $d/readback_BOOT_A.bin 0x0806F000 [file size $d/BOOT_A.bin]
    dump_image $d/readback_records.bin 0x08068000 0x1000
} elseif {$stage eq "slot_f"} {
    drop $d/readback_BOOT_F.bin
    set ver [lindex [file_words $d/BOOT_F.bin] 3]
    if {$ver < 2} { echo [format "BOOT_F.bin has version %d, not 2 or later: stop" $ver]; shutdown error }
    # the starter must start slot A whatever F holds: newest record OK A of version 2 or later,
    # slot A passing the header check with that version in its header word +12
    if {[scan_records] != 1 || $rstate(1) != 3 || $rver(1) < 2} { echo "newest record is not OK A of version 2 or later: stop"; shutdown error }
    if {![header_ok 0x0806F000]} { echo "slot A fails the starter's header check: stop"; shutdown error }
    if {[rd 0x0806F00C] != $rver(1)} { echo "slot A header version differs from its OK record: stop"; shutdown error }
    erase_pages 0x08069000 0x0806F000
    program $d/BOOT_F.bin 0x08069000
    wr 0x40022010 0x80
    dump_image $d/readback_BOOT_F.bin 0x08069000 [file size $d/BOOT_F.bin]
} else {
    erase_pages 0x08000000 0x08000800
    program $d/STARTER.bin 0x08000000
    wr 0x40022010 0x80
    dump_image $d/readback_STARTER.bin 0x08000000 [file size $d/STARTER.bin]
}
echo "stage $stage done; check with tools/make_install.py --check (slot_a / slot_f: --check --stage $stage)"
shutdown
