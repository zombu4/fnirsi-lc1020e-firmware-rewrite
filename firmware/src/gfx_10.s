@ gfx_10.s - graphics routines: axis tick and label drawing, RGB565 pixel-run blending and per-pixel callbacks, rectangle copy helpers
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0801a0a0 - draws the tick marks (and optional numeric labels) of one axis
@ side of an object.
@   r0 = object pointer (kept in r4), r1 = drawing target (saved in the frame
@   at sp+0xe4), r2 = side selector (kept in r8): 0 selects the left variant,
@   non-zero the other; the value 1 negates the two tick lengths. No return
@   value.
@ r5 = base_plus_offset_by_index(r0, r2) is a descriptor: halfwords [r5] and
@ [r5+2] are the major and minor tick lengths, word [r5+4] holds the major
@ tick interval in bits 16..30, halfword [r5+8] holds the label count in bits
@ 0..14 and the "draw labels" flag in bit 15. Returns at once (0x0801a1a4)
@ when (word [r5+8] & 0x7fff) is 1 or less, or when bit 15 of word [r5+8] is
@ clear and halfwords [r5] and [r5+2] are both 0.
@ Frame setup: word sp+0xa4 = 1 when r2 is non-zero else 0;
@   r7 = fn_0802499c(r0, 0), r6 = fn_08024b88(r0, 0);
@   word sp+0xac = signed bits 8..23 of fn_08023e48(r0) * halfword [r0+0x86];
@   word sp+0xc8 = sxth(r6 + r7 + halfword [r0+0x16] - fn_08024208(r0)).
@ Side 0: word sp+0x98 = fn_08024af8(r0, 0x60000), edge fp (r11) = short
@ [r0+0x14]; other sides: word sp+0x98 = fn_08024b34(r0, 0x60000), fp = short
@ [r0+0x18]. sl (r10) = short [r5], r9 = short [r5+2], both negated (sxth)
@ when r2 is 1.
@ Calls fn_0801e8d2(sp+0x84), fn_080250b6(r0, 0x60000, sp+0x84),
@ fn_0801e7b4(sp+0x60), fn_0802501a(r0, 0x60000, sp+0x60) and
@ fn_08023a0c(sp+0x0c, target); stores the word at 0x0801a358 (0x08050f14) at
@ sp+0x10, 6 at sp+0x14, sp+0x84 at sp+0x24, sp+0x60 at sp+0x20, 0x60000 at
@ sp+0x40 and r2 at sp+0x44.
@ r7 = ((halfword [r5+8] & 0x7fff) - 1) * ((word [r5+4] >> 16) & 0x7fff) =
@ tick count; the loop runs i = r6 = 0 to r7 inclusive (unsigned compare at
@ 0x0801a34c).
@ Per tick (0x0801a1a8): y = sp+0xc8 + (sp+0xac - short [sp+0x86]) * i / r7
@ (udiv), stored in halfwords sp+0x56 and sp+0x5e; x1 (sp+0x54) = fp - 1 for
@ r2 = 0, fp + 1 otherwise; x2 (sp+0x5c) = x1 - sl when i is a multiple of
@ the interval ((word [r5+4] >> 16) & 0x7fff; major tick) else x1 - r9;
@ pointers sp+0x54 and sp+0x5c are stored at sp+0x30 and sp+0x34.
@ Value = fn_08022b12(r7 - i, 0, r7, short [r0 + 0x6c + 2*(r2 != 0)], stack
@ argument short [r0 + 0x70 + 2*(r2 != 0)]), stored at sp+0x4c.
@ Major tick with bit 15 of halfword [r5+8] set: fn_0801033c(sp+0xcc, 16,
@ "%d", value) formats the label; sp+0x20 = sp+0x60, sp+0x38 = sp+0xcc,
@ sp+0x3c = 16; fn_080207f4(r0, 0x1a, sp+0x0c); fn_08027d30(sp+0xb0, label,
@ word [sp+0x60], short [sp+0x74], stack: short [sp+0x72], 0x1fff, 0)
@ measures it; the label y rectangle = tick y -/+ (short [sp+0xb2] / 2) in
@ halfwords sp+0x92 and sp+0x96; the label x (sp+0x90, sp+0x94) = x2 - width
@ - sp+0x98 .. x2 - sp+0x98 for r2 = 0 and x2 + sp+0x98 .. x2 + sp+0x98 +
@ width otherwise (width = halfword [sp+0xb0]); when y2 is not below short
@ [r0+0x16] and y1 is not above short [r0+0x1a] it calls fn_0801e274(target,
@ sp+0x60, sp+0x90, label, 0).
@ Minor ticks and major ticks without bit 15 (0x0801a2fa): sp+0x20, sp+0x38,
@ sp+0x3c = 0 and fn_080207f4(r0, 0x1a, sp+0x0c).
@ Every tick (0x0801a30c): when tick y + half of short [sp+0x86] is not below
@ short [r0+0x16] and tick y - half of it is not above short [r0+0x1a], it
@ calls fn_0801e8b8(target, sp+0x84, sp+0x54, sp+0x5c) to draw the tick; then
@ fn_080207f4(r0, 0x1b, sp+0x0c) and i++.
@ Epilogue 0x0801a352: add sp, #236; pop r4-r11, pc.
@ The word 0x08050f14 at 0x0801a358 and the string "%d" at 0x0801a35c are
@ read by this function and lie after the body.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801a0a0,"ax",%progbits
	.p2align 2
	.global fn_0801a0a0
	.thumb_func
	.type fn_0801a0a0, %function
fn_0801a0a0:
	push.w {r0, r1, r2, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0xe0
	mov r8, r2
	mov r4, r0
	mov r1, r2
	bl base_plus_offset_by_index
	mov r5, r0
	ldr r0, [r0, #0x8]
	ubfx r1, r0, #0, #0xf
	cmp r1, #1
	bls.n .L0801a1a4
	lsls r0, r0, #0x10
	bmi.n .L0801a0ca
	ldrh r0, [r5, #0]
	cbnz r0, .L0801a0ca
	ldrh r0, [r5, #2]
	cmp r0, #0
	beq.n .L0801a1a4
.L0801a0ca:
	movs.w r0, r8
	beq.n .L0801a0d2
	movs r0, #1
.L0801a0d2:
	str r0, [sp, #0xa4]
	movs r1, #0
	mov r0, r4
	bl fn_0802499c
	mov r7, r0
	movs r1, #0
	mov r0, r4
	bl fn_08024b88
	mov r6, r0
	mov r0, r4
	bl fn_08023e48
	ldrh.w r1, [r4, #0x86]
	muls r0, r1, r0
	sbfx r0, r0, #8, #0x10
	str r0, [sp, #0xac]
	mov r0, r4
	bl fn_08024208
	mov r1, r0
	ldrh r2, [r4, #0x16]
	adds r0, r6, r7
	add r0, r2
	subs r0, r0, r1
	sxth r0, r0
	mov.w r6, #0x60000
	str r0, [sp, #0xc8]
	cmp.w r8, #0
	mov r1, r6
	mov r0, r4
	beq.n .L0801a138
	bl fn_08024b34
	str r0, [sp, #0x98]
	ldrsh.w r0, [r4, #0x18]
.L0801a126:
	ldrsh.w r10, [r5, #0]
	ldrsh.w r9, [r5, #2]
	mov r11, r0
	cmp.w r8, #1
	beq.n .L0801a144
	b.n .L0801a154
.L0801a138:
	bl fn_08024af8
	str r0, [sp, #0x98]
	ldrsh.w r0, [r4, #0x14]
	b.n .L0801a126
.L0801a144:
	rsb.w r0, r10, #0
	sxth.w r10, r0
	rsb.w r0, r9, #0
	sxth.w r9, r0
.L0801a154:
	add r0, sp, #0x84
	bl fn_0801e8d2
	add r2, sp, #0x84
	mov r1, r6
	mov r0, r4
	bl fn_080250b6
	add r0, sp, #0x60
	bl fn_0801e7b4
	add r2, sp, #0x60
	mov r1, r6
	mov r0, r4
	bl fn_0802501a
	add r0, sp, #0xc
	ldr r1, [sp, #0xe4]
	bl fn_08023a0c
	ldr r0, .L0801a358
	str r0, [sp, #0x10]
	movs r0, #6
	str r0, [sp, #0x14]
	add r0, sp, #0x84
	str r0, [sp, #0x24]
	strd r6, r8, [sp, #0x40]
	add r0, sp, #0x60
	str r0, [sp, #0x20]
	ldrh r0, [r5, #0x8]
	ubfx r7, r0, #0, #0xf
	ldr r0, [r5, #0x4]
	.inst.n 0x1e7f  @ subs r7, r7, #1
	ubfx r0, r0, #0x10, #0xf
	muls r7, r0, r7
	movs r6, #0
	b.n .L0801a34c
.L0801a1a4:
	b.n .L0801a352
	nop  @ padding
.L0801a1a8:
	ldrsh.w r1, [sp, #0x86]
	ldr r0, [sp, #0xac]
	subs r0, r0, r1
	muls r0, r6, r0
	udiv r1, r0, r7
	ldr r0, [sp, #0xc8]
	cmp.w r8, #0
	add r0, r1
	strh.w r0, [sp, #0x56]
	strh.w r0, [sp, #0x5e]
	mov r0, r11
	strh.w r11, [sp, #0x54]
	beq.n .L0801a2a2
	.inst.n 0x1c40  @ adds r0, r0, #1
.L0801a1d0:
	strh.w r0, [sp, #0x54]
	movs r0, #0
	str r0, [sp, #0x8]
	ldr r0, [r5, #0x4]
	ubfx r0, r0, #0x10, #0xf
	udiv r1, r6, r0
	mls r0, r0, r1, r6
	cmp r0, #0
	beq.n .L0801a2d4
	ldrh.w r1, [sp, #0x54]
	sub.w r0, r1, r9
	nop
.L0801a1f4:
	strh.w r0, [sp, #0x5c]
	add r0, sp, #0x54
	str r0, [sp, #0x30]
	add r0, sp, #0x5c
	str r0, [sp, #0x34]
	ldr r0, [sp, #0xa4]
	mov r2, r7
	add.w r0, r4, r0, lsl #1
	ldrsh.w r1, [r0, #0x70]
	str r1, [sp, #0]
	ldrsh.w r3, [r0, #0x6c]
	subs r0, r7, r6
	movs r1, #0
	bl fn_08022b12
	mov r3, r0
	str r0, [sp, #0x4c]
	ldr r0, [sp, #0x8]
	cbz r0, .L0801a2a0
	ldrh r0, [r5, #0x8]
	lsls r0, r0, #0x10
	bpl.n .L0801a2fa
	adr r2, .L0801a35c
	movs r1, #0x10
	add r0, sp, #0xcc
	bl fn_0801033c
	add r0, sp, #0x60
	str r0, [sp, #0x20]
	add r0, sp, #0xcc
	str r0, [sp, #0x38]
	movs r0, #0x10
	str r0, [sp, #0x3c]
	add r2, sp, #0xc
	movs r1, #0x1a
	mov r0, r4
	bl fn_080207f4
	ldrsh.w r0, [sp, #0x72]
	movs r2, #0
	movw r1, #0x1fff
	stm.w sp, {r0, r1, r2}
	ldrsh.w r3, [sp, #0x74]
	add r0, sp, #0xb0
	ldr r2, [sp, #0x60]
	ldr r1, [sp, #0x38]
	bl fn_08027d30
	ldrsh.w r0, [sp, #0xb2]
	ldrh.w r1, [sp, #0x5e]
	add.w r0, r0, r0, lsr #31
	sub.w r2, r1, r0, asr #1
	sxth r2, r2
	add.w r0, r1, r0, asr #1
	strh.w r2, [sp, #0x92]
	sxth r1, r0
	ldr r0, [sp, #0xa4]
	strh.w r1, [sp, #0x96]
	cmp r0, #0
	ldrh.w r0, [sp, #0x5c]
	beq.n .L0801a2e2
	ldr r3, [sp, #0x98]
	add r3, r0
	strh.w r3, [sp, #0x90]
	ldrh.w r3, [sp, #0xb0]
	add r3, r0
	ldr r0, [sp, #0x98]
	b.n .L0801a2a4
.L0801a2a0:
	b.n .L0801a2fa
.L0801a2a2:
	b.n .L0801a2d0
.L0801a2a4:
	add.w r0, r0, r3
.L0801a2a8:
	strh.w r0, [sp, #0x94]
	ldrsh.w r0, [r4, #0x16]
	cmp r1, r0
	blt.n .L0801a30c
	ldrsh.w r0, [r4, #0x1a]
	cmp r2, r0
	bgt.n .L0801a30c
	movs r0, #0
	str r0, [sp, #0]
	add r2, sp, #0x90
	add r1, sp, #0x60
	ldr r3, [sp, #0x38]
	ldr r0, [sp, #0xe4]
	bl fn_0801e274
	b.n .L0801a30c
	b.n .L0801a2d4
.L0801a2d0:
	.inst.n 0x1e40  @ subs r0, r0, #1
	b.n .L0801a1d0
.L0801a2d4:
	movs r0, #1
	ldrh.w r1, [sp, #0x54]
	str r0, [sp, #0x8]
	sub.w r0, r1, r10
	b.n .L0801a1f4
.L0801a2e2:
	ldrh.w r3, [sp, #0xb0]
	sub.w r12, r0, r3
	ldr r3, [sp, #0x98]
	sub.w r3, r12, r3
	strh.w r3, [sp, #0x90]
	ldr r3, [sp, #0x98]
	subs r0, r0, r3
	b.n .L0801a2a8
.L0801a2fa:
	movs r0, #0
	str r0, [sp, #0x20]
	str r0, [sp, #0x38]
	str r0, [sp, #0x3c]
	add r2, sp, #0xc
	movs r1, #0x1a
	mov r0, r4
	bl fn_080207f4
.L0801a30c:
	ldrsh.w r0, [sp, #0x86]
	ldrsh.w r1, [sp, #0x56]
	add.w r0, r0, r0, lsr #31
	ldrsh.w r2, [r4, #0x16]
	add.w r1, r1, r0, asr #1
	cmp r1, r2
	blt.n .L0801a340
	ldrsh.w r1, [sp, #0x5e]
	sub.w r1, r1, r0, asr #1
	ldrsh.w r0, [r4, #0x1a]
	cmp r1, r0
	bgt.n .L0801a340
	add r3, sp, #0x5c
	add r2, sp, #0x54
	add r1, sp, #0x84
	ldr r0, [sp, #0xe4]
	bl fn_0801e8b8
.L0801a340:
	add r2, sp, #0xc
	movs r1, #0x1b
	mov r0, r4
	bl fn_080207f4
	.inst.n 0x1c76  @ adds r6, r6, #1
.L0801a34c:
	cmp r6, r7
	bls.w .L0801a1a8
.L0801a352:
	add sp, #0xec
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801a358:
	.word d_08050f14
.L0801a35c:
	.asciz "%d"
	.byte 0x00  @ padding

@ ----------------------------------------------------------------------------
@ fn_0801a498 - blends a colour into a rectangle of RGB565 pixels through a
@ selectable pixel function.
@   r0 = pointer to RGB565 halfword pixels, r1 = rectangle of 4 shorts (left,
@   top, right, bottom), r2 = row stride in halfwords (saved in the frame),
@   r3 = colour (saved in the frame), stack: param_5 = alpha (r11), param_6 =
@   optional alpha mask byte pointer (r8), param_7 = mask row stride, param_8
@   = blend mode (1, 2 or 3). No return value.
@ Width (r7) and height (r9) are right-left+1 and bottom-top+1 (sxth). Mode 1
@ selects the pixel function fn_08014a26, mode 2 fn_08014b00, mode 3
@ fn_08014a9a (from the three literal words at 0x0801a5d8..0x0801a5e0); any
@ other mode returns. The selected function is called as (colour, pixel,
@ alpha) through blx r6.
@ Without a mask: calls the function once per distinct pixel value and
@ rewrites each pixel of every row, caching the last source pixel.
@ With a mask: skips pixels whose mask byte is 0; the effective alpha is
@ mask*alpha>>8 for mask bytes below 0xfd, else alpha; the result is cached
@ by mask byte and pixel value; the pixel pointer advances by the row stride
@ and the mask pointer by the mask stride per row.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801a498,"ax",%progbits
	.p2align 2
	.global fn_0801a498
	.thumb_func
	.type fn_0801a498, %function
fn_0801a498:
	push.w {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	ldrh r2, [r1, #0x4]
	ldrh r3, [r1, #0]
	sub sp, #0x24
	subs r2, r2, r3
	.inst.n 0x1c52  @ adds r2, r2, #1
	sxth r7, r2
	ldrh r2, [r1, #0x6]
	ldrh r1, [r1, #0x2]
	mov r4, r0
	subs r1, r2, r1
	ldrd r11, r8, [sp, #0x58]
	.inst.n 0x1c49  @ adds r1, r1, #1
	ldr r0, [sp, #0x64]
	sxth.w r9, r1
	cmp r0, #1
	beq.n .L0801a4e8
	cmp r0, #2
	beq.n .L0801a4ec
	cmp r0, #3
	bne.n .L0801a550
	ldr r6, .L0801a5d8
	nop
.L0801a4cc:
	movs.w r0, r8
	beq.n .L0801a4f0
	movs r0, #0
	str r0, [sp, #0x18]
	ldrh r0, [r4, #0]
	strh.w r0, [sp, #0x14]
	ldrb.w r0, [r8, #0]
	cmp r0, #0xfd
	bcc.n .L0801a556
	mov r2, r11
	b.n .L0801a55c
.L0801a4e8:
	ldr r6, .L0801a5dc
	b.n .L0801a4cc
.L0801a4ec:
	ldr r6, .L0801a5e0
	b.n .L0801a4cc
.L0801a4f0:
	ldrh r0, [r4, #0]
	strh.w r0, [sp, #0]
	strh.w r0, [sp, #8]
	mov r2, r11
	ldr r1, [sp, #0]
	ldr r0, [sp, #0x30]
	blx r6
	str r0, [sp, #0x14]
	movs r0, #0
	b.n .L0801a54a
.L0801a508:
	movs r5, #0
	b.n .L0801a53c
.L0801a50c:
	ldrh.w r0, [sp, #8]
	ldrh.w r1, [r4, r5, lsl #1]
	cmp r0, r1
	beq.n .L0801a530
	add.w r0, r4, r5, lsl #1
	mov r2, r11
	ldrh r0, [r0, #0]
	strh.w r0, [sp, #0x14]
	strh.w r0, [sp, #8]
	ldr r1, [sp, #0x14]
	ldr r0, [sp, #0x30]
	blx r6
	str r0, [sp, #0x14]
.L0801a530:
	add.w r0, r4, r5, lsl #1
	ldrh.w r1, [sp, #0x14]
	strh r1, [r0, #0]
	.inst.n 0x1c6d  @ adds r5, r5, #1
.L0801a53c:
	cmp r5, r7
	blt.n .L0801a50c
	ldr r0, [sp, #0x2c]
	add.w r4, r4, r0, lsl #1
	add.w r0, r8, #1
.L0801a54a:
	mov r8, r0
	cmp r0, r9
	blt.n .L0801a508
.L0801a550:
	add sp, #0x34
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801a556:
	mul r0, r0, r11
	lsrs r2, r0, #8
.L0801a55c:
	ldr r1, [sp, #0x14]
	ldr r0, [sp, #0x30]
	blx r6
	str r0, [sp, #0x20]
	movs r0, #0
	b.n .L0801a5d0
.L0801a568:
	movs r5, #0
	b.n .L0801a5be
.L0801a56c:
	ldrb.w r0, [r8, r5]
	cbz r0, .L0801a5bc
	ldr r1, [sp, #0x18]
	cmp r0, r1
	bne.n .L0801a584
	ldrh.w r1, [sp, #0x14]
	ldrh.w r2, [r4, r5, lsl #1]
	cmp r1, r2
	beq.n .L0801a5b2
.L0801a584:
	cmp r0, #0xfd
	bcc.n .L0801a58c
	mov r2, r11
	b.n .L0801a592
.L0801a58c:
	mul r0, r0, r11
	lsrs r2, r0, #8
.L0801a592:
	add.w r0, r4, r5, lsl #1
	ldrh r0, [r0, #0]
	strh.w r0, [sp, #0x18]
	ldr r1, [sp, #0x18]
	ldr r0, [sp, #0x30]
	blx r6
	str r0, [sp, #0x20]
	ldrb.w r0, [r8, r5]
	str r0, [sp, #0x18]
	ldrh.w r0, [r4, r5, lsl #1]
	strh.w r0, [sp, #0x14]
.L0801a5b2:
	add.w r0, r4, r5, lsl #1
	ldrh.w r1, [sp, #0x20]
	strh r1, [r0, #0]
.L0801a5bc:
	.inst.n 0x1c6d  @ adds r5, r5, #1
.L0801a5be:
	cmp r5, r7
	blt.n .L0801a56c
	ldr r0, [sp, #0x2c]
	ldr r1, [sp, #0x60]
	add.w r4, r4, r0, lsl #1
	add r8, r1
	add.w r0, r10, #1
.L0801a5d0:
	mov r10, r0
	cmp r0, r9
	blt.n .L0801a568
	b.n .L0801a550
.L0801a5d8:
	.word fn_08014a9a
.L0801a5dc:
	.word fn_08014a26
.L0801a5e0:
	.word fn_08014b00

@ ----------------------------------------------------------------------------
@ fn_0801a5e4 - blends a colour into a rectangle of RGB565 pixels, with an
@ optional alpha mask.
@   r0 = pointer to RGB565 halfword pixels (r4), r1 = rectangle of 4 shorts
@   (left, top, right, bottom), r2 = row stride in halfwords (frame sp+0x14),
@   r3 = colour halfword (frame sp+0x18), stack: param_5 = alpha (r10),
@   param_6 = optional mask byte pointer (r6), param_7 = mask stride (frame
@   sp+0x48). No return value. Width (r5) and height (r9) are
@   right-left+1 and bottom-top+1.
@ Without a mask and alpha below 0xfd: blends each pixel with the colour using
@ the weight w = (((alpha+4)>>3) & 0x1f) << 3; each RGB565 component becomes
@ (pixel*(255-w) + colour*w) * 0x8081 >> 23 (5-bit red and blue, 6-bit green),
@ caching on the previous source pixel; the first call is
@ blend_565_0801d9dc(colour, 0, alpha).
@ Without a mask and alpha 0xfd or above: fills each row with
@ fill_halfwords(row, colour, width).
@ With a mask and alpha below 0xfd: blends per pixel with blend_565_0801d9dc,
@ skipping mask byte 0; the effective alpha is mask*alpha>>8 (mask 0xff uses
@ alpha); the result is cached by mask byte and pixel value.
@ With a mask and alpha 0xfd or above: handles 4 mask bytes at a time, writing
@ the colour directly for mask word 0xffffffff (one word-pair store when the
@ pixel pointer is 4-aligned, else halfword/word/halfword stores), skipping a
@ zero word, and otherwise per pixel (0xff = colour, else
@ blend_565_0801d9dc), with scalar head loop (until the mask pointer is
@ 4-aligned) and tail loop.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801a5e4,"ax",%progbits
	.p2align 2
	.global fn_0801a5e4
	.thumb_func
	.type fn_0801a5e4, %function
fn_0801a5e4:
	push.w {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov r4, r0
	ldrh r0, [r1, #0x4]
	ldrh r2, [r1, #0]
	sub sp, #0xc
	subs r0, r0, r2
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r5, r0
	ldrh r0, [r1, #0x6]
	ldrh r1, [r1, #0x2]
	ldrd r10, r6, [sp, #0x40]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth.w r9, r0
	cbz r6, .L0801a626
	ldrh.w r0, [sp, #0x18]
	cmp.w r10, #0xfd
	add.w r0, r0, r0, lsl #16
	str r0, [sp, #0]
	bcc.n .L0801a712
	sub.w r8, r5, #4
	mov.w r11, #0
	ldrh.w r10, [sp, #0x18]
	b.n .L0801a896
.L0801a626:
	cmp.w r10, #0xfd
	bcc.n .L0801a64c
	movs r6, #0
	b.n .L0801a642
.L0801a630:
	mov r2, r5
	mov r0, r4
	ldr r1, [sp, #0x18]
	bl fill_halfwords
	ldr r0, [sp, #0x14]
	.inst.n 0x1c76  @ adds r6, r6, #1
	add.w r4, r4, r0, lsl #1
.L0801a642:
	cmp r6, r9
	blt.n .L0801a630
.L0801a646:
	add sp, #0x1c
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801a64c:
	ldrh.w r1, [sp, #0]
	movs r0, #0
	bfi r1, r0, #0, #5
	uxth r1, r1
	bfi r1, r0, #5, #6
	uxth r1, r1
	bfi r1, r0, #0xb, #5
	strh.w r1, [sp, #0]
	uxth r0, r1
	str r0, [sp, #0]
	ldrh.w r0, [sp, #0]
	str r0, [sp, #0]
	mov r1, r0
	mov r2, r10
	ldr r0, [sp, #0x18]
	bl blend_565_0801d9dc
	str r0, [sp, #0x4]
	add.w r0, r10, #4
	lsrs r0, r0, #3
	ldr r1, [sp, #0x18]
	lsls r0, r0, #0x1b
	lsrs r0, r0, #0x18
	uxth r1, r1
	lsrs r2, r1, #0xb
	smulbb r2, r2, r0
	bfi r6, r2, #0, #0x10
	ubfx r2, r1, #5, #6
	smulbb r2, r2, r0
	bfi r6, r2, #0x10, #0x10
	and r1, r1, #0x1f
	smulbb r1, r1, r0
	bfi r7, r1, #0, #0x10
	mov r10, r7
	rsb.w r1, r0, #0xff
	movs r2, #0
	b.n .L0801a752
.L0801a6b6:
	movs r0, #0
	b.n .L0801a746
	nop  @ padding
.L0801a6bc:
	ldrh.w r7, [sp, #0]
	ldrh.w r3, [r4, r0, lsl #1]
	cmp r7, r3
	beq.n .L0801a73a
	add.w r3, r4, r0, lsl #1
	uxth r7, r6
	ldrh r3, [r3, #0]
	strh.w r3, [sp, #0]
	strh.w r3, [sp, #8]
	uxth r3, r3
	lsr.w r12, r3, #0xb
	smlabb r7, r12, r1, r7
	add.w r12, r7, r7, lsl #7
	add.w r7, r12, r7, lsl #15
	ldrh.w r8, [sp, #4]
	ubfx r7, r7, #0x17, #5
	bfi r8, r7, #0xb, #5
	lsrs r7, r6, #0x10
	ubfx r12, r3, #5, #6
	smlabb r7, r12, r1, r7
	add.w r12, r7, r7, lsl #7
	add.w r7, r12, r7, lsl #15
	ubfx r7, r7, #0x17, #6
	bfi r8, r7, #5, #6
	b.n .L0801a714
.L0801a712:
	b.n .L0801a8a4
.L0801a714:
	uxth.w r7, r10
	and r3, r3, #0x1f
	smlabb r3, r3, r1, r7
	add.w r7, r3, r3, lsl #7
	add.w r3, r7, r3, lsl #15
	ubfx r3, r3, #0x17, #5
	bfi r8, r3, #0, #5
	strh.w r8, [sp, #4]
	uxth.w r3, r8
	str r3, [sp, #4]
.L0801a73a:
	add.w r3, r4, r0, lsl #1
	ldrh.w r7, [sp, #4]
	strh r7, [r3, #0]
	.inst.n 0x1c40  @ adds r0, r0, #1
.L0801a746:
	cmp r0, r5
	blt.n .L0801a6bc
	ldr r0, [sp, #0x14]
	.inst.n 0x1c52  @ adds r2, r2, #1
	add.w r4, r4, r0, lsl #1
.L0801a752:
	cmp r2, r9
	blt.n .L0801a6b6
	b.n .L0801a646
.L0801a758:
	movs r7, #0
	b.n .L0801a77e
.L0801a75c:
	ldrb r2, [r6, #0]
	cmp r2, #0xff
	beq.n .L0801a788
	ldrh r0, [r4, #0]
	strh.w r0, [sp, #4]
	ldr r1, [sp, #4]
	ldr r0, [sp, #0x18]
	bl blend_565_0801d9dc
	str r0, [sp, #4]
	ldrh.w r0, [sp, #4]
	strh r0, [r4, #0]
.L0801a778:
	.inst.n 0x1ca4  @ adds r4, r4, #2
	.inst.n 0x1c76  @ adds r6, r6, #1
	.inst.n 0x1c7f  @ adds r7, r7, #1
.L0801a77e:
	cmp r7, r5
	bge.n .L0801a840
	lsls r0, r6, #0x1e
	bne.n .L0801a75c
	b.n .L0801a840
.L0801a788:
	strh.w r10, [r4, #0]
	b.n .L0801a778
.L0801a78e:
	ldr r0, [r6, #0]
	adds r1, r0, #1
	beq.n .L0801a81e
	cbz r0, .L0801a814
	ldrb r2, [r6, #0]
	cmp r2, #0xff
	beq.n .L0801a846
	ldrh r0, [r4, #0]
	strh.w r0, [sp, #4]
	ldr r1, [sp, #4]
	ldr r0, [sp, #0x18]
	bl blend_565_0801d9dc
	str r0, [sp, #4]
	ldrh.w r0, [sp, #4]
	strh.w r0, [r4, #0]
.L0801a7b4:
	ldrb.w r2, [r6, #1]!
	.inst.n 0x1ca4  @ adds r4, r4, #2
	cmp r2, #0xff
	beq.n .L0801a84c
	ldrh r0, [r4, #0]
	strh.w r0, [sp, #4]
	ldr r1, [sp, #4]
	ldr r0, [sp, #0x18]
	bl blend_565_0801d9dc
	str r0, [sp, #4]
	ldrh.w r0, [sp, #4]
	strh r0, [r4, #0]
.L0801a7d4:
	ldrb.w r2, [r6, #1]!
	.inst.n 0x1ca4  @ adds r4, r4, #2
	cmp r2, #0xff
	beq.n .L0801a852
	ldrh r0, [r4, #0]
	strh.w r0, [sp, #4]
	ldr r1, [sp, #4]
	ldr r0, [sp, #0x18]
	bl blend_565_0801d9dc
	str r0, [sp, #4]
	ldrh.w r0, [sp, #4]
	strh r0, [r4, #0]
.L0801a7f4:
	ldrb.w r2, [r6, #1]!
	.inst.n 0x1ca4  @ adds r4, r4, #2
	cmp r2, #0xff
	beq.n .L0801a858
	ldrh r0, [r4, #0]
	strh.w r0, [sp, #4]
	ldr r1, [sp, #4]
	ldr r0, [sp, #0x18]
	bl blend_565_0801d9dc
	str r0, [sp, #4]
	ldrh.w r0, [sp, #4]
	b.n .L0801a816
.L0801a814:
	b.n .L0801a83a
.L0801a816:
	strh r0, [r4, #0]
.L0801a818:
	.inst.n 0x1ca4  @ adds r4, r4, #2
	.inst.n 0x1c76  @ adds r6, r6, #1
	b.n .L0801a83e
.L0801a81e:
	lsls r0, r4, #0x1e
	beq.n .L0801a832
	strh.w r10, [r4, #0]
	movs r0, #2
	ldr r1, [sp, #0]
	str r1, [r0, r4]
	strh.w r10, [r4, #6]
	b.n .L0801a83a
.L0801a832:
	ldr r0, [sp, #0]
	str r0, [r4, #0]
	ldr r0, [sp, #0]
	str r0, [r4, #4]
.L0801a83a:
	adds r4, #8
	.inst.n 0x1d36  @ adds r6, r6, #4
.L0801a83e:
	.inst.n 0x1d3f  @ adds r7, r7, #4
.L0801a840:
	cmp r7, r8
	ble.n .L0801a78e
	b.n .L0801a880
.L0801a846:
	strh.w r10, [r4, #0]
	b.n .L0801a7b4
.L0801a84c:
	strh.w r10, [r4, #0]
	b.n .L0801a7d4
.L0801a852:
	strh.w r10, [r4, #0]
	b.n .L0801a7f4
.L0801a858:
	strh.w r10, [r4, #0]
	b.n .L0801a818
.L0801a85e:
	ldrb r2, [r6, #0]
	cmp r2, #0xff
	beq.n .L0801a89e
	ldrh r0, [r4, #0]
	strh.w r0, [sp, #4]
	ldr r1, [sp, #4]
	ldr r0, [sp, #0x18]
	bl blend_565_0801d9dc
	str r0, [sp, #4]
	ldrh.w r0, [sp, #4]
	strh r0, [r4, #0]
.L0801a87a:
	.inst.n 0x1ca4  @ adds r4, r4, #2
	.inst.n 0x1c76  @ adds r6, r6, #1
	.inst.n 0x1c7f  @ adds r7, r7, #1
.L0801a880:
	cmp r7, r5
	blt.n .L0801a85e
	ldr r0, [sp, #0x14]
	add.w r11, r11, #1
	subs r0, r0, r5
	add.w r4, r4, r0, lsl #1
	ldr r0, [sp, #0x48]
	subs r0, r0, r5
	add r6, r0
.L0801a896:
	cmp r11, r9
	blt.w .L0801a758
	b.n .L0801a646
.L0801a89e:
	strh.w r10, [r4, #0]
	b.n .L0801a87a
.L0801a8a4:
	movs r2, #0
	ldrh r1, [r4, #0]
	strh.w r1, [sp, #0]
	mov r11, r2
	mov r0, r2
	b.n .L0801a91a
.L0801a8b2:
	movs r7, #0
	b.n .L0801a906
.L0801a8b6:
	ldrb r0, [r6, #0]
	cbz r0, .L0801a902
	cmp r0, r2
	beq.n .L0801a8ca
	cmp r0, #0xff
	beq.n .L0801a922
	mul r3, r0, r10
	lsrs r3, r3, #8
.L0801a8c8:
	mov r11, r3
.L0801a8ca:
	cmp r0, r2
	bne.n .L0801a8d6
	ldrh.w r0, [r4, r7, lsl #1]
	cmp r1, r0
	beq.n .L0801a8f8
.L0801a8d6:
	cmp.w r11, #0xff
	beq.n .L0801a926
	add.w r0, r4, r7, lsl #1
	mov r2, r11
	ldrh r0, [r0, #0]
	strh.w r0, [sp, #0]
	ldr r1, [sp, #0]
	ldr r0, [sp, #0x18]
	bl blend_565_0801d9dc
.L0801a8f0:
	str r0, [sp, #0]
	ldrb r2, [r6, #0]
	ldrh.w r1, [r4, r7, lsl #1]
.L0801a8f8:
	add.w r0, r4, r7, lsl #1
	ldrh.w r3, [sp, #0]
	strh r3, [r0, #0]
.L0801a902:
	.inst.n 0x1c76  @ adds r6, r6, #1
	.inst.n 0x1c7f  @ adds r7, r7, #1
.L0801a906:
	cmp r7, r5
	blt.n .L0801a8b6
	ldr r0, [sp, #0x14]
	add.w r4, r4, r0, lsl #1
	ldr r0, [sp, #0x48]
	subs r0, r0, r5
	add r6, r0
	add.w r0, r8, #1
.L0801a91a:
	mov r8, r0
	cmp r0, r9
	blt.n .L0801a8b2
	b.n .L0801a646
.L0801a922:
	mov r3, r10
	b.n .L0801a8c8
.L0801a926:
	ldr r0, [sp, #0x18]
	b.n .L0801a8f0
	.short 0x0000  @ padding

@ ----------------------------------------------------------------------------
@ fn_0801a92c - calls the per-pixel function of the object returned by
@ return_word_200004b8 for every pixel of a rectangle.
@   r0 = first argument forwarded to the callback (saved in the frame), r1 =
@   rectangle of 4 shorts (left, top, right, bottom) (r4), r2 = second
@   callback argument (frame sp+0x14), r3 = halfword argument (r10), stack:
@   param_5 = value (frame sp+0x40), param_6 = optional mask byte pointer
@   (r8; 0 = none), param_7 = mask stride (frame sp+0x48). No return value.
@ The object (r9) is obtained from return_word_200004b8 and its function at
@ (*object)+0x1c is called for every pixel (x from left to right, y from top
@ to bottom).
@ Without a mask the call passes (*object, r0, r2, x, y, r3, param_5); with a
@ mask the pixel is skipped when its mask byte is 0 and param_5 is replaced
@ by (mask byte * param_5) >> 8; the mask pointer advances by param_7 per
@ row.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801a92c,"ax",%progbits
	.p2align 2
	.global fn_0801a92c
	.thumb_func
	.type fn_0801a92c, %function
fn_0801a92c:
	push.w {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0xc
	mov r4, r1
	ldr.w r8, [sp, #0x44]
	bl return_word_200004b8
	ldrh.w r10, [sp, #0x18]
	mov r9, r0
	cmp.w r8, #0
	beq.n .L0801a962
	ldrh r0, [r4, #0x4]
	ldrh r1, [r4, #0]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r7, r0
	ldrh r0, [r4, #0x6]
	ldrh r1, [r4, #0x2]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth.w r11, r0
	movs r6, #0
	b.n .L0801a9e6
.L0801a962:
	ldrsh.w r6, [r4, #0x2]
	b.n .L0801a998
.L0801a968:
	ldrsh.w r5, [r4, #0]
	sxth.w r8, r6
	b.n .L0801a98e
.L0801a972:
	ldr r0, [sp, #0x40]
	str r0, [sp, #0x8]
	strh.w r10, [sp, #4]
	str.w r8, [sp, #0]
	ldr.w r0, [r9, #0]
	sxth r3, r5
	ldr r2, [sp, #0x14]
	ldr r7, [r0, #0x1c]
	ldr r1, [sp, #0xc]
	blx r7
	.inst.n 0x1c6d  @ adds r5, r5, #1
.L0801a98e:
	ldrsh.w r0, [r4, #0x4]
	cmp r0, r5
	bge.n .L0801a972
	.inst.n 0x1c76  @ adds r6, r6, #1
.L0801a998:
	ldrsh.w r0, [r4, #0x6]
	cmp r0, r6
	bge.n .L0801a968
.L0801a9a0:
	add sp, #0x1c
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801a9a6:
	movs r5, #0
	b.n .L0801a9dc
	nop  @ padding
.L0801a9ac:
	ldrb.w r0, [r8, r5]
	cbz r0, .L0801a9da
	ldr r1, [sp, #0x40]
	strh.w r10, [sp, #4]
	muls r0, r1, r0
	lsrs r0, r0, #8
	str r0, [sp, #0x8]
	ldrh r0, [r4, #0x2]
	ldr r1, [sp, #0xc]
	add r0, r6
	sxth r0, r0
	str r0, [sp, #0]
	ldrh r0, [r4, #0]
	ldr r2, [sp, #0x14]
	add r0, r5
	sxth r3, r0
	ldr.w r0, [r9, #0]
	ldr.w r12, [r0, #0x1c]
	blx r12
.L0801a9da:
	.inst.n 0x1c6d  @ adds r5, r5, #1
.L0801a9dc:
	cmp r5, r7
	blt.n .L0801a9ac
	ldr r0, [sp, #0x48]
	.inst.n 0x1c76  @ adds r6, r6, #1
	add r8, r0
.L0801a9e6:
	cmp r6, r11
	blt.n .L0801a9a6
	b.n .L0801a9a0

@ ----------------------------------------------------------------------------
@ copy_rect_0801cf8e - r0 = destination, r1 = source, each 4 halfwords (8
@ bytes); copies halfwords 0 to 3 from r1 to r0. No return value.
@ ----------------------------------------------------------------------------
	.section .text.copy_rect_0801cf8e,"ax",%progbits
	.global copy_rect_0801cf8e
	.thumb_func
	.type copy_rect_0801cf8e, %function
copy_rect_0801cf8e:
	ldrh r2, [r1, #0]
	strh r2, [r0, #0]
	ldrh r2, [r1, #2]
	strh r2, [r0, #2]
	ldrh r2, [r1, #4]
	strh r2, [r0, #4]
	ldrh r1, [r1, #6]
	strh r1, [r0, #6]
	bx lr

@ ----------------------------------------------------------------------------
@ copy_rect_0801cfa0 - r0 = destination, r1 = source, each 4 halfwords (8
@ bytes); copies halfwords 0 to 3 from r1 to r0. No return value.
@ ----------------------------------------------------------------------------
	.section .text.copy_rect_0801cfa0,"ax",%progbits
	.global copy_rect_0801cfa0
	.thumb_func
	.type copy_rect_0801cfa0, %function
copy_rect_0801cfa0:
	ldrh r2, [r1, #0]
	strh r2, [r0, #0]
	ldrh r2, [r1, #2]
	strh r2, [r0, #2]
	ldrh r2, [r1, #4]
	strh r2, [r0, #4]
	ldrh r1, [r1, #6]
	strh r1, [r0, #6]
	bx lr

@ ----------------------------------------------------------------------------
@ copy_rect_0801cfb2 - r0 = destination, r1 = source, each 4 halfwords (8
@ bytes); copies halfwords 0 to 3 from r1 to r0. No return value.
@ ----------------------------------------------------------------------------
	.section .text.copy_rect_0801cfb2,"ax",%progbits
	.global copy_rect_0801cfb2
	.thumb_func
	.type copy_rect_0801cfb2, %function
copy_rect_0801cfb2:
	ldrh r2, [r1, #0]
	strh r2, [r0, #0]
	ldrh r2, [r1, #2]
	strh r2, [r0, #2]
	ldrh r2, [r1, #4]
	strh r2, [r0, #4]
	ldrh r1, [r1, #6]
	strh r1, [r0, #6]
	bx lr

@ ----------------------------------------------------------------------------
@ copy_rect_0801cfc4 - r0 = destination, r1 = source, each 4 halfwords (8
@ bytes); copies halfwords 0 to 3 from r1 to r0. No return value.
@ ----------------------------------------------------------------------------
	.section .text.copy_rect_0801cfc4,"ax",%progbits
	.global copy_rect_0801cfc4
	.thumb_func
	.type copy_rect_0801cfc4, %function
copy_rect_0801cfc4:
	ldrh r2, [r1, #0]
	strh r2, [r0, #0]
	ldrh r2, [r1, #2]
	strh r2, [r0, #2]
	ldrh r2, [r1, #4]
	strh r2, [r0, #4]
	ldrh r1, [r1, #6]
	strh r1, [r0, #6]
	bx lr

@ ----------------------------------------------------------------------------
@ copy_rect_0801cfd6 - r0 = destination, r1 = source, each 4 halfwords (8
@ bytes); copies halfwords 0 to 3 from r1 to r0. No return value.
@ ----------------------------------------------------------------------------
	.section .text.copy_rect_0801cfd6,"ax",%progbits
	.global copy_rect_0801cfd6
	.thumb_func
	.type copy_rect_0801cfd6, %function
copy_rect_0801cfd6:
	ldrh r2, [r1, #0]
	strh r2, [r0, #0]
	ldrh r2, [r1, #2]
	strh r2, [r0, #2]
	ldrh r2, [r1, #4]
	strh r2, [r0, #4]
	ldrh r1, [r1, #6]
	strh r1, [r0, #6]
	bx lr

@ ----------------------------------------------------------------------------
@ copy_rect_0801cfe8 - r0 = destination, r1 = source, each 4 halfwords (8
@ bytes); copies halfwords 0 to 3 from r1 to r0. No return value.
@ ----------------------------------------------------------------------------
	.section .text.copy_rect_0801cfe8,"ax",%progbits
	.global copy_rect_0801cfe8
	.thumb_func
	.type copy_rect_0801cfe8, %function
copy_rect_0801cfe8:
	ldrh r2, [r1, #0]
	strh r2, [r0, #0]
	ldrh r2, [r1, #2]
	strh r2, [r0, #2]
	ldrh r2, [r1, #4]
	strh r2, [r0, #4]
	ldrh r1, [r1, #6]
	strh r1, [r0, #6]
	bx lr

@ ----------------------------------------------------------------------------
@ copy_rect_0801cffa - r0 = destination, r1 = source, each 4 halfwords (8
@ bytes); copies halfwords 0 to 3 from r1 to r0. No return value.
@ ----------------------------------------------------------------------------
	.section .text.copy_rect_0801cffa,"ax",%progbits
	.global copy_rect_0801cffa
	.thumb_func
	.type copy_rect_0801cffa, %function
copy_rect_0801cffa:
	ldrh r2, [r1, #0]
	strh r2, [r0, #0]
	ldrh r2, [r1, #2]
	strh r2, [r0, #2]
	ldrh r2, [r1, #4]
	strh r2, [r0, #4]
	ldrh r1, [r1, #6]
	strh r1, [r0, #6]
	bx lr

@ ----------------------------------------------------------------------------
@ copy_rect_0801d00c - r0 = destination, r1 = source, each 4 halfwords (8
@ bytes); copies halfwords 0 to 3 from r1 to r0. No return value.
@ ----------------------------------------------------------------------------
	.section .text.copy_rect_0801d00c,"ax",%progbits
	.global copy_rect_0801d00c
	.thumb_func
	.type copy_rect_0801d00c, %function
copy_rect_0801d00c:
	ldrh r2, [r1, #0]
	strh r2, [r0, #0]
	ldrh r2, [r1, #2]
	strh r2, [r0, #2]
	ldrh r2, [r1, #4]
	strh r2, [r0, #4]
	ldrh r1, [r1, #6]
	strh r1, [r0, #6]
	bx lr

@ ----------------------------------------------------------------------------
@ rect_height_0801d01e - r0 = rectangle pointer (4 halfwords x0, y0, x1, y1);
@ returns halfword +6 minus halfword +2 plus 1, sign-extended.
@ ----------------------------------------------------------------------------
	.section .text.rect_height_0801d01e,"ax",%progbits
	.global rect_height_0801d01e
	.thumb_func
	.type rect_height_0801d01e, %function
rect_height_0801d01e:
	ldrh r1, [r0, #6]
	ldrh r0, [r0, #2]
	subs r0, r1, r0
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	bx lr

@ ----------------------------------------------------------------------------
@ rect_height_0801d02a - r0 = rectangle pointer (4 halfwords x0, y0, x1, y1);
@ returns halfword +6 minus halfword +2 plus 1, sign-extended.
@ ----------------------------------------------------------------------------
	.section .text.rect_height_0801d02a,"ax",%progbits
	.global rect_height_0801d02a
	.thumb_func
	.type rect_height_0801d02a, %function
rect_height_0801d02a:
	ldrh r1, [r0, #6]
	ldrh r0, [r0, #2]
	subs r0, r1, r0
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	bx lr

@ ----------------------------------------------------------------------------
@ rect_area - r0 = rectangle pointer (4 halfwords x0, y0, x1, y1); returns
@ (x1-x0+1) * (y1-y0+1) using the signed halfwords +4, +0 and +6, +2.
@ ----------------------------------------------------------------------------
	.section .text.rect_area,"ax",%progbits
	.global rect_area
	.thumb_func
	.type rect_area, %function
rect_area:
	ldrsh.w r1, [r0, #4]
	ldrsh.w r2, [r0, #0]
	subs r1, r1, r2
	ldrsh.w r2, [r0, #6]
	ldrsh.w r0, [r0, #2]
	subs r0, r2, r0
	.inst.n 0x1c40  @ adds r0, r0, #1
	.inst.n 0x1c49  @ adds r1, r1, #1
	muls r0, r1, r0
	bx lr

@ ----------------------------------------------------------------------------
@ rect_width_0801d052 - r0 = rectangle pointer (4 halfwords x0, y0, x1, y1);
@ returns halfword +4 minus halfword +0 plus 1, sign-extended.
@ ----------------------------------------------------------------------------
	.section .text.rect_width_0801d052,"ax",%progbits
	.global rect_width_0801d052
	.thumb_func
	.type rect_width_0801d052, %function
rect_width_0801d052:
	ldrh r1, [r0, #4]
	ldrh r0, [r0, #0]
	subs r0, r1, r0
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	bx lr

@ ----------------------------------------------------------------------------
@ rect_width_0801d05e - r0 = rectangle pointer (4 halfwords x0, y0, x1, y1);
@ returns halfword +4 minus halfword +0 plus 1, sign-extended.
@ ----------------------------------------------------------------------------
	.section .text.rect_width_0801d05e,"ax",%progbits
	.global rect_width_0801d05e
	.thumb_func
	.type rect_width_0801d05e, %function
rect_width_0801d05e:
	ldrh r1, [r0, #4]
	ldrh r0, [r0, #0]
	subs r0, r1, r0
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	bx lr

@ ----------------------------------------------------------------------------
@ rect_width_0801d06a - r0 = rectangle pointer (4 halfwords x0, y0, x1, y1);
@ returns halfword +4 minus halfword +0 plus 1, sign-extended.
@ ----------------------------------------------------------------------------
	.section .text.rect_width_0801d06a,"ax",%progbits
	.global rect_width_0801d06a
	.thumb_func
	.type rect_width_0801d06a, %function
rect_width_0801d06a:
	ldrh r1, [r0, #4]
	ldrh r0, [r0, #0]
	subs r0, r1, r0
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	bx lr

@ ----------------------------------------------------------------------------
@ rect_width_0801d076 - r0 = rectangle pointer (4 halfwords x0, y0, x1, y1);
@ returns halfword +4 minus halfword +0 plus 1, sign-extended.
@ ----------------------------------------------------------------------------
	.section .text.rect_width_0801d076,"ax",%progbits
	.global rect_width_0801d076
	.thumb_func
	.type rect_width_0801d076, %function
rect_width_0801d076:
	ldrh r1, [r0, #4]
	ldrh r0, [r0, #0]
	subs r0, r1, r0
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	bx lr

@ ----------------------------------------------------------------------------
@ rect_grow - r0 = rectangle pointer (4 halfwords x0, y0, x1, y1), r1 = dx,
@ r2 = dy; subtracts r1 from x0 and adds r1 to x1 (halfwords +0, +4),
@ subtracts r2 from y0 and adds r2 to y1 (halfwords +2, +6).
@ ----------------------------------------------------------------------------
	.section .text.rect_grow,"ax",%progbits
	.global rect_grow
	.thumb_func
	.type rect_grow, %function
rect_grow:
	ldrh r3, [r0, #0]
	subs r3, r3, r1
	strh r3, [r0, #0]
	ldrh r3, [r0, #4]
	add r1, r3
	strh r1, [r0, #4]
	ldrh r1, [r0, #2]
	subs r1, r1, r2
	strh r1, [r0, #2]
	ldrh r1, [r0, #6]
	add r1, r2
	strh r1, [r0, #6]
	bx lr

@ ----------------------------------------------------------------------------
@ rect_move - r0 = rectangle pointer (4 halfwords x0, y0, x1, y1), r1 = dx,
@ r2 = dy; adds r1 to x0 and x1 (halfwords +0, +4) and r2 to y0 and y1
@ (halfwords +2, +6).
@ ----------------------------------------------------------------------------
	.section .text.rect_move,"ax",%progbits
	.global rect_move
	.thumb_func
	.type rect_move, %function
rect_move:
	ldrh r3, [r0, #0]
	add r3, r1
	strh r3, [r0, #0]
	ldrh r3, [r0, #4]
	add r1, r3
	strh r1, [r0, #4]
	ldrh r1, [r0, #2]
	add r1, r2
	strh r1, [r0, #2]
	ldrh r1, [r0, #6]
	add r1, r2
	strh r1, [r0, #6]
	bx lr

@ ----------------------------------------------------------------------------
@ rect_set - r0 = rectangle pointer, r1..r3 and the stack word at sp+0 (on
@ entry) = four halfword values; stores them to halfwords +0, +2, +4, +6.
@ ----------------------------------------------------------------------------
	.section .text.rect_set,"ax",%progbits
	.global rect_set
	.thumb_func
	.type rect_set, %function
rect_set:
	push {r4, lr}
	ldr r4, [sp, #0x8]
	strh r1, [r0, #0]
	strh r2, [r0, #2]
	strh r3, [r0, #4]
	strh r4, [r0, #6]
	pop {r4, pc}

@ ----------------------------------------------------------------------------
@ rect_set_height - r0 = rectangle pointer, r1 = height; stores halfword +6 =
@ r1 - 1 + halfword +2.
@ ----------------------------------------------------------------------------
	.section .text.rect_set_height,"ax",%progbits
	.global rect_set_height
	.thumb_func
	.type rect_set_height, %function
rect_set_height:
	ldrh r2, [r0, #2]
	.inst.n 0x1e49  @ subs r1, r1, #1
	add r1, r2
	strh r1, [r0, #6]
	bx lr

@ ----------------------------------------------------------------------------
@ rect_set_width - r0 = rectangle pointer, r1 = width; stores halfword +4 =
@ r1 - 1 + halfword +0.
@ ----------------------------------------------------------------------------
	.section .text.rect_set_width,"ax",%progbits
	.global rect_set_width
	.thumb_func
	.type rect_set_width, %function
rect_set_width:
	ldrh r2, [r0, #0]
	.inst.n 0x1e49  @ subs r1, r1, #1
	add r1, r2
	strh r1, [r0, #4]
	bx lr

@ ----------------------------------------------------------------------------
@ fn_0801d0d8 - integer angle of a vector.
@   r0 = x component, r1 = y component (signed); returns a halfword angle 0
@   to 0x168 (360) in r0.
@ r2 collects flags: bit 0 = x was negative (x is negated), bit 1 = y was
@ negative (y is negated, r2 += 2). The magnitudes are compared: when |x| >
@ |y| (unsigned compare) r3 = |y| * 0x2d / |x| and 0x10 is added to the flags,
@ otherwise r3 = |x| * 0x2d / |y| (45 degree scale; the multiply by 0x2d is
@ done as (v*15)*3).
@ A correction 0 to 4 is added to r3 (low byte r1 = r3 & 0xff): for r1 <= 0x16
@ one step each when r1 >= 2, >= 6, >= 10, >= 0xf (0x0801d12a to 0x0801d140);
@ for r1 >= 0x17 one step each when r1 <= 0x2c, <= 0x29, <= 0x25, <= 0x20
@ (0x0801d112 to 0x0801d126).
@ Mirroring: flag 0x10 gives 0x5a - v; then with flag 2 set the result is v +
@ 0xb4 (flag 1 set) or 0xb4 - v (flag 1 clear); with flag 2 clear and flag 1
@ set the result is 0x168 - v. The result is returned zero-extended from 16
@ bits.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801d0d8,"ax",%progbits
	.global fn_0801d0d8
	.thumb_func
	.type fn_0801d0d8, %function
fn_0801d0d8:
	movs r2, #0
	cmp r0, #0
	bge.n .L0801d0e2
	movs r2, #1
	rsbs r0, r0, #0
.L0801d0e2:
	cmp r1, #0
	bge.n .L0801d0ea
	rsbs r1, r1, #0
	.inst.n 0x1c92  @ adds r2, r2, #2
.L0801d0ea:
	cmp r0, r1
	bls.n .L0801d0fe
	rsb r1, r1, r1, lsl #4
	add.w r1, r1, r1, lsl #1
	udiv r3, r1, r0
	adds r2, #0x10
	b.n .L0801d10a
.L0801d0fe:
	rsb r0, r0, r0, lsl #4
	add.w r0, r0, r0, lsl #1
	udiv r3, r0, r1
.L0801d10a:
	movs r0, #0
	uxtb r1, r3
	cmp r1, #0x16
	bls.n .L0801d12a
	cmp r1, #0x2c
	bhi.n .L0801d118
	movs r0, #1
.L0801d118:
	cmp r1, #0x29
	bhi.n .L0801d11e
	.inst.n 0x1c40  @ adds r0, r0, #1
.L0801d11e:
	cmp r1, #0x25
	bhi.n .L0801d124
	.inst.n 0x1c40  @ adds r0, r0, #1
.L0801d124:
	cmp r1, #0x20
	bls.n .L0801d140
	b.n .L0801d142
.L0801d12a:
	cmp r1, #2
	bcc.n .L0801d130
	movs r0, #1
.L0801d130:
	cmp r1, #6
	bcc.n .L0801d136
	.inst.n 0x1c40  @ adds r0, r0, #1
.L0801d136:
	cmp r1, #0xa
	bcc.n .L0801d13c
	.inst.n 0x1c40  @ adds r0, r0, #1
.L0801d13c:
	cmp r1, #0xf
	bcc.n .L0801d142
.L0801d140:
	.inst.n 0x1c40  @ adds r0, r0, #1
.L0801d142:
	add r0, r3
	lsls r1, r2, #0x1b
	bpl.n .L0801d14c
	rsb.w r0, r0, #0x5a
.L0801d14c:
	lsls r1, r2, #0x1e
	lsl.w r1, r2, #0x1f
	bpl.n .L0801d160
	cbz r1, .L0801d15a
	adds r0, #0xb4
	b.n .L0801d166
.L0801d15a:
	rsb.w r0, r0, #0xb4
	b.n .L0801d166
.L0801d160:
	cbz r1, .L0801d166
	rsb.w r0, r0, #0x168
.L0801d166:
	uxth r0, r0
	bx lr

@ ----------------------------------------------------------------------------
@ cubic_bezier_fixed10 - cubic Bernstein sum in 10-bit fixed point.
@   r0 = t (0 to 0x400), r1, r2, r3 and the stack word at sp+0 (on entry) =
@   control values p0, p1, p2, p3; returns an integer in r0.
@ With u = 0x400 - t it returns (u^3 >> 20) * p0 >> 10, plus p1*t*u^2*3 >> 20,
@ plus p2*t^2*u*3 >> 20, plus (t^3 >> 20) * p3 >> 10; the intermediate
@ products are shifted right by 10 after each pair of multiplications as the
@ instructions show.
@ ----------------------------------------------------------------------------
	.section .text.cubic_bezier_fixed10,"ax",%progbits
	.global cubic_bezier_fixed10
	.thumb_func
	.type cubic_bezier_fixed10, %function
cubic_bezier_fixed10:
	push {r4, r5, r6, r7, lr}
	rsb.w r4, r0, #0x400
	mul r5, r4, r4
	lsrs r5, r5, #0xa
	mul r6, r5, r4
	lsr.w r12, r6, #0xa
	mul r6, r0, r0
	lsrs r6, r6, #0xa
	mul r7, r6, r0
	muls r5, r0, r5
	muls r5, r2, r5
	lsrs r7, r7, #0xa
	mul r12, r12, r1
	muls r4, r6, r4
	lsr.w r1, r12, #0xa
	add.w r0, r5, r5, lsl #1
	muls r4, r3, r4
	ldr.w lr, [sp, #0x14]
	add.w r2, r4, r4, lsl #1
	add.w r0, r1, r0, lsr #0x14
	mul r7, r7, lr
	add.w r0, r0, r2, lsr #0x14
	add.w r0, r0, r7, lsr #0xa
	pop {r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_0801d5f8 - clamps a value between two limits, where each limit may be
@ given as a percentage code.
@   r0 = value a (kept in r4), r1 = low code, r2 = high code, r3 = scale;
@   returns an integer in r0.
@ Each of r1 and r2 whose bits 14..13 equal 1 is replaced by sxth(r3 * v /
@ 100) with v = code with bits 14 and 13 cleared (bic 0x6000); a code with v
@ above 0x7d0 is left as it is, and for v above 1000 the value 1000 - v is
@ used. Returns r1 when min(r0, r2) < r1, else min(r0, r2).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801d5f8,"ax",%progbits
	.global fn_0801d5f8
	.thumb_func
	.type fn_0801d5f8, %function
fn_0801d5f8:
	push {r4, r5, r6, r7, lr}
	mov r4, r0
	mov.w r6, #0x7d0
	ubfx r0, r1, #0xd, #2
	asrs r7, r6, #1
	movs r5, #0x64
	cmp r0, #1
	bne.n .L0801d624
	bic.w r0, r1, #0x6000
	cmp r0, r6
	bgt.n .L0801d624
	cmp r0, r7
	ble.n .L0801d61c
	rsb.w r0, r0, #0x3e8
.L0801d61c:
	muls r0, r3, r0
	sdiv r0, r0, r5
	sxth r1, r0
.L0801d624:
	ubfx r0, r2, #0xd, #2
	cmp r0, #1
	bne.n .L0801d644
	bic.w r0, r2, #0x6000
	cmp r0, r6
	bgt.n .L0801d644
	cmp r0, r7
	ble.n .L0801d63c
	rsb.w r0, r0, #0x3e8
.L0801d63c:
	muls r0, r3, r0
	sdiv r0, r0, r5
	sxth r2, r0
.L0801d644:
	cmp r4, r2
	bge.n .L0801d64c
	mov r0, r4
	b.n .L0801d64e
.L0801d64c:
	mov r0, r2
.L0801d64e:
	cmp r0, r1
	bge.n .L0801d656
	mov r0, r1
	pop {r4, r5, r6, r7, pc}
.L0801d656:
	cmp r4, r2
	bge.n .L0801d65e
	mov r0, r4
	pop {r4, r5, r6, r7, pc}
.L0801d65e:
	mov r0, r2
	pop {r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_0801d662 - clamps a value between two limits, where each limit may be
@ given as a percentage code (same instructions as fn_0801d5f8).
@   r0 = value a (kept in r4), r1 = low code, r2 = high code, r3 = scale;
@   returns an integer in r0.
@ Each of r1 and r2 whose bits 14..13 equal 1 is replaced by sxth(r3 * v /
@ 100) with v = code with bits 14 and 13 cleared (bic 0x6000); a code with v
@ above 0x7d0 is left as it is, and for v above 1000 the value 1000 - v is
@ used. Returns r1 when min(r0, r2) < r1, else min(r0, r2).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801d662,"ax",%progbits
	.global fn_0801d662
	.thumb_func
	.type fn_0801d662, %function
fn_0801d662:
	push {r4, r5, r6, r7, lr}
	mov r4, r0
	mov.w r6, #0x7d0
	ubfx r0, r1, #0xd, #2
	asrs r7, r6, #1
	movs r5, #0x64
	cmp r0, #1
	bne.n .L0801d68e
	bic.w r0, r1, #0x6000
	cmp r0, r6
	bgt.n .L0801d68e
	cmp r0, r7
	ble.n .L0801d686
	rsb.w r0, r0, #0x3e8
.L0801d686:
	muls r0, r3, r0
	sdiv r0, r0, r5
	sxth r1, r0
.L0801d68e:
	ubfx r0, r2, #0xd, #2
	cmp r0, #1
	bne.n .L0801d6ae
	bic.w r0, r2, #0x6000
	cmp r0, r6
	bgt.n .L0801d6ae
	cmp r0, r7
	ble.n .L0801d6a6
	rsb.w r0, r0, #0x3e8
.L0801d6a6:
	muls r0, r3, r0
	sdiv r0, r0, r5
	sxth r2, r0
.L0801d6ae:
	cmp r4, r2
	bge.n .L0801d6b6
	mov r0, r4
	b.n .L0801d6b8
.L0801d6b6:
	mov r0, r2
.L0801d6b8:
	cmp r0, r1
	bge.n .L0801d6c0
	mov r0, r1
	pop {r4, r5, r6, r7, pc}
.L0801d6c0:
	cmp r4, r2
	bge.n .L0801d6c8
	mov r0, r4
	pop {r4, r5, r6, r7, pc}
.L0801d6c8:
	mov r0, r2
	pop {r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_0801d6cc - no parameters; returns a halfword: the result of
@ rgb_to_565_0801d852(0, 0, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801d6cc,"ax",%progbits
	.p2align 2
	.global fn_0801d6cc
	.thumb_func
	.type fn_0801d6cc, %function
fn_0801d6cc:
	movs r2, #0
	push {r3, lr}
	mov r1, r2
	mov r0, r2
	bl rgb_to_565_0801d852
	str r0, [sp, #0]
	ldrh.w r0, [sp, #0]
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ fn_0801d6e0 - no parameters; returns a halfword: the result of
@ rgb_to_565_0801d8e2(0, 0, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801d6e0,"ax",%progbits
	.p2align 2
	.global fn_0801d6e0
	.thumb_func
	.type fn_0801d6e0, %function
fn_0801d6e0:
	movs r2, #0
	push {r3, lr}
	mov r1, r2
	mov r0, r2
	bl rgb_to_565_0801d8e2
	str r0, [sp, #0]
	ldrh.w r0, [sp, #0]
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ fn_0801d6f4 - no parameters; returns a halfword: the result of
@ rgb_to_565_0801d912(0, 0, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801d6f4,"ax",%progbits
	.p2align 2
	.global fn_0801d6f4
	.thumb_func
	.type fn_0801d6f4, %function
fn_0801d6f4:
	movs r2, #0
	push {r3, lr}
	mov r1, r2
	mov r0, r2
	bl rgb_to_565_0801d912
	str r0, [sp, #0]
	ldrh.w r0, [sp, #0]
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ fn_0801d708 - r0, r1 = two arguments (kept in r5 and r4); returns a
@ halfword: calls fn_0801d6cc() and returns blend_565_0801d974(result, r0,
@ r1).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801d708,"ax",%progbits
	.p2align 2
	.global fn_0801d708
	.thumb_func
	.type fn_0801d708, %function
fn_0801d708:
	push {r3, r4, r5, lr}
	mov r4, r1
	mov r5, r0
	bl fn_0801d6cc
	mov r2, r4
	mov r1, r5
	bl blend_565_0801d974
	str r0, [sp, #0]
	ldrh.w r0, [sp, #0]
	pop {r3, r4, r5, pc}
	.short 0x0000  @ padding

@ ----------------------------------------------------------------------------
@ fill_halfwords - fills memory with a halfword value.
@   r0 = destination pointer, r1 = halfword value (read from the pushed copy
@   at sp+4), r2 = count of halfwords; no return value.
@ When r0 is not word aligned it stores one halfword and counts r2 down. Then
@ it writes 16 halfwords per round (8 word stores of the value duplicated in
@ both halves) while r2 > 0x10, and finally writes the remaining halfwords one
@ at a time.
@ ----------------------------------------------------------------------------
	.section .text.fill_halfwords,"ax",%progbits
	.p2align 2
	.global fill_halfwords
	.thumb_func
	.type fill_halfwords, %function
fill_halfwords:
	push {r0, r1, r2, lr}
	lsls r1, r0, #0x1e
	ldrh.w r3, [sp, #0x4]
	beq.n .L0801d734
	strh.w r3, [r0], #2
	.inst.n 0x1e52  @ subs r2, r2, #1
.L0801d734:
	ldrh.w r1, [sp, #0x4]
	add.w r1, r1, r1, lsl #16
	b.n .L0801d75c
.L0801d73e:
	stmia r0!, {r1}
	subs r2, #0x10
	stmia r0!, {r1}
	str.w r1, [r0], #8
	str.w r1, [r0, #-4]
	str.w r1, [r0], #0x10
	str.w r1, [r0, #-0xc]
	str.w r1, [r0, #-8]
	str.w r1, [r0, #-4]
.L0801d75c:
	cmp r2, #0x10
	bhi.n .L0801d73e
	b.n .L0801d76a
	nop  @ padding
.L0801d764:
	strh.w r3, [r0], #2
	.inst.n 0x1e52  @ subs r2, r2, #1
.L0801d76a:
	cmp r2, #0
	bne.n .L0801d764
	pop {r1, r2, r3, pc}

@ ----------------------------------------------------------------------------
@ rgb888_word_to_rgb565 - r0 = 0x00RRGGBB; returns the halfword
@ (r0>>8 & 0xf800) | (r0>>5 & 0x7e0) | ((r0 >> 3) & 0x1f).
@ ----------------------------------------------------------------------------
	.section .text.rgb888_word_to_rgb565,"ax",%progbits
	.global rgb888_word_to_rgb565
	.thumb_func
	.type rgb888_word_to_rgb565, %function
rgb888_word_to_rgb565:
	mov.w r1, #0xf800
	mov.w r2, #0x7e0
	and.w r1, r1, r0, lsr #8
	and.w r2, r2, r0, lsr #5
	push {r3, lr}
	orrs r1, r2
	ubfx r0, r0, #3, #5
	orrs r1, r0
	strh.w r1, [sp, #0]
	uxth r0, r1
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ rgb_to_565_0801d792 - r0 = red, r1 = green, r2 = blue (bytes); returns the
@ halfword ((r>>3 & 0x1f) << 11) | ((g>>2 & 0x3f) << 5) | (b>>3 & 0x1f).
@ ----------------------------------------------------------------------------
	.section .text.rgb_to_565_0801d792,"ax",%progbits
	.global rgb_to_565_0801d792
	.thumb_func
	.type rgb_to_565_0801d792, %function
rgb_to_565_0801d792:
	push {r3, lr}
	lsrs r3, r2, #3
	ldrh.w r2, [sp, #0]
	bfi r2, r3, #0, #5
	strh.w r2, [sp, #0]
	lsrs r2, r1, #2
	ldrh.w r1, [sp, #0]
	bfi r1, r2, #5, #6
	strh.w r1, [sp, #0]
	lsrs r1, r0, #3
	ldrh.w r0, [sp, #0]
	bfi r0, r1, #0xb, #5
	strh.w r0, [sp, #0]
	uxth r0, r0
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ rgb_to_565_0801d7c2 - r0 = red, r1 = green, r2 = blue (bytes); returns the
@ halfword ((r>>3 & 0x1f) << 11) | ((g>>2 & 0x3f) << 5) | (b>>3 & 0x1f).
@ ----------------------------------------------------------------------------
	.section .text.rgb_to_565_0801d7c2,"ax",%progbits
	.global rgb_to_565_0801d7c2
	.thumb_func
	.type rgb_to_565_0801d7c2, %function
rgb_to_565_0801d7c2:
	push {r3, lr}
	lsrs r3, r2, #3
	ldrh.w r2, [sp, #0]
	bfi r2, r3, #0, #5
	strh.w r2, [sp, #0]
	lsrs r2, r1, #2
	ldrh.w r1, [sp, #0]
	bfi r1, r2, #5, #6
	strh.w r1, [sp, #0]
	lsrs r1, r0, #3
	ldrh.w r0, [sp, #0]
	bfi r0, r1, #0xb, #5
	strh.w r0, [sp, #0]
	uxth r0, r0
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ rgb_to_565_0801d7f2 - r0 = red, r1 = green, r2 = blue (bytes); returns the
@ halfword ((r>>3 & 0x1f) << 11) | ((g>>2 & 0x3f) << 5) | (b>>3 & 0x1f).
@ ----------------------------------------------------------------------------
	.section .text.rgb_to_565_0801d7f2,"ax",%progbits
	.global rgb_to_565_0801d7f2
	.thumb_func
	.type rgb_to_565_0801d7f2, %function
rgb_to_565_0801d7f2:
	push {r3, lr}
	lsrs r3, r2, #3
	ldrh.w r2, [sp, #0]
	bfi r2, r3, #0, #5
	strh.w r2, [sp, #0]
	lsrs r2, r1, #2
	ldrh.w r1, [sp, #0]
	bfi r1, r2, #5, #6
	strh.w r1, [sp, #0]
	lsrs r1, r0, #3
	ldrh.w r0, [sp, #0]
	bfi r0, r1, #0xb, #5
	strh.w r0, [sp, #0]
	uxth r0, r0
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ rgb_to_565_0801d822 - r0 = red, r1 = green, r2 = blue (bytes); returns the
@ halfword ((r>>3 & 0x1f) << 11) | ((g>>2 & 0x3f) << 5) | (b>>3 & 0x1f).
@ ----------------------------------------------------------------------------
	.section .text.rgb_to_565_0801d822,"ax",%progbits
	.global rgb_to_565_0801d822
	.thumb_func
	.type rgb_to_565_0801d822, %function
rgb_to_565_0801d822:
	push {r3, lr}
	lsrs r3, r2, #3
	ldrh.w r2, [sp, #0]
	bfi r2, r3, #0, #5
	strh.w r2, [sp, #0]
	lsrs r2, r1, #2
	ldrh.w r1, [sp, #0]
	bfi r1, r2, #5, #6
	strh.w r1, [sp, #0]
	lsrs r1, r0, #3
	ldrh.w r0, [sp, #0]
	bfi r0, r1, #0xb, #5
	strh.w r0, [sp, #0]
	uxth r0, r0
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ rgb_to_565_0801d852 - r0 = red, r1 = green, r2 = blue (bytes); returns the
@ halfword ((r>>3 & 0x1f) << 11) | ((g>>2 & 0x3f) << 5) | (b>>3 & 0x1f).
@ ----------------------------------------------------------------------------
	.section .text.rgb_to_565_0801d852,"ax",%progbits
	.global rgb_to_565_0801d852
	.thumb_func
	.type rgb_to_565_0801d852, %function
rgb_to_565_0801d852:
	push {r3, lr}
	lsrs r3, r2, #3
	ldrh.w r2, [sp, #0]
	bfi r2, r3, #0, #5
	strh.w r2, [sp, #0]
	lsrs r2, r1, #2
	ldrh.w r1, [sp, #0]
	bfi r1, r2, #5, #6
	strh.w r1, [sp, #0]
	lsrs r1, r0, #3
	ldrh.w r0, [sp, #0]
	bfi r0, r1, #0xb, #5
	strh.w r0, [sp, #0]
	uxth r0, r0
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ rgb_to_565_0801d882 - r0 = red, r1 = green, r2 = blue (bytes); returns the
@ halfword ((r>>3 & 0x1f) << 11) | ((g>>2 & 0x3f) << 5) | (b>>3 & 0x1f).
@ ----------------------------------------------------------------------------
	.section .text.rgb_to_565_0801d882,"ax",%progbits
	.global rgb_to_565_0801d882
	.thumb_func
	.type rgb_to_565_0801d882, %function
rgb_to_565_0801d882:
	push {r3, lr}
	lsrs r3, r2, #3
	ldrh.w r2, [sp, #0]
	bfi r2, r3, #0, #5
	strh.w r2, [sp, #0]
	lsrs r2, r1, #2
	ldrh.w r1, [sp, #0]
	bfi r1, r2, #5, #6
	strh.w r1, [sp, #0]
	lsrs r1, r0, #3
	ldrh.w r0, [sp, #0]
	bfi r0, r1, #0xb, #5
	strh.w r0, [sp, #0]
	uxth r0, r0
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ rgb_to_565_0801d8b2 - r0 = red, r1 = green, r2 = blue (bytes); returns the
@ halfword ((r>>3 & 0x1f) << 11) | ((g>>2 & 0x3f) << 5) | (b>>3 & 0x1f).
@ ----------------------------------------------------------------------------
	.section .text.rgb_to_565_0801d8b2,"ax",%progbits
	.global rgb_to_565_0801d8b2
	.thumb_func
	.type rgb_to_565_0801d8b2, %function
rgb_to_565_0801d8b2:
	push {r3, lr}
	lsrs r3, r2, #3
	ldrh.w r2, [sp, #0]
	bfi r2, r3, #0, #5
	strh.w r2, [sp, #0]
	lsrs r2, r1, #2
	ldrh.w r1, [sp, #0]
	bfi r1, r2, #5, #6
	strh.w r1, [sp, #0]
	lsrs r1, r0, #3
	ldrh.w r0, [sp, #0]
	bfi r0, r1, #0xb, #5
	strh.w r0, [sp, #0]
	uxth r0, r0
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ rgb_to_565_0801d8e2 - r0 = red, r1 = green, r2 = blue (bytes); returns the
@ halfword ((r>>3 & 0x1f) << 11) | ((g>>2 & 0x3f) << 5) | (b>>3 & 0x1f).
@ ----------------------------------------------------------------------------
	.section .text.rgb_to_565_0801d8e2,"ax",%progbits
	.global rgb_to_565_0801d8e2
	.thumb_func
	.type rgb_to_565_0801d8e2, %function
rgb_to_565_0801d8e2:
	push {r3, lr}
	lsrs r3, r2, #3
	ldrh.w r2, [sp, #0]
	bfi r2, r3, #0, #5
	strh.w r2, [sp, #0]
	lsrs r2, r1, #2
	ldrh.w r1, [sp, #0]
	bfi r1, r2, #5, #6
	strh.w r1, [sp, #0]
	lsrs r1, r0, #3
	ldrh.w r0, [sp, #0]
	bfi r0, r1, #0xb, #5
	strh.w r0, [sp, #0]
	uxth r0, r0
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ rgb_to_565_0801d912 - r0 = red, r1 = green, r2 = blue (bytes); returns the
@ halfword ((r>>3 & 0x1f) << 11) | ((g>>2 & 0x3f) << 5) | (b>>3 & 0x1f).
@ ----------------------------------------------------------------------------
	.section .text.rgb_to_565_0801d912,"ax",%progbits
	.global rgb_to_565_0801d912
	.thumb_func
	.type rgb_to_565_0801d912, %function
rgb_to_565_0801d912:
	push {r3, lr}
	lsrs r3, r2, #3
	ldrh.w r2, [sp, #0]
	bfi r2, r3, #0, #5
	strh.w r2, [sp, #0]
	lsrs r2, r1, #2
	ldrh.w r1, [sp, #0]
	bfi r1, r2, #5, #6
	strh.w r1, [sp, #0]
	lsrs r1, r0, #3
	ldrh.w r0, [sp, #0]
	bfi r0, r1, #0xb, #5
	strh.w r0, [sp, #0]
	uxth r0, r0
	pop {r3, pc}
