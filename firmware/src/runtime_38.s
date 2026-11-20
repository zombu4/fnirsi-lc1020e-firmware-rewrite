@ runtime_38.s - runtime support: float/double helpers (round, sine, polynomial, NaN/overflow producers), word copy/fill, double to decimal digits, sqrt wrapper
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080116a0 - double rounding helper.
@ Parameter: double in d0 (stored at [sp+0x30] after the pushes); returns the
@ double in d0.
@ r = fn_08007734(d0); difference = double_subtract(d0, r).
@ The difference is compared with -0.5 (0xbfe00000 high word) and with 0.5
@ (0x3fe00000 high word) through fn_080077ec and fn_0800781c; depending on the
@ outcome 1.0 (0x3ff00000 high word) is added to r (double_add) or subtracted
@ from r (double_subtract), or r is left unchanged.
@ The sign of d0 (bit 63, tested in the high word at [sp+0x34]) selects which
@ comparison order is used. The result sign bit is copied from d0 by bfi
@ (bits 0..30 of the high word come from the result, bit 31 from the argument).
@ Literal doubles: 1.0 at 08011768, 0.5 at 08011770, -0.5 at 08011778.
@ ----------------------------------------------------------------------------
	.section .text.fn_080116a0,"ax",%progbits
	.p2align 2
	.global fn_080116a0
	.thumb_func
	.type fn_080116a0, %function
fn_080116a0:
	push	{r4, lr}
	vpush	{d0}
	vpush	{d8, d9, d10, d11}
	sub	sp, #0x10
	vldr	d0, [sp, #0x30]
	vmov	r0, r1, d0
	bl	fn_08007734
	vmov	d8, r0, r1
	vldr	d0, [sp, #0x30]
	vmov	r2, r3, d8
	vmov	r0, r1, d0
	bl	double_subtract
	vmov	d9, r0, r1
	ldr	r0, [sp, #0x34]		@ high word of the argument
	vldr	d0, .L08011778		@ -0.5
	tst.w	r0, #0x80000000		@ sign of the argument
	vmov	r2, r3, d0
	vmov	r0, r1, d9
	vldr	d10, .L08011768		@ 1.0
	vldr	d11, .L08011770		@ 0.5
	beq.n	.L0801170a
	bl	fn_080077ec
	bls.n	.L08011710
	vmov	r2, r3, d11
	vmov	r0, r1, d9
	bl	fn_0800781c
	bcs.n	.L0801173a
	b.n	.L0801172c
	nop				@ padding
.L08011704:
	vmov	d8, r0, r1
	b.n	.L0801173a
.L0801170a:
	bl	fn_080077ec
	bcs.n	.L0801171e
.L08011710:
	vmov	r2, r3, d10
	vmov	r0, r1, d8
	bl	double_subtract
	b.n	.L08011704
.L0801171e:
	vmov	r2, r3, d11
	vmov	r0, r1, d9
	bl	fn_0800781c
	bhi.n	.L0801173a
.L0801172c:
	vmov	r2, r3, d10
	vmov	r0, r1, d8
	bl	double_add
	b.n	.L08011704
.L0801173a:
	vstr	d8, [sp, #0x8]		@ result
	vldr	d0, [sp, #0x30]
	vmov	r1, s17			@ high word of the result
	vmov	r0, s1			@ high word of the argument
	vstr	d0, [sp]
	bfi	r0, r1, #0, #31		@ result bits 0..30, argument sign bit
	str	r0, [sp, #0xc]
	vldr	d0, [sp, #0x8]
	add	sp, #0x10
	vpop	{d8, d9, d10, d11}
	add	sp, #0x8
	pop	{r4, pc}
	.short	0x0000			@ padding
	.short	0x0000			@ padding
	.short	0x0000			@ padding
.L08011768:
	.word	0x00000000, 0x3ff00000	@ 1.0
.L08011770:
	.word	0x00000000, 0x3fe00000	@ 0.5
.L08011778:
	.word	0x00000000, 0xbfe00000	@ -0.5

@ ----------------------------------------------------------------------------
@ fn_08011780 - single precision sine (parameter and result float in s0).
@ Same range reduction as the function at 08010900: tests (bits << 1) against
@ 0x7e921fb6 and 0x73000000, (bits & 0x7fffffff) against 0x46490e49; factor
@ 0.63661975 with 8388608.0 added and subtracted (sign selects the order) to
@ round to an integer; subtraction constants 1.5703125, 0.0004837513,
@ 7.5495336e-08 and 2.563344e-12 (literals at 080118f4..08011900); inputs of
@ large magnitude go through fn_08011ae8.
@ The quadrant (0..3) is kept at [sp].
@ Quadrant bit 0 clear selects the polynomial 0.008331979, -0.00019495636,
@ -0.16666651; bit 0 set selects -0.0013597823, 0.041656293, -0.49999896, 1.0.
@ Quadrant bit 1 negates the result. The instruction at 080117e4 (pop {pc},
@ conditional) is one of the function returns.
@ A negative quadrant value (input not finite or subnormal range): infinity
@ calls set_word_20000578(1) and returns through fn_08011ac8; NaN returns
@ through float_add_to_self; a subnormal input calls classify_float and
@ fn_08011ad8 when the class is 4, and returns the input.
@ ----------------------------------------------------------------------------
	.section .text.fn_08011780,"ax",%progbits
	.p2align 2
	.global fn_08011780
	.thumb_func
	.type fn_08011780, %function
fn_08011780:
	push	{lr}
	vmov	r1, s0
	vpush	{d8}
	sub	sp, #0x4
	ldr	r2, .L080118d8
	mov	r0, sp
	cmp.w	r2, r1, lsl #1
	bls.n	.L080117f4
	mov.w	r0, #0x73000000
	cmp.w	r0, r1, lsl #1
	ite	ls
	movls	r0, #0
	movhi.w	r0, #0xffffffff
	str	r0, [sp]		@ quadrant
.L080117a8:
	ldr	r0, [sp]
	vmov.f32	s16, s0
	cmp	r0, #0
	blt.n	.L08011888
	tst.w	r0, #1
	beq.n	.L08011850
	vmul.f32	s1, s16, s16
	vldr	s2, .L080118dc
	vldr	s0, .L080118e0
	vmla.f32	s0, s1, s2
	vldr	s2, .L080118e4
	tst.w	r0, #2
	vmla.f32	s2, s1, s0
	vmov.f32	s0, #1.0
	vmla.f32	s0, s1, s2
	ittt	eq
	addeq	sp, #4
	vpopeq	{d8}
	popeq	{pc}
	nop
.L080117e8:
	add	sp, #0x4
	vneg.f32	s0, s0
	vpop	{d8}
	pop	{pc}
.L080117f4:
	ldr	r3, .L080118e8
	bic	r2, r1, #0x80000000
	cmp	r3, r2
	bls.n	.L08011882
	tst.w	r1, #0x80000000
	vldr	s1, .L080118ec
	vmul.f32	s2, s0, s1
	vldr	s1, .L080118f0
	ittee	ne
	vsubne.f32	s2, s2, s1
	vaddne.f32	s1, s2, s1
	vaddeq.f32	s2, s2, s1
	vsubeq.f32	s1, s2, s1
	vcvt.s32.f32	s2, s1
	vmov	r0, s2
	vldr	s2, .L080118f4
	and	r0, r0, #3
	vmls.f32	s0, s1, s2
	vldr	s2, .L080118f8
	str	r0, [sp]
	vmls.f32	s0, s1, s2
	vldr	s2, .L080118fc
	vmls.f32	s0, s1, s2
	vldr	s2, .L08011900
	vmls.f32	s0, s1, s2
	b.n	.L080117a8
.L08011850:
	vmul.f32	s0, s16, s16
	vldr	s2, .L08011904
	vldr	s1, .L08011908
	tst.w	r0, #2
	vmls.f32	s1, s0, s2
	vldr	s2, .L0801190c
	vmla.f32	s2, s0, s1
	vmul.f32	s1, s2, s0
	vmov.f32	s0, s16
	vmla.f32	s0, s16, s1
	bne.n	.L080117e8
	add	sp, #0x4
	vpop	{d8}
	pop	{pc}
.L08011882:
	bl	fn_08011ae8
	b.n	.L080117a8
.L08011888:
	vmov	r0, s16
	lsls	r0, r0, #1
	cmp.w	r0, #0xff000000
	bcs.n	.L080118b0
	vmov	r0, s16
	bl	classify_float
	cmp	r0, #4
	it	eq
	bleq	fn_08011ad8
	vmov.f32	s0, s16
	add	sp, #0x4
	vpop	{d8}
	pop	{pc}
.L080118b0:
	bne.n	.L080118c6
	movs	r0, #1
	bl	set_word_20000578
	add	sp, #0x4
	vpop	{d8}
	pop.w	{lr}
	b.w	fn_08011ac8
.L080118c6:
	add	sp, #0x4
	vmov.f32	s0, s16
	vpop	{d8}
	pop.w	{lr}
	b.w	float_add_to_self
.L080118d8:
	.word	0x7e921fb6
.L080118dc:
	.word	0xbab23ab9
.L080118e0:
	.word	0x3d2a9fca
.L080118e4:
	.word	0xbeffffdd
.L080118e8:
	.word	0x46490e49
.L080118ec:
	.word	0x3f22f983
.L080118f0:
	.word	0x4b000000
.L080118f4:
	.word	0x3fc90000
.L080118f8:
	.word	0x39fda000
.L080118fc:
	.word	0x33a22000
.L08011900:
	.word	0x2c34611a
.L08011904:
	.word	0x394c6d33
.L08011908:
	.word	0x3c0882da
.L0801190c:
	.word	0xbe2aaaa0

@ ----------------------------------------------------------------------------
@ horner_poly_f64 - evaluates a polynomial of doubles by Horner's scheme.
@ Parameters: pointer to the coefficient doubles (r0), count (r1), x in d0.
@ Starts with the coefficient at index count-1; multiplies by x with
@ double_multiply and adds the next lower coefficient with double_add, down to
@ index 0. The loop runs while (index & 0xfffffff9) != 0 (it stops at index 0,
@ 2, 4 or 6); the remaining steps are unrolled below the loop (compare with 2,
@ 4, 6). Returns the double result in d0.
@ ----------------------------------------------------------------------------
	.section .text.horner_poly_f64,"ax",%progbits
	.p2align 2
	.global horner_poly_f64
	.thumb_func
	.type horner_poly_f64, %function
horner_poly_f64:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	vpush	{d8}
	subs	r5, r1, #1		@ index = count - 1
	add.w	r0, r0, r5, lsl #3
	vmov.f32	s16, s0		@ d8 = x
	vmov.f32	s17, s1
	vldr	d0, [r0]		@ highest coefficient
	bics	r0, r5, #6
	beq.n	.L08011960
.L08011930:
	vmov	r2, r3, d8
	vmov	r0, r1, d0
	bl	double_multiply
	vmov	d0, r0, r1
	.inst.n	0x1e6d			@ subs r5, r5, #1
	add.w	r0, r4, r5, lsl #3
	vldr	d1, [r0]
	vmov	r0, r1, d0
	vmov	r2, r3, d1
	bl	double_add
	vmov	d0, r0, r1
	bics	r0, r5, #6
	bne.n	.L08011930
.L08011960:
	cmp	r5, #2
	beq.n	.L080119d2
	cmp	r5, #4
	beq.n	.L080119a2
	cmp	r5, #6
	itt	ne
	vpopne	{d8}
	popne	{r4, r5, r6, pc}
	vmov	r2, r3, d8
	vmov	r0, r1, d0
	bl	double_multiply
	vldr	d1, [r4, #0x28]		@ coefficient 5
	vmov	r2, r3, d1
	bl	double_add
	vmov	r2, r3, d8
	bl	double_multiply
	vldr	d1, [r4, #0x20]		@ coefficient 4
	vmov	r2, r3, d1
	bl	double_add
	vmov	d0, r0, r1
.L080119a2:
	vmov	r2, r3, d8
	vmov	r0, r1, d0
	bl	double_multiply
	vldr	d1, [r4, #0x18]		@ coefficient 3
	vmov	r2, r3, d1
	bl	double_add
	vmov	r2, r3, d8
	bl	double_multiply
	vldr	d0, [r4, #0x10]		@ coefficient 2
	vmov	r2, r3, d0
	bl	double_add
	vmov	d0, r0, r1
.L080119d2:
	vmov	r2, r3, d8
	vmov	r0, r1, d0
	bl	double_multiply
	vldr	d1, [r4, #0x8]		@ coefficient 1
	vmov	r2, r3, d1
	bl	double_add
	vmov	r2, r3, d8
	bl	double_multiply
	vldr	d1, [r4]		@ coefficient 0
	vmov	r2, r3, d1
	bl	double_add
	vpop	{d8}
	vmov	d0, r0, r1
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08011a08 - no parameters; returns double_divide(0.0, 1.0 (0x3ff00000
@ high word)) in d0. The literal at 08011a28 is 0.0 (loaded into r2:r3), the
@ literal at 08011a30 is 1.0 (loaded into r0:r1).
@ ----------------------------------------------------------------------------
	.section .text.fn_08011a08,"ax",%progbits
	.p2align 2
	.global fn_08011a08
	.thumb_func
	.type fn_08011a08, %function
fn_08011a08:
	vldr	d0, .L08011a28
	push	{r4, lr}
	vmov	r2, r3, d0
	vldr	d0, .L08011a30
	vmov	r0, r1, d0
	bl	double_divide
	vmov	d0, r0, r1
	pop	{r4, pc}
	.word	0x00000000		@ padding
.L08011a28:
	.word	0x00000000, 0x00000000	@ 0.0
.L08011a30:
	.word	0x00000000, 0x3ff00000	@ 1.0

@ ----------------------------------------------------------------------------
@ fn_08011a38 - parameter: double in d0; returns a double in d0.
@ Moves d0 into r2:r3 and into r0:r1, calls double_add(r0:r1, r2:r3) (the same
@ value as both operands), moves the result r0:r1 back into d0 and returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_08011a38,"ax",%progbits
	.p2align 2
	.global fn_08011a38
	.thumb_func
	.type fn_08011a38, %function
fn_08011a38:
	push	{r4, lr}
	vmov	r2, r3, d0
	vmov	r0, r1, d0
	bl	double_add
	vmov	d0, r0, r1
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08011a4c - parameters: doubles d0 and d1; returns a double in d0.
@ Calls double_add with r0:r1 = d0 and r2:r3 = d1 and returns the result in d0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08011a4c,"ax",%progbits
	.p2align 2
	.global fn_08011a4c
	.thumb_func
	.type fn_08011a4c, %function
fn_08011a4c:
	push	{r4, lr}
	vmov	r2, r3, d1
	vmov	r0, r1, d0
	bl	double_add
	vmov	d0, r0, r1
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ divide_zero_by_zero_double - no parameters; returns the double result in d0.
@ Loads 0.0 (literal at 08011a78) into d0, copies it to r2:r3 and r0:r1, calls
@ double_divide (0.0 / 0.0), moves r0:r1 into d0 and returns with pop {r4, pc}.
@ Reached only by the b.w at 08010db0 inside the function at 08010a50, so the
@ pop returns to the caller of that function with d0 = the quotient.
@ ----------------------------------------------------------------------------
	.section .text.divide_zero_by_zero_double,"ax",%progbits
	.p2align 2
	.global divide_zero_by_zero_double
	.thumb_func
	.type divide_zero_by_zero_double, %function
divide_zero_by_zero_double:
	vldr	d0, .L08011a78
	push	{r4, lr}
	vmov	r2, r3, d0
	vmov	r0, r1, d0
	bl	double_divide
	vmov	d0, r0, r1
	pop	{r4, pc}
.L08011a78:
	.word	0x00000000, 0x00000000	@ 0.0

@ ----------------------------------------------------------------------------
@ fn_08011a80 - no parameters; loads the double 0x7000000000000000 (literal at
@ 08011a98), calls double_multiply with it as both operands and returns the
@ result in d0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08011a80,"ax",%progbits
	.p2align 2
	.global fn_08011a80
	.thumb_func
	.type fn_08011a80, %function
fn_08011a80:
	vldr	d0, .L08011a98
	push	{r4, lr}
	vmov	r2, r3, d0
	vmov	r0, r1, d0
	bl	double_multiply
	vmov	d0, r0, r1
	pop	{r4, pc}
.L08011a98:
	.word	0x00000000, 0x70000000	@ double 0x7000000000000000

@ ----------------------------------------------------------------------------
@ fn_08011aa0 - no parameters; loads the double 0x1000000000000000 (literal at
@ 08011ab8), calls double_multiply with it as both operands and returns the
@ result in d0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08011aa0,"ax",%progbits
	.p2align 2
	.global fn_08011aa0
	.thumb_func
	.type fn_08011aa0, %function
fn_08011aa0:
	vldr	d0, .L08011ab8
	push	{r4, lr}
	vmov	r2, r3, d0
	vmov	r0, r1, d0
	bl	double_multiply
	vmov	d0, r0, r1
	pop	{r4, pc}
.L08011ab8:
	.word	0x00000000, 0x10000000	@ double 0x1000000000000000

@ ----------------------------------------------------------------------------
@ float_add_to_self - parameter: float in s0; returns s0 + s0 in s0.
@ ----------------------------------------------------------------------------
	.section .text.float_add_to_self,"ax",%progbits
	.p2align 2
	.global float_add_to_self
	.thumb_func
	.type float_add_to_self, %function
float_add_to_self:
	vadd.f32	s0, s0, s0
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08011ac8 - no parameters; loads 0.0 into s1 from the literal at 08011ad4,
@ divides s1 by s1 (vdiv) and returns the result in s0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08011ac8,"ax",%progbits
	.p2align 2
	.global fn_08011ac8
	.thumb_func
	.type fn_08011ac8, %function
fn_08011ac8:
	vldr	s1, .L08011ad4
	vdiv.f32	s0, s1, s1
	bx	lr
	.short	0x0000			@ padding
.L08011ad4:
	.word	0x00000000		@ float 0.0

@ ----------------------------------------------------------------------------
@ fn_08011ad8 - no parameters; loads the float 0x10000000 (literal at 08011ae4)
@ into s0, multiplies s0 by s0 and returns the product in s0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08011ad8,"ax",%progbits
	.p2align 2
	.global fn_08011ad8
	.thumb_func
	.type fn_08011ad8, %function
fn_08011ad8:
	vldr	s0, .L08011ae4
	vmul.f32	s0, s0, s0
	bx	lr
	.short	0x0000			@ padding
.L08011ae4:
	.word	0x10000000		@ float 0x10000000

@ ----------------------------------------------------------------------------
@ fn_08011ae8 - large-argument range reduction for single precision sine.
@ Parameters: float s0, pointer to the quadrant output (r0), float bits (r1).
@ When (bits << 1) >= 0xff000000 (infinity or NaN) it stores 0xffffffff in *r0
@ and returns s0 unchanged.
@ Otherwise: exponent = ((bits & 0x7fffffff) >> 23) - 0x78; four words of the
@ table at 080510b0 (d_080510b0, reached by add r4, pc with the distance word
@ at 08011c24) starting at index exponent >> 5 are shifted by exponent & 0x1f;
@ the three shifted words are multiplied with (bits << 8 | 0x80000000) by
@ 32x32 to 64 bit multiplies (umull) and summed with carry; three partial
@ floats are built (vcvt) and scaled with the literals 1.9073486e-06 (2C800000
@ at 08011c2c) and 3.637979e-12 (36000000 at 08011c28); the sum is rounded by
@ adding 0x800 and clearing the low 12 bits; the result is formed with
@ 1.12649703e-13 (29FDAA22), 3.6572953e-10 (2FC90FDB) and 3.6561687e-10
@ (2FC90000).
@ Stores the quadrant ((integer + 0x20) >> 6) in *r0; when bit 31 of the input
@ is set it stores 0x10000000 minus the quadrant instead and returns the
@ negated result.
@ ----------------------------------------------------------------------------
	.section .text.fn_08011ae8,"ax",%progbits
	.p2align 2
	.global fn_08011ae8
	.thumb_func
	.type fn_08011ae8, %function
fn_08011ae8:
	push.w	{r4, r5, r6, r7, r8}
	mov.w	r2, #0xff000000
	cmp.w	r2, r1, lsl #1
	itttt	ls
	movls.w	r1, #0xffffffff
	strls	r1, [r0]
	popls.w	{r4, r5, r6, r7, r8}
	bxls	lr
	mov.w	r2, #0x80000000
	orr.w	r3, r2, r1, lsl #8	@ mantissa with the implicit bit
	ubfx	r2, r1, #23, #8
	subs	r2, #0x78
	asrs	r5, r2, #5
	ands	r12, r2, #0x1f
	ldr	r4, .L08011c24
	rsb.w	r6, r12, #0x20
.L08011b1c:
	add	r4, pc			@ r4 = address of the table at 080510b0
	ubfx	r2, r1, #23, #8
	sub.w	r2, r2, #0x78
	asr.w	r2, r2, #5
	add.w	r2, r4, r2, lsl #2
	ldr.w	r4, [r4, r5, lsl #2]
	it	eq
	ldrdeq	r5, r6, [r2, #4]
	beq.n	.L08011b60
	ldr	r5, [r2, #0x4]
	lsl.w	r4, r4, r12
	lsr.w	r7, r5, r6
	orrs	r4, r7
	ldr	r7, [r2, #0x8]
	lsl.w	r5, r5, r12
	lsr.w	r8, r7, r6
	ldr	r2, [r2, #0xc]
	lsl.w	r12, r7, r12
	lsrs	r2, r6
	orr.w	r5, r5, r8
	orr.w	r6, r12, r2
.L08011b60:
	umull	r4, r12, r4, r3
	umull	r5, r2, r5, r3
	umull	r6, r3, r6, r3
	add	r5, r3
	cmp	r5, r3
	ite	cc
	movcc	r6, #1
	movcs	r6, #0
	adds	r3, r2, r4
	add	r3, r6
	cbz	r6, .L08011b82
	cmp	r3, r2
	bls.n	.L08011b86
	b.n	.L08011b8a
.L08011b82:
	cmp	r3, r2
	bcs.n	.L08011b8a
.L08011b86:
	movs	r2, #1
	b.n	.L08011b8c
.L08011b8a:
	movs	r2, #0
.L08011b8c:
	add	r2, r12
	add.w	r12, r2, #0x20
	lsls	r2, r2, #26
	lsrs	r4, r3, #19
	orr.w	r2, r2, r4, lsl #13
	vmov	s0, r2
	lsls	r3, r3, #13
	vldr	s1, .L08011c28
	vcvt.f32.s32	s3, s0
	vmov	s0, r3
	lsr.w	r12, r12, #6		@ quadrant
	tst.w	r1, #0x80000000
	vcvt.f32.u32	s0, s0
	str.w	r12, [r0]
	vmul.f32	s2, s0, s1
	vmov	s0, r5
	vldr	s1, .L08011c2c
	vcvt.f32.u32	s0, s0
	vmul.f32	s0, s0, s1
	vadd.f32	s1, s3, s2
	vadd.f32	s1, s1, s0
	vmov	r2, s1
	add.w	r2, r2, #0x800
	bfc	r2, #0, #12
	vmov	s1, r2
	vsub.f32	s3, s1, s3
	vsub.f32	s2, s3, s2
	vldr	s3, .L08011c34
	vsub.f32	s2, s0, s2
	vldr	s0, .L08011c30
	vmul.f32	s0, s1, s0
	vmla.f32	s0, s2, s3
	vldr	s2, .L08011c38
	vmla.f32	s0, s1, s2
	itt	eq
	popeq.w	{r4, r5, r6, r7, r8}
	bxeq	lr
	rsb.w	r1, r12, #0x10000000
	str	r1, [r0]
	pop.w	{r4, r5, r6, r7, r8}
	vneg.f32	s0, s0
	bx	lr
.L08011c24:
	.word	d_080510b0 - (.L08011b1c + 4)
.L08011c28:
	.word	0x36000000
.L08011c2c:
	.word	0x2c800000
.L08011c30:
	.word	0x29fdaa22
.L08011c34:
	.word	0x2fc90fdb
.L08011c38:
	.word	0x2fc90000

@ ----------------------------------------------------------------------------
@ copy_words_ascending - parameters: source address (r0), destination address
@ (r1), byte count (r2); no return value; r3 is overwritten.
@ The entry branches to the loop test at 08011c44. Loop: while r2 != 0, load a
@ word from [r0] with post-increment, subtract 4 from r2, store the word to
@ [r1] with post-increment. Words move in ascending address order; the loop
@ ends only when r2 reaches exactly 0, so for a count that is not a multiple
@ of 4 it never ends.
@ ----------------------------------------------------------------------------
	.section .text.copy_words_ascending,"ax",%progbits
	.global copy_words_ascending
	.thumb_func
	.type copy_words_ascending, %function
copy_words_ascending:
	b.n	.L08011c44
.L08011c3e:
	ldmia	r0!, {r3}
	.inst.n	0x1f12			@ subs r2, r2, #4
	stmia	r1!, {r3}
.L08011c44:
	cmp	r2, #0
	bne.n	.L08011c3e
	bx	lr

@ ----------------------------------------------------------------------------
@ return_only_08011c4a - no parameters; a single bx lr. No flow or pointer to
@ this address is found.
@ ----------------------------------------------------------------------------
	.section .text.return_only_08011c4a,"ax",%progbits
	.global return_only_08011c4a
	.thumb_func
	.type return_only_08011c4a, %function
return_only_08011c4a:
	bx	lr

@ ----------------------------------------------------------------------------
@ zero_fill_words - parameters: unused (r0, set to 0), destination (r1), byte
@ count (r2). Loop: store a zero word to [r1] with post-increment, subtract 4
@ from r2, until r2 equals 0. The entry address is also held by the scatter-load
@ region table (zero_fill_words_addr).
@ ----------------------------------------------------------------------------
	.section .text.zero_fill_words,"ax",%progbits
	.p2align 2
	.global zero_fill_words
	.global zero_fill_words_addr
zero_fill_words_addr:
	.thumb_func
	.type zero_fill_words, %function
zero_fill_words:
	movs	r0, #0
	b.n	.L08011c54
.L08011c50:
	stmia	r1!, {r0}
	.inst.n	0x1f12			@ subs r2, r2, #4
.L08011c54:
	cmp	r2, #0
	bne.n	.L08011c50
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08011c98 - converts a double to decimal digits.
@ Parameters: result block pointer (r0), digit buffer (r1), double low word
@ (r2), double high word (r3), digit count/precision (stack), mode flag, 1 or
@ other (stack).
@ Zero value: block = {pointer to the string "0" (08011e10), ~precision when
@ the mode is 1 else 0, 1, mode}.
@ Otherwise: decimal exponent estimate = ((high >> 20) - 0x3ff) * 0x4d10 >> 16;
@ the value is scaled by a power of 5.0 (0x4014000000000000, literal 08011e08)
@ built by repeated squaring with double_multiply (start value 1.0, literal
@ 08011e0c), then divided or multiplied (double_divide / double_multiply). The
@ result is compared with 2^64 (0x43f00000 high word, literal 08011e14) through
@ fn_0800781c; when it is not above, the integer is all ones; otherwise 0.5
@ (0x3fe00000 high word, literal 08011e18) is added with double_add and
@ fn_080077bc converts it to a 64 bit integer.
@ Digits are extracted from buffer index 0x10 downwards with unsigned_divide_64
@ (divide by 10) as '0' + remainder.
@ The scan is retried with the exponent estimate changed by 1 until the digit
@ count fits (in mode 1 a nonzero rest sets precision 0x11 and mode 0).
@ Stores block[0] = pointer to the first digit, [1] = exponent, [2] = digit
@ count, [3] = mode.
@ ----------------------------------------------------------------------------
	.section .text.fn_08011c98,"ax",%progbits
	.p2align 2
	.global fn_08011c98
	.thumb_func
	.type fn_08011c98, %function
fn_08011c98:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	sub	sp, #0x8
	movs	r1, #0
	ldrd	r3, r0, [sp, #0x10]	@ double low and high word
	lsrs	r2, r0, #20
	ldr.w	r11, [sp, #0x40]	@ precision
	orrs	r3, r0
	beq.n	.L08011ce0
	movw	r0, #0x4d10
	subw	r2, r2, #0x3ff
	muls	r2, r0, r2
	asrs	r5, r2, #16		@ exponent estimate
.L08011cba:
	ldr	r0, [sp, #0x44]		@ mode
	cmp	r0, #1
	beq.n	.L08011d00
	sub.w	r0, r5, r11
	.inst.n	0x1c40			@ adds r0, r0, #1
.L08011cc6:
	movs.w	r10, r0
	mov.w	r6, #0
	ldr	r7, .L08011e08
	ldr.w	r9, .L08011e0c
	mov	r8, r6
	mov	r0, r10
	bpl.n	.L08011d06
	rsb.w	r4, r10, #0
	b.n	.L08011d08
.L08011ce0:
	ldr	r0, [sp, #0x44]
	movs	r4, #1
	adr	r3, .L08011e10
	cmp	r0, #1
	bne.n	.L08011cee
	mvn.w	r1, r11
.L08011cee:
	ldr	r0, [sp, #0x8]		@ result block pointer
	ldr	r2, [sp, #0x44]
	strd	r3, r1, [r0]
	strd	r4, r2, [r0, #8]
.L08011cfa:
	add	sp, #0x18
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}
.L08011d00:
	rsb.w	r0, r11, #0
	b.n	.L08011cc6
.L08011d06:
	mov	r4, r0
.L08011d08:
	movs	r1, #0
	ldr	r2, .L08011e0c
	adds	r1, r1, r1
	adc.w	r0, r2, r4, lsl #20
	strd	r1, r0, [sp]
	b.n	.L08011d3e
.L08011d18:
	lsls	r0, r4, #31
	beq.n	.L08011d2c
	mov	r2, r6
	mov	r3, r7
	mov	r0, r8
	mov	r1, r9
	bl	double_multiply
	mov	r8, r0
	mov	r9, r1
.L08011d2c:
	mov	r2, r6
	mov	r3, r7
	mov	r0, r2
	mov	r1, r3
	bl	double_multiply
	mov	r6, r0
	mov	r7, r1
	asrs	r4, r4, #1
.L08011d3e:
	cmp	r4, #0
	bne.n	.L08011d18
	ldrd	r0, r1, [sp, #0x10]
	ldrd	r2, r3, [sp]
	cmp.w	r10, #0
	bge.n	.L08011d5e
	bl	double_multiply
	mov	r2, r8
	mov	r3, r9
	bl	double_multiply
	b.n	.L08011d6a
.L08011d5e:
	bl	double_divide
	mov	r2, r8
	mov	r3, r9
	bl	double_divide
.L08011d6a:
	mov	r4, r0
	mov	r6, r1
	movs	r2, #0
	ldr	r3, .L08011e14
	bl	fn_0800781c
	bhi.n	.L08011d80
	mov.w	r0, #0xffffffff
	mov	r1, r0
	b.n	.L08011d90
.L08011d80:
	movs	r2, #0
	ldr	r3, .L08011e18
	mov	r0, r4
	mov	r1, r6
	bl	double_add
	bl	fn_080077bc
.L08011d90:
	movs	r4, #0x10		@ digit index
	b.n	.L08011da8
.L08011d94:
	cmp	r4, #0
	blt.n	.L08011dae
	movs	r2, #0xa
	movs	r3, #0
	bl	unsigned_divide_64
	ldr	r3, [sp, #0xc]		@ digit buffer
	adds	r2, #0x30
	strb	r2, [r3, r4]
	.inst.n	0x1e64			@ subs r4, r4, #1
.L08011da8:
	orrs.w	r2, r0, r1
	bne.n	.L08011d94
.L08011dae:
	.inst.n	0x1c64			@ adds r4, r4, #1
	ldr	r2, [sp, #0xc]
	rsb.w	r3, r4, #0x11		@ digit count
	add	r4, r2
	ldr	r2, [sp, #0x44]
	cmp	r2, #1
	beq.n	.L08011dc6
	movs	r2, #1
	orrs	r0, r1
	bne.n	.L08011de0
	b.n	.L08011ddc
.L08011dc6:
	orrs	r0, r1
	beq.n	.L08011dd4
	movs	r0, #0
	mov.w	r11, #0x11
	str	r0, [sp, #0x44]
.L08011dd2:
	b.n	.L08011cba
.L08011dd4:
	sub.w	r5, r3, r11
	.inst.n	0x1e6d			@ subs r5, r5, #1
	b.n	.L08011df8
.L08011ddc:
	cmp	r3, r11
	ble.n	.L08011dea
.L08011de0:
	mov.w	r2, #0
	add.w	r5, r5, #1
	b.n	.L08011df4
.L08011dea:
	bge.n	.L08011df4
	mov.w	r2, #0
	sub.w	r5, r5, #1
.L08011df4:
	cmp	r2, #0
	beq.n	.L08011dd2
.L08011df8:
	ldr	r0, [sp, #0x8]
	ldr	r1, [sp, #0x44]
	strd	r3, r1, [r0, #8]
	strd	r4, r5, [r0]
	b.n	.L08011cfa
	.short	0x0000			@ padding
.L08011e08:
	.word	0x40140000		@ high word of 5.0
.L08011e0c:
	.word	0x3ff00000		@ high word of 1.0
.L08011e10:
	.asciz	"0"
	.short	0x0000			@ padding
.L08011e14:
	.word	0x43f00000		@ high word of 2^64
.L08011e18:
	.word	0x3fe00000		@ high word of 0.5

@ ----------------------------------------------------------------------------
@ fn_08029ac4 - square root wrapper.
@ Parameters: r0, r1 = a double (r0 low word, r1 high word); returns a double
@ in r0, r1.
@ Calls double_square_root with the same arguments and keeps the result. When
@ the result is a NaN (low word nonzero ORed into the high word, sign cleared,
@ above 0x7ff00000; tested at 08029ad8..08029afa) and the argument was not
@ (same test on the saved argument, 08029afc..08029b1c) it calls
@ set_word_20000578(1). Returns the result of double_square_root.
@ ----------------------------------------------------------------------------
	.section .text.fn_08029ac4,"ax",%progbits
	.p2align 2
	.global fn_08029ac4
	.thumb_func
	.type fn_08029ac4, %function
fn_08029ac4:
	push	{lr}
	vpush	{d8, d9}
	sub	sp, #0xc
	vmov	d9, r0, r1		@ saved argument
	bl	double_square_root
	vmov	d8, r0, r1		@ result
	vmov	r0, s16
	vmov	r1, s17
	vstr	d8, [sp]
	cmp	r0, #0
	it	ne
	movne	r0, #1
	orrs	r0, r1
	bic	r0, r0, #0x80000000
	rsb.w	r0, r0, #0xff00000
	add.w	r0, r0, #0x70000000
	lsrs	r0, r0, #31
	beq.n	.L08029b26
	vmov	r1, s18
	vmov	r0, s19
	vstr	d9, [sp]
	cmp	r1, #0
	it	ne
	movne	r1, #1
	orrs	r0, r1
	bic	r0, r0, #0x80000000
	rsb.w	r0, r0, #0xff00000
	add.w	r0, r0, #0x70000000
	lsrs	r0, r0, #31
	itt	eq
	moveq	r0, #1
	bleq	set_word_20000578
.L08029b26:
	vmov	r0, r1, d8
	add	sp, #0xc
	vpop	{d8, d9}
	pop	{pc}
	.short	0x0000			@ padding
