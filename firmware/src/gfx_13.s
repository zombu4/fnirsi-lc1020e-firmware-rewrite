@ gfx_13.s - graphics module part 13: banded draw routine, draw-operation table builder and its handlers
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0801f980 - draw one pixel block described by a descriptor into the
@ object's clip rectangle, either directly or in horizontal bands.
@ Parameters: r0 = object (word +8 points to the clip rectangle {x0,y0,x1,y1}),
@ r1 = descriptor (halfwords +0 and +2, halfword +8 = colour, byte +0xa =
@ weight, bytes +0xb and +0xc), r2 = rectangle pointer {x0,y0,x1,y1} (four
@ halfwords), r3 = pixel data pointer (pushed, read back at [sp+0x88]),
@ stack word 0 (loaded into r9 at 0x0801f98e) = mode, compared with 4, 14, 20.
@ No return value.
@ Setup: copies the clip rectangle into a local rectangle at sp+0x6c with
@ copy_rect_0801cffa; flag F1 = fn_0801ecd0(that copy), kept at sp+0x60; flag
@ F2 (sp+0x5c) = 0 only when halfword descriptor+0 == 0 and halfword
@ descriptor+2 == 0x100, else 1; clears a 0x1c-byte record at sp+0x30 with
@ clear_bytes; record byte +0x18 = descriptor byte +0xb, record byte +0x19 =
@ descriptor byte +0xc & 0xf, record word +0 = address of the local rectangle
@ at sp+0x18.
@ Direct path (F1 == 0 and F2 == 0), by mode: mode 4 with descriptor byte
@ +0xa == 0 stores r2 at record +0 and the pixel pointer at record +4; mode 14
@ intersects r2 with the clip rectangle using rect_intersect (returns when the
@ result is empty) and stores record +0 = r2, +4 = 0, halfword +8 = descriptor
@ halfword +8, +0xc = pixel pointer, byte +0x10 = 2, +0x14 = r2; mode 20 with
@ descriptor byte +0xa == 0 stores +0 = r2, +4 = pixel pointer, +0xc = pixel
@ pointer + width*2*height (width and height = x1-x0+1 and y1-y0+1 of r2 as
@ signed 16 bit), byte +0x10 = 2, +0x14 = r2; each of these ends with one call
@ fn_0801f730(object, record) and a return; any other mode, or mode 4 or 20
@ with a nonzero weight byte, takes the banded path.
@ Banded path (.L0801fa36): local rectangle sp+0x18 = clip rectangle; width W
@ and height H of r2 (signed 16 bit, stored at sp+0x4c and sp+0x50); clip
@ width and clip height; limit L = fn_0801dcfc(return_word_200004b8()); band
@ height = clip height when the area rect_area(clip) is not above L, else L /
@ clip width (udiv); allocates a halfword buffer of band*width*2 bytes and a
@ byte buffer of band*width bytes with fn_08022bac (record +4 = halfword
@ buffer, +0xc and sp+0x24 = byte buffer, +0x14 = address of the local
@ rectangle, byte +0x10 = 2); the band rectangle is rows y0 .. y0+band-1; for
@ mode 4 with F2 == 0 and descriptor halfwords as above byte +0x10 is set to 1
@ (0x0801fb1a), every other case to 2.
@ Loop while the band y0 (signed halfword sp+0x1a) <= the clip y1 (sp+0x58):
@ copies the band rectangle to sp+0x74 and moves it by (-r2.x0, -r2.y0) with
@ rect_move; F2 == 0 calls fn_08014bd4(rect, pixel pointer, W, H, W,
@ descriptor, mode, halfword buffer, byte buffer) and F2 != 0 calls
@ call_slot_28_if_set(object, rect, pixel pointer, W, H, W, descriptor, mode,
@ halfword buffer, byte buffer).
@ When descriptor byte +0xa > 2 (cmp #2, bls at 0x0801fb80) blends every
@ halfword of the band buffer with colour halfword descriptor+8 and w = byte
@ +0xa: each channel (red bits 15..11, green bits 10..5, blue bits 4..0)
@ becomes ((colour_channel*w + pixel_channel*(255-w)) * 0x8081) >> 23 masked
@ to 5, 6 and 5 bits.
@ When F1 != 0: for each row y from the band y0 to the band y1 (signed) calls
@ fn_0801ec54(row pointer in the byte buffer, x0, y, clip width); result 0
@ clears the clip-width bytes of that row with clear_bytes and sets record
@ byte +0x10 = 2, result 2 sets byte +0x10 = 2, any other result changes
@ nothing; the row pointer advances by the clip width.
@ Per band calls fn_0801f730(object, record); then y0 = y1 + 1 and y1 = y0 +
@ band - 1 limited to the clip y1; after the loop frees the byte buffer
@ (sp+0x24) and the halfword buffer (sp+0x54) with fn_08022c44 and returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801f980,"ax",%progbits
	.p2align 2
	.global fn_0801f980
	.thumb_func
	.type fn_0801f980, %function
fn_0801f980:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x7c
	mov	r5, r1
	mov	r10, r0
	ldr	r1, [r0, #0x8]
	mov	r4, r2
	ldr.w	r9, [sp, #0xb0]
	add	r0, sp, #0x6c
	bl	copy_rect_0801cffa
	add	r0, sp, #0x6c
	bl	fn_0801ecd0
	str	r0, [sp, #0x60]		@ F1
	ldrh	r0, [r5, #0x0]
	cbnz	r0, .L0801f9ac
	ldrh	r0, [r5, #0x2]
	cmp.w	r0, #0x100
	beq.n	.L0801f9b0
.L0801f9ac:
	movs	r0, #0x1
	b.n	.L0801f9b2
.L0801f9b0:
	movs	r0, #0x0
.L0801f9b2:
	str	r0, [sp, #0x5c]		@ F2
	movs	r1, #0x1c
	add	r0, sp, #0x30
	bl	clear_bytes
	ldrb	r0, [r5, #0xb]
	strb.w	r0, [sp, #0x48]
	ldrb	r0, [r5, #0xc]
	mov.w	r6, #0x0
	and.w	r0, r0, #0xf
	strb.w	r0, [sp, #0x49]
	add	r0, sp, #0x18
	str	r0, [sp, #0x30]
	ldrd	r0, r1, [sp, #0x5c]	@ F2 and F1 (flag at sp+0x60)
	orrs	r1, r0
	bne.n	.L0801fa36
	cmp.w	r9, #0x4
	beq.n	.L0801f9f0
	cmp.w	r9, #0xe
	beq.n	.L0801f9fe
	cmp.w	r9, #0x14
	beq.n	.L0801fa32
	b.n	.L0801fa36
.L0801f9f0:
	ldrb	r0, [r5, #0xa]
	cbnz	r0, .L0801fa36
	ldr	r0, [sp, #0x88]
	add	r1, sp, #0x30
	strd	r4, r0, [sp, #0x30]
	b.n	.L0801fa26
.L0801f9fe:
	mov	r1, r4
	mov	r0, sp
	ldr.w	r2, [r10, #0x8]
	bl	rect_intersect
	cmp	r0, #0x0
	beq.n	.L0801fa2c
	ldr	r0, [sp, #0x88]
	str	r6, [sp, #0x34]
	str	r4, [sp, #0x44]
	str	r0, [sp, #0x3c]
	ldrh	r0, [r5, #0x8]
	strh.w	r0, [sp, #0x38]
	movs	r0, #0x2
	strb.w	r0, [sp, #0x40]
	str	r4, [sp, #0x30]
	b.n	.L0801fb06
.L0801fa26:
	mov	r0, r10
	bl	fn_0801f730
.L0801fa2c:
	add	sp, #0x8c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801fa32:
	ldrb	r0, [r5, #0xa]
	cbz	r0, .L0801fab4
.L0801fa36:
	ldr.w	r0, [r10, #0x8]
	ldrh	r2, [r0, #0x0]
	strh.w	r2, [sp, #0x18]
	ldrh	r1, [r0, #0x4]
	strh.w	r1, [sp, #0x1c]
	ldr.w	r0, [r10, #0x8]
	ldrh	r0, [r0, #0x2]
	strh.w	r0, [sp, #0x1a]
	ldr.w	r3, [r10, #0x8]
	ldrh	r3, [r3, #0x6]
	strh.w	r3, [sp, #0x1e]
	ldrh	r6, [r4, #0x4]
	ldrh	r7, [r4, #0x0]
	subs	r0, r3, r0
	subs	r6, r6, r7
	.inst.n	0x1c76		@ adds r6, r6, #1
	sxth	r6, r6
	str	r6, [sp, #0x4c]		@ W
	ldrh	r6, [r4, #0x6]
	ldrh	r7, [r4, #0x2]
	.inst.n	0x1c40		@ adds r0, r0, #1
	subs	r6, r6, r7
	sxth	r7, r0
	.inst.n	0x1c76		@ adds r6, r6, #1
	subs	r0, r1, r2
	sxth	r6, r6
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth.w	r11, r0
	str	r6, [sp, #0x50]		@ H
	bl	return_word_200004b8
	bl	fn_0801dcfc
	mov	r8, r0
	add	r0, sp, #0x18
	bl	rect_area
	mov	r6, r11
	cmp	r0, r8
	bls.n	.L0801fa9a
	udiv	r7, r8, r11
.L0801fa9a:
	muls	r6, r7, r6
	lsls	r0, r6, #0x1
	bl	fn_08022bac
	str	r0, [sp, #0x54]		@ halfword buffer
	mov	r0, r6
	bl	fn_08022bac
	str	r0, [sp, #0x24]		@ byte buffer
	str	r0, [sp, #0x3c]
	add	r0, sp, #0x18
	str	r0, [sp, #0x44]
	b.n	.L0801fab6
.L0801fab4:
	b.n	.L0801fadc
.L0801fab6:
	movs	r0, #0x2
	strb.w	r0, [sp, #0x40]
	ldr	r0, [sp, #0x54]
	str	r0, [sp, #0x34]
	ldrsh.w	r0, [sp, #0x1e]
	str	r0, [sp, #0x58]		@ clip y1
	.inst.n	0x1e7f		@ subs r7, r7, #1
	ldrh.w	r0, [sp, #0x1a]
	str	r7, [sp, #0x68]		@ band height - 1
	add	r0, r7
	strh.w	r0, [sp, #0x1e]
	cmp.w	r9, #0x4
	bne.n	.L0801fb16
	b.n	.L0801fb0a
.L0801fadc:
	ldrh	r0, [r4, #0x4]
	ldrh	r1, [r4, #0x0]
	subs	r0, r0, r1
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r2, r0
	ldrh	r0, [r4, #0x6]
	ldrh	r1, [r4, #0x2]
	str	r4, [sp, #0x30]
	subs	r0, r0, r1
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r1, r0
	ldr	r0, [sp, #0x88]
	lsls	r2, r2, #0x1
	str	r0, [sp, #0x34]
	mla	r0, r2, r1, r0
	str	r0, [sp, #0x3c]
	movs	r0, #0x2
	str	r4, [sp, #0x44]
	strb.w	r0, [sp, #0x40]
.L0801fb06:
	add	r1, sp, #0x30
	b.n	.L0801fa26
.L0801fb0a:
	ldrh	r0, [r5, #0x0]
	cbnz	r0, .L0801fb16
	ldrh	r0, [r5, #0x2]
	cmp.w	r0, #0x100
	beq.n	.L0801fb1a
.L0801fb16:
	movs	r0, #0x2
	b.n	.L0801fb1c
.L0801fb1a:
	movs	r0, #0x1
.L0801fb1c:
	strb.w	r0, [sp, #0x40]
	b.n	.L0801fca0
.L0801fb22:
	add	r1, sp, #0x18
	add	r0, sp, #0x74
	bl	copy_rect_0801cffa
	ldrh	r0, [r4, #0x2]
	rsbs	r0, r0, #0
	sxth	r2, r0
	ldrh	r0, [r4, #0x0]
	rsbs	r0, r0, #0
	sxth	r1, r0
	add	r0, sp, #0x74
	bl	rect_move
	ldr	r0, [sp, #0x5c]
	ldr	r1, [sp, #0x54]
	cmp	r0, #0x0
	ldr	r0, [sp, #0x24]
	beq.n	.L0801fb64
	strd	r1, r0, [sp, #0x10]
	strd	r5, r9, [sp, #0x8]
	ldrd	r1, r0, [sp, #0x4c]
	strd	r0, r1, [sp, #0x0]
	add	r1, sp, #0x74
	mov	r0, r10
	ldr	r3, [sp, #0x4c]
	ldr	r2, [sp, #0x88]
	bl	call_slot_28_if_set
	b.n	.L0801fb7c
.L0801fb64:
	strd	r1, r0, [sp, #0xc]
	strd	r5, r9, [sp, #0x4]
	ldr	r0, [sp, #0x4c]
	str	r0, [sp, #0x0]
	ldrd	r2, r3, [sp, #0x4c]
	add	r0, sp, #0x74
	ldr	r1, [sp, #0x88]
	bl	fn_08014bd4
.L0801fb7c:
	ldrb	r0, [r5, #0xa]
	cmp	r0, #0x2
	bls.n	.L0801fc3a
	@ blend the band buffer with the descriptor colour, weight w = byte +0xa
	ldrh	r2, [r5, #0x8]
	uxtb	r1, r0
	uxth	r2, r2
	lsrs	r7, r2, #0xb
	smulbb	r7, r7, r1
	bfi	r0, r7, #0x0, #0x10
	ubfx	r7, r2, #0x5, #0x6
	smulbb	r7, r7, r1
	bfi	r0, r7, #0x10, #0x10
	and.w	r2, r2, #0x1f
	smulbb	r2, r2, r1
	bfi	r3, r2, #0x0, #0x10
	rsb.w	r1, r1, #0xff
	strd	r1, r3, [sp, #0x10]
	movs	r2, #0x0
	b.n	.L0801fc36
.L0801fbb6:
	ldr	r1, [sp, #0x54]
	ldr	r3, [sp, #0x10]
	add.w	lr, r1, r2, lsl #0x1
	ldrh.w	r1, [lr, #0x0]
	strh.w	r1, [sp, #0x28]
	ldrh.w	r7, [sp, #0x28]
	uxth	r1, r0
	lsr.w	r12, r7, #0xb
	smlabb	r1, r12, r3, r1
	add.w	r12, r1, r1, lsl #0x7
	add.w	r1, r12, r1, lsl #0xf
	ubfx	r12, r1, #0x17, #0x5
	ldrh.w	r1, [sp, #0x2c]
	ubfx	r8, r7, #0x5, #0x6
	bfi	r1, r12, #0xb, #0x5
	lsr.w	r12, r0, #0x10
	smlabb	r12, r8, r3, r12
	add.w	r8, r12, r12, lsl #0x7
	add.w	r12, r8, r12, lsl #0xf
	ubfx	r12, r12, #0x17, #0x6
	bfi	r1, r12, #0x5, #0x6
	ldr.w	r12, [sp, #0x14]
	and.w	r7, r7, #0x1f
	uxth.w	r12, r12
	smlabb	r3, r7, r3, r12
	add.w	r7, r3, r3, lsl #0x7
	add.w	r3, r7, r3, lsl #0xf
	ubfx	r3, r3, #0x17, #0x5
	bfi	r1, r3, #0x0, #0x5
	strh.w	r1, [sp, #0x2c]
	uxth	r1, r1
	str	r1, [sp, #0x4]
	ldrh.w	r3, [sp, #0x4]
	strh.w	r3, [lr, #0x0]
	.inst.n	0x1c52		@ adds r2, r2, #1
.L0801fc36:
	cmp	r2, r6
	bcc.n	.L0801fbb6
.L0801fc3a:
	ldr	r0, [sp, #0x60]
	cbz	r0, .L0801fc7a
	ldrsh.w	r7, [sp, #0x1a]
	ldr.w	r8, [sp, #0x24]
	b.n	.L0801fc72
.L0801fc48:
	ldrsh.w	r1, [sp, #0x18]
	mov	r3, r11
	mov	r2, r7
	mov	r0, r8
	bl	fn_0801ec54
	cbz	r0, .L0801fc5e
	cmp	r0, #0x2
	beq.n	.L0801fc66
	b.n	.L0801fc6c
.L0801fc5e:
	mov	r1, r11
	mov	r0, r8
	bl	clear_bytes
.L0801fc66:
	movs	r0, #0x2
	strb.w	r0, [sp, #0x40]
.L0801fc6c:
	.inst.n	0x1c7f		@ adds r7, r7, #1
	add	r8, r11
	sxth	r7, r7
.L0801fc72:
	ldrsh.w	r0, [sp, #0x1e]
	cmp	r0, r7
	bge.n	.L0801fc48
.L0801fc7a:
	add	r1, sp, #0x30
	mov	r0, r10
	bl	fn_0801f730
	ldrh.w	r1, [sp, #0x1e]
	.inst.n	0x1c49		@ adds r1, r1, #1
	strh.w	r1, [sp, #0x1a]
	ldr	r0, [sp, #0x68]
	add	r0, r1
	sxth	r0, r0
	strh.w	r0, [sp, #0x1e]
	ldr	r1, [sp, #0x58]
	cmp	r0, r1
	ble.n	.L0801fca0
	strh.w	r1, [sp, #0x1e]
.L0801fca0:
	ldrsh.w	r1, [sp, #0x1a]
	ldr	r0, [sp, #0x58]
	cmp	r1, r0
	ble.w	.L0801fb22
	ldr	r0, [sp, #0x24]
	bl	fn_08022c44
	ldr	r0, [sp, #0x54]
	bl	fn_08022c44
	b.n	.L0801fa2c
	.short	0x0000		@ padding

@ ----------------------------------------------------------------------------
@ fn_0801fcbc - fill a 0x54-byte table of draw-operation handler addresses.
@ Parameters: r1 = table pointer (r0 unused). No return value.
@ Clears 0x54 bytes at the table with clear_bytes, then stores 15 code
@ addresses at offsets 0x10 (fn_0801f3b8+1), 0xc (call_five_routines_in_sequence),
@ 0x2c (fn_0801f716), 0x1c (fn_0801ff16), 0x14 (fn_0801f980), 0x20
@ (fn_0802002c), 0x24 (fn_080201d0), 0x28 (fn_08020488), 0x30
@ (return_only_08020724), 0x34 (fn_0801f91a), 0x38 (fn_0801fe1a), 0x3c
@ (fn_0801fd48), 0x40 (fn_0801fd94), 0x44 (fn_0801ff10) and 0x50 (fn_0801f75c),
@ and the constant 0x2c at offset 0x48. The stored addresses have bit 0 set
@ (Thumb function pointers).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801fcbc,"ax",%progbits
	.p2align 2
	.global fn_0801fcbc
	.thumb_func
	.type fn_0801fcbc, %function
fn_0801fcbc:
	push	{r4, lr}
	mov	r4, r1
	movs	r1, #0x54
	mov	r0, r4
	bl	clear_bytes
	ldr	r0, .L0801fd0c
	str	r0, [r4, #0x10]
	ldr	r0, .L0801fd10
	str	r0, [r4, #0xc]
	ldr	r0, .L0801fd14
	str	r0, [r4, #0x2c]
	ldr	r0, .L0801fd18
	str	r0, [r4, #0x1c]
	ldr	r0, .L0801fd1c
	str	r0, [r4, #0x14]
	ldr	r0, .L0801fd20
	str	r0, [r4, #0x20]
	ldr	r0, .L0801fd24
	str	r0, [r4, #0x24]
	ldr	r0, .L0801fd28
	str	r0, [r4, #0x28]
	ldr	r0, .L0801fd2c
	str	r0, [r4, #0x30]
	ldr	r0, .L0801fd30
	str	r0, [r4, #0x34]
	ldr	r0, .L0801fd34
	str	r0, [r4, #0x38]
	ldr	r0, .L0801fd38
	str	r0, [r4, #0x3c]
	ldr	r0, .L0801fd3c
	str	r0, [r4, #0x40]
	ldr	r0, .L0801fd40
	str	r0, [r4, #0x44]
	ldr	r0, .L0801fd44
	str	r0, [r4, #0x50]
	movs	r0, #0x2c
	str	r0, [r4, #0x48]
	pop	{r4, pc}
	.short	0x0000		@ padding
.L0801fd0c:
	.word	fn_0801f3b8		@ stored at table +0x10
.L0801fd10:
	.word	call_five_routines_in_sequence	@ stored at table +0xc
.L0801fd14:
	.word	fn_0801f716		@ stored at table +0x2c
.L0801fd18:
	.word	fn_0801ff16		@ stored at table +0x1c
.L0801fd1c:
	.word	fn_0801f980		@ stored at table +0x14
.L0801fd20:
	.word	fn_0802002c		@ stored at table +0x20
.L0801fd24:
	.word	fn_080201d0		@ stored at table +0x24
.L0801fd28:
	.word	fn_08020488		@ stored at table +0x28
.L0801fd2c:
	.word	return_only_08020724	@ stored at table +0x30
.L0801fd30:
	.word	fn_0801f91a		@ stored at table +0x34
.L0801fd34:
	.word	fn_0801fe1a		@ stored at table +0x38
.L0801fd38:
	.word	fn_0801fd48		@ stored at table +0x3c
.L0801fd3c:
	.word	fn_0801fd94		@ stored at table +0x40
.L0801fd40:
	.word	fn_0801ff10		@ stored at table +0x44
.L0801fd44:
	.word	fn_0801f75c		@ stored at table +0x50

@ ----------------------------------------------------------------------------
@ fn_0801fd48 - set or clear the buffer-active state of an object.
@ Parameters: r0 = 3-word output, r1 = object, r2 = flags (bit 0 tested).
@ No return value. Calls return_word_200004b8 for a pointer p.
@ Bit 0 clear: clears bit 31 of object word +0x28 and clears bit 6 (0x40) of
@ the word at +0x10 of *p.
@ Bit 0 set: clears the buffer pointed to by object word +0x14 with
@ clear_bytes, length = word +0x28 with bit 31 cleared, then sets bit 31 of
@ word +0x28 and sets bit 6 of the word at *p+0x10.
@ Stores output[0] = object word +0x14, output[1] = output[2] = object+8.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801fd48,"ax",%progbits
	.p2align 2
	.global fn_0801fd48
	.thumb_func
	.type fn_0801fd48, %function
fn_0801fd48:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r7, r2
	mov	r4, r1
	mov	r6, r0
	bl	return_word_200004b8
	mov	r5, r0
	lsls	r0, r7, #0x1f		@ bit 0 of the flags to the Z flag
	ldr	r0, [r4, #0x28]
	bic.w	r1, r0, #0x80000000
	beq.n	.L0801fd7a
	ldr	r0, [r4, #0x14]
	bl	clear_bytes
	ldr	r0, [r4, #0x28]
	orr.w	r1, r0, #0x80000000
	str	r1, [r4, #0x28]
	ldr	r0, [r5, #0x0]
	ldr	r1, [r0, #0x10]
	orr.w	r1, r1, #0x40
	b.n	.L0801fd84
.L0801fd7a:
	str	r1, [r4, #0x28]
	ldr	r0, [r5, #0x0]
	ldr	r1, [r0, #0x10]
	bic.w	r1, r1, #0x40
.L0801fd84:
	str	r1, [r0, #0x10]
	ldr	r0, [r4, #0x14]
	adds	r4, #0x8
	strd	r0, r4, [r6, #0x0]
	str	r4, [r6, #0x8]
	pop.w	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_0801fd94 - issue a command built from an object and a 3-word state.
@ Parameters: r0 = 3-word state, r1 = object, r2 = value. No return value.
@ Builds a command word at sp: the word loaded from sp with bits 7..5 cleared,
@ field bits 20..10 = (width of the rectangle at state word 1) + 1 (width =
@ halfword +4 - halfword +0), field bits 31..21 = (height) + 1 (halfword +6 -
@ halfword +2), field bits 4..0 = 5 when object word +0x28 is negative, else 4.
@ Loads state words 0..2 from object words +0x20, +0x1c, +0x18. Calls
@ return_word_200004b8 and writes bit 6 of the word at *ptr+0x10 from bit 0 of
@ object byte +0x24. Then calls fn_0801e1f0(state, value, object+8, command),
@ call_slot_30_if_set(state) and return_only_08021166(command).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801fd94,"ax",%progbits
	.global fn_0801fd94
	.thumb_func
	.type fn_0801fd94, %function
fn_0801fd94:
	push	{r1, r2, r3, r4, r5, r6, r7, lr}
	mov	r5, r0
	ldr	r0, [r0, #0x0]
	str	r0, [sp, #0x8]
	ldr	r0, [sp, #0x0]
	mov	r4, r1
	bic.w	r0, r0, #0xe0
	str	r0, [sp, #0x0]
	ldr	r0, [r5, #0x4]
	mov	r6, r2
	ldrh	r1, [r0, #0x4]
	ldrh	r0, [r0, #0x0]
	subs	r0, r1, r0
	ldr	r1, [sp, #0x0]
	.inst.n	0x1c40		@ adds r0, r0, #1
	bfi	r1, r0, #0xa, #0xb
	str	r1, [sp, #0x0]
	ldr	r0, [r5, #0x4]
	ldrh	r1, [r0, #0x6]
	ldrh	r0, [r0, #0x2]
	subs	r0, r1, r0
	ldr	r1, [sp, #0x0]
	.inst.n	0x1c40		@ adds r0, r0, #1
	bfi	r1, r0, #0x15, #0xb
	str	r1, [sp, #0x0]
	ldr	r0, [r4, #0x28]
	cmp	r0, #0x0
	bge.n	.L0801fdd6
	movs	r1, #0x5
	b.n	.L0801fdd8
.L0801fdd6:
	movs	r1, #0x4
.L0801fdd8:
	ldr	r0, [sp, #0x0]
	bfi	r0, r1, #0x0, #0x5
	str	r0, [sp, #0x0]
	ldr	r0, [r4, #0x20]
	str	r0, [r5, #0x0]
	ldr	r0, [r4, #0x1c]
	str	r0, [r5, #0x4]
	ldr	r0, [r4, #0x18]
	str	r0, [r5, #0x8]
	bl	return_word_200004b8
	ldr	r0, [r0, #0x0]
	ldrb.w	r2, [r4, #0x24]
	mov	r3, sp
	ldr	r1, [r0, #0x10]
	bfi	r1, r2, #0x6, #0x1
	str	r1, [r0, #0x10]
	add.w	r2, r4, #0x8
	mov	r1, r6
	mov	r0, r5
	bl	fn_0801e1f0
	mov	r0, r5
	bl	call_slot_30_if_set
	mov	r0, sp
	bl	return_only_08021166
	pop	{r1, r2, r3, r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_0801fe1a - allocate the buffer of an object and fill a 3-word output.
@ Parameters: r0 = 3-word output, r1 = object (words 0..1 rectangle, word
@ +0x28 flags/size, word +0x14 buffer), r2 = flags. Returns the object, or 0.
@ Bit 0 of the flags set: returns 0.
@ Bit 1 set: size word +0x28 = (old bit 31) + 0x6000; when its low 31 bits
@ exceed 2 * rect_area(object) they are replaced by 2 * rect_area(object);
@ buffer +0x14 = fn_08022b50(low 31 bits of +0x28); on failure retries with
@ +0x28 = (old bit 31) + 0xc00; copies rectangle words 0..1 to +8 and +0xc,
@ stores halfword +0xe = halfword +2, halfword +0x10 = size / (width * 3) and
@ halfword +0x12 = (size / width) >> 1 with width = halfword +0xc - halfword
@ +8 + 1; returns 0 when both allocations fail; the output is not written.
@ Bit 1 clear: copies rectangle words 0..1 to +8 and +0xc, low 31 bits of
@ +0x28 = (rect_area(object) & 0x3fffffff) << 1, allocates with fn_08022b50
@ and clears the buffer with clear_bytes, bit 31 of +0x28 = bit 0 of the
@ flags (0 on this path), returns 0 when the allocation fails, sets output[0]
@ = buffer, output[1] = output[2] = object+8 and writes bit 6 of the word at
@ *(return_word_200004b8())+0x10 from bit 0 of the flags.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801fe1a,"ax",%progbits
	.global fn_0801fe1a
	.thumb_func
	.type fn_0801fe1a, %function
fn_0801fe1a:
	push	{r4, r5, r6, lr}
	mov	r6, r0
	mov	r5, r2
	mov	r4, r1
	lsls	r0, r2, #0x1f
	beq.n	.L0801fe2a
	movs	r0, #0x0
.L0801fe28:
	pop	{r4, r5, r6, pc}
.L0801fe2a:
	lsls	r0, r5, #0x1e
	bpl.n	.L0801feb6
	ldr	r0, [r4, #0x28]
	and.w	r0, r0, #0x80000000
	add.w	r0, r0, #0x6000
	str	r0, [r4, #0x28]
	mov	r0, r4
	bl	rect_area
	ldr	r1, [r4, #0x28]
	lsls	r0, r0, #0x1
	bic.w	r2, r1, #0x80000000
	cmp	r2, r0
	bls.n	.L0801fe52
	bfi	r1, r0, #0x0, #0x1f
	str	r1, [r4, #0x28]
.L0801fe52:
	ldr	r0, [r4, #0x28]
	bic.w	r0, r0, #0x80000000
	bl	fn_08022b50
	mov	r1, r4
	str	r0, [r4, #0x14]
	cbnz	r0, .L0801fe7e
	ldr	r0, [r4, #0x28]
	and.w	r0, r0, #0x80000000
	add.w	r0, r0, #0xc00
	str	r0, [r4, #0x28]
	bic.w	r0, r0, #0x80000000
	bl	fn_08022b50
	mov	r1, r4
	str	r0, [r4, #0x14]
	cmp	r0, #0x0
	beq.n	.L0801fe28
.L0801fe7e:
	mov	r0, r1
	ldrd	r1, r2, [r0, #0x0]
	str	r1, [r0, #0x8]
	str	r2, [r4, #0xc]
	ldrh	r1, [r4, #0x2]
	strh	r1, [r4, #0xe]
	ldrh	r1, [r4, #0xc]
	ldrh	r0, [r4, #0x8]
	subs	r0, r1, r0
	.inst.n	0x1c40		@ adds r0, r0, #1
	ldr	r1, [r4, #0x28]
	sxth	r0, r0
	bic.w	r1, r1, #0x80000000
	add.w	r2, r0, r0, lsl #0x1
	sdiv	r1, r1, r2
	strh	r1, [r4, #0x10]
	ldr	r1, [r4, #0x28]
	bic.w	r1, r1, #0x80000000
	sdiv	r0, r1, r0
	asrs	r1, r0, #0x1
	strh	r1, [r4, #0x12]
	b.n	.L0801ff0c
.L0801feb6:
	mov	r0, r1
	ldrd	r1, r2, [r0, #0x0]
	str	r1, [r0, #0x8]
	str	r2, [r4, #0xc]
	bl	rect_area
	lsls	r1, r0, #0x1
	ldr	r0, [r4, #0x28]
	bfi	r0, r1, #0x0, #0x1f
	str	r0, [r4, #0x28]
	bic.w	r0, r0, #0x80000000
	bl	fn_08022b50
	str	r0, [r4, #0x14]
	ldr	r1, [r4, #0x28]
	bic.w	r1, r1, #0x80000000
	bl	clear_bytes
	ldr	r0, [r4, #0x28]
	and.w	r5, r5, #0x1
	bfi	r0, r5, #0x1f, #0x1
	str	r0, [r4, #0x28]
	ldr	r0, [r4, #0x14]
	cmp	r0, #0x0
	beq.n	.L0801fe28
	str	r0, [r6, #0x0]
	add.w	r0, r4, #0x8
	str	r0, [r6, #0x4]
	str	r0, [r6, #0x8]
	bl	return_word_200004b8
	ldr	r0, [r0, #0x0]
	ldr	r1, [r0, #0x10]
	bfi	r1, r5, #0x6, #0x1
	str	r1, [r0, #0x10]
.L0801ff0c:
	mov	r0, r4
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_0801ff10 - tail call: pass object word +0x14 to fn_08022c68.
@ Parameters: r1 = object. No return value of its own.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ff10,"ax",%progbits
	.global fn_0801ff10
	.thumb_func
	.type fn_0801ff10, %function
fn_0801ff10:
	ldr	r0, [r1, #0x14]
	b.w	fn_08022c68

@ ----------------------------------------------------------------------------
@ fn_0801ff16 - draw one character cell or a glyph at a point.
@ Parameters: r0 = object (field +8 clip rectangle, field +0xc function
@ pointer), r1 = record (word 0 descriptor pointer, word +0xc), r2 = point
@ {x,y} shorts, r3 = character code. No return value.
@ Calls fn_080208c6(*record, &info, code, 0).
@ Result 0: for code > 0x1f, not 0xf8ff and not 0x200c builds a rectangle with
@ rect_set from the point plus the info offsets and size, fills a record with
@ fn_0801f344, sets bytes to 2, halfword 1 and word record[3], then calls the
@ function pointer at object+0xc with (object, record, rectangle).
@ Result nonzero: when width and height of info are both nonzero, computes the
@ position (x + info short, y flipped using the descriptor shorts at +8 and
@ +10), tests it against the clip rectangle at object+8, calls
@ fn_080208c2(info pointer, code) and when its result is nonzero and (byte
@ +0xc & 3) == 0 calls fn_080169ac(object, record, &pos, &info, result).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801ff16,"ax",%progbits
	.global fn_0801ff16
	.thumb_func
	.type fn_0801ff16, %function
fn_0801ff16:
	push	{r4, r5, r6, r7, lr}
	mov	r4, r3
	mov	r7, r0
	sub	sp, #0x5c
	mov	r5, r2
	mov	r6, r1
	ldr	r0, [r1, #0x0]
	movs	r3, #0x0
	mov	r2, r4
	add	r1, sp, #0x4
	bl	fn_080208c6
	cbz	r0, .L0801ffae
	ldrh.w	r2, [sp, #0xc]
	cmp	r2, #0x0
	beq.n	.L0801ffb8
	ldrh.w	r1, [sp, #0xa]
	cmp	r1, #0x0
	beq.n	.L0801ffb8
	ldrh	r0, [r5, #0x0]
	ldrh.w	r3, [sp, #0xe]
	add	r0, r3
	sxth	r0, r0
	strh.w	r0, [sp, #0x4c]
	ldr	r3, [r6, #0x0]
	ldrh	r5, [r5, #0x2]
	ldrh.w	r12, [r3, #0x8]
	ldrh	r3, [r3, #0xa]
	sub.w	r3, r12, r3
	add	r3, r5
	ldrh.w	r5, [sp, #0x10]
	subs	r3, r3, r2
	subs	r3, r3, r5
	sxth	r3, r3
	strh.w	r3, [sp, #0x4e]
	adds	r5, r0, r1
	ldr	r1, [r7, #0x8]
	ldrsh.w	r12, [r1, #0x0]
	cmp	r5, r12
	blt.n	.L0801ffb8
	ldrsh.w	r5, [r1, #0x4]
	cmp	r0, r5
	bgt.n	.L0801ffb8
	adds	r0, r3, r2
	ldrsh.w	r2, [r1, #0x2]
	cmp	r0, r2
	blt.n	.L0801ffb8
	ldrsh.w	r0, [r1, #0x6]
	cmp	r3, r0
	bgt.n	.L0801ffb8
	mov	r1, r4
	ldr	r0, [sp, #0x4]
	bl	fn_080208c2
	cmp	r0, #0x0
	beq.n	.L0801ffb8
	ldr	r1, [sp, #0x4]
	ldrb	r1, [r1, #0xc]
	lsls	r1, r1, #0x1e
	bne.n	.L0801ffb8
	add	r3, sp, #0x4
	add	r2, sp, #0x4c
	mov	r1, r6
	b.n	.L0801ffb0
.L0801ffae:
	b.n	.L0801ffbc
.L0801ffb0:
	str	r0, [sp, #0x0]
	mov	r0, r7
	bl	fn_080169ac
.L0801ffb8:
	add	sp, #0x5c
	pop	{r4, r5, r6, r7, pc}
.L0801ffbc:
	cmp	r4, #0x20
	bcc.n	.L0801ffb8
	sub.w	r0, r4, #0xf800
	subs	r0, #0xff
	beq.n	.L0801ffb8
	sub.w	r0, r4, #0x2000
	subs	r0, #0xc
	beq.n	.L0801ffb8
	ldrh	r0, [r5, #0x0]
	ldrh.w	r1, [sp, #0xe]
	ldrh.w	r2, [sp, #0x10]
	add	r0, r1
	sxth	r1, r0
	ldrh	r0, [r5, #0x2]
	add	r0, r2
	sxth	r2, r0
	ldrh.w	r0, [sp, #0xc]
	add	r0, r2
	sxth	r0, r0
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0xa]
	add	r0, r1
	sxth	r3, r0
	add	r0, sp, #0x50
	bl	rect_set
	add	r0, sp, #0x14
	bl	fn_0801f344
	movs	r0, #0x2
	strb.w	r0, [sp, #0x17]
	strb.w	r0, [sp, #0x3e]
	strb.w	r0, [sp, #0x4a]
	strb.w	r0, [sp, #0x2e]
	ldrh	r0, [r6, #0xc]
	strh.w	r0, [sp, #0x32]
	movs	r0, #0x1
	strh.w	r0, [sp, #0x34]
	ldr	r3, [r7, #0xc]
	add	r2, sp, #0x50
	add	r1, sp, #0x14
	mov	r0, r7
	blx	r3
	b.n	.L0801ffb8

@ ----------------------------------------------------------------------------
@ fn_0802002c - draw a line segment with a pen, with optional end caps.
@ Parameters: r0 = object (field +8 clip rectangle), r1 = pen (halfword +2
@ thickness, byte +8 > 2, byte +9 flags 0x4 and 0x8), r2 and r3 = end points
@ {x,y} shorts. No return value.
@ Does nothing unless thickness (halfword pen+2) != 0, byte +8 > 2 and the end
@ points differ. Builds the bounding box of both points widened by
@ thickness/2 at sp+0x44, clips it with rect_intersect against the clip
@ rectangle at object+8 (returns when empty), temporarily replaces field +8
@ with the box. Draws with fn_08016c6c when the y values are equal,
@ fn_0801713c when the x values are equal, else fn_08016de0. When byte +9 has
@ bit 0x8 or 0x4 set: draws end-cap squares with fn_0801f31c (record from
@ fn_0801f344, value 0x7fff) at the first point (bit 0x4) and the second point
@ (bit 0x8). Restores the clip pointer.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802002c,"ax",%progbits
	.p2align 2
	.global fn_0802002c
	.thumb_func
	.type fn_0802002c, %function
fn_0802002c:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r6, r1
	ldrsh.w	r1, [r1, #0x2]
	sub	sp, #0x58
	mov	r4, r3
	mov	r5, r2
	mov	r9, r0
	cmp	r1, #0x0
	beq.n	.L08020140
	ldrb	r0, [r6, #0x8]
	cmp	r0, #0x2
	bls.n	.L08020140
	ldrsh.w	r0, [r5, #0x0]
	ldrsh.w	r2, [r4, #0x0]
	cmp	r0, r2
	bne.n	.L08020060
	ldrsh.w	r3, [r5, #0x2]
	ldrsh.w	r7, [r4, #0x2]
	cmp	r3, r7
	beq.n	.L08020140
.L08020060:
	cmp	r0, r2
	blt.n	.L08020066
	mov	r0, r2
.L08020066:
	add.w	r1, r1, r1, lsr #0x1f
	sub.w	r0, r0, r1, asr #0x1
	strh.w	r0, [sp, #0x44]		@ box x0 = min x - thickness/2
	ldrsh.w	r1, [r5, #0x0]
	ldrsh.w	r0, [r4, #0x0]
	ldrsh.w	r2, [r6, #0x2]
	cmp	r1, r0
	ble.n	.L08020084
	mov	r0, r1
.L08020084:
	add.w	r1, r2, r2, lsr #0x1f
	add.w	r0, r0, r1, asr #0x1
	strh.w	r0, [sp, #0x48]		@ box x1 = max x + thickness/2
	ldrsh.w	r1, [r5, #0x2]
	ldrsh.w	r0, [r4, #0x2]
	ldrsh.w	r2, [r6, #0x2]
	cmp	r1, r0
	bge.n	.L080200a2
	mov	r0, r1
.L080200a2:
	add.w	r1, r2, r2, lsr #0x1f
	sub.w	r0, r0, r1, asr #0x1
	strh.w	r0, [sp, #0x46]		@ box y0 = min y - thickness/2
	ldrsh.w	r1, [r5, #0x2]
	ldrsh.w	r0, [r4, #0x2]
	ldrsh.w	r2, [r6, #0x2]
	cmp	r1, r0
	ble.n	.L080200c0
	mov	r0, r1
.L080200c0:
	add.w	r1, r2, r2, lsr #0x1f
	add.w	r0, r0, r1, asr #0x1
	strh.w	r0, [sp, #0x4a]		@ box y1 = max y + thickness/2
	add	r1, sp, #0x44
	mov	r0, r1
	ldr.w	r2, [r9, #0x8]
	bl	rect_intersect
	cmp	r0, #0x0
	beq.n	.L080201c8
	add	r1, sp, #0x44
	ldr.w	r10, [r9, #0x8]		@ saved clip pointer
	str.w	r1, [r9, #0x8]
	ldrsh.w	r0, [r5, #0x2]
	ldrsh.w	r1, [r4, #0x2]
	cmp	r0, r1
	bne.n	.L08020100
	mov	r3, r4
	mov	r2, r5
	mov	r1, r6
	mov	r0, r9
	bl	fn_08016c6c
	b.n	.L0802011e
.L08020100:
	ldrsh.w	r0, [r5, #0x0]
	ldrsh.w	r1, [r4, #0x0]
	mov	r3, r4
	cmp	r0, r1
	mov	r2, r5
	mov	r1, r6
	mov	r0, r9
	bne.n	.L0802011a
	bl	fn_0801713c
	b.n	.L0802011e
.L0802011a:
	bl	fn_08016de0
.L0802011e:
	ldrb	r0, [r6, #0x9]
	lsls	r1, r0, #0x1c
	bmi.n	.L08020128
	lsls	r0, r0, #0x1d
	bpl.n	.L080201c4
.L08020128:
	add	r0, sp, #0x8
	bl	fn_0801f344
	ldrh	r0, [r6, #0x0]
	strh.w	r0, [sp, #0xc]
	movw	r0, #0x7fff
	strh.w	r0, [sp, #0x8]
	ldrb	r0, [r6, #0x8]
	b.n	.L08020142
.L08020140:
	b.n	.L080201c8
.L08020142:
	strb.w	r0, [sp, #0xb]
	ldrsh.w	r0, [r6, #0x2]
	asrs	r7, r0, #0x1
	sbfx	r0, r0, #0x0, #0x1
	add.w	r8, r0, #0x1
	ldrb	r0, [r6, #0x9]
	lsls	r0, r0, #0x1d
	bpl.n	.L0802018c
	ldrh	r0, [r5, #0x0]
	mov	r2, sp
	subs	r0, r0, r7
	strh.w	r0, [sp, #0x0]
	ldrh	r0, [r5, #0x2]
	subs	r0, r0, r7
	strh.w	r0, [sp, #0x2]
	ldrh	r0, [r5, #0x0]
	adds	r1, r0, r7
	sub.w	r0, r1, r8
	strh.w	r0, [sp, #0x4]
	ldrh	r0, [r5, #0x2]
	adds	r1, r0, r7
	sub.w	r0, r1, r8
	strh.w	r0, [sp, #0x6]
	add	r1, sp, #0x8
	mov	r0, r9
	bl	fn_0801f31c
.L0802018c:
	ldrb	r0, [r6, #0x9]
	lsls	r0, r0, #0x1c
	bpl.n	.L080201c4
	ldrh	r0, [r4, #0x0]
	mov	r2, sp
	subs	r0, r0, r7
	strh.w	r0, [sp, #0x0]
	ldrh	r0, [r4, #0x2]
	subs	r0, r0, r7
	strh.w	r0, [sp, #0x2]
	ldrh	r0, [r4, #0x0]
	adds	r1, r0, r7
	sub.w	r0, r1, r8
	strh.w	r0, [sp, #0x4]
	ldrh	r0, [r4, #0x2]
	adds	r1, r0, r7
	sub.w	r0, r1, r8
	strh.w	r0, [sp, #0x6]
	add	r1, sp, #0x8
	mov	r0, r9
	bl	fn_0801f31c
.L080201c4:
	str.w	r10, [r9, #0x8]
.L080201c8:
	add	sp, #0x58
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
	.short	0x0000		@ padding

@ ----------------------------------------------------------------------------
@ fn_080201d0 - fill a polygon given as a list of points (scan-edge setup).
@ Parameters: r0 = object (saved at [sp+0x2c], field word +8 = pointer to a
@ clip rectangle), r1 = argument passed on to fn_0801f31c (saved at
@ [sp+0x30]), r2 = array of int16 {x,y} pairs (kept in r7), r3 = point count
@ (kept in r6). No return value.
@ Returns at once when the count is below 3 (unsigned) or the array pointer is
@ 0; allocates 4*count bytes with fn_08022bac and returns when that is 0.
@ Copy loop: word 0 is stored first, then for i = 0 .. count-2 point i is
@ stored to the copy unless point i and point i+1 have equal x and equal y;
@ the last point is stored unless equal to point 0; n = number stored; n < 3
@ frees the copy with fn_08022c44 and returns.
@ Bounding box [sp+8..sp+0xe] = {min x, min y, max x, max y}, starting from
@ the 8 bytes at 0x08050f0c (int16 0x1fff, 0x1fff, -0x1fff, -0x1fff), updated
@ over the n points. Calls rect_intersect(sp+0x14, box, object word +8);
@ result 0 frees the copy and returns; else saves object word +8 at [sp+0x24]
@ and sets it to sp+0x14 (the clipped box); finds r6 = index of the first
@ point with the smallest y; allocates 44*n bytes with fn_08022bac (edge pool,
@ base at [sp+0x10]).
@ Orientation flag [sp+0x1c] = 1 when dy_prev*dx_next < dy_next*dx_prev
@ (smulbb; d = coordinates of the previous / next point (index +-1 modulo n)
@ minus the top point), else 0.
@ Two cursors start at the top point: flag 1 -> cursor s moves +1 and cursor t
@ moves -1, flag 0 -> s moves -1 and t moves +1, indices modulo n, recomputed
@ each pass; when the next point of s has larger y and a different x it calls
@ fn_0801ee18(record, x_s, y_s, x_next, y_next on the stack, 1) then
@ table_slot_insert(record, pool base) and record += 44; equal y advances
@ without a record; smaller y does not advance; cursor t does the same with
@ last argument 0; counter r8 counts advances; stops when r8 == n.
@ Then calls fn_0801f31c(object, r1, box), fn_0801f2cc(pool base), frees the
@ pool and the point copy with fn_08022c44 and restores object word +8 from
@ [sp+0x24].
@ ----------------------------------------------------------------------------
	.section .text.fn_080201d0,"ax",%progbits
	.p2align 2
	.global fn_080201d0
	.thumb_func
	.type fn_080201d0, %function
fn_080201d0:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x2c
	mov	r6, r3
	mov	r7, r2
	cmp	r3, #0x3
	bcc.n	.L080202dc
	cmp	r7, #0x0
	beq.n	.L080202dc
	lsls	r0, r6, #0x2
	bl	fn_08022bac
	movs	r5, r0
	beq.n	.L080202e4
	movs	r4, #0x0
	ldr	r0, [r7, #0x0]
	str	r0, [r5, #0x0]
	mov	r0, r4
	subs	r2, r6, #0x1
	b.n	.L08020224
.L080201f8:
	add.w	r1, r7, r0, lsl #0x2
	ldrsh.w	r3, [r7, r0, lsl #0x2]
	ldrsh.w	r12, [r1, #0x4]
	cmp	r3, r12
	bne.n	.L08020214
	ldrsh.w	r3, [r1, #0x2]
	ldrsh.w	r12, [r1, #0x6]
	cmp	r3, r12
	beq.n	.L08020220
.L08020214:
	add.w	r3, r5, r4, lsl #0x2
	ldr	r1, [r1, #0x0]
	.inst.n	0x1c64		@ adds r4, r4, #1
	str	r1, [r3, #0x0]
	uxth	r4, r4
.L08020220:
	.inst.n	0x1c40		@ adds r0, r0, #1
	uxth	r0, r0
.L08020224:
	cmp	r0, r2
	blt.n	.L080201f8
	add.w	r0, r7, r6, lsl #0x2
	ldrsh.w	r1, [r7, #0x0]
	ldrsh.w	r2, [r0, #-0x4]
	cmp	r1, r2
	bne.n	.L08020244
	ldrsh.w	r1, [r7, #0x2]
	ldrsh.w	r2, [r0, #-0x2]
	cmp	r1, r2
	beq.n	.L08020252
.L08020244:
	add.w	r1, r5, r4, lsl #0x2
	ldr.w	r0, [r0, #-0x4]
	.inst.n	0x1c64		@ adds r4, r4, #1
	str	r0, [r1, #0x0]
	uxth	r4, r4
.L08020252:
	cmp	r4, #0x3
	bcc.n	.L080202de
	ldr	r1, .L0802044c
	ldrd	r0, r1, [r1, #0x0]
	strd	r0, r1, [sp, #0x8]	@ initial bounding box
	movs	r0, #0x0
	b.n	.L080202b4
.L08020264:
	ldrsh.w	r2, [sp, #0x8]
	ldrsh.w	r1, [r5, r0, lsl #0x2]
	cmp	r2, r1
	bge.n	.L08020272
	mov	r1, r2
.L08020272:
	strh.w	r1, [sp, #0x8]
	add.w	r2, r5, r0, lsl #0x2
	ldrsh.w	r1, [sp, #0xa]
	ldrsh.w	r3, [r2, #0x2]
	cmp	r1, r3
	blt.n	.L08020288
	mov	r1, r3
.L08020288:
	strh.w	r1, [sp, #0xa]
	ldrsh.w	r3, [sp, #0xc]
	ldrsh.w	r1, [r5, r0, lsl #0x2]
	cmp	r3, r1
	ble.n	.L0802029a
	mov	r1, r3
.L0802029a:
	strh.w	r1, [sp, #0xc]
	ldrsh.w	r3, [sp, #0xe]
	ldrsh.w	r1, [r2, #0x2]
	cmp	r3, r1
	ble.n	.L080202ac
	mov	r1, r3
.L080202ac:
	.inst.n	0x1c40		@ adds r0, r0, #1
	strh.w	r1, [sp, #0xe]
	uxth	r0, r0
.L080202b4:
	cmp	r0, r4
	bcc.n	.L08020264
	ldr	r0, [sp, #0x2c]
	add	r1, sp, #0x8
	ldr	r2, [r0, #0x8]
	add	r0, sp, #0x14
	bl	rect_intersect
	cbz	r0, .L080202de
	ldr	r0, [sp, #0x2c]
	add	r1, sp, #0x14
	movs	r6, #0x0
	ldr	r0, [r0, #0x8]
	str	r0, [sp, #0x24]		@ saved clip pointer
	ldr	r0, [sp, #0x2c]
	str	r1, [r0, #0x8]
	ldrsh.w	r1, [r5, #0x2]
	movs	r0, #0x1
	b.n	.L08020300
.L080202dc:
	b.n	.L080202e4
.L080202de:
	mov	r0, r5
	bl	fn_08022c44
.L080202e4:
	add	sp, #0x3c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	nop				@ padding
.L080202ec:
	add.w	r2, r5, r0, lsl #0x2
	ldrsh.w	r2, [r2, #0x2]
	cmp	r2, r1
	bge.n	.L080202fc
	mov	r1, r2
	sxth	r6, r0
.L080202fc:
	.inst.n	0x1c40		@ adds r0, r0, #1
	uxth	r0, r0
.L08020300:
	cmp	r0, r4
	bcc.n	.L080202ec
	movs	r1, #0x2c
	mul	r0, r4, r1
	bl	fn_08022bac
	mov	r11, r0
	mov	r10, r6
	str	r0, [sp, #0x10]		@ edge pool base
	mov	r9, r10
	mov.w	r8, #0x0
	subs	r0, r6, #0x1
	bpl.n	.L08020320
	add	r0, r4
.L08020320:
	subs	r2, r4, #0x1
	add.w	r1, r9, #0x1
	str	r2, [sp, #0x20]
	cmp	r1, r2
	ble.n	.L0802032e
	movs	r1, #0x0
.L0802032e:
	ldrh.w	r2, [r5, r6, lsl #0x2]
	ldrh.w	r3, [r5, r0, lsl #0x2]
	ldrh.w	r7, [r5, r1, lsl #0x2]
	add.w	r0, r5, r0, lsl #0x2
	subs	r3, r3, r2
	subs	r7, r7, r2
	ldrh	r2, [r0, #0x2]
	add.w	r0, r5, r6, lsl #0x2
	add.w	r1, r5, r1, lsl #0x2
	ldrh	r0, [r0, #0x2]
	ldrh	r1, [r1, #0x2]
	subs	r2, r2, r0
	subs	r0, r1, r0
	movs	r1, #0x0
	str	r1, [sp, #0x1c]		@ orientation flag
	smulbb	r1, r2, r7
	smulbb	r0, r0, r3
	cmp	r1, r0
	bge.n	.L08020434
	movs	r0, #0x1
	str	r0, [sp, #0x1c]
	b.n	.L0802036e
.L0802036a:
	ldr	r0, [sp, #0x1c]
	cbz	r0, .L080203ec
.L0802036e:
	ldr	r0, [sp, #0x20]
	add.w	r6, r10, #0x1
	cmp	r6, r0
	ble.n	.L0802037a
	movs	r6, #0x0
.L0802037a:
	subs.w	r7, r9, #0x1
	bpl.n	.L08020382
	add	r7, r4
.L08020382:
	add.w	r0, r5, r6, lsl #0x2
	add.w	r1, r5, r10, lsl #0x2
	ldrsh.w	r0, [r0, #0x2]
	ldrsh.w	r2, [r1, #0x2]
	cmp	r0, r2
	blt.n	.L080203c4
	beq.n	.L080203be
	ldrsh.w	r3, [r5, r6, lsl #0x2]
	ldrsh.w	r1, [r5, r10, lsl #0x2]
	cmp	r3, r1
	beq.n	.L080203be
	mov.w	r12, #0x1
	strd	r0, r12, [sp, #0x0]
	mov	r0, r11
	bl	fn_0801ee18
	mov	r0, r11
	ldr	r1, [sp, #0x10]
	bl	table_slot_insert
	add.w	r11, r11, #0x2c
.L080203be:
	add.w	r8, r8, #0x1
	mov	r10, r6
.L080203c4:
	cmp	r8, r4
	beq.n	.L08020410
	add.w	r0, r5, r7, lsl #0x2
	add.w	r1, r5, r9, lsl #0x2
	ldrsh.w	r0, [r0, #0x2]
	ldrsh.w	r2, [r1, #0x2]
	cmp	r0, r2
	blt.n	.L0802040c
	beq.n	.L08020406
	ldrsh.w	r3, [r5, r7, lsl #0x2]
	ldrsh.w	r1, [r5, r9, lsl #0x2]
	cmp	r3, r1
	beq.n	.L08020406
	b.n	.L080203ee
.L080203ec:
	b.n	.L08020434
.L080203ee:
	movs	r6, #0x0
	strd	r0, r6, [sp, #0x0]
	mov	r0, r11
	bl	fn_0801ee18
	mov	r0, r11
	ldr	r1, [sp, #0x10]
	bl	table_slot_insert
	add.w	r11, r11, #0x2c
.L08020406:
	add.w	r8, r8, #0x1
	mov	r9, r7
.L0802040c:
	cmp	r8, r4
	bcc.n	.L0802036a
.L08020410:
	ldrd	r0, r1, [sp, #0x2c]
	add	r2, sp, #0x8
	bl	fn_0801f31c
	ldr	r0, [sp, #0x10]
	bl	fn_0801f2cc
	ldr	r0, [sp, #0x10]
	bl	fn_08022c44
	mov	r0, r5
	bl	fn_08022c44
	ldr	r1, [sp, #0x2c]
	ldr	r0, [sp, #0x24]
	str	r0, [r1, #0x8]		@ restore the clip pointer
	b.n	.L080202e4
.L08020434:
	subs.w	r6, r10, #0x1
	bpl.n	.L0802043c
	add	r6, r4
.L0802043c:
	ldr	r0, [sp, #0x20]
	add.w	r7, r9, #0x1
	cmp	r7, r0
	ble.n	.L08020382
	movs	r7, #0x0
	b.n	.L08020382
	.short	0x0000		@ padding
.L0802044c:
	.word	d_08050f0c		@ initial bounding box {0x1fff, 0x1fff, -0x1fff, -0x1fff}

@ ----------------------------------------------------------------------------
@ call_five_routines_in_sequence - run five routines with the same three
@ arguments.
@ Parameters: r0, r1, r2 passed unchanged to every callee (kept in r6, r5,
@ r4); r3 is not touched. No return value.
@ Pushes r4-r6 and lr, calls fn_08018dd4 (arguments as received), then
@ fn_08015110(r0, r1, r2), fn_080154ba(r0, r1, r2), fn_0801569e(r0, r1, r2),
@ then pops r4-r6 and lr and tail-calls fn_08017b90(r0, r1, r2).
@ ----------------------------------------------------------------------------
	.section .text.call_five_routines_in_sequence,"ax",%progbits
	.p2align 2
	.global call_five_routines_in_sequence
	.thumb_func
	.type call_five_routines_in_sequence, %function
call_five_routines_in_sequence:
	push	{r4, r5, r6, lr}
	mov	r4, r2
	mov	r5, r1
	mov	r6, r0
	bl	fn_08018dd4
	mov	r2, r4
	mov	r1, r5
	mov	r0, r6
	bl	fn_08015110
	mov	r2, r4
	mov	r1, r5
	mov	r0, r6
	bl	fn_080154ba
	mov	r2, r4
	mov	r1, r5
	mov	r0, r6
	bl	fn_0801569e
	mov	r2, r4
	mov	r1, r5
	mov	r0, r6
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08017b90

@ ----------------------------------------------------------------------------
@ fn_08020488 - transform a rectangle of a source image into per-row output
@ buffers (rotation by an angle and scale, one output row at a time).
@ Parameters (13 words pushed at entry, stack arguments at sp+0xb8 after the
@ prologue): r0 not read; r1 = rectangle {halfwords +0 x0, +2 y0, +4 x1, +6
@ y1} (kept in r5); r2 = source base pointer; r3 = source width; stack arg5
@ [sp+0xb8] = source height; arg6 [sp+0xbc] = source row stride; arg7
@ [sp+0xc0] = transform pointer (r7: signed halfword +0, unsigned halfword +2,
@ word +4 (halfwords +4 and +6), byte +0x14); arg8 [sp+0xc4] = mode; arg9
@ [sp+0xc8] = output halfword buffer pointer (advanced per row); arg10
@ [sp+0xcc] = output byte buffer pointer (r11, advanced per row). No return
@ value.
@ Setup: V = -(signed halfword [r7+0]); word sp+0x68 = V; word sp+0x64 =
@ 0x10000 / unsigned halfword [r7+2] (udiv); q = V / 10 (sdiv), rem = V - 10*q
@ (r6); sine_q15_degrees is called with q, q+1, q+0x5a, q+0x5b (each sxth)
@ giving A, C, B, D; word sp+0x5c = ((10-rem)*A + rem*C) / 10 asr 5; word
@ sp+0x60 = ((10-rem)*B + rem*D) / 10 asr 5; word sp+0x74 = word [r7+4]; word
@ sp+0x6c = signed halfword sp+0x74 lsl 8; word sp+0x70 = signed halfword
@ sp+0x76 lsl 8; width r4 = sxth(x1 - x0 + 1); rows r10 = sxth(y1 - y0 + 1);
@ row counter r6 = 0.
@ Per row (loop while r6 < r10, signed): fn_0802ad38(sp+0x4c, x0, y0 + r6,
@ sp+0x2c, [sp] = sp+0x30) and fn_0802ad38(sp+0x4c, x1, y0 + r6, sp+0x34,
@ [sp] = sp+0x38) (the block at sp+0x4c holds the words at sp+0x5c..0x74
@ above; its first 0x10 bytes are not written here); start x = word sp+0x2c
@ (r9), start y = word sp+0x30 (r0); when width r4 > 1: step x = ((sp+0x34 -
@ sp+0x2c) lsl 8) / (r4-1) (r2), step y = ((sp+0x38 - sp+0x30) lsl 8) /
@ (r4-1) (r1), else both 0.
@ When bit 0 of byte [r7+0x14] is set: fn_08013734(source base, source width,
@ height, stride, start x, start y, step x, step y, width, output halfword
@ buffer, output byte buffer, mode) (r0..r3 and stack words sp+0 to sp+0x1c in
@ that order).
@ Else by mode: 4 and 6 call fn_0802928e with the same 12 arguments; mode 5
@ per column c = 0..width-1: x = (start x + ((step x * c) asr 8)) asr 8, y =
@ (start y + ((step y * c) asr 8)) asr 8; out of range when x < 0, x >= source
@ width, y < 0 or y >= height: byte out[c] = 0; otherwise p = base + 3*(y*stride
@ + x), halfword out[c] = byte p[0] + (byte p[1] lsl 8), byte out[c] = byte
@ p[2]; mode 0x14 same x and y, out of range when x < 0, x >= width, y < 0, y
@ >= height: byte out[c] = 0 (halfword not written); otherwise halfword out[c]
@ = halfword at base + 2*(y*stride + x), byte out[c] = byte at base +
@ 2*stride*height + y*stride + x; other modes draw nothing.
@ After each row: output halfword pointer += 2*width, output byte pointer +=
@ width, r6 += 1. Returns through add sp,#0x94 and pop.w {r4-r11,pc}.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020488,"ax",%progbits
	.p2align 2
	.global fn_08020488
	.thumb_func
	.type fn_08020488, %function
fn_08020488:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x84
	mov	r5, r1
	ldr	r7, [sp, #0xc0]
	ldr.w	r11, [sp, #0xcc]
	mov.w	r1, #0x10000
	ldrsh.w	r0, [r7, #0x0]
	mov.w	r9, #0xa
	rsbs	r0, r0, #0
	str	r0, [sp, #0x68]
	ldrh	r0, [r7, #0x2]
	udiv	r0, r1, r0
	ldr	r1, [sp, #0x68]
	str	r0, [sp, #0x64]
	sdiv	r4, r1, r9
	ldr	r0, [r7, #0x4]
	str	r0, [sp, #0x74]
	mov	r0, r1
	rsbs	r1, r4, #0
	add.w	r1, r1, r1, lsl #0x2
	add.w	r6, r0, r1, lsl #0x1
	add.w	r8, r4, #0x1
	sxth	r0, r4
	bl	sine_q15_degrees
	str	r0, [sp, #0x14]
	sxth.w	r0, r8
	bl	sine_q15_degrees
	mov	r10, r0
	adds	r4, #0x5a
	sxth	r0, r4
	bl	sine_q15_degrees
	mov	r4, r0
	add.w	r0, r8, #0x5a
	sxth	r0, r0
	bl	sine_q15_degrees
	ldr	r2, [sp, #0x14]
	rsb.w	r1, r6, #0xa
	mul	r3, r1, r2
	muls	r1, r4, r1
	mla	r1, r0, r6, r1
	mla	r3, r10, r6, r3
	sdiv	r0, r1, r9
	sdiv	r2, r3, r9
	str	r0, [sp, #0x60]
	asrs	r0, r2, #0x5
	str	r0, [sp, #0x5c]
	ldr	r0, [sp, #0x60]
	asrs	r0, r0, #0x5
	str	r0, [sp, #0x60]
	ldrsh.w	r0, [sp, #0x74]
	lsls	r0, r0, #0x8
	str	r0, [sp, #0x6c]
	ldrsh.w	r0, [sp, #0x76]
	lsls	r0, r0, #0x8
	str	r0, [sp, #0x70]
	ldrh	r0, [r5, #0x4]
	ldrh	r1, [r5, #0x0]
	subs	r0, r0, r1
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r4, r0
	ldrh	r0, [r5, #0x6]
	ldrh	r1, [r5, #0x2]
	subs	r0, r0, r1
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth.w	r10, r0
	movs	r6, #0x0
	b.n	.L080205d0
.L08020540:
	add	r0, sp, #0x30
	str	r0, [sp, #0x0]
	ldrsh.w	r0, [r5, #0x2]
	ldrsh.w	r1, [r5, #0x0]
	adds	r2, r0, r6
	add	r3, sp, #0x2c
	add	r0, sp, #0x4c
	bl	fn_0802ad38
	add	r0, sp, #0x38
	str	r0, [sp, #0x0]
	ldrsh.w	r0, [r5, #0x2]
	ldrsh.w	r1, [r5, #0x4]
	adds	r2, r0, r6
	add	r3, sp, #0x34
	add	r0, sp, #0x4c
	bl	fn_0802ad38
	ldr	r3, [sp, #0x2c]
	ldr	r0, [sp, #0x34]
	ldr	r1, [sp, #0x38]
	sub.w	r8, r0, r3
	ldr	r0, [sp, #0x30]
	movs	r2, #0x0
	sub.w	r12, r1, r0
	mov	r1, r2
	cmp	r4, #0x1
	ble.n	.L08020596
	lsl.w	r2, r8, #0x8
	subs	r1, r4, #0x1
	sdiv	r2, r2, r1
	lsl.w	r12, r12, #0x8
	sdiv	r1, r12, r1
.L08020596:
	mov	r9, r3
	ldrb	r3, [r7, #0x14]
	lsls	r3, r3, #0x1f
	beq.n	.L080205da
	ldrd	r3, r8, [sp, #0xc4]
	strd	r11, r3, [sp, #0x18]
	str.w	r9, [sp, #0x0]
	strd	r0, r2, [sp, #0x4]
	add.w	r12, sp, #0xc
	stm.w	r12, {r1, r4, r8}
	ldrd	r0, r1, [sp, #0x8c]
	ldrd	r2, r3, [sp, #0xb8]
	bl	fn_08013734
.L080205c2:
	ldr	r0, [sp, #0xc8]
	.inst.n	0x1c76		@ adds r6, r6, #1
	add.w	r0, r0, r4, lsl #0x1
	add	r11, r4
	sxth	r6, r6
	str	r0, [sp, #0xc8]
.L080205d0:
	cmp	r6, r10
	blt.n	.L08020540
	add	sp, #0x94
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L080205da:
	ldr	r3, [sp, #0xc4]
	cmp	r3, #0x4
	beq.n	.L08020686
	cmp	r3, #0x5
	beq.n	.L0802060c
	cmp	r3, #0x6
	beq.n	.L08020686
	cmp	r3, #0x14
	bne.n	.L080205c2
	ldr	r3, [sp, #0x8c]
	str	r3, [sp, #0x78]
	ldr	r3, [sp, #0x90]
	str	r3, [sp, #0x48]
	ldr	r3, [sp, #0xb8]
	str	r3, [sp, #0x1c]
	str	r1, [sp, #0x14]
	ldr	r3, [sp, #0xbc]
	ldr	r1, [sp, #0xc8]
	mov	lr, r0
	str	r2, [sp, #0x24]
	movs	r0, #0x0
	str.w	r9, [sp, #0x80]
	str	r1, [sp, #0x40]
	b.n	.L0802071e
.L0802060c:
	ldr	r3, [sp, #0x8c]
	str	r3, [sp, #0x48]
	ldr	r3, [sp, #0x90]
	str	r3, [sp, #0x40]
	ldrd	r3, r12, [sp, #0xb8]
	str	r1, [sp, #0x10]
	mov	lr, r9
	ldr	r1, [sp, #0xc8]
	mov	r9, r0
	mov	r8, r12
	str	r2, [sp, #0x4]
	movs	r0, #0x0
	str	r1, [sp, #0x24]
	b.n	.L08020680
.L0802062a:
	ldr	r2, [sp, #0x10]
	ldr	r1, [sp, #0x4]
	muls	r2, r0, r2
	muls	r1, r0, r1
	add.w	r1, lr, r1, asr #0x8
	add.w	r2, r9, r2, asr #0x8
	asrs	r1, r1, #0x8
	asr.w	r2, r2, #0x8
	bmi.n	.L08020652
	ldr.w	r12, [sp, #0x40]
	cmp	r1, r12
	bge.n	.L08020652
	cmp	r2, #0x0
	blt.n	.L08020652
	cmp	r2, r3
	blt.n	.L08020656
.L08020652:
	movs	r2, #0x0
	b.n	.L08020678
.L08020656:
	mla	r1, r2, r8, r1
	ldr.w	r12, [sp, #0x48]
	add.w	r1, r1, r1, lsl #0x1
	add	r1, r12
	ldrb	r2, [r1, #0x0]
	ldrb.w	r12, [r1, #0x1]
	add.w	r2, r2, r12, lsl #0x8
	ldr.w	r12, [sp, #0x24]
	strh.w	r2, [r12, r0, lsl #0x1]
	ldrb	r2, [r1, #0x2]
.L08020678:
	strb.w	r2, [r11, r0]
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r0, r0
.L08020680:
	cmp	r0, r4
	blt.n	.L0802062a
	b.n	.L080205c2
.L08020686:
	strd	r11, r3, [sp, #0x18]
	ldr.w	r8, [sp, #0xc8]
	str.w	r9, [sp, #0x0]
	strd	r0, r2, [sp, #0x4]
	add.w	r12, sp, #0xc
	stm.w	r12, {r1, r4, r8}
	ldrd	r0, r1, [sp, #0x8c]
	ldrd	r2, r3, [sp, #0xb8]
	bl	fn_0802928e
	b.n	.L080205c2
.L080206ac:
	ldr	r1, [sp, #0x24]
	ldr	r2, [sp, #0x80]
	muls	r1, r0, r1
	add.w	r1, r2, r1, asr #0x8
	ldr	r2, [sp, #0x14]
	muls	r2, r0, r2
	add.w	r2, lr, r2, asr #0x8
	asrs	r1, r1, #0x8
	asr.w	r2, r2, #0x8
	bmi.n	.L080206da
	ldr.w	r12, [sp, #0x48]
	cmp	r1, r12
	bge.n	.L080206da
	cmp	r2, #0x0
	blt.n	.L080206da
	ldr.w	r12, [sp, #0x1c]
	cmp	r2, r12
	blt.n	.L080206e2
.L080206da:
	movs	r1, #0x0
	strb.w	r1, [r11, r0]
	b.n	.L0802071a
.L080206e2:
	mla	r9, r2, r3, r1
	ldr.w	r8, [sp, #0x78]
	ldr.w	r12, [sp, #0x40]
	add.w	r8, r8, r9, lsl #0x1
	add.w	r9, r12, r0, lsl #0x1
	ldrh.w	r8, [r8, #0x0]
	strh.w	r8, [r9, #0x0]
	ldr.w	r8, [sp, #0x1c]
	mul	r12, r3, r8
	ldr.w	r8, [sp, #0x78]
	add.w	r12, r8, r12, lsl #0x1
	add	r1, r12
	mla	r1, r2, r3, r1
	ldrb	r2, [r1, #0x0]
	strb.w	r2, [r11, r0]
.L0802071a:
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r0, r0
.L0802071e:
	cmp	r0, r4
	blt.n	.L080206ac
	b.n	.L080205c2

@ ----------------------------------------------------------------------------
@ fn_08020d36 - colour of a gradient table at a position (RGB565).
@ Parameters: r0 = gradient table (ushort entries of two halfwords each; the
@ byte count is at +8, the position byte of an entry is at +2 of the entry),
@ r1 = scale, r2 = position. Returns an RGB565 colour in r0.
@ Position at or below entry 0 (entry position byte * scale >> 8) returns the
@ first halfword; at or beyond the last entry returns the last entry colour.
@ Otherwise finds the interval, converts the two colours with
@ rgb565_to_argb8888, interpolates each channel with weights (position
@ fraction * 0xff / span) and 0xff - weight, packs with multiplier 0x8081 into
@ masks 0x1f, 0x3f << 5, 0x1f << 11. A zero span or the end of the table falls
@ into the infinite loop at .L08020e30.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020d36,"ax",%progbits
	.global fn_08020d36
	.thumb_func
	.type fn_08020d36, %function
fn_08020d36:
	push.w	{r2, r3, r4, r5, r6, r7, r8, lr}
	mov	r4, r1
	ldrb	r1, [r0, #0x2]
	mov	r5, r2
	smulbb	r1, r1, r4
	asrs	r1, r1, #0x8
	cmp	r2, r1
	bgt.n	.L08020d50
	ldrh	r0, [r0, #0x0]
.L08020d4c:
	pop.w	{r2, r3, r4, r5, r6, r7, r8, pc}
.L08020d50:
	ldrb	r2, [r0, #0x8]
	add.w	r1, r0, r2, lsl #0x2
	ldrb.w	r3, [r1, #-0x2]
	smulbb	r3, r3, r4
	asrs	r3, r3, #0x8
	cmp	r5, r3
	blt.n	.L08020d6a
	ldrh.w	r0, [r1, #-0x4]
	b.n	.L08020d4c
.L08020d6a:
	movs	r3, #0x1
	b.n	.L08020e2c
.L08020d6e:
	add.w	r1, r0, r3, lsl #0x2
	ldrb	r1, [r1, #0x2]
	smulbb	r1, r1, r4
	asrs	r1, r1, #0x8
	cmp	r5, r1
	bgt.n	.L08020e28
	add.w	r7, r0, r3, lsl #0x2
	ldrh.w	r0, [r7, #-0x4]!
	strh.w	r0, [sp, #0x4]
	ldr	r0, [sp, #0x4]
	bl	rgb565_to_argb8888
	mov	r6, r0
	ldrh	r0, [r7, #0x4]
	strh.w	r0, [sp, #0x4]
	ldr	r0, [sp, #0x4]
	bl	rgb565_to_argb8888
	mov	r1, r0
	ldrb	r0, [r7, #0x2]
	smulbb	r0, r0, r4
	ldrb	r2, [r7, #0x6]
	asrs	r0, r0, #0x8
	smulbb	r2, r2, r4
	rsbs	r2, r0, r2, asr #0x8	@ span of the interval
	beq.n	.L08020e30
	subs	r0, r5, r0
	sxth	r0, r0
	rsb	r0, r0, r0, lsl #0x8
	sdiv	r0, r0, r2
	uxtb	r2, r0
	rsb.w	r3, r2, #0xff
	uxtb	r0, r1
	smulbb	r0, r0, r2
	uxtb	r4, r6
	smlabb	r0, r4, r3, r0
	add.w	r4, r0, r0, lsl #0x7
	add.w	r0, r4, r0, lsl #0xf
	lsrs	r4, r0, #0x1a
	ldrh.w	r0, [sp, #0x0]
	bfi	r0, r4, #0x0, #0x5
	ubfx	r4, r1, #0x8, #0x8
	smulbb	r4, r4, r2
	ubfx	r5, r6, #0x8, #0x8
	smlabb	r4, r5, r3, r4
	add.w	r5, r4, r4, lsl #0x7
	add.w	r4, r5, r4, lsl #0xf
	lsrs	r4, r4, #0x19
	bfi	r0, r4, #0x5, #0x6
	ubfx	r1, r1, #0x10, #0x8
	smulbb	r1, r1, r2
	ubfx	r2, r6, #0x10, #0x8
	smlabb	r1, r2, r3, r1
	add.w	r2, r1, r1, lsl #0x7
	add.w	r1, r2, r1, lsl #0xf
	lsrs	r1, r1, #0x1a
	bfi	r0, r1, #0xb, #0x5
	strh.w	r0, [sp, #0x0]
	uxth	r0, r0
	b.n	.L08020d4c
.L08020e28:
	.inst.n	0x1c5b		@ adds r3, r3, #1
	uxtb	r3, r3
.L08020e2c:
	cmp	r2, r3
	bhi.n	.L08020d6e
.L08020e30:
	b.n	.L08020e30		@ infinite loop

@ ----------------------------------------------------------------------------
@ fn_08020e32 - free an object when its word +4 is negative.
@ Parameters: r0 = object. No return value of its own.
@ When the word at +4 is negative, tail-calls fn_08022c68(object), which frees
@ the object itself; otherwise returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020e32,"ax",%progbits
	.global fn_08020e32
	.thumb_func
	.type fn_08020e32, %function
fn_08020e32:
	ldr	r1, [r0, #0x4]
	cmp	r1, #0x0
	bge.n	.L08020e3c
	b.w	fn_08022c68
.L08020e3c:
	bx	lr
	.short	0x0000		@ padding

@ ----------------------------------------------------------------------------
@ fn_08020e40 - make sure a gradient has a cached colour table.
@ Parameters: r0 = gradient object (bits 0..2 of byte +9 select the mode),
@ r1, r2, r3 = values (r3 is not used). No return value.
@ Nothing happens when the mode bits are 0. When the byte at 0x20000568 is 0
@ calls fn_08020ee0(0) and sets the byte to 1. Builds key = (mode == 2 ? r1 :
@ r2) ^ (r1 >> 1) ^ object and looks it up with find_record_by_callback(
@ pointed_words_equal, &key, &entry).
@ Found: word +4 of the entry = (((word rotated left by 2) + 4) rotated right
@ by 2). Not found: fn_080134b8(object, r1, r2) creates an entry (returns 0 on
@ failure) and its halfword array (count short at +0xe, array pointer +8) is
@ filled with fn_08020d36(object, count, index) for each index.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020e40,"ax",%progbits
	.p2align 2
	.global fn_08020e40
	.thumb_func
	.type fn_08020e40, %function
fn_08020e40:
	push	{r1, r2, r3, r4, r5, r6, r7, lr}
	mov	r5, r0
	ldrb	r0, [r0, #0x9]
	mov	r6, r2
	mov	r4, r1
	lsls	r0, r0, #0x1d
	beq.n	.L08020eae
	ldr	r7, .L08020ed8
	ldrb	r0, [r7, #0x0]
	cbnz	r0, .L08020e5e
	movs	r0, #0x0
	bl	fn_08020ee0
	movs	r0, #0x1
	strb	r0, [r7, #0x0]
.L08020e5e:
	ldrb	r0, [r5, #0x9]
	and.w	r0, r0, #0x7
	cmp	r0, #0x2
	beq.n	.L08020e9a
	mov.w	r0, r6
.L08020e6c:
	eor.w	r0, r0, r4, asr #0x1
	eors	r0, r5
	str	r0, [sp, #0x4]
	movs	r0, #0x0
	str	r0, [sp, #0x0]
	mov	r2, sp
	add	r1, sp, #0x4
	ldr	r0, .L08020edc
	bl	find_record_by_callback
	cmp	r0, #0x1
	beq.n	.L08020e9e
	mov	r2, r6
	mov	r1, r4
	mov	r0, r5
	bl	fn_080134b8
	str	r0, [sp, #0x0]
	cmp	r0, #0x0
	beq.n	.L08020eae
	movs	r4, #0x0
	b.n	.L08020ecc
.L08020e9a:
	mov	r0, r4
	b.n	.L08020e6c
.L08020e9e:
	ldr	r0, [sp, #0x0]
	movs	r2, #0x4
	ldr	r1, [r0, #0x4]
	add.w	r1, r2, r1, ror #0x1e
	ror.w	r1, r1, #0x2
	str	r1, [r0, #0x4]
.L08020eae:
	pop	{r1, r2, r3, r4, r5, r6, r7, pc}
.L08020eb0:
	mov	r2, r4
	mov	r0, r5
	bl	fn_08020d36
	str	r0, [sp, #0x8]
	ldr	r0, [sp, #0x0]
	ldrh.w	r1, [sp, #0x8]
	ldr	r0, [r0, #0x8]
	add.w	r0, r0, r4, lsl #0x1
	.inst.n	0x1c64		@ adds r4, r4, #1
	strh	r1, [r0, #0x0]
	sxth	r4, r4
.L08020ecc:
	ldr	r0, [sp, #0x0]
	ldrsh.w	r1, [r0, #0xe]
	cmp	r1, r4
	bgt.n	.L08020eb0
	pop	{r1, r2, r3, r4, r5, r6, r7, pc}
.L08020ed8:
	.word	0x20000568		@ byte flag: gradient cache initialised
.L08020edc:
	.word	pointed_words_equal	@ compare callback for find_record_by_callback

@ ----------------------------------------------------------------------------
@ fn_08021324 - expand one row of an indexed image to 3 bytes per pixel.
@ Parameters: r0 = image object, r1 = x, r2 = row, r3 = pixel count, stack
@ word (read at [sp+0x50]) = output buffer (3 bytes per pixel). Returns 1 on
@ success, 0 when fn_08022bac fails.
@ Fills bytes 0 and 1 of every output pixel with the halfword at object+8.
@ Reads the format = word +0x14 & 0x1f and the bits per pixel via fn_08021168;
@ formats 0xb, 0xc, 0xd, 0xe select 1, 2, 4 and 8 bit indexed rows (row bytes
@ = (((word & 0x1fffff) >> 10) + 7) >> 3 etc.) with lookup tables built on the
@ stack: 0xff00 (2 entries, format 0xb), 0xffaa5500 (4 entries, format 0xc)
@ and 0x33221100 0x77665544 0xbbaa9988 0xffeeddcc (16 entries, format 0xd).
@ Allocates a row buffer with fn_08022bac, reads it from memory (word at
@ (*(object+4))+8) or, when byte +0x10 is nonzero, from the file handle at
@ +0x24 via fn_08020c9c(handle, offset+4, 0) and fn_08020b32. Writes the table
@ value (or the raw byte for format 0xe) into byte 2 of each output pixel,
@ shifting by bits per pixel, then frees the buffer with fn_08022c44.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021324,"ax",%progbits
	.p2align 2
	.global fn_08021324
	.thumb_func
	.type fn_08021324, %function
fn_08021324:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r8, r0
	adr	r0, .L0802149c
	sub	sp, #0x1c
	ldr	r0, [r0, #0x0]
	str	r0, [sp, #0x10]
	adr	r0, .L080214a0
	adr	r3, .L080214a4
	ldr	r0, [r0, #0x0]
	mov	r11, r2
	mov	r7, r1
	str	r0, [sp, #0x14]
	ldmia	r3, {r0, r1, r2, r3}
	stm.w	sp, {r0, r1, r2, r3}
	ldrh.w	r1, [r8, #0x8]
	movs	r0, #0x0
	uxth	r1, r1
	uxtb	r2, r1
	lsrs	r1, r1, #0x8
	b.n	.L08021366
	nop				@ padding
.L08021354:
	ldr	r4, [sp, #0x50]
	add.w	r3, r0, r0, lsl #0x1
	.inst.n	0x1c40		@ adds r0, r0, #1
	strb	r2, [r4, r3]
	ldr	r4, [sp, #0x50]
	sxth	r0, r0
	add	r3, r4
	strb	r1, [r3, #0x1]
.L08021366:
	ldr	r3, [sp, #0x28]
	cmp	r0, r3
	blt.n	.L08021354
	ldrb.w	r0, [r8, #0x14]
	mov.w	r9, #0x0
	and.w	r0, r0, #0x1f
	bl	fn_08021168
	mov	r10, r0
	movs	r1, #0x1
	lsl.w	r1, r1, r10
	.inst.n	0x1e49		@ subs r1, r1, #1
	uxth	r0, r1
	str	r0, [sp, #0x18]		@ bit mask of one pixel
	movs	r5, #0x0
	ldr.w	r0, [r8, #0x14]
	mov	r4, r5
	and.w	r1, r0, #0x1f
	mov	r6, r5
	cmp	r1, #0xb
	beq.n	.L080213aa
	cmp	r1, #0xc
	beq.n	.L080213c6
	cmp	r1, #0xd
	beq.n	.L080213e6
	cmp	r1, #0xe
	bne.n	.L0802140c
	b.n	.L08021404
.L080213aa:
	ubfx	r0, r0, #0xa, #0xb
	.inst.n	0x1dc0		@ adds r0, r0, #7
	lsrs	r5, r0, #0x3
	add.w	r1, r4, r7, asr #0x3
	smlabb	r4, r5, r11, r1
	and.w	r0, r7, #0x7
	rsb.w	r6, r0, #0x7
	add	r0, sp, #0x10
	b.n	.L080213e2
.L080213c6:
	ubfx	r0, r0, #0xa, #0xb
	.inst.n	0x1cc0		@ adds r0, r0, #3
	lsrs	r5, r0, #0x2
	add.w	r1, r4, r7, asr #0x2
	smlabb	r4, r5, r11, r1
	and.w	r0, r7, #0x3
	movs	r1, #0x6
	sub.w	r6, r1, r0, lsl #0x1
	add	r0, sp, #0x14
.L080213e2:
	mov	r9, r0
	b.n	.L0802140c
.L080213e6:
	ubfx	r0, r0, #0xa, #0xb
	.inst.n	0x1c40		@ adds r0, r0, #1
	lsrs	r5, r0, #0x1
	add.w	r1, r4, r7, asr #0x1
	smlabb	r4, r5, r11, r1
	and.w	r0, r7, #0x1
	movs	r1, #0x4
	sub.w	r6, r1, r0, lsl #0x2
	mov	r0, sp
	b.n	.L080213e2
.L08021404:
	ubfx	r5, r0, #0xa, #0xb
	smlabb	r4, r5, r11, r7
.L0802140c:
	mov	r0, r5
	ldr.w	r7, [r8, #0x24]
	bl	fn_08022bac
	movs.w	r11, r0
	beq.n	.L08021444
	ldrb.w	r0, [r8, #0x10]
	cbz	r0, .L0802144c
	movs	r2, #0x0
	adds	r1, r4, #0x4
	mov	r0, r7
	bl	fn_08020c9c
	movs	r3, #0x0
	mov	r2, r5
	mov	r1, r11
	mov	r0, r7
	bl	fn_08020b32
	mov	r1, r11
.L0802143a:
	rsb.w	r2, r10, #0x8
	movs	r0, #0x0
	sxtb	r3, r2
	b.n	.L0802148a
.L08021444:
	movs	r0, #0x0
.L08021446:
	add	sp, #0x2c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0802144c:
	ldr.w	r0, [r8, #0x4]
	ldr	r0, [r0, #0x8]
	adds	r1, r0, r4
	b.n	.L0802143a
.L08021456:
	ldrb	r2, [r1, #0x0]
	ldr	r4, [sp, #0x18]
	lsrs	r2, r6
	ands	r2, r4
	ldrb.w	r4, [r8, #0x14]
	and.w	r4, r4, #0x1f
	cmp	r4, #0xe
	beq.n	.L0802146e
	ldrb.w	r2, [r9, r2]
.L0802146e:
	ldr	r4, [sp, #0x50]
	add.w	r5, r0, r0, lsl #0x1
	add	r4, r5
	strb	r2, [r4, #0x2]
	sub.w	r2, r6, r10
	sxtb	r6, r2
	cmp	r6, #0x0
	bge.n	.L08021486
	mov	r6, r3
	.inst.n	0x1c49		@ adds r1, r1, #1
.L08021486:
	.inst.n	0x1c40		@ adds r0, r0, #1
	sxth	r0, r0
.L0802148a:
	ldr	r2, [sp, #0x28]
	cmp	r0, r2
	blt.n	.L08021456
	mov	r0, r11
	bl	fn_08022c44
	movs	r0, #0x1
	b.n	.L08021446
	.short	0x0000		@ padding
.L0802149c:
	.word	0x0000ff00		@ 1-bit lookup table, entries 0x00 and 0xff
.L080214a0:
	.word	0xffaa5500		@ 2-bit lookup table, entries 0x00 0x55 0xaa 0xff
.L080214a4:
	.word	0x33221100		@ 4-bit lookup table, entries 0x00 .. 0x33
	.word	0x77665544		@ entries 0x44 .. 0x77
	.word	0xbbaa9988		@ entries 0x88 .. 0xbb
	.word	0xffeeddcc		@ entries 0xcc .. 0xff
