@ measure_32.s - measurement module part 32: DMA/ADC/timer start-up routine and the helpers after it.
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08007bdc - no parameters, no return value.
@ Calls fn_080079ac(0, 1) and fn_0800b290(0x400, 0x3800), then
@ fn_08007e7c with the word at 0x20001144 (word at 0x2000057c + 0xbc8).
@ Sets up three channel blocks through fn_0800864c, fn_08008794(block,
@ settings) and fn_08008770(block, 1). The settings words (offsets
@ 0,4,8,12,16,20,24,28,32,36,40) are:
@   block 0x40020008: {0x4002084c, 0x20005a38, 0, 0x80, 0, 0x80, 0x100,
@                      0x400, 0, 0x2000, 0}
@   block 0x40020094: {0x40020c4c, 0x20005b38, 0, 0x80, 0, 0x80, 0x100,
@                      0x400, 0, 0x2000, 0}
@   block 0x40020458: {0x4002184c, 0x20005c38, 0, 0x80, 0, 0x80, 0x100,
@                      0x400, 0, 0, 0}
@ (the sources 0x4002084c, 0x40020c4c, 0x4002184c are the register block
@ addresses 0x40020800, 0x40020c00, 0x40021800 plus 0x4c).
@ For the register blocks 0x40020800, 0x40020c00 and 0x40021800, in this
@ order (the block address is the literal minus 0x4c):
@   fn_08007ab4(block); a settings block on the stack (word at sp+44 = 0,
@   bytes at sp+48 and sp+49 = 0, word at sp+52 = 0x40000, word at sp+56 =
@   0, byte at sp+60 = 1) passed to fn_08007b74(block, settings);
@   fn_08007a30(block, n, 1, 0) with n = 3, 4, 1 respectively;
@   fn_08007b28(block, 1); fn_08007b08(block, 1); a wait until
@   fn_08007b66(block, 0x20) returns nonzero; fn_08007bc0(block); a wait
@   until fn_08007b50(block) returns 0; fn_08007b3c(block, 1).
@ Then calls set_or_clear_bit_0_0800c404(0x40012c00, 1) and
@ fn_0800c418(0x40012c00, 1), and stores 1 to the byte 0x200011c4
@ (0x2000057c + 0xc48).
@ ----------------------------------------------------------------------------
	.section .text.fn_08007bdc,"ax",%progbits
	.p2align 2
	.global fn_08007bdc
	.thumb_func
	.type fn_08007bdc, %function
fn_08007bdc:
	push.w {r4, r5, r6, r7, r8, r9, r10, lr}
	sub sp, #0x40
	movs r1, #1
	movs r0, #0
	bl fn_080079ac
	mov.w r6, #0x400
	mov.w r1, #0x3800
	mov r0, r6
	bl fn_0800b290
	ldr.w r9, .L08007dfc		@ r9 = 0x2000057c, base of the module RAM
	ldr.w r0, [r9, #0xbc8]		@ word at 0x20001144
	bl fn_08007e7c
	ldr.w r10, .L08007e00		@ r10 = 0x40020008, first channel block
	mov r0, r10
	bl fn_0800864c
	ldr r0, .L08007e04		@ 0x4002084c
	str r0, [sp]
	ldr r0, .L08007e08		@ 0x20005a38
	add r1, sp, #4
	movs r4, #0
	movs r5, #0x80
	stm.w r1, {r0, r4, r5}
	add r0, sp, #0x10
	lsls r7, r5, #1			@ r7 = 0x100
	stm.w r0, {r4, r5, r7}
	strd r6, r4, [sp, #0x1c]
	mov.w r8, #0x2000
	strd r8, r4, [sp, #0x24]
	mov r1, sp
	mov r0, r10
	bl fn_08008794
	movs r1, #1
	mov r0, r10
	bl fn_08008770
	ldr.w r10, .L08007e00
	add.w r10, r10, #0x8c		@ 0x40020094, second channel block
	mov r0, r10
	bl fn_0800864c
	ldr r0, .L08007e0c		@ 0x40020c4c
	str r0, [sp]
	ldr r0, .L08007e10		@ 0x20005b38
	add r1, sp, #4
	stm.w r1, {r0, r4, r5}
	add r0, sp, #0x10
	mov r1, sp
	stm.w r0, {r4, r5, r7}
	strd r6, r4, [sp, #0x1c]
	strd r8, r4, [sp, #0x24]
	mov r0, r10
	bl fn_08008794
	movs r1, #1
	mov r0, r10
	bl fn_08008770
	ldr.w r8, .L08007e14		@ 0x40020458, third channel block
	mov r0, r8
	bl fn_0800864c
	ldr r0, .L08007e18		@ 0x4002184c
	str r0, [sp]
	ldr r0, .L08007e1c		@ 0x20005c38
	add r1, sp, #4
	stm.w r1, {r0, r4, r5}
	add r0, sp, #0x10
	mov r1, sp
	stm.w r0, {r4, r5, r7}
	strd r6, r4, [sp, #0x1c]
	str r4, [sp, #0x24]
	mov r0, r8
	str r4, [sp, #0x28]
	bl fn_08008794
	movs r1, #1
	mov r0, r8
	bl fn_08008770
	ldr r5, .L08007e04
	subs r5, #0x4c			@ r5 = 0x40020800
	mov r0, r5
	bl fn_08007ab4
	strb.w r4, [sp, #0x30]
	str r4, [sp, #0x2c]
	strb.w r4, [sp, #0x31]
	lsls r6, r6, #8			@ r6 = 0x40000
	strd r6, r4, [sp, #0x34]
	movs r7, #1
	strb.w r7, [sp, #0x3c]
	add r1, sp, #0x2c
	mov r0, r5
	bl fn_08007b74
	movs r3, #0
	movs r2, #1
	movs r1, #3
	mov r0, r5
	bl fn_08007a30
	movs r1, #1
	mov r0, r5
	bl fn_08007b28
	movs r1, #1
	mov r0, r5
	bl fn_08007b08
.L08007cf2:
	movs r1, #0x20
	mov r0, r5
	bl fn_08007b66
	cmp r0, #0
	beq.n .L08007cf2
	mov r0, r5
	bl fn_08007bc0
.L08007d04:
	mov r0, r5
	bl fn_08007b50
	cmp r0, #0
	bne.n .L08007d04
	movs r1, #1
	mov r0, r5
	bl fn_08007b3c
	ldr r5, .L08007e0c
	subs r5, #0x4c			@ r5 = 0x40020c00
	mov r0, r5
	bl fn_08007ab4
	strb.w r4, [sp, #0x30]
	str r4, [sp, #0x2c]
	strb.w r4, [sp, #0x31]
	strd r6, r4, [sp, #0x34]
	strb.w r7, [sp, #0x3c]
	add r1, sp, #0x2c
	mov r0, r5
	bl fn_08007b74
	movs r3, #0
	movs r2, #1
	movs r1, #4
	mov r0, r5
	bl fn_08007a30
	movs r1, #1
	mov r0, r5
	bl fn_08007b28
	movs r1, #1
	mov r0, r5
	bl fn_08007b08
.L08007d56:
	movs r1, #0x20
	mov r0, r5
	bl fn_08007b66
	cmp r0, #0
	beq.n .L08007d56
	mov r0, r5
	bl fn_08007bc0
.L08007d68:
	mov r0, r5
	bl fn_08007b50
	cmp r0, #0
	bne.n .L08007d68
	movs r1, #1
	mov r0, r5
	bl fn_08007b3c
	ldr r5, .L08007e18
	subs r5, #0x4c			@ r5 = 0x40021800
	mov r0, r5
	bl fn_08007ab4
	strb.w r4, [sp, #0x30]
	str r4, [sp, #0x2c]
	strb.w r4, [sp, #0x31]
	strd r6, r4, [sp, #0x34]
	strb.w r7, [sp, #0x3c]
	add r1, sp, #0x2c
	mov r0, r5
	bl fn_08007b74
	movs r2, #1
	movs r3, #0
	mov r1, r2
	mov r0, r5
	bl fn_08007a30
	movs r1, #1
	mov r0, r5
	bl fn_08007b28
	movs r1, #1
	mov r0, r5
	bl fn_08007b08
.L08007dba:
	movs r1, #0x20
	mov r0, r5
	bl fn_08007b66
	cmp r0, #0
	beq.n .L08007dba
	mov r0, r5
	bl fn_08007bc0
.L08007dcc:
	mov r0, r5
	bl fn_08007b50
	cmp r0, #0
	bne.n .L08007dcc
	movs r1, #1
	mov r0, r5
	bl fn_08007b3c
	ldr r4, .L08007e20		@ 0x40012c00
	movs r1, #1
	mov r0, r4
	bl set_or_clear_bit_0_0800c404
	movs r1, #1
	mov r0, r4
	bl fn_0800c418
	strb.w r7, [r9, #0xc48]		@ byte 0x200011c4 = 1
	add sp, #0x40
	pop.w {r4, r5, r6, r7, r8, r9, r10, pc}
	.short 0x0000			@ padding
.L08007dfc:
	.word 0x2000057c
.L08007e00:
	.word 0x40020008
.L08007e04:
	.word 0x4002084c
.L08007e08:
	.word 0x20005a38
.L08007e0c:
	.word 0x40020c4c
.L08007e10:
	.word 0x20005b38
.L08007e14:
	.word 0x40020458
.L08007e18:
	.word 0x4002184c
.L08007e1c:
	.word 0x20005c38
.L08007e20:
	.word 0x40012c00

@ ----------------------------------------------------------------------------
@ fn_08007e24 - no parameters; returns 1 when bit 1 (value 2) of word
@ 0x40020000, bit value 0x20000000 of word 0x40020000 and bit value
@ 0x20000 of word 0x40020400 are all set (each tested with test_bits),
@ else 0. In the success case it writes 2 and 0x20000000 through
@ store_word_offset_4 to the word at 0x40020004 and 0x20000 to the word at
@ 0x40020404.
@ ----------------------------------------------------------------------------
	.section .text.fn_08007e24,"ax",%progbits
	.p2align 2
	.global fn_08007e24
	.thumb_func
	.type fn_08007e24, %function
fn_08007e24:
	push.w {r4, r5, r6, r7, r8, lr}
	ldr r4, .L08007e74		@ 0x40020000
	movs r0, #2
	mov r1, r4
	bl test_bits
	cmp r0, #0
	beq.n .L08007e6e
	lsls r5, r4, #0xc		@ r5 = 0x20000000
	mov r1, r4
	mov r0, r5
	bl test_bits
	cmp r0, #0
	beq.n .L08007e6e
	ldr r6, .L08007e78		@ 0x40020400
	asrs r7, r5, #0xc		@ r7 = 0x20000
	mov r1, r6
	mov r0, r7
	bl test_bits
	cmp r0, #0
	beq.n .L08007e6e
	mov r1, r4
	movs r0, #2
	bl store_word_offset_4
	mov r1, r4
	mov r0, r5
	bl store_word_offset_4
	mov r1, r6
	mov r0, r7
	bl store_word_offset_4
	movs r0, #1
.L08007e6e:
	pop.w {r4, r5, r6, r7, r8, pc}
	.short 0x0000			@ padding
.L08007e74:
	.word 0x40020000
.L08007e78:
	.word 0x40020400

@ ----------------------------------------------------------------------------
@ fn_08007e7c - r0 = value (the word at 0x20001144 in the caller); no
@ return value.
@ Scales r0 * 0x80 (r4); when r0 >= 10000 the product is divided by 4 with
@ rounding toward zero if r0 < 100000 (0x186a0), else divided by 16.
@ Calls fn_0800c33c(0x40012c00) and init_eleven_field_record on a block on
@ the stack. Builds a settings block with halfwords at sp+0, +2, +6 = 0 and
@ the halfword at sp+4 = 144000000 (0x08954400) / scaled value (udiv), then
@ calls fn_0800c590(0x40012c00, block). A second block (halfwords at sp+0x10
@ = 0x70, sp+0x12 = 1, sp+0x16 = 1, sp+0x18 = 0) goes to
@ fn_0800c504(0x40012c00, block).
@ ----------------------------------------------------------------------------
	.section .text.fn_08007e7c,"ax",%progbits
	.p2align 2
	.global fn_08007e7c
	.thumb_func
	.type fn_08007e7c, %function
fn_08007e7c:
	push {r4, r5, r6, lr}
	movw r1, #0x2710		@ 10000
	lsls r4, r0, #7			@ r4 = value * 0x80
	sub sp, #0x20
	cmp r0, r1
	blt.n .L08007ea2
	ldr r2, .L08007ef0		@ 100000
	sbfx r1, r0, #0x18, #1
	cmp r0, r2
	bge.n .L08007e9c
	add.w r0, r4, r1, lsr #0x1e
	asrs r4, r0, #2			@ scaled value / 4
	b.n .L08007ea2
.L08007e9c:
	add.w r0, r4, r1, lsr #0x1c
	asrs r4, r0, #4			@ scaled value / 16
.L08007ea2:
	ldr r6, .L08007ef4		@ 0x40012c00
	mov r0, r6
	bl fn_0800c33c
	mov r0, sp
	bl init_eleven_field_record
	ldr r0, .L08007ef8		@ 144000000
	movs r5, #0
	udiv r0, r0, r4
	strh.w r5, [sp, #6]
	strh.w r5, [sp, #2]
	strh.w r0, [sp, #4]
	strh.w r5, [sp]
	mov r1, sp
	mov r0, r6
	bl fn_0800c590
	movs r0, #0x70
	strh.w r0, [sp, #0x10]
	movs r1, #1
	strh.w r1, [sp, #0x12]
	strh.w r1, [sp, #0x16]
	strh.w r5, [sp, #0x18]
	add r1, sp, #0x10
	mov r0, r6
	bl fn_0800c504
	add sp, #0x20
	pop {r4, r5, r6, pc}
.L08007ef0:
	.word 0x000186a0
.L08007ef4:
	.word 0x40012c00
.L08007ef8:
	.word 0x08954400

@ ----------------------------------------------------------------------------
@ fn_08007efc - no parameters, no return value.
@ Waits until test_bits(2, 0x40020000) returns nonzero, then until
@ test_bits(0x20000000, 0x40020000) returns nonzero, then until
@ test_bits(0x20000, 0x40020400) returns nonzero.
@ ----------------------------------------------------------------------------
	.section .text.fn_08007efc,"ax",%progbits
	.p2align 2
	.global fn_08007efc
	.thumb_func
	.type fn_08007efc, %function
fn_08007efc:
	push {r4, r5, r6, lr}
	ldr r4, .L08007f30		@ 0x40020000
.L08007f00:
	movs r0, #2
	mov r1, r4
	bl test_bits
	cmp r0, #0
	beq.n .L08007f00
	mov.w r5, #0x20000000
.L08007f10:
	mov r1, r4
	mov r0, r5
	bl test_bits
	cmp r0, #0
	beq.n .L08007f10
	ldr r4, .L08007f34		@ 0x40020400
	mov.w r5, #0x20000
.L08007f22:
	mov r1, r4
	mov r0, r5
	bl test_bits
	cmp r0, #0
	beq.n .L08007f22
	pop {r4, r5, r6, pc}
.L08007f30:
	.word 0x40020000
.L08007f34:
	.word 0x40020400

@ ----------------------------------------------------------------------------
@ fn_08007f38 - no parameters, no return value.
@ Scans the 128 halfwords at 0x20005b38 (word at the literal 0x08007f7c).
@ Each sample is loaded sign-extended (ldrsh) and compared with the running
@ maximum (starts 0, signed compare) and the running minimum (starts
@ 0xffff, signed compare); the running values are stored zero-extended
@ (ldrh). Stores the maximum to the halfword 0x200011d2, the minimum to
@ 0x200011d4, maximum - minimum to 0x200011d6 and (minimum + maximum) >> 1
@ to 0x200011d8 (base 0x2000057c from the literal 0x08007f80, offsets
@ 0xc56, 0xc58, 0xc5a, 0xc5c).
@ ----------------------------------------------------------------------------
	.section .text.fn_08007f38,"ax",%progbits
	.p2align 2
	.global fn_08007f38
	.thumb_func
	.type fn_08007f38, %function
fn_08007f38:
	push {r4, lr}
	movs r2, #0			@ r2 = running maximum
	ldr r3, .L08007f7c		@ 0x20005b38
	movw r1, #0xffff		@ r1 = running minimum
	mov r0, r2			@ r0 = index
.L08007f44:
	ldrsh.w r4, [r3, r0, lsl #1]
	cmp r4, r2
	ble.n .L08007f50
	ldrh.w r2, [r3, r0, lsl #1]
.L08007f50:
	ldrsh.w r4, [r3, r0, lsl #1]
	cmp r4, r1
	bge.n .L08007f5c
	ldrh.w r1, [r3, r0, lsl #1]
.L08007f5c:
	.inst.n 0x1c40			@ adds r0, r0, #1
	cmp r0, #0x80
	blt.n .L08007f44
	ldr r3, .L08007f80		@ 0x2000057c
	subs r0, r2, r1			@ maximum - minimum
	strh.w r2, [r3, #0xc56]		@ halfword 0x200011d2 = maximum
	strh.w r1, [r3, #0xc58]		@ halfword 0x200011d4 = minimum
	add r1, r2
	strh.w r0, [r3, #0xc5a]		@ halfword 0x200011d6 = maximum - minimum
	lsrs r1, r1, #1
	strh.w r1, [r3, #0xc5c]		@ halfword 0x200011d8 = (minimum + maximum) >> 1
	pop {r4, pc}
.L08007f7c:
	.word 0x20005b38
.L08007f80:
	.word 0x2000057c

@ ----------------------------------------------------------------------------
@ fn_08007f84 - no parameters, no return value.
@ Scans the 128 halfwords at 0x20005c38 (word at the literal 0x08007fcc)
@ the same way as fn_08007f38: sign-extended compare against the running
@ maximum (starts 0) and the running minimum (starts 0xffff), values kept
@ zero-extended, index kept as a halfword (uxth). Stores the maximum to the
@ halfword 0x200011da, the minimum to 0x200011dc, maximum - minimum to
@ 0x200011de and (minimum + maximum) >> 1 to 0x200011e0 (base 0x2000057c
@ from the literal 0x08007fd0, offsets 0xc5e, 0xc60, 0xc62, 0xc64).
@ ----------------------------------------------------------------------------
	.section .text.fn_08007f84,"ax",%progbits
	.p2align 2
	.global fn_08007f84
	.thumb_func
	.type fn_08007f84, %function
fn_08007f84:
	push {r4, lr}
	movs r2, #0			@ r2 = running maximum
	ldr r3, .L08007fcc		@ 0x20005c38
	movw r1, #0xffff		@ r1 = running minimum
	mov r0, r2			@ r0 = index
.L08007f90:
	ldrsh.w r4, [r3, r0, lsl #1]
	cmp r4, r2
	ble.n .L08007f9c
	ldrh.w r2, [r3, r0, lsl #1]
.L08007f9c:
	ldrsh.w r4, [r3, r0, lsl #1]
	cmp r4, r1
	bge.n .L08007fa8
	ldrh.w r1, [r3, r0, lsl #1]
.L08007fa8:
	.inst.n 0x1c40			@ adds r0, r0, #1
	uxth r0, r0
	cmp r0, #0x80
	bcc.n .L08007f90
	ldr r3, .L08007fd0		@ 0x2000057c
	subs r0, r2, r1			@ maximum - minimum
	strh.w r2, [r3, #0xc5e]		@ halfword 0x200011da = maximum
	strh.w r1, [r3, #0xc60]		@ halfword 0x200011dc = minimum
	add r1, r2
	strh.w r0, [r3, #0xc62]		@ halfword 0x200011de = maximum - minimum
	lsrs r1, r1, #1
	strh.w r1, [r3, #0xc64]		@ halfword 0x200011e0 = (minimum + maximum) >> 1
	pop {r4, pc}
	.short 0x0000			@ padding
.L08007fcc:
	.word 0x20005c38
.L08007fd0:
	.word 0x2000057c

@ ----------------------------------------------------------------------------
@ fn_08007fd4 - no parameters, no return value.
@ Scans the 128 halfwords at 0x20005a38 (word at the literal 0x0800801c)
@ the same way as fn_08007f84. Stores the maximum to the halfword
@ 0x200011ca, the minimum to 0x200011cc, maximum - minimum to 0x200011ce
@ and (minimum + maximum) >> 1 to 0x200011d0 (base 0x2000057c from the
@ literal 0x08008020, offsets 0xc4e, 0xc50, 0xc52, 0xc54).
@ ----------------------------------------------------------------------------
	.section .text.fn_08007fd4,"ax",%progbits
	.p2align 2
	.global fn_08007fd4
	.thumb_func
	.type fn_08007fd4, %function
fn_08007fd4:
	push {r4, lr}
	movs r2, #0			@ r2 = running maximum
	ldr r3, .L0800801c		@ 0x20005a38
	movw r1, #0xffff		@ r1 = running minimum
	mov r0, r2			@ r0 = index
.L08007fe0:
	ldrsh.w r4, [r3, r0, lsl #1]
	cmp r4, r2
	ble.n .L08007fec
	ldrh.w r2, [r3, r0, lsl #1]
.L08007fec:
	ldrsh.w r4, [r3, r0, lsl #1]
	cmp r4, r1
	bge.n .L08007ff8
	ldrh.w r1, [r3, r0, lsl #1]
.L08007ff8:
	.inst.n 0x1c40			@ adds r0, r0, #1
	uxth r0, r0
	cmp r0, #0x80
	bcc.n .L08007fe0
	ldr r3, .L08008020		@ 0x2000057c
	subs r0, r2, r1			@ maximum - minimum
	strh.w r2, [r3, #0xc4e]		@ halfword 0x200011ca = maximum
	strh.w r1, [r3, #0xc50]		@ halfword 0x200011cc = minimum
	add r1, r2
	strh.w r0, [r3, #0xc52]		@ halfword 0x200011ce = maximum - minimum
	lsrs r1, r1, #1
	strh.w r1, [r3, #0xc54]		@ halfword 0x200011d0 = (minimum + maximum) >> 1
	pop {r4, pc}
	.short 0x0000			@ padding
.L0800801c:
	.word 0x20005a38
.L08008020:
	.word 0x2000057c

@ ----------------------------------------------------------------------------
@ fn_08008024 - no parameters, no return value.
@ Channel block 0x40020494 is set up through fn_0800864c, fn_08008794 and
@ fn_08008770(block, 1) with the settings words {0x40021c4c, 0x20005d38 (the
@ halfword buffer), 0, 0x80, 0, 0x80, 0x100, 0x400, 0x20, 0x2000, 0}.
@ Register block 0x40021c00 (literal 0x40021c4c minus 0x4c): fn_08007ab4,
@ a settings block on the stack (word at sp+44 = 0, byte at sp+48 = 0, byte
@ at sp+49 = 1, word at sp+52 = 0xe0000, word at sp+56 = 0, byte at sp+60 =
@ 1) passed to fn_08007b74, fn_08007a30(block, 3, 1, 6), fn_08007b28(block,
@ 1), fn_08007b08(block, 1), a wait until fn_08007b66(block, 0x20) returns
@ nonzero, fn_08007bc0, a wait until fn_08007b50 returns 0, then
@ fn_08007b3c(block, 1).
@ Then calls init_four_byte_record on a block at sp+0x40 and stores 6 in its
@ byte at sp+0x43, calls fn_0800aec0(0xc, block), fn_0800af2c(0xc, 0x200),
@ fn_0800af10(0xc, 0xc0), fn_0800aea0(0xc, 1), fn_08011c68(10) and
@ fn_080092cc.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008024,"ax",%progbits
	.p2align 2
	.global fn_08008024
	.thumb_func
	.type fn_08008024, %function
fn_08008024:
	push {r4, r5, lr}
	ldr r5, .L08008110		@ 0x40020494, channel block
	sub sp, #0x44
	mov r0, r5
	bl fn_0800864c
	ldr r0, .L08008114		@ 0x40021c4c
	str r0, [sp]
	ldr r0, .L08008118		@ 0x20005d38
	movs r4, #0
	strd r0, r4, [sp, #4]
	movs r1, #0x80
	strd r1, r4, [sp, #0xc]
	lsls r0, r1, #1			@ r0 = 0x100
	strd r1, r0, [sp, #0x14]
	lsls r0, r0, #2			@ r0 = 0x400
	str r0, [sp, #0x1c]
	movs r0, #0x20
	str r0, [sp, #0x20]
	lsls r0, r0, #8			@ r0 = 0x2000
	strd r0, r4, [sp, #0x24]
	mov r1, sp
	mov r0, r5
	bl fn_08008794
	movs r1, #1
	mov r0, r5
	bl fn_08008770
	ldr r5, .L08008114
	subs r5, #0x4c			@ r5 = 0x40021c00
	mov r0, r5
	bl fn_08007ab4
	strb.w r4, [sp, #0x30]
	movs r0, #1
	str r4, [sp, #0x2c]
	strb.w r0, [sp, #0x31]
	mov.w r1, #0xe0000
	strd r1, r4, [sp, #0x34]
	strb.w r0, [sp, #0x3c]
	add r1, sp, #0x2c
	mov r0, r5
	bl fn_08007b74
	movs r3, #6
	movs r2, #1
	movs r1, #3
	mov r0, r5
	bl fn_08007a30
	movs r1, #1
	mov r0, r5
	bl fn_08007b28
	movs r1, #1
	mov r0, r5
	bl fn_08007b08
	mov r4, r5
.L080080ae:
	movs r1, #0x20
	mov r0, r4
	bl fn_08007b66
	cmp r0, #0
	beq.n .L080080ae
	mov r0, r4
	bl fn_08007bc0
.L080080c0:
	mov r0, r4
	bl fn_08007b50
	cmp r0, #0
	bne.n .L080080c0
	movs r1, #1
	mov r0, r4
	bl fn_08007b3c
	add r0, sp, #0x40
	bl init_four_byte_record
	movs r0, #6
	strb.w r0, [sp, #0x43]
	add r1, sp, #0x40
	movs r0, #0xc
	bl fn_0800aec0
	mov.w r1, #0x200
	movs r0, #0xc
	bl fn_0800af2c
	movs r1, #0xc0
	movs r0, #0xc
	bl fn_0800af10
	movs r1, #1
	movs r0, #0xc
	bl fn_0800aea0
	movs r0, #0xa
	bl fn_08011c68
	bl fn_080092cc
	add sp, #0x44
	pop {r4, r5, pc}
	.short 0x0000			@ padding
.L08008110:
	.word 0x40020494
.L08008114:
	.word 0x40021c4c
.L08008118:
	.word 0x20005d38

@ ----------------------------------------------------------------------------
@ fn_08008814 - s0 = float amplitude, r0 = frequency value (r1 is not
@ read); no return value.
@ Sample count n = 0xb4 (r4) and scale divisor 2.34 (0x4015c28f, in s1) when
@ the frequency is below 100000, else n = 0x24 and divisor 2.1 (0x40066666).
@ Fills the halfword table 0x20005120 with
@   (short)(sin(2*pi*i/n) * 2047.5 * (amplitude / divisor)
@           + float(word 0x2000113c) * 620.0 + 2047.5)
@ for i = 0..n-1; the sine comes from sine_radians (2*pi = 0x40c90fdb,
@ 2047.5 = 0x44fff000, 620.0 = 0x441b0000, the word 0x2000113c is read as
@ a float from 0x20000d7c + 0x3c0).
@ Sets up channel block 0x40020430 through fn_0800864c and fn_08008794 with
@ the settings words {0x40007408, 0x20005120, 0x10, n, 0, 0x80, 0x100,
@ 0x400, 0x20, 0x2000, 0}, then set_or_clear_bits(block, 2, 1) and
@ fn_08008770(block, 1).
@ Calls fn_0800ad68 with a block of four bytes (0x3a, 0, 0, 1). Then
@ init_eleven_field_record on a timer settings block: halfword 0 = 0,
@ period halfword = 72000000 / frequency / n - 1, other halfwords 0; passed
@ to fn_0800c590(0x40001000, block), then fn_0800c6dc(0x40001000, 0x20) and
@ set_or_clear_bit_0_0800c404(0x40001000, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_08008814,"ax",%progbits
	.p2align 2
	.global fn_08008814
	.thumb_func
	.type fn_08008814, %function
fn_08008814:
	push.w {r4, r5, r6, r7, r8, lr}
	ldr r1, .L08008938		@ 100000
	mov r8, r0			@ r8 = frequency
	vpush {d8, d9}
	sub sp, #0x40
	cmp r0, r1
	bhs.n .L0800882e
	movs r4, #0xb4			@ n = 180
	vldr s1, .L0800893c		@ 2.34
	b.n .L08008834
.L0800882e:
	movs r4, #0x24			@ n = 36
	vldr s1, .L08008940		@ 2.1
.L08008834:
	movs r5, #0			@ r5 = i
	vdiv.f32 s16, s0, s1		@ s16 = amplitude / divisor
	vldr s18, .L08008944		@ 2*pi
	vldr s17, .L08008948		@ 2047.5
	ldr r6, .L0800894c		@ 0x20000d7c
	vldr s19, .L08008950		@ 620.0
	ldr r7, .L08008954		@ 0x20005120, halfword table
	nop
.L0800884c:
	vmov s0, r5
	vcvt.f32.s32 s0, s0
	vmul.f32 s1, s0, s18
	vmov s0, r4
	vcvt.f32.s32 s2, s0
	vdiv.f32 s0, s1, s2
	bl sine_radians
	vmul.f32 s0, s0, s17
	vldr s1, [r6, #0x3c0]		@ float at 0x2000113c
	vmul.f32 s0, s0, s16
	vmla.f32 s0, s1, s19
	vadd.f32 s0, s0, s17
	vcvt.s32.f32 s0, s0
	vmov r0, s0
	strh.w r0, [r7, r5, lsl #1]
	.inst.n 0x1c6d			@ adds r5, r5, #1
	cmp r5, r4
	blt.n .L0800884c
	ldr r6, .L08008958		@ 0x40020430, channel block
	mov r0, r6
	bl fn_0800864c
	ldr r0, .L0800895c		@ 0x40007408
	strd r0, r7, [sp]
	add r1, sp, #8
	movs r0, #0x10
	movs r5, #0
	stm.w r1, {r0, r4, r5}
	movs r0, #0x80
	str r0, [sp, #0x14]
	lsls r0, r0, #1			@ r0 = 0x100
	str r0, [sp, #0x18]
	lsls r0, r0, #2			@ r0 = 0x400
	str r0, [sp, #0x1c]
	movs r0, #0x20
	str r0, [sp, #0x20]
	lsls r0, r0, #8			@ r0 = 0x2000
	strd r0, r5, [sp, #0x24]
	mov r1, sp
	mov r0, r6
	bl fn_08008794
	movs r2, #1
	movs r1, #2
	mov r0, r6
	bl set_or_clear_bits
	movs r1, #1
	mov r0, r6
	bl fn_08008770
	movs r0, #0x3a
	strb.w r0, [sp, #0x3c]
	strb.w r5, [sp, #0x3d]
	strb.w r5, [sp, #0x3e]
	movs r0, #1
	strb.w r0, [sp, #0x3f]
	add r0, sp, #0x3c
	bl fn_0800ad68
	add r0, sp, #0x2c
	bl init_eleven_field_record
	ldr r1, .L08008960		@ 72000000
	strh.w r5, [sp, #0x2c]
	udiv r0, r1, r8
	udiv r0, r0, r4
	.inst.n 0x1e40			@ subs r0, r0, #1
	strh.w r0, [sp, #0x30]
	ldr r4, .L08008964		@ 0x40001000
	strh.w r5, [sp, #0x32]
	strh.w r5, [sp, #0x2e]
	add r1, sp, #0x2c
	mov r0, r4
	bl fn_0800c590
	movs r1, #0x20
	mov r0, r4
	bl fn_0800c6dc
	movs r1, #1
	mov r0, r4
	bl set_or_clear_bit_0_0800c404
	add sp, #0x40
	vpop {d8, d9}
	pop.w {r4, r5, r6, r7, r8, pc}
	.short 0x0000			@ padding
.L08008938:
	.word 0x000186a0
.L0800893c:
	.word 0x4015c28f
.L08008940:
	.word 0x40066666
.L08008944:
	.word 0x40c90fdb
.L08008948:
	.word 0x44fff000
.L0800894c:
	.word 0x20000d7c
.L08008950:
	.word 0x441b0000
.L08008954:
	.word 0x20005120
.L08008958:
	.word 0x40020430
.L0800895c:
	.word 0x40007408
.L08008960:
	.word 0x044aa200
.L08008964:
	.word 0x40001000

@ ----------------------------------------------------------------------------
@ fn_08008e40 - s0 = float to store (r0 is overwritten); returns a float in
@ s0.
@ Sums the float array 0x20003150 over the count in the word 0x200011f0
@ (r2) and divides the sum by that count (computed before the store). Then
@ stores the argument at the index held in the word 0x200011f8, increments
@ the index and wraps it to 0 when it reaches the count. Returns the
@ average computed before the store.
@ Offsets from the base 0x2000057c: count 0xc74, index 0xc7c, array
@ 0x2800 + 0x3d4.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008e40,"ax",%progbits
	.p2align 2
	.global fn_08008e40
	.thumb_func
	.type fn_08008e40, %function
fn_08008e40:
	ldr r0, .L08008ea4		@ 0x2000057c
	vldr s1, .L08008ea0		@ 0.0, running sum
	movs r1, #0
	ldr.w r2, [r0, #0xc74]		@ count (word 0x200011f0)
	b.n .L08008e62
	nop				@ padding
.L08008e50:
	add.w r3, r0, r1, lsl #2
	add.w r3, r3, #0x2800
	.inst.n 0x1c49			@ adds r1, r1, #1
	vldr s2, [r3, #0x3d4]		@ array 0x20003150, element r1
	vadd.f32 s1, s2, s1
.L08008e62:
	cmp r2, r1
	bhi.n .L08008e50
	vmov s2, r2
	ldr.w r1, [r0, #0xc7c]		@ index (word 0x200011f8)
	vcvt.f32.u32 s3, s2
	add.w r1, r0, r1, lsl #2
	add.w r1, r1, #0x2800
	vdiv.f32 s2, s1, s3		@ s2 = average
	vstr s0, [r1, #0x3d4]		@ store the argument at the index
	ldr.w r1, [r0, #0xc7c]
	.inst.n 0x1c49			@ adds r1, r1, #1
	str.w r1, [r0, #0xc7c]
	ldr.w r2, [r0, #0xc74]
	cmp r1, r2
	blo.n .L08008e9a
	movs r1, #0
	str.w r1, [r0, #0xc7c]		@ wrap the index to 0
.L08008e9a:
	vmov.f32 s0, s2
	bx lr
.L08008ea0:
	.word 0x00000000
.L08008ea4:
	.word 0x2000057c

@ ----------------------------------------------------------------------------
@ fn_08008ea8 - s0 = float sample (r0 is overwritten); returns a float in
@ s0.
@ avg = sum of the float array 0x20001210 over the count in the word
@ 0x200011f0, divided by the count. When |sample - avg| <= |avg * 0.5| or
@ the sample bits are at least 0x4cd1cef0 as a signed integer: clears the
@ byte 0x2000000a, stores the sample at the index held in the word
@ 0x200011f4 and increments the index; when the index reaches the count it
@ wraps to 0, the word 0x20001200 is set to 1 and the word 0x20001204 is
@ set to 1 if it was 0. Returns avg.
@ Otherwise increments the byte 0x2000000a; when its old value was above 10
@ it fills both arrays 0x20001210 (with the sample) and 0x20003150 (with
@ the word 0x20005094) over the count, sets the index 0x200011f4 to 0, the
@ word 0x20001200 to 1 and returns (the sample); when it was 10 or less
@ returns avg.
@ Offsets from the base 0x2000057c: count 0xc74, index 0xc78, flag 0xc84,
@ flag 0xc88, array 0xc00 + 0x94, array 0x2800 + 0x3d4, source word
@ 0x4800 + 0x318.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008ea8,"ax",%progbits
	.p2align 2
	.global fn_08008ea8
	.thumb_func
	.type fn_08008ea8, %function
fn_08008ea8:
	push {r4, r5, r6, lr}
	ldr r0, .L08008f88		@ 0x2000057c
	vldr s2, .L08008f84		@ 0.0, running sum
	movs r1, #0
	ldr.w r2, [r0, #0xc74]		@ count (word 0x200011f0)
	b.n .L08008eca
.L08008eb8:
	add.w r3, r0, r1, lsl #2
	add.w r3, r3, #0xc00
	.inst.n 0x1c49			@ adds r1, r1, #1
	vldr s1, [r3, #0x94]		@ array 0x20001210, element r1
	vadd.f32 s2, s1, s2
.L08008eca:
	cmp r2, r1
	bhi.n .L08008eb8
	vmov s1, r2
	movs r3, #0
	movs r2, #1
	vcvt.f32.u32 s3, s1
	ldr r4, .L08008f8c		@ 0x2000000a
	vdiv.f32 s1, s2, s3		@ s1 = avg
	vmov.f32 s3, #0.5
	vsub.f32 s2, s0, s1
	vmul.f32 s3, s1, s3
	vabs.f32 s2, s2
	vabs.f32 s3, s3
	vcmpe.f32 s2, s3
	vmrs APSR_nzcv, fpscr
	ble.n .L08008f48
	vmov r1, s0
	ldr r5, .L08008f90		@ 0x4cd1cef0
	cmp r1, r5
	bge.n .L08008f48
	ldrb r1, [r4]
	adds r5, r1, #1
	strb r5, [r4]
	cmp r1, #0xa
	bls.n .L08008f7e
	movs r1, #0
	add.w r5, r0, #0x4800
	b.n .L08008f36
	nop				@ padding
.L08008f1c:
	add.w r4, r0, r1, lsl #2
	add.w r6, r4, #0xc00
	add.w r4, r4, #0x2800
	vstr s0, [r6, #0x94]		@ array 0x20001210, element r1 = sample
	vldr s1, [r5, #0x318]		@ word 0x20005094
	.inst.n 0x1c49			@ adds r1, r1, #1
	vstr s1, [r4, #0x3d4]		@ array 0x20003150, element r1
.L08008f36:
	ldr.w r4, [r0, #0xc74]
	cmp r4, r1
	bhi.n .L08008f1c
	str.w r3, [r0, #0xc78]		@ index = 0
	str.w r2, [r0, #0xc84]		@ word 0x20001200 = 1
	pop {r4, r5, r6, pc}
.L08008f48:
	strb r3, [r4]			@ clear the byte 0x2000000a
	ldr.w r1, [r0, #0xc78]
	add.w r1, r0, r1, lsl #2
	add.w r1, r1, #0xc00
	vstr s0, [r1, #0x94]		@ store the sample at the index
	ldr.w r1, [r0, #0xc78]
	.inst.n 0x1c49			@ adds r1, r1, #1
	str.w r1, [r0, #0xc78]
	ldr.w r4, [r0, #0xc74]
	cmp r1, r4
	blo.n .L08008f7e
	str.w r3, [r0, #0xc78]		@ wrap the index to 0
	str.w r2, [r0, #0xc84]		@ word 0x20001200 = 1
	ldr.w r1, [r0, #0xc88]
	cbnz r1, .L08008f7e
	str.w r2, [r0, #0xc88]		@ word 0x20001204 = 1
.L08008f7e:
	vmov.f32 s0, s1
	pop {r4, r5, r6, pc}
.L08008f84:
	.word 0x00000000
.L08008f88:
	.word 0x2000057c
.L08008f8c:
	.word 0x2000000a
.L08008f90:
	.word 0x4cd1cef0

@ ----------------------------------------------------------------------------
@ fn_08008f94 - r0 = frequency value, s0 = float; returns a float in s0.
@ Copies the 5 words 100, 120, 1000, 10000, 100000 from 0x0802aed0 (20
@ bytes, copy_bytes_080070dc) to the stack and looks for r0 among them; not
@ found returns 0.0 (vldr s0 from the literal 0x08009018 = 0).
@ Float bits below 0x3e4ccccd (0.2, signed compare) load the float at
@ 0x200010c4 + 24 * index; below 0x3f000000 (0.5) the float at 0x200010cc +
@ 24 * index; otherwise the float at 0x200010d4 + 24 * index (base
@ 0x2000057c from the literal 0x08009014, offsets 0x800 + 0x348, 0x350,
@ 0x358).
@ ----------------------------------------------------------------------------
	.section .text.fn_08008f94,"ax",%progbits
	.p2align 2
	.global fn_08008f94
	.thumb_func
	.type fn_08008f94, %function
fn_08008f94:
	push {r4, lr}
	mov r4, r0			@ r4 = frequency value
	vpush {d8}
	sub sp, #0x18
	vmov.f32 s16, s0		@ s16 = float argument
	movs r2, #0x14
	ldr r1, .L0800900c		@ 0x0802aed0, table of 5 words
	mov r0, sp
	bl copy_bytes_080070dc
	movs r1, #0
	mov r0, sp
.L08008fb0:
	ldr.w r2, [r0, r1, lsl #2]
	cmp r2, r4
	bne.n .L08008ffe
	vmov r2, s16
	ldr r3, .L08009010		@ 0x3e4ccccd
	ldr r0, .L08009014		@ 0x2000057c
	cmp r2, r3
	bge.n .L08008fdc
	add.w r1, r1, r1, lsl #1
	add.w r0, r0, r1, lsl #3
	add.w r0, r0, #0x800
	vldr s0, [r0, #0x348]
.L08008fd4:
	add sp, #0x18
	vpop {d8}
	pop {r4, pc}
.L08008fdc:
	vmov r2, s16
	add.w r1, r1, r1, lsl #1
	add.w r0, r0, r1, lsl #3
	cmp.w r2, #0x3f000000
	add.w r0, r0, #0x800
	bge.n .L08008ff8
	vldr s0, [r0, #0x350]
	b.n .L08008fd4
.L08008ff8:
	vldr s0, [r0, #0x358]
	b.n .L08008fd4
.L08008ffe:
	.inst.n 0x1c49			@ adds r1, r1, #1
	cmp r1, #5
	bcc.n .L08008fb0
	vldr s0, .L08009018		@ 0.0, not found
	b.n .L08008fd4
	.short 0x0000			@ padding
.L0800900c:
	.word d_0802aed0
.L08009010:
	.word 0x3e4ccccd
.L08009014:
	.word 0x2000057c
.L08009018:
	.word 0x00000000

@ ----------------------------------------------------------------------------
@ fn_0800901c - r0 = frequency value, s0 = float; returns a float in s0.
@ Same search as fn_08008f94 over the 5 words 100, 120, 1000, 10000, 100000
@ copied from 0x0802aebc (copy_bytes_080070dc, 20 bytes); not found returns
@ 0.0 (literal 0x080090a0 = 0).
@ Float bits below 0x3e4ccccd (0.2, signed compare) load the float at
@ 0x200010c0 + 24 * index; below 0x3f000000 (0.5) the float at 0x200010c8 +
@ 24 * index; otherwise the float at 0x200010d0 + 24 * index (base from the
@ literal 0x0800909c, offsets 0x800 + 0x344, 0x34c, 0x354).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800901c,"ax",%progbits
	.p2align 2
	.global fn_0800901c
	.thumb_func
	.type fn_0800901c, %function
fn_0800901c:
	push {r4, lr}
	mov r4, r0			@ r4 = frequency value
	vpush {d8}
	sub sp, #0x18
	vmov.f32 s16, s0		@ s16 = float argument
	movs r2, #0x14
	ldr r1, .L08009094		@ 0x0802aebc, table of 5 words
	mov r0, sp
	bl copy_bytes_080070dc
	movs r1, #0
	mov r0, sp
.L08009038:
	ldr.w r2, [r0, r1, lsl #2]
	cmp r2, r4
	bne.n .L08009086
	vmov r2, s16
	ldr r3, .L08009098		@ 0x3e4ccccd
	ldr r0, .L0800909c		@ 0x2000057c
	cmp r2, r3
	bge.n .L08009064
	add.w r1, r1, r1, lsl #1
	add.w r0, r0, r1, lsl #3
	add.w r0, r0, #0x800
	vldr s0, [r0, #0x344]
.L0800905c:
	add sp, #0x18
	vpop {d8}
	pop {r4, pc}
.L08009064:
	vmov r2, s16
	add.w r1, r1, r1, lsl #1
	add.w r0, r0, r1, lsl #3
	cmp.w r2, #0x3f000000
	add.w r0, r0, #0x800
	bge.n .L08009080
	vldr s0, [r0, #0x34c]
	b.n .L0800905c
.L08009080:
	vldr s0, [r0, #0x354]
	b.n .L0800905c
.L08009086:
	.inst.n 0x1c49			@ adds r1, r1, #1
	cmp r1, #5
	bcc.n .L08009038
	vldr s0, .L080090a0		@ 0.0, not found
	b.n .L0800905c
	.short 0x0000			@ padding
.L08009094:
	.word d_0802aebc
.L08009098:
	.word 0x3e4ccccd
.L0800909c:
	.word 0x2000057c
.L080090a0:
	.word 0x00000000

@ ----------------------------------------------------------------------------
@ fn_080090a4 - r0 = frequency value, s0 = float; returns a pointer in r0.
@ Copies the 5 words 100, 120, 1000, 10000, 100000 from 0x0802ae94
@ (copy_bytes_080070dc) and looks for r0 among them. Found with float bits
@ below 0x3e4ccccd (signed compare): returns 0x20000b20 + 0x90 * index.
@ Found with float bits at least 0x3e4ccccd: below 0x3f000000 returns
@ 0x20000b50 + 0x90 * index, else 0x20000b80 + 0x90 * index. Not found:
@ returns 0x20000b20 (base 0x2000057c from the literal 0x08009118, plus
@ 0x5a4, 0x5d4 or 0x604).
@ ----------------------------------------------------------------------------
	.section .text.fn_080090a4,"ax",%progbits
	.p2align 2
	.global fn_080090a4
	.thumb_func
	.type fn_080090a4, %function
fn_080090a4:
	push {r4, lr}
	mov r4, r0			@ r4 = frequency value
	vpush {d8}
	sub sp, #0x18
	vmov.f32 s16, s0		@ s16 = float argument
	movs r2, #0x14
	ldr r1, .L08009110		@ 0x0802ae94, table of 5 words
	mov r0, sp
	bl copy_bytes_080070dc
	movs r1, #0
	mov r0, sp
.L080090c0:
	ldr.w r2, [r0, r1, lsl #2]
	cmp r2, r4
	bne.n .L08009106
	vmov r2, s16
	ldr r3, .L08009114		@ 0x3e4ccccd
	ldr r0, .L08009118		@ 0x2000057c
	cmp r2, r3
	bge.n .L080090e8
	add.w r1, r1, r1, lsl #3
	add.w r0, r0, r1, lsl #4
.L080090dc:
	addw r0, r0, #0x5a4
.L080090e0:
	add sp, #0x18
	vpop {d8}
	pop {r4, pc}
.L080090e8:
	vmov r2, s16
	add.w r1, r1, r1, lsl #3
	add.w r0, r0, r1, lsl #4
	cmp.w r2, #0x3f000000
	bge.n .L08009100
	addw r0, r0, #0x5d4
	b.n .L080090e0
.L08009100:
	addw r0, r0, #0x604
	b.n .L080090e0
.L08009106:
	.inst.n 0x1c49			@ adds r1, r1, #1
	cmp r1, #5
	bcc.n .L080090c0
	ldr r0, .L08009118		@ not found: base 0x2000057c
	b.n .L080090dc
.L08009110:
	.word d_0802ae94
.L08009114:
	.word 0x3e4ccccd
.L08009118:
	.word 0x2000057c

@ ----------------------------------------------------------------------------
@ fn_080092cc - no parameters, no return value.
@ Sums the 128 signed halfwords at 0x20005d38 as floats, multiplies the sum
@ by 0.0078125 (0x3c000000), by 6.6 (0x40d33333) and divides it by 4095.0
@ (0x457ff000). The old value is the float at 0x20004d7c + 0x384
@ (0x20005100). When the distance (absolute difference, compared as integer
@ bits, signed) to the old value is above 0x3ca3d70a (0.02) the new value
@ is stored to 0x20005100.
@ ----------------------------------------------------------------------------
	.section .text.fn_080092cc,"ax",%progbits
	.p2align 2
	.global fn_080092cc
	.thumb_func
	.type fn_080092cc, %function
fn_080092cc:
	vldr s0, .L08009320		@ 0.0, running sum
	ldr r1, .L08009324		@ 0x20005d38
	movs r0, #0
.L080092d4:
	ldrsh.w r2, [r1, r0, lsl #1]
	.inst.n 0x1c40			@ adds r0, r0, #1
	vmov s1, r2
	cmp r0, #0x80
	vcvt.f32.s32 s1, s1
	vadd.f32 s0, s1, s0
	blt.n .L080092d4
	ldr r0, .L08009334		@ 0x20004d7c
	vldr s1, .L08009328		@ 0.0078125
	vldr s2, .L08009330		@ 4095.0
	ldr r2, .L08009338		@ 0x3ca3d70a
	vmul.f32 s0, s0, s1
	vldr s1, .L0800932c		@ 6.6
	vmul.f32 s1, s0, s1
	vdiv.f32 s0, s1, s2
	vldr s1, [r0, #0x384]		@ old value, 0x20005100
	vsub.f32 s1, s0, s1
	vabs.f32 s1, s1
	vmov r1, s1
	cmp r1, r2
	ble.n .L0800931e
	vstr s0, [r0, #0x384]
.L0800931e:
	bx lr
.L08009320:
	.word 0x00000000
.L08009324:
	.word 0x20005d38
.L08009328:
	.word 0x3c000000
.L0800932c:
	.word 0x40d33333
.L08009330:
	.word 0x457ff000
.L08009334:
	.word 0x20004d7c
.L08009338:
	.word 0x3ca3d70a

@ ----------------------------------------------------------------------------
@ fn_08009f10 - no parameters, no return value.
@ Calls fn_08008814 with s0 = float at 0x20001138 (0x20000d7c + 0x3bc) and
@ r0 = word at 0x20001144 (0x2000057c + 0xbc8), then fn_08007bdc.
@ Stores to the word 0x200011f0 a count chosen by the word 0x20001150
@ (0, 1, other) and the word 0x20001144 (100, 0x78, 1000, 10000, other):
@ The value order is the one of the word 0x20001144 = 100, 0x78, 1000,
@ 10000, other:
@   0x20001150 = 0:     0x60, 0x6e, 0x1d6, 0x45b, 0x44c
@   0x20001150 = 1:     0x2d, 0x34, 0xfa, 600, 0x24e
@   0x20001150 = other: 0x14, 0x16, 0x5f, 0x122, 0x118
@ Clears the words 0x200011f4, 0x200011f8, 0x200011fc, 0x20001200,
@ 0x20001208 and 0x2000120c.
@ ----------------------------------------------------------------------------
	.section .text.fn_08009f10,"ax",%progbits
	.p2align 2
	.global fn_08009f10
	.thumb_func
	.type fn_08009f10, %function
fn_08009f10:
	push {r4, lr}
	ldr r0, .L08009fdc		@ 0x20000d7c
	sub.w r4, r0, #0x800		@ r4 = 0x2000057c
	vldr s0, [r0, #0x3bc]		@ float at 0x20001138
	ldr.w r0, [r4, #0xbc8]		@ word 0x20001144
	bl fn_08008814
	bl fn_08007bdc
	ldr.w r0, [r4, #0xbd4]		@ word 0x20001150
	mov.w r2, #0x3e8
	movw r1, #0x2710
	cbz r0, .L08009f4e
	cmp r0, #1
	ldr.w r0, [r4, #0xbc8]
	beq.n .L08009f7c
	cmp r0, #0x64
	beq.n .L08009fa4
	cmp r0, #0x78
	beq.n .L08009fa8
	cmp r0, r2
	bne.n .L08009fac
	movs r0, #0x5f
	b.n .L08009fba
.L08009f4e:
	ldr.w r0, [r4, #0xbc8]
	cmp r0, #0x64
	beq.n .L08009f64
	cmp r0, #0x78
	beq.n .L08009f68
	cmp r0, r2
	bne.n .L08009f6c
	mov.w r0, #0x1d6
	b.n .L08009fba
.L08009f64:
	movs r0, #0x60
	b.n .L08009fba
.L08009f68:
	movs r0, #0x6e
	b.n .L08009fba
.L08009f6c:
	cmp r0, r1
	bne.n .L08009f76
	movw r0, #0x45b
	b.n .L08009fba
.L08009f76:
	movw r0, #0x44c
	b.n .L08009fba
.L08009f7c:
	cmp r0, #0x64
	beq.n .L08009f8c
	cmp r0, #0x78
	beq.n .L08009f90
	cmp r0, r2
	bne.n .L08009f94
	movs r0, #0xfa
	b.n .L08009fba
.L08009f8c:
	movs r0, #0x2d
	b.n .L08009fba
.L08009f90:
	movs r0, #0x34
	b.n .L08009fba
.L08009f94:
	cmp r0, r1
	bne.n .L08009f9e
	mov.w r0, #0x258
	b.n .L08009fba
.L08009f9e:
	movw r0, #0x24e
	b.n .L08009fba
.L08009fa4:
	movs r0, #0x14
	b.n .L08009fba
.L08009fa8:
	movs r0, #0x16
	b.n .L08009fba
.L08009fac:
	cmp r0, r1
	bne.n .L08009fb6
	mov.w r0, #0x122
	b.n .L08009fba
.L08009fb6:
	mov.w r0, #0x118
.L08009fba:
	str.w r0, [r4, #0xc74]		@ word 0x200011f0 = count
	movs r0, #0
	str.w r0, [r4, #0xc78]		@ word 0x200011f4
	str.w r0, [r4, #0xc7c]		@ word 0x200011f8
	str.w r0, [r4, #0xc80]		@ word 0x200011fc
	str.w r0, [r4, #0xc84]		@ word 0x20001200
	str.w r0, [r4, #0xc8c]		@ word 0x20001208
	str.w r0, [r4, #0xc90]		@ word 0x2000120c
	pop {r4, pc}
	.short 0x0000			@ padding
.L08009fdc:
	.word 0x20000d7c
