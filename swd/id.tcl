# id.tcl - read-only identification over SWD: debug port ID, access port ID, and a few ID words read
# through the memory access port (no target created: the core is never halted or reset).
swd newdap chip cpu -enable
dap create chip.dap -chain-position chip.cpu
init
echo "DPIDR [chip.dap dpreg 0x0]"
echo "AP0 IDR [chip.dap apreg 0 0xfc]"
proc rd {addr} {
    chip.dap apreg 0 0x0 0x23000002
    chip.dap apreg 0 0x4 $addr
    return [chip.dap apreg 0 0xc]
}
foreach {name addr} {CPUID 0xE000ED00 DBGMCU_IDCODE 0xE0042000 ROM_PID0 0xE00FFFE0 ROM_PID1 0xE00FFFE4 ROM_PID2 0xE00FFFE8 ROM_PID4 0xE00FFFD0 FLASHSIZE 0x1FFFF7E0 UID0 0x1FFFF7E8 FLASH_OBR 0x4002201C} {
    if {[catch {set v [rd $addr]} err]} { echo "$name $addr: error $err" } else { echo "$name $addr = $v" }
}
shutdown
