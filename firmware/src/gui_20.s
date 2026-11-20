@ gui_20.s - GUI object helpers: text-object geometry, text fitting/ellipsis, text setters and polyline extent (0x08021bd0..0x08022afc)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08021bd0 - returns the packed width/height of an object's rectangle.
@ r0 = object. Reads the signed halfwords at +0x2c, +0x2e, +0x30, the halfword
@ at +0x36 and passes the address object+0x32 to fn_080122e0, which fills an
@ 8-byte output rectangle on the stack (four halfwords x0, y0, x1, y1).
@ Returns ((x1 - x0 + 1) & 0xffff) | ((y1 - y0 + 1) << 16).
@ The incoming r2 and r3 are not read; their stack slots receive the output.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021bd0,"ax",%progbits
	.p2align 2
	.global fn_08021bd0
	.thumb_func
	.type fn_08021bd0, %function
fn_08021bd0:
	push	{r0, r1, r2, r3, r4, lr}
	add.w	r2, r0, #0x32			@ r2 = object + 0x32
	ldrh	r1, [r0, #0x36]
	strd	r1, r2, [sp]			@ stack arguments 5 and 6
	ldrsh.w	r3, [r0, #0x30]
	ldrsh.w	r2, [r0, #0x2e]
	ldrsh.w	r1, [r0, #0x2c]
	add	r0, sp, #8			@ r0 = output rectangle at sp+8
	bl	fn_080122e0
	ldrh.w	r0, [sp, #0xc]			@ x1
	ldrh.w	r1, [sp, #0x8]			@ x0
	ldrh.w	r2, [sp, #0xa]			@ y0
	subs	r1, r0, r1
	mov	r0, r4
	.inst.n	0x1c49				@ adds r1, r1, #1
	bfi	r0, r1, #0, #16			@ low half = x1 - x0 + 1
	ldrh.w	r1, [sp, #0xe]			@ y1
	add	sp, #0x10
	subs	r1, r1, r2
	.inst.n	0x1c49				@ adds r1, r1, #1
	bfi	r0, r1, #16, #16		@ high half = y1 - y0 + 1
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08021c14 - sets the text pointer of an object and derives its packed
@ geometry fields.
@ r0 = object (kept in r4), r1 = source pointer (kept in r8); no return value.
@ Calls fn_08025400(object) first and again at the end. The class
@ c = fn_08021d60(source) selects the path:
@  c == 3 (null source): when byte +0x38 & 3 is 2 or 1, frees the word +0x24
@    with fn_08022c68; stores 0 to word +0x24; sets bits 1..0 of byte +0x38
@    (orr 3) and returns without the final steps.
@  otherwise fn_0802187c(source, sp+12) fills the word at sp+12:
@  c == 0: frees word +0x24 with fn_08022c68 when byte +0x38 & 3 is 1 or 2,
@    stores the source pointer itself at word +0x24.
@  c == 1 or 2: when word +0x24 differs from the source, remembers the old
@    pointer when byte +0x38 & 3 is 1 or 2, allocates string_length(source)+1
@    bytes with fn_08022b50 (returns at once when that gives 0), copies the
@    string with string_copy, stores the new block at word +0x24 and frees the
@    old one with fn_08022c68.
@  c == 2 only: reads fn_08024bac(object, 0, 0x57) (full word, r6),
@    fn_08024bac(object, 0, 0x58) and fn_08024bac(object, 0, 0x59) (signed 16
@    bit) and calls fn_08027d30(sp+16, source, r6, value 0x58, stack: value
@    0x59, 0x1fff, 0); inserts the halfword at sp+16 into bits 10..20 and the
@    halfword at sp+18 into bits 21..31 of the word at sp+12.
@ Common end (.L08021d14): byte +0x38 bits 1..0 = c; halfword +0x2c = bits
@ 10..20 of the word at sp+12; halfword +0x2e = word >> 21; byte +0x38 bits
@ 6..2 = low 5 bits of that word; halfword +0x32 = (bits 10..20) >> 1;
@ halfword +0x34 = word >> 22; calls fn_08025d04(object); calls fn_08025cac
@ (object) when halfword +0x30 != 0 or halfword +0x36 != 0x100; finally calls
@ fn_08025400(object).
@ ----------------------------------------------------------------------------
	.section .text.fn_08021c14,"ax",%progbits
	.p2align 2
	.global fn_08021c14
	.thumb_func
	.type fn_08021c14, %function
fn_08021c14:
	push.w	{r4, r5, r6, r7, r8, r9, lr}
	sub	sp, #0x14
	mov	r8, r1				@ r8 = source
	mov	r4, r0				@ r4 = object
	bl	fn_08025400
	mov	r0, r8
	bl	fn_08021d60			@ class of the source
	mov	r5, r0
	mov.w	r9, #0
	cmp	r0, #3
	beq.n	.L08021c46
	add	r1, sp, #0xc
	mov	r0, r8
	bl	fn_0802187c
	cbz	r5, .L08021c6e
	cmp	r5, #1
	beq.n	.L08021c8a
	cmp	r5, #2
	beq.n	.L08021c8a
	b.n	.L08021d14
.L08021c46:
	ldrb.w	r0, [r4, #0x38]
	and.w	r0, r0, #3
	cmp	r0, #2
	beq.n	.L08021c56
	cmp	r0, #1
	bne.n	.L08021c5c
.L08021c56:
	ldr	r0, [r4, #0x24]
	bl	fn_08022c68			@ free the old text block
.L08021c5c:
	str.w	r9, [r4, #0x24]!		@ word +0x24 = 0; r4 = object + 0x24
	ldrb	r0, [r4, #0x14]			@ byte at object + 0x38
	orr.w	r0, r0, #3
	strb	r0, [r4, #0x14]
.L08021c68:
	add	sp, #0x14
	pop.w	{r4, r5, r6, r7, r8, r9, pc}
.L08021c6e:
	ldrb.w	r0, [r4, #0x38]
	and.w	r0, r0, #3
	cmp	r0, #1
	beq.n	.L08021c7e
	cmp	r0, #2
	bne.n	.L08021c84
.L08021c7e:
	ldr	r0, [r4, #0x24]
	bl	fn_08022c68			@ free the old text block
.L08021c84:
	str.w	r8, [r4, #0x24]			@ store the source pointer itself
	b.n	.L08021d14
.L08021c8a:
	ldr	r0, [r4, #0x24]
	cmp	r0, r8
	beq.n	.L08021cc4
	ldrb.w	r1, [r4, #0x38]
	movs	r6, #0				@ r6 = old block to free (none)
	and.w	r1, r1, #3
	cmp	r1, #1
	beq.n	.L08021ca2
	cmp	r1, #2
	bne.n	.L08021ca4
.L08021ca2:
	mov	r6, r0				@ remember the old block
.L08021ca4:
	mov	r0, r8
	bl	string_length
	.inst.n	0x1c40				@ adds r0, r0, #1
	bl	fn_08022b50			@ allocate length + 1 bytes
	movs	r7, r0
	beq.n	.L08021c68			@ allocation failed: return
	mov	r1, r8
	bl	string_copy			@ copy the string into the new block
	str	r7, [r4, #0x24]
	cbz	r6, .L08021cc4
	mov	r0, r6
	bl	fn_08022c68			@ free the old block
.L08021cc4:
	cmp	r5, #2
	bne.n	.L08021d14
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x57
	bl	fn_08024bac
	mov	r6, r0				@ r6 = value of key 0x57 (full word)
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x58
	bl	fn_08024bac
	sxth	r7, r0				@ r7 = value of key 0x58
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x59
	bl	fn_08024bac
	sxth	r0, r0				@ value of key 0x59
	movw	r2, #0x1fff
	stm.w	sp, {r0, r2, r9}		@ stack arguments: key 0x59 value, 0x1fff, 0
	mov	r3, r7
	mov	r2, r6
	mov	r1, r8
	add	r0, sp, #0x10			@ output halfwords at sp+16, sp+18
	bl	fn_08027d30
	ldrh.w	r1, [sp, #0x10]
	ldr	r0, [sp, #0xc]
	bfi	r0, r1, #10, #11		@ bits 10..20 = halfword at sp+16
	ldrh.w	r1, [sp, #0x12]
	bfi	r0, r1, #21, #11		@ bits 21..31 = halfword at sp+18
	str	r0, [sp, #0xc]
.L08021d14:
	ldrb.w	r0, [r4, #0x38]
	bfi	r0, r5, #0, #2			@ bits 1..0 = class
	strb.w	r0, [r4, #0x38]
	ldr	r0, [sp, #0xc]
	ubfx	r1, r0, #10, #11
	strh	r1, [r4, #0x2c]
	lsrs	r3, r0, #0x15
	strh	r3, [r4, #0x2e]
	ldrb.w	r2, [r4, #0x38]
	bfi	r2, r0, #2, #5			@ bits 6..2 = low 5 bits of the word
	strb.w	r2, [r4, #0x38]
	lsrs	r2, r1, #1
	lsrs	r1, r0, #0x16
	strh	r2, [r4, #0x32]
	mov	r0, r4
	strh	r1, [r4, #0x34]
	bl	fn_08025d04
	ldrh	r0, [r4, #0x30]
	cbnz	r0, .L08021d52
	ldrh	r0, [r4, #0x36]
	cmp.w	r0, #0x100
	beq.n	.L08021d58
.L08021d52:
	mov	r0, r4
	bl	fn_08025cac
.L08021d58:
	mov	r0, r4
	bl	fn_08025400
	b.n	.L08021c68

@ ----------------------------------------------------------------------------
@ fn_08021d60 - classifies the first byte of a string.
@ r0 = byte pointer; returns the class in r0: 3 when the pointer is null,
@ 1 when the first byte is in 0x20..0x7f, 0 when the byte is below 0x80
@ (and outside 0x20..0x7f), else 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021d60,"ax",%progbits
	.p2align 2
	.global fn_08021d60
	.thumb_func
	.type fn_08021d60, %function
fn_08021d60:
	movs	r1, #3
	cbz	r0, .L08021d72
	ldrb	r0, [r0]
	sub.w	r1, r0, #0x20
	cmp	r1, #0x5f
	bhi.n	.L08021d76
	movs	r0, #1
	bx	lr
.L08021d72:
	mov	r0, r1				@ null pointer: class 3
	bx	lr
.L08021d76:
	cmp	r0, #0x80
	bcc.n	.L08021d7e
	movs	r0, #2
	bx	lr
.L08021d7e:
	movs	r0, #0
	bx	lr
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ read_word_200004ac - returns the word at 0x200004ac (0x200004a4 + 8).
@ No parameters; value returned in r0.
@ ----------------------------------------------------------------------------
	.section .text.read_word_200004ac,"ax",%progbits
	.p2align 2
	.global read_word_200004ac
	.thumb_func
	.type read_word_200004ac, %function
read_word_200004ac:
	ldr	r0, .L08021d8c
	ldr	r0, [r0, #8]
	bx	lr
	.short	0x0000				@ padding
.L08021d8c:
	.word	0x200004a4

@ ----------------------------------------------------------------------------
@ fn_08021d90 - iterates a list: returns the next node.
@ r0 = node or 0. With 0 it tail-calls get_word_4_or_zero(0x20008068) (the
@ head); otherwise it tail-calls read_word_at_base_plus_offset_4(0x20008068,
@ node) (the following node).
@ ----------------------------------------------------------------------------
	.section .text.fn_08021d90,"ax",%progbits
	.p2align 2
	.global fn_08021d90
	.thumb_func
	.type fn_08021d90, %function
fn_08021d90:
	cbz	r0, .L08021d9a
	mov	r1, r0
	ldr	r0, .L08021da0
	b.w	read_word_at_base_plus_offset_4
.L08021d9a:
	ldr	r0, .L08021da0
	b.w	get_word_4_or_zero
.L08021da0:
	.word	0x20008068

@ ----------------------------------------------------------------------------
@ read_word_200004a8 - returns the word at 0x200004a8 (0x200004a4 + 4).
@ No parameters; value returned in r0.
@ ----------------------------------------------------------------------------
	.section .text.read_word_200004a8,"ax",%progbits
	.p2align 2
	.global read_word_200004a8
	.thumb_func
	.type read_word_200004a8, %function
read_word_200004a8:
	ldr	r0, .L08021dac
	ldr	r0, [r0, #4]
	bx	lr
	.short	0x0000				@ padding
.L08021dac:
	.word	0x200004a4

@ ----------------------------------------------------------------------------
@ fn_08021db0 - reads the two size halfwords of an object into an output pair.
@ r0 = object (or 0), r1 = output of two halfwords. When the object is nonzero
@ and the byte at **object is 1 or 3, stores the halfwords at object+8 and
@ object+10 into out[0] and out[1]; otherwise stores 0xffff (0 for a null
@ object) into both.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021db0,"ax",%progbits
	.p2align 2
	.global fn_08021db0
	.thumb_func
	.type fn_08021db0, %function
fn_08021db0:
	cbz	r0, .L08021dc2
	ldr	r2, [r0]
	ldrb	r2, [r2]
	cmp	r2, #1
	beq.n	.L08021dc6
	cmp	r2, #3
	beq.n	.L08021dc6
	mov.w	r0, #0xffffffff
.L08021dc2:
	strh	r0, [r1]
	b.n	.L08021dcc
.L08021dc6:
	ldrh	r2, [r0, #8]
	strh	r2, [r1]
	ldrh	r0, [r0, #0xa]
.L08021dcc:
	strh	r0, [r1, #2]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08021dd0 - returns the low nibble of byte +0x40 of an object.
@ r0 = object; returns 0 when null or when the byte at **object is not 1 or 3,
@ else (byte at object+0x40) & 0xf.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021dd0,"ax",%progbits
	.global fn_08021dd0
	.thumb_func
	.type fn_08021dd0, %function
fn_08021dd0:
	cmp	r0, #0
	beq.n	.L08021de2
	ldr	r1, [r0]
	ldrb	r1, [r1]
	cmp	r1, #1
	beq.n	.L08021de4
	cmp	r1, #3
	beq.n	.L08021de4
	movs	r0, #0
.L08021de2:
	bx	lr
.L08021de4:
	ldrb.w	r0, [r0, #0x40]
	and.w	r0, r0, #0xf
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08021dee - returns word +0x2c of an object.
@ r0 = object; returns 0 when null or when the byte at **object is not 1 or 3,
@ else the word at object+0x2c.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021dee,"ax",%progbits
	.global fn_08021dee
	.thumb_func
	.type fn_08021dee, %function
fn_08021dee:
	cmp	r0, #0
	beq.n	.L08021e00
	ldr	r1, [r0]
	ldrb	r1, [r1]
	cmp	r1, #1
	beq.n	.L08021e02
	cmp	r1, #3
	beq.n	.L08021e02
	movs	r0, #0
.L08021e00:
	bx	lr
.L08021e02:
	ldr	r0, [r0, #0x2c]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08021e06 - returns the first byte of the object's class record.
@ r0 = object; returns 0 when null, else the byte at **object.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021e06,"ax",%progbits
	.global fn_08021e06
	.thumb_func
	.type fn_08021e06, %function
fn_08021e06:
	cmp	r0, #0
	beq.n	.L08021e0e
	ldr	r0, [r0]
	ldrb	r0, [r0]
.L08021e0e:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08021e10 - invalidates references to a value in one object or in all.
@ r0 = object or 0, r1 = value (kept in r4); r6 = 0x200004a4, r5 = 0.
@ Object given: sets bit 1 of byte +5, clears the word at 0x200004a8 when the
@ word at 0x200004ac equals the object, and for kinds (byte at **object) 1 or
@ 2 clears the words +0x30, +0x24, +0x28 that equal the value (all of them
@ when the value is 0).
@ Null object: repeats the same for every node returned by fn_08021d90
@ (starting with 0), then clears the word at 0x200004a8.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021e10,"ax",%progbits
	.p2align 2
	.global fn_08021e10
	.thumb_func
	.type fn_08021e10, %function
fn_08021e10:
	push	{r4, r5, r6, lr}
	ldr	r6, .L08021e94
	mov	r4, r1
	movs	r5, #0
	cbz	r0, .L08021e88
	ldrb	r1, [r0, #5]
	orr.w	r1, r1, #2
	strb	r1, [r0, #5]
	ldr	r1, [r6, #8]
	cmp	r1, r0
	bne.n	.L08021e2a
	str	r5, [r6, #4]
.L08021e2a:
	ldr	r1, [r0]
	ldrb	r1, [r1]
	cmp	r1, #1
	beq.n	.L08021e36
	cmp	r1, #2
	bne.n	.L08021e54
.L08021e36:
	cbz	r4, .L08021e3e
	ldr	r1, [r0, #0x30]
	cmp	r1, r4
	bne.n	.L08021e42
.L08021e3e:
	str	r5, [r0, #0x30]
	cbz	r4, .L08021e48
.L08021e42:
	ldr	r1, [r0, #0x24]
	cmp	r1, r4
	bne.n	.L08021e4c
.L08021e48:
	str	r5, [r0, #0x24]
	cbz	r4, .L08021e52
.L08021e4c:
	ldr	r1, [r0, #0x28]
	cmp	r1, r4
	bne.n	.L08021e54
.L08021e52:
	str	r5, [r0, #0x28]
.L08021e54:
	pop	{r4, r5, r6, pc}
.L08021e56:
	ldrb	r1, [r0, #5]
	orr.w	r1, r1, #2
	strb	r1, [r0, #5]
	ldr	r1, [r0]
	ldrb	r1, [r1]
	cmp	r1, #1
	beq.n	.L08021e6a
	cmp	r1, #2
	bne.n	.L08021e88
.L08021e6a:
	cbz	r4, .L08021e72
	ldr	r1, [r0, #0x30]
	cmp	r1, r4
	bne.n	.L08021e76
.L08021e72:
	str	r5, [r0, #0x30]
	cbz	r4, .L08021e7c
.L08021e76:
	ldr	r1, [r0, #0x24]
	cmp	r1, r4
	bne.n	.L08021e80
.L08021e7c:
	str	r5, [r0, #0x24]
	cbz	r4, .L08021e86
.L08021e80:
	ldr	r1, [r0, #0x28]
	cmp	r1, r4
	bne.n	.L08021e88
.L08021e86:
	str	r5, [r0, #0x28]
.L08021e88:
	bl	fn_08021d90			@ next node (0 for the first call)
	cmp	r0, #0
	bne.n	.L08021e56
	str	r5, [r6, #4]			@ clear the word at 0x200004a8
	pop	{r4, r5, r6, pc}
.L08021e94:
	.word	0x200004a4

@ ----------------------------------------------------------------------------
@ fn_08021e98 - one-time initialisation of the GUI module.
@ No parameters, no return value. When the byte at 0x2000045c is 0 it calls
@ fn_08022c94, fn_08012b50, init_header_20008074, fn_08011e1c,
@ init_header_2000808c, no_op, init_header_200080a4,
@ init_header_aligned4(0x2000805c, 0x15c), init_header_aligned4(0x20008068,
@ 0x58), return_only_08012b00, fn_080124a0 and fn_0802084a, then sets the byte
@ at 0x2000045c to 1.
@ The self-loop at .L08021ee8 is reached only when r0 = 0x44 equals 0x11 (the
@ compare at 0x08021eda, never true), so it is dead.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021e98,"ax",%progbits
	.p2align 2
	.global fn_08021e98
	.thumb_func
	.type fn_08021e98, %function
fn_08021e98:
	push	{r4, lr}
	ldr	r4, .L08021eec			@ r4 = address of the init flag byte
	ldrb	r0, [r4]
	cmp	r0, #0
	bne.n	.L08021ee6
	bl	fn_08022c94
	bl	fn_08012b50
	bl	init_header_20008074
	bl	fn_08011e1c
	bl	init_header_2000808c
	bl	no_op
	bl	init_header_200080a4
	mov.w	r1, #0x15c
	ldr	r0, .L08021ef0
	bl	init_header_aligned4
	movs	r1, #0x58
	ldr	r0, .L08021ef4
	bl	init_header_aligned4
	bl	return_only_08012b00
	bl	fn_080124a0
	movs	r0, #0x44
	cmp	r0, #0x11
	beq.n	.L08021ee8
	bl	fn_0802084a
	movs	r0, #1
	strb	r0, [r4]			@ mark the module initialised
.L08021ee6:
	pop	{r4, pc}
.L08021ee8:
	b.n	.L08021ee8
	.short	0x0000				@ padding
.L08021eec:
	.word	0x2000045c
.L08021ef0:
	.word	0x2000805c
.L08021ef4:
	.word	0x20008068

@ ----------------------------------------------------------------------------
@ fn_08021ef8 - resets a text object to its default state.
@ r1 = object (kept in r4); r0 is not read. Clears word +0x24, bits 3 and 4,
@ bits 0..2 and bit 6 of byte +0x48; sets words +0x2c and +0x30 to
@ 0xffffffff; sets words +0x38, +0x28, +0x34 to 0, words +0x3c and +0x40 to
@ 0xffff, halfwords +0x44 and +0x46 to 0. Then calls fn_08023558(object, 2),
@ fn_080227e4(object, 0) and tail-calls fn_0802285c(object, "Text").
@ ----------------------------------------------------------------------------
	.section .text.fn_08021ef8,"ax",%progbits
	.p2align 2
	.global fn_08021ef8
	.thumb_func
	.type fn_08021ef8, %function
fn_08021ef8:
	push	{r4, lr}
	mov	r4, r1
	movs	r0, #0
	str	r0, [r1, #0x24]
	ldrb.w	r1, [r4, #0x48]!		@ r4 = object + 0x48
	bic.w	r1, r1, #0x18			@ clear bits 3 and 4
	strb.w	r1, [r4], #-0x1c		@ r4 = object + 0x2c
	subs	r1, r0, #1			@ r1 = 0xffffffff
	str	r1, [r4]			@ word +0x2c = -1
	ldrb	r2, [r4, #0x1c]
	bic.w	r2, r2, #7			@ clear bits 0..2
	strb	r2, [r4, #0x1c]
	strh	r0, [r4, #0x18]			@ halfword +0x44 = 0
	strh	r0, [r4, #0x1a]			@ halfword +0x46 = 0
	str	r0, [r4, #0xc]			@ word +0x38 = 0
	strd	r1, r0, [r4, #4]		@ word +0x30 = -1, word +0x34 = 0
	lsrs	r1, r1, #0x10			@ r1 = 0xffff
	str	r1, [r4, #0x10]			@ word +0x3c = 0xffff
	str	r1, [r4, #0x14]			@ word +0x40 = 0xffff
	str.w	r0, [r4, #-4]			@ word +0x28 = 0
	ldrb.w	r0, [r4, #0x1c]!		@ r4 = object + 0x48
	movs	r1, #2
	bic.w	r0, r0, #0x40			@ clear bit 6
	strb.w	r0, [r4], #-0x48		@ r4 = object
	mov	r0, r4
	bl	fn_08023558
	movs	r1, #0
	mov	r0, r4
	bl	fn_080227e4
	mov	r0, r4
	pop.w	{r4, lr}
	adr	r1, .L08021f54			@ r1 = "Text"
	b.w	fn_0802285c
.L08021f54:
	.asciz	"Text"
	.byte	0x00, 0x00, 0x00		@ padding

@ ----------------------------------------------------------------------------
@ fn_08021f5c - creates an object from the class table at 0x0804fd3c.
@ r0 = argument. Calls fn_080233c4(table 0x0804fd3c, argument), then
@ fn_080234ac(object); returns the object created by fn_080233c4.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021f5c,"ax",%progbits
	.p2align 2
	.global fn_08021f5c
	.thumb_func
	.type fn_08021f5c, %function
fn_08021f5c:
	push	{r4, lr}
	mov	r1, r0
	ldr	r0, .L08021f70
	bl	fn_080233c4
	mov	r4, r0
	bl	fn_080234ac
	mov	r0, r4
	pop	{r4, pc}
.L08021f70:
	.word	d_0804fd3c

@ ----------------------------------------------------------------------------
@ fn_08021f74 - releases the text of an object.
@ r1 = object (kept in r4); r0 is not read. Calls fn_08021f92(object); when
@ bit 3 of byte +0x48 is clear frees the word +0x24 with fn_08022c68; then
@ clears word +0x24.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021f74,"ax",%progbits
	.global fn_08021f74
	.thumb_func
	.type fn_08021f74, %function
fn_08021f74:
	push	{r4, lr}
	mov	r0, r1
	mov	r4, r1
	bl	fn_08021f92
	ldrb.w	r0, [r4, #0x48]
	lsls	r0, r0, #0x1c			@ bit 3 to the sign bit
	bmi.n	.L08021f8c
	ldr	r0, [r4, #0x24]
	bl	fn_08022c68
.L08021f8c:
	movs	r0, #0
	str	r0, [r4, #0x24]
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08021f92 - releases the saved text copy of an object.
@ r0 = object (kept in r4). When bit 6 of byte +0x48 is set and word +0x28 is
@ nonzero frees it with fn_08022c68; then clears bit 6 (mask 0xbf) of byte
@ +0x48 and word +0x28.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021f92,"ax",%progbits
	.global fn_08021f92
	.thumb_func
	.type fn_08021f92, %function
fn_08021f92:
	push	{r4, lr}
	mov	r4, r0
	ldrb.w	r0, [r0, #0x48]
	lsls	r0, r0, #0x19			@ bit 6 to the sign bit
	bpl.n	.L08021fa6
	ldr	r0, [r4, #0x28]
	cbz	r0, .L08021fa6
	bl	fn_08022c68
.L08021fa6:
	ldrb.w	r0, [r4, #0x48]
	bic.w	r0, r0, #0x40
	strb.w	r0, [r4, #0x48]
	movs	r0, #0
	str	r0, [r4, #0x28]
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08021fb8 - message handler of the text class at table 0x0804fd3c.
@ r0 = value returned on the paths that reach the final pop (.L080220b6),
@ r1 = message pointer M (kept in r6); r2 and r3 are saved and not read.
@ Returns r0 unchanged or the result of a tail-called routine.
@ Calls fn_08023d54(0x0804fd3c, M); a result other than 1 returns r0.
@ t = get_byte8_low7(M) (r4), r5 = get_first_word(M). Dispatch: 0x2a and 0x29
@ go to .L08022016, 0x13 to .L08021ff8, 0x2c to .L08022026, 0x15 to the
@ tail call of fn_0801729a(M); any other t returns r0.
@  t = 0x2a or 0x29: calls fn_08022780(r5), then drops the saved registers,
@    r0 = r5 and tail-calls fn_080222b8(r5).
@  t = 0x13: v = signed halfword at fn_08024ca2(r5, 0) + 8; tail-calls
@    fn_08020834(M, v / 4 rounded toward zero).
@  t = 0x15: tail-calls fn_0801729a(M).
@  t = 0x2c: r9 = fn_08024ca2(r5, 0), r8 = fn_08024cb4(r5, 0), r7 =
@    fn_08024ccc(r5, 0); r4 = bit 4 of byte [r5+0x48] (value 1) | bit 5 of that
@    byte (value 2); calls fn_08023e7c(r5) (result unused); the limit is
@    0x1fff when fn_08024d08(r5, 0) = 0x27d1 and bit 10 of halfword [r5+0x22]
@    is clear, else fn_08023e7c(r5); calls fn_08027d30(sp+0xc, word [r5+0x24],
@    r9, r8, stack: r7, limit, r4), which fills two signed halfwords at sp+0xc
@    and sp+0xe; p = get_word_at_0x10(M); signed halfword [p] = max([p], the
@    halfword at sp+0xc) and signed halfword [p+2] = max([p+2], the halfword
@    at sp+0xe); returns r0.
@ Returns with pop {r0-r10, pc} at .L080220b6.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021fb8,"ax",%progbits
	.p2align 2
	.global fn_08021fb8
	.thumb_func
	.type fn_08021fb8, %function
fn_08021fb8:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r6, r1				@ r6 = message pointer
	ldr	r0, .L080220bc
	bl	fn_08023d54
	cmp	r0, #1
	bne.n	.L080220b6
	mov	r0, r6
	bl	get_byte8_low7
	mov	r4, r0				@ r4 = message type
	mov	r0, r6
	bl	get_first_word
	mov	r5, r0				@ r5 = target object
	cmp	r4, #0x2a
	beq.n	.L08022016
	cmp	r4, #0x13
	beq.n	.L08021ff8
	cmp	r4, #0x29
	beq.n	.L08022016
	cmp	r4, #0x2c
	beq.n	.L08022026
	cmp	r4, #0x15
	bne.n	.L080220b6
	add	sp, #0x10
	mov	r0, r6
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	b.w	fn_0801729a
.L08021ff8:
	movs	r1, #0
	bl	fn_08024ca2
	ldrsh.w	r0, [r0, #8]
	add	sp, #0x10
	asrs	r1, r0, #0x1f
	add.w	r0, r0, r1, lsr #30		@ add 3 to a negative value
	asrs	r1, r0, #2			@ value / 4, rounded toward zero
	mov	r0, r6
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	b.w	fn_08020834
.L08022016:
	bl	fn_08022780
	add	sp, #0x10
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	b.w	fn_080222b8
.L08022026:
	movs	r1, #0
	bl	fn_08024ca2
	mov	r9, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024cb4
	mov	r8, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024ccc
	mov	r7, r0
	ldrb.w	r0, [r5, #0x48]
	movs	r4, #0
	lsls	r1, r0, #0x1b			@ bit 4 to the sign bit
	bpl.n	.L0802204e
	movs	r4, #1
.L0802204e:
	lsls	r0, r0, #0x1a			@ bit 5 to the sign bit
	bpl.n	.L08022056
	orr.w	r4, r4, #2
.L08022056:
	mov	r0, r5
	bl	fn_08023e7c			@ result unused
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024d08
	sub.w	r1, r0, #0x2700
	subs	r1, #0xd1			@ compare with 0x27d1
	bne.n	.L08022078
	ldrh	r0, [r5, #0x22]
	lsls	r0, r0, #0x15			@ bit 10 to the sign bit
	bmi.n	.L08022078
	movw	r0, #0x1fff
	b.n	.L0802207e
.L08022078:
	mov	r0, r5
	bl	fn_08023e7c
.L0802207e:
	str	r7, [sp]
	strd	r0, r4, [sp, #4]
	mov	r3, r8
	mov	r2, r9
	add	r0, sp, #0xc			@ output halfwords at sp+0xc, sp+0xe
	ldr	r1, [r5, #0x24]
	bl	fn_08027d30
	mov	r0, r6
	bl	get_word_at_0x10
	ldrsh.w	r2, [r0]
	ldrsh.w	r1, [sp, #0xc]
	cmp	r2, r1
	ble.n	.L080220a4
	mov	r1, r2
.L080220a4:
	strh	r1, [r0]			@ [p] = max([p], width)
	ldrsh.w	r2, [r0, #2]
	ldrsh.w	r1, [sp, #0xe]
	cmp	r2, r1
	ble.n	.L080220b4
	mov	r1, r2
.L080220b4:
	strh	r1, [r0, #2]			@ [p+2] = max([p+2], height)
.L080220b6:
	pop.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, pc}
	.short	0x0000				@ padding
.L080220bc:
	.word	d_0804fd3c

@ ----------------------------------------------------------------------------
@ fn_080220c0 - finds the text position at which a line of a text object
@ fits into a limit and returns the sum of two calls through a stored
@ function pointer.
@ r0 = object (r8; word +0x24 = text pointer, byte +0x48, halfword +0x22),
@ r1 = pointer to two halfwords {limit width at +0, limit height at +2}.
@ Returns the sum of two calls through the function pointer stored in the word
@ at 0x20000514 (r6 + r0). Body contiguous, literals 0x20000510 (.L080222b0)
@ and 0x20000514 (.L080222b4).
@ r9 low half = short [r1] - fn_08024bac(r0, 0, 0x12), high half = short
@ [r1+2] - fn_08024bac(r0, 0, 0x10); fn_08023dec(r0, sp+0x20) fills a
@ rectangle (halfwords left at +0, right at +4 are read), word sp+0x14 =
@ sxth(right - left + 1); r7 = word [r0+0x24].
@ [sp+8] = fn_08024ca2(r0, 0) (halfword [result+8] read with ldrsh into
@ sp+0x1c), [sp+0] = fn_08024ccc(r0, 0), [sp+0xc] = fn_08024cb4(r0, 0).
@ r6 flags: bit 0 = bit 4 of byte [r0+0x48], bit 1 = bit 5 of byte [r0+0x48],
@ bit 2 = (fn_08024d08(r0, 0) = 0x27d1 and bit 10 of halfword [r0+0x22]
@ clear); r10 = fn_08023390(r0, 0, word [r0+0x24]) (compared with 2 and 3).
@ Line loop (.L080221c2, r5 = start offset, r4 = end offset, r11 = line y,
@ r8 = line step = ldrsh [font+8] + [sp+0]): while byte [r7+r5] is not 0:
@ r4 += fn_08012b9c(r7+r5, [sp+8], [sp+0xc], width, stack 0 and r6); when the
@ high half of r9 is above r11 + ldrsh [font+8] the line is accepted (r11 +=
@ r8, r5 = r4); otherwise calls the function pointer in the word at
@ 0x20000510 with (r7, address of word sp+0 holding r4), and r4 is
@ incremented when the result is not 10 and byte [r7+r4] is 0, and the loop
@ ends.
@ Alignment offset r8: r10 = 2 (.L080221de): fn_08027dec(line, r4 - r5, font,
@ [sp+0xc], stack r6) = w, offset = (rect width)/2 - (w/2) (halves toward
@ zero); r10 = 3: offset = rect width - w; other values: 0.
@ Character loop (.L08022238) while index [sp+0x10] + r5 is below r4:
@ fn_08012b6c(line, sp+4, sp+0, sp+0x10); when r6 bit 0 is set and
@ fn_08012c9c(sp+0x18, byte at line[index]) is non-zero the character is
@ skipped; else width = sxth(fn_08020a0a(font, [sp+4], [sp+0])); stops (index
@ = the previous index r10, .L080222aa) when the low half of r9 is below
@ width + offset, when index + r5 = r4, or when byte [r7+r10+r5] is 0;
@ otherwise r10 = index and offset = sxth(offset + width + [sp+0xc]).
@ Result = f(line pointer, index) + f(r7, r5) where f is the function whose
@ pointer is stored in the word at 0x20000514 (calls at 0x08022296 and
@ 0x080222a0).
@ ----------------------------------------------------------------------------
	.section .text.fn_080220c0,"ax",%progbits
	.p2align 2
	.global fn_080220c0
	.thumb_func
	.type fn_080220c0, %function
fn_080220c0:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r5, r1				@ r5 = limit pointer
	sub	sp, #0x2c
	mov	r8, r0				@ r8 = object
	movs	r1, #0
	movs	r2, #0x12
	bl	fn_08024bac
	ldrh	r1, [r5]
	movs	r2, #0x10
	subs	r0, r1, r0
	bfi	r4, r0, #0, #16			@ r9 low half = limit width - value 0x12
	mov	r0, r8
	movs	r1, #0
	bl	fn_08024bac
	ldrh	r1, [r5, #2]
	subs	r0, r1, r0
	bfi	r4, r0, #16, #16		@ r9 high half = limit height - value 0x10
	mov	r9, r4
	add	r1, sp, #0x20
	mov	r0, r8
	bl	fn_08023dec			@ rectangle at sp+0x20
	ldrh.w	r0, [sp, #0x24]
	ldrh.w	r1, [sp, #0x20]
	movs	r5, #0
	subs	r0, r0, r1
	.inst.n	0x1c40				@ adds r0, r0, #1
	sxth	r0, r0
	ldr.w	r7, [r8, #0x24]			@ r7 = text pointer
	str	r0, [sp, #0x14]			@ rectangle width
	mov	r4, r5
	mov	r1, r5
	mov	r0, r8
	bl	fn_08024ca2
	str	r0, [sp, #8]			@ font pointer
	movs	r1, #0
	mov	r0, r8
	bl	fn_08024ccc
	str	r0, [sp]
	movs	r1, #0
	mov	r0, r8
	bl	fn_08024cb4
	str	r0, [sp, #0xc]
	ldr	r0, [sp, #8]
	mov	r11, r5
	mov	r6, r11
	ldrsh.w	r0, [r0, #8]
	str	r0, [sp, #0x1c]			@ font height
	ldrb.w	r0, [r8, #0x48]
	lsls	r1, r0, #0x1b
	bpl.n	.L08022142
	movs	r6, #1
.L08022142:
	lsls	r0, r0, #0x1a
	bpl.n	.L0802214a
	orr.w	r6, r6, #2
.L0802214a:
	movs	r1, #0
	mov	r0, r8
	bl	fn_08024d08
	sub.w	r1, r0, #0x2700
	subs	r1, #0xd1			@ compare with 0x27d1
	bne.n	.L08022166
	ldrh.w	r0, [r8, #0x22]
	lsls	r0, r0, #0x15
	bmi.n	.L08022166
	orr.w	r6, r6, #4
.L08022166:
	mov	r0, r8
	movs	r1, #0
	ldr.w	r2, [r8, #0x24]
	bl	fn_08023390
	mov	r10, r0				@ r10 = alignment kind
	ldr	r1, [sp]
	ldr	r0, [sp, #0x1c]
	add.w	r8, r0, r1			@ r8 = line step
	b.n	.L080221c2
.L0802217e:
	movs	r0, #0
	strd	r0, r6, [sp]			@ stack arguments: 0 and flags
	ldrd	r1, r2, [sp, #8]
	adds	r0, r7, r5
	ldr	r3, [sp, #0x14]
	bl	fn_08012b9c
	ldr	r1, [sp, #0x1c]
	add	r4, r0				@ end offset += characters on the line
	asr.w	r2, r9, #16
	add.w	r0, r11, r1
	cmp	r2, r0
	bgt.n	.L080221b8
	ldr	r2, .L080222b0
	str	r4, [sp]
	mov	r1, sp
	ldr	r2, [r2]
	mov	r0, r7
	blx	r2
	cmp	r0, #0xa
	beq.n	.L080221c8
	ldrb	r0, [r7, r4]
	cbnz	r0, .L080221c8
	.inst.n	0x1c64				@ adds r4, r4, #1
	b.n	.L080221c8
.L080221b8:
	add.w	r0, r8, r11
	sxth.w	r11, r0
	mov	r5, r4
.L080221c2:
	ldrb	r0, [r7, r5]
	cmp	r0, #0
	bne.n	.L0802217e
.L080221c8:
	add.w	r11, r7, r5			@ r11 = start of the line
	mov.w	r8, #0
	cmp.w	r10, #2
	beq.n	.L080221de
	cmp.w	r10, #3
	beq.n	.L0802220a
	b.n	.L0802222a
.L080221de:
	ldrd	r2, r3, [sp, #8]
	subs	r1, r4, r5
	mov	r0, r11
	str	r6, [sp]
	bl	fn_08027dec
	ldrh.w	r1, [sp, #0x24]
	ldrh.w	r2, [sp, #0x20]
	add.w	r0, r0, r0, lsr #31
	subs	r1, r1, r2
	.inst.n	0x1c49				@ adds r1, r1, #1
	sxth	r1, r1
	add.w	r1, r1, r1, lsr #31
	asrs	r1, r1, #1
	sub.w	r0, r1, r0, asr #1
	b.n	.L08022226
.L0802220a:
	ldrd	r2, r3, [sp, #8]
	subs	r1, r4, r5
	mov	r0, r11
	str	r6, [sp]
	bl	fn_08027dec
	ldrh.w	r2, [sp, #0x24]
	ldrh.w	r1, [sp, #0x20]
	subs	r1, r2, r1
	.inst.n	0x1c49				@ adds r1, r1, #1
	subs	r0, r1, r0
.L08022226:
	sxth.w	r8, r0
.L0802222a:
	movs	r0, #0
	strb.w	r0, [sp, #0x18]
	mov	r10, r0
	str	r0, [sp, #0x10]
	cbnz	r4, .L08022286
	b.n	.L0802228e
.L08022238:
	add	r3, sp, #0x10
	mov	r2, sp
	add	r1, sp, #4
	mov	r0, r11
	bl	fn_08012b6c
	lsls	r0, r6, #0x1f
	beq.n	.L08022256
	ldr	r1, [sp, #0x10]
	add	r0, sp, #0x18
	ldrb.w	r1, [r11, r1]
	bl	fn_08012c9c
	cbnz	r0, .L08022286
.L08022256:
	ldrd	r1, r0, [sp, #4]
	ldr	r2, [sp]
	bl	fn_08020a0a
	sxth	r0, r0
	sxth.w	r2, r9
	add	r0, r8
	cmp	r2, r0
	blt.n	.L080222aa
	ldr	r1, [sp, #0x10]
	adds	r2, r1, r5
	cmp	r2, r4
	beq.n	.L080222aa
	add.w	r2, r10, r5
	ldrb	r2, [r7, r2]
	cbz	r2, .L080222aa
	ldr	r2, [sp, #0xc]
	mov	r10, r1
	add	r0, r2
	sxth.w	r8, r0
.L08022286:
	ldr	r0, [sp, #0x10]
	add	r0, r5
	cmp	r0, r4
	bcc.n	.L08022238
.L0802228e:
	ldr	r4, .L080222b4
	mov	r0, r11
	ldr	r1, [sp, #0x10]
	ldr	r2, [r4]
	blx	r2
	mov	r6, r0
	ldr	r2, [r4]
	mov	r1, r5
	mov	r0, r7
	blx	r2
	add	sp, #0x2c
	add	r0, r6
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L080222aa:
	str.w	r10, [sp, #0x10]
	b.n	.L0802228e
.L080222b0:
	.word	0x20000510
.L080222b4:
	.word	0x20000514

@ ----------------------------------------------------------------------------
@ fn_080222b8 - lays out the text of an object and starts or stops its
@ scrolling animation records.
@ r0 = object (r4); no return value. Returns without further work when word
@ obj+0x24 is 0 (.L080223c4 -> .L0802275c).
@ Word obj+0x30 = 0xffffffff; fn_08023dec(obj, sp+0xc) fills the area
@ rectangle (halfwords x0, y0, x1, y1 at sp+0xc, +0xe, +0x10, +0x12); width W
@ = sxth(x1 - x0 + 1) (r8); r5 = fn_08024ca2(obj, 0), r7 = fn_08024ccc(obj,
@ 0), r10 = fn_08024cb4(obj, 0); flags r6 = (bit 4 of byte obj+0x48) | (bit 5
@ of byte obj+0x48 as value 2) | 4 when fn_08024d08(obj, 0) = 0x27d1 and bit
@ 10 of halfword obj+0x22 is clear; fn_08027d30(sp+0x58, [obj+0x24], r5, r10,
@ [sp]=r7, [sp+4]=W, [sp+8]=r6), after which the halfwords at sp+0x58 and
@ sp+0x5a are the text width Tw and text height Th (signed).
@ fn_08025d04(obj); r8 = 0, r11 = 0xffff.
@ Mode = byte obj+0x48 AND 7: 2 -> .L08022368, 3 -> .L080224aa, 1 ->
@ .L080225f0, other values go to the common end (.L08022756).
@ Common end: fn_08025400(obj), then add sp,#0x5c and pop at .L0802275c.
@ Animation records live on the stack at sp+0x14 (initialised by
@ fn_0801c718(sp+0x14)); callbacks are 0x080297ad (stored at sp+0x18 in the
@ horizontal case) and 0x080297b5 (vertical); an existing record is looked up
@ with fn_0801c6e8(obj, callback) (word record+0x30 and bit 1 of byte
@ record+0x42 are read from it), a record is removed with fn_0801c688(obj,
@ callback), a duration is computed by fn_0801c7a4(duration, [sp+0x34],
@ [sp+0x3c]) and a record is started with fn_0801c7c0(sp+0x14).
@ Mode 2 (.L08022368): duration r6 = unsigned halfword fn_080248e4(obj, 0),
@ when 0 it is fn_0801dcd8(fn_08023ebc(obj)) / 3 (sdiv, uxth); record:
@ [sp+0x14] = obj, words sp+0x48 and sp+0x50 = 0x12c, halfword sp+0x54 =
@ 0xffff; when W >= Tw: fn_0801c688(obj, 0x080297ad) and halfword obj+0x44 =
@ 0, no horizontal record; else words sp+0x34 = 0, sp+0x38 = 0, sp+0x3c = W -
@ Tw, callback sp+0x18 = 0x080297ad, existing record found with fn_0801c6e8
@ (obj, 0x080297ad): when word sp+0x40 > its word +0x30 (signed) then word
@ sp+0x44 = that value, bit 0 of byte sp+0x56 cleared, and when its bit 1 of
@ byte +0x42 is set bit 1 of byte sp+0x56 is set and words sp+0x34 and sp+0x3c
@ are swapped; then r0 = fn_0801c7a4(r6, [sp+0x34], [sp+0x3c]) stored to words
@ sp+0x40 and sp+0x4c, fn_0801c7c0(sp+0x14) and r7 = 1.
@ Mode 2 vertical (.L08022428): only when sxth(y1 - y0 + 1) < Th and r7 = 0:
@ words sp+0x34 = 0, sp+0x38 = 0, sp+0x3c = (areaH - Th) - signed halfword
@ [r5+8], callback 0x080297b5, same record lookup, compare, swap and
@ fn_0801c7a4 steps as above (0x08022464..0x080224a8), then fn_0801c7c0
@ (sp+0x14) (.L080225e8); otherwise the vertical record is removed
@ (.L0802258e: fn_0801c688(obj, 0x080297b5), halfword obj+0x46 = 0).
@ Mode 3 (.L080224aa): r6 = fn_08024bac(obj, 0, 0x63) (record or 0), r7 =
@ duration as in mode 2; record [sp+0x14] = obj, halfword sp+0x54 = 0xffff,
@ r9 = 0; when W >= Tw the horizontal record is removed (.L08022566); else r0
@ = fn_08020a0a(r5, 0x20, 0x20), s = Tw + 3*r0, words sp+0x34 = 0, sp+0x38 =
@ 0, sp+0x3c = -s, callback 0x080297ad, word sp+0x40 = fn_0801c7a4(r7, 0, -s),
@ existing record via fn_0801c6e8(obj, 0x080297ad) (r0 = its word +0x30 or 0);
@ when r6 is nonzero words sp+0x44 = [r6+0x30] and sp+0x50 = [r6+0x3c],
@ otherwise when word sp+0x40 > r0 word sp+0x44 = r0 and bit 0 of byte sp+0x56
@ is cleared; fn_0801c7c0(sp+0x14), r9 = 1; vertical (.L08022572): only when
@ areaH < Th and r9 = 0, words sp+0x34 = 0, sp+0x38 = 0, sp+0x3c = -(Th +
@ signed halfword [r5+8]), callback 0x080297b5, fn_0801c7a4(r7, 0, that
@ value), same lookup and fields, fn_0801c7c0(sp+0x14); otherwise
@ fn_0801c688(obj, 0x080297b5) and halfword obj+0x46 = 0.
@ Mode 1 (.L080225f0): acts only when areaH < Th and Th > signed halfword
@ [r5+8] and the function in the word at 0x20000518 called with the text
@ pointer returns more than 3 (unsigned); otherwise word obj+0x2c =
@ 0xffffffff. The cut: r6 = (x1 - x0 + 1) as unsigned halfword difference;
@ halfword [sp+0] = r6 - 3*(fn_08020a0a(r5, 0x2e, 0x2e) + r10); halfword
@ [sp+2] = areaH - rem - r7 when signed halfword [r5+8] > rem, else areaH -
@ rem + halfword [r5+8], where rem = areaH mod (halfword [r5+8] + r7) (sdiv,
@ mls); r9 = fn_080220c0(obj, sp); r7 = string_length(text); [sp+4] = [word at
@ 0x2000050c](text, r9); while [sp+4] + 3 > r7 (unsigned) [word at
@ 0x20000510](text, sp+4) is called and r9 is decremented; then up to 4
@ passes of r5 = (r5 + [word at 0x20000504](text + [sp+4])) as byte and [word
@ at 0x20000508](text, sp+4), stopping when r5 > 3 or [sp+4] > r7; r6 = the
@ cut offset; r10 = text + r6; fn_08021f92(obj); when r5 > 4 a buffer
@ fn_08022b50(r5+1) is stored at word obj+0x28 (zero ends the function at the
@ common end), copy_bytes_08022ce0(buffer, r10, r5), byte buffer[r5] = 0, bit
@ 6 of byte obj+0x48 is set; else bit 6 is cleared and copy_bytes_08022ce0
@ (obj+0x28, r10, r5); then three bytes 0x2e are written at text+r6.., a 0
@ byte at text+r6+3 and word obj+0x2c = r9 + 3.
@ ----------------------------------------------------------------------------
	.section .text.fn_080222b8,"ax",%progbits
	.p2align 2
	.global fn_080222b8
	.thumb_func
	.type fn_080222b8, %function
fn_080222b8:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r4, r0				@ r4 = object
	ldr	r0, [r0, #0x24]
	sub	sp, #0x5c
	cmp	r0, #0
	beq.n	.L080223c4			@ no text: return
	mov.w	r9, #0xffffffff
	add	r1, sp, #0xc
	mov	r0, r4
	str.w	r9, [r4, #0x30]
	bl	fn_08023dec			@ area rectangle at sp+0xc
	ldrh.w	r0, [sp, #0x10]
	ldrh.w	r1, [sp, #0xc]
	subs	r0, r0, r1
	.inst.n	0x1c40				@ adds r0, r0, #1
	sxth.w	r8, r0				@ r8 = area width W
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024ca2
	mov	r5, r0				@ r5 = font pointer
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024ccc
	mov	r7, r0
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024cb4
	mov	r10, r0
	ldrb.w	r0, [r4, #0x48]
	movs	r6, #0
	lsls	r1, r0, #0x1b
	bpl.n	.L08022310
	movs	r6, #1
.L08022310:
	lsls	r0, r0, #0x1a
	bpl.n	.L08022318
	orr.w	r6, r6, #2
.L08022318:
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024d08
	sub.w	r1, r0, #0x2700
	subs	r1, #0xd1			@ compare with 0x27d1
	bne.n	.L08022332
	ldrh	r0, [r4, #0x22]
	lsls	r0, r0, #0x15
	bmi.n	.L08022332
	orr.w	r6, r6, #4
.L08022332:
	str	r7, [sp]
	strd	r8, r6, [sp, #4]
	mov	r3, r10
	mov	r2, r5
	add	r0, sp, #0x58			@ output Tw at sp+0x58, Th at sp+0x5a
	ldr	r1, [r4, #0x24]
	bl	fn_08027d30
	mov	r0, r4
	bl	fn_08025d04
	ldrb.w	r0, [r4, #0x48]
	movw	r11, #0xffff
	and.w	r0, r0, #7			@ mode
	mov.w	r8, #0
	cmp	r0, #2
	beq.n	.L08022368
	cmp	r0, #3
	beq.n	.L08022460
	cmp	r0, #1
	beq.n	.L08022462
	b.n	.L08022756
.L08022368:
	movs	r1, #0
	mov	r0, r4
	bl	fn_080248e4
	lsls	r6, r0, #0x10
	lsrs	r6, r6, #0x10			@ r6 = duration (uxth)
	bne.n	.L08022388
	mov	r0, r4
	bl	fn_08023ebc
	bl	fn_0801dcd8
	movs	r1, #3
	sdiv	r0, r0, r1
	uxth	r6, r0
.L08022388:
	add	r0, sp, #0x14
	bl	fn_0801c718			@ initialise the record at sp+0x14
	mov.w	r0, #0x12c
	str	r4, [sp, #0x14]
	str	r0, [sp, #0x48]
	str	r0, [sp, #0x50]
	ldrh.w	r0, [sp, #0x10]
	ldrh.w	r1, [sp, #0xc]
	ldrsh.w	r2, [sp, #0x58]
	subs	r0, r0, r1
	.inst.n	0x1c40				@ adds r0, r0, #1
	movs	r7, #0				@ r7 = horizontal record started flag
	sxth	r0, r0
	strh.w	r11, [sp, #0x54]
	cmp	r0, r2
	bge.n	.L0802241c
	movs	r1, #0
	subs	r0, r0, r2
	strd	r1, r0, [sp, #0x38]
	ldr	r0, .L08022764
	str	r1, [sp, #0x34]
	mov	r1, r0
	b.n	.L080223c6
.L080223c4:
	b.n	.L0802275c
.L080223c6:
	str	r0, [sp, #0x18]			@ callback 0x080297ad
	mov	r0, r4
	bl	fn_0801c6e8
	movs	r1, #0
	mov	r2, r1
	cbz	r0, .L080223de
	ldr	r1, [r0, #0x30]
	ldrb.w	r0, [r0, #0x42]
	ubfx	r2, r0, #1, #1
.L080223de:
	ldr	r0, [sp, #0x40]
	cmp	r0, r1
	ble.n	.L08022404
	ldrb.w	r0, [sp, #0x56]
	str	r1, [sp, #0x44]
	bic.w	r0, r0, #1
	strb.w	r0, [sp, #0x56]
	cbz	r2, .L08022404
	orr.w	r0, r0, #2
	strb.w	r0, [sp, #0x56]
	ldr	r1, [sp, #0x3c]
	ldr	r0, [sp, #0x34]
	str	r1, [sp, #0x34]			@ swap words sp+0x34 and sp+0x3c
	str	r0, [sp, #0x3c]
.L08022404:
	mov	r0, r6
	ldr	r2, [sp, #0x3c]
	ldr	r1, [sp, #0x34]
	bl	fn_0801c7a4
	str	r0, [sp, #0x40]
	str	r0, [sp, #0x4c]
	add	r0, sp, #0x14
	bl	fn_0801c7c0			@ start the record
	movs	r7, #1
	b.n	.L08022428
.L0802241c:
	ldr	r1, .L08022764
	mov	r0, r4
	bl	fn_0801c688			@ remove the horizontal record
	strh.w	r8, [r4, #0x44]
.L08022428:
	ldrh.w	r0, [sp, #0x12]
	ldrh.w	r1, [sp, #0xe]
	ldrsh.w	r2, [sp, #0x5a]
	subs	r0, r0, r1
	.inst.n	0x1c40				@ adds r0, r0, #1
	sxth	r0, r0
	cmp	r0, r2
	bge.n	.L0802253c
	cmp	r7, #0
	bne.n	.L0802253c
	subs	r2, r0, r2
	ldrsh.w	r0, [r5, #8]
	movs	r1, #0
	subs	r0, r2, r0
	strd	r1, r0, [sp, #0x38]
	ldr	r0, .L08022768
	str	r1, [sp, #0x34]
	mov	r1, r0
	str	r0, [sp, #0x18]			@ callback 0x080297b5
	mov	r0, r4
	bl	fn_0801c6e8
	b.n	.L08022464
.L08022460:
	b.n	.L080224aa
.L08022462:
	b.n	.L080225f0
.L08022464:
	movs	r1, #0
	mov	r2, r1
	cbz	r0, .L08022474
	ldr	r1, [r0, #0x30]
	ldrb.w	r0, [r0, #0x42]
	ubfx	r2, r0, #1, #1
.L08022474:
	ldr	r0, [sp, #0x40]
	cmp	r0, r1
	ble.n	.L0802249a
	ldrb.w	r0, [sp, #0x56]
	str	r1, [sp, #0x44]
	bic.w	r0, r0, #1
	strb.w	r0, [sp, #0x56]
	cbz	r2, .L0802249a
	orr.w	r0, r0, #2
	strb.w	r0, [sp, #0x56]
	ldr	r1, [sp, #0x3c]
	ldr	r0, [sp, #0x34]
	str	r1, [sp, #0x34]			@ swap words sp+0x34 and sp+0x3c
	str	r0, [sp, #0x3c]
.L0802249a:
	mov	r0, r6
	ldr	r2, [sp, #0x3c]
	ldr	r1, [sp, #0x34]
	bl	fn_0801c7a4
	str	r0, [sp, #0x40]
	str	r0, [sp, #0x4c]
	b.n	.L080225e8
.L080224aa:
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x63
	bl	fn_08024bac
	mov	r6, r0				@ r6 = record for key 0x63 (or 0)
	movs	r1, #0
	mov	r0, r4
	bl	fn_080248e4
	lsls	r7, r0, #0x10
	lsrs	r7, r7, #0x10			@ r7 = duration (uxth)
	bne.n	.L080224d6
	mov	r0, r4
	bl	fn_08023ebc
	bl	fn_0801dcd8
	movs	r1, #3
	sdiv	r0, r0, r1
	uxth	r7, r0
.L080224d6:
	add	r0, sp, #0x14
	bl	fn_0801c718
	ldrh.w	r0, [sp, #0x10]
	ldrh.w	r1, [sp, #0xc]
	str	r4, [sp, #0x14]
	subs	r0, r0, r1
	.inst.n	0x1c40				@ adds r0, r0, #1
	ldrsh.w	r1, [sp, #0x58]
	sxth	r0, r0
	strh.w	r11, [sp, #0x54]
	mov.w	r9, #0				@ r9 = horizontal record started flag
	cmp	r0, r1
	bge.n	.L08022566
	movs	r2, #0x20
	mov	r1, r2
	mov	r0, r5
	bl	fn_08020a0a
	ldrsh.w	r1, [sp, #0x58]
	add.w	r0, r0, r0, lsl #1		@ 3 * width
	add	r0, r1
	rsbs	r1, r0, #0			@ r1 = -s
	strd	r9, r1, [sp, #0x38]
	ldr	r0, .L08022764
	mov	r2, r1
	str	r0, [sp, #0x18]			@ callback 0x080297ad
	str.w	r9, [sp, #0x34]
	mov	r1, r9
	mov	r0, r7
	bl	fn_0801c7a4
	str	r0, [sp, #0x40]
	ldr	r1, .L08022764
	mov	r0, r4
	bl	fn_0801c6e8
	cbz	r0, .L08022536
	ldr	r0, [r0, #0x30]
.L08022536:
	cbz	r6, .L08022546
	ldr	r0, [r6, #0x30]
	b.n	.L0802253e
.L0802253c:
	b.n	.L0802258e
.L0802253e:
	str	r0, [sp, #0x44]
	ldr	r0, [r6, #0x3c]
	str	r0, [sp, #0x50]
	b.n	.L0802255a
.L08022546:
	ldr	r1, [sp, #0x40]
	cmp	r1, r0
	ble.n	.L0802255a
	str	r0, [sp, #0x44]
	ldrb.w	r0, [sp, #0x56]
	bic.w	r0, r0, #1
	strb.w	r0, [sp, #0x56]
.L0802255a:
	add	r0, sp, #0x14
	bl	fn_0801c7c0
	mov.w	r9, #1
	b.n	.L08022572
.L08022566:
	ldr	r1, .L08022764
	mov	r0, r4
	bl	fn_0801c688			@ remove the horizontal record
	strh.w	r8, [r4, #0x44]
.L08022572:
	ldrh.w	r0, [sp, #0x12]
	ldrh.w	r1, [sp, #0xe]
	subs	r0, r0, r1
	.inst.n	0x1c40				@ adds r0, r0, #1
	ldrsh.w	r1, [sp, #0x5a]
	sxth	r0, r0
	cmp	r0, r1
	bge.n	.L0802258e
	cmp.w	r9, #0
	beq.n	.L0802259c
.L0802258e:
	ldr	r1, .L08022768
	mov	r0, r4
	bl	fn_0801c688			@ remove the vertical record
	strh.w	r8, [r4, #0x46]
	b.n	.L08022756
.L0802259c:
	ldrsh.w	r2, [r5, #8]
	movs	r0, #0
	add	r1, r2
	rsbs	r1, r1, #0
	str	r0, [sp, #0x34]
	strd	r0, r1, [sp, #0x38]
	ldr	r0, .L08022768
	mov	r2, r1
	str	r0, [sp, #0x18]			@ callback 0x080297b5
	mov	r0, r7
	ldr	r1, [sp, #0x34]
	bl	fn_0801c7a4
	str	r0, [sp, #0x40]
	ldr	r1, .L08022768
	mov	r0, r4
	bl	fn_0801c6e8
	cbz	r0, .L080225c8
	ldr	r0, [r0, #0x30]
.L080225c8:
	cbz	r6, .L080225d4
	ldr	r0, [r6, #0x30]
	str	r0, [sp, #0x44]
	ldr	r0, [r6, #0x3c]
	str	r0, [sp, #0x50]
	b.n	.L080225e8
.L080225d4:
	ldr	r1, [sp, #0x40]
	cmp	r1, r0
	ble.n	.L080225e8
	str	r0, [sp, #0x44]
	ldrb.w	r0, [sp, #0x56]
	bic.w	r0, r0, #1
	strb.w	r0, [sp, #0x56]
.L080225e8:
	add	r0, sp, #0x14
	bl	fn_0801c7c0			@ start the vertical record
	b.n	.L08022756
.L080225f0:
	ldrh.w	r0, [sp, #0x12]
	ldrh.w	r1, [sp, #0xe]
	subs	r0, r0, r1
	.inst.n	0x1c40				@ adds r0, r0, #1
	sxth	r1, r0				@ areaH
	ldrsh.w	r0, [sp, #0x5a]			@ Th
	cmp	r1, r0
	bge.n	.L0802261a
	ldrsh.w	r1, [r5, #8]
	cmp	r0, r1
	ble.n	.L0802261a
	ldr	r1, .L0802276c
	ldr	r0, [r4, #0x24]
	ldr	r1, [r1]
	blx	r1
	cmp	r0, #3
	bhi.n	.L08022620
.L0802261a:
	str.w	r9, [r4, #0x2c]			@ word +0x2c = 0xffffffff
	b.n	.L08022756
.L08022620:
	ldrh.w	r0, [sp, #0x10]
	ldrh.w	r1, [sp, #0xc]
	movs	r2, #0x2e
	subs	r6, r0, r1
	mov	r1, r2
	mov	r0, r5
	.inst.n	0x1c76				@ adds r6, r6, #1
	bl	fn_08020a0a
	add	r0, r10
	sub.w	r0, r0, r0, lsl #2		@ -3 * (width + r10)
	add	r0, r6
	strh.w	r0, [sp]			@ halfword [sp+0]
	ldrh.w	r0, [sp, #0x12]
	ldrh.w	r1, [sp, #0xe]
	subs	r0, r0, r1
	.inst.n	0x1c40				@ adds r0, r0, #1
	sxth	r0, r0
	strh.w	r0, [sp, #2]
	ldrsh.w	r2, [r5, #8]
	adds	r1, r2, r7
	sdiv	r3, r0, r1
	mls	r1, r1, r3, r0			@ rem = areaH mod (height + r7)
	cmp	r2, r1
	sub.w	r0, r0, r1
	bgt.n	.L08022674
	strh.w	r0, [sp, #2]
	ldrh	r1, [r5, #8]
	add	r0, r1
	b.n	.L08022676
.L08022674:
	subs	r0, r0, r7
.L08022676:
	strh.w	r0, [sp, #2]
	mov	r1, sp
	mov	r0, r4
	bl	fn_080220c0
	mov	r9, r0
	ldr	r0, [r4, #0x24]
	bl	string_length
	ldr	r2, .L08022770
	mov	r7, r0
	mov	r1, r9
	ldr	r2, [r2]
	ldr	r0, [r4, #0x24]
	blx	r2
	ldr	r5, .L08022774
	str	r0, [sp, #4]
	b.n	.L080226a8
.L0802269c:
	ldr	r2, [r5]
	add	r1, sp, #4
	ldr	r0, [r4, #0x24]
	blx	r2
	sub.w	r9, r9, #1
.L080226a8:
	ldr	r0, [sp, #4]
	.inst.n	0x1cc0				@ adds r0, r0, #3
	cmp	r0, r7
	bhi.n	.L0802269c
	movs	r5, #0
	ldr.w	r11, .L08022778
	ldr	r6, [sp, #4]
	mov	r10, r5
.L080226ba:
	ldr	r0, [r4, #0x24]
	ldr	r1, [sp, #4]
	add	r0, r1
	ldr.w	r1, [r11]
	blx	r1
	ldr	r2, .L0802277c
	add	r0, r5
	uxtb	r5, r0
	ldr	r2, [r2]
	add	r1, sp, #4
	ldr	r0, [r4, #0x24]
	blx	r2
	cmp	r5, #3
	bhi.n	.L080226e8
	ldr	r0, [sp, #4]
	cmp	r0, r7
	bhi.n	.L080226e8
	add.w	r10, r10, #1
	cmp.w	r10, #3
	bls.n	.L080226ba
.L080226e8:
	ldr	r1, [r4, #0x24]
	mov	r0, r4
	add.w	r10, r1, r6
	mov	r7, r0
	bl	fn_08021f92
	cmp	r5, #4
	bls.n	.L08022720
	adds	r0, r5, #1
	bl	fn_08022b50
	str	r0, [r7, #0x28]
	cbz	r0, .L08022756
	mov	r2, r5
	mov	r1, r10
	bl	copy_bytes_08022ce0
	ldr	r1, [r7, #0x28]
	strb.w	r8, [r1, r5]
	ldrb.w	r0, [r7, #0x48]
	orr.w	r0, r0, #0x40
	strb.w	r0, [r7, #0x48]
	b.n	.L08022738
.L08022720:
	ldrb.w	r0, [r7, #0x48]
	mov	r2, r5
	bic.w	r0, r0, #0x40
	strb.w	r0, [r7, #0x48]
	mov	r1, r10
	add.w	r0, r7, #0x28
	bl	copy_bytes_08022ce0
.L08022738:
	movs	r0, #0
	movs	r1, #0x2e
.L0802273c:
	adds	r3, r6, r0
	ldr	r2, [r4, #0x24]
	.inst.n	0x1c40				@ adds r0, r0, #1
	cmp	r0, #3
	strb	r1, [r2, r3]			@ write one '.' of the ellipsis
	bcc.n	.L0802273c
	ldr	r1, [r4, #0x24]
	.inst.n	0x1cf6				@ adds r6, r6, #3
	add.w	r0, r9, #3
	strb.w	r8, [r1, r6]
	str	r0, [r4, #0x2c]
.L08022756:
	mov	r0, r4
	bl	fn_08025400
.L0802275c:
	add	sp, #0x5c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short	0x0000				@ padding
.L08022764:
	.word	fn_080297ac			@ callback 0x080297ad (horizontal)
.L08022768:
	.word	fn_080297b4			@ callback 0x080297b5 (vertical)
.L0802276c:
	.word	0x20000518
.L08022770:
	.word	0x2000050c
.L08022774:
	.word	0x20000510
.L08022778:
	.word	0x20000504
.L0802277c:
	.word	0x20000508

@ ----------------------------------------------------------------------------
@ fn_08022780 - restores the text that an ellipsis cut replaced.
@ r0 = text object (kept in r4 and r5); no return value. When (byte +0x48 & 7)
@ is 1 and word +0x2c is not -1: pos = [word at 0x2000050c](text, +0x2c - 3);
@ for i = 0, 1, ... copies the saved byte src[i] to text[pos+i] while
@ text[pos+i] is nonzero (src = word +0x28 as a pointer when bit 6 of byte
@ +0x48 is set, else the inline bytes at +0x28), then writes src[i] over the
@ first zero byte text[pos+i], calls fn_08021f92(object) and sets word +0x2c
@ to 0xffffffff.
@ ----------------------------------------------------------------------------
	.section .text.fn_08022780,"ax",%progbits
	.p2align 2
	.global fn_08022780
	.thumb_func
	.type fn_08022780, %function
fn_08022780:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r4, r0
	mov	r5, r0
	ldrb.w	r0, [r0, #0x48]
	and.w	r0, r0, #7			@ mode
	cmp	r0, #1
	bne.n	.L080227dc
	ldr	r1, [r5, #0x2c]
	adds	r0, r1, #1			@ -1 means nothing was cut
	beq.n	.L080227dc
	ldr	r2, .L080227e0
	ldr	r0, [r5, #0x24]
	.inst.n	0x1ec9				@ subs r1, r1, #3
	ldr	r2, [r2]
	blx	r2
	mov	r2, r0				@ r2 = position of the cut
	ldrb.w	r1, [r4, #0x48]
	movs	r0, #0
	lsls	r1, r1, #0x19			@ bit 6 to the sign bit
	bpl.n	.L080227b4
	ldr	r1, [r4, #0x28]			@ saved bytes in an allocated block
	b.n	.L080227c2
.L080227b4:
	add.w	r1, r4, #0x28			@ saved bytes inline at +0x28
	b.n	.L080227c2
.L080227ba:
	ldrb	r7, [r1, r0]
	.inst.n	0x1c40				@ adds r0, r0, #1
	strb	r7, [r6, r3]
	uxtb	r0, r0
.L080227c2:
	ldr	r6, [r5, #0x24]
	adds	r3, r2, r0
	ldrb	r7, [r6, r3]
	cmp	r7, #0
	bne.n	.L080227ba
	ldrb	r1, [r1, r0]
	add	r0, r2
	strb	r1, [r6, r0]
	mov	r0, r4
	bl	fn_08021f92
	subs	r0, r7, #1			@ r7 = 0, so r0 = 0xffffffff
	str	r0, [r5, #0x2c]
.L080227dc:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L080227e0:
	.word	0x2000050c

@ ----------------------------------------------------------------------------
@ fn_080227e4 - sets the display mode of a text object.
@ r0 = object (kept in r4), r1 = mode (kept in r5); no return value. Calls
@ fn_0801c688 with callbacks 0x080297ad and 0x080297b5, clears halfwords +0x44
@ and +0x46, sets bit 5 of byte +0x48 when the mode is 2, 3 or 4 else clears
@ it, restores the saved text with fn_08022780 when mode 1 is active and word
@ +0x2c is not -1, stores the mode in bits 0..2 of byte +0x48 and tail-calls
@ fn_080222b8.
@ ----------------------------------------------------------------------------
	.section .text.fn_080227e4,"ax",%progbits
	.p2align 2
	.global fn_080227e4
	.thumb_func
	.type fn_080227e4, %function
fn_080227e4:
	push	{r4, r5, r6, lr}
	mov	r5, r1
	mov	r4, r0
	ldr	r1, .L08022854
	bl	fn_0801c688			@ remove the horizontal record
	ldr	r1, .L08022858
	mov	r0, r4
	bl	fn_0801c688			@ remove the vertical record
	movs	r0, #0
	strh.w	r0, [r4, #0x44]
	strh.w	r0, [r4, #0x46]
	cmp	r5, #2
	beq.n	.L08022826
	cmp	r5, #3
	beq.n	.L08022826
	cmp	r5, #4
	beq.n	.L08022826
	ldrb.w	r0, [r4, #0x48]
	bic.w	r1, r0, #0x20			@ clear bit 5
	nop
.L08022818:
	and.w	r0, r1, #7
	strb.w	r1, [r4, #0x48]
	cmp	r0, #1
	beq.n	.L08022830
	b.n	.L0802283c
.L08022826:
	ldrb.w	r0, [r4, #0x48]
	orr.w	r1, r0, #0x20			@ set bit 5
	b.n	.L08022818
.L08022830:
	ldr	r0, [r4, #0x2c]
	.inst.n	0x1c40				@ adds r0, r0, #1
	beq.n	.L0802283c
	mov	r0, r4
	bl	fn_08022780
.L0802283c:
	ldrb.w	r0, [r4, #0x48]
	bfi	r0, r5, #0, #3			@ bits 2..0 = mode
	strb.w	r0, [r4, #0x48]
	mov	r0, r4
	pop.w	{r4, r5, r6, lr}
	b.w	fn_080222b8
	.short	0x0000				@ padding
.L08022854:
	.word	fn_080297ac			@ callback 0x080297ad (horizontal)
.L08022858:
	.word	fn_080297b4			@ callback 0x080297b5 (vertical)

@ ----------------------------------------------------------------------------
@ fn_0802285c - sets the text of an object from a string.
@ r0 = object (kept in r4), r1 = text pointer or 0 (kept in r5); no return
@ value. Calls fn_08025400 first. When r1 is 0 it is replaced by the current
@ text pointer. When the pointer equals the current text and bit 3 of byte
@ +0x48 is clear, resizes the text block to string_length+1 with fn_08022cb0
@ (zero result: return). Otherwise frees the old copy (fn_08022c68) when one
@ is owned (word +0x24 nonzero and bit 3 clear), allocates
@ string_length(text)+1 with fn_08022b50 (zero result: return), copies with
@ string_copy and clears bit 3. Then tail-calls fn_080222b8(object).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802285c,"ax",%progbits
	.p2align 2
	.global fn_0802285c
	.thumb_func
	.type fn_0802285c, %function
fn_0802285c:
	push	{r4, r5, r6, lr}
	mov	r5, r1
	mov	r4, r0
	bl	fn_08025400
	cbnz	r5, .L0802286a
	ldr	r5, [r4, #0x24]
.L0802286a:
	ldr	r0, [r4, #0x24]
	cmp	r0, r5
	bne.n	.L0802288c
	ldrb.w	r1, [r4, #0x48]
	lsls	r1, r1, #0x1c			@ bit 3 to the sign bit
	bmi.n	.L0802288c
	bl	string_length
	adds	r1, r0, #1
	ldr	r0, [r4, #0x24]
	bl	fn_08022cb0			@ resize the owned block
	str	r0, [r4, #0x24]
	cmp	r0, #0
	beq.n	.L080228cc
	b.n	.L080228c2
.L0802288c:
	cbz	r0, .L0802289e
	ldrb.w	r1, [r4, #0x48]
	lsls	r1, r1, #0x1c
	bmi.n	.L0802289e
	bl	fn_08022c68			@ free the old copy
	movs	r1, #0
	str	r1, [r4, #0x24]
.L0802289e:
	mov	r0, r5
	bl	string_length
	.inst.n	0x1c40				@ adds r0, r0, #1
	bl	fn_08022b50			@ allocate length + 1 bytes
	str	r0, [r4, #0x24]
	cmp	r0, #0
	beq.n	.L080228cc
	mov	r1, r5
	bl	string_copy
	ldrb.w	r0, [r4, #0x48]
	bic.w	r1, r0, #8			@ clear bit 3
	strb.w	r1, [r4, #0x48]
.L080228c2:
	mov	r0, r4
	pop.w	{r4, r5, r6, lr}
	b.w	fn_080222b8
.L080228cc:
	pop	{r4, r5, r6, pc}
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ fn_080228d0 - sets the text of an object from a format string.
@ r0 = object (kept in r4), r1 = format pointer, r2 and r3 = format arguments
@ (pushed together with r0 and r1; the format pointer is then at sp+0x14 and
@ the argument list starts at sp+0x18); no return value. Calls fn_08025400;
@ when the format pointer is nonzero frees an owned old text (word +0x24
@ nonzero and bit 3 of byte +0x48 clear) and clears word +0x24, builds a new
@ string with fn_08012cd2(format, argument list) into word +0x24 and clears
@ bit 3. Calls fn_080222b8(object), pops r4-r6 and returns by loading pc from
@ the stack while releasing the 16 pushed argument bytes.
@ ----------------------------------------------------------------------------
	.section .text.fn_080228d0,"ax",%progbits
	.p2align 2
	.global fn_080228d0
	.thumb_func
	.type fn_080228d0, %function
fn_080228d0:
	push	{r0, r1, r2, r3}
	push	{r4, r5, r6, lr}
	mov	r4, r0
	bl	fn_08025400
	ldr	r0, [sp, #0x14]			@ format pointer
	cbz	r0, .L08022916
	ldr	r0, [r4, #0x24]
	movs	r5, #0
	cbz	r0, .L080228f2
	ldrb.w	r1, [r4, #0x48]
	lsls	r1, r1, #0x1c
	bmi.n	.L080228f2
	bl	fn_08022c68			@ free the old text
	str	r5, [r4, #0x24]
.L080228f2:
	add	r1, sp, #0x18			@ argument list
	ldr	r0, [sp, #0x14]
	bl	fn_08012cd2
	str	r0, [r4, #0x24]
	ldrb.w	r0, [r4, #0x48]
	bic.w	r1, r0, #8			@ clear bit 3
	mov	r0, r4
	strb.w	r1, [r4, #0x48]
	nop
.L0802290c:
	bl	fn_080222b8
	pop	{r4, r5, r6}
	ldr.w	pc, [sp], #0x14
.L08022916:
	mov	r0, r4
	b.n	.L0802290c
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ fn_0802291c - appends a pair of words to a growing table.
@ r0 = first word (kept in r6), r1 = second word (kept in r7); returns the new
@ count in r0. Increments the counter at 0x20000468, resizes the table whose
@ pointer is at 0x200004d4 to count*8 bytes with fn_08022cb0, stores the two
@ words at the last 8 bytes of the table and returns the count.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802291c,"ax",%progbits
	.p2align 2
	.global fn_0802291c
	.thumb_func
	.type fn_0802291c, %function
fn_0802291c:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r4, .L08022948			@ r4 = 0x20000464 (counter at +4)
	mov	r6, r0
	ldr	r5, .L0802294c			@ r5 = address of the table pointer
	ldr	r0, [r4, #4]
	mov	r7, r1
	.inst.n	0x1c40				@ adds r0, r0, #1
	lsls	r1, r0, #3			@ new size = count * 8
	str	r0, [r4, #4]
	ldr	r0, [r5]
	bl	fn_08022cb0
	str	r0, [r5]
	ldr	r1, [r4, #4]
	add.w	r0, r0, r1, lsl #3
	strd	r6, r7, [r0, #-8]
	mov	r0, r1
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08022948:
	.word	0x20000464
.L0802294c:
	.word	0x200004d4

@ ----------------------------------------------------------------------------
@ fn_08022950 - resets the list fields of an object.
@ r1 = object (moved to r0); r0 is not read. Clears halfword +0x28, word +0x24
@ and byte +0x2a, then tail-calls fn_08023558(object, 2).
@ ----------------------------------------------------------------------------
	.section .text.fn_08022950,"ax",%progbits
	.p2align 2
	.global fn_08022950
	.thumb_func
	.type fn_08022950, %function
fn_08022950:
	mov	r0, r1
	movs	r1, #0
	strh	r1, [r0, #0x28]
	str	r1, [r0, #0x24]
	strb.w	r1, [r0, #0x2a]
	movs	r1, #2
	b.w	fn_08023558
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ fn_08022964 - creates an object from the class table at 0x0804fd58.
@ r0 = argument. Calls fn_080233c4(table 0x0804fd58, argument), then
@ fn_080234ac(object); returns the object created by fn_080233c4.
@ ----------------------------------------------------------------------------
	.section .text.fn_08022964,"ax",%progbits
	.p2align 2
	.global fn_08022964
	.thumb_func
	.type fn_08022964, %function
fn_08022964:
	push	{r4, lr}
	mov	r1, r0
	ldr	r0, .L08022978
	bl	fn_080233c4
	mov	r4, r0
	bl	fn_080234ac
	mov	r0, r4
	pop	{r4, pc}
.L08022978:
	.word	d_0804fd58

@ ----------------------------------------------------------------------------
@ fn_0802297c - message handler of the class at table 0x0804fd58: updates the
@ extent of a polyline object, or draws its segments.
@ r0 is not read (overwritten); r1 = message pointer (kept in r5); no return
@ value. Does nothing unless fn_08023d54(0x0804fd58, message) returns 1. Type
@ t = get_byte8_low7(message) (r6); target d = get_first_word(message) (r4).
@  t == 0x13: v = fn_08024a14(d, 0); p = get_word_at_0x10(message); when the
@    signed halfword at p is below v (signed compare at 0x08022a1c) stores v
@    there.
@  t == 0x2c: requires halfword d+0x28 (count n) != 0 and word d+0x24 (array)
@    != 0; scans n points of 4 bytes (signed halfwords x at +0, y at +2)
@    keeping the maximum x (r5) and maximum y (r6), both starting at 0; with
@    m = fn_08024a14(d, 0) stores x_max + m in halfword +0 and y_max + m in
@    halfword +2 of the structure at p = get_word_at_0x10(message).
@  t == 0x15: requires halfword d+0x28 != 0 and word d+0x24 != 0; fb =
@    get_word_10_if_byte_8_14_to_19(message); copies the rectangle at d+0x14
@    to sp+20 with fn_08023eb0; r6 = signed halfword (sp+20) -
@    fn_08024216(d); r5 = signed halfword (sp+22) - fn_08024224(d); r10 =
@    rect_height_plus_one(d); clears the 10-byte record at sp with
@    fn_0801e8d2 and fills it with fn_080250b6(d, 0, sp); for i = 0 while i <
@    count-1 (signed): point A = (x_i + r6, y_i + r5) at sp+12 and point B =
@    (x_i+1 + r6, y_i+1 + r5) at sp+16, where y is replaced by r10 - y + r5
@    when bit 0 of byte d+0x2a is set; calls fn_0801e8b8(fb, sp, sp+12,
@    sp+16); clears bit 2 of the record byte at sp+9 after each segment.
@  any other t returns without action.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802297c,"ax",%progbits
	.p2align 2
	.global fn_0802297c
	.thumb_func
	.type fn_0802297c, %function
fn_0802297c:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x1c
	mov	r5, r1				@ r5 = message pointer
	ldr	r0, .L08022af8
	bl	fn_08023d54
	cmp	r0, #1
	bne.n	.L08022a22
	mov	r0, r5
	bl	get_byte8_low7
	mov	r6, r0				@ r6 = message type
	mov	r0, r5
	bl	get_first_word
	mov	r4, r0				@ r4 = target object
	cmp	r6, #0x13
	beq.n	.L08022a0a
	mov.w	r8, #2
	cmp	r6, #0x2c
	beq.n	.L08022a28
	cmp	r6, #0x15
	bne.n	.L08022a22
	mov	r7, r0
	mov	r0, r5
	bl	get_word_10_if_byte_8_14_to_19
	mov	r11, r0				@ r11 = drawing target
	ldrh	r0, [r7, #0x28]
	mov	r4, r7
	cmp	r0, #0
	beq.n	.L08022a22
	ldr	r0, [r7, #0x24]
	cmp	r0, #0
	beq.n	.L08022a22
	add	r1, sp, #0x14
	mov	r0, r7
	bl	fn_08023eb0			@ rectangle copy at sp+20
	mov	r0, r4
	bl	fn_08024216
	ldrh.w	r1, [sp, #0x14]
	subs	r0, r1, r0
	sxth	r6, r0				@ r6 = x offset
	mov	r0, r4
	bl	fn_08024224
	ldrh.w	r1, [sp, #0x16]
	subs	r0, r1, r0
	sxth	r5, r0				@ r5 = y offset
	mov	r0, r4
	bl	rect_height_plus_one
	mov	r10, r0
	mov	r0, sp
	bl	fn_0801e8d2			@ clear the record at sp
	mov	r2, sp
	movs	r1, #0
	mov	r0, r4
	bl	fn_080250b6			@ fill the record at sp
	movs	r4, #0				@ r4 = segment index
	mov.w	r9, #6
	b.n	.L08022ada
.L08022a0a:
	movs	r1, #0
	bl	fn_08024a14
	mov	r4, r0
	mov	r0, r5
	bl	get_word_at_0x10
	ldrsh.w	r1, [r0]
	cmp	r1, r4
	bge.n	.L08022a22
	strh	r4, [r0]
.L08022a22:
	add	sp, #0x1c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08022a28:
	ldrh	r0, [r4, #0x28]
	cmp	r0, #0
	beq.n	.L08022a22
	ldr	r0, [r4, #0x24]
	cmp	r0, #0
	beq.n	.L08022a22
	mov	r0, r5
	bl	get_word_at_0x10
	movs	r5, #0				@ r5 = maximum x
	mov	r7, r0
	mov	r6, r5				@ r6 = maximum y
	mov	r0, r5
	ldrh	r2, [r4, #0x28]			@ r2 = point count
	mov	r12, r8				@ r12 = 2 (offset of y)
	b.n	.L08022a64
.L08022a48:
	ldr	r3, [r4, #0x24]
	ldrsh.w	r1, [r3, r0, lsl #2]
	cmp	r1, r5
	ble.n	.L08022a54
	mov	r5, r1
.L08022a54:
	add.w	r1, r12, r0, lsl #2
	ldrsh	r1, [r3, r1]
	cmp	r1, r6
	ble.n	.L08022a60
	mov	r6, r1
.L08022a60:
	.inst.n	0x1c40				@ adds r0, r0, #1
	uxth	r0, r0
.L08022a64:
	cmp	r2, r0
	bhi.n	.L08022a48
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024a14
	adds	r1, r5, r0
	add	r0, r6
	strh	r1, [r7]			@ x_max + m
	strh	r0, [r7, #2]			@ y_max + m
	b.n	.L08022a22
.L08022a7a:
	ldr	r0, [r7, #0x24]
	ldrh.w	r1, [r0, r4, lsl #2]
	add	r1, r6
	strh.w	r1, [sp, #0xc]			@ point A x
	movs	r1, #4
	add.w	r1, r1, r4, lsl #2
	ldrh	r1, [r0, r1]
	add	r1, r6
	strh.w	r1, [sp, #0x10]			@ point B x
	ldrb.w	r1, [r7, #0x2a]
	lsls	r1, r1, #0x1f			@ bit 0 to the sign bit
	add.w	r1, r8, r4, lsl #2
	beq.n	.L08022ae4
	ldrh	r1, [r0, r1]
	sub.w	r0, r10, r1
	add	r0, r5
	strh.w	r0, [sp, #0xe]			@ point A y (mirrored)
	ldr	r1, [r7, #0x24]
	add.w	r0, r9, r4, lsl #2
	ldrh	r1, [r1, r0]
	sub.w	r0, r10, r1
.L08022ab8:
	add	r0, r5
	strh.w	r0, [sp, #0x12]			@ point B y
	add	r3, sp, #0x10
	add	r2, sp, #0xc
	mov	r1, sp
	mov	r0, r11
	bl	fn_0801e8b8			@ draw the segment
	ldrb.w	r0, [sp, #9]
	.inst.n	0x1c64				@ adds r4, r4, #1
	bic.w	r0, r0, #4
	strb.w	r0, [sp, #9]
	uxth	r4, r4
.L08022ada:
	ldrh	r0, [r7, #0x28]
	.inst.n	0x1e40				@ subs r0, r0, #1
	cmp	r0, r4
	bgt.n	.L08022a7a
	b.n	.L08022a22
.L08022ae4:
	ldrh	r0, [r0, r1]
	add	r0, r5
	strh.w	r0, [sp, #0xe]			@ point A y
	ldr	r1, [r7, #0x24]
	add.w	r0, r9, r4, lsl #2
	ldrh	r0, [r1, r0]
	b.n	.L08022ab8
	.short	0x0000				@ padding
.L08022af8:
	.word	d_0804fd58
