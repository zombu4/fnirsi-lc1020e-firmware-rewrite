# read_sram.tcl - read-only copy of SRAM 0x20000000..+SRAM_LEN (default 0x8000) to SRAM_OUT, through a
# mem_ap target (core not halted, reset or examined; nothing written). Shows the state of the
# vendor bootloader's SRAM, e.g. during an update.
# Usage: cd swd && DAP_HOST=<probe-ip> DAP_PORT=4441 SRAM_OUT=../dumps/x.bin openocd -f probe-cmsis-dap-tcp.cfg -f read_sram.tcl
swd newdap chip cpu -enable
dap create chip.dap -chain-position chip.cpu
target create chip.mem mem_ap -dap chip.dap -ap-num 0
init
set len 0x8000
if {[info exists ::env(SRAM_LEN)]} { set len $::env(SRAM_LEN) }
dump_image $::env(SRAM_OUT) 0x20000000 $len
echo [format "DHCSR 0x%08X" [lindex [chip.mem read_memory 0xE000EDF0 32 1] 0]]
shutdown
