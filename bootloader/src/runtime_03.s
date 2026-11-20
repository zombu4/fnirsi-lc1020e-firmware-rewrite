@ runtime_03.s - 32-bit unsigned divide, double-precision floating-point and 64-bit shift helpers, formatting wrappers
@ Part of the FNIRSI LC1020E firmware rewrite: port of the stock bootloader (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ udiv32 - unsigned 32-bit division by shift and subtract.
@ In:  r0 = dividend, r1 = divisor.   Out: r0 = quotient.
@ Works from bit 31 down to bit 0: if (dividend >> n) >= divisor, subtract
@ (divisor << n) from the dividend and add (1 << n) to the quotient.
@ The remainder is not returned and a zero divisor is not tested.
@ Uses r1..r5 (r4 and r5 are saved). The entry jumps to the counter test.
@ ----------------------------------------------------------------------------
	.section .text.udiv32,"ax",%progbits
	.p2align 2
	.global udiv32
	.thumb_func
	.type udiv32, %function
udiv32:
	push	{r4, r5, lr}
	mov	r3, r1			@ r3 = divisor
	mov	r1, r0			@ r1 = running dividend
	movs	r0, #0			@ quotient = 0
	movs	r2, #0x20		@ bit counter = 32
	movs	r4, #1			@ constant 1 for building (1 << n)
	b.n	.L080001fe
.L080001ea:
	lsr.w	r5, r1, r2		@ r5 = dividend >> n
	cmp	r5, r3
	bcc.n	.L080001fe		@ below the divisor: this bit is 0
	lsl.w	r5, r3, r2		@ r5 = divisor << n
	subs	r1, r1, r5		@ dividend -= divisor << n
	lsl.w	r5, r4, r2		@ r5 = 1 << n
	add	r0, r5			@ quotient += 1 << n
.L080001fe:
	subs	r5, r2, #0		@ sets flags from the counter
	sub.w	r2, r2, #1		@ n = counter - 1
	bgt.n	.L080001ea		@ continue while the old counter > 0
	pop	{r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_08000208 - unsigned 64-bit division by shift and subtract.
@ In:  r1:r0 = dividend (r1 high), r3:r2 = divisor (r3 high).
@ Out: r1:r0 = quotient, r3:r2 = remainder (what is left of the dividend).
@ For n = 63 down to 0: if (dividend >> n) >= divisor (compared as 64 bits,
@ using fn_0800061e), subtract (divisor << n) (fn_08000600) from the dividend
@ and add (1 << n) to the quotient. A zero divisor is not tested.
@ Callee-saved registers r4..r12 are pushed and restored.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000208,"ax",%progbits
	.global fn_08000208
	.thumb_func
	.type fn_08000208, %function
fn_08000208:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	mov	r5, r0			@ r5 = dividend low
	movs	r0, #0
	mov	r10, r2			@ r10 = divisor low
	mov	r11, r3			@ r11 = divisor high
	mov	r8, r1			@ r8 = dividend high
	mov	r6, r0			@ r6 = quotient high = 0
	mov	r9, r0			@ r9 = quotient low = 0
	movs	r4, #0x40		@ bit counter = 64
	b.n	.L08000256
.L0800021e:
	mov	r0, r5
	mov	r1, r8
	mov	r7, r8			@ r7 = dividend high (kept across the call)
	mov	r2, r4
	bl	fn_0800061e		@ r1:r0 = dividend >> n
	mov	r3, r10
	mov	r2, r11
	subs	r0, r0, r3		@ 64-bit compare: (dividend >> n) - divisor
	sbcs	r1, r2
	bcc.n	.L08000256		@ below the divisor: this bit is 0
	mov	r1, r2
	mov	r0, r3
	mov	r2, r4
	bl	fn_08000600		@ r1:r0 = divisor << n
	subs	r5, r5, r0		@ dividend -= divisor << n
	sbc.w	r8, r7, r1
	mov	r7, r9
	mov	r2, r4
	movs	r0, #1
	movs	r1, #0
	bl	fn_08000600		@ r1:r0 = 1 << n
	adds.w	r9, r7, r0		@ quotient += 1 << n
	adcs	r6, r1
.L08000256:
	subs	r0, r4, #0		@ sets flags from the counter
	sub.w	r4, r4, #1		@ n = counter - 1
	bgt.n	.L0800021e		@ continue while the old counter > 0
	mov	r0, r9			@ quotient low
	mov	r1, r6			@ quotient high
	mov	r2, r5			@ remainder low
	mov	r3, r8			@ remainder high
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}

@ ----------------------------------------------------------------------------
@ fn_0800026a - double-precision addition (IEEE 754 binary64), a + b.
@ In:  r1:r0 = a (r1 high word), r3:r2 = b (r3 high word).
@ Out: r1:r0 = a + b.
@ Takes the sign difference of the operands, orders them by magnitude so the
@ larger one is in r4:r8, and aligns the smaller mantissa (with the implicit
@ 0x100000 bit) by the exponent difference using fn_08000600 / fn_0800063e.
@ A difference of 64 or more returns the larger operand (adjusted by the sign
@ difference). The mantissas are added or subtracted (negated for unlike
@ signs); a carry or borrow out of the mantissa renormalises it, and the
@ result is rounded and packed by fn_08000662, or by fn_08000680 for a
@ near-cancelling subtraction. Two zero-magnitude operands return a unchanged.
@ Stack frame: 12 bytes locals at sp+0 (sign difference), sp+4 (exponent
@ difference), sp+8 (exponent of the larger operand).
@ fn_080003ac and fn_080003b2 follow and branch here.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800026a,"ax",%progbits
	.global fn_0800026a
	.thumb_func
	.type fn_0800026a, %function
fn_0800026a:
	push.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r8, r0			@ r8 = a low
	eor.w	r0, r1, r3
	lsrs	r0, r0, #0x1f		@ r0 = 1 if the signs differ
	mov	r4, r1			@ r4 = a high
	str	r0, [sp]		@ sp+0 = sign difference
	bic	r1, r1, #0x80000000	@ |a| high
	bic	r5, r3, #0x80000000	@ |b| high
	subs.w	r0, r8, r2		@ compare |a| with |b| (64 bits)
	sbcs	r1, r5
	bcs.n	.L08000296		@ |a| >= |b|: operands already ordered
	mov	r0, r8			@ otherwise swap a and b
	mov	r1, r4
	mov	r8, r2
	mov	r4, r3
	mov	r3, r1
	mov	r2, r0
.L08000296:
	bic	r0, r3, #0x80000000
	orrs	r0, r2
	beq.n	.L0800032e		@ smaller operand is zero: return the larger
	lsrs	r7, r4, #0x14		@ r7 = sign and exponent of the larger
	ubfx	r0, r7, #0, #0xb	@ r0 = exponent of the larger
	ubfx	r1, r3, #0x14, #0xb	@ r1 = exponent of the smaller
	str	r0, [sp, #8]
	subs	r0, r0, r1		@ exponent difference
	str	r0, [sp, #4]
	cmp	r0, #0x40
	bge.n	.L0800038a		@ 64 or more: smaller operand is negligible
	ubfx	r0, r3, #0, #0x14
	orr	r11, r0, #0x100000	@ r11 = smaller mantissa high with implicit bit
	ldr	r0, [sp]
	mov	r10, r2			@ r10 = smaller mantissa low
	cbz	r0, .L080002ca		@ like signs: keep the mantissa
	movs	r3, #0
	rsbs.w	r10, r2, r3		@ unlike signs: negate the 64-bit mantissa
	sbc.w	r11, r3, r11
.L080002ca:
	ldr	r0, [sp, #4]
	mov	r1, r11
	rsb.w	r2, r0, #0x40
	mov	r0, r10
	bl	fn_08000600		@ mantissa << (64 - difference): bits shifted out
	mov	r6, r0			@ r6 = shifted-out bits low
	mov	r5, r1			@ r5 = shifted-out bits high
	mov	r0, r10
	mov	r1, r11
	ldr	r2, [sp, #4]
	bl	fn_0800063e		@ mantissa >> difference (arithmetic)
	adds.w	r0, r0, r8		@ add the larger mantissa
	adcs	r1, r4
	movs	r4, #0
	eor.w	r2, r7, r1, lsr #0x14	@ did the exponent field change
	eor.w	r3, r4, r7, asr #0x1f
	orrs	r2, r3
	beq.n	.L0800037c		@ no: result is ready for packing
	ldr	r2, [sp]
	cbz	r2, .L08000358		@ like signs: carry out, shift right by one
	ldr	r2, [sp, #4]
	cmp	r2, #1
	lsl.w	r2, r7, #0x14
	bgt.n	.L08000334		@ difference above 1: normalise left by one
	subs	r0, r0, r4
	sbc.w	r1, r1, r2
	mov.w	r2, #0x80000000
	and.w	r2, r2, r7, lsl #0x14	@ sign of the larger operand
	strd	r4, r2, [sp]
	.inst.n 0x1c00			@ adds r0, r0, #0
	adc	r1, r1, #0x100000
	mov	r2, r6
	mov	r3, r5
	bl	fn_08000680		@ normalise, round and pack
.L08000328:
	add	sp, #0xc
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0800032e:
	mov	r0, r8			@ return the larger operand unchanged
	mov	r1, r4
	b.n	.L08000328
.L08000334:
	subs	r0, r0, r4
	sbc.w	r1, r1, r2
	.inst.n 0x1c00			@ adds r0, r0, #0
	adc	r3, r1, #0x100000
	adds	r0, r0, r0		@ shift the mantissa left by one
	adcs	r3, r3
	adds	r0, r4, r0
	sub.w	r7, r2, #0x200000
	adc.w	r1, r7, r3
	orr.w	r0, r0, r5, lsr #0x1f
	adds	r6, r6, r6
	adcs	r5, r5
	b.n	.L0800037c
.L08000358:
	lsrs	r5, r5, #1		@ like signs: shift mantissa right by one
	rrx	r6, r6
	orr.w	r5, r5, r0, lsl #0x1f
	lsl.w	r2, r7, #0x14
	subs	r0, r0, r4
	sbc.w	r1, r1, r2
	.inst.n 0x1c00			@ adds r0, r0, #0
	adc	r1, r1, #0x100000
	lsrs	r1, r1, #1
	rrx	r0, r0
	adds	r0, r0, r4
	adcs	r1, r2
.L0800037c:
	mov	r2, r6
	mov	r3, r5
.L08000380:
	add	sp, #0xc
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w	fn_08000662		@ round and pack, returns to the caller
.L0800038a:
	ldr	r0, [sp]		@ negligible operand: result is the larger
	movs	r2, #1			@ adjusted by the sign difference
	lsls	r0, r0, #1
	movs	r3, #0
	rsbs	r2, r0, r2
	sbc.w	r3, r3, r0, asr #0x1f
	ldr	r0, [sp]
	mov	r1, r4
	asr.w	r4, r0, #0x1f
	subs.w	r0, r8, r0
	sbc.w	r1, r1, r4
	b.n	.L08000380

@ ----------------------------------------------------------------------------
@ fn_080003ac - double-precision subtraction, a - b (no caller in the image).
@ In:  r1:r0 = a, r3:r2 = b.   Out: r1:r0 = a - b.
@ Flips the sign bit of b (r3 ^= 0x80000000), then continues in fn_0800026a.
@ ----------------------------------------------------------------------------
	.global fn_080003ac
	.thumb_func
	.type fn_080003ac, %function
fn_080003ac:
	eor	r3, r3, #0x80000000
	b.n	fn_0800026a

@ ----------------------------------------------------------------------------
@ fn_080003b2 - double-precision reverse subtraction, b - a (no caller in the
@ image).
@ In:  r1:r0 = a, r3:r2 = b.   Out: r1:r0 = b - a.
@ Flips the sign bit of a (r1 ^= 0x80000000), then continues in fn_0800026a.
@ ----------------------------------------------------------------------------
	.global fn_080003b2
	.thumb_func
	.type fn_080003b2, %function
fn_080003b2:
	eor	r1, r1, #0x80000000
	b.n	fn_0800026a

@ ----------------------------------------------------------------------------
@ fn_080003b8 - double-precision multiplication (IEEE 754 binary64), a * b.
@ In:  r1:r0 = a (r1 high word), r3:r2 = b (r3 high word).
@ Out: r1:r0 = a * b.
@ If either operand has a zero magnitude the result is 0. Otherwise the sign
@ is a.high ^ b.high (bit 31), the exponent fields are added and 0x3f3 is
@ subtracted, the 53-bit mantissas (with the implicit 0x100000 bit) are
@ multiplied in partial products with umull / mla / umlal, and the product is
@ normalised, rounded and packed by fn_08000680, which receives the product
@ in r1:r0 and r3:r2 and, on the stack, 0 (sp+0), the sign (sp+4) and the
@ exponent minus 12 (sp+8); its result is returned unchanged.
@ Stack frame: 12 bytes locals at sp+0, sp+4, sp+8 (then the 8 saved
@ registers).
@ ----------------------------------------------------------------------------
	.section .text.fn_080003b8,"ax",%progbits
	.p2align 2
	.global fn_080003b8
	.thumb_func
	.type fn_080003b8, %function
fn_080003b8:
	push.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	eor.w	r4, r1, r3
	and	r4, r4, #0x80000000	@ result sign
	bic	r1, r1, #0x80000000	@ |a| high
	str	r4, [sp]
	mov.w	r11, #0
	bic	r3, r3, #0x80000000	@ |b| high
	orrs.w	r4, r0, r1
	beq.n	.L08000496		@ a is zero
	orrs.w	r4, r2, r3
	beq.n	.L08000496		@ b is zero
	ubfx	r4, r3, #0x14, #0xb	@ exponent of b
	ubfx	r5, r1, #0x14, #0xb	@ exponent of a
	add	r4, r5
	subw	r4, r4, #0x3f3
	str	r4, [sp, #4]		@ sp+4 = summed exponent
	umull	r5, r4, r0, r2		@ low x low
	ubfx	r1, r1, #0, #0x14
	orr	r1, r1, #0x100000	@ mantissa of a with implicit bit
	ubfx	r3, r3, #0, #0x14
	orr	r3, r3, #0x100000	@ mantissa of b with implicit bit
	mla	r4, r1, r2, r4
	mla	lr, r0, r3, r4
	lsrs	r4, r0, #0xa
	lsrs	r7, r2, #0xa
	orr.w	r4, r4, r1, lsl #0x16
	orr.w	r7, r7, r3, lsl #0x16
	umull	r6, r8, r4, r7
	str	r5, [sp, #8]
	lsrs	r5, r1, #0xa
	mla	r5, r5, r7, r8
	lsr.w	r12, r3, #0xa
	mla	r4, r4, r12, r5
	lsls	r7, r4, #0x14
	ldr	r5, [sp, #8]
	lsl.w	r8, r6, #0x14
	orr.w	r7, r7, r6, lsr #0xc
	subs.w	r5, r5, r8
	sbc.w	r12, lr, r7
	lsrs	r7, r0, #0x1a
	lsrs	r2, r2, #0x1a
	orr.w	r7, r7, r1, lsl #0x6
	orr.w	r2, r2, r3, lsl #0x6
	umull	r0, r1, r7, r2
	subs.w	r1, r6, r11
	sbc.w	r4, r4, r0
	lsrs	r3, r5, #0x14
	orr.w	r3, r3, r12, lsl #0xc
	adds	r6, r3, r1
	adc.w	r0, r4, r12, lsr #0x14
	mov	r10, r11
	mov	r1, r10
	umlal	r0, r1, r7, r2
	ubfx	r4, r5, #0, #0x14
	lsl.w	r3, r11, #0xc
	orr.w	r3, r3, r4, lsr #0x14
	lsl.w	r2, r4, #0xc
	ldr	r4, [sp, #4]
	orr.w	r3, r3, r6
	sub.w	r4, r4, #0xc
	str	r4, [sp, #8]
	ldr	r4, [sp]
	strd	r11, r4, [sp]		@ sp+0 = 0, sp+4 = sign
	bl	fn_08000680		@ normalise, round and pack
.L08000490:
	add	sp, #0xc
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08000496:
	movs	r0, #0			@ a zero operand: result is 0
	mov	r1, r0
	b.n	.L08000490

@ ----------------------------------------------------------------------------
@ fn_0800049c - double-precision division (IEEE 754 binary64), a / b.
@ In:  r1:r0 = a (r1 high word), r3:r2 = b (r3 high word).
@ Out: r1:r0 = a / b (0 when a or b has zero magnitude, or the exponent
@ underflows).
@ Sign = a.high ^ b.high (bit 31); exponent = exponent(a) - exponent(b) +
@ 0x3fd, plus 1 when mantissa(a) >= mantissa(b) (otherwise a's mantissa is
@ doubled). The quotient mantissa is built bit by bit (53 bits, in r6 low /
@ r12 high) by compare-and-subtract with the 64-bit remainder doubling each
@ step. The remainder is then classified (zero, exactly half, below half,
@ above half) into the rounding word r3:r2 = 0:0, 0x80000000:0,
@ 0xffffffff:0xfffffffe or 0:1, and fn_08000662 rounds and packs the result
@ (tail call, it returns to the caller).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800049c,"ax",%progbits
	.global fn_0800049c
	.thumb_func
	.type fn_0800049c, %function
fn_0800049c:
	push.w	{r4, r5, r6, r7, r8, r10, r11, lr}
	eor.w	r4, r1, r3
	and	r11, r4, #0x80000000	@ r11 = result sign
	bic	r5, r1, #0x80000000	@ |a| high
	mov	r4, r2			@ r4 = b low
	mov.w	r10, #0
	bic	r1, r3, #0x80000000	@ |b| high
	orrs.w	r2, r0, r5
	beq.n	.L080004fe		@ a is zero
	orrs.w	r2, r4, r1
	beq.n	.L080004fe		@ b is zero
	ubfx	r7, r5, #0x14, #0xb	@ exponent of a
	mov	r2, r0			@ r3:r2 = a mantissa (low : high below)
	ubfx	r3, r5, #0, #0x14
	ubfx	r0, r1, #0, #0x14
	ubfx	r6, r1, #0x14, #0xb	@ exponent of b
	orr	r5, r0, #0x100000	@ r5:r4 = b mantissa with implicit bit
	orr	r3, r3, #0x100000	@ r3:r2 = a mantissa with implicit bit
	sub.w	r8, r7, r6		@ exponent difference
	subs	r0, r2, r4		@ compare mantissa(a) with mantissa(b)
	mov	lr, r10
	addw	r8, r8, #0x3fd
	sbcs.w	r0, r3, r5
	bcc.n	.L080004f4
	add.w	r8, r8, #1		@ a >= b: exponent + 1
	b.n	.L080004f8
.L080004f4:
	adds	r2, r2, r2		@ a < b: double a's mantissa
	adcs	r3, r3
.L080004f8:
	cmp.w	r8, #0
	bge.n	.L08000506		@ exponent is not negative: divide
.L080004fe:
	movs	r0, #0			@ zero operand or underflow: result 0
	mov	r1, r0
	pop.w	{r4, r5, r6, r7, r8, r10, r11, pc}
.L08000506:
	movs	r0, #0			@ r1:r0 = 0x100000:0 (moving quotient bit)
	mov.w	r1, #0x100000
	mov	r6, r0			@ r6 = quotient low
	mov	r12, r0			@ r12 = quotient high
	b.n	.L08000530
.L08000512:
	subs	r7, r2, r4		@ remainder - divisor (64 bits)
	sbcs.w	r7, r3, r5
	bcc.n	.L08000526		@ remainder below divisor: bit is 0
	subs	r2, r2, r4
	sbc.w	r3, r3, r5
	orrs	r6, r0			@ set the quotient bit
	orr.w	r12, r12, r1
.L08000526:
	lsrs	r1, r1, #1		@ move the quotient bit right
	rrx	r0, r0
	adds	r2, r2, r2		@ remainder *= 2
	adcs	r3, r3
.L08000530:
	orrs.w	r7, r0, r1
	bne.n	.L08000512		@ until the quotient bit is shifted out
	orrs.w	r0, r2, r3
	beq.n	.L08000562		@ remainder zero: exact, rounding word 0
	eor.w	r0, r2, r4
	eor.w	r1, r3, r5
	orrs	r0, r1
	beq.n	.L08000554		@ remainder equals divisor: exactly half
	subs	r0, r2, r4
	sbcs	r3, r5
	bcs.n	.L0800055c		@ remainder above divisor: above half
	movs	r2, #1			@ below half: rounding word 0:1
	movs	r3, #0
	b.n	.L08000562
.L08000554:
	movs	r2, #0
	mov.w	r3, #0x80000000
	b.n	.L08000562
.L0800055c:
	mvn	r2, #1
	asrs	r3, r2, #1		@ rounding word 0xffffffff:0xfffffffe
.L08000562:
	adds.w	r0, r10, r6		@ pack quotient, exponent and sign
	adc.w	r1, r12, r8, lsl #0x14
	adds.w	r0, r0, r10
	adc.w	r1, r1, r11
	pop.w	{r4, r5, r6, r7, r8, r10, r11, lr}
	b.w	fn_08000662		@ round, returns to the caller

@ ----------------------------------------------------------------------------
@ fn_0800057a - converts a double to a 64-bit unsigned integer (truncating
@ toward zero; the sign bit is ignored by the field extraction).
@ In:  r1:r0 = double (r1 high word).   Out: r1:r0 = integer.
@ Takes the exponent field e = (r1 >> 20) & 0x7ff and the mantissa with the
@ implicit bit (r1 = (r1 & 0xfffff) | 0x100000). If e < 0x3ff (below 1.0) the
@ result is 0. If e <= 0x433 the mantissa is shifted right by 0x433 - e
@ (tail call to fn_0800061e); otherwise it is shifted left by e - 0x433
@ (tail call to fn_08000600).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800057a,"ax",%progbits
	.global fn_0800057a
	.thumb_func
	.type fn_0800057a, %function
fn_0800057a:
	ubfx	r2, r1, #0x14, #0xb
	ubfx	r1, r1, #0, #0x14
	movw	r3, #0x3ff
	orr	r1, r1, #0x100000
	cmp	r2, r3
	bge.n	.L08000594
	movs	r0, #0			@ below 1.0: result 0
	mov	r1, r0
	bx	lr
.L08000594:
	movw	r3, #0x433
	cmp	r2, r3
	subw	r2, r2, #0x433		@ r2 = e - 0x433
	bgt.n	.L080005a6
	rsbs	r2, r2, #0		@ r2 = 0x433 - e
	b.w	fn_0800061e		@ shift right
.L080005a6:
	b.w	fn_08000600		@ shift left
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_080005ac - compares two doubles and sets the condition flags.
@ In:  r1:r0 = a (r1 high word), r3:r2 = b (r3 high word).
@ Out: flags from cmp r1,r3 then (if equal) cmp r0,r2; no register result.
@ Each operand that is not negative as a signed 64-bit value is replaced by
@ 0x8000000000000000 - value, which turns the sign-magnitude double format
@ into an order-preserving 64-bit integer; the two are then compared as
@ integers. Uses r4 (saved) and the IT block for the low-word compare.
@ ----------------------------------------------------------------------------
	.section .text.fn_080005ac,"ax",%progbits
	.p2align 2
	.global fn_080005ac
	.thumb_func
	.type fn_080005ac, %function
fn_080005ac:
	push	{r4, r5, lr}
	subs	r4, r0, #0
	sbcs	r4, r1, #0
	blt.n	.L080005c0		@ a negative: keep
	mov.w	r4, #0x80000000
	rsbs	r0, r0, #0
	sbc.w	r1, r4, r1		@ a = 0x8000000000000000 - a
.L080005c0:
	subs	r4, r2, #0
	sbcs	r4, r3, #0
	blt.n	.L080005d4		@ b negative: keep
	mov	r4, r3
	mov.w	r3, #0x80000000
	rsbs	r2, r2, #0
	sbc.w	r3, r3, r4		@ b = 0x8000000000000000 - b
.L080005d4:
	cmp	r1, r3
	it	eq
	cmpeq	r0, r2
	pop	{r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_08000600 - 64-bit logical shift left.
@ In:  r1:r0 = value (r1 high word), r2 = shift count (signed compare).
@ Out: r1:r0 = value << count.
@ A count of 32 or more moves the low word into the high word, shifted by
@ count - 32, and clears the low word; a smaller count combines both words.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000600,"ax",%progbits
	.global fn_08000600
	.thumb_func
	.type fn_08000600, %function
fn_08000600:
	cmp	r2, #0x20
	blt.n	.L0800060e
	subs	r2, #0x20
	lsl.w	r1, r0, r2		@ high = low << (count - 32)
	movs	r0, #0
	bx	lr
.L0800060e:
	lsls	r1, r2			@ high <<= count
	rsb.w	r3, r2, #0x20
	lsr.w	r3, r0, r3		@ bits carried over from the low word
	orrs	r1, r3
	lsls	r0, r2			@ low <<= count
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0800061e - 64-bit logical shift right.
@ In:  r1:r0 = value (r1 high word), r2 = shift count (signed compare).
@ Out: r1:r0 = value >> count (zero fill).
@ A count of 32 or more moves the high word into the low word, shifted by
@ count - 32, and clears the high word; a smaller count combines both words.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800061e,"ax",%progbits
	.global fn_0800061e
	.thumb_func
	.type fn_0800061e, %function
fn_0800061e:
	cmp	r2, #0x20
	blt.n	.L0800062c
	subs	r2, #0x20
	lsr.w	r0, r1, r2		@ low = high >> (count - 32)
	movs	r1, #0
	bx	lr
.L0800062c:
	lsr.w	r3, r1, r2		@ new high word
	lsrs	r0, r2			@ low >>= count
	rsb.w	r2, r2, #0x20
	lsls	r1, r2			@ bits carried down from the high word
	orrs	r0, r1
	mov	r1, r3
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0800063e - 64-bit arithmetic shift right.
@ In:  r1:r0 = value (r1 high word), r2 = shift count (signed compare).
@ Out: r1:r0 = value >> count (sign fill).
@ For a count of 32 or more the low word is the high word shifted
@ arithmetically by count - 32 and the high word is its sign extension
@ (ORed with the sign of the original high word); otherwise both words are
@ combined.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800063e,"ax",%progbits
	.global fn_0800063e
	.thumb_func
	.type fn_0800063e, %function
fn_0800063e:
	cmp	r2, #0x20
	blt.n	.L08000650
	asrs	r3, r1, #0x1f		@ r3 = sign of the high word
	subs	r2, #0x20
	asr.w	r0, r1, r2		@ low = high >> (count - 32)
	orr.w	r3, r3, r0, asr #0x1f
	b.n	.L0800065e
.L08000650:
	asr.w	r3, r1, r2		@ new high word
	lsrs	r0, r2			@ low >>= count
	rsb.w	r2, r2, #0x20
	lsls	r1, r2			@ bits carried down from the high word
	orrs	r0, r1
.L0800065e:
	mov	r1, r3
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08000662 - rounds a packed double: round to nearest, ties to even.
@ In:  r1:r0 = packed result (r1 high word), r3:r2 = rounding word (the
@ discarded bits as a signed 64-bit value: negative means above half).
@ Out: r1:r0 = rounded double.
@ If r3:r2 is not negative the value is returned unchanged. Otherwise 1 is
@ added to r1:r0; then if r3:r2 * 2 is zero (exactly half) bit 0 of r0 is
@ cleared so that a tie rounds to even.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000662,"ax",%progbits
	.global fn_08000662
	.thumb_func
	.type fn_08000662, %function
fn_08000662:
	push	{r4, lr}
	subs	r4, r2, #0
	sbcs	r4, r3, #0
	bge.n	.L0800067e		@ not negative: nothing to round
	.inst.n 0x1c40			@ adds r0, r0, #1
	adc	r1, r1, #0
	adds	r2, r2, r2
	adcs	r3, r3
	orrs	r2, r3
	bne.n	.L0800067e		@ not exactly half
	bic	r0, r0, #1		@ tie: round to even
.L0800067e:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08000680 - normalises, rounds and packs a double from a 64-bit mantissa
@ product (used by the add, subtract and multiply routines).
@ In:  r1:r0 = mantissa (r1 high word), r3:r2 = extra low bits,
@ stack (after the 8 registers pushed here): [sp+0x20] and [sp+0x24] = a
@ 64-bit addend (low, high; the callers pass 0 and the sign bit),
@ [sp+0x28] = exponent.
@ Out: r1:r0 = double, 0 if the exponent becomes negative.
@ Counts the leading zeros of the mantissa (clz of r1, or of r0 plus 32),
@ shifts it left by that count (fn_08000600), folds the extra bits r3:r2,
@ shifted right by 64 - count (fn_0800061e), and a sticky bit when the bits
@ shifted out are non-zero, into the low bits; then splits the 64-bit value
@ into the 53-bit mantissa (>> 11) and the rounding word (<< 21), forms the
@ exponent as (stack exponent - count) + 10 shifted to bit 20, adds the
@ 64-bit addend from the stack and tail-calls fn_08000662 to round.
@ ----------------------------------------------------------------------------
	.global fn_08000680
	.thumb_func
	.type fn_08000680, %function
fn_08000680:
	push.w	{r4, r5, r6, r7, r8, r10, r11, lr}
	mov	r10, r2
	mov	r11, r3
	cbz	r1, .L08000690
	clz	r2, r1
	b.n	.L08000696
.L08000690:
	clz	r2, r0
	adds	r2, #0x20		@ high word zero: 32 + clz of low word
.L08000696:
	mov	r8, r2			@ r8 = leading zero count
	bl	fn_08000600		@ mantissa <<= count
	mov	r4, r0
	mov	r7, r1
	orr.w	r0, r0, r10
	orr.w	r1, r1, r11
	mov	r3, r10
	mov	r2, r11
	orrs	r0, r1
	beq.n	.L080006d8		@ everything zero: return it as is
	mov	r1, r2
	orrs.w	r0, r3, r1
	beq.n	.L080006ec		@ no extra bits to fold in
	rsb.w	r2, r8, #0x40
	mov	r0, r10
	bl	fn_0800061e		@ extra bits >> (64 - count)
	mov	r5, r0
	mov	r6, r1
	mov	r0, r10
	mov	r1, r11
	mov	r2, r8
	bl	fn_08000600		@ extra bits << count (bits shifted past)
	orrs	r0, r1
	beq.n	.L080006e0
	movs	r0, #1			@ sticky bit
	b.n	.L080006e2
.L080006d8:
	mov	r0, r4
	mov	r1, r7
.L080006dc:
	pop.w	{r4, r5, r6, r7, r8, r10, r11, pc}
.L080006e0:
	movs	r0, #0
.L080006e2:
	orrs	r5, r0
	orr.w	r6, r6, r0, asr #0x1f
	orrs	r4, r5			@ fold the extra bits into the mantissa
	orrs	r7, r6
.L080006ec:
	ldr	r0, [sp, #0x28]
	lsls	r3, r4, #0x15		@ rounding word high = low bits << 21
	lsrs	r4, r4, #0xb		@ mantissa low = value >> 11
	sub.w	r0, r0, r8		@ exponent - leading zero count
	movs	r2, #0			@ rounding word low = 0
	lsrs	r5, r7, #0xb
	orr.w	r4, r4, r7, lsl #0x15
	adds	r0, #0xa		@ + 10
	bpl.n	.L08000708
	movs	r0, #0			@ negative exponent: result 0
	mov	r1, r0
	b.n	.L080006dc
.L08000708:
	lsls	r1, r0, #0x14		@ exponent field
	adds	r0, r2, r4
	adcs	r1, r5
	ldrd	r4, r5, [sp, #0x20]
	adds	r0, r0, r4		@ add the addend (sign word) from the stack
	adcs	r1, r5
	pop.w	{r4, r5, r6, r7, r8, r10, r11, lr}
	b.n	fn_08000662		@ round, returns to the caller

@ ----------------------------------------------------------------------------
@ fn_080031ac - formatted-output wrapper with a variable argument list.
@ In:  r0 = format pointer, r1..r3 = further arguments. The four argument
@ registers are pushed so the arguments form a list in memory.
@ Calls fn_080033bc(format, pointer to the argument list on the stack,
@ 0x2000021c, fn_08003e00) and returns to the caller, popping the 16 bytes of
@ arguments with the return.
@ ----------------------------------------------------------------------------
	.section .text.fn_080031ac,"ax",%progbits
	.p2align 2
	.global fn_080031ac
	.thumb_func
	.type fn_080031ac, %function
fn_080031ac:
	push	{r0, r1, r2, r3}
	ldr	r3, .L080031c4
	push	{r4, lr}
	add	r1, sp, #0xc		@ r1 = address of the second argument
	ldr	r2, .L080031c8
	ldr	r0, [sp, #8]		@ r0 = first argument (format)
	bl	fn_080033bc
	pop	{r4}
	ldr.w	pc, [sp], #0x14		@ return and drop the 4 pushed arguments
	.short	0x0000			@ padding
.L080031c4:
	.word	fn_08003e00		@ function pointer passed to fn_080033bc
.L080031c8:
	.word	0x2000021c		@ RAM address passed to fn_080033bc

@ ----------------------------------------------------------------------------
@ fn_080031cc - formatted-output wrapper writing to a stack buffer.
@ In:  r0, r1, r2 = three words stored on the stack; r1 and r2 are passed on.
@ Calls fn_080033bc(r1, r2, pointer to the stack words, fn_08003ac2), then
@ fn_08003ac2(0, pointer to the stack words). Returns the result of
@ fn_080033bc in r0 and the first stack word (updated by the callees) in r1.
@ ----------------------------------------------------------------------------
	.section .text.fn_080031cc,"ax",%progbits
	.p2align 2
	.global fn_080031cc
	.thumb_func
	.type fn_080031cc, %function
fn_080031cc:
	push	{r0, r1, r2, r4, r5, lr}
	mov	r4, r2
	mov	r0, r1
	ldr	r3, .L080031ec
	mov	r2, sp
	mov	r1, r4
	bl	fn_080033bc
	mov	r4, r0			@ keep fn_080033bc result
	mov	r1, sp
	movs	r0, #0
	bl	fn_08003ac2
	mov	r0, r4
	pop	{r1, r2, r3, r4, r5, pc}
	.short	0x0000			@ padding
.L080031ec:
	.word	fn_08003ac2		@ function pointer passed to fn_080033bc

@ ----------------------------------------------------------------------------
@ fn_080031f0 - copies words from one buffer to another (no caller in the
@ image).
@ In:  r0 = source, r1 = destination, r2 = byte count (multiple of 4).
@ Copies one word at a time with post-increment until the count reaches 0.
@ A count that is not a multiple of 4 does not terminate.
@ ----------------------------------------------------------------------------
	.section .text.fn_080031f0,"ax",%progbits
	.global fn_080031f0
	.thumb_func
	.type fn_080031f0, %function
fn_080031f0:
	b.n	.L080031f8
.L080031f2:
	ldmia	r0!, {r3}		@ load a word, advance the source
	.inst.n 0x1f12			@ subs r2, r2, #4
	stmia	r1!, {r3}		@ store it, advance the destination
.L080031f8:
	cmp	r2, #0
	bne.n	.L080031f2
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_080031fe - empty function: returns immediately (no caller in the image).
@ ----------------------------------------------------------------------------
	.section .text.fn_080031fe,"ax",%progbits
	.global fn_080031fe
	.thumb_func
	.type fn_080031fe, %function
fn_080031fe:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08003238 - converts a double to decimal digits (digit generation for the
@ number formatter).
@ In:  r0 = pointer to a 4-word result block, r1 = digit buffer (at least
@ 17 bytes), r3:r2 = double value, stack argument at sp+0x40 (after the 14
@ words pushed here) = digit limit, at sp+0x44 = mode (the value 1 is tested;
@ any other value takes the second path of the code).
@ Out: the block gets { pointer to first digit, decimal exponent, number of
@ digits, mode }. A zero value yields the string "0", a count of 1 and, in
@ mode 1, the bitwise complement of the limit as the exponent.
@ Estimates the decimal exponent as ((binary exponent - 0x3ff) * 0x4d10) >> 16,
@ builds 10^|k| by repeated squaring with fn_080003b8 (multiplying from the
@ constants 5.0 = 0x40140000:0 and 1.0 = 0x3ff00000:0 held in the literal
@ pool), scales the value with fn_080003b8 / fn_0800049c, tests the range
@ with fn_080005ac, converts to an integer with fn_0800026a (adding 0.5) and
@ fn_0800057a (or -1 when out of range), then peels off up to 17 decimal
@ digits from the end of the buffer with fn_08000208 (divide by 10, adding
@ '0'). If the digit count does not fit the limit, the exponent estimate is
@ corrected by one and the conversion repeats; mode 1 may switch to mode 0 with
@ a limit of 17 for a second pass.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003238,"ax",%progbits
	.p2align 2
	.global fn_08003238
	.thumb_func
	.type fn_08003238, %function
fn_08003238:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	sub	sp, #8
	movs	r1, #0
	ldrd	r3, r0, [sp, #0x10]	@ r3:r0 = the double (low : high)
	lsrs	r2, r0, #0x14
	ldr.w	r11, [sp, #0x40]	@ r11 = digit limit
	orrs	r3, r0
	beq.n	.L08003280		@ zero value
	movw	r0, #0x4d10
	subw	r2, r2, #0x3ff
	muls	r2, r0, r2
	asrs	r5, r2, #0x10		@ r5 = decimal exponent estimate
.L0800325a:
	ldr	r0, [sp, #0x44]
	cmp	r0, #1
	beq.n	.L080032a0
	sub.w	r0, r5, r11
	.inst.n 0x1c40			@ adds r0, r0, #1
.L08003266:
	movs.w	r10, r0			@ r10 = scale exponent k
	mov.w	r6, #0
	ldr	r7, .L080033a8		@ r7:r6 = 5.0
	ldr.w	r9, .L080033ac		@ r9:r8 = 1.0
	mov	r8, r6
	mov	r0, r10
	bpl.n	.L080032a6
	rsb.w	r4, r10, #0		@ r4 = |k|
	b.n	.L080032a8
.L08003280:
	ldr	r0, [sp, #0x44]
	movs	r4, #1
	adr	r3, .L080033b0		@ r3 = pointer to the string "0"
	cmp	r0, #1
	bne.n	.L0800328e
	mvn.w	r1, r11
.L0800328e:
	ldr	r0, [sp, #8]
	ldr	r2, [sp, #0x44]
	strd	r3, r1, [r0]
	strd	r4, r2, [r0, #8]
.L0800329a:
	add	sp, #0x18
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}
.L080032a0:
	rsb.w	r0, r11, #0
	b.n	.L08003266
.L080032a6:
	mov	r4, r0
.L080032a8:
	movs	r1, #0
	ldr	r2, .L080033ac
	adds	r1, r1, r1
	adc.w	r0, r2, r4, lsl #0x14
	strd	r1, r0, [sp]
	b.n	.L080032de
.L080032b8:
	lsls	r0, r4, #0x1f
	beq.n	.L080032cc		@ bit 0 of the exponent clear: skip
	mov	r2, r6
	mov	r3, r7
	mov	r0, r8
	mov	r1, r9
	bl	fn_080003b8		@ result *= power
	mov	r8, r0
	mov	r9, r1
.L080032cc:
	mov	r2, r6
	mov	r3, r7
	mov	r0, r2
	mov	r1, r3
	bl	fn_080003b8		@ power *= power
	mov	r6, r0
	mov	r7, r1
	asrs	r4, r4, #1
.L080032de:
	cmp	r4, #0
	bne.n	.L080032b8
	ldrd	r0, r1, [sp, #0x10]
	ldrd	r2, r3, [sp]
	cmp.w	r10, #0
	bge.n	.L080032fe
	bl	fn_080003b8		@ negative k: value * constant * result
	mov	r2, r8
	mov	r3, r9
	bl	fn_080003b8
	b.n	.L0800330a
.L080032fe:
	bl	fn_0800049c		@ k >= 0: value / constant / result
	mov	r2, r8
	mov	r3, r9
	bl	fn_0800049c
.L0800330a:
	mov	r4, r0
	mov	r6, r1
	movs	r2, #0
	ldr	r3, .L080033b4		@ 0x43f00000: upper bound as a double
	bl	fn_080005ac
	bhi.n	.L08003320
	mov.w	r0, #0xffffffff		@ in range: use -1
	mov	r1, r0
	b.n	.L08003330
.L08003320:
	movs	r2, #0
	ldr	r3, .L080033b8		@ 0x3fe00000: 0.5 as a double
	mov	r0, r4
	mov	r1, r6
	bl	fn_0800026a
	bl	fn_0800057a
.L08003330:
	movs	r4, #0x10		@ digit index, from the end of the buffer
	b.n	.L08003348
.L08003334:
	cmp	r4, #0
	blt.n	.L0800334e
	movs	r2, #0xa
	movs	r3, #0
	bl	fn_08000208		@ r3:r2 = remainder, r1:r0 = quotient
	ldr	r3, [sp, #0xc]
	adds	r2, #0x30		@ remainder to ASCII digit
	strb	r2, [r3, r4]
	.inst.n 0x1e64			@ subs r4, r4, #1
.L08003348:
	orrs.w	r2, r0, r1
	bne.n	.L08003334
.L0800334e:
	.inst.n 0x1c64			@ adds r4, r4, #1
	ldr	r2, [sp, #0xc]
	rsb.w	r3, r4, #0x11		@ r3 = number of digits
	add	r4, r2			@ r4 = pointer to the first digit
	ldr	r2, [sp, #0x44]
	cmp	r2, #1
	beq.n	.L08003366
	movs	r2, #1
	orrs	r0, r1
	bne.n	.L08003380
	b.n	.L0800337c
.L08003366:
	orrs	r0, r1
	beq.n	.L08003374
	movs	r0, #0
	mov.w	r11, #0x11
	str	r0, [sp, #0x44]		@ mode = 0
.L08003372:
	b.n	.L0800325a
.L08003374:
	sub.w	r5, r3, r11
	.inst.n 0x1e6d			@ subs r5, r5, #1
	b.n	.L08003398
.L0800337c:
	cmp	r3, r11
	ble.n	.L0800338a
.L08003380:
	mov.w	r2, #0
	add.w	r5, r5, #1
	b.n	.L08003394
.L0800338a:
	bge.n	.L08003394
	mov.w	r2, #0
	sub.w	r5, r5, #1
.L08003394:
	cmp	r2, #0
	beq.n	.L08003372
.L08003398:
	ldr	r0, [sp, #8]
	ldr	r1, [sp, #0x44]
	strd	r3, r1, [r0, #8]
	strd	r4, r5, [r0]
	b.n	.L0800329a
	.short	0x0000			@ padding
.L080033a8:
	.word	0x40140000		@ high word of 5.0
.L080033ac:
	.word	0x3ff00000		@ high word of 1.0
.L080033b0:
	.asciz	"0"			@ digit string used for a zero value
	.short	0x0000			@ padding
.L080033b4:
	.word	0x43f00000		@ high word of 2^64 as a double
.L080033b8:
	.word	0x3fe00000		@ high word of 0.5 as a double
