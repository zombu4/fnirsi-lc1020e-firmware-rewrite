@ slot.inc - constants of the slot build of the bootloader (make slot), included under .ifdef SLOT.
@ Part of the FNIRSI LC1020E firmware rewrite (assembly).
@
@ Flash layout (the starter's, starter/starter.s):
@   0x08000000 page 0     starter
@   0x08006000..0x08061FFF application (vector page 0x08006000..0x080067FF)
@   0x08068000, 0x08068800 control record pages
@   0x08069000 slot F, 0x0806F000 slot A, 0x08075000 slot B (24 KiB each, header + image)
@   0x0807F000..0x0807FFFF settings / calibration of the application: never written here
@ SLOT_INDEX (0 F, 1 A, 2 B) comes from the command line (--defsym), one build per slot.

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
