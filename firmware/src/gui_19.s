@ gui_19.s - GUI module part 19: plane position, scaling and record set-up helpers
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0801d478 - computes the x/y position of one sample on an object's plane.
@ Parameters: r0 = object pointer, r1 = pointer to a 4-word record (word +0 =
@ pointer to a halfword x-value list, word +4 = pointer to a halfword y-value
@ list, byte +0xc holds selector bits), r2 = index, r3 = pointer to two output
@ halfwords (x, y). No return value.
@ When the index is not below halfword [object+0x82] both outputs are set to 0.
@ Otherwise: x scale = fn_08023e7c(object) * halfword [object+0x84] sign
@ extended from bits 8..23 (result >> 8, low 16 bits); y scale =
@ fn_08023e48(object) * halfword [object+0x86], same extraction.
@ Mode = byte [object+0x88] & 7:
@   1: x = index * x scale / (halfword [object+0x82] - 1)
@   3: x = fn_08022b12(halfword at [word [r1] + index*2], halfword
@      [object + bit3(byte [r1+0xc])*2 + 0x74], halfword
@      [object + bit3*2 + 0x78], 0, x scale)
@   2: steps over the list at object+0x24 using fn_080125d6 (count),
@      get_word_8_or_zero and read_word_at_base_plus_offset until the entry
@      equals the record pointer, adding a per-entry width each step, with
@      two fn_08024ad4 calls (arguments 0x50000 and 0) taking part
@   other: x is left as it is
@ Then adds fn_0802499c(object,0) and fn_08024af8(object,0) to x and
@ subtracts fn_08024070(object).
@ y = (y scale >> 16) - ((value - min) * (y scale >> 16) / (max - min)) where
@ value = halfword [word [r1+4] + index*2], min / max = halfwords
@ [object + bit4(byte [r1+0xc])*2 + 0x6c] / [... + 0x70]; then adds
@ fn_08024b88(object,0) and fn_0802499c(object,0) and subtracts
@ fn_08024208(object).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801d478,"ax",%progbits
	.p2align 2
	.global fn_0801d478
	.thumb_func
	.type fn_0801d478, %function
fn_0801d478:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r5, r0
	ldrh.w	r0, [r0, #0x82]
	mov	r7, r2
	sub	sp, #0x24
	mov	r8, r1
	mov	r4, r3
	cmp	r0, r7
	bhi.n	.L0801d49a
	movs	r0, #0x0
	strh	r0, [r4, #0x0]
	strh	r0, [r3, #0x2]
.L0801d494:
	add	sp, #0x24
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801d49a:
	mov	r0, r5
	bl	fn_08023e7c
	ldrh.w	r1, [r5, #0x84]
	muls	r0, r1, r0
	sbfx	r6, r0, #8, #16
	mov	r0, r5
	bl	fn_08023e48
	ldrh.w	r1, [r5, #0x86]
	muls	r0, r1, r0
	sbfx	r9, r0, #8, #16
	ldrb.w	r0, [r5, #0x88]
	and.w	r0, r0, #7
	cmp	r0, #1
	beq.n	.L0801d4d0
	cmp	r0, #3
	beq.n	.L0801d4de
	cmp	r0, #2
	beq.n	.L0801d504
	b.n	.L0801d586
.L0801d4d0:
	ldrh.w	r0, [r5, #0x82]
	muls	r6, r7, r6
	.inst.n	0x1e40	@ subs r0, r0, #1
	sdiv	r0, r6, r0
	b.n	.L0801d584
.L0801d4de:
	str	r6, [sp, #0x0]
	ldrb.w	r1, [r8, #0xc]
	ldr.w	r0, [r8, #0x0]
	ubfx	r2, r1, #3, #1
	add.w	r1, r5, r2, lsl #1
	ldrsh.w	r0, [r0, r7, lsl #1]
	ldrsh.w	r2, [r1, #0x78]
	ldrsh.w	r1, [r1, #0x74]
	movs	r3, #0x0
	bl	fn_08022b12
	b.n	.L0801d584
.L0801d504:
	add.w	r0, r5, #0x24
	str	r0, [sp, #0x0]
	str	r0, [sp, #0x10]
	bl	fn_080125d6
	mov	r10, r0
	mov.w	r1, #0x50000
	mov	r0, r5
	bl	fn_08024ad4
	ldrh.w	r1, [r5, #0x84]
	muls	r0, r1, r0
	asr.w	r11, r0, #8
	movs	r1, #0x0
	mov	r0, r5
	bl	fn_08024ad4
	ldrh.w	r1, [r5, #0x84]
	muls	r0, r1, r0
	asrs	r1, r0, #8
	ldrh.w	r0, [r5, #0x82]
	rsb.w	r2, r0, #1
	mla	r1, r2, r1, r6
	sdiv	r1, r1, r0
	muls	r6, r7, r6
	sxth	r2, r1
	sdiv	r0, r6, r0
	udiv	r1, r2, r10
	strh	r0, [r4, #0x0]
	sxth.w	r10, r1
	ldr	r0, [sp, #0x10]
	bl	get_word_8_or_zero
	b.n	.L0801d572
.L0801d560:
	cmp	r1, r8
	beq.n	.L0801d576
	ldrh	r2, [r4, #0x0]
	add.w	r0, r2, r10
	strh	r0, [r4, #0x0]
	ldr	r0, [sp, #0x0]
	bl	read_word_at_base_plus_offset
.L0801d572:
	movs	r1, r0
	bne.n	.L0801d560
.L0801d576:
	sub.w	r0, r10, r11
	ldrh	r1, [r4, #0x0]
	add.w	r0, r0, r0, lsr #31
	add.w	r0, r1, r0, asr #1
.L0801d584:
	strh	r0, [r4, #0x0]
.L0801d586:
	movs	r1, #0x0
	mov	r0, r5
	bl	fn_0802499c
	mov	r6, r0
	movs	r1, #0x0
	mov	r0, r5
	bl	fn_08024af8
	ldrh	r1, [r4, #0x0]
	add	r0, r6
	add	r0, r1
	strh	r0, [r4, #0x0]
	mov	r0, r5
	bl	fn_08024070
	ldrh	r1, [r4, #0x0]
	subs	r0, r1, r0
	strh	r0, [r4, #0x0]
	ldr.w	r0, [r8, #0x4]
	ldrsh.w	r3, [r0, r7, lsl #1]
	ldrb.w	r0, [r8, #0xc]
	ubfx	r1, r0, #4, #1
	add.w	r1, r5, r1, lsl #1
	ldrsh	r2, [r1, #0x6c]!
	ldrsh.w	r1, [r1, #0x4]
	subs	r0, r3, r2
	mul	r0, r0, r9
	subs	r1, r1, r2
	sdiv	r0, r0, r1
	sub.w	r0, r9, r0
	strh	r0, [r4, #0x2]
	movs	r1, #0x0
	mov	r0, r5
	bl	fn_08024b88
	ldrh	r1, [r4, #0x2]
	add	r0, r6
	add	r0, r1
	strh	r0, [r4, #0x2]
	mov	r0, r5
	bl	fn_08024208
	ldrh	r1, [r4, #0x2]
	subs	r0, r1, r0
	strh	r0, [r4, #0x2]
	b.n	.L0801d494

@ ----------------------------------------------------------------------------
@ fn_0801dac6 - scales a halfword value by a factor from fn_0801dcd8.
@ Parameters: r0 = object, r1 = value (halfword). Returns a halfword (sign
@ extended) in r0.
@ Returns 0 when r1 is 0. Otherwise n = fn_0801dcd8(r0) * r1 + 0x50; returns 1
@ when n < 0x140, else n / 0xa0 (signed division, calling fn_0801dcd8 again).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dac6,"ax",%progbits
	.global fn_0801dac6
	.thumb_func
	.type fn_0801dac6, %function
fn_0801dac6:
	push	{r4, r5, r6, lr}
	movs	r4, r1
	mov	r5, r0
	beq.n	.L0801daf2
	bl	fn_0801dcd8
	smulbb	r0, r0, r4
	adds	r0, #0x50
	cmp.w	r0, #0x140
	blt.n	.L0801daf6
	mov	r0, r5
	bl	fn_0801dcd8
	smulbb	r0, r0, r4
	movs	r1, #0xa0
	adds	r0, #0x50
	sdiv	r0, r0, r1
	b.n	.L0801daf8
.L0801daf2:
	movs	r0, #0x0
	b.n	.L0801daf8
.L0801daf6:
	movs	r0, #0x1
.L0801daf8:
	sxth	r0, r0
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_0801dafc - initialises a 0x1c-byte structure.
@ Parameters: r0 = structure pointer, r1, r2, r3 = values. No return value.
@ Clears 0x1c bytes with clear_bytes, then writes word +0 = r1, word +4 = r2,
@ word +8 = r1, word +0xc = r3. Followed by 2 bytes of padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dafc,"ax",%progbits
	.p2align 2
	.global fn_0801dafc
	.thumb_func
	.type fn_0801dafc, %function
fn_0801dafc:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r5, r1
	mov	r6, r3
	mov	r7, r2
	mov	r4, r0
	movs	r1, #0x1c
	bl	clear_bytes
	strd	r5, r7, [r4, #0x0]
	strd	r5, r6, [r4, #0x8]
	pop.w	{r4, r5, r6, r7, r8, pc}
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_0801db1c - initialises a 0x50-byte structure with default values.
@ Parameter: r0 = structure pointer. No return value.
@ Clears 0x50 bytes with clear_bytes, then writes halfwords +0 = 0x140,
@ +2 = 0xf0, +4 = 0xffff, +6 = 0xffff, +8 = 0, +0xa = 0, +0x38 = 0 (the zero
@ goes through a stack slot). Word +0x10: bit 6 cleared, bit 3 set and the ten
@ bits from bit 7 set to 0x8f (bic, orr, bfi), other bits kept. Words
@ +0x40 = +0x44 = 0x0801fcbd (a function pointer to fn_0801fcbc, Thumb bit
@ set), +0x48 = 0x54.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801db1c,"ax",%progbits
	.p2align 2
	.global fn_0801db1c
	.thumb_func
	.type fn_0801db1c, %function
fn_0801db1c:
	push	{r3, r4, r5, lr}
	mov	r4, r0
	movs	r1, #0x50
	bl	clear_bytes
	mov.w	r0, #0x140
	strh	r0, [r4, #0x0]
	movs	r0, #0xf0
	strh	r0, [r4, #0x2]
	mov.w	r0, #0xffffffff
	strh	r0, [r4, #0x4]
	strh	r0, [r4, #0x6]
	movs	r0, #0x0
	strh	r0, [r4, #0x8]
	strh	r0, [r4, #0xa]
	ldr	r1, [r4, #0x10]
	movs	r2, #0x8f
	bic	r1, r1, #0x40
	orr	r1, r1, #0x8
	bfi	r1, r2, #7, #10
	str	r1, [r4, #0x10]
	strh.w	r0, [sp, #0x0]
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0x38]
	ldr	r0, .L0801db68
	str	r0, [r4, #0x40]
	str	r0, [r4, #0x44]
	movs	r0, #0x54
	str	r0, [r4, #0x48]
	pop	{r3, r4, r5, pc}
.L0801db68:
	.word	fn_0801fcbc		@ function pointer (0x0801fcbd)

@ ----------------------------------------------------------------------------
@ fn_0801db6c - creates and initialises a 0x15c-byte record for a structure.
@ Parameter: r0 = structure (kept in r5). Returns r4 = the new record, or 0.
@ r4 = fn_08012618(0x2000805c); 0 returns 0. When word [r5+0x3c] is 0:
@ r6 = fn_08022b50(word [r5+0x48]) (0 returns 0), then calls the function
@ whose address is word [r5+0x40] with (r5, r6) and stores r6 in word
@ [r5+0x3c].
@ clear_bytes(r4, 0x15c); word [r4] = r5; word [r4+0x154] = 1; r7 = word
@ 0x20000478; word 0x20000478 = r4; word [r4+4] = fn_080277c8(0x08012189,
@ 0x1e, r4) (0x08012189 is a function pointer to fn_08012188). When that is 0
@ the record is released with fn_08022c68(r4) and 0 is returned (word
@ 0x20000478 stays r4).
@ When bit 1 of word [r5+0x10] is set and halfword [r5] * halfword [r5+2]
@ is above word [word [r5+0xc]+0xc] (unsigned), that bit is cleared.
@ Halfword [r4+0x2a] = 0xffff (built from bitfields 0x1f, 0x3f, 0x1f at bits
@ 0, 5, 11 through a stack slot); byte [r4+0x29] = 0xff.
@ fn_0802776c(): when it returns 0, a = fn_08026858(0), b = fn_08026858(5),
@ r0 = fn_080276c8(r4, b, a, 1, [sp] = d_0802ce5c); otherwise r0 =
@ fn_080276b4(). Word [r4+8] = r0.
@ Words [r4+0x10], [r4+0x1c], [r4+0x20] = results of three fn_08023678(0)
@ calls; fn_08025ede(word [r4+0x1c], 0, 0xfffff) and the same for
@ [r4+0x20]; fn_08023558(each, 2); fn_08026380(each, 0);
@ fn_08025400(word [r4+0x10]).
@ Word 0x20000478 = r7; when r7 is 0 the word is set to r4 instead.
@ fn_0802796e(word [r4+4]); returns r4.
@ The b.n at 0x0801dc6e (to 0x0801dc72) has no entry from any instruction.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801db6c,"ax",%progbits
	.p2align 2
	.global fn_0801db6c
	.thumb_func
	.type fn_0801db6c, %function
fn_0801db6c:
	push	{r3, r4, r5, r6, r7, lr}
	mov	r5, r0
	ldr	r0, .L0801dcac
	bl	fn_08012618
	movs	r4, r0
	beq.n	.L0801dc72
	ldr	r0, [r5, #0x3c]
	cbnz	r0, .L0801db92
	ldr	r0, [r5, #0x48]
	bl	fn_08022b50
	movs	r6, r0
	beq.n	.L0801dc72
	mov	r1, r0
	ldr	r2, [r5, #0x40]
	mov	r0, r5
	blx	r2
	str	r6, [r5, #0x3c]
.L0801db92:
	mov.w	r1, #0x15c
	mov	r0, r4
	bl	clear_bytes
	movs	r0, #0x1
	ldr	r6, .L0801dcb0
	str	r5, [r4, #0x0]
	str.w	r0, [r4, #0x154]
	ldr	r7, [r6, #0xc]
	mov	r2, r4
	movs	r1, #0x1e
	ldr	r0, .L0801dcb4
	str	r4, [r6, #0xc]
	bl	fn_080277c8
	str	r0, [r4, #0x4]
	cmp	r0, #0x0
	beq.n	.L0801dc76
	ldr	r0, [r5, #0x10]
	lsls	r1, r0, #0x1e
	bpl.n	.L0801dbd6
	ldrh	r1, [r5, #0x0]
	ldrh	r2, [r5, #0x2]
	smulbb	r1, r1, r2
	ldr	r2, [r5, #0xc]
	ldr	r2, [r2, #0xc]
	cmp	r1, r2
	bls.n	.L0801dbd6
	bic	r0, r0, #0x2
	str	r0, [r5, #0x10]
.L0801dbd6:
	ldrh.w	r1, [sp, #0x0]
	movs	r0, #0x1f
	bfi	r1, r0, #0, #5
	movs	r2, #0x3f
	uxth	r1, r1
	bfi	r1, r2, #5, #6
	uxth	r1, r1
	bfi	r1, r0, #11, #5
	strh.w	r1, [sp, #0x0]
	uxth	r0, r1
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0x2a]
	movs	r0, #0xff
	strb.w	r0, [r4, #0x29]
	bl	fn_0802776c
	cbz	r0, .L0801dc70
	bl	fn_080276b4
.L0801dc12:
	str	r0, [r4, #0x8]
	movs	r0, #0x0
	bl	fn_08023678
	str	r0, [r4, #0x10]
	movs	r0, #0x0
	bl	fn_08023678
	str	r0, [r4, #0x1c]
	movs	r0, #0x0
	bl	fn_08023678
	ldr	r5, .L0801dcb8
	str	r0, [r4, #0x20]
	mov	r2, r5
	movs	r1, #0x0
	ldr	r0, [r4, #0x1c]
	bl	fn_08025ede
	mov	r2, r5
	movs	r1, #0x0
	ldr	r0, [r4, #0x20]
	bl	fn_08025ede
	movs	r1, #0x2
	ldr	r0, [r4, #0x1c]
	bl	fn_08023558
	movs	r1, #0x2
	ldr	r0, [r4, #0x20]
	bl	fn_08023558
	movs	r1, #0x0
	ldr	r0, [r4, #0x1c]
	bl	fn_08026380
	movs	r1, #0x0
	ldr	r0, [r4, #0x20]
	bl	fn_08026380
	ldr	r0, [r4, #0x10]
	bl	fn_08025400
	str	r7, [r6, #0xc]
	cbz	r7, .L0801dc9e
	b.n	.L0801dca0
	b.n	.L0801dc72
.L0801dc70:
	b.n	.L0801dc7e
.L0801dc72:
	movs	r0, #0x0
	pop	{r3, r4, r5, r6, r7, pc}
.L0801dc76:
	mov	r0, r4
	bl	fn_08022c68
	b.n	.L0801dc72
.L0801dc7e:
	movs	r0, #0x0
	bl	fn_08026858
	mov	r5, r0
	movs	r0, #0x5
	bl	fn_08026858
	mov	r1, r0
	ldr	r0, .L0801dcbc
	str	r0, [sp, #0x0]
	movs	r3, #0x1
	mov	r2, r5
	mov	r0, r4
	bl	fn_080276c8
	b.n	.L0801dc12
.L0801dc9e:
	str	r4, [r6, #0xc]
.L0801dca0:
	ldr	r0, [r4, #0x4]
	bl	fn_0802796e
	mov	r0, r4
	pop	{r3, r4, r5, r6, r7, pc}
	.short	0x0000	@ padding
.L0801dcac:
	.word	0x2000805c
.L0801dcb0:
	.word	0x2000046c
.L0801dcb4:
	.word	fn_08012188		@ function pointer (0x08012189)
.L0801dcb8:
	.word	0x000fffff
.L0801dcbc:
	.word	d_0802ce5c

@ ----------------------------------------------------------------------------
@ fn_0801dcc0 - clears two words of the object that word [P+12] points to.
@ Parameter: r0 = pointer P. No return value.
@ Loads Q = word [P+12] and stores 0 in word [Q+16], reloads Q = word [P+12]
@ and stores 0 in word [Q+20].
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dcc0,"ax",%progbits
	.p2align 2
	.global fn_0801dcc0
	.thumb_func
	.type fn_0801dcc0, %function
fn_0801dcc0:
	ldr	r2, [r0, #0xc]
	movs	r1, #0x0
	str	r1, [r2, #0x10]
	ldr	r0, [r0, #0xc]
	str	r1, [r0, #0x14]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801dccc - returns the current node pointer.
@ No parameters. Returns the word at 0x2000046c + 0xc (0x20000478) in r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dccc,"ax",%progbits
	.p2align 2
	.global fn_0801dccc
	.thumb_func
	.type fn_0801dccc, %function
fn_0801dccc:
	ldr	r0, .L0801dcd4
	ldr	r0, [r0, #0xc]
	bx	lr
	.short	0x0000	@ padding
.L0801dcd4:
	.word	0x2000046c

@ ----------------------------------------------------------------------------
@ fn_0801dcd8 - extracts a ten-bit field from the structure of a node.
@ Parameter: r0 = pointer to a node or 0. Returns an unsigned integer in r0.
@ When r0 is 0 the word at 0x20000478 is used; when that is also 0 the result
@ is 0x8f. Otherwise returns bits 7..16 of word [[node]+0x10]
@ ((word & 0x1ffff) >> 7).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dcd8,"ax",%progbits
	.p2align 2
	.global fn_0801dcd8
	.thumb_func
	.type fn_0801dcd8, %function
fn_0801dcd8:
	cbnz	r0, .L0801dce0
	ldr	r0, .L0801dcf0
	ldr	r0, [r0, #0xc]
	cbz	r0, .L0801dcea
.L0801dce0:
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0x10]
	ubfx	r0, r0, #7, #10
	bx	lr
.L0801dcea:
	movs	r0, #0x8f
	bx	lr
	.short	0x0000	@ padding
.L0801dcf0:
	.word	0x2000046c

@ ----------------------------------------------------------------------------
@ fn_0801dcf4 - returns the word at offset 0xc of the structure of a node.
@ Parameter: r0 = pointer to a node. Returns the word at [[node]+0xc] in r0.
@ Followed by 2 bytes of padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dcf4,"ax",%progbits
	.p2align 2
	.global fn_0801dcf4
	.thumb_func
	.type fn_0801dcf4, %function
fn_0801dcf4:
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0xc]
	bx	lr
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_0801dcfc - returns the width or the height of a node's structure.
@ Parameter: r0 = pointer to a node or 0 (0 uses the word at 0x20000478 and
@ returns 0 when that is also 0). Returns an integer in r0.
@ d = the structure at [node]; mode = bits 4..5 of byte [d+0x10]. Returns
@ halfword [d+2] (signed) when mode is 1 or 3, else halfword [d+0] (signed).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dcfc,"ax",%progbits
	.p2align 2
	.global fn_0801dcfc
	.thumb_func
	.type fn_0801dcfc, %function
fn_0801dcfc:
	cbnz	r0, .L0801dd06
	ldr	r0, .L0801dd24
	ldr	r0, [r0, #0xc]
	cmp	r0, #0x0
	beq.n	.L0801dd1a
.L0801dd06:
	ldr	r0, [r0, #0x0]
	ldrb	r1, [r0, #0x10]
	ubfx	r1, r1, #4, #2
	cmp	r1, #1
	beq.n	.L0801dd1c
	cmp	r1, #3
	beq.n	.L0801dd1c
	ldrsh.w	r0, [r0, #0x0]
.L0801dd1a:
	bx	lr
.L0801dd1c:
	ldrsh.w	r0, [r0, #0x2]
	bx	lr
	.short	0x0000	@ padding
.L0801dd24:
	.word	0x2000046c

@ ----------------------------------------------------------------------------
@ fn_0801dd28 - returns the word at offset 0x20 of a node.
@ Parameter: r0 = node pointer or 0 (0 uses fn_0801dccc(), returns 0 when
@ that is 0). Returns the word at node+0x20 in r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dd28,"ax",%progbits
	.p2align 2
	.global fn_0801dd28
	.thumb_func
	.type fn_0801dd28, %function
fn_0801dd28:
	push	{r4, lr}
	cbnz	r0, .L0801dd34
	bl	fn_0801dccc
	cmp	r0, #0x0
	beq.n	.L0801dd36
.L0801dd34:
	ldr	r0, [r0, #0x20]
.L0801dd36:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0801dd38 - returns the word at offset 0x1c of a node.
@ Parameter: r0 = node pointer or 0 (0 uses fn_0801dccc(), returns 0 when
@ that is 0). Returns the word at node+0x1c in r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dd38,"ax",%progbits
	.p2align 2
	.global fn_0801dd38
	.thumb_func
	.type fn_0801dd38, %function
fn_0801dd38:
	push	{r4, lr}
	cbnz	r0, .L0801dd44
	bl	fn_0801dccc
	cmp	r0, #0x0
	beq.n	.L0801dd46
.L0801dd44:
	ldr	r0, [r0, #0x1c]
.L0801dd46:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0801dd48 - returns the first or the next entry of the list at 0x2000805c.
@ Parameter: r0 = node pointer or 0. With r0 = 0 tail-calls
@ get_word_4_or_zero(0x2000805c) (first entry), otherwise tail-calls
@ read_word_at_base_plus_offset_4(0x2000805c, r0) (next entry).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dd48,"ax",%progbits
	.p2align 2
	.global fn_0801dd48
	.thumb_func
	.type fn_0801dd48, %function
fn_0801dd48:
	cbz	r0, .L0801dd52
	mov	r1, r0
	ldr	r0, .L0801dd58
	b.w	read_word_at_base_plus_offset_4
.L0801dd52:
	ldr	r0, .L0801dd58
	b.w	get_word_4_or_zero
.L0801dd58:
	.word	0x2000805c

@ ----------------------------------------------------------------------------
@ fn_0801dd5c - returns the word at offset 0x10 of a node.
@ Parameter: r0 = node pointer or 0 (0 uses fn_0801dccc(), returns 0 when
@ that is 0). Returns the word at node+0x10 in r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dd5c,"ax",%progbits
	.p2align 2
	.global fn_0801dd5c
	.thumb_func
	.type fn_0801dd5c, %function
fn_0801dd5c:
	push	{r4, lr}
	cbnz	r0, .L0801dd68
	bl	fn_0801dccc
	cmp	r0, #0x0
	beq.n	.L0801dd6a
.L0801dd68:
	ldr	r0, [r0, #0x10]
.L0801dd6a:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0801dd6c - returns the word at offset 0x14 of a node.
@ Parameter: r0 = node pointer or 0 (0 uses fn_0801dccc(), returns 0 when
@ that is 0). Returns the word at node+0x14 in r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dd6c,"ax",%progbits
	.p2align 2
	.global fn_0801dd6c
	.thumb_func
	.type fn_0801dd6c, %function
fn_0801dd6c:
	push	{r4, lr}
	cbnz	r0, .L0801dd78
	bl	fn_0801dccc
	cmp	r0, #0x0
	beq.n	.L0801dd7a
.L0801dd78:
	ldr	r0, [r0, #0x14]
.L0801dd7a:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0801dd7c - returns the word at offset 8 of a node.
@ Parameter: r0 = node pointer or 0 (0 uses fn_0801dccc()). Returns the word
@ at node+8 in r0 (no zero check on the fn_0801dccc result).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dd7c,"ax",%progbits
	.p2align 2
	.global fn_0801dd7c
	.thumb_func
	.type fn_0801dd7c, %function
fn_0801dd7c:
	push	{r4, lr}
	cbnz	r0, .L0801dd84
	bl	fn_0801dccc
.L0801dd84:
	ldr	r0, [r0, #0x8]
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0801dd88 - returns the height or the width of a node's structure.
@ Parameter: r0 = pointer to a node or 0 (0 uses the word at 0x20000478 and
@ returns 0 when that is also 0). Returns an integer in r0.
@ d = the structure at [node]; mode = bits 4..5 of byte [d+0x10]. Returns
@ halfword [d+0] (signed) when mode is 1 or 3, else halfword [d+2] (signed).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dd88,"ax",%progbits
	.p2align 2
	.global fn_0801dd88
	.thumb_func
	.type fn_0801dd88, %function
fn_0801dd88:
	cbnz	r0, .L0801dd92
	ldr	r0, .L0801ddb0
	ldr	r0, [r0, #0xc]
	cmp	r0, #0x0
	beq.n	.L0801dda6
.L0801dd92:
	ldr	r0, [r0, #0x0]
	ldrb	r1, [r0, #0x10]
	ubfx	r1, r1, #4, #2
	cmp	r1, #1
	beq.n	.L0801dda8
	cmp	r1, #3
	beq.n	.L0801dda8
	ldrsh.w	r0, [r0, #0x2]
.L0801dda6:
	bx	lr
.L0801dda8:
	ldrsh.w	r0, [r0, #0x0]
	bx	lr
	.short	0x0000	@ padding
.L0801ddb0:
	.word	0x2000046c

@ ----------------------------------------------------------------------------
@ fn_0801ddb4 - tests whether the use count of a node is above zero.
@ Parameter: r0 = node pointer or 0 (0 uses fn_0801dccc(), returns 0 when
@ that is 0). Returns 1 when the signed word node+0x154 is above 0, else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ddb4,"ax",%progbits
	.p2align 2
	.global fn_0801ddb4
	.thumb_func
	.type fn_0801ddb4, %function
fn_0801ddb4:
	push	{r4, lr}
	cbnz	r0, .L0801ddc0
	bl	fn_0801dccc
	cmp	r0, #0x0
	beq.n	.L0801ddca
.L0801ddc0:
	ldr.w	r0, [r0, #0x154]
	cmp	r0, #0x0
	ble.n	.L0801ddcc
	movs	r0, #0x1
.L0801ddca:
	pop	{r4, pc}
.L0801ddcc:
	movs	r0, #0x0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0801ddd0 - calls fn_08026b88(r0, 0, 0, 0, 0).
@ Parameter: r0 is passed on unchanged; r1, r2, r3 and the stack argument
@ [sp] are set to 0. No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ddd0,"ax",%progbits
	.p2align 2
	.global fn_0801ddd0
	.thumb_func
	.type fn_0801ddd0, %function
fn_0801ddd0:
	push	{r3, lr}
	movs	r1, #0x0
	mov	r3, r1
	mov	r2, r1
	str	r1, [sp, #0x0]
	bl	fn_08026b88
	pop	{r3, pc}

@ ----------------------------------------------------------------------------
@ fn_0801dde0 - calls the function pointer at word [device+0x10] under
@ conditions.
@ Parameters: r0 = pointer to a device description (function pointer at word
@ +0x10), r1 = pointer to a structure (byte +0xc, halfword +2), r2, r3,
@ stack [sp+0x18] = start, stack [sp+0x1c] = end. No return value.
@ When byte [r1+0xc] is above 2, halfword [r1+2] is nonzero and the two stack
@ values differ, calls the function pointer at word [r0+0x10] with
@ (r0, r1, r2, r3, start, end), the last two passed on the stack.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801dde0,"ax",%progbits
	.p2align 2
	.global fn_0801dde0
	.thumb_func
	.type fn_0801dde0, %function
fn_0801dde0:
	push	{r2, r3, r4, r5, r6, lr}
	ldrb	r6, [r1, #0xc]
	ldrd	r5, r4, [sp, #0x18]
	cmp	r6, #2
	bls.n	.L0801ddfe
	ldrh	r6, [r1, #0x2]
	cmp	r6, #0x0
	beq.n	.L0801ddfe
	cmp	r5, r4
	beq.n	.L0801ddfe
	strd	r5, r4, [sp, #0x0]
	ldr	r4, [r0, #0x10]
	blx	r4
.L0801ddfe:
	pop	{r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_0801de00 - initialises a 0x10-byte structure.
@ Parameter: r0 = structure pointer. No return value.
@ Clears 0x10 bytes with clear_bytes, sets halfword +2 = 1, byte +0xc = 0xff,
@ then halfword +0 = 0 (built from three zero bitfields at bits 0, 5 and 11
@ through a stack slot).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801de00,"ax",%progbits
	.global fn_0801de00
	.thumb_func
	.type fn_0801de00, %function
fn_0801de00:
	push	{r3, r4, r5, lr}
	mov	r4, r0
	movs	r1, #0x10
	bl	clear_bytes
	movs	r0, #0x1
	strh	r0, [r4, #0x2]
	movs	r0, #0xff
	strb	r0, [r4, #0xc]
	ldrh.w	r1, [sp, #0x0]
	movs	r0, #0x0
	bfi	r1, r0, #0, #5
	uxth	r1, r1
	bfi	r1, r0, #5, #6
	uxth	r1, r1
	bfi	r1, r0, #11, #5
	strh.w	r1, [sp, #0x0]
	uxth	r0, r1
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0x0]
	pop	{r3, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ return_only_08020724 - returns immediately. No parameters, no return value.
@ ----------------------------------------------------------------------------
	.section .text.return_only_08020724,"ax",%progbits
	.global return_only_08020724
	.thumb_func
	.type return_only_08020724, %function
return_only_08020724:
	bx	lr

@ ----------------------------------------------------------------------------
@ call_slot_28_if_set - calls the function pointer at word [object+0x28].
@ Parameters: r0 = object, r1..r3 and ten stack-passed values forwarded.
@ When the word at [r0+0x28] is nonzero, calls that function pointer with all
@ ten arguments (r0 = object, r1 = param_2, r2, r3, and the remaining six on
@ the stack, copied from the caller's stack). No return value.
@ ----------------------------------------------------------------------------
	.section .text.call_slot_28_if_set,"ax",%progbits
	.global call_slot_28_if_set
	.thumb_func
	.type call_slot_28_if_set, %function
call_slot_28_if_set:
	push.w	{r4, r5, r6, r7, r8, r9, lr}
	sub	sp, #0x1c
	mov	r9, r1
	ldrd	r5, r1, [sp, #0x48]
	ldrd	r7, r6, [sp, #0x40]
	ldrd	r8, r12, [sp, #0x38]
	ldr	r4, [r0, #0x28]
	cmp	r4, #0x0
	beq.n	.L08020752
	str.w	r8, [sp, #0x0]
	strd	r5, r1, [sp, #0x10]
	str	r6, [sp, #0xc]
	strd	r12, r7, [sp, #0x4]
	mov	r1, r9
	blx	r4
.L08020752:
	add	sp, #0x1c
	pop.w	{r4, r5, r6, r7, r8, r9, pc}

@ ----------------------------------------------------------------------------
@ call_slot_30_if_set - tail-calls the function pointer at word [object+0x30].
@ Parameter: r0 = object. When the word at [r0+0x30] is nonzero it is jumped
@ to with bx and r0 still holding the object; otherwise returns. No return
@ value of its own.
@ ----------------------------------------------------------------------------
	.section .text.call_slot_30_if_set,"ax",%progbits
	.global call_slot_30_if_set
	.thumb_func
	.type call_slot_30_if_set, %function
call_slot_30_if_set:
	ldr	r1, [r0, #0x30]
	cmp	r1, #0x0
	beq.n	.L08020760
	bx	r1
.L08020760:
	bx	lr

@ ----------------------------------------------------------------------------
@ get_byte8_low7 - returns byte [r0+8] with bit 7 cleared (masked with 0x7f).
@ Parameter: r0 = pointer.
@ ----------------------------------------------------------------------------
	.section .text.get_byte8_low7,"ax",%progbits
	.global get_byte8_low7
	.thumb_func
	.type get_byte8_low7, %function
get_byte8_low7:
	ldrb	r0, [r0, #0x8]
	bic.w	r0, r0, #0x80
	bx	lr

@ ----------------------------------------------------------------------------
@ get_word_at_4 - returns the word at [r0+4]. Parameter: r0 = pointer.
@ ----------------------------------------------------------------------------
	.section .text.get_word_at_4,"ax",%progbits
	.global get_word_at_4
	.thumb_func
	.type get_word_at_4, %function
get_word_at_4:
	ldr	r0, [r0, #0x4]
	bx	lr

@ ----------------------------------------------------------------------------
@ get_word_10_if_byte_8_14_to_19 - returns word [r0+0x10] for some types.
@ Parameter: r0 = object pointer. Returns word [r0+0x10] when byte [r0+8] is
@ 0x14, 0x15, 0x16, 0x17, 0x18 or 0x19 (compared in the order 0x15, 0x14,
@ 0x16, 0x18, 0x17, 0x19), else 0.
@ ----------------------------------------------------------------------------
	.section .text.get_word_10_if_byte_8_14_to_19,"ax",%progbits
	.global get_word_10_if_byte_8_14_to_19
	.thumb_func
	.type get_word_10_if_byte_8_14_to_19, %function
get_word_10_if_byte_8_14_to_19:
	ldrb	r1, [r0, #0x8]
	cmp	r1, #0x15
	beq.n	.L0802078c
	cmp	r1, #0x14
	beq.n	.L0802078c
	cmp	r1, #0x16
	beq.n	.L0802078c
	cmp	r1, #0x18
	beq.n	.L0802078c
	cmp	r1, #0x17
	beq.n	.L0802078c
	cmp	r1, #0x19
	beq.n	.L0802078c
	movs	r0, #0x0
	bx	lr
.L0802078c:
	ldr	r0, [r0, #0x10]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08020790 - returns word [r0+0x10] for the types 0x01 to 0x10.
@ Parameter: r0 = object pointer. Returns word [r0+0x10] when byte [r0+8] is
@ one of 0x01 .. 0x10 (compared in ascending order), else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020790,"ax",%progbits
	.global fn_08020790
	.thumb_func
	.type fn_08020790, %function
fn_08020790:
	ldrb	r1, [r0, #0x8]
	cmp	r1, #0x1
	beq.n	.L080207d6
	cmp	r1, #0x2
	beq.n	.L080207d6
	cmp	r1, #0x3
	beq.n	.L080207d6
	cmp	r1, #0x4
	beq.n	.L080207d6
	cmp	r1, #0x5
	beq.n	.L080207d6
	cmp	r1, #0x6
	beq.n	.L080207d6
	cmp	r1, #0x7
	beq.n	.L080207d6
	cmp	r1, #0x8
	beq.n	.L080207d6
	cmp	r1, #0x9
	beq.n	.L080207d6
	cmp	r1, #0xa
	beq.n	.L080207d6
	cmp	r1, #0xb
	beq.n	.L080207d6
	cmp	r1, #0xc
	beq.n	.L080207d6
	cmp	r1, #0xd
	beq.n	.L080207d6
	cmp	r1, #0xe
	beq.n	.L080207d6
	cmp	r1, #0xf
	beq.n	.L080207d6
	cmp	r1, #0x10
	beq.n	.L080207d6
	movs	r0, #0x0
	bx	lr
.L080207d6:
	ldr	r0, [r0, #0x10]
	bx	lr

@ ----------------------------------------------------------------------------
@ get_word_at_0x10 - returns the word at [r0+0x10]. Parameter: r0 = pointer.
@ ----------------------------------------------------------------------------
	.section .text.get_word_at_0x10,"ax",%progbits
	.global get_word_at_0x10
	.thumb_func
	.type get_word_at_0x10, %function
get_word_at_0x10:
	ldr	r0, [r0, #0x10]
	bx	lr

@ ----------------------------------------------------------------------------
@ get_first_word - returns the word at [r0+0]. Parameter: r0 = pointer.
@ Used with a message pointer to read the object pointer stored at message+0.
@ Followed by 2 bytes of padding.
@ ----------------------------------------------------------------------------
	.section .text.get_first_word,"ax",%progbits
	.global get_first_word
	.thumb_func
	.type get_first_word, %function
get_first_word:
	ldr	r0, [r0, #0x0]
	bx	lr
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ increment_counter_20000498 - adds 1 to the word at 0x20000498.
@ No parameters, no return value (r0 and r1 are used as scratch).
@ ----------------------------------------------------------------------------
	.section .text.increment_counter_20000498,"ax",%progbits
	.p2align 2
	.global increment_counter_20000498
	.thumb_func
	.type increment_counter_20000498, %function
increment_counter_20000498:
	ldr	r1, .L080207f0
	ldr	r0, [r1, #0x0]
	.inst.n	0x1c40	@ adds r0, r0, #1
	str	r0, [r1, #0x0]
	bx	lr
	.short	0x0000	@ padding
.L080207f0:
	.word	0x20000498

@ ----------------------------------------------------------------------------
@ fn_080207f4 - builds a record on the stack and passes it to fn_0801a360.
@ Parameters: r0 = target, r1 = byte code, r2 = argument. Returns 1 when r0 is
@ 0, else the result of fn_0801a360(record).
@ The record (0x20 bytes on the stack): words +0 and +4 = r0, byte +8 = r1,
@ word +0xc = 0, word +0x10 = r2, word +0x14 = the old head of the chain at
@ word 0x2000049c (0x20000498 + 4), byte +0x18 with bits 0..2 cleared. The
@ record address is stored as the new head of that chain while fn_0801a360
@ runs, then the old head is restored.
@ ----------------------------------------------------------------------------
	.section .text.fn_080207f4,"ax",%progbits
	.p2align 2
	.global fn_080207f4
	.thumb_func
	.type fn_080207f4, %function
fn_080207f4:
	push	{r4, lr}
	sub	sp, #0x20
	cbz	r0, .L0802082c
	str	r0, [sp, #0x0]
	str	r0, [sp, #0x4]
	strb.w	r1, [sp, #0x8]
	movs	r0, #0x0
	strd	r0, r2, [sp, #0xc]
	ldrb.w	r0, [sp, #0x18]
	ldr	r4, .L08020830
	bic.w	r0, r0, #0x7
	strb.w	r0, [sp, #0x18]
	ldr	r0, [r4, #0x4]
	str	r0, [sp, #0x14]
	str.w	sp, [r4, #0x4]
	mov	r0, sp
	bl	fn_0801a360
	ldr	r1, [sp, #0x14]
	str	r1, [r4, #0x4]
.L08020828:
	add	sp, #0x20
	pop	{r4, pc}
.L0802082c:
	movs	r0, #0x1
	b.n	.L08020828
.L08020830:
	.word	0x20000498

@ ----------------------------------------------------------------------------
@ fn_08020834 - raises the halfword an object points to to at least a value.
@ Parameters: r0 = object, r1 = value. No return value.
@ When byte [r0+8] is 0x13, stores max(r1, signed halfword at [word [r0+0x10]])
@ into that halfword.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020834,"ax",%progbits
	.global fn_08020834
	.thumb_func
	.type fn_08020834, %function
fn_08020834:
	ldrb	r2, [r0, #0x8]
	cmp	r2, #0x13
	bne.n	.L08020848
	ldr	r0, [r0, #0x10]
	ldrsh.w	r2, [r0, #0x0]
	cmp	r2, r1
	ble.n	.L08020846
	mov	r1, r2
.L08020846:
	strh	r1, [r0, #0x0]
.L08020848:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0802084a - calls fn_0802085c and fn_08020f0c, then tail-calls fn_08023030.
@ No parameters; no value of its own. push {r4,lr}; bl fn_0802085c;
@ bl fn_08020f0c; pop {r4,lr}; b.w fn_08023030, which returns to the caller of
@ this function. fn_08023030 (a separate function) calls
@ increment_counter_20000498, stores the low byte of r0 to byte 0x20000566,
@ then tail-calls fn_08012608(0x20014398, 0x10).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802084a,"ax",%progbits
	.global fn_0802084a
	.thumb_func
	.type fn_0802084a, %function
fn_0802084a:
	push	{r4, lr}
	bl	fn_0802085c
	bl	fn_08020f0c
	pop.w	{r4, lr}
	b.w	fn_08023030

@ ----------------------------------------------------------------------------
@ fn_0802085c - stores five handles into the halfwords at 0x20000544.
@ No parameters, no return value.
@ Halfword 0x20000544 = fn_0802291c(0x0801ac51, 0) (0x0801ac51 is a function
@ pointer to fn_0801ac50); 0x20000546 = fn_08026ffc(0); 0x20000548,
@ 0x2000054a and 0x2000054c = fn_08026ffc(4) each.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802085c,"ax",%progbits
	.p2align 2
	.global fn_0802085c
	.thumb_func
	.type fn_0802085c, %function
fn_0802085c:
	push	{r4, lr}
	movs	r1, #0x0
	ldr	r0, .L0802088c
	bl	fn_0802291c
	ldr	r4, .L08020890
	strh	r0, [r4, #0x0]
	movs	r0, #0x0
	bl	fn_08026ffc
	strh	r0, [r4, #0x2]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0x4]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0x6]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0x8]
	pop	{r4, pc}
.L0802088c:
	.word	fn_0801ac50		@ function pointer (0x0801ac51)
.L08020890:
	.word	0x20000544

@ ----------------------------------------------------------------------------
@ fn_08020ee0 - replaces the buffer at 0x200004e4 with a new cleared one.
@ Parameter: r0 = size. No return value.
@ Frees the buffer pointed to by word 0x200004e4 with fn_08022c68, allocates r0
@ bytes with fn_08022b50 into word 0x200004e4 and word 0x20000570, clears it
@ with clear_bytes and stores the size in word 0x2000056c.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020ee0,"ax",%progbits
	.p2align 2
	.global fn_08020ee0
	.thumb_func
	.type fn_08020ee0, %function
fn_08020ee0:
	push	{r4, r5, r6, lr}
	ldr	r5, .L08020f04
	mov	r4, r0
	ldr	r0, [r5, #0x0]
	bl	fn_08022c68
	mov	r0, r4
	bl	fn_08022b50
	str	r0, [r5, #0x0]
	ldr	r5, .L08020f08
	mov	r1, r4
	str	r0, [r5, #0x8]
	bl	clear_bytes
	str	r4, [r5, #0x4]
	pop	{r4, r5, r6, pc}
	.short	0x0000	@ padding
.L08020f04:
	.word	0x200004e4
.L08020f08:
	.word	0x20000568

@ ----------------------------------------------------------------------------
@ fn_08020f0c - stores eleven handles into the halfwords at 0x20000550.
@ No parameters, no return value.
@ Halfword 0x20000550 = fn_0802291c(0x0801baf9, 0) (0x0801baf9 is a function
@ pointer to fn_0801baf8); then each of fn_08026ffc(4) is stored in order to
@ 0x20000552, 0x20000556, 0x20000554, 0x20000558, 0x20000562, 0x20000560,
@ 0x2000055c, 0x2000055a, 0x2000055e, 0x20000564.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020f0c,"ax",%progbits
	.p2align 2
	.global fn_08020f0c
	.thumb_func
	.type fn_08020f0c, %function
fn_08020f0c:
	push	{r4, lr}
	movs	r1, #0x0
	ldr	r0, .L08020f6c
	bl	fn_0802291c
	ldr	r4, .L08020f70
	strh	r0, [r4, #0x0]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0x2]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0x6]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0x4]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0x8]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0x12]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0x10]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0xc]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0xa]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0xe]
	movs	r0, #0x4
	bl	fn_08026ffc
	strh	r0, [r4, #0x14]
	pop	{r4, pc}
.L08020f6c:
	.word	fn_0801baf8		@ function pointer (0x0801baf9)
.L08020f70:
	.word	0x20000550

@ ----------------------------------------------------------------------------
@ fn_08020f74 - adds an item to a list and links it to its owner.
@ Parameters: r0 = list, r1 = item. No return value. Does nothing when r0 is 0.
@ Calls fn_0802108c(item). Walks the list with get_word_4_or_zero and
@ read_word_at_base_plus_offset_4 and returns when the item is already in it.
@ When fn_08023f18(item) is nonzero and word [[item+8]+8] (the owner) is
@ nonzero and the owner's current item ([[owner+0xc]]) equals the item, calls
@ fn_08021062(owner). When word [item+8] is 0 calls fn_0802318c(item). Stores
@ the list into word [[item+8]+8]. Appends a node with fn_08012654(list)
@ (returns when it is 0), stores the item in the node, and when the list's
@ first node (get_word_4_or_zero) is that node tail-calls fn_08021062(list).
@ ----------------------------------------------------------------------------
	.section .text.fn_08020f74,"ax",%progbits
	.p2align 2
	.global fn_08020f74
	.thumb_func
	.type fn_08020f74, %function
fn_08020f74:
	push	{r4, r5, r6, lr}
	movs	r6, r0
	mov	r4, r1
	beq.n	.L08020fe2
	mov	r0, r1
	bl	fn_0802108c
	mov	r0, r6
	bl	get_word_4_or_zero
	b.n	.L08020f96
.L08020f8a:
	ldr	r0, [r1, #0x0]
	cmp	r0, r4
	beq.n	.L08020fe2
	mov	r0, r6
	bl	read_word_at_base_plus_offset_4
.L08020f96:
	movs	r1, r0
	bne.n	.L08020f8a
	mov	r0, r4
	bl	fn_08023f18
	cbz	r0, .L08020fb4
	ldr	r1, [r4, #0x8]
	ldr	r1, [r1, #0x8]
	cbz	r1, .L08020fb4
	ldr	r1, [r1, #0xc]
	ldr	r1, [r1, #0x0]
	cmp	r1, r4
	bne.n	.L08020fb4
	bl	fn_08021062
.L08020fb4:
	ldr	r0, [r4, #0x8]
	cbnz	r0, .L08020fbe
	mov	r0, r4
	bl	fn_0802318c
.L08020fbe:
	ldr	r0, [r4, #0x8]
	str	r6, [r0, #0x8]
	mov	r0, r6
	bl	fn_08012654
	movs	r5, r0
	beq.n	.L08020fe2
	mov	r0, r6
	str	r4, [r5, #0x0]
	bl	get_word_4_or_zero
	cmp	r0, r5
	bne.n	.L08020fe2
	mov	r0, r6
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08021062
.L08020fe2:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08020fe4 - calls fn_0801af20 and then the slot at [object+0x14].
@ Parameter: r0 = object. No return value.
@ Calls fn_0801af20(object, get_word_4_or_zero, read_word_at_base_plus_offset_4)
@ (the two function pointers 0x080125cf and 0x080125f3). When the word at
@ [object+0x14] is set and the result is 0, jumps to it with bx (after
@ restoring the stack) with r0 = object and r1 = 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020fe4,"ax",%progbits
	.p2align 2
	.global fn_08020fe4
	.thumb_func
	.type fn_08020fe4, %function
fn_08020fe4:
	push	{r4, lr}
	mov	r4, r0
	ldr	r2, .L08021008
	ldr	r1, .L0802100c
	bl	fn_0801af20
	ldr	r2, [r4, #0x14]
	cmp	r2, #0x0
	beq.n	.L08021004
	cmp	r0, #0x0
	bne.n	.L08021004
	mov	r0, r4
	pop.w	{r4, lr}
	movs	r1, #0x1
	bx	r2
.L08021004:
	pop	{r4, pc}
	.short	0x0000	@ padding
.L08021008:
	.word	read_word_at_base_plus_offset_4		@ function pointer (0x080125f3)
.L0802100c:
	.word	get_word_4_or_zero		@ function pointer (0x080125cf)

@ ----------------------------------------------------------------------------
@ fn_08021010 - calls fn_0801af20 and then the slot at [object+0x14].
@ Parameter: r0 = object. No return value.
@ Calls fn_0801af20(object, get_word_8_or_zero, read_word_at_base_plus_offset)
@ (the two function pointers 0x08012601 and 0x080125fb). When the word at
@ [object+0x14] is set and the result is 0, jumps to it with bx (after
@ restoring the stack) with r0 = object and r1 = 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021010,"ax",%progbits
	.p2align 2
	.global fn_08021010
	.thumb_func
	.type fn_08021010, %function
fn_08021010:
	push	{r4, lr}
	mov	r4, r0
	ldr	r2, .L08021034
	ldr	r1, .L08021038
	bl	fn_0801af20
	ldr	r2, [r4, #0x14]
	cmp	r2, #0x0
	beq.n	.L08021030
	cmp	r0, #0x0
	bne.n	.L08021030
	mov	r0, r4
	pop.w	{r4, lr}
	movs	r1, #0x0
	bx	r2
.L08021030:
	pop	{r4, pc}
	.short	0x0000	@ padding
.L08021034:
	.word	read_word_at_base_plus_offset		@ function pointer (0x080125fb)
.L08021038:
	.word	get_word_8_or_zero		@ function pointer (0x08012601)

@ ----------------------------------------------------------------------------
@ read_word_200004a0 - returns the word at 0x200004a0. No parameters.
@ ----------------------------------------------------------------------------
	.section .text.read_word_200004a0,"ax",%progbits
	.p2align 2
	.global read_word_200004a0
	.thumb_func
	.type read_word_200004a0, %function
read_word_200004a0:
	ldr	r0, .L08021044
	ldr	r0, [r0, #0x0]
	bx	lr
	.short	0x0000	@ padding
.L08021044:
	.word	0x200004a0

@ ----------------------------------------------------------------------------
@ fn_08021048 - returns bit 1 of byte [object+0x1c], or 0 for a null object.
@ Parameter: r0 = object. Returns 0 when r0 is 0, else (byte [r0+0x1c] & 3) >> 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021048,"ax",%progbits
	.p2align 2
	.global fn_08021048
	.thumb_func
	.type fn_08021048, %function
fn_08021048:
	cmp	r0, #0x0
	beq.n	.L08021052
	ldrb	r0, [r0, #0x1c]
	ubfx	r0, r0, #1, #1
.L08021052:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08021054 - returns the word an object's pointer at +0xc refers to.
@ Parameter: r0 = object. Returns 0 when r0 is 0 or the pointer at [r0+0xc] is
@ 0, else the word at [[r0+0xc]].
@ ----------------------------------------------------------------------------
	.section .text.fn_08021054,"ax",%progbits
	.global fn_08021054
	.thumb_func
	.type fn_08021054, %function
fn_08021054:
	cmp	r0, #0x0
	beq.n	.L08021060
	ldr	r0, [r0, #0xc]
	cmp	r0, #0x0
	beq.n	.L08021060
	ldr	r0, [r0, #0x0]
.L08021060:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08021062 - runs fn_08020fe4 or fn_08021010 with bit 3 of byte +0x1c set.
@ Parameter: r0 = object. No return value.
@ Sets bit 3 of byte [object+0x1c], calls fn_08021010(object) when bit 2 of
@ the old byte was set, else fn_08020fe4(object), then restores bit 3 of the
@ byte to its old value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021062,"ax",%progbits
	.global fn_08021062
	.thumb_func
	.type fn_08021062, %function
fn_08021062:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	ldrb	r0, [r0, #0x1c]
	ubfx	r5, r0, #3, #1
	orr.w	r0, r0, #0x8
	strb	r0, [r4, #0x1c]
	lsls	r0, r0, #0x1d
	mov	r0, r4
	bmi.n	.L0802107e
	bl	fn_08020fe4
	b.n	.L08021082
.L0802107e:
	bl	fn_08021010
.L08021082:
	ldrb	r0, [r4, #0x1c]
	bfi	r0, r5, #3, #1
	strb	r0, [r4, #0x1c]
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_0802108c - removes an item from its owner's list.
@ Parameter: r0 = item (kept in r6). No return value.
@ Finds the owner with fn_08023f18(item) (r4); returns when it is 0.
@ When the owner's current item pointer ([owner+0xc]) is set and the word it
@ points to equals the item: clears bit 0 of byte [owner+0x1c] when set, then
@ calls fn_080207f4(word [[owner+0xc]], 0xf, fn_0801b298(owner)) when
@ get_word_4_or_zero(owner) and get_word_8_or_zero(owner) both equal
@ [owner+0xc], else fn_08021062(owner).
@ Clears [owner+0xc] when it is still set and its word still equals the item.
@ Walks the owner's list (get_word_4_or_zero, read_word_at_base_plus_offset_4)
@ for the item; when found, removes the node with fn_080126a2(owner, node),
@ frees it with fn_08022c68 and clears word [[item+8]+8] when [item+8] is set.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802108c,"ax",%progbits
	.p2align 2
	.global fn_0802108c
	.thumb_func
	.type fn_0802108c, %function
fn_0802108c:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r6, r0
	bl	fn_08023f18
	movs	r4, r0
	beq.n	.L08021116
	ldr	r0, [r4, #0xc]
	movs	r7, #0x0
	cbz	r0, .L080210f2
	ldr	r0, [r0, #0x0]
	cmp	r0, r6
	bne.n	.L080210e8
	ldrb	r0, [r4, #0x1c]
	lsls	r1, r0, #0x1f
	beq.n	.L080210b2
	bic.w	r0, r0, #0x1
	strb	r0, [r4, #0x1c]
.L080210b2:
	mov	r0, r4
	bl	get_word_4_or_zero
	ldr	r1, [r4, #0xc]
	cmp	r0, r1
	bne.n	.L080210de
	mov	r0, r4
	bl	get_word_8_or_zero
	ldr	r1, [r4, #0xc]
	cmp	r0, r1
	bne.n	.L080210de
	mov	r0, r4
	bl	fn_0801b298
	mov	r2, r0
	ldr	r0, [r4, #0xc]
	movs	r1, #0xf
	ldr	r0, [r0, #0x0]
	bl	fn_080207f4
	b.n	.L080210e4
.L080210de:
	mov	r0, r4
	bl	fn_08021062
.L080210e4:
	ldr	r0, [r4, #0xc]
	cbz	r0, .L080210f2
.L080210e8:
	ldr	r0, [r4, #0xc]
	ldr	r0, [r0, #0x0]
	cmp	r0, r6
	bne.n	.L080210f2
	str	r7, [r4, #0xc]
.L080210f2:
	mov	r0, r4
	bl	get_word_4_or_zero
	b.n	.L0802111e
.L080210fa:
	ldr	r0, [r5, #0x0]
	mov	r1, r5
	cmp	r0, r6
	mov	r0, r4
	bne.n	.L0802111a
	bl	fn_080126a2
	mov	r0, r5
	bl	fn_08022c68
	ldr	r0, [r6, #0x8]
	cmp	r0, #0x0
	beq.n	.L08021116
	str	r7, [r0, #0x8]
.L08021116:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0802111a:
	bl	read_word_at_base_plus_offset_4
.L0802111e:
	movs	r5, r0
	bne.n	.L080210fa
	b.n	.L08021116

@ ----------------------------------------------------------------------------
@ fn_08021124 - sets or clears bit 1 of byte [object+0x1c] and notifies.
@ Parameters: r0 = object (r4), r1 = flag (compared as a full word with bit 1
@ of the byte). No return value of its own.
@ Returns when r0 is 0 or when bit 1 of byte [r4+0x1c] already equals r1.
@ Otherwise inserts bit 0 of r1 into bit 1 of byte [r4+0x1c]; r5 =
@ fn_08021054(r4), returns when it is 0; calls fn_080207f4(word [[r4+0xc]],
@ 0xe, fn_0801b298(r4)); returns unless the result is 1; then tail-calls
@ fn_08025400(r5).
@ ----------------------------------------------------------------------------
	.section .text.fn_08021124,"ax",%progbits
	.global fn_08021124
	.thumb_func
	.type fn_08021124, %function
fn_08021124:
	push	{r4, r5, r6, lr}
	movs	r4, r0
	beq.n	.L08021164
	ldrb	r0, [r4, #0x1c]
	ubfx	r2, r0, #1, #1
	cmp	r2, r1
	beq.n	.L08021164
	bfi	r0, r1, #1, #1
	strb	r0, [r4, #0x1c]
	mov	r0, r4
	bl	fn_08021054
	movs	r5, r0
	beq.n	.L08021164
	mov	r0, r4
	bl	fn_0801b298
	mov	r2, r0
	ldr	r0, [r4, #0xc]
	movs	r1, #0xe
	ldr	r0, [r0, #0x0]
	bl	fn_080207f4
	cmp	r0, #0x1
	bne.n	.L08021164
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08025400
.L08021164:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ return_only_08021166 - returns immediately. No parameters, no return value.
@ ----------------------------------------------------------------------------
	.section .text.return_only_08021166,"ax",%progbits
	.global return_only_08021166
	.thumb_func
	.type return_only_08021166, %function
return_only_08021166:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08021168 - maps a code (0..14) to a size value.
@ Parameter: r0 = code. Returns in r0: codes 4 and 6 give 0x10, 5 gives 0x18,
@ 7 and 0xb give 1, 8 and 0xc give 2, 9 and 0xd give 4, 0xa and 0xe give 8,
@ all others (0..3 and 15 and above) give 0. Uses a tbb jump table.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021168,"ax",%progbits
	.p2align 2
	.global fn_08021168
	.thumb_func
	.type fn_08021168, %function
fn_08021168:
	mov	r1, r0
	movs	r0, #0x0
	cmp	r1, #0xf
	bcs.n	.L08021186
	tbb	[pc, r1]
.L08021174:
	.byte	(.L08021186 - .L08021174)/2
	.byte	(.L08021186 - .L08021174)/2
	.byte	(.L08021186 - .L08021174)/2
	.byte	(.L08021186 - .L08021174)/2
	.byte	(.L08021184 - .L08021174)/2
	.byte	(.L08021188 - .L08021174)/2
	.byte	(.L08021184 - .L08021174)/2
	.byte	(.L0802118c - .L08021174)/2
	.byte	(.L08021190 - .L08021174)/2
	.byte	(.L08021194 - .L08021174)/2
	.byte	(.L08021198 - .L08021174)/2
	.byte	(.L0802118c - .L08021174)/2
	.byte	(.L08021190 - .L08021174)/2
	.byte	(.L08021194 - .L08021174)/2
	.byte	(.L08021198 - .L08021174)/2
	.byte	0x00	@ padding
.L08021184:
	movs	r0, #0x10
.L08021186:
	bx	lr
.L08021188:
	movs	r0, #0x18
	bx	lr
.L0802118c:
	movs	r0, #0x1
	bx	lr
.L08021190:
	movs	r0, #0x2
	bx	lr
.L08021194:
	movs	r0, #0x4
	bx	lr
.L08021198:
	movs	r0, #0x8
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0802119c - tests whether a code is 2, 5 or 7 to 0xe.
@ Parameter: r0 = code. Returns 1 for 2, 5, 7, 8, 9, 0xa, 0xb, 0xc, 0xd, 0xe,
@ else 0. Subtracts 2 and uses a tbb jump table (13 entries).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802119c,"ax",%progbits
	.p2align 2
	.global fn_0802119c
	.thumb_func
	.type fn_0802119c, %function
fn_0802119c:
	mov	r1, r0
	movs	r0, #0x0
	.inst.n	0x1e89	@ subs r1, r1, #2
	cmp	r1, #0xd
	bcs.n	.L080211ba
	tbb	[pc, r1]
.L080211aa:
	.byte	(.L080211b8 - .L080211aa)/2
	.byte	(.L080211ba - .L080211aa)/2
	.byte	(.L080211ba - .L080211aa)/2
	.byte	(.L080211b8 - .L080211aa)/2
	.byte	(.L080211ba - .L080211aa)/2
	.byte	(.L080211b8 - .L080211aa)/2
	.byte	(.L080211b8 - .L080211aa)/2
	.byte	(.L080211b8 - .L080211aa)/2
	.byte	(.L080211b8 - .L080211aa)/2
	.byte	(.L080211b8 - .L080211aa)/2
	.byte	(.L080211b8 - .L080211aa)/2
	.byte	(.L080211b8 - .L080211aa)/2
	.byte	(.L080211b8 - .L080211aa)/2
	.byte	0x00	@ padding
.L080211b8:
	movs	r0, #0x1
.L080211ba:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_080211bc - tests whether a code is 3 or 6.
@ Parameter: r0 = code. Returns 1 when r0 is 3 or 6, else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080211bc,"ax",%progbits
	.p2align 2
	.global fn_080211bc
	.thumb_func
	.type fn_080211bc, %function
fn_080211bc:
	mov	r1, r0
	movs	r0, #0x0
	cmp	r1, #0x3
	beq.n	.L080211c8
	cmp	r1, #0x6
	bne.n	.L080211ca
.L080211c8:
	movs	r0, #0x1
.L080211ca:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_080211cc - resets the scroll/size fields of an object.
@ Parameters: r1 = object (r0 is not used). No return value.
@ Clears word [object+0x24]; byte [object+0x38] = (old & ~0x7c) | 3; halfword
@ +0x2c = rect_width_plus_one(object); +0x2e = rect_height_plus_one(object);
@ halfword +0x30 = 0; halfword +0x36 = 0x100; bit 7 of byte +0x38 set;
@ halfwords +0x28, +0x2a, +0x32, +0x34 = 0; byte +0x39 = 0. Then
@ fn_08023558(object, 2) and tail-call fn_08023050(object, 0x10000). Followed
@ by 2 bytes of padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_080211cc,"ax",%progbits
	.p2align 2
	.global fn_080211cc
	.thumb_func
	.type fn_080211cc, %function
fn_080211cc:
	push	{r4, r5, r6, lr}
	movs	r5, #0x0
	str	r5, [r1, #0x24]
	ldrb.w	r0, [r1, #0x38]
	mov	r4, r1
	bic.w	r0, r0, #0x7c
	orr.w	r0, r0, #0x3
	strb.w	r0, [r1, #0x38]
	mov	r0, r1
	bl	rect_width_plus_one
	strh	r0, [r4, #0x2c]
	mov	r0, r4
	bl	rect_height_plus_one
	strh	r0, [r4, #0x2e]
	strh	r5, [r4, #0x30]
	mov.w	r0, #0x100
	strh	r0, [r4, #0x36]
	ldrb.w	r0, [r4, #0x38]
	movs	r1, #0x2
	orr.w	r0, r0, #0x80
	strb.w	r0, [r4, #0x38]
	strh	r5, [r4, #0x28]
	strh	r5, [r4, #0x2a]
	strh	r5, [r4, #0x32]
	strh	r5, [r4, #0x34]
	strb.w	r5, [r4, #0x39]
	mov	r0, r4
	bl	fn_08023558
	mov	r0, r4
	pop.w	{r4, r5, r6, lr}
	mov.w	r1, #0x10000
	b.w	fn_08023050
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_0802122c - creates an object from a table and finishes it.
@ Parameter: r0 = argument. Returns the object in r0.
@ Calls fn_080233c4(d_0804fd20, r0), then fn_080234ac() and returns the
@ object created by the first call.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802122c,"ax",%progbits
	.p2align 2
	.global fn_0802122c
	.thumb_func
	.type fn_0802122c, %function
fn_0802122c:
	push	{r4, lr}
	mov	r1, r0
	ldr	r0, .L08021240
	bl	fn_080233c4
	mov	r4, r0
	bl	fn_080234ac
	mov	r0, r4
	pop	{r4, pc}
.L08021240:
	.word	d_0804fd20

@ ----------------------------------------------------------------------------
@ fn_08021244 - releases the block at word [object+0x24].
@ Parameters: r1 = object (r0 is not used). No return value.
@ When word [object+0x24] (the block) is nonzero: when byte [object+0x10] is 1
@ calls fn_08020a1e(block); frees words [block+0xc] and [block+0x10] with
@ fn_08022c68 when they are set, frees the block itself with fn_08022c68, and
@ clears word [object+0x24].
@ ----------------------------------------------------------------------------
	.section .text.fn_08021244,"ax",%progbits
	.p2align 2
	.global fn_08021244
	.thumb_func
	.type fn_08021244, %function
fn_08021244:
	push	{r4, r5, r6, lr}
	ldr	r4, [r1, #0x24]
	mov	r5, r1
	cmp	r4, #0x0
	beq.n	.L08021274
	ldrb	r0, [r5, #0x10]
	cmp	r0, #0x1
	bne.n	.L0802125a
	mov	r0, r4
	bl	fn_08020a1e
.L0802125a:
	ldr	r0, [r4, #0xc]
	cbz	r0, .L08021262
	bl	fn_08022c68
.L08021262:
	ldr	r0, [r4, #0x10]
	cbz	r0, .L0802126a
	bl	fn_08022c68
.L0802126a:
	mov	r0, r4
	bl	fn_08022c68
	movs	r0, #0x0
	str	r0, [r5, #0x24]
.L08021274:
	pop	{r4, r5, r6, pc}
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_08021278 - reads a three-way classified source into an output word.
@ Parameters: r0 = unused, r1 = source (string or descriptor), r2 = output word
@ pointer, r3 = unused (the four register arguments are pushed to the stack).
@ Returns 1 on success, 0 on failure.
@ Classifies r1 with fn_08021d60:
@   class 0: when (word [r1] & 0x1f) - 4 is below 0x11, copies bits 10..20 of
@     word [r1] to bits 10..20 of [r2], bits 21..31 of word [r1] to bits 21..31
@     of [r2] and the low 5 bits of byte [r1] to bits 0..4 of [r2]; returns 1
@   class 1: takes the extension with fn_08020a84(r1) and compares it with the
@     string "bin" (0x08021320) using string_compare; when equal opens the file
@     with fn_08020abc(handle on stack, r1, 2) and, when that returns 0, reads
@     4 bytes with fn_08020b32(handle, r2, 4, &count) and closes with
@     fn_08020a1e(handle); a nonzero read result or a count other than 4
@     returns 0; accepts (returns 1) when (byte [r2] & 0x1f) - 4 is below 0x11
@   class 2: stores into [r2] ((bits 10..20 of the word set to 1, bits 0..20
@     kept) + 0x200000, low 5 bits cleared) + 0xb and returns 1
@   other classes return 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021278,"ax",%progbits
	.p2align 2
	.global fn_08021278
	.thumb_func
	.type fn_08021278, %function
fn_08021278:
	push	{r0, r1, r2, r3, r4, r5, r6, lr}
	mov	r4, r2
	mov	r5, r1
	mov	r0, r1
	bl	fn_08021d60
	cbz	r0, .L08021290
	cmp	r0, #1
	beq.n	.L080212ba
	cmp	r0, #2
	beq.n	.L08021302
	b.n	.L080212fc
.L08021290:
	ldr	r1, [r5, #0x0]
	and.w	r0, r1, #0x1f
	.inst.n	0x1f00	@ subs r0, r0, #4
	cmp	r0, #0x11
	bcs.n	.L080212fc
	lsrs	r0, r1, #0xa
	ldr	r1, [r4, #0x0]
	bfi	r1, r0, #10, #11
	str	r1, [r4, #0x0]
	ldr	r0, [r5, #0x0]
	lsrs	r0, r0, #0x15
	bfi	r1, r0, #21, #11
	str	r1, [r4, #0x0]
	ldrb	r0, [r5, #0x0]
	bfi	r1, r0, #0, #5
	str	r1, [r4, #0x0]
	b.n	.L0802131a
.L080212ba:
	mov	r0, r5
	bl	fn_08020a84
	adr	r1, .L08021320
	bl	string_compare
	cbnz	r0, .L080212fc
	movs	r2, #0x2
	mov	r1, r5
	mov	r0, sp
	bl	fn_08020abc
	cbnz	r0, .L080212f0
	add	r3, sp, #0xc
	movs	r2, #0x4
	mov	r1, r4
	mov	r0, sp
	bl	fn_08020b32
	mov	r5, r0
	mov	r0, sp
	bl	fn_08020a1e
	cbnz	r5, .L080212fc
	ldr	r0, [sp, #0xc]
	cmp	r0, #0x4
	bne.n	.L080212fc
.L080212f0:
	ldrb	r0, [r4, #0x0]
	and.w	r0, r0, #0x1f
	.inst.n	0x1f00	@ subs r0, r0, #4
	cmp	r0, #0x11
	bcc.n	.L0802131a
.L080212fc:
	movs	r0, #0x0
.L080212fe:
	add	sp, #0x10
	pop	{r4, r5, r6, pc}
.L08021302:
	ldr	r0, [r4, #0x0]
	movs	r1, #0x1
	bfi	r0, r1, #10, #11
	ubfx	r0, r0, #0, #21
	add.w	r0, r0, #0x200000
	bic.w	r0, r0, #0x1f
	adds	r0, #0xb
	str	r0, [r4, #0x0]
.L0802131a:
	movs	r0, #0x1
	b.n	.L080212fe
	.short	0x0000	@ padding
.L08021320:
	.asciz	"bin"		@ extension string compared by string_compare

@ ----------------------------------------------------------------------------
@ fn_0802185c - takes a cleared 0x14-byte block from the pool at 0x20008098.
@ No parameters. Returns the block pointer in r0, or 0.
@ Takes a block from the pool with fn_08012618(0x20008098) and clears 0x14
@ bytes of it with clear_bytes.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802185c,"ax",%progbits
	.p2align 2
	.global fn_0802185c
	.thumb_func
	.type fn_0802185c, %function
fn_0802185c:
	push	{r4, lr}
	ldr	r0, .L08021878
	bl	fn_08012618
	movs	r4, r0
	beq.n	.L08021872
	movs	r1, #0x14
	bl	clear_bytes
	mov	r0, r4
	pop	{r4, pc}
.L08021872:
	movs	r0, #0x0
	pop	{r4, pc}
	.short	0x0000	@ padding
.L08021878:
	.word	0x20008098

@ ----------------------------------------------------------------------------
@ fn_0802187c - offers a source to the loaders in the list at 0x20008098.
@ Parameters: r0 = source (r5), r1 = 4-byte output (r7). Returns 1 when a
@ loader accepted, else 0.
@ Clears the 4 output bytes with clear_bytes; returns 0 when r0 is 0, or when
@ the classification fn_08021d60(r0) is 0 and word [r0+8] is 0. Walks the list
@ at 0x20008098 (get_word_4_or_zero, read_word_at_base_plus_offset_4) and calls
@ each entry's function pointer (word [entry+0]) when it is set, with
@ (entry, source, output), until one returns 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802187c,"ax",%progbits
	.p2align 2
	.global fn_0802187c
	.thumb_func
	.type fn_0802187c, %function
fn_0802187c:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r7, r1
	mov	r5, r0
	movs	r1, #0x4
	mov	r0, r7
	bl	clear_bytes
	cbz	r5, .L08021898
	mov	r0, r5
	bl	fn_08021d60
	cbz	r0, .L0802189e
	b.n	.L080218a4
.L08021898:
	movs	r0, #0x0
.L0802189a:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0802189e:
	ldr	r0, [r5, #0x8]
	cmp	r0, #0x0
	beq.n	.L0802189a
.L080218a4:
	movs	r6, #0x0
	ldr	r0, .L080218d0
	bl	get_word_4_or_zero
	b.n	.L080218c6
.L080218ae:
	ldr	r3, [r4, #0x0]
	cbz	r3, .L080218be
	mov	r2, r7
	mov	r1, r5
	blx	r3
	mov	r6, r0
	cmp	r0, #0x1
	beq.n	.L080218ca
.L080218be:
	mov	r1, r4
	ldr	r0, .L080218d0
	bl	read_word_at_base_plus_offset_4
.L080218c6:
	movs	r4, r0
	bne.n	.L080218ae
.L080218ca:
	mov	r0, r6
	b.n	.L0802189a
	.short	0x0000	@ padding
.L080218d0:
	.word	0x20008098

@ ----------------------------------------------------------------------------
@ fn_080218d4 - fills a 0x28-byte record from a source and a loader entry.
@ Parameters: r0 = record (r4), r1 = source (r6), r2 = halfword value (stack
@ copy at [sp+8]), r3 = word value (r5). Returns 1 on success, else 0.
@ Clears 0x28 bytes of the record. Returns 0 when the source is 0, or when the
@ classification fn_08021d60(source) is 0 and word [source+8] is 0.
@ Stores halfword +8 = r2, byte +0x10 = the class, word +0xc = r3. Class 1
@ copies the name into a new buffer (string_length + 1, fn_08022b50,
@ string_copy) whose pointer goes to word +4 (returns 0 when the allocation
@ fails); other classes store the source pointer at +4.
@ Walks the list at 0x20008098 (get_word_4_or_zero,
@ read_word_at_base_plus_offset_4). For each entry with words +0 and +4 set it
@ calls entry(entry, source, record+0x14); when that returns 1, stores the
@ entry in record word 0 and calls its slot +4 with (entry, record), returning
@ 1 when that returns 1; otherwise it clears the 4 bytes at record+0x14 and
@ the words +0x18, +0x1c, +0x20 and +0x24. When no entry succeeds frees the
@ copied name (class 1) with fn_08022c68 and returns the last result.
@ ----------------------------------------------------------------------------
	.section .text.fn_080218d4,"ax",%progbits
	.p2align 2
	.global fn_080218d4
	.thumb_func
	.type fn_080218d4, %function
fn_080218d4:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, lr}
	mov	r6, r1
	mov	r5, r3
	mov	r4, r0
	movs	r1, #0x28
	bl	clear_bytes
	cbz	r6, .L08021912
	mov	r0, r6
	bl	fn_08021d60
	cbnz	r0, .L080218f2
	ldr	r1, [r6, #0x8]
	cbz	r1, .L08021912
.L080218f2:
	ldrh.w	r1, [sp, #0x8]
	strh	r1, [r4, #0x8]
	strb	r0, [r4, #0x10]
	str	r5, [r4, #0xc]
	cmp	r0, #0x1
	beq.n	.L0802191a
	str	r6, [r4, #0x4]
.L08021902:
	movs	r7, #0x0
	ldr	r0, .L0802198c
	bl	get_word_4_or_zero
	mov	r5, r0
	add.w	r8, r4, #0x14
	b.n	.L08021976
.L08021912:
	movs	r0, #0x0
.L08021914:
	add	sp, #0x10
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0802191a:
	mov	r0, r6
	bl	string_length
	.inst.n	0x1c40	@ adds r0, r0, #1
	bl	fn_08022b50
	str	r0, [r4, #0x4]
	cmp	r0, #0x0
	beq.n	.L08021914
	mov	r1, r6
	bl	string_copy
	b.n	.L08021902
.L08021934:
	ldr	r3, [r5, #0x0]
	cbz	r3, .L0802196c
	ldr	r0, [r5, #0x4]
	cbz	r0, .L0802196c
	mov	r2, r8
	mov	r1, r6
	mov	r0, r5
	blx	r3
	mov	r7, r0
	cmp	r0, #0x1
	bne.n	.L0802196c
	str	r5, [r4, #0x0]
	ldr	r2, [r5, #0x4]
	mov	r1, r4
	mov	r0, r5
	blx	r2
	mov	r7, r0
	cmp	r0, #0x1
	beq.n	.L08021914
	movs	r1, #0x4
	mov	r0, r8
	bl	clear_bytes
	movs	r0, #0x0
	str	r0, [r4, #0x20]
	str	r0, [r4, #0x18]
	str	r0, [r4, #0x24]
	str	r0, [r4, #0x1c]
.L0802196c:
	mov	r1, r5
	ldr	r0, .L0802198c
	bl	read_word_at_base_plus_offset_4
	mov	r5, r0
.L08021976:
	cmp	r5, #0x0
	bne.n	.L08021934
	ldrb	r0, [r4, #0x10]
	cmp	r0, #0x1
	bne.n	.L08021986
	ldr	r0, [r4, #0x4]
	bl	fn_08022c68
.L08021986:
	mov	r0, r7
	b.n	.L08021914
	.short	0x0000	@ padding
.L0802198c:
	.word	0x20008098

@ ----------------------------------------------------------------------------
@ fn_08021990 - calls slot +8 of the table an object's word 0 points to.
@ Parameters: r0 = object whose word 0 points to a table, r1, r2, r3 and the
@ stack argument [sp+0x20] (after the push) forwarded. Returns the slot result
@ in r0, or 0 when the slot is 0.
@ Calls the function at table+8 with (table, object, r1, r2, r3, stack
@ argument) when it is nonzero.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021990,"ax",%progbits
	.global fn_08021990
	.thumb_func
	.type fn_08021990, %function
fn_08021990:
	push.w	{r2, r3, r4, r5, r6, r7, r8, lr}
	ldr	r5, [r0, #0x0]
	mov	r6, r1
	ldr	r7, [sp, #0x20]
	ldr	r4, [r5, #0x8]
	movs	r1, #0x0
	cbz	r4, .L080219b0
	strd	r3, r7, [sp, #0x0]
	mov	r3, r2
	mov	r1, r0
	mov	r2, r6
	mov	r0, r5
	blx	r4
	mov	r1, r0
.L080219b0:
	mov	r0, r1
	pop.w	{r2, r3, r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_080219b6 - frees the block at word [object+0x24] for storage modes 1 and 2.
@ Parameters: r1 = object (r0 is not used). No return value.
@ When (byte [object+0x38] & 3) is 1 or 2: frees word [object+0x24] with
@ fn_08022c68, clears that word, and sets bits 0..1 of byte [object+0x38]
@ (accessed as [word+0x14] after the writeback load of the pointer).
@ ----------------------------------------------------------------------------
	.section .text.fn_080219b6,"ax",%progbits
	.global fn_080219b6
	.thumb_func
	.type fn_080219b6, %function
fn_080219b6:
	push	{r4, lr}
	ldrb.w	r0, [r1, #0x38]
	mov	r4, r1
	and.w	r0, r0, #0x3
	cmp	r0, #1
	beq.n	.L080219ca
	cmp	r0, #2
	bne.n	.L080219de
.L080219ca:
	ldr.w	r0, [r4, #0x24]!
	bl	fn_08022c68
	movs	r0, #0x0
	str	r0, [r4, #0x0]
	ldrb	r0, [r4, #0x14]
	orr.w	r0, r0, #0x3
	strb	r0, [r4, #0x14]
.L080219de:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080219e0 - handles a message for a rectangle object by message type.
@ Parameters: r0 = value returned on the paths that end at the final pop,
@ r1 = message pointer M (kept in r7), r2 and r3 saved and not read. Returns r0
@ unchanged or the result of the tail-called routine.
@ t = get_byte8_low7(M) (r5). When t is neither 0x15 nor 0x18,
@ fn_08023d54(d_0804fd20, M) must return 1, else returns r0.
@ r4 = get_first_word(M) (the object), r6 = 0x100.
@   t = 0x2a: when (byte [r4+0x38] & 3) is 2 tail-calls fn_08021c14(r4, word
@     [r4+0x24]), else tail-calls fn_08025cac(r4).
@   t = 0x13: p = get_word_at_0x10(M); returns when halfword [r4+0x30] is 0 and
@     halfword [r4+0x36] is 0x100. Otherwise w = rect_width_plus_one(r4),
@     h = rect_height_plus_one(r4), fn_080122e0(sp+8, w, h, signed halfword
@     [r4+0x30], stack: halfword [r4+0x36], r4+0x32) fills four signed
@     halfwords out[0..3] at sp+8; the signed halfword [p] becomes
@     max([p], -out[0], -out[1], out[2] - w, out[3] - h).
@   t = 0x11: p = get_word_at_0x10(M); the rectangle is fn_08023dae(r4, sp)
@     when rect_width_plus_one(r4) differs from signed halfword [r4+0x2c], or
@     rect_height_plus_one(r4) differs from signed halfword [r4+0x2e], or when
@     it is not true that halfword [r4+0x36] = 0x100, halfword [r4+0x30] = 0,
@     signed halfword [r4+0x32] = signed halfword [r4+0x2c] / 2 and signed
@     halfword [r4+0x34] = signed halfword [r4+0x2e] / 2 is false (the
@     division is an add of the sign bit and asr #1); otherwise the rectangle
@     is the fn_080122e0 output (sp+8, same arguments as for 0x13) with
@     halfwords 0 and 2 increased by halfword [r4+0x14] and halfwords 1 and 3
@     by halfword [r4+0x16]. Then byte [p+4] = low byte of
@     fn_0801201c(rectangle, word [p], 0).
@   t = 0x2c: p = get_word_at_0x10(M); when (byte [r4+0x39] & 3) is 1 the word
@     [p] = fn_08021bd0(r4), else halfword [p] = halfword [r4+0x2c] and
@     halfword [p+2] = halfword [r4+0x2e].
@   t = 0x15, 0x18 or 0x12: tail-calls fn_08016580(M).
@   any other t returns r0.
@ Returns with pop {r0-r8,pc}. Ends with 2 bytes of padding and the literal
@ d_0804fd20.
@ ----------------------------------------------------------------------------
	.section .text.fn_080219e0,"ax",%progbits
	.p2align 2
	.global fn_080219e0
	.thumb_func
	.type fn_080219e0, %function
fn_080219e0:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, lr}
	mov	r7, r1
	mov	r0, r1
	bl	get_byte8_low7
	mov	r5, r0
	cmp	r0, #0x15
	beq.n	.L08021a02
	cmp	r5, #0x18
	beq.n	.L08021a02
	mov	r1, r7
	ldr	r0, .L08021bcc
	bl	fn_08023d54
	cmp	r0, #0x1
	bne.n	.L08021ad6
.L08021a02:
	mov	r0, r7
	bl	get_first_word
	mov	r4, r0
	cmp	r5, #0x2a
	beq.n	.L08021a36
	mov.w	r6, #0x100
	cmp	r5, #0x13
	beq.n	.L08021a5a
	cmp	r5, #0x11
	beq.n	.L08021ada
	cmp	r5, #0x2c
	beq.n	.L08021b1c
	cmp	r5, #0x15
	beq.n	.L08021a2a
	cmp	r5, #0x18
	beq.n	.L08021a2a
	cmp	r5, #0x12
	bne.n	.L08021ad6
.L08021a2a:
	add	sp, #0x10
	mov	r0, r7
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08016580
.L08021a36:
	ldrb.w	r0, [r4, #0x38]
	and.w	r0, r0, #0x3
	cmp	r0, #2
	mov	r0, r4
	beq.n	.L08021a4e
	add	sp, #0x10
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08025cac
.L08021a4e:
	ldr	r1, [r4, #0x24]
	add	sp, #0x10
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08021c14
.L08021a5a:
	mov	r0, r7
	bl	get_word_at_0x10
	mov	r5, r0
	ldrh	r0, [r4, #0x30]
	cbnz	r0, .L08021a6c
	ldrh	r0, [r4, #0x36]
	cmp	r0, r6
	beq.n	.L08021ad6
.L08021a6c:
	mov	r0, r4
	bl	rect_width_plus_one
	mov	r6, r0
	mov	r0, r4
	bl	rect_height_plus_one
	mov	r7, r0
	add.w	r1, r4, #0x32
	ldrh	r0, [r4, #0x36]
	strd	r0, r1, [sp, #0x0]
	ldrsh.w	r3, [r4, #0x30]
	mov	r2, r7
	mov	r1, r6
	add	r0, sp, #8
	bl	fn_080122e0
	ldrsh.w	r0, [sp, #0x8]
	ldrsh.w	r1, [r5, #0x0]
	rsbs	r0, r0, #0
	cmp	r1, r0
	ble.n	.L08021aa4
	mov	r0, r1
.L08021aa4:
	sxth	r0, r0
	strh	r0, [r5, #0x0]
	ldrsh.w	r1, [sp, #0xa]
	rsbs	r1, r1, #0
	cmp	r0, r1
	bgt.n	.L08021ab4
	mov	r0, r1
.L08021ab4:
	sxth	r0, r0
	strh	r0, [r5, #0x0]
	ldrsh.w	r1, [sp, #0xc]
	subs	r1, r1, r6
	cmp	r0, r1
	bgt.n	.L08021ac4
	mov	r0, r1
.L08021ac4:
	sxth	r0, r0
	strh	r0, [r5, #0x0]
	ldrsh.w	r1, [sp, #0xe]
	subs	r1, r1, r7
	cmp	r0, r1
	bgt.n	.L08021ad4
	mov	r0, r1
.L08021ad4:
	strh	r0, [r5, #0x0]
.L08021ad6:
	pop.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, pc}
.L08021ada:
	mov	r0, r7
	bl	get_word_at_0x10
	mov	r5, r0
	mov	r0, r4
	bl	rect_width_plus_one
	ldrsh.w	r1, [r4, #0x2c]
	cmp	r0, r1
	bne.n	.L08021b8c
	mov	r0, r4
	bl	rect_height_plus_one
	mov	r1, r0
	ldrsh.w	r0, [r4, #0x2e]
	cmp	r1, r0
	bne.n	.L08021b8c
	ldrh	r1, [r4, #0x36]
	cmp	r1, r6
	bne.n	.L08021b2e
	ldrh	r1, [r4, #0x30]
	cbnz	r1, .L08021b2e
	ldrsh.w	r1, [r4, #0x2c]
	ldrsh.w	r2, [r4, #0x32]
	add.w	r1, r1, r1, lsr #31
	cmp.w	r2, r1, asr #1
	b.n	.L08021b1e
.L08021b1c:
	b.n	.L08021ba2
.L08021b1e:
	bne.n	.L08021b2e
	ldrsh.w	r1, [r4, #0x34]
	add.w	r0, r0, r0, lsr #31
	cmp.w	r1, r0, asr #1
	beq.n	.L08021b8c
.L08021b2e:
	mov	r0, r4
	bl	rect_width_plus_one
	mov	r6, r0
	mov	r0, r4
	bl	rect_height_plus_one
	mov	r2, r0
	add.w	r1, r4, #0x32
	ldrh	r0, [r4, #0x36]
	strd	r0, r1, [sp, #0x0]
	ldrsh.w	r3, [r4, #0x30]
	mov	r1, r6
	add	r0, sp, #8
	bl	fn_080122e0
	ldrh.w	r0, [sp, #0x8]
	ldrh	r1, [r4, #0x14]
	movs	r2, #0x0
	add	r0, r1
	strh.w	r0, [sp, #0x8]
	ldrh.w	r0, [sp, #0xa]
	ldrh	r1, [r4, #0x16]
	add	r0, r1
	strh.w	r0, [sp, #0xa]
	ldrh.w	r0, [sp, #0xc]
	ldrh	r1, [r4, #0x14]
	add	r0, r1
	strh.w	r0, [sp, #0xc]
	ldrh.w	r0, [sp, #0xe]
	ldrh	r1, [r4, #0x16]
	add	r0, r1
	strh.w	r0, [sp, #0xe]
	add	r0, sp, #8
	ldr	r1, [r5, #0x0]
	b.n	.L08021b9a
.L08021b8c:
	mov	r1, sp
	mov	r0, r4
	bl	fn_08023dae
	movs	r2, #0x0
	mov	r0, sp
	ldr	r1, [r5, #0x0]
.L08021b9a:
	bl	fn_0801201c
	strb	r0, [r5, #0x4]
	b.n	.L08021ad6
.L08021ba2:
	mov	r0, r7
	bl	get_word_at_0x10
	mov	r5, r0
	ldrb.w	r0, [r4, #0x39]
	and.w	r0, r0, #0x3
	cmp	r0, #1
	beq.n	.L08021bc0
	ldrh	r0, [r4, #0x2c]
	strh	r0, [r5, #0x0]
	ldrh	r0, [r4, #0x2e]
	strh	r0, [r5, #0x2]
	b.n	.L08021ad6
.L08021bc0:
	mov	r0, r4
	bl	fn_08021bd0
	str	r0, [r5, #0x0]
	b.n	.L08021ad6
	.short	0x0000	@ padding
.L08021bcc:
	.word	d_0804fd20
