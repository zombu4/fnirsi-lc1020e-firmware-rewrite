@ lang.s - English only in our build: the settings menu without the language item.
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ Revision 2. The language word 0x2000115C (block 0xBE0) selects
@ row 0 (Chinese) or row 1 (English) of 17 pointer tables in RAM; save.s keeps it and the
@ first-start flag 0x20001140 (block 0xBC4) at 1 in RAM and in every copy it writes. In our
@ build row 0 of every table already equals row 1 in the initial RAM image (src/rodata_04.s
@ ram_image), so every reader gets an English text whatever the
@ language word holds. The Chinese strings, the Chinese glyphs of the fonts 0x0802ce5c /
@ 0x0802f0d8 and the Chinese speed icons are freed in our build (src/rodata_01..04.s,
@ .ifdef OWN; link_own.ld). Addresses of data below are V1.1 addresses, reached through their
@ labels (d_<address>).
@
@ own_menu - replaces fn_0800f294 (ui_44.s: a b.w at its entry, .ifdef OWN): the rows of the
@   settings screen (screen 3). r0 = create flag (non-zero: the five row objects are created),
@   r1 = step of the menu position (fn_08009974: +1 for key 0x20, -1 for key 2; 0 elsewhere).
@   The visible items are the vendor items 0, 2, 3, 4, 5, 6 (Sorting, Brightness, Volume, Off
@   Time, Calibration, System); position p = 0..5 names vendor item 0 for p = 0 and p + 1 else.
@   The menu item word 0x200011A8 keeps the vendor item number, so the dialog title
@   (fn_08009974), the key handler fn_0800f5e8, the dialog builder fn_0800e6c8 and the
@   sub-screens {0, 5, 6} read it unchanged.
@   As fn_0800f294: returns at once while the word 0x200011AC is 1; stores 0 to 0x200011B4 and
@   0x200011B8; the position moves by r1 and stops at 0 and 5 (the vendor stops the item at 0
@   and 6, no wrap). Item 1 (and any value below 0) reads as position 0.
@   Create (r0 != 0), i = 0..4: X = fn_0802122c(word 0x20000014) -> word 0x200058F0[i],
@   fn_08023170(X, 2, 0, 39 + 40 i); T = fn_08021f5c(X) -> 0x20005904[i], fn_08023170(T, 7,
@   15, 0), fn_080266ac(T, 0x0802f0d8, 0); P = fn_08023678(X) -> 0x20005918[i],
@   fn_08023170(P, 9, 60, 0), fn_080263a8(P, 180, 40), fn_08026592 / fn_08026680 /
@   fn_080265be / fn_0802662a (P, 0, 0), fn_08026380(P, 0).
@   Then for i = 0..4: fn_08023050(row i, 1) and fn_08023520(value object i) (all five rows
@   stay objects: fn_0800e6c8 calls fn_08023050 on each).
@   Rows: page 1 (position 0..4) rows 0..4 = items 0, 2, 3, 4, 5; page 2 (position 5) row 0 =
@   item 6. Per row r with item n: fn_080228d0(label r, word 0x20000054[9 language + n]),
@   fn_08023558(row r, 1), fn_08021c14(row r, picture 0x0804bbf8 when n is the menu item, else
@   0x0804a5bc), then the value of item n into value object r, as fn_0800f294 draws it:
@     0, 5, 6: Q = fn_0802122c(value r), fn_08023170(Q, 9, 0, 0), fn_08021c14(Q, 0x0804bd24);
@     2, 3: word 0x20001158 (brightness) / 0x20001160 (volume) divided by 10 (signed) pictures
@       0x0804bda4: Q = fn_0802122c(value r), fn_08023170(Q, 9, 9 j - 35, 0) for j = 0, 1, ..;
@     4: Q = fn_08021f5c(value r), fn_08023170(Q, 9, 0, 0), fn_080266ac(Q, 0x0802f0d8, 0),
@       fn_080228d0(Q, word 0x20000174[4 language + word 0x20001164 (off time)]).
@   No result; r0..r3, r12 and the flags changed. Stack: 40 bytes.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

	.equ	MENU_ROWS,	0x200058F0	@ 5 row objects; +0x14 their labels, +0x28 their
	.equ	MENU_LABELS,	0x14		@ value objects (fn_0800f294: r6, r9, r8)
	.equ	MENU_VALUES,	0x28
	.equ	MENU_LAST,	5		@ last position (vendor item 6)
	.equ	V_UI_WORDS,	0x2000000C	@ +8: word 0x20000014, parent of the rows
	.equ	T_MENU_TXT,	0x20000054	@ menu labels, 9 pointers per language
	.equ	T_OFF_TXT,	0x20000174	@ off time texts, 4 pointers per language
	@ offsets from V_BLOCK (0x2000057C), as fn_0800f294 reads them through r5
	.equ	B_BRIGHT,	0xBDC		@ 0x20001158
	.equ	B_LANGUAGE,	0xBE0		@ 0x2000115C
	.equ	B_VOLUME,	0xBE4		@ 0x20001160
	.equ	B_OFFTIME,	0xBE8		@ 0x20001164
	.equ	B_MENU,		0xC2C		@ 0x200011A8
	.equ	B_DIALOG,	0xC30		@ 0x200011AC
	.equ	B_SEL,		0xC38		@ 0x200011B4
	.equ	B_DIGIT,	0xC3C		@ 0x200011B8

	.section .text.own.lang,"ax",%progbits
	.p2align 2

	.global	own_menu
	.thumb_func
	.type	own_menu, %function
own_menu:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #4			@ [sp]: picture object of a bar; 8-byte aligned calls
	ldr	r5, =V_BLOCK
	ldr.w	r2, [r5, #B_DIALOG]
	cmp	r2, #1
	beq	.Lom_out		@ a dialog is open
	movs	r2, #0
	str.w	r2, [r5, #B_SEL]
	str.w	r2, [r5, #B_DIGIT]
	ldr.w	r7, [r5, #B_MENU]	@ r7 = position of the menu item
	subs	r7, r7, #1		@ item n -> n - 1; items 0 and 1 -> 0
	it	mi
	movmi	r7, #0
	adds	r7, r7, r1		@ + step
	cmp	r7, #MENU_LAST
	it	gt
	movgt	r7, #MENU_LAST
	cmp	r7, #0
	it	lt
	movlt	r7, #0
	adds	r1, r7, #1		@ menu item of the position
	cmp	r7, #0
	it	eq
	moveq	r1, #0
	str.w	r1, [r5, #B_MENU]
	ldr	r6, =MENU_ROWS
	add	r9, r6, #MENU_LABELS
	add	r10, r6, #MENU_VALUES
	cmp	r0, #0
	beq	.Lom_hide
	ldr	r11, =V_UI_WORDS
	movs	r4, #0
.Lom_create:
	ldr.w	r0, [r11, #8]		@ word 0x20000014
	bl	fn_0802122c
	str.w	r0, [r6, r4, lsl #2]
	add.w	r2, r4, r4, lsl #2
	movs	r3, #0x27
	add.w	r3, r3, r2, lsl #3	@ y = 39 + 40 i
	sxth	r3, r3
	movs	r2, #0
	movs	r1, #2
	bl	fn_08023170
	ldr.w	r0, [r6, r4, lsl #2]
	bl	fn_08021f5c
	str.w	r0, [r9, r4, lsl #2]
	movs	r3, #0
	movs	r2, #0xf
	movs	r1, #7
	bl	fn_08023170
	ldr.w	r0, [r9, r4, lsl #2]
	movs	r2, #0
	ldr	r1, =d_0802f0d8
	bl	fn_080266ac
	ldr.w	r0, [r6, r4, lsl #2]
	bl	fn_08023678
	str.w	r0, [r10, r4, lsl #2]
	movs	r3, #0
	movs	r2, #0x3c
	movs	r1, #9
	bl	fn_08023170
	ldr.w	r0, [r10, r4, lsl #2]
	movs	r2, #0x28
	movs	r1, #0xb4
	bl	fn_080263a8
	movs	r2, #0
	mov	r1, r2
	ldr.w	r0, [r10, r4, lsl #2]
	bl	fn_08026592
	movs	r2, #0
	mov	r1, r2
	ldr.w	r0, [r10, r4, lsl #2]
	bl	fn_08026680
	movs	r2, #0
	mov	r1, r2
	ldr.w	r0, [r10, r4, lsl #2]
	bl	fn_080265be
	movs	r2, #0
	mov	r1, r2
	ldr.w	r0, [r10, r4, lsl #2]
	bl	fn_0802662a
	movs	r1, #0
	ldr.w	r0, [r10, r4, lsl #2]
	bl	fn_08026380
	adds	r4, r4, #1
	cmp	r4, #5
	blt	.Lom_create
.Lom_hide:
	movs	r4, #0
.Lom_hide_row:
	ldr.w	r0, [r6, r4, lsl #2]
	movs	r1, #1
	bl	fn_08023050
	ldr.w	r0, [r10, r4, lsl #2]
	bl	fn_08023520
	adds	r4, r4, #1
	cmp	r4, #5
	blt	.Lom_hide_row
	movs	r4, #0			@ r4 = row
.Lom_row:
	movs	r8, #6			@ r8 = item of the row: page 2, item 6
	cmp	r7, #MENU_LAST
	beq	.Lom_label
	adds	r8, r4, #1		@ page 1: rows 0..4 = items 0, 2, 3, 4, 5
	cmp	r4, #0
	it	eq
	moveq	r8, #0
.Lom_label:
	ldr.w	r0, [r5, #B_LANGUAGE]
	add.w	r0, r0, r0, lsl #3	@ 9 language
	add	r0, r0, r8
	ldr	r1, =T_MENU_TXT
	ldr.w	r1, [r1, r0, lsl #2]
	ldr.w	r0, [r9, r4, lsl #2]
	bl	fn_080228d0
	ldr.w	r0, [r6, r4, lsl #2]
	movs	r1, #1
	bl	fn_08023558
	ldr.w	r0, [r5, #B_MENU]
	cmp	r0, r8
	ite	eq
	ldreq	r1, =d_0804bbf8		@ selected row
	ldrne	r1, =d_0804a5bc
	ldr.w	r0, [r6, r4, lsl #2]
	bl	fn_08021c14
	cmp	r8, #2
	beq	.Lom_bright
	cmp	r8, #3
	beq	.Lom_volume
	cmp	r8, #4
	beq	.Lom_offtime
	ldr.w	r0, [r10, r4, lsl #2]	@ items 0, 5, 6: the arrow picture
	bl	fn_0802122c
	mov	r8, r0
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	bl	fn_08023170
	ldr	r1, =d_0804bd24
	mov	r0, r8
	bl	fn_08021c14
	b	.Lom_next
.Lom_bright:
	ldr.w	r1, [r5, #B_BRIGHT]
	b	.Lom_bars
.Lom_volume:
	ldr.w	r1, [r5, #B_VOLUME]
.Lom_bars:
	movs	r0, #10
	sdiv	r11, r1, r0		@ r11 = bars left
	mvn	r8, #0x22		@ r8 = x of the bar: -35, then +9
.Lom_bar:
	cmp	r11, #0
	ble	.Lom_next
	ldr.w	r0, [r10, r4, lsl #2]
	bl	fn_0802122c
	str	r0, [sp]
	sxth	r2, r8
	movs	r3, #0
	movs	r1, #9
	bl	fn_08023170
	ldr	r1, =d_0804bda4
	ldr	r0, [sp]
	bl	fn_08021c14
	adds	r8, r8, #9
	subs	r11, r11, #1
	b	.Lom_bar
.Lom_offtime:
	ldr.w	r0, [r10, r4, lsl #2]
	bl	fn_08021f5c
	mov	r8, r0
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, =d_0802f0d8
	mov	r0, r8
	bl	fn_080266ac
	ldr.w	r1, [r5, #B_LANGUAGE]
	ldr.w	r0, [r5, #B_OFFTIME]
	ldr	r2, =T_OFF_TXT
	add.w	r1, r2, r1, lsl #4	@ 4 pointers per language
	ldr.w	r1, [r1, r0, lsl #2]
	mov	r0, r8
	bl	fn_080228d0
.Lom_next:
	adds	r4, r4, #1
	cmp	r7, #MENU_LAST
	beq	.Lom_out		@ page 2: one row
	cmp	r4, #5
	blt	.Lom_row
.Lom_out:
	add	sp, #4
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}

	.ltorg
