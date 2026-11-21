@ periph_34.s - peripheral register helpers: bit-field setters on register blocks, flag setters/getters, a block settings writer, a TIM2 pulse routine and GPIO setup sequences
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080079ac - switches four register blocks (0x40020800, 0x40020C00,
@ 0x40021800, 0x40021C00) with a mode.
@ r0 = mode, r1 = value; no return value.
@ Mode 0: calls fn_0800b2b8(0x100, 0) and fn_0800b2a4(r1), then clears bit 4 of
@ the words at offset 0x58 of the four blocks.
@ Other mode: calls fn_0800b2b8(r1, 1) and fn_0800b2a4(0), then sets bit 4 of
@ the same four words.
@ r1 is kept in r8; the block bases are held in r7, r4, r5, r6.
@ ----------------------------------------------------------------------------
	.section .text.fn_080079ac,"ax",%progbits
	.p2align 2
	.global fn_080079ac
	.thumb_func
	.type fn_080079ac, %function
fn_080079ac:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r7, .L08007a20		@ 0x40020800
	ldr	r4, .L08007a24		@ 0x40020C00
	ldr	r5, .L08007a28		@ 0x40021800
	ldr	r6, .L08007a2c		@ 0x40021C00
	mov	r8, r1
	cbz	r0, .L080079ee		@ mode 0: clear path
	movs	r1, #1
	mov	r0, r8
	bl	fn_0800b2b8		@ fn_0800b2b8(value, 1)
	movs	r0, #0
	bl	fn_0800b2a4		@ fn_0800b2a4(0)
	ldr	r0, [r7, #0x58]
	orr.w	r0, r0, #0x10		@ set bit 4
	str	r0, [r7, #0x58]
	ldr	r0, [r4, #0x58]
	orr.w	r0, r0, #0x10
	str	r0, [r4, #0x58]
	ldr	r0, [r5, #0x58]
	orr.w	r0, r0, #0x10
	str	r0, [r5, #0x58]
	ldr	r0, [r6, #0x58]
	orr.w	r0, r0, #0x10
.L080079e8:
	str	r0, [r6, #0x58]
	pop.w	{r4, r5, r6, r7, r8, pc}
.L080079ee:
	movs	r1, #0
	mov.w	r0, #0x100
	bl	fn_0800b2b8		@ fn_0800b2b8(0x100, 0)
	mov	r0, r8
	bl	fn_0800b2a4		@ fn_0800b2a4(value)
	ldr	r0, [r7, #0x58]
	bic.w	r0, r0, #0x10		@ clear bit 4
	str	r0, [r7, #0x58]
	ldr	r0, [r4, #0x58]
	bic.w	r0, r0, #0x10
	str	r0, [r4, #0x58]
	ldr	r0, [r5, #0x58]
	bic.w	r0, r0, #0x10
	str	r0, [r5, #0x58]
	ldr	r0, [r6, #0x58]
	bic.w	r0, r0, #0x10
	b.n	.L080079e8
	.short	0x0000			@ padding
.L08007a20:
	.word	0x40020800
.L08007a24:
	.word	0x40020c00
.L08007a28:
	.word	0x40021800
.L08007a2c:
	.word	0x40021c00

@ ----------------------------------------------------------------------------
@ fn_08007a30 - writes pin-function selector fields of a register block.
@ r0 = register block base, r1 = index n, r2 = slot, r3 = value; no return
@ value.
@ n == 0x12: replaces bits 0..2 of word [r0+0x5c] with r3.
@ n < 10: writes r3 into the 3-bit field n*3 of word [r0+0x10].
@ Otherwise into the 3-bit field (n-10)*3 of word [r0+0xc].
@ Slot < 7: writes n into the 5-bit field (slot-1)*5 of word [r0+0x34];
@ slot < 13: field (slot-7)*5 of word [r0+0x30]; otherwise field
@ (slot-13)*5 of word [r0+0x2c].
@ ----------------------------------------------------------------------------
	.section .text.fn_08007a30,"ax",%progbits
	.p2align 2
	.global fn_08007a30
	.thumb_func
	.type fn_08007a30, %function
fn_08007a30:
	push	{r4, r5, r6, lr}
	cmp	r1, #0x12
	beq.n	.L08007a52
	movs	r4, #7			@ 3-bit field mask
	cmp	r1, #9
	bls.n	.L08007a5e
	ldr	r5, [r0, #0xc]		@ n >= 10: word at +0xc
	sub.w	r6, r1, #0xa
	add.w	r6, r6, r6, lsl #1	@ (n-10)*3
	lsls	r4, r6
	bics	r5, r4
	lsls	r3, r6
	orrs	r5, r3
	str	r5, [r0, #0xc]
	b.n	.L08007a6e
.L08007a52:
	ldr	r4, [r0, #0x5c]		@ n == 0x12: bits 0..2 of +0x5c
	bic.w	r4, r4, #7
	orrs	r4, r3
	str	r4, [r0, #0x5c]
	b.n	.L08007a6e
.L08007a5e:
	ldr	r5, [r0, #0x10]		@ n < 10: word at +0x10
	add.w	r6, r1, r1, lsl #1	@ n*3
	lsls	r4, r6
	bics	r5, r4
	lsls	r3, r6
	orrs	r5, r3
	str	r5, [r0, #0x10]
.L08007a6e:
	movs	r3, #0x1f		@ 5-bit field mask
	cmp	r2, #7
	bcs.n	.L08007a88
	ldr	r4, [r0, #0x34]		@ slot < 7
	.inst.n	0x1e52		@ subs r2, r2, #1
	add.w	r2, r2, r2, lsl #2	@ (slot-1)*5
	lsls	r3, r2
	bics	r4, r3
	lsls	r1, r2
	orrs	r4, r1
	str	r4, [r0, #0x34]
	pop	{r4, r5, r6, pc}
.L08007a88:
	cmp	r2, #0xd
	bcs.n	.L08007aa0
	ldr	r4, [r0, #0x30]		@ slot < 13
	.inst.n	0x1fd2		@ subs r2, r2, #7
	add.w	r2, r2, r2, lsl #2	@ (slot-7)*5
	lsls	r3, r2
	bics	r4, r3
	lsls	r1, r2
	orrs	r4, r1
	str	r4, [r0, #0x30]
	pop	{r4, r5, r6, pc}
.L08007aa0:
	ldr	r4, [r0, #0x2c]		@ slot >= 13
	subs	r2, #0xd
	add.w	r2, r2, r2, lsl #2	@ (slot-13)*5
	lsls	r3, r2
	bics	r4, r3
	lsls	r1, r2
	orrs	r4, r1
	str	r4, [r0, #0x2c]
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08007ab4 - pulses a clock/reset mask for one of four register blocks.
@ r0 = register block base; no return value.
@ Maps 0x40020800 to 0x1000, 0x40020C00 to 0x2000, 0x40021800 to 0x4000 and
@ 0x40021C00 to 0x8000 (any other base returns), then calls
@ set_or_clear_bits_40021028(mask, 1) followed by
@ set_or_clear_bits_40021028(mask, 0) (the second as a tail jump).
@ ----------------------------------------------------------------------------
	.section .text.fn_08007ab4,"ax",%progbits
	.p2align 2
	.global fn_08007ab4
	.thumb_func
	.type fn_08007ab4, %function
fn_08007ab4:
	ldr	r1, .L08007af8		@ 0x40020800
	push	{r4, lr}
	cmp	r0, r1
	bne.n	.L08007ac2
	movs	r1, #1
	asrs	r4, r0, #0x12		@ 0x40020800 >> 18 = 0x1000
	b.n	.L08007ae4
.L08007ac2:
	ldr	r1, .L08007afc		@ 0x40020C00
	cmp	r0, r1
	bne.n	.L08007ace
	movs	r1, #1
	lsls	r4, r1, #0xd		@ 0x2000
	b.n	.L08007ae4
.L08007ace:
	ldr	r1, .L08007b00		@ 0x40021800
	cmp	r0, r1
	bne.n	.L08007ada
	movs	r1, #1
	lsls	r4, r1, #0xe		@ 0x4000
	b.n	.L08007ae4
.L08007ada:
	ldr	r1, .L08007b04		@ 0x40021C00
	cmp	r0, r1
	bne.n	.L08007af6
	movs	r1, #1
	lsls	r4, r1, #0xf		@ 0x8000
.L08007ae4:
	mov	r0, r4
	bl	set_or_clear_bits_40021028	@ (mask, 1): r1 is 1
	mov	r0, r4
	pop.w	{r4, lr}
	movs	r1, #0
	b.w	set_or_clear_bits_40021028	@ (mask, 0)
.L08007af6:
	pop	{r4, pc}
.L08007af8:
	.word	0x40020800
.L08007afc:
	.word	0x40020c00
.L08007b00:
	.word	0x40021800
.L08007b04:
	.word	0x40021c00

@ ----------------------------------------------------------------------------
@ fn_08007b08 - sets or clears bit 0 of a register block word, then delays.
@ r0 = register block base, r1 = flag; no return value.
@ Sets bit 0 of word [r0+8] when r1 != 0, clears it otherwise. Then runs a
@ counting delay loop from 2 up to 0x128.
@ ----------------------------------------------------------------------------
	.section .text.fn_08007b08,"ax",%progbits
	.p2align 2
	.global fn_08007b08
	.thumb_func
	.type fn_08007b08, %function
fn_08007b08:
	cmp	r1, #0
	ldr	r1, [r0, #8]
	beq.n	.L08007b14
	orr.w	r1, r1, #1
	b.n	.L08007b18
.L08007b14:
	bic.w	r1, r1, #1
.L08007b18:
	str	r1, [r0, #8]
	movs	r0, #2
	mov.w	r1, #0x128
.L08007b20:
	.inst.n	0x1c40		@ adds r0, r0, #1
	cmp	r0, r1
	bcc.n	.L08007b20
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08007b28 - sets or clears bit 8 (0x100) of a register block word.
@ r0 = register block base, r1 = flag; no return value.
@ Sets bit 8 of word [r0+8] when r1 != 0, clears it otherwise.
@ ----------------------------------------------------------------------------
	.section .text.fn_08007b28,"ax",%progbits
	.p2align 2
	.global fn_08007b28
	.thumb_func
	.type fn_08007b28, %function
fn_08007b28:
	cmp	r1, #0
	ldr	r1, [r0, #8]
	beq.n	.L08007b34
	orr.w	r1, r1, #0x100
	b.n	.L08007b38
.L08007b34:
	bic.w	r1, r1, #0x100
.L08007b38:
	str	r1, [r0, #8]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08007b3c - sets or clears bits 20 and 22 (0x500000) of a register block
@ word.
@ r0 = register block base, r1 = flag; no return value.
@ Sets bits 20 and 22 of word [r0+8] when r1 != 0, clears them (mask
@ 0xffafffff) otherwise.
@ ----------------------------------------------------------------------------
	.section .text.fn_08007b3c,"ax",%progbits
	.p2align 2
	.global fn_08007b3c
	.thumb_func
	.type fn_08007b3c, %function
fn_08007b3c:
	cmp	r1, #0
	ldr	r1, [r0, #8]
	beq.n	.L08007b48
	orr.w	r1, r1, #0x500000
	b.n	.L08007b4c
.L08007b48:
	bic.w	r1, r1, #0x500000
.L08007b4c:
	str	r1, [r0, #8]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08007b50 - tests a register block for "word +0x54 is 0 and bit 2 of +8".
@ r0 = register block base; returns 1 when word [r0+0x54] == 0 and bit 2 of
@ word [r0+8] is set, else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08007b50,"ax",%progbits
	.global fn_08007b50
	.thumb_func
	.type fn_08007b50, %function
fn_08007b50:
	mov	r1, r0
	movs	r0, #0
	ldr	r2, [r1, #8]
	lsls	r2, r2, #0x1d		@ bit 2 to the sign bit
	bpl.n	.L08007b5c
	movs	r0, #1
.L08007b5c:
	ldr	r1, [r1, #0x54]
	cmp	r1, #0
	beq.n	.L08007b64
	movs	r0, #0
.L08007b64:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08007b66 - tests a mask against a register block word.
@ r0 = register block base, r1 = mask; returns 1 when word [r0+0x58] & r1 is
@ not 0, else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08007b66,"ax",%progbits
	.global fn_08007b66
	.thumb_func
	.type fn_08007b66, %function
fn_08007b66:
	mov	r2, r0
	movs	r0, #0
	ldr	r2, [r2, #0x58]
	tst	r2, r1
	beq.n	.L08007b72
	movs	r0, #1
.L08007b72:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08007b74 - writes a settings block into a register block.
@ r0 = register block base, r1 = pointer to a settings block s (word at s+0,
@ byte at s+4, byte at s+5, words at s+8 and s+12, byte at s+16); no return
@ value.
@ Writes 0x28 to [r0+0x60].
@ [r0+4] = ([r0+4] & 0xfff0feff) | word[s+0] | (byte[s+4] << 8).
@ [r0+8] = ([r0+8] & 0xfff1f7fd) | word[s+8] | word[s+12] | (byte[s+5] << 1).
@ [r0+0x2c] = ([r0+0x2c] & 0xff0fffff) | ((byte[s+16] - 1) & 0xff) << 20.
@ ----------------------------------------------------------------------------
	.section .text.fn_08007b74,"ax",%progbits
	.p2align 2
	.global fn_08007b74
	.thumb_func
	.type fn_08007b74, %function
fn_08007b74:
	push	{r4, lr}
	movs	r3, #0x28
	str	r3, [r0, #0x60]
	ldr	r2, [r0, #4]
	ldr	r3, .L08007bb8		@ 0xfff0feff
	ldrb	r4, [r1, #4]
	ands	r2, r3
	ldr	r3, [r1, #0]
	orr.w	r2, r2, r4, lsl #8
	orrs	r3, r2
	str	r3, [r0, #4]
	ldr	r2, [r0, #8]
	ldr	r3, .L08007bbc		@ 0xfff1f7fd
	ands	r2, r3
	ldrd	r4, r3, [r1, #8]
	orrs	r3, r4
	ldrb	r4, [r1, #5]
	orr.w	r2, r2, r4, lsl #1
	orrs	r3, r2
	str	r3, [r0, #8]
	ldr	r2, [r0, #0x2c]
	ldrb	r1, [r1, #0x10]
	bic.w	r2, r2, #0xf00000
	.inst.n	0x1e49		@ subs r1, r1, #1
	uxtb	r1, r1
	orr.w	r1, r2, r1, lsl #0x14
	str	r1, [r0, #0x2c]
	pop	{r4, pc}
	.short	0x0000			@ padding
.L08007bb8:
	.word	0xfff0feff
.L08007bbc:
	.word	0xfff1f7fd

@ ----------------------------------------------------------------------------
@ fn_08007bc0 - sets bit 2 of a register block word when allowed, then delays.
@ r0 = register block base; no return value.
@ Sets bit 2 of word [r0+8] when word [r0+0x54] == 0. Then runs a counting
@ delay loop from 2 up to 0x128.
@ ----------------------------------------------------------------------------
	.section .text.fn_08007bc0,"ax",%progbits
	.p2align 2
	.global fn_08007bc0
	.thumb_func
	.type fn_08007bc0, %function
fn_08007bc0:
	ldr	r1, [r0, #0x54]
	cbnz	r1, .L08007bcc
	ldr	r1, [r0, #8]
	orr.w	r1, r1, #4
	str	r1, [r0, #8]
.L08007bcc:
	movs	r0, #2
	mov.w	r1, #0x128
.L08007bd2:
	.inst.n	0x1c40		@ adds r0, r0, #1
	cmp	r0, r1
	bcc.n	.L08007bd2
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0800811c - tail jump to fn_08008dc0 (same parameters).
@ The unit is the single instruction b.w fn_08008dc0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800811c,"ax",%progbits
	.p2align 2
	.global fn_0800811c
	.thumb_func
	.type fn_0800811c, %function
fn_0800811c:
	b.w	fn_08008dc0

@ ----------------------------------------------------------------------------
@ fn_08008120 - TIM2 (0x40000000) sequence around a delay.
@ r0 = delay value (passed to fn_08011c68); no return value.
@ Calls fn_0800c6ec(0x40000000, halfword at 0x20001160), then
@ fn_08011c68(r0), then fn_0800c6ec(0x40000000, 0) as a tail jump.
@ The halfword is read from 0x2000057c + 0xbe4.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008120,"ax",%progbits
	.p2align 2
	.global fn_08008120
	.thumb_func
	.type fn_08008120, %function
fn_08008120:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	ldr	r0, .L08008148		@ 0x2000057c
	mov.w	r5, #0x40000000
	ldrh.w	r0, [r0, #0xbe4]	@ halfword at 0x20001160
	uxth	r1, r0
	mov	r0, r5
	bl	fn_0800c6ec
	mov	r0, r4
	bl	fn_08011c68
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	movs	r1, #0
	b.w	fn_0800c6ec
.L08008148:
	.word	0x2000057c

@ ----------------------------------------------------------------------------
@ fn_0800814c - sets up TIM2 (0x40000000) and GPIOB pins.
@ No parameters, no return value.
@ Calls fn_0800911c(0x180100, 1) and fn_08008338(0x40010c00 (GPIOB), 8, 0x18).
@ Builds a settings block (halfword 0x47 at +0, 0 at +2, 0x172 at +4, 0 at +6)
@ for fn_0800c590(0x40000000, block) and a second block (0x60 at +0x10, 1 at
@ +0x12, 0 at +0x16 and +0x18) for fn_0800c490(0x40000000, block).
@ Then fn_0800c328(0x40000000, 8), set_or_clear_bit_7(0x40000000, 1) and
@ set_or_clear_bit_0_0800c404(0x40000000, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800814c,"ax",%progbits
	.p2align 2
	.global fn_0800814c
	.thumb_func
	.type fn_0800814c, %function
fn_0800814c:
	push	{r4, r5, lr}
	sub	sp, #0x24
	movs	r1, #1
	ldr	r0, .L080081c0		@ 0x180100
	bl	fn_0800911c
	movs	r2, #0x18
	movs	r1, #8
	ldr	r0, .L080081c4		@ 0x40010c00 (GPIOB)
	bl	fn_08008338
	mov.w	r0, #0x172
	strh.w	r0, [sp, #4]
	movs	r0, #0x47
	strh.w	r0, [sp, #0]
	movs	r4, #0
	mov.w	r5, #0x40000000		@ TIM2 base
	strh.w	r4, [sp, #6]
	strh.w	r4, [sp, #2]
	mov	r1, sp
	mov	r0, r5
	bl	fn_0800c590
	movs	r0, #0x60
	strh.w	r0, [sp, #0x10]
	movs	r0, #1
	strh.w	r0, [sp, #0x12]
	strh.w	r4, [sp, #0x16]
	strh.w	r4, [sp, #0x18]
	add	r1, sp, #0x10
	mov	r0, r5
	bl	fn_0800c490
	movs	r1, #8
	mov	r0, r5
	bl	fn_0800c328
	movs	r1, #1
	mov	r0, r5
	bl	set_or_clear_bit_7
	movs	r1, #1
	mov	r0, r5
	bl	set_or_clear_bit_0_0800c404
	add	sp, #0x24
	pop	{r4, r5, pc}
	.short	0x0000			@ padding
.L080081c0:
	.word	0x00180100
.L080081c4:
	.word	0x40010c00

@ ----------------------------------------------------------------------------
@ fn_080081fa - masks a register block word.
@ r0 = register block base, r1 = mask; returns word [r0+8] & r1.
@ ----------------------------------------------------------------------------
	.section .text.fn_080081fa,"ax",%progbits
	.global fn_080081fa
	.thumb_func
	.type fn_080081fa, %function
fn_080081fa:
	ldr	r0, [r0, #8]
	ands	r0, r1
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08008200 - initial GPIO output levels and pin modes.
@ No parameters, no return value. Port bases: GPIOA 0x40010800, GPIOB
@ 0x40010C00, GPIOC 0x40011000, GPIOD 0x40011400, GPIOE 0x40011800.
@ fn_08008350(port, mask, flag) writes a mask to a port word (+0x14 for flag 0,
@ +0x10 otherwise); fn_08008338(port, mask, mode) configures the pins of mask
@ with a mode byte. Calls, in order:
@   fn_08008350(GPIOA, 0x100, 0), fn_08008338(GPIOA, 0x100, 0x10),
@   fn_08008350(GPIOB, 0x10, 0),  fn_08008338(GPIOB, 0x10, 0x10),
@   mode 0x10: GPIOA mask 1, GPIOC mask 8, GPIOB masks 0x2000 and 0x1000;
@   fn_08008350(GPIOB, 0x2000, 1) and fn_08008350(GPIOB, 0x1000, 1);
@   mode 0x48: GPIOD 0x1000, GPIOC 0x40, 0x80, 0x100, 0x200, 0x400; GPIOA
@   0x8000; GPIOC 0x800, 0x1000; GPIOB 0x20;
@   mode 0x28: GPIOB 0x80;
@   mode 0x48: GPIOE 0x40, GPIOB 0x100 and 0x200, GPIOE 1.
@ Ends with a tail jump to fn_0800911c(0x300200, 1).
@ Registers: r5 = GPIOA, r9 = GPIOB, r8 = GPIOC, r4 = 0x100, r6 = 0x2000,
@ r7 = 0x1000.
@ Own build: the first call (PA8, the power latch, driven low until main
@ 0x08027FF4 sets it high after 0x08011C68(1000)) goes through own_pa8_level
@ (own/ctl.s), which keeps PA8 high after a soft restart.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008200,"ax",%progbits
	.p2align 2
	.global fn_08008200
	.thumb_func
	.type fn_08008200, %function
fn_08008200:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr	r5, .L08008320		@ GPIOA
	mov.w	r4, #0x100
	movs	r2, #0
	mov	r1, r4
	mov	r0, r5
.ifdef OWN
	bl	own_pa8_level		@ 0x08008210: (GPIOA, 0x100, 0), or 1 after a soft restart
.else
	bl	fn_08008350		@ (GPIOA, 0x100, 0)
.endif
	movs	r2, #0x10
	mov	r1, r4
	mov	r0, r5
	bl	fn_08008338		@ (GPIOA, 0x100, 0x10)
	ldr.w	r9, .L08008324		@ GPIOB
	movs	r2, #0
	movs	r1, #0x10
	mov	r0, r9
	bl	fn_08008350		@ (GPIOB, 0x10, 0)
	movs	r2, #0x10
	mov	r1, r2
	mov	r0, r9
	bl	fn_08008338		@ (GPIOB, 0x10, 0x10)
	movs	r2, #0x10
	movs	r1, #1
	mov	r0, r5
	bl	fn_08008338		@ (GPIOA, 1, 0x10)
	ldr.w	r8, .L08008328		@ GPIOC
	movs	r2, #0x10
	movs	r1, #8
	mov	r0, r8
	bl	fn_08008338		@ (GPIOC, 8, 0x10)
	movs	r2, #0x10
	lsls	r6, r2, #9		@ 0x2000
	mov	r1, r6
	mov	r0, r9
	bl	fn_08008338		@ (GPIOB, 0x2000, 0x10)
	movs	r2, #0x10
	lsls	r7, r2, #8		@ 0x1000
	mov	r1, r7
	mov	r0, r9
	bl	fn_08008338		@ (GPIOB, 0x1000, 0x10)
	movs	r2, #1
	mov	r1, r6
	mov	r0, r9
	bl	fn_08008350		@ (GPIOB, 0x2000, 1)
	movs	r2, #1
	mov	r1, r7
	mov	r0, r9
	bl	fn_08008350		@ (GPIOB, 0x1000, 1)
	movs	r2, #0x48
	mov	r1, r7
	ldr	r0, .L0800832c		@ GPIOD
	bl	fn_08008338		@ (GPIOD, 0x1000, 0x48)
	movs	r2, #0x48
	movs	r1, #0x40
	mov	r0, r8
	bl	fn_08008338		@ (GPIOC, 0x40, 0x48)
	movs	r2, #0x48
	movs	r1, #0x80
	mov	r0, r8
	bl	fn_08008338		@ (GPIOC, 0x80, 0x48)
	movs	r2, #0x48
	mov	r1, r4
	mov	r0, r8
	bl	fn_08008338		@ (GPIOC, 0x100, 0x48)
	lsls	r6, r4, #1		@ 0x200
	movs	r2, #0x48
	mov	r1, r6
	mov	r0, r8
	bl	fn_08008338		@ (GPIOC, 0x200, 0x48)
	movs	r2, #0x48
	lsls	r1, r4, #2		@ 0x400
	mov	r0, r8
	bl	fn_08008338		@ (GPIOC, 0x400, 0x48)
	movs	r2, #0x48
	lsls	r1, r4, #7		@ 0x8000
	mov	r0, r5
	bl	fn_08008338		@ (GPIOA, 0x8000, 0x48)
	movs	r2, #0x48
	lsls	r1, r4, #3		@ 0x800
	mov	r0, r8
	bl	fn_08008338		@ (GPIOC, 0x800, 0x48)
	movs	r2, #0x48
	mov	r1, r7
	mov	r0, r8
	bl	fn_08008338		@ (GPIOC, 0x1000, 0x48)
	movs	r2, #0x48
	movs	r1, #0x20
	mov	r0, r9
	bl	fn_08008338		@ (GPIOB, 0x20, 0x48)
	movs	r2, #0x28
	movs	r1, #0x80
	mov	r0, r9
	bl	fn_08008338		@ (GPIOB, 0x80, 0x28)
	ldr	r5, .L08008330		@ GPIOE
	movs	r2, #0x48
	movs	r1, #0x40
	mov	r0, r5
	bl	fn_08008338		@ (GPIOE, 0x40, 0x48)
	movs	r2, #0x48
	mov	r1, r4
	mov	r0, r9
	bl	fn_08008338		@ (GPIOB, 0x100, 0x48)
	movs	r2, #0x48
	mov	r1, r6
	mov	r0, r9
	bl	fn_08008338		@ (GPIOB, 0x200, 0x48)
	movs	r2, #0x48
	movs	r1, #1
	mov	r0, r5
	bl	fn_08008338		@ (GPIOE, 1, 0x48)
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	movs	r1, #1
	ldr	r0, .L08008334		@ 0x300200
	b.w	fn_0800911c
.L08008320:
	.word	0x40010800
.L08008324:
	.word	0x40010c00
.L08008328:
	.word	0x40011000
.L0800832c:
	.word	0x40011400
.L08008330:
	.word	0x40011800
.L08008334:
	.word	0x00300200

@ ----------------------------------------------------------------------------
@ fn_08008338 - configures pins of a port from a mask and a mode byte.
@ r0 = port base, r1 = pin mask (halfword), r2 = mode byte; no return value.
@ Builds a 4-byte block on the stack (halfword mask at +0, byte 3 at +2, byte
@ mode at +3) and calls fn_08009228(port, block).
@ ----------------------------------------------------------------------------
	.section .text.fn_08008338,"ax",%progbits
	.p2align 2
	.global fn_08008338
	.thumb_func
	.type fn_08008338, %function
fn_08008338:
	push	{r3, lr}
	strh.w	r1, [sp, #0]
	strb.w	r2, [sp, #3]
	movs	r1, #3
	strb.w	r1, [sp, #2]
	mov	r1, sp
	bl	fn_08009228
	pop	{r3, pc}

@ ----------------------------------------------------------------------------
@ fn_08008350 - writes a pin mask to one of two port words.
@ r0 = port base, r1 = pin mask, r2 = flag; no return value.
@ Flag 0: stores r1 to word [r0+0x14]; otherwise stores r1 to word [r0+0x10].
@ ----------------------------------------------------------------------------
	.section .text.fn_08008350,"ax",%progbits
	.p2align 2
	.global fn_08008350
	.thumb_func
	.type fn_08008350, %function
fn_08008350:
	cbz	r2, .L08008356
	str	r1, [r0, #0x10]
	bx	lr
.L08008356:
	str	r1, [r0, #0x14]
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08008504 - enables peripheral clocks and starts SysTick.
@ No parameters, no return value.
@ Calls set_or_clear_bits_40021014(3, 1) and (0xf000, 1),
@ set_or_clear_bits_4002101c (RCC_APB1PCLKEN) with (0x8000003f, 1) and
@ (0x20000000, 1), and set_or_clear_bits_40021018 (RCC_APB2PCLKEN) with
@ (0x1c, 1), (0x61, 1) and (0x6800, 1).
@ Reload value = word 0x200002b0 / 100 - 1 (udiv); when it is below 0x1000000
@ it writes it to 0xe000e014, writes 0xf0 to the byte 0xe000ed23, 0 to
@ 0xe000e018 and 7 to 0xe000e010 (SysTick registers).
@ ----------------------------------------------------------------------------
	.section .text.fn_08008504,"ax",%progbits
	.p2align 2
	.global fn_08008504
	.thumb_func
	.type fn_08008504, %function
fn_08008504:
	push	{r4, lr}
	movs	r1, #1
	movs	r0, #3
	bl	set_or_clear_bits_40021014
	movs	r1, #1
	mov.w	r0, #0xf000
	bl	set_or_clear_bits_40021014
	movs	r1, #1
	ldr	r0, .L0800856c		@ 0x8000003f
	bl	set_or_clear_bits_4002101c
	movs	r1, #1
	lsls	r0, r1, #0x1d		@ 0x20000000
	bl	set_or_clear_bits_4002101c
	movs	r1, #1
	movs	r0, #0x1c
	bl	set_or_clear_bits_40021018
	movs	r1, #1
	movs	r0, #0x61
	bl	set_or_clear_bits_40021018
	movs	r1, #1
	mov.w	r0, #0x6800
	bl	set_or_clear_bits_40021018
	ldr	r0, .L08008570		@ 0x200002b0
	movs	r1, #0x64
	ldr	r0, [r0, #0]
	udiv	r0, r0, r1		@ word / 100
	.inst.n	0x1e40		@ subs r0, r0, #1
	cmp.w	r0, #0x1000000
	bcs.n	.L0800856a
	mov.w	r1, #0xe000e000
	str	r0, [r1, #0x14]		@ 0xe000e014 = reload value
	ldr	r2, .L08008574		@ 0xe000e00f
	movs	r0, #0xf0
	strb.w	r0, [r2, #0xd14]	@ byte 0xe000ed23 = 0xf0
	movs	r0, #0
	str	r0, [r1, #0x18]		@ 0xe000e018 = 0
	movs	r0, #7
	str	r0, [r1, #0x10]		@ 0xe000e010 = 7
.L0800856a:
	pop	{r4, pc}
.L0800856c:
	.word	0x8000003f
.L08008570:
	.word	0x200002b0
.L08008574:
	.word	0xe000e00f

@ ----------------------------------------------------------------------------
@ fn_08008578 - sets or clears bit (0x1000 << n) of the word 0x40007400.
@ r0 = bit number n, r1 = flag; no return value.
@ Sets (r1 != 0) or clears the bit 0x1000 << n of word 0x40007400.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008578,"ax",%progbits
	.p2align 2
	.global fn_08008578
	.thumb_func
	.type fn_08008578, %function
fn_08008578:
	ldr	r2, .L0800858c		@ 0x40007400
	asrs	r3, r2, #0x12		@ 0x1000
	lsls	r3, r0
	ldr	r0, [r2, #0]
	cbz	r1, .L08008586
	orrs	r0, r3
	b.n	.L08008588
.L08008586:
	bics	r0, r3
.L08008588:
	str	r0, [r2, #0]
	bx	lr
.L0800858c:
	.word	0x40007400

@ ----------------------------------------------------------------------------
@ fn_08008590 - sets or clears bit (1 << n) of the word 0x40007400.
@ r0 = bit number n, r1 = flag; no return value.
@ Sets (r1 != 0) or clears the bit 1 << n of word 0x40007400.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008590,"ax",%progbits
	.p2align 2
	.global fn_08008590
	.thumb_func
	.type fn_08008590, %function
fn_08008590:
	ldr	r2, .L080085a4		@ 0x40007400
	movs	r3, #1
	lsls	r3, r0
	ldr	r0, [r2, #0]
	cbz	r1, .L0800859e
	orrs	r0, r3
	b.n	.L080085a0
.L0800859e:
	bics	r0, r3
.L080085a0:
	str	r0, [r2, #0]
	bx	lr
.L080085a4:
	.word	0x40007400

@ ----------------------------------------------------------------------------
@ fn_080085a8 - writes a shifted combination of four words into 0x40007400.
@ r0 = shift n, r1 = pointer to a block of four words; no return value.
@ Word 0x40007400 = ((w0 | w1 | w2 | w3) << n) | (word 0x40007400 & ~(0xffe << n)).
@ ----------------------------------------------------------------------------
	.section .text.fn_080085a8,"ax",%progbits
	.p2align 2
	.global fn_080085a8
	.thumb_func
	.type fn_080085a8, %function
fn_080085a8:
	push	{r4, r5, lr}
	ldr	r4, .L080085cc		@ 0x40007400
	ldr	r3, [r4, #0]
	movw	r2, #0xffe
	lsls	r2, r0
	bics	r3, r2
	ldrd	r2, r5, [r1, #0]
	orrs	r2, r5
	ldrd	r5, r1, [r1, #8]
	orrs	r5, r1
	orrs	r2, r5
	lsls	r2, r0
	orrs	r2, r3
	str	r2, [r4, #0]
	pop	{r4, r5, pc}
.L080085cc:
	.word	0x40007400

@ ----------------------------------------------------------------------------
@ fn_080085d0 - exception handler for vector word 74.
@ No parameters, no return value.
@ Writes 0x200 to word 0x40020404 (DMA2 base 0x40020400, offset 4).
@ Returns when the byte 0x200011c4 (0x2000057c + 0xc48) is 0; otherwise clears
@ it and calls fn_080087ce with (0x40020008, 0x80), (0x40020094, 0x80) and
@ (0x40020458, 0x80), then fn_08008770(..., 1) for the same three blocks (the
@ last as a tail jump).
@ ----------------------------------------------------------------------------
	.section .text.fn_080085d0,"ax",%progbits
	.p2align 2
	.global fn_080085d0
	.thumb_func
	.type fn_080085d0, %function
fn_080085d0:
	push	{r4, r5, r6, lr}
	ldr	r1, .L0800862c		@ 0x40020404
	mov.w	r0, #0x200
	str	r0, [r1, #0]
	ldr	r0, .L08008630		@ 0x2000057c
	ldrb.w	r1, [r0, #0xc48]	@ byte 0x200011c4
	cmp	r1, #0
	beq.n	.L08008628
	movs	r1, #0
	strb.w	r1, [r0, #0xc48]
	ldr	r4, .L08008634		@ 0x40020008
	movs	r1, #0x80
	mov	r0, r4
.ifdef OWN
	bl	own_dma_rearm		@ own build: channel disabled before its count (own/fix.s)
.else
	bl	fn_080087ce
.endif
	ldr	r5, .L08008634		@ 0x40020008
	movs	r1, #0x80
	adds	r5, #0x8c		@ 0x40020094
	mov	r0, r5
.ifdef OWN
	bl	own_dma_rearm
.else
	bl	fn_080087ce
.endif
	ldr	r6, .L0800862c		@ 0x40020404
	movs	r1, #0x80
	adds	r6, #0x54		@ 0x40020458
	mov	r0, r6
.ifdef OWN
	bl	own_dma_rearm
.else
	bl	fn_080087ce
.endif
	movs	r1, #1
	mov	r0, r4
	bl	fn_08008770
	movs	r1, #1
	mov	r0, r5
	bl	fn_08008770
	mov	r0, r6
	pop.w	{r4, r5, r6, lr}
	movs	r1, #1
	b.w	fn_08008770
.L08008628:
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L0800862c:
	.word	0x40020404
.L08008630:
	.word	0x2000057c
.L08008634:
	.word	0x40020008

@ ----------------------------------------------------------------------------
@ store_word_offset_4 - stores a value to word [base+4].
@ r0 = value, r1 = base address; no return value.
@ ----------------------------------------------------------------------------
	.section .text.store_word_offset_4,"ax",%progbits
	.p2align 2
	.global store_word_offset_4
	.thumb_func
	.type store_word_offset_4, %function
store_word_offset_4:
	str	r0, [r1, #4]
	bx	lr

@ ----------------------------------------------------------------------------
@ set_or_clear_bits - sets or clears the bits of a mask in a word.
@ r0 = word pointer, r1 = mask, r2 = flag; no return value.
@ Flag 0: *r0 = *r0 & ~r1; otherwise *r0 = *r0 | r1.
@ ----------------------------------------------------------------------------
	.section .text.set_or_clear_bits,"ax",%progbits
	.p2align 2
	.global set_or_clear_bits
	.thumb_func
	.type set_or_clear_bits, %function
set_or_clear_bits:
	cmp	r2, #0
	ldr	r2, [r0, #0]
	beq.n	.L08008646
	orrs	r2, r1
	b.n	.L08008648
.L08008646:
	bics	r2, r1
.L08008648:
	str	r2, [r0, #0]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0800864c - resets a channel block and sets its 4-bit group in a shared word.
@ r0 = channel block pointer; no return value.
@ Clears bit 0 of word [r0] (and 0xfffe), then stores 0 to the words [r0+0],
@ [r0+4], [r0+8] and [r0+0xc].
@ For the block addresses 0x40020008, 0x4002001c, 0x40020030, 0x40020044,
@ 0x40020058, 0x4002006c, 0x40020080 and 0x40020094 (spacing 0x14) it sets the
@ 4-bit group 0..7 (0xf << 4n) in the word 0x40020004; for 0x40020408,
@ 0x4002041c, 0x40020430, 0x40020444, 0x40020458, 0x4002046c, 0x40020480 and
@ 0x40020494 it sets the group in the word 0x40020404. Any other address
@ returns without that write. (DMA1 base 0x40020000, DMA2 base 0x40020400.)
@ r1 = 0x40020000 (first group) or 0x40020400 (second group), word at +4.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800864c,"ax",%progbits
	.p2align 2
	.global fn_0800864c
	.thumb_func
	.type fn_0800864c, %function
fn_0800864c:
	ldr	r1, [r0, #0]
	movw	r2, #0xfffe
	ands	r1, r2
	str	r1, [r0, #0]		@ clear bit 0
	movs	r1, #0
	str	r1, [r0, #0]
	str	r1, [r0, #4]
	str	r1, [r0, #8]
	str	r1, [r0, #0xc]
	ldr	r1, .L08008768		@ 0x40020008
	ldr	r2, .L08008768
	subs	r1, #8			@ 0x40020000
	cmp	r0, r2
	bne.n	.L08008672
	ldr	r0, [r1, #4]
	orr.w	r0, r0, #0xf
	b.n	.L08008680
.L08008672:
	ldr	r2, .L08008768
	adds	r2, #0x14		@ 0x4002001c
	cmp	r0, r2
	bne.n	.L08008684
	ldr	r0, [r1, #4]
	orr.w	r0, r0, #0xf0
.L08008680:
	str	r0, [r1, #4]
	bx	lr
.L08008684:
	ldr	r2, .L08008768
	adds	r2, #0x28		@ 0x40020030
	cmp	r0, r2
	bne.n	.L08008694
	ldr	r0, [r1, #4]
	orr.w	r0, r0, #0xf00
	b.n	.L08008680
.L08008694:
	ldr	r2, .L08008768
	adds	r2, #0x3c		@ 0x40020044
	cmp	r0, r2
	bne.n	.L080086a4
	ldr	r0, [r1, #4]
	orr.w	r0, r0, #0xf000
	b.n	.L08008680
.L080086a4:
	ldr	r2, .L08008768
	adds	r2, #0x50		@ 0x40020058
	cmp	r0, r2
	bne.n	.L080086b4
	ldr	r0, [r1, #4]
	orr.w	r0, r0, #0xf0000
	b.n	.L08008680
.L080086b4:
	ldr	r2, .L08008768
	adds	r2, #0x64		@ 0x4002006c
	cmp	r0, r2
	bne.n	.L080086c4
	ldr	r0, [r1, #4]
	orr.w	r0, r0, #0xf00000
	b.n	.L08008680
.L080086c4:
	ldr	r2, .L08008768
	adds	r2, #0x78		@ 0x40020080
	cmp	r0, r2
	bne.n	.L080086d4
	ldr	r0, [r1, #4]
	orr.w	r0, r0, #0xf000000
	b.n	.L08008680
.L080086d4:
	ldr	r2, .L08008768
	adds	r2, #0x8c		@ 0x40020094
	cmp	r0, r2
	bne.n	.L080086e4
	ldr	r0, [r1, #4]
	orr.w	r0, r0, #0xf0000000
	b.n	.L08008680
.L080086e4:
	ldr	r2, .L0800876c		@ 0x40020408
	subs	r1, r2, #4		@ 0x40020404
	cmp	r0, r2
	bne.n	.L080086f4
	ldr	r0, [r1, #0]
	orr.w	r0, r0, #0xf
	b.n	.L08008702
.L080086f4:
	ldr	r2, .L0800876c
	adds	r2, #0x14		@ 0x4002041c
	cmp	r0, r2
	bne.n	.L08008706
	ldr	r0, [r1, #0]
	orr.w	r0, r0, #0xf0
.L08008702:
	str	r0, [r1, #0]
.L08008704:
	bx	lr
.L08008706:
	ldr	r2, .L0800876c
	adds	r2, #0x28		@ 0x40020430
	cmp	r0, r2
	bne.n	.L08008716
	ldr	r0, [r1, #0]
	orr.w	r0, r0, #0xf00
	b.n	.L08008702
.L08008716:
	ldr	r2, .L0800876c
	adds	r2, #0x3c		@ 0x40020444
	cmp	r0, r2
	bne.n	.L08008726
	ldr	r0, [r1, #0]
	orr.w	r0, r0, #0xf000
	b.n	.L08008702
.L08008726:
	ldr	r2, .L0800876c
	adds	r2, #0x50		@ 0x40020458
	cmp	r0, r2
	bne.n	.L08008736
	ldr	r0, [r1, #0]
	orr.w	r0, r0, #0xf0000
	b.n	.L08008702
.L08008736:
	ldr	r2, .L0800876c
	adds	r2, #0x64		@ 0x4002046c
	cmp	r0, r2
	bne.n	.L08008746
	ldr	r0, [r1, #0]
	orr.w	r0, r0, #0xf00000
	b.n	.L08008702
.L08008746:
	ldr	r2, .L0800876c
	adds	r2, #0x78		@ 0x40020480
	cmp	r0, r2
	bne.n	.L08008756
	ldr	r0, [r1, #0]
	orr.w	r0, r0, #0xf000000
	b.n	.L08008702
.L08008756:
	ldr	r2, .L0800876c
	adds	r2, #0x8c		@ 0x40020494
	cmp	r0, r2
	bne.n	.L08008704
	ldr	r0, [r1, #0]
	orr.w	r0, r0, #0xf0000000
	b.n	.L08008702
	.short	0x0000			@ padding
.L08008768:
	.word	0x40020008
.L0800876c:
	.word	0x40020408

@ ----------------------------------------------------------------------------
@ fn_08008770 - sets or clears bit 0 of a word.
@ r0 = word pointer, r1 = flag; no return value.
@ Flag 0: *r0 = *r0 & 0xfffe; otherwise *r0 = *r0 | 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008770,"ax",%progbits
	.global fn_08008770
	.thumb_func
	.type fn_08008770, %function
fn_08008770:
	cmp	r1, #0
	ldr	r1, [r0, #0]
	beq.n	.L0800877c
	orr.w	r1, r1, #1
	b.n	.L08008782
.L0800877c:
	movw	r2, #0xfffe
	ands	r1, r2
.L08008782:
	str	r1, [r0, #0]
	bx	lr

@ ----------------------------------------------------------------------------
@ test_bits - tests a mask against a word.
@ r0 = mask, r1 = word pointer; returns 1 when (*r1 & r0) is not 0, else 0.
@ ----------------------------------------------------------------------------
	.section .text.test_bits,"ax",%progbits
	.global test_bits
	.thumb_func
	.type test_bits, %function
test_bits:
	mov	r2, r0
	ldr	r1, [r1, #0]
	movs	r0, #0
	tst	r1, r2
	beq.n	.L08008792
	movs	r0, #1
.L08008792:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08008794 - writes a settings block (11 words) into a channel block.
@ r0 = channel block pointer, r1 = settings block s (11 words); no return
@ value.
@ [r0]   = ([r0] & 0xffff800f) | s[2] | s[4] | s[5] | s[6] | s[7] | s[8] |
@          s[9] | s[10]
@ [r0+4] = s[3]
@ [r0+8] = s[0]
@ [r0+12] = s[1]
@ ----------------------------------------------------------------------------
	.section .text.fn_08008794,"ax",%progbits
	.global fn_08008794
	.thumb_func
	.type fn_08008794, %function
fn_08008794:
	push	{r4, r5, lr}
	ldr	r3, [r0, #0]
	movw	r2, #0x7ff0
	bics	r3, r2			@ keep ~0x7ff0 (0xffff800f)
	ldr	r4, [r1, #0x20]
	ldr	r2, [r1, #8]
	orrs	r2, r4
	ldrd	r4, r5, [r1, #0x10]
	orrs	r4, r5
	orrs	r2, r4
	ldr	r4, [r1, #0x18]
	orrs	r2, r4
	ldr	r4, [r1, #0x1c]
	orrs	r2, r4
	ldr	r4, [r1, #0x24]
	orrs	r2, r4
	ldr	r4, [r1, #0x28]
	orrs	r2, r4
	orrs	r2, r3
	str	r2, [r0, #0]
	ldr	r2, [r1, #0xc]
	str	r2, [r0, #4]
	ldr	r2, [r1, #0]
	str	r2, [r0, #8]
	ldr	r1, [r1, #4]
	str	r1, [r0, #0xc]
	pop	{r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_080087ce - stores a value to word [base+4].
@ r0 = base address, r1 = value; no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080087ce,"ax",%progbits
	.global fn_080087ce
	.thumb_func
	.type fn_080087ce, %function
fn_080087ce:
	str	r1, [r0, #4]
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_080087d4 - sets up the word 0x40007400 and calls fn_08008814.
@ No parameters are read (r0..r3 are only pushed); the pop at the end loads
@ r0..r4 from the local block, so on return r0 = 4 and r1 = 0 and the function
@ has no defined return value.
@ Builds the local block (word 4 at +0, word 0 at +4, word 2 at +0xc; the word
@ at +8 keeps the pushed r2) and calls fn_080085a8(0, block),
@ fn_08008590(0, 1), fn_08008578(0, 1), then fn_08008814 with the float at
@ 0x20001138 (base 0x20000d7c from the literal, offset 0x3bc) in s0 and the
@ word at 0x20001144 (offset 0xbc8 from 0x20000d7c - 0x800) in r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080087d4,"ax",%progbits
	.p2align 2
	.global fn_080087d4
	.thumb_func
	.type fn_080087d4, %function
fn_080087d4:
	push	{r0, r1, r2, r3, r4, lr}
	movs	r0, #4
	str	r0, [sp, #0]
	movs	r0, #0
	str	r0, [sp, #4]
	movs	r0, #2
	str	r0, [sp, #0xc]
	mov	r1, sp
	movs	r0, #0
	bl	fn_080085a8
	movs	r1, #1
	movs	r0, #0
	bl	fn_08008590
	movs	r1, #1
	movs	r0, #0
	bl	fn_08008578
	ldr	r0, .L08008810		@ 0x20000d7c
	vldr	s0, [r0, #0x3bc]	@ float at 0x20001138
	sub.w	r0, r0, #0x800
	ldr.w	r0, [r0, #0xbc8]	@ word at 0x20001144
	bl	fn_08008814
	pop	{r0, r1, r2, r3, r4, pc}
	.short	0x0000			@ padding
.L08008810:
	.word	0x20000d7c

@ ----------------------------------------------------------------------------
@ fn_08008c78 - configures a GPIOA pin and USART1 (115200 setting).
@ No parameters, no return value.
@ Builds a pin block on the stack (halfword 0x200 at +0x10, byte 3 at +0x12,
@ byte 0x18 at +0x13) and calls fn_08009228(0x40010800 (GPIOA), block).
@ Builds a settings block with the word 0x1c200 (115200) at +0, halfword 0 at
@ +4, +6, +8 and +0xc, and halfword 8 at +0xa; calls fn_0800fa88(0x40013800
@ (USART1), block), then set_or_clear_halfword_bit_13(0x40013800, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_08008c78,"ax",%progbits
	.p2align 2
	.global fn_08008c78
	.thumb_func
	.type fn_08008c78, %function
fn_08008c78:
	push	{r4, lr}
	sub	sp, #0x18
	mov.w	r0, #0x200
	strh.w	r0, [sp, #0x10]
	movs	r0, #3
	strb.w	r0, [sp, #0x12]
	movs	r0, #0x18
	strb.w	r0, [sp, #0x13]
	add	r1, sp, #0x10
	ldr	r0, .L08008ccc		@ 0x40010800 (GPIOA)
	bl	fn_08009228
	mov.w	r0, #0x1c200		@ 115200
	str	r0, [sp, #0]
	movs	r0, #0
	strh.w	r0, [sp, #4]
	strh.w	r0, [sp, #6]
	strh.w	r0, [sp, #8]
	strh.w	r0, [sp, #0xc]
	movs	r0, #8
	ldr	r4, .L08008cd0		@ 0x40013800 (USART1)
	strh.w	r0, [sp, #0xa]
	mov	r1, sp
	mov	r0, r4
	bl	fn_0800fa88
	movs	r1, #1
	mov	r0, r4
	bl	set_or_clear_halfword_bit_13
	add	sp, #0x18
	pop	{r4, pc}
.L08008ccc:
	.word	0x40010800
.L08008cd0:
	.word	0x40013800

@ ----------------------------------------------------------------------------
@ fn_08008cd4 - starts the timer at 0x40001400 (TIM7) with a prescaler setting.
@ No parameters are read (r0..r3 are only pushed); the pop at the end loads
@ r0..r4 from the local block, so on return r0 = 0x47 and r1 = 0x0000ffff and
@ the function has no defined return value.
@ Calls fn_0800c33c(0x40001400), stores the halfword 0x47 at [sp+0], halfword 0
@ at [sp+2], halfword 0xffff at [sp+4], halfword 0 at [sp+6], calls
@ fn_0800c590(0x40001400, block) and set_or_clear_bit_0_0800c404(0x40001400, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_08008cd4,"ax",%progbits
	.p2align 2
	.global fn_08008cd4
	.thumb_func
	.type fn_08008cd4, %function
fn_08008cd4:
	push	{r0, r1, r2, r3, r4, lr}
	ldr	r4, .L08008d08		@ 0x40001400
	mov	r0, r4
	bl	fn_0800c33c
	movw	r0, #0xffff
	strh.w	r0, [sp, #4]
	movs	r0, #0x47
	strh.w	r0, [sp, #0]
	movs	r1, #0
	strh.w	r1, [sp, #6]
	strh.w	r1, [sp, #2]
	mov	r1, sp
	mov	r0, r4
	bl	fn_0800c590
	movs	r1, #1
	mov	r0, r4
	bl	set_or_clear_bit_0_0800c404
	pop	{r0, r1, r2, r3, r4, pc}
.L08008d08:
	.word	0x40001400

@ ----------------------------------------------------------------------------
@ write_word_40010414 - stores a value to the word 0x40010414.
@ r0 = value; no return value.
@ Loads r1 = 0x40010414 from the literal, stores r0 at [r1] and returns.
@ ----------------------------------------------------------------------------
	.section .text.write_word_40010414,"ax",%progbits
	.p2align 2
	.global write_word_40010414
	.thumb_func
	.type write_word_40010414, %function
write_word_40010414:
	ldr	r1, .L08008d1c		@ 0x40010414
	str	r0, [r1, #0]
	bx	lr
	.short	0x0000			@ padding
.L08008d1c:
	.word	0x40010414

@ ----------------------------------------------------------------------------
@ fn_08008d20 - sets bits in FLASH_STS (0x4002200c).
@ r0 = mask; no return value.
@ Word 0x4002200c = word 0x4002200c | r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008d20,"ax",%progbits
	.p2align 2
	.global fn_08008d20
	.thumb_func
	.type fn_08008d20, %function
fn_08008d20:
	ldr	r1, .L08008d2c		@ 0x40022000 (flash registers)
	ldr	r2, [r1, #0xc]		@ FLASH_STS
	orrs	r2, r0
	str	r2, [r1, #0xc]
	bx	lr
	.short	0x0000			@ padding
.L08008d2c:
	.word	0x40022000

@ ----------------------------------------------------------------------------
@ fn_08008d30 - writes a word to the address in FLASH_ADD (0x40022014) with
@ FLASH_CTRL (0x40022010) bits.
@ r0 = value; no return value.
@ Calls fn_08008d20(0x7c); when fn_08008e1c(0xb0000) returns 6: sets bit 1 of
@ word 0x40022010, stores r0 to word 0x40022014, sets bit 6 of word
@ 0x40022010, calls fn_08008e1c(0xb0000), then word 0x40022010 &= 0x3ffd.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008d30,"ax",%progbits
	.p2align 2
	.global fn_08008d30
	.thumb_func
	.type fn_08008d30, %function
fn_08008d30:
.ifdef OWN
	movs	r0, #8			@ own build: the vendor page erase is switched off (returns at
	bx	lr			@ once; all flash writes go through own/save.s)
.else
	push	{r4, r5, r6, lr}
	mov	r5, r0
.endif
	movs	r0, #0x7c
	bl	fn_08008d20
	mov.w	r6, #0xb0000
	mov	r0, r6
	bl	fn_08008e1c
	cmp	r0, #6
	bne.n	.L08008d6c
	ldr	r4, .L08008d70		@ 0x40022000 (flash registers)
	ldr	r0, [r4, #0x10]
	orr.w	r0, r0, #2
	str	r0, [r4, #0x10]		@ FLASH_CTRL |= 2
	str	r5, [r4, #0x14]		@ FLASH_ADD = value
	ldr	r0, [r4, #0x10]
	orr.w	r0, r0, #0x40
	str	r0, [r4, #0x10]		@ FLASH_CTRL |= 0x40
	mov	r0, r6
	bl	fn_08008e1c
	ldr	r1, [r4, #0x10]
	movw	r2, #0x3ffd
	ands	r1, r2
	str	r1, [r4, #0x10]
.L08008d6c:
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L08008d70:
	.word	0x40022000

@ ----------------------------------------------------------------------------
@ fn_08008d74 - returns a status code from FLASH_STS (0x4002200c).
@ No parameters. Returns: bit 0 set: 1; else bit 2: 3; bit 3: 4; bit 4: 5;
@ bit 6: 7; none of these: 6.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008d74,"ax",%progbits
	.p2align 2
	.global fn_08008d74
	.thumb_func
	.type fn_08008d74, %function
fn_08008d74:
	ldr	r1, .L08008dac		@ 0x40022000 (flash registers)
	movs	r0, #6
	ldr	r2, [r1, #0xc]
	lsls	r2, r2, #0x1f		@ bit 0
	beq.n	.L08008d82
	movs	r0, #1
	bx	lr
.L08008d82:
	ldr	r2, [r1, #0xc]
	lsls	r2, r2, #0x1d		@ bit 2
	bpl.n	.L08008d8c
	movs	r0, #3
	bx	lr
.L08008d8c:
	ldr	r2, [r1, #0xc]
	lsls	r2, r2, #0x1c		@ bit 3
	bpl.n	.L08008d96
	movs	r0, #4
	bx	lr
.L08008d96:
	ldr	r2, [r1, #0xc]
	lsls	r2, r2, #0x1b		@ bit 4
	bpl.n	.L08008da0
	movs	r0, #5
.L08008d9e:
	bx	lr
.L08008da0:
	ldr	r1, [r1, #0xc]
	lsls	r1, r1, #0x19		@ bit 6
	bpl.n	.L08008d9e
	movs	r0, #7
	bx	lr
	.short	0x0000			@ padding
.L08008dac:
	.word	0x40022000

@ ----------------------------------------------------------------------------
@ fn_08008db0 - sets bit 7 of FLASH_CTRL (0x40022010).
@ No parameters, no return value; entered only by the tail call b.w at
@ 0x08014bc4 (inside 0x08014b94), so its bx lr returns to the caller of
@ 0x08014b94.
@ r0 = 0x40022000; r1 = word [r0+0x10]; r1 |= 0x80; word [r0+0x10] = r1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008db0,"ax",%progbits
	.p2align 2
	.global fn_08008db0
	.thumb_func
	.type fn_08008db0, %function
fn_08008db0:
	ldr	r0, .L08008dbc		@ 0x40022000 (flash registers)
	ldr	r1, [r0, #0x10]
	orr.w	r1, r1, #0x80
	str	r1, [r0, #0x10]
	bx	lr
.L08008dbc:
	.word	0x40022000

@ ----------------------------------------------------------------------------
@ fn_08008dc0 - writes a word to a word-aligned address through FLASH_CTRL.
@ r0 = address, r1 = value; returns a status code.
@ When r0 is not word aligned returns 9. Otherwise calls fn_08008d20(0x7c);
@ when fn_08008e1c(0x2000) returns 6: sets bit 0 of word 0x40022010, stores r1
@ to the address, calls fn_08008e1c(0x2000), clears bits (word 0x40022010 &=
@ 0x3ffe) and returns that status; else returns the status.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008dc0,"ax",%progbits
	.p2align 2
	.global fn_08008dc0
	.thumb_func
	.type fn_08008dc0, %function
fn_08008dc0:
.ifdef OWN
	movs	r0, #8			@ own build: the vendor word program is switched off (returns
	bx	lr			@ 8, as for a refused address; flash writes go through save.s)
.else
	push	{r4, r5, r6, r7, lr}
	mov	r5, r0
.endif
	mov	r6, r1
	lsls	r0, r0, #0x1e		@ low two address bits
	beq.n	.L08008dce
	movs	r0, #9
.L08008dcc:
	pop	{r4, r5, r6, r7, pc}
.L08008dce:
	movs	r0, #0x7c
	bl	fn_08008d20
	mov.w	r7, #0x2000
	mov	r0, r7
	bl	fn_08008e1c
	cmp	r0, #6
	bne.n	.L08008dcc
	ldr	r4, .L08008e00		@ 0x40022000 (flash registers)
	ldr	r0, [r4, #0x10]
	orr.w	r0, r0, #1
	str	r0, [r4, #0x10]		@ FLASH_CTRL |= 1
	str	r6, [r5, #0]		@ store the value
	mov	r0, r7
	bl	fn_08008e1c
	ldr	r1, [r4, #0x10]
	movw	r2, #0x3ffe
	ands	r1, r2
	str	r1, [r4, #0x10]
	pop	{r4, r5, r6, r7, pc}
.L08008e00:
	.word	0x40022000

@ ----------------------------------------------------------------------------
@ fn_08008e04 - writes the two flash unlock keys.
@ No parameters, no return value.
@ Writes 0x45670123 and then 0xcdef89ab to FLASH_KEY (word 0x40022004).
@ ----------------------------------------------------------------------------
	.section .text.fn_08008e04,"ax",%progbits
	.p2align 2
	.global fn_08008e04
	.thumb_func
	.type fn_08008e04, %function
fn_08008e04:
.ifdef OWN
	bx	lr			@ own build: the vendor flash unlock is switched off (the
					@ controller stays locked for every vendor routine)
.else
	ldr	r0, .L08008e14		@ 0x40022000 (flash registers)
.endif
	ldr	r1, .L08008e10		@ 0x45670123
	str	r1, [r0, #4]
	ldr	r1, .L08008e18		@ 0xcdef89ab
	str	r1, [r0, #4]
	bx	lr
.L08008e10:
	.word	0x45670123
.L08008e14:
	.word	0x40022000
.L08008e18:
	.word	0xcdef89ab

@ ----------------------------------------------------------------------------
@ fn_08008e1c - polls fn_08008d74 up to a retry count.
@ r0 = retry count (kept in r3); returns a status code.
@ Calls fn_08008d74; while it returns 1 decrements the count and calls it
@ again. Returns 10 when the count is 0 at the moment the status is tested
@ after a call (whether or not the status is 1); else returns the status.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008e1c,"ax",%progbits
	.p2align 2
	.global fn_08008e1c
	.thumb_func
	.type fn_08008e1c, %function
fn_08008e1c:
	push	{lr}
	mov	r3, r0
	bl	fn_08008d74
	b.n	.L08008e2e
	nop				@ padding
.L08008e28:
	bl	fn_08008d74
	.inst.n	0x1e5b		@ subs r3, r3, #1
.L08008e2e:
	cmp	r0, #1
	beq.n	.L08008e3a
	cmp	r3, #0
	bne.n	.L08008e38
.L08008e36:
	movs	r0, #0xa
.L08008e38:
	pop	{pc}
.L08008e3a:
	cmp	r3, #0
	bne.n	.L08008e28
	b.n	.L08008e36
