# FNIRSI LC1020E firmware rewrite

Firmware work for the **FNIRSI LC1020E** LCR meter. Its microcontroller is a Nations Technologies
**N32G455** (Arm Cortex-M4F, 512 KiB flash, 144 KiB SRAM). The firmware is written in native
**Thumb-2 assembly**.

The vendor firmware leaves the chip's flash **read protection (level 1)** on. While it is on, a
debugger cannot read the flash, and the first pages of flash, which hold the vendor bootloader,
cannot be replaced. Getting past that costs the whole flash contents, so everything the meter
holds has to be backed up first. This repository contains the tools for exactly that.

## Status

What exists now:

| Part | Folder | What it does |
|---|---|---|
| SRAM dumper | [`dumper/`](dumper/) | Assembly program, installed through the vendor update drive. It copies the vendor bootloader, the drive and settings area (which holds the calibration) and the option bytes into SRAM, stores a CRC-32 of each flash part, and then runs from SRAM so that a debugger can read the copies. An emulator test and a checker for the dump are included. |
| SWD tools | [`swd/`](swd/) | OpenOCD scripts: identify the chip, back up the flash under read protection through the halted CPU (`cpu_read.tcl`) or read the dumper's copies (`read_dump.tcl`), remove the read protection (`unprotect.tcl`), write the backup back and read it back (`program.tcl`), reset (`reset.tcl`). |
| Update-drive installer | [`tools/`](tools/) | `iap_write.py` installs an image through the vendor bootloader's USB update drive (macOS), `make_restore.py` builds and checks the images `program.tcl` writes. |
| Starter | [`starter/`](starter/) | First stage of the two-part bootloader, flash page 0 (1020 bytes). It holds the power latch, reads the control records and starts one of three bootloader slots (factory F, A, B): an installed slot is first recorded as on trial, a slot that never confirmed is replaced by the newest confirmed one, and slot F is the fallback. Every slot is checked (header, CRC-32 of the image, vector table) before it is started. The emulator test covers every record state, bad headers, a full record page and a power cut after every single flash operation. |

What follows, in this order: the port of the vendor bootloader as the slot bootloader, the
installation of the two-part bootloader, then the application.

## Start here

[GUIDE.md](GUIDE.md) takes you through the wiring, the backup, the removal of the read protection
and the restore, with the output to expect at every step.

**Read the warnings at the top of the guide first.** Removing the read protection is irreversible
and erases the meter's flash; without a verified backup the meter's settings and calibration are
lost.

## Build and test

    make -C dumper && make -C starter               # needs binutils for arm-none-eabi
    python3 -m venv venv && venv/bin/pip install unicorn
    venv/bin/python -I dumper/test_sram_dumper.py dumper/sram_dumper.bin   # "16 checks, 0 failed"
    venv/bin/python -I starter/test_starter.py starter/build/starter.elf   # "14 tests, 0 failed"

A GitHub Actions workflow ([`.github/workflows/build.yml`](.github/workflows/build.yml)) does the
same on every push.

## Repository layout

    dumper/   sram_dumper.s, Makefile, test_sram_dumper.py, check_dump.py
    starter/  starter.s, Makefile, test_starter.py
    swd/      OpenOCD scripts and the probe configuration
    tools/    update-drive installer, root helper, restore-image builder
    GUIDE.md  step-by-step procedure

`build/` and `dumps/` (your backups and the images built from them) and `vendor/` (the vendor
application, which you download yourself) are created by you and never committed.

## License

Non-commercial, see [LICENSE](LICENSE). Not affiliated with FNIRSI.
