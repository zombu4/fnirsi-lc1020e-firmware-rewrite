@ gui_17.s - GUI module, batch 17: 26 functions at 0x0801b418..0x0801c2e8
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0801b418 - find or create an 8-byte entry by 24-bit key.
@ Parameters: r0 = record pointer (word +0xc = array of 8-byte entries,
@ halfword +0x22 bits 3..8 = number of 8-byte entries), r1 = 24-bit key.
@ Returns a pointer (word 0 of the entry).
@ Scans the entries for one with bit 24 (0x1000000) set in word 1 and
@ (word 1 & 0xffffff) equal to r1; returns its word 0.
@ When absent: grows the array by 8 bytes with fn_08022cb0, shifts the entries
@ up (stopping at an entry with bit 24 or bit 25 set), clears the new slot with
@ clear_bytes, allocates 8 bytes with fn_08022b50 into word 0, calls
@ fn_08026f0e, stores word 1 as flag 0x1000000 | (r1 & 0xffffff) keeping the
@ upper byte, and returns the new word 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b418,"ax",%progbits
	.p2align 2
	.global fn_0801b418
	.thumb_func
	.type fn_0801b418, %function
fn_0801b418:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r5, r0
	mov	r7, r1
	ldrh	r1, [r5, #0x22]
	movs	r0, #0
	movs	r6, #4
	ubfx	r3, r1, #3, #6		@ r3 = entry count
	ldr	r2, [r5, #0xc]		@ r2 = entry array
	b.n	.L0801b44e
	nop				@ padding
.L0801b430:
	add.w	r4, r6, r0, lsl #3
	ldr	r4, [r2, r4]		@ word 1 of entry r0
	lsls.w	ip, r4, #7		@ test bit 24
	bpl.n	.L0801b44c
	bic.w	r4, r4, #0xff000000
	cmp	r4, r7			@ key match?
	bne.n	.L0801b44c
	ldr.w	r0, [r2, r0, lsl #3]	@ found: return word 0
.L0801b448:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0801b44c:
	.inst.n	0x1c40			@ adds r0, r0, #1
.L0801b44e:
	cmp	r3, r0
	bhi.n	.L0801b430
	mov.w	r0, #0x4000000
	add.w	r0, r0, r1, ror #9
	ror.w	r0, r0, #0x17		@ count + 1 in halfword +0x22 form
	strh	r0, [r5, #0x22]
	ubfx	r0, r0, #3, #6
	lsls	r1, r0, #3		@ new size in bytes
	mov	r0, r2
	bl	fn_08022cb0
	str	r0, [r5, #0xc]
	ldrh	r0, [r5, #0x22]
	ubfx	r4, r0, #3, #6
	.inst.n	0x1e64			@ subs r4, r4, #1
	beq.n	.L0801b4a8
	mvn	r2, #3
	lsls.w	r3, r2, #1
.L0801b480:
	ldr	r0, [r5, #0xc]
	add.w	r1, r2, r4, lsl #3
	ldr	r1, [r0, r1]
	lsls.w	ip, r1, #7
	bmi.n	.L0801b4a8		@ stop at an entry with bit 24 set
	lsls	r1, r1, #6
	bmi.n	.L0801b4a8		@ stop at an entry with bit 25 set
	add.w	ip, r3, r4, lsl #3
	add.w	r1, r0, r4, lsl #3
	add	ip, r0
	.inst.n	0x1e64			@ subs r4, r4, #1
	ldrd	r0, ip, [ip]
	strd	r0, ip, [r1]		@ move the previous entry up
	bne.n	.L0801b480
.L0801b4a8:
	ldr	r0, [r5, #0xc]
	movs	r1, #8
	add.w	r0, r0, r4, lsl #3
	bl	clear_bytes
	movs	r0, #8
	bl	fn_08022b50
	ldr	r1, [r5, #0xc]
	str.w	r0, [r1, r4, lsl #3]
	bl	fn_08026f0e
	ldr	r2, [r5, #0xc]
	add.w	r1, r6, r4, lsl #3
	ldr	r0, [r2, r1]
	orr.w	r0, r0, #0x1000000
	str	r0, [r2, r1]
	ldr	r2, [r5, #0xc]
	bfi	r0, r7, #0, #0x18	@ insert the 24-bit key
	str	r0, [r2, r1]
	ldr	r0, [r5, #0xc]
	ldr.w	r0, [r0, r4, lsl #3]
	b.n	.L0801b448
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0801b4e4 - clamped count that fits a height.
@ Parameters: r0 = pointer to a pointer to a record (record word +0xc, then
@ word +0xc of that, divided by r1), r1 = divisor, r2 = upper limit.
@ Returns a count.
@ Computes r4 = *(*(*r0 + 0xc) + 0xc) / r1 (unsigned) and clamps it to r2
@ (signed). When the function at (*word 0x200004b8)+0x18 exists, calls it
@ repeatedly with a rectangle (left 0, top 0, right 0, bottom n-1) for
@ decreasing n until the returned height ((bottom - top) + 1) is at most the
@ clamped value, and returns the returned bottom + 1; returns 0 when n-1
@ reaches 0 without a fit; returns the clamped value when the function pointer
@ is 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b4e4,"ax",%progbits
	.p2align 2
	.global fn_0801b4e4
	.thumb_func
	.type fn_0801b4e4, %function
fn_0801b4e4:
	push.w	{r2, r3, r4, r5, r6, r7, r8, lr}
	ldr	r0, [r0]
	ldr	r0, [r0, #0xc]
	ldr	r0, [r0, #0xc]
	udiv	r4, r0, r1
	cmp	r4, r2
	ble.n	.L0801b4f8
	mov	r4, r2			@ clamp to the limit
.L0801b4f8:
	ldr	r7, .L0801b550
	ldr	r0, [r7, #4]
	ldr	r0, [r0]
	ldr	r0, [r0, #0x18]		@ function pointer at +0x18
	cbz	r0, .L0801b54c
	movs	r0, #0
	strh.w	r0, [sp]		@ rectangle left = 0
	strh.w	r0, [sp, #4]		@ rectangle right = 0
	strh.w	r0, [sp, #2]		@ rectangle top = 0
	sxth	r5, r4
.L0801b512:
	subs	r0, r5, #1
	sxth	r6, r0
	strh.w	r6, [sp, #6]		@ rectangle bottom = n - 1
	ldr	r0, [r7, #4]
	mov	r1, sp
	ldr	r0, [r0]
	ldr	r2, [r0, #0x18]
	blx	r2
	ldrh.w	r0, [sp, #6]
	ldrh.w	r1, [sp, #2]
	subs	r0, r0, r1
	.inst.n	0x1c40			@ adds r0, r0, #1
	sxth	r0, r0			@ returned height
	cmp	r0, r4
	ble.n	.L0801b53c
	subs	r5, r6, #0
	bgt.n	.L0801b512
	b.n	.L0801b540
.L0801b53c:
	cmp	r5, #0
	bgt.n	.L0801b546
.L0801b540:
	movs	r0, #0
.L0801b542:
	pop.w	{r2, r3, r4, r5, r6, r7, r8, pc}
.L0801b546:
	ldrsh.w	r4, [sp, #6]
	.inst.n	0x1c64			@ adds r4, r4, #1
.L0801b54c:
	mov	r0, r4
	b.n	.L0801b542
.L0801b550:
	.word	0x200004b4

@ ----------------------------------------------------------------------------
@ fn_0801b554 - step an index through a list and return the element.
@ Parameters: r0 = object pointer (word +8 = list: word 0 = array, word 4 =
@ count), r1 = direction (0 = forward, otherwise backward), r2 = pointer to an
@ index. Returns the next element or 0.
@ Forward: increments *r2 and returns 0 when it reaches the count.
@ Backward: decrements *r2 and returns 0 when it goes below 0.
@ Otherwise returns the array element at the new index.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b554,"ax",%progbits
	.global fn_0801b554
	.thumb_func
	.type fn_0801b554, %function
fn_0801b554:
	ldr	r3, [r2]
	cbz	r1, .L0801b562
	.inst.n	0x1e5b			@ subs r3, r3, #1
	str	r3, [r2]
	bmi.n	.L0801b576
	ldr	r0, [r0, #8]
	b.n	.L0801b56e
.L0801b562:
	.inst.n	0x1c5b			@ adds r3, r3, #1
	str	r3, [r2]
	ldr	r0, [r0, #8]
	ldr	r1, [r0, #4]
	cmp	r3, r1
	bge.n	.L0801b576
.L0801b56e:
	ldr	r0, [r0]
	ldr.w	r0, [r0, r3, lsl #2]
	bx	lr
.L0801b576:
	movs	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801b57a - map a point to column and row indices.
@ Parameters: r0 = object pointer, r1 = output pointer to the row index
@ (ushort) or 0, r2 = output pointer to the column index (ushort) or 0, r3 is
@ not read. Returns 1 when found, 0 otherwise.
@ Calls read_word_200004ac and fn_08021e06; for state 1 or 3 takes the point
@ (two shorts at sp+0, sp+2) from fn_08021db0(read_word_200004ac(), sp). For
@ the column output, walks the ushort widths at object +0x30 (count ushort
@ +0x24), accumulating until the sum passes (x - left offset); when
@ fn_08024936(r0, 0) is 1 the offset is ushort +0x18 - fn_08024b4c(r0, 0) - x.
@ For the row output walks the widths at +0x2c (count ushort +0x26) against
@ (y - top offset - margin); stores the counted indices.
@ For any other state writes 0xffff to both outputs and returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b57a,"ax",%progbits
	.global fn_0801b57a
	.thumb_func
	.type fn_0801b57a, %function
fn_0801b57a:
	push.w	{r3, r4, r5, r6, r7, r8, r9, lr}
	mov	r5, r2
	mov	r6, r1
	mov	r4, r0
	bl	read_word_200004ac
	bl	fn_08021e06
	cmp	r0, #1
	beq.n	.L0801b5a6
	cmp	r0, #3
	beq.n	.L0801b5a6
	movw	r0, #0xffff
	cbz	r5, .L0801b59c
	strh	r0, [r5]
.L0801b59c:
	cbz	r6, .L0801b5a0
	strh	r0, [r6]
.L0801b5a0:
	movs	r0, #0
.L0801b5a2:
	pop.w	{r3, r4, r5, r6, r7, r8, r9, pc}
.L0801b5a6:
	bl	read_word_200004ac
	mov	r1, sp
	bl	fn_08021db0
	mov.w	r8, #0
	cbz	r5, .L0801b614
	mov	r0, r4
	bl	fn_08024216
	ldrh.w	r1, [sp]
	add	r0, r1
	sxth	r7, r0			@ x position
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024936
	cmp	r0, #1
	beq.n	.L0801b5ea
	ldrh	r0, [r4, #0x14]
	movs	r1, #0
	subs	r7, r7, r0
	mov	r0, r4
	bl	fn_08024b10
	subs	r0, r7, r0
.L0801b5de:
	sxth	r2, r0			@ target offset for the column walk
	mov	r0, r8
	movs	r1, #0
	strh.w	r8, [r5]
	b.n	.L0801b60c
.L0801b5ea:
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024b4c
	ldrh	r1, [r4, #0x18]
	subs	r0, r1, r0
	subs	r0, r0, r7
	b.n	.L0801b5de
.L0801b5fa:
	ldr	r3, [r4, #0x30]
	ldrh.w	r3, [r3, r0, lsl #1]
	add	r1, r3
	sxth	r1, r1
	cmp	r2, r1
	blt.n	.L0801b614
	.inst.n	0x1c40			@ adds r0, r0, #1
	strh	r0, [r5]
.L0801b60c:
	ldrh	r3, [r4, #0x24]
	uxth	r0, r0
	cmp	r0, r3
	bcc.n	.L0801b5fa
.L0801b614:
	cbz	r6, .L0801b656
	mov	r0, r4
	bl	fn_08024224
	ldrh.w	r1, [sp, #2]
	add	r0, r1
	ldrh	r1, [r4, #0x16]
	subs	r5, r0, r1
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024ba0
	subs	r0, r5, r0
	sxth	r2, r0			@ target offset for the row walk
	mov	r0, r8
	movs	r1, #0
	strh.w	r8, [r6]
	b.n	.L0801b64e
.L0801b63c:
	ldr	r3, [r4, #0x2c]
	ldrh.w	r3, [r3, r0, lsl #1]
	add	r1, r3
	sxth	r1, r1
	cmp	r2, r1
	blt.n	.L0801b656
	.inst.n	0x1c40			@ adds r0, r0, #1
	strh	r0, [r6]
.L0801b64e:
	ldrh	r3, [r4, #0x26]
	uxth	r0, r0
	cmp	r0, r3
	bcc.n	.L0801b63c
.L0801b656:
	movs	r0, #1
	b.n	.L0801b5a2

@ ----------------------------------------------------------------------------
@ fn_0801b65a - look up an entry by group id and value.
@ Parameters: r0 = object pointer (word +0xc = array of 8-byte entries,
@ halfword +0x20 = wanted flags, halfword +0x22 = count info), r1 = group id,
@ r2 = value, r3 = pointer to the result word. Returns 1, 2 or 0.
@ Computes the mask 1 << field_1ff_shr4_max7(r2) (low byte) and the inverted
@ wanted flags.
@ First loop (from index 0 until the first entry whose bit 25 of word 1 is
@ clear): when (byte +0x22 & 4) is clear, the entry's byte 2 of word 1 shifted
@ left by 16 equals r1 and its object byte +6 has the mask bit, calls
@ fn_08026dc4 (entry object, r2, &result); result 1 returns 1 with the stored
@ result, result 2 returns 2.
@ Second loop over the remaining entries: entries with the same group id whose
@ low halfword has no inverted wanted flag and exceeds the best so far call the
@ same function; an exact match with the wanted flags returns immediately,
@ otherwise the highest-ranked result is kept; returns 1 with the best result
@ or 0 when none.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b65a,"ax",%progbits
	.global fn_0801b65a
	.thumb_func
	.type fn_0801b65a, %function
fn_0801b65a:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0xc
	mov	r5, r0
	mov	r7, r3
	ldr	r0, [sp, #0x14]
	bl	field_1ff_shr4_max7
	mov	r1, r0
	movs	r0, #1
	lsls	r0, r1			@ mask bit
	ldrh.w	r9, [r5, #0x20]		@ wanted flags
	and.w	r8, r0, #0xff
	mvn.w	r0, r9
	uxth	r0, r0
	str	r0, [sp, #4]		@ inverted wanted flags
	ldrb.w	r0, [r5, #0x22]
	mov.w	r6, #0xffffffff		@ best rank so far
	ubfx	r10, r0, #2, #1
	movs	r4, #0
	mov.w	r11, #4
	b.n	.L0801b6d4
.L0801b694:
	ldr	r1, [r5, #0xc]
	add.w	r0, r1, r4, lsl #3
	ldr	r2, [r0, #4]
	lsls	r2, r2, #6
	bpl.n	.L0801b722		@ bit 25 clear: leave the first loop
	cmp.w	r10, #0
	bne.n	.L0801b6d2
	add.w	r2, r11, r4, lsl #3
	ldr	r1, [r1, r2]
	ldr	r2, [sp, #0x10]
	ubfx	r1, r1, #0x10, #8
	lsls	r1, r1, #0x10
	cmp	r1, r2
	bne.n	.L0801b6d2
	ldr	r0, [r0]
	ldrb	r1, [r0, #6]
	tst.w	r1, r8
	beq.n	.L0801b6d2
	mov	r2, sp
	ldr	r1, [sp, #0x14]
	bl	fn_08026dc4
	cmp	r0, #1
	beq.n	.L0801b730
	cmp	r0, #2
	beq.n	.L0801b736
.L0801b6d2:
	.inst.n	0x1c64			@ adds r4, r4, #1
.L0801b6d4:
	ldrh	r0, [r5, #0x22]
	ubfx	r0, r0, #3, #6
	cmp	r0, r4
	bhi.n	.L0801b694
	b.n	.L0801b722
.L0801b6e0:
	ldr	r1, [r5, #0xc]
	ldr.w	r0, [r1, r4, lsl #3]
	ldrb	r2, [r0, #6]
	tst.w	r2, r8
	beq.n	.L0801b720
	add.w	r2, r11, r4, lsl #3
	ldr	r2, [r1, r2]
	ubfx	r1, r2, #0x10, #8
	uxth.w	r10, r2			@ low halfword of word 1
	ldr	r2, [sp, #0x10]
	lsls	r1, r1, #0x10
	cmp	r1, r2
	bne.n	.L0801b720
	ldr	r2, [sp, #4]
	tst.w	r10, r2
	bne.n	.L0801b720
	cmp	r10, r6
	ble.n	.L0801b720
	mov	r2, sp
	ldr	r1, [sp, #0x14]
	bl	fn_08026dc4
	cmp	r0, #1
	beq.n	.L0801b73c
	cmp	r0, #2
	beq.n	.L0801b736
.L0801b720:
	.inst.n	0x1c64			@ adds r4, r4, #1
.L0801b722:
	ldrh	r0, [r5, #0x22]
	ubfx	r0, r0, #3, #6
	cmp	r0, r4
	bhi.n	.L0801b6e0
	cmp	r6, #0
	blt.n	.L0801b74e
.L0801b730:
	ldr	r0, [sp]
	str	r0, [r7]		@ store the result
	movs	r0, #1
.L0801b736:
	add	sp, #0x1c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801b73c:
	mov	r0, r10
	cmp	r10, r9
	beq.n	.L0801b730		@ exact match with the wanted flags
	cmp	r6, r10
	bge.n	.L0801b720
	mov	r6, r0			@ new best rank
	ldr	r0, [sp]
	str	r0, [r7]
	b.n	.L0801b720
.L0801b74e:
	movs	r0, #0
	b.n	.L0801b736

@ ----------------------------------------------------------------------------
@ fn_0801b752 - compute an output rectangle from an angle and a size.
@ Parameters: r0 = angle value, r1 = size, r2 = flags (bit 0 selects the
@ odd-size correction, higher bits give half size), r3 = pointer to 4 shorts
@ (output rectangle). No return value.
@ Gets the factors sine_q15_degrees(0x5a - angle) and sine_q15_degrees(angle),
@ multiplies each by (r1 - (r2 >> 1)) and shifts right by 7.
@ Builds output left/right (shorts 0 and 2) and top/bottom (shorts 1 and 3):
@ each pair is (value + 0x7f, or value - 0x7f, >> 8) minus and plus half of r2,
@ with the correction (1 when bit 0 of r2 is clear, 0 when it is set) applied to
@ one side depending on the sign of the product.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b752,"ax",%progbits
	.global fn_0801b752
	.thumb_func
	.type fn_0801b752, %function
fn_0801b752:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r9, r0
	sbfx	r6, r2, #0, #1
	rsb.w	r0, r0, #0x5a
	mov	r5, r3
	mov	r7, r1
	lsrs	r4, r2, #1		@ half of the flags
	sxth	r0, r0
	.inst.n	0x1c76			@ adds r6, r6, #1
	bl	sine_q15_degrees
	sub.w	r8, r7, r4
	mul	r0, r0, r8
	asrs	r7, r0, #7
	mov	r0, r9
	bl	sine_q15_degrees
	mul	r0, r0, r8
	asrs	r0, r0, #7
	cmp	r7, #0
	ble.n	.L0801b796
	subs	r7, #0x7f
	asrs	r1, r7, #8
	subs	r2, r1, r4
	add	r2, r6
	strh	r2, [r5]
	add	r1, r4
	b.n	.L0801b7a2
.L0801b796:
	adds	r7, #0x7f
	asrs	r1, r7, #8
	subs	r2, r1, r4
	add	r1, r4
	strh	r2, [r5]
	subs	r1, r1, r6
.L0801b7a2:
	strh	r1, [r5, #4]
	cmp	r0, #0
	ble.n	.L0801b7b6
	subs	r0, #0x7f
	asrs	r0, r0, #8
	subs	r1, r0, r4
	add	r1, r6
	strh	r1, [r5, #2]
	add	r0, r4
	b.n	.L0801b7c2
.L0801b7b6:
	adds	r0, #0x7f
	asrs	r0, r0, #8
	subs	r1, r0, r4
	add	r0, r4
	strh	r1, [r5, #2]
	subs	r0, r0, r6
.L0801b7c2:
	strh	r0, [r5, #6]
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ fn_0801b7c8 - tail call of fn_08024bac with a halfword of 0x20000550.
@ Parameter: r0 = object pointer; returns the result of
@ fn_08024bac(r0, 0, halfword at 0x20000556).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b7c8,"ax",%progbits
	.p2align 2
	.global fn_0801b7c8
	.thumb_func
	.type fn_0801b7c8, %function
fn_0801b7c8:
	ldr	r2, .L0801b7d4
	movs	r1, #0
	ldrh	r2, [r2, #6]
	b.w	fn_08024bac
	.short	0x0000			@ padding
.L0801b7d4:
	.word	0x20000550

@ ----------------------------------------------------------------------------
@ fn_0801b7d8 - lowest bottom coordinate of the cells of a grid row.
@ Parameters: r0 = grid object (ushort +0x24 = columns, word +0x28 = cell
@ pointer array, word +0x30 = column width array of shorts), r1 = row index,
@ r2 = font/style pointer (short +8 = height), r3 and the stack argument at
@ sp+0x4c-ish (param_5) = text arguments, stack shorts param_6 / param_7 =
@ padding, param_8 / param_9 = offsets. Returns the lowest bottom coordinate
@ (short), starting from param_8 + param_9 + short(+8 of r2) and raised per
@ cell.
@ For each column of the row (index starts at row * columns): skips null cells;
@ while the cell at the current index is non-null and its first byte has bit 0
@ set (and the column index is below columns - 1), adds the width of the next
@ column (merged cells); a cell with bit 1 set only raises the result to
@ param_8 + param_9 + short(+8 of r2); otherwise measures the text at cell + 1
@ with fn_08027d30 using width (sum - param_6 - param_7) and raises the result
@ to (param_8 + param_9) + measured height; merged columns are skipped.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b7d8,"ax",%progbits
	.p2align 2
	.global fn_0801b7d8
	.thumb_func
	.type fn_0801b7d8, %function
fn_0801b7d8:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x14
	mov	r7, r0
	ldr	r0, [sp, #0x1c]
	ldrh	r3, [r0, #8]
	ldrd	r0, r2, [sp, #0x54]
	add	r0, r2
	str	r0, [sp, #0x10]
	add	r0, r3
	sxth.w	r10, r0			@ result so far
	ldrh	r0, [r7, #0x24]
	muls	r0, r1, r0
	uxth	r4, r0			@ first cell index of the row
	mov	r9, r4
	movs	r5, #0			@ column index
	b.n	.L0801b8b2
.L0801b7fe:
	ldr	r3, [r7, #0x28]
	ldr.w	r1, [r3, r4, lsl #2]
	cbz	r1, .L0801b864
	ldr	r2, [r7, #0x30]
	movs	r6, #0
	mov	lr, r2
	ldrsh.w	r11, [r2, r5, lsl #1]
	mov.w	ip, #2
	.inst.n	0x1e40			@ subs r0, r0, #1
	b.n	.L0801b83e
.L0801b818:
	adds	r2, r4, r6
	ldr.w	r2, [r3, r2, lsl #2]
	cbz	r2, .L0801b844
	ldrb	r2, [r2]
	lsls	r2, r2, #0x1f
	beq.n	.L0801b844
	add.w	r8, r5, r6
	add.w	r8, ip, r8, lsl #1
	ldrh.w	r8, [lr, r8]		@ width of the next column
	.inst.n	0x1c76			@ adds r6, r6, #1
	add.w	r2, r8, r11
	sxth.w	r11, r2
	uxth	r6, r6
.L0801b83e:
	adds	r2, r6, r5
	cmp	r2, r0
	blt.n	.L0801b818
.L0801b844:
	ldrb	r0, [r1]
	lsls	r0, r0, #0x1e
	bpl.n	.L0801b866
	ldr	r0, [sp, #0x1c]
	ldr	r1, [sp, #0x54]
	ldrsh.w	r0, [r0, #8]
	add	r1, r0
	ldr	r0, [sp, #0x58]
	add	r0, r1
	mov	r1, r10
	cmp	r0, r10
	bgt.n	.L0801b860
	mov	r0, r1
.L0801b860:
	sxth.w	r10, r0
.L0801b864:
	b.n	.L0801b8aa
.L0801b866:
	ldrd	r0, r1, [sp, #0x4c]
	add	r1, r0
	sub.w	r0, r11, r1
	sxth	r0, r0			@ width minus the paddings
	ldr	r1, [sp, #0x48]
	strd	r1, r0, [sp]
	movs	r2, #0
	str	r2, [sp, #8]
	ldr	r0, [r7, #0x28]
	ldr.w	r1, [r0, r4, lsl #2]
	ldrd	r2, r3, [sp, #0x1c]
	add	r0, sp, #0xc
	.inst.n	0x1c49			@ adds r1, r1, #1
	bl	fn_08027d30
	ldrsh.w	r1, [sp, #0xe]		@ measured height
	ldr	r0, [sp, #0x10]
	add	r0, r1
	mov	r1, r10
	cmp	r0, r10
	bgt.n	.L0801b89e
	mov	r0, r1
.L0801b89e:
	sxth.w	r10, r0
	adds	r0, r4, r6
	uxth	r4, r0
	adds	r0, r5, r6
	uxth	r5, r0
.L0801b8aa:
	.inst.n	0x1c64			@ adds r4, r4, #1
	.inst.n	0x1c6d			@ adds r5, r5, #1
	uxth	r4, r4
	uxth	r5, r5
.L0801b8b2:
	ldrh	r0, [r7, #0x24]
	add.w	r1, r0, r9
	cmp	r1, r4
	bhi.n	.L0801b7fe
	add	sp, #0x24
	mov	r0, r10
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}

@ ----------------------------------------------------------------------------
@ fn_0801b8c4 - fn_08024bac with a halfword of 0x20000550, low byte result.
@ Parameter: r0 = object pointer; returns the low byte of
@ fn_08024bac(r0, 0, halfword at 0x20000560).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b8c4,"ax",%progbits
	.p2align 2
	.global fn_0801b8c4
	.thumb_func
	.type fn_0801b8c4, %function
fn_0801b8c4:
	ldr	r2, .L0801b8d4
	push	{r4, lr}
	movs	r1, #0
	ldrh	r2, [r2, #0x10]
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}
.L0801b8d4:
	.word	0x20000550

@ ----------------------------------------------------------------------------
@ fn_0801b8d8 - fn_08024bac with a halfword of 0x20000550, low byte result.
@ Parameter: r0 = object pointer; returns the low byte of
@ fn_08024bac(r0, 0, halfword at 0x20000562).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b8d8,"ax",%progbits
	.p2align 2
	.global fn_0801b8d8
	.thumb_func
	.type fn_0801b8d8, %function
fn_0801b8d8:
	ldr	r2, .L0801b8e8
	push	{r4, lr}
	movs	r1, #0
	ldrh	r2, [r2, #0x12]
	bl	fn_08024bac
	uxtb	r0, r0
	pop	{r4, pc}
.L0801b8e8:
	.word	0x20000550

@ ----------------------------------------------------------------------------
@ base_plus_offset_by_index - select a sub-structure address by index.
@ Parameters: r0 = base pointer, r1 = index. Returns r0 + 0x3c for index 0,
@ r0 + 0x54 for 1, r0 + 0x48 for 2, r0 + 0x60 for 4, and 0 for any other index.
@ ----------------------------------------------------------------------------
	.section .text.base_plus_offset_by_index,"ax",%progbits
	.p2align 2
	.global base_plus_offset_by_index
	.thumb_func
	.type base_plus_offset_by_index, %function
base_plus_offset_by_index:
	cbz	r1, .L0801b8fe
	cmp	r1, #1
	beq.n	.L0801b906
	cmp	r1, #2
	beq.n	.L0801b902
	cmp	r1, #4
	beq.n	.L0801b90a
	movs	r0, #0
	bx	lr
.L0801b8fe:
	adds	r0, #0x3c
	bx	lr
.L0801b902:
	adds	r0, #0x48
	bx	lr
.L0801b906:
	adds	r0, #0x54
	bx	lr
.L0801b90a:
	adds	r0, #0x60
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0801b910 - find or create the entry with flag 0x2000000 and a 24-bit key.
@ Parameters: r0 = record pointer (word +0xc = array of 8-byte entries,
@ halfword +0x22 low 9 bits >> 3 = count), r1 = 24-bit key. Returns a pointer
@ to the entry.
@ Scans for an entry whose word 1 has bit 25 (0x2000000) set and key
@ (word 1 & 0xffffff) equal to r1 and returns its address.
@ When absent: grows the array by 8 bytes with fn_08022cb0, shifts all entries
@ up by one, clears entry 0 with clear_bytes, stores fn_08022b50(8) in word 0,
@ calls fn_08026f0e and writes word 1 with flag 0x2000000 and the key; returns
@ the array start.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b910,"ax",%progbits
	.p2align 2
	.global fn_0801b910
	.thumb_func
	.type fn_0801b910, %function
fn_0801b910:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r4, r0
	mov	r5, r1
	ldrh	r6, [r4, #0x22]
	movs	r0, #0
	movs	r3, #4
	ubfx	r1, r6, #3, #6		@ entry count
	ldr	r2, [r4, #0xc]
	b.n	.L0801b93e
	nop				@ padding
.L0801b928:
	add.w	r7, r3, r0, lsl #3
	ldr	r7, [r2, r7]
	lsls.w	ip, r7, #6		@ test bit 25
	bpl.n	.L0801b93c
	bic.w	r7, r7, #0xff000000
	cmp	r7, r5
	beq.n	.L0801b942
.L0801b93c:
	.inst.n	0x1c40			@ adds r0, r0, #1
.L0801b93e:
	cmp	r1, r0
	bhi.n	.L0801b928
.L0801b942:
	cmp	r1, r0
	beq.n	.L0801b94e
	add.w	r0, r2, r0, lsl #3
.L0801b94a:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0801b94e:
	mov.w	r0, #0x4000000
	add.w	r0, r0, r6, ror #9
	ror.w	r0, r0, #0x17
	strh	r0, [r4, #0x22]
	ubfx	r0, r0, #3, #6
	lsls	r1, r0, #3
	mov	r0, r2
	bl	fn_08022cb0
	str	r0, [r4, #0xc]
	ldrh	r0, [r4, #0x22]
	ubfx	r0, r0, #3, #6
	.inst.n	0x1e40			@ subs r0, r0, #1
	beq.n	.L0801b990
	mvn	r2, #7
.L0801b978:
	ldr	r1, [r4, #0xc]
	add.w	r6, r2, r0, lsl #3
	add.w	r3, r1, r0, lsl #3
	add	r6, r1
	.inst.n	0x1e40			@ subs r0, r0, #1
	ldrd	r1, r6, [r6]
	strd	r1, r6, [r3]		@ move the previous entry up
	bne.n	.L0801b978
.L0801b990:
	movs	r1, #8
	ldr	r0, [r4, #0xc]
	bl	clear_bytes
	movs	r0, #8
	bl	fn_08022b50
	ldr	r1, [r4, #0xc]
	str	r0, [r1]
	bl	fn_08026f0e
	ldr	r1, [r4, #0xc]
	ldr	r0, [r1, #4]
	orr.w	r0, r0, #0x2000000
	str	r0, [r1, #4]
	ldr	r1, [r4, #0xc]
	bfi	r0, r5, #0, #0x18	@ insert the 24-bit key
	str	r0, [r1, #4]
	ldr	r0, [r4, #0xc]
	b.n	.L0801b94a

@ ----------------------------------------------------------------------------
@ fn_0801b9bc - blended halfword colour from a selected source.
@ Parameters: r0 = unused, r1 and r2 forwarded, r3 = forwarded. Returns a
@ halfword colour.
@ When bit 0 of the byte at 0x20014294 is clear calls fn_08026824(0x12, 2, ...)
@ else fn_080267f4(0x12, 2, ...) with the same registers, then returns
@ blend_565_0801d9a8(that result, r1, r2).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b9bc,"ax",%progbits
	.p2align 2
	.global fn_0801b9bc
	.thumb_func
	.type fn_0801b9bc, %function
fn_0801b9bc:
	push	{r3, r4, r5, lr}
	ldr	r0, .L0801b9f0
	mov	r5, r1
	mov	r4, r2
	ldrb.w	r0, [r0, #0x20]
	mov.w	r1, #2
	lsls	r0, r0, #0x1f
	mov.w	r0, #0x12
	beq.n	.L0801b9da
	bl	fn_080267f4
	b.n	.L0801b9de
.L0801b9da:
	bl	fn_08026824
.L0801b9de:
	mov	r2, r4
	mov	r1, r5
	bl	blend_565_0801d9a8
	str	r0, [sp]
	ldrh.w	r0, [sp]
	pop	{r3, r4, r5, pc}
	.short	0x0000			@ padding
.L0801b9f0:
	.word	0x20014274

@ ----------------------------------------------------------------------------
@ fn_0801b9f4 - lay out a row of sizes with gaps and alignment.
@ Parameters: r0 = total length, r1 = 0 selects normal layout (non-zero zeroes
@ the first offset), r2 = alignment mode (0..6), r3 = gap (short); stack:
@ sp+0x20 = count, sp+0x24 = pointer to ushort sizes, sp+0x28 = pointer to
@ output offsets (shorts), sp+0x2c = mirror flag. Returns the occupied length
@ (short).
@ Sums sizes plus gaps (modes 4, 5, 6 force gap 0; with a count of 1 they also
@ force mode 1), subtracts one gap, and per mode sets the start offset:
@ 1 = half of the free space, 2 = all of the free space, 5 = gap becomes
@ free / count and the start is half of it, 4 = gap free / (count + 1) and the
@ start = that gap, 6 = gap free / (count - 1) and start 0; 0 starts at 0;
@ 3 leaves offsets[0] unwritten.
@ Fills offsets[i+1] = offsets[i] + size[i] + gap; when the mirror flag is set
@ replaces each offset with (total - offset - size); returns last offset + last
@ size - first offset.
@ The tbb table at 0x0801ba48 selects the start-offset code by mode.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801b9f4,"ax",%progbits
	.p2align 2
	.global fn_0801b9f4
	.thumb_func
	.type fn_0801b9f4, %function
fn_0801b9f4:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov.w	ip, #0
	ldrd	r6, r4, [sp, #0x24]
	ldr	r5, [sp, #0x20]
	ldr.w	r10, [sp, #0x2c]
	mov	r9, ip
	subs	r7, r5, #1
	cbnz	r1, .L0801ba50
	cmp	r2, #5
	beq.n	.L0801ba18
	cmp	r2, #6
	beq.n	.L0801ba18
	cmp	r2, #4
	bne.n	.L0801ba1e
.L0801ba18:
	movs	r3, #0			@ modes 4, 5, 6: gap 0
	cmp	r5, #1
	beq.n	.L0801ba22
.L0801ba1e:
	movs	r1, #0
	b.n	.L0801ba36
.L0801ba22:
	movs	r2, #1			@ count 1: mode 1
	movs.w	r1, #0
.L0801ba28:
	add	ip, r3
	ldrh.w	r8, [r6, r1, lsl #1]
	.inst.n	0x1c49			@ adds r1, r1, #1
	add	ip, r8
	sxth.w	ip, ip			@ running sum of sizes and gaps
.L0801ba36:
	cmp	r1, r5
	bcc.n	.L0801ba28
	sub.w	r1, ip, r3
	sxth	r1, r1
	cmp	r2, #7
	bcs.n	.L0801ba9a
	tbb	[pc, r2]
.L0801ba48:
	.byte	(.L0801ba50 - .L0801ba48)/2
	.byte	(.L0801ba56 - .L0801ba48)/2
	.byte	(.L0801ba5e - .L0801ba48)/2
	.byte	(.L0801ba9a - .L0801ba48)/2
	.byte	(.L0801ba8a - .L0801ba48)/2
	.byte	(.L0801ba74 - .L0801ba48)/2
	.byte	(.L0801ba62 - .L0801ba48)/2
	.byte	0x00			@ padding
.L0801ba50:
	strh.w	r9, [r4]
	b.n	.L0801ba9a
.L0801ba56:
	subs	r1, r0, r1
	add.w	r1, r1, r1, lsr #31
	b.n	.L0801ba84
.L0801ba5e:
	subs	r1, r0, r1
	b.n	.L0801ba86
.L0801ba62:
	subs	r1, r0, r1
	sxth	r1, r1
	sxth	r2, r7
	sdiv	r1, r1, r2
	strh.w	r9, [r4]
	sxth	r3, r1
	b.n	.L0801ba9a
.L0801ba74:
	subs	r1, r0, r1
	sxth	r1, r1
	sxth	r2, r5
	sdiv	r1, r1, r2
	sxth	r3, r1
	add.w	r1, r3, r3, lsr #31
.L0801ba84:
	asrs	r1, r1, #1
.L0801ba86:
	strh	r1, [r4]		@ offsets[0]
	b.n	.L0801ba9a
.L0801ba8a:
	subs	r1, r0, r1
	sxth	r2, r1
	adds	r1, r5, #1
	sxth	r1, r1
	sdiv	r1, r2, r1
	sxth	r3, r1
	strh	r3, [r4]
.L0801ba9a:
	movs	r1, #0
	b.n	.L0801bab6
	nop				@ padding
.L0801baa0:
	ldrh.w	r2, [r4, r1, lsl #1]
	ldrh.w	ip, [r6, r1, lsl #1]
	add	r2, ip
	add.w	ip, r4, r1, lsl #1
	add	r2, r3
	strh.w	r2, [ip, #2]		@ offsets[i+1]
	.inst.n	0x1c49			@ adds r1, r1, #1
.L0801bab6:
	cmp	r1, r7
	bcc.n	.L0801baa0
	add.w	r1, r4, r5, lsl #1
	add.w	r2, r6, r5, lsl #1
	ldrh.w	r1, [r1, #-2]
	ldrh.w	r2, [r2, #-2]
	add	r1, r2
	ldrh	r2, [r4]
	subs	r1, r1, r2
	sxth	r2, r1			@ occupied length
	cmp.w	r10, #0
	beq.n	.L0801baf2
	movs	r1, #0
	b.n	.L0801baee
.L0801badc:
	ldrh.w	r3, [r4, r1, lsl #1]
	ldrh.w	r7, [r6, r1, lsl #1]
	subs	r3, r0, r3
	subs	r3, r3, r7
	strh.w	r3, [r4, r1, lsl #1]	@ mirrored offset
	.inst.n	0x1c49			@ adds r1, r1, #1
.L0801baee:
	cmp	r1, r5
	bcc.n	.L0801badc
.L0801baf2:
	mov	r0, r2
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ fn_0801baf8 - lay out and process the children of an object.
@ Parameter: r0 = object pointer (word +8 = child list: word 0 = array, word 4
@ = count). No return value.
@ Does nothing unless fn_0801b13c(r0) and fn_0801b7c8(r0) are both non-zero.
@ Fills a layout record with fn_08013ce0, clears 12 bytes with clear_bytes,
@ computes the origin from fn_08024bac(r0, 0, 0x32 / 0x12 / 0x10) and
@ fn_08024216 / fn_08024224 plus object shorts +0x14 / +0x16, calls
@ fn_0801be48(child, record, work) for every child, frees four buffers with
@ fn_08022c44, tests fn_08024d20 / fn_080249e4 against 0x27d1 to call
@ fn_08025a00(r0), then fn_080207f4(r0, 0x2b, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801baf8,"ax",%progbits
	.p2align 2
	.global fn_0801baf8
	.thumb_func
	.type fn_0801baf8, %function
fn_0801baf8:
	push	{r4, r5, r6, lr}
	sub	sp, #0x28
	mov	r4, r0
	bl	fn_0801b13c
	mov	r5, r0
	mov	r0, r4
	bl	fn_0801b7c8
	cmp	r5, #0
	beq.n	.L0801bbc8
	cmp	r0, #0
	beq.n	.L0801bbc8
	mov	r1, sp
	mov	r0, r4
	bl	fn_08013ce0
	movs	r1, #0xc
	add	r0, sp, #0x1c
	bl	clear_bytes
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x32
	bl	fn_08024bac
	mov	r5, r0
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x12
	bl	fn_08024bac
	adds	r6, r0, r5
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x10
	bl	fn_08024bac
	add	r5, r0
	mov	r0, r4
	bl	fn_08024216
	ldrh	r1, [r4, #0x14]
	add	r1, r6
	subs	r0, r1, r0
	strh.w	r0, [sp, #0x24]
	mov	r0, r4
	bl	fn_08024224
	ldrh	r1, [r4, #0x16]
	add	r1, r5
	subs	r0, r1, r0
	strh.w	r0, [sp, #0x26]
	movs	r5, #0
	b.n	.L0801bb7a
.L0801bb6a:
	ldr	r0, [r0]
	add	r2, sp, #0x1c
	mov	r1, sp
	ldr.w	r0, [r0, r5, lsl #2]
	bl	fn_0801be48
	.inst.n	0x1c6d			@ adds r5, r5, #1
.L0801bb7a:
	ldr	r0, [r4, #8]
	ldr	r1, [r0, #4]
	cmp	r1, r5
	bhi.n	.L0801bb6a
	ldr	r0, [sp]
	bl	fn_08022c44
	ldr	r0, [sp, #4]
	bl	fn_08022c44
	ldr	r0, [sp, #8]
	bl	fn_08022c44
	ldr	r0, [sp, #0xc]
	bl	fn_08022c44
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024d20
	mov	r5, r0
	movs	r1, #0
	mov	r0, r4
	bl	fn_080249e4
	movw	r1, #0x27d1
	cmp	r5, r1
	beq.n	.L0801bbb8
	cmp	r0, r1
	bne.n	.L0801bbbe
.L0801bbb8:
	mov	r0, r4
	bl	fn_08025a00
.L0801bbbe:
	movs	r2, #0
	movs	r1, #0x2b
	mov	r0, r4
	bl	fn_080207f4
.L0801bbc8:
	add	sp, #0x28
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ hex_digit_value - value of a hexadecimal digit character.
@ Parameter: r0 = ASCII character. Returns 0 to 15 for '0'..'9', 'A'..'F' and
@ 'a'..'f' (values above 0x60 have 0x20 subtracted), 0 for every other
@ character. The tbb table at 0x0801bbec handles 'A'..'F'.
@ ----------------------------------------------------------------------------
	.section .text.hex_digit_value,"ax",%progbits
	.p2align 2
	.global hex_digit_value
	.thumb_func
	.type hex_digit_value, %function
hex_digit_value:
	movs	r1, #0
	sub.w	r2, r0, #0x30
	cmp	r2, #9
	bhi.n	.L0801bbda
	uxtb	r1, r2			@ '0'..'9'
	b.n	.L0801bc08
.L0801bbda:
	cmp	r0, #0x61
	bcc.n	.L0801bbe2
	subs	r0, #0x20		@ lower case to upper case
	uxtb	r0, r0
.L0801bbe2:
	subs	r0, #0x41
	cmp	r0, #6
	bcs.n	.L0801bc08
	tbb	[pc, r0]
.L0801bbec:
	.byte	(.L0801bbf2 - .L0801bbec)/2
	.byte	(.L0801bbf6 - .L0801bbec)/2
	.byte	(.L0801bbfa - .L0801bbec)/2
	.byte	(.L0801bbfe - .L0801bbec)/2
	.byte	(.L0801bc02 - .L0801bbec)/2
	.byte	(.L0801bc06 - .L0801bbec)/2
.L0801bbf2:
	movs	r1, #0xa
	b.n	.L0801bc08
.L0801bbf6:
	movs	r1, #0xb
	b.n	.L0801bc08
.L0801bbfa:
	movs	r1, #0xc
	b.n	.L0801bc08
.L0801bbfe:
	movs	r1, #0xd
	b.n	.L0801bc08
.L0801bc02:
	movs	r1, #0xe
	b.n	.L0801bc08
.L0801bc06:
	movs	r1, #0xf
.L0801bc08:
	mov	r0, r1
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801bc0c - invalidate the bounding box of an arc between two angles.
@ Parameters: r0 = object pointer, r1 = start angle value, r2 = end angle
@ value, r3 = layer argument. No return value.
@ Returns unless fn_080254dc() is non-zero and r1 != r2.
@ Wraps r1 and r2 into 0..0x168 (subtracting 0x168 above 0x168), adds the
@ ushort at +0x24 and wraps again; gets the centre and half size with
@ fn_0801b0ae, the radius fn_080248fa(r0, r3) and the flag
@ fn_08024bac(r0, r3, 0x51) != 0; builds a rectangle with arc_bounding_box and
@ invalidates it with fn_08025446(r0, rectangle).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801bc0c,"ax",%progbits
	.global fn_0801bc0c
	.thumb_func
	.type fn_0801bc0c, %function
fn_0801bc0c:
	push.w	{r4, r5, r6, r7, r8, lr}
	sub	sp, #0x20
	mov	r7, r3
	mov	r4, r2
	mov	r5, r1
	mov	r6, r0
	bl	fn_080254dc
	cmp	r0, #0
	beq.n	.L0801bca8
	cmp	r5, r4
	beq.n	.L0801bca8
	mov.w	r0, #0x168
	cmp	r5, r0
	bls.n	.L0801bc34
	sub.w	r5, r5, #0x168
	uxth	r5, r5
.L0801bc34:
	cmp	r4, r0
	bls.n	.L0801bc3e
	sub.w	r4, r4, #0x168
	uxth	r4, r4
.L0801bc3e:
	ldrh	r1, [r6, #0x24]
	adds	r2, r1, r5
	uxth	r5, r2
	add	r1, r4
	uxth	r4, r1
	cmp	r5, r0
	bls.n	.L0801bc52
	sub.w	r5, r5, #0x168
	uxth	r5, r5
.L0801bc52:
	cmp	r4, r0
	bls.n	.L0801bc5c
	sub.w	r4, r4, #0x168
	uxth	r4, r4
.L0801bc5c:
	add	r2, sp, #0x1c
	add	r1, sp, #0x18
	mov	r0, r6
	bl	fn_0801b0ae
	mov	r1, r7
	mov	r0, r6
	bl	fn_080248fa
	mov	r8, r0
	mov	r0, r6
	mov	r1, r7
	movs	r2, #0x51
	bl	fn_08024bac
	add	r1, sp, #0x10
	cbz	r0, .L0801bc82
	movs	r2, #1
	b.n	.L0801bc84
.L0801bc82:
	movs	r2, #0
.L0801bc84:
	strd	r2, r1, [sp, #8]
	strd	r4, r8, [sp]
	ldrh.w	r0, [sp, #0x1c]
	ldrsh.w	r1, [sp, #0x1a]
	uxth	r2, r0
	ldrsh.w	r0, [sp, #0x18]
	mov	r3, r5
	bl	arc_bounding_box
	add	r1, sp, #0x10
	mov	r0, r6
	bl	fn_08025446
.L0801bca8:
	add	sp, #0x20
	pop.w	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_0801bcae - invalidate the rectangle built from an object's centre.
@ Parameters: r0 = object pointer, r1..r3 are not read (their frame slots sp+0
@ to sp+0xc are overwritten by the rectangle at sp+0, the centre at sp+8 and
@ the half size at sp+0xc); on exit pop restores the first two frame words
@ (the rectangle shorts) into r0 and r1.
@ Calls fn_0801b0ae(r0, &frame+8, &frame+0xc) to get the centre and half size,
@ fn_0801b378(r0, centre, short half size, &rectangle) to build the rectangle,
@ then fn_08025446(r0, &rectangle).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801bcae,"ax",%progbits
	.global fn_0801bcae
	.thumb_func
	.type fn_0801bcae, %function
fn_0801bcae:
	push	{r0, r1, r2, r3, r4, lr}
	mov	r4, r0
	add	r2, sp, #0xc
	add	r1, sp, #8
	bl	fn_0801b0ae
	mov	r3, sp
	ldrsh.w	r2, [sp, #0xc]
	add	r1, sp, #8
	mov	r0, r4
	bl	fn_0801b378
	mov	r1, sp
	mov	r0, r4
	bl	fn_08025446
	pop	{r0, r1, r2, r3, r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0801bcd2 - invalidate the rectangle of one element of an object.
@ Parameters: r0 = object pointer (kept in r4), r1 = index (kept in r5,
@ compared unsigned); r2 and r3 are only saved by the push and restored
@ unchanged. No return value.
@ Returns (via .L0801bdde -> .L0801be44) unless ushort [r0 + 0x82] > r1.
@ r6 = sbfx(fn_08023e7c(r0) * ushort [r0 + 0x84], bits 8..23) (signed 16-bit of
@ the product >> 8); r7 = fn_08024070(r0).
@ Tests bit 3 of byte [r0 + 0x88]: when clear, or when (byte & 7) is neither 1
@ nor 2, tail-jumps (after restoring r2, r3 and lr) to fn_08025400 with r0 =
@ object, r1 = the value byte << 28 left by the lsls, r2 and r3 as passed in.
@ Layout (byte & 7) = 1: r8 = fn_0802499c(r0, 0); r9 = sxth(fn_08024af8(r0, 0)
@ + r8 + ushort [r0 + 0x14] - r7); r8 = sxth(fn_08024bac(r0, 0x50000, 0x49));
@ r7 = fn_08024d2c(r0, 0x20000); rectangle at sp = halfwords [r0 + 0x14],
@ [r0 + 0x16] - (r8 + r7), [r0 + 0x18], [r0 + 0x1a] + (r8 + r7).
@ With n = ushort [r0 + 0x82] - 1: only when n > r1 (signed) sets
@ x0 = r6 * r1 / n + r9 - r8 - r7 and x1 = r6 * (r1 + 1) / n + r9 + r8 + r7
@ (sdiv, halfwords at sp and sp+4) and calls fn_08025446(r0, sp). Then when r1
@ is nonzero: x0 = r6 * (r1 - 1) / n + r9 - r8 - r7, x1 = r6 * r1 / n + r9 +
@ r8 + r7 and calls fn_08025446(r0, sp) at .L0801be3c.
@ Layout 2 (.L0801bdea): r8 = (fn_08024ad4(r0, 0) * ushort [r0 + 0x84]) >> 8
@ (asr, 32-bit); cell = (r6 + r8) / ushort [r0 + 0x82] (sdiv); r9 =
@ fn_0802499c(r0, 0); r5 = fn_08024af8(r0, 0) + r9 + ushort [r0 + 0x14] + r1 *
@ cell; fn_08023eb0(r0, sp) fills the rectangle at sp; x1 = r5 - r7 + cell and
@ x0 = r5 - r7 - r8 are stored to halfwords sp+4 and sp, then
@ fn_08025446(r0, sp) is called.
@ Return: the pop at .L0801be44 restores r2-r10 and pc.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801bcd2,"ax",%progbits
	.global fn_0801bcd2
	.thumb_func
	.type fn_0801bcd2, %function
fn_0801bcd2:
	push.w	{r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r4, r0
	ldrh.w	r0, [r0, #0x82]
	mov	r5, r1
	cmp	r0, r5
	bls.n	.L0801bdde
	mov	r0, r4
	bl	fn_08023e7c
	ldrh.w	r1, [r4, #0x84]
	muls	r0, r1, r0
	sbfx	r6, r0, #8, #0x10
	mov	r0, r4
	bl	fn_08024070
	mov	r7, r0
	ldrb.w	r0, [r4, #0x88]
	lsls	r1, r0, #0x1c
	bpl.n	.L0801bd0e
	and.w	r0, r0, #7
	cmp	r0, #1
	beq.n	.L0801bd18
	cmp	r0, #2
	beq.n	.L0801bdea
.L0801bd0e:
	mov	r0, r4
	pop.w	{r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	b.w	fn_08025400
.L0801bd18:
	movs	r1, #0
	mov	r0, r4
	bl	fn_0802499c
	mov	r8, r0
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024af8
	ldrh	r2, [r4, #0x14]
	add	r0, r8
	add	r0, r2
	subs	r0, r0, r7
	sxth.w	r9, r0
	mov	r0, r4
	mov.w	r1, #0x50000
	movs	r2, #0x49
	bl	fn_08024bac
	sxth.w	r8, r0
	mov.w	r1, #0x20000
	mov	r0, r4
	bl	fn_08024d2c
	mov	r7, r0
	ldrh	r0, [r4, #0x14]
	strh.w	r0, [sp]
	ldrh	r2, [r4, #0x16]
	strh.w	r2, [sp, #2]
	ldrh	r0, [r4, #0x18]
	strh.w	r0, [sp, #4]
	add.w	r0, r8, r7
	ldrh	r1, [r4, #0x1a]
	subs	r2, r2, r0
	add	r0, r1
	strh.w	r2, [sp, #2]
	strh.w	r0, [sp, #6]
	ldrh.w	r0, [r4, #0x82]
	.inst.n	0x1e40			@ subs r0, r0, #1
	cmp	r0, r5
	ble.n	.L0801bdb0
	mul	r1, r6, r5
	sdiv	r2, r1, r0
	add	r2, r9
	sub.w	r1, r2, r8
	subs	r1, r1, r7
	strh.w	r1, [sp]
	adds	r1, r5, #1
	muls	r1, r6, r1
	sdiv	r1, r1, r0
	add	r1, r9
	add.w	r0, r1, r8
	add	r0, r7
	strh.w	r0, [sp, #4]
	mov	r1, sp
	mov	r0, r4
	bl	fn_08025446
.L0801bdb0:
	cmp	r5, #0
	beq.n	.L0801be44
	subs	r0, r5, #1
	mul	r1, r6, r0
	ldrh.w	r0, [r4, #0x82]
	.inst.n	0x1e40			@ subs r0, r0, #1
	sdiv	r2, r1, r0
	add	r2, r9
	sub.w	r1, r2, r8
	subs	r1, r1, r7
	strh.w	r1, [sp]
	muls	r6, r5, r6
	sdiv	r1, r6, r0
	add	r1, r9
	add.w	r0, r1, r8
	b.n	.L0801bde2
.L0801bdde:
	b.n	.L0801be44
	b.n	.L0801bdea
.L0801bde2:
	add	r0, r7
	strh.w	r0, [sp, #4]
	b.n	.L0801be3c
.L0801bdea:
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024ad4
	ldrh.w	r1, [r4, #0x84]
	muls	r0, r1, r0
	asr.w	r8, r0, #8
	ldrh.w	r0, [r4, #0x82]
	add.w	r1, r6, r8
	sdiv	r6, r1, r0
	movs	r1, #0
	mov	r0, r4
	bl	fn_0802499c
	mov	r9, r0
	muls	r5, r6, r5
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024af8
	ldrh	r1, [r4, #0x14]
	add	r0, r9
	add	r1, r5
	adds	r5, r0, r1
	mov	r1, sp
	mov	r0, r4
	bl	fn_08023eb0
	subs	r0, r5, r7
	adds	r1, r0, r6
	sub.w	r0, r0, r8
	strh.w	r1, [sp, #4]
	strh.w	r0, [sp]
.L0801be3c:
	mov	r1, sp
	mov	r0, r4
	bl	fn_08025446
.L0801be44:
	pop.w	{r2, r3, r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ fn_0801be48 - place and size one child object inside a layout cell.
@ r0 = object (r4), r1 = pointer to a table of four halfword-array pointers
@ (r5: [r5+0], [r5+4], [r5+8], [r5+0xc]), r2 = pointer to a record with
@ halfwords at +8 and +0xa (stored in the pushed slot [sp+0x10]). No return
@ value. Epilogue at .L0801c10c (add sp,#0x14 / pop). Literals: 0x0801c114 =
@ 0x00060001, 0x0801c118 = 0x20000550.
@ Returns when any_flag_bit_set(obj, 0x00060001) is non-zero, or r10 =
@ fn_0801b160(obj) is 0, or r9 = fn_0801b8d8(obj) is 0; r7 = fn_0801b14c(obj)
@ (first column index), r6 = fn_0801b8c4(obj) (first row index).
@ Alignment codes: r8 = byte fn_08024bac(obj, 0, halfword at 0x2000055e)
@ (0x20000550 + 0xe); [sp+4] = byte fn_08024bac(obj, 0, halfword at
@ 0x20000564) (0x20000550 + 0x14).
@ Cell size: [sp+0] = sxth(A0[r7+r10-1] + A2[r7+r10-1] - A0[r7]) and r11 =
@ sxth(A1[r6+r9-1] + A3[r6+r9-1] - A1[r6]) with Ak = halfword array [r5+4k]
@ (unsigned ldrh).
@ When fn_0802492a(obj, 0) == 1 the code in r8 is mirrored: 0 -> 2, 2 -> 0,
@ others unchanged.
@ Object size: r10 = sxth(h[obj+0x18] - h[obj+0x14] + 1), r9 = sxth(h[obj+0x1a]
@ - h[obj+0x16] + 1).
@ Horizontal by code r8: 1 -> r8 = A0[r7] + ((cellwidth - r10) + sign bit)
@ asr 1; 2 -> r8 = A0[r7] + cellwidth - rect_width_plus_one(obj); 3 -> r8 =
@ ldrsh A0[r7], r10 = cellwidth, h[obj+0x22] |= 0x400; other -> r8 = ldrsh
@ A0[r7]; codes 1, 2 and others clear bit 0x400 of h[obj+0x22].
@ Vertical by code [sp+4]: 1 -> r7 = A1[r6] + ((cellheight - r9) + sign bit)
@ asr 1; 2 -> r7 = A1[r6] + cellheight - rect_height_plus_one(obj); 3 -> r7 =
@ ldrsh A1[r6], r9 = cellheight, h[obj+0x22] |= 0x200; other -> r7 = ldrsh
@ A1[r6]; codes 1, 2 and others clear bit 0x200.
@ At .L0801bfa0 stores h[obj+0x22]; when rect_width_plus_one(obj) != r10 or
@ rect_height_plus_one(obj) != r9: saves the halfwords at obj+0x14, +0x16,
@ +0x18, +0x1a to [sp+0..6]; fn_08025400(obj); rect_set_width(obj+0x14, r10);
@ rect_set_height(obj+0x14, r9); fn_08025400(obj); fn_080207f4(obj, 0x29, sp);
@ fn_080207f4(fn_08023fa4(obj), 0x22, obj).
@ Offsets: r6 = sxth fn_08024bac(obj, 0, 0x6a), r5 = sxth fn_08024bac(obj, 0,
@ 0x6b), r9 = rect_width_plus_one(obj), r1 = rect_height_plus_one(obj). For
@ each: when bits 14..13 (ubfx #0xd, #2) equal 1 and (v & ~0x6000) is not above
@ 0x7d0: v' = v & ~0x6000, replaced by 0x3e8 - v' when v' is above 0x3e8, then
@ multiplied by r9 (x) or r1 (y) and divided by 100 (sdiv), sxth; otherwise v
@ is kept as read.
@ dx = sxth(r8 + r6 + h[rec+8] - h[obj+0x14]), dy = sxth(r7 + r5 + h[rec+0xa] -
@ h[obj+0x16]); both zero -> return. Else fn_08025400(obj); h[obj+0x14] += dx;
@ h[obj+0x18] += dx; h[obj+0x16] += dy; h[obj+0x1a] += dy; fn_08025400(obj);
@ tail call fn_0802554c(obj, dx, dy, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801be48,"ax",%progbits
	.p2align 2
	.global fn_0801be48
	.thumb_func
	.type fn_0801be48, %function
fn_0801be48:
	push.w	{r0, r1, r2, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r5, r1
	sub	sp, #8
	mov	r4, r0
	ldr	r1, .L0801c114
	bl	any_flag_bit_set
	cmp	r0, #0
	bne.n	.L0801bf58
	mov	r0, r4
	bl	fn_0801b160
	mov	r10, r0
	mov	r0, r4
	bl	fn_0801b8d8
	movs.w	r9, r0
	beq.n	.L0801bf58
	cmp.w	r10, #0
	beq.n	.L0801bf58
	mov	r0, r4
	bl	fn_0801b14c
	mov	r7, r0
	mov	r0, r4
	bl	fn_0801b8c4
	ldr.w	r11, .L0801c118
	mov	r6, r0
	mov	r0, r4
	movs	r1, #0
	ldrh.w	r2, [r11, #0xe]
	bl	fn_08024bac
	and.w	r8, r0, #0xff		@ horizontal alignment code
	mov	r0, r4
	movs	r1, #0
	ldrh.w	r2, [r11, #0x14]
	bl	fn_08024bac
	uxtb	r0, r0
	str	r0, [sp, #4]		@ vertical alignment code
	ldr	r3, [r5]
	add.w	r0, r7, r10
	mvn	r2, #1
	ldr.w	ip, [r5, #8]
	ldrh.w	r1, [r3, r7, lsl #1]
	add.w	r0, r2, r0, lsl #1
	ldrh	r3, [r3, r0]
	ldrh.w	r0, [ip, r0]
	add	r0, r3
	subs	r0, r0, r1
	sxth	r0, r0
	str	r0, [sp]		@ cell width
	ldr	r3, [r5, #4]
	add.w	r0, r6, r9
	add.w	r0, r2, r0, lsl #1
	ldrh.w	r1, [r3, r6, lsl #1]
	ldrh	r2, [r3, r0]
	ldr	r3, [r5, #0xc]
	ldrh	r0, [r3, r0]
	add	r0, r2
	subs	r0, r0, r1
	sxth.w	r11, r0			@ cell height
	movs	r1, #0
	mov	r0, r4
	bl	fn_0802492a
	cmp	r0, #1
	bne.n	.L0801bf0c
	cmp.w	r8, #0
	beq.n	.L0801bf04
	cmp.w	r8, #2
	beq.n	.L0801bf08
	b.n	.L0801bf0c
.L0801bf04:
	movs	r0, #2
	b.n	.L0801bf0a
.L0801bf08:
	movs	r0, #0
.L0801bf0a:
	mov	r8, r0			@ mirrored horizontal code
.L0801bf0c:
	ldrh	r0, [r4, #0x18]
	ldrh	r1, [r4, #0x14]
	subs	r0, r0, r1
	.inst.n	0x1c40			@ adds r0, r0, #1
	sxth.w	r10, r0			@ object width
	ldrh	r0, [r4, #0x1a]
	ldrh	r1, [r4, #0x16]
	subs	r0, r0, r1
	.inst.n	0x1c40			@ adds r0, r0, #1
	sxth.w	r9, r0			@ object height
	mov	r0, r8
	cmp.w	r8, #1
	beq.n	.L0801bf64
	cmp	r0, #2
	beq.n	.L0801bf7a
	ldr	r0, [r5]
	cmp.w	r8, #3
	ldrsh.w	r0, [r0, r7, lsl #1]
	bne.n	.L0801bf8e
	mov	r8, r0
	ldrh	r0, [r4, #0x22]
	ldr.w	r10, [sp]
	orr.w	r0, r0, #0x400
.L0801bf48:
	strh	r0, [r4, #0x22]
	ldr	r0, [sp, #4]
	cmp	r0, #1
	beq.n	.L0801c048
	cmp	r0, #2
	beq.n	.L0801c044
	cmp	r0, #3
	b.n	.L0801bf5a
.L0801bf58:
	b.n	.L0801c10c
.L0801bf5a:
	ldr	r0, [r5, #4]
	ldrsh.w	r7, [r0, r6, lsl #1]
	bne.n	.L0801c046
	b.n	.L0801bf98
.L0801bf64:
	ldr	r1, [r5]
	ldr	r0, [sp]
	sub.w	r0, r0, r10
	ldrh.w	r1, [r1, r7, lsl #1]
	add.w	r0, r0, r0, lsr #31
	add.w	r0, r1, r0, asr #1
	b.n	.L0801bf8c
.L0801bf7a:
	mov	r0, r4
	bl	rect_width_plus_one
	ldr	r1, [r5]
	ldrh.w	r2, [r1, r7, lsl #1]
	ldr	r1, [sp]
	add	r1, r2
	subs	r0, r1, r0
.L0801bf8c:
	sxth	r0, r0
.L0801bf8e:
	mov	r8, r0
	ldrh	r0, [r4, #0x22]
	bic.w	r0, r0, #0x400
	b.n	.L0801bf48
.L0801bf98:
	ldrh	r0, [r4, #0x22]
	mov	r9, r11
	orr.w	r0, r0, #0x200
.L0801bfa0:
	strh	r0, [r4, #0x22]
	mov	r0, r4
	bl	rect_width_plus_one
	cmp	r0, r10
	bne.n	.L0801bfb6
	mov	r0, r4
	bl	rect_height_plus_one
	cmp	r0, r9
	beq.n	.L0801c006
.L0801bfb6:
	ldrh	r0, [r4, #0x14]
	strh.w	r0, [sp]
	ldrh	r0, [r4, #0x16]
	strh.w	r0, [sp, #2]
	ldrh	r0, [r4, #0x18]
	strh.w	r0, [sp, #4]
	ldrh	r0, [r4, #0x1a]
	strh.w	r0, [sp, #6]
	mov	r0, r4
	bl	fn_08025400
	add.w	r0, r4, #0x14
	mov	r1, r10
	mov	r5, r0
	bl	rect_set_width
	mov	r1, r9
	mov	r0, r5
	bl	rect_set_height
	mov	r0, r4
	bl	fn_08025400
	mov	r2, sp
	movs	r1, #0x29
	mov	r0, r4
	bl	fn_080207f4
	mov	r0, r4
	bl	fn_08023fa4
	mov	r2, r4
	movs	r1, #0x22
	bl	fn_080207f4
.L0801c006:
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x6a
	bl	fn_08024bac
	sxth	r6, r0			@ x offset value
	mov	r0, r4
	movs	r1, #0
	movs	r2, #0x6b
	bl	fn_08024bac
	sxth	r5, r0			@ y offset value
	mov	r0, r4
	bl	rect_width_plus_one
	mov	r9, r0
	mov	r0, r4
	bl	rect_height_plus_one
	mov	r1, r0
	ubfx	r0, r6, #0xd, #2
	movs	r2, #0x64
	mov.w	r3, #0x7d0
	mov.w	ip, #0x3e8
	cmp	r0, #1
	beq.n	.L0801c078
	b.n	.L0801c092
	b.n	.L0801c048
.L0801c044:
	b.n	.L0801c05c
.L0801c046:
	b.n	.L0801c070
.L0801c048:
	ldr	r1, [r5, #4]
	sub.w	r0, r11, r9
	add.w	r0, r0, r0, lsr #31
	ldrh.w	r1, [r1, r6, lsl #1]
	add.w	r0, r1, r0, asr #1
	b.n	.L0801c06e
.L0801c05c:
	mov	r0, r4
	bl	rect_height_plus_one
	ldr	r1, [r5, #4]
	ldrh.w	r2, [r1, r6, lsl #1]
	add.w	r1, r2, r11
	subs	r0, r1, r0
.L0801c06e:
	sxth	r7, r0
.L0801c070:
	ldrh	r0, [r4, #0x22]
	bic.w	r0, r0, #0x200
	b.n	.L0801bfa0
.L0801c078:
	bic.w	r0, r6, #0x6000
	cmp	r0, r3
	bgt.n	.L0801c092
	cmp	r0, ip
	ble.n	.L0801c088
	rsb.w	r0, r0, #0x3e8
.L0801c088:
	mul	r0, r0, r9
	sdiv	r0, r0, r2
	sxth	r6, r0
.L0801c092:
	ubfx	r0, r5, #0xd, #2
	cmp	r0, #1
	bne.n	.L0801c0b2
	bic.w	r0, r5, #0x6000
	cmp	r0, r3
	bgt.n	.L0801c0b2
	cmp	r0, ip
	ble.n	.L0801c0aa
	rsb.w	r0, r0, #0x3e8
.L0801c0aa:
	muls	r0, r1, r0
	sdiv	r0, r0, r2
	sxth	r5, r0
.L0801c0b2:
	ldr	r2, [sp, #0x10]
	add.w	r0, r8, r6
	adds	r1, r7, r5
	ldrh	r2, [r2, #8]
	add	r0, r2
	ldrh	r2, [r4, #0x14]
	subs	r0, r0, r2
	sxth	r5, r0			@ dx
	ldr	r0, [sp, #0x10]
	ldrh	r0, [r0, #0xa]
	add	r0, r1
	ldrh	r1, [r4, #0x16]
	subs	r0, r0, r1
	sxth	r6, r0			@ dy
	orrs.w	r0, r5, r6
	beq.n	.L0801c10c
	mov	r0, r4
	bl	fn_08025400
	ldrh	r0, [r4, #0x14]
	add	r0, r5
	strh	r0, [r4, #0x14]
	ldrh	r0, [r4, #0x18]
	add	r0, r5
	strh	r0, [r4, #0x18]
	ldrh	r0, [r4, #0x16]
	add	r0, r6
	strh	r0, [r4, #0x16]
	ldrh	r0, [r4, #0x1a]
	add	r0, r6
	strh	r0, [r4, #0x1a]
	mov	r0, r4
	bl	fn_08025400
	add	sp, #0x14
	mov	r2, r6
	mov	r1, r5
	mov	r0, r4
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	movs	r3, #0
	b.w	fn_0802554c
.L0801c10c:
	add	sp, #0x14
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short	0x0000			@ padding
.L0801c114:
	.word	0x00060001
.L0801c118:
	.word	0x20000550

@ ----------------------------------------------------------------------------
@ find_record_by_callback - find the first record accepted by a callback.
@ Parameters: r0 = function pointer, r1 = argument, r2 = pointer to a result
@ word or 0. Returns 1 when found, else 0.
@ Loops rec = fn_08028968(rec) starting from 0 while the result is nonzero and
@ its word at +4 masked with 0x3fffffff is nonzero. Calls r0(rec, r1) for each;
@ when that returns 1, stores rec to *r2 if r2 is not 0 and returns 1.
@ ----------------------------------------------------------------------------
	.section .text.find_record_by_callback,"ax",%progbits
	.global find_record_by_callback
	.thumb_func
	.type find_record_by_callback, %function
find_record_by_callback:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r6, r0
	mov	r5, r2
	mov	r7, r1
	movs	r0, #0
	b.n	.L0801c136
.L0801c12a:
	mov	r1, r7
	mov	r0, r4
	blx	r6
	cmp	r0, #1
	beq.n	.L0801c14a
	mov	r0, r4
.L0801c136:
	bl	fn_08028968
	movs	r4, r0
	beq.n	.L0801c144
	ldr	r0, [r4, #4]
	lsls	r0, r0, #2
	bne.n	.L0801c12a
.L0801c144:
	movs	r0, #0
.L0801c146:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0801c14a:
	cbz	r5, .L0801c14e
	str	r4, [r5]
.L0801c14e:
	movs	r0, #1
	b.n	.L0801c146

@ ----------------------------------------------------------------------------
@ compare_u16_pair - compare two pairs of unsigned halfwords.
@ Parameters: r0, r1 = pointers to pairs of unsigned halfwords. Returns the
@ difference of the halfwords at +0, and when equal the difference of the
@ halfwords at +2.
@ ----------------------------------------------------------------------------
	.section .text.compare_u16_pair,"ax",%progbits
	.global compare_u16_pair
	.thumb_func
	.type compare_u16_pair, %function
compare_u16_pair:
	ldrh	r3, [r0]
	ldrh	r2, [r1]
	cmp	r3, r2
	beq.n	.L0801c15e
	subs	r0, r3, r2
	bx	lr
.L0801c15e:
	ldrh	r0, [r0, #2]
	ldrh	r1, [r1, #2]
	subs	r0, r0, r1
	bx	lr

@ ----------------------------------------------------------------------------
@ compare_u8_pair - compare two pairs of bytes.
@ Parameters: r0, r1 = pointers to pairs of bytes. Returns the difference of
@ the bytes at +0, and when equal the difference of the bytes at +1.
@ ----------------------------------------------------------------------------
	.section .text.compare_u8_pair,"ax",%progbits
	.global compare_u8_pair
	.thumb_func
	.type compare_u8_pair, %function
compare_u8_pair:
	ldrb	r3, [r0]
	ldrb	r2, [r1]
	cmp	r3, r2
	beq.n	.L0801c172
	subs	r0, r3, r2
	bx	lr
.L0801c172:
	ldrb	r0, [r0, #1]
	ldrb	r1, [r1, #1]
	subs	r0, r0, r1
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0801c17c - remove the record whose key matches and compact the area.
@ Parameters: r0 = record pointer, r1 = pointer to a key word. Returns 1 when
@ the record's word at +4 masked with 0x3fffffff equals *r1, else 0.
@ On match: size = fn_0801b09c(); tail = word 0x20000570 - r0 - size; word
@ 0x20000570 -= size. When tail is not 0: copy_bytes_08022ce0(r0, r0 + size,
@ tail) moves the following data down, then for every record from r0 to the
@ new end subtracts size from its word at +8 stepping by fn_0801b09c(record),
@ then clear_bytes(r0 + tail, size) clears the freed bytes.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c17c,"ax",%progbits
	.p2align 2
	.global fn_0801c17c
	.thumb_func
	.type fn_0801c17c, %function
fn_0801c17c:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r2, [r0, #4]
	ldr	r1, [r1]
	bic.w	r2, r2, #0xc0000000
	cmp	r2, r1
	bne.n	.L0801c1dc
	mov	r4, r0
	bl	fn_0801b09c
	ldr.w	r8, .L0801c1e0
	mov	r5, r0
	ldr.w	r2, [r8, #8]
	subs	r3, r2, r4
	sub.w	r0, r2, r5
	subs	r6, r3, r5
	str.w	r0, [r8, #8]
	beq.n	.L0801c1d6
	mov	r7, r4
	adds	r1, r4, r5
	mov	r2, r6
	mov	r0, r7
	bl	copy_bytes_08022ce0
	b.n	.L0801c1c6
.L0801c1b8:
	ldr	r0, [r4, #8]
	subs	r0, r0, r5
	str	r0, [r4, #8]
	mov	r0, r4
	bl	fn_0801b09c
	add	r4, r0
.L0801c1c6:
	ldr.w	r0, [r8, #8]
	cmp	r4, r0
	bne.n	.L0801c1b8
	adds	r0, r7, r6
	mov	r1, r5
	bl	clear_bytes
.L0801c1d6:
	movs	r0, #1
.L0801c1d8:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0801c1dc:
	movs	r0, #0
	b.n	.L0801c1d8
.L0801c1e0:
	.word	0x20000568

@ ----------------------------------------------------------------------------
@ fn_0801c1e4 - clip a rectangle and report it through the object's class.
@ Parameters: r0 = object pointer, r1 = class table pointer, r2 = pointer to a
@ structure (halfwords at +6, +0xa, +0xe, +0x10; rectangle at +8), r3 = flags.
@ When bit 0 of the flags is clear the local result is 0; otherwise result 1
@ and when fn_08011e9c(r2+8, r0+0x14, 0) is nonzero calls
@ fn_080207f4(r0, 0x12, &local) and uses result 0 if the first byte stays 0.
@ Otherwise sets halfword r2+0xe = halfword r2+0xa + halfword r2+0x10 - 1.
@ Limits halfword r2+0xe to halfword r2+6.
@ Tail-calls call_word_at_0x3c_if_set(r1, r2, result), which calls the function
@ pointer at word r1+0x3c when it is not 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c1e4,"ax",%progbits
	.global fn_0801c1e4
	.thumb_func
	.type fn_0801c1e4, %function
fn_0801c1e4:
	push.w	{r2, r3, r4, r5, r6, r7, r8, lr}
	mov	r6, r0
	mov	r4, r2
	mov	r8, r1
	lsls	r0, r3, #0x1f
	beq.n	.L0801c246
	add.w	r0, r4, #8
	movs	r5, #1
	movs	r2, #0
	add.w	r1, r6, #0x14
	mov	r7, r0
	bl	fn_08011e9c
	cbz	r0, .L0801c21e
	movs	r0, #0
	strb.w	r0, [sp]
	mov	r2, sp
	movs	r1, #0x12
	mov	r0, r6
	str	r7, [sp, #4]
	bl	fn_080207f4
	ldrb.w	r0, [sp]
	cbz	r0, .L0801c246
.L0801c21e:
	ldrh	r0, [r4, #0xa]
	ldrh	r1, [r4, #0x10]
	add	r0, r1
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh	r0, [r4, #0xe]
.L0801c228:
	ldrsh.w	r1, [r4, #0xe]
	ldrsh.w	r0, [r4, #6]
	cmp	r1, r0
	ble.n	.L0801c236
	strh	r0, [r4, #0xe]		@ limit to halfword +6
.L0801c236:
	add	sp, #8
	mov	r2, r5
	mov	r1, r4
	mov	r0, r8
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	call_word_at_0x3c_if_set
.L0801c246:
	movs	r5, #0
	b.n	.L0801c228

@ ----------------------------------------------------------------------------
@ fn_0801c24a - compute the clipped rectangle of a child object.
@ Parameters: r0 = object pointer, r1 = child object, r2 = mode (1 or 2), r3 =
@ pointer to 8-byte output rectangle. Returns 1 on success, 0 otherwise.
@ Calls fn_08012726(r1), fn_08023eb0(r1, &rect) and rect_grow(&rect, value).
@ Mode 1: rect_intersect(&out, word r0+8, &rect) and copies the result.
@ Mode 2: fn_08024d50(r1, &rect2, 0), rect_intersect(&tmp, word r0+8, &rect2),
@ fn_08024d50(r1, &tmp, 0, 1), rect_intersect(&tmp, &tmp, &rect), copies the
@ result.
@ Any other mode, or a failing rect_intersect, returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801c24a,"ax",%progbits
	.global fn_0801c24a
	.thumb_func
	.type fn_0801c24a, %function
fn_0801c24a:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r7, r0
	sub	sp, #0x20
	mov	r5, r3
	mov	r6, r2
	mov	r8, r1
	mov	r0, r1
	bl	fn_08012726
	mov	r4, r0
	add	r1, sp, #8
	mov	r0, r8
	bl	fn_08023eb0
	mov	r2, r4
	mov	r1, r2
	add	r0, sp, #8
	bl	rect_grow
	cmp	r6, #2
	beq.n	.L0801c282
	cmp	r6, #1
	beq.n	.L0801c2ce
	movs	r0, #0
.L0801c27c:
	add	sp, #0x20
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0801c282:
	ldrd	r0, r1, [sp, #8]
	strd	r0, r1, [sp, #0x10]
	movs	r3, #0
	mov	r2, r3
	add	r1, sp, #0x10
	mov	r0, r8
	bl	fn_08024d50
	add	r2, sp, #0x10
	mov	r0, sp
	ldr	r1, [r7, #8]
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L0801c27c
	ldrd	r0, r1, [sp]
	strd	r0, r1, [sp, #0x18]
	movs	r3, #1
	movs	r2, #0
	add	r1, sp, #0x18
	mov	r0, r8
	bl	fn_08024d50
	add	r1, sp, #0x18
	add	r2, sp, #8
	mov	r0, r1
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L0801c27c
	ldr	r0, [sp, #0x18]
	str	r0, [r5]
	ldr	r0, [sp, #0x1c]
	b.n	.L0801c2e2
.L0801c2ce:
	add	r2, sp, #8
	mov	r0, sp
	ldr	r1, [r7, #8]
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L0801c27c
	ldr	r0, [sp]
	str	r0, [r5]
	ldr	r0, [sp, #4]
.L0801c2e2:
	str	r0, [r5, #4]
	movs	r0, #1
	b.n	.L0801c27c
