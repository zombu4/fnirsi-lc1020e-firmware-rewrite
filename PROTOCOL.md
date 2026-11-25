# FNIRSI LC1020E USB control protocol (protocol version 1)

This document specifies the control channel of our firmware for the FNIRSI LC1020E: a USB serial
port (CDC ACM) through which a host reads and controls every function of the meter, reads and
restores its settings and calibration, takes screenshots and updates the application and the slot
bootloader. It is written for authors of companion applications and test tools. The firmware side
is assembly in `firmware/own/` (`ctl.s` frames, keys, events, streams and the command engine,
`cmd.s` the commands and records, `usb.s` the USB driver, `screen.s` the screenshot, `save.s` the
settings storage); the host side is `tools/lc1020e.py` (library and command-line tool).

All multi-byte numbers are little-endian. `u8`, `u16`, `u32` are unsigned integers, `f32` an IEEE
754 single-precision float. Records and answers are byte-packed (no alignment padding).

## 1. Transport

- USB full speed. Device descriptor: class 0x02 (communications, no interface association), VID
  `0x19F5`, PID `0x1020`, bcdDevice 1.00, manufacturer string "FNIRSI", product "LC1020E", serial
  number the chip's 96-bit unique ID (0x1FFFF7F0..0x1FFFF7FB) as 24 hex digits, the byte at
  0x1FFFF7F0 first, high nibble first, digits 0-9 A-F. One configuration (self powered, 100 mA):
  interface 0 (CDC control: header 1.10, call management, ACM capabilities 0x02, union 0 -> 1,
  interrupt endpoint 0x83, 16 bytes, interval 16 ms, never used for notifications), interface 1
  (CDC data: bulk IN 0x81 and bulk OUT 0x02, 64 bytes).
- Line coding (SET_LINE_CODING / GET_LINE_CODING) is stored and returned (115200 8N1 until the host
  sets one) and has no other effect. SET_CONTROL_LINE_STATE bit 0 is DTR.
- **DTR** must be set for events (section 10) and for SCREENSHOT. Requests are answered and STREAM /
  MEASURE_STREAM frames are sent with or without DTR. A USB bus reset clears DTR and the
  configuration and drops the bytes waiting to be sent. The device never enters USB suspend: after
  an unplug DTR stays set until the next bus reset.
- The control channel exists whenever our application runs and USB is connected; no menu setting
  is involved. The meter keeps working normally while no host is connected.
- The device appears on the bus at the first pass of the meter's main loop, when requests are
  served: the port is there only once the meter can answer (measured on a meter: back 4.1 s
  after a RESET, the first INFO answered at once).
- Flow control: the meter receives into a 1 KiB buffer; while it holds fewer than 64 free bytes the
  OUT endpoint answers NAK, so nothing sent by the host is lost. It sends from an 8 KiB buffer.

## 2. Frames

| Field | Size | Content |
|---|---|---|
| sync | 1 | `0xA5` |
| length | 2 | bytes from `seq` to the end of `payload`: 3..515 |
| seq | 1 | request: chosen by the host; answer: the request's value; stream / event: a running counter of the meter (one counter for both types) |
| type | 1 | `0x01` request, `0x02` answer, `0x03` stream, `0x04` event |
| cmd | 1 | command number (section 4); an answer carries the request's `cmd` |
| payload | n | 0..512 bytes |
| crc | 2 | CRC-16/CCITT-FALSE over `length` .. `payload`: polynomial 0x1021, initial value 0xFFFF, no reflection, no final XOR (check value of "123456789": 0x29B1) |

- Every request that the meter parses gets exactly one answer with the same `seq` and `cmd`. The
  first payload byte of an answer is the status (section 3); the answer data follows it (at most
  511 bytes).
- The meter's parser looks for `0xA5`, takes the length (a length outside 3..515 sends it back to
  the search at the next byte), collects the frame and checks the CRC. A frame with a wrong CRC, or
  a type other than request, is dropped without an answer, and the search continues after it.
  Hosts resynchronise the same way; `tools/lc1020e.py` also skips a `0xA5` whose frame is still
  incomplete when a complete valid frame follows it.
- A frame is put into the send buffer whole or not at all. An answer that does not fit waits and is
  sent in a later main-loop pass; a stream or event frame that does not fit is dropped and counted
  (STATE field "dropped frames").

## 3. Status codes

| Code | Meaning |
|---|---|
| 0 | OK |
| 1 | unknown command |
| 2 | bad length or argument (also: wrong confirmation value) |
| 3 | not allowed now (wrong screen, saves held, a condition of the command does not hold, a value the meter does not reach, the meter's procedure failed) |
| 4 | busy (a physical key took over, the time limit of the command passed, a capture or calibration already runs) |
| 5 | storage error (a flash erase, program or read-back failed) |
| 6 | refused for safety (section 7.3) |
| 7 | CRC or length mismatch of transferred data (settings block, slot file) |

Commands that run through the meter's own keys (section 4.1) and the direct commands (SCREEN,
LCR_SET, HOLD, SETTINGS_SET, COMPARE_SET) answer their record also when the status is not 0 (status
2 excepted: no data): the record then shows the state the meter was left in.

## 4. Processing and timing

### 4.1 The main loop

The control channel runs as one step of the meter's main loop, once per pass, after the watchdog
feed and the timer walk: (1) one step of a running key job, (2) a pending key injection is posted,
(3) the meter's key handler runs, or, in a pass with no key event and no key held, a pending
direct change, (4) events are detected and the screenshot and streams advance, (5) received bytes
are parsed, (6) a pending answer is sent. No step waits.

- At most one request is taken per pass, and none while an answer is still pending, a key job or a
  pending action (restart, update mode, power-off) runs, or a screenshot capture runs. Bytes sent
  meanwhile wait in the receive buffer. Hosts send the next request only after the answer of the
  previous one (and, for SCREENSHOT, after the capture has ended).
- Commands that change something through the meter's keys (KEY, CALIBRATE) run as a **job**: a
  program of steps, one step per pass, each step either pressing one key through the injection
  (section 7), waiting for the meter to handle it, or checking a RAM word. A job answers when its
  program ends or fails, or when its time limit passes (status 4). BOOT_BEGIN is a job too (one
  page erase per pass).
- SCREEN, LCR_SET, HOLD, SETTINGS_SET and COMPARE_SET are **direct** (capability bit 21, section
  14): the request is checked (section 5.3.4) and the requested value is set at once, in step (3)
  of the next pass that has no key event and no key held, with the same follow-up work the
  meter's own key handler does for the press that lands on that value (redraws, the measurement
  restart, the backlight), without key presses, beeps or intermediate values, and without
  changing the screen (SETTINGS_SET and COMPARE_SET stay on the screen shown). The answer comes in
  the pass after the change. A value that is already set is answered at once with nothing changed.
  Firmware without bit 21 runs these five as jobs of key presses.

### 4.2 Time base

The `time` fields and every time limit count the GUI tick word of the firmware (0x20000480), which
advances by 10 per SysTick interrupt; SysTick runs every 10 ms (reload 144000000 / 100), so one tick
is 1 ms.

### 4.3 Answer times

| Command | Time limit in the meter | `tools/lc1020e.py` waits |
|---|---|---|
| every command not listed here | answered in the pass of the request | 1.5 s |
| SETTINGS_SAVE, RESTORE_DEFAULTS, SETTINGS_RESTORE_B / ACCEPT_A / ACCEPT_B / ACCEPT_DEFAULTS, the last SETTINGS_WRITE_BLOCK chunk | one save inside the pass: up to 1.5 s (four page erases and the programming of two copies, one retry each; the watchdog is fed inside) | 4 s |
| SCREEN, LCR_SET, HOLD, SETTINGS_SET, COMPARE_SET | direct (bit 21): the next pass without a key event or a held key, at most 2000 ms (status 4 when a key stays held that long; nothing is changed then) | 4 s with bit 21 set; without it (older firmware: jobs of key presses) 23 s, COMPARE_SET 63 s |
| KEY | job, 20 000 ms + the hold time | 23 s + hold |
| CALIBRATE | job, 360 000 ms with capability bit 25 (15 points of at most 20 s each, 30 s for the bias wait after the start, which is not counted as a point's time, plus 30 s for the menu steps); 120 000 ms without it | 366 s with bit 25, 126 s without it |
| BOOT_BEGIN | job, 10 000 ms (12 pages, one erase per pass) | 13 s |
| BOOT_INSTALL | one record write (with a page erase when the record page is full) | 4 s |
| the last OCAL_WRITE chunk, OCAL_ROLLBACK | one commit inside the pass: up to 1.0 s (two page erases and up to 0x2000 bytes programmed, one retry; or two revoke words), the watchdog fed inside | 4 s |

Actions after an answer (RESET, UPDATE_MODE, POWER_OFF, BOOT_INSTALL, a restart after a settings
recovery): the action runs once the answer has left and the send buffer is empty, or 200 ms after
the answer left, or at the latest 1000 ms after the request (when the host stops reading).

## 5. Commands

Request = the request payload; Answer = the answer data after the status byte. "Confirmation" is
the u16 `0x4F4B` (bytes `4B 4F`, "OK") at the place given; POWER_OFF takes `0x4F46` (bytes `46 4F`).
A missing or wrong confirmation gives status 2. A payload longer than a command needs is accepted
and the extra bytes are ignored, except for PING, SETTINGS_WRITE_BLOCK, OCAL_WRITE and BOOT_DATA, whose length
is their data length. RESET, UPDATE_MODE and the BOOT_* commands take no confirmation.

### 5.1 Device

| cmd | Name | Request | Answer |
|---|---|---|---|
| 0x00 | INFO | - | INFO record (section 6.4), 58 bytes (46 before capability bit 27) |
| 0x01 | PING | any, 0..511 bytes (512: status 2) | the request bytes |
| 0x02 | RESET | - | none. After the answer: soft restart (section 7.6): the meter stays on, the port disappears and comes back with the next start. Status 6 (no data) when the slot bootloader that would start next is feature version 1 (it does not keep the watchdog fed after a soft restart): the meter would switch off |
| 0x03 | BATTERY | - | supply voltage f32 V (0x20005100: mean of 128 ADC samples x 6.6 / 4095), icon level u8 0..4 (the number of the thresholds 3.4 / 3.6 / 3.8 / 4.0 V the value is above, as the meter's battery icon 0x0800C724 compares them), low-voltage popup u8 (1 while 0x20005118 != 0); 6 bytes |
| 0x05 | POWER_OFF | u16 `0x4F46` | none. After the answer the meter's own power-off path runs (section 7.5). Status 3 in powered-off mode, 6 while a calibration runs |
| 0x06 | FACTORY_MODE | - | u8: word 0x200011C0 (0, 1 or 2; 2 = factory mode, set at start-up from the keys held at power-on). Read only |

### 5.2 State and keys

| cmd | Name | Request | Answer |
|---|---|---|---|
| 0x10 | STATE | - | STATE record (section 6.1), 32 bytes |
| 0x11 | STREAM | period u16 ms, 0 stops | none; STATE records follow as stream frames cmd 0x10 every period (section 11) |
| 0x12 | SCREEN | screen u8: 1 measure, 2 compare, 3 settings | STATE. Direct (section 5.3.4): the meter's own screen builder of the requested screen runs (from the settings screen an open sorting or calibration dialog is closed first). Status 6 while a calibration runs and from the settings screen while the restore-defaults dialog (item 6) is open; from the calibration dialog (item 5) with no calibration running the dialog is closed (status 0; firmware before MEASUREMENT_FIX_DESIGN revision 10 answered 6); status 3 in screen 0 (the vendor's language chooser; it never occurs: the firmware is English only, section 5.6) |
| 0x13 | KEY | key bit u8 0..13, hold u16 ms (optional, 0 or missing: short press) | STATE after the meter handled the key. Status 6 when the key is refused (section 7.3) or the guard stopped a flash write or defaults change; status 4 when a physical key ended the injection or the time limit passed; status 3 in powered-off mode |

### 5.3 Measurement

| cmd | Name | Request | Answer |
|---|---|---|---|
| 0x20 | LCR_TABLES | list id u8 (0..7), or nothing | with an id: the list (section 8.1); without: the number of lists u8 (8) |
| 0x21 | LCR_SET | setting u8 (0 Func, 1 secondary, 2 frequency, 3 level, 4 bias, 5 range, 6 speed, 7 circuit mode), value index u8 (below the list's count) | MEASURE (section 6.2). Screens 1 and 2 only (else status 3). Direct (table below, section 5.3.4); a value the meter's keys do not reach is refused with status 3 and nothing changed: level 0.6 V while the bias is 0.1 V or more (the bias float's bits 0x3DCCCCCD or above), Func AUTO or Z in the compare screen |
| 0x22 | MEASURE | - | MEASURE record, 66 bytes (65 before capability bit 26, 64 before capability bit 24) |
| 0x23 | MEASURE_STREAM | u16: 0 = a frame for every new result, 0xFFFF = stop, else period in ms | none; MEASURE records follow as stream frames cmd 0x22 |
| 0x24 | COMPARE | - | COMPARE record (section 6.3), 50 bytes (29 before capability bit 23) |
| 0x25 | COMPARE_SET | nominal f32, tolerance f32 (percent), warn type u8, warn sound u8, warn LED u8 (11 bytes, all required) | COMPARE. Direct, in screens 1..3 (section 5.3.1): the values as the sorting editor stores them; the screen stays; RAM only. A changed tolerance returns the tolerance mode of TOLERANCE_SET to 0 |
| 0x26 | HOLD | u8: 0 off, 1 on | STATE. Screens 1 and 2 only (else status 3). Direct: the hold word 0x200011A4 and the HOLD mark, as key 0x400 sets them. A change of frequency, level, bias, range, speed or circuit mode ends hold (Func and secondary do not) |
| 0x27 | CALIBRATE | type u8, confirmation u16 at byte 1 (3 bytes) | calibration status u8 (0x200050EC: 0 start, 1 busy, 2 finish, 3 fail), type u8 (0x200050E0), save status u32 (section 9.1), failed point u8 (0..14, 0xFF none), reason u8 (section 5.3.3); 8 bytes (6 before capability bit 25), with every status (section 5.3.3) |
| 0x28 | TOLERANCE_SET | mode u8, lower i32, upper i32, letter u8, secondary kind u8, secondary value f32 (15 bytes; section 5.3.5) | COMPARE, with every status. Capability bit 23. RAM only, answered at once; status 2 for a bad argument, 3 for the pF mode with a quantity other than C |

Settings of LCR_SET (the work of the meter's measure-screen handler 0x08009614 for the press of
its key that lands on the value; the key is named for reference, it is not pressed):

| Setting | Values (index: value) | Key | Follow-up work of the direct change |
|---|---|---|---|
| 0 Func | 0 AUTO, 1 R, 2 C, 3 L, 4 Z (word 0x20001148) | 0x0200 | AUTO: the Func picture; R..Z: main row and secondary = the value (R -> X, C -> D, L -> Q, Z -> theta) with their pictures; then the Func text, the measurement restart; in the compare screen its rule (C / L kept as the compare quantity, any other value: R); the result display |
| 1 secondary | 0 R, 1 X, 2 D, 3 Q, 4 theta (word 0x200011E8) | 0x0040 | the result display |
| 2 frequency | 0: 100 Hz, 1: 120 Hz, 2: 1 kHz, 3: 10 kHz, 4: 100 kHz, 5: 60 Hz (capability bit 22; word 0x20001144) | 0x2000 | cursor on FREQ, the measurement restart, the cursor row redrawn |
| 3 level | 0: 0.1 V, 1: 0.3 V, 2: 0.6 V (float 0x20001138) | 0x0800 | cursor on AMP, the measurement restart, the cursor row |
| 4 bias | 0: 0 V, 1: 0.5 V (float 0x2000113C) | 0x0100 | cursor on BIAS; 0.5 V with the level 0.6 V sets the level to 0.3 V (as the key does); the measurement restart, the cursor row |
| 5 range | 0 AUTO, 1: 100 ohm, 2: 1 kohm, 3: 10 kohm, 4: 100 kohm (word 0x2000114C) | 0x0080 | cursor on RANGE, the cursor row (no restart, as the key) |
| 6 speed | 0, 1, 2 (word 0x20001150) | 0x1000 | the speed icon, the measurement restart |
| 7 circuit mode | 0 auto, 1 series, 2 parallel (word 0x20001154) | 0x1000 long | the circuit icon |

#### 5.3.1 Limits of COMPARE_SET

- nominal: 0.001 <= nominal < 1e9 (compared as float bit patterns: negative values, NaN and
  infinity give status 2); tolerance: 0 <= tolerance <= 99.9 (-0.0 gives status 2); warn type,
  sound, LED: 0 or 1 each (else status 2).
- The sorting editor holds the nominal as a scale (0.001, 1, 1000 or 1e6) and five digits. The
  scale is chosen by the nominal: below 1 -> 0.001, below 1000 -> 1, below 1e6 -> 1000, else 1e6;
  the digit count is round(nominal x 100 / scale), limited to 100..99999. COMPARE_SET stores the
  scale index (word 0x2000119C) and the nominal float(count) / 100 x scale (the editor's formula
  for a digit), only when the scale or the count differ from the stored ones. The tolerance is set
  in tenths of a percent (round(tolerance x 10), at most 999) and stored as float(tenths) / 10,
  only when the tenths differ. The value the meter stored is in the COMPARE answer.
- In the settings screen with the sorting dialog open, the dialog is redrawn; in the compare screen
  the deviation, OK / NG and the nominal are recomputed and redrawn.

#### 5.3.2 What the jobs press

- Where a step has two keys, the job presses one and swaps them when the value did not move or
  moved away from the target. Every step has a press limit; a value not reached within it ends the
  job with status 3. CALIBRATE (5.3.3) is the only command with such a program; KEY presses one key.

#### 5.3.3 CALIBRATE

- Types: 0 short, 11 open; 1..10 (the factory resistor references) only in factory mode
  (FACTORY_MODE = 2), else status 2. Any other type: status 2.
- Refused with status 3 while saves are held or a restart is pending (section 9.2: the result
  could not be saved), with status 4 while a calibration already runs.
- The job runs the meter's own procedure with the guard off: settings screen, menu item 5, key
  0x008 (dialog, checked), keys 0x004 / 0x010 to the type, key 0x008 (start; checked: the
  calibration-running word 0x200050E4 must be 1, else status 3). Then the meter's sweep runs from
  the main loop; the job waits for status 2 (finish; the meter saves the result itself) -> answer
  status 0, or 3 (fail) -> status 3. When the running word goes to 0 for 1000 ms without one of
  them: status 3 (counted from the start of the waiting step). After the sweep's end (finish or
  fail; revision 10 of MEASUREMENT_FIX_DESIGN) the job presses long key 0x008 until the dialog is
  closed and then returns to the screen it found at the request (1, 2 or 3), so no physical key is
  needed afterwards; the calibration status, the failed point and the reason stay for the answer.
  When a check of the start fails (status 3) the job ends there. Progress comes as CALIBRATION
  events (section 10). The answer's save status is the save status word at the end of the job
  (after a finished calibration: the result of the meter's own save of it).
- The sweep of firmware with capability bit 25 (firmware/own/cal.s): 15 points in the vendor's
  order (100, 120, 1000, 10000, 100000 Hz, each at 0.1, 0.3, 0.6 V). Each point takes complete
  measurement windows only. A short (and a factory reference) point: the result is the median of
  its last 3 windows when all 3 lie within a factor 2 of it; a no-reading window starts its
  windows again. An open point (revisions 10 and 11): every usable window is kept (a no-reading or
  non-finite window is skipped, nothing is dropped); the point ends at its 7th usable window or at
  its 20-s limit. Its result is the mean of the windows' open admittances (each window's |Z| and
  phase, less the point's short), stored in the entry's form (|Zo| minus the short, phase of Zo)
  when the mean stands clear of the windows' scatter (2 or more windows and n (n - 1) |mean|^2 /
  sum |Y - mean|^2 above the 0.999 quantile of F(2, 2n - 2)) and (revision 14) when it is a lead
  stray: the mean admittance G + jB has B >= |G| and B > 0 (its phase from +45 to +135
  degrees: capacitive, G of either sign by noise) and B / (2 pi f) at most 50 pF; a mean below 100 kohm is kept (it fails the sweep,
  reason 3). Otherwise, and with fewer than 2 usable windows, it is stored "not resolved" (|Z|
  1e10, phase entry +400), and the measurement applies no open correction at that point (the
  short only). With leads open at 100 and 120 Hz the window scatter is far above the fixture's
  stray admittance, so those points are normally "not resolved"; after the 15th point (revision
  14) each 100 / 120 Hz open point "not resolved" takes the capacitance of the first resolved
  point of: the same level at 1 kHz, the same level at 10 kHz, the other 1 kHz levels ascending,
  stored as a pure susceptance at its own frequency (none resolved: it stays "not resolved"); 60
  Hz uses the 100 Hz entry. The sweep goes on in either case; an open point never fails by its time. The results stay in RAM and are written to the user table only after all 15
  points (a save during the sweep, by the power key or a host command, holds the old table and the
  settings of before the sweep). The finish restores the frequency, level, bias, speed and type of
  before the sweep, then saves once. The factory table is never written.
- Answer bytes 6 and 7 (capability bit 25): the point 0..14 at which the sweep ended without a
  result (0xFF when it finished or never started) and the reason: 0 none, 1 no acquisition for
  1.5 s, 2 a short or reference point's 20-s limit with fewer than 3 windows (the limit does not run while the
  measurement's bias wait holds publication after the start moved the bias to 0: a window is
  published once the DC midpoints are steady, at the latest 30 s after the bias change), 3 an open point below 100 kohm, 4 the
  vendor's store check (the table is written back as it was), 5 the point's limit with 3 windows
  that do not agree, 6 ended by a key, the dialog closed or the screen left. With status 3 the
  meter shows "Fail n/15" and the reason in the dialog; during the sweep "n/15" with the point's
  frequency (Hz, k for 1000) and level, for example "13/15" and "100k 0.1V".
- While CALIBRATE runs, every other request waits (section 4.1) and every injected key is refused.
- A calibration can also be started with KEY (key 0x008 on menu item 5 opens the dialog, key 0x008
  in it starts the sweep; revision 10) or with the meter's keys: it is the same sweep with the same
  finish and save. While any calibration runs, KEY, SCREEN, LCR_SET and the other direct changes
  answer status 6 (section 7.3).

#### 5.3.4 Direct changes: checks and differences from the jobs

Checks, in this order, at the request and again when the change is to run (a physical key in
between may have changed the state); a refusal changes nothing and answers the record:
- powered-off mode, or the meter's power-off path ran (its save is done; a change now would be
  lost): status 3;
- a calibration runs (0x200050E4 != 0, or the sweep of cal.s still in progress): status 6;
- the screen is not 1..3: status 3; LCR_SET and HOLD outside screens 1 and 2: status 3;
- the value is set already: status 0 at once, nothing changed;
- the refusals of the command (LCR_SET, SCREEN rows above).

The change runs in a pass with no key event and no key held; a key held for 2000 ms ends the
command with status 4 and nothing changed (the change does not run later). No key event, no beep,
no change of the busy flag of the long presses; SETTING_CHANGED and SCREEN_CHANGED events come as
for any change (section 10).

Differences from the results of the jobs of earlier firmware (firmware without bit 21):
- SETTINGS_SET and COMPARE_SET no longer go to the settings screen: the screen stays, the range is
  no longer set to AUTO (the settings screen's builder does that), and the effect of the sorting
  dialog the jobs opened goes away: with Func AUTO or Z they set Func to R, and they wrote the
  compare quantity and the main row; now these stay as they are.
- SCREEN from the settings screen to the measure screen when it was entered from the compare
  screen no longer passes the compare screen; the resulting state is the same.
- LCR_SET Func R in the compare screen from C or L: the job's presses passed Z (secondary theta)
  and the compare screen's rule set R; the direct change takes R itself (secondary X). The
  difference shows only in the secondary field of STATE / MEASURE while the compare screen is
  shown (the compare screen hides the secondary row; the measure screen sets the secondary from
  Func again).
- COMPARE_SET: the tolerance is float(tenths) / 10 instead of the editor's stepped value; the
  nominal is always float(count) / 100 x scale (the job could leave the editor's rescaled value
  after a scale change with every digit already in place; both are the same number to the last
  bit or one bit apart).
- No intermediate values: speed 2 -> 1 no longer passes 0, circuit mode 1 -> 0 no longer passes
  parallel, frequency and level no longer restart the measurement once per press.

#### 5.3.5 TOLERANCE_SET and the compare judgement (capability bit 23)

Request (15 bytes, little-endian): mode u8, lower i32, upper i32, letter u8, secondary kind u8,
secondary value f32. Modes: 0 the meter's own symmetric tolerance (COMPARE_SET's, 0x20001188; the
mode after every start); 1 lower / upper in 0.01 % steps (-9999..99990, lower <= upper); 2 lower /
upper in 0.01 pF steps (-99999..99999, lower <= upper; compare quantity C only, else status 3); 3 an
IEC 60062 letter: B C D F G J K M = +-0.1 / 0.25 / 0.5 / 1 / 2 / 5 / 10 / 20 %, Z = -20 / +80 %; B, C
and D are +-0.1 / 0.25 / 0.5 pF for a C nominal below 10 pF (decided at every judgement). Secondary
kind: 0 none, 1 D maximum, 2 Q minimum, 3 ESR (the series R) maximum; its value finite and >= 0.
Fields a mode does not use are not checked. The modes are RAM only: lost at power-off, and any
later change of 0x20001188 (the meter's sorting editor or COMPARE_SET) returns to mode 0.

The judgement (screen 2, every new result): a part is present when |Z| is not above the meter's
presence limit (110 Mohm / 10 = 11 Mohm at 60 Hz..1 kHz, 1.1 Mohm at 10 kHz, 110 kohm at 100 kHz).
Not present: "---" (no reading, overload, or above the measurement range) or "OUT" (a reading above
the presence limit; not counted). Present: the signed deviation (in % of the nominal, or in pF for
the pF modes) against the limits gives IN, HI or LO; IN with a failed secondary limit is reported
separately. The result is final once two consecutive results agree within min(band / 4, 0.1 %)
(band: the smaller limit); before that "---". It is counted once per insertion (pass for IN, fail
for every other result, each counter at most 999); the alarm follows the warn type (1 on IN, 0 on
every other result): the LED level held until the part is removed or the screen is left, and 1
beep (IN) or 2 beeps (other) of 200 ms. A long press of key bit 8 (mask 0x100) on the compare screen
resets both counters (once per press).

### 5.4 Settings and storage

| cmd | Name | Request | Answer |
|---|---|---|---|
| 0x50 | SETTINGS_TABLES | setting id u8 (0..5), or nothing | with an id: the setting (section 8.2); without: the number of settings u8 (6) |
| 0x51 | SETTINGS_SET | id u8, value u16 (3 bytes); the value must lie in min..max and on the step of SETTINGS_TABLES (else status 2) | STATE. Direct in screens 1..3 (section 5.3.4): the setting's word; brightness also sets the backlight at once; in the settings screen the menu rows and an open dialog are redrawn; the screen stays. RAM only, nothing saved |
| 0x52 | SETTINGS_SAVE | confirmation | save status u32, save flags u32 (section 9). Answer status: 0 saved; 3 saves held or refused; 5 a flash step failed; 7 bad block |
| 0x53 | CAL_READ | copy u8 (0 = A at 0x0807F000, 1 = B at 0x08066000), offset u16, length u16 (1..256), offset + length <= 0x1000 (5 bytes) | the bytes of that copy as they are in flash |
| 0x54 | RESTORE_DEFAULTS | confirmation | save status u32, save flags u32. Runs the meter's defaults routine 0x0800B4C8(0) with the guard off (it saves once itself), then redraws (backlight, the measure screen built anew). The user calibration table becomes the factory one; the first-start flag and the language word stay 1 (section 5.6; V1.1 clears the flag and shows its language chooser at the next start). Status 3 while saves are held or a restart is pending, or while a calibration runs |
| 0x55 | SETTINGS_RESTORE_B | confirmation | save status u32, save flags u32. Section 9.3. After status 0 the meter restarts |
| 0x56 | SETTINGS_ACCEPT_A | confirmation | as 0x55; section 9.3 |
| 0x57 | SETTINGS_WRITE_BLOCK | confirmation u16, offset u16, total u16 (0x0C14), CRC-32 u32 of the whole 0xC14-byte block (the same in every chunk), chunk bytes (1..502); at least 11 bytes | for a chunk that does not complete the block: the next expected offset u16. For the chunk that completes it: save status u32, save flags u32; after status 0 the meter restarts. Section 9.4 |
| 0x58 | (SETUP_LANGUAGE) | - | not implemented: status 1 (unknown command) for any payload; capability bit 20 is clear (section 5.6) |
| 0x59 | SETTINGS_ACCEPT_B | confirmation | as 0x55; section 9.3 |
| 0x5A | SETTINGS_ACCEPT_DEFAULTS | confirmation | as 0x55; section 9.3 |

### 5.7 Own calibration area (capability bit 26)

| cmd | Name | Request | Answer |
|---|---|---|---|
| 0x30 | OCAL_INFO | - | OCAL_INFO record (section 16.2), 64 bytes |
| 0x31 | OCAL_READ | slot u8 (0 at 0x08062000, 1 at 0x08064000), offset u16, length u16 (1..256), offset + length <= 0x2000 (5 bytes) | the bytes of that slot as they are in flash |
| 0x32 | OCAL_WRITE | confirmation u16, offset u16, total u16 (body length 8..0x9C0, a multiple of 4), CRC-32 u32 of the whole body (the same in every chunk), chunk bytes (1..502); at least 11 bytes; the chunk is every byte after byte 10 | a chunk that does not complete the body: the next expected offset u16. The last chunk: commit result u8 (0 OK, else the flash result of section 9.1), active slot u8, sequence u32. Section 16.4 |
| 0x33 | OCAL_ROLLBACK | confirmation u16, mode u8 (0 the active record, 1 every own format-1 record in force, the older first); 3 bytes | active slot u8 (0xFF none), sequence u32, flags u32 (section 16.2). Status 3 when no record qualifies, 5 when a revoke word failed; the refusals of section 16.4 |
| 0x34 | OCAL_LOCK | c5 u8 (0..7), c6 u8 (0..7), c8 u8 (0..3), or FF FF FF to release; 3 bytes | the OCAL_RAW record of the last window. Status 2 for a code out of range, 6 while a calibration runs, 3 powered off, after the power-off path ran or off screen 1. Section 16.3 |
| 0x35 | OCAL_RAW | - | the raw record of the last closed window, 64 bytes (section 16.3) |
| 0x36 | OCAL_TRACE | op u8 (0 disarm, 1 arm, 2 read), start u8 (read only, 0..31) | state u8 (0 idle, 1 armed, 2 recording, 3 full), kind u8, change tick u32, count u8, n u8, then n entries {tick u32, Zm re f32, Zm im f32, flags u8 (bit 0 discarded by the settle rule, bit 1 saturated, bit 2 discarded by the ranging band rule: the first or second out-of-band acquisition in a row, not ranged), c5 u8, c6 u8, c8 u8}; n at most 31 from start, so a full trace takes two reads (start 0, start 31) |
| 0x37 | MONITOR | - | V rms f32 (V), I rms f32 (A), A_V,ref f32, A_I,ref f32, flags u8 (bit 0 V calibrated at this frequency, bit 1 gain applied, bit 2 no reading or overload, bit 3 lock), DC midpoint ADC1 u16, ADC2 u16 (counts, no scale), window u32; 25 bytes. Section 16.5 |

### 5.6 English only

The firmware shows English only. The first-start flag (0x20001140, block 0x0BC4) and the language
word (0x2000115C, block 0x0BE0) are set to 1 after every load and before every save, in RAM and in
every copy written, by every path (power-off, the menu's and the start-up's defaults, RESTORE_DEFAULTS,
SETTINGS_WRITE_BLOCK, the recovery commands, the calibration finish). So the vendor's language
chooser (screen 0) never runs, a block with other values (written by V1.1) is loaded as English, and
V1.1 started on a copy our firmware wrote starts in English. The settings menu has no "Language"
item (section 7.1); its Chinese texts, icons and font glyphs are not in the image.

### 5.5 Screenshot and diagnostics

| cmd | Name | Request | Answer |
|---|---|---|---|
| 0x60 | SCREENSHOT | band u8 0..23, or 0xFF, or nothing (all bands) | width u16 (320), height u16 (240), format u8 (0: RGB565 as the panel gets it), number of bands that follow u8 (24 or 1); 6 bytes. Status 3 while DTR is clear, 4 while a capture runs, 2 for a band above 23. The bands follow as stream frames (section 12) |
| 0xF0 | MEM_READ | address u32, length u16 (1..256) (6 bytes) | the bytes. The whole range [address, address + length) must lie inside one of: flash 0x08000000..0x0807FFFF, system memory 0x1FFF0000..0x1FFF3FFF, the system configuration area and option bytes 0x1FFFF000..0x1FFFF811, RAM 0x20000000..0x2001FFFF; else status 2 |

### 5.6 Updates

| cmd | Name | Request | Answer |
|---|---|---|---|
| 0x80..0x83 | - | reserved | status 1 |
| 0x84 | UPDATE_MODE | - | slot that starts next u8 (0 F, 1 A, 2 B), its version u32 (slot header word +12), running slot u8 (as in INFO); 6 bytes. Status 0: after the answer the meter writes the update request word and restarts (soft restart, section 7.6: the meter stays on) into the slot bootloader's update mode. Status 6 (nothing done) when the slot that starts next has a version below 2 or an erased version word (0xFFFFFFFF): it would ignore the request |
| 0x85 | BOOT_BEGIN | slot u8 (1 A, 2 B: must be the free slot of BOOT_STATUS, else status 3), length u32 (0x208..0x6000, a multiple of 4, else status 2), CRC-32 u32 of the slot file (9 bytes) | none. Job: the slot's 12 pages are erased, one per pass, each checked to read 0xFF; status 5 when an erase fails |
| 0x86 | BOOT_DATA | offset u32 (a multiple of 4), chunk 4..256 bytes (a multiple of 4), offset + chunk length <= the length of BOOT_BEGIN | none. Every word programmed and read back. Status 3 before a successful BOOT_BEGIN; status 5 with flash result u8 (section 9.1) and the file offset u32 of the failing word |
| 0x87 | BOOT_END | - | the slot header's version u32. The slot is checked: CRC-32 of the written file = the CRC-32 of BOOT_BEGIN, then as the starter checks a slot (magic "SLOT", header CRC-32, link address = slot base + 0x200, image length 8..0x5E00 and a multiple of 4, image CRC-32, initial SP above 0x20000000 and at most 0x20024000, reset vector odd and inside the image), and the image inside the file length. Status 7 when a check fails, 3 before BOOT_BEGIN finished |
| 0x88 | BOOT_INSTALL | - | none. After a passed BOOT_END and while the slot is still the free one and still checks (else status 3 / 7): an INSTALL record for the slot is appended to the starter's records (status 5 when it did not read back in three attempts), then the meter restarts (soft restart, section 7.6) |
| 0x89 | BOOT_STATUS | - | 47 bytes: for slot F, A, B (13 bytes each): version u32, length u32, image CRC-32 u32 (header words +12, +4, +8 as stored), check u8 (1 = the slot passes the starter's check); then the newest record: slot u8 (0xFF none), state u8 (1 INSTALL, 2 TRIAL, 3 OK; 0 none), sequence u32; the slot that will start next u8; the free slot u8 |

BOOT_DATA after a passed BOOT_END makes BOOT_END necessary again. Section 13 gives both update
procedures.

## 6. Records

Records grow only at the end: a host reads the fields it knows and ignores further bytes.

### 6.1 STATE (32 bytes)

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | screen (0x20001168): 1 measure, 2 compare, 3 settings (0, the vendor's language chooser, never occurs) |
| 1 | u16 | flags (below) |
| 3 | u8 | Func (0x20001148): 0 AUTO, 1 R, 2 C, 3 L, 4 Z |
| 4 | u8 | main row shown (byte 0x200011E4): 1 R, 2 C, 3 L, 4 Z |
| 5 | u8 | secondary (0x200011E8): 0 R, 1 X, 2 D, 3 Q, 4 theta |
| 6 | u32 | frequency in Hz (0x20001144) |
| 10 | f32 | level in V (0x20001138) |
| 14 | f32 | bias in V (0x2000113C) |
| 18 | u8 | range (0x2000114C): 0 AUTO, 1 100 ohm, 2 1 kohm, 3 10 kohm, 4 100 kohm |
| 19 | u8 | speed (0x20001150): 0..2 |
| 20 | u8 | circuit mode (0x20001154): 0 auto, 1 series, 2 parallel |
| 21 | u8 | cursor (0x200011A8 in screens 1 and 2; 0xFF in screens 0 and 3) |
| 22 | u8 | dialog (0x200011AC: not 0 while a dialog is open) |
| 23 | u8 | menu item (0x200011A8 in screen 3: 0, 2, 3, 4, 5 or 6, never 1, section 7.1; 0xFF in the other screens) |
| 24 | u8 | language (0x2000115C): always 1, English (section 5.6) |
| 25 | u16 | dropped frames (low 16 bits of the count of stream and event frames dropped for lack of room) |
| 27 | u8 | save status (low byte of the save status word: the result code of section 9.1) |
| 28 | u32 | time (tick, section 4.2) |

Flags: bit 0 hold (0x200011A4 != 0), 1 compare screen (screen = 2), 2 DTR, 3 power off requested
or done, 4 last save failed, 5 backup differs, 6 calibration running (0x200050E4 != 0), 7 factory
mode (0x200011C0 = 2), 8 saves held, 9 restart pending (flash differs from RAM), 10 powered-off
mode (section 7.5).

### 6.2 MEASURE (66 bytes; 65 before capability bit 26, 64 before capability bit 24)

| Offset | Type | Field |
|---|---|---|
| 0 | u32 | result number (count of new results seen since start; the MEASURE_DONE number) |
| 4 | u32 | time (tick) |
| 8 | u8 | main row (byte 0x200011E4): 1 R, 2 C, 3 L, 4 Z |
| 9 | 15 | main value block |
| 24 | u8 | secondary (0x200011E8): 0 R, 1 X, 2 D, 3 Q, 4 theta |
| 25 | 15 | secondary value block |
| 40 | u8 | series / parallel values in use (0x200011EC): 0 series, 1 parallel |
| 41 | f32 | \|Z\| in ohm (0x200050C4) |
| 45 | f32 | theta in degrees (0x200050CC) |
| 49 | u32 | frequency in Hz |
| 53 | f32 | level in V |
| 57 | f32 | bias in V |
| 61 | u8 | range |
| 62 | u8 | speed |
| 63 | u8 | circuit mode |
| 64 | u8 | markers (capability bit 24): bit 0 the main value, bit 1 the secondary value lies outside the manual's accuracy table for the frequency (the meter shows the digits in amber); 60 Hz has no table column (always marked); theta, D and Q are never marked |
| 65 | u8 | OCAL flags (capability bit 26): bit 0 the gain correction of the own calibration area applied to this result, bit 1 a GAIN section calibrates this frequency but not this range / gain cell, bit 2 OCAL_LOCK holds the codes, bit 3 OF_RETAKE (section 16.2) |

Value block (15 bytes):

| Offset | Type | Field |
|---|---|---|
| 0 | f32 | the value the display formats, as read before formatting, in the base unit of its quantity: R, Z and X in ohm, C in nF, L in uH, D and Q without unit, theta in degrees. A negative R, C, L, D or Q keeps its sign here while its text (offset 7) is 0 or "0L" |
| 4 | u8 | unit code of the display text: 0 none, 1 ohm, 2 kohm, 3 Mohm, 4 pF, 5 nF, 6 uF, 7 mF, 8 uH, 9 mH, 10 H, 11 degree |
| 5 | u8 | decimals: digits after the point in the display text |
| 6 | u8 | validity: 0 valid, 1 overload ("0L" from the formatter), 2 no reading (the meter's no-reading counter 0x2000120C above 200), 3 held. Checked in the order 3, 2, 1 |
| 7 | 8 | display text, ASCII, zero padded: the text the display shows (firmware/own/fmt.s on the meter's formatters 0x0800E028 ohm, 0x0800DB24 C, 0x0800DE2C L, 0x0800DD44 D / Q, 0x0800DFC4 theta): "0L" above the measurement range (R, Z, X above 10 Mohm, C above 100 mF, L above 100 H, or not finite); "0L" in every value block at 60, 100 and 120 Hz when \|Z\| (offset 41) is above 1e7 ohm, the highest impedance the manual specifies at 100 Hz (MEASUREMENT_FIX_DESIGN revision 14; 1, 10 and 100 kHz unchanged); a negative value by its quantity (revision 14, by offset 40): series R (main or secondary), parallel C and series L shown as 0 ("0.0000" with unit code 1 and 4 decimals, "0.0" with unit code 4 and 1 decimal, "0.0" with unit code 8 and 1 decimal; marker bit set), parallel R, series C and parallel L shown as "0L" (validity 1, unit code 0, marker bit clear), a negative D as "0.0000" and a negative Q as "0L" (the meter stores D and Q as magnitudes, so neither comes negative today); D "0L" (validity 1) and Q "0.0000" when the main value is C or L and its text is 0 ("0.0": a negative value shown as 0, or one below the last place; D goes to infinity and Q to 0 as C or L goes to 0; revision 15); revision 13 showed all of them as 0, firmware before it sent them with a '-'; a '-' in front of a negative X or theta, at most 19,999 counts (one decimal less above; C 2000.0 .. 7999.9 uF is sent in mF with 3 decimals, unit code 7; D and Q from 20,000 have no decimal to drop and keep 5 digits). Every byte after the terminating 0 is 0 (firmware before MEASUREMENT_FIX_DESIGN revision 12 could leave bytes of the vendor's longer text there: read the text up to its first 0) |

Sources: main row 1 R 0x200050B8, 2 C 0x200050BC, 3 L 0x200050C0, 4 Z 0x200050C4; secondary 0 R
(0x200050B8, the signed word the display formats), 1 X 0x200050C8 (sign kept), 2 D 0x200050D4, 3 Q
0x200050D0, 4 theta 0x200050CC. A main row or secondary outside these values gives a block with
value 0, unit 0, decimals 0 and an empty text (validity 3 or 2 as above, else 0).

The measured values (firmware/own/meas.s): theta (offset 45) is the phase of the measured
impedance in degrees from -180 to 180, not folded into -90..90 as the vendor firmware V1.1 did, so
a part with a negative resistive part keeps its sign in R (0x200050B8 in series mode). A new result
comes once per averaging window: 1, 2 or 4 per second for speed 0, 1 or 2 (a window holds at least
3 acquisitions, so it can last longer when an acquisition is slow). Series / parallel in circuit
mode auto: series below 1 kohm, parallel above 10 kohm, the mode in use kept in between (after a
change of frequency, level, bias or speed: series below 3.16 kohm). In AUTO the main quantity
changes R -> C below -11 degrees, R -> L above 11 degrees and back to R above -9 / below 9 degrees;
R shows theta as its secondary. An overload (ADC saturated with no range step left, or no
finite value) and the no-reading result (no in-band acquisition for 2 s) carry |Z| 1e10 and theta
-400, the vendor firmware's values; while hold is on no result is published.

|Z| (0x200050C4) is never negative on the measure and compare screens (revision 10 of
MEASUREMENT_FIX_DESIGN): where the open / short compensation cannot be used the result is |Zbar|
minus the short entry, and a reading below the short entry is published as the same complex value
with |Z| >= 0 and theta moved by 180 degrees (R, X, C, L, D, Q unchanged; firmware before it
published a negative |Z| with the uncorrected theta). On the settings screen the field is the
calibration's store quantity (|Zbar| for the short, |Zbar| minus the short entry for the other
types), which can be negative.

With capability bit 26 the result can carry the gain correction of the own calibration area
(section 16): where a GAIN section calibrates the frequency and the range / gain cell (all four
mask bits), |Z| and theta are K zeta nu sum V' / sum I' and the vendor decade interpolation is not
applied; everywhere else the result is the one without the area.

### 6.3 COMPARE (50 bytes; 29 before capability bit 23)

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | quantity (0x20001178): 1 R, 2 C, 3 L |
| 1 | f32 | nominal (0x20001184), in the quantity's base unit as above |
| 5 | f32 | tolerance in percent (0x20001188) |
| 9 | f32 | deviation in percent (0x200050D8) |
| 13 | u8 | OK: 1 when the judgement (offset 40) is IN, else 0 |
| 14 | u32 | pass counter (0x200050F0, RAM only, at most 999) |
| 18 | u32 | fail counter (0x200050F4, RAM only, at most 999) |
| 22 | f32 | compare value (0x200050DC) |
| 26 | u8 | warn type (0x2000116C) |
| 27 | u8 | warn sound (0x20001170): 0 / 1 |
| 28 | u8 | warn LED (0x20001174): 0 / 1 |
| 29 | u8 | tolerance mode in force: 0 the meter's symmetric %, 1 % limits, 2 pF limits (section 5.3.5) |
| 30 | u8 | tolerance mode as set: 0 vendor, 1 %, 2 pF, 3 letter |
| 31 | u8 | the letter of mode 3 (ASCII), else as last set |
| 32 | f32 | lower limit in force (% or pF by offset 29) |
| 36 | f32 | upper limit in force |
| 40 | u8 | judgement: 0 no part ("---"), 1 IN, 2 HI, 3 LO, 4 the secondary limit failed, 5 out of range (a reading above the presence limit, not counted), 6 not yet stable ("---") |
| 41 | f32 | signed deviation of the last judgement (% or pF by offset 29) |
| 45 | u8 | secondary limit: 0 none, 1 D maximum, 2 Q minimum, 3 ESR maximum |
| 46 | f32 | its value |

### 6.4 INFO (58 bytes; 46 before capability bit 27)

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | protocol version: 1 |
| 1 | u32 | capability bits (section 14) |
| 5 | 16 | firmware version text, ASCII, not zero-terminated: "LC1020E V1.1 OWN" |
| 21 | 12 | chip unique ID (0x1FFFF7F0..0x1FFFF7FB) |
| 33 | u8 | running slot bootloader: 0 F, 1 A, 2 B, 0xFF unknown (from the hand-over word a slot bootloader of version 2 or later writes before it starts the application) |
| 34 | u32 | version of the running slot (its header word +12), 0 when the slot is unknown or its header has no "SLOT" magic |
| 38 | u32 | application size in bytes (end of our image - 0x08006000) |
| 42 | u32 | result of the last update (from the result word the slot bootloader writes before its restart after an update; tag and complement checked): 0 none, 1 written and checked, 2 image check failed, 3 programming failed |
| 46 | u32 | (capability bit 27) progress word of the previous start, as this start found it: bits 31..16 the tag 0x5350, 15..8 clock flags, 7..0 the last stage reached (table below); 0 when the word had no tag (power-on: main SRAM does not keep its contents without power, or firmware without the word) |
| 50 | u32 | (capability bit 27) progress word of this start (the same format; stage 14 once the main loop runs) |
| 54 | u32 | (capability bit 27) RCC_CTRLSTS (0x40021024, N32G45x user manual 6.3.11) as this start read it before it cleared the reset flags: bit 31 low-power, 30 window watchdog, 29 independent watchdog, 28 software, 27 power-on / power-down, 26 NRST pin, 25 MMU, 23 RAM, 21 backup domain EMC, 20 retention domain EMC, 19 BOR reset; bits 1 / 0 LSI ready / enabled. The flags gather every reset since the last start that cleared them (a start that stops earlier leaves them) |

Progress word stages (each stored just before the step it names; firmware/own/boot.s): 1 reset
handler, 2 clock set-up done, 3 GPIO set-up (after the RAM initialisation), 4 own start code, 5
settings load, 6 timer / GPIOB set-up (0x0800814C), 7 LCD set-up, 8 start-up animation, 9
0x0800B0D8, 10 0x080087D4, 11 0x08008024, 12 0x0800CA2C (first-start flag set) or 13 0x0800C86C (flag
clear), each followed by 0x08008120, the watchdog start 0x08010178 and the print "loop", 14 the main
loop. Clock flags: 0x01 the switch to the internal oscillator did not happen within 0x8000 polls (the
clock is left as the slot bootloader set it), 0x02 the PLL did not lock (the meter runs on the
internal 8 MHz oscillator and shows the crystal-fault screen), 0x04 the switch to the PLL did not
happen (the same).

Where a clock flag can be read: 0x01 leaves a normal start (USB runs), so INFO byte 50 reports it.
0x02 and 0x04 never reach a host through byte 50: both starts end in the crystal-fault screen
(firmware/own/ctl.s own_start, `bne.w xtal_fault` before its return; firmware/own/xtal.s
xtal_fault never returns), which runs before USB is started (ctl_loop's first pass,
usb_start) and starts nothing after it; on battery the screen ends with the power off, which
loses main SRAM. They are read over SWD at 0x2001FFEC (BOOT_PROG; stage 4) while the fault
screen or its end loop runs. Byte 46 of a later start could show them only after a reset that
keeps the meter powered (USB power, the fault loop running) and main SRAM, which the user manual
does not state for a reset (N32G45x user manual V3.5.0, 3.2.3 SRAM: "SRAM data cannot be
retained in Stop2, Standby and VBAT modes"; resets are not named).

The hand-over word is read once at start and cleared, so INFO reports it for the start that
followed it. The result word is kept until an INFO answer has been queued whole for sending (the
meter clears it when the answer frame enters its USB send buffer, firmware/own/ctl.s ans_step; a
start that stops before that leaves it to the next start; firmware before capability bit 27
cleared it at every start); a result word with a wrong tag or complement is cleared at start.
The meter does not see whether the host received the frame (its USB driver sends the buffer in
packets and keeps no frame boundary): an INFO answer queued but not received, for example
because the port was closed or the meter restarted first, loses the result.

## 7. Keys

### 7.1 Key bits

KEY takes the bit number; events and job descriptions use the mask (1 << bit). The meter scans the
keys every 10 ms (mask 0x20000008, active low except bit 9) and hands one event at a time to its
handler: code 1 short press (released), 0xFE held (the press lasted more than 99 scans), 0xFF
released after a hold.

| Bit | Mask | Pin | Measure screen (1) | Settings screen (3) |
|---|---|---|---|---|
| 0 | 0x0001 | PC6 | long: power off | |
| 1 | 0x0002 | PC7 (up) | value +1 of the parameter under the cursor | previous menu item; in the sorting editor: steps the digit |
| 2 | 0x0004 | PC8 | cursor +1 | value of menu items 2..4; in the sorting dialog: row, digit position, alarm value |
| 3 | 0x0008 | PC9 (OK) | long: settings screen | opens the item / dialog, starts editing a row, starts the calibration (item 5); long: leaves editing, closes the dialog, leaves the menu to the previous screen |
| 4 | 0x0010 | PC10 | cursor -1 | as 0x0004, other direction |
| 5 | 0x0020 | PA15 | value -1 of the parameter under the cursor | next menu item; in the sorting editor: steps the digit |
| 6 | 0x0040 | PC11 | secondary +1 | |
| 7 | 0x0080 | PC12 | cursor to RANGE, then step it | |
| 8 | 0x0100 | PB5 | cursor to BIAS, then step it | |
| 9 | 0x0200 | PB7 | Func +1 (Func 1..4 also sets the secondary: R -> X, C -> D, L -> Q, Z -> theta) | |
| 10 | 0x0400 | PE6 | hold on / off; long: compare screen | |
| 11 | 0x0800 | PB8 | cursor to AMP (level), then step it | |
| 12 | 0x1000 | PB9 | speed +1; long: circuit mode +1 | |
| 13 | 0x2000 | PE0 | cursor to FREQ, then step it | |

Menu items of screen 3 (the numbers of the menu item word 0x200011A8, in the order shown): 0
Sorting, 2 Brightness, 3 Volume, 4 Off Time, 5 Calibration (page 1), 6 System (model, version,
restore defaults; page 2). Keys 0x0020 / 0x0002 step through these six and stop at both ends; the
vendor's item 1 (Language) is not in the menu. In the compare screen (2) long 0x0400 returns to the
measure screen; the other keys of that screen are not specified here (COMPARE_SET sets its values).
Empty cells: no function that this document specifies.

### 7.2 Injection

- Short press (KEY hold 0): the meter's event slot gets the mask and code 1, posted with interrupts
  masked, only while the slot is empty and no physical key is down; the press is done when the
  meter's handler has consumed it.
- Hold of n ms: below 1000 ms it is posted as a short press after n ms (as the scan would report
  it). From 1000 ms on: one 0xFE per main-loop pass while the slot is empty, until n ms have passed
  and at least one 0xFE was consumed, then 0xFF.
- A physical key during an injection ends it (a hold that sent 0xFE ends with 0xFF), the physical
  key goes on as normal, and the job answers status 4.
- Job presses that are "long" hold for 1100 ms.

### 7.3 Refusals (status 6, nothing posted)

Injected keys (KEY and every job step except the procedures listed below) are refused before they
reach the meter when (the direct commands press no key; their refusals are in section 5.3.4,
with the same status 6 while a calibration runs and for SCREEN from the dialog of item 6):

| Condition (RAM words the meter's key handler reads) | Why | Use instead |
|---|---|---|
| screen 0 (0x20001168 = 0): every key (never occurs, section 5.6) | the language chooser's keys store the first-start flag and save | - |
| a calibration runs (0x200050E4 != 0, or the sweep of cal.s still in progress for the pass after the running word was cleared) or CALIBRATE is active: every key | keys of item 5 abort a calibration (with bit 25 nothing is stored and the settings are put back; without it the start has already changed the calibration table) | wait for its end |
| a hold of the power key (bit 0) | the meter's power-off path switches the meter off | POWER_OFF |
| key 0x0008 in screen 3 on menu item 6 while a dialog is open (0x200011AC != 0) | confirms the restore of the defaults | RESTORE_DEFAULTS |

Key 0x0008 on menu item 5 is not refused (revision 10 of MEASUREMENT_FIX_DESIGN; refused before):
with the dialog closed it opens the calibration dialog, in the dialog it starts the calibration,
the same sweep with the same finish and save as from the meter's keys or CALIBRATE (5.3.3); the
keys 0x004 / 0x010 there choose the type, a long key 0x008 closes the dialog. With bit 25 the
calibration table is written only after its 15th point.

Guard: while the meter's key handler processes an injected event, and while a direct change runs,
the settings save and the menu's call of the defaults routine return without acting; the job or
the direct command then answers status 6 (no direct change reaches either). A dialog
opened by injected keys and confirmed with a physical key is a user action: the guard does not
apply to physical keys.

Commands that run the meter's own path with the guard off and without these refusals: CALIBRATE,
POWER_OFF. POWER_OFF is refused with status 6 while a calibration runs.
UPDATE_MODE is refused with status 6 when the next slot bootloader would not honour it.

### 7.4 Jobs and the screen

CALIBRATE goes to the settings screen for the sweep and, after its end, closes the calibration
dialog and returns to the screen it found (revision 10 of MEASUREMENT_FIX_DESIGN; before, it stayed
in the dialog and a physical long OK was needed). SETTINGS_SET and COMPARE_SET leave the screen as it is (with bit 21;
the jobs of older firmware went to the settings screen).

### 7.5 Power-off

POWER_OFF posts the meter's own power-off event (0xFE with mask 0x0001) after the answer: the meter
saves, beeps and releases its power latch. When the meter still runs 1000 ms after its power-off
path ran (powered from USB), it enters powered-off mode: backlight off, event POWERED_OFF, STATE
flag 10; the meter's key handler no longer runs, every key event is discarded except the power key,
which restarts the meter (soft restart, section 7.6; it then starts normally and stays on). In powered-off mode KEY, the jobs and the direct commands answer
status 3; the direct commands answer status 3 already once the power-off path ran. The same mode
follows a physical long press of the power key on USB power.

### 7.6 Restart

RESET, UPDATE_MODE, BOOT_INSTALL, the restart after a settings recovery and the power key in
powered-off mode restart the meter without a system reset (a system reset releases the power latch
and switches the meter off, also on USB power): the meter disconnects from USB, stops its
interrupts, keeps its power latch on and starts again from the first-stage bootloader, which starts
the slot bootloader and then the application (or the update mode). The meter stays on; the serial
port disappears and comes back (same serial number) with the next start. This needs slot
bootloaders of version 2 (INFO: running slot version): a slot of version 1 does not pass the restart
on to the application, which then releases the power latch during its start as at a power-on (the
meter switches off unless the power key is held). The slot bootloader's own restart after an update
(section 13.1) works the same way.

## 8. Option tables

Texts are zero-terminated, at most 40 bytes, cut where the answer ends (511 bytes): the last text of
a long answer can lack its zero. Every text is English (section 5.6); texts taken from the meter's
own tables are its English texts (UTF-8: the ohm sign is CE A9); the texts below in quotes are
ASCII.

### 8.1 LCR_TABLES list

id u8, count u8, value type u8 (0 index, 1 u32, 2 f32), name, unit text, then per entry: value u32
(the index for type 0; the u32 or the f32 bits otherwise) and its text. Entries that do not fit are
left out (count stays).

| Id | List | Count | Type | Name | Entries | Unit |
|---|---|---|---|---|---|---|
| 0 | Func | 5 | index | "Func" | the meter's Func names (0x20000270) | "" |
| 1 | secondary | 5 | index | "Secondary" | "R", "X", "D", "Q", "theta" | "" |
| 2 | frequency | 6 (5 before capability bit 22) | u32 | the meter's cursor label (0x20000234: "FREQ") | "100Hz", "120Hz", "1kHz", "10kHz", "100kHz", "60Hz"; values 100, 120, 1000, 10000, 100000, 60 | "Hz" |
| 3 | level | 3 | f32 | cursor label ("AMP") | "0.1V", "0.3V", "0.6V"; values 0.1, 0.3, 0.6 | "V" |
| 4 | bias | 2 | f32 | cursor label ("BIAS") | "0V", "0.5V"; values 0.0, 0.5 | "V" |
| 5 | range | 5 | index | cursor label ("RANGE") | the meter's range names (0x20000244) | "ohm" |
| 6 | speed | 3 | index | "Speed" | "0", "1", "2" | "" |
| 7 | circuit mode | 3 | index | "Circuit" | "AUTO", "SERIES", "PARALLEL" | "" |

### 8.2 SETTINGS_TABLES setting

id u8, kind u8 (0 choices, 1 range), current value u32, min u32, max u32, step u32, name, number of
choices u8, then per choice its text (choice i has the value min + i x step).

| Id | Setting | Kind | Values | Where (SETTINGS_SET) | Name |
|---|---|---|---|---|---|
| 0 | brightness (0x20001158) | range | 10..100 step 10 (backlight percent) | menu item 2 | menu label ("Brightness") |
| 1 | volume (0x20001160) | range | 10..100 step 10 | menu item 3 | menu label ("Volume") |
| 2 | off time (0x20001164) | choices | 0..3: "NO", "5min", "15min", "30min" | menu item 4 | menu label ("Off Time") |
| 3 | warn type (0x2000116C) | choices | 0 "NG", 1 "OK" | sorting dialog row 2 | sorting row label ("Warn") |
| 4 | warn sound (0x20001170) | range | 0..1 | sorting dialog row 3 | sorting row label ("Volume") |
| 5 | warn LED (0x20001174) | range | 0..1 | sorting dialog row 4 | sorting row label ("LED") |

The language has no setting: the firmware is English only (section 5.6).

The off time has no consumer in the meter's firmware V1.1 that this firmware is built on: the
setting is stored, the meter does not switch itself off by it.

## 9. Settings storage

The meter keeps its settings and calibration in a 0xC14-byte block (RAM 0x2000057C). It is stored
in two copies of two flash pages each: copy A at 0x0807F000 (the vendor's place and format) and copy
B at 0x08066000. Block bytes at offset 0..0xC13 of the copy, first and last word 0x12345678; a
trailer at copy offset 0xFF8 (sequence u32) and 0xFFC (CRC-32 of the 0xC14 block bytes followed by
the 4 sequence bytes). CRC-32 everywhere in this protocol: reflected, polynomial 0xEDB88320,
initial and final XOR 0xFFFFFFFF (zlib's crc32; check value of "123456789": 0xCBF43926).

A copy is valid with both markers and a matching trailer CRC; copy A is also valid with both
trailer words 0xFFFFFFFF (vendor format). At start the meter loads the valid copy with the higher
sequence (A when equal or in vendor format). A save takes a snapshot of the RAM block and writes it
with the highest valid sequence + 1: copy B, then copy A; only copy A while "backup differs" or
"copy B loaded" is set (flags 1 and 4 below). Each copy: erase both pages and check them, program,
read the whole copy back; one retry; a failure leaves the other copy untouched. Block offsets 0x04
to 0xB43 are the calibration tables (factory 0x04..0x5A3, user 0x5A4..0xB43).

### 9.1 Save status word and flags

Save status u32 = result | step << 8 | copy << 16:

| Result | Meaning | Answer status |
|---|---|---|
| 0 | OK | 0 |
| 1 | held: nothing written (saves held or restart pending) | 3 |
| 2 | refused: nothing written (the guard, or the command's condition does not hold) | 3 |
| 3 | the trailer mark of a vendor-format A failed (stopped before any erase) | 5 |
| 4 | a page erase or its blank check failed | 5 |
| 5 | a word failed to program | 5 |
| 6 | the copy read back differs | 5 |
| 7 | bad block: markers missing or transfer CRC wrong | 7 |
| 8 | the source copy of a recovery is not valid | 5 |
| 9 | unchanged (capability bit 24): both copies already hold the block, nothing erased or written (a save of the meter or SETTINGS_SAVE with nothing changed) | 0 |

Step: 0x01 the check before any write, 0x41 mark, 0x42 erase, 0x43 program, 0x44 verify. Copy: 0
none, 1 A, 2 B.

Save flags u32: bit 0 saves held, 1 backup differs (B valid, its calibration tables differ from
A's), 2 no valid copy at load, 3 the last save failed, 4 copy B was loaded (ordinary saves write A
only), 5 copy A damaged (both markers, CRC wrong) while B is valid, 6 a rewrite of A from B is
pending, 7 restart pending (flash differs from RAM: saves are held until the restart).

Flash result (BOOT_DATA status 5): 0 OK, 1 outside the writable area, 2 word holds another value
and is not erased, 3 flash controller stayed locked, 4 flash error flag after the operation, 5 word
read back differs, 6 page not blank after its erase.

### 9.2 Held saves

Saves are held (flag 0) when at load neither copy was valid (flag 2: the defaults run in RAM, both
damaged copies stay in flash), or copy A is damaged and B valid (flag 5: A may hold data B lacks).
While held, every save of the meter (power-off, defaults, calibration) and SETTINGS_SAVE
writes nothing (result 1), and RESTORE_DEFAULTS and CALIBRATE are refused. A host first takes a
backup (CAL_READ of both copies), then resolves it with one of the commands of 9.3 / 9.4.

### 9.3 Recovery commands

| Command | Allowed when (else result 2, nothing written) | Writes | Then |
|---|---|---|---|
| SETTINGS_RESTORE_B (0x55) | not held, and backup differs (flag 1) or B was loaded (flag 4) | B's block to A with B's sequence | clears flags 1, 4, 6; restart after result 0 |
| SETTINGS_ACCEPT_A (0x56) | not held, and flag 1 or flag 4 | A's block to B (A's sequence; a vendor-format A gets the highest sequence + 1) | clears flags 1, 4; restart when B was the loaded copy |
| SETTINGS_ACCEPT_B (0x59) | A damaged (flag 5) | B's block to A with B's sequence | clears flags 0, 5, 6 |
| SETTINGS_ACCEPT_DEFAULTS (0x5A) | no valid copy at load (flag 2) | the RAM block (the defaults, plus any change since), markers checked, to B then A | clears flags 0, 2 |

Whenever flag 7 (restart pending) is set after one of these commands or WRITE_BLOCK, the meter
restarts after the answer (also when the command itself was refused). A host reconnects and reads
STATE.

### 9.4 Host backup and restore

- Backup: CAL_READ of copy 0 and copy 1, offsets 0..0xF00 in steps of 256 (32 requests): the full
  two pages of each copy, trailer included. `tools/lc1020e.py backup` writes them to one file of
  0x2000 bytes (copy A, then copy B).
- Restore: SETTINGS_WRITE_BLOCK with the 0xC14 block bytes in order from offset 0. Every chunk
  carries the total 0x0C14 and the CRC-32 of the whole block; a chunk at offset 0 starts a new
  transfer, any other chunk must start at the offset the previous answer named and carry the same
  CRC-32 (else status 2). The chunks are collected in a staging buffer, not in the live block. With
  the last chunk the meter checks both markers and the CRC-32 (status 7, nothing written, when
  either fails), writes the block by the save rules above (B then A, or A only), clears flags 0, 2,
  5, 6, and restarts after the answer; the next start loads the written block.
- A save of the meter during a transfer uses the same staging buffer and makes the final CRC check
  fail (status 7): a host keeps the meter's own saves out of the transfer (no power key, no
  calibration) and repeats from offset 0 after a status 7.

## 10. Events

Type 0x04 frames, sent only while DTR is set, detected once per main-loop pass by comparing with
the previous pass. The comparison runs also without DTR, so a host that sets DTR receives the
changes from then on. The meter's key handler is not run in powered-off mode, so no KEY events
come then.

| cmd | Name | Payload |
|---|---|---|
| 0x90 | KEY | mask u16, code u8 (1 short, 0xFE held, 0xFF released after a hold), source u8 (0 physical, 1 injected): every key event the meter's handler receives (the direct commands post none) |
| 0x91 | SCREEN_CHANGED | screen u8, previous screen u8 |
| 0x93 | SETTING_CHANGED | id u16, value u32 (below) |
| 0x94 | POWERED_OFF | none (section 7.5) |
| 0x95 | MEASURE_DONE | result number u32 (as MEASURE offset 0) |
| 0x96 | SAVE_RESULT | save status u32, save flags u32 (section 9.1): when the meter's save counter changed (saves and recovery commands) |
| 0x97 | CALIBRATION | status u8 (0x200050EC), step u8 (0x200050E8), type u8 (0x200050E0): when status or step changed. Step with capability bit 25: 3 x the points done + the windows held for the point in progress (0..2), 45 at the store; without it the vendor's seconds 0..45 |
| 0x98 | OCAL_CHANGED | active slot u8 (0xFF none), sequence u32, flags u32 (section 16.2): after every OCAL_WRITE commit and OCAL_ROLLBACK (not at the start) |

SETTING_CHANGED ids: for every changed 32-bit word of the settings block, its byte offset in the
block (address - 0x2000057C) with the new word; for the calibration tables (offsets 0x04..0xB43)
one event with id 0xFFFE and the number of words that changed in that pass. Further ids for
RAM-only state (offsets beyond the block): 0x0C28 hold (0x200011A4), 0x0C2C cursor / menu item
(0x200011A8), 0x0C68 main row (byte 0x200011E4), 0x0C6C secondary (0x200011E8). Offsets of the
settings in the block:

| Id | Setting | Id | Setting |
|---|---|---|---|
| 0x0BBC | level (f32 bits) | 0x0BE4 | volume |
| 0x0BC0 | bias (f32 bits) | 0x0BE8 | off time |
| 0x0BC4 | first-start flag (1, section 5.6) | 0x0BEC | screen |
| 0x0BC8 | frequency | 0x0BF0 | warn type |
| 0x0BCC | Func | 0x0BF4 | warn sound |
| 0x0BD0 | range | 0x0BF8 | warn LED |
| 0x0BD4 | speed | 0x0BFC | compare quantity |
| 0x0BD8 | circuit mode | 0x0C08 | nominal (f32 bits) |
| 0x0BDC | brightness | 0x0C0C | tolerance (f32 bits) |
| 0x0BE0 | language (1, section 5.6) | | |

Other offsets of the block are reported as they change; their meaning is not specified here.

## 11. Streams

- STATE stream (STREAM, period p ms): a stream frame cmd 0x10 with the STATE record every p ms.
- MEASURE stream (MEASURE_STREAM): a stream frame cmd 0x22 with the MEASURE record for every new
  result (argument 0) or every p ms.
- Both run until stopped (STREAM 0, MEASURE_STREAM 0xFFFF) or the meter restarts; they pause while
  a screenshot capture runs. A frame without room in the send buffer is dropped and counted.
- A new result is detected each main-loop pass: the meter's new-result flag 0x20001200 was set in
  the previous pass and is 0 now, or \|Z\| or theta changed.
- Timing (measured on a meter, STATE stream at 20 ms, time field of the records): steady on one
  screen, every gap is the period (750 of 750 in 15 s). A screen change redraws the whole screen;
  the streams are also served from each display flush of the redraw, so a gap then is at most 90 ms
  (20 screen changes, 1659 records), and the next record follows sooner to keep the period on
  average. A host should allow 100 ms plus the period between two records.

## 12. Screenshot

The meter has no frame buffer: its GUI draws into a 10-row buffer and flushes finished rectangles
to the panel. A capture asks the GUI to redraw one band of 10 rows at a time and copies every flush
that falls into that band, as the panel gets it, into stream frames cmd 0x60.

- Pixel frame: band u8, offset u16, x1, y1, x2, y2 (i16 each: the flushed rectangle with its rows
  clipped to the band), then up to 240 RGB565 values u16 as written to the panel. `offset` is the
  index of the first value in the rectangle, row-major with width x2 - x1 + 1: value k of the frame
  belongs to x = x1 + (offset + k) mod width, y = y1 + (offset + k) div width.
- Band end frame: band u8, offset 0xFFFF, 0, 10 x band, 319, 10 x band + 9, result u8 (12 bytes):
  0 done (all 10 rows arrived in full-width pieces), 1 no room (a frame did not fit the send
  buffer: the band ends at once), 2 no refresh (no complete redraw after 3 requests of 250 ticks
  each).
- Per band the meter first waits until 6914 bytes of the send buffer are free (the whole band with
  framing), then requests the redraw. A host that does not read for 2000 ticks, or clears DTR,
  stops the capture without an end frame.
- A band may show content drawn later than an earlier band; within a band a later frame for the
  same pixel is the newer one.
- During a capture no request is parsed, the streams pause and events wait in a queue of 16 (sent
  after the capture; beyond 16 they are dropped and counted).
- Procedure: SCREENSHOT 0xFF, read until the 24 end frames arrived; then SCREENSHOT n for every
  band whose result was not 0 or whose end frame is missing (`tools/lc1020e.py screenshot` does
  this, three rounds, and writes a PNG). The values are exactly what the firmware writes to the
  panel (set up with pixel format 0x05: 16 bits per pixel); the tool decodes bits 15..11 as red,
  10..5 as green and 4..0 as blue.

## 13. Updates

### 13.1 Application

1. INFO (note the running slot and version) and check the .uf2: 512-byte UF2 blocks, family ID
   0xC6B3602B, 256-byte payloads for 0x08006000..0x08061FFF (`tools/bin2uf2.py` makes such a file).
2. UPDATE_MODE. Status 6: the slot bootloader that starts next has a version below 2 and would not
   take the request; nothing was changed. Status 0: the meter restarts into the slot bootloader's
   update mode and stays on (section 7.6); the serial port disappears.
3. The update drive appears (USB mass storage; the volume label entry of its root directory is
   "LC1020E-IAP", and the root holds a file Ready.TXT). Copy the .uf2 onto it as an ordinary file and flush it to the device. Every 512-byte UF2
   block is programmed wherever it lands, so the file name, write order and extra files of the host
   do not matter. On macOS a copy that writes extended attributes leaves a "._" companion file;
   it is ignored, but a plain write of the file data is enough.
4. The slot bootloader checks the CRC-32 of the whole image, writes the application's vector page
   last, waits about 1 s and restarts (section 7.6, the meter stays on). An interrupted or failed update leaves the meter in update
   mode: copy the file again.
5. Wait for the serial port (same serial number) and read INFO: last update result 1.

### 13.2 Bootloader slots (BOOT_*)

The starter (flash page 0) starts one of three slot bootloaders: F (factory, fallback, never
written over USB), A or B. Only the free slot can be written: the one of A / B that is not the
newest slot recorded OK; when neither has an OK record, A unless the newest record names A, then B.

1. BOOT_STATUS: note the free slot f (1 A at 0x0806F000, 2 B at 0x08075000).
2. Check the slot file (header 0x200 bytes + image, as `tools/slot_header.py` makes it): its header
   link address (word +16) must be the free slot's base + 0x200; a file linked for the other slot
   cannot run there and is refused before anything is written. The tool also runs BOOT_END's checks
   on the file.
3. BOOT_BEGIN f, file length, CRC-32 of the file (up to 10 s: 12 page erases).
4. BOOT_DATA in chunks of 256 bytes from offset 0.
5. BOOT_END (the version is returned).
6. BOOT_INSTALL: an INSTALL record is appended, the meter restarts (section 7.6). The starter starts the new slot on
   trial; the slot confirms itself (OK record) when it starts. A slot that never confirms is
   replaced at a later start by the newest confirmed slot or F.
7. Wait for the port, then BOOT_STATUS and INFO: running slot f (with a version-2 slot), newest
   record slot f state OK.

An interruption before BOOT_INSTALL leaves the records unchanged; the procedure starts again with
BOOT_STATUS and BOOT_BEGIN (the free slot is erased and written again).

## 14. Capability bits and versioning

INFO bits (bits 0..19 and 21..27 set in this firmware, 0x0FEFFFFF): 0 STATE / STREAM, 1 SCREEN, 2 KEY,
3 LCR_TABLES / LCR_SET, 4 MEASURE / MEASURE_STREAM, 5 COMPARE / COMPARE_SET, 6 HOLD, 7 CALIBRATE,
8 SETTINGS_TABLES / SET / SAVE, 9 CAL_READ, 10 SCREENSHOT, 11 MEM_READ, 12 events, 13 UPDATE_MODE,
14 BOOT_*, 15 BATTERY, 16 POWER_OFF, 17 RESTORE_DEFAULTS, 18 settings recovery (SETTINGS_RESTORE_B,
ACCEPT_A, ACCEPT_B, ACCEPT_DEFAULTS, WRITE_BLOCK), 19 FACTORY_MODE; bit 20 (SETUP_LANGUAGE) is
clear: English only (section 5.6); 21 direct set: SCREEN, LCR_SET, HOLD, SETTINGS_SET and
COMPARE_SET set the value directly (sections 4.1, 4.3, 5.3.4; requests and answer records are the
same as without the bit, so the protocol version stays 1). A host waits the answer times of
section 4.3 by this bit: firmware without it runs these commands as jobs of key presses.
22 60 Hz: frequency index 5 of LCR_TABLES / LCR_SET (the frequency key cycles 60 -> 100 -> 120 ->
1k -> 10k -> 100k -> 60; 60 Hz is never saved: the copies hold 100 and the meter starts at 100 Hz).
23 TOLERANCE_SET and the COMPARE tail (offsets 29..49, section 5.3.5). 24 the MEASURE marker byte
64, the display rules of its value texts (section 6.2) and the save result 9 (section 9.1).
25 the calibration sweep of section 5.3.3: CALIBRATE answers 8 bytes (failed point and reason),
waits up to 360 000 ms in the meter, and the CALIBRATION step counts windows and points.
26 the own calibration area: OCAL_INFO .. OCAL_TRACE and MONITOR (section 5.7), event OCAL_CHANGED, the MEASURE OCAL flags byte 65 (section 16).
27 the start-up diagnostics: INFO bytes 46..57 (the previous start's progress word, this start's,
RCC_CTRLSTS as read at start; section 6.4), and the update result kept until an INFO answer is
queued (section 6.4).

Rules: the protocol version changes only when the frame format or the meaning of an existing field
changes. Within a version, records and answers grow only at the end, new commands and events get
new numbers and a capability bit; hosts ignore unknown trailing bytes and unknown events and test
the capability bit before using a command.

## 15. Worked examples

Frames in hex, as on the wire (CRC last, low byte first).

| Frame | Bytes |
|---|---|
| INFO request, seq 0x01 | `a5 03 00 01 01 00 df fb` |
| PING request 01 02 03, seq 0x02 | `a5 06 00 02 01 01 01 02 03 61 87` |
| PING answer (status 0, 01 02 03), seq 0x02 | `a5 07 00 02 02 01 00 01 02 03 1a 89` |
| STATE request, seq 0x03 | `a5 03 00 03 01 10 8e 87` |
| KEY bit 10 (0x0400: hold on / off), short, seq 0x04 | `a5 06 00 04 01 13 0a 00 00 bf 5a` |
| KEY bit 3 (0x0008), hold 1500 ms, seq 0x05 | `a5 06 00 05 01 13 03 dc 05 61 81` |
| STREAM every 1000 ms, seq 0x06 | `a5 05 00 06 01 11 e8 03 73 ee` |
| MEASURE_STREAM every new result, seq 0x07 | `a5 05 00 07 01 23 00 00 9f 46` |
| SETTINGS_SAVE (confirmation 4B 4F), seq 0x08 | `a5 05 00 08 01 52 4b 4f 43 a4` |
| CAL_READ copy A, offset 0, 256 bytes, seq 0x09 | `a5 08 00 09 01 53 00 00 00 00 01 4f e4` |
| CALIBRATE short (type 0, confirmation), seq 0x0A | `a5 06 00 0a 01 27 00 4b 4f d8 93` |
| POWER_OFF (confirmation 46 4F), seq 0x0B | `a5 05 00 0b 01 05 46 4f 93 e7` |
| SCREENSHOT all bands, seq 0x0C | `a5 04 00 0c 01 60 ff 69 65` |
| answer to an unknown command 0x7F (status 1), seq 0x0D | `a5 04 00 0d 02 7f 01 11 57` |
| SCREEN_CHANGED event (screen 2, previous 1), running seq 0x00 | `a5 05 00 00 04 91 02 01 d2 7b` |

Reading the first one: `a5` sync, `03 00` length 3 (seq, type, cmd, no payload), `01` seq, `01`
request, `00` INFO, `df fb` CRC-16 0xFBDF over `03 00 01 01 00`.

## 16. Own calibration area (capability bit 26)

OWN_CAL_DESIGN.md revision 3. Flash 0x08062000..0x08065FFF, two slots of 0x2000 bytes (slot 0 at
0x08062000, slot 1 at 0x08064000), written by nothing but the application's ocal.s through the
settings gate; neither bootloader, the starter nor V1.1 reach it. With both slots erased or
invalid every reading is the one without the area.

### 16.1 Record

Header (0x40 bytes): magic u32 0x4C41434F ("OCAL"), format u16 = 1, header size u16 = 0x40,
length u32 (header + body, 0x40..0x2000, a multiple of 4), sequence u32 (1..0xFFFFFFFE), chip UID
3 x u32 (the serial, 0x1FFFF7F0), short / open CRC u32 (CRC-32 of the user table's short and open
entries at the write: for each of the 15 points the magnitude of type 0, of type 11, the phase of
type 0, of type 11), reserved 0x20..0x37 = 0, revoke word u32 at 0x38 (0xFFFFFFFF in force, any
other value revoked; not in the CRC), CRC-32 u32 at 0x3C over bytes 0x00..0x37 and 0x40..length-1
(written last). The meter fills the whole header; the host sends the body only.

Body: sections {id u16, length u16, body}, ids strictly ascending, each length a multiple of 4:

| Id | Section | Body | Without it |
|---|---|---|---|
| 0 | META | host time u32 (Unix seconds), note 28 bytes ASCII, zero-padded (32) | - |
| 1 | GAIN | per frequency index fi 0..5 (100, 120, 1000, 10000, 100000, 60 Hz): zeta magnitude mask u32 (bit 8 c8 + c6), zeta phase mask u32, nu magnitude mask u8 (bit c5), nu phase mask u8, pad u16 = 0, zeta[c8][c6] 32 x (re f32, im f32), nu[c5] 8 x (re, im): 332 bytes, 1992 in all | no correction |
| 2 | CLIP | [channel 0 V, 1 I][gain code 0..7] {lo u16, hi u16} (64) | lo 0, hi 4095 |
| 3 | SETTLE | [kind 0 restart, 1 frequency, 2 level, 3 bias, 4 speed, 5 screen, 6 range or gain code][fi] u16 ms (84) | 26 ms for kinds 0..4, 5 ms for 5, 6 |
| 4 | MONITOR | mask u32 (bit fi), kV[6] f32 (V rms per count of peak amplitude at V gain 1) (28) | uncalibrated |
| 5 | BIAS | DC-midpoint limit u16 counts, pad u16 = 0 (4) | 4 counts |

Other ids are skipped by this firmware (format stays 1). Value rules (the meter checks them at
the write, status 2 with the section and entry, and at every start, where a failing section keeps
its default): GAIN pad 0; every factor with a mask bit: re and im finite, 0.25 <= re^2 + im^2 <= 4,
re > 0, 4 re^2 >= re^2 + im^2 (entry index 41 fi + k: k 0..31 zeta, 32..39 nu, 40 the pad);
CLIP hi <= 4095, lo < hi, hi - lo > 3600 (index 8 channel + code); SETTLE 1..500 (index 6 kind +
fi); MONITOR mask bits 0..5 only (index 6), each kV with its bit finite and 1e-6..1 (index fi);
BIAS 1..4095, pad 0 (index 0 / 1). A structure fault (a header crossing the end: id 0xFF, a
length past the end, ids not ascending, a known id with another length) gives index 0xFFFF.

The gain is applied to a reading only when the cell (c8, c6, c5) of the window has all four mask
bits: Z = K zeta[fi][c8][c6] nu[fi][c5] sum V' / sum I'; the vendor decade interpolation and the
S4.2 (K) references are then skipped, the short subtraction and the open / short compensation stay.

### 16.2 OCAL_INFO (64 bytes)

flags u32 (bit 0 a record active, 1 slot 0 CRC-valid, 2 slot 1 CRC-valid, 3 a newer own record of
another format in force (none applied), 4 a CRC-valid record of another meter (UID), 5 a section
rejected or the section walk stopped, 6 OF_RETAKE: the active GAIN was written with the short /
open entries still the same (take them again), 7 OCAL_LOCK, 8 an OCAL_WRITE transfer open, 9 the
trace not idle), active slot u8 (0xFF none), format u8, active length u16, active sequence u32,
other slot's sequence u32 (0 when CRC-invalid; with no active record the higher CRC-valid
sequence of both slots), active CRC u32, sections present u8 (bit = id), gain frequencies u8 (bit
fi: some cell with all four bits), monitor frequencies u8, sections rejected u8, T_max u16 (the
longest settle in use, at least 26 ms), pad u16, META time u32, META note 28 bytes, pad 4.

Choice of the active record at every start and after every write: the own records (this chip's
UID) in force; the higher sequence wins (slot 0 on equal ones); of format 1 it is active, of
another format none is (flag 3).

### 16.3 OCAL_LOCK, OCAL_RAW

OCAL_LOCK fixes the codes c5 (V gain), c6 (I gain), c8 (range): the ranging calls stop and the
codes are set at the next acquisition (a settle of kind 6 follows). Released by FF FF FF, any key
event that reaches the meter's key handler (physical or injected), a screen change, DTR clear or
a USB reset, a calibration start, the power-off path, and 30 s without OCAL_LOCK or OCAL_RAW.
LCR_SET keeps the lock (frequency, level, bias and speed are set, the settle of their kind runs);
LCR_SET of the range (id 5) answers status 3 while locked.

OCAL_RAW (64 bytes), taken at every window close, also under hold: window u32, c5 u8, c6 u8, c8
u8, lock u8, frequency u32, level f32, bias f32, N u16, class u8 (0 noise-limited, 1 resolved),
flags u8 (bit 0 a saturated acquisition since the previous close, bit 1 the overload set
published since then), Z_nom re f32, im f32 (K sum V' / sum I', no gain, no compensation; NaN for
sum I' = 0), A_V f32, A_I f32 (|sum V'| / (64 N), |sum I'| / (64 N): peak amplitude in counts),
sigma^2 V f32, sigma^2 I f32 (noise power of the last acquisition), ADC1 max / min / midpoint u16,
ADC2 max / min / midpoint u16 (of the last acquisition), pad 4.

### 16.4 OCAL_WRITE, OCAL_ROLLBACK

A chunk at offset 0 starts a new transfer; another chunk must start at the offset the previous
answer named and carry the same total and CRC-32, else status 2 (no data) and the transfer stays
as it was; a chunk ending beyond the total: status 2. With the last chunk: CRC-32 of the body
(status 7), the structure and value rules (status 2 with data: section id u8 and entry index u16,
the only status-2 answer with data), then the refusals, then the commit. Refusals of the last
chunk and of OCAL_ROLLBACK, in this order, nothing written: 3 powered-off mode or the power-off
path ran; 6 a calibration runs (0x200050E4 != 0) or the CALIBRATE job is active; 4 another job
runs (BOOT_BEGIN's erase included) or a rewrite of copy A is pending (flag 6 of section 9.1). A
refused last chunk leaves the transfer open at its offset.

Commit: the target slot is the one not active (with no active record: an empty or invalid slot,
else one of another meter, else a revoked one, else the lower sequence); sequence = the highest
CRC-valid one + 1 (status 3 when that cannot win: the other slot holds this meter's in-force
record with 0xFFFFFFFE). The target's pages are erased, the record programmed with the CRC word
last, read back, once more on a failure, then status 5 with the flash result (the previous record
still active). After a success the new record is the active one (else status 5, result 1), the
measurement restarts, and event OCAL_CHANGED follows. A power cut before the CRC word leaves the
previous record active; the record that a write replaces is never erased by that write.

Rollback: mode 0 programs the revoke word of the active record (the other slot's record becomes
active if it qualifies); mode 1 revokes every own format-1 record in force, the older first.
Revoked records are never brought back; a backup body is written again instead.

### 16.5 MONITOR

From the window MEASURE published last: A_V,ref = A_V |nu| / G[c5], A_I,ref = A_I / (G[c6] R[c8]
|zeta|) (G = 1, 2, .. 128 by code, R = 100 ohm .. 100 kohm by range; |nu| = |zeta| = 1 where the
gain was not applied); V rms = kV A_V,ref, I rms = kV A_I,ref = V / |Z| (Z before the open / short
compensation). V and I are NaN (0x7FC00000) without kV at the frequency or at a frequency outside
the six; all four are NaN with no reading or the overload set (flag bit 2). The midpoints are
counts only (no DC scale is claimed).
