# Guide: back up, unprotect and restore the LC1020E flash over SWD

This guide takes a FNIRSI LC1020E (N32G455) from the vendor firmware with flash read protection on
to the same vendor firmware with read protection off, with a verified backup in between. After it,
the chip can be written freely over the SWD header.

## 1. Read this first

- **Step 7 is irreversible.** Removing the read protection (level 1 to level 0) makes the chip erase
  its **whole main flash**: the vendor bootloader (0x08000000), the vendor application (0x08006000)
  and the settings page (0x0807F000), which holds the meter's settings and calibration. User manual
  V3.5.0, p.58. Without a verified backup these are gone.
- Do not run step 7 until step 5 or 6 has ended with its success lines, **and** `make_restore.py`
  (step 8, first command) has built the images without complaint.
- **Never write the option bytes at 0x1FFFF810.** They hold the level 2 protection (RDP2 0xCC /
  nRDP2 0x33), which cannot be undone and locks SWD out for good. The scripts never write there.
- On the blank chip (between steps 7 and 8) the meter has no code to keep its power on. **Hold the
  power key** from the reset until step 8 has finished, or SWD stops answering.
- Back up the unit you flash. The settings page and the calibration are individual to each meter.
- You do this at your own risk (see [LICENSE](LICENSE)).

## 2. What you need

- A CMSIS-DAP probe with SWD (a USB probe, or an ESP32 running a CMSIS-DAP TCP firmware).
- [OpenOCD](https://openocd.org/) with CMSIS-DAP support. Scripts that use the probe over TCP take
  its address from the environment: `DAP_HOST=<probe-ip>` and `DAP_PORT` (default 4441); see
  `swd/probe-cmsis-dap-tcp.cfg`. For a USB probe, replace `-f probe-cmsis-dap-tcp.cfg` in every
  command below with `-f interface/cmsis-dap.cfg -c "transport select swd"`.
- Python 3. For the dumper route also the Arm binutils (`arm-none-eabi-as`, `-ld`, `-objcopy`),
  `make`, and on macOS `sudo` for the update-drive helper (step 6).
- The vendor application `LC1020E_V1.1_250702.bin` from FNIRSI's download page, in `vendor/`.
  `tools/make_restore.py` writes that file back, so it must be the version the meter runs.

All commands run from the repository root unless a `cd` is shown. Your backups go in `dumps/`, the
images built from them in `build/`; both are git-ignored.

## 3. Wiring

Solder or clip three wires to the SWD pads on the board:

| Probe | Meter |
|---|---|
| SWCLK (ESP32 GPIO22) | SWCLK |
| SWDIO (ESP32 GPIO23) | SWDIO |
| GND | GND |

The probe's NRST (ESP32 GPIO17) is only needed if the board brings out the MCU's reset pin; the
scripts reset through the debug port. **Join only the grounds**, never the 3.3 V supplies of probe
and meter. Both sides are assumed to use 3.3 V logic; check yours.

## 4. Identify the chip (read-only)

    cd swd
    DAP_HOST=<probe-ip> DAP_PORT=4441 openocd -f probe-cmsis-dap-tcp.cfg -f id.tcl

Switch the meter on first. `id.tcl` creates no target, so the core is neither halted nor reset.
Expected values (seen on an LC1020E running the vendor firmware; the script prints each in
OpenOCD's number format):

    DPIDR 0x2BA01477
    AP0 IDR 0x24770011
    CPUID 0xE000ED00 = 0x410FC241
    DBGMCU_IDCODE 0xE0042000 = 0x8F584511
    FLASH_OBR 0x4002201C = 0x03FFFFFE

`FLASH_OBR` bit 1 set means read protection level 1 is on. If DPIDR does not appear, check the
wiring before doing anything else.

## 5. Backup with the halted CPU (`cpu_read.tcl`)

Under level 1 the debugger cannot read flash, but a stepped CPU can: the script halts the core at
the bootloader's reset vector and executes one load instruction of the vendor bootloader
(0x080025A6, `ldr r1, [r0]`) per word.

Save the settings copy kept in RAM first, with the meter running normally (it is compared with the
flash copy later):

    cd swd
    DAP_HOST=<probe-ip> DAP_PORT=4441 SRAM_OUT=../dumps/sram_run.bin SRAM_LEN=0x2000 \
        openocd -f probe-cmsis-dap-tcp.cfg -f read_sram.tcl
    cd .. && dd if=dumps/sram_run.bin of=dumps/settings_ram_2000057C.bin bs=1 skip=$((0x57C)) count=$((0xC14))

Then read the bootloader and the drive-and-settings area, twice:

    mkdir -p dumps/read1 dumps/read2
    cd swd
    for n in 1 2; do
      DAP_HOST=<probe-ip> DAP_PORT=4441 READ_OUT=../dumps/read$n/boot_08000000.bin \
          READ_ADDR=0x08000000 READ_LEN=0x6000 openocd -f probe-cmsis-dap-tcp.cfg -f cpu_read.tcl
      DAP_HOST=<probe-ip> DAP_PORT=4441 READ_OUT=../dumps/read$n/high_08068000.bin \
          READ_ADDR=0x08068000 READ_LEN=0x18000 openocd -f probe-cmsis-dap-tcp.cfg -f cpu_read.tcl
    done
    cd ..
    cmp dumps/read1/boot_08000000.bin dumps/read2/boot_08000000.bin && echo boot identical
    cmp dumps/read1/high_08068000.bin dumps/read2/high_08068000.bin && echo high identical

**Hold the power key** until the first run prints `latched`: the reset releases the power latch
(PA8) and the script then sets it itself. Later runs find the core halted and skip the reset
(`core already halted: no reset`). Expected lines of every run:

    latched: GPIOA PH_CFG 0x........ POD 0x........
    self-check: 0x08000000 = 0x20002028, 0x08000004 = 0x080001B9
    read 0x6000 bytes from 0x08000000 to ../dumps/read1/boot_08000000.bin

If the self-check line differs, the script reads nothing: your bootloader is not the one this
procedure was written against; stop and do not continue to step 7. Then derive the files step 8
expects (the settings page is the last 0x1000 bytes of the area, 0x0807F000..0x0807FFFF; step 8
checks that only its first 0xC14 bytes hold data and that the rest is 0xFF):

    cp dumps/read1/boot_08000000.bin dumps/boot_08000000_a.bin
    cp dumps/read2/boot_08000000.bin dumps/boot_08000000_b.bin
    for s in a b; do n=$([ $s = a ] && echo 1 || echo 2)
      dd if=dumps/read$n/high_08068000.bin of=dumps/settings_0807F000_$s.bin bs=1 skip=$((0x17000)) count=$((0x1000))
    done

## 6. Backup with the dumper (alternative to step 5)

The dumper is a small program that the vendor bootloader installs and starts like an application.
Started normally, user code from main flash may read the protected flash. The dumper copies the
flash parts to SRAM and then runs from SRAM, so the debugger can read the copies without stopping
it. Its source documents the SRAM layout and the registers it uses.

1. Build and test it:

       make -C dumper
       python3 -m venv venv && venv/bin/pip install unicorn
       venv/bin/python -I dumper/test_sram_dumper.py dumper/sram_dumper.bin     # 16 checks, 0 failed

2. Save the RAM copy of the settings as in step 5 (`read_sram.tcl`, `dd`) **before** installing.
3. Install it. No OpenOCD session may be running (level 1 allows flash reads only in non-debugging
   mode). Switch the meter off, hold UP and press power: the update drive `LC1020E-IAP` appears.
   One-time on macOS: `sudo sh tools/install_sudo_rule.sh` (a root helper for raw access to that
   drive; the sudoers rule names only that copy). Then:

       python3 -I tools/iap_write.py dumper/sram_dumper.bin

   Always use this script and not Finder or `cp`: a stray file on the drive (such as `._name`)
   leaves the meter in the bootloader. The meter then starts the dumper: blank screen, power
   latched.
4. Read twice:

       mkdir -p dumps/read1 dumps/read2
       cd swd
       DAP_HOST=<probe-ip> DUMP_DIR=../dumps/read1 openocd -f probe-cmsis-dap-tcp.cfg -f read_dump.tcl
       DAP_HOST=<probe-ip> DUMP_DIR=../dumps/read2 openocd -f probe-cmsis-dap-tcp.cfg -f read_dump.tcl
       cd ..

   The first line reads `result: magic 0x504D5544 ...`; the last lines print the option bytes at
   0x1FFFF800.. and FLASH_OBR. Keep that output: the option bytes are not part of the restore.
5. Check:

       python3 -I dumper/check_dump.py dumps/read1 dumps/read2

   It must end with `ALL OK`: each part's CRC-32 equals the CRC the meter computed from flash, the
   bootloader's vector table is plausible, both settings markers read 0x12345678, and both reads
   are identical.
6. Derive the files step 8 expects:

       cp dumps/read1/boot_08000000.bin dumps/boot_08000000_a.bin
       cp dumps/read2/boot_08000000.bin dumps/boot_08000000_b.bin
       dd if=dumps/read1/high_08068000.bin of=dumps/settings_0807F000_a.bin bs=1 skip=$((0x17000)) count=$((0x1000))
       dd if=dumps/read2/high_08068000.bin of=dumps/settings_0807F000_b.bin bs=1 skip=$((0x17000)) count=$((0x1000))

7. Reinstall the vendor application the same way as in 3:
   `python3 -I tools/iap_write.py vendor/LC1020E_V1.1_250702.bin`.

## 7. Remove the read protection (irreversible)

Preconditions: step 5 or 6 done and verified, and the restore images build (first command of
step 8). `unprotect.tcl` additionally refuses to run unless the option bytes are as expected
(0x1FFFF800 = 0x00FF00FF and 0x1FFFF810 = 0x00FFFF00, or all 0xFF after an interrupted earlier
run).

    cd swd
    DAP_HOST=<probe-ip> DAP_PORT=4441 CONFIRM=L1-TO-L0 openocd -f probe-cmsis-dap-tcp.cfg -f unprotect.tcl

The script stops the watchdog, halts the core, unlocks the flash and option registers, erases the
option block (checked), writes the RDP word 0x00FF00A5, and waits for the automatic mass erase.
Expected last lines:

    RDP written: STS 0x00000020  0x1FFFF800 0x00FF5AA5 (expect 0x00FF5AA5)
    now reset the chip (power cycle or AIRCR) to load L0; then swd/program.tcl

If it stops with any other message, do not reset; the message names the check that failed. Then
reset the chip while **holding the power key**. The core is in lockup on the blank chip, which is
expected; `FLASH_OBR` bit 1 is now clear (level 0).

## 8. Write the backup back

Build the images from your backup (it compares every pair of dumps again and stops on any
difference):

    python3 -I tools/make_restore.py

Expected: three lines, `boot_08000000.bin`, `app_08006000.bin`, `settings_0807F000.bin`, each with
its size and SHA-256. (Run this before step 7 as well, to know the backup is complete.)

With the power key still held:

    cd swd
    DAP_HOST=<probe-ip> DAP_PORT=4441 openocd -f probe-cmsis-dap-tcp.cfg -f program.tcl

`program.tcl` refuses unless the chip is level 0 and every target word reads 0xFFFFFFFF. Expected
lines, with the usual `STS 0x00000020` (end of operation, no error bits) after each image:

    all target areas erased
    ../build/restore/boot_08000000.bin at 0x08000000: STS 0x00000020
    ../build/restore/app_08006000.bin at 0x08006000: STS 0x00000020
    ../build/restore/settings_0807F000.bin at 0x0807F000: STS 0x00000020
    programmed and read back

Then, from the repository root:

    python3 -I tools/make_restore.py --check

It must print `read back identical` for all three images.

## 9. Reset

    cd swd
    DAP_HOST=<probe-ip> DAP_PORT=4441 openocd -f probe-cmsis-dap-tcp.cfg -f reset.tcl

The meter restarts into the vendor bootloader and the vendor application. The meter now stays at
level 0: SWD can read and write its flash at any time.

## 10. Install the two-part bootloader

The starter goes into flash page 0, slots F and A of the bootloader and the first control record
into 0x08068000..0x08074FFF. The settings page 0x0807F000 is never addressed.

Build and test first (README, "Build and test", plus `make -C bootloader slot` and the tests in
`tests/`), then, from the repository root:

    python3 -I tools/make_install.py

Expected: four lines, `STARTER.bin`, `BOOT_F.bin`, `BOOT_A.bin`, `record.bin`, each with its size
and SHA-256. With the meter switched on:

    cd swd
    DAP_HOST=<probe-ip> DAP_PORT=4441 STAGE=slots openocd -f probe-cmsis-dap-tcp.cfg -f install_bootloader.tcl
    cd .. && python3 -I tools/make_install.py --check

`BOOT_F.bin`, `BOOT_A.bin` and `record.bin` must print `read back identical`; `STARTER.bin` prints
`MISMATCH` until the next stage. Page 0 still holds the old start code, so a cut up to here changes
nothing. Then:

    cd swd
    DAP_HOST=<probe-ip> DAP_PORT=4441 STAGE=starter openocd -f probe-cmsis-dap-tcp.cfg -f install_bootloader.tcl
    cd .. && python3 -I tools/make_install.py --check

All four must print `read back identical`. The scripts leave the core halted. Release it (debug
registers DEMCR 0xE000EDFC = 0, DBG_CTRL 0xE0042004 = 0, DHCSR 0xE000EDF0 = 0xA05F0000) rather
than resetting over SWD: a reset drops the power latch. Switch the meter off and on with the power
key. On the first start the starter records slot A as on trial and the slot records it as
confirmed before it starts the application; the application appears as usual.

Check over SWD: VTOR 0xE000ED08 = 0x08006000 and, at 0x08068000, three records of slot A
(word 0 `4C520101`, `4C520102`, `4C520103`). Only then remove the vendor bootloader, which the new
chain never uses:

    cd swd
    DAP_HOST=<probe-ip> DAP_PORT=4441 STAGE=clean openocd -f probe-cmsis-dap-tcp.cfg -f install_bootloader.tcl

It refuses unless page 0 holds the starter and the confirmation record exists, erases
0x08000800..0x08005FFF and prints `0x08000800..0x08005FFF erased and read 0xFF`. Release the core
again and switch the meter off and on. Your backup still holds the vendor bootloader.

To update the application afterwards: hold the up key while switching on, the meter shows the
update drive; convert the image with `tools/bin2uf2.py` and copy it with `tools/iap_write.py`.

## 11. Our application (and older slots)

Our application needs slot bootloader version 2 or later (it keeps the meter on over a restart and
serves the update request of the control channel). `make -C bootloader slot` builds version 3
(version 2 plus bounded clock waits at the start, FEATURES.md "Bootloader"), and section 10 installs
those images, so after section 10 go straight to "Our application" below.

Only a meter whose slots were installed from an older release with version 1 needs the two slot
stages first:

    make -C bootloader slot
    python3 -I tools/make_install.py --stage slot_a
    cd swd
    DAP_HOST=<probe-ip> DAP_PORT=4441 STAGE=slot_a openocd -f probe-cmsis-dap-tcp.cfg -f install_bootloader.tcl
    cd .. && python3 -I tools/make_install.py --check --stage slot_a

Expected: `BOOT_A.bin ... read back identical` and `records      newest INSTALL slot 1 version 3
...`. Release the core as in section 10 and switch the meter off and on. At 0x08068000 three more
records of slot A follow the earlier ones (word 1 = 3, the version). Slot F,
the fallback, follows only now:

    python3 -I tools/make_install.py --stage slot_f
    cd swd
    DAP_HOST=<probe-ip> DAP_PORT=4441 STAGE=slot_f openocd -f probe-cmsis-dap-tcp.cfg -f install_bootloader.tcl
    cd .. && python3 -I tools/make_install.py --check --stage slot_f

`BOOT_F.bin ... read back identical`; release the core.

Our application: `make -C firmware own` builds `firmware/build/own/APP_OWN.uf2`. Switch the meter
off, hold the up key and switch it on until the drive `LC1020E-IAP` appears, then

    python3 -I tools/iap_write.py firmware/build/own/APP_OWN.uf2

The bootloader writes the application's vector page last and restarts into it. The meter appears as
a USB serial device (19F5:1020, "LC1020E"); `python3 -I tools/lc1020e.py info` names slot A and slot
bootloader version 3. Later updates need no key: `python3 -I tools/lc1020e.py update
firmware/build/own/APP_OWN.uf2 --yes` puts the meter into update mode, copies the file and checks
the result (PROTOCOL.md section 13).

A newer slot bootloader goes into the free slot over USB, without SWD (PROTOCOL.md 13.2). With
slot A confirmed and slot B empty, B is the free one (`python3 -I tools/lc1020e.py boot-status`):

    python3 -I tools/lc1020e.py boot-update bootloader/build/slot/BOOT_B.bin --yes

The file is the slot file `make -C bootloader slot` writes (header and image), linked for slot B.
The meter restarts, the starter starts B on trial and B confirms itself; `info` then names slot B
and its version. A slot B that never confirms is replaced by slot A at the next start, as long as
slot A's confirmation is still in the record pages (FEATURES.md "Bootloader": after about 40
bootloader updates the oldest records are erased, and slot F takes A's place).

## 12. Recovery

- **No SWD answer on the blank chip:** hold the power key and retry; the blank chip cannot latch
  its own power.
- **`program.tcl` prints `programming error: stop`:** it has locked the flash again and stopped.
  The chip is level 0 and partly written. Do not remove the backup; the images in `build/restore/`
  are exactly what to write. `program.tcl` only writes into erased words and there is no script in
  this repository yet that erases the flash again, so do not guess: report the output.
- **The meter stays at "Bootloader" after the dumper route:** a stray file is on the update drive.
  Switch the meter off, enter update mode again and use `tools/iap_write.py` with the vendor image.
- **`cpu_read.tcl` self-check failed:** nothing was read and nothing was written; stop, your
  bootloader differs.
- Your backups in `dumps/` are the only copy of the meter's own settings and calibration. Keep
  them.
