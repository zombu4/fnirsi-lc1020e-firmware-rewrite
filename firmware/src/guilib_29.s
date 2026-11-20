@ guilib_29.s - GUI library routines: object timer list, bitmap sampling, block allocator helpers, font and file handle helpers
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08013594 - no parameters; returns the value of the tail-called function.
@ Stores 1 in the byte at 0x200004bc. Calls get_word_4_or_zero with 0x20008080.
@ Loads the word at 0x200004c4 into r0 before the branch. When the call
@ returned 0 it tail-calls record_set_flag, otherwise record_clear_flag.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013594,"ax",%progbits
	.p2align 2
	.global fn_08013594
	.thumb_func
	.type fn_08013594, %function
fn_08013594:
	push {r4, lr}
	ldr r4, .L080135b8
	movs r0, #1
	strb r0, [r4]
	ldr r0, .L080135bc
	bl get_word_4_or_zero
	cmp r0, #0
	ldr r0, [r4, #8]
	beq.n .L080135b0
	pop.w {r4, lr}
	b.w record_clear_flag
.L080135b0:
	pop.w {r4, lr}
	b.w record_set_flag
.L080135b8:
	.word 0x200004bc
.L080135bc:
	.word 0x20008080

@ ----------------------------------------------------------------------------
@ fn_080135c0 - r0 = object pointer; no return value.
@ Object fields: byte +0x42 flags, word +0x38, short +0x40 counter, words
@ +0x20 +0x28 +0x2c +0x30 +0x34 +0x3c, function pointers +0xc and +0x10.
@ Reads the flag byte (+0x42) and the word at +0x38. When flag bit 1 is clear
@ and the short at +0x40 is neither 0 nor 0xffff it decrements the short.
@ The object is retired when the short is 0 and (the word at +0x38 is 0 or
@ flag bit 1 is set): calls fn_080126a2 with 0x20008080 and the object, calls
@ fn_08013594, calls the function pointer at +0xc and then the one at +0x10
@ when they are not 0, and tail-calls fn_08022c68 with the object.
@ Otherwise it stores the negated word at +0x3c in the word at +0x30; when the
@ word at +0x38 is not 0 it also stores the negated word at +0x34 when flag
@ bit 1 is clear, toggles flag bit 1, swaps the words at +0x20 and +0x28 and
@ swaps the words at +0x2c and +0x38.
@ ----------------------------------------------------------------------------
	.section .text.fn_080135c0,"ax",%progbits
	.p2align 2
	.global fn_080135c0
	.thumb_func
	.type fn_080135c0, %function
fn_080135c0:
	push {r4, lr}
	mov r4, r0
	ldrb.w r0, [r0, #0x42]
	ldr r1, [r4, #0x38]
	lsls r2, r0, #0x1e
	bmi.n .L080135e2
	ldrh.w r2, [r4, #0x40]
	cbz r2, .L080135e8
	sub.w r3, r2, #0xff00
	subs r3, #0xff
	beq.n .L08013614
	.inst.n 0x1e52  @ subs r2, r2, #1
	strh.w r2, [r4, #0x40]
.L080135e2:
	ldrh.w r2, [r4, #0x40]
	cbnz r2, .L08013614
.L080135e8:
	cbz r1, .L080135ee
	lsls r2, r0, #0x1e
	bpl.n .L08013614
.L080135ee:
	mov r1, r4
	ldr r0, .L08013644
	bl fn_080126a2
	bl fn_08013594
	ldr r1, [r4, #0xc]
	cbz r1, .L08013602
	mov r0, r4
	blx r1
.L08013602:
	ldr r1, [r4, #0x10]
	cbz r1, .L0801360a
	mov r0, r4
	blx r1
.L0801360a:
	mov r0, r4
	pop.w {r4, lr}
	b.w fn_08022c68
.L08013614:
	ldr r2, [r4, #0x3c]
	rsbs r2, r2, #0
	str r2, [r4, #0x30]
	cmp r1, #0
	beq.n .L08013642
	lsls r2, r0, #0x1e
	bmi.n .L08013628
	ldr r2, [r4, #0x34]
	rsbs r2, r2, #0
	str r2, [r4, #0x30]
.L08013628:
	asrs r2, r0, #1
	.inst.n 0x1c52  @ adds r2, r2, #1
	bfi r0, r2, #1, #1
	strb.w r0, [r4, #0x42]
	ldr r2, [r4, #0x28]
	ldr r0, [r4, #0x20]
	str r2, [r4, #0x20]
	str r0, [r4, #0x28]
	ldr r0, [r4, #0x2c]
	str r1, [r4, #0x2c]
	str r0, [r4, #0x38]
.L08013642:
	pop {r4, pc}
.L08013644:
	.word 0x20008080

@ ----------------------------------------------------------------------------
@ fn_08013648 - no parameters; no return value.
@ Calls ticks_since with the word at 0x200004c0 and keeps the result as the
@ elapsed amount (r6); toggles the byte at 0x200004bd with 1.
@ Walks the list at 0x20008080 with get_word_4_or_zero (first) and
@ read_word_at_base_plus_offset_4 (next). For each entry whose bit 2 of the
@ byte at +0x42 differs from the byte at 0x200004bd: copies that toggle bit
@ into the entry, and when bit 3 of the byte is clear and the signed word at
@ +0x30 is below 1 and word + elapsed is not negative it calls the function
@ pointers at +0x14 (adds the result to the words at +0x20 and +0x28, only
@ when bit 0 of the old flag byte is clear) and +0x8 and sets bit 3.
@ Adds the elapsed amount to the word at +0x30; when the result is not
@ negative it limits it to the word at +0x2c, calls the function pointer at
@ +0x1c, stores the result in the word at +0x24 and calls the function pointer
@ at +0x4 with the word at +0 when the value changed, and calls fn_080135c0
@ when the word at +0x30 reaches the word at +0x2c.
@ Restarts the walk when the byte at 0x200004bc became non-zero; at the end of
@ the list stores the result of fn_080277a0 in the word at 0x200004c0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013648,"ax",%progbits
	.p2align 2
	.global fn_08013648
	.thumb_func
	.type fn_08013648, %function
fn_08013648:
	push {r4, r5, r6, lr}
	ldr r5, .L0801370c
	ldr r0, [r5, #4]
	bl ticks_since
	mov r6, r0
	ldrb r0, [r5, #1]
	eor.w r0, r0, #1
	strb r0, [r5, #1]
	b.n .L080136ee
.L0801365e:
	movs r0, #0
	strb r0, [r5]
	ldrb.w r0, [r4, #0x42]
	ldrb r1, [r5, #1]
	ubfx r2, r0, #2, #1
	cmp r2, r1
	beq.n .L080136f6
	bfi r0, r1, #2, #1
	strb.w r0, [r4, #0x42]
	ldr r1, [r4, #0x30]
	adds r2, r1, r6
	lsls r3, r0, #0x1c
	bmi.n .L080136b4
	cmp r1, #0
	bgt.n .L080136b4
	cmp r2, #0
	blt.n .L080136b4
	lsls r0, r0, #0x1f
	bne.n .L080136a0
	ldr r1, [r4, #0x14]
	cbz r1, .L080136a0
	mov r0, r4
	blx r1
	ldr r1, [r4, #0x20]
	add r1, r0
	str r1, [r4, #0x20]
	ldr r1, [r4, #0x28]
	add r0, r1
	str r0, [r4, #0x28]
.L080136a0:
	ldr r1, [r4, #8]
	cbz r1, .L080136a8
	mov r0, r4
	blx r1
.L080136a8:
	ldrb.w r0, [r4, #0x42]
	orr.w r0, r0, #8
	strb.w r0, [r4, #0x42]
.L080136b4:
	ldr r0, [r4, #0x30]
	adds r0, r0, r6
	str r0, [r4, #0x30]
	bmi.n .L080136ea
	ldr r1, [r4, #0x2c]
	cmp r0, r1
	ble.n .L080136c4
	str r1, [r4, #0x30]
.L080136c4:
	ldr r1, [r4, #0x1c]
	mov r0, r4
	blx r1
	mov r1, r0
	ldr r0, [r4, #0x24]
	cmp r0, r1
	beq.n .L080136dc
	str r1, [r4, #0x24]
	ldr r2, [r4, #4]
	cbz r2, .L080136dc
	ldr r0, [r4]
	blx r2
.L080136dc:
	ldrd r0, r1, [r4, #0x2c]
	cmp r1, r0
	blt.n .L080136ea
	mov r0, r4
	bl fn_080135c0
.L080136ea:
	ldrb r0, [r5]
	cbz r0, .L080136f6
.L080136ee:
	ldr r0, .L08013710
	bl get_word_4_or_zero
	b.n .L080136fe
.L080136f6:
	mov r1, r4
	ldr r0, .L08013710
	bl read_word_at_base_plus_offset_4
.L080136fe:
	movs r4, r0
	bne.n .L0801365e
	bl fn_080277a0
	str r0, [r5, #4]
	pop {r4, r5, r6, pc}
	.short 0x0000  @ padding
.L0801370c:
	.word 0x200004bc
.L08013710:
	.word 0x20008080

@ ----------------------------------------------------------------------------
@ run_callback_chain - r0 = node pointer (offset 0 = function pointer, offset
@ 4 = pointer to the next node), r1 = argument; no return value.
@ Recurses with the node at offset 4 and the same r1 first when the pointer at
@ offset 4 is not 0. Then, when the word at offset 0 is not 0, calls the
@ function at offset 0 with (node, r1) as a tail call through bx.
@ ----------------------------------------------------------------------------
	.section .text.run_callback_chain,"ax",%progbits
	.p2align 2
	.global run_callback_chain
	.thumb_func
	.type run_callback_chain, %function
run_callback_chain:
	push {r4, r5, r6, lr}
	mov r4, r0
	ldr r0, [r0, #4]
	mov r5, r1
	cbz r0, .L08013722
	bl run_callback_chain
.L08013722:
	ldr r2, [r4]
	cmp r2, #0
	beq.n .L08013732
	mov r1, r5
	mov r0, r4
	pop.w {r4, r5, r6, lr}
	bx r2
.L08013732:
	pop {r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08013734 - samples a source bitmap along a line and writes one output
@ halfword (colour) and one output byte (alpha) per index.
@ Parameters: r0 = source base (stored at [sp + 0x64]), r1 = width ([sp +
@ 0x68]), r2 = height (r6), r3 = row stride in pixels (r8); stack arguments at
@ entry [sp + 0]: start x (fp), [sp + 4]: start y (sl), [sp + 8]: x step,
@ [sp + 0xc]: y step, [sp + 0x10]: number of outputs, [sp + 0x14]: output
@ halfword array, [sp + 0x18]: output byte array, [sp + 0x1c]: mode; these sit
@ at [sp + 0x98..0xb4] after the prologue (push r0-r3 / r4-r8 / sb / sl / fp /
@ lr, sub sp #0x64). No return value.
@ Mode (0x08013746-0x08013758): 4 sets r7 = 0, r5 = 2; 5 sets r7 = 1, r5 = 3;
@ 6 sets r7 = 1, r5 = 2 and sb = word [[return_word_200004b8()] + 0x38]; 0x14
@ sets r7 = 1, r5 = 2 (r5 = bytes per source pixel); any other mode jumps to
@ the exit.
@ Setup: [sp + 0x38] = smulbb(stride, height), [sp + 0x34] = width - 1,
@ [sp + 0x18] = height - 1, index r4 = 0, then the loop test (signed r4 <
@ output count, r4 kept as sxth).
@ Per index: x = start x + ((x step * i) >> 8), y = start y + ((y step * i) >>
@ 8) (arithmetic), ix = x >> 8, iy = y >> 8; when ix < 0, ix >= width, iy < 0
@ or iy >= height the output byte is 0. Otherwise fx = x & 0xff, fy = y &
@ 0xff: for f < 0x80 the weight is (0x7f - f) * 2 and the step d = -1,
@ otherwise f * 2 - 0x100 and d = +1 (weights [sp + 0x24] for x, [sp + 0x28]
@ for y, d in r1 / r2); A0 = base + (iy * stride + ix) * r5 ([sp + 0x1c]).
@ Border: when ix + dx < 0 or > width - 1 or iy + dy < 0 or > height - 1 the
@ output halfword is the little-endian halfword of the first two bytes at A0
@ and the output byte is: mode 5 byte A0[2]; mode 6 0 when that halfword
@ equals the 16-bit key sb else 0xff; mode 0x14 byte plane[iy * stride + ix];
@ mode 4 0xff; this value a is then scaled to ((0xff - w) * a) >> 8 with w =
@ x weight when the x neighbour is outside (ix == 0 and dx < 0, or ix == width
@ - 1 and dx > 0), else y weight when the y neighbour is outside (same test on
@ iy), else the byte is 0.
@ Inside: A1 = A0 + dx * r5 ([sp + 0x58]), A2 = A0 + dy * stride * r5 ([sp +
@ 0x30]); mode 5 alpha bytes are byte 2 of the pixels A0, A1, A2; mode 0x14
@ alpha bytes come from the byte plane at base + 2 * stride * height; the
@ vertical alpha = ((a0 * (0x100 - wy) + aV * wy) >> 8) & 0xff and the
@ horizontal alpha likewise with wx (each skipped when equal to a0); output
@ byte = (horizontal + vertical) >> 1; mode 6: the output byte is 0 when the
@ halfword at A0, A1 or A2 equals the key, else 0xff; mode 4: 0xff. In modes
@ 5, 6 and 0x14 an output byte of 0 ends the index without writing the
@ halfword; otherwise the colours c0 (A0), cH (A1), cV (A2) are read as
@ halfwords in mode 4 and as two bytes each, low byte first, in modes 5, 6 and
@ 0x14, and when all three are equal c0 is stored in the output halfword; else
@ r = blend_565_0801da10(cV, c0, wy & 0xff), s = blend_565_0801da10(cH, c0, wx
@ & 0xff), result = blend_565_0801da10(s, r, 0x7f) is stored in the output
@ halfword.
@ Index step: r4 += 1, sxth; exit: add sp #0x74, pop.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013734,"ax",%progbits
	.p2align 2
	.global fn_08013734
	.thumb_func
	.type fn_08013734, %function
fn_08013734:
	push.w {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0x64
	mov r8, r3
	ldrd r11, r1, [sp, #0x98]
	ldr r0, [sp, #0xb4]
	mov r6, r2
	mov r10, r1
	mov.w r9, #0
	cmp r0, #4
	beq.n .L08013772
	cmp r0, #5
	beq.n .L08013776
	cmp r0, #6
	beq.n .L0801377c
	cmp r0, #0x14
	bne.n .L0801383c
	movs r7, #1
.L0801375c:
	movs r5, #2
.L0801375e:
	movs r4, #0
	smulbb r0, r8, r6
	str r0, [sp, #0x38]
	ldr r0, [sp, #0x68]
	.inst.n 0x1e40  @ subs r0, r0, #1
	str r0, [sp, #0x34]
	subs r0, r6, #1
	str r0, [sp, #0x18]
	b.n .L08013a16
.L08013772:
	movs r7, #0
	b.n .L0801375c
.L08013776:
	movs r7, #1
	movs r5, #3
	b.n .L0801375e
.L0801377c:
	movs r7, #1
	movs r5, #2
	bl return_word_200004b8
	ldr r0, [r0]
	ldr.w r9, [r0, #0x38]
	b.n .L0801375e
.L0801378c:
	ldr r0, [sp, #0xa0]
	muls r0, r4, r0
	add.w r2, r11, r0, asr #8
	ldr r0, [sp, #0xa4]
	muls r0, r4, r0
	add.w r1, r10, r0, asr #8
	asrs r0, r2, #8
	asr.w lr, r1, #8
	bmi.n .L080138a0
	ldr r3, [sp, #0x68]
	cmp r0, r3
	bge.n .L080138a0
	cmp.w lr, #0
	blt.n .L080138a0
	cmp lr, r6
	bge.n .L080138a0
	uxtb r2, r2
	uxtb r3, r1
	cmp r2, #0x80
	bge.n .L080137c8
	rsb.w r2, r2, #0x7f
	mov.w r1, #-1
	lsls r2, r2, #1
	b.n .L080137d0
.L080137c8:
	movs r1, #1
	lsls r2, r2, #1
	sub.w r2, r2, #0x100
.L080137d0:
	str r2, [sp, #0x24]
	cmp r3, #0x80
	bge.n .L080137e2
	rsb.w r3, r3, #0x7f
	mov.w r2, #-1
	lsls r3, r3, #1
	b.n .L080137ea
.L080137e2:
	movs r2, #1
	lsls r3, r3, #1
	sub.w r3, r3, #0x100
.L080137ea:
	str r3, [sp, #0x28]
	mla ip, lr, r8, r0
	ldr r3, [sp, #0x64]
	mla r3, ip, r5, r3
	str r3, [sp, #0x1c]
	adds r3, r0, r1
	str r3, [sp, #0x44]
	bmi.n .L080138e4
	ldr.w ip, [sp, #0x34]
	cmp r3, ip
	bgt.n .L080138e4
	adds.w r3, lr, r2
	bmi.n .L080138e4
	ldr.w ip, [sp, #0x18]
	cmp r3, ip
	bgt.n .L080138e4
	ldr.w ip, [sp, #0x1c]
	smlabb r1, r1, r5, ip
	strd ip, r1, [sp, #0x54]
	smulbb r1, r2, r8
	mla r1, r1, r5, ip
	str r1, [sp, #0x30]
	cbz r7, .L080138a2
	ldr r1, [sp, #0xb4]
	cmp r1, #5
	beq.n .L0801383e
	cmp r1, #0x14
	beq.n .L0801384e
	cmp r1, #6
	beq.n .L080138e6
	b.n .L0801390a
.L0801383c:
	b.n .L08013a1e
.L0801383e:
	ldr r0, [sp, #0x54]
	ldrb r0, [r0, #2]
	str r0, [sp, #0x1c]
	ldr r0, [sp, #0x30]
	ldrb r1, [r0, #2]
	ldr r0, [sp, #0x58]
	ldrb r0, [r0, #2]
	b.n .L08013870
.L0801384e:
	ldr r2, [sp, #0x64]
	ldr r1, [sp, #0x38]
	mul ip, lr, r8
	add.w r1, r2, r1, lsl #1
	adds r2, r1, r0
	mla r1, lr, r8, r1
	ldrb.w r0, [ip, r2]
	str r0, [sp, #0x1c]
	ldr r0, [sp, #0x44]
	mul r3, r3, r8
	ldrb r0, [r1, r0]
	ldrb r1, [r3, r2]
.L08013870:
	ldr r2, [sp, #0x1c]
	cmp r1, r2
	beq.n .L0801388c
	ldr r2, [sp, #0x28]
	smulbb r2, r1, r2
	ldr r1, [sp, #0x28]
	rsb.w r3, r1, #0x100
	ldr r1, [sp, #0x1c]
	smlabb r1, r1, r3, r2
	ubfx r1, r1, #8, #8
.L0801388c:
	ldr r2, [sp, #0x1c]
	cmp r0, r2
	beq.n .L080138ae
	ldr r2, [sp, #0x24]
	smulbb r2, r0, r2
	ldr r0, [sp, #0x24]
	rsb.w r3, r0, #0x100
	b.n .L080138a4
.L080138a0:
	b.n .L08013902
.L080138a2:
	b.n .L08013910
.L080138a4:
	ldr r0, [sp, #0x1c]
	smlabb r0, r0, r3, r2
	ubfx r0, r0, #8, #8
.L080138ae:
	add r0, r1
	ldr r1, [sp, #0xb0]
	lsrs r0, r0, #1
	strb r0, [r1, r4]
	beq.n .L08013908
	ldr r0, [sp, #0x54]
	ldrb r1, [r0]
	ldrb r0, [r0, #1]
	add.w r0, r1, r0, lsl #8
	strh.w r0, [sp, #0xc]
	ldr r0, [sp, #0x30]
	ldrb r1, [r0]
	ldrb r0, [r0, #1]
	add.w r0, r1, r0, lsl #8
	strh.w r0, [sp, #0x10]
	ldr r0, [sp, #0x58]
	ldrb r1, [r0]
	ldrb r0, [r0, #1]
	add.w r0, r1, r0, lsl #8
	strh.w r0, [sp, #8]
	b.n .L0801392c
.L080138e4:
	b.n .L08013980
.L080138e6:
	ldr r0, [sp, #0x54]
	ldrh r1, [r0]
	uxth.w r0, r9
	cmp r1, r0
	beq.n .L08013902
	ldr r1, [sp, #0x30]
	ldrh r1, [r1]
	cmp r1, r0
	beq.n .L08013902
	ldr r1, [sp, #0x58]
	ldrh r1, [r1]
	cmp r1, r0
	bne.n .L0801390a
.L08013902:
	ldr r1, [sp, #0xb0]
	movs r0, #0
	strb r0, [r1, r4]
.L08013908:
	b.n .L08013a12
.L0801390a:
	movs r1, #0xff
	mov r0, r1
	b.n .L080138ae
.L08013910:
	ldr r0, [sp, #0x54]
	ldrh r0, [r0]
	strh.w r0, [sp, #0xc]
	ldr r0, [sp, #0x58]
	ldrh r0, [r0]
	strh.w r0, [sp, #8]
	ldrh r0, [r1]
	strh.w r0, [sp, #0x10]
	ldr r0, [sp, #0xb0]
	movs r1, #0xff
	strb r1, [r0, r4]
.L0801392c:
	ldrh.w r0, [sp, #0xc]
	ldrh.w r1, [sp, #0x10]
	cmp r0, r1
	bne.n .L0801394c
	ldrh.w r1, [sp, #8]
	cmp r0, r1
	bne.n .L0801394c
	ldr r0, [sp, #0xac]
	ldrh.w r1, [sp, #0xc]
	add.w r0, r0, r4, lsl #1
	b.n .L0801397c
.L0801394c:
	ldr r0, [sp, #0x28]
	uxtb r2, r0
	ldrd r1, r0, [sp, #0xc]
	bl blend_565_0801da10
	str r0, [sp, #0x10]
	ldr r0, [sp, #0x24]
	uxtb r2, r0
	ldrd r0, r1, [sp, #8]
	bl blend_565_0801da10
	movs r2, #0x7f
	str r0, [sp, #8]
	ldr r1, [sp, #0x10]
	bl blend_565_0801da10
	str r0, [sp]
	ldr r0, [sp, #0xac]
	ldrh.w r1, [sp]
	add.w r0, r0, r4, lsl #1
.L0801397c:
	strh r1, [r0]
	b.n .L08013a12
.L08013980:
	ldr r3, [sp, #0x1c]
	ldrb.w ip, [r3]
	ldrb r3, [r3, #1]
	add.w r3, ip, r3, lsl #8
	ldr.w ip, [sp, #0xac]
	uxth r3, r3
	strh.w r3, [ip, r4, lsl #1]
	ldr.w ip, [sp, #0xb4]
	cmp.w ip, #5
	beq.n .L080139ae
	cmp.w ip, #6
	beq.n .L080139b4
	cmp.w ip, #0x14
	bne.n .L080139c0
	b.n .L080139c4
.L080139ae:
	ldr r3, [sp, #0x1c]
	ldrb r3, [r3, #2]
	b.n .L080139d4
.L080139b4:
	uxth.w ip, r9
	cmp r3, ip
	bne.n .L080139c0
	movs r3, #0
	b.n .L080139d4
.L080139c0:
	movs r3, #0xff
	b.n .L080139d4
.L080139c4:
	ldr r3, [sp, #0x64]
	mla ip, lr, r8, r3
	ldr r3, [sp, #0x38]
	add.w r3, r0, r3, lsl #1
	ldrb.w r3, [ip, r3]
.L080139d4:
	cbnz r0, .L080139da
	cmp r1, #0
	blt.n .L080139e6
.L080139da:
	ldr.w ip, [sp, #0x34]
	cmp r0, ip
	bne.n .L080139ea
	cmp r1, #0
	ble.n .L080139ea
.L080139e6:
	ldr r0, [sp, #0x24]
	b.n .L08013a00
.L080139ea:
	cmp.w lr, #0
	bne.n .L080139f4
	cmp r2, #0
	blt.n .L080139fe
.L080139f4:
	ldr r1, [sp, #0x18]
	cmp lr, r1
	bne.n .L08013a0c
	cmp r2, #0
	ble.n .L08013a0c
.L080139fe:
	ldr r0, [sp, #0x28]
.L08013a00:
	rsb.w r0, r0, #0xff
	smulbb r0, r0, r3
	lsrs r1, r0, #8
	b.n .L08013a0e
.L08013a0c:
	movs r1, #0
.L08013a0e:
	ldr r0, [sp, #0xb0]
	strb r1, [r0, r4]
.L08013a12:
	.inst.n 0x1c64  @ adds r4, r4, #1
	sxth r4, r4
.L08013a16:
	ldr r0, [sp, #0xa8]
	cmp r4, r0
	blt.w .L0801378c
.L08013a1e:
	add sp, #0x74
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}

@ ----------------------------------------------------------------------------
@ fn_08013a24 - r0:r1 = 64-bit value passed in d0; returns r0:r1 = d0 after
@ the call. Moves r0:r1 into d0, calls atan_f64, moves d0 back to r0:r1 and
@ returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013a24,"ax",%progbits
	.p2align 2
	.global fn_08013a24
	.thumb_func
	.type fn_08013a24, %function
fn_08013a24:
	push {r4, lr}
	vmov d0, r0, r1
	bl atan_f64
	vmov r0, r1, d0
	pop {r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08013a34 - r0 = block pointer, r1 = following block pointer; returns r0.
@ Loops forever (branch to itself) when the word at r0+4 shifted right by 2 is
@ 0. Adds (word at r1+4 & ~3) + 4 to the word at r0+4, calls
@ set_following_block_link with r0 and returns r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013a34,"ax",%progbits
	.global fn_08013a34
	.thumb_func
	.type fn_08013a34, %function
fn_08013a34:
	push {r4, lr}
	mov r4, r0
	ldr r0, [r0, #4]
	lsrs r2, r0, #2
	beq.n .L08013a54
	ldr r1, [r1, #4]
	bic.w r1, r1, #3
	.inst.n 0x1d09  @ adds r1, r1, #4
	add r0, r1
	str r0, [r4, #4]
	mov r0, r4
	bl set_following_block_link
	mov r0, r4
	pop {r4, pc}
.L08013a54:
	b.n .L08013a54

@ ----------------------------------------------------------------------------
@ fn_08013a56 - r0 = block pointer, r1 = size; returns 1 or 0.
@ Returns 0 when (word at r0+4 & ~3) is below r1 + 0x10, otherwise 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013a56,"ax",%progbits
	.global fn_08013a56
	.thumb_func
	.type fn_08013a56, %function
fn_08013a56:
	ldr r0, [r0, #4]
	adds r1, #0x10
	bic.w r0, r0, #3
	cmp r0, r1
	bcc.n .L08013a66
	movs r0, #1
	bx lr
.L08013a66:
	movs r0, #0
	bx lr

@ ----------------------------------------------------------------------------
@ fn_08013a6a - r0 = pool pointer, r1 = block pointer; r2 and r3 are not
@ inputs (their stack slots hold the two indices); no return value.
@ Calls fn_0802891c with (word at r1+4 & ~3) and the addresses sp and sp+4 to
@ get two indices (a, b). Slot address is r0 + a * 0x80 + b * 4 with the old
@ list head at +0x3c; loops forever when the head is 0 or r1 is 0.
@ Links the block: word at r1+8 = old head, word at r1+0xc = r0, word at
@ head+0xc = r1; checks with align_up_pow2 (r1+8, 4) that r1+8 is aligned
@ (loops forever otherwise); stores r1 as the new head, sets bit a in the word
@ at r0+0x10 and bit b in the word at r0 + a * 4 + 0x14.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013a6a,"ax",%progbits
	.global fn_08013a6a
	.thumb_func
	.type fn_08013a6a, %function
fn_08013a6a:
	push.w {r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	mov r5, r0
	ldr r0, [r1, #4]
	mov r4, r1
	bic.w r0, r0, #3
	add r2, sp, #4
	mov r1, sp
	bl fn_0802891c
	ldrd r7, r0, [sp]
	add.w r1, r5, r7, lsl #7
	add.w r9, r1, r0, lsl #2
	mov r8, r0
	ldr.w r0, [r9, #0x3c]
	cbz r0, .L08013aae
	cbz r4, .L08013ab0
	strd r0, r5, [r4, #8]
	add.w r6, r4, #8
	str r4, [r0, #0xc]
	mov r0, r6
	movs r1, #4
	bl align_up_pow2
	cmp r6, r0
	beq.n .L08013ab2
.L08013aac:
	b.n .L08013aac
.L08013aae:
	b.n .L08013aae
.L08013ab0:
	b.n .L08013ab0
.L08013ab2:
	str.w r4, [r9, #0x3c]
	movs r0, #1
	ldr r1, [r5, #0x10]
	lsl.w r2, r0, r7
	orrs r1, r2
	str r1, [r5, #0x10]
	add.w r1, r5, r7, lsl #2
	lsl.w r0, r0, r8
	ldr r2, [r1, #0x14]
	orrs r2, r0
	str r2, [r1, #0x14]
	pop.w {r2, r3, r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ set_following_block_link - r0 = block pointer; returns r0 = the address of
@ the following block header computed by next_block_header.
@ Calls next_block_header with r0 to get the address of the following block
@ header and stores r0 (the block pointer) in the word at offset 0 of it.
@ ----------------------------------------------------------------------------
	.section .text.set_following_block_link,"ax",%progbits
	.p2align 2
	.global set_following_block_link
	.thumb_func
	.type set_following_block_link, %function
set_following_block_link:
	push {r4, lr}
	mov r4, r0
	bl next_block_header
	str r4, [r0]
	pop {r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08013ae0 - r0 = pool pointer, r1 = requested size; returns a block
@ pointer or 0.
@ Returns 0 when r1 is 0; for sizes above 0x7f it adds (1 << (index - 5)) - 1
@ with the index from highest_set_bit_index to round up.
@ Calls fn_0802891c to get the size class indices (word at sp, word at sp+4)
@ and returns 0 when the first index is 10 or more.
@ Looks in the bitmap words at r0 + index * 4 + 0x14 for a free slot at or
@ above the second index; if none, checks the word at r0+0x10 for a higher
@ class (returns 0 when none), finds it with lowest_set_bit_index and loops
@ forever when that class list is empty.
@ Takes the head block at r0 + class * 0x80 + slot * 4 + 0x3c; loops forever
@ when its size (word at +4 & ~3) is below r1; unlinks it with fn_080291f4 and
@ returns it.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013ae0,"ax",%progbits
	.p2align 2
	.global fn_08013ae0
	.thumb_func
	.type fn_08013ae0, %function
fn_08013ae0:
	push.w {r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	mov r6, r0
	mov.w r0, #0
	movs r5, r1
	str r0, [sp]
	mov r7, r0
	str r0, [sp, #4]
	beq.n .L08013b7a
	mov r4, r1
	mov r9, sp
	add.w r8, sp, #4
	cmp r1, #0x80
	blo.n .L08013b10
	mov r0, r1
	bl highest_set_bit_index
	subs r1, r0, #5
	movs r0, #1
	lsls r0, r1
	.inst.n 0x1e40  @ subs r0, r0, #1
	add r4, r0
.L08013b10:
	mov r2, r8
	mov r1, r9
	mov r0, r4
	bl fn_0802891c
	ldr r4, [sp]
	cmp r4, #0xa
	bge.n .L08013b7a
	add.w r0, r6, r4, lsl #2
	ldr r2, [sp, #4]
	ldr r0, [r0, #0x14]
	mov.w r1, #-1
	lsl.w r2, r1, r2
	ands r0, r2
	bne.n .L08013b4e
	.inst.n 0x1c64  @ adds r4, r4, #1
	ldr r0, [r6, #0x10]
	lsls r1, r4
	ands r0, r1
	beq.n .L08013b7a
	bl lowest_set_bit_index
	mov r4, r0
	str r0, [sp]
	add.w r0, r6, r0, lsl #2
	ldr r0, [r0, #0x14]
	cbz r0, .L08013b6e
.L08013b4e:
	bl lowest_set_bit_index
	mov r3, r0
	add.w r1, r6, r4, lsl #7
	str r0, [sp, #4]
	add.w r0, r1, r0, lsl #2
	ldr r7, [r0, #0x3c]
	cbz r7, .L08013b7a
	ldr r0, [r7, #4]
	bic.w r0, r0, #3
	cmp r0, r5
	bhs.n .L08013b70
.L08013b6c:
	b.n .L08013b6c
.L08013b6e:
	b.n .L08013b6e
.L08013b70:
	mov r1, r7
	mov r0, r6
	ldr r2, [sp]
	bl fn_080291f4
.L08013b7a:
	mov r0, r7
	pop.w {r2, r3, r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ set_block_and_next_flags - r0 = block pointer; no return value.
@ Calls set_following_block_link with r0 (which returns the following block),
@ sets bit 1 in the word at +4 of the returned block and sets bit 0 in the
@ word at r0+4.
@ ----------------------------------------------------------------------------
	.section .text.set_block_and_next_flags,"ax",%progbits
	.global set_block_and_next_flags
	.thumb_func
	.type set_block_and_next_flags, %function
set_block_and_next_flags:
	push {r4, lr}
	mov r4, r0
	bl set_following_block_link
	ldr r1, [r0, #4]
	orr.w r1, r1, #2
	str r1, [r0, #4]
	ldr r0, [r4, #4]
	orr.w r0, r0, #1
	str r0, [r4, #4]
	pop {r4, pc}

@ ----------------------------------------------------------------------------
@ clear_block_and_next_flags - r0 = block pointer; no return value.
@ Calls next_block_header with r0 to get the following block, clears bit 1 in
@ the word at +4 of it and clears bit 0 in the word at r0+4.
@ ----------------------------------------------------------------------------
	.section .text.clear_block_and_next_flags,"ax",%progbits
	.global clear_block_and_next_flags
	.thumb_func
	.type clear_block_and_next_flags, %function
clear_block_and_next_flags:
	push {r4, lr}
	mov r4, r0
	bl next_block_header
	ldr r1, [r0, #4]
	bic.w r1, r1, #2
	str r1, [r0, #4]
	ldr r0, [r4, #4]
	bic.w r0, r0, #1
	str r0, [r4, #4]
	pop {r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08013bb4 - r0 = pool pointer, r1 = block pointer; returns the block
@ pointer.
@ Gets the following block with next_block_header (loops forever when it is
@ 0); when bit 0 of the byte at +4 of the following block is set it loops
@ forever if the word at r1+4 >> 2 is 0, calls fn_08013c50 with (r0, following
@ block) to unlink it and merges it into r1 with fn_08013a34.
@ Returns r1 (merged block or unchanged).
@ ----------------------------------------------------------------------------
	.section .text.fn_08013bb4,"ax",%progbits
	.global fn_08013bb4
	.thumb_func
	.type fn_08013bb4, %function
fn_08013bb4:
	push {r4, r5, r6, lr}
	mov r6, r0
	mov r5, r1
	mov r0, r1
	bl next_block_header
	movs r4, r0
	beq.n .L08013be6
	ldrb r0, [r4, #4]
	lsls r0, r0, #0x1f
	beq.n .L08013be2
	ldr r0, [r5, #4]
	lsrs r0, r0, #2
	beq.n .L08013be8
	mov r1, r4
	mov r0, r6
	bl fn_08013c50
	mov r1, r4
	mov r0, r5
	bl fn_08013a34
	mov r5, r0
.L08013be2:
	mov r0, r5
	pop {r4, r5, r6, pc}
.L08013be6:
	b.n .L08013be6
.L08013be8:
	b.n .L08013be8

@ ----------------------------------------------------------------------------
@ next_block_header - r0 = block pointer; returns the address (word at r0+4 &
@ ~3) + r0 + 4. Loops forever (branch to itself) when the word at r0+4
@ shifted right by 2 is 0.
@ ----------------------------------------------------------------------------
	.section .text.next_block_header,"ax",%progbits
	.global next_block_header
	.thumb_func
	.type next_block_header, %function
next_block_header:
	ldr r2, [r0, #4]
	add.w r1, r0, #8
	bic.w r0, r2, #3
	.inst.n 0x1f00  @ subs r0, r0, #4
	add r0, r1
	lsrs r1, r2, #2
	bne.n .L08013bfe
.L08013bfc:
	b.n .L08013bfc
.L08013bfe:
	bx lr

@ ----------------------------------------------------------------------------
@ fn_08013c00 - r0 = control block (kept in r6), r1 = block pointer (kept in
@ r4), r2 = size (kept in r5); returns r4 + 8 (block pointer + 8), or 0 when
@ r1 is 0. Reached only by the b.w at 0x08027ab6.
@ r1 = 0: returns 0. r2 = 0: branches to itself (endless loop). Byte [r4+4]
@ bit 0 clear: branches to itself (endless loop).
@ r0 = fn_08013a56(r4, r5); when it is non-zero: r5 = fn_08013c72(r4, r5),
@ calls set_following_block_link(r4), word [r5+4] |= 2, calls
@ fn_08013a6a(r6, r5). In both cases then calls clear_block_and_next_flags(r4)
@ and returns r0 = r4 + 8.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013c00,"ax",%progbits
	.p2align 2
	.global fn_08013c00
	.thumb_func
	.type fn_08013c00, %function
fn_08013c00:
	push {r4, r5, r6, lr}
	mov r6, r0
	movs r4, r1
	mov.w r0, #0
	beq.n .L08013c4a
	cbz r2, .L08013c4c
	ldrb r0, [r4, #4]
	mov r5, r2
	lsls r0, r0, #0x1f
	beq.n .L08013c4e
	mov r1, r2
	mov r0, r4
	bl fn_08013a56
	cbz r0, .L08013c40
	mov r1, r5
	mov r0, r4
	bl fn_08013c72
	mov r5, r0
	mov r0, r4
	bl set_following_block_link
	ldr r0, [r5, #4]
	mov r1, r5
	orr.w r0, r0, #2
	str r0, [r5, #4]
	mov r0, r6
	bl fn_08013a6a
.L08013c40:
	mov r0, r4
	bl clear_block_and_next_flags
	add.w r0, r4, #8
.L08013c4a:
	pop {r4, r5, r6, pc}
.L08013c4c:
	b.n .L08013c4c
.L08013c4e:
	b.n .L08013c4e

@ ----------------------------------------------------------------------------
@ fn_08013c50 - r0 = pool pointer, r1 = block pointer; no return value.
@ Calls fn_0802891c with (word at r1+4 & ~3) and two stack slots to get the
@ class indices, then calls fn_080291f4 with (r0, r1, first index, second
@ index).
@ ----------------------------------------------------------------------------
	.section .text.fn_08013c50,"ax",%progbits
	.global fn_08013c50
	.thumb_func
	.type fn_08013c50, %function
fn_08013c50:
	push {r2, r3, r4, r5, r6, lr}
	mov r5, r0
	ldr r0, [r1, #4]
	mov r4, r1
	bic.w r0, r0, #3
	add r2, sp, #4
	mov r1, sp
	bl fn_0802891c
	ldrd r2, r3, [sp]
	mov r1, r4
	mov r0, r5
	bl fn_080291f4
	pop {r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08013c72 - r0 = block pointer, r1 = size to keep; returns the new block
@ pointer.
@ New block address is r0 + r1 + 4; remaining size is (word at r0+4 & ~3) - r1
@ - 4. Loops forever when the address plus 8 is not aligned by align_up_pow2
@ (..., 4) or when the sizes do not add up. Stores (low 2 bits of the byte at
@ +4 of the new block) | remaining size in the new block; loops forever when
@ remaining & ~3 is below 0xc; stores (low 2 bits of the byte at +4 of the old
@ block) | r1 in the word at r0+4, calls set_block_and_next_flags with the new
@ block and returns it.
@ ----------------------------------------------------------------------------
	.section .text.fn_08013c72,"ax",%progbits
	.global fn_08013c72
	.thumb_func
	.type fn_08013c72, %function
fn_08013c72:
	push.w {r4, r5, r6, r7, r8, lr}
	mov r5, r1
	mov r4, r0
	add.w r1, r0, #8
	subs r0, r5, #4
	adds r6, r1, r0
	ldr r0, [r4, #4]
	add.w r7, r6, #8
	bic.w r0, r0, #3
	subs r0, r0, r5
	sub.w r8, r0, #4
	mov r0, r7
	movs r1, #4
	bl align_up_pow2
	cmp r7, r0
	beq.n .L08013ca0
.L08013c9e:
	b.n .L08013c9e
.L08013ca0:
	ldr r0, [r4, #4]
	bic.w r1, r0, #3
	add.w r0, r8, r5
	.inst.n 0x1d00  @ adds r0, r0, #4
	cmp r1, r0
	beq.n .L08013cb2
.L08013cb0:
	b.n .L08013cb0
.L08013cb2:
	ldrb r0, [r6, #4]
	and.w r0, r0, #3
	orr.w r0, r0, r8
	str r0, [r6, #4]
	bic.w r0, r0, #3
	cmp r0, #0xc
	bhs.n .L08013cc8
.L08013cc6:
	b.n .L08013cc6
.L08013cc8:
	ldrb r0, [r4, #4]
	and.w r0, r0, #3
	orrs r0, r5
	str r0, [r4, #4]
	mov r0, r6
	bl set_block_and_next_flags
	mov r0, r6
	pop.w {r4, r5, r6, r7, r8, pc}
	.short 0x0000  @ padding

@ ----------------------------------------------------------------------------
@ fn_08020894 - r0 = font object, r1 = character code; returns an address or 0.
@ Maps code 9 to 0x20, looks up the index with fn_0801b174, returns 0 when it
@ is 0 or the top two bits of the halfword at +0x12 of the data (word at
@ object+0x10) are set, else (word at table(+4) + index * 8 & 0xfffff) + the
@ word at data+0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020894,"ax",%progbits
	.global fn_08020894
	.thumb_func
	.type fn_08020894, %function
fn_08020894:
	push {r4, lr}
	cmp r1, #9
	bne.n .L0802089c
	movs r1, #0x20
.L0802089c:
	ldr r4, [r0, #0x10]
	bl fn_0801b174
	cmp r0, #0
	beq.n .L080208b4
	ldr r1, [r4, #4]
	add.w r0, r1, r0, lsl #3
	ldrh r1, [r4, #0x12]
	lsrs r1, r1, #0xe
	beq.n .L080208b6
	movs r0, #0
.L080208b4:
	pop {r4, pc}
.L080208b6:
	ldr r0, [r0]
	ldr r1, [r4]
	ubfx r0, r0, #0, #0x14
	add r0, r1
	pop {r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080208c2 - r0 = object; tail-calls the function pointer at r0+4 (bx r2).
@ No return value of its own.
@ ----------------------------------------------------------------------------
	.section .text.fn_080208c2,"ax",%progbits
	.global fn_080208c2
	.thumb_func
	.type fn_080208c2, %function
fn_080208c2:
	ldr r2, [r0, #4]
	bx r2

@ ----------------------------------------------------------------------------
@ fn_080208c6 - r0 = list head of nodes (next pointer at +0x14, function
@ pointer at +0), r1 = info record, r2 = character code, r3 = argument;
@ returns 1 when a node accepted, else 0.
@ Clears *r1, calls each node function (node, info, code, arg) until one
@ returns nonzero; stores that node in *info and returns 1 unless bit 4 of
@ byte +0xe of the info is set, in which case the first such node is kept as
@ fallback and the walk continues.
@ End of list without fallback: for code below 0x20 or 0xf8ff or 0x200c sets
@ short +6 = 0 and short +4 = 2, else short +6 = half of the halfword at
@ head+8 (rounded toward zero) and short +4 = that + 2; writes short +8 =
@ halfword at head+8, shorts +10 and +12 = 0, byte +0xe = ((old & 0xf0) + 1) |
@ 0x10, *info = 0; returns 0.
@ With fallback calls it and stores it in *info, returns 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_080208c6,"ax",%progbits
	.global fn_080208c6
	.thumb_func
	.type fn_080208c6, %function
fn_080208c6:
	push.w {r4, r5, r6, r7, r8, r9, r10, lr}
	movs r6, #0
	mov r10, r3
	mov r8, r2
	mov r4, r1
	mov r7, r0
	mov r5, r0
	mov r9, r6
	str r6, [r1]
	b.n .L080208fc
.L080208dc:
	ldr.w ip, [r5]
	mov r3, r10
	mov r2, r8
	mov r1, r4
	mov r0, r5
	blx ip
	cbz r0, .L080208fa
	ldrb r0, [r4, #0xe]
	lsls r0, r0, #0x1b
	bmi.n .L080208f6
	str r5, [r4]
	b.n .L08020910
.L080208f6:
	cbnz r6, .L080208fa
	mov r6, r5
.L080208fa:
	ldr r5, [r5, #0x14]
.L080208fc:
	cmp r5, #0
	bne.n .L080208dc
	cbz r6, .L08020916
	ldr r5, [r6]
	mov r3, r10
	mov r2, r8
	mov r1, r4
	mov r0, r6
	blx r5
	str r6, [r4]
.L08020910:
	movs r0, #1
.L08020912:
	pop.w {r4, r5, r6, r7, r8, r9, r10, pc}
.L08020916:
	cmp.w r8, #0x20
	blo.n .L0802095e
	sub.w r1, r8, #0xf800
	subs r1, #0xff
	beq.n .L0802095e
	sub.w r1, r8, #0x2000
	subs r1, #0xc
	beq.n .L0802095e
	ldrsh.w r0, [r7, #8]
	add.w r0, r0, r0, lsr #31
	lsrs r0, r0, #1
	strh r0, [r4, #6]
	.inst.n 0x1c80  @ adds r0, r0, #2
.L0802093a:
	strh r0, [r4, #4]
	str.w r9, [r4]
	ldrh r1, [r7, #8]
	strh r1, [r4, #8]
	strh.w r9, [r4, #0xa]
	strh.w r9, [r4, #0xc]
	ldrb r0, [r4, #0xe]
	bic.w r0, r0, #0xf
	.inst.n 0x1c40  @ adds r0, r0, #1
	orr.w r0, r0, #0x10
	strb r0, [r4, #0xe]
	movs r0, #0
	b.n .L08020912
.L0802095e:
	mov r0, r9
	strh.w r9, [r4, #6]
	b.n .L0802093a
	.short 0x0000  @ padding

@ ----------------------------------------------------------------------------
@ fn_08020968 - r0 = font object, r1 = info record, r2 = code, r3 = second
@ code; returns 1 on success else 0.
@ Maps code 9 to 0x20 (flag doubles width), index = fn_0801b174(object, code),
@ returns 0 when 0. When the word at +0xc of the data (word at object+0x10) is
@ set and fn_0801b174(object, second code) is nonzero gets a kerning value from
@ fn_0801b2e8(object, index, second index).
@ Reads the 8-byte table entry at word(data+4) + index * 8 and fills shorts at
@ info+0x4 (advance = ((entry word >> 20, doubled for code 9) + ((halfword at
@ data+0x10 * kern) >> 4) + 8) >> 4), +0x8 (byte entry+5), +0x6 (byte entry+4,
@ doubled for code 9), +0xa (signed byte entry+6) and +0xc (signed byte
@ entry+7); sets the low 4 bits of byte +0xe from the halfword at data+0x12 >>
@ 9 and clears bit 4 of byte +0xe.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020968,"ax",%progbits
	.global fn_08020968
	.thumb_func
	.type fn_08020968, %function
fn_08020968:
	push.w {r4, r5, r6, r7, r8, r9, r10, lr}
	movs r6, #0
	mov r10, r3
	mov r4, r1
	mov r9, r0
	cmp r2, #9
	bne.n .L0802097c
	movs r2, #0x20
	movs r6, #1
.L0802097c:
	mov r1, r2
	ldr.w r5, [r9, #0x10]
	bl fn_0801b174
	subs r7, r0, #0
	beq.n .L08020a06
	ldr r0, [r5, #0xc]
	mov.w r8, #0
	cbz r0, .L080209a8
	mov r1, r10
	mov r0, r9
	bl fn_0801b174
	movs r2, r0
	beq.n .L080209a8
	mov r1, r7
	mov r0, r9
	bl fn_0801b2e8
	mov r8, r0
.L080209a8:
	ldr r0, [r5, #4]
	ldrh r1, [r5, #0x10]
	add.w r0, r0, r7, lsl #3
	mul r1, r1, r8
	asrs r2, r1, #4
	ldr r1, [r0]
	lsrs r1, r1, #0x14
	cmp r6, #0
	beq.n .L080209c4
	nop
	lsl.w r1, r1, #1
.L080209c4:
	add r1, r2
	add.w r1, r1, #8
	lsr.w r1, r1, #4
	strh r1, [r4, #4]
	ldrb r1, [r0, #5]
	strh r1, [r4, #8]
	ldrb r1, [r0, #4]
	strh r1, [r4, #6]
	ldrsb.w r2, [r0, #6]
	strh r2, [r4, #0xa]
	ldrsb.w r0, [r0, #7]
	strh r0, [r4, #0xc]
	ldrh r0, [r5, #0x12]
	lsr.w r2, r0, #9
	ldrb r0, [r4, #0xe]
	bfi r0, r2, #0, #4
	bic.w r0, r0, #0x10
	strb r0, [r4, #0xe]
	beq.n .L08020a02
	movw r0, #0xffff
	and.w r0, r0, r1, lsl #1
	strh r0, [r4, #6]
.L08020a02:
	mov.w r0, #1
.L08020a06:
	pop.w {r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ fn_08020a0a - r0 = list head, r1 = code, r2 = argument (r3 is not used);
@ returns the low 16 bits of the word stored at +4 of the info record.
@ Builds a 4-word info record on the stack, calls fn_080208c6(list head,
@ record, code, argument), returns record[1] & 0xffff.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020a0a,"ax",%progbits
	.global fn_08020a0a
	.thumb_func
	.type fn_08020a0a, %function
fn_08020a0a:
	push {r0, r1, r2, r3, r4, lr}
	mov r3, r2
	mov r2, r1
	mov r1, sp
	bl fn_080208c6
	ldrh.w r0, [sp, #4]
	add sp, #0x10
	pop {r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08020a1e - r0 = 3-word handle; returns 0xb when handle[1] is 0, 9 when
@ the function pointer at +0xc of it is 0, else that function's result.
@ Calls (*(handle[1] + 0xc))(handle[1], handle[0]). When the short at
@ handle[1]+2 is nonzero and handle[2] is nonzero frees (fn_08022c68) the
@ buffer at +0xc of handle[2] when set and handle[2] itself. Clears all three
@ words.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020a1e,"ax",%progbits
	.global fn_08020a1e
	.thumb_func
	.type fn_08020a1e, %function
fn_08020a1e:
	push {r4, r5, r6, lr}
	mov r4, r0
	ldr r0, [r0, #4]
	cbz r0, .L08020a54
	ldr r2, [r0, #0xc]
	cbz r2, .L08020a58
	ldr r1, [r4]
	blx r2
	mov r5, r0
	ldr r0, [r4, #4]
	ldrh r0, [r0, #2]
	cbz r0, .L08020a48
	ldr r0, [r4, #8]
	cbz r0, .L08020a48
	ldr r0, [r0, #0xc]
	cbz r0, .L08020a42
	bl fn_08022c68
.L08020a42:
	ldr r0, [r4, #8]
	bl fn_08022c68
.L08020a48:
	movs r0, #0
	str r0, [r4]
	str r0, [r4, #4]
	str r0, [r4, #8]
	mov r0, r5
	pop {r4, r5, r6, pc}
.L08020a54:
	movs r0, #0xb
	pop {r4, r5, r6, pc}
.L08020a58:
	movs r0, #9
	pop {r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08020a5c - r0 = byte value; returns the node pointer whose first byte
@ equals it, or 0.
@ Walks the list at 0x20008074 with get_word_4_or_zero and
@ read_word_at_base_plus_offset_4 and compares the byte at the node's first
@ word with r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020a5c,"ax",%progbits
	.p2align 2
	.global fn_08020a5c
	.thumb_func
	.type fn_08020a5c, %function
fn_08020a5c:
	push {r4, lr}
	mov r4, r0
	ldr r0, .L08020a80
	bl get_word_4_or_zero
	b.n .L08020a7a
.L08020a68:
	ldr r0, [r1]
	ldrb r0, [r0]
	cmp r0, r4
	bne.n .L08020a74
	ldr r0, [r1]
	pop {r4, pc}
.L08020a74:
	ldr r0, .L08020a80
	bl read_word_at_base_plus_offset_4
.L08020a7a:
	movs r1, r0
	bne.n .L08020a68
	pop {r4, pc}
.L08020a80:
	.word 0x20008074

@ ----------------------------------------------------------------------------
@ fn_08020a84 - r0 = path string; returns a pointer to the extension.
@ Calls string_length for the length and scans backwards from index length
@ down to 1: at '.' returns r0+index+1; at '/' or '\' or when the length is 0
@ or the scan reaches index 0 returns the address 0x08020aac (adr at
@ 0x08020aa0; the byte at 0x08020aac is 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_08020a84,"ax",%progbits
	.p2align 2
	.global fn_08020a84
	.thumb_func
	.type fn_08020a84, %function
fn_08020a84:
	push {r4, lr}
	mov r4, r0
	bl string_length
	cbz r0, .L08020aa0
.L08020a8e:
	ldrb r1, [r4, r0]
	cmp r1, #0x2e
	beq.n .L08020aa4
	cmp r1, #0x2f
	beq.n .L08020aa0
	cmp r1, #0x5c
	beq.n .L08020aa0
	.inst.n 0x1e40  @ subs r0, r0, #1
	bne.n .L08020a8e
.L08020aa0:
	adr r0, .L08020aac
	pop {r4, pc}
.L08020aa4:
	add r0, r4
	.inst.n 0x1c40  @ adds r0, r0, #1
	pop {r4, pc}
	.short 0x0000  @ zero bytes before the empty string
.L08020aac:
	.word 0x00000000  @ four zero bytes; the first is the empty string

@ ----------------------------------------------------------------------------
@ skip_one_char_and_colon - r0 = string; returns r0+2 when the byte at r0+1 is
@ ':' else r0+1.
@ ----------------------------------------------------------------------------
	.section .text.skip_one_char_and_colon,"ax",%progbits
	.p2align 2
	.global skip_one_char_and_colon
	.thumb_func
	.type skip_one_char_and_colon, %function
skip_one_char_and_colon:
	ldrb.w r1, [r0, #1]!
	cmp r1, #0x3a
	bne.n .L08020aba
	.inst.n 0x1c40  @ adds r0, r0, #1
.L08020aba:
	bx lr

@ ----------------------------------------------------------------------------
@ fn_08020abc - r0 = 3-word handle output, r1 = path string, r2 = argument;
@ returns 0 on success, 0xb when the path is 0, 3 when no node has that first
@ byte (fn_08020a5c), 1 when the node check at +4 returns 0, 9 when slot +8 is
@ 0, 0xc when slot +8 returns 0 or -1.
@ Calls the slot +8 with (node, path after the drive prefix from
@ skip_one_char_and_colon, argument), stores the result in handle[0] and the
@ node in handle[1]; when the short at node+2 is nonzero allocates 0x10 bytes
@ (fn_08022b50), clears them (clear_bytes) and stores 0xffffffff at +0 and
@ 0xfffffffe at +4 of that block (handle[2]).
@ ----------------------------------------------------------------------------
	.section .text.fn_08020abc,"ax",%progbits
	.global fn_08020abc
	.thumb_func
	.type fn_08020abc, %function
fn_08020abc:
	push.w {r4, r5, r6, r7, r8, lr}
	mov r7, r2
	movs r6, r1
	mov r5, r0
	beq.n .L08020b1e
	ldrb r0, [r6]
	bl fn_08020a5c
	movs r4, r0
	beq.n .L08020b22
	ldr r1, [r4, #4]
	cbz r1, .L08020ada
	blx r1
	cbz r0, .L08020b26
.L08020ada:
	ldr r0, [r4, #8]
	cbz r0, .L08020b2a
	mov r0, r6
	bl skip_one_char_and_colon
	mov r1, r0
	ldr r3, [r4, #8]
	mov r2, r7
	mov r0, r4
	blx r3
	cbz r0, .L08020b2e
	adds r1, r0, #1
	beq.n .L08020b2e
	strd r0, r4, [r5]
	ldrh r0, [r4, #2]
	cbz r0, .L08020b18
	movs r0, #0x10
	bl fn_08022b50
	movs r1, #0x10
	str r0, [r5, #8]
	bl clear_bytes
	ldr r1, [r5, #8]
	mov.w r0, #-1
	str r0, [r1]
	ldr r1, [r5, #8]
	lsls r0, r0, #1
	str r0, [r1, #4]
.L08020b18:
	movs r0, #0
.L08020b1a:
	pop.w {r4, r5, r6, r7, r8, pc}
.L08020b1e:
	movs r0, #0xb
	b.n .L08020b1a
.L08020b22:
	movs r0, #3
	b.n .L08020b1a
.L08020b26:
	movs r0, #1
	b.n .L08020b1a
.L08020b2a:
	movs r0, #9
	b.n .L08020b1a
.L08020b2e:
	movs r0, #0xc
	b.n .L08020b1a

@ ----------------------------------------------------------------------------
@ fn_08020b32 - r0 = handle, r1 and r2 = arguments, r3 = optional result
@ pointer; returns a status.
@ Clears *r3 when given, returns 0xb when handle[1] is 0, 9 when slot +0x10 of
@ it is 0. Calls slot +0x10 (node, handle[0], r1, r2, &count) directly when the
@ short at node+2 is 0, else fn_08020b7a. Stores the count into *r3.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020b32,"ax",%progbits
	.global fn_08020b32
	.thumb_func
	.type fn_08020b32, %function
fn_08020b32:
	push {r2, r3, r4, r5, r6, lr}
	movs r4, r3
	mov.w r5, #0
	beq.n .L08020b3e
	str r5, [r4]
.L08020b3e:
	ldr r3, [r0, #4]
	cbz r3, .L08020b58
	ldr r3, [r3, #0x10]
	cbz r3, .L08020b5c
	str r5, [sp, #4]
	ldr r5, [r0, #4]
	ldrh r3, [r5, #2]
	cmp r3, #0
	add r3, sp, #4
	beq.n .L08020b60
	bl fn_08020b7a
	b.n .L08020b70
.L08020b58:
	movs r0, #0xb
	pop {r2, r3, r4, r5, r6, pc}
.L08020b5c:
	movs r0, #9
.L08020b5e:
	pop {r2, r3, r4, r5, r6, pc}
.L08020b60:
	str r3, [sp]
	ldr r0, [r0]
	mov r3, r2
	mov r2, r1
	mov r1, r0
	ldr r6, [r5, #0x10]
	mov r0, r5
	blx r6
.L08020b70:
	cmp r4, #0
	beq.n .L08020b5e
	ldr r1, [sp, #4]
	str r1, [r4]
	pop {r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08020b7a - r0 = handle (word 2 = cache record {start, end, position,
@ buffer}), r1 = destination, r2 = length, r3 = result pointer; returns a
@ status (0 on success).
@ Cached read: when the position lies outside [start, end) and the length
@ exceeds the cache size (short at node+2) reads directly through slot +0x10,
@ else allocates the cache buffer with fn_08022b50, reads a block through slot
@ +0x10, updates start and end and copies with copy_bytes_08022ce0.
@ Inside the cache copies with copy_bytes_08022ce0 and refills in the same way
@ when the request exceeds the cached remainder.
@ Adds *r3 to the position word at +8 of the cache record.
@ ----------------------------------------------------------------------------
	.section .text.fn_08020b7a,"ax",%progbits
	.global fn_08020b7a
	.thumb_func
	.type fn_08020b7a, %function
fn_08020b7a:
	push.w {r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	mov r5, r0
	ldr r0, [r0, #8]
	mov r4, r2
	mov r11, r1
	ldm.w r0, {r1, r2, r6}
	ldr.w r8, [r0, #0xc]
	ldr r0, [r5, #4]
	movs r7, #0
	mov r9, r3
	ldrh.w r10, [r0, #2]
	cmp r1, r6
	bhi.n .L08020c2c
	cmp r6, r2
	bhs.n .L08020c2c
	subs r0, r6, r1
	uxth r0, r0
	sub.w r1, r10, r0
	subs r6, r2, r6
	cmp r1, r6
	bhs.n .L08020bb0
	mov r6, r1
.L08020bb0:
	cmp r4, r6
	add.w r1, r8, r0
	bhi.n .L08020bc6
	mov r2, r4
	mov r0, r11
	bl copy_bytes_08022ce0
	str.w r4, [r9]
	b.n .L08020c8a
.L08020bc6:
	mov r2, r6
	mov r0, r11
	bl copy_bytes_08022ce0
	movs r0, #0
	str r0, [sp, #4]
	add r0, sp, #4
	cmp r4, r10
	str r0, [sp]
	bls.n .L08020bec
	ldrd r1, r0, [r5]
	subs r3, r4, r6
	ldr r7, [r0, #0x10]
	add.w r2, r11, r6
	blx r7
	mov r7, r0
	b.n .L08020c1c
.L08020bec:
	ldrd r1, r0, [r5]
	mov r3, r10
	ldr r7, [r0, #0x10]
	mov r2, r8
	blx r7
	mov r7, r0
	ldr r0, [r5, #8]
	ldr r2, [r0, #4]
	str r2, [r0]
	ldr r1, [r5, #8]
	ldr r0, [sp, #4]
	add r2, r0
	str r2, [r1, #4]
	subs r1, r4, r6
	cmp r1, r0
	bhs.n .L08020c10
	mov r0, r1
.L08020c10:
	uxth r2, r0
	add.w r0, r11, r6
	mov r1, r8
	bl copy_bytes_08022ce0
.L08020c1c:
	ldr r0, [sp, #4]
	add r0, r6
	cmp r0, r4
	bhs.n .L08020c26
	mov r4, r0
.L08020c26:
	str.w r4, [r9]
	b.n .L08020c88
.L08020c2c:
	cmp r4, r10
	bls.n .L08020c42
	str.w r9, [sp]
	ldr r6, [r0, #0x10]
	ldr r1, [r5]
	mov r3, r4
	mov r2, r11
	blx r6
	mov r7, r0
	b.n .L08020c88
.L08020c42:
	cmp.w r8, #0
	bne.n .L08020c54
	mov r0, r10
	bl fn_08022b50
	ldr r1, [r5, #8]
	mov r8, r0
	str r0, [r1, #0xc]
.L08020c54:
	movs r0, #0
	str r0, [sp, #4]
	add r0, sp, #4
	str r0, [sp]
	ldrd r1, r0, [r5]
	mov r3, r10
	ldr r7, [r0, #0x10]
	mov r2, r8
	blx r7
	mov r7, r0
	ldr r0, [r5, #8]
	str r6, [r0]
	ldr r2, [sp, #4]
	ldr r0, [r5, #8]
	adds r1, r6, r2
	cmp r4, r2
	str r1, [r0, #4]
	bhs.n .L08020c7c
	mov r2, r4
.L08020c7c:
	mov r1, r8
	mov r0, r11
	str.w r2, [r9]
	bl copy_bytes_08022ce0
.L08020c88:
	cbnz r7, .L08020c96
.L08020c8a:
	ldr r0, [r5, #8]
	ldr.w r1, [r9]
	ldr r2, [r0, #8]
	add r1, r2
	str r1, [r0, #8]
.L08020c96:
	mov r0, r7
	pop.w {r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}

@ ----------------------------------------------------------------------------
@ fn_08020c9c - r0 = handle, r1 = offset, r2 = origin (0, 1 or 2), r3 is not
@ used; returns a status (0xb when no node, 9 when slot +0x18 is 0).
@ Calls slot +0x18 (node, handle[0], offset, origin) directly when the short at
@ node+2 is 0. Else updates the position word +8 of the cache record by origin
@ 0 (absolute), 1 (relative) or 2 (slot +0x18 then slot +0x1c for the end) and
@ calls slot +0x18 (node, handle[0], position, 0) when the position leaves
@ [start, end].
@ ----------------------------------------------------------------------------
	.section .text.fn_08020c9c,"ax",%progbits
	.global fn_08020c9c
	.thumb_func
	.type fn_08020c9c, %function
fn_08020c9c:
	push {r3, r4, r5, r6, r7, lr}
	ldr r5, [r0, #4]
	mov r4, r0
	cbz r5, .L08020cde
	ldr r6, [r5, #0x18]
	cbz r6, .L08020ce2
	ldrh r3, [r5, #2]
	movs r0, #0
	cbz r3, .L08020d20
	cbz r2, .L08020ce6
	cmp r2, #1
	beq.n .L08020cf8
	cmp r2, #2
	bne.n .L08020cdc
	mov r3, r2
	ldr r0, [r4]
	mov r2, r1
	mov r1, r0
	mov r0, r5
	blx r6
	cmp r0, #0
	bne.n .L08020cdc
	ldrd r1, r0, [r4]
	mov r2, sp
	ldr r3, [r0, #0x1c]
	blx r3
	cmp r0, #0
	bne.n .L08020cdc
	ldr r2, [r4, #8]
	ldr r1, [sp]
	str r1, [r2, #8]
.L08020cdc:
	pop {r3, r4, r5, r6, r7, pc}
.L08020cde:
	movs r0, #0xb
	pop {r3, r4, r5, r6, r7, pc}
.L08020ce2:
	movs r0, #9
.L08020ce4:
	pop {r3, r4, r5, r6, r7, pc}
.L08020ce6:
	ldr r2, [r4, #8]
	str r1, [r2, #8]
	ldr r3, [r4, #8]
	mov r2, r1
	ldr r5, [r3]
	cmp r1, r5
	blo.n .L08020d0e
	ldr r1, [r3, #4]
	b.n .L08020d0a
.L08020cf8:
	ldr r3, [r4, #8]
	ldr r2, [r3, #8]
	add r2, r1
	str r2, [r3, #8]
	ldr r1, [r4, #8]
	ldr r3, [r1]
	cmp r2, r3
	blo.n .L08020d0e
	ldr r1, [r1, #4]
.L08020d0a:
	cmp r2, r1
	bls.n .L08020ce4
.L08020d0e:
	ldrd r1, r0, [r4]
	movs r3, #0
	ldr r4, [r0, #0x18]
	add sp, #4
	mov ip, r4
	pop.w {r4, r5, r6, r7, lr}
	bx ip
.L08020d20:
	b.n .L08020d22
.L08020d22:
	mov r3, r2
	ldr r0, [r4]
	mov r2, r1
	mov r1, r0
	add sp, #4
	mov r0, r5
	mov ip, r6
	pop.w {r4, r5, r6, r7, lr}
	bx ip

@ ----------------------------------------------------------------------------
@ fn_08022b12 - r0 = value, r1 = start point, r2 = end point, r3 = result at
@ the start, [sp + 0] at entry = result at the end (loaded into r4 at
@ 0x08022b16); returns an int.
@ When end >= start (ascending): value >= end returns the result at the end,
@ value <= start returns the result at the start. When end < start
@ (descending): value <= end returns the result at the end, value >= start
@ returns the result at the start. Otherwise returns ((end result - start
@ result) * (value - start)) / (end - start) + start result, with signed
@ multiply and sdiv.
@ ----------------------------------------------------------------------------
	.section .text.fn_08022b12,"ax",%progbits
	.global fn_08022b12
	.thumb_func
	.type fn_08022b12, %function
fn_08022b12:
	push {r4, lr}
	cmp r2, r1
	ldr r4, [sp, #8]
	blt.n .L08022b1e
	cmp r0, r2
	bge.n .L08022b2e
.L08022b1e:
	cmp r2, r1
	blt.n .L08022b26
	cmp r0, r1
	ble.n .L08022b3a
.L08022b26:
	cmp r2, r1
	bgt.n .L08022b32
	cmp r0, r2
	bgt.n .L08022b32
.L08022b2e:
	mov r0, r4
	pop {r4, pc}
.L08022b32:
	cmp r2, r1
	bgt.n .L08022b3e
	cmp r0, r1
	blt.n .L08022b3e
.L08022b3a:
	mov r0, r3
	pop {r4, pc}
.L08022b3e:
	subs r2, r2, r1
	subs r4, r4, r3
	subs r0, r0, r1
	muls r0, r4, r0
	sdiv r0, r0, r2
	add r0, r3
	pop {r4, pc}
	.short 0x0000  @ padding

@ ----------------------------------------------------------------------------
@ fn_08022b50 - r0 = size; returns a pointer.
@ Size 0 returns the address 0x200004ec. Else calls fn_08027a94 (word at
@ 0x200004f0, size); when it returns a block adds size to the word at
@ 0x200004f4 and keeps the maximum of 0x200004f4 in 0x200004f8; returns the
@ block or 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08022b50,"ax",%progbits
	.p2align 2
	.global fn_08022b50
	.thumb_func
	.type fn_08022b50, %function
fn_08022b50:
	push {r4, r5, r6, lr}
	movs r4, r0
	beq.n .L08022b78
	ldr r5, .L08022b7c
	mov r1, r0
	ldr r0, [r5, #4]
	bl fn_08027a94
	movs r1, r0
	beq.n .L08022b74
	ldr r0, [r5, #8]
	add r0, r4
	str r0, [r5, #8]
	ldr r2, [r5, #0xc]
	cmp r0, r2
	bhi.n .L08022b72
	mov r0, r2
.L08022b72:
	str r0, [r5, #0xc]
.L08022b74:
	mov r0, r1
	pop {r4, r5, r6, pc}
.L08022b78:
	ldr r0, .L08022b7c
	pop {r4, r5, r6, pc}
.L08022b7c:
	.word 0x200004ec

