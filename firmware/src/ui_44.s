@ ui_44.s - system settings menu screen builder, its key handler and the compare result display
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0800f294 - builds / refreshes the system settings menu screen (screen 3).
@ r0 = create flag (non-zero creates the five row objects), r1 = step added to
@ the selected menu item; no return value.
@ Base pointer r5 = 0x2000057C (settings block; word offsets are relative to it).
@ Returns at once when the word 0x200011AC (r5+0xC30) equals 1.
@ Stores 0 to 0x200011B4 and 0x200011B8. Menu item word 0x200011A8 (r5+0xC2C)
@ = old + r1, set to 6 when the sum is 7 or more, set to 0 when it is negative.
@ r6 = 0x200058F0 (row object table), r9 = 0x20005904 (label table),
@ r8 = 0x20005918 (value table).
@ Create flag non-zero, loop i = 0..4: X = fn_0802122c([0x20000014]) is stored
@ to 0x200058F0[i]; fn_08023170(X, 2, 0, sxth(0x27 + 40*i)); T = fn_08021f5c(X)
@ is stored to 0x20005904[i]; fn_08023170(T, 7, 0xf, 0); fn_080266ac(T,
@ 0x0802F0D8, 0); P = fn_08023678(X) is stored to 0x20005918[i];
@ fn_08023170(P, 9, 0x3c, 0); fn_080263a8(P, 0xb4, 0x28); fn_08026592,
@ fn_08026680, fn_080265be, fn_0802662a (P, 0, 0) and fn_08026380(P, 0).
@ Then for i = 0..4 (always): fn_08023050(0x200058F0[i], 1) and
@ fn_08023520(0x20005918[i]).
@ Menu item below 5: loop i = 0..4: text = 0x20000054[9*lang + i] with lang =
@ word 0x2000115C (language); fn_080228D0(0x20005904[i], text);
@ fn_08023558(0x200058F0[i], 1); fn_08021c14(0x200058F0[i], 0x0804BBF8 when
@ the menu item equals i, else 0x0804A5BC); then a switch on i:
@   i = 0: Q = fn_0802122c(0x20005918[0]); fn_08023170(Q, 9, 0, 0);
@          fn_08021c14(Q, 0x0804BD24).
@   i = 1: Q = fn_08021f5c(0x20005918[1]); fn_08023170(Q, 9, 0, 0);
@          fn_080266ac(Q, 0x0802F0D8, 0); fn_080228D0(Q, word at
@          0x20000024 + 4*lang).
@   i = 2: for j while j < word 0x20001158 / 10 (brightness): Q =
@          fn_0802122c(0x20005918[2]) stored at [sp + 0x50 + 4*j];
@          fn_08023170(Q, 9, sxth(9*j - 0x23), 0); fn_08021c14(Q, 0x0804BDA4).
@   i = 3: the same with 0x20005918[3], word 0x20001160 / 10 (volume), stored
@          at [sp + 0x78 + 4*j].
@   i = 4: Q = fn_08021f5c(0x20005918[4]) stored at [sp+0xa0]; fn_08023170(Q,
@          9, 0, 0); fn_080266ac(Q, 0x0802F0D8, 0); fn_080228D0(Q, word at
@          0x20000174 + 16*lang + 4*word 0x20001164 (off time)); returns.
@ Menu item 5 or 6: loop i = 0..1: fn_080228D0(0x20005904[i], word at
@ 0x20000068 + 4*(9*lang + i)); fn_08023558(0x200058F0[i], 1);
@ fn_08021c14(0x200058F0[i], 0x0804BBF8 when menu item - 5 == i, else
@ 0x0804A5BC); i = 0: Q = fn_0802122c(0x20005918[0]); fn_08023170(Q, 9, 0, 0);
@ fn_08021c14(Q, 0x0804BD24); i = 1: the same with 0x20005918[1], then returns.
@ All exits share the epilogue at 0x0800F41E (add sp, #0xcc; pop).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800f294,"ax",%progbits
	.p2align 2
	.global fn_0800f294
	.thumb_func
	.type fn_0800f294, %function
fn_0800f294:
.ifdef OWN
	b.w	own_menu		@ our build: the menu without "Language" (own/lang.s)
.else
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
.endif
	ldr	r5, .L0800f5c4
	sub	sp, #0xcc
	ldr.w	r2, [r5, #0xc30]
	cmp	r2, #1
	beq.n	.L0800f3a0
	movs	r2, #0
	str.w	r2, [r5, #0xc38]
	str.w	r2, [r5, #0xc3c]
	ldr.w	r3, [r5, #0xc2c]
	add	r1, r3
	str.w	r1, [r5, #0xc2c]
	cmp	r1, #7
	blt.n	.L0800f2c4
	movs	r1, #6
	str.w	r1, [r5, #0xc2c]
	b.n	.L0800f2cc
.L0800f2c4:
	cmp	r1, #0
	bge.n	.L0800f2cc
	str.w	r2, [r5, #0xc2c]
.L0800f2cc:
	ldr.w	r9, .L0800f5c8
	cmp	r0, #0
	sub.w	r6, r9, #0x14
	add.w	r8, r6, #0x28
	beq.n	.L0800f38e
	ldr.w	r11, .L0800f5cc
	movs	r4, #0
	mov.w	r10, #0x27
	nop
.L0800f2e8:
	ldr.w	r0, [r11, #0x8]
	bl	fn_0802122c
	add.w	r2, r4, r4, lsl #2
	add.w	r1, r10, r2, lsl #3
	sxth	r3, r1
	str.w	r0, [r6, r4, lsl #2]
	movs	r2, #0
	movs	r1, #2
	bl	fn_08023170
	ldr.w	r0, [r6, r4, lsl #2]
	bl	fn_08021f5c
	mov	r7, r9
	str.w	r0, [r9, r4, lsl #2]
	movs	r3, #0
	movs	r2, #0xf
	movs	r1, #7
	bl	fn_08023170
	ldr.w	r0, [r7, r4, lsl #2]
	movs	r2, #0
	ldr	r1, .L0800f5d0
	bl	fn_080266ac
	ldr.w	r0, [r6, r4, lsl #2]
	bl	fn_08023678
	mov	r7, r8
	str.w	r0, [r8, r4, lsl #2]
	movs	r3, #0
	movs	r2, #0x3c
	movs	r1, #9
	bl	fn_08023170
	ldr.w	r0, [r7, r4, lsl #2]
	movs	r2, #0x28
	movs	r1, #0xb4
	bl	fn_080263a8
	movs	r2, #0
	ldr.w	r0, [r7, r4, lsl #2]
	mov	r1, r2
	bl	fn_08026592
	movs	r2, #0
	ldr.w	r0, [r7, r4, lsl #2]
	mov	r1, r2
	bl	fn_08026680
	movs	r2, #0
	ldr.w	r0, [r7, r4, lsl #2]
	mov	r1, r2
	bl	fn_080265be
	movs	r2, #0
	ldr.w	r0, [r7, r4, lsl #2]
	mov	r1, r2
	bl	fn_0802662a
	ldr.w	r0, [r7, r4, lsl #2]
	movs	r1, #0
	bl	fn_08026380
	.inst.n	0x1c64		@ adds r4, r4, #1
	cmp	r4, #5
	blt.n	.L0800f2e8
.L0800f38e:
	movs	r4, #0
	mov.w	r7, r8
.L0800f394:
	ldr.w	r0, [r6, r4, lsl #2]
	movs	r1, #1
	bl	fn_08023050
	b.n	.L0800f3a2
.L0800f3a0:
	b.n	.L0800f41e
.L0800f3a2:
	ldr.w	r0, [r7, r4, lsl #2]
	bl	fn_08023520
	.inst.n	0x1c64		@ adds r4, r4, #1
	cmp	r4, #5
	blt.n	.L0800f394
	ldr	r0, .L0800f5cc
	ldr.w	r1, [r5, #0xc2c]
	adds	r0, #0x48
	mov	r10, sp
	cmp	r1, #5
	mov.w	r4, #0
	bge.n	.L0800f4bc
	mov	r8, r5
	mov	r11, r0
	mov	r9, r6
.L0800f3c8:
	ldr.w	r0, [r8, #0xbe0]
	mov	r6, r8
	add.w	r1, r0, r0, lsl #3
	add.w	r0, r11, r1, lsl #2
	ldr.w	r1, [r0, r4, lsl #2]
	ldr	r0, .L0800f5c8
	ldr.w	r0, [r0, r4, lsl #2]
	bl	fn_080228d0
	mov	r5, r9
	ldr.w	r0, [r9, r4, lsl #2]
	movs	r1, #1
	bl	fn_08023558
	ldr.w	r0, [r6, #0xc2c]
	cmp	r0, r4
	ldr.w	r0, [r5, r4, lsl #2]
	beq.n	.L0800f400
	ldr	r1, .L0800f5d4
	b.n	.L0800f402
.L0800f400:
	ldr	r1, .L0800f5d8
.L0800f402:
	bl	fn_08021c14
	cbz	r4, .L0800f424
	cmp	r4, #1
	beq.n	.L0800f442
	cmp	r4, #2
	beq.n	.L0800f474
	cmp	r4, #3
	beq.n	.L0800f4be
	cmp	r4, #4
	beq.n	.L0800f508
	.inst.n	0x1c64		@ adds r4, r4, #1
	cmp	r4, #5
	blt.n	.L0800f3c8
.L0800f41e:
	add	sp, #0xcc
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0800f424:
	ldr	r0, [r7]
	bl	fn_0802122c
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	str	r0, [sp]
	bl	fn_08023170
	ldr	r1, .L0800f5dc
	ldr	r0, [sp]
	bl	fn_08021c14
	movs	r4, #1
	b.n	.L0800f3c8
.L0800f442:
	ldr	r0, [r7, #4]
	bl	fn_08021f5c
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	str	r0, [sp, #0x28]
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800f5d0
	ldr	r0, [sp, #0x28]
	bl	fn_080266ac
	ldr	r1, .L0800f5cc
	ldr.w	r0, [r6, #0xbe0]
	adds	r1, #0x18
	ldr.w	r1, [r1, r0, lsl #2]
	ldr	r0, [sp, #0x28]
	bl	fn_080228d0
	movs	r4, #2
	b.n	.L0800f3c8
.L0800f474:
	movs	r5, #0
	mov	r8, r6
	b.n	.L0800f4ac
	nop			@ padding
.L0800f47c:
	ldr.w	r0, [r7, r4, lsl #2]
	bl	fn_0802122c
	add.w	r2, r4, r4, lsl #2
	add.w	r6, r10, r2, lsl #3
	add.w	r1, r5, r5, lsl #3
	subs	r1, #0x23
	sxth	r2, r1
	str.w	r0, [r6, r5, lsl #2]
	movs	r3, #0
	movs	r1, #9
	bl	fn_08023170
	ldr.w	r0, [r6, r5, lsl #2]
	ldr	r1, .L0800f5e0
	bl	fn_08021c14
	.inst.n	0x1c6d		@ adds r5, r5, #1
.L0800f4ac:
	ldr.w	r1, [r8, #0xbdc]
	movs	r0, #0xa
	sdiv	r0, r1, r0
	cmp	r0, r5
	bgt.n	.L0800f47c
	b.n	.L0800f502
.L0800f4bc:
	b.n	.L0800f53e
.L0800f4be:
	movs	r5, #0
	mov	r8, r6
	b.n	.L0800f4f4
.L0800f4c4:
	ldr.w	r0, [r7, r4, lsl #2]
	bl	fn_0802122c
	add.w	r2, r4, r4, lsl #2
	add.w	r6, r10, r2, lsl #3
	add.w	r1, r5, r5, lsl #3
	subs	r1, #0x23
	sxth	r2, r1
	str.w	r0, [r6, r5, lsl #2]
	movs	r3, #0
	movs	r1, #9
	bl	fn_08023170
	ldr.w	r0, [r6, r5, lsl #2]
	ldr	r1, .L0800f5e0
	bl	fn_08021c14
	.inst.n	0x1c6d		@ adds r5, r5, #1
.L0800f4f4:
	ldr.w	r1, [r8, #0xbe4]
	movs	r0, #0xa
	sdiv	r0, r1, r0
	cmp	r0, r5
	bgt.n	.L0800f4c4
.L0800f502:
	.inst.n	0x1c64		@ adds r4, r4, #1
	b.n	.L0800f3c8
	b.n	.L0800f508
.L0800f508:
	ldr	r0, [r7, #0x10]
	bl	fn_08021f5c
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	str	r0, [sp, #0xa0]
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800f5d0
	ldr	r0, [sp, #0xa0]
	bl	fn_080266ac
	ldr	r2, .L0800f5e4
	ldr.w	r1, [r8, #0xbe0]
	ldr.w	r0, [r8, #0xbe8]
	add.w	r1, r2, r1, lsl #4
	ldr.w	r1, [r1, r0, lsl #2]
	ldr	r0, [sp, #0xa0]
	bl	fn_080228d0
	b.n	.L0800f41e
.L0800f53e:
	mov	r8, r0
.L0800f540:
	ldr.w	r0, [r5, #0xbe0]
	add.w	r1, r0, r0, lsl #3
	add.w	r0, r8, r1, lsl #2
	add.w	r0, r0, r4, lsl #2
	ldr	r1, [r0, #0x14]
	ldr.w	r0, [r9, r4, lsl #2]
	bl	fn_080228d0
	ldr.w	r0, [r6, r4, lsl #2]
	movs	r1, #1
	bl	fn_08023558
	ldr.w	r0, [r5, #0xc2c]
	.inst.n	0x1f40		@ subs r0, r0, #5
	cmp	r0, r4
	ldr.w	r0, [r6, r4, lsl #2]
	beq.n	.L0800f576
	ldr	r1, .L0800f5d4
	b.n	.L0800f578
.L0800f576:
	ldr	r1, .L0800f5d8
.L0800f578:
	bl	fn_08021c14
	cbz	r4, .L0800f58a
	cmp	r4, #1
	beq.n	.L0800f5a8
	.inst.n	0x1c64		@ adds r4, r4, #1
	cmp	r4, #2
	blt.n	.L0800f540
	b.n	.L0800f41e
.L0800f58a:
	ldr	r0, [r7]
	bl	fn_0802122c
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	str	r0, [sp]
	bl	fn_08023170
	ldr	r1, .L0800f5dc
	ldr	r0, [sp]
	bl	fn_08021c14
	movs	r4, #1
	b.n	.L0800f540
.L0800f5a8:
	ldr	r0, [r7, #4]
	bl	fn_0802122c
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	str	r0, [sp, #0x28]
	bl	fn_08023170
	ldr	r1, .L0800f5dc
	ldr	r0, [sp, #0x28]
	bl	fn_08021c14
	b.n	.L0800f41e
.L0800f5c4:
	.word 0x2000057c	@ settings block base (r5)
.L0800f5c8:
	.word 0x20005904	@ label object table
.L0800f5cc:
	.word 0x2000000c
.L0800f5d0:
	.word d_0802f0d8
.L0800f5d4:
	.word d_0804a5bc
.L0800f5d8:
	.word d_0804bbf8
.L0800f5dc:
	.word d_0804bd24
.L0800f5e0:
	.word d_0804bda4
.L0800f5e4:
	.word 0x20000174

@ ----------------------------------------------------------------------------
@ fn_0800f5e8 - key handler of the settings and calibration screens.
@ r0 = key code. Reads the menu item word 0x200011A8 (r6, base 0x2000057C +
@ 0xC2C) and the byte 0x2000000C (r7). Ends with fn_0800f294(0) (r0 = r1 = 0)
@ and a tail branch to fn_0800e6c8().
@ Menu item 0 and byte 0x2000000C = 0: keys 4 or 0x20 increment word
@ 0x200011B4 up to 4, keys 0x10 or 2 decrement it down to 0.
@ Same item with the byte non-zero: key 4 raises word 0x200011B8 (limit 5 for
@ row 0, 2 for row 1) or sets word 0x2000116C, 0x20001170, 0x20001174 to 1
@ for rows 2, 3, 4 (WarnType, WarnSound, WarnLed); key 0x10 lowers 0x200011B8
@ or sets those words to 0; key 2 or 0x20 on rows 0 and 1 call fn_0800e224
@ with +1 or -1.
@ Menu item 1: keys 0x10 or 4 step word 0x2000115C (language) up by one and
@ wrap it to 0 when it exceeds 1.
@ Menu item 2: key 0x10 subtracts 10 from word 0x20001158 (brightness) above
@ 10, key 4 adds 10 up to 0x5A or less; then calls fn_08009e60(0x20001158).
@ Menu item 3: same limits on word 0x20001160 (volume), without the call.
@ Menu item 4: key 4 raises word 0x20001164 (off time) up to 3, key 0x10 lowers
@ it down to 0.
@ Menu item 6 with byte 0x2000000C = 1: keys 4 or 0x10 set word 0x200011B4 to
@ (value + 1) mod 2.
@ Menu item 5 (calibration): keys 4 / 0x10 move word 0x200050E0 (calibration
@ type; 0..0xB when word 0x200011C0 = 2, else toggles between 0 and 0xB) and
@ clear 0x200050E4, 0x200050E8, 0x200050EC; key 8 with word 0x200011B0 = 1
@ sets 0x200050E4 = 1, clears 0x200050E8, 0x20005108, 0x20005114, sets
@ 0x200050EC = 1, clears 0x78 bytes at 0x200010C0 with zero_bytes, sets
@ 0x2000113C = 0, 0x20001150 = 0, 0x20001144 = 100, float 0x20001138 =
@ 0x3DCCCCCD (0.1) and calls fn_08009f10.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800f5e8,"ax",%progbits
	.p2align 2
	.global fn_0800f5e8
	.thumb_func
	.type fn_0800f5e8, %function
fn_0800f5e8:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r1, .L0800f840
	ldr	r4, .L0800f83c
	movs	r3, #1
	ldrb	r7, [r1]
	mov	r1, r4
	ldr.w	r6, [r4, #0xc2c]
	ldr.w	r1, [r1, #0xc38]
	adds	r2, r1, #1
	movs	r5, #0
	cbz	r6, .L0800f61e
	cmp	r6, #5
	beq.n	.L0800f6e2
	cmp	r6, #1
	beq.n	.L0800f700
	cmp	r6, #2
	beq.n	.L0800f702
	cmp	r6, #3
	beq.n	.L0800f704
	cmp	r6, #4
	beq.n	.L0800f706
	cmp	r6, #6
	beq.n	.L0800f708
	b.n	.L0800f82a
.L0800f61e:
	cbz	r7, .L0800f638
	ldr	r2, .L0800f83c
	cmp	r0, #4
	ldr.w	r2, [r2, #0xc3c]
	beq.n	.L0800f660
	cmp	r0, #0x10
	beq.n	.L0800f696
	cmp	r0, #2
	beq.n	.L0800f6c8
	cmp	r0, #0x20
	beq.n	.L0800f6d2
	b.n	.L0800f82a
.L0800f638:
	cmp	r0, #4
	beq.n	.L0800f64a
	cmp	r0, #0x20
	beq.n	.L0800f64a
	cmp	r0, #0x10
	beq.n	.L0800f654
	cmp	r0, #2
	beq.n	.L0800f654
	b.n	.L0800f82a
.L0800f64a:
	cmp	r1, #4
	bge.n	.L0800f652
	str.w	r2, [r4, #0xc38]
.L0800f652:
	b.n	.L0800f82a
.L0800f654:
	cmp	r1, #0
	ble.n	.L0800f65e
	.inst.n	0x1e49		@ subs r1, r1, #1
	str.w	r1, [r4, #0xc38]
.L0800f65e:
	b.n	.L0800f82a
.L0800f660:
	cbz	r1, .L0800f674
	cmp	r1, #1
	beq.n	.L0800f674
	cmp	r1, #2
	beq.n	.L0800f684
	cmp	r1, #3
	beq.n	.L0800f68a
	cmp	r1, #4
	beq.n	.L0800f690
	b.n	.L0800f82a
.L0800f674:
	cbz	r1, .L0800f680
	movs	r0, #2
.L0800f678:
	cmp	r2, r0
	bge.n	.L0800f688
	.inst.n	0x1c52		@ adds r2, r2, #1
	b.n	.L0800f6b0
.L0800f680:
	movs	r0, #5
	b.n	.L0800f678
.L0800f684:
	str.w	r3, [r4, #0xbf0]
.L0800f688:
	b.n	.L0800f82a
.L0800f68a:
	str.w	r3, [r4, #0xbf4]
	b.n	.L0800f82a
.L0800f690:
	str.w	r3, [r4, #0xbf8]
	b.n	.L0800f82a
.L0800f696:
	cbz	r1, .L0800f6aa
	cmp	r1, #1
	beq.n	.L0800f6aa
	cmp	r1, #2
	beq.n	.L0800f6b6
	cmp	r1, #3
	beq.n	.L0800f6bc
	cmp	r1, #4
	beq.n	.L0800f6c2
	b.n	.L0800f82a
.L0800f6aa:
	cmp	r2, #0
	ble.n	.L0800f6b4
	.inst.n	0x1e52		@ subs r2, r2, #1
.L0800f6b0:
	str.w	r2, [r4, #0xc3c]
.L0800f6b4:
	b.n	.L0800f82a
.L0800f6b6:
	str.w	r5, [r4, #0xbf0]
	b.n	.L0800f82a
.L0800f6bc:
	str.w	r5, [r4, #0xbf4]
	b.n	.L0800f82a
.L0800f6c2:
	str.w	r5, [r4, #0xbf8]
	b.n	.L0800f82a
.L0800f6c8:
	cbz	r1, .L0800f6ce
	cmp	r1, #1
	bne.n	.L0800f6e0
.L0800f6ce:
	movs	r0, #1
	b.n	.L0800f6dc
.L0800f6d2:
	cbz	r1, .L0800f6d8
	cmp	r1, #1
	bne.n	.L0800f6e0
.L0800f6d8:
	mov.w	r0, #0xffffffff
.L0800f6dc:
	bl	fn_0800e224
.L0800f6e0:
	b.n	.L0800f82a
.L0800f6e2:
	ldr	r1, .L0800f83c
	movs	r7, #0xb
	cmp	r0, #4
	ldr.w	r6, [r1, #0xc44]
	add.w	r1, r1, #0x4000
	ldr.w	r2, [r1, #0xb64]
	beq.n	.L0800f70a
	cmp	r0, #0x10
	beq.n	.L0800f72e
	cmp	r0, #8
	beq.n	.L0800f740
	b.n	.L0800f82a
.L0800f700:
	b.n	.L0800f780
.L0800f702:
	b.n	.L0800f79c
.L0800f704:
	b.n	.L0800f7c8
.L0800f706:
	b.n	.L0800f7ec
.L0800f708:
	b.n	.L0800f810
.L0800f70a:
	cmp	r6, #2
	bne.n	.L0800f71a
	.inst.n	0x1c52		@ adds r2, r2, #1
	str.w	r2, [r1, #0xb64]
	cmp	r2, #0xb
	bgt.n	.L0800f71c
	b.n	.L0800f720
.L0800f71a:
	cbz	r2, .L0800f73a
.L0800f71c:
	str.w	r5, [r1, #0xb64]
.L0800f720:
	str.w	r5, [r1, #0xb6c]
	str.w	r5, [r1, #0xb68]
	str.w	r5, [r1, #0xb70]
	b.n	.L0800f82a
.L0800f72e:
	cmp	r6, #2
	bne.n	.L0800f71a
	.inst.n	0x1e52		@ subs r2, r2, #1
	str.w	r2, [r1, #0xb64]
	bpl.n	.L0800f720
.L0800f73a:
	str.w	r7, [r1, #0xb64]
	b.n	.L0800f720
.L0800f740:
	ldr.w	r0, [r4, #0xc34]
	cmp	r0, #1
	bne.n	.L0800f82a
	addw	r1, r1, #0xb68
	ldr	r0, .L0800f844
	strd	r3, r5, [r1]
	str	r5, [r1, #0x24]
	str	r5, [r1, #0x30]
	str	r3, [r1, #8]
	movs	r1, #0x78
	bl	zero_bytes
	ldr	r0, .L0800f84c
	vldr	s0, .L0800f848
	movs	r1, #0x64
	vstr	s0, [r0, #0x3c0]
	vldr	s0, .L0800f850
	str.w	r5, [r4, #0xbd4]
	str.w	r1, [r4, #0xbc8]
	vstr	s0, [r0, #0x3bc]
	bl	fn_08009f10
	b.n	.L0800f82a
.L0800f780:
	cmp	r0, #0x10
	beq.n	.L0800f788
	cmp	r0, #4
	bne.n	.L0800f82a
.L0800f788:
	ldr.w	r0, [r4, #0xbe0]
	.inst.n	0x1c40		@ adds r0, r0, #1
.ifdef OWN
	nop.w			@ our build: the language word is not toggled (own_menu)
.else
	str.w	r0, [r4, #0xbe0]
.endif
	cmp	r0, #1
	ble.n	.L0800f82a
.ifdef OWN
	nop.w			@ our build: no store of 0 to the language word
.else
	str.w	r5, [r4, #0xbe0]
.endif
	b.n	.L0800f82a
.L0800f79c:
	ldr	r1, .L0800f83c
	cmp	r0, #0x10
	ldr.w	r1, [r1, #0xbdc]
	beq.n	.L0800f7ac
	cmp	r0, #4
	beq.n	.L0800f7b4
	b.n	.L0800f7be
.L0800f7ac:
	cmp	r1, #0xa
	ble.n	.L0800f7be
	subs	r1, #0xa
	b.n	.L0800f7ba
.L0800f7b4:
	cmp	r1, #0x5a
	bgt.n	.L0800f7be
	adds	r1, #0xa
.L0800f7ba:
	str.w	r1, [r4, #0xbdc]
.L0800f7be:
	ldr.w	r0, [r4, #0xbdc]
	bl	fn_08009e60
	b.n	.L0800f82a
.L0800f7c8:
	ldr	r1, .L0800f83c
	cmp	r0, #0x10
	ldr.w	r1, [r1, #0xbe4]
	beq.n	.L0800f7d8
	cmp	r0, #4
	beq.n	.L0800f7e0
	b.n	.L0800f82a
.L0800f7d8:
	cmp	r1, #0xa
	ble.n	.L0800f82a
	subs	r1, #0xa
	b.n	.L0800f7e6
.L0800f7e0:
	cmp	r1, #0x5a
	bgt.n	.L0800f82a
	adds	r1, #0xa
.L0800f7e6:
	str.w	r1, [r4, #0xbe4]
	b.n	.L0800f82a
.L0800f7ec:
	ldr	r1, .L0800f83c
	cmp	r0, #4
	ldr.w	r1, [r1, #0xbe8]
	beq.n	.L0800f7fc
	cmp	r0, #0x10
	beq.n	.L0800f804
	b.n	.L0800f82a
.L0800f7fc:
	cmp	r1, #3
	bge.n	.L0800f82a
	.inst.n	0x1c49		@ adds r1, r1, #1
	b.n	.L0800f80a
.L0800f804:
	cmp	r1, #0
	ble.n	.L0800f82a
	.inst.n	0x1e49		@ subs r1, r1, #1
.L0800f80a:
	str.w	r1, [r4, #0xbe8]
	b.n	.L0800f82a
.L0800f810:
	cmp	r7, #1
	bne.n	.L0800f82a
	cmp	r0, #4
	beq.n	.L0800f81c
	cmp	r0, #0x10
	bne.n	.L0800f82a
.L0800f81c:
	add.w	r0, r2, r2, lsr #31
	bic.w	r0, r0, #1
	subs	r0, r2, r0
	str.w	r0, [r4, #0xc38]
.L0800f82a:
	movs	r1, #0
	mov	r0, r1
	bl	fn_0800f294
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_0800e6c8
	.short	0x0000		@ padding
.L0800f83c:
	.word 0x2000057c	@ settings block base (r4)
.L0800f840:
	.word 0x2000000c
.L0800f844:
	.word 0x200010c0
.L0800f848:
	.word 0x00000000
.L0800f84c:
	.word 0x20000d7c
.L0800f850:
	.word 0x3dcccccd	@ float 0.1

@ ----------------------------------------------------------------------------
@ fn_0800f854 - refreshes the measure / compare screens: mode image choice and
@ compare result text. No parameters.
@ Returns unless word 0x20001168 (screen state) is 1 or 2.
@ When word 0x20001148 (Func) is 0 (AUTO), chooses the mode from words
@ 0x200050A8, 0x200050D0, 0x200050CC, 0x200050C0 (range tests on their integer
@ view): mode 2 (image 0x0803D3D4), mode 3 (image 0x0803D584) or mode 1 (image
@ 0x0803D2FC); a change draws the image with fn_08021c14(0x200001E8, image) and
@ stores the mode to byte 0x200011E4 (0x2000057C + 0xC68) and word 0x200011E8
@ (0x2000057C + 0xC6C).
@ Calls fn_0800d3d8 and fn_0800d294.
@ With word 0x20001168 = 2 (compare screen): float 0x200050D8 = abs(float
@ 0x200050DC - float 0x20001184) * 100 / float 0x20001184 (computed in double
@ through float_to_double, double_multiply, double_divide, double_to_float),
@ limited to 99.99 (0x42C7FAE1) when it exceeds 0x42C60000 (99.0). When it
@ does not exceed float 0x20001188 (tolerance) prints "OK" into object
@ 0x200001D4+0x40 with color rgb_to_565(0, 0xff), otherwise "NG" with color
@ rgb_to_565(0xff, 0). Prints "%0.2f" of 0x200050D8 into object 0x200001D4+0x44
@ and the nominal float 0x20001184 formatted by fn_0800e028, fn_0800db24 or
@ fn_0800de2c (word 0x20001178 = 1, 2, 3) with "%s%s" into object
@ 0x200001D4+0x34.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800f854,"ax",%progbits
	.p2align 2
	.global fn_0800f854
	.thumb_func
	.type fn_0800f854, %function
fn_0800f854:
	push	{r4, r5, r6, r7, lr}
	ldr	r4, .L0800fa0c
	vpush	{d8, d9}
	sub	sp, #0x14
	ldr.w	r0, [r4, #0xbec]
	cmp	r0, #1
	beq.n	.L0800f86a
	cmp	r0, #2
	bne.n	.L0800f94a
.L0800f86a:
	ldr	r6, .L0800fa10
	ldr	r5, .L0800fa14
	ldr.w	r0, [r4, #0xbcc]
	cbnz	r0, .L0800f8d6
.ifdef OWN
	@ S2.5: the AUTO decision with hysteresis (own/cmp.s); the rest
	@ of the vendor block is not reached (same size, the labels the code outside uses kept)
	bl	own_auto_class		@ 0x0800F874
	b.n	.L0800f8ec		@ 0x0800F878
	.rept	46			@ 0x0800F87A..0x0800F8D5: not reached
	nop.n
	.endr
.L0800f8d6:
	b.n	.L0800f8ec		@ 0x0800F8D6: the target of the cbnz (Func not AUTO)
	.rept	10			@ 0x0800F8D8..0x0800F8EB: not reached
	nop.n
	.endr
.else
	ldr	r1, .L0800fa18
	ldr.w	r0, [r5, #0x32c]
	ldr	r7, .L0800fa1c
	adds	r3, r0, r1
	ldr	r1, .L0800fa0c
	mov	r0, r6
	cmp	r3, r7
	ldrsb.w	r2, [r1, #0xc68]
	add.w	r1, r1, #0x4800
	ldr	r0, [r0, #0x14]
	ldr.w	r1, [r1, #0x350]
	bcs.n	.L0800f8b2
	ldr.w	r3, [r5, #0x354]
	cmp.w	r3, #0x3f000000
	ble.n	.L0800f8b2
	cmn.w	r1, #0x40800000
	bls.n	.L0800f8b2
	cmp	r2, #2
	beq.n	.L0800f8ec
	ldr	r1, .L0800fa20
	bl	fn_08021c14
	movs	r0, #2
	b.n	.L0800f8e4
.L0800f8b2:
	ldr.w	r3, [r5, #0x344]
	mvn	r7, #0x3f000000
	add	r3, r7
	ldr	r7, .L0800fa24
	cmp	r3, r7
	bcs.n	.L0800f8d8
	ldr	r3, .L0800fa28
	cmp	r1, r3
	ble.n	.L0800f8d8
	cmp	r2, #3
	beq.n	.L0800f8ec
	ldr	r1, .L0800fa2c
	bl	fn_08021c14
	movs	r0, #3
	b.n	.L0800f8e4
.L0800f8d6:
	b.n	.L0800f8ec
.L0800f8d8:
	cmp	r2, #1
	beq.n	.L0800f8ec
	ldr	r1, .L0800fa30
	bl	fn_08021c14
	movs	r0, #1
.L0800f8e4:
	strb.w	r0, [r4, #0xc68]
	str.w	r0, [r4, #0xc6c]
.endif
.L0800f8ec:
	bl	fn_0800d3d8
	bl	fn_0800d294
	ldr.w	r0, [r4, #0xbec]
	cmp	r0, #2
	bne.n	.L0800f94a
.ifdef OWN
	@ S2.8 / S2.9: the compare screen's result, deviation and nominal
	@ (own/cmp.s); the rest of the vendor block is not reached (same size, .L0800f94a kept)
	bl	own_cmp_show		@ 0x0800F8FC
	b.n	.L0800fa04		@ 0x0800F900
	.rept	36			@ 0x0800F902..0x0800F949: not reached
	nop.n
	.endr
.L0800f94a:
	b.n	.L0800fa04		@ 0x0800F94A: the target of the screen tests above
	.rept	92			@ 0x0800F94C..0x0800FA03: not reached
	nop.n
	.endr
.else
	ldr	r7, .L0800fa34
	vldr	s18, [r7, #8]
	vmov	r0, s18
	bl	float_to_double
	vldr	s0, [r5, #0x360]
	vmov	d8, r0, r1
	vsub.f32	s0, s0, s18
	vabs.f32	s0, s0
	vmov	r0, s0
	bl	float_to_double
	vldr	d1, .L0800fa38
	vmov	r2, r3, d1
	bl	double_multiply
	vmov	r2, r3, d8
	bl	double_divide
	bl	double_to_float
	ldr	r1, .L0800fa40
	str.w	r0, [r5, #0x35c]
	cmp	r0, r1
	bgt.n	.L0800f94c
	vmov	s0, r0
	b.n	.L0800f954
.L0800f94a:
	b.n	.L0800fa04
.L0800f94c:
	vldr	s0, .L0800fa44
	vstr	s0, [r5, #0x35c]
.L0800f954:
	vldr	s1, [r7, #0xc]
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	ble.n	.L0800f974
	adr	r2, .L0800fa48
	adr	r1, .L0800fa4c
	ldr	r0, [r6, #0x40]
	bl	fn_080228d0
	movs	r2, #0
	mov	r1, r2
	movs	r0, #0xff
	b.n	.L0800f984
.L0800f974:
	adr	r2, .L0800fa50
	adr	r1, .L0800fa4c
	ldr	r0, [r6, #0x40]
	bl	fn_080228d0
	movs	r2, #0
	movs	r1, #0xff
	mov	r0, r2
.L0800f984:
	bl	rgb_to_565_0801d7c2
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r6, #0x40]
	bl	fn_08026694
	ldr.w	r0, [r5, #0x35c]
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800fa54
	vmov	r2, r3, d0
	ldr	r0, [r6, #0x44]
	bl	fn_080228d0
	movs	r0, #0
	str	r0, [sp]
	str	r0, [sp, #4]
	str	r0, [sp, #8]
	str	r0, [sp, #0xc]
	str	r0, [sp, #0x10]
	ldr.w	r0, [r4, #0xbfc]
	cmp	r0, #1
	bne.n	.L0800f9cc
	vldr	s0, [r7, #8]
	mov	r2, sp
	add	r1, sp, #0xc
	add	r0, sp, #4
	bl	fn_0800e028
.L0800f9cc:
	ldr.w	r0, [r4, #0xbfc]
	cmp	r0, #2
	bne.n	.L0800f9e2
	vldr	s0, [r7, #8]
	mov	r2, sp
	add	r1, sp, #0xc
	add	r0, sp, #4
	bl	fn_0800db24
.L0800f9e2:
	ldr.w	r0, [r4, #0xbfc]
	cmp	r0, #3
	bne.n	.L0800f9f8
	vldr	s0, [r7, #8]
	mov	r2, sp
	add	r1, sp, #0xc
	add	r0, sp, #4
	bl	fn_0800de2c
.L0800f9f8:
	add	r3, sp, #0xc
	add	r2, sp, #4
	adr	r1, .L0800fa5c
	ldr	r0, [r6, #0x34]
	bl	fn_080228d0
.endif
.L0800fa04:
	add	sp, #0x14
	vpop	{d8, d9}
	pop	{r4, r5, r6, r7, pc}
.L0800fa0c:
	.word 0x2000057c	@ settings block base (r4)
.L0800fa10:
	.word 0x200001d4	@ screen object table (r6)
.L0800fa14:
	.word 0x20004d7c	@ measured values base (r5)
.L0800fa18:
	.word 0xc5fced90
.L0800fa1c:
	.word 0x133ba9b0
.L0800fa20:
	.word d_0803d3d4
.L0800fa24:
	.word 0x0dbebc1f
.L0800fa28:
	.word 0x40a00000
.L0800fa2c:
	.word d_0803d584
.L0800fa30:
	.word d_0803d2fc
.L0800fa34:
	.word 0x2000117c	@ compare values (nominal, tolerance)
.L0800fa38:
	.word 0x00000000	@ double 100.0 (low word)
	.word 0x40590000	@ double 100.0 (high word)
.L0800fa40:
	.word 0x42c60000	@ float 99.0
.L0800fa44:
	.word 0x42c7fae1	@ float 99.99
.L0800fa48:
	.asciz "NG"
	.byte 0x00		@ padding
.L0800fa4c:
	.asciz "%s"
	.byte 0x00		@ padding
.L0800fa50:
	.asciz "OK"
	.byte 0x00		@ padding
.L0800fa54:
	.asciz "%0.2f"
	.short 0x0000		@ padding
.L0800fa5c:
	.asciz "%s%s"
	.byte 0x00, 0x00, 0x00	@ padding
