@ gfx_12.s - graphics helpers: arc set-up, clipped-span test, angle point calculation (batch 12)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0801eba8 - fills an arc structure and computes its two end points.
@ Parameters: r0 = pointer to the structure, r1 and r2 = values stored as
@ halfwords +8 and +0xa, r3 = start angle, stack argument 0 = end angle (loaded
@ with ldr r4,[sp,#32] after the 32-byte push). No return value.
@ Both angles are limited to 0..0x167.
@ Halfword +0x68 = angular span: end - start, or 0x168 - start + end when the
@ end angle is below the start angle.
@ Halfwords +0xc = start, +0xe = end, +8 = r1, +0xa = r2; word +0 = 0x0801e945
@ (function pointer to fn_0801e944); byte +4 = 1.
@ A start angle above 0x168 or an end angle below 0 ends in an endless loop
@ (b to itself).
@ Calls fn_0801edd0(r0+0x10, r1, r2, start, start > 0xb3) and
@ fn_0801edd0(r0+0x3c, r1, r2, end, flag), where flag is 0 when the end
@ angle lies in 0xb4..0x167, else 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801eba8,"ax",%progbits
	.p2align 2
	.global fn_0801eba8
	.thumb_func
	.type fn_0801eba8, %function
fn_0801eba8:
	push.w	{r3, r4, r5, r6, r7, r8, r9, lr}
	mov	r5, r0			@ r5 = structure pointer
	mov	r8, r1			@ r8 = first value
	movw	r0, #0x167		@ r0 = highest angle
	adds	r1, r0, #1		@ r1 = 0x168
	ldr	r4, [sp, #0x20]		@ r4 = end angle (stack argument 0)
	mov	r7, r2			@ r7 = second value
	cmp	r3, #0
	bge.n	.L0801ebc2
	movs	r3, #0			@ start angle below 0 becomes 0
	b.n	.L0801ebc8
.L0801ebc2:
	cmp	r3, r1
	blt.n	.L0801ebc8
	mov	r3, r0			@ start angle of 0x168 or more becomes 0x167
.L0801ebc8:
	cmp	r4, #0
	bge.n	.L0801ebd0
	movs	r4, #0			@ end angle below 0 becomes 0
	b.n	.L0801ebd6
.L0801ebd0:
	cmp	r4, r1
	blt.n	.L0801ebd6
	mov	r4, r0			@ end angle of 0x168 or more becomes 0x167
.L0801ebd6:
	cmp	r4, r3
	bge.n	.L0801ebe2
	rsb.w	r0, r3, #0x168		@ end < start: span = 0x168 - start + end
	add	r0, r4
	b.n	.L0801ebea
.L0801ebe2:
	subs	r0, r4, r3		@ span = end - start
	cmp	r0, #0
	bgt.n	.L0801ebea
	subs	r0, r3, r4		@ span not positive: start - end
.L0801ebea:
	strh.w	r0, [r5, #0x68]		@ halfword +0x68 = span
	strh	r3, [r5, #0xc]		@ halfword +0xc = start angle
	strh	r4, [r5, #0xe]		@ halfword +0xe = end angle
	strh.w	r8, [r5, #0x8]		@ halfword +8 = first value
	strh	r7, [r5, #0xa]		@ halfword +0xa = second value
	ldr	r0, .L0801ec50
	str	r0, [r5, #0]		@ word +0 = function pointer
	movs	r0, #1
	strb	r0, [r5, #4]		@ byte +4 = 1
	cmp	r3, r1
	bls.n	.L0801ec06
.L0801ec04:
	b.n	.L0801ec04		@ endless loop: start angle above 0x168
.L0801ec06:
	cmp	r3, #0xb4
	bcs.n	.L0801ec0e
	movs	r0, #0			@ r0 = 0 when start angle < 0xb4
	b.n	.L0801ec10
.L0801ec0e:
	movs	r0, #1			@ r0 = 1 when start angle >= 0xb4
.L0801ec10:
	cmp	r4, #0
	blt.n	.L0801ec18
	cmp	r3, r1
	ble.n	.L0801ec1a
.L0801ec18:
	b.n	.L0801ec18		@ endless loop: end angle below 0
.L0801ec1a:
	cmp	r4, #0xb4
	bcc.n	.L0801ec2a
	sub.w	r1, r4, #0xb4
	cmp	r1, #0xb4
	bcs.n	.L0801ec2a
	movs	r6, #0			@ r6 = 0 when end angle is in 0xb4..0x167
	b.n	.L0801ec2c
.L0801ec2a:
	movs	r6, #1			@ r6 = 1 otherwise
.L0801ec2c:
	str	r0, [sp, #0]		@ stack argument = flag for the start point
	mov	r2, r7
	mov	r1, r8
	add.w	r0, r5, #0x10		@ destination structure r0+0x10
	bl	fn_0801edd0		@ start point (angle in r3)
	mov	r3, r4
	mov	r2, r7
	mov	r1, r8
	add.w	r0, r5, #0x3c		@ destination structure r0+0x3c
	str	r6, [sp, #0]		@ stack argument = flag for the end point
	bl	fn_0801edd0		@ end point (angle in r3)
	pop.w	{r3, r4, r5, r6, r7, r8, r9, pc}
	.short	0x0000			@ padding
.L0801ec50:
	.word	fn_0801e944		@ function pointer stored at word +0 (0x0801e945)

@ ----------------------------------------------------------------------------
@ fn_0801ec54 - calls every function of the table at 0x200081cc.
@ Parameters: r0..r3 = four values passed on. Returns 0, 1 or 2.
@ Walks the table at 0x200081cc (entries of two words) until an entry whose
@ first word is 0; each first word is a pointer to a structure whose first word
@ is a function pointer; that function is called with (r0, r1, r2, r3, entry
@ pointer on the stack).
@ A result of 0 ends the walk at once and returns 0; a result of 2 sets a flag.
@ At the end of the table returns 2 when the flag was set, else 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ec54,"ax",%progbits
	.p2align 2
	.global fn_0801ec54
	.thumb_func
	.type fn_0801ec54, %function
fn_0801ec54:
	push.w	{r3, r4, r5, r6, r7, r8, r9, lr}
	mov	r6, r3
	mov	r7, r2
	mov	r8, r1
	mov	r9, r0
	movs	r5, #0			@ r5 = flag (result 2 seen)
	ldr	r4, .L0801ec94		@ r4 = table address 0x200081cc
	b.n	.L0801ec82
.L0801ec66:
	str	r0, [sp, #0]		@ stack argument = entry pointer
	ldr.w	r12, [r0, #0]		@ function pointer of the entry
	mov	r3, r6
	mov	r2, r7
	mov	r1, r8
	mov	r0, r9
	blx	r12
	cmp	r0, #0
	beq.n	.L0801ec8c		@ result 0: return 0
	cmp	r0, #2
	bne.n	.L0801ec80
	movs	r5, #1			@ result 2: set the flag
.L0801ec80:
	adds	r4, #8			@ next table entry
.L0801ec82:
	ldr	r0, [r4, #0]		@ first word of the entry
	cmp	r0, #0
	bne.n	.L0801ec66
	cbz	r5, .L0801ec90
	movs	r0, #2
.L0801ec8c:
	pop.w	{r3, r4, r5, r6, r7, r8, r9, pc}
.L0801ec90:
	movs	r0, #1
	b.n	.L0801ec8c
.L0801ec94:
	.word	0x200081cc		@ start of the table

@ ----------------------------------------------------------------------------
@ fn_0801ec98 - releases what a table entry structure holds, by its type byte.
@ Parameter: r0 = structure pointer. No return value.
@ Byte +4 = 2: when word +0x14 is nonzero: if word [+0x14]+0x10 is negative,
@ frees word [[+0x14]+4] with fn_08022c68, then frees word +0x14 itself with
@ fn_08022c68 (tail branch at 0x0801ecaa); otherwise decrements word
@ [+0x14]+0x14.
@ Byte +4 = 5: frees word +8 with fn_08022c68 (tail branch at 0x0801ecaa).
@ Any other value does nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ec98,"ax",%progbits
	.p2align 2
	.global fn_0801ec98
	.thumb_func
	.type fn_0801ec98, %function
fn_0801ec98:
	push	{r4, lr}
	ldrb	r1, [r0, #4]		@ type byte
	cmp	r1, #2
	beq.n	.L0801ecae
	cmp	r1, #5
	bne.n	.L0801eccc
	ldr	r0, [r0, #8]		@ type 5: pointer to free
.L0801eca6:
	pop.w	{r4, lr}
	b.w	fn_08022c68		@ tail call: free r0
.L0801ecae:
	mov	r4, r0
	ldr	r0, [r0, #0x14]
	cmp	r0, #0
	beq.n	.L0801eccc
	ldr	r1, [r0, #0x10]
	cmp	r1, #0
	bge.n	.L0801ecc6
	ldr	r0, [r0, #4]
	bl	fn_08022c68		@ free word [[+0x14]+4]
	ldr	r0, [r4, #0x14]
	b.n	.L0801eca6		@ then free word +0x14
.L0801ecc6:
	ldr	r1, [r0, #0x14]
	.inst.n	0x1e49		@ subs r1, r1, #1
	str	r1, [r0, #0x14]
.L0801eccc:
	pop	{r4, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0801ecd0 - tests whether the entries of the table at 0x200081cc are used.
@ Parameter: r0 = rectangle pointer or 0. Returns 1 or 0.
@ With r0 = 0: returns 1 when the first word at 0x200081cc is nonzero, else 0.
@ Otherwise scans the 16 table entries (two words each): an entry whose first
@ word is 0 is skipped; an entry whose byte +4 is not 2 returns 1; for byte
@ +4 = 2 it calls fn_08011e9c(r0, entry+8, signed halfword entry+0x10) when
@ bit 0 of byte entry+0x12 is clear, else fn_08011f7c(r0, entry+8, halfword
@ entry+0x10), and returns 1 when that result is 0.
@ Returns 0 after all 16 entries.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ecd0,"ax",%progbits
	.p2align 2
	.global fn_0801ecd0
	.thumb_func
	.type fn_0801ecd0, %function
fn_0801ecd0:
	push	{r4, r5, r6, lr}
	ldr	r5, .L0801ed20		@ r5 = table address 0x200081cc
	movs	r6, r0			@ r6 = rectangle pointer; zero: table test only
	beq.n	.L0801ecea
	movs.w	r4, #0			@ r4 = entry index
.L0801ecdc:
	ldr.w	r1, [r5, r4, lsl #3]	@ first word of entry r4
	cbz	r1, .L0801ed12
	ldrb	r0, [r1, #4]
	cmp	r0, #2
	beq.n	.L0801ecf4
	b.n	.L0801ecf0
.L0801ecea:
	ldr	r0, [r5, #0]
	cmp	r0, #0
	beq.n	.L0801ecf2
.L0801ecf0:
	movs	r0, #1
.L0801ecf2:
	pop	{r4, r5, r6, pc}
.L0801ecf4:
	ldrb	r0, [r1, #0x12]
	ldrsh.w	r2, [r1, #0x10]
	lsls	r0, r0, #0x1f		@ sets Z from bit 0 of byte +0x12
	mov	r0, r6
	add.w	r1, r1, #8
	beq.n	.L0801ed0a
	bl	fn_08011f7c
	b.n	.L0801ed0e
.L0801ed0a:
	bl	fn_08011e9c
.L0801ed0e:
	cmp	r0, #0
	beq.n	.L0801ecf0
.L0801ed12:
	.inst.n	0x1c64		@ adds r4, r4, #1
	uxtb	r4, r4
	cmp	r4, #0x10
	bcc.n	.L0801ecdc
	movs	r0, #0
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L0801ed20:
	.word	0x200081cc		@ start of the table

@ ----------------------------------------------------------------------------
@ fn_0801ed24 - decides whether a span of bytes lies inside a shape and clears
@ the part outside.
@ Parameters: r0 = byte buffer, r1 = halfword start offset (y), r2 = halfword
@ line (x), r3 = length, stack argument 0 = edge structure pointer (loaded
@ with ldr r4,[sp,#0x18] after the 24-byte push). Returns 0, 1 or 2.
@ x = r2 - halfword +0x14, y = r1 - halfword +0x12 (both sign-extended
@ halfwords); the test flag is bit 0 of byte +0x28 (shifted to bit 31).
@ When word +0x20 is nonzero: calls fn_0801c4ac (flag clear, bl at 0x0801edca)
@ or fn_0801c358 (flag set, bl at 0x0801ed44) with the edge structure pointer
@ as stack argument and returns its result.
@ Otherwise decides by the low 2 bits of byte +0x10 and the signs of x and y
@ whether the span is fully inside (1), outside (0) or partial (2).
@ For partial spans it clears the leading or trailing bytes with clear_bytes
@ (buffer, count) and returns 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ed24,"ax",%progbits
	.p2align 2
	.global fn_0801ed24
	.thumb_func
	.type fn_0801ed24, %function
fn_0801ed24:
	push	{r3, r4, r5, r6, r7, lr}
	ldr	r4, [sp, #0x18]		@ r4 = edge structure pointer
	ldrh	r5, [r4, #0x14]
	ldr	r6, [r4, #0x20]
	subs	r2, r2, r5
	ldrh	r5, [r4, #0x12]
	sxth	r2, r2			@ r2 = x
	subs	r1, r1, r5
	ldrb.w	r5, [r4, #0x28]
	sxth	r1, r1			@ r1 = y
	lsl.w	r5, r5, #0x1f		@ r5 = bit 0 of byte +0x28 at bit 31
	cbz	r6, .L0801ed4a
	str	r4, [sp, #0]
	cbz	r5, .L0801eda6
	bl	fn_0801c358
	pop	{r3, r4, r5, r6, r7, pc}
.L0801ed4a:
	cbz	r5, .L0801ed6e
	ldrb	r0, [r4, #0x10]
	lsls	r1, r0, #0x1e
	beq.n	.L0801eda2
	and.w	r1, r0, #3
	cmp	r1, #1
	beq.n	.L0801eda2
	cmp	r1, #2
	bne.n	.L0801ed62
	adds	r1, r2, #1
	bmi.n	.L0801eda2
.L0801ed62:
	mvns	r0, r0
	lsls	r0, r0, #0x1e
	bne.n	.L0801edba
	cmp	r2, #0
	bgt.n	.L0801eda2
	b.n	.L0801edba
.L0801ed6e:
	ldrb	r2, [r4, #0x10]
	and.w	r4, r2, #3
	cmp	r4, #2
	beq.n	.L0801eda2
	mvns	r5, r2
	lsls	r5, r5, #0x1e
	beq.n	.L0801eda2
	cmp	r4, #1
	bne.n	.L0801ed86
	cmp	r1, #0
	bgt.n	.L0801eda2
.L0801ed86:
	lsls	r2, r2, #0x1e
	add.w	r2, r1, r3
	beq.n	.L0801ed9e
	cmp	r2, #0
	blt.n	.L0801edba
	rsbs	r1, r1, #0
	bpl.n	.L0801edb6
	movs	r1, #0
	cmp	r3, #0
	ble.n	.L0801edba
	b.n	.L0801edbe
.L0801ed9e:
	cmp	r2, #0
	bge.n	.L0801eda8
.L0801eda2:
	movs	r0, #1			@ fully inside
.L0801eda4:
	pop	{r3, r4, r5, r6, r7, pc}
.L0801eda6:
	b.n	.L0801edca
.L0801eda8:
	rsbs	r2, r1, #0
	bmi.n	.L0801edba
	cmp	r2, r3
	bge.n	.L0801edc6
	subs	r1, r3, r2
	add	r0, r2
	b.n	.L0801edc2
.L0801edb6:
	cmp	r1, r3
	blt.n	.L0801edbe
.L0801edba:
	movs	r0, #0			@ outside
	b.n	.L0801eda4
.L0801edbe:
	cmp	r1, r3
	bge.n	.L0801edc6
.L0801edc2:
	bl	clear_bytes		@ clear the bytes outside the shape
.L0801edc6:
	movs	r0, #2			@ partial
	b.n	.L0801eda4
.L0801edca:
	bl	fn_0801c4ac
	b.n	.L0801eda4

@ ----------------------------------------------------------------------------
@ fn_0801edd0 - computes the second point of a line from a point and an angle.
@ Parameters: r0 = destination structure, r1 and r2 = point (x, y), r3 = angle
@ in degrees, stack argument 0 = flag (loaded with ldr.w r8,[sp,#0x28] after
@ the 40-byte push). No return value.
@ When the angle is above 0xb4, 0xb4 is subtracted (result sign-extended from
@ 16 bits).
@ Calls sine_q15_degrees(angle + 0x5a) and sine_q15_degrees(angle); adds each
@ result shifted right by 5 to r1 and r2 respectively (sign-extended from 16
@ bits) and calls fn_0801ee18(r0, r1, r2, r1 + (first >> 5), r2 + (second >> 5),
@ flag) with the last two arguments on the stack (x2 first, then the flag).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801edd0,"ax",%progbits
	.p2align 2
	.global fn_0801edd0
	.thumb_func
	.type fn_0801edd0, %function
fn_0801edd0:
	push.w	{r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r4, r3			@ r4 = angle
	ldr.w	r8, [sp, #0x28]		@ r8 = flag (stack argument)
	mov	r6, r2			@ r6 = y
	mov	r7, r1			@ r7 = x
	mov	r9, r0			@ r9 = destination structure
	cmp	r3, #0xb4
	ble.n	.L0801ede8
	subs	r4, #0xb4
	sxth	r4, r4
.L0801ede8:
	add.w	r0, r4, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	add.w	r5, r7, r0, asr #5	@ r5 = x + (value >> 5)
	mov	r0, r4
	bl	sine_q15_degrees
	add.w	r0, r6, r0, asr #5	@ r0 = y + (value >> 5)
	sxth	r0, r0
	strd	r0, r8, [sp]		@ stack: y2, flag
	sxth	r3, r5			@ r3 = x2
	mov	r2, r6
	mov	r1, r7
	mov	r0, r9
	bl	fn_0801ee18
	pop.w	{r2, r3, r4, r5, r6, r7, r8, r9, r10, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0801ee18 - fills a line edge structure (0x2c bytes) from two points.
@ Parameters: r0 = structure pointer, r1 and r2 = first point (x, y), r3 and
@ stack argument 0 = second point (x, y), stack argument 1 = flags (loaded with
@ ldrd r6,r9,[sp,#0x20] after the 32-byte push). No return value.
@ Clears 0x2c bytes at r0 with clear_bytes.
@ When both y values are equal and the flags are 3, both y values are
@ decremented (sign-extended from 16 bits).
@ Orders the two points by y (lower y first), then stores halfwords +8 (x of
@ the first point), +0xa (its y), +0xc (x of the second point), +0xe (its y),
@ +0x12 (x of the first point), +0x14 (its y), and byte +0x10 = flags.
@ Bit 0 of byte +0x28 is set when |dx| > |dy|, else cleared.
@ Slopes: word +0x18 = dx * (0x100000 / dy) >> 10 (only when dy is nonzero),
@ word +0x1c = dy * (0x100000 / dx) >> 10 (only when dx is nonzero); words
@ +0x18 and +0x1c start at 0.
@ Word +0x20 = word +0x1c when bit 0 of byte +0x28 is set, else word +0x18.
@ Word +0x24 = word +0x20 >> 2 (arithmetic), negated when word +0x20 is
@ negative.
@ Word +0 = 0x0801ed25 (function pointer to fn_0801ed24), byte +4 = 0.
@ Bit 1 of byte +0x28 depends on flags & 3: 0 clears it, 1 sets it, 2 sets it
@ when word +0x20 is positive else clears it, 3 sets it when word +0x20 is not
@ positive else clears it; any other value leaves it unchanged.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ee18,"ax",%progbits
	.p2align 2
	.global fn_0801ee18
	.thumb_func
	.type fn_0801ee18, %function
fn_0801ee18:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r7, r1			@ r7 = x of first point
	ldrd	r6, r9, [sp, #0x20]	@ r6 = y of second point, r9 = flags
	mov	r8, r3			@ r8 = x of second point
	mov	r5, r2			@ r5 = y of first point
	mov	r4, r0			@ r4 = structure pointer
	movs	r1, #0x2c
	bl	clear_bytes
	cmp	r5, r6
	bne.n	.L0801ee40
	cmp.w	r9, #3
	bne.n	.L0801ee40
	.inst.n	0x1e6d		@ subs r5, r5, #1
	.inst.n	0x1e76		@ subs r6, r6, #1
	sxth	r5, r5
	sxth	r6, r6
.L0801ee40:
	cmp	r5, r6
	ble.n	.L0801ee50
	mov	r0, r8			@ first y above second y: swap the points
	mov	r8, r7
	mov	r7, r0
	mov	r0, r6
	mov	r6, r5
	mov	r5, r0
.L0801ee50:
	strh	r7, [r4, #0x8]
	strh	r5, [r4, #0xa]
	strh.w	r8, [r4, #0xc]
	strh	r6, [r4, #0xe]
	strb.w	r9, [r4, #0x10]		@ byte +0x10 = flags
	strh	r7, [r4, #0x12]
	sub.w	r0, r8, r7		@ r0 = dx
	mov	r3, r9			@ r3 = flags
	strh	r5, [r4, #0x14]
	cmp	r0, #0
	ble.n	.L0801ee70
	mov	r1, r0
	b.n	.L0801ee74
.L0801ee70:
	sub.w	r1, r7, r8		@ r1 = |dx|
.L0801ee74:
	subs	r2, r6, r5		@ r2 = dy
	cmp	r2, #0
	ble.n	.L0801ee7e
	mov	r5, r2
	b.n	.L0801ee80
.L0801ee7e:
	subs	r5, r5, r6		@ r5 = |dy|
.L0801ee80:
	cmp	r1, r5
	ldrb.w	r1, [r4, #0x28]
	ble.n	.L0801ee8e
	orr.w	r1, r1, #1		@ |dx| > |dy|: set bit 0 of byte +0x28
	b.n	.L0801ee92
.L0801ee8e:
	bic.w	r1, r1, #1
.L0801ee92:
	strb.w	r1, [r4, #0x28]
	movs	r5, #0
	str	r5, [r4, #0x1c]
	ldr	r6, .L0801ef2c
	str	r6, [r4, #0]		@ word +0 = function pointer
	str	r5, [r4, #0x18]
	strb	r5, [r4, #4]		@ byte +4 = 0
	lsls	r6, r1, #0x1f		@ Z from bit 0 of byte +0x28
	mov.w	r5, #0x100000
	beq.n	.L0801eec6
	cbz	r0, .L0801eeb6
	sdiv	r6, r5, r0
	muls	r6, r2, r6
	asrs	r6, r6, #0xa
	str	r6, [r4, #0x1c]		@ word +0x1c = dy * (0x100000 / dx) >> 10
.L0801eeb6:
	cbz	r2, .L0801eec2
	sdiv	r2, r5, r2
	muls	r2, r0, r2
	asrs	r0, r2, #0xa
	str	r0, [r4, #0x18]		@ word +0x18 = dx * (0x100000 / dy) >> 10
.L0801eec2:
	ldr	r0, [r4, #0x1c]
	b.n	.L0801eee0
.L0801eec6:
	cbz	r2, .L0801eed2
	sdiv	r6, r5, r2
	muls	r6, r0, r6
	asrs	r6, r6, #0xa
	str	r6, [r4, #0x18]		@ word +0x18 = dx * (0x100000 / dy) >> 10
.L0801eed2:
	cbz	r0, .L0801eede
	sdiv	r0, r5, r0
	muls	r0, r2, r0
	asrs	r0, r0, #0xa
	str	r0, [r4, #0x1c]		@ word +0x1c = dy * (0x100000 / dx) >> 10
.L0801eede:
	ldr	r0, [r4, #0x18]
.L0801eee0:
	str	r0, [r4, #0x20]		@ word +0x20 = slope of the major axis
	lsls	r0, r3, #0x1e		@ Z from flags & 3
	beq.n	.L0801eefa
	and.w	r0, r3, #3
	cmp	r0, #1
	beq.n	.L0801ef00
	cmp	r0, #2
	beq.n	.L0801ef1a
	mvns	r0, r3
	lsls	r0, r0, #0x1e
	beq.n	.L0801ef22
	b.n	.L0801ef08
.L0801eefa:
	bic.w	r0, r1, #2		@ clear bit 1 of byte +0x28
	b.n	.L0801ef04
.L0801ef00:
	orr.w	r0, r1, #2		@ set bit 1 of byte +0x28
.L0801ef04:
	strb.w	r0, [r4, #0x28]
.L0801ef08:
	ldr	r1, [r4, #0x20]
	asrs	r0, r1, #2
	str	r0, [r4, #0x24]
	cmp	r1, #0
	bge.n	.L0801ef16
	rsbs	r0, r0, #0
	str	r0, [r4, #0x24]		@ word +0x24 = -(word +0x20 >> 2)
.L0801ef16:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L0801ef1a:
	ldr	r0, [r4, #0x20]
	cmp	r0, #0
	bgt.n	.L0801ef00
	b.n	.L0801eefa
.L0801ef22:
	ldr	r0, [r4, #0x20]
	cmp	r0, #0
	ble.n	.L0801ef00
	b.n	.L0801eefa
	.short	0x0000			@ padding
.L0801ef2c:
	.word	fn_0801ed24		@ function pointer stored at word +0 (0x0801ed25)

@ ----------------------------------------------------------------------------
@ fn_0801ef30 - clips one row of bytes against a rounded rectangle.
@ Parameters: r0 = byte buffer (kept in r8), r1 = start offset (r6), r2 = line
@ (r7), r3 = length (r4), stack argument 0 = pointer r9 to a structure (loaded
@ with ldr.w r9,[sp,#0x30] after the 12-register push): rectangle at +8,
@ signed halfword +0x10 = radius (r5), bit 0 of byte +0x12 = flag (r10), word
@ +0x14 = corner table pointer T. Returns r0 = 0, 1 or 2 (pop.w at 0x0801efee
@ restores r1..r3 from the push).
@ copy_rect_0801cfe8(sp, r9+8) copies the 4 halfwords of the rectangle to the
@ stack: x0 [sp+0], y0 [sp+2], x1 [sp+4], y1 [sp+6] (read with ldrsh).
@ Rows outside [y0, y1] (y0 > line or y1 < line, signed): flag 0 returns 0
@ (0x0801efec), flag 1 returns 1 (0x0801f006); the buffer is untouched.
@ Corner test: when x0 + radius > start (bgt at 0x0801ef74) or start + length >
@ x1 - radius (not ble at 0x0801ef80), and y0 + radius > line or y1 - radius <
@ line (0x0801ef88, 0x0801ef94), the row is in a corner band (0x0801f00e);
@ otherwise it is a straight row (0x0801ef96).
@ Straight row, flag 0 (0x0801efce): r7 = x0 - start; r7 > length returns 0;
@ r7 >= 0 clears r7 bytes at the buffer (clear_bytes); r5 = x1 - start + 1,
@ r5 <= 0 returns 0; r5 < length clears length - r5 bytes at buffer + r5;
@ returns 1 when r7 == 0 and r5 == length, else 2.
@ Straight row, flag 1 (0x0801ef9c): r0 = max(x0 - start, 0); r0 > length
@ returns 2; count = x1 - start - r0 + 1, reduced to length - r0 when r0 +
@ count > length; count < 0 returns 2; clears count bytes at buffer + r0
@ (clear_bytes at 0x0801f1a0) and returns 2.
@ Corner band (0x0801f00e): w = sxth(x1 - x0 + 1), h = sxth(y1 - y0 + 1), dy =
@ sxth(line - y0); index = radius - dy - 1 when dy < radius (cmp at 0x0801f02a,
@ bge), else dy - (h - radius). With T = word [r9+0x14]: run length r6 =
@ sxth(ushort[[T+0xc] + 2*index + 2] - ushort[[T+0xc] + 2*index]); coverage
@ bytes at [T+4] + ushort[[T+0xc] + 2*index] (r11); inset = ushort[[T+8] +
@ 2*index]; R = sxth((x0 - start) + w - radius + inset) (r9), L = sxth((x0 -
@ start) + radius - inset - 1) (r5).
@ Loop r7 = 0 while r7 < r6 (signed): coverage c = byte[r11 + r6 - r7 - 1]; for
@ flag 0 the bytes at buffer[R + r7] and buffer[L - r7] (each only when 0 <=
@ index < length) become scale_value_by_factor_over_255(c, old byte); for flag
@ 1 the same with 0xff - c (rsb.w at 0x0801f11a).
@ After the loop, flag 0: clears from buffer + clamp(R + r7, 0, length) to the
@ end of the length (r7 is the loop counter after the loop) with clear_bytes at
@ 0x0801f0ea, then clears clamp(L - r6 + 1, 0, length) bytes from the buffer
@ start (0x0801f1a0). Flag 1: with r5 = clamp(L + 1, 0, length) clears
@ clamp(R - r5, 0, length - r5) bytes at buffer + r5 (the span between the two
@ corner runs). Both return 2 (0x0801f1a4 -> 0x0801f00a).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ef30,"ax",%progbits
	.p2align 2
	.global fn_0801ef30
	.thumb_func
	.type fn_0801ef30, %function
fn_0801ef30:
	push.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r8, r0			@ r8 = byte buffer
	ldr.w	r9, [sp, #0x30]		@ r9 = structure pointer (stack argument)
	mov	r6, r1			@ r6 = start offset
	mov	r4, r3			@ r4 = length
	ldrb.w	r0, [r9, #0x12]
	mov	r7, r2			@ r7 = line
	and.w	r10, r0, #1		@ r10 = flag (bit 0 of byte +0x12)
	ldrsh.w	r5, [r9, #0x10]		@ r5 = radius
	mov	r0, sp
	add.w	r1, r9, #8
	bl	copy_rect_0801cfe8	@ copy the rectangle to the stack
	ldrsh.w	r0, [sp, #2]		@ r0 = y0
	cmp.w	r10, #0
	beq.n	.L0801efc0
	cmp	r0, r7
	bgt.n	.L0801f006
	ldrsh.w	r0, [sp, #6]		@ r0 = y1
	cmp	r0, r7
	blt.n	.L0801f006
.L0801ef6c:
	ldrsh.w	r0, [sp, #0]		@ r0 = x0
	adds	r1, r0, r5
	cmp	r1, r6
	bgt.n	.L0801ef82
	ldrsh.w	r2, [sp, #4]		@ r2 = x1
	adds	r1, r6, r4
	subs	r2, r2, r5
	cmp	r1, r2
	ble.n	.L0801ef96
.L0801ef82:
	ldrsh.w	r1, [sp, #2]		@ r1 = y0
	adds	r2, r1, r5
	cmp	r2, r7
	bgt.n	.L0801f00e
	ldrsh.w	r2, [sp, #6]
	subs	r2, r2, r5
	cmp	r2, r7
	blt.n	.L0801f00e
.L0801ef96:
	cmp.w	r10, #0
	beq.n	.L0801efce
	subs	r0, r0, r6		@ flag 1: r0 = x0 - start
	bpl.n	.L0801efa2
	movs	r0, #0
.L0801efa2:
	cmp	r0, r4
	bgt.n	.L0801f00a
	ldrsh.w	r1, [sp, #4]
	subs	r1, r1, r6
	subs	r1, r1, r0
	.inst.n	0x1c49		@ adds r1, r1, #1
	adds	r2, r0, r1
	cmp	r2, r4
	ble.n	.L0801efb8
	subs	r1, r4, r0
.L0801efb8:
	cmp	r1, #0
	blt.n	.L0801f00a
	add	r0, r8
	b.n	.L0801f1a0
.L0801efc0:
	cmp	r0, r7
	bgt.n	.L0801efec
	ldrsh.w	r0, [sp, #6]
	cmp	r0, r7
	blt.n	.L0801efec
	b.n	.L0801ef6c
.L0801efce:
	subs	r7, r0, r6		@ flag 0: r7 = x0 - start
	cmp	r7, r4
	bgt.n	.L0801efec
	cmp	r7, #0
	blt.n	.L0801efe0
	mov	r1, r7
	mov	r0, r8
	bl	clear_bytes		@ clear r7 bytes at the buffer
.L0801efe0:
	ldrsh.w	r0, [sp, #4]
	subs	r5, r0, r6
	.inst.n	0x1c6d		@ adds r5, r5, #1
	cmp	r5, #0
	bgt.n	.L0801eff2
.L0801efec:
	movs	r0, #0
.L0801efee:
	pop.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801eff2:
	cmp	r5, r4
	bge.n	.L0801f000
	subs	r1, r4, r5
	add.w	r0, r8, r5
	bl	clear_bytes		@ clear length - r5 bytes at buffer + r5
.L0801f000:
	cbnz	r7, .L0801f00a
	cmp	r5, r4
	bne.n	.L0801f00a
.L0801f006:
	movs	r0, #1
	b.n	.L0801efee
.L0801f00a:
	movs	r0, #2
	b.n	.L0801efee
.L0801f00e:
	ldrh.w	r3, [sp, #4]
	subs	r2, r0, r6		@ r2 = x0 - start
	subs	r0, r3, r0
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth.w	r12, r0			@ r12 = w
	ldrh.w	r0, [sp, #6]
	subs	r0, r0, r1
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r3, r0			@ r3 = h
	subs	r0, r7, r1
	sxth	r0, r0			@ r0 = dy
	cmp	r0, r5
	bge.n	.L0801f034
	subs	r0, r5, r0
	.inst.n	0x1e40		@ subs r0, r0, #1
	b.n	.L0801f038
.L0801f034:
	subs	r1, r3, r5
	subs	r0, r0, r1
.L0801f038:
	ldr.w	r1, [r9, #0x14]		@ r1 = table pointer T
	sxth	r0, r0			@ r0 = index
	movs	r3, #2
	ldr	r7, [r1, #0xc]
	add.w	r3, r3, r0, lsl #1
	ldrh	r3, [r7, r3]
	ldrh.w	r6, [r7, r0, lsl #1]
	subs	r3, r3, r6
	sxth	r6, r3			@ r6 = run length
	ldr	r3, [r1, #8]
	ldr	r1, [r1, #4]
	ldrh.w	r3, [r3, r0, lsl #1]	@ r3 = inset
	ldrh.w	r0, [r7, r0, lsl #1]
	mov.w	r7, #0			@ r7 = loop counter
	add.w	r11, r0, r1		@ r11 = coverage bytes
	add.w	r0, r2, r12
	subs	r0, r0, r5
	add	r0, r3
	sxth.w	r9, r0			@ r9 = R
	adds	r0, r2, r5
	subs	r0, r0, r3
	.inst.n	0x1e40		@ subs r0, r0, #1
	sxth	r5, r0			@ r5 = L
	cmp.w	r10, #0
	beq.n	.L0801f0c4
	b.n	.L0801f158
.L0801f080:
	subs	r1, r6, r7		@ flag 0 loop body
	add.w	r0, r1, r11
	ldrb.w	r0, [r0, #-1]		@ coverage c
	str	r0, [sp, #8]
	add.w	r0, r9, r7
	movs.w	r10, r0			@ index R + r7
	bmi.n	.L0801f0a8
	cmp	r10, r4
	bge.n	.L0801f0a8
	ldrb.w	r1, [r8, r10]
	ldr	r0, [sp, #8]
	bl	scale_value_by_factor_over_255
	strb.w	r0, [r8, r10]
.L0801f0a8:
	subs.w	r10, r5, r7		@ index L - r7
	bmi.n	.L0801f0c0
	cmp	r10, r4
	bge.n	.L0801f0c0
	ldrb.w	r1, [r8, r10]
	ldr	r0, [sp, #8]
	bl	scale_value_by_factor_over_255
	strb.w	r0, [r8, r10]
.L0801f0c0:
	.inst.n	0x1c7f		@ adds r7, r7, #1
	sxth	r7, r7
.L0801f0c4:
	cmp	r7, r6
	blt.n	.L0801f080
	add.w	r0, r9, r7
	cmp	r0, r4
	bge.n	.L0801f0d4
	mov	r1, r0
	b.n	.L0801f0d6
.L0801f0d4:
	mov	r1, r4
.L0801f0d6:
	cmp	r1, #0
	bge.n	.L0801f0de
	movs	r0, #0
	b.n	.L0801f0e4
.L0801f0de:
	cmp	r0, r4
	blt.n	.L0801f0e4
	mov	r0, r4
.L0801f0e4:
	sxth	r0, r0
	subs	r1, r4, r0
	add	r0, r8
	bl	clear_bytes		@ clear from buffer + clamp(R + r7) to the end
	subs	r0, r5, r6
	adds	r1, r0, #1
	cmp	r1, r4
	bge.n	.L0801f0fa
	mov	r2, r1
	b.n	.L0801f0fc
.L0801f0fa:
	mov	r2, r4
.L0801f0fc:
	cmp	r2, #0
	bge.n	.L0801f104
	movs	r4, #0
	b.n	.L0801f10a
.L0801f104:
	cmp	r1, r4
	bge.n	.L0801f10a
	mov	r4, r1
.L0801f10a:
	sxth	r1, r4
	mov	r0, r8
	b.n	.L0801f1a0
.L0801f110:
	subs	r1, r6, r7		@ flag 1 loop body
	add.w	r0, r1, r11
	ldrb.w	r0, [r0, #-1]
	rsb.w	r0, r0, #0xff		@ 0xff - c
	str	r0, [sp, #8]
	add.w	r0, r9, r7
	movs.w	r10, r0			@ index R + r7
	bmi.n	.L0801f13c
	cmp	r10, r4
	bge.n	.L0801f13c
	ldrb.w	r1, [r8, r10]
	ldr	r0, [sp, #8]
	bl	scale_value_by_factor_over_255
	strb.w	r0, [r8, r10]
.L0801f13c:
	subs.w	r10, r5, r7		@ index L - r7
	bmi.n	.L0801f154
	cmp	r10, r4
	bge.n	.L0801f154
	ldrb.w	r1, [r8, r10]
	ldr	r0, [sp, #8]
	bl	scale_value_by_factor_over_255
	strb.w	r0, [r8, r10]
.L0801f154:
	.inst.n	0x1c7f		@ adds r7, r7, #1
	sxth	r7, r7
.L0801f158:
	cmp	r7, r6
	blt.n	.L0801f110
	adds	r0, r5, #1
	cmp	r0, r4
	bge.n	.L0801f166
	adds	r1, r5, #1
	b.n	.L0801f168
.L0801f166:
	mov	r1, r4
.L0801f168:
	cmp	r1, #0
	bge.n	.L0801f170
	movs	r5, #0
	b.n	.L0801f17a
.L0801f170:
	cmp	r0, r4
	bge.n	.L0801f178
	.inst.n	0x1c6d		@ adds r5, r5, #1
	b.n	.L0801f17a
.L0801f178:
	mov	r5, r4
.L0801f17a:
	sxth	r2, r5
	sub.w	r0, r9, r2
	subs	r1, r4, r2
	cmp	r0, r1
	bge.n	.L0801f18a
	mov	r3, r0
	b.n	.L0801f18c
.L0801f18a:
	mov	r3, r1
.L0801f18c:
	cmp	r3, #0
	bge.n	.L0801f194
	movs	r0, #0
	b.n	.L0801f19a
.L0801f194:
	cmp	r0, r1
	blt.n	.L0801f19a
	mov	r0, r1
.L0801f19a:
	sxth	r1, r0
	add.w	r0, r8, r2
.L0801f1a0:
	bl	clear_bytes
	b.n	.L0801f00a
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0801f1a8 - initialises a rounded-rectangle clip structure.
@ Parameters: r0 = structure pointer (r6), r1 = rectangle pointer (4 halfwords:
@ left, top, right, bottom), r2 = radius (signed, r5), r3 = byte value (r4). No
@ return value (ends by pop, or by the tail branch b.w to fn_08014758).
@ Width = sxth(h[r1+4] - h[r1+0] + 1), height = sxth(h[r1+6] - h[r1+2] + 1);
@ m = the smaller of the two (signed); radius = m >> 1 (asrs) when r2 > m >> 1;
@ radius = 0 when negative.
@ copy_rect_0801cfe8(struct+8, r1) copies the rectangle; halfword [struct+0x10]
@ = radius; byte [struct+0x12] = r3; word [struct+0] = 0x0801ef31 (function
@ pointer to fn_0801ef30, literal at 0x0801f2c4); byte [struct+4] = 2.
@ Radius 0: word [struct+0x14] = 0 and return.
@ Search of the 4 entries of 28 bytes at 0x2000815c (word +0x10 weight, word
@ +0x14 use count, signed halfword +0x18 radius): an entry whose radius equals
@ r5 gets word +0x14 += 1 and word +0x10 = min(1000, weight + inc), inc = 1 when
@ r5 < 16 else r5 >> 4; word [struct+0x14] = entry; return.
@ No match: r4 = 0; for each entry whose use count (word +0x14) is 0, r4 = the
@ entry when r4 is 0 or when its weight (word +0x10) is below the weight of r4
@ (signed).
@ r4 nonzero: word [r4+0x10] = 0 and word [r4+0x14] += 1 (strd), then word
@ [r4+0x10] = min(1000, inc).
@ r4 zero: r4 = fn_08022b50(0x1c); clear_bytes(r4, 0x1c); word [r4+0x10] =
@ 0xffffffff.
@ Finally word [struct+0x14] = r4; r0 = r4, r1 = radius; pops and tail-branches
@ to fn_08014758.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801f1a8,"ax",%progbits
	.p2align 2
	.global fn_0801f1a8
	.thumb_func
	.type fn_0801f1a8, %function
fn_0801f1a8:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r5, r2			@ r5 = radius
	mov	r6, r0			@ r6 = structure pointer
	ldrh	r0, [r1, #4]
	ldrh	r2, [r1, #0]
	mov	r4, r3			@ r4 = byte value
	subs	r0, r0, r2
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r2, r0			@ r2 = width
	ldrh	r0, [r1, #6]
	ldrh	r3, [r1, #2]
	subs	r0, r0, r3
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r0, r0			@ r0 = height
	cmp	r2, r0
	bge.n	.L0801f1cc
	mov	r0, r2			@ r0 = the smaller of width and height
.L0801f1cc:
	cmp.w	r5, r0, asr #1
	ble.n	.L0801f1d4
	asrs	r5, r0, #1		@ radius limited to half of the smaller side
.L0801f1d4:
	cmp	r5, #0
	bge.n	.L0801f1da
	movs	r5, #0			@ negative radius becomes 0
.L0801f1da:
	add.w	r0, r6, #8
	bl	copy_rect_0801cfe8	@ copy the rectangle to struct+8
	strh	r5, [r6, #0x10]		@ halfword +0x10 = radius
	strb	r4, [r6, #0x12]		@ byte +0x12 = r3
	ldr	r0, .L0801f2c4
	str	r0, [r6, #0]		@ word +0 = function pointer
	movs	r0, #2
	strb	r0, [r6, #4]		@ byte +4 = 2
	movs	r3, #0
	cbz	r5, .L0801f224
	ldr	r0, .L0801f2c8		@ r0 = 0x2000815c (4 entries of 28 bytes)
	movs	r1, #0			@ r1 = entry index
	mov.w	r2, #0x3e8		@ r2 = 1000
	nop
.L0801f1fc:
	rsb	r4, r1, r1, lsl #3	@ r4 = index * 7
	add.w	r4, r0, r4, lsl #2	@ r4 = entry address
	ldrsh.w	r4, [r4, #0x18]		@ entry radius
	cmp	r4, r5
	bne.n	.L0801f244
	rsb	r1, r1, r1, lsl #3
	add.w	r0, r0, r1, lsl #2	@ r0 = matching entry
	ldr	r1, [r0, #0x14]
	.inst.n	0x1c49		@ adds r1, r1, #1
	str	r1, [r0, #0x14]		@ use count + 1
	ldr	r1, [r0, #0x10]		@ r1 = weight
	cmp	r5, #0x10
	bge.n	.L0801f22a
	movs	r3, #1			@ inc = 1 when radius < 16
	b.n	.L0801f22c
.L0801f224:
	str	r3, [r6, #0x14]		@ radius 0: word +0x14 = 0
.L0801f226:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0801f22a:
	asrs	r3, r5, #4		@ inc = radius >> 4
.L0801f22c:
	add	r3, r1			@ weight + inc
	cmp	r3, r2
	bge.n	.L0801f23e
	cmp	r5, #0x10
	bge.n	.L0801f23a
	movs	r2, #1
	b.n	.L0801f23c
.L0801f23a:
	asrs	r2, r5, #4
.L0801f23c:
	add	r2, r1			@ r2 = weight + inc (below 1000)
.L0801f23e:
	str	r2, [r0, #0x10]		@ word +0x10 = min(1000, weight + inc)
	str	r0, [r6, #0x14]
	b.n	.L0801f226
.L0801f244:
	.inst.n	0x1c49		@ adds r1, r1, #1
	cmp	r1, #4
	bcc.n	.L0801f1fc
	movs	r4, #0			@ no match: search an unused entry
.L0801f24a:
	mov.w	r1, r4
.L0801f250:
	rsb	r7, r1, r1, lsl #3
	add.w	r7, r0, r7, lsl #2	@ r7 = entry address
	ldr.w	r12, [r7, #0x14]
	cmp.w	r12, #0
	bne.n	.L0801f272
	cbz	r4, .L0801f270
	ldr.w	r12, [r7, #0x10]
	ldr.w	lr, [r4, #0x10]
	cmp	r12, lr
	bge.n	.L0801f272
.L0801f270:
	mov	r4, r7
.L0801f272:
	.inst.n	0x1c49		@ adds r1, r1, #1
	cmp	r1, #4
	bcc.n	.L0801f250
	cbz	r4, .L0801f28a
	ldr	r0, [r4, #0x14]
	.inst.n	0x1c40		@ adds r0, r0, #1
	strd	r3, r0, [r4, #0x10]	@ word +0x10 = 0, word +0x14 = use count + 1
	cmp	r5, #0x10
	bge.n	.L0801f2a0
	movs	r0, #1
	b.n	.L0801f2a2
.L0801f28a:
	movs	r0, #0x1c
	bl	fn_08022b50		@ r0 = new block of 0x1c bytes
	mov	r4, r0
	movs	r1, #0x1c
	bl	clear_bytes
	mov.w	r0, #0xffffffff
	str	r0, [r4, #0x10]		@ word +0x10 = 0xffffffff
	b.n	.L0801f2b6
.L0801f2a0:
	asrs	r0, r5, #4
.L0801f2a2:
	add	r0, r3
	cmp	r0, r2
	bge.n	.L0801f2b4
	cmp	r5, #0x10
	bge.n	.L0801f2b0
	movs	r0, #1
	b.n	.L0801f2b2
.L0801f2b0:
	asrs	r0, r5, #4
.L0801f2b2:
	adds	r2, r3, r0		@ r2 = weight + inc
.L0801f2b4:
	str	r2, [r4, #0x10]		@ word +0x10 = min(1000, weight + inc)
.L0801f2b6:
	mov	r0, r4
	mov	r1, r5
	str	r4, [r6, #0x14]
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08014758		@ tail call (r0 = entry, r1 = radius)
.L0801f2c4:
	.word	fn_0801ef30		@ function pointer stored at word +0 (0x0801ef31)
.L0801f2c8:
	.word	0x2000815c		@ start of the 4 entries of 28 bytes

@ ----------------------------------------------------------------------------
@ fn_0801f2cc - clears every table slot whose second word equals r0.
@ Parameter: r0 = second word to search for. Returns a word.
@ Scans the 16 slot pairs at 0x200081cc / 0x200081d0 (two words per slot); for
@ each slot whose second word equals r0 it remembers the slot's first word and
@ clears the slot with table_slot_clear.
@ Returns the first word of the last cleared slot, or 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801f2cc,"ax",%progbits
	.p2align 2
	.global fn_0801f2cc
	.thumb_func
	.type fn_0801f2cc, %function
fn_0801f2cc:
	push	{r4, r5, r6, r7, lr}
	movs	r5, #0			@ r5 = result
	ldr	r6, .L0801f2f8		@ r6 = table address 0x200081cc
	mov	r7, r0			@ r7 = word to search for
	mov	r4, r5			@ r4 = slot index
	nop
.L0801f2d8:
	add.w	r0, r6, r4, lsl #3
	ldr	r0, [r0, #4]		@ second word of the slot
	cmp	r0, r7
	bne.n	.L0801f2ec
	ldr.w	r5, [r6, r4, lsl #3]	@ remember the first word
	mov	r0, r4
	bl	table_slot_clear
.L0801f2ec:
	.inst.n	0x1c64		@ adds r4, r4, #1
	uxtb	r4, r4
	cmp	r4, #0x10
	bcc.n	.L0801f2d8
	mov	r0, r5
	pop	{r4, r5, r6, r7, pc}
.L0801f2f8:
	.word	0x200081cc		@ start of the table

@ ----------------------------------------------------------------------------
@ table_slot_clear - clears one slot of the table at 0x200081cc.
@ Parameter: r0 = slot index or 0xffffffff. Returns the first word of the slot,
@ or 0.
@ For an index other than -1 reads the word at 0x200081cc + index*8, writes 0
@ to it and to the word at 0x200081d0 + index*8.
@ ----------------------------------------------------------------------------
	.section .text.table_slot_clear,"ax",%progbits
	.p2align 2
	.global table_slot_clear
	.thumb_func
	.type table_slot_clear, %function
table_slot_clear:
	movs	r1, #0			@ r1 = result
	adds	r2, r0, #1
	beq.n	.L0801f314		@ index -1: return 0
	ldr	r2, .L0801f318		@ r2 = table address 0x200081cc
	movs	r3, #0
	ldr.w	r1, [r2, r0, lsl #3]	@ result = first word of the slot
	str.w	r3, [r2, r0, lsl #3]	@ clear the first word
	add.w	r0, r2, r0, lsl #3
	str	r3, [r0, #4]		@ clear the second word
.L0801f314:
	mov	r0, r1
	bx	lr
.L0801f318:
	.word	0x200081cc		@ start of the table

@ ----------------------------------------------------------------------------
@ fn_0801f31c - calls the function pointer of an object for a non-empty
@ rectangle.
@ Parameters: r0 = object pointer, r1 = style, r2 = rectangle pointer. No
@ return value.
@ Returns when the rectangle height (halfword +6 - halfword +2 + 1) or width
@ (halfword +4 - halfword +0 + 1) is below 1 (signed 16-bit).
@ Otherwise restores r4 and r5 and branches (bx r3, at 0x0801f33e) to the
@ function pointer at word r0+0xc, with r0, r1, r2 unchanged.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801f31c,"ax",%progbits
	.p2align 2
	.global fn_0801f31c
	.thumb_func
	.type fn_0801f31c, %function
fn_0801f31c:
	push	{r4, r5}
	ldrh	r3, [r2, #6]
	ldrh	r4, [r2, #2]
	subs	r3, r3, r4
	.inst.n	0x1c5b		@ adds r3, r3, #1
	sxth	r3, r3			@ height
	cmp	r3, #1
	blt.n	.L0801f340
	ldrh	r3, [r2, #4]
	ldrh	r4, [r2, #0]
	subs	r3, r3, r4
	.inst.n	0x1c5b		@ adds r3, r3, #1
	sxth	r3, r3			@ width
	cmp	r3, #1
	blt.n	.L0801f340
	ldr	r3, [r0, #0xc]		@ function pointer of the object
	pop	{r4, r5}
	bx	r3
.L0801f340:
	pop	{r4, r5}
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801f344 - initialises a 0x38-byte style structure.
@ Parameter: r0 = structure pointer. No return value.
@ Clears 0x38 bytes with clear_bytes. Halfwords +4 and +6 = low halfword of
@ fn_0801da8a() (called twice), halfwords +0xa, +0x1e and +0x2c = low halfword
@ of fn_0801d6f4() (called three times). Bytes +0xc, +3, +0x1a, +0x2a, +0x22
@ and +0x36 = 0xff, byte +0xe = 2, word +0x14 = 0x0802ce5c.
@ Byte +0x23 = (byte +0x23 & 0xc1) + 0x1e (bic 0x3e, then add 0x1e).
@ The code keeps r4 = r0 + 4 after the first strh (write-back), so the later
@ stores use offsets reduced by 4.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801f344,"ax",%progbits
	.p2align 2
	.global fn_0801f344
	.thumb_func
	.type fn_0801f344, %function
fn_0801f344:
	push	{r3, r4, r5, lr}
	mov	r4, r0
	movs	r1, #0x38
	bl	clear_bytes
	bl	fn_0801da8a
	str	r0, [sp, #0]
	ldrh.w	r0, [sp, #0]
	strh.w	r0, [r4, #4]!		@ halfword +4; r4 = r0 + 4
	bl	fn_0801da8a
	str	r0, [sp, #0]
	ldrh.w	r0, [sp, #0]
	strh	r0, [r4, #2]		@ halfword +6
	bl	fn_0801d6f4
	str	r0, [sp, #0]
	ldrh.w	r0, [sp, #0]
	strh	r0, [r4, #6]		@ halfword +0xa
	movs	r5, #0xff
	strb	r5, [r4, #8]		@ byte +0xc = 0xff
	movs	r0, #2
	strb	r0, [r4, #0xa]		@ byte +0xe = 2
	bl	fn_0801d6f4
	str	r0, [sp, #0]
	ldrh.w	r0, [sp, #0]
	strh	r0, [r4, #0x1a]		@ halfword +0x1e
	bl	fn_0801d6f4
	str	r0, [sp, #0]
	ldrh.w	r0, [sp, #0]
	strh	r0, [r4, #0x28]		@ halfword +0x2c
	ldr	r0, .L0801f3b4
	str	r0, [r4, #0x10]		@ word +0x14 = 0x0802ce5c
	strb.w	r5, [r4, #-1]		@ byte +3 = 0xff
	strb	r5, [r4, #0x16]		@ byte +0x1a = 0xff
	strb.w	r5, [r4, #0x26]		@ byte +0x2a = 0xff
	strb	r5, [r4, #0x1e]		@ byte +0x22 = 0xff
	strb.w	r5, [r4, #0x32]		@ byte +0x36 = 0xff
	ldrb	r0, [r4, #0x1f]		@ byte +0x23
	bic.w	r0, r0, #0x3e
	adds	r0, #0x1e
	strb	r0, [r4, #0x1f]
	pop	{r3, r4, r5, pc}
.L0801f3b4:
	.word	d_0802ce5c		@ literal 0x0802ce5c

@ ----------------------------------------------------------------------------
@ fn_0801f3b8 - draws a circle or arc outline of a given pen width.
@ Parameters: r0 = target object (r11), r1 = pen structure (r7: halfword +0,
@ halfword +2 = width, word +8, byte +0x0c, byte +0x0d), r2 = pointer to the
@ centre (r4: halfword x at +0, halfword y at +2), r3 = radius (r8), first stack
@ argument = start angle (r6, [sp+0x150] on entry), second stack argument = end
@ angle (r5). No return value. The frame is 300 bytes (push r4-r11,lr and
@ sub sp,#0x12c).
@ Returns at once (0x0801f52a) when byte [r1+0x0c] is 2 or less, when signed
@ halfword [r1+2] is 0, or when start angle = end angle.
@ r9 = signed halfword [r1+2] if it is not above r8, else sxth(r8); r10 =
@ sxth(r8).
@ Style block at sp+4 initialised with fn_0801f344; byte sp+6 = byte [r1+0x0d]
@ & 3; when word [r1+8] is non-zero byte sp+7 = 0, word sp+0x14 = word [r1+8],
@ byte sp+0x1e = byte [r1+0x0c]; else byte sp+7 = byte [r1+0x0c] and halfword
@ sp+8 = halfword [r1].
@ Outer rectangle at sp+0x40 = (x - r8, y - r8, x + r8 - 1, y + r8 - 1); inner
@ rectangle at sp+0xd0 = the outer rectangle shrunk by halfword [r1+2] on every
@ side.
@ Word sp+0x10c = -1 and word sp+0x110 = 0; when the inner rectangle has
@ positive width and height: fn_0801f1a8(sp+0xdc, sp+0xd0, 0x7fff, 1), word
@ sp+0x110 = 1, word sp+0x10c = table_slot_insert(sp+0xdc, 0).
@ Outer record: fn_0801f1a8(sp+0xf4, sp+0x40, 0x7fff, 0), word sp+0x114 =
@ table_slot_insert(sp+0xf4, 0).
@ Full circle (start + 0x168 = end or end + 0x168 = start): halfword sp+4 =
@ 0x7fff, fn_0801f31c(r0, sp+4, sp+0x40), table_slot_clear(sp+0x114),
@ table_slot_clear(sp+0x10c) when it is not -1, fn_0801ec98(sp+0xf4),
@ fn_0801ec98(sp+0xdc) when word sp+0x110 is non-zero, then returns (no end
@ caps).
@ Otherwise start and end are each reduced by 0x168 while at or above 0x168
@ (uxth); fn_0801eba8(sp+0x64, x, y, start, stack end) (end angle saved at
@ sp+0x124, start angle at sp+0x128), word sp+0x118 = table_slot_insert(sp+0x64,
@ 0); span = start - end when end is not above start, else 0x168 - (end -
@ start); word [r0+8] saved in sp+0.
@ When span is above 0x3c (signed) and r8 is above 10 (unsigned): work
@ structure at sp+0x48 (word +0 = r2, halfword +4 = sl, +6 = start, +8 = end,
@ +0x0a = (end/0x5a)&3, +0x0c = (start/0x5a)&3, +0x0e = r9, word +0x10 = sp+4,
@ word +0x14 = sp+0x40, word +0x18 = r11) and calls fn_08017c64, fn_08017df4,
@ fn_08017f92 and fn_0801816e each with r0 = sp+0x48; otherwise
@ fn_0801f31c(r11, sp+4, sp+0x40).
@ Then fn_0801ec98(sp+0x64), fn_0801ec98(sp+0xf4), fn_0801ec98(sp+0xdc) when
@ word sp+0x110 is non-zero, table_slot_clear(sp+0x118),
@ table_slot_clear(sp+0x114), table_slot_clear(sp+0x10c) when not -1.
@ When bit 2 of byte [r7+0x0d] is set, end caps for the end angle (saved at
@ sp+0x128) and the start angle (sp+0x124) in turn: fn_0801b752(angle, sl,
@ r9 & 0xff, sp+0x48) gives a rectangle, whose x halfwords (+0, +4) get halfword
@ [r4] added and whose y halfwords (+2, +6) get halfword [r4+2] added;
@ rect_intersect(sp+0x54, saved word, sp+0x48): when non-zero
@ fn_0801f1a8(sp+0x10c, sp+0x48, 0x7fff, 0), table_slot_insert(sp+0x10c, 0),
@ word [r11+8] = sp+0x54, fn_0801f31c(r11, sp+4, sp+0x40), table_slot_clear and
@ fn_0801ec98(sp+0x10c); finally word [r11+8] = the saved word.
@ Epilogue 0x0801f52a: add sp,#0x12c, pop r4-r11,pc.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801f3b8,"ax",%progbits
	.global fn_0801f3b8
	.thumb_func
	.type fn_0801f3b8, %function
fn_0801f3b8:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x12c
	mov	r11, r0			@ r11 = target object
	ldrd	r6, r5, [sp, #0x150]	@ r6 = start angle, r5 = end angle
	ldrb	r0, [r1, #0xc]
	mov	r8, r3			@ r8 = radius
	mov	r4, r2			@ r4 = centre pointer
	mov	r7, r1			@ r7 = pen structure
	cmp	r0, #2
	bls.n	.L0801f4cc
	ldrsh.w	r0, [r7, #2]		@ pen width
	cmp	r0, #0
	beq.n	.L0801f4cc
	cmp	r6, r5
	beq.n	.L0801f4cc
	sxth	r2, r3
	mov	r9, r0
	mov	r10, r2			@ r10 = sxth(radius)
	cmp	r0, r8
	ble.n	.L0801f3e8
	mov	r9, r2			@ r9 = sxth(radius) when the width is above it
.L0801f3e8:
	add	r0, sp, #4
	bl	fn_0801f344		@ initialise the style block at sp+4
	ldrb	r0, [r7, #0xd]
	and.w	r0, r0, #3
	strb.w	r0, [sp, #6]
	ldr	r0, [r7, #8]
	cbz	r0, .L0801f40e
	movs	r0, #0
	strb.w	r0, [sp, #7]
	ldr	r0, [r7, #8]
	str	r0, [sp, #0x14]
	ldrb	r0, [r7, #0xc]
	strb.w	r0, [sp, #0x1e]
	b.n	.L0801f41a
.L0801f40e:
	ldrb	r0, [r7, #0xc]
	strb.w	r0, [sp, #7]
	ldrh	r0, [r7, #0]
	strh.w	r0, [sp, #8]
.L0801f41a:
	ldrh	r1, [r4, #0]
	sub.w	r3, r8, #1
	sub.w	r2, r1, r8
	strh.w	r2, [sp, #0x40]		@ outer rectangle left = x - radius
	ldrh	r1, [r4, #2]
	sub.w	r1, r1, r8
	strh.w	r1, [sp, #0x42]		@ outer rectangle top = y - radius
	ldrh	r0, [r4, #0]
	add	r0, r3
	strh.w	r0, [sp, #0x44]		@ outer rectangle right = x + radius - 1
	ldrh.w	r12, [r4, #2]
	strh.w	r0, [sp, #0xd4]
	add	r3, r12
	strh.w	r3, [sp, #0x46]		@ outer rectangle bottom = y + radius - 1
	strh.w	r2, [sp, #0xd0]
	strh.w	r1, [sp, #0xd2]
	strh.w	r3, [sp, #0xd6]
	ldrh.w	r12, [r7, #2]
	add	r2, r12
	strh.w	r2, [sp, #0xd0]		@ inner rectangle left
	ldrh.w	r12, [r7, #2]
	add	r1, r12
	sxth	r1, r1
	strh.w	r1, [sp, #0xd2]		@ inner rectangle top
	ldrh.w	r12, [r7, #2]
	sub.w	r0, r0, r12
	strh.w	r0, [sp, #0xd4]		@ inner rectangle right
	ldrh.w	r12, [r7, #2]
	subs	r0, r0, r2
	sub.w	r3, r3, r12
	mov.w	r12, #0xffffffff
	sxth	r3, r3
	str.w	r12, [sp, #0x10c]	@ word sp+0x10c = -1
	.inst.n	0x1c40		@ adds r0, r0, #1
	strh.w	r3, [sp, #0xd6]		@ inner rectangle bottom
	mov.w	r12, #0
	sxth	r0, r0			@ inner width
	str.w	r12, [sp, #0x110]	@ word sp+0x110 = 0
	cmp	r0, #0
	ble.n	.L0801f4c4
	subs	r0, r3, r1
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r0, r0			@ inner height
	cmp	r0, #0
	ble.n	.L0801f4c4
	movs	r3, #1
	movw	r2, #0x7fff
	add	r1, sp, #0xd0
	add	r0, sp, #0xdc
	bl	fn_0801f1a8		@ inner clip structure
	movs	r0, #1
	str	r0, [sp, #0x110]
	movs	r1, #0
	add	r0, sp, #0xdc
	bl	table_slot_insert
	str	r0, [sp, #0x10c]
.L0801f4c4:
	movs	r3, #0
	movw	r2, #0x7fff
	b.n	.L0801f4ce
.L0801f4cc:
	b.n	.L0801f52a
.L0801f4ce:
	add	r1, sp, #0x40
	add	r0, sp, #0xf4
	bl	fn_0801f1a8		@ outer clip structure
	movs	r1, #0
	add	r0, sp, #0xf4
	bl	table_slot_insert
	str	r0, [sp, #0x114]
	add.w	r0, r6, #0x168
	cmp	r0, r5
	beq.n	.L0801f4f4
	add.w	r1, r5, #0x168
	mov.w	r0, #0x168
	cmp	r6, r1
	bne.n	.L0801f536
.L0801f4f4:
	movw	r0, #0x7fff		@ full circle
	strh.w	r0, [sp, #4]
	add	r2, sp, #0x40
	add	r1, sp, #4
	mov	r0, r11
	bl	fn_0801f31c
	ldr	r0, [sp, #0x114]
	bl	table_slot_clear
	ldr	r0, [sp, #0x10c]
	.inst.n	0x1c40		@ adds r0, r0, #1
	beq.n	.L0801f518
	ldr	r0, [sp, #0x10c]
	bl	table_slot_clear
.L0801f518:
	add	r0, sp, #0xf4
	bl	fn_0801ec98
	ldr	r0, [sp, #0x110]
	cmp	r0, #0
	beq.n	.L0801f52a
	add	r0, sp, #0xdc
	bl	fn_0801ec98
.L0801f52a:
	add	sp, #0x12c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801f530:
	sub.w	r6, r6, #0x168		@ reduce the start angle
	uxth	r6, r6
.L0801f536:
	cmp	r6, r0
	bcs.n	.L0801f530
	b.n	.L0801f542
.L0801f53c:
	sub.w	r5, r5, #0x168		@ reduce the end angle
	uxth	r5, r5
.L0801f542:
	cmp	r5, r0
	bcs.n	.L0801f53c
	sxth	r0, r5
	str	r0, [sp, #0x124]	@ saved end angle
	str	r0, [sp, #0]		@ stack argument = end angle
	ldrsh.w	r2, [r4, #2]
	ldrsh.w	r1, [r4, #0]
	sxth	r3, r6
	add	r0, sp, #0x64
	str	r3, [sp, #0x128]	@ saved start angle
	bl	fn_0801eba8		@ arc structure at sp+0x64
	movs	r1, #0
	add	r0, sp, #0x64
	bl	table_slot_insert
	str	r0, [sp, #0x118]
	cmp	r5, r6
	bls.n	.L0801f574
	subs	r0, r5, r6
	rsb.w	r0, r0, #0x168
	b.n	.L0801f576
.L0801f574:
	subs	r0, r6, r5		@ r0 = span
.L0801f576:
	ldr.w	r1, [r11, #0x8]
	str	r1, [sp, #0]		@ saved word [r11+8]
	cmp	r0, #0x3c
	ble.n	.L0801f5d6
	cmp.w	r8, #0xa
	bls.n	.L0801f5d6
	movs	r0, #0x5a
	udiv	r1, r6, r0
	udiv	r0, r5, r0
	and.w	r0, r0, #3
	strh.w	r0, [sp, #0x54]		@ work structure +0x0c = (end/0x5a)&3
	add	r0, sp, #4
	strh.w	r10, [sp, #0x4c]	@ work structure +4 = sl
	strh.w	r5, [sp, #0x50]		@ work structure +8 = end
	and.w	r1, r1, #3
	str	r0, [sp, #0x58]		@ work structure +0x10 = sp+4
	str	r4, [sp, #0x48]		@ work structure +0 = centre pointer
	strh.w	r6, [sp, #0x4e]		@ work structure +6 = start
	strh.w	r1, [sp, #0x52]		@ work structure +0x0a = (start/0x5a)&3
	strh.w	r9, [sp, #0x56]		@ work structure +0x0e = r9
	add	r0, sp, #0x40
	strd	r0, r11, [sp, #0x5c]	@ work structure +0x14, +0x18
	add	r0, sp, #0x48
	bl	fn_08017c64
	add	r0, sp, #0x48
	bl	fn_08017df4
	add	r0, sp, #0x48
	bl	fn_08017f92
	add	r0, sp, #0x48
	bl	fn_0801816e
	b.n	.L0801f5e0
.L0801f5d6:
	add	r2, sp, #0x40
	add	r1, sp, #4
	mov	r0, r11
	bl	fn_0801f31c
.L0801f5e0:
	add	r0, sp, #0x64
	bl	fn_0801ec98
	add	r0, sp, #0xf4
	bl	fn_0801ec98
	ldr	r0, [sp, #0x110]
	cbz	r0, .L0801f5f6
	add	r0, sp, #0xdc
	bl	fn_0801ec98
.L0801f5f6:
	ldr	r0, [sp, #0x118]
	bl	table_slot_clear
	ldr	r0, [sp, #0x114]
	bl	table_slot_clear
	ldr	r0, [sp, #0x10c]
	.inst.n	0x1c40		@ adds r0, r0, #1
	beq.n	.L0801f60e
	ldr	r0, [sp, #0x10c]
	bl	table_slot_clear
.L0801f60e:
	ldrb	r0, [r7, #0xd]
	lsls	r0, r0, #0x1d		@ bit 2 of byte +0x0d to the sign
	bpl.n	.L0801f52a
	and.w	r2, r9, #0xff
	add	r3, sp, #0x48
	mov	r1, r10
	ldr	r0, [sp, #0x128]	@ saved start angle
	bl	fn_0801b752		@ end cap rectangle at sp+0x48
	ldrh.w	r0, [sp, #0x48]
	ldrh	r1, [r4, #0]
	add	r2, sp, #0x48
	add	r0, r1
	strh.w	r0, [sp, #0x48]
	ldrh.w	r0, [sp, #0x4c]
	ldrh	r1, [r4, #0]
	add	r0, r1
	strh.w	r0, [sp, #0x4c]
	ldrh.w	r0, [sp, #0x4a]
	ldrh	r1, [r4, #2]
	add	r0, r1
	strh.w	r0, [sp, #0x4a]
	ldrh.w	r0, [sp, #0x4e]
	ldrh	r1, [r4, #2]
	add	r0, r1
	strh.w	r0, [sp, #0x4e]
	add	r0, sp, #0x54
	ldr	r1, [sp, #0]
	bl	rect_intersect
	add	r6, sp, #0x54
	cbz	r0, .L0801f692
	movs	r3, #0
	movw	r2, #0x7fff
	add	r1, sp, #0x48
	add	r0, sp, #0x10c
	bl	fn_0801f1a8
	movs	r1, #0
	add	r0, sp, #0x10c
	bl	table_slot_insert
	mov	r5, r0
	mov	r0, r11
	add	r2, sp, #0x40
	add	r1, sp, #4
	str.w	r6, [r11, #0x8]
	bl	fn_0801f31c
	mov	r0, r5
	bl	table_slot_clear
	add	r0, sp, #0x10c
	bl	fn_0801ec98
.L0801f692:
	and.w	r2, r9, #0xff
	add	r3, sp, #0x48
	mov	r1, r10
	ldr	r0, [sp, #0x124]	@ saved end angle
	bl	fn_0801b752
	ldrh.w	r0, [sp, #0x48]
	ldrh	r1, [r4, #0]
	add	r2, sp, #0x48
	add	r0, r1
	strh.w	r0, [sp, #0x48]
	ldrh.w	r0, [sp, #0x4c]
	ldrh	r1, [r4, #0]
	add	r0, r1
	strh.w	r0, [sp, #0x4c]
	ldrh.w	r0, [sp, #0x4a]
	ldrh	r1, [r4, #2]
	add	r0, r1
	strh.w	r0, [sp, #0x4a]
	ldrh.w	r0, [sp, #0x4e]
	ldrh	r1, [r4, #2]
	add	r0, r1
	strh.w	r0, [sp, #0x4e]
	add	r0, sp, #0x54
	ldr	r1, [sp, #0]
	bl	rect_intersect
	cbz	r0, .L0801f70e
	movs	r3, #0
	movw	r2, #0x7fff
	add	r1, sp, #0x48
	add	r0, sp, #0x10c
	bl	fn_0801f1a8
	movs	r1, #0
	add	r0, sp, #0x10c
	bl	table_slot_insert
	mov	r4, r0
	mov	r0, r11
	add	r2, sp, #0x40
	add	r1, sp, #4
	str.w	r6, [r11, #0x8]
	bl	fn_0801f31c
	mov	r0, r4
	bl	table_slot_clear
	add	r0, sp, #0x10c
	bl	fn_0801ec98
.L0801f70e:
	ldr	r0, [sp, #0]
	str.w	r0, [r11, #0x8]		@ restore word [r11+8]
	b.n	.L0801f52a

@ ----------------------------------------------------------------------------
@ fn_0801f716 - calls fn_08015110, then tail-branches to fn_080154ba.
@ Parameters: r0, r1, r2 = values passed on to fn_080154ba (kept in r6, r5, r4
@ across the first call). No return value of its own.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801f716,"ax",%progbits
	.global fn_0801f716
	.thumb_func
	.type fn_0801f716, %function
fn_0801f716:
	push	{r4, r5, r6, lr}
	mov	r4, r2
	mov	r5, r1
	mov	r6, r0
	bl	fn_08015110
	mov	r2, r4
	mov	r1, r5
	mov	r0, r6
	pop.w	{r4, r5, r6, lr}
	b.w	fn_080154ba		@ tail call with the original r0, r1, r2

@ ----------------------------------------------------------------------------
@ fn_0801f730 - runs the callbacks of an object for a command whose rectangle
@ intersects the object's clip.
@ Parameters: r0 = object pointer, r1 = pointer to a structure (word +0, byte
@ +0x18). No return value (r2 and r3 are not read: sp+0..7 is a local rectangle
@ written by rect_intersect).
@ When byte r1+0x18 is above 2 and rect_intersect(sp, word [r1+0], word [r0+8])
@ is nonzero: calls the function pointer at word r0+0x30 with r0 when it is
@ nonzero, then the function pointer at word r0+0x50 with (r0, r1).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801f730,"ax",%progbits
	.p2align 2
	.global fn_0801f730
	.thumb_func
	.type fn_0801f730, %function
fn_0801f730:
	push	{r2, r3, r4, r5, r6, lr}
	mov	r4, r0			@ r4 = object pointer
	ldrb	r0, [r1, #0x18]
	mov	r5, r1			@ r5 = structure pointer
	cmp	r0, #2
	bls.n	.L0801f75a
	ldr	r2, [r4, #0x8]
	mov	r0, sp			@ local rectangle at sp
	ldr	r1, [r5, #0]
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L0801f75a
	ldr	r1, [r4, #0x30]
	cbz	r1, .L0801f752
	mov	r0, r4
	blx	r1			@ function pointer at word +0x30
.L0801f752:
	ldr	r2, [r4, #0x50]
	mov	r1, r5
	mov	r0, r4
	blx	r2			@ function pointer at word +0x50
.L0801f75a:
	pop	{r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_0801f75c - draws one rectangle command into a frame buffer.
@ Parameters: r0 = pointer to a draw context (word +0 = frame buffer, word +4 =
@ rectangle pointer, word +8 = clip), r1 = pointer to a draw command (r4:
@ rectangle at word +0, source pixels word +4, colour word +8, mask word +0xc,
@ byte +0x10 mode, byte +0x18 and byte +0x19, word +0x14 = mask rectangle).
@ No return value.
@ Returns when the mask word +0xc is 0 and byte +0x10 is 0; byte +0x10 = 1 sets
@ the mask value to 0.
@ Frame width = sxth(h[ctx rectangle +4] - h[ctx rectangle +0] + 1) (stored at
@ sp+0x1c). Clips with rect_intersect(sp+0x14, command rectangle, clip); returns
@ when that is 0.
@ p = return_word_200004b8(). Destination address in the frame buffer: when
@ word [*p+0x1c] is 0, 3 bytes per pixel when bit 6 of byte [*p+0x10] is set,
@ else 2 bytes per pixel (offsets taken from the clipped rectangle relative to
@ the context rectangle); when word [*p+0x1c] is nonzero the frame buffer
@ address is used as it is.
@ Source and mask addresses come from the pixel offsets of the clipped
@ rectangle inside the command rectangle (2 bytes per pixel for the source
@ pixels) and inside the mask rectangle (1 byte per pixel).
@ Moves the clipped rectangle by minus the context rectangle origin with
@ rect_move.
@ When word [*p+0x1c] is 0: byte +0x19 = 0 calls fn_0801a5e4 (source word +4 is
@ 0) or blit_565_alpha_mask (otherwise); byte +0x19 nonzero calls fn_0801a498
@ (source word +4 is 0) or fn_080283c8 (otherwise).
@ When word [*p+0x1c] is nonzero: fn_0801a92c (source word +4 is 0) or
@ fn_08028848 (otherwise).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801f75c,"ax",%progbits
	.global fn_0801f75c
	.thumb_func
	.type fn_0801f75c, %function
fn_0801f75c:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	ldr	r5, [r1, #0xc]		@ r5 = mask word
	sub	sp, #0x24
	mov	r4, r1			@ r4 = draw command
	mov	r7, r0			@ r7 = draw context
	cbz	r5, .L0801f770
	ldrb	r0, [r4, #0x10]
	cmp	r0, #0
	beq.n	.L0801f856		@ mask set and mode 0: return
.L0801f770:
	ldrb	r0, [r4, #0x10]
	cmp	r0, #1
	bne.n	.L0801f778
	movs	r5, #0			@ mode 1: no mask
.L0801f778:
	ldr	r0, [r7, #4]
	ldrh	r1, [r0, #4]
	ldrh	r0, [r0, #0]
	subs	r0, r1, r0
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r0, r0
	str	r0, [sp, #0x1c]		@ frame width
	ldr	r2, [r7, #8]
	add	r0, sp, #0x14
	ldr	r1, [r4, #0]
	bl	rect_intersect		@ clipped rectangle at sp+0x14
	cmp	r0, #0
	beq.n	.L0801f894
	bl	return_word_200004b8
	mov	r11, r0			@ r11 = p
	ldr	r0, [r0, #0]
	ldr.w	r9, [r7, #0]		@ r9 = frame buffer
	ldr	r1, [r0, #0x1c]
	cbnz	r1, .L0801f7f6
	ldrb	r0, [r0, #0x10]
	lsls	r0, r0, #0x19		@ bit 6 of byte +0x10 to the sign
	bmi.n	.L0801f7cc
	ldr	r0, [r7, #4]		@ 2 bytes per pixel
	ldrsh.w	r1, [sp, #0x14]
	ldrsh.w	r2, [r0, #0]
	ldrsh.w	r0, [r0, #2]
	subs	r1, r1, r2
	ldrsh.w	r2, [sp, #0x16]
	subs	r2, r2, r0
	ldr	r0, [sp, #0x1c]
	mla	r1, r0, r2, r1
	add.w	r0, r9, r1, lsl #1
	b.n	.L0801f7f4
.L0801f7cc:
	ldr	r1, [r7, #4]		@ 3 bytes per pixel
	ldrsh.w	r2, [sp, #0x16]
	ldrsh.w	r3, [r1, #2]
	ldrsh.w	r1, [r1, #0]
	subs	r2, r2, r3
	ldr	r3, [sp, #0x1c]
	muls	r2, r3, r2
	add.w	r2, r2, r2, lsl #1
	add.w	r0, r2, r9
	ldrsh.w	r2, [sp, #0x14]
	subs	r1, r2, r1
	add.w	r1, r1, r1, lsl #1
	add	r0, r1
.L0801f7f4:
	mov	r9, r0			@ r9 = destination address
.L0801f7f6:
	ldr.w	r10, [r4, #4]		@ r10 = source pixels
	movs.w	r0, r10
	beq.n	.L0801f82a
	ldr	r0, [r4, #0]
	ldrh	r2, [r0, #4]
	ldrsh.w	r1, [r0, #0]
	ldrsh.w	r0, [r0, #2]
	subs	r2, r2, r1
	.inst.n	0x1c52		@ adds r2, r2, #1
	sxth.w	r8, r2			@ r8 = source row width
	ldrsh.w	r2, [sp, #0x14]
	subs	r1, r2, r1
	ldrsh.w	r2, [sp, #0x16]
	subs	r0, r2, r0
	mla	r1, r8, r0, r1
	add.w	r10, r10, r1, lsl #1	@ r10 = source address
	b.n	.L0801f82e
.L0801f82a:
	mov.w	r8, #0
.L0801f82e:
	cbz	r5, .L0801f858
	ldr	r0, [r4, #0x14]		@ mask rectangle
	ldrh	r2, [r0, #4]
	ldrsh.w	r1, [r0, #0]
	ldrsh.w	r0, [r0, #2]
	subs	r2, r2, r1
	.inst.n	0x1c52		@ adds r2, r2, #1
	sxth	r6, r2			@ r6 = mask row width
	ldrsh.w	r2, [sp, #0x14]
	subs	r1, r2, r1
	ldrsh.w	r2, [sp, #0x16]
	add	r1, r5
	subs	r0, r2, r0
	mla	r5, r6, r0, r1		@ r5 = mask address
	b.n	.L0801f85a
.L0801f856:
	b.n	.L0801f894
.L0801f858:
	movs	r6, #0
.L0801f85a:
	ldr	r0, [r7, #4]
	ldrh	r1, [r0, #2]
	ldrh	r0, [r0, #0]
	rsbs	r1, r1, #0
	sxth	r2, r1
	rsbs	r0, r0, #0
	sxth	r1, r0
	add	r0, sp, #0x14
	bl	rect_move		@ move the clipped rectangle by minus the origin
	ldr.w	r0, [r11, #0]
	ldr	r0, [r0, #0x1c]
	cbz	r0, .L0801f8ac
	ldr	r0, [r4, #4]
	cmp	r0, #0
	ldrb	r0, [r4, #0x18]
	beq.n	.L0801f89a
	add	r1, sp, #4
	str.w	r8, [sp, #0]
	stm.w	r1, {r0, r5, r6}
	mov	r3, r10
	add	r1, sp, #0x14
	mov	r0, r9
	ldr	r2, [sp, #0x1c]
	bl	fn_08028848
.L0801f894:
	add	sp, #0x24
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801f89a:
	stm.w	sp, {r0, r5, r6}
	ldr	r3, [r4, #0x8]
	add	r1, sp, #0x14
	mov	r0, r9
	ldr	r2, [sp, #0x1c]
	bl	fn_0801a92c
	b.n	.L0801f894
.L0801f8ac:
	ldrb	r0, [r4, #0x19]
	cbz	r0, .L0801f8d2
	ldr	r1, [r4, #4]
	cmp	r1, #0
	ldrb	r1, [r4, #0x18]
	beq.n	.L0801f904
	str.w	r8, [sp, #0]
	strd	r6, r0, [sp, #0xc]
	strd	r1, r5, [sp, #4]
	mov	r3, r10
	add	r1, sp, #0x14
	mov	r0, r9
	ldr	r2, [sp, #0x1c]
	bl	fn_080283c8
	b.n	.L0801f894
.L0801f8d2:
	ldr	r0, [r4, #4]
	cmp	r0, #0
	ldrb	r0, [r4, #0x18]
	beq.n	.L0801f8f2
	add	r1, sp, #4
	str.w	r8, [sp, #0]
	stm.w	r1, {r0, r5, r6}
	mov	r3, r10
	add	r1, sp, #0x14
	mov	r0, r9
	ldr	r2, [sp, #0x1c]
	bl	blit_565_alpha_mask
	b.n	.L0801f894
.L0801f8f2:
	stm.w	sp, {r0, r5, r6}
	ldr	r3, [r4, #0x8]
	add	r1, sp, #0x14
	mov	r0, r9
	ldr	r2, [sp, #0x1c]
	bl	fn_0801a5e4
	b.n	.L0801f894
.L0801f904:
	strd	r6, r0, [sp, #8]
	strd	r1, r5, [sp, #0]
	ldr	r3, [r4, #0x8]
	add	r1, sp, #0x14
	mov	r0, r9
	ldr	r2, [sp, #0x1c]
	bl	fn_0801a498
	b.n	.L0801f894

@ ----------------------------------------------------------------------------
@ fn_0801f91a - copies a rectangle of 16-bit pixels from one buffer to another,
@ row by row.
@ Parameters: r1 = base A, r2 = row stride A in halfwords, r3 = rectangle of 4
@ halfwords {x0, y0, x1, y1}, stack argument 0 = base B (r0), stack argument 1 =
@ row stride B in halfwords (r9), stack argument 2 = point of 2 halfwords {x, y}
@ in B; r0 is not read on entry. No return value.
@ Address A = base A + (y0 * stride A + x0) * 2 (smulbb of y0 and the low
@ halfword of the stride), address B = base B + (py * stride B + px) * 2.
@ For each row from y0 while y <= y1 (halfword rectangle +6) calls
@ copy_bytes_08022ce0(address A, address B, (x1 - x0 + 1) * 2) and then
@ advances A by stride A * 2 and B by stride B * 2 bytes.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801f91a,"ax",%progbits
	.global fn_0801f91a
	.thumb_func
	.type fn_0801f91a, %function
fn_0801f91a:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldrsh.w	r4, [r3, #2]		@ r4 = y0
	ldrd	r0, r9, [sp, #0x20]	@ r0 = base B, r9 = stride B
	mov	r5, r3			@ r5 = rectangle pointer
	mov	r8, r2			@ r8 = stride A
	smulbb	r3, r4, r8
	add.w	r3, r1, r3, lsl #1
	ldrsh.w	r1, [r5, #0]		@ r1 = x0
	ldr	r2, [sp, #0x28]		@ r2 = point pointer
	add.w	r6, r3, r1, lsl #1	@ r6 = address A
	ldrsh.w	r3, [r2, #2]
	ldrsh.w	r2, [r2, #0]
	mul	r3, r3, r9
	add.w	r0, r0, r3, lsl #1
	add.w	r7, r0, r2, lsl #1	@ r7 = address B
	ldrh	r0, [r5, #4]
	subs	r0, r0, r1
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r0, r0
	lsl.w	r10, r0, #1		@ r10 = row length in bytes
	b.n	.L0801f974
.L0801f95e:
	mov	r2, r10
	mov	r1, r7
	mov	r0, r6
	bl	copy_bytes_08022ce0
	.inst.n	0x1c64		@ adds r4, r4, #1
	add.w	r6, r6, r8, lsl #1
	add.w	r7, r7, r9, lsl #1
	sxth	r4, r4
.L0801f974:
	ldrsh.w	r0, [r5, #6]
	cmp	r0, r4
	bge.n	.L0801f95e
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
