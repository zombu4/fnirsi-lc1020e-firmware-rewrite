# trace_boot.tcl - single-step the vendor bootloader from reset and log PC and registers.
# Only debug registers are written: DHCSR (C_DEBUGEN, step),
# DEMCR (TRCENA | VC_CORERESET), DCRSR (register select), AIRCR (system reset); no flash, option
# byte or flash-controller register. At the end debug is switched off and the core is reset to run
# normally. Hold the power key throughout (a reset releases the PA8 power latch).
# Usage: cd swd && DAP_HOST=<probe-ip> DAP_PORT=4441 TRACE_OUT=../dumps/trace.txt TRACE_STEPS=600 \
#        openocd -f probe-cmsis-dap-tcp.cfg -f trace_boot.tcl
swd newdap chip cpu -enable
dap create chip.dap -chain-position chip.cpu
target create chip.mem mem_ap -dap chip.dap -ap-num 0
init
proc rd {a} { return [lindex [chip.mem read_memory $a 32 1] 0] }
proc wr {a v} { chip.mem write_memory $a 32 $v }
proc reg {n} {
    wr 0xE000EDF4 $n
    for {set i 0} {$i < 50} {incr i} { if {[expr {[rd 0xE000EDF0] & 0x10000}]} break }
    return [rd 0xE000EDF8]
}
proc halted {} {
    for {set i 0} {$i < 200} {incr i} { if {[expr {[rd 0xE000EDF0] & 0x20000}]} { return 1 } }
    return 0
}
set f [open $::env(TRACE_OUT) w]
set steps 600
if {[info exists ::env(TRACE_STEPS)]} { set steps $::env(TRACE_STEPS) }
wr 0xE000EDF0 0xA05F0001
wr 0xE000EDFC 0x01000001
catch {wr 0xE000ED0C 0x05FA0004}
after 200
if {![halted]} { puts $f "not halted after reset: DHCSR [format 0x%08X [rd 0xE000EDF0]]"; close $f; shutdown error }
puts $f [format "halted at reset, DHCSR 0x%08X" [rd 0xE000EDF0]]
for {set s 0} {$s < $steps} {incr s} {
    set line [format "%4d pc %08X" $s [reg 15]]
    foreach n {0 1 2 3 4 5 13 14 16} { append line [format " r%d %08X" $n [reg $n]] }
    puts $f $line
    flush $f
    wr 0xE000EDF0 0xA05F000D
    if {![halted]} { puts $f "step $s: did not halt again, DHCSR [format 0x%08X [rd 0xE000EDF0]]"; break }
}
puts $f [format "end: CFSR 0x%08X HFSR 0x%08X" [rd 0xE000ED28] [rd 0xE000ED2C]]
close $f
wr 0xE000EDFC 0x00000000
wr 0xE000EDF0 0xA05F0000
catch {wr 0xE000ED0C 0x05FA0004}
shutdown
