@ gui_25.s - GUI module part 25: circle hit test, display setup, hit search, rectangle merging, object transition
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080269b8 - circle containment test.
@ r0 = rectangle (x1, y1, x2, y2 as signed halfwords at +0, +2, +4, +6),
@ r1 = point (x, y halfwords).
@ r = (x2 - x1) / 2 (rounded toward zero). Returns 1 in r0 when
@ (px - (x1 + r))^2 + (py - (y1 + r))^2 <= r*r (unsigned compare of the
@ products), else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080269b8,"ax",%progbits
	.p2align 2
	.global fn_080269b8
	.thumb_func
	.type fn_080269b8, %function
fn_080269b8:
	push	{r4, lr}
	ldrsh.w	r2, [r0, #4]
	ldrsh.w	r3, [r0]
	ldrh	r0, [r0, #2]
	subs	r2, r2, r3
	add.w	r2, r2, r2, lsr #31	@ round the division toward zero
	asrs	r2, r2, #1		@ r2 = r = (x2 - x1) / 2
	ldrh	r4, [r1]
	add	r3, r2			@ r3 = x1 + r
	ldrh	r1, [r1, #2]
	add	r0, r2			@ r0 = y1 + r
	subs	r3, r4, r3		@ r3 = px - (x1 + r)
	subs	r0, r1, r0		@ r0 = py - (y1 + r)
	smulbb	r1, r2, r2		@ r1 = r*r
	smulbb	r2, r3, r3
	smlabb	r0, r0, r0, r2		@ r0 = dx*dx + dy*dy
	cmp	r0, r1
	bhi	.L080269ec
	movs	r0, #1
	pop	{r4, pc}
.L080269ec:
	movs	r0, #0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080269f0 - sets up the object at 0x20008000 (halfwords 0x140 and 0xf0).
@ No parameters; ends in a tail branch.
@ Calls fn_0801dafc(0x200066e4, 0x20006700, 0, 0xc80) (r1 = 0x20006700 from
@ the literal at 0x08026a34, r0 = r1 - 0x1c) and fn_0801db1c(0x20008000).
@ Then, with r0 = 0x20008000: halfword [r0+0] = 0x140, halfword [r0+2] = 0xf0,
@ word [r0+20] = 0x08014f9d (fn_08014f9c plus the Thumb bit), word [r0+12] =
@ 0x200066e4, and word [r0+16] has bits 0x30 cleared and bit 0x04 set.
@ Restores lr and tail-calls fn_0801db6c(0x20008000).
@ ----------------------------------------------------------------------------
	.section .text.fn_080269f0,"ax",%progbits
	.p2align 2
	.global fn_080269f0
	.thumb_func
	.type fn_080269f0, %function
fn_080269f0:
	ldr	r1, .L08026a34
	push	{r4, lr}
	mov.w	r3, #0xc80
	movs	r2, #0
	sub.w	r0, r1, #0x1c		@ r0 = 0x200066e4
	bl	fn_0801dafc
	ldr	r0, .L08026a38
	bl	fn_0801db1c
	ldr	r0, .L08026a38
	mov.w	r1, #0x140
	strh	r1, [r0]
	movs	r1, #0xf0
	strh	r1, [r0, #2]
	ldr	r1, .L08026a3c
	str	r1, [r0, #0x14]
	ldr	r1, .L08026a34
	subs	r1, #0x1c
	str	r1, [r0, #0xc]
	ldr	r1, [r0, #0x10]
	bic	r1, r1, #0x30
	orr	r1, r1, #4
	str	r1, [r0, #0x10]
	pop.w	{r4, lr}
	b.w	fn_0801db6c
	.short	0x0000			@ padding
.L08026a34:
	.word	0x20006700
.L08026a38:
	.word	0x20008000
.L08026a3c:
.ifdef OWN
	.word	own_flush		@ flush pointer: own/screen.s (then fn_08014f9c)
.else
	.word	fn_08014f9c		@ function pointer 0x08014f9d
.endif

@ ----------------------------------------------------------------------------
@ fn_08026a40 - hit search over an object tree.
@ r0 = point pointer, r1 = object, r2 and r3 unused (r2 is set to 0 for
@ fn_08011e9c). Returns the hit object or 0.
@ Tests the point against the rectangle at object+0x14 with fn_08011e9c;
@ continues only when all_flag_bits_set(object, 1) is 0 and fn_08012732(object)
@ is 0. Sends message 0x12 with a record holding the point (byte at sp+0
@ cleared, point at sp+4) through fn_080207f4; when the result byte is 2
@ returns 0.
@ Recurses over the children from the last (count from fn_08023da4, children
@ list through [[object+8]]) down to the first and returns the first nonzero
@ hit; when none hits returns the object if the result byte is 0, else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026a40,"ax",%progbits
	.p2align 2
	.global fn_08026a40
	.thumb_func
	.type fn_08026a40, %function
fn_08026a40:
	push.w	{r2, r3, r4, r5, r6, r7, r8, lr}
	mov	r6, r1			@ r6 = object
	movs	r5, #0			@ r5 = hit result
	mov	r7, r0			@ r7 = point
	mov	r2, r5
	adds	r1, #0x14
	bl	fn_08011e9c
	cmp	r0, #0
	beq.n	.L08026aa4
	movs	r1, #1
	mov	r0, r6
	bl	all_flag_bits_set
	cbnz	r0, .L08026aa2
	mov	r0, r6
	bl	fn_08012732
	cbnz	r0, .L08026aa2
	movs	r0, #0
	strb.w	r0, [sp]		@ result byte of the message record
	mov	r2, sp
	movs	r1, #0x12
	mov	r0, r6
	str	r7, [sp, #4]		@ point into the record
	bl	fn_080207f4
	ldrb.w	r0, [sp]
	cmp	r0, #2
	beq.n	.L08026aa2
	mov	r0, r6
	bl	fn_08023da4
	.inst.n	0x1e40			@ subs r0, r0, #1
	movs	r4, r0
	bmi.n	.L08026aac
.L08026a8e:
	ldr	r0, [r6, #8]
	ldr	r0, [r0]
	ldr.w	r1, [r0, r4, lsl #2]	@ child number r4
	mov	r0, r7
	bl	fn_08026a40
	movs	r5, r0
	bne.n	.L08026ab4
	b.n	.L08026aa8
.L08026aa2:
	movs	r0, #0
.L08026aa4:
	pop.w	{r2, r3, r4, r5, r6, r7, r8, pc}
.L08026aa8:
	.inst.n	0x1e64			@ subs r4, r4, #1
	bpl.n	.L08026a8e
.L08026aac:
	ldrb.w	r0, [sp]
	cbnz	r0, .L08026ab4
	mov	r5, r6			@ no child hit: the object itself
.L08026ab4:
	mov	r0, r5
	b.n	.L08026aa4

@ ----------------------------------------------------------------------------
@ fn_08026ab8 - merges overlapping rectangles of the table.
@ r0..r3 unused; no return value.
@ Uses the table base in the word at 0x200004b4: for each pair (i, j) of
@ entries below the halfword at base+0x150 whose marker bytes at base+0x130+i
@ and base+0x130+j are 0 and that differ, tests the 8-byte rectangles at
@ base+0x30+idx*8 with rect_overlaps; when they overlap it computes the union
@ with rect_union and, when rect_area of the union is smaller than the sum of
@ the areas of both rectangles, copies the union into rectangle i
@ (copy_rect_0801cfc4) and marks j with 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026ab8,"ax",%progbits
	.p2align 2
	.global fn_08026ab8
	.thumb_func
	.type fn_08026ab8, %function
fn_08026ab8:
	push.w	{r2, r3, r4, r5, r6, r7, r8, lr}
	movs	r5, #0			@ r5 = i
	ldr.w	r8, .L08026b74
	b.n	.L08026b64
.L08026ac4:
	add	r1, r5
	ldrb.w	r1, [r1, #0x130]
	cbnz	r1, .L08026b48
	movs	r4, #0			@ r4 = j
	b.n	.L08026b54
.L08026ad0:
	adds	r1, r0, r4
	ldrb.w	r1, [r1, #0x130]
	cbnz	r1, .L08026b4a
	cmp	r5, r4
	beq.n	.L08026b52
	add.w	r1, r0, r4, lsl #3
	add.w	r0, r0, r5, lsl #3
	adds	r0, #0x30
	adds	r1, #0x30
	bl	rect_overlaps
	cbz	r0, .L08026b4a
	ldr	r0, [r6, #4]
	mov	r8, r6
	add.w	r2, r0, r4, lsl #3
	add.w	r1, r0, r5, lsl #3
	mov	r0, sp
	adds	r1, #0x30
	adds	r2, #0x30
	bl	rect_union
	mov	r0, sp
	bl	rect_area
	mov	r6, r0			@ r6 = area of the union
	ldr.w	r0, [r8, #4]
	add.w	r0, r0, r5, lsl #3
	adds	r0, #0x30
	bl	rect_area
	mov	r7, r0			@ r7 = area of rectangle i
	ldr.w	r0, [r8, #4]
	add.w	r0, r0, r4, lsl #3
	adds	r0, #0x30
	bl	rect_area
	add	r0, r7
	cmp	r6, r0
	bhs.n	.L08026b52
	ldr.w	r0, [r8, #4]
	mov	r6, r8
	add.w	r0, r0, r5, lsl #3
	mov	r1, sp
	adds	r0, #0x30
	bl	copy_rect_0801cfc4
	movs	r0, #1
	ldr	r1, [r6, #4]
	b.n	.L08026b4c
.L08026b48:
	b.n	.L08026b62
.L08026b4a:
	b.n	.L08026b52
.L08026b4c:
	add	r1, r4
	strb.w	r0, [r1, #0x130]	@ mark entry j
.L08026b52:
	.inst.n	0x1c64			@ adds r4, r4, #1
.L08026b54:
	ldr.w	r0, [r8, #4]
	mov	r6, r8
	ldrh.w	r1, [r0, #0x150]
	cmp	r1, r4
	bhi.n	.L08026ad0
.L08026b62:
	.inst.n	0x1c6d			@ adds r5, r5, #1
.L08026b64:
	ldr.w	r1, [r8, #4]
	ldrh.w	r2, [r1, #0x150]
	cmp	r2, r5
	bhi.n	.L08026ac4
	pop.w	{r2, r3, r4, r5, r6, r7, r8, pc}
.L08026b74:
	.word	0x200004b4

@ ----------------------------------------------------------------------------
@ fn_08026b78 - no parameters; returns the result of fn_0801dd5c.
@ Calls fn_0801dccc, then tail-calls fn_0801dd5c.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026b78,"ax",%progbits
	.p2align 2
	.global fn_08026b78
	.thumb_func
	.type fn_08026b78, %function
fn_08026b78:
	push	{r4, lr}
	bl	fn_0801dccc
	pop.w	{r4, lr}
	b.w	fn_0801dd5c
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08026b88 - switches an object transition.
@ r0 = new object (kept in r9), r1 = transition code (r5), r2 = dx (r6),
@ r3 = dy (r8), stack argument at [sp+0xb8] = flag (r10, bit 0 used); no
@ return value.
@ r4 = fn_08023ebc(); r7 = fn_08026b78() (no argument; calls fn_0801dccc
@ then tail-jumps to fn_0801dd5c).
@ When the word [r4+0x18] is nonzero and differs from r7: fn_0802939a(old),
@ fn_0801c688(old, 0), fn_0802636a(old, 0, 0), fn_08025e80(old, 0x60, 0);
@ when bit 1 of the byte [r4+0x28] is set it also calls fn_08023690(r7);
@ then r7 = old [r4+0x18].
@ Word [r4+0x18] = new object; when the word [r4+0x14] is nonzero and bit 1
@ of the byte [r4+0x28] is set: fn_08023690([r4+0x14]) and word [r4+0x14] = 0.
@ Byte [r4+0x28]: bit 0 = 1 when the code is 10..14, else 0; bit 1 = bit 0 of
@ the flag (bit 0 is cleared and bit 1 inserted with bfi).
@ Then fn_0801c688(obj, 0); fn_0801c688(fn_08026b78(), 0);
@ fn_0802636a(obj, 0, 0); fn_0802636a(fn_08026b78(), 0, 0);
@ fn_08025e80(obj, 0x60, 0); fn_08025e80(fn_08026b78(), 0x60, 0).
@ When dx OR dy is 0: fn_0802939a(obj) and return.
@ Else two records on the stack: record 1 at sp+0x50 (fn_0801c718(sp+0x50);
@ word sp+0x58 = 0x08029377, word sp+0x5c = 0x08029321, word sp+0x50 = obj,
@ words sp+0x7c = dx and sp+0x80 = -dy) and record 2 at sp+0x0c
@ (fn_0801c718(sp+0x0c); word sp+0x0c = word [r4+0x10], words sp+0x38 = dx and
@ sp+0x3c = -dy).
@ Code >= 0xf skips to the final step; codes 0..0xe go through the tbb table
@ at 0x08026c90, with F1 = fn_0801dcfc(r4) and F2 = fn_0801dd88(r4), callbacks
@ CA = 0x080297bd, CB = 0x080297c3, CC = 0x08028ac9. Record 1 callback word
@ sp+0x54 and value words sp+0x70, sp+0x74, sp+0x78: code 0: CA, 0, 0, 0;
@ 1: CA, F1, F1, 0; 2: CA, -F1, -F1, 0; 3: CB, F2, F2, 0; 4: CB, -F2, -F2, 0;
@ 5: CA, F1, F1, 0; 6: CA, -F1, -F1, 0; 7: CB, F2, F2, 0; 8: CB, -F2, -F2, 0;
@ 9: CC, 0, 0, 0xff. Record 2 callback word sp+0x10 and words sp+0x2c,
@ sp+0x30, sp+0x34: code 5: CA, 0, 0, -F1; 6: CA, 0, 0, F1; 7: CB, 0, 0, -F2;
@ 8: CB, 0, 0, F2; 0xa: CC, 0xff, 0xff, 0; 0xb: CA, 0, 0, -F1; 0xc: CA, 0, 0,
@ F1; 0xd: CB, 0, 0, -F2; 0xe: CB, 0, 0, F2. Codes 0..4 and 9 leave the
@ record 2 fields unset in this function; codes 5..8 set both records.
@ Final step (0x08026d96): fn_080207f4(r7, 0x25, 0), then fn_0801c7c0(sp+0x50)
@ and fn_0801c7c0(sp+0x0c); return at 0x08026cac.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026b88,"ax",%progbits
	.p2align 2
	.global fn_08026b88
	.thumb_func
	.type fn_08026b88, %function
fn_08026b88:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	sub	sp, #0x98
	mov	r8, r3			@ r8 = dy
	mov	r6, r2			@ r6 = dx
	mov	r5, r1			@ r5 = transition code
	mov	r9, r0			@ r9 = new object
	ldr.w	r10, [sp, #0xb8]	@ r10 = flag
	bl	fn_08023ebc
	mov	r4, r0
	bl	fn_08026b78
	mov	r7, r0
	ldr	r0, [r4, #0x18]
	cbz	r0, .L08026bde
	cmp	r0, r7
	beq.n	.L08026bde
	bl	fn_0802939a
	movs	r1, #0
	ldr	r0, [r4, #0x18]
	bl	fn_0801c688
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r4, #0x18]
	bl	fn_0802636a
	movs	r2, #0
	movs	r1, #0x60
	ldr	r0, [r4, #0x18]
	bl	fn_08025e80
	ldrb.w	r0, [r4, #0x28]
	lsls	r0, r0, #0x1e		@ bit 1 of the byte into the sign
	bpl.n	.L08026bdc
	mov	r0, r7
	bl	fn_08023690
.L08026bdc:
	ldr	r7, [r4, #0x18]
.L08026bde:
	str.w	r9, [r4, #0x18]
	ldr	r0, [r4, #0x14]
	cbz	r0, .L08026bf6
	ldrb.w	r1, [r4, #0x28]
	lsls	r1, r1, #0x1e
	bpl.n	.L08026bf6
	bl	fn_08023690
	movs	r0, #0
	str	r0, [r4, #0x14]
.L08026bf6:
	cmp	r5, #0xa
	beq.n	.L08026ca0
	cmp	r5, #0xb
	beq.n	.L08026ca0
	cmp	r5, #0xc
	beq.n	.L08026ca0
	cmp	r5, #0xd
	beq.n	.L08026ca0
	cmp	r5, #0xe
	beq.n	.L08026ca0
	movs	r1, #0			@ bit 0 value: codes 10..14 give 1
.L08026c0c:
	ldrb.w	r0, [r4, #0x28]
	bfi	r0, r1, #0, #1
	bfi	r0, r10, #1, #1
	strb.w	r0, [r4, #0x28]
	movs	r1, #0
	mov	r0, r9
	bl	fn_0801c688
	bl	fn_08026b78
	movs	r1, #0
	bl	fn_0801c688
	movs	r2, #0
	mov	r1, r2
	mov	r0, r9
	bl	fn_0802636a
	bl	fn_08026b78
	movs	r2, #0
	mov	r1, r2
	bl	fn_0802636a
	movs	r2, #0
	movs	r1, #0x60
	mov	r0, r9
	bl	fn_08025e80
	bl	fn_08026b78
	movs	r2, #0
	movs	r1, #0x60
	bl	fn_08025e80
	orrs.w	r0, r6, r8
	beq.n	.L08026ca4
	add	r0, sp, #0x50
	bl	fn_0801c718		@ initialise record 1
	ldr	r0, .L08026db0
	str	r0, [sp, #0x58]
	ldr	r0, .L08026db4
	str	r0, [sp, #0x5c]
	str.w	r9, [sp, #0x50]
	rsb.w	r8, r8, #0		@ r8 = -dy
	strd	r6, r8, [sp, #0x7c]
	add	r0, sp, #0xc
	bl	fn_0801c718		@ initialise record 2
	ldr	r0, [r4, #0x10]
	strd	r6, r8, [sp, #0x38]
	str	r0, [sp, #0xc]
	cmp	r5, #0xf
	bhs.n	.L08026cca
	tbb	[pc, r5]
.L08026c90:
	.byte	(.L08026cb0 - .L08026c90)/2	@ code 0
	.byte	(.L08026cb8 - .L08026c90)/2	@ code 1
	.byte	(.L08026ccc - .L08026c90)/2	@ code 2
	.byte	(.L08026cd8 - .L08026c90)/2	@ code 3
	.byte	(.L08026ce4 - .L08026c90)/2	@ code 4
	.byte	(.L08026cf2 - .L08026c90)/2	@ code 5
	.byte	(.L08026d12 - .L08026c90)/2	@ code 6
	.byte	(.L08026d3a - .L08026c90)/2	@ code 7
	.byte	(.L08026d5c - .L08026c90)/2	@ code 8
	.byte	(.L08026d7e - .L08026c90)/2	@ code 9
	.byte	(.L08026d88 - .L08026c90)/2	@ code 10
	.byte	(.L08026d04 - .L08026c90)/2	@ code 11
	.byte	(.L08026d26 - .L08026c90)/2	@ code 12
	.byte	(.L08026d4c - .L08026c90)/2	@ code 13
	.byte	(.L08026d70 - .L08026c90)/2	@ code 14
	.byte	0x00			@ padding
.L08026ca0:
	movs	r1, #1
	b.n	.L08026c0c
.L08026ca4:
	mov	r0, r9
	bl	fn_0802939a
.L08026caa:
	add	sp, #0x98
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L08026cb0:
	ldr	r0, .L08026db8
	str	r0, [sp, #0x54]
	movs	r0, #0
	b.n	.L08026cc2
.L08026cb8:
	ldr	r0, .L08026db8
	str	r0, [sp, #0x54]
	mov	r0, r4
	bl	fn_0801dcfc
.L08026cc2:
	movs	r1, #0
.L08026cc4:
	str	r0, [sp, #0x70]
	strd	r0, r1, [sp, #0x74]
.L08026cca:
	b.n	.L08026d96
.L08026ccc:
	ldr	r0, .L08026db8
	str	r0, [sp, #0x54]
	mov	r0, r4
	bl	fn_0801dcfc
	b.n	.L08026cee
.L08026cd8:
	ldr	r0, .L08026dbc
	str	r0, [sp, #0x54]
	mov	r0, r4
	bl	fn_0801dd88
	b.n	.L08026cc2
.L08026ce4:
	ldr	r0, .L08026dbc
	str	r0, [sp, #0x54]
	mov	r0, r4
	bl	fn_0801dd88
.L08026cee:
	rsbs	r0, r0, #0
	b.n	.L08026cc2
.L08026cf2:
	ldr	r0, .L08026db8
	str	r0, [sp, #0x54]
	mov	r0, r4
	bl	fn_0801dcfc
	movs	r1, #0
	str	r0, [sp, #0x70]
	strd	r0, r1, [sp, #0x74]
.L08026d04:
	ldr	r0, .L08026db8
	str	r0, [sp, #0x10]
	movs	r5, #0
	mov	r0, r4
	bl	fn_0801dcfc
	b.n	.L08026d58
.L08026d12:
	ldr	r0, .L08026db8
	str	r0, [sp, #0x54]
	mov	r0, r4
	bl	fn_0801dcfc
	rsbs	r0, r0, #0
	movs	r1, #0
	str	r0, [sp, #0x70]
	strd	r0, r1, [sp, #0x74]
.L08026d26:
	ldr	r0, .L08026db8
	str	r0, [sp, #0x10]
	movs	r5, #0
	mov	r0, r4
	bl	fn_0801dcfc
.L08026d32:
	strd	r5, r0, [sp, #0x30]
	str	r5, [sp, #0x2c]
	b.n	.L08026d96
.L08026d3a:
	ldr	r0, .L08026dbc
	str	r0, [sp, #0x54]
	mov	r0, r4
	bl	fn_0801dd88
	movs	r1, #0
	str	r0, [sp, #0x70]
	strd	r0, r1, [sp, #0x74]
.L08026d4c:
	ldr	r0, .L08026dbc
	str	r0, [sp, #0x10]
	movs	r5, #0
	mov	r0, r4
	bl	fn_0801dd88
.L08026d58:
	rsbs	r0, r0, #0
	b.n	.L08026d32
.L08026d5c:
	ldr	r0, .L08026dbc
	str	r0, [sp, #0x54]
	mov	r0, r4
	bl	fn_0801dd88
	rsbs	r0, r0, #0
	movs	r1, #0
	str	r0, [sp, #0x70]
	strd	r0, r1, [sp, #0x74]
.L08026d70:
	ldr	r0, .L08026dbc
	str	r0, [sp, #0x10]
	movs	r5, #0
	mov	r0, r4
	bl	fn_0801dd88
	b.n	.L08026d32
.L08026d7e:
	ldr	r0, .L08026dc0
	str	r0, [sp, #0x54]
	movs	r0, #0
	movs	r1, #0xff
	b.n	.L08026cc4
.L08026d88:
	ldr	r0, .L08026dc0
	str	r0, [sp, #0x10]
	movs	r0, #0xff
	movs	r1, #0
	str	r0, [sp, #0x2c]
	strd	r0, r1, [sp, #0x30]
.L08026d96:
	movs	r2, #0
	movs	r1, #0x25
	mov	r0, r7
	bl	fn_080207f4
	add	r0, sp, #0x50
	bl	fn_0801c7c0
	add	r0, sp, #0xc
	bl	fn_0801c7c0
	b.n	.L08026caa
	.short	0x0000			@ padding
.L08026db0:
	.word	fn_08029376		@ function pointer 0x08029377
.L08026db4:
	.word	fn_08029320		@ function pointer 0x08029321
.L08026db8:
	.word	fn_080297bc		@ function pointer 0x080297bd
.L08026dbc:
	.word	fn_080297c2		@ function pointer 0x080297c3
.L08026dc0:
	.word	fn_08028ac8		@ function pointer 0x08028ac9

@ ----------------------------------------------------------------------------
@ fn_08026dc4 - 4-byte tail branch to fn_08026e6c.
@ Parameters: r0 = table record T (word T+0, halfword T+4, byte T+7), r1 = id,
@ r2 = pointer to an output word; returns 0 (not found), 1 (value stored to
@ [r2]) or 2 (found with bit 15 set, nothing stored). The same instructions
@ as fn_08026dc8 exist at fn_08026e6c, which this branch enters.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026dc4,"ax",%progbits
	.p2align 2
	.global fn_08026dc4
	.thumb_func
	.type fn_08026dc4, %function
fn_08026dc4:
	b.w	fn_08026e6c

@ ----------------------------------------------------------------------------
@ fn_08026dc8 - table lookup by 14-bit key.
@ r0 = record (word at +0 = data pointer, halfword at +4, byte at +7 = count),
@ r1 = key, r2 = pointer to the result word (kept in r4). Returns 0 (absent),
@ 1 (found, result stored) or 2 (found with bit 15 set, nothing stored).
@ Halfword at +4 equal to 0xffff: scans the 8-byte entries at [r0]; otherwise
@ count 1 uses the halfword at +4 and the word at [r0], count above 1 uses the
@ words at [r0] and the halfwords after count*4; count 0 returns 0.
@ An entry matches when its halfword with bits 14 and 15 cleared equals the
@ key; bit 15 set returns 2; bit 14 set stores fn_08026f20(key) into the
@ result; otherwise it stores the stored word (the word at entry+4 for the
@ 8-byte entries). Returns 1 after storing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026dc8,"ax",%progbits
	.p2align 2
	.global fn_08026dc8
	.thumb_func
	.type fn_08026dc8, %function
fn_08026dc8:
	push	{r4, r5, r6, lr}
	mov	r4, r2			@ r4 = result pointer
	ldrh	r2, [r0, #4]		@ r2 = halfword h
	ldrb	r3, [r0, #7]		@ r3 = count c
	sub.w	r5, r2, #0xff00
	subs	r5, #0xff		@ zero when h = 0xffff
	beq.n	.L08026de8
	cbz	r3, .L08026e3a
	cmp	r3, #1
	bls.n	.L08026e4a
	ldr	r6, [r0]
	movs	r2, #0
	add.w	r5, r6, r3, lsl #2	@ halfword ids follow the word array
	b.n	.L08026e44
.L08026de8:
	movs	r2, #0
	b.n	.L08026e14
.L08026dec:
	ldr	r5, [r0]
	add.w	r5, r5, r2, lsl #3
	ldrh	r6, [r5]
	bic	r6, r6, #0xc000
	cmp	r6, r1
	bne.n	.L08026e12
	ldrh	r0, [r5]
	lsls	r1, r0, #0x10		@ bit 15
	bmi.n	.L08026e56
	lsls	r0, r0, #0x11		@ bit 14
	bpl.n	.L08026e0a
	mov	r0, r6
	b.n	.L08026e34
.L08026e0a:
	ldr	r0, [r5, #4]
.L08026e0c:
	str	r0, [r4]
	movs	r0, #1
	pop	{r4, r5, r6, pc}
.L08026e12:
	.inst.n	0x1c52			@ adds r2, r2, #1
.L08026e14:
	cmp	r3, r2
	bhi.n	.L08026dec
	b.n	.L08026e66
	nop				@ padding
.L08026e1c:
	ldrh.w	r0, [r5, r2, lsl #1]
	bic	r0, r0, #0xc000
	cmp	r0, r1
	bne.n	.L08026e42
	ldrh.w	r1, [r5, r2, lsl #1]
	lsls	r3, r1, #0x10		@ bit 15
	bmi.n	.L08026e56
	lsls	r1, r1, #0x11		@ bit 14
	bpl.n	.L08026e3c
.L08026e34:
	bl	fn_08026f20
	b.n	.L08026e0c
.L08026e3a:
	b.n	.L08026e66
.L08026e3c:
	add.w	r0, r6, r2, lsl #2
	b.n	.L08026e62
.L08026e42:
	.inst.n	0x1c52			@ adds r2, r2, #1
.L08026e44:
	cmp	r3, r2
	bhi.n	.L08026e1c
	b.n	.L08026e66
.L08026e4a:
	bic	r3, r2, #0xc000
	cmp	r3, r1
	bne.n	.L08026e66
	lsls	r1, r2, #0x10		@ bit 15
	bpl.n	.L08026e5a
.L08026e56:
	movs	r0, #2
	pop	{r4, r5, r6, pc}
.L08026e5a:
	lsls	r1, r2, #0x11		@ bit 14
	bpl.n	.L08026e62
	mov	r0, r3
	b.n	.L08026e34
.L08026e62:
	ldr	r0, [r0]
	b.n	.L08026e0c
.L08026e66:
	movs	r0, #0
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08026e6c - table lookup by 14-bit key (same instructions as fn_08026dc8).
@ r0 = table record T (word T+0, halfword T+4, byte T+7), r1 = key, r2 =
@ pointer to an output word (kept in r4); returns r0 = 0 (not found), 1 (value
@ stored to [r2]) or 2 (found with bit 15 set, nothing stored).
@ c = byte T+7 (r3), h = halfword T+4 (r2).
@ h = 0xffff (sub 0xff00, sub 0xff, beq): c entries of 8 bytes at [T+0]; for i
@ below c with halfword [entry] & ~0xc000 = key: bit 15 set returns 2, bit 14
@ set stores fn_08026f20(key) to [r2] and returns 1, else stores the word
@ [entry+4] and returns 1; i reaching c returns 0.
@ h != 0xffff: c = 0 returns 0; c = 1 tests h & ~0xc000 = key (bit 15 returns
@ 2, bit 14 stores fn_08026f20(key), else stores the word [T+0]); c >= 2: word
@ array at [T+0], halfword ids at [T+0] + 4*c, for i below c with id halfword
@ & ~0xc000 = key: bit 15 returns 2, bit 14 stores fn_08026f20(key), else
@ stores the word [[T+0] + 4*i]. Not found in every form returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026e6c,"ax",%progbits
	.global fn_08026e6c
	.thumb_func
	.type fn_08026e6c, %function
fn_08026e6c:
	push	{r4, r5, r6, lr}
	mov	r4, r2			@ r4 = result pointer
	ldrh	r2, [r0, #4]		@ r2 = halfword h
	ldrb	r3, [r0, #7]		@ r3 = count c
	sub.w	r5, r2, #0xff00
	subs	r5, #0xff		@ zero when h = 0xffff
	beq.n	.L08026e8c
	cbz	r3, .L08026ede
	cmp	r3, #1
	bls.n	.L08026eee
	ldr	r6, [r0]
	movs	r2, #0
	add.w	r5, r6, r3, lsl #2	@ halfword ids follow the word array
	b.n	.L08026ee8
.L08026e8c:
	movs	r2, #0
	b.n	.L08026eb8
.L08026e90:
	ldr	r5, [r0]
	add.w	r5, r5, r2, lsl #3
	ldrh	r6, [r5]
	bic	r6, r6, #0xc000
	cmp	r6, r1
	bne.n	.L08026eb6
	ldrh	r0, [r5]
	lsls	r1, r0, #0x10		@ bit 15
	bmi.n	.L08026efa
	lsls	r0, r0, #0x11		@ bit 14
	bpl.n	.L08026eae
	mov	r0, r6
	b.n	.L08026ed8
.L08026eae:
	ldr	r0, [r5, #4]
.L08026eb0:
	str	r0, [r4]
	movs	r0, #1
	pop	{r4, r5, r6, pc}
.L08026eb6:
	.inst.n	0x1c52			@ adds r2, r2, #1
.L08026eb8:
	cmp	r3, r2
	bhi.n	.L08026e90
	b.n	.L08026f0a
	nop				@ padding
.L08026ec0:
	ldrh.w	r0, [r5, r2, lsl #1]
	bic	r0, r0, #0xc000
	cmp	r0, r1
	bne.n	.L08026ee6
	ldrh.w	r1, [r5, r2, lsl #1]
	lsls	r3, r1, #0x10		@ bit 15
	bmi.n	.L08026efa
	lsls	r1, r1, #0x11		@ bit 14
	bpl.n	.L08026ee0
.L08026ed8:
	bl	fn_08026f20
	b.n	.L08026eb0
.L08026ede:
	b.n	.L08026f0a
.L08026ee0:
	add.w	r0, r6, r2, lsl #2
	b.n	.L08026f06
.L08026ee6:
	.inst.n	0x1c52			@ adds r2, r2, #1
.L08026ee8:
	cmp	r3, r2
	bhi.n	.L08026ec0
	b.n	.L08026f0a
.L08026eee:
	bic	r3, r2, #0xc000
	cmp	r3, r1
	bne.n	.L08026f0a
	lsls	r1, r2, #0x10		@ bit 15
	bpl.n	.L08026efe
.L08026efa:
	movs	r0, #2
	pop	{r4, r5, r6, pc}
.L08026efe:
	lsls	r1, r2, #0x11		@ bit 14
	bpl.n	.L08026f06
	mov	r0, r3
	b.n	.L08026ed8
.L08026f06:
	ldr	r0, [r0]
	b.n	.L08026eb0
.L08026f0a:
	movs	r0, #0
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08026f0e - clears 8 bytes: r0 = buffer; no return value.
@ Sets r1 = 8 and tail-calls clear_bytes(r0, 8).
@ ----------------------------------------------------------------------------
	.section .text.fn_08026f0e,"ax",%progbits
	.global fn_08026f0e
	.thumb_func
	.type fn_08026f0e, %function
fn_08026f0e:
	movs	r1, #8
	b.w	clear_bytes

@ ----------------------------------------------------------------------------
@ fn_08026f14 - r0 = record; returns 1 when the byte at r0+7 is 0, else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026f14,"ax",%progbits
	.p2align 2
	.global fn_08026f14
	.thumb_func
	.type fn_08026f14, %function
fn_08026f14:
	ldrb	r0, [r0, #7]
	cbz	r0, .L08026f1c
	movs	r0, #0
	bx	lr
.L08026f1c:
	movs	r0, #1
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08026f20 - default value for a key.
@ r0 = key; returns a default value in r0 (a 16-bit value, except key 0x57
@ which returns the full word). The value is staged through a stack slot at
@ sp+0.
@   0x03 and 0x06 give 0x1fff
@   0x33 gives 0xf
@   0x6c gives 0x100
@   0x57 gives the pool word at 0x08026fe8 (d_0802ce5c)
@   0x25, 0x29, 0x31, 0x37, 0x45, 0x46, 0x4e, 0x53, 0x56 and 0x60 give 0xff
@   0x20 gives rgb_to_565_0801d882(0xff, 0xff, 0xff)
@   0x22, 0x30, 0x36, 0x44, 0x47, 0x4d, 0x52 and 0x55 give
@   rgb_to_565_0801d882(0, 0, 0)
@   every other key gives 0
@ ----------------------------------------------------------------------------
	.section .text.fn_08026f20,"ax",%progbits
	.p2align 2
	.global fn_08026f20
	.thumb_func
	.type fn_08026f20, %function
fn_08026f20:
	push	{r2, r3, r4, lr}
	movs	r2, #0
	movs	r1, #0xff
	cmp	r0, #0x45
	beq.n	.L08026fd2
	bgt.n	.L08026f6a
	cmp	r0, #0x30
	beq.n	.L08026fb6
	bgt.n	.L08026f50
	cmp	r0, #0x22
	beq.n	.L08026fb6
	bgt.n	.L08026f46
	cmp	r0, #3
	beq.n	.L08026fe0
	cmp	r0, #6
	beq.n	.L08026fe0
	cmp	r0, #0x20
	bne.n	.L08026fa2
	b.n	.L08026fae
.L08026f46:
	cmp	r0, #0x25
	beq.n	.L08026fd2
	cmp	r0, #0x29
	bne.n	.L08026fa2
	b.n	.L08026fd2
.L08026f50:
	cmp	r0, #0x36
	beq.n	.L08026fb6
	bgt.n	.L08026f60
	cmp	r0, #0x31
	beq.n	.L08026fd2
	cmp	r0, #0x33
	bne.n	.L08026fa2
	b.n	.L08026fd6
.L08026f60:
	cmp	r0, #0x37
	beq.n	.L08026fd2
	cmp	r0, #0x44
	bne.n	.L08026fa2
	b.n	.L08026fb6
.L08026f6a:
	cmp	r0, #0x53
	beq.n	.L08026fd2
	bgt.n	.L08026f8a
	cmp	r0, #0x4d
	beq.n	.L08026fb6
	bgt.n	.L08026f80
	cmp	r0, #0x46
	beq.n	.L08026fd2
	cmp	r0, #0x47
	bne.n	.L08026fa2
	b.n	.L08026fb6
.L08026f80:
	cmp	r0, #0x4e
	beq.n	.L08026fd2
	cmp	r0, #0x52
	bne.n	.L08026fa2
	b.n	.L08026fb6
.L08026f8a:
	cmp	r0, #0x57
	beq.n	.L08026fdc
	bgt.n	.L08026f9a
	cmp	r0, #0x55
	beq.n	.L08026fb6
	cmp	r0, #0x56
	bne.n	.L08026fa2
	b.n	.L08026fd2
.L08026f9a:
	cmp	r0, #0x60
	beq.n	.L08026fd2
	cmp	r0, #0x6c
	beq.n	.L08026fa8
.L08026fa2:
	str	r2, [sp]		@ default 0
.L08026fa4:
	ldr	r0, [sp]
	pop	{r2, r3, r4, pc}
.L08026fa8:
	mov.w	r0, #0x100
	b.n	.L08026fd8
.L08026fae:
	movs	r2, #0xff		@ colour (0xff, 0xff, 0xff)
	mov	r1, r2
	mov	r0, r2
	b.n	.L08026fbc
.L08026fb6:
	movs	r2, #0			@ colour (0, 0, 0)
	mov	r1, r2
	mov	r0, r2
.L08026fbc:
	bl	rgb_to_565_0801d882
	str	r0, [sp, #4]
	ldrh.w	r0, [sp, #4]		@ keep the low 16 bits
	str	r0, [sp, #4]
	ldrh.w	r0, [sp, #4]
	strh.w	r0, [sp]
	b.n	.L08026fa4
.L08026fd2:
	str	r1, [sp]		@ 0xff
	b.n	.L08026fa4
.L08026fd6:
	movs	r0, #0xf
.L08026fd8:
	str	r0, [sp]
	b.n	.L08026fa4
.L08026fdc:
	ldr	r0, .L08026fe8
	b.n	.L08026fd8
.L08026fe0:
	movw	r0, #0x1fff
	b.n	.L08026fd8
	.short	0x0000			@ padding
.L08026fe8:
	.word	d_0802ce5c		@ literal read by 0x08026fdc

@ ----------------------------------------------------------------------------
@ fn_08026fec - mask test of fn_08012b10.
@ r0 = key, r1 = mask; returns 1 when (fn_08012b10(key) & mask) is nonzero,
@ else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026fec,"ax",%progbits
	.p2align 2
	.global fn_08026fec
	.thumb_func
	.type fn_08026fec, %function
fn_08026fec:
	push	{r4, lr}
	mov	r4, r1			@ r4 = mask
	bl	fn_08012b10
	ands	r0, r4
	beq.n	.L08026ffa
	movs	r0, #1
.L08026ffa:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08026ffc - appends a byte to a growing buffer.
@ r0 = byte to append; returns the new count or 0.
@ Uses the word 0x200004e8 (buffer pointer), the halfword 0x200004fc (count)
@ and the word 0x20000500 (capacity). When the buffer pointer is 0 it resets
@ the capacity to 0 and the count to 0x6f.
@ Returns 0 when (count + 1) & 0xc000 is nonzero.
@ When the capacity is below count - 0x6e it grows the buffer with
@ fn_08022cb0(buffer, size) to (count - 0x4f) & 0xffffffe0 (infinite loop when
@ that size is 0, returns 0 when the allocation fails) and stores the new
@ pointer and capacity.
@ Then increments the count (kept as a halfword) and stores the byte at
@ buffer + count - 0x70.
@ ----------------------------------------------------------------------------
	.section .text.fn_08026ffc,"ax",%progbits
	.p2align 2
	.global fn_08026ffc
	.thumb_func
	.type fn_08026ffc, %function
fn_08026ffc:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r5, .L08027054		@ r5 = 0x200004e8
	mov	r6, r0			@ r6 = byte
	ldr	r4, .L08027058		@ r4 = 0x200004fc
	ldr	r0, [r5]
	cbnz	r0, .L08027012
	movs	r1, #0
	str	r1, [r4, #4]		@ capacity = 0
	movs	r1, #0x6f
	strh	r1, [r4]		@ count = 0x6f
.L08027012:
	ldrh	r1, [r4]
	adds	r2, r1, #1
	tst.w	r2, #0xc000
	beq.n	.L08027022
	movs	r0, #0
.L0802701e:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08027022:
	ldr	r2, [r4, #4]
	subs	r1, #0x6e
	cmp	r2, r1
	bhs.n	.L08027040
	adds	r1, #0x1f
	bics	r7, r1, #0x1f		@ r7 = new capacity
	beq.n	.L08027052
	mov	r1, r7
	bl	fn_08022cb0
	cmp	r0, #0
	beq.n	.L0802701e
	str	r0, [r5]
	str	r7, [r4, #4]
.L08027040:
	ldrh	r0, [r4]
	.inst.n	0x1c40			@ adds r0, r0, #1
	uxth	r0, r0
	strh	r0, [r4]
	ldr	r1, [r5]
	add	r1, r0
	strb.w	r6, [r1, #-0x70]
	b.n	.L0802701e
.L08027052:
	b.n	.L08027052		@ infinite loop
.L08027054:
	.word	0x200004e8
.L08027058:
	.word	0x200004fc

@ ----------------------------------------------------------------------------
@ fn_0802705c - removes a key from a record.
@ r0 = record (same layout as in fn_08026dc8), r1 = key; returns 1 when the
@ key was removed, else 0.
@ Returns 0 when the halfword at +4 is 0xffff or the count (byte at +7) is 0.
@ Count 1: clears the halfword at +4 and the count when its halfword with
@ bits 14 and 15 cleared equals the key.
@ Count 2: leaves the other entry in place (count 1).
@ Larger counts: allocates (count - 1) * 6 bytes (fn_08022b50), copies the
@ other words and halfwords, decrements the count.
@ Releases the old data with fn_08022c68.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802705c,"ax",%progbits
	.global fn_0802705c
	.thumb_func
	.type fn_0802705c, %function
fn_0802705c:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r7, r1			@ r7 = key
	ldrh	r1, [r0, #4]
	mov	r4, r0			@ r4 = record
	sub.w	r0, r1, #0xff00
	subs	r0, #0xff		@ zero when the halfword is 0xffff
	beq.n	.L08027116
	ldrb	r0, [r4, #7]		@ r0 = count
	cmp	r0, #0
	beq.n	.L0802710c
	cmp	r0, #1
	beq.n	.L08027082
	ldr	r6, [r4]		@ r6 = word array
	movs	r1, #0
	add.w	r5, r6, r0, lsl #2	@ r5 = halfword ids after the words
	b.n	.L08027112
.L08027082:
	bic	r0, r1, #0xc000
	cmp	r0, r7
	bne.n	.L08027116
	movs	r0, #0
	strh	r0, [r4, #4]
	strb	r0, [r4, #7]
	b.n	.L0802710a
	nop				@ padding
.L08027094:
	ldrh.w	r2, [r5, r1, lsl #1]
	bic	r2, r2, #0xc000
	cmp	r2, r7
	bne.n	.L08027110
	cmp	r0, #2
	beq.n	.L080270c8
	.inst.n	0x1e40			@ subs r0, r0, #1
	add.w	r0, r0, r0, lsl #1
	lsls	r0, r0, #1		@ (count - 1) * 6
	bl	fn_08022b50
	movs	r1, r0
	beq.n	.L08027116
	str	r1, [r4]
	ldrb	r0, [r4, #7]
	.inst.n	0x1e40			@ subs r0, r0, #1
	uxtb	r0, r0
	strb	r0, [r4, #7]
	add.w	r3, r1, r0, lsl #2	@ r3 = halfword ids of the new array
	movs	r0, #0
	mov	r2, r0
	b.n	.L080270fc
.L080270c8:
	movs	r0, #1
	strb	r0, [r4, #7]
	cbz	r1, .L080270d8
	ldrh	r0, [r5]
	strh	r0, [r4, #4]
	ldr	r0, [r6]
.L080270d4:
	str	r0, [r4]
	b.n	.L08027104
.L080270d8:
	ldrh	r0, [r5, #2]
	strh	r0, [r4, #4]
	ldr	r0, [r6, #4]
	b.n	.L080270d4
.L080270e0:
	ldrh.w	r12, [r5, r0, lsl #1]
	cmp	r12, r7
	beq.n	.L080270fa
	ldr.w	lr, [r6, r0, lsl #2]
	str.w	lr, [r1, r2, lsl #2]
	ldrh.w	r12, [r5, r0, lsl #1]
	strh.w	r12, [r3, r2, lsl #1]
	.inst.n	0x1c52			@ adds r2, r2, #1
.L080270fa:
	.inst.n	0x1c40			@ adds r0, r0, #1
.L080270fc:
	ldrb.w	r12, [r4, #7]
	cmp	r12, r0
	bhs.n	.L080270e0
.L08027104:
	mov	r0, r6
	bl	fn_08022c68
.L0802710a:
	movs	r0, #1
.L0802710c:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08027110:
	.inst.n	0x1c49			@ adds r1, r1, #1
.L08027112:
	cmp	r0, r1
	bhi.n	.L08027094
.L08027116:
	movs	r0, #0
	b.n	.L0802710c

@ ----------------------------------------------------------------------------
@ fn_0802711a - releases and clears an 8-byte record.
@ r0 = object pointer; no return value.
@ Returns at once when the halfword at object+4 is 0xffff. When the byte at
@ object+7 is greater than 1, calls fn_08022c68 with the word at object+0.
@ Then tail-calls clear_bytes(object, 8), which zero-fills 8 bytes.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802711a,"ax",%progbits
	.global fn_0802711a
	.thumb_func
	.type fn_0802711a, %function
fn_0802711a:
	push	{r4, lr}
	mov	r4, r0
	ldrh	r0, [r0, #4]
	sub.w	r1, r0, #0xff00
	subs	r1, #0xff		@ zero when the halfword is 0xffff
	beq.n	.L08027140
	ldrb	r0, [r4, #7]
	cmp	r0, #1
	bls.n	.L08027134
	ldr	r0, [r4]
	bl	fn_08022c68
.L08027134:
	mov	r0, r4
	pop.w	{r4, lr}
	movs	r1, #8
	b.w	clear_bytes
.L08027140:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08027142 - r0 = object, r1 = value; no return value.
@ Moves r1 to r2, sets r1 = 100 (0x64) and branches to fn_08027280
@ (key 100, 32-bit value).
@ ----------------------------------------------------------------------------
	.section .text.fn_08027142,"ax",%progbits
	.global fn_08027142
	.thumb_func
	.type fn_08027142, %function
fn_08027142:
	mov	r2, r1
	movs	r1, #0x64
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_0802714a - r0 = object, r1 = 16-bit value; no return value.
@ Stores the halfword from the stack frame (the argument saved by push),
@ passes it zero-extended in r2 with r1 = 0x52 and branches to fn_08027280
@ (key 0x52, 16-bit value).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802714a,"ax",%progbits
	.global fn_0802714a
	.thumb_func
	.type fn_0802714a, %function
fn_0802714a:
	push	{r0, r1}
	sub	sp, #8
	ldrh.w	r1, [sp, #0xc]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x52
	add	sp, #0x10
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027160 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x51 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027160,"ax",%progbits
	.p2align 2
	.global fn_08027160
	.thumb_func
	.type fn_08027160, %function
fn_08027160:
	mov	r2, r1
	movs	r1, #0x51
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027168 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x50 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027168,"ax",%progbits
	.p2align 2
	.global fn_08027168
	.thumb_func
	.type fn_08027168, %function
fn_08027168:
	mov	r2, r1
	movs	r1, #0x50
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027170 - r0 = object, r1 = 16-bit value; no return value.
@ Zero-extends the halfword and calls fn_08027280 with key 0x20.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027170,"ax",%progbits
	.global fn_08027170
	.thumb_func
	.type fn_08027170, %function
fn_08027170:
	push	{r0, r1}
	sub	sp, #8
	ldrh.w	r1, [sp, #0xc]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x20
	add	sp, #0x10
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027186 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x21 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027186,"ax",%progbits
	.global fn_08027186
	.thumb_func
	.type fn_08027186, %function
fn_08027186:
	mov	r2, r1
	movs	r1, #0x21
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_0802718e - r0 = object, r1 = 16-bit value; no return value.
@ Zero-extends the halfword and calls fn_08027280 with key 0x30.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802718e,"ax",%progbits
	.global fn_0802718e
	.thumb_func
	.type fn_0802718e, %function
fn_0802718e:
	push	{r0, r1}
	sub	sp, #8
	ldrh.w	r1, [sp, #0xc]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x30
	add	sp, #0x10
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080271a4 - r0 = object, r1 = value; no return value.
@ Moves r1 to r2, sets r1 = 0x34 and branches to fn_08027280 (key 0x34).
@ ----------------------------------------------------------------------------
	.section .text.fn_080271a4,"ax",%progbits
	.p2align 2
	.global fn_080271a4
	.thumb_func
	.type fn_080271a4, %function
fn_080271a4:
	mov	r2, r1
	movs	r1, #0x34
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080271ac - r0 = object, r1 = value.
@ r2 = r1, r1 = 0x33, r0 unchanged; tail-calls fn_08027280(r0, 0x33, r2).
@ Entered by the b.w at 0x0802a6a4 of fn_08029b34.
@ ----------------------------------------------------------------------------
	.section .text.fn_080271ac,"ax",%progbits
	.p2align 2
	.global fn_080271ac
	.thumb_func
	.type fn_080271ac, %function
fn_080271ac:
	mov	r2, r1
	movs	r1, #0x33
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080271b4 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x32 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080271b4,"ax",%progbits
	.p2align 2
	.global fn_080271b4
	.thumb_func
	.type fn_080271b4, %function
fn_080271b4:
	mov	r2, r1
	movs	r1, #0x32
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080271bc - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x17 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080271bc,"ax",%progbits
	.p2align 2
	.global fn_080271bc
	.thumb_func
	.type fn_080271bc, %function
fn_080271bc:
	mov	r2, r1
	movs	r1, #0x17
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080271c4 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x61 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080271c4,"ax",%progbits
	.p2align 2
	.global fn_080271c4
	.thumb_func
	.type fn_080271c4, %function
fn_080271c4:
	mov	r2, r1
	movs	r1, #0x61
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080271cc - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x62 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080271cc,"ax",%progbits
	.p2align 2
	.global fn_080271cc
	.thumb_func
	.type fn_080271cc, %function
fn_080271cc:
	mov	r2, r1
	movs	r1, #0x62
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080271d4 - r0 = object, r1 = value; no return value.
@ Entered only by the tail jump b.w at 0x080273d2 (from 0x080273c0).
@ r2 = r1; r1 = 4; tail-calls fn_08027280(r0 as received, 4, value).
@ ----------------------------------------------------------------------------
	.section .text.fn_080271d4,"ax",%progbits
	.p2align 2
	.global fn_080271d4
	.thumb_func
	.type fn_080271d4, %function
fn_080271d4:
	mov	r2, r1
	movs	r1, #4
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080271dc - r0 = object, r1 = 16-bit value; no return value.
@ Zero-extends the halfword and calls fn_08027280 with key 0x4d.
@ ----------------------------------------------------------------------------
	.section .text.fn_080271dc,"ax",%progbits
	.global fn_080271dc
	.thumb_func
	.type fn_080271dc, %function
fn_080271dc:
	push	{r0, r1}
	sub	sp, #8
	ldrh.w	r1, [sp, #0xc]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x4d
	add	sp, #0x10
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080271f2 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x49 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080271f2,"ax",%progbits
	.global fn_080271f2
	.thumb_func
	.type fn_080271f2, %function
fn_080271f2:
	mov	r2, r1
	movs	r1, #0x49
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080271fa - r0 = object, r1 = 16-bit value; no return value.
@ Zero-extends the halfword and calls fn_08027280 with key 0x36.
@ ----------------------------------------------------------------------------
	.section .text.fn_080271fa,"ax",%progbits
	.global fn_080271fa
	.thumb_func
	.type fn_080271fa, %function
fn_080271fa:
	push	{r0, r1}
	sub	sp, #8
	ldrh.w	r1, [sp, #0xc]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x36
	add	sp, #0x10
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027210 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x37 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027210,"ax",%progbits
	.p2align 2
	.global fn_08027210
	.thumb_func
	.type fn_08027210, %function
fn_08027210:
	mov	r2, r1
	movs	r1, #0x37
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027218 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x38 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027218,"ax",%progbits
	.p2align 2
	.global fn_08027218
	.thumb_func
	.type fn_08027218, %function
fn_08027218:
	mov	r2, r1
	movs	r1, #0x38
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027220 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x35 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027220,"ax",%progbits
	.p2align 2
	.global fn_08027220
	.thumb_func
	.type fn_08027220, %function
fn_08027220:
	mov	r2, r1
	movs	r1, #0x35
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027228 - r0 = object, r1 = value; no return value.
@ Saves r0 and r1 in r5 and r4, then calls fn_0802725e, fn_08027266 and
@ fn_08027276 with (object, value) (keys 0x12, 0x13, 0x10).
@ Restores r4-r6 and lr and falls through the nop.w at 0x0802724a into
@ fn_0802724e, which sets key 0x11 with the same object and value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027228,"ax",%progbits
	.global fn_08027228
	.thumb_func
	.type fn_08027228, %function
fn_08027228:
	push	{r4, r5, r6, lr}
	mov	r4, r1			@ r4 = value
	mov	r5, r0			@ r5 = object
	bl	fn_0802725e
	mov	r1, r4
	mov	r0, r5
	bl	fn_08027266
	mov	r1, r4
	mov	r0, r5
	bl	fn_08027276
	mov	r1, r4
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	nop.w

@ ----------------------------------------------------------------------------
@ fn_0802724e - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x11 and the value. Entered by the fall-through
@ of fn_08027228.
@ ----------------------------------------------------------------------------
	.global fn_0802724e
	.thumb_func
	.type fn_0802724e, %function
fn_0802724e:
	mov	r2, r1
	movs	r1, #0x11
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027256 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x15 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027256,"ax",%progbits
	.global fn_08027256
	.thumb_func
	.type fn_08027256, %function
fn_08027256:
	mov	r2, r1
	movs	r1, #0x15
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_0802725e - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x12 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802725e,"ax",%progbits
	.global fn_0802725e
	.thumb_func
	.type fn_0802725e, %function
fn_0802725e:
	mov	r2, r1
	movs	r1, #0x12
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027266 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x13 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027266,"ax",%progbits
	.global fn_08027266
	.thumb_func
	.type fn_08027266, %function
fn_08027266:
	mov	r2, r1
	movs	r1, #0x13
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_0802726e - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x14 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802726e,"ax",%progbits
	.global fn_0802726e
	.thumb_func
	.type fn_0802726e, %function
fn_0802726e:
	mov	r2, r1
	movs	r1, #0x14
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027276 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x10 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027276,"ax",%progbits
	.global fn_08027276
	.thumb_func
	.type fn_08027276, %function
fn_08027276:
	mov	r2, r1
	movs	r1, #0x10
	b.w	fn_08027280
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08027280 - tail call of fn_08027294 with a callback.
@ Parameters: r0 = object, r1 = key, r2 = value (passed on unchanged); r3 is
@ overwritten; no return value.
@ Loads r3 = the word at 0x08027288 (fn_0802728c plus the Thumb bit) and
@ branches to fn_08027294(r0, r1, r2, r3). The callback fn_0802728c stores the
@ key in the halfword slot and the value in the word slot.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027280,"ax",%progbits
	.p2align 2
	.global fn_08027280
	.thumb_func
	.type fn_08027280, %function
fn_08027280:
	ldr	r3, .L08027288
	b.w	fn_08027294
	.short	0x0000			@ padding
.L08027288:
	.word	fn_0802728c		@ function pointer 0x0802728d

@ ----------------------------------------------------------------------------
@ fn_0802728c - callback storing a key and a value.
@ r0 = 16-bit key, r1 = 32-bit value, r2 = pointer to a halfword, r3 =
@ pointer to a word; no return value.
@ Stores r0 as a halfword at *r2 and r1 as a word at *r3, then bx lr.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802728c,"ax",%progbits
	.p2align 2
	.global fn_0802728c
	.thumb_func
	.type fn_0802728c, %function
fn_0802728c:
	strh	r0, [r2]
	str	r1, [r3]
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08027294 - inserts or finds a key in a record and calls a callback.
@ Parameters: r0 = table record T (word T+0, halfword T+4, byte T+6, byte
@ T+7), r1 = id (kept in r9), r2 = value passed through (r7), r3 = function
@ pointer f (r5); no return value of its own.
@ m = id & ~0xc000 (r6), c = byte T+7, h = halfword T+4; r8 = 1.
@ h = 0xffff: returns at once.
@ c = 0: stores 1 in byte T+7 and calls f(id, value, T+4, T).
@ c = 1: when h & ~0xc000 = m restores the registers and tail-branches (bx ip)
@ to f(id, value, T+4, T); otherwise r0 = fn_08022b50(12) (returns when 0),
@ r1 = old word [T], word [T] = r0, byte T+7 = 2, halfword [r0+8] = h, word
@ [r0] = r1, then calls f(id, value, r0+10, r0+4).
@ c >= 2: P = word [T], halfword ids at P + 4*c; searches i from c - 1 down to
@ 0 for halfword [P + 4*c + 2*i] & ~0xc000 = m and on a match tail-branches to
@ f(id, value, address of that halfword, P + 4*i); when none matches r1 =
@ fn_08022cb0(P, 6 * (c + 1)) (returns when 0), word [T] = r1, moves the c + 1
@ halfwords at r1 + 4*c up by 4 bytes, byte T+7 = c + 1 and calls f(id,
@ value, r1 + 4*(c+1) + 2*(c+1) - 2, r1 + 4*c).
@ After each call to f (not after the tail branches) it calls
@ field_1ff_shr4_max7(m) and sets bit (result) of byte T+6 (lsl, orr) and
@ returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027294,"ax",%progbits
	.global fn_08027294
	.thumb_func
	.type fn_08027294, %function
fn_08027294:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r4, r0			@ r4 = record
	ldrh	r0, [r0, #4]
	mov	r9, r1			@ r9 = id
	sub.w	r1, r0, #0xff00
	mov	r5, r3			@ r5 = callback
	subs	r1, #0xff		@ zero when the halfword is 0xffff
	beq.n	.L0802737c
	ldrb	r1, [r4, #7]		@ r1 = count
	bic	r6, r9, #0xc000		@ r6 = id without bits 14 and 15
	mov	r7, r2			@ r7 = value
	mov.w	r8, #1
	cmp	r1, #1
	bls.n	.L08027328
	ldr	r2, [r4]
	mov	r0, r1
	add.w	r3, r2, r1, lsl #2	@ r3 = halfword ids after the words
	b.n	.L080272dc
	nop				@ padding
.L080272c4:
	ldrh.w	r12, [r3, r0, lsl #1]
	bic	r12, r12, #0xc000
	cmp	r12, r6
	bne.n	.L080272dc
	add.w	r1, r2, r0, lsl #2
	add.w	r2, r3, r0, lsl #1
	mov	r3, r1
	b.n	.L08027336
.L080272dc:
	.inst.n	0x1e40			@ subs r0, r0, #1
	bpl.n	.L080272c4
	.inst.n	0x1c49			@ adds r1, r1, #1
	add.w	r0, r1, r1, lsl #1
	lsls	r1, r0, #1		@ 6 * (count + 1)
	mov	r0, r2
	bl	fn_08022cb0
	movs	r1, r0
	beq.n	.L0802737c
	str	r1, [r4]
	ldrb	r0, [r4, #7]
	add.w	r2, r1, r0, lsl #2
	b.n	.L08027308
.L080272fc:
	add.w	r12, r2, r0, lsl #1
	ldrh.w	r3, [r2, r0, lsl #1]
	strh.w	r3, [r12, #4]		@ move the halfword up by 4 bytes
.L08027308:
	.inst.n	0x1e40			@ subs r0, r0, #1
	bpl.n	.L080272fc
	ldrb	r0, [r4, #7]
	.inst.n	0x1c40			@ adds r0, r0, #1
	uxtb	r0, r0
	add.w	r3, r1, r0, lsl #2
	add.w	r2, r3, r0, lsl #1
	subs	r1, r3, #4
	strb	r0, [r4, #7]
	mov	r3, r1
	mov	r1, r7
	mov	r0, r9
	.inst.n	0x1e92			@ subs r2, r2, #2
	b.n	.L0802736a
.L08027328:
	bne.n	.L08027380
	bic	r0, r0, #0xc000
	cmp	r0, r6
	bne.n	.L08027342
	mov	r3, r4
	adds	r2, r4, #4
.L08027336:
	mov	r1, r7
	mov	r0, r9
	mov	ip, r5
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	bx	ip			@ tail branch to the callback
.L08027342:
	movs	r0, #0xc
	bl	fn_08022b50
	cmp	r0, #0
	beq.n	.L0802737c
	ldr	r1, [r4]
	str	r0, [r4]
	ldrb	r2, [r4, #7]
	.inst.n	0x1c52			@ adds r2, r2, #1
	uxtb	r2, r2
	strb	r2, [r4, #7]
	add.w	r2, r0, r2, lsl #2
	ldrh	r3, [r4, #4]
	strh	r3, [r2], #2
	adds	r3, r0, #4
	str	r1, [r0]
.L08027366:
	mov	r1, r7
	mov	r0, r9
.L0802736a:
	blx	r5			@ call the callback
	mov	r0, r6
	bl	field_1ff_shr4_max7
	ldrb	r1, [r4, #6]
	lsl.w	r2, r8, r0
	orrs	r1, r2
	strb	r1, [r4, #6]
.L0802737c:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L08027380:
	strb.w	r8, [r4, #7]
	mov	r3, r4
	adds	r2, r4, #4
	b.n	.L08027366

@ ----------------------------------------------------------------------------
@ fn_0802738a - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x0b and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802738a,"ax",%progbits
	.global fn_0802738a
	.thumb_func
	.type fn_0802738a, %function
fn_0802738a:
	mov	r2, r1
	movs	r1, #0xb
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027392 - r0 = object, r1 = 16-bit value; no return value.
@ Zero-extends the halfword and calls fn_08027280 with key 0x44.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027392,"ax",%progbits
	.global fn_08027392
	.thumb_func
	.type fn_08027392, %function
fn_08027392:
	push	{r0, r1}
	sub	sp, #8
	ldrh.w	r1, [sp, #0xc]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x44
	add	sp, #0x10
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080273a8 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x42 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080273a8,"ax",%progbits
	.p2align 2
	.global fn_080273a8
	.thumb_func
	.type fn_080273a8, %function
fn_080273a8:
	mov	r2, r1
	movs	r1, #0x42
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080273b0 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x45 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080273b0,"ax",%progbits
	.p2align 2
	.global fn_080273b0
	.thumb_func
	.type fn_080273b0, %function
fn_080273b0:
	mov	r2, r1
	movs	r1, #0x45
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080273b8 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x40 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080273b8,"ax",%progbits
	.p2align 2
	.global fn_080273b8
	.thumb_func
	.type fn_080273b8, %function
fn_080273b8:
	mov	r2, r1
	movs	r1, #0x40
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080273c0 - r0 = object, r1 = value; no return value.
@ Saves r0 and r1, calls fn_08027414 (key 1) with (object, value), restores
@ them and branches to fn_080271d4 (key 4 with the same value).
@ ----------------------------------------------------------------------------
	.section .text.fn_080273c0,"ax",%progbits
	.global fn_080273c0
	.thumb_func
	.type fn_080273c0, %function
fn_080273c0:
	push	{r4, r5, r6, lr}
	mov	r4, r1			@ r4 = value
	mov	r5, r0			@ r5 = object
	bl	fn_08027414
	mov	r1, r4
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	b.w	fn_080271d4

@ ----------------------------------------------------------------------------
@ fn_080273d6 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x5b and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080273d6,"ax",%progbits
	.global fn_080273d6
	.thumb_func
	.type fn_080273d6, %function
fn_080273d6:
	mov	r2, r1
	movs	r1, #0x5b
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080273de - r0 = object, r1 = 16-bit value; no return value.
@ Zero-extends the halfword and calls fn_08027280 with key 0x55.
@ ----------------------------------------------------------------------------
	.section .text.fn_080273de,"ax",%progbits
	.global fn_080273de
	.thumb_func
	.type fn_080273de, %function
fn_080273de:
	push	{r0, r1}
	sub	sp, #8
	ldrh.w	r1, [sp, #0xc]
	strh.w	r1, [sp]
	ldr	r2, [sp]
	movs	r1, #0x55
	add	sp, #0x10
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080273f4 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x59 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080273f4,"ax",%progbits
	.p2align 2
	.global fn_080273f4
	.thumb_func
	.type fn_080273f4, %function
fn_080273f4:
	mov	r2, r1
	movs	r1, #0x59
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_080273fc - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x69 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080273fc,"ax",%progbits
	.p2align 2
	.global fn_080273fc
	.thumb_func
	.type fn_080273fc, %function
fn_080273fc:
	mov	r2, r1
	movs	r1, #0x69
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027404 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x68 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027404,"ax",%progbits
	.p2align 2
	.global fn_08027404
	.thumb_func
	.type fn_08027404, %function
fn_08027404:
	mov	r2, r1
	movs	r1, #0x68
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_0802740c - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 0x66 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802740c,"ax",%progbits
	.p2align 2
	.global fn_0802740c
	.thumb_func
	.type fn_0802740c, %function
fn_0802740c:
	mov	r2, r1
	movs	r1, #0x66
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_08027414 - r0 = object, r1 = value; no return value.
@ Calls fn_08027280 with key 1 and the value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027414,"ax",%progbits
	.p2align 2
	.global fn_08027414
	.thumb_func
	.type fn_08027414, %function
fn_08027414:
	mov	r2, r1
	movs	r1, #1
	b.w	fn_08027280

@ ----------------------------------------------------------------------------
@ fn_0802741c - fills a 20-byte record.
@ r0 = destination record, r1 = word stored at +0, r2 = word stored at +8
@ (replaced by the literal word fn_0801c780 plus the Thumb bit when 0), r3 =
@ word stored at +12, stack word 0 (at sp+0x20 after the push) = stored at
@ +16, stack word 1 = stored at +4; no return value.
@ Zero-fills 0x14 (20) bytes of the record with clear_bytes, then writes the
@ five words.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802741c,"ax",%progbits
	.p2align 2
	.global fn_0802741c
	.thumb_func
	.type fn_0802741c, %function
fn_0802741c:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r7, r1			@ r7 = word for +0
	ldrd	r8, r9, [sp, #0x20]	@ r8 = word for +16, r9 = word for +4
	mov	r6, r3			@ r6 = word for +12
	mov	r5, r2			@ r5 = word for +8
	mov	r4, r0			@ r4 = record
	movs	r1, #0x14
	bl	clear_bytes
	str	r7, [r4]
	cbnz	r5, .L08027438
	ldr	r5, .L08027448		@ default for +8
.L08027438:
	str.w	r9, [r4, #4]
	adds	r4, #8
	stm.w	r4, {r5, r6, r8}	@ words +8, +12, +16
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
	.short	0x0000			@ padding
.L08027448:
	.word	fn_0801c780		@ function pointer 0x0801c781

@ ----------------------------------------------------------------------------
@ fn_0802744c - initialises the grid arrays of an object.
@ r1 = object (r0 unused); no return value.
@ Sets the halfwords at +0x24 and +0x26 to 1.
@ Allocates 2 bytes with fn_08022b50 into +0x30 and (halfword +0x26) * 2
@ bytes into +0x2c, and stores 0x8f in the first halfword of each.
@ Resizes the pointer at +0x28 with fn_08022cb0 to (+0x24) * (+0x26) * 4 bytes
@ and stores 0 in its first word.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802744c,"ax",%progbits
	.p2align 2
	.global fn_0802744c
	.thumb_func
	.type fn_0802744c, %function
fn_0802744c:
	push	{r4, lr}
	movs	r0, #1
	strh	r0, [r1, #0x24]
	strh	r0, [r1, #0x26]
	mov	r4, r1			@ r4 = object
	movs	r0, #2
	bl	fn_08022b50
	str	r0, [r4, #0x30]
	ldrh	r0, [r4, #0x26]
	lsls	r0, r0, #1
	bl	fn_08022b50
	str	r0, [r4, #0x2c]
	ldr	r1, [r4, #0x30]
	movs	r0, #0x8f
	strh	r0, [r1]
	ldr	r1, [r4, #0x2c]
	strh	r0, [r1]
	ldrh	r0, [r4, #0x26]
	ldrh	r1, [r4, #0x24]
	muls	r0, r1, r0
	lsls	r1, r0, #2		@ (+0x24) * (+0x26) * 4
	ldr	r0, [r4, #0x28]
	bl	fn_08022cb0
	movs	r1, #0
	str	r0, [r4, #0x28]
	str	r1, [r0]
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08027488 - releases the grid arrays of an object.
@ r1 = object (r0 unused); no return value.
@ Loops over (+0x26) * (+0x24) words of the array at +0x28; for each nonzero
@ word calls fn_08022c68 and stores 0. Then calls fn_08022c68 when the
@ pointers at +0x28, +0x2c and +0x30 are nonzero (the last one as a tail
@ call).
@ ----------------------------------------------------------------------------
	.section .text.fn_08027488,"ax",%progbits
	.p2align 2
	.global fn_08027488
	.thumb_func
	.type fn_08027488, %function
fn_08027488:
	push	{r4, r5, r6, lr}
	movs	r5, #0			@ r5 = index
	mov	r4, r1			@ r4 = object
	mov	r6, r5
	b.n	.L080274a8
	nop				@ padding
.L08027494:
	ldr.w	r0, [r0, r5, lsl #2]
	cbz	r0, .L080274a4
	bl	fn_08022c68
	ldr	r0, [r4, #0x28]
	str.w	r6, [r0, r5, lsl #2]
.L080274a4:
	.inst.n	0x1c6d			@ adds r5, r5, #1
	uxth	r5, r5
.L080274a8:
	ldrh	r0, [r4, #0x24]
	ldrh	r1, [r4, #0x26]
	muls	r0, r1, r0
	cmp	r0, r5
	ldr	r0, [r4, #0x28]
	bgt.n	.L08027494
	cbz	r0, .L080274ba
	bl	fn_08022c68
.L080274ba:
	ldr	r0, [r4, #0x2c]
	cbz	r0, .L080274c2
	bl	fn_08022c68
.L080274c2:
	ldr	r0, [r4, #0x30]
	cmp	r0, #0
	beq.n	.L080274d0
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08022c68
.L080274d0:
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_080274d4 - message handler of a grid object.
@ Parameters: r1 = message pointer (r7); r2 and r3 are saved by the push
@ {r2..r8,lr} and restored by the pops; no return value except through the
@ tail jumps.
@ fn_08023d54(0x08050f68, message): a result other than 1 returns. r5 = code =
@ get_byte8_low7(message); r4 = object = get_first_word(message).
@ Dispatch on the code: 0x2a, 0x2c, 1, 2, 8, 0x0e, 0x0d, 0x15; any other code
@ returns; r6 = 0xffff from 0x08027504.
@ Code 0x15: r0 = message; pop; tail-calls fn_08017510 with the message (not
@ the object).
@ Code 0x2a: pop {r2..r8,lr}; r1 = 0; tail-calls fn_080290fc with r0 = object,
@ r1 = 0, r2 and r3 as received.
@ Code 0x0e: pop; tail-calls fn_08025400(object).
@ Code 0x2c: p = get_word_at_0x10(message); r0 = sxth sum of the halfwords
@ [word [obj+0x30] + 2*i] for i below halfword [obj+0x24] (unsigned loop); r1
@ = the same for word [obj+0x2c] over halfword [obj+0x26] entries; halfword
@ [p] = r0 - 1; halfword [p+2] = r1 - 1.
@ Codes 1 and 2: fn_0801b57a(obj, r1 = sp, r2 = sp+4); a result other than 1
@ returns; when halfword [obj+0x34] = h[sp+4] and halfword [obj+0x36] = h[sp]
@ returns; else halfword [obj+0x34] = h[sp+4], halfword [obj+0x36] = h[sp],
@ fn_08025400(obj).
@ Code 8: fn_08025400(obj); read_word_200004ac(); t = fn_08021dee(result);
@ when halfword [obj+0x34] and [obj+0x36] are both not 0xffff and t = 0:
@ fn_080207f4(obj, 0x1c, 0), a result other than 1 returns; then u =
@ fn_08021e06(read_word_200004ac()); u = 1 or 3 stores 0xffff to halfwords
@ [obj+0x34] and [obj+0x36].
@ Code 0x0d: key = word [get_word_at_0x10(message)]; i = halfword [obj+0x34],
@ j = halfword [obj+0x36]; i or j equal 0xffff: both set to 0 and
@ fn_08025400(obj) as a tail call; nA = halfword [obj+0x24], nB = halfword
@ [obj+0x26]: i = 0 when nA <= i (signed), j = 0 when nB <= j; key 0x14: i -
@ 1, 0x13: i + 1, 0x11: j - 1, 0x12: j + 1, other keys return; i >= nA: j <
@ nB - 1 gives i = 0 and j + 1, else i = nA - 1; i < 0: j = 0 gives i = 0,
@ else i = nA - 1 and j - 1; j >= nB gives nB - 1, j < 0 gives 0; i and j
@ equal to the stored values returns; else halfword [obj+0x34] = i,
@ [obj+0x36] = j, fn_08025400(obj), add sp,#8, pop {r4..r8,lr}, r0 = obj, r1 =
@ 0x1c, r2 = 0, tail-calls fn_080207f4.
@ ----------------------------------------------------------------------------
	.section .text.fn_080274d4,"ax",%progbits
	.p2align 2
	.global fn_080274d4
	.thumb_func
	.type fn_080274d4, %function
fn_080274d4:
	push.w	{r2, r3, r4, r5, r6, r7, r8, lr}
	mov	r7, r1			@ r7 = message
	ldr	r0, .L08027688
	bl	fn_08023d54
	cmp	r0, #1
	bne.n	.L0802756c
	mov	r0, r7
	bl	get_byte8_low7
	mov	r5, r0			@ r5 = code
	mov	r0, r7
	bl	get_first_word
	mov	r4, r0			@ r4 = object
	cmp	r5, #0x2a
	beq.n	.L08027522
	cmp	r5, #0x2c
	beq.n	.L0802752c
	cmp	r5, #1
	beq.n	.L08027570
	cmp	r5, #2
	beq.n	.L08027570
	movw	r6, #0xffff
	cmp	r5, #8
	beq.n	.L080275a0
	cmp	r5, #0xe
	beq.n	.L080275de
	cmp	r5, #0xd
	beq.n	.L080275e6
	cmp	r5, #0x15
	bne.n	.L0802756c
	mov	r0, r7
	pop.w	{r2, r3, r4, r5, r6, r7, r8, lr}
	b.w	fn_08017510
.L08027522:
	pop.w	{r2, r3, r4, r5, r6, r7, r8, lr}
	movs	r1, #0
	b.w	fn_080290fc
.L0802752c:
	mov	r0, r7
	bl	get_word_at_0x10
	mov	r3, r0			@ r3 = result record
	movs	r0, #0
	mov	r1, r0
	ldrh	r2, [r4, #0x24]
	b.n	.L08027548
.L0802753c:
	ldr	r5, [r4, #0x30]
	ldrh.w	r5, [r5, r1, lsl #1]
	.inst.n	0x1c49			@ adds r1, r1, #1
	add	r0, r5
	sxth	r0, r0
.L08027548:
	cmp	r2, r1
	bhi.n	.L0802753c
	movs	r1, #0
	mov	r2, r1
	ldrh	r5, [r4, #0x26]
	b.n	.L08027560
.L08027554:
	ldr	r6, [r4, #0x2c]
	ldrh.w	r6, [r6, r2, lsl #1]
	.inst.n	0x1c52			@ adds r2, r2, #1
	add	r1, r6
	sxth	r1, r1
.L08027560:
	cmp	r5, r2
	bhi.n	.L08027554
	.inst.n	0x1e40			@ subs r0, r0, #1
	strh	r0, [r3]
	.inst.n	0x1e49			@ subs r1, r1, #1
	strh	r1, [r3, #2]
.L0802756c:
	pop.w	{r2, r3, r4, r5, r6, r7, r8, pc}
.L08027570:
	add	r2, sp, #4
	mov	r1, sp
	bl	fn_0801b57a
	cmp	r0, #1
	bne.n	.L0802756c
	ldrh	r1, [r4, #0x34]
	ldrh.w	r0, [sp, #4]
	cmp	r1, r0
	bne.n	.L08027590
	ldrh	r1, [r4, #0x36]
	ldrh.w	r2, [sp]
	cmp	r1, r2
	beq.n	.L0802756c
.L08027590:
	strh	r0, [r4, #0x34]
	ldrh.w	r1, [sp]
	mov	r0, r4
	strh	r1, [r4, #0x36]
	bl	fn_08025400
.L0802759e:
	b.n	.L0802756c
.L080275a0:
	bl	fn_08025400
	bl	read_word_200004ac
	bl	fn_08021dee
	ldrh	r1, [r4, #0x34]
	cmp	r1, r6
	beq.n	.L080275c8
	ldrh	r1, [r4, #0x36]
	cmp	r1, r6
	beq.n	.L080275c8
	cbnz	r0, .L080275c8
	movs	r2, #0
	movs	r1, #0x1c
	mov	r0, r4
	bl	fn_080207f4
	cmp	r0, #1
	bne.n	.L0802756c
.L080275c8:
	bl	read_word_200004ac
	bl	fn_08021e06
	cmp	r0, #1
	beq.n	.L080275d8
	cmp	r0, #3
	bne.n	.L0802756c
.L080275d8:
	strh	r6, [r4, #0x34]
	strh	r6, [r4, #0x36]
	b.n	.L0802756c
.L080275de:
	pop.w	{r2, r3, r4, r5, r6, r7, r8, lr}
	b.w	fn_08025400
.L080275e6:
	mov	r0, r7
	bl	get_word_at_0x10
	ldrh	r1, [r4, #0x34]		@ r1 = i
	ldr	r5, [r0]		@ r5 = key
	ldrh	r0, [r4, #0x36]		@ r0 = j
	mov	r7, r1			@ r7 = stored i
	mov	ip, r0			@ r12 = stored j
	cmp	r1, r6
	beq.n	.L080275fe
	cmp	r0, r6
	bne.n	.L08027608
.L080275fe:
	movs	r0, #0
	strh	r0, [r4, #0x34]
	strh	r0, [r4, #0x36]
	mov	r0, r4
	b.n	.L080275de
.L08027608:
	ldrh	r3, [r4, #0x24]		@ r3 = nA
	cmp	r3, r1
	bgt.n	.L08027610
	movs	r1, #0
.L08027610:
	ldrh	r2, [r4, #0x26]		@ r2 = nB
	cmp	r2, r0
	bgt.n	.L08027618
	movs	r0, #0
.L08027618:
	cmp	r5, #0x14
	beq.n	.L0802763a
	cmp	r5, #0x13
	beq.n	.L0802763e
	cmp	r5, #0x11
	beq.n	.L08027642
	cmp	r5, #0x12
	bne.n	.L0802756c
	.inst.n	0x1c40			@ adds r0, r0, #1
.L0802762a:
	cmp	r3, r1
	bgt.n	.L0802764a
	subs	r1, r2, #1
	cmp	r1, r0
	ble.n	.L08027646
	movs	r1, #0
	.inst.n	0x1c40			@ adds r0, r0, #1
	b.n	.L08027658
.L0802763a:
	.inst.n	0x1e49			@ subs r1, r1, #1
	b.n	.L0802762a
.L0802763e:
	.inst.n	0x1c49			@ adds r1, r1, #1
	b.n	.L0802762a
.L08027642:
	.inst.n	0x1e40			@ subs r0, r0, #1
	b.n	.L0802762a
.L08027646:
	subs	r1, r3, #1
	b.n	.L08027658
.L0802764a:
	cmp	r1, #0
	bge.n	.L08027658
	cbz	r0, .L08027656
	subs	r1, r3, #1
	.inst.n	0x1e40			@ subs r0, r0, #1
	b.n	.L08027658
.L08027656:
	movs	r1, #0
.L08027658:
	cmp	r2, r0
	bgt.n	.L08027660
	subs	r0, r2, #1
	b.n	.L08027666
.L08027660:
	cmp	r0, #0
	bge.n	.L08027666
	movs	r0, #0
.L08027666:
	cmp	r7, r1
	bne.n	.L0802766e
	cmp	ip, r0
	beq.n	.L0802759e
.L0802766e:
	strh	r1, [r4, #0x34]
	strh	r0, [r4, #0x36]
	mov	r0, r4
	bl	fn_08025400
	add	sp, #8
	mov	r0, r4
	pop.w	{r4, r5, r6, r7, r8, lr}
	movs	r2, #0
	movs	r1, #0x1c
	b.w	fn_080207f4
.L08027688:
	.word	d_08050f68		@ literal read by 0x080274da

@ ----------------------------------------------------------------------------
@ fn_0802768c - r0 = argument passed on; no return value.
@ Calls fn_0802777c; returns when the result is 0. Otherwise calls
@ fn_08025ede(r0, 0, 0x000fffff) and tail-calls run_callback_chain(result, r0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802768c,"ax",%progbits
	.p2align 2
	.global fn_0802768c
	.thumb_func
	.type fn_0802768c, %function
fn_0802768c:
	push	{r4, r5, r6, lr}
	mov	r4, r0			@ r4 = argument
	bl	fn_0802777c
	movs	r5, r0
	beq.n	.L080276ae
	mov	r0, r4
	ldr	r2, .L080276b0
	movs	r1, #0
	bl	fn_08025ede
	mov	r1, r4
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	b.w	run_callback_chain
.L080276ae:
	pop	{r4, r5, r6, pc}
.L080276b0:
	.word	0x000fffff

@ ----------------------------------------------------------------------------
@ fn_080276b4 - no parameters; returns a pointer.
@ Returns 0x20014274 when fn_0802776c returns nonzero, otherwise 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080276b4,"ax",%progbits
	.p2align 2
	.global fn_080276b4
	.thumb_func
	.type fn_080276b4, %function
fn_080276b4:
	push	{lr}
	bl	fn_0802776c
	cmp	r0, #0
	beq.n	.L080276c0
	ldr	r0, .L080276c4
.L080276c0:
	pop	{pc}
	.short	0x0000			@ padding
.L080276c4:
	.word	0x20014274

@ ----------------------------------------------------------------------------
@ fn_080276c8 - creates or reinitialises the object at 0x20014274.
@ r0 = word stored at 0x20014280, r1 = halfword stored at 0x20014284, r2 =
@ halfword stored at 0x20014286, r3 = word stored at 0x20014294, stack words
@ (the first one at sp+0x30 after the push) = stored at 0x20014288,
@ 0x2001428c and 0x20014290; returns 0x20014274 in r0.
@ When fn_0802776c returns 0: sets byte 0x2000051c to 0 and allocates 0x150
@ (336) bytes with fn_08022b50 into the words 0x200004dc and 0x20000528.
@ Calls fn_0801dccc and fn_0801dcfc; when the result is below 0x141 sets byte
@ 0x2000051d to 3, otherwise calls them again and sets it to 2 when the
@ result is below 0x2d0, else 1.
@ Stores 0x0802a7a9 (fn_0802a7a8 plus the Thumb bit) in 0x20014274.
@ Calls fn_08029b34.
@ When r0 is 0 or fn_0801dd7c(r0) returns 0x20014274 calls fn_08025fdc(0).
@ Sets byte 0x2000051c to 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_080276c8,"ax",%progbits
	.p2align 2
	.global fn_080276c8
	.thumb_func
	.type fn_080276c8, %function
fn_080276c8:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r9, r3			@ r9 = word for 0x20014294
	mov	r7, r0			@ r7 = word for 0x20014280
	ldr	r6, [sp, #0x30]		@ r6 = stack word
	bl	fn_0802776c
	ldr	r5, .L0802775c		@ r5 = 0x2000051c
	cbnz	r0, .L080276ec
	movs	r0, #0
	strb	r0, [r5]
	mov.w	r0, #0x150
	bl	fn_08022b50
	ldr	r1, .L08027760
	str	r0, [r1]		@ word 0x200004dc
	str	r0, [r5, #0xc]		@ word 0x20000528
.L080276ec:
	bl	fn_0801dccc
	bl	fn_0801dcfc
	mov.w	r8, #1
	cmp.w	r0, #0x140
	bgt.n	.L08027702
	movs	r0, #3
	b.n	.L08027712
.L08027702:
	bl	fn_0801dccc
	bl	fn_0801dcfc
	cmp.w	r0, #0x2d0
	bge.n	.L08027716
	movs	r0, #2
.L08027712:
	strb	r0, [r5, #1]		@ byte 0x2000051d
	b.n	.L0802771a
.L08027716:
	strb.w	r8, [r5, #1]
.L0802771a:
	ldr	r4, .L08027764		@ r4 = 0x20014274
	sub.w	r0, r4, #0x28
	str	r7, [r4, #0xc]		@ 0x20014280
	ldrh.w	r1, [sp, #4]
	strh	r1, [r0, #0x38]		@ 0x20014284
	ldrh.w	r1, [sp, #8]
	strh	r1, [r0, #0x3a]		@ 0x20014286
	str	r6, [r4, #0x14]		@ 0x20014288
	ldr	r0, .L08027768
	str	r6, [r4, #0x18]		@ 0x2001428c
	str	r0, [r4]
	strd	r6, r9, [r4, #0x1c]	@ 0x20014290 and 0x20014294
	bl	fn_08029b34
	cbz	r7, .L0802774a
	mov	r0, r7
	bl	fn_0801dd7c
	cmp	r0, r4
	bne.n	.L08027750
.L0802774a:
	movs	r0, #0
	bl	fn_08025fdc
.L08027750:
	strb.w	r8, [r5]
	add	sp, #0x10
	ldr	r0, .L08027764
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L0802775c:
	.word	0x2000051c
.L08027760:
	.word	0x200004dc
.L08027764:
	.word	0x20014274
.L08027768:
	.word	fn_0802a7a8		@ function pointer 0x0802a7a9

@ ----------------------------------------------------------------------------
@ fn_0802776c - no parameters; returns 0 or 1.
@ Returns 1 when the word at 0x200004dc (literal at 0x08027778) is nonzero,
@ otherwise 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802776c,"ax",%progbits
	.p2align 2
	.global fn_0802776c
	.thumb_func
	.type fn_0802776c, %function
fn_0802776c:
	ldr	r0, .L08027778
	ldr	r0, [r0]
	cmp	r0, #0
	beq.n	.L08027776
	movs	r0, #1
.L08027776:
	bx	lr
.L08027778:
	.word	0x200004dc

@ ----------------------------------------------------------------------------
@ fn_0802777c - r0 = selector; no return value.
@ Calls fn_08023ebc when r0 is nonzero, otherwise fn_0801dccc, then
@ tail-calls fn_0801dd7c.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802777c,"ax",%progbits
	.global fn_0802777c
	.thumb_func
	.type fn_0802777c, %function
fn_0802777c:
	push	{r4, lr}
	cbz	r0, .L08027786
	bl	fn_08023ebc
	b.n	.L0802778a
.L08027786:
	bl	fn_0801dccc
.L0802778a:
	pop.w	{r4, lr}
	b.w	fn_0801dd7c

@ ----------------------------------------------------------------------------
@ fn_0802891c - splits a value into an exponent and a mantissa.
@ Parameters: r0 = value, r1 = pointer to int result 1, r2 = pointer to uint
@ result 2.
@ Value below 0x80: stores 0 to *r1 and value / 4 (rounded toward zero) to
@ *r2.
@ Value 0x80 and above: n = highest_set_bit_index(value), stores n - 6 to *r1
@ and (value >> (n - 5)) ^ 0x20 to *r2.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802891c,"ax",%progbits
	.p2align 2
	.global fn_0802891c
	.thumb_func
	.type fn_0802891c, %function
fn_0802891c:
	push	{r4, r5, r6, lr}
	mov	r5, r2			@ r5 = pointer to result 2
	mov	r6, r1			@ r6 = pointer to result 1
	mov	r4, r0			@ r4 = value
	cmp	r0, #0x80
	bhs.n	.L08028934
	asrs	r1, r4, #0x1f
	movs	r0, #0
	add.w	r1, r4, r1, lsr #0x1e	@ round the division toward zero
	asrs	r1, r1, #2
	b.n	.L08028942
.L08028934:
	bl	highest_set_bit_index
	subs	r1, r0, #5
	lsrs	r4, r1
	eor	r1, r4, #0x20
	.inst.n	0x1f80			@ subs r0, r0, #6
.L08028942:
	str	r0, [r6]
	str	r1, [r5]
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ scale_value_by_factor_over_255 - scales a value by a factor over 255.
@ Parameters: r0 = value, r1 = factor; returns r0.
@ Factor 0xfd and above returns r0 unchanged; factor 0 to 2 returns 0;
@ otherwise p = signed 16-bit r0 * signed 16-bit r1 (smulbb) and the result is
@ (p * 0x8081 >> 23) & 0xff (p + p<<7, + p<<15 = p * 0x8081, ubfx #23,#8),
@ which is about r0 * r1 / 255.
@ ----------------------------------------------------------------------------
	.section .text.scale_value_by_factor_over_255,"ax",%progbits
	.p2align 2
	.global scale_value_by_factor_over_255
	.thumb_func
	.type scale_value_by_factor_over_255, %function
scale_value_by_factor_over_255:
	cmp	r1, #0xfd
	bhs.n	.L08028952
	cmp	r1, #2
	bhi.n	.L08028954
	movs	r0, #0
.L08028952:
	bx	lr
.L08028954:
	smulbb	r0, r0, r1
	add.w	r1, r0, r0, lsl #7
	add.w	r0, r1, r0, lsl #15
	ubfx	r0, r0, #0x17, #8
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08028968 - bounded pointer advance.
@ Parameters: r0 = pointer value; returns r0.
@ Returns 0 when the word at 0x2000056c is 0; r0 = 0 returns the word at
@ 0x200004e4; otherwise returns r0 + fn_0801b09c(r0), or 0 when that sum is
@ >= the word at 0x20000570.
@ ----------------------------------------------------------------------------
	.section .text.fn_08028968,"ax",%progbits
	.p2align 2
	.global fn_08028968
	.thumb_func
	.type fn_08028968, %function
fn_08028968:
	push	{r4, r5, r6, lr}
	ldr	r5, .L08028990		@ r5 = 0x20000568
	mov	r4, r0
	ldr	r0, [r5, #4]		@ word 0x2000056c
	cmp	r0, #0
	beq.n	.L08028986
	cbz	r4, .L08028988
	mov	r0, r4
	bl	fn_0801b09c
	ldr	r1, [r5, #8]		@ word 0x20000570
	add	r0, r4
	cmp	r0, r1
	blo.n	.L08028986
	movs	r0, #0
.L08028986:
	pop	{r4, r5, r6, pc}
.L08028988:
	ldr	r0, .L08028994
	ldr	r0, [r0]
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L08028990:
	.word	0x20000568
.L08028994:
	.word	0x200004e4

@ ----------------------------------------------------------------------------
@ store_word_plus4_if_offset_nonzero - conditional word store.
@ Parameters: r0 = pointer to a base address word, r1 = offset, r2 = value.
@ When r1 is not 0 stores r2 at address *r0 + r1 + 4.
@ ----------------------------------------------------------------------------
	.section .text.store_word_plus4_if_offset_nonzero,"ax",%progbits
	.p2align 2
	.global store_word_plus4_if_offset_nonzero
	.thumb_func
	.type store_word_plus4_if_offset_nonzero, %function
store_word_plus4_if_offset_nonzero:
	cmp	r1, #0
	beq.n	.L080289a2
	ldr	r0, [r0]
	.inst.n	0x1d09			@ adds r1, r1, #4
	str	r2, [r0, r1]
.L080289a2:
	bx	lr

@ ----------------------------------------------------------------------------
@ store_word_if_offset_nonzero - conditional word store.
@ Parameters: r0 = pointer to a base address word, r1 = offset, r2 = value.
@ When r1 is not 0 stores r2 at address *r0 + r1.
@ ----------------------------------------------------------------------------
	.section .text.store_word_if_offset_nonzero,"ax",%progbits
	.global store_word_if_offset_nonzero
	.thumb_func
	.type store_word_if_offset_nonzero, %function
store_word_if_offset_nonzero:
	cmp	r1, #0
	beq.n	.L080289ac
	ldr	r0, [r0]
	str	r2, [r0, r1]
.L080289ac:
	bx	lr

