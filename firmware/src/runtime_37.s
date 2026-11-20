@ runtime_37.s - runtime batch 37: double-precision arctangent-style function fn_08010700, single-precision function fn_08010900 and double_power
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08010700 - two-argument double function. Parameters: doubles d0 and d1
@ (the code pushes them and reads them back from the stack: d0 low word r5 /
@ [sp+0x18], d0 high word r10-side [sp+0x1c], d1 at [sp+0x20]); returns the
@ double in d0.
@ When (|d1 high| | (d1 low != 0)) or (|d0 high| | (d0 low != 0)) is above
@ 0x7ff00000 it tail-branches to fn_08011a4c (d0 + d1).
@ d1 equal to 0x3ff0000000000000: result is fn_08013a24(d0).
@ Quadrant code = (d1 high >> 30 & 2) | (d0 high >> 31).
@ d0 zero: returns d0 for quadrant 0 or 1, 0x400921fb54442d18 for quadrant 2,
@ 0xc00921fb54442d18 for quadrant 3.
@ d1 zero: returns 0x3ff921fb54442d18 when d0 high is >= 0, otherwise
@ 0xbff921fb54442d18.
@ d1 infinite and d0 not infinite: returns the zero double at 0x080510a8
@ (quadrant 0), its negation (quadrant 1), 0x400921fb54442d18 (2) or
@ 0xc00921fb54442d18 (3).
@ d0 infinite and d1 not infinite: returns 0x3ff921fb54442d18 when d0 high is
@ >= 0, otherwise 0xbff921fb54442d18.
@ Both infinite: clears bit 30 of both high words (0x7ff00000 becomes
@ 0x3ff00000) and continues in the finite case.
@ Finite case: exponent difference (|d0 high| - |d1 high|) >> 20: above 0x3c
@ gives 0x3ff921fb54442d18; below -0x3c with d1 negative gives 0.0; otherwise
@ fn_08013a24(|d0 / d1|) with double_divide and clear_sign_bit_64.
@ Quadrant 0 returns the value, quadrant 1 negates it, quadrant 2 returns
@ 0x400921fb54442d18 - (value - 0x3ca1a62633145c07), quadrant 3 returns
@ (value - 0x3ca1a62633145c07) - 0x400921fb54442d18, through double_subtract
@ and double_reverse_subtract.
@ For quadrant 0 or 1 a zero value calls fn_080077ec and set_word_20000578(2).
@ ----------------------------------------------------------------------------
	.section .text.fn_08010700,"ax",%progbits
	.p2align 2
	.global fn_08010700
	.thumb_func
	.type fn_08010700, %function
fn_08010700:
	push {r4, r5, r6, lr}
	ldr r6, .L080108c0            @ r6 = 0x7ff00000
	vpush {d0, d1}
	vpush {d8, d9}
	sub sp, #8
	ldr.w ip, [sp, #0x24]         @ d1 high word
	ldrd r2, r3, [sp, #0x1c]      @ r2 = d0 high word, r3 = d1 low word
	rsbs r4, r3, #0
	bic r1, ip, #0x80000000       @ r1 = |d1 high|
	orrs r4, r3
	orr.w r4, r1, r4, lsr #31
	ldr r5, [sp, #0x18]           @ d0 low word
	bic r0, r2, #0x80000000       @ r0 = |d0 high|
	cmp r4, r6
	bhi.n .L08010738
	rsbs r4, r5, #0
	orrs r4, r5
	orr.w r4, r0, r4, lsr #31
	cmp r4, r6
	bls.n .L08010750
.L08010738:
	vldr d1, [sp, #0x20]          @ NaN input: tail call fn_08011a4c(d0, d1)
	vldr d0, [sp, #0x18]
	add sp, #8
	vpop {d8, d9}
	add sp, #0x10
	pop.w {r4, r5, r6, lr}
	b.w fn_08011a4c
.L08010750:
	sub.w r4, ip, #0x30000000     @ test d1 == 0x3ff0000000000000
	sub.w r4, r4, #0xff00000
	orrs r4, r3
	beq.n .L08010774
	movs r4, #2
	and.w r4, r4, ip, asr #30
	orr.w r4, r4, r2, lsr #31     @ r4 = quadrant code
	orrs r5, r0
	vldr d8, .L080108c8           @ d8 = 0x400921fb54442d18
	vldr d2, .L080108d0           @ d2 = 0xc00921fb54442d18
	beq.n .L08010782
	b.n .L080107a0
.L08010774:
	vldr d0, [sp, #0x18]          @ d1 == 1.0: result is fn_08013a24(d0)
	vmov r0, r1, d0
	bl fn_08013a24
	b.n .L08010808
.L08010782:
	cmp r4, #0                    @ d0 zero: quadrant 0 or 1 returns d0
	iteee ne
	cmpne r4, #1
	vldreq d0, [sp, #0x18]
	addeq sp, #8
	vpopeq {d8, d9}
	itt eq
	addeq sp, #0x10
	popeq {r4, r5, r6, pc}
	cmp r4, #2
	beq.n .L0801080e
	cmp r4, #3
	beq.n .L08010818
.L080107a0:
	orrs r3, r1
	vldr d1, .L080108d8           @ d1 = 0xbff921fb54442d18
	vldr d0, .L080108e0           @ d0 = 0x3ff921fb54442d18
	beq.n .L080107c2
	cmp r1, r6
	bne.n .L080107e2
	cmp r0, r6
	bne.n .L080107c8
	bic r1, r1, #0x40000000       @ both infinite: clear bit 30 of both high words
	bic r0, r0, #0x40000000
	str r1, [sp, #0x24]
	str r0, [sp, #0x1c]
	b.n .L080107e2
.L080107c2:
	cmp r2, #0                    @ d1 zero: +-pi/2 by the sign of d0 high
	bge.n .L080107f2
	b.n .L080107ea
.L080107c8:
	ldr r3, .L080108e8            @ d1 infinite, d0 finite: r3 = address 0x080510a8
.L080107ca:
	add r3, pc
	cmp r4, #0
	it eq
	vldreq d0, [r3]               @ quadrant 0: the zero double at 0x080510a8
	beq.n .L080107f2
	cmp r4, #1
	beq.n .L080107fc
	cmp r4, #2
	beq.n .L0801080e
	cmp r4, #3
	beq.n .L08010818
.L080107e2:
	cmp r0, r6
	bne.n .L08010822
	cmp r2, #0                    @ d0 infinite: +-pi/2 by the sign of d0 high
	bge.n .L080107f2
.L080107ea:
	vmov.f32 s0, s2
	vmov.f32 s1, s3
.L080107f2:
	add sp, #8                    @ common exit, result in d0
	vpop {d8, d9}
	add sp, #0x10
	pop {r4, r5, r6, pc}
.L080107fc:
	vldr d0, [r3]                 @ quadrant 1: negate the zero double
	vmov r0, r1, d0
	eor r1, r1, #0x80000000
.L08010808:
	vmov d0, r0, r1
	b.n .L080107f2
.L0801080e:
	vmov.f32 s0, s16              @ quadrant 2: d0 = 0x400921fb54442d18
	vmov.f32 s1, s17
	b.n .L080107f2
.L08010818:
	vmov.f32 s0, s4               @ quadrant 3: d0 = 0xc00921fb54442d18
	vmov.f32 s1, s5
	b.n .L080107f2
.L08010822:
	subs r0, r0, r1               @ finite case: exponent difference
	asrs r0, r0, #0x14
	vldr d9, .L080108f0           @ d9 = 0.0
	cmp r0, #0x3c
	it gt
	vstrgt d0, [sp]               @ difference above 0x3c: value = 0x3ff921fb54442d18
	bgt.n .L08010864
	cmp.w ip, #0
	itt lt
	cmnlt.w r0, #0x3c
	vstrlt d9, [sp]               @ d1 negative and difference below -0x3c: value = 0.0
	blt.n .L08010864
	vldr d0, [sp, #0x20]
	vmov r2, r3, d0
	vldr d0, [sp, #0x18]
	vmov r0, r1, d0
	bl double_divide
	bl clear_sign_bit_64
	bl fn_08013a24
	strd r0, r1, [sp]
.L08010864:
	cbz r4, .L08010894            @ quadrant 0: value as is
	cmp r4, #1
	beq.n .L0801088c
	cmp r4, #2
	vldr d0, .L080108f8           @ d0 = 0x3ca1a62633145c07
	vmov r2, r3, d0
	vldr d0, [sp]
	vmov r0, r1, d0
	beq.n .L080108b2
	bl double_subtract            @ quadrant 3: (value - 0x3ca1a62633145c07) - 0x400921fb54442d18
	vmov r2, r3, d8
	bl double_subtract
	b.n .L08010808
.L0801088c:
	ldr r0, [sp, #4]              @ quadrant 1: negate the value (flip the sign bit)
	eor r0, r0, #0x80000000
	str r0, [sp, #4]
.L08010894:
	vldr d0, [sp]
	vmov r2, r3, d9
	vmov r0, r1, d0
	bl fn_080077ec                @ compare the value with 0.0
	itt eq
	moveq r0, #2
	bleq set_word_20000578        @ zero value: set_word_20000578(2)
	vldr d0, [sp]
	b.n .L080107f2
.L080108b2:
	bl double_subtract            @ quadrant 2: 0x400921fb54442d18 - (value - 0x3ca1a62633145c07)
	vmov r2, r3, d8
	bl double_reverse_subtract
	b.n .L08010808
.L080108c0:
	.word 0x7ff00000
	.word 0x00000000              @ padding
.L080108c8:
	.word 0x54442d18, 0x400921fb  @ double 0x400921fb54442d18
.L080108d0:
	.word 0x54442d18, 0xc00921fb  @ double 0xc00921fb54442d18
.L080108d8:
	.word 0x54442d18, 0xbff921fb  @ double 0xbff921fb54442d18
.L080108e0:
	.word 0x54442d18, 0x3ff921fb  @ double 0x3ff921fb54442d18
.L080108e8:
	.word d_080510a8 - (.L080107ca + 4)
	.word 0x00000000              @ padding
.L080108f0:
	.word 0x00000000, 0x00000000  @ double 0.0
.L080108f8:
	.word 0x33145c07, 0x3ca1a626  @ double 0x3ca1a62633145c07

@ ----------------------------------------------------------------------------
@ fn_08010900 - single-precision function. Parameter: float in s0; returns
@ float in s0.
@ Tests: (bits << 1) >= 0x7e921fb6 selects the reduction path, otherwise
@ (bits << 1) < 0x73000000 gives quadrant code -1 and a larger value gives
@ code 0; (bits & 0x7fffffff) >= 0x46490e49 selects the fn_08011ae8
@ reduction.
@ Range reduction: x * 0.63661975, rounded with 8388608.0, quadrant =
@ rounded & 3 (stored at [sp]), then subtraction of 1.5703125, 0.0004837513,
@ 7.5495336e-08, 2.563344e-12 times the rounded value. Larger inputs call
@ fn_08011ae8 for the reduction.
@ With x2 = r*r: quadrant bit 0 clear gives 1.0 + x2*(-0.49999896 + x2*
@ (0.041656293 + x2*-0.0013597823)); quadrant bit 0 set gives r + r*x2*
@ (-0.16666651 + x2*(0.008331979 + x2*-0.00019495636)).
@ Negation: with bit 0 clear the result is negated when quadrant bit 1 is
@ set; with bit 0 set the result is negated when quadrant bit 1 is clear.
@ Quadrant code -1 with (bits << 1) < 0xff000000: returns 1.0.
@ Infinite input: calls set_word_20000578(1) and tail-branches to
@ fn_08011ac8; NaN input: tail-branches to float_add_to_self.
@ ----------------------------------------------------------------------------
	.section .text.fn_08010900,"ax",%progbits
	.p2align 2
	.global fn_08010900
	.thumb_func
	.type fn_08010900, %function
fn_08010900:
	vmov r1, s0                   @ r1 = bits of the argument
	push {r3, lr}
	ldr r2, .L08010a18            @ r2 = 0x7e921fb6
	mov r0, sp                    @ r0 = address of the quadrant word (for fn_08011ae8)
	cmp.w r2, r1, lsl #1
	bls.n .L08010962
	mov.w r0, #0x73000000
	cmp.w r0, r1, lsl #1
	ite ls
	movls r0, #0
	movhi.w r0, #0xffffffff
	str r0, [sp]
.L08010922:
	ldr r0, [sp]                  @ r0 = quadrant code
	cmp r0, #0
	blt.n .L080109ec
	vmul.f32 s1, s0, s0           @ s1 = x2
	tst.w r0, #1
	beq.n .L080109be
	tst.w r0, #2
	vldr s3, .L08010a1c
	vldr s2, .L08010a20
	vmls.f32 s2, s1, s3
	vldr s3, .L08010a24
	vmla.f32 s3, s1, s2
	vmul.f32 s2, s3, s1
	vmov.f32 s1, s0
	vmla.f32 s1, s0, s2
	it eq
	vnegeq.f32 s1, s1
	vmov.f32 s0, s1
	pop {r3, pc}
.L08010962:
	ldr r3, .L08010a28            @ r3 = 0x46490e49
	bic r2, r1, #0x80000000
	cmp r3, r2
	bls.n .L080109e6
	tst.w r1, #0x80000000
	vldr s1, .L08010a2c           @ 0.63661975
	vmul.f32 s2, s0, s1
	vldr s1, .L08010a30           @ 8388608.0
	ittee ne
	vsubne.f32 s2, s2, s1
	vaddne.f32 s1, s2, s1
	vaddeq.f32 s2, s2, s1
	vsubeq.f32 s1, s2, s1
	vcvt.s32.f32 s2, s1
	vmov r0, s2
	vldr s2, .L08010a34           @ 1.5703125
	and r0, r0, #3
	vmls.f32 s0, s1, s2
	vldr s2, .L08010a38           @ 0.0004837513
	str r0, [sp]
	vmls.f32 s0, s1, s2
	vldr s2, .L08010a3c           @ 7.5495336e-08
	vmls.f32 s0, s1, s2
	vldr s2, .L08010a40           @ 2.563344e-12
	vmls.f32 s0, s1, s2
	b.n .L08010922
.L080109be:
	vldr s2, .L08010a44
	vldr s0, .L08010a48
	tst.w r0, #2
	vmla.f32 s0, s1, s2
	vldr s2, .L08010a4c
	vmla.f32 s2, s1, s0
	vmov.f32 s0, #1.0
	vmla.f32 s0, s1, s2
	it ne
	vnegne.f32 s0, s0
	pop {r3, pc}
.L080109e6:
	bl fn_08011ae8
	b.n .L08010922
.L080109ec:
	vmov r0, s0
	lsls r0, r0, #1
	cmp.w r0, #0xff000000
	itt cc
	vmovcc.f32 s0, #1.0
	popcc {r3, pc}
	bne.n .L08010a10
	mov.w r0, #1
	bl set_word_20000578
	pop.w {r3, lr}
	b.w fn_08011ac8
.L08010a10:
	pop.w {r3, lr}
	b.w float_add_to_self
.L08010a18:
	.word 0x7e921fb6
.L08010a1c:
	.word 0x394c6d33
.L08010a20:
	.word 0x3c0882da
.L08010a24:
	.word 0xbe2aaaa0
.L08010a28:
	.word 0x46490e49
.L08010a2c:
	.word 0x3f22f983
.L08010a30:
	.word 0x4b000000
.L08010a34:
	.word 0x3fc90000
.L08010a38:
	.word 0x39fda000
.L08010a3c:
	.word 0x33a22000
.L08010a40:
	.word 0x2c34611a
.L08010a44:
	.word 0xbab23ab9
.L08010a48:
	.word 0x3d2a9fca
.L08010a4c:
	.word 0xbeffffdd

@ ----------------------------------------------------------------------------
@ double_power - x raised to y. Parameters: d0 = x, d1 = y (doubles); returns
@ x raised to y in d0. The prologue pushes r4-r8, r10, r11, lr, d0, d1 and
@ d8-d14 and subtracts 0x58; x is then read from [sp+0x90] (low word r10,
@ high word r5) and y from [sp+0x98] (low word r0, high word r4); r6 = r5 &
@ 0x7fffffff (|x| high), r8 = r4 & 0x7fffffff (|y| high); d9 = 1.0
@ (0x08010e78), d10 = +inf (0x7ff0000000000000, 0x08010e90), d8 = 0.0
@ (0x08010e98) until replaced by a sign factor.
@ Body range: 0x08010a50..0x0801169f (literal words in between; the double
@ 2.0 at 0x08011698..0x0801169f is read at 0x080115aa). The function at
@ 0x08011a60 (divide_zero_by_zero_double) is a function of its own.
@ Tests at 0x08010a7a..0x08010a9a: when ((x high << 1) + (x low != 0) +
@ 0x1fffff) mod 2^32 is below 0xfffff (unsigned), or the same sum with y
@ (+0x1fffff, y low != 0, y high << 1) is below 0xfffff, the code goes to
@ 0x08010ade, which reloads d0 and d1 and tail-branches to fn_08011a4c
@ (d0 + d1).
@ y == +-0 (|y| high | y low == 0, orrs at 0x08010a9c, beq 0x08010b94 then
@ b 0x08010bc8) returns d9 = 1.0 for every x, and x == 1.0 (x high ==
@ 0x3ff00000 with x low 0, 0x08010aaa) returns d9 = 1.0 through 0x08010bc8
@ for every y that passed the first NaN tests. A second pair of NaN tests
@ (0x08010ac2..0x08010adc: (high << 1) + (low != 0) above 0xffe00000 by cmn
@ #0x200000 / bhi, for x then y) leads to the same 0x08010ade exit.
@ r7 = y-integer class for x < 0 (0x08010af6..0x08010b46): 0 when x >= 0,
@ when |y| high >= 0x7ff00000, when |y| high < 0x3ff00000, or when y is not
@ an integer; 2 when |y| high >= 0x43400000; otherwise e = (|y| high >> 20) -
@ 0x3ff: for e > 0x14 the low word shifted right and left by 0x34-e must give
@ the low word back, for e <= 0x14 the low word must be 0 and the high word
@ shifted right and left by 0x14-e must give |y| high back; then r7 = 2 -
@ (shifted value & 1), so 1 for odd and 2 for even integers.
@ x = +-0 with y < 0 (0x08010b46..0x08010b5a): r0 = 2, set_word_20000578(2)
@ (stores 2 in the word 0x20000578), then b.w fn_08011a08 (1.0 divided by
@ 0.0 with double_divide) for x = +0 and for x = -0 with r7 != 1 (0x08010b5c);
@ for x = -0 with r7 = 1 (0x08010b72) the same call as bl and the sign bit of
@ the result is flipped (eor at 0x08010b80).
@ d10 = +inf and d8 = 0.0 are loaded (0x08010b96, 0x08010b9a); the following
@ cases apply only when y low == 0 (cmp r0,#0 / bne 0x08010c86 at
@ 0x08010b9e): y = +-inf (|y| high == 0x7ff00000): returns 1.0 when x == -1.0
@ (x high + 0x40100000 == 0, x low 0, 0x08010ba8), for |x| high < 0x3ff00000
@ returns the word at 0x080510a8 (0.0) when y > 0 and -y (+inf) when y < 0,
@ for |x| high >= 0x3ff00000 returns y when y > 0 and 0.0 when y < 0.
@ y low == 0 and |y| high == 0x3ff00000 (y = +-1): y > 0 returns x
@ (0x08010c88); y < 0: |x| high == 0 with x low nonzero gives fn_08011a80
@ (0x7000000000000000 squared, overflow) with the sign bit of x after
@ set_word_20000578(2); x = +-0 gives +inf with the sign of x (0x08010c32);
@ x = +-inf gives 0.0 with the sign of x (0x08010c52); other x with |x| high
@ below 0x7ff00000 gives 1.0/x (double_divide, 0x08010c78); x NaN returns x.
@ y low == 0 and |x| high below 0x7ff00000: y high == 0x40000000 returns x*x
@ (0x08010cb4, b.w 0x08011648, double_multiply); y high == 0x3fe00000 with x
@ high >= 0 returns fn_08029ac4(x) (0x08010ca6..0x08010cae); every other case
@ goes to 0x08010cca.
@ General part from 0x08010cca: ax = |x| (clear_sign_bit_64) stored at
@ [sp+0x38]; with x low == 0: |x| high == 0 (0x08010d38) returns 0.0 (d8)
@ except -0 with r7 = 1 which returns -0.0 (0x08010ea8); x = +-inf (|x| high
@ - 0x7ff00000 == 0, 0x08010d0a): x = +inf returns +inf (d10) for y >= 0 and
@ 0.0 for y < 0; x = -inf returns -inf (0x08010eb0) when y >= 0 and r7 = 1,
@ +inf when y >= 0 and r7 != 1, -0.0 when y < 0 and r7 = 1, 0.0 when y < 0
@ and r7 != 1; |x| high == 0x3ff00000 with x < 0: r7 = 0 goes to 0x08010d9e,
@ else returns int_to_double(1) when r7 == 2 and int_to_double(-1) otherwise.
@ 0x08010d66: when x < 0 and r7 == 0 (orrs at 0x08010d6c) goes to 0x08010d9e:
@ set_word_20000578(1) and tail branch divide_zero_by_zero_double (0.0
@ divided by 0.0 with double_divide). Otherwise d8 = d9 = 1.0, replaced by
@ -1.0 (word 0x08010eb8) when x < 0 and r7 == 1; r5 = 0.
@ |y| high <= 0x41e00000 (cmp at 0x08010d88, ble 0x08010e6e) goes to
@ 0x08010f8a; above it the thresholds 0x43f00000 (0x08010ec4) and 0x3fefffff
@ (0x08010ec8) choose overflow, underflow or the near-one path: |y| high >
@ 0x43f00000: |x| high > 0x3fefffff gives overflow for y > 0 and underflow
@ for y <= 0, |x| high <= 0x3fefffff gives overflow for y < 0 and underflow
@ for y >= 0; |y| high <= 0x43f00000: |x| high < 0x3fefffff gives underflow
@ for y >= 0 and overflow for y < 0, |x| high <= 0x3ff00000 goes to
@ 0x08010e24, above it overflow for y > 0 and underflow for y <= 0.
@ Overflow exit (0x08010dd0): set_word_20000578(2), fn_08011a80
@ (0x7000000000000000 squared) and the sign bit taken from d8 * d10
@ (double_multiply, bfi at 0x08010df2); underflow exit (0x08010dfe):
@ set_word_20000578(2), fn_08011aa0 (0x1000000000000000 squared) with the
@ sign bit of d8 (bfi at 0x08010e18).
@ Near-one path 0x08010e24: t = ax - 1.0 (double_subtract); w = t*t*(0.5 -
@ t*(0x3fd5555555555555 - t*0.25)) (constants 0x08010ed8, 0x08010ed0,
@ 0x08010ee0); d11 = t*0x3ff7154760000000 (0x08011308); d10 =
@ t*0x3e54ae0bf85ddf44 (0x08011318) - w*0x3ff71547652b82fe (0x08011310); t1 =
@ d11 + d10 with its low word cleared (strd r5 = 0 at 0x08010f66); t2 = d10 -
@ (t1 - d11); then b.w 0x080112cc with d0 = t2 and t1 at [sp+0x18].
@ Normal path 0x08010f8a: n = 0; when |x| high < 0x100000 ax is multiplied by
@ 0x4340000000000000 (0x08011320) and n = -53; n += (|x| high >> 20) - 0x3ff;
@ j = |x| high & 0xfffff; ax high is replaced by j | 0x3ff00000; k = 0 when
@ j <= 0x3988e, k = 1 when j < 0xbb67a (words 0x08011328, 0x0801132c),
@ otherwise k = 0 with the ax high word lowered by 0x100000 and n += 1.
@ With tables of two doubles indexed by k: 0x08050f88 (1.0, 1.5), 0x08050f98
@ (0.0, 0x3fe2b80340000000) and 0x08050fa8 (0.0, 0x3e4cfdeb43cfd006): u = ax -
@ table1[k]; v = 1.0 / (ax + table1[k]) (double_divide); s = u*v, s_h = s with
@ low word cleared; t_h has low word 0 and high word ((ax high >> 1) |
@ 0x20000000) + 0x80000 + (k << 18) (0x08011044..0x08011058); s_l = ((u -
@ s_h*t_h) - s_h*(ax - (t_h - table1[k]))) * v; q = s*s; P = horner_poly_f64
@ (0x08050fb8, 6, q) (6 coefficients 0x08050fb8..0x08050fe0); r = q*q*P + (s_h
@ + s)*s_l; t_h2 = (3.0 (0x08011340) + s_h*s_h + r) with low word cleared; p =
@ s_h*t_h2 + (s_l*t_h2 + (r - ((t_h2 - 3.0) - s_h*s_h))*s), p_h = p with low
@ word cleared, p_l = (that sum) - (p_h - s_h*t_h2).
@ z_h = p_h*0x3feec709e0000000 (0x08011348); z_l = p_h*0xbe3e2fe0145b01f5
@ (0x08011358) + p_l*0x3feec709dc3a03fd (0x08011350) + table3[k] (0x08050fa8);
@ n converted with int_to_double; t = (z_h + z_l) + table2[k] (0x08050f98) +
@ n; t1 = t with low word cleared; t2 = z_l - (((t1 - n) - table2[k]) - z_h);
@ falls into 0x080112cc.
@ 0x080112cc (common to both paths): y1 = y with low word cleared; p_l = y*t2
@ + (y - y1)*t1 (d10); p_h = y1*t1 stored at [sp+0x30]; z = p_l + p_h stored
@ at [sp+8], r4 = high word of z; limits on z high (signed): >= 0x40900000
@ (word 0x08011650) with z != 0x4090000000000000 goes to the overflow exit
@ 0x080113e4; z == 0x4090000000000000 calls fn_0800781c(p_l +
@ 0x3c971547652b82fe (word 0x08011658), z - p_h) and continues at 0x08011440
@ on bcs, else overflow; z high below 0x40900000: |z high| >= 0x4090cc00 (word
@ 0x08011660) goes to underflow except that z high == 0xc090cc00 with z low 0
@ calls fn_0800781c(z - p_h, p_l) (bls to the underflow exit 0x08010dfe, else
@ continues at 0x08011440).
@ 0x08011440: when |z high| > 0x3fe00000 (word 0x0801166c) r6 = integer part
@ of z: r0 = z high + (0x100000 >> ((|z high| >> 20) - 0x3ff + 1)), mask
@ 0xfffff (word 0x08011674) shifted by the exponent, r6 = ((r0 & 0xfffff) |
@ 0x100000) >> (0x14 - exponent) negated when z < 0; the double built from the
@ masked high word with low word 0 (zero double at 0x080510a8) is subtracted
@ from p_h; r6 = 0 otherwise.
@ Then t = (p_l + p_h) with low word cleared (p_h = value at [sp+0x30] after
@ the integer part is subtracted); u = t*0x3fe62e4300000000 (0x08011678); v =
@ (p_l - (t - p_h))*0x3fe62e42fefa39ef (0x08011688) + t*0xbe205c610ca86c39
@ (0x08011680); w = u + v; w2 = v - (w - u); q = w*w; P = horner_poly_f64
@ (0x08050fe8, 5, q) (5 coefficients 0x08050fe8..0x08051008); c = w - q*P;
@ result = 1.0 - (((w*c)/(c - 2.0 (0x08011698)) - (w2 + w*w2)) - w)
@ (double_divide, double_subtract, double_reverse_subtract).
@ Scaling: high word of the result + (r6 << 20); when that value >> 20 (asr)
@ is above 0 the high word is stored back (str.gt at 0x0801160c); otherwise
@ double_scale_by_power_of_two(result, r6) is called, classify_double
@ classifies it and a result of 4 calls fn_08011aa0 (0x08011622), then
@ double_scale_by_power_of_two(result, r6) again; finally double_multiply(d8,
@ result) (0x08011648, sign factor) and b.w 0x08010cc4 which moves r0:r1 to
@ d0 and returns through 0x08010b88 (add sp, vpop d8-d14, add sp, pop.w
@ {r4-r8,r10,r11,pc}).
@ ----------------------------------------------------------------------------
	.section .text.double_power,"ax",%progbits
	.p2align 2
	.global double_power
	.thumb_func
	.type double_power, %function
double_power:
	push.w {r4, r5, r6, r7, r8, r10, r11, lr}
	vpush {d0, d1}
	vpush {d8, d9, d10, d11, d12, d13, d14}
	sub sp, #0x58
	ldrd r5, r0, [sp, #0x94]      @ r5 = x high word, r0 = y low word
	ldr r4, [sp, #0x9c]           @ r4 = y high word
	ldr.w r10, [sp, #0x90]        @ r10 = x low word
	bic r6, r5, #0x80000000       @ r6 = |x| high
	bic r8, r4, #0x80000000       @ r8 = |y| high
	cmp.w r10, #0
	ite ne
	movne r1, #1
	moveq r1, #0
	add.w r2, r1, r5, lsl #1
	ldr r1, .L08010e70            @ r1 = 0x001fffff
	adds r3, r2, r1
	asrs r2, r1, #1               @ r2 = 0x000fffff
	cmp r3, r2
	bcc.n .L08010ade              @ x is NaN
	cmp r0, #0
	ite ne
	movne r3, #1
	moveq r3, #0
	add.w r3, r3, r4, lsl #1
	add r3, r1
	ldr r1, .L08010e74            @ r1 = 0x000fffff
	cmp r3, r1
	bcc.n .L08010ade              @ y is NaN
	orrs.w r1, r8, r0             @ |y| == 0 ?
	vldr d9, .L08010e78           @ d9 = 1.0
	beq.n .L08010b94
	ldr.w fp, .L08010e80          @ r11 = 0x3ff00000
	cmp r5, fp
	bne.n .L08010ab6
	cmp.w r10, #0
	bne.n .L08010ac0
	b.n .L08010bc8                @ x == 1.0: result 1.0
.L08010ab6:
	cmp.w r10, #0
	it eq
	moveq r1, #0
	beq.n .L08010ac2
.L08010ac0:
	movs r1, #1
.L08010ac2:
	add.w r1, r1, r5, lsl #1
	cmn.w r1, #0x200000
	bhi.n .L08010ade
	cmp r0, #0
	ite ne
	movne r1, #1
	moveq r1, #0
	add.w r1, r1, r4, lsl #1
	cmn.w r1, #0x200000
	bls.n .L08010af6
.L08010ade:
	vldr d1, [sp, #0x98]          @ NaN operand: tail call fn_08011a4c(d0, d1)
	vldr d0, [sp, #0x90]
	add sp, #0x58
	vpop {d8, d9, d10, d11, d12, d13, d14}
	add sp, #0x10
	pop.w {r4, r5, r6, r7, r8, r10, r11, lr}
	b.w fn_08011a4c
.L08010af6:
	movs r7, #0                   @ r7 = y-integer class
	cmp r5, #0
	itt lt
	ldrlt r1, .L08010e84          @ r1 = 0x7ff00000
	cmplt r8, r1
	bge.n .L08010b46
	ldr r1, .L08010e88            @ r1 = 0x43400000
	cmp r8, r1
	it ge
	movge r7, #2
	bge.n .L08010b46
	cmp fp, r8
	bgt.n .L08010b46
	ldr r1, .L08010e8c            @ r1 = 0xfffffc01 (-0x3ff)
	add.w r1, r1, r8, asr #20
	cmp r1, #0x14
	ble.n .L08010b2c
	rsb.w r2, r1, #0x34
	lsr.w r1, r0, r2
	lsl.w r2, r1, r2
	cmp r2, r0
	bne.n .L08010b46
	b.n .L08010b3e
.L08010b2c:
	cbnz r0, .L08010b46
	rsb.w r2, r1, #0x14
	lsr.w r1, r8, r2
	lsl.w r2, r1, r2
	cmp r2, r8
	bne.n .L08010b46
.L08010b3e:
	and r1, r1, #1
	rsb.w r7, r1, #2
.L08010b46:
	orrs.w r1, r6, r10            @ x == +-0 ?
	bne.n .L08010b96
	cmp r4, #0
	bge.n .L08010b96
	cmp r5, #0
	it ne
	cmpne r7, #2
	beq.n .L08010b5c
	cmp r7, #1
	beq.n .L08010b72
.L08010b5c:
	movs r0, #2
	bl set_word_20000578          @ set_word_20000578(2)
	add sp, #0x58
	vpop {d8, d9, d10, d11, d12, d13, d14}
	add sp, #0x10
	pop.w {r4, r5, r6, r7, r8, r10, r11, lr}
	b.w fn_08011a08               @ tail call: 1.0 / 0.0
.L08010b72:
	movs r0, #2
	bl set_word_20000578          @ set_word_20000578(2)
	bl fn_08011a08
	vmov r0, r1, d0
	eor r1, r1, #0x80000000       @ flip the sign bit of the result
	vmov d0, r0, r1
.L08010b88:
	add sp, #0x58                 @ common exit, result in d0
	vpop {d8, d9, d10, d11, d12, d13, d14}
	add sp, #0x10
	pop.w {r4, r5, r6, r7, r8, r10, r11, pc}
.L08010b94:
	b.n .L08010bc8
.L08010b96:
	vldr d10, .L08010e90          @ d10 = +inf
	vldr d8, .L08010e98           @ d8 = 0.0
	cmp r0, #0
	bne.n .L08010c86
	ldr r0, .L08010e84            @ r0 = 0x7ff00000
	cmp r8, r0
	bne.n .L08010bee
	add.w r0, r5, #0x40000000     @ y = +-inf: x == -1.0 ?
	adds.w r0, r0, #0x100000
	it eq
	cmpeq.w r10, #0
	beq.n .L08010bc8
	cmp fp, r6
	bgt.n .L08010bd2
	cmp r4, #0
	it ge
	vldrge d0, [sp, #0x98]
	bge.n .L08010b88
	b.n .L08010be4
.L08010bc8:
	vmov.f32 s0, s18              @ result 1.0 (d9)
	vmov.f32 s1, s19
	b.n .L08010b88
.L08010bd2:
	cmp r4, #0
	bge.n .L08010be4
	vldr d0, [sp, #0x98]
	vmov r0, r1, d0
	eor r1, r1, #0x80000000       @ -y
	b.n .L08010cc4
.L08010be4:
	ldr r0, .L08010ea0            @ r0 = distance to the zero double at 0x080510a8
.L08010be6:
	add r0, pc
	vldr d0, [r0]
	b.n .L08010b88
.L08010bee:
	cmp r8, fp
	bne.n .L08010c8e
	cmp r4, #0
	bge.n .L08010c88
	cbz r6, .L08010c04
	cmp r6, r0
	bne.n .L08010c72
	cmp.w r10, #0
	bne.n .L08010c88
	b.n .L08010c52
.L08010c04:
	cmp.w r10, #0
	beq.n .L08010c32
	movs r0, #2
	bl set_word_20000578          @ set_word_20000578(2)
	bl fn_08011a80
	vstr d0, [sp, #8]
	vldr d0, [sp, #0x90]
	vstr d0, [sp]
	vmov r0, s1
	ldr r1, [sp, #0xc]
	bfi r0, r1, #0, #31
	str r0, [sp, #0xc]
	vldr d0, [sp, #8]
	b.n .L08010b88
.L08010c32:
	vstr d10, [sp, #8]
	vldr d0, [sp, #0x90]
	vmov r1, s21
	vmov r0, s1
	vstr d0, [sp]
	bfi r0, r1, #0, #31
	str r0, [sp, #0xc]
	vldr d0, [sp, #8]
	b.n .L08010b88
.L08010c52:
	vstr d8, [sp, #8]
	vldr d0, [sp, #0x90]
	vmov r1, s17
	vmov r0, s1
	vstr d0, [sp]
	bfi r0, r1, #0, #31
	str r0, [sp, #0xc]
	vldr d0, [sp, #8]
	b.n .L08010b88
.L08010c72:
	bge.n .L08010c88
	vldr d0, [sp, #0x90]
	vmov r0, r1, d9
	vmov r2, r3, d0
	bl double_divide
	b.n .L08010cc4
.L08010c86:
	b.n .L08010cca
.L08010c88:
	vldr d0, [sp, #0x90]
	b.n .L08010b88
.L08010c8e:
	cmp r6, r0
	bge.n .L08010cca
	cmp.w r4, #0x40000000
	beq.n .L08010cb4
	sub.w r0, r4, #0x20000000
	subs.w r0, r0, #0x1fe00000
	bne.n .L08010cca
	cmp r5, #0
	blt.n .L08010cca
	vldr d0, [sp, #0x90]
	vmov r0, r1, d0
	bl fn_08029ac4
	b.n .L08010cc4
.L08010cb4:
	vldr d0, [sp, #0x90]
	vmov r2, r3, d0
	vmov r0, r1, d0
	b.w .L08011648                @ y == 2.0: x * x
.L08010cc4:
	vmov d0, r0, r1
	b.n .L08010b88
.L08010cca:
	vldr d0, [sp, #0x90]
	vmov r0, r1, d0
	bl clear_sign_bit_64
	cmp.w r10, #0
	strd r0, r1, [sp, #0x38]      @ ax = |x|
	bne.n .L08010d66
	vldr d0, .L08010ea8           @ d0 = -0.0
	cbz r6, .L08010d38
	sub.w r0, r6, #0x70000000
	subs.w r0, r0, #0xff00000
	beq.n .L08010d0a
	cmp r6, fp
	bne.n .L08010d66
	cmp r5, #0
	bge.n .L08010cfa
	cbz r7, .L08010d64
.L08010cfa:
	cmp r7, #2
	ite eq
	moveq r0, #1
	movne.w r0, #0xffffffff
	bl int_to_double
	b.n .L08010cc4
.L08010d0a:
	cmp r5, #0
	ble.n .L08010d12
	cmp r4, #0
	bge.n .L08010d2e
.L08010d12:
	cmp r5, #0
	ble.n .L08010d1a
	cmp r4, #0
	blt.n .L08010d5a
.L08010d1a:
	cmp r5, #0
	bge.n .L08010d4c
	cmp r4, #0
	blt.n .L08010d4c
	cmp r7, #1
	it eq
	vldreq d0, .L08010eb0         @ -inf
	beq.w .L08010b88
.L08010d2e:
	vmov.f32 s0, s20              @ +inf (d10)
	vmov.f32 s1, s21
	b.n .L08010b88
.L08010d38:
	cmp r7, #2
	it ne
	cmpne r5, #0
	beq.n .L08010d5a
	cmp r7, #1
	bne.n .L08010d5a
	cmp r5, #0
	blt.w .L08010b88
	b.n .L08010d5a
.L08010d4c:
	cmp r5, #0
	it lt
	cmplt r4, #0
	bge.n .L08010d66
	cmp r7, #1
	beq.w .L08010b88
.L08010d5a:
	vmov.f32 s0, s16              @ 0.0 (d8)
	vmov.f32 s1, s17
	b.n .L08010b88
.L08010d64:
	b.n .L08010d9e
.L08010d66:
	movs r0, #1
	add.w r0, r0, r5, asr #31
	orrs.w r1, r0, r7
	beq.n .L08010d9e
	subs r1, r7, #1
	vmov.f32 s16, s18             @ d8 = 1.0
	vmov.f32 s17, s19
	orrs r0, r1
	it eq
	vldreq d8, .L08010eb8         @ d8 = -1.0
	ldr r0, .L08010ec0            @ r0 = 0x41e00000
	movs r5, #0
	cmp r8, r0
	ble.n .L08010e6e
	ldr r1, .L08010ec4            @ r1 = 0x43f00000
	ldr r0, .L08010ec8            @ r0 = 0x3fefffff
	cmp r8, r1
	ble.n .L08010dbe
	cmp r0, r6
	blt.n .L08010db4
	cmp r4, #0
	blt.n .L08010dd0
	b.n .L08010dfe
.L08010d9e:
	movs r0, #1
	bl set_word_20000578          @ set_word_20000578(1)
	add sp, #0x58
	vpop {d8, d9, d10, d11, d12, d13, d14}
	add sp, #0x10
	pop.w {r4, r5, r6, r7, r8, r10, r11, lr}
	b.w divide_zero_by_zero_double
.L08010db4:
	cmp fp, r6
	bgt.n .L08010dbe
	cmp r4, #0
	bgt.n .L08010dd0
	b.n .L08010dfe
.L08010dbe:
	cmp r6, r0
	bge.n .L08010dc8
	cmp r4, #0
	bge.n .L08010dfe
	b.n .L08010dd0
.L08010dc8:
	cmp r6, fp
	ble.n .L08010e24
	cmp r4, #0
	ble.n .L08010dfe
.L08010dd0:
	movs r0, #2                   @ overflow exit
	bl set_word_20000578          @ set_word_20000578(2)
	bl fn_08011a80
	vstr d0, [sp, #8]
	vmov r2, r3, d10
	vmov r0, r1, d8
	bl double_multiply
	strd r0, r1, [sp]
	ldr r1, [sp, #0xc]
	ldr r0, [sp, #4]
	bfi r0, r1, #0, #31
	str r0, [sp, #0xc]
	vldr d0, [sp, #8]
	b.n .L08010b88
.L08010dfe:
	movs r0, #2                   @ underflow exit
	bl set_word_20000578          @ set_word_20000578(2)
	bl fn_08011aa0
	vmov r1, s1
	vmov r0, s17
	vstr d0, [sp, #8]
	vstr d8, [sp]
	bfi r0, r1, #0, #31
	str r0, [sp, #0xc]
	vldr d0, [sp, #8]
	b.n .L08010b88
.L08010e24:
	vldr d0, [sp, #0x38]          @ near-one path: t = ax - 1.0
	vmov r2, r3, d9
	vmov r0, r1, d0
	bl double_subtract
	vldr d0, .L08010ed0           @ 0.25
	strd r0, r1, [sp, #0x20]
	vmov r2, r3, d0
	vldr d0, [sp, #0x20]
	vmov r0, r1, d0
	bl double_multiply
	vldr d1, .L08010ed8           @ 0x3fd5555555555555
	vmov r2, r3, d1
	bl double_reverse_subtract
	vldr d1, [sp, #0x20]
	vmov r2, r3, d1
	bl double_multiply
	vldr d1, .L08010ee0           @ 0.5
	vmov r2, r3, d1
	b.n .L08010ee8
.L08010e6e:
	b.n .L08010f8a
.L08010e70:
	.word 0x001fffff
.L08010e74:
	.word 0x000fffff
.L08010e78:
	.word 0x00000000, 0x3ff00000  @ double 1.0
.L08010e80:
	.word 0x3ff00000
.L08010e84:
	.word 0x7ff00000
.L08010e88:
	.word 0x43400000
.L08010e8c:
	.word 0xfffffc01
.L08010e90:
	.word 0x00000000, 0x7ff00000  @ double +inf
.L08010e98:
	.word 0x00000000, 0x00000000  @ double 0.0
.L08010ea0:
	.word d_080510a8 - (.L08010be6 + 4)
	.word 0x00000000              @ padding
.L08010ea8:
	.word 0x00000000, 0x80000000  @ double -0.0
.L08010eb0:
	.word 0x00000000, 0xfff00000  @ double -inf
.L08010eb8:
	.word 0x00000000, 0xbff00000  @ double -1.0
.L08010ec0:
	.word 0x41e00000
.L08010ec4:
	.word 0x43f00000
.L08010ec8:
	.word 0x3fefffff
	.word 0x00000000              @ padding
.L08010ed0:
	.word 0x00000000, 0x3fd00000  @ double 0.25
.L08010ed8:
	.word 0x55555555, 0x3fd55555  @ double 0x3fd5555555555555
.L08010ee0:
	.word 0x00000000, 0x3fe00000  @ double 0.5
.L08010ee8:
	bl double_reverse_subtract
	vldr d0, [sp, #0x20]
	vmov d10, r0, r1
	vmov r2, r3, d0
	vmov r0, r1, d0
	bl double_multiply
	vmov r2, r3, d10
	bl double_multiply
	vmov d10, r0, r1              @ w
	vldr d0, .L08011308
	vmov r2, r3, d0
	vldr d0, [sp, #0x20]
	vmov r0, r1, d0
	bl double_multiply
	vmov d11, r0, r1
	vldr d0, .L08011310
	vmov r0, r1, d10
	vmov r2, r3, d0
	bl double_multiply
	vmov d10, r0, r1
	vldr d0, .L08011318
	vmov r2, r3, d0
	vldr d0, [sp, #0x20]
	vmov r0, r1, d0
	bl double_multiply
	vmov r2, r3, d10
	bl double_subtract
	vmov d10, r0, r1
	vmov r0, r1, d11
	vmov r2, r3, d10
	bl double_add
	str r0, [sp, #0x18]
	strd r5, r1, [sp, #0x18]      @ t1 = sum with its low word cleared (r5 = 0)
	vldr d0, [sp, #0x18]
	vmov r2, r3, d11
	vmov r0, r1, d0
	bl double_subtract
	vmov r2, r3, d10
	bl double_reverse_subtract
	vmov d0, r0, r1
	b.w .L080112cc
.L08010f8a:
	movs r0, #0                   @ normal path: n = 0
	cmp.w r6, #0x100000
	bge.n .L08010fb0
	vldr d0, .L08011320
	vmov r2, r3, d0
	vldr d0, [sp, #0x38]
	vmov r0, r1, d0
	bl double_multiply            @ ax * 0x4340000000000000
	strd r0, r1, [sp, #0x38]
	mvn r0, #0x34                 @ n = -53
	mov r6, r1
.L08010fb0:
	add.w r0, r0, r6, asr #20
	subw r7, r0, #0x3ff
	ubfx r0, r6, #0, #20          @ j = |x| high & 0xfffff
	ldr r1, .L08011328
	orr r6, r0, #0xff00000
	orr r6, r6, #0x30000000       @ r6 = j | 0x3ff00000
	cmp r0, r1
	it le
	movle r4, #0
	ble.n .L08010fe0
	ldr r1, .L0801132c
	cmp r1, r0
	it gt
	movgt r4, #1
	bgt.n .L08010fe0
	movs r4, #0
	sub.w r6, r6, #0x100000
	.inst.n 0x1c7f                @ adds r7, r7, #1
.L08010fe0:
	ldr r0, .L08011330
.L08010fe2:
	add r0, pc
	add.w r0, r0, r4, lsl #3
	str r6, [sp, #0x3c]
	vldr d12, [r0]                @ d12 = table1[k]
	vldr d0, [sp, #0x38]
	vmov r2, r3, d12
	vmov r0, r1, d0
	bl double_subtract            @ u = ax - table1[k]
	vldr d0, [sp, #0x38]
	vmov d11, r0, r1
	vmov r2, r3, d12
	vmov r0, r1, d0
	bl double_add
	vmov d0, r0, r1
	vmov r0, r1, d9
	vmov r2, r3, d0
	bl double_divide              @ v = 1.0 / (ax + table1[k])
	vmov d13, r0, r1
	vmov r0, r1, d11
	vmov r2, r3, d13
	bl double_multiply            @ s = u * v
	vmov d10, r0, r1
	ldr r0, .L08011334
	vstr d10, [sp, #0x40]
.L0801103c:
	add r0, pc
	str r5, [sp, #0x40]           @ s_h = s with low word cleared (r5 = 0)
	vldr d0, [r0]
	mov.w r0, #0x20000000
	orr.w r0, r0, r6, asr #1
	add.w r0, r0, r4, lsl #18
	vstr d0, [sp, #0x20]
	add.w r0, r0, #0x80000
	str r0, [sp, #0x24]           @ t_h: low word 0, high word as computed
	vldr d0, [sp, #0x20]
	vmov r2, r3, d12
	vmov r0, r1, d0
	bl double_subtract
	vldr d1, [sp, #0x38]
	vmov r2, r3, d1
	bl double_reverse_subtract
	vmov d0, r0, r1
	vmov r2, r3, d0
	vldr d0, [sp, #0x40]
	vmov r0, r1, d0
	bl double_multiply
	vldr d0, [sp, #0x20]
	vmov d12, r0, r1
	vmov r2, r3, d0
	vldr d0, [sp, #0x40]
	vmov r0, r1, d0
	bl double_multiply
	vmov r2, r3, d11
	bl double_reverse_subtract
	vmov r2, r3, d12
	bl double_subtract
	vmov r2, r3, d13
	bl double_multiply            @ s_l
	vmov d12, r0, r1
	vmov r2, r3, d10
	vmov r0, r1, d10
	bl double_multiply            @ q = s * s
	vmov d11, r0, r1
	ldr r0, .L08011338
	movs r1, #6
	vmov.f32 s0, s22
	vmov.f32 s1, s23
.L080110da:
	add r0, pc
	bl horner_poly_f64            @ horner_poly_f64(q, 0x08050fb8, 6)
	vmov.f32 s2, s0
	vmov.f32 s3, s1
	vmov.f32 s26, s2
	vmov.f32 s27, s3
	vmov r2, r3, d11
	vmov r0, r1, d11
	bl double_multiply
	vmov r2, r3, d13
	bl double_multiply
	vldr d0, [sp, #0x40]
	vmov d11, r0, r1
	vmov r2, r3, d10
	vmov r0, r1, d0
	bl double_add
	vmov r2, r3, d12
	bl double_multiply
	vmov r2, r3, d11
	bl double_add                 @ r
	vldr d0, [sp, #0x40]
	vmov d11, r0, r1
	vmov r2, r3, d0
	vmov r0, r1, d0
	bl double_multiply
	vmov d13, r0, r1
	vldr d14, .L08011340          @ d14 = 3.0
	vmov r2, r3, d14
	bl double_add
	vmov r2, r3, d11
	bl double_add
	str r0, [sp, #0x20]
	strd r5, r1, [sp, #0x20]      @ t_h2 = sum with low word cleared
	vldr d0, [sp, #0x20]
	vmov r2, r3, d14
	vmov r0, r1, d0
	bl double_subtract
	vmov r2, r3, d13
	bl double_subtract
	vmov r2, r3, d11
	bl double_reverse_subtract
	vldr d0, [sp, #0x20]
	vmov d13, r0, r1
	vmov r2, r3, d0
	vldr d0, [sp, #0x40]
	vmov r0, r1, d0
	bl double_multiply
	vmov d11, r0, r1
	vmov r2, r3, d10
	vmov r0, r1, d13
	bl double_multiply
	vldr d0, [sp, #0x20]
	vmov d10, r0, r1
	vmov r2, r3, d0
	vmov r0, r1, d12
	bl double_multiply
	vmov r2, r3, d10
	bl double_add
	vmov d10, r0, r1
	vmov r0, r1, d11
	vmov r2, r3, d10
	bl double_add
	str r0, [sp, #0x30]
	strd r5, r1, [sp, #0x30]      @ p_h = p with low word cleared
	vldr d0, [sp, #0x30]
	vmov r2, r3, d11
	vmov r0, r1, d0
	bl double_subtract
	vmov r2, r3, d10
	bl double_reverse_subtract    @ p_l
	vmov d11, r0, r1
	vldr d0, .L08011348           @ 0x3feec709e0000000
	vmov r2, r3, d0
	vldr d0, [sp, #0x30]
	vmov r0, r1, d0
	bl double_multiply            @ z_h
	vmov d10, r0, r1
	vldr d0, .L08011350           @ 0x3feec709dc3a03fd
	vmov r0, r1, d11
	vmov r2, r3, d0
	bl double_multiply
	vmov d11, r0, r1
	vldr d0, .L08011358           @ 0xbe3e2fe0145b01f5
	vmov r2, r3, d0
	vldr d0, [sp, #0x30]
	vmov r0, r1, d0
	bl double_multiply
	vmov r2, r3, d11
	bl double_add
	vmov d0, r0, r1
	ldr r0, .L08011360
.L0801123e:
	add r0, pc
	add.w r0, r0, r4, lsl #3
	vldr d1, [r0]                 @ table3[k]
	vmov r0, r1, d0
	vmov r2, r3, d1
	bl double_add                 @ z_l
	vmov d11, r0, r1
	mov r0, r7
	bl int_to_double              @ n as a double
	strd r0, r1, [sp, #0x20]
	vmov r2, r3, d11
	vmov r0, r1, d10
	bl double_add
	vmov d0, r0, r1
	ldr r0, .L08011364
.L08011274:
	add r0, pc
	add.w r0, r0, r4, lsl #3
	vldr d12, [r0]                @ table2[k]
	vmov r0, r1, d0
	vmov r2, r3, d12
	bl double_add
	vldr d1, [sp, #0x20]
	vmov r2, r3, d1
	bl double_add
	str r0, [sp, #0x18]
	strd r5, r1, [sp, #0x18]      @ t1 = t with low word cleared
	vldr d0, [sp, #0x20]
	vmov r2, r3, d0
	vldr d0, [sp, #0x18]
	vmov r0, r1, d0
	bl double_subtract
	vmov r2, r3, d12
	bl double_subtract
	vmov r2, r3, d10
	bl double_subtract
	vmov r2, r3, d11
	bl double_reverse_subtract    @ t2
	vmov d0, r0, r1
.L080112cc:
	vldr d1, [sp, #0x98]          @ common part: d0 = t2, t1 at [sp+0x18]
	vmov r2, r3, d0
	vstr d1, [sp]
	str r5, [sp]                  @ y1 = y with low word cleared
	vldr d0, [sp, #0x98]
	vmov r0, r1, d0
	bl double_multiply
	vldr d0, [sp]
	vmov d10, r0, r1
	vmov r2, r3, d0
	vldr d0, [sp, #0x98]
	vmov r0, r1, d0
	bl double_subtract
	vldr d1, [sp, #0x18]
	vmov r2, r3, d1
	b.n .L08011368
.L08011308:
	.word 0x60000000, 0x3ff71547  @ double 0x3ff7154760000000
.L08011310:
	.word 0x652b82fe, 0x3ff71547  @ double 0x3ff71547652b82fe
.L08011318:
	.word 0xf85ddf44, 0x3e54ae0b  @ double 0x3e54ae0bf85ddf44
.L08011320:
	.word 0x00000000, 0x43400000  @ double 0x4340000000000000
.L08011328:
	.word 0x0003988e
.L0801132c:
	.word 0x000bb67a
.L08011330:
	.word d_08050f88 - (.L08010fe2 + 4)
.L08011334:
	.word d_080510a8 - (.L0801103c + 4)
.L08011338:
	.word d_08050fb8 - (.L080110da + 4)
	.word 0x00000000              @ padding
.L08011340:
	.word 0x00000000, 0x40080000  @ double 3.0
.L08011348:
	.word 0xe0000000, 0x3feec709  @ double 0x3feec709e0000000
.L08011350:
	.word 0xdc3a03fd, 0x3feec709  @ double 0x3feec709dc3a03fd
.L08011358:
	.word 0x145b01f5, 0xbe3e2fe0  @ double 0xbe3e2fe0145b01f5
.L08011360:
	.word d_08050fa8 - (.L0801123e + 4)
.L08011364:
	.word d_08050f98 - (.L08011274 + 4)
.L08011368:
	bl double_multiply
	vmov r2, r3, d10
	bl double_add
	vldr d0, [sp, #0x18]
	vmov d10, r0, r1              @ p_l
	vmov r2, r3, d0
	vldr d0, [sp]
	vmov r0, r1, d0
	bl double_multiply
	strd r0, r1, [sp, #0x30]      @ p_h = y1 * t1
	vldr d0, [sp, #0x30]
	vmov r0, r1, d10
	vmov r2, r3, d0
	bl double_add
	strd r0, r1, [sp, #8]         @ z = p_l + p_h
	mov r4, r1                    @ r4 = z high word
	ldr r1, .L08011650            @ r1 = 0x40900000
	cmp r4, r1
	blt.n .L0801140c
	subs r1, r4, r1
	orrs r0, r1
	bne.n .L080113e4
	vldr d0, [sp, #0x30]
	vmov r2, r3, d0
	vldr d0, [sp, #8]
	vmov r0, r1, d0
	bl double_subtract
	vmov d11, r0, r1
	vldr d0, .L08011658           @ 0x3c971547652b82fe
	vmov r0, r1, d10
	vmov r2, r3, d0
	bl double_add
	vmov r2, r3, d11
	bl fn_0800781c
	bcs.n .L08011440
.L080113e4:
	movs r0, #2                   @ overflow exit
	bl set_word_20000578          @ set_word_20000578(2)
	bl fn_08011a80
	vmov r1, s1
	vmov r0, s17
	vstr d0, [sp, #8]
	vstr d8, [sp]
	bfi r0, r1, #0, #31
	str r0, [sp, #0xc]
	vldr d0, [sp, #8]
	b.w .L08010b88
.L0801140c:
	ldr r2, .L08011660            @ r2 = 0x4090cc00
	bic r1, r4, #0x80000000
	cmp r1, r2
	bcc.n .L08011440
	ldr r1, .L08011664            @ r1 = 0x3f6f3400
	add r1, r4
	orrs r0, r1
	bne.w .L08010dfe
	vldr d0, [sp, #0x30]
	vmov r2, r3, d0
	vldr d0, [sp, #8]
	vmov r0, r1, d0
	bl double_subtract
	vmov r2, r3, d10
	bl fn_0800781c
	bls.w .L08010dfe
.L08011440:
	bic r0, r4, #0x80000000       @ r0 = |z high|
	ldr r1, .L08011668            @ r1 = 0xfffffc01 (-0x3ff)
	ldr r2, .L0801166c            @ r2 = 0x3fe00000
	movs r6, #0                   @ r6 = integer part of z (0 by default)
	add.w r1, r1, r0, asr #20
	cmp r2, r0
	bge.n .L080114aa
	adds r0, r1, #1
	mov.w r1, #0x100000
	lsr.w r0, r1, r0
	add r0, r4
	ldr r2, .L08011670
	ubfx r1, r0, #20, #11
.L08011464:
	add r2, pc
	subw r1, r1, #0x3ff
	vldr d0, [r2]
	ldr r2, .L08011674            @ r2 = 0x000fffff
	vstr d0, [sp, #0x20]
	lsrs r2, r1
	bic.w r2, r0, r2
	ubfx r0, r0, #0, #20
	orr r0, r0, #0x100000
	rsb.w r1, r1, #0x14
	lsr.w r6, r0, r1
	str r2, [sp, #0x24]
	cmp r4, #0
	it lt
	rsblt r6, r6, #0
	vldr d0, [sp, #0x20]
	vmov r2, r3, d0
	vldr d0, [sp, #0x30]
	vmov r0, r1, d0
	bl double_subtract
	strd r0, r1, [sp, #0x30]
.L080114aa:
	vldr d0, [sp, #0x30]
	vmov r0, r1, d10
	vmov r2, r3, d0
	bl double_add
	vldr d0, .L08011678           @ 0x3fe62e4300000000
	str r0, [sp, #0x20]
	strd r5, r1, [sp, #0x20]      @ t = sum with low word cleared
	vmov r2, r3, d0
	vldr d0, [sp, #0x20]
	vmov r0, r1, d0
	bl double_multiply            @ u
	vmov d11, r0, r1
	vldr d0, .L08011680           @ 0xbe205c610ca86c39
	vmov r2, r3, d0
	vldr d0, [sp, #0x20]
	vmov r0, r1, d0
	bl double_multiply
	vldr d0, [sp, #0x30]
	vmov d12, r0, r1
	vmov r2, r3, d0
	vldr d0, [sp, #0x20]
	vmov r0, r1, d0
	bl double_subtract
	vmov r2, r3, d10
	bl double_reverse_subtract
	vldr d1, .L08011688           @ 0x3fe62e42fefa39ef
	vmov r2, r3, d1
	bl double_multiply
	vmov r2, r3, d12
	bl double_add                 @ v
	vmov d10, r0, r1
	vmov r0, r1, d11
	vmov r2, r3, d10
	bl double_add                 @ w = u + v
	strd r0, r1, [sp, #8]
	vldr d0, [sp, #8]
	vmov r2, r3, d11
	vmov r0, r1, d0
	bl double_subtract
	vmov r2, r3, d10
	bl double_reverse_subtract    @ w2
	vldr d0, [sp, #8]
	vmov d10, r0, r1
	vmov r2, r3, d0
	vmov r0, r1, d0
	bl double_multiply
	strd r0, r1, [sp, #0x20]      @ q = w * w
	ldr r0, .L08011690
	vldr d0, [sp, #0x20]
	movs r1, #5
.L0801156c:
	add r0, pc
	bl horner_poly_f64            @ horner_poly_f64(q, 0x08050fe8, 5)
	vldr d1, [sp, #0x20]
	vmov r0, r1, d0
	vmov r2, r3, d1
	bl double_multiply
	vldr d1, [sp, #8]
	vmov r2, r3, d1
	bl double_reverse_subtract    @ c = w - q * P
	strd r0, r1, [sp, #0x18]
	vldr d0, [sp, #8]
	vmov r2, r3, d10
	vmov r0, r1, d0
	bl double_multiply
	vmov r2, r3, d10
	bl double_add
	vldr d0, .L08011698           @ 2.0
	vmov d10, r0, r1
	vmov r2, r3, d0
	vldr d0, [sp, #0x18]
	vmov r0, r1, d0
	bl double_subtract
	vldr d0, [sp, #0x18]
	vmov d11, r0, r1
	vmov r2, r3, d0
	vldr d0, [sp, #8]
	vmov r0, r1, d0
	bl double_multiply
	vmov r2, r3, d11
	bl double_divide
	vmov r2, r3, d10
	bl double_subtract
	vldr d1, [sp, #8]
	vmov r2, r3, d1
	bl double_subtract
	vmov r2, r3, d9
	bl double_reverse_subtract    @ result = 1.0 - (...)
	strd r0, r1, [sp, #8]
	add.w r0, r1, r6, lsl #20
	asrs r1, r0, #20
	cmp r1, #0
	it gt
	strgt r0, [sp, #0xc]
	bgt.n .L0801163c
	vldr d0, [sp, #8]
	mov r2, r6
	vmov r0, r1, d0
	bl double_scale_by_power_of_two
	bl classify_double
	cmp r0, #4
	it eq
	bleq fn_08011aa0
	mov r2, r6
	vldr d0, [sp, #8]
	vmov r0, r1, d0
	bl double_scale_by_power_of_two
	strd r0, r1, [sp, #8]
.L0801163c:
	vldr d0, [sp, #8]
	vmov r0, r1, d8
	vmov r2, r3, d0
.L08011648:
	bl double_multiply            @ multiply by the sign factor d8
	b.w .L08010cc4
.L08011650:
	.word 0x40900000
	.word 0x00000000              @ padding
.L08011658:
	.word 0x652b82fe, 0x3c971547  @ double 0x3c971547652b82fe
.L08011660:
	.word 0x4090cc00
.L08011664:
	.word 0x3f6f3400
.L08011668:
	.word 0xfffffc01
.L0801166c:
	.word 0x3fe00000
.L08011670:
	.word d_080510a8 - (.L08011464 + 4)
.L08011674:
	.word 0x000fffff
.L08011678:
	.word 0x00000000, 0x3fe62e43  @ double 0x3fe62e4300000000
.L08011680:
	.word 0x0ca86c39, 0xbe205c61  @ double 0xbe205c610ca86c39
.L08011688:
	.word 0xfefa39ef, 0x3fe62e42  @ double 0x3fe62e42fefa39ef
.L08011690:
	.word d_08050fe8 - (.L0801156c + 4)
	.word 0x00000000              @ padding
.L08011698:
	.word 0x00000000, 0x40000000  @ double 2.0
