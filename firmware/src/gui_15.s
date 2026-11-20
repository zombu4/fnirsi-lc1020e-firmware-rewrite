@ gui_15.s - GUI module part 15: object redraw routine, record clearing, key flagging, rectangle bounds and following routines
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08012188 - r0 = object pointer or 0 (kept in r7); r1..r3 are only saved by the
@ push {r1..r7,lr}. Returns nothing defined; the path with B[0x10] = 0 pops with
@ r0 = B; the other path ends in a tail call to fn_0801226c.
@ r6 = fn_080277a0(); r5 = 0; word [sp] = 0; r4 = 0x200004b4 (literal .L08012268).
@ r0 nonzero: word 0x200004b8 = word [r7+0xc], record_set_flag(r7), B = word 0x200004b8.
@ r0 = 0: B = fn_0801dccc(), word 0x200004b8 = B.
@ fn_080267c0 is called with B[0x10]; with B[0x14] only when nonzero; with B[0x1c];
@ with B[0x20]. r1 = B[0x10]; zero goes to .L0801224e -> .L08012260: halfword
@ [B+0x150] = 0 (r5) and pop {r1..r7,pc}.
@ Nonzero: fn_08026ab8(r0 = B, r1 = B[0x10]); fn_08028e1c(); halfword [B+0x150] zero
@ goes to the common end.
@ Bit 1 of byte [[B]+0x10] set: r7 = sxth(fn_0801dd88(B) - 1);
@ r3 = sxth(fn_0801dcfc(word 0x200004b8) - 1); rect_set(r0 = sp+4, r1 = 0, r2 = 0,
@ r3, stack [sp] = r7); word [[[B]+0x3c]+4] = sp+4; fn_08015d28(B).
@ Then: clear_bytes(B+0x30, 0x100); clear_bytes(B+0x130, 0x20); halfword [B+0x150] = 0;
@ [sp] = ticks_since(r6); r3 = word [[B]+0x24]; when nonzero blx r3 with r0 = [B],
@ r1 = [sp], r2 = word [0x200004b4].
@ Common end .L08012250: fn_08022b80(); return_only_080122c4(); pop {r1..r7,lr};
@ b.w fn_0801226c (tail call).
@ ----------------------------------------------------------------------------
	.section .text.fn_08012188,"ax",%progbits
	.p2align 2
	.global fn_08012188
	.thumb_func
	.type fn_08012188, %function
fn_08012188:
	push	{r1, r2, r3, r4, r5, r6, r7, lr}
	mov	r7, r0
	bl	fn_080277a0
	movs	r5, #0x0
	ldr	r4, .L08012268
	mov	r6, r0
	str	r5, [sp, #0x0]
	cbz	r7, .L080121a8
	ldr	r0, [r7, #0xc]
	str	r0, [r4, #0x4]
	mov	r0, r7
	bl	record_set_flag
	ldr	r0, [r4, #0x4]
	b.n	.L080121ae
.L080121a8:
	bl	fn_0801dccc
	str	r0, [r4, #0x4]
.L080121ae:
	ldr	r0, [r0, #0x10]
	bl	fn_080267c0
	ldr	r0, [r4, #0x4]
	ldr	r0, [r0, #0x14]
	cbz	r0, .L080121be
	bl	fn_080267c0
.L080121be:
	ldr	r0, [r4, #0x4]
	ldr	r0, [r0, #0x1c]
	bl	fn_080267c0
	ldr	r0, [r4, #0x4]
	ldr	r0, [r0, #0x20]
	bl	fn_080267c0
	ldr	r0, [r4, #0x4]
	ldr	r1, [r0, #0x10]
	cbz	r1, .L0801224e
	bl	fn_08026ab8
	bl	fn_08028e1c
	ldr	r0, [r4, #0x4]
	ldrh.w	r1, [r0, #0x150]
	cbz	r1, .L0801224c
	ldr	r1, [r0, #0x0]
	ldrb	r1, [r1, #0x10]
	lsls	r1, r1, #0x1e
	bpl.n	.L08012218
	bl	fn_0801dd88
	.inst.n 0x1e40	@ subs r0, r0, #1
	sxth	r7, r0
	ldr	r0, [r4, #0x4]
	bl	fn_0801dcfc
	.inst.n 0x1e40	@ subs r0, r0, #1
	sxth	r3, r0
	movs	r2, #0x0
	mov	r1, r2
	add	r0, sp, #0x4
	str	r7, [sp, #0x0]
	bl	rect_set
	ldr	r0, [r4, #0x4]
	add	r1, sp, #0x4
	ldr	r2, [r0, #0x0]
	ldr	r2, [r2, #0x3c]
	str	r1, [r2, #0x4]
	bl	fn_08015d28
.L08012218:
	ldr	r0, [r4, #0x4]
	mov.w	r1, #0x100
	adds	r0, #0x30
	bl	clear_bytes
	ldr	r0, [r4, #0x4]
	movs	r1, #0x20
	add.w	r0, r0, #0x130
	bl	clear_bytes
	ldr	r0, [r4, #0x4]
	strh.w	r5, [r0, #0x150]
	mov	r0, r6
	bl	ticks_since
	str	r0, [sp, #0x0]
	ldr	r0, [r4, #0x4]
	ldr	r0, [r0, #0x0]
	ldr	r3, [r0, #0x24]
	cbz	r3, .L0801224c
	ldr	r2, [r4, #0x0]
	ldr	r1, [sp, #0x0]
	blx	r3
.L0801224c:
	b.n	.L08012250
.L0801224e:
	b.n	.L08012260
.L08012250:
	bl	fn_08022b80
	bl	return_only_080122c4
	pop.w	{r1, r2, r3, r4, r5, r6, r7, lr}
	b.w	fn_0801226c
.L08012260:
	strh.w	r5, [r0, #0x150]
	pop	{r1, r2, r3, r4, r5, r6, r7, pc}
	.short 0x0000	@ padding
.L08012268:
	.word 0x200004b4	@ address of the word pair 0x200004b4 / 0x200004b8

@ ----------------------------------------------------------------------------
@ fn_0801226c - no parameters, no value of its own.
@ r5 = 0x2000815c (literal .L08012298); for r4 = 0..3 (uxtb, loop while r4 < 4):
@ r6 = 7*r4 (rsb), record R = r5 + r6*4 (28 bytes); when word [R] is nonzero calls
@ fn_08022c68(word [R]); calls clear_bytes(R, 0x1c).
@ Entered by the b.w of fn_08012188.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801226c,"ax",%progbits
	.p2align 2
	.global fn_0801226c
	.thumb_func
	.type fn_0801226c, %function
fn_0801226c:
	push	{r4, r5, r6, lr}
	ldr	r5, .L08012298
	movs	r4, #0x0
	nop
.L08012274:
	rsb	r6, r4, r4, lsl #0x3
	ldr.w	r0, [r5, r6, lsl #0x2]
	cbz	r0, .L08012282
	bl	fn_08022c68
.L08012282:
	add.w	r0, r5, r6, lsl #0x2
	movs	r1, #0x1c
	bl	clear_bytes
	.inst.n 0x1c64	@ adds r4, r4, #1
	uxtb	r4, r4
	cmp	r4, #0x4
	bcc.n	.L08012274
	pop	{r4, r5, r6, pc}
	.short 0x0000	@ padding
.L08012298:
	.word 0x2000815c	@ base of four 28-byte records

@ ----------------------------------------------------------------------------
@ fn_0801229c - parameter: key (r0).
@ Walks the list starting at the word 0x2000049c (word [0x20000498+4]) through the next
@ pointer at node word [5]. For each node with word [1] or word [0] equal to the key
@ sets bit 0 of the byte at node + 0x18.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801229c,"ax",%progbits
	.p2align 2
	.global fn_0801229c
	.thumb_func
	.type fn_0801229c, %function
fn_0801229c:
	ldr	r1, .L080122c0
	ldr	r1, [r1, #0x4]
	b.n	.L080122b8
.L080122a2:
	ldr	r2, [r1, #0x4]
	cmp	r2, r0
	beq.n	.L080122ae
	ldr	r2, [r1, #0x0]
	cmp	r2, r0
	bne.n	.L080122b6
.L080122ae:
	ldrb	r2, [r1, #0x18]
	orr	r2, r2, #0x1
	strb	r2, [r1, #0x18]
.L080122b6:
	ldr	r1, [r1, #0x14]
.L080122b8:
	cmp	r1, #0x0
	bne.n	.L080122a2
	bx	lr
	.short 0x0000	@ padding
.L080122c0:
	.word 0x20000498	@ list head base; the code reads word [+4]

@ ----------------------------------------------------------------------------
@ return_only_080122c4 - no parameters. Single return (bx lr).
@ ----------------------------------------------------------------------------
	.section .text.return_only_080122c4,"ax",%progbits
	.p2align 2
	.global return_only_080122c4
	.thumb_func
	.type return_only_080122c4, %function
return_only_080122c4:
	bx	lr
	.short 0x0000	@ padding

@ ----------------------------------------------------------------------------
@ init_header_20008074 - no parameters. Tail call init_header_aligned4(0x20008074, 4).
@ ----------------------------------------------------------------------------
	.section .text.init_header_20008074,"ax",%progbits
	.p2align 2
	.global init_header_20008074
	.thumb_func
	.type init_header_20008074, %function
init_header_20008074:
	movs	r1, #0x4
	ldr	r0, .L080122d0
	b.w	init_header_aligned4
.L080122d0:
	.word 0x20008074

@ ----------------------------------------------------------------------------
@ init_header_2000808c - no parameters. Tail call init_header_aligned4(0x2000808c, 0x20).
@ ----------------------------------------------------------------------------
	.section .text.init_header_2000808c,"ax",%progbits
	.p2align 2
	.global init_header_2000808c
	.thumb_func
	.type init_header_2000808c, %function
init_header_2000808c:
	movs	r1, #0x20
	ldr	r0, .L080122dc
	b.w	init_header_aligned4
.L080122dc:
	.word 0x2000808c

@ ----------------------------------------------------------------------------
@ fn_080122e0 - parameters: output rectangle int16[4] (r0, kept in r4), width (r1),
@ height (r2), r3 (kept in r5) and two stack words (loaded into r6, r7) passed through
@ to fn_08026878 as r2 / r3.
@ When r3 is 0 and r6 is 0x100 stores {0, 0, width-1, height-1} to the rectangle.
@ Otherwise stores the four corner points (0,0), (width,0), (0,height), (width,height)
@ at sp+0, sp+4, sp+8, sp+12, transforms each with fn_08026878(point, r5, r6, r7) and
@ stores the bounding box widened by 2: out[0] = min x - 2, out[1] = min y - 2,
@ out[2] = max x + 2, out[3] = max y + 2.
@ Returns with the registers restored by pop {r0..r8,pc}, so r0 is the rectangle
@ pointer unchanged.
@ ----------------------------------------------------------------------------
	.section .text.fn_080122e0,"ax",%progbits
	.p2align 2
	.global fn_080122e0
	.thumb_func
	.type fn_080122e0, %function
fn_080122e0:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, lr}
	mov	r4, r0
	ldrd	r6, r7, [sp, #0x28]
	movs	r5, r3
	mov.w	r0, #0x0
	bne.n	.L080122f8
	cmp.w	r6, #0x100
	beq.n	.L08012350
.L080122f8:
	str	r0, [sp, #0xc]
	str	r0, [sp, #0x4]
	str	r0, [sp, #0x8]
	strh.w	r1, [sp, #0xc]
	str	r0, [sp, #0x0]
	strh.w	r1, [sp, #0x4]
	strh.w	r2, [sp, #0xa]
	strh.w	r2, [sp, #0xe]
	mov	r3, r7
	mov	r2, r6
	mov	r1, r5
	mov	r0, sp
	bl	fn_08026878
	mov	r3, r7
	mov	r2, r6
	mov	r1, r5
	add	r0, sp, #0x4
	bl	fn_08026878
	mov	r3, r7
	mov	r2, r6
	mov	r1, r5
	add	r0, sp, #0x8
	bl	fn_08026878
	mov	r3, r7
	mov	r2, r6
	mov	r1, r5
	add	r0, sp, #0xc
	bl	fn_08026878
	ldrsh.w	r0, [sp, #0x0]
	ldrsh.w	r3, [sp, #0x4]
	cmp	r0, r3
	bge.n	.L08012360
	mov	r5, r0
	b.n	.L08012362
.L08012350:
	strh	r0, [r4, #0x0]
	.inst.n 0x1e49	@ subs r1, r1, #1
	strh	r0, [r4, #0x2]
	strh	r1, [r4, #0x4]
	.inst.n 0x1e52	@ subs r2, r2, #1
	strh	r2, [r4, #0x6]
.L0801235c:
	pop.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, pc}
.L08012360:
	mov	r5, r3
.L08012362:
	ldrsh.w	r2, [sp, #0x8]
	ldrsh.w	r1, [sp, #0xc]
	cmp	r2, r1
	bge.n	.L08012372
	mov	r6, r2
	b.n	.L08012374
.L08012372:
	mov	r6, r1
.L08012374:
	cmp	r5, r6
	bge.n	.L08012380
	cmp	r0, r3
	blt.n	.L0801238a
	mov	r0, r3
	b.n	.L0801238a
.L08012380:
	cmp	r2, r1
	bge.n	.L08012388
	mov	r0, r2
	b.n	.L0801238a
.L08012388:
	mov	r0, r1
.L0801238a:
	.inst.n 0x1e80	@ subs r0, r0, #2
	strh	r0, [r4, #0x0]
	ldrsh.w	r3, [sp, #0x0]
	ldrsh.w	r2, [sp, #0x4]
	cmp	r3, r2
	ble.n	.L0801239e
	mov	r5, r3
	b.n	.L080123a0
.L0801239e:
	mov	r5, r2
.L080123a0:
	ldrsh.w	r0, [sp, #0x8]
	ldrsh.w	r1, [sp, #0xc]
	cmp	r0, r1
	ble.n	.L080123b0
	mov	r6, r0
	b.n	.L080123b2
.L080123b0:
	mov	r6, r1
.L080123b2:
	cmp	r5, r6
	ble.n	.L080123c2
	cmp	r3, r2
	ble.n	.L080123be
	mov	r1, r3
	b.n	.L080123c8
.L080123be:
	mov	r1, r2
	b.n	.L080123c8
.L080123c2:
	cmp	r0, r1
	ble.n	.L080123c8
	mov	r1, r0
.L080123c8:
	.inst.n 0x1c89	@ adds r1, r1, #2
	strh	r1, [r4, #0x4]
	ldrsh.w	r3, [sp, #0x2]
	ldrsh.w	r2, [sp, #0x6]
	cmp	r3, r2
	bge.n	.L080123dc
	mov	r5, r3
	b.n	.L080123de
.L080123dc:
	mov	r5, r2
.L080123de:
	ldrsh.w	r0, [sp, #0xa]
	ldrsh.w	r1, [sp, #0xe]
	cmp	r0, r1
	bge.n	.L080123ee
	mov	r6, r0
	b.n	.L080123f0
.L080123ee:
	mov	r6, r1
.L080123f0:
	cmp	r5, r6
	bge.n	.L08012400
	cmp	r3, r2
	bge.n	.L080123fc
	mov	r1, r3
	b.n	.L08012406
.L080123fc:
	mov	r1, r2
	b.n	.L08012406
.L08012400:
	cmp	r0, r1
	bge.n	.L08012406
	mov	r1, r0
.L08012406:
	.inst.n 0x1e89	@ subs r1, r1, #2
	strh	r1, [r4, #0x2]
	ldrsh.w	r3, [sp, #0x2]
	ldrsh.w	r2, [sp, #0x6]
	cmp	r3, r2
	ble.n	.L0801241a
	mov	r5, r3
	b.n	.L0801241c
.L0801241a:
	mov	r5, r2
.L0801241c:
	ldrsh.w	r0, [sp, #0xa]
	ldrsh.w	r1, [sp, #0xe]
	cmp	r0, r1
	ble.n	.L0801242c
	mov	r6, r0
	b.n	.L0801242e
.L0801242c:
	mov	r6, r1
.L0801242e:
	cmp	r5, r6
	ble.n	.L0801243e
	cmp	r3, r2
	ble.n	.L0801243a
	mov	r1, r3
	b.n	.L08012444
.L0801243a:
	mov	r1, r2
	b.n	.L08012444
.L0801243e:
	cmp	r0, r1
	ble.n	.L08012444
	mov	r1, r0
.L08012444:
	.inst.n 0x1c89	@ adds r1, r1, #2
	strh	r1, [r4, #0x6]
	b.n	.L0801235c
	.short 0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_0801244c - parameters r0, r1, r2 (kept in r7, r6, r5) passed on to fn_080218d4.
@ Calls fn_080277a0 (result kept in r8), then fn_080218d4(0x200080b0, r0, r1, r2).
@ On result 0: clear_bytes(0x200080b0, 0x2c), stores 0x80000000 in the word 0x200080d8,
@ returns 0.
@ Otherwise stores 0 in the word 0x200080d8; when the word 0x200080cc is 0 sets it to
@ ticks_since(saved value), or to 1 when that is 0; returns 0x200080b0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801244c,"ax",%progbits
	.p2align 2
	.global fn_0801244c
	.thumb_func
	.type fn_0801244c, %function
fn_0801244c:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r5, r2
	mov	r6, r1
	mov	r7, r0
	ldr	r4, .L0801249c
	bl	fn_080277a0
	mov	r8, r0
	mov	r3, r5
	mov	r2, r6
	mov	r1, r7
	mov	r0, r4
	bl	fn_080218d4
	cbz	r0, .L08012476
	movs	r0, #0x0
	str	r0, [r4, #0x28]
	ldr	r0, [r4, #0x1c]
	cbz	r0, .L0801248a
	b.n	.L08012498
.L08012476:
	movs	r1, #0x2c
	mov	r0, r4
	bl	clear_bytes
	mov.w	r0, #0x80000000
	str	r0, [r4, #0x28]
	movs	r0, #0x0
.L08012486:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0801248a:
	mov	r0, r8
	bl	ticks_since
	str	r0, [r4, #0x1c]
	cbnz	r0, .L08012498
	movs	r0, #0x1
	str	r0, [r4, #0x1c]
.L08012498:
	mov	r0, r4
	b.n	.L08012486
.L0801249c:
	.word 0x200080b0	@ 44-byte record cleared and returned by this routine

@ ----------------------------------------------------------------------------
@ fn_080124a0 - no parameters.
@ Calls init_header_aligned4(0x20008098, 0x14); p = fn_0802185c(); when p is nonzero
@ stores the words 0x08021279, 0x080215f5, 0x0802177d, 0x08021245 (code addresses
@ with the Thumb bit set) at p[0..3].
@ ----------------------------------------------------------------------------
	.section .text.fn_080124a0,"ax",%progbits
	.p2align 2
	.global fn_080124a0
	.thumb_func
	.type fn_080124a0, %function
fn_080124a0:
	push	{r4, lr}
	movs	r1, #0x14
	ldr	r0, .L080124c4
	bl	init_header_aligned4
	bl	fn_0802185c
	cmp	r0, #0x0
	beq.n	.L080124c2
	ldr	r1, .L080124c8
	str	r1, [r0, #0x0]
	ldr	r1, .L080124cc
	str	r1, [r0, #0x4]
	ldr	r1, .L080124d0
	str	r1, [r0, #0x8]
	ldr	r1, .L080124d4
	str	r1, [r0, #0xc]
.L080124c2:
	pop	{r4, pc}
.L080124c4:
	.word 0x20008098
.L080124c8:
	.word fn_08021278	@ function pointer 0x08021279
.L080124cc:
	.word fn_080215f4	@ function pointer 0x080215f5
.L080124d0:
	.word fn_0802177c	@ function pointer 0x0802177d
.L080124d4:
	.word fn_08021244	@ function pointer 0x08021245

@ ----------------------------------------------------------------------------
@ fn_080124d8 - parameters: object (r0, 0 selects fn_0801dccc()), rectangle (r1, kept
@ in r6), r2 and r3 (only saved by the push).
@ Requires fn_0801ddb4() nonzero and bit 2 of the byte object + 0x28 clear (else it
@ returns). Rectangle 0: clears the halfword at object + 0x150.
@ Otherwise builds {0, 0, fn_0801dcfc - 1, fn_0801dd88 - 1} at sp and intersects it
@ with the rectangle through rect_intersect(sp+8, r1, sp).
@ When non-empty: if bit 1 of the byte *(*object + 0x10) is set stores the unclipped
@ rectangle (ldrd from [sp]) at object + 0x30 with count 1; else calls the function at
@ *(*object + 0x18) with (r1 = sp+8) when nonzero, scans the stored rectangles (8 bytes
@ each at object + 0x30, count in the halfword at object + 0x150) with
@ fn_08011e9c(sp+8, stored rectangle, 0) and returns when one is nonzero, appends the
@ intersection with copy_rect_0801cfc4 at slot count when count < 0x20 (otherwise
@ resets the count to 0 and stores the unclipped rectangle at the first slot),
@ increments the count.
@ Calls record_clear_flag when object word [1] is nonzero.
@ ----------------------------------------------------------------------------
	.section .text.fn_080124d8,"ax",%progbits
	.global fn_080124d8
	.thumb_func
	.type fn_080124d8, %function
fn_080124d8:
	push	{r0, r1, r2, r3, r4, r5, r6, lr}
	mov	r6, r1
	movs	r4, r0
	bne.n	.L080124e8
	bl	fn_0801dccc
	movs	r4, r0
	beq.n	.L08012542
.L080124e8:
	bl	fn_0801ddb4
	cmp	r0, #0x0
	beq.n	.L08012542
	ldrb.w	r0, [r4, #0x28]
	lsls	r0, r0, #0x1d
	bmi.n	.L08012542
	movs	r5, #0x0
	cbz	r6, .L0801253e
	strh.w	r5, [sp, #0x0]
	strh.w	r5, [sp, #0x2]
	mov	r0, r4
	bl	fn_0801dcfc
	.inst.n 0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #0x4]
	mov	r0, r4
	bl	fn_0801dd88
	.inst.n 0x1e40	@ subs r0, r0, #1
	strh.w	r0, [sp, #0x6]
	mov	r2, sp
	mov	r1, r6
	add	r0, sp, #0x8
	bl	rect_intersect
	cmp	r0, #0x0
	beq.n	.L08012542
	ldr	r0, [r4, #0x0]
	ldrb	r1, [r0, #0x10]
	lsls	r1, r1, #0x1e
	bpl.n	.L08012544
	ldrd	r0, r1, [sp, #0x0]
	strd	r0, r1, [r4, #0x30]
	movs	r0, #0x1
	b.n	.L08012592
.L0801253e:
	strh.w	r5, [r4, #0x150]
.L08012542:
	pop	{r0, r1, r2, r3, r4, r5, r6, pc}
.L08012544:
	ldr	r2, [r0, #0x18]
	cbz	r2, .L0801254c
	add	r1, sp, #0x8
	blx	r2
.L0801254c:
	movs	r6, #0x0
	b.n	.L08012566
.L08012550:
	add.w	r1, r4, r6, lsl #0x3
	movs	r2, #0x0
	add	r0, sp, #0x8
	adds	r1, #0x30
	bl	fn_08011e9c
	cmp	r0, #0x0
	bne.n	.L08012542
	.inst.n 0x1c76	@ adds r6, r6, #1
	uxth	r6, r6
.L08012566:
	ldrh.w	r0, [r4, #0x150]
	cmp	r0, r6
	bhi.n	.L08012550
	uxth	r0, r0
	cmp	r0, #0x20
	bcs.n	.L0801257e
	add.w	r0, r4, r0, lsl #0x3
	add	r1, sp, #0x8
	adds	r0, #0x30
	b.n	.L08012588
.L0801257e:
	strh.w	r5, [r4, #0x150]
	add.w	r0, r4, #0x30
	mov	r1, sp
.L08012588:
	bl	copy_rect_0801cfc4
	ldrh.w	r0, [r4, #0x150]
	.inst.n 0x1c40	@ adds r0, r0, #1
.L08012592:
	strh.w	r0, [r4, #0x150]
	ldr	r0, [r4, #0x4]
	cmp	r0, #0x0
	beq.n	.L08012542
	bl	record_clear_flag
	pop	{r0, r1, r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_0801270a - parameter: pointer to object pointer (r0, kept in r4).
@ Loop: calls the function at *(*r0 + 8) with (*r0, r0) when it is nonzero; replaces
@ *r0 with the first word of the object at *r0; stops when that word is 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801270a,"ax",%progbits
	.global fn_0801270a
	.thumb_func
	.type fn_0801270a, %function
fn_0801270a:
	push	{r4, lr}
	mov	r4, r0
	ldr	r0, [r0, #0x0]
.L08012710:
	ldr	r2, [r0, #0x8]
	cbz	r2, .L08012718
	mov	r1, r4
	blx	r2
.L08012718:
	ldr	r0, [r4, #0x0]
	ldr	r0, [r0, #0x0]
	cmp	r0, #0x0
	beq.n	.L08012724
	str	r0, [r4, #0x0]
	b.n	.L08012710
.L08012724:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08012726 - parameter: object (r0).
@ Returns 0 when word [2] (r0 + 8) is 0, otherwise the signed halfword at
@ *(r0 + 8) + 0x16.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012726,"ax",%progbits
	.global fn_08012726
	.thumb_func
	.type fn_08012726, %function
fn_08012726:
	ldr	r0, [r0, #0x8]
	cmp	r0, #0x0
	beq.n	.L08012730
	ldrsh.w	r0, [r0, #0x16]
.L08012730:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08012732 - parameter: object (r0).
@ Returns 0 when word [2] (r0 + 8) is 0, otherwise the byte at *(r0 + 8) + 0x1a
@ shifted right by 6.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012732,"ax",%progbits
	.global fn_08012732
	.thumb_func
	.type fn_08012732, %function
fn_08012732:
	ldr	r0, [r0, #0x8]
	cmp	r0, #0x0
	beq.n	.L0801273c
	ldrb	r0, [r0, #0x1a]
	lsrs	r0, r0, #0x6
.L0801273c:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0801273e - parameters: object (r0, kept in r5), dx (r1, kept in r4), dy (r2,
@ kept in r6).
@ When dx or dy is nonzero: calls fn_0802318c(object), adds dx to the halfword at
@ *(object + 8) + 0x10 and dy to the halfword at +0x12, calls
@ fn_0802554c(object, dx, dy, 1), r = fn_080207f4(object, 0xb, 0); returns r when r
@ is not 1, otherwise calls fn_08025400(object).
@ Returns 1 otherwise.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801273e,"ax",%progbits
	.global fn_0801273e
	.thumb_func
	.type fn_0801273e, %function
fn_0801273e:
	push	{r4, r5, r6, lr}
	mov	r6, r2
	mov	r5, r0
	mov	r4, r1
	orrs.w	r0, r1, r6
	beq.n	.L08012782
	mov	r0, r5
	bl	fn_0802318c
	ldr	r0, [r5, #0x8]
	movs	r3, #0x1
	mov	r2, r6
	ldrh	r1, [r0, #0x10]
	add	r1, r4
	strh	r1, [r0, #0x10]
	ldr	r0, [r5, #0x8]
	ldrh	r1, [r0, #0x12]
	add	r1, r6
	strh	r1, [r0, #0x12]
	mov	r1, r4
	mov	r0, r5
	bl	fn_0802554c
	movs	r2, #0x0
	movs	r1, #0xb
	mov	r0, r5
	bl	fn_080207f4
	cmp	r0, #0x1
	bne.n	.L08012784
	mov	r0, r5
	bl	fn_08025400
.L08012782:
	movs	r0, #0x1
.L08012784:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08012786 - parameters: object (r0, kept in r5), r1 (kept in r6), default value
@ (r2, stored at sp+0xc).
@ When r0 is nonzero and p = fn_08024bac(r0, r1, 0x61) is nonzero with *p nonzero and
@ the byte of fn_08024bac(r0, r1, 0x62) is nonzero, calls the function *p with
@ (p, r2) and stores the low halfword of its result over the low halfword of the
@ stacked r2. Returns the stacked r2 word.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012786,"ax",%progbits
	.global fn_08012786
	.thumb_func
	.type fn_08012786, %function
fn_08012786:
	push	{r0, r1, r2, r4, r5, r6, lr}
	sub	sp, #0x4
	mov	r6, r1
	movs	r5, r0
	beq.n	.L080127c0
	movs	r2, #0x61
	bl	fn_08024bac
	movs	r4, r0
	beq.n	.L080127c0
	ldr	r0, [r4, #0x0]
	cbz	r0, .L080127c0
	mov	r0, r5
	mov	r1, r6
	movs	r2, #0x62
	bl	fn_08024bac
	ands.w	r2, r0, #0xff
	beq.n	.L080127c0
	ldr	r3, [r4, #0x0]
	mov	r0, r4
	ldr	r1, [sp, #0xc]
	blx	r3
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh.w	r0, [sp, #0xc]
.L080127c0:
	ldr	r0, [sp, #0xc]
	add	sp, #0x10
	pop	{r4, r5, r6, pc}
	.short 0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_080127c8 - parameters: object (r0, kept in r7), r1 (kept in r10), short a (r2,
@ kept in r8), short b (r3, kept in r9), table entry pointer (stack word at sp+0x68
@ after the prologue, loaded into r6; ushort fields).
@ Sets bit 2 of the halfword at object + 0x22, writes a then b to the halfword at
@ object + 0x20 and reads v1 (r5) and v2 (r4) with fn_08024bac(object, r1, entry[4]),
@ clears bit 2 again.
@ When v1 and v2 are equal returns. Otherwise: writes a, reads v1 again, writes b,
@ p = fn_0801b910(object, r1) and calls fn_08027280(*p, entry[4], v1).
@ When entry[4] is 0xb and v1 or v2 is 0x7fff replaces each value equal to 0x7fff by
@ the smaller of rect_width_plus_one(object)/2 + 1 and rect_height_plus_one(object)/2 + 1
@ (signed halving: add the sign bit, then asrs #1).
@ node = fn_08012618(0x200080a4); when nonzero fills node[0] = object, node[3] = v1,
@ node[4] = v2, halfword node[1] = entry[4], node[2] = r1, calls fn_0801c718 with the
@ frame at sp, stores the callback words 0x0802aa01, 0x0802abe5, 0x0802ab41 at
@ sp+4, sp+8, sp+0xc, the constant 0xff, entry[0], -entry[1], the words from entry + 12
@ and entry + 16, clears bit 0 of the byte at sp+0x42 and calls fn_0801c7c0 with the
@ frame at sp.
@ ----------------------------------------------------------------------------
	.section .text.fn_080127c8,"ax",%progbits
	.p2align 2
	.global fn_080127c8
	.thumb_func
	.type fn_080127c8, %function
fn_080127c8:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r7, r0
	sub	sp, #0x48
	ldrh	r0, [r0, #0x22]
	ldr	r6, [sp, #0x68]
	orr	r0, r0, #0x4
	strh	r0, [r7, #0x22]
	mov	r8, r2
	strh	r2, [r7, #0x20]
	mov	r9, r3
	mov	r10, r1
	ldrh	r2, [r6, #0x8]
	mov	r0, r7
	bl	fn_08024bac
	mov	r5, r0
	strh.w	r9, [r7, #0x20]
	ldrh	r2, [r6, #0x8]
	mov	r1, r10
	mov	r0, r7
	bl	fn_08024bac
	mov	r4, r0
	ldrh	r0, [r7, #0x22]
	cmp	r5, r4
	bic	r0, r0, #0x4
	strh	r0, [r7, #0x22]
	bne.n	.L08012810
	lsls	r1, r5, #0x10
	cmp.w	r1, r4, lsl #0x10
	beq.n	.L080128e2
.L08012810:
	strh.w	r8, [r7, #0x20]
	ldrh	r2, [r6, #0x8]
	mov	r1, r10
	mov	r0, r7
	bl	fn_08024bac
	mov	r5, r0
	mov	r8, r0
	strh.w	r9, [r7, #0x20]
	mov	r1, r10
	mov	r0, r7
	bl	fn_0801b910
	ldrh	r1, [r6, #0x8]
	ldr	r0, [r0, #0x0]
	mov	r2, r5
	bl	fn_08027280
	ldrh	r0, [r6, #0x8]
	cmp	r0, #0xb
	bne.n	.L08012886
	movw	r9, #0x7fff
	cmp	r5, r9
	beq.n	.L0801284a
	cmp	r4, r9
	bne.n	.L08012886
.L0801284a:
	mov	r0, r7
	bl	rect_width_plus_one
	add.w	r0, r0, r0, lsr #0x1f
	asrs	r5, r0, #0x1
	mov	r0, r7
	bl	rect_height_plus_one
	add.w	r0, r0, r0, lsr #0x1f
	asrs	r0, r0, #0x1
	cmp	r8, r9
	bne.n	.L08012874
	adds	r1, r5, #0x1
	adds	r3, r0, #0x1
	cmp	r1, r3
	bge.n	.L08012870
	b.n	.L08012872
.L08012870:
	mov	r1, r3
.L08012872:
	mov	r8, r1
.L08012874:
	cmp	r4, r9
	bne.n	.L08012886
	adds	r1, r5, #0x1
	adds	r2, r0, #0x1
	cmp	r1, r2
	bge.n	.L08012884
	adds	r4, r5, #0x1
	b.n	.L08012886
.L08012884:
	mov	r4, r2
.L08012886:
	ldr	r0, .L080128e8
	bl	fn_08012618
	movs	r5, r0
	beq.n	.L080128e2
	str	r7, [r5, #0x0]
	strd	r8, r4, [r5, #0xc]
	ldrh	r0, [r6, #0x8]
	strh	r0, [r5, #0x4]
	mov	r0, sp
	str.w	r10, [r5, #0x8]
	bl	fn_0801c718
	ldr	r0, .L080128ec
	movs	r1, #0xff
	strd	r5, r0, [sp, #0x0]
	ldr	r0, .L080128f0
	str	r0, [sp, #0x8]
	ldr	r0, .L080128f4
	str	r0, [sp, #0xc]
	movs	r0, #0x0
	str	r0, [sp, #0x20]
	strd	r0, r1, [sp, #0x24]
	ldrh	r0, [r6, #0x0]
	str	r0, [sp, #0x2c]
	ldrh	r0, [r6, #0x2]
	ldrb.w	r1, [sp, #0x42]
	rsbs	r0, r0, #0
	str	r0, [sp, #0x30]
	ldr	r0, [r6, #0xc]
	str	r0, [sp, #0x1c]
	movs	r0, #0x0
	bfi	r1, r0, #0x0, #0x1
	strb.w	r1, [sp, #0x42]
	ldr	r0, [r6, #0x10]
	str	r0, [sp, #0x18]
	mov	r0, sp
	bl	fn_0801c7c0
.L080128e2:
	add	sp, #0x48
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L080128e8:
	.word 0x200080a4
.L080128ec:
	.word fn_0802aa00	@ function pointer 0x0802aa01
.L080128f0:
	.word fn_0802abe4	@ function pointer 0x0802abe5
.L080128f4:
	.word fn_0802ab40	@ function pointer 0x0802ab41

@ ----------------------------------------------------------------------------
@ fn_08012904 - parameters: object (r0, kept in r6), mask a (r1, kept in r9), mask b
@ (r2, kept in r8); r3 is saved on the stack (the stack slot at sp is passed to
@ fn_08026dc4 as its third argument).
@ Loops r4 = 0.. over ((halfword at object + 0x22 >> 3) & 0x3f) entries of 8 bytes at
@ *(object + 0xc), skipping entries whose word [1] has bit 25 set.
@ For entries where ((low16 of word [1] & ~mask a) == 0) differs from
@ ((low16 & ~mask b) == 0) calls fn_08026dc4(entry word [0], id, sp) (r10 holds the
@ entry word) for the ids 0x10, 0x11, 0x12, 0x13, 0x15, 0x14, 0x0a, 0x6a, 0x6b, 1, 4,
@ 2, 3, 5, 6, 0x32, 0x6d, 0x6c and returns 3 as soon as one returns nonzero.
@ Then tests the ids 0x68, 0x69, 0x6d, 0x6c, 0x37, 0x38, 0x35, 0x40, 0x45, 0x41, 0x42,
@ 0x43, 0x49: when one returns nonzero sets the result (r5) to 2; when all return 0
@ sets the result to 1 if it was 0 and leaves it unchanged otherwise.
@ Returns the result (0 when no entry matched).
@ ----------------------------------------------------------------------------
	.section .text.fn_08012904,"ax",%progbits
	.p2align 2
	.global fn_08012904
	.thumb_func
	.type fn_08012904, %function
fn_08012904:
	push.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	movs	r5, #0x0
	mov	r8, r2
	mov	r9, r1
	mov	r6, r0
	mov	r4, r5
	movs	r7, #0x4
	b.n	.L08012ae4
	nop	@ padding
.L08012918:
	ldr	r0, [r6, #0xc]
	add.w	r1, r7, r4, lsl #0x3
	ldr	r0, [r0, r1]
	lsls	r1, r0, #0x6
	bmi.n	.L08012a1e
	uxth	r0, r0
	bics.w	r1, r0, r9
	beq.n	.L08012952
	movs.w	r2, #0x0
.L08012930:
	bics.w	r0, r0, r8
	beq.n	.L08012956
	movs	r0, #0x0
.L08012938:
	cmp	r2, r0
	beq.n	.L08012a1e
	ldr	r0, [r6, #0xc]
	mov	r2, sp
	movs	r1, #0x10
	ldr.w	r0, [r0, r4, lsl #0x3]
	mov	r10, r0
	bl	fn_08026dc4
	cmp	r0, #0x0
	bne.n	.L08012a34
	b.n	.L0801295a
.L08012952:
	movs	r2, #0x1
	b.n	.L08012930
.L08012956:
	movs	r0, #0x1
	b.n	.L08012938
.L0801295a:
	mov	r2, sp
	movs	r1, #0x11
	mov	r0, r10
	bl	fn_08026dc4
	cmp	r0, #0x0
	bne.n	.L08012a34
	mov	r2, sp
	movs	r1, #0x12
	mov	r0, r10
	bl	fn_08026dc4
	cmp	r0, #0x0
	bne.n	.L08012a34
	mov	r2, sp
	movs	r1, #0x13
	mov	r0, r10
	bl	fn_08026dc4
	cmp	r0, #0x0
	bne.n	.L08012a34
	mov	r2, sp
	movs	r1, #0x15
	mov	r0, r10
	bl	fn_08026dc4
	cmp	r0, #0x0
	bne.n	.L08012a34
	mov	r2, sp
	movs	r1, #0x14
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a1c
	mov	r2, sp
	movs	r1, #0xa
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a1c
	mov	r2, sp
	movs	r1, #0x6a
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a1c
	mov	r2, sp
	movs	r1, #0x6b
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a1c
	mov	r2, sp
	movs	r1, #0x1
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a1c
	mov	r2, sp
	movs	r1, #0x4
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a1c
	mov	r2, sp
	movs	r1, #0x2
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a1c
	mov	r2, sp
	movs	r1, #0x3
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a1c
	mov	r2, sp
	movs	r1, #0x5
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a1c
	mov	r2, sp
	movs	r1, #0x6
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a1c
	mov	r2, sp
	movs	r1, #0x32
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a1c
	mov	r2, sp
	movs	r1, #0x6d
	b.n	.L08012a20
.L08012a1c:
	b.n	.L08012a34
.L08012a1e:
	b.n	.L08012ae2
.L08012a20:
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012a34
	mov	r2, sp
	movs	r1, #0x6c
	mov	r0, r10
	bl	fn_08026dc4
	cbz	r0, .L08012a3a
.L08012a34:
	movs	r0, #0x3
.L08012a36:
	pop.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08012a3a:
	mov	r2, sp
	movs	r1, #0x68
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ac4
	mov	r2, sp
	movs	r1, #0x69
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ac4
	mov	r2, sp
	movs	r1, #0x6d
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ac4
	mov	r2, sp
	movs	r1, #0x6c
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ac4
	mov	r2, sp
	movs	r1, #0x37
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ac4
	mov	r2, sp
	movs	r1, #0x38
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ac4
	mov	r2, sp
	movs	r1, #0x35
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ac4
	mov	r2, sp
	movs	r1, #0x40
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ac4
	mov	r2, sp
	movs	r1, #0x45
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ac4
	mov	r2, sp
	movs	r1, #0x41
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ac4
	mov	r2, sp
	movs	r1, #0x42
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ac4
	mov	r2, sp
	movs	r1, #0x43
	b.n	.L08012ac6
.L08012ac4:
	b.n	.L08012ada
.L08012ac6:
	mov	r0, r10
	bl	fn_08026dc4
	cbnz	r0, .L08012ada
	mov	r2, sp
	movs	r1, #0x49
	mov	r0, r10
	bl	fn_08026dc4
	cbz	r0, .L08012ade
.L08012ada:
	movs	r5, #0x2
	b.n	.L08012ae2
.L08012ade:
	cbnz	r5, .L08012ae2
	movs	r5, #0x1
.L08012ae2:
	.inst.n 0x1c64	@ adds r4, r4, #1
.L08012ae4:
	ldrh	r0, [r6, #0x22]
	ubfx	r0, r0, #0x3, #0x6
	cmp	r0, r4
	bhi.w	.L08012918
	mov	r0, r5
	b.n	.L08012a36

@ ----------------------------------------------------------------------------
@ return_word_200004b8 - no parameters. Returns the word at 0x200004b8 (the literal
@ holds 0x200004b4, the load is from offset 4).
@ ----------------------------------------------------------------------------
	.section .text.return_word_200004b8,"ax",%progbits
	.p2align 2
	.global return_word_200004b8
	.thumb_func
	.type return_word_200004b8, %function
return_word_200004b8:
	ldr	r0, .L08012afc
	ldr	r0, [r0, #0x4]
	bx	lr
	.short 0x0000	@ padding
.L08012afc:
	.word 0x200004b4

@ ----------------------------------------------------------------------------
@ return_only_08012b00 - no parameters. Single return (bx lr).
@ ----------------------------------------------------------------------------
	.section .text.return_only_08012b00,"ax",%progbits
	.global return_only_08012b00
	.thumb_func
	.type return_only_08012b00, %function
return_only_08012b00:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08013ce0 - parameters: r0 = object pointer (kept in r4), r1 = pointer to a
@ record (kept in r5): words at index 0-5 are sizes, halfword result at +0x18 and
@ +0x1a, words +0x10 and +0x14 are counts. No return value.
@ Calls fn_08023d80(r0, 0); when it returns 0 it tail-calls clear_bytes(r1, 0x1c)
@ and returns. Otherwise calls fn_080141bc(r0, r1) and fn_08013de0(r0, r1).
@ Collects fn_08024ac8, fn_08024b64, fn_0802492a, fn_08024d20, fn_080249e4 (all with
@ (r0, 0)), fn_08023e7c and fn_08023e48 and the byte of fn_08024bac(r0, 0, halfword
@ at 0x20000554 or halfword at 0x20000558).
@ First result: fn_0801b9f4(fn_08023e7c result, flag 1 when fn_08024d20 returned
@ 0x27d1 and bit 10 of the halfword at r0+0x22 is clear, byte, fn_08024ac8 result,
@ words +0x10, +8, +0, flag fn_0802492a result == 1) stored as halfword at r1+0x18.
@ Second result: fn_0801b9f4(fn_08023e48 result, flag 1 when fn_080249e4 returned
@ 0x27d1 and bit 9 of the halfword at r0+0x22 is clear, byte, fn_08024b64 result,
@ words +0x14, +0xc, +4, 0) stored as halfword at r1+0x1a.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013ce0,"ax",%progbits
	.p2align 2
	.global fn_08013ce0
	.thumb_func
	.type fn_08013ce0, %function
fn_08013ce0:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r5, r1
	sub	sp, #0x1c
	mov	r4, r0
	movs	r1, #0x0
	bl	fn_08023d80
	cbz	r0, .L08013d4c
	mov	r1, r5
	mov	r0, r4
	bl	fn_080141bc
	mov	r1, r5
	mov	r0, r4
	bl	fn_08013de0
	movs	r1, #0x0
	mov	r0, r4
	bl	fn_08024ac8
	str	r0, [sp, #0x14]
	movs	r1, #0x0
	mov	r0, r4
	bl	fn_08024b64
	str	r0, [sp, #0x10]
	movs	r1, #0x0
	mov	r0, r4
	bl	fn_0802492a
	cmp	r0, #0x1
	beq.n	.L08013d24
	movs	r0, #0x0
.L08013d24:
	mov	r8, r0
	movs	r1, #0x0
	mov	r0, r4
	bl	fn_08024d20
	mov	r7, r0
	movs	r1, #0x0
	mov	r0, r4
	bl	fn_080249e4
	movw	r9, #0x27d1
	mov	r6, r0
	cmp	r7, r9
	bne.n	.L08013d5a
	ldrh	r0, [r4, #0x22]
	lsls	r0, r0, #0x15
	bmi.n	.L08013d5a
	movs	r7, #0x1
	b.n	.L08013d5c
.L08013d4c:
	add	sp, #0x1c
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	movs	r1, #0x1c
	b.w	clear_bytes
.L08013d5a:
	movs	r7, #0x0
.L08013d5c:
	mov	r0, r4
	bl	fn_08023e7c
	ldr.w	r10, .L08013ddc
	mov	r11, r0
	mov	r0, r4
	movs	r1, #0x0
	ldrh.w	r2, [r10, #0x4]
	bl	fn_08024bac
	ldr.w	r12, [r5, #0x10]
	ldr	r3, [r5, #0x8]
	ldr	r1, [r5, #0x0]
	str.w	r12, [sp, #0x0]
	str.w	r8, [sp, #0xc]
	strd	r3, r1, [sp, #0x4]
	uxtb	r2, r0
	mov	r1, r7
	mov	r0, r11
	ldr	r3, [sp, #0x14]
	bl	fn_0801b9f4
	strh	r0, [r5, #0x18]
	cmp	r6, r9
	bne.n	.L08013da4
	ldrh	r0, [r4, #0x22]
	lsls	r0, r0, #0x16
	bmi.n	.L08013da4
	movs	r6, #0x1
	b.n	.L08013da6
.L08013da4:
	movs	r6, #0x0
.L08013da6:
	mov	r0, r4
	bl	fn_08023e48
	mov	r7, r0
	mov	r0, r4
	movs	r1, #0x0
	ldrh.w	r2, [r10, #0x8]
	bl	fn_08024bac
	uxtb	r2, r0
	ldr	r0, [r5, #0x14]
	movs	r4, #0x0
	ldr	r3, [r5, #0x4]
	ldr	r1, [r5, #0xc]
	stm.w	sp, {r0, r1, r3, r4}
	mov	r1, r6
	mov	r0, r7
	ldr	r3, [sp, #0x10]
	bl	fn_0801b9f4
	strh	r0, [r5, #0x1a]
	add	sp, #0x1c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short 0x0000	@ padding
.L08013ddc:
	.word 0x20000550	@ halfwords at +4 (0x20000554) and +8 (0x20000558) are read

@ ----------------------------------------------------------------------------
@ fn_08013de0 - parameters: r0 = object pointer (kept at [sp+4]), r1 = record
@ pointer (kept in r4): word +0 array A, word +8 array B, word +0x10 count. No
@ return value.
@ Gets the size list with fn_0801b13c(r0) (kept in r6) and fn_08023e7c(r0) (kept in
@ r10), the count with count_shorts_until_0x1fff, stores the count in the word at
@ +0x10 and allocates two halfword arrays of count * 2 bytes with fn_08022bac into the
@ words at +0 and +8.
@ For each entry equal to 0x1f9a it scans the children (fn_08023da4 count,
@ fn_08023d80 child) and takes the largest rect_width_plus_one value of the children
@ that pass any_flag_bit_set(child, 0x60001) == 0, fn_0801b160 == 1 and
@ fn_0801b14c == entry index (start value 0xffffe001), storing max(0, value) in
@ array B.
@ Sums the fixed sizes (entries below 0x1f9b are copied to array B, or take the array B
@ value for 0x1f9a) in r7 and the weights (entry - 0x1f9b for entries from 0x1f9b up)
@ in r5.
@ The remaining space is fn_08024ac8(r0, 0) * (1 - count) + fn_08023e7c(r0) - fixed
@ sum, at least 0. It is distributed over the weighted entries as
@ remaining * weight / weight sum (udiv) into array B, and the last weighted entry
@ gets remaining - remaining * (weight sum - its weight) / weight sum.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013de0,"ax",%progbits
	.p2align 2
	.global fn_08013de0
	.thumb_func
	.type fn_08013de0, %function
fn_08013de0:
	push.w	{r0, r1, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x4
	mov	r4, r1
	ldr	r0, [sp, #0x4]
	bl	fn_0801b13c
	mov	r6, r0
	ldr	r0, [sp, #0x4]
	bl	fn_08023e7c
	mov	r10, r0
	mov	r0, r6
	bl	count_shorts_until_0x1fff
	str	r0, [r4, #0x10]
	lsls	r0, r0, #0x1
	bl	fn_08022bac
	str	r0, [r4, #0x0]
	ldr	r0, [r4, #0x10]
	lsls	r0, r0, #0x1
	bl	fn_08022bac
	movs	r5, #0x0
	movw	r9, #0x1f9a
	str	r0, [r4, #0x8]
	b.n	.L08013e90
.L08013e1a:
	ldrsh.w	r1, [r6, r5, lsl #0x1]
	ldr.w	r8, .L08013f40
	cmp	r1, r9
	bne.n	.L08013e8e
	movs	r7, #0x0
	ldr.w	r11, .L08013f44
	b.n	.L08013e6e
.L08013e2e:
	mov	r1, r7
	ldr	r0, [sp, #0x4]
	bl	fn_08023d80
	mov	r1, r11
	str	r0, [sp, #0x0]
	bl	any_flag_bit_set
	cbnz	r0, .L08013e6c
	ldr	r0, [sp, #0x0]
	bl	fn_0801b160
	cmp	r0, #0x1
	bne.n	.L08013e6c
	ldr	r0, [sp, #0x0]
	bl	fn_0801b14c
	cmp	r0, r5
	bne.n	.L08013e6c
	ldr	r0, [sp, #0x0]
	bl	rect_width_plus_one
	mov	r1, r8
	cmp	r0, r8
	bge.n	.L08013e64
	mov	r0, r1
	b.n	.L08013e6a
.L08013e64:
	ldr	r0, [sp, #0x0]
	bl	rect_width_plus_one
.L08013e6a:
	mov	r8, r0
.L08013e6c:
	.inst.n 0x1c7f	@ adds r7, r7, #1
.L08013e6e:
	ldr	r0, [sp, #0x4]
	bl	fn_08023da4
	cmp	r0, r7
	bhi.n	.L08013e2e
	cmp.w	r8, #0x0
	blt.n	.L08013e86
	ldr	r1, [r4, #0x8]
	strh.w	r8, [r1, r5, lsl #0x1]
	b.n	.L08013e8e
.L08013e86:
	ldr	r1, [r4, #0x8]
	movs	r0, #0x0
	strh.w	r0, [r1, r5, lsl #0x1]
.L08013e8e:
	.inst.n 0x1c6d	@ adds r5, r5, #1
.L08013e90:
	ldr	r0, [r4, #0x10]
	cmp	r0, r5
	bhi.n	.L08013e1a
	movs	r5, #0x0
	mov	r7, r5
	mov	r0, r5
	movw	r8, #0x1f9b
	mov	r3, r9
	b.n	.L08013ed0
.L08013ea4:
	ldrsh.w	r1, [r6, r0, lsl #0x1]
	cmp	r1, r8
	blt.n	.L08013eb6
	add	r5, r1
	sub.w	r5, r5, #0x1f00
	subs	r5, #0x9b
	b.n	.L08013ece
.L08013eb6:
	cmp	r1, r3
	bne.n	.L08013ec4
	ldr	r1, [r4, #0x8]
	ldrh.w	r1, [r1, r0, lsl #0x1]
	add	r1, r7
	b.n	.L08013ecc
.L08013ec4:
	ldr	r2, [r4, #0x8]
	strh.w	r1, [r2, r0, lsl #0x1]
	add	r1, r7
.L08013ecc:
	sxth	r7, r1
.L08013ece:
	.inst.n 0x1c40	@ adds r0, r0, #1
.L08013ed0:
	ldr	r1, [r4, #0x10]
	cmp	r1, r0
	bhi.n	.L08013ea4
	movs	r1, #0x0
	ldr	r0, [sp, #0x4]
	bl	fn_08024ac8
	ldr	r1, [r4, #0x10]
	rsb.w	r2, r1, #0x1
	mla	r0, r0, r2, r10
	subs	r0, r0, r7
	sxth	r0, r0
	cmp	r0, #0x0
	bge.n	.L08013ef2
	movs	r0, #0x0
.L08013ef2:
	movs	r2, #0x0
	mov.w	r3, #0xffffffff
	mov	r1, r2
	mov	r12, r8
	b.n	.L08013f22
	nop	@ padding
.L08013f00:
	ldrsh.w	r7, [r6, r1, lsl #0x1]
	cmp	r7, r12
	blt.n	.L08013f20
	sub.w	r7, r7, #0x1f00
	subs	r7, #0x9b
	sxth	r2, r7
	smulbb	r3, r0, r2
	udiv	r3, r3, r5
	ldr	r7, [r4, #0x8]
	strh.w	r3, [r7, r1, lsl #0x1]
	mov	r3, r1
.L08013f20:
	.inst.n 0x1c49	@ adds r1, r1, #1
.L08013f22:
	ldr	r7, [r4, #0x10]
	cmp	r7, r1
	bhi.n	.L08013f00
	cmp	r3, #0x0
	blt.n	.L08013f3c
	subs	r1, r5, r2
	muls	r1, r0, r1
	udiv	r1, r1, r5
	subs	r0, r0, r1
	ldr	r1, [r4, #0x8]
	strh.w	r0, [r1, r3, lsl #0x1]
.L08013f3c:
	pop.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08013f40:
	.word 0xffffe001	@ start value of the largest-width search (-0x1fff)
.L08013f44:
	.word 0x00060001	@ flag mask passed to any_flag_bit_set

@ ----------------------------------------------------------------------------
@ fn_08013f48 - parameter: r0 = object pointer (kept at [sp]); returns the largest
@ extent as a signed 16-bit value.
@ Calls fn_08026298(r0, 0, 0), gets fn_08024984, fn_08024b70, fn_08024a80 (all
@ (r0, 0)) and fn_08024890(r0) and builds the minimum (r6) as the sum
@ fn_08024890 + (fn_08024b70 + fn_08024984) + (fn_08024a80 + fn_08024984), each sum
@ truncated to a signed 16-bit value (r9 and r8 hold the two partial sums).
@ Starts the maximum (r4) at 0xffffe001 (-0x1fff) and goes over the children
@ (fn_08023da4 count, pointer list at word +8 of the object, then word [0] of that):
@ skips a child when any_flag_bit_set(child, 0x40001) is not 0; a child with
@ fn_080254b0 not 0, or with kind fn_080248d8(child, 0) of 0, 1, 2 or 3 contributes
@ (halfword child+0x1a) - (halfword r0+0x16) + 1; other kinds with
@ fn_08024d44(child, 0) == 0 contribute (halfword +0x1a - halfword +0x16 + 1) + r9;
@ other kinds with fn_08024d44 not 0 are skipped.
@ Returns the larger of (maximum + r8, signed 16-bit) and the minimum, or the minimum
@ when no child counted.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013f48,"ax",%progbits
	.p2align 2
	.global fn_08013f48
	.thumb_func
	.type fn_08013f48, %function
fn_08013f48:
	push.w	{r0, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	movs	r2, #0x0
	mov	r1, r2
	ldr	r0, [sp, #0x0]
	bl	fn_08026298
	movs	r1, #0x0
	ldr	r0, [sp, #0x0]
	bl	fn_08024984
	mov	r4, r0
	movs	r1, #0x0
	ldr	r0, [sp, #0x0]
	bl	fn_08024b70
	add	r0, r4
	sxth.w	r9, r0
	movs	r1, #0x0
	ldr	r0, [sp, #0x0]
	bl	fn_08024a80
	add	r0, r4
	sxth.w	r8, r0
	ldr	r0, [sp, #0x0]
	bl	fn_08024890
	add.w	r1, r0, r9
	add.w	r0, r1, r8
	ldr.w	r10, .L08014024
	sxth	r6, r0
	mov	r4, r10
	ldr	r0, [sp, #0x0]
	bl	fn_08023da4
	mov	r7, r0
	movs	r5, #0x0
	b.n	.L08013ff4
.L08013f9e:
	ldr	r0, [sp, #0x0]
	ldr	r1, .L08014028
	ldr	r0, [r0, #0x8]
	ldr	r0, [r0, #0x0]
	ldr.w	r0, [r0, r5, lsl #0x2]
	mov	r11, r0
	bl	any_flag_bit_set
	cbnz	r0, .L08013ff2
	mov	r0, r11
	bl	fn_080254b0
	cbnz	r0, .L0801400c
	movs	r1, #0x0
	mov	r0, r11
	bl	fn_080248d8
	cbz	r0, .L0801400c
	cmp	r0, #0x1
	beq.n	.L0801400c
	cmp	r0, #0x2
	beq.n	.L0801400c
	cmp	r0, #0x3
	beq.n	.L0801400c
	movs	r1, #0x0
	mov	r0, r11
	bl	fn_08024d44
	cbnz	r0, .L08013ff2
	ldrh.w	r1, [r11, #0x1a]
	ldrh.w	r0, [r11, #0x16]
	subs	r0, r1, r0
	.inst.n 0x1c40	@ adds r0, r0, #1
	sxth	r0, r0
	add	r0, r9
	cmp	r0, r4
	blt.n	.L08013ff0
	mov	r4, r0
.L08013ff0:
	sxth	r4, r4
.L08013ff2:
	.inst.n 0x1c6d	@ adds r5, r5, #1
.L08013ff4:
	cmp	r5, r7
	bcc.n	.L08013f9e
	cmp	r4, r10
	beq.n	.L08014006
	add.w	r0, r4, r8
	sxth	r0, r0
	cmp	r0, r6
	bgt.n	.L08014008
.L08014006:
	mov	r0, r6
.L08014008:
	pop.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801400c:
	ldr	r0, [sp, #0x0]
	ldrsh.w	r1, [r11, #0x1a]
	ldrsh.w	r0, [r0, #0x16]
	subs	r0, r1, r0
	adds	r1, r0, #0x1
	cmp	r1, r4
	blt.n	.L08013ff0
	mov	r4, r1
	b.n	.L08013ff0
	.short 0x0000	@ padding
.L08014024:
	.word 0xffffe001	@ start value of the maximum (-0x1fff)
.L08014028:
	.word 0x00040001	@ flag mask passed to any_flag_bit_set

@ ----------------------------------------------------------------------------
@ fn_0801402c - parameters: r0 = object pointer (kept in r8), r3 passed on unchanged to
@ fn_0802626c (r1 and r2 are set to 0 and are not inputs); returns the largest
@ extent as a signed 16-bit value.
@ Calls fn_0802626c(r0, 0, 0, r3), gets fn_08024984, fn_08024b1c, fn_08024ae0 (all
@ (r0, 0)) and fn_080248ac(r0); with r10 = fn_08024b1c + fn_08024984 and
@ r9 = fn_08024ae0 + fn_08024984 (each signed 16-bit) the minimum (r5) is
@ fn_080248ac + r9 + r10.
@ Starts the maximum (r4) at 0xffffe001 (-0x1fff) and goes over the children
@ (fn_08023da4 count in r7, pointer list at word +8, then word [0] of that),
@ skipping a child when any_flag_bit_set(child, 0x40001) is not 0.
@ When fn_08024906(r0, 0) == 1: a child with fn_080254b0 not 0 contributes
@ (halfword r0+0x18) - (halfword child+0x14) + 1, kinds fn_080248d8 of 0, 3, 6 or 8
@ contribute the same value, other kinds with fn_08024d38 == 0 contribute
@ rect_width_0801d052(child + 0x14) + r10 and kinds with fn_08024d38 not 0 are
@ skipped; the result is the larger of maximum + r9 and the minimum.
@ Otherwise: a child with fn_080254b0 not 0 or of kind 0, 1, 4 or 7 contributes
@ (halfword child+0x18) - (halfword r0+0x14) + 1, other kinds with fn_08024d44 == 0
@ contribute rect_width_0801d052(child + 0x14) + r9 and kinds with fn_08024d44 not 0
@ are skipped; the result is the larger of maximum + r10 and the minimum.
@ Returns the minimum when no child counted or when the maximum plus its offset is
@ not above the minimum.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801402c,"ax",%progbits
	.p2align 2
	.global fn_0801402c
	.thumb_func
	.type fn_0801402c, %function
fn_0801402c:
	push.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	movs	r2, #0x0
	mov	r8, r0
	mov	r1, r2
	bl	fn_0802626c
	movs	r1, #0x0
	mov	r0, r8
	bl	fn_08024984
	mov	r4, r0
	movs	r1, #0x0
	mov	r0, r8
	bl	fn_08024b1c
	add	r0, r4
	sxth.w	r10, r0
	movs	r1, #0x0
	mov	r0, r8
	bl	fn_08024ae0
	add	r0, r4
	sxth.w	r9, r0
	mov	r0, r8
	bl	fn_080248ac
	add.w	r1, r0, r9
	add.w	r0, r1, r10
	ldr.w	r11, .L080141b4
	sxth	r5, r0
	mov	r4, r11
	mov	r0, r8
	bl	fn_08023da4
	mov	r7, r0
	movs	r1, #0x0
	mov	r0, r8
	bl	fn_08024906
	cmp	r0, #0x1
	mov.w	r6, #0x0
	beq.n	.L08014118
	b.n	.L08014182
.L08014090:
	ldr.w	r0, [r8, #0x8]
	ldr	r1, .L080141b8
	ldr	r0, [r0, #0x0]
	ldr.w	r0, [r0, r6, lsl #0x2]
	str	r0, [sp, #0x0]
	bl	any_flag_bit_set
	cbnz	r0, .L08014116
	ldr	r0, [sp, #0x0]
	bl	fn_080254b0
	cbz	r0, .L080140c2
	ldr	r0, [sp, #0x0]
	ldrsh.w	r1, [r8, #0x18]
	ldrsh.w	r0, [r0, #0x14]
	subs	r1, r1, r0
	adds	r0, r1, #0x1
	cmp	r0, r4
	blt.n	.L08014114
	adds	r4, r1, #0x1
	b.n	.L08014114
.L080140c2:
	movs	r1, #0x0
	ldr	r0, [sp, #0x0]
	bl	fn_080248d8
	cbz	r0, .L080140e4
	cmp	r0, #0x3
	beq.n	.L080140e4
	cmp	r0, #0x6
	beq.n	.L080140e4
	cmp	r0, #0x8
	beq.n	.L080140e4
	movs	r1, #0x0
	ldr	r0, [sp, #0x0]
	bl	fn_08024d38
	cbz	r0, .L080140fa
	b.n	.L08014116
.L080140e4:
	ldr	r0, [sp, #0x0]
	ldrsh.w	r1, [r8, #0x18]
	ldrsh.w	r0, [r0, #0x14]
	subs	r0, r1, r0
	adds	r1, r0, #0x1
	cmp	r1, r4
	blt.n	.L08014114
	mov	r4, r1
	b.n	.L08014114
.L080140fa:
	ldr	r0, [sp, #0x0]
	adds	r0, #0x14
	str	r0, [sp, #0x0]
	bl	rect_width_0801d052
	add	r0, r10
	cmp	r0, r4
	blt.n	.L08014114
	ldr	r0, [sp, #0x0]
	bl	rect_width_0801d052
	add.w	r4, r0, r10
.L08014114:
	sxth	r4, r4
.L08014116:
	.inst.n 0x1c76	@ adds r6, r6, #1
.L08014118:
	cmp	r6, r7
	bcc.n	.L08014090
	cmp	r4, r11
	beq.n	.L08014198
	add.w	r0, r4, r9
	b.n	.L0801418e
	nop	@ padding
.L08014128:
	ldr.w	r0, [r8, #0x8]
	ldr	r1, .L080141b8
	ldr	r0, [r0, #0x0]
	ldr.w	r0, [r0, r6, lsl #0x2]
	str	r0, [sp, #0x0]
	bl	any_flag_bit_set
	cbnz	r0, .L08014180
	ldr	r0, [sp, #0x0]
	bl	fn_080254b0
	cbnz	r0, .L0801419e
	movs	r1, #0x0
	ldr	r0, [sp, #0x0]
	bl	fn_080248d8
	cbz	r0, .L0801419e
	cmp	r0, #0x1
	beq.n	.L0801419e
	cmp	r0, #0x4
	beq.n	.L0801419e
	cmp	r0, #0x7
	beq.n	.L0801419e
	movs	r1, #0x0
	ldr	r0, [sp, #0x0]
	bl	fn_08024d44
	cbnz	r0, .L08014180
	ldr	r0, [sp, #0x0]
	adds	r0, #0x14
	str	r0, [sp, #0x0]
	bl	rect_width_0801d052
	add	r0, r9
	cmp	r0, r4
	blt.n	.L0801417e
	ldr	r0, [sp, #0x0]
	bl	rect_width_0801d052
	add.w	r4, r0, r9
.L0801417e:
	sxth	r4, r4
.L08014180:
	.inst.n 0x1c76	@ adds r6, r6, #1
.L08014182:
	cmp	r6, r7
	bcc.n	.L08014128
	cmp	r4, r11
	beq.n	.L08014198
	add.w	r0, r4, r10
.L0801418e:
	sxth	r0, r0
	cmp	r0, r11
	beq.n	.L08014198
	cmp	r0, r5
	bgt.n	.L0801419a
.L08014198:
	mov	r0, r5
.L0801419a:
	pop.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801419e:
	ldr	r0, [sp, #0x0]
	ldrsh.w	r1, [r0, #0x18]
	ldrsh.w	r0, [r8, #0x14]
	subs	r1, r1, r0
	adds	r0, r1, #0x1
	cmp	r0, r4
	blt.n	.L0801417e
	adds	r4, r1, #0x1
	b.n	.L0801417e
.L080141b4:
	.word 0xffffe001	@ start value of the maximum (-0x1fff)
.L080141b8:
	.word 0x00040001	@ flag mask passed to any_flag_bit_set

@ ----------------------------------------------------------------------------
@ fn_080141bc - parameters: r0 = object pointer (kept in r11), r1 = record pointer
@ (kept in r4): word +4 array A, word +0xc array B, word +0x14 count. No return value.
@ Same algorithm as fn_08013de0 on the vertical axis: list from fn_0801b7c8 (kept in
@ r6), count from count_shorts_until_0x1fff stored at +0x14, two halfword arrays
@ allocated with fn_08022bac (count * 2) into +4 and +0xc.
@ Entries equal to 0x1f9a take the largest rect_height_plus_one value of the children
@ that pass any_flag_bit_set(child, 0x60001) == 0, fn_0801b8d8 == 1 and
@ fn_0801b8c4 == entry index (start value 0xffffe001), stored as max(0, value) in
@ array B.
@ The remaining space is fn_08024b64(r0, 0) * (1 - count) + fn_08023e48(r0) - fixed
@ sum, at least 0, distributed over the entries from 0x1f9b up as
@ remaining * weight / weight sum; the last weighted entry gets
@ remaining - remaining * (weight sum - its weight) / weight sum.
@ ----------------------------------------------------------------------------
	.section .text.fn_080141bc,"ax",%progbits
	.p2align 2
	.global fn_080141bc
	.thumb_func
	.type fn_080141bc, %function
fn_080141bc:
	push.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r4, r1
	mov	r11, r0
	bl	fn_0801b7c8
	mov	r6, r0
	bl	count_shorts_until_0x1fff
	str	r0, [r4, #0x14]
	lsls	r0, r0, #0x1
	bl	fn_08022bac
	str	r0, [r4, #0x4]
	ldr	r0, [r4, #0x14]
	lsls	r0, r0, #0x1
	bl	fn_08022bac
	movs	r5, #0x0
	movw	r9, #0x1f9a
	str	r0, [r4, #0xc]
	b.n	.L08014260
.L080141ea:
	ldrsh.w	r0, [r6, r5, lsl #0x1]
	ldr.w	r8, .L08014318
	cmp	r0, r9
	bne.n	.L0801425e
	movs	r7, #0x0
	ldr.w	r10, .L0801431c
	b.n	.L0801423e
.L080141fe:
	mov	r1, r7
	mov	r0, r11
	bl	fn_08023d80
	mov	r1, r10
	str	r0, [sp, #0x0]
	bl	any_flag_bit_set
	cbnz	r0, .L0801423c
	ldr	r0, [sp, #0x0]
	bl	fn_0801b8d8
	cmp	r0, #0x1
	bne.n	.L0801423c
	ldr	r0, [sp, #0x0]
	bl	fn_0801b8c4
	cmp	r0, r5
	bne.n	.L0801423c
	ldr	r0, [sp, #0x0]
	bl	rect_height_plus_one
	mov	r1, r8
	cmp	r0, r8
	bge.n	.L08014234
	mov	r0, r1
	b.n	.L0801423a
.L08014234:
	ldr	r0, [sp, #0x0]
	bl	rect_height_plus_one
.L0801423a:
	mov	r8, r0
.L0801423c:
	.inst.n 0x1c7f	@ adds r7, r7, #1
.L0801423e:
	mov	r0, r11
	bl	fn_08023da4
	cmp	r0, r7
	bhi.n	.L080141fe
	cmp.w	r8, #0x0
	blt.n	.L08014256
	ldr	r1, [r4, #0xc]
	strh.w	r8, [r1, r5, lsl #0x1]
	b.n	.L0801425e
.L08014256:
	ldr	r1, [r4, #0xc]
	movs	r0, #0x0
	strh.w	r0, [r1, r5, lsl #0x1]
.L0801425e:
	.inst.n 0x1c6d	@ adds r5, r5, #1
.L08014260:
	ldr	r0, [r4, #0x14]
	cmp	r0, r5
	bhi.n	.L080141ea
	movs	r5, #0x0
	mov	r7, r5
	mov	r0, r5
	movw	r8, #0x1f9b
	mov	r3, r9
	b.n	.L080142a0
.L08014274:
	ldrsh.w	r1, [r6, r0, lsl #0x1]
	cmp	r1, r8
	blt.n	.L08014286
	add	r5, r1
	sub.w	r5, r5, #0x1f00
	subs	r5, #0x9b
	b.n	.L0801429e
.L08014286:
	cmp	r1, r3
	bne.n	.L08014294
	ldr	r1, [r4, #0xc]
	ldrh.w	r1, [r1, r0, lsl #0x1]
	add	r1, r7
	b.n	.L0801429c
.L08014294:
	ldr	r2, [r4, #0xc]
	strh.w	r1, [r2, r0, lsl #0x1]
	add	r1, r7
.L0801429c:
	sxth	r7, r1
.L0801429e:
	.inst.n 0x1c40	@ adds r0, r0, #1
.L080142a0:
	ldr	r1, [r4, #0x14]
	cmp	r1, r0
	bhi.n	.L08014274
	movs	r1, #0x0
	mov	r0, r11
	bl	fn_08024b64
	mov	r9, r0
	mov	r0, r11
	bl	fn_08023e48
	mov	r1, r0
	ldr	r0, [r4, #0x14]
	rsb.w	r2, r0, #0x1
	mla	r0, r9, r2, r1
	subs	r0, r0, r7
	sxth	r0, r0
	cmp	r0, #0x0
	bge.n	.L080142cc
	movs	r0, #0x0
.L080142cc:
	movs	r2, #0x0
	mov.w	r3, #0xffffffff
	mov	r1, r2
	mov	r12, r8
	b.n	.L080142fa
.L080142d8:
	ldrsh.w	r7, [r6, r1, lsl #0x1]
	cmp	r7, r12
	blt.n	.L080142f8
	sub.w	r7, r7, #0x1f00
	subs	r7, #0x9b
	sxth	r2, r7
	smulbb	r3, r0, r2
	udiv	r3, r3, r5
	ldr	r7, [r4, #0xc]
	strh.w	r3, [r7, r1, lsl #0x1]
	mov	r3, r1
.L080142f8:
	.inst.n 0x1c49	@ adds r1, r1, #1
.L080142fa:
	ldr	r7, [r4, #0x14]
	cmp	r7, r1
	bhi.n	.L080142d8
	cmp	r3, #0x0
	blt.n	.L08014314
	subs	r1, r5, r2
	muls	r1, r0, r1
	udiv	r1, r1, r5
	subs	r0, r0, r1
	ldr	r1, [r4, #0xc]
	strh.w	r0, [r1, r3, lsl #0x1]
.L08014314:
	pop.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08014318:
	.word 0xffffe001	@ start value of the largest-height search (-0x1fff)
.L0801431c:
	.word 0x00060001	@ flag mask passed to any_flag_bit_set

@ ----------------------------------------------------------------------------
@ call_with_offset_rect - parameters: r0 = object pointer (halfwords at +8 and +10 =
@ offset x and y, function pointer at +0x14), r1 = pointer to four halfwords
@ (x0, y0, x1, y1). No return value.
@ Builds a rectangle at sp: x0 + halfword at r0+8, y0 + halfword at r0+10,
@ x1 + halfword at r0+8, y1 + halfword at r0+10.
@ Calls the function pointer at r0+0x14 with (r0, pointer to the rectangle).
@ ----------------------------------------------------------------------------
	.section .text.call_with_offset_rect,"ax",%progbits
	.p2align 2
	.global call_with_offset_rect
	.thumb_func
	.type call_with_offset_rect, %function
call_with_offset_rect:
	push	{r2, r3, r4, lr}
	ldrh	r3, [r1, #0x0]
	ldrh	r4, [r0, #0x8]
	add	r3, r4
	strh.w	r3, [sp, #0x0]
	ldrh	r3, [r1, #0x2]
	ldrh	r4, [r0, #0xa]
	add	r3, r4
	strh.w	r3, [sp, #0x2]
	ldrh	r3, [r1, #0x4]
	ldrh	r4, [r0, #0x8]
	add	r3, r4
	strh.w	r3, [sp, #0x4]
	ldrh	r1, [r1, #0x6]
	ldrh	r3, [r0, #0xa]
	add	r1, r3
	strh.w	r1, [sp, #0x6]
	ldr	r3, [r0, #0x14]
	mov	r1, sp
	blx	r3
	pop	{r2, r3, r4, pc}
	.short 0x0000	@ padding
