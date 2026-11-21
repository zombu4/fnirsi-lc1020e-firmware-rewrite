@ app_02.s - application code, 11 functions at 0x0800b000..0x0800c848 and 0x08014b74..0x08014bd4
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0800b000 - selection step driven by a measured value.
@ Parameter r0 = measured value; returns r0 = 0 or 1.
@ Literal pool word 0x2000057c is the base of the variables used (r4);
@ offsets give the words 0x2000114c (+0xbd0), 0x200011c6 (+0xc4a),
@ 0x200011c8 (+0xc4c) and halfword 0x200011de (+0xc62).
@ When word 0x2000114c is above 0: stores (its low byte - 1) in byte
@ 0x200011c8 and calls fn_080093b8 with that byte.
@ When halfword 0x200011de is above 250, word 0x2000114c is 0 and byte
@ 0x200011c8 is non-zero: decrements byte 0x200011c8, calls fn_080093b8 with
@ it and returns 0.
@ r0 below 1500: when byte 0x200011c6 is below 7 it is incremented, fn_0800af58
@ is called and 0 is returned; at 7 with byte 0x200011c8 below 3 it stores 0
@ in 0x200011c6, calls fn_0800af58, and when word 0x2000114c is 0 increments
@ byte 0x200011c8 and calls fn_080093b8 with it, and returns 0; at 7 with
@ 0x200011c8 at 3 or above it continues as in the last paragraph below.
@ r0 above 3000: when byte 0x200011c6 is non-zero it is decremented,
@ fn_0800af58 is called and 0 is returned; at 0 with byte 0x200011c8 non-zero
@ it stores 0 in 0x200011c6, calls fn_0800af58, and when word 0x2000114c is 0
@ decrements byte 0x200011c8 and calls fn_080093b8 with it, and returns 0; at
@ 0 with byte 0x200011c8 zero it continues as in the last paragraph below.
@ r0 from 1500 to 3000 and the continuing cases: when word 0x2000114c is 0,
@ byte 0x200011c6 is above 3 and byte 0x200011c8 is below 3 it increments byte
@ 0x200011c8, calls fn_080093b8 with it and returns 0; otherwise returns 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b000,"ax",%progbits
	.p2align 2
	.global fn_0800b000
	.thumb_func
	.type fn_0800b000, %function
fn_0800b000:
	push	{r4, r5, r6, lr}
	ldr	r4, .L0800b0d4
	mov	r5, r0
	ldr.w	r0, [r4, #0xbd0]
	cmp	r0, #0
	ble.n	.L0800b01c
	.inst.n 0x1e40	@ subs r0, r0, #1
	strb.w	r0, [r4, #0xc4c]
	ldrb.w	r0, [r4, #0xc4c]
	bl	fn_080093b8
.L0800b01c:
	ldrh.w	r0, [r4, #0xc62]
	cmp	r0, #0xfa
	bls.n	.L0800b030
	ldr.w	r0, [r4, #0xbd0]
	cbnz	r0, .L0800b030
	ldrb.w	r0, [r4, #0xc4c]
	cbnz	r0, .L0800b090
.L0800b030:
	movw	r1, #0x5dc
	movs	r0, #0
	cmp	r5, r1
	bge.n	.L0800b072
	ldrb.w	r1, [r4, #0xc4a]
	cmp	r1, #7
	bcs.n	.L0800b04a
	ldrb.w	r0, [r4, #0xc4a]
	.inst.n 0x1c40	@ adds r0, r0, #1
	b.n	.L0800b086
.L0800b04a:
	ldrb.w	r1, [r4, #0xc4c]
	cmp	r1, #3
	bcs.n	.L0800b0b2
	strb.w	r0, [r4, #0xc4a]
	bl	fn_0800af58
	ldr.w	r0, [r4, #0xbd0]
	cbz	r0, .L0800b0c8
	b.n	.L0800b0a6
	.byte	0x00, 0xbf	@ padding
.L0800b064:
	strb.w	r0, [r4, #0xc4c]
	ldrb.w	r0, [r4, #0xc4c]
	bl	fn_080093b8
	b.n	.L0800b0a6
.L0800b072:
	movw	r1, #0xbb8
	cmp	r5, r1
	ble.n	.L0800b0b2
	ldrb.w	r1, [r4, #0xc4a]
	cbz	r1, .L0800b092
	ldrb.w	r0, [r4, #0xc4a]
	.inst.n 0x1e40	@ subs r0, r0, #1
.L0800b086:
	strb.w	r0, [r4, #0xc4a]
	bl	fn_0800af58
	b.n	.L0800b0a6
.L0800b090:
	b.n	.L0800b0aa
.L0800b092:
	ldrb.w	r1, [r4, #0xc4c]
	cbz	r1, .L0800b0b2
	strb.w	r0, [r4, #0xc4a]
	bl	fn_0800af58
	ldr.w	r0, [r4, #0xbd0]
	cbz	r0, .L0800b0aa
.L0800b0a6:
	movs	r0, #0
	pop	{r4, r5, r6, pc}
.L0800b0aa:
	ldrb.w	r0, [r4, #0xc4c]
	.inst.n 0x1e40	@ subs r0, r0, #1
	b.n	.L0800b064
.L0800b0b2:
	ldr.w	r0, [r4, #0xbd0]
	cbnz	r0, .L0800b0d0
	ldrb.w	r0, [r4, #0xc4a]
	cmp	r0, #3
	bls.n	.L0800b0d0
	ldrb.w	r0, [r4, #0xc4c]
	cmp	r0, #3
	bcs.n	.L0800b0d0
.L0800b0c8:
	ldrb.w	r0, [r4, #0xc4c]
	.inst.n 0x1c40	@ adds r0, r0, #1
	b.n	.L0800b064
.L0800b0d0:
	movs	r0, #1
	pop	{r4, r5, r6, pc}
.L0800b0d4:
	.word	0x2000057c

@ ----------------------------------------------------------------------------
@ fn_0800b0d8 - initialisation of two port groups and the selection state.
@ No parameters.
@ Calls fn_08008338 with r2 = 0x10 for base 0x40010800 (r1 masks 1, 2, 4, 8)
@ and base 0x40011000 (r1 masks 8, 1, 2, 4), in the order: 0x40010800/1,
@ 0x40011000/8, /1, /2, /4, then 0x40010800/2, /4, /8.
@ Stores 0 to byte 0x200011c5, 7 to 0x200011c6 and 0 to 0x200011c8 (base
@ 0x2000057c in the literal pool, offsets 0xc49, 0xc4a, 0xc4c), calls
@ fn_0800b164 and fn_0800af58, then tail-calls fn_080093b8 with byte
@ 0x200011c8 as the argument.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b0d8,"ax",%progbits
	.p2align 2
	.global fn_0800b0d8
	.thumb_func
	.type fn_0800b0d8, %function
fn_0800b0d8:
	push	{r4, r5, r6, lr}
	ldr	r4, .L0800b158
	movs	r2, #0x10
	movs	r1, #1
	mov	r0, r4
	bl	fn_08008338
	ldr	r5, .L0800b15c
	movs	r2, #0x10
	movs	r1, #8
	mov	r0, r5
	bl	fn_08008338
	movs	r2, #0x10
	movs	r1, #1
	mov	r0, r5
	bl	fn_08008338
	movs	r2, #0x10
	movs	r1, #2
	mov	r0, r5
	bl	fn_08008338
	movs	r2, #0x10
	movs	r1, #4
	mov	r0, r5
	bl	fn_08008338
	movs	r2, #0x10
	movs	r1, #2
	mov	r0, r4
	bl	fn_08008338
	movs	r2, #0x10
	movs	r1, #4
	mov	r0, r4
	bl	fn_08008338
	movs	r2, #0x10
	movs	r1, #8
	mov	r0, r4
	bl	fn_08008338
	ldr	r4, .L0800b160
	movs	r0, #0
	strb.w	r0, [r4, #0xc49]
	movs	r1, #7
	strb.w	r1, [r4, #0xc4a]
	strb.w	r0, [r4, #0xc4c]
	addw	r4, r4, #0xc49
	bl	fn_0800b164
	bl	fn_0800af58
	ldrb	r0, [r4, #3]
	pop.w	{r4, r5, r6, lr}
	b.w	fn_080093b8
	.short	0x0000	@ padding
.L0800b158:
	.word	0x40010800
.L0800b15c:
	.word	0x40011000
.L0800b160:
	.word	0x2000057c

@ ----------------------------------------------------------------------------
@ fn_0800b164 - drives three outputs of port base 0x40011000 from byte
@ 0x200011c5 (same selection scheme as fn_0800af58).
@ No parameters. Reads byte 0x200011c5 (base 0x2000057c + 0xc49) and calls
@ fn_08008350 with r0 = 0x40011000, r1 = mask 1, 2 and 4 in that order, and
@ r2 = one bit of the value each: value 0 -> bits 0,0,0; 1 -> 0,0,1;
@ 2 -> 0,1,0; 3 -> 0,1,1; 4 -> 1,0,0; 5 -> 1,0,1; 6 -> 1,1,0; any other
@ value -> 1,1,1 (bit order mask 1, mask 2, mask 4). The last call is a tail
@ call.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b164,"ax",%progbits
	.p2align 2
	.global fn_0800b164
	.thumb_func
	.type fn_0800b164, %function
fn_0800b164:
	ldr	r0, .L0800b204
	push	{r4, lr}
	ldrb.w	r1, [r0, #0xc49]
	ldr	r4, .L0800b208
	cbz	r1, .L0800b1a6
	ldrb.w	r1, [r0, #0xc49]
	cmp	r1, #1
	beq.n	.L0800b1aa
	ldrb.w	r1, [r0, #0xc49]
	cmp	r1, #2
	beq.n	.L0800b1ae
	ldrb.w	r1, [r0, #0xc49]
	cmp	r1, #3
	beq.n	.L0800b1c6
	ldrb.w	r1, [r0, #0xc49]
	cmp	r1, #4
	beq.n	.L0800b1e8
	ldrb.w	r1, [r0, #0xc49]
	cmp	r1, #5
	beq.n	.L0800b1f6
	ldrb.w	r0, [r0, #0xc49]
	mov.w	r2, #1
	cmp	r0, #6
	beq.n	.L0800b1b0
	b.n	.L0800b1c8
.L0800b1a6:
	movs	r2, #0
	b.n	.L0800b1ea
.L0800b1aa:
	movs	r2, #0
	b.n	.L0800b1f8
.L0800b1ae:
	movs	r2, #0
.L0800b1b0:
	movs	r1, #1
	mov	r0, r4
	bl	fn_08008350
	movs	r2, #1
.L0800b1ba:
	movs	r1, #2
	mov	r0, r4
	bl	fn_08008350
	movs	r2, #0
	b.n	.L0800b1dc
.L0800b1c6:
	movs	r2, #0
.L0800b1c8:
	movs	r1, #1
	mov	r0, r4
	bl	fn_08008350
	movs	r2, #1
.L0800b1d2:
	movs	r1, #2
	mov	r0, r4
	bl	fn_08008350
	movs	r2, #1
.L0800b1dc:
	mov	r0, r4
	pop.w	{r4, lr}
	movs	r1, #4
	b.w	fn_08008350
.L0800b1e8:
	movs	r2, #1
.L0800b1ea:
	movs	r1, #1
	mov	r0, r4
	bl	fn_08008350
	movs	r2, #0
	b.n	.L0800b1ba
.L0800b1f6:
	movs	r2, #1
.L0800b1f8:
	movs	r1, #1
	mov	r0, r4
	bl	fn_08008350
	movs	r2, #0
	b.n	.L0800b1d2
.L0800b204:
	.word	0x2000057c
.L0800b208:
	.word	0x40011000

@ ----------------------------------------------------------------------------
@ fn_0800b20c - steps byte 0x200011c5 up or down from a measured value.
@ Parameter r0 = measured value; returns r0 = 0 or 1.
@ r0 below 0x5dc: returns 1 when byte 0x200011c5 (base 0x2000057c + 0xc49) is
@ above 6, else increments it.
@ r0 from 0xe11 (3601) and above: returns 1 when the byte is 0, else
@ decrements it.
@ In between: returns 1.
@ After a change calls fn_0800b164 and returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b20c,"ax",%progbits
	.p2align 2
	.global fn_0800b20c
	.thumb_func
	.type fn_0800b20c, %function
fn_0800b20c:
	push	{r4, lr}
	movw	r2, #0x5dc
	ldr	r1, .L0800b24c
	cmp	r0, r2
	bge.n	.L0800b228
	ldrb.w	r0, [r1, #0xc49]
	cmp	r0, #7
	bcs.n	.L0800b246
	ldrb.w	r0, [r1, #0xc49]
	.inst.n 0x1c40	@ adds r0, r0, #1
	b.n	.L0800b23a
.L0800b228:
	cmp.w	r0, #0xe10
	ble.n	.L0800b246
	ldrb.w	r0, [r1, #0xc49]
	cbz	r0, .L0800b246
	ldrb.w	r0, [r1, #0xc49]
	.inst.n 0x1e40	@ subs r0, r0, #1
.L0800b23a:
	strb.w	r0, [r1, #0xc49]
	bl	fn_0800b164
	movs	r0, #0
	pop	{r4, pc}
.L0800b246:
	movs	r0, #1
	pop	{r4, pc}
	.short	0x0000	@ padding
.L0800b24c:
	.word	0x2000057c

@ ----------------------------------------------------------------------------
@ fn_0800b4c8 - restore default parameters.
@ Parameter r0 = mode (kept in r6).
@ Copies 0x5a0 bytes from 0x20000580 to a stack buffer with
@ copy_bytes_080070dc(dest, src, count), clears 0xc14 bytes at 0x2000057c with
@ zero_bytes, writes 0x12345678 to 0x2000057c and 0x2000118c, and stores the
@ defaults 100 (0x20001158), 0 (0x2000115c), 100 (0x20001160), 0
@ (0x20001164), 1000 (0x20001144), 1 (0x20001150), 0x3f19999a (0x20001138),
@ 1 (0x20001178), 0x447a0000 (0x20001184), 0x40a00000 (0x20001188), 1
@ (0x20001170), 0 (0x2000116c), 1 (0x20001174).
@ Calls fn_0801031c("Restore_Default_Para:%d\n", mode).
@ Mode 0: copies 0x5a0 bytes from the stack buffer to 0x20000b20 and then
@ from the stack buffer to 0x20000580.
@ Mode non-zero: for i = 0..4 and j = 0..2 stores 12 words at
@ 0x2000057c + i * 0x90 + j * 0x30 + offset: +4 0x00000000, +8 0x3c23d70a,
@ +0xc 0x3dcccccd, +0x10 0x3f800000, +0x14 0x41200000, +0x18 0x42c80000,
@ +0x1c 0x447a0000, +0x20 0x461c4000, +0x24 0x47c35000, +0x28 0x49742400,
@ +0x2c 0x4b189680, +0x30 0x5368d4a5; then copies 0x5a0 bytes from 0x20000580
@ to 0x20000b20.
@ Both paths end with fn_08014b94 and release the 0x5a4 byte stack frame.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b4c8,"ax",%progbits
	.p2align 2
	.global fn_0800b4c8
	.thumb_func
	.type fn_0800b4c8, %function
fn_0800b4c8:
	push	{r4, r5, r6, r7, lr}
	vpush	{d8}
	subw	sp, sp, #0x5a4
	ldr	r4, .L0800b5e4
	mov	r6, r0
	mov.w	r5, #0x5a0
	mov	r2, r5
	adds	r1, r4, #4
	mov	r0, sp
	bl	copy_bytes_080070dc
	movw	r1, #0xc14
	mov	r0, r4
	bl	zero_bytes
	ldr	r0, .L0800b5e8
	str	r0, [r4]
	str.w	r0, [r4, #0xc10]
	movs	r0, #0x64
	str.w	r0, [r4, #0xbdc]
	movs	r2, #0
	str.w	r2, [r4, #0xbe0]
	str.w	r0, [r4, #0xbe4]
	mov.w	r1, #0x3e8
	str.w	r2, [r4, #0xbe8]
	str.w	r1, [r4, #0xbc8]
	movs	r0, #1
	vldr	s0, .L0800b5ec
	add.w	r1, r4, #0x800
	str.w	r0, [r4, #0xbd4]
	vstr	s0, [r1, #0x3bc]
	vldr	s16, .L0800b5f0
	add.w	r1, r1, #0x400
	str.w	r0, [r4, #0xbfc]
	vstr	s16, [r1, #8]
	vmov.f32	s0, #5.0
	vstr	s0, [r1, #0xc]
	str.w	r0, [r4, #0xbf4]
	str.w	r2, [r4, #0xbf0]
	str.w	r0, [r4, #0xbf8]
	mov	r1, r6
	adr.n	r0, .L0800b5f4
	bl	fn_0801031c
	addw	r7, r4, #0x5a4
	cbz	r6, .L0800b5ce
	vldr	s0, .L0800b610
	vldr	s1, .L0800b614
	vldr	s2, .L0800b618
	vldr	s5, .L0800b61c
	vldr	s6, .L0800b620
	vldr	s7, .L0800b624
	vldr	s8, .L0800b628
	vldr	s9, .L0800b62c
	vldr	s10, .L0800b630
	movs	r2, #0
	vmov.f32	s3, #1.0
	vmov.f32	s4, #10.0
.L0800b584:
	add.w	r0, r2, r2, lsl #3
	movs	r3, #0
	add.w	r1, r4, r0, lsl #4
	nop
.L0800b590:
	add.w	r0, r3, r3, lsl #1
	add.w	r0, r1, r0, lsl #4
	adds	r6, r0, #4
	vstr	s16, [r0, #0x1c]
	adds	r0, #0x20
	vstmia	r6, {s0, s1, s2, s3, s4, s5}
	.inst.n 0x1c5b	@ adds r3, r3, #1
	cmp	r3, #3
	vstmia	r0, {s6, s7, s8, s9, s10}
	blt.n	.L0800b590
	.inst.n 0x1c52	@ adds r2, r2, #1
	cmp	r2, #5
	blt.n	.L0800b584
	mov	r2, r5
	adds	r1, r4, #4
	mov.w	r0, r7
.L0800b5bc:
	bl	copy_bytes_080070dc
.ifdef OWN
	bl	own_save		@ 0x0800B5C0: our save (own/save.s)
.else
	bl	fn_08014b94
.endif
	addw	sp, sp, #0x5a4
	vpop	{d8}
	pop	{r4, r5, r6, r7, pc}
.L0800b5ce:
	b.n	.L0800b5d0
.L0800b5d0:
	mov	r2, r5
	mov	r1, sp
	mov	r0, r7
	bl	copy_bytes_080070dc
	mov	r2, r5
	mov	r1, sp
	adds	r0, r4, #4
	b.n	.L0800b5bc
	.short	0x0000	@ padding
.L0800b5e4:
	.word	0x2000057c
.L0800b5e8:
	.word	0x12345678
.L0800b5ec:
	.word	0x3f19999a
.L0800b5f0:
	.word	0x447a0000
.L0800b5f4:
	.asciz	"Restore_Default_Para:%d\n"
	.byte	0x00, 0x00, 0x00	@ padding
.L0800b610:
	.word	0x00000000
.L0800b614:
	.word	0x3c23d70a
.L0800b618:
	.word	0x3dcccccd
.L0800b61c:
	.word	0x42c80000
.L0800b620:
	.word	0x461c4000
.L0800b624:
	.word	0x47c35000
.L0800b628:
	.word	0x49742400
.L0800b62c:
	.word	0x4b189680
.L0800b630:
	.word	0x5368d4a5

@ ----------------------------------------------------------------------------
@ fn_0800bb64 - checks the float at 0x200050c4 and stores it in the table.
@ No parameters; returns r0 = 0 or 1.
@ Reads the float at 0x200050c4 (absolute value kept in s0) and the type word
@ 0x200050e0 (base 0x2000457c, offset 0xb64). Types 0, 1, 2 go to the store
@ path when the absolute value as an integer is below 0x3f666666; type 3 when
@ it is above 0x3de147ae and below 0x40000000; types 9, 10 and 11 always.
@ Otherwise it gets fn_0800a004(word 0x20001144) and fn_08009fe0(float
@ 0x20001138) and compares abs(value * 0.5) with abs(value - the float at
@ 0x20000b20 + i * 0x90 + j * 0x30 + type * 4). When the first is not larger
@ it clears words 0x200050e4 and 0x200050e8, stores 3 in 0x200050ec, calls
@ fn_08008120(0x32), fn_08011c68(0x32), fn_08008120(0x32) and
@ fn_080228d0(word 0x20005960, string pointer from the table at 0x200000fc:
@ entry [word 0x2000115c * 4 + word 0x200050ec]) and returns 0.
@ Store path: copies the float 0x200050c4 to 0x20000b20 + i * 0x90 + j * 0x30
@ + type * 4 and the word 0x200050cc to 0x20000df0 + the same offset, and
@ returns 1. (i is the result of fn_0800a004, j the result of fn_08009fe0.)
@ ----------------------------------------------------------------------------
	.section .text.fn_0800bb64,"ax",%progbits
	.p2align 2
	.global fn_0800bb64
	.thumb_func
	.type fn_0800bb64, %function
fn_0800bb64:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r4, .L0800bcc4
	ldr	r1, .L0800bcc8
	sub.w	r8, r4, #0x4000
	add.w	r6, r8, #0x4800
	ldr.w	r0, [r4, #0xb64]
	vldr	s0, [r6, #0x348]
	add.w	r5, r8, #0x800
	vabs.f32	s0, s0
	cbz	r0, .L0800bc04
	cmp	r0, #1
	beq.n	.L0800bc3a
	cmp	r0, #2
	beq.n	.L0800bc3a
	cmp	r0, #3
	beq.n	.L0800bc44
	cmp	r0, #9
	beq.n	.L0800bc58
	cmp	r0, #0xa
	beq.n	.L0800bc58
	cmp	r0, #0xb
	beq.n	.L0800bc58
.L0800bb9e:
	mov	r7, r8
	ldr.w	r0, [r8, #0xbc8]
	bl	fn_0800a004
	add.w	r0, r0, r0, lsl #3
	add.w	r7, r7, r0, lsl #4
	vldr	s0, [r5, #0x3bc]
	bl	fn_08009fe0
	add.w	r0, r0, r0, lsl #1
	ldr.w	r1, [r4, #0xb64]
	add.w	r0, r7, r0, lsl #4
	add.w	r0, r0, r1, lsl #2
	add.w	r0, r0, #0x400
	vldr	s0, [r6, #0x348]
	vldr	s1, [r0, #0x1a4]
	vmov.f32	s2, #0.5
	vsub.f32	s1, s0, s1
	vmul.f32	s0, s0, s2
	vabs.f32	s1, s1
	vabs.f32	s0, s0
	vcmpe.f32	s1, s0
	vmrs	APSR_nzcv, fpscr
	bcc.n	.L0800bc58
	movs	r0, #0
	str.w	r0, [r4, #0xb68]
	str.w	r0, [r4, #0xb6c]
	movs	r0, #3
	str.w	r0, [r4, #0xb70]
	b.n	.L0800bc06
.L0800bc04:
	b.n	.L0800bc3a
.L0800bc06:
	movs	r0, #0x32
	addw	r4, r4, #0xb68
	bl	fn_08008120
	movs	r0, #0x32
	bl	fn_08011c68
	movs	r0, #0x32
	bl	fn_08008120
	ldr	r1, .L0800bccc
	ldr.w	r0, [r8, #0xbe0]
	add.w	r0, r1, r0, lsl #4
	ldr	r1, [r4, #8]
	ldr.w	r1, [r0, r1, lsl #2]
	ldr	r0, .L0800bcd0
	ldr	r0, [r0, #0xc]
	bl	fn_080228d0
	movs	r0, #0
.L0800bc36:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0800bc3a:
	vmov	r0, s0
	cmp	r0, r1
	blt.n	.L0800bc58
	b.n	.L0800bb9e
.L0800bc44:
	vmov	r0, s0
	ldr	r1, .L0800bcd4
	cmp	r0, r1
	ble.n	.L0800bb9e
	vmov	r0, s0
	cmp.w	r0, #0x40000000
	bge.n	.L0800bb9e
.L0800bc58:
	ldr.w	r0, [r8, #0xbc8]
	bl	fn_0800a004
	add.w	r1, r0, r0, lsl #3
	add.w	r7, r8, r1, lsl #4
	vldr	s0, [r5, #0x3bc]
	bl	fn_08009fe0
	add.w	r0, r0, r0, lsl #1
	ldr.w	r1, [r4, #0xb64]
	add.w	r0, r7, r0, lsl #4
	add.w	r0, r0, r1, lsl #2
	vldr	s0, [r6, #0x348]
	add.w	r0, r0, #0x400
	vstr	s0, [r0, #0x1a4]
	ldr.w	r0, [r8, #0xbc8]
	bl	fn_0800a004
	add.w	r1, r0, r0, lsl #3
	add.w	r7, r8, r1, lsl #4
	vldr	s0, [r5, #0x3bc]
	bl	fn_08009fe0
	add.w	r0, r0, r0, lsl #1
	ldr.w	r1, [r4, #0xb64]
	add.w	r0, r7, r0, lsl #4
	add.w	r0, r0, r1, lsl #2
	vldr	s0, [r6, #0x350]
	add.w	r0, r0, #0x800
	vstr	s0, [r0, #0x74]
	movs	r0, #1
	b.n	.L0800bc36
.L0800bcc4:
	.word	0x2000457c
.L0800bcc8:
	.word	0x3f666666
.L0800bccc:
	.word	0x200000fc
.L0800bcd0:
	.word	0x20005954
.L0800bcd4:
	.word	0x3de147ae

@ ----------------------------------------------------------------------------
@ fn_0800bcd8 - sets default scaling state and redraws.
@ No parameters.
@ Stores 2 in word 0x200050ec (base 0x2000457c + 0xb70), calls
@ fn_08008120(0x32), stores 1000 in word 0x20001144 and the float 0x3f19999a
@ in 0x20001138, calls fn_08009f10. When word 0x200011c0 is 2 it copies 0x5a0
@ bytes from 0x20000b20 to 0x20000580 with copy_bytes_080070dc(dest, src,
@ count). Calls fn_08014b94, runs two counting loops without a body (3 x 3),
@ then tail-calls fn_080228d0(word 0x20005960, string pointer from the table
@ at 0x200000fc: entry [word 0x2000115c * 4 + word 0x200050ec]).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800bcd8,"ax",%progbits
	.p2align 2
	.global fn_0800bcd8
	.thumb_func
	.type fn_0800bcd8, %function
fn_0800bcd8:
	push	{r4, r5, r6, lr}
	ldr	r5, .L0800bd4c
	movs	r0, #2
	str.w	r0, [r5, #0xb70]
	movs	r0, #0x32
	bl	fn_08008120
	sub.w	r4, r5, #0x4000
	mov.w	r0, #0x3e8
	str.w	r0, [r4, #0xbc8]
	vldr	s0, .L0800bd50
	add.w	r0, r4, #0x800
	vstr	s0, [r0, #0x3bc]
	bl	fn_08009f10
	ldr.w	r0, [r4, #0xc44]
	cmp	r0, #2
	bne.n	.L0800bd1a
	mov.w	r2, #0x5a0
	addw	r1, r4, #0x5a4
	adds	r0, r4, #4
	bl	copy_bytes_080070dc
.L0800bd1a:
.ifdef OWN
	bl	own_save		@ 0x0800BD1A: our save (own/save.s)
.else
	bl	fn_08014b94
.endif
	movs	r1, #0
.L0800bd20:
	movs	r2, #2
.L0800bd22:
	.inst.n 0x1c52	@ adds r2, r2, #1
	cmp	r2, #5
	blt.n	.L0800bd22
	.inst.n 0x1c49	@ adds r1, r1, #1
	cmp	r1, #3
	blt.n	.L0800bd20
	ldr	r1, .L0800bd54
	ldr.w	r0, [r4, #0xbe0]
	add.w	r0, r1, r0, lsl #4
	ldr.w	r1, [r5, #0xb70]
	ldr.w	r1, [r0, r1, lsl #2]
	ldr	r0, .L0800bd58
	ldr	r0, [r0, #0xc]
	pop.w	{r4, r5, r6, lr}
	b.w	fn_080228d0
.L0800bd4c:
	.word	0x2000457c
.L0800bd50:
	.word	0x3f19999a
.L0800bd54:
	.word	0x200000fc
.L0800bd58:
	.word	0x20005954

@ ----------------------------------------------------------------------------
@ fn_0800bd5c - periodic update of the measured-value display and range steps.
@ No parameters. Returns at once unless word 0x20001168 (base 0x2000057c +
@ 0xbec) is 3.
@ When word 0x20000010 is below 5 it is incremented and, when the float at
@ 0x200050a0 is positive and below 0x3f800000 as an integer and word
@ 0x200011c0 is non-zero, 2 is stored in 0x200011c0.
@ Continues only when word 0x200011a8 is 5 and word 0x200011ac is non-zero.
@ When word 0x200050e4 is non-zero it increments 0x200050e8; at 0x2d (45) it
@ clears 0x200050e4 and calls fn_0800bcd8 when fn_0800bb64 returns non-zero.
@ At the counts 3, 6 (value 100), 9, 0xc, 0xf (0x78), 0x12, 0x15, 0x18
@ (1000), 0x1b, 0x1e, 0x21 (10000), 0x24, 0x27 and 0x2a (100000) it calls
@ fn_0800bb64 and, on non-zero, stores the value in 0x20001144 and the float
@ 0x3f19999a (counts 6, 0xf, 0x18, 0x21, 0x2a), 0x3dcccccd (counts 9, 0x12,
@ 0x1b, 0x24) or 0x3e99999a (counts 3, 0xc, 0x15, 0x1e, 0x27) in 0x20001138,
@ then calls fn_08009f10.
@ Finally calls fn_0800e028(float 0x200050c4, two 8-byte stack buffers, a word
@ set to 0) and fn_080228d0(word 0x2000595c, "%s%s", both buffers).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800bd5c,"ax",%progbits
	.p2align 2
	.global fn_0800bd5c
	.thumb_func
	.type fn_0800bd5c, %function
fn_0800bd5c:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r4, .L0800bea4
	vpush	{d8, d9}
	sub	sp, #0x18
	ldr.w	r0, [r4, #0xbec]
	cmp	r0, #3
	bne.n	.L0800be4e
	ldr	r1, .L0800bea8
	add.w	r6, r4, #0x4800
	ldr	r0, [r1, #4]
	cmp	r0, #5
	bcs.n	.L0800bda4
	.inst.n 0x1c40	@ adds r0, r0, #1
	str	r0, [r1, #4]
	vldr	s0, [r6, #0x324]
	vmov	r0, s0
	cmp.w	r0, #0x3f800000
	bge.n	.L0800bda4
	vcmpe.f32	s0, #0
	vmrs	APSR_nzcv, fpscr
	ble.n	.L0800bda4
	ldr.w	r0, [r4, #0xc44]
	cbz	r0, .L0800bda4
	movs	r0, #2
	str.w	r0, [r4, #0xc44]
.L0800bda4:
	ldr.w	r0, [r4, #0xc2c]
	cmp	r0, #5
	bne.n	.L0800be7c
	ldr.w	r0, [r4, #0xc30]
	cmp	r0, #0
	beq.n	.L0800be7c
	ldr	r1, .L0800beac
	mov.w	r8, #0
	ldr.w	r0, [r1, #0xb68]
	cbz	r0, .L0800be24
	ldr.w	r0, [r1, #0xb6c]
	.inst.n 0x1c40	@ adds r0, r0, #1
	str.w	r0, [r1, #0xb6c]
	cmp	r0, #0x2d
	beq.n	.L0800be26
	ldr	r7, .L0800beb0
	vldr	s16, .L0800beb4
	sub.w	r5, r1, #0x3800
	cmp	r0, #0x2a
	beq.n	.L0800be90
	cmp	r0, #0x27
	vldr	s17, .L0800beb8
	beq.n	.L0800be9a
	cmp	r0, #0x24
	vldr	s18, .L0800bebc
	beq.n	.L0800be86
	movw	r7, #0x2710
	cmp	r0, #0x21
	beq.n	.L0800be90
	cmp	r0, #0x1e
	beq.n	.L0800be9a
	cmp	r0, #0x1b
	beq.n	.L0800be86
	mov.w	r7, #0x3e8
	cmp	r0, #0x18
	beq.n	.L0800be90
	cmp	r0, #0x15
	beq.n	.L0800be9a
	cmp	r0, #0x12
	beq.n	.L0800be86
	movs	r7, #0x78
	cmp	r0, #0xf
	beq.n	.L0800be90
	cmp	r0, #0xc
	beq.n	.L0800be9a
	cmp	r0, #9
	beq.n	.L0800be86
	movs	r7, #0x64
	cmp	r0, #6
	beq.n	.L0800be90
	cmp	r0, #3
	beq.n	.L0800be9a
.L0800be24:
	b.n	.L0800be5c
.L0800be26:
	str.w	r8, [r1, #0xb68]
	bl	fn_0800bb64
	cbz	r0, .L0800be5c
	bl	fn_0800bcd8
	b.n	.L0800be5c
	.byte	0x00, 0xbf	@ padding
.L0800be38:
	str.w	r7, [r4, #0xbc8]
	vstr	s16, [r5, #0x3bc]
	b.n	.L0800be58
	.byte	0x00, 0xbf	@ padding
.L0800be44:
	str.w	r7, [r4, #0xbc8]
	vstr	s17, [r5, #0x3bc]
	b.n	.L0800be58
.L0800be4e:
	b.n	.L0800be7c
.L0800be50:
	str.w	r7, [r4, #0xbc8]
	vstr	s18, [r5, #0x3bc]
.L0800be58:
	bl	fn_08009f10
.L0800be5c:
	str.w	r8, [sp, #0x10]
	vldr	s0, [r6, #0x348]
	add	r2, sp, #0x10
	add	r1, sp, #8
	mov	r0, sp
	bl	fn_0800e028
	ldr	r0, .L0800bec0
	add	r3, sp, #8
	mov	r2, sp
	ldr	r0, [r0, #8]
	adr.n	r1, .L0800bec4
	bl	fn_080228d0
.L0800be7c:
	add	sp, #0x18
	vpop	{d8, d9}
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0800be86:
	bl	fn_0800bb64
	cmp	r0, #0
	bne.n	.L0800be50
	b.n	.L0800be5c
.L0800be90:
	bl	fn_0800bb64
	cmp	r0, #0
	bne.n	.L0800be38
	b.n	.L0800be5c
.L0800be9a:
	bl	fn_0800bb64
	cmp	r0, #0
	bne.n	.L0800be44
	b.n	.L0800be5c
.L0800bea4:
	.word	0x2000057c
.L0800bea8:
	.word	0x2000000c
.L0800beac:
	.word	0x2000457c
.L0800beb0:
	.word	0x000186a0
.L0800beb4:
	.word	0x3f19999a
.L0800beb8:
	.word	0x3e99999a
.L0800bebc:
	.word	0x3dcccccd
.L0800bec0:
	.word	0x20005954
.L0800bec4:
	.asciz	"%s%s"
	.byte	0x00, 0x00, 0x00	@ padding

@ ----------------------------------------------------------------------------
@ fn_0800c724 - supply-voltage range selection and low-voltage handling.
@ No parameters, no return value.
@ Calls fn_080092cc. r6 = 0x20004d7c, r4 = 0x2000028c, r5 = 0x2000457c,
@ r7 = 0x404ccccd (3.2f), r8 = 0. w = word 0x20005100 (r6 + 0x384), a float
@ whose bit pattern is compared as a signed integer: w > 0x40866666 (4.2f)
@ stores 0x40866666 in w; w < 0x404ccccd stores 0x404ccccd in w.
@ Selects r1 from w (signed compares of the bit pattern): w > 0x40800000
@ (4.0f): d_08044990; else w > 0x40733333 (3.8f): d_08044844; else w >
@ 0x40666666 (3.6f): d_080446e8; else w > 0x4059999a (3.4f): d_0804459c; else
@ d_08044440. For w > 0x404ccccd with any of these it calls
@ fn_08021c14(word 0x2000028c, r1) and continues at 0x0800c7c8.
@ w = 0x404ccccd: calls fn_08021c14(word 0x2000028c, d_08044440), then when
@ word 0x20005118 (r5 + 0xb9c) is non-zero it goes to 0x0800c7c8; otherwise
@ calls float_to_double(w), passes the result as the double in r2:r3 with
@ r0 = the string "Low Voltage Power Off:%f\n" to fn_0801031c, stores 0 in
@ words 0x20005110 and 0x20005114, stores 10 in word 0x20005118 and calls
@ fn_0800cf68(1).
@ 0x0800c7c8: when w > 0x404ccccd and word 0x20005118 is non-zero it stores 0
@ there, calls fn_08023690(word 0x20000290), then tail-calls
@ fn_08023690(word 0x20000294); otherwise it returns (pop pc at 0x0800c7ec).
@ Entered by the tail branch at 0x0800c862 of the function at 0x0800c848.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c724,"ax",%progbits
	.p2align 2
	.global fn_0800c724
	.thumb_func
	.type fn_0800c724, %function
fn_0800c724:
	push.w	{r4, r5, r6, r7, r8, lr}
	bl	fn_080092cc
	ldr	r6, .L0800c7f0
	ldr	r1, .L0800c7f4
	ldr.w	r0, [r6, #0x384]
	cmp	r0, r1
	ble.n	.L0800c740
	vldr	s0, .L0800c7f8
	vstr	s0, [r6, #0x384]
.L0800c740:
	ldr	r7, .L0800c7fc
	ldr.w	r0, [r6, #0x384]
	cmp	r0, r7
	bge.n	.L0800c752
	vldr	s0, .L0800c800
	vstr	s0, [r6, #0x384]
.L0800c752:
	ldr.w	r0, [r6, #0x384]
	ldr	r4, .L0800c804
	ldr	r5, .L0800c808
	mov.w	r8, #0
	cmp.w	r0, #0x40800000
	ble.n	.L0800c768
	ldr	r1, .L0800c80c
	b.n	.L0800c784
.L0800c768:
	ldr	r1, .L0800c810
	cmp	r0, r1
	ble.n	.L0800c772
	ldr	r1, .L0800c814
	b.n	.L0800c784
.L0800c772:
	ldr	r1, .L0800c818
	cmp	r0, r1
	ble.n	.L0800c77c
	ldr	r1, .L0800c81c
	b.n	.L0800c784
.L0800c77c:
	ldr	r1, .L0800c820
	cmp	r0, r1
	ble.n	.L0800c78c
	ldr	r1, .L0800c824
.L0800c784:
	ldr	r0, [r4]
	bl	fn_08021c14
	b.n	.L0800c7c8
.L0800c78c:
	ldr	r1, .L0800c828
	cmp	r0, r7
	bgt.n	.L0800c784
	ldr	r0, [r4]
	bl	fn_08021c14
	ldr.w	r0, [r5, #0xb9c]
	cbnz	r0, .L0800c7c8
	ldr.w	r0, [r6, #0x384]
	bl	float_to_double
	vmov	d0, r0, r1
	adr.n	r0, .L0800c82c
	vmov	r2, r3, d0
	bl	fn_0801031c
	str.w	r8, [r5, #0xb94]
	movs	r1, #0xa
	str.w	r8, [r5, #0xb98]
	movs	r0, #1
	str.w	r1, [r5, #0xb9c]
	bl	fn_0800cf68
.L0800c7c8:
	ldr.w	r0, [r6, #0x384]
	cmp	r0, r7
	ble.n	.L0800c7ec
	ldr.w	r0, [r5, #0xb9c]
	cmp	r0, #0
	beq.n	.L0800c7ec
	str.w	r8, [r5, #0xb9c]
	ldr	r0, [r4, #4]
	bl	fn_08023690
	ldr	r0, [r4, #8]
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08023690
.L0800c7ec:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0800c7f0:
	.word	0x20004d7c
.L0800c7f4:
	.word	0x40866666
.L0800c7f8:
	.word	0x40866666
.L0800c7fc:
	.word	0x404ccccd
.L0800c800:
	.word	0x404ccccd
.L0800c804:
	.word	0x2000028c
.L0800c808:
	.word	0x2000457c
.L0800c80c:
	.word	d_08044990
.L0800c810:
	.word	0x40733333
.L0800c814:
	.word	d_08044844
.L0800c818:
	.word	0x40666666
.L0800c81c:
	.word	d_080446e8
.L0800c820:
	.word	0x4059999a
.L0800c824:
	.word	d_0804459c
.L0800c828:
	.word	d_08044440
.L0800c82c:
	.asciz	"Low Voltage Power Off:%f\n"
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ copy_flash_block_to_ram - copies the stored parameter block to RAM.
@ No parameters, no return value.
@ Copies 0xc14 bytes (in 4-byte words, loop 0x08014b80..0x08014b88) from
@ 0x0807f000 (literal at 0x08014b8c) to RAM 0x2000057c (literal at
@ 0x08014b90).
@ ----------------------------------------------------------------------------
	.section .text.copy_flash_block_to_ram,"ax",%progbits
	.p2align 2
	.global copy_flash_block_to_ram
	.thumb_func
	.type copy_flash_block_to_ram, %function
copy_flash_block_to_ram:
	push	{r4, lr}
	ldr	r2, .L08014b8c
	ldr	r3, .L08014b90
	movs	r0, #0
	movw	r4, #0xc14
.L08014b80:
	ldr	r1, [r0, r2]
	str	r1, [r3, r0]
	.inst.n 0x1d00	@ adds r0, r0, #4
	cmp	r0, r4
	bcc.n	.L08014b80
	pop	{r4, pc}
.L08014b8c:
	.word	0x0807f000
.L08014b90:
	.word	0x2000057c

@ ----------------------------------------------------------------------------
@ fn_08014b94 - writes the RAM parameter block to the flash page area.
@ No parameters, no return value.
@ Calls fn_08008e04 (writes 0x45670123 then 0xcdef89ab to 0x40022004), then
@ fn_08008d30 for 0x0807f000 and for 0x0807f800 (each: fn_08008d20(0x7c) ORs
@ 0x7c into word 0x4002200c, fn_08008e1c(0xb0000) waits, and only when that
@ wait returns 6 it sets bit 1 of 0x40022010, writes the address to
@ 0x40022014, sets bit 6 of 0x40022010, waits again with fn_08008e1c(0xb0000),
@ then ANDs 0x40022010 with 0x3ffd).
@ Loops 0xc14 bytes in 4-byte steps calling fn_0800811c(0x0807f000 + offset,
@ word at 0x2000057c + offset).
@ Ends with a tail branch (b.w at 0x08014bc4) to fn_08008db0, which sets bit
@ 7 of 0x40022010.
@ ----------------------------------------------------------------------------
	.section .text.fn_08014b94,"ax",%progbits
	.p2align 2
	.global fn_08014b94
	.thumb_func
	.type fn_08014b94, %function
fn_08014b94:
	push.w	{r4, r5, r6, r7, r8, lr}
	bl	fn_08008e04
	ldr	r5, .L08014bc8
	mov	r0, r5
	bl	fn_08008d30
	ldr	r0, .L08014bcc
	bl	fn_08008d30
	ldr	r6, .L08014bd0
	movs	r4, #0
	movw	r7, #0xc14
.L08014bb2:
	ldr	r1, [r6, r4]
	adds	r0, r4, r5
	bl	fn_0800811c
	.inst.n 0x1d24	@ adds r4, r4, #4
	cmp	r4, r7
	bcc.n	.L08014bb2
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08008db0
.L08014bc8:
	.word	0x0807f000
.L08014bcc:
	.word	0x0807f800
.L08014bd0:
	.word	0x2000057c

