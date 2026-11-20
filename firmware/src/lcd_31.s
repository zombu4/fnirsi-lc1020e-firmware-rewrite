@ lcd_31.s - display (LCD) routines: bus setup, full-screen fill, pixel and window writes, panel init, backlight timer
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08009b14 - no parameters, no return value.
@ Calls set_or_clear_bits_40021014(0x100, 1), then builds a 0x58-byte block on
@ the stack (0x58 bytes, offsets 0x00..0x57) holding the values 0xa0000000
@ (offset 0), 0x10 (offset 0x0c), 0x1000 (offset 0x24), 0x4000 (offset 0x2c),
@ 0x100000 (offset 0x4c), 2 (offset 0x44) and a pointer to the sub-block at
@ offset 0x3c (stored at offsets 0x34 and 0x38); all other words are 0.
@ Calls fn_08010280(block), then set_or_clear_bit_0_0801026c(0xa0000000, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_08009b14,"ax",%progbits
	.p2align 2
	.global fn_08009b14
	.thumb_func
	.type fn_08009b14, %function
fn_08009b14:
	push {r4, lr}
	movs r1, #1
	sub sp, #0x58
	lsls r0, r1, #8                 @ r0 = 0x100
	bl set_or_clear_bits_40021014
	movs r1, #0
	movs r0, #2
	strd r1, r0, [sp, #0x40]        @ words 0x40 = 0, 0x44 = 2
	lsls r0, r0, #0x13              @ r0 = 0x100000
	strd r1, r0, [sp, #0x48]        @ words 0x48 = 0, 0x4c = 0x100000
	movs r0, #0x10
	strd r1, r0, [sp, #8]           @ words 0x08 = 0, 0x0c = 0x10
	str r1, [sp, #0x3c]
	str r1, [sp, #0x50]
	mov.w r4, #0xa0000000
	str r1, [sp, #0x54]
	strd r4, r1, [sp, #0]           @ words 0x00 = 0xa0000000, 0x04 = 0
	str r1, [sp, #0x10]
	lsls r0, r0, #8                 @ r0 = 0x1000
	strd r1, r0, [sp, #0x20]        @ words 0x20 = 0, 0x24 = 0x1000
	str r1, [sp, #0x18]
	str r1, [sp, #0x14]
	lsls r0, r0, #2                 @ r0 = 0x4000
	strd r1, r0, [sp, #0x28]        @ words 0x28 = 0, 0x2c = 0x4000
	add r0, sp, #0x3c
	str r1, [sp, #0x1c]
	strd r1, r0, [sp, #0x30]        @ word 0x30 = 0, 0x34 = pointer to offset 0x3c
	str r0, [sp, #0x38]
	mov r0, sp
	bl fn_08010280                  @ r0 = pointer to the block
	movs r1, #1
	mov r0, r4                      @ r0 = 0xa0000000
	bl set_or_clear_bit_0_0801026c
	add sp, #0x58
	pop {r4, pc}

@ ----------------------------------------------------------------------------
@ write_76800_halfwords - r0 = halfword value (kept in r4); no return value.
@ Calls fn_08009e30(0, 0, 0x13f, 0xef) (r0 = r1 = 0, r2 = 319, r3 = 239) to set
@ the window, then writes the halfword r4 with strh to 0x60020000 320 times per
@ row (inner loop, signed compare with 0x140) for 240 rows (outer loop, signed
@ compare with 0xf0): 76800 writes in all. Entered by the tail branch at
@ 0x08009e1e of fn_08009c14 with r0 = 0.
@ ----------------------------------------------------------------------------
	.section .text.write_76800_halfwords,"ax",%progbits
	.p2align 2
	.global write_76800_halfwords
	.thumb_func
	.type write_76800_halfwords, %function
write_76800_halfwords:
	push {r4, lr}
	mov r4, r0
	movs r1, #0
	movs r3, #0xef
	movw r2, #0x13f
	mov r0, r1
	bl fn_08009e30
	ldr r0, .L08009b9c              @ r0 = 0x60020000
	movs r2, #0                     @ row counter
	mov.w r3, #0x140                @ columns per row
.L08009b8a:
	movs r1, #0                     @ column counter
.L08009b8c:
	strh r4, [r0, #0]
	.inst.n 0x1c49                  @ adds r1, r1, #1
	cmp r1, r3
	blt.n .L08009b8c
	.inst.n 0x1c52                  @ adds r2, r2, #1
	cmp r2, #0xf0
	blt.n .L08009b8a
	pop {r4, pc}
.L08009b9c:
	.word 0x60020000

@ ----------------------------------------------------------------------------
@ fn_08009ba0 - draws a rectangle pixel by pixel.
@ r0 = row origin, r1 = column origin, r2 = rows, r3 = columns;
@ stack (after the 10 pushed registers): [sp+0x28] = flag (nonzero writes
@ colour 0 for every pixel), [sp+0x2c] = flag (nonzero calls fn_08011c68(4)
@ after each row), [sp+0x30] = pointer to a halfword array; no return value.
@ For each row and column calls fn_08009bfc(r0 + row, r1 + column, colour), the
@ colour being the halfword at array + (row * columns + column) * 2, or 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08009ba0,"ax",%progbits
	.p2align 2
	.global fn_08009ba0
	.thumb_func
	.type fn_08009ba0, %function
fn_08009ba0:
	push.w {r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	mov r7, r3                      @ r7 = columns
	mov r8, r2                      @ r8 = rows
	mov r9, r1                      @ r9 = column origin
	mov r11, r0                     @ r11 = row origin
	movs r5, #0                     @ row index
	ldr.w r10, [sp, #0x28]          @ r10 = flag: write colour 0
	b.n .L08009be2
.L08009bb4:
	movs r4, #0                     @ column index
	add.w r6, r11, r5               @ r6 = row origin + row
	b.n .L08009bd2
.L08009bbc:
	cmp.w r10, #0
	beq.n .L08009bea
	add.w r1, r9, r4
	mov r0, r6
	movs.w r2, #0
.L08009bcc:
	bl fn_08009bfc
	.inst.n 0x1c64                  @ adds r4, r4, #1
.L08009bd2:
	cmp r4, r7
	blt.n .L08009bbc
	ldr r0, [sp, #0x2c]             @ flag: delay call after each row
	cbz r0, .L08009be0
	movs r0, #4
	bl fn_08011c68
.L08009be0:
	.inst.n 0x1c6d                  @ adds r5, r5, #1
.L08009be2:
	cmp r5, r8
	blt.n .L08009bb4
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}
.L08009bea:
	mla r1, r5, r7, r4              @ r1 = row * columns + column
	ldr r0, [sp, #0x30]             @ r0 = pointer to the halfword array
	ldrh.w r2, [r0, r1, lsl #1]     @ r2 = colour from the array
	add.w r1, r9, r4
	mov r0, r6
	b.n .L08009bcc

@ ----------------------------------------------------------------------------
@ fn_08009bfc - writes one pixel. r0 = x, r1 = y, r2 = colour halfword; no
@ return value. Calls fn_08009e30(r0, r1, r0, r1) to set the window, then
@ writes r2 as a halfword to 0x60020000.
@ ----------------------------------------------------------------------------
	.section .text.fn_08009bfc,"ax",%progbits
	.p2align 2
	.global fn_08009bfc
	.thumb_func
	.type fn_08009bfc, %function
fn_08009bfc:
	push {r4, lr}
	mov r4, r2                      @ r4 = colour
	mov r3, r1
	mov r2, r0
	bl fn_08009e30
	ldr r0, .L08009c10              @ r0 = 0x60020000
	strh r4, [r0, #0]
	pop {r4, pc}
	.short 0x0000                   @ padding
.L08009c10:
	.word 0x60020000

@ ----------------------------------------------------------------------------
@ fn_08009c14 - display port and panel initialisation; no parameters, no
@ return value.
@ Calls fn_08008338(port, mask, 0x18) for port r4 = 0x40011400 with masks 0x10,
@ 0x20, 0x80, 0x800, 0x4000, 0x8000, 1, 2 (0x800 = asr(0x40011400, 19); 0x4000
@ and 0x8000 are that value shifted left by 3 and 4), then for port r8 =
@ 0x40011800 with masks 0x80, 0x100, 0x200, 0x400, 0x800, 0x1000
@ (asr(0x40011400, 18)), 0x2000 (asr(0x40011400, 17)), 0x4000, 0x8000, then for
@ port 0x40011400 with masks 0x100, 0x200, 0x400; then calls fn_08009b14().
@ Pin 0x40 of port 0x40011400: fn_08008338(port, 0x40, 0x10),
@ fn_08008350(port, 0x40, 0), fn_08011c68(1), fn_08008350(port, 0x40, 1),
@ fn_08011c68(100).
@ Then halfword writes with r4 = 0x6001fffe (command) and r4 + 2 = 0x60020000
@ (data): command 0x11, then fn_08011c68(0x78); command 0x36 (data 0xb0), 0x3a
@ (5), 0xb2 (0x0c, 0x0c, 0, 0x33, 0x33), 0xb7 (0x35), 0xbb (0x28), 0xc0
@ (0x2c), 0xc2 (1), 0xc3 (0x0b), 0xc4 (0x20), 0xc6 (0x0f), 0xd0 (0xa4, 0xa1),
@ 0xe0 (0xd0, 1, 8, 0x0f, 0x11, 0x2a, 0x36, 0x55, 0x44, 0x3a, 0x0b, 6, 0x11,
@ 0x20), 0xe1 (0xd0, 2, 7, 0x0a, 0x0b, 0x18, 0x34, 0x43, 0x4a, 0x2b, 0x1b,
@ 0x1c, 0x22, 0x1f); then command 0x29.
@ Restores the saved registers, sets r0 = 0 and tail-calls
@ write_76800_halfwords(0) with b.w, which sets the window with
@ fn_08009e30(0, 0, 0x13f, 0xef) and writes 76800 halfwords of r0 to
@ 0x60020000.
@ ----------------------------------------------------------------------------
	.section .text.fn_08009c14,"ax",%progbits
	.p2align 2
	.global fn_08009c14
	.thumb_func
	.type fn_08009c14, %function
fn_08009c14:
	push.w {r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	ldr r4, .L08009e24              @ r4 = 0x40011400
	movs r2, #0x18
	movs r1, #0x10
	mov r0, r4
	bl fn_08008338
	movs r2, #0x18
	movs r1, #0x20
	mov r0, r4
	bl fn_08008338
	movs r2, #0x18
	movs r1, #0x80
	mov r0, r4
	bl fn_08008338
	asrs r5, r4, #0x13              @ r5 = 0x800
	movs r2, #0x18
	mov r1, r5
	mov r0, r4
	bl fn_08008338
	lsls r6, r5, #3                 @ r6 = 0x4000
	movs r2, #0x18
	mov r1, r6
	mov r0, r4
	bl fn_08008338
	lsls r7, r5, #4                 @ r7 = 0x8000
	movs r2, #0x18
	mov r1, r7
	mov r0, r4
	bl fn_08008338
	movs r2, #0x18
	movs r1, #1
	mov r0, r4
	bl fn_08008338
	movs r2, #0x18
	movs r1, #2
	mov r0, r4
	bl fn_08008338
	ldr.w r8, .L08009e28            @ r8 = 0x40011800
	movs r2, #0x18
	movs r1, #0x80
	mov r0, r8
	bl fn_08008338
	mov.w r9, #0x100
	movs r2, #0x18
	mov r1, r9
	mov r0, r8
	bl fn_08008338
	mov.w r10, #0x200
	movs r2, #0x18
	mov r1, r10
	mov r0, r8
	bl fn_08008338
	mov.w r11, #0x400
	movs r2, #0x18
	mov r1, r11
	mov r0, r8
	bl fn_08008338
	movs r2, #0x18
	mov r1, r5                      @ 0x800
	mov r0, r8
	bl fn_08008338
	movs r2, #0x18
	asrs r1, r4, #0x12              @ r1 = 0x1000
	mov r0, r8
	bl fn_08008338
	movs r2, #0x18
	asrs r1, r4, #0x11              @ r1 = 0x2000
	mov r0, r8
	bl fn_08008338
	movs r2, #0x18
	mov r1, r6                      @ 0x4000
	mov r0, r8
	bl fn_08008338
	movs r2, #0x18
	mov r1, r7                      @ 0x8000
	mov r0, r8
	bl fn_08008338
	movs r2, #0x18
	mov r1, r9                      @ 0x100
	mov r0, r4
	bl fn_08008338
	movs r2, #0x18
	mov r1, r10                     @ 0x200
	mov r0, r4
	bl fn_08008338
	movs r2, #0x18
	mov r1, r11                     @ 0x400
	mov r0, r4
	bl fn_08008338
	bl fn_08009b14
	movs r2, #0x10
	movs r1, #0x40
	mov r0, r4
	bl fn_08008338
	movs r2, #0
	movs r1, #0x40
	mov r0, r4
	bl fn_08008350
	movs r0, #1
	bl fn_08011c68
	movs r2, #1
	movs r1, #0x40
	mov r0, r4
	bl fn_08008350
	movs r0, #0x64
	bl fn_08011c68
	ldr r4, .L08009e2c              @ r4 = 0x6001fffe (command address)
	movs r0, #0x11
	strh r0, [r4, #0]               @ command 0x11
	movs r0, #0x78
	bl fn_08011c68
	movs r0, #0x36
	strh r0, [r4, #0]               @ command 0x36
	movs r1, #0xb0
	adds r0, r4, #2                 @ r0 = 0x60020000 (data address)
	strh r1, [r0, #0]
	movs r1, #0x3a
	strh r1, [r4, #0]               @ command 0x3a
	movs r1, #5
	strh r1, [r0, #0]
	movs r1, #0xb2
	strh r1, [r4, #0]               @ command 0xb2
	movs r1, #0xc
	strh r1, [r0, #0]
	strh r1, [r0, #0]
	movs r1, #0
	strh r1, [r0, #0]
	movs r1, #0x33
	strh r1, [r0, #0]
	strh r1, [r0, #0]
	movs r1, #0xb7
	strh r1, [r4, #0]               @ command 0xb7
	movs r1, #0x35
	strh r1, [r0, #0]
	movs r1, #0xbb
	strh r1, [r4, #0]               @ command 0xbb
	movs r1, #0x28
	strh r1, [r0, #0]
	movs r1, #0xc0
	strh r1, [r4, #0]               @ command 0xc0
	movs r1, #0x2c
	strh r1, [r0, #0]
	movs r1, #0xc2
	strh r1, [r4, #0]               @ command 0xc2
	movs r1, #1
	strh r1, [r0, #0]
	movs r1, #0xc3
	strh r1, [r4, #0]               @ command 0xc3
	movs r1, #0xb
	strh r1, [r0, #0]
	movs r1, #0xc4
	strh r1, [r4, #0]               @ command 0xc4
	movs r1, #0x20
	strh r1, [r0, #0]
	movs r1, #0xc6
	strh r1, [r4, #0]               @ command 0xc6
	movs r1, #0xf
	strh r1, [r0, #0]
	movs r1, #0xd0
	strh r1, [r4, #0]               @ command 0xd0
	movs r1, #0xa4
	strh r1, [r0, #0]
	movs r1, #0xa1
	strh r1, [r0, #0]
	movs r1, #0xe0
	strh r1, [r4, #0]               @ command 0xe0
	movs r1, #0xd0
	strh r1, [r0, #0]
	movs r1, #1
	strh r1, [r0, #0]
	movs r1, #8
	strh r1, [r0, #0]
	movs r1, #0xf
	strh r1, [r0, #0]
	movs r1, #0x11
	strh r1, [r0, #0]
	movs r1, #0x2a
	strh r1, [r0, #0]
	movs r1, #0x36
	strh r1, [r0, #0]
	movs r1, #0x55
	strh r1, [r0, #0]
	movs r1, #0x44
	strh r1, [r0, #0]
	movs r1, #0x3a
	strh r1, [r0, #0]
	movs r1, #0xb
	strh r1, [r0, #0]
	movs r1, #6
	strh r1, [r0, #0]
	movs r1, #0x11
	strh r1, [r0, #0]
	movs r1, #0x20
	strh r1, [r0, #0]
	movs r1, #0xe1
	strh r1, [r4, #0]               @ command 0xe1
	movs r1, #0xd0
	strh r1, [r0, #0]
	movs r1, #2
	strh r1, [r0, #0]
	movs r1, #7
	strh r1, [r0, #0]
	movs r1, #0xa
	strh r1, [r0, #0]
	movs r1, #0xb
	strh r1, [r0, #0]
	movs r1, #0x18
	strh r1, [r0, #0]
	movs r1, #0x34
	strh r1, [r0, #0]
	movs r1, #0x43
	strh r1, [r0, #0]
	movs r1, #0x4a
	strh r1, [r0, #0]
	movs r1, #0x2b
	strh r1, [r0, #0]
	movs r1, #0x1b
	strh r1, [r0, #0]
	movs r1, #0x1c
	strh r1, [r0, #0]
	movs r1, #0x22
	strh r1, [r0, #0]
	movs r1, #0x1f
	strh r1, [r0, #0]
	movs r0, #0x29
	strh r0, [r4, #0]               @ command 0x29
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	movs r0, #0
	b.w write_76800_halfwords       @ tail call with r0 = 0
	.short 0x0000                   @ padding
.L08009e24:
	.word 0x40011400
.L08009e28:
	.word 0x40011800
.L08009e2c:
	.word 0x6001fffe

@ ----------------------------------------------------------------------------
@ fn_08009e30 - sets the drawing window. r0 = x start, r1 = y start, r2 = x end,
@ r3 = y end; no return value.
@ Writes command 0x2a to the halfword 0x6001fffe, then r0 >> 8, r0, r2 >> 8, r2
@ to 0x60020000; writes command 0x2b, then r1 >> 8, r1, r3 >> 8, r3 to
@ 0x60020000; writes command 0x2c to 0x6001fffe.
@ ----------------------------------------------------------------------------
	.section .text.fn_08009e30,"ax",%progbits
	.p2align 2
	.global fn_08009e30
	.thumb_func
	.type fn_08009e30, %function
fn_08009e30:
	push {r4, r5, r6, lr}
	ldr r5, .L08009e5c              @ r5 = 0x6001fffe (command address)
	movs r4, #0x2a
	strh r4, [r5, #0]
	lsrs r6, r0, #8
	adds r4, r5, #2                 @ r4 = 0x60020000 (data address)
	strh r6, [r4, #0]
	strh r0, [r4, #0]
	lsrs r0, r2, #8
	strh r0, [r4, #0]
	strh r2, [r4, #0]
	movs r0, #0x2b
	strh r0, [r5, #0]
	lsrs r0, r1, #8
	strh r0, [r4, #0]
	strh r1, [r4, #0]
	lsrs r0, r3, #8
	strh r0, [r4, #0]
	strh r3, [r4, #0]
	movs r0, #0x2c
	strh r0, [r5, #0]
	pop {r4, r5, r6, pc}
.L08009e5c:
	.word 0x6001fffe

@ ----------------------------------------------------------------------------
@ fn_08009e60 - r0 = value; no return value.
@ Below 100: calls fn_0800911c(0x1a0800, 1), fn_08008338(0x40010c00, 0x10,
@ 0x18), builds a timer block on the stack with period 0xe10 (halfword at
@ sp+4, other fields 0) and calls fn_0800c590(0x40000400, block); builds a
@ second block (0x60, 1, compare = ((r0 + 8 * r0) * 4) & 0xffff, 0) for
@ fn_0800c430(0x40000400, block); then fn_0800c31c(0x40000400, 8),
@ set_or_clear_bit_7(0x40000400, 1), set_or_clear_bit_0_0800c404(0x40000400, 1)
@ and fn_0800c418(0x40000400, 1).
@ Otherwise calls fn_08008338(0x40010c00, 0x10, 0x10) and tail-calls
@ fn_08008350(0x40010c00, 0x10, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_08009e60,"ax",%progbits
	.p2align 2
	.global fn_08009e60
	.thumb_func
	.type fn_08009e60, %function
fn_08009e60:
	push {r4, r5, r6, lr}
	ldr r4, .L08009f04              @ r4 = 0x40010c00
	sub sp, #0x20
	mov r5, r0                      @ r5 = value
	cmp r0, #0x64
	blt.n .L08009e86
	movs r2, #0x10
	mov r1, r2
	mov r0, r4
	bl fn_08008338
	add sp, #0x20
	mov r0, r4
	pop.w {r4, r5, r6, lr}
	movs r2, #1
	movs r1, #0x10
	b.w fn_08008350
.L08009e86:
	movs r1, #1
	ldr r0, .L08009f08              @ r0 = 0x001a0800
	bl fn_0800911c
	movs r2, #0x18
	movs r1, #0x10
	mov r0, r4
	bl fn_08008338
	mov.w r0, #0xe10
	movs r4, #0
	strh.w r0, [sp, #4]             @ period 0xe10
	ldr r6, .L08009f0c              @ r6 = 0x40000400
	strh.w r4, [sp, #0]
	strh.w r4, [sp, #6]
	strh.w r4, [sp, #2]
	mov r1, sp
	mov r0, r6
	bl fn_0800c590
	movs r0, #0x60
	strh.w r0, [sp, #0x10]
	movs r0, #1
	strh.w r0, [sp, #0x12]
	add.w r0, r5, r5, lsl #3        @ r0 = value * 9
	movw r1, #0xffff
	and.w r0, r1, r0, lsl #2        @ r0 = (value * 9 * 4) & 0xffff
	strh.w r0, [sp, #0x16]
	strh.w r4, [sp, #0x18]
	add r1, sp, #0x10
	mov r0, r6
	bl fn_0800c430
	movs r1, #8
	mov r0, r6
	bl fn_0800c31c
	movs r1, #1
	mov r0, r6
	bl set_or_clear_bit_7
	movs r1, #1
	mov r0, r6
	bl set_or_clear_bit_0_0800c404
	movs r1, #1
	mov r0, r6
	bl fn_0800c418
	add sp, #0x20
	pop {r4, r5, r6, pc}
.L08009f04:
	.word 0x40010c00
.L08009f08:
	.word 0x001a0800
.L08009f0c:
	.word 0x40000400
