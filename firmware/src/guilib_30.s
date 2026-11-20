@ guilib_30.s - memory pool release/allocate/free, pool setup, realloc-style resize, and the copy/fill/clear byte routines
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08022b80 - releases every used entry of the 16-entry pool at 0x200080dc.
@ No parameters, no return value.
@ The pool has 16 entries of 8 bytes at 0x200080dc: word pointer at +0, halfword
@ size at +4 (0x200080e0), byte in-use flag at +6 (0x200080e2).
@ For each entry whose pointer word is nonzero: calls fn_08022c68 with the
@ pointer in r0, then clears the pointer word, the size halfword (+4) and the
@ flag byte (+6). The loop index is kept as a byte (uxtb) and runs to 0x10.
@ ----------------------------------------------------------------------------
	.section .text.fn_08022b80,"ax",%progbits
	.p2align 2
	.global fn_08022b80
	.thumb_func
	.type fn_08022b80, %function
fn_08022b80:
	push	{r4, r5, r6, lr}
	movs	r4, #0x0		@ r4 = entry index
	ldr	r6, .L08022ba8		@ r6 = pool base 0x200080dc
	mov	r5, r4			@ r5 = 0, used to clear fields
.L08022b88:
	ldr.w	r0, [r6, r4, lsl #3]	@ pointer word of the entry
	cbz	r0, .L08022b9e		@ unused entry: skip
	bl	fn_08022c68
	add.w	r0, r6, r4, lsl #3
	str.w	r5, [r6, r4, lsl #3]	@ pointer = 0
	strb	r5, [r0, #0x6]		@ in-use flag = 0
	strh	r5, [r0, #0x4]		@ size = 0
.L08022b9e:
	.inst.n	0x1c64			@ adds r4, r4, #1
	uxtb	r4, r4
	cmp	r4, #0x10
	bcc.n	.L08022b88
	pop	{r4, r5, r6, pc}
.L08022ba8:
	.word	0x200080dc		@ pool base

@ ----------------------------------------------------------------------------
@ fn_08022bac - allocates a block from the pool of 16 entries at 0x200080dc.
@ Parameter r0 = size in bytes; returns r0 = block pointer (0 for size 0).
@ Pool entry (8 bytes): word pointer +0, halfword size +4 (0x200080e0), byte
@ in-use flag +6 (0x200080e2).
@ Searches the 16 entries: a free entry (flag bit 0 clear) with exactly the
@ requested size is taken at once (flag set to 1, its pointer returned);
@ otherwise the free entry with the smallest size that is still large enough
@ is remembered and taken (flag set to 1, pointer returned).
@ When none fits, the first free entry is taken: its block is resized with
@ fn_08022cb0(pointer, size), then the flag is set to 1, the size stored and the
@ new pointer stored in the entry and returned.
@ Enters an endless loop (at 0x08022c22 or 0x08022c3e) when all 16 entries are
@ in use or fn_08022cb0 returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08022bac,"ax",%progbits
	.p2align 2
	.global fn_08022bac
	.thumb_func
	.type fn_08022bac, %function
fn_08022bac:
	push.w	{r4, r5, r6, r7, r8, lr}
	movs	r5, r0			@ r5 = requested size
	beq.n	.L08022bcc		@ size 0: return 0
	movs	r2, #0x0		@ r2 = entry index
	ldr	r4, .L08022c40		@ r4 = pool base 0x200080dc
	mov.w	r0, #-1			@ r0 = best entry so far (-1 = none)
	movs	r6, #0x1		@ r6 = in-use value
	nop
.L08022bc0:
	add.w	r1, r4, r2, lsl #3
	ldrb	r3, [r1, #0x6]
	lsls	r3, r3, #0x1f		@ test the flag bit 0
	beq.n	.L08022bd2		@ free entry
	b.n	.L08022bf6		@ in use: next entry
.L08022bcc:
	movs	r0, #0x0
.L08022bce:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08022bd2:
	ldrh	r1, [r1, #0x4]		@ size of the free entry
	cmp	r1, r5
	bcc.n	.L08022bf6		@ too small: next entry
	bne.n	.L08022be6		@ larger than needed
	add.w	r0, r4, r2, lsl #3	@ exact size: take it
	strb	r6, [r0, #0x6]
	ldr.w	r0, [r4, r2, lsl #3]
	b.n	.L08022bce
.L08022be6:
	cmp	r0, #0x0
	blt.n	.L08022bf4		@ no candidate yet
	add.w	r3, r4, r0, lsl #3
	ldrh	r3, [r3, #0x4]		@ size of the current candidate
	cmp	r1, r3
	bcs.n	.L08022bf6		@ not smaller than the candidate
.L08022bf4:
	sxtb	r0, r2			@ this entry becomes the candidate
.L08022bf6:
	.inst.n	0x1c52			@ adds r2, r2, #1
	uxtb	r2, r2
	cmp	r2, #0x10
	bcc.n	.L08022bc0
	cmp	r0, #0x0
	blt.n	.L08022c0e		@ no candidate: grow the first free entry
	add.w	r1, r4, r0, lsl #3	@ take the candidate
	strb	r6, [r1, #0x6]
	ldr.w	r0, [r4, r0, lsl #3]
	b.n	.L08022bce
.L08022c0e:
	movs	r7, #0x0		@ r7 = index of the first free entry
.L08022c10:
	add.w	r0, r4, r7, lsl #3
	ldrb	r0, [r0, #0x6]
	lsls	r0, r0, #0x1f
	beq.n	.L08022c24
	.inst.n	0x1c7f			@ adds r7, r7, #1
	uxtb	r7, r7
	cmp	r7, #0x10
	bcc.n	.L08022c10
.L08022c22:
	b.n	.L08022c22		@ all entries in use: endless loop
.L08022c24:
	ldr.w	r0, [r4, r7, lsl #3]	@ old pointer of the entry
	mov	r1, r5			@ new size
	bl	fn_08022cb0
	cbz	r0, .L08022c3e
	add.w	r1, r4, r7, lsl #3
	strb	r6, [r1, #0x6]		@ flag = 1
	strh	r5, [r1, #0x4]		@ size
	str.w	r0, [r4, r7, lsl #3]	@ pointer
	b.n	.L08022bce
.L08022c3e:
	b.n	.L08022c3e		@ fn_08022cb0 returned 0: endless loop
.L08022c40:
	.word	0x200080dc		@ pool base

@ ----------------------------------------------------------------------------
@ fn_08022c44 - marks a pool block as free.
@ Parameter r0 = block pointer; no return value.
@ Searches the 16 entries at 0x200080dc for the pointer word and, on a match,
@ clears the in-use byte of that entry (0x200080e2 + entry*8); nothing happens
@ when no entry holds the pointer.
@ ----------------------------------------------------------------------------
	.section .text.fn_08022c44,"ax",%progbits
	.p2align 2
	.global fn_08022c44
	.thumb_func
	.type fn_08022c44, %function
fn_08022c44:
	ldr	r2, .L08022c64		@ r2 = pool base 0x200080dc
	movs	r1, #0x0		@ r1 = entry index
.L08022c48:
	ldr.w	r3, [r2, r1, lsl #3]
	cmp	r3, r0
	bne.n	.L08022c5a
	add.w	r1, r2, r1, lsl #3
	movs	r0, #0x0
	strb	r0, [r1, #0x6]		@ in-use flag = 0
	bx	lr
.L08022c5a:
	.inst.n	0x1c49			@ adds r1, r1, #1
	uxtb	r1, r1
	cmp	r1, #0x10
	bcc.n	.L08022c48
	bx	lr
.L08022c64:
	.word	0x200080dc		@ pool base

@ ----------------------------------------------------------------------------
@ fn_08022c68 - releases a block through fn_08027a3c and adjusts a counter.
@ Parameter r0 = pointer; no return value.
@ Does nothing for 0 or for the address 0x200004ec.
@ Otherwise calls fn_08027a3c(word at 0x200004f0, pointer) and subtracts the
@ returned size from the word at 0x200004f4; the word is set to 0 when the size
@ is not smaller than it.
@ ----------------------------------------------------------------------------
	.section .text.fn_08022c68,"ax",%progbits
	.p2align 2
	.global fn_08022c68
	.thumb_func
	.type fn_08022c68, %function
fn_08022c68:
	ldr	r1, .L08022c90		@ r1 = 0x200004ec
	push	{r4, lr}
	cmp	r0, r1
	beq.n	.L08022c8c
	cmp	r0, #0x0
	beq.n	.L08022c8c
	ldr	r4, .L08022c90
	mov	r1, r0			@ pointer
	ldr	r0, [r4, #0x4]		@ word at 0x200004f0
	bl	fn_08027a3c
	ldr	r1, [r4, #0x8]		@ word at 0x200004f4
	cmp	r1, r0
	bls.n	.L08022c88
	subs	r0, r1, r0
	b.n	.L08022c8a
.L08022c88:
	movs	r0, #0x0
.L08022c8a:
	str	r0, [r4, #0x8]
.L08022c8c:
	pop	{r4, pc}
	.short	0x0000			@ padding
.L08022c90:
	.word	0x200004ec

@ ----------------------------------------------------------------------------
@ fn_08022c94 - stores the result of fn_08027a20(0x2000824c, 0xc000) into the
@ word at 0x200004f0 (0x200004ec + 4).
@ No parameters, no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08022c94,"ax",%progbits
	.p2align 2
	.global fn_08022c94
	.thumb_func
	.type fn_08022c94, %function
fn_08022c94:
	push	{r4, lr}
	mov.w	r1, #0xc000		@ size
	ldr	r0, .L08022ca8		@ r0 = 0x2000824c
	bl	fn_08027a20
	ldr	r1, .L08022cac		@ r1 = 0x200004ec
	str	r0, [r1, #0x4]
	pop	{r4, pc}
	.short	0x0000			@ padding
.L08022ca8:
	.word	0x2000824c
.L08022cac:
	.word	0x200004ec

@ ----------------------------------------------------------------------------
@ fn_08022cb0 - resizes a block (realloc-style).
@ Parameters: r0 = pointer, r1 = new size; returns r0 = pointer.
@ r1 = 0: calls fn_08022c68(r0) and returns the address 0x200004ec.
@ r1 != 0 and r0 = 0x200004ec: tail-calls fn_08022b50(r1) (r0 = r1 first).
@ Otherwise sets r2 = r1, r1 = r0, r0 = word at 0x200004f0 (0x200004ec + 4) and
@ tail-calls fn_08027aba(r0, r1, r2) (pop r4, lr; b.w).
@ ----------------------------------------------------------------------------
	.section .text.fn_08022cb0,"ax",%progbits
	.p2align 2
	.global fn_08022cb0
	.thumb_func
	.type fn_08022cb0, %function
fn_08022cb0:
	push	{r4, lr}
	cbz	r1, .L08022cc4
	ldr	r2, .L08022cdc		@ r2 = 0x200004ec
	cmp	r0, r2
	bne.n	.L08022ccc
	pop.w	{r4, lr}
	mov	r0, r1
	b.w	fn_08022b50
.L08022cc4:
	bl	fn_08022c68
	ldr	r0, .L08022cdc
	pop	{r4, pc}
.L08022ccc:
	mov	r2, r1			@ new size
	mov	r1, r0			@ pointer
	ldr	r0, .L08022cdc
	ldr	r0, [r0, #0x4]		@ word at 0x200004f0
	pop.w	{r4, lr}
	b.w	fn_08027aba
.L08022cdc:
	.word	0x200004ec

@ ----------------------------------------------------------------------------
@ copy_bytes_08022ce0 - copies a byte block forward.
@ Parameters: r0 = destination, r1 = source, r2 = byte count; no return value.
@ Different low 2 address bits of destination and source: copies 0x20 bytes
@ per pass (byte loads and stores) while the count is above 0x20, then the rest
@ bytewise.
@ Equal alignment: copies single bytes until the destination is word aligned,
@ then 8 words (0x20 bytes) per pass while the count is above 0x20, then single
@ words while the count is above 4, then bytes.
@ Copies forward only.
@ ----------------------------------------------------------------------------
	.section .text.copy_bytes_08022ce0,"ax",%progbits
	.p2align 2
	.global copy_bytes_08022ce0
	.thumb_func
	.type copy_bytes_08022ce0, %function
copy_bytes_08022ce0:
	push	{r4, r5, lr}
	and	r4, r0, #0x3		@ destination alignment
	and	r5, r1, #0x3		@ source alignment
	mov	r3, r0			@ r3 = destination pointer
	cmp	r5, r4
	bne.n	.L08022d78		@ alignments differ: bytewise path
	b.n	.L08022d90
.L08022cf2:
	ldrb	r4, [r1, #0x0]
	strb	r4, [r3, #0x0]
	ldrb	r4, [r1, #0x1]
	strb	r4, [r3, #0x1]
	ldrb	r4, [r1, #0x2]
	strb	r4, [r3, #0x2]
	ldrb	r4, [r1, #0x3]
	strb	r4, [r3, #0x3]
	ldrb	r4, [r1, #0x4]
	strb	r4, [r3, #0x4]
	ldrb	r4, [r1, #0x5]
	strb	r4, [r3, #0x5]
	ldrb	r4, [r1, #0x6]
	strb	r4, [r3, #0x6]
	ldrb	r4, [r1, #0x7]
	strb	r4, [r3, #0x7]
	ldrb	r4, [r1, #0x8]
	strb	r4, [r3, #0x8]
	ldrb	r4, [r1, #0x9]
	strb	r4, [r3, #0x9]
	ldrb	r4, [r1, #0xa]
	strb	r4, [r3, #0xa]
	ldrb	r4, [r1, #0xb]
	strb	r4, [r3, #0xb]
	ldrb	r4, [r1, #0xc]
	strb	r4, [r3, #0xc]
	ldrb	r4, [r1, #0xd]
	strb	r4, [r3, #0xd]
	ldrb	r4, [r1, #0xe]
	strb	r4, [r3, #0xe]
	ldrb	r4, [r1, #0xf]
	strb	r4, [r3, #0xf]
	ldrb	r4, [r1, #0x10]
	strb	r4, [r3, #0x10]
	ldrb	r4, [r1, #0x11]
	strb	r4, [r3, #0x11]
	ldrb	r4, [r1, #0x12]
	strb	r4, [r3, #0x12]
	ldrb	r4, [r1, #0x13]
	strb	r4, [r3, #0x13]
	ldrb	r4, [r1, #0x14]
	strb	r4, [r3, #0x14]
	ldrb	r4, [r1, #0x15]
	strb	r4, [r3, #0x15]
	ldrb	r4, [r1, #0x16]
	strb	r4, [r3, #0x16]
	ldrb	r4, [r1, #0x17]
	strb	r4, [r3, #0x17]
	ldrb	r4, [r1, #0x18]
	strb	r4, [r3, #0x18]
	ldrb	r4, [r1, #0x19]
	strb	r4, [r3, #0x19]
	ldrb	r4, [r1, #0x1a]
	strb	r4, [r3, #0x1a]
	ldrb	r4, [r1, #0x1b]
	strb	r4, [r3, #0x1b]
	ldrb	r4, [r1, #0x1c]
	strb	r4, [r3, #0x1c]
	ldrb	r4, [r1, #0x1d]
	strb	r4, [r3, #0x1d]
	ldrb	r4, [r1, #0x1e]
	strb	r4, [r3, #0x1e]
	ldrb	r4, [r1, #0x1f]
	strb	r4, [r3, #0x1f]
	adds	r1, #0x20
	subs	r2, #0x20
	adds	r3, #0x20
.L08022d78:
	cmp	r2, #0x20
	bhi.n	.L08022cf2
	b.n	.L08022d8a
	nop				@ padding
.L08022d80:
	ldrb.w	r4, [r1], #0x1
	strb.w	r4, [r3], #0x1
	.inst.n	0x1e52			@ subs r2, r2, #1
.L08022d8a:
	cmp	r2, #0x0
	bne.n	.L08022d80
	pop	{r4, r5, pc}
.L08022d90:
	cbz	r4, .L08022de6		@ destination already word aligned
	rsb.w	r4, r4, #0x4		@ bytes to copy to reach alignment
	b.n	.L08022da4
.L08022d98:
	ldrb.w	r5, [r1], #0x1
	.inst.n	0x1e52			@ subs r2, r2, #1
	strb.w	r5, [r3], #0x1
	.inst.n	0x1e64			@ subs r4, r4, #1
.L08022da4:
	cbz	r4, .L08022de6
	cmp	r2, #0x0
	bne.n	.L08022d98
	b.n	.L08022de6
.L08022dac:
	ldmia	r1!, {r4}
	subs	r2, #0x20
	stmia	r3!, {r4}
	ldmia	r1!, {r4}
	stmia	r3!, {r4}
	ldr.w	r4, [r1], #0x8
	str.w	r4, [r3], #0x8
	ldr.w	r4, [r1, #-0x4]
	str.w	r4, [r3, #-0x4]
	ldr.w	r4, [r1], #0x10
	str.w	r4, [r3], #0x10
	ldr.w	r4, [r1, #-0xc]
	str.w	r4, [r3, #-0xc]
	ldr.w	r4, [r1, #-0x8]
	str.w	r4, [r3, #-0x8]
	ldr.w	r4, [r1, #-0x4]
	str.w	r4, [r3, #-0x4]
.L08022de6:
	cmp	r2, #0x20
	bhi.n	.L08022dac
	b.n	.L08022df2
.L08022dec:
	ldmia	r1!, {r4}
	.inst.n	0x1f12			@ subs r2, r2, #4
	stmia	r3!, {r4}
.L08022df2:
	cmp	r2, #0x4
	bhi.n	.L08022dec
	b.n	.L08022e02
.L08022df8:
	ldrb.w	r4, [r1], #0x1
	strb.w	r4, [r3], #0x1
	.inst.n	0x1e52			@ subs r2, r2, #1
.L08022e02:
	cmp	r2, #0x0
	bne.n	.L08022df8
	pop	{r4, r5, pc}

@ ----------------------------------------------------------------------------
@ fill_bytes_08022e08 - fills a byte block with a byte value.
@ Parameters: r0 = destination, r1 = fill byte, r2 = byte count; no return value.
@ Writes single bytes until the destination is word aligned (or the count runs
@ out), builds the word r1 * 0x1010101 in r3, then writes 8 words per pass
@ while the count is above 0x20, then single words while the count is above 4,
@ then bytes.
@ ----------------------------------------------------------------------------
	.section .text.fill_bytes_08022e08,"ax",%progbits
	.p2align 2
	.global fill_bytes_08022e08
	.thumb_func
	.type fill_bytes_08022e08, %function
fill_bytes_08022e08:
	ands	r3, r0, #0x3		@ destination alignment
	beq.n	.L08022e22
	rsb.w	r3, r3, #0x4		@ bytes to write to reach alignment
	b.n	.L08022e1c
.L08022e14:
	.inst.n	0x1e52			@ subs r2, r2, #1
	strb.w	r1, [r0], #0x1
	.inst.n	0x1e5b			@ subs r3, r3, #1
.L08022e1c:
	cbz	r3, .L08022e22
	cmp	r2, #0x0
	bne.n	.L08022e14
.L08022e22:
	add.w	r3, r1, r1, lsl #8	@ r3 = r1 * 0x1010101
	add.w	r3, r3, r1, lsl #16
	add.w	r3, r3, r1, lsl #24
	b.n	.L08022e4e
.L08022e30:
	stmia	r0!, {r3}
	subs	r2, #0x20
	stmia	r0!, {r3}
	str.w	r3, [r0], #0x8
	str.w	r3, [r0, #-0x4]
	str.w	r3, [r0], #0x10
	str.w	r3, [r0, #-0xc]
	str.w	r3, [r0, #-0x8]
	str.w	r3, [r0, #-0x4]
.L08022e4e:
	cmp	r2, #0x20
	bhi.n	.L08022e30
	b.n	.L08022e58
.L08022e54:
	stmia	r0!, {r3}
	.inst.n	0x1f12			@ subs r2, r2, #4
.L08022e58:
	cmp	r2, #0x4
	bhi.n	.L08022e54
	b.n	.L08022e66
	nop				@ padding
.L08022e60:
	strb.w	r1, [r0], #0x1
	.inst.n	0x1e52			@ subs r2, r2, #1
.L08022e66:
	cmp	r2, #0x0
	bne.n	.L08022e60
	bx	lr

@ ----------------------------------------------------------------------------
@ clear_bytes - writes zero to a byte block.
@ Parameters: r0 = destination, r1 = byte count; no return value.
@ r2 holds the zero value. Writes single bytes until the destination is word
@ aligned (returns when the count runs out first), then 8 zero words per pass
@ while the count is above 0x20, then zero words while the count is above 4,
@ then bytes.
@ ----------------------------------------------------------------------------
	.section .text.clear_bytes,"ax",%progbits
	.p2align 2
	.global clear_bytes
	.thumb_func
	.type clear_bytes, %function
clear_bytes:
	ands	r3, r0, #0x3		@ destination alignment
	mov.w	r2, #0x0		@ r2 = zero value
	beq.n	.L08022eaa
	rsb.w	r3, r3, #0x4		@ bytes to write to reach alignment
	b.n	.L08022e84
.L08022e7c:
	.inst.n	0x1e49			@ subs r1, r1, #1
	strb.w	r2, [r0], #0x1
	.inst.n	0x1e5b			@ subs r3, r3, #1
.L08022e84:
	cbz	r3, .L08022eaa
	cmp	r1, #0x0
	bne.n	.L08022e7c
	bx	lr			@ count ran out before alignment
.L08022e8c:
	stmia	r0!, {r2}
	subs	r1, #0x20
	stmia	r0!, {r2}
	str.w	r2, [r0], #0x8
	str.w	r2, [r0, #-0x4]
	str.w	r2, [r0], #0x10
	str.w	r2, [r0, #-0xc]
	str.w	r2, [r0, #-0x8]
	str.w	r2, [r0, #-0x4]
.L08022eaa:
	cmp	r1, #0x20
	bhi.n	.L08022e8c
	b.n	.L08022eb4
.L08022eb0:
	stmia	r0!, {r2}
	.inst.n	0x1f09			@ subs r1, r1, #4
.L08022eb4:
	cmp	r1, #0x4
	bhi.n	.L08022eb0
	b.n	.L08022ec2
	nop				@ padding
.L08022ebc:
	strb.w	r2, [r0], #0x1
	.inst.n	0x1e49			@ subs r1, r1, #1
.L08022ec2:
	cmp	r1, #0x0
	bne.n	.L08022ebc
	bx	lr

@ ----------------------------------------------------------------------------
@ fill_bytes_ff - writes 0xff to a byte block.
@ Parameters: r0 = destination, r1 = byte count; no return value.
@ r3 holds the byte value 0xff and r2 the word 0xffffffff. Writes single
@ bytes until the destination is word aligned (returns when the count runs out
@ first), then 8 words of 0xffffffff per pass while the count is above 0x20,
@ then words while the count is above 4, then bytes.
@ ----------------------------------------------------------------------------
	.section .text.fill_bytes_ff,"ax",%progbits
	.p2align 2
	.global fill_bytes_ff
	.thumb_func
	.type fill_bytes_ff, %function
fill_bytes_ff:
	ands	r2, r0, #0x3		@ destination alignment
	mov.w	r3, #0xff		@ r3 = fill byte
	beq.n	.L08022ee8
	rsb.w	r2, r2, #0x4		@ bytes to write to reach alignment
	b.n	.L08022ee0
.L08022ed8:
	.inst.n	0x1e49			@ subs r1, r1, #1
	strb.w	r3, [r0], #0x1
	.inst.n	0x1e52			@ subs r2, r2, #1
.L08022ee0:
	cbz	r2, .L08022ee8
	cmp	r1, #0x0
	bne.n	.L08022ed8
	bx	lr			@ count ran out before alignment
.L08022ee8:
	mov.w	r2, #-1			@ r2 = 0xffffffff
	b.n	.L08022f0c
.L08022eee:
	stmia	r0!, {r2}
	subs	r1, #0x20
	stmia	r0!, {r2}
	str.w	r2, [r0], #0x8
	str.w	r2, [r0, #-0x4]
	str.w	r2, [r0], #0x10
	str.w	r2, [r0, #-0xc]
	str.w	r2, [r0, #-0x8]
	str.w	r2, [r0, #-0x4]
.L08022f0c:
	cmp	r1, #0x20
	bhi.n	.L08022eee
	b.n	.L08022f16
.L08022f12:
	stmia	r0!, {r2}
	.inst.n	0x1f09			@ subs r1, r1, #4
.L08022f16:
	cmp	r1, #0x4
	bhi.n	.L08022f12
	b.n	.L08022f22
.L08022f1c:
	strb.w	r3, [r0], #0x1
	.inst.n	0x1e49			@ subs r1, r1, #1
.L08022f22:
	cmp	r1, #0x0
	bne.n	.L08022f1c
	bx	lr

@ ----------------------------------------------------------------------------
@ ticks_since - elapsed value since an earlier tick value.
@ Parameter r0 = earlier tick value; returns r0 = elapsed value.
@ Calls fn_080277a0 and returns its result minus the parameter.
@ ----------------------------------------------------------------------------
	.section .text.ticks_since,"ax",%progbits
	.global ticks_since
	.thumb_func
	.type ticks_since, %function
ticks_since:
	push	{r4, lr}
	mov	r4, r0			@ earlier tick value
	bl	fn_080277a0
	subs	r0, r0, r4
	pop	{r4, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_080277a0 - reads the tick word at 0x20000480.
@ No parameters; returns r0 = the word at 0x20000480.
@ Reads the word at 0x20000480 (0x2000047c + 4), then writes 1 to the byte at
@ 0x2000047c and reads that byte back, repeating the write until the byte read
@ back is nonzero (0x080277a6 to 0x080277ac), then returns the word read.
@ ----------------------------------------------------------------------------
	.section .text.fn_080277a0,"ax",%progbits
	.p2align 2
	.global fn_080277a0
	.thumb_func
	.type fn_080277a0, %function
fn_080277a0:
	ldr	r1, .L080277b0		@ r1 = 0x2000047c
	movs	r2, #0x1
	ldr	r0, [r1, #0x4]		@ word at 0x20000480
.L080277a6:
	strb	r2, [r1, #0x0]
	ldrb	r3, [r1, #0x0]
	cmp	r3, #0x0
	beq.n	.L080277a6
	bx	lr
.L080277b0:
	.word	0x2000047c

@ ----------------------------------------------------------------------------
@ add_to_word_20000480_clear_byte_2000047c - adds r0 to the word at 0x20000480.
@ Parameter r0 = amount to add; on return r0 holds the new value of the word
@ at 0x20000480. Entered by the tail jump b.w at 0x0802a796 (from 0x0802a720).
@ r1 = 0x2000047c; clears the byte at [r1]; r2 = word [r1 + 4] (0x20000480);
@ r0 = r0 + r2; stores r0 to [r1 + 4]; returns with bx lr.
@ ----------------------------------------------------------------------------
	.section .text.add_to_word_20000480_clear_byte_2000047c,"ax",%progbits
	.p2align 2
	.global add_to_word_20000480_clear_byte_2000047c
	.thumb_func
	.type add_to_word_20000480_clear_byte_2000047c, %function
add_to_word_20000480_clear_byte_2000047c:
	ldr	r1, .L080277c4		@ r1 = 0x2000047c
	movs	r2, #0x0
	strb	r2, [r1, #0x0]		@ clear the byte at 0x2000047c
	ldr	r2, [r1, #0x4]		@ word at 0x20000480
	add	r0, r2
	str	r0, [r1, #0x4]
	bx	lr
	.short	0x0000			@ padding
.L080277c4:
	.word	0x2000047c

@ ----------------------------------------------------------------------------
@ fn_080277c8 - allocates and initialises a record.
@ Parameters: r0 = word stored at +8, r1 = word stored at +0, r2 = word stored
@ at +12; returns r0 = pointer to the new record, or 0.
@ Allocates a record from the pool at 0x20008050 with fn_08012618; returns 0
@ when none is free. Otherwise stores the parameters, +16 = 0xffffffff,
@ +20 = 0, +4 = the result of fn_080277a0, and sets the byte at 0x20000488
@ (0x20000484 + 4) to 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_080277c8,"ax",%progbits
	.p2align 2
	.global fn_080277c8
	.thumb_func
	.type fn_080277c8, %function
fn_080277c8:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r7, r0			@ value for +8
	mov	r5, r2			@ value for +12
	mov	r6, r1			@ value for +0
	ldr	r0, .L08027804		@ r0 = pool 0x20008050
	bl	fn_08012618
	movs	r4, r0			@ r4 = new record (0 = none free)
	beq.n	.L080277fe
	str	r7, [r4, #0x8]
	mov.w	r0, #-1
	str	r6, [r4, #0x0]
	str	r0, [r4, #0x10]		@ +16 = 0xffffffff
	movs	r0, #0x0
	str	r0, [r4, #0x14]		@ +20 = 0
	bl	fn_080277a0
	str	r5, [r4, #0xc]
	ldr	r1, .L08027808		@ r1 = 0x20000484
	str	r0, [r4, #0x4]		@ +4 = tick word
	movs	r0, #0x1
	strb	r0, [r1, #0x4]		@ byte 0x20000488 = 1
	mov	r0, r4
.L080277fa:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L080277fe:
	movs	r0, #0x0
	b.n	.L080277fa
	.short	0x0000			@ padding
.L08027804:
	.word	0x20008050
.L08027808:
	.word	0x20000484

@ ----------------------------------------------------------------------------
@ fn_0802780c - removes a record.
@ Parameter r0 = record pointer; no return value.
@ Calls fn_080126a2(0x20008050, record), sets the byte at 0x20000487
@ (0x20000484 + 3) to 1 and tail-calls fn_08022c68(record).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802780c,"ax",%progbits
	.p2align 2
	.global fn_0802780c
	.thumb_func
	.type fn_0802780c, %function
fn_0802780c:
	push	{r4, lr}
	mov	r4, r0
	mov	r1, r0			@ record
	ldr	r0, .L08027828		@ r0 = pool 0x20008050
	bl	fn_080126a2
	ldr	r1, .L0802782c		@ r1 = 0x20000484
	movs	r0, #0x1
	strb	r0, [r1, #0x3]		@ byte 0x20000487 = 1
	mov	r0, r4
	pop.w	{r4, lr}
	b.w	fn_08022c68
.L08027828:
	.word	0x20008050
.L0802782c:
	.word	0x20000484

@ ----------------------------------------------------------------------------
@ fn_08027830 - runs the timer record list once.
@ No parameters; returns r0 = the smallest remaining delay found (0xffffffff
@ when none), or 1 when the routine is already running or byte 0x20000484 is 0.
@ Variable block at 0x20000484: byte +0 (0x20000484) enable, +1 (0x20000485)
@ load value, +2 (0x20000486) running flag, +3 (0x20000487) and +4 (0x20000488)
@ change flags, word +8 (0x2000048c) start tick, +12 (0x20000490) busy ticks,
@ +16 (0x20000494) counter; word 0x200004d8 holds the current record.
@ When byte 0x20000486 is 0: sets it to 1; when byte 0x20000484 is zero clears
@ 0x20000486 and returns 1. Otherwise reads the tick with fn_080277a0 (r9); when
@ it is 0 increments the word at 0x20000494 and clears it when above 100.
@ Walks the list at 0x20008050 (first record get_word_4_or_zero, next
@ read_word_at_base_plus_offset_4), clearing the bytes 0x20000487 and
@ 0x20000488 at each start. For each record whose flag word bit 0 (at +0x14) is
@ clear: ticks_remaining(record); at 0 it decrements the counter at +16 when
@ above 0, stores the current tick (fn_080277a0) at +4 and calls the function
@ pointer at +8 with the record when the old counter was nonzero. A record whose
@ counter is 0 (with 0x20000487 clear) is removed with fn_0802780c. The walk
@ restarts when 0x20000487 or 0x20000488 was set during a callback.
@ After the walk it computes the minimum ticks_remaining over the unflagged
@ records, adds ticks_since(r9) to the word at 0x20000490 and, when
@ ticks_since(word 0x2000048c) is 500 or more, stores byte 0x20000485 = 100
@ minus (0x20000490 * 100 / elapsed) (0 when that is above 100), clears
@ 0x20000490 and stores a new tick in 0x2000048c. Clears byte 0x20000486
@ before returning.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027830,"ax",%progbits
	.p2align 2
	.global fn_08027830
	.thumb_func
	.type fn_08027830, %function
fn_08027830:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr	r4, .L0802795c		@ r4 = 0x20000484
	ldrb	r0, [r4, #0x2]		@ running flag
	cbz	r0, .L08027840
.L0802783a:
	movs	r0, #0x1
.L0802783c:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L08027840:
	movs	r0, #0x1
	strb	r0, [r4, #0x2]		@ running flag = 1
	ldrb	r0, [r4, #0x0]		@ enable byte
	movs	r6, #0x0
	cbz	r0, .L08027856
	bl	fn_080277a0
	movs.w	r9, r0			@ r9 = start tick
	beq.n	.L0802785a
	b.n	.L08027866
.L08027856:
	strb	r6, [r4, #0x2]		@ running flag = 0
	b.n	.L0802783a
.L0802785a:
	ldr	r0, [r4, #0x10]
	.inst.n	0x1c40			@ adds r0, r0, #1
	str	r0, [r4, #0x10]
	cmp	r0, #0x64
	bls.n	.L08027866
	str	r6, [r4, #0x10]
.L08027866:
	ldr	r5, .L08027960		@ r5 = 0x200004d8 (current record word)
	mov.w	r8, r6			@ r8 = 0
.L0802786c:
	strb.w	r8, [r4, #0x3]		@ clear the change flags
	strb.w	r8, [r4, #0x4]
	ldr	r0, .L08027964		@ r0 = list 0x20008050
	bl	get_word_4_or_zero
	str	r0, [r5, #0x0]
	b.n	.L080278ee
.L0802787e:
	ldr	r0, .L08027964
	bl	read_word_at_base_plus_offset_4
	ldr	r6, [r5, #0x0]		@ r6 = current record
	mov	r7, r0			@ r7 = next record
	ldrb	r0, [r6, #0x14]
	lsls	r0, r0, #0x1f
	bne.n	.L080278ec		@ flag bit 0 set: next record
	mov	r10, r0			@ r10 = 0
	mov	r0, r6
	bl	ticks_remaining
	cbnz	r0, .L080278bc
	ldr	r0, [r6, #0x10]		@ counter
	subs.w	r10, r0, #0x0
	ble.n	.L080278a4
	.inst.n	0x1e40			@ subs r0, r0, #1
	str	r0, [r6, #0x10]
.L080278a4:
	bl	fn_080277a0
	str	r0, [r6, #0x4]
	ldr	r1, [r6, #0x8]		@ function pointer
	cbz	r1, .L080278b8
	cmp.w	r10, #0x0
	beq.n	.L080278b8
	mov	r0, r6
	blx	r1
.L080278b8:
	mov.w	r10, #0x1
.L080278bc:
	ldrb	r0, [r4, #0x3]
	cbnz	r0, .L080278ca
	ldr	r0, [r6, #0x10]
	cbnz	r0, .L080278ca
	mov	r0, r6
	bl	fn_0802780c
.L080278ca:
	cmp.w	r10, #0x0
	beq.n	.L080278ec
	ldrb	r0, [r4, #0x4]
	ldrb	r1, [r4, #0x3]
	orrs	r0, r1
	beq.n	.L080278ec
	ldr	r0, [r5, #0x0]
	cmp	r0, #0x0
	bne.n	.L0802786c		@ change flag set: restart the walk
	nop
.L080278e0:
	mov.w	r5, #-1			@ r5 = minimum so far (0xffffffff)
	ldr	r0, .L08027964
	bl	get_word_4_or_zero
	b.n	.L08027910
.L080278ec:
	str	r7, [r5, #0x0]		@ current record = next record
.L080278ee:
	ldr	r1, [r5, #0x0]
	cmp	r1, #0x0
	bne.n	.L0802787e
	b.n	.L080278e0
.L080278f6:
	ldrb	r0, [r6, #0x14]
	lsls	r0, r0, #0x1f
	bne.n	.L08027908
	mov	r0, r6
	bl	ticks_remaining
	cmp	r0, r5
	bcs.n	.L08027908
	mov	r5, r0			@ new minimum
.L08027908:
	mov	r1, r6
	ldr	r0, .L08027964
	bl	read_word_at_base_plus_offset_4
.L08027910:
	movs	r6, r0
	bne.n	.L080278f6
	mov	r0, r9
	bl	ticks_since
	ldr	r1, [r4, #0xc]
	add	r0, r1
	str	r0, [r4, #0xc]		@ word 0x20000490 += elapsed ticks
	ldr	r0, [r4, #0x8]		@ word 0x2000048c
	bl	ticks_since
	cmp.w	r0, #0x1f4
	bcc.n	.L08027954
	ldr	r1, [r4, #0xc]
	movs	r2, #0x64
	muls	r1, r2, r1
	udiv	r0, r1, r0
	uxtb	r0, r0
	strb	r0, [r4, #0x1]
	cmp	r0, #0x64
	bls.n	.L08027942
	movs	r0, #0x0
	b.n	.L08027946
.L08027942:
	rsb.w	r0, r0, #0x64
.L08027946:
	strb	r0, [r4, #0x1]		@ byte 0x20000485
	mov	r6, r4
	str.w	r8, [r4, #0xc]		@ word 0x20000490 = 0
	bl	fn_080277a0
	str	r0, [r6, #0x8]		@ word 0x2000048c = new tick
.L08027954:
	strb.w	r8, [r4, #0x2]		@ running flag = 0
	mov	r0, r5			@ return the minimum
	b.n	.L0802783c
.L0802795c:
	.word	0x20000484
.L08027960:
	.word	0x200004d8
.L08027964:
	.word	0x20008050

@ ----------------------------------------------------------------------------
@ record_set_flag - sets the flag word of a record.
@ Parameter r0 = record pointer; no return value.
@ Stores 1 in the word at +0x14 of the record.
@ ----------------------------------------------------------------------------
	.section .text.record_set_flag,"ax",%progbits
	.global record_set_flag
	.thumb_func
	.type record_set_flag, %function
record_set_flag:
	movs	r1, #0x1
	str	r1, [r0, #0x14]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0802796e - restarts a record's elapsed time.
@ Parameter r0 = record pointer; no return value.
@ Stores (result of fn_080277a0) - (word at r0 + 0) - 1 in the word at +4.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802796e,"ax",%progbits
	.global fn_0802796e
	.thumb_func
	.type fn_0802796e, %function
fn_0802796e:
	push	{r4, lr}
	mov	r4, r0
	bl	fn_080277a0
	ldr	r1, [r4, #0x0]
	subs	r0, r0, r1
	.inst.n	0x1e40			@ subs r0, r0, #1
	str	r0, [r4, #0x4]
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ record_clear_flag - clears the flag word of a record.
@ Parameter r0 = record pointer; no return value.
@ Stores 0 in the word at +0x14 of the record.
@ ----------------------------------------------------------------------------
	.section .text.record_clear_flag,"ax",%progbits
	.global record_clear_flag
	.thumb_func
	.type record_clear_flag, %function
record_clear_flag:
	movs	r1, #0x0
	str	r1, [r0, #0x14]
	bx	lr

@ ----------------------------------------------------------------------------
@ ticks_remaining - ticks left for a record.
@ Parameter r0 = record pointer; returns r0 = the remaining ticks.
@ Elapsed = ticks_since(word at +4). Returns (word at +0) - elapsed when elapsed
@ is below the word at +0, otherwise 0.
@ ----------------------------------------------------------------------------
	.section .text.ticks_remaining,"ax",%progbits
	.global ticks_remaining
	.thumb_func
	.type ticks_remaining, %function
ticks_remaining:
	push	{r4, lr}
	mov	r4, r0
	ldr	r0, [r0, #0x4]
	bl	ticks_since
	ldr	r1, [r4, #0x0]
	cmp	r1, r0
	bhi.n	.L0802799a
	movs	r0, #0x0
	pop	{r4, pc}
.L0802799a:
	subs	r0, r1, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0802799e - sets up a heap region inside a control block.
@ Parameters: r0 = control block pointer, passed on unchanged to fn_08013a6a;
@ r1 = region start (must be 4-aligned); r2 = region size. Returns r1 or 0.
@ The size is (r2 - 8) rounded down to a multiple of 4. Returns 0 when r1 is not
@ 4-aligned or when (size - 0xc) is not below 0xfff5 (unsigned).
@ Otherwise writes the size word at r1 as (low 2 bits of the old word | size)
@ with bit 1 cleared and bit 0 set, calls fn_08013a6a(r0, r1 - 4), calls
@ set_following_block_link(r1 - 4) and stores 2 in the word at +4 of the block
@ it returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802799e,"ax",%progbits
	.global fn_0802799e
	.thumb_func
	.type fn_0802799e, %function
fn_0802799e:
	push	{r4, r5, r6, lr}
	mov	r3, r0			@ control block
	subs	r2, #0x8
	mov	r4, r1			@ region start
	and	r0, r2, #0x3
	subs	r1, r2, r0		@ size rounded down to a multiple of 4
	lsls	r0, r4, #0x1e
	bne.n	.L080279bc		@ not 4-aligned
	sub.w	r0, r1, #0xc
	movw	r2, #0xfff5
	cmp	r0, r2
	bcc.n	.L080279c0
.L080279bc:
	movs	r0, #0x0
	pop	{r4, r5, r6, pc}
.L080279c0:
	ldrb	r0, [r4, #0x0]
	subs	r5, r4, #0x4
	and	r0, r0, #0x3
	orrs	r0, r1
	bic	r0, r0, #0x2
	orr	r1, r0, #0x1
	str	r1, [r4, #0x0]
	mov	r1, r5
	mov	r0, r3
	bl	fn_08013a6a
	mov	r0, r5
	bl	set_following_block_link
	ldrb	r1, [r0, #0x4]
	movs	r1, #0x2
	str	r1, [r0, #0x4]
	mov	r0, r4
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_080279ec - initialises a control block.
@ Parameter r0 = control block pointer; returns r0, or 0 when r0 is not
@ 4-aligned.
@ Stores r0 at +8 and +0xc and 0 at +0x10. Then for 10 groups sets the word at
@ +0x14 + 4*group to 0 and fills 32 words at +0x3c + 0x80*group with r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080279ec,"ax",%progbits
	.p2align 2
	.global fn_080279ec
	.thumb_func
	.type fn_080279ec, %function
fn_080279ec:
	push	{r4, r5, r6, lr}
	lsls	r1, r0, #0x1e
	beq.n	.L080279f6
	movs	r0, #0x0		@ not 4-aligned: return 0
	pop	{r4, r5, r6, pc}
.L080279f6:
	movs	r3, #0x0
	str	r0, [r0, #0x8]
	strd	r0, r3, [r0, #0xc]	@ +0xc = r0, +0x10 = 0
	mov	r1, r3			@ r1 = group index
.L08027a00:
	add.w	r2, r0, r1, lsl #2
	add.w	r4, r0, r1, lsl #7
	str	r3, [r2, #0x14]
	movs	r2, #0x0		@ r2 = word index
.L08027a0c:
	add.w	r6, r4, r2, lsl #2
	.inst.n	0x1c52			@ adds r2, r2, #1
	str	r0, [r6, #0x3c]
	cmp	r2, #0x20
	blt.n	.L08027a0c
	.inst.n	0x1c49			@ adds r1, r1, #1
	cmp	r1, #0xa
	blt.n	.L08027a00
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08027a20 - creates a heap in a memory region.
@ Parameters: r0 = base address, r1 = size; returns r0 = the control block.
@ Calls fn_080279ec(base), then fn_0802799e(control block, base + 0x53c,
@ size - 0x53c).
@ ----------------------------------------------------------------------------
	.section .text.fn_08027a20,"ax",%progbits
	.p2align 2
	.global fn_08027a20
	.thumb_func
	.type fn_08027a20, %function
fn_08027a20:
	push	{r4, r5, r6, lr}
	mov	r4, r1			@ size
	mov	r5, r0			@ base
	bl	fn_080279ec
	mov	r6, r0			@ control block
	subw	r2, r4, #0x53c
	addw	r1, r5, #0x53c
	bl	fn_0802799e
	mov	r0, r6
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08027a3c - releases a heap block.
@ Parameters: r0 = control block, r1 = user pointer; returns r0 = the size word
@ at r1 - 4 (0 when r1 is 0).
@ Returns 0 for r1 = 0. Loops forever when bit 0 of the size word at r1 - 4 is
@ set (0x08027a50). Calls set_block_and_next_flags(r1 - 8); when bit 1 of the
@ size byte at r1 - 4 is set it takes the neighbour pointer at r1 - 8, loops
@ forever when it is 0 (0x08027a90) or when bit 0 of the byte at its +4 is
@ clear (0x08027a92), calls fn_08013c50(control block, neighbour) and merges
@ with fn_08013a34(neighbour, block). Then calls fn_08013bb4 and fn_08013a6a
@ with the block.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027a3c,"ax",%progbits
	.p2align 2
	.global fn_08027a3c
	.thumb_func
	.type fn_08027a3c, %function
fn_08027a3c:
	push.w	{r4, r5, r6, r7, r8, lr}
	movs	r6, #0x0		@ result 0
	cbz	r1, .L08027a8a
	subs	r1, #0x8		@ block header
	mov	r5, r0			@ control block
	ldr	r6, [r1, #0x4]		@ size word
	mov	r4, r1
	lsls	r0, r6, #0x1f
	beq.n	.L08027a52
.L08027a50:
	b.n	.L08027a50		@ bit 0 set: endless loop
.L08027a52:
	mov	r0, r1
	bl	set_block_and_next_flags
	ldrb	r1, [r4, #0x4]
	mov	r0, r5
	lsls	r1, r1, #0x1e
	bpl.n	.L08027a7a
	ldr	r7, [r4, #0x0]		@ neighbour pointer
	cbz	r7, .L08027a90
	ldrb	r1, [r7, #0x4]
	lsls	r1, r1, #0x1f
	beq.n	.L08027a92
	mov	r1, r7
	bl	fn_08013c50
	mov	r1, r4
	mov	r0, r7
	bl	fn_08013a34
	mov	r4, r0
.L08027a7a:
	mov	r1, r4
	mov	r0, r5
	bl	fn_08013bb4
	mov	r1, r0
	mov	r0, r5
	bl	fn_08013a6a
.L08027a8a:
	mov	r0, r6
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08027a90:
	b.n	.L08027a90		@ neighbour pointer 0: endless loop
.L08027a92:
	b.n	.L08027a92		@ neighbour in use: endless loop

@ ----------------------------------------------------------------------------
@ fn_08027a94 - allocates a heap block.
@ Parameters: r0 = control block (kept in r5), r1 = requested size; returns what
@ the tail-called function returns.
@ r4 = fn_0801347e(size, 4) (size rounded up to a multiple of 4 and at least 12;
@ 0 when the size is 0 or the rounded size is 0x10000 or more); block =
@ fn_08013ae0(control block, r4). Restores r4..r6 and lr and tail-calls
@ fn_08013c00(control block, block, r4) (b.w).
@ ----------------------------------------------------------------------------
	.section .text.fn_08027a94,"ax",%progbits
	.global fn_08027a94
	.thumb_func
	.type fn_08027a94, %function
fn_08027a94:
	push	{r4, r5, r6, lr}
	mov	r2, r1			@ size
	mov	r5, r0			@ control block
	movs	r1, #0x4
	mov	r0, r2
	bl	fn_0801347e
	mov	r4, r0			@ rounded size
	mov	r1, r0
	mov	r0, r5
	bl	fn_08013ae0
	mov	r1, r0			@ block
	mov	r2, r4
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08013c00

@ ----------------------------------------------------------------------------
@ fn_08027aba - resizes a heap block (realloc-style tail function).
@ Parameters: r0 = control block S (kept in r9; fn_08022cb0 passes the word
@ 0x200004f0 loaded from 0x200004ec + 4), r1 = pointer P (r4), r2 = size n (r8);
@ returns r5 in r0 (pop of r4-r12 and pc at 0x08027b1c). Entered by the b.w at
@ 0x08022cd8 of fn_08022cb0.
@ P = 0 (movs sets Z): r5 = fn_08027a94(S, n), returns r5.
@ n = 0 (0x08027b08): calls fn_08027a3c(S, P), returns r5 (0 unless set below).
@ Otherwise r5 = P - 8, r10 = next_block_header(r5), r7 = word [r5 + 4] & ~3,
@ r11 = r7 + (word [r10 + 4] & ~3) + 4, r6 = fn_0801347e(n, 4). When n > r7
@ (unsigned) and r6 = 0 it returns 0 (0x08027b1a); bit 0 of byte [r5 + 4] set
@ loops forever at 0x08027b06.
@ When r6 > r7 and (bit 0 of byte [r10 + 4] is clear or r6 > r11) (0x08027b30):
@ r5 = fn_08027a94(S, n); returns 0 when r5 is 0; otherwise copies min(r7, n)
@ bytes from P to r5 with copy_bytes_08022ce0(r5, P, count), calls
@ fn_08027a3c(S, P) and returns r5.
@ Otherwise (0x08027b52): when r6 > r7 calls fn_08013bb4(S, r5) and
@ clear_block_and_next_flags(r5); bit 0 of byte [r5 + 4] set loops forever at
@ 0x08027b6c; fn_08013a56(r5, r6) = 0 returns P (r5 = r4 at 0x08027b98); else
@ r1 = fn_08013c72(r5, r6), clears bit 1 of word [r1 + 4],
@ r0 = fn_08013bb4(S, r1), fn_08013a6a(S, r0), returns P.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027aba,"ax",%progbits
	.global fn_08027aba
	.thumb_func
	.type fn_08027aba, %function
fn_08027aba:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	mov	r8, r2			@ n
	movs	r4, r1			@ P
	mov	r9, r0			@ S
	mov.w	r5, #0x0
	beq.n	.L08027b10		@ P = 0: plain allocate
	cmp.w	r8, #0x0
	beq.n	.L08027b08		@ n = 0: free
	sub.w	r5, r4, #0x8
	mov	r0, r5
	bl	next_block_header
	mov	r10, r0
	ldr	r0, [r5, #0x4]
	movs	r1, #0x4
	bic	r7, r0, #0x3		@ r7 = current size
	ldr.w	r0, [r10, #0x4]
	bic	r0, r0, #0x3
	add	r0, r7
	add.w	r11, r0, #0x4		@ r11 = size with the following block
	mov	r0, r8
	bl	fn_0801347e
	mov	r6, r0			@ r6 = rounded size
	cmp	r8, r7
	bls.n	.L08027b00
	cbz	r6, .L08027b1a
.L08027b00:
	ldrb	r0, [r5, #0x4]
	lsls	r0, r0, #0x1f
	beq.n	.L08027b20
.L08027b06:
	b.n	.L08027b06		@ block header bit 0 set: endless loop
.L08027b08:
	mov	r0, r9
	bl	fn_08027a3c
	b.n	.L08027b9a
.L08027b10:
	mov	r1, r2
	bl	fn_08027a94
	mov	r5, r0
	b.n	.L08027b9a
.L08027b1a:
	movs	r0, #0x0
.L08027b1c:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}
.L08027b20:
	cmp	r6, r7
	bls.n	.L08027b52
	ldrb.w	r0, [r10, #0x4]
	lsls	r0, r0, #0x1f
	beq.n	.L08027b30
	cmp	r6, r11
	bls.n	.L08027b52
.L08027b30:
	mov	r1, r8
	mov	r0, r9
	bl	fn_08027a94		@ allocate a new block
	movs	r5, r0
	beq.n	.L08027b9a
	mov	r0, r8
	cmp	r7, r8
	bcc.n	.L08027b44
	mov	r7, r0			@ r7 = min(current size, n)
.L08027b44:
	mov	r2, r7
	mov	r1, r4
	mov	r0, r5
	bl	copy_bytes_08022ce0
	mov	r1, r4
	b.n	.L08027b08		@ free the old block
.L08027b52:
	cmp	r6, r7
	bls.n	.L08027b64
	mov	r1, r5
	mov	r0, r9
	bl	fn_08013bb4
	mov	r0, r5
	bl	clear_block_and_next_flags
.L08027b64:
	ldrb	r0, [r5, #0x4]
	mov	r7, r9
	lsls	r0, r0, #0x1f
	beq.n	.L08027b6e
.L08027b6c:
	b.n	.L08027b6c		@ block header bit 0 set: endless loop
.L08027b6e:
	mov	r1, r6
	mov	r0, r5
	bl	fn_08013a56
	cbz	r0, .L08027b98
	mov	r1, r6
	mov	r0, r5
	bl	fn_08013c72
	mov	r1, r0
	ldr	r0, [r0, #0x4]
	bic	r0, r0, #0x2
	str	r0, [r1, #0x4]
	mov	r0, r7
	bl	fn_08013bb4
	mov	r1, r0
	mov	r0, r7
	bl	fn_08013a6a
.L08027b98:
	mov	r5, r4
.L08027b9a:
	mov	r0, r5
	b.n	.L08027b1c

@ ----------------------------------------------------------------------------
@ cosine_q15_degrees - cosine of an angle in whole degrees.
@ Parameter r0 = angle in whole degrees (halfword); returns the value times
@ 32767. Adds 0x5a (90) to the angle (sxth) and branches to sine_q15_degrees.
@ ----------------------------------------------------------------------------
	.section .text.cosine_q15_degrees,"ax",%progbits
	.global cosine_q15_degrees
	.thumb_func
	.type cosine_q15_degrees, %function
cosine_q15_degrees:
	adds	r0, #0x5a
	sxth	r0, r0
	b.w	sine_q15_degrees
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ sine_q15_degrees - sine of an angle in whole degrees.
@ Parameter r0 = angle in whole degrees; returns a signed value equal to 32767
@ times the sine.
@ Reduces r0 modulo 0x168 (360) with sdiv/mls and adds 360 when negative. Looks
@ up the 91-entry halfword table at 0x08050d1e (index 0 gives 0, index 0x5a
@ gives 32767): angles 0 to 89 use the index directly, 90 to 179 the index
@ 180 - angle, and 180 to 359 the negated entry with the index angle - 180 or
@ 360 - angle.
@ ----------------------------------------------------------------------------
	.section .text.sine_q15_degrees,"ax",%progbits
	.p2align 2
	.global sine_q15_degrees
	.thumb_func
	.type sine_q15_degrees, %function
sine_q15_degrees:
	mov.w	r1, #0x168
	sdiv	r2, r0, r1
	mls	r0, r1, r2, r0		@ r0 = angle mod 360
	cmp	r0, #0x0
	bge.n	.L08027bbe
	add.w	r0, r0, #0x168
	sxth	r0, r0
.L08027bbe:
	ldr	r1, .L08027bf8		@ r1 = table at 0x08050d1e
	cmp	r0, #0x5a
	bge.n	.L08027bca
.L08027bc4:
	ldrsh.w	r0, [r1, r0, lsl #1]
	bx	lr
.L08027bca:
	sub.w	r2, r0, #0x5a
	cmp	r2, #0x5a
	bcs.n	.L08027bda
	rsb.w	r0, r0, #0xb4		@ 180 - angle
	sxth	r0, r0
	b.n	.L08027bc4
.L08027bda:
	sub.w	r2, r0, #0xb4
	cmp	r2, #0x5a
	bcs.n	.L08027be6
	sxth	r0, r2			@ index angle - 180
	b.n	.L08027bec
.L08027be6:
	rsb.w	r0, r0, #0x168		@ index 360 - angle
	sxth	r0, r0
.L08027bec:
	ldrh.w	r0, [r1, r0, lsl #1]
	rsbs	r0, r0, #0		@ negate
	sxth	r0, r0
	bx	lr
	.short	0x0000			@ padding
.L08027bf8:
	.word	d_08050d1e		@ sine table

@ ----------------------------------------------------------------------------
@ fn_08027bfc - finds a line-break offset in UTF-8 text for a width limit.
@ Parameters: r0 = text pointer (UTF-8), r1 = font pointer, r2 = extra spacing
@ per glyph, r3 = width limit. Stack arguments after the push of r0-r3, r4-r11
@ and lr and the 0xc-byte frame: [sp + 0x40] flags (bit 0 skips glyphs for
@ which fn_08012c9c(state byte pointer, glyph) returns nonzero, bit 1 ignores
@ the limit and uses 0x1fff), [sp + 0x44] result width pointer, [sp + 0x48]
@ pointer to the state byte passed to fn_08012c9c, [sp + 0x4c] return-offset
@ mode. Returns a byte offset in the text.
@ Returns 0 for a null or empty text and for a null font. Decodes glyphs
@ through the function pointer at 0x20000508 (0x20000504 + 4), adds the width
@ from fn_08020a0a(font, glyph, next glyph) plus the spacing (when the glyph
@ width is above 0) and records the first offset where the width minus the
@ spacing exceeds the limit. Stops at 10, 0xd, a glyph in 0x4e00 to 0x9fa5, or
@ a byte of the NUL-terminated list at 0x08027d28 (bytes 0x20 0x2c 0x2e 0x3b
@ 0x3a 0x2d 0x5f: space , . ; : - _). On such a stop the width is stored to the
@ result width pointer (when it is not null) if the offset is 0 and no limit
@ break was recorded. When the glyph is none of those stops, the width is
@ stored to the result width pointer (when it is not null) while no limit break
@ was recorded.
@ When the limit was passed: returns the recorded break offset when the mode
@ argument is nonzero, otherwise stores 0 in the width pointer (when it is not
@ null) and returns 0 (0x08027cf6 to 0x08027d1e). When the limit was not passed
@ returns the offset reached.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027bfc,"ax",%progbits
	.p2align 2
	.global fn_08027bfc
	.thumb_func
	.type fn_08027bfc, %function
fn_08027bfc:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0xc
	movs.w	r9, r0			@ r9 = text pointer
	ldr	r7, [sp, #0x44]		@ r7 = result width pointer
	beq.n	.L08027d02
	ldrb.w	r0, [r9, #0x0]
	cmp	r0, #0x0
	beq.n	.L08027d02
	ldr	r0, [sp, #0x10]		@ font pointer
	cmp	r0, #0x0
	beq.n	.L08027cfc
	ldr	r0, [sp, #0x40]		@ flags
	lsls	r0, r0, #0x1e
	bpl.n	.L08027c24
	movw	r0, #0x1fff
	str	r0, [sp, #0x18]		@ limit = 0x1fff
.L08027c24:
	movs	r4, #0x0		@ r4 = offset
	ldr	r2, .L08027d24		@ r2 = 0x20000504
	str	r4, [sp, #0x0]
	str	r4, [sp, #0x4]
	ldr	r2, [r2, #0x4]		@ glyph decoder function pointer
	mov	r11, r4
	mov	r5, r4			@ r5 = width
	mov	r6, r4			@ r6 = glyph count
	mov.w	r8, #-1			@ r8 = break offset (none)
	mov	r1, sp
	mov	r0, r9
	blx	r2
	mov	r10, r0			@ r10 = current glyph
	ldr	r0, [sp, #0x0]
	str	r0, [sp, #0x4]
	b.n	.L08027ce8
.L08027c46:
	ldr	r2, .L08027d24
	add	r1, sp, #0x4
	mov	r0, r9
	ldr	r2, [r2, #0x4]
	blx	r2
	mov	r11, r0			@ r11 = next glyph
	ldr	r0, [sp, #0x40]
	.inst.n	0x1c76			@ adds r6, r6, #1
	lsls	r0, r0, #0x1f
	beq.n	.L08027c64
	mov	r1, r10
	ldr	r0, [sp, #0x48]
	bl	fn_08012c9c
	cbnz	r0, .L08027ccc
.L08027c64:
	mov	r2, r11
	mov	r1, r10
	ldr	r0, [sp, #0x10]
	bl	fn_08020a0a
	sxth	r0, r0
	adds	r1, r5, r0
	sxth	r5, r1
	cmp	r0, #0x0
	ble.n	.L08027c7e
	ldr	r0, [sp, #0x14]
	add	r0, r5
	sxth	r5, r0
.L08027c7e:
	cmp.w	r8, #0xffffffff
	bne.n	.L08027c90
	ldr	r0, [sp, #0x14]
	subs	r1, r5, r0
	ldr	r0, [sp, #0x18]
	cmp	r1, r0
	ble.n	.L08027c90
	mov	r8, r4			@ record the break offset
.L08027c90:
	mov	r0, r10
	cmp.w	r10, #0xa
	beq.n	.L08027cce
	cmp.w	r10, #0xd
	beq.n	.L08027cce
	mov	r1, r0
	sub.w	r0, r0, #0x4e00
	movw	r2, #0x51a5
	cmp	r0, r2
	bls.n	.L08027cce
	movs	r0, #0x0
	b.n	.L08027cbc
.L08027cb0:
	adr	r2, .L08027d28
	ldrb	r2, [r2, r0]
	cmp	r2, r1
	beq.n	.L08027cce
	.inst.n	0x1c40			@ adds r0, r0, #1
	uxtb	r0, r0
.L08027cbc:
	adr	r2, .L08027d28
	ldrb	r2, [r2, r0]
	cmp	r2, #0x0
	bne.n	.L08027cb0
	cbz	r7, .L08027ccc
	cmp.w	r8, #0xffffffff
	beq.n	.L08027cde
.L08027ccc:
	b.n	.L08027ce0
.L08027cce:
	cbnz	r4, .L08027cda
	cmp.w	r8, #0xffffffff
	bne.n	.L08027cda
	cbz	r7, .L08027cda
	str	r5, [r7, #0x0]
.L08027cda:
	.inst.n	0x1e76			@ subs r6, r6, #1
	b.n	.L08027cf0
.L08027cde:
	str	r5, [r7, #0x0]
.L08027ce0:
	ldrd	r4, r0, [sp]
	mov	r10, r11
	str	r0, [sp, #0x0]
.L08027ce8:
	ldrb.w	r0, [r9, r4]
	cmp	r0, #0x0
	bne.n	.L08027c46
.L08027cf0:
	cmp.w	r8, #0xffffffff
	beq.n	.L08027d04
	ldr	r0, [sp, #0x4c]		@ return-offset mode
	cbz	r0, .L08027d18
	mov	r0, r8
.L08027cfc:
	add	sp, #0x1c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08027d02:
	b.n	.L08027d1e
.L08027d04:
	cbz	r6, .L08027d12
	cmp.w	r10, #0xd
	bne.n	.L08027d14
	cmp.w	r11, #0xa
	bne.n	.L08027d14
.L08027d12:
	ldr	r4, [sp, #0x0]
.L08027d14:
	mov	r0, r4
	b.n	.L08027cfc
.L08027d18:
	cbz	r7, .L08027d1e
	movs	r0, #0x0
	str	r0, [r7, #0x0]
.L08027d1e:
	movs	r0, #0x0
	b.n	.L08027cfc
	.short	0x0000			@ padding
.L08027d24:
	.word	0x20000504
.L08027d28:
	.asciz	" ,.;:-_"		@ break characters (NUL terminated)

@ ----------------------------------------------------------------------------
@ fn_08027d30 - measures the size of a multi-line UTF-8 text.
@ Parameters: r0 = result pointer (two halfwords: width at +0, height at +2),
@ r1 = text pointer, r2 = font pointer, r3 = extra spacing per glyph (passed to
@ fn_08012b9c as r2 and to fn_08027dec as r3). Stack arguments after the push
@ of r0-r3, r4-r11 and lr and the 0xc-byte frame: [sp + 0x40] line spacing,
@ [sp + 0x44] width limit (passed to fn_08012b9c as r3), [sp + 0x48] flags (bit 1
@ replaces the limit by 0x1fff). No return value.
@ Clears both result halfwords. Returns at once for a null text or font. For
@ each line, calls fn_08012b9c to find the line length, adds the font height
@ (halfword at font + 8) plus the line spacing to the height halfword and
@ returns early when that sum would reach 0x8000 or more, and takes the maximum
@ of the width halfword and the line width from fn_08027dec.
@ Adds a final line when the text ends in 10 or 0xd. The result height is the
@ accumulated height minus one line spacing, or the font height when the height
@ is 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027d30,"ax",%progbits
	.p2align 2
	.global fn_08027d30
	.thumb_func
	.type fn_08027d30, %function
fn_08027d30:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0xc
	mov	r4, r0			@ r4 = result pointer
	mov.w	r0, #0x0
	ldr.w	r10, [sp, #0x48]	@ flags
	ldr.w	r9, [sp, #0x40]		@ line spacing
	strh	r0, [r4, #0x0]		@ width = 0
	mov	r11, r2			@ r11 = font pointer
	movs	r7, r1			@ r7 = text pointer
	strh	r0, [r4, #0x2]		@ height = 0
	beq.n	.L08027de2
	cmp.w	r11, #0x0
	beq.n	.L08027de2
	lsls.w	r0, r10, #0x1e
	bpl.n	.L08027d60
	movw	r0, #0x1fff
	str	r0, [sp, #0x44]		@ limit = 0x1fff
.L08027d60:
	movs	r5, #0x0		@ r5 = byte offset of the line
	mov	r8, r5
	ldrh.w	r6, [r11, #0x8]		@ r6 = font height
	b.n	.L08027db6
.L08027d6a:
	movs	r0, #0x0
	strd	r0, r10, [sp]		@ stack arguments of fn_08012b9c
	adds	r0, r7, r5
	str	r0, [sp, #0x8]		@ line start pointer
	mov	r1, r11
	ldr	r3, [sp, #0x44]
	ldr	r2, [sp, #0x18]
	bl	fn_08012b9c
	add	r8, r0			@ r8 = offset after the line
	ldrsh.w	r0, [r4, #0x2]
	add.w	r1, r6, r9
	add	r1, r0
	cmp.w	r1, #0x8000
	bcs.n	.L08027de2
	add	r0, r6
	add	r0, r9
	strh	r0, [r4, #0x2]		@ height += font height + line spacing
	sub.w	r1, r8, r5		@ line length
	str.w	r10, [sp, #0x0]
	mov	r2, r11
	ldr	r3, [sp, #0x18]
	ldr	r0, [sp, #0x8]
	bl	fn_08027dec
	ldrsh.w	r1, [r4]
	cmp	r1, r0
	blt.n	.L08027db2
	mov	r0, r1			@ keep the larger width
.L08027db2:
	strh	r0, [r4, #0x0]
	mov	r5, r8
.L08027db6:
	ldrb	r0, [r7, r5]
	cmp	r0, #0x0
	bne.n	.L08027d6a
	cbz	r5, .L08027dd6
	adds	r0, r7, r5
	ldrb.w	r0, [r0, #-0x1]		@ last byte of the text
	cmp	r0, #0xa
	beq.n	.L08027dcc
	cmp	r0, #0xd
	bne.n	.L08027dd6
.L08027dcc:
	ldrh	r1, [r4, #0x2]
	add.w	r0, r6, r9
	add	r0, r1
	strh	r0, [r4, #0x2]		@ add a final line
.L08027dd6:
	ldrsh.w	r0, [r4, #0x2]
	cbz	r0, .L08027de8
	sub.w	r0, r0, r9
	strh	r0, [r4, #0x2]		@ height minus one line spacing
.L08027de2:
	add	sp, #0x1c
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08027de8:
	strh	r6, [r4, #0x2]		@ empty: height = font height
	b.n	.L08027de2

@ ----------------------------------------------------------------------------
@ fn_08027dec - pixel width of a text run.
@ Parameters: r0 = text pointer, r1 = byte length, r2 = font pointer, r3 = extra
@ spacing, stack argument [sp + 0x30] (after the push of r0-r3, r4-r10 and lr)
@ = flags; returns r0 = the pixel width.
@ Returns 0 for a null text, a null font or an empty text. Walks the text with
@ fn_08012b6c(text, &glyph, &next, &index) and sums
@ fn_08020a0a(font, glyph, next) plus the spacing for each glyph of positive
@ width (flags bit 0 skips glyphs for which fn_08012c9c(state byte, glyph)
@ returns nonzero) until the index reaches the length. Subtracts one spacing
@ from a positive sum.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027dec,"ax",%progbits
	.p2align 2
	.global fn_08027dec
	.thumb_func
	.type fn_08027dec, %function
fn_08027dec:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r6, r3			@ r6 = spacing
	ldr.w	r9, [sp, #0x30]		@ r9 = flags
	mov	r8, r2			@ r8 = font pointer
	mov	r5, r1			@ r5 = byte length
	movs	r7, r0			@ r7 = text pointer
	beq.n	.L08027e18
	cmp.w	r8, #0x0
	beq.n	.L08027e18
	ldrb	r0, [r7, #0x0]
	cmp	r0, #0x0
	beq.n	.L08027e1a
	movs	r0, #0x0
	mov	r4, r0			@ r4 = width sum
	str	r0, [sp, #0x8]		@ index = 0
	strb.w	r0, [sp, #0xc]		@ state byte = 0
	cbnz	r5, .L08027e52
	b.n	.L08027e60
.L08027e18:
	movs	r0, #0x0
.L08027e1a:
	add	sp, #0x10
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L08027e20:
	add	r3, sp, #0x8
	add	r2, sp, #0x4
	mov	r1, sp
	mov	r0, r7
	bl	fn_08012b6c
	lsls.w	r0, r9, #0x1f
	beq.n	.L08027e3c
	add	r0, sp, #0xc
	ldr	r1, [sp, #0x0]
	bl	fn_08012c9c
	cbnz	r0, .L08027e52
.L08027e3c:
	ldrd	r1, r2, [sp]		@ glyph, next glyph
	mov	r0, r8
	bl	fn_08020a0a
	sxth	r0, r0
	cmp	r0, #0x0
	ble.n	.L08027e52
	add	r0, r4
	add	r0, r6
	sxth	r4, r0
.L08027e52:
	ldr	r0, [sp, #0x8]
	cmp	r0, r5
	bcc.n	.L08027e20
	cmp	r4, #0x0
	ble.n	.L08027e60
	subs	r0, r4, r6
	sxth	r4, r0
.L08027e60:
	mov	r0, r4
	b.n	.L08027e1a

@ ----------------------------------------------------------------------------
@ fn_08027e64 - byte offset after a number of characters.
@ Parameters: r0 = text pointer, r1 = character count; returns r0 = the byte
@ offset reached.
@ Advances over up to r1 characters or until a 0 byte, adding for each the
@ length returned by the function pointer at 0x20000504 (called with the
@ pointer to the character; 1 is added when it returns 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_08027e64,"ax",%progbits
	.p2align 2
	.global fn_08027e64
	.thumb_func
	.type fn_08027e64, %function
fn_08027e64:
	push.w	{r4, r5, r6, r7, r8, lr}
	movs	r4, #0x0		@ r4 = byte offset
	mov	r7, r1			@ character count
	mov	r6, r0			@ text pointer
	mov	r5, r4			@ r5 = characters done
	ldr.w	r8, .L08027e98		@ r8 = 0x20000504
	b.n	.L08027e86
.L08027e76:
	ldr.w	r1, [r8, #0x0]		@ length function pointer
	adds	r0, r6, r4
	blx	r1
	cbnz	r0, .L08027e82
	movs	r0, #0x1
.L08027e82:
	add	r4, r0
	.inst.n	0x1c6d			@ adds r5, r5, #1
.L08027e86:
	cmp	r5, r7
	bcs.n	.L08027e90
	ldrb	r0, [r6, r4]
	cmp	r0, #0x0
	bne.n	.L08027e76
.L08027e90:
	mov	r0, r4
	pop.w	{r4, r5, r6, r7, r8, pc}
	.short	0x0000			@ padding
.L08027e98:
	.word	0x20000504

@ ----------------------------------------------------------------------------
@ fn_08027e9c - counts characters up to a byte offset.
@ Parameters: r0 = text pointer, r1 = byte offset limit; returns r0 = the
@ character count.
@ Calls the function pointer at 0x20000508 (0x20000504 + 4) with the text and
@ the address of an index word (starting at 0) repeatedly until the index
@ reaches r1, and counts the calls.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027e9c,"ax",%progbits
	.p2align 2
	.global fn_08027e9c
	.thumb_func
	.type fn_08027e9c, %function
fn_08027e9c:
	push	{r3, r4, r5, r6, r7, lr}
	mov	r7, r0			@ text pointer
	movs	r0, #0x0
	mov	r5, r1			@ limit
	mov	r4, r0			@ r4 = count
	ldr	r6, .L08027ec0		@ r6 = 0x20000504
	str	r0, [sp, #0x0]		@ index = 0
	b.n	.L08027eb6
.L08027eac:
	ldr	r2, [r6, #0x4]		@ decoder function pointer
	mov	r1, sp
	mov	r0, r7
	blx	r2
	.inst.n	0x1c64			@ adds r4, r4, #1
.L08027eb6:
	ldr	r0, [sp, #0x0]
	cmp	r0, r5
	bcc.n	.L08027eac
	mov	r0, r4
	pop	{r3, r4, r5, r6, r7, pc}
.L08027ec0:
	.word	0x20000504

@ ----------------------------------------------------------------------------
@ fn_08027ec4 - counts the characters of a text.
@ Parameter r0 = text pointer; returns r0 = the character count.
@ Calls the function pointer at 0x20000508 (0x20000504 + 4) with the text and
@ the address of an index word (starting at 0) until the byte at the index is
@ 0, and counts the calls.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027ec4,"ax",%progbits
	.p2align 2
	.global fn_08027ec4
	.thumb_func
	.type fn_08027ec4, %function
fn_08027ec4:
	push	{r3, r4, r5, r6, r7, lr}
	movs	r4, #0x0		@ r4 = count
	mov	r5, r0			@ text pointer
	ldr	r6, .L08027ee8		@ r6 = 0x20000504
	str	r4, [sp, #0x0]		@ index = 0
	b.n	.L08027eda
.L08027ed0:
	ldr	r2, [r6, #0x4]		@ decoder function pointer
	mov	r1, sp
	mov	r0, r5
	blx	r2
	.inst.n	0x1c64			@ adds r4, r4, #1
.L08027eda:
	ldr	r0, [sp, #0x0]
	ldrb	r0, [r5, r0]
	cmp	r0, #0x0
	bne.n	.L08027ed0
	mov	r0, r4
	pop	{r3, r4, r5, r6, r7, pc}
	.short	0x0000			@ padding
.L08027ee8:
	.word	0x20000504

@ ----------------------------------------------------------------------------
@ utf8_decode_next - decodes the next UTF-8 character.
@ Parameters: r0 = text pointer, r1 = pointer to the byte index word (null uses
@ a local index word of 0); returns r0 = the code point and advances the index.
@ A single byte below 0x80 is returned as is. A lead byte 110xxxxx (top bits
@ shifted right by 5 give 6), 1110xxxx (shift 4 gives 0xe) or 11110xxx (shift 3
@ gives 0x1e) combines the payload bits with the 6-bit payloads of the 1 to 3
@ continuation bytes (top bits 10, checked by a shift right by 6 giving 2).
@ Returns 0 when a continuation byte is not 10xxxxxx (the index then points at
@ that byte). A lead byte of another kind (0x80 to 0xbf, 0xf8 to 0xff) returns 0
@ and advances the index by 1.
@ ----------------------------------------------------------------------------
	.section .text.utf8_decode_next,"ax",%progbits
	.p2align 2
	.global utf8_decode_next
	.thumb_func
	.type utf8_decode_next, %function
utf8_decode_next:
	push	{r3, r4, r5, r6, lr}
	movs	r5, #0x0		@ r5 = result
	mov	r4, r0			@ text pointer
	str	r5, [sp, #0x0]		@ local index word = 0
	cbnz	r1, .L08027ef8
	mov	r1, sp			@ null index pointer: use the local word
.L08027ef8:
	ldr	r2, [r1, #0x0]		@ r2 = index
	ldrb	r0, [r4, r2]		@ lead byte
	lsls	r3, r0, #0x18
	bmi.n	.L08027f04
	mov	r5, r0			@ below 0x80: the byte itself
	b.n	.L08027f6e
.L08027f04:
	movs	r6, #0x6
	movs	r3, #0x2
	cmp.w	r6, r0, lsr #5
	bne.n	.L08027f1c
	lsls	r0, r0, #0x1b		@ 2-byte sequence: payload bits << 6
	lsrs	r0, r0, #0x15
	b.n	.L08027f5e
.L08027f14:
	and	r3, r4, #0x3f		@ last continuation payload
	adds	r5, r3, r0
	b.n	.L08027f6e
.L08027f1c:
	movs	r6, #0xe
	cmp.w	r6, r0, lsr #4
	bne.n	.L08027f2a
	lsls	r0, r0, #0x1c		@ 3-byte sequence: payload bits << 12
	lsrs	r0, r0, #0x10
	b.n	.L08027f4a
.L08027f2a:
	movs	r6, #0x1e
	cmp.w	r6, r0, lsr #3
	bne.n	.L08027f6e
	.inst.n	0x1c52			@ adds r2, r2, #1
	str	r2, [r1, #0x0]
	lsls	r0, r0, #0x1d		@ 4-byte sequence: payload bits << 18
	ldrb	r5, [r4, r2]
	lsrs	r0, r0, #0xb
	cmp.w	r3, r5, lsr #6
	bne.n	.L08027f6a
	and	r5, r5, #0x3f
	add.w	r0, r0, r5, lsl #12
.L08027f4a:
	.inst.n	0x1c52			@ adds r2, r2, #1
	str	r2, [r1, #0x0]
	ldrb	r5, [r4, r2]
	cmp.w	r3, r5, lsr #6
	bne.n	.L08027f6a
	and	r5, r5, #0x3f
	add.w	r0, r0, r5, lsl #6
.L08027f5e:
	.inst.n	0x1c52			@ adds r2, r2, #1
	str	r2, [r1, #0x0]
	ldrb	r4, [r4, r2]
	cmp.w	r3, r4, lsr #6
	beq.n	.L08027f14
.L08027f6a:
	movs	r0, #0x0		@ bad continuation byte
	pop	{r3, r4, r5, r6, pc}
.L08027f6e:
	.inst.n	0x1c52			@ adds r2, r2, #1
	mov	r0, r5
	str	r2, [r1, #0x0]
	pop	{r3, r4, r5, r6, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08027f78 - decodes the character before the index.
@ Parameters: r0 = text pointer, r1 = pointer to the byte index word; returns
@ r0 = a code point or 0.
@ Subtracts 1 from the index word, then tries at most 4 positions (counter r5,
@ exit at 0x08027f8c when it reaches 4): calls the function pointer at
@ 0x20000504 with text + index and treats a nonzero result as a character
@ start; on a zero result with index 0 returns 0 (0x08027f9a), otherwise
@ subtracts 1 from the index and tries again; after 4 failed tries returns 0.
@ At a character start copies the index to a local word and returns the result
@ of the function pointer at 0x20000508 (0x20000504 + 4) called with the text
@ and the address of the local word; the index word keeps the character start.
@ ----------------------------------------------------------------------------
	.section .text.fn_08027f78,"ax",%progbits
	.p2align 2
	.global fn_08027f78
	.thumb_func
	.type fn_08027f78, %function
fn_08027f78:
	push	{r3, r4, r5, r6, r7, lr}
	mov	r7, r0			@ text pointer
	ldr	r0, [r1, #0x0]
	movs	r5, #0x0		@ r5 = try counter
	.inst.n	0x1e40			@ subs r0, r0, #1
	mov	r4, r1			@ index pointer
	ldr	r6, .L08027fbc		@ r6 = 0x20000504
	str	r0, [r1, #0x0]
	b.n	.L08027f8e
.L08027f8a:
	cmp	r5, #0x4
	bcs.n	.L08027fb6
.L08027f8e:
	ldr	r0, [r4, #0x0]
	ldr	r1, [r6, #0x0]		@ length function pointer
	add	r0, r7
	blx	r1
	cbnz	r0, .L08027fa0
	ldr	r1, [r4, #0x0]
	cbz	r1, .L08027fb6
	.inst.n	0x1e49			@ subs r1, r1, #1
	str	r1, [r4, #0x0]
.L08027fa0:
	.inst.n	0x1c6d			@ adds r5, r5, #1
	uxtb	r5, r5
	cmp	r0, #0x0
	beq.n	.L08027f8a
	ldr	r0, [r4, #0x0]
	str	r0, [sp, #0x0]		@ local index word
	ldr	r2, [r6, #0x4]		@ decoder function pointer
	mov	r1, sp
	mov	r0, r7
	blx	r2
	pop	{r3, r4, r5, r6, r7, pc}
.L08027fb6:
	movs	r0, #0x0
	pop	{r3, r4, r5, r6, r7, pc}
	.short	0x0000			@ padding
.L08027fbc:
	.word	0x20000504

@ ----------------------------------------------------------------------------
@ utf8_lead_byte_length - length of a UTF-8 sequence from its lead byte.
@ Parameter r0 = pointer to a byte; returns r0 = the length of the sequence.
@ A byte below 0x80 gives 1, top bits 110 give 2, 1110 give 3, 11110 give 4, any
@ other value gives 0.
@ ----------------------------------------------------------------------------
	.section .text.utf8_lead_byte_length,"ax",%progbits
	.p2align 2
	.global utf8_lead_byte_length
	.thumb_func
	.type utf8_lead_byte_length, %function
utf8_lead_byte_length:
	ldrb	r0, [r0, #0x0]
	lsls	r1, r0, #0x18
	bmi.n	.L08027fca
	movs	r0, #0x1
	bx	lr
.L08027fca:
	movs	r1, #0x6
	cmp.w	r1, r0, lsr #5
	bne.n	.L08027fd6
	movs	r0, #0x2
	bx	lr
.L08027fd6:
	movs	r1, #0xe
	cmp.w	r1, r0, lsr #4
	bne.n	.L08027fe2
	movs	r0, #0x3
	bx	lr
.L08027fe2:
	movs	r1, #0x1e
	cmp.w	r1, r0, lsr #3
	bne.n	.L08027fee
	movs	r0, #0x4
	bx	lr
.L08027fee:
	movs	r0, #0x0
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ lowest_set_bit_index - index of the lowest set bit.
@ Parameter r0 = value; returns r0 = 31 - clz(r0 & -r0), the index of the
@ lowest set bit of r0, and -1 when r0 is 0.
@ ----------------------------------------------------------------------------
	.section .text.lowest_set_bit_index,"ax",%progbits
	.p2align 2
	.global lowest_set_bit_index
	.thumb_func
	.type lowest_set_bit_index, %function
lowest_set_bit_index:
	mvns	r1, r0
	.inst.n	0x1c49			@ adds r1, r1, #1
	ands	r0, r1			@ r0 & -r0
	clz	r0, r0
	rsb.w	r0, r0, #0x1f
	bx	lr

@ ----------------------------------------------------------------------------
@ highest_set_bit_index - index of the highest set bit.
@ Parameter r0 = value; returns r0 = 0x20 - clz(r0) - 1, the index of the
@ highest set bit of r0, and -1 when r0 is 0.
@ ----------------------------------------------------------------------------
	.section .text.highest_set_bit_index,"ax",%progbits
	.p2align 2
	.global highest_set_bit_index
	.thumb_func
	.type highest_set_bit_index, %function
highest_set_bit_index:
	cbz	r0, .L0802a9fa
	clz	r0, r0
	rsb.w	r0, r0, #0x20
.L0802a9fa:
	.inst.n	0x1e40			@ subs r0, r0, #1
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ u16_pointer_difference - difference of two unsigned halfwords.
@ Parameters: r0 = pointer to unsigned halfword a, r1 = pointer to unsigned
@ halfword b; returns r0 = a - b of the two unsigned 16-bit values.
@ ----------------------------------------------------------------------------
	.section .text.u16_pointer_difference,"ax",%progbits
	.global u16_pointer_difference
	.thumb_func
	.type u16_pointer_difference, %function
u16_pointer_difference:
	ldrh	r0, [r0, #0x0]
	ldrh	r1, [r1, #0x0]
	subs	r0, r0, r1
	bx	lr
