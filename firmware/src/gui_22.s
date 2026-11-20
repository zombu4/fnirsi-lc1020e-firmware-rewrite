@ gui_22.s - GUI object helpers: list walks, rectangle layout, property getters (0x08023d54..0x08024c40)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08023d54 - r0 = start node or 0, r1 = context pointer.
@ When r0 is 0 starts at the word at context+4. Follows the link word at
@ offset 0 of each node, skipping nodes whose word at node+0x10 is zero.
@ When a node with a nonzero word at node+0x10 is found: stores 0 at
@ context+0xc and calls the function pointer at node+0x10 with
@ (node, context); returns 1 when the byte at context+0x18 has bit 0 clear,
@ else 0. Returns 1 when the chain ends (link word zero) without a call.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023d54,"ax",%progbits
	.p2align 2
	.global fn_08023d54
	.thumb_func
	.type fn_08023d54, %function
fn_08023d54:
	push	{r4, lr}
	mov	r4, r1
	cbnz	r0, .L08023d5c
	ldr	r0, [r4, #4]		@ start at the word at context+4
.L08023d5c:
	ldr	r0, [r0]		@ follow the link word of the node
	cbz	r0, .L08023d7c
	ldr	r1, [r0, #0x10]
	cmp	r1, #0
	beq.n	.L08023d5c		@ no handler: next node
	movs	r1, #0
	str	r1, [r4, #0xc]
	ldr	r2, [r0, #0x10]
	mov	r1, r4
	blx	r2			@ handler(node, context)
	ldrb	r1, [r4, #0x18]
	movs	r0, #1
	lsls	r1, r1, #0x1f
	beq.n	.L08023d7a
	movs	r0, #0
.L08023d7a:
	pop	{r4, pc}
.L08023d7c:
	movs	r0, #1			@ chain ended without a handler call
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08023d80 - r0 = object, r1 = signed index; returns the element or 0.
@ Reads the list pointer at object+8. Returns 0 when it is zero or when the
@ index (a negative index gets the count at list+4 added) is outside
@ 0..count-1. Otherwise returns the word at [list]+index*4.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023d80,"ax",%progbits
	.p2align 2
	.global fn_08023d80
	.thumb_func
	.type fn_08023d80, %function
fn_08023d80:
	ldr	r0, [r0, #8]
	cmp	r0, #0
	beq.n	.L08023d9a
	cmp	r1, #0
	bge.n	.L08023d90
	ldr	r2, [r0, #4]		@ negative index: add the count
	adds	r1, r2, r1
	bmi.n	.L08023d98
.L08023d90:
	ldr	r3, [r0, #4]		@ count
	mov	r2, r1
	cmp	r3, r1
	bhi.n	.L08023d9c
.L08023d98:
	movs	r0, #0
.L08023d9a:
	bx	lr
.L08023d9c:
	ldr	r0, [r0]
	ldr.w	r0, [r0, r2, lsl #2]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08023da4 - r0 = object; returns the word at [object+8]+4, or 0 when the
@ word at object+8 is zero.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023da4,"ax",%progbits
	.global fn_08023da4
	.thumb_func
	.type fn_08023da4, %function
fn_08023da4:
	ldr	r0, [r0, #8]
	cmp	r0, #0
	beq.n	.L08023dac
	ldr	r0, [r0, #4]
.L08023dac:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08023dae - r0 = object, r1 = pointer to four halfwords (x1, y1, x2, y2);
@ no return value. Copies the rectangle at object+0x14 into r1 with
@ copy_rect_0801cfa0. When the pointer at object+8 is nonzero, shrinks it by
@ the halfword at [object+8]+0x14: x1 and y1 decrease, x2 and y2 increase.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023dae,"ax",%progbits
	.global fn_08023dae
	.thumb_func
	.type fn_08023dae, %function
fn_08023dae:
	push	{r4, r5, r6, lr}
	mov	r4, r1
	mov	r5, r0
	add.w	r1, r0, #0x14
	mov	r0, r4
	bl	copy_rect_0801cfa0
	ldr	r0, [r5, #8]
	cmp	r0, #0
	beq.n	.L08023dea
	ldrh	r1, [r4]
	ldrh	r0, [r0, #0x14]
	subs	r0, r1, r0
	strh	r0, [r4]		@ x1 -= value
	ldr	r1, [r5, #8]
	ldrh	r0, [r4, #4]
	ldrh	r1, [r1, #0x14]
	add	r0, r1
	strh	r0, [r4, #4]		@ x2 += value
	ldr	r1, [r5, #8]
	ldrh	r0, [r4, #2]
	ldrh	r1, [r1, #0x14]
	subs	r0, r0, r1
	strh	r0, [r4, #2]		@ y1 -= value
	ldr	r1, [r5, #8]
	ldrh	r0, [r4, #6]
	ldrh	r1, [r1, #0x14]
	add	r0, r1
	strh	r0, [r4, #6]		@ y2 += value
.L08023dea:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08023dec - r0 = object, r1 = pointer to four halfwords; no return value.
@ Reads fn_08024984 (key 0), copies the object rectangle with fn_08023eb0,
@ changes it with rect_grow by the negated value, then adds fn_08024ae0 to
@ x1, subtracts fn_08024b1c from x2, adds fn_08024b70 to y1 and subtracts
@ fn_08024a80 from y2 (all called with key 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_08023dec,"ax",%progbits
	.p2align 2
	.global fn_08023dec
	.thumb_func
	.type fn_08023dec, %function
fn_08023dec:
	push	{r4, r5, r6, lr}
	mov	r4, r1
	mov	r5, r0
	movs	r1, #0
	bl	fn_08024984
	mov	r6, r0
	mov	r1, r4
	mov	r0, r5
	bl	fn_08023eb0
	rsbs	r0, r6, #0
	sxth	r2, r0
	mov	r1, r2
	mov	r0, r4
	bl	rect_grow
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024ae0
	ldrh	r1, [r4]
	add	r0, r1
	strh	r0, [r4]		@ x1 += fn_08024ae0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024b1c
	ldrh	r1, [r4, #4]
	subs	r0, r1, r0
	strh	r0, [r4, #4]		@ x2 -= fn_08024b1c
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024b70
	ldrh	r1, [r4, #2]
	add	r0, r1
	strh	r0, [r4, #2]		@ y1 += fn_08024b70
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024a80
	ldrh	r1, [r4, #6]
	subs	r0, r1, r0
	strh	r0, [r4, #6]		@ y2 -= fn_08024a80
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08023e48 - r0 = object; returns a signed 16-bit value.
@ rect_height_plus_one(object) minus fn_08024b70 minus fn_08024a80 minus
@ twice fn_08024984 (the last one is taken from r2 as left by the call).
@ ----------------------------------------------------------------------------
	.section .text.fn_08023e48,"ax",%progbits
	.p2align 2
	.global fn_08023e48
	.thumb_func
	.type fn_08023e48, %function
fn_08023e48:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	movs	r1, #0
	bl	fn_08024b70
	mov	r5, r0
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024a80
	mov	r6, r0
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024984
	mov	r2, r0
	mov	r0, r4
	bl	rect_height_plus_one
	subs	r0, r0, r5
	subs	r0, r0, r6
	rsbs	r1, r2, #0
	add.w	r0, r0, r1, lsl #1
	sxth	r0, r0
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08023e7c - r0 = object; returns a signed 16-bit value.
@ rect_width_plus_one(object) minus fn_08024ae0 minus fn_08024b1c minus
@ twice fn_08024984 (the last one is taken from r2 as left by the call).
@ ----------------------------------------------------------------------------
	.section .text.fn_08023e7c,"ax",%progbits
	.p2align 2
	.global fn_08023e7c
	.thumb_func
	.type fn_08023e7c, %function
fn_08023e7c:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	movs	r1, #0
	bl	fn_08024ae0
	mov	r5, r0
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024b1c
	mov	r6, r0
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024984
	mov	r2, r0
	mov	r0, r4
	bl	rect_width_plus_one
	subs	r0, r0, r5
	subs	r0, r0, r6
	rsbs	r1, r2, #0
	add.w	r0, r0, r1, lsl #1
	sxth	r0, r0
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08023eb0 - r0 = object, r1 = destination rectangle; no return value.
@ Tail-calls copy_rect_0801cfa0 with (r1, object+0x14), copying the
@ rectangle at object+0x14.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023eb0,"ax",%progbits
	.p2align 2
	.global fn_08023eb0
	.thumb_func
	.type fn_08023eb0, %function
fn_08023eb0:
	mov	r2, r1
	add.w	r1, r0, #0x14
	mov	r0, r2
	b.w	copy_rect_0801cfa0

@ ----------------------------------------------------------------------------
@ fn_08023ebc - r0 = object; returns the node pointer found or 0.
@ When the word at object+4 is nonzero replaces the object by fn_08023fac.
@ Walks the list starting at get_word_4_or_zero for the list head at
@ 0x2000805c with read_word_at_base_plus_offset_4 as next; returns the first
@ node for which one of the words in the array at node+0xc (count at
@ node+0x24) equals the object.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023ebc,"ax",%progbits
	.p2align 2
	.global fn_08023ebc
	.thumb_func
	.type fn_08023ebc, %function
fn_08023ebc:
	push	{r4, lr}
	ldr	r1, [r0, #4]
	cbz	r1, .L08023ec6
	bl	fn_08023fac
.L08023ec6:
	mov	r4, r0
	ldr	r0, .L08023ef4
	bl	get_word_4_or_zero
	b.n	.L08023eee
.L08023ed0:
	movs	r1, #0
	ldr	r2, [r0, #0x24]		@ count
	b.n	.L08023ee2
.L08023ed6:
	ldr	r3, [r0, #0xc]
	ldr.w	r3, [r3, r1, lsl #2]
	cmp	r3, r4
	beq.n	.L08023ef2
	.inst.n	0x1c49		@ adds r1, r1, #1
.L08023ee2:
	cmp	r2, r1
	bhi.n	.L08023ed6
	mov	r1, r0
	ldr	r0, .L08023ef4
	bl	read_word_at_base_plus_offset_4
.L08023eee:
	cmp	r0, #0
	bne.n	.L08023ed0
.L08023ef2:
	pop	{r4, pc}
.L08023ef4:
	.word	0x2000805c

@ ----------------------------------------------------------------------------
@ fn_08023ef8 - r0 = object, r1 = index; returns a pointer or 0.
@ Returns 0 when the word at object+8 is zero or when index >= (byte at
@ [object+8]+0x1a & 0x3f). Otherwise returns [[object+8]+0xc] + index*0xc.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023ef8,"ax",%progbits
	.p2align 2
	.global fn_08023ef8
	.thumb_func
	.type fn_08023ef8, %function
fn_08023ef8:
	ldr	r0, [r0, #8]
	cmp	r0, #0
	beq.n	.L08023f0a
	ldrb	r2, [r0, #0x1a]
	and.w	r2, r2, #0x3f
	cmp	r2, r1
	bhi.n	.L08023f0c
	movs	r0, #0
.L08023f0a:
	bx	lr
.L08023f0c:
	ldr	r0, [r0, #0xc]
	add.w	r1, r1, r1, lsl #1	@ index * 3
	add.w	r0, r0, r1, lsl #2	@ + index * 12
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08023f18 - r0 = object; returns the word at [object+8]+8, or 0 when the
@ word at object+8 is zero.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023f18,"ax",%progbits
	.global fn_08023f18
	.thumb_func
	.type fn_08023f18, %function
fn_08023f18:
	ldr	r0, [r0, #8]
	cmp	r0, #0
	beq.n	.L08023f20
	ldr	r0, [r0, #8]
.L08023f20:
	bx	lr

@ ----------------------------------------------------------------------------
@ rect_height_plus_one - r0 = object; returns the signed 16-bit value
@ halfword(object+0x1a) - halfword(object+0x16) + 1.
@ ----------------------------------------------------------------------------
	.section .text.rect_height_plus_one,"ax",%progbits
	.global rect_height_plus_one
	.thumb_func
	.type rect_height_plus_one, %function
rect_height_plus_one:
	ldrh	r1, [r0, #0x1a]
	ldrh	r0, [r0, #0x16]
	subs	r0, r1, r0
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r0, r0
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08023f2e - r0 = object; returns its index in the parent's list,
@ 0xffffffff when absent, 0 when there is no parent.
@ Gets the parent with fn_08023fa4; scans indices below fn_08023da4 of the
@ parent comparing fn_08023d80 with the object.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023f2e,"ax",%progbits
	.global fn_08023f2e
	.thumb_func
	.type fn_08023f2e, %function
fn_08023f2e:
	push	{r4, r5, r6, lr}
	mov	r6, r0
	bl	fn_08023fa4
	movs	r5, r0
	beq.n	.L08023f3e
	movs	r4, #0
	b.n	.L08023f54
.L08023f3e:
	movs	r0, #0			@ no parent
	pop	{r4, r5, r6, pc}
.L08023f42:
	mov	r1, r4
	mov	r0, r5
	bl	fn_08023d80
	cmp	r0, r6
	bne.n	.L08023f52
	mov	r0, r4
	pop	{r4, r5, r6, pc}
.L08023f52:
	.inst.n	0x1c64		@ adds r4, r4, #1
.L08023f54:
	mov	r0, r5
	bl	fn_08023da4
	cmp	r0, r4
	bhi.n	.L08023f42
	mov.w	r0, #0xffffffff		@ not found
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08023f64 - r0 = object, r1 and r2 passed on, r3 = 24-bit entry id;
@ returns 0 or the result of the lookup.
@ Scans the 8-byte entries at [object+0xc], count (halfword at object+0x22
@ bits 3..8, i.e. (value & 0x1ff) >> 3), for an entry whose second word has
@ bit 24 set and low 24 bits equal to r3. Tail-calls fn_08026dc4 with the
@ first word of that entry (r1, r2 unchanged); returns 0 when none matches.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023f64,"ax",%progbits
	.p2align 2
	.global fn_08023f64
	.thumb_func
	.type fn_08023f64, %function
fn_08023f64:
	push	{r4, r5, r6, r7}
	ldrh	r6, [r0, #0x22]
	movs	r4, #0
	movs	r5, #4
	ubfx	r6, r6, #3, #6
	b.n	.L08023f9a
	nop				@ padding
.L08023f74:
	ldr	r7, [r0, #0xc]
	add.w	r12, r5, r4, lsl #3
	ldr.w	r7, [r7, r12]		@ second word of entry r4
	lsls.w	r12, r7, #7
	bpl.n	.L08023f98		@ bit 24 clear
	bic.w	r7, r7, #0xff000000
	cmp	r7, r3
	bne.n	.L08023f98
	ldr	r0, [r0, #0xc]
	ldr.w	r0, [r0, r4, lsl #3]	@ first word of the entry
	pop	{r4, r5, r6, r7}
	b.w	fn_08026dc4
.L08023f98:
	.inst.n	0x1c64		@ adds r4, r4, #1
.L08023f9a:
	cmp	r6, r4
	bhi.n	.L08023f74
	pop	{r4, r5, r6, r7}
	movs	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08023fa4 - r0 = object; returns the word at object+4 (parent link), or 0
@ when r0 is 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023fa4,"ax",%progbits
	.p2align 2
	.global fn_08023fa4
	.thumb_func
	.type fn_08023fa4, %function
fn_08023fa4:
	cmp	r0, #0
	beq.n	.L08023faa
	ldr	r0, [r0, #4]
.L08023faa:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08023fac - r0 = object; returns the last object reached by repeatedly
@ following fn_08023fa4 (word at +4) until it returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023fac,"ax",%progbits
	.p2align 2
	.global fn_08023fac
	.thumb_func
	.type fn_08023fac, %function
fn_08023fac:
	push	{lr}
.L08023fae:
	mov	r1, r0
	bl	fn_08023fa4
	cmp	r0, #0
	bne.n	.L08023fae
	mov	r0, r1
	pop	{pc}

@ ----------------------------------------------------------------------------
@ fn_08023fbc - r0 = object; returns a signed 16-bit value.
@ Takes the maximum of halfword(child+0x1a) over all children (fn_08023da4
@ count, list at [[object+8]]) whose flag test any_flag_bit_set with 0x40001
@ is zero, starting at -0x1fff (0xffffe001), and converts it (when it is not
@ the start value) as maximum - (halfword(object+0x1a) - fn_08024a8c -
@ fn_08024990). fn_08024b7c is called but only used in the alternative.
@ Alternative value: fn_08024890 minus (rect_height_plus_one minus the three
@ offsets) minus fn_08024224. Returns the larger of the two.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023fbc,"ax",%progbits
	.p2align 2
	.global fn_08023fbc
	.thumb_func
	.type fn_08023fbc, %function
fn_08023fbc:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr.w	r8, .L08024058		@ -0x1fff, the "none" value
	mov	r6, r0
	mov	r4, r8
	bl	fn_08023da4		@ child count
	mov	r7, r0
	movs	r5, #0
	ldr.w	r10, .L0802405c		@ flag mask 0x00040001
	b.n	.L08023ff4
.L08023fd6:
	ldr	r0, [r6, #8]
	mov	r1, r10
	ldr	r0, [r0]
	ldr.w	r0, [r0, r5, lsl #2]	@ child
	mov	r9, r0
	bl	any_flag_bit_set
	cbnz	r0, .L08023ff2
	ldrsh.w	r0, [r9, #0x1a]
	cmp	r0, r4
	blt.n	.L08023ff2
	mov	r4, r0			@ new maximum
.L08023ff2:
	.inst.n	0x1c6d		@ adds r5, r5, #1
.L08023ff4:
	cmp	r5, r7
	bcc.n	.L08023fd6
	movs	r1, #0
	mov	r0, r6
	bl	fn_08024b7c
	mov	r9, r0
	movs	r1, #0
	mov	r0, r6
	bl	fn_08024a8c
	mov	r7, r0
	movs	r1, #0
	mov	r0, r6
	bl	fn_08024990
	mov	r5, r0
	cmp	r4, r8
	beq.n	.L08024024
	ldrh	r0, [r6, #0x1a]
	subs	r0, r0, r7
	subs	r0, r0, r5
	subs	r0, r4, r0
	sxth	r4, r0
.L08024024:
	mov	r0, r6
	bl	fn_08024890
	mov	r8, r0
	mov	r0, r6
	bl	rect_height_plus_one
	sub.w	r0, r0, r9
	subs	r0, r0, r7
	rsbs	r1, r5, #0
	add.w	r1, r0, r1, lsl #1
	sub.w	r1, r8, r1
	mov	r0, r6
	bl	fn_08024224
	subs	r0, r1, r0
	sxth	r0, r0
	cmp	r4, r0
	ble.n	.L08024052
	mov	r0, r4
.L08024052:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
	.short	0x0000		@ padding
.L08024058:
	.word	0xffffe001
.L0802405c:
	.word	0x00040001

@ ----------------------------------------------------------------------------
@ fn_08024060 - r0 = object; returns 0xf when the word at object+8 is zero,
@ else the byte at [object+8]+0x19 masked with 0xf.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024060,"ax",%progbits
	.p2align 2
	.global fn_08024060
	.thumb_func
	.type fn_08024060, %function
fn_08024060:
	ldr	r0, [r0, #8]
	cbz	r0, .L0802406c
	ldrb	r0, [r0, #0x19]
	and.w	r0, r0, #0xf
	bx	lr
.L0802406c:
	movs	r0, #0xf
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08024070 - r0 = object; returns a signed 16-bit value.
@ When fn_08024912 (key 0) is 1: takes the minimum of halfword(child+0x14)
@ over children whose any_flag_bit_set test with 0x40001 is zero (start
@ 0x1fff), converts it (when it is not 0x1fff) to fn_08024aec +
@ fn_08024990 + halfword(object+0x14) - minimum, and uses the literal word
@ 0xffffe001 when no child counted. fn_08024b28 is called and kept in [sp]
@ for the alternative: fn_080248ac minus the width terms
@ (rect_width_plus_one) plus fn_08024216; returns the larger of the two.
@ Otherwise returns minus halfword([object+8]+0x10), or 0 when object+8 is
@ zero.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024070,"ax",%progbits
	.p2align 2
	.global fn_08024070
	.thumb_func
	.type fn_08024070, %function
fn_08024070:
	push.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r6, r0
	movs	r1, #0
	bl	fn_08024912
	cmp	r0, #1
	beq.n	.L08024090
	ldr	r0, [r6, #8]
	cmp	r0, #0
	beq.n	.L0802408c
	ldrh	r0, [r0, #0x10]
	rsbs	r0, r0, #0
	sxth	r0, r0
.L0802408c:
	pop.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08024090:
	movs	r1, #0
	mov	r0, r6
	bl	fn_08024b28
	str	r0, [sp]
	movs	r1, #0
	mov	r0, r6
	bl	fn_08024aec
	mov	r9, r0
	movs	r1, #0
	mov	r0, r6
	bl	fn_08024990
	mov	r8, r0
	movw	r10, #0x1fff		@ start value of the minimum
	mov	r4, r10
	mov	r0, r6
	bl	fn_08023da4		@ child count
	mov	r7, r0
	movs	r5, #0
	b.n	.L080240de
.L080240c0:
	ldr	r0, [r6, #8]
	ldr	r1, .L08024128		@ flag mask 0x00040001
	ldr	r0, [r0]
	ldr.w	r0, [r0, r5, lsl #2]	@ child
	mov	r11, r0
	bl	any_flag_bit_set
	cbnz	r0, .L080240dc
	ldrsh.w	r0, [r11, #0x14]
	cmp	r0, r4
	bgt.n	.L080240dc
	mov	r4, r0			@ new minimum
.L080240dc:
	.inst.n	0x1c6d		@ adds r5, r5, #1
.L080240de:
	cmp	r5, r7
	bcc.n	.L080240c0
	cmp	r4, r10
	beq.n	.L080240f4
	ldrh	r2, [r6, #0x14]
	add.w	r0, r9, r8
	add	r0, r2
	subs	r0, r0, r4
	sxth	r4, r0
	b.n	.L080240f6
.L080240f4:
	ldr	r4, .L0802412c		@ -0x1fff when no child counted
.L080240f6:
	mov	r0, r6
	bl	fn_080248ac
	mov	r5, r0
	mov	r0, r6
	bl	rect_width_plus_one
	ldr	r1, [sp]
	subs	r1, r0, r1
	sub.w	r1, r1, r9
	rsb.w	r0, r8, #0
	add.w	r0, r1, r0, lsl #1
	subs	r1, r5, r0
	mov	r0, r6
	bl	fn_08024216
	add	r0, r1
	sxth	r0, r0
	cmp	r4, r0
	ble.n	.L0802408c
	mov	r0, r4
	b.n	.L0802408c
.L08024128:
	.word	0x00040001
.L0802412c:
	.word	0xffffe001

@ ----------------------------------------------------------------------------
@ fn_08024130 - r0 = object; returns a signed 16-bit value.
@ When fn_08024912 (key 0) is 1 returns halfword([object+8]+0x10) (0 when
@ object+8 is zero). Otherwise takes the maximum of halfword(child+0x18)
@ over children whose any_flag_bit_set test with 0x40001 is zero (start
@ -0x1fff), adjusts it with fn_08024b28, fn_08024990 and halfword
@ (object+0x18), computes fn_080248ac minus the width terms
@ (rect_width_plus_one) minus fn_08024216 and returns the larger of the two.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024130,"ax",%progbits
	.p2align 2
	.global fn_08024130
	.thumb_func
	.type fn_08024130, %function
fn_08024130:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r6, r0
	movs	r1, #0
	bl	fn_08024912
	cmp	r0, #1
	beq.n	.L08024156
	ldr.w	r8, .L080241e4		@ -0x1fff, the "none" value
	mov	r0, r6
	mov	r4, r8
	bl	fn_08023da4		@ child count
	mov	r7, r0
	movs	r5, #0
	ldr.w	r10, .L080241e8		@ flag mask 0x00040001
	b.n	.L08024182
.L08024156:
	ldr	r0, [r6, #8]
	cmp	r0, #0
	beq.n	.L08024160
	ldrsh.w	r0, [r0, #0x10]
.L08024160:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L08024164:
	ldr	r0, [r6, #8]
	mov	r1, r10
	ldr	r0, [r0]
	ldr.w	r0, [r0, r5, lsl #2]	@ child
	mov	r9, r0
	bl	any_flag_bit_set
	cbnz	r0, .L08024180
	ldrsh.w	r0, [r9, #0x18]
	cmp	r0, r4
	blt.n	.L08024180
	mov	r4, r0			@ new maximum
.L08024180:
	.inst.n	0x1c6d		@ adds r5, r5, #1
.L08024182:
	cmp	r5, r7
	bcc.n	.L08024164
	movs	r1, #0
	mov	r0, r6
	bl	fn_08024b28
	mov	r7, r0
	movs	r1, #0
	mov	r0, r6
	bl	fn_08024aec
	mov	r9, r0
	movs	r1, #0
	mov	r0, r6
	bl	fn_08024990
	mov	r5, r0
	cmp	r4, r8
	beq.n	.L080241b2
	ldrh	r0, [r6, #0x18]
	subs	r0, r0, r7
	subs	r0, r0, r5
	subs	r0, r4, r0
	sxth	r4, r0
.L080241b2:
	mov	r0, r6
	bl	fn_080248ac
	mov	r8, r0
	mov	r0, r6
	bl	rect_width_plus_one
	subs	r1, r0, r7
	sub.w	r0, r1, r9
	rsbs	r1, r5, #0
	add.w	r1, r0, r1, lsl #1
	sub.w	r1, r8, r1
	mov	r0, r6
	bl	fn_08024216
	subs	r0, r1, r0
	sxth	r0, r0
	cmp	r4, r0
	ble.n	.L08024160
	mov	r0, r4
	b.n	.L08024160
	.short	0x0000		@ padding
.L080241e4:
	.word	0xffffe001
.L080241e8:
	.word	0x00040001

@ ----------------------------------------------------------------------------
@ fn_080241ec - r0 = object; returns (byte([object+8]+0x18) & 0xf) >> 2, or
@ 0 when object+8 is zero.
@ ----------------------------------------------------------------------------
	.section .text.fn_080241ec,"ax",%progbits
	.global fn_080241ec
	.thumb_func
	.type fn_080241ec, %function
fn_080241ec:
	ldr	r0, [r0, #8]
	cmp	r0, #0
	beq.n	.L080241f8
	ldrb	r0, [r0, #0x18]
	ubfx	r0, r0, #2, #2
.L080241f8:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_080241fa - r0 = object; returns (byte([object+8]+0x18) & 0x3f) >> 4, or
@ 0 when object+8 is zero.
@ ----------------------------------------------------------------------------
	.section .text.fn_080241fa,"ax",%progbits
	.global fn_080241fa
	.thumb_func
	.type fn_080241fa, %function
fn_080241fa:
	ldr	r0, [r0, #8]
	cmp	r0, #0
	beq.n	.L08024206
	ldrb	r0, [r0, #0x18]
	ubfx	r0, r0, #4, #2
.L08024206:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08024208 - r0 = object; returns minus the signed halfword at
@ [object+8]+0x12, or 0 when object+8 is zero.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024208,"ax",%progbits
	.global fn_08024208
	.thumb_func
	.type fn_08024208, %function
fn_08024208:
	ldr	r0, [r0, #8]
	cmp	r0, #0
	beq.n	.L08024214
	ldrh	r0, [r0, #0x12]
	rsbs	r0, r0, #0
	sxth	r0, r0
.L08024214:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08024216 - r0 = object; returns minus the signed halfword at
@ [object+8]+0x10, or 0 when object+8 is zero.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024216,"ax",%progbits
	.global fn_08024216
	.thumb_func
	.type fn_08024216, %function
fn_08024216:
	ldr	r0, [r0, #8]
	cmp	r0, #0
	beq.n	.L08024222
	ldrh	r0, [r0, #0x10]
	rsbs	r0, r0, #0
	sxth	r0, r0
.L08024222:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08024224 - r0 = object; returns minus the signed halfword at
@ [object+8]+0x12, or 0 when object+8 is zero.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024224,"ax",%progbits
	.global fn_08024224
	.thumb_func
	.type fn_08024224, %function
fn_08024224:
	ldr	r0, [r0, #8]
	cmp	r0, #0
	beq.n	.L08024230
	ldrh	r0, [r0, #0x12]
	rsbs	r0, r0, #0
	sxth	r0, r0
.L08024230:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08024232 - r0 = object (r5), r1 = output rectangle A (r4), r2 = output
@ rectangle B (r6); r3 not read; no return value. Rectangles are four
@ halfwords (x0 +0, y0 +2, x1 +4, y1 +6). The function lays out two bars
@ (B on the vertical, A on the horizontal side of the object rectangle) from
@ the object rectangle at object+0x14..0x1a and offsets read from the object.
@
@ rect_set(rect, 0, 0, 0xffffffff, [sp]=0xffffffff) is applied to A and B
@ first. Returns (shared epilogue .L08024298: add sp,#0x44 and pop) when
@ all_flag_bits_set(obj, 0x10) is zero, or r7 = fn_0802487e(obj) is 0
@ (fn_0802487e returns byte [[obj+8]+0x18] AND 3, or 3 when [obj+8] is 0);
@ r8 = fn_08021d90(0); when r7 = 2 the list is walked (r8 = fn_08021d90(r8)
@ while fn_08021dee(r8) differs from obj) and the function returns when r8
@ reaches 0.
@ Words: [sp+0x14] = fn_08024208(obj), [sp+0x30] = fn_08023fbc(obj),
@ [sp+0x28] = fn_08024070(obj), [sp+0x20] = fn_08024130(obj),
@ r9 = fn_08024060(obj).
@ Flag H ([sp+0x00]) when r9 AND 0xc is nonzero and: r7 = 1, or r7 = 3 with
@ [sp+0x14] > 0 or [sp+0x30] > 0 (signed), or r7 = 2 with fn_08021dd0(r8) = 0xc.
@ Flag V ([sp+0x24]) when r9 AND 3 is nonzero and: r7 = 1, or r7 = 3 with
@ [sp+0x28] > 0 or [sp+0x20] > 0, or r7 = 2 with fn_08021dd0(r8) = 3.
@ Returns when H and V are both 0.
@ r7 = 0x10000; W ([sp+0x38]) = 1 when fn_08024912(obj, 0x10000) = 1 else 0;
@ [sp+0x18] = fn_08024b7c(obj, 0x10000); [sp+0x3c] = fn_08024a8c;
@ r8 = fn_08024aec; r9 = fn_08024b28; r11 = sxth(fn_08024bac(obj, 0x10000,
@ 1)); [sp+0x10] = rect_height_plus_one(obj); [sp+0x0c] =
@ rect_width_plus_one(obj); r10 = H ? r11 : 0; [sp+0x40] = V ? r11 : 0;
@ continues only when byte fn_08024bac(obj, 0x10000, 0x21) >= 2 or byte
@ fn_08024bac(obj, 0x10000, 0x31) >= 2; [sp+0x2c] = sxth([sp+0x30] +
@ [sp+0x14] + [sp+0x10]); r7 = 0xa0.
@ Rectangle B (r6) when H and [sp+0x2c] are nonzero: y0 = halfword obj+0x16,
@ y1 = halfword obj+0x1a; when W: x0 = halfword obj+0x14 + r8, x1 = x0 + r11
@ - 1; else x1 = halfword obj+0x18 - r9, x0 = x1 - r11 + 1;
@ L = [sp+0x10] - [sp+0x18] - [sp+0x3c] - [sp+0x40]; len = sxth(L *
@ [sp+0x10] / [sp+0x2c]); min length m = (0x50 + 10 * fn_0801dcd8(0) >=
@ 0x140) ? (0x50 + 10 * fn_0801dcd8(0)) / 0xa0 : 1, evaluated again at each
@ use; size = max(m, len) as sxth; when sxth([sp+0x2c] - [sp+0x10]) <= 0:
@ y0 = halfword obj+0x16 + [sp+0x18], y1 = halfword obj+0x1a - [sp+0x3c] -
@ [sp+0x40] - 1; else offset = (L - size) - (smulbb(L - size, [sp+0x30]) /
@ ([sp+0x2c] - [sp+0x10])), y0 = sxth(offset + [sp+0x18] + halfword
@ obj+0x16), y1 = y0 + size - 1; then clamps: y0 >= signed halfword obj+0x16
@ + [sp+0x18] (when raised, y1 is raised to at least y0 + m), y1 <= signed
@ halfword obj+0x1a - [sp+0x40] - [sp+0x3c] (when lowered, y0 is lowered to
@ at most y1 - m).
@ .L080245e4: [sp+0x10] = sxth([sp+0x28] + [sp+0x0c] + [sp+0x20]).
@ Rectangle A (r4) only when V and [sp+0x10] are nonzero: y1 = halfword
@ obj+0x1a - [sp+0x3c], y0 = y1 - r11 + 1, x0 = halfword obj+0x14, x1 =
@ halfword obj+0x18; L2 = [sp+0x0c] - r8 - r9 - r10; len2 = sxth(L2 *
@ [sp+0x0c] / [sp+0x10]); size2 = max(m, len2); when sxth([sp+0x10] -
@ [sp+0x0c]) <= 0: with W: x0 = halfword obj+0x14 + r8 + r10 - 1, x1 =
@ halfword obj+0x18 - r9; without W: x0 = halfword obj+0x14 + r8, x1 =
@ halfword obj+0x18 - r9 - r10 - 1; else offset2 = (L2 - size2) -
@ smulbb(L2 - size2, [sp+0x20]) / ([sp+0x10] - [sp+0x0c]); with W
@ (.L080246d8 onwards): x0 = sxth(halfword obj+0x14 + offset2 + r8 + r10),
@ x1 = x0 + size2 - 1, x0 raised to at least signed halfword obj+0x14 + r8 +
@ r10 (x1 then at least x0 + m), x1 lowered to at most signed halfword
@ obj+0x18 - r9; without W (.L080247dc): x0 = sxth(offset2 + r8 + halfword
@ obj+0x14), x1 = x0 + size2 - 1, x0 raised to at least signed halfword
@ obj+0x14 + r8, x1 lowered to at most signed halfword obj+0x18 - r10 - r9;
@ in both cases, when x1 was lowered, x0 = x1 - m if x1 - m < x0
@ (.L080247a2).
@ Merged pieces of this one contiguous range: .L08024298 shared epilogue;
@ .L080246d6 b to the epilogue; .L080247a2 compare of (x1 - m) with x0 after
@ the x1 clamp; .L080247d4 store x0 = halfword x1 - m; 0x08024874 unreferenced
@ b to .L08024876; .L08024876 and .L0802487a each set m = 1 (movs r0,#1)
@ and branch to .L080247a2 and .L080247d4.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024232,"ax",%progbits
	.global fn_08024232
	.thumb_func
	.type fn_08024232, %function
fn_08024232:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x44
	mov	r6, r2
	mov	r4, r1
	mov.w	r7, #0xffffffff
	mov	r5, r0
	movs	r2, #0
	mov	r3, r7
	mov	r1, r2
	mov	r0, r4
	str	r7, [sp]
	bl	rect_set		@ rect A = (0, 0, -1, -1)
	movs	r2, #0
	mov	r3, r7
	mov	r1, r2
	mov	r0, r6
	str	r7, [sp]
	bl	rect_set		@ rect B = (0, 0, -1, -1)
	movs	r1, #0x10
	mov	r0, r5
	bl	all_flag_bits_set
	cmp	r0, #0
	beq.n	.L08024298
	mov	r0, r5
	bl	fn_0802487e
	movs	r7, r0
	beq.n	.L08024298
	movs	r0, #0
	bl	fn_08021d90
	mov	r8, r0
	cmp	r7, #2
	beq.n	.L08024292
	b.n	.L080242a4
.L08024282:
	bl	fn_08021dee
	cmp	r0, r5
	beq.n	.L0802429e
	mov	r0, r8
	bl	fn_08021d90
	mov	r8, r0
.L08024292:
	cmp.w	r8, #0
	bne.n	.L08024282
.L08024298:
	add	sp, #0x44
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0802429e:
	cmp.w	r8, #0
	beq.n	.L08024298
.L080242a4:
	mov	r0, r5
	bl	fn_08024208
	str	r0, [sp, #0x14]
	mov	r0, r5
	bl	fn_08023fbc
	str	r0, [sp, #0x30]
	mov	r0, r5
	bl	fn_08024070
	str	r0, [sp, #0x28]
	mov	r0, r5
	bl	fn_08024130
	str	r0, [sp, #0x20]
	mov	r0, r5
	bl	fn_08024060
	mov	r9, r0
	movs	r0, #0
	tst.w	r9, #0xc
	str	r0, [sp]		@ flag H = 0
	beq.n	.L08024300
	cmp	r7, #1
	beq.n	.L080242fc
	cmp	r7, #3
	beq.n	.L080242e4
	cmp	r7, #2
	beq.n	.L080242f2
	b.n	.L08024300
.L080242e4:
	ldr	r0, [sp, #0x14]
	cmp	r0, #0
	bgt.n	.L080242fc
	ldr	r0, [sp, #0x30]
	cmp	r0, #0
	bgt.n	.L080242fc
	b.n	.L08024300
.L080242f2:
	mov	r0, r8
	bl	fn_08021dd0
	cmp	r0, #0xc
	bne.n	.L08024300
.L080242fc:
	movs	r0, #1
	str	r0, [sp]		@ flag H = 1
.L08024300:
	movs	r0, #0
	str	r0, [sp, #0x24]		@ flag V = 0
	lsls.w	r0, r9, #0x1e
	beq.n	.L08024334
	cmp	r7, #1
	beq.n	.L08024330
	cmp	r7, #3
	beq.n	.L08024318
	cmp	r7, #2
	beq.n	.L08024326
	b.n	.L08024334
.L08024318:
	ldr	r0, [sp, #0x28]
	cmp	r0, #0
	bgt.n	.L08024330
	ldr	r0, [sp, #0x20]
	cmp	r0, #0
	bgt.n	.L08024330
	b.n	.L08024334
.L08024326:
	mov	r0, r8
	bl	fn_08021dd0
	cmp	r0, #3
	bne.n	.L08024334
.L08024330:
	movs	r0, #1
	str	r0, [sp, #0x24]		@ flag V = 1
.L08024334:
	ldr	r1, [sp]
	ldr	r0, [sp, #0x24]
	orrs	r0, r1
	beq.n	.L08024298		@ H and V both 0: return
	mov.w	r7, #0x10000
	mov	r1, r7
	mov	r0, r5
	bl	fn_08024912
	cmp	r0, #1
	beq.n	.L0802434e
	movs	r0, #0
.L0802434e:
	str	r0, [sp, #0x38]		@ W
	mov	r1, r7
	mov	r0, r5
	bl	fn_08024b7c
	str	r0, [sp, #0x18]
	mov	r1, r7
	mov	r0, r5
	bl	fn_08024a8c
	str	r0, [sp, #0x3c]
	mov	r1, r7
	mov	r0, r5
	bl	fn_08024aec
	mov	r8, r0
	mov	r1, r7
	mov	r0, r5
	bl	fn_08024b28
	mov	r9, r0
	mov	r0, r5
	movs	r2, #1
	mov	r1, r7
	bl	fn_08024bac
	sxth.w	r11, r0
	mov	r0, r5
	bl	rect_height_plus_one
	str	r0, [sp, #0x10]
	mov	r0, r5
	bl	rect_width_plus_one
	str	r0, [sp, #0xc]
	ldr	r0, [sp]
	cbz	r0, .L0802439c
	mov	r0, r11
.L0802439c:
	mov	r10, r0			@ r10 = H ? r11 : 0
	ldr	r0, [sp, #0x24]
	cbz	r0, .L080243a4
	mov	r0, r11
.L080243a4:
	str	r0, [sp, #0x40]		@ V ? r11 : 0
	mov	r0, r5
	mov	r1, r7
	movs	r2, #0x21
	bl	fn_08024bac
	uxtb	r0, r0
	cmp	r0, #2
	bcs.n	.L080243c8
	mov	r0, r5
	mov	r1, r7
	movs	r2, #0x31
	bl	fn_08024bac
	uxtb	r0, r0
	cmp	r0, #2
	bcc.w	.L08024298
.L080243c8:
	ldrd	r0, r1, [sp, #0x10]
	add	r1, r0
	ldr	r0, [sp, #0x30]
	movs	r7, #0xa0
	add	r0, r1
	sxth	r0, r0
	str	r0, [sp, #0x2c]
	ldr	r0, [sp]
	cmp	r0, #0
.L080243dc:
	beq.n	.L080244c0
	ldr	r0, [sp, #0x2c]
	cmp	r0, #0
	beq.n	.L080243dc
	ldrh	r0, [r5, #0x16]
	strh	r0, [r6, #2]		@ B y0
	ldrh	r0, [r5, #0x1a]
	strh	r0, [r6, #6]		@ B y1
	ldr	r0, [sp, #0x38]
	cbz	r0, .L08024402
	ldrh	r1, [r5, #0x14]
	add.w	r0, r1, r8
	strh	r0, [r6]		@ B x0
	sub.w	r1, r11, #1
	add	r0, r1
	strh	r0, [r6, #4]		@ B x1
	b.n	.L08024412
.L08024402:
	ldrh	r1, [r5, #0x18]
	sub.w	r0, r1, r9
	strh	r0, [r6, #4]		@ B x1
	sub.w	r0, r0, r11
	.inst.n	0x1c40		@ adds r0, r0, #1
	strh	r0, [r6]		@ B x0
.L08024412:
	ldr	r1, [sp, #0x18]
	ldr	r0, [sp, #0x10]
	subs	r1, r0, r1
	ldr	r0, [sp, #0x3c]
	subs	r1, r1, r0
	ldr	r0, [sp, #0x40]
	subs	r0, r1, r0		@ L
	ldr	r1, [sp, #0x10]
	str	r0, [sp]
	muls	r0, r1, r0
	ldr	r1, [sp, #0x2c]
	sdiv	r0, r0, r1
	sxth	r0, r0
	str	r0, [sp, #0x14]		@ len
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	cmp.w	r0, #0x140
	blt.n	.L0802445c
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	sdiv	r0, r0, r7
	b.n	.L0802445e
.L0802445c:
	movs	r0, #1
.L0802445e:
	ldr	r1, [sp, #0x14]
	cmp	r0, r1
	bge.n	.L08024468
	mov	r0, r1
	b.n	.L08024496
.L08024468:
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	cmp.w	r0, #0x140
	blt.n	.L08024494
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	sdiv	r0, r0, r7
	b.n	.L08024496
.L08024494:
	movs	r0, #1
.L08024496:
	ldr	r1, [sp]
	sxth	r0, r0			@ size
	subs	r1, r1, r0
	sxth	r2, r1
	ldr	r3, [sp, #0x10]
	ldr	r1, [sp, #0x2c]
	subs	r1, r1, r3
	sxth	r1, r1
	cmp	r1, #0
	bgt.n	.L080244c2
	ldrh	r1, [r5, #0x16]
	ldr	r0, [sp, #0x18]
	add	r0, r1
	strh	r0, [r6, #2]		@ B y0
	ldrh	r1, [r5, #0x1a]
	ldr	r0, [sp, #0x3c]
	subs	r1, r1, r0
	ldr	r0, [sp, #0x40]
	subs	r0, r1, r0
	.inst.n	0x1e40		@ subs r0, r0, #1
	strh	r0, [r6, #6]		@ B y1
.L080244c0:
	b.n	.L080245e4
.L080244c2:
	ldr	r3, [sp, #0x30]
	smulbb	r3, r2, r3
	sdiv	r1, r3, r1
	subs	r1, r2, r1
	ldr	r2, [sp, #0x18]
	ldrh	r3, [r5, #0x16]
	add	r1, r2
	add	r1, r3
	sxth	r1, r1
	.inst.n	0x1e40		@ subs r0, r0, #1
	strh	r1, [r6, #2]		@ B y0
	add	r0, r1
	strh	r0, [r6, #6]		@ B y1 = y0 + size - 1
	ldrsh.w	r2, [r5, #0x16]
	ldr	r0, [sp, #0x18]
	add	r0, r2
	cmp	r1, r0
	bge.n	.L0802455e
	strh	r0, [r6, #2]		@ y0 raised
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	cmp.w	r0, #0x140
	blt.n	.L0802451a
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	sdiv	r0, r0, r7
	b.n	.L0802451c
.L0802451a:
	movs	r0, #1
.L0802451c:
	ldrsh.w	r1, [r6, #2]
	add	r0, r1
	ldrsh.w	r1, [r6, #6]
	cmp	r0, r1
	ble.n	.L0802455e
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	cmp.w	r0, #0x140
	blt.n	.L08024556
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	sdiv	r0, r0, r7
	b.n	.L08024558
.L08024556:
	movs	r0, #1
.L08024558:
	ldrh	r1, [r6, #2]
	add	r0, r1
	strh	r0, [r6, #6]		@ y1 = y0 + m
.L0802455e:
	ldrsh.w	r2, [r5, #0x1a]
	ldr	r0, [sp, #0x40]
	ldrsh.w	r1, [r6, #6]
	subs	r2, r2, r0
	ldr	r0, [sp, #0x3c]
	subs	r0, r2, r0
	cmp	r1, r0
	ble.n	.L080245e4
	strh	r0, [r6, #6]		@ y1 lowered
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	cmp.w	r0, #0x140
	blt.n	.L080245a0
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	sdiv	r0, r0, r7
	b.n	.L080245a2
.L080245a0:
	movs	r0, #1
.L080245a2:
	ldrsh.w	r1, [r6, #6]
	subs	r0, r1, r0
	ldrsh.w	r1, [r6, #2]
	cmp	r0, r1
	bge.n	.L080245e4
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	cmp.w	r0, #0x140
	blt.n	.L080245dc
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r1, r0, r0, lsl #2
	movs	r0, #0x50
	add.w	r0, r0, r1, lsl #1
	sdiv	r0, r0, r7
	b.n	.L080245de
.L080245dc:
	movs	r0, #1
.L080245de:
	ldrh	r1, [r6, #6]
	subs	r0, r1, r0
	strh	r0, [r6, #2]		@ y0 = y1 - m
.L080245e4:
	ldr	r1, [sp, #0x28]
	ldr	r0, [sp, #0xc]
	add	r1, r0
	ldr	r0, [sp, #0x20]
	add	r0, r1
	sxth	r0, r0
	str	r0, [sp, #0x10]
	ldr	r0, [sp, #0x24]
	cmp	r0, #0
.L080245f6:
	beq.w	.L08024298
	ldr	r0, [sp, #0x10]
	cmp	r0, #0
	beq.n	.L080245f6
	ldrh	r1, [r5, #0x1a]
	ldr	r0, [sp, #0x3c]
	subs	r0, r1, r0
	strh	r0, [r4, #6]		@ A y1
	sub.w	r0, r0, r11
	.inst.n	0x1c40		@ adds r0, r0, #1
	strh	r0, [r4, #2]		@ A y0
	ldrh	r0, [r5, #0x14]
	strh	r0, [r4]		@ A x0
	ldrh	r0, [r5, #0x18]
	strh	r0, [r4, #4]		@ A x1
	ldr	r1, [sp, #0xc]
	sub.w	r1, r1, r8
	sub.w	r1, r1, r9
	sub.w	r0, r1, r10		@ L2
	ldr	r1, [sp, #0xc]
	str	r0, [sp]
	muls	r0, r1, r0
	ldr	r1, [sp, #0x10]
	sdiv	r0, r0, r1
	sxth	r0, r0
	str	r0, [sp, #8]		@ len2
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	movs	r6, #0x50
	add.w	r0, r6, r0, lsl #1
	mov.w	r11, #0x140
	cmp	r0, r11
	blt.n	.L08024662
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	sdiv	r0, r0, r7
	b.n	.L08024664
.L08024662:
	movs	r0, #1
.L08024664:
	ldr	r1, [sp, #8]
	cmp	r0, r1
	bge.n	.L0802466e
	mov	r0, r1
	b.n	.L08024696
.L0802466e:
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	cmp	r0, r11
	blt.n	.L08024694
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	sdiv	r0, r0, r7
	b.n	.L08024696
.L08024694:
	movs	r0, #1
.L08024696:
	ldr	r1, [sp]
	sxth	r0, r0			@ size2
	subs	r1, r1, r0
	sxth	r2, r1
	ldrd	r3, r1, [sp, #0xc]
	subs	r1, r1, r3
	sxth	r1, r1
	cmp	r1, #0
	bgt.n	.L080246d8
	ldrh	r1, [r5, #0x14]
	ldr	r0, [sp, #0x38]
	cbz	r0, .L080246c2
	add	r1, r8
	sub.w	r0, r10, #1
	add	r0, r1
	strh	r0, [r4]		@ A x0
	ldrh	r1, [r5, #0x18]
	sub.w	r0, r1, r9
	b.n	.L080246d4
.L080246c2:
	add.w	r0, r1, r8
	strh	r0, [r4]		@ A x0
	ldrh	r1, [r5, #0x18]
	sub.w	r1, r1, r9
	sub.w	r0, r1, r10
	.inst.n	0x1e40		@ subs r0, r0, #1
.L080246d4:
	strh	r0, [r4, #4]		@ A x1
.L080246d6:
	b.n	.L08024298
.L080246d8:
	ldr	r3, [sp, #0x20]
	smulbb	r3, r2, r3
	sdiv	r1, r3, r1
	subs	r1, r2, r1
	ldr	r2, [sp, #0x38]
	sxth	r1, r1
	cbz	r2, .L08024766
	ldrh	r2, [r5, #0x14]
	.inst.n	0x1e40		@ subs r0, r0, #1
	adds	r3, r2, r1
	add.w	r2, r8, r10
	adds	r1, r3, r2
	sxth	r1, r1
	strh	r1, [r4]		@ A x0
	add	r0, r1
	strh	r0, [r4, #4]		@ A x1 = x0 + size2 - 1
	ldrsh.w	r0, [r5, #0x14]
	add	r0, r2
	cmp	r0, r1
	ble.n	.L08024770
	strh	r0, [r4]		@ x0 raised
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	cmp	r0, r11
	blt.n	.L08024730
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	sdiv	r0, r0, r7
	b.n	.L08024732
.L08024730:
	movs	r0, #1
.L08024732:
	ldrsh.w	r1, [r4]
	add	r0, r1
	ldrsh.w	r1, [r4, #4]
	cmp	r0, r1
	ble.n	.L08024770
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	cmp	r0, r11
	blt.n	.L08024768
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	sdiv	r0, r0, r7
	b.n	.L0802476a
.L08024766:
	b.n	.L080247dc
.L08024768:
	movs	r0, #1
.L0802476a:
	ldrh	r1, [r4]
	add	r0, r1
	strh	r0, [r4, #4]		@ x1 = x0 + m
.L08024770:
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r5, #0x18]
	b.n	.L0802486a
.L0802477a:
	strh	r0, [r4, #4]		@ x1 lowered
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	mov	r5, r11
	cmp	r0, r5
	blt.n	.L08024876
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	sdiv	r0, r0, r7
.L080247a2:
	ldrsh.w	r1, [r4, #4]
	subs	r0, r1, r0
	ldrsh.w	r1, [r4]
	cmp	r0, r1
	bge.n	.L080246d6
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	cmp	r0, r5
	blt.n	.L0802487a
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	sdiv	r0, r0, r7
.L080247d4:
	ldrh	r1, [r4, #4]
	subs	r0, r1, r0
	strh	r0, [r4]		@ x0 = x1 - m
	b.n	.L08024298
.L080247dc:
	ldrh	r3, [r5, #0x14]
	add	r1, r8
	add	r1, r3
	sxth	r1, r1
	.inst.n	0x1e40		@ subs r0, r0, #1
	strh	r1, [r4]		@ A x0
	add	r0, r1
	strh	r0, [r4, #4]		@ A x1 = x0 + size2 - 1
	ldrsh.w	r2, [r5, #0x14]
	add.w	r0, r2, r8
	cmp	r1, r0
	bge.n	.L0802485e
	strh	r0, [r4]		@ x0 raised
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	cmp	r0, r11
	blt.n	.L08024820
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	sdiv	r0, r0, r7
	b.n	.L08024822
.L08024820:
	movs	r0, #1
.L08024822:
	ldrsh.w	r1, [r4]
	add	r0, r1
	ldrsh.w	r1, [r4, #4]
	cmp	r0, r1
	ble.n	.L0802485e
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	cmp	r0, r11
	blt.n	.L08024856
	movs	r0, #0
	bl	fn_0801dcd8
	add.w	r0, r0, r0, lsl #2
	add.w	r0, r6, r0, lsl #1
	sdiv	r0, r0, r7
	b.n	.L08024858
.L08024856:
	movs	r0, #1
.L08024858:
	ldrh	r1, [r4]
	add	r0, r1
	strh	r0, [r4, #4]		@ x1 = x0 + m
.L0802485e:
	ldrsh.w	r2, [r5, #0x18]
	ldrsh.w	r1, [r4, #4]
	sub.w	r2, r2, r10
.L0802486a:
	sub.w	r0, r2, r9
	cmp	r1, r0
	bgt.n	.L0802477a
	b.n	.L08024298
	b.n	.L08024876		@ unreferenced
.L08024876:
	movs	r0, #1
	b.n	.L080247a2
.L0802487a:
	movs	r0, #1
	b.n	.L080247d4

@ ----------------------------------------------------------------------------
@ fn_0802487e - r0 = object; returns 3 when the word at object+8 is zero,
@ else the byte at [object+8]+0x18 masked with 3.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802487e,"ax",%progbits
	.global fn_0802487e
	.thumb_func
	.type fn_0802487e, %function
fn_0802487e:
	ldr	r0, [r0, #8]
	cbz	r0, .L0802488a
	ldrb	r0, [r0, #0x18]
	and.w	r0, r0, #3
	bx	lr
.L0802488a:
	movs	r0, #3
	bx	lr
	.short	0x0000		@ padding

@ ----------------------------------------------------------------------------
@ fn_08024890 - r0 = object; returns a signed 16-bit value.
@ Builds a word on the stack from the word at [0x0804fd18 + 4] (the literal
@ points to d_0804fd18), sends message 0x2c to the object with fn_080207f4
@ (r0 = object, r1 = 0x2c, r2 = pointer to the word) and returns the upper
@ halfword (signed) of the word at [sp].
@ ----------------------------------------------------------------------------
	.section .text.fn_08024890,"ax",%progbits
	.p2align 2
	.global fn_08024890
	.thumb_func
	.type fn_08024890, %function
fn_08024890:
	push	{r3, lr}
	ldr	r1, .L080248a8
	mov	r2, sp
	ldr	r1, [r1, #4]
	str	r1, [sp]
	movs	r1, #0x2c
	bl	fn_080207f4
	ldrsh.w	r0, [sp, #2]
	pop	{r3, pc}
	.short	0x0000		@ padding
.L080248a8:
	.word	d_0804fd18

@ ----------------------------------------------------------------------------
@ fn_080248ac - r0 = object; returns a signed 16-bit value.
@ Builds a word on the stack from the word at [0x0804fd18] (the literal
@ points to d_0804fd18), sends message 0x2c to the object with fn_080207f4
@ (r0 = object, r1 = 0x2c, r2 = pointer to the word) and returns the lower
@ halfword (signed) of the word at [sp].
@ ----------------------------------------------------------------------------
	.section .text.fn_080248ac,"ax",%progbits
	.p2align 2
	.global fn_080248ac
	.thumb_func
	.type fn_080248ac, %function
fn_080248ac:
	push	{r3, lr}
	ldr	r1, .L080248c4
	mov	r2, sp
	ldr	r1, [r1]
	str	r1, [sp]
	movs	r1, #0x2c
	bl	fn_080207f4
	ldrsh.w	r0, [sp]
	pop	{r3, pc}
	.short	0x0000		@ padding
.L080248c4:
	.word	d_0804fd18

@ ----------------------------------------------------------------------------
@ fn_080248c8 - r0 = object; returns the halfword at offset 0x20 of the
@ object.
@ ----------------------------------------------------------------------------
	.section .text.fn_080248c8,"ax",%progbits
	.p2align 2
	.global fn_080248c8
	.thumb_func
	.type fn_080248c8, %function
fn_080248c8:
	ldrh	r0, [r0, #0x20]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_080248cc - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x9 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_080248cc,"ax",%progbits
	.p2align 2
	.global fn_080248cc
	.thumb_func
	.type fn_080248cc, %function
fn_080248cc:
	push	{r4, lr}
	movs	r2, #9
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080248d8 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x9 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_080248d8,"ax",%progbits
	.p2align 2
	.global fn_080248d8
	.thumb_func
	.type fn_080248d8, %function
fn_080248d8:
	push	{r4, lr}
	movs	r2, #9
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080248e4 - r0 = object, r1 = second argument of fn_08024bac.
@ Tail-calls fn_08024bac with key 0x65; returns r0 as left by fn_08024bac.
@ ----------------------------------------------------------------------------
	.section .text.fn_080248e4,"ax",%progbits
	.global fn_080248e4
	.thumb_func
	.type fn_080248e4, %function
fn_080248e4:
	movs	r2, #0x65
	b.w	fn_08024bac

@ ----------------------------------------------------------------------------
@ fn_080248ea - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x51; returns 1 when the result is nonzero,
@ else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080248ea,"ax",%progbits
	.global fn_080248ea
	.thumb_func
	.type fn_080248ea, %function
fn_080248ea:
	push	{r4, lr}
	movs	r2, #0x51
	bl	fn_08024bac
	cmp	r0, #0
	beq.n	.L080248f8
	movs	r0, #1
.L080248f8:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080248fa - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x50; returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_080248fa,"ax",%progbits
	.global fn_080248fa
	.thumb_func
	.type fn_080248fa, %function
fn_080248fa:
	push	{r4, lr}
	movs	r2, #0x50
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024906 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x16 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024906,"ax",%progbits
	.global fn_08024906
	.thumb_func
	.type fn_08024906, %function
fn_08024906:
	push	{r4, lr}
	movs	r2, #0x16
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024912 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x16 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024912,"ax",%progbits
	.global fn_08024912
	.thumb_func
	.type fn_08024912, %function
fn_08024912:
	push	{r4, lr}
	movs	r2, #0x16
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0802491e - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x16 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802491e,"ax",%progbits
	.global fn_0802491e
	.thumb_func
	.type fn_0802491e, %function
fn_0802491e:
	push	{r4, lr}
	movs	r2, #0x16
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0802492a - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x16 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802492a,"ax",%progbits
	.global fn_0802492a
	.thumb_func
	.type fn_0802492a, %function
fn_0802492a:
	push	{r4, lr}
	movs	r2, #0x16
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024936 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x16 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024936,"ax",%progbits
	.global fn_08024936
	.thumb_func
	.type fn_08024936, %function
fn_08024936:
	push	{r4, lr}
	movs	r2, #0x16
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024942 - r0 = object, r1 = second argument.
@ Reads key 0x20 with fn_08024bac and passes the result as the third
@ argument to fn_08012786 with r0, r1; a tail call (b.w to fn_08012786), so
@ the function returns what fn_08012786 returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024942,"ax",%progbits
	.global fn_08024942
	.thumb_func
	.type fn_08024942, %function
fn_08024942:
	push	{r4, r5, r6, lr}
	mov	r4, r1
	mov	r5, r0
	movs	r2, #0x20
	bl	fn_08024bac
	mov	r2, r0
	mov	r1, r4
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08012786

@ ----------------------------------------------------------------------------
@ fn_0802495c - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x21 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802495c,"ax",%progbits
	.p2align 2
	.global fn_0802495c
	.thumb_func
	.type fn_0802495c, %function
fn_0802495c:
	push	{r4, lr}
	movs	r2, #0x21
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024968 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x67 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024968,"ax",%progbits
	.p2align 2
	.global fn_08024968
	.thumb_func
	.type fn_08024968, %function
fn_08024968:
	push	{r4, lr}
	movs	r2, #0x67
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024974 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x34; returns 1 when the result is nonzero,
@ else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024974,"ax",%progbits
	.p2align 2
	.global fn_08024974
	.thumb_func
	.type fn_08024974, %function
fn_08024974:
	push	{r4, lr}
	movs	r2, #0x34
	bl	fn_08024bac
	cmp	r0, #0
	beq.n	.L08024982
	movs	r0, #1
.L08024982:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024984 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x32 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024984,"ax",%progbits
	.p2align 2
	.global fn_08024984
	.thumb_func
	.type fn_08024984, %function
fn_08024984:
	push	{r4, lr}
	movs	r2, #0x32
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024990 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x32 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024990,"ax",%progbits
	.p2align 2
	.global fn_08024990
	.thumb_func
	.type fn_08024990, %function
fn_08024990:
	push	{r4, lr}
	movs	r2, #0x32
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0802499c - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x32 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802499c,"ax",%progbits
	.p2align 2
	.global fn_0802499c
	.thumb_func
	.type fn_0802499c, %function
fn_0802499c:
	push	{r4, lr}
	movs	r2, #0x32
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080249a8 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x17; returns 1 when the result is nonzero,
@ else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080249a8,"ax",%progbits
	.p2align 2
	.global fn_080249a8
	.thumb_func
	.type fn_080249a8, %function
fn_080249a8:
	push	{r4, lr}
	movs	r2, #0x17
	bl	fn_08024bac
	cmp	r0, #0
	beq.n	.L080249b6
	movs	r0, #1
.L080249b6:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080249b8 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with the key taken from the halfword at 0x2000054e (the
@ literal holds 0x20000544, ldrh r2, [r2, #10]) and returns the low byte of
@ the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_080249b8,"ax",%progbits
	.p2align 2
	.global fn_080249b8
	.thumb_func
	.type fn_080249b8, %function
fn_080249b8:
	ldr	r2, .L080249c8
	push	{r4, lr}
	ldrh	r2, [r2, #0xa]
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}
	.short	0x0000		@ padding
.L080249c8:
	.word	0x20000544

@ ----------------------------------------------------------------------------
@ fn_080249cc - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x4 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_080249cc,"ax",%progbits
	.p2align 2
	.global fn_080249cc
	.thumb_func
	.type fn_080249cc, %function
fn_080249cc:
	push	{r4, lr}
	movs	r2, #4
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080249d8 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x4 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_080249d8,"ax",%progbits
	.p2align 2
	.global fn_080249d8
	.thumb_func
	.type fn_080249d8, %function
fn_080249d8:
	push	{r4, lr}
	movs	r2, #4
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080249e4 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x4 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_080249e4,"ax",%progbits
	.p2align 2
	.global fn_080249e4
	.thumb_func
	.type fn_080249e4, %function
fn_080249e4:
	push	{r4, lr}
	movs	r2, #4
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080249f0 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x4 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_080249f0,"ax",%progbits
	.p2align 2
	.global fn_080249f0
	.thumb_func
	.type fn_080249f0, %function
fn_080249f0:
	push	{r4, lr}
	movs	r2, #4
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080249fc - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0xa and returns the low 16 bits of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_080249fc,"ax",%progbits
	.p2align 2
	.global fn_080249fc
	.thumb_func
	.type fn_080249fc, %function
fn_080249fc:
	push	{r4, lr}
	movs	r2, #0xa
	bl	fn_08024bac
	uxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a08 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0xa and returns the low 16 bits of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a08,"ax",%progbits
	.p2align 2
	.global fn_08024a08
	.thumb_func
	.type fn_08024a08, %function
fn_08024a08:
	push	{r4, lr}
	movs	r2, #0xa
	bl	fn_08024bac
	uxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a14 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x49 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a14,"ax",%progbits
	.p2align 2
	.global fn_08024a14
	.thumb_func
	.type fn_08024a14, %function
fn_08024a14:
	push	{r4, lr}
	movs	r2, #0x49
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a20 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x6 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a20,"ax",%progbits
	.p2align 2
	.global fn_08024a20
	.thumb_func
	.type fn_08024a20, %function
fn_08024a20:
	push	{r4, lr}
	movs	r2, #6
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a2c - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x5 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a2c,"ax",%progbits
	.p2align 2
	.global fn_08024a2c
	.thumb_func
	.type fn_08024a2c, %function
fn_08024a2c:
	push	{r4, lr}
	movs	r2, #5
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a38 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x60 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a38,"ax",%progbits
	.p2align 2
	.global fn_08024a38
	.thumb_func
	.type fn_08024a38, %function
fn_08024a38:
	push	{r4, lr}
	movs	r2, #0x60
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a44 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x60 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a44,"ax",%progbits
	.p2align 2
	.global fn_08024a44
	.thumb_func
	.type fn_08024a44, %function
fn_08024a44:
	push	{r4, lr}
	movs	r2, #0x60
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a50 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x60 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a50,"ax",%progbits
	.p2align 2
	.global fn_08024a50
	.thumb_func
	.type fn_08024a50, %function
fn_08024a50:
	push	{r4, lr}
	movs	r2, #0x60
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a5c - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x37 and returns the low byte of the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a5c,"ax",%progbits
	.p2align 2
	.global fn_08024a5c
	.thumb_func
	.type fn_08024a5c, %function
fn_08024a5c:
	push	{r4, lr}
	movs	r2, #0x37
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a68 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x38 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a68,"ax",%progbits
	.p2align 2
	.global fn_08024a68
	.thumb_func
	.type fn_08024a68, %function
fn_08024a68:
	push	{r4, lr}
	movs	r2, #0x38
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a74 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x35 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a74,"ax",%progbits
	.p2align 2
	.global fn_08024a74
	.thumb_func
	.type fn_08024a74, %function
fn_08024a74:
	push	{r4, lr}
	movs	r2, #0x35
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a80 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x11 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a80,"ax",%progbits
	.p2align 2
	.global fn_08024a80
	.thumb_func
	.type fn_08024a80, %function
fn_08024a80:
	push	{r4, lr}
	movs	r2, #0x11
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a8c - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x11 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a8c,"ax",%progbits
	.p2align 2
	.global fn_08024a8c
	.thumb_func
	.type fn_08024a8c, %function
fn_08024a8c:
	push	{r4, lr}
	movs	r2, #0x11
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024a98 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x11 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024a98,"ax",%progbits
	.p2align 2
	.global fn_08024a98
	.thumb_func
	.type fn_08024a98, %function
fn_08024a98:
	push	{r4, lr}
	movs	r2, #0x11
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024aa4 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x11 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024aa4,"ax",%progbits
	.p2align 2
	.global fn_08024aa4
	.thumb_func
	.type fn_08024aa4, %function
fn_08024aa4:
	push	{r4, lr}
	movs	r2, #0x11
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024ab0 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x11 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024ab0,"ax",%progbits
	.p2align 2
	.global fn_08024ab0
	.thumb_func
	.type fn_08024ab0, %function
fn_08024ab0:
	push	{r4, lr}
	movs	r2, #0x11
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024abc - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x15 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024abc,"ax",%progbits
	.p2align 2
	.global fn_08024abc
	.thumb_func
	.type fn_08024abc, %function
fn_08024abc:
	push	{r4, lr}
	movs	r2, #0x15
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024ac8 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x15 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024ac8,"ax",%progbits
	.p2align 2
	.global fn_08024ac8
	.thumb_func
	.type fn_08024ac8, %function
fn_08024ac8:
	push	{r4, lr}
	movs	r2, #0x15
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024ad4 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x15 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024ad4,"ax",%progbits
	.p2align 2
	.global fn_08024ad4
	.thumb_func
	.type fn_08024ad4, %function
fn_08024ad4:
	push	{r4, lr}
	movs	r2, #0x15
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024ae0 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x12 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024ae0,"ax",%progbits
	.p2align 2
	.global fn_08024ae0
	.thumb_func
	.type fn_08024ae0, %function
fn_08024ae0:
	push	{r4, lr}
	movs	r2, #0x12
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024aec - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x12 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024aec,"ax",%progbits
	.p2align 2
	.global fn_08024aec
	.thumb_func
	.type fn_08024aec, %function
fn_08024aec:
	push	{r4, lr}
	movs	r2, #0x12
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024af8 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x12 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024af8,"ax",%progbits
	.p2align 2
	.global fn_08024af8
	.thumb_func
	.type fn_08024af8, %function
fn_08024af8:
	push	{r4, lr}
	movs	r2, #0x12
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b04 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x12 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b04,"ax",%progbits
	.p2align 2
	.global fn_08024b04
	.thumb_func
	.type fn_08024b04, %function
fn_08024b04:
	push	{r4, lr}
	movs	r2, #0x12
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b10 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x12 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b10,"ax",%progbits
	.p2align 2
	.global fn_08024b10
	.thumb_func
	.type fn_08024b10, %function
fn_08024b10:
	push	{r4, lr}
	movs	r2, #0x12
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b1c - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x13 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b1c,"ax",%progbits
	.p2align 2
	.global fn_08024b1c
	.thumb_func
	.type fn_08024b1c, %function
fn_08024b1c:
	push	{r4, lr}
	movs	r2, #0x13
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b28 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x13 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b28,"ax",%progbits
	.p2align 2
	.global fn_08024b28
	.thumb_func
	.type fn_08024b28, %function
fn_08024b28:
	push	{r4, lr}
	movs	r2, #0x13
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b34 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x13 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b34,"ax",%progbits
	.p2align 2
	.global fn_08024b34
	.thumb_func
	.type fn_08024b34, %function
fn_08024b34:
	push	{r4, lr}
	movs	r2, #0x13
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b40 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x13 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b40,"ax",%progbits
	.p2align 2
	.global fn_08024b40
	.thumb_func
	.type fn_08024b40, %function
fn_08024b40:
	push	{r4, lr}
	movs	r2, #0x13
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b4c - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x13 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b4c,"ax",%progbits
	.p2align 2
	.global fn_08024b4c
	.thumb_func
	.type fn_08024b4c, %function
fn_08024b4c:
	push	{r4, lr}
	movs	r2, #0x13
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b58 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x14 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b58,"ax",%progbits
	.p2align 2
	.global fn_08024b58
	.thumb_func
	.type fn_08024b58, %function
fn_08024b58:
	push	{r4, lr}
	movs	r2, #0x14
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b64 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x14 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b64,"ax",%progbits
	.p2align 2
	.global fn_08024b64
	.thumb_func
	.type fn_08024b64, %function
fn_08024b64:
	push	{r4, lr}
	movs	r2, #0x14
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b70 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x10 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b70,"ax",%progbits
	.p2align 2
	.global fn_08024b70
	.thumb_func
	.type fn_08024b70, %function
fn_08024b70:
	push	{r4, lr}
	movs	r2, #0x10
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b7c - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x10 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b7c,"ax",%progbits
	.p2align 2
	.global fn_08024b7c
	.thumb_func
	.type fn_08024b7c, %function
fn_08024b7c:
	push	{r4, lr}
	movs	r2, #0x10
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b88 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x10 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b88,"ax",%progbits
	.p2align 2
	.global fn_08024b88
	.thumb_func
	.type fn_08024b88, %function
fn_08024b88:
	push	{r4, lr}
	movs	r2, #0x10
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024b94 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x10 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024b94,"ax",%progbits
	.p2align 2
	.global fn_08024b94
	.thumb_func
	.type fn_08024b94, %function
fn_08024b94:
	push	{r4, lr}
	movs	r2, #0x10
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024ba0 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac with key 0x10 and returns the result as a signed 16-bit
@ value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024ba0,"ax",%progbits
	.p2align 2
	.global fn_08024ba0
	.thumb_func
	.type fn_08024ba0, %function
fn_08024ba0:
	push	{r4, lr}
	movs	r2, #0x10
	bl	fn_08024bac
	sxth	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024bac - r0 = object, r1 = flag, r2 = key, r3 is not read (a stack
@ address is passed to fn_0801b65a as its fourth argument); returns the
@ value for the key.
@ Tests fn_08026fec of the key with mask 1.
@ Loops: fn_0801b65a looks the key up in the object; result 1 returns the
@ found value; result 2, or flag 0, moves to the parent (fn_08023fa4),
@ otherwise the flag becomes 0.
@ When nothing is found and the flag is 0 and the key is 1 or 4: scans the
@ children chain (first word of each link) for the first one whose halfword
@ at +0x14 (key 1) or +0x16 (key 4) is nonzero and returns it, else 0.
@ Otherwise returns fn_08026f20 of the key (default value).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024bac,"ax",%progbits
	.p2align 2
	.global fn_08024bac
	.thumb_func
	.type fn_08024bac, %function
fn_08024bac:
	push.w	{r3, r4, r5, r6, r7, r8, r9, lr}
	mov	r8, r1
	mov	r6, r0
	mov	r4, r2
	movs	r1, #1
	mov	r0, r2
	bl	fn_08026fec
	mov	r7, r0
	movs	r5, #0
	b.n	.L08024bf0
.L08024bc4:
	mov	r3, sp
	mov	r2, r4
	mov	r1, r8
	mov	r0, r6
	bl	fn_0801b65a
	mov	r5, r0
	cmp	r0, #1
	beq.n	.L08024c26
	cbz	r7, .L08024bf8
	cmp	r5, #2
	beq.n	.L08024be8
	cmp.w	r8, #0
	beq.n	.L08024be8
	mov.w	r8, #0
	b.n	.L08024bf0
.L08024be8:
	mov	r0, r6
	bl	fn_08023fa4
	mov	r6, r0
.L08024bf0:
	cmp	r6, #0
	bne.n	.L08024bc4
	cmp	r5, #1
	beq.n	.L08024c26
.L08024bf8:
	cmp.w	r8, #0
	bne.n	.L08024c06
	cmp	r4, #1
	beq.n	.L08024c0e
	cmp	r4, #4
	beq.n	.L08024c0e
.L08024c06:
	mov	r0, r4
	bl	fn_08026f20
	b.n	.L08024c24
.L08024c0e:
	ldr	r1, [r6]
	b.n	.L08024c32
.L08024c12:
	cmp	r4, #1
	beq.n	.L08024c2c
	ldrh	r0, [r1, #0x16]
.L08024c18:
	cbz	r0, .L08024c30
	cbz	r1, .L08024c36
	cmp	r4, #1
	beq.n	.L08024c3a
	ldrsh.w	r0, [r1, #0x16]
.L08024c24:
	str	r0, [sp]
.L08024c26:
	ldr	r0, [sp]
	pop.w	{r3, r4, r5, r6, r7, r8, r9, pc}
.L08024c2c:
	ldrh	r0, [r1, #0x14]
	b.n	.L08024c18
.L08024c30:
	ldr	r1, [r1]
.L08024c32:
	cmp	r1, #0
	bne.n	.L08024c12
.L08024c36:
	movs	r0, #0
	b.n	.L08024c24
.L08024c3a:
	ldrsh.w	r0, [r1, #0x14]
	b.n	.L08024c24
