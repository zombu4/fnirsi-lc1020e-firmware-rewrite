@ gui_21.s - GUI object helpers: object field setters, list insert/remove, class-based object creation, rectangle/flag handling and the object message handlers at 0x08022afc..0x08023d54
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08022afc - stores a word and a halfword into an object, then calls two
@ helpers.
@ r0 = object, r1 = word, r2 = halfword; no return value.
@ Stores word +0x24 = r1 and halfword +0x28 = r2, calls fn_08025d04() and then
@ tail-calls fn_08025400(object).
@ ----------------------------------------------------------------------------
	.section .text.fn_08022afc,"ax",%progbits
	.global fn_08022afc
	.thumb_func
	.type fn_08022afc, %function
fn_08022afc:
	push	{r4, lr}
	str	r1, [r0, #0x24]
	mov	r4, r0
	strh	r2, [r0, #0x28]
	bl	fn_08025d04
	mov	r0, r4
	pop.w	{r4, lr}
	b.w	fn_08025400

@ ----------------------------------------------------------------------------
@ fn_08022f28 - initialises two sub-blocks of an object.
@ r1 = object (r0 not used); no return value.
@ Calls init_header_aligned4(object + 0x24, 0x24), then tail-calls
@ init_header_aligned4(object + 0x30, 0x1c).
@ ----------------------------------------------------------------------------
	.section .text.fn_08022f28,"ax",%progbits
	.p2align 2
	.global fn_08022f28
	.thumb_func
	.type fn_08022f28, %function
fn_08022f28:
	push	{r4, lr}
	mov	r4, r1
	movs	r1, #0x24
	add.w	r0, r4, #0x24
	bl	init_header_aligned4
	add.w	r0, r4, #0x30
	pop.w	{r4, lr}
	movs	r1, #0x1c
	b.w	init_header_aligned4

@ ----------------------------------------------------------------------------
@ fn_08022f44 - releases two sub-blocks of an object.
@ r1 = object (r0 not used); no return value.
@ Calls fn_080125a2(object + 0x30), then tail-calls fn_080125a2(object + 0x24).
@ ----------------------------------------------------------------------------
	.section .text.fn_08022f44,"ax",%progbits
	.p2align 2
	.global fn_08022f44
	.thumb_func
	.type fn_08022f44, %function
fn_08022f44:
	push	{r4, lr}
	mov	r4, r1
	add.w	r0, r1, #0x30
	bl	fn_080125a2
	add.w	r0, r4, #0x24
	pop.w	{r4, lr}
	b.w	fn_080125a2

@ ----------------------------------------------------------------------------
@ fn_08022f5c - draws a centred item for an object of type 0x15.
@ r1 = object handle (kept in r5); r0 is overwritten by the literal load and
@ not read; no return value.
@ Calls fn_08023d54(0x08050f30, handle) (literal at 0x0802302c) and leaves
@ unless the result is 1. type = get_byte8_low7(handle), r4 = get_first_word
@ (handle); leaves unless the type is 0x15.
@ r9 = get_word_10_if_byte_8_14_to_19(handle). Fills the 4-halfword rectangle
@ at sp with fn_08023dec(r4, sp), then calls fn_08014ff4, fn_0801998c and
@ fn_080179ac each with (r4, r9, sp).
@ Centre: half = sxth(h[2] - h[0] + 1) / 2 (signed halving by add lsr #31 and
@ asr #1) from the halfwords at sp+4 and sp; r6 = h[0] + half, r5 = h[1]
@ (halfword at sp+2) + the same half.
@ Initialises the record at sp+0x10 with fn_0801f344 and calls fn_0802516e
@ (r4, 0x20000, record). r7 = sxth(fn_08024bac(r4, 0x20000, 1)) / 2 and
@ r0 = sxth(fn_08024bac(r4, 0x20000, 4)) / 2.
@ Stores the rectangle at sp+0x54 as halfwords {r6 - r7, r5 - r0, r6 + r7,
@ r5 + r0} and calls fn_0801f31c(r9, record at sp+0x10, rectangle at
@ sp+0x54). Stack frame: 7 registers pushed plus 0x5c bytes.
@ ----------------------------------------------------------------------------
	.section .text.fn_08022f5c,"ax",%progbits
	.p2align 2
	.global fn_08022f5c
	.thumb_func
	.type fn_08022f5c, %function
fn_08022f5c:
	push.w	{r4, r5, r6, r7, r8, r9, lr}
	sub	sp, #0x5c
	mov	r5, r1
	ldr	r0, .L0802302c
	bl	fn_08023d54
	cmp	r0, #1
	bne.n	.L08023026
	mov	r0, r5
	bl	get_byte8_low7
	mov	r6, r0
	mov	r0, r5
	bl	get_first_word
	mov	r4, r0
	cmp	r6, #0x15
	bne.n	.L08023026
	mov	r0, r5
	bl	get_word_10_if_byte_8_14_to_19
	mov	r9, r0
	mov	r1, sp
	mov	r0, r4
	bl	fn_08023dec
	mov	r2, sp
	mov	r1, r9
	mov	r0, r4
	bl	fn_08014ff4
	mov	r2, sp
	mov	r1, r9
	mov	r0, r4
	bl	fn_0801998c
	mov	r2, sp
	mov	r1, r9
	mov	r0, r4
	bl	fn_080179ac
	ldrh.w	r0, [sp, #0x4]
	ldrh.w	r1, [sp]
	subs	r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth	r0, r0
	add.w	r0, r0, r0, lsr #31
	asrs	r0, r0, #1
	adds	r6, r1, r0
	ldrh.w	r1, [sp, #0x2]
	adds	r5, r1, r0
	add	r0, sp, #0x10
	bl	fn_0801f344
	mov.w	r8, #0x20000
	add	r2, sp, #0x10
	mov	r1, r8
	mov	r0, r4
	bl	fn_0802516e
	mov	r0, r4
	movs	r2, #1
	mov	r1, r8
	bl	fn_08024bac
	sxth	r0, r0
	add.w	r0, r0, r0, lsr #31
	asrs	r7, r0, #1
	mov	r0, r4
	movs	r2, #4
	mov	r1, r8
	bl	fn_08024bac
	sxth	r0, r0
	add.w	r0, r0, r0, lsr #31
	subs	r1, r6, r7
	asrs	r0, r0, #1
	strh.w	r1, [sp, #0x54]
	subs	r1, r5, r0
	strh.w	r1, [sp, #0x56]
	adds	r1, r6, r7
	strh.w	r1, [sp, #0x58]
	add	r0, r5
	strh.w	r0, [sp, #0x5a]
	add	r2, sp, #0x54
	add	r1, sp, #0x10
	mov	r0, r9
	bl	fn_0801f31c
.L08023026:
	add	sp, #0x5c
	pop.w	{r4, r5, r6, r7, r8, r9, pc}
.L0802302c:
	.word d_08050f30

@ ----------------------------------------------------------------------------
@ fn_08023030 - stores a counter result and initialises a 0x10-byte block.
@ No parameters; no return value of its own. Reached only by the b.w at
@ 0x08020858 in the function at 0x0802084a.
@ Calls increment_counter_20000498(), stores the low byte of its result at
@ byte 0x20000566, then tail-calls init_header_aligned4(0x20014398, 0x10),
@ which returns to the caller of the function at 0x0802084a.
@ The two literals are 0x20000566 and 0x20014398; two padding bytes (0x0000)
@ precede them.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023030,"ax",%progbits
	.p2align 2
	.global fn_08023030
	.thumb_func
	.type fn_08023030, %function
fn_08023030:
	push	{r4, lr}
	bl	increment_counter_20000498
	ldr	r1, .L08023048
	strb	r0, [r1]
	pop.w	{r4, lr}
	movs	r1, #0x10
	ldr	r0, .L0802304c
	b.w	init_header_aligned4
	.short 0x0000  @ padding
.L08023048:
	.word 0x20000566
.L0802304c:
	.word 0x20014398

@ ----------------------------------------------------------------------------
@ fn_08023050 - sets flag bits in an object word and refreshes dependent state.
@ r0 = object, r1 = flag mask; r2 and r3 are pushed with r0 and r1 as a
@ 16-byte local area; the final pop reloads r0 from the stack word at sp+0
@ (the object, or the first word written by fn_08024232 when bit 4 is set),
@ so there is no defined return value.
@ Reads fn_080254b0(object) as before. When bit 0 of the mask is set calls
@ fn_08025400(object) before and after ORing the mask into the word at +0x1c.
@ When fn_080254b0 changed or the mask has bits 0x1800000 set, calls
@ fn_08023fa4(object) and fn_08025522 twice (second time with the object).
@ When bit 4 of the mask is set calls fn_08024232(object, sp, sp+8) and
@ fn_08025446 on both results.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023050,"ax",%progbits
	.global fn_08023050
	.thumb_func
	.type fn_08023050, %function
fn_08023050:
	push	{r0, r1, r2, r3, r4, r5, r6, lr}
	mov	r4, r1
	mov	r5, r0
	bl	fn_080254b0
	mov	r6, r0
	lsls	r0, r4, #31
	beq.n	.L08023066
	mov	r0, r5
	bl	fn_08025400
.L08023066:
	ldr	r0, [r5, #0x1c]
	orrs	r0, r4
	str	r0, [r5, #0x1c]
	lsls	r0, r4, #31
	beq.n	.L08023076
	mov	r0, r5
	bl	fn_08025400
.L08023076:
	mov	r0, r5
	bl	fn_080254b0
	cmp	r0, r6
	bne.n	.L08023086
	tst.w	r4, #0x1800000
	beq.n	.L08023096
.L08023086:
	mov	r0, r5
	bl	fn_08023fa4
	bl	fn_08025522
	mov	r0, r5
	bl	fn_08025522
.L08023096:
	lsls	r0, r4, #27
	bpl.n	.L080230b4
	add	r2, sp, #0x8
	mov	r1, sp
	mov	r0, r5
	bl	fn_08024232
	mov	r1, sp
	mov	r0, r5
	bl	fn_08025446
	add	r1, sp, #0x8
	mov	r0, r5
	bl	fn_08025446
.L080230b4:
	pop	{r0, r1, r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_080230b6 - ORs a mask into the halfword at +0x20 of an object (via a
@ helper).
@ r0 = object, r1 = mask; no return value.
@ Reads the halfword h at +0x20; when h | mask differs from h tail-calls
@ fn_080263c0(object, h | mask), otherwise returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_080230b6,"ax",%progbits
	.global fn_080230b6
	.thumb_func
	.type fn_080230b6, %function
fn_080230b6:
	ldrh	r2, [r0, #0x20]
	orrs	r1, r2
	cmp	r2, r1
	beq.n	.L080230c2
	b.w	fn_080263c0
.L080230c2:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_080230c4 - inserts a new 8-byte entry into the table at +0xc of an
@ object.
@ r0 = object, r1 = word, r2 = value; no return value.
@ Calls fn_0802ac24(object, value, 0xffff, 0). Finds the first entry of the
@ 8-byte table at +0xc whose word +4 has neither bit 25 nor bit 24 set (the
@ entry count is bits 3..8 of the halfword at +0x22). Increments that count
@ by 1 (stored back into the halfword at +0x22), resizes the table with
@ fn_08022cb0(table, count * 8), shifts the entries above the insert index up
@ by one, clears the slot with clear_bytes(slot, 8), writes word +0 = r1 and
@ the low 24 bits of word +4 = value & 0xffffff, then tail-calls fn_08025d34
@ (object, value, 0xffff).
@ ----------------------------------------------------------------------------
	.section .text.fn_080230c4,"ax",%progbits
	.p2align 2
	.global fn_080230c4
	.thumb_func
	.type fn_080230c4, %function
fn_080230c4:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r7, r2
	mov	r8, r1
	movw	r9, #0xffff
	mov	r4, r0
	movs	r3, #0
	mov	r2, r9
	mov	r1, r7
	bl	fn_0802ac24
	ldrh	r1, [r4, #0x22]
	movs	r5, #0
	movs	r6, #4
	ubfx	r2, r1, #3, #6
	ldr	r0, [r4, #0xc]
	b.n	.L080230fe
	nop  @ padding
.L080230ec:
	add.w	r3, r6, r5, lsl #3
	ldr	r3, [r0, r3]
	lsls.w	ip, r3, #6
	bmi.n	.L080230fc
	lsls	r3, r3, #7
	bpl.n	.L08023102
.L080230fc:
	.inst.n 0x1c6d  @ adds r5, r5, #1
.L080230fe:
	cmp	r2, r5
	bhi.n	.L080230ec
.L08023102:
	mov.w	r2, #0x4000000
	add.w	r1, r2, r1, ror #9
	ror.w	r1, r1, #0x17
	strh	r1, [r4, #0x22]
	ubfx	r1, r1, #3, #6
	lsls	r1, r1, #3
	bl	fn_08022cb0
	str	r0, [r4, #0xc]
	ldrh	r0, [r4, #0x22]
	mvn	r2, #7
	ubfx	r0, r0, #3, #6
	b.n	.L0802313c
.L08023128:
	ldr	r1, [r4, #0xc]
	add.w	ip, r2, r0, lsl #3
	add.w	r3, r1, r0, lsl #3
	add	r1, ip
	ldrd	ip, r1, [r1]
	strd	ip, r1, [r3]
.L0802313c:
	.inst.n 0x1e40  @ subs r0, r0, #1
	cmp	r0, r5
	bhi.n	.L08023128
	ldr	r0, [r4, #0xc]
	movs	r1, #8
	add.w	r0, r0, r5, lsl #3
	bl	clear_bytes
	ldr	r1, [r4, #0xc]
	str.w	r8, [r1, r5, lsl #3]
	ldr	r0, [r4, #0xc]
	add.w	r1, r6, r5, lsl #3
	ldr	r2, [r0, r1]
	bfi	r2, r7, #0, #24
	str	r2, [r0, r1]
	mov	r2, r9
	mov	r1, r7
	mov	r0, r4
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	b.w	fn_08025d34

@ ----------------------------------------------------------------------------
@ fn_08023170 - calls two helpers in sequence with forwarded arguments.
@ r0..r3 = param_1..param_4; no return value.
@ Calls fn_08026570(r0, r1, 0), then tail-calls fn_0802636a(r0, r2, r3).
@ ----------------------------------------------------------------------------
	.section .text.fn_08023170,"ax",%progbits
	.p2align 2
	.global fn_08023170
	.thumb_func
	.type fn_08023170, %function
fn_08023170:
	push	{r4, r5, r6, lr}
	mov	r6, r2
	mov	r5, r3
	mov	r4, r0
	movs	r2, #0
	bl	fn_08026570
	mov	r2, r5
	mov	r1, r6
	mov	r0, r4
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0802636a

@ ----------------------------------------------------------------------------
@ fn_0802318c - creates the 0x1c-byte data block at +8 of an object when
@ missing.
@ r0 = object; no return value.
@ When the word at +8 is 0: increments the word at 0x20000460 (the literal
@ 0x2000045c plus 4), allocates 0x1c bytes with fn_08022b50 into the word
@ at +8, and when the allocation succeeded clears it (clear_bytes, 0x1c),
@ sets byte +0x19 to 0xf and sets bits 0 and 1 of byte +0x18.
@ The literal at 0x080231c4 is 0x2000045c; two padding bytes precede it.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802318c,"ax",%progbits
	.p2align 2
	.global fn_0802318c
	.thumb_func
	.type fn_0802318c, %function
fn_0802318c:
	push	{r4, lr}
	mov	r4, r0
	ldr	r0, [r0, #0x8]
	cmp	r0, #0
	bne.n	.L080231c0
	ldr	r0, .L080231c4
	ldr	r1, [r0, #0x4]
	.inst.n 0x1c49  @ adds r1, r1, #1
	str	r1, [r0, #0x4]
	movs	r0, #0x1c
	bl	fn_08022b50
	str	r0, [r4, #0x8]
	cmp	r0, #0
	beq.n	.L080231c0
	movs	r1, #0x1c
	bl	clear_bytes
	ldr	r1, [r4, #0x8]
	movs	r0, #0xf
	strb	r0, [r1, #0x19]
	ldr	r0, [r4, #0x8]
	ldrb	r1, [r0, #0x18]
	orr.w	r1, r1, #3
	strb	r1, [r0, #0x18]
.L080231c0:
	pop	{r4, pc}
	.short 0x0000  @ padding
.L080231c4:
	.word 0x2000045c

@ ----------------------------------------------------------------------------
@ fn_080231c8 - clips a rectangle against an object and each of its parents.
@ r0 = object (r5), r1 = rectangle pointer (r6, read and written); r2 and r3
@ are only pushed with r4..r8 to reserve 8 bytes of stack used as a local
@ rectangle (sp+0..7). Returns r0 = 1 when the walk to the top finishes, 0
@ otherwise.
@ all_flag_bits_set(object, 1) nonzero returns 0. r4 = fn_08023fac(object),
@ r7 = fn_08023ebc(object); continues only when one of fn_0801dd5c(r7),
@ fn_0801dd6c(r7), fn_0801dd38(r7), fn_0801dd28(r7) equals r4, else returns 0.
@ r4 = 0x80000; when any_flag_bit_set(object, 0x80000) is zero: r7 =
@ fn_08012726(object), copy_rect_0801cfa0(sp, object + 0x14) fills the local
@ rectangle, halfwords sp+0 and sp+2 are decreased by r7 and halfwords sp+4
@ and sp+6 increased by r7, then rect_intersect(r6, r6, sp) zero returns 0.
@ Then fn_08024d50(object, r6, 1, 0).
@ Loop: r5 = fn_08023fa4(r5) (parent); zero ends with return 1. For each
@ parent: all_flag_bits_set(parent, 1) nonzero returns 0; when
@ any_flag_bit_set(parent, 0x80000) is zero the two words at parent+0x14 and
@ parent+0x18 are copied to sp+0..7, fn_08024d50(parent, sp, 1, 0) is called
@ and rect_intersect(r6, r6, sp) zero returns 0; the loop then repeats.
@ ----------------------------------------------------------------------------
	.section .text.fn_080231c8,"ax",%progbits
	.p2align 2
	.global fn_080231c8
	.thumb_func
	.type fn_080231c8, %function
fn_080231c8:
	push.w	{r2, r3, r4, r5, r6, r7, r8, lr}
	mov	r6, r1
	mov	r5, r0
	movs	r1, #1
	bl	all_flag_bits_set
	cbnz	r0, .L08023252
	mov	r0, r5
	bl	fn_08023fac
	mov	r4, r0
	bl	fn_08023ebc
	mov	r7, r0
	bl	fn_0801dd5c
	cmp	r0, r4
	beq.n	.L0802320c
	mov	r0, r7
	bl	fn_0801dd6c
	cmp	r0, r4
	beq.n	.L0802320c
	mov	r0, r7
	bl	fn_0801dd38
	cmp	r0, r4
	beq.n	.L0802320c
	mov	r0, r7
	bl	fn_0801dd28
	cmp	r0, r4
	bne.n	.L0802327c
.L0802320c:
	mov.w	r4, #0x80000
	mov	r1, r4
	mov	r0, r5
	bl	any_flag_bit_set
	cbnz	r0, .L08023266
	mov	r0, r5
	bl	fn_08012726
	mov	r7, r0
	add.w	r1, r5, #0x14
	mov	r0, sp
	bl	copy_rect_0801cfa0
	ldrh.w	r0, [sp]
	subs	r0, r0, r7
	strh.w	r0, [sp]
	ldrh.w	r0, [sp, #0x2]
	subs	r0, r0, r7
	strh.w	r0, [sp, #0x2]
	ldrh.w	r0, [sp, #0x4]
	add	r0, r7
	strh.w	r0, [sp, #0x4]
	ldrh.w	r0, [sp, #0x6]
	add	r0, r7
	b.n	.L08023254
.L08023252:
	b.n	.L0802327c
.L08023254:
	strh.w	r0, [sp, #0x6]
	mov	r1, r6
	mov	r2, sp
	mov	r0, r1
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L0802327e
.L08023266:
	movs	r3, #0
	movs	r2, #1
	mov	r1, r6
	mov	r0, r5
	bl	fn_08024d50
	b.n	.L080232ae
.L08023274:
	movs	r1, #1
	bl	all_flag_bits_set
	cbz	r0, .L08023282
.L0802327c:
	movs	r0, #0
.L0802327e:
	pop.w	{r2, r3, r4, r5, r6, r7, r8, pc}
.L08023282:
	mov	r1, r4
	mov	r0, r5
	bl	any_flag_bit_set
	cbnz	r0, .L080232ae
	ldrd	r0, r1, [r5, #0x14]
	strd	r0, r1, [sp]
	movs	r3, #0
	movs	r2, #1
	mov	r1, sp
	mov	r0, r5
	bl	fn_08024d50
	mov	r1, r6
	mov	r2, sp
	mov	r0, r1
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L0802327e
.L080232ae:
	mov	r0, r5
	bl	fn_08023fa4
	subs	r5, r0, #0
	bne.n	.L08023274
	movs	r0, #1
	b.n	.L0802327e

@ ----------------------------------------------------------------------------
@ fn_080232bc - computes a signed 16-bit size from object parts.
@ r0 = first argument (r7), r1 = second argument (r6), both passed unchanged
@ to every call; returns r0 = the sum as a signed 16-bit value (r5).
@ r5 = 0; r4 = fn_08024c7c(r0, r1). When r4 != 0 and fn_08024c64(r0, r1) > 2
@ (unsigned): r4 = 1 + ((r4 + (r4 >>> 31)) >>a 1), r8 = sxth(fn_08024c70
@ (r0, r1) + r4), a = fn_08024c4c(r0, r1), b = fn_08024c58(r0, r1),
@ m = max(abs(a), abs(b)), r5 = sxth(m + r8), set to 0 when negative.
@ r4 = fn_08024a74(r0, r1); when r4 != 0 and fn_08024a5c(r0, r1) > 2
@ (unsigned): r0 = fn_08024a68(r0, r1) + r4; r5 = sxth(r0) when r0 >= r5
@ (signed), else sxth(r5).
@ r4 = sxth fn_08024bac(r0, r1, 0x68), r0 = sxth fn_08024bac(r0, r1, 0x69);
@ r4 = max(r4, r0) (signed); when r4 > 0, r5 = sxth(r5 + r4). Returns r5.
@ ----------------------------------------------------------------------------
	.section .text.fn_080232bc,"ax",%progbits
	.p2align 2
	.global fn_080232bc
	.thumb_func
	.type fn_080232bc, %function
fn_080232bc:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r6, r1
	mov	r7, r0
	movs	r5, #0
	bl	fn_08024c7c
	movs	r4, r0
	beq.n	.L0802333a
	mov	r1, r6
	mov	r0, r7
	bl	fn_08024c64
	cmp	r0, #2
	bls.n	.L0802333a
	add.w	r0, r4, r4, lsr #31
	movs	r1, #1
	add.w	r4, r1, r0, asr #1
	mov	r1, r6
	mov	r0, r7
	bl	fn_08024c70
	add	r0, r4
	sxth.w	r8, r0
	mov	r1, r6
	mov	r0, r7
	bl	fn_08024c4c
	mov	r4, r0
	mov	r1, r6
	mov	r0, r7
	bl	fn_08024c58
	cmp	r4, #0
	ble.n	.L0802330c
	mov	r1, r4
	b.n	.L0802330e
.L0802330c:
	rsbs	r1, r4, #0
.L0802330e:
	cmp	r0, #0
	ble.n	.L08023316
	mov	r2, r0
	b.n	.L08023318
.L08023316:
	rsbs	r2, r0, #0
.L08023318:
	cmp	r1, r2
	ble.n	.L08023328
	cmp	r4, #0
	ble.n	.L08023324
	mov	r0, r4
	b.n	.L0802332e
.L08023324:
	rsbs	r0, r4, #0
	b.n	.L0802332e
.L08023328:
	cmp	r0, #0
	bgt.n	.L0802332e
	rsbs	r0, r0, #0
.L0802332e:
	add	r0, r8
	sxth	r0, r0
	cmp	r0, #0
	bge.n	.L08023338
	mov	r0, r5
.L08023338:
	mov	r5, r0
.L0802333a:
	mov	r1, r6
	mov	r0, r7
	bl	fn_08024a74
	movs	r4, r0
	beq.n	.L08023364
	mov	r1, r6
	mov	r0, r7
	bl	fn_08024a5c
	cmp	r0, #2
	bls.n	.L08023364
	mov	r1, r6
	mov	r0, r7
	bl	fn_08024a68
	add	r0, r4
	cmp	r0, r5
	blt.n	.L08023362
	mov	r5, r0
.L08023362:
	sxth	r5, r5
.L08023364:
	mov	r0, r7
	mov	r1, r6
	movs	r2, #0x68
	bl	fn_08024bac
	sxth	r4, r0
	mov	r0, r7
	mov	r1, r6
	movs	r2, #0x69
	bl	fn_08024bac
	sxth	r0, r0
	cmp	r4, r0
	bgt.n	.L08023382
	mov	r4, r0
.L08023382:
	cmp	r4, #0
	ble.n	.L0802338a
	adds	r0, r5, r4
	sxth	r5, r0
.L0802338a:
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_08023390 - returns a byte value of an object part, or 1 when it is 0.
@ r0 = object, r1 = part; returns r0 = byte (r4).
@ Calls fn_08024bac(object, part, 0x5b) and keeps its low byte; calls
@ fn_08024bac(object, part, 0x16) with the result unused; returns the 0x5b
@ value, or 1 when it is 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023390,"ax",%progbits
	.p2align 2
	.global fn_08023390
	.thumb_func
	.type fn_08023390, %function
fn_08023390:
	push	{r4, r5, r6, lr}
	mov	r5, r1
	mov	r6, r0
	movs	r2, #0x5b
	bl	fn_08024bac
	uxtb	r4, r0
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x16
	bl	fn_08024bac
	cbnz	r4, .L080233ac
	movs	r4, #1
.L080233ac:
	mov	r0, r4
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_080233b0 - tests whether the first word of an object equals a value.
@ r0 = object pointer, r1 = value; returns 1 when r0 is nonzero and its
@ first word equals r1, else 0 (returns r0 = 0 unchanged when r0 is 0).
@ Two padding bytes (0x0000) follow the code.
@ ----------------------------------------------------------------------------
	.section .text.fn_080233b0,"ax",%progbits
	.p2align 2
	.global fn_080233b0
	.thumb_func
	.type fn_080233b0, %function
fn_080233b0:
	cmp	r0, #0
	beq.n	.L080233bc
	ldr	r0, [r0]
	cmp	r0, r1
	bne.n	.L080233be
	movs	r0, #1
.L080233bc:
	bx	lr
.L080233be:
	movs	r0, #0
	bx	lr
	.short 0x0000  @ padding

@ ----------------------------------------------------------------------------
@ fn_080233c4 - creates an object from a class and links it to its parent.
@ r0 = class pointer, r1 = parent object; returns r0 = the new object or 0.
@ Walks the class chain (first word of each class) for the first class whose
@ word +0x18 has bits 4..19 set (mask 0x000ffff0, literal at 0x080234a8); the
@ size is bits 4..19 of that word. When the chain ends, the size is 0.
@ Allocates the object with fn_08022b50 (returns 0 when that fails), clears
@ it with clear_bytes(object, size), stores the class at +0 and the parent
@ at +4.
@ No parent: gets the root with fn_0801dccc(); when that is 0 releases the
@ object with fn_08022c68 and returns 0. Otherwise appends the object to the
@ root's list at +0xc (count at +0x24): when the list is empty a 4-byte list
@ is allocated with fn_08022b50(4) and the count set to 1, else the count is
@ incremented and the list resized with fn_08022cb0(list, count * 4) and the
@ object stored in the last slot. Sets the object's halfwords +0x14 = 0,
@ +0x16 = 0, +0x18 = fn_0801dcfc(0) - 1 and +0x1a = fn_0801dd88(0) - 1.
@ With a parent: creates the parent's data block via fn_0802318c when the
@ word at parent+8 is 0, then appends the object to the list pointed to by
@ the first word of that block (count at block +4), allocating a 4-byte list
@ with fn_08022b50(4) when empty (count 1) or resizing it with fn_08022cb0
@ (list, count * 4) otherwise.
@ ----------------------------------------------------------------------------
	.section .text.fn_080233c4,"ax",%progbits
	.p2align 2
	.global fn_080233c4
	.thumb_func
	.type fn_080233c4, %function
fn_080233c4:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r5, r1
	mov	r7, r0
	movs	r6, #0
	ldr	r1, .L080234a8
	b.n	.L080233d4
.L080233d2:
	ldr	r0, [r0]
.L080233d4:
	cbz	r0, .L08023406
	ldr	r2, [r0, #0x18]
	tst	r2, r1
	beq.n	.L080233d2
	ldr	r0, [r0, #0x18]
	ubfx	r0, r0, #4, #16
.L080233e2:
	mov	r8, r0
	bl	fn_08022b50
	subs	r4, r0, #0
	beq.n	.L08023450
	mov	r1, r8
	bl	clear_bytes
	strd	r7, r5, [r4]
	mov.w	r8, #1
	mvn	r7, #3
	cbz	r5, .L0802340a
	ldr	r0, [r5, #0x8]
	cbz	r0, .L08023464
	b.n	.L0802346c
.L08023406:
	mov	r0, r6
	b.n	.L080233e2
.L0802340a:
	bl	fn_0801dccc
	movs	r5, r0
	beq.n	.L08023448
	ldr	r2, [r5, #0xc]
	cbz	r2, .L08023454
	ldr	r0, [r5, #0x24]
	.inst.n 0x1c40  @ adds r0, r0, #1
	lsls	r1, r0, #2
	str	r0, [r5, #0x24]
	mov	r0, r2
	bl	fn_08022cb0
	str	r0, [r5, #0xc]
	ldr	r1, [r5, #0x24]
	add.w	r1, r7, r1, lsl #2
	str	r4, [r0, r1]
.L0802342e:
	strh	r6, [r4, #0x14]
	strh	r6, [r4, #0x16]
	movs	r0, #0
	bl	fn_0801dcfc
	.inst.n 0x1e40  @ subs r0, r0, #1
	strh	r0, [r4, #0x18]
	movs	r0, #0
	bl	fn_0801dd88
	.inst.n 0x1e40  @ subs r0, r0, #1
	strh	r0, [r4, #0x1a]
	b.n	.L08023490
.L08023448:
	mov	r0, r4
	bl	fn_08022c68
	movs	r0, #0
.L08023450:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08023454:
	movs	r0, #4
	bl	fn_08022b50
	str	r0, [r5, #0xc]
	str	r4, [r0]
	str.w	r8, [r5, #0x24]
	b.n	.L0802342e
.L08023464:
	b.n	.L08023466
.L08023466:
	mov	r0, r5
	bl	fn_0802318c
.L0802346c:
	ldr	r0, [r5, #0x8]
	ldr	r1, [r0]
	cbz	r1, .L08023494
	ldr	r1, [r0, #0x4]
	.inst.n 0x1c49  @ adds r1, r1, #1
	str	r1, [r0, #0x4]
	ldr	r0, [r5, #0x8]
	lsls	r1, r1, #2
	ldr	r0, [r0]
	bl	fn_08022cb0
	ldr	r1, [r5, #0x8]
	str	r0, [r1]
	ldr	r1, [r5, #0x8]
	ldr	r1, [r1, #0x4]
	add.w	r1, r7, r1, lsl #2
	str	r4, [r0, r1]
.L08023490:
	mov	r0, r4
	b.n	.L08023450
.L08023494:
	movs	r0, #4
	bl	fn_08022b50
	ldr	r1, [r5, #0x8]
	str	r0, [r1]
	str	r4, [r0]
	ldr	r1, [r5, #0x8]
	str.w	r8, [r1, #0x4]
	b.n	.L08023490
.L080234a8:
	.word 0x000ffff0

@ ----------------------------------------------------------------------------
@ fn_080234ac - finishes setting up an object and notifies its parent.
@ r0 = object (r5); no return value.
@ Calls fn_08025522(), store_byte_200004b0(0), fn_0802768c(object),
@ fn_080235dc(object), store_byte_200004b0(1), fn_08025d34(object, 0xf0000,
@ 0xffff) and fn_08025d04(object). When read_word_200004a0() (r3) is nonzero
@ and fn_08025494(object) is nonzero calls fn_08020f74(r3, object).
@ Then, when fn_08023fa4(object) gives a parent, sends fn_080207f4(parent,
@ 0x22, object) and fn_080207f4(parent, 0x23, object) and tail-calls
@ fn_08025400(object).
@ ----------------------------------------------------------------------------
	.section .text.fn_080234ac,"ax",%progbits
	.p2align 2
	.global fn_080234ac
	.thumb_func
	.type fn_080234ac, %function
fn_080234ac:
	push	{r4, r5, r6, lr}
	mov	r5, r0
	bl	fn_08025522
	movs	r0, #0
	bl	store_byte_200004b0
	mov	r0, r5
	bl	fn_0802768c
	mov	r0, r5
	bl	fn_080235dc
	movs	r0, #1
	bl	store_byte_200004b0
	movw	r2, #0xffff
	mov.w	r1, #0xf0000
	mov	r0, r5
	bl	fn_08025d34
	mov	r0, r5
	bl	fn_08025d04
	bl	read_word_200004a0
	movs	r3, r0
	beq.n	.L080234f8
	mov	r0, r5
	bl	fn_08025494
	cbz	r0, .L080234f8
	mov	r1, r5
	mov	r0, r3
	bl	fn_08020f74
.L080234f8:
	mov	r0, r5
	bl	fn_08023fa4
	movs	r4, r0
	beq.n	.L0802351e
	mov	r2, r5
	movs	r1, #0x22
	bl	fn_080207f4
	mov	r2, r5
	movs	r1, #0x23
	mov	r0, r4
	bl	fn_080207f4
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08025400
.L0802351e:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08023520 - removes all children of an object and clears its data counters.
@ r0 = object (r4); no return value.
@ Calls fn_08025400(object), then while fn_08023d80(object, 0) returns a child
@ calls fn_080289ae(child); then calls fn_08026216(object, 0, 0, 0) and, when
@ the word at +8 is nonzero, clears the halfwords +0x10 and +0x12 of that
@ data block.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023520,"ax",%progbits
	.p2align 2
	.global fn_08023520
	.thumb_func
	.type fn_08023520, %function
fn_08023520:
	push	{r4, lr}
	mov	r4, r0
	bl	fn_08025400
	b.n	.L08023530
	nop  @ padding
.L0802352c:
	bl	fn_080289ae
.L08023530:
	movs	r1, #0
	mov	r0, r4
	bl	fn_08023d80
	cmp	r0, #0
	bne.n	.L0802352c
	movs	r3, #0
	mov	r2, r3
	mov	r1, r3
	mov	r0, r4
	bl	fn_08026216
	ldr	r0, [r4, #0x8]
	cmp	r0, #0
	beq.n	.L08023556
	movs	r1, #0
	strh	r1, [r0, #0x10]
	ldr	r0, [r4, #0x8]
	strh	r1, [r0, #0x12]
.L08023556:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08023558 - clears flag bits in an object word and refreshes dependent
@ state.
@ r0 = object (r6), r1 = flag mask (r4); r2 and r3 are pushed with r0 and r1
@ as a 16-byte local area (sp+0..0xf). Returns what the final helper call
@ returns.
@ Reads r5 = fn_080254b0(object). When bit 4 of the mask is set calls
@ fn_08024232(object, sp, sp+8) and fn_08025446 on both results. Clears the
@ mask bits in the word +0x1c. When bit 0 of the mask is set calls
@ fn_08025400(object) and, if fn_080254b0(object) is nonzero, fn_08023fa4
@ (object) and fn_08025522 twice (second time with the object).
@ When fn_080254b0(object) differs from r5 or the mask has bits 0x1800000,
@ calls fn_08023fa4(object) and tail-calls fn_08025522 (after releasing the
@ 16-byte local area); otherwise pops the stack words r0..r6 and returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023558,"ax",%progbits
	.p2align 2
	.global fn_08023558
	.thumb_func
	.type fn_08023558, %function
fn_08023558:
	push	{r0, r1, r2, r3, r4, r5, r6, lr}
	mov	r4, r1
	mov	r6, r0
	bl	fn_080254b0
	mov	r5, r0
	lsls	r0, r4, #27
	bpl.n	.L08023582
	add	r2, sp, #0x8
	mov	r1, sp
	mov	r0, r6
	bl	fn_08024232
	mov	r1, sp
	mov	r0, r6
	bl	fn_08025446
	add	r1, sp, #0x8
	mov	r0, r6
	bl	fn_08025446
.L08023582:
	ldr	r0, [r6, #0x1c]
	bics	r0, r4
	str	r0, [r6, #0x1c]
	lsls	r0, r4, #31
	beq.n	.L080235aa
	mov	r0, r6
	bl	fn_08025400
	mov	r0, r6
	bl	fn_080254b0
	cbz	r0, .L080235aa
	mov	r0, r6
	bl	fn_08023fa4
	bl	fn_08025522
	mov	r0, r6
	bl	fn_08025522
.L080235aa:
	mov	r0, r6
	bl	fn_080254b0
	cmp	r0, r5
	bne.n	.L080235ba
	tst.w	r4, #0x1800000
	beq.n	.L080235ca
.L080235ba:
	mov	r0, r6
	bl	fn_08023fa4
	add	sp, #0x10
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08025522
.L080235ca:
	pop	{r0, r1, r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_080235cc - clears mask bits in the halfword at +0x20 of an object (via a
@ helper).
@ r0 = object, r1 = mask; no return value.
@ Reads the halfword h at +0x20; when h & ~mask differs from h tail-calls
@ fn_080263c0(object, h & ~mask), otherwise returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_080235cc,"ax",%progbits
	.p2align 2
	.global fn_080235cc
	.thumb_func
	.type fn_080235cc, %function
fn_080235cc:
	ldrh	r2, [r0, #0x20]
	bic.w	r1, r2, r1
	cmp	r2, r1
	beq.n	.L080235da
	b.w	fn_080263c0
.L080235da:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_080235dc - recursive walk down a node chain, then calls the node handler.
@ r0 = pointer to a node pointer (r5); no return value.
@ Loads the node r4 = *r0. While the first word of the node is nonzero it
@ stores that word into *r0 and recurses with r0. Afterwards stores the node
@ back into *r0 and, when the word at node+4 is nonzero, pops the frame and
@ jumps (bx r2) to that function with r0 = node, r1 = r0 pointer.
@ Two padding bytes (0x0000) follow the code.
@ ----------------------------------------------------------------------------
	.section .text.fn_080235dc,"ax",%progbits
	.p2align 2
	.global fn_080235dc
	.thumb_func
	.type fn_080235dc, %function
fn_080235dc:
	push	{r4, r5, r6, lr}
	ldr	r4, [r0]
	mov	r5, r0
	ldr	r0, [r4]
	cbz	r0, .L080235ee
	str	r0, [r5]
	mov	r0, r5
	bl	fn_080235dc
.L080235ee:
	str	r4, [r5]
	ldr	r2, [r4, #0x4]
	mov	r0, r4
	cmp	r2, #0
	beq.n	.L08023600
	mov	r1, r5
	pop.w	{r4, r5, r6, lr}
	bx	r2
.L08023600:
	pop	{r4, r5, r6, pc}
	.short 0x0000  @ padding

@ ----------------------------------------------------------------------------
@ fn_08023604 - positions a new object relative to its parent and sets its
@ flag word.
@ r1 = object (r4, r0 not used); no return value.
@ r5 = word at +4 (parent). When the parent is nonzero: r6 =
@ fn_08024070(parent), r7 = fn_08024208(parent); halfword +0x16 = parent
@ halfword +0x16 + fn_08024bac(parent, 0, 0x10) - r7, halfword +0x1a =
@ halfword +0x16 - 1; halfword +0x14 = parent halfword +0x14 +
@ fn_08024bac(parent, 0, 0x12) - r6, halfword +0x18 = halfword +0x14 - 1.
@ Then the word +0x1c is set to 0x1002 (0x3002 and then 0x3302 with a
@ parent), then ORed with 0x74 and 0x800 (0x1876 without a parent, 0x3b76
@ with a parent) and, with a parent, ORed with 0x8000 (0xbb76).
@ ----------------------------------------------------------------------------
	.section .text.fn_08023604,"ax",%progbits
	.p2align 2
	.global fn_08023604
	.thumb_func
	.type fn_08023604, %function
fn_08023604:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r5, [r1, #0x4]
	mov	r4, r1
	cbz	r5, .L0802364a
	mov	r0, r5
	bl	fn_08024070
	mov	r6, r0
	mov	r0, r5
	bl	fn_08024208
	mov	r7, r0
	mov	r0, r5
	movs	r1, #0
	movs	r2, #0x10
	bl	fn_08024bac
	ldrh	r1, [r5, #0x16]
	movs	r2, #0x12
	add	r0, r1
	subs	r0, r0, r7
	strh	r0, [r4, #0x16]
	.inst.n 0x1e40  @ subs r0, r0, #1
	strh	r0, [r4, #0x1a]
	mov	r0, r5
	movs	r1, #0
	bl	fn_08024bac
	ldrh	r1, [r5, #0x14]
	add	r0, r1
	subs	r0, r0, r6
	strh	r0, [r4, #0x14]
	.inst.n 0x1e40  @ subs r0, r0, #1
	strh	r0, [r4, #0x18]
.L0802364a:
	movw	r0, #0x1002
	str	r0, [r4, #0x1c]
	cmp	r5, #0
	beq.n	.L08023662
	movw	r0, #0x3002
	str.w	r0, [r4, #0x1c]
	movw	r0, #0x3302
	str	r0, [r4, #0x1c]
.L08023662:
	orr.w	r0, r0, #0x74
	orr.w	r0, r0, #0x800
	str	r0, [r4, #0x1c]
	beq.n	.L08023674
	orr.w	r0, r0, #0x8000
	str	r0, [r4, #0x1c]
.L08023674:
	pop.w	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_08023678 - creates an object of the class at 0x0804fcfc and sets it up.
@ r0 = argument (passed as the parent to fn_080233c4); returns r0 = the
@ created object (r4).
@ Calls fn_080233c4(0x0804fcfc, r0) (literal at 0x0802368c), then
@ fn_080234ac(object) with the result still in r0, and returns the object.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023678,"ax",%progbits
	.p2align 2
	.global fn_08023678
	.thumb_func
	.type fn_08023678, %function
fn_08023678:
	push	{r4, lr}
	mov	r1, r0
	ldr	r0, .L0802368c
	bl	fn_080233c4
	mov	r4, r0
	bl	fn_080234ac
	mov	r0, r4
	pop	{r4, pc}
.L0802368c:
	.word d_0804fcfc

@ ----------------------------------------------------------------------------
@ fn_08023690 - removes an object from its parent (or from its container).
@ r0 = object (r5); no return value.
@ Calls fn_08025400(object); r4 = fn_08023fa4(object) (parent). With a
@ parent: calls fn_080262c4(), fn_080289ae(object), fn_080267c0(parent),
@ fn_080256cc(parent, 0), fn_080262c4(parent), fn_080207f4(parent, 0x22, 0)
@ and tail-calls fn_080207f4(parent, 0x24, 0).
@ Without a parent: r4 = fn_08023ebc(object) gives a container; when it is
@ nonzero calls fn_080289ae(object) and, when the container word +0x10
@ equalled the object, clears that word to 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023690,"ax",%progbits
	.p2align 2
	.global fn_08023690
	.thumb_func
	.type fn_08023690, %function
fn_08023690:
	push	{r4, r5, r6, lr}
	mov	r5, r0
	bl	fn_08025400
	mov	r0, r5
	bl	fn_08023fa4
	movs	r4, r0
	beq.n	.L080236a6
	bl	fn_080262c4
.L080236a6:
	mov	r0, r5
	cbz	r4, .L080236da
	bl	fn_080289ae
	mov	r0, r4
	bl	fn_080267c0
	movs	r1, #0
	mov	r0, r4
	bl	fn_080256cc
	mov	r0, r4
	bl	fn_080262c4
	movs	r2, #0
	movs	r1, #0x22
	mov	r0, r4
	bl	fn_080207f4
	mov	r0, r4
	pop.w	{r4, r5, r6, lr}
	movs	r2, #0
	movs	r1, #0x24
	b.w	fn_080207f4
.L080236da:
	bl	fn_08023ebc
	movs	r4, r0
	beq.n	.L080236f2
	ldr	r0, [r4, #0x10]
	cmp	r0, r5
	mov	r0, r5
	bne.n	.L080236f4
	bl	fn_080289ae
	movs	r0, #0
	str	r0, [r4, #0x10]
.L080236f2:
	pop	{r4, r5, r6, pc}
.L080236f4:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_080289ae

@ ----------------------------------------------------------------------------
@ fn_080236fc - tears down an object's resources.
@ r1 = object (r4; r0 not used); no return value.
@ Calls fn_0801229c(object), store_byte_200004b0(0), fn_08025ede(object, 0,
@ 0xfffff) (literal 0x000fffff at 0x08023760), store_byte_200004b0(1) and
@ fn_0801c688(object, 0). When fn_08023f18(object) is nonzero calls
@ fn_0802108c(object). When the word at object+8 is nonzero: releases the
@ block at the first word of that data block with fn_08022c68 and zeroes it
@ when nonzero, does the same for the word at data block +0xc, then releases
@ the data block itself with fn_08022c68 and zeroes object+8.
@ ----------------------------------------------------------------------------
	.section .text.fn_080236fc,"ax",%progbits
	.p2align 2
	.global fn_080236fc
	.thumb_func
	.type fn_080236fc, %function
fn_080236fc:
	push	{r4, r5, r6, lr}
	mov	r4, r1
	mov	r0, r1
	bl	fn_0801229c
	movs	r0, #0
	bl	store_byte_200004b0
	mov	r0, r4
	ldr	r2, .L08023760
	movs	r1, #0
	bl	fn_08025ede
	movs	r0, #1
	bl	store_byte_200004b0
	movs	r1, #0
	mov	r0, r4
	bl	fn_0801c688
	mov	r0, r4
	bl	fn_08023f18
	cbz	r0, .L08023732
	mov	r0, r4
	bl	fn_0802108c
.L08023732:
	ldr	r0, [r4, #0x8]
	cmp	r0, #0
	beq.n	.L0802375c
	ldr	r0, [r0]
	movs	r5, #0
	cbz	r0, .L08023746
	bl	fn_08022c68
	ldr	r0, [r4, #0x8]
	str	r5, [r0]
.L08023746:
	ldr	r0, [r4, #0x8]
	ldr	r0, [r0, #0xc]
	cbz	r0, .L08023754
	bl	fn_08022c68
	ldr	r0, [r4, #0x8]
	str	r5, [r0, #0xc]
.L08023754:
	ldr	r0, [r4, #0x8]
	bl	fn_08022c68
	str	r5, [r4, #0x8]
.L0802375c:
	pop	{r4, r5, r6, pc}
	.short 0x0000  @ padding
.L08023760:
	.word 0x000fffff

@ ----------------------------------------------------------------------------
@ fn_08023764 - object type handler for types 0x12, 0x15 and 0x18.
@ r0 = object E (kept in r8); no return value. Stack frame 0x88 (the
@ rectangle of four halfwords lives at sp+0, a record at sp+8, a call record
@ at sp+0x40). r6 = t = get_byte8_low7(E), r5 = O = get_first_word(E),
@ r7 = 1, r4 = 0; r9 = 0x0804fcfc (literal 0x08023a08, loaded at 0x08023782
@ after the t = 0x12 test, so not set on the t = 0x12 path to case A).
@ t = 0x12 goes to case A (0x08023868), t = 0x15 to case C (0x08023902),
@ t = 0x18 to case B (0x0802378e); any other t returns at once (0x08023884).
@ 0x08023862 (b 0x08023868) and 0x08023866 (b 0x08023884) are two branches
@ that no instruction of the function targets.
@ Case B (t = 0x18): sl = get_word_10_if_byte_8_14_to_19(E); calls
@ fn_08018308(O, sl); when fn_080249a8(O, 0) is nonzero calls
@ fn_0801f2cc(O + 0x120) and, when that result (r6) is nonzero,
@ fn_0801ec98() and fn_08022c44(r6); returns when fn_08024974(O, 0) is 0;
@ else fn_0801f344(sp+8), stores 0 in bytes [sp+0xb], [sp+0x22], [sp+0x32],
@ [sp+0x3e], calls fn_0802516e(O, 0, sp+8), r8 = fn_08024cf0(O, 0), r6 =
@ fn_08024ce4(O, 0), copies the four halfwords at O+0x14 to sp with
@ copy_rect_0801cf8e, then halfwords [sp] -= r8, [sp+4] += r8, [sp+2] -= r6,
@ [sp+6] += r6; fn_08023a0c(sp+0x40, sl) clears 0x48 bytes and stores sl in
@ word [sp+0x40]; sets word [sp+0x44] = r9, [sp+0x48] = 1, [sp+0x4c] = sp,
@ [sp+0x50] = sp+8, [sp+0x74] = 0; calls fn_080207f4(O, 0x1a, sp+0x40) and
@ fn_0801f31c(sl, sp+8, sp), then (0x080239fc) fn_080207f4(O, 0x1b, sp+0x40)
@ and returns.
@ Case A (t = 0x12, 0x08023868): R = get_word_at_0x10(E); returns when byte
@ [R] = 2; when fn_080249a8(O, 0) is nonzero stores 2 in byte [R] and
@ returns; else sl = fn_08024c40(O, 0), r9 = fn_08024cf0(O, 0), r8 =
@ fn_08024ce4(O, 0), copies O+0x14 to sp, adjusts the halfwords [sp] -= r9,
@ [sp+4] += r9, [sp+2] -= r8, [sp+6] += r8, calls fn_08011e9c(word [R+4], sp,
@ sl); result 0: stores 1 in byte [R]; nonzero: stores 1 when fn_0802495c
@ (O, 0) is below 0xfd (unsigned compare, bcs at 0x080238f8), otherwise
@ stores 0; returns.
@ Case C (t = 0x15, 0x08023902): r8 = get_word_10_if_byte_8_14_to_19(E);
@ fn_0801f344(sp+8); when fn_08024974(O, 0) is nonzero sets bit 0 of byte
@ [sp+0x2b]; calls fn_0802516e(O, 0, sp+8), r6 = fn_08024cf0(O, 0), r7 =
@ fn_08024ce4(O, 0); copies O+0x14 to sp (sl = O+0x14); halfwords [sp] -= r6,
@ [sp+4] += r6, [sp+2] -= r7, [sp+6] += r7; fn_08023a0c(sp+0x40, r8); words
@ [sp+0x44] = r9, [sp+0x48] = 0, [sp+0x4c] = sp, [sp+0x50] = sp+8,
@ [sp+0x74] = 0; calls fn_080207f4(O, 0x1a, sp+0x40); when fn_080249a8(O, 0)
@ is nonzero and halfword [sp+8] is nonzero: r6 = word [sp+0x18], r7 = 1,
@ word [sp+0x18] = 0, else r6 = word [sp+0x18], r7 = 0; calls fn_0801f31c
@ (r8, sp+8, sp); r7 = 0 goes to 0x080239fc; else r7 = fn_08022bac(0x18),
@ calls fn_0801f1a8(r7, O+0x14, ldrsh [sp+8], 0) and fn_0801e910(r7,
@ O+0x120); r6 = 0 goes to 0x080239fc; else stores 0 in bytes [sp+0xb],
@ [sp+0x2a], [sp+0x32], [sp+0x3e], word [sp+0x18] = r6 and calls fn_0801f31c
@ (r8, sp+8, sp) once more (0x0802385c), then 0x080239fc: fn_080207f4(O,
@ 0x1b, sp+0x40) and return.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023764,"ax",%progbits
	.p2align 2
	.global fn_08023764
	.thumb_func
	.type fn_08023764, %function
fn_08023764:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	sub	sp, #0x88
	mov	r8, r0
	bl	get_byte8_low7
	mov	r6, r0
	mov	r0, r8
	bl	get_first_word
	movs	r7, #1
	movs	r4, #0
	mov	r5, r0
	cmp	r6, #0x12
	beq.n	.L08023868
	ldr.w	r9, .L08023a08
	cmp	r6, #0x15
	beq.n	.L08023864
	cmp	r6, #0x18
	bne.n	.L08023884
	mov	r0, r8
	bl	get_word_10_if_byte_8_14_to_19
	mov	r10, r0
	mov	r1, r0
	mov	r0, r5
	bl	fn_08018308
	movs	r1, #0
	mov	r0, r5
	bl	fn_080249a8
	cbz	r0, .L080237be
	add.w	r0, r5, #0x120
	bl	fn_0801f2cc
	movs	r6, r0
	beq.n	.L080237be
	bl	fn_0801ec98
	mov	r0, r6
	bl	fn_08022c44
.L080237be:
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024974
	cmp	r0, #0
	beq.n	.L08023884
	add	r0, sp, #0x8
	bl	fn_0801f344
	strb.w	r4, [sp, #0xb]
	strb.w	r4, [sp, #0x22]
	strb.w	r4, [sp, #0x32]
	strb.w	r4, [sp, #0x3e]
	add	r2, sp, #0x8
	movs	r1, #0
	mov	r0, r5
	bl	fn_0802516e
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024cf0
	mov	r8, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024ce4
	mov	r6, r0
	add.w	r1, r5, #0x14
	mov	r0, sp
	bl	copy_rect_0801cf8e
	ldrh.w	r1, [sp]
	sub.w	r0, r1, r8
	ldrh.w	r1, [sp, #0x4]
	strh.w	r0, [sp]
	add.w	r0, r1, r8
	strh.w	r0, [sp, #0x4]
	ldrh.w	r0, [sp, #0x2]
	mov	r1, r10
	subs	r0, r0, r6
	strh.w	r0, [sp, #0x2]
	ldrh.w	r0, [sp, #0x6]
	add	r0, r6
	strh.w	r0, [sp, #0x6]
	add	r0, sp, #0x40
	bl	fn_08023a0c
	add	r0, sp, #0x8
	str	r0, [sp, #0x50]
	mov	r0, sp
	str	r4, [sp, #0x74]
	strd	r7, r0, [sp, #0x48]
	str.w	r9, [sp, #0x44]
	add	r2, sp, #0x40
	movs	r1, #0x1a
	mov	r0, r5
	bl	fn_080207f4
	mov	r2, sp
	add	r1, sp, #0x8
	mov	r0, r10
.L0802385c:
	bl	fn_0801f31c
	b.n	.L080239fc
	b.n	.L08023868
.L08023864:
	b.n	.L08023902
	b.n	.L08023884
.L08023868:
	mov	r0, r8
	bl	get_word_at_0x10
	mov	r6, r0
	ldrb	r0, [r0]
	cmp	r0, #2
	beq.n	.L08023884
	movs	r1, #0
	mov	r0, r5
	bl	fn_080249a8
	cbz	r0, .L0802388a
	movs	r0, #2
	strb	r0, [r6]
.L08023884:
	add	sp, #0x88
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L0802388a:
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024c40
	mov	r10, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024cf0
	mov	r9, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024ce4
	mov	r8, r0
	add.w	r1, r5, #0x14
	mov	r0, sp
	bl	copy_rect_0801cf8e
	ldrh.w	r1, [sp]
	mov	r2, r10
	sub.w	r0, r1, r9
	ldrh.w	r1, [sp, #0x4]
	strh.w	r0, [sp]
	add.w	r0, r1, r9
	ldrh.w	r1, [sp, #0x2]
	strh.w	r0, [sp, #0x4]
	sub.w	r0, r1, r8
	ldrh.w	r1, [sp, #0x6]
	strh.w	r0, [sp, #0x2]
	add.w	r0, r1, r8
	strh.w	r0, [sp, #0x6]
	mov	r1, sp
	ldr	r0, [r6, #0x4]
	bl	fn_08011e9c
	cbz	r0, .L080238fa
	movs	r1, #0
	mov	r0, r5
	bl	fn_0802495c
	cmp	r0, #0xfd
	bcs.n	.L080238fe
.L080238fa:
	strb	r7, [r6]
	b.n	.L08023884
.L080238fe:
	strb	r4, [r6]
	b.n	.L08023884
.L08023902:
	mov	r0, r8
	bl	get_word_10_if_byte_8_14_to_19
	mov	r8, r0
	add	r0, sp, #0x8
	bl	fn_0801f344
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024974
	cbz	r0, .L08023926
	ldrb.w	r0, [sp, #0x2b]
	orr.w	r0, r0, #1
	strb.w	r0, [sp, #0x2b]
.L08023926:
	add	r2, sp, #0x8
	movs	r1, #0
	mov	r0, r5
	bl	fn_0802516e
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024cf0
	mov	r6, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024ce4
	mov	r7, r0
	add.w	r1, r5, #0x14
	mov	r10, r1
	mov	r0, sp
	bl	copy_rect_0801cf8e
	ldrh.w	r0, [sp]
	mov	r1, r8
	subs	r0, r0, r6
	strh.w	r0, [sp]
	ldrh.w	r0, [sp, #0x4]
	add	r0, r6
	strh.w	r0, [sp, #0x4]
	ldrh.w	r0, [sp, #0x2]
	subs	r0, r0, r7
	strh.w	r0, [sp, #0x2]
	ldrh.w	r0, [sp, #0x6]
	add	r0, r7
	strh.w	r0, [sp, #0x6]
	add	r0, sp, #0x40
	bl	fn_08023a0c
	add	r0, sp, #0x8
	str	r0, [sp, #0x50]
	mov	r0, sp
	strd	r4, r0, [sp, #0x48]
	str.w	r9, [sp, #0x44]
	add	r2, sp, #0x40
	movs	r1, #0x1a
	mov	r0, r5
	str	r4, [sp, #0x74]
	bl	fn_080207f4
	movs	r1, #0
	mov	r0, r5
	bl	fn_080249a8
	cbz	r0, .L080239b2
	ldrh.w	r0, [sp, #0x8]
	cbz	r0, .L080239b2
	ldr	r6, [sp, #0x18]
	movs	r7, #1
	str	r4, [sp, #0x18]
	b.n	.L080239b6
.L080239b2:
	ldr	r6, [sp, #0x18]
	movs	r7, #0
.L080239b6:
	mov	r2, sp
	add	r1, sp, #0x8
	mov	r0, r8
	bl	fn_0801f31c
	cbz	r7, .L080239fc
	movs	r0, #0x18
	bl	fn_08022bac
	mov	r7, r0
	ldrsh.w	r2, [sp, #0x8]
	movs	r3, #0
	mov	r1, r10
	bl	fn_0801f1a8
	add.w	r1, r5, #0x120
	mov	r0, r7
	bl	table_slot_insert
	cbz	r6, .L080239fc
	strb.w	r4, [sp, #0xb]
	strb.w	r4, [sp, #0x2a]
	strb.w	r4, [sp, #0x32]
	strb.w	r4, [sp, #0x3e]
	mov	r2, sp
	add	r1, sp, #0x8
	mov	r0, r8
	str	r6, [sp, #0x18]
	b.n	.L0802385c
.L080239fc:
	add	r2, sp, #0x40
	movs	r1, #0x1b
	mov	r0, r5
	bl	fn_080207f4
	b.n	.L08023884
.L08023a08:
	.word d_0804fcfc

@ ----------------------------------------------------------------------------
@ fn_08023a0c - clears a 0x48-byte buffer and stores a value in its first
@ word.
@ r0 = buffer (r4), r1 = value (r5); no return value.
@ Calls clear_bytes(buffer, 0x48), then stores r1 into the first word of the
@ buffer.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023a0c,"ax",%progbits
	.p2align 2
	.global fn_08023a0c
	.thumb_func
	.type fn_08023a0c, %function
fn_08023a0c:
	push	{r4, r5, r6, lr}
	mov	r5, r1
	mov	r4, r0
	movs	r1, #0x48
	bl	clear_bytes
	str	r5, [r4]
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ store_byte_200004b0 - stores a byte into the global at 0x200004b0.
@ r0 = byte value; no return value. The literal at 0x08023a24 is the address
@ 0x200004b0; two padding bytes precede it.
@ ----------------------------------------------------------------------------
	.section .text.store_byte_200004b0,"ax",%progbits
	.p2align 2
	.global store_byte_200004b0
	.thumb_func
	.type store_byte_200004b0, %function
store_byte_200004b0:
	ldr	r1, .L08023a24
	strb	r0, [r1]
	bx	lr
	.short 0x0000  @ padding
.L08023a24:
	.word 0x200004b0

@ ----------------------------------------------------------------------------
@ fn_08023a28 - object message handler (dispatch on the message type).
@ r1 = message pointer M (kept in r8). r0, r2 and r3 are pushed at entry
@ with r1 and r4..r8 and popped back at the return path 0x08023ae4
@ (pop {r0-r8,pc}), which gives back the slots at [sp+0..0xc]; the other
@ paths end in tail calls after add sp,#16 and return what the target
@ returns.
@ t = get_byte8_low7(M) (r4), object r5 = get_word_at_4(M) (word M+4);
@ the dispatch at 0x08023a3e..0x08023a78 compares t with 1, 8, 3, 0x2a,
@ 0x0d, 0x0e, 9, 0x0a, 0x0f, 0x29, 0x22, 0x13, then 0x15, 0x18 and 0x12
@ together; any other t returns at 0x08023ae4.
@ t = 1 (0x08023a86): tail-calls fn_080230b6(r5, 0x20).
@ t = 3 (0x08023ac4): tail-calls fn_080235cc(r5, 0x20).
@ t = 9 (0x08023c7c): tail-calls fn_080230b6(r5, 0x40).
@ t = 0x0f (0x08023cb6): tail-calls fn_080235cc(r5, 0x0e).
@ t = 0x15, 0x18, 0x12 (0x08023a7a): tail-calls fn_08023764(M).
@ t = 0x13 (0x08023d40): tail-calls fn_08020834(M, fn_080232bc(r5, 0)).
@ t = 8 (0x08023a8a): fn_080235cc(r5, 0x20); returns when fn_08021dee
@ (get_word_at_0x10(M)) is nonzero, or all_flag_bits_set(r5, 8) is 0; then
@ when bit 0 of byte [r5+0x20] is set fn_080235cc(r5, 1) else
@ fn_080230b6(r5, 1); tail-calls fn_080207f4(r5, 0x1c, 0) (0x08023b20).
@ t = 0x2a (0x08023ac8) and t = 0x29 (0x08023cc2, which first calls
@ fn_08025522(r5) when fn_080248cc(r5, 0) | fn_080249fc(r5, 0) is nonzero):
@ n = fn_08023da4(r5); for i = 0 while i < n (unsigned) calls fn_08025522
@ (word [[word[r5+8]] + i*4]); returns.
@ t = 0x0d (0x08023ae8): when all_flag_bits_set(r5, 8) is nonzero: k = byte
@ [get_word_at_0x10(M)]; k = 0x13 or 0x11 calls fn_080230b6(r5, 1), k = 0x14
@ or 0x12 calls fn_080235cc(r5, 1); k = 0x0a returns, else tail-calls
@ fn_080207f4(r5, 0x1c, 0). When it is 0: returns when all_flag_bits_set
@ (r5, 0x810) is 0 or fn_0802547a(r5) is nonzero; r6 = fn_08024070(r5),
@ r4 = fn_08024130(r5), r7 = 0; k = byte [get_word_at_0x10(M)]; with
@ h = rect_height_plus_one(r5) and w = rect_width_plus_one(r5), division by 4
@ = add of the sign bit lsr #30, asr #2: k = 0x12 (0x08023bae) tail-calls
@ fn_08026298(r5, sxth(fn_08024224(r5) + h/4), 0); k = 0x11 (0x08023b94)
@ tail-calls fn_08026298(r5, sxth(fn_08024224(r5) - h/4), 0); k = 0x14 goes
@ to 0x08023b94 when fn_08024060(r5) & 3 = 0 or (r6 <= 0 and r4 <= 0), else
@ (0x08023c02) tail-calls fn_0802626c(r5, sxth(fn_08024216(r5) - w/4), 0);
@ k = 0x13 goes to 0x08023bae when fn_08024060(r5) & 3 = 0 or (r6 <= 0 and
@ r4 <= 0), else (0x08023be8) tail-calls fn_0802626c(r5, sxth(fn_08024216
@ (r5) + w/4), 0); any other k returns.
@ t = 0x0e (0x08023c2a): when all_flag_bits_set(r5, 0x400) is nonzero calls
@ fn_08026232(r5, 1); fn_08023f18(r5); r6 = fn_08021048(); r4 = 2; when
@ read_word_200004ac() is 0 calls fn_08020790(M); r4 = 6 when fn_08021e06()
@ is 2 or 4; r6 nonzero: tail-calls fn_080230b6(r5, r4 | 8); r6 = 0:
@ fn_080230b6(r5, r4) then tail-calls fn_080235cc(r5, 8).
@ t = 0x0a (0x08023c88): fn_080235cc(r5, 0x40); returns unless fn_0802487e
@ (r5) = 2; then fn_08024232(r5, sp, sp+8), fn_08025446(r5, sp),
@ fn_08025446(r5, sp+8), returns.
@ t = 0x22 (0x08023cfc): a = sxth(fn_08024bac(r5, 0, 1)), b = sxth
@ (fn_08024bac(r5, 0, 4)); tail-calls fn_08025522(r5) when (fn_080248cc(r5,
@ 0) | fn_080249fc(r5, 0)) is nonzero or a = 0x27d1 or b = 0x27d1, else
@ returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_08023a28,"ax",%progbits
	.p2align 2
	.global fn_08023a28
	.thumb_func
	.type fn_08023a28, %function
fn_08023a28:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, lr}
	mov	r8, r1
	mov	r0, r1
	bl	get_byte8_low7
	mov	r4, r0
	mov	r0, r8
	bl	get_word_at_4
	mov	r5, r0
	cmp	r4, #1
	beq.n	.L08023a86
	cmp	r4, #8
	beq.n	.L08023a8a
	cmp	r4, #3
	beq.n	.L08023ac4
	cmp	r4, #0x2a
	beq.n	.L08023ac8
	cmp	r4, #0xd
	beq.n	.L08023ae8
	cmp	r4, #0xe
	beq.n	.L08023b54
	cmp	r4, #9
	beq.n	.L08023b56
	cmp	r4, #0xa
	beq.n	.L08023b58
	cmp	r4, #0xf
	beq.n	.L08023b5a
	cmp	r4, #0x29
	beq.n	.L08023b5c
	cmp	r4, #0x22
	beq.n	.L08023b5e
	cmp	r4, #0x13
	beq.n	.L08023b60
	cmp	r4, #0x15
	beq.n	.L08023a7a
	cmp	r4, #0x18
	beq.n	.L08023a7a
	cmp	r4, #0x12
	bne.n	.L08023ae4
.L08023a7a:
	add	sp, #0x10
	mov	r0, r8
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08023764
.L08023a86:
	movs	r1, #0x20
	b.n	.L08023c7e
.L08023a8a:
	movs	r1, #0x20
	bl	fn_080235cc
	mov	r0, r8
	bl	get_word_at_0x10
	bl	fn_08021dee
	cmp	r0, #0
	bne.n	.L08023ae4
	movs	r1, #8
	mov	r0, r5
	bl	all_flag_bits_set
	cmp	r0, #0
	beq.n	.L08023ae4
	ldrb.w	r0, [r5, #0x20]
	mov.w	r1, #1
	lsls	r0, r0, #31
	mov	r0, r5
	beq.n	.L08023abe
	bl	fn_080235cc
	b.n	.L08023b20
.L08023abe:
	bl	fn_080230b6
	b.n	.L08023b20
.L08023ac4:
	movs	r1, #0x20
	b.n	.L08023cb8
.L08023ac8:
	bl	fn_08023da4
	mov	r6, r0
	movs	r4, #0
	b.n	.L08023ae0
.L08023ad2:
	ldr	r0, [r5, #0x8]
	ldr	r0, [r0]
	ldr.w	r0, [r0, r4, lsl #2]
	bl	fn_08025522
	.inst.n 0x1c64  @ adds r4, r4, #1
.L08023ae0:
	cmp	r4, r6
	bcc.n	.L08023ad2
.L08023ae4:
	pop.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, pc}
.L08023ae8:
	movs	r1, #8
	bl	all_flag_bits_set
	cbz	r0, .L08023b30
	mov	r0, r8
	bl	get_word_at_0x10
	ldrb	r4, [r0]
	cmp	r4, #0x13
	beq.n	.L08023b0a
	cmp	r4, #0x11
	beq.n	.L08023b0a
	cmp	r4, #0x14
	beq.n	.L08023b14
	cmp	r4, #0x12
	beq.n	.L08023b14
	b.n	.L08023b1c
.L08023b0a:
	movs	r1, #1
	mov	r0, r5
	bl	fn_080230b6
	b.n	.L08023b1c
.L08023b14:
	movs	r1, #1
	mov	r0, r5
	bl	fn_080235cc
.L08023b1c:
	cmp	r4, #0xa
	beq.n	.L08023ae4
.L08023b20:
	add	sp, #0x10
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, lr}
	movs	r2, #0
	movs	r1, #0x1c
	b.w	fn_080207f4
.L08023b30:
	mov.w	r1, #0x810
	mov	r0, r5
	bl	all_flag_bits_set
	cmp	r0, #0
	beq.n	.L08023ae4
	mov	r0, r5
	bl	fn_0802547a
	cmp	r0, #0
	bne.n	.L08023ae4
	movs	r7, #0
	mov	r0, r5
	bl	fn_08024070
	mov	r6, r0
	b.n	.L08023b62
.L08023b54:
	b.n	.L08023c2a
.L08023b56:
	b.n	.L08023c7c
.L08023b58:
	b.n	.L08023c88
.L08023b5a:
	b.n	.L08023cb6
.L08023b5c:
	b.n	.L08023cc2
.L08023b5e:
	b.n	.L08023cfc
.L08023b60:
	b.n	.L08023d40
.L08023b62:
	mov	r0, r5
	bl	fn_08024130
	mov	r4, r0
	mov	r0, r8
	bl	get_word_at_0x10
	ldrb	r0, [r0]
	cmp	r0, #0x12
	beq.n	.L08023bae
	cmp	r0, #0x11
	beq.n	.L08023b94
	cmp	r0, #0x13
	beq.n	.L08023bd6
	cmp	r0, #0x14
	bne.n	.L08023ae4
	mov	r0, r5
	bl	fn_08024060
	lsls	r0, r0, #30
	beq.n	.L08023b94
	cmp	r6, #0
	bgt.n	.L08023c02
	cmp	r4, #0
	bgt.n	.L08023c02
.L08023b94:
	mov	r0, r5
	bl	rect_height_plus_one
	mov	r4, r0
	mov	r0, r5
	bl	fn_08024224
	asrs	r1, r4, #31
	add.w	r1, r4, r1, lsr #30
	sub.w	r0, r0, r1, asr #2
	b.n	.L08023bc6
.L08023bae:
	mov	r0, r5
	bl	rect_height_plus_one
	mov	r4, r0
	mov	r0, r5
	bl	fn_08024224
	asrs	r1, r4, #31
	add.w	r1, r4, r1, lsr #30
	add.w	r0, r0, r1, asr #2
.L08023bc6:
	sxth	r1, r0
	add	sp, #0x10
	mov	r2, r7
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08026298
.L08023bd6:
	mov	r0, r5
	bl	fn_08024060
	lsls	r0, r0, #30
	beq.n	.L08023bae
	cmp	r6, #0
	bgt.n	.L08023be8
	cmp	r4, #0
	ble.n	.L08023bae
.L08023be8:
	mov	r0, r5
	bl	rect_width_plus_one
	mov	r4, r0
	mov	r0, r5
	bl	fn_08024216
	asrs	r1, r4, #31
	add.w	r1, r4, r1, lsr #30
	add.w	r0, r0, r1, asr #2
	b.n	.L08023c1a
.L08023c02:
	mov	r0, r5
	bl	rect_width_plus_one
	mov	r4, r0
	mov	r0, r5
	bl	fn_08024216
	asrs	r1, r4, #31
	add.w	r1, r4, r1, lsr #30
	sub.w	r0, r0, r1, asr #2
.L08023c1a:
	sxth	r1, r0
	add	sp, #0x10
	mov	r2, r7
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_0802626c
.L08023c2a:
	mov.w	r1, #0x400
	bl	all_flag_bits_set
	cbz	r0, .L08023c3c
	movs	r1, #1
	mov	r0, r5
	bl	fn_08026232
.L08023c3c:
	mov	r0, r5
	bl	fn_08023f18
	bl	fn_08021048
	mov	r6, r0
	movs	r4, #2
	bl	read_word_200004ac
	cbnz	r0, .L08023c56
	mov	r0, r8
	bl	fn_08020790
.L08023c56:
	bl	fn_08021e06
	cmp	r0, #2
	beq.n	.L08023c62
	cmp	r0, #4
	bne.n	.L08023c64
.L08023c62:
	movs	r4, #6
.L08023c64:
	cbz	r6, .L08023c6e
	orr.w	r1, r4, #8
	mov	r0, r5
	b.n	.L08023c7e
.L08023c6e:
	mov	r1, r4
	mov	r0, r5
	bl	fn_080230b6
	movs	r1, #8
	mov	r0, r5
	b.n	.L08023cb8
.L08023c7c:
	movs	r1, #0x40
.L08023c7e:
	add	sp, #0x10
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_080230b6
.L08023c88:
	movs	r1, #0x40
	bl	fn_080235cc
	mov	r0, r5
	bl	fn_0802487e
	cmp	r0, #2
	bne.w	.L08023ae4
	add	r2, sp, #0x8
	mov	r1, sp
	mov	r0, r5
	bl	fn_08024232
	mov	r1, sp
	mov	r0, r5
	bl	fn_08025446
	add	r1, sp, #0x8
	mov	r0, r5
	bl	fn_08025446
.L08023cb4:
	b.n	.L08023ae4
.L08023cb6:
	movs	r1, #0xe
.L08023cb8:
	add	sp, #0x10
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_080235cc
.L08023cc2:
	movs	r1, #0
	bl	fn_080248cc
	mov	r4, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_080249fc
	orrs	r0, r4
	beq.n	.L08023cdc
	mov	r0, r5
	bl	fn_08025522
.L08023cdc:
	mov	r0, r5
	bl	fn_08023da4
	mov	r6, r0
	movs	r4, #0
	b.n	.L08023cf6
.L08023ce8:
	ldr	r0, [r5, #0x8]
	ldr	r0, [r0]
	ldr.w	r0, [r0, r4, lsl #2]
	bl	fn_08025522
	.inst.n 0x1c64  @ adds r4, r4, #1
.L08023cf6:
	cmp	r4, r6
	bcc.n	.L08023ce8
	b.n	.L08023ae4
.L08023cfc:
	movs	r1, #0
	movs	r2, #1
	bl	fn_08024bac
	sxth	r6, r0
	mov	r0, r5
	movs	r1, #0
	movs	r2, #4
	bl	fn_08024bac
	sxth	r4, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_080248cc
	mov	r7, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_080249fc
	orrs	r0, r7
	bne.n	.L08023d34
	movw	r0, #0x27d1
	cmp	r6, r0
	beq.n	.L08023d34
	cmp	r4, r0
	bne.n	.L08023cb4
.L08023d34:
	add	sp, #0x10
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08025522
.L08023d40:
	movs	r1, #0
	bl	fn_080232bc
	mov	r1, r0
	add	sp, #0x10
	mov	r0, r8
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08020834
