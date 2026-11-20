@ runtime_36.s - runtime library, part 36: byte copy/fill, string helpers and the double-precision arithmetic routines (batch 36)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ copy_bytes_080070dc - copy r2 bytes from r1 to r0.
@ r0 = destination, r1 = source, r2 = byte count; no return value.
@ When both addresses are word aligned ((r0 | r1) & 3 == 0) it copies words
@ while the count is above 3 (ldmia/stmia of one register, count - 4 each
@ round); the remaining bytes are copied one at a time.
@ ----------------------------------------------------------------------------
	.section .text.copy_bytes_080070dc,"ax",%progbits
	.p2align 2
	.global copy_bytes_080070dc
	.thumb_func
	.type copy_bytes_080070dc, %function
copy_bytes_080070dc:
	orr.w	r3, r0, r1
	lsls	r3, r3, #30			@ keeps the low two bits of (r0 | r1)
	beq.n	.L080070ec			@ both word aligned: word loop
	b.n	.L080070fa			@ otherwise bytes only
.L080070e6:
	ldmia	r1!, {r3}			@ copy one word
	.inst.n	0x1f12				@ subs r2, r2, #4
	stmia	r0!, {r3}
.L080070ec:
	cmp	r2, #4
	bcs.n	.L080070e6			@ count >= 4: next word
	b.n	.L080070fa
.L080070f2:
	ldrb.w	r3, [r1], #1			@ copy one byte
	strb.w	r3, [r0], #1
.L080070fa:
	.inst.n	0x1e52				@ subs r2, r2, #1
	bcs.n	.L080070f2			@ loop while the count did not wrap
	bx	lr

@ ----------------------------------------------------------------------------
@ fill_bytes_08007100 - store a byte value into r1 consecutive bytes.
@ r0 = destination, r1 = byte count, r2 = fill byte (only the low 8 bits are
@ used); no return value. 14-byte routine at 0x08007100.
@ ----------------------------------------------------------------------------
	.section .text.fill_bytes_08007100,"ax",%progbits
	.global fill_bytes_08007100
	.thumb_func
	.type fill_bytes_08007100, %function
fill_bytes_08007100:
	uxtb	r2, r2
	b.n	.L08007108
.L08007104:
	strb.w	r2, [r0], #1
.L08007108:
	.inst.n	0x1e49				@ subs r1, r1, #1
	bcs.n	.L08007104			@ loop while the count did not wrap
	bx	lr

@ ----------------------------------------------------------------------------
@ zero_bytes - clear r1 bytes at r0.
@ r0 = destination, r1 = byte count; no return value. Sets r2 = 0 and branches
@ to fill_bytes_08007100 (0x08007100).
@ ----------------------------------------------------------------------------
	.global zero_bytes
	.thumb_func
	.type zero_bytes, %function
zero_bytes:
	movs	r2, #0
	b.n	fill_bytes_08007100

@ ----------------------------------------------------------------------------
@ fill_bytes_returning_destination - fill r2 bytes at r0 with the byte r1.
@ r0 = destination, r1 = fill byte, r2 = byte count; returns r0 (the
@ destination). Swaps r1 and r2 into the argument order of 0x08007100
@ (r0 = destination, r1 = count, r2 = value) and calls it.
@ ----------------------------------------------------------------------------
	.section .text.fill_bytes_returning_destination,"ax",%progbits
	.global fill_bytes_returning_destination
	.thumb_func
	.type fill_bytes_returning_destination, %function
fill_bytes_returning_destination:
	push	{r4, lr}
	mov	r3, r2
	mov	r2, r1
	mov	r4, r0				@ keep the destination
	mov	r1, r3
	bl	fill_bytes_08007100
	mov	r0, r4
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ string_length - length of a zero-terminated byte string.
@ r0 = string; returns the number of bytes before the terminating zero.
@ Walks the bytes until a zero byte is read (14-byte routine at 0x08007124).
@ ----------------------------------------------------------------------------
	.section .text.string_length,"ax",%progbits
	.global string_length
	.thumb_func
	.type string_length, %function
string_length:
	adds	r2, r0, #1			@ r2 = string + 1
.L08007126:
	ldrb.w	r1, [r0], #1
	cmp	r1, #0
	bne.n	.L08007126
	subs	r0, r0, r2			@ end pointer - (string + 1)
	bx	lr

@ ----------------------------------------------------------------------------
@ string_compare - compare two zero-terminated byte strings.
@ r0 = first string, r1 = second string; returns the difference of the first
@ differing bytes (or of the terminators: 0 when equal). Compares byte by byte
@ and stops at the first difference or at a zero byte.
@ ----------------------------------------------------------------------------
	.section .text.string_compare,"ax",%progbits
	.global string_compare
	.thumb_func
	.type string_compare, %function
string_compare:
	push	{r4, lr}
	movs	r2, #0				@ index
	b.n	.L0800713a
.L08007138:
	.inst.n	0x1c52				@ adds r2, r2, #1
.L0800713a:
	ldrb	r3, [r0, r2]
	ldrb	r4, [r1, r2]
	cmp	r3, r4
	bne.n	.L08007146
	cmp	r3, #0
	bne.n	.L08007138
.L08007146:
	uxtb	r0, r3
	uxtb	r1, r4
	subs	r0, r0, r1
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ string_copy - copy a zero-terminated byte string.
@ r0 = destination, r1 = source; returns the destination. Copies the bytes
@ including the terminating zero (18-byte routine at 0x0800714e).
@ ----------------------------------------------------------------------------
	.section .text.string_copy,"ax",%progbits
	.global string_copy
	.thumb_func
	.type string_copy, %function
string_copy:
	mov	r3, r0				@ keep the destination
.L08007150:
	ldrb.w	r2, [r1], #1
	strb.w	r2, [r0], #1
	cmp	r2, #0
	bne.n	.L08007150
	mov	r0, r3
	bx	lr

@ ----------------------------------------------------------------------------
@ double_multiply - multiply two doubles.
@ r0:r1 = first double (low word, high word), r2:r3 = second double; returns
@ the product as a double in r0:r1.
@ Returns 0 in r0 and r1 when either operand has a zero magnitude (branch to
@ 0x0800723e). Otherwise multiplies the 53-bit mantissas with 32x32 to 64 bit
@ products (umull, mla), adds the exponents (minus 0x3ff), xors the signs and
@ hands the pieces to fn_0800751a for normalising and rounding (three words
@ on the stack: value added to the result low word, sign, exponent).
@ ----------------------------------------------------------------------------
	.section .text.double_multiply,"ax",%progbits
	.p2align 2
	.global double_multiply
	.thumb_func
	.type double_multiply, %function
double_multiply:
	push.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	eor.w	r4, r1, r3
	and	r4, r4, #0x80000000		@ sign of the product
	bic	r1, r1, #0x80000000		@ magnitude of the first operand
	str	r4, [sp]
	mov.w	r11, #0
	bic	r3, r3, #0x80000000		@ magnitude of the second operand
	orrs.w	r4, r0, r1
	beq.n	.L0800723e			@ first operand zero
	orrs.w	r4, r2, r3
	beq.n	.L0800723e			@ second operand zero
	ubfx	r4, r3, #20, #11		@ exponent of the second operand
	ubfx	r5, r1, #20, #11		@ exponent of the first operand
	add	r4, r5
	subw	r4, r4, #0x3f3
	str	r4, [sp, #4]
	umull	r5, r4, r0, r2
	ubfx	r1, r1, #0, #20
	orr	r1, r1, #0x100000		@ mantissa with the hidden bit
	ubfx	r3, r3, #0, #20
	orr	r3, r3, #0x100000
	mla	r4, r1, r2, r4
	mla	lr, r0, r3, r4
	lsrs	r4, r0, #10
	lsrs	r7, r2, #10
	orr.w	r4, r4, r1, lsl #22
	orr.w	r7, r7, r3, lsl #22
	umull	r6, r8, r4, r7
	str	r5, [sp, #8]
	lsrs	r5, r1, #10
	mla	r5, r5, r7, r8
	lsr.w	r12, r3, #10
	mla	r4, r4, r12, r5
	lsls	r7, r4, #20
	ldr	r5, [sp, #8]
	lsl.w	r8, r6, #20
	orr.w	r7, r7, r6, lsr #12
	subs.w	r5, r5, r8
	sbc.w	r12, lr, r7
	lsrs	r7, r0, #26
	lsrs	r2, r2, #26
	orr.w	r7, r7, r1, lsl #6
	orr.w	r2, r2, r3, lsl #6
	umull	r0, r1, r7, r2
	subs.w	r1, r6, r11
	sbc.w	r4, r4, r0
	lsrs	r3, r5, #20
	orr.w	r3, r3, r12, lsl #12
	adds	r6, r3, r1
	adc.w	r0, r4, r12, lsr #20
	mov	r10, r11
	mov	r1, r10
	umlal	r0, r1, r7, r2
	ubfx	r4, r5, #0, #20
	lsl.w	r3, r11, #12
	orr.w	r3, r3, r4, lsr #20
	lsl.w	r2, r4, #12
	ldr	r4, [sp, #4]
	orr.w	r3, r3, r6
	sub.w	r4, r4, #12
	str	r4, [sp, #8]			@ exponent for the normaliser
	ldr	r4, [sp]
	strd	r11, r4, [sp]			@ stack: 0, sign, exponent
	bl	fn_0800751a
.L08007238:
	add	sp, #12
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0800723e:
	movs	r0, #0				@ zero operand: result 0
	mov	r1, r0
	b.n	.L08007238

@ ----------------------------------------------------------------------------
@ double_divide - divide two doubles.
@ r0:r1 = dividend double, r2:r3 = divisor double; returns the quotient as a
@ double in r0:r1.
@ Returns 0 in r0 and r1 when either operand has zero magnitude (branch to
@ 0x080072a6) and when the resulting exponent is negative. The exponent is
@ the difference plus 0x3fd or 0x3fe depending on the mantissa comparison;
@ 53 iterations of shift-and-subtract division of the mantissas follow;
@ remainder-based rounding bits are set in r2/r3 and the result goes through
@ round_half_even_increment_64 (tail branch).
@ ----------------------------------------------------------------------------
	.section .text.double_divide,"ax",%progbits
	.global double_divide
	.thumb_func
	.type double_divide, %function
double_divide:
	push.w	{r4, r5, r6, r7, r8, r10, r11, lr}
	eor.w	r4, r1, r3
	and	r11, r4, #0x80000000		@ sign of the quotient
	bic	r5, r1, #0x80000000
	mov	r4, r2
	mov.w	r10, #0
	bic	r1, r3, #0x80000000
	orrs.w	r2, r0, r5
	beq.n	.L080072a6			@ dividend zero
	orrs.w	r2, r4, r1
	beq.n	.L080072a6			@ divisor zero
	ubfx	r7, r5, #20, #11		@ dividend exponent
	mov	r2, r0
	ubfx	r3, r5, #0, #20
	ubfx	r0, r1, #0, #20
	ubfx	r6, r1, #20, #11		@ divisor exponent
	orr	r5, r0, #0x100000
	orr	r3, r3, #0x100000
	sub.w	r8, r7, r6
	subs	r0, r2, r4
	mov	lr, r10
	addw	r8, r8, #0x3fd
	sbcs.w	r0, r3, r5			@ compare the mantissas
	bcc.n	.L0800729c
	add.w	r8, r8, #1
	b.n	.L080072a0
.L0800729c:
	adds	r2, r2, r2			@ dividend mantissa << 1
	adcs	r3, r3
.L080072a0:
	cmp.w	r8, #0
	bge.n	.L080072ae
.L080072a6:
	movs	r0, #0				@ result 0
	mov	r1, r0
	pop.w	{r4, r5, r6, r7, r8, r10, r11, pc}
.L080072ae:
	movs	r0, #0
	mov.w	r1, #0x100000
	mov	r6, r0
	mov	r12, r0
	b.n	.L080072d8
.L080072ba:
	subs	r7, r2, r4			@ trial subtraction of the divisor mantissa
	sbcs.w	r7, r3, r5
	bcc.n	.L080072ce
	subs	r2, r2, r4
	sbc.w	r3, r3, r5
	orrs	r6, r0				@ set the quotient bit (low word)
	orr.w	r12, r12, r1			@ set the quotient bit (high word)
.L080072ce:
	lsrs	r1, r1, #1
	rrx	r0, r0				@ move the quotient bit mask right
	adds	r2, r2, r2
	adcs	r3, r3				@ remainder << 1
.L080072d8:
	orrs.w	r7, r0, r1
	bne.n	.L080072ba			@ until the bit mask is empty
	orrs.w	r0, r2, r3
	beq.n	.L0800730a			@ remainder zero: exact
	eor.w	r0, r2, r4
	eor.w	r1, r3, r5
	orrs	r0, r1
	beq.n	.L080072fc			@ remainder equals the divisor mantissa
	subs	r0, r2, r4
	sbcs	r3, r5
	bcs.n	.L08007304			@ remainder above the divisor mantissa
	movs	r2, #1
	movs	r3, #0
	b.n	.L0800730a
.L080072fc:
	movs	r2, #0
	mov.w	r3, #0x80000000
	b.n	.L0800730a
.L08007304:
	mvn	r2, #1
	asrs	r3, r2, #1
.L0800730a:
	adds.w	r0, r10, r6
	adc.w	r1, r12, r8, lsl #20		@ add the exponent
	adds.w	r0, r0, r10
	adc.w	r1, r1, r11			@ add the sign
	pop.w	{r4, r5, r6, r7, r8, r10, r11, lr}
	b.w	round_half_even_increment_64

@ ----------------------------------------------------------------------------
@ int_to_double - convert a signed 32-bit integer to a double.
@ r0 = signed integer; returns the double in r0:r1.
@ r1 = r0 >> 31 (logical shift, so 0 or 1); r0 = (r0 ^ (r0 asr 31)) + r1 is the
@ absolute value. The sign word (r1 << 31) and the exponent base 0x433 are
@ passed on the stack with a zero word; r1 = r2 = r3 = 0, and the call goes to
@ fn_0800751a for normalising.
@ ----------------------------------------------------------------------------
	.section .text.int_to_double,"ax",%progbits
	.global int_to_double
	.thumb_func
	.type int_to_double, %function
int_to_double:
	push	{r1, r2, r3, lr}
	lsrs	r1, r0, #31
	eor.w	r0, r0, r0, asr #31
	add	r0, r1				@ absolute value
	lsls	r2, r1, #31			@ sign word
	movs	r1, #0
	movw	r3, #0x433			@ exponent base
	stm.w	sp, {r1, r2, r3}
	mov	r2, r1
	mov	r3, r1
	bl	fn_0800751a
	add	sp, #12
	pop	{pc}

@ ----------------------------------------------------------------------------
@ double_to_int32 - convert a double to a signed 32-bit integer.
@ r0:r1 = double; returns the integer in r0.
@ An exponent field below 0x3ff gives 0. Up to exponent 0x433 the 53-bit
@ mantissa is shifted right by (0x433 - exponent) with shift_right_64; above
@ that the low word is shifted left. The result is negated when the sign bit
@ (bit 31 of r1) is set.
@ ----------------------------------------------------------------------------
	.section .text.double_to_int32,"ax",%progbits
	.global double_to_int32
	.thumb_func
	.type double_to_int32, %function
double_to_int32:
	push	{r4, r5, r6, lr}
	ubfx	r2, r1, #20, #11		@ exponent field
	and	r5, r1, #0x80000000		@ sign
	movs	r4, #0
	ubfx	r1, r1, #0, #20
	movw	r3, #0x3ff
	orr	r1, r1, #0x100000		@ mantissa with the hidden bit
	cmp	r2, r3
	bge.n	.L08007364
	movs	r0, #0
.L08007362:
	pop	{r4, r5, r6, pc}
.L08007364:
	movw	r3, #0x433
	cmp	r2, r3
	subw	r2, r2, #0x433
	bgt.n	.L08007378
	rsbs	r2, r2, #0
	bl	shift_right_64
	b.n	.L0800737a
.L08007378:
	lsls	r0, r2
.L0800737a:
	orrs	r4, r5
	beq.n	.L08007362			@ positive: done
	rsbs	r0, r0, #0			@ negate
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ float_to_double - convert float bits to a double.
@ r0 = float bits; returns the double in r0:r1.
@ Returns 0 when the magnitude bits are 0. Otherwise the sign is kept, the
@ exponent field + 0x380 is placed at bit 20 of the high word, the 23-bit
@ fraction is shifted right by 3 into the high word and the remaining 3
@ fraction bits are shifted into the top of the low word.
@ ----------------------------------------------------------------------------
	.section .text.float_to_double,"ax",%progbits
	.global float_to_double
	.thumb_func
	.type float_to_double, %function
float_to_double:
	and	r2, r0, #0x80000000		@ sign
	bics	r0, r0, #0x80000000		@ magnitude
	beq.n	.L080073a2
	lsrs	r1, r0, #23
	add.w	r1, r1, #0x380			@ exponent + 0x380
	ubfx	r0, r0, #0, #23			@ fraction
	orr.w	r1, r2, r1, lsl #20
	lsrs	r2, r0, #3
	lsls	r0, r0, #29
	orrs	r1, r2
	bx	lr
.L080073a2:
	movs	r0, #0
	mov	r1, r0
	bx	lr

@ ----------------------------------------------------------------------------
@ double_to_float - convert a double to float bits.
@ r0:r1 = double; returns the float bits in r0.
@ Returns 0 when the double is zero or the biased exponent minus 0x380 is not
@ above 0. Otherwise builds sign + (exponent - 0x380) << 23 + the fraction
@ from the high mantissa bits, then tail-branches to round_nearest_even with
@ r1 = low word << 3 (the dropped bits).
@ ----------------------------------------------------------------------------
	.section .text.double_to_float,"ax",%progbits
	.p2align 2
	.global double_to_float
	.thumb_func
	.type double_to_float, %function
double_to_float:
	and	r3, r1, #0x80000000		@ sign
	push	{r4, r5}
	bic	r1, r1, #0x80000000
	orrs.w	r2, r0, r1
	beq.n	.L080073c6			@ zero
	lsrs	r2, r1, #20
	sub.w	r2, r2, #0x380			@ rebased exponent
	ubfx	r1, r1, #0, #20
	cmp	r2, #0
	bgt.n	.L080073cc
.L080073c6:
	pop	{r4, r5}
	movs	r0, #0
	bx	lr
.L080073cc:
	lsrs	r4, r0, #29
	orr.w	r4, r4, r1, lsl #3
	lsls	r1, r0, #3			@ dropped bits for the rounding
	adds	r0, r4, r3
	pop	{r4, r5}
	add.w	r0, r0, r2, lsl #23
	b.w	round_nearest_even

@ ----------------------------------------------------------------------------
@ unsigned_divide_32 - unsigned 32-bit division.
@ r0 = dividend, r1 = divisor; returns the quotient in r0.
@ 32 iterations from bit 31 down: when divisor <= dividend >> k it subtracts
@ divisor << k and sets bit k of the quotient.
@ ----------------------------------------------------------------------------
	.section .text.unsigned_divide_32,"ax",%progbits
	.p2align 2
	.global unsigned_divide_32
	.thumb_func
	.type unsigned_divide_32, %function
unsigned_divide_32:
	push	{r4, r5, lr}
	mov	r3, r1				@ divisor
	mov	r1, r0				@ remainder
	movs	r0, #0				@ quotient
	movs	r2, #0x20
	movs	r4, #1
	b.n	.L08007402
.L080073ee:
	lsr.w	r5, r1, r2
	cmp	r5, r3
	bcc.n	.L08007402
	lsl.w	r5, r3, r2
	subs	r1, r1, r5
	lsl.w	r5, r4, r2
	add	r0, r5
.L08007402:
	subs	r5, r2, #0
	sub.w	r2, r2, #1
	bgt.n	.L080073ee
	pop	{r4, r5, pc}

@ ----------------------------------------------------------------------------
@ unsigned_divide_64 - unsigned 64-bit division.
@ r0:r1 = dividend (low, high), r2:r3 = divisor (low, high); returns the
@ 64-bit quotient in r0:r1 and the remainder in r2:r3.
@ 64 iterations from bit 63 down: compares dividend >> k (shift_right_64) with
@ the divisor, subtracts divisor << k (shift_left_64) and adds 1 << k to the
@ quotient.
@ ----------------------------------------------------------------------------
	.section .text.unsigned_divide_64,"ax",%progbits
	.global unsigned_divide_64
	.thumb_func
	.type unsigned_divide_64, %function
unsigned_divide_64:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	mov	r5, r0
	movs	r0, #0
	mov	r10, r2
	mov	r11, r3
	mov	r8, r1
	mov	r6, r0
	mov	r9, r0
	movs	r4, #0x40
	b.n	.L0800745a
.L08007422:
	mov	r0, r5
	mov	r1, r8
	mov	r7, r8
	mov	r2, r4
	bl	shift_right_64
	mov	r3, r10
	mov	r2, r11
	subs	r0, r0, r3
	sbcs	r1, r2
	bcc.n	.L0800745a			@ dividend >> k < divisor: skip
	mov	r1, r2
	mov	r0, r3
	mov	r2, r4
	bl	shift_left_64
	subs	r5, r5, r0
	sbc.w	r8, r7, r1			@ dividend -= divisor << k
	mov	r7, r9
	mov	r2, r4
	movs	r0, #1
	movs	r1, #0
	bl	shift_left_64
	adds.w	r9, r7, r0
	adcs	r6, r1				@ quotient += 1 << k
.L0800745a:
	subs	r0, r4, #0
	sub.w	r4, r4, #1
	bgt.n	.L08007422
	mov	r0, r9
	mov	r1, r6
	mov	r2, r5
	mov	r3, r8
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}

@ ----------------------------------------------------------------------------
@ shift_right_64 - logical right shift of a 64-bit value.
@ r0:r1 = value (low, high), r2 = shift count; returns the shifted value in
@ r0:r1. Counts below 32 combine both words; counts of 32 or more shift the
@ high word right by (count - 32) into the low word and give a high word of 0.
@ ----------------------------------------------------------------------------
	.section .text.shift_right_64,"ax",%progbits
	.global shift_right_64
	.thumb_func
	.type shift_right_64, %function
shift_right_64:
	cmp	r2, #0x20
	blt.n	.L0800747c
	subs	r2, #0x20
	lsr.w	r0, r1, r2
	movs	r1, #0
	bx	lr
.L0800747c:
	lsr.w	r3, r1, r2
	lsrs	r0, r2
	rsb.w	r2, r2, #0x20
	lsls	r1, r2
	orrs	r0, r1
	mov	r1, r3
	bx	lr

@ ----------------------------------------------------------------------------
@ round_nearest_even - round r0 to nearest even by the dropped bits in r1.
@ r0 = result bits so far, r1 = remainder bits left-aligned (bit 31 = first
@ dropped bit); returns r0.
@ cmp r1, #0: when r1 >= 0 (signed) r0 is returned unchanged. Otherwise
@ r0 += 1, r1 <<= 1 sets the flags, and when that result is 0 (r1 was exactly
@ 0x80000000) bit 0 of r0 is cleared.
@ Reached by the tail branch of double_to_float.
@ ----------------------------------------------------------------------------
	.section .text.round_nearest_even,"ax",%progbits
	.global round_nearest_even
	.thumb_func
	.type round_nearest_even, %function
round_nearest_even:
	cmp	r1, #0
	it	ge
	bxge	lr
	.inst.n	0x1c40				@ adds r0, r0, #1
	lsls	r1, r1, #1
	it	eq
	biceq	r0, r0, #1
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_080074a0 - normalise and round a 64-bit mantissa to float bits.
@ r0 = high word of a 64-bit mantissa, r1 = low word, r2 = value added to the
@ result (sign), r3 = exponent; returns the float bits in r0.
@ Normalises with clz of r0, folds the low word into a sticky bit, rounds to
@ nearest even at bit 7 of the shifted value, returns 0 when the exponent term
@ goes negative.
@ ----------------------------------------------------------------------------
	.section .text.fn_080074a0,"ax",%progbits
	.p2align 2
	.global fn_080074a0
	.thumb_func
	.type fn_080074a0, %function
fn_080074a0:
	push	{r4}
	clz	r12, r0
	lsl.w	r0, r0, r12
	orrs.w	r4, r0, r1
	itt	eq
	popeq	{r4}
	bxeq	lr				@ both words zero: return 0
	cbz	r1, .L080074ca
	rsb.w	r4, r12, #0x20
	lsr.w	r4, r1, r4
	lsls.w	r1, r1, r12
	it	ne
	movne	r1, #1				@ sticky bit
	orrs	r1, r4
	orrs	r0, r1
.L080074ca:
	sub.w	r1, r3, r12
	adds	r3, r1, #7			@ exponent term
	lsl.w	r1, r0, #24			@ dropped bits
	lsr.w	r0, r0, #8
	ittt	mi
	movmi	r0, #0
	popmi	{r4}
	bxmi	lr				@ exponent term negative: return 0
	add.w	r0, r0, r3, lsl #23
	add	r0, r2
	cmp	r1, #0
	itt	ge
	popge	{r4}
	bxge	lr
	.inst.n	0x1c40				@ adds r0, r0, #1
	lsls	r1, r1, #1
	it	eq
	biceq	r0, r0, #1
	pop	{r4}
	bx	lr

@ ----------------------------------------------------------------------------
@ round_half_even_increment_64 - round a 64-bit value by 64 remainder bits.
@ r0:r1 = 64-bit value (low, high), r2:r3 = 64-bit remainder bits; returns the
@ adjusted value in r0:r1. When the remainder is negative as a signed 64-bit
@ value (top bit set) 1 is added to r0:r1; when the remainder shifted left by
@ 1 is then 0 (exact half) bit 0 of r0 is cleared.
@ ----------------------------------------------------------------------------
	.section .text.round_half_even_increment_64,"ax",%progbits
	.global round_half_even_increment_64
	.thumb_func
	.type round_half_even_increment_64, %function
round_half_even_increment_64:
	push	{r4, lr}
	subs	r4, r2, #0
	sbcs	r4, r3, #0			@ sign of the remainder
	bge.n	.L08007518
	.inst.n	0x1c40				@ adds r0, r0, #1
	adc	r1, r1, #0
	adds	r2, r2, r2
	adcs	r3, r3
	orrs	r2, r3
	bne.n	.L08007518
	bic	r0, r0, #1			@ exact half: round to even
.L08007518:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0800751a - normalise and pack a 64-bit mantissa into a double.
@ r0:r1 = 64-bit mantissa (low, high), r2:r3 = extra low bits, three stack
@ words (a value added to the result low word, the sign, the exponent);
@ returns the packed double in r0:r1.
@ Counts leading zeros (clz of r1, or of r0 + 0x20 when r1 is 0), shifts left
@ with shift_left_64 and folds the lost bits into a sticky bit using
@ shift_right_64, shifts right by 11, adds the sign and the exponent
@ (exponent - clz + 10, in units of 0x100000), rounds with
@ round_half_even_increment_64 (tail branch) and returns 0 when the exponent
@ term is negative.
@ ----------------------------------------------------------------------------
	.global fn_0800751a
	.thumb_func
	.type fn_0800751a, %function
fn_0800751a:
	push.w	{r4, r5, r6, r7, r8, r10, r11, lr}
	mov	r10, r2
	mov	r11, r3
	cbz	r1, .L0800752a
	clz	r2, r1
	b.n	.L08007530
.L0800752a:
	clz	r2, r0
	adds	r2, #0x20
.L08007530:
	mov	r8, r2				@ leading zero count
	bl	shift_left_64
	mov	r4, r0
	mov	r7, r1
	orr.w	r0, r0, r10
	orr.w	r1, r1, r11
	mov	r3, r10
	mov	r2, r11
	orrs	r0, r1
	beq.n	.L08007572
	mov	r1, r2
	orrs.w	r0, r3, r1
	beq.n	.L08007586
	rsb.w	r2, r8, #0x40
	mov	r0, r10
	bl	shift_right_64
	mov	r5, r0
	mov	r6, r1
	mov	r0, r10
	mov	r1, r11
	mov	r2, r8
	bl	shift_left_64
	orrs	r0, r1
	beq.n	.L0800757a
	movs	r0, #1
	b.n	.L0800757c
.L08007572:
	mov	r0, r4
	mov	r1, r7
.L08007576:
	pop.w	{r4, r5, r6, r7, r8, r10, r11, pc}
.L0800757a:
	movs	r0, #0
.L0800757c:
	orrs	r5, r0
	orr.w	r6, r6, r0, asr #31
	orrs	r4, r5
	orrs	r7, r6
.L08007586:
	ldr	r0, [sp, #0x28]			@ exponent
	lsls	r3, r4, #21
	lsrs	r4, r4, #11
	sub.w	r0, r0, r8
	movs	r2, #0
	lsrs	r5, r7, #11
	orr.w	r4, r4, r7, lsl #21
	adds	r0, #10
	bpl.n	.L080075a2
	movs	r0, #0				@ negative exponent term: result 0
	mov	r1, r0
	b.n	.L08007576
.L080075a2:
	lsls	r1, r0, #20
	adds	r0, r2, r4
	adcs	r1, r5
	ldrd	r4, r5, [sp, #0x20]		@ value added (low), sign
	adds	r0, r0, r4
	adcs	r1, r5
	pop.w	{r4, r5, r6, r7, r8, r10, r11, lr}
	b.n	round_half_even_increment_64

@ ----------------------------------------------------------------------------
@ double_add - add two doubles.
@ r0:r1 = first double, r2:r3 = second double; returns the sum in r0:r1.
@ Orders the operands by magnitude, returns the larger one when the other is
@ zero, aligns the smaller mantissa with shift_left_64 / arithmetic_shift_right_64
@ by the exponent difference (below 0x40), adds or subtracts according to the
@ xor of the signs, then renormalises through fn_0800751a or rounds with
@ round_half_even_increment_64 (tail branch). Stack words used: sign xor,
@ exponent difference, larger exponent.
@ ----------------------------------------------------------------------------
	.section .text.double_add,"ax",%progbits
	.global double_add
	.thumb_func
	.type double_add, %function
double_add:
	push.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r8, r0
	eor.w	r0, r1, r3
	lsrs	r0, r0, #31			@ 1 when the signs differ
	mov	r4, r1
	str	r0, [sp]
	bic	r1, r1, #0x80000000
	bic	r5, r3, #0x80000000
	subs.w	r0, r8, r2
	sbcs	r1, r5				@ compare the magnitudes
	bcs.n	.L080075e2
	mov	r0, r8				@ swap the operands
	mov	r1, r4
	mov	r8, r2
	mov	r4, r3
	mov	r3, r1
	mov	r2, r0
.L080075e2:
	bic	r0, r3, #0x80000000
	orrs	r0, r2
	beq.n	.L0800767a			@ smaller operand zero: return the larger
	lsrs	r7, r4, #20
	ubfx	r0, r7, #0, #11			@ exponent of the larger
	ubfx	r1, r3, #20, #11		@ exponent of the smaller
	str	r0, [sp, #8]
	subs	r0, r0, r1
	str	r0, [sp, #4]			@ exponent difference
	cmp	r0, #0x40
	bge.n	.L080076d6
	ubfx	r0, r3, #0, #20
	orr	r11, r0, #0x100000		@ mantissa of the smaller operand
	ldr	r0, [sp]
	mov	r10, r2
	cbz	r0, .L08007616
	movs	r3, #0
	rsbs	r10, r2, r3			@ signs differ: negate the mantissa
	sbc.w	r11, r3, r11
.L08007616:
	ldr	r0, [sp, #4]
	mov	r1, r11
	rsb.w	r2, r0, #0x40
	mov	r0, r10
	bl	shift_left_64
	mov	r6, r0				@ bits shifted out below
	mov	r5, r1
	mov	r0, r10
	mov	r1, r11
	ldr	r2, [sp, #4]
	bl	arithmetic_shift_right_64
	adds.w	r0, r0, r8
	adcs	r1, r4
	movs	r4, #0
	eor.w	r2, r7, r1, lsr #20
	eor.w	r3, r4, r7, asr #31
	orrs	r2, r3
	beq.n	.L080076c8
	ldr	r2, [sp]
	cbz	r2, .L080076a4
	ldr	r2, [sp, #4]
	cmp	r2, #1
	lsl.w	r2, r7, #20
	bgt.n	.L08007680
	subs	r0, r0, r4
	sbc.w	r1, r1, r2
	mov.w	r2, #0x80000000
	and.w	r2, r2, r7, lsl #20
	strd	r4, r2, [sp]
	.inst.n	0x1c00				@ adds r0, r0, #0
	adc	r1, r1, #0x100000
	mov	r2, r6
	mov	r3, r5
	bl	fn_0800751a
.L08007674:
	add	sp, #12
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0800767a:
	mov	r0, r8
	mov	r1, r4
	b.n	.L08007674
.L08007680:
	subs	r0, r0, r4
	sbc.w	r1, r1, r2
	.inst.n	0x1c00				@ adds r0, r0, #0
	adc	r3, r1, #0x100000
	adds	r0, r0, r0
	adcs	r3, r3
	adds	r0, r4, r0
	sub.w	r7, r2, #0x200000
	adc.w	r1, r7, r3
	orr.w	r0, r0, r5, lsr #31
	adds	r6, r6, r6
	adcs	r5, r5
	b.n	.L080076c8
.L080076a4:
	lsrs	r5, r5, #1
	rrx	r6, r6
	orr.w	r5, r5, r0, lsl #31
	lsl.w	r2, r7, #20
	subs	r0, r0, r4
	sbc.w	r1, r1, r2
	.inst.n	0x1c00				@ adds r0, r0, #0
	adc	r1, r1, #0x100000
	lsrs	r1, r1, #1
	rrx	r0, r0
	adds	r0, r0, r4
	adcs	r1, r2
.L080076c8:
	mov	r2, r6
	mov	r3, r5
.L080076cc:
	add	sp, #12
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w	round_half_even_increment_64
.L080076d6:
	ldr	r0, [sp]
	movs	r2, #1
	lsls	r0, r0, #1
	movs	r3, #0
	rsbs	r2, r0, r2
	sbc.w	r3, r3, r0, asr #31
	ldr	r0, [sp]
	mov	r1, r4
	asr.w	r4, r0, #31
	subs.w	r0, r8, r0
	sbc.w	r1, r1, r4
	b.n	.L080076cc

@ ----------------------------------------------------------------------------
@ double_subtract - subtract two doubles.
@ r0:r1 = first double, r2:r3 = second double; returns first minus second.
@ Flips bit 31 of r3 and branches to double_add.
@ ----------------------------------------------------------------------------
	.global double_subtract
	.thumb_func
	.type double_subtract, %function
double_subtract:
	eor	r3, r3, #0x80000000
	b.n	double_add

@ ----------------------------------------------------------------------------
@ double_reverse_subtract - subtract two doubles, operands reversed.
@ r0:r1 = first double, r2:r3 = second double; returns second minus first.
@ Flips bit 31 of r1 and branches to double_add.
@ ----------------------------------------------------------------------------
	.global double_reverse_subtract
	.thumb_func
	.type double_reverse_subtract, %function
double_reverse_subtract:
	eor	r1, r1, #0x80000000
	b.n	double_add

@ ----------------------------------------------------------------------------
@ double_scale_by_power_of_two - add an integer to the exponent of a double.
@ r0:r1 = double, r2 = signed exponent increment; returns the double in r0:r1.
@ Returns the input unchanged when its magnitude is zero. When the biased
@ exponent plus r2 is above 0 it returns the high word plus (r2 << 20);
@ otherwise it returns 0 in r0 and r1. Followed by two bytes of zero padding.
@ ----------------------------------------------------------------------------
	.section .text.double_scale_by_power_of_two,"ax",%progbits
	.p2align 2
	.global double_scale_by_power_of_two
	.thumb_func
	.type double_scale_by_power_of_two, %function
double_scale_by_power_of_two:
	push	{r4, r5, r6, lr}
	bic	r3, r1, #0x80000000
	orrs	r3, r0
	beq.n	.L08007728			@ zero: unchanged
	ubfx	r5, r1, #20, #11		@ biased exponent
	movs	r4, #0
	rsbs	r5, r5, r4			@ -exponent
	sbc.w	r3, r4, r4
	asrs	r6, r2, #31
	subs	r5, r5, r2
	sbcs	r3, r6
	blt.n	.L0800772a			@ exponent + increment > 0
	movs	r0, #0
	mov	r1, r0
.L08007728:
	pop	{r4, r5, r6, pc}
.L0800772a:
	adds	r0, r4, r0
	adc.w	r1, r1, r2, lsl #20		@ add the increment to the exponent field
	pop	{r4, r5, r6, pc}
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ fn_08007734 - round a double to an integral value (as a double).
@ r0:r1 = double (low, high); returns a double in r0:r1.
@ Magnitude zero: returns the input. Biased exponent above 0x433: returns the
@ input. Exponent 0x3fe: when the fraction bits are not all zero it returns
@ r1 = sign | 0x3ff00000 (the word at 0x080077b8) and r0 = 0 (+-1.0), when
@ they are zero it returns 0. Exponent below 0x3fe: returns 0.
@ Exponent 0x3ff..0x433: r6 = 0x433 - exponent; the whole 64-bit pattern is
@ shifted left by 64 - r6 with shift_left_64 (giving the remainder bits
@ r7:r8) and right by r6 with shift_right_64, rounded with
@ round_half_even_increment_64 and shifted back left by r6 (tail branch to
@ shift_left_64).
@ ----------------------------------------------------------------------------
	.section .text.fn_08007734,"ax",%progbits
	.p2align 2
	.global fn_08007734
	.thumb_func
	.type fn_08007734, %function
fn_08007734:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r5, r0
	bic	r0, r1, #0x80000000
	mov	r4, r1
	orrs	r0, r5
	beq.n	.L08007758
	ubfx	r0, r4, #20, #11		@ biased exponent
	movw	r1, #0x433
	cmp	r0, r1
	ble.n	.L0800775c
	mov	r0, r5				@ exponent above 0x433: unchanged
	mov	r1, r4
.L08007754:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08007758:
	mov	r0, r5
	b.n	.L08007754
.L0800775c:
	movw	r1, #0x3fe
	cmp	r0, r1
	bgt.n	.L08007786
	blt.n	.L08007780
	lsl.w	r0, r4, #12
	orr.w	r0, r0, r5, lsr #20
	orrs.w	r1, r0, r5, lsl #12		@ fraction bits all zero?
	beq.n	.L08007780
	ldr	r0, .L080077b8
	and	r1, r4, #0x80000000
	orrs	r1, r0				@ sign | 0x3ff00000
	movs	r0, #0
	b.n	.L08007754
.L08007780:
	movs	r0, #0
	mov	r1, r0
	b.n	.L08007754
.L08007786:
	subw	r0, r0, #0x433
	rsbs	r6, r0, #0			@ 0x433 - exponent
	rsb.w	r2, r6, #0x40
	mov	r0, r5
	mov	r1, r4
	bl	shift_left_64
	mov	r7, r0
	mov	r8, r1
	mov	r0, r5
	mov	r1, r4
	mov	r2, r6
	bl	shift_right_64
	mov	r3, r8
	mov	r2, r7
	bl	round_half_even_increment_64
	mov	r2, r6
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	shift_left_64
.L080077b8:
	.word	0x3ff00000

@ ----------------------------------------------------------------------------
@ fn_080077bc - double to unsigned 64-bit integer (sign not applied).
@ r0:r1 = double; returns a 64-bit integer in r0:r1.
@ An exponent field below 0x3ff gives 0. Otherwise the 53-bit mantissa (high
@ word & 0xfffff | 0x100000) is shifted right by (0x433 - exponent) with
@ shift_right_64 when the exponent is up to 0x433, else shifted left by
@ (exponent - 0x433) with shift_left_64 (both by tail branch).
@ ----------------------------------------------------------------------------
	.section .text.fn_080077bc,"ax",%progbits
	.p2align 2
	.global fn_080077bc
	.thumb_func
	.type fn_080077bc, %function
fn_080077bc:
	ubfx	r2, r1, #20, #11		@ exponent field
	ubfx	r1, r1, #0, #20
	movw	r3, #0x3ff
	orr	r1, r1, #0x100000		@ mantissa with the hidden bit
	cmp	r2, r3
	bge.n	.L080077d6
	movs	r0, #0
	mov	r1, r0
	bx	lr
.L080077d6:
	movw	r3, #0x433
	cmp	r2, r3
	subw	r2, r2, #0x433
	bgt.n	.L080077e8
	rsbs	r2, r2, #0
	b.w	shift_right_64
.L080077e8:
	b.w	shift_left_64

@ ----------------------------------------------------------------------------
@ fn_080077ec - compare two 64-bit values, second against first.
@ r0:r1 = first signed 64-bit value, r2:r3 = second signed 64-bit value;
@ returns the flags of cmp r3, r1 / cmpeq r2, r0.
@ Each value that is not negative as a signed 64-bit value (subs/sbcs test at
@ 0x080077ee and 0x08007800) is replaced by 0x8000000000000000 minus the
@ value; negative values stay unchanged. Then the second is compared with the
@ first as a 64-bit value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080077ec,"ax",%progbits
	.p2align 2
	.global fn_080077ec
	.thumb_func
	.type fn_080077ec, %function
fn_080077ec:
	push	{r4, r5, lr}
	subs	r4, r0, #0
	sbcs	r4, r1, #0
	blt.n	.L08007800
	mov.w	r4, #0x80000000
	rsbs	r0, r0, #0
	sbc.w	r1, r4, r1
.L08007800:
	subs	r4, r2, #0
	sbcs	r4, r3, #0
	blt.n	.L08007814
	mov	r4, r3
	mov.w	r3, #0x80000000
	rsbs	r2, r2, #0
	sbc.w	r3, r3, r4
.L08007814:
	cmp	r3, r1
	it	eq
	cmpeq	r2, r0
	pop	{r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_0800781c - compare two 64-bit values, first against second.
@ r0:r1 = first signed 64-bit value, r2:r3 = second signed 64-bit value;
@ returns the flags of cmp r1, r3 / cmpeq r0, r2.
@ Each value that is not negative as a signed 64-bit value (subs/sbcs test at
@ 0x0800781e and 0x08007830) is replaced by 0x8000000000000000 minus the
@ value; negative values stay unchanged. Then the first is compared with the
@ second as a 64-bit value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800781c,"ax",%progbits
	.p2align 2
	.global fn_0800781c
	.thumb_func
	.type fn_0800781c, %function
fn_0800781c:
	push	{r4, r5, lr}
	subs	r4, r0, #0
	sbcs	r4, r1, #0
	blt.n	.L08007830
	mov.w	r4, #0x80000000
	rsbs	r0, r0, #0
	sbc.w	r1, r4, r1
.L08007830:
	subs	r4, r2, #0
	sbcs	r4, r3, #0
	blt.n	.L08007844
	mov	r4, r3
	mov.w	r3, #0x80000000
	rsbs	r2, r2, #0
	sbc.w	r3, r3, r4
.L08007844:
	cmp	r1, r3
	it	eq
	cmpeq	r0, r2
	pop	{r4, r5, pc}

@ ----------------------------------------------------------------------------
@ __scatterload - run the load/clear handlers of the region table.
@ No parameters, never returns. For r4 = 0x08051510 while r4 < 0x08051530
@ (literals at 0x08007868 and 0x0800786c) in steps of 0x10: loads r0, r1, r2
@ from the entry and calls its word at +12 with bit 0 set (blx). Afterwards it
@ branches with bl to fn_08006260.
@ ----------------------------------------------------------------------------
	.section .text.__scatterload,"ax",%progbits
	.global __scatterload
	.thumb_func
	.type __scatterload, %function
__scatterload:
	@ The two literal loads stay as .inst.n: this section (which also holds the
	@ following 64-bit shift routines) ends at 0x0800788e, not on a 4-byte
	@ boundary, so it cannot carry .p2align 2, and without it the assembler
	@ warns that the section is not aligned enough for PC-relative loads.
	.inst.n	0x4c06				@ ldr r4, .L08007868
	.inst.n	0x4d07				@ ldr r5, .L0800786c
	b.n	.L08007860
.L08007852:
	ldr	r0, [r4, #12]
	orr	r3, r0, #1			@ handler address with the Thumb bit
	ldm.w	r4, {r0, r1, r2}
	blx	r3
	adds	r4, #0x10
.L08007860:
	cmp	r4, r5
	bcc.n	.L08007852
	bl	fn_08006260
.L08007868:
	.word	d_08051510			@ region table start (literal at 0x08007868)
.L0800786c:
	.word	d_08051530			@ region table end (literal at 0x0800786c)

@ ----------------------------------------------------------------------------
@ shift_left_64 - logical left shift of a 64-bit value.
@ r0:r1 = value (low, high), r2 = shift count; returns the shifted value in
@ r0:r1. Counts below 32 combine both words; counts of 32 or more shift the
@ low word left by (count - 32) into the high word and give a low word of 0.
@ ----------------------------------------------------------------------------
	.global shift_left_64
	.thumb_func
	.type shift_left_64, %function
shift_left_64:
	cmp	r2, #0x20
	blt.n	.L0800787e
	subs	r2, #0x20
	lsl.w	r1, r0, r2
	movs	r0, #0
	bx	lr
.L0800787e:
	lsls	r1, r2
	rsb.w	r3, r2, #0x20
	lsr.w	r3, r0, r3
	orrs	r1, r3
	lsls	r0, r2
	bx	lr

@ ----------------------------------------------------------------------------
@ arithmetic_shift_right_64 - arithmetic right shift of a 64-bit value.
@ r0:r1 = value (low, high), r2 = shift count; returns the shifted value in
@ r0:r1. Counts below 32 combine both words; counts of 32 or more shift the
@ high word right (sign-extending) by (count - 32) into the low word and fill
@ the high word with its sign.
@ ----------------------------------------------------------------------------
	.section .text.arithmetic_shift_right_64,"ax",%progbits
	.global arithmetic_shift_right_64
	.thumb_func
	.type arithmetic_shift_right_64, %function
arithmetic_shift_right_64:
	cmp	r2, #0x20
	blt.n	.L080078a0
	asrs	r3, r1, #31
	subs	r2, #0x20
	asr.w	r0, r1, r2
	orr.w	r3, r3, r0, asr #31
	b.n	.L080078ae
.L080078a0:
	asr.w	r3, r1, r2
	lsrs	r0, r2
	rsb.w	r2, r2, #0x20
	lsls	r1, r2
	orrs	r0, r1
.L080078ae:
	mov	r1, r3
	bx	lr

@ ----------------------------------------------------------------------------
@ double_square_root - square root of a double.
@ r0:r1 = double; returns the root as a double in r0:r1.
@ Returns 0 in r0 and r1 when the value is not above 0 as a signed 64-bit
@ value (0 - value is computed by subs/sbcs; the branch to 0x080078c8 is
@ taken only for a positive value). Exponent field e: when e is even the
@ mantissa is shifted left once and e is decremented; the result exponent
@ term is 0x1ff + (e asr 1). Then 53 iterations (counter r8 from 0, loop while
@ r8 <= 52) of a restoring square-root bit loop using shift_right_64 and
@ 64-bit sums; the final rounding bits go to round_half_even_increment_64
@ (tail branch).
@ ----------------------------------------------------------------------------
	.section .text.double_square_root,"ax",%progbits
	.global double_square_root
	.thumb_func
	.type double_square_root, %function
double_square_root:
	push.w	{r4, r5, r6, r7, r8, r10, r11, lr}
	movs	r3, #0
	mov	r2, r3
	subs	r3, r3, r0
	sbcs	r2, r1				@ 0 - value
	blt.n	.L080078c8			@ value positive
	movs	r0, #0
	mov	r1, r0
	pop.w	{r4, r5, r6, r7, r8, r10, r11, pc}
.L080078c8:
	ubfx	r2, r1, #20, #11		@ exponent field
	ubfx	r1, r1, #0, #20
	orr	r5, r1, #0x100000		@ mantissa with the hidden bit
	mov.w	r11, #0
	lsls	r1, r2, #31
	bne.n	.L080078e2			@ odd exponent field
	adds	r0, r0, r0			@ even: mantissa << 1
	adcs	r5, r5
	.inst.n	0x1e52				@ subs r2, r2, #1
.L080078e2:
	movs	r7, #0
	mov	r4, r0
	movw	r1, #0x1ff
	mov	r0, r7
	add.w	r10, r1, r2, asr #1		@ result exponent term
	mov	r6, r7
	mov	r8, r0				@ iteration counter
.L080078f4:
	mov	r2, r0
	movs	r0, #0
	mov.w	r1, #0x100000
	bl	shift_right_64
	adds	r2, r0, r7
	adcs	r1, r6
	adds	r3, r7, r2
	adc.w	r0, r6, r1
	subs.w	r12, r4, r3
	sbcs.w	r12, r5, r0
	bcc.n	.L0800791e
	subs	r4, r4, r3
	sbc.w	r5, r5, r0
	mov	r7, r2
	mov	r6, r1
.L0800791e:
	adds	r4, r4, r4
	add.w	r0, r8, #1
	adcs	r5, r5
	mov	r8, r0
	cmp	r0, #0x34
	ble.n	.L080078f4			@ until 53 iterations are done
	adds	r1, r7, r7
	adc.w	r0, r6, r6
	subs	r1, r1, r4
	sbcs	r0, r5
	bcs.n	.L08007940
	mov.w	r2, #0xffffffff
	mov	r3, r2
	b.n	.L08007944
.L08007940:
	movs	r2, #0
	mov	r3, r2
.L08007944:
	adds.w	r0, r11, r7
	adc.w	r1, r6, r10, lsl #20		@ add the exponent
	pop.w	{r4, r5, r6, r7, r8, r10, r11, lr}
	b.w	round_half_even_increment_64

@ ----------------------------------------------------------------------------
@ __decompress - decompress a scatter-load region.
@ r0 = compressed source, r1 = destination, r2 = byte count of the output;
@ returns 0. Entered as handler word 0x08007954 (word at 0x0805151c) of the
@ scatter-load entry 0x08051510.
@ Reads a header byte per token: the low 3 bits are the literal count (a
@ following byte when the low 3 bits are 0), bits 4..7 are the length (a
@ following byte when 0); copies (count - 1) literal bytes, then bit 3 set
@ selects a back-reference copy of length + 2 bytes from the destination
@ pointer minus the next byte; bit 3 clear writes length zero bytes (not
@ length + 1). Repeats until the destination pointer reaches r1 + r2.
@ __decompress_addr marks the same address as an even value for the region
@ table. Followed by two bytes of zero padding.
@ ----------------------------------------------------------------------------
	.section .text.__decompress,"ax",%progbits
	.p2align 2
	.global __decompress
	.thumb_func
	.type __decompress, %function
__decompress:
	.global __decompress_addr
__decompress_addr:
	push	{r4, r5, r6, lr}
	adds	r4, r1, r2			@ end of the output
.L08007958:
	ldrb.w	r5, [r0], #1			@ header byte
	ands	r3, r5, #7			@ literal count
	bne.n	.L08007966
	ldrb.w	r3, [r0], #1
.L08007966:
	asrs	r2, r5, #4			@ length
	bne.n	.L08007978
	ldrb.w	r2, [r0], #1
	b.n	.L08007978
.L08007970:
	ldrb.w	r6, [r0], #1			@ copy one literal byte
	strb.w	r6, [r1], #1
.L08007978:
	.inst.n	0x1e5b				@ subs r3, r3, #1
	bne.n	.L08007970
	lsls	r3, r5, #28
	bmi.n	.L0800798c			@ bit 3 set: back-reference
	movs	r3, #0
.L08007982:
	.inst.n	0x1e52				@ subs r2, r2, #1
	bmi.n	.L080079a2
	strb.w	r3, [r1], #1			@ write a zero byte
	b.n	.L08007982
.L0800798c:
	ldrb.w	r3, [r0], #1			@ back-reference distance
	subs	r3, r1, r3
	.inst.n	0x1c92				@ adds r2, r2, #2
	b.n	.L0800799e
.L08007996:
	ldrb.w	r5, [r3], #1			@ copy one byte from earlier output
	strb.w	r5, [r1], #1
.L0800799e:
	.inst.n	0x1e52				@ subs r2, r2, #1
	bpl.n	.L08007996
.L080079a2:
	cmp	r1, r4
	bcc.n	.L08007958			@ until the output is complete
	movs	r0, #0
	pop	{r4, r5, r6, pc}
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ fn_0801031c - formatted output through fn_08012d58 into the sink at
@ 0x20000574.
@ r0 = format string, r1..r3 = arguments.
@ Stores r1..r3 on the stack and calls fn_08012d58(r0, argument list,
@ 0x20000574, 0x0801b011). Followed by two bytes of zero padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801031c,"ax",%progbits
	.p2align 2
	.global fn_0801031c
	.thumb_func
	.type fn_0801031c, %function
fn_0801031c:
	push	{r0, r1, r2, r3}
	ldr	r3, .L08010334
	push	{r4, lr}
	add	r1, sp, #12			@ argument list
	ldr	r2, .L08010338
	ldr	r0, [sp, #8]
	bl	fn_08012d58
	pop	{r4}
	ldr.w	pc, [sp], #0x14
	.short	0x0000				@ padding
.L08010334:
	.word	fn_0801b010			@ function pointer
.L08010338:
	.word	0x20000574

@ ----------------------------------------------------------------------------
@ fn_0801033c - formatted output into a size-limited buffer.
@ r0 = buffer, r1 = buffer size, r2 = format string, r3 = argument.
@ Limit = 0 when r1 is 0, otherwise r1 - 1. Calls fn_08012d58(r2, argument
@ list, {buffer, limit}, 0x0801345f) and, when r1 is non-zero, stores a 0
@ byte at the pointer left by the call.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801033c,"ax",%progbits
	.p2align 2
	.global fn_0801033c
	.thumb_func
	.type fn_0801033c, %function
fn_0801033c:
	push	{r0, r1, r2, r3}
	push	{r2, r3, r4, r5, r6, lr}
	movs	r4, r1
	add	r5, sp, #0x24			@ argument list
	beq.n	.L0801034a
	subs	r1, r4, #1
	b.n	.L0801034c
.L0801034a:
	movs	r1, #0
.L0801034c:
	strd	r0, r1, [sp]			@ context {pointer, limit}
	ldr	r3, .L0801036c
	mov	r2, sp
	mov	r1, r5
	ldr	r0, [sp, #0x20]
	bl	fn_08012d58
	cmp	r4, #0
	beq.n	.L08010366
	ldr	r2, [sp]
	movs	r1, #0
	strb	r1, [r2]			@ terminating zero byte
.L08010366:
	pop	{r2, r3, r4, r5, r6}
	ldr.w	pc, [sp], #0x14
.L0801036c:
	.word	store_byte_advance_pointer_if_space_left	@ function pointer

@ ----------------------------------------------------------------------------
@ fn_08010370 - formatted output through store_byte_advance_pointer.
@ Parameters r0..r3 (spilled to a 16-byte stack block).
@ Calls fn_08012d58 with r0 = param_2 (r1), r1 = address of the stack slot
@ holding param_3 (argument list), r2 = address of the slot holding param_1
@ (context), r3 = store_byte_advance_pointer (output callback). Then calls
@ store_byte_advance_pointer with r0 = 0 and r1 = the context address.
@ Returns the fn_08012d58 result. Followed by two bytes of zero padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08010370,"ax",%progbits
	.p2align 2
	.global fn_08010370
	.thumb_func
	.type fn_08010370, %function
fn_08010370:
	push	{r0, r1, r2, r3}
	ldr	r3, .L08010394
	push	{r4, lr}
	add	r1, sp, #16			@ argument list
	add	r2, sp, #8			@ context
	ldr	r0, [sp, #12]
	bl	fn_08012d58
	mov	r4, r0
	add	r1, sp, #8
	movs	r0, #0
	bl	store_byte_advance_pointer
	mov	r0, r4
	pop	{r4}
	ldr.w	pc, [sp], #0x14
	.short	0x0000				@ padding
.L08010394:
	.word	store_byte_advance_pointer	@ function pointer

@ ----------------------------------------------------------------------------
@ fn_08010398 - formatted output into a size-limited buffer (argument list
@ passed in r3).
@ r0 = buffer pointer, r1 = size, r2 = format, r3 = argument list.
@ Local context = {pointer = buffer, count = size - 1, or 0 when size is 0}.
@ Calls fn_08012d58 with r3 = store_byte_advance_pointer_if_space_left as the
@ output callback. When size is non-zero stores byte 0 at the final pointer.
@ Followed by two bytes of zero padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08010398,"ax",%progbits
	.p2align 2
	.global fn_08010398
	.thumb_func
	.type fn_08010398, %function
fn_08010398:
	push	{r2, r3, r4, r5, r6, lr}
	movs	r4, r1
	mov	r5, r3
	mov	r6, r2
	mov	r1, r0
	beq.n	.L080103a8
	subs	r0, r4, #1
	b.n	.L080103aa
.L080103a8:
	movs	r0, #0
.L080103aa:
	strd	r1, r0, [sp]			@ context {pointer, limit}
	ldr	r3, .L080103c8
	mov	r2, sp
	mov	r1, r5
	mov	r0, r6
	bl	fn_08012d58
	cmp	r4, #0
	beq.n	.L080103c4
	ldr	r2, [sp]
	movs	r1, #0
	strb	r1, [r2]			@ terminating zero byte
.L080103c4:
	pop	{r2, r3, r4, r5, r6, pc}
	.short	0x0000				@ padding
.L080103c8:
	.word	store_byte_advance_pointer_if_space_left	@ function pointer

@ ----------------------------------------------------------------------------
@ classify_double - classify a double.
@ r0 = low word, r1 = high word; returns a bit mask in r0: 4 when the low word
@ is non-zero or high & 0xfffff is non-zero; bit 0 when
@ (high & 0x7fffffff) >> 20 is non-zero; bit 1 (2) when that exponent field
@ equals 0x7ff; a result of exactly 1 is returned as 5.
@ ----------------------------------------------------------------------------
	.section .text.classify_double,"ax",%progbits
	.p2align 2
	.global classify_double
	.thumb_func
	.type classify_double, %function
classify_double:
	push	{r0, r1}
	ldr	r0, [sp, #4]
	lsls	r1, r0, #1			@ high word without the sign
	ldr	r0, [sp]
	orrs.w	r0, r0, r1, lsl #11
	it	ne
	movne	r0, #4
	lsrs	r2, r1, #21
	it	ne
	orrne	r0, r0, #1
	movw	r2, #0x7ff
	cmp.w	r2, r1, lsr #21
	it	eq
	orreq	r0, r0, #2
	cmp	r0, #1
	it	eq
	moveq	r0, #5
	add	sp, #8
	bx	lr

@ ----------------------------------------------------------------------------
@ classify_float - classify a float.
@ r0 = float bits; returns a bit mask in r0: 4 when bits & 0x7fffff is
@ non-zero; bit 0 when (bits & 0x7fffffff) >> 23 is non-zero; bit 1 (2) when
@ the exponent field is 0xff; a result of exactly 1 is returned as 5.
@ Followed by six bytes of zero padding.
@ ----------------------------------------------------------------------------
	.section .text.classify_float,"ax",%progbits
	.p2align 2
	.global classify_float
	.thumb_func
	.type classify_float, %function
classify_float:
	lsls	r1, r0, #1
	lsls	r0, r1, #8
	it	ne
	movne	r0, #4
	lsrs	r2, r1, #24
	it	ne
	orrne	r0, r0, #1
	mov.w	r2, #0xff000000
	bics.w	r1, r2, r1
	it	eq
	orreq	r0, r0, #2
	cmp	r0, #1
	it	eq
	moveq	r0, #5
	bx	lr
	.short	0x0000				@ padding
	.short	0x0000				@ padding
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ atan_f64 - arc tangent of a double, in radians.
@ Parameter: double x in d0 (stored at [sp + 24]; its high word is read from
@ [sp + 28] into r5); returns the double in d0. Body 0x08010428..0x08010695;
@ literal words and doubles at 0x08010698..0x080106ef; pc-relative distances
@ at 0x080106f0..0x080106fc.
@ ax = r5 & 0x7fffffff (r4); the comparisons are signed on ax.
@ ax >= 0x44100000: when ax > 0x7ff00000, or ax = 0x7ff00000 with a non-zero
@ low word, it restores the registers and tail-calls fn_08011a38 with d0 = x;
@ otherwise it returns +1.5707963267948966 (0x3ff921fb54442d18, literal at
@ 0x080106a0) when r5 > 0 (signed), else -1.5707963267948966 (0x080106a8).
@ ax < 0x3e200000: calls classify_double(low, high), calls fn_08011aa0 when the
@ result is 4, then reloads d0 from [sp + 24] and returns x.
@ 0x3e200000 <= ax < 0x3fdc0000: r4 = -1 and t = x.
@ ax >= 0x3fdc0000: t = |x| (clear_sign_bit_64, stored back at [sp + 24]),
@ d8 = 1.0 (0x080106c0): ax < 0x3fe60000: r4 = 0, t = (2t - 1) / (t + 2) with
@ 2.0 at 0x080106d0; ax < 0x3ff30000: r4 = 1, t = (t - 1) / (t + 1);
@ ax < 0x40038000: r4 = 2, t = (t - 1.5) / (1 + 1.5 t) with 1.5 at
@ 0x080106e0; otherwise r4 = 3, t = -1.0 / t (-1.0 at 0x080106e8). The
@ arithmetic uses double_add, double_subtract, double_multiply and
@ double_divide.
@ Common part (0x08010596): z = t*t, w = z*z, p = horner_poly_f64(0x08051078,
@ 6, w), q = horner_poly_f64(0x08051050, 5, w), s = z*p + w*q.
@ r4 < 0: returns t - t*s (double_reverse_subtract at 0x0801061e).
@ r4 >= 0: f = T10[r4] - ((t*s - T30[r4]) - t), T10 = doubles at 0x08051010,
@ T30 = doubles at 0x08051030 (index r4, 8 bytes each); the result has its sign
@ bit flipped (0x0801068c) when r5 is negative (cmp r5, #0 at 0x0801067c).
@ The table values and intervals (0.4636476090008061, 0.7853981633974483,
@ 0.982793723247329, 1.5707963267948966) correspond to atan(0.5), atan(1),
@ atan(1.5) and pi/2.
@ ----------------------------------------------------------------------------
	.section .text.atan_f64,"ax",%progbits
	.p2align 2
	.global atan_f64
	.thumb_func
	.type atan_f64, %function
atan_f64:
	push	{r4, r5, r6, lr}
	ldr	r0, .L08010698
	vpush	{d0}				@ x at [sp + 24] after the next push
	vpush	{d8, d9, d10}
	ldr	r5, [sp, #0x1c]			@ high word of x
	bic	r4, r5, #0x80000000		@ ax
	cmp	r0, r4
	bgt.n	.L08010470			@ ax < 0x44100000
	ldr	r0, .L0801069c
	cmp	r4, r0
	bgt.n	.L0801044a			@ ax > 0x7ff00000
	bne.n	.L0801045c
	ldr	r0, [sp, #0x18]
	cbz	r0, .L0801045c			@ low word zero: infinity
.L0801044a:
	vldr	d0, [sp, #0x18]
	vpop	{d8, d9, d10}
	add	sp, #8
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08011a38
.L0801045c:
	cmp	r5, #0
	ite	gt
	vldrgt	d0, .L080106a0			@ +pi/2
	vldrle	d0, .L080106a8			@ -pi/2
	vpop	{d8, d9, d10}
	add	sp, #8
	pop	{r4, r5, r6, pc}
.L08010470:
	ldr	r0, .L080106b0
	cmp	r0, r4
	ble.n	.L080104a2			@ ax >= 0x3fdc0000
	ldr	r0, .L080106b4
	cmp	r0, r4
	it	le
	movle.w	r4, #0xffffffff			@ r4 = -1
	ble.n	.L08010534			@ 0x3e200000 <= ax: t = x
	vldr	d0, [sp, #0x18]
	vmov	r0, r1, d0
	bl	classify_double
	cmp	r0, #4
	it	eq
	bleq	fn_08011aa0
	vldr	d0, [sp, #0x18]
.L0801049a:
	vpop	{d8, d9, d10}
	add	sp, #8
	pop	{r4, r5, r6, pc}
.L080104a2:
	vldr	d0, [sp, #0x18]
	vmov	r0, r1, d0
	bl	clear_sign_bit_64
	strd	r0, r1, [sp, #0x18]		@ t = |x|
	ldr	r0, .L080106b8
	vldr	d8, .L080106c0			@ 1.0
	cmp	r0, r4
	ble.n	.L08010536
	ldr	r0, .L080106c8
	cmp	r0, r4
	ble.n	.L08010502
	movs	r4, #0
	vldr	d10, .L080106d0			@ 2.0
	vldr	d0, [sp, #0x18]
	vmov	r2, r3, d10
	vmov	r0, r1, d0
	bl	double_add			@ t + 2
	vldr	d0, [sp, #0x18]
	vmov	d9, r0, r1
	vmov	r2, r3, d10
	vmov	r0, r1, d0
	bl	double_multiply			@ 2t
	vmov	r2, r3, d8
	bl	double_subtract			@ 2t - 1
	vmov	r2, r3, d9
	bl	double_divide
	strd	r0, r1, [sp, #0x18]
	b.n	.L08010596
.L08010502:
	vldr	d0, [sp, #0x18]
	movs	r4, #1
	vmov	r2, r3, d8
	vmov	r0, r1, d0
	bl	double_add			@ t + 1
	vldr	d0, [sp, #0x18]
	vmov	d9, r0, r1
	vmov	r2, r3, d8
	vmov	r0, r1, d0
	bl	double_subtract			@ t - 1
	vmov	r2, r3, d9
	bl	double_divide
	strd	r0, r1, [sp, #0x18]
.L08010534:
	b.n	.L08010596
.L08010536:
	ldr	r0, .L080106d8
	cmp	r0, r4
	ble.n	.L0801057c
	movs	r4, #2
	vldr	d9, .L080106e0			@ 1.5
	vldr	d0, [sp, #0x18]
	vmov	r2, r3, d9
	vmov	r0, r1, d0
	bl	double_multiply			@ 1.5 t
	vmov	r2, r3, d8
	bl	double_add			@ 1 + 1.5 t
	vldr	d0, [sp, #0x18]
	vmov	d8, r0, r1
	vmov	r2, r3, d9
	vmov	r0, r1, d0
	bl	double_subtract			@ t - 1.5
	vmov	r2, r3, d8
	bl	double_divide
	strd	r0, r1, [sp, #0x18]
	b.n	.L08010596
.L0801057c:
	vldr	d0, [sp, #0x18]
	movs	r4, #3
	vmov	r2, r3, d0
	vldr	d0, .L080106e8			@ -1.0
	vmov	r0, r1, d0
	bl	double_divide			@ -1.0 / t
	strd	r0, r1, [sp, #0x18]
.L08010596:
	vldr	d0, [sp, #0x18]
	vmov	r2, r3, d0
	vmov	r0, r1, d0
	bl	double_multiply			@ z = t*t
	vmov	d8, r0, r1
	vmov	r2, r3, d8
	bl	double_multiply			@ w = z*z
	vmov	d9, r0, r1
	ldr	r0, .L080106f0
	movs	r1, #6
	vmov.f32	s0, s18
	vmov.f32	s1, s19
.L080105c2:
	add	r0, pc				@ r0 = 0x08051078
	bl	horner_poly_f64
	vmov	r2, r3, d8
	vmov	r0, r1, d0
	bl	double_multiply			@ z * p
	vmov	d8, r0, r1
	ldr	r0, .L080106f4
	vmov.f32	s0, s18
	vmov.f32	s1, s19
	movs	r1, #5
.L080105e4:
	add	r0, pc				@ r0 = 0x08051050
	bl	horner_poly_f64
	vmov	r2, r3, d9
	vmov	r0, r1, d0
	bl	double_multiply			@ q * w
	vmov	d0, r0, r1
	vmov	r0, r1, d8
	vmov	r2, r3, d0
	cmp	r4, #0
	bge.n	.L08010624
	bl	double_add			@ s = z*p + w*q
	vldr	d1, [sp, #0x18]
	vmov	r2, r3, d1
	bl	double_multiply			@ t * s
	vldr	d1, [sp, #0x18]
	vmov	r2, r3, d1
	bl	double_reverse_subtract		@ t - t*s
	b.n	.L08010690
.L08010624:
	bl	double_add			@ s = z*p + w*q
	vldr	d1, [sp, #0x18]
	vmov	r2, r3, d1
	bl	double_multiply			@ t * s
	vmov	d0, r0, r1
	ldr	r0, .L080106f8
.L0801063a:
	add	r0, pc				@ r0 = 0x08051030
	add.w	r0, r0, r4, lsl #3
	vldr	d1, [r0]			@ T30[r4]
	vmov	r0, r1, d0
	vmov	r2, r3, d1
	bl	double_subtract
	vldr	d1, [sp, #0x18]
	vmov	r2, r3, d1
	bl	double_subtract
	vmov	d0, r0, r1
	ldr	r0, .L080106fc
.L08010662:
	add	r0, pc				@ r0 = 0x08051010
	add.w	r0, r0, r4, lsl #3
	vldr	d1, [r0]			@ T10[r4]
	vmov	r0, r1, d0
	vmov	r2, r3, d1
	bl	double_reverse_subtract
	vmov	d0, r0, r1
	cmp	r5, #0
	ittt	ge
	vpopge	{d8, d9, d10}
	addge	sp, #8
	popge	{r4, r5, r6, pc}
	vmov	r0, r1, d0
	eor	r1, r1, #0x80000000		@ negate the result for negative x
.L08010690:
	vmov	d0, r0, r1
	b.n	.L0801049a
	.short	0x0000				@ padding
.L08010698:
	.word	0x44100000
.L0801069c:
	.word	0x7ff00000
.L080106a0:
	.word	0x54442d18			@ +1.5707963267948966 (0x3ff921fb54442d18)
	.word	0x3ff921fb
.L080106a8:
	.word	0x54442d18			@ -1.5707963267948966 (0xbff921fb54442d18)
	.word	0xbff921fb
.L080106b0:
	.word	0x3fdc0000
.L080106b4:
	.word	0x3e200000
.L080106b8:
	.word	0x3ff30000
	.word	0x00000000			@ padding
.L080106c0:
	.word	0x00000000			@ 1.0 (0x3ff0000000000000)
	.word	0x3ff00000
.L080106c8:
	.word	0x3fe60000
	.word	0x00000000			@ padding
.L080106d0:
	.word	0x00000000			@ 2.0 (0x4000000000000000)
	.word	0x40000000
.L080106d8:
	.word	0x40038000
	.word	0x00000000			@ padding
.L080106e0:
	.word	0x00000000			@ 1.5 (0x3ff8000000000000)
	.word	0x3ff80000
.L080106e8:
	.word	0x00000000			@ -1.0 (0xbff0000000000000)
	.word	0xbff00000
.L080106f0:
	.word	d_08051078 - (.L080105c2 + 4)	@ distance for the add r0, pc at 0x080105c2
.L080106f4:
	.word	d_08051050 - (.L080105e4 + 4)	@ distance for the add r0, pc at 0x080105e4
.L080106f8:
	.word	d_08051030 - (.L0801063a + 4)	@ distance for the add r0, pc at 0x0801063a
.L080106fc:
	.word	d_08051010 - (.L08010662 + 4)	@ distance for the add r0, pc at 0x08010662
