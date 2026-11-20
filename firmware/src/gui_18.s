@ gui_18.s - GUI module, batch 18: 20 functions at 0x0801c2e8..0x0801d478
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0801c2e8 - walks an object tree and runs a per-object callback.
@ Parameters: r0 = object pointer; no return value.
@ Calls fn_08023da4() for the child count n and recurses over the n child
@ pointers, read as *(word *)(*(word *)(r0 + 8) + i*4).
@ When bit 0 of halfword r0+0x22 is set: clears that bit, calls fn_08025a00(r0)
@ and fn_08025844(r0). When the child count is nonzero and fn_08024a08(r0, 0)
@ = k is nonzero and not above the word at 0x20000468: loads the table pointer
@ from word 0x200004d4, reads the pair at table + k*8 - 8 (function pointer in
@ the first word, argument in the second), restores the registers and jumps
@ to the function pointer with r0 = the object and r1 = the second word of the
@ pair (tail call through bx r2).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c2e8,"ax",%progbits
	.p2align 2
	.global fn_0801c2e8
	.thumb_func
	.type fn_0801c2e8, %function
fn_0801c2e8:
	push	{r4, r5, r6, lr}
	mov	r5, r0
	bl	fn_08023da4
	mov	r6, r0
	movs	r4, #0
	b.n	.L0801c304
.L0801c2f6:
	ldr	r0, [r5, #8]
	ldr	r0, [r0]
	ldr.w	r0, [r0, r4, lsl #2]
	bl	fn_0801c2e8
	.inst.n	0x1c64	@ adds r4, r4, #1
.L0801c304:
	cmp	r4, r6
	blo.n	.L0801c2f6
	ldrh	r0, [r5, #0x22]
	lsls	r1, r0, #31
	beq.n	.L0801c34c
	bic	r0, r0, #1
	strh	r0, [r5, #0x22]
	mov	r0, r5
	bl	fn_08025a00
	mov	r0, r5
	bl	fn_08025844
	cmp	r6, #0
	beq.n	.L0801c34c
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024a08
	cmp	r0, #0
	beq.n	.L0801c34c
	ldr	r1, .L0801c350
	ldr	r1, [r1, #4]
	cmp	r0, r1
	bhi.n	.L0801c34c
	ldr	r1, .L0801c354
	ldr	r1, [r1]
	add.w	r0, r1, r0, lsl #3
	ldrd	r2, r1, [r0, #-8]
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	bx	r2
.L0801c34c:
	pop	{r4, r5, r6, pc}
	.short	0x0000	@ padding
.L0801c350:
	.word	0x20000464
.L0801c354:
	.word	0x200004d4

@ ----------------------------------------------------------------------------
@ fn_0801c358 - anti-aliased coverage of a span on a byte buffer (variant 1).
@ Parameters: r0 = byte buffer, r1 = start offset s, r2 = value v, r3 = length
@ n; fifth argument on the stack ([sp, #32] after the 8-register push) =
@ pointer S to a record (words +0x18, +0x1c, +0x24, byte +0x28). Returns 0, 1
@ or 2 in r0.
@ k = word S+0x1c; a = (k*s) >> 10 and b = ((s+n)*k) >> 10 (arithmetic
@ shifts) are compared with v: k > 0 passes when a <= v and b >= v, k <= 0
@ passes when a >= v and b <= v.
@ Start outside: returns 1 when bit 1 of byte S+0x28 is set, else 0. End
@ outside: returns 0 when bit 1 is set, else 1.
@ Inside: f = sbfx(word S+0x18 * v', bit 2, width 22) with v' = v+1 on the
@ k <= 0 path and v' = v on the k > 0 path (the bge at 0x0801c38e goes to
@ 0x0801c404, which loads word S+0x18 and branches to 0x0801c3a6, past the
@ adds); e = f >> 8 (arithmetic), fr = f & 0xff; m = e - s kept in r4 and r9;
@ w = 255 when fr = 0, else w = 255 - (((255-fr) * word S+0x24) >> 8). When
@ fr = 0 the beq at 0x0801c3ce is taken (the flags of the cmp at 0x0801c3b2
@ survive because the sub.w and mov between do not set flags) and the edge
@ byte is skipped.
@ Edge byte (fr != 0): when 0 <= m < n, byte[r0+m] = scale_value_by_factor_
@ over_255(byte[r0+m], q) with q = 255 - (((255-fr) * (255-w)) >> 9) & 0xff,
@ replaced by 255 - q when bit 1 of byte S+0x28 is set; m is then
@ incremented.
@ Run (loop head 0x0801c43e, body 0x0801c40e..0x0801c43c): while word S+0x24
@ < w (signed), with m < n tested only after each pass and not before the
@ first pass; in each pass when 0 <= m < n, byte[r0+m] = scale_value_by_
@ factor_over_255(byte[r0+m], (w - (S+0x24 >> 1)) & 0xff), complemented by
@ bit 1; then m += 1 and w -= word S+0x24.
@ Last byte: when 0 <= m < n, q = ((((word S+0x18 * w) >> 10) * w) >> 9) &
@ 0xff (ubfx), 255 - q when word S+0x1c < 0, 255 - q again when bit 1 is
@ set, byte[r0+m] = scale_value_by_factor_over_255(byte[r0+m], q).
@ Tail with bit 1 clear: m+1 negative returns 0, m+1 > n returns 2, else
@ clear_bytes(r0+m+1, n-(m+1)) clears the rest and returns 2. Tail with bit
@ 1 set: r9 > n returns 0, r9 < 0 returns 2, else clear_bytes(r0, r9) clears
@ the first r9 bytes and returns 2.
@ Merged pieces: 0x0801c39a is the epilogue (pop r4-r10, pc); 0x0801c490 is
@ b.n 0x0801c496 (no instruction of the function branches to it); 0x0801c496
@ is movs r0,#0 then b 0x0801c39a (return 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c358,"ax",%progbits
	.p2align 2
	.global fn_0801c358
	.thumb_func
	.type fn_0801c358, %function
fn_0801c358:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r8, r0
	ldr	r5, [sp, #0x20]
	mov	r7, r3
	ldr	r0, [r5, #0x1c]
	mul.w	r3, r0, r1
	asrs	r3, r3, #10
	cmp	r0, #0
	ble.n	.L0801c37e
	cmp	r3, r2
	ble.n	.L0801c382
	nop
.L0801c374:
	ldrb.w	r0, [r5, #0x28]
	lsls	r0, r0, #30
	bmi.n	.L0801c398
	b.n	.L0801c496
.L0801c37e:
	cmp	r3, r2
	blt.n	.L0801c374
.L0801c382:
	adds	r3, r1, r7
	muls	r3, r0, r3
	asrs	r3, r3, #10
	cmp	r0, #0
	ble.n	.L0801c39e
	cmp	r3, r2
	bge.n	.L0801c404
.L0801c390:
	ldrb.w	r0, [r5, #0x28]
	lsls	r0, r0, #30
	bmi.n	.L0801c496
.L0801c398:
	movs	r0, #1
.L0801c39a:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L0801c39e:
	cmp	r3, r2
	bgt.n	.L0801c390
	ldr	r0, [r5, #0x18]
	.inst.n	0x1c52	@ adds r2, r2, #1
.L0801c3a6:
	muls	r0, r2, r0
	sbfx	r0, r0, #2, #22
	asrs	r3, r0, #8
	uxtb	r0, r0
	movs	r2, #0xff
	cmp	r0, #0
	beq.n	.L0801c408
	nop
	ldr	r6, [r5, #0x24]
	rsb.w	r4, r0, #0xff
	mul.w	r4, r4, r6
	sub.w	r6, r2, r4, asr #8
	nop
.L0801c3c8:
	sub.w	r4, r3, r1
	mov	r9, r4
	beq.n	.L0801c43e
	cmp	r4, #0
	blt.n	.L0801c400
	cmp	r4, r7
	bge.n	.L0801c400
	rsb.w	r0, r0, #0xff
	rsb.w	r1, r6, #0xff
	muls	r0, r1, r0
	sub.w	r0, r2, r0, asr #9
	uxtb	r1, r0
	ldrb.w	r0, [r5, #0x28]
	lsls	r0, r0, #30
	bpl.n	.L0801c3f4
	rsb.w	r1, r1, #0xff
.L0801c3f4:
	ldrb.w	r0, [r8, r4]
	bl	scale_value_by_factor_over_255
	strb.w	r0, [r8, r4]
.L0801c400:
	.inst.n	0x1c64	@ adds r4, r4, #1
	b.n	.L0801c43e
.L0801c404:
	ldr	r0, [r5, #0x18]
	b.n	.L0801c3a6
.L0801c408:
	mov.w	r6, #0xff
	b.n	.L0801c3c8
.L0801c40e:
	cmp	r4, #0
	blt.n	.L0801c434
	cmp	r4, r7
	bge.n	.L0801c434
	sub.w	r0, r6, r0, asr #1
	uxtb	r1, r0
	ldrb.w	r0, [r5, #0x28]
	lsls	r0, r0, #30
	bpl.n	.L0801c428
	rsb.w	r1, r1, #0xff
.L0801c428:
	ldrb.w	r0, [r8, r4]
	bl	scale_value_by_factor_over_255
	strb.w	r0, [r8, r4]
.L0801c434:
	ldr	r0, [r5, #0x24]
	.inst.n	0x1c64	@ adds r4, r4, #1
	subs	r6, r6, r0
	cmp	r4, r7
	bge.n	.L0801c444
.L0801c43e:
	ldr	r0, [r5, #0x24]
	cmp	r0, r6
	blt.n	.L0801c40e
.L0801c444:
	cmp	r4, r7
	bge.n	.L0801c47a
	cmp	r4, #0
	blt.n	.L0801c47a
	ldr	r0, [r5, #0x18]
	muls	r0, r6, r0
	asrs	r0, r0, #10
	muls	r0, r6, r0
	ubfx	r1, r0, #9, #8
	ldr	r0, [r5, #0x1c]
	cmp	r0, #0
	bge.n	.L0801c462
	rsb.w	r1, r1, #0xff
.L0801c462:
	ldrb.w	r0, [r5, #0x28]
	lsls	r0, r0, #30
	bpl.n	.L0801c46e
	rsb.w	r1, r1, #0xff
.L0801c46e:
	ldrb.w	r0, [r8, r4]
	bl	scale_value_by_factor_over_255
	strb.w	r0, [r8, r4]
.L0801c47a:
	ldrb.w	r0, [r5, #0x28]
	lsls	r0, r0, #30
	bpl.n	.L0801c492
	mov	r1, r9
	cmp	r9, r7
	bgt.n	.L0801c496
	cmp	r1, #0
	blt.n	.L0801c4a8
	mov	r0, r8
	b.n	.L0801c4a4
	b.n	.L0801c496
.L0801c492:
	.inst.n	0x1c64	@ adds r4, r4, #1
	bpl.n	.L0801c49a
.L0801c496:
	movs	r0, #0
	b.n	.L0801c39a
.L0801c49a:
	cmp	r4, r7
	bgt.n	.L0801c4a8
	subs	r1, r7, r4
	add.w	r0, r8, r4
.L0801c4a4:
	bl	clear_bytes
.L0801c4a8:
	movs	r0, #2
	b.n	.L0801c39a

@ ----------------------------------------------------------------------------
@ fn_0801c4ac - anti-aliased coverage of a line crossing on a byte buffer
@ (variant 2).
@ Parameters: r0 = byte buffer, r1 = start offset, r2 = position index, r3 =
@ length; stack word ([sp, #0x28] after the 10-register push) = pointer to a
@ structure (words at +0x18, +0x1c, byte at +0x28). Returns 0, 1 or 2 in r0.
@ Computes p = word +0x18 * r2 >> 10 as the line position (p+1 when word
@ +0x18 is positive for the start test) and returns early (1 or 0, chosen by
@ bit 1 of byte +0x28) when it lies outside r1..r1+r3.
@ Computes the sub-pixel parts of positions r2 and r2+1 (word*256 >> 10 &
@ 0xff) and writes 1 to 3 partial-coverage bytes through scale_value_by_
@ factor_over_255(old, new) at buffer index position - r1 (and +1, -1),
@ complemented 0xff - value when bit 1 of byte +0x28 is set.
@ Clears the remaining run with clear_bytes(buf + index, count).
@ Returns 2 after writing; the shared exits are 0x0801c67a (returns 2),
@ 0x0801c680 (returns 0) and 0x0801c5ec (returns 1), all ending in the pop
@ at 0x0801c5ee.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c4ac,"ax",%progbits
	.p2align 2
	.global fn_0801c4ac
	.thumb_func
	.type fn_0801c4ac, %function
fn_0801c4ac:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	mov	r6, r0
	ldr	r7, [sp, #0x28]
	mov	r10, r1
	mov	r5, r3
	ldr	r0, [r7, #0x18]
	mul.w	r1, r0, r2
	asrs	r4, r1, #10
	cmp	r0, #0
	ble.n	.L0801c4c6
	.inst.n	0x1c64	@ adds r4, r4, #1
.L0801c4c6:
	ldrb.w	r3, [r7, #0x28]
	cmp	r4, r10
	bge.n	.L0801c4d4
	lsls	r0, r3, #30
	bmi.n	.L0801c4e2
	b.n	.L0801c680
.L0801c4d4:
	asrs	r4, r1, #10
	add.w	r12, r10, r5
	cmp	r12, r4
	bge.n	.L0801c4e4
	lsls	r0, r3, #30
	bmi.n	.L0801c5e0
.L0801c4e2:
	b.n	.L0801c5ec
.L0801c4e4:
	.inst.n	0x1c52	@ adds r2, r2, #1
	muls	r2, r0, r2
	sbfx	r1, r1, #2, #22
	sbfx	r4, r2, #2, #22
	asr.w	r9, r1, #8
	asrs	r2, r4, #8
	and.w	r8, r4, #0xff
	uxtb	r1, r1
	sub.w	r4, r9, r10
	cmp	r9, r2
	beq.n	.L0801c510
	cmp	r0, #0
	bge.n	.L0801c510
	cbnz	r1, .L0801c510
	movs	r1, #0xff
	mov	r9, r2
	.inst.n	0x1e64	@ subs r4, r4, #1
.L0801c510:
	cmp	r9, r2
	bne.n	.L0801c566
	cmp	r4, #0
	blt.n	.L0801c532
	cmp	r4, r5
	bge.n	.L0801c532
	add.w	r0, r1, r8
	lsrs	r1, r0, #1
	lsls	r0, r3, #30
	bpl.n	.L0801c52a
	rsb.w	r1, r1, #0xff
.L0801c52a:
	ldrb	r0, [r6, r4]
	bl	scale_value_by_factor_over_255
	strb	r0, [r6, r4]
.L0801c532:
	ldrb.w	r0, [r7, #0x28]
	.inst.n	0x1c64	@ adds r4, r4, #1
	lsls	r0, r0, #30
	bpl.n	.L0801c54a
	sub.w	r1, r9, r10
	cmp	r1, r5
	bge.n	.L0801c5e0
	b.n	.L0801c664
.L0801c546:
	mov	r0, r6
	b.n	.L0801c560
.L0801c54a:
	cmp	r4, r5
	ble.n	.L0801c550
	mov	r4, r5
.L0801c550:
	cmp	r4, #0
	beq.n	.L0801c5e0
	ble.n	.L0801c564
	nop
.L0801c558:
	sub.w	r1, r5, r4
	add.w	r0, r6, r4
.L0801c560:
	bl	clear_bytes
.L0801c564:
	b.n	.L0801c67a
.L0801c566:
	mov.w	r11, #0xff
	cmp	r0, #0
	bge.n	.L0801c5f8
	ldr	r0, [r7, #0x1c]
	rsbs	r0, r0, #0
	muls	r0, r1, r0
	asr.w	r8, r0, #10
	cmp	r4, #0
	blt.n	.L0801c598
	cmp	r4, r5
	bge.n	.L0801c598
	mul.w	r0, r8, r1
	ubfx	r1, r0, #9, #8
	lsls	r0, r3, #30
	bpl.n	.L0801c590
	rsb.w	r1, r1, #0xff
.L0801c590:
	ldrb	r0, [r6, r4]
	bl	scale_value_by_factor_over_255
	strb	r0, [r6, r4]
.L0801c598:
	ldr	r1, [r7, #0x18]
	sub.w	r0, r8, #0xff
	muls	r1, r0, r1
	asrs	r0, r1, #10
	.inst.n	0x1e64	@ subs r4, r4, #1
	bmi.n	.L0801c5ca
	cmp	r4, r5
	bge.n	.L0801c5ca
	rsb.w	r1, r8, #0xff
	muls	r1, r0, r1
	sub.w	r0, r11, r1, asr #9
	uxtb	r1, r0
	ldrb.w	r0, [r7, #0x28]
	lsls	r0, r0, #30
	bpl.n	.L0801c5c2
	rsb.w	r1, r1, #0xff
.L0801c5c2:
	ldrb	r0, [r6, r4]
	bl	scale_value_by_factor_over_255
	strb	r0, [r6, r4]
.L0801c5ca:
	ldrb.w	r0, [r7, #0x28]
	.inst.n	0x1ca4	@ adds r4, r4, #2
	lsls	r0, r0, #30
	bpl.n	.L0801c5e8
	sub.w	r1, r9, r10
	.inst.n	0x1e49	@ subs r1, r1, #1
	cmp	r1, r5
	bgt.n	.L0801c67a
	b.n	.L0801c5e2
.L0801c5e0:
	b.n	.L0801c680
.L0801c5e2:
	cmp	r1, #0
	bgt.n	.L0801c546
	b.n	.L0801c67a
.L0801c5e8:
	cmp	r4, r5
	ble.n	.L0801c5f2
.L0801c5ec:
	movs	r0, #1
.L0801c5ee:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}
.L0801c5f2:
	cmp	r4, #0
	bge.n	.L0801c558
	b.n	.L0801c67a
.L0801c5f8:
	rsb.w	r0, r1, #0xff
	ldr	r1, [r7, #0x1c]
	muls	r1, r0, r1
	asr.w	r8, r1, #10
	cmp	r4, #0
	blt.n	.L0801c626
	cmp	r4, r5
	bge.n	.L0801c626
	mul.w	r0, r0, r8
	sub.w	r0, r11, r0, asr #9
	uxtb	r1, r0
	lsls	r0, r3, #30
	bpl.n	.L0801c61e
	rsb.w	r1, r1, #0xff
.L0801c61e:
	ldrb	r0, [r6, r4]
	bl	scale_value_by_factor_over_255
	strb	r0, [r6, r4]
.L0801c626:
	ldr	r1, [r7, #0x18]
	rsb.w	r0, r8, #0xff
	muls	r1, r0, r1
	asrs	r1, r1, #10
	.inst.n	0x1c64	@ adds r4, r4, #1
	bmi.n	.L0801c652
	cmp	r4, r5
	bge.n	.L0801c652
	muls	r0, r1, r0
	ubfx	r1, r0, #9, #8
	ldrb.w	r0, [r7, #0x28]
	lsls	r0, r0, #30
	bpl.n	.L0801c64a
	rsb.w	r1, r1, #0xff
.L0801c64a:
	ldrb	r0, [r6, r4]
	bl	scale_value_by_factor_over_255
	strb	r0, [r6, r4]
.L0801c652:
	ldrb.w	r0, [r7, #0x28]
	.inst.n	0x1c64	@ adds r4, r4, #1
	lsls	r0, r0, #30
	bpl.n	.L0801c66c
	sub.w	r1, r9, r10
	cmp	r1, r5
	bgt.n	.L0801c680
.L0801c664:
	cmp	r1, #0
	bge.w	.L0801c546
	b.n	.L0801c67a
.L0801c66c:
	cmp	r4, r5
	ble.n	.L0801c672
	mov	r4, r5
.L0801c672:
	cmp	r4, #0
	beq.n	.L0801c680
	bgt.w	.L0801c558
.L0801c67a:
	mov.w	r0, #2
	b.n	.L0801c5ee
.L0801c680:
	mov.w	r0, #0
	b.n	.L0801c5ee
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_0801c688 - removes the entries with matching keys from the list at
@ 0x20008080.
@ Parameters: r0 = key 1, r1 = key 2 (0 matches any). Returns 1 in r0 when at
@ least one entry was removed, else 0.
@ Walks the list at 0x20008080 with get_word_4_or_zero (first entry) and
@ read_word_at_base_plus_offset_4 (next entry, read before the entry can be
@ freed). Entries whose word +0 equals r0 (or r0 = 0) and whose word +4 equals
@ r1 (or r1 = 0) are removed with fn_080126a2(list, entry); the function
@ pointer at word +0x10 is then called with the entry when it is nonzero;
@ fn_08022c68(entry) frees it and fn_08013594() is called.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c688,"ax",%progbits
	.p2align 2
	.global fn_0801c688
	.thumb_func
	.type fn_0801c688, %function
fn_0801c688:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r7, r0
	mov	r8, r1
	movs	r6, #0
	ldr	r0, .L0801c6e4
	bl	get_word_4_or_zero
	mov	r4, r0
	b.n	.L0801c6d8
.L0801c69c:
	mov	r1, r4
	ldr	r0, .L0801c6e4
	bl	read_word_at_base_plus_offset_4
	mov	r5, r0
	ldr	r0, [r4]
	cmp	r0, r7
	beq.n	.L0801c6ae
	cbnz	r7, .L0801c6d6
.L0801c6ae:
	ldr	r1, [r4, #4]
	cmp	r1, r8
	beq.n	.L0801c6ba
	cmp.w	r8, #0
	bne.n	.L0801c6d6
.L0801c6ba:
	mov	r1, r4
	ldr	r0, .L0801c6e4
	bl	fn_080126a2
	ldr	r1, [r4, #0x10]
	cbz	r1, .L0801c6ca
	mov	r0, r4
	blx	r1
.L0801c6ca:
	mov	r0, r4
	bl	fn_08022c68
	bl	fn_08013594
	movs	r6, #1
.L0801c6d6:
	mov	r4, r5
.L0801c6d8:
	cmp	r4, #0
	bne.n	.L0801c69c
	mov	r0, r6
	pop.w	{r4, r5, r6, r7, r8, pc}
	.short	0x0000	@ padding
.L0801c6e4:
	.word	0x20008080

@ ----------------------------------------------------------------------------
@ fn_0801c6e8 - looks up an entry in the list at 0x20008080.
@ Parameters: r0 = key 1, r1 = key 2; changes nothing in the list.
@ Walks the list at 0x20008080 with get_word_4_or_zero (first entry) and
@ read_word_at_base_plus_offset_4 (next entry) until an entry has word +0
@ equal to r0 and (word +4 equal to r1 or r1 = 0).
@ Returns the found entry pointer in r0 (the pop at 0x0801c712 runs with r0 =
@ the entry), or 0 when the list is exhausted.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c6e8,"ax",%progbits
	.p2align 2
	.global fn_0801c6e8
	.thumb_func
	.type fn_0801c6e8, %function
fn_0801c6e8:
	push	{r4, r5, r6, lr}
	mov	r5, r0
	mov	r4, r1
	ldr	r0, .L0801c714
	bl	get_word_4_or_zero
	b.n	.L0801c70e
.L0801c6f6:
	ldr	r1, [r0]
	cmp	r1, r5
	bne.n	.L0801c706
	ldr	r1, [r0, #4]
	cmp	r1, r4
	beq.n	.L0801c712
	cmp	r4, #0
	beq.n	.L0801c712
.L0801c706:
	mov	r1, r0
	ldr	r0, .L0801c714
	bl	read_word_at_base_plus_offset_4
.L0801c70e:
	cmp	r0, #0
	bne.n	.L0801c6f6
.L0801c712:
	pop	{r4, r5, r6, pc}
.L0801c714:
	.word	0x20008080

@ ----------------------------------------------------------------------------
@ fn_0801c718 - initialises a 0x44-byte entry template.
@ Parameters: r0 = pointer to a 0x44-byte structure.
@ Clears 0x44 bytes with clear_bytes, then sets word +0x2c = 500, word +0x20
@ = 0, word +0x28 = 100, halfword +0x40 = 1, word +0x1c = 0x0801c781
@ (function pointer to fn_0801c780) and sets bit 0 of byte +0x42.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c718,"ax",%progbits
	.p2align 2
	.global fn_0801c718
	.thumb_func
	.type fn_0801c718, %function
fn_0801c718:
	push	{r4, lr}
	mov	r4, r0
	movs	r1, #0x44
	bl	clear_bytes
	mov.w	r0, #0x1f4
	str	r0, [r4, #0x2c]
	movs	r0, #0
	str	r0, [r4, #0x20]
	movs	r0, #0x64
	str	r0, [r4, #0x28]
	movs	r0, #1
	strh.w	r0, [r4, #0x40]
	ldr	r0, .L0801c748
	str	r0, [r4, #0x1c]
	ldrb.w	r0, [r4, #0x42]
	orr	r0, r0, #1
	strb.w	r0, [r4, #0x42]
	pop	{r4, pc}
.L0801c748:
	.word	fn_0801c780

@ ----------------------------------------------------------------------------
@ fn_0801c74c - eased interpolation between two values of an entry.
@ Parameters: r0 = pointer to a structure (words at +0x20, +0x28, +0x2c,
@ +0x30). Returns an integer in r0.
@ t = fn_08022b12(word +0x30, 0, word +0x2c, 0, 0x400)
@ e = cubic_bezier_fixed10(t, 0, 900, 0x3b6, 0x400)
@ Returns word +0x20 + (e * (word +0x28 - word +0x20) >> 10).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c74c,"ax",%progbits
	.p2align 2
	.global fn_0801c74c
	.thumb_func
	.type fn_0801c74c, %function
fn_0801c74c:
	push	{r3, r4, r5, lr}
	mov	r4, r0
	mov.w	r5, #0x400
	str	r5, [sp]
	ldrd	r2, r0, [r4, #0x2c]
	movs	r3, #0
	mov	r1, r3
	bl	fn_08022b12
	movw	r3, #0x3b6
	mov.w	r2, #0x384
	movs	r1, #0
	str	r5, [sp]
	bl	cubic_bezier_fixed10
	ldr	r2, [r4, #0x20]
	ldr	r1, [r4, #0x28]
	subs	r1, r1, r2
	muls	r1, r0, r1
	add.w	r0, r2, r1, asr #10
	pop	{r3, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_0801c780 - linear interpolation between two values of an entry.
@ Parameters: r0 = pointer to a structure (words at +0x20, +0x28, +0x2c,
@ +0x30). Returns an integer in r0.
@ t = fn_08022b12(word +0x30, 0, word +0x2c, 0, 0x400)
@ Returns word +0x20 + (t * (word +0x28 - word +0x20) >> 10).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c780,"ax",%progbits
	.p2align 2
	.global fn_0801c780
	.thumb_func
	.type fn_0801c780, %function
fn_0801c780:
	push	{r3, r4, r5, lr}
	mov	r4, r0
	mov.w	r0, #0x400
	str	r0, [sp]
	ldrd	r2, r0, [r4, #0x2c]
	movs	r3, #0
	mov	r1, r3
	bl	fn_08022b12
	ldr	r2, [r4, #0x20]
	ldr	r1, [r4, #0x28]
	subs	r1, r1, r2
	muls	r1, r0, r1
	add.w	r0, r2, r1, asr #10
	pop	{r3, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_0801c7a4 - scaled absolute difference divided by a divisor.
@ Parameters: r0 = divisor, r1 and r2 = values. Returns an unsigned integer in
@ r0: d = |r1 - r2|, result = d*1000 / r0 (unsigned division), or 1 when that
@ is 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c7a4,"ax",%progbits
	.p2align 2
	.global fn_0801c7a4
	.thumb_func
	.type fn_0801c7a4, %function
fn_0801c7a4:
	subs	r3, r1, r2
	cmp	r3, #0
	bgt.n	.L0801c7ac
	subs	r3, r2, r1
.L0801c7ac:
	mov.w	r1, #0x3e8
	muls	r3, r1, r3
	udiv	r0, r3, r0
	cmp	r0, #0
	bne.n	.L0801c7bc
	movs	r0, #1
.L0801c7bc:
	bx	lr
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_0801c7c0 - adds an entry to the list at 0x20008080.
@ Parameters: r0 = pointer to a 0x44-byte template. Returns the pointer to the
@ new entry in r0, or 0.
@ When word r0+4 is nonzero, removes matching entries with fn_0801c688(word
@ r0, word r0+4) (r1 keeps word r0+4 from 0x0801c7c2).
@ When fn_08012690(0x20008080) is nonzero, stores fn_080277a0() to word
@ 0x200004c0. Gets a new entry from fn_08012618(0x20008080) and copies 0x44
@ bytes from the template with copy_bytes_08022ce0; a first word equal to the
@ template pointer is replaced with the entry pointer.
@ Copies bit 0 of byte 0x200004bd to bit 2 of byte +0x42.
@ When bit 0 of byte +0x42 was set: calls the function pointer at word +0x14
@ (when nonzero) and adds its result to words +0x20 and +0x28; then calls the
@ pointer at word +4 with (word +0, word +0x20) when both are nonzero.
@ Calls fn_08013594() and returns the entry.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c7c0,"ax",%progbits
	.p2align 2
	.global fn_0801c7c0
	.thumb_func
	.type fn_0801c7c0, %function
fn_0801c7c0:
	push	{r4, r5, r6, lr}
	ldr	r1, [r0, #4]
	mov	r5, r0
	cbz	r1, .L0801c7ce
	ldr	r0, [r5]
	bl	fn_0801c688
.L0801c7ce:
	ldr	r0, .L0801c834
	bl	fn_08012690
	ldr	r6, .L0801c838
	cbz	r0, .L0801c7de
	bl	fn_080277a0
	str	r0, [r6, #4]
.L0801c7de:
	ldr	r0, .L0801c834
	bl	fn_08012618
	subs	r4, r0, #0
	beq.n	.L0801c830
	movs	r2, #0x44
	mov	r1, r5
	bl	copy_bytes_08022ce0
	ldr	r0, [r5]
	cmp	r0, r5
	bne.n	.L0801c7f8
	str	r4, [r4]
.L0801c7f8:
	ldrb	r1, [r6, #1]
	ldrb.w	r0, [r4, #0x42]
	bfi	r0, r1, #2, #1
	strb.w	r0, [r4, #0x42]
	lsls	r0, r0, #31
	beq.n	.L0801c82a
	ldr	r1, [r4, #0x14]
	cbz	r1, .L0801c81e
	mov	r0, r4
	blx	r1
	ldr	r1, [r4, #0x20]
	add	r1, r0
	str	r1, [r4, #0x20]
	ldr	r1, [r4, #0x28]
	add	r0, r1
	str	r0, [r4, #0x28]
.L0801c81e:
	ldr	r2, [r4, #4]
	cbz	r2, .L0801c82a
	ldr	r0, [r4]
	cbz	r0, .L0801c82a
	ldr	r1, [r4, #0x20]
	blx	r2
.L0801c82a:
	bl	fn_08013594
	mov	r0, r4
.L0801c830:
	pop	{r4, r5, r6, pc}
	.short	0x0000	@ padding
.L0801c834:
	.word	0x20008080
.L0801c838:
	.word	0x200004bc

@ ----------------------------------------------------------------------------
@ fn_0801c83c - initialises the geometry fields of an object and finishes
@ through fn_08026306.
@ Parameters: r0 unused (overwritten with 0 at 0x0801c83e), r1 = object
@ pointer (kept in r4). Ends with a tail jump to fn_08026306(r0 = object, r1 =
@ 0x0e), so it returns to the caller from there.
@ Halfword stores: [r4+0x24] = 0, +0x2a = 0x87, +0x2c = 0x2d, +0x26 = 0x87,
@ +0x28 = 0x10e (0x87 << 1), +0x2e = 0x8000, +0x30 = 0, +0x32 = 100, +0x36 =
@ 0x2d0 (0x2d << 4).
@ Halfword +0x34: bits 1 and 2 cleared; the reloaded value gets bit 3 set and
@ bit 0 cleared and is stored.
@ Word +0x38 = fn_080277a0(); halfword +0x3c = halfword +0x28.
@ Calls fn_08023050(object, 2) and fn_08023558(object, 0x310), then pops r4
@ and lr, sets r1 = 0x0e and branches (b.w) to fn_08026306.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c83c,"ax",%progbits
	.p2align 2
	.global fn_0801c83c
	.thumb_func
	.type fn_0801c83c, %function
fn_0801c83c:
	push	{r4, lr}
	movs	r0, #0
	mov	r4, r1
	strh	r0, [r1, #0x24]
	movs	r1, #0x87
	strh	r1, [r4, #0x2a]
	movs	r2, #0x2d
	strh	r2, [r4, #0x2c]
	strh	r1, [r4, #0x26]
	lsls	r1, r1, #1
	strh	r1, [r4, #0x28]
	ldrh	r1, [r4, #0x34]
	bic	r1, r1, #6
	strh	r1, [r4, #0x34]
	mov.w	r1, #0x8000
	strh	r1, [r4, #0x2e]
	ldrh	r1, [r4, #0x34]
	strh	r0, [r4, #0x30]
	movs	r0, #0x64
	orr	r1, r1, #8
	strh	r0, [r4, #0x32]
	uxth	r0, r1
	bic	r0, r0, #1
	strh	r0, [r4, #0x34]
	lsls	r0, r2, #4
	strh	r0, [r4, #0x36]
	bl	fn_080277a0
	str	r0, [r4, #0x38]
	ldrh	r0, [r4, #0x28]
	strh	r0, [r4, #0x3c]
	movs	r1, #2
	mov	r0, r4
	bl	fn_08023050
	mov.w	r1, #0x310
	mov	r0, r4
	bl	fn_08023558
	mov	r0, r4
	pop.w	{r4, lr}
	movs	r1, #0xe
	b.w	fn_08026306

@ ----------------------------------------------------------------------------
@ fn_0801c8a0 - draws the three parts of a message's object (two optional
@ strips and a final part).
@ Parameters: r0 = message (kept in r4); no return value.
@ Body 0x0801c8a0..0x0801ca57 (push of r4-r11 and lr, sub sp, #0xbc; pop at
@ 0x0801ca54); the literal at 0x0801ca58 holds the address 0x08050f4c (kept in
@ r8). Reached only by the b.w at 0x0801caaa in fn_0801ca5c.
@ r7 = get_first_word(msg) (object); word [sp+0xa8] =
@ get_word_10_if_byte_8_14_to_19(msg); calls fn_0801b0ae(r7, sp+0xb0,
@ sp+0xa0); fn_08023a0c(sp+0x18, [sp+0xa8]); r10 = sp+0xb0, r11 = sp+8.
@ Part 1 (0x0801c8c8-0x0801c934), only when ldrsh [sp+0xa0] > 0:
@ fn_0801de00(sp+8); fn_08024eda(r7, 0, sp+8); record at sp+0x18: word
@ [sp+0x3c] = sp+0xb0, word [sp+0x4c] = 0, word [sp+0x1c] = 0x08050f4c, word
@ [sp+0x20] = 0 (mode), halfword [sp+0x54] = halfword [sp+0xa0], word [sp+0x38]
@ = sp+8; calls fn_080207f4(r7, 0x1a, sp+0x18), then fn_0801dde0([sp+0xa8],
@ sp+8, sp+0xb0, halfword [sp+0x54], stack [sp+0] = uxth(h[r7+0x24] +
@ h[r7+0x2a]), [sp+4] = uxth(h[r7+0x24] + h[r7+0x2c])), then
@ fn_080207f4(r7, 0x1b, sp+0x18).
@ Part 2 (0x0801c938-0x0801ca00): r9 = 0x20000; m = signed maximum of
@ fn_08024b04, fn_08024b40, fn_08024b94 and fn_08024aa4, each called with (r7,
@ 0x20000) (compare chain 0x0801c962-0x0801c98a); x = sxth(halfword [sp+0xa0]
@ - m); only when x > 0: fn_0801de00(sp+8); fn_08024eda(r7, 0x20000, sp+8);
@ the record as in part 1 but word [sp+0x4c] = 0x20000, word [sp+0x20] = 1,
@ halfword [sp+0x54] = x; fn_080207f4(r7, 0x1a, sp+0x18); halfword [sp+0xa] =
@ min(ldrsh [sp+0xa], x) (stores x when ldrsh [sp+0xa] is greater than x: cmp
@ r1,r0 at 0x0801c9d0, ble skip at 0x0801c9d2, strh at 0x0801c9d4);
@ fn_0801dde0([sp+0xa8], sp+8, sp+0xb0, halfword [sp+0x54], stack [sp+0] =
@ uxth(h[r7+0x24] + h[r7+0x26]), [sp+4] = uxth(h[r7+0x28] + h[r7+0x24]));
@ fn_080207f4(r7, 0x1b, sp+0x18).
@ Part 3 (0x0801ca02-0x0801ca52): fn_0801b378(r7, sp+0xb0, ldrsh [sp+0xa0],
@ sp+0xb4); fn_0801f344(sp+0x60); fn_0802516e(r7, 0x30000, sp+0x60); word
@ [sp+0x4c] = 0x30000, word [sp+0x20] = 2, word [sp+0x24] = sp+0xb4, word
@ [sp+0x28] = sp+0x60; fn_080207f4(r7, 0x1a, sp+0x18); fn_0801f31c([sp+0xa8],
@ sp+0x60, sp+0xb4); fn_080207f4(r7, 0x1b, sp+0x18); returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c8a0,"ax",%progbits
	.p2align 2
	.global fn_0801c8a0
	.thumb_func
	.type fn_0801c8a0, %function
fn_0801c8a0:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0xbc
	mov	r4, r0
	bl	get_first_word
	mov	r7, r0
	mov	r0, r4
	bl	get_word_10_if_byte_8_14_to_19
	str	r0, [sp, #0xa8]
	add	r2, sp, #0xa0
	add	r1, sp, #0xb0
	mov	r0, r7
	bl	fn_0801b0ae
	add	r0, sp, #0x18
	ldr	r1, [sp, #0xa8]
	bl	fn_08023a0c
	ldrsh.w	r0, [sp, #0xa0]
	ldr.w	r8, .L0801ca58
	add.w	r10, sp, #0xb0
	add.w	r11, sp, #8
	cmp	r0, #0
	ble.n	.L0801c938
	mov	r0, r11
	bl	fn_0801de00
	add	r2, sp, #8
	movs	r1, #0
	mov	r0, r7
	bl	fn_08024eda
	movs	r0, #0
	str.w	r10, [sp, #0x3c]
	str	r0, [sp, #0x4c]
	strd	r8, r0, [sp, #0x1c]
	ldrh.w	r0, [sp, #0xa0]
	strh.w	r0, [sp, #0x54]
	add	r2, sp, #0x18
	movs	r1, #0x1a
	mov	r0, r7
	str.w	r11, [sp, #0x38]
	bl	fn_080207f4
	ldrh	r1, [r7, #0x2c]
	ldrh	r0, [r7, #0x24]
	ldrh	r2, [r7, #0x2a]
	add	r1, r0
	add	r0, r2
	uxth	r1, r1
	uxth	r0, r0
	strd	r0, r1, [sp]
	ldrh.w	r3, [sp, #0x54]
	add	r2, sp, #0xb0
	add	r1, sp, #8
	ldr	r0, [sp, #0xa8]
	bl	fn_0801dde0
	add	r2, sp, #0x18
	movs	r1, #0x1b
	mov	r0, r7
	bl	fn_080207f4
.L0801c938:
	mov.w	r9, #0x20000
	mov	r1, r9
	mov	r0, r7
	bl	fn_08024b04
	mov	r6, r0
	mov	r1, r9
	mov	r0, r7
	bl	fn_08024b40
	mov	r5, r0
	mov	r1, r9
	mov	r0, r7
	bl	fn_08024b94
	mov	r4, r0
	mov	r1, r9
	mov	r0, r7
	bl	fn_08024aa4
	cmp	r6, r5
	ble.n	.L0801c96a
	mov	r1, r6
	b.n	.L0801c96c
.L0801c96a:
	mov	r1, r5
.L0801c96c:
	cmp	r4, r0
	ble.n	.L0801c974
	mov	r2, r4
	b.n	.L0801c976
.L0801c974:
	mov	r2, r0
.L0801c976:
	cmp	r1, r2
	ble.n	.L0801c986
	cmp	r6, r5
	ble.n	.L0801c982
	mov	r0, r6
	b.n	.L0801c98c
.L0801c982:
	mov	r0, r5
	b.n	.L0801c98c
.L0801c986:
	cmp	r4, r0
	ble.n	.L0801c98c
	mov	r0, r4
.L0801c98c:
	ldrh.w	r1, [sp, #0xa0]
	subs	r0, r1, r0
	sxth	r4, r0
	cmp	r4, #0
	ble.n	.L0801ca02
	add	r0, sp, #8
	bl	fn_0801de00
	add	r2, sp, #8
	mov	r5, r9
	mov	r1, r9
	mov	r0, r7
	bl	fn_08024eda
	movs	r0, #1
	str.w	r10, [sp, #0x3c]
	str	r5, [sp, #0x4c]
	strd	r8, r0, [sp, #0x1c]
	strh.w	r4, [sp, #0x54]
	add	r2, sp, #0x18
	movs	r1, #0x1a
	mov	r0, r7
	str.w	r11, [sp, #0x38]
	bl	fn_080207f4
	ldrsh.w	r1, [sp, #0xa]
	ldrsh.w	r0, [sp, #0x54]
	cmp	r1, r0
	ble.n	.L0801c9d8
	strh.w	r0, [sp, #0xa]
.L0801c9d8:
	ldrh	r1, [r7, #0x28]
	ldrh	r0, [r7, #0x24]
	ldrh	r2, [r7, #0x26]
	add	r1, r0
	add	r0, r2
	uxth	r1, r1
	uxth	r0, r0
	strd	r0, r1, [sp]
	ldrh.w	r3, [sp, #0x54]
	add	r2, sp, #0xb0
	add	r1, sp, #8
	ldr	r0, [sp, #0xa8]
	bl	fn_0801dde0
	add	r2, sp, #0x18
	movs	r1, #0x1b
	mov	r0, r7
	bl	fn_080207f4
.L0801ca02:
	add	r3, sp, #0xb4
	ldrsh.w	r2, [sp, #0xa0]
	add	r1, sp, #0xb0
	mov	r0, r7
	bl	fn_0801b378
	add	r0, sp, #0x60
	bl	fn_0801f344
	mov.w	r4, #0x30000
	add	r2, sp, #0x60
	mov	r1, r4
	mov	r0, r7
	bl	fn_0802516e
	movs	r0, #2
	str	r4, [sp, #0x4c]
	strd	r8, r0, [sp, #0x1c]
	add	r0, sp, #0xb4
	str	r0, [sp, #0x24]
	add	r0, sp, #0x60
	str	r0, [sp, #0x28]
	add	r2, sp, #0x18
	movs	r1, #0x1a
	mov	r0, r7
	bl	fn_080207f4
	add	r2, sp, #0xb4
	add	r1, sp, #0x60
	ldr	r0, [sp, #0xa8]
	bl	fn_0801f31c
	add	r2, sp, #0x18
	movs	r1, #0x1b
	mov	r0, r7
	bl	fn_080207f4
	add	sp, #0xbc
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801ca58:
	.word	d_08050f4c

@ ----------------------------------------------------------------------------
@ fn_0801ca5c - message handler of an object (dispatch on the message code).
@ Parameters: r0 not read, r1 = message (kept in r10); no return value.
@ Body 0x0801ca5c..0x0801ce41 and 0x0801ce48..0x0801ce69 (0x0801ce42 is
@ padding, the literal at 0x0801ce44 holds 0x08050f4c); fn_0801c8a0 and
@ fn_08021124 are separate functions reached by tail calls.
@ Returns at once when fn_08023d54(0x08050f4c) is not 1. r6 =
@ get_byte8_low7(msg) (code); r5 = get_first_word(msg) and r4 =
@ get_first_word(msg) (two identical calls, the object).
@ Dispatch: 2 -> 0x0801caae; 8 and 3 -> 0x0801cca4; 0xd -> 0x0801ccd8; 0x11 ->
@ 0x0801cd20; 0x13 -> 0x0801cda2; 0x15 -> add sp, r0 = msg, pop, then tail
@ call of fn_0801c8a0 (b.w at 0x0801caaa); any other code returns.
@ Code 2 (0x0801caae): r6 = read_word_200004ac() must be non-zero and
@ fn_08021e06() must equal 1, else return; fn_08021db0(r6, sp+4);
@ fn_0801b0ae(r5, sp+8, sp+0xc); halfword [sp+4] -= [sp+8], halfword [sp+6]
@ -= [sp+0xa].
@ Code 2 with bit 0 of byte [r4+0x34] clear (0x0801caec): r6 = fn_080248fa(r5,
@ 0x20000); halfword [sp+0xc] -= r6; when all_flag_bits_set(r5, 0x10000) is
@ non-zero r6 is kept, otherwise r6 = min(r6, signed halfword [sp+0xc] / 4
@ toward zero); halfword [sp+0xc] = max(1, signed [sp+0xc] - r6); when
@ [sp+4]^2 + [sp+6]^2 (smulbb, smlabb) is above [sp+0xc]^2 (compare at
@ 0x0801cb58) sets bit 0 of halfword [r4+0x34] and word [r4+0x38] =
@ fn_080277a0(); when bit 0 is still clear returns (0x0801cb76).
@ Code 2 tracking (0x0801cb7e, also entered directly when bit 0 was already
@ set): returns when signed [sp+4] and halfword [sp+6] are both 0. r6 =
@ ldrsh [r4+0x2c], plus 0x168 when halfword [r4+0x2c] is below halfword
@ [r4+0x2a] (unsigned); a = sxth(fn_0801d0d8(ldrsh [sp+6], ldrsh [sp+4]) -
@ h[r4+0x24] - h[r4+0x2a]), plus 0x168 when negative; c = sxth(r6 -
@ h[r4+0x2a]); r8 = sxth(h[r4+0x3c] - h[r4+0x2a]).
@ When sxth(a - r8) + 0x118 is above 0x230 (unsigned, cmp.w at 0x0801cbd0):
@ a = 0 if bit 3 of byte [r4+0x34] is set, else a = c; otherwise bit 3 of
@ halfword [r4+0x34] is set when a < c/2 (c + sign bit, asr 1) and cleared
@ else. r7 = sxth(a - r8), limited to -L..L with L = sxth(udiv(h[r4+0x36] *
@ ticks_since(word [r4+0x38]), 1000)).
@ Code 2 result: v = sxth(fn_08022b12(r0 = sxth(r8 + r7 + ((((r6 -
@ h[r4+0x2a]) << 3) sdiv (ldrsh [r4+0x32] - ldrsh [r4+0x30]) + 4) asr 4) +
@ h[r4+0x2a]), r1 = h[r4+0x2a], r2 = r6, r3 = ldrsh [r4+0x30], stack [sp+0] =
@ ldrsh [r4+0x32])); old = ldrsh [r4+0x2e] was read before the call. When
@ ldrsh [r5+0x2e] differs from v: word [r4+0x38] = fn_080277a0(),
@ set_value_halfword_2e_clamped(r5, v), and when v differs from old
@ fn_080207f4(r5, 0x1c, 0) must return 1 to continue (0x0801cc84). Then (also
@ when ldrsh [r5+0x2e] equalled v) when ldrsh [r4+0x30] or ldrsh [r4+0x32]
@ equals v word [r4+0x38] = fn_080277a0().
@ Codes 8 and 3 (0x0801cca4): halfword [r4+0x34] &= ~1; r5 = fn_08023f18(r5);
@ r4 = fn_08021048(); calls read_word_200004ac(); requires fn_08021e06() = 4
@ and r4 non-zero, then pops and tail-calls fn_08021124(r5, 0) (b.w at
@ 0x0801ccd4).
@ Code 0xd (0x0801ccd8): key = byte [get_word_at_0x10(msg)], r6 = ldrsh
@ [r4+0x2e]; keys 0x13 and 0x11 call set_value_halfword_2e_clamped(r5,
@ sxth(h[r5+0x2e] + 1)), keys 0x14 and 0x12 call it with sxth(h[r5+0x2e] -
@ 1); when ldrsh [r4+0x2e] differs from r6, pops and tail-calls
@ fn_080207f4(r5, 0x1c, 0) (b.w at 0x0801cd1c), else returns.
@ Code 0x11 (0x0801cd20): rec = r4 = get_word_at_0x10(msg); fn_0801b0ae(r5,
@ sp+0xc, sp+0x10); r6 = ldrsh [[r5+8]+0x14] (0 when word [r5+8] is 0); r5 =
@ fn_080248fa(r5, 0); d = h[sp+0x10] - (r5 + r6); rect_set(sp+4, sxth(h[sp+0xc]
@ - d), sxth(h[sp+0xe] - d), sxth(h[sp+0xc] + d), stack [sp+0] =
@ sxth(h[sp+0xe] + d)); r0 = fn_0801201c(sp+4, word [rec], 0x7fff): when
@ non-zero byte [rec+4] = 0, else v = sxth(r5 + 2*r6), rect_grow(sp+4, v, v),
@ byte [rec+4] = fn_0801201c(sp+4, word [rec], 0x7fff).
@ Code 0x13 (0x0801cda2): m0 = signed maximum of fn_08024b04, fn_08024b40,
@ fn_08024b94 and fn_08024aa4, each called with (r5, 0); m3 = the maximum of
@ the same four called with (r5, 0x30000); halfword [get_word_at_0x10(msg)] =
@ max(ldrsh old, sxth(m3 + 2) - m0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ca5c,"ax",%progbits
	.global fn_0801ca5c
	.thumb_func
	.type fn_0801ca5c, %function
fn_0801ca5c:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	sub	sp, #0x18
	mov	r10, r1
	.inst.n	0x48f7	@ ldr r0, .L0801ce44
	bl	fn_08023d54
	cmp	r0, #1
	bne.n	.L0801cb6c
	mov	r0, r10
	bl	get_byte8_low7
	mov	r6, r0
	mov	r0, r10
	bl	get_first_word
	mov	r5, r0
	mov	r0, r10
	bl	get_first_word
	mov	r4, r0
	cmp	r6, #2
	beq.n	.L0801caae
	cmp	r6, #8
.L0801ca8c:
	beq.n	.L0801cb6e
	cmp	r6, #3
	beq.n	.L0801ca8c
	cmp	r6, #0xd
	beq.n	.L0801cb70
	cmp	r6, #0x11
	beq.n	.L0801cb72
	cmp	r6, #0x13
	beq.n	.L0801cb74
	cmp	r6, #0x15
	bne.n	.L0801cb6c
	add	sp, #0x18
	mov	r0, r10
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	b.w	fn_0801c8a0
.L0801caae:
	bl	read_word_200004ac
	movs	r6, r0
	beq.n	.L0801cb6c
	bl	fn_08021e06
	cmp	r0, #1
	bne.n	.L0801cb6c
	add	r1, sp, #4
	mov	r0, r6
	bl	fn_08021db0
	add	r2, sp, #0xc
	add	r1, sp, #8
	mov	r0, r5
	bl	fn_0801b0ae
	ldrh.w	r0, [sp, #4]
	ldrh.w	r1, [sp, #8]
	subs	r0, r0, r1
	strh.w	r0, [sp, #4]
	ldrh.w	r0, [sp, #6]
	ldrh.w	r1, [sp, #0xa]
	subs	r0, r0, r1
	strh.w	r0, [sp, #6]
	ldrb.w	r0, [r4, #0x34]
	lsls	r0, r0, #31
	bne.n	.L0801cb7e
	mov.w	r1, #0x20000
	mov	r0, r5
	bl	fn_080248fa
	mov	r6, r0
	ldrh.w	r0, [sp, #0xc]
	mov.w	r1, #0x10000
	subs	r0, r0, r6
	strh.w	r0, [sp, #0xc]
	mov	r0, r5
	bl	all_flag_bits_set
	cbz	r0, .L0801cb1c
	ldrh.w	r0, [sp, #0xc]
	b.n	.L0801cb2e
.L0801cb1c:
	ldrsh.w	r0, [sp, #0xc]
	asrs	r1, r0, #31
	add.w	r1, r0, r1, lsr #30
	cmp.w	r6, r1, asr #2
	bge.n	.L0801cb2e
	asrs	r6, r1, #2
.L0801cb2e:
	subs	r0, r0, r6
	strh.w	r0, [sp, #0xc]
	sxth	r0, r0
	cmp	r0, #1
	bge.n	.L0801cb40
	movs	r0, #1
	strh.w	r0, [sp, #0xc]
.L0801cb40:
	ldrh.w	r0, [sp, #4]
	smulbb	r1, r0, r0
	ldrh.w	r0, [sp, #6]
	smlabb	r0, r0, r0, r1
	ldrh.w	r1, [sp, #0xc]
	smulbb	r1, r1, r1
	cmp	r0, r1
	ble.n	.L0801cb6a
	ldrh	r0, [r4, #0x34]
	orr	r0, r0, #1
	strh	r0, [r4, #0x34]
	bl	fn_080277a0
	str	r0, [r4, #0x38]
.L0801cb6a:
	b.n	.L0801cb76
.L0801cb6c:
	b.n	.L0801cc7c
.L0801cb6e:
	b.n	.L0801cca4
.L0801cb70:
	b.n	.L0801ccd8
.L0801cb72:
	b.n	.L0801cd20
.L0801cb74:
	b.n	.L0801cda2
.L0801cb76:
	ldrb.w	r0, [r4, #0x34]
	lsls	r0, r0, #31
	beq.n	.L0801cc7c
.L0801cb7e:
	ldrsh.w	r1, [sp, #4]
	cbnz	r1, .L0801cb8c
	ldrh.w	r0, [sp, #6]
	cmp	r0, #0
	beq.n	.L0801cc7c
.L0801cb8c:
	ldrsh.w	r6, [r4, #0x2c]
	ldrh	r2, [r4, #0x2a]
	uxth	r0, r6
	cmp	r0, r2
	bhs.n	.L0801cb9e
	add.w	r0, r0, #0x168
	sxth	r6, r0
.L0801cb9e:
	ldrsh.w	r0, [sp, #6]
	bl	fn_0801d0d8
	ldrh	r1, [r4, #0x24]
	ldrh	r2, [r4, #0x2a]
	subs	r0, r0, r1
	subs	r0, r0, r2
	sxth	r0, r0
	cmp	r0, #0
	bge.n	.L0801cbba
	add.w	r0, r0, #0x168
	sxth	r0, r0
.L0801cbba:
	subs	r1, r6, r2
	ldrh	r3, [r4, #0x3c]
	sxth	r1, r1
	subs	r2, r3, r2
	sxth.w	r8, r2
	sub.w	r2, r0, r8
	sxth	r2, r2
	add.w	r2, r2, #0x118
	cmp.w	r2, #0x230
	bls.n	.L0801cbe6
	ldrb.w	r0, [r4, #0x34]
	lsls	r0, r0, #28
	bpl.n	.L0801cbe2
	movs	r0, #0
	b.n	.L0801cbfe
.L0801cbe2:
	mov	r0, r1
	b.n	.L0801cbfe
.L0801cbe6:
	add.w	r1, r1, r1, lsr #31
	cmp.w	r0, r1, asr #1
	ldrh	r1, [r4, #0x34]
	bge.n	.L0801cbf8
	orr	r1, r1, #8
	b.n	.L0801cbfc
.L0801cbf8:
	bic	r1, r1, #8
.L0801cbfc:
	strh	r1, [r4, #0x34]
.L0801cbfe:
	sub.w	r0, r0, r8
	sxth	r7, r0
	ldr	r0, [r4, #0x38]
	bl	ticks_since
	ldrh	r1, [r4, #0x36]
	muls	r1, r0, r1
	mov.w	r0, #0x3e8
	udiv	r0, r1, r0
	sxth	r0, r0
	cmp	r7, r0
	ble.n	.L0801cc20
	mov	r7, r0
	b.n	.L0801cc28
.L0801cc20:
	rsbs	r0, r0, #0
	cmp	r7, r0
	bge.n	.L0801cc28
	sxth	r7, r0
.L0801cc28:
	ldrh	r1, [r4, #0x2a]
	ldrsh.w	r2, [r4, #0x32]
	ldrsh.w	r3, [r4, #0x30]
	add.w	r0, r8, r7
	sub.w	r12, r6, r1
	subs	r7, r2, r3
	lsl.w	r12, r12, #3
	sdiv	r7, r12, r7
	.inst.n	0x1d3f	@ adds r7, r7, #4
	add.w	r0, r0, r7, asr #4
	ldrsh.w	r7, [r4, #0x2e]
	add	r0, r1
	str	r2, [sp]
	sxth	r0, r0
	mov	r2, r6
	bl	fn_08022b12
	sxth	r6, r0
	ldrsh.w	r0, [r5, #0x2e]
	cmp	r0, r6
	beq.n	.L0801cc88
	bl	fn_080277a0
	str	r0, [r4, #0x38]
	mov	r1, r6
	mov	r0, r5
	bl	set_value_halfword_2e_clamped
	cmp	r6, r7
	beq.n	.L0801cc88
	movs	r2, #0
	movs	r1, #0x1c
	b.n	.L0801cc7e
.L0801cc7c:
	b.n	.L0801cc9e
.L0801cc7e:
	mov	r0, r5
	bl	fn_080207f4
	cmp	r0, #1
	bne.n	.L0801cc9e
.L0801cc88:
	ldrsh.w	r0, [r4, #0x30]
	cmp	r0, r6
	beq.n	.L0801cc98
	ldrsh.w	r0, [r4, #0x32]
	cmp	r0, r6
	bne.n	.L0801cc9e
.L0801cc98:
	bl	fn_080277a0
	str	r0, [r4, #0x38]
.L0801cc9e:
	add	sp, #0x18
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L0801cca4:
	ldrh	r0, [r4, #0x34]
	bic	r0, r0, #1
	strh	r0, [r4, #0x34]
	mov	r0, r5
	bl	fn_08023f18
	mov	r5, r0
	bl	fn_08021048
	mov	r4, r0
	bl	read_word_200004ac
	bl	fn_08021e06
	cmp	r0, #4
	bne.n	.L0801cc9e
	cmp	r4, #0
	beq.n	.L0801cc9e
	add	sp, #0x18
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	movs	r1, #0
	b.w	fn_08021124
.L0801ccd8:
	mov	r0, r10
	bl	get_word_at_0x10
	ldrb	r0, [r0]
	ldrsh.w	r6, [r4, #0x2e]
	cmp	r0, #0x13
	beq.n	.L0801ccf6
	cmp	r0, #0x11
	beq.n	.L0801ccf6
	cmp	r0, #0x14
	beq.n	.L0801ccfc
	cmp	r0, #0x12
	beq.n	.L0801ccfc
	b.n	.L0801cd08
.L0801ccf6:
	ldrh	r0, [r5, #0x2e]
	.inst.n	0x1c40	@ adds r0, r0, #1
	b.n	.L0801cd00
.L0801ccfc:
	ldrh	r0, [r5, #0x2e]
	.inst.n	0x1e40	@ subs r0, r0, #1
.L0801cd00:
	sxth	r1, r0
	mov	r0, r5
	bl	set_value_halfword_2e_clamped
.L0801cd08:
	ldrsh.w	r0, [r4, #0x2e]
	cmp	r0, r6
	beq.n	.L0801cc9e
	add	sp, #0x18
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	movs	r2, #0
	movs	r1, #0x1c
	b.w	fn_080207f4
.L0801cd20:
	mov	r0, r10
	bl	get_word_at_0x10
	mov	r4, r0
	add	r2, sp, #0x10
	add	r1, sp, #0xc
	mov	r0, r5
	bl	fn_0801b0ae
	ldr	r0, [r5, #8]
	movs	r6, #0
	cbz	r0, .L0801cd3c
	ldrsh.w	r6, [r0, #0x14]
.L0801cd3c:
	movs	r1, #0
	mov	r0, r5
	bl	fn_080248fa
	mov	r5, r0
	ldrh.w	r1, [sp, #0x10]
	add	r0, r6
	subs	r0, r1, r0
	ldrh.w	r2, [sp, #0xe]
	strh.w	r0, [sp, #0x10]
	adds	r1, r2, r0
	sxth	r1, r1
	str	r1, [sp]
	ldrh.w	r1, [sp, #0xc]
	subs	r2, r2, r0
	adds	r3, r1, r0
	subs	r0, r1, r0
	sxth	r1, r0
	sxth	r3, r3
	sxth	r2, r2
	add	r0, sp, #4
	bl	rect_set
	movw	r7, #0x7fff
	mov	r2, r7
	add	r0, sp, #4
	ldr	r1, [r4]
	bl	fn_0801201c
	cbz	r0, .L0801cd86
	movs	r0, #0
	b.n	.L0801cd9e
.L0801cd86:
	add.w	r0, r5, r6, lsl #1
	sxth	r2, r0
	mov	r1, r2
	add	r0, sp, #4
	bl	rect_grow
	mov	r2, r7
	add	r0, sp, #4
	ldr	r1, [r4]
	bl	fn_0801201c
.L0801cd9e:
	strb	r0, [r4, #4]
	b.n	.L0801cc9e
.L0801cda2:
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024b04
	mov	r7, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024b40
	mov	r6, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024b94
	mov	r4, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024aa4
	cmp	r7, r6
	ble.n	.L0801cdd0
	mov	r1, r7
	b.n	.L0801cdd2
.L0801cdd0:
	mov	r1, r6
.L0801cdd2:
	cmp	r4, r0
	ble.n	.L0801cdda
	mov	r2, r4
	b.n	.L0801cddc
.L0801cdda:
	mov	r2, r0
.L0801cddc:
	cmp	r1, r2
	ble.n	.L0801cdec
	cmp	r7, r6
	ble.n	.L0801cde8
	mov	r0, r7
	b.n	.L0801cdf2
.L0801cde8:
	mov	r0, r6
	b.n	.L0801cdf2
.L0801cdec:
	cmp	r4, r0
	ble.n	.L0801cdf2
	mov	r0, r4
.L0801cdf2:
	mov	r8, r0
	mov.w	r9, #0x30000
	mov	r1, r9
	mov	r0, r5
	bl	fn_08024b04
	mov	r4, r0
	mov	r1, r9
	mov	r0, r5
	bl	fn_08024b40
	mov	r7, r0
	mov	r1, r9
	mov	r0, r5
	bl	fn_08024b94
	mov	r6, r0
	mov	r1, r9
	mov	r0, r5
	bl	fn_08024aa4
	cmp	r4, r7
	ble.n	.L0801ce26
	mov	r1, r4
	b.n	.L0801ce28
.L0801ce26:
	mov	r1, r7
.L0801ce28:
	cmp	r6, r0
	ble.n	.L0801ce30
	mov	r2, r6
	b.n	.L0801ce32
.L0801ce30:
	mov	r2, r0
.L0801ce32:
	cmp	r1, r2
	ble.n	.L0801ce48
	cmp	r4, r7
	ble.n	.L0801ce3e
	mov	r0, r4
	b.n	.L0801ce4e
.L0801ce3e:
	mov	r0, r7
	b.n	.L0801ce4e
	.short	0x0000	@ padding
.L0801ce44:
	.word	d_08050f4c
.L0801ce48:
	cmp	r6, r0
	ble.n	.L0801ce4e
	mov	r0, r6
.L0801ce4e:
	.inst.n	0x1c80	@ adds r0, r0, #2
	sxth	r4, r0
	mov	r0, r10
	bl	get_word_at_0x10
	ldrsh.w	r1, [r0]
	sub.w	r2, r4, r8
	cmp	r1, r2
	bgt.n	.L0801ce66
	mov	r1, r2
.L0801ce66:
	strh	r1, [r0]
	b.n	.L0801cc9e

@ ----------------------------------------------------------------------------
@ fn_0801ce6a - sets both angle fields of an object.
@ Parameters: r0 = object, r1 = value for the second call, r2 = value for the
@ first call; no return value.
@ Calls fn_0801ce82(r0, r2), then pops and tail-calls fn_0801cef4(r0, r1)
@ (b.w).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ce6a,"ax",%progbits
	.global fn_0801ce6a
	.thumb_func
	.type fn_0801ce6a, %function
fn_0801ce6a:
	push	{r4, r5, r6, lr}
	mov	r4, r1
	mov	r5, r0
	mov	r1, r2
	bl	fn_0801ce82
	mov	r1, r4
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0801cef4

@ ----------------------------------------------------------------------------
@ fn_0801ce82 - sets the end angle (halfword +0x28) of an object and
@ redraws the changed arc.
@ Parameters: r0 = object pointer, r1 = angle in degrees; no return value.
@ Values above 0x168 (360) are reduced by 0x168.
@ Compares the angle against halfword +0x28 relative to halfword +0x26 (modulo
@ 0x168); when the difference is within 0xb4 either side calls
@ fn_0801bc0c(obj, from, to, 0x20000), otherwise fn_08025400(obj).
@ Then fn_0801bcae(obj), stores halfword +0x28 = angle, then tail-calls
@ fn_0801bcae(obj) again.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ce82,"ax",%progbits
	.global fn_0801ce82
	.thumb_func
	.type fn_0801ce82, %function
fn_0801ce82:
	push	{r4, r5, r6, lr}
	mov.w	r3, #0x168
	mov	r5, r0
	mov	r4, r1
	cmp	r1, r3
	bls.n	.L0801ce96
	sub.w	r4, r1, #0x168
	uxth	r4, r4
.L0801ce96:
	ldrh	r0, [r5, #0x28]
	ldrh	r1, [r5, #0x26]
	subs	r2, r0, r1
	subs	r1, r4, r1
	sxth	r2, r2
	sxth	r1, r1
	cmp	r2, #0
	bge.n	.L0801ceac
	add.w	r2, r2, #0x168
	sxth	r2, r2
.L0801ceac:
	cmp	r1, #0
	bge.n	.L0801ceb6
	add.w	r1, r1, #0x168
	sxth	r1, r1
.L0801ceb6:
	subs	r6, r1, r2
	adds	r6, #0xb4
	cmp	r6, r3
	bls.n	.L0801cec6
	mov	r0, r5
	bl	fn_08025400
	b.n	.L0801cee2
.L0801cec6:
	mov.w	r3, #0x20000
	cmp	r1, r2
	bge.n	.L0801ced4
	mov	r2, r0
	mov	r1, r4
	b.n	.L0801cedc
.L0801ced4:
	cmp	r2, r1
	bge.n	.L0801cee2
	mov	r2, r4
	mov	r1, r0
.L0801cedc:
	mov	r0, r5
	bl	fn_0801bc0c
.L0801cee2:
	mov	r0, r5
	bl	fn_0801bcae
	mov	r0, r5
	strh	r4, [r5, #0x28]
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0801bcae

@ ----------------------------------------------------------------------------
@ fn_0801cef4 - sets the start angle (halfword +0x26) of an object and
@ redraws the changed arc.
@ Parameters: r0 = object pointer, r1 = angle in degrees; no return value.
@ Values above 0x168 (360) are reduced by 0x168.
@ Compares the angle against halfword +0x26 relative to halfword +0x28 (modulo
@ 0x168); when the difference is within 0xb4 either side calls
@ fn_0801bc0c(obj, from, to, 0x20000), otherwise fn_08025400(obj).
@ Then fn_0801bcae(obj), stores halfword +0x26 = angle, then tail-calls
@ fn_0801bcae(obj) again.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801cef4,"ax",%progbits
	.global fn_0801cef4
	.thumb_func
	.type fn_0801cef4, %function
fn_0801cef4:
	push	{r4, r5, r6, lr}
	mov.w	r3, #0x168
	mov	r5, r0
	mov	r4, r1
	cmp	r1, r3
	bls.n	.L0801cf08
	sub.w	r4, r1, #0x168
	uxth	r4, r4
.L0801cf08:
	ldrh	r1, [r5, #0x28]
	ldrh	r0, [r5, #0x26]
	subs	r2, r1, r0
	subs	r1, r1, r4
	sxth	r2, r2
	sxth	r1, r1
	cmp	r2, #0
	bge.n	.L0801cf1e
	add.w	r2, r2, #0x168
	sxth	r2, r2
.L0801cf1e:
	cmp	r1, #0
	bge.n	.L0801cf28
	add.w	r1, r1, #0x168
	sxth	r1, r1
.L0801cf28:
	subs	r6, r1, r2
	adds	r6, #0xb4
	cmp	r6, r3
	bls.n	.L0801cf38
	mov	r0, r5
	bl	fn_08025400
	b.n	.L0801cf54
.L0801cf38:
	mov.w	r3, #0x20000
	cmp	r1, r2
	bge.n	.L0801cf46
	mov	r2, r4
	mov	r1, r0
	b.n	.L0801cf4e
.L0801cf46:
	cmp	r2, r1
	bge.n	.L0801cf54
	mov	r2, r0
	mov	r1, r4
.L0801cf4e:
	mov	r0, r5
	bl	fn_0801bc0c
.L0801cf54:
	mov	r0, r5
	bl	fn_0801bcae
	mov	r0, r5
	strh	r4, [r5, #0x26]
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0801bcae

@ ----------------------------------------------------------------------------
@ set_value_halfword_2e_clamped - stores a clamped value to halfword +0x2e.
@ Parameters: r0 = object, r1 = new value (compared as a full register); no
@ return value.
@ r3 = int16 [r0+0x2e]; equal to r1 returns (bx lr at 0x0801cf8c). r1 =
@ min(r1, int16 [r0+0x32]) (signed); r1 = max(r1, int16 [r0+0x30]). When r3
@ equals the clamped r1 returns; else halfword [r0+0x2e] = r1 and b.w to
@ fn_0802add2(r0) (tail call).
@ ----------------------------------------------------------------------------
	.section .text.set_value_halfword_2e_clamped,"ax",%progbits
	.global set_value_halfword_2e_clamped
	.thumb_func
	.type set_value_halfword_2e_clamped, %function
set_value_halfword_2e_clamped:
	ldrsh.w	r3, [r0, #0x2e]
	cmp	r3, r1
	beq.n	.L0801cf8c
	ldrsh.w	r2, [r0, #0x32]
	cmp	r2, r1
	bge.n	.L0801cf78
	mov	r1, r2
.L0801cf78:
	ldrsh.w	r2, [r0, #0x30]
	cmp	r2, r1
	ble.n	.L0801cf82
	mov	r1, r2
.L0801cf82:
	cmp	r3, r1
	beq.n	.L0801cf8c
	strh	r1, [r0, #0x2e]
	b.w	fn_0802add2
.L0801cf8c:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801d1b8 - initialises the two lists and the default fields of an object.
@ Parameters: r0 unused, r1 = object pointer (kept in r4); no return value.
@ Calls init_header_aligned4(obj+0x24, 0x10) and init_header_aligned4(obj+0x30,
@ 0x10).
@ Writes halfwords +0x6c = 0, +0x74 = 0, +0x6e = 0, +0x76 = 0, +0x70 = 100,
@ +0x78 = 100, +0x72 = 100, +0x7a = 100, +0x7e = 3, +0x80 = 5, +0x82 = 10,
@ +0x7c = 0x7fff, +0x84 = 0x100, +0x86 = 0x100 (r4 is advanced by 0x6c with
@ the pre-indexed first store, so the later offsets are relative to obj+0x6c).
@ Byte +0x88 = ((byte & ~7) + 1) & ~8.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801d1b8,"ax",%progbits
	.p2align 2
	.global fn_0801d1b8
	.thumb_func
	.type fn_0801d1b8, %function
fn_0801d1b8:
	push	{r4, lr}
	mov	r4, r1
	movs	r1, #0x10
	add.w	r0, r4, #0x24
	bl	init_header_aligned4
	movs	r1, #0x10
	add.w	r0, r4, #0x30
	bl	init_header_aligned4
	movs	r0, #0
	strh.w	r0, [r4, #0x6c]!
	strh	r0, [r4, #8]
	strh	r0, [r4, #2]
	strh	r0, [r4, #0xa]
	movs	r0, #0x64
	strh	r0, [r4, #4]
	strh	r0, [r4, #0xc]
	strh	r0, [r4, #6]
	strh	r0, [r4, #0xe]
	movs	r0, #3
	strh	r0, [r4, #0x12]
	movs	r0, #5
	strh	r0, [r4, #0x14]
	movs	r0, #0xa
	strh	r0, [r4, #0x16]
	movw	r0, #0x7fff
	strh	r0, [r4, #0x10]
	ldrb	r0, [r4, #0x1c]
	bic	r0, r0, #7
	.inst.n	0x1c40	@ adds r0, r0, #1
	bic	r0, r0, #8
	strb	r0, [r4, #0x1c]
	mov.w	r0, #0x100
	strh	r0, [r4, #0x18]
	strh	r0, [r4, #0x1a]
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0801d210 - empties and frees the two lists of an object.
@ Parameters: r0 unused, r1 = object pointer (kept in r4); no return value.
@ While word +0x28 is nonzero: get_word_4_or_zero(obj+0x24) takes the first
@ list entry, fn_08022c68 frees the pointer in its word +4 when bit 2 of byte
@ +0xc is clear, fn_080126a2 removes the entry, fn_08022c68 frees the entry.
@ Then calls fn_080125a2(obj+0x24).
@ While word +0x34 is nonzero: get_word_4_or_zero(obj+0x30) takes the first
@ entry, fn_080126a2 removes it, fn_08022c68 frees it.
@ Finally pops and tail-calls fn_080125a2(obj+0x30) (b.w at 0x0801d270).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801d210,"ax",%progbits
	.p2align 2
	.global fn_0801d210
	.thumb_func
	.type fn_0801d210, %function
fn_0801d210:
	push	{r4, r5, r6, lr}
	mov	r4, r1
	add.w	r6, r1, #0x24
	b.n	.L0801d23c
	nop	@ padding
.L0801d21c:
	bl	get_word_4_or_zero
	mov	r5, r0
	ldrb	r0, [r0, #0xc]
	lsls	r0, r0, #29
	bmi.n	.L0801d22e
	ldr	r0, [r5, #4]
	bl	fn_08022c68
.L0801d22e:
	mov	r1, r5
	mov	r0, r6
	bl	fn_080126a2
	mov	r0, r5
	bl	fn_08022c68
.L0801d23c:
	ldr	r0, [r4, #0x28]
	cmp	r0, #0
	mov	r0, r6
	bne.n	.L0801d21c
	bl	fn_080125a2
	add.w	r5, r4, #0x30
	b.n	.L0801d264
	nop	@ padding
.L0801d250:
	bl	get_word_4_or_zero
	mov	r6, r0
	mov	r1, r0
	mov	r0, r5
	bl	fn_080126a2
	mov	r0, r6
	bl	fn_08022c68
.L0801d264:
	ldr	r0, [r4, #0x34]
	cmp	r0, #0
	mov	r0, r5
	bne.n	.L0801d250
	pop.w	{r4, r5, r6, lr}
	b.w	fn_080125a2

@ ----------------------------------------------------------------------------
@ fn_0801d274 - message handler of an object (dispatch on the message code).
@ Parameters: r1 = message pointer (copied to r5); r3 is saved by the push of
@ r3-r7 and lr and restored by the pops (used by code 0x13); r0 and r2 are not
@ read; no return value except through the tail jumps.
@ fn_08023d54(r0 = 0x08050f14, r1 = message): a result other than 1 returns
@ (0x0801d36c -> pop at 0x0801d3aa).
@ r6 = code = get_byte8_low7(message); r4 = object = get_first_word(message)
@ (also left in r0). Dispatch by compare chain: 1, 8, 0x29, 0x13, 0x2c, 0x15;
@ any other code returns.
@ Code 1 (0x0801d2f2): fn_08021db0(r0 = read_word_200004ac(), r1 = sp) stores
@ a halfword at [sp]; [sp] = [sp] - halfword [r4+0x14]; r6 = fn_08024070(obj)
@ + zero-extended [sp] (32-bit add); r7 = bits 8..23 of (fn_08023e7c(obj) *
@ halfword [obj+0x84]) sign-extended (sbfx at 0x0801d322); r0 = sxth(r6 -
@ fn_08024af8(obj, 0)); r6 = 0; r0 < 0 (signed) keeps r6 = 0; r0 > r7
@ (signed) gives r6 = halfword [obj+0x82] - 1; otherwise by byte [obj+0x88]
@ AND 7: 1 gives r6 = (((halfword [obj+0x82] - 1) * r0) + ((r7 + (r7 >> 31
@ logical)) >> 1 arithmetic)) / r7 (sdiv), 2 gives r6 = (halfword [obj+0x82]
@ * r0) / r7 (sdiv), other values keep r6 = 0. r6 equal to int16 [obj+0x7c]
@ returns; else fn_0801bcd2(obj, uxth(r6)), fn_0801bcd2(obj, halfword
@ [obj+0x7c]), halfword [obj+0x7c] = r6, fn_080207f4(obj, 0x1c, 0).
@ Code 8 (0x0801d3ac): fn_0801bcd2(obj, halfword [obj+0x7c]), then halfword
@ [obj+0x7c] = 0x7fff.
@ Code 0x29 (0x0801d3bc): pop r3-r7 and lr; b.w fn_08025d04 with r0 = obj.
@ Code 0x13 (0x0801d3c4): r1 = largest (signed) of the halfwords [obj+0x40],
@ +0x4c, +0x58, +0x64 (0x0801d3c8..0x0801d3fe); r2 = int16 [obj+0x40]; pop
@ r3-r7 and lr; b.w fn_08020834 with r0 = message, r1 = largest, r2 = int16
@ [obj+0x40], r3 = the value received.
@ Code 0x2c (0x0801d40a): r5 = get_word_at_0x10(message); halfword [r5] =
@ (fn_08023e7c(obj) * halfword [obj+0x84]) >> 8 (asrs); halfword [r5+2] =
@ (fn_08023e48(obj) * halfword [obj+0x86]) >> 8.
@ Code 0x15 (0x0801d2aa): r5 = get_word_10_if_byte_8_14_to_19(message);
@ fn_0801631c(obj, r5); fn_0801a0a0(obj, r5, 0); fn_0801a0a0(obj, r5, 1);
@ fn_08019d70(obj, r5, 2); fn_08019d70(obj, r5, 4); fn_08012690(obj+0x24):
@ nonzero goes to 0x0801d466, zero to 0x0801d434, which by byte [obj+0x88]
@ AND 7 calls 1: fn_080185ec(obj, r5), 2: fn_080183b0(obj, r5), 3:
@ fn_08018a20(obj, r5), other values call nothing.
@ 0x0801d466: r1 = r5, r0 = obj, pop r3-r7 and lr, b.w fn_08016100 (tail call
@ with r0 = obj, r1 = r5).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801d274,"ax",%progbits
	.p2align 2
	.global fn_0801d274
	.thumb_func
	.type fn_0801d274, %function
fn_0801d274:
	push	{r3, r4, r5, r6, r7, lr}
	mov	r5, r1
	ldr	r0, .L0801d474
	bl	fn_08023d54
	cmp	r0, #1
	bne.n	.L0801d36c
	mov	r0, r5
	bl	get_byte8_low7
	mov	r6, r0
	mov	r0, r5
	bl	get_first_word
	mov	r4, r0
	cmp	r6, #1
	beq.n	.L0801d2f2
	cmp	r6, #8
	beq.n	.L0801d36e
	cmp	r6, #0x29
	beq.n	.L0801d370
	cmp	r6, #0x13
	beq.n	.L0801d372
	cmp	r6, #0x2c
	beq.n	.L0801d3a4
	cmp	r6, #0x15
	bne.n	.L0801d3aa
	mov	r0, r5
	bl	get_word_10_if_byte_8_14_to_19
	mov	r5, r0
	mov	r1, r0
	mov	r0, r4
	bl	fn_0801631c
	mov	r6, r4
	movs	r2, #0
	mov	r1, r5
	mov	r0, r4
	bl	fn_0801a0a0
	movs	r2, #1
	mov	r1, r5
	mov	r0, r6
	bl	fn_0801a0a0
	movs	r2, #2
	mov	r1, r5
	mov	r0, r6
	bl	fn_08019d70
	movs	r2, #4
	mov	r1, r5
	mov	r0, r6
	bl	fn_08019d70
	add.w	r0, r4, #0x24
	bl	fn_08012690
	cmp	r0, #0
	beq.n	.L0801d3d4
	b.n	.L0801d466
.L0801d2f2:
	bl	read_word_200004ac
	mov	r1, sp
	bl	fn_08021db0
	ldrh.w	r1, [sp]
	ldrh	r0, [r4, #0x14]
	mov	r5, r4
	subs	r0, r1, r0
	strh.w	r0, [sp]
	mov	r0, r5
	bl	fn_08024070
	ldrh.w	r1, [sp]
	adds	r6, r0, r1
	mov	r0, r5
	bl	fn_08023e7c
	ldrh.w	r1, [r5, #0x84]
	muls	r0, r1, r0
	sbfx	r7, r0, #8, #16
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024af8
	subs	r0, r6, r0
	sxth	r0, r0
	movs	r6, #0
	cmp	r0, #0
	blt.n	.L0801d37e
	cmp	r0, r7
	ble.n	.L0801d344
	ldrh.w	r6, [r5, #0x82]
	.inst.n	0x1e76	@ subs r6, r6, #1
	b.n	.L0801d37e
.L0801d344:
	ldrb.w	r1, [r5, #0x88]
	and.w	r1, r1, #7
	cmp	r1, #1
	beq.n	.L0801d356
	cmp	r1, #2
	beq.n	.L0801d374
	b.n	.L0801d37e
.L0801d356:
	ldrh.w	r1, [r5, #0x82]
	.inst.n	0x1e49	@ subs r1, r1, #1
	muls	r1, r0, r1
	add.w	r0, r7, r7, lsr #31
	add.w	r0, r1, r0, asr #1
	sdiv	r6, r0, r7
	b.n	.L0801d37e
.L0801d36c:
	b.n	.L0801d3aa
.L0801d36e:
	b.n	.L0801d3ac
.L0801d370:
	b.n	.L0801d3bc
.L0801d372:
	b.n	.L0801d3c4
.L0801d374:
	ldrh.w	r1, [r5, #0x82]
	muls	r1, r0, r1
	sdiv	r6, r1, r7
.L0801d37e:
	ldrsh.w	r0, [r4, #0x7c]
	cmp	r0, r6
	beq.n	.L0801d3aa
	uxth	r1, r6
	mov	r0, r4
	bl	fn_0801bcd2
	mov	r0, r4
	ldrh.w	r1, [r4, #0x7c]
	bl	fn_0801bcd2
	movs	r2, #0
	mov	r0, r4
	strh.w	r6, [r4, #0x7c]
	movs	r1, #0x1c
	b.n	.L0801d3a6
.L0801d3a4:
	b.n	.L0801d40a
.L0801d3a6:
	bl	fn_080207f4
.L0801d3aa:
	pop	{r3, r4, r5, r6, r7, pc}
.L0801d3ac:
	ldrh.w	r1, [r4, #0x7c]!
	bl	fn_0801bcd2
	movw	r0, #0x7fff
	strh	r0, [r4]
	pop	{r3, r4, r5, r6, r7, pc}
.L0801d3bc:
	pop.w	{r3, r4, r5, r6, r7, lr}
	b.w	fn_08025d04
.L0801d3c4:
	ldrsh.w	r2, [r4, #0x40]
	ldrsh.w	r0, [r4, #0x4c]
	cmp	r2, r0
	ble.n	.L0801d3d6
	mov	r6, r2
	b.n	.L0801d3d8
.L0801d3d4:
	b.n	.L0801d434
.L0801d3d6:
	mov	r6, r0
.L0801d3d8:
	ldrsh.w	r1, [r4, #0x58]!
	ldrsh.w	r3, [r4, #0xc]
	cmp	r1, r3
	ble.n	.L0801d3e8
	mov	r4, r1
	b.n	.L0801d3ea
.L0801d3e8:
	mov	r4, r3
.L0801d3ea:
	cmp	r6, r4
	ble.n	.L0801d3fa
	cmp	r2, r0
	ble.n	.L0801d3f6
	mov	r1, r2
	b.n	.L0801d400
.L0801d3f6:
	mov	r1, r0
	b.n	.L0801d400
.L0801d3fa:
	cmp	r1, r3
	bgt.n	.L0801d400
	mov	r1, r3
.L0801d400:
	mov	r0, r5
	pop.w	{r3, r4, r5, r6, r7, lr}
	b.w	fn_08020834
.L0801d40a:
	mov	r0, r5
	bl	get_word_at_0x10
	mov	r5, r0
	mov	r0, r4
	bl	fn_08023e7c
	ldrh.w	r1, [r4, #0x84]
	muls	r0, r1, r0
	asrs	r0, r0, #8
	strh	r0, [r5]
	mov	r0, r4
	bl	fn_08023e48
	ldrh.w	r1, [r4, #0x86]
	muls	r0, r1, r0
	asrs	r0, r0, #8
	strh	r0, [r5, #2]
	pop	{r3, r4, r5, r6, r7, pc}
.L0801d434:
	ldrb.w	r0, [r4, #0x88]
	and.w	r0, r0, #7
	cmp	r0, #1
	beq.n	.L0801d44a
	cmp	r0, #2
	beq.n	.L0801d454
	cmp	r0, #3
	beq.n	.L0801d45e
	b.n	.L0801d466
.L0801d44a:
	mov	r1, r5
	mov	r0, r4
	bl	fn_080185ec
	b.n	.L0801d466
.L0801d454:
	mov	r1, r5
	mov	r0, r4
	bl	fn_080183b0
	b.n	.L0801d466
.L0801d45e:
	mov	r1, r5
	mov	r0, r4
	bl	fn_08018a20
.L0801d466:
	mov	r1, r5
	mov	r0, r4
	pop.w	{r3, r4, r5, r6, r7, lr}
	b.w	fn_08016100
	.short	0x0000	@ padding
.L0801d474:
	.word	d_08050f14
