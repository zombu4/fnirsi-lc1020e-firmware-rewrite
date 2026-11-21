@ xtal.s - the crystal-fault screen of our build and the text renderer it uses.
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ VENDOR_FIXES_DESIGN.md F4. When the 8 MHz crystal does not start, the clock set-up of the
@ reset handler (fn_0800c274 -> fn_0800ba4c, branch 0x0800BAF8) leaves the core on the 8 MHz HSI
@ with RCC_CFG SCLKSTS != PLL; V1.1 then runs on, its clock word says 144 MHz, and the IWDG resets
@ the chip in the first main-loop pass, which switches the meter off at every start without a
@ word. Our build instead:
@ - own_pa8_level (ctl.s) latches the power (PA8 high) at once when SCLKSTS != PLL, so the meter
@   stays on through the slower start-up without the power key held;
@ - own_start (ctl.s) ends in xtal_fault when SCLKSTS != PLL. xtal_fault initialises the LCD
@   (fn_08009c14: FSMC, panel commands, screen black; its waits run on TIM7 through fn_08011c68,
@   which feeds the IWDG), draws the text below with font F1, switches the backlight on
@   (fn_08009e60(100): PB4 high), counts 20 s down on the screen, then switches the meter off
@   (fn_0800b274: PA8 low, backlight off) and stays in a loop that feeds the IWDG (on USB power
@   or with the key held the meter stays powered, dark).
@ The wait runs on SysTick, taken over here: CTRL 0, LOAD 79999, VAL 0, CTRL 5 (processor clock,
@ no interrupt), so COUNTFLAG (bit 16, cleared by the read) sets every 10 ms at 8 MHz (HSI:
@ 7.92..8.08 MHz at 25 C, +-2.5 % over temperature, datasheet). Each 10 ms the IWDG is fed
@ (own_feed): it runs when the slot started it (a trial start or a soft restart).
@
@ text_draw - draws one line of font F1 (the vendor's 18-pixel font, object d_0802ce5c) straight
@   to the panel, without the vendor GUI (which is set up only later, fn_08021e98). The font
@   format, as the vendor font engine reads it (RESOURCE_FACTS.md section 7, fn_08020968,
@   fn_0801B174, fn_080169ac):
@   - font object +8 line height, +0xA base line (signed halfwords), +0x10 the font record;
@   - record +0 bitmap base, +4 glyph entries (8 bytes each, by glyph id), +8 range records
@     (20 bytes each), +0x12 bits 0..8 the number of ranges;
@   - range: +0 first code, +4 length (code - first <= length, unsigned, inclusive), +6 glyph id
@     base, +8 sorted u16 list, +0x10 its count, +0x12 type. Type 2: id = base + code - first;
@     type 3: id = base + the index of code - first in the list (0x0801B212); F1 has only these
@     two; the first range whose test passes decides; no glyph: nothing drawn, no advance;
@   - glyph entry: bits 0..19 bitmap offset, bits 20..31 advance in 1/16 pixel (rounded:
@     (a + 8) >> 4), +4 box width, +5 box height, +6 x offset, +7 y offset (signed bytes);
@   - glyph top = line top + (line height - base line) - box height - y offset (0x0801FF4A);
@   - bitmap: 2 bits per pixel (F1's record flags 0x2407), one stream, most significant bits
@     first, row after row without padding; a glyph with width or height 0 (the space) draws
@     nothing (0x0801FF2A / 0x0801FF30).
@   F1's class kerning (record +0xC) is not applied.
@   Each pixel value 0..3 is a colour from a 4-entry RGB565 table (the shade on black).
@   r0 = x of the pen, r1 = top of the line, r2 = text (bytes, 0 at the end), r3 = shade table.
@   Returns r0 = x of the pen after the text. AAPCS (r4..r11 kept).
@
@ RAM: none (stack only). Flash: nothing here addresses the flash controller.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

	.equ	LCD_DATA,	0x60020000	@ panel data port (fn_08009e30: 0x6001FFFE + 2)
	.equ	SYST_RVR,	SYST_CSR + 4	@ SysTick reload value
	.equ	SYST_CVR,	SYST_CSR + 8	@ SysTick current value
	.equ	SYST_10MS_HSI,	79999		@ 10 ms at 8 MHz, minus 1
	.equ	SYST_ON_NOINT,	5		@ CLKSOURCE processor clock | ENABLE, TICKINT 0
	.equ	SYST_COUNTFLAG,	0x10000
	.equ	XT_X,		16		@ left margin of the text
	.equ	XT_SECONDS,	20		@ the time the text stays (owner, 2026-11-21)
	.equ	XT_TICKS,	100		@ COUNTFLAG periods per second
	.equ	XT_NUM_W,	40		@ width of the cleared number area (two digits and " s")
	.equ	XT_LINE_H,	19		@ height of the cleared number area
	.equ	BL_FULL,	100		@ fn_08009e60(100): backlight pin high, no PWM

	.section .text.own.xtal,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ xtal_fault - entered by own_start (b), never returns. Rules in the file header.
@ ----------------------------------------------------------------------------
	.global	xtal_fault
	.thumb_func
	.type	xtal_fault, %function
xtal_fault:
	sub	sp, #8			@ number text: up to "20 s" and 0
	bl	fn_08009c14		@ LCD set up, screen black
	ldr	r4, =xt_lines
.Lxf_line:
	ldr	r2, [r4, #4]		@ text
	cmp	r2, #0
	beq	.Lxf_lines_done
	movs	r0, #XT_X
	ldrh	r1, [r4, #0]		@ line top
	ldrh	r3, [r4, #2]		@ shade table selector
	ldr	r5, =xt_shades
	add	r3, r5, r3, lsl #3	@ 8 bytes per table
	bl	text_draw
	adds	r4, r4, #8
	b	.Lxf_line
.Lxf_lines_done:
	mov	r6, r0			@ r6 = x after the last line ("Switching off in ")
	ldrh	r7, [r4, #0]		@ r7 = its line top (the end entry repeats it)
	movs	r0, #BL_FULL
	bl	fn_08009e60		@ backlight on
	ldr	r4, =SYST_CSR		@ SysTick: 10 ms periods, no interrupt
	movs	r0, #0
	str	r0, [r4]
	ldr	r0, =SYST_10MS_HSI
	str	r0, [r4, #4]
	movs	r0, #0
	str	r0, [r4, #8]
	movs	r0, #SYST_ON_NOINT
	str	r0, [r4]
	movs	r5, #XT_SECONDS		@ r5 = seconds left
.Lxf_second:
	add	r0, r6, #XT_NUM_W - 1	@ number area cleared
	add	r3, r7, #XT_LINE_H - 1
	mov	r2, r0
	mov	r0, r6
	mov	r1, r7
	bl	fn_08009e30		@ window (x0, y0, x1, y1), then RAMWR
	ldr	r0, =LCD_DATA
	movs	r1, #0
	movw	r2, #XT_NUM_W * XT_LINE_H
.Lxf_clear:
	strh	r1, [r0]
	subs	r2, r2, #1
	bne	.Lxf_clear
	mov	r2, sp			@ the number text: [tens] units ' ' 's' 0
	movs	r0, #10
	udiv	r1, r5, r0		@ tens
	mls	r0, r1, r0, r5		@ units
	cmp	r1, #0
	itt	ne
	addne	r1, r1, #'0'
	strbne	r1, [r2], #1
	adds	r0, r0, #'0'
	strb	r0, [r2], #1
	movs	r0, #' '
	strb	r0, [r2], #1
	movs	r0, #'s'
	strb	r0, [r2], #1
	movs	r0, #0
	strb	r0, [r2]
	mov	r0, r6
	mov	r1, r7
	mov	r2, sp
	ldr	r3, =xt_shades		@ white
	bl	text_draw
	movs	r8, #XT_TICKS
.Lxf_tick:
	ldr	r0, [r4]		@ the read clears COUNTFLAG
	tst	r0, #SYST_COUNTFLAG
	beq	.Lxf_tick
	bl	own_feed
	subs	r8, r8, #1
	bne	.Lxf_tick
	subs	r5, r5, #1
	bne	.Lxf_second
	bl	fn_0800b274		@ PA8 low (power latch released), backlight off
.Lxf_off:
	bl	own_feed		@ still powered (USB or the key held): stay dark
	b	.Lxf_off

@ ----------------------------------------------------------------------------
@ text_draw - one line of font F1; arguments and format in the file header.
@   Registers: r4 pen x, r5 line top, r6 text, r7 shade table, r8 font record, r9 glyph top
@   offset (line height - base line), r10 pixel index, r11 pixel count.
@ ----------------------------------------------------------------------------
	.global	text_draw
	.thumb_func
	.type	text_draw, %function
text_draw:
	push	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #4			@ 8-byte stack alignment for the calls
	mov	r4, r0
	mov	r5, r1
	mov	r6, r2
	mov	r7, r3
	ldr	r0, =d_0802ce5c		@ font F1
	ldrsh	r9, [r0, #8]		@ line height
	ldrsh	r1, [r0, #0xA]		@ base line
	sub	r9, r9, r1
	ldr	r8, [r0, #0x10]		@ font record
.Ltd_char:
	ldrb	r0, [r6], #1
	cmp	r0, #0
	beq	.Ltd_end
	bl	font_gid		@ r0 = glyph id, 0 = none
	cmp	r0, #0
	beq	.Ltd_char
	ldr	r1, [r8, #4]		@ glyph entries
	add	r1, r1, r0, lsl #3
	ldr	r0, [r1, #0]
	lsrs	r2, r0, #20		@ advance, 1/16 pixel
	adds	r2, r2, #8		@ rounded: (a + 8) >> 4 at .Ltd_advance
	str	r2, [sp]		@ kept for the end of the glyph
	ldrb	r2, [r1, #4]		@ box width
	ldrb	r3, [r1, #5]		@ box height
	cmp	r2, #0
	beq	.Ltd_advance
	cmp	r3, #0
	beq	.Ltd_advance
	mul	r11, r2, r3		@ pixel count
	ldr	r12, [r8, #0]		@ bitmap base
	ubfx	r0, r0, #0, #20		@ bitmap offset
	add	r10, r12, r0		@ r10 = bitmap of this glyph (pixel index later)
	ldrsb	r0, [r1, #6]		@ x offset
	add	r0, r0, r4		@ x0
	ldrsb	r12, [r1, #7]		@ y offset
	add	r1, r5, r9		@ line top + (line height - base line)
	sub	r1, r1, r3		@ - box height
	sub	r1, r1, r12		@ - y offset: y0
	add	r2, r0, r2		@ x1 = x0 + width - 1
	subs	r2, r2, #1
	add	r3, r1, r3		@ y1 = y0 + height - 1
	subs	r3, r3, #1
	bl	fn_08009e30		@ window, then RAMWR (keeps r4..r11)
	mov	r0, r10			@ r0 = bitmap
	ldr	r2, =LCD_DATA
	movs	r10, #0			@ pixel index
.Ltd_px:
	lsr	r12, r10, #2
	ldrb	r12, [r0, r12]		@ the byte of this pixel
	and	r1, r10, #3
	eor	r1, r1, #3
	lsls	r1, r1, #1		@ shift 6, 4, 2, 0: most significant bits first
	lsr	r12, r12, r1
	and	r12, r12, #3
	ldrh	r12, [r7, r12, lsl #1]	@ shade
	strh	r12, [r2]
	add	r10, r10, #1
	cmp	r10, r11
	blo	.Ltd_px
.Ltd_advance:
	ldr	r2, [sp]
	add	r4, r4, r2, lsr #4
	b	.Ltd_char
.Ltd_end:
	mov	r0, r4
	add	sp, #4
	pop	{r4, r5, r6, r7, r8, r9, r10, r11, pc}

@ ----------------------------------------------------------------------------
@ font_gid - r0 = character code, r8 = font record -> r0 = glyph id (0: no glyph).
@   Uses r1, r2, r3, r10, r12 (r10 is free in text_draw between glyphs). Rules (ranges, types 2
@   and 3) in the file header.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	font_gid, %function
font_gid:
	ldr	r1, [r8, #8]		@ ranges
	ldrh	r2, [r8, #0x12]
	ubfx	r2, r2, #0, #9		@ number of ranges
.Lfg_range:
	cmp	r2, #0
	beq	.Lfg_none
	ldr	r3, [r1, #0]		@ first code
	subs	r3, r0, r3		@ code - first
	blo	.Lfg_next		@ below the range
	ldrh	r12, [r1, #4]		@ length
	cmp	r3, r12
	bls	.Lfg_found		@ code - first <= length
.Lfg_next:
	adds	r1, r1, #20
	subs	r2, r2, #1
	b	.Lfg_range
.Lfg_found:
	ldrh	r12, [r1, #0x12]	@ type
	cmp	r12, #2
	beq	.Lfg_tiny
	cmp	r12, #3
	bne	.Lfg_none		@ types 0 / 1: not in F1
	ldr	r12, [r1, #8]		@ sorted list
	ldrh	r2, [r1, #0x10]		@ its count
	movs	r0, #0			@ index
.Lfg_search:
	cmp	r0, r2
	bhs	.Lfg_none
	ldrh	r10, [r12, r0, lsl #1]
	cmp	r10, r3
	beq	.Lfg_hit
	adds	r0, r0, #1
	b	.Lfg_search
.Lfg_hit:
	ldrh	r1, [r1, #6]		@ glyph id base
	add	r0, r0, r1
	bx	lr
.Lfg_tiny:
	ldrh	r1, [r1, #6]
	add	r0, r3, r1
	bx	lr
.Lfg_none:
	movs	r0, #0
	bx	lr

	.ltorg

	.section .rodata.own.xtal,"a",%progbits
	.p2align 2

@ lines: top (u16), shade table (u16: 0 white, 1 red), text; the end entry: top of the
@ countdown line (its "Switching off in " is the last text), text 0
xt_lines:
	.hword	6, 1
	.word	xt_t0
	.hword	44, 0
	.word	xt_t1
	.hword	63, 0
	.word	xt_t2
	.hword	82, 0
	.word	xt_t3
	.hword	101, 0
	.word	xt_t4
	.hword	139, 0
	.word	xt_t5
	.hword	158, 0
	.word	xt_t6
	.hword	177, 0
	.word	xt_t7
	.hword	215, 0
	.word	xt_t8
	.hword	215, 0
	.word	0

@ shades of the 2-bit pixel values on black (RGB565): white 0, 1/3, 2/3, 1; red the same
xt_shades:
	.hword	0x0000, 0x52AA, 0xA554, 0xFFFF
	.hword	0x0000, 0x5000, 0xA000, 0xF800

xt_t0:	.asciz	"CRYSTAL FAULT"
xt_t1:	.asciz	"The 8 MHz crystal of the"
xt_t2:	.asciz	"microcontroller does not start."
xt_t3:	.asciz	"Without it the meter cannot"
xt_t4:	.asciz	"measure or use USB."
xt_t5:	.asciz	"Repair: resolder or replace the"
xt_t6:	.asciz	"8 MHz crystal on pins PD0 and"
xt_t7:	.asciz	"PD1 of the microcontroller."
xt_t8:	.asciz	"Switching off in "
