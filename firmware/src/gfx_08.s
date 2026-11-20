@ gfx_08.s - graphics code: quarter-circle ring segment drawing, two-rectangle redraw helper, chart sample drawing and two further graphics units (batch 08)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0801816e - draws up to two clipped rectangles for a ring segment record.
@ param r0 = pointer to a record: word 0 = pointer to two halfwords (centre x,
@ centre y), halfword +4 = R, halfword +6 = angle A0, halfword +8 = angle A1,
@ halfword +0xa = q, halfword +0xc = qp, halfword +0xe = inner radius ri,
@ words +0x10 and +0x14 = arguments 2 and 3 of fn_0801f31c, word +0x18 = context.
@ r1 is unused; r2 and r3 are saved on the stack and the 8 bytes at sp are used
@ as the scratch rectangle (x0, y0, x1, y1 halfwords). No return value.
@ S(a) = sine_q15_degrees(a); products are S() * value >> 15; cx, cy = centre.
@ Case q = 3 and qp = 3 and A0 < A1: one rectangle
@   x0 = cx + S(A0+90)*(R-ri), y0 = cy + S(A0)*R,
@   x1 = cx + S(A1+90)*R,      y1 = cy + S(A1)*(R-ri).
@ Case q = 3 otherwise: rectangle x0 = cx + S(A0+90)*(R-ri), y0 = cy + S(A0)*R,
@   x1 = cx + R, y1 = cy - 1; then, only when qp = 3, the rectangle
@   x0 = cx, y0 = cy - R, x1 = cx + S(A1+90)*R, y1 = cy + S(A1)*(R-ri).
@ Case q != 3 and qp = 3: only the second rectangle.
@ Case q != 3 and qp != 3: the full rectangle cx..cx+R, cy-R..cy-1 when
@   (q = qp and A1 < A0) or (q = 2 and qp = 0 or 1) or (q = 1 and qp = 0);
@   otherwise nothing (q = 0 draws nothing).
@ Each rectangle is intersected (rect_intersect) with the clip saved from
@ *(context+8); when the result is not empty, *(context+8) is set to it and
@ fn_0801f31c(context, word +0x10, word +0x14) is called. *(context+8) is
@ restored at the end.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801816e,"ax",%progbits
	.global fn_0801816e
	.thumb_func
	.type fn_0801816e, %function
fn_0801816e:
	push	{r2, r3, r4, r5, r6, lr}
	mov	r4, r0			@ r4 = record
	ldr	r0, [r0, #0x18]		@ context
	ldrh	r1, [r4, #0xa]		@ q
	mov	r5, sp			@ r5 = scratch rectangle
	ldr	r6, [r0, #0x8]		@ r6 = saved clip *(context+8)
	ldrh	r0, [r4, #0xc]		@ qp
	cmp	r1, #3
	beq.n	.L0801819e
	cmp	r0, #3
	beq.n	.L08018254
	cmp	r1, r0
	bne.n	.L08018190
	ldrh	r2, [r4, #0x8]		@ A1
	ldrh	r3, [r4, #0x6]		@ A0
	cmp	r2, r3
	bcc.n	.L0801828e
.L08018190:
	cmp	r1, #2
	beq.n	.L08018290
	cmp	r1, #1
	beq.n	.L08018292
	cmp	r1, #2
	beq.n	.L08018294
	b.n	.L08018302
.L0801819e:
	cmp	r0, #3
	bne.n	.L080181e2
	ldrh	r0, [r4, #0x6]		@ A0
	ldrh	r1, [r4, #0x8]		@ A1
	cmp	r0, r1
	bcs.n	.L080181e2
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees	@ S(A0+90)
	ldrsh.w	r1, [r4, #0x4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2		@ R - ri
	muls	r0, r1, r0
	ldr	r1, [r4, #0x0]
	ldrh	r1, [r1, #0x0]		@ cx
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #0x0]		@ x0
	ldrsh.w	r0, [r4, #0x6]
	bl	sine_q15_degrees	@ S(A0)
	ldrh	r1, [r4, #0x4]
	smulbb	r0, r0, r1
	ldr	r1, [r4, #0x0]
	ldrh	r1, [r1, #0x2]		@ cy
	add.w	r0, r1, r0, asr #15	@ y0
	b.n	.L08018264
.L080181e2:
	ldr	r0, [r4, #0x0]
	ldrh	r1, [r4, #0x4]
	ldrh	r0, [r0, #0x0]		@ cx
	add	r0, r1
	strh.w	r0, [sp, #0x4]		@ x1 = cx + R
	ldr	r0, [r4, #0x0]
	ldrh	r0, [r0, #0x2]		@ cy
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh.w	r0, [sp, #0x6]		@ y1 = cy - 1
	ldrh	r0, [r4, #0x6]
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees	@ S(A0+90)
	ldrsh.w	r1, [r4, #0x4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2		@ R - ri
	muls	r0, r1, r0
	ldr	r1, [r4, #0x0]
	ldrh	r1, [r1, #0x0]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #0x0]		@ x0
	ldrsh.w	r0, [r4, #0x6]
	bl	sine_q15_degrees	@ S(A0)
	ldrh	r1, [r4, #0x4]
	smulbb	r0, r0, r1
	ldr	r1, [r4, #0x0]
	mov	r2, r6			@ r2 = saved clip
	ldrh	r1, [r1, #0x2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #0x2]		@ y0
	mov	r1, sp
	mov	r0, r1
	bl	rect_intersect		@ rect = rect ^ clip
	cbz	r0, .L0801824e
	ldr	r0, [r4, #0x18]
	str	r5, [r0, #0x8]		@ clip = rect
	ldrd	r2, r0, [r4, #0x14]
	ldr	r1, [r4, #0x10]
	bl	fn_0801f31c
.L0801824e:
	ldrh	r0, [r4, #0xc]
	cmp	r0, #3
	bne.n	.L08018302
.L08018254:
	ldr	r0, [r4, #0x0]
	ldrh	r0, [r0, #0x0]
	strh.w	r0, [sp, #0x0]		@ x0 = cx
	ldr	r0, [r4, #0x0]
	ldrh	r1, [r4, #0x4]
	ldrh	r0, [r0, #0x2]
	subs	r0, r0, r1		@ cy - R
.L08018264:
	strh.w	r0, [sp, #0x2]		@ y0
	ldrh	r0, [r4, #0x8]
	adds	r0, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees	@ S(A1+90)
	ldrh	r1, [r4, #0x4]
	smulbb	r0, r0, r1
	ldr	r1, [r4, #0x0]
	ldrh	r1, [r1, #0x0]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #0x4]		@ x1
	ldrsh.w	r0, [r4, #0x8]
	bl	sine_q15_degrees	@ S(A1)
	b.n	.L08018296
.L0801828e:
	b.n	.L080182be
.L08018290:
	b.n	.L080182b4
.L08018292:
	b.n	.L080182bc
.L08018294:
	b.n	.L080182b6
.L08018296:
	ldrsh.w	r1, [r4, #0x4]
	ldrsh.w	r2, [r4, #0xe]
	subs	r1, r1, r2		@ R - ri
	muls	r0, r1, r0
	ldr	r1, [r4, #0x0]
	mov	r2, r6			@ r2 = saved clip
	ldrh	r1, [r1, #0x2]
	add.w	r0, r1, r0, asr #15
	strh.w	r0, [sp, #0x6]		@ y1
	mov	r1, sp
	b.n	.L080182ec
.L080182b4:
	cbz	r0, .L080182be
.L080182b6:
	cmp	r0, #1
	beq.n	.L080182be
	b.n	.L08018302
.L080182bc:
	cbnz	r0, .L08018302
.L080182be:
	ldr	r0, [r4, #0x0]
	mov	r2, r6			@ r2 = saved clip
	ldrh	r0, [r0, #0x0]
	strh.w	r0, [sp, #0x0]		@ x0 = cx
	ldr	r0, [r4, #0x0]
	ldrh	r1, [r4, #0x4]
	ldrh	r0, [r0, #0x2]
	subs	r0, r0, r1
	strh.w	r0, [sp, #0x2]		@ y0 = cy - R
	ldr	r0, [r4, #0x0]
	ldrh	r1, [r4, #0x4]
	ldrh	r0, [r0, #0x0]
	add	r0, r1
	strh.w	r0, [sp, #0x4]		@ x1 = cx + R
	ldr	r0, [r4, #0x0]
	mov	r1, r5
	ldrh	r0, [r0, #0x2]
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh.w	r0, [sp, #0x6]		@ y1 = cy - 1
.L080182ec:
	mov	r0, r1
	bl	rect_intersect
	cbz	r0, .L08018302
	ldr	r0, [r4, #0x18]
	str	r5, [r0, #0x8]
	ldrd	r2, r0, [r4, #0x14]
	ldr	r1, [r4, #0x10]
	bl	fn_0801f31c
.L08018302:
	ldr	r0, [r4, #0x18]
	str	r6, [r0, #0x8]		@ restore the saved clip
	pop	{r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08018308 - redraws an object through up to two rectangles.
@ param r0 = object, r1 = target context. No return value.
@ Gets two rectangles with fn_08024232(object, &rectA, &rectB) (sp+0x88 and
@ sp+0x80); continues when either has nonzero area (rect_area) and
@ fn_080296ac(object, record) = 1, where the record B is at sp+0x48.
@ Fills record A at sp with fn_08023a0c(A, context), then sets A word +4 = the
@ literal at 0x080183ac (d_0804fcfc), A word +8 = 2, A word +0x10 = address of
@ record B and A word +0x34 = 0x10000.
@ For each rectangle with nonzero area: stores its address in A word +0xc, calls
@ fn_080207f4(object, 0x1a, A), fn_0801f31c(context, record B, rectangle) and
@ fn_080207f4(object, 0x1b, A).
@ ----------------------------------------------------------------------------
	.section .text.fn_08018308,"ax",%progbits
	.p2align 2
	.global fn_08018308
	.thumb_func
	.type fn_08018308, %function
fn_08018308:
	push	{r4, r5, r6, lr}
	sub	sp, #0x90
	mov	r4, r1			@ r4 = context
	mov	r5, r0			@ r5 = object
	add	r2, sp, #0x80
	add	r1, sp, #0x88
	bl	fn_08024232
	add	r0, sp, #0x88
	bl	rect_area
	cbnz	r0, .L0801832a
	add	r0, sp, #0x80
	bl	rect_area
	cmp	r0, #0
	beq.n	.L080183a8
.L0801832a:
	add	r1, sp, #0x48
	mov	r0, r5
	bl	fn_080296ac
	cmp	r0, #1
	bne.n	.L080183a8
	mov	r1, r4
	mov	r0, sp
	bl	fn_08023a0c		@ fill record A
	ldr	r0, .L080183ac
	str	r0, [sp, #0x4]
	movs	r0, #2
	str	r0, [sp, #0x8]
	add	r0, sp, #0x48
	str	r0, [sp, #0x10]		@ A +0x10 = record B
	mov.w	r0, #0x10000
	str	r0, [sp, #0x34]
	add	r0, sp, #0x88
	bl	rect_area
	cbz	r0, .L0801837a
	add	r0, sp, #0x88
	str	r0, [sp, #0xc]
	mov	r2, sp
	movs	r1, #0x1a
	mov	r0, r5
	bl	fn_080207f4
	add	r2, sp, #0x88
	add	r1, sp, #0x48
	mov	r0, r4
	bl	fn_0801f31c
	mov	r2, sp
	movs	r1, #0x1b
	mov	r0, r5
	bl	fn_080207f4
.L0801837a:
	add	r0, sp, #0x80
	bl	rect_area
	cmp	r0, #0
	beq.n	.L080183a8
	add	r6, sp, #0x80
	mov	r2, sp
	movs	r1, #0x1a
	mov	r0, r5
	str	r6, [sp, #0xc]
	bl	fn_080207f4
	add	r2, sp, #0x80
	add	r1, sp, #0x48
	mov	r0, r4
	str	r6, [sp, #0xc]
	bl	fn_0801f31c
	mov	r2, sp
	movs	r1, #0x1b
	mov	r0, r5
	bl	fn_080207f4
.L080183a8:
	add	sp, #0x90
	pop	{r4, r5, r6, pc}
.L080183ac:
	.word d_0804fcfc

@ ----------------------------------------------------------------------------
@ fn_080183b0 - draws the sample boxes of a chart object, column by column.
@ param r0 = chart object (rectangle at +0x14, count halfword +0x82, scale
@ halfwords +0x84 and +0x86, node list at +0x24), r1 = target context. No
@ return value.
@ Intersects the object rectangle with the clip at *(context+8) via
@ rect_intersect (result at sp+0x94) and returns when empty; otherwise saves the
@ old clip (sp+0xc0) and stores the result as the new clip.
@ Origin terms come from fn_08024af8, fn_08024b88, fn_0802499c, fn_08024070 and
@ fn_08024208; scale terms from fn_08023e7c and fn_08023e48 (times halfwords
@ +0x84 / +0x86, >> 8, sign-extended 16 bits from bit 8) and from
@ fn_08024ad4(object, 0) and fn_08024ad4(object, 0x50000) (times halfword
@ +0x84, >> 8). The box width is derived from these terms divided by the node
@ count n returned by fn_080125d6.
@ For each column 0 .. count-1 (halfword +0x82) the column x = object x0 +
@ origin + step*column/(count-1); for each list node (get_word_8_or_zero /
@ read_word_at_base_plus_offset on object+0x24) whose byte +0xc bit 0 is clear:
@ the box x range is [x, x + width - 1] and x advances by width plus a term
@ after every node; a node whose box ends left of the clip is skipped and a box
@ starting right of the clip ends the column.
@ The sample is the halfword node[+4][(column + off) mod count] with off = node
@ halfword +10, or 0 when bit 3 of object byte +0x88 is set; samples equal to
@ 0x7fff are skipped. The sample is mapped between object halfwords +0x6c and
@ +0x70 (+0x6e and +0x72 when bit 4 of node byte +0xc is set) to a y position
@ y = origin_y + (scale - (v - lo)*scale/(hi - lo)) + object y0 at +0x16; the
@ box bottom is object y1 at +0x1a plus the first halfword of the style.
@ The box is drawn with fn_0801f31c(context, style at sp+0x48, box at sp+0xa4)
@ between fn_080207f4(object, 0x1a, ...) and fn_080207f4(object, 0x1b, ...).
@ The clip is restored at the end.
@ ----------------------------------------------------------------------------
	.section .text.fn_080183b0,"ax",%progbits
	.p2align 2
	.global fn_080183b0
	.thumb_func
	.type fn_080183b0, %function
fn_080183b0:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r7, r1			@ r7 = context
	ldr	r2, [r1, #0x8]		@ old clip
	sub	sp, #0xd4
	mov	r4, r0			@ r4 = object
	add.w	r1, r0, #0x14		@ object rectangle
	add	r0, sp, #0x94		@ result rectangle
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L080184c8
	ldr	r0, [r7, #0x8]
	str	r0, [sp, #0xc0]		@ saved clip
	add	r0, sp, #0x94
	str	r0, [r7, #0x8]		@ clip = intersection
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024af8
	mov	r8, r0
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024b88
	str	r0, [sp, #0xac]
	mov	r0, r4
	bl	fn_08023e7c
	ldrh.w	r1, [r4, #0x84]
	muls	r0, r1, r0
	sbfx	r10, r0, #0x8, #0x10	@ r10 = x scale term
	mov	r0, r4
	bl	fn_08023e48
	ldrh.w	r1, [r4, #0x86]
	muls	r0, r1, r0
	sbfx	r0, r0, #0x8, #0x10
	str	r0, [sp, #0xa0]		@ y scale term
	add.w	r0, r4, #0x24
	str	r0, [sp, #0x9c]		@ node list base
	bl	fn_080125d6
	mov	r5, r0			@ r5 = node count n
	movs	r1, #0
	mov	r0, r4
	bl	fn_08024ad4
	ldrh.w	r1, [r4, #0x84]
	mov.w	r6, #0x50000
	muls	r0, r1, r0
	asrs	r1, r0, #8
	ldrh.w	r0, [r4, #0x82]		@ count
	rsb.w	r3, r0, #1		@ 1 - count
	mla	r1, r3, r1, r10
	sdiv	r0, r1, r0
	sxth.w	r9, r0
	mov	r1, r6
	mov	r0, r4
	bl	fn_08024ad4
	ldrh.w	r1, [r4, #0x84]
	rsb.w	r2, r5, #1		@ 1 - n
	muls	r0, r1, r0
	asr.w	r11, r0, #8		@ r11 = term of fn_08024ad4(object, 0x50000)
	mla	r0, r2, r11, r9
	udiv	r0, r0, r5
	sxth	r0, r0
	str	r0, [sp, #0x80]		@ box width
	movs	r1, #0
	mov	r0, r4
	bl	fn_0802499c
	mov	r5, r0
	mov	r0, r4
	bl	fn_08024070
	sub.w	r0, r8, r0
	add	r0, r5
	sxth	r0, r0
	str	r0, [sp, #0xc4]		@ x origin
	mov	r0, r4
	bl	fn_08024208
	mov	r1, r0
	ldr	r0, [sp, #0xac]
	subs	r0, r0, r1
	add	r0, r5
	sxth	r0, r0
	str	r0, [sp, #0xc8]		@ y origin
	add	r0, sp, #0x48
	bl	fn_0801f344		@ initialise the style record at sp+0x48
	add	r2, sp, #0x48
	mov	r1, r6
	mov	r0, r4
	bl	fn_0802516e
	ldrb.w	r0, [sp, #0x57]
	bic	r0, r0, #0x7		@ clear bits 0..2 of style byte +0xf
	strb.w	r0, [sp, #0x57]
	movs	r0, #0xff
	strb.w	r0, [sp, #0x4b]
	ldrh	r0, [r4, #0x1a]		@ object y1
	ldrh.w	r1, [sp, #0x48]		@ first halfword of the style
	add	r0, r1
	strh.w	r0, [sp, #0xaa]		@ box bottom
	mov	r1, r7
	mov	r0, sp
	bl	fn_08023a0c		@ fill record at sp
	ldr	r0, .L080185e8
	str	r6, [sp, #0x34]
	str	r0, [sp, #0x4]
	b.n	.L080184ca
.L080184c8:
	b.n	.L080185e2
.L080184ca:
	movs	r0, #0x4
	movs	r6, #0			@ r6 = column index
	str	r0, [sp, #0x8]
	b.n	.L080185d4
	nop				@ padding
.L080184d4:
	sub.w	r1, r10, r9
	muls	r1, r6, r1		@ column * step
	.inst.n	0x1e40			@ subs r0, r0, #1
	sdiv	r1, r1, r0		@ / (count - 1)
	ldr	r0, [sp, #0xc4]
	add	r1, r0
	ldrh	r0, [r4, #0x14]		@ object x0
	str	r6, [sp, #0x38]
	add	r0, r1
	sxth.w	r8, r0			@ r8 = column x
	ldr	r0, [sp, #0x9c]
	bl	get_word_8_or_zero	@ first node
	b.n	.L080185cc
.L080184f6:
	ldrb	r0, [r5, #0xc]
	lsls	r0, r0, #0x1f
	bne.n	.L080185c4		@ node byte +0xc bit 0 set: skip
	ldrb.w	r0, [r4, #0x88]
	lsls	r0, r0, #0x1c
	bmi.n	.L08018508		@ object byte +0x88 bit 3 set: offset 0
	ldrh	r0, [r5, #0xa]
	b.n	.L0801850a
.L08018508:
	movs	r0, #0
.L0801850a:
	ldr	r2, [sp, #0x80]
	sxth	r1, r0			@ r1 = offset
	.inst.n	0x1e52			@ subs r2, r2, #1
	add	r2, r8
	sxth	r2, r2
	strh.w	r2, [sp, #0xa8]		@ box x1 = x + width - 1
	ldr	r3, [sp, #0x80]
	mov	r0, r8
	add	r3, r11
	strh.w	r8, [sp, #0xa4]		@ box x0 = x
	add	r3, r0
	sxth.w	r8, r3			@ next x
	ldrsh.w	r3, [sp, #0x94]		@ clip x0
	cmp	r2, r3
	blt.n	.L080185c4		@ box ends left of the clip: skip
	ldrsh.w	r2, [sp, #0x98]		@ clip x1
	cmp	r0, r2
	bgt.n	.L080185d0		@ box starts right of the clip: end column
	ldrh	r0, [r5, #0x8]
	strh.w	r0, [sp, #0x4c]
	adds	r0, r1, r6		@ offset + column
	ldrh.w	r1, [r4, #0x82]
	ldr.w	r12, [sp, #0xa0]
	sdiv	r2, r0, r1
	mls	r0, r1, r2, r0		@ (offset + column) mod count
	ldr	r1, [r5, #0x4]		@ sample array
	sxth	r0, r0
	ldrsh.w	r2, [r1, r0, lsl #1]	@ sample v
	ldrb	r1, [r5, #0xc]
	ubfx	r1, r1, #0x4, #0x1	@ node byte +0xc bit 4
	add.w	r1, r4, r1, lsl #1
	ldrsh.w	r3, [r1, #0x6c]!	@ lo
	ldrsh.w	r1, [r1, #0x4]		@ hi
	subs	r2, r2, r3
	mul	r2, r2, r12
	subs	r1, r1, r3
	sdiv	r1, r2, r1
	sub.w	r2, r12, r1
	ldr	r1, [sp, #0xc8]
	ldrh	r3, [r4, #0x16]		@ object y0
	add	r1, r2
	add	r1, r3
	strh.w	r1, [sp, #0xa6]		@ box y
	ldr	r1, [r5, #0x4]
	ldrsh.w	r1, [r1, r0, lsl #1]
	sub.w	r2, r1, #0x7f00
	subs	r2, #0xff
	beq.n	.L080185c4		@ sample = 0x7fff: skip
	add	r1, sp, #0xa4
	str	r1, [sp, #0xc]
	add	r1, sp, #0x48
	str	r5, [sp, #0x44]
	str	r1, [sp, #0x10]
	ldr	r1, [r5, #0x4]
	mov	r2, sp
	ldrsh.w	r0, [r1, r0, lsl #1]
	str	r0, [sp, #0x40]
	movs	r1, #0x1a
	mov	r0, r4
	bl	fn_080207f4
	add	r2, sp, #0xa4
	add	r1, sp, #0x48
	mov	r0, r7
	bl	fn_0801f31c
	mov	r2, sp
	movs	r1, #0x1b
	mov	r0, r4
	bl	fn_080207f4
.L080185c4:
	mov	r1, r5
	ldr	r0, [sp, #0x9c]
	bl	read_word_at_base_plus_offset	@ next node
.L080185cc:
	movs	r5, r0
	bne.n	.L080184f6
.L080185d0:
	.inst.n	0x1c76			@ adds r6, r6, #1
	uxth	r6, r6
.L080185d4:
	ldrh.w	r0, [r4, #0x82]
	cmp	r0, r6
	bhi.w	.L080184d4
	ldr	r0, [sp, #0xc0]
	str	r0, [r7, #0x8]		@ restore the clip
.L080185e2:
	add	sp, #0xd4
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L080185e8:
	.word d_08050f14

@ ----------------------------------------------------------------------------
@ fn_080185ec - draws the sample curve of a chart object (marker mode or
@ compact mode).
@ param r0 = chart object (rectangle at +0x14, count halfword +0x82, scale
@ halfwords +0x84 and +0x86, list at +0x24), r1 = target context. No return
@ value.
@ Intersects the object rectangle with the clip at *(context+8) via
@ rect_intersect (result at sp+0xf0; an empty result returns before the clip is
@ changed), saves the old clip in r10, stores the result as the new clip, then
@ returns when count halfword +0x82 is below 2.
@ Computes origin and scale from fn_0802499c, fn_08024af8, fn_08024b88,
@ fn_08024070, fn_08024208, fn_08023e7c * halfword +0x84 >> 8 (x extent, kept at
@ sp+0x3c) and fn_08023e48 * halfword +0x86 >> 8 (y extent, kept at sp+0x24); a
@ second intersection of the object rectangle with the new clip (result at
@ sp+0xf8) that is empty also returns; marker half sizes are fn_08024d2c(object,
@ 0x20000) / 2 (r7) and fn_080249f0(object, 0x20000) / 2 (r11).
@ Compact mode flag (sp+0xec) = count halfword +0x82 >= x extent.
@ For each list node (get_word_8_or_zero / read_word_at_base_plus_offset on the
@ list at +0x24) with byte +0xc bit 0 clear, walks the samples (halfword array
@ at node word +4, index = (start + i) mod count with start = node halfword +10,
@ or 0 when object byte +0x88 bit 3 is set; 0x7fff = missing), maps each into
@ y = origin y + y extent - (v - lo) * y extent / (hi - lo) with lo / hi the
@ halfwords at object +0x6c / +0x70 (or +0x6e / +0x72 when node byte +0xc bit 4
@ is set) and x = origin x + i * x extent / (count - 1).
@ Marker mode (flag 0): for each sample i > 0 with both this and the previous
@ sample not missing draws a segment between them with fn_0801e8b8(context, pen,
@ previous, current), and a marker box around the previous point with
@ fn_0801f31c(context, style, box) when both marker half sizes are nonzero, each
@ bracketed by fn_080207f4(object, 0x1a / 0x1b); after the loop draws a final
@ marker around the last point when the last sample is not missing; stops when
@ the previous x exceeds the right edge of the clip saved at entry (r10 + 4)
@ plus marker half size + 1.
@ Compact mode (flag 1): keeps min and max y of samples with the same x and,
@ when x changes, draws one vertical span (x - 1, max y) to (x - 1, min y) with
@ fn_0801e8b8, with no fn_080207f4 bracket.
@ The clip pointer is restored (0x08018a10) only when the walk finishes; the
@ returns for count < 2 and for the empty second intersection leave the new
@ clip stored.
@ ----------------------------------------------------------------------------
	.section .text.fn_080185ec,"ax",%progbits
	.p2align 2
	.global fn_080185ec
	.thumb_func
	.type fn_080185ec, %function
fn_080185ec:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r9, r1			@ r9 = context
	ldr	r2, [r1, #0x8]		@ old clip
	add.w	r1, r0, #0x14		@ object rectangle
	sub	sp, #0x104
	mov	r5, r0			@ r5 = object
	mov	r7, r1
	add	r0, sp, #0xf0		@ result rectangle
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L08018702
	add	r1, sp, #0xf0
	ldr.w	r10, [r9, #0x8]		@ r10 = saved clip
	str.w	r1, [r9, #0x8]		@ clip = intersection
	ldrh.w	r0, [r5, #0x82]		@ count
	cmp	r0, #2
	bcc.n	.L08018702
	movs	r1, #0
	mov	r0, r5
	bl	fn_0802499c
	mov	r4, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024af8
	adds	r6, r0, r4
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024b88
	add	r4, r0
	mov	r0, r5
	bl	fn_08023e7c
	ldrh.w	r1, [r5, #0x84]
	muls	r0, r1, r0
	sbfx	r0, r0, #0x8, #0x10
	str	r0, [sp, #0x3c]		@ x extent
	mov	r0, r5
	bl	fn_08023e48
	ldrh.w	r1, [r5, #0x86]
	muls	r0, r1, r0
	sbfx	r0, r0, #0x8, #0x10
	str	r0, [sp, #0x24]		@ y extent
	mov	r0, r5
	bl	fn_08024070
	ldrh	r1, [r5, #0x14]
	add	r1, r6
	subs	r0, r1, r0
	sxth	r0, r0
	str	r0, [sp, #0xe4]		@ x origin
	mov	r0, r5
	bl	fn_08024208
	ldrh	r1, [r5, #0x16]
	add	r1, r4
	subs	r0, r1, r0
	sxth	r0, r0
	str	r0, [sp, #0xe8]		@ y origin
	mov	r1, r7
	add	r0, sp, #0xf8
	ldr.w	r2, [r9, #0x8]
	bl	rect_intersect		@ second intersection with the new clip
	cmp	r0, #0
	beq.n	.L08018702
	add	r0, sp, #0x9c
	bl	fn_0801e8d2		@ initialise the pen record at sp+0x9c
	add	r2, sp, #0x9c
	mov.w	r1, #0x50000
	mov	r0, r5
	bl	fn_080250b6
	add	r0, sp, #0xa8
	bl	fn_0801f344		@ initialise the style record at sp+0xa8
	mov.w	r4, #0x20000
	add	r2, sp, #0xa8
	mov	r1, r4
	mov	r0, r5
	bl	fn_0802516e
	mov	r1, r4
	mov	r0, r5
	bl	fn_08024d2c
	add.w	r0, r0, r0, lsr #31
	asrs	r7, r0, #1		@ r7 = half size 1
	mov	r1, r4
	mov	r0, r5
	bl	fn_080249f0
	add.w	r0, r0, r0, lsr #31
	asrs	r1, r0, #1
	mov	r11, r1			@ r11 = half size 2
	ldrsh.w	r0, [sp, #0x9e]
	cmp	r7, r11
	bge.n	.L080186da
	mov	r1, r7			@ r1 = the smaller half size
.L080186da:
	add.w	r2, r0, r0, lsr #31
	cmp.w	r1, r2, asr #1
	ble.n	.L080186f0
	ldrb.w	r1, [sp, #0xa5]
	orr.w	r1, r1, #0x10
	strb.w	r1, [sp, #0xa5]
.L080186f0:
	cmp	r0, #1
	bne.n	.L08018700
	ldrb.w	r0, [sp, #0xa5]
	orr.w	r0, r0, #0x10
	strb.w	r0, [sp, #0xa5]
.L08018700:
	b.n	.L08018704
.L08018702:
	b.n	.L08018a14
.L08018704:
	ldrh.w	r1, [r5, #0x82]
	ldr	r0, [sp, #0x3c]
	cmp	r1, r0
	blt.n	.L08018712
	movs	r0, #1
	b.n	.L08018714
.L08018712:
	movs	r0, #0
.L08018714:
	str	r0, [sp, #0xec]		@ compact mode flag
	add.w	r0, r5, #0x24
	str	r0, [sp, #0xe0]		@ node list base
	bl	get_word_8_or_zero	@ first node
	b.n	.L08018a0a
.L08018722:
	ldrb	r0, [r4, #0xc]
	lsls	r0, r0, #0x1f
	bne.n	.L08018822		@ node byte +0xc bit 0 set: skip
	ldrh	r0, [r4, #0x8]
	strh.w	r0, [sp, #0x9c]
	ldrh	r0, [r4, #0x8]
	strh.w	r0, [sp, #0xac]
	ldrb.w	r0, [r5, #0x88]
	lsls	r0, r0, #0x1c
	bmi.n	.L08018740		@ object byte +0x88 bit 3 set: start 0
	ldrh	r0, [r4, #0xa]
	b.n	.L08018742
.L08018740:
	movs	r0, #0
.L08018742:
	sxth	r0, r0
	str	r0, [sp, #0x30]		@ start index
	ldr	r0, [sp, #0xe4]
	strh.w	r0, [sp, #0x18]
	strh.w	r0, [sp, #0x8]
	ldr	r0, [sp, #0x30]
	str	r0, [sp, #0x14]
	str	r0, [sp, #0x4c]
	ldr	r1, [r4, #0x4]		@ sample array
	ldr	r3, [sp, #0x24]
	ldrsh.w	r0, [r1, r0, lsl #1]	@ first sample
	ldrb	r1, [r4, #0xc]
	ubfx	r2, r1, #0x4, #0x1	@ node byte +0xc bit 4
	add.w	r1, r5, r2, lsl #1
	ldrsh.w	r2, [r1, #0x6c]!	@ lo
	ldrsh.w	r1, [r1, #0x4]		@ hi
	subs	r0, r0, r2
	muls	r0, r3, r0
	subs	r1, r1, r2
	sdiv	r0, r0, r1
	subs	r1, r3, r0
	ldr	r0, [sp, #0xe8]
	add	r0, r1
	strh.w	r0, [sp, #0xa]		@ first point y
	mov	r1, r9
	add	r0, sp, #0x50
	bl	fn_08023a0c		@ fill record at sp+0x50
	ldr	r0, .L08018a1c
	str	r0, [sp, #0x54]
	movs	r0, #3
	str	r0, [sp, #0x58]
	mov.w	r0, #0x50000
	str	r0, [sp, #0x84]
	add	r0, sp, #0x9c
	str	r0, [sp, #0x68]
	add	r0, sp, #0xa8
	str	r4, [sp, #0x94]
	str	r0, [sp, #0x60]
	ldrsh.w	r0, [sp, #0xa]
	str	r0, [sp, #0xc]		@ min/max y accumulators (compact mode)
	movs	r6, #0			@ r6 = sample index i
	str	r0, [sp, #0x1c]
	b.n	.L08018984
.L080187b0:
	ldrsh.w	r1, [sp, #0x8]
	strh.w	r1, [sp, #0x18]
	ldrh.w	r0, [sp, #0xa]
	strh.w	r0, [sp, #0x1a]
	ldrsh.w	r2, [r10, #0x4]		@ saved clip x1
	adds	r0, r7, #1
	add	r0, r2
	cmp	r1, r0
	bgt.n	.L080188c4		@ previous x beyond the clip: stop
	ldr	r0, [sp, #0x3c]
	ldrh.w	r2, [r5, #0x82]
	muls	r0, r6, r0
	subs	r3, r2, #1
	sdiv	r3, r0, r3
	ldr	r0, [sp, #0xe4]
	add	r0, r3
	sxth	r0, r0
	strh.w	r0, [sp, #0x8]		@ current x
	ldr	r3, [sp, #0x30]
	add	r3, r6
	sdiv	r12, r3, r2
	mls	r2, r2, r12, r3		@ (start + i) mod count
	sxth	r2, r2
	str	r2, [sp, #0x14]
	ldr	r3, [r4, #0x4]
	ldr.w	r12, [sp, #0x24]
	ldrsh.w	r2, [r3, r2, lsl #1]
	ldrb	r3, [r4, #0xc]
	ubfx	r3, r3, #0x4, #0x1
	add.w	r3, r5, r3, lsl #1
	ldrsh.w	r8, [r3, #0x6c]
	ldrsh.w	r3, [r3, #0x70]
	sub.w	r2, r2, r8
	mul	r2, r2, r12
	sub.w	r3, r3, r8
	sdiv	r2, r2, r3
	b.n	.L08018824
.L08018822:
	b.n	.L08018a02
.L08018824:
	sub.w	r3, r12, r2
	ldr	r2, [sp, #0xe8]
	add	r2, r3
	sxth	r2, r2
	strh.w	r2, [sp, #0xa]		@ current y
	mov	r8, r2
	ldrsh.w	r2, [r10, #0x0]		@ saved clip x0
	subs	r2, r2, r7
	.inst.n	0x1e52			@ subs r2, r2, #1
	cmp	r0, r2
	blt.n	.L080188c0
	cmp	r6, #0
	beq.n	.L080188c0
	ldr	r2, [sp, #0xec]
	cbz	r2, .L080188c2		@ marker mode
	ldr	r3, [r4, #0x4]
	ldr	r2, [sp, #0x4c]
	ldrsh.w	r12, [r3, r2, lsl #1]
	movw	r2, #0x7fff
	cmp	r12, r2
	beq.n	.L080188c0
	ldr.w	r12, [sp, #0x14]
	ldrsh.w	r3, [r3, r12, lsl #1]
	cmp	r3, r2
	beq.n	.L080188c0
	ldr	r3, [sp, #0x1c]
	cmp	r8, r3
	bge.n	.L0801886e
	mov	r2, r3
	b.n	.L08018870
.L0801886e:
	mov	r2, r8
.L08018870:
	ldr	r3, [sp, #0xc]
	str	r2, [sp, #0x1c]
	cmp	r8, r3
	ble.n	.L0801887c
	mov	r2, r3
	b.n	.L0801887e
.L0801887c:
	mov	r2, r8
.L0801887e:
	str	r2, [sp, #0xc]
	cmp	r1, r0
	beq.n	.L0801897c
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh.w	r0, [sp, #0x18]
	strh.w	r0, [sp, #0x8]
	ldr	r0, [sp, #0x1c]
	strh.w	r2, [sp, #0x1a]
	strh.w	r0, [sp, #0xa]
	cmp	r2, r0
	bne.n	.L080188a2
	.inst.n	0x1c40			@ adds r0, r0, #1
	strh.w	r0, [sp, #0xa]
.L080188a2:
	add	r3, sp, #0x8
	add	r2, sp, #0x18
	add	r1, sp, #0x9c
	mov	r0, r9
	bl	fn_0801e8b8		@ vertical span
	ldrh.w	r0, [sp, #0x8]
	str.w	r8, [sp, #0xc]
	.inst.n	0x1c40			@ adds r0, r0, #1
	strh.w	r0, [sp, #0x8]
	str.w	r8, [sp, #0x1c]
.L080188c0:
	b.n	.L0801897c
.L080188c2:
	b.n	.L080188c6
.L080188c4:
	b.n	.L0801898e
.L080188c6:
	ldrh.w	r0, [sp, #0x18]
	subs	r1, r0, r7
	add	r0, r7
	strh.w	r0, [sp, #0x38]
	ldrh.w	r0, [sp, #0x1a]
	strh.w	r1, [sp, #0x34]
	sub.w	r1, r0, r11
	add	r0, r11
	strh.w	r0, [sp, #0x3a]
	subs	r0, r6, #1
	str	r0, [sp, #0x88]
	strh.w	r1, [sp, #0x36]
	ldr	r1, [r4, #0x4]
	ldr	r0, [sp, #0x4c]
	ldrsh.w	r1, [r1, r0, lsl #1]
	movw	r0, #0x7fff
	cmp	r1, r0
	beq.n	.L08018900
	add	r1, sp, #0x18
	b.n	.L08018902
.L08018900:
	movs	r1, #0
.L08018902:
	str	r1, [sp, #0x74]
	ldr	r2, [r4, #0x4]
	ldr	r1, [sp, #0x14]
	mov	r8, r0
	ldrsh.w	r1, [r2, r1, lsl #1]
	cmp	r1, r8
	beq.n	.L08018916
	add	r0, sp, #0x8
	b.n	.L08018918
.L08018916:
	movs	r0, #0
.L08018918:
	str	r0, [sp, #0x78]
	add	r0, sp, #0x34
	str	r0, [sp, #0x5c]
	ldr	r1, [r4, #0x4]
	ldr	r0, [sp, #0x4c]
	add	r2, sp, #0x50
	ldrsh.w	r0, [r1, r0, lsl #1]
	str	r0, [sp, #0x90]
	movs	r1, #0x1a
	mov	r0, r5
	bl	fn_080207f4
	ldr	r0, [r4, #0x4]
	ldr	r1, [sp, #0x4c]
	ldrsh.w	r2, [r0, r1, lsl #1]
	cmp	r2, r8
	beq.n	.L08018954
	ldr	r1, [sp, #0x14]
	ldrsh.w	r1, [r0, r1, lsl #1]
	cmp	r1, r8
	beq.n	.L08018954
	add	r3, sp, #0x8
	add	r2, sp, #0x18
	add	r1, sp, #0x9c
	mov	r0, r9
	bl	fn_0801e8b8		@ segment previous -> current
.L08018954:
	cbz	r7, .L08018972
	cmp.w	r11, #0
	beq.n	.L08018972
	ldr	r1, [r4, #0x4]
	ldr	r0, [sp, #0x4c]
	ldrsh.w	r1, [r1, r0, lsl #1]
	cmp	r1, r8
	beq.n	.L08018972
	add	r2, sp, #0x34
	add	r1, sp, #0xa8
	mov	r0, r9
	bl	fn_0801f31c		@ marker box around the previous point
.L08018972:
	add	r2, sp, #0x50
	movs	r1, #0x1b
	mov	r0, r5
	bl	fn_080207f4
.L0801897c:
	ldr	r0, [sp, #0x14]
	.inst.n	0x1c76			@ adds r6, r6, #1
	uxth	r6, r6
	str	r0, [sp, #0x4c]
.L08018984:
	ldrh.w	r0, [r5, #0x82]
	cmp	r0, r6
	bhi.w	.L080187b0
.L0801898e:
	ldr	r0, [sp, #0xec]
	cbnz	r0, .L08018a02
	ldrh.w	r0, [r5, #0x82]
	cmp	r0, r6
	bne.n	.L08018a02
	ldr	r1, [r4, #0x4]
	ldr	r0, [sp, #0x14]
	ldrsh.w	r1, [r1, r0, lsl #1]
	sub.w	r0, r1, #0x7f00
	subs	r0, #0xff
	beq.n	.L08018a02
	ldrh.w	r0, [sp, #0x8]
	.inst.n	0x1e76			@ subs r6, r6, #1
	subs	r1, r0, r7
	add	r0, r7
	strh.w	r1, [sp, #0x30]
	strh.w	r0, [sp, #0x34]
	ldrh.w	r0, [sp, #0xa]
	add	r2, sp, #0x50
	sub.w	r1, r0, r11
	add	r0, r11
	strh.w	r0, [sp, #0x36]
	movs	r0, #0
	str	r0, [sp, #0x74]
	str	r0, [sp, #0x78]
	add	r0, sp, #0x30
	str	r0, [sp, #0x5c]
	strh.w	r1, [sp, #0x32]
	str	r6, [sp, #0x88]
	ldr	r1, [r4, #0x4]
	ldr	r0, [sp, #0x14]
	ldrsh.w	r0, [r1, r0, lsl #1]
	str	r0, [sp, #0x90]
	movs	r1, #0x1a
	mov	r0, r5
	bl	fn_080207f4
	add	r2, sp, #0x30
	add	r1, sp, #0xa8
	mov	r0, r9
	bl	fn_0801f31c		@ final marker around the last point
	add	r2, sp, #0x50
	movs	r1, #0x1b
	mov	r0, r5
	bl	fn_080207f4
.L08018a02:
	mov	r1, r4
	ldr	r0, [sp, #0xe0]
	bl	read_word_at_base_plus_offset	@ next node
.L08018a0a:
	movs	r4, r0
	bne.w	.L08018722
	str.w	r10, [r9, #0x8]		@ restore the clip
.L08018a14:
	add	sp, #0x104
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short	0x0000			@ padding
.L08018a1c:
	.word d_08050f14

@ ----------------------------------------------------------------------------
@ fn_08018a20 - draws the sample curve of a chart object with markers, mapping
@ x and y through fn_08022b12.
@ param r0 = chart object (rectangle at +0x14, count halfword +0x82, scale
@ halfwords +0x84 and +0x86, list at +0x24), r1 = target context. No return
@ value.
@ Intersects the object rectangle with the clip at *(context+8) via
@ rect_intersect (result at sp+0xdc; an empty result returns before the clip is
@ changed), saves the old clip at sp+0xd0, stores the result as the new clip,
@ takes origin and scale from fn_0802499c, fn_08024af8, fn_08024b88,
@ fn_08024070, fn_08024208, fn_08023e7c * halfword +0x84 >> 8 (x extent, sp+0xcc)
@ and fn_08023e48 * halfword +0x86 >> 8 (y extent, sp+0x90), and marker half
@ sizes from fn_08024d2c(object, 0x20000) / 2 (r9) and fn_080249f0(object,
@ 0x20000) / 2 (r8); there is no count check and no second intersection.
@ For each list node (get_word_8_or_zero / read_word_at_base_plus_offset on the
@ list at +0x24) with byte +0xc bit 0 clear, starts at index start = node
@ halfword +10 (0 when object byte +0x88 bit 3 is set); when the halfword at
@ node word +4 [start] equals 10 the start point is (-0x1fff, -0x1fff) (literal
@ 0xffffe001 stored at sp+0x9c), otherwise x = origin x + fn_08022b12(halfword
@ at node word +0 [start], object halfwords +0x74 / +0x78 (+0x76 / +0x7a when
@ node byte +0xc bit 3 is set), 0, x extent) and y = origin y + y extent -
@ fn_08022b12(halfword at node word +4 [start], object halfwords +0x6c / +0x70
@ (+0x6e / +0x72 when node byte +0xc bit 4 is set), 0, y extent); 0x7fff =
@ missing. The fifth argument of fn_08022b12 (the extent) is passed on the
@ stack.
@ Walks halfword +0x82 samples (index = (start + i) mod count) and, for i > 0
@ with the current and previous sample not missing, draws a segment from the
@ previous point to the current point with fn_0801e8b8(context, pen, previous,
@ current) and, when both marker half sizes are nonzero, a marker box around the
@ previous point with fn_0801f31c(context, style, box); each sample (also a
@ missing one) is bracketed by fn_080207f4(object, 0x1a / 0x1b).
@ After the loop draws a final marker around the last point with fn_0801f31c,
@ bracketed by fn_080207f4, when the last sample is not missing.
@ Restores the clip at the end (0x08018dc2).
@ ----------------------------------------------------------------------------
	.section .text.fn_08018a20,"ax",%progbits
	.p2align 2
	.global fn_08018a20
	.thumb_func
	.type fn_08018a20, %function
fn_08018a20:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r10, r1			@ r10 = context
	ldr	r2, [r1, #0x8]		@ old clip
	sub	sp, #0xe4
	mov	r5, r0			@ r5 = object
	add.w	r1, r0, #0x14		@ object rectangle
	add	r0, sp, #0xdc		@ result rectangle
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L08018b36
	ldr.w	r0, [r10, #0x8]
	str	r0, [sp, #0xd0]		@ saved clip
	add	r1, sp, #0xdc
	str.w	r1, [r10, #0x8]		@ clip = intersection
	movs	r1, #0
	mov	r0, r5
	bl	fn_0802499c
	mov	r4, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024af8
	mov	r6, r0
	movs	r1, #0
	mov	r0, r5
	bl	fn_08024b88
	mov	r7, r0
	mov	r0, r5
	bl	fn_08023e7c
	ldrh.w	r1, [r5, #0x84]
	muls	r0, r1, r0
	sbfx	r0, r0, #0x8, #0x10
	str	r0, [sp, #0xcc]		@ x extent
	mov	r0, r5
	bl	fn_08023e48
	mov	r1, r0
	ldrh.w	r0, [r5, #0x86]
	muls	r1, r0, r1
	sbfx	r0, r1, #0x8, #0x10
	str	r0, [sp, #0x90]		@ y extent
	mov	r0, r5
	bl	fn_08024070
	mov	r1, r0
	ldrh	r2, [r5, #0x14]
	adds	r0, r6, r4
	add	r0, r2
	subs	r0, r0, r1
	sxth	r0, r0
	str	r0, [sp, #0x94]		@ x origin
	mov	r0, r5
	bl	fn_08024208
	mov	r1, r0
	ldrh	r2, [r5, #0x16]
	adds	r0, r7, r4
	add	r0, r2
	subs	r0, r0, r1
	sxth	r0, r0
	str	r0, [sp, #0xa0]		@ y origin
	add	r0, sp, #0xb0
	bl	fn_0801e8d2		@ initialise the pen record at sp+0xb0
	add	r2, sp, #0xb0
	mov.w	r1, #0x50000
	mov	r0, r5
	bl	fn_080250b6
	add	r0, sp, #0x58
	bl	fn_0801f344		@ initialise the style record at sp+0x58
	mov.w	r4, #0x20000
	add	r2, sp, #0x58
	mov	r1, r4
	mov	r0, r5
	bl	fn_0802516e
	mov	r1, r4
	mov	r0, r5
	bl	fn_08024d2c
	add.w	r0, r0, r0, lsr #31
	asr.w	r9, r0, #1		@ r9 = half size 1
	mov	r1, r4
	mov	r0, r5
	bl	fn_080249f0
	add.w	r0, r0, r0, lsr #31
	asrs	r2, r0, #1
	mov	r8, r2			@ r8 = half size 2
	ldrsh.w	r0, [sp, #0xb2]
	mov	r1, r9
	cmp	r9, r8
	blt.n	.L08018b04
	mov	r1, r2			@ r1 = the smaller half size
.L08018b04:
	add.w	r2, r0, r0, lsr #31
	cmp.w	r1, r2, asr #1
	ble.n	.L08018b1a
	ldrb.w	r1, [sp, #0xb9]
	orr.w	r1, r1, #0x10
	strb.w	r1, [sp, #0xb9]
.L08018b1a:
	cmp	r0, #1
	bne.n	.L08018b2a
	ldrb.w	r0, [sp, #0xb9]
	orr.w	r0, r0, #0x10
	strb.w	r0, [sp, #0xb9]
.L08018b2a:
	add.w	r0, r5, #0x24
	str	r0, [sp, #0xa8]		@ node list base
	bl	get_word_8_or_zero	@ first node
	b.n	.L08018dba
.L08018b36:
	b.n	.L08018dc6
.L08018b38:
	ldrb	r0, [r4, #0xc]
	lsls	r0, r0, #0x1f
	bne.n	.L08018c3c		@ node byte +0xc bit 0 set: skip
	ldrh	r0, [r4, #0x8]
	strh.w	r0, [sp, #0xb0]
	ldrh	r0, [r4, #0x8]
	strh.w	r0, [sp, #0x5c]
	ldrb.w	r0, [r5, #0x88]
	lsls	r0, r0, #0x1c
	bmi.n	.L08018b56		@ object byte +0x88 bit 3 set: start 0
	ldrh	r0, [r4, #0xa]
	b.n	.L08018b58
.L08018b56:
	movs	r0, #0
.L08018b58:
	sxth	r6, r0			@ r6 = start index
	ldr	r0, [sp, #0x94]
	strh.w	r0, [sp, #0xd8]
	str	r6, [sp, #0xa4]
	strh.w	r0, [sp, #0x9c]
	ldr	r0, [r4, #0x4]		@ sample array
	mov	r11, r6
	ldrh.w	r0, [r0, r6, lsl #1]
	cmp	r0, #0xa
	beq.n	.L08018bcc
	ldr	r0, [sp, #0xcc]
	str	r0, [sp]		@ stack argument: x extent
	ldr	r0, [r4, #0x0]
	movs	r3, #0
	ldrsh.w	r7, [r0, r6, lsl #1]
	ldrb	r0, [r4, #0xc]
	ubfx	r1, r0, #0x3, #0x1	@ node byte +0xc bit 3
	add.w	r0, r5, r1, lsl #1
	ldrsh.w	r2, [r0, #0x78]
	ldrsh.w	r1, [r0, #0x74]
	mov	r0, r7
	bl	fn_08022b12		@ x offset
	ldr	r1, [sp, #0x94]
	movs	r3, #0
	add	r0, r1
	strh.w	r0, [sp, #0x9c]		@ start point x
	ldr	r0, [sp, #0x90]
	str	r0, [sp]		@ stack argument: y extent
	ldr	r0, [r4, #0x4]
	ldrsh.w	r7, [r0, r6, lsl #1]
	ldrb	r0, [r4, #0xc]
	ubfx	r1, r0, #0x4, #0x1	@ node byte +0xc bit 4
	add.w	r0, r5, r1, lsl #1
	ldrsh.w	r2, [r0, #0x70]
	ldrsh.w	r1, [r0, #0x6c]
	mov	r0, r7
	bl	fn_08022b12		@ y offset
	ldr	r1, [sp, #0x90]
	subs	r0, r1, r0
	ldr	r1, [sp, #0xa0]
	add	r0, r1
	b.n	.L08018bd2
.L08018bcc:
	ldr	r0, .L08018dcc
	strh.w	r0, [sp, #0x9c]
.L08018bd2:
	strh.w	r0, [sp, #0x9e]		@ start point y
	mov	r1, r10
	add	r0, sp, #0x8
	bl	fn_08023a0c		@ fill record at sp+0x8
	mov.w	r0, #0x50000
	str	r0, [sp, #0x3c]
	ldr	r0, .L08018dd0
	str	r0, [sp, #0xc]
	movs	r0, #3
	str	r0, [sp, #0x10]
	add	r0, sp, #0xb0
	str	r0, [sp, #0x20]
	add	r0, sp, #0x58
	movs	r7, #0			@ r7 = sample index i
	str	r4, [sp, #0x4c]
	str	r0, [sp, #0x18]
	b.n	.L08018d3a
	nop				@ padding
.L08018bfc:
	ldrh.w	r0, [sp, #0x9c]
	strh.w	r0, [sp, #0xd8]		@ previous x
	ldrh.w	r0, [sp, #0x9e]
	strh.w	r0, [sp, #0xda]		@ previous y
	ldr	r0, [sp, #0xa4]
	ldrh.w	r2, [r5, #0x82]
	adds	r1, r0, r7
	sdiv	r0, r1, r2
	mls	r0, r2, r0, r1		@ (start + i) mod count
	sxth	r6, r0
	ldr	r0, [r4, #0x4]
	ldrsh.w	r0, [r0, r6, lsl #1]
	sub.w	r1, r0, #0x7f00
	subs	r1, #0xff
	beq.n	.L08018cfe		@ sample = 0x7fff: skip
	ldr	r1, [sp, #0x90]
	str	r1, [sp]		@ stack argument: y extent
	ldrb	r1, [r4, #0xc]
	ubfx	r1, r1, #0x4, #0x1
	add.w	r1, r5, r1, lsl #1
	b.n	.L08018c3e
.L08018c3c:
	b.n	.L08018db2
.L08018c3e:
	ldrsh.w	r2, [r1, #0x70]
	ldrsh.w	r1, [r1, #0x6c]
	movs	r3, #0
	bl	fn_08022b12		@ y offset
	ldr	r1, [sp, #0x90]
	movs	r3, #0
	subs	r0, r1, r0
	ldr	r1, [sp, #0xa0]
	add	r0, r1
	strh.w	r0, [sp, #0x9e]		@ current y
	ldr	r0, [sp, #0xcc]
	str	r0, [sp]		@ stack argument: x extent
	ldrb	r1, [r4, #0xc]
	ldr	r0, [r4, #0x0]
	ubfx	r1, r1, #0x3, #0x1
	add.w	r1, r5, r1, lsl #1
	ldrsh.w	r0, [r0, r6, lsl #1]
	ldrsh.w	r2, [r1, #0x78]
	ldrsh.w	r1, [r1, #0x74]
	bl	fn_08022b12		@ x offset
	ldr	r1, [sp, #0x94]
	add	r0, r1
	strh.w	r0, [sp, #0x9c]		@ current x
	cbz	r7, .L08018cfe		@ i = 0: no segment
	ldrh.w	r0, [sp, #0xd8]
	sub.w	r1, r0, r9
	add	r0, r9
	strh.w	r0, [sp, #0xc0]		@ box x1
	ldrh.w	r0, [sp, #0xda]
	strh.w	r1, [sp, #0xbc]		@ box x0
	sub.w	r1, r0, r8
	add	r0, r8
	strh.w	r0, [sp, #0xc2]		@ box y1
	subs	r0, r7, #1
	strh.w	r1, [sp, #0xbe]		@ box y0
	str	r0, [sp, #0x40]
	ldr	r1, [r4, #0x4]
	ldrsh.w	r1, [r1, r11, lsl #1]	@ previous sample
	sub.w	r0, r1, #0x7f00
	subs	r0, #0xff
	beq.n	.L08018cbe
	add	r1, sp, #0xd8
	b.n	.L08018cc0
.L08018cbe:
	movs	r1, #0
.L08018cc0:
	str	r1, [sp, #0x2c]
	ldr	r1, [r4, #0x4]
	ldrsh.w	r1, [r1, r6, lsl #1]	@ current sample
	sub.w	r0, r1, #0x7f00
	subs	r0, #0xff
	beq.n	.L08018cd4
	add	r0, sp, #0x9c
	b.n	.L08018cd6
.L08018cd4:
	movs	r0, #0
.L08018cd6:
	str	r0, [sp, #0x30]
	add	r0, sp, #0xbc
	str	r0, [sp, #0x14]
	ldr	r1, [r4, #0x4]
	add	r2, sp, #0x8
	ldrsh.w	r0, [r1, r11, lsl #1]
	str	r0, [sp, #0x48]
	movs	r1, #0x1a
	mov	r0, r5
	bl	fn_080207f4
	ldr	r1, [r4, #0x4]
	movw	r0, #0x7fff
	ldrsh.w	r2, [r1, r11, lsl #1]
	cmp	r2, r0
	beq.n	.L08018d2a
	b.n	.L08018d00
.L08018cfe:
	b.n	.L08018d34
.L08018d00:
	ldrsh.w	r1, [r1, r6, lsl #1]
	cmp	r1, r0
	beq.n	.L08018d2a
	add	r3, sp, #0x9c
	add	r2, sp, #0xd8
	add	r1, sp, #0xb0
	mov	r0, r10
	bl	fn_0801e8b8		@ segment previous -> current
	cmp.w	r9, #0
	beq.n	.L08018d2a
	cmp.w	r8, #0
	beq.n	.L08018d2a
	add	r2, sp, #0xbc
	add	r1, sp, #0x58
	mov	r0, r10
	bl	fn_0801f31c		@ marker box around the previous point
.L08018d2a:
	add	r2, sp, #0x8
	movs	r1, #0x1b
	mov	r0, r5
	bl	fn_080207f4
.L08018d34:
	.inst.n	0x1c7f			@ adds r7, r7, #1
	mov	r11, r6
	uxth	r7, r7
.L08018d3a:
	ldrh.w	r0, [r5, #0x82]
	cmp	r0, r7
	bhi.w	.L08018bfc
	ldrh.w	r0, [r5, #0x82]
	cmp	r0, r7
	bne.n	.L08018db2
	ldr	r0, [r4, #0x4]
	ldrsh.w	r1, [r0, r6, lsl #1]
	sub.w	r0, r1, #0x7f00
	subs	r0, #0xff
	beq.n	.L08018db2
	ldrh.w	r0, [sp, #0x9c]
	.inst.n	0x1e7f			@ subs r7, r7, #1
	sub.w	r1, r0, r9
	add	r0, r9
	strh.w	r0, [sp, #0xc0]
	ldrh.w	r0, [sp, #0x9e]
	strh.w	r1, [sp, #0xbc]
	sub.w	r1, r0, r8
	add	r0, r8
	strh.w	r0, [sp, #0xc2]
	movs	r0, #0
	strh.w	r1, [sp, #0xbe]
	str	r0, [sp, #0x2c]
	str	r0, [sp, #0x30]
	add	r0, sp, #0xbc
	str	r7, [sp, #0x40]
	str	r0, [sp, #0x14]
	ldr	r0, [r4, #0x4]
	add	r2, sp, #0x8
	movs	r1, #0x1a
	ldrsh.w	r0, [r0, r6, lsl #1]
	str	r0, [sp, #0x48]
	mov	r0, r5
	bl	fn_080207f4
	add	r2, sp, #0xbc
	add	r1, sp, #0x58
	mov	r0, r10
	bl	fn_0801f31c		@ final marker around the last point
	add	r2, sp, #0x8
	movs	r1, #0x1b
	mov	r0, r5
	bl	fn_080207f4
.L08018db2:
	mov	r1, r4
	ldr	r0, [sp, #0xa8]
	bl	read_word_at_base_plus_offset	@ next node
.L08018dba:
	movs	r4, r0
	bne.w	.L08018b38
	ldr	r1, [sp, #0xd0]
	str.w	r1, [r10, #0x8]		@ restore the clip
.L08018dc6:
	add	sp, #0xe4
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08018dcc:
	.word 0xffffe001
.L08018dd0:
	.word d_08050f14

