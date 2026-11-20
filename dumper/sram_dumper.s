@ sram_dumper.s - LC1020E flash dumper.
@
@ Installed at 0x08006000 through the vendor update drive and started normally (no debugger
@ attached: under read protection L1 main flash is readable only by user code started from main
@ flash "in non debugging mode", user manual V3.5.0 p.58).  It
@   1. sets VTOR to its own table, holds the power latch PA8 high (main 0x08027FF4 sets PA8 with
@      0x08008350(0x40010800, 0x100, 1); the power-off path 0x0800B274 clears it),
@   2. copies the vendor bootloader 0x08000000..0x08005FFF and the drive + settings area
@      0x08068000..0x0807FFFF to SRAM, and the option bytes 0x1FFFF800..0x1FFFF80F,
@   3. stores the CRC-32 (zlib polynomial, read from flash itself) of each flash part,
@   4. moves a vector table and a wait loop into SRAM and runs only from there, so a debugger
@      connecting afterwards cannot stop it, and feeds the independent watchdog.
@ Nothing is written to flash.  SWD then reads the SRAM through the AHB access port.
@
@ SRAM layout:
@   0x20000000  vector table (16 words, all handlers -> ram_fault)      VTOR after step 4
@   0x20000040  wait loop and fault entry (copied from ram_code)
@   0x20001000  initial stack top (grows down; the dumper uses < 32 bytes)
@   0x20001000  copy of 0x08000000..0x08005FFF (0x6000 bytes)
@   0x20007000  copy of 0x08068000..0x0807FFFF (0x18000 bytes)
@   0x2001F000  result block:
@       +0x00  0x504D5544 "DUMP" when steps 1-3 are done (written last), 0x4C554146 "FAUL" after a fault
@       +0x04  CRC-32 of 0x08000000..0x08005FFF
@       +0x08  CRC-32 of 0x08068000..0x0807FFFF
@       +0x0C  CRC-32 of 0x08006000..0x08067FFF (the update area: this dumper and what lies after it)
@       +0x10  heartbeat, incremented by the wait loop
@       +0x20  option bytes 0x1FFFF800..0x1FFFF80F (4 words)
@
@ Registers (user manual V3.5.0): RCC_APB2PCLKEN 0x40021018 bit 2 IOPAEN (6.3.8); GPIOA
@ 0x40010800 (memory map), PH_CFG +0x04 pin 8 = bits 3:0, PBSC +0x10 (7.3.3, 7.3.6); IWDG_KEY
@ 0x40003000, 0xAAAA reloads the counter and does not start it (16.5.2); VTOR 0xE000ED08.

        .syntax unified
        .cpu    cortex-m4
        .thumb

        .equ    VTOR,           0xE000ED08
        .equ    RCC_APB2PCLKEN, 0x40021018
        .equ    GPIOA_PH_CFG,   0x40010804
        .equ    GPIOA_PBSC,     0x40010810
        .equ    IWDG_KEY,       0x40003000
        .equ    STACK_TOP,      0x20001000
        .equ    RAM_VECTORS,    0x20000000
        .equ    RAM_CODE,       0x20000040
        .equ    COPY_BOOT,      0x20001000
        .equ    COPY_HIGH,      0x20007000
        .equ    RESULT,         0x2001F000
        .equ    MAGIC_DONE,     0x504D5544
        .equ    MAGIC_FAULT,    0x4C554146

        .text
@ ---- flash vector table at 0x08006000 (16 words) ----
vectors:
        .word   STACK_TOP
        .word   reset
        .rept   14
        .word   flash_fault
        .endr

@ ---- reset handler ----
        .global reset
        .thumb_func
reset:
        cpsid   i
        ldr     r0, =VTOR
        ldr     r1, =vectors
        str     r1, [r0]
        ldr     r0, =STACK_TOP
        mov     sp, r0

        @ power latch: GPIOA clock on, PA8 output register high, then PA8 push-pull output
        @ (PMODE 10 = 10 MHz on this chip, manual GPIO table)
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
        orr     r1, r1, #0x2
        str     r1, [r0]

        @ copies
        ldr     r0, =0x08000000
        ldr     r1, =COPY_BOOT
        ldr     r2, =0x6000
        bl      copy_words
        ldr     r0, =0x08068000
        ldr     r1, =COPY_HIGH
        ldr     r2, =0x18000
        bl      copy_words
        ldr     r0, =0x1FFFF800
        ldr     r1, =RESULT + 0x20
        movs    r2, #16
        bl      copy_words

        @ CRCs from flash
        ldr     r4, =RESULT
        ldr     r0, =0x08000000
        ldr     r1, =0x6000
        bl      crc32
        str     r0, [r4, #4]
        ldr     r0, =0x08068000
        ldr     r1, =0x18000
        bl      crc32
        str     r0, [r4, #8]
        ldr     r0, =0x08006000
        ldr     r1, =0x62000
        bl      crc32
        str     r0, [r4, #12]
        movs    r0, #0
        str     r0, [r4, #16]
        ldr     r0, =MAGIC_DONE
        str     r0, [r4, #0]

        @ SRAM vector table: 16 words, word 0 = stack top, the rest -> ram_fault in SRAM
        ldr     r0, =RAM_VECTORS
        ldr     r1, =STACK_TOP
        str     r1, [r0], #4
        ldr     r1, =RAM_FAULT_ENTRY
        movs    r2, #15
1:      str     r1, [r0], #4
        subs    r2, r2, #1
        bne     1b
        @ wait loop and fault entry into SRAM
        ldr     r0, =ram_code
        ldr     r1, =RAM_CODE
        ldr     r2, =RAM_CODE_SIZE
        bl      copy_words
        dsb
        isb
        ldr     r0, =VTOR
        ldr     r1, =RAM_VECTORS
        str     r1, [r0]
        dsb
        isb
        ldr     r0, =RAM_CODE + 1
        bx      r0

@ copy_words: r0 = source, r1 = destination, r2 = byte count (a non-zero multiple of 4);
@ feeds the watchdog after each word.  Uses r3, r12.
        .thumb_func
copy_words:
        ldr     r12, =IWDG_KEY
2:      ldr     r3, [r0], #4
        str     r3, [r1], #4
        movw    r3, #0xAAAA
        str     r3, [r12]
        subs    r2, r2, #4
        bne     2b
        bx      lr

@ crc32: r0 = address, r1 = byte count (non-zero); returns in r0 the CRC-32 of zlib
@ (reflected, polynomial 0xEDB88320, initial and final value 0xFFFFFFFF).  Feeds the
@ watchdog after each byte.  Uses r2, r3, r12, and saves r5-r7.
        .thumb_func
crc32:
        push    {r5, r6, r7, lr}
        mov     r2, r0
        mvn     r0, #0
        ldr     r6, =0xEDB88320
        ldr     r12, =IWDG_KEY
        movw    r5, #0xAAAA
3:      ldrb    r3, [r2], #1
        eors    r0, r0, r3
        movs    r7, #8
4:      lsrs    r0, r0, #1
        it      cs
        eorcs   r0, r0, r6
        subs    r7, r7, #1
        bne     4b
        str     r5, [r12]
        subs    r1, r1, #1
        bne     3b
        mvns    r0, r0
        pop     {r5, r6, r7, pc}

@ flash_fault: a fault before the switch to SRAM; marks the result block and waits.
        .thumb_func
flash_fault:
        ldr     r0, =RESULT
        ldr     r1, =MAGIC_FAULT
        str     r1, [r0]
5:      b       5b

        .ltorg

@ ---- code run from SRAM at RAM_CODE (position-independent: pc-relative literals only) ----
        .balign 4
ram_code:
        .thumb_func
ram_wait:
        ldr     r0, ram_iwdg
        ldr     r1, ram_key
        ldr     r2, ram_result
6:      str     r1, [r0]
        ldr     r3, [r2, #16]
        adds    r3, r3, #1
        str     r3, [r2, #16]
        b       6b
        .thumb_func
ram_fault:
        ldr     r2, ram_result
        ldr     r3, ram_fault_magic
        str     r3, [r2]
        b       ram_wait
        .balign 4
ram_iwdg:        .word   IWDG_KEY
ram_key:         .word   0xAAAA
ram_result:      .word   RESULT
ram_fault_magic: .word   MAGIC_FAULT
ram_code_end:

        .equ    RAM_FAULT_ENTRY, RAM_CODE + (ram_fault - ram_code) + 1
        .equ    RAM_CODE_SIZE,   ram_code_end - ram_code
