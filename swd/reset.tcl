# reset.tcl - system reset of the meter over SWD: one write of 0x05FA0004 (VECTKEY | SYSRESETREQ) to AIRCR 0xE000ED0C through a mem_ap target.
# The core is not halted or examined; no flash, option byte or flash-controller register is written.
# Usage: cd swd && DAP_HOST=<probe-ip> DAP_PORT=4441 openocd -f probe-cmsis-dap-tcp.cfg -f reset.tcl
swd newdap chip cpu -enable
dap create chip.dap -chain-position chip.cpu
target create chip.mem mem_ap -dap chip.dap -ap-num 0
init
echo [format "before: DHCSR 0x%08X" [lindex [chip.mem read_memory 0xE000EDF0 32 1] 0]]
catch {chip.mem write_memory 0xE000ED0C 32 0x05FA0004} err
echo "AIRCR write done ($err)"
shutdown
