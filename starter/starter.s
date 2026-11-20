@ starter.s - first stage of the two-part bootloader for the FNIRSI LC1020E (N32G455).
@
@ Lives in flash page 0 (0x08000000..0x080007FF) and is never changed by the meter itself. At every
@ reset it chooses one of three bootloader slots and starts it:
@
@   1. power latch PA8 high, so every flash write below runs with the power held;
@   2. fault flag: a start after a fault of this starter goes straight to slot F;
@   3. control records (two pages, 16-byte cells) give the active slot and its state;
@   4. INSTALL or OK with a good header -> that slot (INSTALL is first recorded as TRIAL);
@      TRIAL (started before, never confirmed) -> the newest other slot recorded OK with a good
@      header; anything else -> slot F (factory); F bad too -> wait with the power held (SWD);
@   5. lock the flash, VTOR = slot + 0x200, MSP and PC from that table, interrupts unmasked again
@      (the starter runs with PRIMASK set; the code it starts expects the reset state).
@
@ Flash writes: only appending a record and erasing the other record page when one is full; both
@ go through flash_erase / flash_word, which refuse every address outside the record pages.
@
@ Layout (flash):
@   0x08068000, 0x08068800   control record pages
@   0x08069000 slot F, 0x0806F000 slot A, 0x08075000 slot B (24 KiB each)
@ Slot header (slot start, 32 bytes used of 0x200):
@   +0 magic "SLOT" 0x544F4C53, +4 image length, +8 CRC-32 of the image, +12 version,
@   +16 link address (= slot + 0x200), +20 / +24 zero, +28 CRC-32 of bytes 0..27
@ Record cell (16 bytes):
@   +0 0x4C52 << 16 | slot << 8 | state  (slot 0 F, 1 A, 2 B; state 1 INSTALL, 2 TRIAL, 3 OK)
@   +4 version, +8 sequence number (starts at 1), +12 CRC-32 of bytes 0..11
@   An erased cell cannot be valid: its CRC word is 0xFFFFFFFF, the CRC-32 of twelve 0xFF bytes
@   is 0xBB99FF8A.
@
@ Registers (N32G45x user manual): RCC_APB2PCLKEN 0x40021018 bit 2 IOPAEN; GPIOA PH_CFG
@ 0x40010804 (pin 8 = bits 3:0), PBSC 0x40010810; FLASH KEY 0x40022004, STS 0x4002200C (BUSY
@ bit 0), CTRL 0x40022010 (PG bit 0, PER bit 1, START bit 6, LOCK bit 7), ADD 0x40022014;
@ VTOR 0xE000ED08, AIRCR 0xE000ED0C.

        .syntax unified
        .cpu    cortex-m4
        .thumb

        .equ    RCC_APB2PCLKEN, 0x40021018
        .equ    GPIOA_PH_CFG,   0x40010804
        .equ    GPIOA_PBSC,     0x40010810
        .equ    FLASH_KEY,      0x40022004
        .equ    FLASH_STS,      0x4002200C
        .equ    FLASH_CTRL,     0x40022010
        .equ    FLASH_ADD,      0x40022014
        .equ    KEY1,           0x45670123
        .equ    KEY2,           0xCDEF89AB
        .equ    VTOR,           0xE000ED08
        .equ    AIRCR,          0xE000ED0C
        .equ    AIRCR_RESET,    0x05FA0004

        .equ    REC0,           0x08068000
        .equ    REC1,           0x08068800
        .equ    REC_END,        0x08069000
        .equ    PAGE,           0x800
        .equ    SLOT_F,         0x08069000
        .equ    SLOT_A,         0x0806F000
        .equ    SLOT_B,         0x08075000
        .equ    HDR_MAGIC,      0x544F4C53
        .equ    REC_TAG,        0x4C52
        .equ    ROOM,           0x5E00
        .equ    ST_INSTALL,     1
        .equ    ST_TRIAL,       2
        .equ    ST_OK,          3

        .equ    SRAM_LO,        0x20000000
        .equ    SRAM_HI,        0x20024000
        .equ    STACK_TOP,      0x20002000
        .equ    FLAG,           0x2001FFF0      @ last words of main SRAM: used by neither the
                                                @ slots (below 0x20002B00) nor V1.1 (below
                                                @ 0x200163A8), not retention SRAM
        .equ    FLAG_MAGIC,     0x464C5446
        .equ    TAB,            0x20000000      @ 3 x {seq, state, version, cell address}
        .equ    CELL,           0x20000030      @ record being written (4 words)

        .text
@ ---- vector table (16 words); every exception except reset goes to fault ----
vectors:
        .word   STACK_TOP
        .word   reset
        .rept   14
        .word   fault
        .endr

@ ---- reset ----
        .global reset
        .thumb_func
reset:
        cpsid   i
        ldr     r0, =STACK_TOP
        msr     msp, r0
        bl      latch_power

        @ fault flag: consumed here; set means the previous start faulted -> slot F
        ldr     r0, =FLAG
        ldr     r1, [r0]
        movs    r2, #0
        str     r2, [r0]
        ldr     r2, =FLAG_MAGIC
        cmp     r1, r2
        beq     use_f

        bl      scan_records            @ r0 = slot of the newest record, or -1
        cmp     r0, #0
        blt     use_f
        mov     r4, r0                  @ r4 = active slot
        ldr     r5, =TAB
        add     r5, r5, r4, lsl #4      @ r5 = its table entry
        ldr     r6, [r5, #4]            @ r6 = its state
        cmp     r6, #ST_TRIAL
        beq     trial_fallback
        mov     r0, r4
        bl      slot_base
        mov     r7, r0                  @ r7 = slot base
        bl      header_ok
        cmp     r0, #0
        beq     use_f
        cmp     r6, #ST_INSTALL
        bne     start_slot
        mov     r0, r4
        movs    r1, #ST_TRIAL
        ldr     r2, [r5, #8]
        bl      append_record
        b       start_slot

        @ active slot is TRIAL: the newest other slot recorded OK whose header checks
trial_fallback:
        movs    r8, #0                  @ best sequence number so far
        mov     r9, #-1                 @ best slot so far
        movs    r10, #0                 @ slot index i
2:      cmp     r10, r4
        beq     3f
        ldr     r5, =TAB
        add     r5, r5, r10, lsl #4
        ldr     r1, [r5, #4]
        cmp     r1, #ST_OK
        bne     3f
        ldr     r1, [r5, #0]
        cmp     r1, r8
        bls     3f
        mov     r0, r10
        bl      slot_base
        bl      header_ok
        cmp     r0, #0
        beq     3f
        ldr     r8, [r5, #0]
        mov     r9, r10
3:      add     r10, r10, #1
        cmp     r10, #3
        blo     2b
        cmp     r9, #0
        blt     use_f
        mov     r0, r9
        bl      slot_base
        mov     r7, r0
        b       start_slot

use_f:
        ldr     r7, =SLOT_F
        mov     r0, r7
        bl      header_ok
        cmp     r0, #0
        beq     dead_end

        @ r7 = slot base: lock the flash, VTOR = slot + 0x200, MSP / PC from that table
start_slot:
        ldr     r0, =FLASH_CTRL
        movs    r1, #0x80
        str     r1, [r0]
        add     r7, r7, #0x200
        ldr     r0, =VTOR
        str     r7, [r0]
        dsb
        isb
        ldr     r0, [r7, #0]
        ldr     r1, [r7, #4]
        msr     msp, r0
        cpsie   i                       @ hand over with interrupts unmasked, as after a reset
        bx      r1

        @ no slot can be started: keep the power held so that SWD reaches the chip
dead_end:
        b       dead_end

@ ---- fault: mark the fault for the next start and reset ----
        .thumb_func
fault:
        ldr     r0, =FLAG
        ldr     r1, =FLAG_MAGIC
        str     r1, [r0]
        dsb
        ldr     r0, =AIRCR
        ldr     r1, =AIRCR_RESET
        str     r1, [r0]
        dsb
4:      b       4b

@ ---- latch_power: GPIOA clock on, PA8 output register high, then PA8 push-pull output ----
        .thumb_func
latch_power:
        ldr     r0, =RCC_APB2PCLKEN
        ldr     r1, [r0]
        orr     r1, r1, #4
        str     r1, [r0]
        ldr     r0, =GPIOA_PBSC
        mov     r1, #0x100
        str     r1, [r0]
        ldr     r0, =GPIOA_PH_CFG
        ldr     r1, [r0]
        bic     r1, r1, #0xF
        orr     r1, r1, #0x3
        str     r1, [r0]
        bx      lr

@ ---- slot_base: r0 = slot index 0..2 -> r0 = slot base address ----
        .thumb_func
slot_base:
        ldr     r1, =SLOT_F
        mov     r2, #0x6000
        mla     r0, r0, r2, r1
        bx      lr

@ ---- crc32: r0 = address, r1 = byte count (> 0) -> r0 = CRC-32 (zlib); uses r2, r3, r12 ----
        .thumb_func
crc32:
        push    {r4, r5}
        mov     r2, r0
        mvn     r0, #0
        ldr     r4, =0xEDB88320
5:      ldrb    r3, [r2], #1
        eors    r0, r0, r3
        movs    r5, #8
6:      lsrs    r0, r0, #1
        it      cs
        eorcs   r0, r0, r4
        subs    r5, r5, #1
        bne     6b
        subs    r1, r1, #1
        bne     5b
        mvns    r0, r0
        pop     {r4, r5}
        bx      lr

@ ---- header_ok: r0 = slot base -> r0 = 1 when the slot may be started, else 0 ----
@ magic, header CRC, link address = base + 0x200, 8 <= length <= ROOM and a multiple of 4,
@ image CRC, SP inside SRAM, reset vector odd and inside the image.
        .thumb_func
header_ok:
        push    {r4, r5, lr}
        mov     r4, r0
        ldr     r1, [r4, #0]
        ldr     r2, =HDR_MAGIC
        cmp     r1, r2
        bne     8f
        mov     r0, r4
        movs    r1, #28
        bl      crc32
        ldr     r1, [r4, #28]
        cmp     r0, r1
        bne     8f
        ldr     r1, [r4, #16]
        add     r5, r4, #0x200          @ r5 = image start
        cmp     r1, r5
        bne     8f
        ldr     r1, [r4, #4]            @ length
        cmp     r1, #8
        blo     8f
        cmp     r1, #ROOM
        bhi     8f
        tst     r1, #3
        bne     8f
        mov     r0, r5
        bl      crc32
        ldr     r1, [r4, #8]
        cmp     r0, r1
        bne     8f
        ldr     r1, [r5, #0]            @ initial SP
        ldr     r2, =SRAM_LO
        cmp     r1, r2
        bls     8f
        ldr     r2, =SRAM_HI
        cmp     r1, r2
        bhi     8f
        ldr     r1, [r5, #4]            @ reset vector
        tst     r1, #1
        beq     8f
        bic     r1, r1, #1
        cmp     r1, r5
        blo     8f
        ldr     r2, [r4, #4]
        add     r2, r2, r5
        cmp     r1, r2
        bhs     8f
        movs    r0, #1
        pop     {r4, r5, pc}
8:      movs    r0, #0
        pop     {r4, r5, pc}

@ ---- cell_valid: r0 = cell address -> r0 = 1 when tag and CRC match, else 0 ----
        .thumb_func
cell_valid:
        push    {r4, lr}
        mov     r4, r0
        ldr     r1, [r4, #0]
        lsrs    r1, r1, #16
        movw    r2, #REC_TAG
        cmp     r1, r2
        bne     9f
        movs    r1, #12
        bl      crc32
        ldr     r1, [r4, #12]
        cmp     r0, r1
        bne     9f
        movs    r0, #1
        pop     {r4, pc}
9:      movs    r0, #0
        pop     {r4, pc}

@ ---- scan_records: fill TAB with the newest valid record of each slot ----
@ returns r0 = slot of the newest record over both pages, or -1 when there is none
        .thumb_func
scan_records:
        push    {r4, r5, r6, r7, lr}
        ldr     r0, =TAB
        movs    r1, #0
        movs    r2, #12
10:     str     r1, [r0], #4
        subs    r2, r2, #1
        bne     10b
        ldr     r4, =REC0               @ r4 = cell address
11:     mov     r0, r4
        bl      cell_valid
        cmp     r0, #0
        beq     12f
        ldr     r1, [r4, #0]
        ubfx    r5, r1, #8, #8          @ r5 = slot
        uxtb    r6, r1                  @ r6 = state
        cmp     r5, #3
        bhs     12f
        cmp     r6, #ST_INSTALL
        blo     12f
        cmp     r6, #ST_OK
        bhi     12f
        ldr     r7, =TAB
        add     r7, r7, r5, lsl #4
        ldr     r1, [r4, #8]            @ sequence number
        ldr     r2, [r7, #0]
        cmp     r1, r2
        bls     12f
        str     r1, [r7, #0]
        str     r6, [r7, #4]
        ldr     r1, [r4, #4]
        str     r1, [r7, #8]
        str     r4, [r7, #12]
12:     adds    r4, r4, #16
        ldr     r1, =REC_END
        cmp     r4, r1
        blo     11b
        @ newest over the three slots
        mov     r0, #-1
        movs    r1, #0                  @ best sequence
        movs    r2, #0                  @ i
        ldr     r3, =TAB
13:     add     r12, r3, r2, lsl #4
        ldr     r12, [r12, #0]
        cmp     r12, r1
        bls     14f
        mov     r1, r12
        mov     r0, r2
14:     adds    r2, r2, #1
        cmp     r2, #3
        blo     13b
        pop     {r4, r5, r6, r7, pc}

@ ---- append_record: r0 = slot, r1 = state, r2 = version ----
@ Writes the next record after the last used cell of the page holding the newest record; when that
@ page has no free cell, erases the other page and writes the record as its first cell. The cell
@ is read back; when it differs, the record is written again in the next free cell (three
@ attempts in all). Called only when a record exists (TAB has a cell address).
        .thumb_func
append_record:
        push    {r4, r5, r6, r7, r8, lr}
        ldr     r4, =CELL
        movw    r3, #REC_TAG
        orr     r3, r1, r3, lsl #16
        orr     r3, r3, r0, lsl #8
        str     r3, [r4, #0]
        str     r2, [r4, #4]
        @ sequence = highest + 1; r6 = cell address of the newest record
        ldr     r3, =TAB
        movs    r5, #0
        movs    r6, #0
        movs    r7, #0
15:     add     r2, r3, r7, lsl #4
        ldr     r1, [r2, #0]
        cmp     r1, r5
        bls     16f
        mov     r5, r1
        ldr     r6, [r2, #12]
16:     adds    r7, r7, #1
        cmp     r7, #3
        blo     15b
        adds    r5, r5, #1
        str     r5, [r4, #8]
        mov     r0, r4
        movs    r1, #12
        bl      crc32
        str     r0, [r4, #12]
        @ page of the newest record; free cell above its last used cell
        bic     r6, r6, #0x7F0
        bic     r6, r6, #0xF            @ r6 = page base
        mov     r8, #3                  @ write attempts; a cell that fails its read-back
                                        @ stays used (not all 0xFF) and fails its CRC
60:     mov     r5, r6                  @ r5 = first cell above the last used one
        mov     r7, r6                  @ r7 = cell being looked at
17:     ldm     r7, {r0, r1, r2, r3}
        and     r0, r0, r1
        and     r2, r2, r3
        and     r0, r0, r2
        adds    r0, r0, #1              @ zero only when all four words are 0xFFFFFFFF
        beq     18f
        add     r5, r7, #16
18:     adds    r7, r7, #16
        add     r1, r6, #PAGE
        cmp     r7, r1
        blo     17b
        add     r1, r6, #PAGE
        cmp     r5, r1
        blo     19f
        @ page full: erase the other page and write there first
        ldr     r1, =REC0
        cmp     r6, r1
        ite     eq
        ldreq   r5, =REC1
        ldrne   r5, =REC0
        mov     r0, r5
        bl      flash_erase
19:     bl      flash_unlock
        movs    r7, #0
20:     add     r0, r5, r7
        ldr     r1, [r4, r7]
        bl      flash_word
        adds    r7, r7, #4
        cmp     r7, #16
        blo     20b
        ldr     r0, =FLASH_CTRL
        movs    r1, #0x80
        str     r1, [r0]
        @ read back the cell; on a difference write the record again in the next free cell
        movs    r7, #0
61:     ldr     r0, [r5, r7]
        ldr     r1, [r4, r7]
        cmp     r0, r1
        bne     62f
        adds    r7, r7, #4
        cmp     r7, #16
        blo     61b
        b       63f
62:     subs    r8, r8, #1
        bne     60b
63:     pop     {r4, r5, r6, r7, r8, pc}

@ ---- flash primitives; every address outside REC0..REC_END is refused ----
        .thumb_func
flash_unlock:
        ldr     r0, =FLASH_KEY
        ldr     r1, =KEY1
        str     r1, [r0]
        ldr     r1, =KEY2
        str     r1, [r0]
        bx      lr

        .thumb_func
flash_wait:
        ldr     r2, =FLASH_STS
21:     ldr     r3, [r2]
        tst     r3, #1
        bne     21b
        movs    r3, #0xFC               @ clear EOP and the error flags (write 1 to clear)
        str     r3, [r2]
        bx      lr

@ flash_erase: r0 = page base inside the record pages
        .thumb_func
flash_erase:
        push    {r4, lr}
        mov     r4, r0
        ldr     r1, =REC0
        cmp     r4, r1
        blo     22f
        ldr     r1, =REC_END
        cmp     r4, r1
        bhs     22f
        bl      flash_unlock
        bl      flash_wait
        ldr     r0, =FLASH_CTRL
        movs    r1, #0x02
        str     r1, [r0]
        ldr     r1, =FLASH_ADD
        str     r4, [r1]
        movs    r1, #0x42
        str     r1, [r0]
        bl      flash_wait
        ldr     r0, =FLASH_CTRL
        movs    r1, #0x80
        str     r1, [r0]
22:     pop     {r4, pc}

@ flash_word: r0 = word address inside the record pages, r1 = value (flash already unlocked)
        .thumb_func
flash_word:
        push    {r4, r5, lr}
        mov     r4, r0
        mov     r5, r1
        ldr     r1, =REC0
        cmp     r4, r1
        blo     23f
        ldr     r1, =REC_END
        cmp     r4, r1
        bhs     23f
        bl      flash_wait
        ldr     r0, =FLASH_CTRL
        movs    r1, #0x01
        str     r1, [r0]
        str     r5, [r4]
        nop                             @ five NOPs after the store: no flash read while
        nop                             @ the word programs (N32G45x user manual 3.2.1.4.2)
        nop
        nop
        nop
        bl      flash_wait
        ldr     r0, =FLASH_CTRL
        movs    r1, #0x00
        str     r1, [r0]
23:     pop     {r4, r5, pc}

        .ltorg
