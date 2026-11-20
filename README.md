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
| Starter | [`starter/`](starter/) | First stage of the two-part bootloader, flash page 0 (1064 bytes). It holds the power latch, reads the control records and starts one of three bootloader slots (factory F, A, B): an installed slot is first recorded as on trial, a slot that never confirmed is replaced by the newest confirmed one, and slot F is the fallback. Every slot is checked (header, CRC-32 of the image, vector table) before it is started; every record it writes is read back. The emulator test covers every record state, bad headers, a full record page and a power cut after every single flash operation. |
| Bootloader port | [`bootloader/`](bootloader/) | The vendor bootloader (USB update drive, flash programming, start of the application) in symbolic assembly, 208 functions in nine source files plus the vector table and the data, every function commented. Linked at 0x08000000 it reproduces the vendor bootloader byte for byte (`make check`); it is the base of the slot bootloader. Its three larger data blocks come from your own meter's flash: `make vendor-data DUMP=<your 0x08000000 dump>`. |
| Slot bootloader | [`bootloader/`](bootloader/) (`make slot`) | The port built for the three slots F, A and B: linked for its slot with its own vector table, the packed RAM image typed with symbols, the confirmation records of the starter, a flash gate inside the erase and program routines (application area and record pages only), checks of the application's vector table before it is started, and its own update path: UF2 (each 512-byte block names its address, so host write order, cluster layout and extra files do not matter; the application's vector page is written last and only after the rest is verified, so an interrupted update leaves the meter in update mode). `tools/bin2uf2.py` converts a `.bin`, `tools/iap_write.py` writes the `.uf2` to the drive. |
| Tests | [`tests/`](tests/) | Emulator tests of the whole chain (starter, slot, application start; records, faults, power cuts after every record write) and of the UF2 path (any block order, junk, repeated and foreign blocks, flash errors, power cuts), and a static never-brick check of every image (no option-byte or protection register, nothing in the settings page, flash-controller access only in the listed routines). |

The two-part bootloader runs on a meter: installed over SWD (`swd/install_bootloader.tcl`,
`tools/make_install.py`), started the vendor application through slot A and confirmed it, and the
vendor bootloader pages were erased.

The application is ported too: [`firmware/`](firmware/) holds the vendor application V1.1 in
assembly, 1107 functions in 46 source files plus the vector table and the fixed data, every
function commented. `make check` rebuilds it byte for byte (309080 bytes). Its fonts, pictures and
the packed initial RAM image are not part of this repository; `make vendor-data
IMAGE=<LC1020E_V1.1_250702.bin>` copies them out of your own copy of the vendor update file (each
block checked by SHA-256, `firmware/vendor_blobs.tsv`). What follows: our own build on this base
(the fixed settings save, USB control with a full API for a companion application, the vendor
defects fixed).

## Start here

[GUIDE.md](GUIDE.md) takes you through the wiring, the backup, the removal of the read protection,
the restore and the installation of the two-part bootloader, with the output to expect at every
step.

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

    bootloader/  bootloader port and slot build: src/, link*.ld, Makefile (vendor-data, check, slot)
    dumper/      sram_dumper.s, Makefile, test_sram_dumper.py, check_dump.py
    firmware/    application port: src/, link.ld, link_units.ld, link_rodata.ld, Makefile
                 (vendor-data, check, uf2), vendor_blobs.tsv
    starter/     starter.s, Makefile, test_starter.py
    swd/         OpenOCD scripts and the probe configuration
    tests/       emulator chain and UF2 tests, chip model, never-brick check
    tools/       update-drive writer, root helper, UF2 converter, slot header and image builders
    GUIDE.md     step-by-step procedure

`build/` and `dumps/` (your backups and the images built from them) and `vendor/` (the vendor
application, which you download yourself) are created by you and never committed.

## License

Non-commercial, see [LICENSE](LICENSE). Not affiliated with FNIRSI.
