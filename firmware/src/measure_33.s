@ measure_33.s - measurement helpers: float range class, rate-code lookups, and the two-channel FFT phase/impedance routine (first part of the batch)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08009fe0 - classifies a float given in s0 by its raw bits.
@ Input: s0 is read as a 32-bit integer (vmov r0, s0). Returns r0 = 0 when the
@ bits are below 0x3e4ccccd (signed compare), 1 when they are below
@ 0x3f000000 (signed compare), else 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_08009fe0,"ax",%progbits
	.p2align 2
	.global fn_08009fe0
	.thumb_func
	.type fn_08009fe0, %function
fn_08009fe0:
	vmov	r0, s0
	ldr	r1, .L0800a000
	cmp	r0, r1
	bge.n	.L08009fee
	movs	r0, #0
	bx	lr
.L08009fee:
	vmov	r0, s0
	cmp.w	r0, #0x3f000000
	bge.n	.L08009ffc
	movs	r0, #1
	bx	lr
.L08009ffc:
	movs	r0, #2
	bx	lr
.L0800a000:
	.word	0x3e4ccccd

@ ----------------------------------------------------------------------------
@ fn_0800a004 - maps a value in r0 to an index.
@ Returns r0 = 0 for 100, 1 for 0x78, 2 for 1000, 3 for 10000 and 4 for any
@ other value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800a004,"ax",%progbits
	.p2align 2
	.global fn_0800a004
	.thumb_func
	.type fn_0800a004, %function
fn_0800a004:
	cmp	r0, #0x64
	beq.n	.L0800a022
	cmp	r0, #0x78
	beq.n	.L0800a026
	cmp.w	r0, #0x3e8
	beq.n	.L0800a02a
	sub.w	r1, r0, #0x2700
	subs	r1, #0x10		@ r1 = value - 10000
	beq.n	.L0800a01e
	movs	r0, #4
	bx	lr
.L0800a01e:
	movs	r0, #3
	bx	lr
.L0800a022:
	movs	r0, #0
	bx	lr
.L0800a026:
	movs	r0, #1
	bx	lr
.L0800a02a:
	movs	r0, #2
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0800a030 - returns a constant chosen by word 0x20001144.
@ No parameters. Reads word 0x20001144 (via the base 0x2000057c, offset
@ 0xbc8). Returns r0 = 0x068e7780 (110000000) when the word is 100, 0x78 or
@ 1000, r0 = 0x00a7d8c0 (11000000) when it is 10000, else r0 = 0x0010c8e0
@ (1100000).
@ Our build (.ifdef OWN, 0x0800A03A): bls.n for the first beq.n, so every word
@ up to 100 unsigned, 60 Hz among them, returns 110000000 (S2.12); the only other word below 100, an invalid loaded one, is repaired at
@ load (own/save.s load_fix, S2.11).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800a030,"ax",%progbits
	.p2align 2
	.global fn_0800a030
	.thumb_func
	.type fn_0800a030, %function
fn_0800a030:
	ldr	r0, .L0800a058
	ldr.w	r1, [r0, #0xbc8]	@ word 0x20001144
	ldr	r0, .L0800a05c
	cmp	r1, #0x64
.ifdef OWN
	bls.n	.L0800a050		@ 0x0800A03A: 60 and 100 (S2.12)
.else
	beq.n	.L0800a050
.endif
	cmp	r1, #0x78
	beq.n	.L0800a050
	cmp.w	r1, #0x3e8
	beq.n	.L0800a050
	sub.w	r0, r1, #0x2700
	subs	r0, #0x10		@ r0 = word - 10000
	beq.n	.L0800a052
	ldr	r0, .L0800a060
.L0800a050:
	bx	lr
.L0800a052:
	ldr	r0, .L0800a064
	bx	lr
	.short	0x0000			@ padding
.L0800a058:
	.word	0x2000057c
.L0800a05c:
	.word	0x068e7780
.L0800a060:
	.word	0x0010c8e0
.L0800a064:
	.word	0x00a7d8c0

@ ----------------------------------------------------------------------------
@ fn_0800a068 - two-channel FFT measurement: phase, magnitude ratio, derived
@ impedance values.
@ No parameters, no return value. r6 = 0x2000057c (literal 0x0800a468); frame
@ 0x610 bytes (magnitudes at sp, results at sp+0x200 and sp+0x204, complex
@ array at sp+0x208, loop index at sp+0x608); d8-d11 saved.
@ Returns early (0x0800a182 -> 0x0800a270) unless word 0x20001168 is 1, 2 or
@ 3, when fn_08007e24 returns 0, when byte 0x200011c4 is not 0 or when word
@ 0x200011a4 is not 0.
@ When word 0x2000120c > 200 (unsigned) sets word 0x20001208 = 1; calls
@ fn_08007f84, fn_08007fd4 and fn_0800b20c.
@ When fn_0800b20c returns 0 and word 0x20001208 is 0: byte 0x200011c4 = 1 and
@ a wait loop (0x0800a0d0) until the byte is 0, then (0x0800a268)
@ fn_08007efc(), byte 0x200011c4 = 1, return. The decompiler treats the byte as
@ ordinary memory; the loop waits for another context to clear it.
@ Otherwise calls fn_08007f38 and fn_0800b000; when it returns 0 and word
@ 0x20001208 is 0 the same wait (0x0800a260), fn_08007efc(), byte = 1, return.
@ Otherwise: byte 0x200011c4 = 1, word 0x2000120c = 0; for each of the buffers
@ 0x20005a38 then 0x20005b38 converts the 128 signed halfwords to floats (real
@ part; imaginary part 0.0 from the literal 0x0800a470) into the 128 float
@ pairs at sp+0x208, transforms them with fn_080069dc(literal 0x0800a474,
@ array, 0, 1), writes the 128 magnitudes with complex_magnitude_f32(array, sp,
@ 128), sets magnitude[0] = 0.0, finds the maximum of the first 0x40 magnitudes
@ with float_array_max_with_index(sp, 0x40, result pointer, index pointer
@ sp+0x608) (maximum to sp+0x200 for the first buffer, sp+0x204 for the
@ second). Phase of each buffer = float(double_divide(double_multiply(
@ fn_08010700(imaginary part, real part of the maximum bin, both converted by
@ float_to_double), 180.0), literal double 0x400921fb60000000)) via
@ double_to_float.
@ Stores phase(first) - phase(second) to 0x20005094 and wraps it: above 180.0
@ (signed compare with 0x43340000) minus 360.0, below -180.0 (unsigned compare
@ with 0xc3340000) plus 360.0.
@ Stores to 0x20005090: float(word [0x0802aeec + 4 * byte 0x200011c8]) *
@ float(byte [0x0802aee4 + byte 0x200011c6]) / float(byte [0x0802aee4 + byte
@ 0x200011c5]) * (maximum of the first buffer / maximum of the second buffer);
@ then 0x20005090 = fn_08008ea8(0x20005090) and 0x20005094 =
@ fn_08008e40(0x20005094).
@ Returns when word 0x20001200 is 0; otherwise clears it, copies 0x20005090 to
@ 0x200050c4 and 0x20005094 to 0x200050cc, r7 = fn_080090a4(word 0x20001144,
@ float 0x20001138), s20 = fn_0800901c(...) and s19 = fn_08008f94(...), M =
@ word 0x20001168.
@ When M is 3 and word 0x200050e0 is 0 the next two steps are skipped;
@ otherwise 0x200050c4 = 0x200050c4 - float [r7], minus s20 when word
@ 0x200011a0 is nonzero; only when M is 1 the value is rescaled with the
@ breakpoints [r7 + 4k] (k = 0..10): s1 / [r7+4] * 0.01 below [r7+4], then
@ linear interpolations 0.01 + 0.09 * ..., 0.1 + 0.9 * ..., 1.0 + 9 * ...,
@ 10 + 90 * ..., 100 + 900 * ..., 1000 + 9000 * ..., 10000 + 90000 * ...,
@ 100000 + 900000 * ... over the successive breakpoint intervals, and
@ 1000000 + 9000000 * (s1 - [r7+0x24]) / ([r7+0x28] - [r7+0x24]) from
@ [r7+0x24] up (result stored at 0x200050c4).
@ Phase 0x200050cc: below -90.0 (unsigned compare with 0xc2b40000) becomes
@ (|p| - 90.0) / 3.0 - 90.0, above 90.0 becomes 90.0 - (p - 90.0) / 3.0.
@ x = 0x200050cc / 180.0 * 3.14159274; with Z = 0x200050c4, F1 = fn_08011780(x),
@ F2 = fn_08010900(x): 0x20005098 = F1 * Z, 0x200050a0 = F2 * Z, 0x2000509c =
@ 1.0 / (F1 / Z), 0x200050a4 = 1.0 / (F2 / Z); w = float(word 0x20001144) *
@ 6.2831855: 0x200050a8 = -1e9 / (w * 0x20005098), 0x200050ac = -1e9 / (w *
@ 0x2000509c), 0x200050b0 = 0x20005098 * 1e6 / w, 0x200050b4 = 0x2000509c *
@ 1e6 / w; 0x200050d0 = |0x20005098 / 0x200050a0|, 0x200050d4 = 1.0 / that
@ when it is above 0.0, else 0.0.
@ When word 0x20001154 is 0 and Z (signed bit compare) is below 1100000.0
@ (0x49864700), or word 0x20001154 is 1: word 0x200011ec = 0, 0x200050c8 =
@ 0x20005098, 0x200050b8 = 0x200050a0, 0x200050bc = 0x200050a8, 0x200050c0 =
@ 0x200050b0; otherwise word 0x200011ec = 1, 0x200050c8 = 0x20005098,
@ 0x200050b8 = 0x200050a4, 0x200050bc = 0x200050ac, 0x200050c0 = 0x200050b4.
@ When word 0x200011a0 is nonzero 0x200050bc = 0x200050bc - s19.
@ When word 0x20001208 is nonzero: 0x200050cc = -400.0 and 0x200050c4,
@ 0x200050c8, 0x200050b8, 0x200050bc, 0x200050c0, 0x200050d4, 0x200050d0 = 1e10.
@ Compares float(fn_0800a030() / 10, signed division) with 0x200050c4: below
@ it sets byte 0x2000000b = 1; otherwise when that byte is 1 clears it and
@ clears word 0x2000511c.
@ Word 0x20001178 = 1, 2 or 3 stores 0x200050b8, 0x200050bc or 0x200050c0 to
@ 0x200050dc; calls fn_0800f854, clears word 0x20001208 and returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800a068,"ax",%progbits
	.p2align 2
	.global fn_0800a068
	.thumb_func
	.type fn_0800a068, %function
fn_0800a068:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr	r6, .L0800a468		@ r6 = 0x2000057c
	vpush	{d8, d9, d10, d11}
	sub.w	sp, sp, #0x610
	ldr.w	r0, [r6, #0xbec]	@ word 0x20001168
	cmp	r0, #1
	beq.n	.L0800a086
	cmp	r0, #2
	beq.n	.L0800a086
	cmp	r0, #3
	bne.n	.L0800a182
.L0800a086:
	bl	fn_08007e24
	cmp	r0, #0
	beq.n	.L0800a182
	ldrb.w	r0, [r6, #0xc48]	@ byte 0x200011c4
	cmp	r0, #0
	bne.n	.L0800a182
	ldr.w	r0, [r6, #0xc28]	@ word 0x200011a4
	cmp	r0, #0
	bne.n	.L0800a182
	ldr.w	r0, [r6, #0xc90]	@ word 0x2000120c
	movs	r4, #1
	cmp	r0, #0xc8
	bls.n	.L0800a0ac
	str.w	r4, [r6, #0xc8c]	@ word 0x20001208 = 1
.L0800a0ac:
	bl	fn_08007f84
	bl	fn_08007fd4
	bl	fn_0800b20c
	cbnz	r0, .L0800a0c0
	ldr.w	r0, [r6, #0xc8c]	@ word 0x20001208
	cbz	r0, .L0800a0cc
.L0800a0c0:
	bl	fn_08007f38
	bl	fn_0800b000
	cbz	r0, .L0800a0da
	b.n	.L0800a0e2
.L0800a0cc:
	strb.w	r4, [r6, #0xc48]	@ byte 0x200011c4 = 1
.L0800a0d0:
	ldrb.w	r0, [r6, #0xc48]
	cmp	r0, #0
	bne.n	.L0800a0d0		@ wait until the byte is cleared
	b.n	.L0800a268
.L0800a0da:
	ldr.w	r0, [r6, #0xc8c]	@ word 0x20001208
	cmp	r0, #0
	beq.n	.L0800a1de
.L0800a0e2:
	mov	r9, r4
	strb.w	r4, [r6, #0xc48]	@ byte 0x200011c4 = 1
	movs	r5, #0
	ldr	r2, .L0800a46c		@ r2 = 0x20005a38 (first buffer)
	str.w	r5, [r6, #0xc90]	@ word 0x2000120c = 0
	add	r4, sp, #0x208		@ r4 = complex array
	vldr	s16, .L0800a470		@ s16 = 0.0 (imaginary part)
	str.w	r5, [sp, #0x608]	@ index = 0
	nop
.L0800a0fc:
	ldr.w	r0, [sp, #0x608]
	ldrsh.w	r1, [r2, r0, lsl #1]
	vmov	s0, r1
	add.w	r1, r4, r0, lsl #3
	.inst.n	0x1c40			@ adds r0, r0, #1
	vcvt.f32.s32	s0, s0
	cmp	r0, #0x80
	vstr	s0, [r1]		@ real part
	vstr	s16, [r1, #4]		@ imaginary part
	str.w	r0, [sp, #0x608]
	bcc.n	.L0800a0fc
	movs	r3, #1
	movs	r2, #0
	mov	r1, r4
	ldr	r0, .L0800a474
	bl	fn_080069dc
	movs	r2, #0x80
	mov	r1, sp
	add	r0, sp, #0x208
	bl	complex_magnitude_f32
	vstr	s16, [sp]		@ magnitude[0] = 0.0
	add.w	r3, sp, #0x608
	add	r2, sp, #0x200
	movs	r1, #0x40
	mov	r0, sp
	bl	float_array_max_with_index
	ldr.w	r0, [sp, #0x608]	@ index of the maximum
	add.w	r1, r4, r0, lsl #3
	ldrd	r0, r7, [r1]		@ r0 = real part, r7 = imaginary part
	bl	float_to_double
	vmov	d9, r0, r1
	mov	r0, r7
	bl	float_to_double
	vmov	d0, r0, r1
	vmov.f32	s2, s18
	vmov.f32	s3, s19
	bl	fn_08010700
	vldr	d10, .L0800a478
	vmov	r0, r1, d0
	vmov	r2, r3, d10
	b.n	.L0800a184
.L0800a182:
	b.n	.L0800a270
.L0800a184:
	bl	double_multiply
	vldr	d9, .L0800a480
	vmov	r2, r3, d9
	bl	double_divide
	bl	double_to_float
	vmov	s17, r0			@ s17 = phase of the first buffer
	ldr	r2, .L0800a488		@ r2 = 0x20005b38 (second buffer)
	str.w	r5, [sp, #0x608]	@ index = 0
	nop
.L0800a1a4:
	ldr.w	r0, [sp, #0x608]
	ldrsh.w	r1, [r2, r0, lsl #1]
	vmov	s0, r1
	add.w	r1, r4, r0, lsl #3
	.inst.n	0x1c40			@ adds r0, r0, #1
	vcvt.f32.s32	s0, s0
	cmp	r0, #0x80
	vstr	s0, [r1]		@ real part
	vstr	s16, [r1, #4]		@ imaginary part
	str.w	r0, [sp, #0x608]
	bcc.n	.L0800a1a4
	movs	r3, #1
	movs	r2, #0
	add	r1, sp, #0x208
	ldr	r0, .L0800a474
	bl	fn_080069dc
	movs	r2, #0x80
	mov	r1, sp
	add	r0, sp, #0x208
	b.n	.L0800a1e0
.L0800a1de:
	b.n	.L0800a25a
.L0800a1e0:
	bl	complex_magnitude_f32
	vstr	s16, [sp]		@ magnitude[0] = 0.0
	add.w	r3, sp, #0x608
	add	r2, sp, #0x204
	movs	r1, #0x40
	mov	r0, sp
	bl	float_array_max_with_index
	ldr.w	r0, [sp, #0x608]
	add.w	r1, r4, r0, lsl #3
	ldrd	r0, r4, [r1]
	bl	float_to_double
	vmov	d11, r0, r1
	mov	r0, r4
	bl	float_to_double
	vmov	d0, r0, r1
	vmov.f32	s2, s22
	vmov.f32	s3, s23
	bl	fn_08010700
	vmov	r2, r3, d10
	vmov	r0, r1, d0
	bl	double_multiply
	vmov	r2, r3, d9
	bl	double_divide
	bl	double_to_float
	vmov	s0, r0			@ s0 = phase of the second buffer
	ldr	r4, .L0800a48c		@ r4 = 0x20004d7c (0x20005090 = r4 + 0x314)
	ldr	r1, .L0800a490
	vsub.f32	s0, s17, s0
	vmov	r0, s0
	vstr	s0, [r4, #0x318]	@ 0x20005094 = phase difference
	vldr	s1, .L0800a494
	cmp	r0, r1
	ble.n	.L0800a27c
	vsub.f32	s0, s0, s1
	b.n	.L0800a28a
.L0800a25a:
	strb.w	r4, [r6, #0xc48]	@ byte 0x200011c4 = 1
	nop
.L0800a260:
	ldrb.w	r0, [r6, #0xc48]
	cmp	r0, #0
	bne.n	.L0800a260		@ wait until the byte is cleared
.L0800a268:
	bl	fn_08007efc
	strb.w	r4, [r6, #0xc48]	@ byte 0x200011c4 = 1
.L0800a270:
	add.w	sp, sp, #0x610
.L0800a274:
	vpop	{d8, d9, d10, d11}
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L0800a27c:
	vmov	r0, s0
	ldr	r1, .L0800a498
	cmp	r0, r1
	bls.n	.L0800a28e
	vadd.f32	s0, s0, s1
.L0800a28a:
	vstr	s0, [r4, #0x318]	@ 0x20005094
.L0800a28e:
	ldrb.w	r0, [r6, #0xc4c]	@ byte 0x200011c8
	ldr	r1, .L0800a49c
	ldr.w	r0, [r1, r0, lsl #2]
	ldrb.w	r1, [r6, #0xc4a]	@ byte 0x200011c6
	vmov	s0, r0
	vcvt.f32.u32	s1, s0
	ldr	r0, .L0800a4a0
	ldrb	r1, [r0, r1]
	vmov	s0, r1
	ldrb.w	r1, [r6, #0xc49]	@ byte 0x200011c5
	vcvt.f32.u32	s0, s0
	vmul.f32	s1, s1, s0
	ldrb	r0, [r0, r1]
	vldr	s3, [sp, #0x204]	@ maximum of the second buffer
	vmov	s0, r0
	vcvt.f32.u32	s2, s0
	vdiv.f32	s0, s1, s2
	vldr	s2, [sp, #0x200]	@ maximum of the first buffer
	vdiv.f32	s1, s2, s3
	vmul.f32	s0, s1, s0
	vstr	s0, [r4, #0x314]	@ 0x20005090
	bl	fn_08008ea8
	vstr	s0, [r4, #0x314]
	vldr	s0, [r4, #0x318]
	bl	fn_08008e40
	vstr	s0, [r4, #0x318]
	ldr.w	r0, [r6, #0xc84]	@ word 0x20001200
	cmp	r0, #0
	beq.n	.L0800a270
	str.w	r5, [r6, #0xc84]	@ word 0x20001200 = 0
	vldr	s1, [r4, #0x314]
	ldr.w	r8, .L0800a4a4
	vstr	s1, [r4, #0x348]	@ 0x200050c4 = 0x20005090
	vstr	s0, [r4, #0x350]	@ 0x200050cc = 0x20005094
	mov	r10, r6
	ldr.w	r0, [r6, #0xbc8]	@ word 0x20001144
	vldr	s0, [r8, #0x3bc]	@ float 0x20001138
	addw	r6, r6, #0xbc8
	bl	fn_080090a4
	mov	r7, r0
	vldr	s0, [r8, #0x3bc]
	ldr	r0, [r6]
	bl	fn_0800901c
	vmov.f32	s20, s0
	vldr	s0, [r8, #0x3bc]
	ldr	r0, [r6]
	bl	fn_08008f94
	ldr	r0, [r6, #0x24]		@ word 0x20001168
	vmov.f32	s19, s0
	add.w	r6, r8, #0x3800
	vldr	s2, .L0800a4a8
	vldr	s18, .L0800a4ac
	vmov.f32	s17, #1.0
	cmp	r0, #3
	bne.n	.L0800a358
	ldr.w	r1, [r6, #0xb64]	@ word 0x200050e0
	cmp	r1, #0
	beq.n	.L0800a43a
.L0800a358:
	vldr	s0, [r4, #0x348]
	vldr	s1, [r7]
	vsub.f32	s0, s0, s1
	vstr	s0, [r4, #0x348]
	ldr.w	r1, [r10, #0xc24]	@ word 0x200011a0
	cbz	r1, .L0800a376
	vsub.f32	s0, s0, s20
	vstr	s0, [r4, #0x348]
.L0800a376:
	cmp	r0, #1
	bne.n	.L0800a43a
	vmov.f32	s1, s0
	vldr	s0, [r7, #4]
	vldr	s3, .L0800a4b0
	vcmpe.f32	s1, s0
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a39a
	vdiv.f32	s4, s1, s0
	vmul.f32	s0, s4, s3
	b.n	.L0800a55c
.L0800a39a:
	vldr	s4, [r7, #8]
	vcmpe.f32	s1, s4
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a3c2
	vsub.f32	s1, s1, s0
	vldr	s5, .L0800a4b4
	vsub.f32	s4, s4, s0
	vmul.f32	s1, s1, s5
	vdiv.f32	s0, s1, s4
	vadd.f32	s0, s0, s3
	b.n	.L0800a55c
.L0800a3c2:
	vldr	s3, [r7, #0xc]
	vcmpe.f32	s1, s3
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a3ea
	vsub.f32	s0, s1, s4
	vldr	s1, .L0800a4b8
	vsub.f32	s3, s3, s4
	vmul.f32	s0, s0, s1
	vdiv.f32	s1, s0, s3
	vldr	s0, .L0800a4bc
	b.n	.L0800a462
.L0800a3ea:
	vldr	s0, [r7, #0x10]
	vcmpe.f32	s1, s0
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a412
	vsub.f32	s1, s1, s3
	vmov.f32	s4, #9.0
	vsub.f32	s3, s0, s3
	vmul.f32	s1, s1, s4
	vdiv.f32	s0, s1, s3
	vadd.f32	s0, s0, s17		@ + 1.0
	b.n	.L0800a55c
.L0800a412:
	vldr	s3, [r7, #0x14]
	vcmpe.f32	s1, s3
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a43c
	vsub.f32	s1, s1, s0
	vsub.f32	s3, s3, s0
	vmul.f32	s1, s1, s2
	vdiv.f32	s0, s1, s3
	vmov.f32	s1, #10.0
	vadd.f32	s0, s0, s1
	b.n	.L0800a55c
.L0800a43a:
	b.n	.L0800a560
.L0800a43c:
	vldr	s4, [r7, #0x18]
	vcmpe.f32	s1, s4
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a4c8
	vsub.f32	s0, s1, s3
	vldr	s1, .L0800a4c0
	vsub.f32	s3, s4, s3
	vmul.f32	s0, s0, s1
	vdiv.f32	s1, s0, s3
	vldr	s0, .L0800a4c4
.L0800a462:
	vadd.f32	s0, s1, s0
	b.n	.L0800a55c
.L0800a468:
	.word	0x2000057c
.L0800a46c:
	.word	0x20005a38
.L0800a470:
	.word	0x00000000
.L0800a474:
	.word	d_0804fcec
.L0800a478:
	.word	0x00000000, 0x40668000	@ double 180.0
.L0800a480:
	.word	0x60000000, 0x400921fb	@ double 0x400921fb60000000
.L0800a488:
	.word	0x20005b38
.L0800a48c:
	.word	0x20004d7c
.L0800a490:
	.word	0x43340000
.L0800a494:
	.word	0x43b40000
.L0800a498:
	.word	0xc3340000
.L0800a49c:
	.word	d_0802aeec
.L0800a4a0:
	.word	d_0802aee4
.L0800a4a4:
	.word	0x20000d7c
.L0800a4a8:
	.word	0x42b40000
.L0800a4ac:
	.word	0x49742400
.L0800a4b0:
	.word	0x3c23d70a
.L0800a4b4:
	.word	0x3db851ec
.L0800a4b8:
	.word	0x3f666666
.L0800a4bc:
	.word	0x3dcccccd
.L0800a4c0:
	.word	0x44610000
.L0800a4c4:
	.word	0x42c80000
.L0800a4c8:
	vldr	s3, [r7, #0x1c]
	vcmpe.f32	s1, s3
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a4f0
	vsub.f32	s0, s1, s4
	vldr	s1, .L0800a7a8
	vsub.f32	s3, s3, s4
	vmul.f32	s0, s0, s1
	vdiv.f32	s1, s0, s3
	vldr	s0, .L0800a7ac
	b.n	.L0800a462
.L0800a4f0:
	vldr	s4, [r7, #0x20]
	vcmpe.f32	s1, s4
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a518
	vsub.f32	s0, s1, s3
	vldr	s1, .L0800a7b0
	vsub.f32	s3, s4, s3
	vmul.f32	s0, s0, s1
	vdiv.f32	s1, s0, s3
	vldr	s0, .L0800a7b4
	b.n	.L0800a462
.L0800a518:
	vldr	s3, [r7, #0x24]
	vcmpe.f32	s1, s3
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a540
	vsub.f32	s0, s1, s4
	vldr	s1, .L0800a7b8
	vsub.f32	s3, s3, s4
	vmul.f32	s0, s0, s1
	vdiv.f32	s1, s0, s3
	vldr	s0, .L0800a7bc
	b.n	.L0800a462
.L0800a540:
	vldr	s0, [r7, #0x28]
	vldr	s4, .L0800a7c0
	vsub.f32	s1, s1, s3
	vsub.f32	s3, s0, s3
	vmul.f32	s1, s1, s4
	vdiv.f32	s0, s1, s3
	vadd.f32	s0, s0, s18
.L0800a55c:
	vstr	s0, [r4, #0x348]	@ 0x200050c4 = rescaled value
.L0800a560:
	vldr	s1, [r4, #0x350]	@ phase 0x200050cc
	ldr	r1, .L0800a7c4
	vmov	r0, s1
	vmov.f32	s0, #3.0
	cmp	r0, r1
	bls.n	.L0800a584
	vabs.f32	s1, s1
	vsub.f32	s1, s1, s2
	vdiv.f32	s3, s1, s0
	vsub.f32	s0, s3, s2
	b.n	.L0800a59a
.L0800a584:
	vmov	r0, s1
	ldr	r1, .L0800a7c8
	cmp	r0, r1
	ble.n	.L0800a59e
	vsub.f32	s1, s1, s2
	vdiv.f32	s3, s1, s0
	vsub.f32	s0, s2, s3
.L0800a59a:
	vstr	s0, [r4, #0x350]
.L0800a59e:
	vldr	s1, [r4, #0x350]
	vldr	s21, .L0800a7cc		@ 180.0
	vdiv.f32	s0, s1, s21
	vldr	s20, .L0800a7d0		@ 3.14159274
	vmul.f32	s0, s0, s20		@ x = phase / 180.0 * 3.14159274
	bl	fn_08011780
	vldr	s1, [r4, #0x348]
	vmul.f32	s0, s0, s1
	vstr	s0, [r4, #0x31c]	@ 0x20005098 = F1 * Z
	vldr	s1, [r4, #0x350]
	vdiv.f32	s0, s1, s21
	vmul.f32	s0, s0, s20
	bl	fn_08010900
	vldr	s1, [r4, #0x348]
	vmul.f32	s0, s0, s1
	vstr	s0, [r4, #0x324]	@ 0x200050a0 = F2 * Z
	vldr	s1, [r4, #0x350]
	vdiv.f32	s0, s1, s21
	vmul.f32	s0, s0, s20
	bl	fn_08011780
	vldr	s2, [r4, #0x348]
	vdiv.f32	s1, s0, s2
	vdiv.f32	s0, s17, s1
	vstr	s0, [r4, #0x320]	@ 0x2000509c = 1.0 / (F1 / Z)
	vldr	s0, [r4, #0x350]
	vdiv.f32	s1, s0, s21
	vmul.f32	s0, s1, s20
	bl	fn_08010900
	vldr	s3, [r4, #0x348]
	mov	r7, r10
	vdiv.f32	s1, s0, s3
	vdiv.f32	s4, s17, s1
	vstr	s4, [r4, #0x328]	@ 0x200050a4 = 1.0 / (F2 / Z)
	ldr.w	r0, [r10, #0xbc8]	@ word 0x20001144
	vmov	s0, r0
	vcvt.f32.s32	s1, s0
	vldr	s0, .L0800a7d4		@ 6.2831855
	vmul.f32	s2, s1, s0		@ w
	vldr	s1, [r4, #0x31c]
	vmul.f32	s2, s2, s1
	vldr	s7, .L0800a7d8		@ -1e9
	vmul.f32	s9, s1, s18
	vdiv.f32	s5, s7, s2
	vmov	s2, r0
	vcvt.f32.s32	s2, s2
	vmul.f32	s2, s2, s0
	vstr	s5, [r4, #0x32c]	@ 0x200050a8
	vldr	s8, [r4, #0x320]
	vmul.f32	s2, s2, s8
	vmul.f32	s8, s8, s18
	vdiv.f32	s6, s7, s2
	vmov	s2, r0
	vcvt.f32.s32	s2, s2
	vmul.f32	s2, s2, s0
	vdiv.f32	s7, s9, s2
	vmov	s2, r0
	vstr	s6, [r4, #0x330]	@ 0x200050ac
	vcvt.f32.s32	s2, s2
	vmul.f32	s2, s2, s0
	vdiv.f32	s0, s8, s2
	vstr	s7, [r4, #0x334]	@ 0x200050b0
	vstr	s0, [r4, #0x338]	@ 0x200050b4
	vldr	s8, [r4, #0x324]
	vdiv.f32	s2, s1, s8
	vabs.f32	s2, s2
	vstr	s2, [r4, #0x354]	@ 0x200050d0 = |0x20005098 / 0x200050a0|
	vabs.f32	s9, s2
	vcmpe.f32	s9, #0.0
	vmrs	APSR_nzcv, fpscr
	ble.n	.L0800a6bc
	vdiv.f32	s9, s17, s2
	vstr	s9, [r4, #0x358]	@ 0x200050d4 = 1.0 / 0x200050d0
	b.n	.L0800a6c0
.L0800a6bc:
	vstr	s16, [r4, #0x358]	@ 0x200050d4 = 0.0
.L0800a6c0:
	ldr.w	r0, [r7, #0xbd8]	@ word 0x20001154
	cbz	r0, .L0800a6cc
	cmp	r0, #1
	beq.n	.L0800a6d6
	b.n	.L0800a6ec
.L0800a6cc:
	vmov	r0, s3
	ldr	r1, .L0800a7dc
	cmp	r0, r1
	bge.n	.L0800a6ec
.L0800a6d6:
	str.w	r5, [r7, #0xc70]	@ word 0x200011ec = 0
	vstr	s1, [r4, #0x34c]	@ 0x200050c8
	vstr	s8, [r4, #0x33c]	@ 0x200050b8
	vstr	s5, [r4, #0x340]	@ 0x200050bc
	vstr	s7, [r4, #0x344]	@ 0x200050c0
	b.n	.L0800a700
.L0800a6ec:
	str.w	r9, [r7, #0xc70]	@ word 0x200011ec = 1
	vstr	s1, [r4, #0x34c]
	vstr	s4, [r4, #0x33c]
	vstr	s6, [r4, #0x340]
	vstr	s0, [r4, #0x344]
.L0800a700:
	ldr.w	r0, [r7, #0xc24]	@ word 0x200011a0
	cbz	r0, .L0800a712
	vldr	s0, [r4, #0x340]
	vsub.f32	s0, s0, s19
	vstr	s0, [r4, #0x340]
.L0800a712:
	ldr.w	r0, [r7, #0xc8c]	@ word 0x20001208
	cbz	r0, .L0800a740
	vldr	s0, .L0800a7e0		@ -400.0
	vstr	s0, [r4, #0x350]
	vldr	s0, .L0800a7e4		@ 1e10
	vstr	s0, [r4, #0x348]
	vstr	s0, [r4, #0x34c]
	vstr	s0, [r4, #0x33c]
	vstr	s0, [r4, #0x340]
	vstr	s0, [r4, #0x344]
	vstr	s0, [r4, #0x358]
	vstr	s0, [r4, #0x354]
.L0800a740:
	bl	fn_0800a030
	movs	r1, #0xa
	sdiv	r0, r0, r1
	vmov	s0, r0
	vldr	s1, [r4, #0x348]
	ldr	r0, .L0800a7e8
	vcvt.f32.s32	s0, s0
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a768
	strb.w	r9, [r0, #1]		@ byte 0x2000000b = 1
	b.n	.L0800a774
.L0800a768:
	ldrb	r1, [r0, #1]
	cmp	r1, #1
	bne.n	.L0800a774
	strb	r5, [r0, #1]		@ byte 0x2000000b = 0
	str.w	r5, [r6, #0xba0]	@ word 0x2000511c = 0
.L0800a774:
	ldr.w	r0, [r7, #0xbfc]	@ word 0x20001178
	cmp	r0, #1
	beq.n	.L0800a786
	cmp	r0, #2
	beq.n	.L0800a78c
	cmp	r0, #3
	beq.n	.L0800a7a2
	b.n	.L0800a794
.L0800a786:
	vldr	s0, [r4, #0x33c]
	b.n	.L0800a790
.L0800a78c:
	vldr	s0, [r4, #0x340]
.L0800a790:
	vstr	s0, [r4, #0x360]	@ 0x200050dc
.L0800a794:
	bl	fn_0800f854
	str.w	r5, [r7, #0xc8c]	@ word 0x20001208 = 0
	add.w	sp, sp, #0x610
	b.n	.L0800a274
.L0800a7a2:
	vldr	s0, [r4, #0x344]
	b.n	.L0800a790
.L0800a7a8:
	.word	0x460ca000
.L0800a7ac:
	.word	0x447a0000
.L0800a7b0:
	.word	0x47afc800
.L0800a7b4:
	.word	0x461c4000
.L0800a7b8:
	.word	0x495bba00
.L0800a7bc:
	.word	0x47c35000
.L0800a7c0:
	.word	0x4b095440
.L0800a7c4:
	.word	0xc2b40000
.L0800a7c8:
	.word	0x42b40000
.L0800a7cc:
	.word	0x43340000
.L0800a7d0:
	.word	0x40490fdb
.L0800a7d4:
	.word	0x40c90fdb
.L0800a7d8:
	.word	0xce6e6b28
.L0800a7dc:
	.word	0x49864700
.L0800a7e0:
	.word	0xc3c80000
.L0800a7e4:
	.word	0x501502f9
.L0800a7e8:
	.word	0x2000000a

@ ----------------------------------------------------------------------------
@ fn_0800a7ec - tracks a measured value in a 3-entry ring and pulses the
@ outputs on a stable reading; counts the two outcomes.
@ No parameters, no return value. r4 = 0x2000057c (literal 0x0800a9cc).
@ Returns unless word 0x20001168 is 2.
@ f = float at 0x200050dc; when float 0x200050c4 is above (fn_0800a030() / 10)
@ clears bytes 0x200001d4 (ring index) and 0x200001d5 (flag).
@ Stores f in the 3-entry float ring 0x2000599c at index 0x200001d4 (index
@ wraps at 3).
@ Returns when f / 100.0 is not above both |entry0 - entry1| and
@ |entry0 - entry2| or when byte 0x200001d5 is set; otherwise sets
@ 0x200001d5 = 1.
@ When float 0x20001188 <= float 0x200050d8 increments word 0x200050f4, else
@ word 0x200050f0 (the counter addresses are the base 0x2000117c + 0x3400 +
@ 0xb74 / 0xb78). Depending on word 0x2000116c (compared with 1 in the first
@ case, tested for 0 in the second) it then pulses the outputs: fn_08008350 on
@ 0x40010c00 with masks 0x2000 and 0x1000, gated by word 0x20001174, with
@ delays fn_08011c68 (0x96, 300) or fn_08008120 (200) gated by word
@ 0x20001170.
@ Finally calls fn_080228d0(word 0x2000020c, "%03d", word 0x200050f0) and then
@ fn_080228d0(word 0x20000210, "%03d", word 0x200050f4) as a tail call.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800a7ec,"ax",%progbits
	.p2align 2
	.global fn_0800a7ec
	.thumb_func
	.type fn_0800a7ec, %function
fn_0800a7ec:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr	r4, .L0800a9cc		@ r4 = 0x2000057c
	ldr.w	r0, [r4, #0xbec]	@ word 0x20001168
	cmp	r0, #2
	bne.n	.L0800a8e6
	bl	fn_0800a030
	movs	r1, #0xa
	sdiv	r0, r0, r1
	vmov	s0, r0
	add.w	r1, r4, #0x4800		@ r1 = 0x20004d7c
	movs	r2, #0
	vcvt.f32.s32	s0, s0
	vldr	s1, [r1, #0x348]	@ float 0x200050c4
	ldr	r5, .L0800a9d0		@ r5 = 0x200001d4
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a826
	strb	r2, [r5]		@ byte 0x200001d4 = 0
	strb	r2, [r5, #1]		@ byte 0x200001d5 = 0
.L0800a826:
	ldr	r0, .L0800a9d4		@ r0 = 0x2000599c (ring)
	ldrb	r3, [r5]
	vldr	s1, [r1, #0x360]	@ f = float 0x200050dc
	add.w	r6, r0, r3, lsl #2
	.inst.n	0x1c5b			@ adds r3, r3, #1
	uxtb	r3, r3
	vstr	s1, [r6]		@ ring[index] = f
	strb	r3, [r5]
	cmp	r3, #2
	bls.n	.L0800a842
	strb	r2, [r5]		@ index wraps to 0
.L0800a842:
	vldr	s2, .L0800a9d8		@ s2 = 100.0
	vdiv.f32	s0, s1, s2		@ s0 = f / 100.0
	vldmia	r0, {s1, s2}		@ s1 = entry0, s2 = entry1
	vsub.f32	s2, s1, s2
	vabs.f32	s2, s2
	vcmpe.f32	s2, s0
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a8e6
	vldr	s2, [r0, #8]		@ entry2
	vsub.f32	s1, s1, s2
	vabs.f32	s1, s1
	vcmpe.f32	s1, s0
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800a8e6
	ldrb	r0, [r5, #1]
	cmp	r0, #0
	bne.n	.L0800a8e6
	movs	r0, #1
	strb	r0, [r5, #1]		@ byte 0x200001d5 = 1
	ldr	r0, .L0800a9dc		@ r0 = 0x2000117c
	vldr	s0, [r1, #0x35c]	@ float 0x200050d8
	ldr	r7, .L0800a9e0		@ r7 = 0x40010c00
	vldr	s1, [r0, #0xc]		@ float 0x20001188
	mov.w	r8, #0x2000
	mov.w	r9, #0x1000
	vcmpe.f32	s0, s1
	add.w	r6, r0, #0x3400		@ r6 = 0x2000457c
	vmrs	APSR_nzcv, fpscr
.ifdef OWN
	bhi.n	.L0800a8e8		@ own build: fail only when deviation > tolerance, as the
					@ display decides OK (ble at 0x0800f960); unordered -> fail
.else
	bcs.n	.L0800a8e8		@ deviation >= tolerance: fail (the display shows OK at =)
.endif
	ldr.w	r0, [r6, #0xb74]	@ word 0x200050f0
	.inst.n	0x1c40			@ adds r0, r0, #1
	str.w	r0, [r6, #0xb74]
	ldr.w	r0, [r4, #0xbf0]	@ word 0x2000116c
	cmp	r0, #1
	bne.n	.L0800a9aa
	ldr.w	r0, [r4, #0xbf8]	@ word 0x20001174
	cbz	r0, .L0800a8d4
	movs	r2, #0
	mov	r1, r8
	mov	r0, r7
	bl	fn_08008350
	ldr.w	r0, [r4, #0xbf8]
	cbz	r0, .L0800a8d4
	movs	r2, #1
	mov	r1, r9
	mov	r0, r7
	bl	fn_08008350
.L0800a8d4:
	ldr.w	r0, [r4, #0xbf4]	@ word 0x20001170
	cbz	r0, .L0800a8e0
	movs	r0, #0xc8
	bl	fn_08008120
.L0800a8e0:
	mov.w	r0, #0x12c
	b.n	.L0800a986
.L0800a8e6:
	b.n	.L0800a9c6
.L0800a8e8:
	ldr.w	r0, [r6, #0xb78]	@ word 0x200050f4
	.inst.n	0x1c40			@ adds r0, r0, #1
	str.w	r0, [r6, #0xb78]
	ldr.w	r0, [r4, #0xbf0]	@ word 0x2000116c
	cbnz	r0, .L0800a974
	ldr.w	r0, [r4, #0xbf8]
	cbz	r0, .L0800a918
	movs	r2, #1
	mov	r1, r8
	mov	r0, r7
	bl	fn_08008350
	ldr.w	r0, [r4, #0xbf8]
	cbz	r0, .L0800a918
	movs	r2, #0
	mov	r1, r9
	mov	r0, r7
	bl	fn_08008350
.L0800a918:
	ldr.w	r0, [r4, #0xbf4]
	cbz	r0, .L0800a926
	movs	r0, #0xc8
	bl	fn_08008120
	b.n	.L0800a92c
.L0800a926:
	movs	r0, #0x96
	bl	fn_08011c68
.L0800a92c:
	ldr.w	r0, [r4, #0xbf8]
	cbz	r0, .L0800a94c
	movs	r2, #1
	mov	r1, r8
	mov	r0, r7
	bl	fn_08008350
	ldr.w	r0, [r4, #0xbf8]
	cbz	r0, .L0800a94c
	movs	r2, #1
	mov	r1, r9
	mov	r0, r7
	bl	fn_08008350
.L0800a94c:
	movs	r0, #0x96
	bl	fn_08011c68
	ldr.w	r0, [r4, #0xbf8]
	cbz	r0, .L0800a972
	movs	r2, #1
	mov	r1, r8
	mov	r0, r7
	bl	fn_08008350
	ldr.w	r0, [r4, #0xbf8]
	cbz	r0, .L0800a972
	movs	r2, #0
	mov	r1, r9
	mov	r0, r7
	bl	fn_08008350
.L0800a972:
	b.n	.L0800a976
.L0800a974:
	b.n	.L0800a9aa
.L0800a976:
	ldr.w	r0, [r4, #0xbf4]
	cbz	r0, .L0800a984
	movs	r0, #0xc8
	bl	fn_08008120
	b.n	.L0800a98a
.L0800a984:
	movs	r0, #0x96
.L0800a986:
	bl	fn_08011c68
.L0800a98a:
	ldr.w	r0, [r4, #0xbf8]
	cbz	r0, .L0800a9aa
	movs	r2, #1
	mov	r1, r8
	mov	r0, r7
	bl	fn_08008350
	ldr.w	r0, [r4, #0xbf8]
	cbz	r0, .L0800a9aa
	movs	r2, #1
	mov	r1, r9
	mov	r0, r7
	bl	fn_08008350
.L0800a9aa:
	adr	r1, .L0800a9e4		@ format "%03d"
	ldr.w	r2, [r6, #0xb74]	@ word 0x200050f0
	ldr	r0, [r5, #0x38]		@ word 0x2000020c
	bl	fn_080228d0
	ldr.w	r2, [r6, #0xb78]	@ word 0x200050f4
	ldr	r0, [r5, #0x3c]		@ word 0x20000210
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	adr	r1, .L0800a9e4
	b.w	fn_080228d0
.L0800a9c6:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
	.short	0x0000			@ padding
.L0800a9cc:
	.word	0x2000057c
.L0800a9d0:
	.word	0x200001d4
.L0800a9d4:
	.word	0x2000599c
.L0800a9d8:
	.word	0x42c80000
.L0800a9dc:
	.word	0x2000117c
.L0800a9e0:
	.word	0x40010c00
.L0800a9e4:
	.ascii	"%03d"
	.word	0x00000000		@ padding
