@ ui_43.s - user-interface code: sorting value editor, sorting tolerance marker, sorting value text formatter, and the large screen-drawing routine at 0x0800e6c8
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0800e224 - changes the sorting nominal value or tolerance by one step.
@ Parameter r0 = step (positive or negative, kept in r5).
@ RAM used (base 0x2000057c): word 0x200011b4 (base+0xc38), word 0x200011b8
@ (base+0xc3c), float 0x20001184 (nominal value), float 0x20001188
@ (tolerance), word 0x2000119c (unit/scale index).
@ Word 0x200011b4 non-zero (tolerance editing): float 0x20001188 =
@ (float 0x20001188 * 10 + r0 * integer(10 ^ (2 - word 0x200011b8))) / 10,
@ using int_to_double, double_power (base 10.0 from the literal), double_to_int32;
@ the result is limited to 99.9 (0x42c7cccd, compared as an integer) and to 0.
@ Otherwise (nominal value editing) with word 0x200011b8 below 5: the scale
@ is 0.001 (0x3a83126f) for word 0x2000119c = 0, 1.0 for 1, 1000.0 for 2 and
@ 1e6 (0x49742400) otherwise. The float 0x20001184 * 100 / scale is converted
@ to an integer (float_to_double, fn_080116a0, double_to_int32) and split into
@ 5 decimal digits kept on the stack ([sp+0] is the highest digit). The digit
@ selected by word 0x200011b8 is raised by 1 (maximum 9) for a positive step
@ or lowered by 1 (minimum 0) for a negative step; when the three highest
@ digits are then all zero, the third digit is set to 1. The float is written
@ back as digits / 100 * scale.
@ Word 0x200011b8 of 5 or more: word 0x2000119c is changed by the step inside
@ 0..3, then float 0x20001184 is rescaled: below 0x3f800000 it is multiplied
@ by 1000, from 0x447a0000 below 0x49742400 divided by 1000, from 0x49742400
@ divided by 1e6, and finally multiplied by the new scale.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800e224,"ax",%progbits
	.p2align 2
	.global fn_0800e224
	.thumb_func
	.type fn_0800e224, %function
fn_0800e224:
	push	{r4, r5, r6, lr}
	ldr	r1, .L0800e46c		@ 0x2000057c, RAM base
	mov	r5, r0			@ r5 = step
	vpush	{d8}
	mov	r0, r1
	ldr.w	r2, [r1, #0xc38]	@ r2 = word 0x200011b4
	ldr.w	r6, [r0, #0xc3c]	@ r6 = word 0x200011b8
	sub	sp, #0x18
	add.w	r4, r0, #0xc00		@ r4 = 0x2000117c
	cbz	r2, .L0800e2b2
	vldr	s0, [r4, #0xc]		@ float 0x20001188
	vmov.f32	s16, #10.0
	rsb.w	r0, r6, #2
	vmul.f32	s0, s0, s16
	vstr	s0, [r4, #0xc]
	bl	int_to_double
	vmov	d1, r0, r1
	vldr	d0, .L0800e470		@ 10.0 (double)
	bl	double_power
	vmov	r0, r1, d0
	bl	double_to_int32
	muls	r0, r5, r0		@ step * integer power of ten
	vmov	s0, r0
	vldr	s1, [r4, #0xc]
	ldr	r1, .L0800e478		@ 0x42c7cccd, 99.9
	vcvt.f32.s32	s0, s0
	vadd.f32	s1, s0, s1
	vdiv.f32	s0, s1, s16
	vmov	r0, s0
	vstr	s0, [r4, #0xc]
	cmp	r0, r1
	ble.n	.L0800e298
	vldr	s0, .L0800e47c		@ 99.9
	vstr	s0, [r4, #0xc]
.L0800e298:
	vcmpe.f32	s0, #0
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800e2aa
	vldr	s0, .L0800e480		@ 0.0
	vstr	s0, [r4, #0xc]
.L0800e2aa:
	add	sp, #0x18
	vpop	{d8}
	pop	{r4, r5, r6, pc}
.L0800e2b2:
	b.n	.L0800e2b4
.L0800e2b4:
	vldr	s16, .L0800e484		@ 0.001
	ldr	r2, .L0800e46c
	vmov.f32	s3, #1.0
	vldr	s1, .L0800e488		@ 1000.0
	vldr	s2, .L0800e48c		@ 1e6
	ldr.w	r0, [r2, #0xc20]	@ r0 = word 0x2000119c
	add.w	r2, r2, #0xc00
	cmp	r6, #5
	vldr	s0, [r2, #8]		@ float 0x20001184
	bge	.L0800e3d2
	cbz	r0, .L0800e2e4
	cmp	r0, #1
	beq	.L0800e37e
	cmp	r0, #2
	beq	.L0800e384
	vmov.f32	s16, s2
.L0800e2e4:
	vldr	s17, .L0800e490		@ 100.0
	vmul.f32	s1, s0, s17
	vdiv.f32	s0, s1, s16
	vmov	r0, s0
	bl	float_to_double
	vmov	d0, r0, r1
	bl	fn_080116a0
	vmov	r0, r1, d0
	bl	double_to_int32
	@ split r0 into 5 decimal digits at [sp+0] .. [sp+0x10]
	movw	r1, #0x2710
	sdiv	r2, r0, r1
	movs	r1, #0xa
	sdiv	r3, r2, r1
	mls	r2, r1, r3, r2
	str	r2, [sp, #0]		@ (value / 10000) % 10
	mov.w	r2, #0x3e8
	sdiv	r2, r0, r2
	sdiv	r3, r2, r1
	mls	r2, r1, r3, r2
	str	r2, [sp, #4]		@ (value / 1000) % 10
	movs	r2, #0x64
	sdiv	r2, r0, r2
	sdiv	r3, r2, r1
	mls	r2, r1, r3, r2
	str	r2, [sp, #8]		@ (value / 100) % 10
	sdiv	r2, r0, r1
	sdiv	r3, r2, r1
	mls	r2, r1, r3, r2
	str	r2, [sp, #0xc]		@ (value / 10) % 10
	sdiv	r2, r0, r1
	mls	r0, r1, r2, r0
	str	r0, [sp, #0x10]		@ value % 10
	ldr.w	r1, [sp, r6, lsl #2]	@ digit selected by word 0x200011b8
	mov	r0, sp
	cmp	r1, #9
	bge	.L0800e36a
	cmp	r5, #0
	ble	.L0800e36a
	.inst.n	0x1c49			@ adds r1, r1, #1
	str.w	r1, [r0, r6, lsl #2]
.L0800e36a:
	cmp	r1, #0
	ble	.L0800e396
	cmp	r5, #0
	bge	.L0800e396
	.inst.n	0x1e49			@ subs r1, r1, #1
	str.w	r1, [r0, r6, lsl #2]
	ldr	r0, [sp, #0]
	cbz	r0, .L0800e38a
	b.n	.L0800e396
.L0800e37e:
	vmov.f32	s16, s3
	b.n	.L0800e2e4
.L0800e384:
	vmov.f32	s16, s1
	b.n	.L0800e2e4
.L0800e38a:
	ldr	r0, [sp, #4]
	cbnz	r0, .L0800e396
	ldr	r0, [sp, #8]
	cbnz	r0, .L0800e396
	movs	r0, #1
	str	r0, [sp, #8]		@ three highest digits zero: third digit = 1
.L0800e396:
	@ value = d0*10000 + d1*1000 + d2*100 + d3*10 + d4, then as float
	ldr	r0, [sp, #0]
	movw	r1, #0x2710
	muls	r0, r1, r0
	ldr	r1, [sp, #4]
	add.w	r2, r1, r1, lsl #1
	rsb	r1, r2, r1, lsl #7
	add.w	r0, r0, r1, lsl #3
	ldr	r1, [sp, #8]
	add.w	r2, r1, r1, lsl #3
	add.w	r1, r2, r1, lsl #4
	add.w	r0, r0, r1, lsl #2
	ldr	r1, [sp, #0xc]
	add.w	r1, r1, r1, lsl #2
	add.w	r0, r0, r1, lsl #1
	ldr	r1, [sp, #0x10]
	add	r0, r1
	vmov	s0, r0
	vcvt.f32.s32	s0, s0
	b.n	.L0800e3d4
.L0800e3d2:
	b.n	.L0800e3de
.L0800e3d4:
	vdiv.f32	s1, s0, s17		@ digits / 100
	vmul.f32	s0, s1, s16		@ times scale
	b.n	.L0800e464
.L0800e3de:
	cmp	r0, #3
	bge	.L0800e3f6
	cmp	r5, #0
	bgt	.L0800e3ec
	ldr.w	r0, [r1, #0xc20]
	b.n	.L0800e3f2
.L0800e3ec:
	add	r0, r5
	str.w	r0, [r1, #0xc20]	@ word 0x2000119c += step
.L0800e3f2:
	cmp	r0, #0
	ble	.L0800e404
.L0800e3f6:
	cmp	r5, #0
	bge	.L0800e404
	ldr.w	r0, [r1, #0xc20]
	add	r0, r5
	str.w	r0, [r1, #0xc20]	@ word 0x2000119c += step (negative)
.L0800e404:
	ldr.w	r0, [r1, #0xc20]
	cbz	r0, .L0800e416
	cmp	r0, #1
	beq	.L0800e42a
	cmp	r0, #2
	beq	.L0800e430
	vmov.f32	s16, s2
.L0800e416:
	vmov	r0, s0
	cmp.w	r0, #0x3f800000
	bge	.L0800e436
	vmul.f32	s0, s0, s1
	vstr	s0, [r4, #8]
	b.n	.L0800e45c
.L0800e42a:
	vmov.f32	s16, s3
	b.n	.L0800e416
.L0800e430:
	vmov.f32	s16, s1
	b.n	.L0800e416
.L0800e436:
	vmov	r0, s0
	ldr	r1, .L0800e494		@ 0x447a0000
	cmp	r0, r1
	blt	.L0800e45c
	vmov	r0, s0
	ldr	r1, .L0800e498		@ 0x49742400
	cmp	r0, r1
	bge	.L0800e454
	vdiv.f32	s2, s0, s1
	vstr	s2, [r4, #8]
	b.n	.L0800e45c
.L0800e454:
	vdiv.f32	s1, s0, s2
	vstr	s1, [r4, #8]
.L0800e45c:
	vldr	s0, [r4, #8]
	vmul.f32	s0, s0, s16
.L0800e464:
	vstr	s0, [r4, #8]
	b.n	.L0800e2aa
	.short	0x0000			@ padding
.L0800e46c:
	.word	0x2000057c
.L0800e470:
	.word	0x00000000, 0x40240000	@ double 10.0
.L0800e478:
	.word	0x42c7cccd
.L0800e47c:
	.word	0x42c7cccd
.L0800e480:
	.word	0x00000000
.L0800e484:
	.word	0x3a83126f
.L0800e488:
	.word	0x447a0000
.L0800e48c:
	.word	0x49742400
.L0800e490:
	.word	0x42c80000
.L0800e494:
	.word	0x447a0000
.L0800e498:
	.word	0x49742400

@ ----------------------------------------------------------------------------
@ fn_0800e49c - builds a line object from a horizontal position and width.
@ Parameters: r0 = x offset (short), r1 = width (short).
@ Stores r0 + 7 to halfword 0x2000004c, r0 + r1 + 7 to halfword 0x20000050
@ and 0x57 to halfwords 0x2000004e and 0x20000052. Then takes the object
@ pointer from table 0x2000592c indexed by word 0x200011b4 (base 0x2000057c
@ + 0xc38), creates a line object with fn_08022964, calls
@ fn_08022afc(obj, 0x2000004c, 2) and fn_08026616(obj, 2, 0), obtains the
@ colour rgb_to_565_0801d792(0xfd, 0xd0, 0x1b) and tail-jumps to
@ fn_080265fe(obj, colour, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800e49c,"ax",%progbits
	.p2align 2
	.global fn_0800e49c
	.thumb_func
	.type fn_0800e49c, %function
fn_0800e49c:
	adds	r3, r0, #7
	ldr	r2, .L0800e4ec		@ 0x2000004c
	push	{r4, lr}
	add	r0, r1
	strh	r3, [r2, #0]		@ halfword 0x2000004c = x + 7
	.inst.n	0x1dc0			@ adds r0, r0, #7
	strh	r0, [r2, #4]		@ halfword 0x20000050 = x + width + 7
	movs	r0, #0x57
	strh	r0, [r2, #2]		@ halfword 0x2000004e = 0x57
	strh	r0, [r2, #6]		@ halfword 0x20000052 = 0x57
	ldr	r0, .L0800e4f0		@ 0x2000057c
	ldr	r1, .L0800e4f4		@ 0x2000592c, object pointer table
	ldr.w	r0, [r0, #0xc38]	@ word 0x200011b4
	ldr.w	r0, [r1, r0, lsl #2]
	bl	fn_08022964
	mov	r4, r0
	movs	r2, #2
	ldr	r1, .L0800e4ec
	bl	fn_08022afc
	movs	r2, #0
	movs	r1, #2
	mov	r0, r4
	bl	fn_08026616
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	bl	rgb_to_565_0801d792
	mov	r1, r0
	mov	r0, r4
	pop.w	{r4, lr}
	movs	r2, #0
	b.w	fn_080265fe
.L0800e4ec:
	.word	0x2000004c
.L0800e4f0:
	.word	0x2000057c
.L0800e4f4:
	.word	0x2000592c

@ ----------------------------------------------------------------------------
@ fn_0800e4f8 - formats the sorting nominal value and tolerance as text.
@ No parameters. RAM base 0x2000057c (r4), float block base 0x2000117c (r6).
@ Word 0x20001148 (base+0xbcc) of 2 or 3 is kept in word 0x20001178
@ (base+0xbfc) and byte 0x200011e4 (base+0xc68); any other value sets
@ word 0x20001178, byte 0x200011e4 and word 0x20001148 to 1.
@ Float 0x20001184 below 0x3f800000: prints value * 1000 with "%06.2f"
@ (fn_08010370 into a 32-byte stack buffer) and sets word 0x2000119c = 0;
@ below 0x447a0000: prints the value, word 0x2000119c = 1; below 0x49742400:
@ value / 1000, word 0x2000119c = 2; below 0x4e6e6b28: value / 1e6 (0x49742400
@ is 1e6 as a float constant), word 0x2000119c = 3.
@ Then fn_080228d0(word 0x20000020, "%s", string from table 0x20000194
@ indexed by word 0x20001178 * 4 + word 0x2000119c) and prints
@ five characters of the buffer (bytes 0, 1, 2, 4, 5) with "%c" into the
@ objects held in words 0x2000597c, 0x20005980, 0x20005984, 0x20005988,
@ 0x2000598c. Finally prints float 0x20001188 with "%04.1f" and puts bytes
@ 0, 1 and 3 of the buffer with "%c" into objects 0x20005990, 0x20005994,
@ 0x20005998.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800e4f8,"ax",%progbits
	.p2align 2
	.global fn_0800e4f8
	.thumb_func
	.type fn_0800e4f8, %function
fn_0800e4f8:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r4, .L0800e688		@ 0x2000057c
	movs	r7, #2
	movs	r5, #1
	ldr.w	r0, [r4, #0xbcc]	@ word 0x20001148
	sub	sp, #0x20
	mov.w	r8, #3
	cmp	r0, #2
	beq	.L0800e558
	cmp	r0, #3
	beq	.L0800e562
	str.w	r5, [r4, #0xbfc]	@ word 0x20001178 = 1
	strb.w	r5, [r4, #0xc68]	@ byte 0x200011e4 = 1
	str.w	r5, [r4, #0xbcc]	@ word 0x20001148 = 1
.L0800e520:
	ldr	r6, .L0800e68c		@ 0x2000117c
	vldr	s0, [r6, #8]		@ float 0x20001184
	vmov	r0, s0
	vldr	s2, .L0800e690		@ 1000.0
	cmp.w	r0, #0x3f800000
	bge	.L0800e56c
	vmul.f32	s0, s0, s2
	vmov	r0, s0
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e694		@ "%06.2f"
	vmov	r2, r3, d0
	mov	r0, sp
	bl	fn_08010370
	movs	r0, #0
	str.w	r0, [r4, #0xc20]	@ word 0x2000119c = 0
	b.n	.L0800e5ea
.L0800e558:
	str.w	r7, [r4, #0xbfc]	@ word 0x20001178 = 2
	strb.w	r7, [r4, #0xc68]	@ byte 0x200011e4 = 2
	b.n	.L0800e520
.L0800e562:
	str.w	r8, [r4, #0xbfc]	@ word 0x20001178 = 3
	strb.w	r8, [r4, #0xc68]	@ byte 0x200011e4 = 3
	b.n	.L0800e520
.L0800e56c:
	vmov	r0, s0
	ldr	r1, .L0800e69c		@ 0x447a0000
	cmp	r0, r1
	vmov	r0, s0
	bge	.L0800e594
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e694		@ "%06.2f"
	vmov	r2, r3, d0
	mov	r0, sp
	bl	fn_08010370
	str.w	r5, [r4, #0xc20]	@ word 0x2000119c = 1
	b.n	.L0800e5ea
.L0800e594:
	ldr	r1, .L0800e6a0		@ 0x49742400
	cmp	r0, r1
	bge	.L0800e5bc
	vdiv.f32	s1, s0, s2		@ value / 1000
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e694		@ "%06.2f"
	vmov	r2, r3, d0
	mov	r0, sp
	bl	fn_08010370
	str.w	r7, [r4, #0xc20]	@ word 0x2000119c = 2
	b.n	.L0800e5ea
.L0800e5bc:
	vmov	r0, s0
	ldr	r1, .L0800e6a4		@ 0x4e6e6b28
	cmp	r0, r1
	bge	.L0800e5ea
	vldr	s2, .L0800e6a8		@ 0x49742400 (1e6)
	vdiv.f32	s1, s0, s2		@ value / 1e6
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e694		@ "%06.2f"
	vmov	r2, r3, d0
	mov	r0, sp
	bl	fn_08010370
	str.w	r8, [r4, #0xc20]	@ word 0x2000119c = 3
.L0800e5ea:
	ldr	r1, .L0800e6ac		@ 0x200001a4
	ldr.w	r0, [r4, #0xbfc]	@ word 0x20001178
	add.w	r0, r1, r0, lsl #4
	ldr.w	r1, [r4, #0xc20]	@ word 0x2000119c
	add.w	r0, r0, r1, lsl #2
	adr	r1, .L0800e6b0		@ "%s"
	ldr.w	r2, [r0, #-0x10]	@ string pointer from the table
	ldr	r0, .L0800e6b4		@ 0x2000000c
	ldr	r0, [r0, #0x14]		@ word 0x20000020, the object
	bl	fn_080228d0
	ldr	r4, .L0800e6b8		@ 0x2000597c, object table
	ldrb.w	r2, [sp]
	adr	r1, .L0800e6bc		@ "%c"
	ldr	r0, [r4, #0]
	bl	fn_080228d0
	ldrb.w	r2, [sp, #1]
	adr	r1, .L0800e6bc
	ldr	r0, [r4, #4]
	bl	fn_080228d0
	ldrb.w	r2, [sp, #2]
	adr	r1, .L0800e6bc
	ldr	r0, [r4, #8]
	bl	fn_080228d0
	ldrb.w	r2, [sp, #4]
	adr	r1, .L0800e6bc
	ldr	r0, [r4, #0xc]
	bl	fn_080228d0
	ldrb.w	r2, [sp, #5]
	adr	r1, .L0800e6bc
	ldr	r0, [r4, #0x10]
	bl	fn_080228d0
	ldr	r0, [r6, #0xc]		@ float 0x20001188
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e6c0		@ "%04.1f"
	vmov	r2, r3, d0
	mov	r0, sp
	bl	fn_08010370
	ldrb.w	r2, [sp]
	adr	r1, .L0800e6bc
	ldr	r0, [r4, #0x14]
	bl	fn_080228d0
	ldrb.w	r2, [sp, #1]
	adr	r1, .L0800e6bc
	ldr	r0, [r4, #0x18]
	bl	fn_080228d0
	ldrb.w	r2, [sp, #3]
	adr	r1, .L0800e6bc
	ldr	r0, [r4, #0x1c]
	bl	fn_080228d0
	add	sp, #0x20
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0800e688:
	.word	0x2000057c
.L0800e68c:
	.word	0x2000117c
.L0800e690:
	.word	0x447a0000
.L0800e694:
	.asciz	"%06.2f"
	.byte	0x00			@ padding
.L0800e69c:
	.word	0x447a0000
.L0800e6a0:
	.word	0x49742400
.L0800e6a4:
	.word	0x4e6e6b28
.L0800e6a8:
	.word	0x49742400
.L0800e6ac:
	.word	0x200001a4
.L0800e6b0:
	.asciz	"%s"
	.byte	0x00			@ padding
.L0800e6b4:
	.word	0x2000000c
.L0800e6b8:
	.word	0x2000597c
.L0800e6bc:
	.asciz	"%c"
	.byte	0x00			@ padding
.L0800e6c0:
	.asciz	"%04.1f"
	.byte	0x00			@ padding

@ ----------------------------------------------------------------------------
@ fn_0800e6c8 - builds the widget tree of one screen of the user interface.
@ The routine is one range 0x0800e6c8..0x0800f294 (3020 bytes). Notation:
@ B = 0x2000057c (r5), M = 0x2000000c (r6), lang = word 0x2000115c (B+0xbe0),
@ mode = word 0x200011a8 (B+0xc2c), sel = word 0x200011b4 (B+0xc38),
@ idx = word 0x200011b8 (B+0xc3c), P0 = word 0x20000018 (M+12, the parent
@ object), rgb(r,g,b) = rgb_to_565_0801d792(r, g, b), T = fn_08023170(obj,
@ a, x, y), the object constructors are fn_0802122c, fn_08021f5c and
@ fn_08023678, text goes through fn_0802285c and fn_080228d0.
@ The entry push {r2, r3, ...} keeps the incoming r2 and r3 at [sp+0] and
@ [sp+4]; they are popped back into r2 and r3 at the exits 0x0800f1b6 and
@ 0x0800f26a before a tail branch, and the ldmia at 0x0800ef64 also pops
@ [sp+0] and [sp+4] into r2 and r3. No parameter is read; no return value.
@ Returns at once when word 0x200011ac (B+0xc30) is 0.
@ Calls fn_08023520(P0), then fn_08023050(word 0x200058f0[i], 1) for i = 0..4
@ (loop 0x0800e6e4..0x0800e6f2); sets r7 = 0x20005954.
@ mode 0: 0x0800e97e; mode 5: 0x0800ef68; mode 6: falls through to
@ 0x0800e710; any other mode goes to the epilogue 0x0800ef64. The branches
@ at 0x0800e7d4, 0x0800e7d6 and 0x0800e920 are trampolines to 0x0800e920,
@ 0x0800e97e and 0x0800ef64.
@ MODE 6 (0x0800e710): t = fn_0802122c(P0), T(t, 9, 0, -50),
@ fn_08021c14(t, 0x0804cac0); for i = 0, 1: o = fn_08021f5c(P0), word
@ 0x20005954[i] = o, T(o, 7, 0x69, i*0x14 - 10), fn_0802285c(o, word
@ 0x20000194[lang*2 + i]); p = fn_08023678(P0) sized fn_080263a8(p, 0x82,
@ 0x1e), T(p, 9, 0, 50), fn_0802657a(p, rgb(0,0,0), 0), fn_08026680(p, 5, 0),
@ fn_080265be(p, 1, 0), fn_0802659c(p, rgb(0xfd,0xd0,0x1b), 0),
@ fn_08026380(p, 0), fn_0802662a(p, 0, 0); child c = fn_08021f5c(p) stored in
@ word 0x20005960, T(c, 9, 0, 0), fn_080266ac(c, 0x0802f0d8, 0),
@ fn_08026694(c, rgb(0xfd,0xd0,0x1b), 0), fn_0802285c(c, word 0x2000003c[lang]).
@ When byte M is 0 the function ends; otherwise q = fn_08023678(P0) sized
@ (0xdc, 0x78), T(q, 9, 0, -20), black fn_0802657a, fn_08026680(q, 5, 0),
@ fn_080265be(q, 1, 0), fn_0802659c(q, rgb(255,255,255), 0), fn_08026380(q, 0),
@ fn_0802662a(q, 0, 0); child t2 = fn_08021f5c(q), T(t2, 9, 0, -20),
@ fn_080266ac(t2, 0x0802ce5c, 0), fn_0802285c(t2, word 0x20000044[lang]),
@ fn_080266d4(t2, 0xc8), fn_080227e4(t2, 0), fn_0802668a(t2, 2, 0); two
@ buttons b1, b2 = fn_08023678(q), each sized (0x30, 0x1a), T(b1, 5, -45, -15),
@ T(b2, 5, 45, -15), black fn_0802657a, fn_08026680(., 5, 0), fn_080265be(.,
@ 1, 0) on both; the fn_0802659c colour: sel = 1 gives b1 rgb(0xfd,0xd0,0x1b)
@ and b2 rgb(255,255,255), any other sel gives b1 rgb(255,255,255) and b2
@ rgb(0xfd,0xd0,0x1b); then fn_08026380(., 0) and fn_0802662a(., 0, 0) on
@ both; children x1 = fn_08021f5c(b1), x2 = fn_08021f5c(b2), T(., 9, 0, 0),
@ fn_080266ac(., 0x0802f0d8, 0), fn_0802285c(x1, word 0x20000164[lang*2]),
@ tail branch fn_0802285c(x2, word 0x20000168[lang*2]) (0x0800f26e).
@ MODE 5 (0x0800ef68): panel A = fn_08023678(P0) sized (0xc8, 0x82), T(A, 9,
@ 0, -10), fn_0802657a(A, rgb(0,0,0), 0), fn_08026680(A, 5, 0),
@ fn_080265be(A, 1, 0), fn_0802659c(A, rgb(255,0,0), 0), fn_08026380(A, 0),
@ fn_0802662a(A, 0, 0); B = fn_08023678(A) sized (0xb4, 0x32), T(B, 9, 0,
@ -30), black fn_0802657a, fn_08026680(B, 0, 0), fn_080265be(B, 1, 0),
@ fn_0802659c(B, rgb(255,0,0), 0), fn_08026380(B, 0), fn_0802662a(B, 0, 0);
@ C = fn_08023678(B) sized (0x50, 0x32), T(C, 7, 0, 0), fn_0802657a(C,
@ rgb(255,0,0), 0), fn_08026680(C, 0, 0), fn_080265be(C, 0, 0),
@ fn_08026380(C, 0); D = fn_08023678(A) sized (0x50, 0x28), T(D, 5, 0, -9),
@ fn_0802657a(D, rgb(0x33,0x33,0x33), 0), fn_08026680(D, 5, 0),
@ fn_080265be(D, 1, 0), fn_0802659c(D, rgb(0x54,0x54,0x54), 0),
@ fn_08026380(D, 0); children fn_08021f5c(C), (B), (A), (D) stored in words
@ 0x20005954, 0x20005958, 0x2000595c, 0x20005960, placed with T(., 9, 0, 0),
@ T(., 9, 0x28, 0), T(., 9, 0, 6), T(., 9, 0, 0); fn_080266ac with 0x0802f0d8,
@ 0x0802f0d8, 0x0802ce5c, 0x0802f0d8; fn_080228d0 prints word
@ 0x20000034[lang] into the first, word 0x2000009c[lang*12 + word
@ 0x200050e0] into the second, the empty string 0x0800f28c into the third,
@ and the last is a tail branch fn_080228d0(obj, word 0x200000fc[lang*4 +
@ word 0x200050ec], r2, r3) with the original r2 and r3 (0x0800f1b6).
@ MODE 0 (0x0800e97e): for i = 0..4: o = fn_0802122c(P0) into word
@ 0x2000592c[i]; colour = rgb(0xfd,0xd0,0x1b) when sel = i else
@ rgb(0x54,0x54,0x54); fn_0802659c(o, colour, 0), fn_080265be(o, 2, 0),
@ fn_0802662a(o, 0, 0); child c = fn_08021f5c(o) into word 0x20005954[i],
@ fn_080266ac(c, 0x0802ce5c, 0), fn_08026694(c, colour2, 0) with colour2 =
@ rgb(0xfd,0xd0,0x1b) when sel = i and byte M is nonzero, else
@ rgb(255,255,255); fn_080228d0(c, "%s", word 0x2000011c[lang*5 + i]).
@ fn_08021c14 with 0x0804f850 on 0x2000592c[0] and [1] and 0x0804d990 on [2],
@ [3], [4]; T(., 9, x, y) for 0x2000592c[0..4]: (-80,-39), (80,-39),
@ (-104,60), (0,60), (104,60). Five more objects word 0x20005940..0x20005950 =
@ fn_0802122c(0x20005934), (0x20005938), (0x2000593c), (0x20005938),
@ (0x2000593c); fn_08021c14 with 0x0804cc40, 0x0804cb74, 0x0804da5c on the
@ first three, and on the fourth and fifth 0x0804fa98 when word 0x20001170
@ (B+0xbf4), respectively 0x20001174 (B+0xbf8), is 0, else 0x0804fce0;
@ fn_080265dc(., rgb(0xfd,0xd0,0x1b), 0) on the first three; fn_080265f4(.,
@ 255 or 0, 0) on the first three where 255 only when sel = 2, 3, 4
@ respectively and byte M is nonzero; T(., 9, -34, -20) on the first three,
@ T(., 9, 0, 16) on the fourth and fifth. T(0x20005954[0], 9, 0, -33), T([1],
@ 9, 0, -33), T([2], 9, 10, -19), T([3], 9, 10, -19), T([4], 9, 10, -19).
@ Five children word 0x20005968..0x20005978 = fn_08021f5c(0x20005934),
@ (0x20005938), (0x20005938), (0x2000593c), (0x2000593c), each with
@ fn_080266ac(., 0x0802ce5c, 0), T(., 9, 0, 16), (., 9, -33, 16), (., 9, 33,
@ 17), (., 9, -33, 16), (., 9, 33, 17); fn_080228d0(., "%s", ...) with word
@ 0x20000144[lang*2 + word 0x2000116c], word 0x20000154[lang*2], word
@ 0x20000158[lang*2], word 0x20000154[lang*2], word 0x20000158[lang*2].
@ Eight digit objects word 0x2000597c..0x20005998 = fn_08021f5c(0x2000592c)
@ five times and fn_08021f5c(0x20005930) three times, plus word 0x20000020 =
@ fn_08021f5c(0x2000592c) and one more kept in r10 = fn_08021f5c(0x20005930);
@ fn_080266ac(., 0x0802f5e8, 0) on the eight; two objects
@ fn_08023678(0x2000592c), fn_08023678(0x20005930) stored in [sp+0] and
@ [sp+4] (overwriting the saved r2, r3), sized (3, 3), fn_08026680(., 0, 0),
@ fn_080265be(., 0, 0), fn_0802657a(., rgb(255,255,255), 0), fn_08026380(., 0);
@ T(., 8, x, y) on the eight digit objects and the two extra objects with y =
@ 18 (29 for [sp+0], [sp+4]) and x = -120, -100, -80, [sp+0] -78, -58, -38,
@ -95, -75, [sp+4] -73, -53; fn_080266ac(0x20000020, 0x0802f0d8, 0) and
@ (r10, 0x0802f0d8, 0); fn_080228d0(r10, "%%" at 0x0800ef18); T(0x20000020,
@ 7, 0x6c, 0x18) and T(r10, 7, 0x61, 0x18); calls fn_0800e4f8. With sel = 0
@ and byte M nonzero calls fn_0800e49c(x, w) with idx < 3: (idx*0x14, 0x11);
@ 3 <= idx < 5: (2 + idx*0x14, 0x11); idx >= 5: (3 + idx*0x14, 0x18); with
@ sel = 1 and byte M nonzero calls fn_0800e49c(25 + idx*0x14, 0x11) for idx <
@ 2 and fn_0800e49c(27 + idx*0x14, 0x11) for idx >= 2; other sel calls
@ nothing (signed comparisons at 0x0800eee4, 0x0800ef1c, 0x0800ef4c).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800e6c8,"ax",%progbits
	.p2align 2
	.global fn_0800e6c8
	.thumb_func
	.type fn_0800e6c8, %function
fn_0800e6c8:
	push.w	{r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	ldr	r5, .L0800eac8		@ 0x2000057c, B
	ldr.w	r0, [r5, #0xc30]	@ word 0x200011ac
	cmp	r0, #0
	beq	.L0800e7d4		@ trampoline to the epilogue
	ldr	r6, .L0800eacc		@ 0x2000000c, M
	ldr	r0, [r6, #0xc]		@ P0
	bl	fn_08023520
	ldr	r7, .L0800ead0		@ 0x200058f0
	movs	r4, #0
	nop
.L0800e6e4:
	ldr.w	r0, [r7, r4, lsl #2]
	movs	r1, #1
	bl	fn_08023050
	.inst.n	0x1c64			@ adds r4, r4, #1
	cmp	r4, #5
	blt	.L0800e6e4
	ldr	r7, .L0800ead0
	ldr.w	r0, [r5, #0xc2c]	@ mode, word 0x200011a8
	adds	r7, #0x64		@ r7 = 0x20005954
	mvn	r10, #0x13		@ r10 = -20
	cmp	r0, #0
	beq	.L0800e7d6		@ mode 0
	mvn	r8, #9			@ r8 = -10
	cmp	r0, #5
	beq	.L0800e806		@ mode 5
	cmp	r0, #6
	bne	.L0800e7d4		@ other modes: epilogue
	@ mode 6
	ldr	r0, [r6, #0xc]
	bl	fn_0802122c
	mov	r4, r0
	mvn	r3, #0x31		@ y = -50
	movs	r2, #0
	movs	r1, #9
	bl	fn_08023170
	ldr	r1, .L0800ead4		@ 0x0804cac0
	mov	r0, r4
	bl	fn_08021c14
	ldr.w	r9, .L0800ead8		@ 0x20000194
	movs	r4, #0
.L0800e732:
	ldr	r0, [r6, #0xc]
	bl	fn_08021f5c
	add.w	r2, r4, r4, lsl #2
	add.w	r1, r8, r2, lsl #2	@ i*0x14 - 10
	sxth	r3, r1
	str.w	r0, [r7, r4, lsl #2]	@ word 0x20005954[i]
	movs	r2, #0x69
	movs	r1, #7
	bl	fn_08023170
	ldr.w	r1, [r5, #0xbe0]	@ lang, word 0x2000115c
	add.w	r0, r9, r1, lsl #3
	ldr.w	r1, [r0, r4, lsl #2]	@ word 0x20000194[lang*2 + i]
	ldr.w	r0, [r7, r4, lsl #2]
	bl	fn_0802285c
	.inst.n	0x1c64			@ adds r4, r4, #1
	cmp	r4, #2
	blt	.L0800e732
	ldr	r0, [r6, #0xc]
	bl	fn_08023678
	mov	r4, r0
	movs	r2, #0x1e
	movs	r1, #0x82
	bl	fn_080263a8
	movs	r3, #0x32
	movs	r2, #0
	movs	r1, #9
	mov	r0, r4
	bl	fn_08023170
	movs	r2, #0
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d792	@ black
	mov	r1, r0
	movs	r2, #0
	mov	r0, r4
	bl	fn_0802657a
	movs	r2, #0
	movs	r1, #5
	mov	r0, r4
	bl	fn_08026680
	movs	r2, #0
	movs	r1, #1
	mov	r0, r4
	bl	fn_080265be
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	bl	rgb_to_565_0801d792
	mov	r1, r0
	movs	r2, #0
	mov	r0, r4
	bl	fn_0802659c
	movs	r1, #0
	mov	r0, r4
	bl	fn_08026380
	movs	r2, #0
	mov	r1, r2
	mov	r0, r4
	bl	fn_0802662a
	b.n	.L0800e7d8
.L0800e7d4:
	b.n	.L0800e920
.L0800e7d6:
	b.n	.L0800e97e
.L0800e7d8:
	mov	r0, r4
	bl	fn_08021f5c
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	str	r0, [r7, #0xc]		@ word 0x20005960
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800eadc		@ 0x0802f0d8
	ldr	r0, [r7, #0xc]
	bl	fn_080266ac
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	bl	rgb_to_565_0801d792
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r7, #0xc]
	b.n	.L0800e808
.L0800e806:
	b.n	.L0800ef68
.L0800e808:
	bl	fn_08026694
	ldr	r1, .L0800eacc
	ldr.w	r0, [r5, #0xbe0]	@ lang
	adds	r1, #0x30		@ 0x2000003c
	ldr.w	r1, [r1, r0, lsl #2]
	ldr	r0, [r7, #0xc]
	bl	fn_0802285c
	ldrb	r0, [r6, #0]		@ byte M
	cmp	r0, #0
	beq	.L0800e920
	ldr	r0, [r6, #0xc]
	bl	fn_08023678
	mov	r6, r0
	movs	r2, #0x78
	movs	r1, #0xdc
	bl	fn_080263a8
	mov	r7, r10
	mov	r3, r10			@ y = -20
	movs	r2, #0
	movs	r1, #9
	mov	r0, r6
	bl	fn_08023170
	movs	r2, #0
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d792
	mov	r1, r0
	movs	r2, #0
	mov	r0, r6
	bl	fn_0802657a
	movs	r2, #0
	movs	r1, #5
	mov	r0, r6
	bl	fn_08026680
	movs	r2, #0
	movs	r1, #1
	mov	r0, r6
	bl	fn_080265be
	movs	r2, #0xff
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d792	@ white
	mov	r1, r0
	movs	r2, #0
	mov	r0, r6
	bl	fn_0802659c
	movs	r1, #0
	mov	r0, r6
	bl	fn_08026380
	movs	r2, #0
	mov	r1, r2
	mov	r0, r6
	bl	fn_0802662a
	mov	r0, r6
	bl	fn_08021f5c
	mov	r4, r0
	mov	r3, r7
	movs	r2, #0
	movs	r1, #9
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800eae0		@ 0x0802ce5c
	mov	r0, r4
	bl	fn_080266ac
	ldr	r1, .L0800eacc
	ldr.w	r0, [r5, #0xbe0]
	adds	r1, #0x38		@ 0x20000044
	ldr.w	r1, [r1, r0, lsl #2]
	mov	r0, r4
	bl	fn_0802285c
	movs	r1, #0xc8
	mov	r0, r4
	bl	fn_080266d4
	movs	r1, #0
	mov	r0, r4
	bl	fn_080227e4
	movs	r2, #0
	movs	r1, #2
	mov	r0, r4
	bl	fn_0802668a
	mov	r0, r6
	bl	fn_08023678
	mov	r7, r0			@ button b1
	mov	r0, r6
	bl	fn_08023678
	mov	r6, r0			@ button b2
	movs	r2, #0x1a
	movs	r1, #0x30
	mov	r0, r7
	bl	fn_080263a8
	movs	r2, #0x1a
	movs	r1, #0x30
	mov	r0, r6
	bl	fn_080263a8
	mvn	r4, #0xe		@ r4 = -15
	mov	r3, r4
	mvn	r2, #0x2c		@ x = -45
	movs	r1, #5
	mov	r0, r7
	bl	fn_08023170
	mov	r3, r4
	movs	r2, #0x2d
	movs	r1, #5
	mov	r0, r6
	bl	fn_08023170
	movs	r2, #0
	mov	r1, r2
	b.n	.L0800e922
.L0800e920:
	b.n	.L0800ef64
.L0800e922:
	mov	r0, r2
	bl	rgb_to_565_0801d792
	mov	r1, r0
	movs	r2, #0
	mov	r0, r7
	bl	fn_0802657a
	movs	r2, #0
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d792
	mov	r1, r0
	movs	r2, #0
	mov	r0, r6
	bl	fn_0802657a
	movs	r2, #0
	movs	r1, #5
	mov	r0, r7
	bl	fn_08026680
	movs	r2, #0
	movs	r1, #5
	mov	r0, r6
	bl	fn_08026680
	movs	r2, #0
	movs	r1, #1
	mov	r0, r7
	bl	fn_080265be
	movs	r2, #0
	movs	r1, #1
	mov	r0, r6
	bl	fn_080265be
	ldr.w	r0, [r5, #0xc38]	@ sel
	cmp	r0, #1
	beq	.L0800ea74
	movs	r2, #0xff
	mov	r1, r2
	mov	r0, r2
	b.n	.L0800f17c
.L0800e97e:
	@ mode 0
	ldr.w	r11, .L0800ead8		@ 0x20000194
	ldr.w	r9, .L0800ead0		@ 0x200058f0
	movs	r4, #0
	sub.w	r11, r11, #0x78		@ 0x2000011c
	add.w	r9, r9, #0x3c		@ 0x2000592c
	mov	r8, r7			@ r8 = 0x20005954
.L0800e992:
	ldr	r0, [r6, #0xc]
	bl	fn_0802122c
	str.w	r0, [r9, r4, lsl #2]	@ word 0x2000592c[i]
	ldr.w	r0, [r5, #0xc38]
	mov	r7, r9
	cmp	r0, r4
	bne	.L0800e9ae
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	b.n	.L0800e9b4
.L0800e9ae:
	movs	r2, #0x54
	mov	r1, r2
	mov	r0, r2
.L0800e9b4:
	bl	rgb_to_565_0801d792
	mov	r1, r0
	ldr.w	r0, [r7, r4, lsl #2]
	movs	r2, #0
	bl	fn_0802659c
	ldr.w	r0, [r7, r4, lsl #2]
	movs	r2, #0
	movs	r1, #2
	bl	fn_080265be
	movs	r2, #0
	ldr.w	r0, [r7, r4, lsl #2]
	mov	r1, r2
	bl	fn_0802662a
	ldr.w	r0, [r7, r4, lsl #2]
	bl	fn_08021f5c
	mov	r7, r8
	str.w	r0, [r8, r4, lsl #2]	@ word 0x20005954[i]
	movs	r2, #0
	ldr	r1, .L0800eae0		@ 0x0802ce5c
	bl	fn_080266ac
	ldr.w	r0, [r5, #0xc38]
	cmp	r0, r4
	bne	.L0800ea06
	ldrb	r0, [r6, #0]
	cbz	r0, .L0800ea06
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	b.n	.L0800ea0c
.L0800ea06:
	movs	r2, #0xff
	mov	r1, r2
	mov	r0, r2
.L0800ea0c:
	bl	rgb_to_565_0801d792
	mov	r1, r0
	ldr.w	r0, [r7, r4, lsl #2]
	movs	r2, #0
	bl	fn_08026694
	ldr.w	r0, [r5, #0xbe0]
	add.w	r1, r0, r0, lsl #2
	add.w	r0, r11, r1, lsl #2
	adr	r1, .L0800eae4		@ "%s"
	ldr.w	r2, [r0, r4, lsl #2]	@ word 0x2000011c[lang*5 + i]
	ldr.w	r0, [r7, r4, lsl #2]
	bl	fn_080228d0
	.inst.n	0x1c64			@ adds r4, r4, #1
	cmp	r4, #5
	blt	.L0800e992
	mov	r7, r9
	ldr	r1, .L0800eae8		@ 0x0804f850
	ldr.w	r0, [r9]
	bl	fn_08021c14
	ldr	r1, .L0800eae8
	ldr	r0, [r7, #4]
	bl	fn_08021c14
	ldr	r1, .L0800eaec		@ 0x0804d990
	ldr	r0, [r7, #8]
	bl	fn_08021c14
	ldr	r1, .L0800eaec
	ldr	r0, [r7, #0xc]
	bl	fn_08021c14
	ldr	r1, .L0800eaec
	ldr	r0, [r7, #0x10]
	bl	fn_08021c14
	mvn	r4, #0x26		@ r4 = -39
	mov	r3, r4
	mvn	r11, #0x4f		@ r11 = -80
	b.n	.L0800ea76
.L0800ea74:
	b.n	.L0800f1be
.L0800ea76:
	mov	r2, r11
	movs	r1, #9
	ldr	r0, [r7, #0]
	bl	fn_08023170
	mov	r3, r4
	movs	r2, #0x50
	movs	r1, #9
	ldr	r0, [r7, #4]
	bl	fn_08023170
	movs	r3, #0x3c
	mvn	r2, #0x67		@ x = -104
	movs	r1, #9
	ldr	r0, [r7, #8]
	bl	fn_08023170
	movs	r3, #0x3c
	movs	r2, #0
	movs	r1, #9
	ldr	r0, [r7, #0xc]
	bl	fn_08023170
	movs	r3, #0x3c
	movs	r2, #0x68
	movs	r1, #9
	ldr	r0, [r7, #0x10]
	bl	fn_08023170
	ldr	r0, [r7, #8]
	bl	fn_0802122c
	ldr	r4, .L0800ead0
	adds	r4, #0x50		@ 0x20005940
	str	r0, [r4, #0]
	ldr	r0, [r7, #0xc]
	bl	fn_0802122c
	str	r0, [r4, #4]
	b.n	.L0800eaf0
.L0800eac8:
	.word	0x2000057c
.L0800eacc:
	.word	0x2000000c
.L0800ead0:
	.word	0x200058f0
.L0800ead4:
	.word	d_0804cac0
.L0800ead8:
	.word	0x20000194
.L0800eadc:
	.word	d_0802f0d8
.L0800eae0:
	.word	d_0802ce5c
.L0800eae4:
	.asciz	"%s"
	.byte	0x00			@ padding
.L0800eae8:
	.word	d_0804f850
.L0800eaec:
	.word	d_0804d990
.L0800eaf0:
	ldr	r0, [r7, #0x10]
	bl	fn_0802122c
	str	r0, [r4, #8]
	ldr	r0, [r7, #0xc]
	bl	fn_0802122c
	str	r0, [r4, #0xc]
	ldr	r0, [r7, #0x10]
	bl	fn_0802122c
	str	r0, [r4, #0x10]
	ldr	r1, .L0800eef0
	ldr	r0, [r4, #0]
	bl	fn_08021c14
	ldr	r1, .L0800eef4
	ldr	r0, [r4, #4]
	bl	fn_08021c14
	ldr	r1, .L0800eef8
	ldr	r0, [r4, #8]
	bl	fn_08021c14
	ldr.w	r0, [r5, #0xbf4]	@ word 0x20001170
	cmp	r0, #0
	ldr	r0, [r4, #0xc]
	beq	.L0800eb2e
	ldr	r1, .L0800eefc
	b.n	.L0800eb30
.L0800eb2e:
	ldr	r1, .L0800ef00
.L0800eb30:
	bl	fn_08021c14
	ldr.w	r0, [r5, #0xbf8]	@ word 0x20001174
	cmp	r0, #0
	ldr	r0, [r4, #0x10]
	beq	.L0800eb42
	ldr	r1, .L0800eefc
	b.n	.L0800eb44
.L0800eb42:
	ldr	r1, .L0800ef00
.L0800eb44:
	bl	fn_08021c14
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	bl	rgb_to_565_0801d792
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r4, #0]
	bl	fn_080265dc
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	bl	rgb_to_565_0801d792
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r4, #4]
	bl	fn_080265dc
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	bl	rgb_to_565_0801d792
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r4, #8]
	bl	fn_080265dc
	ldr.w	r0, [r5, #0xc38]
	cmp	r0, #2
	bne	.L0800eb94
	ldrb	r0, [r6, #0]
	cbz	r0, .L0800eb94
	movs	r1, #0xff
	b.n	.L0800eb96
.L0800eb94:
	movs	r1, #0
.L0800eb96:
	movs	r2, #0
	ldr	r0, [r4, #0]
	bl	fn_080265f4
	ldr.w	r0, [r5, #0xc38]
	cmp	r0, #3
	bne	.L0800ebae
	ldrb	r0, [r6, #0]
	cbz	r0, .L0800ebae
	movs	r1, #0xff
	b.n	.L0800ebb0
.L0800ebae:
	movs	r1, #0
.L0800ebb0:
	movs	r2, #0
	ldr	r0, [r4, #4]
	bl	fn_080265f4
	ldr.w	r0, [r5, #0xc38]
	mov	r9, r5
	cmp	r0, #4
	bne	.L0800ebca
	ldrb	r0, [r6, #0]
	cbz	r0, .L0800ebca
	movs	r1, #0xff
	b.n	.L0800ebcc
.L0800ebca:
	movs	r1, #0
.L0800ebcc:
	movs	r2, #0
	ldr	r0, [r4, #8]
	bl	fn_080265f4
	mov	r5, r10			@ r5 = -20
	mov	r3, r10
	mvn	r10, #0x21		@ r10 = -34
	mov	r2, r10
	movs	r1, #9
	ldr	r0, [r4, #0]
	bl	fn_08023170
	mov	r3, r5
	mov	r2, r10
	movs	r1, #9
	ldr	r0, [r4, #4]
	bl	fn_08023170
	mov	r3, r5
	mov	r2, r10
	movs	r1, #9
	ldr	r0, [r4, #8]
	bl	fn_08023170
	movs	r3, #0x10
	movs	r2, #0
	movs	r1, #9
	ldr	r0, [r4, #0xc]
	bl	fn_08023170
	movs	r3, #0x10
	movs	r2, #0
	movs	r1, #9
	ldr	r0, [r4, #0x10]
	bl	fn_08023170
	mvn	r5, #0x20		@ r5 = -33
	mov	r4, r8			@ r4 = 0x20005954
	mov	r3, r5
	movs	r2, #0
	movs	r1, #9
	ldr.w	r0, [r8]
	bl	fn_08023170
	mov	r3, r5
	movs	r2, #0
	movs	r1, #9
	ldr	r0, [r4, #4]
	bl	fn_08023170
	mvn	r8, #0x12		@ r8 = -19
	mov	r3, r8
	movs	r2, #0xa
	movs	r1, #9
	ldr	r0, [r4, #8]
	bl	fn_08023170
	mov	r3, r8
	movs	r2, #0xa
	movs	r1, #9
	ldr	r0, [r4, #0xc]
	bl	fn_08023170
	mov	r3, r8
	movs	r2, #0xa
	movs	r1, #9
	ldr	r0, [r4, #0x10]
	bl	fn_08023170
	mov	r8, r7
	ldr	r0, [r7, #8]
	bl	fn_08021f5c
	ldr	r4, .L0800ef04		@ 0x20005968
	str	r0, [r4, #0]
	ldr	r0, [r7, #0xc]
	bl	fn_08021f5c
	str	r0, [r4, #4]
	ldr	r0, [r7, #0xc]
	bl	fn_08021f5c
	str	r0, [r4, #8]
	ldr	r0, [r7, #0x10]
	bl	fn_08021f5c
	str	r0, [r4, #0xc]
	ldr	r0, [r7, #0x10]
	bl	fn_08021f5c
	movs	r7, #0
	str	r0, [r4, #0x10]
.L0800ec8c:
	ldr.w	r0, [r4, r7, lsl #2]
	movs	r2, #0
	ldr	r1, .L0800ef08		@ 0x0802ce5c
	bl	fn_080266ac
	.inst.n	0x1c7f			@ adds r7, r7, #1
	cmp	r7, #5
	blt	.L0800ec8c
	movs	r3, #0x10
	movs	r2, #0
	movs	r1, #9
	ldr	r0, [r4, #0]
	bl	fn_08023170
	movs	r3, #0x10
	mov	r2, r5			@ x = -33
	movs	r1, #9
	ldr	r0, [r4, #4]
	bl	fn_08023170
	movs	r3, #0x11
	movs	r2, #0x21
	movs	r1, #9
	ldr	r0, [r4, #8]
	bl	fn_08023170
	movs	r3, #0x10
	mov	r2, r5
	movs	r1, #9
	ldr	r0, [r4, #0xc]
	bl	fn_08023170
	movs	r3, #0x11
	movs	r2, #0x21
	movs	r1, #9
	ldr	r0, [r4, #0x10]
	bl	fn_08023170
	ldr	r1, .L0800ef0c		@ 0x20000144
	ldr.w	r0, [r9, #0xbe0]	@ lang
	add.w	r0, r1, r0, lsl #3
	ldr.w	r1, [r9, #0xbf0]	@ word 0x2000116c
	ldr.w	r2, [r0, r1, lsl #2]	@ word 0x20000144[lang*2 + word 0x2000116c]
	adr.w	r1, .L0800eae4		@ "%s"
	add.w	r5, r9, #0xbe0		@ r5 = address of lang
	ldr	r0, [r4, #0]
	bl	fn_080228d0
	ldr	r7, .L0800ef0c
	ldr	r0, [r5, #0]
	adds	r7, #0x10		@ 0x20000154
	ldr.w	r2, [r7, r0, lsl #3]	@ word 0x20000154[lang*2]
	adr.w	r1, .L0800eae4
	ldr	r0, [r4, #4]
	bl	fn_080228d0
	ldr	r0, [r5, #0]
	add.w	r0, r7, r0, lsl #3
	ldr	r2, [r0, #4]		@ word 0x20000158[lang*2]
	adr.w	r1, .L0800eae4
	ldr	r0, [r4, #8]
	bl	fn_080228d0
	ldr	r0, [r5, #0]
	ldr.w	r2, [r7, r0, lsl #3]
	adr.w	r1, .L0800eae4
	ldr	r0, [r4, #0xc]
	bl	fn_080228d0
	ldr	r0, [r5, #0]
	add.w	r0, r7, r0, lsl #3
	ldr	r2, [r0, #4]
	adr.w	r1, .L0800eae4
	sub.w	r5, r5, #0xbe0		@ r5 = 0x2000057c again
	ldr	r0, [r4, #0x10]
	bl	fn_080228d0
	mov	r9, r8
	mov	r7, r8
	ldr.w	r0, [r8]
	bl	fn_08021f5c
	ldr	r4, .L0800ef04
	adds	r4, #0x14		@ 0x2000597c
	str	r0, [r4, #0]
	ldr	r0, [r7, #0]
	bl	fn_08021f5c
	str	r0, [r4, #4]
	ldr	r0, [r7, #0]
	bl	fn_08021f5c
	str	r0, [r4, #8]
	ldr	r0, [r7, #0]
	bl	fn_08021f5c
	str	r0, [r4, #0xc]
	ldr	r0, [r7, #0]
	bl	fn_08021f5c
	str	r0, [r4, #0x10]
	ldr	r0, [r7, #4]
	bl	fn_08021f5c
	str	r0, [r4, #0x14]
	ldr	r0, [r7, #4]
	bl	fn_08021f5c
	str	r0, [r4, #0x18]
	ldr	r0, [r7, #4]
	bl	fn_08021f5c
	str	r0, [r4, #0x1c]
	ldr	r0, [r7, #0]
	bl	fn_08021f5c
	str	r0, [r6, #0x14]		@ word 0x20000020
	mov	r8, r6
	ldr	r0, [r7, #4]
	bl	fn_08021f5c
	mov	r10, r0
	movs	r6, #0
.L0800eda4:
	movs	r2, #0
	ldr.w	r0, [r4, r6, lsl #2]
	ldr	r1, .L0800ef10		@ 0x0802f5e8
	bl	fn_080266ac
	.inst.n	0x1c76			@ adds r6, r6, #1
	cmp	r6, #8
	blt	.L0800eda4
	movs	r6, #0
	mov.w	r7, sp
.L0800edbc:
	ldr.w	r0, [r9, r6, lsl #2]
	bl	fn_08023678
	movs	r2, #3
	str.w	r0, [r7, r6, lsl #2]
	mov	r1, r2
	bl	fn_080263a8
	movs	r2, #0
	ldr.w	r0, [r7, r6, lsl #2]
	mov	r1, r2
	bl	fn_08026680
	movs	r2, #0
	ldr.w	r0, [r7, r6, lsl #2]
	mov	r1, r2
	bl	fn_080265be
	movs	r2, #0xff
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d792
	mov	r1, r0
	ldr.w	r0, [r7, r6, lsl #2]
	movs	r2, #0
	bl	fn_0802657a
	ldr.w	r0, [r7, r6, lsl #2]
	movs	r1, #0
	bl	fn_08026380
	.inst.n	0x1c76			@ adds r6, r6, #1
	cmp	r6, #2
	blt	.L0800edbc
	movs	r3, #0x12
	mvn	r2, #0x77		@ x = -120
	movs	r1, #8
	ldr	r0, [r4, #0]
	bl	fn_08023170
	movs	r3, #0x12
	mvn	r2, #0x63		@ x = -100
	movs	r1, #8
	ldr	r0, [r4, #4]
	bl	fn_08023170
	movs	r3, #0x12
	mov	r2, r11			@ x = -80
	movs	r1, #8
	ldr	r0, [r4, #8]
	bl	fn_08023170
	movs	r3, #0x1d
	mvn	r2, #0x4d		@ x = -78
	movs	r1, #8
	ldr	r0, [sp, #0]
	bl	fn_08023170
	movs	r3, #0x12
	mvn	r2, #0x39		@ x = -58
	movs	r1, #8
	ldr	r0, [r4, #0xc]
	bl	fn_08023170
	movs	r3, #0x12
	mvn	r2, #0x25		@ x = -38
	movs	r1, #8
	ldr	r0, [r4, #0x10]
	bl	fn_08023170
	movs	r3, #0x12
	mvn	r2, #0x5e		@ x = -95
	movs	r1, #8
	ldr	r0, [r4, #0x14]
	bl	fn_08023170
	movs	r3, #0x12
	mvn	r2, #0x4a		@ x = -75
	movs	r1, #8
	ldr	r0, [r4, #0x18]
	bl	fn_08023170
	movs	r3, #0x1d
	mvn	r2, #0x48		@ x = -73
	movs	r1, #8
	ldr	r0, [sp, #4]
	bl	fn_08023170
	movs	r3, #0x12
	mvn	r2, #0x34		@ x = -53
	movs	r1, #8
	ldr	r0, [r4, #0x1c]
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800ef14		@ 0x0802f0d8
	mov	r4, r8			@ r4 = M
	ldr.w	r0, [r8, #0x14]		@ word 0x20000020
	bl	fn_080266ac
	movs	r2, #0
	ldr	r1, .L0800ef14
	mov	r0, r10
	bl	fn_080266ac
	adr	r1, .L0800ef18		@ "%%"
	mov	r0, r10
	bl	fn_080228d0
	movs	r3, #0x18
	movs	r2, #0x6c
	movs	r1, #7
	ldr	r0, [r4, #0x14]
	bl	fn_08023170
	movs	r3, #0x18
	movs	r2, #0x61
	movs	r1, #7
	mov	r0, r10
	bl	fn_08023170
	bl	fn_0800e4f8
	ldr.w	r0, [r5, #0xc38]	@ sel
	cbnz	r0, .L0800ef3a
	ldrb	r0, [r4, #0]		@ byte M
	cmp	r0, #0
	beq	.L0800ef64
	ldr.w	r0, [r5, #0xc3c]	@ idx
	cmp	r0, #3
	bge	.L0800ef1c
	add.w	r0, r0, r0, lsl #2
	lsls	r0, r0, #2		@ idx * 0x14
	b.n	.L0800ef2a
.L0800eef0:
	.word	d_0804cc40
.L0800eef4:
	.word	d_0804cb74
.L0800eef8:
	.word	d_0804da5c
.L0800eefc:
	.word	d_0804fce0
.L0800ef00:
	.word	d_0804fa98
.L0800ef04:
	.word	0x20005968
.L0800ef08:
	.word	d_0802ce5c
.L0800ef0c:
	.word	0x20000144
.L0800ef10:
	.word	d_0802f5e8
.L0800ef14:
	.word	d_0802f0d8
.L0800ef18:
	.asciz	"%%"
	.byte	0x00			@ padding
.L0800ef1c:
	cmp	r0, #5
	add.w	r0, r0, r0, lsl #2
	bge	.L0800ef2e
	movs	r1, #2
	add.w	r0, r1, r0, lsl #2	@ 2 + idx * 0x14
.L0800ef2a:
	movs	r1, #0x11
	b.n	.L0800ef36
.L0800ef2e:
	movs	r1, #3
	add.w	r0, r1, r0, lsl #2	@ 3 + idx * 0x14
	movs	r1, #0x18
.L0800ef36:
	bl	fn_0800e49c
.L0800ef3a:
	ldr.w	r0, [r5, #0xc38]
	cmp	r0, #1
	bne	.L0800ef64
	ldrb	r0, [r4, #0]
	cmp	r0, #0
	beq	.L0800ef64
	ldr.w	r0, [r5, #0xc3c]
	cmp	r0, #2
	add.w	r0, r0, r0, lsl #2
	bge	.L0800ef58
	movs	r1, #0x19
	b.n	.L0800ef5a
.L0800ef58:
	movs	r1, #0x1b
.L0800ef5a:
	add.w	r0, r1, r0, lsl #2	@ 25 or 27 + idx * 0x14
	movs	r1, #0x11
	bl	fn_0800e49c
.L0800ef64:
	pop.w	{r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}
.L0800ef68:
	@ mode 5: panel A, B, C, D
	ldr	r0, [r6, #0xc]
	bl	fn_08023678
	mov	r9, r0			@ A
	movs	r2, #0x82
	movs	r1, #0xc8
	bl	fn_080263a8
	mov	r3, r8			@ y = -10
	movs	r2, #0
	movs	r1, #9
	mov	r0, r9
	bl	fn_08023170
	movs	r2, #0
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d792	@ black
	mov	r1, r0
	movs	r2, #0
	mov	r0, r9
	bl	fn_0802657a
	movs	r2, #0
	movs	r1, #5
	mov	r0, r9
	bl	fn_08026680
	movs	r2, #0
	movs	r1, #1
	mov	r0, r9
	bl	fn_080265be
	movs	r2, #0
	mov	r1, r2
	movs	r0, #0xff
	bl	rgb_to_565_0801d792	@ red
	mov	r1, r0
	movs	r2, #0
	mov	r0, r9
	bl	fn_0802659c
	movs	r1, #0
	mov	r0, r9
	bl	fn_08026380
	movs	r2, #0
	mov	r1, r2
	mov	r0, r9
	bl	fn_0802662a
	mov	r0, r9
	bl	fn_08023678
	mov	r8, r0			@ B
	movs	r2, #0x32
	movs	r1, #0xb4
	bl	fn_080263a8
	mvn	r3, #0x1d		@ y = -30
	movs	r2, #0
	movs	r1, #9
	mov	r0, r8
	bl	fn_08023170
	movs	r2, #0
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d792	@ black
	mov	r1, r0
	movs	r2, #0
	mov	r0, r8
	bl	fn_0802657a
	movs	r2, #0
	mov	r1, r2
	mov	r0, r8
	bl	fn_08026680
	movs	r2, #0
	movs	r1, #1
	mov	r0, r8
	bl	fn_080265be
	movs	r2, #0
	mov	r1, r2
	movs	r0, #0xff
	bl	rgb_to_565_0801d792	@ red
	mov	r1, r0
	movs	r2, #0
	mov	r0, r8
	bl	fn_0802659c
	movs	r1, #0
	mov	r0, r8
	bl	fn_08026380
	movs	r2, #0
	mov	r1, r2
	mov	r0, r8
	bl	fn_0802662a
	mov	r0, r8
	bl	fn_08023678
	mov	r6, r0			@ C
	movs	r2, #0x32
	movs	r1, #0x50
	bl	fn_080263a8
	movs	r3, #0
	mov	r2, r3
	movs	r1, #7
	mov	r0, r6
	bl	fn_08023170
	movs	r2, #0
	mov	r1, r2
	movs	r0, #0xff
	bl	rgb_to_565_0801d792	@ red
	mov	r1, r0
	movs	r2, #0
	mov	r0, r6
	bl	fn_0802657a
	movs	r2, #0
	mov	r1, r2
	mov	r0, r6
	bl	fn_08026680
	movs	r2, #0
	mov	r1, r2
	mov	r0, r6
	bl	fn_080265be
	movs	r1, #0
	mov	r0, r6
	bl	fn_08026380
	mov	r0, r9
	bl	fn_08023678
	mov	r4, r0			@ D
	movs	r2, #0x28
	movs	r1, #0x50
	bl	fn_080263a8
	mvn	r3, #8			@ y = -9
	movs	r2, #0
	movs	r1, #5
	mov	r0, r4
	bl	fn_08023170
	movs	r2, #0x33
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d792	@ rgb(0x33,0x33,0x33)
	mov	r1, r0
	movs	r2, #0
	mov	r0, r4
	bl	fn_0802657a
	movs	r2, #0
	movs	r1, #5
	mov	r0, r4
	bl	fn_08026680
	movs	r2, #0
	movs	r1, #1
	mov	r0, r4
	bl	fn_080265be
	movs	r2, #0x54
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d792	@ rgb(0x54,0x54,0x54)
	mov	r1, r0
	movs	r2, #0
	mov	r0, r4
	bl	fn_0802659c
	movs	r1, #0
	mov	r0, r4
	bl	fn_08026380
	mov	r0, r6
	bl	fn_08021f5c
	str	r0, [r7, #0]		@ word 0x20005954 = child of C
	mov	r0, r8
	bl	fn_08021f5c
	str	r0, [r7, #4]		@ word 0x20005958 = child of B
	mov	r0, r9
	bl	fn_08021f5c
	str	r0, [r7, #8]		@ word 0x2000595c = child of A
	mov	r0, r4
	bl	fn_08021f5c
	str	r0, [r7, #0xc]		@ word 0x20005960 = child of D
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	ldr	r0, [r7, #0]
	bl	fn_08023170
	movs	r3, #0
	movs	r2, #0x28
	movs	r1, #9
	ldr	r0, [r7, #4]
	bl	fn_08023170
	movs	r3, #6
	movs	r2, #0
	movs	r1, #9
	ldr	r0, [r7, #8]
	bl	fn_08023170
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	ldr	r0, [r7, #0xc]
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800f27c		@ 0x0802f0d8
	ldr	r0, [r7, #0]
	bl	fn_080266ac
	movs	r2, #0
	ldr	r1, .L0800f27c
	ldr	r0, [r7, #4]
	bl	fn_080266ac
	movs	r2, #0
	ldr	r1, .L0800f280		@ 0x0802ce5c
	ldr	r0, [r7, #8]
	bl	fn_080266ac
	movs	r2, #0
	ldr	r1, .L0800f27c
	ldr	r0, [r7, #0xc]
	bl	fn_080266ac
	ldr	r1, .L0800f284		@ 0x20000034
	ldr.w	r0, [r5, #0xbe0]	@ lang
	add.w	r5, r5, #0xbe0		@ r5 = address of lang
	ldr.w	r1, [r1, r0, lsl #2]	@ word 0x20000034[lang]
	ldr	r0, [r7, #0]
	bl	fn_080228d0
	ldr	r0, [r5, #0]
	b.n	.L0800f17e
.L0800f17c:
	b.n	.L0800f1c4
.L0800f17e:
	ldr	r1, .L0800f284
	ldr	r4, .L0800f288		@ 0x2000457c
	add.w	r0, r0, r0, lsl #1
	adds	r1, #0x68		@ 0x2000009c
	add.w	r0, r1, r0, lsl #4
	ldr.w	r1, [r4, #0xb64]	@ word 0x200050e0
	ldr.w	r1, [r0, r1, lsl #2]	@ word 0x2000009c[lang*12 + word 0x200050e0]
	ldr	r0, [r7, #4]
	bl	fn_080228d0
	adr	r1, .L0800f28c		@ empty string
	ldr	r0, [r7, #8]
	bl	fn_080228d0
	ldr	r1, .L0800f284
	ldr	r0, [r5, #0]
	adds	r1, #0xc8		@ 0x200000fc
	add.w	r0, r1, r0, lsl #4
	ldr.w	r1, [r4, #0xb70]	@ word 0x200050ec
	ldr.w	r1, [r0, r1, lsl #2]	@ word 0x200000fc[lang*4 + word 0x200050ec]
	ldr	r0, [r7, #0xc]
	pop.w	{r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}	@ restores the original r2, r3
	b.w	fn_080228d0
.L0800f1be:
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
.L0800f1c4:
	bl	rgb_to_565_0801d792
	mov	r1, r0
	movs	r2, #0
	mov	r0, r7
	bl	fn_0802659c
	ldr.w	r0, [r5, #0xc38]
	cmp	r0, #1
	beq	.L0800f272
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
.L0800f1e0:
	bl	rgb_to_565_0801d792
	mov	r1, r0
	movs	r2, #0
	mov	r0, r6
	bl	fn_0802659c
	movs	r1, #0
	mov	r0, r7
	bl	fn_08026380
	movs	r1, #0
	mov	r0, r6
	bl	fn_08026380
	movs	r2, #0
	mov	r1, r2
	mov	r0, r7
	bl	fn_0802662a
	movs	r2, #0
	mov	r1, r2
	mov	r0, r6
	bl	fn_0802662a
	mov	r0, r7
	bl	fn_08021f5c
	mov	r4, r0
	mov	r0, r6
	bl	fn_08021f5c
	mov	r6, r0
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	mov	r0, r4
	bl	fn_08023170
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	mov	r0, r6
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800f27c
	mov	r0, r4
	bl	fn_080266ac
	movs	r2, #0
	ldr	r1, .L0800f27c
	mov	r0, r6
	bl	fn_080266ac
	ldr	r7, .L0800f290		@ 0x20000164
	ldr.w	r0, [r5, #0xbe0]
	ldr.w	r1, [r7, r0, lsl #3]	@ word 0x20000164[lang*2]
	mov	r0, r4
	bl	fn_0802285c
	ldr.w	r0, [r5, #0xbe0]
	add.w	r0, r7, r0, lsl #3
	ldr	r1, [r0, #4]		@ word 0x20000168[lang*2]
	mov	r0, r6
	pop.w	{r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}	@ restores the original r2, r3
	b.w	fn_0802285c
.L0800f272:
	movs	r2, #0xff
	mov	r1, r2
	mov	r0, r2
	b.n	.L0800f1e0
	.short	0x0000			@ padding
.L0800f27c:
	.word	d_0802f0d8
.L0800f280:
	.word	d_0802ce5c
.L0800f284:
	.word	0x20000034
.L0800f288:
	.word	0x2000457c
.L0800f28c:
	.byte	0x00, 0x00, 0x00, 0x00	@ empty string (format argument), zero bytes
.L0800f290:
	.word	0x20000164
