# read_dump.tcl - read the SRAM copies made by dumper/sram_dumper.bin (GUIDE.md section 6).
# Only a mem_ap target is created: reads go through the AHB access port, the core is never
# halted, reset or examined, and nothing is written.  Output directory: env DUMP_DIR.
# Usage: cd swd && DAP_HOST=<probe-ip> DAP_PORT=4441 DUMP_DIR=../dumps/run1 openocd -f probe-cmsis-dap-tcp.cfg -f read_dump.tcl
swd newdap chip cpu -enable
dap create chip.dap -chain-position chip.cpu
target create chip.mem mem_ap -dap chip.dap -ap-num 0
init
set d $::env(DUMP_DIR)
set r [chip.mem read_memory 0x2001F000 32 12]
echo [format "result: magic 0x%08X crc boot 0x%08X crc high 0x%08X crc update 0x%08X heartbeat %d" \
    [lindex $r 0] [lindex $r 1] [lindex $r 2] [lindex $r 3] [lindex $r 4]]
if {[lindex $r 0] != 0x504D5544} {
    echo "result word is not DUMP: nothing read"
    shutdown error
}
dump_image $d/result.bin 0x2001F000 0x40
dump_image $d/boot_08000000.bin 0x20001000 0x6000
dump_image $d/high_08068000.bin 0x20007000 0x18000
set h [chip.mem read_memory 0x2001F010 32 1]
echo [format "heartbeat after the reads %d (still counting = dumper running from SRAM)" [lindex $h 0]]
foreach {name addr} {FLASH_OBR 0x4002201C FLASH_WRP 0x40022020 OPT0 0x1FFFF800 OPT1 0x1FFFF804 OPT2 0x1FFFF808 OPT3 0x1FFFF80C OPT4 0x1FFFF810} {
    if {[catch {set v [chip.mem read_memory $addr 32 1]} err]} { echo "$name $addr: error $err" } else { echo [format "%s %s = 0x%08X" $name $addr [lindex $v 0]] }
}
shutdown
