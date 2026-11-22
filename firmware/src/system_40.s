@ system_40.s - fault and exception handler stubs, clock setup, SysTick handler, USART1 byte send, main entry/loop
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0800835c - BusFault handler. Never returns. Calls fn_0801031c with the
@ string "BusFault_Handler\n" (literal at 0x08008364), then loops forever
@ (branch to itself at 0x08008362).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800835c,"ax",%progbits
	.p2align 2
	.global fn_0800835c
	.thumb_func
	.type fn_0800835c, %function
fn_0800835c:
	adr	r0, .L08008364
	bl	fn_0801031c
.L08008362:
	b.n	.L08008362
.L08008364:
	.asciz	"BusFault_Handler\n"
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08008c5c - DebugMon handler. No parameters. Loads the address of the
@ string "DebugMon_Handler\n" (literal 0x08008c64) into r0 and tail-calls
@ fn_0801031c (b.w), which returns to the caller.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008c5c,"ax",%progbits
	.p2align 2
	.global fn_08008c5c
	.thumb_func
	.type fn_08008c5c, %function
fn_08008c5c:
	adr	r0, .L08008c64
	b.w	fn_0801031c
	.short	0x0000			@ padding
.L08008c64:
	.asciz	"DebugMon_Handler\n"
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08009358 - HardFault handler. Never returns. Calls fn_0801031c with the
@ string "HardFault_Handler\n" (literal 0x08009360), then loops forever
@ (branch to itself at 0x0800935e).
@ ----------------------------------------------------------------------------
	.section .text.fn_08009358,"ax",%progbits
	.p2align 2
	.global fn_08009358
	.thumb_func
	.type fn_08009358, %function
fn_08009358:
	adr	r0, .L08009360
	bl	fn_0801031c
.L0800935e:
	b.n	.L0800935e
.L08009360:
	.asciz	"HardFault_Handler\n"
	.byte	0x00			@ padding

@ ----------------------------------------------------------------------------
@ fn_0800ad34 - MemManage handler. Never returns. Calls fn_0801031c with the
@ string "MemManage_Handler\n" (literal 0x0800ad3c), then loops forever
@ (branch to itself at 0x0800ad3a).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ad34,"ax",%progbits
	.p2align 2
	.global fn_0800ad34
	.thumb_func
	.type fn_0800ad34, %function
fn_0800ad34:
	adr	r0, .L0800ad3c
	bl	fn_0801031c
.L0800ad3a:
	b.n	.L0800ad3a
.L0800ad3c:
	.asciz	"MemManage_Handler\n"
	.byte	0x00			@ padding

@ ----------------------------------------------------------------------------
@ fn_0800ad50 - NMI handler. No parameters. Loads the address of the string
@ "NMI_Handler\n" (literal 0x0800ad58) into r0 and tail-calls fn_0801031c
@ (b.w), which returns to the caller.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ad50,"ax",%progbits
	.p2align 2
	.global fn_0800ad50
	.thumb_func
	.type fn_0800ad50, %function
fn_0800ad50:
	adr	r0, .L0800ad58
	b.w	fn_0801031c
	.short	0x0000			@ padding
.L0800ad58:
	.asciz	"NMI_Handler\n"
	.byte	0x00, 0x00, 0x00	@ padding

@ ----------------------------------------------------------------------------
@ fn_0800b9d4 - SVC handler. No parameters. Loads the address of the string
@ "SVC_Handler\n" (literal 0x0800b9dc) into r0 and tail-calls fn_0801031c
@ (b.w), which returns to the caller.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b9d4,"ax",%progbits
	.p2align 2
	.global fn_0800b9d4
	.thumb_func
	.type fn_0800b9d4, %function
fn_0800b9d4:
	adr	r0, .L0800b9dc
	b.w	fn_0801031c
	.short	0x0000			@ padding
.L0800b9dc:
	.asciz	"SVC_Handler\n"
	.byte	0x00, 0x00, 0x00	@ padding

@ ----------------------------------------------------------------------------
@ fn_0800ba4c - system clock setup (called by fn_0800c274). No parameters.
@ r0 = 0x40021000 (RCC_CTRL), RCC_CFG is at 0x40021004, 0x40022000 is
@ FLASH_AC.
@  1. Sets bit 16 of RCC_CTRL and polls it up to 0x8000 times (counter in the
@     stack word at sp+4) until the byte (RCC_CTRL & 0x3ffff) >> 17 is non-zero
@     (the loop reads bit 17 of RCC_CTRL).
@  2. When that byte is still 0 after the loop: stores 8000000 (0x007a1200) to
@     the word 0x200002b0 and returns.
@  3. Otherwise: clears bits 2:0 of 0x40022000 and ors 4 into it; rewrites
@     RCC_CFG unchanged; ors 0x2000 into RCC_CFG; ors 0x500 into RCC_CFG; ands
@     RCC_CFG with 0xf7c0ffff; ors 0x10000 and 0x08040000 into RCC_CFG (value
@     also kept in the stack word at sp); sets bit 24 of RCC_CTRL and waits
@     until bit 25 of RCC_CTRL is set; clears bits 1:0 of RCC_CFG and ors 2;
@     waits until (RCC_CFG & 0xf) >> 2 equals 2; returns.
@ Frame: push {r2,r3,lr}; the stack words at sp and sp+4 are scratch.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ba4c,"ax",%progbits
	.p2align 2
	.global fn_0800ba4c
	.thumb_func
	.type fn_0800ba4c, %function
fn_0800ba4c:
	push	{r2, r3, lr}
	movs	r0, #0			@ r0 = 0
	str	r0, [sp, #0]		@ scratch word = 0
	strb.w	r0, [sp, #0]		@ scratch byte = 0
	str	r0, [sp, #4]		@ poll counter = 0
	ldr	r0, .L0800bb04		@ r0 = 0x40021000 (RCC_CTRL)
	ldr	r1, [r0, #0]
	orr	r1, r1, #0x10000	@ set bit 16
	str	r1, [r0, #0]
	mov.w	r2, #0x8000		@ poll limit
.L0800ba66:
	ldr	r1, [r0, #0]
	ubfx	r1, r1, #0x11, #1	@ bit 17 of RCC_CTRL
	strb.w	r1, [sp, #0]
	ldr	r1, [sp, #4]
	.inst.n	0x1c49			@ adds r1, r1, #1
	str	r1, [sp, #4]		@ counter += 1
	ldrb.w	r1, [sp, #0]
	cbnz	r1, .L0800ba82		@ bit seen: leave the loop
	ldr	r1, [sp, #4]
	cmp	r1, r2
	bne.n	.L0800ba66		@ until 0x8000 polls
.L0800ba82:
	ldr	r1, [r0, #0]
	ubfx	r1, r1, #0x11, #1
	strb.w	r1, [sp, #0]
	ldrb.w	r1, [sp, #0]
	cbz	r1, .L0800baf8		@ bit never set: store the fallback value
	ldr	r1, .L0800bb08		@ r1 = 0x40022000 (FLASH_AC)
	ldr	r2, [r1, #0]
	bic	r2, r2, #0x7		@ clear bits 2:0
	str	r2, [r1, #0]
	ldr	r2, [r1, #0]
	orr	r2, r2, #0x4		@ or 4
	str	r2, [r1, #0]
	ldr	r1, [r0, #4]		@ RCC_CFG rewritten unchanged
	str	r1, [r0, #4]
	ldr	r1, [r0, #4]
	orr	r1, r1, #0x2000
	str	r1, [r0, #4]
	ldr	r1, [r0, #4]
	orr	r1, r1, #0x500
	str	r1, [r0, #4]
	ldr	r1, [r0, #4]
	ldr	r2, .L0800bb0c		@ r2 = 0xf7c0ffff
	ands	r1, r2
	str	r1, [r0, #4]
	ldr	r1, [r0, #4]
	ldr	r2, .L0800bb10		@ r2 = 0x08040000
	orr	r1, r1, #0x10000
	orrs	r1, r2
	str	r1, [sp, #0]
	str	r1, [r0, #4]
	ldr	r1, [r0, #0]
	orr	r1, r1, #0x1000000	@ set bit 24 of RCC_CTRL
	str	r1, [r0, #0]
.L0800bad6:
	ldr	r1, [r0, #0]
	lsls	r1, r1, #6		@ bit 25 into the sign flag
	bpl.n	.L0800bad6		@ wait until bit 25 is set
	ldr	r1, [r0, #4]
	bic	r1, r1, #0x3		@ clear bits 1:0 of RCC_CFG
	str	r1, [r0, #4]
	ldr	r1, [r0, #4]
	orr	r1, r1, #0x2		@ or 2
	str	r1, [r0, #4]
.L0800baec:
	ldr	r1, [r0, #4]
	ubfx	r1, r1, #2, #2		@ (RCC_CFG & 0xf) >> 2
	cmp	r1, #2
	bne.n	.L0800baec		@ wait until it equals 2
.L0800baf6:
	pop	{r2, r3, pc}
.L0800baf8:
	b.n	.L0800bafa
.L0800bafa:
	ldr	r1, .L0800bb18		@ r1 = 0x200002b0
	ldr	r0, .L0800bb14		@ r0 = 8000000
	str	r0, [r1, #0]
	b.n	.L0800baf6
	.short	0x0000			@ padding
.L0800bb04:
	.word	0x40021000
.L0800bb08:
	.word	0x40022000
.L0800bb0c:
	.word	0xf7c0ffff
.L0800bb10:
	.word	0x08040000		@ RCC_CFG bits ORed in at 0x0800BAC8 (not an address)
.L0800bb14:
	.word	0x007a1200
.L0800bb18:
	.word	0x200002b0

@ ----------------------------------------------------------------------------
@ systick_handler - SysTick exception entry (vector slot 15; the vector
@ table word 0x0800603c holds this address). Single instruction: tail-calls
@ fn_0802a720 (b.w).
@ ----------------------------------------------------------------------------
	.section .text.systick_handler,"ax",%progbits
	.p2align 2
	.global systick_handler
	.thumb_func
	.type systick_handler, %function
systick_handler:
	b.w	fn_0802a720

@ ----------------------------------------------------------------------------
@ fn_0800c274 - early hardware setup. No parameters. RCC = 0x40021000.
@  - ors 0xf00000 into the word 0xE000ED88 (SCB CPACR)
@  - RCC_CTRL (0x40021000) ors 1; RCC_CFG (0x40021004) ands 0xf8ffc000;
@    RCC_CTRL ands 0xfef6ffff, then clears bit 18 (0xfffbffff);
@    RCC_CFG ands 0xf700ffff
@  - writes 0 to 0x4002102c and 0x40021030, 0x009f0000 to 0x40021008
@    (RCC_CLKINT)
@  - sets bit 28 of 0x4002101c (RCC_APB1PCLKEN), ors 1 into 0x4000700c,
@    clears bit 28 of 0x4002101c again
@  - ors 0x90 into 0x40022000 (FLASH_AC)
@  - calls fn_0800ba4c (clock setup)
@  - writes 0x08006000 (the vector table) to 0xE000ED08 (SCB VTOR); the
@    address is formed as 0xE000ED88 - 0x80
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c274,"ax",%progbits
	.p2align 2
	.global fn_0800c274
	.thumb_func
	.type fn_0800c274, %function
fn_0800c274:
	ldr	r0, .L0800c2e8		@ r0 = 0xE000ED88
	push	{r4, lr}
	ldr	r1, [r0, #0]
	orr	r1, r1, #0xf00000
	str	r1, [r0, #0]
	ldr	r0, .L0800c2ec		@ r0 = 0x40021000
	ldr	r1, [r0, #0]
	orr	r1, r1, #1
	str	r1, [r0, #0]
	ldr	r1, [r0, #4]
	ldr	r2, .L0800c2f0		@ r2 = 0xf8ffc000
	ands	r1, r2
	str	r1, [r0, #4]
	ldr	r1, [r0, #0]
	ldr	r2, .L0800c2f4		@ r2 = 0xfef6ffff
	ands	r1, r2
	str	r1, [r0, #0]
	ldr	r1, [r0, #0]
	bic	r1, r1, #0x40000
	str	r1, [r0, #0]
	ldr	r1, [r0, #4]
	ldr	r2, .L0800c2f8		@ r2 = 0xf700ffff
	ands	r1, r2
	str	r1, [r0, #4]
	movs	r1, #0
	str	r1, [r0, #0x2c]
	str	r1, [r0, #0x30]
	mov.w	r1, #0x9f0000
	str	r1, [r0, #8]		@ RCC_CLKINT
	ldr	r1, [r0, #0x1c]
	orr	r1, r1, #0x10000000
	str	r1, [r0, #0x1c]
	ldr	r1, .L0800c2fc		@ r1 = 0x40007000
	ldr	r2, [r1, #0xc]
	orr	r2, r2, #1
	str	r2, [r1, #0xc]
	ldr	r1, [r0, #0x1c]
	bic	r1, r1, #0x10000000
	str	r1, [r0, #0x1c]
	ldr	r0, .L0800c300		@ r0 = 0x40022000 (FLASH_AC)
	ldr	r1, [r0, #0]
	orr	r1, r1, #0x90
	str	r1, [r0, #0]
	bl	fn_0800ba4c
	ldr	r1, .L0800c2e8		@ r1 = 0xE000ED88
	ldr	r0, .L0800c304		@ r0 = 0x08006000
	subs	r1, #0x80		@ r1 = 0xE000ED08 (SCB VTOR)
	str	r0, [r1, #0]
	pop	{r4, pc}
.L0800c2e8:
	.word	0xe000ed88
.L0800c2ec:
	.word	0x40021000
.L0800c2f0:
	.word	0xf8ffc000
.L0800c2f4:
	.word	0xfef6ffff
.L0800c2f8:
	.word	0xf700ffff
.L0800c2fc:
	.word	0x40007000
.L0800c300:
	.word	0x40022000
.L0800c304:
	.word	vectors

@ ----------------------------------------------------------------------------
@ fn_08010158 - UsageFault handler. Never returns. Calls fn_0801031c with the
@ string "UsageFault_Handler\n" (literal 0x08010160), then loops forever
@ (branch to itself at 0x0801015e).
@ ----------------------------------------------------------------------------
	.section .text.fn_08010158,"ax",%progbits
	.p2align 2
	.global fn_08010158
	.thumb_func
	.type fn_08010158, %function
fn_08010158:
	adr	r0, .L08010160
	bl	fn_0801031c
.L0801015e:
	b.n	.L0801015e
.L08010160:
	.asciz	"UsageFault_Handler\n"

@ ----------------------------------------------------------------------------
@ fn_0801b010 - send one byte on USART1 (register block 0x40013800).
@ Parameter: r0 = byte (low 8 bits used). Returns r0 unchanged.
@ Calls fn_0800fb38(0x40013800, r0 & 0xff), then calls
@ test_halfword_bits(0x40013800, 0x80) repeatedly until it returns non-zero.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b010,"ax",%progbits
	.p2align 2
	.global fn_0801b010
	.thumb_func
	.type fn_0801b010, %function
fn_0801b010:
	push	{r4, r5, r6, lr}
	ldr	r5, .L0801b030		@ r5 = 0x40013800 (USART1)
	mov	r4, r0			@ keep the byte
	uxtb	r1, r0
	mov	r0, r5
	bl	fn_0800fb38
.L0801b01e:
	movs	r1, #0x80
	mov	r0, r5
	bl	test_halfword_bits
	cmp	r0, #0
	beq.n	.L0801b01e		@ wait until the test returns non-zero
	mov	r0, r4			@ return the byte
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L0801b030:
	.word	0x40013800

@ ----------------------------------------------------------------------------
@ fn_08027ff4 - program entry after reset: initialisation, then the main
@ loop. No parameters. Never returns.
@ Init: calls fn_08008504, fn_08008200, fn_08008cd4, fn_08008c78,
@ fn_08011c68(1000) and fn_08008350(0x40010800 (GPIOA), 0x100, 1). Prints
@ "\n\nstart\n" and "Sys.Config:%d\n" (0xc14) through fn_0801031c. Zero-fills
@ 0x4ba4 bytes at 0x2000057c with zero_bytes and calls
@ copy_flash_block_to_ram (copies 0xc14 bytes from 0x0807f000 to 0x2000057c).
@ When the words 0x2000057c and 0x2000118c are not both 0x12345678 calls
@ fn_0800b4c8(1).
@ Limits applied to the RAM words (r4 = 0x2000057c base):
@   0x20001150 (+0xbd4): set to 0 when negative
@   0x20001158 (+0xbdc): set to 100 unless 1..100
@   0x20001160 (+0xbe4): set to 100 when above 100
@   0x2000115c (+0xbe0): set to 0 when above 1
@ Calls fn_080081fa(0x40011000 (GPIOC), 0x800): when it returns 0 the word
@ 0x200011c0 (+0xc44) is set to 1. Calls fn_080081fa(0x40011800 (GPIOE),
@ 0x40) and, when that returns 0, fn_080081fa(0x40011800, 1); when both return
@ 0 the word 0x200011c0 is set to 2.
@ Prints with fn_0801031c the words 0x2000115c, 0x20001158, 0x20001160,
@ 0x20001164, 0x20001148, 0x20001154, 0x200011e8, 0x20001144, 0x20001138 and
@ 0x2000113c (the last two converted by float_to_double and passed in d0 /
@ r2:r3), 0x2000114c, 0x20001150, 0x2000116c, 0x20001170, 0x20001174,
@ 0x20001140 and 0x200011c0 with the "Sys.Config.*" and "Sys.UI.Factory"
@ format strings.
@ Then an empty 12 x 3 x 3 counting loop, then calls fn_0800814c,
@ fn_08009c14, fn_08011c68(100), fn_0800ce54, fn_0800b0d8, fn_080087d4,
@ fn_08008024, and fn_0800ca2c when the word 0x20001140 is non-zero (else
@ fn_0800c86c). Clears the halfwords 0x20001190 to 0x20001196, calls
@ fn_08008120(0x32) and fn_08010178 and prints "loop\n".
@ Main loop (r4 = 0x2000457c): calls fn_08010174, fn_08027830, fn_08009400,
@ fn_0800a068; when the word 0x20005110 (+0xb94) is non-zero it is cleared and
@ fn_0800a7ec is called; when the word 0x20005114 (+0xb98) is non-zero it is
@ cleared and fn_0800bd5c is called; repeats.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027ff4,"ax",%progbits
	.p2align 2
	.global fn_08027ff4
	.thumb_func
	.type fn_08027ff4, %function
fn_08027ff4:
	bl	fn_08008504
	bl	fn_08008200
	bl	fn_08008cd4
	bl	fn_08008c78
	mov.w	r0, #0x3e8
	bl	fn_08011c68		@ argument 1000
	movs	r2, #1			@ third argument 1
	lsls	r1, r2, #8		@ second argument 0x100
	ldr	r0, .L08028200		@ r0 = 0x40010800 (GPIOA)
	bl	fn_08008350
	adr	r0, .L08028204		@ "\n\nstart\n"
.ifdef OWN
	bl	own_start		@ 0x08028018: this print, then our start (own/ctl.s)
.else
	bl	fn_0801031c
.endif
	movw	r1, #0xc14
	adr	r0, .L08028210		@ "Sys.Config:%d\n"
	bl	fn_0801031c
	movw	r1, #0x4ba4
	ldr	r0, .L08028220		@ r0 = 0x2000057c
	bl	zero_bytes
.ifdef OWN
	bl	own_load		@ 0x08028030: load from copy A or B (own/save.s)
.else
	bl	copy_flash_block_to_ram
.endif
	ldr	r4, .L08028220		@ r4 = 0x2000057c
	ldr	r0, .L08028224		@ r0 = 0x12345678
	ldr	r1, [r4, #0]
	cmp	r1, r0
	bne.n	.L08028046
	ldr.w	r1, [r4, #0xc10]	@ word 0x2000118c
	cmp	r1, r0
	beq.n	.L0802804c
.L08028046:
	movs	r0, #1
	bl	fn_0800b4c8
.L0802804c:
	ldr.w	r0, [r4, #0xbd4]	@ word 0x20001150
	movs	r5, #0			@ r5 = 0 (kept for the stores below)
	cmp	r0, #0
	bge.n	.L0802805a
	str.w	r5, [r4, #0xbd4]	@ negative: set to 0
.L0802805a:
	ldr.w	r1, [r4, #0xbdc]	@ word 0x20001158
	movs	r0, #0x64
	.inst.n	0x1e49			@ subs r1, r1, #1
	cmp	r1, #0x64
	bcc.n	.L0802806a		@ 1..100 stays
	str.w	r0, [r4, #0xbdc]	@ else 100
.L0802806a:
	ldr.w	r1, [r4, #0xbe4]	@ word 0x20001160
	cmp	r1, #0x65
	bcc.n	.L08028076
	str.w	r0, [r4, #0xbe4]	@ above 100: set to 100
.L08028076:
	ldr.w	r0, [r4, #0xbe0]	@ word 0x2000115c
	cmp	r0, #2
	bcc.n	.L08028082
	str.w	r5, [r4, #0xbe0]	@ above 1: set to 0
.L08028082:
	mov.w	r1, #0x800
	ldr	r0, .L08028228		@ r0 = 0x40011000 (GPIOC)
	bl	fn_080081fa
	cbnz	r0, .L08028094
	movs	r0, #1
	str.w	r0, [r4, #0xc44]	@ word 0x200011c0 = 1
.L08028094:
	ldr	r6, .L0802822c		@ r6 = 0x40011800 (GPIOE)
	movs	r1, #0x40
	mov	r0, r6
	bl	fn_080081fa
	cbnz	r0, .L080280b0
	movs	r1, #1
	mov	r0, r6
	bl	fn_080081fa
	cbnz	r0, .L080280b0
	movs	r0, #2
	str.w	r0, [r4, #0xc44]	@ word 0x200011c0 = 2
.L080280b0:
	ldr.w	r1, [r4, #0xbe0]	@ word 0x2000115c
	adr	r0, .L08028230		@ "Sys.Config.Lang:%d\n"
	addw	r4, r4, #0xbc4		@ r4 = 0x20001140
	bl	fn_0801031c
	adr	r0, .L08028244		@ "Sys.Config.Brightness:%d\n"
	ldr	r1, [r4, #0x18]		@ word 0x20001158
	bl	fn_0801031c
	adr	r0, .L08028260		@ "Sys.Config.Volume:%d\n"
	ldr	r1, [r4, #0x20]		@ word 0x20001160
	bl	fn_0801031c
	adr	r0, .L08028278		@ "Sys.Config.AutoOff:%d\n"
	ldr	r1, [r4, #0x24]		@ word 0x20001164
	bl	fn_0801031c
	adr	r0, .L08028290		@ "Sys.Config.Func:%d\n"
	ldr	r1, [r4, #8]		@ word 0x20001148
	bl	fn_0801031c
	adr	r0, .L080282a4		@ "Sys.Config.Model:%d\n"
	ldr	r1, [r4, #0x14]		@ word 0x20001154
	bl	fn_0801031c
	adr	r0, .L080282bc		@ "Sys.Config.Para:%d\n"
	ldr.w	r1, [r4, #0xa8]		@ word 0x200011e8
	bl	fn_0801031c
	adr	r0, .L080282d0		@ "Sys.Config.Freq:%dHz\n"
	ldr	r1, [r4, #4]		@ word 0x20001144
	bl	fn_0801031c
	ldr	r6, .L08028220		@ r6 = 0x2000057c
	ldr.w	r0, [r6, #0xbbc]	@ word 0x20001138
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r0, .L080282e8		@ "Sys.Config.Amp:%0.1fV\n"
	vmov	r2, r3, d0
	bl	fn_0801031c
	ldr.w	r0, [r6, #0xbc0]	@ word 0x2000113c
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r0, .L08028300		@ "Sys.Config.Bias:%0.1fV\n"
	vmov	r2, r3, d0
	bl	fn_0801031c
	adr	r0, .L08028318		@ "Sys.Config.Range:%d\n"
	ldr	r1, [r4, #0xc]		@ word 0x2000114c
	bl	fn_0801031c
	adr	r0, .L08028330		@ "Sys.Config.Speed:%d\n"
	ldr	r1, [r4, #0x10]		@ word 0x20001150
	bl	fn_0801031c
	adr	r0, .L08028348		@ "Sys.Config.WarnType:%d\n"
	ldr	r1, [r4, #0x2c]		@ word 0x2000116c
	bl	fn_0801031c
	adr	r0, .L08028360		@ "Sys.Config.WarnSound:%d\n"
	ldr	r1, [r4, #0x30]		@ word 0x20001170
	bl	fn_0801031c
	adr	r0, .L0802837c		@ "Sys.Config.WarnLed:%d\n"
	ldr	r1, [r4, #0x34]		@ word 0x20001174
	bl	fn_0801031c
	adr	r0, .L08028394		@ "Sys.Config.Init:%d\n"
	ldr	r1, [r4, #0]		@ word 0x20001140
	bl	fn_0801031c
	ldr.w	r1, [r4, #0x80]		@ word 0x200011c0
	adr	r0, .L080283a8		@ "Sys.UI.Factory:%d\n"
	subw	r4, r4, #0xbc4		@ r4 = 0x2000057c again
	bl	fn_0801031c
	movs	r2, #0			@ outer counter (12)
.L08028166:
	movs	r1, #0			@ middle counter (3)
.L08028168:
	movs	r0, #2			@ inner counter (3 passes)
.L0802816a:
	.inst.n	0x1c40			@ adds r0, r0, #1
	cmp	r0, #5
	blt.n	.L0802816a
	.inst.n	0x1c49			@ adds r1, r1, #1
	cmp	r1, #3
	blt.n	.L08028168
	.inst.n	0x1c52			@ adds r2, r2, #1
	cmp	r2, #0xc
	blt.n	.L08028166
	bl	fn_0800814c
	bl	fn_08009c14
	movs	r0, #0x64
	bl	fn_08011c68		@ argument 100
	bl	fn_0800ce54
	bl	fn_0800b0d8
	bl	fn_080087d4
	bl	fn_08008024
	ldr.w	r0, [r4, #0xbc4]	@ word 0x20001140
	cbz	r0, .L080281f8
	bl	fn_0800ca2c
.L080281a4:
	strh.w	r5, [r4, #0xc1a]	@ halfword 0x20001196 = 0
	strh.w	r5, [r4, #0xc16]	@ halfword 0x20001192 = 0
	strh.w	r5, [r4, #0xc18]	@ halfword 0x20001194 = 0
	strh.w	r5, [r4, #0xc14]	@ halfword 0x20001190 = 0
	movs	r0, #0x32
	bl	fn_08008120
	bl	fn_08010178
	adr	r0, .L080283bc		@ "loop\n"
	bl	fn_0801031c
	ldr	r4, .L080283c4		@ r4 = 0x2000457c
	nop
.L080281c8:
	bl	fn_08010174		@ main loop starts here
	bl	fn_08027830
.ifdef OWN
	bl	ctl_loop		@ 0x080281D0: control step around fn_08009400 (own/ctl.s)
.else
	bl	fn_08009400
.endif
.ifdef OWN
	bl	own_measure		@ 0x080281D4: our measurement core (own/meas.s)
.else
	bl	fn_0800a068
.endif
	ldr.w	r0, [r4, #0xb94]	@ word 0x20005110
	cbz	r0, .L080281e6
	str.w	r5, [r4, #0xb94]	@ clear it
	bl	fn_0800a7ec
.L080281e6:
	ldr.w	r0, [r4, #0xb98]	@ word 0x20005114
	cmp	r0, #0
	beq.n	.L080281c8
	str.w	r5, [r4, #0xb98]	@ clear it
	bl	fn_0800bd5c
	b.n	.L080281c8
.L080281f8:
	bl	fn_0800c86c
	b.n	.L080281a4
	.short	0x0000			@ padding
.L08028200:
	.word	0x40010800
.L08028204:
	.asciz	"\n\nstart\n"
	.byte	0x00, 0x00, 0x00	@ padding
.L08028210:
	.asciz	"Sys.Config:%d\n"
	.byte	0x00			@ padding
.L08028220:
	.word	0x2000057c
.L08028224:
	.word	0x12345678
.L08028228:
	.word	0x40011000
.L0802822c:
	.word	0x40011800
.L08028230:
	.asciz	"Sys.Config.Lang:%d\n"
.L08028244:
	.asciz	"Sys.Config.Brightness:%d\n"
	.short	0x0000			@ padding
.L08028260:
	.asciz	"Sys.Config.Volume:%d\n"
	.short	0x0000			@ padding
.L08028278:
	.asciz	"Sys.Config.AutoOff:%d\n"
	.byte	0x00			@ padding
.L08028290:
	.asciz	"Sys.Config.Func:%d\n"
.L080282a4:
	.asciz	"Sys.Config.Model:%d\n"
	.byte	0x00, 0x00, 0x00	@ padding
.L080282bc:
	.asciz	"Sys.Config.Para:%d\n"
.L080282d0:
	.asciz	"Sys.Config.Freq:%dHz\n"
	.short	0x0000			@ padding
.L080282e8:
	.asciz	"Sys.Config.Amp:%0.1fV\n"
	.byte	0x00			@ padding
.L08028300:
	.asciz	"Sys.Config.Bias:%0.1fV\n"
.L08028318:
	.asciz	"Sys.Config.Range:%d\n"
	.byte	0x00, 0x00, 0x00	@ padding
.L08028330:
	.asciz	"Sys.Config.Speed:%d\n"
	.byte	0x00, 0x00, 0x00	@ padding
.L08028348:
	.asciz	"Sys.Config.WarnType:%d\n"
.L08028360:
	.asciz	"Sys.Config.WarnSound:%d\n"
	.byte	0x00, 0x00, 0x00	@ padding
.L0802837c:
	.asciz	"Sys.Config.WarnLed:%d\n"
	.byte	0x00			@ padding
.L08028394:
	.asciz	"Sys.Config.Init:%d\n"
.L080283a8:
	.asciz	"Sys.UI.Factory:%d\n"
	.byte	0x00			@ padding
.L080283bc:
	.asciz	"loop\n"
	.short	0x0000			@ padding
.L080283c4:
	.word	0x2000457c

@ ----------------------------------------------------------------------------
@ fn_0802a720 - SysTick work routine, entered by the tail call in
@ systick_handler. No parameters.
@ Base r0 = 0x2000057c: when the word at +0xc28 (0x200011a4) is 0, the word at
@ +0xc90 (0x2000120c) is incremented.
@ Base r0 = 0x2000457c, r4 = 0: the words at +0xb88 (0x20005104) and +0xb8c
@ (0x20005108, new value in r2) are incremented. Base r1 = 0x20000000: the
@ words at [r1] (new value in r3) and [r1+4] (0x20000004, new value in r5) are
@ incremented.
@  - r3 above 9: [r1] = 0 and the word at +0xb90 (0x2000510c) is incremented
@  - r5 above 0x31: [r1+4] = 0 and the word at +0xb94 (0x20005110) is
@    incremented
@  - r2 above 0x63: the word at +0xb8c = 0 and the word at +0xb98
@    (0x20005114) is incremented
@ Then calls fn_080094a0, restores the registers and tail-calls
@ add_to_word_20000480_clear_byte_2000047c with r0 = 10 (b.w).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802a720,"ax",%progbits
	.p2align 2
	.global fn_0802a720
	.thumb_func
	.type fn_0802a720, %function
fn_0802a720:
	push	{r4, r5, r6, lr}
	ldr	r0, .L0802a79c		@ r0 = 0x2000057c
	ldr.w	r1, [r0, #0xc28]	@ word 0x200011a4
	cbnz	r1, .L0802a734
	ldr.w	r1, [r0, #0xc90]	@ word 0x2000120c
	.inst.n	0x1c49			@ adds r1, r1, #1
	str.w	r1, [r0, #0xc90]
.L0802a734:
	ldr	r0, .L0802a7a0		@ r0 = 0x2000457c
	movs	r4, #0
	ldr.w	r1, [r0, #0xb88]	@ word 0x20005104
	.inst.n	0x1c49			@ adds r1, r1, #1
	str.w	r1, [r0, #0xb88]
	ldr.w	r2, [r0, #0xb8c]	@ word 0x20005108
	ldr	r1, .L0802a7a4		@ r1 = 0x20000000
	.inst.n	0x1c52			@ adds r2, r2, #1
	str.w	r2, [r0, #0xb8c]
	ldr	r3, [r1, #0]
	.inst.n	0x1c5b			@ adds r3, r3, #1
	str	r3, [r1, #0]
	ldr	r5, [r1, #4]		@ word 0x20000004
	.inst.n	0x1c6d			@ adds r5, r5, #1
	str	r5, [r1, #4]
	cmp	r3, #9
	bls.n	.L0802a76a
	str	r4, [r1, #0]
	ldr.w	r3, [r0, #0xb90]	@ word 0x2000510c
	.inst.n	0x1c5b			@ adds r3, r3, #1
	str.w	r3, [r0, #0xb90]
.L0802a76a:
	cmp	r5, #0x31
	bls.n	.L0802a77a
	str	r4, [r1, #4]
	ldr.w	r1, [r0, #0xb94]	@ word 0x20005110
	.inst.n	0x1c49			@ adds r1, r1, #1
	str.w	r1, [r0, #0xb94]
.L0802a77a:
	cmp	r2, #0x63
	bls.n	.L0802a78c
	str.w	r4, [r0, #0xb8c]	@ word 0x20005108 = 0
	ldr.w	r1, [r0, #0xb98]	@ word 0x20005114
	.inst.n	0x1c49			@ adds r1, r1, #1
	str.w	r1, [r0, #0xb98]
.L0802a78c:
	bl	fn_080094a0
	pop.w	{r4, r5, r6, lr}
	movs	r0, #0xa
	b.w	add_to_word_20000480_clear_byte_2000047c
	.short	0x0000			@ padding
.L0802a79c:
	.word	0x2000057c
.L0802a7a0:
	.word	0x2000457c
.L0802a7a4:
	.word	0x20000000
