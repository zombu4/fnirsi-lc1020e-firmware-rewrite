@ gfx_14.s - image row readers and image object release, and the 565 alpha blit routines
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080214b4 - reads one row segment of a palette image into a 3 bytes per
@ pixel buffer.
@ r0 = image object, r1 = x, r2 = row, r3 = pixel count, stack (after the
@ 13 pushed words and the 4 byte local: sp+0x38) = output buffer. Returns 1 on
@ success, 0 when fn_08022bac fails.
@ Format = word [r0+0x14] & 0x1f: 7, 8, 9, 10 select 1, 2, 4, 8 bits per pixel
@ with data offsets 8, 0x10, 0x40, 0x400. The bits per pixel come from
@ fn_08021168(format); the row length in bytes is derived from the bit field
@ (word [r0+0x14] >> 10) & 0x7ff.
@ The row is read from memory (word at [[r0+4]+8] plus the offset) when byte
@ [r0+0x10] is 0, otherwise through the handle at [r0+0x24] (fn_08020c9c seeks
@ to offset+4, fn_08020b32 reads the row into the buffer from fn_08022bac).
@ Per pixel it looks up the halfword colour at table [[handle]+0xc] and the
@ alpha byte at table [[handle]+0x10], and writes colour low byte, colour high
@ byte, alpha byte. The row buffer is freed with fn_08022c44.
@ ----------------------------------------------------------------------------
	.section .text.fn_080214b4,"ax",%progbits
	.p2align 2
	.global fn_080214b4
	.thumb_func
	.type fn_080214b4, %function
fn_080214b4:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r8, r0
	ldrb	r0, [r0, #0x14]
	sub	sp, #4
	mov	r9, r2
	mov	r6, r1
	and.w	r0, r0, #0x1f
	bl	fn_08021168
	mov	r10, r0
	movs	r1, #1
	lsl.w	r1, r1, r10
	.inst.n	0x1e49	@ subs r1, r1, #1
	movs	r5, #0
	ldr.w	r0, [r8, #0x14]
	uxth.w	r11, r1
	and.w	r1, r0, #0x1f
	mov	r7, r5
	mov	r4, r5
	cmp	r1, #7
	beq.n	.L080214f8
	cmp	r1, #8
	beq.n	.L08021514
	cmp	r1, #9
	beq.n	.L08021532
	cmp	r1, #0xa
	bne.n	.L0802155c
	b.n	.L08021550
.L080214f8:
	@ format 7: 1 bit per pixel, data offset 8
	ubfx	r0, r0, #0xa, #0xb
	.inst.n	0x1dc0	@ adds r0, r0, #7
	lsrs	r5, r0, #3
	add.w	r1, r4, r6, asr #3
	smlabb	r4, r5, r9, r1
	and.w	r0, r6, #7
	rsb.w	r7, r0, #7
	adds	r4, #8
	b.n	.L0802155c
.L08021514:
	@ format 8: 2 bits per pixel, data offset 0x10
	ubfx	r0, r0, #0xa, #0xb
	.inst.n	0x1cc0	@ adds r0, r0, #3
	lsrs	r5, r0, #2
	add.w	r1, r4, r6, asr #2
	smlabb	r4, r5, r9, r1
	movs	r1, #6
	and.w	r0, r6, #3
	sub.w	r7, r1, r0, lsl #1
	adds	r4, #0x10
	b.n	.L0802155c
.L08021532:
	@ format 9: 4 bits per pixel, data offset 0x40
	ubfx	r0, r0, #0xa, #0xb
	.inst.n	0x1c40	@ adds r0, r0, #1
	lsrs	r5, r0, #1
	add.w	r1, r4, r6, asr #1
	smlabb	r4, r5, r9, r1
	movs	r1, #4
	and.w	r0, r6, #1
	sub.w	r7, r1, r0, lsl #2
	adds	r4, #0x40
	b.n	.L0802155c
.L08021550:
	@ format 10: 8 bits per pixel, data offset 0x400
	ubfx	r5, r0, #0xa, #0xb
	smlabb	r4, r5, r9, r6
	add.w	r4, r4, #0x400
.L0802155c:
	mov	r0, r5
	ldr.w	r9, [r8, #0x24]
	bl	fn_08022bac
	subs	r6, r0, #0
	beq.n	.L080215ec
	ldrb.w	r0, [r8, #0x10]
	cbz	r0, .L0802158c
	movs	r2, #0
	adds	r1, r4, #4
	mov	r0, r9
	bl	fn_08020c9c
	movs	r3, #0
	mov	r2, r5
	mov	r1, r6
	mov	r0, r9
	bl	fn_08020b32
	mov	r1, r6
.L08021588:
	movs	r0, #0
	b.n	.L080215de
.L0802158c:
	ldr.w	r0, [r8, #4]
	ldr	r0, [r0, #8]
	adds	r1, r0, r4
	b.n	.L08021588
.L08021596:
	ldrb	r2, [r1, #0]
	ldr.w	r3, [r9, #0xc]
	lsrs	r2, r7
	and.w	r2, r2, r11
	add.w	r3, r3, r2, lsl #1
	ldr	r5, [sp, #0x38]
	ldrh	r3, [r3, #0]
	add.w	r4, r0, r0, lsl #1
	strh.w	r3, [sp, #0]
	strb	r3, [r5, r4]
	ldrh.w	r3, [sp, #0]
	lsrs	r5, r3, #8
	ldr	r3, [sp, #0x38]
	add	r3, r4
	strb	r5, [r3, #1]
	ldr.w	r4, [r9, #0x10]
	ldrb	r2, [r4, r2]
	strb	r2, [r3, #2]
	sub.w	r2, r7, r10
	sxtb	r7, r2
	cmp	r7, #0
	bge.n	.L080215da
	rsb.w	r2, r10, #8
	sxtb	r7, r2
	.inst.n	0x1c49	@ adds r1, r1, #1
.L080215da:
	.inst.n	0x1c40	@ adds r0, r0, #1
	sxth	r0, r0
.L080215de:
	ldr	r2, [sp, #0x10]
	cmp	r0, r2
	blt.n	.L08021596
	mov	r0, r6
	bl	fn_08022c44
	movs	r0, #1
.L080215ec:
	add	sp, #0x14
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_080215f4 - prepares an image object for reading: loads the palette tables
@ or records the data pointer, depending on the format.
@ r0 = target (kept in r6, passed to fn_08021244 on failure), r1 = image object
@ (r4); r2 and r3 are not read (their push slots at sp+4 and sp+8 are
@ overwritten). Returns 1 on success, 0 on failure.
@ Mode = byte [r1+0x10]: 1 goes to the file path, 0 to the memory path, any
@ other value goes straight to the format switch.
@ Mode 1: fn_08020a84(word [r1+4]) returns the extension, string_compare(
@ extension, "bin") must return 0, fn_08020abc(sp, word [r1+4], 2) must return
@ 0, otherwise return 0. When word [r1+0x24] is 0 it is set to
@ fn_08022b50(0x14) (null: fn_08020a1e(sp) and return 0) and cleared with
@ clear_bytes(ptr, 0x14). The 12 bytes at sp are then copied to that block.
@ Mode 0: returns 0 when the word at [[r1+4]+8] is 0.
@ Format f = byte [r1+0x14] & 0x1f: f = 4, 5, 6, 0x14 or 0xe: in mode 0 the word
@ [[r1+4]+8] is stored into [r1+0x18], then 1 is returned (other modes return 1).
@ f = 0xb, 0xc, 0xd return 1. Any other f calls fn_08021244(r0, r1) and returns 0.
@ f = 7..10: n = 1 << fn_08021168(f) (2, 4, 16, 256 entries). Allocates the
@ 0x14-byte block as above when [r1+0x24] is 0 (null returns 0). Colour table =
@ fn_08022b50(2*n) into block word +0xc, alpha table = fn_08022b50(n) into block
@ word +0x10. A null table calls fn_08021244(r0, r1) and returns 0.
@ Entries, mode 1: fn_08020c9c(block, 4, 0), then for i = 0..n-1:
@ fn_08020b32(block, sp, 4, 0) reads 4 bytes, colour[i] = low 16 bits of
@ rgb_to_565_0801d942(byte2, byte1, byte0), alpha[i] = byte3.
@ Other modes: the same from the words at [[r1+4]+8], 4 bytes per entry, colour
@ halfword at colour + 2*i, alpha byte at alpha + i; then returns 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_080215f4,"ax",%progbits
	.p2align 2
	.global fn_080215f4
	.thumb_func
	.type fn_080215f4, %function
fn_080215f4:
	push.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, lr}
	mov	r6, r0
	ldrb	r0, [r1, #0x10]
	mov	r4, r1
	cmp	r0, #1
	beq.n	.L08021606
	cbz	r0, .L08021656
	b.n	.L0802165e
.L08021606:
	ldr	r0, [r4, #4]
	bl	fn_08020a84
	adr	r1, .L08021778
	bl	string_compare
	cmp	r0, #0
	bne.n	.L08021654
	movs	r2, #2
	mov	r0, sp
	ldr	r1, [r4, #4]
	bl	fn_08020abc
	cmp	r0, #0
	bne.n	.L08021654
	ldr	r0, [r4, #0x24]
	cbnz	r0, .L08021638
	movs	r0, #0x14
	bl	fn_08022b50
	str	r0, [r4, #0x24]
	cbz	r0, .L0802164e
	movs	r1, #0x14
	bl	clear_bytes
.L08021638:
	ldr.w	r0, [r4, #0x24]
	mov	r1, sp
	movs	r2, #0xc
.L08021640:
	ldrb.w	r3, [r1], #1
	strb.w	r3, [r0], #1
	.inst.n	0x1e52	@ subs r2, r2, #1
	bne.n	.L08021640
	b.n	.L0802165e
.L0802164e:
	mov	r0, sp
	bl	fn_08020a1e
.L08021654:
	b.n	.L08021772
.L08021656:
	ldr	r0, [r4, #4]
	ldr	r0, [r0, #8]
	cmp	r0, #0
	beq.n	.L08021756
.L0802165e:
	ldrb	r0, [r4, #0x14]
	and.w	r0, r0, #0x1f
	cmp	r0, #4
	beq.n	.L08021696
	cmp	r0, #5
	beq.n	.L08021696
	cmp	r0, #6
	beq.n	.L08021696
	cmp	r0, #0x14
	beq.n	.L08021696
	cmp	r0, #0xe
	beq.n	.L08021696
	cmp	r0, #7
	beq.n	.L080216a2
	cmp	r0, #8
	beq.n	.L080216a2
	cmp	r0, #9
	beq.n	.L080216a2
	cmp	r0, #0xa
	beq.n	.L080216a2
	cmp	r0, #0xb
	beq.n	.L08021764
	cmp	r0, #0xc
	beq.n	.L08021764
	cmp	r0, #0xd
	beq.n	.L08021764
	b.n	.L0802176a
.L08021696:
	ldrb	r0, [r4, #0x10]
	cbnz	r0, .L08021718
	ldr	r0, [r4, #4]
	ldr	r0, [r0, #8]
	str	r0, [r4, #0x18]
	b.n	.L08021764
.L080216a2:
	bl	fn_08021168
	movs	r7, #1
	lsls	r7, r0
	ldr	r0, [r4, #0x24]
	cbnz	r0, .L080216c0
	movs	r0, #0x14
	bl	fn_08022b50
	str	r0, [r4, #0x24]
	cmp	r0, #0
	beq.n	.L08021766
	movs	r1, #0x14
	bl	clear_bytes
.L080216c0:
	lsls	r0, r7, #1
	ldr	r5, [r4, #0x24]
	bl	fn_08022b50
	str	r0, [r5, #0xc]
	mov	r0, r7
	bl	fn_08022b50
	str	r0, [r5, #0x10]
	ldr	r1, [r5, #0xc]
	cbz	r1, .L08021754
	cbz	r0, .L08021754
	ldrb	r0, [r4, #0x10]
	cmp	r0, #1
	beq.n	.L080216e8
	ldr	r0, [r4, #4]
	movs	r4, #0
	ldr.w	r8, [r0, #8]
	b.n	.L08021760
.L080216e8:
	movs	r2, #0
	movs	r1, #4
	mov	r0, r5
	bl	fn_08020c9c
	movs	r4, #0
	b.n	.L0802172e
.L080216f6:
	movs	r3, #0
	movs	r2, #4
	mov	r1, sp
	mov	r0, r5
	bl	fn_08020b32
	ldrb.w	r2, [sp, #0]
	ldrb.w	r1, [sp, #1]
	ldrb.w	r0, [sp, #2]
	bl	rgb_to_565_0801d942
	str	r0, [sp, #4]
	ldr	r0, [r5, #0xc]
	b.n	.L0802171a
.L08021718:
	b.n	.L08021764
.L0802171a:
	add.w	r0, r0, r4, lsl #1
	ldrh.w	r1, [sp, #4]
	strh	r1, [r0, #0]
	ldr	r1, [r5, #0x10]
	ldrb.w	r0, [sp, #3]
	strb	r0, [r1, r4]
	.inst.n	0x1c64	@ adds r4, r4, #1
.L0802172e:
	cmp	r4, r7
	bcc.n	.L080216f6
	b.n	.L08021764
.L08021734:
	add.w	r6, r8, r4, lsl #2
	ldrb.w	r2, [r8, r4, lsl #2]
	ldrb	r1, [r6, #1]
	ldrb	r0, [r6, #2]
	bl	rgb_to_565_0801d942
	str	r0, [sp, #0]
	ldr	r0, [r5, #0xc]
	ldrh.w	r1, [sp, #0]
	add.w	r0, r0, r4, lsl #1
	strh	r1, [r0, #0]
	b.n	.L08021758
.L08021754:
	b.n	.L0802176a
.L08021756:
	b.n	.L08021766
.L08021758:
	ldr	r1, [r5, #0x10]
	ldrb	r0, [r6, #3]
	strb	r0, [r1, r4]
	.inst.n	0x1c64	@ adds r4, r4, #1
.L08021760:
	cmp	r4, r7
	bcc.n	.L08021734
.L08021764:
	movs	r0, #1
.L08021766:
	pop.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, pc}
.L0802176a:
	mov	r1, r4
	mov	r0, r6
	bl	fn_08021244
.L08021772:
	movs	r0, #0
	b.n	.L08021766
	.short	0x0000	@ padding
.L08021778:
	.asciz	"bin"	@ extension compared against the file name extension

@ ----------------------------------------------------------------------------
@ fn_0802177c - reads count pixels of one row of an image object into a buffer.
@ r1 = image object, r2 = x, r3 = row, stack (after the 10 pushed words, sp+0x28
@ and sp+0x2c) = pixel count, output buffer. Returns 1 on success, 0 on failure.
@ Format = byte [r1+0x14] & 0x1f: 4, 5, 6 read directly from the file handle at
@ [r1+0x24] (mode byte [r1+0x10] must be 1) after fn_08020c9c to offset
@ ((bits * (row * width + x)) >> 3) + 4, with fn_08020b32 of (bits >> 3) * count
@ bytes (bits from fn_08021168, width from the bit field (word [r1+0x14] >> 10)
@ & 0x7ff); 0xb to 0xe call fn_08021324; 7 to 10 call fn_080214b4; other formats
@ return 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802177c,"ax",%progbits
	.global fn_0802177c
	.thumb_func
	.type fn_0802177c, %function
fn_0802177c:
	push.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r4, r1
	mov	r5, r3
	mov	r6, r2
	ldrb	r0, [r4, #0x14]
	ldrd	r3, r2, [sp, #0x28]
	movs	r1, #0
	and.w	r0, r0, #0x1f
	cmp	r0, #4
	beq.n	.L080217c4
	cmp	r0, #5
	beq.n	.L080217c4
	cmp	r0, #6
	beq.n	.L080217c4
	cmp	r0, #0xb
	beq.n	.L08021816
	cmp	r0, #0xc
	beq.n	.L08021816
	cmp	r0, #0xd
	beq.n	.L08021816
	cmp	r0, #0xe
	beq.n	.L08021816
	cmp	r0, #7
	beq.n	.L08021824
	cmp	r0, #8
	beq.n	.L08021824
	cmp	r0, #9
	beq.n	.L08021824
	cmp	r0, #0xa
	beq.n	.L08021824
	movs	r0, #0
.L080217c0:
	pop.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L080217c4:
	ldrb	r7, [r4, #0x10]
	cmp	r7, #1
	bne.n	.L08021832
	mov	r8, r3
	mov	r9, r2
	ldr.w	r10, [r4, #0x24]
	bl	fn_08021168
	mov	r7, r0
	ldr	r0, [r4, #0x14]
	ubfx	r0, r0, #0xa, #0xb
	smlabb	r0, r5, r0, r6
	muls	r0, r7, r0
	asrs	r1, r0, #3
	movs	r2, #0
	mov	r0, r10
	.inst.n	0x1d09	@ adds r1, r1, #4
	bl	fn_08020c9c
	movs	r4, #0
	cbnz	r0, .L08021812
	lsrs	r5, r7, #3
	mul	r5, r5, r8
	mov	r3, sp
	mov	r2, r5
	mov	r1, r9
	mov	r0, r10
	str	r4, [sp, #0]
	bl	fn_08020b32
	cbnz	r0, .L08021812
	ldr	r0, [sp, #0]
	cmp	r5, r0
	bne.n	.L08021812
	movs	r4, #1
.L08021812:
	mov	r1, r4
	b.n	.L08021832
.L08021816:
	str	r2, [sp, #0]
	mov	r2, r5
	mov	r1, r6
	mov	r0, r4
	bl	fn_08021324
	b.n	.L08021830
.L08021824:
	str	r2, [sp, #0]
	mov	r2, r5
	mov	r1, r6
	mov	r0, r4
	bl	fn_080214b4
.L08021830:
	mov	r1, r0
.L08021832:
	mov	r0, r1
	b.n	.L080217c0

@ ----------------------------------------------------------------------------
@ fn_08021836 - releases an image object.
@ r0 = image object; no return value. When word [r0] is nonzero: calls the slot
@ at +0xc of it, when set, with (word [r0], r0), and when byte [r0+0x10] is 1
@ frees word [r0+4] with fn_08022c68 and clears it.
@ ----------------------------------------------------------------------------
	.section .text.fn_08021836,"ax",%progbits
	.global fn_08021836
	.thumb_func
	.type fn_08021836, %function
fn_08021836:
	push	{r4, lr}
	mov	r4, r0
	ldr	r0, [r0, #0]
	cmp	r0, #0
	beq.n	.L08021858
	ldr	r2, [r0, #0xc]
	cbz	r2, .L08021848
	mov	r1, r4
	blx	r2
.L08021848:
	ldrb	r0, [r4, #0x10]
	cmp	r0, #1
	bne.n	.L08021858
	ldr	r0, [r4, #4]
	bl	fn_08022c68
	movs	r0, #0
	str	r0, [r4, #4]
.L08021858:
	pop	{r4, pc}
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_080283c8 - blends a source halfword (565) rectangle onto a destination
@ with a blend function chosen by mode, optional per-pixel mask.
@ r0 = destination pixels (halfwords), r1 = rectangle (halfwords left, top,
@ right, bottom), r2 = destination row stride in halfwords, r3 = source pixels;
@ stack (sp+0x60 after the prologue): source row stride in halfwords, alpha,
@ mask pointer (0 = none), mask row stride, mode. No return value.
@ Width and height are right-left+1 and bottom-top+1 (signed 16 bit).
@ Mode 1, 2 or 3 selects the pixel blend function fn_08014a26, fn_08014b00 or
@ fn_08014a9a (literal pool at the end); other modes return.
@ Without a mask every pixel is blended with the alpha, recomputing only when
@ the source or destination pixel changes. With a mask it skips pixels whose
@ mask byte is 0, and uses the alpha scaled as alpha*mask>>8 for mask bytes
@ below 0xfd and the full alpha otherwise (the result is reused while source,
@ destination and weight stay the same). Each row advances the destination and
@ source by their strides (halfwords) and the mask by its stride (bytes).
@ ----------------------------------------------------------------------------
	.section .text.fn_080283c8,"ax",%progbits
	.p2align 2
	.global fn_080283c8
	.thumb_func
	.type fn_080283c8, %function
fn_080283c8:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r5, r3
	ldrh	r2, [r1, #4]
	ldrh	r3, [r1, #0]
	sub	sp, #0x2c
	subs	r2, r2, r3
	.inst.n	0x1c52	@ adds r2, r2, #1
	sxth	r7, r2
	ldrh	r2, [r1, #6]
	ldrh	r1, [r1, #2]
	mov	r4, r0
	subs	r1, r2, r1
	.inst.n	0x1c49	@ adds r1, r1, #1
	ldr	r0, [sp, #0x70]
	ldr.w	r10, [sp, #0x68]
	sxth.w	r9, r1
	cmp	r0, #1
	beq.n	.L080283fe
	cmp	r0, #2
	beq.n	.L08028402
	cmp	r0, #3
	bne.n	.L08028496
	ldr	r0, .L08028538
	b.n	.L08028404
.L080283fe:
	ldr	r0, .L0802853c
	b.n	.L08028404
.L08028402:
	ldr	r0, .L08028540
.L08028404:
	mov	r8, r0
	movs.w	r0, r10
	ldrh	r0, [r4, #0]
	strh.w	r0, [sp, #4]
	ldrh	r0, [r5, #0]
	strh.w	r0, [sp, #8]
	beq.n	.L08028424
	ldrb.w	r0, [r10, #0]
	cmp	r0, #0xfd
	bcc.n	.L0802849c
	ldr	r0, [sp, #0x64]
	b.n	.L080284a2
.L08028424:
	ldrd	r1, r0, [sp, #4]
	mov	r3, r8
	ldr	r2, [sp, #0x64]
	blx	r3
	str	r0, [sp, #0]
	movs	r0, #0
	b.n	.L08028490
.L08028434:
	movs	r6, #0
	b.n	.L0802847c
.L08028438:
	ldrh.w	r0, [sp, #8]
	ldrh.w	r1, [r5, r6, lsl #1]
	cmp	r0, r1
	bne.n	.L08028450
	ldrh.w	r0, [sp, #4]
	ldrh.w	r1, [r4, r6, lsl #1]
	cmp	r0, r1
	beq.n	.L08028470
.L08028450:
	add.w	r0, r4, r6, lsl #1
	mov	r3, r8
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #4]
	add.w	r0, r5, r6, lsl #1
	ldr	r2, [sp, #0x64]
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #8]
	ldrd	r1, r0, [sp, #4]
	blx	r3
	str	r0, [sp, #0]
.L08028470:
	add.w	r0, r4, r6, lsl #1
	ldrh.w	r1, [sp, #0]
	strh	r1, [r0, #0]
	.inst.n	0x1c76	@ adds r6, r6, #1
.L0802847c:
	cmp	r6, r7
	blt.n	.L08028438
	ldr	r0, [sp, #0x34]
	add.w	r4, r4, r0, lsl #1
	ldr	r0, [sp, #0x60]
	add.w	r5, r5, r0, lsl #1
	add.w	r0, r10, #1
.L08028490:
	mov	r10, r0
	cmp	r0, r9
	blt.n	.L08028434
.L08028496:
	add	sp, #0x3c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0802849c:
	ldr	r1, [sp, #0x64]
	muls	r0, r1, r0
	lsrs	r0, r0, #8
.L080284a2:
	mov	r2, r0
	str	r0, [sp, #0]
	ldrd	r1, r0, [sp, #4]
	mov	r3, r8
	blx	r3
	str	r0, [sp, #0x24]
	movs	r0, #0
	b.n	.L08028530
.L080284b4:
	movs	r6, #0
	b.n	.L08028518
.L080284b8:
	ldrb.w	r0, [r10, r6]
	cbz	r0, .L08028516
	cmp	r0, #0xfd
	bcc.n	.L080284c6
	ldr	r0, [sp, #0x64]
	b.n	.L080284cc
.L080284c6:
	ldr	r1, [sp, #0x64]
	muls	r0, r1, r0
	lsrs	r0, r0, #8
.L080284cc:
	ldrh.w	r1, [sp, #8]
	ldrh.w	r2, [r5, r6, lsl #1]
	cmp	r1, r2
	bne.n	.L080284ea
	ldrh.w	r1, [sp, #4]
	ldrh.w	r2, [r4, r6, lsl #1]
	cmp	r1, r2
	bne.n	.L080284ea
	ldr	r1, [sp, #0]
	cmp	r1, r0
	beq.n	.L0802850c
.L080284ea:
	add.w	r1, r4, r6, lsl #1
	mov	r2, r0
	ldrh	r1, [r1, #0]
	strh.w	r1, [sp, #4]
	add.w	r1, r5, r6, lsl #1
	mov	r3, r8
	ldrh	r1, [r1, #0]
	strh.w	r1, [sp, #8]
	str	r0, [sp, #0]
	ldrd	r1, r0, [sp, #4]
	blx	r3
	str	r0, [sp, #0x24]
.L0802850c:
	add.w	r0, r4, r6, lsl #1
	ldrh.w	r1, [sp, #0x24]
	strh	r1, [r0, #0]
.L08028516:
	.inst.n	0x1c76	@ adds r6, r6, #1
.L08028518:
	cmp	r6, r7
	blt.n	.L080284b8
	ldr	r0, [sp, #0x34]
	add.w	r4, r4, r0, lsl #1
	ldr	r0, [sp, #0x60]
	add.w	r5, r5, r0, lsl #1
	ldr	r0, [sp, #0x6c]
	add	r10, r0
	add.w	r0, r11, #1
.L08028530:
	mov	r11, r0
	cmp	r0, r9
	blt.n	.L080284b4
	b.n	.L08028496
.L08028538:
	.word	fn_08014a9a	@ blend function for mode 3
.L0802853c:
	.word	fn_08014a26	@ blend function for mode 1
.L08028540:
	.word	fn_08014b00	@ blend function for mode 2

@ ----------------------------------------------------------------------------
@ blit_565_alpha_mask - copies or alpha-blends a source halfword (565) rectangle
@ onto a destination, optionally through a mask.
@ r0 = destination pixels (halfwords, kept in r6), r1 = rectangle pointer
@ (halfwords left, top, right, bottom), r2 = destination row stride in halfwords
@ (saved at sp+0x34), r3 = source pixels (r5); stack word 0 = source row stride
@ in halfwords (sp+0x60), stack word 1 = alpha (r11), stack word 2 = mask
@ pointer or 0 (r10), stack word 3 = mask row stride in bytes (sp+0x6c). No
@ return value.
@ Width r7 = right-left+1, height r8 = bottom-top+1 (signed 16 bit). Every row
@ advances the destination by stride*2 bytes, the source by source stride*2
@ bytes and (with mask) the mask by the mask stride.
@ No mask, alpha >= 0xfd: per row copy_bytes_08022ce0(destination, source,
@ width*2) copies the row.
@ No mask, alpha < 0xfd: per pixel blend_565_0801d9dc(source pixel, destination
@ pixel, alpha) and the result halfword is stored at the destination.
@ Mask, alpha <= 0xfd: per pixel with mask byte m: m == 0 skips; the weight is
@ the alpha when m >= 0xfd, else (m*alpha) >> 8; stores blend_565_0801d9dc(
@ source, destination, weight).
@ Mask, alpha >= 0xfe: r11 = width-4; a first loop steps single mask bytes while
@ the mask pointer & 3 != 0 and x < width; then a word loop while x < width-4
@ reads an aligned 4-byte mask word: word 0 skips 4 pixels, word 0xffffffff
@ copies 4 halfwords from source to destination, otherwise each of its four
@ bytes is handled singly; the tail loop handles the remaining bytes. A single
@ mask byte b: 0 skips, 0xff copies the source halfword, any other value stores
@ blend_565_0801d9dc(source, destination, b).
@ Every row loop leaves through the epilogue at .L080285a2 (add sp, #0x3c, pop).
@ The three nops at 0x080285fe, 0x0802877a and 0x080287e6 are padding that no
@ path executes.
@ ----------------------------------------------------------------------------
	.section .text.blit_565_alpha_mask,"ax",%progbits
	.p2align 2
	.global blit_565_alpha_mask
	.thumb_func
	.type blit_565_alpha_mask, %function
blit_565_alpha_mask:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r6, r0
	ldrh	r2, [r1, #4]
	ldrh	r0, [r1, #0]
	sub	sp, #0x2c
	subs	r0, r2, r0
	.inst.n	0x1c40	@ adds r0, r0, #1
	sxth	r7, r0
	ldrh	r2, [r1, #6]
	ldrh	r0, [r1, #2]
	ldrd	r11, r10, [sp, #0x64]
	subs	r0, r2, r0
	.inst.n	0x1c40	@ adds r0, r0, #1
	sxth.w	r8, r0
	movs.w	r0, r10
	mov	r5, r3
	mov	r0, r11
	beq.n	.L0802857c
	cmp	r0, #0xfd
	bls.n	.L0802866e
	sub.w	r11, r7, #4
	movs	r0, #0
	b.n	.L080287cc
.L0802857c:
	cmp	r0, #0xfd
	bcc.n	.L080285a8
	movs	r4, #0
	lsls	r7, r7, #1
	b.n	.L0802859e
.L08028586:
	mov	r2, r7
	mov	r1, r5
	mov	r0, r6
	bl	copy_bytes_08022ce0
	ldr	r0, [sp, #0x34]
	.inst.n	0x1c64	@ adds r4, r4, #1
	add.w	r6, r6, r0, lsl #1
	ldr	r0, [sp, #0x60]
	add.w	r5, r5, r0, lsl #1
.L0802859e:
	cmp	r4, r8
	blt.n	.L08028586
.L080285a2:
	add	sp, #0x3c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L080285a8:
	movs	r0, #0
	b.n	.L080285f0
.L080285ac:
	movs	r4, #0
	b.n	.L080285dc
.L080285b0:
	add.w	r10, r6, r4, lsl #1
	mov	r2, r11
	ldrh.w	r0, [r10, #0]
	strh.w	r0, [sp, #0x18]
	add.w	r0, r5, r4, lsl #1
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #0x14]
	ldrd	r0, r1, [sp, #0x14]
	bl	blend_565_0801d9dc
	str	r0, [sp, #0x14]
	ldrh.w	r1, [sp, #0x14]
	strh.w	r1, [r10, #0]
	.inst.n	0x1c64	@ adds r4, r4, #1
.L080285dc:
	cmp	r4, r7
	blt.n	.L080285b0
	ldr	r0, [sp, #0x34]
	add.w	r6, r6, r0, lsl #1
	ldr	r0, [sp, #0x60]
	add.w	r5, r5, r0, lsl #1
	add.w	r0, r9, #1
.L080285f0:
	mov	r9, r0
	cmp	r0, r8
	blt.n	.L080285ac
	b.n	.L080285a2
.L080285f8:
	mov	r9, r10
	movs	r4, #0
	b.n	.L08028638
	nop	@ padding
	@ single mask byte loop: mask pointer r9, x in r4
.L08028600:
	ldrb.w	r2, [r9, #0]
	cbz	r2, .L08028632
	cmp	r2, #0xff
	add.w	r0, r6, r4, lsl #1
	beq.n	.L08028644
	str	r0, [sp, #0x24]
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #0x20]
	add.w	r0, r5, r4, lsl #1
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #0x1c]
	ldrd	r0, r1, [sp, #0x1c]
	bl	blend_565_0801d9dc
	str	r0, [sp, #0x18]
	ldrh.w	r1, [sp, #0x18]
	ldr	r0, [sp, #0x24]
.L08028630:
	strh	r1, [r0, #0]
.L08028632:
	add.w	r9, r9, #1
	.inst.n	0x1c64	@ adds r4, r4, #1
.L08028638:
	cmp	r4, r7
	bge.n	.L08028736
	lsls.w	r0, r9, #0x1e
	bne.n	.L08028600
	b.n	.L08028736
.L08028644:
	add.w	r1, r5, r4, lsl #1
	ldrh	r1, [r1, #0]
	b.n	.L08028630
	@ word loop: reads the aligned mask word at r9
.L0802864c:
	ldr.w	r0, [r9, #0]
	cbz	r0, .L080286d0
	.inst.n	0x1c40	@ adds r0, r0, #1
	beq.n	.L08028740
	ldrb.w	r2, [r9, #0]
	cbz	r2, .L0802868c
	cmp	r2, #0xff
	add.w	r0, r6, r4, lsl #1
	beq.n	.L0802875a
	str	r0, [sp, #0x24]
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #0x20]
	b.n	.L08028670
.L0802866e:
	b.n	.L080287de
.L08028670:
	add.w	r0, r5, r4, lsl #1
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #0x1c]
	ldrd	r0, r1, [sp, #0x1c]
	bl	blend_565_0801d9dc
	str	r0, [sp, #0x18]
	ldrh.w	r1, [sp, #0x18]
	ldr	r0, [sp, #0x24]
.L0802868a:
	strh	r1, [r0, #0]
.L0802868c:
	add.w	r0, r9, #1
	str	r0, [sp, #0x14]
	ldrb.w	r2, [r9, #1]
	cbz	r2, .L080286c4
	cmp	r2, #0xff
	add.w	r0, r6, r4, lsl #1
	beq.n	.L08028762
	str	r0, [sp, #0x24]
	ldrh	r0, [r0, #2]
	strh.w	r0, [sp, #0x20]
	add.w	r0, r5, r4, lsl #1
	ldrh	r0, [r0, #2]
	strh.w	r0, [sp, #0x1c]
	ldrd	r0, r1, [sp, #0x1c]
	bl	blend_565_0801d9dc
	str	r0, [sp, #0x18]
	ldrh.w	r1, [sp, #0x18]
	ldr	r0, [sp, #0x24]
.L080286c2:
	strh	r1, [r0, #2]
.L080286c4:
	ldr	r0, [sp, #0x14]
	.inst.n	0x1c40	@ adds r0, r0, #1
	str	r0, [sp, #0x14]
	ldrb	r2, [r0, #0]
	cbz	r2, .L080286fe
	b.n	.L080286d2
.L080286d0:
	b.n	.L08028730
.L080286d2:
	cmp	r2, #0xff
	add.w	r0, r6, r4, lsl #1
	beq.n	.L0802876a
	str	r0, [sp, #0x24]
	ldrh	r0, [r0, #4]
	strh.w	r0, [sp, #0x20]
	add.w	r0, r5, r4, lsl #1
	ldrh	r0, [r0, #4]
	strh.w	r0, [sp, #0x1c]
	ldrd	r0, r1, [sp, #0x1c]
	bl	blend_565_0801d9dc
	str	r0, [sp, #0x18]
	ldrh.w	r1, [sp, #0x18]
	ldr	r0, [sp, #0x24]
.L080286fc:
	strh	r1, [r0, #4]
.L080286fe:
	ldr	r0, [sp, #0x14]
	ldrb	r2, [r0, #1]
	cbz	r2, .L08028730
	cmp	r2, #0xff
	add.w	r0, r6, r4, lsl #1
	beq.n	.L08028772
	str	r0, [sp, #0x14]
	ldrh	r0, [r0, #6]
	strh.w	r0, [sp, #0x20]
	add.w	r0, r5, r4, lsl #1
	ldrh	r0, [r0, #6]
	strh.w	r0, [sp, #0x1c]
	ldrd	r0, r1, [sp, #0x1c]
	bl	blend_565_0801d9dc
	str	r0, [sp, #0x18]
	ldrh.w	r1, [sp, #0x18]
	ldr	r0, [sp, #0x14]
.L0802872e:
	strh	r1, [r0, #6]
.L08028730:
	add.w	r9, r9, #4
	.inst.n	0x1d24	@ adds r4, r4, #4
.L08028736:
	cmp	r4, r11
	blt.n	.L0802864c
	b.n	.L080287b4
	b.n	.L08028740
	b.n	.L0802875a
.L08028740:
	@ mask word 0xffffffff: copies 4 halfwords from source to destination
	add.w	r0, r5, r4, lsl #1
	add.w	r1, r6, r4, lsl #1
	ldrh	r2, [r0, #0]
	strh	r2, [r1, #0]
	ldrh	r2, [r0, #2]
	strh	r2, [r1, #2]
	ldrh	r2, [r0, #4]
	strh	r2, [r1, #4]
	ldrh	r0, [r0, #6]
	strh	r0, [r1, #6]
	b.n	.L08028730
.L0802875a:
	add.w	r1, r5, r4, lsl #1
	ldrh	r1, [r1, #0]
	b.n	.L0802868a
.L08028762:
	add.w	r1, r5, r4, lsl #1
	ldrh	r1, [r1, #2]
	b.n	.L080286c2
.L0802876a:
	add.w	r1, r5, r4, lsl #1
	ldrh	r1, [r1, #4]
	b.n	.L080286fc
.L08028772:
	add.w	r1, r5, r4, lsl #1
	ldrh	r1, [r1, #6]
	b.n	.L0802872e
	nop	@ padding
	@ tail loop: remaining mask bytes
.L0802877c:
	ldrb.w	r2, [r9, #0]
	cbz	r2, .L080287ae
	cmp	r2, #0xff
	add.w	r0, r6, r4, lsl #1
	beq.n	.L080287d6
	str	r0, [sp, #0x24]
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #0x20]
	add.w	r0, r5, r4, lsl #1
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #0x1c]
	ldrd	r0, r1, [sp, #0x1c]
	bl	blend_565_0801d9dc
	str	r0, [sp, #0x18]
	ldrh.w	r1, [sp, #0x18]
	ldr	r0, [sp, #0x24]
.L080287ac:
	strh	r1, [r0, #0]
.L080287ae:
	add.w	r9, r9, #1
	.inst.n	0x1c64	@ adds r4, r4, #1
.L080287b4:
	cmp	r4, r7
	blt.n	.L0802877c
	ldr	r0, [sp, #0x34]
	ldr	r1, [sp, #0x6c]
	add.w	r6, r6, r0, lsl #1
	ldr	r0, [sp, #0x60]
	add	r10, r1
	add.w	r5, r5, r0, lsl #1
	ldr	r0, [sp, #4]
	.inst.n	0x1c40	@ adds r0, r0, #1
.L080287cc:
	str	r0, [sp, #4]
	cmp	r0, r8
	blt.w	.L080285f8
	b.n	.L080285a2
.L080287d6:
	add.w	r1, r5, r4, lsl #1
	ldrh	r1, [r1, #0]
	b.n	.L080287ac
.L080287de:
	movs	r0, #0
	b.n	.L0802883e
.L080287e2:
	movs	r4, #0
	b.n	.L08028826
	nop	@ padding
	@ mask loop for alpha <= 0xfd: mask pointer r10, x in r4
.L080287e8:
	ldrb.w	r0, [r10, r4]
	cbz	r0, .L08028824
	cmp	r0, #0xfd
	bcc.n	.L080287f6
	mov	r2, r11
	b.n	.L080287fc
.L080287f6:
	mul	r0, r0, r11
	lsrs	r2, r0, #8
.L080287fc:
	add.w	r0, r6, r4, lsl #1
	str	r0, [sp, #0xc]
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #0x18]
	add.w	r0, r5, r4, lsl #1
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #0x14]
	ldrd	r0, r1, [sp, #0x14]
	bl	blend_565_0801d9dc
	str	r0, [sp, #0x14]
	ldr	r0, [sp, #0xc]
	ldrh.w	r1, [sp, #0x14]
	strh	r1, [r0, #0]
.L08028824:
	.inst.n	0x1c64	@ adds r4, r4, #1
.L08028826:
	cmp	r4, r7
	blt.n	.L080287e8
	ldr	r0, [sp, #0x34]
	ldr	r1, [sp, #0x6c]
	add.w	r6, r6, r0, lsl #1
	ldr	r0, [sp, #0x60]
	add	r10, r1
	add.w	r5, r5, r0, lsl #1
	add.w	r0, r9, #1
.L0802883e:
	mov	r9, r0
	cmp	r0, r8
	blt.n	.L080287e2
	b.n	.L080285a2
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_08028848 - draws a source halfword rectangle pixel by pixel through a
@ virtual call, optionally weighted by a mask.
@ r0 = param_1 (stored at sp+0x14), r1 = rectangle pointer (4 shorts: left, top,
@ right, bottom), r2 = param_3 (sp+0x1c), r3 = source halfword array; stack: row
@ stride in halfwords (sp+0x48), value (sp+0x4c), mask pointer (0 = none, r11),
@ mask row stride (sp+0x54). No return value.
@ Calls return_word_200004b8 (0x08012af4) for an object pointer p and uses the
@ function pointer at offset 0x1c of the table *p, called as (*p, param_1,
@ param_3, x, y, pixel, value) for each pixel of the rectangle (width =
@ right-left+1, height = bottom-top+1; x = left + column, y = top + row).
@ Without mask the value is passed unchanged; with mask a mask byte of 0 skips
@ the pixel and other bytes pass value * mask >> 8.
@ Advances the source by stride*2 bytes and the mask by its stride per row.
@ ----------------------------------------------------------------------------
	.section .text.fn_08028848,"ax",%progbits
	.p2align 2
	.global fn_08028848
	.thumb_func
	.type fn_08028848, %function
fn_08028848:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x14
	mov	r10, r3
	mov	r4, r1
	ldr.w	r11, [sp, #0x50]
	bl	return_word_200004b8
	str	r0, [sp, #0xc]
	ldrh	r0, [r4, #4]
	ldrh	r1, [r4, #0]
	subs	r0, r0, r1
	.inst.n	0x1c40	@ adds r0, r0, #1
	sxth	r6, r0
	ldrh	r0, [r4, #6]
	ldrh	r1, [r4, #2]
	subs	r0, r0, r1
	.inst.n	0x1c40	@ adds r0, r0, #1
	sxth.w	r8, r0
	cmp.w	r11, #0
	beq.n	.L0802887c
	movs	r0, #0
	b.n	.L08028914
.L0802887c:
	movs	r7, #0
	b.n	.L080288bc
.L08028880:
	movs	r5, #0
	b.n	.L080288b0
.L08028884:
	ldr	r0, [sp, #0x4c]
	str	r0, [sp, #8]
	add.w	r0, r10, r5, lsl #1
	ldr	r2, [sp, #0x1c]
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #4]
	ldrh	r0, [r4, #2]
	add	r0, r7
	sxth	r0, r0
	str	r0, [sp, #0]
	ldrh	r0, [r4, #0]
	ldr	r1, [sp, #0x14]
	add	r0, r5
	sxth	r3, r0
	ldr	r0, [sp, #0xc]
	ldr	r0, [r0, #0]
	ldr.w	r12, [r0, #0x1c]
	blx	r12
	.inst.n	0x1c6d	@ adds r5, r5, #1
.L080288b0:
	cmp	r5, r6
	blt.n	.L08028884
	ldr	r1, [sp, #0x48]
	.inst.n	0x1c7f	@ adds r7, r7, #1
	add.w	r10, r10, r1, lsl #1
.L080288bc:
	cmp	r7, r8
	blt.n	.L08028880
.L080288c0:
	add	sp, #0x24
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L080288c6:
	movs	r5, #0
	b.n	.L08028902
	nop	@ padding
	@ masked pixel loop: mask pointer r11, column r5
.L080288cc:
	ldrb.w	r0, [r11, r5]
	cbz	r0, .L08028900
	ldr	r1, [sp, #0x4c]
	muls	r0, r1, r0
	lsrs	r0, r0, #8
	str	r0, [sp, #8]
	add.w	r0, r10, r5, lsl #1
	ldr	r2, [sp, #0x1c]
	ldrh	r0, [r0, #0]
	strh.w	r0, [sp, #4]
	ldrh	r1, [r4, #2]
	add.w	r0, r1, r9
	sxth	r0, r0
	str	r0, [sp, #0]
	ldrh	r0, [r4, #0]
	ldr	r1, [sp, #0x14]
	add	r0, r5
	sxth	r3, r0
	ldr	r0, [sp, #0xc]
	ldr	r0, [r0, #0]
	ldr	r7, [r0, #0x1c]
	blx	r7
.L08028900:
	.inst.n	0x1c6d	@ adds r5, r5, #1
.L08028902:
	cmp	r5, r6
	blt.n	.L080288cc
	ldr	r1, [sp, #0x54]
	add.w	r0, r9, #1
	add	r11, r1
	ldr	r1, [sp, #0x48]
	add.w	r10, r10, r1, lsl #1
.L08028914:
	mov	r9, r0
	cmp	r0, r8
	blt.n	.L080288c6
	b.n	.L080288c0

@ ----------------------------------------------------------------------------
@ fn_08028b4c - draws one rectangle of the object at word [0x200004b8], either
@ as a whole or split into bands.
@ r0 = pointer to a rectangle of 4 shorts (left, top, right, bottom).
@ Uses the object pointer at [0x200004b4 + 4] (0x200004b8; base word 0x200004b4
@ from the literal at the end) and the record R = word at offset 0x3c of the
@ first word of that object (*object): stores the word at ((*object)+0xc)+8
@ into R word 0.
@ When bit 0 or bit 1 of the word at (*object)+0x10 is set: builds the
@ rectangle 0, 0, fn_0801dcfc(object)-1, fn_0801dd88(object)-1 with rect_set
@ into [sp+4] and stores its address in R word 1; when bit 1 of the byte at
@ (*object)+0x10 is set it sets bit 1 of the flags word at ((*object)+0xc)+0x18
@ and stores the same address in R word 2, otherwise it copies bit 0 of that
@ flags word into bit 1 (bfi) and stores r0 in R word 2; then calls
@ fn_08028ca8(R) once.
@ Otherwise it splits the rectangle into bands of fn_0801b4e4(object, width,
@ height) lines, up to the bottom row min(rect bottom, fn_0801dd88(object)-1),
@ clamps each band bottom to that row, calls fn_08028ca8(R) for each band and
@ sets bit 1 of the flags word at ((*object)+0xc)+0x18 for the band whose
@ bottom equals that row; a final band to that row is drawn the same way when
@ the loop ended before it.
@ ----------------------------------------------------------------------------
	.section .text.fn_08028b4c,"ax",%progbits
	.p2align 2
	.global fn_08028b4c
	.thumb_func
	.type fn_08028b4c, %function
fn_08028b4c:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	ldr	r6, .L08028ca4
	mov	r5, r0
	sub	sp, #0x24
	ldr	r0, [r6, #4]
	ldr	r1, [r0, #0]
	ldr	r4, [r1, #0x3c]
	ldr	r1, [r1, #0xc]
	ldr	r1, [r1, #8]
	str	r1, [r4, #0]
	ldr	r1, [r0, #0]
	ldr	r1, [r1, #0x10]
	lsls	r2, r1, #0x1e
	bmi.n	.L08028b6e
	lsls	r1, r1, #0x1f
	beq.n	.L08028bb6
.L08028b6e:
	bl	fn_0801dd88
	.inst.n	0x1e40	@ subs r0, r0, #1
	sxth	r7, r0
	ldr	r0, [r6, #4]
	bl	fn_0801dcfc
	.inst.n	0x1e40	@ subs r0, r0, #1
	sxth	r3, r0
	movs	r2, #0
	mov	r1, r2
	add	r0, sp, #4
	str	r7, [sp, #0]
	bl	rect_set
	add	r1, sp, #4
	str	r1, [r4, #4]
	ldr	r0, [r6, #4]
	ldr	r0, [r0, #0]
	ldrb	r2, [r0, #0x10]
	ldr	r0, [r0, #0xc]
	lsls	r2, r2, #0x1e
	bpl.n	.L08028ba8
	ldr	r2, [r0, #0x18]
	orr.w	r2, r2, #2
	str	r2, [r0, #0x18]
	str	r1, [r4, #8]
	b.n	.L08028c96
.L08028ba8:
	ldr	r1, [r0, #0x18]
	ldr	r2, [r0, #0x18]
	bfi	r2, r1, #1, #1
	str	r2, [r0, #0x18]
	str	r5, [r4, #8]
	b.n	.L08028c96
.L08028bb6:
	ldrh	r1, [r5, #4]
	ldrh	r2, [r5, #0]
	subs	r1, r1, r2
	.inst.n	0x1c49	@ adds r1, r1, #1
	sxth.w	r9, r1
	ldrh	r1, [r5, #6]
	ldrh	r2, [r5, #2]
	subs	r1, r1, r2
	.inst.n	0x1c49	@ adds r1, r1, #1
	sxth.w	r8, r1
	bl	fn_0801dd88
	mov	r1, r0
	ldrsh.w	r0, [r5, #6]
	cmp	r1, r0
	bgt.n	.L08028be4
	ldr	r0, [r6, #4]
	bl	fn_0801dd88
	.inst.n	0x1e40	@ subs r0, r0, #1
.L08028be4:
	sxth	r7, r0
	mov	r2, r8
	mov	r1, r9
	mov	r10, r6
	ldr	r0, [r6, #4]
	bl	fn_0801b4e4
	mov	r9, r0
	movs	r6, #0
	ldrsh.w	r0, [r5, #2]
	add.w	r11, sp, #0xc
	b.n	.L08028c52
.L08028c00:
	ldrh	r2, [r5, #0]
	strh.w	r2, [sp, #0xc]
	ldrh	r2, [r5, #4]
	strh.w	r2, [sp, #0x10]
	strh.w	r0, [sp, #0xe]
	strh.w	r1, [sp, #0x12]
	str.w	r11, [r4, #4]
	str.w	r11, [r4, #8]
	ldr.w	r0, [r10, #4]
	ldr	r1, [r0, #0]
	ldr	r1, [r1, #0xc]
	ldr	r1, [r1, #8]
	str	r1, [r4, #0]
	ldrsh.w	r1, [sp, #0x12]
	cmp	r1, r7
	ble.n	.L08028c34
	strh.w	r7, [sp, #0x12]
.L08028c34:
	ldrsh.w	r6, [sp, #0x12]
	cmp	r7, r6
	bne.n	.L08028c48
	ldr	r0, [r0, #0]
	ldr	r0, [r0, #0xc]
	ldr	r1, [r0, #0x18]
	orr.w	r1, r1, #2
	str	r1, [r0, #0x18]
.L08028c48:
	mov	r0, r4
	bl	fn_08028ca8
	sxth.w	r0, r8
.L08028c52:
	add.w	r8, r0, r9
	sub.w	r1, r8, #1
	cmp	r1, r7
	ble.n	.L08028c00
	cmp	r7, r6
	beq.n	.L08028c9c
	ldrh	r1, [r5, #0]
	strh.w	r1, [sp, #0xc]
	ldrh	r1, [r5, #4]
	strh.w	r1, [sp, #0x10]
	strh.w	r0, [sp, #0xe]
	strh.w	r7, [sp, #0x12]
	str.w	r11, [r4, #4]
	str.w	r11, [r4, #8]
	ldr.w	r0, [r10, #4]
	ldr	r1, [r0, #0]
	ldr	r1, [r1, #0xc]
	ldr	r1, [r1, #8]
	str	r1, [r4, #0]
	ldr	r0, [r0, #0]
	ldr	r0, [r0, #0xc]
	ldr	r1, [r0, #0x18]
	orr.w	r1, r1, #2
	str	r1, [r0, #0x18]
.L08028c96:
	mov	r0, r4
	bl	fn_08028ca8
.L08028c9c:
	add	sp, #0x24
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short	0x0000	@ padding
.L08028ca4:
	.word	0x200004b4	@ base word; the object pointer is read from [base+4] (0x200004b8)

@ ----------------------------------------------------------------------------
@ fn_08028ca8 - draws the background and layers of one draw record.
@ r0 = draw record pointer (r7; word +4 = clip, word +0x2c = callback).
@ Using the object at [0x200004b4 + 4] (0x200004b8): while R = fn_0801dcf4(
@ object) has word 0 nonzero, word 1 zero and word 4 (+16) nonzero, calls the
@ function at offset 0x28 of the table *object when that is not 0.
@ Looks up two items with fn_08026a40(clip, fn_0801dd5c(object)) and, when
@ object word 5 (+20) is not 0, fn_08026a40(clip, word 5) (r6 and r5).
@ If both are 0: builds the rectangle 0, 0, fn_0801dcfc(object)-1,
@ fn_0801dd88(object)-1 with rect_set (at sp+0x44); when the record callback at
@ r0+0x2c is not 0 it clears a block with fn_0801f344, fills it from object
@ bytes +0x29, +0x2a and word +0x2c and calls the callback(r0, block,
@ rectangle); else when object word +0x2c is not 0 and fn_0802187c(word, sp)
@ returns 1 it fills a block with fn_0801e240 and draws with fn_0801e1f0; else
@ (object word +0x2c is 0) it clears a block with fn_0801f344, sets its
@ halfword +4 and byte +3 from object bytes +0x2a, +0x29 and draws with
@ fn_0801f31c.
@ Then calls fn_08029080(r0, item) for the two items in an order chosen by bit 0
@ of the byte at object offset 0x28 (bit set: first item then second; clear:
@ second then first; a missing item is replaced by word +0x10 or +0x14 of the
@ object), then for fn_0801dd38(object) and fn_0801dd28(object).
@ Returns when bit 1 of the byte at offset 0x10 of the first word of the object
@ is set, else tail-calls fn_08015d28.
@ ----------------------------------------------------------------------------
	.section .text.fn_08028ca8,"ax",%progbits
	.p2align 2
	.global fn_08028ca8
	.thumb_func
	.type fn_08028ca8, %function
fn_08028ca8:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r4, .L08028e18
	mov	r7, r0
	sub	sp, #0x50
	ldr	r0, [r4, #4]
	bl	fn_0801dcf4
	mov	r5, r0
	ldr	r0, [r0, #0]
	cbz	r0, .L08028cd4
	ldr	r0, [r5, #4]
	cbz	r0, .L08028cce
	b.n	.L08028cd4
.L08028cc4:
	ldr	r0, [r4, #4]
	ldr	r0, [r0, #0]
	ldr	r1, [r0, #0x28]
	cbz	r1, .L08028cce
	blx	r1
.L08028cce:
	ldr	r0, [r5, #0x10]
	cmp	r0, #0
	bne.n	.L08028cc4
.L08028cd4:
	movs	r5, #0
	ldr	r0, [r4, #4]
	bl	fn_0801dd5c
	mov	r1, r0
	ldr	r0, [r7, #4]
	bl	fn_08026a40
	mov	r6, r0
	ldr	r0, [r4, #4]
	ldr	r1, [r0, #0x14]
	cbz	r1, .L08028cf4
	ldr	r0, [r7, #4]
	bl	fn_08026a40
	mov	r5, r0
.L08028cf4:
	orrs.w	r0, r6, r5
	bne.n	.L08028da0
	ldr	r0, [r4, #4]
	bl	fn_0801dd88
	.inst.n	0x1e40	@ subs r0, r0, #1
	sxth.w	r8, r0
	ldr	r0, [r4, #4]
	bl	fn_0801dcfc
	.inst.n	0x1e40	@ subs r0, r0, #1
	sxth	r3, r0
	movs	r2, #0
	mov	r1, r2
	add	r0, sp, #0x44
	str.w	r8, [sp, #0]
	bl	rect_set
	ldr	r0, [r7, #0x2c]
	cbz	r0, .L08028d50
	add	r0, sp, #0xc
	bl	fn_0801f344
	ldr	r0, [r4, #4]
	add	r2, sp, #0x44
	ldr	r1, [r0, #0x2c]
	str	r1, [sp, #0x1c]
	ldrb.w	r1, [r0, #0x29]
	strb.w	r1, [sp, #0x26]
	ldrh	r1, [r0, #0x2a]
	strh.w	r1, [sp, #0x10]
	ldrb.w	r0, [r0, #0x29]
	strb.w	r0, [sp, #0xf]
	ldr	r3, [r7, #0x2c]
	add	r1, sp, #0xc
	mov	r0, r7
	blx	r3
	b.n	.L08028da0
.L08028d50:
	ldr	r0, [r4, #4]
	ldr	r1, [r0, #0x2c]
	cbz	r1, .L08028d80
	mov	r0, r1
	mov	r1, sp
	bl	fn_0802187c
	cmp	r0, #1
	bne.n	.L08028da0
	add	r0, sp, #0xc
	bl	fn_0801e240
	ldr	r0, [r4, #4]
	add	r2, sp, #0x44
	ldrb.w	r1, [r0, #0x29]
	strb.w	r1, [sp, #0x17]
	ldr	r3, [r0, #0x2c]
	add	r1, sp, #0xc
	mov	r0, r7
	bl	fn_0801e1f0
	b.n	.L08028da0
.L08028d80:
	add	r0, sp, #0xc
	bl	fn_0801f344
	ldr	r0, [r4, #4]
	ldrh	r1, [r0, #0x2a]
	strh.w	r1, [sp, #0x10]
	ldrb.w	r0, [r0, #0x29]
	strb.w	r0, [sp, #0xf]
	add	r1, sp, #0xc
	mov	r0, r7
	ldr	r2, [r7, #4]
	bl	fn_0801f31c
.L08028da0:
	ldr	r0, [r4, #4]
	ldrb.w	r1, [r0, #0x28]
	lsls	r1, r1, #0x1f
	beq.n	.L08028dc4
	cbnz	r6, .L08028dae
	ldr	r6, [r0, #0x10]
.L08028dae:
	mov	r0, r7
	mov	r1, r6
	bl	fn_08029080
	ldr	r0, [r4, #4]
	ldr	r0, [r0, #0x14]
	cbz	r0, .L08028de2
	cbnz	r5, .L08028dc0
	mov	r5, r0
.L08028dc0:
	mov	r1, r5
	b.n	.L08028ddc
.L08028dc4:
	ldr	r0, [r0, #0x14]
	cbz	r0, .L08028dd4
	cbnz	r5, .L08028dcc
	mov	r5, r0
.L08028dcc:
	mov	r1, r5
	mov	r0, r7
	bl	fn_08029080
.L08028dd4:
	cbnz	r6, .L08028dda
	ldr	r0, [r4, #4]
	ldr	r6, [r0, #0x10]
.L08028dda:
	mov	r1, r6
.L08028ddc:
	mov	r0, r7
	bl	fn_08029080
.L08028de2:
	ldr	r0, [r4, #4]
	bl	fn_0801dd38
	mov	r1, r0
	mov	r0, r7
	bl	fn_08029080
	ldr	r0, [r4, #4]
	bl	fn_0801dd28
	mov	r1, r0
	mov	r0, r7
	bl	fn_08029080
	ldr	r0, [r4, #4]
	ldr	r1, [r0, #0]
	ldrb	r1, [r1, #0x10]
	lsls	r1, r1, #0x1e
	bmi.n	.L08028e12
	add	sp, #0x50
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08015d28
.L08028e12:
	add	sp, #0x50
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08028e18:
	.word	0x200004b4	@ base word; the object pointer is read from [base+4] (0x200004b8)

@ ----------------------------------------------------------------------------
@ fn_08028e1c - draws every rectangle of the object at [0x200004b8] that is
@ marked as zero in its flag byte array, and sums their areas.
@ No parameters. Clears the word at 0x200004b4, then when the halfword at
@ object (0x200004b8) + 0x150 is not 0 walks the byte array at object + 0x130
@ downward from index count-1 to find the last entry equal to 0 (index 0 when
@ none is 0).
@ Calls the function at offset 0x34 of the table *object when not 0, clears
@ bits 0 and 1 of the flags word at ((*object)+0xc)+0x18, sets bit 2 of the
@ byte at object + 0x28.
@ For every index of the array whose byte is 0: sets bit 0 of the flag word when
@ the index is the last one found, clears bit 1, draws the rectangle at object +
@ 0x30 + index*8 with fn_08028b4c and adds the result of rect_area(rectangle) to
@ the word at 0x200004b4. Clears bit 2 of the byte at object + 0x28 at the end.
@ ----------------------------------------------------------------------------
	.section .text.fn_08028e1c,"ax",%progbits
	.p2align 2
	.global fn_08028e1c
	.thumb_func
	.type fn_08028e1c, %function
fn_08028e1c:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r4, .L08028ed0
	movs	r0, #0
	str	r0, [r4, #0]
	ldr	r0, [r4, #4]
	ldrh.w	r5, [r0, #0x150]
	cmp	r5, #0
	beq.n	.L08028ecc
	movs	r7, #0
	b.n	.L08028e3c
.L08028e34:
	adds	r1, r0, r5
	ldrb.w	r1, [r1, #0x130]
	cbz	r1, .L08028e72
.L08028e3c:
	.inst.n	0x1e6d	@ subs r5, r5, #1
	bpl.n	.L08028e34
.L08028e40:
	ldr	r0, [r0, #0]
	ldr	r1, [r0, #0x34]
	cbz	r1, .L08028e48
	blx	r1
.L08028e48:
	ldr	r0, [r4, #4]
	ldr	r1, [r0, #0]
	ldr	r1, [r1, #0xc]
	ldr	r2, [r1, #0x18]
	bic.w	r2, r2, #1
	str	r2, [r1, #0x18]
	ldr	r1, [r0, #0]
	ldr	r1, [r1, #0xc]
	ldr	r2, [r1, #0x18]
	bic.w	r2, r2, #2
	str	r2, [r1, #0x18]
	ldrb.w	r1, [r0, #0x28]
	movs	r6, #0
	orr.w	r1, r1, #4
	strb.w	r1, [r0, #0x28]
	b.n	.L08028eb8
.L08028e72:
	mov	r7, r5
	b.n	.L08028e40
.L08028e76:
	adds	r1, r0, r6
	ldrb.w	r1, [r1, #0x130]
	cbnz	r1, .L08028eb6
	cmp	r6, r7
	bne.n	.L08028e8e
	ldr	r1, [r0, #0]
	ldr	r1, [r1, #0xc]
	ldr	r2, [r1, #0x18]
	orr.w	r2, r2, #1
	str	r2, [r1, #0x18]
.L08028e8e:
	ldr	r1, [r0, #0]
	ldr	r1, [r1, #0xc]
	ldr	r2, [r1, #0x18]
	bic.w	r2, r2, #2
	str	r2, [r1, #0x18]
	add.w	r0, r0, r6, lsl #3
	adds	r0, #0x30
	bl	fn_08028b4c
	ldr	r0, [r4, #4]
	add.w	r0, r0, r6, lsl #3
	adds	r0, #0x30
	bl	rect_area
	ldr	r1, [r4, #0]
	add	r0, r1
	str	r0, [r4, #0]
.L08028eb6:
	.inst.n	0x1c76	@ adds r6, r6, #1
.L08028eb8:
	ldr	r0, [r4, #4]
	ldrh.w	r1, [r0, #0x150]
	cmp	r1, r6
	bgt.n	.L08028e76
	ldrb.w	r1, [r0, #0x28]!
	bic.w	r1, r1, #4
	strb	r1, [r0, #0]
.L08028ecc:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08028ed0:
	.word	0x200004b4	@ base word; the object pointer is read from [base+4] (0x200004b8)

@ ----------------------------------------------------------------------------
@ fn_08028ed4 - draws one object band by band through a draw record.
@ r0 = draw context (kept in r9), r1 = object pointer (kept in r5).
@ Returns at once when all_flag_bits_set(r1, 1) is not 0.
@ When fn_08012732(r1) is 0 it tail-calls fn_0802575e(r0, r1) and returns.
@ Reads byte fn_08024bac(r1, 0, 0x60) (kept in r8) and returns when it is below 2.
@ Gets the rectangle (at sp) with fn_0801c24a(r0, r1, mode, rect) with mode =
@ the fn_08012732 result, returns when the result is not 1; builds flags (r6):
@ bit 0 is 1 unless fn_08011e9c(rect, r1+20, 0) is not 0 and the message 0x12
@ sent with fn_080207f4 leaves its byte result 0, bit 1 when mode is 1.
@ Creates a draw record with fn_0801e814(r0, rect, flags) (r4), reads the
@ properties 0x6e and 0x6f with fn_08024bac into the two halves of r7, fills a
@ parameter block at sp+8 with fn_0801e240, stores r8 at sp+0x13, reads the
@ property 0x6d (folded: a value above 0xe10 has 0xe10 subtracted, a negative
@ one has 0xe10 added) into the halfword at sp+8, 0x6c into the halfword at
@ sp+0xa and 0x67 into the byte at sp+0x14, and stores bit 3 of the byte at
@ offset 0x10 of the first word of the object at [0x200004b4 + 4] into the byte
@ at sp+0x1c.
@ With flag bit 1 set the record is prepared for bands (words 2 and 3 copied
@ from words 0 and 1, halfword +0xe set to halfword +0xa + halfword +0x12 - 1
@ limited to the signed halfword at +6). Loops over bands with fn_0801c1e4,
@ fn_0802575e and fn_0801e80a until the band top passes the rectangle bottom
@ (signed halfword at sp+6); ends with fn_0801e872(r0, record).
@ ----------------------------------------------------------------------------
	.section .text.fn_08028ed4,"ax",%progbits
	.p2align 2
	.global fn_08028ed4
	.thumb_func
	.type fn_08028ed4, %function
fn_08028ed4:
	push.w	{r4, r5, r6, r7, r8, r9, lr}
	mov	r5, r1
	mov	r9, r0
	sub	sp, #0x2c
	movs	r1, #1
	mov	r0, r5
	bl	all_flag_bits_set
	cmp	r0, #0
	bne.n	.L08028fe8
	mov	r0, r5
	bl	fn_08012732
	movs	r4, r0
	beq.n	.L08028f44
	mov	r0, r5
	movs	r1, #0
	movs	r2, #0x60
	bl	fn_08024bac
	and.w	r8, r0, #0xff
	cmp.w	r8, #2
	bcc.n	.L08028fe8
	mov	r3, sp
	mov	r2, r4
	mov	r1, r5
	mov	r0, r9
	bl	fn_0801c24a
	cmp	r0, #1
	bne.n	.L08028fe8
	movs	r6, #1
	movs	r2, #0
	add.w	r1, r5, #0x14
	mov	r0, sp
	bl	fn_08011e9c
	cbz	r0, .L08028f54
	movs	r0, #0
	strb.w	r0, [sp, #0x20]
	str.w	sp, [sp, #0x24]
	add	r2, sp, #0x20
	movs	r1, #0x12
	mov	r0, r5
	bl	fn_080207f4
	ldrb.w	r0, [sp, #0x20]
	cbz	r0, .L08028f52
	b.n	.L08028f54
.L08028f44:
	add	sp, #0x2c
	mov	r1, r5
	mov	r0, r9
	pop.w	{r4, r5, r6, r7, r8, r9, lr}
	b.w	fn_0802575e
.L08028f52:
	movs	r6, #0
.L08028f54:
	cmp	r4, #1
	bne.n	.L08028f5c
	orr.w	r6, r6, #2
.L08028f5c:
	mov	r2, r6
	mov	r1, sp
	mov	r0, r9
	bl	fn_0801e814
	movs	r4, r0
	beq.n	.L08028fe8
	mov	r0, r5
	movs	r1, #0
	movs	r2, #0x6e
	bl	fn_08024bac
	bfi	r7, r0, #0, #16
	mov	r0, r5
	movs	r1, #0
	movs	r2, #0x6f
	bl	fn_08024bac
	bfi	r7, r0, #16, #16
	add	r0, sp, #8
	bl	fn_0801e240
	strb.w	r8, [sp, #0x13]
	mov	r0, r5
	movs	r1, #0
	movs	r2, #0x6d
	bl	fn_08024bac
	sxth	r0, r0
	strh.w	r0, [sp, #8]
	cmp.w	r0, #0xe10
	ble.n	.L08028fac
	sub.w	r0, r0, #0xe10
	b.n	.L08028fb4
.L08028fac:
	cmp	r0, #0
	bge.n	.L08028fb8
	add.w	r0, r0, #0xe10
.L08028fb4:
	strh.w	r0, [sp, #8]
.L08028fb8:
	mov	r0, r5
	movs	r1, #0
	movs	r2, #0x6c
	bl	fn_08024bac
	strh.w	r0, [sp, #0xa]
	mov	r0, r5
	movs	r1, #0
	movs	r2, #0x67
	bl	fn_08024bac
	strb.w	r0, [sp, #0x14]
	ldr	r0, .L0802907c
	ldr	r0, [r0, #4]
	ldr	r0, [r0, #0]
	ldrb	r0, [r0, #0x10]
	ubfx	r0, r0, #3, #1
	strb.w	r0, [sp, #0x1c]
	lsls	r0, r6, #0x1e
	b.n	.L08028fea
.L08028fe8:
	b.n	.L08029074
.L08028fea:
	bpl.n	.L0802900a
	ldrd	r0, r1, [r4, #0]
	strd	r0, r1, [r4, #8]
	ldrh	r0, [r4, #0xa]
	ldrh	r1, [r4, #0x12]
	add	r0, r1
	.inst.n	0x1e40	@ subs r0, r0, #1
	sxth	r1, r0
	strh	r1, [r4, #0xe]
	ldrsh.w	r0, [r4, #6]
	cmp	r1, r0
	ble.n	.L0802900a
.L08029008:
	strh	r0, [r4, #0xe]
.L0802900a:
	ldrsh.w	r0, [r4, #0xa]
	ldrsh.w	r1, [sp, #6]
	cmp	r0, r1
	bgt.n	.L0802906c
	lsls	r0, r6, #0x1e
	bpl.n	.L08029026
	mov	r3, r6
	mov	r2, r4
	mov	r1, r9
	mov	r0, r5
	bl	fn_0801c1e4
.L08029026:
	mov	r1, r5
	mov	r0, r9
	bl	fn_0802575e
	ldrh	r0, [r5, #0x14]
	add	r2, sp, #8
	adds	r1, r0, r7
	ldr.w	r0, [r9, #4]
	ldrh	r0, [r0, #0]
	subs	r0, r1, r0
	strh.w	r0, [sp, #0xc]
	ldrh	r0, [r5, #0x16]
	add.w	r1, r0, r7, asr #16
	ldr.w	r0, [r9, #4]
	ldrh	r0, [r0, #2]
	subs	r0, r1, r0
	strh.w	r0, [sp, #0xe]
	mov	r1, r4
	mov	r0, r9
	bl	fn_0801e80a
	lsls	r0, r6, #0x1e
	bpl.n	.L0802906c
	ldrh	r0, [r4, #0xe]
	.inst.n	0x1c40	@ adds r0, r0, #1
	strh	r0, [r4, #0xa]
	ldrh	r1, [r4, #0x12]
	add	r0, r1
	.inst.n	0x1e40	@ subs r0, r0, #1
	b.n	.L08029008
.L0802906c:
	mov	r1, r4
	mov	r0, r9
	bl	fn_0801e872
.L08029074:
	add	sp, #0x2c
	pop.w	{r4, r5, r6, r7, r8, r9, pc}
	.short	0x0000	@ padding
.L0802907c:
	.word	0x200004b4	@ base word; the object pointer is read from [base+4] (0x200004b8)

@ ----------------------------------------------------------------------------
@ fn_0802928e - samples a source halfword image along a stepped line into a
@ destination buffer with a validity mask.
@ r0 = source halfword image, r1 = width, r2 = height, r3 = stride (kept in r8);
@ stack: start x (24.8, sp+0x38), start y (24.8, sp+0x3c), dx step (sp+0x40),
@ dy step (sp+0x44), count (sp+0x48), destination halfword buffer (sp+0x4c),
@ mask byte buffer (sp+0x50), mode (sp+0x54). Returns with r0 and r1 unchanged.
@ Calls return_word_200004b8 (0x08012af4) for an object p and reads the word at
@ [*p + 0x38] as a color key (r7); clears the mask with fill_bytes_ff(mask,
@ count).
@ For each i below count it samples at x = (start x + ((dx*i) >> 8)) >> 8,
@ y = (start y + ((dy*i) >> 8)) >> 8; outside 0..width-1 and 0..height-1 the
@ mask byte is 0, inside the pixel at source + (y*stride + x)*2 is copied to
@ destination + i*2.
@ With mode 6 a destination halfword equal to the low 16 bits of the color key
@ sets its mask byte to 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802928e,"ax",%progbits
	.global fn_0802928e
	.thumb_func
	.type fn_0802928e, %function
fn_0802928e:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	mov	r8, r3
	ldrd	r5, r4, [sp, #0x38]
	ldrd	r10, r6, [sp, #0x44]
	ldrd	r9, r11, [sp, #0x50]
	bl	return_word_200004b8
	ldr	r0, [r0, #0]
	mov	r1, r6
	ldr	r7, [r0, #0x38]
	mov	r0, r9
	bl	fill_bytes_ff
	movs	r0, #0
	mov	r3, r0
	b.n	.L08029318
.L080292b6:
	ldr	r1, [sp, #0x40]
	mul	r2, r10, r0
	muls	r1, r0, r1
	add.w	r1, r5, r1, asr #8
	add.w	r2, r4, r2, asr #8
	asrs	r1, r1, #8
	asr.w	r2, r2, #8
	bmi.n	.L080292e2
	ldr.w	r12, [sp, #4]
	cmp	r1, r12
	bge.n	.L080292e2
	cmp	r2, #0
	blt.n	.L080292e2
	ldr.w	r12, [sp, #8]
	cmp	r2, r12
	blt.n	.L080292e8
.L080292e2:
	strb.w	r3, [r9, r0]
	b.n	.L080292fe
.L080292e8:
	mla	r1, r2, r8, r1
	ldr.w	r12, [sp, #0]
	ldr	r2, [sp, #0x4c]
	add.w	r1, r12, r1, lsl #1
	add.w	r2, r2, r0, lsl #1
	ldrh	r1, [r1, #0]
	strh	r1, [r2, #0]
.L080292fe:
	cmp.w	r11, #6
	bne.n	.L08029314
	ldr	r1, [sp, #0x4c]
	uxth	r2, r7
	ldrh.w	r1, [r1, r0, lsl #1]
	cmp	r1, r2
	bne.n	.L08029314
	strb.w	r3, [r9, r0]
.L08029314:
	.inst.n	0x1c40	@ adds r0, r0, #1
	sxth	r0, r0
.L08029318:
	cmp	r0, r6
	blt.n	.L080292b6
	pop.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}

