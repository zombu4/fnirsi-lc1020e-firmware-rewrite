@ gfx_05.s - graphics: image item drawing, rounded rectangle frame, frame strips, flush with rotation
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080154ba - draws an image item into a rectangle (no return value).
@   r0 = context (word +8 = clip rectangle pointer)
@   r1 = image item (word +0x10 = resource, word +0x14, byte +0x1a alpha,
@        byte +0x1c tiling flag, byte +2, halfword +0x18, byte +0x1b)
@   r2 = rectangle (four unsigned halfwords x0, y0, x1, y1)
@ Does nothing unless word item+0x10 is non-zero, byte item+0x1a is above 2 and
@ rect_intersect (0x08011e4c) of the rectangle with the clip rectangle
@ *(context+8) is non-empty. The intersection (sp+0x38) replaces the clip pointer
@ at context+8 while drawing; the old clip pointer is restored at the end.
@ The kind of the resource is read with fn_08021d60:
@   kind 2: size (halfwords at sp+0x40, sp+0x42) from fn_08027d30(resource,
@     item+0x14); the rectangle is centred on the given rectangle (width and
@     height by rect_width_0801d06a / rect_height_0801d01e, halved toward zero);
@     a draw record is initialised with fn_0801e7b4, filled from the item (word
@     +0x14, halfword +0x18, byte +0x1a) and drawn with fn_0801e274.
@   otherwise fn_0802187c(resource, &size) must return 1: a record is initialised
@     with fn_0801e240; with byte item+0x1c = 0 one copy is centred (size packed:
@     width in bits 10-20, height from bit 21) and drawn with fn_0801e1f0; with
@     byte item+0x1c non-zero copies are tiled over the rectangle in steps of
@     that width and height, each drawn with fn_0801e1f0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080154ba,"ax",%progbits
	.global fn_080154ba
	.thumb_func
	.type fn_080154ba, %function
fn_080154ba:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r6, r0			@ r6 = context
	ldr	r0, [r1, #0x10]		@ resource
	sub	sp, #0x48
	mov	r5, r2			@ r5 = rectangle
	mov	r4, r1			@ r4 = image item
	cmp	r0, #0
	beq.n	.L080155c8
	ldrb	r0, [r4, #0x1a]		@ alpha byte
	cmp	r0, #2
	bls.n	.L080155c8
	mov	r1, r5
	add	r0, sp, #0x38		@ result rectangle of the intersection
	ldr	r2, [r6, #8]		@ clip rectangle
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L080155c8
	add	r0, sp, #0x38
	ldr.w	r8, [r6, #8]		@ r8 = old clip pointer
	str	r0, [r6, #8]		@ clip = intersection
	ldr	r0, [r4, #0x10]
	bl	fn_08021d60		@ kind of the resource
	cmp	r0, #2
	beq.n	.L08015500
	mov	r1, sp			@ size output
	ldr	r0, [r4, #0x10]
	bl	fn_0802187c
	cmp	r0, #1
	beq.n	.L08015592
	b.n	.L08015694
.L08015500:
	movs	r7, #0
	movw	r0, #0x1fff
	strd	r7, r0, [sp]		@ [sp] = 0, [sp+4] = 0x1fff
	str	r7, [sp, #8]		@ [sp+8] = 0
	ldrd	r1, r2, [r4, #0x10]	@ resource, item word +0x14
	mov	r3, r7
	add	r0, sp, #0x40
	bl	fn_08027d30		@ size to sp+0x40 / sp+0x42
	mov	r0, r5
	bl	rect_width_0801d06a
	mov	r1, r0
	ldrh	r2, [r5]		@ x0
	ldrsh.w	r0, [sp, #0x40]		@ width of the resource
	add.w	r1, r1, r1, lsr #31	@ rectangle width / 2 toward zero
	add.w	r1, r2, r1, asr #1
	add.w	r2, r0, r0, lsr #31	@ resource width / 2 toward zero
	sub.w	r1, r1, r2, asr #1	@ left edge of the centred copy
	add	r0, r1
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh.w	r0, [sp, #0x10]		@ right edge
	strh.w	r1, [sp, #0xc]		@ left edge
	mov	r0, r5
	bl	rect_height_0801d01e
	mov	r1, r0
	ldrh	r2, [r5, #2]		@ y0
	ldrsh.w	r0, [sp, #0x42]		@ height of the resource
	add.w	r1, r1, r1, lsr #31
	add.w	r1, r2, r1, asr #1
	add.w	r2, r0, r0, lsr #31
	sub.w	r1, r1, r2, asr #1	@ top edge of the centred copy
	add	r0, r1
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh.w	r0, [sp, #0x12]		@ bottom edge
	strh.w	r1, [sp, #0xe]		@ top edge
	add	r0, sp, #0x14
	bl	fn_0801e7b4		@ initialise the draw record at sp+0x14
	ldr	r0, [r4, #0x14]
	str	r0, [sp, #0x14]
	ldrh	r0, [r4, #0x18]
	strh.w	r0, [sp, #0x20]
	ldrb	r0, [r4, #0x1a]
	strb.w	r0, [sp, #0x2e]
	str	r7, [sp]
	add	r2, sp, #0xc		@ destination rectangle
	add	r1, sp, #0x14		@ draw record
	mov	r0, r6
	ldr	r3, [r4, #0x10]		@ resource
	bl	fn_0801e274
	b.n	.L08015694
.L08015592:
	add	r0, sp, #0x14
	bl	fn_0801e240		@ initialise the draw record at sp+0x14
	ldrb	r0, [r4, #2]
	strb.w	r0, [sp, #0x20]
	ldrh	r0, [r4, #0x18]
	strh.w	r0, [sp, #0x1c]
	ldrb	r0, [r4, #0x1b]
	strb.w	r0, [sp, #0x1e]
	ldrb	r0, [r4, #0x1a]
	strb.w	r0, [sp, #0x1f]
	ldrb	r0, [r4, #0x1c]		@ tiling flag
	mov.w	r7, #0xffffffff
	cbz	r0, .L080155ca
	ldr	r1, [sp]		@ packed size
	ldrh	r0, [r5, #2]
	strh.w	r0, [sp, #6]		@ tile rectangle top = rectangle y0
	add.w	r1, r7, r1, lsr #21	@ height - 1
	add	r0, r1
	b.n	.L08015684
.L080155c8:
	b.n	.L08015698
.L080155ca:
	mov	r0, r5
	bl	rect_width_0801d06a
	ldrh	r1, [r5]
	add.w	r0, r0, r0, lsr #31
	add.w	r0, r1, r0, asr #1
	ldr	r1, [sp]
	ubfx	r1, r1, #0xa, #0xb	@ width of the resource (bits 10-20)
	sub.w	r0, r0, r1, lsr #1
	strh.w	r0, [sp, #4]		@ left edge of the centred copy
	mov	r0, r5
	bl	rect_height_0801d01e
	ldrh	r1, [r5, #2]
	add.w	r0, r0, r0, lsr #31
	add.w	r1, r1, r0, asr #1
	ldr	r0, [sp]
	sub.w	r1, r1, r0, lsr #22	@ top edge of the centred copy (height from bit 21)
	ubfx	r2, r0, #0xa, #0xb
	strh.w	r1, [sp, #6]
	ldrh.w	r3, [sp, #4]
	.inst.n	0x1e52			@ subs r2, r2, #1
	add	r2, r3
	add.w	r0, r7, r0, lsr #21
	strh.w	r2, [sp, #8]		@ right edge
	add	r0, r1
	strh.w	r0, [sp, #0xa]		@ bottom edge
	add	r2, sp, #4
	add	r1, sp, #0x14
	mov	r0, r6
	ldr	r3, [r4, #0x10]
	bl	fn_0801e1f0
	b.n	.L08015694
.L0801562a:
	ldr	r1, [sp]
	ldrh	r0, [r5]
	ubfx	r1, r1, #0xa, #0xb	@ tile width
	strh.w	r0, [sp, #4]		@ tile left = rectangle x0
	.inst.n	0x1e49			@ subs r1, r1, #1
	add	r0, r1
	b.n	.L0801565e
.L0801563c:
	add	r2, sp, #4
	add	r1, sp, #0x14
	mov	r0, r6
	ldr	r3, [r4, #0x10]
	bl	fn_0801e1f0
	ldr	r0, [sp]
	ldrh.w	r1, [sp, #4]
	ubfx	r0, r0, #0xa, #0xb
	add	r1, r0
	strh.w	r1, [sp, #4]		@ next tile to the right
	ldrh.w	r1, [sp, #8]
	add	r0, r1
.L0801565e:
	strh.w	r0, [sp, #8]
	ldrsh.w	r0, [sp, #4]
	ldrsh.w	r1, [r5, #4]		@ rectangle x1
	cmp	r0, r1
	ble.n	.L0801563c
	ldrh.w	r1, [sp, #6]
	ldr	r0, [sp]
	add.w	r1, r1, r0, lsr #21	@ next row of tiles
	strh.w	r1, [sp, #6]
	ldrh.w	r1, [sp, #0xa]
	add.w	r0, r1, r0, lsr #21
.L08015684:
	strh.w	r0, [sp, #0xa]
	ldrsh.w	r0, [sp, #6]
	ldrsh.w	r1, [r5, #6]		@ rectangle y1
	cmp	r0, r1
	ble.n	.L0801562a
.L08015694:
	str.w	r8, [r6, #8]		@ restore the clip pointer
.L08015698:
	add	sp, #0x48
	pop.w	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_0801569e - draws a style record's frame (no return value).
@   r0 = context, r1 = style record, r2 = rectangle (x0, y0, x1, y1)
@ Needs byte style+0x22 above 2, halfword +0x20 non-zero, byte +0x23 & 0x3e
@ non-zero and bit 0 of byte +0x23 clear; otherwise returns.
@ r = min(halfword style+0 (signed), min(width, height) / 2 with width and
@ height signed halfwords of the rectangle). The rectangle is copied to sp+0x10
@ with copy_rect_0801d00c; then each edge is moved by halfword +0x20 or by
@ -(halfword +0x20 + r), chosen by bits 1-4 of byte +0x23: a set bit selects
@ halfword +0x20, a clear bit -(halfword +0x20 + r). Bit 3 decides x0 (added),
@ bit 4 decides x1 (subtracted), bit 2 decides y0 (added), bit 1 decides y1
@ (subtracted).
@ Calls fn_0801578c(context, rectangle, adjusted rectangle, r, max(r - halfword
@ +0x20, 0), halfword +0x1e, byte +0x22, byte +2).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801569e,"ax",%progbits
	.global fn_0801569e
	.thumb_func
	.type fn_0801569e, %function
fn_0801569e:
	push	{r4, r5, r6, r7, lr}
	mov	r7, r0			@ r7 = context
	ldrb.w	r0, [r1, #0x22]
	sub	sp, #0x1c
	mov	r6, r2			@ r6 = rectangle
	mov	r4, r1			@ r4 = style record
	cmp	r0, #2
	bls.n	.L08015788
	ldrh	r0, [r4, #0x20]
	cmp	r0, #0
	beq.n	.L08015788
	ldrb.w	r0, [r4, #0x23]
	tst.w	r0, #0x3e
	beq.n	.L08015788
	lsls	r0, r0, #0x1f		@ bit 0 of byte +0x23
	bne.n	.L08015788
	ldrh	r0, [r6, #4]
	ldrh	r1, [r6]
	ldrh	r2, [r6, #2]
	subs	r0, r0, r1
	.inst.n	0x1c40			@ adds r0, r0, #1
	sxth	r1, r0			@ width
	ldrh	r0, [r6, #6]
	ldrsh.w	r5, [r4]		@ r5 = halfword style+0
	subs	r0, r0, r2
	.inst.n	0x1c40			@ adds r0, r0, #1
	sxth	r0, r0			@ height
	cmp	r1, r0
	bge.n	.L080156e2
	mov	r0, r1			@ r0 = min(width, height)
.L080156e2:
	cmp.w	r5, r0, asr #1
	ble.n	.L080156ea
	asrs	r5, r0, #1		@ r5 = min(style+0, min / 2)
.L080156ea:
	mov	r1, r6
	add	r0, sp, #0x10
	bl	copy_rect_0801d00c	@ copy of the rectangle at sp+0x10
	ldrb.w	r0, [r4, #0x23]
	ldrsh.w	r2, [sp, #0x10]		@ x0
	ubfx	r1, r0, #1, #5
	lsls	r0, r1, #0x1d
	ldrsh.w	r0, [r4, #0x20]
	bmi.n	.L0801570a
	add	r0, r5
	rsbs	r0, r0, #0		@ -(halfword +0x20 + r)
.L0801570a:
	add	r0, r2
	strh.w	r0, [sp, #0x10]
	lsls	r0, r1, #0x1c
	ldrsh.w	r2, [sp, #0x14]
	ldrsh.w	r0, [r4, #0x20]
	bmi.n	.L08015720
	add	r0, r5
	rsbs	r0, r0, #0
.L08015720:
	subs	r0, r2, r0
	strh.w	r0, [sp, #0x14]
	ldrb.w	r0, [r4, #0x23]
	ldrsh.w	r1, [sp, #0x12]
	lsrs	r0, r0, #1
	lsls	r0, r0, #0x1e
	ldrsh.w	r0, [r4, #0x20]
	bmi.n	.L0801573c
	add	r0, r5
	rsbs	r0, r0, #0
.L0801573c:
	add	r0, r1
	strh.w	r0, [sp, #0x12]
	ldrb.w	r0, [r4, #0x23]
	ldrsh.w	r1, [sp, #0x16]
	lsrs	r0, r0, #1
	lsls	r0, r0, #0x1f
	ldrsh.w	r0, [r4, #0x20]
	bne.n	.L08015758
	add	r0, r5
	rsbs	r0, r0, #0
.L08015758:
	subs	r0, r1, r0
	strh.w	r0, [sp, #0x16]
	ldrh	r0, [r4, #0x20]
	subs	r0, r5, r0
	sxth	r0, r0
	cmp	r0, #0
	bge.n	.L0801576a
	movs	r0, #0			@ max(r - halfword +0x20, 0)
.L0801576a:
	ldrb	r2, [r4, #2]
	ldrb.w	r1, [r4, #0x22]
	strd	r1, r2, [sp, #8]	@ stack words 7, 8: byte +0x22, byte +2
	ldrh	r1, [r4, #0x1e]
	strh.w	r1, [sp, #4]		@ stack word 6: halfword +0x1e
	str	r0, [sp]		@ stack word 5: inner radius
	mov	r3, r5			@ outer radius
	add	r2, sp, #0x10		@ adjusted rectangle
	mov	r1, r6
	mov	r0, r7
	bl	fn_0801578c
.L08015788:
	add	sp, #0x1c
	pop	{r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_0801578c - fills the area between an outer and an inner rectangle, with
@ optional rounded corners (no return value).
@   r0 = drawing context (saved at [sp+0xa4])
@   r1 = outer rectangle O (r4), r2 = inner rectangle I (r6)
@   r3 = outer corner radius (r5, signed)
@   stack word 5 = inner corner radius (r8)
@   stack word 6 = colour (word at [sp+0xdc], its low halfword is also used)
@   stack word 7 = alpha (r7), limited to 0xff (cmp r7,#255 / bcc)
@   stack word 8 = flag byte (r9)
@ F = fn_0801ecd0(O) is stored at [sp+0x98].
@ When F, r3 and the inner radius are all 0 it only calls fn_08015c1e(context, O,
@ I, colour, alpha) (the plain strips, 0x080158a0) and returns (0x080158ae).
@ Otherwise O is intersected with the clip [context+8] by rect_intersect into
@ sp+0x20 and the function returns when the result is empty. C = that result
@ (halfwords x0, y0, x1, y1); width W = sxth(x1 - x0 + 1) is stored at [sp+0x10].
@ 28 bytes at sp+0x28 are cleared with clear_bytes and the row buffer [sp+0x34]
@ = fn_08022bac(W) is taken. [sp+0x90] = -1; when r3 > 0 the corner mask is built
@ with fn_0801f1a8(sp+0x54, O, r3, 0) and [sp+0x90] = table_slot_insert(sp+0x54,
@ 0). Always fn_0801f1a8(sp+0x6c, I, inner radius, 1) and [sp+0x94] =
@ table_slot_insert(sp+0x6c, 0). Words [sp+0x28] and [sp+0x3c] = sp+4 (the
@ 4-halfword rectangle record at sp+4), halfword [sp+0x30] = low halfword of the
@ colour, bytes [sp+0x40] = alpha and [sp+0x41] = flag.
@ Limits (signed halfwords, O = outer, I = inner, r = outer radius): X0c =
@ max(O.x0 + r, I.x0) (r9), X1c = min(O.x1 - r, I.x1) (r8), Y0c = max(O.y0 + r,
@ I.y0) (r7), Y1c = min(O.y1 - r, I.y1) (stored at [sp+0x14]), Wc = sxth(X1c -
@ X0c + 1) ([sp+0x9c]); sl = (O.y0 <= I.y0) (r10), fb = (O.y1 >= I.y1) (r11),
@ later a = (O.x0 <= I.x0) at [sp+0x4c] and b = (O.x1 >= I.x1) at [sp+0x48].
@ When F is non-zero (loop 0x08015924): for y = signed halfword [sp+0x22] while
@ y <= signed halfword [sp+0x26]: the row is skipped when sl = 0 and Y0c > y; the
@ loop ends when fb = 0 and Y1c < y; otherwise halfwords [sp+6] and [sp+0xa] = y
@ (the rectangle at sp+4 takes x0 and x1 from C), the buffer is filled with
@ fill_bytes_ff(buf, W), masked with fn_0801ec54(buf, C.x0, y, W) (result byte to
@ [sp+0x38]) and drawn with fn_0801f730(context, sp+0x28). Then it frees:
@ fn_0801ec98(sp+0x6c), table_slot_clear([sp+0x94]), and when [sp+0x90] is not
@ -1 also fn_0801ec98(sp+0x54), table_slot_clear([sp+0x90]); finally
@ fn_08022c44(buf).
@ When F is 0 (0x08015956): v = 1, except v = 0 when a, b, sl and fb are all set
@ and Wc < 50 (0x0801597a-0x0801598c); byte [sp+0x38] = 1; strips with
@ fn_0801f730(context, sp+0x28): top (when sl and v) x X0c..X1c, y O.y0..I.y0 -
@ 1; bottom (fb and v) x X0c..X1c, y I.y1 + 1..O.y1; left (a) x O.x0..I.x0 - 1,
@ y Y0c..Y1c; right (b) x I.x1 + 1..O.x1, y Y0c..Y1c.
@ v = 1: left corner block x C.x0..min(C.x1, X0c - 1) of width Wl = sxth(...)
@ when Wl > 0, rows y = C.y0 .. Y0c - 1 when (a or sl) and rows y = Y1c + 1 ..
@ C.y1 when (a or fb); right block x max(C.x0, X1c + 1)..C.x1 of width Wr when
@ Wr > 0, rows C.y0 .. Y0c - 1 when (b or sl) and Y1c + 1 .. C.y1 when (b or
@ fb); each row: fill_bytes_ff(buf, width), fn_0801ec54(buf, x0, y, width) (byte
@ to [sp+0x38]), fn_0801f730.
@ v = 0: n = max(r3, O.y0 - I.y0) rows (loop 0x08015a86, i = 0 .. n - 1) of the
@ full width C.x0..C.x1: rows O.y0 + i (drawn when C.y0 <= row) and O.y1 - i
@ (drawn when C.y1 >= row), skipped together when C.y0 > O.y0 + i and C.y1 <
@ O.y1 - i; per index that is not skipped fill_bytes_ff(buf, W) and
@ fn_0801ec54(buf, C.x0, O.y0 + i, W) (byte to [sp+0x38]) run once, so the mask
@ is made for row O.y0 + i and the same buffer serves both rows, and
@ fn_0801f730(context, sp+0x28) is called once per drawn row with halfwords
@ [sp+6] and [sp+0xa] set to that row.
@ Common end (0x08015c10): fn_0801ec98(sp+0x6c), table_slot_clear([sp+0x94]),
@ then a jump to 0x0801593e, which always calls fn_0801ec98(sp+0x54) and
@ table_slot_clear([sp+0x90]) (without the -1 test of the F-nonzero path),
@ fn_08022c44(buf) and returns. The two branches at 0x0801589c and 0x0801589e go
@ to 0x080158a0 and 0x080158ae; 0x080158ae is the epilogue (add sp,#0xb4 / pop).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801578c,"ax",%progbits
	.global fn_0801578c
	.thumb_func
	.type fn_0801578c, %function
fn_0801578c:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0xa4
	mov	r5, r3			@ r5 = outer corner radius
	ldrd	r7, r9, [sp, #0xe0]	@ r7 = alpha, r9 = flag byte
	ldr.w	r8, [sp, #0xd8]		@ r8 = inner corner radius
	mov	r6, r2			@ r6 = inner rectangle
	mov	r4, r1			@ r4 = outer rectangle
	cmp	r7, #0xff
	bcc.n	.L080157a6
	movs	r7, #0xff		@ alpha limited to 0xff
.L080157a6:
	mov	r0, r1
	bl	fn_0801ecd0
	str	r0, [sp, #0x98]		@ F
	orrs	r0, r5
	orrs.w	r0, r0, r8
	beq.n	.L080158a0
	ldr	r0, [sp, #0xa4]
	mov	r1, r4
	ldr	r2, [r0, #8]		@ clip rectangle
	add	r0, sp, #0x20
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L080158ae
	ldrh.w	r0, [sp, #0x24]
	ldrh.w	r1, [sp, #0x20]
	subs	r0, r0, r1
	.inst.n	0x1c40			@ adds r0, r0, #1
	sxth	r0, r0
	str	r0, [sp, #0x10]		@ W
	movs	r1, #0x1c
	add	r0, sp, #0x28
	bl	clear_bytes
	ldr	r0, [sp, #0x10]
	bl	fn_08022bac
	str	r0, [sp, #0x34]		@ row buffer
	mov.w	r0, #0xffffffff
	str	r0, [sp, #0x90]
	cmp	r5, #0
	ble.n	.L08015806
	movs	r3, #0
	mov	r2, r5
	mov	r1, r4
	add	r0, sp, #0x54
	bl	fn_0801f1a8
	movs	r1, #0
	add	r0, sp, #0x54
	bl	table_slot_insert
	str	r0, [sp, #0x90]
.L08015806:
	movs	r3, #1
	mov	r2, r8
	mov	r1, r6
	add	r0, sp, #0x6c
	bl	fn_0801f1a8
	movs	r1, #0
	add	r0, sp, #0x6c
	bl	table_slot_insert
	str	r0, [sp, #0x94]
	add	r0, sp, #4
	str	r0, [sp, #0x28]
	str	r0, [sp, #0x3c]
	ldrh.w	r0, [sp, #0xdc]
	strb.w	r7, [sp, #0x40]		@ alpha
	strh.w	r0, [sp, #0x30]		@ low halfword of the colour
	strb.w	r9, [sp, #0x41]		@ flag byte
	ldrsh.w	r0, [r4]
	str	r0, [sp, #0x88]		@ O.x0
	ldrsh.w	r12, [r6]		@ I.x0
	adds	r3, r0, r5
	cmp	r3, r12
	bgt.n	.L08015844
	mov	r3, r12
.L08015844:
	ldrsh.w	r0, [r4, #4]
	sxth.w	r9, r3			@ X0c
	str	r0, [sp, #0x84]		@ O.x1
	ldrsh.w	r3, [r6, #4]		@ I.x1
	subs	r0, r0, r5
	cmp	r0, r3
	blt.n	.L0801585a
	mov	r0, r3
.L0801585a:
	sxth.w	r8, r0			@ X1c
	ldrsh.w	lr, [r4, #2]		@ O.y0
	ldrsh.w	r0, [r6, #2]		@ I.y0
	add.w	r1, lr, r5
	mov	r10, r0
	cmp	r1, r10
	bgt.n	.L08015872
	mov	r1, r0
.L08015872:
	sxth	r7, r1			@ Y0c
	ldrsh.w	r11, [r4, #6]		@ O.y1
	ldrsh.w	r1, [r6, #6]		@ I.y1
	sub.w	r2, r11, r5
	cmp	r2, r1
	blt.n	.L08015886
	mov	r2, r1
.L08015886:
	sxth	r0, r2			@ Y1c
	str	r0, [sp, #0x14]
	sub.w	r0, r8, r9
	.inst.n	0x1c40			@ adds r0, r0, #1
	sxth	r0, r0
	str	r0, [sp, #0x9c]		@ Wc
	cmp	lr, r10
	bgt.n	.L080158b4
	movs	r0, #1
	b.n	.L080158b6
	b.n	.L080158a0
	b.n	.L080158ae
.L080158a0:
	str	r7, [sp]		@ stack word 5 = alpha
	mov	r2, r6
	mov	r1, r4
	ldr	r3, [sp, #0xdc]		@ colour
	ldr	r0, [sp, #0xa4]
	bl	fn_08015c1e
.L080158ae:
	add	sp, #0xb4
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L080158b4:
	movs	r0, #0
.L080158b6:
	mov	r10, r0			@ sl
	cmp	r11, r1
	blt.n	.L080158c0
	movs	r0, #1
	b.n	.L080158c2
.L080158c0:
	movs	r0, #0
.L080158c2:
	mov	r11, r0			@ fb
	ldr	r0, [sp, #0x98]
	cbz	r0, .L08015940
	ldrh.w	r0, [sp, #0x20]
	strh.w	r0, [sp, #4]
	ldrh.w	r0, [sp, #0x24]
	strh.w	r0, [sp, #8]
	ldrsh.w	r4, [sp, #0x22]		@ y = C.y0
	b.n	.L08015924
	nop.n				@ padding (halfword 0xbf00, never reached)
.L080158e0:
	cmp.w	r10, #0
	bne.n	.L080158ea
	cmp	r7, r4
	bgt.n	.L08015922
.L080158ea:
	cmp.w	r11, #0
	bne.n	.L080158f6
	ldr	r0, [sp, #0x14]
	cmp	r0, r4
	blt.n	.L0801592c
.L080158f6:
	sxth	r5, r4
	strh.w	r5, [sp, #6]
	strh.w	r5, [sp, #0xa]
	ldr	r1, [sp, #0x10]
	ldr	r0, [sp, #0x34]
	bl	fill_bytes_ff
	ldrsh.w	r1, [sp, #0x20]
	mov	r2, r5
	ldr	r3, [sp, #0x10]
	ldr	r0, [sp, #0x34]
	bl	fn_0801ec54
	strb.w	r0, [sp, #0x38]
	add	r1, sp, #0x28
	ldr	r0, [sp, #0xa4]
	bl	fn_0801f730
.L08015922:
	.inst.n	0x1c64			@ adds r4, r4, #1
.L08015924:
	ldrsh.w	r0, [sp, #0x26]
	cmp	r0, r4
	bge.n	.L080158e0
.L0801592c:
	add	r0, sp, #0x6c
	bl	fn_0801ec98
	ldr	r0, [sp, #0x94]
	bl	table_slot_clear
	ldr	r0, [sp, #0x90]
	.inst.n	0x1c40			@ adds r0, r0, #1
	beq.n	.L0801594e
.L0801593e:
	b.n	.L08015942
.L08015940:
	b.n	.L08015956
.L08015942:
	add	r0, sp, #0x54
	bl	fn_0801ec98
	ldr	r0, [sp, #0x90]
	bl	table_slot_clear
.L0801594e:
	ldr	r0, [sp, #0x34]
	bl	fn_08022c44
	b.n	.L080158ae
.L08015956:
	ldr	r0, [sp, #0x88]
	cmp	r0, r12
	bgt.n	.L08015960
	movs	r0, #1
	b.n	.L08015962
.L08015960:
	movs	r0, #0
.L08015962:
	str	r0, [sp, #0x4c]		@ a = (O.x0 <= I.x0)
	ldr	r0, [sp, #0x84]
	cmp	r0, r3
	blt.n	.L0801596e
	movs	r1, #1
	b.n	.L08015970
.L0801596e:
	movs	r1, #0
.L08015970:
	movs	r0, #1
	str	r0, [sp]		@ v = 1
	ldr	r0, [sp, #0x4c]
	str	r1, [sp, #0x48]		@ b = (O.x1 >= I.x1)
	ands	r0, r1
	and.w	r0, r0, r10
	tst.w	r0, r11
	beq.n	.L0801598e
	ldr	r0, [sp, #0x9c]
	cmp	r0, #0x32
	bge.n	.L0801598e
	movs	r0, #0
	str	r0, [sp]		@ v = 0
.L0801598e:
	movs	r0, #1
	ldr	r1, [sp]
	strb.w	r0, [sp, #0x38]
	tst.w	r10, r1
	beq.n	.L080159ba
	strh.w	r9, [sp, #4]		@ top strip: x X0c..X1c
	strh.w	r8, [sp, #8]
	ldrh	r0, [r4, #2]
	strh.w	r0, [sp, #6]		@ y O.y0
	ldrh	r0, [r6, #2]
	add	r1, sp, #0x28
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh.w	r0, [sp, #0xa]		@ to I.y0 - 1
	ldr	r0, [sp, #0xa4]
	bl	fn_0801f730
.L080159ba:
	ldr	r1, [sp]
	tst.w	r11, r1
	beq.n	.L080159e0
	strh.w	r9, [sp, #4]		@ bottom strip: x X0c..X1c
	strh.w	r8, [sp, #8]
	ldrh	r0, [r6, #6]
	add	r1, sp, #0x28
	.inst.n	0x1c40			@ adds r0, r0, #1
	strh.w	r0, [sp, #6]		@ y I.y1 + 1
	ldrh	r0, [r4, #6]
	strh.w	r0, [sp, #0xa]		@ to O.y1
	ldr	r0, [sp, #0xa4]
	bl	fn_0801f730
.L080159e0:
	ldr	r0, [sp, #0x4c]
	cbz	r0, .L08015a04
	ldrh	r0, [r4]
	strh.w	r0, [sp, #4]		@ left strip: x O.x0..I.x0 - 1
	ldrh	r0, [r6]
	strh.w	r7, [sp, #6]		@ y Y0c..Y1c
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh.w	r0, [sp, #8]
	ldr	r0, [sp, #0x14]
	strh.w	r0, [sp, #0xa]
	add	r1, sp, #0x28
	ldr	r0, [sp, #0xa4]
	bl	fn_0801f730
.L08015a04:
	ldr	r0, [sp, #0x48]
	cbz	r0, .L08015a28
	ldrh	r0, [r6, #4]
	add	r1, sp, #0x28
	.inst.n	0x1c40			@ adds r0, r0, #1
	strh.w	r0, [sp, #4]		@ right strip: x I.x1 + 1..O.x1
	ldrh	r0, [r4, #4]
	strh.w	r0, [sp, #8]
	ldr	r0, [sp, #0x14]
	strh.w	r7, [sp, #6]		@ y Y0c..Y1c
	strh.w	r0, [sp, #0xa]
	ldr	r0, [sp, #0xa4]
	bl	fn_0801f730
.L08015a28:
	ldr	r0, [sp]
	cbz	r0, .L08015a5e
	ldrsh.w	r0, [sp, #0x24]
	ldrsh.w	r1, [sp, #0x20]
	sub.w	r2, r9, #1
	strh.w	r1, [sp, #4]		@ left corner block: x C.x0..min(C.x1, X0c - 1)
	cmp	r0, r2
	blt.n	.L08015a42
	mov	r0, r2
.L08015a42:
	strh.w	r0, [sp, #8]
	subs	r0, r0, r1
	.inst.n	0x1c40			@ adds r0, r0, #1
	sxth	r5, r0			@ Wl
	cmp	r5, #0
	ble.n	.L08015b32
	ldr	r0, [sp, #0x4c]
	orrs.w	r0, r0, r10
	beq.n	.L08015b26
	ldrsh.w	r4, [sp, #0x22]
	b.n	.L08015b22
.L08015a5e:
	ldrh.w	r0, [sp, #0x20]
	strh.w	r0, [sp, #4]		@ v = 0: full width C.x0..C.x1
	ldrh.w	r0, [sp, #0x24]
	strh.w	r0, [sp, #8]
	ldrsh.w	r0, [r4, #2]
	ldrsh.w	r1, [r6, #2]
	subs	r0, r0, r1		@ O.y0 - I.y0
	cmp	r0, r5
	blt.n	.L08015a7e
	mov	r5, r0
.L08015a7e:
	sxth.w	r8, r5			@ n = max(r3, O.y0 - I.y0)
	movs	r5, #0			@ i = 0
	b.n	.L08015aee
.L08015a86:
	ldrh	r0, [r4, #2]
	add	r0, r5
	sxth	r6, r0			@ O.y0 + i
	ldrh	r0, [r4, #6]
	subs	r0, r0, r5
	sxth	r7, r0			@ O.y1 - i
	ldrsh.w	r0, [sp, #0x22]
	cmp	r0, r6
	ble.n	.L08015aa2
	ldrsh.w	r0, [sp, #0x26]
	cmp	r0, r7
	blt.n	.L08015aec
.L08015aa2:
	ldr	r1, [sp, #0x10]
	ldr	r0, [sp, #0x34]
	bl	fill_bytes_ff
	ldrsh.w	r1, [sp, #4]
	mov	r2, r6
	ldr	r3, [sp, #0x10]
	ldr	r0, [sp, #0x34]
	bl	fn_0801ec54
	strb.w	r0, [sp, #0x38]
	ldrsh.w	r0, [sp, #0x22]
	cmp	r0, r6
	bgt.n	.L08015ad4
	strh.w	r6, [sp, #6]
	strh.w	r6, [sp, #0xa]
	add	r1, sp, #0x28
	ldr	r0, [sp, #0xa4]
	bl	fn_0801f730
.L08015ad4:
	ldrsh.w	r0, [sp, #0x26]
	cmp	r0, r7
	blt.n	.L08015aec
	strh.w	r7, [sp, #6]
	strh.w	r7, [sp, #0xa]
	add	r1, sp, #0x28
	ldr	r0, [sp, #0xa4]
	bl	fn_0801f730
.L08015aec:
	.inst.n	0x1c6d			@ adds r5, r5, #1
.L08015aee:
	cmp	r5, r8
	blt.n	.L08015a86
	b.n	.L08015c10
.L08015af4:
	sxth	r6, r4
	strh.w	r6, [sp, #6]
	strh.w	r6, [sp, #0xa]
	mov	r1, r5
	ldr	r0, [sp, #0x34]
	bl	fill_bytes_ff
	ldrsh.w	r1, [sp, #4]
	mov	r3, r5
	mov	r2, r6
	ldr	r0, [sp, #0x34]
	bl	fn_0801ec54
	strb.w	r0, [sp, #0x38]
	add	r1, sp, #0x28
	ldr	r0, [sp, #0xa4]
	bl	fn_0801f730
	.inst.n	0x1c64			@ adds r4, r4, #1
.L08015b22:
	cmp	r7, r4
	bgt.n	.L08015af4
.L08015b26:
	ldr	r0, [sp, #0x4c]
	orrs.w	r0, r0, r11
	beq.n	.L08015b6a
	ldr	r4, [sp, #0x14]
	b.n	.L08015b60
.L08015b32:
	b.n	.L08015b6a
.L08015b34:
	sxth	r6, r4
	strh.w	r6, [sp, #6]
	strh.w	r6, [sp, #0xa]
	mov	r1, r5
	ldr	r0, [sp, #0x34]
	bl	fill_bytes_ff
	ldrsh.w	r1, [sp, #4]
	mov	r3, r5
	mov	r2, r6
	ldr	r0, [sp, #0x34]
	bl	fn_0801ec54
	strb.w	r0, [sp, #0x38]
	add	r1, sp, #0x28
	ldr	r0, [sp, #0xa4]
	bl	fn_0801f730
.L08015b60:
	ldrsh.w	r0, [sp, #0x26]
	.inst.n	0x1c64			@ adds r4, r4, #1
	cmp	r0, r4
	bge.n	.L08015b34
.L08015b6a:
	ldrsh.w	r0, [sp, #0x20]
	add.w	r1, r8, #1
	cmp	r0, r1
	bgt.n	.L08015b78
	mov	r0, r1
.L08015b78:
	ldrh.w	r1, [sp, #0x24]
	strh.w	r0, [sp, #4]		@ right block: x max(C.x0, X1c + 1)..C.x1
	subs	r0, r1, r0
	.inst.n	0x1c40			@ adds r0, r0, #1
	sxth	r5, r0			@ Wr
	strh.w	r1, [sp, #8]
	cmp	r5, #0
	ble.n	.L08015c10
	ldr	r0, [sp, #0x48]
	orrs.w	r0, r0, r10
	beq.n	.L08015bce
	ldrsh.w	r4, [sp, #0x22]
	b.n	.L08015bca
.L08015b9c:
	sxth	r6, r4
	strh.w	r6, [sp, #6]
	strh.w	r6, [sp, #0xa]
	mov	r1, r5
	ldr	r0, [sp, #0x34]
	bl	fill_bytes_ff
	ldrsh.w	r1, [sp, #4]
	mov	r3, r5
	mov	r2, r6
	ldr	r0, [sp, #0x34]
	bl	fn_0801ec54
	strb.w	r0, [sp, #0x38]
	add	r1, sp, #0x28
	ldr	r0, [sp, #0xa4]
	bl	fn_0801f730
	.inst.n	0x1c64			@ adds r4, r4, #1
.L08015bca:
	cmp	r7, r4
	bgt.n	.L08015b9c
.L08015bce:
	ldr	r0, [sp, #0x48]
	orrs.w	r0, r0, r11
	beq.n	.L08015c10
	ldr	r4, [sp, #0x14]
	b.n	.L08015c06
.L08015bda:
	sxth	r6, r4
	strh.w	r6, [sp, #6]
	strh.w	r6, [sp, #0xa]
	mov	r1, r5
	ldr	r0, [sp, #0x34]
	bl	fill_bytes_ff
	ldrsh.w	r1, [sp, #4]
	mov	r3, r5
	mov	r2, r6
	ldr	r0, [sp, #0x34]
	bl	fn_0801ec54
	strb.w	r0, [sp, #0x38]
	add	r1, sp, #0x28
	ldr	r0, [sp, #0xa4]
	bl	fn_0801f730
.L08015c06:
	ldrsh.w	r0, [sp, #0x26]
	.inst.n	0x1c64			@ adds r4, r4, #1
	cmp	r0, r4
	bge.n	.L08015bda
.L08015c10:
	add	r0, sp, #0x6c
	bl	fn_0801ec98
	ldr	r0, [sp, #0x94]
	bl	table_slot_clear
	b.n	.L0801593e

@ ----------------------------------------------------------------------------
@ fn_08015c1e - draws the four plain strips between an outer and an inner
@ rectangle (no return value).
@   r0 = context, r1 = outer rectangle (r4), r2 = inner rectangle (r5),
@   r3 = colour halfword (saved at [sp+0x44]), stack word 5 = alpha byte
@   (r6 = [sp+0x68])
@ Initialises a 0x1c-byte draw record at sp+8 with clear_bytes, sets record word
@ 0 = pointer to the rectangle scratch at sp (halfwords x0, y0, x1, y1), record
@ +8 = colour halfword, record +0x18 = alpha byte. Flags: r7 = (outer.y0 <=
@ inner.y0), r6 = (outer.y1 >= inner.y1), r9 = (outer.x0 <= inner.x0), r8 =
@ (outer.x1 >= inner.x1), all signed. Draws each through fn_0801f730(context,
@ record): the strip above (x0..x1 of the outer rectangle, y from outer.y0 to
@ inner.y0 - 1) when r7, the strip below (inner.y1 + 1 to outer.y1) when r6, the
@ left strip (x from outer.x0 to inner.x0 - 1, y from the larger of the two top
@ values to the smaller of the two bottom values) when r9, and the right strip
@ (inner.x1 + 1 to outer.x1) when r8.
@ ----------------------------------------------------------------------------
	.section .text.fn_08015c1e,"ax",%progbits
	.global fn_08015c1e
	.thumb_func
	.type fn_08015c1e, %function
fn_08015c1e:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	sub	sp, #0x38
	mov	r4, r1			@ r4 = outer rectangle
	mov	r10, r0			@ r10 = context
	mov	r5, r2			@ r5 = inner rectangle
	movs	r1, #0x1c
	add	r0, sp, #8
	ldr	r6, [sp, #0x68]		@ alpha
	bl	clear_bytes
	str.w	sp, [sp, #8]		@ record word 0 = rectangle scratch at sp
	ldrh.w	r0, [sp, #0x44]
	strh.w	r0, [sp, #0x10]		@ record +8 = colour halfword
	strb.w	r6, [sp, #0x20]		@ record +0x18 = alpha
	ldrsh.w	r0, [r4, #2]
	ldrsh.w	r1, [r5, #2]
	cmp	r0, r1
	bgt.n	.L08015c54
	movs	r7, #1
	b.n	.L08015c56
.L08015c54:
	movs	r7, #0
.L08015c56:
	ldrsh.w	r0, [r4, #6]
	ldrsh.w	r1, [r5, #6]
	cmp	r0, r1
	blt.n	.L08015c66
	movs	r6, #1
	b.n	.L08015c68
.L08015c66:
	movs	r6, #0
.L08015c68:
	ldrsh.w	r0, [r4]
	ldrsh.w	r1, [r5]
	cmp	r0, r1
	bgt.n	.L08015c78
	movs	r1, #1
	b.n	.L08015c7a
.L08015c78:
	movs	r1, #0
.L08015c7a:
	mov	r9, r1
	ldrsh.w	r1, [r4, #4]
	ldrsh.w	r2, [r5, #4]
	cmp	r1, r2
	blt.n	.L08015c8c
	movs	r1, #1
	b.n	.L08015c8e
.L08015c8c:
	movs	r1, #0
.L08015c8e:
	strh.w	r0, [sp]		@ x0 = outer.x0
	ldrh	r0, [r4, #4]
	strh.w	r0, [sp, #4]		@ x1 = outer.x1
	ldrh	r0, [r4, #2]
	strh.w	r0, [sp, #2]		@ y0 = outer.y0
	ldrh	r0, [r5, #2]
	mov	r8, r1
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh.w	r0, [sp, #6]		@ y1 = inner.y0 - 1
	cbz	r7, .L08015cb2
	add	r1, sp, #8
	mov	r0, r10
	bl	fn_0801f730		@ strip above
.L08015cb2:
	ldrh	r0, [r5, #6]
	.inst.n	0x1c40			@ adds r0, r0, #1
	strh.w	r0, [sp, #2]		@ y0 = inner.y1 + 1
	ldrh	r0, [r4, #6]
	strh.w	r0, [sp, #6]		@ y1 = outer.y1
	cbz	r6, .L08015cca
	add	r1, sp, #8
	mov	r0, r10
	bl	fn_0801f730		@ strip below
.L08015cca:
	ldrh	r0, [r4]
	strh.w	r0, [sp]		@ x0 = outer.x0
	ldrh	r0, [r5]
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh.w	r0, [sp, #4]		@ x1 = inner.x0 - 1
	cbz	r7, .L08015ce0
	ldrsh.w	r0, [r5, #2]
	b.n	.L08015ce4
.L08015ce0:
	ldrsh.w	r0, [r4, #2]
.L08015ce4:
	strh.w	r0, [sp, #2]		@ y0 = larger top value
	cbz	r6, .L08015cf0
	ldrsh.w	r0, [r5, #6]
	b.n	.L08015cf4
.L08015cf0:
	ldrsh.w	r0, [r4, #6]
.L08015cf4:
	strh.w	r0, [sp, #6]		@ y1 = smaller bottom value
	cmp.w	r9, #0
	beq.n	.L08015d06
	add	r1, sp, #8
	mov	r0, r10
	bl	fn_0801f730		@ left strip
.L08015d06:
	ldrh	r0, [r5, #4]
	.inst.n	0x1c40			@ adds r0, r0, #1
	strh.w	r0, [sp]		@ x0 = inner.x1 + 1
	ldrh	r0, [r4, #4]
	strh.w	r0, [sp, #4]		@ x1 = outer.x1
	cmp.w	r8, #0
	beq.n	.L08015d22
	add	r1, sp, #8
	mov	r0, r10
	bl	fn_0801f730		@ right strip
.L08015d22:
	add	sp, #0x48
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ fn_08015d28 - hands the rectangle and pixel pointers of a descriptor to
@ call_with_offset_rect or fn_08015dd0 and updates a state block (no return
@ value).
@   r0 = pointer to a record whose first word points to a block (words +0x10
@        and +0x14 flags, byte +0x10, word +0x3c pointer to a descriptor)
@ r4 = fn_0801dcf4(word at 0x200004b8 [via the base 0x200004b4 + 4]); r5 =
@ descriptor = block word +0x3c. Calls the function pointer descriptor[0xc]
@ (descriptor word +0x30) with the descriptor when it is non-zero.
@ When r4[0] and r4[1] are both non-zero it loops while r4[4] != 0, calling the
@ pointer at *(*0x200004b8 + 0x28) when that is non-zero. Then r4[4] = 1 and
@ r4[5] = 1 only when bits 0 and 1 of the word at *(*(*0x200004b8 + 0xc) + 0x18)
@ are both set, else 0.
@ When block word +0x14 is non-zero: with (block word +0x10 & 0x30) = 0 or bit 2
@ of that word clear it calls call_with_offset_rect(block, descriptor[1],
@ descriptor[0]); otherwise fn_08015dd0(descriptor[1], descriptor[0]).
@ Last, with r4[0] and r4[1] non-zero and (block byte +0x10 & ~(r4[5] != 0) & 1)
@ = 0, r4[2] is toggled between r4[0] and r4[1].
@ ----------------------------------------------------------------------------
	.section .text.fn_08015d28,"ax",%progbits
	.p2align 2
	.global fn_08015d28
	.thumb_func
	.type fn_08015d28, %function
fn_08015d28:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r6, .L08015dcc		@ r6 = 0x200004b4
	mov	r7, r0			@ r7 = record
	ldr	r0, [r6, #4]
	bl	fn_0801dcf4
	mov	r4, r0
	ldr	r0, [r7]		@ block
	ldr	r5, [r0, #0x3c]		@ descriptor
	ldr	r1, [r5, #0x30]
	cbz	r1, .L08015d44
	mov	r0, r5
	blx	r1
.L08015d44:
	ldr	r0, [r4]
	cbz	r0, .L08015d5e
	ldr	r0, [r4, #4]
	cbnz	r0, .L08015d58
	b.n	.L08015d5e
.L08015d4e:
	ldr	r0, [r6, #4]
	ldr	r0, [r0]
	ldr	r1, [r0, #0x28]
	cbz	r1, .L08015d58
	blx	r1
.L08015d58:
	ldr	r0, [r4, #0x10]
	cmp	r0, #0
	bne.n	.L08015d4e
.L08015d5e:
	movs	r0, #1
	str	r0, [r4, #0x10]
	ldr	r1, [r6, #4]
	ldr	r1, [r1]
	ldr	r1, [r1, #0xc]
	ldr	r2, [r1, #0x18]
	lsls	r2, r2, #0x1f
	beq.n	.L08015d74
	ldr	r1, [r1, #0x18]
	lsls	r1, r1, #0x1e
	bmi.n	.L08015d76
.L08015d74:
	movs	r0, #0
.L08015d76:
	str	r0, [r4, #0x14]
	ldr	r0, [r4, #0x14]
	cbz	r0, .L08015d80
	movs	r6, #1
	b.n	.L08015d82
.L08015d80:
	movs	r6, #0
.L08015d82:
	ldr	r0, [r7]
	ldr	r1, [r0, #0x14]
	cbz	r1, .L08015da6
	ldr	r1, [r0, #0x10]
	tst.w	r1, #0x30
	beq.n	.L08015d9e
	lsls	r1, r1, #0x1d
	bpl.n	.L08015d9e
	ldrd	r1, r0, [r5]
	bl	fn_08015dd0
	b.n	.L08015da6
.L08015d9e:
	ldrd	r2, r1, [r5]
	bl	call_with_offset_rect
.L08015da6:
	ldr	r0, [r4]
	cmp	r0, #0
	beq.n	.L08015dc4
	ldr	r1, [r4, #4]
	cmp	r1, #0
	beq.n	.L08015dc4
	ldr	r2, [r7]
	ldrb	r2, [r2, #0x10]
	bics	r2, r6
	lsls	r2, r2, #0x1f
	bne.n	.L08015dc4
	ldr	r2, [r4, #8]
	cmp	r2, r0
	bne.n	.L08015dc8
	str	r1, [r4, #8]
.L08015dc4:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08015dc8:
	str	r0, [r4, #8]
	b.n	.L08015dc4
.L08015dcc:
	.word	0x200004b4		@ literal read by 0x08015d2c

@ ----------------------------------------------------------------------------
@ fn_08015dd0 - sends a rectangle of 16-bit pixels to call_with_offset_rect,
@ rotating or reversing it according to a mode field (no return value).
@   r0 = pointer to a rectangle (four signed halfwords x0, y0, x1, y1; they are
@        modified), [sp+0x50] after the prologue = r1 = pointer to the pixels
@ r6 = *0x200004b8 (block read through the base 0x200004b4 + 4). Returns without
@ drawing when bits 1 and 2 of block word +0x10 are both set. mode = (block word
@ +0x10 & 0x3f) >> 4.
@ Mode 2: calls fn_08016018(block, rectangle, pixels) and then tail-calls
@ call_with_offset_rect(block, rectangle, pixels).
@ Modes 1 and 3: r11 = fn_0801dcf4 result; width r4 and height r7 of the
@ rectangle; strip height = min(height, 0x1400 / width) rows. The rectangle
@ coordinates are mapped against halfwords 0 and 1 of the block (offset by -1):
@ mode 1 sets y1 = block[1] - x0 - 1 and y0 = y1 - width + 1, other modes set y0
@ = x0 and y1 = y0 + (x1 - x0). Each strip: word r11+0x10 = 1; when the strip
@ start is 0 and the height is at least the width, the whole square is rotated in
@ place with rotate_square_halfword_matrix(mode == 3, width, pixels); otherwise a
@ temporary buffer of 0x2800 bytes from fn_08022bac (allocated once) is filled
@ with a transposing copy of the strip (mode 3 reverses the index) and the
@ rectangle x range is updated for that strip. After the strip, word r11+0x14 = 1
@ for the last strip when bits 0 and 1 of word r11+0x18 are both set, else 0. The
@ strip is sent with call_with_offset_rect(block, rectangle, buffer or pixels) and
@ the function then waits while word r11+0x10 != 0, calling the pointer at
@ block+0x28 (when non-zero) with the block. Frees the temporary buffer with
@ fn_08022c44 (tail call) when one was allocated.
@ ----------------------------------------------------------------------------
	.section .text.fn_08015dd0,"ax",%progbits
	.p2align 2
	.global fn_08015dd0
	.thumb_func
	.type fn_08015dd0, %function
fn_08015dd0:
	push.w	{r0, r1, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r5, r0			@ r5 = rectangle
	ldr	r0, .L08016000		@ r0 = 0x200004b4
	sub	sp, #0x4c
	ldr	r1, [r0, #4]
	ldr	r6, [r1]		@ r6 = block
	ldr	r0, [r6, #0x10]
	lsls	r2, r0, #0x1e
	bpl.n	.L08015de8
	lsls	r2, r0, #0x1d
	bmi.n	.L08015ec6
.L08015de8:
	ubfx	r0, r0, #4, #2		@ mode
	cmp	r0, #2
	beq.n	.L08015e2e
	cmp	r0, #1
	beq.n	.L08015df8
	cmp	r0, #3
	bne.n	.L08015ec6
.L08015df8:
	movs	r0, #0
	str	r0, [sp, #0x3c]		@ temporary buffer = none
	mov	r0, r1
	bl	fn_0801dcf4
	mov	r11, r0
	ldrh	r1, [r5, #4]
	ldrsh.w	r0, [r5]
	ldrh	r2, [r5, #6]
	subs	r1, r1, r0
	.inst.n	0x1c49			@ adds r1, r1, #1
	sxth	r4, r1			@ r4 = width
	ldrsh.w	r1, [r5, #2]
	subs	r2, r2, r1
	.inst.n	0x1c52			@ adds r2, r2, #1
	sxth	r7, r2			@ r7 = height
	mov.w	r2, #0x1400
	udiv	r3, r2, r4
	cmp	r3, r7
	bge.n	.L08015e48
	udiv	r2, r2, r4
	b.n	.L08015e4a
.L08015e2e:
	mov	r1, r5
	mov	r0, r6
	ldr	r2, [sp, #0x50]
	bl	fn_08016018
	ldr	r2, [sp, #0x50]
	add	sp, #0x54
	mov	r1, r5
	mov	r0, r6
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w	call_with_offset_rect
.L08015e48:
	mov	r2, r7
.L08015e4a:
	str	r2, [sp, #0x30]		@ strip height
	str	r1, [sp, #0x1c]		@ y0 of the rectangle
	ldrb	r1, [r6, #0x10]
	ubfx	r1, r1, #4, #2
	cmp	r1, #1
	beq.n	.L08015e64
	strh	r0, [r5, #2]		@ y0 = x0
	subs	r1, r4, #1
	add	r0, r1
	strh	r0, [r5, #6]		@ y1 = x0 + width - 1
.L08015e60:
	movs	r0, #0
	b.n	.L08015fe0
.L08015e64:
	ldrh	r1, [r6, #2]
	subs	r0, r1, r0
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh	r0, [r5, #6]		@ y1 = block[1] - x0 - 1
	subs	r0, r0, r4
	.inst.n	0x1c40			@ adds r0, r0, #1
	strh	r0, [r5, #2]		@ y0 = y1 - width + 1
	b.n	.L08015e60
.L08015e74:
	ldr	r1, [sp, #0x30]
	sub.w	r0, r7, r10		@ rows left
	cmp	r0, r1
	ble.n	.L08015e80
	mov	r0, r1
.L08015e80:
	sxth	r0, r0			@ rows of this strip
	str	r0, [sp, #4]
	movs	r0, #1
	str.w	r0, [r11, #0x10]
	cmp.w	r10, #0
	bne.n	.L08015ed2
	cmp	r7, r4
	blt.n	.L08015ed2
	str	r4, [sp, #4]		@ whole square: strip = width rows
	ldrb	r0, [r6, #0x10]
	ubfx	r0, r0, #4, #2
	cmp	r0, #3
	beq.n	.L08015ec2
	movs	r0, #0
.L08015ea2:
	mov	r1, r4
	ldr	r2, [sp, #0x50]
	bl	rotate_square_halfword_matrix
	ldrb	r0, [r6, #0x10]
	ubfx	r0, r0, #4, #2
	cmp	r0, #1
	beq.n	.L08015ec8
	ldrh	r1, [r6]
	ldr	r0, [sp, #0x1c]
	subs	r0, r1, r0
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh	r0, [r5, #4]		@ x1 = block[0] - y0 - 1
	subs	r0, r0, r4
	b.n	.L08015f70
.L08015ec2:
	movs	r0, #1
	b.n	.L08015ea2
.L08015ec6:
	b.n	.L08015ff8
.L08015ec8:
	ldr	r0, [sp, #0x1c]
	strh	r0, [r5]		@ x0 = y0 of the rectangle
	ldr	r0, [sp, #0x1c]
	add	r0, r4
	b.n	.L08015fa0
.L08015ed2:
	ldr	r0, [sp, #0x3c]
	cbnz	r0, .L08015ee0
	mov.w	r0, #0x2800
	bl	fn_08022bac
	str	r0, [sp, #0x3c]		@ temporary buffer of 0x2800 bytes
.L08015ee0:
	ldrb	r0, [r6, #0x10]
	ubfx	r0, r0, #4, #2
	cmp	r0, #3
	beq.n	.L08015f22
	movs	r0, #0
.L08015eec:
	mov	lr, r0			@ lr = 1 for mode 3 (reversed index)
	ldr.w	r12, [sp, #0x50]	@ r12 = source pointer
	ldr	r1, [sp, #4]		@ rows of the strip
	ldr	r0, [sp, #0x3c]
	str	r0, [sp, #0x28]
	smulbb	r0, r4, r1
	.inst.n	0x1e40			@ subs r0, r0, #1
	str	r0, [sp, #0x34]		@ width * rows - 1
	subs	r0, r4, #1
	muls	r0, r1, r0
	str	r0, [sp, #0x38]		@ rows * (width - 1)
	movs	r0, #0
.L08015f08:
	mov	r9, r0			@ row counter
	cmp	r0, r1
	bge.n	.L08015f54
	ldr	r2, [sp, #0x38]
	cmp.w	lr, #0
	add.w	r0, r2, r9
	beq.n	.L08015f1e
	ldr	r2, [sp, #0x34]
	subs	r0, r2, r0
.L08015f1e:
	movs	r2, #0
	b.n	.L08015f48
.L08015f22:
	movs	r0, #1
	b.n	.L08015eec
.L08015f26:
	ldr	r3, [sp, #0x28]
	cmp.w	lr, #0
	add.w	r8, r3, r0, lsl #1
	mov	r3, r12
	add.w	r12, r12, #2
	ldrh	r3, [r3]
	strh.w	r3, [r8]
	beq.n	.L08015f42
	add	r0, r1
	b.n	.L08015f44
.L08015f42:
	subs	r0, r0, r1
.L08015f44:
	.inst.n	0x1c52			@ adds r2, r2, #1
	sxth	r2, r2
.L08015f48:
	cmp	r2, r4
	blt.n	.L08015f26
	add.w	r0, r9, #1
	sxth	r0, r0
	b.n	.L08015f08
.L08015f54:
	ldrb	r0, [r6, #0x10]
	ubfx	r0, r0, #4, #2
	cmp	r0, #1
	beq.n	.L08015f96
	ldrh	r1, [r6]
	ldr	r0, [sp, #0x1c]
	subs	r1, r1, r0
	sub.w	r0, r1, r10
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh	r0, [r5, #4]
	ldr	r1, [sp, #4]
	subs	r0, r0, r1
.L08015f70:
	.inst.n	0x1c40			@ adds r0, r0, #1
	strh	r0, [r5]
.L08015f74:
	ldr	r1, [sp, #4]
	add.w	r8, r10, r1		@ rows done after this strip
	cmp	r8, r7
	blt.n	.L08015fa6
	ldr.w	r0, [r11, #0x18]
	lsls	r0, r0, #0x1f
	beq.n	.L08015fa6
	ldr.w	r0, [r11, #0x18]
	lsls	r0, r0, #0x1e
	bpl.n	.L08015fa6
	movs	r0, #1
	str.w	r0, [r11, #0x14]	@ last strip and bits 0 and 1 of word +0x18 set
	b.n	.L08015fac
.L08015f96:
	ldr	r0, [sp, #0x1c]
	add	r0, r10
	strh	r0, [r5]
	ldr	r1, [sp, #4]
	add	r0, r1
.L08015fa0:
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh	r0, [r5, #4]
	b.n	.L08015f74
.L08015fa6:
	movs	r1, #0
	str.w	r1, [r11, #0x14]
.L08015fac:
	ldr	r0, [sp, #0x3c]
	cbz	r0, .L08015fbc
	mov	r2, r0			@ pixels = temporary buffer
.L08015fb2:
	mov	r1, r5
	mov	r0, r6
	bl	call_with_offset_rect
	b.n	.L08015fc8
.L08015fbc:
	ldr	r2, [sp, #0x50]		@ pixels = the caller's array
	b.n	.L08015fb2
.L08015fc0:
	ldr	r1, [r6, #0x28]
	cbz	r1, .L08015fc8
	mov	r0, r6
	blx	r1
.L08015fc8:
	ldr.w	r0, [r11, #0x10]
	cmp	r0, #0
	bne.n	.L08015fc0
	ldr	r0, [sp, #4]
	ldr	r1, [sp, #0x50]
	muls	r0, r4, r0
	add.w	r0, r1, r0, lsl #1
	str	r0, [sp, #0x50]		@ advance the source by rows * width pixels
	sxth.w	r0, r8
.L08015fe0:
	mov	r10, r0			@ r10 = rows done
	cmp	r0, r7
	blt.w	.L08015e74
	ldr	r0, [sp, #0x3c]
	cmp	r0, #0
	beq.n	.L08015ff8
	add	sp, #0x54
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w	fn_08022c44
.L08015ff8:
	add	sp, #0x54
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short	0x0000			@ padding
.L08016000:
	.word	0x200004b4		@ literal read by 0x08015dd6

@ ----------------------------------------------------------------------------
@ rotate_four_halfwords - rotates four halfword values (no return value).
@   r0, r1, r2, r3 = pointers to four halfwords A, B, C, D
@ Saves *A, then *A = *B, *B = *C, *C = *D, *D = saved value.
@ ----------------------------------------------------------------------------
	.section .text.rotate_four_halfwords,"ax",%progbits
	.p2align 2
	.global rotate_four_halfwords
	.thumb_func
	.type rotate_four_halfwords, %function
rotate_four_halfwords:
	push	{r4, r5, lr}
	ldrh	r4, [r0]		@ saved *A
	ldrh	r5, [r1]
	strh	r5, [r0]		@ *A = *B
	ldrh	r0, [r2]
	strh	r0, [r1]		@ *B = *C
	ldrh	r0, [r3]
	strh	r0, [r2]		@ *C = *D
	strh	r4, [r3]		@ *D = saved value
	pop	{r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fn_08016018 - reverses a halfword pixel array and mirrors its rectangle (no
@ return value).
@   r0 = pointer to a block (halfwords 0 and 1), r1 = pointer to a rectangle
@   (halfwords x0, y0, x1, y1, modified), r2 = pixel array
@ Reverses the order of the (x1 - x0 + 1) * (y1 - y0 + 1) halfwords at r2 by
@ swapping index i with count - 1 - i while i < count - 1 - i (unsigned compare).
@ Then rewrites the rectangle as x0' = block[0] - x1 - 1, x1' = block[0] - x0 - 1,
@ y0' = block[1] - y1 - 1, y1' = block[1] - y0 - 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08016018,"ax",%progbits
	.global fn_08016018
	.thumb_func
	.type fn_08016018, %function
fn_08016018:
	push	{r3, r4, r5, r6, r7, lr}
	ldrh	r3, [r1, #4]
	ldrh	r4, [r1]
	ldrh	r5, [r1, #2]
	subs	r3, r3, r4
	ldrh	r4, [r1, #6]
	.inst.n	0x1c5b			@ adds r3, r3, #1
	subs	r4, r4, r5
	.inst.n	0x1c64			@ adds r4, r4, #1
	smulbb	r3, r3, r4		@ count
	movs	r4, #0			@ i = 0
	.inst.n	0x1e5b			@ subs r3, r3, #1
	b.n	.L08016050
.L08016034:
	add.w	r6, r2, r3, lsl #1
	add.w	r7, r2, r4, lsl #1
	ldrh	r5, [r6]
	strh.w	r5, [sp]
	ldrh.w	r12, [r7]
	strh.w	r12, [r6]
	.inst.n	0x1e5b			@ subs r3, r3, #1
	strh	r5, [r7]
	.inst.n	0x1c64			@ adds r4, r4, #1
.L08016050:
	cmp	r3, r4
	bhi.n	.L08016034
	ldrh	r3, [r0, #2]
	ldrh	r4, [r1, #2]
	ldrh	r2, [r1, #6]
	subs	r3, r3, r4
	.inst.n	0x1e5b			@ subs r3, r3, #1
	strh	r3, [r1, #6]		@ y1' = block[1] - y0 - 1
	ldrh	r3, [r0, #2]
	subs	r2, r3, r2
	.inst.n	0x1e52			@ subs r2, r2, #1
	strh	r2, [r1, #2]		@ y0' = block[1] - y1 - 1
	ldrh	r3, [r0]
	ldrh	r4, [r1]
	ldrh	r2, [r1, #4]
	subs	r3, r3, r4
	.inst.n	0x1e5b			@ subs r3, r3, #1
	strh	r3, [r1, #4]		@ x1' = block[0] - x0 - 1
	ldrh	r0, [r0]
	subs	r0, r0, r2
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh	r0, [r1]		@ x0' = block[0] - x1 - 1
	pop	{r3, r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ rotate_square_halfword_matrix - rotates a square matrix of halfwords in place
@ (no return value).
@   r0 = direction flag (r10), r1 = side length n (r4), r2 = pointer to n * n
@   halfwords (r7)
@ For i in 0 .. n/2 - 1 and j in 0 .. (n+1)/2 - 1 (both counted as signed
@ halfwords, the bounds by an add of the sign bit and asr #1) rotates the four
@ halfwords at the positions (i, j), (j, n-1-i), (n-1-i, n-1-j), (n-1-j, i) with
@ rotate_four_halfwords; with the flag non-zero the order of two of the four
@ pointers is swapped (the other rotation direction).
@ ----------------------------------------------------------------------------
	.section .text.rotate_square_halfword_matrix,"ax",%progbits
	.global rotate_square_halfword_matrix
	.thumb_func
	.type rotate_square_halfword_matrix, %function
rotate_square_halfword_matrix:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r4, r1			@ r4 = n
	mov	r7, r2			@ r7 = matrix
	mov	r10, r0			@ r10 = direction flag
	movs	r6, #0			@ i = 0
	add.w	r9, r1, r4, lsr #31	@ n + sign bit
	b.n	.L080160f4
.L08016090:
	movs	r5, #0			@ j = 0
	adds	r0, r4, #1
	add.w	r8, r0, r0, lsr #31	@ n + 1 + sign bit
	b.n	.L080160ea
.L0801609a:
	subs	r0, r4, r6
	.inst.n	0x1e40			@ subs r0, r0, #1
	sxth	r1, r0			@ n - 1 - i
	subs	r0, r4, r5
	.inst.n	0x1e40			@ subs r0, r0, #1
	sxth	r0, r0			@ n - 1 - j
	cmp.w	r10, #0
	beq.n	.L080160c2
	smlabb	r2, r5, r4, r1
	add.w	r3, r7, r2, lsl #1
	smlabb	r1, r1, r4, r0
	add.w	r2, r7, r1, lsl #1
	smlabb	r0, r0, r4, r6
	b.n	.L080160d6
.L080160c2:
	smlabb	r2, r0, r4, r6
	add.w	r3, r7, r2, lsl #1
	smlabb	r0, r1, r4, r0
	add.w	r2, r7, r0, lsl #1
	smlabb	r0, r5, r4, r1
.L080160d6:
	add.w	r1, r7, r0, lsl #1
	smlabb	r0, r6, r4, r5
	add.w	r0, r7, r0, lsl #1
	bl	rotate_four_halfwords
	.inst.n	0x1c6d			@ adds r5, r5, #1
	sxth	r5, r5
.L080160ea:
	cmp.w	r5, r8, asr #1
	blt.n	.L0801609a
	.inst.n	0x1c76			@ adds r6, r6, #1
	sxth	r6, r6
.L080160f4:
	cmp.w	r6, r9, asr #1
	blt.n	.L08016090
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08016100 - draws two-point lines for each record of the list at object +
@ 0x30 (no return value).
@   r0 = object (r5), r1 = context (r6)
@ Reached only by the b.w at 0x0801d46e. [sp+0x98] = object + 0x30 (a list); the
@ function returns at once when fn_08012690(object + 0x30) is non-zero, and
@ calls rect_intersect(sp+0x104, word [context+8], object + 0x14), returning
@ when that gives 0. r10 = word [context+8]; word [context+8] = sp+0x104 (the
@ intersection; restored from r10 when the loop ends). Calls fn_0801e8d2(sp+0xf0),
@ fn_080250b6(object, 0x70000, sp+0xf0) and fn_0801f344(sp+0xb0); byte [sp+0xb3] =
@ byte [sp+0xf8]; halfword [sp+0xb0] = 0x7fff. r7 = fn_08024d2c(object, 0x70000)
@ divided by 2 toward zero (add of the sign bit, asr #1); r11 = the same for a
@ second call of fn_08024d2c(object, 0x70000); fn_08023a0c(sp, context) is called;
@ stack words [sp+4] = literal 0x08050f14, [sp+8] = 5, [sp+0x10] = sp+0x60,
@ [sp+0x18] = sp+0xa4, [sp+0x34] = 0x70000.
@ r4 = get_word_8_or_zero(object + 0x30); the loop at 0x08016198 runs while r4 is
@ non-zero, with r4 = read_word_at_base_plus_offset(object + 0x30, r4) after each
@ pass (0x08016306).
@ Per record r4: copy_bytes_08022ce0 copies 10 bytes sp+0xf0 to sp+0xa4 and 0x38
@ bytes sp+0xb0 to sp+0x60; halfword [sp+0xa4] = halfword [sp+0x64] = halfword
@ [r4+6]; word [sp+0x24] = sp+0x48, word [sp+0x28] = sp+0xfc.
@ Point (r0, r1): bit 0 of byte [r4+0xd] set gives the signed halfwords [r4+0],
@ [r4+2]; clear: a signed halfword [r4+4] equal to 0x7fff skips the record
@ (0x080161da, goes to 0x080162fe), otherwise fn_0801d478(object, word [r4+8],
@ halfword [r4+4], sp+0xe8) and the point is the signed halfwords [sp+0xe8],
@ [sp+0xea]. r8 = sxth(r0 + halfword [object+0x14]), r9 = sxth(r1 + halfword
@ [object+0x16]).
@ When r7 and r11 are both non-zero: word [sp+0x100] = 1 and the halfwords at
@ sp+0x9c.. = (r8 - r7, r9 - r11, r8 + r7, r9 + r11), pointer sp+0x9c stored at
@ [sp+0xc]; otherwise word [sp+0x100] = 0 and [sp+0xc] = 0.
@ Bits 0 and 1 of byte [r4+0xc] (0x0801623a: lsls #30 non-zero): first point
@ (x0, r9) with x0 = signed halfword [object+0x14] when bit 0 is set else r8,
@ second point (x1, r9) with x1 = signed halfword [object+0x18] when bit 1 is
@ set else r8, stored at sp+0x48 and sp+0xfc; then fn_080207f4(object, 0x1a, sp),
@ fn_0801e8b8(context, sp+0xa4, sp+0x48, sp+0xfc), fn_0801f31c(context, sp+0x60,
@ sp+0x9c) only when word [sp+0x100] is non-zero, and fn_080207f4(object, 0x1b,
@ sp).
@ Bits 2 and 3 of byte [r4+0xc] (tst #12 at 0x0801629c): first point (r8, y0) with
@ y0 = signed halfword [object+0x16] when bit 2 is set else r9, second point (r8,
@ y1) with y1 = signed halfword [object+0x1a] when bit 3 is set else r9, then the
@ same four calls (0x1a, fn_0801e8b8, optional fn_0801f31c, 0x1b).
@ Next record: r4 = read_word_at_base_plus_offset(object + 0x30, r4) (0x080162fe);
@ after the last record restores word [context+8] = r10 and returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_08016100,"ax",%progbits
	.p2align 2
	.global fn_08016100
	.thumb_func
	.type fn_08016100, %function
fn_08016100:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x10c
	mov	r5, r0			@ r5 = object
	adds	r0, #0x30
	mov	r6, r1			@ r6 = context
	str	r0, [sp, #0x98]		@ object + 0x30
	bl	fn_08012690
	cmp	r0, #0
	bne.n	.L08016212
	add.w	r2, r5, #0x14
	add	r0, sp, #0x104
	ldr	r1, [r6, #8]
	bl	rect_intersect
	cmp	r0, #0
	beq.n	.L08016212
	add	r0, sp, #0x104
	ldr.w	r10, [r6, #8]		@ old clip pointer
	str	r0, [r6, #8]
	add	r0, sp, #0xf0
	bl	fn_0801e8d2
	mov.w	r4, #0x70000
	add	r2, sp, #0xf0
	mov	r1, r4
	mov	r0, r5
	bl	fn_080250b6
	add	r0, sp, #0xb0
	bl	fn_0801f344
	ldrb.w	r0, [sp, #0xf8]
	strb.w	r0, [sp, #0xb3]
	movw	r0, #0x7fff
	strh.w	r0, [sp, #0xb0]
	mov	r1, r4
	mov	r0, r5
	bl	fn_08024d2c
	add.w	r0, r0, r0, lsr #31
	asrs	r7, r0, #1		@ r7 = first result / 2 toward zero
	mov	r1, r4
	mov	r0, r5
	bl	fn_08024d2c
	add.w	r0, r0, r0, lsr #31
	asr.w	r11, r0, #1		@ r11 = second result / 2 toward zero
	mov	r1, r6
	mov	r0, sp
	bl	fn_08023a0c
	add	r0, sp, #0xa4
	str	r0, [sp, #0x18]
	add	r0, sp, #0x60
	str	r0, [sp, #0x10]
	ldr	r0, .L08016318
	str	r0, [sp, #4]
	movs	r0, #5
	str	r4, [sp, #0x34]
	str	r0, [sp, #8]
	ldr	r0, [sp, #0x98]
	bl	get_word_8_or_zero
	b.n	.L08016306
.L08016198:
	movs	r2, #0xa
	add	r1, sp, #0xf0
	add	r0, sp, #0xa4
	bl	copy_bytes_08022ce0
	movs	r2, #0x38
	add	r1, sp, #0xb0
	add	r0, sp, #0x60
	bl	copy_bytes_08022ce0
	ldrh	r0, [r4, #6]
	strh.w	r0, [sp, #0xa4]
	ldrh	r0, [r4, #6]
	strh.w	r0, [sp, #0x64]
	add	r0, sp, #0x48
	str	r0, [sp, #0x24]
	add	r0, sp, #0xfc
	str	r0, [sp, #0x28]
	ldrb	r0, [r4, #0xd]
	lsls	r0, r0, #0x1f
	beq.n	.L080161d0
	ldrsh.w	r0, [r4]
	ldrsh.w	r1, [r4, #2]
	b.n	.L080161f0
.L080161d0:
	ldrsh.w	r1, [r4, #4]
	sub.w	r0, r1, #0x7f00
	subs	r0, #0xff		@ zero when the halfword is 0x7fff
	beq.n	.L080162c8
	ldrh	r2, [r4, #4]
	add	r3, sp, #0xe8
	mov	r0, r5
	ldr	r1, [r4, #8]
	bl	fn_0801d478
	ldrsh.w	r0, [sp, #0xe8]
	ldrsh.w	r1, [sp, #0xea]
.L080161f0:
	ldrh	r2, [r5, #0x14]
	add	r0, r2
	sxth.w	r8, r0			@ r8 = x + halfword [object+0x14]
	ldrh	r0, [r5, #0x16]
	add	r0, r1
	sxth.w	r9, r0			@ r9 = y + halfword [object+0x16]
	cbz	r7, .L08016234
	cmp.w	r11, #0
	beq.n	.L08016234
	movs	r0, #1
	str	r0, [sp, #0x100]
	sub.w	r0, r8, r7
	b.n	.L08016214
.L08016212:
	b.n	.L08016310
.L08016214:
	strh.w	r0, [sp, #0x9c]
	add.w	r0, r8, r7
	strh.w	r0, [sp, #0xa0]
	sub.w	r0, r9, r11
	strh.w	r0, [sp, #0x9e]
	add.w	r0, r9, r11
	strh.w	r0, [sp, #0xa2]
	add	r0, sp, #0x9c
	b.n	.L08016238
.L08016234:
	movs	r0, #0
	str	r0, [sp, #0x100]
.L08016238:
	str	r0, [sp, #0xc]
	ldrb	r0, [r4, #0xc]
	lsls	r1, r0, #0x1e
	beq.n	.L0801629a
	lsls	r0, r0, #0x1f
	beq.n	.L0801624a
	ldrsh.w	r0, [r5, #0x14]
	b.n	.L0801624c
.L0801624a:
	mov	r0, r8
.L0801624c:
	strh.w	r0, [sp, #0x48]
	strh.w	r9, [sp, #0x4a]
	ldrb	r1, [r4, #0xc]
	mov	r0, r9
	lsls	r1, r1, #0x1e
	bpl.n	.L08016262
	ldrsh.w	r1, [r5, #0x18]
	b.n	.L08016264
.L08016262:
	mov	r1, r8
.L08016264:
	strh.w	r1, [sp, #0xfc]
	strh.w	r0, [sp, #0xfe]
	mov	r2, sp
	movs	r1, #0x1a
	mov	r0, r5
	bl	fn_080207f4
	add	r3, sp, #0xfc
	add	r2, sp, #0x48
	add	r1, sp, #0xa4
	mov	r0, r6
	bl	fn_0801e8b8
	ldr	r0, [sp, #0x100]
	cbz	r0, .L08016290
	add	r2, sp, #0x9c
	add	r1, sp, #0x60
	mov	r0, r6
	bl	fn_0801f31c
.L08016290:
	mov	r2, sp
	movs	r1, #0x1b
	mov	r0, r5
	bl	fn_080207f4
.L0801629a:
	ldrb	r1, [r4, #0xc]
	tst.w	r1, #0xc
	beq.n	.L080162fe
	mov	r0, r8
	strh.w	r8, [sp, #0x48]
	lsls	r1, r1, #0x1d
	bpl.n	.L080162b2
	ldrsh.w	r1, [r5, #0x16]
	b.n	.L080162b4
.L080162b2:
	mov	r1, r9
.L080162b4:
	strh.w	r1, [sp, #0x4a]
	strh.w	r0, [sp, #0xfc]
	ldrb	r0, [r4, #0xc]
	lsls	r0, r0, #0x1c
	bpl.n	.L080162ca
	ldrsh.w	r0, [r5, #0x1a]
	b.n	.L080162cc
.L080162c8:
	b.n	.L080162fe
.L080162ca:
	mov	r0, r9
.L080162cc:
	strh.w	r0, [sp, #0xfe]
	mov	r2, sp
	movs	r1, #0x1a
	mov	r0, r5
	bl	fn_080207f4
	add	r3, sp, #0xfc
	add	r2, sp, #0x48
	add	r1, sp, #0xa4
	mov	r0, r6
	bl	fn_0801e8b8
	ldr	r0, [sp, #0x100]
	cbz	r0, .L080162f4
	add	r2, sp, #0x9c
	add	r1, sp, #0x60
	mov	r0, r6
	bl	fn_0801f31c
.L080162f4:
	mov	r2, sp
	movs	r1, #0x1b
	mov	r0, r5
	bl	fn_080207f4
.L080162fe:
	mov	r1, r4
	ldr	r0, [sp, #0x98]
	bl	read_word_at_base_plus_offset
.L08016306:
	movs	r4, r0
	bne.w	.L08016198
	str.w	r10, [r6, #8]		@ restore the clip pointer
.L08016310:
	add	sp, #0x10c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short	0x0000			@ padding
.L08016318:
	.word	d_08050f14		@ literal read by 0x08016186 (0x08050f14)

