@ gui_26.s - GUI object tree helpers: object removal, layout step calculation, redraw walk, size-array refresh
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080289ae - removes an object from the object tree (recursive).
@ Parameter: r0 = object pointer.
@ Returns at once (via the pop at 0x08028ac4) when fn_080207f4(r0, 0x21, 0) is 0.
@ Calls itself for every child returned by fn_08023d80(r0, 0) until none is left.
@ Walks the list fn_08021d90(0), fn_08021d90(item): clears the item words at +0x24
@ and +0x28 (via fn_08021e10(item, r0)) and +0x30 when they equal r0, and calls
@ fn_08021e10 when item word +0x50 equals fn_08023f18(r0) and read_word_200004a8()
@ returns r0.
@ Calls fn_0801270a(r0).
@ When word r0+4 is 0, removes r0 from the pointer array at
@ (fn_08023ebc(r0) + 0xc) by shifting the later entries down, decrements the count
@ at +0x24 and reallocates the array with fn_08022cb0. Otherwise removes it by the
@ same shift from the array of the object at word (r0+4)+8, using the index
@ fn_08023f2e().
@ Ends with a tail call to fn_08022c68(r0).
@ ----------------------------------------------------------------------------
	.section .text.fn_080289ae,"ax",%progbits
	.global fn_080289ae
	.thumb_func
	.type fn_080289ae, %function
fn_080289ae:
	push.w {r4, r5, r6, r7, r8, lr}
	mov r4, r0
	movs r2, #0
	movs r1, #0x21
	bl fn_080207f4
	cmp r0, #0
	beq.n .L08028abe
.L080289c0:
	movs r1, #0
	mov r0, r4
	bl fn_08023d80
	cbz r0, .L080289d0
	bl fn_080289ae
	b.n .L080289c0
.L080289d0:
	mov r0, r4
	bl fn_08023f18
	mov r6, r0
	movs r0, #0
	bl fn_08021d90
	mov r5, r0
	movs r7, #0
	b.n .L08028a1e
.L080289e4:
	ldr r0, [r5, #0x24]
	cmp r0, r4
	beq.n .L080289f0
	ldr r0, [r5, #0x28]
	cmp r0, r4
	bne.n .L080289f8
.L080289f0:
	mov r1, r4
	mov r0, r5
	bl fn_08021e10
.L080289f8:
	ldr r0, [r5, #0x30]
	cmp r0, r4
	bne.n .L08028a00
	str r7, [r5, #0x30]
.L08028a00:
	ldr r0, [r5, #0x50]
	cmp r0, r6
	bne.n .L08028a16
	bl read_word_200004a8
	cmp r0, r4
	bne.n .L08028a16
	mov r1, r4
	mov r0, r5
	bl fn_08021e10
.L08028a16:
	mov r0, r5
	bl fn_08021d90
	mov r5, r0
.L08028a1e:
	cmp r5, #0
	bne.n .L080289e4
	mov r0, r4
	bl fn_0801270a
	ldr r0, [r4, #0x4]
	movs r6, #4
	cmp r0, #0
	mov r0, r4
	beq.n .L08028a38
	bl fn_08023f2e
	b.n .L08028a8c
.L08028a38:
	bl fn_08023ebc
	mov r5, r0
	movs r0, #0
	ldr r2, [r5, #0xc]
	ldr r1, [r5, #0x24]
	b.n .L08028a50
.L08028a46:
	ldr.w r3, [r2, r0, lsl #2]
	cmp r3, r4
	beq.n .L08028a64
	.inst.n 0x1c40  @ adds r0, r0, #1
.L08028a50:
	cmp r1, r0
	bhi.n .L08028a46
	b.n .L08028a64
.L08028a56:
	ldr r1, [r5, #0xc]
	add.w r2, r6, r0, lsl #2
	ldr r2, [r1, r2]
	str.w r2, [r1, r0, lsl #2]
	.inst.n 0x1c40  @ adds r0, r0, #1
.L08028a64:
	ldr r1, [r5, #0x24]
	.inst.n 0x1e49  @ subs r1, r1, #1
	cmp r1, r0
	bhi.n .L08028a56
	ldr r0, [r5, #0x24]
	.inst.n 0x1e40  @ subs r0, r0, #1
	lsls r1, r0, #2
	str r0, [r5, #0x24]
	ldr r0, [r5, #0xc]
	bl fn_08022cb0
	str r0, [r5, #0xc]
	b.n .L08028ab6
.L08028a7e:
	ldr r1, [r1, #0]
	add.w r2, r6, r0, lsl #2
	ldr r2, [r1, r2]
	str.w r2, [r1, r0, lsl #2]
	.inst.n 0x1c40  @ adds r0, r0, #1
.L08028a8c:
	ldr r1, [r4, #0x4]
	ldr r1, [r1, #0x8]
	ldr r2, [r1, #0x4]
	.inst.n 0x1e52  @ subs r2, r2, #1
	cmp r2, r0
	bhi.n .L08028a7e
	ldr r0, [r4, #0x4]
	ldr r0, [r0, #0x8]
	ldr r0, [r0, #0x4]
	.inst.n 0x1e40  @ subs r0, r0, #1
	str r0, [r1, #0x4]
	ldr r1, [r4, #0x4]
	lsls r2, r0, #2
	ldr r1, [r1, #0x8]
	ldr r0, [r1, #0]
	mov r1, r2
	bl fn_08022cb0
	ldr r1, [r4, #0x4]
	ldr r1, [r1, #0x8]
	str r0, [r1, #0]
.L08028ab6:
	mov r0, r4
	pop.w {r4, r5, r6, r7, r8, lr}
	b.n .L08028ac0
.L08028abe:
	b.n .L08028ac4
.L08028ac0:
	b.w fn_08022c68
.L08028ac4:
	pop.w {r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_08028ac8 - zero-extends a byte value and tail-calls fn_08026620.
@ Parameters: r0 = param_1, r1 = byte value.
@ Zero-extends r1 to 8 bits (uxtb), sets r2 = 0 and tail-calls fn_08026620, which
@ tail-calls fn_08026342(r0, 0x60, value, 0).
@ Nothing is returned by this function itself.
@ ----------------------------------------------------------------------------
	.section .text.fn_08028ac8,"ax",%progbits
	.p2align 2
	.global fn_08028ac8
	.thumb_func
	.type fn_08028ac8, %function
fn_08028ac8:
	uxtb r1, r1
	movs r2, #0
	b.w fn_08026620

@ ----------------------------------------------------------------------------
@ fn_08028ad0 - computes the step and start position of items laid out in a
@ range, by mode.
@ Parameters: r0 = mode 1..5, r1 = total size, r2 = item size, r3 = item count,
@ stack: short pointer position (param_5), short pointer step (param_6).
@ When r3 < 2 and mode is 3, 4 or 5, or mode 2: stores 0 to *step and adds
@ (r1 - r2) / 2 to *position.
@ Mode 1: *step = 0, *position += r1 - r2.
@ Mode 3: *step = (r1 - r2) / (r3 + 1), *position += *step.
@ Mode 4: *step += (r1 - r2) / r3, *position += *step / 2.
@ Mode 5: *step = (r1 - r2) / (r3 - 1), position unchanged.
@ Other modes: *step = 0, position unchanged.
@ The mode is dispatched through a tbb table (modes 0..5).
@ ----------------------------------------------------------------------------
	.section .text.fn_08028ad0,"ax",%progbits
	.p2align 2
	.global fn_08028ad0
	.thumb_func
	.type fn_08028ad0, %function
fn_08028ad0:
	push {r4, r5, r6, r7, lr}
	movs r7, #0
	ldrd r4, r5, [sp, #0x14]
	subs r6, r1, r2
	cmp r3, #1
	bgt.n .L08028aea
	cmp r0, #3
	beq.n .L08028afc
	cmp r0, #4
	beq.n .L08028afc
	cmp r0, #5
	beq.n .L08028afc
.L08028aea:
	subs r1, r1, r2
	sxth r1, r1
	cmp r0, #6
	bcs.n .L08028b48
	tbb [pc, r0]
.L08028af6:
	.byte (.L08028b48 - .L08028af6)/2
	.byte (.L08028b0a - .L08028af6)/2
	.byte (.L08028afc - .L08028af6)/2
	.byte (.L08028b36 - .L08028af6)/2
	.byte (.L08028b1e - .L08028af6)/2
	.byte (.L08028b12 - .L08028af6)/2
.L08028afc:
	strh r7, [r5, #0]
	ldrh r0, [r4, #0]
	add.w r1, r6, r6, lsr #31
	add.w r0, r0, r1, asr #1
	b.n .L08028b44
.L08028b0a:
	strh r7, [r5, #0]
	ldrh r0, [r4, #0]
	add r0, r6
	b.n .L08028b44
.L08028b12:
	.inst.n 0x1e5b  @ subs r3, r3, #1
	sxth r0, r3
	sdiv r0, r1, r0
	strh r0, [r5, #0]
	pop {r4, r5, r6, r7, pc}
.L08028b1e:
	sdiv r0, r1, r3
	ldrh r1, [r5, #0]
	add r0, r1
	sxth r0, r0
	strh r0, [r5, #0]
	ldrh r1, [r4, #0]
	add.w r0, r0, r0, lsr #31
	add.w r0, r1, r0, asr #1
	b.n .L08028b44
.L08028b36:
	.inst.n 0x1c5b  @ adds r3, r3, #1
	sxth r0, r3
	sdiv r0, r1, r0
	strh r0, [r5, #0]
	ldrh r1, [r4, #0]
	add r0, r1
.L08028b44:
	strh r0, [r4, #0]
	pop {r4, r5, r6, r7, pc}
.L08028b48:
	strh r7, [r5, #0]
	pop {r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_08029080 - redraw walk from an object up through its parents.
@ Parameters: r0 = draw context, r1 = object pointer (0 selects
@ fn_0801dd5c of the word at 0x200004b8; if that is 0 the function returns).
@ When the object is not 0 calls fn_08028ed4(r0, object).
@ Then walks upward with fn_08023fa4(object) (parent): for each parent counts its
@ children with fn_08023da4(), calls fn_08028ed4 for every child after the object
@ itself in the parent's child array (pointer array at (word +8)) and sends the
@ messages 0x17, 0x18, 0x19 with fn_080207f4(parent, msg, r0).
@ Continues with the parent as object until none is left.
@ ----------------------------------------------------------------------------
	.section .text.fn_08029080,"ax",%progbits
	.p2align 2
	.global fn_08029080
	.thumb_func
	.type fn_08029080, %function
fn_08029080:
	push.w {r4, r5, r6, r7, r8, r9, r10, lr}
	movs r4, r1
	mov r9, r0
	bne.n .L08029096
	ldr r0, .L080290f8
	ldr r0, [r0, #4]
	bl fn_0801dd5c
	movs r4, r0
	beq.n .L080290ec
.L08029096:
	mov r1, r4
	mov r0, r9
	bl fn_08028ed4
	b.n .L080290e0
.L080290a0:
	movs r7, #0
	bl fn_08023da4
	mov r6, r0
	movs r5, #0
	b.n .L080290be
.L080290ac:
	ldr r0, [r4, #0x8]
	ldr r0, [r0, #0]
	ldr.w r1, [r0, r5, lsl #2]
	cbz r7, .L080290f0
	mov r0, r9
	bl fn_08028ed4
.L080290bc:
	.inst.n 0x1c6d  @ adds r5, r5, #1
.L080290be:
	cmp r5, r6
	bcc.n .L080290ac
	mov r2, r9
	movs r1, #0x17
	mov r0, r4
	bl fn_080207f4
	mov r2, r9
	movs r1, #0x18
	mov r0, r4
	bl fn_080207f4
	mov r2, r9
	movs r1, #0x19
	mov r0, r4
	bl fn_080207f4
.L080290e0:
	mov r8, r4
	mov r0, r8
	bl fn_08023fa4
	movs r4, r0
	bne.n .L080290a0
.L080290ec:
	pop.w {r4, r5, r6, r7, r8, r9, r10, pc}
.L080290f0:
	cmp r1, r8
	bne.n .L080290bc
	movs r7, #1
	b.n .L080290bc
.L080290f8:
	.word 0x200004b4

@ ----------------------------------------------------------------------------
@ fn_080290fc - recomputes the halfword array of an object (word +0x2c) from
@ index r1 up to the count in halfword +0x26, then refreshes the object.
@ Parameters: r0 = object (r5), r1 = start index (r4); r2 and r3 are not read.
@ Returns what fn_08025400 returns (tail call, b.w at 0x080291b2 with r0 = r5).
@ Calls fn_08024b10, fn_08024b4c, fn_08024ba0, fn_08024ab0, fn_08024cc0,
@ fn_08024cd8, fn_08024cae, fn_08024a2c and fn_08024a20 each with (r5, 0x50000);
@ results: [sp+28] = fn_08024b10, fp = fn_08024b4c, sl = fn_08024ba0, r9 =
@ fn_08024ab0, [sp+24] = fn_08024cc0, r8 = fn_08024cd8, [sp+20] = fn_08024cae,
@ r7 = fn_08024a2c, r6 = fn_08024a20.
@ Loop while halfword [r5+0x26] > r4 (unsigned): v = fn_0801b7d8(r5, uint16 r4,
@ [sp+20], [sp+24], stack words: r8, [sp+28], fp, sl, r9); the value stored is v
@ limited to r6 (signed) and then to at least r7; halfword
@ [word [r5+0x2c] + r4*2] = that value; r4 += 1.
@ After the loop calls fn_08025d04(r5), then add sp,#36 and tail-calls
@ fn_08025400(r5).
@ Called through the b.w at 0x08027528 of fn_080274d4 (message code 0x2a, r1 = 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_080290fc,"ax",%progbits
	.global fn_080290fc
	.thumb_func
	.type fn_080290fc, %function
fn_080290fc:
	push.w {r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov r4, r1
	mov.w r6, #0x50000
	sub sp, #0x24
	mov r5, r0
	mov r1, r6
	bl fn_08024b10
	str r0, [sp, #0x1c]
	mov r1, r6
	mov r0, r5
	bl fn_08024b4c
	mov r11, r0
	mov r1, r6
	mov r0, r5
	bl fn_08024ba0
	mov r10, r0
	mov r1, r6
	mov r0, r5
	bl fn_08024ab0
	mov r9, r0
	mov r1, r6
	mov r0, r5
	bl fn_08024cc0
	str r0, [sp, #0x18]
	mov r1, r6
	mov r0, r5
	bl fn_08024cd8
	mov r8, r0
	mov r1, r6
	mov r0, r5
	bl fn_08024cae
	str r0, [sp, #0x14]
	mov r1, r6
	mov r0, r5
	bl fn_08024a2c
	mov r7, r0
	mov r1, r6
	mov r0, r5
	bl fn_08024a20
	mov r6, r0
	b.n .L0802919e
.L08029164:
	ldr r3, [sp, #0x1c]
	str.w r11, [sp, #0x8]
	strd r8, r3, [sp, #0]
	strd r10, r9, [sp, #0xc]
	ldrd r2, r3, [sp, #0x14]
	uxth r1, r4
	mov r0, r5
	bl fn_0801b7d8
	cmp r0, r6
	bge.n .L08029186
	mov r1, r0
	b.n .L08029188
.L08029186:
	mov r1, r6
.L08029188:
	cmp r1, r7
	bge.n .L08029190
	mov r0, r7
	b.n .L08029196
.L08029190:
	cmp r0, r6
	blt.n .L08029196
	mov r0, r6
.L08029196:
	ldr r1, [r5, #0x2c]
	strh.w r0, [r1, r4, lsl #1]
	.inst.n 0x1c64  @ adds r4, r4, #1
.L0802919e:
	ldrh r0, [r5, #0x26]
	cmp r0, r4
	bhi.n .L08029164
	mov r0, r5
	bl fn_08025d04
	add sp, #0x24
	mov r0, r5
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w fn_08025400

@ ----------------------------------------------------------------------------
@ fn_080291b6 - sends message 0x2a to every descendant of an object (recursive).
@ Parameter: r0 = object pointer.
@ Child count n = fn_08023da4(); for every child pointer at (word r0+8 -> array)
@ index 0..n-1: calls fn_08025400(child), fn_080207f4(child, 0x2a, 0),
@ fn_08025400(child) again and recurses into the child.
@ ----------------------------------------------------------------------------
	.section .text.fn_080291b6,"ax",%progbits
	.global fn_080291b6
	.thumb_func
	.type fn_080291b6, %function
fn_080291b6:
	push.w {r4, r5, r6, r7, r8, lr}
	mov r7, r0
	bl fn_08023da4
	mov r5, r0
	movs r4, #0
	b.n .L080291ec
.L080291c6:
	ldr r0, [r7, #0x8]
	ldr r0, [r0, #0]
	ldr.w r6, [r0, r4, lsl #2]
	mov r0, r6
	bl fn_08025400
	movs r2, #0
	movs r1, #0x2a
	mov r0, r6
	bl fn_080207f4
	mov r0, r6
	bl fn_08025400
	mov r0, r6
	bl fn_080291b6
	.inst.n 0x1c64  @ adds r4, r4, #1
.L080291ec:
	cmp r4, r5
	bcc.n .L080291c6
	pop.w {r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_080291f4 - unlinks a node from a doubly linked list and updates the head's
@ slot and bit masks.
@ Parameters: r0 = list head, r1 = node, r2 = priority row, r3 = priority column.
@ Loads previous = word node+8 and next = word node+12; next = 0 enters the
@ endless loop at 0x08029232 (cbz at 0x080291fa) and previous = 0 the endless
@ loop at 0x08029234 (cbz at 0x080291fc).
@ Joins them: previous+0xc = next, next+8 = previous.
@ When the slot at head + r2*0x80 + r3*4 + 0x3c held the node it is set to
@ previous; when previous is the head, bit r3 of the word at head + r2*4 + 0x14
@ is cleared and, when that word becomes 0, bit r2 of the word at head + 0x10 is
@ cleared.
@ ----------------------------------------------------------------------------
	.section .text.fn_080291f4,"ax",%progbits
	.global fn_080291f4
	.thumb_func
	.type fn_080291f4, %function
fn_080291f4:
	push {r4, r5, r6, lr}
	ldrd r4, r5, [r1, #8]
	cbz r5, .L08029232
	cbz r4, .L08029234
	str r5, [r4, #0xc]
	str r4, [r5, #0x8]
	add.w r5, r0, r2, lsl #7
	add.w r5, r5, r3, lsl #2
	ldr r6, [r5, #0x3c]
	cmp r6, r1
	bne.n .L08029230
	str r4, [r5, #0x3c]
	cmp r4, r0
	bne.n .L08029230
	add.w r5, r0, r2, lsl #2
	movs r1, #1
	ldr r4, [r5, #0x14]
	lsl.w r3, r1, r3
	bics r4, r3
	str r4, [r5, #0x14]
	bne.n .L08029230
	ldr r3, [r0, #0x10]
	lsls r1, r2
	bics r3, r1
	str r3, [r0, #0x10]
.L08029230:
	pop {r4, r5, r6, pc}
.L08029232:
	b.n .L08029232
.L08029234:
	b.n .L08029234

@ ----------------------------------------------------------------------------
@ fn_08029236 - calls fn_08025d34 on matching entries of an object, then recurses
@ into the children (recursive).
@ Parameters: r0 = filter value, r1 = object pointer.
@ For each of (halfword at object+0x22 & 0x1ff) >> 3 entries (8 bytes each at
@ word object+0xc) whose first word equals r0 (or r0 = 0): calls
@ fn_08025d34(object, 0xf0000, 0xffff) and stops after the first hit.
@ Then recurses into every child (count fn_08023da4, array at word +8) with the
@ same r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08029236,"ax",%progbits
	.global fn_08029236
	.thumb_func
	.type fn_08029236, %function
fn_08029236:
	push.w {r4, r5, r6, r7, r8, lr}
	mov r4, r1
	ldrh r1, [r1, #0x22]
	mov r6, r0
	movs r0, #0
	ubfx r1, r1, #3, #6
	b.n .L08029266
.L08029248:
	cbz r6, .L08029254
	ldr r2, [r4, #0xc]
	ldr.w r2, [r2, r0, lsl #3]
	cmp r2, r6
	bne.n .L08029264
.L08029254:
	movw r2, #0xffff
	mov.w r1, #0xf0000
	mov r0, r4
	bl fn_08025d34
	b.n .L0802926a
.L08029264:
	.inst.n 0x1c40  @ adds r0, r0, #1
.L08029266:
	cmp r1, r0
	bhi.n .L08029248
.L0802926a:
	mov r0, r4
	bl fn_08023da4
	mov r7, r0
	movs r5, #0
	b.n .L08029286
.L08029276:
	ldr r0, [r4, #0x8]
	ldr r0, [r0, #0]
	ldr.w r1, [r0, r5, lsl #2]
	mov r0, r6
	bl fn_08029236
	.inst.n 0x1c6d  @ adds r5, r5, #1
.L08029286:
	cmp r5, r7
	bcc.n .L08029276
	pop.w {r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_08029320 - resets the state record of an object and sends messages 0x27,
@ 0x28.
@ Parameter: r0 = pointer to an object pointer.
@ Gets record R = fn_08023ebc(*r0); sends message 0x27 to word R+0x10 and
@ message 0x28 to word R+0x14 via fn_080207f4.
@ When R+0x14 is not 0 and bit 1 of the byte at R+0x28 is set calls fn_08023690().
@ Clears the word R+0x14, bit 0 of the byte R+0x28 and the word R+0x18, calls
@ fn_08025e80(*r0, 0x60, 0), then tail-calls fn_08025400(word R+0x10).
@ ----------------------------------------------------------------------------
	.section .text.fn_08029320,"ax",%progbits
	.global fn_08029320
	.thumb_func
	.type fn_08029320, %function
fn_08029320:
	push {r4, r5, r6, lr}
	mov r5, r0
	ldr r0, [r0, #0]
	bl fn_08023ebc
	mov r4, r0
	ldr r0, [r0, #0x10]
	movs r2, #0
	movs r1, #0x27
	bl fn_080207f4
	movs r2, #0
	movs r1, #0x28
	ldr r0, [r4, #0x14]
	bl fn_080207f4
	ldr r0, [r4, #0x14]
	cbz r0, .L08029350
	ldrb.w r1, [r4, #0x28]
	lsls r1, r1, #0x1e
	bpl.n .L08029350
	bl fn_08023690
.L08029350:
	movs r0, #0
	str r0, [r4, #0x14]
	ldrb.w r1, [r4, #0x28]!
	movs r2, #0
	bic.w r1, r1, #1
	strb.w r1, [r4], #-0x18
	movs r1, #0x60
	str r0, [r4, #0x8]
	ldr r0, [r5, #0]
	bl fn_08025e80
	ldr r0, [r4, #0]
	pop.w {r4, r5, r6, lr}
	b.w fn_08025400

@ ----------------------------------------------------------------------------
@ fn_08029376 - stores the active object in its state record and sends message
@ 0x26.
@ Parameter: r0 = pointer to an object pointer.
@ Gets record R = fn_08023ebc(*r0), stores fn_08026b78() in word R+0x14, stores
@ *r0 in word R+0x10 and tail-calls fn_080207f4(*r0, 0x26, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_08029376,"ax",%progbits
	.global fn_08029376
	.thumb_func
	.type fn_08029376, %function
fn_08029376:
	push {r4, r5, r6, lr}
	mov r4, r0
	ldr r0, [r0, #0]
	bl fn_08023ebc
	mov r5, r0
	bl fn_08026b78
	str r0, [r5, #0x14]
	ldr r3, [r4, #0]
	str r3, [r5, #0x10]
	pop.w {r4, r5, r6, lr}
	movs r2, #0
	movs r1, #0x26
	mov r0, r3
	b.w fn_080207f4

@ ----------------------------------------------------------------------------
@ fn_0802939a - makes an object the current one in its state record.
@ Parameter: r0 = new object pointer.
@ Gets record R = fn_08023ebc(r0) and returns when it is 0.
@ Old = word R+0x10; when Old is not 0 sends message 0x25 to Old and, when R+0x10
@ is still not 0, message 0x26 to r0.
@ Stores r0 in R+0x10; when r0 is not 0 sends message 0x27 to r0 and, when R+0x10
@ is still not 0, message 0x28 to Old.
@ Tail-calls fn_08025400(r0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802939a,"ax",%progbits
	.global fn_0802939a
	.thumb_func
	.type fn_0802939a, %function
fn_0802939a:
	push {r4, r5, r6, lr}
	mov r5, r0
	bl fn_08023ebc
	movs r4, r0
	beq.n .L080293e8
	ldr r6, [r4, #0x10]
	cbz r6, .L080293c2
	movs r2, #0
	movs r1, #0x25
	mov r0, r6
	bl fn_080207f4
	ldr r0, [r4, #0x10]
	cbz r0, .L080293c2
	movs r2, #0
	movs r1, #0x26
	mov r0, r5
	bl fn_080207f4
.L080293c2:
	str r5, [r4, #0x10]
	cbz r5, .L080293de
	movs r2, #0
	movs r1, #0x27
	mov r0, r5
	bl fn_080207f4
	ldr r0, [r4, #0x10]
	cbz r0, .L080293de
	movs r2, #0
	movs r1, #0x28
	mov r0, r6
	bl fn_080207f4
.L080293de:
	mov r0, r5
	pop.w {r4, r5, r6, lr}
	b.w fn_08025400
.L080293e8:
	pop {r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_080293ea - sends message 10 with value 0 to an object.
@ Parameter: r0 = pointer to an object pointer.
@ Tail-calls fn_080207f4(*r0, 10, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_080293ea,"ax",%progbits
	.global fn_080293ea
	.thumb_func
	.type fn_080293ea, %function
fn_080293ea:
	movs r2, #0
	ldr r0, [r0, #0]
	movs r1, #0xa
	b.w fn_080207f4

@ ----------------------------------------------------------------------------
@ fn_080293f4 - computes the scroll shift that brings a rectangle of an object
@ into the visible rectangle of its parent and applies it.
@ Parameters: r0 = reference rectangle pointer (4 shorts), r1 = object pointer,
@ r2 = pointer to a 2-short offset (x, y), r3 = apply flag (stored at [sp+32]).
@ Parent P = fn_08023fa4(r1); returns when all_flag_bits_set(P, 0x10) is 0.
@ Computes for the vertical and then the horizontal axis the shift that moves a
@ rectangle into the visible rectangle of P using the properties fn_08024990,
@ fn_08024b7c, fn_08024a8c, fn_08024aec and fn_08024b28 and the alignment modes
@ fn_080241fa (vertical) and fn_080241ec (horizontal) with the limits fn_08023fbc,
@ fn_08024208, fn_08024130 and fn_08024070.
@ Alignment mode 0 uses the reference rectangle r0 (minimal shift); modes 1, 2 and
@ 3 use the object rectangle at object+20 and align its start edge, end edge or
@ centre.
@ Applies the mask bits of fn_08024060 (bit 0 allows negative x shifts, bit 1
@ positive x, bit 2 negative y, bit 3 positive y; a disallowed shift is set to 0).
@ Returns without change when fn_0801c688(P, 0x08029695) or fn_0801c688(P,
@ 0x0802967d) is not 0 and fn_080207f4(P, 10, 0) is not 1.
@ When r3 is not 0 adds the x shift to *r2 and the y shift to *(r2+2).
@ Ends with a tail call fn_08026014(P, xshift, yshift, r3).
@ ----------------------------------------------------------------------------
	.section .text.fn_080293f4,"ax",%progbits
	.p2align 2
	.global fn_080293f4
	.thumb_func
	.type fn_080293f4, %function
fn_080293f4:
	push.w {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0x14
	mov r8, r2
	mov r4, r1
	mov r0, r1
	bl fn_08023fa4
	mov r6, r0
	movs r1, #0x10
	bl all_flag_bits_set
	cmp r0, #0
	beq.n .L080294f0
	mov r0, r6
	bl fn_08024060
	mov r11, r0
	movs r5, #0
	mov r0, r6
	bl fn_080241fa
	adds r4, #0x14
	strd r4, r0, [sp, #0x8]
	cbnz r0, .L0802942a
	ldr r4, [sp, #0x14]
.L0802942a:
	movs r1, #0
	mov r0, r6
	bl fn_08024990
	mov r10, r0
	movs r1, #0
	mov r0, r6
	bl fn_08024b7c
	add r0, r10
	sxth r7, r0
	movs r1, #0
	mov r0, r6
	bl fn_08024a8c
	add r0, r10
	sxth r0, r0
	str r0, [sp, #0x4]
	ldrh r0, [r6, #0x16]
	ldrh r1, [r4, #0x2]
	add r0, r7
	subs r2, r0, r1
	ldrh.w r1, [r8, #0x2]
	subs r0, r2, r1
	sxth.w r9, r0
	ldrh r2, [r6, #0x1a]
	ldr r0, [sp, #0x4]
	subs r0, r2, r0
	ldrh r2, [r4, #0x6]
	subs r0, r0, r2
	subs r0, r1, r0
	sxth r0, r0
	str r0, [sp, #0]
	mov r0, r6
	bl rect_height_plus_one
	subs r1, r0, r7
	ldr r0, [sp, #0x4]
	subs r0, r1, r0
	sxth r0, r0
	str r0, [sp, #0x10]
	cmp.w r9, #0
	blt.n .L080294a0
	ldr r0, [sp, #0]
	cmp r0, #0
	bge.n .L080294b6
	subs.w r0, r9, #0
	ble.n .L080294a0
	mov r5, r0
	mov r0, r6
	bl fn_08024208
	subs r0, r0, r5
	bmi.n .L080294b4
	b.n .L080294b6
.L080294a0:
	ldr r0, [sp, #0]
	cmp r0, #0
	ble.n .L080294b6
	rsbs r0, r0, #0
	sxth r5, r0
	mov r0, r6
	bl fn_08023fbc
	cmn r0, r5
	bpl.n .L080294b6
.L080294b4:
	movs r5, #0
.L080294b6:
	ldr r0, [sp, #0xc]
	cmp r0, #1
	beq.n .L080294c6
	cmp r0, #2
	beq.n .L080294d0
	cmp r0, #3
	bne.n .L080294e0
	b.n .L080294f2
.L080294c6:
	ldrh r0, [r6, #0x16]
	ldrh r1, [r4, #0x2]
	add r0, r7
	add r1, r5
	b.n .L08029514
.L080294d0:
	ldrh r1, [r6, #0x1a]
	ldr r0, [sp, #0x4]
	subs r1, r1, r0
	ldrh r0, [r4, #0x6]
	add r0, r5
	subs r0, r1, r0
.L080294dc:
	add r0, r5
	sxth r5, r0
.L080294e0:
	movs r4, #0
	mov r0, r6
	bl fn_080241ec
	str r0, [sp, #0]
	cbz r0, .L08029518
	ldr r7, [sp, #0x8]
	b.n .L0802951a
.L080294f0:
	b.n .L0802966e
.L080294f2:
	ldr r0, [sp, #0x10]
	ldrh r1, [r6, #0x16]
	add.w r0, r0, r0, lsr #31
	add.w r0, r7, r0, asr #1
	add r0, r1
	ldrh r2, [r4, #0x6]
	ldrh r1, [r4, #0x2]
	subs r2, r2, r1
	.inst.n 0x1c52  @ adds r2, r2, #1
	sxth r2, r2
	add.w r2, r2, r2, lsr #31
	add.w r2, r5, r2, asr #1
	add r1, r2
.L08029514:
	subs r0, r0, r1
	b.n .L080294dc
.L08029518:
	ldr r7, [sp, #0x14]
.L0802951a:
	movs r1, #0
	mov r0, r6
	bl fn_08024aec
	add r0, r10
	sxth.w r9, r0
	movs r1, #0
	mov r0, r6
	bl fn_08024b28
	add r0, r10
	ldrh r1, [r6, #0x14]
	sxth.w r10, r0
	add.w r0, r1, r9
	ldrh r1, [r7, #0]
	ldrh r3, [r6, #0x18]
	subs r2, r0, r1
	ldrh.w r1, [r8, #0]
	subs r0, r2, r1
	sub.w r2, r3, r10
	ldrh r3, [r7, #4]
	sxth r0, r0
	subs r2, r2, r3
	subs r1, r1, r2
	sxth r1, r1
	cmp r0, #0
	blt.n .L08029570
	cmp r1, #0
	bge.n .L08029584
	cmp r0, #0
	ble.n .L08029570
	mov r4, r0
	mov r0, r6
	bl fn_08024070
	subs r0, r0, r4
	bmi.n .L08029582
	b.n .L08029584
.L08029570:
	cmp r1, #0
	ble.n .L08029584
	rsbs r0, r1, #0
	sxth r4, r0
	mov r0, r6
	bl fn_08024130
	cmn r0, r4
	bpl.n .L08029584
.L08029582:
	movs r4, #0
.L08029584:
	mov r0, r6
	bl rect_width_plus_one
	sub.w r1, r0, r9
	sub.w r0, r1, r10
	ldr r1, [sp, #0]
	sxth r0, r0
	cmp r1, #1
	beq.n .L080295a4
	cmp r1, #2
	beq.n .L080295ae
	cmp r1, #3
	bne.n .L080295be
	b.n .L080295ea
.L080295a4:
	ldrh r1, [r6, #0x14]
	add.w r0, r1, r9
	ldrh r1, [r7, #0]
	b.n .L080295b6
.L080295ae:
	ldrh r1, [r6, #0x18]
	sub.w r0, r1, r10
	ldrh r1, [r7, #4]
.L080295b6:
	add r1, r4
.L080295b8:
	subs r0, r0, r1
	add r0, r4
	sxth r4, r0
.L080295be:
	ldr r1, .L08029674
	mov r0, r6
	bl fn_0801c688
	mov r7, r0
	ldr r1, .L08029678
	mov r0, r6
	bl fn_0801c688
	orrs r0, r7
	beq.n .L080295e2
	movs r2, #0
	movs r1, #0xa
	mov r0, r6
	bl fn_080207f4
	cmp r0, #1
	bne.n .L0802966e
.L080295e2:
	lsls.w r0, r11, #31
	beq.n .L0802960c
	b.n .L08029612
.L080295ea:
	add.w r2, r0, r0, lsr #31
	ldrh r1, [r6, #0x14]
	add.w r0, r9, r2, asr #1
	add r0, r1
	ldrh r1, [r7, #4]
	ldrh r2, [r7, #0]
	subs r1, r1, r2
	.inst.n 0x1c49  @ adds r1, r1, #1
	sxth r1, r1
	add.w r1, r1, r1, lsr #31
	add.w r1, r4, r1, asr #1
	add r1, r2
	b.n .L080295b8
.L0802960c:
	cmp r4, #0
	bge.n .L08029612
	movs r4, #0
.L08029612:
	lsls.w r0, r11, #30
	bmi.n .L0802961e
	cmp r4, #0
	ble.n .L0802961e
	movs r4, #0
.L0802961e:
	lsls.w r0, r11, #29
	bmi.n .L0802962a
	cmp r5, #0
	bge.n .L0802962a
	movs r5, #0
.L0802962a:
	lsls.w r0, r11, #28
	bmi.n .L08029636
	cmp r5, #0
	ble.n .L08029636
	movs r5, #0
.L08029636:
	ldr r0, [sp, #0x20]
	ldrsh.w r1, [r8, #0]
	cmp r0, #0
	beq.n .L08029642
	mov r0, r4
.L08029642:
	add r0, r1
	strh.w r0, [r8, #0]
	ldrsh.w r1, [r8, #2]
	bne.n .L08029654
	mov.w r0, #0
	b.n .L08029656
.L08029654:
	mov r0, r5
.L08029656:
	add r0, r1
	strh.w r0, [r8, #2]
	ldr r3, [sp, #0x20]
	add sp, #0x24
	mov r2, r5
	mov r1, r4
	mov r0, r6
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w fn_08026014
.L0802966e:
	add sp, #0x24
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08029674:
	.word fn_08029694
.L08029678:
	.word fn_0802967c

@ ----------------------------------------------------------------------------
@ fn_0802967c - adds a value to fn_08024216 of an object and passes the sum as
@ the second argument to fn_0801273e.
@ Parameters: r0 = object pointer, r1 = value.
@ Saves r0 in r3, calls fn_08024216(r0), adds r1 to its result, sign-extends it
@ to 16 bits and tail-calls fn_0801273e(r0, sum, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802967c,"ax",%progbits
	.p2align 2
	.global fn_0802967c
	.thumb_func
	.type fn_0802967c, %function
fn_0802967c:
	push {r4, lr}
	mov r3, r0
	bl fn_08024216
	add r0, r1
	sxth r1, r0
	pop.w {r4, lr}
	movs r2, #0
	mov r0, r3
	b.w fn_0801273e

@ ----------------------------------------------------------------------------
@ fn_08029694 - adds a value to fn_08024224 of an object and passes the sum as
@ the third argument to fn_0801273e.
@ Parameters: r0 = object pointer, r1 = value.
@ Saves r0 in r3, calls fn_08024224(r0), adds r1 to its result, sign-extends it
@ to 16 bits and tail-calls fn_0801273e(r0, 0, sum).
@ ----------------------------------------------------------------------------
	.section .text.fn_08029694,"ax",%progbits
	.p2align 2
	.global fn_08029694
	.thumb_func
	.type fn_08029694, %function
fn_08029694:
	push {r4, lr}
	mov r3, r0
	bl fn_08024224
	add r0, r1
	sxth r2, r0
	pop.w {r4, lr}
	movs r1, #0
	mov r0, r3
	b.w fn_0801273e

@ ----------------------------------------------------------------------------
@ fn_080296ac - reads the property block of an object into a parameter block.
@ Parameters: r0 = object pointer, r1 = parameter block pointer; returns byte 1
@ when any of the three bytes at block+3, +0x22, +0x36 is not 0, 0 otherwise.
@ Clears the block with fn_0801f344(r1) and reads properties with mask 0x10000 via
@ fn_08024bac / fn_0802495c: byte at block+3 = fn_0802495c(r0, 0x10000), halfword
@ block+4 = property 0x20 when that byte is above 2.
@ Byte block+0x22 = property 0x31; when above 2: halfword block+0x20 = property
@ 0x32 and, only when that value is above 0, halfword block+0x1e = property 0x30,
@ otherwise byte block+0x22 is set to 0.
@ Byte block+0x36 = property 0x45; when above 2: halfword block+0x2e = property
@ 0x40 and, only when that value is above 0, halfword block+0x34 = property 0x43
@ and halfword block+0x2c = property 0x44, otherwise byte block+0x36 is set to 0.
@ Property 0x60 below 0xfd: byte block+3 = (byte block+3 * v) >> 8, then bytes
@ block+0x22 and block+0x36 are both overwritten with (new byte block+3 * v) >> 8.
@ When any of the three bytes is not 0 stores fn_08024c40(r0, 0x10000) in the
@ halfword block+0 and returns 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_080296ac,"ax",%progbits
	.p2align 2
	.global fn_080296ac
	.thumb_func
	.type fn_080296ac, %function
fn_080296ac:
	push {r3, r4, r5, r6, r7, lr}
	mov r5, r0
	mov r4, r1
	mov r0, r1
	bl fn_0801f344
	mov.w r6, #0x10000
	mov r1, r6
	mov r0, r5
	bl fn_0802495c
	strb r0, [r4, #0x3]
	cmp r0, #2
	bls.n .L080296dc
	mov r0, r5
	mov r1, r6
	movs r2, #0x20
	bl fn_08024bac
	str r0, [sp, #0]
	ldrh.w r0, [sp, #0]
	strh r0, [r4, #0x4]
.L080296dc:
	mov r0, r5
	mov r1, r6
	movs r2, #0x31
	bl fn_08024bac
	uxtb r0, r0
	movs r7, #0
	strb.w r0, [r4, #0x22]
	cmp r0, #2
	bls.n .L0802971c
	mov r0, r5
	mov r1, r6
	movs r2, #0x32
	bl fn_08024bac
	sxth r0, r0
	strh r0, [r4, #0x20]
	cmp r0, #0
	ble.n .L08029718
	mov r0, r5
	mov r1, r6
	movs r2, #0x30
	bl fn_08024bac
	str r0, [sp, #0]
	ldrh.w r0, [sp, #0]
	strh r0, [r4, #0x1e]
	b.n .L0802971c
.L08029718:
	strb.w r7, [r4, #0x22]
.L0802971c:
	mov r0, r5
	mov r1, r6
	movs r2, #0x45
	bl fn_08024bac
	uxtb r0, r0
	strb.w r0, [r4, #0x36]
	cmp r0, #2
	bls.n .L08029766
	mov r0, r5
	mov r1, r6
	movs r2, #0x40
	bl fn_08024bac
	sxth r0, r0
	strh r0, [r4, #0x2e]
	cmp r0, #0
	ble.n .L08029762
	mov r0, r5
	movs r2, #0x43
	mov r1, r6
	bl fn_08024bac
	strh r0, [r4, #0x34]
	mov r0, r5
	movs r2, #0x44
	mov r1, r6
	bl fn_08024bac
	str r0, [sp, #0]
	ldrh.w r0, [sp, #0]
	strh r0, [r4, #0x2c]
	b.n .L08029766
.L08029762:
	strb.w r7, [r4, #0x36]
.L08029766:
	mov r0, r5
	mov r1, r6
	movs r2, #0x60
	bl fn_08024bac
	uxtb r0, r0
	cmp r0, #0xfd
	bcs.n .L0802978c
	ldrb r1, [r4, #0x3]
	smulbb r1, r1, r0
	lsrs r1, r1, #8
	strb r1, [r4, #0x3]
	muls r1, r0, r1
	lsrs r0, r1, #8
	strb.w r0, [r4, #0x22]
	strb.w r0, [r4, #0x36]
.L0802978c:
	ldrb r0, [r4, #0x3]
	cbnz r0, .L0802979e
	ldrb.w r0, [r4, #0x22]
	cbnz r0, .L0802979e
	ldrb.w r0, [r4, #0x36]
	cmp r0, #0
	beq.n .L080297aa
.L0802979e:
	mov r1, r6
	mov r0, r5
	bl fn_08024c40
	strh r0, [r4, #0]
	movs r0, #1
.L080297aa:
	pop {r3, r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_080297ac - stores a halfword value at object offset 0x44.
@ Parameters: r0 = object pointer, r1 = halfword value.
@ Stores the value in the halfword at r0 + 0x44, then tail-calls fn_08025400(r0).
@ ----------------------------------------------------------------------------
	.section .text.fn_080297ac,"ax",%progbits
	.p2align 2
	.global fn_080297ac
	.thumb_func
	.type fn_080297ac, %function
fn_080297ac:
	strh.w r1, [r0, #0x44]
	b.w fn_08025400

@ ----------------------------------------------------------------------------
@ fn_080297b4 - stores a halfword value at object offset 0x46.
@ Parameters: r0 = object pointer, r1 = halfword value.
@ Stores the value in the halfword at r0 + 0x46, then tail-calls fn_08025400(r0).
@ ----------------------------------------------------------------------------
	.section .text.fn_080297b4,"ax",%progbits
	.p2align 2
	.global fn_080297b4
	.thumb_func
	.type fn_080297b4, %function
fn_080297b4:
	strh.w r1, [r0, #0x46]
	b.w fn_08025400

@ ----------------------------------------------------------------------------
@ fn_080297bc - sign-extends a halfword value and tail-calls fn_08026700.
@ Parameters: r0 = argument, r1 = halfword value.
@ Sign-extends r1 and tail-calls fn_08026700(r0, value).
@ ----------------------------------------------------------------------------
	.section .text.fn_080297bc,"ax",%progbits
	.global fn_080297bc
	.thumb_func
	.type fn_080297bc, %function
fn_080297bc:
	sxth r1, r1
	b.w fn_08026700

@ ----------------------------------------------------------------------------
@ fn_080297c2 - sign-extends a halfword value and tail-calls fn_0802672c.
@ Parameters: r0 = argument, r1 = halfword value.
@ Sign-extends r1 and tail-calls fn_0802672c(r0, value).
@ ----------------------------------------------------------------------------
	.section .text.fn_080297c2,"ax",%progbits
	.global fn_080297c2
	.thumb_func
	.type fn_080297c2, %function
fn_080297c2:
	sxth r1, r1
	b.w fn_0802672c

@ ----------------------------------------------------------------------------
@ fn_080297c8 - box filter over a square array of halfwords, rows then columns.
@ Parameters: r0 = side length n, r1 = window size w, r2 = pointer to n*n
@ halfwords (modified in place); r3 is not read (overwritten at 0x080297e8).
@ Allocates a row buffer with fn_08022bac(n*2) and applies a box filter of width
@ w along each of the n rows (running sum, window half-widths w >> 1 and w >> 1
@ or one less for even w), writing the sums back with copy_bytes_08022ce0.
@ Divides every nonzero entry by w (value 0x3fc0 becomes 0x3fc0 / w).
@ Then applies the same running-sum filter along the n columns (result >> 6,
@ negative sums become 0).
@ Frees the buffer with a tail call to fn_08022c44.
@ ----------------------------------------------------------------------------
	.section .text.fn_080297c8,"ax",%progbits
	.p2align 2
	.global fn_080297c8
	.thumb_func
	.type fn_080297c8, %function
fn_080297c8:
	push.w {r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov r4, r0
	asrs r7, r1, #1
	mov r9, r2
	mov r5, r1
	asr.w r10, r1, #1
	lsls r0, r1, #31
	bne.n .L080297de
	.inst.n 0x1e7f  @ subs r7, r7, #1
.L080297de:
	lsls r0, r4, #1
	mov r11, r0
	bl fn_08022bac
	mov r6, r0
	mov r3, r9
	movs r0, #0
	b.n .L0802983c
	nop  @ padding
.L080297f0:
	add.w r0, r3, r4, lsl #1
	str r0, [sp, #0]
	ldrh.w r1, [r0, #-2]
	muls r1, r5, r1
	subs r0, r4, #1
	bmi.n .L0802982c
.L08029800:
	movs r2, #0
	add.w r12, r0, r10
	strh.w r1, [r6, r0, lsl #1]
	cmp r12, r4
	bge.n .L08029812
	ldrh.w r2, [r3, r12, lsl #1]
.L08029812:
	subs r2, r1, r2
	subs r1, r0, r7
	cmp r1, #1
	bpl.n .L0802981e
	ldrh r1, [r3, #0]
	b.n .L08029826
.L0802981e:
	add.w r1, r3, r1, lsl #1
	ldrh.w r1, [r1, #-2]
.L08029826:
	.inst.n 0x1e40  @ subs r0, r0, #1
	add r1, r2
	bpl.n .L08029800
.L0802982c:
	mov r2, r11
	mov r1, r6
	mov r0, r3
	bl copy_bytes_08022ce0
	ldr r3, [sp, #0]
	add.w r0, r8, #1
.L0802983c:
	mov r8, r0
	cmp r0, r4
	blt.n .L080297f0
	mov.w r1, #0x3fc0
	udiv r2, r1, r5
	movs r0, #0
	uxth r3, r2
	smulbb r12, r4, r4
	b.n .L0802986e
.L08029854:
	ldrh.w r2, [r9, r0, lsl #1]
	cbz r2, .L0802986c
	cmp r2, r1
	bne.n .L08029864
	strh.w r3, [r9, r0, lsl #1]
	b.n .L0802986c
.L08029864:
	sdiv r2, r2, r5
	strh.w r2, [r9, r0, lsl #1]
.L0802986c:
	.inst.n 0x1c40  @ adds r0, r0, #1
.L0802986e:
	cmp r12, r0
	bhi.n .L08029854
	movs r0, #0
	b.n .L080298ea
	nop  @ padding
.L08029878:
	add.w r2, r9, r0, lsl #1
	mov r11, r2
	ldrh r3, [r2, #0]
	muls r3, r5, r3
	movs r1, #0
	b.n .L080298ce
.L08029886:
	cmp r3, #0
	bge.n .L08029890
	mov.w r12, #0
	b.n .L08029894
.L08029890:
	asr.w r12, r3, #6
.L08029894:
	strh.w r12, [r6, r1, lsl #1]
	sub.w r12, r1, r10
	cmp.w r12, #0
	bgt.n .L080298a8
	ldrh.w r12, [r2, #0]
	b.n .L080298b0
.L080298a8:
	mla r8, r12, r4, r0
	ldrh.w r12, [r9, r8, lsl #1]
.L080298b0:
	sub.w r12, r3, r12
	adds r3, r1, r7
	.inst.n 0x1c5b  @ adds r3, r3, #1
	cmp r3, r4
	blt.n .L080298be
	subs r3, r4, #1
.L080298be:
	mla r8, r3, r4, r0
	add.w r2, r2, r4, lsl #1
	ldrh.w r3, [r9, r8, lsl #1]
	.inst.n 0x1c49  @ adds r1, r1, #1
	add r3, r12
.L080298ce:
	cmp r1, r4
	blt.n .L08029886
	mov r2, r11
	movs r1, #0
	b.n .L080298e4
.L080298d8:
	ldrh.w r3, [r6, r1, lsl #1]
	strh r3, [r2, #0]
	add.w r2, r2, r4, lsl #1
	.inst.n 0x1c49  @ adds r1, r1, #1
.L080298e4:
	cmp r1, r4
	blt.n .L080298d8
	.inst.n 0x1c40  @ adds r0, r0, #1
.L080298ea:
	cmp r0, r4
	blt.n .L08029878
	mov r0, r6
	pop.w {r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w fn_08022c44

@ ----------------------------------------------------------------------------
@ fn_080298f8 - builds an n*n filtered coverage map of byte or halfword values.
@ Parameters: r0 = object pointer, r1 = output buffer of n*n halfwords, r2 =
@ radius value a, r3 = value b; n = a + b.
@ Builds a rectangle from copy_rect_0801d00c(object) and the sizes a, b and sets
@ up a line source with fn_0801f1a8; allocates an n-byte buffer with
@ fn_08022bac(n).
@ For each of the n rows sets the buffer to 0xff (fill_bytes_ff), calls the line
@ function in the source (first word) for that row; a returned 0 clears the
@ output row (clear_bytes, n*2 bytes), otherwise converts each byte to
@ (byte << 6) / k, repeating the previous value when the byte equals the previous
@ one, with k = a / 2 (1 when a is 1).
@ Frees with fn_08022c44 and fn_0801ec98.
@ k = 1 packs the output to bytes (value >> 6); otherwise filters with
@ fn_080297c8(n, k, out), re-scales entries by m = (a & 1) + k when m is above 1
@ (nonzero entry (v << 6) / m, 0xff becomes 0x3fc0 / m) and filters again with
@ fn_080297c8(n, m, out), then packs the low byte of each halfword to bytes.
@ ----------------------------------------------------------------------------
	.section .text.fn_080298f8,"ax",%progbits
	.global fn_080298f8
	.thumb_func
	.type fn_080298f8, %function
fn_080298f8:
	push.w {r4, r5, r6, r7, r8, r9, r10, lr}
	mov r6, r1
	sub sp, #0x28
	mov r7, r3
	mov r8, r0
	mov r1, r0
	mov r5, r2
	mov r9, r2
	adds r4, r2, r7
	add r0, sp, #0x1c
	bl copy_rect_0801d00c
	add.w r0, r5, r5, lsr #31
	add.w r1, r7, r0, asr #1
	sbfx r2, r5, #0, #1
	subs r1, r1, r2
	.inst.n 0x1e89  @ subs r1, r1, #2
	strh.w r1, [sp, #0x20]
	movs r1, #1
	add.w r0, r1, r0, asr #1
	strh.w r0, [sp, #0x1e]
	mov r0, r8
	bl rect_width_0801d06a
	ldrh.w r1, [sp, #0x20]
	subs r0, r1, r0
	strh.w r0, [sp, #0x1c]
	mov r0, r8
	bl rect_height_0801d01e
	ldrh.w r1, [sp, #0x1e]
	movs r3, #0
	add r0, r1
	strh.w r0, [sp, #0x22]
	mov r2, r7
	add r1, sp, #0x1c
	add r0, sp, #0x4
	bl fn_0801f1a8
	mov r5, r9
	cmp.w r9, #1
	beq.n .L08029968
	asr.w r5, r9, #1
.L08029968:
	mov r0, r4
	bl fn_08022bac
	mov r10, r0
	mov r8, r6
	movs r7, #0
	b.n .L080299e0
.L08029976:
	mov r1, r4
	mov r0, r10
	bl fill_bytes_ff
	add r0, sp, #0x4
	str r0, [sp, #0]
	ldr.w r12, [sp, #0x4]
	sxth r3, r4
	sxth r2, r7
	movs r1, #0
	mov r0, r10
	blx r12
	cbz r0, .L080299a4
	ldrb.w r0, [r10, #0]
	lsls r0, r0, #6
	sdiv r1, r0, r5
	strh.w r1, [r8, #0]
	movs r0, #1
	b.n .L080299d6
.L080299a4:
	lsls r1, r4, #1
	mov r0, r8
	bl clear_bytes
	b.n .L080299da
	nop  @ padding
.L080299b0:
	add.w r2, r10, r0
	ldrb.w r1, [r10, r0]
	ldrb.w r2, [r2, #-1]
	cmp r1, r2
	bne.n .L080299ca
	add.w r1, r8, r0, lsl #1
	ldrh.w r2, [r1, #-2]
	b.n .L080299d0
.L080299ca:
	lsls r1, r1, #6
	sdiv r2, r1, r5
.L080299d0:
	strh.w r2, [r8, r0, lsl #1]
	.inst.n 0x1c40  @ adds r0, r0, #1
.L080299d6:
	cmp r0, r4
	blt.n .L080299b0
.L080299da:
	add.w r8, r8, r4, lsl #1
	.inst.n 0x1c7f  @ adds r7, r7, #1
.L080299e0:
	cmp r7, r4
	blt.n .L08029976
	mov r0, r10
	bl fn_08022c44
	add r0, sp, #0x4
	bl fn_0801ec98
	cmp r5, #1
	beq.n .L08029a1e
	sxth r0, r4
	mov r2, r6
	mov r1, r5
	mov r7, r0
	bl fn_080297c8
	and.w r0, r9, #1
	add r0, r5
	sxth r1, r0
	cmp r1, #1
	ble.n .L08029a5a
	mov.w r0, #0x3fc0
	sdiv r2, r0, r1
	movs r0, #0
	uxth r3, r2
	mul r5, r4, r4
	b.n .L08029a4e
.L08029a1e:
	movs r0, #0
	muls r4, r4, r4
	b.n .L08029a2e
.L08029a24:
	ldrh.w r1, [r6, r0, lsl #1]
	lsrs r2, r1, #6
	strb r2, [r6, r0]
	.inst.n 0x1c40  @ adds r0, r0, #1
.L08029a2e:
	cmp r4, r0
	bgt.n .L08029a24
.L08029a32:
	add sp, #0x28
	pop.w {r4, r5, r6, r7, r8, r9, r10, pc}
.L08029a38:
	ldrh.w r2, [r6, r0, lsl #1]
	cbz r2, .L08029a4c
	cmp r2, #0xff
	beq.n .L08029a60
	lsls r2, r2, #6
	sdiv r2, r2, r1
	strh.w r2, [r6, r0, lsl #1]
.L08029a4c:
	.inst.n 0x1c40  @ adds r0, r0, #1
.L08029a4e:
	cmp r5, r0
	bhi.n .L08029a38
	mov r2, r6
	mov r0, r7
	bl fn_080297c8
.L08029a5a:
	movs r0, #0
	muls r4, r4, r4
	b.n .L08029a70
.L08029a60:
	strh.w r3, [r6, r0, lsl #1]
	b.n .L08029a4c
	nop  @ padding
.L08029a68:
	ldrb.w r1, [r6, r0, lsl #1]
	strb r1, [r6, r0]
	.inst.n 0x1c40  @ adds r0, r0, #1
.L08029a70:
	cmp r4, r0
	bgt.n .L08029a68
	b.n .L08029a32

@ ----------------------------------------------------------------------------
@ fn_08029a76 - draws a white filled block and a second block.
@ Parameters: r0 = param_1, r1 = param_2, r2 = param_3.
@ Clears a block with fn_0801f344, sets its halfword at offset 4 to
@ rgb_to_565_0801d8b2(0xff, 0xff, 0xff), draws with fn_0801f31c(r0, block, r1),
@ builds a second block with fn_0801e7b4 and draws with fn_0801e274(r0, block2,
@ r1, r2, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_08029a76,"ax",%progbits
	.global fn_08029a76
	.thumb_func
	.type fn_08029a76, %function
fn_08029a76:
	push {r4, r5, r6, r7, lr}
	sub sp, #0x5c
	mov r7, r0
	mov r4, r2
	mov r5, r1
	add r0, sp, #4
	bl fn_0801f344
	movs r2, #0xff
	mov r1, r2
	mov r0, r2
	bl rgb_to_565_0801d8b2
	str r0, [sp, #0]
	ldrh.w r0, [sp, #0]
	str r0, [sp, #0]
	ldrh.w r0, [sp, #0]
	strh.w r0, [sp, #8]
	movs r6, #0
	mov r2, r5
	add r1, sp, #4
	mov r0, r7
	bl fn_0801f31c
	add r0, sp, #0x3c
	bl fn_0801e7b4
	mov r3, r4
	mov r2, r5
	add r1, sp, #0x3c
	mov r0, r7
	str r6, [sp, #0]
	bl fn_0801e274
	add sp, #0x5c
	pop {r4, r5, r6, r7, pc}

