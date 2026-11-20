@ gfx_11.s - RGB565 conversion and blend helpers, constant white, and the arc bounding box routine
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ rgb_to_565_0801d942 - packs three 8-bit colour components into a 565 halfword.
@ Parameters: r0 = red, r1 = green, r2 = blue (bytes).
@ Returns r0 = ((r >> 3) & 0x1f) << 11 | ((g >> 2) & 0x3f) << 5 | ((b >> 3) & 0x1f).
@ The halfword is assembled in the stack slot [sp] with three bfi inserts
@ (bits 0..4 blue, bits 5..10 green, bits 11..15 red) and returned zero-extended.
@ ----------------------------------------------------------------------------
	.section .text.rgb_to_565_0801d942,"ax",%progbits
	.global rgb_to_565_0801d942
	.thumb_func
	.type rgb_to_565_0801d942, %function
rgb_to_565_0801d942:
	push	{r3, lr}
	lsrs	r3, r2, #3
	ldrh.w	r2, [sp]
	bfi	r2, r3, #0, #5
	strh.w	r2, [sp]
	lsrs	r2, r1, #2
	ldrh.w	r1, [sp]
	bfi	r1, r2, #5, #6
	strh.w	r1, [sp]
	lsrs	r1, r0, #3
	ldrh.w	r0, [sp]
	bfi	r0, r1, #11, #5
	strh.w	r0, [sp]
	uxth	r0, r0
	pop	{r3, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ blend_565_0801d974 - blends two 565 colours with a weight.
@ Parameters: r0 = colour a (565), r1 = colour b (565), r2 = weight 0 to 255.
@ Returns r0 = 565 halfword.
@ Each colour is replicated into both halves of a word (x | x << 16) and masked
@ with 0x07e0f81f (spreads red, green and blue apart). With w = (weight + 4) >> 3:
@ result = (b + ((w * (a - b)) >> 5)) & 0x07e0f81f, then the two halves are
@ folded with an OR (r0 | r0 >> 16) and the low halfword is returned (also stored at [sp]).
@ ----------------------------------------------------------------------------
	.section .text.blend_565_0801d974,"ax",%progbits
	.p2align 2
	.global blend_565_0801d974
	.thumb_func
	.type blend_565_0801d974, %function
blend_565_0801d974:
	push	{r3, lr}
	.inst.n 0x1d12			@ adds r2, r2, #4
	lsrs	r3, r2, #3
	ldr	r2, .L0801d9a4
	uxth	r1, r1
	uxth	r0, r0
	orr.w	r1, r1, r1, lsl #16
	orr.w	r0, r0, r0, lsl #16
	ands	r1, r2
	ands	r0, r2
	subs	r0, r0, r1
	muls	r0, r3, r0
	add.w	r0, r1, r0, lsr #5
	ands	r0, r2
	orr.w	r0, r0, r0, lsr #16
	strh.w	r0, [sp]
	uxth	r0, r0
	pop	{r3, pc}
	.short	0x0000			@ padding
.L0801d9a4:
	.word	0x07e0f81f		@ mask for red, green and blue after spreading

@ ----------------------------------------------------------------------------
@ blend_565_0801d9a8 - blends two 565 colours with a weight (same code as
@ blend_565_0801d974, own literal).
@ Parameters: r0 = colour a (565), r1 = colour b (565), r2 = weight 0 to 255.
@ Returns r0 = 565 halfword.
@ With w = (weight + 4) >> 3 and the colours spread by the mask 0x07e0f81f:
@ result = (b + ((w * (a - b)) >> 5)) & 0x07e0f81f, halves folded with an OR.
@ ----------------------------------------------------------------------------
	.section .text.blend_565_0801d9a8,"ax",%progbits
	.p2align 2
	.global blend_565_0801d9a8
	.thumb_func
	.type blend_565_0801d9a8, %function
blend_565_0801d9a8:
	push	{r3, lr}
	.inst.n 0x1d12			@ adds r2, r2, #4
	lsrs	r3, r2, #3
	ldr	r2, .L0801d9d8
	uxth	r1, r1
	uxth	r0, r0
	orr.w	r1, r1, r1, lsl #16
	orr.w	r0, r0, r0, lsl #16
	ands	r1, r2
	ands	r0, r2
	subs	r0, r0, r1
	muls	r0, r3, r0
	add.w	r0, r1, r0, lsr #5
	ands	r0, r2
	orr.w	r0, r0, r0, lsr #16
	strh.w	r0, [sp]
	uxth	r0, r0
	pop	{r3, pc}
	.short	0x0000			@ padding
.L0801d9d8:
	.word	0x07e0f81f		@ mask for red, green and blue after spreading

@ ----------------------------------------------------------------------------
@ blend_565_0801d9dc - blends two 565 colours with a weight (same code as
@ blend_565_0801d974, own literal).
@ Parameters: r0 = colour a (565), r1 = colour b (565), r2 = weight 0 to 255.
@ Returns r0 = 565 halfword.
@ With w = (weight + 4) >> 3 and the colours spread by the mask 0x07e0f81f:
@ result = (b + ((w * (a - b)) >> 5)) & 0x07e0f81f, halves folded with an OR.
@ ----------------------------------------------------------------------------
	.section .text.blend_565_0801d9dc,"ax",%progbits
	.p2align 2
	.global blend_565_0801d9dc
	.thumb_func
	.type blend_565_0801d9dc, %function
blend_565_0801d9dc:
	push	{r3, lr}
	.inst.n 0x1d12			@ adds r2, r2, #4
	lsrs	r3, r2, #3
	ldr	r2, .L0801da0c
	uxth	r1, r1
	uxth	r0, r0
	orr.w	r1, r1, r1, lsl #16
	orr.w	r0, r0, r0, lsl #16
	ands	r1, r2
	ands	r0, r2
	subs	r0, r0, r1
	muls	r0, r3, r0
	add.w	r0, r1, r0, lsr #5
	ands	r0, r2
	orr.w	r0, r0, r0, lsr #16
	strh.w	r0, [sp]
	uxth	r0, r0
	pop	{r3, pc}
	.short	0x0000			@ padding
.L0801da0c:
	.word	0x07e0f81f		@ mask for red, green and blue after spreading

@ ----------------------------------------------------------------------------
@ blend_565_0801da10 - blends two 565 colours with a weight (same code as
@ blend_565_0801d974, own literal).
@ Parameters: r0 = colour a (565), r1 = colour b (565), r2 = weight 0 to 255.
@ Returns r0 = 565 halfword.
@ With w = (weight + 4) >> 3 and the colours spread by the mask 0x07e0f81f:
@ result = (b + ((w * (a - b)) >> 5)) & 0x07e0f81f, halves folded with an OR.
@ ----------------------------------------------------------------------------
	.section .text.blend_565_0801da10,"ax",%progbits
	.p2align 2
	.global blend_565_0801da10
	.thumb_func
	.type blend_565_0801da10, %function
blend_565_0801da10:
	push	{r3, lr}
	.inst.n 0x1d12			@ adds r2, r2, #4
	lsrs	r3, r2, #3
	ldr	r2, .L0801da40
	uxth	r1, r1
	uxth	r0, r0
	orr.w	r1, r1, r1, lsl #16
	orr.w	r0, r0, r0, lsl #16
	ands	r1, r2
	ands	r0, r2
	subs	r0, r0, r1
	muls	r0, r3, r0
	add.w	r0, r1, r0, lsr #5
	ands	r0, r2
	orr.w	r0, r0, r0, lsr #16
	strh.w	r0, [sp]
	uxth	r0, r0
	pop	{r3, pc}
	.short	0x0000			@ padding
.L0801da40:
	.word	0x07e0f81f		@ mask for red, green and blue after spreading

@ ----------------------------------------------------------------------------
@ rgb565_to_argb8888 - expands a 565 halfword to an opaque 32-bit colour.
@ Parameter: r0 = 565 halfword. Returns r0 = 0xff000000 | R << 16 | G << 8 | B.
@ R = (r5 * 0x107 + 7) >> 5, G = (g6 * 0x103 + 3) >> 6, B = (b5 * 0x107 + 7) >> 5,
@ where r5 = bits 11..15, g6 = bits 5..10, b5 = bits 0..4 of the input; each result
@ is inserted into its byte with bfi; the alpha byte 0xff is inserted last.
@ The first insert starts from the incoming r1 and the later inserts overwrite
@ the other three bytes.
@ ----------------------------------------------------------------------------
	.section .text.rgb565_to_argb8888,"ax",%progbits
	.global rgb565_to_argb8888
	.thumb_func
	.type rgb565_to_argb8888, %function
rgb565_to_argb8888:
	uxth	r2, r0
	lsrs	r0, r2, #11
	rsb	r3, r0, r0, lsl #3
	add.w	r0, r3, r0, lsl #8
	.inst.n 0x1dc0			@ adds r0, r0, #7
	lsrs	r0, r0, #5
	bfi	r1, r0, #16, #8
	mov	r0, r1
	ubfx	r1, r2, #5, #6
	add.w	r3, r1, r1, lsl #1
	add.w	r1, r3, r1, lsl #8
	.inst.n 0x1cc9			@ adds r1, r1, #3
	lsrs	r1, r1, #6
	bfi	r0, r1, #8, #8
	and	r1, r2, #0x1f
	rsb	r2, r1, r1, lsl #3
	add.w	r1, r2, r1, lsl #8
	.inst.n 0x1dc9			@ adds r1, r1, #7
	lsrs	r1, r1, #5
	bfi	r0, r1, #0, #8
	movs	r1, #0xff
	bfi	r0, r1, #24, #8
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801da8a - returns the 565 value 0xffff.
@ No parameters. Calls rgb_to_565_0801d912 with r0 = r1 = r2 = 0xff, stores the
@ result at [sp] and returns the low halfword of it.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801da8a,"ax",%progbits
	.global fn_0801da8a
	.thumb_func
	.type fn_0801da8a, %function
fn_0801da8a:
	movs	r2, #0xff
	push	{r3, lr}
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d912
	str	r0, [sp]
	ldrh.w	r0, [sp]
	pop	{r3, pc}

@ ----------------------------------------------------------------------------
@ fn_0801da9e - returns the halfword 0xffff.
@ No parameters. Builds it in r1 with three bfi inserts (field value 0x1f at
@ bit 0, 0x3f at bit 5, 0x1f at bit 11, each followed by uxth where shown),
@ stores it to [sp] and returns the halfword read back from [sp].
@ ----------------------------------------------------------------------------
	.section .text.fn_0801da9e,"ax",%progbits
	.global fn_0801da9e
	.thumb_func
	.type fn_0801da9e, %function
fn_0801da9e:
	push	{r3, lr}
	movs	r0, #0x1f
	ldrh.w	r1, [sp]
	movs	r2, #0x3f
	bfi	r1, r0, #0, #5
	uxth	r1, r1
	bfi	r1, r2, #5, #6
	uxth	r1, r1
	bfi	r1, r0, #11, #5
	strh.w	r1, [sp]
	uxth	r0, r1
	str	r0, [sp]
	ldrh.w	r0, [sp]
	pop	{r3, pc}

@ ----------------------------------------------------------------------------
@ arc_bounding_box - computes the bounding box of an arc segment.
@ Parameters: r0 = centre x (cx), r1 = centre y (cy), r2 = radius R (halfword,
@ sign-extended), r3 = start angle a0 in degrees; stack: [sp+0x38] = end angle a1,
@ [sp+0x3c] = line width w, [sp+0x40] = flag f, [sp+0x44] = pointer o to four
@ output halfwords. No return value. Writes o[0] = x0, o[1] = y0, o[2] = x1, o[3] = y1.
@ The stack offsets are seen after the nine register push and sub sp,#0x14.
@ S = sine_q15_degrees (0x08027ba8, 32767 * sin of the angle in degrees).
@ Ri = sxth(R - w) (inner radius, kept at [sp+0]); m = 0 when f = 0, else
@ w/2 + 1 (w + (w >>> 31) asr 1, plus 1) in r5.
@ Full box: when a1 = a0 + 0x168 (compare at 0x0801de7c) or one of the cases below
@ selects it (label 0x0801e182), writes o = {sxth(cx - R), sxth(cy - R),
@ sxth(cx + R), sxth(cy + R)} (the four values prepared at the entry and kept in
@ [sp+0x10], r7, r2 and r3).
@ Otherwise a0 and a1 above 0x168 (unsigned compare) have 0x168 subtracted once
@ (uxth); quadrant q0 = a0 / 0x5a and q1 = a1 / 0x5a (udiv, uxtb), a value 4
@ becomes 3.
@ Same quadrant (q0 = q1) with a0 <= a1 (unsigned):
@   q = 0: x0 = cx + (S(a1+90)*Ri >> 15) - m, y0 = cy + (S(a0)*Ri >> 15) - m,
@          x1 = cx + (S(a0+90)*R >> 15) + m, y1 = cy + (S(a1)*R >> 15) + m
@   q = 1: x0 = cx + (S(a1+90)*R >> 15) - m, y0 = cy + (S(a1)*Ri >> 15) - m,
@          x1 = cx + (S(a0+90)*Ri >> 15) + m, y1 = cy + (S(a0)*R >> 15) + m
@   q = 2: x0 = cx + (S(a0+90)*R >> 15) - m, y0 = cy + (S(a1)*R >> 15) - m,
@          x1 = cx + (S(a1+90)*Ri >> 15) + m, y1 = cy + (S(a0)*Ri >> 15) + m
@   q = 3: x0 = cx + (S(a0+90)*Ri >> 15) - m, y0 = cy + (S(a0)*R >> 15) - m,
@          x1 = cx + (S(a1+90)*R >> 15) + m, y1 = cy + (S(a1)*Ri >> 15) + m
@   any other q returns without writing.
@ Adjacent quadrants (q0, q1):
@   (0,1): x0 = cx + (S(a1+90)*R >> 15) - m, y0 = cy + (S(g)*Ri >> 15) - m with
@          g = a1 when S(a1) < S(a0) else a0, x1 = cx + (S(a0+90)*R >> 15) + m,
@          y1 = cy + R + m
@   (1,2): x0 = cx - R - m, y0 = cy + (S(a1)*R >> 15) - m, x1 = cx +
@          (S(g)*Ri >> 15) + m with g = a1+90 when S(a0+90) <= S(a1+90) else a0+90,
@          y1 = cy + (S(a0)*R >> 15) + m
@   (2,3): x0 = cx + (S(a0+90)*R >> 15) - m, y0 = cy - R - m, x1 = cx +
@          (S(a1+90)*R >> 15) + m, y1 = cy + (S(g)*Ri >> 15) + m with g = a1 when
@          S(a1)*Ri > S(a0)*Ri (signed products) else a0
@   (3,0): x0 = cx + (S(g)*Ri >> 15) - m with g = a0+90 when S(a1+90) >= S(a0+90)
@          else a1+90, y0 = cy + (S(a0)*R >> 15) - m, x1 = cx + R + m,
@          y1 = cy + (S(a1)*R >> 15) + m
@ Every other combination (including q0 = q1 with a0 > a1) selects the full box.
@ All sums are stored with strh (low 16 bits); products use smulbb.
@ The halfword at 0x0801dfd2 (b.n to the exit) is not a branch target.
@ ----------------------------------------------------------------------------
	.section .text.arc_bounding_box,"ax",%progbits
	.global arc_bounding_box
	.thumb_func
	.type arc_bounding_box, %function
arc_bounding_box:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x14
	mov	r10, r0
	sxth	r0, r2
	mov	r12, r2
	mov	r11, r1
	sxth.w	r9, r2
	sub.w	lr, r10, r0
	ldr.w	r8, [sp, #0x38]
	sxth.w	r2, lr
	str	r2, [sp, #0x10]
	sub.w	r2, r11, r0
	sxth	r7, r2
	str	r2, [sp, #0xc]
	add.w	r2, r10, r0
	add.w	r1, r3, #0x168
	ldr	r4, [sp, #0x44]
	add	r0, r11
	mov	r6, r3
	str	r2, [sp, #0x8]
	sxth	r2, r2
	sxth	r3, r0
	str	r0, [sp, #0x4]
	cmp	r8, r1
	beq.n	.L0801df7c
	mov.w	r1, #0x168
	cmp	r6, r1
	bls.n	.L0801de8e
	sub.w	r6, r6, #0x168
	uxth	r6, r6
.L0801de8e:
	cmp	r8, r1
	bls.n	.L0801de9a
	sub.w	r0, r8, #0x168
	uxth.w	r8, r0
.L0801de9a:
	ldr	r1, [sp, #0x3c]
	sub.w	r0, r12, r1
	sxth	r0, r0
	str	r0, [sp]
	ldr	r0, [sp, #0x40]
	cbz	r0, .L0801deb0
	add.w	r0, r1, r1, lsr #31
	asrs	r0, r0, #1
	.inst.n 0x1c40			@ adds r0, r0, #1
.L0801deb0:
	sxth	r5, r0
	movs	r1, #0x5a
	udiv	r0, r6, r1
	udiv	r1, r8, r1
	uxtb	r0, r0
	uxtb	r1, r1
	cmp	r0, #4
	bne.n	.L0801dec6
	movs	r0, #3
.L0801dec6:
	cmp	r1, #4
	bne.n	.L0801decc
	movs	r1, #3
.L0801decc:
	cmp	r0, r1
	bne.n	.L0801dfce
	cmp	r6, r8
	bhi.n	.L0801dfce
	cbz	r0, .L0801df32
	cmp	r0, #1
	beq.n	.L0801df84
	cmp	r0, #2
	beq.n	.L0801dfd0
	cmp	r0, #3
	bne.n	.L0801dfe0
	@ same quadrant 3
	add.w	r0, r6, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r1, r0, r1
	add.w	r0, r10, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4]
	sxth	r0, r6
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r11, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4, #2]
	add.w	r0, r8, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r10, r1, asr #15
	add	r0, r5
	strh	r0, [r4, #4]
	sxth.w	r0, r8
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r1, r0, r1
	b.n	.L0801e1e8
	@ same quadrant 0
.L0801df32:
	sxth	r0, r6
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r1, r0, r1
	add.w	r0, r11, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4, #2]
	adds	r6, #0x5a
	sxth	r0, r6
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r10, r1, asr #15
	add	r0, r5
	strh	r0, [r4, #4]
	sxth.w	r0, r8
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r11, r1, asr #15
	add	r0, r5
	strh	r0, [r4, #6]
	add.w	r0, r8, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldr	r1, [sp]
	b.n	.L0801df7e
.L0801df7c:
	b.n	.L0801e14c
.L0801df7e:
	smulbb	r1, r0, r1
	b.n	.L0801dfd8
	@ same quadrant 1
.L0801df84:
	sxth	r0, r6
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r11, r1, asr #15
	add	r0, r5
	strh	r0, [r4, #6]
	adds	r6, #0x5a
	sxth	r0, r6
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r1, r0, r1
	add.w	r0, r10, r1, asr #15
	add	r0, r5
	strh	r0, [r4, #4]
	sxth.w	r0, r8
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r1, r0, r1
	add.w	r0, r11, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4, #2]
	add.w	r0, r8, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	b.n	.L0801dfd4
.L0801dfce:
	b.n	.L0801e03e
.L0801dfd0:
	b.n	.L0801dfe6
	b.n	.L0801dfe0
.L0801dfd4:
	smulbb	r1, r0, r9
.L0801dfd8:
	add.w	r0, r10, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4]
	@ shared exit
.L0801dfe0:
	add	sp, #0x14
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	@ same quadrant 2
.L0801dfe6:
	add.w	r0, r6, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r10, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4]
	sxth	r0, r6
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r1, r0, r1
	add.w	r0, r11, r1, asr #15
	add	r0, r5
	strh	r0, [r4, #6]
	sxth.w	r0, r8
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r11, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4, #2]
	add.w	r0, r8, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r1, r0, r1
	add.w	r0, r10, r1, asr #15
	add	r0, r5
	strh	r0, [r4, #4]
	b.n	.L0801dfe0
	@ different quadrants
.L0801e03e:
	cbz	r0, .L0801e04e
	cmp	r0, #1
	beq.n	.L0801e0b4
	cmp	r0, #2
	beq.n	.L0801e10c
	cmp	r0, #3
	beq.n	.L0801e14a
	b.n	.L0801e182
.L0801e04e:
	cmp	r1, #1
	bne.n	.L0801e14c
	add.w	r0, r8, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r10, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4]
	sxth.w	r0, r8
	str	r0, [sp, #0x8]
	bl	sine_q15_degrees
	mov	r7, r0
	sxth	r0, r6
	mov	r8, r0
	bl	sine_q15_degrees
	cmp	r7, r0
	bge.n	.L0801e084
	ldr	r0, [sp, #0x8]
	b.n	.L0801e086
.L0801e084:
	mov	r0, r8
.L0801e086:
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r1, r0, r1
	add.w	r0, r11, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4, #2]
	adds	r6, #0x5a
	sxth	r0, r6
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r10, r1, asr #15
	add	r0, r5
	strh	r0, [r4, #4]
	ldr	r0, [sp, #0x4]
.L0801e0ae:
	add	r0, r5
	strh	r0, [r4, #6]
	b.n	.L0801dfe0
.L0801e0b4:
	cmp	r1, #2
	bne.n	.L0801e182
	sub.w	r0, lr, r5
	strh	r0, [r4]
	sxth.w	r0, r8
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r11, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4, #2]
	add.w	r0, r6, #0x5a
	sxth	r0, r0
	str	r0, [sp, #0x4]
	bl	sine_q15_degrees
	mov	r7, r0
	add.w	r0, r8, #0x5a
	sxth	r0, r0
	mov	r8, r0
	bl	sine_q15_degrees
	cmp	r7, r0
	ble.n	.L0801e0f4
	ldr	r0, [sp, #0x4]
	b.n	.L0801e0f6
.L0801e0f4:
	mov	r0, r8
.L0801e0f6:
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r1, r0, r1
	add.w	r0, r10, r1, asr #15
	add	r0, r5
	strh	r0, [r4, #4]
	sxth	r0, r6
	b.n	.L0801e1e0
.L0801e10c:
	cmp	r1, #3
	bne.n	.L0801e182
	add.w	r0, r6, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r10, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4]
	ldr	r0, [sp, #0xc]
	subs	r0, r0, r5
	strh	r0, [r4, #2]
	add.w	r0, r8, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r10, r1, asr #15
	add	r0, r5
	strh	r0, [r4, #4]
	sxth.w	r0, r8
	mov	r8, r0
	b.n	.L0801e14e
.L0801e14a:
	b.n	.L0801e180
.L0801e14c:
	b.n	.L0801e182
.L0801e14e:
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r7, r0, r1
	sxth	r0, r6
	mov	r6, r0
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r0, r0, r1
	cmp	r7, r0
	ble.n	.L0801e16e
	mov	r0, r8
	b.n	.L0801e170
.L0801e16e:
	mov	r0, r6
.L0801e170:
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r0, r0, r1
	add.w	r0, r11, r0, asr #15
	b.n	.L0801e0ae
.L0801e180:
	cbz	r1, .L0801e18e
	@ full box
.L0801e182:
	ldr	r0, [sp, #0x10]
	strh	r0, [r4]
	strh	r7, [r4, #2]
	strh	r2, [r4, #4]
	strh	r3, [r4, #6]
	b.n	.L0801dfe0
.L0801e18e:
	add.w	r0, r8, #0x5a
	sxth	r0, r0
	str	r0, [sp, #0xc]
	bl	sine_q15_degrees
	mov	r7, r0
	add.w	r0, r6, #0x5a
	sxth	r0, r0
	str	r0, [sp, #0x4]
	bl	sine_q15_degrees
	cmp	r7, r0
	bge.n	.L0801e1b0
	ldr	r0, [sp, #0xc]
	b.n	.L0801e1b2
.L0801e1b0:
	ldr	r0, [sp, #0x4]
.L0801e1b2:
	bl	sine_q15_degrees
	ldr	r1, [sp]
	smulbb	r1, r0, r1
	add.w	r0, r10, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4]
	sxth	r0, r6
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
	add.w	r0, r11, r1, asr #15
	subs	r0, r0, r5
	strh	r0, [r4, #2]
	ldr	r0, [sp, #0x8]
	add	r0, r5
	strh	r0, [r4, #4]
	sxth.w	r0, r8
.L0801e1e0:
	bl	sine_q15_degrees
	smulbb	r1, r0, r9
.L0801e1e8:
	add.w	r0, r11, r1, asr #15
	b.n	.L0801e0ae
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0801e1f0 - reports "No data" for a missing object.
@ Parameters: r0 = object pointer, r1 = structure pointer (byte +0xb is tested),
@ r2 = rectangle pointer, r3 = flag. No return value.
@ When r3 is 0, tail-calls fn_08029a76(r0, r2, "No\ndata").
@ Otherwise, when byte r1+0xb is above 2: calls the function pointer at word
@ r0+0x18 with r0 as argument, or fn_08014da2(r0) when that pointer is 0; when
@ the result is 0, tail-calls fn_08029a76(r0, r2, "No\ndata"). Otherwise returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e1f0,"ax",%progbits
	.p2align 2
	.global fn_0801e1f0
	.thumb_func
	.type fn_0801e1f0, %function
fn_0801e1f0:
	push	{r4, r5, r6, lr}
	mov	r6, r2
	mov	r4, r0
	cbz	r3, .L0801e208
	ldrb	r0, [r1, #0xb]
	cmp	r0, #2
	bls.n	.L0801e224
	ldr	r5, [r4, #0x18]
	mov	r0, r4
	cbz	r5, .L0801e20e
	blx	r5
	b.n	.L0801e212
.L0801e208:
	adr	r2, .L0801e228
	mov	r1, r6
	b.n	.L0801e21c
.L0801e20e:
	bl	fn_08014da2
.L0801e212:
	cmp	r0, #0
	bne.n	.L0801e224
	adr	r2, .L0801e228
	mov	r1, r6
	mov	r0, r4
.L0801e21c:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08029a76
.L0801e224:
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L0801e228:
	.asciz	"No\ndata"		@ text passed to fn_08029a76

@ ----------------------------------------------------------------------------
@ fn_0801e230 - calls the function pointer at word +0x14 of an object.
@ Parameter: r0 = object pointer; the stack argument at [sp+0x10] (after the
@ push) is copied to [sp] before the call. When the pointer at r0+0x14 is
@ nonzero it is called with blx; otherwise nothing happens.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e230,"ax",%progbits
	.p2align 2
	.global fn_0801e230
	.thumb_func
	.type fn_0801e230, %function
fn_0801e230:
	push	{r3, r4, r5, lr}
	ldr	r4, [r0, #0x14]
	ldr	r5, [sp, #0x10]
	cmp	r4, #0
	beq.n	.L0801e23e
	str	r5, [sp]
	blx	r4
.L0801e23e:
	pop	{r3, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_0801e240 - initialises a 0x18-byte structure.
@ Parameter: r0 = structure pointer. No return value.
@ Clears 0x18 bytes with clear_bytes(r0, 0x18). Then halfword +8 = the result of
@ rgb_to_565_0801d8b2(0, 0, 0), byte +0xb = 0xff, halfword +2 = 0x100, byte +0x14 = 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e240,"ax",%progbits
	.p2align 2
	.global fn_0801e240
	.thumb_func
	.type fn_0801e240, %function
fn_0801e240:
	push	{r3, r4, r5, lr}
	mov	r4, r0
	movs	r1, #0x18
	bl	clear_bytes
	movs	r2, #0
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d8b2
	str	r0, [sp]
	ldrh.w	r0, [sp]
	str	r0, [sp]
	ldrh.w	r0, [sp]
	strh	r0, [r4, #8]
	movs	r0, #0xff
	strb	r0, [r4, #0xb]
	.inst.n 0x1c40			@ adds r0, r0, #1
	strh	r0, [r4, #2]
	movs	r0, #1
	strb	r0, [r4, #0x14]
	pop	{r3, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ no_op - returns at once and changes nothing (bx lr).
@ No parameters.
@ ----------------------------------------------------------------------------
	.section .text.no_op,"ax",%progbits
	.p2align 2
	.global no_op
	.thumb_func
	.type no_op, %function
no_op:
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0801e274 - draws a text string with style, alignment, selection and
@ inline colour codes into a rectangle.
@ Parameters: r0 = target object O (saved at [sp+0xd4]), r1 = style record Y,
@ r2 = destination rectangle R (4 halfwords x1, y1, x2, y2), r3 = text pointer T;
@ fifth argument on the stack ([sp+0x108]) = scroll record Z or 0.
@ The four register arguments are pushed with the registers; no return value.
@ Returns at once when byte Y+0x1a <= 2, word Y+0 (font F) is 0, word O+0x1c is 0,
@ T is 0, byte [T] is 0, or rect_intersect(sp+0xb8, R, word O+8) returns 0
@ (0x0801e27a..0x0801e2ba).
@ Copies 0x20 bytes of Y to sp+0x48 with copy_bytes_080070dc (the working style,
@ colour halfword at +0xc).
@ fp = byte Y+0x1c (0 becomes 1) is the alignment code. Width W = halfword R+4 -
@ R+0 + 1, or, when bit 1 of byte Y+0x1d is set, fn_08027d30(sp+0x18, T, F,
@ short Y+0x14, short Y+0x12, 0x1fff, byte Y+0x1d) and its first halfword.
@ step = short Y+0x12 + short F+8; x = R.x1, y = R.y1 + short Y+0x18. With Z
@ nonzero, short Y+0x18 = 0 and R.y1 < 0: when |Z.word8 - R.y1| > 1024 - 2*step,
@ Z.word0 is set to -1; when Z.word0 >= 0 it becomes the start offset and y +=
@ halfword Z+4 (0x0801e332..0x0801e372).
@ First line end e = start + fn_08012b9c(T+start, F, short Y+0x14, W, 0, byte
@ Y+0x1d); while y + short F+8 < short [word O+8]+2 (line above the clip) the next
@ line is taken the same way and y += step; when Z is nonzero, y >= -1024 and
@ Z.word0 < 0 it records Z.word0 = start, Z.word4 = y - R.y1, Z.word8 = R.y1; ends
@ when text[start] = 0 (loop 0x0801e394..0x0801e3e6, test 0x0801e3e2..0x0801e3e6).
@ Alignment 2 (centre) and 3 (right): width wd = fn_08027dec(T+start, e-start, F,
@ short Y+0x14, byte Y+0x1d), x += (rect_width_0801d05e(R) - wd)/2 for 2 or
@ x += rect_width_0801d05e(R) - wd for 3 (0x0801e40e..0x0801e45e).
@ Selection bounds s0 = word Y+4 and s1 = word Y+8, swapped when s0 > s1. When
@ byte Y+0x1e & 3 is nonzero a line record at sp+0xa8 is made with fn_0801e8d2:
@ halfword +0 = halfword Y+0xc, +2 = signed byte F+0xe (1 when 0), byte +8 = byte
@ Y+0x1a, bits 0..1 of byte +9 = bits 3..4 of byte Y+0x1e. Colours are set to
@ fn_0801d6e0() twice, a 0x38-byte record at sp+0x68 is initialised with
@ fn_0801f344 and its halfword +4 = halfword Y+0x10, x is kept in [sp+0xc8].
@ Per line (0x0801e4cc..0x0801e668): x += short Y+0x16; loops over the line bytes
@ with an offset at [sp+0x1c]; when s0 and s1 are not 0xffff the character index is
@ the result of the function pointer stored in word 0x20000514 (read through the
@ literal at 0x0801e7b0, blx r2 at 0x0801e506) called with (T, start + offset);
@ fn_08012b6c fetches the code (sp+4) and the next code (sp).
@ Inline colour (only when bit 0 of byte Y+0x1d is set), state r7: code 0x23 in
@ state 0 records the offset and enters state 1 (nothing drawn); in state 1 any
@ code other than 0x20 is skipped, and 0x23 returns to state 0 and is drawn as an
@ ordinary character; code 0x20 in state 1 with exactly 7 bytes consumed since the
@ 0x23 reads six hex digits through hex_digit_value (pairs high*16+low), packs
@ them with rgb_to_565_0801d8e2(red, green, blue) and enters state 2, with another
@ count it uses halfword Y+0xc and enters state 2; in state 2 the colour is that
@ value, and 0x23 returns to state 0 (nothing drawn).
@ Glyph: advance = fn_08020a0a(F, code, next code); when index is in [s0, s1) a
@ rectangle (x, y, x + short Y+0x14 + advance - 1, y + step - 1) is filled with
@ fn_0801f31c(O, sp+0x68, rect) and the colour becomes halfword Y+0xe; the working
@ style colour halfword is set and fn_0801e8ae(O, working style, &x, code) draws
@ it; when advance > 0, x += short Y+0x14 + advance.
@ After each line: bit 1 of byte Y+0x1e draws a line from x start ([sp+0xc8]) to x
@ at y = y + short F+8 / 2 + thickness/2 (thickness = halfword at sp+0xaa) and
@ bit 0 draws a line at y + halfword F+8 - halfword F+10 - signed byte F+13, both
@ with fn_0801e8b8(O, record, point, point).
@ Next line: e' = start + fn_08012b9c(...), x = R.x1 with the same alignment, y +=
@ step; the loop ends when y > short [word O+8]+6 or text[start] = 0
@ (0x0801e788..0x0801e7a6).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e274,"ax",%progbits
	.p2align 2
	.global fn_0801e274
	.thumb_func
	.type fn_0801e274, %function
fn_0801e274:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0xd4
	ldrb	r0, [r1, #0x1a]
	ldr	r7, [sp, #0x108]
	mov	r6, r3
	mov	r10, r2
	mov	r4, r1
	cmp	r0, #2
	bls.n	.L0801e384
	ldr	r0, [r4]
	cmp	r0, #0
	beq.n	.L0801e384
	ldr	r0, [sp, #0xd4]
	ldr	r0, [r0, #0x1c]
	cmp	r0, #0
	beq.n	.L0801e384
	movs	r2, #0x20
	add	r0, sp, #0x48
	bl	copy_bytes_080070dc
	ldr	r0, [r4]
	str	r0, [sp, #0xc]
	cmp	r6, #0
	beq.n	.L0801e384
	ldrb	r0, [r6]
	cmp	r0, #0
	beq.n	.L0801e384
	ldr	r0, [sp, #0xd4]
	mov	r1, r10
	ldr	r2, [r0, #0x8]
	add	r0, sp, #0xb8
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L0801e384
	ldrb	r0, [r4, #0x1c]
	subs.w	r11, r0, #0
	bne.n	.L0801e2c8
	mov.w	r11, #1
.L0801e2c8:
	ldrb	r0, [r4, #0x1d]
	lsls	r0, r0, #30
	bmi.n	.L0801e2de
	ldrh.w	r1, [r10, #0x4]
	ldrh.w	r0, [r10]
	subs	r0, r1, r0
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth	r3, r0
	b.n	.L0801e2fe
.L0801e2de:
	ldrsh.w	r0, [r4, #0x12]
	ldrb	r2, [r4, #0x1d]
	movw	r1, #0x1fff
	stm.w	sp, {r0, r1, r2}
	ldrsh.w	r3, [r4, #0x14]
	mov	r1, r6
	add	r0, sp, #0x18
	ldr	r2, [r4]
	bl	fn_08027d30
	ldrsh.w	r3, [sp, #0x18]
.L0801e2fe:
	ldr	r0, [sp, #0xc]
	ldrsh.w	r1, [r4, #0x12]
	movs	r5, #0
	ldrsh.w	r9, [r0, #0x8]
	subs	r2, r5, #1
	add.w	r0, r1, r9
	str	r0, [sp, #0x2c]
	ldrh.w	r0, [r10]
	strh.w	r0, [sp, #0x10]
	ldrh.w	r1, [r10, #0x2]
	strh.w	r1, [sp, #0x12]
	ldrsh.w	r0, [r4, #0x16]
	str	r0, [sp, #0x24]
	ldrsh.w	r0, [r4, #0x18]
	add	r1, r0
	strh.w	r1, [sp, #0x12]
	cbz	r7, .L0801e374
	cbnz	r0, .L0801e374
	ldrsh.w	r1, [r10, #0x2]
	cmp	r1, #0
	bge.n	.L0801e374
	ldr.w	r12, [r7, #0x8]
	sub.w	r0, r12, r1
	cmp	r0, #0
	bgt.n	.L0801e34e
	sub.w	r0, r1, r12
.L0801e34e:
	ldr	r1, [sp, #0x2c]
	mov.w	r12, #0x400
	rsbs	r1, r1, #0
	add.w	r1, r12, r1, lsl #1
	cmp	r0, r1
	ble.n	.L0801e360
	str	r2, [r7]
.L0801e360:
	ldr	r0, [r7]
	cmp	r0, #0
	blt.n	.L0801e374
	mov	r5, r0
	ldrh.w	r1, [sp, #0x12]
	ldrh	r0, [r7, #0x4]
	add	r0, r1
	strh.w	r0, [sp, #0x12]
.L0801e374:
	ldrb	r1, [r4, #0x1d]
	movs	r0, #0
	strd	r0, r1, [sp]
	ldrsh.w	r2, [r4, #0x14]
	adds	r0, r6, r5
	b.n	.L0801e386
.L0801e384:
	b.n	.L0801e4ca
.L0801e386:
	str	r3, [sp, #0xb4]
	ldr	r1, [sp, #0xc]
	bl	fn_08012b9c
	add.w	r8, r0, r5
	b.n	.L0801e3e8
.L0801e394:
	ldrb	r1, [r4, #0x1d]
	movs	r0, #0
	strd	r0, r1, [sp]
	ldrsh.w	r2, [r4, #0x14]
	add.w	r0, r6, r8
	ldr	r3, [sp, #0xb4]
	ldr	r1, [sp, #0xc]
	bl	fn_08012b9c
	mov	r5, r8
	add.w	r8, r0, r5
	ldrh.w	r1, [sp, #0x12]
	ldr	r0, [sp, #0x2c]
	add	r0, r1
	sxth	r0, r0
	strh.w	r0, [sp, #0x12]
	cbz	r7, .L0801e3e2
	cmn.w	r0, #0x400
	blt.n	.L0801e3e2
	ldr	r0, [r7]
	cmp	r0, #0
	bge.n	.L0801e3e2
	str	r5, [r7]
	ldrsh.w	r1, [sp, #0x12]
	ldrsh.w	r0, [r10, #0x2]
	subs	r0, r1, r0
	str	r0, [r7, #0x4]
	ldrsh.w	r0, [r10, #0x2]
	str	r0, [r7, #0x8]
.L0801e3e2:
	ldrb	r0, [r6, r5]
	cmp	r0, #0
	beq.n	.L0801e4ca
.L0801e3e8:
	ldrsh.w	r1, [sp, #0x12]
	add.w	r0, r1, r9
	ldr	r1, [sp, #0xd4]
	ldr	r1, [r1, #0x8]
	ldrsh.w	r1, [r1, #0x2]
	cmp	r0, r1
	blt.n	.L0801e394
	mov	r0, r11
	str.w	r11, [sp, #0xc0]
	cmp.w	r11, #2
	beq.n	.L0801e40e
	cmp	r0, #3
	beq.n	.L0801e43a
	b.n	.L0801e462
	@ alignment 2: centre
.L0801e40e:
	ldrb	r0, [r4, #0x1d]
	str	r0, [sp]
	ldrsh.w	r3, [r4, #0x14]
	sub.w	r1, r8, r5
	adds	r0, r6, r5
	ldr	r2, [sp, #0xc]
	bl	fn_08027dec
	mov	r7, r0
	mov	r0, r10
	bl	rect_width_0801d05e
	subs	r0, r0, r7
	ldrh.w	r1, [sp, #0x10]
	add.w	r0, r0, r0, lsr #31
	add.w	r0, r1, r0, asr #1
	b.n	.L0801e45e
	@ alignment 3: right
.L0801e43a:
	ldrb	r0, [r4, #0x1d]
	str	r0, [sp]
	ldrsh.w	r3, [r4, #0x14]
	sub.w	r1, r8, r5
	adds	r0, r6, r5
	ldr	r2, [sp, #0xc]
	bl	fn_08027dec
	mov	r7, r0
	mov	r0, r10
	bl	rect_width_0801d05e
	ldrh.w	r1, [sp, #0x10]
	subs	r0, r0, r7
	add	r0, r1
.L0801e45e:
	strh.w	r0, [sp, #0x10]
	@ selection bounds
.L0801e462:
	ldrd	r9, r11, [r4, #0x4]
	cmp	r9, r11
	bls.n	.L0801e470
	mov	r0, r9
	mov	r9, r11
	mov	r11, r0
.L0801e470:
	ldrb	r0, [r4, #0x1e]
	lsls	r0, r0, #30
	beq.n	.L0801e4a6
	add	r0, sp, #0xa8
	bl	fn_0801e8d2
	ldrh	r0, [r4, #0xc]
	strh.w	r0, [sp, #0xa8]
	ldr	r0, [sp, #0xc]
	ldrsb.w	r0, [r0, #0xe]
	cbnz	r0, .L0801e48c
	movs	r0, #1
.L0801e48c:
	strh.w	r0, [sp, #0xaa]
	ldrb	r0, [r4, #0x1a]
	strb.w	r0, [sp, #0xb0]
	ldrb	r0, [r4, #0x1e]
	ldrb.w	r1, [sp, #0xb1]
	lsrs	r0, r0, #3
	bfi	r1, r0, #0, #2
	strb.w	r1, [sp, #0xb1]
.L0801e4a6:
	movs	r0, #0
	str	r0, [sp, #0x38]
	bl	fn_0801d6e0
	str	r0, [sp, #0xcc]
	bl	fn_0801d6e0
	str	r0, [sp, #0xc4]
	add	r0, sp, #0x68
	bl	fn_0801f344
	ldrh	r0, [r4, #0x10]
	strh.w	r0, [sp, #0x6c]
	ldrsh.w	r0, [sp, #0x10]
	str	r0, [sp, #0xc8]
	b.n	.L0801e7a2
.L0801e4ca:
	b.n	.L0801e7aa
	@ per line
.L0801e4cc:
	ldrh.w	r1, [sp, #0x10]
	ldr	r0, [sp, #0x24]
	movs	r7, #0
	add	r0, r1
	strh.w	r0, [sp, #0x10]
	adds	r0, r6, r5
	str	r0, [sp, #0x3c]
	str	r7, [sp, #0x1c]
	sub.w	r0, r8, r5
	str	r0, [sp, #0x44]
	b.n	.L0801e662
	@ per character
.L0801e4e8:
	movs	r0, #0
	sub.w	r1, r9, #0xff00
	str	r0, [sp, #0x28]
	subs	r1, #0xff
	beq.n	.L0801e50a
	sub.w	r0, r11, #0xff00
	subs	r0, #0xff
	beq.n	.L0801e50a
	ldr	r2, .L0801e7b0
	ldr	r0, [sp, #0x1c]
	adds	r1, r5, r0
	ldr	r2, [r2]
	mov	r0, r6
	blx	r2
	str	r0, [sp, #0x28]
.L0801e50a:
	add	r3, sp, #0x1c
	mov	r2, sp
	add	r1, sp, #0x4
	ldr	r0, [sp, #0x3c]
	bl	fn_08012b6c
	ldrb	r0, [r4, #0x1d]
	lsls	r0, r0, #31
	beq.n	.L0801e532
	ldr	r0, [sp, #0x4]
	cmp	r0, #0x23
	beq.n	.L0801e528
	cmp	r7, #1
	beq.n	.L0801e54e
	b.n	.L0801e532
.L0801e528:
	cbz	r7, .L0801e53c
	cmp	r7, #1
	beq.n	.L0801e544
	cmp	r7, #2
	beq.n	.L0801e54a
.L0801e532:
	ldr	r0, [r4, #0xc]
	str	r0, [sp, #0xc4]
	cmp	r7, #2
	beq.n	.L0801e5da
	b.n	.L0801e5de
.L0801e53c:
	ldr	r0, [sp, #0x1c]
	str	r0, [sp, #0x38]
	movs	r0, #1
	b.n	.L0801e5d6
.L0801e544:
	movs	r7, #0
	ldr	r0, [r4, #0xc]
	b.n	.L0801e5dc
.L0801e54a:
	movs	r0, #0
	b.n	.L0801e5d6
.L0801e54e:
	cmp	r0, #0x20
	bne.n	.L0801e5d8
	ldr	r1, [sp, #0x1c]
	ldr	r0, [sp, #0x38]
	subs	r0, r1, r0
	cmp	r0, #7
	beq.n	.L0801e560
	ldrh	r0, [r4, #0xc]
	b.n	.L0801e5d2
.L0801e560:
	ldrd	r2, r1, [sp, #0x38]
	add	r2, r1
	add	r0, sp, #0xa0
	movs.w	r1, #6
.L0801e56c:
	ldrb.w	r3, [r2], #1
	strb.w	r3, [r0], #1
	.inst.n 0x1e49			@ subs r1, r1, #1
	bne.n	.L0801e56c
	movs	r0, #0
	strb.w	r0, [sp, #0xa6]
	ldrb.w	r0, [sp, #0xa1]
	bl	hex_digit_value
	mov	r7, r0
	ldrb.w	r0, [sp, #0xa0]
	bl	hex_digit_value
	add.w	r0, r7, r0, lsl #4
	str	r0, [sp, #0x28]
	ldrb.w	r0, [sp, #0xa3]
	bl	hex_digit_value
	mov	r7, r0
	ldrb.w	r0, [sp, #0xa2]
	bl	hex_digit_value
	add.w	r0, r7, r0, lsl #4
	str	r0, [sp, #0x30]
	ldrb.w	r0, [sp, #0xa5]
	bl	hex_digit_value
	mov	r7, r0
	ldrb.w	r0, [sp, #0xa4]
	bl	hex_digit_value
	add.w	r0, r7, r0, lsl #4
	uxtb	r2, r0
	ldr	r0, [sp, #0x30]
	uxtb	r1, r0
	ldr	r0, [sp, #0x28]
	uxtb	r0, r0
	bl	rgb_to_565_0801d8e2
.L0801e5d2:
	str	r0, [sp, #0xcc]
	movs	r0, #2
.L0801e5d6:
	mov	r7, r0
.L0801e5d8:
	b.n	.L0801e662
.L0801e5da:
	ldr	r0, [sp, #0xcc]
.L0801e5dc:
	str	r0, [sp, #0xc4]
	@ draw the glyph
.L0801e5de:
	ldrd	r2, r1, [sp]
	ldr	r0, [sp, #0xc]
	bl	fn_08020a0a
	str	r0, [sp, #0xa4]
	movw	r0, #0xffff
	cmp	r9, r0
	beq.n	.L0801e638
	cmp	r11, r0
	beq.n	.L0801e638
	ldr	r0, [sp, #0x28]
	cmp	r0, r9
	bcc.n	.L0801e638
	cmp	r0, r11
	bcs.n	.L0801e638
	ldrh.w	r0, [sp, #0x10]
	strh.w	r0, [sp, #0x30]
	ldrh.w	r1, [sp, #0x12]
	strh.w	r1, [sp, #0x32]
	ldrh	r2, [r4, #0x14]
	add	r2, r0
	ldr	r0, [sp, #0xa4]
	.inst.n 0x1e40			@ subs r0, r0, #1
	add	r0, r2
	strh.w	r0, [sp, #0x34]
	ldr	r0, [sp, #0x2c]
	add	r2, sp, #0x30
	.inst.n 0x1e40			@ subs r0, r0, #1
	add	r0, r1
	strh.w	r0, [sp, #0x36]
	add	r1, sp, #0x68
	ldr	r0, [sp, #0xd4]
	bl	fn_0801f31c
	ldrh	r0, [r4, #0xe]
	strh.w	r0, [sp, #0xc4]
.L0801e638:
	ldrh.w	r0, [sp, #0xc4]
	strh.w	r0, [sp, #0x54]
	add	r2, sp, #0x10
	add	r1, sp, #0x48
	ldr	r3, [sp, #0x4]
	ldr	r0, [sp, #0xd4]
	bl	fn_0801e8ae
	ldr	r0, [sp, #0xa4]
	cmp	r0, #0
	ble.n	.L0801e662
	ldrh.w	r1, [sp, #0x10]
	ldrh	r0, [r4, #0x14]
	add	r0, r1
	ldr	r1, [sp, #0xa4]
	add	r0, r1
	strh.w	r0, [sp, #0x10]
.L0801e662:
	ldr	r1, [sp, #0x1c]
	ldr	r0, [sp, #0x44]
	cmp	r0, r1
	bhi.w	.L0801e4e8
	@ underline and strike lines after the line
	ldrb	r0, [r4, #0x1e]
	lsls	r0, r0, #30
	bpl.n	.L0801e6ba
	ldr	r0, [sp, #0xc8]
	strh.w	r0, [sp]
	ldr	r0, [r4]
	ldrsh.w	r1, [sp, #0xaa]
	add	r3, sp, #0x8
	ldrsh.w	r0, [r0, #0x8]
	add.w	r1, r1, r1, lsr #31
	add.w	r0, r0, r0, lsr #31
	asrs	r0, r0, #1
	add.w	r0, r0, r1, asr #1
	ldrh.w	r1, [sp, #0x12]
	mov	r2, sp
	add	r0, r1
	ldrh.w	r1, [sp, #0x10]
	strh.w	r1, [sp, #0x8]
	strh.w	r0, [sp, #0x2]
	strh.w	r0, [sp, #0xa]
	ldrh.w	r0, [sp, #0xc4]
	strh.w	r0, [sp, #0xa8]
	add	r1, sp, #0xa8
	ldr	r0, [sp, #0xd4]
	bl	fn_0801e8b8
.L0801e6ba:
	ldrb	r0, [r4, #0x1e]
	lsls	r0, r0, #31
	beq.n	.L0801e700
	ldr	r0, [sp, #0xc8]
	strh.w	r0, [sp]
	ldr	r0, [r4]
	ldrh.w	r1, [sp, #0x12]
	add	r3, sp, #0x8
	ldrh	r2, [r0, #0x8]
	ldrh	r0, [r0, #0xa]
	add	r1, r2
	subs	r1, r1, r0
	ldr	r0, [sp, #0xc]
	mov	r2, sp
	ldrsb.w	r0, [r0, #0xd]
	subs	r0, r1, r0
	ldrh.w	r1, [sp, #0x10]
	strh.w	r1, [sp, #0x8]
	strh.w	r0, [sp, #0x2]
	strh.w	r0, [sp, #0xa]
	ldrh.w	r0, [sp, #0xc4]
	strh.w	r0, [sp, #0xa8]
	add	r1, sp, #0xa8
	ldr	r0, [sp, #0xd4]
	bl	fn_0801e8b8
	@ next line
.L0801e700:
	ldrb	r1, [r4, #0x1d]
	movs	r0, #0
	strd	r0, r1, [sp]
	add.w	r0, r6, r8
	ldrsh.w	r2, [r4, #0x14]
	mov	r7, r0
	ldr	r3, [sp, #0xb4]
	ldr	r1, [sp, #0xc]
	bl	fn_08012b9c
	mov	r5, r8
	add.w	r8, r0, r5
	ldrh.w	r0, [r10]
	strh.w	r0, [sp, #0x10]
	ldr	r0, [sp, #0xc0]
	cmp	r0, #2
	beq.n	.L0801e734
	cmp	r0, #3
	beq.n	.L0801e760
	b.n	.L0801e788
.L0801e734:
	ldrb	r0, [r4, #0x1d]
	str	r0, [sp]
	ldrsh.w	r3, [r4, #0x14]
	sub.w	r1, r8, r5
	mov	r0, r7
	ldr	r2, [sp, #0xc]
	bl	fn_08027dec
	mov	r7, r0
	mov	r0, r10
	bl	rect_width_0801d05e
	subs	r0, r0, r7
	ldrh.w	r1, [sp, #0x10]
	add.w	r0, r0, r0, lsr #31
	add.w	r0, r1, r0, asr #1
	b.n	.L0801e784
.L0801e760:
	ldrb	r0, [r4, #0x1d]
	str	r0, [sp]
	ldrsh.w	r3, [r4, #0x14]
	sub.w	r1, r8, r5
	mov	r0, r7
	ldr	r2, [sp, #0xc]
	bl	fn_08027dec
	mov	r7, r0
	mov	r0, r10
	bl	rect_width_0801d05e
	ldrh.w	r1, [sp, #0x10]
	subs	r0, r0, r7
	add	r0, r1
.L0801e784:
	strh.w	r0, [sp, #0x10]
.L0801e788:
	ldrh.w	r1, [sp, #0x12]
	ldr	r0, [sp, #0x2c]
	add	r0, r1
	ldr	r1, [sp, #0xd4]
	sxth	r0, r0
	strh.w	r0, [sp, #0x12]
	ldr	r1, [r1, #0x8]
	ldrsh.w	r1, [r1, #0x6]
	cmp	r0, r1
	bgt.n	.L0801e7aa
.L0801e7a2:
	ldrb	r0, [r6, r5]
	cmp	r0, #0
	bne.w	.L0801e4cc
.L0801e7aa:
	add	sp, #0xe4
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801e7b0:
	.word	0x20000514		@ address of the stored function pointer used for the character index

@ ----------------------------------------------------------------------------
@ fn_0801e7b4 - initialises a 0x20-byte style record.
@ Parameter: r0 = structure pointer. No return value.
@ Clears 0x20 bytes with clear_bytes(r0, 0x20). Then byte +0x1a = 0xff, halfword
@ +0xc = fn_0801d6e0(), word +0 = the address d_0802ce5c, words +4 and +8 = 0xffff,
@ halfword +0xe = fn_0801d6e0(), halfword +0x10 = fn_08026858(5), byte +0x1b = 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e7b4,"ax",%progbits
	.p2align 2
	.global fn_0801e7b4
	.thumb_func
	.type fn_0801e7b4, %function
fn_0801e7b4:
	push	{r3, r4, r5, lr}
	mov	r4, r0
	movs	r1, #0x20
	bl	clear_bytes
	movs	r0, #0xff
	strb	r0, [r4, #0x1a]
	bl	fn_0801d6e0
	str	r0, [sp]
	ldrh.w	r0, [sp]
	strh	r0, [r4, #0xc]
	ldr	r0, .L0801e7fc
	str	r0, [r4]
	movw	r0, #0xffff
	str	r0, [r4, #0x4]
	str	r0, [r4, #0x8]
	bl	fn_0801d6e0
	str	r0, [sp]
	ldrh.w	r0, [sp]
	strh	r0, [r4, #0xe]
	movs	r0, #5
	bl	fn_08026858
	str	r0, [sp]
	ldrh.w	r0, [sp]
	strh	r0, [r4, #0x10]
	movs	r0, #0
	strb	r0, [r4, #0x1b]
	pop	{r3, r4, r5, pc}
	.short	0x0000			@ padding
.L0801e7fc:
	.word	d_0802ce5c

@ ----------------------------------------------------------------------------
@ call_word_at_0x3c_if_set - tail-jumps to the routine whose address is stored at
@ word +0x3c of an object, when that word is nonzero.
@ Parameter: r0 = pointer P (r1..r3 pass through unchanged for the jump, r3 is
@ overwritten by the word). Loads r3 = word [r0+0x3c]; when it is nonzero executes
@ bx r3 (a tail jump, the routine returns to the caller); when it is 0 returns
@ with bx lr. Entered by the b.w at 0x0801c242 of 0x0801c1e4, which passes
@ r0 = r8, r1 = r4, r2 = r5.
@ ----------------------------------------------------------------------------
	.section .text.call_word_at_0x3c_if_set,"ax",%progbits
	.global call_word_at_0x3c_if_set
	.thumb_func
	.type call_word_at_0x3c_if_set, %function
call_word_at_0x3c_if_set:
	ldr	r3, [r0, #0x3c]
	cmp	r3, #0
	beq.n	.L0801e808
	bx	r3
.L0801e808:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801e80a - tail-jumps to the routine whose address is stored at word +0x40
@ of an object, when that word is nonzero.
@ Parameter: r0 = object pointer. Loads r3 = word [r0+0x40]; when it is nonzero
@ executes bx r3, when it is 0 returns with bx lr.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e80a,"ax",%progbits
	.global fn_0801e80a
	.thumb_func
	.type fn_0801e80a, %function
fn_0801e80a:
	ldr	r3, [r0, #0x40]
	cmp	r3, #0
	beq.n	.L0801e812
	bx	r3
.L0801e812:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801e814 - calls the callback at word +0x38 of an object with a new block.
@ Parameters: r0 = object pointer, r1 = pointer to 2 words, r2 = argument.
@ Returns the callback result, or 0.
@ Returns 0 when word r0+0x38 is 0. Allocates fn_08022b50(word r0+0x48) and returns
@ 0 on failure; clears the block with clear_bytes(block, word r0+0x48). Gets
@ return_word_200004b8() = p, copies words r0+0, r0+4, r0+8 into the block at
@ +0x20, +0x1c, +0x18, stores bit 6 of byte [*p+0x10] to byte +0x24, and words
@ +0 and +4 = r1[0], r1[1]. Calls the function pointer at word r0+0x38 with
@ (r0, block, r2); frees the block with fn_08022c68 when that returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e814,"ax",%progbits
	.global fn_0801e814
	.thumb_func
	.type fn_0801e814, %function
fn_0801e814:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r5, r0
	ldr	r0, [r0, #0x38]
	mov	r7, r2
	mov	r6, r1
	cmp	r0, #0
	beq.n	.L0801e86e
	ldr	r0, [r5, #0x48]
	bl	fn_08022b50
	subs	r4, r0, #0
	beq.n	.L0801e86e
	ldr	r1, [r5, #0x48]
	bl	clear_bytes
	bl	return_word_200004b8
	ldr	r1, [r5]
	str	r1, [r4, #0x20]
	ldr	r1, [r5, #0x4]
	str	r1, [r4, #0x1c]
	ldr	r1, [r5, #0x8]
	str	r1, [r4, #0x18]
	ldr	r0, [r0]
	mov	r2, r7
	mov	r1, r4
	ldrb	r0, [r0, #0x10]
	ubfx	r0, r0, #6, #1
	strb.w	r0, [r4, #0x24]
	ldr	r0, [r6]
	str	r0, [r4]
	ldr	r0, [r6, #0x4]
	str	r0, [r4, #0x4]
	ldr	r3, [r5, #0x38]
	mov	r0, r5
	blx	r3
	movs	r5, r0
	bne.n	.L0801e86c
	mov	r0, r4
	bl	fn_08022c68
.L0801e86c:
	mov	r0, r5
.L0801e86e:
	pop.w	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_0801e872 - restores state from a block and frees it.
@ Parameters: r0 = object pointer, r1 = block pointer. No return value.
@ Calls call_slot_30_if_set(), copies words r1+0x20, r1+0x1c, r1+0x18 to words
@ r0+0, +4, +8. With p = return_word_200004b8(): writes bit 6 of word [*p+0x10]
@ from bit 0 of byte r1+0x24 (bfi). Calls the function pointer at word r0+0x44
@ with (r0, r1) when it is nonzero. Frees r1 with a tail jump to fn_08022c68.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e872,"ax",%progbits
	.global fn_0801e872
	.thumb_func
	.type fn_0801e872, %function
fn_0801e872:
	push	{r4, r5, r6, lr}
	mov	r4, r1
	mov	r5, r0
	bl	call_slot_30_if_set
	ldr	r0, [r4, #0x20]
	str	r0, [r5]
	ldr	r0, [r4, #0x1c]
	str	r0, [r5, #0x4]
	ldr	r0, [r4, #0x18]
	str	r0, [r5, #0x8]
	bl	return_word_200004b8
	ldr	r0, [r0]
	ldrb.w	r2, [r4, #0x24]
	ldr	r1, [r0, #0x10]
	bfi	r1, r2, #6, #1
	str	r1, [r0, #0x10]
	ldr	r2, [r5, #0x44]
	cbz	r2, .L0801e8a4
	mov	r1, r4
	mov	r0, r5
	blx	r2
.L0801e8a4:
	mov	r0, r4
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08022c68

@ ----------------------------------------------------------------------------
@ fn_0801e8ae - tail-jumps through the word at +0x1c of an object.
@ Parameter: r0 = object pointer; r1..r3 pass through unchanged. Loads r12 from
@ [r0+0x1c] (r4 and r5 are saved and restored around the load) and branches to
@ it with bx r12 (0x0801e8b6).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e8ae,"ax",%progbits
	.global fn_0801e8ae
	.thumb_func
	.type fn_0801e8ae, %function
fn_0801e8ae:
	push	{r4, r5}
	ldr	r4, [r0, #0x1c]
	mov	r12, r4
	pop	{r4, r5}
	bx	r12

@ ----------------------------------------------------------------------------
@ fn_0801e8b8 - tail-jumps through the word at +0x20 of an object when a
@ structure is valid.
@ Parameters: r0 = object pointer, r1 = structure pointer (halfword +2, byte +8).
@ Returns at once when halfword r1+2 is 0 or byte r1+8 is 2 or less; otherwise
@ branches through the word at r0+0x20 with bx r12 (0x0801e8cc), with r0..r3
@ passed on unchanged.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e8b8,"ax",%progbits
	.global fn_0801e8b8
	.thumb_func
	.type fn_0801e8b8, %function
fn_0801e8b8:
	push	{r4, r5}
	ldrh	r4, [r1, #0x2]
	cmp	r4, #0
	beq.n	.L0801e8ce
	ldrb	r4, [r1, #0x8]
	cmp	r4, #2
	bls.n	.L0801e8ce
	ldr	r4, [r0, #0x20]
	mov	r12, r4
	pop	{r4, r5}
	bx	r12
.L0801e8ce:
	pop	{r4, r5}
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801e8d2 - initialises a 10-byte line record.
@ Parameter: r0 = structure pointer. No return value.
@ Clears 10 bytes with clear_bytes(r0, 10). Then halfword +2 = 1, byte +8 = 0xff,
@ and halfword +0 = the 565 value 0 built in the stack slot [sp] with three bfi
@ inserts of the value 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e8d2,"ax",%progbits
	.global fn_0801e8d2
	.thumb_func
	.type fn_0801e8d2, %function
fn_0801e8d2:
	push	{r3, r4, r5, lr}
	mov	r4, r0
	movs	r1, #0xa
	bl	clear_bytes
	movs	r0, #1
	strh	r0, [r4, #0x2]
	movs	r0, #0xff
	strb	r0, [r4, #0x8]
	ldrh.w	r1, [sp]
	movs	r0, #0
	bfi	r1, r0, #0, #5
	uxth	r1, r1
	bfi	r1, r0, #5, #6
	uxth	r1, r1
	bfi	r1, r0, #11, #5
	strh.w	r1, [sp]
	uxth	r0, r1
	str	r0, [sp]
	ldrh.w	r0, [sp]
	str	r0, [sp]
	ldrh.w	r0, [sp]
	strh	r0, [r4]
	pop	{r3, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ table_slot_insert - stores a pair of words in the first free slot of a table.
@ Parameters: r0 = first word, r1 = second word. Returns the slot index 0 to 15,
@ or 0xffffffff when all 16 slots are used.
@ Scans the 16 pairs at 0x200081cc (first word) and 0x200081d0 (second word) for
@ the first pair whose first word is 0, stores r0 and r1 there and returns the
@ index.
@ ----------------------------------------------------------------------------
	.section .text.table_slot_insert,"ax",%progbits
	.p2align 2
	.global table_slot_insert
	.thumb_func
	.type table_slot_insert, %function
table_slot_insert:
	push	{r4, lr}
	mov	r3, r0
	ldr	r2, .L0801e940
	movs	r0, #0
.L0801e918:
	ldr.w	r4, [r2, r0, lsl #3]
	cbz	r4, .L0801e928
	.inst.n 0x1c40			@ adds r0, r0, #1
	uxtb	r0, r0
	cmp	r0, #0x10
	bcc.n	.L0801e918
	b.n	.L0801e92c
.L0801e928:
	cmp	r0, #0x10
	bcc.n	.L0801e932
.L0801e92c:
	mov.w	r0, #0xffffffff
	pop	{r4, pc}
.L0801e932:
	str.w	r3, [r2, r0, lsl #3]
	add.w	r2, r2, r0, lsl #3
	str	r1, [r2, #0x4]
	pop	{r4, pc}
	.short	0x0000			@ padding
.L0801e940:
	.word	0x200081cc		@ base of the 16 pairs of words

@ ----------------------------------------------------------------------------
@ fn_0801e944 - classifies one scan line of an arc record against two edges.
@ Parameters: r0 = byte buffer (saved at [sp+4]), r1 = start x (fp), r2 = line y
@ (r6), r3 = length (r4); stack [sp+0x38] = pointer r5 to an arc record. Returns
@ r0 = 0, 1 or 2.
@ Body: one range 0x0801e944..0x0801eba7. No bl or b instruction targets it; its
@ address 0x0801e945 (Thumb bit set) is the literal word at 0x0801ec50, loaded by
@ the ldr at 0x0801ebf8 and stored into word [r5 + 0] of a record, so it is
@ reached through that stored pointer.
@ Record fields read: halfwords +8 = cx, +10 = cy, +12 = a0, +14 = a1 (ldrsh),
@ words +0x28 (u) and +0x54 (v), edge A = r5+0x10 (r9), edge B = r5+0x3c (sl);
@ dx = x - cx (r3), dy = line - cy (r7). E(edge) denotes
@ fn_0801ed24(buffer, x, line, length, edge), which returns 0, 1 or 2.
@ Span case A (0x0801e96c..0x0801e988): a0 < 180, a1 < 180, a0 != 0, a1 != 0 and
@ a0 > a1 (signed); returns 1 when cy > line, else computes below with edge A for
@ the first part and edge B for the second.
@ Span case B (0x0801ea2c..0x0801ea42): a0 > 180, a1 > 180 and a0 > a1; returns 1
@ when cy < line, else computes below with edge B first and edge A second.
@ Computation: p = (v*dy) asr 10, e = (u*(dy+1)) asr 10; e is set to 0 when a0 is
@ in 271..359 and e < 0, or a0 is in 1..90 and e < 0, or a0 is in 91..269 and
@ e > 0 (unsigned range tests on a0-271, a0-1, a0-91), then the same test with
@ a1; mid = e + ((p - e) asr 1); n = mid - dx, limited to the length (signed).
@ First part: res1 = 1; when n > 0, res1 = E(first edge) over n bytes
@ (r3 = sxth(n)), and when res1 = 0 calls clear_bytes(buffer, n); then n is
@ limited to the length and to 0 from below.
@ Second part: E(second edge) at buffer+n, x+n over length-n bytes; when it
@ returns 0 calls clear_bytes(buffer+n, length-n).
@ Returns res1 when res1 equals the second result, else 2.
@ Every other angle combination (0x0801eb00): r7 = r8 = 1; by a0: a0 = 180 gives
@ r7 = 1 when cy > line else 3; a0 = 0 gives 3 when cy > line else 1; 0 < a0 < 180
@ (and negative a0) gives 3 when cy > line else E(edge A) over the full length;
@ a0 > 180 gives E(edge A) when cy > line else 3; by a1: a1 = 180 gives r8 = 3
@ when cy > line else 1; a1 = 0 gives 3 when cy <= line else 1; a1 < 180 (not 0)
@ gives 3 when cy > line else E(edge B); a1 > 180 gives 3 when cy <= line else
@ E(edge B). Result of that case: 0 when r7 = 0 or r8 = 0; r7 = 3 gives 0 when
@ r8 = 3 else 2; r7 = 1 gives 1 when r8 = 1 else 2; any other r7 gives 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801e944,"ax",%progbits
	.p2align 2
	.global fn_0801e944
	.thumb_func
	.type fn_0801e944, %function
fn_0801e944:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x4
	mov	r11, r1
	ldr	r5, [sp, #0x38]
	mov	r6, r2
	mov	r4, r3
	ldrsh.w	r1, [r5, #0xa]
	ldrsh.w	r0, [r5, #0xc]
	subs	r7, r2, r1
	ldrsh.w	r2, [r5, #0x8]
	add.w	r9, r5, #0x10
	sub.w	r3, r11, r2
	add.w	r10, r5, #0x3c
	cmp	r0, #0xb4
	bge.n	.L0801ea2c
	ldrsh.w	r2, [r5, #0xe]
	cmp	r2, #0xb4
	bge.n	.L0801ea74
	cmp	r0, #0
	beq.n	.L0801ea74
	cmp	r2, #0
	beq.n	.L0801ea74
	cmp	r0, r2
	ble.n	.L0801ea74
	cmp	r1, r6
	bgt.n	.L0801ea3e
	@ span case A: first part with edge A
	ldr	r1, [r5, #0x54]
	muls	r1, r7, r1
	asr.w	r12, r1, #10
	ldr	r1, [r5, #0x28]
	.inst.n 0x1c7f			@ adds r7, r7, #1
	muls	r1, r7, r1
	asrs	r1, r1, #10
	subw	r5, r0, #0x10f
	cmp	r5, #0x58
	bhi.n	.L0801e9a4
	cmp	r1, #0
	blt.n	.L0801e9b8
.L0801e9a4:
	subs	r5, r0, #1
	cmp	r5, #0x59
	bhi.n	.L0801e9ae
	cmp	r1, #0
	blt.n	.L0801e9b8
.L0801e9ae:
	subs	r0, #0x5b
	cmp	r0, #0xb3
	bcs.n	.L0801e9ba
	cmp	r1, #0
	ble.n	.L0801e9ba
.L0801e9b8:
	movs	r1, #0
.L0801e9ba:
	subw	r0, r2, #0x10f
	cmp	r0, #0x58
	bhi.n	.L0801e9c6
	cmp	r1, #0
	blt.n	.L0801e9da
.L0801e9c6:
	subs	r0, r2, #1
	cmp	r0, #0x59
	bhi.n	.L0801e9d0
	cmp	r1, #0
	blt.n	.L0801e9da
.L0801e9d0:
	subs	r2, #0x5b
	cmp	r2, #0xb3
	bcs.n	.L0801e9dc
	cmp	r1, #0
	ble.n	.L0801e9dc
.L0801e9da:
	movs	r1, #0
.L0801e9dc:
	sub.w	r0, r12, r1
	add.w	r0, r1, r0, asr #1
	movs	r5, #1
	subs	r7, r0, r3
	cmp	r7, r4
	ble.n	.L0801e9ee
	mov	r7, r4
.L0801e9ee:
	cmp	r7, #0
	ble.n	.L0801ea0e
	sxth	r3, r7
	mov	r2, r6
	mov	r1, r11
	str.w	r9, [sp]
	ldr	r0, [sp, #0x4]
	bl	fn_0801ed24
	movs	r5, r0
	bne.n	.L0801ea0e
	mov	r1, r7
	ldr	r0, [sp, #0x4]
	bl	clear_bytes
.L0801ea0e:
	cmp	r7, r4
	ble.n	.L0801ea14
	mov	r7, r4
.L0801ea14:
	cmp	r7, #0
	bge.n	.L0801ea1a
	movs	r7, #0
.L0801ea1a:
	str.w	r10, [sp]
	b.n	.L0801eadc
	@ common exit: res1 = r5, second result = r6
.L0801ea20:
	cmp	r5, r6
	bne.n	.L0801eb12
	mov	r0, r5
.L0801ea26:
	add	sp, #0x14
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	@ span case B
.L0801ea2c:
	ble.n	.L0801eb00
	ldrsh.w	r2, [r5, #0xe]
	cmp	r2, #0xb4
	ble.n	.L0801eb00
	cmp	r0, r2
	ble.n	.L0801eb00
	cmp	r1, r6
	bge.n	.L0801ea42
.L0801ea3e:
	movs	r0, #1
	b.n	.L0801ea26
.L0801ea42:
	ldr	r1, [r5, #0x54]
	muls	r1, r7, r1
	asr.w	r12, r1, #10
	ldr	r1, [r5, #0x28]
	.inst.n 0x1c7f			@ adds r7, r7, #1
	muls	r1, r7, r1
	asrs	r1, r1, #10
	subw	r5, r0, #0x10f
	cmp	r5, #0x58
	bhi.n	.L0801ea5e
	cmp	r1, #0
	blt.n	.L0801ea72
.L0801ea5e:
	subs	r5, r0, #1
	cmp	r5, #0x59
	bhi.n	.L0801ea68
	cmp	r1, #0
	blt.n	.L0801ea72
.L0801ea68:
	subs	r0, #0x5b
	cmp	r0, #0xb3
	bcs.n	.L0801ea78
	cmp	r1, #0
	ble.n	.L0801ea78
.L0801ea72:
	b.n	.L0801ea76
.L0801ea74:
	b.n	.L0801eb00
.L0801ea76:
	movs	r1, #0
.L0801ea78:
	subw	r0, r2, #0x10f
	cmp	r0, #0x58
	bhi.n	.L0801ea84
	cmp	r1, #0
	blt.n	.L0801ea98
.L0801ea84:
	subs	r0, r2, #1
	cmp	r0, #0x59
	bhi.n	.L0801ea8e
	cmp	r1, #0
	blt.n	.L0801ea98
.L0801ea8e:
	subs	r2, #0x5b
	cmp	r2, #0xb3
	bcs.n	.L0801ea9a
	cmp	r1, #0
	ble.n	.L0801ea9a
.L0801ea98:
	movs	r1, #0
.L0801ea9a:
	sub.w	r0, r12, r1
	add.w	r0, r1, r0, asr #1
	movs	r5, #1
	subs	r7, r0, r3
	cmp	r7, r4
	ble.n	.L0801eaac
	mov	r7, r4
.L0801eaac:
	cmp	r7, #0
	ble.n	.L0801eacc
	sxth	r3, r7
	mov	r2, r6
	mov	r1, r11
	str.w	r10, [sp]
	ldr	r0, [sp, #0x4]
	bl	fn_0801ed24
	movs	r5, r0
	bne.n	.L0801eacc
	mov	r1, r7
	ldr	r0, [sp, #0x4]
	bl	clear_bytes
.L0801eacc:
	cmp	r7, r4
	ble.n	.L0801ead2
	mov	r7, r4
.L0801ead2:
	cmp	r7, #0
	bge.n	.L0801ead8
	movs	r7, #0
.L0801ead8:
	str.w	r9, [sp]
	@ second part
.L0801eadc:
	add.w	r0, r11, r7
	sxth	r1, r0
	ldr	r0, [sp, #0x4]
	subs	r4, r4, r7
	add	r0, r7
	sxth	r3, r4
	mov	r7, r0
	mov	r2, r6
	bl	fn_0801ed24
	movs	r6, r0
	bne.n	.L0801ea20
	mov	r1, r4
	mov	r0, r7
	bl	clear_bytes
	b.n	.L0801ea20
	@ every other angle combination
.L0801eb00:
	movs	r7, #1
	mov	r8, r7
	cmp	r0, #0xb4
	beq.n	.L0801eb14
	cbz	r0, .L0801eb1a
	bge.n	.L0801eb20
	cmp	r1, r6
	bgt.n	.L0801eb24
	b.n	.L0801eb28
.L0801eb12:
	b.n	.L0801eba4
.L0801eb14:
	cmp	r1, r6
	bgt.n	.L0801eb3a
	b.n	.L0801eb24
.L0801eb1a:
	cmp	r1, r6
	bgt.n	.L0801eb24
	b.n	.L0801eb3a
.L0801eb20:
	cmp	r1, r6
	bgt.n	.L0801eb28
.L0801eb24:
	movs	r7, #3
	b.n	.L0801eb3a
.L0801eb28:
	mov	r3, r4
	mov	r2, r6
	mov	r1, r11
	str.w	r9, [sp]
	ldr	r0, [sp, #0x4]
	bl	fn_0801ed24
	mov	r7, r0
.L0801eb3a:
	ldrsh.w	r0, [r5, #0xe]
	cmp	r0, #0xb4
	beq.n	.L0801eb50
	cbz	r0, .L0801eb5e
	ldrsh.w	r0, [r5, #0xa]
	bge.n	.L0801eb6a
	cmp	r0, r6
	bgt.n	.L0801eb58
	b.n	.L0801eb6e
.L0801eb50:
	ldrsh.w	r0, [r5, #0xa]
	cmp	r0, r6
	ble.n	.L0801eb66
.L0801eb58:
	mov.w	r8, #3
	b.n	.L0801eb66
.L0801eb5e:
	ldrsh.w	r0, [r5, #0xa]
	cmp	r0, r6
	ble.n	.L0801eb58
.L0801eb66:
	cbz	r7, .L0801eb98
	b.n	.L0801eb88
.L0801eb6a:
	cmp	r0, r6
	ble.n	.L0801eb58
.L0801eb6e:
	mov	r3, r4
	mov	r2, r6
	mov	r1, r11
	str.w	r10, [sp]
	ldr	r0, [sp, #0x4]
	bl	fn_0801ed24
	mov	r8, r0
	cbz	r7, .L0801eb98
	cmp.w	r8, #0
	beq.n	.L0801eb98
.L0801eb88:
	cmp	r7, #3
	beq.n	.L0801eb92
	cmp	r7, #1
	beq.n	.L0801eb9c
	b.n	.L0801eba4
.L0801eb92:
	cmp.w	r8, #3
	bne.n	.L0801eba4
.L0801eb98:
	movs	r0, #0
.L0801eb9a:
	b.n	.L0801ea26
.L0801eb9c:
	mov	r0, r8
	cmp.w	r8, #1
	beq.n	.L0801eb9a
.L0801eba4:
	movs	r0, #2
	b.n	.L0801ea26

