@ gfx_04.s - rectangle helpers of the graphics module: intersection, containment, overlap, rounded-corner point test, union and following routines.
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ rect_intersect - intersection of two rectangles.
@ Rectangles are four int16 values {left, top, right, bottom}.
@ Parameters: r0 = output rectangle, r1 = rectangle a, r2 = rectangle b.
@ Result: out[0] = max(a[0], b[0]); out[1] = max(a[1], b[1]);
@ out[2] = min(a[2], b[2]); out[3] = min(a[3], b[3]).
@ Returns r0 = 0 when out[2] < out[0] or out[3] < out[1], otherwise 1.
@ Uses r3-r6 (saved on the stack); calls nothing.
@ ----------------------------------------------------------------------------
	.section .text.rect_intersect,"ax",%progbits
	.p2align 2
	.global rect_intersect
	.thumb_func
	.type rect_intersect, %function
rect_intersect:
	push {r4, r5, r6, lr}
	ldrsh.w r3, [r1]		@ r3 = a.left
	ldrsh.w r4, [r2]		@ r4 = b.left
	cmp r3, r4
	bgt.n .L08011e5c
	mov r3, r4			@ r3 = max(a.left, b.left)
.L08011e5c:
	strh r3, [r0]			@ out.left
	ldrsh.w r5, [r1, #2]		@ r5 = a.top
	ldrsh.w r4, [r2, #2]		@ r4 = b.top
	cmp r5, r4
	ble.n .L08011e6c
	mov r4, r5			@ r4 = max(a.top, b.top)
.L08011e6c:
	strh r4, [r0, #2]		@ out.top
	ldrsh.w r6, [r1, #4]		@ r6 = a.right
	ldrsh.w r5, [r2, #4]		@ r5 = b.right
	cmp r6, r5
	bge.n .L08011e7c
	mov r5, r6			@ r5 = min(a.right, b.right)
.L08011e7c:
	strh r5, [r0, #4]		@ out.right
	ldrsh.w r1, [r1, #6]		@ r1 = a.bottom
	ldrsh.w r2, [r2, #6]		@ r2 = b.bottom
	cmp r1, r2
	blt.n .L08011e8c
	mov r1, r2			@ r1 = min(a.bottom, b.bottom)
.L08011e8c:
	strh r1, [r0, #6]		@ out.bottom
	movs r0, #1
	cmp r3, r5
	bgt.n .L08011e98		@ left > right: empty
	cmp r4, r1
	ble.n .L08011e9a		@ top <= bottom: non-empty, return 1
.L08011e98:
	movs r0, #0
.L08011e9a:
	pop {r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08011e9c - containment test with optional rounded corners.
@ Parameters: r0 = rectangle a, r1 = rectangle b, r2 = corner radius;
@ rectangles are four int16 values {left, top, right, bottom}.
@ Returns r0 = 0 when a[0] < b[0], a[1] < b[1], b[2] < a[2] or b[3] < a[3].
@ When the radius is nonzero, the four corner points of a, (left, top),
@ (right, top), (left, bottom) and (right, bottom), are each tested with
@ fn_0801201c(b, point, radius) (the point is built as two int16 on the stack);
@ returns 0 as soon as one test returns 0.
@ Otherwise returns 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08011e9c,"ax",%progbits
	.p2align 2
	.global fn_08011e9c
	.thumb_func
	.type fn_08011e9c, %function
fn_08011e9c:
	push {r3, r4, r5, r6, r7, lr}
	mov r5, r1			@ r5 = rectangle b
	mov r4, r0			@ r4 = rectangle a
	ldrsh.w r0, [r0]		@ r0 = a.left
	ldrsh.w r1, [r1]		@ r1 = b.left
	mov r6, r2			@ r6 = radius
	cmp r0, r1
	blt.n .L08011f40		@ a.left < b.left: return 0
	ldrsh.w r1, [r4, #2]
	ldrsh.w r2, [r5, #2]
	cmp r1, r2
	blt.n .L08011f40		@ a.top < b.top: return 0
	ldrsh.w r1, [r4, #4]
	ldrsh.w r2, [r5, #4]
	cmp r1, r2
	bgt.n .L08011f40		@ a.right > b.right: return 0
	ldrsh.w r1, [r4, #6]
	ldrsh.w r2, [r5, #6]
	cmp r1, r2
	bgt.n .L08011f40		@ a.bottom > b.bottom: return 0
	cbz r6, .L08011f3c		@ radius 0: skip the corner tests
	strh.w r0, [sp]			@ point x = a.left
	ldrh r0, [r4, #2]
	strh.w r0, [sp, #2]		@ point y = a.top
	mov r2, r6
	mov r1, sp
	mov r0, r5
	bl fn_0801201c
	cmp r0, #0
	beq.n .L08011f3e
	ldrh r0, [r4, #4]
	strh.w r0, [sp]			@ point x = a.right
	ldrh r0, [r4, #2]
	strh.w r0, [sp, #2]		@ point y = a.top
	mov r2, r6
	mov r1, sp
	mov r0, r5
	bl fn_0801201c
	cmp r0, #0
	beq.n .L08011f3e
	ldrh r0, [r4]
	strh.w r0, [sp]			@ point x = a.left
	ldrh r0, [r4, #6]
	strh.w r0, [sp, #2]		@ point y = a.bottom
	mov r2, r6
	mov r1, sp
	mov r0, r5
	bl fn_0801201c
	cmp r0, #0
	beq.n .L08011f3e
	ldrh r0, [r4, #4]
	strh.w r0, [sp]			@ point x = a.right
	ldrh r0, [r4, #6]
	strh.w r0, [sp, #2]		@ point y = a.bottom
	mov r2, r6
	mov r1, sp
	mov r0, r5
	bl fn_0801201c
	cmp r0, #0
	beq.n .L08011f3e
.L08011f3c:
	movs r0, #1
.L08011f3e:
	pop {r3, r4, r5, r6, r7, pc}
.L08011f40:
	movs r0, #0
	pop {r3, r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ rect_overlaps - tests whether two rectangles overlap.
@ Parameters: r0 = rectangle a, r1 = rectangle b, each four int16
@ {left, top, right, bottom}.
@ Returns r0 = 0 when b[2] < a[0], a[2] < b[0], b[3] < a[1] or a[3] < b[1],
@ otherwise 1. Uses r2, r3; calls nothing.
@ ----------------------------------------------------------------------------
	.section .text.rect_overlaps,"ax",%progbits
	.p2align 2
	.global rect_overlaps
	.thumb_func
	.type rect_overlaps, %function
rect_overlaps:
	ldrsh.w r2, [r0]		@ a.left
	ldrsh.w r3, [r1, #4]		@ b.right
	cmp r2, r3
	bgt.n .L08011f78
	ldrsh.w r2, [r0, #4]		@ a.right
	ldrsh.w r3, [r1]		@ b.left
	cmp r2, r3
	blt.n .L08011f78
	ldrsh.w r2, [r0, #2]		@ a.top
	ldrsh.w r3, [r1, #6]		@ b.bottom
	cmp r2, r3
	bgt.n .L08011f78
	ldrsh.w r0, [r0, #6]		@ a.bottom
	ldrsh.w r1, [r1, #2]		@ b.top
	cmp r0, r1
	blt.n .L08011f78
	movs r0, #1
	bx lr
.L08011f78:
	movs r0, #0
	bx lr

@ ----------------------------------------------------------------------------
@ fn_08011f7c - disjointness test of two rectangles with optional rounded corners.
@ Parameters: r0 = rectangle a, r1 = rectangle b, r2 = radius; rectangles are
@ four int16 values {left, top, right, bottom}.
@ Returns r0 = 1 when a[2] < b[0], a[3] < b[1], b[2] < a[0] or b[3] < a[1].
@ With a nonzero radius the four corner points of a, (left, top),
@ (right, top), (left, bottom) and (right, bottom), are tested with
@ fn_0801201c(b, point, radius); returns 0 as soon as one test returns
@ nonzero, 1 when all four return zero.
@ With radius 0 and overlapping rectangles returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08011f7c,"ax",%progbits
	.p2align 2
	.global fn_08011f7c
	.thumb_func
	.type fn_08011f7c, %function
fn_08011f7c:
	push {r3, r4, r5, r6, r7, lr}
	mov r5, r1			@ r5 = rectangle b
	mov r4, r0			@ r4 = rectangle a
	ldrsh.w r0, [r0, #4]		@ a.right
	ldrsh.w r1, [r1]		@ b.left
	mov r6, r2			@ r6 = radius
	cmp r0, r1
	blt.n .L08012018		@ a.right < b.left: return 1
	ldrsh.w r0, [r4, #6]		@ a.bottom
	ldrsh.w r1, [r5, #2]		@ b.top
	cmp r0, r1
	blt.n .L08012018		@ a.bottom < b.top: return 1
	ldrsh.w r0, [r4]		@ a.left
	ldrsh.w r1, [r5, #4]		@ b.right
	cmp r0, r1
	bgt.n .L08012018		@ a.left > b.right: return 1
	ldrsh.w r1, [r4, #2]		@ a.top
	ldrsh.w r2, [r5, #6]		@ b.bottom
	cmp r1, r2
	bgt.n .L08012018		@ a.top > b.bottom: return 1
	cbz r6, .L08012014		@ radius 0: overlapping, return 0
	strh.w r0, [sp]			@ point x = a.left
	ldrh r0, [r4, #2]
	strh.w r0, [sp, #2]		@ point y = a.top
	mov r2, r6
	mov r1, sp
	mov r0, r5
	bl fn_0801201c
	cbnz r0, .L08012014
	ldrh r0, [r4, #4]
	strh.w r0, [sp]			@ point x = a.right
	ldrh r0, [r4, #2]
	strh.w r0, [sp, #2]		@ point y = a.top
	mov r2, r6
	mov r1, sp
	mov r0, r5
	bl fn_0801201c
	cbnz r0, .L08012014
	ldrh r0, [r4]
	strh.w r0, [sp]			@ point x = a.left
	ldrh r0, [r4, #6]
	strh.w r0, [sp, #2]		@ point y = a.bottom
	mov r2, r6
	mov r1, sp
	mov r0, r5
	bl fn_0801201c
	cbnz r0, .L08012014
	ldrh r0, [r4, #4]
	strh.w r0, [sp]			@ point x = a.right
	ldrh r0, [r4, #6]
	strh.w r0, [sp, #2]		@ point y = a.bottom
	mov r2, r6
	mov r1, sp
	mov r0, r5
	bl fn_0801201c
	cbz r0, .L08012018
.L08012014:
	movs r0, #0
	pop {r3, r4, r5, r6, r7, pc}
.L08012018:
	movs r0, #1
	pop {r3, r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_0801201c - point-in-rectangle test with rounded corners.
@ Parameters: r0 = rectangle {left, top, right, bottom} (four int16),
@ r1 = point {x, y} (two int16), r2 = corner radius.
@ Returns r0 = 0 when x < left, x > right, y < top or y > bottom; returns 1
@ when the radius is less than 1.
@ The radius is limited to the smaller of (right - left + 1)/2 and
@ (bottom - top + 1)/2 (signed halving, rounding toward zero).
@ Then the point is tested, with recursive calls of this function using
@ radius 0, against the four corner squares of side radius r: {left, top,
@ left+r, top+r}, {left, bottom-r, left+r, bottom}, {right-r, bottom-r,
@ right, bottom}, {right-r, top, right, top+r}; the squares are built on the
@ stack. When the point is in none of them returns 1.
@ When the point is in a corner square the corner square is widened to side
@ 2*r ({left, top, left+2r, top+2r}, {left, bottom-2r, left+2r, bottom},
@ {right-2r, bottom-2r, right, bottom}, {right-2r, top, right, top+2r}) and
@ the function returns fn_080269b8(widened square, point).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801201c,"ax",%progbits
	.global fn_0801201c
	.thumb_func
	.type fn_0801201c, %function
fn_0801201c:
	push.w {r2, r3, r4, r5, r6, r7, r8, lr}
	mov r4, r2			@ r4 = radius
	mov r6, r1			@ r6 = point
	ldrsh.w r2, [r1]		@ r2 = x
	ldrsh.w r1, [r0]		@ r1 = left
	mov r5, r0			@ r5 = rectangle
	cmp r2, r1
	blt.n .L080120a8		@ x < left: return 0
	ldrsh.w r0, [r5, #4]		@ r0 = right
	cmp r2, r0
	bgt.n .L080120a8		@ x > right: return 0
	ldrsh.w r7, [r6, #2]		@ r7 = y
	ldrsh.w r2, [r5, #2]		@ r2 = top
	cmp r7, r2
	blt.n .L080120a8		@ y < top: return 0
	ldrsh.w r3, [r5, #6]		@ r3 = bottom
	cmp r7, r3
	bgt.n .L080120a8		@ y > bottom: return 0
	cmp r4, #0
	ble.n .L0801213e		@ radius < 1: return 1
	subs r0, r0, r1			@ right - left
	subs r2, r3, r2			@ bottom - top
	.inst.n 0x1c40			@ adds r0, r0, #1
	.inst.n 0x1c52			@ adds r2, r2, #1
	sxth r0, r0
	sxth r2, r2
	add.w r0, r0, r0, lsr #31
	add.w r2, r2, r2, lsr #31
	asrs r0, r0, #1			@ (right - left + 1) / 2
	asrs r2, r2, #1			@ (bottom - top + 1) / 2
	cmp r0, r2
	blt.n .L08012070
	mov r0, r2
.L08012070:
	cmp r4, r0
	ble.n .L08012076
	mov r4, r0			@ radius = min(radius, half sizes)
.L08012076:
	strh.w r1, [sp]			@ square: left
	ldrh r0, [r5]
	movs r2, #0
	add r0, r4
	strh.w r0, [sp, #4]		@ square: left + r
	ldrh r0, [r5, #2]
	strh.w r0, [sp, #2]		@ square: top
	ldrh r0, [r5, #2]
	mov r1, r6
	add r0, r4
	strh.w r0, [sp, #6]		@ square: top + r
	mov r0, sp
	bl fn_0801201c			@ point in top-left corner square?
	cbz r0, .L080120ae
	ldrh.w r0, [sp, #4]
	add r0, r4
	strh.w r0, [sp, #4]		@ widen: left + 2r
	b.n .L08012128
.L080120a8:
	movs r0, #0
.L080120aa:
	pop.w {r2, r3, r4, r5, r6, r7, r8, pc}
.L080120ae:
	ldrh r0, [r5, #6]
	movs r2, #0
	subs r0, r0, r4
	strh.w r0, [sp, #2]		@ square: bottom - r
	ldrh r0, [r5, #6]
	strh.w r0, [sp, #6]		@ square: bottom
	mov r1, r6
	mov r0, sp
	bl fn_0801201c			@ point in bottom-left corner square?
	cbz r0, .L080120d4
	ldrh.w r0, [sp, #4]
	add r0, r4
	strh.w r0, [sp, #4]		@ widen: left + 2r
	b.n .L080120f8
.L080120d4:
	ldrh r0, [r5, #4]
	movs r2, #0
	subs r0, r0, r4
	strh.w r0, [sp]			@ square: right - r
	ldrh r0, [r5, #4]
	strh.w r0, [sp, #4]		@ square: right
	mov r1, r6
	mov r0, sp
	bl fn_0801201c			@ point in bottom-right corner square?
	cbz r0, .L08012104
	ldrh.w r0, [sp]
	subs r0, r0, r4
	strh.w r0, [sp]			@ widen: right - 2r
.L080120f8:
	ldrh.w r0, [sp, #2]
	subs r0, r0, r4
	strh.w r0, [sp, #2]		@ widen: bottom - 2r
	b.n .L08012132
.L08012104:
	ldrh r0, [r5, #2]
	strh.w r0, [sp, #2]		@ square: top
	ldrh r0, [r5, #2]
	movs r2, #0
	add r0, r4
	strh.w r0, [sp, #6]		@ square: top + r
	mov r1, r6
	mov r0, sp
	bl fn_0801201c			@ point in top-right corner square?
	cbz r0, .L0801213c
	ldrh.w r0, [sp]
	subs r0, r0, r4
	strh.w r0, [sp]			@ widen: right - 2r
.L08012128:
	ldrh.w r0, [sp, #6]
	add r0, r4
	strh.w r0, [sp, #6]		@ widen: top + 2r (or bottom side)
.L08012132:
	mov r1, r6
	mov r0, sp
	bl fn_080269b8			@ result = fn_080269b8(widened square, point)
	b.n .L080120aa
.L0801213c:
	b.n .L0801213e
.L0801213e:
	movs r0, #1
	b.n .L080120aa

@ ----------------------------------------------------------------------------
@ rect_union - bounding rectangle of two rectangles.
@ Rectangles are four int16 values {left, top, right, bottom}.
@ Parameters: r0 = output rectangle, r1 = rectangle a, r2 = rectangle b.
@ Result: out[0] = min(a[0], b[0]); out[1] = min(a[1], b[1]);
@ out[2] = max(a[2], b[2]); out[3] = max(a[3], b[3]).
@ No return value. Uses r3, r4 (r4 saved on the stack); calls nothing.
@ The unit ends with two padding bytes (0x0000).
@ ----------------------------------------------------------------------------
	.section .text.rect_union,"ax",%progbits
	.global rect_union
	.thumb_func
	.type rect_union, %function
rect_union:
	push {r4, lr}
	ldrsh.w r4, [r1]		@ a.left
	ldrsh.w r3, [r2]		@ b.left
	cmp r4, r3
	bge.n .L08012152
	mov r3, r4			@ r3 = min(a.left, b.left)
.L08012152:
	strh r3, [r0]			@ out.left
	ldrsh.w r4, [r1, #2]		@ a.top
	ldrsh.w r3, [r2, #2]		@ b.top
	cmp r4, r3
	bge.n .L08012162
	mov r3, r4			@ r3 = min(a.top, b.top)
.L08012162:
	strh r3, [r0, #2]		@ out.top
	ldrsh.w r4, [r1, #4]		@ a.right
	ldrsh.w r3, [r2, #4]		@ b.right
	cmp r4, r3
	ble.n .L08012172
	mov r3, r4			@ r3 = max(a.right, b.right)
.L08012172:
	strh r3, [r0, #4]		@ out.right
	ldrsh.w r1, [r1, #6]		@ a.bottom
	ldrsh.w r2, [r2, #6]		@ b.bottom
	cmp r1, r2
	bgt.n .L08012182
	mov r1, r2			@ r1 = max(a.bottom, b.bottom)
.L08012182:
	strh r1, [r0, #6]		@ out.bottom
	pop {r4, pc}
	.short 0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08014758 - builds the tables of a rounded-corner shape for a given radius.
@ Parameters: r0 = object pointer (kept in r5), r1 = radius (kept in r6); a
@ radius of 0 returns at once. No return value. Reached only by the b.w at
@ 0x0801f2c0.
@ Stores the radius at halfword [object + 0x18]; frees the block at word
@ [object + 0] with fn_08022c68 when it is nonzero; allocates a block of
@ 6 + 6*radius bytes with fn_08022b50 and stores it at words [object + 0] and
@ [object + 4]; stores block + 2 + 2*radius at word [object + 0xc] and
@ block + 4 + 4*radius at word [object + 8]. The block holds a byte table at
@ [object + 4] and two halfword tables at [object + 0xc] and [object + 8].
@ Radius 1: byte [block] = 0xb4, halfword [[object + 0xc] + 0] = 0,
@ halfword [[object + 0xc] + 2] = 1, halfword [[object + 8] + 0] = 0; returns.
@ Otherwise a scratch area of 8*radius + 8 bytes is allocated with
@ fn_08022bac (halfword table X at r9, halfword table Y at r8 = r9 +
@ 4*radius + 4). Start values: x = sxth(4*radius) (halfword [sp + 0x10]),
@ y = 0 (halfword [sp + 0x12]), d = sxth(1 - x) in r10, entry count r4 = 0,
@ group counter r11 = 0; stores x asr 2 at [sp + 0x18] and 0 at [sp + 0x28]
@ (both overwritten by the first record).
@ Loop at 0x0801493a: runs while short_pair_first_ge_second(sp + 0x10) is 1
@ (y <= x). Up to 4 steps (r7 = 0..3): d <= 0 (signed): d += 2*y + 3; d > 0:
@ d += 2*(y - x) + 5 and x -= 1; then y += 1; the step is recorded when
@ y <= x still holds: A[r7] = x asr 2 (words from [sp + 0x18]),
@ B[r7] = x and 3 (words from [sp + 0x28]).
@ After 4 records a group is stored at index r4 of X (r9) and Y (r8) as
@ halfword stores, with Y = the group counter; the byte table [object + 4]
@ gets a value v written twice at the same index (v, then v << 4), so the
@ final byte is (v << 4) and 0xff; r4 is incremented per entry, the group
@ counter per group.
@ A0 = A3: one entry (X = A0, Y = group, v = B0+B1+B2+B3).
@ A0 != A3 and A0 != A1: entries (A0, group, B0) and
@ (A0-1, group, B1+B2+B3+4).
@ A0 = A1 != A2: entries (A0, group, B0+B1) and (A0-1, group, B2+B3+8).
@ A0 = A1 = A2 != A3: entries (A0, group, B0+B1+B2) and (A0-1, group, B3+12).
@ When the step loop ends with r7 != 4 nothing is stored and the code goes to
@ 0x08014946; after a stored group it continues at 0x0801493a.
@ After the loop: s = smulbb(radius, 723), q = s asr 10; unless the last
@ entry (index r4 - 1) has X = q and Y = q, one entry X = Y = q is appended
@ with f = s - 1024*q: v = (f*f) asr 15 (sbfx #15,#16) when f <= 512, else
@ v = 15 - ((1024 - f)^2 asr 15); stored with the same double byte write.
@ Mirror (0x0801499e-0x080149c2): for index j = r4 - 2 down to 0 appends an
@ entry with X = Y[j], Y = X[j] and the byte at [object + 4] + j copied.
@ Index build (0x080149c4-0x08014a08): halfword [[object + 0xc] + 0] = 0; for
@ row r1 = 0, 1, ... while the position r0 < r4: halfword
@ [[object + 0xc] + 2*r1] = r0, halfword [[object + 8] + 2*r1] = X[r0], then
@ r0 advances while Y[r0] = r1 and r0 < r4, each step lowering halfword
@ [[object + 8] + 2*r1] to X[r0] when that is smaller (signed compare).
@ Finally frees the scratch area with fn_08022c44(r9) and returns.
@ Two padding bytes (0x00 0xbf) sit at 0x080149a2.
@ ----------------------------------------------------------------------------
	.section .text.fn_08014758,"ax",%progbits
	.global fn_08014758
	.thumb_func
	.type fn_08014758, %function
fn_08014758:
	push.w {r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0x44
	movs r6, r1			@ r6 = radius
	mov r5, r0			@ r5 = object
	beq.n .L080147e0		@ radius 0: return
	strh r6, [r5, #0x18]
	ldr r0, [r5]
	cbz r0, .L0801476e
	bl fn_08022c68			@ free the old block
.L0801476e:
	add.w r0, r6, r6, lsl #1	@ 3*radius
	movs r1, #6
	add.w r0, r1, r0, lsl #1	@ 6 + 6*radius
	bl fn_08022b50			@ allocate the block
	movs r1, #2
	add.w r1, r1, r6, lsl #1	@ 2 + 2*radius
	add r1, r0
	str r1, [r5, #0xc]
	movs r1, #4
	add.w r1, r1, r6, lsl #2	@ 4 + 4*radius
	str r0, [r5]
	add r1, r0
	strd r0, r1, [r5, #4]		@ [object + 4] = block, [object + 8] = block + 4 + 4*radius
	movs r1, #1
	movs r4, #0
	cmp r6, #1
	beq.n .L080147d0
	lsls r0, r6, #3
	adds r0, #8
	bl fn_08022bac			@ allocate the scratch area
	mov r9, r0			@ r9 = table X
	add.w r0, r0, r6, lsl #2
	add.w r8, r0, #4		@ r8 = table Y
	lsls r0, r6, #2
	sxth r0, r0
	mov r11, r4			@ group counter = 0
	strh.w r0, [sp, #0x10]		@ x = 4*radius
	rsb.w r2, r0, #1
	asrs r0, r0, #2
	strh.w r11, [sp, #0x12]		@ y = 0
	sxth.w r10, r2			@ d = 1 - x
	mov r4, r11			@ entry count = 0
	str.w r11, [sp, #0x28]
	str r0, [sp, #0x18]
	b.n .L0801493a
.L080147d0:
	movs r2, #0xb4
	strb r2, [r0]
	ldr r0, [r5, #0xc]
	strh r4, [r0]
	ldr r0, [r5, #0xc]
	strh r1, [r0, #2]
	ldr r0, [r5, #8]
	strh r4, [r0]
.L080147e0:
	add sp, #0x44
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L080147e6:
	movs r7, #0			@ step index
.L080147e8:
	ldrh.w r2, [sp, #0x12]		@ y
	cmp.w r10, #0
	bgt.n .L08014802
	movs r1, #3
	add.w r1, r1, r2, lsl #1	@ 2*y + 3
	add.w r0, r10, r1
	sxth.w r10, r0			@ d += 2*y + 3
	b.n .L0801481c
.L08014802:
	ldrh.w r1, [sp, #0x10]		@ x
	subs r3, r2, r1			@ y - x
	movs r2, #5
	add.w r2, r2, r3, lsl #1	@ 2*(y - x) + 5
	add.w r0, r2, r10
	.inst.n 0x1e49			@ subs r1, r1, #1
	sxth.w r10, r0			@ d += 2*(y - x) + 5
	strh.w r1, [sp, #0x10]		@ x -= 1
.L0801481c:
	ldrh.w r0, [sp, #0x12]
	.inst.n 0x1c40			@ adds r0, r0, #1
	strh.w r0, [sp, #0x12]		@ y += 1
	add r0, sp, #0x10
	bl short_pair_first_ge_second
	cbz r0, .L0801484a
	ldrsh.w r0, [sp, #0x10]
	add r2, sp, #0x18
	asrs r1, r0, #2
	str.w r1, [r2, r7, lsl #2]	@ A[r7] = x asr 2
	add r1, sp, #0x28
	and.w r0, r0, #3
	str.w r0, [r1, r7, lsl #2]	@ B[r7] = x and 3
	.inst.n 0x1c7f			@ adds r7, r7, #1
	cmp r7, #4
	blt.n .L080147e8
.L0801484a:
	cmp r7, #4
	bne.n .L08014946		@ fewer than 4 records: nothing stored
	ldr r1, [sp, #0x24]		@ A3
	ldr r0, [sp, #0x18]		@ A0
	cmp r0, r1
	bne.n .L0801487c
	strh.w r0, [r9, r4, lsl #1]	@ one entry: X = A0
	strh.w r11, [r8, r4, lsl #1]	@ Y = group
	ldrd r0, r1, [sp, #0x28]
	adds r2, r0, r1
	ldrd r0, r1, [sp, #0x30]
	add r0, r1
	adds r1, r2, r0			@ v = B0 + B1 + B2 + B3
	ldr r0, [r5, #4]
	strb r1, [r0, r4]
	ldr r0, [r5, #4]
	lsls r1, r1, #4
	strb r1, [r0, r4]
	.inst.n 0x1c64			@ adds r4, r4, #1
	sxth r4, r4
	b.n .L08014936
.L0801487c:
	ldr r1, [sp, #0x1c]		@ A1
	cmp r0, r1
	beq.n .L080148be
	strh.w r0, [r9, r4, lsl #1]	@ entry (A0, group, B0)
	strh.w r11, [r8, r4, lsl #1]
	ldr r2, [r5, #4]
	ldr r0, [sp, #0x28]
	strb r0, [r2, r4]
	ldr r2, [r5, #4]
	lsls r0, r0, #4
	strb r0, [r2, r4]
	.inst.n 0x1c64			@ adds r4, r4, #1
	ldr r3, [sp, #0x18]
	sxth r0, r4
	.inst.n 0x1e5b			@ subs r3, r3, #1
	strh.w r3, [r9, r0, lsl #1]	@ entry (A0 - 1, group, B1 + B2 + B3 + 4)
	strh.w r11, [r8, r0, lsl #1]
	ldrd r1, r2, [sp, #0x2c]
	add r2, r1
	ldr r1, [sp, #0x34]
	.inst.n 0x1d09			@ adds r1, r1, #4
	add r2, r1
	ldr r1, [r5, #4]
	strb r2, [r1, r0]
	ldr r1, [r5, #4]
	lsls r2, r2, #4
	strb r2, [r1, r0]
	b.n .L08014932
.L080148be:
	ldr r1, [sp, #0x20]		@ A2
	cmp r0, r1
	beq.n .L080148f8
	strh.w r0, [r9, r4, lsl #1]	@ entry (A0, group, B0 + B1)
	strh.w r11, [r8, r4, lsl #1]
	ldrd r0, r2, [sp, #0x28]
	add r0, r2
	ldr r2, [r5, #4]
	strb r0, [r2, r4]
	ldr r2, [r5, #4]
	lsls r0, r0, #4
	strb r0, [r2, r4]
	.inst.n 0x1c64			@ adds r4, r4, #1
	ldr r2, [sp, #0x18]
	sxth r0, r4
	.inst.n 0x1e52			@ subs r2, r2, #1
	strh.w r2, [r9, r0, lsl #1]	@ entry (A0 - 1, group, B2 + B3 + 8)
	strh.w r11, [r8, r0, lsl #1]
	ldrd r1, r2, [sp, #0x30]
	add r1, r2
	adds r1, #8
	ldr r2, [r5, #4]
	b.n .L0801492a
.L080148f8:
	strh.w r0, [r9, r4, lsl #1]	@ entry (A0, group, B0 + B1 + B2)
	strh.w r11, [r8, r4, lsl #1]
	ldrd r0, r2, [sp, #0x28]
	add r0, r2
	ldr r2, [sp, #0x30]
	add r0, r2
	ldr r2, [r5, #4]
	strb r0, [r2, r4]
	ldr r2, [r5, #4]
	lsls r0, r0, #4
	strb r0, [r2, r4]
	.inst.n 0x1c64			@ adds r4, r4, #1
	ldr r2, [sp, #0x18]
	sxth r0, r4
	.inst.n 0x1e52			@ subs r2, r2, #1
	strh.w r2, [r9, r0, lsl #1]	@ entry (A0 - 1, group, B3 + 12)
	strh.w r11, [r8, r0, lsl #1]
	ldr r1, [sp, #0x34]
	ldr r2, [r5, #4]
	adds r1, #0xc
.L0801492a:
	strb r1, [r2, r0]
	ldr r2, [r5, #4]
	lsls r1, r1, #4
	strb r1, [r2, r0]
.L08014932:
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth r4, r0
.L08014936:
	add.w r11, r11, #1		@ next group
.L0801493a:
	add r0, sp, #0x10
	bl short_pair_first_ge_second
	cmp r0, #0
	bne.w .L080147e6
.L08014946:
	movw r0, #0x2d3
	smulbb r1, r6, r0		@ s = radius * 723
	add.w r2, r9, r4, lsl #1
	asrs r0, r1, #10		@ q = s asr 10
	ldrsh.w r2, [r2, #-2]		@ X of the last entry
	cmp r2, r0
	bne.n .L08014968
	add.w r2, r8, r4, lsl #1
	ldrsh.w r2, [r2, #-2]		@ Y of the last entry
	cmp r2, r0
	beq.n .L0801499e
.L08014968:
	sub.w r1, r1, r0, lsl #10	@ f = s - 1024*q
	cmp.w r1, #0x200
	bgt.n .L0801497a
	muls r1, r1, r1
	sbfx r1, r1, #15, #16
	b.n .L08014988
.L0801497a:
	rsb.w r1, r1, #0x400
	muls r1, r1, r1
	sbfx r1, r1, #15, #16
	rsb.w r1, r1, #15
.L08014988:
	strh.w r0, [r9, r4, lsl #1]	@ X = q
	strh.w r0, [r8, r4, lsl #1]	@ Y = q
	ldr r0, [r5, #4]
	strb r1, [r0, r4]
	ldr r0, [r5, #4]
	lsls r1, r1, #4
	strb r1, [r0, r4]
	.inst.n 0x1c64			@ adds r4, r4, #1
	sxth r4, r4
.L0801499e:
	subs r0, r4, #2			@ j = entry count - 2
	b.n .L080149c0
	.byte 0x00, 0xbf		@ padding
.L080149a4:
	ldrh.w r2, [r8, r0, lsl #1]
	strh.w r2, [r9, r4, lsl #1]	@ X[new] = Y[j]
	ldrh.w r2, [r9, r0, lsl #1]
	strh.w r2, [r8, r4, lsl #1]	@ Y[new] = X[j]
	ldr r1, [r5, #4]
	ldrb r2, [r1, r0]
	strb r2, [r1, r4]		@ byte copied unchanged
	.inst.n 0x1c64			@ adds r4, r4, #1
	sxth r4, r4
	.inst.n 0x1e40			@ subs r0, r0, #1
.L080149c0:
	cmp r0, #0
	bge.n .L080149a4
	ldr r3, [r5, #0xc]
	movs r1, #0
	mov r0, r1
	strh r1, [r3]
	b.n .L08014a06
.L080149ce:
	ldr r2, [r5, #0xc]
	strh.w r0, [r2, r1, lsl #1]
	ldr r3, [r5, #8]
	ldrh.w r2, [r9, r0, lsl #1]
	strh.w r2, [r3, r1, lsl #1]
	b.n .L080149f6
.L080149e0:
	ldr r6, [r5, #8]
	ldrsh.w r2, [r9, r0, lsl #1]
	ldrh.w r3, [r6, r1, lsl #1]
	cmp r3, r2
	bge.n .L080149f0
	mov r2, r3
.L080149f0:
	strh.w r2, [r6, r1, lsl #1]
	.inst.n 0x1c40			@ adds r0, r0, #1
.L080149f6:
	ldrsh.w r2, [r8, r0, lsl #1]
	cmp r2, r1
	bne.n .L08014a02
	cmp r0, r4
	blt.n .L080149e0
.L08014a02:
	.inst.n 0x1c49			@ adds r1, r1, #1
	sxth r1, r1
.L08014a06:
	cmp r0, r4
	blt.n .L080149ce
	mov r0, r9
	bl fn_08022c44			@ free the scratch area
	b.n .L080147e0

@ ----------------------------------------------------------------------------
@ short_pair_first_ge_second - compares two signed halfwords.
@ Parameter: r0 = pointer to two signed halfwords.
@ Returns r0 = 1 when halfword[0] >= halfword[1], otherwise 0 (both loaded with
@ ldrsh, compared with cmp, branch on gt). Uses r1.
@ ----------------------------------------------------------------------------
	.section .text.short_pair_first_ge_second,"ax",%progbits
	.global short_pair_first_ge_second
	.thumb_func
	.type short_pair_first_ge_second, %function
short_pair_first_ge_second:
	ldrsh.w r1, [r0, #2]
	ldrsh.w r0, [r0]
	cmp r1, r0
	bgt.n .L08014a22
	movs r0, #1
	bx lr
.L08014a22:
	movs r0, #0
	bx lr

@ ----------------------------------------------------------------------------
@ fn_08014a26 - additive blend of two RGB565 values.
@ Parameters: r0 = source RGB565 value, r1 = destination RGB565 value,
@ r2 = alpha. Returns r0 = a 16-bit value.
@ Alpha below 3: returns the destination value & 0xffff.
@ Otherwise adds the channels (red bits 11-15, green bits 5-10, blue bits
@ 0-4) of both values, each clamped to 0x1f / 0x3f / 0x1f (a sum above
@ 0x1e / 0x3e / 0x1e gives the limit). Alpha 0xff returns the sum; any other
@ alpha returns blend_565_0801d9dc(sum, destination) & 0xffff.
@ The arguments are spilled to the stack at entry (push {r0, r1, r2, r4, lr}).
@ ----------------------------------------------------------------------------
	.section .text.fn_08014a26,"ax",%progbits
	.global fn_08014a26
	.thumb_func
	.type fn_08014a26, %function
fn_08014a26:
	push {r0, r1, r2, r4, lr}
	sub sp, #4
	cmp r2, #2
	bhi.n .L08014a36
	ldrh.w r0, [sp, #8]		@ alpha < 3: destination value
.L08014a32:
	add sp, #0x10
	pop {r4, pc}
.L08014a36:
	ldrh.w r3, [sp, #8]		@ destination
	ldrh.w r0, [sp, #4]		@ source
	lsrs r1, r3, #11
	add.w r1, r1, r0, lsr #11	@ red sum
	cmp r1, #0x1f
	bcc.n .L08014a4a
	movs r1, #0x1f
.L08014a4a:
	bfi r0, r1, #11, #5
	ubfx r1, r3, #5, #6
	ubfx r4, r0, #5, #6
	add r1, r4			@ green sum
	strh.w r0, [sp, #4]
	cmp r1, #0x3f
	bcc.n .L08014a62
	movs r1, #0x3f
.L08014a62:
	bfi r0, r1, #5, #6
	and.w r1, r3, #0x1f
	and.w r3, r0, #0x1f
	add r1, r3			@ blue sum
	strh.w r0, [sp, #4]
	cmp r1, #0x1f
	bcc.n .L08014a7a
	movs r1, #0x1f
.L08014a7a:
	bfi r0, r1, #0, #5
	strh.w r0, [sp, #4]
	cmp r2, #0xff
	beq.n .L08014a96
	ldrd r0, r1, [sp, #4]
	bl blend_565_0801d9dc
	str r0, [sp]
	ldrh.w r0, [sp]
	b.n .L08014a32
.L08014a96:
	uxth r0, r0
	b.n .L08014a32

@ ----------------------------------------------------------------------------
@ fn_08014a9a - multiplicative blend of two RGB565 values.
@ Parameters: r0 = source RGB565 value, r1 = destination RGB565 value,
@ r2 = alpha. Returns r0 = a 16-bit value.
@ Alpha below 3: returns the destination value & 0xffff.
@ Otherwise multiplies the channels: red (src >> 11) * (dst >> 11) >> 5 placed
@ at bit 11, blue (src & 0x1f) * (dst & 0x1f) >> 5, green
@ ((src >> 5) & 0x3f) * ((dst >> 5) & 0x3f) >> 6 placed at bit 5.
@ Alpha 0xff returns the result; any other alpha returns
@ blend_565_0801d9dc(result, destination) & 0xffff.
@ The arguments are spilled to the stack at entry (push {r0, r1, r2, r4, lr}).
@ ----------------------------------------------------------------------------
	.section .text.fn_08014a9a,"ax",%progbits
	.global fn_08014a9a
	.thumb_func
	.type fn_08014a9a, %function
fn_08014a9a:
	push {r0, r1, r2, r4, lr}
	sub sp, #4
	cmp r2, #2
	bhi.n .L08014aaa
	ldrh.w r0, [sp, #8]		@ alpha < 3: destination value
.L08014aa6:
	add sp, #0x10
	pop {r4, pc}
.L08014aaa:
	ldrh.w r0, [sp, #4]		@ source
	ldrh.w r1, [sp, #8]		@ destination
	lsrs r3, r0, #11
	lsrs r4, r1, #11
	smulbb r3, r3, r4
	lsrs r3, r3, #5
	bfi r0, r3, #11, #5		@ red
	and.w r3, r0, #0x1f
	and.w r4, r1, #0x1f
	smulbb r3, r3, r4
	lsrs r3, r3, #5
	bfi r0, r3, #0, #5		@ blue
	ubfx r3, r0, #5, #6
	ubfx r1, r1, #5, #6
	smulbb r1, r3, r1
	lsrs r1, r1, #6
	bfi r0, r1, #5, #6		@ green
	strh.w r0, [sp, #4]
	cmp r2, #0xff
	beq.n .L08014afc
	ldrd r0, r1, [sp, #4]
	bl blend_565_0801d9dc
	str r0, [sp]
	ldrh.w r0, [sp]
	b.n .L08014aa6
.L08014afc:
	uxth r0, r0
	b.n .L08014aa6

@ ----------------------------------------------------------------------------
@ fn_08014b00 - subtractive blend of two RGB565 values.
@ Parameters: r0 = source RGB565 value, r1 = destination RGB565 value,
@ r2 = alpha. Returns r0 = a 16-bit value.
@ Alpha below 3: returns the destination value & 0xffff.
@ Otherwise subtracts the channels of the source from those of the
@ destination (red bits 11-15, green bits 5-10, blue bits 0-4), each result
@ limited below at 0. Alpha 0xff returns the result; any other alpha returns
@ blend_565_0801d9dc(result, destination) & 0xffff.
@ The arguments are spilled to the stack at entry (push {r0, r1, r2, r4, lr}).
@ ----------------------------------------------------------------------------
	.section .text.fn_08014b00,"ax",%progbits
	.p2align 2
	.global fn_08014b00
	.thumb_func
	.type fn_08014b00, %function
fn_08014b00:
	push {r0, r1, r2, r4, lr}
	sub sp, #4
	cmp r2, #2
	bhi.n .L08014b10
	ldrh.w r0, [sp, #8]		@ alpha < 3: destination value
.L08014b0c:
	add sp, #0x10
	pop {r4, pc}
.L08014b10:
	ldrh.w r3, [sp, #8]		@ destination
	ldrh.w r0, [sp, #4]		@ source
	lsrs r1, r3, #11
	sub.w r1, r1, r0, lsr #11	@ red difference
	cmp r1, #0
	bgt.n .L08014b24
	movs r1, #0
.L08014b24:
	bfi r0, r1, #11, #5
	ubfx r1, r3, #5, #6
	ubfx r4, r0, #5, #6
	subs r1, r1, r4			@ green difference
	strh.w r0, [sp, #4]
	cmp r1, #0
	bgt.n .L08014b3c
	movs r1, #0
.L08014b3c:
	bfi r0, r1, #5, #6
	and.w r1, r3, #0x1f
	and.w r3, r0, #0x1f
	subs r1, r1, r3			@ blue difference
	strh.w r0, [sp, #4]
	cmp r1, #0
	bgt.n .L08014b54
	movs r1, #0
.L08014b54:
	bfi r0, r1, #0, #5
	strh.w r0, [sp, #4]
	cmp r2, #0xff
	beq.n .L08014b70
	ldrd r0, r1, [sp, #4]
	bl blend_565_0801d9dc
	str r0, [sp]
	ldrh.w r0, [sp]
	b.n .L08014b0c
.L08014b70:
	uxth r0, r0
	b.n .L08014b0c

@ ----------------------------------------------------------------------------
@ fn_08014bd4 - copies a rectangle of a source image into two buffers.
@ Parameters: r0 = rectangle (four int16 x0, y0, x1, y1); r1 = source base;
@ r2 and r3 = factors used by mode 0x14; stack: source row pitch (sp + 0x58
@ after the entry push), a word at sp + 0x5c that is not used, mode (sp +
@ 0x60), destination halfword buffer (sp + 0x64), destination byte buffer
@ (sp + 0x68). The source base is read from sp + 0x28 (the pushed r1). No
@ return value.
@ Modes 4 and 6: n = rect_area(rect); fill_bytes_ff(byte buffer, n); copies
@ each row y0..y1 of (x1 - x0 + 1) halfwords from source + (pitch*y + x0)*2 to
@ the halfword buffer with copy_bytes_08022ce0; mode 6 then zeroes every byte
@ of the byte buffer whose halfword in the halfword buffer is 0.
@ Mode 5: the source has 3 bytes per pixel at (pitch*y0 + x0)*3 + source:
@ each pixel stores its first halfword to the halfword buffer and its third
@ byte to the byte buffer; row advance (pitch - width)*3.
@ Mode 0x14: copies the rows of halfwords from source + (pitch*y0 + x0)*2 to
@ the halfword buffer, then copies byte rows of width bytes from source +
@ pitch*y0 + x0 + factor2*2*factor3 to the byte buffer with row step pitch.
@ Other modes do nothing.
@ Two padding bytes (0x00 0xbf) sit at 0x08014ca2.
@ ----------------------------------------------------------------------------
	.section .text.fn_08014bd4,"ax",%progbits
	.global fn_08014bd4
	.thumb_func
	.type fn_08014bd4, %function
fn_08014bd4:
	push.w {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0x24
	mov r4, r0			@ r4 = rectangle
	ldr r6, [sp, #0x58]		@ r6 = source row pitch
	ldrd r5, r7, [sp, #0x64]	@ r5 = halfword buffer, r7 = byte buffer
	lsls r0, r6, #1
	ldr.w r9, [sp, #0x60]		@ r9 = mode
	ldr.w r10, [sp, #0x28]		@ r10 = source base
	sxth.w r11, r0			@ r11 = pitch*2
	cmp.w r9, #4
	beq.n .L08014c3c
	cmp.w r9, #6
	beq.n .L08014c3c
	cmp.w r9, #5
	beq.n .L08014cbc
	cmp.w r9, #0x14
	bne.n .L08014cb6
	ldrsh.w r1, [r4]
	ldrsh.w r0, [r4, #2]
	str.w r11, [sp, #0xc]
	mla r3, r6, r0, r1
	add.w r2, r10, r3, lsl #1
	str r2, [sp]
	ldrh r2, [r4, #6]
	mov.w r8, #0
	subs r0, r2, r0
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth.w r9, r0			@ r9 = height
	ldrh r0, [r4, #4]
	subs r0, r0, r1
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth.w r10, r0			@ r10 = width
	lsl.w r11, r10, #1		@ r11 = width*2
	b.n .L08014d40
.L08014c3c:
	mov r0, r4
	bl rect_area
	mov r1, r0
	str r0, [sp, #0xc]
	mov r0, r7
	bl fill_bytes_ff
	ldrsh.w r0, [r4]
	ldrsh.w r8, [r4, #2]
	ldrh r1, [r4, #4]
	mla r2, r6, r8, r0
	subs r0, r1, r0
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth r0, r0
	str r0, [sp, #0x18]
	lsls r0, r0, #1
	add.w r10, r10, r2, lsl #1
	mov r6, r5
	str r0, [sp, #8]
	b.n .L08014c88
.L08014c6e:
	mov r1, r10
	mov r0, r6
	ldr r2, [sp, #8]
	bl copy_bytes_08022ce0
	ldr r0, [sp, #0x18]
	add.w r8, r8, #1
	add r10, r11
	add.w r6, r6, r0, lsl #1
	sxth.w r8, r8
.L08014c88:
	ldrsh.w r0, [r4, #6]
	cmp r0, r8
	bge.n .L08014c6e
	cmp.w r9, #6
	bne.n .L08014cb6
	movs r1, #0
	strh.w r1, [sp]
	mov r0, r1
	mov r2, r1
	b.n .L08014cb0
	.byte 0x00, 0xbf		@ padding
.L08014ca4:
	ldrh.w r3, [r5, r2, lsl #1]
	cmp r3, r0
	bne.n .L08014cae
	strb r1, [r7, r2]		@ halfword is 0: zero the byte
.L08014cae:
	.inst.n 0x1c52			@ adds r2, r2, #1
.L08014cb0:
	ldr r3, [sp, #0xc]
	cmp r2, r3
	bcc.n .L08014ca4
.L08014cb6:
	add sp, #0x34
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08014cbc:
	ldrsh.w r1, [r4]
	ldrsh.w r3, [r4, #2]
	mla r0, r6, r3, r1
	add.w r2, r0, r0, lsl #1
	add.w r0, r2, r10		@ source pointer for 3 bytes per pixel
	ldrh r2, [r4, #4]
	subs r1, r2, r1
	.inst.n 0x1c49			@ adds r1, r1, #1
	sxth r2, r1			@ r2 = width
	subs r1, r6, r2
	add.w r1, r1, r1, lsl #1
	sxth r6, r1			@ r6 = (pitch - width)*3
	ldrh r1, [r4, #6]
	subs r1, r1, r3
	.inst.n 0x1c49			@ adds r1, r1, #1
	sxth r4, r1			@ r4 = height
	movs r3, #0
	b.n .L08014d1c
.L08014cec:
	movs r1, #0
	b.n .L08014d0c
.L08014cf0:
	ldrb.w r12, [r0, #2]
	strb.w r12, [r7, r1]		@ third byte to the byte buffer
	ldrb.w r12, [r0], #1
	ldrb.w r8, [r0], #2
	add.w r12, r12, r8, lsl #8
	strh.w r12, [r5, r1, lsl #1]	@ first halfword to the halfword buffer
	.inst.n 0x1c49			@ adds r1, r1, #1
	sxth r1, r1
.L08014d0c:
	cmp r1, r2
	blt.n .L08014cf0
	.inst.n 0x1c5b			@ adds r3, r3, #1
	add.w r5, r5, r2, lsl #1
	add r7, r2
	add r0, r6
	sxth r3, r3
.L08014d1c:
	cmp r3, r4
	blt.n .L08014cec
	b.n .L08014cb6
.L08014d22:
	mov r2, r11
	mov r0, r5
	ldr r1, [sp]
	bl copy_bytes_08022ce0
	ldr r1, [sp, #0xc]
	ldr r0, [sp]
	add.w r5, r5, r10, lsl #1
	add r0, r1
	str r0, [sp]
	add.w r0, r8, #1
	sxth.w r8, r0
.L08014d40:
	cmp r8, r9
	blt.n .L08014d22
	ldrd r0, r1, [sp, #0x28]
	lsls r2, r1, #1
	ldr r1, [sp, #0x30]
	mla r0, r2, r1, r0
	ldrsh.w r1, [r4]
	ldrsh.w r2, [r4, #2]
	mla r1, r6, r2, r1
	adds r5, r1, r0
	movs r4, #0
	b.n .L08014d74
.L08014d62:
	mov r2, r10
	mov r1, r5
	mov r0, r7
	bl copy_bytes_08022ce0
	.inst.n 0x1c64			@ adds r4, r4, #1
	add r7, r10
	add r5, r6
	sxth r4, r4
.L08014d74:
	cmp r4, r9
	blt.n .L08014d62
	b.n .L08014cb6

@ ----------------------------------------------------------------------------
@ count_shorts_until_0x1fff - index of the first halfword equal to 0x1fff.
@ Parameter: r0 = pointer to signed halfwords. Returns r0 = the index of the
@ first halfword equal to 0x1fff (index starts at 0; each halfword is loaded
@ with ldrsh and compared with 0x1fff). Uses r1-r3.
@ ----------------------------------------------------------------------------
	.section .text.count_shorts_until_0x1fff,"ax",%progbits
	.global count_shorts_until_0x1fff
	.thumb_func
	.type count_shorts_until_0x1fff, %function
count_shorts_until_0x1fff:
	mov r1, r0
	movs r0, #0
	movw r2, #0x1fff
	b.n .L08014d86
.L08014d84:
	.inst.n 0x1c40			@ adds r0, r0, #1
.L08014d86:
	ldrsh.w r3, [r1, r0, lsl #1]
	cmp r3, r2
	bne.n .L08014d84
	bx lr

@ ----------------------------------------------------------------------------
@ fn_08014d90 - forwards two of its arguments to fn_0801d708.
@ Parameters: r0 unused; r1, r2 and r3 are passed on. Calls
@ fn_0801d708(r0 = r1, r1 = r2, r2 and r3 as at entry), stores the result on
@ the stack and returns its low halfword (ldrh) in r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08014d90,"ax",%progbits
	.global fn_08014d90
	.thumb_func
	.type fn_08014d90, %function
fn_08014d90:
	push {r3, lr}
	mov r0, r1
	mov r1, r2
	bl fn_0801d708
	str r0, [sp]
	ldrh.w r0, [sp]
	pop {r3, pc}

@ ----------------------------------------------------------------------------
@ fn_08014da2 - draws one image record of a context, row by row or at once.
@ Parameters: r0 = context (kept in r7), r1 = halfword record (r6; byte +0xb is
@ a level, words +8 and +0x10 are lookup keys, halfwords 0 and 1 are compared
@ with 0 and 0x100), r2 = rectangle (r5), r3 = lookup argument.
@ Returns r0 = 1, or 0 when the lookup fails or a row read fails.
@ Does nothing but return 1 when byte [record + 0xb] is 2 or less.
@ Looks up an entry with fn_0801244c(argument, key1, key2) and returns 0 when
@ it is null (entry in r4). Chooses a mode (r9) from entry byte +0x14 & 0x1f:
@ 6 when fn_080211bc returns nonzero; value 0xe stays 0xe only when the record
@ halfwords are 0 and 0x100, else it becomes 5 and entry word +0x18 is cleared;
@ value 0x14 stays 0x14; otherwise 4 or 5 depending on fn_0802119c.
@ Entry word +0x20 nonzero: calls fn_08029a76(context, rectangle, entry word
@ +0x20). Entry word +0x18 zero: intersects the clip rectangle at
@ [context + 8] with the rectangle (rect_intersect), allocates width*3 bytes
@ with fn_08022bac, and loops over the rows: for each row it intersects again,
@ reads the row with fn_08021990(entry, x offset, y offset, width, buffer) and
@ draws it with fn_0801e230(context, record, rect, buffer, mode). Entry word
@ +0x18 nonzero: draws that data once with fn_0801e230, with the rectangle
@ offset by fn_080122e0 when the halfword pair is not 0 and 0x100, the clip
@ rectangle at [context + 8] temporarily replaced.
@ When fn_08021990 returns other than 1 for a row, the entry is released with
@ fn_08021836, the buffer is freed with fn_08022c44, the clip pointer is
@ restored and 0 is returned. Every other path releases the entry once with
@ fn_08021836 and returns 1.
@ Two padding bytes (0x0000) end the unit.
@ ----------------------------------------------------------------------------
	.section .text.fn_08014da2,"ax",%progbits
	.global fn_08014da2
	.thumb_func
	.type fn_08014da2, %function
fn_08014da2:
	push.w {r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov r7, r0			@ r7 = context
	ldrb r0, [r1, #0xb]
	sub sp, #0x24
	mov r5, r2			@ r5 = rectangle
	mov r6, r1			@ r6 = record
	cmp r0, #2
	bhi.n .L08014dbc
.L08014db4:
	movs r0, #1
.L08014db6:
	add sp, #0x24
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08014dbc:
	mov r0, r3
	ldr r2, [r6, #0x10]
	ldr r1, [r6, #8]
	bl fn_0801244c
	subs r4, r0, #0			@ r4 = entry
	beq.n .L08014db6		@ not found: return 0
	ldrb r0, [r4, #0x14]
	and.w r0, r0, #0x1f
	bl fn_080211bc
	mov.w r8, #0x100
	cbz r0, .L08014dde
	movs r0, #6
	b.n .L08014e02
.L08014dde:
	ldrb r0, [r4, #0x14]
	and.w r0, r0, #0x1f
	cmp r0, #0xe
	beq.n .L08014df6
	cmp r0, #0x14
	beq.n .L08014e02
	bl fn_0802119c
	cbz r0, .L08014e00
	movs r0, #5
	b.n .L08014e02
.L08014df6:
	ldrh r0, [r6]
	mov.w r9, #0xe
	cbnz r0, .L08014e0c
	b.n .L08014e06
.L08014e00:
	movs r0, #4
.L08014e02:
	mov r9, r0			@ r9 = mode
	b.n .L08014e14
.L08014e06:
	ldrh r0, [r6, #2]
	cmp r0, r8
	beq.n .L08014e14
.L08014e0c:
	movs r0, #0
	mov.w r9, #5
	str r0, [r4, #0x18]		@ clear entry word +0x18
.L08014e14:
	ldr r2, [r4, #0x20]
	cbz r2, .L08014e22
	mov r1, r5
	mov r0, r7
	bl fn_08029a76
	b.n .L08014f92
.L08014e22:
	ldr r0, [r4, #0x18]
	cbz r0, .L08014ea0
	mov r1, r5
	add r0, sp, #8
	bl copy_rect_0801cfd6		@ local copy of the rectangle
	ldrsh.w r3, [r6]
	cbnz r3, .L08014e3a
	ldrh r0, [r6, #2]
	cmp r0, r8
	beq.n .L08014e8e
.L08014e3a:
	ldrh r0, [r5, #4]
	ldrh r1, [r5]
	ldrh r2, [r5, #2]
	subs r0, r0, r1
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth r1, r0			@ width
	ldrh r0, [r5, #6]
	add.w r12, r6, #4
	subs r0, r0, r2
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth r2, r0			@ height
	ldrh r0, [r6, #2]
	strd r0, r12, [sp]
	add r0, sp, #8
	bl fn_080122e0
	ldrh.w r0, [sp, #8]
	ldrh r1, [r5]
	add r0, r1
	strh.w r0, [sp, #8]
	ldrh.w r1, [sp, #0xa]
	ldrh r0, [r5, #2]
	add r0, r1
	strh.w r0, [sp, #0xa]
	ldrh.w r0, [sp, #0xc]
	ldrh r1, [r5]
	add r0, r1
	strh.w r0, [sp, #0xc]
	ldrh.w r1, [sp, #0xe]
	ldrh r0, [r5, #2]
	add r0, r1
	strh.w r0, [sp, #0xe]
.L08014e8e:
	add r2, sp, #8
	add r0, sp, #0x10
	ldr r1, [r7, #8]
	bl rect_intersect
	cmp r0, #0
	beq.n .L08014f92
	add r0, sp, #0x10
	b.n .L08014ea2
.L08014ea0:
	b.n .L08014ebe
.L08014ea2:
	ldr.w r8, [r7, #8]		@ saved clip pointer
	str r0, [r7, #8]
	str.w r9, [sp]
	mov r2, r5
	mov r1, r6
	mov r0, r7
	ldr r3, [r4, #0x18]
	bl fn_0801e230
	str.w r8, [r7, #8]		@ restore clip pointer
	b.n .L08014f92
.L08014ebe:
	mov r2, r5
	add r0, sp, #0x10
	ldr r1, [r7, #8]
	bl rect_intersect
	cbz r0, .L08014f44
	ldrh.w r0, [sp, #0x14]
	ldrh.w r1, [sp, #0x10]
	subs r0, r0, r1
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth.w r11, r0			@ r11 = width
	add.w r0, r11, r11, lsl #1	@ width*3
	bl fn_08022bac
	str r0, [sp, #0xc]		@ row buffer
	add r1, sp, #0x10
	add r0, sp, #4
	ldr.w r10, [r7, #8]		@ saved clip pointer
	bl copy_rect_0801cfd6
	movs r1, #1
	add r0, sp, #4
	bl rect_set_height
	ldrsh.w r0, [sp, #0x10]
	ldrsh.w r1, [r5]
	ldrsh.w r8, [sp, #0x12]
	subs r0, r0, r1
	str r0, [sp, #0x18]		@ x offset
	ldrsh.w r0, [r5, #2]
	sub.w r5, r8, r0		@ y offset
	b.n .L08014f80
.L08014f12:
	add r2, sp, #4
	mov r1, r10
	add r0, sp, #0x1c
	bl rect_intersect
	cbz r0, .L08014f7c
	ldr r0, [sp, #0xc]
	str r0, [sp]
	ldr r0, [sp, #0x18]
	mov r3, r11
	sxth r1, r0
	sxth r2, r5
	mov r0, r4
	bl fn_08021990
	cmp r0, #1
	beq.n .L08014f52
	mov r0, r4
	bl fn_08021836
	ldr r0, [sp, #0xc]
	bl fn_08022c44
	mov r0, r4
	b.n .L08014f46
.L08014f44:
	b.n .L08014f92
.L08014f46:
	bl fn_08021836
	movs r0, #0
	str.w r10, [r7, #8]		@ restore clip pointer
	b.n .L08014db6
.L08014f52:
	add r0, sp, #0x1c
	str r0, [r7, #8]
	str.w r9, [sp]
	add r2, sp, #4
	mov r1, r6
	mov r0, r7
	ldr r3, [sp, #0xc]
	bl fn_0801e230
	ldrh.w r0, [sp, #6]
	.inst.n 0x1c40			@ adds r0, r0, #1
	strh.w r0, [sp, #6]
	ldrh.w r0, [sp, #0xa]
	.inst.n 0x1c40			@ adds r0, r0, #1
	strh.w r0, [sp, #0xa]
	.inst.n 0x1c6d			@ adds r5, r5, #1
.L08014f7c:
	add.w r8, r8, #1
.L08014f80:
	ldrsh.w r0, [sp, #0x16]
	cmp r0, r8
	bge.n .L08014f12
	str.w r10, [r7, #8]
	ldr r0, [sp, #0xc]
	bl fn_08022c44
.L08014f92:
	mov r0, r4
	bl fn_08021836
	b.n .L08014db4
	.short 0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08014f9c - writes a rectangle of 16-bit pixels to the display window.
@ Parameters: r0 = object (word +0xc is a pointer), r1 = rectangle (four
@ signed halfwords x0, y0, x1, y1), r2 = pointer to 16-bit pixels.
@ Calls fn_08009e30(x0, y0, x1, y1), then writes (x1 - x0 + 1) * (y1 - y0 + 1)
@ halfwords one after another to the address 0x60020000, then tail-calls
@ fn_0801dcc0(object) (the decompiler notes that it clears the words at
@ *(object + 0xc) + 0x10 and + 0x14).
@ The literal at the end of the unit holds 0x60020000; two padding bytes
@ precede it.
@ ----------------------------------------------------------------------------
	.section .text.fn_08014f9c,"ax",%progbits
	.p2align 2
	.global fn_08014f9c
	.thumb_func
	.type fn_08014f9c, %function
fn_08014f9c:
	push {r4, r5, r6, lr}
	mov r5, r2			@ r5 = pixel pointer
	mov r4, r1			@ r4 = rectangle
	mov r6, r0			@ r6 = object
	ldrsh.w r3, [r1, #6]
	ldrsh.w r2, [r1, #4]
	ldrsh.w r1, [r1, #2]
	ldrsh.w r0, [r4]
	bl fn_08009e30
	ldrsh.w r0, [r4, #4]
	ldrsh.w r1, [r4]
	ldrsh.w r2, [r4, #2]
	subs r0, r0, r1
	ldrsh.w r1, [r4, #6]
	.inst.n 0x1c40			@ adds r0, r0, #1
	subs r1, r1, r2
	.inst.n 0x1c49			@ adds r1, r1, #1
	muls r0, r1, r0			@ pixel count
	movs r1, #0
	ldr r2, .L08014ff0
	b.n .L08014fe0
.L08014fd8:
	ldrh.w r3, [r5], #2
	strh r3, [r2]			@ write one pixel to 0x60020000
	.inst.n 0x1c49			@ adds r1, r1, #1
.L08014fe0:
	cmp r1, r0
	blt.n .L08014fd8
	mov r0, r6
	pop.w {r4, r5, r6, lr}
	b.w fn_0801dcc0
	.short 0x0000			@ padding
.L08014ff0:
	.word 0x60020000

@ ----------------------------------------------------------------------------
@ fn_08014ff4 - draws the entries of type 3 of an object's list.
@ Parameters: r0 = object (kept in r7), r1 = target context (r10),
@ r2 = rectangle (r4 first, later reused as the list node).
@ No return value.
@ Initialises a record at sp + 0x10 with fn_0801de00 (record of 16 bytes);
@ sets bit 2 of the byte at sp + 0x1d from fn_080248ea(object, 0x50000) & 1;
@ computes half the rectangle width (x1 - x0 + 1) / 2 (signed halving) and
@ the centre point (x0 + half, y0 + half), stored as halfwords at sp + 0x70 and
@ sp + 0x72. alpha = fn_08024a50(object, 0). Calls fn_08023a0c(sp + 0x20,
@ target context) and stores sp + 0x10 at sp + 0x40, 0x20000 at sp + 0x54, the
@ word 0x08050f30 (d_08050f30) at sp + 0x24 and 0 at sp + 0x28.
@ Walks the list: first node from get_word_8_or_zero(object + 0x30), next node
@ from read_word_at_base_plus_offset(object + 0x30, node). For each node whose
@ byte +4 is 3: takes halfwords from node words +0x18 and +0x10 (stored at
@ sp + 0x10 and sp + 0x12), scales alpha by byte node + 5 when that is below
@ 0xfe (product >> 8, stored as byte at sp + 0x1c), maps node words +8 and +0xc
@ through fn_08022b12 (with fields of the node's word [node + 0] at +0x14, +0x18,
@ +0x1e and +0x20) and calls fn_080207f4(object, 0x1a, sp + 0x20),
@ fn_0801dde0(target context, record, centre, halfword node + 0x1a plus half,
@ the two mapped values), fn_080207f4(object, 0x1b, sp + 0x20).
@ Two padding bytes (0x0000) precede the literal pool.
@ ----------------------------------------------------------------------------
	.section .text.fn_08014ff4,"ax",%progbits
	.p2align 2
	.global fn_08014ff4
	.thumb_func
	.type fn_08014ff4, %function
fn_08014ff4:
	push.w {r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0x84
	mov r7, r0			@ r7 = object
	mov r4, r2			@ r4 = rectangle
	mov r10, r1			@ r10 = target context
	add r0, sp, #0x10
	bl fn_0801de00
	mov.w r1, #0x50000
	mov r0, r7
	bl fn_080248ea
	ldrb.w r1, [sp, #0x1d]
	bfi r1, r0, #2, #1
	strb.w r1, [sp, #0x1d]
	ldrh r1, [r4, #4]
	ldrh r0, [r4]
	subs r1, r1, r0
	.inst.n 0x1c49			@ adds r1, r1, #1
	sxth r1, r1
	add.w r1, r1, r1, lsr #31
	asrs r6, r1, #1			@ r6 = half width
	add r0, r6
	strh.w r0, [sp, #0x70]		@ centre x
	ldrh r0, [r4, #2]
	movs r1, #0
	add r0, r6
	strh.w r0, [sp, #0x72]		@ centre y
	mov r0, r7
	bl fn_08024a50
	mov r9, r0			@ r9 = alpha
	mov r1, r10
	add r0, sp, #0x20
	bl fn_08023a0c
	add r0, sp, #0x10
	str r0, [sp, #0x40]
	mov.w r0, #0x20000
	str r0, [sp, #0x54]
	ldr r0, .L0801510c
	str r0, [sp, #0x24]
	movs r0, #0
	str r0, [sp, #0x28]
	add.w r0, r7, #0x30
	mov r11, r0			@ r11 = list base (object + 0x30)
	bl get_word_8_or_zero
	b.n .L08015100
.L0801506a:
	ldrb r0, [r4, #4]
	cmp r0, #3
	bne.n .L080150f8
	ldrh r0, [r4, #0x18]
	strh.w r0, [sp, #0x10]
	ldrh r0, [r4, #0x10]
	strh.w r0, [sp, #0x12]
	ldrb r0, [r4, #5]
	cmp r0, #0xfd
	bls.n .L08015086
	mov r0, r9
	b.n .L0801508c
.L08015086:
	smulbb r0, r0, r9
	lsrs r0, r0, #8
.L0801508c:
	strb.w r0, [sp, #0x1c]		@ scaled alpha
	ldr r5, [r4]
	ldrsh.w r3, [r5, #0x20]
	ldrh r0, [r5, #0x1e]
	add r0, r3
	str r0, [sp]
	ldrd r1, r2, [r5, #0x14]
	ldr r0, [r4, #8]
	bl fn_08022b12
	mov r8, r0			@ first mapped value
	ldrsh.w r3, [r5, #0x20]
	ldrh r0, [r5, #0x1e]
	add r0, r3
	str r0, [sp]
	ldrd r1, r2, [r5, #0x14]
	ldr r0, [r4, #0xc]
	bl fn_08022b12
	mov r5, r0			@ second mapped value
	ldrh r0, [r4, #0x1a]
	add r2, sp, #0x20
	add r0, r6
	strh.w r0, [sp, #0x5c]
	add r0, sp, #0x70
	str r0, [sp, #0x44]
	movs r1, #0x1a
	str r4, [sp, #0x64]
	mov r0, r7
	bl fn_080207f4
	uxth r1, r5
	uxth.w r0, r8
	strd r0, r1, [sp]
	ldrh.w r3, [sp, #0x5c]
	add r2, sp, #0x70
	add r1, sp, #0x10
	mov r0, r10
	bl fn_0801dde0
	add r2, sp, #0x20
	movs r1, #0x1b
	mov r0, r7
	bl fn_080207f4
.L080150f8:
	mov r1, r4
	mov r0, r11
	bl read_word_at_base_plus_offset
.L08015100:
	movs r4, r0
	bne.n .L0801506a
	add sp, #0x84
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short 0x0000			@ padding
.L0801510c:
	.word d_08050f30

@ ----------------------------------------------------------------------------
@ fn_08015110 - fills a rectangle with a style, with optional rounded corners.
@ Parameters: r0 = context (stored at sp + 0x80 after the entry push), r1 =
@ style record (kept in r4; halfword/byte fields read below), r2 = rectangle.
@ No return value.
@ Does nothing when byte [style + 3] is 2 or less. Copies the rectangle with
@ copy_rect_0801d00c; when halfword [style + 0x20] > 1, byte [style + 0x22] >=
@ 0xfd and halfword [style + 0] != 0 it adds bit 2 of (byte [style + 0x23] >> 1)
@ to x0, bit 1 to y0 and subtracts bit 3 of that value from x1 and bit 0 of
@ (byte [style + 0x23] >> 1) from y1 (as the ubfx fields at 0x08015144-0x08015178).
@ Intersects with the clip rectangle at [context + 8] via rect_intersect and
@ returns when the result is empty.
@ Mode r6 = byte [style + 0xf] & 7. Mode 0 takes word [style + 4] as colour; a
@ nonzero mode takes halfword [style + 6]; the mode is cleared to 0 when the
@ colour equals halfword [style + 0xa]. r7 = fn_0801ecd0(rectangle). A
@ 28-byte structure at sp + 0x38 is cleared with zero_bytes; the colour is
@ stored at sp + 0x40 and byte [style + 2] at sp + 0x51.
@ Without corner radius (r7 = 0, halfword [style + 0] = 0, mode 0) the whole
@ rectangle is drawn with one fn_0801f730(context, structure) call, alpha byte
@ [style + 3] stored at sp + 0x50.
@ Otherwise the alpha is limited to 0xff (r11), the width and height of the
@ rectangle are computed, and the radius r5 = min(halfword [style + 0],
@ min(width, height) / 2) (signed halving). With r5 > 0 or r7 nonzero a row
@ buffer is allocated with fn_08022bac(width of the clipped rectangle), a mask
@ is built with fn_0801f1a8 and stored by table_slot_insert (slot at sp +
@ 0x74, initial -1). fn_08020e40(style + 6, width, height) gives an object
@ (r4 afterwards); with mode 2 the word [object + 8] offset by the clipped x0
@ minus x0, times 2, is stored at sp + 0x3c.
@ With r7 = 0: for each of the r5 top rows and r5 bottom rows (when inside the
@ clipped rows) the row buffer is filled with fill_bytes_08022e08, masked with
@ fn_0801ec54, and drawn with fn_0801f730 (mode 1 reads the colour per row from
@ halfwords at [object + 8]); then the middle rows are drawn, in one call when
@ fn_0801ecd0 of the middle rectangle is 0 and the mode is 0, else row by row.
@ With r7 nonzero every row of the clipped rectangle is filled, masked and
@ drawn.
@ Finally frees the row buffer with fn_08022c44, clears the slot with
@ table_slot_clear and fn_0801ec98 when the slot is not -1, and releases the
@ object with fn_08020e32 when it is nonzero.
@ Two padding bytes (0x00 0xbf) sit at 0x08015322.
@ ----------------------------------------------------------------------------
	.section .text.fn_08015110,"ax",%progbits
	.global fn_08015110
	.thumb_func
	.type fn_08015110, %function
fn_08015110:
	push.w {r0, r1, r2, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	ldrb r0, [r1, #3]
	sub sp, #0x80
	mov r4, r1			@ r4 = style record
	cmp r0, #2
	bls.n .L0801521a
	mov r1, r2
	add r0, sp, #4
	bl copy_rect_0801d00c		@ local copy of the rectangle at sp + 4
	ldrsh.w r0, [r4, #0x20]
	cmp r0, #1
	ble.n .L08015182
	ldrb.w r0, [r4, #0x22]
	cmp r0, #0xfd
	bcc.n .L08015182
	ldrh r0, [r4]
	cbz r0, .L08015182
	ldrb.w r0, [r4, #0x23]
	ldrh.w r1, [sp, #4]
	lsrs r0, r0, #1
	ubfx r2, r0, #2, #1
	add r1, r2
	strh.w r1, [sp, #4]		@ x0 += bit 2
	ldrh.w r1, [sp, #6]
	ubfx r0, r0, #1, #1
	add r0, r1
	strh.w r0, [sp, #6]		@ y0 += bit 1
	ldrb.w r1, [r4, #0x23]
	ldrh.w r0, [sp, #8]
	lsrs r1, r1, #1
	ubfx r1, r1, #3, #1
	subs r0, r0, r1
	strh.w r0, [sp, #8]		@ x1 -= bit 3
	ldrb.w r1, [r4, #0x23]
	ldrh.w r0, [sp, #0xa]
	ubfx r1, r1, #1, #1
	subs r0, r0, r1
	strh.w r0, [sp, #0xa]		@ y1 -= bit 1 of the byte
.L08015182:
	ldr r0, [sp, #0x80]
	add r1, sp, #4
	ldr r2, [r0, #8]
	add r0, sp, #0x14
	bl rect_intersect		@ clipped rectangle at sp + 0x14
	cmp r0, #0
	beq.n .L0801521a
	ldrb r0, [r4, #0xf]
	ands.w r6, r0, #7		@ r6 = mode
	beq.n .L080151ce
	ldrh r0, [r4, #6]
	strh.w r0, [sp]
.L080151a0:
	ldrh.w r0, [sp]			@ colour
	ldrh r1, [r4, #0xa]
	cmp r0, r1
	bne.n .L080151ac
	movs r6, #0			@ colour equals halfword +0xa: mode 0
.L080151ac:
	add r0, sp, #4
	bl fn_0801ecd0
	mov r7, r0
	movs r1, #0x1c
	add r0, sp, #0x38
	bl zero_bytes
	ldrb r0, [r4, #2]
	strb.w r0, [sp, #0x51]
	ldrh.w r0, [sp]
	strh.w r0, [sp, #0x40]
	cbz r7, .L080151d4
	b.n .L080151da
.L080151ce:
	ldr r0, [r4, #4]
	str r0, [sp]
	b.n .L080151a0
.L080151d4:
	ldrh r0, [r4]
	cbnz r0, .L080151da
	cbz r6, .L08015256
.L080151da:
	ldrb r0, [r4, #3]
	cmp r0, #0xfd
	bcc.n .L080151e2
	movs r0, #0xff
.L080151e2:
	mov r11, r0			@ r11 = alpha (limited to 0xff)
	ldrh.w r0, [sp, #8]
	ldrh.w r1, [sp, #4]
	subs r0, r0, r1
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth.w r10, r0			@ r10 = width
	ldrh.w r0, [sp, #0xa]
	ldrh.w r1, [sp, #6]
	subs r0, r0, r1
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth r1, r0			@ height
	mov r9, r1
	mov r0, r10
	cmp r10, r9
	blt.n .L0801520c
	mov r0, r1
.L0801520c:
	ldrsh.w r5, [r4]
	cmp.w r5, r0, asr #1
	blt.n .L08015218
	asrs r5, r0, #1			@ r5 = radius
.L08015218:
	b.n .L0801521c
.L0801521a:
	b.n .L080152a4
.L0801521c:
	ldrh.w r1, [sp, #0x18]
	ldrh.w r0, [sp, #0x14]
	subs r0, r1, r0
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth.w r8, r0			@ r8 = width of the clipped rectangle
	mov.w r0, #0xffffffff
	str r0, [sp, #0x74]		@ slot = -1
	movs r0, #0
	str r0, [sp, #0x1c]		@ row buffer = 0
	cmp r5, #0
	bgt.n .L0801523c
	cbz r7, .L0801525e
.L0801523c:
	mov r0, r8
	bl fn_08022bac
	str r0, [sp, #0x1c]
	movs r3, #0
	mov r2, r5
	add r1, sp, #4
	add r0, sp, #0x58
	bl fn_0801f1a8
	movs r1, #0
	add r0, sp, #0x58
	b.n .L08015258
.L08015256:
	b.n .L08015292
.L08015258:
	bl table_slot_insert
	str r0, [sp, #0x74]
.L0801525e:
	ldrh.w r0, [sp, #0x14]
	strh.w r0, [sp, #0xc]
	ldrh.w r0, [sp, #0x18]
	strh.w r0, [sp, #0x10]
	ldr r0, [sp, #0x1c]
	str r0, [sp, #0x44]
	add r0, sp, #0xc
	str r0, [sp, #0x38]
	str r0, [sp, #0x4c]
	movs r0, #0xff
	strb.w r0, [sp, #0x50]
	mov r2, r9
	mov r1, r10
	adds r0, r4, #6
	bl fn_08020e40
	movs r4, r0			@ r4 = object (or 0)
	beq.n .L080152be
	cmp r6, #2
	beq.n .L080152aa
	b.n .L080152be
.L08015292:
	add r0, sp, #4
	str r0, [sp, #0x38]
	ldrb r0, [r4, #3]
	strb.w r0, [sp, #0x50]
	add r1, sp, #0x38
	ldr r0, [sp, #0x80]
	bl fn_0801f730
.L080152a4:
	add sp, #0x8c
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L080152aa:
	ldrsh.w r1, [sp, #0x14]
	ldr r0, [r4, #8]
	add.w r0, r0, r1, lsl #1
	ldrsh.w r1, [sp, #4]
	sub.w r0, r0, r1, lsl #1
	str r0, [sp, #0x3c]
.L080152be:
	cmp r7, #0
	beq.n .L080153be
	ldrsh.w r5, [sp, #0x16]
	b.n .L08015318
.L080152c8:
	sxth r7, r5
	strh.w r7, [sp, #0xe]
	strh.w r7, [sp, #0x12]
	mov r2, r8
	mov r1, r11
	ldr r0, [sp, #0x1c]
	bl fill_bytes_08022e08
	ldrsh.w r1, [sp, #0x14]
	mov r3, r8
	mov r2, r7
	ldr r0, [sp, #0x1c]
	bl fn_0801ec54
	strb.w r0, [sp, #0x48]
	cmp r0, #1
	bne.n .L080152f8
	movs r0, #2
	strb.w r0, [sp, #0x48]
.L080152f8:
	cmp r6, #1
	bne.n .L0801530e
	ldrsh.w r1, [sp, #6]
	ldr r0, [r4, #8]
	subs r1, r5, r1
	add.w r0, r0, r1, lsl #1
	ldrh r0, [r0]
	strh.w r0, [sp, #0x40]
.L0801530e:
	add r1, sp, #0x38
	ldr r0, [sp, #0x80]
	bl fn_0801f730
	.inst.n 0x1c6d			@ adds r5, r5, #1
.L08015318:
	ldrsh.w r0, [sp, #0x1a]
	cmp r0, r5
	bge.n .L080152c8
	b.n .L08015492
	.byte 0x00, 0xbf		@ padding
.L08015324:
	ldrh.w r0, [sp, #6]
	ldrsh.w r1, [sp, #0x16]
	add r0, r7
	sxth.w r9, r0
	ldrh.w r0, [sp, #0xa]
	subs r0, r0, r7
	sxth.w r10, r0
	cmp r1, r9
	ble.n .L08015348
	ldrsh.w r1, [sp, #0x1a]
	cmp r1, r10
	blt.n .L080153d2
.L08015348:
	mov r2, r8
	mov r1, r11
	ldr r0, [sp, #0x1c]
	bl fill_bytes_08022e08
	ldrsh.w r1, [sp, #0xc]
	mov r3, r8
	mov r2, r9
	ldr r0, [sp, #0x1c]
	bl fn_0801ec54
	strb.w r0, [sp, #0x48]
	cmp r0, #1
	bne.n .L0801536e
	movs r0, #2
	strb.w r0, [sp, #0x48]
.L0801536e:
	ldrsh.w r1, [sp, #0x16]
	cmp r1, r9
	bgt.n .L0801539e
	strh.w r9, [sp, #0xe]
	strh.w r9, [sp, #0x12]
	cmp r6, #1
	bne.n .L08015396
	ldrsh.w r2, [sp, #6]
	ldr r1, [r4, #8]
	sub.w r0, r9, r2
	add.w r0, r1, r0, lsl #1
	ldrh r0, [r0]
	strh.w r0, [sp, #0x40]
.L08015396:
	add r1, sp, #0x38
	ldr r0, [sp, #0x80]
	bl fn_0801f730
.L0801539e:
	ldrsh.w r1, [sp, #0x1a]
	cmp r1, r10
	blt.n .L080153d2
	strh.w r10, [sp, #0xe]
	strh.w r10, [sp, #0x12]
	cmp r6, #1
	bne.n .L080153ca
	ldrsh.w r0, [sp, #6]
	ldr r2, [r4, #8]
	sub.w r0, r10, r0
	b.n .L080153c0
.L080153be:
	b.n .L080153d4
.L080153c0:
	add.w r0, r2, r0, lsl #1
	ldrh r0, [r0]
	strh.w r0, [sp, #0x40]
.L080153ca:
	add r1, sp, #0x38
	ldr r0, [sp, #0x80]
	bl fn_0801f730
.L080153d2:
	.inst.n 0x1c7f			@ adds r7, r7, #1
.L080153d4:
	cmp r7, r5
	blt.n .L08015324
	ldrh.w r0, [sp, #4]
	strh.w r0, [sp, #0x78]
	ldrh.w r0, [sp, #8]
	strh.w r0, [sp, #0x7c]
	ldrh.w r0, [sp, #6]
	add r0, r5
	strh.w r0, [sp, #0x7a]
	ldrh.w r0, [sp, #0xa]
	subs r0, r0, r5
	strh.w r0, [sp, #0x7e]
	add r0, sp, #0x78
	bl fn_0801ecd0
	mov r7, r0
	orrs r0, r6
	beq.n .L08015422
	movs r0, #1
	strb.w r0, [sp, #0x48]
	ldrsh.w r0, [sp, #0xa]
	strb.w r11, [sp, #0x50]
	sub.w r9, r0, r5
	ldrsh.w r0, [sp, #6]
	add r5, r0
	b.n .L0801548e
.L08015422:
	ldrh.w r0, [sp, #6]
	strb.w r11, [sp, #0x50]
	add r0, r5
	strh.w r0, [sp, #0xe]
	ldrh.w r0, [sp, #0xa]
	add r1, sp, #0x38
	subs r0, r0, r5
	strh.w r0, [sp, #0x12]
	movs r0, #0
	str r0, [sp, #0x44]
	ldr r0, [sp, #0x80]
	bl fn_0801f730
	b.n .L08015492
.L08015448:
	cbz r7, .L08015466
	mov r2, r8
	mov r1, r11
	ldr r0, [sp, #0x1c]
	bl fill_bytes_08022e08
	ldrsh.w r1, [sp, #0x14]
	mov r3, r8
	sxth r2, r5
	ldr r0, [sp, #0x1c]
	bl fn_0801ec54
	strb.w r0, [sp, #0x48]
.L08015466:
	strh.w r5, [sp, #0xe]
	strh.w r5, [sp, #0x12]
	cmp r6, #1
	bne.n .L08015484
	ldrsh.w r0, [sp, #6]
	ldr r1, [r4, #8]
	subs r0, r5, r0
	add.w r0, r1, r0, lsl #1
	ldrh r0, [r0]
	strh.w r0, [sp, #0x40]
.L08015484:
	add r1, sp, #0x38
	ldr r0, [sp, #0x80]
	bl fn_0801f730
	.inst.n 0x1c6d			@ adds r5, r5, #1
.L0801548e:
	cmp r5, r9
	ble.n .L08015448
.L08015492:
	ldr r0, [sp, #0x1c]
	cbz r0, .L0801549a
	bl fn_08022c44
.L0801549a:
	ldr r0, [sp, #0x74]
	.inst.n 0x1c40			@ adds r0, r0, #1
	beq.n .L080154ac
	ldr r0, [sp, #0x74]
	bl table_slot_clear
	add r0, sp, #0x58
	bl fn_0801ec98
.L080154ac:
	cmp r4, #0
	beq.w .L080152a4
	mov r0, r4
	bl fn_08020e32
	b.n .L080152a4
