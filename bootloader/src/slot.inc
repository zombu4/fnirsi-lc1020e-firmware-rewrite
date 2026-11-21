@ slot.inc - constants of the slot build of the bootloader (make slot), included under .ifdef SLOT.
@ Part of the FNIRSI LC1020E firmware rewrite (assembly).
@
@ Flash layout (the starter's, starter/starter.s):
@   0x08000000 page 0     starter
@   0x08006000..0x08061FFF application (vector page 0x08006000..0x080067FF)
@   0x08066000..0x08066FFF settings copy B of our application (SETTINGS_SAVE_DESIGN.md):
@                          never written here
@   0x08068000, 0x08068800 control record pages
@   0x08069000 slot F, 0x0806F000 slot A, 0x08075000 slot B (24 KiB each, header + image)
@   0x0807F000..0x0807FFFF settings / calibration of the application (copy A): never written here
@ The flash gate (flash_gate, rec_flash_*) admits 0x08006000..0x08061FFF and the record pages only.
@ SLOT_INDEX (0 F, 1 A, 2 B) comes from the command line (--defsym), one build per slot.
@ Feature version 2 (header word +12, bootloader/Makefile SLOT_VERSION): update request word,
@ hand-over word, result word, the watchdog of a trial start and the feeds of the update path.

        .equ    APP_BASE,       0x08006000      @ application vector table
        .equ    APP_VEC_END,    0x08006800      @ end of the application vector page
        .equ    APP_END,        0x08062000      @ end of the application area (exclusive)
        .equ    FLASH_PAGE,     0x800           @ erase unit (2 KiB)
        .equ    REC0,           0x08068000      @ control record page 0
        .equ    REC1,           0x08068800      @ control record page 1
        .equ    REC_END,        0x08069000      @ end of the record pages (exclusive)
        .equ    REC_TAG,        0x4C52          @ record word 0 bits 31..16
        .equ    ST_INSTALL,     1               @ record states
        .equ    ST_TRIAL,       2
        .equ    ST_OK,          3

        .equ    SRAM_LO,        0x20000000      @ an initial SP must lie above this ...
        .equ    SRAM_HI,        0x20024000      @ ... and at most here
        .equ    FAULT_FLAG,     0x2001FFF0      @ the starter's fault flag (no-init word,
                                                @ outside every stack and data area)
        .equ    FAULT_MAGIC,    0x464C5446      @ value that sends the next start to slot F
        .equ    AIRCR,          0xE000ED0C
        .equ    AIRCR_RESET,    0x05FA0004      @ register key and SYSRESETREQ

@ No-init words at the top of main SRAM, outside every region a start code clears or uses
@ (starter: 0x20000000..0x2000003F and FAULT_FLAG; slot: stack below 0x20002028, RAM
@ 0x20002100..0x20002AFF; application: 0x2000057C..0x200163A7 and the 0x4BA4 bytes from
@ 0x2000057C). Absolute addresses, never in a section.
        .equ    REQ_WORD,       0x2001FFF4      @ update request, written by the application
        .equ    REQ_MAGIC,      0x55504454      @ "UPDT": this start enters update mode
        .equ    REQ_RESTART,    0x52535452      @ "RSTR": normal start after a soft restart
                                                @ (both values: the IWDG runs, WDG_ON = 1)
        .equ    HANDOVER_WORD,  0x2001FFF8      @ written before the application start
        .equ    HANDOVER_TAG,   0x534C0000      @ "SL" << 16; low byte = SLOT_INDEX
        .equ    RESULT_WORD,    0x2001FFFC      @ written before the restart after an update

@ Soft restart (slot_soft_restart, USB_CONTROL_DESIGN.md 6b): N32G45x user manual 6.3.9
@ (RCC_APB1PCLKEN USBEN bit 23), 19.5.3 (USB_CTRL 0x40005C40: FRST bit 0, PD bit 1), the D+
@ pull-up bit 28 of 0x40001820 (usb_09.s fn_08002c10 sets it); ARMv7-M NVIC ICER0..2 /
@ ICPR0..2 (IRQ 0..95, the vector table ends with IRQ 85), SysTick CTRL, ICSR (PENDSVCLR bit 27,
@ PENDSTCLR bit 25), VTOR.
        .equ    SR_APB1PCLKEN,  0x4002101C
        .equ    SR_USBEN,       0x00800000
        .equ    SR_USB_CTRL,    0x40005C40
        .equ    SR_USB_OFF,     0x0003          @ FRST | PD
        .equ    SR_PULLUP,      0x40001820
        .equ    SR_PULLUP_BIT,  0x10000000
        .equ    SR_ICER0,       0xE000E180
        .equ    SR_ICPR0,       0xE000E280
        .equ    SR_SYST_CSR,    0xE000E010
        .equ    SR_ICSR,        0xE000ED04
        .equ    SR_PEND_CLR,    0x0A000000
        .equ    SR_VTOR,        0xE000ED08
        .equ    SR_BOOT_SPACE,  0x00000000      @ boot space = main flash from 0x08000000: the
                                                @ starter's vector table (SP, reset entry)
        .equ    RESULT_TAG,     0x5552          @ "UR": tag << 16 | result << 8 | ~result & 0xFF
        .equ    RES_OK,         1               @ result: update written and checked

@ Independent watchdog (N32G45x user manual 16.5): KEY +0 (0x5555 unlocks PREDIV / RELV,
@ 0xAAAA reloads the counter, 0xCCCC starts it), PREDIV +4, RELV +8, STS +12 (PVU bit 0,
@ CRVU bit 1). The values of the application's own start (V1.1 0x08010178..0x08010198):
@ PREDIV 2 (LSI / 16), RELV 0x9C4 (2500): 2500 * 16 / 40 kHz = 1.0 s at the manual's LSI
@ frequency (16.1); USB_CONTROL_DESIGN.md section 6 works with 0.67 s as the shortest period.
        .equ    IWDG_KEY,       0x40003000
        .equ    IWDG_UNLOCK,    0x5555
        .equ    IWDG_RELOAD,    0xAAAA
        .equ    IWDG_START,     0xCCCC
        .equ    IWDG_PREDIV,    2
        .equ    IWDG_RELV,      0x9C4

        .equ    FLASH_KEY,      0x40022004      @ flash controller (N32G455)
        .equ    FLASH_STS,      0x4002200C      @ BUSY bit 0, flags 2..6 write 1 to clear
        .equ    FLASH_CTRL,     0x40022010      @ PG bit 0, PER bit 1, START bit 6, LOCK bit 7
        .equ    FLASH_ADD,      0x40022014
        .equ    KEY1,           0x45670123
        .equ    KEY2,           0xCDEF89AB

        .equ    DRIVE_SECTORS,  512             @ update drive: 512 sectors of 2048 bytes (1 MiB)

@ UF2 (512-byte blocks; words: 0 magic 0, 1 magic 1, 2 flags, 3 target address, 4 payload size,
@ 5 block number, 6 block count, 7 family ID; payload from byte 32; word 127 end magic)
        .equ    UF2_MAGIC0,     0x0A324655
        .equ    UF2_MAGIC1,     0x9E5D5157
        .equ    UF2_MAGIC_END,  0x0AB16F30
        .equ    UF2_FAMILY,     0xC6B3602B      @ family ID of the LC1020E application
        .equ    UF2_TAG,        0x45FB650C      @ extension tag word: size 12, type 0x45FB65
        .equ    UF2_MAX_BLOCKS, 1472            @ 0x5C000 / 256: the whole application area

@ RAM of the slot build, 0x20002100.. in main SRAM above the stock bootloader's RAM
@ (0x20000000..0x20002027); not set by the start-up code, cleared by uf2_init / rec_scan.
        .equ    TAB,            0x20002100      @ 3 x {sequence, state, version, cell address}
        .equ    CELL,           0x20002130      @ record being written (4 words)
        .equ    U_BASE,         0x20002140      @ UF2 transfer state, offsets below
        .equ    U_STATE,        0x00            @ 0 idle, 1 receiving, 2 written, 3 failed
        .equ    U_ERR,          0x04            @ error code of state 3 (ERR_*)
        .equ    U_NUM,          0x08            @ transfer key: block count
        .equ    U_LEN,          0x0C            @ transfer key: image length in bytes
        .equ    U_CRC,          0x10            @ transfer key: CRC-32 of the image
        .equ    U_COUNT,        0x14            @ blocks taken so far
        .equ    U_PAGES,        0x18            @ bitmap of erased pages, 184 bits (6 words)
        .equ    U_BLOCKS,       0x30            @ bitmap of taken blocks, 1472 bits (46 words)
        .equ    U_SIZE,         0xE8            @ bytes of the state (0x20002140..0x20002227)
        .equ    WDG_ON,         0x20002228      @ 0: no watchdog; 1: this start began it (trial
                                                @ start, slot_trial_wdg); 3: the request word was
                                                @ UPDT / RSTR (soft restart from the application,
                                                @ slot_key_check; bit 1 = hand-over bit 9).
                                                @ Cleared by slot_trial_wdg first thing in main;
                                                @ slot_feed feeds when it is not 0
        .equ    VBUF,           0x20002300      @ application vector page held in RAM (2 KiB)
        .equ    UST_IDLE,       0
        .equ    UST_RECEIVE,    1
        .equ    UST_DONE,       2
        .equ    UST_FAIL,       3
        .equ    ERR_ERASE,      1               @ a page did not read all 0xFF after its erase
        .equ    ERR_PROGRAM,    2               @ a word failed to program or read back
        .equ    ERR_CRC,        3               @ image CRC-32 differs from the transfer key
        .equ    ERR_VECTOR,     4               @ the vector page failed to program or read back
        .equ    BOOT_STATE,     0x20000274      @ stock state byte: 2 = finished, main resets
        .equ    STATUS_LEN,     32              @ size of Ready.TXT (the status text)
