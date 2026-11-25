@ logo.s - the start-up logo of our build: "FU**NIRSI" (owner, 2026-11-21).
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ The vendor's start-up animation fn_0800ce54 (ui_41.s) draws straight
@ to the panel (no GUI): the white word "FNIRSI" (picture d_08046c9c, 160 columns x 27 rows,
@ RGB565, stored column by column: index = column * rows + row, fn_08009ba0) at x 80, y 106; the
@ backlight ramp up to the brightness setting; three drops (8 x 8 d_08048e5c, 6 x 8 d_08048edc,
@ 5 x 8 d_08048f3c) falling one after the other from y 1 to 105 at x 0xDD / 0xE5 / 0xEB onto the
@ dots of the i; the blue word (d_0804499c, 160 x 28, with the coloured dots) revealed column by
@ column at x 80, y 105; a wait; the GUI set-up fn_08021e98; fn_080269f0.
@ own_logo is the same sequence with the word "FU**NIRSI", composed while it is drawn from pieces
@ of the vendor's own two pictures (no new pixel data): the letters F N I R S i as they are, the
@ U from the S's bottom-right corner under the I's stem top (and the same mirrored), with the
@ S's bottom bar between the halves, each * from the I's stem ends crossed by the N's diagonal
@ and its mirror. Each picture has its own piece table (the pictures differ: the blue strokes
@ are one column wider on the left and reach row 27; measured column by column).
@ The word is 244 columns wide at x 38; the drops fall onto the same columns of the i as before
@ (source columns 141 / 149 / 155 -> x 263 / 271 / 277).
@
@ logo_draw - r0 = picture, r1 = rows, r2 = piece table, r3 = screen y | delay << 16. For each of
@   the LOGO_W destination columns: a column of `rows` halfwords on the stack is cleared, every
@   piece covering the column adds its pixels (per pixel the brighter one stays, brightness
@   R + G / 2 + B of the RGB565 fields), then the panel window of that one column
@   (fn_08009e30) and the halfwords to the data port; fn_08011c68(delay) after each column when
@   the delay is not 0 (the vendor's reveal waited 4 per column, fn_08009ba0's row-delay flag).
@ Piece table: a word with the number of pieces, then 8 bytes per piece: source column, source
@   row, width, height, flags (bit 0: mirrored), destination column, destination row, repeat
@   count (the piece repeated side by side). Every piece stays inside its picture and the column.
@
@ RAM: none (stack only). Flash: nothing here addresses the flash controller.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

	.equ	LCD_DATA,	0x60020000	@ panel data port
	.equ	LOGO_X,		38		@ (320 - 244) / 2
	.equ	LOGO_W,		244		@ destination columns
	.equ	LOGO_Y_WHITE,	106		@ as the vendor's white word (0x6A)
	.equ	LOGO_Y_BLUE,	105		@ as the vendor's blue word (0x69)
	.equ	ROWS_WHITE,	27
	.equ	ROWS_BLUE,	28
	.equ	REVEAL_DELAY,	3		@ fn_08011c68 count per column: 244 x 3 = 732 (vendor 640)
	.equ	DROP_STEPS,	0x6A		@ drop positions y 1 .. 0x69
	.equ	DROP_H,		8
	.equ	BRIGHT_OFF,	0xBDC		@ brightness word: V_BLOCK + 0xBDC (0x0800CE80)
	.equ	PIECE,		8		@ bytes per piece
	.equ	COL_BUF,	56		@ column buffer: 28 halfwords
	.equ	COL_END,	56		@ stack word after it: end of the piece table

	.section .text.own.logo,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ own_logo - entered from the first instruction of fn_0800ce54 (ui_41.s, .ifdef OWN); the only
@   caller is the start-up (system_40.s), which needs r4..r11 kept (AAPCS). Ends as the vendor's
@   function: tail call of fn_080269f0.
@ ----------------------------------------------------------------------------
	.global	own_logo
	.thumb_func
	.type	own_logo, %function
own_logo:
	push	{r4, r5, r6, r7, lr}
	sub	sp, #12			@ [sp], [sp + 4], [sp + 8]: stack arguments of fn_08009ba0
	ldr	r0, =d_08046c9c		@ the white word
	movs	r1, #ROWS_WHITE
	ldr	r2, =logo_white
	movs	r3, #LOGO_Y_WHITE
	bl	logo_draw
	movs	r5, #0			@ backlight ramp, as 0x0800CE6C..0x0800CE86
	ldr	r6, =V_BLOCK
	b	.Lol_ramp_test
.Lol_ramp:
	movs	r0, #2
	bl	fn_08011c68
	mov	r0, r5
	bl	fn_08009e60
	adds	r5, r5, #1
.Lol_ramp_test:
	ldr	r0, [r6, #BRIGHT_OFF]
	cmp	r0, r5
	bgt	.Lol_ramp
	ldr	r4, =logo_drops		@ the three drops, one after the other
.Lol_drop:
	ldrh	r0, [r4, #0]		@ x
	cmp	r0, #0
	beq	.Lol_drops_done
	movs	r6, #1			@ y
.Lol_fall:
	movs	r0, #1			@ erase at y - 1 (flag: colour 0), as 0x0800CE8E..
	str	r0, [sp, #0]
	movs	r0, #0
	str	r0, [sp, #4]
	ldr	r7, [r4, #4]		@ drop picture
	str	r7, [sp, #8]
	ldrh	r0, [r4, #0]
	subs	r1, r6, #1
	ldrh	r2, [r4, #2]		@ width
	movs	r3, #DROP_H
	bl	fn_08009ba0
	movs	r0, #0			@ draw at y
	str	r0, [sp, #0]
	str	r0, [sp, #4]
	str	r7, [sp, #8]
	ldrh	r0, [r4, #0]
	mov	r1, r6
	ldrh	r2, [r4, #2]
	movs	r3, #DROP_H
	bl	fn_08009ba0
	movs	r0, #2
	bl	fn_08011c68
	adds	r6, r6, #1
	cmp	r6, #DROP_STEPS
	blt	.Lol_fall
	adds	r4, r4, #8
	b	.Lol_drop
.Lol_drops_done:
	ldr	r0, =d_0804499c		@ the blue word, revealed column by column
	movs	r1, #ROWS_BLUE
	ldr	r2, =logo_blue
	ldr	r3, =LOGO_Y_BLUE | (REVEAL_DELAY << 16)
	bl	logo_draw
	mov	r0, #0x1F4		@ as 0x0800CF38..
	bl	fn_08011c68
	bl	fn_08021e98		@ the GUI set-up
	add	sp, #12
	pop.w	{r4, r5, r6, r7, lr}
	b.w	fn_080269f0

@ ----------------------------------------------------------------------------
@ logo_draw - arguments and rules in the file header. AAPCS.
@   Registers: r4 picture, r5 rows, r6 piece table, r7 screen y, r8 delay, r9 destination
@   column, r11 piece, r10 / lr scratch in the pixel loop.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	logo_draw, %function
logo_draw:
	push	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #60			@ column buffer (56 bytes) and the table end (4)
	mov	r4, r0
	mov	r5, r1
	mov	r6, r2
	uxth	r7, r3
	lsrs	r8, r3, #16
	ldr	r0, [r6], #4		@ number of pieces; r6 = the first piece
	add	r0, r6, r0, lsl #3
	str	r0, [sp, #COL_END]	@ end of the table
	movs	r9, #0
.Lld_col:
	movs	r0, #0			@ column cleared
	movs	r1, #0
.Lld_clear:
	strh	r0, [sp, r1]
	adds	r1, r1, #2
	cmp	r1, r5, lsl #1
	blo	.Lld_clear
	mov	r11, r6
.Lld_piece:
	ldrb	r0, [r11, #5]		@ destination column
	ldrb	r1, [r11, #2]		@ width
	ldrb	r2, [r11, #7]		@ repeat count
	mul	r2, r1, r2		@ columns covered
	subs	r3, r9, r0		@ column within the piece
	blo	.Lld_next		@ left of it
	cmp	r3, r2
	bhs	.Lld_next		@ right of it
	udiv	r12, r3, r1		@ the repeat ...
	mls	r3, r12, r1, r3		@ ... and the column in one copy
	ldrb	r12, [r11, #4]		@ flags
	tst	r12, #1
	itt	ne
	subne	r3, r1, r3		@ mirrored: width - 1 - column
	subne	r3, r3, #1
	ldrb	r0, [r11, #0]		@ source column
	add	r3, r3, r0
	mul	r3, r3, r5		@ * rows
	add	r3, r4, r3, lsl #1	@ the source column's first halfword
	ldrb	r0, [r11, #1]		@ source row
	add	r3, r3, r0, lsl #1
	ldrb	r1, [r11, #6]		@ destination row
	add	r1, sp, r1, lsl #1
	ldrb	r2, [r11, #3]		@ height
.Lld_px:
	ldrh	r0, [r3], #2		@ piece pixel
	ldrh	r12, [r1]		@ column pixel so far
	ubfx	lr, r12, #6, #5		@ its brightness: G / 2 ...
	add	lr, lr, r12, lsr #11	@ + R
	and	r12, r12, #31
	add	lr, lr, r12		@ + B
	ubfx	r10, r0, #6, #5		@ the piece pixel's brightness
	add	r10, r10, r0, lsr #11
	and	r12, r0, #31
	add	r10, r10, r12
	cmp	r10, lr
	it	hi
	strhhi	r0, [r1]		@ the brighter one stays
	adds	r1, r1, #2
	subs	r2, r2, #1
	bne	.Lld_px
.Lld_next:
	add	r11, r11, #PIECE
	ldr	r0, [sp, #COL_END]
	cmp	r11, r0
	blo	.Lld_piece
	add	r0, r9, #LOGO_X		@ the column to the panel
	mov	r1, r7
	mov	r2, r0
	add	r3, r7, r5
	subs	r3, r3, #1
	bl	fn_08009e30		@ window (x, y, x, y + rows - 1), then RAMWR
	ldr	r0, =LCD_DATA
	movs	r1, #0
.Lld_out:
	ldrh	r2, [sp, r1]
	strh	r2, [r0]
	adds	r1, r1, #2
	cmp	r1, r5, lsl #1
	blo	.Lld_out
	cmp	r8, #0
	beq	.Lld_nodelay
	mov	r0, r8
	bl	fn_08011c68
.Lld_nodelay:
	add	r9, r9, #1
	cmp	r9, #LOGO_W
	blo	.Lld_col
	add	sp, #60
	pop	{r4, r5, r6, r7, r8, r9, r10, r11, pc}

	.ltorg

	.section .rodata.own.logo,"a",%progbits
	.p2align 2

@ drops: x (u16), width (u16), picture; x 0 ends the list
logo_drops:
	.hword	263, 8
	.word	d_08048e5c
	.hword	271, 6
	.word	d_08048edc
	.hword	277, 5
	.word	d_08048f3c
	.hword	0, 0
	.word	0

@ pieces: source column, source row, width, height, flags (1 mirrored), destination column,
@ destination row, repeat
logo_white:
	.word	15
	.byte	0, 0, 30, 27, 0, 0, 0, 1	@ F
	.byte	128, 17, 14, 10, 0, 53, 17, 1	@ U: right corner (the S's bottom-right corner)
	.byte	64, 0, 11, 17, 0, 56, 0, 1	@ U: right stem (the I's stem top)
	.byte	128, 17, 14, 10, 1, 33, 17, 1	@ U: left corner (mirrored)
	.byte	64, 0, 11, 17, 1, 33, 0, 1	@ U: left stem (mirrored)
	.byte	127, 22, 1, 5, 0, 47, 22, 6	@ U: bottom bar (the S's bottom bar, 6 columns)
	.byte	64, 0, 11, 7, 0, 74, 1, 1	@ first *: vertical arm, top (the I's top end)
	.byte	64, 20, 11, 7, 0, 74, 8, 1	@ first *: vertical arm, bottom (the I's bottom end)
	.byte	37, 9, 19, 10, 0, 70, 3, 1	@ first *: diagonal (the N's)
	.byte	37, 9, 19, 10, 1, 70, 3, 1	@ first *: the other diagonal (mirrored)
	.byte	64, 0, 11, 7, 0, 96, 1, 1	@ second *
	.byte	64, 20, 11, 7, 0, 96, 8, 1
	.byte	37, 9, 19, 10, 0, 92, 3, 1
	.byte	37, 9, 19, 10, 1, 92, 3, 1
	.byte	31, 0, 129, 27, 0, 115, 0, 1	@ N I R S i

logo_blue:
	.word	15
	.byte	0, 0, 30, 28, 0, 0, 0, 1	@ F
	.byte	128, 18, 14, 10, 0, 53, 18, 1	@ U: right corner
	.byte	64, 0, 11, 18, 0, 56, 0, 1	@ U: right stem
	.byte	128, 18, 14, 10, 1, 33, 18, 1	@ U: left corner (mirrored)
	.byte	64, 0, 11, 18, 1, 33, 0, 1	@ U: left stem (mirrored)
	.byte	127, 23, 1, 5, 0, 47, 23, 6	@ U: bottom bar
	.byte	64, 0, 11, 7, 0, 74, 1, 1	@ first *: vertical arm, top
	.byte	64, 21, 11, 7, 0, 74, 8, 1	@ first *: vertical arm, bottom
	.byte	37, 9, 19, 10, 0, 70, 3, 1	@ first *: diagonal
	.byte	37, 9, 19, 10, 1, 70, 3, 1	@ first *: the other diagonal
	.byte	64, 0, 11, 7, 0, 96, 1, 1	@ second *
	.byte	64, 21, 11, 7, 0, 96, 8, 1
	.byte	37, 9, 19, 10, 0, 92, 3, 1
	.byte	37, 9, 19, 10, 1, 92, 3, 1
	.byte	30, 0, 130, 28, 0, 114, 0, 1	@ N I R S i with the dots
