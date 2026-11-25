# Features in detail

What the firmware does and how, part by part. The [README](README.md) has the short version.

## Measurement (`firmware/own/meas.s`)

- Every acquisition covers whole signal periods (the timer and DAC periods are corrected).
- One DFT bin per channel, with its noise estimate.
- A complex average over a window of 1, 2 or 4 readings per second (the manual's speeds), with rules for
  outliers and for a part being changed.
- An acquisition handshake that never uses a buffer re-armed during the reads; the voltage and current
  buffers start on the same conversion (their DMA channels are switched off and on together).
- A settle time after every change, and a wait for a steady DC level after a bias change.
- Saturation and no-reading detection.
- The phase is not folded: a negative R keeps its sign.
- Complex open / short compensation on the measure and compare screens, with the factory resistor
  references kept as breakpoints through it.
- The factory calibration table is protected from the calibration sweep and the menu restore.

## Display and instrument functions (`firmware/own/fmt.s`, `firmware/own/cmp.s`)

- **OL** outside the manual's measurement range, and at 60, 100 and 120 Hz above the 10 Mohm the manual
  specifies there.
- **Amber digits** when the value lies outside the manual's accuracy table.
- **Negative values** shown as the end of the range they point to (no passive part has one): series R,
  parallel C, series L and D as 0; parallel R, series C, parallel L and Q as OL. Beside a C or L shown as
  0, D is OL and Q is 0.
- The sign of X and theta is shown; at most 19,999 counts.
- **AUTO** R / C / L and series / parallel with hysteresis; a secondary picked with its key or over USB
  stays.
- A **hold** that ends at a change of a measurement setting.
- A **60 Hz** test frequency.
- **Compare mode**: judged once per stable insertion with HI / IN / LO, asymmetric and IEC-letter
  tolerances, a secondary limit, a non-blocking beeper, an LED that holds the result, counters that stop
  at 999 and a counter reset key.

## Calibration (`firmware/own/cal.s`, `firmware/own/ocal.s`, `tools/ocal_fit.py`)

- **Open / short sweep**: complete windows only. Each short point is the median of three agreeing
  windows. Each open point is the vector mean of the admittances of up to seven usable windows, kept only
  when it stands out from their scatter (F test at 0.999) and is a lead stray (capacitive, phase +45 ..
  +135 degrees, at most 50 pF); otherwise it is "not resolved" and only the short correction applies
  there.
- The 100 / 120 Hz points that are not resolved take the capacitance of a resolved 1 kHz (else 10 kHz)
  point. A no-reading window is skipped, never a restart. Open points must read at least 100 kohm.
- A host can start and leave a calibration like the meter's menu. The results are stored only after all
  15 points, the settings are put back before the one save, and the dialog shows the progress and the
  reason of a failure.
- **Own calibration area** at 0x08062000..0x08065FFF (two slots, written only by `ocal.s` through the
  settings gate): per-range / per-gain complex gain calibration, clip limits, settle times and a level
  monitor. Commands 0x30..0x37 and event 0x98 (`PROTOCOL.md` 5.7 and 16); host fit `tools/ocal_fit.py`.

## Settings and power (`firmware/own/save.s`, `firmware/own/power.s`, `firmware/own/xtal.s`)

- Settings and calibration are kept in two copies, each read back after writing; a power cut never loses
  both. A save writes nothing when nothing changed, and loaded settings are checked in RAM.
- The vendor's own flash routines are switched off.
- Off Time, the low-voltage power-off and the battery icon kept up to date every 30 s.
- A crystal fault is shown on the display with its repair for 20 s, then a clean power-off, instead of
  the vendor's silent restarts.
- Start-up (`firmware/own/boot.s`): the clock is switched to the internal oscillator and the switch is
  waited for before the PLL is turned off (after a restart the PLL still drives the core); every clock
  wait of the application has a bound, and a PLL that does not lock or switch ends in the crystal-fault
  screen (with the timer clocks of the vendor's crystal-fault start) instead of a hang. The slot
  bootloader, which runs first on every start, bounds its own three clock waits from version 3 on
  (Bootloader, below); a version-2 slot still waits for them without a bound. A progress word in RAM records the last start-up stage reached. A soft restart keeps
  RAM powered and does not reset the chip, so the next start finds the word; after a chip reset that
  keeps the power (watchdog, reset pin) the word is found only if main SRAM keeps its contents through
  it, which the chip's user manual does not state (it names Stop2, Standby and VBAT as losing SRAM; the
  emulator tests assume it is kept); a power loss clears it. INFO reports the word for this start and
  the previous one, with the chip's reset-cause flags, and the last update result stays until an INFO
  answer has been queued for the host.

## Interface (`firmware/own/lang.s`, `firmware/own/logo.s`, `firmware/own/fix.s`)

- English only: the language chooser and the Language menu item are gone; the settings menu has six
  items.
- Start-up logo "FU\*\*NIRSI", composed from pieces of the vendor's own logo pictures.
- Fixes of vendor defects found in the code.

## USB control (`firmware/own/`, [`PROTOCOL.md`](PROTOCOL.md), [`tools/lc1020e.py`](tools/lc1020e.py))

A USB serial port (CDC ACM) with a framed request / answer protocol, events and streams:

- every key, screen, measurement setting and reading; the screen, settings, hold and compare values can
  be set directly, without key presses;
- the compare mode, the menu settings, calibration;
- settings backup and restore, screenshots, memory read;
- restart, power off;
- application updates (the slot bootloader's update drive, entered by command) and bootloader updates
  into the free slot (trial and rollback by the starter).

`PROTOCOL.md` is the specification for companion applications; `tools/lc1020e.py` is a host library
with a command-line tool.

## Bootloader (`starter/`, `bootloader/`)

- **Starter** (flash page 0, 1064 bytes): holds the power latch, reads the control records and starts
  one of three bootloader slots (factory F, A, B). An installed slot is first recorded as on trial, a
  slot that never confirmed is replaced by the newest confirmed one, and slot F is the fallback. Every
  slot is checked (header, CRC-32 of the image, vector table) before it starts; every record it writes
  is read back.
- **Slot bootloader** (`make -C bootloader slot`): the vendor bootloader port built for the three slots,
  with a flash gate inside the erase and program routines (application area and record pages only),
  checks of the application's vector table before it starts, and its own **UF2 update path**. Each
  512-byte block names its address, so host write order, cluster layout and extra files do not matter;
  the application's vector page is written last, after the rest has been written and read back, so an
  interrupted update leaves the meter in update mode.
- **Bounded start-up clock waits** (slot version 3, `bootloader/src/board_02.s`): the switch to the
  internal oscillator, the PLL lock and the switch to the PLL each end after 0x8000 polls. When the
  switch to the internal oscillator does not happen, the PLL keeps running the core and nothing of the
  clock is changed; when the PLL does not lock or switch, the core stays on the internal oscillator
  (the PLL turned off or deselected, the bus prescalers undone once the internal oscillator is seen to
  run the core) and the start goes on: the application
  starts and shows its crystal-fault screen. Update mode is still entered with the key, but USB needs
  the PLL's 48 MHz, so no update is possible on such a meter.
- `tools/bin2uf2.py` converts a `.bin`; `tools/iap_write.py` writes the `.uf2` to the drive.

## The port

- `firmware/`: the vendor application V1.1 in assembly, 1107 functions in 46 source files plus the
  vector table and the fixed data, every function commented. `make check` rebuilds it byte for byte
  (309080 bytes).
- `bootloader/`: the vendor bootloader in assembly, 208 functions in nine source files plus the vector
  table and the data. `make check` rebuilds it byte for byte.
- Our build (`make own`) joins our modules to the port by same-size hooks (`.ifdef OWN`), so `make check`
  still rebuilds V1.1. The code keeps its addresses; the data is packed (every data pointer is a label,
  the Chinese texts, glyphs and pictures are cut out, the initial RAM image is typed out), so the free
  space lies in one block after our image. `tests/check_pack.py` checks every byte against V1.1.
- The fonts, pictures and packed RAM image are not in this repository: `make vendor-data` copies them
  out of your own vendor files (each block checked by SHA-256, `firmware/vendor_blobs.tsv`).

## Backup tools (`dumper/`, `swd/`, `tools/`)

- **SRAM dumper**: an assembly program installed through the vendor update drive. It copies the vendor
  bootloader, the drive and settings area (which holds the calibration) and the option bytes into SRAM,
  stores a CRC-32 of each flash part, and runs from SRAM so that a debugger can read the copies.
- **OpenOCD scripts**: identify the chip, back up the flash under read protection through the halted
  CPU (`cpu_read.tcl`) or read the dumper's copies (`read_dump.tcl`), remove the read protection
  (`unprotect.tcl`), write the backup back and read it back (`program.tcl`), reset (`reset.tcl`).
- `tools/iap_write.py` installs an image through the vendor update drive (macOS); `tools/make_restore.py`
  builds and checks the images `program.tcl` writes.

## Tests (`tests/`)

All run in an emulator of the chip, its USB device and the measurement hardware:

- the whole start chain (starter, slots, application start; records, faults, power cuts after every
  record write, the slot's bounded clock waits) and the UF2 update path (any block order, junk, repeated and foreign blocks, flash
  errors, power cuts);
- a static never-brick check of every image (no option-byte or protection register, nothing in the
  settings page, flash-controller access only in the listed routines);
- the settings save with power cuts (`test_own_save.py`);
- USB control and the start-up (clock order with a strict clock model, the bounded clock waits, the
  progress word and reset flags over a watchdog reset, the kept update result) (`test_own_control.py`);
- the direct changes of screen, measurement settings, hold, menu settings and compare values against
  the meter's own key path, word by word and pixel by pixel (`test_own_dset.py`);
- power-off (`test_own_power.py`) and English only with the reset path (`test_own_lang.py`);
- the measurement core against the vendor build and recomputed from the sampled buffers, with a
  write-watch on the calibration tables in every case (`test_own_measure.py`);
- the display and instrument functions and 60 Hz (`test_own_func.py`);
- the calibration sweep with its aborts, failures and a power-off in the middle (`test_own_cal.py`);
- the open / short compensation and the bias wait (`test_own_comp.py`);
- the own calibration area (`test_own_ocal.py`, `test_ocal_fit.py`);
- the byte check of the packed image (`check_pack.py`).
