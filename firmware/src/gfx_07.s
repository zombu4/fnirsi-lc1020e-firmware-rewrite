@ gfx_07.s - graphics functions 0x0801713c..0x0801816e (pen-drawn vertical rectangle, object drawing handlers)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0801713c - fills a vertical bar with a pen (solid or dashed).
@   r0 = drawing context (word +8 = clip rectangle pointer), r1 = pen record
@   (halfword 0 colour, halfword 1 thickness, halfword 2 dash length,
@   halfword 3 dash gap, byte +8), r2 = point (x, y halfwords),
@   r3 = pointer to a second point (y halfword at +2). No return value.
@   Builds the rectangle x from x - thickness/2 to x + (thickness - 1)/2 (the
@   exact split is (thickness - 1) >> 1 and bit 0 of (thickness - 1)) and y from
@   min(y1, y2) to max(y1, y2) - 1, intersects it with the clip rectangle via
@   rect_intersect (0x08011e4c); an empty result returns at once.
@   Solid pen (fn_0801ecd0 returns nonzero or dash length/gap is zero): clears
@   a 0x1c byte record with clear_bytes, stores the colour and byte +8 of the
@   pen into it and makes one fn_0801f730 call with the rectangle.
@   Otherwise allocates a row buffer of width bytes with fn_08022bac and for
@   every row fills it with 0xff (fill_bytes_ff), masks it (fn_0801ec54),
@   applies the dash counter (the mask byte is cleared while the counter is
@   greater than the dash length, the counter restarts at length + gap) and
@   calls fn_0801f730; the buffer is freed with fn_08022c44.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801713c,"ax",%progbits
	.global fn_0801713c
	.thumb_func
	.type fn_0801713c, %function
fn_0801713c:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r11, r0
	ldrsh.w	r0, [r1, #2]
	mov	r4, r1
	.inst.n	0x1e40	@ subs r0, r0, #1
	asrs	r1, r0, #1
	and.w	r0, r0, #1
	ldrh	r5, [r2]
	sub	sp, #0x24
	add	r0, r1
	subs	r0, r5, r0
	strh.w	r0, [sp]
	ldrh	r0, [r2]
	add	r0, r1
	strh.w	r0, [sp, #4]
	ldrsh.w	r1, [r2, #2]
	ldrsh.w	r0, [r3, #2]
	cmp	r1, r0
	bge.n	.L08017172
	mov	r0, r1
.L08017172:
	strh.w	r0, [sp, #2]
	ldrsh.w	r0, [r2, #2]
	ldrsh.w	r1, [r3, #2]
	cmp	r0, r1
	bgt.n	.L08017184
	mov	r0, r1
.L08017184:
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #6]
	mov	r1, sp
	mov	r0, r1
	ldr.w	r2, [r11, #8]
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L080171da
	ldrh	r0, [r4, #6]
	cbz	r0, .L080171a6
	ldrh	r0, [r4, #4]
	cbz	r0, .L080171a6
	movs	r6, #1
	b.n	.L080171a8
.L080171a6:
	movs	r6, #0
.L080171a8:
	movs	r7, #1
	mov	r0, sp
	bl	fn_0801ecd0
	cbnz	r0, .L080171b4
	cbz	r6, .L080171b6
.L080171b4:
	movs	r7, #0
.L080171b6:
	movs	r1, #0x1c
	add	r0, sp, #8
	bl	clear_bytes
	str.w	sp, [sp, #8]
	ldrh	r0, [r4]
	strh.w	r0, [sp, #0x10]
	ldrb	r0, [r4, #8]
	mov	r5, sp
	strb.w	r0, [sp, #0x20]
	cbz	r7, .L080171e0
	add	r1, sp, #8
	mov	r0, r11
	bl	fn_0801f730
.L080171da:
	add	sp, #0x24
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L080171e0:
	ldrh.w	r0, [sp, #4]
	ldrh.w	r1, [sp]
	ldrsh.w	r7, [sp, #6]
	subs	r0, r0, r1
	.inst.n	0x1c40	@ adds r0, r0, #1
	sxth.w	r9, r0
	ldrh.w	r0, [sp, #2]
	strh.w	r0, [sp, #6]
	mov	r0, r9
	bl	fn_08022bac
	mov	r10, r0
	str	r0, [sp, #0x14]
	str	r5, [sp, #0x1c]
	movs	r0, #0
	cbz	r6, .L08017222
	ldrsh.w	r0, [r4, #6]
	ldrsh.w	r1, [r4, #4]
	add	r0, r1
	ldrsh.w	r1, [sp, #2]
	sdiv	r2, r1, r0
	mls	r0, r0, r2, r1
.L08017222:
	mov	r8, r0
	ldrsh.w	r5, [sp, #2]
	b.n	.L0801728e
.L0801722a:
	mov	r1, r9
	mov	r0, r10
	bl	fill_bytes_ff
	ldrsh.w	r1, [sp]
	mov	r3, r9
	sxth	r2, r5
	mov	r0, r10
	bl	fn_0801ec54
	strb.w	r0, [sp, #0x18]
	cbz	r6, .L08017270
	cbz	r0, .L08017268
	ldrsh.w	r1, [r4, #4]
	cmp	r1, r8
	bge.n	.L08017256
	movs	r0, #0
	strb.w	r0, [sp, #0x18]
.L08017256:
	ldrsh.w	r0, [r4, #6]
	ldrsh.w	r1, [r4, #4]
	add	r1, r0
	cmp	r1, r8
	bgt.n	.L08017268
	mov.w	r8, #0
.L08017268:
	add.w	r0, r8, #1
	sxth.w	r8, r0
.L08017270:
	add	r1, sp, #8
	mov	r0, r11
	bl	fn_0801f730
	ldrh.w	r0, [sp, #2]
	.inst.n	0x1c40	@ adds r0, r0, #1
	strh.w	r0, [sp, #2]
	ldrh.w	r0, [sp, #6]
	.inst.n	0x1c40	@ adds r0, r0, #1
	strh.w	r0, [sp, #6]
	.inst.n	0x1c6d	@ adds r5, r5, #1
.L0801728e:
	cmp	r5, r7
	ble.n	.L0801722a
	mov	r0, r10
	bl	fn_08022c44
	b.n	.L080171da

@ ----------------------------------------------------------------------------
@ fn_0801729a - draws one object (message handler), entered by the tail jump
@   b.w at 0x08021ff4 from 0x08021fb8.
@   r0 = message pointer (kept in r5). No return value. Frame 96 bytes.
@   r4 = get_first_word(msg) (the object), r6 = get_word_10_if_byte_8_14_to_19(msg)
@   (the drawing context). fn_08023dec(r4, sp+0x24) fills the rectangle at
@   sp+0x24 (halfwords +0x24 left, +0x26 top, +0x28 right, +0x2a bottom).
@   r5 = flags: bit 0 set when bit 4 of byte [r4+0x48] is set, bit 1 set when
@   bit 5 of it is set, bit 2 set when fn_08024d08(r4, 0) = 0x27d1 and bit 10
@   of halfword [r4+0x22] is clear.
@   fn_0801e7b4(sp+0x2c) initialises a record; halfword [sp+0x42] = halfword
@   [r4+0x44]; halfword [sp+0x44] = halfword [r4+0x46]; byte [sp+0x49] = r5;
@   fn_0802501a(r4, 0, sp+0x2c); byte [sp+0x48] is set to 1 (r8) when it is 0.
@   Words [sp+0x30] = [r4+0x3c], [sp+0x34] = [r4+0x40]; when neither is 0xffff
@   halfword [sp+0x3a] = low half of fn_08012786(r4, 0x40000,
@   fn_08024bac(r4, 0x40000, 0x55)) and halfword [sp+0x3c] = low half of
@   fn_08024bac(r4, 0x40000, 0x20).
@   Mode m = byte [r4+0x48] AND 7. When m is 2 or 3 and byte [sp+0x48] is 2 or
@   3: fn_08027d30(sp+0x58, word [r4+0x24], word [sp+0x2c], int16 [sp+0x40],
@   stack int16 [sp+0x3e], 0x1fff, r5); when sxth(h[sp+0x28] - h[sp+0x24] + 1)
@   < int16 [sp+0x58], byte [sp+0x48] = 1.
@   r7 = r4 + 0x30, except r7 = 0 when m = 3 or sxth(h[sp+0x2a] - h[sp+0x26]
@   + 1) < 0x400.
@   rect_intersect(sp+0x50, sp+0x24, word [r6+8]); a zero result returns
@   without touching word [r6+8].
@   m = 0: fn_08024208(r4) is negated and rect_move(sp+0x24, 0, sxth(-result))
@   is called; halfword [sp+0x2a] = halfword [r4+0x1a].
@   r9 = sp+0x50. m = 2 or 3: r8 = word [r6+8]; word [r6+8] = r9;
@   fn_0801e274(r6, sp+0x2c, sp+0x24, word [r4+0x24], stack r7); word [r6+8] =
@   r8 (restored); then r8 = word [r6+8], word [r6+8] = r9; m = 3 continues at
@   0x08017464, m = 2 goes to the exit.
@   Other m: fn_0801e274(r6, sp+0x2c, sp+0x24, word [r4+0x24], stack r7);
@   r8 = word [r6+8]; word [r6+8] = r9; goes to the exit.
@   m = 3: fn_08027d30(sp+0x18, ...) as above; when sxth(h[sp+0x28] -
@   h[sp+0x24] + 1) < int16 [sp+0x18]: halfword [sp+0x42] = h[r4+0x44] +
@   h[sp+0x18] + 3 * fn_08020a0a(word [sp+0x2c], 0x20, 0x20), halfword [sp+0x44]
@   = h[r4+0x46], fn_0801e274(...). Then when sxth(h[sp+0x2a] - h[sp+0x26] + 1)
@   < int16 [sp+0x1a]: halfword [sp+0x42] = h[r4+0x44]; halfword [sp+0x44] =
@   int16 [sp+0x1a] + h[r4+0x46] + halfword [word [sp+0x2c] + 8];
@   fn_0801e274(...).
@   Exit: word [r6+8] = r8; add sp, #96; pop {r4..r10, pc}.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801729a,"ax",%progbits
	.global fn_0801729a
	.thumb_func
	.type fn_0801729a, %function
fn_0801729a:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	sub	sp, #0x60
	mov	r5, r0
	bl	get_first_word
	mov	r4, r0
	mov	r0, r5
	bl	get_word_10_if_byte_8_14_to_19
	mov	r6, r0
	add	r1, sp, #0x24
	mov	r0, r4
	bl	fn_08023dec
	ldrb.w	r0, [r4, #0x48]
	movs	r5, #0
	lsls	r1, r0, #0x1b
	bpl.n	.L080172c4
	movs	r5, #1
.L080172c4:
	lsls	r0, r0, #0x1a
	bpl.n	.L080172cc
	orr.w	r5, r5, #2
.L080172cc:
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024d08
	sub.w	r1, r0, #0x2700
	subs	r1, #0xd1
	bne.n	.L080172e6
	ldrh	r0, [r4, #0x22]
	lsls	r0, r0, #0x15
	bmi.n	.L080172e6
	orr.w	r5, r5, #4
.L080172e6:
	add	r0, sp, #0x2c
	bl	fn_0801e7b4
	ldrh.w	r0, [r4, #0x44]
	strh.w	r0, [sp, #0x42]
	ldrh.w	r0, [r4, #0x46]
	strh.w	r0, [sp, #0x44]
	strb.w	r5, [sp, #0x49]
	add	r2, sp, #0x2c
	movs	r1, #0
	mov	r0, r4
	bl	fn_0802501a
	ldrb.w	r0, [sp, #0x48]
	mov.w	r8, #1
	cbnz	r0, .L08017318
	strb.w	r8, [sp, #0x48]
.L08017318:
	ldr	r0, [r4, #0x3c]
	str	r0, [sp, #0x30]
	ldr	r0, [r4, #0x40]
	str	r0, [sp, #0x34]
	ldr	r1, [sp, #0x30]
	movw	r0, #0xffff
	cmp	r1, r0
	beq.n	.L08017368
	ldr	r1, [sp, #0x34]
	cmp	r1, r0
	beq.n	.L08017368
	mov.w	r9, #0x40000
	mov	r7, r4
	movs	r2, #0x55
	mov	r1, r9
	mov	r0, r4
	bl	fn_08024bac
	mov	r2, r0
	mov	r1, r9
	mov	r0, r7
	bl	fn_08012786
	str	r0, [sp]
	ldrh.w	r0, [sp]
	strh.w	r0, [sp, #0x3a]
	mov	r0, r4
	movs	r2, #0x20
	mov	r1, r9
	bl	fn_08024bac
	str	r0, [sp]
	ldrh.w	r0, [sp]
	strh.w	r0, [sp, #0x3c]
.L08017368:
	ldrb.w	r0, [r4, #0x48]
	movw	r10, #0x1fff
	and.w	r0, r0, #7
	cmp	r0, #2
	beq.n	.L0801737c
	cmp	r0, #3
	bne.n	.L080173ba
.L0801737c:
	ldrb.w	r0, [sp, #0x48]
	cmp	r0, #2
	beq.n	.L08017388
	cmp	r0, #3
	bne.n	.L080173ba
.L08017388:
	ldrsh.w	r1, [sp, #0x3e]
	strd	r1, r10, [sp]
	str	r5, [sp, #8]
	ldrsh.w	r3, [sp, #0x40]
	ldr	r2, [sp, #0x2c]
	add	r0, sp, #0x58
	ldr	r1, [r4, #0x24]
	bl	fn_08027d30
	ldrh.w	r0, [sp, #0x28]
	ldrh.w	r1, [sp, #0x24]
	subs	r0, r0, r1
	.inst.n	0x1c40	@ adds r0, r0, #1
	ldrsh.w	r1, [sp, #0x58]
	sxth	r0, r0
	cmp	r0, r1
	bge.n	.L080173ba
	strb.w	r8, [sp, #0x48]
.L080173ba:
	ldrb.w	r0, [r4, #0x48]
	add.w	r7, r4, #0x30
	and.w	r0, r0, #7
	cmp	r0, #3
	beq.n	.L080173de
	ldrh.w	r0, [sp, #0x2a]
	ldrh.w	r1, [sp, #0x26]
	subs	r0, r0, r1
	.inst.n	0x1c40	@ adds r0, r0, #1
	sxth	r0, r0
	cmp.w	r0, #0x400
	bge.n	.L080173e0
.L080173de:
	movs	r7, #0
.L080173e0:
	add	r1, sp, #0x24
	add	r0, sp, #0x50
	ldr	r2, [r6, #8]
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L080174ea
	ldrb.w	r0, [r4, #0x48]
	lsls	r0, r0, #0x1d
	bne.n	.L0801740e
	mov	r0, r4
	bl	fn_08024208
	rsbs	r0, r0, #0
	sxth	r2, r0
	movs	r1, #0
	add	r0, sp, #0x24
	bl	rect_move
	ldrh	r0, [r4, #0x1a]
	strh.w	r0, [sp, #0x2a]
.L0801740e:
	ldrb.w	r0, [r4, #0x48]
	add.w	r9, sp, #0x50
	and.w	r0, r0, #7
	cmp	r0, #2
	beq.n	.L08017446
	cmp	r0, #3
	beq.n	.L08017446
	str	r7, [sp]
	add	r2, sp, #0x24
	add	r1, sp, #0x2c
	mov	r0, r6
	ldr	r3, [r4, #0x24]
	bl	fn_0801e274
	ldr	r0, [r6, #8]
.L08017432:
	str.w	r9, [r6, #8]
	mov	r8, r0
	ldrb.w	r0, [r4, #0x48]
	and.w	r0, r0, #7
	cmp	r0, #3
	beq.n	.L08017464
	b.n	.L08017506
.L08017446:
	ldr.w	r8, [r6, #8]
	str.w	r9, [r6, #8]
	str	r7, [sp]
	add	r2, sp, #0x24
	add	r1, sp, #0x2c
	mov	r0, r6
	ldr	r3, [r4, #0x24]
	bl	fn_0801e274
	mov	r0, r8
	str.w	r8, [r6, #8]
	b.n	.L08017432
.L08017464:
	ldrsh.w	r1, [sp, #0x3e]
	strd	r1, r10, [sp]
	str	r5, [sp, #8]
	ldrsh.w	r3, [sp, #0x40]
	ldr	r2, [sp, #0x2c]
	add	r0, sp, #0x18
	ldr	r1, [r4, #0x24]
	bl	fn_08027d30
	ldrh.w	r0, [sp, #0x28]
	ldrh.w	r1, [sp, #0x24]
	subs	r0, r0, r1
	.inst.n	0x1c40	@ adds r0, r0, #1
	ldrsh.w	r1, [sp, #0x18]
	sxth	r0, r0
	cmp	r0, r1
	bge.n	.L080174c6
	movs	r2, #0x20
	mov	r1, r2
	ldr	r0, [sp, #0x2c]
	bl	fn_08020a0a
	ldrh.w	r1, [r4, #0x44]
	ldrh.w	r2, [sp, #0x18]
	add.w	r0, r0, r0, lsl #1
	add	r1, r2
	add	r0, r1
	strh.w	r0, [sp, #0x42]
	ldrh.w	r0, [r4, #0x46]
	strh.w	r0, [sp, #0x44]
	str	r7, [sp]
	add	r2, sp, #0x24
	add	r1, sp, #0x2c
	mov	r0, r6
	ldr	r3, [r4, #0x24]
	bl	fn_0801e274
.L080174c6:
	ldrh.w	r0, [sp, #0x2a]
	ldrh.w	r1, [sp, #0x26]
	subs	r0, r0, r1
	.inst.n	0x1c40	@ adds r0, r0, #1
	sxth	r1, r0
	ldrsh.w	r0, [sp, #0x1a]
	cmp	r1, r0
	bge.n	.L08017506
	ldrh.w	r1, [r4, #0x44]
	strh.w	r1, [sp, #0x42]
	ldr	r1, [sp, #0x2c]
	ldrh	r1, [r1, #8]
	b.n	.L080174ec
.L080174ea:
	b.n	.L0801750a
.L080174ec:
	ldrh.w	r2, [r4, #0x46]
	str	r7, [sp]
	add	r0, r2
	add	r0, r1
	strh.w	r0, [sp, #0x44]
	add	r2, sp, #0x24
	add	r1, sp, #0x2c
	mov	r0, r6
	ldr	r3, [r4, #0x24]
	bl	fn_0801e274
.L08017506:
	str.w	r8, [r6, #8]
.L0801750a:
	add	sp, #0x60
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ fn_08017510 - draws the cell grid of an object (message handler), entered by
@   the tail jump b.w at 0x0802751e from 0x080274d4.
@   r0 = message pointer (kept in r5). No return value. Frame 388 bytes.
@   r4 = get_first_word(msg) (the object), sl = get_word_10_if_byte_8_14_to_19(
@   msg) (the drawing context). rect_intersect(sp+0xc0, r4+0x14, word [sl+8]);
@   a zero result returns (word [sl+8] untouched); otherwise word [sp+0x3c] =
@   word [sl+8] and word [sl+8] = sp+0xc0 (the clip rectangle: halfwords sp+0xc0
@   left, +0xc2 top, +0xc4 right, +0xc6 bottom).
@   Setup: word [sp+0x15c] = sxth(fn_08024bac(r4, 0, 0x32)); [sp+0x16c] =
@   fn_08024ba0(r4, 0); [sp+0x174] = fn_08024ab0(r4, 0); [sp+0x168] =
@   fn_08024b10(r4, 0); [sp+0x164] = fn_08024b4c(r4, 0); word [sp+0x24] =
@   halfword [r4+0x20]; halfword [r4+0x20] = 0; bit 2 of halfword [r4+0x22] set;
@   fn_0801f344(sp+0x88); fn_0802516e(r4, 0x50000, sp+0x88); fn_0801e7b4(sp+0xc8);
@   fn_0802501a(r4, 0x50000, sp+0xc8); halfword [r4+0x20] = word [sp+0x24]; bit 2
@   of halfword [r4+0x22] cleared.
@   halfword [sp+0x16] = [sp+0x16c] + h[r4+0x16] - fn_08024224(r4) + [sp+0x15c]
@   - 1; word [sp+0x160] = fn_08024216(r4); fp = 1 when fn_08024936(r4, 0) = 1
@   else 0; fn_08023a0c(sp+0x108, sl); words [sp+0x13c] = 0x50000, [sp+0x10c] =
@   0x08050f68 (literal at 0x080179a8), [sp+0x110] = 0, [sp+0x118] = sp+0x50,
@   [sp+0x11c] = sp+0xe8; r9 = 0 (row), r7 = 0 (cell index).
@   Row loop: runs while halfword [r4+0x26] > r9 (unsigned); else word [sl+8] =
@   word [sp+0x3c] and return. Row: word [sp+0x150] = int16 [word [r4+0x2c] +
@   2*r9]; halfword [sp+0x12] = sxth(h[sp+0x16] + 1) (row top); halfword
@   [sp+0x16] = [sp+0x150] - 1 + row top (row bottom); row top above int16
@   [sp+0xc6] ends the loop. fp = 1: halfword [sp+0x10] = h[r4+0x18] - [sp+0x164]
@   - [sp+0x160] - [sp+0x15c] - 1; fp = 0: halfword [sp+0x14] = h[r4+0x14] +
@   [sp+0x168] - [sp+0x160] + [sp+0x15c] - 1; r5 = 0 (column).
@   Column loop: runs while halfword [r4+0x24] > r5 (unsigned); else r9 += 1
@   (uxth). Cell: word [sp+0x154] = byte [cell] when cell = word [word [r4+0x28]
@   + 4*r7] is nonzero, else 0; fp = 1: h[sp+0x14] = h[sp+0x10] - 1, h[sp+0x10]
@   = h[sp+0x14] - h[word [r4+0x30] + 2*r5] + 1; fp = 0: h[sp+0x10] = h[sp+0x14]
@   + 1, h[sp+0x14] = h[sp+0x10] + h[word [r4+0x30] + 2*r5] - 1.
@   Span loop r6 = 0.. while r5 + r6 < halfword [r4+0x24] - 1 (signed): the
@   cell at index r7 + r6 must be nonzero with bit 0 of its first byte set,
@   otherwise the loop ends; each such cell adds int16 [word [r4+0x30] + 2 +
@   2*(r5 + r6)] to h[sp+0x14] (fp = 0) or subtracts it from h[sp+0x10] (fp = 1).
@   int16 [sp+0x16] >= int16 [sp+0xc2] draws the cell; otherwise r7 = uxth(r7 +
@   r6 + 1) and r5 = uxth(r5 + r6) + 1 and the column loop continues.
@   Draw: halfwords [sp+0x28..0x2e] = int16 [sp+0x10], [sp+0x12], [sp+0x14],
@   [sp+0x16] (cell rectangle); t = (byte [sp+0xab] >> 1) AND 0x1f: bit 2 of t
@   and int16 [sp+0x28] > [sp+0x168] + int16 [r4+0x14]: [sp+0x28] -= int16
@   [sp+0xa8] / 2 (round toward zero); bit 1 and [sp+0x2a] > [sp+0x16c] + int16
@   [r4+0x16]: [sp+0x2a] -= int16 [sp+0xa8] / 2; bit 3 and [sp+0x2c] < int16
@   [r4+0x18] - [sp+0x164] - 1: [sp+0x2c] += (v AND 1) + v / 2 with v = int16
@   [sp+0xa8]; bit 0 and [sp+0x2e] < int16 [r4+0x1a] - [sp+0x174] - 1:
@   [sp+0x2e] += (v AND 1) + v / 2.
@   When halfword [r4+0x36] = r9 and halfword [r4+0x34] = r5 (selected cell):
@   r1 = flags from halfword [r4+0x20]: 0x20 when bit 6 is clear and bit 5 set,
@   2 for bit 1, 4 for bit 2, 8 for bit 3; r1 nonzero: halfword [r4+0x20] = r1,
@   bit 2 of [r4+0x22] set, fn_0801f344(sp+0x50), fn_0801e7b4(sp+0xe8),
@   fn_0802516e(r4, 0x50000, sp+0x50), fn_0802501a(r4, 0x50000, sp+0xe8),
@   halfword [r4+0x20] = word [sp+0x24], bit 2 of [r4+0x22] cleared; otherwise,
@   and for every cell that is not the selected one, copy_bytes_08022ce0(sp+0x50,
@   sp+0x88, 0x38) and copy_bytes_08022ce0(sp+0xe8, sp+0xc8, 0x20).
@   Then word [sp+0x114] = sp+0x28; word [sp+0x140] = r9 * halfword [r4+0x24] +
@   r5; fn_080207f4(r4, 0x1a, sp+0x108); fn_0801f31c(sl, sp+0x50, sp+0x28); a
@   zero cell pointer skips the text.
@   Text rectangle: halfwords [sp+0x40] = h[sp+0x10] + fn_08024b10(r4, 0x50000)
@   (sxth), [sp+0x42] = h[sp+0x12] + fn_08024ba0, [sp+0x44] = h[sp+0x14] -
@   fn_08024b4c, [sp+0x46] = h[sp+0x16] - fn_08024ab0; f = bit 1 of word
@   [sp+0x154]; fn_08027d30(sp+0x170, cell + 1, word [sp+0xc8], int16 [sp+0xfc],
@   stack int16 [sp+0xfa], sxth([sp+0x44] - [sp+0x40] + 1), 2 when f else 0).
@   f = 0: [sp+0x42] = row top + [sp+0x150]/2 - int16 [sp+0x172]/2 and [sp+0x46]
@   = row top + [sp+0x150]/2 + int16 [sp+0x172]/2 (halves rounded toward zero).
@   rect_intersect(sp+0x17c, sp+0xc0, sp+0x10); nonzero: word [sl+8] = sp+0x17c,
@   fn_0801e274(sl, sp+0xe8, sp+0x40, cell + 1, stack 0), word [sl+8] = sp+0xc0.
@   Last: fn_080207f4(r4, 0x1b, sp+0x108); continue with the next cell.
@   Exit: add sp, #388; pop {r4..r11, pc}.
@ ----------------------------------------------------------------------------
	.section .text.fn_08017510,"ax",%progbits
	.p2align 2
	.global fn_08017510
	.thumb_func
	.type fn_08017510, %function
fn_08017510:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x184
	mov	r5, r0
	bl	get_first_word
	mov	r4, r0
	mov	r0, r5
	bl	get_word_10_if_byte_8_14_to_19
	mov	r10, r0
	ldr	r2, [r0, #8]
	add.w	r1, r4, #0x14
	add	r0, sp, #0xc0
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L08017634
	ldr.w	r0, [r10, #8]
	str	r0, [sp, #0x3c]
	add	r0, sp, #0xc0
	str.w	r0, [r10, #8]
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x32
	bl	fn_08024bac
	sxth	r0, r0
	str	r0, [sp, #0x15c]
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024ba0
	str	r0, [sp, #0x16c]
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024ab0
	str	r0, [sp, #0x174]
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024b10
	str	r0, [sp, #0x168]
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024b4c
	str	r0, [sp, #0x164]
	ldrh	r0, [r4, #0x20]
	movs	r6, #0
	str	r0, [sp, #0x24]
	strh	r6, [r4, #0x20]
	ldrh	r0, [r4, #0x22]
	orr.w	r0, r0, #4
	strh	r0, [r4, #0x22]
	add	r0, sp, #0x88
	bl	fn_0801f344
	mov.w	r5, #0x50000
	add	r2, sp, #0x88
	mov	r1, r5
	mov	r0, r4
	bl	fn_0802516e
	add	r0, sp, #0xc8
	bl	fn_0801e7b4
	add	r2, sp, #0xc8
	mov	r1, r5
	mov	r0, r4
	bl	fn_0802501a
	ldr	r0, [sp, #0x24]
	strh	r0, [r4, #0x20]
	ldrh	r0, [r4, #0x22]
	movs	r7, #0
	bic.w	r0, r0, #4
	strh	r0, [r4, #0x22]
	mov	r0, r4
	bl	fn_08024224
	mov	r1, r0
	ldrh	r2, [r4, #0x16]
	ldr	r0, [sp, #0x16c]
	add	r0, r2
	subs	r1, r0, r1
	ldr	r0, [sp, #0x15c]
	add	r0, r1
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #0x16]
	mov	r0, r4
	bl	fn_08024216
	str	r0, [sp, #0x160]
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024936
	cmp	r0, #1
	beq.n	.L080175ea
	movs	r0, #0
.L080175ea:
	mov	r11, r0
	mov	r1, r10
	add	r0, sp, #0x108
	bl	fn_08023a0c
	mov.w	r0, #0x50000
	str	r0, [sp, #0x13c]
	ldr	r0, .L080179a8
	str	r0, [sp, #0x10c]
	movs	r0, #0
	str	r0, [sp, #0x110]
	add	r0, sp, #0x50
	str	r0, [sp, #0x118]
	add	r0, sp, #0xe8
	str	r0, [sp, #0x11c]
	movs	r0, #0
	b.n	.L08017722
.L0801760e:
	ldr	r0, [r4, #0x2c]
	ldrsh.w	r1, [r0, r9, lsl #1]
	ldrh.w	r0, [sp, #0x16]
	str	r1, [sp, #0x150]
	.inst.n	0x1c40	@ adds r0, r0, #1
	sxth	r0, r0
	.inst.n	0x1e49	@ subs r1, r1, #1
	add	r1, r0
	strh.w	r0, [sp, #0x12]
	strh.w	r1, [sp, #0x16]
	ldrsh.w	r1, [sp, #0xc6]
	cmp	r0, r1
	bgt.n	.L0801772c
	b.n	.L08017636
.L08017634:
	b.n	.L08017732
.L08017636:
	cmp.w	r11, #0
	beq.n	.L08017652
	ldrh	r1, [r4, #0x18]
	ldr	r0, [sp, #0x164]
	subs	r1, r1, r0
	ldr	r0, [sp, #0x160]
	subs	r1, r1, r0
	ldr	r0, [sp, #0x15c]
	subs	r0, r1, r0
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #0x10]
	b.n	.L08017666
.L08017652:
	ldrh	r1, [r4, #0x14]
	ldr	r0, [sp, #0x168]
	add	r1, r0
	ldr	r0, [sp, #0x160]
	subs	r1, r1, r0
	ldr	r0, [sp, #0x15c]
	add	r0, r1
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #0x14]
.L08017666:
	movs	r5, #0
	b.n	.L08017716
.L0801766a:
	movs	r0, #0
	str	r0, [sp, #0x154]
	ldr	r0, [r4, #0x28]
	ldr.w	r0, [r0, r7, lsl #2]
	cbz	r0, .L0801767a
	ldrb	r0, [r0]
	str	r0, [sp, #0x154]
.L0801767a:
	cmp.w	r11, #0
	beq.n	.L0801769a
	ldrh.w	r0, [sp, #0x10]
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #0x14]
	ldr	r1, [r4, #0x30]
	ldrh.w	r1, [r1, r5, lsl #1]
	subs	r0, r0, r1
	.inst.n	0x1c40	@ adds r0, r0, #1
	strh.w	r0, [sp, #0x10]
	b.n	.L080176b2
.L0801769a:
	ldrh.w	r0, [sp, #0x14]
	.inst.n	0x1c40	@ adds r0, r0, #1
	strh.w	r0, [sp, #0x10]
	ldr	r1, [r4, #0x30]
	ldrh.w	r1, [r1, r5, lsl #1]
	add	r0, r1
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #0x14]
.L080176b2:
	movs	r6, #0
	b.n	.L080176f2
.L080176b6:
	ldr	r0, [r4, #0x28]
	adds	r1, r7, r6
	ldr.w	r0, [r0, r1, lsl #2]
	cbz	r0, .L080176fc
	ldrb	r0, [r0]
	lsls	r0, r0, #0x1f
	beq.n	.L080176fc
	ldr	r0, [r4, #0x30]
	adds	r1, r5, r6
	movs	r2, #2
	add.w	r1, r2, r1, lsl #1
	ldrsh	r0, [r0, r1]
	cmp.w	r11, #0
	beq.n	.L080176e4
	ldrh.w	r1, [sp, #0x10]
	subs	r0, r1, r0
	strh.w	r0, [sp, #0x10]
	b.n	.L080176ee
.L080176e4:
	ldrh.w	r1, [sp, #0x14]
	add	r0, r1
	strh.w	r0, [sp, #0x14]
.L080176ee:
	.inst.n	0x1c76	@ adds r6, r6, #1
	uxth	r6, r6
.L080176f2:
	ldrh	r0, [r4, #0x24]
	adds	r1, r6, r5
	.inst.n	0x1e40	@ subs r0, r0, #1
	cmp	r1, r0
	blt.n	.L080176b6
.L080176fc:
	ldrsh.w	r0, [sp, #0x16]
	ldrsh.w	r1, [sp, #0xc2]
	cmp	r0, r1
	bge.n	.L08017738
.L08017708:
	adds	r0, r7, r6
	.inst.n	0x1c40	@ adds r0, r0, #1
	uxth	r7, r0
	adds	r0, r5, r6
	uxth	r0, r0
	.inst.n	0x1c40	@ adds r0, r0, #1
	uxth	r5, r0
.L08017716:
	ldrh	r0, [r4, #0x24]
	cmp	r0, r5
	bhi.n	.L0801766a
	add.w	r0, r9, #1
	uxth	r0, r0
.L08017722:
	ldrh	r1, [r4, #0x26]
	mov	r9, r0
	cmp	r1, r9
	bhi.w	.L0801760e
.L0801772c:
	ldr	r1, [sp, #0x3c]
	str.w	r1, [r10, #8]
.L08017732:
	add	sp, #0x184
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08017738:
	ldrsh.w	r2, [sp, #0x10]
	strh.w	r2, [sp, #0x28]
	ldrsh.w	r8, [sp, #0x12]
	strh.w	r8, [sp, #0x2a]
	ldrsh.w	r1, [sp, #0x14]
	strh.w	r1, [sp, #0x2c]
	strh.w	r0, [sp, #0x2e]
	mov	lr, r0
	ldrb.w	r0, [sp, #0xab]
	ubfx	r0, r0, #1, #5
	lsls	r3, r0, #0x1d
	bpl.n	.L0801777e
	ldrsh.w	r12, [r4, #0x14]
	ldr	r3, [sp, #0x168]
	add	r3, r12
	cmp	r2, r3
	ble.n	.L0801777e
	ldrsh.w	r3, [sp, #0xa8]
	add.w	r3, r3, r3, lsr #31
	sub.w	r2, r2, r3, asr #1
	strh.w	r2, [sp, #0x28]
.L0801777e:
	lsls	r2, r0, #0x1e
	bpl.n	.L0801779e
	ldrsh.w	r3, [r4, #0x16]
	ldr	r2, [sp, #0x16c]
	add	r2, r3
	cmp	r8, r2
	ble.n	.L0801779e
	ldrsh.w	r2, [sp, #0xa8]
	add.w	r2, r2, r2, lsr #31
	sub.w	r2, r8, r2, asr #1
	strh.w	r2, [sp, #0x2a]
.L0801779e:
	lsls	r2, r0, #0x1c
	bpl.n	.L080177c6
	ldrsh.w	r3, [r4, #0x18]
	ldr	r2, [sp, #0x164]
	subs	r2, r3, r2
	.inst.n	0x1e52	@ subs r2, r2, #1
	cmp	r1, r2
	bge.n	.L080177c6
	ldrsh.w	r2, [sp, #0xa8]
	and.w	r3, r2, #1
	add.w	r2, r2, r2, lsr #31
	add.w	r2, r3, r2, asr #1
	add	r1, r2
	strh.w	r1, [sp, #0x2c]
.L080177c6:
	lsls	r0, r0, #0x1f
	beq.n	.L080177f0
	ldrsh.w	r2, [r4, #0x1a]
	ldr	r0, [sp, #0x174]
	subs	r0, r2, r0
	.inst.n	0x1e40	@ subs r0, r0, #1
	cmp	lr, r0
	bge.n	.L080177f0
	ldrsh.w	r0, [sp, #0xa8]
	and.w	r1, r0, #1
	add.w	r0, r0, r0, lsr #31
	add.w	r1, r1, r0, asr #1
	add.w	r0, r1, lr
	strh.w	r0, [sp, #0x2e]
.L080177f0:
	ldrh	r2, [r4, #0x36]
	movs	r1, #0
	cmp	r2, r9
	bne.n	.L080178f4
	ldrh	r0, [r4, #0x34]
	cmp	r0, r5
	bne.n	.L080178f4
	ldrh	r0, [r4, #0x20]
	lsls	r2, r0, #0x19
	bmi.n	.L0801780a
	lsls	r2, r0, #0x1a
	bpl.n	.L0801780a
	movs	r1, #0x20
.L0801780a:
	lsls	r2, r0, #0x1e
	bpl.n	.L08017812
	orr.w	r1, r1, #2
.L08017812:
	lsls	r2, r0, #0x1d
	bpl.n	.L0801781a
	orr.w	r1, r1, #4
.L0801781a:
	lsls	r0, r0, #0x1c
	bpl.n	.L08017822
	orr.w	r1, r1, #8
.L08017822:
	cmp	r1, #0
	beq.n	.L080178f4
	strh	r1, [r4, #0x20]
	ldrh	r0, [r4, #0x22]
	orr.w	r1, r0, #4
	strh	r1, [r4, #0x22]
	add	r0, sp, #0x50
	bl	fn_0801f344
	add	r0, sp, #0xe8
	bl	fn_0801e7b4
	mov.w	r8, #0x50000
	add	r2, sp, #0x50
	mov	r1, r8
	mov	r0, r4
	bl	fn_0802516e
	add	r2, sp, #0xe8
	mov	r1, r8
	mov	r0, r4
	bl	fn_0802501a
	ldr	r0, [sp, #0x24]
	strh	r0, [r4, #0x20]
	ldrh	r0, [r4, #0x22]
	bic.w	r1, r0, #4
	strh	r1, [r4, #0x22]
.L08017860:
	add	r0, sp, #0x28
	str	r0, [sp, #0x114]
	ldrh	r1, [r4, #0x24]
	add	r2, sp, #0x108
	mla	r0, r9, r1, r5
	str	r0, [sp, #0x140]
	movs	r1, #0x1a
	mov	r0, r4
	bl	fn_080207f4
	add	r2, sp, #0x28
	add	r1, sp, #0x50
	mov	r0, r10
	bl	fn_0801f31c
	ldr	r0, [r4, #0x28]
	ldr.w	r0, [r0, r7, lsl #2]
	cmp	r0, #0
	beq.n	.L08017988
	mov.w	r8, #0x50000
	mov	r1, r8
	mov	r0, r4
	bl	fn_08024b10
	str	r0, [sp, #0x30]
	mov	r1, r8
	mov	r0, r4
	bl	fn_08024b4c
	str	r0, [sp, #0x48]
	mov	r1, r8
	mov	r0, r4
	bl	fn_08024ba0
	str	r0, [sp, #8]
	mov	r1, r8
	mov	r0, r4
	bl	fn_08024ab0
	ldrh.w	r3, [sp, #0x10]
	ldr	r2, [sp, #0x30]
	ldrh.w	r12, [sp, #0x12]
	add	r2, r3
	sxth.w	r8, r2
	ldrh.w	r3, [sp, #0x14]
	ldr	r2, [sp, #0x48]
	strh.w	r8, [sp, #0x40]
	subs	r2, r3, r2
	sxth	r3, r2
	strh.w	r3, [sp, #0x44]
	ldr	r2, [sp, #8]
	mov	r1, r0
	add	r2, r12
	strh.w	r2, [sp, #0x42]
	ldrh.w	r2, [sp, #0x16]
	movs	r0, #0
	subs	r1, r2, r1
	strh.w	r1, [sp, #0x46]
	ldr	r1, [sp, #0x154]
	ubfx	r1, r1, #1, #1
	b.n	.L080178f6
.L080178f4:
	b.n	.L08017928
.L080178f6:
	str	r1, [sp, #0x178]
	cbz	r1, .L080178fc
	movs	r0, #2
.L080178fc:
	sub.w	r1, r3, r8
	.inst.n	0x1c49	@ adds r1, r1, #1
	ldrsh.w	r2, [sp, #0xfa]
	sxth	r1, r1
	str	r2, [sp]
	strd	r1, r0, [sp, #4]
	ldr	r0, [r4, #0x28]
	ldrsh.w	r3, [sp, #0xfc]
	ldr	r2, [sp, #0xc8]
	ldr.w	r1, [r0, r7, lsl #2]
	add	r0, sp, #0x170
	.inst.n	0x1c49	@ adds r1, r1, #1
	bl	fn_08027d30
	ldr	r0, [sp, #0x178]
	cbz	r0, .L0801793e
	b.n	.L08017968
.L08017928:
	movs	r2, #0x38
	add	r1, sp, #0x88
	add	r0, sp, #0x50
	bl	copy_bytes_08022ce0
	movs	r2, #0x20
	add	r1, sp, #0xc8
	add	r0, sp, #0xe8
	bl	copy_bytes_08022ce0
	b.n	.L08017860
.L0801793e:
	ldr	r0, [sp, #0x150]
	ldrh.w	r1, [sp, #0x12]
	ldrsh.w	r2, [sp, #0x172]
	add.w	r0, r0, r0, lsr #31
	add.w	r3, r1, r0, asr #1
	add.w	r2, r2, r2, lsr #31
	asrs	r0, r0, #1
	add.w	r0, r0, r2, asr #1
	sub.w	r3, r3, r2, asr #1
	add	r0, r1
	strh.w	r3, [sp, #0x42]
	strh.w	r0, [sp, #0x46]
.L08017968:
	add	r2, sp, #0x10
	add	r1, sp, #0xc0
	add	r0, sp, #0x17c
	bl	rect_intersect
	cbz	r0, .L08017988
	add	r1, sp, #0x17c
	movs	r0, #0
	str.w	r1, [r10, #8]
	str	r0, [sp]
	ldr	r0, [r4, #0x28]
	add	r2, sp, #0x40
	ldr.w	r3, [r0, r7, lsl #2]
	b.n	.L0801798a
.L08017988:
	b.n	.L0801799a
.L0801798a:
	add	r1, sp, #0xe8
	mov	r0, r10
	.inst.n	0x1c5b	@ adds r3, r3, #1
	bl	fn_0801e274
	add	r1, sp, #0xc0
	str.w	r1, [r10, #8]
.L0801799a:
	add	r2, sp, #0x108
	movs	r1, #0x1b
	mov	r0, r4
	bl	fn_080207f4
	b.n	.L08017708
	.short	0x0000	@ padding
.L080179a8:
	.word	d_08050f68

@ ----------------------------------------------------------------------------
@ fn_080179ac - draws the nodes of a list around a centre point (lines or pictures).
@   r0 = object (the list is at +0x30), r1 = target context, r2 = rectangle
@   (halfwords left, top, right). No return value. Frame 164 bytes.
@   Centre = (x0 + half, y0 + half) with half = (x1 - x0 + 1) / 2 (round toward
@   zero); the centre halfwords are stored at sp+0x78 and sp+0x7a.
@   Builds styles with fn_0801e8d2(sp+0x80) / fn_080250b6(object, 0x50000,
@   sp+0x80) and fn_0801e240(sp+0x60) / fn_08024f78(object, 0x50000, sp+0x60);
@   alpha (r10) = fn_08024a50(object, 0); fn_08023a0c(sp+0x8, context); word
@   [sp+0xc] = 0x08050f30 (literal at 0x08017b8c); word [sp+0x2c] = sp+0x78;
@   word [sp+0x90] = object + 0x30.
@   For each list node (first node from get_word_8_or_zero, next ones from
@   read_word_at_base_plus_offset(word [sp+0x90], node); the loop ends at a zero
@   node): r5 = word [node]; kind byte [node+4] = 1 draws a line, kind byte 0
@   with word [node+0x10] nonzero draws a picture, any other kind draws nothing.
@   Kind 1: angle = fn_08022b12(word [node+0xc], word [r5+0x14], word [r5+0x18],
@   int16 [r5+0x20], stack halfword [r5+0x1e] + int16 [r5+0x20]); r = halfword
@   [r5+0x1c] + halfword [node+0x12] + half; end point y = centre y +
@   sine_q15_degrees(angle) * r / 0x7fff (stored at sp+0x9a), end point x =
@   centre x + cosine_q15_degrees(angle) * r / 0x7fff (stored at sp+0x98); style
@   halfwords [sp+0x80] = halfword [node+0x14], [sp+0x82] = halfword [node+0x10];
@   byte [sp+0x88] = byte [node+5] when it is above 0xfd (alpha r10 is used)
@   or (byte [node+5] * alpha) >> 8 otherwise; word [sp+0x40] = 1; words
@   [sp+0x20] = sp+0x80, [sp+0x30] = sp+0x98; fn_080207f4(object, 0x1a, sp+0x8);
@   fn_0801e8b8(context, sp+0x80, sp+0x78, sp+0x98).
@   Kind 0: angle as above in r5; fn_0802187c(word [node+0x10], sp+0x94) gives
@   the picture size word; rectangle halfwords [sp+0x58] = centre x - halfword
@   [node+0x14], [sp+0x5a] = centre y - halfword [node+0x16], [sp+0x5c] = [sp+0x58]
@   + ((size >> 10) AND 0x7ff) - 1, [sp+0x5e] = [sp+0x5a] + (size >> 21) - 1;
@   byte [sp+0x6b] = alpha scaled by byte [node+5] as above; halfwords [sp+0x64]
@   = halfword [node+0x14], [sp+0x66] = halfword [node+0x16]; rotation = angle * 10
@   minus 0xe10 when it is above 0xe10, stored as halfword [sp+0x60]; word
@   [sp+0x24] = sp+0x60; fn_080207f4(object, 0x1a, sp+0x8); fn_0801e1f0(context,
@   sp+0x60, sp+0x58, word [node+0x10]).
@   Each draw is followed by fn_080207f4(object, 0x1b, sp+0x8).
@ ----------------------------------------------------------------------------
	.section .text.fn_080179ac,"ax",%progbits
	.p2align 2
	.global fn_080179ac
	.thumb_func
	.type fn_080179ac, %function
fn_080179ac:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r11, r1
	mov	r7, r0
	ldrh	r0, [r2, #4]
	ldrh	r1, [r2]
	sub	sp, #0xa4
	subs	r0, r0, r1
	.inst.n	0x1c40	@ adds r0, r0, #1
	sxth	r0, r0
	add.w	r0, r0, r0, lsr #31
	asrs	r6, r0, #1
	adds	r0, r1, r6
	strh.w	r0, [sp, #0x78]
	ldrh	r0, [r2, #2]
	add	r0, r6
	strh.w	r0, [sp, #0x7a]
	add	r0, sp, #0x80
	bl	fn_0801e8d2
	mov.w	r4, #0x50000
	add	r2, sp, #0x80
	mov	r1, r4
	mov	r0, r7
	bl	fn_080250b6
	add	r0, sp, #0x60
	bl	fn_0801e240
	add	r2, sp, #0x60
	mov	r1, r4
	mov	r0, r7
	bl	fn_08024f78
	movs	r1, #0
	mov	r0, r7
	bl	fn_08024a50
	mov	r10, r0
	mov	r1, r11
	add	r0, sp, #8
	bl	fn_08023a0c
	ldr	r0, .L08017b8c
	str	r0, [sp, #0xc]
	add	r0, sp, #0x78
	str	r0, [sp, #0x2c]
	add.w	r0, r7, #0x30
	str	r0, [sp, #0x90]
	bl	get_word_8_or_zero
	b.n	.L08017b7e
.L08017a1e:
	ldr	r5, [r4]
	str	r4, [sp, #0x4c]
	ldrb	r0, [r4, #4]
	cmp	r0, #1
	beq.n	.L08017a2c
	cbz	r0, .L08017a94
	b.n	.L08017b76
.L08017a2c:
	ldrsh.w	r3, [r5, #0x20]
	ldrh	r0, [r5, #0x1e]
	add	r0, r3
	str	r0, [sp]
	ldrd	r1, r2, [r5, #0x14]
	ldr	r0, [r4, #0xc]
	bl	fn_08022b12
	ldrh	r1, [r5, #0x1c]
	ldrh	r2, [r4, #0x12]
	sxth	r0, r0
	add	r1, r2
	adds	r5, r1, r6
	mov	r8, r0
	bl	sine_q15_degrees
	smulbb	r1, r0, r5
	movw	r9, #0x7fff
	sdiv	r0, r1, r9
	ldrh.w	r1, [sp, #0x7a]
	add	r0, r1
	strh.w	r0, [sp, #0x9a]
	mov	r0, r8
	bl	cosine_q15_degrees
	smulbb	r1, r0, r5
	sdiv	r0, r1, r9
	ldrh.w	r1, [sp, #0x78]
	add	r0, r1
	strh.w	r0, [sp, #0x98]
	ldrh	r0, [r4, #0x14]
	strh.w	r0, [sp, #0x80]
	ldrh	r0, [r4, #0x10]
	strh.w	r0, [sp, #0x82]
	ldrb	r0, [r4, #5]
	cmp	r0, #0xfd
	bls.n	.L08017a96
	mov	r0, r10
	b.n	.L08017a9c
.L08017a94:
	b.n	.L08017ac4
.L08017a96:
	smulbb	r0, r0, r10
	lsrs	r0, r0, #8
.L08017a9c:
	strb.w	r0, [sp, #0x88]
	movs	r0, #1
	str	r0, [sp, #0x40]
	add	r0, sp, #0x80
	str	r0, [sp, #0x20]
	add	r0, sp, #0x98
	str	r0, [sp, #0x30]
	add	r2, sp, #8
	movs	r1, #0x1a
	mov	r0, r7
	bl	fn_080207f4
	add	r3, sp, #0x98
	add	r2, sp, #0x78
	add	r1, sp, #0x80
	mov	r0, r11
	bl	fn_0801e8b8
	b.n	.L08017b6c
.L08017ac4:
	ldr	r0, [r4, #0x10]
	cbz	r0, .L08017b42
	ldrsh.w	r3, [r5, #0x20]
	ldrh	r0, [r5, #0x1e]
	add	r0, r3
	str	r0, [sp]
	ldrd	r1, r2, [r5, #0x14]
	ldr	r0, [r4, #0xc]
	bl	fn_08022b12
	mov	r5, r0
	add	r1, sp, #0x94
	ldr	r0, [r4, #0x10]
	bl	fn_0802187c
	ldrh.w	r0, [sp, #0x78]
	ldrh	r1, [r4, #0x14]
	subs	r1, r0, r1
	strh.w	r1, [sp, #0x58]
	ldrh.w	r0, [sp, #0x7a]
	ldrh	r2, [r4, #0x16]
	subs	r0, r0, r2
	strh.w	r0, [sp, #0x5a]
	ldr	r2, [sp, #0x94]
	ubfx	r3, r2, #0xa, #0xb
	.inst.n	0x1e5b	@ subs r3, r3, #1
	add	r1, r3
	strh.w	r1, [sp, #0x5c]
	mov.w	r1, #0xffffffff
	add.w	r1, r1, r2, lsr #21
	add	r0, r1
	strh.w	r0, [sp, #0x5e]
	ldrb	r0, [r4, #5]
	cmp	r0, #0xfd
	bls.n	.L08017b24
	mov	r0, r10
	b.n	.L08017b2a
.L08017b24:
	smulbb	r0, r0, r10
	lsrs	r0, r0, #8
.L08017b2a:
	strb.w	r0, [sp, #0x6b]
	ldrh	r0, [r4, #0x14]
	strh.w	r0, [sp, #0x64]
	ldrh	r0, [r4, #0x16]
	strh.w	r0, [sp, #0x66]
	add.w	r0, r5, r5, lsl #2
	lsls	r0, r0, #1
	b.n	.L08017b44
.L08017b42:
	b.n	.L08017b76
.L08017b44:
	cmp.w	r0, #0xe10
	ble.n	.L08017b4e
	sub.w	r0, r0, #0xe10
.L08017b4e:
	strh.w	r0, [sp, #0x60]
	add	r0, sp, #0x60
	str	r0, [sp, #0x24]
	add	r2, sp, #8
	movs	r1, #0x1a
	mov	r0, r7
	bl	fn_080207f4
	add	r2, sp, #0x58
	add	r1, sp, #0x60
	mov	r0, r11
	ldr	r3, [r4, #0x10]
	bl	fn_0801e1f0
.L08017b6c:
	add	r2, sp, #8
	movs	r1, #0x1b
	mov	r0, r7
	bl	fn_080207f4
.L08017b76:
	mov	r1, r4
	ldr	r0, [sp, #0x90]
	bl	read_word_at_base_plus_offset
.L08017b7e:
	movs	r4, r0
	bne.w	.L08017a1e
	add	sp, #0xa4
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short	0x0000	@ padding
.L08017b8c:
	.word	d_08050f30

@ ----------------------------------------------------------------------------
@ fn_08017b90 - grows a rectangle by two widths and calls fn_0801578c (body of a
@   handler reached only by the b.w at 0x08020484; its own push {r4, r5, lr} /
@   sub sp, #0x24 frame is at 0x08017b90, the pop at 0x08017c62).
@   r0 = context (kept in r5), r1 = record (kept in r4), r2 = rectangle pointer
@   (4 halfwords). No return value.
@   Returns at once when byte [r4+0x2a] is 2 or below (unsigned) or halfword
@   [r4+0x26] is 0. copy_rect_0801d00c(sp+0x10, r2) copies the rectangle;
@   w = halfword [r4+0x28] - 1; halfwords [sp+0x10] and [sp+0x12] -= w,
@   [sp+0x14] and [sp+0x16] += w; copy_rect_0801d00c(sp+0x18, sp+0x10) copies it
@   again; then halfwords [sp+0x18] and [sp+0x1a] -= halfword [r4+0x26],
@   [sp+0x1c] and [sp+0x1e] += halfword [r4+0x26].
@   W = sxth(h[sp+0x14] - h[sp+0x10] + 1), H = sxth(h[sp+0x16] - h[sp+0x12] + 1);
@   m = signed min(W, H); rad = signed min(ldrsh [r4+0], m asr 1).
@   Calls fn_0801578c(r5, sp+0x18, sp+0x10, sxth(halfword [r4+0x26] + rad),
@   stack [sp+0] = rad, halfword [sp+4] = halfword [r4+0x24], word [sp+8] = byte
@   [r4+0x2a], word [sp+0xc] = byte [r4+2]) and returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_08017b90,"ax",%progbits
	.p2align 2
	.global fn_08017b90
	.thumb_func
	.type fn_08017b90, %function
fn_08017b90:
	push	{r4, r5, lr}
	mov	r5, r0
	ldrb.w	r0, [r1, #0x2a]
	sub	sp, #0x24
	mov	r4, r1
	cmp	r0, #2
	bls.n	.L08017c60
	ldrh	r0, [r4, #0x26]
	cmp	r0, #0
	beq.n	.L08017c60
	mov	r1, r2
	add	r0, sp, #0x10
	bl	copy_rect_0801d00c
	ldrh	r0, [r4, #0x28]
	ldrh.w	r1, [sp, #0x10]
	.inst.n	0x1e40	@ subs r0, r0, #1
	subs	r1, r1, r0
	strh.w	r1, [sp, #0x10]
	ldrh.w	r1, [sp, #0x12]
	subs	r1, r1, r0
	strh.w	r1, [sp, #0x12]
	ldrh.w	r1, [sp, #0x14]
	add	r1, r0
	strh.w	r1, [sp, #0x14]
	ldrh.w	r1, [sp, #0x16]
	add	r0, r1
	strh.w	r0, [sp, #0x16]
	add	r1, sp, #0x10
	add	r0, sp, #0x18
	bl	copy_rect_0801d00c
	ldrh.w	r1, [sp, #0x18]
	ldrh	r0, [r4, #0x26]
	ldrh.w	r2, [sp, #0x12]
	subs	r1, r1, r0
	strh.w	r1, [sp, #0x18]
	ldrh.w	r1, [sp, #0x1c]
	add	r0, r1
	strh.w	r0, [sp, #0x1c]
	ldrh.w	r0, [sp, #0x1a]
	ldrh	r1, [r4, #0x26]
	subs	r0, r0, r1
	strh.w	r0, [sp, #0x1a]
	ldrh.w	r0, [sp, #0x1e]
	ldrh	r1, [r4, #0x26]
	add	r0, r1
	strh.w	r0, [sp, #0x1e]
	ldrh.w	r0, [sp, #0x14]
	ldrh.w	r1, [sp, #0x10]
	subs	r0, r0, r1
	ldrh.w	r1, [sp, #0x16]
	.inst.n	0x1c40	@ adds r0, r0, #1
	subs	r1, r1, r2
	.inst.n	0x1c49	@ adds r1, r1, #1
	sxth	r0, r0
	sxth	r1, r1
	ldrsh.w	r2, [r4]
	cmp	r0, r1
	bge.n	.L08017c36
	mov	r1, r0
.L08017c36:
	cmp.w	r2, r1, asr #1
	ble.n	.L08017c3e
	asrs	r2, r1, #1
.L08017c3e:
	ldrh	r0, [r4, #0x26]
	ldrb	r1, [r4, #2]
	add	r0, r2
	sxth	r3, r0
	ldrb.w	r0, [r4, #0x2a]
	strd	r0, r1, [sp, #8]
	ldrh	r0, [r4, #0x24]
	strh.w	r0, [sp, #4]
	str	r2, [sp]
	add	r2, sp, #0x10
	add	r1, sp, #0x18
	mov	r0, r5
	bl	fn_0801578c
.L08017c60:
	add	sp, #0x24
	pop	{r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_08017c64 - fills the rectangles selected by the q = 0 case, positions
@   computed from sine values (sibling of fn_08017df4 and fn_08017f92).
@   r0 = pointer to a record: word 0 = pointer to two halfwords (centre x,
@   centre y); halfword +4 = R, +6 = angle A0, +8 = angle A1, +0xa = q, +0xc =
@   qp, +0xe = inner radius ri; words +0x10 and +0x14 = arguments 2 and 3 of
@   fn_0801f31c; word +0x18 = context. r1 is unused; the scratch rectangle lives
@   at sp (the push saves r2 and r3 to make room). No return value.
@   S(a) = sine_q15_degrees(a); products are S() * value >> 15; cx, cy = centre.
@   q = 0 and qp = 0 and A0 < A1 (unsigned): one rectangle x0 = cx + S(A1+90) *
@   (R - ri), y0 = cy + S(A0) * (R - ri), x1 = cx + S(A0+90) * R, y1 = cy +
@   S(A1) * R.
@   q = 0 otherwise: rectangle x0 = cx, y0 = cy + S(A0) * (R - ri), x1 = cx +
@   S(A0+90) * R, y1 = cy + R; then, only when qp = 0, the rectangle x0 = cx +
@   S(A1+90) * (R - ri), y0 = cy, x1 = cx + R, y1 = cy + S(A1) * R.
@   q != 0 and qp = 0: only the second rectangle.
@   q != 0 and qp != 0: the full rectangle cx..cx+R, cy..cy+R when (q = qp and
@   A1 < A0) or (q = 2 and qp = 1) or (q = 3 and qp = 1 or 2), else nothing.
@   Each rectangle is intersected with the clip saved from word [context+8] via
@   rect_intersect and, when not empty, word [context+8] is set to it and
@   fn_0801f31c(context, word +0x10, word +0x14) is called; word [context+8] is
@   restored at the end.
@ ----------------------------------------------------------------------------
	.section .text.fn_08017c64,"ax",%progbits
	.p2align 2
	.global fn_08017c64
	.thumb_func
	.type fn_08017c64, %function
fn_08017c64:
	push	{r2, r3, r4, r5, r6, lr}
	mov	r4, r0
	ldr	r0, [r0, #0x18]
	ldrh	r1, [r4, #0xa]
	mov	r5, sp
	ldr	r6, [r0, #8]
	ldrh	r0, [r4, #0xc]
	cbz	r1, .L08017c8e
	cmp	r0, #0
	beq.n	.L08017d44
	cmp	r1, r0
	bne.n	.L08017c84
	ldrh	r2, [r4, #8]
	ldrh	r3, [r4, #6]
	cmp	r2, r3
	bcc.n	.L08017d7e
.L08017c84:
	cmp	r1, #2
	beq.n	.L08017d80
	cmp	r1, #3
	beq.n	.L08017d82
	b.n	.L08017dee
.L08017c8e:
	cbnz	r0, .L08017cd6
	ldrh	r0, [r4, #6]
	ldrh	r1, [r4, #8]
	cmp	r0, r1
	bcs.n	.L08017cd6
	ldrsh.w	r0, [r4, #6]
	bl	sine_q15_degrees
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2
	muls	r0, r1, r0
	ldr	r1, [r4]
	ldrh	r1, [r1, #2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #2]
	ldrh	r0, [r4, #6]
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldrh	r1, [r4, #4]
	smulbb	r0, r0, r1
	ldr	r1, [r4]
	ldrh	r1, [r1]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #4]
	b.n	.L08017d58
.L08017cd6:
	ldr	r0, [r4]
	ldrh	r0, [r0]
	strh.w	r0, [sp]
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	ldrh	r0, [r0, #2]
	add	r0, r1
	strh.w	r0, [sp, #6]
	ldrsh.w	r0, [r4, #6]
	bl	sine_q15_degrees
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2
	muls	r0, r1, r0
	ldr	r1, [r4]
	ldrh	r1, [r1, #2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #2]
	ldrh	r0, [r4, #6]
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldrh	r1, [r4, #4]
	smulbb	r0, r0, r1
	ldr	r1, [r4]
	mov	r2, r6
	ldrh	r1, [r1]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #4]
	mov	r1, sp
	mov	r0, r1
	bl	rect_intersect
	cbz	r0, .L08017d40
	ldr	r0, [r4, #0x18]
	str	r5, [r0, #8]
	ldrd	r2, r0, [r4, #0x14]
	ldr	r1, [r4, #0x10]
	bl	fn_0801f31c
.L08017d40:
	ldrh	r0, [r4, #0xc]
	cbnz	r0, .L08017da2
.L08017d44:
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	ldrh	r0, [r0]
	add	r0, r1
	strh.w	r0, [sp, #4]
	ldr	r0, [r4]
	ldrh	r0, [r0, #2]
	strh.w	r0, [sp, #2]
.L08017d58:
	ldrsh.w	r0, [r4, #8]
	bl	sine_q15_degrees
	ldrh	r1, [r4, #4]
	smulbb	r0, r0, r1
	ldr	r1, [r4]
	ldrh	r1, [r1, #2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #6]
	ldrh	r0, [r4, #8]
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	b.n	.L08017d84
.L08017d7e:
	b.n	.L08017dac
.L08017d80:
	b.n	.L08017da8
.L08017d82:
	b.n	.L08017da4
.L08017d84:
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2
	muls	r0, r1, r0
	ldr	r1, [r4]
	mov	r2, r6
	ldrh	r1, [r1]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp]
	mov	r1, sp
	b.n	.L08017dd8
.L08017da2:
	b.n	.L08017dee
.L08017da4:
	cmp	r0, #2
	beq.n	.L08017dac
.L08017da8:
	cmp	r0, #1
	bne.n	.L08017dee
.L08017dac:
	ldr	r0, [r4]
	mov	r2, r6
	ldrh	r0, [r0]
	strh.w	r0, [sp]
	ldr	r0, [r4]
	ldrh	r0, [r0, #2]
	strh.w	r0, [sp, #2]
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	ldrh	r0, [r0]
	add	r0, r1
	strh.w	r0, [sp, #4]
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	ldrh	r0, [r0, #2]
	add	r0, r1
	strh.w	r0, [sp, #6]
	mov	r1, r5
.L08017dd8:
	mov	r0, r1
	bl	rect_intersect
	cbz	r0, .L08017dee
	ldr	r0, [r4, #0x18]
	str	r5, [r0, #8]
	ldrd	r2, r0, [r4, #0x14]
	ldr	r1, [r4, #0x10]
	bl	fn_0801f31c
.L08017dee:
	ldr	r0, [r4, #0x18]
	str	r6, [r0, #8]
	pop	{r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08017df4 - fills the rectangles selected by the q = 1 case, positions
@   computed from sine values (sibling of fn_08017c64 and fn_08017f92).
@   r0 = pointer to a record: word 0 = pointer to two halfwords (centre x,
@   centre y); halfword +4 = R, +6 = angle A0, +8 = angle A1, +0xa = q, +0xc =
@   qp, +0xe = inner radius ri; words +0x10 and +0x14 = arguments 2 and 3 of
@   fn_0801f31c; word +0x18 = context. r1 is unused; the scratch rectangle lives
@   at sp (the push saves r2 and r3 to make room). No return value.
@   S(a) = sine_q15_degrees(a); products are S() * value >> 15; cx, cy = centre.
@   q = 1 and qp = 1 and A0 < A1 (unsigned): one rectangle x0 = cx + S(A1+90) *
@   R, y0 = cy + S(A1) * (R - ri), x1 = cx + S(A0+90) * (R - ri), y1 = cy +
@   S(A0) * R.
@   q = 1 otherwise: rectangle x0 = cx - R, y0 = cy, x1 = cx + S(A0+90) *
@   (R - ri), y1 = cy + S(A0) * R; then, only when qp = 1, the rectangle x0 =
@   cx + S(A1+90) * R, y0 = cy + S(A1) * (R - ri), x1 = cx - 1, y1 = cy + R.
@   q != 1 and qp = 1: only the second rectangle.
@   q != 1 and qp != 1: full rectangle cx-R..cx-1, cy..cy+R when (q = qp and
@   A1 < A0) or (q = 0 and qp = 2 or 3) or (q = 3 and qp = 2), else nothing.
@   Each rectangle is intersected with the clip saved from word [context+8] via
@   rect_intersect and, when not empty, word [context+8] is set to it and
@   fn_0801f31c(context, word +0x10, word +0x14) is called; word [context+8] is
@   restored at the end.
@ ----------------------------------------------------------------------------
	.section .text.fn_08017df4,"ax",%progbits
	.global fn_08017df4
	.thumb_func
	.type fn_08017df4, %function
fn_08017df4:
	push	{r2, r3, r4, r5, r6, lr}
	mov	r4, r0
	ldr	r0, [r0, #0x18]
	ldrh	r1, [r4, #0xa]
	mov	r5, sp
	ldr	r6, [r0, #8]
	ldrh	r0, [r4, #0xc]
	cmp	r1, #1
	beq.n	.L08017e20
	cmp	r0, #1
	beq.n	.L08017eda
	cmp	r1, r0
	bne.n	.L08017e16
	ldrh	r2, [r4, #8]
	ldrh	r3, [r4, #6]
	cmp	r2, r3
	bcc.n	.L08017f14
.L08017e16:
	cmp	r1, #0
	beq.n	.L08017f16
	cmp	r1, #3
	beq.n	.L08017f18
	b.n	.L08017f8c
.L08017e20:
	cmp	r0, #1
	bne.n	.L08017e6a
	ldrh	r0, [r4, #6]
	ldrh	r1, [r4, #8]
	cmp	r0, r1
	bcs.n	.L08017e6a
	ldrsh.w	r0, [r4, #6]
	bl	sine_q15_degrees
	ldrh	r1, [r4, #4]
	smulbb	r0, r0, r1
	ldr	r1, [r4]
	ldrh	r1, [r1, #2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #6]
	ldrh	r0, [r4, #6]
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2
	muls	r0, r1, r0
	ldr	r1, [r4]
	ldrh	r1, [r1]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #4]
	b.n	.L08017ef0
.L08017e6a:
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	ldrh	r0, [r0]
	subs	r0, r0, r1
	strh.w	r0, [sp]
	ldr	r0, [r4]
	ldrh	r0, [r0, #2]
	strh.w	r0, [sp, #2]
	ldrsh.w	r0, [r4, #6]
	bl	sine_q15_degrees
	ldrh	r1, [r4, #4]
	smulbb	r0, r0, r1
	ldr	r1, [r4]
	ldrh	r1, [r1, #2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #6]
	ldrh	r0, [r4, #6]
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2
	muls	r0, r1, r0
	ldr	r1, [r4]
	mov	r2, r6
	ldrh	r1, [r1]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #4]
	mov	r1, sp
	mov	r0, r1
	bl	rect_intersect
	cbz	r0, .L08017ed4
	ldr	r0, [r4, #0x18]
	str	r5, [r0, #8]
	ldrd	r2, r0, [r4, #0x14]
	ldr	r1, [r4, #0x10]
	bl	fn_0801f31c
.L08017ed4:
	ldrh	r0, [r4, #0xc]
	cmp	r0, #1
	bne.n	.L08017f8c
.L08017eda:
	ldr	r0, [r4]
	ldrh	r0, [r0]
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #4]
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	ldrh	r0, [r0, #2]
	add	r0, r1
	strh.w	r0, [sp, #6]
.L08017ef0:
	ldrsh.w	r0, [r4, #8]
	bl	sine_q15_degrees
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2
	muls	r0, r1, r0
	ldr	r1, [r4]
	ldrh	r1, [r1, #2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #2]
	ldrh	r0, [r4, #8]
	b.n	.L08017f1a
.L08017f14:
	b.n	.L08017f48
.L08017f16:
	b.n	.L08017f3a
.L08017f18:
	b.n	.L08017f44
.L08017f1a:
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldrh	r1, [r4, #4]
	smulbb	r0, r0, r1
	ldr	r1, [r4]
	mov	r2, r6
	ldrh	r1, [r1]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp]
	mov	r1, sp
	b.n	.L08017f76
.L08017f3a:
	cmp	r0, #2
	beq.n	.L08017f48
	cmp	r0, #3
	beq.n	.L08017f48
	b.n	.L08017f8c
.L08017f44:
	cmp	r0, #2
	bne.n	.L08017f8c
.L08017f48:
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	mov	r2, r6
	ldrh	r0, [r0]
	subs	r0, r0, r1
	strh.w	r0, [sp]
	ldr	r0, [r4]
	ldrh	r0, [r0, #2]
	strh.w	r0, [sp, #2]
	ldr	r0, [r4]
	ldrh	r0, [r0]
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #4]
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	ldrh	r0, [r0, #2]
	add	r0, r1
	strh.w	r0, [sp, #6]
	mov	r1, r5
.L08017f76:
	mov	r0, r1
	bl	rect_intersect
	cbz	r0, .L08017f8c
	ldr	r0, [r4, #0x18]
	str	r5, [r0, #8]
	ldrd	r2, r0, [r4, #0x14]
	ldr	r1, [r4, #0x10]
	bl	fn_0801f31c
.L08017f8c:
	ldr	r0, [r4, #0x18]
	str	r6, [r0, #8]
	pop	{r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08017f92 - fills the rectangles selected by the q = 2 case, positions
@   computed from sine values (sibling of fn_08017c64 and fn_08017df4).
@   r0 = pointer to a record: word 0 = pointer to two halfwords (centre x,
@   centre y); halfword +4 = R, +6 = angle A0, +8 = angle A1, +0xa = q, +0xc =
@   qp, +0xe = inner radius ri; words +0x10 and +0x14 = arguments 2 and 3 of
@   fn_0801f31c; word +0x18 = context. r1 is unused; the scratch rectangle lives
@   at sp (the push saves r2 and r3 to make room). No return value.
@   S(a) = sine_q15_degrees(a); products are S() * value >> 15; cx, cy = centre.
@   q = 2 and qp = 2 and A0 < A1 (unsigned): one rectangle x0 = cx + S(A0+90) *
@   R, y0 = cy + S(A1) * R, x1 = cx + S(A1+90) * (R - ri), y1 = cy + S(A0) *
@   (R - ri).
@   q = 2 otherwise: rectangle x0 = cx + S(A0+90) * R, y0 = cy - R, x1 = cx - 1,
@   y1 = cy + S(A0) * (R - ri); then, only when qp = 2, the rectangle x0 = cx -
@   R, y0 = cy + S(A1) * R, x1 = cx + S(A1+90) * (R - ri), y1 = cy - 1.
@   q != 2 and qp = 2: only the second rectangle.
@   q != 2 and qp != 2: full rectangle cx-R..cx-1, cy-R..cy-1 when (q = qp and
@   A1 < A0) or (q = 0 and qp = 3) or (q = 1 and qp = 0 or 3), else nothing
@   (q = 3 draws nothing).
@   Each rectangle is intersected with the clip saved from word [context+8] via
@   rect_intersect and, when not empty, word [context+8] is set to it and
@   fn_0801f31c(context, word +0x10, word +0x14) is called; word [context+8] is
@   restored at the end.
@ ----------------------------------------------------------------------------
	.section .text.fn_08017f92,"ax",%progbits
	.global fn_08017f92
	.thumb_func
	.type fn_08017f92, %function
fn_08017f92:
	push	{r2, r3, r4, r5, r6, lr}
	mov	r4, r0
	ldr	r0, [r0, #0x18]
	ldrh	r1, [r4, #0xa]
	mov	r5, sp
	ldr	r6, [r0, #8]
	ldrh	r0, [r4, #0xc]
	cmp	r1, #2
	beq.n	.L08017fbe
	cmp	r0, #2
	beq.n	.L080180a6
	cmp	r1, r0
	bne.n	.L08017fb4
	ldrh	r2, [r4, #8]
	ldrh	r3, [r4, #6]
	cmp	r2, r3
	bcc.n	.L080180a8
.L08017fb4:
	cmp	r1, #0
	beq.n	.L080180aa
	cmp	r1, #1
	beq.n	.L080180ac
	b.n	.L08018168
.L08017fbe:
	cmp	r0, #2
	bne.n	.L08018042
	ldrh	r0, [r4, #6]
	ldrh	r1, [r4, #8]
	cmp	r0, r1
	bcs.n	.L08018042
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldrh	r1, [r4, #4]
	smulbb	r0, r0, r1
	ldr	r1, [r4]
	ldrh	r1, [r1]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp]
	ldrsh.w	r0, [r4, #6]
	bl	sine_q15_degrees
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2
	muls	r0, r1, r0
	ldr	r1, [r4]
	ldrh	r1, [r1, #2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #6]
	ldrsh.w	r0, [r4, #8]
	bl	sine_q15_degrees
	ldrh	r1, [r4, #4]
	smulbb	r0, r0, r1
	ldr	r1, [r4]
	ldrh	r1, [r1, #2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #2]
	ldrh	r0, [r4, #8]
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2
	muls	r0, r1, r0
	ldr	r1, [r4]
	ldrh	r1, [r1]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #4]
	b.n	.L08018110
.L08018042:
	ldr	r0, [r4]
	ldrh	r0, [r0]
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #4]
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	ldrh	r0, [r0, #2]
	subs	r0, r0, r1
	strh.w	r0, [sp, #2]
	ldrh	r0, [r4, #6]
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldrh	r1, [r4, #4]
	smulbb	r0, r0, r1
	ldr	r1, [r4]
	ldrh	r1, [r1]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp]
	ldrsh.w	r0, [r4, #6]
	bl	sine_q15_degrees
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2
	muls	r0, r1, r0
	ldr	r1, [r4]
	mov	r2, r6
	ldrh	r1, [r1, #2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #6]
	mov	r1, sp
	mov	r0, r1
	bl	rect_intersect
	cbz	r0, .L080180b8
	ldr	r0, [r4, #0x18]
	str	r5, [r0, #8]
	b.n	.L080180ae
.L080180a6:
	b.n	.L080180be
.L080180a8:
	b.n	.L08018122
.L080180aa:
	b.n	.L08018116
.L080180ac:
	b.n	.L0801811c
.L080180ae:
	ldrd	r2, r0, [r4, #0x14]
	ldr	r1, [r4, #0x10]
	bl	fn_0801f31c
.L080180b8:
	ldrh	r0, [r4, #0xc]
	cmp	r0, #2
	bne.n	.L08018168
.L080180be:
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	ldrh	r0, [r0]
	subs	r0, r0, r1
	strh.w	r0, [sp]
	ldr	r0, [r4]
	ldrh	r0, [r0, #2]
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #6]
	ldrh	r0, [r4, #8]
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2
	muls	r0, r1, r0
	ldr	r1, [r4]
	ldrh	r1, [r1]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #4]
	ldrsh.w	r0, [r4, #8]
	bl	sine_q15_degrees
	ldrh	r1, [r4, #4]
	smulbb	r0, r0, r1
	ldr	r1, [r4]
	ldrh	r1, [r1, #2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #2]
.L08018110:
	mov	r2, r6
	mov	r1, sp
	b.n	.L08018152
.L08018116:
	cmp	r0, #3
	beq.n	.L08018122
	b.n	.L08018168
.L0801811c:
	cmp	r0, #3
	beq.n	.L08018122
	cbnz	r0, .L08018168
.L08018122:
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	mov	r2, r6
	ldrh	r0, [r0]
	subs	r0, r0, r1
	strh.w	r0, [sp]
	ldr	r0, [r4]
	ldrh	r1, [r4, #4]
	ldrh	r0, [r0, #2]
	subs	r0, r0, r1
	strh.w	r0, [sp, #2]
	ldr	r0, [r4]
	mov	r1, r5
	ldrh	r0, [r0]
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #4]
	ldr	r0, [r4]
	ldrh	r0, [r0, #2]
	.inst.n	0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #6]
.L08018152:
	mov	r0, r1
	bl	rect_intersect
	cbz	r0, .L08018168
	ldr	r0, [r4, #0x18]
	str	r5, [r0, #8]
	ldrd	r2, r0, [r4, #0x14]
	ldr	r1, [r4, #0x10]
	bl	fn_0801f31c
.L08018168:
	ldr	r0, [r4, #0x18]
	str	r6, [r0, #8]
	pop	{r2, r3, r4, r5, r6, pc}
