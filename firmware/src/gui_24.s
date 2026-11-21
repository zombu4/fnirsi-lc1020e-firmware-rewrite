@ gui_24.s - GUI object size, layout and key handling routines (0x08025a00..0x080269b8)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08025a00 - recomputes the width and height of an object.
@ r0 = object; returns 1 when the size changed, else 0.
@ Returns 0 when bits 9 and 10 (0x200, 0x400) of the halfword at object+0x22 are
@ both set (lsls #21 tests bit 10, lsls #22 tests bit 9) or when there is no
@ parent (fn_08023fa4).
@ Computes the new width and height from keys 1-3 and 4-6 (fn_08024cfc,
@ fn_080249cc, fn_08024bac, fn_0801d662, fn_0801d5f8); the value 0x27d1 selects
@ fn_0801402c (width) / fn_08013f48 (height); percent values (bits 13-14 == 1,
@ value below 0x7d1) scale the parent size by value/100 (sdiv by 100).
@ When the size differs: fn_08025400, fn_08023dec, fn_08011e9c, updates
@ object+0x1a and +0x14/+0x18, sends message 0x29 and message 0x22 to the parent
@ (fn_080207f4), fn_080256cc, fn_08025cac; returns 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08025a00,"ax",%progbits
	.p2align 2
	.global fn_08025a00
	.thumb_func
	.type fn_08025a00, %function
fn_08025a00:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r4, r0
	ldrh	r0, [r0, #0x22]
	sub	sp, #0x1c
	lsls	r1, r0, #0x15
	bpl.n	.L08025a12
	lsls	r0, r0, #0x16
	bmi.n	.L08025b10
.L08025a12:
	mov	r0, r4
	bl	fn_08023fa4
	movs.w	r8, r0
	beq.n	.L08025b10
	mov	r0, r4
	bl	fn_08024070
	str	r0, [sp, #4]
	ldrh	r0, [r4, #0x22]
	movs	r6, #0
	lsls	r0, r0, #0x15
	mov.w	r11, #0x7d0
	movw	r10, #0x27d1
	bpl.n	.L08025a3e
	mov	r0, r4
	bl	rect_width_plus_one
	b.n	.L08025afa
.L08025a3e:
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024cfc
	mov	r5, r0
	cmp	r0, r10
	bne.n	.L08025a50
	movs	r6, #1
	b.n	.L08025a52
.L08025a50:
	movs	r6, #0
.L08025a52:
	ubfx	r0, r5, #0xd, #2
	cmp	r0, #1
	bne.n	.L08025a66
	bic.w	r0, r5, #0x6000
	cmp	r0, r11
	bgt.n	.L08025a66
	movs	r0, #1
	b.n	.L08025a68
.L08025a66:
	movs	r0, #0
.L08025a68:
	mov	r9, r0
	mov	r0, r8
	bl	fn_08023e7c
	mov	r7, r0
	cbz	r6, .L08025a7e
	mov	r0, r4
	bl	fn_0801402c
	mov	r5, r0
	b.n	.L08025ad6
.L08025a7e:
	cmp.w	r9, #0
	beq.n	.L08025ad6
	ldrh.w	r0, [r8, #0x22]
	lsls	r0, r0, #0x15
	bmi.n	.L08025abe
	movs	r1, #0
	mov	r0, r8
	bl	fn_08024cfc
	cmp	r0, r10
	bne.n	.L08025abe
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024984
	mov	r5, r0
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024ae0
	add.w	r9, r0, r5
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024b1c
	adds	r1, r0, r5
	add.w	r0, r1, r9
	b.n	.L08025ad4
.L08025abe:
	bic.w	r0, r5, #0x6000
	cmp.w	r0, #0x3e8
	ble.n	.L08025acc
	rsb.w	r0, r0, #0x3e8
.L08025acc:
	muls	r0, r7, r0
	movs	r1, #0x64
	sdiv	r0, r0, r1
.L08025ad4:
	sxth	r5, r0
.L08025ad6:
	mov	r0, r4
	movs	r1, #0
	movs	r2, #2
	bl	fn_08024bac
	sxth.w	r9, r0
	mov	r0, r4
	movs	r1, #0
	movs	r2, #3
	bl	fn_08024bac
	sxth	r2, r0
	mov	r3, r7
	mov	r1, r9
	mov	r0, r5
	bl	fn_0801d662
.L08025afa:
	mov	r7, r0
	mov	r0, r4
	bl	fn_08024208
	str	r0, [sp]
	ldrh	r0, [r4, #0x22]
	mov.w	r9, #0
	lsls	r0, r0, #0x16
	bpl.n	.L08025b1a
	b.n	.L08025b12
.L08025b10:
	b.n	.L08025bea
.L08025b12:
	mov	r0, r4
	bl	rect_height_plus_one
	b.n	.L08025bc2
.L08025b1a:
	movs	r1, #0
	mov	r0, r4
	bl	fn_080249cc
	sub.w	r1, r0, #0x2700
	mov	r5, r0
	subs	r1, #0xd1
	beq.n	.L08025b3a
	movs	r0, #0
.L08025b2e:
	mov	r9, r0
	ubfx	r0, r5, #0xd, #2
	cmp	r0, #1
	beq.n	.L08025b3e
	b.n	.L08025b4a
.L08025b3a:
	movs	r0, #1
	b.n	.L08025b2e
.L08025b3e:
	bic.w	r0, r5, #0x6000
	cmp	r0, r11
	bgt.n	.L08025b4a
	movs	r0, #1
	b.n	.L08025b4c
.L08025b4a:
	movs	r0, #0
.L08025b4c:
	mov	r11, r0
	mov	r0, r8
	bl	fn_08023e48
	mov	r10, r0
	cmp.w	r9, #0
	beq.n	.L08025b66
	mov	r0, r4
	bl	fn_08013f48
	mov	r5, r0
	b.n	.L08025b9e
.L08025b66:
	cmp.w	r11, #0
	beq.n	.L08025b9e
	ldrh.w	r0, [r8, #0x22]
	lsls	r0, r0, #0x16
	bmi.n	.L08025b84
	movs	r1, #0
	mov	r0, r8
	bl	fn_080249cc
	sub.w	r1, r0, #0x2700
	subs	r1, #0xd1
	beq.n	.L08025bf2
.L08025b84:
	bic.w	r0, r5, #0x6000
	cmp.w	r0, #0x3e8
	ble.n	.L08025b92
	rsb.w	r0, r0, #0x3e8
.L08025b92:
	mul	r0, r0, r10
	movs	r1, #0x64
	sdiv	r0, r0, r1
.L08025b9c:
	sxth	r5, r0
.L08025b9e:
	mov	r0, r4
	movs	r1, #0
	movs	r2, #5
	bl	fn_08024bac
	sxth.w	r11, r0
	mov	r0, r4
	movs	r1, #0
	movs	r2, #6
	bl	fn_08024bac
	sxth	r2, r0
	mov	r3, r10
	mov	r1, r11
	mov	r0, r5
	bl	fn_0801d5f8
.L08025bc2:
	mov	r5, r0
	orrs.w	r6, r6, r9
	beq.n	.L08025bd6
	ldrd	r2, r1, [sp]
	movs	r3, #0
	mov	r0, r4
	bl	fn_08026216
.L08025bd6:
	mov	r0, r4
	bl	rect_width_plus_one
	cmp	r0, r7
	bne.n	.L08025c18
	mov	r0, r4
	bl	rect_height_plus_one
	cmp	r0, r5
	bne.n	.L08025c18
.L08025bea:
	movs	r0, #0
.L08025bec:
	add	sp, #0x1c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08025bf2:
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024984
	mov	r5, r0
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024b70
	add.w	r11, r0, r5
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024a80
	adds	r1, r0, r5
	add.w	r0, r1, r11
	b.n	.L08025b9c
.L08025c18:
	mov	r0, r4
	bl	fn_08025400
	add	r1, sp, #8
	mov	r0, r4
	bl	fn_08023eb0
	add	r1, sp, #0x10
	mov	r0, r8
	bl	fn_08023dec
	movs	r2, #0
	add	r1, sp, #0x10
	add	r0, sp, #8
	bl	fn_08011e9c
	movs	r6, r0
	bne.n	.L08025c42
	mov	r0, r8
	bl	fn_080262c4
.L08025c42:
	ldrh	r0, [r4, #0x16]
	.inst.n 0x1e6d	@ subs r5, r5, #1
	add	r0, r5
	strh	r0, [r4, #0x1a]
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024906
	cmp	r0, #1
	beq.n	.L08025c90
	ldrh	r0, [r4, #0x14]
	.inst.n 0x1e7f	@ subs r7, r7, #1
	add	r0, r7
	strh	r0, [r4, #0x18]
.L08025c5e:
	add	r2, sp, #8
	movs	r1, #0x29
	mov	r0, r4
	bl	fn_080207f4
	mov	r2, r4
	movs	r1, #0x22
	mov	r0, r8
	bl	fn_080207f4
	mov	r0, r4
	bl	fn_08025400
	movs	r1, #0
	mov	r0, r4
	bl	fn_080256cc
	movs	r2, #0
	add	r1, sp, #0x10
	add.w	r0, r4, #0x14
	bl	fn_08011e9c
	cbnz	r6, .L08025c9c
	b.n	.L08025c9a
.L08025c90:
	ldrh	r0, [r4, #0x18]
	subs	r0, r0, r7
	.inst.n 0x1c40	@ adds r0, r0, #1
	strh	r0, [r4, #0x14]
	b.n	.L08025c5e
.L08025c9a:
	cbz	r0, .L08025ca2
.L08025c9c:
	mov	r0, r8
	bl	fn_080262c4
.L08025ca2:
	mov	r0, r4
	bl	fn_08025cac
	movs	r0, #1
	b.n	.L08025bec

@ ----------------------------------------------------------------------------
@ fn_08025cac - re-reads an object's value through message 0x13.
@ r0 = object; no other input (r3 is pushed only as a stack slot); no return value.
@ Gets fn_08012726, clears the halfword at [sp] (strh at 0x08025cb8) and sends
@ message 0x13 to the object with fn_080207f4 (the halfword at [sp] is the
@ result). When the result differs from fn_08012726 calls fn_08025400.
@ Stores the result at halfword [object+8]+0x16 (allocating the block with
@ fn_0802318c when object+8 is zero and the value is nonzero) and calls
@ fn_08025400 again when it differs.
@ ----------------------------------------------------------------------------
	.section .text.fn_08025cac,"ax",%progbits
	.p2align 2
	.global fn_08025cac
	.thumb_func
	.type fn_08025cac, %function
fn_08025cac:
	push	{r3, r4, r5, lr}
	mov	r4, r0
	bl	fn_08012726
	mov	r5, r0
	movs	r0, #0
	strh.w	r0, [sp]
	mov	r2, sp
	movs	r1, #0x13
	mov	r0, r4
	bl	fn_080207f4
	ldrsh.w	r0, [sp]
	cmp	r0, r5
	beq.n	.L08025cd4
	mov	r0, r4
	bl	fn_08025400
.L08025cd4:
	ldr	r0, [r4, #8]
	cbz	r0, .L08025ce0
	ldrh.w	r1, [sp]
	strh	r1, [r0, #0x16]
	b.n	.L08025cf4
.L08025ce0:
	ldrh.w	r0, [sp]
	cbz	r0, .L08025cf4
	mov	r0, r4
	bl	fn_0802318c
	ldr	r1, [r4, #8]
	ldrh.w	r0, [sp]
	strh	r0, [r1, #0x16]
.L08025cf4:
	ldrsh.w	r0, [sp]
	cmp	r0, r5
	beq.n	.L08025d02
	mov	r0, r4
	bl	fn_08025400
.L08025d02:
	pop	{r3, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_08025d04 - tests whether width or height is the special value 0x27d1.
@ r0 = object; returns 1 or 0.
@ When fn_08024cfc or fn_080249cc equals 0x27d1 calls fn_08025522 and returns
@ 1, else returns 0. Ends with 2 bytes of padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08025d04,"ax",%progbits
	.p2align 2
	.global fn_08025d04
	.thumb_func
	.type fn_08025d04, %function
fn_08025d04:
	push	{r4, r5, r6, lr}
	mov	r5, r0
	movs	r1, #0
	bl	fn_08024cfc
	mov	r4, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_080249cc
	movw	r1, #0x27d1
	cmp	r4, r1
	beq.n	.L08025d28
	cmp	r0, r1
	beq.n	.L08025d28
	movs	r0, #0
	pop	{r4, r5, r6, pc}
.L08025d28:
	mov	r0, r5
	bl	fn_08025522
	movs	r0, #1
	pop	{r4, r5, r6, pc}
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_08025d34 - updates an object after a key change.
@ r0 = object, r1 = class mask (bits 16-23 used), r2 = key (0xffff = all);
@ no return value.
@ Returns when the byte at 0x200004b0 is 0.
@ fn_08025400; tests the key with fn_08026fec using masks 4, 2, 1, 0x10.
@ Mask 4: sends message 0x2a (fn_080207f4) and calls fn_08025522 when the class
@ mask is 0xf0000, 0, or key 4 or key 1 equals 0x27d1 (either one).
@ Mask 0x10 with class 0xf0000 or 0: sets bits 6-7 of the byte [object+8]+0x1a
@ to 0, 1 or 2 from keys 0x6d, 0x6c (0x100), fn_08024a44 and 0x67
@ (allocating the block with fn_0802318c when object+8 is zero).
@ Key 0xffff or mask 2: fn_08025cac; fn_08025400 again and, when the class mask
@ is not 0x10000 and the key is 0xffff or ((mask2|mask4) & mask1) is nonzero,
@ tail call to fn_080291b6.
@ ----------------------------------------------------------------------------
	.section .text.fn_08025d34,"ax",%progbits
	.p2align 2
	.global fn_08025d34
	.thumb_func
	.type fn_08025d34, %function
fn_08025d34:
	push.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r4, r0
	ldr	r0, .L08025e7c
	mov	r8, r2
	mov	r5, r1
	ldrb	r0, [r0]
	cmp	r0, #0
	beq.n	.L08025e24
	mov	r0, r4
	bl	fn_08025400
	and	r5, r5, #0xff0000
	movs	r1, #4
	mov	r0, r8
	bl	fn_08026fec
	mov	r6, r0
	movs	r1, #2
	mov	r0, r8
	bl	fn_08026fec
	mov	r9, r0
	movs	r1, #1
	mov	r0, r8
	bl	fn_08026fec
	str	r0, [sp]
	movs	r1, #0x10
	mov	r0, r8
	bl	fn_08026fec
	mov	r7, r0
	movw	r11, #0xffff
	cbz	r6, .L08025dba
	cmp.w	r5, #0xf0000
	beq.n	.L08025daa
	cbz	r5, .L08025daa
	mov	r0, r4
	movs	r1, #0
	movs	r2, #4
	bl	fn_08024bac
	sxth	r0, r0
	movw	r10, #0x27d1
	cmp	r0, r10
	beq.n	.L08025daa
	mov	r0, r4
	movs	r1, #0
	movs	r2, #1
	bl	fn_08024bac
	sxth	r0, r0
	cmp	r0, r10
	bne.n	.L08025e42
.L08025daa:
	movs	r2, #0
	movs	r1, #0x2a
	mov	r0, r4
	bl	fn_080207f4
	mov	r0, r4
	bl	fn_08025522
.L08025dba:
	mov.w	r10, #0xf0000
	cmp	r5, r10
	beq.n	.L08025dc4
	cbnz	r5, .L08025e22
.L08025dc4:
	cmp	r8, r11
	beq.n	.L08025dca
	cbz	r6, .L08025dd6
.L08025dca:
	mov	r0, r4
	bl	fn_08023fa4
	cbz	r0, .L08025dd6
	bl	fn_08025522
.L08025dd6:
	cmp	r5, r10
	beq.n	.L08025ddc
	cbnz	r5, .L08025e22
.L08025ddc:
	cbz	r7, .L08025e22
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x6d
	bl	fn_08024bac
	sxth	r0, r0
	cbnz	r0, .L08025dfe
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x6c
	bl	fn_08024bac
	sxth	r0, r0
	cmp.w	r0, #0x100
	beq.n	.L08025e02
.L08025dfe:
	movs	r7, #2
	b.n	.L08025e28
.L08025e02:
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024a44
	cmp	r0, #0xff
	bne.n	.L08025e1e
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x67
	bl	fn_08024bac
	tst.w	r0, #0xff
	beq.n	.L08025e26
.L08025e1e:
	movs	r7, #1
	b.n	.L08025e28
.L08025e22:
	b.n	.L08025e42
.L08025e24:
	b.n	.L08025e78
.L08025e26:
	movs	r7, #0
.L08025e28:
	ldr	r0, [r4, #8]
	cbz	r0, .L08025e36
.L08025e2c:
	ldrb	r1, [r0, #0x1a]
	bfi	r1, r7, #6, #2
	strb	r1, [r0, #0x1a]
	b.n	.L08025e42
.L08025e36:
	cbz	r7, .L08025e42
	mov	r0, r4
	bl	fn_0802318c
	ldr	r0, [r4, #8]
	b.n	.L08025e2c
.L08025e42:
	mov	r7, r11
	cmp	r8, r7
	beq.n	.L08025e4e
	cmp.w	r9, #0
	beq.n	.L08025e54
.L08025e4e:
	mov	r0, r4
	bl	fn_08025cac
.L08025e54:
	mov	r0, r4
	bl	fn_08025400
	cmp	r8, r7
	beq.n	.L08025e68
	ldr	r1, [sp]
	orr.w	r0, r9, r6
	tst	r0, r1
	beq.n	.L08025e78
.L08025e68:
	cmp.w	r5, #0x10000
	beq.n	.L08025e78
	mov	r0, r4
	pop.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w	fn_080291b6
.L08025e78:
	pop.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08025e7c:
	.word	0x200004b0

@ ----------------------------------------------------------------------------
@ fn_08025e80 - looks up an entry by id and notifies on a key match.
@ r0 = object, r1 = key, r2 = entry id; returns 1 when the key was handled,
@ else 0.
@ Scans the 8-byte entries at [object+0xc] (count = (halfword at object+0x22
@ & 0x1ff) >> 3) for one whose second word has bit 24 set and low 24 bits equal
@ to r2.
@ Calls fn_0802705c with the first word of the entry and the key; when it
@ returns nonzero calls fn_08025d34 (object, r2, key) and returns 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08025e80,"ax",%progbits
	.global fn_08025e80
	.thumb_func
	.type fn_08025e80, %function
fn_08025e80:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r4, r0
	mov	r6, r1
	ldrh	r0, [r0, #0x22]
	movs	r1, #0
	mov	r5, r2
	movs	r3, #4
	ubfx	r0, r0, #3, #6
	b.n	.L08025eae
	nop			@ padding
.L08025e98:
	ldr	r2, [r4, #0xc]
	add.w	r7, r3, r1, lsl #3
	ldr	r2, [r2, r7]
	lsls	r7, r2, #7
	bpl.n	.L08025eac
	bic.w	r2, r2, #0xff000000
	cmp	r2, r5
	beq.n	.L08025eb2
.L08025eac:
	.inst.n 0x1c49	@ adds r1, r1, #1
.L08025eae:
	cmp	r0, r1
	bhi.n	.L08025e98
.L08025eb2:
	cmp	r0, r1
	bne.n	.L08025ebc
	movs	r0, #0
.L08025eb8:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08025ebc:
	ldr	r0, [r4, #0xc]
	ldr.w	r0, [r0, r1, lsl #3]
	mov	r1, r6
	bl	fn_0802705c
	cbz	r0, .L08025ed6
	mov	r2, r6
	mov	r1, r5
	mov	r0, r4
	bl	fn_08025d34
	b.n	.L08025eda
.L08025ed6:
	cmp	r0, #0
	beq.n	.L08025eb8
.L08025eda:
	movs	r0, #1
	b.n	.L08025eb8

@ ----------------------------------------------------------------------------
@ fn_08025ede - removes matching entries from an object's 8-byte entry table.
@ r0 = object, r1 = entry pointer or 0, r2 = key word (low 16 bits 0xffff = any);
@ no return value.
@ class = r2 & 0xff0000; notify key = 0xffff, or 0 when r1 is nonzero and
@ byte(r1+7) is 0.
@ Scans the 8-byte entries at [object+0xc] (count = (halfword at object+0x22
@ & 0x1ff) >> 3) matching key, class (0xf0000 = any) and entry pointer;
@ matching entries with bit 25 call fn_0802ac24; entries with bit 24 or 25 are
@ released with fn_0802711a and fn_08022c68; later entries move down by one,
@ the count in bits 3-8 of the halfword at object+0x22 decreases and the table
@ is resized with fn_08022cb0.
@ At the end tail-calls fn_08025d34 (object, class, notify key) when something
@ was removed and the notify key is nonzero. Ends with 2 bytes of padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08025ede,"ax",%progbits
	.global fn_08025ede
	.thumb_func
	.type fn_08025ede, %function
fn_08025ede:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	movw	r10, #0xffff
	movs	r7, r1
	mov	r5, r0
	uxth.w	r8, r2
	and	r9, r2, #0xff0000
	mov	r6, r10
	beq.n	.L08025efc
	ldrb	r0, [r7, #7]
	cbnz	r0, .L08025efc
	movs	r6, #0
.L08025efc:
	movs	r4, #0
	mov	r1, r4
	b.n	.L08025fb6
.L08025f02:
	ldr	r2, [r5, #0xc]
	movs	r0, #4
	add.w	r11, r0, r4, lsl #3
	mov	lr, r2
	ldr.w	r0, [r2, r11]
	ubfx	r2, r0, #0x10, #8
	lsl.w	r12, r2, #0x10
	mov	r2, r10
	uxth	r3, r0
	cmp	r8, r2
	beq.n	.L08025f24
	cmp	r3, r8
	bne.n	.L08025f38
.L08025f24:
	cmp.w	r9, #0xf0000
	beq.n	.L08025f2e
	cmp	r12, r9
	bne.n	.L08025f38
.L08025f2e:
	cbz	r7, .L08025f3c
	ldr.w	r3, [lr, r4, lsl #3]
	cmp	r3, r7
	beq.n	.L08025f3c
.L08025f38:
	.inst.n 0x1c64	@ adds r4, r4, #1
	b.n	.L08025fb6
.L08025f3c:
	lsls	r0, r0, #6
	bpl.n	.L08025f4a
	movs	r3, #0
	mov	r1, r9
	mov	r0, r5
	bl	fn_0802ac24
.L08025f4a:
	ldr	r0, [r5, #0xc]
	ldr.w	r1, [r0, r11]
	lsls	r2, r1, #7
	bmi.n	.L08025f58
	lsls	r1, r1, #6
	bpl.n	.L08025f72
.L08025f58:
	ldr.w	r0, [r0, r4, lsl #3]
	bl	fn_0802711a
	ldr	r0, [r5, #0xc]
	ldr.w	r0, [r0, r4, lsl #3]
	bl	fn_08022c68
	ldr	r1, [r5, #0xc]
	movs	r0, #0
	str.w	r0, [r1, r4, lsl #3]
.L08025f72:
	mov	r0, r4
	movs	r2, #8
	b.n	.L08025f8e
.L08025f78:
	ldr	r1, [r5, #0xc]
	add.w	r12, r2, r0, lsl #3
	add.w	r3, r1, r0, lsl #3
	add	r1, r12
	.inst.n 0x1c40	@ adds r0, r0, #1
	ldrd	r12, r1, [r1]
	strd	r12, r1, [r3]
.L08025f8e:
	ldrh	r1, [r5, #0x22]
	ubfx	r1, r1, #3, #6
	.inst.n 0x1e49	@ subs r1, r1, #1
	cmp	r1, r0
	bhi.n	.L08025f78
	ldrh	r0, [r5, #0x22]
	lsrs	r1, r0, #3
	.inst.n 0x1e49	@ subs r1, r1, #1
	bfi	r0, r1, #3, #6
	strh	r0, [r5, #0x22]
	ubfx	r0, r0, #3, #6
	lsls	r1, r0, #3
	ldr	r0, [r5, #0xc]
	bl	fn_08022cb0
	movs	r1, #1
	str	r0, [r5, #0xc]
.L08025fb6:
	ldrh	r0, [r5, #0x22]
	ubfx	r0, r0, #3, #6
	cmp	r0, r4
	bhi.n	.L08025f02
	cmp	r1, #0
	beq.n	.L08025fd6
	cmp	r6, #0
	beq.n	.L08025fd6
	mov	r2, r6
	mov	r1, r9
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	b.w	fn_08025d34
.L08025fd6:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_08025fdc - calls fn_08029236 for every element of every node.
@ r0 = argument passed on; no return value.
@ Returns when the byte at 0x200004b0 is 0.
@ Iterates the nodes returned by fn_0801dd48 (start 0, until 0) and for each
@ element of the array at node+0xc (count at node+0x24) calls fn_08029236 with
@ r0 and the element.
@ ----------------------------------------------------------------------------
	.section .text.fn_08025fdc,"ax",%progbits
	.p2align 2
	.global fn_08025fdc
	.thumb_func
	.type fn_08025fdc, %function
fn_08025fdc:
	push	{r4, r5, r6, lr}
	mov	r6, r0
	ldr	r0, .L08026010
	ldrb	r0, [r0]
	cmp	r0, #0
	beq.n	.L0802600e
	movs	r0, #0
	b.n	.L08026006
.L08025fec:
	movs	r5, #0
	b.n	.L08025ffe
.L08025ff0:
	ldr	r0, [r4, #0xc]
	ldr.w	r1, [r0, r5, lsl #2]
	mov	r0, r6
	bl	fn_08029236
	.inst.n 0x1c6d	@ adds r5, r5, #1
.L08025ffe:
	ldr	r0, [r4, #0x24]
	cmp	r0, r5
	bhi.n	.L08025ff0
	mov	r0, r4
.L08026006:
	bl	fn_0801dd48
	movs	r4, r0
	bne.n	.L08025fec
.L0802600e:
	pop	{r4, r5, r6, pc}
.L08026010:
	.word	0x200004b0

@ ----------------------------------------------------------------------------
@ fn_08026014 - moves an object's content by (dx, dy), animated in mode 1.
@ r0 = object, r1 = dx, r2 = dy, r3 = mode; no return value.
@ Does nothing when dx and dy are both 0.
@ Mode 1: gets fn_08023ebc, builds a record on the stack with fn_0801c718 with
@ callbacks fn_080293ea, fn_0802967c, fn_08029694 and fn_0801c74c; derives the
@ duration from fn_0801dcfc / fn_0801dd88 (halved) with fn_0801c7a4, limited to
@ 200..400 (0xc8..0x190); sends message 9 (fn_080207f4) and starts the record
@ with fn_0801c7c0; done for x and then for y (start offset from fn_08024216 /
@ fn_08024224).
@ Other modes: fn_0801c688 for fn_08029694 and fn_0802967c, message 9, then
@ fn_0801273e, then message 10 as a tail call.
@ Ends with 2 bytes of padding and four function-pointer words.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026014,"ax",%progbits
	.p2align 2
	.global fn_08026014
	.thumb_func
	.type fn_08026014, %function
fn_08026014:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	mov	r7, r0
	sub	sp, #0x48
	mov	r5, r1
	orrs.w	r0, r1, r6
	beq.n	.L0802611c
	cmp	r3, #1
	beq.n	.L08026066
	ldr	r1, .L08026124
	mov	r0, r7
	bl	fn_0801c688
	ldr	r1, .L08026128
	mov	r0, r7
	bl	fn_0801c688
	movs	r2, #0
	movs	r1, #9
	mov	r0, r7
	bl	fn_080207f4
	cmp	r0, #1
	bne.n	.L0802611c
	mov	r2, r6
	mov	r1, r5
	mov	r0, r7
	bl	fn_0801273e
	cmp	r0, #1
	bne.n	.L0802611c
	add	sp, #0x48
	mov	r0, r7
	pop.w	{r4, r5, r6, r7, r8, lr}
	movs	r2, #0
	movs	r1, #0xa
	b.w	fn_080207f4
.L08026066:
	mov	r0, r7
	bl	fn_08023ebc
	mov	r8, r0
	mov	r0, sp
	bl	fn_0801c718
	ldr	r0, .L0802612c
	mov.w	r4, #0x190
	str	r7, [sp]
	str	r0, [sp, #0xc]
	cbz	r5, .L080260cc
	mov	r0, r8
	bl	fn_0801dcfc
	asrs	r0, r0, #1
	mov	r2, r5
	movs	r1, #0
	bl	fn_0801c7a4
	cmp	r0, #0xc8
	bhs.n	.L08026098
	movs	r0, #0xc8
	b.n	.L0802609e
.L08026098:
	cmp	r0, r4
	bls.n	.L0802609e
	mov	r0, r4
.L0802609e:
	str	r0, [sp, #0x2c]
	mov	r0, r7
	bl	fn_08024216
	rsbs	r1, r0, #0
	subs	r0, r5, r0
	str	r1, [sp, #0x20]
	strd	r1, r0, [sp, #0x24]
	ldr	r0, .L08026128
	str	r0, [sp, #4]
	ldr	r0, .L08026130
	str	r0, [sp, #0x1c]
	mov	r2, sp
	movs	r1, #9
	mov	r0, r7
	bl	fn_080207f4
	cmp	r0, #1
	bne.n	.L0802611c
	mov	r0, sp
	bl	fn_0801c7c0
.L080260cc:
	cmp	r6, #0
	beq.n	.L0802611c
	mov	r0, r8
	bl	fn_0801dd88
	asrs	r0, r0, #1
	mov	r2, r6
	movs	r1, #0
	bl	fn_0801c7a4
	cmp	r0, #0xc8
	bhs.n	.L080260e8
	movs	r0, #0xc8
	b.n	.L080260ee
.L080260e8:
	cmp	r0, r4
	bls.n	.L080260ee
	mov	r0, r4
.L080260ee:
	str	r0, [sp, #0x2c]
	mov	r0, r7
	bl	fn_08024224
	rsbs	r1, r0, #0
	subs	r0, r6, r0
	str	r1, [sp, #0x20]
	strd	r1, r0, [sp, #0x24]
	ldr	r0, .L08026124
	str	r0, [sp, #4]
	ldr	r0, .L08026130
	str	r0, [sp, #0x1c]
	mov	r2, sp
	movs	r1, #9
	mov	r0, r7
	bl	fn_080207f4
	cmp	r0, #1
	bne.n	.L0802611c
	mov	r0, sp
	bl	fn_0801c7c0
.L0802611c:
	add	sp, #0x48
	pop.w	{r4, r5, r6, r7, r8, pc}
	.short	0x0000	@ padding
.L08026124:
	.word	fn_08029694
.L08026128:
	.word	fn_0802967c
.L0802612c:
	.word	fn_080293ea
.L08026130:
	.word	fn_0801c74c

@ ----------------------------------------------------------------------------
@ fn_08026134 - limits a requested offset change and calls fn_08026014.
@ r0 = object, r1 = target x offset, r2 = target y offset, r3 = mode passed on;
@ no return value.
@ Does nothing when r1 and r2 are 0.
@ fn_080267c0; limits the x change by fn_08024070 + fn_08024130 (direction by
@ fn_08024912) and the y change by fn_08024208 + fn_08023fbc, using
@ fn_08024216 and fn_08024224 as current offsets (negated).
@ Tail-calls fn_08026014 with the limited values unless both are 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026134,"ax",%progbits
	.global fn_08026134
	.thumb_func
	.type fn_08026134, %function
fn_08026134:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r5, r2
	mov	r10, r0
	mov	r9, r3
	mov	r4, r1
	orrs.w	r0, r1, r5
	beq.n	.L08026212
	mov	r0, r10
	bl	fn_080267c0
	mov	r0, r10
	bl	fn_08024216
	rsbs	r0, r0, #0
	sxth.w	r8, r0
	add.w	r0, r8, r4
	sxth	r4, r0
	movs	r1, #0
	mov	r0, r10
	bl	fn_08024912
	cmp	r0, #1
	beq.n	.L08026192
	cmp	r4, #0
	bgt.n	.L08026196
	bge.n	.L080261bc
	mov	r0, r10
	bl	fn_08024070
	mov	r6, r0
	mov	r0, r10
	bl	fn_08024130
	add	r0, r6
	sxth	r0, r0
	cmp	r0, #0
	bge.n	.L08026188
	movs	r0, #0
.L08026188:
	rsbs	r0, r0, #0
	cmp	r4, r0
	bge.n	.L080261bc
	sxth	r4, r0
	b.n	.L080261bc
.L08026192:
	cmp	r4, #0
	bge.n	.L0802619c
.L08026196:
	mov.w	r4, #0
	b.n	.L080261bc
.L0802619c:
	ble.n	.L080261bc
	mov	r0, r10
	bl	fn_08024070
	mov	r6, r0
	mov	r0, r10
	bl	fn_08024130
	add	r0, r6
	sxth	r0, r0
	cmp	r0, #0
	bge.n	.L080261b6
	movs	r0, #0
.L080261b6:
	cmp	r4, r0
	ble.n	.L080261bc
	mov	r4, r0
.L080261bc:
	mov	r0, r10
	bl	fn_08024224
	rsbs	r0, r0, #0
	sxth	r6, r0
	adds	r0, r6, r5
	sxth	r5, r0
	cmp	r5, #0
	ble.n	.L080261d4
	mov.w	r5, #0
	b.n	.L080261f6
.L080261d4:
	bge.n	.L080261f6
	mov	r0, r10
	bl	fn_08024208
	mov	r7, r0
	mov	r0, r10
	bl	fn_08023fbc
	add	r0, r7
	sxth	r0, r0
	cmp	r0, #0
	bge.n	.L080261ee
	movs	r0, #0
.L080261ee:
	rsbs	r0, r0, #0
	cmp	r5, r0
	bge.n	.L080261f6
	sxth	r5, r0
.L080261f6:
	sub.w	r0, r4, r8
	sxth	r1, r0
	subs	r0, r5, r6
	sxth	r2, r0
	orrs.w	r0, r1, r2
	beq.n	.L08026212
	mov	r3, r9
	mov	r0, r10
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	b.w	fn_08026014
.L08026212:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ fn_08026216 - applies an x and a y offset to an object.
@ r0 = object, r1 = x, r2 = y, r3 = mode; no return value.
@ Calls fn_0802626c with (object, r1, r3), then tail-calls fn_08026298 with
@ (object, r2, r3).
@ ----------------------------------------------------------------------------
	.section .text.fn_08026216,"ax",%progbits
	.global fn_08026216
	.thumb_func
	.type fn_08026216, %function
fn_08026216:
	push	{r4, r5, r6, lr}
	mov	r6, r2
	mov	r5, r3
	mov	r4, r0
	mov	r2, r3
	bl	fn_0802626c
	mov	r2, r5
	mov	r1, r6
	mov	r0, r4
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08026298

@ ----------------------------------------------------------------------------
@ fn_08026232 - notifies each ancestor of an object.
@ r0 = object, r1 = argument passed on; no return value.
@ Calls fn_080267c0, then for the object and each ancestor that itself has a
@ parent (fn_08023fa4; the top object, whose parent link is 0, is not visited;
@ nothing is called when the object has no parent) calls fn_080293f4 with
@ (object+0x14, current node, pointer to a zero word on the stack, r1).
@ Ends with 2 bytes of padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026232,"ax",%progbits
	.global fn_08026232
	.thumb_func
	.type fn_08026232, %function
fn_08026232:
	push	{r3, r4, r5, r6, r7, lr}
	mov	r6, r1
	mov	r4, r0
	bl	fn_080267c0
	movs	r0, #0
	str	r0, [sp]
	mov	r0, r4
	bl	fn_08023fa4
	mov	r5, r0
	add.w	r7, r4, #0x14
	b.n	.L08026264
.L0802624e:
	mov	r3, r6
	mov	r2, sp
	mov	r1, r4
	mov	r0, r7
	bl	fn_080293f4
	mov	r4, r5
	mov	r0, r4
	bl	fn_08023fa4
	mov	r5, r0
.L08026264:
	cmp	r5, #0
	bne.n	.L0802624e
	pop	{r3, r4, r5, r6, r7, pc}
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_0802626c - moves an object horizontally to a position.
@ r0 = object, r1 = value (16-bit), r2 = mode; no return value.
@ fn_0801c688 with fn_0802967c, then tail-calls fn_08026134 with (object,
@ halfword(fn_08024216 - r1), 0, r2). Ends with 2 bytes of padding and one
@ function-pointer word.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802626c,"ax",%progbits
	.p2align 2
	.global fn_0802626c
	.thumb_func
	.type fn_0802626c, %function
fn_0802626c:
	push	{r4, r5, r6, lr}
	mov	r5, r1
	mov	r4, r2
	mov	r6, r0
	ldr	r1, .L08026294
	bl	fn_0801c688
	mov	r0, r6
	bl	fn_08024216
	subs	r0, r0, r5
	sxth	r1, r0
	mov	r3, r4
	mov	r0, r6
	pop.w	{r4, r5, r6, lr}
	movs	r2, #0
	b.w	fn_08026134
	.short	0x0000	@ padding
.L08026294:
	.word	fn_0802967c

@ ----------------------------------------------------------------------------
@ fn_08026298 - moves an object vertically to a position.
@ r0 = object, r1 = value (16-bit), r2 = mode; no return value.
@ fn_0801c688 with fn_08029694, then tail-calls fn_08026134 with (object, 0,
@ halfword(fn_08024224 - r1), r2). Ends with 2 bytes of padding and one
@ function-pointer word.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026298,"ax",%progbits
	.p2align 2
	.global fn_08026298
	.thumb_func
	.type fn_08026298, %function
fn_08026298:
	push	{r4, r5, r6, lr}
	mov	r5, r1
	mov	r4, r2
	mov	r6, r0
	ldr	r1, .L080262c0
	bl	fn_0801c688
	mov	r0, r6
	bl	fn_08024224
	subs	r0, r0, r5
	sxth	r2, r0
	mov	r3, r4
	mov	r0, r6
	pop.w	{r4, r5, r6, lr}
	movs	r1, #0
	b.w	fn_08026134
	.short	0x0000	@ padding
.L080262c0:
	.word	fn_08029694

@ ----------------------------------------------------------------------------
@ fn_080262c4 - redraws the two rectangles computed for an object.
@ r0 = object; returns 8 bytes (the first rectangle) as the decompiler shows.
@ Computes two 8-byte rectangles on the stack with fn_08024232; for each
@ rectangle for which rect_area (0x0801d036) reports nonzero calls fn_08025446
@ with (object, rectangle).
@ ----------------------------------------------------------------------------
	.section .text.fn_080262c4,"ax",%progbits
	.global fn_080262c4
	.thumb_func
	.type fn_080262c4, %function
fn_080262c4:
	push	{r0, r1, r2, r3, r4, lr}
	mov	r4, r0
	add	r2, sp, #8
	mov	r1, sp
	bl	fn_08024232
	mov	r0, sp
	bl	rect_area
	cbnz	r0, .L080262e2
	add	r0, sp, #8
	bl	rect_area
	cmp	r0, #0
	beq.n	.L08026304
.L080262e2:
	mov	r0, sp
	bl	rect_area
	cbz	r0, .L080262f2
	mov	r1, sp
	mov	r0, r4
	bl	fn_08025446
.L080262f2:
	add	r0, sp, #8
	bl	rect_area
	cmp	r0, #0
	beq.n	.L08026304
	add	r1, sp, #8
	mov	r0, r4
	bl	fn_08025446
.L08026304:
	pop	{r0, r1, r2, r3, r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08026306 - stores a value into an object's attribute block.
@ r0 = object (r4), r1 = value (r5); no return value.
@ Body = push {r4,r5,r6,lr} ... pop. Reached only by the b.w at 0x0801c89c in
@ 0x0801c83c.
@ Calls fn_0802318c (r0 = object); then halfword [word [r4+8] + 0x14] = low 16
@ bits of r1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026306,"ax",%progbits
	.global fn_08026306
	.thumb_func
	.type fn_08026306, %function
fn_08026306:
	push	{r4, r5, r6, lr}
	mov	r5, r1
	mov	r4, r0
	bl	fn_0802318c
	ldr	r0, [r4, #8]
	strh	r5, [r0, #0x14]
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08026316 - sets the value of attribute 4 when it differs.
@ r0 = object (r5), r1 = value (r4); no return value. Entered only by the
@ tail jump b.w at 0x080263ba (from fn_080263a8).
@ push {r3,r4,r5,lr}; fn_08023f64(r0 = object, r1 = 4, r2 = sp, r3 = 0).
@ Result 1: the word at [sp] equal to the value returns; different goes on to
@ the call below. Result 0: fn_080265d2(object, value, 0). Any other result
@ returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026316,"ax",%progbits
	.global fn_08026316
	.thumb_func
	.type fn_08026316, %function
fn_08026316:
	push	{r3, r4, r5, lr}
	mov	r4, r1
	mov	r5, r0
	movs	r3, #0
	mov	r2, sp
	movs	r1, #4
	bl	fn_08023f64
	cmp	r0, #1
	beq.n	.L0802633a
	cmp	r0, #0
	bne.n	.L08026338
.L0802632e:
	movs	r2, #0
	mov	r1, r4
	mov	r0, r5
	bl	fn_080265d2
.L08026338:
	pop	{r3, r4, r5, pc}
.L0802633a:
	ldr	r0, [sp]
	cmp	r0, r4
	bne.n	.L0802632e
	pop	{r3, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_08026342 - stores a value into an entry and notifies the object.
@ r0 = object, r1 = key, r2 = value, r3 = entry id; no return value.
@ Gets the entry with fn_0801b418 (object, r3), stores the value with
@ fn_08027280 (entry, key, value) and tail-calls fn_08025d34 (object, r3, key).
@ ----------------------------------------------------------------------------
	.section .text.fn_08026342,"ax",%progbits
	.global fn_08026342
	.thumb_func
	.type fn_08026342, %function
fn_08026342:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r4, r1
	mov	r5, r2
	mov	r7, r3
	mov	r6, r0
	mov	r1, r3
	bl	fn_0801b418
	mov	r2, r5
	mov	r1, r4
	bl	fn_08027280
	mov	r2, r4
	mov	r1, r7
	mov	r0, r6
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08025d34

@ ----------------------------------------------------------------------------
@ fn_0802636a - calls fn_08026700, then fn_0802672c.
@ r0 = object, r1 passed on, r2 = value; no return value.
@ Calls fn_08026700 with the incoming arguments, then tail-calls fn_0802672c
@ with (object, r2).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802636a,"ax",%progbits
	.global fn_0802636a
	.thumb_func
	.type fn_0802636a, %function
fn_0802636a:
.ifdef OWN
	b.w	own_event_obj		@ own build: no event for object 0 (own/fix.s); the two
	.global	own_event_obj_back	@ instructions below are done there
	.thumb_func
	.type	own_event_obj_back, %function
own_event_obj_back:
.else
	push	{r4, r5, r6, lr}
	mov	r5, r2
.endif
	mov	r4, r0
	bl	fn_08026700
	mov	r1, r5
	mov	r0, r4
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0802672c

@ ----------------------------------------------------------------------------
@ fn_08026380 - sets bits 0-1 of the attribute byte at [object+8]+0x18.
@ r0 = object, r1 = value (bits 0-1 used); no return value.
@ fn_0802318c; when bits 0-1 of the byte [object+8]+0x18 differ from r1 stores
@ them and tail-calls fn_08025400.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026380,"ax",%progbits
	.p2align 2
	.global fn_08026380
	.thumb_func
	.type fn_08026380, %function
fn_08026380:
	push	{r4, r5, r6, lr}
	mov	r4, r1
	mov	r5, r0
	bl	fn_0802318c
	ldr	r0, [r5, #8]
	ldrb	r1, [r0, #0x18]
	and	r2, r1, #3
	cmp	r2, r4
	beq.n	.L080263a6
	bfi	r1, r4, #0, #2
	strb	r1, [r0, #0x18]
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08025400
.L080263a6:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_080263a8 - calls fn_080266d4, then fn_08026316.
@ r0 = object (r4), r1 = first argument, r2 = value (r5), r3 = fourth argument;
@ no return value.
@ push {r4,r5,r6,lr}; bl fn_080266d4 with r0..r3 as received; r1 = r5, r0 = r4;
@ pop.w {r4,r5,r6,lr}; tail-calls fn_08026316(object, value). Ends with 2 bytes
@ of padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_080263a8,"ax",%progbits
	.p2align 2
	.global fn_080263a8
	.thumb_func
	.type fn_080263a8, %function
fn_080263a8:
	push	{r4, r5, r6, lr}
	mov	r5, r2
	mov	r4, r0
	bl	fn_080266d4
	mov	r1, r5
	mov	r0, r4
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08026316
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_080263c0 - sets the halfword at object+0x20 and refreshes dependants.
@ r0 = object, r1 = new halfword value for object+0x20; no return value.
@ Returns when the value equals the halfword at object+0x20; stores it, calls
@ fn_08012904 (object, old, new) and returns when that is 0.
@ Allocates 0x280 bytes (fn_08022bac, clear_bytes 0x08022e6c) and collects up
@ to 0x20 distinct 0x14-byte records from the entries at [object+0xc] (using
@ low_16_bits 0x0802675e, mask_bits_16_to_23 0x08026758, fn_08026dc8 with key
@ 0x66).
@ Calls fn_080127c8 for each record, frees with fn_08022c44.
@ Result of fn_08012904: 1: fn_08025400; 3: fn_08025d34 (object, 0xf0000,
@ 0xffff); 2: fn_08025400 and fn_08025cac.
@ ----------------------------------------------------------------------------
	.section .text.fn_080263c0,"ax",%progbits
	.p2align 2
	.global fn_080263c0
	.thumb_func
	.type fn_080263c0, %function
fn_080263c0:
	push.w	{r0, r1, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x3c
	mov	r9, r0
	ldrh	r0, [r0, #0x20]
	ldr	r1, [sp, #0x40]
	cmp	r0, r1
	beq.n	.L080264cc
	str	r0, [sp, #0x10]
	strh.w	r1, [r9, #0x20]
	mov	r0, r9
	ldr	r2, [sp, #0x40]
	ldr	r1, [sp, #0x10]
	bl	fn_08012904
	movs.w	r8, r0
	beq.n	.L080264cc
	mov.w	r4, #0x280
	mov	r0, r4
	bl	fn_08022bac
	mov	r1, r4
	str	r0, [sp, #0xc]
	bl	clear_bytes
	movs	r4, #0
	mov	r0, r4
	b.n	.L080264e4
	nop			@ padding
.L08026400:
	ldr.w	r0, [r9, #0xc]
	movs	r2, #4
	add.w	r1, r0, r10, lsl #3
	add.w	r5, r2, r10, lsl #3
	str	r1, [sp, #0x28]
	ldr	r0, [r0, r5]
	bic.w	r0, r0, #0xff000000
	bl	low_16_bits
	str	r0, [sp, #0x14]
	ldr.w	r0, [r9, #0xc]
	ldr	r0, [r0, r5]
	bic.w	r0, r0, #0xff000000
	bl	mask_bits_16_to_23
	str	r0, [sp, #0x18]
	ldr	r1, [sp, #0x40]
	ldr	r0, [sp, #0x14]
	bics	r0, r1
	bne.n	.L080264e0
	ldr	r0, [sp, #0x28]
	ldr	r0, [r0, #4]
	lsls	r0, r0, #6
	bmi.n	.L080264e0
	ldr	r0, [sp, #0x28]
	add	r2, sp, #0x2c
	movs	r1, #0x66
	ldr	r0, [r0]
	bl	fn_08026dc8
	cmp	r0, #1
	bne.n	.L080264e0
	movs	r7, #0
	ldr	r5, [sp, #0x2c]
	b.n	.L080264d4
.L08026452:
	movs	r6, #0
	b.n	.L08026494
	nop			@ padding
.L08026458:
	ldr	r0, [sp, #0xc]
	add.w	r1, r6, r6, lsl #2
	add.w	r1, r0, r1, lsl #2
	str	r1, [sp, #0x38]
	ldr.w	r11, [r1, #4]
	mov	r0, r11
	bl	low_16_bits
	str	r0, [sp, #0x20]
	mov	r0, r11
	bl	mask_bits_16_to_23
	ldr	r1, [r5]
	ldrh.w	r2, [r1, r7, lsl #1]
	ldr	r1, [sp, #0x38]
	ldrh	r1, [r1, #8]
	cmp	r2, r1
	bne.n	.L08026492
	ldr	r1, [sp, #0x18]
	cmp	r0, r1
	bne.n	.L08026492
	ldr	r1, [sp, #0x14]
	ldr	r0, [sp, #0x20]
	cmp	r0, r1
	bhs.n	.L08026498
.L08026492:
	.inst.n 0x1c76	@ adds r6, r6, #1
.L08026494:
	cmp	r6, r4
	blo.n	.L08026458
.L08026498:
	cmp	r6, r4
	bne.n	.L080264d2
	ldr	r2, [sp, #0xc]
	add.w	r0, r4, r4, lsl #2
	ldrh	r1, [r5, #0xc]
	strh.w	r1, [r2, r0, lsl #2]
	ldr	r2, [sp, #0xc]
	ldrh	r1, [r5, #0x10]
	add.w	r0, r2, r0, lsl #2
	strh	r1, [r0, #2]
	ldr	r1, [r5, #8]
	str	r1, [r0, #0xc]
	ldr	r1, [r5]
	ldrh.w	r1, [r1, r7, lsl #1]
	strh	r1, [r0, #8]
	ldr	r1, [r5, #4]
	str	r1, [r0, #0x10]
	ldr	r1, [sp, #0x28]
	ldr	r1, [r1, #4]
	bic.w	r1, r1, #0xff000000
	b.n	.L080264ce
.L080264cc:
	b.n	.L0802656a
.L080264ce:
	.inst.n 0x1c64	@ adds r4, r4, #1
	str	r1, [r0, #4]
.L080264d2:
	.inst.n 0x1c7f	@ adds r7, r7, #1
.L080264d4:
	ldr	r0, [r5]
	ldrh.w	r0, [r0, r7, lsl #1]
	cbz	r0, .L080264e0
	cmp	r4, #0x20
	blo.n	.L08026452
.L080264e0:
	add.w	r0, r10, #1
.L080264e4:
	mov	r10, r0
	ldrh.w	r0, [r9, #0x22]
	ubfx	r1, r0, #3, #6
	cmp	r1, r10
	bls.n	.L080264f6
	cmp	r4, #0x20
	blo.n	.L08026400
.L080264f6:
	movs	r5, #0
	b.n	.L0802651c
	nop			@ padding
.L080264fc:
	ldr	r0, [sp, #0xc]
	add.w	r1, r5, r5, lsl #2
	add.w	r6, r0, r1, lsl #2
	ldr	r0, [r6, #4]
	bl	mask_bits_16_to_23
	mov	r1, r0
	str	r6, [sp]
	mov	r0, r9
	ldr	r3, [sp, #0x40]
	ldr	r2, [sp, #0x10]
	bl	fn_080127c8
	.inst.n 0x1c6d	@ adds r5, r5, #1
.L0802651c:
	cmp	r5, r4
	blo.n	.L080264fc
	ldr	r0, [sp, #0xc]
	bl	fn_08022c44
	cmp.w	r8, #1
	beq.n	.L0802654a
	cmp.w	r8, #3
	beq.n	.L08026556
	cmp.w	r8, #2
	bne.n	.L0802656a
	mov	r0, r9
	bl	fn_08025400
	add	sp, #0x44
	mov	r0, r9
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w	fn_08025cac
.L0802654a:
	add	sp, #0x44
	mov	r0, r9
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w	fn_08025400
.L08026556:
	add	sp, #0x44
	mov	r0, r9
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	movw	r2, #0xffff
	mov.w	r1, #0xf0000
	b.w	fn_08025d34
.L0802656a:
	add	sp, #0x44
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}

@ ----------------------------------------------------------------------------
@ fn_08026570 - stores r1 under key 0x9 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x9 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026570,"ax",%progbits
	.global fn_08026570
	.thumb_func
	.type fn_08026570, %function
fn_08026570:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #9
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_0802657a - stores a 16-bit value under key 0x20 (tail call of
@ fn_08026342).
@ r0 = object, r1 = value (16-bit), r2 = third argument; no return value.
@ Pushes r0-r2, reserves 4 bytes, copies the low halfword of the pushed r1 to
@ [sp] (so the upper 16 bits of the loaded r2 are the unwritten stack word),
@ sets r1 = 0x20, releases 16 bytes and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802657a,"ax",%progbits
	.global fn_0802657a
	.thumb_func
	.type fn_0802657a, %function
fn_0802657a:
	push	{r0, r1, r2}
	sub	sp, #4
	mov	r3, r2
	ldrh.w	r1, [sp, #8]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x20
	add	sp, #0x10
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_08026592 - stores r1 under key 0x21 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x21 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026592,"ax",%progbits
	.global fn_08026592
	.thumb_func
	.type fn_08026592, %function
fn_08026592:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x21
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_0802659c - stores a 16-bit value under key 0x30 (tail call of
@ fn_08026342).
@ r0 = object, r1 = value (16-bit), r2 = third argument; no return value.
@ Pushes r0-r2, reserves 4 bytes, copies the low halfword of the pushed r1 to
@ [sp], sets r1 = 0x30, releases 16 bytes and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802659c,"ax",%progbits
	.p2align 2
	.global fn_0802659c
	.thumb_func
	.type fn_0802659c, %function
fn_0802659c:
	push	{r0, r1, r2}
	sub	sp, #4
	mov	r3, r2
	ldrh.w	r1, [sp, #8]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x30
	add	sp, #0x10
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080265b4 - stores r1 under key 0x33 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x33 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_080265b4,"ax",%progbits
	.global fn_080265b4
	.thumb_func
	.type fn_080265b4, %function
fn_080265b4:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x33
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080265be - stores r1 under key 0x32 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x32 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_080265be,"ax",%progbits
	.global fn_080265be
	.thumb_func
	.type fn_080265be, %function
fn_080265be:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x32
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080265c8 - stores r1 under key 0x17 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x17 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_080265c8,"ax",%progbits
	.global fn_080265c8
	.thumb_func
	.type fn_080265c8, %function
fn_080265c8:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x17
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080265d2 - stores r1 under key 0x4 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 4 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_080265d2,"ax",%progbits
	.global fn_080265d2
	.thumb_func
	.type fn_080265d2, %function
fn_080265d2:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #4
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080265dc - stores a 16-bit value under key 0x47 (tail call of
@ fn_08026342).
@ r0 = object, r1 = value (16-bit), r2 = third argument; no return value.
@ Pushes r0-r2, reserves 4 bytes, copies the low halfword of the pushed r1 to
@ [sp], sets r1 = 0x47, releases 16 bytes and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_080265dc,"ax",%progbits
	.p2align 2
	.global fn_080265dc
	.thumb_func
	.type fn_080265dc, %function
fn_080265dc:
	push	{r0, r1, r2}
	sub	sp, #4
	mov	r3, r2
	ldrh.w	r1, [sp, #8]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x47
	add	sp, #0x10
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080265f4 - stores r1 under key 0x48 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x48 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_080265f4,"ax",%progbits
	.global fn_080265f4
	.thumb_func
	.type fn_080265f4, %function
fn_080265f4:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x48
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080265fe - stores a 16-bit value under key 0x4d (tail call of
@ fn_08026342).
@ r0 = first argument, r1 = second argument (only its low halfword is used),
@ r2 = third argument; ends in a tail branch.
@ Pushes r0, r1, r2, reserves 4 bytes, sets r3 = r2, copies the low halfword of
@ the pushed r1 to [sp] (ldrh [sp+8], strh [sp]) and loads r2 = word [sp], so
@ the low 16 bits of r2 are the low halfword of r1 and the upper 16 bits are
@ the unwritten stack word. Sets r1 = 0x4d, releases the 16 bytes and
@ tail-calls fn_08026342(r0, 0x4d, r2, r3).
@ ----------------------------------------------------------------------------
	.section .text.fn_080265fe,"ax",%progbits
	.global fn_080265fe
	.thumb_func
	.type fn_080265fe, %function
fn_080265fe:
	push	{r0, r1, r2}
	sub	sp, #4
	mov	r3, r2
	ldrh.w	r1, [sp, #8]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x4d
	add	sp, #0x10
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_08026616 - stores r1 under key 0x49 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x49 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026616,"ax",%progbits
	.global fn_08026616
	.thumb_func
	.type fn_08026616, %function
fn_08026616:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x49
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_08026620 - stores r1 under key 0x60 (tail call of fn_08026342).
@ Parameters: r0, r1, r2 as received; returns what fn_08026342 returns.
@ r3 = r2, r2 = r1, r1 = 0x60, then b.w fn_08026342: the two incoming
@ arguments shift to r2 and r3 and 0x60 is inserted as the second argument.
@ Reached only by the b.w at 0x08028acc.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026620,"ax",%progbits
	.global fn_08026620
	.thumb_func
	.type fn_08026620, %function
fn_08026620:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x60
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_0802662a - stores r1 under keys 0x12, 0x13, 0x10 and 0x11.
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Calls fn_08026662 (key 0x12), fn_0802666c (key 0x13) and fn_08026676 (key
@ 0x10) with r0, r1, r2, then runs on through the nop.w at 0x08026654 into
@ fn_08026658 (same section), which tail-calls fn_08026342 with key 0x11 and
@ the same arguments.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802662a,"ax",%progbits
	.global fn_0802662a
	.thumb_func
	.type fn_0802662a, %function
fn_0802662a:
	push	{r4, r5, r6, lr}
	mov	r4, r2
	mov	r5, r1
	mov	r6, r0
	bl	fn_08026662
	mov	r2, r4
	mov	r1, r5
	mov	r0, r6
	bl	fn_0802666c
	mov	r2, r4
	mov	r1, r5
	mov	r0, r6
	bl	fn_08026676
	mov	r2, r4
	mov	r1, r5
	mov	r0, r6
	pop.w	{r4, r5, r6, lr}
	nop.w

@ ----------------------------------------------------------------------------
@ fn_08026658 - stores r1 under key 0x11 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x11 and tail-calls fn_08026342. Reached
@ by fall-through from fn_0802662a.
@ ----------------------------------------------------------------------------
	.global fn_08026658
	.thumb_func
	.type fn_08026658, %function
fn_08026658:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x11
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_08026662 - stores r1 under key 0x12 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x12 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026662,"ax",%progbits
	.global fn_08026662
	.thumb_func
	.type fn_08026662, %function
fn_08026662:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x12
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_0802666c - stores r1 under key 0x13 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x13 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802666c,"ax",%progbits
	.global fn_0802666c
	.thumb_func
	.type fn_0802666c, %function
fn_0802666c:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x13
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_08026676 - stores r1 under key 0x10 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x10 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026676,"ax",%progbits
	.global fn_08026676
	.thumb_func
	.type fn_08026676, %function
fn_08026676:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x10
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_08026680 - stores r1 under key 0xb (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0xb and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026680,"ax",%progbits
	.global fn_08026680
	.thumb_func
	.type fn_08026680, %function
fn_08026680:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0xb
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_0802668a - stores r1 under key 0x5b (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x5b and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802668a,"ax",%progbits
	.global fn_0802668a
	.thumb_func
	.type fn_0802668a, %function
fn_0802668a:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x5b
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_08026694 - stores a 16-bit value under key 0x55 (tail call of
@ fn_08026342).
@ r0 = object, r1 = value (16-bit), r2 = third argument; no return value.
@ Pushes r0-r2, reserves 4 bytes, copies the low halfword of the pushed r1 to
@ [sp], sets r1 = 0x55, releases 16 bytes and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026694,"ax",%progbits
	.p2align 2
	.global fn_08026694
	.thumb_func
	.type fn_08026694, %function
fn_08026694:
	push	{r0, r1, r2}
	sub	sp, #4
	mov	r3, r2
	ldrh.w	r1, [sp, #8]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x55
	add	sp, #0x10
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080266ac - stores r1 under key 0x57 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 0x57 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_080266ac,"ax",%progbits
	.global fn_080266ac
	.thumb_func
	.type fn_080266ac, %function
fn_080266ac:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #0x57
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080266b6 - stores r1 under key 0x1 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 1 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_080266b6,"ax",%progbits
	.global fn_080266b6
	.thumb_func
	.type fn_080266b6, %function
fn_080266b6:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #1
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080266c0 - stores r1 under key 0x7 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 7 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_080266c0,"ax",%progbits
	.global fn_080266c0
	.thumb_func
	.type fn_080266c0, %function
fn_080266c0:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #7
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080266ca - stores r1 under key 0x8 (tail call of fn_08026342).
@ r0 = object, r1 = value, r2 = third argument; no return value.
@ Moves r2 to r3, r1 to r2, sets r1 = 8 and tail-calls fn_08026342.
@ ----------------------------------------------------------------------------
	.section .text.fn_080266ca,"ax",%progbits
	.global fn_080266ca
	.thumb_func
	.type fn_080266ca, %function
fn_080266ca:
	mov	r3, r2
	mov	r2, r1
	movs	r1, #8
	b.w	fn_08026342

@ ----------------------------------------------------------------------------
@ fn_080266d4 - sets attribute key 1 through fn_080266b6 when it differs.
@ r0 = object, r1 = value; r3 is not read (it is set to 0 and passed as the
@ entry id); no return value.
@ Calls fn_08023f64 with (object, key 1, pointer to a stack word, 0); returns
@ when it gives 1 and the stored value equals r1, or gives a result other than
@ 0 and 1. Otherwise calls fn_080266b6 with (object, r1, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_080266d4,"ax",%progbits
	.p2align 2
	.global fn_080266d4
	.thumb_func
	.type fn_080266d4, %function
fn_080266d4:
	push	{r3, r4, r5, lr}
	mov	r4, r1
	mov	r5, r0
	movs	r3, #0
	mov	r2, sp
	movs	r1, #1
	bl	fn_08023f64
	cmp	r0, #1
	beq.n	.L080266f8
	cmp	r0, #0
	bne.n	.L080266f6
.L080266ec:
	movs	r2, #0
	mov	r1, r4
	mov	r0, r5
	bl	fn_080266b6
.L080266f6:
	pop	{r3, r4, r5, pc}
.L080266f8:
	ldr	r0, [sp]
	cmp	r0, r4
	bne.n	.L080266ec
	pop	{r3, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_08026700 - sets attribute key 7 through fn_080266c0 when it differs.
@ r0 = object, r1 = value; r3 is not read (it is set to 0 and passed as the
@ entry id); no return value.
@ Calls fn_08023f64 with (object, key 7, pointer to a stack word, 0); returns
@ when it gives 1 and the stored value equals r1, or gives a result other than
@ 0 and 1. Otherwise calls fn_080266c0 with (object, r1, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_08026700,"ax",%progbits
	.p2align 2
	.global fn_08026700
	.thumb_func
	.type fn_08026700, %function
fn_08026700:
	push	{r3, r4, r5, lr}
	mov	r4, r1
	mov	r5, r0
	movs	r3, #0
	mov	r2, sp
	movs	r1, #7
	bl	fn_08023f64
	cmp	r0, #1
	beq.n	.L08026724
	cmp	r0, #0
	bne.n	.L08026722
.L08026718:
	movs	r2, #0
	mov	r1, r4
	mov	r0, r5
	bl	fn_080266c0
.L08026722:
	pop	{r3, r4, r5, pc}
.L08026724:
	ldr	r0, [sp]
	cmp	r0, r4
	bne.n	.L08026718
	pop	{r3, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_0802672c - sets attribute key 8 through fn_080266ca when it differs.
@ r0 = object, r1 = value; r3 is not read (it is set to 0 and passed as the
@ entry id); no return value.
@ Calls fn_08023f64 with (object, key 8, pointer to a stack word, 0); returns
@ when it gives 1 and the stored value equals r1, or gives a result other than
@ 0 and 1. Otherwise calls fn_080266ca with (object, r1, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802672c,"ax",%progbits
	.p2align 2
	.global fn_0802672c
	.thumb_func
	.type fn_0802672c, %function
fn_0802672c:
	push	{r3, r4, r5, lr}
	mov	r4, r1
	mov	r5, r0
	movs	r3, #0
	mov	r2, sp
	movs	r1, #8
	bl	fn_08023f64
	cmp	r0, #1
	beq.n	.L08026750
	cmp	r0, #0
	bne.n	.L0802674e
.L08026744:
	movs	r2, #0
	mov	r1, r4
	mov	r0, r5
	bl	fn_080266ca
.L0802674e:
	pop	{r3, r4, r5, pc}
.L08026750:
	ldr	r0, [sp]
	cmp	r0, r4
	bne.n	.L08026744
	pop	{r3, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ mask_bits_16_to_23 - returns r0 & 0xff0000.
@ r0 = value; returns r0 & 0xff0000 (and.w at 0x08026758).
@ ----------------------------------------------------------------------------
	.section .text.mask_bits_16_to_23,"ax",%progbits
	.global mask_bits_16_to_23
	.thumb_func
	.type mask_bits_16_to_23, %function
mask_bits_16_to_23:
	and	r0, r0, #0xff0000
	bx	lr

@ ----------------------------------------------------------------------------
@ low_16_bits - returns the low 16 bits of r0.
@ r0 = value; returns the low 16 bits of r0 (uxth at 0x0802675e).
@ ----------------------------------------------------------------------------
	.section .text.low_16_bits,"ax",%progbits
	.global low_16_bits
	.thumb_func
	.type low_16_bits, %function
low_16_bits:
	uxth	r0, r0
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08026762 - calls fn_0802accc for an object and optionally its ancestors.
@ r0 = object, r1 = argument, r2 = walk-up flag, r3 = mode; no return value.
@ Loop while the object is nonzero: gets fn_08012732; with r3 = 0 calls
@ fn_0802accc (object, r1, 0) when it is 2, returns when r2 is 0, else moves
@ to the parent (fn_08023fa4).
@ With r3 nonzero first recurses on the parent when r2 is nonzero, then
@ tail-calls fn_0802accc with (object, r1, r3) when the result is 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026762,"ax",%progbits
	.global fn_08026762
	.thumb_func
	.type fn_08026762, %function
fn_08026762:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r6, r3
	mov	r5, r2
	mov	r8, r1
.L0802676c:
	movs	r7, r0
	beq.n	.L080267bc
	bl	fn_08012732
	cmp	r0, #2
	beq.n	.L080267a0
	movs	r4, #0
.L0802677a:
	cbz	r6, .L080267a4
	cbz	r5, .L0802678e
	mov	r0, r7
	bl	fn_08023fa4
	mov	r3, r6
	mov	r2, r5
	mov	r1, r8
	bl	fn_08026762
.L0802678e:
	cmp	r4, #0
	beq.n	.L080267bc
	mov	r2, r6
	mov	r1, r8
	mov	r0, r7
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_0802accc
.L080267a0:
	movs	r4, #1
	b.n	.L0802677a
.L080267a4:
	cbz	r4, .L080267b0
	mov	r2, r6
	mov	r1, r8
	mov	r0, r7
	bl	fn_0802accc
.L080267b0:
	cmp	r5, #0
	beq.n	.L080267bc
	mov	r0, r7
	bl	fn_08023fa4
	b.n	.L0802676c
.L080267bc:
	pop.w	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_080267c0 - clears the pending bit 1 flags on the top object.
@ No parameters (r0 as left by the caller is passed to fn_08023fac); no return
@ value.
@ When the byte at 0x20000464 is 0: sets it to 1, takes the top object from
@ fn_08023fac and, while bit 1 of the halfword at +0x22 is set, clears it and
@ calls fn_0801c2e8 on it; sets the byte back to 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080267c0,"ax",%progbits
	.p2align 2
	.global fn_080267c0
	.thumb_func
	.type fn_080267c0, %function
fn_080267c0:
	push	{r4, r5, r6, lr}
	ldr	r5, .L080267f0
	ldrb	r1, [r5]
	cmp	r1, #0
	bne.n	.L080267ee
	movs	r1, #1
	strb	r1, [r5]
	bl	fn_08023fac
	mov	r4, r0
	b.n	.L080267e4
	nop			@ padding
.L080267d8:
	bic	r0, r0, #2
	strh	r0, [r4, #0x22]
	mov	r0, r4
	bl	fn_0801c2e8
.L080267e4:
	ldrh	r0, [r4, #0x22]
	lsls	r1, r0, #0x1e
	bmi.n	.L080267d8
	movs	r0, #0
	strb	r0, [r5]
.L080267ee:
	pop	{r4, r5, r6, pc}
.L080267f0:
	.word	0x20000464

@ ----------------------------------------------------------------------------
@ fn_080267f4 - reads a halfword from the table at 0x08050bfc.
@ r0 = row (below 0x13), r1 = column 1..4; returns a 16-bit value.
@ When valid returns the halfword at 0x08050bfc + r0*8 + (r1-1)*2, else the
@ result of fn_0801d6cc. Ends with 2 bytes of padding and the table address.
@ ----------------------------------------------------------------------------
	.section .text.fn_080267f4,"ax",%progbits
	.p2align 2
	.global fn_080267f4
	.thumb_func
	.type fn_080267f4, %function
fn_080267f4:
	push	{r3, lr}
	cmp	r0, #0x13
	bhs.n	.L08026800
	cbz	r1, .L08026800
	cmp	r1, #4
	bls.n	.L0802680c
.L08026800:
	bl	fn_0801d6cc
	str	r0, [sp]
	ldrh.w	r0, [sp]
	pop	{r3, pc}
.L0802680c:
	ldr	r2, .L08026820
	.inst.n 0x1e49	@ subs r1, r1, #1
	uxtb	r1, r1
	add.w	r0, r2, r0, lsl #3
	add.w	r0, r0, r1, lsl #1
	ldrh	r0, [r0]
	pop	{r3, pc}
	.short	0x0000	@ padding
.L08026820:
	.word	d_08050bfc

@ ----------------------------------------------------------------------------
@ fn_08026824 - reads a halfword from the table at 0x08050b3e.
@ r0 = row (below 0x13), r1 = column 1..5; returns a 16-bit value.
@ When valid returns the halfword at 0x08050b3e + r0*10 + (r1-1)*2, else the
@ result of fn_0801d6cc. Ends with 2 bytes of padding and the table address.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026824,"ax",%progbits
	.p2align 2
	.global fn_08026824
	.thumb_func
	.type fn_08026824, %function
fn_08026824:
	push	{r3, lr}
	cmp	r0, #0x13
	bhs.n	.L08026830
	cbz	r1, .L08026830
	cmp	r1, #5
	bls.n	.L0802683c
.L08026830:
	bl	fn_0801d6cc
	str	r0, [sp]
	ldrh.w	r0, [sp]
	pop	{r3, pc}
.L0802683c:
	ldr	r2, .L08026854
	.inst.n 0x1e49	@ subs r1, r1, #1
	add.w	r0, r0, r0, lsl #2
	uxtb	r1, r1
	add.w	r0, r2, r0, lsl #1
	add.w	r0, r0, r1, lsl #1
	ldrh	r0, [r0]
	pop	{r3, pc}
	.short	0x0000	@ padding
.L08026854:
	.word	d_08050b3e

@ ----------------------------------------------------------------------------
@ fn_08026858 - reads a halfword from the table at 0x08050b18.
@ r0 = index (below 0x13); returns a 16-bit value.
@ When valid returns the halfword at 0x08050b18 + r0*2 (pool word at
@ 0x08026874), else the result of fn_0801d6cc.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026858,"ax",%progbits
	.p2align 2
	.global fn_08026858
	.thumb_func
	.type fn_08026858, %function
fn_08026858:
	push	{r3, lr}
	cmp	r0, #0x13
	blo.n	.L0802686a
	bl	fn_0801d6cc
	str	r0, [sp]
	ldrh.w	r0, [sp]
	pop	{r3, pc}
.L0802686a:
	ldr	r1, .L08026874
	add.w	r0, r1, r0, lsl #1
	ldrh	r0, [r0]
	pop	{r3, pc}
.L08026874:
	.word	d_08050b18

@ ----------------------------------------------------------------------------
@ fn_08026878 - rotates and scales a point around a centre point.
@ r0 = point (x, y halfwords, updated in place), r1 = angle in tenths of a
@ degree, r2 = scale (0x100 = 1.0), r3 = centre point (x, y halfwords); no
@ return value.
@ Does nothing when the angle is 0 and the scale is 0x100.
@ Subtracts the centre from the point.
@ Angle 0: result = centre + (point * scale) >> 8.
@ Otherwise, when the angle differs from the cached word at 0x200004c8,
@ normalises it into 0..0xe10, interpolates two table values from
@ sine_q15_degrees (0x08027ba8) at index angle/10, +1, +0x5a, +0x5b with weight
@ angle%10 (divide by 10, shift right 5) into the words 0x200004cc and
@ 0x200004d0 and caches the angle.
@ Rotates: x' = centre.x + (c*x - s*y) >> 10 (scale 0x100) or * scale >> 0x12,
@ y' = centre.y + (c*y + s*x) >> 10 or >> 0x12 with c = word 0x200004d0,
@ s = word 0x200004cc.
@ Ends with 2 bytes of padding and the address 0x200004c8.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026878,"ax",%progbits
	.p2align 2
	.global fn_08026878
	.thumb_func
	.type fn_08026878, %function
fn_08026878:
	push.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r7, r2
	movs	r4, r1
	mov	r5, r0
	mov	r6, r3
	bne.n	.L0802688c
	cmp.w	r7, #0x100
	beq.n	.L08026974
.L0802688c:
	ldrh	r0, [r5]
	ldrh	r1, [r6]
	subs	r0, r0, r1
	sxth	r1, r0
	strh	r1, [r5]
	ldrh	r0, [r5, #2]
	ldrh	r2, [r6, #2]
	subs	r0, r0, r2
	sxth	r0, r0
	strh	r0, [r5, #2]
	cmp	r4, #0
	beq.n	.L08026978
	ldr.w	r11, .L080269b4
	ldr.w	r0, [r11]
	cmp	r0, r4
	beq.n	.L0802693a
	mov	r0, r4
	cmp.w	r4, #0xe10
	ble.n	.L080268bc
	sub.w	r0, r4, #0xe10
.L080268bc:
	cmp	r0, #0
	bge.n	.L080268c4
	add.w	r0, r0, #0xe10
.L080268c4:
	movs	r1, #0xa
	sdiv	r8, r0, r1
	rsb.w	r1, r8, #0
	add.w	r1, r1, r1, lsl #2
	add.w	r9, r0, r1, lsl #1
	add.w	r10, r8, #1
	sxth.w	r0, r8
	bl	sine_q15_degrees
	str	r0, [sp, #8]
	sxth.w	r0, r10
	bl	sine_q15_degrees
	add.w	r1, r8, #0x5a
	str	r0, [sp, #4]
	sxth	r0, r1
	bl	sine_q15_degrees
	add.w	r1, r10, #0x5a
	str	r0, [sp]
	sxth	r0, r1
	bl	sine_q15_degrees
	mov	r3, r0
	ldr	r0, [sp, #8]
	rsb.w	r8, r9, #0xa
	mul	r1, r8, r0
	ldr	r0, [sp, #4]
	ldr	r2, [sp]
	mla	r1, r0, r9, r1
	movs	r0, #0xa
	sdiv	r12, r1, r0
	mul	r1, r8, r2
	mla	r2, r3, r9, r1
	movs	r1, #0xa
	sdiv	r1, r2, r1
	asr.w	r2, r12, #5
	asrs	r1, r1, #5
	strd	r2, r1, [r11, #4]
	str.w	r4, [r11]
.L0802693a:
	ldrsh.w	r1, [r5]
	ldrsh.w	r0, [r5, #2]
	cmp.w	r7, #0x100
	beq.n	.L0802698c
	ldr.w	r2, [r11, #8]
	ldr.w	r3, [r11, #4]
	mul	r4, r2, r1
	mls	r4, r3, r0, r4
	ldrh.w	r12, [r6]
	muls	r4, r7, r4
	muls	r3, r1, r3
	add.w	r4, r12, r4, asr #18
	strh	r4, [r5]
	mla	r0, r2, r0, r3
	ldrh	r1, [r6, #2]
	muls	r0, r7, r0
	add.w	r0, r1, r0, asr #18
.L08026972:
	strh	r0, [r5, #2]
.L08026974:
	pop.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08026978:
	ldrh	r2, [r6]
	muls	r1, r7, r1
	add.w	r1, r2, r1, asr #8
	strh	r1, [r5]
	ldrh	r1, [r3, #2]
	muls	r0, r7, r0
	add.w	r0, r1, r0, asr #8
	b.n	.L08026972
.L0802698c:
	ldr.w	r3, [r11, #8]
	ldr.w	r2, [r11, #4]
	mul	r4, r3, r1
	mls	r4, r2, r0, r4
	ldrh	r7, [r6]
	muls	r2, r1, r2
	add.w	r4, r7, r4, asr #10
	strh	r4, [r5]
	mla	r0, r3, r0, r2
	ldrh	r1, [r6, #2]
	add.w	r0, r1, r0, asr #10
	b.n	.L08026972
	.short	0x0000	@ padding
.L080269b4:
	.word	0x200004c8

