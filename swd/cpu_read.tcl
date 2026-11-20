# cpu_read.tcl - read flash words through the halted CPU (read protection L1 blocks the debugger's
# own flash reads, but the stepped CPU still loads flash data: in a single-step trace made with
# swd/trace_boot.tcl the literal load at 0x080025A2 gave r0 = 0xE000ED88).
# Method: reset with vector catch (core halted at the bootloader's reset vector), latch the power
# (PA8 high, as the dumper does), then per word: r0 = address, PC = 0x080025A6 (the bootloader's
# "ldr r1, [r0]", trace step 8 -> 9: r0 0x40021000 -> r1 0x8783), one step, read r1.
# Self-check first: 0x08000000 must give the reset SP 0x20002028 and 0x08000004 the reset vector
# 0x080001B9 (trace step 0: pc 0x080001B8, sp 0x20002028); otherwise nothing is read.
# Writes only debug registers (DHCSR, DEMCR, DCRSR, DCRDR), core registers, AIRCR (reset) and the
# GPIOA / RCC registers of the power latch; no flash, option byte or flash-controller register.
# Procedure and warnings: GUIDE.md section 5.  Hold the power key until the first run prints "latched".
# Usage: cd swd && DAP_HOST=<probe-ip> DAP_PORT=4441 READ_OUT=../dumps/x.bin READ_ADDR=0x0807F000 \
#        READ_LEN=0x1000 openocd -f probe-cmsis-dap-tcp.cfg -f cpu_read.tcl
swd newdap chip cpu -enable
dap create chip.dap -chain-position chip.cpu
target create chip.mem mem_ap -dap chip.dap -ap-num 0
init
proc rd {a} { return [lindex [chip.mem read_memory $a 32 1] 0] }
proc wr {a v} { chip.mem write_memory $a 32 $v }
proc waitbit {m} { for {set i 0} {$i < 200} {incr i} { if {[expr {[rd 0xE000EDF0] & $m}]} { return 1 } }; return 0 }
proc rreg {n} { wr 0xE000EDF4 $n; waitbit 0x10000; return [rd 0xE000EDF8] }
proc wreg {n v} { wr 0xE000EDF8 $v; wr 0xE000EDF4 [expr {0x10000 | $n}]; waitbit 0x10000 }
proc fword {a} {
    wreg 0 $a
    wreg 15 0x080025A6
    wreg 16 0x01000000
    wr 0xE000EDF0 0xA05F000D
    if {![waitbit 0x20000]} { error "no halt after step at [format 0x%08X $a]" }
    return [rreg 1]
}
set out $::env(READ_OUT)
set base $::env(READ_ADDR)
set len $::env(READ_LEN)
# already halted by an earlier run (C_DEBUGEN and S_HALT set): no reset, so the power latch stays
if {([rd 0xE000EDF0] & 0x20001) != 0x20001} {
    wr 0xE000EDF0 0xA05F0001
    wr 0xE000EDFC 0x01000001
    catch {wr 0xE000ED0C 0x05FA0004}
    after 200
    if {![waitbit 0x20000]} { echo "not halted after reset"; shutdown error }
} else { echo "core already halted: no reset" }
# power latch PA8: GPIOA clock, output register high, push-pull output, PMODE 10 = 10 MHz (manual GPIO table)
wr 0x40021018 [expr {[rd 0x40021018] | 4}]
wr 0x40010810 0x100
wr 0x40010804 [expr {([rd 0x40010804] & ~0xF) | 2}]
echo [format "latched: GPIOA PH_CFG 0x%08X POD 0x%08X" [rd 0x40010804] [rd 0x4001080C]]
set w0 [fword 0x08000000]
set w1 [fword 0x08000004]
echo [format "self-check: 0x08000000 = 0x%08X, 0x08000004 = 0x%08X" $w0 $w1]
if {$w0 != 0x20002028 || $w1 != 0x080001B9} { echo "self-check failed: nothing read"; shutdown error }
set f [open $out wb]
set t0 [clock milliseconds]
for {set a $base} {$a < $base + $len} {incr a 4} {
    puts -nonewline $f [binary format i [fword $a]]
    if {($a - $base) % 0x400 == 0} { flush $f; echo [format "0x%08X  %d s" $a [expr {([clock milliseconds] - $t0) / 1000}]] }
}
close $f
echo [format "read 0x%X bytes from 0x%08X to %s" $len $base $out]
shutdown
