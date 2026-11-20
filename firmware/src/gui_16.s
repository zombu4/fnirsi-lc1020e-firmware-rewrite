@ gui_16.s - GUI layout distribution, event dispatch and small helper functions of the application
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08014354 - distributes the size of a layout over the child entries of a
@ size record and places the children of a context one after another. The
@ listing marks it as never returning: a weight sum of 0 ends in the endless
@ loop at 0x080144e0 (otherwise the function ends with the pop at the loop
@ test).
@
@ Parameters: r0 = context ([sp + 0x24]), r1 = layout record (r5),
@ r2 = first child index ([sp + 0x2c]), r3 = end index ([sp + 0x30]).
@ Stack arguments at entry: [sp + 0] x origin ([sp + 0x58]), [sp + 4] y origin
@ ([sp + 0x5c]), [sp + 8] argument r1 of fn_08028ad0 ([sp + 0x60]), [sp + 0xc]
@ gap ([sp + 0x64]), [sp + 0x10] size record pointer (r4, [sp + 0x68]).
@ Record fields used: r5 byte +0 (r0 of fn_08028ad0), byte +1 (alignment 1 or
@ 2), byte +3 (bit 0, bit 2). Size record: halfwords +0 span, +2 total, +4
@ reserve, +8, word +0xc entry list, word +0x10 entry count. Entry of 0x14
@ bytes: word +0 child, halfword +4 minimum, +6 maximum, +8 size, +0xc weight,
@ byte +0x10 bit 0 / word +0x10 fixed flag. No return value.
@
@ Prologue: pushes r0-r3 / r4-r8 / sb / sl / fp / lr and subtracts 0x24 from
@ sp. When bit 0 of byte [r5 + 3] is clear, F10 = 0x0801d02a (height: half[+6]
@ - half[+2] + 1), F14 = 0x0801d076 (width: half[+4] - half[+0] + 1), F18 =
@ 0x0801d0c4 (stores half[+2] + r1 - 1 at half[+6]); when set, F10 =
@ 0x0801d076, F14 = 0x0801d02a, F18 = 0x0801d0ce (stores half[+0] + r1 - 1 at
@ half[+4]). r3 = 0x10, lr = 0xc, fp = 8 (entry field offsets).
@
@ Distribution (0x08014390-0x08014486): remaining r1 = sxth(total - reserve)
@ minus the sizes (+8) of entries with the fixed flag set, r0 = sum of the
@ weights (+0xc) of the others (0x080143a8-0x080143da). Then for each non-fixed
@ entry in order: when r0 = 0 the code branches to itself at 0x080144e0 (never
@ leaves; 0x080144de b 0x080144e0 is entered by no instruction); candidate =
@ sxth(weight * (r1 / r0)) (sdiv); value = candidate limited by the maximum
@ (+6, ldrsh) first and then raised to the minimum (+4, ldrsh) when that is
@ larger (0x0801442c-0x08014440); the value is stored at +8 as halfword; when
@ value != candidate the entry word +0x10 is set to 1 and the repeat flag sl
@ = 1; r0 -= weight and r1 -= value (both sxth); after the pass sl != 0
@ repeats from 0x08014390.
@
@ After the distribution (0x08014488-0x080144e4): calls fn_0802491e(context,
@ 0), r7 = 1 when it returns 1 else 0; clears two local halfwords [sp + 8],
@ [sp + 0xc]; calls fn_08028ad0(byte [r5], [sp + 0x60], sxth half[r4 + 2],
@ sxth half[r4 + 8], &[sp + 8], &[sp + 0xc]); when bit 0 of byte [r5 + 3] and
@ r7 are both set adds fn_08023e7c(context) to [sp + 8]; r6 =
@ fn_08023d80(context, [sp + 0x2c]); r8 = 0x7d0; goes to the loop test
@ 0x0801472e.
@
@ Loop test 0x0801472e: ends (add sp #0x34, pop) when r6 = 0 or the words
@ [sp + 0x2c] and [sp + 0x30] are equal, else the body from 0x080144e6; next
@ child (0x0801471e): r6 = fn_0801b554(context, bit 2 of byte [r5 + 3],
@ &[sp + 0x2c]).
@
@ Body (0x080144e6-0x08014716): when any_flag_bit_set(child, 0x60001) != 0 the
@ child is skipped; when fn_080249b8(child, 0) = 0 bits 0x600 of halfword
@ [child + 0x22] are cleared; otherwise sb = size (+8) of the entry whose word
@ +0 equals the child (0 when none), halfword [child + 0x22] |= 0x400 when bit
@ 0 of byte [r5 + 3] is set else 0x200, and when F10(child + 0x14) != sb:
@ calls fn_08025400(child), saves the four halfwords [child + 0x14..0x1a] at
@ [sp + 0..6], calls F18(child + 0x14, sb), then fn_080207f4(child, 0x29,
@ &saved), fn_08023fa4(child), fn_080207f4(that result, 0x22, child) and
@ fn_08025400(child).
@
@ Placement (0x080145a0-0x08014716): offset [sp] = 0; alignment byte [r5 + 1]
@ = 1: sxth(half[r4] - F14(child + 0x14)); = 2: ((half[r4] + 1) & ~1 -
@ F14(...)) / 2 truncated toward zero as a signed 16-bit field
@ (0x080145c0-0x080145c6); when bit 0 of byte [r5 + 3] and r7 are set [sp + 8]
@ = half[sp + 8] - F10(child + 0x14); sb = sxth fn_08024bac(child, 0, 0x6a),
@ sl = sxth fn_08024bac(child, 0, 0x6b), r0 = rect_width_plus_one(child)
@ (stored [sp + 4]), rect_height_plus_one(child); for sb (factor [sp + 4] =
@ rect_width_plus_one(child)) and for sl (factor rect_height_plus_one(child)),
@ each only when its bits 13..14 equal 1 and its value with 0x6000 cleared is
@ <= r8 (signed): v = that value (0x3e8 - v when v > 0x3e8), the entry becomes
@ sxth(v * factor / 100) (sdiv); dx = (x origin - half[child + 0x14]) + sb and
@ dy = (y origin - half[child + 0x16]) + sl (sxth); with bit 0 of byte [r5 +
@ 3] clear: sl = sxth(dx + [sp]), sb = sxth(half[sp + 8] + dy); set: sl =
@ sxth(dx + half[sp + 8]), sb = sxth([sp] + dy); when sl or sb is nonzero:
@ fn_08025400(child), adds sl to halfwords +0x14 / +0x18 and sb to +0x16 /
@ +0x1a, fn_08025400(child), fn_0802554c(child, sl, sb, 0); then [sp + 8] =
@ F10(...) + gap + half[sp + 0xc] + half[sp + 8] when (bit 0 and r7) is clear,
@ else half[sp + 8] - (gap + half[sp + 0xc]).
@
@ Literal pool: the four function pointers rect_set_width, rect_set_height,
@ rect_width_0801d076, rect_height_0801d02a and the mask 0x00060001.
@ ----------------------------------------------------------------------------
	.section .text.fn_08014354,"ax",%progbits
	.p2align 2
	.global fn_08014354
	.thumb_func
	.type fn_08014354, %function
fn_08014354:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x24
	ldrb	r0, [r1, #3]
	ldr	r4, [sp, #0x68]
	lsls	r0, r0, #0x1f
	mov	r5, r1
	cmp	r0, #0
	beq.n	.L0801436a
	ldr	r0, .L08014744			@ rect_set_width
	b.n	.L0801436c
.L0801436a:
	ldr	r0, .L08014748			@ rect_set_height
.L0801436c:
	str	r0, [sp, #0x18]			@ F18
	beq.n	.L08014374
	ldr	r0, .L0801474c			@ rect_width_0801d076
	b.n	.L08014376
.L08014374:
	ldr	r0, .L08014750			@ rect_height_0801d02a
.L08014376:
	str	r0, [sp, #0x10]			@ F10
	bne.n	.L0801437e
	ldr	r0, .L0801474c			@ rect_width_0801d076
	b.n	.L08014380
.L0801437e:
	ldr	r0, .L08014750			@ rect_height_0801d02a
.L08014380:
	mov.w	r3, #0x10			@ entry field offset
	mov.w	lr, #0xc			@ entry field offset
	mov.w	r11, #8				@ entry field offset
	str.w	r0, [sp, #0x14]			@ F14
.L08014390:
	ldrh	r2, [r4, #2]
	ldrh	r1, [r4, #4]
	mov.w	r10, #0				@ repeat flag
	sub.w	r1, r2, r1
	mov	r0, r10
	sxth	r1, r1
	mov	r2, r10
	ldr.w	r12, [r4, #0x10]		@ entry count
	b.n	.L080143c8
.L080143a8:
	add.w	r7, r2, r2, lsl #2
	ldr	r6, [r4, #0xc]
	add.w	r8, r3, r7, lsl #2
	ldrb.w	r8, [r6, r8]
	lsls.w	r8, r8, #0x1f
	beq.n	.L080143d0
	add.w	r7, r11, r7, lsl #2
	ldrh	r6, [r6, r7]
	subs	r1, r1, r6
	sxth	r1, r1
.L080143c6:
	.inst.n	0x1c52				@ adds r2, r2, #1
.L080143c8:
	cmp	r12, r2
	bhi.n	.L080143a8
	movs	r2, #0
	b.n	.L0801447c
.L080143d0:
	add.w	r7, lr, r7, lsl #2
	ldrh	r6, [r6, r7]
	add	r0, r6
	sxth	r0, r0
	b.n	.L080143c6
.L080143dc:
	ldr	r6, [r4, #0xc]
	add.w	r7, r2, r2, lsl #2
	add.w	r12, r3, r7, lsl #2
	mov	r9, r6
	str.w	r12, [sp, #0x20]
	ldrb.w	r6, [r6, r12]
	lsls	r6, r6, #0x1f
	bne.n	.L0801447a
	cmp	r0, #0
	beq.n	.L080144e0
	sdiv	r8, r1, r0
	add.w	r6, lr, r7, lsl #2
	str	r6, [sp, #0x1c]
	ldrh.w	r6, [r9, r6]
	mul	r6, r6, r8
	sxth.w	r12, r6
	str.w	r12, [sp]
	mov.w	r12, #6
	add.w	r12, r12, r7, lsl #2
	movs	r6, #4
	ldrsh.w	r8, [r9, r12]
	add.w	r6, r6, r7, lsl #2
	ldr.w	r12, [sp]
	ldrsh.w	r6, [r9, r6]
	cmp	r8, r12
	bgt.n	.L08014432
	mov	r12, r8
.L08014432:
	cmp	r6, r12
	bgt.n	.L08014442
	ldr.w	r12, [sp]
	mov	r6, r8
	cmp	r8, r12
	ble.n	.L08014442
	mov	r6, r12
.L08014442:
	ldr.w	r12, [sp]
	str	r6, [sp, #4]
	cmp	r6, r12
	beq.n	.L0801445a
	ldr.w	r12, [sp, #0x20]
	mov.w	r8, #1
	mov	r10, r8
	str.w	r8, [r9, r12]
.L0801445a:
	ldr.w	r8, [r4, #0xc]
	ldr	r6, [sp, #4]
	add.w	r7, r11, r7, lsl #2
	strh.w	r6, [r8, r7]
	ldr.w	r12, [r4, #0xc]
	ldr	r7, [sp, #0x1c]
	ldrh.w	r7, [r12, r7]
	subs	r0, r0, r7
	subs	r1, r1, r6
	sxth	r0, r0
	sxth	r1, r1
.L0801447a:
	.inst.n	0x1c52				@ adds r2, r2, #1
.L0801447c:
	ldr	r6, [r4, #0x10]
	cmp	r6, r2
	bhi.n	.L080143dc
	cmp.w	r10, #0
	bne.n	.L08014390
	movs	r1, #0
	ldr	r0, [sp, #0x24]
	bl	fn_0802491e
	cmp	r0, #1
	beq.n	.L080144e2
	movs	r7, #0
.L08014496:
	movs	r0, #0
	strh.w	r0, [sp, #8]
	strh.w	r0, [sp, #0xc]
	add	r1, sp, #0xc
	add	r0, sp, #8
	strd	r0, r1, [sp]
	ldrh	r0, [r4, #8]
	ldrsh.w	r2, [r4, #2]
	sxth	r3, r0
	ldrb	r0, [r5]
	ldr	r1, [sp, #0x60]
	bl	fn_08028ad0
	ldrb	r0, [r5, #3]
	tst	r0, r7
	beq.n	.L080144ce
	ldr	r0, [sp, #0x24]
	bl	fn_08023e7c
	ldrh.w	r1, [sp, #8]
	add	r0, r1
	strh.w	r0, [sp, #8]
.L080144ce:
	ldr	r1, [sp, #0x2c]
	ldr	r0, [sp, #0x24]
	bl	fn_08023d80
	mov	r6, r0
	mov.w	r8, #0x7d0
	b.n	.L0801472e
	b.n	.L080144e0			@ entered by no instruction
.L080144e0:
	b.n	.L080144e0			@ branch to itself
.L080144e2:
	movs	r7, #1
	b.n	.L08014496
.L080144e6:
	ldr	r1, .L08014754			@ 0x00060001
	mov	r0, r6
	bl	any_flag_bit_set
	cmp	r0, #0
	bne.n	.L080145f0
	movs	r1, #0
	mov	r0, r6
	bl	fn_080249b8
	cbz	r0, .L08014578
	mov.w	r9, #0
	mov	r0, r9
	ldr	r1, [r4, #0x10]
	b.n	.L08014528
	nop					@ padding
.L08014508:
	ldr	r2, [r4, #0xc]
	add.w	r3, r0, r0, lsl #2
	ldr.w	r2, [r2, r3, lsl #2]
	cmp	r2, r6
	bne.n	.L08014526
	ldr	r1, [r4, #0xc]
	add.w	r2, r0, r0, lsl #2
	add.w	r0, r11, r2, lsl #2
	ldrsh.w	r9, [r1, r0]
	b.n	.L0801452c
.L08014526:
	.inst.n	0x1c40				@ adds r0, r0, #1
.L08014528:
	cmp	r1, r0
	bhi.n	.L08014508
.L0801452c:
	ldrb	r0, [r5, #3]
	lsls	r0, r0, #0x1f
	ldrh	r0, [r6, #0x22]
	beq.n	.L0801453a
	orr.w	r0, r0, #0x400
	b.n	.L0801453e
.L0801453a:
	orr.w	r0, r0, #0x200
.L0801453e:
	strh	r0, [r6, #0x22]
	add.w	r0, r6, #0x14
	ldr	r1, [sp, #0x10]
	mov	r10, r0
	blx	r1				@ F10(child + 0x14)
	cmp	r0, r9
	beq.n	.L080145a0
	mov	r0, r6
	bl	fn_08025400
	ldrh	r0, [r6, #0x14]
	strh.w	r0, [sp]
	ldrh	r0, [r6, #0x16]
	strh.w	r0, [sp, #2]
	ldrh	r0, [r6, #0x18]
	strh.w	r0, [sp, #4]
	ldrh	r0, [r6, #0x1a]
	strh.w	r0, [sp, #6]
	ldr	r2, [sp, #0x18]
	mov	r1, r9
	mov	r0, r10
	blx	r2				@ F18(child + 0x14, sb)
	mov	r2, sp
	b.n	.L0801457a
.L08014578:
	b.n	.L08014598
.L0801457a:
	movs	r1, #0x29
	mov	r0, r6
	bl	fn_080207f4
	mov	r0, r6
	bl	fn_08023fa4
	mov	r2, r6
	movs	r1, #0x22
	bl	fn_080207f4
	mov	r0, r6
	bl	fn_08025400
	b.n	.L080145a0
.L08014598:
	ldrh	r0, [r6, #0x22]
	bic.w	r0, r0, #0x600
	strh	r0, [r6, #0x22]
.L080145a0:
	movs	r0, #0
	str	r0, [sp]
	ldrb	r0, [r5, #1]
	cmp	r0, #1
	beq.n	.L080145cc
	cmp	r0, #2
	bne.n	.L080145dc
	ldr	r1, [sp, #0x14]
	add.w	r0, r6, #0x14
	blx	r1				@ F14(child + 0x14)
	ldrsh.w	r1, [r4]
	.inst.n	0x1c49				@ adds r1, r1, #1
	bic.w	r1, r1, #1
	subs	r0, r1, r0
	add.w	r0, r0, r0, lsr #31
	sbfx	r0, r0, #1, #0x10
	b.n	.L080145da
.L080145cc:
	ldr	r1, [sp, #0x14]
	add.w	r0, r6, #0x14
	blx	r1				@ F14(child + 0x14)
	ldrh	r1, [r4]
	subs	r0, r1, r0
	sxth	r0, r0
.L080145da:
	str	r0, [sp]
.L080145dc:
	ldrb	r0, [r5, #3]
	tst	r0, r7
	beq.n	.L080145f8
	ldr	r1, [sp, #0x10]
	add.w	r0, r6, #0x14
	blx	r1				@ F10(child + 0x14)
	ldrh.w	r1, [sp, #8]
	b.n	.L080145f2
.L080145f0:
	b.n	.L0801471e
.L080145f2:
	subs	r0, r1, r0
	strh.w	r0, [sp, #8]
.L080145f8:
	mov	r0, r6
	movs	r1, #0
	movs	r2, #0x6a
	bl	fn_08024bac
	sxth.w	r9, r0
	mov	r0, r6
	movs	r1, #0
	movs	r2, #0x6b
	bl	fn_08024bac
	sxth.w	r10, r0
	mov	r0, r6
	bl	rect_width_plus_one
	str	r0, [sp, #4]
	mov	r0, r6
	bl	rect_height_plus_one
	ubfx	r1, r9, #0xd, #2
	cmp	r1, #1
	bne.n	.L0801464a
	bic.w	r1, r9, #0x6000
	cmp	r1, r8
	bgt.n	.L0801464a
	cmp.w	r1, #0x3e8
	ble.n	.L0801463c
	rsb.w	r1, r1, #0x3e8
.L0801463c:
	ldr	r2, [sp, #4]
	muls	r1, r2, r1
	movs	r2, #0x64
	sdiv	r1, r1, r2
	sxth.w	r9, r1
.L0801464a:
	ubfx	r1, r10, #0xd, #2
	cmp	r1, #1
	bne.n	.L08014670
	bic.w	r1, r10, #0x6000
	cmp	r1, r8
	bgt.n	.L08014670
	cmp.w	r1, #0x3e8
	ble.n	.L08014664
	rsb.w	r1, r1, #0x3e8
.L08014664:
	muls	r1, r0, r1
	movs	r0, #0x64
	sdiv	r0, r1, r0
	sxth.w	r10, r0
.L08014670:
	ldrh	r1, [r6, #0x14]
	ldr	r0, [sp, #0x58]			@ x origin
	ldr	r2, [sp, #0x5c]			@ y origin
	subs	r1, r0, r1
	add.w	r0, r1, r9
	ldrh	r1, [r6, #0x16]
	sxth	r0, r0
	subs	r2, r2, r1
	add.w	r1, r2, r10
	ldrb	r2, [r5, #3]
	sxth	r1, r1
	lsls	r2, r2, #0x1f
	cmp	r2, #0
	beq.n	.L08014696
	ldrsh.w	r2, [sp, #8]
	b.n	.L08014698
.L08014696:
	ldr	r2, [sp]
.L08014698:
	add	r0, r2
	sxth.w	r10, r0
	beq.n	.L080146a4
	ldr	r0, [sp]
	b.n	.L080146a8
.L080146a4:
	ldrsh.w	r0, [sp, #8]
.L080146a8:
	add	r0, r1
	sxth.w	r9, r0
	orrs.w	r0, r10, r9
	beq.n	.L080146ec
	mov	r0, r6
	bl	fn_08025400
	ldrh	r1, [r6, #0x14]
	add.w	r0, r1, r10
	strh	r0, [r6, #0x14]
	ldrh	r1, [r6, #0x18]
	add.w	r0, r1, r10
	strh	r0, [r6, #0x18]
	ldrh	r1, [r6, #0x16]
	add.w	r0, r1, r9
	strh	r0, [r6, #0x16]
	ldrh	r1, [r6, #0x1a]
	add.w	r0, r1, r9
	strh	r0, [r6, #0x1a]
	mov	r0, r6
	bl	fn_08025400
	movs	r3, #0
	mov	r2, r9
	mov	r1, r10
	mov	r0, r6
	bl	fn_0802554c
.L080146ec:
	ldrb	r0, [r5, #3]
	tst	r0, r7
	bne.n	.L0801470c
	ldr	r1, [sp, #0x10]
	add.w	r0, r6, #0x14
	blx	r1				@ F10(child + 0x14)
	ldr	r1, [sp, #0x64]			@ gap
	add	r0, r1
	ldrh.w	r1, [sp, #0xc]
	add	r0, r1
	ldrh.w	r1, [sp, #8]
	add	r0, r1
	b.n	.L0801471a
.L0801470c:
	ldrh.w	r1, [sp, #0xc]
	ldr	r0, [sp, #0x64]			@ gap
	add	r0, r1
	ldrh.w	r1, [sp, #8]
	subs	r0, r1, r0
.L0801471a:
	strh.w	r0, [sp, #8]
.L0801471e:
	ldrb	r0, [r5, #3]
	add	r2, sp, #0x2c
	ubfx	r1, r0, #2, #1
	ldr	r0, [sp, #0x24]
	bl	fn_0801b554
	mov	r6, r0
.L0801472e:
	cmp	r6, #0
	beq.n	.L0801473c
	ldrd	r0, r1, [sp, #0x2c]
	cmp	r0, r1
	bne.w	.L080144e6
.L0801473c:
	add	sp, #0x34
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short	0x0000				@ padding
.L08014744:
	.word	rect_set_width			@ function pointer 0x0801d0cf
.L08014748:
	.word	rect_set_height			@ function pointer 0x0801d0c5
.L0801474c:
	.word	rect_width_0801d076		@ function pointer 0x0801d077
.L08014750:
	.word	rect_height_0801d02a		@ function pointer 0x0801d02b
.L08014754:
	.word	0x00060001

@ ----------------------------------------------------------------------------
@ fn_0801a360 - dispatches an event record to the handler tables of its target
@ object and then forwards it to the parent object.
@
@ Parameter: r0 = event record pointer (word +4 = target object, byte +8 =
@ event code, word +0xc = handler data, byte +0x18 = flags: bit 0 = stop with
@ 0, bit 1 = stop with 1, bit 2 = no parent forwarding). Returns 1 or 0 or the
@ result of fn_08023d54.
@
@ Gets a hook table pointer with read_word_200004ac (0x08021d84) and calls its
@ function at (*table)+8 with (table word, event code); returns 1 when flag
@ bit 1 is set, 0 when bit 0 is set.
@
@ Walks the handler table of the target with fn_08023ef8(target, index):
@ entries (word 0 = function, word 1 = data, byte +8 = filter, bit 7 set =
@ pre-handler) whose filter is 0x80 or matches the event code are called with
@ the record; stops on flag bits.
@
@ Calls fn_08023d54(0, record); when it returns 1 walks the table again for
@ normal handlers (filter byte bit 7 clear, 0 or equal to the event code).
@
@ If the result is 1, the target has a parent (word +4 of the target) and flag
@ bit 2 is clear, event codes other than 0x23 / 0x24 are first checked with
@ all_flag_bits_set(target, 0x4000); a result 0 returns 1; codes 0x11..0x1b,
@ 0x1e, 0x21, 0x22, 0x29, 0x2a, 0x2c stop forwarding (jump table at
@ 0x0801a448); codes 0x23 and 0x24 branch to the parent step before the table
@ (0x0801a42c cmp #35, 0x0801a430 cmp #36, both beq 0x0801a464) and are
@ forwarded, as are codes outside 0x11..0x2c; otherwise the parent replaces
@ word +4 and the function recurses on itself.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801a360,"ax",%progbits
	.global fn_0801a360
	.thumb_func
	.type fn_0801a360, %function
fn_0801a360:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	bl	read_word_200004ac
	cbz	r0, .L0801a37e
	ldr	r0, [r0]
	ldr	r2, [r0, #8]
	cbz	r2, .L0801a374
	ldrb	r1, [r4, #8]
	blx	r2
.L0801a374:
	ldrb	r0, [r4, #0x18]
	lsls	r1, r0, #0x1e
	bmi.n	.L0801a400
	lsls	r0, r0, #0x1f
	bne.n	.L0801a476
.L0801a37e:
	movs	r1, #0
	ldr	r0, [r4, #4]
	bl	fn_08023ef8
	movs	r5, #0
	b.n	.L0801a3bc
.L0801a38a:
	ldrb	r1, [r0, #8]
	lsrs	r2, r1, #7
	beq.n	.L0801a3b2
	cmp	r1, #0x80
	beq.n	.L0801a39e
	ldrb	r2, [r4, #8]
	bic.w	r1, r1, #0x80
	cmp	r1, r2
	bne.n	.L0801a3b2
.L0801a39e:
	ldr	r1, [r0, #4]
	str	r1, [r4, #0xc]
	ldr	r1, [r0]
	mov	r0, r4
	blx	r1
	ldrb	r0, [r4, #0x18]
	lsls	r1, r0, #0x1e
	bmi.n	.L0801a400
	lsls	r0, r0, #0x1f
	bne.n	.L0801a476
.L0801a3b2:
	.inst.n	0x1c6d				@ adds r5, r5, #1
	mov	r1, r5
	ldr	r0, [r4, #4]
	bl	fn_08023ef8
.L0801a3bc:
	cbz	r0, .L0801a3c6
	ldr	r1, [r0]
	cmp	r1, #0
	beq.n	.L0801a3b2
	b.n	.L0801a38a
.L0801a3c6:
	mov	r1, r4
	movs	r0, #0
	bl	fn_08023d54
	movs	r5, r0
	beq.n	.L0801a47a
	movs	r1, #0
	ldr	r0, [r4, #4]
	bl	fn_08023ef8
	movs	r6, #0
	b.n	.L0801a412
.L0801a3de:
	ldr	r1, [r0]
	cbz	r1, .L0801a408
	ldrb	r1, [r0, #8]
	lsls	r2, r1, #0x18
	bmi.n	.L0801a408
	cbz	r1, .L0801a3f0
	ldrb	r2, [r4, #8]
	cmp	r1, r2
	bne.n	.L0801a408
.L0801a3f0:
	ldr	r1, [r0, #4]
	str	r1, [r4, #0xc]
	ldr	r1, [r0]
	mov	r0, r4
	blx	r1
	ldrb	r0, [r4, #0x18]
	lsls	r1, r0, #0x1e
	bpl.n	.L0801a404
.L0801a400:
	movs	r0, #1
	pop	{r4, r5, r6, pc}
.L0801a404:
	lsls	r0, r0, #0x1f
	bne.n	.L0801a476
.L0801a408:
	.inst.n	0x1c76				@ adds r6, r6, #1
	mov	r1, r6
	ldr	r0, [r4, #4]
	bl	fn_08023ef8
.L0801a412:
	cbz	r0, .L0801a41a
	cmp	r5, #1
	beq.n	.L0801a3de
	b.n	.L0801a47a
.L0801a41a:
	cmp	r5, #1
	bne.n	.L0801a47a
	ldr	r0, [r4, #4]
	ldr	r1, [r0, #4]
	cbz	r1, .L0801a47a
	ldrb	r1, [r4, #0x18]
	lsls	r1, r1, #0x1d
	bmi.n	.L0801a47a
	ldrb	r1, [r4, #8]
	cmp	r1, #0x23
	beq.n	.L0801a464
	cmp	r1, #0x24
	beq.n	.L0801a464
	lsls	r1, r5, #0xe
	bl	all_flag_bits_set
	cbz	r0, .L0801a47a
	ldrb	r0, [r4, #8]
	subs	r0, #0x11
	cmp	r0, #0x1c
	bcs.n	.L0801a464
	tbb	[pc, r0]
.L0801a448:
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x11
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x12
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x13
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x14
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x15
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x16
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x17
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x18
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x19
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x1a
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x1b
	.byte	(.L0801a464 - .L0801a448)/2	@ code 0x1c
	.byte	(.L0801a464 - .L0801a448)/2	@ code 0x1d
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x1e
	.byte	(.L0801a464 - .L0801a448)/2	@ code 0x1f
	.byte	(.L0801a464 - .L0801a448)/2	@ code 0x20
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x21
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x22
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x23
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x24
	.byte	(.L0801a464 - .L0801a448)/2	@ code 0x25
	.byte	(.L0801a464 - .L0801a448)/2	@ code 0x26
	.byte	(.L0801a464 - .L0801a448)/2	@ code 0x27
	.byte	(.L0801a464 - .L0801a448)/2	@ code 0x28
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x29
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x2a
	.byte	(.L0801a464 - .L0801a448)/2	@ code 0x2b
	.byte	(.L0801a47a - .L0801a448)/2	@ code 0x2c
.L0801a464:
	ldr	r0, [r4, #4]
	ldr	r0, [r0, #4]
	str	r0, [r4, #4]
	mov	r0, r4
	bl	fn_0801a360
	mov	r5, r0
	cmp	r0, #1
	beq.n	.L0801a47a
.L0801a476:
	movs	r0, #0
	pop	{r4, r5, r6, pc}
.L0801a47a:
	mov	r0, r5
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ clear_sign_bit_64 - clears bit 63 of a 64-bit value.
@ Parameters: r0 = low word, r1 = high word. Returns the 64-bit value (r0 /
@ r1) with bit 63 cleared (AND 0x7fffffffffffffff), the high word AND
@ 0x7fffffff. The value goes through the stack and the doubleword register d0.
@ ----------------------------------------------------------------------------
	.section .text.clear_sign_bit_64,"ax",%progbits
	.global clear_sign_bit_64
	.thumb_func
	.type clear_sign_bit_64, %function
clear_sign_bit_64:
	sub	sp, #8
	strd	r0, r1, [sp]
	bic.w	r0, r1, #0x80000000
	str	r0, [sp, #4]
	.inst.w	0xed9d0b00			@ vldr.64 d0, [sp]
	add	sp, #8
	.inst.w	0xec510b10			@ vmov r0, r1, d0
	bx	lr
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ pointed_words_equal - compares two words through pointers.
@ Parameters: r0 and r1 = pointers to words; returns 1 when *r0 == *r1,
@ otherwise 0.
@ ----------------------------------------------------------------------------
	.section .text.pointed_words_equal,"ax",%progbits
	.p2align 2
	.global pointed_words_equal
	.thumb_func
	.type pointed_words_equal, %function
pointed_words_equal:
	ldr	r0, [r0]
	ldr	r1, [r1]
	cmp	r0, r1
	bne.n	.L0801a9f8
	movs	r0, #1
	bx	lr
.L0801a9f8:
	movs	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801a9fc - running minimum of the masked word of a record.
@ Parameters: r0 = pointer to a record (word at +4), r1 = pointer to a word
@ minimum; returns 0 always. Takes (word at r0+4) AND 0x3fffffff and stores it
@ in *r1 when it is below *r1.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801a9fc,"ax",%progbits
	.p2align 2
	.global fn_0801a9fc
	.thumb_func
	.type fn_0801a9fc, %function
fn_0801a9fc:
	ldr	r0, [r0, #4]
	ldr	r2, [r1]
	bic.w	r0, r0, #0xc0000000
	cmp	r0, r2
	bcs.n	.L0801aa0a
	str	r0, [r1]
.L0801aa0a:
	movs	r0, #0
	bx	lr
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ fn_0801aa10 - measures a row (or column) of children of an object and fills
@ a result record of shorts.
@
@ Parameters: r0 = object pointer, r1 = layout record (byte at +0x03: bit 0 =
@ orientation, bit 1 = limit total, bit 2 = walk backwards), r2 = start index,
@ r3 = limit size; stack: param_5 = gap (short), param_6 = result record of
@ shorts. Returns the index at which the walk stopped.
@
@ Reads fn_08024d14(r0, 0) and fn_080249d8(r0, 0); when bit 1 of the flags is
@ set it compares the first result (flag bit 0 set) or the second result
@ (flag bit 0 clear) with 0x27d1 and clears bit 1 of the flags on equality;
@ selects the size getters rect_height_plus_one (0x08023f22) /
@ rect_width_plus_one (0x08024eb6) by the orientation bit.
@
@ Clears the result record fields [0], [1], [2], [4], [5], [6..7], [8..9];
@ loops over the children with fn_08023d80(r0, index) (step +1 or -1 by bit 2)
@ until none, until index != start and all_flag_bits_set(child, 0x800000) is
@ non-zero, or until the limit is exceeded; skips children for which
@ any_flag_bit_set(child, 0x60001) is non-zero.
@
@ For a child with fn_080249b8(child, 0) == 0 it adds the child size
@ (rect_width_plus_one / rect_height_plus_one) plus the gap to field [2];
@ otherwise it counts a weighted child in field [8], and when result bit 0 of
@ the byte at +0x14 is set it grows an array of 0x14-byte entries with
@ fn_08022bac, copy_bytes_08022ce0 and fn_08022c44 and stores child, two
@ values from fn_08024bac(child, 0, 2/3 or 5/6), the weight and 0.
@
@ Tracks the maximum cross size in field [0], the child count in field [4],
@ subtracts the final gap from [2], sets [1] to the limit when the
@ weighted-child count (field [8]) is non-zero, otherwise to [2].
@
@ On stopping at the start index, steps with fn_0801b554 and stores both sizes
@ with fields [4] = 1, [5] = 0.
@
@ Literal pool: rect_width_plus_one, rect_height_plus_one and the mask
@ 0x00060001.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801aa10,"ax",%progbits
	.p2align 2
	.global fn_0801aa10
	.thumb_func
	.type fn_0801aa10, %function
fn_0801aa10:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0xc
	mov	r6, r1
	ldrd	r11, r4, [sp, #0x40]
	mov	r7, r2
	movs	r1, #0
	ldr	r0, [sp, #0xc]
	bl	fn_08024d14
	mov	r5, r0
	movs	r1, #0
	ldr	r0, [sp, #0xc]
	bl	fn_080249d8
	mov	r1, r0
	ldrb	r0, [r6, #3]
	lsls	r2, r0, #0x1e
	bpl.n	.L0801aa50
	lsls	r3, r0, #0x1f
	movw	r2, #0x27d1
	beq.n	.L0801aa46
	cmp	r5, r2
	beq.n	.L0801aa4a
	b.n	.L0801aa54
.L0801aa46:
	cmp	r1, r2
	bne.n	.L0801aa58
.L0801aa4a:
	bic.w	r0, r0, #2
	strb	r0, [r6, #3]
.L0801aa50:
	lsls	r0, r0, #0x1f
	beq.n	.L0801aa58
.L0801aa54:
	ldr	r0, .L0801ac44			@ rect_width_plus_one
	b.n	.L0801aa5a
.L0801aa58:
	ldr	r0, .L0801ac48			@ rect_height_plus_one
.L0801aa5a:
	mov	r9, r0
	ldrb	r0, [r6, #3]
	lsls	r0, r0, #0x1f
	beq.n	.L0801aa88
	ldr	r0, .L0801ac48			@ rect_height_plus_one
.L0801aa64:
	mov.w	r10, #0
	strh.w	r10, [r4, #2]
	strh.w	r10, [r4, #4]
	str.w	r10, [r4, #0x10]
	strh.w	r10, [r4]
	str.w	r10, [r4, #8]
	str.w	r10, [r4, #0xc]
	mov	r8, r0
	mov	r1, r7
	str	r7, [sp, #4]
	b.n	.L0801abde
.L0801aa88:
	ldr	r0, .L0801ac44			@ rect_width_plus_one
	b.n	.L0801aa64
.L0801aa8c:
	ldr	r0, [sp, #4]
	cmp	r0, r7
	beq.n	.L0801aaa0
	mov.w	r1, #0x800000
	mov	r0, r5
	bl	all_flag_bits_set
	cmp	r0, #0
	bne.n	.L0801ab80
.L0801aaa0:
	ldr	r1, .L0801ac4c			@ 0x00060001
	mov	r0, r5
	bl	any_flag_bit_set
	cmp	r0, #0
	bne.n	.L0801ab82
	movs	r1, #0
	mov	r0, r5
	bl	fn_080249b8
	str	r0, [sp, #8]
	cbz	r0, .L0801ab16
	ldr	r0, [r4, #0x10]
	.inst.n	0x1c40				@ adds r0, r0, #1
	str	r0, [r4, #0x10]
	ldrh	r2, [r4, #4]
	add.w	r1, r2, r11
	strh	r1, [r4, #4]
	ldrb	r1, [r4, #0x14]
	lsls	r1, r1, #0x1f
	beq.n	.L0801aba8
	add.w	r0, r0, r0, lsl #2
	lsls	r0, r0, #2
	bl	fn_08022bac
	str	r0, [sp]
	cmp	r0, #0
	beq.n	.L0801abd2
	ldr	r1, [r4, #0xc]
	cbz	r1, .L0801aaf6
	ldr	r0, [r4, #0x10]
	.inst.n	0x1e40				@ subs r0, r0, #1
	add.w	r0, r0, r0, lsl #2
	lsls	r2, r0, #2
	ldr	r0, [sp]
	bl	copy_bytes_08022ce0
	ldr	r0, [r4, #0xc]
	bl	fn_08022c44
.L0801aaf6:
	ldr	r0, [r4, #0x10]
	add.w	r1, r0, r0, lsl #2
	ldr	r0, [sp]
	add.w	r0, r0, r1, lsl #2
	mov.w	r1, #0
	str.w	r5, [r0, #-0x14]
	ldrb	r0, [r6, #3]
	lsls	r0, r0, #0x1f
	mov	r0, r5
	beq.n	.L0801ab18
	movs	r2, #2
	b.n	.L0801ab1a
.L0801ab16:
	b.n	.L0801ab84
.L0801ab18:
	movs	r2, #5
.L0801ab1a:
	bl	fn_08024bac
	ldr	r1, [r4, #0x10]
	sxth	r0, r0
	add.w	r2, r1, r1, lsl #2
	ldr	r1, [sp]
	add.w	r1, r1, r2, lsl #2
	strh	r0, [r1, #-0x10]
	ldrb	r0, [r6, #3]
	mov.w	r1, #0
	lsls	r0, r0, #0x1f
	mov	r0, r5
	beq.n	.L0801ab40
	movs	r2, #3
	b.n	.L0801ab42
.L0801ab40:
	movs	r2, #6
.L0801ab42:
	bl	fn_08024bac
	ldr	r1, [r4, #0x10]
	sxth	r0, r0
	add.w	r2, r1, r1, lsl #2
	ldr	r1, [sp]
	add.w	r1, r1, r2, lsl #2
	strh	r0, [r1, #-0xe]
	ldr	r0, [r4, #0x10]
	ldr	r1, [sp, #8]
	add.w	r2, r0, r0, lsl #2
	ldr	r0, [sp]
	add.w	r0, r0, r2, lsl #2
	str.w	r1, [r0, #-8]
	ldr	r0, [r4, #0x10]
	add.w	r2, r0, r0, lsl #2
	ldr	r0, [sp]
	add.w	r0, r0, r2, lsl #2
	str.w	r10, [r0, #-4]
	ldr	r0, [sp]
	str	r0, [r4, #0xc]
	b.n	.L0801aba8
.L0801ab80:
	b.n	.L0801abea
.L0801ab82:
	b.n	.L0801abc6
.L0801ab84:
	mov	r0, r5
	mov	r1, r9
	blx	r1
	mov	r1, r0
	ldrb	r0, [r6, #3]
	lsls	r0, r0, #0x1e
	bpl.n	.L0801ab9e
	ldrsh.w	r0, [r4, #4]
	adds	r2, r0, r1
	ldr	r0, [sp, #0x18]
	cmp	r2, r0
	bgt.n	.L0801abea
.L0801ab9e:
	ldrh	r2, [r4, #4]
	add.w	r0, r1, r11
	add	r0, r2
	strh	r0, [r4, #4]
.L0801aba8:
	mov	r0, r5
	mov	r1, r8
	blx	r1
	mov	r1, r0
	ldrsh.w	r0, [r4]
	cmp	r1, r0
	ble.n	.L0801abbe
	mov	r0, r5
	mov	r1, r8
	blx	r1
.L0801abbe:
	strh	r0, [r4]
	ldr	r0, [r4, #8]
	.inst.n	0x1c40				@ adds r0, r0, #1
	str	r0, [r4, #8]
.L0801abc6:
	ldrb	r0, [r6, #3]
	lsls	r0, r0, #0x1d
	bpl.n	.L0801abd4
	mov.w	r0, #0xffffffff
	b.n	.L0801abd6
.L0801abd2:
	b.n	.L0801ac3c
.L0801abd4:
	movs	r0, #1
.L0801abd6:
	ldr	r1, [sp, #4]
	adds	r1, r0, r1
	str	r1, [sp, #4]
	bmi.n	.L0801abea
.L0801abde:
	ldr	r0, [sp, #0xc]
	bl	fn_08023d80
	.inst.n	0x1e05				@ subs r5, r0, #0
	bne.w	.L0801aa8c
.L0801abea:
	ldrsh.w	r0, [r4, #4]
	cmp	r0, #0
	ble.n	.L0801abf8
	sub.w	r0, r0, r11
	strh	r0, [r4, #4]
.L0801abf8:
	ldr	r0, [r4, #0x10]
	cbz	r0, .L0801ac00
	ldr	r0, [sp, #0x18]
	b.n	.L0801ac04
.L0801ac00:
	ldrsh.w	r0, [r4, #4]
.L0801ac04:
	strh	r0, [r4, #2]
	cbz	r5, .L0801ac3c
	ldr	r0, [sp, #4]
	cmp	r0, r7
	bne.n	.L0801ac3c
	ldr	r1, [sp, #0xc]
	add	r2, sp, #4
	ldr	r1, [r1, #8]
	ldr	r1, [r1]
	ldr.w	r5, [r1, r0, lsl #2]
	ldrb	r0, [r6, #3]
	ubfx	r1, r0, #2, #1
	ldr	r0, [sp, #0xc]
	bl	fn_0801b554
	cbz	r5, .L0801ac3c
	mov	r0, r5
	mov	r1, r8
	blx	r1
	strh	r0, [r4]
	mov	r0, r5
	mov	r1, r9
	blx	r1
	strh	r0, [r4, #2]
	movs	r0, #1
	str	r0, [r4, #8]
.L0801ac3c:
	ldr	r0, [sp, #4]
	add	sp, #0x1c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801ac44:
	.word	rect_width_plus_one		@ function pointer 0x08024eb7
.L0801ac48:
	.word	rect_height_plus_one		@ function pointer 0x08023f23
.L0801ac4c:
	.word	0x00060001

@ ----------------------------------------------------------------------------
@ fn_0801ac50 - lays out the children of an object in rows (or columns).
@
@ Parameter: r0 = object pointer (word +8 holds the child list: word 0 = array
@ of children, word 4 = count). No return value.
@
@ Reads layout settings with fn_08024bac(r0, 0, halfword 0x20000546 /
@ 0x20000548 / 0x2000054a / 0x2000054c) into a local record, flag byte at
@ sp+0x17: bit 0 = bit 0 of (first value + 1), bit 1 = bit 2 of the first
@ value, bit 2 = bit 3 of the first value; the other three values are stored
@ as bytes at sp+0x14, sp+0x15, sp+0x16; reads fn_0802491e(r0, 0).
@
@ Reads the gap (fn_08024abc / fn_08024b58), sizes (fn_08023e48 /
@ fn_08023e7c), offsets (fn_08024bac codes 0x32, 0x10, 0x12) and the origin
@ via fn_08024224 / fn_08024216.
@
@ Tests fn_08024d14 and fn_080249d8 against 0x27d1 together with bits in the
@ halfword at +0x22 to drop the alignment (byte at sp+0x16 = 0) and swaps
@ alignment 0 and 1 for the case fn_0802491e == 1 when flag bit 0 is clear.
@
@ In the first pass (when the alignment is non-zero) it walks all children
@ through fn_0801aa10 to sum their sizes, then positions with fn_08028ad0.
@
@ In the second pass it walks the children again with fn_0801aa10 and places
@ each row with fn_08014354(r0, record, index, next, x, y, size, gap, result),
@ frees fn_08022c44(local_40) and advances the position by the row size plus
@ the gap.
@
@ Finally calls fn_08025a00(r0) when either value equals 0x27d1 and
@ fn_080207f4(r0, 0x2b, 0).
@
@ Literal pool: the address 0x20000544.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ac50,"ax",%progbits
	.p2align 2
	.global fn_0801ac50
	.thumb_func
	.type fn_0801ac50, %function
fn_0801ac50:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	ldr	r5, .L0801af1c			@ 0x20000544
	sub	sp, #0x4c
	mov	r4, r0
	movs	r1, #0
	ldrh	r2, [r5, #2]
	bl	fn_08024bac
	ldrb.w	r1, [sp, #0x17]
	adds	r2, r0, #1
	bfi	r1, r2, #0, #1
	lsrs	r2, r0, #2
	bfi	r1, r2, #1, #1
	lsrs	r0, r0, #3
	bfi	r1, r0, #2, #1
	strb.w	r1, [sp, #0x17]
	mov	r0, r4
	movs	r1, #0
	ldrh	r2, [r5, #4]
	bl	fn_08024bac
	strb.w	r0, [sp, #0x14]
	mov	r0, r4
	movs	r1, #0
	ldrh	r2, [r5, #6]
	bl	fn_08024bac
	strb.w	r0, [sp, #0x15]
	mov	r0, r4
	movs	r1, #0
	ldrh	r2, [r5, #8]
	bl	fn_08024bac
	strb.w	r0, [sp, #0x16]
	movs	r1, #0
	mov	r0, r4
	bl	fn_0802491e
	cmp	r0, #1
	beq.n	.L0801acb4
	movs	r0, #0
.L0801acb4:
	mov	r9, r0
	ldrb.w	r0, [sp, #0x17]
	mov.w	r1, #0
	lsls	r0, r0, #0x1f
	mov	r0, r4
	beq.n	.L0801acde
	bl	fn_08024b58
.L0801acc8:
	mov	r10, r0
	ldrb.w	r0, [sp, #0x17]
	mov.w	r1, #0
	lsls	r0, r0, #0x1f
	mov	r0, r4
	beq.n	.L0801ace4
	bl	fn_08024abc
	b.n	.L0801ace8
.L0801acde:
	bl	fn_08024abc
	b.n	.L0801acc8
.L0801ace4:
	bl	fn_08024b58
.L0801ace8:
	str	r0, [sp, #0x1c]
	ldrb.w	r0, [sp, #0x17]
	lsls	r0, r0, #0x1f
	mov	r0, r4
	beq.n	.L0801acfa
	bl	fn_08023e7c
	b.n	.L0801acfe
.L0801acfa:
	bl	fn_08023e48
.L0801acfe:
	str	r0, [sp, #0x18]
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x32
	bl	fn_08024bac
	mov	r5, r0
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x10
	bl	fn_08024bac
	ldrh	r1, [r4, #0x16]
	add	r0, r5
	adds	r6, r0, r1
	mov	r0, r4
	bl	fn_08024224
	subs	r0, r6, r0
	strh.w	r0, [sp, #0x20]
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x12
	bl	fn_08024bac
	ldrh	r1, [r4, #0x14]
	add	r0, r5
	adds	r5, r0, r1
	mov	r0, r4
	bl	fn_08024216
	subs	r0, r5, r0
	strh.w	r0, [sp, #0x40]
	ldrb.w	r0, [sp, #0x17]
	ldrb.w	r6, [sp, #0x16]
	lsls	r0, r0, #0x1f
	beq.n	.L0801ad54
	add	r5, sp, #0x20
	b.n	.L0801ad56
.L0801ad54:
	add	r5, sp, #0x40
.L0801ad56:
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024d14
	str	r0, [sp, #0x44]
	movs	r1, #0
	mov	r0, r4
	bl	fn_080249d8
	mov	r11, r0
	ldrb.w	r0, [sp, #0x17]
	lsls	r1, r0, #0x1f
	beq.n	.L0801ad84
	sub.w	r2, r11, #0x2700
	subs	r2, #0xd1
	bne.n	.L0801ad80
	ldrh	r1, [r4, #0x22]
	lsls	r1, r1, #0x16
	bpl.n	.L0801ad94
.L0801ad80:
	lsls	r1, r0, #0x1f
	bne.n	.L0801ad96
.L0801ad84:
	ldr	r2, [sp, #0x44]
	sub.w	r1, r2, #0x2700
	subs	r1, #0xd1
	bne.n	.L0801ad96
	ldrh	r1, [r4, #0x22]
	lsls	r1, r1, #0x15
	bmi.n	.L0801ad96
.L0801ad94:
	movs	r6, #0
.L0801ad96:
	cmp.w	r9, #0
	beq.n	.L0801adae
	lsls	r0, r0, #0x1f
	bne.n	.L0801adae
	cbz	r6, .L0801ada8
	cmp	r6, #1
	beq.n	.L0801adac
	b.n	.L0801adae
.L0801ada8:
	movs	r6, #1
	b.n	.L0801adae
.L0801adac:
	movs	r6, #0
.L0801adae:
	movs	r7, #0
	strh.w	r7, [sp, #0x3c]
	mov	r8, r7
	cbz	r6, .L0801ae1c
	ldrb.w	r0, [sp, #0x17]
	lsls	r0, r0, #0x1d
	bpl.n	.L0801adc8
	ldr	r0, [r4, #8]
	ldr	r2, [r0, #4]
	.inst.n	0x1e52				@ subs r2, r2, #1
	b.n	.L0801adf4
.L0801adc8:
	movs	r2, #0
	b.n	.L0801adf4
.L0801adcc:
	movs	r0, #0
	str	r0, [sp, #0x38]
	add	r1, sp, #0x24
	ldr	r0, [sp, #0x1c]
	strd	r0, r1, [sp]
	add	r1, sp, #0x14
	mov	r0, r4
	ldr	r3, [sp, #0x18]
	bl	fn_0801aa10
	mov	r2, r0
	ldrh.w	r1, [sp, #0x24]
	add.w	r0, r7, r10
	add	r0, r1
	sxth	r7, r0
	add.w	r8, r8, #1
.L0801adf4:
	ldr	r0, [r4, #8]
	ldr	r0, [r0, #4]
	cmp	r0, r2
	ble.n	.L0801ae00
	cmp	r2, #0
	bge.n	.L0801adcc
.L0801ae00:
	cmp.w	r8, #0
	beq.n	.L0801ae0c
	sub.w	r0, r7, r10
	sxth	r7, r0
.L0801ae0c:
	ldrb.w	r0, [sp, #0x17]
	lsls	r0, r0, #0x1f
	mov	r0, r4
	beq.n	.L0801ae1e
	bl	fn_08023e48
	b.n	.L0801ae22
.L0801ae1c:
	b.n	.L0801ae36
.L0801ae1e:
	bl	fn_08023e7c
.L0801ae22:
	add	r1, sp, #0x3c
	strd	r5, r1, [sp]
	mov	r1, r0
	sxth.w	r3, r8
	mov	r2, r7
	mov	r0, r6
	bl	fn_08028ad0
.L0801ae36:
	ldrb.w	r0, [sp, #0x17]
	lsls	r1, r0, #0x1d
	bpl.n	.L0801ae46
	ldr	r1, [r4, #8]
	ldr	r6, [r1, #4]
	.inst.n	0x1e76				@ subs r6, r6, #1
	b.n	.L0801ae48
.L0801ae46:
	movs	r6, #0
.L0801ae48:
	cmp.w	r9, #0
	beq.n	.L0801ae58
	lsls	r0, r0, #0x1f
	bne.n	.L0801ae58
	ldrh	r0, [r5]
	add	r0, r7
	strh	r0, [r5]
.L0801ae58:
	add	r7, sp, #0x24
.L0801ae5a:
	ldr	r0, [r4, #8]
	ldr	r0, [r0, #4]
	cmp	r0, r6
	ble.n	.L0801aef6
	cmp	r6, #0
	blt.n	.L0801aef6
	movs	r0, #1
	str	r0, [sp, #0x38]
	ldr	r0, [sp, #0x1c]
	strd	r0, r7, [sp]
	mov	r2, r6
	add	r1, sp, #0x14
	mov	r0, r4
	ldr	r3, [sp, #0x18]
	bl	fn_0801aa10
	mov	r8, r0
	cmp.w	r9, #0
	beq.n	.L0801ae96
	ldrb.w	r0, [sp, #0x17]
	lsls	r0, r0, #0x1f
	bne.n	.L0801ae96
	ldrh	r0, [r5]
	ldrh.w	r1, [sp, #0x24]
	subs	r0, r0, r1
	strh	r0, [r5]
.L0801ae96:
	ldrd	r0, r1, [sp, #0x18]
	ldrsh.w	r2, [sp, #0x20]
	add	r3, sp, #8
	str	r2, [sp, #4]
	stm.w	r3, {r0, r1, r7}
	ldrsh.w	r0, [sp, #0x40]
	str	r0, [sp]
	mov	r3, r8
	mov	r2, r6
	add	r1, sp, #0x14
	mov	r0, r4
	bl	fn_08014354
	mov	r6, r8
	ldr	r0, [sp, #0x30]
	bl	fn_08022c44
	movs	r0, #0
	str	r0, [sp, #0x30]
	cmp.w	r9, #0
	beq.n	.L0801aed2
	ldrb.w	r0, [sp, #0x17]
	lsls	r0, r0, #0x1f
	beq.n	.L0801aee8
.L0801aed2:
	ldrh	r0, [r5]
	ldrh.w	r1, [sp, #0x24]
	ldrh.w	r2, [sp, #0x3c]
	add	r1, r0
	add.w	r0, r2, r10
	add	r0, r1
.L0801aee4:
	strh	r0, [r5]
	b.n	.L0801ae5a
.L0801aee8:
	ldrh.w	r2, [sp, #0x3c]
	ldrh	r1, [r5]
	add.w	r0, r2, r10
	subs	r0, r1, r0
	b.n	.L0801aee4
.L0801aef6:
	ldr	r1, [sp, #0x44]
	movw	r0, #0x27d1
	cmp	r1, r0
	beq.n	.L0801af04
	cmp	r11, r0
	bne.n	.L0801af0a
.L0801af04:
	mov	r0, r4
	bl	fn_08025a00
.L0801af0a:
	movs	r2, #0
	movs	r1, #0x2b
	mov	r0, r4
	bl	fn_080207f4
	add	sp, #0x4c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short	0x0000				@ padding
.L0801af1c:
	.word	0x20000544

@ ----------------------------------------------------------------------------
@ fn_0801af20 - moves the selection of an object to the next candidate entry
@ and sends the deselect / select messages.
@
@ Parameters: r0 = object pointer (byte +0x1c: bit 0 = disabled, bit 3 = wrap;
@ word +0xc = current entry pointer; word +0x10 = callback), r1 = function
@ giving the first candidate, r2 = function giving the next candidate. Returns
@ r0 = 1 when the selection changed, 0 when unchanged.
@
@ Returns 0 at once when bit 0 of byte +0x1c is set.
@
@ Picks a candidate with r1(r0) or r2(r0, entry), skipping entries for which
@ fn_080248c8(*entry) has bit 7 set or for which the entry's object or one of
@ its ancestors (fn_08023fa4) has all_flag_bits_set(object, 1) non-zero; gives
@ up when the next candidate equals the first candidate (0x0801af74 cmp
@ r0,r6), or when the list ends and bit 3 (wrap) of byte +0x1c is clear; with
@ wrap set it restarts with r1(r0).
@
@ If the candidate differs from the current entry (word +0xc): sends
@ fn_080207f4(*current, 0xf, fn_0801b298(r0)) and on a result of 1 calls
@ fn_08025400(*current), then stores the candidate, sends fn_080207f4(*new,
@ 0xe, fn_0801b298(r0)) and on 1 calls fn_08025400(*new) and the callback at
@ +0x10, returning 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801af20,"ax",%progbits
	.p2align 2
	.global fn_0801af20
	.thumb_func
	.type fn_0801af20, %function
fn_0801af20:
	push.w	{r0, r1, r2, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r5, r0
	ldrb	r0, [r0, #0x1c]
	mov	r11, r2
	mov.w	r10, #0
	lsls	r0, r0, #0x1f
	bne.n	.L0801aff4
	mov.w	r8, #1
	ldr	r4, [r5, #0xc]
	movs	r6, #0
	mov	r9, r8
.L0801af3c:
	cbnz	r4, .L0801af5e
.L0801af3e:
	ldrb	r0, [r5, #0x1c]
	ubfx	r0, r0, #3, #1
	.inst.n	0x1e40				@ subs r0, r0, #1
	tst	r0, r6
	bne.n	.L0801aff4
	cmp.w	r9, #0
	beq.n	.L0801aff4
	ldr	r1, [sp, #4]
	mov	r0, r5
	blx	r1
	mov.w	r8, #0
	mov	r4, r0
	mov	r9, r8
.L0801af5e:
	cbnz	r6, .L0801af64
	.inst.n	0x1e26				@ subs r6, r4, #0
	beq.n	.L0801aff4
.L0801af64:
	cmp.w	r8, #0
	beq.n	.L0801af78
	mov	r1, r4
	mov	r0, r5
	mov	r2, r11
	blx	r2
	mov	r4, r0
	cmp	r0, r6
	beq.n	.L0801aff4
.L0801af78:
	mov.w	r8, #1
	cmp	r4, #0
	beq.n	.L0801af3e
	ldr	r0, [r4]
	bl	fn_080248c8
	lsls	r0, r0, #0x18
	bmi.n	.L0801af3c
	ldr	r7, [r4]
	b.n	.L0801afce
.L0801af8e:
	movs	r1, #1
	mov	r0, r7
	bl	all_flag_bits_set
	cbz	r0, .L0801afc6
	cbz	r7, .L0801afa6
	movs	r1, #1
	mov	r0, r7
	bl	all_flag_bits_set
	cmp	r0, #0
	bne.n	.L0801af3c
.L0801afa6:
	ldr	r0, [r5, #0xc]
	cmp	r0, r4
	beq.n	.L0801aff4
	cbz	r0, .L0801afdc
	mov	r0, r5
	bl	fn_0801b298
	mov	r2, r0
	ldr	r0, [r5, #0xc]
	movs	r1, #0xf
	ldr	r0, [r0]
	bl	fn_080207f4
	cmp	r0, #1
	bne.n	.L0801aff4
	b.n	.L0801afd4
.L0801afc6:
	mov	r0, r7
	bl	fn_08023fa4
	mov	r7, r0
.L0801afce:
	cmp	r7, #0
	bne.n	.L0801af8e
	b.n	.L0801afa6
.L0801afd4:
	ldr	r0, [r5, #0xc]
	ldr	r0, [r0]
	bl	fn_08025400
.L0801afdc:
	mov	r0, r5
	str	r4, [r5, #0xc]
	bl	fn_0801b298
	mov	r2, r0
	ldr	r0, [r5, #0xc]
	movs	r1, #0xe
	ldr	r0, [r0]
	bl	fn_080207f4
	cmp	r0, #1
	beq.n	.L0801affa
.L0801aff4:
	mov	r0, r10
.L0801aff6:
	pop.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801affa:
	ldr	r0, [r5, #0xc]
	ldr	r0, [r0]
	bl	fn_08025400
	ldr	r1, [r5, #0x10]
	cbz	r1, .L0801b00a
	mov	r0, r5
	blx	r1
.L0801b00a:
	movs	r0, #1
	b.n	.L0801aff6
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ fn_0801b034 - computes a signed value from the halfwords of a record.
@
@ Parameter: r0 = record pointer; returns a signed value.
@
@ Starts from the short at +0x24; when (halfword +0x34 & 6) is 0 adds the
@ short at +0x28, for (halfword +0x34 & 7)>>1 == 2 adds the short at +0x26.
@
@ For value 1 takes the halfwords +0x2a and +0x2c (the latter raised by 0x168
@ when below the former) and +0x26 / +0x28 (the latter raised by 0x168 when
@ below +0x26), builds the midpoint (+0x2a + adjusted +0x2c)/2 and adds +0x26,
@ +0x28 or the midpoint to the short at +0x24 depending on where the midpoint
@ lies; other values return the short at +0x24 unchanged.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b034,"ax",%progbits
	.p2align 2
	.global fn_0801b034
	.thumb_func
	.type fn_0801b034, %function
fn_0801b034:
	push	{r4, r5, r6, lr}
	ldrh	r2, [r0, #0x34]
	ldrh	r1, [r0, #0x24]
	tst.w	r2, #6
	beq.n	.L0801b04e
	ubfx	r2, r2, #1, #2
	cmp	r2, #2
	beq.n	.L0801b052
	cmp	r2, #1
	beq.n	.L0801b058
	b.n	.L0801b094
.L0801b04e:
	ldrh	r0, [r0, #0x28]
	b.n	.L0801b054
.L0801b052:
	ldrh	r0, [r0, #0x26]
.L0801b054:
	add	r0, r1
	b.n	.L0801b092
.L0801b058:
	ldrsh.w	r5, [r0, #0x2c]
	ldrh	r6, [r0, #0x2a]
	uxth	r2, r5
	cmp	r2, r6
	bcs.n	.L0801b06a
	add.w	r2, r2, #0x168
	sxth	r5, r2
.L0801b06a:
	ldrsh.w	r3, [r0, #0x28]
	ldrh	r4, [r0, #0x26]
	uxth	r2, r3
	cmp	r2, r4
	bcs.n	.L0801b07c
	add.w	r0, r2, #0x168
	sxth	r3, r0
.L0801b07c:
	adds	r0, r6, r5
	add.w	r0, r0, r0, lsr #31
	asrs	r0, r0, #1
	cmp	r4, r0
	bge.n	.L0801b08c
	adds	r0, r4, r1
	b.n	.L0801b092
.L0801b08c:
	cmp	r3, r0
	ble.n	.L0801b098
	adds	r0, r2, r1
.L0801b092:
	uxth	r1, r0
.L0801b094:
	sxth	r0, r1
	pop	{r4, r5, r6, pc}
.L0801b098:
	add	r0, r1
	b.n	.L0801b092

@ ----------------------------------------------------------------------------
@ fn_0801b09c - rounds twice a halfword of a record up to a multiple of 4 and
@ adds 0x10.
@ Parameter: r0 = record pointer; returns ((short at +0xc)*2 + 3 &
@ 0xfffffffc) + 0x10.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b09c,"ax",%progbits
	.global fn_0801b09c
	.thumb_func
	.type fn_0801b09c, %function
fn_0801b09c:
	ldrsh.w	r0, [r0, #0xc]
	movs	r1, #3
	add.w	r0, r1, r0, lsl #1
	bic.w	r0, r0, #3
	adds	r0, #0x10
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801b0ae - computes the centre and half size of the square that fits into
@ an object after its four margins.
@
@ Parameters: r0 = object pointer, r1 = pointer to 2 shorts (output centre),
@ r2 = pointer to a short (output half size) or 0. No return value.
@
@ Reads the four margins fn_08024b04, fn_08024b40, fn_08024b94, fn_08024aa4
@ (each with 0), the sizes rect_width_plus_one (0x08024eb6) and
@ rect_height_plus_one (0x08023f22), and takes the smaller of (size1 - left
@ margin - right margin) and (size2 - top margin - bottom margin).
@
@ Half of that (rounded toward zero) is the half size; stores r1[0] =
@ short(+0x14) + half + left margin, r1[1] = short(+0x16) + half + top margin,
@ and *r2 = half when r2 is non-zero.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b0ae,"ax",%progbits
	.global fn_0801b0ae
	.thumb_func
	.type fn_0801b0ae, %function
fn_0801b0ae:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	mov	r9, r1
	mov	r11, r2
	mov	r10, r0
	movs	r1, #0
	bl	fn_08024b04
	mov	r5, r0
	movs	r1, #0
	mov	r0, r10
	bl	fn_08024b40
	mov	r8, r0
	movs	r1, #0
	mov	r0, r10
	bl	fn_08024b94
	mov	r4, r0
	movs	r1, #0
	mov	r0, r10
	bl	fn_08024aa4
	mov	r6, r0
	mov	r0, r10
	bl	rect_width_plus_one
	subs	r1, r0, r5
	sub.w	r7, r1, r8
	mov	r0, r10
	bl	rect_height_plus_one
	subs	r0, r0, r4
	subs	r0, r0, r6
	cmp	r7, r0
	mov	r0, r10
	bge.n	.L0801b106
	bl	rect_width_plus_one
	subs	r1, r0, r5
	sub.w	r0, r1, r8
	b.n	.L0801b10e
.L0801b106:
	bl	rect_height_plus_one
	subs	r0, r0, r4
	subs	r0, r0, r6
.L0801b10e:
	add.w	r0, r0, r0, lsr #31
	sbfx	r0, r0, #1, #0x10
	ldrh.w	r1, [r10, #0x14]
	adds	r2, r0, r5
	add	r1, r2
	strh.w	r1, [r9]
	ldrh.w	r1, [r10, #0x16]
	adds	r2, r0, r4
	add	r1, r2
	strh.w	r1, [r9, #2]
	cmp.w	r11, #0
	beq.n	.L0801b138
	strh.w	r0, [r11]
.L0801b138:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}

@ ----------------------------------------------------------------------------
@ fn_0801b13c - tail call to fn_08024bac with the halfword at 0x20000552.
@ Parameter: r0 = object pointer; returns the result of fn_08024bac(r0, 0,
@ halfword at 0x20000552).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b13c,"ax",%progbits
	.p2align 2
	.global fn_0801b13c
	.thumb_func
	.type fn_0801b13c, %function
fn_0801b13c:
	ldr	r2, .L0801b148			@ 0x20000550
	movs	r1, #0
	ldrh	r2, [r2, #2]
	b.w	fn_08024bac
	.short	0x0000				@ padding
.L0801b148:
	.word	0x20000550

@ ----------------------------------------------------------------------------
@ fn_0801b14c - low byte of a setting of an object.
@ Parameter: r0 = object pointer; returns the low byte of fn_08024bac(r0, 0,
@ halfword at 0x2000055a).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b14c,"ax",%progbits
	.p2align 2
	.global fn_0801b14c
	.thumb_func
	.type fn_0801b14c, %function
fn_0801b14c:
	ldr	r2, .L0801b15c			@ 0x20000550
	push	{r4, lr}
	movs	r1, #0
	ldrh	r2, [r2, #0xa]
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}
.L0801b15c:
	.word	0x20000550

@ ----------------------------------------------------------------------------
@ fn_0801b160 - low byte of a setting of an object.
@ Parameter: r0 = object pointer; returns the low byte of fn_08024bac(r0, 0,
@ halfword at 0x2000055c).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b160,"ax",%progbits
	.p2align 2
	.global fn_0801b160
	.thumb_func
	.type fn_0801b160, %function
fn_0801b160:
	ldr	r2, .L0801b170			@ 0x20000550
	push	{r4, lr}
	movs	r1, #0
	ldrh	r2, [r2, #0xc]
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}
.L0801b170:
	.word	0x20000550

@ ----------------------------------------------------------------------------
@ fn_0801b174 - looks up the offset value of a character code in the glyph
@ table of an object, with a one-entry cache.
@
@ Parameters: r0 = object pointer (word +0x10 = glyph table record), r1 =
@ character code, r2 and r3 = unused halves. Returns an offset value or 0.
@
@ Returns 0 for code 0; first checks the cached pair at (record word +0x14):
@ when its word 0 equals the code, returns its word 1.
@
@ Searches the 0x14-byte range table at record word +8 (count = halfword
@ +0x12 & 0x1ff) for the range holding the code (code - start <= ushort +4);
@ by the range type byte at +0x12: 0 adds ushort +6 to the byte at (range
@ word +0xc)[offset], 1 and 3 binary search with binary_search_with_compare
@ (0x08012d0c, element size 2, comparator u16_pointer_difference 0x0802adcb),
@ 2 adds ushort +6 to the offset.
@
@ Writes the result into the cache pair and returns it; a miss stores 0 in
@ the cache and returns 0.
@
@ Literal pool: the comparator u16_pointer_difference.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b174,"ax",%progbits
	.p2align 2
	.global fn_0801b174
	.thumb_func
	.type fn_0801b174, %function
fn_0801b174:
	push.w	{r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	movs	r7, r1
	beq.n	.L0801b1c4
	ldr	r4, [r0, #0x10]
	ldr	r2, [r4, #0x14]
	cbz	r2, .L0801b18e
	ldr	r0, [r2]
	cmp	r0, r7
	bne.n	.L0801b18e
	ldr	r0, [r2, #4]
.L0801b18a:
	pop.w	{r2, r3, r4, r5, r6, r7, r8, r9, r10, pc}
.L0801b18e:
	ldrh	r0, [r4, #0x12]
	movs	r1, #0
	mov.w	r12, #4
	ubfx	r3, r0, #0, #9
	b.n	.L0801b1b6
.L0801b19c:
	ldr	r6, [r4, #8]
	add.w	r5, r1, r1, lsl #2
	ldr.w	r0, [r6, r5, lsl #2]
	add.w	r5, r12, r5, lsl #2
	ldrh	r5, [r6, r5]
	subs	r0, r7, r0
	cmp	r5, r0
	bcs.n	.L0801b1c8
	.inst.n	0x1c49				@ adds r1, r1, #1
	uxth	r1, r1
.L0801b1b6:
	cmp	r3, r1
	bhi.n	.L0801b19c
	cbz	r2, .L0801b1c4
	str	r7, [r2]
	ldr	r1, [r4, #0x14]
	movs	r0, #0
	str	r0, [r1, #4]
.L0801b1c4:
	movs	r0, #0
	b.n	.L0801b18a
.L0801b1c8:
	add.w	r5, r1, r1, lsl #2
	movs	r1, #0x12
	ldr	r2, [r4, #8]
	add.w	r1, r1, r5, lsl #2
	movs	r6, #0
	ldrb	r1, [r2, r1]
	mov.w	r8, #6
	cmp	r1, #2
	beq.n	.L0801b1f8
	mov.w	r10, #0xc
	cbz	r1, .L0801b200
	ldr.w	r12, .L0801b294			@ u16_pointer_difference
	movs	r2, #0x10
	movs	r3, #8
	cmp	r1, #3
	beq.n	.L0801b212
	cmp	r1, #1
	beq.n	.L0801b246
	b.n	.L0801b284
.L0801b1f8:
	add.w	r1, r8, r5, lsl #2
	ldrh	r1, [r2, r1]
	b.n	.L0801b282
.L0801b200:
	add.w	r1, r10, r5, lsl #2
	add.w	r3, r8, r5, lsl #2
	ldr	r1, [r2, r1]
	ldrh	r2, [r2, r3]
	ldrb	r0, [r1, r0]
	adds	r6, r2, r0
	b.n	.L0801b284
.L0801b212:
	strh.w	r0, [sp, #4]
	str.w	r12, [sp]
	ldr	r0, [r4, #8]
	add.w	r1, r2, r5, lsl #2
	add.w	r9, r3, r5, lsl #2
	ldrh	r2, [r0, r1]
	ldr.w	r1, [r0, r9]
	movs	r3, #2
	add	r0, sp, #4
	bl	binary_search_with_compare
	cbz	r0, .L0801b284
	ldr	r1, [r4, #8]
	ldr.w	r2, [r1, r9]
	subs	r0, r0, r2
	add.w	r2, r8, r5, lsl #2
	asrs	r0, r0, #1
	ldrh	r1, [r1, r2]
	b.n	.L0801b282
.L0801b246:
	strh.w	r0, [sp, #4]
	str.w	r12, [sp]
	ldr	r0, [r4, #8]
	add.w	r1, r2, r5, lsl #2
	add.w	r9, r3, r5, lsl #2
	ldrh	r2, [r0, r1]
	ldr.w	r1, [r0, r9]
	movs	r3, #2
	add	r0, sp, #4
	bl	binary_search_with_compare
	cbz	r0, .L0801b284
	ldr	r1, [r4, #8]
	add.w	r3, r8, r5, lsl #2
	ldr.w	r2, [r1, r9]
	subs	r0, r0, r2
	add.w	r2, r10, r5, lsl #2
	asrs	r0, r0, #1
	ldr	r2, [r1, r2]
	ldrh	r1, [r1, r3]
	ldrh.w	r0, [r2, r0, lsl #1]
.L0801b282:
	adds	r6, r1, r0
.L0801b284:
	ldr	r0, [r4, #0x14]
	cbz	r0, .L0801b28e
	str	r7, [r0]
	ldr	r0, [r4, #0x14]
	str	r6, [r0, #4]
.L0801b28e:
	mov	r0, r6
	b.n	.L0801b18a
	.short	0x0000				@ padding
.L0801b294:
	.word	u16_pointer_difference		@ function pointer 0x0802adcb

@ ----------------------------------------------------------------------------
@ fn_0801b298 - finds the entry whose key word matches, preferring entries in
@ state 2, then state 4, then the last match.
@
@ Parameter: r0 = key value (compared with the word at +0x50 of each entry);
@ returns an entry pointer.
@
@ Iterates entries with fn_08021d90(previous) starting from 0; calls
@ fn_08021e06(entry) for every entry and compares word +0x50 with r0; returns
@ the first one with state 2; remembers the last match and the last match with
@ state 4.
@
@ At the end returns the state-4 match if any, else the last match, else
@ fn_08021d90(0) (tail call).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b298,"ax",%progbits
	.p2align 2
	.global fn_0801b298
	.thumb_func
	.type fn_0801b298, %function
fn_0801b298:
	push.w	{r4, r5, r6, r7, r8, lr}
	movs	r6, #0
	mov	r7, r0
	mov	r5, r6
	mov	r0, r6
	b.n	.L0801b2c8
	nop					@ padding
.L0801b2a8:
	bl	fn_08021e06
	ldr	r1, [r4, #0x50]
	cmp	r1, r7
	bne.n	.L0801b2c6
	cmp	r0, #2
	beq.n	.L0801b2bc
	cmp	r0, #4
	beq.n	.L0801b2c2
	b.n	.L0801b2c4
.L0801b2bc:
	mov	r0, r4
.L0801b2be:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0801b2c2:
	mov	r6, r4
.L0801b2c4:
	mov	r5, r4
.L0801b2c6:
	mov	r0, r4
.L0801b2c8:
	bl	fn_08021d90
	movs	r4, r0
	bne.n	.L0801b2a8
	cbz	r6, .L0801b2d6
	mov	r0, r6
	b.n	.L0801b2be
.L0801b2d6:
	cbz	r5, .L0801b2dc
	mov	r0, r5
	b.n	.L0801b2be
.L0801b2dc:
	pop.w	{r4, r5, r6, r7, r8, lr}
	movs	r0, #0
	b.w	fn_08021d90
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ fn_0801b2e8 - looks up a signed byte for an index pair in the table record
@ of an object.
@
@ Parameters: r0 = object pointer (word +0x10 = table record), r1 = first
@ index, r2 = second index, r3 = spare. Returns a signed byte or 0.
@
@ When bit 13 of the halfword at record+0x12 is set: returns 0 if byte
@ table1[r1] or table2[r2] is 0, otherwise the signed byte at
@ table0[(table1[r1]-1) * byte(+0xd) + (table2[r2]-1)].
@
@ Otherwise looks up the index pair by the top two bits of the word at +8: 0
@ searches 2-byte keys (r1 + r2<<8) with binary_search_with_compare
@ (0x08012d0c, comparator compare_u8_pair 0x0801c167), 1 searches 4-byte keys
@ (r1 + r2<<16) with comparator compare_u16_pair 0x0801c153; returns the
@ signed byte at word +4 [found index], or 0 when absent or for other types.
@
@ Literal pool: compare_u16_pair, compare_u8_pair.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b2e8,"ax",%progbits
	.p2align 2
	.global fn_0801b2e8
	.thumb_func
	.type fn_0801b2e8, %function
fn_0801b2e8:
	push	{r2, r3, r4, r5, r6, lr}
	ldr	r3, [r0, #0x10]
	ldr	r0, [r0, #0x10]
	movs	r5, #0
	ldrh	r3, [r3, #0x12]
	ldr	r4, [r0, #0xc]
	lsls	r6, r3, #0x12
	ldr	r3, [r4, #8]
	bmi.n	.L0801b352
	lsrs	r0, r3, #0x1e
	beq.n	.L0801b32e
	movs	r0, #1
	cmp.w	r0, r3, lsr #0x1e
	bne.n	.L0801b36a
	add.w	r0, r1, r2, lsl #0x10
	ldr	r6, [r4]
	str	r0, [sp, #4]
	ldr	r0, .L0801b370			@ compare_u16_pair
	str	r0, [sp]
	ldr	r0, [r4, #8]
	movs	r3, #4
	bic.w	r2, r0, #0xc0000000
	mov	r1, r6
	add	r0, sp, #4
	bl	binary_search_with_compare
	cbz	r0, .L0801b36a
	subs	r0, r0, r6
	asrs	r0, r0, #2
.L0801b328:
	ldr	r1, [r4, #4]
	ldrsb	r5, [r1, r0]
	b.n	.L0801b36a
.L0801b32e:
	add.w	r0, r1, r2, lsl #8
	ldr	r6, [r4]
	strh.w	r0, [sp, #4]
	ldr	r0, .L0801b374			@ compare_u8_pair
	bic.w	r2, r3, #0xc0000000
	str	r0, [sp]
	movs	r3, #2
	mov	r1, r6
	add	r0, sp, #4
	bl	binary_search_with_compare
	cbz	r0, .L0801b36a
	subs	r0, r0, r6
	asrs	r0, r0, #1
	b.n	.L0801b328
.L0801b352:
	ldr	r0, [r4, #4]
	ldrb	r0, [r0, r1]
	ldrb	r1, [r3, r2]
	cbz	r0, .L0801b36a
	cbz	r1, .L0801b36a
	ldrb	r3, [r4, #0xd]
	ldr	r2, [r4]
	.inst.n	0x1e40				@ subs r0, r0, #1
	smlabb	r0, r0, r3, r2
	.inst.n	0x1e49				@ subs r1, r1, #1
	ldrsb	r5, [r0, r1]
.L0801b36a:
	mov	r0, r5
	pop	{r2, r3, r4, r5, r6, pc}
	.short	0x0000				@ padding
.L0801b370:
	.word	compare_u16_pair		@ function pointer 0x0801c153
.L0801b374:
	.word	compare_u8_pair			@ function pointer 0x0801c167

@ ----------------------------------------------------------------------------
@ fn_0801b378 - computes the rectangle of a circle-shaped element placed on a
@ circle around a centre.
@
@ Parameters: r0 = object pointer, r1 = pointer to 2 shorts (centre), r2 =
@ short (radius), r3 = pointer to 4 shorts (output rectangle). No return
@ value.
@
@ Gets a half size via fn_080248fa(r0, 0x20000) / 2 and an angle
@ fn_0801b034(r0); the factors sine_q15_degrees(angle + 0x5a) and
@ sine_q15_degrees(angle) (scaled by 0x8000, shifted by 15) are multiplied by
@ (r2 - half).
@
@ Output left = centre x + x offset - margin(fn_08024b04(r0, 0x30000)) - half,
@ right = margin(fn_08024b40) + half + centre x + x offset, top = centre y +
@ y offset - margin(fn_08024b94) - half, bottom = margin(fn_08024aa4) + half
@ + centre y + y offset.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b378,"ax",%progbits
	.p2align 2
	.global fn_0801b378
	.thumb_func
	.type fn_0801b378, %function
fn_0801b378:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #4
	mov	r6, r1
	mov	r5, r3
	mov	r7, r2
	mov.w	r1, #0x20000
	ldr	r0, [sp, #4]
	bl	fn_080248fa
	add.w	r0, r0, r0, lsr #31
	asrs	r4, r0, #1
	subs	r7, r7, r4
	ldr	r0, [sp, #4]
	bl	fn_0801b034
	mov	r9, r0
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	smulbb	r0, r0, r7
	asr.w	r8, r0, #0xf
	mov	r0, r9
	bl	sine_q15_degrees
	smulbb	r0, r0, r7
	asrs	r7, r0, #0xf
	mov.w	r9, #0x30000
	mov	r1, r9
	ldr	r0, [sp, #4]
	bl	fn_08024b04
	mov	r11, r0
	mov	r1, r9
	ldr	r0, [sp, #4]
	bl	fn_08024b40
	str	r0, [sp]
	mov	r1, r9
	ldr	r0, [sp, #4]
	bl	fn_08024b94
	mov	r10, r0
	mov	r1, r9
	ldr	r0, [sp, #4]
	bl	fn_08024aa4
	ldrh	r2, [r6]
	add	r0, r4
	add	r2, r8
	sub.w	r1, r2, r11
	subs	r1, r1, r4
	strh	r1, [r5]
	ldrh	r2, [r6]
	ldr	r1, [sp]
	add	r2, r8
	add	r1, r4
	add	r1, r2
	strh	r1, [r5, #4]
	ldrh	r1, [r6, #2]
	adds	r2, r1, r7
	sub.w	r1, r2, r10
	subs	r1, r1, r4
	strh	r1, [r5, #2]
	ldrh	r1, [r6, #2]
	add	r1, r7
	add	r0, r1
	strh	r0, [r5, #6]
	add	sp, #0x14
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
