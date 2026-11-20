@ gfx_09.s - graphics module part 9: a nine-strip corner/edge/interior fill routine and two tick-drawing routines
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08018dd4 - draws a rectangle in nine strips (four corners, four edges,
@ interior) through the per-scanline draw routine 0x0801f730.
@ Parameters: r0 = object (its word +8 is passed as r2 to every 0x08011e4c call),
@ r1 = parameter block (shorts at +0x00 corner limit, +0x2c, +0x2e, +0x30, +0x32,
@ +0x34; bytes at +2, +3, +0x36), r2 = rectangle of four halfwords (left +0,
@ top +2, right +4, bottom +6). No return value.
@ The body is one contiguous range 0x08018dd4..0x08019988; the five 2-byte nops
@ at 0x080193b6, 0x08019506, 0x08019556, 0x08019766, 0x0801992e are alignment
@ padding outside the executed code.
@ Returns at once (0x08018ecc, b 0x080196cc, pop) when short [r1+0x2e] is 0, when
@ byte [r1+0x36] is 2 or less, or when short [r1+0x2e] is 1 with short [r1+0x34]
@ not above 0 and shorts [r1+0x30] and [r1+0x32] both 0.
@ Rectangle A at sp+0x28 = (left + s30 - s34, top + s32 - s34, right + s30 + s34,
@ bottom + s32 + s34) where sNN = short [r1+NN]; rectangle W at sp+0x4c = A grown
@ by s2e/2 + 1 on every side (halving truncates toward zero); alpha word sp+0xa4 =
@ byte [r1+0x36], set to 0xff when above 0xfd.
@ Calls 0x08011e4c(sp+0x9c, W, word [r0+8]); a zero result returns.
@ Copies the r2 rectangle into sp+0x74 with 0x0801d00c and calls
@ 0x0801d082(sp+0x74, -1, -1); r9 = min(short [r1], min(0x0801d06a, 0x0801d01e of
@ sp+0x74) / 2); r4 = min(short [r1], min(0x0801d06a, 0x0801d01e of A) / 2).
@ r5 = s2e + r4; allocates r5*r5*2 bytes with 0x08022bac (pointer in sp+0x40) and
@ fills it with 0x080298f8(A, buffer, s2e, r4).
@ r7 = 1 only when 0x0801ecd0(W) is 0 and byte [r1+3] is 0xff or more and byte
@ [r1+2] is 0; otherwise r7 = 0 and the record 0x0801f1a8(sp+0x80, sp+0x74, r9, 1)
@ is made, with 0x0801e910(sp+0x80, 0) stored at sp+0x98 (sp+0x98 = -1 when r7 = 1).
@ Allocates a row buffer fp with 0x08022bac (size 0x0801d06a of W), clears the
@ 0x1c-byte draw block at sp+0x54 with 0x08022e6c and sets its word +0 = sp
@ (address of the strip rectangle at sp+0), word +0x0c (sp+0x60) = row pointer,
@ word +0x14 = sp, halfword +8 = s2c, byte +0x18 (sp+0x6c) = byte [r1+0x36],
@ byte +0x19 = byte [r1+2], byte +0x10 (sp+0x64) = mode.
@ midX = W.left + (W.width)/2, midY = W.top + (W.height)/2.
@ Nine strips are drawn, each: strip rectangle at sp+0, clip
@ 0x08011e4c(sp+0x18, sp, [r0+8]) (zero skips), test 0x08011e9c(sp+0x18, sp+0x74,
@ r9) (nonzero skips), width = clipped right - left + 1 (zero or less skips), then
@ one 0x0801f730(r0, sp+0x54) call per clipped scanline.
@ Strip 1 0x08018ff4 top-right corner: x from max(W.right - r5 + 1, midX) to
@ W.right, y from W.top to min(W.top + r5 - 1, midY), rows ascending, buffer
@ pointer = buffer + (clipTop - W.top)*r5 + (clipLeft - (W.right - r5)) - 1;
@ strip 2 0x080190a6 bottom-right corner: y from max(W.bottom - r5 + 1, midY + 1)
@ to W.bottom, rows descending from the clipped bottom, pointer = buffer +
@ (rectBottom - clipBottom)*r5 + (clipLeft - (W.right - r5)) - 1.
@ In strips 1, 2, 7, 8 (corners) the flag equals r7 (r7 is only ever 0 or 1; when
@ r7 is 1, 0x08011f7c(clip, sp+0x74, r9) is called and either result leaves the
@ flag at 1): flagged rows pass the buffer pointer directly as row pointer
@ (pointer += r5 per row) with mode byte 2; unflagged rows copy r5 bytes with
@ 0x08022ce0(fp, pointer, r5), set mode = 0x0801ec54(fp, clipLeft, y, width) (a
@ result of 1 becomes 2) and pass fp.
@ Strip 3 0x080191c6 top edge: x from W.left + r5 to W.right - r5, y from W.top to
@ min(W.top + r5 - 1, midY), pointer = buffer + (clipTop - stripTop)*r5, one byte
@ per row: flagged rows (flag = r7, row pointer word 0; when r7 is 1,
@ 0x08011f7c(clip, sp+0x74, r9) is called and its result does not change the flag)
@ store the byte (scaled to byte * byte[r1+0x36] >> 8 when the capped alpha is not
@ 0xff) in sp+0x6c, unflagged rows fill fp with 0x08022e08(fp, byte, width) and set
@ mode with 0x0801ec54; strip 4 0x0801930c bottom edge: y from max(W.bottom - r5 +
@ 1, midY + 1) to W.bottom, rows descending, pointer = buffer + (stripBottom -
@ clipBottom)*r5 advanced by r5 per row, same row handling with r7 in place of the
@ flag and the 0x08011f7c result unused; 0x0801942c restores byte sp+0x6c from
@ byte [r1+0x36].
@ Strip 5 0x0801942c right side: x from max(W.right - r5 + 1, midX) to W.right, y
@ from min(W.top + r5, midY + 1) to max(W.bottom - r5, midY); from 0x08019490 r6 =
@ r9 (the parameter block pointer is no longer held); pointer = buffer +
@ (r5-1)*r5 + (clipLeft - (W.right - r5)) - 1; the flag is r7 (0x08011f7c is
@ called when r7 is 1 and its result is unused); flagged rows pass the pointer
@ unchanged as row pointer to every row (mode byte 2); unflagged rows pass fp as
@ row pointer, copy width bytes with 0x08022ce0(fp, pointer, width) and take the
@ mode from 0x0801ec54.
@ Mirror loop 0x08019550..0x08019589: for each of the r5 rows of r5 bytes at the
@ start of the buffer swaps byte i with byte r5-1-i for i below r5/2.
@ Strip 6 0x0801958a left side: x from W.left to min(W.left + r5 - 1, midX - 1),
@ same y span as strip 5, pointer = buffer + (r5-1)*r5 + (clipLeft - stripLeft),
@ flag and row handling as strip 5; strip 7 0x080196a4 top-left corner: x as strip
@ 6, y from W.top to min(W.top + r5 - 1, midY), rows ascending, pointer = buffer +
@ (clipTop - stripTop)*r5 + (clipLeft - stripLeft) advanced by r5 per row; strip 8
@ 0x0801978e bottom-left corner: y from max(W.bottom - r5 + 1, midY + 1) to
@ W.bottom, rows descending, pointer = buffer + (stripBottom - clipBottom)*r5 +
@ (clipLeft - stripLeft) advanced by r5 per row, width kept in sl.
@ Strip 9 0x0801989e interior: x from W.left + r5 to W.right - r5, y from W.top +
@ r5 to W.bottom - r5, per row 0x08022ec8(fp, width) fills 0xff, mode =
@ 0x0801ec54(fp, clipLeft, y, width) (no remap), row pointer fp.
@ Epilogue 0x0801996a: when r7 is 0 calls 0x0801ec98(sp+0x80) and
@ 0x0801f2fc(word sp+0x98); frees the corner buffer and the row buffer with
@ 0x08022c44; add sp,#180 and pop r4-r11,pc at 0x08019984..0x08019988.
@ ----------------------------------------------------------------------------
	.section .text.fn_08018dd4,"ax",%progbits
	.p2align 2
	.global fn_08018dd4
	.thumb_func
	.type fn_08018dd4, %function
fn_08018dd4:
	push.w {r0, r1, r2, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	ldrsh.w r0, [r1, #0x2e]
	sub sp, #0xa8
	mov r4, r2
	mov r6, r1
	cmp r0, #0
.L08018de4:
	beq.n .L08018ecc
	ldrb.w r1, [r6, #0x36]
	cmp r1, #2
	bls.n .L08018ecc
	cmp r0, #1
	bne.n .L08018e04
	ldrsh.w r0, [r6, #0x34]
	cmp r0, #0
	bgt.n .L08018e04
	ldrh r0, [r6, #0x30]
	cbnz r0, .L08018e04
	ldrh r0, [r6, #0x32]
	cmp r0, #0
	beq.n .L08018de4
.L08018e04:
	ldrh r0, [r4, #0x0]
	ldrh r1, [r6, #0x30]
	adds r2, r0, r1
	ldrh r0, [r6, #0x34]
	subs r5, r2, r0
	strh.w r5, [sp, #0x28]
	ldrh r2, [r4, #0x4]
	add r1, r2
	adds r3, r1, r0
	strh.w r3, [sp, #0x2c]
	ldrh r0, [r4, #0x2]
	ldrh r1, [r6, #0x32]
	add r0, r1
	ldrh r1, [r6, #0x34]
	subs r2, r0, r1
	strh.w r2, [sp, #0x2a]
	ldrh r0, [r4, #0x6]
	ldrh r1, [r6, #0x32]
	add r0, r1
	ldrh r1, [r6, #0x34]
	add r1, r0
	strh.w r1, [sp, #0x2e]
	ldrsh.w r0, [r6, #0x2e]
	add.w r0, r0, r0, lsr #31
	sub.w r5, r5, r0, asr #1
	.inst.n 0x1e6d  @ subs r5, r5, #1
	strh.w r5, [sp, #0x4c]
	movs r5, #1
	add.w r0, r5, r0, asr #1
	add r0, r3
	strh.w r0, [sp, #0x50]
	ldrsh.w r0, [r6, #0x2e]
	add.w r0, r0, r0, lsr #31
	sub.w r0, r2, r0, asr #1
	.inst.n 0x1e40  @ subs r0, r0, #1
	strh.w r0, [sp, #0x4e]
	ldrsh.w r0, [r6, #0x2e]
	add.w r0, r0, r0, lsr #31
	add.w r0, r5, r0, asr #1
	add r0, r1
	strh.w r0, [sp, #0x52]
	ldrb.w r0, [r6, #0x36]
	str r0, [sp, #0xa4]
	cmp r0, #0xfd
	bls.n .L08018e88
	movs r0, #0xff
	str r0, [sp, #0xa4]
.L08018e88:
	ldr r0, [sp, #0xa8]
	add r1, sp, #0x4c
	ldr r2, [r0, #8]
	add r0, sp, #0x9c
	bl rect_intersect
	cmp r0, #0
	beq.n .L08018de4
	mov r1, r4
	add r0, sp, #0x74
	bl copy_rect_0801d00c
	mov.w r8, #-1
	mov r1, r8
	mov r2, r8
	add r0, sp, #0x74
	bl rect_grow
	ldrsh.w r9, [r6]
	add r0, sp, #0x74
	bl rect_width_0801d06a
	mov r4, r0
	add r0, sp, #0x74
	bl rect_height_0801d01e
	cmp r4, r0
	add r0, sp, #0x74
	bge.n .L08018ece
	bl rect_width_0801d06a
	b.n .L08018ed2
.L08018ecc:
	b.n .L080196cc
.L08018ece:
	bl rect_height_0801d01e
.L08018ed2:
	cmp.w r9, r0, asr #1
	ble.n .L08018edc
	asr.w r9, r0, #1
.L08018edc:
	ldrsh.w r4, [r6]
	add r0, sp, #0x28
	bl rect_width_0801d06a
	mov r5, r0
	add r0, sp, #0x28
	bl rect_height_0801d01e
	cmp r5, r0
	add r0, sp, #0x28
	bge.n .L08018efa
	bl rect_width_0801d06a
	b.n .L08018efe
.L08018efa:
	bl rect_height_0801d01e
.L08018efe:
	cmp.w r4, r0, asr #1
	ble.n .L08018f06
	asrs r4, r0, #1
.L08018f06:
	ldrsh.w r0, [r6, #0x2e]
	adds r5, r0, r4
	mul.w r0, r5, r5
	lsls r0, r0, #1
	bl fn_08022bac
	str r0, [sp, #0x40]
	mov r1, r0
	ldrsh.w r2, [r6, #0x2e]
	mov r3, r4
	add r0, sp, #0x28
	bl fn_080298f8
	add r0, sp, #0x4c
	bl fn_0801ecd0
	movs r7, #1
	cbnz r0, .L08018f3a
	ldrb r0, [r6, #3]
	cmp r0, #0xff
	blo.n .L08018f3a
	ldrb r0, [r6, #2]
	cbz r0, .L08018f54
.L08018f3a:
	movs r7, #0
	movs r3, #1
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x80
	bl fn_0801f1a8
	movs r1, #0
	add r0, sp, #0x80
	bl table_slot_insert
	str r0, [sp, #0x98]
	b.n .L08018f58
.L08018f54:
	str.w r8, [sp, #0x98]
.L08018f58:
	add r0, sp, #0x4c
	bl rect_width_0801d06a
	bl fn_08022bac
	mov r11, r0
	movs r1, #0x1c
	add r0, sp, #0x54
	bl clear_bytes
	str.w sp, [sp, #0x54]
	str.w r11, [sp, #0x60]
	str.w sp, [sp, #0x68]
	ldrh r0, [r6, #0x2c]
	strh.w r0, [sp, #0x5c]
	ldrb.w r0, [r6, #0x36]
	strb.w r0, [sp, #0x6c]
	ldrb r0, [r6, #2]
	strb.w r0, [sp, #0x6d]
	ldrh.w r0, [sp, #0x50]
	ldrh.w r2, [sp, #0x4c]
	strh.w r0, [sp, #4]
	subs r1, r0, r2
	.inst.n 0x1c49  @ adds r1, r1, #1
	sxth r1, r1
	add.w r1, r1, r1, lsr #31
	add.w r1, r2, r1, asr #1
	sxth.w r10, r1
	ldrh.w r2, [sp, #0x52]
	ldrh.w r1, [sp, #0x4e]
	subs r0, r0, r5
	subs r2, r2, r1
	.inst.n 0x1c52  @ adds r2, r2, #1
	sxth r2, r2
	add.w r2, r2, r2, lsr #31
	add.w r2, r1, r2, asr #1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r4, r2
	sxth r0, r0
	subs r2, r5, #1
	strh.w r0, [sp]
	strh.w r1, [sp, #2]
	add r1, r2
	sxth r1, r1
	str r2, [sp, #0x24]
	strh.w r1, [sp, #6]
	mov r2, r10
	cmp r0, r10
	bgt.n .L08018fe4
	mov r0, r2
.L08018fe4:
	strh.w r0, [sp]
	cmp r1, r4
	blt.n .L08018fee
	mov r1, r4
.L08018fee:
	ldr r0, [sp, #0xa8]
	strh.w r1, [sp, #6]
	mov r1, sp
	ldr r2, [r0, #8]
	add r0, sp, #0x18
	bl rect_intersect
	cbz r0, .L08019076
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011e9c
	cbnz r0, .L08019076
	ldrh.w r0, [sp, #0x1c]
	ldrsh.w r1, [sp, #0x18]
	ldrsh.w r2, [sp, #0x1a]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	str r0, [sp, #0x20]
	ldrsh.w r3, [sp, #0x4e]
	ldr r0, [sp, #0x40]
	subs r2, r2, r3
	mla r0, r2, r5, r0
	ldrsh.w r2, [sp, #0x50]
	subs r2, r2, r5
	subs r1, r1, r2
	add r0, r1
	.inst.n 0x1e40  @ subs r0, r0, #1
	str r0, [sp, #0x14]
	cbz r7, .L0801904e
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011f7c
	cbz r0, .L0801904e
	movs r0, #1
	str r0, [sp, #0x3c]
	b.n .L08019050
.L0801904e:
	str r7, [sp, #0x3c]
.L08019050:
	ldr r0, [sp, #0x20]
	cmp r0, #0
	ble.n .L080190a6
	ldrh.w r0, [sp, #0x18]
	strh.w r0, [sp]
	ldrh.w r0, [sp, #0x1c]
	strh.w r0, [sp, #4]
	movs r0, #2
	str.w r11, [sp, #0x60]
	strb.w r0, [sp, #0x64]
	ldrsh.w r8, [sp, #0x1a]
	b.n .L0801909e
.L08019076:
	b.n .L080190a6
.L08019078:
	strh.w r8, [sp, #2]
	ldr r0, [sp, #0x3c]
	strh.w r8, [sp, #6]
	cbz r0, .L080190e2
	ldr r0, [sp, #0x14]
	str r0, [sp, #0x60]
.L08019088:
	add r1, sp, #0x54
	ldr r0, [sp, #0xa8]
	bl fn_0801f730
	ldr r0, [sp, #0x14]
	add r0, r5
	str r0, [sp, #0x14]
	add.w r0, r8, #1
	sxth.w r8, r0
.L0801909e:
	ldrsh.w r1, [sp, #0x1e]
	cmp r1, r8
	bge.n .L08019078
.L080190a6:
	ldrh.w r0, [sp, #0x50]
	strh.w r0, [sp, #4]
	subs r0, r0, r5
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	strh.w r0, [sp]
	ldrh.w r2, [sp, #0x52]
	strh.w r2, [sp, #6]
	subs r1, r2, r5
	.inst.n 0x1c49  @ adds r1, r1, #1
	sxth r1, r1
	strh.w r1, [sp, #2]
	mov r2, r10
	cmp r0, r10
	bgt.n .L080190d2
	mov r0, r2
.L080190d2:
	strh.w r0, [sp]
	adds r0, r4, #1
	str r0, [sp, #0x44]
	cmp r1, r0
	ble.n .L0801910c
	mov r0, r1
	b.n .L0801910e
.L080190e2:
	b.n .L080190e4
.L080190e4:
	mov r2, r5
	mov r0, r11
	ldr r1, [sp, #0x14]
	bl copy_bytes_08022ce0
	ldrsh.w r1, [sp, #0x18]
	mov r2, r8
	mov r0, r11
	ldr r3, [sp, #0x20]
	bl fn_0801ec54
	strb.w r0, [sp, #0x64]
	cmp r0, #1
	bne.n .L08019088
	movs r0, #2
	strb.w r0, [sp, #0x64]
	b.n .L08019088
.L0801910c:
	adds r0, r4, #1
.L0801910e:
	strh.w r0, [sp, #2]
	ldr r0, [sp, #0xa8]
	mov r1, sp
	ldr r2, [r0, #8]
	add r0, sp, #0x18
	bl rect_intersect
	cbz r0, .L08019196
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011e9c
	cbnz r0, .L08019196
	ldrh.w r0, [sp, #0x1c]
	ldrsh.w r1, [sp, #0x18]
	ldrsh.w r2, [sp, #6]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	str r0, [sp, #0x20]
	ldrsh.w r3, [sp, #0x1e]
	ldr r0, [sp, #0x40]
	subs r2, r2, r3
	mla r0, r2, r5, r0
	ldrsh.w r2, [sp, #0x50]
	subs r2, r2, r5
	subs r1, r1, r2
	add r0, r1
	.inst.n 0x1e40  @ subs r0, r0, #1
	str r0, [sp, #0x14]
	cbz r7, .L0801916e
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011f7c
	cbz r0, .L0801916e
	movs r0, #1
	str r0, [sp, #0x3c]
	b.n .L08019170
.L0801916e:
	str r7, [sp, #0x3c]
.L08019170:
	ldr r0, [sp, #0x20]
	cmp r0, #0
	ble.n .L080191c6
	ldrh.w r0, [sp, #0x18]
	strh.w r0, [sp]
	ldrh.w r0, [sp, #0x1c]
	strh.w r0, [sp, #4]
	movs r0, #2
	str.w r11, [sp, #0x60]
	strb.w r0, [sp, #0x64]
	ldrsh.w r8, [sp, #0x1e]
	b.n .L080191be
.L08019196:
	b.n .L080191c6
.L08019198:
	strh.w r8, [sp, #2]
	ldr r0, [sp, #0x3c]
	strh.w r8, [sp, #6]
	cbz r0, .L08019212
	ldr r0, [sp, #0x14]
	str r0, [sp, #0x60]
.L080191a8:
	add r1, sp, #0x54
	ldr r0, [sp, #0xa8]
	bl fn_0801f730
	ldr r0, [sp, #0x14]
	add r0, r5
	str r0, [sp, #0x14]
	sub.w r0, r8, #1
	sxth.w r8, r0
.L080191be:
	ldrsh.w r1, [sp, #0x1a]
	cmp r1, r8
	ble.n .L08019198
.L080191c6:
	ldrh.w r0, [sp, #0x4c]
	ldr r1, [sp, #0x24]
	add r0, r5
	strh.w r0, [sp]
	ldrh.w r0, [sp, #0x50]
	subs r0, r0, r5
	strh.w r0, [sp, #4]
	ldrh.w r0, [sp, #0x4e]
	strh.w r0, [sp, #2]
	add r0, r1
	sxth r0, r0
	strh.w r0, [sp, #6]
	cmp r0, r4
	blt.n .L080191f2
	mov r0, r4
.L080191f2:
	strh.w r0, [sp, #6]
	ldr r0, [sp, #0xa8]
	mov r1, sp
	ldr r2, [r0, #8]
	add r0, sp, #0x18
	bl rect_intersect
	cbz r0, .L08019272
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011e9c
	cbz r0, .L0801923c
	b.n .L0801930c
.L08019212:
	b.n .L08019214
.L08019214:
	mov r2, r5
	mov r0, r11
	ldr r1, [sp, #0x14]
	bl copy_bytes_08022ce0
	ldrsh.w r1, [sp, #0x18]
	mov r2, r8
	mov r0, r11
	ldr r3, [sp, #0x20]
	bl fn_0801ec54
	strb.w r0, [sp, #0x64]
	cmp r0, #1
	bne.n .L080191a8
	movs r0, #2
	strb.w r0, [sp, #0x64]
	b.n .L080191a8
.L0801923c:
	ldrh.w r0, [sp, #0x1c]
	ldrh.w r1, [sp, #0x18]
	ldrsh.w r2, [sp, #2]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	str r0, [sp, #0x20]
	ldrsh.w r1, [sp, #0x1a]
	ldr r0, [sp, #0x40]
	subs r1, r1, r2
	mla r0, r1, r5, r0
	str r0, [sp, #0x14]
	cbz r7, .L08019274
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011f7c
	cbz r0, .L08019274
	movs r0, #1
	str r0, [sp, #0x3c]
	b.n .L08019276
.L08019272:
	b.n .L0801930c
.L08019274:
	str r7, [sp, #0x3c]
.L08019276:
	ldr r0, [sp, #0x20]
	cmp r0, #0
	ble.n .L0801930c
	ldr r0, [sp, #0x3c]
	cbz r0, .L0801929a
	movs r0, #0
	str r0, [sp, #0x60]
.L08019284:
	ldrh.w r0, [sp, #0x18]
	strh.w r0, [sp]
	ldrh.w r0, [sp, #0x1c]
	strh.w r0, [sp, #4]
	ldrsh.w r0, [sp, #0x1a]
	b.n .L08019302
.L0801929a:
	str.w r11, [sp, #0x60]
	b.n .L08019284
.L080192a0:
	strh.w r8, [sp, #2]
	ldr r0, [sp, #0x3c]
	strh.w r8, [sp, #6]
	cbz r0, .L080192c6
	ldr r0, [sp, #0xa4]
	cmp r0, #0xff
	ldr r0, [sp, #0x14]
	ldrb r0, [r0]
	beq.n .L080192c0
	ldrb.w r1, [r6, #0x36]
	smulbb r0, r0, r1
	lsrs r0, r0, #8
.L080192c0:
	strb.w r0, [sp, #0x6c]
	b.n .L080192ee
.L080192c6:
	ldr r0, [sp, #0x14]
	ldr r2, [sp, #0x20]
	ldrb r1, [r0]
	mov r0, r11
	bl fill_bytes_08022e08
	ldrsh.w r1, [sp, #0x18]
	mov r2, r8
	mov r0, r11
	ldr r3, [sp, #0x20]
	bl fn_0801ec54
	strb.w r0, [sp, #0x64]
	cmp r0, #1
	bne.n .L080192ee
	movs r0, #2
	strb.w r0, [sp, #0x64]
.L080192ee:
	add r1, sp, #0x54
	ldr r0, [sp, #0xa8]
	bl fn_0801f730
	ldr r0, [sp, #0x14]
	add r0, r5
	str r0, [sp, #0x14]
	add.w r0, r8, #1
	sxth r0, r0
.L08019302:
	ldrsh.w r1, [sp, #0x1e]
	mov r8, r0
	cmp r1, r8
	bge.n .L080192a0
.L0801930c:
	ldrb.w r0, [r6, #0x36]
	strb.w r0, [sp, #0x6c]
	ldrh.w r0, [sp, #0x4c]
	add r0, r5
	strh.w r0, [sp]
	ldrh.w r0, [sp, #0x50]
	ldrh.w r1, [sp, #0x52]
	subs r0, r0, r5
	strh.w r0, [sp, #4]
	subs r0, r1, r5
	.inst.n 0x1c40  @ adds r0, r0, #1
	strh.w r1, [sp, #6]
	sxth r0, r0
	ldr r1, [sp, #0x44]
	strh.w r0, [sp, #2]
	cmp r0, r1
	bgt.n .L08019342
	adds r0, r4, #1
.L08019342:
	strh.w r0, [sp, #2]
	ldr r0, [sp, #0xa8]
	mov r1, sp
	ldr r2, [r0, #8]
	add r0, sp, #0x18
	bl rect_intersect
	cbz r0, .L080193b4
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011e9c
	cbnz r0, .L080193b4
	ldrh.w r0, [sp, #0x1c]
	ldrh.w r1, [sp, #0x18]
	ldrsh.w r2, [sp, #0x1e]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	str r0, [sp, #0x20]
	ldrsh.w r1, [sp, #6]
	ldr r0, [sp, #0x40]
	subs r1, r1, r2
	mla r0, r1, r5, r0
	str r0, [sp, #0x14]
	ldr r0, [sp, #0x20]
	cmp r0, #0
	ble.n .L0801942c
	cbz r7, .L0801939a
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011f7c
	movs r0, #0
	str r0, [sp, #0x60]
	b.n .L0801939e
.L0801939a:
	str.w r11, [sp, #0x60]
.L0801939e:
	ldrh.w r0, [sp, #0x18]
	strh.w r0, [sp]
	ldrh.w r0, [sp, #0x1c]
	strh.w r0, [sp, #4]
	ldrsh.w r0, [sp, #0x1e]
	b.n .L08019422
.L080193b4:
	b.n .L0801942c
	nop  @ padding
.L080193b8:
	strh.w r8, [sp, #2]
	strh.w r8, [sp, #6]
	cbz r7, .L080193e6
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011f7c
	ldr r0, [sp, #0xa4]
	cmp r0, #0xff
	ldr r0, [sp, #0x14]
	ldrb r0, [r0]
	beq.n .L080193e0
	ldrb.w r1, [r6, #0x36]
	smulbb r0, r0, r1
	lsrs r0, r0, #8
.L080193e0:
	strb.w r0, [sp, #0x6c]
	b.n .L0801940e
.L080193e6:
	ldr r0, [sp, #0x14]
	ldr r2, [sp, #0x20]
	ldrb r1, [r0]
	mov r0, r11
	bl fill_bytes_08022e08
	ldrsh.w r1, [sp, #0x18]
	mov r2, r8
	mov r0, r11
	ldr r3, [sp, #0x20]
	bl fn_0801ec54
	strb.w r0, [sp, #0x64]
	cmp r0, #1
	bne.n .L0801940e
	movs r0, #2
	strb.w r0, [sp, #0x64]
.L0801940e:
	add r1, sp, #0x54
	ldr r0, [sp, #0xa8]
	bl fn_0801f730
	ldr r0, [sp, #0x14]
	add r0, r5
	str r0, [sp, #0x14]
	sub.w r0, r8, #1
	sxth r0, r0
.L08019422:
	ldrsh.w r1, [sp, #0x1a]
	mov r8, r0
	cmp r1, r8
	ble.n .L080193b8
.L0801942c:
	ldrb.w r0, [r6, #0x36]
	strb.w r0, [sp, #0x6c]
	ldrh.w r0, [sp, #0x50]
	strh.w r0, [sp, #4]
	subs r1, r0, r5
	ldrh.w r0, [sp, #0x4e]
	.inst.n 0x1c49  @ adds r1, r1, #1
	sxth r2, r1
	add r0, r5
	strh.w r2, [sp]
	sxth r0, r0
	strh.w r0, [sp, #2]
	ldrh.w r1, [sp, #0x52]
	ldr r3, [sp, #0x44]
	subs r1, r1, r5
	sxth r1, r1
	strh.w r1, [sp, #6]
	cmp r0, r3
	blt.n .L08019466
	adds r0, r4, #1
.L08019466:
	strh.w r0, [sp, #2]
	cmp r1, r4
	bgt.n .L08019470
	mov r1, r4
.L08019470:
	strh.w r1, [sp, #6]
	mov r0, r10
	cmp r2, r10
	bgt.n .L0801947c
	mov r2, r0
.L0801947c:
	ldr r0, [sp, #0xa8]
	strh.w r2, [sp]
	mov r1, sp
	ldr r2, [r0, #8]
	add r0, sp, #0x18
	bl rect_intersect
	cbz r0, .L080194fe
	mov r2, r9
	mov r6, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011e9c
	cbnz r0, .L080194fe
	ldrh.w r0, [sp, #0x1c]
	ldrsh.w r1, [sp, #0x18]
	ldr r2, [sp, #0x24]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	str r0, [sp, #0x20]
	ldr r0, [sp, #0x40]
	mla r0, r2, r5, r0
	ldrsh.w r2, [sp, #0x50]
	subs r2, r2, r5
	subs r1, r1, r2
	add r0, r1
	.inst.n 0x1e40  @ subs r0, r0, #1
	str r0, [sp, #0x14]
	cbz r7, .L08019500
	mov r2, r6
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011f7c
	cbz r0, .L080194d6
	mov.w r8, #1
	b.n .L080194d8
.L080194d6:
	mov r8, r7
.L080194d8:
	ldr r0, [sp, #0x14]
.L080194da:
	str r0, [sp, #0x60]
	ldr r0, [sp, #0x20]
	cmp r0, #0
	ble.n .L08019550
	ldrh.w r0, [sp, #0x18]
	strh.w r0, [sp]
	ldrh.w r0, [sp, #0x1c]
	strh.w r0, [sp, #4]
	movs r0, #2
	strb.w r0, [sp, #0x64]
	ldrsh.w r6, [sp, #0x1a]
	b.n .L08019548
.L080194fe:
	b.n .L08019550
.L08019500:
	mov r8, r7
	mov r0, r11
	b.n .L080194da
	nop  @ padding
.L08019508:
	strh.w r6, [sp, #2]
	strh.w r6, [sp, #6]
	cmp.w r8, #0
	bne.n .L0801953c
	mov r0, r11
	ldr r2, [sp, #0x20]
	ldr r1, [sp, #0x14]
	bl copy_bytes_08022ce0
	ldrsh.w r1, [sp, #0x18]
	mov r2, r6
	mov r0, r11
	ldr r3, [sp, #0x20]
	bl fn_0801ec54
	strb.w r0, [sp, #0x64]
	cmp r0, #1
	bne.n .L0801953c
	movs r0, #2
	strb.w r0, [sp, #0x64]
.L0801953c:
	add r1, sp, #0x54
	ldr r0, [sp, #0xa8]
	bl fn_0801f730
	.inst.n 0x1c76  @ adds r6, r6, #1
	sxth r6, r6
.L08019548:
	ldrsh.w r0, [sp, #0x1e]
	cmp r0, r6
	bge.n .L08019508
.L08019550:
	movs r2, #0
	ldr r0, [sp, #0x40]
	b.n .L08019586
	nop  @ padding
.L08019558:
	add.w lr, r0, r5
	sub.w r1, lr, #1
	movs r3, #0
	add.w r6, r5, r5, lsr #31
	b.n .L0801957a
.L08019568:
	ldrb.w r12, [r0]
	ldrb.w r8, [r1]
	strb.w r8, [r0], #1
	strb.w r12, [r1], #-1
	.inst.n 0x1c5b  @ adds r3, r3, #1
.L0801957a:
	cmp.w r3, r6, asr #1
	blt.n .L08019568
	.inst.n 0x1c52  @ adds r2, r2, #1
	mov r0, lr
	sxth r2, r2
.L08019586:
	cmp r2, r5
	blt.n .L08019558
	ldrh.w r0, [sp, #0x4c]
	ldr r1, [sp, #0x24]
	strh.w r0, [sp]
	add r0, r1
	sxth r1, r0
	ldrh.w r0, [sp, #0x4e]
	ldr r3, [sp, #0x44]
	add r0, r5
	sxth r0, r0
	strh.w r0, [sp, #2]
	ldrh.w r2, [sp, #0x52]
	strh.w r1, [sp, #4]
	subs r2, r2, r5
	sxth r2, r2
	strh.w r2, [sp, #6]
	cmp r0, r3
	blt.n .L080195bc
	adds r0, r4, #1
.L080195bc:
	strh.w r0, [sp, #2]
	cmp r2, r4
	bgt.n .L080195c6
	mov r2, r4
.L080195c6:
	sub.w r0, r10, #1
	strh.w r2, [sp, #6]
	str r0, [sp, #0x30]
	cmp r1, r0
	blt.n .L080195d6
	mov r1, r0
.L080195d6:
	ldr r0, [sp, #0xa8]
	strh.w r1, [sp, #4]
	mov r1, sp
	ldr r2, [r0, #8]
	add r0, sp, #0x18
	bl rect_intersect
	cbz r0, .L08019654
	mov r2, r9
	mov r6, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011e9c
	cbnz r0, .L08019654
	ldrh.w r0, [sp, #0x1c]
	ldrsh.w r1, [sp, #0x18]
	ldr r2, [sp, #0x24]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	str r0, [sp, #0x20]
	ldr r0, [sp, #0x40]
	mla r0, r2, r5, r0
	ldrsh.w r2, [sp]
	subs r1, r1, r2
	add r0, r1
	str r0, [sp, #0x14]
	cbz r7, .L08019656
	mov r2, r6
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011f7c
	cbz r0, .L0801962c
	mov.w r8, #1
	b.n .L0801962e
.L0801962c:
	mov r8, r7
.L0801962e:
	ldr r0, [sp, #0x14]
.L08019630:
	str r0, [sp, #0x60]
	ldr r0, [sp, #0x20]
	cmp r0, #0
	ble.n .L080196a4
	ldrh.w r0, [sp, #0x18]
	strh.w r0, [sp]
	ldrh.w r0, [sp, #0x1c]
	strh.w r0, [sp, #4]
	movs r0, #2
	strb.w r0, [sp, #0x64]
	ldrsh.w r6, [sp, #0x1a]
	b.n .L0801969c
.L08019654:
	b.n .L080196a4
.L08019656:
	mov r8, r7
	mov r0, r11
	b.n .L08019630
.L0801965c:
	strh.w r6, [sp, #2]
	strh.w r6, [sp, #6]
	cmp.w r8, #0
	bne.n .L08019690
	mov r0, r11
	ldr r2, [sp, #0x20]
	ldr r1, [sp, #0x14]
	bl copy_bytes_08022ce0
	ldrsh.w r1, [sp, #0x18]
	mov r2, r6
	mov r0, r11
	ldr r3, [sp, #0x20]
	bl fn_0801ec54
	strb.w r0, [sp, #0x64]
	cmp r0, #1
	bne.n .L08019690
	movs r0, #2
	strb.w r0, [sp, #0x64]
.L08019690:
	add r1, sp, #0x54
	ldr r0, [sp, #0xa8]
	bl fn_0801f730
	.inst.n 0x1c76  @ adds r6, r6, #1
	sxth r6, r6
.L0801969c:
	ldrsh.w r0, [sp, #0x1e]
	cmp r0, r6
	bge.n .L0801965c
.L080196a4:
	ldrh.w r0, [sp, #0x4c]
	ldr r1, [sp, #0x24]
	strh.w r0, [sp]
	add r0, r1
	ldrh.w r1, [sp, #0x4e]
	ldr r2, [sp, #0x24]
	strh.w r1, [sp, #2]
	add r1, r2
	sxth r0, r0
	strh.w r0, [sp, #4]
	sxth r1, r1
	strh.w r1, [sp, #6]
	ldr r2, [sp, #0x30]
	b.n .L080196ce
.L080196cc:
	b.n .L08019984
.L080196ce:
	cmp r0, r2
	blt.n .L080196d6
	sub.w r0, r10, #1
.L080196d6:
	strh.w r0, [sp, #4]
	cmp r1, r4
	blt.n .L080196e0
	mov r1, r4
.L080196e0:
	ldr r0, [sp, #0xa8]
	strh.w r1, [sp, #6]
	mov r1, sp
	ldr r2, [r0, #8]
	add r0, sp, #0x18
	bl rect_intersect
	cbz r0, .L08019764
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011e9c
	cbnz r0, .L08019764
	ldrh.w r0, [sp, #0x1c]
	ldrsh.w r1, [sp, #0x18]
	ldrsh.w r2, [sp, #0x1a]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	str r0, [sp, #0x20]
	ldrsh.w r3, [sp, #2]
	ldr r0, [sp, #0x40]
	subs r2, r2, r3
	mla r0, r2, r5, r0
	ldrsh.w r2, [sp]
	subs r1, r1, r2
	add.w r8, r1, r0
	cbz r7, .L0801973c
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011f7c
	cbz r0, .L0801973c
	movs r0, #1
	str r0, [sp, #0x3c]
	b.n .L0801973e
.L0801973c:
	str r7, [sp, #0x3c]
.L0801973e:
	ldr r0, [sp, #0x20]
	str.w r11, [sp, #0x60]
	cmp r0, #0
	ble.n .L0801978e
	ldrh.w r0, [sp, #0x18]
	strh.w r0, [sp]
	ldrh.w r0, [sp, #0x1c]
	strh.w r0, [sp, #4]
	movs r0, #2
	strb.w r0, [sp, #0x64]
	ldrsh.w r6, [sp, #0x1a]
	b.n .L08019786
.L08019764:
	b.n .L0801978e
	nop  @ padding
.L08019768:
	strh.w r6, [sp, #2]
	ldr r0, [sp, #0x3c]
	strh.w r6, [sp, #6]
	cbz r0, .L080197e8
	str.w r8, [sp, #0x60]
.L08019778:
	add r1, sp, #0x54
	ldr r0, [sp, #0xa8]
	bl fn_0801f730
	.inst.n 0x1c76  @ adds r6, r6, #1
	add r8, r5
	sxth r6, r6
.L08019786:
	ldrsh.w r0, [sp, #0x1e]
	cmp r0, r6
	bge.n .L08019768
.L0801978e:
	ldrh.w r0, [sp, #0x4c]
	strh.w r0, [sp]
	ldr r1, [sp, #0x24]
	ldrh.w r2, [sp, #0x52]
	add r0, r1
	sxth r1, r0
	subs r0, r2, r5
	strh.w r1, [sp, #4]
	.inst.n 0x1c40  @ adds r0, r0, #1
	strh.w r2, [sp, #6]
	sxth r0, r0
	ldr r2, [sp, #0x44]
	strh.w r0, [sp, #2]
	cmp r0, r2
	bgt.n .L080197ba
	adds r0, r4, #1
.L080197ba:
	strh.w r0, [sp, #2]
	ldr r0, [sp, #0x30]
	cmp r1, r0
	blt.n .L080197c8
	sub.w r1, r10, #1
.L080197c8:
	ldr r0, [sp, #0xa8]
	strh.w r1, [sp, #4]
	mov r1, sp
	ldr r2, [r0, #8]
	add r0, sp, #0x18
	bl rect_intersect
	cbz r0, .L0801984e
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011e9c
	cbz r0, .L08019812
	b.n .L0801989e
.L080197e8:
	b.n .L080197ea
.L080197ea:
	mov r2, r5
	mov r1, r8
	mov r0, r11
	bl copy_bytes_08022ce0
	ldrsh.w r1, [sp, #0x18]
	mov r2, r6
	mov r0, r11
	ldr r3, [sp, #0x20]
	bl fn_0801ec54
	strb.w r0, [sp, #0x64]
	cmp r0, #1
	bne.n .L08019778
	movs r0, #2
	strb.w r0, [sp, #0x64]
	b.n .L08019778
.L08019812:
	ldrh.w r0, [sp, #0x1c]
	ldrsh.w r1, [sp, #0x18]
	ldrsh.w r2, [sp, #6]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth.w r10, r0
	ldrsh.w r3, [sp, #0x1e]
	ldr r0, [sp, #0x40]
	subs r2, r2, r3
	mla r0, r2, r5, r0
	ldrsh.w r2, [sp]
	subs r1, r1, r2
	adds r6, r1, r0
	cbz r7, .L08019850
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011f7c
	cbz r0, .L08019850
	mov.w r8, #1
	b.n .L08019852
.L0801984e:
	b.n .L0801989e
.L08019850:
	mov r8, r7
.L08019852:
	str.w r11, [sp, #0x60]
	cmp.w r10, #0
	ble.n .L0801989e
	ldrh.w r0, [sp, #0x18]
	strh.w r0, [sp]
	ldrh.w r0, [sp, #0x1c]
	strh.w r0, [sp, #4]
	movs r0, #2
	strb.w r0, [sp, #0x64]
	ldrsh.w r4, [sp, #0x1e]
	b.n .L08019896
.L08019878:
	strh.w r4, [sp, #2]
	strh.w r4, [sp, #6]
	cmp.w r8, #0
	beq.n .L080198e6
	str r6, [sp, #0x60]
.L08019888:
	add r1, sp, #0x54
	ldr r0, [sp, #0xa8]
	bl fn_0801f730
	.inst.n 0x1e64  @ subs r4, r4, #1
	add r6, r5
	sxth r4, r4
.L08019896:
	ldrsh.w r0, [sp, #0x1a]
	cmp r0, r4
	ble.n .L08019878
.L0801989e:
	ldrh.w r0, [sp, #0x4c]
	mov r1, sp
	add r0, r5
	strh.w r0, [sp]
	ldrh.w r0, [sp, #0x50]
	subs r0, r0, r5
	strh.w r0, [sp, #4]
	ldrh.w r0, [sp, #0x4e]
	str.w r11, [sp, #0x60]
	add r0, r5
	strh.w r0, [sp, #2]
	ldrh.w r0, [sp, #0x52]
	subs r0, r0, r5
	strh.w r0, [sp, #6]
	ldr r0, [sp, #0xa8]
	ldr r2, [r0, #8]
	add r0, sp, #0x18
	bl rect_intersect
	cbz r0, .L08019954
	mov r2, r9
	add r1, sp, #0x74
	add r0, sp, #0x18
	bl fn_08011e9c
	cbz r0, .L0801990e
	b.n .L0801996a
.L080198e6:
	mov r2, r5
	mov r1, r6
	mov r0, r11
	bl copy_bytes_08022ce0
	ldrsh.w r1, [sp, #0x18]
	mov r3, r10
	mov r2, r4
	mov r0, r11
	bl fn_0801ec54
	strb.w r0, [sp, #0x64]
	cmp r0, #1
	bne.n .L08019888
	movs r0, #2
	strb.w r0, [sp, #0x64]
	b.n .L08019888
.L0801990e:
	ldrsh.w r1, [sp, #0x1c]
	ldrsh.w r0, [sp, #0x18]
	subs r2, r1, r0
	.inst.n 0x1c52  @ adds r2, r2, #1
	sxth r5, r2
	cmp r5, #0
	ble.n .L0801996a
	strh.w r1, [sp, #4]
	strh.w r0, [sp]
	ldrsh.w r4, [sp, #0x1a]
	b.n .L08019962
	nop  @ padding
.L08019930:
	strh.w r4, [sp, #2]
	strh.w r4, [sp, #6]
	mov r1, r5
	mov r0, r11
	bl fill_bytes_ff
	ldrsh.w r1, [sp, #0x18]
	mov r3, r5
	mov r2, r4
	mov r0, r11
	bl fn_0801ec54
	strb.w r0, [sp, #0x64]
	b.n .L08019956
.L08019954:
	b.n .L0801996a
.L08019956:
	add r1, sp, #0x54
	ldr r0, [sp, #0xa8]
	bl fn_0801f730
	.inst.n 0x1c64  @ adds r4, r4, #1
	sxth r4, r4
.L08019962:
	ldrsh.w r0, [sp, #0x1e]
	cmp r0, r4
	bge.n .L08019930
.L0801996a:
	cbnz r7, .L08019978
	add r0, sp, #0x80
	bl fn_0801ec98
	ldr r0, [sp, #0x98]
	bl table_slot_clear
.L08019978:
	ldr r0, [sp, #0x40]
	bl fn_08022c44
	mov r0, r11
	bl fn_08022c44
.L08019984:
	add sp, #0xb4
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short 0x0000  @ padding

@ ----------------------------------------------------------------------------
@ fn_0801998c - draws a series of rotated ticks around a centre point, one series
@ per node of the object's first list, with "%d" number labels on major steps.
@ Parameters: r0 = object (words +0x24 and +0x30 are list descriptors), r1 =
@ drawing target (stored by 0x08023a0c as the first word of the 0x48-byte record
@ at sp+0x18, also passed to 0x0801e274 and 0x0801e8b8), r2 = pointer to a
@ rectangle of 4 halfwords (left signed at +0, top at +2, right at +4, bottom at
@ +6). No return value. Entry: push {r0,r1,r2,r4-r11,lr}, sub sp,#0x160.
@ Sizes: width = sxth(right - left + 1), height = sxth(bottom - top + 1); r5 =
@ min(width/2, height/2) (each halved toward zero with add x lsr 31 / asr 1;
@ cmp.w r5, r0 asr 1 at 0x080199b6, blt at 0x080199ba); centre = (left + r5,
@ top + r5) stored as halfwords at sp+0x10 and sp+0x12.
@ Setup: 0x0801e8d2(sp+0x90); 0x080250b6(object, 0x60000, sp+0x90); byte
@ [sp+0x99] |= 0x10; 0x0801e7b4(sp+0x70); 0x0802501a(object, 0x60000, sp+0x70);
@ 0x08023a0c(sp+0x18, r1); word [sp+0x1c] = 0x08050f30 (literal 0x08019d64); word
@ [sp+0x20] = 3; word [sp+0x30] = sp+0x90; word [sp+0x4c] = 0x60000; [sp+0xf4] =
@ object+0x24; first node = 0x08012600(object+0x24) (word at object+0x2c, 0 for a
@ null argument); the loop at 0x08019d56 ends at the return (add sp,#0x16c,
@ pop.w {r4-r11,pc}) when the node is 0; the next node is
@ 0x080125fa(object+0x24, node) (word at [object+0x24] + node).
@ Per node r4 (0x08019a1e): d = r5 - ushort[r4+4]; rectangle (cx-d, cy-d, cx+d,
@ cy+d) at sp+0x130 and 0x0801f1a8(sp+0x104, sp+0x130, 0x7fff, 1); r11 = sxth(r5
@ - ushort[r4+0xc]); rectangle (cx-r11, cy-r11, cx+r11-1, cy+r11-1) at sp+0xfc
@ and 0x0801f1a8(sp+0xb4, sp+0xfc, 0x7fff, 1); rectangle (cx-r5, cy-r5, cx+r5-1,
@ cy+r5-1) at sp+0x138 and 0x0801f1a8(sp+0x9c, sp+0x138, 0x7fff, 0);
@ 0x0801e910(sp+0x9c, 0) with the slot index stored at [sp+0xec].
@ Step counter: r8 = ushort[r4+0xa] - 1, or 0xffff when that halfword is 0; r7 =
@ 0 counts steps while ushort[r4+2] > r7 (bhi at 0x08019d32); each step does r8 +=
@ 1 (32-bit add, no wrap at 16 bits), r10 = 0, and when r8 == ushort[r4+0xa] sets
@ r8 = 0 and r10 = 1 (a major step); with ushort[r4+0xa] = 0 no step is major.
@ Step value: r9 = 0x08022b12(r7, 0, ushort[r4+2] - 1, word [r4+0x14], stack word
@ [r4+0x18]) stored at [sp+0x58]; for a major step colour word = [r4+8] and length
@ = sxth(ushort[r4+0xe]), otherwise colour word = [r4+0] and length =
@ sxth(ushort[r4+6]); stored at [sp+0xd4], [sp+0xf0] (colour) and [sp+0xd0],
@ [sp+0x140] (length).
@ Second list: [sp+0x60] = object+0x30; node = 0x08012600(object+0x30), next node
@ = 0x080125fa(object+0x30, node); a node is used when byte [node+4] == 2 and
@ signed [node+8] <= r9 <= signed [node+0xc] (bgt at 0x08019b3a, blt at
@ 0x08019b40); then length += ushort[node+0x10] (sxth); when ushort[node+0x12] ==
@ ushort[node+0x14] the colour halfword [sp+0xd4] = ushort[node+0x12].
@ Otherwise alpha = uxtb(0x08022b12(r9, start, end, 0, stack 0xff)) with
@ start/end = [node+8]/[node+0xc] when bit 0 of byte [node+0x16] is set and
@ [r4+0x14]/[r4+0x18] when it is clear; w = (alpha + 4) >> 3; with the mask
@ 0x07e0f81f (word 0x08019d68) and the two RGB565 halfwords c0 =
@ ushort[node+0x12], c1 = ushort[node+0x14] spread as x | x << 16 and masked:
@ colour = (c0 + (((c1 - c0) * w) >> 5)) & mask, folded back with | >> 16 and
@ stored as the word [sp+0xd4].
@ Angle: r6 = ushort[r4+0x1e] * 10 * r7 / (ushort[r4+2] - 1) (signed divide,
@ 0x08019bc2) + 10 * sxth(ushort[r4+0x20]); halfword [sp+0x90] = colour, halfword
@ [sp+0x92] = length; point (x, y) at sp+0x144 with x = cx + r5 + max(r5, 0x8f)
@ (signed cmp r5,#0x8f at 0x08019bca) and y = cy; 0x08026878(sp+0x144, r6,
@ 0x100, sp+0x10); words [sp+0x3c] = sp+0x10, [sp+0x40] = sp+0x144, [sp+0x2c] =
@ sp+0x70, [sp+0x50] = r7.
@ Major step (r10 != 0): 0x0801f2fc([sp+0xec]); point (cx + r11 - ushort[r4+0x10],
@ cy) at sp+0x68 rotated with 0x08026878(sp+0x68, r6, 0x100, sp+0x10);
@ 0x08022ce0(sp+0xcc, sp+0x70, 0x20) copies the record; [sp+0x2c] = sp+0xcc;
@ 0x0801033c(sp+0x14c, 0x10, "%d" (the address 0x08019d6c, adr r2 at 0x08019c5e,
@ holds the bytes 0x25 0x64 0x00, not a pointer word), r9); [sp+0x44] = sp+0x14c;
@ 0x080207f4(object, 0x1a, sp+0x18); 0x08027d30(sp+0x148, text, word [sp+0x70],
@ sxth[sp+0x84], stack: sxth[sp+0x82], 0x1fff, 0) measures the text; rectangle at
@ sp+0x60 centred on (sp+0x68, sp+0x6a) with the measured width and height (x0 =
@ px - w/2, y0 = py - h/2, sizes halved toward zero); 0x0801e274(r1, sp+0xcc,
@ sp+0x60, text, stack 0); [sp+0xec] = 0x0801e910(sp+0x9c, 0); r0 = sp+0xb4.
@ Other step (r10 == 0, 0x08019ce6): [sp+0x2c] = 0, [sp+0x44] = 0,
@ 0x080207f4(object, 0x1a, sp+0x18), r0 = sp+0x104.
@ Both: r6 = 0x0801e910(r0, 0) (r0 = sp+0xb4 or sp+0x104); 0x0801e8b8(r1,
@ sp+0x90, sp+0x144, sp+0x10); 0x0801f2fc(r6); 0x080207f4(object, 0x16, sp+0x18);
@ halfword [sp+0x90] = [sp+0xf0] and [sp+0x92] = [sp+0x140] restored; r7 = (r7 +
@ 1) & 0xffff.
@ After the steps (0x08019d36): 0x0801ec98 on sp+0x104, sp+0xb4 and sp+0x9c;
@ 0x0801f2fc([sp+0xec]); next node = 0x080125fa([sp+0xf4], r4).
@ Literal words after the code: 0x08019d64 = pointer constant, 0x08019d68 = mask
@ 0x07e0f81f, 0x08019d6c = the bytes of the text "%d".
@ ----------------------------------------------------------------------------
	.section .text.fn_0801998c,"ax",%progbits
	.p2align 2
	.global fn_0801998c
	.thumb_func
	.type fn_0801998c, %function
fn_0801998c:
	push.w {r0, r1, r2, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0x160
	ldr r0, [sp, #0x160]
	str r0, [sp, #0x12c]
	ldrh r0, [r2, #4]
	ldrsh.w r1, [r2]
	ldrh r4, [r2, #2]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r3, r0
	ldrh r0, [r2, #6]
	add.w r3, r3, r3, lsr #31
	subs r0, r0, r4
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r0, r0
	asrs r5, r3, #1
	add.w r0, r0, r0, lsr #31
	cmp.w r5, r0, asr #1
	blt.n .L080199be
	asrs r5, r0, #1
.L080199be:
	adds r0, r1, r5
	strh.w r0, [sp, #0x10]
	ldrh r0, [r2, #2]
	add r0, r5
	strh.w r0, [sp, #0x12]
	add r0, sp, #0x90
	bl fn_0801e8d2
	mov.w r4, #0x60000
	add r2, sp, #0x90
	mov r1, r4
	ldr r0, [sp, #0x160]
	bl fn_080250b6
	ldrb.w r0, [sp, #0x99]
	orr.w r0, r0, #0x10
	strb.w r0, [sp, #0x99]
	add r0, sp, #0x70
	bl fn_0801e7b4
	add r2, sp, #0x70
	mov r1, r4
	ldr r0, [sp, #0x160]
	bl fn_0802501a
	add r0, sp, #0x18
	ldr r1, [sp, #0x164]
	bl fn_08023a0c
	ldr r0, .L08019d64
	str r0, [sp, #0x1c]
	movs r0, #3
	str r0, [sp, #0x20]
	add r0, sp, #0x90
	str r0, [sp, #0x30]
	ldr r0, [sp, #0x12c]
	str r4, [sp, #0x4c]
	adds r0, #0x24
	str r0, [sp, #0xf4]
	bl get_word_8_or_zero
	b.n .L08019d56
.L08019a1e:
	str r4, [sp, #0x5c]
	ldrh r1, [r4, #0xc]
	ldrh r0, [r4, #4]
	subs r1, r5, r1
	sxth.w r11, r1
	ldrh.w r1, [sp, #0x10]
	subs r0, r5, r0
	subs r2, r1, r0
	strh.w r2, [sp, #0x130]
	ldrh.w r2, [sp, #0x12]
	add r1, r0
	subs r3, r2, r0
	strh.w r1, [sp, #0x134]
	add r0, r2
	strh.w r3, [sp, #0x132]
	strh.w r0, [sp, #0x136]
	movw r6, #0x7fff
	movs r3, #1
	mov r2, r6
	add r1, sp, #0x130
	add r0, sp, #0x104
	bl fn_0801f1a8
	ldrh.w r2, [sp, #0x10]
	movs r3, #1
	sub.w r0, r2, r11
	strh.w r0, [sp, #0xfc]
	ldrh.w r0, [sp, #0x12]
	sub.w r1, r0, r11
	strh.w r1, [sp, #0xfe]
	sub.w r1, r11, #1
	add r2, r1
	strh.w r2, [sp, #0x100]
	add r0, r1
	strh.w r0, [sp, #0x102]
	mov r2, r6
	add r1, sp, #0xfc
	add r0, sp, #0xb4
	bl fn_0801f1a8
	ldrh.w r2, [sp, #0x10]
	ldrh.w r1, [sp, #0x12]
	subs r0, r2, r5
	strh.w r0, [sp, #0x138]
	subs r0, r1, r5
	strh.w r0, [sp, #0x13a]
	subs r0, r5, #1
	add r2, r0
	strh.w r2, [sp, #0x13c]
	add r0, r1
	strh.w r0, [sp, #0x13e]
	movs r3, #0
	mov r2, r6
	add r1, sp, #0x138
	add r0, sp, #0x9c
	bl fn_0801f1a8
	movs r1, #0
	add r0, sp, #0x9c
	bl table_slot_insert
	str r0, [sp, #0xec]
	ldrh r0, [r4, #0xa]
	cbz r0, .L08019ad0
	.inst.n 0x1e40  @ subs r0, r0, #1
	b.n .L08019ad4
.L08019ad0:
	movw r0, #0xffff
.L08019ad4:
	mov r8, r0
	movs r7, #0
	b.n .L08019d2e
	nop  @ padding
.L08019adc:
	ldrh r1, [r4, #0xa]
	add.w r8, r8, #1
	mov.w r10, #0
	cmp r1, r8
	bne.n .L08019af0
	mov r8, r10
	mov.w r10, #1
.L08019af0:
	ldr r0, [r4, #0x18]
	str r0, [sp]
	ldrh r2, [r4, #2]
	movs r1, #0
	mov r0, r7
	.inst.n 0x1e52  @ subs r2, r2, #1
	ldr r3, [r4, #0x14]
	bl fn_08022b12
	mov r9, r0
	str r0, [sp, #0x58]
	cmp.w r10, #0
	beq.n .L08019b16
	ldr r0, [r4, #8]
	str r0, [sp, #0xd4]
	str r0, [sp, #0xf0]
	ldrh r0, [r4, #0xe]
	b.n .L08019b1e
.L08019b16:
	ldr r0, [r4]
	str r0, [sp, #0xd4]
	str r0, [sp, #0xf0]
	ldrh r0, [r4, #6]
.L08019b1e:
	sxth r0, r0
	str r0, [sp, #0x140]
	str r0, [sp, #0xd0]
	ldr r0, [sp, #0x12c]
	adds r0, #0x30
	str r0, [sp, #0x60]
	bl get_word_8_or_zero
	b.n .L08019bb0
.L08019b30:
	ldrb r0, [r6, #4]
	cmp r0, #2
	bne.n .L08019ba8
	ldr r1, [r6, #8]
	cmp r1, r9
	bgt.n .L08019ba8
	ldr r2, [r6, #0xc]
	cmp r2, r9
	blt.n .L08019ba8
	ldrh r3, [r6, #0x10]
	ldr r0, [sp, #0xd0]
	add r0, r3
	sxth r0, r0
	str r0, [sp, #0xd0]
	ldrh r0, [r6, #0x12]
	ldrh r3, [r6, #0x14]
	cmp r0, r3
	bne.n .L08019b5c
	ldrh r0, [r6, #0x12]
	strh.w r0, [sp, #0xd4]
	b.n .L08019ba8
.L08019b5c:
	ldrb r0, [r6, #0x16]
	mov.w r3, #0
	lsls r0, r0, #0x1f
	mov.w r0, #0xff
	str r0, [sp]
	mov r0, r9
	bne.n .L08019b72
	ldrd r1, r2, [r4, #0x14]
.L08019b72:
	bl fn_08022b12
	uxtb r0, r0
	ldrh r2, [r6, #0x12]
	.inst.n 0x1d00  @ adds r0, r0, #4
	lsrs r3, r0, #3
	uxth r0, r2
	ldrh r1, [r6, #0x14]
	orr.w r2, r0, r0, lsl #16
	ldr r0, .L08019d68
	uxth r1, r1
	orr.w r1, r1, r1, lsl #16
	ands r2, r0
	ands r1, r0
	subs r1, r1, r2
	muls r1, r3, r1
	add.w r1, r2, r1, lsr #5
	ands r1, r0
	orr.w r0, r1, r1, lsr #16
	strh.w r0, [sp]
	uxth r0, r0
	str r0, [sp, #0xd4]
.L08019ba8:
	mov r1, r6
	ldr r0, [sp, #0x60]
	bl read_word_at_base_plus_offset
.L08019bb0:
	movs r6, r0
	bne.n .L08019b30
	ldrh r1, [r4, #0x1e]
	add.w r0, r7, r7, lsl #2
	lsls r0, r0, #1
	muls r1, r0, r1
	ldrh r0, [r4, #2]
	.inst.n 0x1e40  @ subs r0, r0, #1
	sdiv r0, r1, r0
	ldrsh.w r1, [r4, #0x20]
	cmp r5, #0x8f
	add.w r1, r1, r1, lsl #2
	add.w r6, r0, r1, lsl #1
	ldrh.w r0, [sp, #0xd4]
	strh.w r0, [sp, #0x90]
	ldr r0, [sp, #0xd0]
	strh.w r0, [sp, #0x92]
	ldrsh.w r1, [sp, #0x10]
	mov r0, r5
	bge.n .L08019bee
	movs r2, #0x8f
	b.n .L08019bf0
.L08019bee:
	mov r2, r0
.L08019bf0:
	adds r0, r2, r5
	add r0, r1
	strh.w r0, [sp, #0x144]
	ldrh.w r0, [sp, #0x12]
	strh.w r0, [sp, #0x146]
	add r3, sp, #0x10
	mov.w r2, #0x100
	mov r1, r6
	add r0, sp, #0x144
	bl fn_08026878
	add r0, sp, #0x10
	str r0, [sp, #0x3c]
	add r0, sp, #0x144
	str r0, [sp, #0x40]
	add r0, sp, #0x70
	str r7, [sp, #0x50]
	str r0, [sp, #0x2c]
	cmp.w r10, #0
	beq.n .L08019ce6
	ldr r0, [sp, #0xec]
	bl table_slot_clear
	ldrh r1, [r4, #0x10]
	add r3, sp, #0x10
	sub.w r0, r11, r1
	ldrh.w r1, [sp, #0x10]
	mov.w r2, #0x100
	add r0, r1
	strh.w r0, [sp, #0x68]
	ldrh.w r0, [sp, #0x12]
	strh.w r0, [sp, #0x6a]
	mov r1, r6
	add r0, sp, #0x68
	bl fn_08026878
	movs r2, #0x20
	add r1, sp, #0x70
	add r0, sp, #0xcc
	bl copy_bytes_08022ce0
	add r0, sp, #0xcc
	str r0, [sp, #0x2c]
	mov r3, r9
	adr r2, .L08019d6c
	movs r1, #0x10
	add r0, sp, #0x14c
	bl fn_0801033c
	add r0, sp, #0x14c
	str r0, [sp, #0x44]
	add r2, sp, #0x18
	movs r1, #0x1a
	ldr r0, [sp, #0x160]
	bl fn_080207f4
	ldrsh.w r0, [sp, #0x82]
	mov.w r9, #0
	movw r2, #0x1fff
	stm.w sp, {r0, r2, r9}
	ldrsh.w r3, [sp, #0x84]
	add r0, sp, #0x148
	ldr r2, [sp, #0x70]
	ldr r1, [sp, #0x44]
	bl fn_08027d30
	ldrsh.w r0, [sp, #0x148]
	ldrh.w r1, [sp, #0x68]
	add.w r2, r0, r0, lsr #31
	sub.w r3, r1, r2, asr #1
	ldrsh.w r1, [sp, #0x14a]
	ldrh.w r2, [sp, #0x6a]
	add.w r6, r1, r1, lsr #31
	add r0, r3
	sub.w r2, r2, r6, asr #1
	strh.w r0, [sp, #0x64]
	adds r0, r2, r1
	strh.w r3, [sp, #0x60]
	strh.w r2, [sp, #0x62]
	strh.w r0, [sp, #0x66]
	str.w r9, [sp]
	add r2, sp, #0x60
	ldr r3, [sp, #0x44]
	ldr r1, [sp, #0x2c]
	ldr r0, [sp, #0x164]
	bl fn_0801e274
	movs r1, #0
	add r0, sp, #0x9c
	bl table_slot_insert
	str r0, [sp, #0xec]
	add r0, sp, #0xb4
	b.n .L08019cf8
.L08019ce6:
	movs r0, #0
	str r0, [sp, #0x2c]
	str r0, [sp, #0x44]
	add r2, sp, #0x18
	movs r1, #0x1a
	ldr r0, [sp, #0x160]
	bl fn_080207f4
	add r0, sp, #0x104
.L08019cf8:
	movs r1, #0
	bl table_slot_insert
	mov r6, r0
	add r3, sp, #0x10
	add r2, sp, #0x144
	add r1, sp, #0x90
	ldr r0, [sp, #0x164]
	bl fn_0801e8b8
	mov r0, r6
	bl table_slot_clear
	add r2, sp, #0x18
	movs r1, #0x16
	ldr r0, [sp, #0x160]
	bl fn_080207f4
	ldrh.w r0, [sp, #0xf0]
	strh.w r0, [sp, #0x90]
	ldr r0, [sp, #0x140]
	.inst.n 0x1c7f  @ adds r7, r7, #1
	strh.w r0, [sp, #0x92]
	uxth r7, r7
.L08019d2e:
	ldrh r0, [r4, #2]
	cmp r0, r7
	bhi.w .L08019adc
	add r0, sp, #0x104
	bl fn_0801ec98
	add r0, sp, #0xb4
	bl fn_0801ec98
	add r0, sp, #0x9c
	bl fn_0801ec98
	ldr r0, [sp, #0xec]
	bl table_slot_clear
	mov r1, r4
	ldr r0, [sp, #0xf4]
	bl read_word_at_base_plus_offset
.L08019d56:
	movs r4, r0
	bne.w .L08019a1e
	add sp, #0x16c
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short 0x0000  @ padding
.L08019d64:
	.word d_08050f30  @ pointer constant stored at sp+0x1c
.L08019d68:
	.word 0x07e0f81f  @ RGB565 channel mask
.L08019d6c:
	.asciz "%d"  @ format text read as data by adr at 0x08019c5e
	.byte 0x00  @ padding

@ ----------------------------------------------------------------------------
@ fn_08019d70 - draws a row of tick lines with optional "%d" number labels for an
@ object, for one selector.
@ Parameters: r0 = object (r5), r1 = drawing target T (saved at [sp+0xd4]), r2 =
@ selector (r8); r0, r1 and r2 are pushed by the prologue; no return value.
@ D = 0x0801b8ec(r0, r2) (r4); W = word [D + 8]; returns (0x08019e7a ->
@ 0x0801a092) when (W & 0x7fff) <= 1, or when bit 15 of W is clear and the
@ halfwords [D] and [D + 2] are both 0.
@ r6 = 0x08024af8(r0, 0) + 0x0802499c(r0, 0); r7 = sbfx(0x08023e7c(r0) * ushort
@ [r0 + 0x84], bits 8..23); 0x0801e7b4 fills the record at sp+0x8c,
@ 0x0802501a(r0, 0x60000, sp+0x8c); r9 = sxth(ushort [r0 + 0x14] + r6 -
@ 0x08024070(r0)).
@ Selector 2 (cmp r8,#2 at 0x08019de4): fb = 0x08024a98(r0, 0x60000) when bit 15
@ of W is set, else 0; r6 = sxth [r0 + 0x1a]; returns when signed halfword
@ [[T + 8] + 6] < r6, or when r6 + fb + signed halfword [D] + signed halfword
@ [[sp+0x8c] + 8] < signed halfword [[T + 8] + 2].
@ Any other selector: fb = 0x08024b88(r0, 0x60000) when bit 15 of W is set, else
@ 0; r6 = sxth [r0 + 0x16].
@ 0x0801e8d2(sp+0x74) and 0x080250b6(r0, 0x60000, sp+0x74) fill the record at
@ sp+0x74 (halfwords sp+0x78 and sp+0x7a then set to 0); 0x08023a0c(sp+0xc, T);
@ word [sp+0x10] = 0x08050f14, [sp+0x14] = 6, [sp+0x40] = 0x60000, [sp+0x44] = 2,
@ [sp+0x20] = sp+0x8c, [sp+0x24] = sp+0x74; q = 0 for selector 2, else 1 (stored
@ at sp+0x84).
@ When byte [r0 + 0x88] & 7 is 2: A = (0x08024ad4(r0, 0) * ushort [r0 + 0x84]) >>
@ 8; B = sxth((r7 + A) / ushort [r0 + 0x82]) - A; r9 = sxth(r9 + B / 2) and r7 =
@ sxth(r7 - B).
@ Halfword [sp+0x5a] = r6; M = (word [D + 4] >> 16) & 0x7fff; N = ((W & 0x7fff) -
@ 1) * M (r8). Loop i = 0..N inclusive (cmp r6,r8 / bls at 0x0801a08c): major =
@ (i mod M == 0) (udiv / mls); p = i * (r7 - signed halfword [sp+0x76]) / N (udiv)
@ + r9, stored to halfwords sp+0x54 and sp+0x58; length L = signed halfword [D]
@ for a major tick, signed halfword [D + 2] otherwise; halfword [sp+0x56] =
@ [sp+0x5a] - L for q = 1 and [sp+0x5a] + L for q = 0; words [sp+0x30] = sp+0x58,
@ [sp+0x34] = sp+0x54.
@ Value V stored to word [sp+0x4c]: when byte [r0 + 0x88] & 7 is 3, V =
@ 0x08022b12(i, 0, N, signed halfword [r0 + 2q + 0x74], stack signed halfword
@ [r0 + 2q + 0x78]); otherwise V = i / M.
@ Major tick with bit 15 of W set (0x08019f6e): formats V into the 16-byte buffer
@ sp+0xc0 with 0x0801033c(sp+0xc0, 0x10, format 0x0801a09c = the bytes '%' 'd' 0,
@ V), words [sp+0x38] = sp+0xc0, [sp+0x3c] = 0x10, calls 0x080207f4(r0, 0x1a,
@ sp+0xc), measures the text with 0x08027d30(sp+0x70, sp+0xc0, [sp+0x8c], sxth
@ [sp+0xa0], stack sxth [sp+0x9e], 0x1fff, 0) giving width w (signed halfword
@ sp+0x70) and height h (halfword sp+0x72); label rectangle at sp+0x64 = {p - w/2,
@ y0, p + w/2, y1} with (y0, y1) = ([sp+0x56] - fb - h, [sp+0x56] - fb) for q = 1
@ and ([sp+0x56] + fb, [sp+0x56] + fb + h) for q = 0; drawn with
@ 0x0801e274(T, sp+0x8c, sp+0x64, sp+0xc0, 0) unless p + w/2 < signed halfword
@ [r0 + 0x14] or p - w/2 > signed halfword [r0 + 0x18].
@ Other ticks (0x0801a03a): words [sp+0x20], [sp+0x38], [sp+0x3c] = 0 and
@ 0x080207f4(r0, 0x1a, sp+0xc).
@ Tick line: with half = signed halfword [sp+0x76] / 2, drawn with
@ 0x0801e8b8(T, sp+0x74, sp+0x58, sp+0x54) unless [sp+0x58] + half < signed
@ halfword [r0 + 0x14] or [sp+0x54] - half > signed halfword [r0 + 0x18]; then
@ 0x080207f4(r0, 0x1b, sp+0xc) and i = i + 1.
@ End: releases the frame (add sp,#220) and returns with pop pc (0x0801a094).
@ Literal words after the code: 0x0801a098 = pointer constant, 0x0801a09c = the
@ bytes of the text "%d".
@ ----------------------------------------------------------------------------
	.section .text.fn_08019d70,"ax",%progbits
	.p2align 2
	.global fn_08019d70
	.thumb_func
	.type fn_08019d70, %function
fn_08019d70:
	push.w {r0, r1, r2, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0xd0
	mov r8, r2
	mov r5, r0
	mov r1, r2
	bl base_plus_offset_by_index
	mov r4, r0
	ldr r0, [r0, #8]
	ubfx r1, r0, #0, #15
	cmp r1, #1
	bls.n .L08019e7a
	lsls r0, r0, #16
	bmi.n .L08019d9a
	ldrh r0, [r4]
	cbnz r0, .L08019d9a
	ldrh r0, [r4, #2]
	cmp r0, #0
	beq.n .L08019e7a
.L08019d9a:
	movs r1, #0
	mov r0, r5
	bl fn_08024af8
	mov r6, r0
	movs r1, #0
	mov r0, r5
	bl fn_0802499c
	add r6, r0
	mov r0, r5
	bl fn_08023e7c
	ldrh.w r1, [r5, #0x84]
	muls r0, r1, r0
	sbfx r7, r0, #8, #16
	add r0, sp, #0x8c
	bl fn_0801e7b4
	mov.w r10, #0x60000
	add r2, sp, #0x8c
	mov r1, r10
	mov r0, r5
	bl fn_0802501a
	mov r0, r5
	bl fn_08024070
	ldrh r1, [r5, #0x14]
	add r1, r6
	subs r0, r1, r0
	sxth.w r9, r0
	ldrh r0, [r4, #8]
	cmp.w r8, #2
	lsl.w r0, r0, #16
	beq.n .L08019dfc
	cmp r0, #0
	bge.n .L08019e7c
	mov r1, r10
	mov r0, r5
	bl fn_08024b88
	b.n .L08019e7e
.L08019dfc:
	cmp r0, #0
	bge.n .L08019e0a
	mov r1, r10
	mov r0, r5
	bl fn_08024a98
	b.n .L08019e0c
.L08019e0a:
	movs r0, #0
.L08019e0c:
	mov r11, r0
	ldr r0, [sp, #0xd4]
	ldrsh.w r6, [r5, #0x1a]
	ldr r0, [r0, #8]
	ldrsh.w r1, [r0, #6]
	cmp r1, r6
	blt.n .L08019e7a
	ldr r1, [sp, #0x8c]
	ldrsh.w r2, [r4]
	ldrsh.w r0, [r0, #2]
	ldrsh.w r1, [r1, #8]
	add r2, r1
	add.w r1, r6, r11
	add r1, r2
	cmp r1, r0
	blt.n .L08019e7a
.L08019e38:
	add r0, sp, #0x74
	bl fn_0801e8d2
	add r2, sp, #0x74
	mov r1, r10
	mov r0, r5
	bl fn_080250b6
	movs r0, #0
	strh.w r0, [sp, #0x7a]
	strh.w r0, [sp, #0x78]
	add r0, sp, #0xc
	ldr r1, [sp, #0xd4]
	bl fn_08023a0c
	ldr r0, .L0801a098
	str r0, [sp, #0x10]
	movs r0, #6
	str r0, [sp, #0x14]
	movs r0, #2
	strd r10, r0, [sp, #0x40]
	add r0, sp, #0x8c
	str r0, [sp, #0x20]
	add r0, sp, #0x74
	str r0, [sp, #0x24]
	cmp.w r8, #2
	beq.n .L08019e86
	movs r0, #1
	b.n .L08019e88
.L08019e7a:
	b.n .L0801a092
.L08019e7c:
	movs r0, #0
.L08019e7e:
	mov r11, r0
	ldrsh.w r6, [r5, #0x16]
	b.n .L08019e38
.L08019e86:
	movs r0, #0
.L08019e88:
	str r0, [sp, #0x84]
	ldrb.w r0, [r5, #0x88]
	and.w r0, r0, #7
	cmp r0, #2
	bne.n .L08019ec4
	movs r1, #0
	mov r0, r5
	bl fn_08024ad4
	ldrh.w r1, [r5, #0x84]
	muls r0, r1, r0
	asrs r0, r0, #8
	ldrh.w r1, [r5, #0x82]
	adds r2, r7, r0
	sdiv r1, r2, r1
	sxth r1, r1
	subs r0, r1, r0
	add.w r2, r0, r0, lsr #31
	add.w r1, r9, r2, asr #1
	subs r0, r7, r0
	sxth.w r9, r1
	sxth r7, r0
.L08019ec4:
	strh.w r6, [sp, #0x5a]
	ldrh r0, [r4, #8]
	ldr r1, [r4, #4]
	ubfx r0, r0, #0, #15
	.inst.n 0x1e40  @ subs r0, r0, #1
	ubfx r1, r1, #16, #15
	mul.w r8, r0, r1
	movs r6, #0
	b.n .L0801a08c
	nop  @ padding
.L08019ee0:
	ldr r0, [r4, #4]
	mov.w r10, #0
	ubfx r0, r0, #16, #15
	udiv r1, r6, r0
	mls r0, r0, r1, r6
	cbnz r0, .L08019ef8
	mov.w r10, #1
.L08019ef8:
	ldrsh.w r0, [sp, #0x76]
	subs r0, r7, r0
	muls r0, r6, r0
	udiv r1, r0, r8
	add.w r0, r1, r9
	strh.w r0, [sp, #0x58]
	strh.w r0, [sp, #0x54]
	ldrsh.w r1, [sp, #0x5a]
	ldr r0, [sp, #0x84]
	cbz r0, .L08019f2c
	cmp.w r10, #0
	beq.n .L08019f24
	ldrsh.w r0, [r4]
	b.n .L08019f28
.L08019f24:
	ldrsh.w r0, [r4, #2]
.L08019f28:
	subs r0, r1, r0
	b.n .L08019f3e
.L08019f2c:
	cmp.w r10, #0
	beq.n .L08019f38
	ldrsh.w r0, [r4]
	b.n .L08019f3c
.L08019f38:
	ldrsh.w r0, [r4, #2]
.L08019f3c:
	add r0, r1
.L08019f3e:
	strh.w r0, [sp, #0x56]
	add r0, sp, #0x58
	str r0, [sp, #0x30]
	add r0, sp, #0x54
	str r0, [sp, #0x34]
	ldrb.w r0, [r5, #0x88]
	and.w r0, r0, #7
	cmp r0, #3
	beq.n .L08019fe8
	ldr r0, [r4, #4]
	ubfx r0, r0, #16, #15
	udiv r3, r6, r0
.L08019f60:
	str r3, [sp, #0x4c]
	cmp.w r10, #0
	beq.n .L0801a03a
	ldrh r0, [r4, #8]
	lsls r0, r0, #16
	bpl.n .L0801a03a
	adr r2, .L0801a09c
	movs r1, #0x10
	add r0, sp, #0xc0
	bl fn_0801033c
	add r0, sp, #0x8c
	str r0, [sp, #0x20]
	add r0, sp, #0xc0
	str r0, [sp, #0x38]
	movs r0, #0x10
	str r0, [sp, #0x3c]
	add r2, sp, #0xc
	movs r1, #0x1a
	mov r0, r5
	bl fn_080207f4
	ldrsh.w r0, [sp, #0x9e]
	mov.w r10, #0
	movw r2, #0x1fff
	stm.w sp, {r0, r2, r10}
	ldrsh.w r3, [sp, #0xa0]
	add r0, sp, #0x70
	ldr r2, [sp, #0x8c]
	ldr r1, [sp, #0x38]
	bl fn_08027d30
	ldrsh.w r1, [sp, #0x70]
	ldrh.w r0, [sp, #0x54]
	add.w r1, r1, r1, lsr #31
	sub.w r2, r0, r1, asr #1
	add.w r0, r0, r1, asr #1
	sxth r0, r0
	strh.w r0, [sp, #0x68]
	sxth r2, r2
	ldrh.w r3, [sp, #0x56]
	ldr r1, [sp, #0x84]
	strh.w r2, [sp, #0x64]
	cbz r1, .L0801a006
	sub.w r1, r3, r11
	ldrh.w r3, [sp, #0x72]
	strh.w r1, [sp, #0x6a]
	subs r1, r1, r3
	strh.w r1, [sp, #0x66]
	b.n .L0801a018
.L08019fe8:
	ldr r0, [sp, #0x84]
	mov r2, r8
	add.w r1, r5, r0, lsl #1
	ldrsh.w r0, [r1, #0x78]
	str r0, [sp]
	ldrsh.w r3, [r1, #0x74]
	movs r1, #0
	mov r0, r6
	bl fn_08022b12
	mov r3, r0
	b.n .L08019f60
.L0801a006:
	add.w r1, r3, r11
	ldrh.w r3, [sp, #0x72]
	strh.w r1, [sp, #0x66]
	add r1, r3
	strh.w r1, [sp, #0x6a]
.L0801a018:
	ldrsh.w r1, [r5, #0x14]
	cmp r0, r1
	blt.n .L0801a04c
	ldrsh.w r0, [r5, #0x18]
	cmp r2, r0
	bgt.n .L0801a04c
	str.w r10, [sp]
	add r2, sp, #0x64
	add r1, sp, #0x8c
	ldr r3, [sp, #0x38]
	ldr r0, [sp, #0xd4]
	bl fn_0801e274
	b.n .L0801a04c
.L0801a03a:
	movs r0, #0
	str r0, [sp, #0x20]
	str r0, [sp, #0x38]
	str r0, [sp, #0x3c]
	add r2, sp, #0xc
	movs r1, #0x1a
	mov r0, r5
	bl fn_080207f4
.L0801a04c:
	ldrsh.w r0, [sp, #0x76]
	ldrsh.w r1, [sp, #0x58]
	add.w r0, r0, r0, lsr #31
	add.w r2, r1, r0, asr #1
	ldrsh.w r1, [r5, #0x14]
	cmp r2, r1
	blt.n .L0801a080
	ldrsh.w r1, [sp, #0x54]
	sub.w r1, r1, r0, asr #1
	ldrsh.w r0, [r5, #0x18]
	cmp r1, r0
	bgt.n .L0801a080
	add r3, sp, #0x54
	add r2, sp, #0x58
	add r1, sp, #0x74
	ldr r0, [sp, #0xd4]
	bl fn_0801e8b8
.L0801a080:
	add r2, sp, #0xc
	movs r1, #0x1b
	mov r0, r5
	bl fn_080207f4
	.inst.n 0x1c76  @ adds r6, r6, #1
.L0801a08c:
	cmp r6, r8
	bls.w .L08019ee0
.L0801a092:
	add sp, #0xdc
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801a098:
	.word d_08050f14  @ pointer constant stored at sp+0x10
.L0801a09c:
	.asciz "%d"  @ format text read as data by adr at 0x08019f6e
	.byte 0x00  @ padding
