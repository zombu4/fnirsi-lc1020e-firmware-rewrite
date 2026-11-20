@ gfx_06.s - graphics module, part 06: grid line drawing and object frame drawing
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0801631c - draws the grid lines of an object.
@ Parameters: r0 = object (rectangle at +0x14, grid line counts at halfwords
@ +0x7e (horizontal lines) and +0x80 (vertical lines), scale halfwords +0x84
@ and +0x86), r1 = target context (clip pointer at +8). No return value.
@ Intersects the object rectangle with the clip at *(context+8) using
@ rect_intersect (0x08011e4c); returns at once when the result is empty.
@ Otherwise it saves the clip pointer, replaces it with the intersection and
@ takes offsets from fn_0802499c, fn_08024af8, fn_08024b88, fn_08024070 and
@ fn_08024208, and the scales from fn_08023e7c / fn_08023e48 multiplied with
@ the halfwords +0x84 / +0x86 (product * 256, arithmetic shift right 16 via
@ sbfx).
@ Builds a record on the stack with fn_08023a0c and brackets every line with
@ fn_080207f4(object, 0x1a / 0x1b, record).
@ If halfword +0x7e is nonzero it draws that many horizontal lines at
@ y = base + (scale_y * i) / (count - 1), from x = halfword +0x14 to halfword
@ +0x18, with fn_0801e8b8(context, record, point 1, point 2).
@ If halfword +0x80 is nonzero it draws that many vertical lines at
@ x = base + (scale_x * i) / (count - 1), from y = halfword +0x16 to +0x1a.
@ When fn_08024bac(object, 0, 0x31) > 2 and fn_0802499c(object, 0) > 0, bits of
@ the byte fn_08024bac(object, 0, 0x33) skip the first line (bit 1 for
@ horizontal with fn_08024b88 = 0, bit 2 for vertical with fn_08024af8 = 0)
@ or the last line (bit 0 for horizontal with fn_08024a98 = 0, bit 3 for
@ vertical with fn_08024b34 = 0).
@ At the end the clip pointer of the context is restored.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801631c,"ax",%progbits
	.p2align 2
	.global fn_0801631c
	.thumb_func
	.type fn_0801631c, %function
fn_0801631c:
	push.w {r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov r8, r1
	ldr r2, [r1, #0x8]
	sub sp, #0x9c
	mov r4, r0
	add.w r1, r0, #0x14
	add r0, sp, #0x90
	bl rect_intersect
	cmp r0, #0x0
	beq.n .L08016434
	ldr.w r0, [r8, #0x8]
	str r0, [sp, #0x7c]
	add r1, sp, #0x90
	str.w r1, [r8, #0x8]
	movs r1, #0x0
	mov r0, r4
	bl fn_0802499c
	mov r5, r0
	movs r1, #0x0
	mov r0, r4
	bl fn_08024af8
	add r0, r5
	sxth r0, r0
	str r0, [sp, #0x80]
	movs r1, #0x0
	mov r0, r4
	bl fn_08024b88
	add r0, r5
	sxth r5, r0
	mov r0, r4
	bl fn_08023e7c
	ldrh.w r1, [r4, #0x84]
	muls r0, r1, r0
	sbfx r0, r0, #0x8, #0x10
	str r0, [sp, #0x6c]
	mov r0, r4
	bl fn_08023e48
	ldrh.w r1, [r4, #0x86]
	muls r0, r1, r0
	sbfx r0, r0, #0x8, #0x10
	str r0, [sp, #0x74]
	add r0, sp, #0x60
	bl fn_0801e8d2
	add r2, sp, #0x60
	movs r1, #0x0
	mov r0, r4
	bl fn_080250b6
	mov r1, r8
	mov r0, sp
	bl fn_08023a0c
	movs r6, #0x0
	add r0, sp, #0x60
	str r0, [sp, #0x18]
	subs r0, r6, #0x1
	str r0, [sp, #0x38]
	ldr.w r10, .L0801657c
	str r6, [sp, #0x34]
	strd r10, r6, [sp, #0x4]
	str r6, [sp, #0x24]
	mov r2, sp
	movs r1, #0x1a
	mov r0, r4
	str r6, [sp, #0x28]
	bl fn_080207f4
	mov r0, r4
	movs r2, #0x31
	mov r1, r6
	bl fn_08024bac
	and.w r9, r0, #0xff
	movs r1, #0x0
	mov r0, r4
	bl fn_0802499c
	mov r11, r0
	mov r0, r4
	movs r2, #0x33
	mov r1, r6
	bl fn_08024bac
	uxtb r6, r0
	mov r0, r4
	bl fn_08024070
	str r0, [sp, #0x8c]
	mov r0, r4
	bl fn_08024208
	ldrh.w r1, [r4, #0x7e]
	cbz r1, .L08016478
	ldrh r1, [r4, #0x16]
	add r1, r5
	subs r0, r1, r0
	sxth r0, r0
	str r0, [sp, #0x78]
	ldrh r0, [r4, #0x14]
	strh.w r0, [sp, #0x4c]
	ldrh r0, [r4, #0x18]
	strh.w r0, [sp, #0x5c]
	movs r5, #0x0
	ldrsh.w r7, [r4, #0x7e]
	cmp.w r9, #0x2
	bls.n .L080164a0
	cmp.w r11, #0x0
	ble.n .L080164a0
	lsls r0, r6, #0x1e
	bpl.n .L08016438
	movs r1, #0x0
	mov r0, r4
	bl fn_08024b88
	cbnz r0, .L08016438
	b.n .L08016436
.L08016434:
	b.n .L08016576
.L08016436:
	movs r5, #0x1
.L08016438:
	lsls r0, r6, #0x1f
	beq.n .L080164a0
	movs r1, #0x0
	mov r0, r4
	bl fn_08024a98
	cbnz r0, .L080164a0
	.inst.n 0x1e7f  @ subs r7, r7, #1
	sxth r7, r7
	b.n .L080164a0
.L0801644c:
	ldr r0, [sp, #0x74]
	smulbb r1, r0, r5
	ldrh.w r0, [r4, #0x7e]
	mov r2, sp
	.inst.n 0x1e40  @ subs r0, r0, #1
	sdiv r0, r1, r0
	ldr r1, [sp, #0x78]
	add r0, r1
	strh.w r0, [sp, #0x4e]
	strh.w r0, [sp, #0x5e]
	movs r0, #0x1
	strd r10, r0, [sp, #0x4]
	add r0, sp, #0x4c
	str r0, [sp, #0x24]
	add r0, sp, #0x5c
	b.n .L0801647a
.L08016478:
	b.n .L080164a4
.L0801647a:
	str r0, [sp, #0x28]
	movs r1, #0x1a
	str r5, [sp, #0x38]
	mov r0, r4
	bl fn_080207f4
	add r3, sp, #0x5c
	add r2, sp, #0x4c
	add r1, sp, #0x60
	mov r0, r8
	bl fn_0801e8b8
	mov r2, sp
	movs r1, #0x1b
	mov r0, r4
	bl fn_080207f4
	.inst.n 0x1c6d  @ adds r5, r5, #1
	sxth r5, r5
.L080164a0:
	cmp r5, r7
	blt.n .L0801644c
.L080164a4:
	ldrh.w r0, [r4, #0x80]
	cbz r0, .L08016528
	ldrh r1, [r4, #0x14]
	ldr r0, [sp, #0x80]
	movs r7, #0x0
	add r1, r0
	ldr r0, [sp, #0x8c]
	subs r0, r1, r0
	sxth r0, r0
	str r0, [sp, #0x70]
	ldrh r0, [r4, #0x16]
	strh.w r0, [sp, #0x4e]
	ldrh r0, [r4, #0x1a]
	strh.w r0, [sp, #0x5e]
	ldrsh.w r5, [r4, #0x80]
	cmp.w r9, #0x2
	bls.n .L080164f8
	cmp.w r11, #0x0
	ble.n .L080164f8
	lsls r0, r6, #0x1d
	bpl.n .L080164e6
	movs r1, #0x0
	mov r0, r4
	bl fn_08024af8
	cbnz r0, .L080164e6
	movs r7, #0x1
.L080164e6:
	lsls r0, r6, #0x1c
	bpl.n .L080164f8
	movs r1, #0x0
	mov r0, r4
	bl fn_08024b34
	cbnz r0, .L080164f8
	.inst.n 0x1e6d  @ subs r5, r5, #1
	sxth r5, r5
.L080164f8:
	mov r6, r10
	add.w r11, sp, #0x4c
	add.w r9, sp, #0x5c
	mov.w r10, #0x2
	b.n .L08016556
.L08016508:
	ldr r0, [sp, #0x6c]
	smulbb r1, r0, r7
	ldrh.w r0, [r4, #0x80]
	mov r2, sp
	.inst.n 0x1e40  @ subs r0, r0, #1
	sdiv r0, r1, r0
	ldr r1, [sp, #0x70]
	add r0, r1
	strh.w r0, [sp, #0x4c]
	strh.w r0, [sp, #0x5c]
	b.n .L0801652a
.L08016528:
	b.n .L0801655a
.L0801652a:
	str r7, [sp, #0x38]
	strd r6, r10, [sp, #0x4]
	strd r11, r9, [sp, #0x24]
	movs r1, #0x1a
	mov r0, r4
	bl fn_080207f4
	add r3, sp, #0x5c
	add r2, sp, #0x4c
	add r1, sp, #0x60
	mov r0, r8
	bl fn_0801e8b8
	mov r2, sp
	movs r1, #0x1b
	mov r0, r4
	bl fn_080207f4
	.inst.n 0x1c7f  @ adds r7, r7, #1
	sxth r7, r7
.L08016556:
	cmp r7, r5
	blt.n .L08016508
.L0801655a:
	mov.w r0, #0xffffffff
	str r0, [sp, #0x38]
	movs r0, #0x0
	str r0, [sp, #0x24]
	str r0, [sp, #0x28]
	mov r2, sp
	movs r1, #0x1b
	mov r0, r4
	bl fn_080207f4
	ldr r0, [sp, #0x7c]
	str.w r0, [r8, #0x8]
.L08016576:
	add sp, #0x9c
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801657c:
	.word d_08050f14

@ ----------------------------------------------------------------------------
@ fn_08016580 - draws the frame / background of an object (event object E).
@ Parameter: r0 = object E (kept in r11); no return value.
@ t = get_byte8_low7(E) (r6), O = get_first_word(E) (r4). t = 18 goes to case A,
@ t = 21 or 24 to case B, any other t returns at once. Stack frame 0x74; the
@ literal 0x080169a8 holds 0x0804fd20; copy_rect_0801cfb2(dst, src) copies four
@ halfwords from src to dst.
@ Case B (t = 21 or 24): [sp+12] = rect_width_plus_one(O), [sp+16] =
@ rect_height_plus_one(O); p = fn_08024bac(O, 0, 0x32) (r5); r8 = sxth(
@ fn_08024bac(O, 0, 0x12) + p), r10 = sxth(fn_08024bac(O, 0, 0x13) + p), r7 =
@ sxth(fn_08024bac(O, 0, 0x10) + p), r9 = sxth(fn_08024bac(O, 0, 0x11) + p);
@ halfword [sp+0x64] = halfword [O+0x32] + r8, [sp+0x66] = halfword [O+0x34]
@ + r7. When byte [O+0x39] & 3 = 1: fn_08023eb0(O, sp+0x14) (0x08016816);
@ else fn_080122e0(sp+0x14, [sp+12], [sp+16], ldrsh [O+0x30], stack: halfword
@ [O+0x36], sp+0x64) and then halfwords [sp+0x14] and [sp+0x18] += halfword
@ [O+0x14], [sp+0x16] and [sp+0x1a] += halfword [O+0x16].
@ Copies O+0x14 to sp+0x68, copies sp+0x14 to O+0x14, calls fn_08023d54(
@ 0x0804fd20, E) and returns unless it returned 1; then copies sp+0x68 back to
@ O+0x14; returns unless t = 21, halfword [O+0x2e] != 0, halfword [O+0x2c] != 0
@ and halfword [O+0x36] != 0.
@ r6 = get_word_10_if_byte_8_14_to_19(E); copies O+0x14 to sp+12; r5 =
@ fn_08021bd0(O). The four halfwords at sp+12 are then adjusted (sxth r5 = low
@ half, r5 asr 16 = high half of r5; byte [O+0x39] & 3 = 1 uses the centring
@ form 0x08016820 with halfwords [O+0x2c], [O+0x2e], otherwise 0x080166ca uses
@ the differences of the rectangle at sp+0x14): x0 += r8, y0 += r7, x1 -= r10,
@ y1 -= r9.
@ m = byte [O+0x38] & 3: m = 0 or 1 (0x08016876): calls fn_0801e240(sp+0x44)
@ and fn_08024f78(O, 0, sp+0x44), fills a record at sp+0x44 (halfwords [O+0x30],
@ [O+0x36], [O+0x32], [O+0x34]; byte [sp+0x58] = bit 7 of byte [O+0x38];
@ rectangle at sp+0x5c = rectangle at sp+0x14 moved by r8, r7, r10, r9), calls
@ rect_intersect(sp+0x5c, word [r6+8], sp+0x5c) and returns on 0; otherwise
@ stores sp+0x5c in word [r6+8] and loops (row start y = sxth(halfword [O+0x2a]
@ + signed halfword [sp+14]) and column start x = sxth(halfword [O+0x28] +
@ signed halfword [sp+12]); y is reduced by halfword [O+0x2e] when it is
@ greater than y0 and x by halfword [O+0x2c] when it is greater than x0) over
@ rows and columns of the rectangle at sp+12..sp+18, calling fn_0801e1f0(r6,
@ sp+0x44, sp, word [O+0x24]) per cell and advancing the cell rectangle by the
@ low half of r5 horizontally and by its high half (asr 16) vertically; at the
@ end restores word [r6+8].
@ m = 2 (0x08016986): fn_0801e7b4(sp+0x28), fn_0802501a(O, 0, sp+0x28), then
@ fn_0801e274(r6, sp+0x28, O+0x14, word [O+0x24], stack 0).
@ m = 3: fn_0801e1f0(r6, 0, O+0x14, 0).
@ All of these return through the epilogue 0x08016746.
@ Case A (t = 18, 0x0801674c): R = get_word_at_0x10(E); returns when byte [R] =
@ 2; b = byte [O+0x38]; stores 1 in byte [R] when (b & 3) = 3 or 2, or when
@ bits 6..2 of b are neither 4 nor 1, or when fn_08024bac(O, 0, 0x46) & 0xff !=
@ 0xff, or halfword [O+0x30] != 0; otherwise q = get_word_at_0x10(E) and the
@ rectangle at O+0x14 (halfword [O+0x36] = 0x100) or the rectangle built by
@ fn_080122e0(sp+12, rect_width_plus_one(O), rect_height_plus_one(O), 0, stack:
@ halfword [O+0x36], O+0x32) plus halfwords [O+0x14], [O+0x16] is tested with
@ fn_08011e9c(q, rectangle, 0); returns when that is nonzero, else stores 1 in
@ byte [R].
@ ----------------------------------------------------------------------------
	.section .text.fn_08016580,"ax",%progbits
	.p2align 2
	.global fn_08016580
	.thumb_func
	.type fn_08016580, %function
fn_08016580:
	push.w {r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0x74
	mov r11, r0
	bl get_byte8_low7
	mov r6, r0
	mov r0, r11
	bl get_first_word
	mov r4, r0
	cmp r6, #0x12
	beq.n .L08016698
	cmp r6, #0x15
	beq.n .L080165a2
	cmp r6, #0x18
	bne.n .L0801669a
.L080165a2:
	bl rect_width_plus_one
	str r0, [sp, #0xc]
	mov r0, r4
	bl rect_height_plus_one
	str r0, [sp, #0x10]
	mov r0, r4
	movs r1, #0x0
	movs r2, #0x32
	bl fn_08024bac
	mov r5, r0
	mov r0, r4
	movs r1, #0x0
	movs r2, #0x12
	bl fn_08024bac
	add r0, r5
	sxth.w r8, r0
	mov r0, r4
	movs r1, #0x0
	movs r2, #0x13
	bl fn_08024bac
	add r0, r5
	sxth.w r10, r0
	mov r0, r4
	movs r1, #0x0
	movs r2, #0x10
	bl fn_08024bac
	add r0, r5
	sxth r7, r0
	mov r0, r4
	movs r1, #0x0
	movs r2, #0x11
	bl fn_08024bac
	add r0, r5
	ldrh r1, [r4, #0x32]
	sxth.w r9, r0
	add.w r0, r1, r8
	strh.w r0, [sp, #0x64]
	ldrh r0, [r4, #0x34]
	add r0, r7
	strh.w r0, [sp, #0x66]
	ldrb.w r0, [r4, #0x39]
	and.w r0, r0, #0x3
	cmp r0, #0x1
	beq.n .L08016714
	add r1, sp, #0x64
	ldrh r0, [r4, #0x36]
	strd r0, r1, [sp]
	ldrd r1, r2, [sp, #0xc]
	ldrsh.w r3, [r4, #0x30]
	add r0, sp, #0x14
	bl fn_080122e0
	ldrh.w r1, [sp, #0x14]
	ldrh r0, [r4, #0x14]
	add r0, r1
	strh.w r0, [sp, #0x14]
	ldrh.w r1, [sp, #0x16]
	ldrh r0, [r4, #0x16]
	add r0, r1
	strh.w r0, [sp, #0x16]
	ldrh.w r1, [sp, #0x18]
	ldrh r0, [r4, #0x14]
	add r0, r1
	strh.w r0, [sp, #0x18]
	ldrh.w r1, [sp, #0x1a]
	ldrh r0, [r4, #0x16]
	add r0, r1
	strh.w r0, [sp, #0x1a]
	nop
.L08016660:
	add.w r1, r4, #0x14
	mov r5, r1
	add r0, sp, #0x68
	str r1, [sp, #0x48]
	bl copy_rect_0801cfb2
	add r1, sp, #0x14
	mov r0, r5
	bl copy_rect_0801cfb2
	mov r1, r11
	ldr r0, .L080169a8
	bl fn_08023d54
	cmp r0, #0x1
	bne.n .L08016746
	add r1, sp, #0x68
	ldr r0, [sp, #0x48]
	bl copy_rect_0801cfb2
	cmp r6, #0x15
	bne.n .L08016746
	ldrh r0, [r4, #0x2e]
	cmp r0, #0x0
	beq.n .L08016746
	ldrh r0, [r4, #0x2c]
	b.n .L0801669c
.L08016698:
	b.n .L0801674c
.L0801669a:
	b.n .L08016746
.L0801669c:
	cmp r0, #0x0
	beq.n .L08016746
	ldrh r0, [r4, #0x36]
	cmp r0, #0x0
	beq.n .L08016746
	mov r0, r11
	bl get_word_10_if_byte_8_14_to_19
	mov r6, r0
	add r0, sp, #0xc
	ldr r1, [sp, #0x48]
	bl copy_rect_0801cfb2
	mov r0, r4
	bl fn_08021bd0
	mov r5, r0
	ldrb.w r0, [r4, #0x39]
	and.w r0, r0, #0x3
	cmp r0, #0x1
	beq.n .L080167c6
	ldrh.w r0, [sp, #0x18]
	ldrh.w r1, [sp, #0x14]
	subs r0, r0, r1
	ldrh.w r1, [sp, #0xc]
	add r0, r1
	strh.w r0, [sp, #0x10]
	ldrh.w r0, [sp, #0x1a]
	ldrh.w r1, [sp, #0x16]
	subs r0, r0, r1
	ldrh.w r1, [sp, #0xe]
	add.w r0, r0, r1
.L080166f0:
	ldrh.w r1, [sp, #0xc]
	strh.w r0, [sp, #0x12]
	add.w r0, r1, r8
	strh.w r0, [sp, #0xc]
	ldrh.w r0, [sp, #0xe]
	ldrh.w r1, [sp, #0x10]
	add r0, r7
	strh.w r0, [sp, #0xe]
	sub.w r0, r1, r10
	b.n .L08016716
.L08016714:
	b.n .L08016816
.L08016716:
	strh.w r0, [sp, #0x10]
	ldrh.w r1, [sp, #0x12]
	sub.w r0, r1, r9
	strh.w r0, [sp, #0x12]
	ldrb.w r1, [r4, #0x38]
	and.w r0, r1, #0x3
	cmp r0, #0x1
	beq.n .L08016812
	lsls r1, r1, #0x1e
	beq.n .L08016812
	cmp r0, #0x2
	beq.n .L08016814
	movs r3, #0x0
	mov r1, r3
	mov r0, r6
	ldr r2, [sp, #0x48]
	bl fn_0801e1f0
.L08016746:
	add sp, #0x74
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0801674c:
	mov r0, r11
	bl get_word_at_0x10
	mov r5, r0
	ldrb r0, [r0, #0x0]
	cmp r0, #0x2
	beq.n .L08016746
	ldrb.w r0, [r4, #0x38]
	mov.w r6, #0x1
	mvns r1, r0
	lsls r1, r1, #0x1e
	beq.n .L08016806
	and.w r1, r0, #0x3
	cmp r1, #0x2
	beq.n .L08016806
	ubfx r0, r0, #0x2, #0x5
	cmp r0, #0x4
	beq.n .L0801677c
	cmp r0, #0x1
	bne.n .L08016806
.L0801677c:
	mov r0, r4
	movs r1, #0x0
	movs r2, #0x46
	bl fn_08024bac
	uxtb r0, r0
	cmp r0, #0xff
	bne.n .L08016806
	ldrh r0, [r4, #0x30]
	cbnz r0, .L08016806
	mov r0, r11
	bl get_word_at_0x10
	mov r7, r0
	ldrh r0, [r4, #0x36]
	cmp.w r0, #0x100
	beq.n .L0801680a
	mov r0, r4
	bl rect_height_plus_one
	mov r8, r0
	mov r0, r4
	bl rect_width_plus_one
	mov r1, r0
	add.w r2, r4, #0x32
	ldrh r0, [r4, #0x36]
	strd r0, r2, [sp]
	movs r3, #0x0
	mov r2, r8
	add r0, sp, #0xc
	bl fn_080122e0
	b.n .L080167c8
.L080167c6:
	b.n .L08016820
.L080167c8:
	ldrh.w r0, [sp, #0xc]
	ldrh r1, [r4, #0x14]
	movs r2, #0x0
	add r0, r1
	strh.w r0, [sp, #0xc]
	ldrh.w r0, [sp, #0xe]
	ldrh r1, [r4, #0x16]
	add r0, r1
	strh.w r0, [sp, #0xe]
	ldrh.w r0, [sp, #0x10]
	ldrh r1, [r4, #0x14]
	add r0, r1
	strh.w r0, [sp, #0x10]
	ldrh.w r0, [sp, #0x12]
	ldrh r1, [r4, #0x16]
	add r0, r1
	strh.w r0, [sp, #0x12]
	add r1, sp, #0xc
.L080167fc:
	mov r0, r7
	bl fn_08011e9c
	cmp r0, #0x0
	bne.n .L08016746
.L08016806:
	strb r6, [r5, #0x0]
.L08016808:
	b.n .L08016746
.L0801680a:
	movs r2, #0x0
	add.w r1, r4, #0x14
	b.n .L080167fc
.L08016812:
	b.n .L08016876
.L08016814:
	b.n .L08016986
.L08016816:
	add r1, sp, #0x14
	mov r0, r4
	bl fn_08023eb0
	b.n .L08016660
.L08016820:
	ldrsh.w r0, [r4, #0x2c]
	sxth r1, r5
	subs r0, r0, r1
	ldrh.w r1, [sp, #0xc]
	.inst.n 0x1c40  @ adds r0, r0, #1
	add.w r0, r0, r0, lsr #31
	sub.w r1, r1, r0, asr #1
	strh.w r1, [sp, #0xc]
	ldrh.w r1, [sp, #0x10]
	ldrh.w r2, [sp, #0xe]
	sub.w r0, r1, r0, asr #1
	strh.w r0, [sp, #0x10]
	ldrsh.w r0, [r4, #0x2e]
	asrs r1, r5, #0x10
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	add.w r0, r0, r0, lsr #31
	sub.w r0, r2, r0, asr #1
	strh.w r0, [sp, #0xe]
	ldrsh.w r0, [r4, #0x2e]
	subs r0, r0, r1
	ldrh.w r1, [sp, #0x12]
	.inst.n 0x1c40  @ adds r0, r0, #1
	add.w r0, r0, r0, lsr #31
	sub.w r0, r1, r0, asr #1
	b.n .L080166f0
.L08016876:
	add r0, sp, #0x44
	bl fn_0801e240
	add r2, sp, #0x44
	movs r1, #0x0
	mov r0, r4
	bl fn_08024f78
	ldrh r0, [r4, #0x36]
	strh.w r0, [sp, #0x46]
	ldrh r0, [r4, #0x30]
	strh.w r0, [sp, #0x44]
	ldrh r0, [r4, #0x32]
	strh.w r0, [sp, #0x48]
	ldrh r0, [r4, #0x34]
	strh.w r0, [sp, #0x4a]
	ldrb.w r0, [r4, #0x38]
	ldrh.w r1, [sp, #0x14]
	lsrs r0, r0, #0x7
	strb.w r0, [sp, #0x58]
	add.w r0, r1, r8
	strh.w r0, [sp, #0x5c]
	ldrh.w r0, [sp, #0x16]
	ldrh.w r1, [sp, #0x18]
	add r0, r7
	strh.w r0, [sp, #0x5e]
	sub.w r0, r1, r10
	ldrh.w r1, [sp, #0x1a]
	strh.w r0, [sp, #0x60]
	sub.w r0, r1, r9
	strh.w r0, [sp, #0x62]
	ldr r1, [r6, #0x8]
	add r2, sp, #0x5c
	mov r7, r1
	mov r0, r2
	bl rect_intersect
	cmp r0, #0x0
	beq.n .L08016808
	add r0, sp, #0x5c
	str r0, [r6, #0x8]
	ldrsh.w r1, [sp, #0xe]
	ldrh r0, [r4, #0x2a]
	add r0, r1
	sxth r0, r0
	strh.w r0, [sp, #0x2]
	cmp r0, r1
	ble.n .L08016904
	ldrh r1, [r4, #0x2e]
	subs r0, r0, r1
	strh.w r0, [sp, #0x2]
.L08016904:
	ldrh r1, [r4, #0x2e]
	uxth r0, r0
	add r0, r1
	.inst.n 0x1e40  @ subs r0, r0, #1
	b.n .L08016972
	nop  @ padding
.L08016910:
	ldrsh.w r1, [sp, #0xc]
	ldrh r0, [r4, #0x28]
	add r0, r1
	sxth r0, r0
	strh.w r0, [sp, #0x0]
	cmp r0, r1
	ble.n .L0801692a
	ldrh r1, [r4, #0x2c]
	subs r0, r0, r1
	strh.w r0, [sp, #0x0]
.L0801692a:
	ldrh r1, [r4, #0x2c]
	uxth r0, r0
	add r0, r1
	.inst.n 0x1e40  @ subs r0, r0, #1
	b.n .L08016950
.L08016934:
	mov r2, sp
	add r1, sp, #0x44
	mov r0, r6
	ldr r3, [r4, #0x24]
	bl fn_0801e1f0
	ldrh.w r0, [sp, #0x0]
	add r0, r5
	strh.w r0, [sp, #0x0]
	ldrh.w r0, [sp, #0x4]
	add r0, r5
.L08016950:
	strh.w r0, [sp, #0x4]
	ldrsh.w r1, [sp, #0x0]
	ldrsh.w r0, [sp, #0x10]
	cmp r1, r0
	blt.n .L08016934
	ldrh.w r1, [sp, #0x2]
	asrs r0, r5, #0x10
	add r1, r0
	strh.w r1, [sp, #0x2]
	ldrh.w r1, [sp, #0x6]
	add r0, r1
.L08016972:
	strh.w r0, [sp, #0x6]
	ldrsh.w r1, [sp, #0x2]
	ldrsh.w r0, [sp, #0x12]
	cmp r1, r0
	blt.n .L08016910
	str r7, [r6, #0x8]
	b.n .L08016746
.L08016986:
	add r0, sp, #0x28
	bl fn_0801e7b4
	add r2, sp, #0x28
	movs r1, #0x0
	mov r0, r4
	bl fn_0802501a
	movs r0, #0x0
	str r0, [sp, #0x0]
	ldr r3, [r4, #0x24]
	add r1, sp, #0x28
	mov r0, r6
	ldr r2, [sp, #0x48]
	bl fn_0801e274
	b.n .L08016746
.L080169a8:
	.word d_0804fd20

@ ----------------------------------------------------------------------------
@ fn_080169ac - draws a packed bitmap through a palette in blocks.
@ Parameters: r0 = context (clip rectangle pointer at +8), r1 = style record
@ (byte +0x1a alpha, halfword +0xc colour, byte +0x1e), r2 = position (two
@ halfwords x, y), r3 = bitmap header (low nibble of byte +0xe = bits per
@ pixel, halfwords +6 and +8 = width and height), stack argument at [sp+0xb0]
@ after the prologue = pixel bits. No return value.
@ Bits per pixel 1, 2, 3 (treated as 4), 4 or 8 select the pixel mask (0x80,
@ 0xc0, 0xf0, 0xff), the table (0x08050dd4, 0x08050dd6, 0x08050dda, 0x08050dea;
@ the table pointer is the literal 0x08016c60 minus 0x16, 0x14, 0x10 or 0)
@ and the entry count (2, 4, 16, 256); any other value returns.
@ Alpha below 0xfd: rebuilds the palette at RAM 0x20014298 when the cache pair
@ 0x2000053c (alpha) / 0x20000540 (bits per pixel) differs, each entry = table
@ byte * alpha >> 8 (alpha itself for an 0xff table byte), and uses it instead
@ of the table; then stores alpha and bits per pixel in the cache pair.
@ Clips the bitmap to the clip rectangle at *(context+8), clears a 0x1c byte
@ record with clear_bytes, fills it from the style record, calls
@ return_word_200004b8 and fn_0801dcfc, allocates a buffer with fn_08022bac
@ sized from fn_0801dcfc (limited to width * height), unpacks each row bit
@ group to one palette byte (0 stays 0), masks rows with fn_0801ec54 when
@ fn_0801ecd0 is nonzero (clearing the row with clear_bytes when that returns
@ 0), and sends blocks with fn_0801f730 with kind byte 2. Frees the buffer
@ with fn_08022c44.
@ ----------------------------------------------------------------------------
	.section .text.fn_080169ac,"ax",%progbits
	.p2align 2
	.global fn_080169ac
	.thumb_func
	.type fn_080169ac, %function
fn_080169ac:
	push.w {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0x7c
	ldrb r0, [r3, #0xe]
	ldrb r2, [r1, #0x1a]
	and.w r4, r0, #0xf
	ldr.w lr, [sp, #0xb0]
	mov r6, r1
	cmp r4, #0x3
	beq.n .L080169f6
	cmp r4, #0x1
	beq.n .L08016a04
	cmp r4, #0x2
	beq.n .L08016a10
	cmp r4, #0x4
	beq.n .L080169f8
	cmp r4, #0x8
	bne.n .L08016ad0
	ldr r5, .L08016c60
	mov.w r10, #0xff
	lsls r1, r4, #0x5
.L080169dc:
	cmp r2, #0xfd
	bhs.n .L08016a40
	ldr r7, .L08016c64
	ldrb r0, [r7, #0x0]
	cmp r0, r2
	bne.n .L080169ee
	ldr r0, [r7, #0x4]
	cmp r0, r4
	beq.n .L08016a3a
.L080169ee:
	movs r0, #0x0
	ldr.w r8, .L08016c68
	b.n .L08016a36
.L080169f6:
	movs r4, #0x4
.L080169f8:
	ldr r5, .L08016c60
	mov.w r10, #0xf0
	subs r5, #0x10
	movs r1, #0x10
	b.n .L080169dc
.L08016a04:
	ldr r5, .L08016c60
	mov.w r10, #0x80
	subs r5, #0x16
	movs r1, #0x2
	b.n .L080169dc
.L08016a10:
	ldr r5, .L08016c60
	mov.w r10, #0xc0
	subs r5, #0x14
	movs r1, #0x4
	b.n .L080169dc
.L08016a1c:
	ldrb.w r12, [r5, r0]
	cmp.w r12, #0xff
	beq.n .L08016a62
	smulbb r12, r12, r2
	lsr.w r12, r12, #0x8
	nop
.L08016a30:
	strb.w r12, [r8, r0]
	.inst.n 0x1c40  @ adds r0, r0, #1
.L08016a36:
	cmp r0, r1
	blo.n .L08016a1c
.L08016a3a:
	ldr r5, .L08016c68
	strb r2, [r7, #0x0]
	str r4, [r7, #0x4]
.L08016a40:
	ldr r2, [sp, #0x7c]
	ldrh.w r8, [r3, #0x6]
	ldrh r0, [r3, #0x8]
	str r0, [sp, #0x1c]
	ldr r1, [sp, #0x84]
	ldr r2, [r2, #0x8]
	mul r0, r8, r4
	ldrsh.w r1, [r1, #0x0]
	ldrsh.w r3, [r2, #0x0]
	cmp r1, r3
	blt.n .L08016a66
	movs r3, #0x0
	b.n .L08016a68
.L08016a62:
	mov r12, r2
	b.n .L08016a30
.L08016a66:
	subs r3, r3, r1
.L08016a68:
	mov r11, r3
	ldrsh.w r3, [r2, #0x4]
	add.w r7, r1, r8
	cmp r7, r3
	bgt.n .L08016a7a
	mov r1, r8
	b.n .L08016a7e
.L08016a7a:
	subs r1, r3, r1
	.inst.n 0x1c49  @ adds r1, r1, #1
.L08016a7e:
	mov r9, r1
	ldr r1, [sp, #0x84]
	ldrsh.w r3, [r2, #0x2]
	ldrsh.w r1, [r1, #0x2]
	cmp r1, r3
	blt.n .L08016a92
	movs r3, #0x0
	b.n .L08016a94
.L08016a92:
	subs r3, r3, r1
.L08016a94:
	str r3, [sp, #0x44]
	ldr r3, [sp, #0x1c]
	ldrsh.w r2, [r2, #0x6]
	add r3, r1
	cmp r3, r2
	bgt.n .L08016aa6
	ldr r1, [sp, #0x1c]
	b.n .L08016aaa
.L08016aa6:
	subs r1, r2, r1
	.inst.n 0x1c49  @ adds r1, r1, #1
.L08016aaa:
	str r1, [sp, #0x28]
	ldr r1, [sp, #0x44]
	muls r1, r0, r1
	mla r0, r11, r4, r1
	add.w r1, lr, r0, lsr #0x3
	and.w r7, r0, #0x7
	str r1, [sp, #0xb0]
	movs r1, #0x1c
	add r0, sp, #0x54
	bl clear_bytes
	ldrh r0, [r6, #0xc]
	strh.w r0, [sp, #0x5c]
	ldrb r0, [r6, #0x1a]
	b.n .L08016ad2
.L08016ad0:
	b.n .L08016c58
.L08016ad2:
	strb.w r0, [sp, #0x6c]
	ldrb r0, [r6, #0x1e]
	ubfx r0, r0, #0x3, #0x3
	strb.w r0, [sp, #0x6d]
	bl return_word_200004b8
	bl fn_0801dcfc
	ldr r2, [sp, #0x1c]
	mul r1, r8, r2
	cmp r1, r0
	bgt.n .L08016af4
	mov r0, r1
.L08016af4:
	str r0, [sp, #0x70]
	bl fn_08022bac
	str r0, [sp, #0x1c]
	str r0, [sp, #0x60]
	ldr r0, [sp, #0x84]
	movs r6, #0x0
	ldrh r1, [r0, #0x0]
	add.w r2, r1, r11
	strh.w r2, [sp, #0xc]
	ldrh r1, [r0, #0x0]
	sub.w r0, r9, #0x1
	add r1, r0
	ldr r0, [sp, #0x84]
	strh.w r1, [sp, #0x10]
	ldrh r3, [r0, #0x2]
	ldr r0, [sp, #0x44]
	add r0, r3
	subs r3, r1, r2
	strh.w r0, [sp, #0x12]
	strh.w r0, [sp, #0xe]
	strh.w r1, [sp, #0x38]
	strh.w r2, [sp, #0x34]
	ldr r1, [sp, #0x28]
	strh.w r0, [sp, #0x36]
	.inst.n 0x1c5b  @ adds r3, r3, #1
	add r0, r1
	sxth r3, r3
	strh.w r0, [sp, #0x3a]
	str r3, [sp, #0x2c]
	add r0, sp, #0x34
	bl fn_0801ecd0
	str r0, [sp, #0x74]
	add r0, sp, #0xc
	str r0, [sp, #0x54]
	str r0, [sp, #0x68]
	rsb.w r0, r4, #0x8
	add.w r1, r8, r11
	str r0, [sp, #0x3c]
	sub.w r0, r1, r9
	muls r0, r4, r0
	str r0, [sp, #0x48]
	ldr r0, [sp, #0x44]
	b.n .L08016c2a
.L08016b68:
	mov r3, r6
	lsr.w r0, r10, r7
	mov r1, r11
	mov.w r12, #0x0
	b.n .L08016bb6
.L08016b76:
	ldr r2, [sp, #0xb0]
	ldr.w r8, [sp, #0x3c]
	ldrb r2, [r2, #0x0]
	sub.w r8, r8, r7
	ands r2, r0
	lsrs.w r2, r2, r8
	beq.n .L08016b96
	ldrb.w r8, [r5, r2]
	ldr r2, [sp, #0x1c]
	strb.w r8, [r2, r6]
	b.n .L08016b9c
.L08016b96:
	ldr r2, [sp, #0x1c]
	strb.w r12, [r2, r6]
.L08016b9c:
	ldr r2, [sp, #0x3c]
	cmp r7, r2
	bhs.n .L08016ba8
	add r7, r4
	lsrs r0, r4
	b.n .L08016bb2
.L08016ba8:
	ldr r2, [sp, #0xb0]
	movs r7, #0x0
	.inst.n 0x1c52  @ adds r2, r2, #1
	mov r0, r10
	str r2, [sp, #0xb0]
.L08016bb2:
	.inst.n 0x1c49  @ adds r1, r1, #1
	.inst.n 0x1c76  @ adds r6, r6, #1
.L08016bb6:
	cmp r1, r9
	blt.n .L08016b76
	ldr r0, [sp, #0x74]
	cbz r0, .L08016be0
	ldr r0, [sp, #0x1c]
	ldrsh.w r2, [sp, #0x12]
	add r0, r3
	ldrsh.w r1, [sp, #0xc]
	mov r8, r0
	ldr r3, [sp, #0x2c]
	bl fn_0801ec54
	strb.w r0, [sp, #0x64]
	cbnz r0, .L08016be0
	mov r0, r8
	ldr r1, [sp, #0x2c]
	bl clear_bytes
.L08016be0:
	sub.w r0, r9, r11
	adds r1, r0, r6
	ldr r0, [sp, #0x70]
	cmp r1, r0
	bhs.n .L08016bf8
	ldrh.w r0, [sp, #0x12]
	.inst.n 0x1c40  @ adds r0, r0, #1
	strh.w r0, [sp, #0x12]
	b.n .L08016c16
.L08016bf8:
	movs r0, #0x2
	strb.w r0, [sp, #0x64]
	add r1, sp, #0x54
	ldr r0, [sp, #0x7c]
	bl fn_0801f730
	ldrh.w r0, [sp, #0x12]
	.inst.n 0x1c40  @ adds r0, r0, #1
	strh.w r0, [sp, #0xe]
	strh.w r0, [sp, #0x12]
	movs r6, #0x0
.L08016c16:
	ldr r0, [sp, #0x48]
	ldr r1, [sp, #0xb0]
	add r0, r7
	add.w r1, r1, r0, lsr #0x3
	and.w r7, r0, #0x7
	ldr r0, [sp, #0x4]
	str r1, [sp, #0xb0]
	.inst.n 0x1c40  @ adds r0, r0, #1
.L08016c2a:
	ldr r1, [sp, #0x28]
	str r0, [sp, #0x4]
	cmp r0, r1
	blt.n .L08016b68
	ldrsh.w r1, [sp, #0xe]
	ldrsh.w r0, [sp, #0x12]
	cmp r1, r0
	beq.n .L08016c52
	.inst.n 0x1e40  @ subs r0, r0, #1
	strh.w r0, [sp, #0x12]
	movs r0, #0x2
	strb.w r0, [sp, #0x64]
	add r1, sp, #0x54
	ldr r0, [sp, #0x7c]
	bl fn_0801f730
.L08016c52:
	ldr r0, [sp, #0x1c]
	bl fn_08022c44
.L08016c58:
	add sp, #0x8c
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short 0x0000  @ padding
.L08016c60:
	.word d_08050dea
.L08016c64:
	.word 0x2000053c
.L08016c68:
	.word 0x20014298

@ ----------------------------------------------------------------------------
@ fn_08016c6c - draws a horizontal line with a pen, solid or dashed.
@ Parameters: r0 = context (clip rectangle pointer at +8), r1 = pen record
@ (halfword 0 colour, halfword 1 thickness, halfwords 2 and 3 dash length and
@ gap, byte at +8), r2 and r3 = two points (x, y halfwords). No return value.
@ Builds the rectangle x from min(x3, x4) to max(x3, x4) - 1 and y from
@ y3 - thickness/2 to y3 + (thickness - 1)/2, intersects it with the clip at
@ *(context+8) via rect_intersect and returns when the result is empty.
@ Solid pen (halfword 2 or 3 zero) with fn_0801ecd0 = 0: one fn_0801f730 call
@ with a 0x1c byte record (cleared with clear_bytes; colour halfword and byte
@ +8 of the pen copied into it).
@ Otherwise allocates a row buffer of the width with fn_08022bac and for each
@ of the thickness rows fills it with 0xff (fill_bytes_ff), calls fn_0801ec54
@ (its result stored in byte [sp+0x18]) and, for a dashed pen, zeroes the gap
@ bytes using the period halfword 2 + halfword 3 starting at x mod period (then
@ stores 2 in byte [sp+0x18]), then calls fn_0801f730 and moves the row one
@ down. Frees the buffer with fn_08022c44.
@ ----------------------------------------------------------------------------
	.section .text.fn_08016c6c,"ax",%progbits
	.p2align 2
	.global fn_08016c6c
	.thumb_func
	.type fn_08016c6c, %function
fn_08016c6c:
	push.w {r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov r11, r0
	ldrsh.w r0, [r1, #0x2]
	mov r4, r1
	.inst.n 0x1e40  @ subs r0, r0, #1
	asrs r1, r0, #0x1
	and.w r0, r0, #0x1
	adds r6, r0, r1
	ldrsh.w r5, [r2, #0x0]
	ldrsh.w r0, [r3, #0x0]
	sub sp, #0x24
	cmp r5, r0
	bge.n .L08016c92
	mov r0, r5
.L08016c92:
	strh.w r0, [sp, #0x0]
	ldrsh.w r0, [r2, #0x0]
	ldrsh.w r3, [r3, #0x0]
	cmp r0, r3
	bgt.n .L08016ca4
	mov r0, r3
.L08016ca4:
	.inst.n 0x1e40  @ subs r0, r0, #1
	strh.w r0, [sp, #0x4]
	ldrh r0, [r2, #0x2]
	subs r0, r0, r6
	strh.w r0, [sp, #0x2]
	ldrh r0, [r2, #0x2]
	add r0, r1
	strh.w r0, [sp, #0x6]
	mov r1, sp
	mov r0, r1
	ldr.w r2, [r11, #0x8]
	bl rect_intersect
	cmp r0, #0x0
	beq.n .L08016d0a
	ldrh r0, [r4, #0x6]
	cbz r0, .L08016cd6
	ldrh r0, [r4, #0x4]
	cbz r0, .L08016cd6
	movs r7, #0x1
	b.n .L08016cd8
.L08016cd6:
	movs r7, #0x0
.L08016cd8:
	movs r5, #0x1
	mov r0, sp
	bl fn_0801ecd0
	cbnz r0, .L08016ce4
	cbz r7, .L08016ce6
.L08016ce4:
	movs r5, #0x0
.L08016ce6:
	movs r1, #0x1c
	add r0, sp, #0x8
	bl clear_bytes
	str.w sp, [sp, #0x8]
	ldrh r0, [r4, #0x0]
	strh.w r0, [sp, #0x10]
	ldrb r0, [r4, #0x8]
	mov r6, sp
	strb.w r0, [sp, #0x20]
	cbz r5, .L08016d10
	add r1, sp, #0x8
	mov r0, r11
	bl fn_0801f730
.L08016d0a:
	add sp, #0x24
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08016d10:
	ldrh.w r1, [sp, #0x4]
	ldrsh.w r0, [sp, #0x0]
	ldrsh.w r8, [sp, #0x6]
	subs r1, r1, r0
	.inst.n 0x1c49  @ adds r1, r1, #1
	sxth r5, r1
	ldrh.w r1, [sp, #0x2]
	strh.w r1, [sp, #0x6]
	mov.w r10, #0x0
	cbz r7, .L08016d42
	ldrsh.w r1, [r4, #0x6]
	ldrsh.w r2, [r4, #0x4]
	add r1, r2
	sdiv r2, r0, r1
	mls r10, r1, r2, r0
.L08016d42:
	mov r0, r5
	bl fn_08022bac
	str r6, [sp, #0x1c]
	str r0, [sp, #0x14]
	mov r9, r0
	ldrsh.w r6, [sp, #0x2]
	b.n .L08016dd2
.L08016d54:
	mov r1, r5
	mov r0, r9
	bl fill_bytes_ff
	ldrsh.w r1, [sp, #0x0]
	mov r3, r5
	sxth r2, r6
	mov r0, r9
	bl fn_0801ec54
	strb.w r0, [sp, #0x18]
	cbz r7, .L08016db4
	cbz r0, .L08016db4
	movs r1, #0x0
	mov r0, r10
	mov r3, r1
	b.n .L08016daa
	nop  @ padding
.L08016d7c:
	ldrsh.w r2, [r4, #0x4]
	cmp r2, r0
	blt.n .L08016d90
	subs r2, r2, r0
	add r1, r2
	add r0, r2
	sxth r1, r1
	sxth r0, r0
	b.n .L08016da2
.L08016d90:
	ldrsh.w r12, [r4, #0x6]
	add r2, r12
	cmp r2, r0
	bgt.n .L08016d9e
	movs r0, #0x0
	b.n .L08016da2
.L08016d9e:
	strb.w r3, [r9, r1]
.L08016da2:
	.inst.n 0x1c49  @ adds r1, r1, #1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r1, r1
	sxth r0, r0
.L08016daa:
	cmp r1, r5
	blt.n .L08016d7c
	movs r0, #0x2
	strb.w r0, [sp, #0x18]
.L08016db4:
	add r1, sp, #0x8
	mov r0, r11
	bl fn_0801f730
	ldrh.w r0, [sp, #0x2]
	.inst.n 0x1c40  @ adds r0, r0, #1
	strh.w r0, [sp, #0x2]
	ldrh.w r0, [sp, #0x6]
	.inst.n 0x1c40  @ adds r0, r0, #1
	strh.w r0, [sp, #0x6]
	.inst.n 0x1c76  @ adds r6, r6, #1
.L08016dd2:
	cmp r6, r8
	ble.n .L08016d54
	mov r0, r9
	bl fn_08022c44
	b.n .L08016d0a
	.short 0x0000  @ padding

@ ----------------------------------------------------------------------------
@ fn_08016de0 - draws a thick line between two points with a pen.
@ Parameters: r0 = context (clip rectangle pointer at +8), r1 = pen record
@ (halfword 0 colour, halfword 1 thickness, byte +8, byte +9 flags), r2 and r3 =
@ end points (x, y halfwords). No return value.
@ Orders the points by y, takes dx and dy and uses the larger of |dx| and |dy|
@ as the major axis (flag [sp+0x54] = 1 when |dy| < |dx|). The offset is
@ (byte table 0x08050eea[(minor << 5) / major] * thickness + 0x3f) >> 7 (the
@ full width); the half widths are that value >> 1 (r8) and that value & 1 plus
@ r8 (r11), minor and major being the smaller and larger of |dx| and |dy|.
@ Builds the bounding rectangle (at sp+0x58) widened by the offset and
@ intersects it with the clip at *(context+8) via rect_intersect; returns when
@ the result is empty.
@ Builds edge records with fn_0801ee18 (two long edges at sp+0x80 and sp+0x28
@ and, when bit 4 of byte +9 is clear, two cap edges at sp+0xac and sp+0xd8)
@ and inserts them with table_slot_insert (slot numbers kept in [sp+0x60],
@ [sp+0x54], r9 and r8; -1 for caps that are not used).
@ Allocates a row buffer with fn_08022bac, sized from fn_0801dcfc and rect_area
@ (the smaller of the two), fills it with 0xff (fill_bytes_ff), and for each
@ row masks it with fn_0801ec54 (clearing the row with clear_bytes when that
@ returns 0) and sends blocks with fn_0801f730 using kind byte 2 (byte
@ [sp+0x74]).
@ Frees the buffer with fn_08022c44, releases the edge records with
@ fn_0801ec98 and the slots with table_slot_clear.
@ ----------------------------------------------------------------------------
	.section .text.fn_08016de0,"ax",%progbits
	.p2align 2
	.global fn_08016de0
	.thumb_func
	.type fn_08016de0, %function
fn_08016de0:
	push.w {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	ldrsh.w r4, [r2, #0x2]
	ldrsh.w r5, [r3, #0x2]
	sub sp, #0x114
	cmp r4, r5
	bge.n .L08016e04
	ldrh r2, [r2, #0x0]
	bfi r0, r4, #0x10, #0x10
	bfi r0, r2, #0x0, #0x10
	bfi r1, r5, #0x10, #0x10
	ldrh r2, [r3, #0x0]
	b.n .L08016e14
.L08016e04:
	ldrh r3, [r3, #0x0]
	bfi r0, r5, #0x10, #0x10
	ldrh r2, [r2, #0x0]
	bfi r1, r4, #0x10, #0x10
	bfi r0, r3, #0x0, #0x10
.L08016e14:
	bfi r1, r2, #0x0, #0x10
	sxth.w r9, r1
	sxth r4, r0
	asrs r5, r0, #0x10
	sub.w r6, r9, r4
	asr.w r10, r1, #0x10
	sub.w r7, r10, r5
	str r1, [sp, #0xc]
	cmp r6, #0x0
	ble.n .L08016e36
	mov r1, r6
	b.n .L08016e38
.L08016e36:
	rsbs r1, r6, #0
.L08016e38:
	cmp r7, #0x0
	ble.n .L08016e40
	mov r0, r7
	b.n .L08016e42
.L08016e40:
	rsbs r0, r7, #0
.L08016e42:
	cmp r1, r0
	ble.n .L08016e4a
	movs r0, #0x1
	b.n .L08016e4c
.L08016e4a:
	movs r0, #0x0
.L08016e4c:
	str r0, [sp, #0x54]
	ldr r0, [sp, #0x118]
	ldrsh.w r1, [r0, #0x2]
	ldr r0, [sp, #0x54]
	cbz r0, .L08016e70
	cmp r7, #0x0
	ble.n .L08016e60
	mov r0, r7
	b.n .L08016e62
.L08016e60:
	rsbs r0, r7, #0
.L08016e62:
	lsls r2, r0, #0x5
	cmp r6, #0x0
	ble.n .L08016e6c
	mov r0, r6
	b.n .L08016e86
.L08016e6c:
	rsbs r0, r6, #0
	b.n .L08016e86
.L08016e70:
	cmp r6, #0x0
	ble.n .L08016e78
	mov r0, r6
	b.n .L08016e7a
.L08016e78:
	rsbs r0, r6, #0
.L08016e7a:
	lsls r2, r0, #0x5
	cmp r7, #0x0
	ble.n .L08016e84
	mov r0, r7
	b.n .L08016e86
.L08016e84:
	rsbs r0, r7, #0
.L08016e86:
	sdiv r0, r2, r0
	ldr r2, .L08017138
	ldrb r0, [r2, r0]
	smulbb r0, r0, r1
	adds r0, #0x3f
	asrs r0, r0, #0x7
	asr.w r8, r0, #1
	and.w r2, r0, #0x1
	add.w r11, r2, r8
	mov r1, r9
	cmp r4, r9
	bge.n .L08016eaa
	mov r1, r4
.L08016eaa:
	sub.w r1, r1, r0
	strh.w r1, [sp, #0x58]
	ble.n .L08016eb8
	mov r1, r4
	b.n .L08016eba
.L08016eb8:
	mov r1, r9
.L08016eba:
	add r1, r0
	strh.w r1, [sp, #0x5c]
	mov r1, r10
	cmp r5, r10
	bge.n .L08016ec8
	mov r1, r5
.L08016ec8:
	sub.w r1, r1, r0
	strh.w r1, [sp, #0x5a]
	ble.n .L08016ed6
	mov r1, r5
	b.n .L08016ed8
.L08016ed6:
	mov r1, r10
.L08016ed8:
	add r0, r1
	strh.w r0, [sp, #0x5e]
	ldr r0, [sp, #0x114]
	add r1, sp, #0x58
	ldr r2, [r0, #0x8]
	mov r0, r1
	bl rect_intersect
	cmp r0, #0x0
	beq.n .L08016fec
	ldr r0, [sp, #0x54]
	movs r1, #0x0
	cmp r0, #0x0
	beq.n .L08016fee
	cmp r6, #0x0
	ble.n .L08016f28
	sub.w r0, r10, r8
	sxth r0, r0
	strd r0, r1, [sp, #0x0]
	sub.w r0, r5, r8
	sxth r2, r0
	mov r3, r9
	mov r1, r4
	add r0, sp, #0x80
	bl fn_0801ee18
	add.w r0, r10, r11
	movs r1, #0x1
	sxth r0, r0
	strd r0, r1, [sp, #0x0]
	mov r3, r9
	add.w r0, r5, r11
	b.n .L08016f54
.L08016f28:
	add.w r0, r10, r11
	sxth r0, r0
	strd r0, r1, [sp, #0x0]
	add.w r0, r5, r11
	sxth r2, r0
	mov r3, r9
	mov r1, r4
	add r0, sp, #0x80
	bl fn_0801ee18
	sub.w r0, r10, r8
	movs r1, #0x1
	sxth r0, r0
	strd r0, r1, [sp, #0x0]
	mov r3, r9
	sub.w r0, r5, r8
.L08016f54:
	sxth r2, r0
	mov r1, r4
.L08016f58:
	add r0, sp, #0x28
	bl fn_0801ee18
	movs r1, #0x0
	add r0, sp, #0x80
	bl table_slot_insert
	str r0, [sp, #0x60]
	movs r1, #0x0
	add r0, sp, #0x28
	bl table_slot_insert
	str r0, [sp, #0x54]
	ldr r0, [sp, #0x118]
	mov.w r9, #0xffffffff
	mov r8, r9
	ldrb r0, [r0, #0x9]
	lsls r0, r0, #0x1b
	bmi.n .L08016fc8
	adds r0, r5, r6
	movs r1, #0x3
	sxth r0, r0
	strd r0, r1, [sp, #0x0]
	subs r0, r4, r7
	sxth r3, r0
	mov r2, r5
	mov r1, r4
	add r0, sp, #0xac
	bl fn_0801ee18
	ldr r1, [sp, #0xc]
	movs r0, #0x2
	asrs r2, r1, #0x10
	adds r1, r2, r6
	sxth r1, r1
	strd r1, r0, [sp, #0x0]
	ldr r0, [sp, #0xc]
	sxth r1, r0
	subs r0, r1, r7
	sxth r3, r0
	add r0, sp, #0xd8
	bl fn_0801ee18
	movs r1, #0x0
	add r0, sp, #0xac
	bl table_slot_insert
	mov r9, r0
	movs r1, #0x0
	add r0, sp, #0xd8
	bl table_slot_insert
	mov r8, r0
.L08016fc8:
	ldrh.w r0, [sp, #0x5c]
	ldrh.w r1, [sp, #0x58]
	subs r0, r0, r1
	.inst.n 0x1c40  @ adds r0, r0, #1
	sxth r4, r0
	bl return_word_200004b8
	bl fn_0801dcfc
	mov r5, r0
	add r0, sp, #0x58
	bl rect_area
	cmp r0, r5
	bhs.n .L08016ff8
	b.n .L08016ff0
.L08016fec:
	b.n .L08017132
.L08016fee:
	b.n .L08017040
.L08016ff0:
	add r0, sp, #0x58
	bl rect_area
	mov r5, r0
.L08016ff8:
	mov r10, r5
	mov r0, r5
	bl fn_08022bac
	mov r11, r0
	ldrsh.w r7, [sp, #0x5e]
	ldrh.w r0, [sp, #0x5a]
	strh.w r0, [sp, #0x5e]
	movs r5, #0x0
	mov r1, r10
	mov r0, r11
	bl fill_bytes_ff
	movs r1, #0x1c
	add r0, sp, #0x64
	bl clear_bytes
	add r1, sp, #0x58
	str r1, [sp, #0x64]
	ldr r0, [sp, #0x118]
	ldrh r0, [r0, #0x0]
	strh.w r0, [sp, #0x6c]
	ldr r0, [sp, #0x118]
	ldrsh.w r6, [sp, #0x5a]
	ldrb r0, [r0, #0x8]
	strb.w r0, [sp, #0x7c]
	str.w r11, [sp, #0x70]
	str r1, [sp, #0x78]
	b.n .L080170cc
.L08017040:
	add.w r0, r9, r11
	strd r10, r1, [sp, #0x0]
	sxth r3, r0
	add.w r0, r4, r11
	sxth r1, r0
	mov r2, r5
	add r0, sp, #0x80
	bl fn_0801ee18
	movs r1, #0x1
	sub.w r0, r9, r8
	strd r10, r1, [sp, #0x0]
	sxth r3, r0
	sub.w r0, r4, r8
	sxth r1, r0
	mov r2, r5
	b.n .L08016f58
	nop  @ padding
.L08017070:
	ldrsh.w r1, [sp, #0x58]
	add.w r0, r11, r5
	mov r3, r4
	sxth r2, r6
	str r0, [sp, #0x1c]
	bl fn_0801ec54
	strb.w r0, [sp, #0x74]
	cbnz r0, .L08017090
	mov r1, r4
	ldr r0, [sp, #0x1c]
	bl clear_bytes
.L08017090:
	add r5, r4
	adds r1, r5, r4
	cmp r1, r10
	bhs.n .L080170a4
	ldrh.w r0, [sp, #0x5e]
	.inst.n 0x1c40  @ adds r0, r0, #1
	strh.w r0, [sp, #0x5e]
	b.n .L080170ca
.L080170a4:
	movs r0, #0x2
	strb.w r0, [sp, #0x74]
	add r1, sp, #0x64
	ldr r0, [sp, #0x114]
	bl fn_0801f730
	ldrh.w r0, [sp, #0x5e]
	movs r5, #0x0
	.inst.n 0x1c40  @ adds r0, r0, #1
	strh.w r0, [sp, #0x5a]
	strh.w r0, [sp, #0x5e]
	mov r1, r10
	mov r0, r11
	bl fill_bytes_ff
.L080170ca:
	.inst.n 0x1c76  @ adds r6, r6, #1
.L080170cc:
	cmp r6, r7
	ble.n .L08017070
	ldrsh.w r1, [sp, #0x5a]
	ldrsh.w r0, [sp, #0x5e]
	cmp r1, r0
	beq.n .L080170f0
	.inst.n 0x1e40  @ subs r0, r0, #1
	strh.w r0, [sp, #0x5e]
	movs r0, #0x2
	strb.w r0, [sp, #0x74]
	add r1, sp, #0x64
	ldr r0, [sp, #0x114]
	bl fn_0801f730
.L080170f0:
	mov r0, r11
	bl fn_08022c44
	add r0, sp, #0x80
	bl fn_0801ec98
	add r0, sp, #0x28
	bl fn_0801ec98
	cmp.w r9, #0xffffffff
	beq.n .L0801710e
	add r0, sp, #0xac
	bl fn_0801ec98
.L0801710e:
	cmp.w r8, #0xffffffff
	beq.n .L0801711a
	add r0, sp, #0xd8
	bl fn_0801ec98
.L0801711a:
	ldr r0, [sp, #0x60]
	bl table_slot_clear
	ldr r0, [sp, #0x54]
	bl table_slot_clear
	mov r0, r9
	bl table_slot_clear
	mov r0, r8
	bl table_slot_clear
.L08017132:
	add sp, #0x124
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08017138:
	.word d_08050eea
