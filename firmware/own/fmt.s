@ fmt.s - the measured-value formatters of our build (MEASUREMENT_FIX_DESIGN.md stage 2: S2.1 OL
@ and the specified range, S2.2 signs, S2.4 digits).
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ The seven measured-value formatter calls of the two display rows (src/ui_41.s, .ifdef OWN:
@ 0x0800D2E4 secondary R, 0x0800D32A X, 0x0800D356 D / Q, 0x0800D378 theta, 0x0800D43C R or |Z|,
@ 0x0800D452 C, 0x0800D48C L) and the host's table fmt_fn (own/cmd.s) call the wrappers here; the
@ two row draws (0x0800D380 row 1, 0x0800D4B8 row 0) call own_row_draw. Each wrapper has the
@ vendor formatter's interface: s0 = value, r0 = text buffer (8 bytes), r1 = unit text buffer, r2 =
@ address of the unit index word; it writes the same three outputs:
@ - R, |Z|, X (ohm), C (nF) and L (uH):
@   - OL (the vendor's text "0L  ", unit text empty, index 0) when the value is not finite or its
@     magnitude lies above the manual's measurement range (UM 1543: R 0..10 Mohm, C 0..100 mF,
@     L 0..100 H; |Z| and X by the R row, design S2.1 "The other quantities");
@   - else the vendor formatter (0x0800E028 ohm, 0x0800DB24 C, 0x0800DE2C L) on the magnitude, one
@     decimal less where its text would exceed 19,999 counts (S2.4, D5), and a '-' in front for a
@     negative value (S2.2: R, L and C signed; X too, which the vendor formats signed itself only
@     with 0x20001198 = 2, so X is signed once); a text of more than 7 characters with its sign is
@     OL (never reached by the vendor formats: at most 6 characters);
@   - MF_MARK = 1 when the magnitude lies outside the accuracy table of the manual for the
@     frequency now (UM 1596-1646 as read in design S2.1; 120 Hz in the 100 Hz column; 60 Hz has no
@     column: always marked), else 0 (design D6: the value is shown, with a marker);
@ - D, Q (0x0800DD44) and theta (0x0800DFC4): the vendor formatter on the value, the S2.4 decimal
@   rule, MF_MARK = 0 (no table entry, design S2.1).
@ own_row_draw draws the row's text with the vendor's fn_0800d14c and then colours the row's seven
@ glyph objects (0x200059A8 + 32 row + 4 i, i = 0..6; ui_41.s 1111, 274) with the image recolour
@ style keys the vendor uses for its own highlight in the settings dialog (ui_43.s 1114-1170: key
@ 0x47 = colour through fn_080265dc, rgb_to_565_0801d792(0xFD, 0xD0, 0x1B); key 0x48 = 0xFF on,
@ 0 off through fn_080265f4, both found and replaced in place by fn_08027294) when MF_MARK is 1,
@ and switches the colour off again (key 0x48 = 0) on the objects it coloured.
@
@ RAM: only MF_MARK, MF_ROW0, MF_ROW1 (OWN_FUNC, own.inc). Never-brick: no flash, no save.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

	.equ	K_R,		0		@ kinds: ohm (R, |Z|, X)
	.equ	K_C,		1		@ capacitance, nF
	.equ	K_L,		2		@ inductance, uH
	.equ	K_DQ,		3		@ D, Q
	.equ	K_TH,		4		@ theta, degrees
	.equ	EXP_MASK,	0x7F800000	@ exponent field: all ones = Inf or NaN
	.equ	GLYPHS,		0x200059A8	@ 2 rows x 8 glyph objects (ui_41.s 274)
	.equ	MAX_COUNT,	19999		@ D5: 4 1/2 digits

	.section .text.own.fmt,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ own_fmt_r - ohm: R, |Z| or X in s0 (signed). own_fmt_rs - the secondary R: the value from
@   0x200050B8 (the caller at 0x0800D2E4 made s0 absolute, ui_41.s 1350-1352; S2.2 takes the
@   signed word). own_fmt_c - C in nF. own_fmt_l - L in uH. own_fmt_dq - D or Q. own_fmt_th -
@   theta. All: r0 = text, r1 = unit text, r2 = index word address (the vendor interface).
@   AAPCS: r0..r3, r12, s0..s15 changed.
@ ----------------------------------------------------------------------------
	.global	own_fmt_rs
	.thumb_func
	.type	own_fmt_rs, %function
own_fmt_rs:
	ldr	r3, =V_R
	vldr	s0, [r3]		@ the signed R (series or parallel by 0x200011EC)
	.global	own_fmt_r
	.thumb_func
	.type	own_fmt_r, %function
own_fmt_r:
	movs	r3, #K_R
	b	fmt_core

	.global	own_fmt_c
	.thumb_func
	.type	own_fmt_c, %function
own_fmt_c:
	movs	r3, #K_C
	b	fmt_core

	.global	own_fmt_l
	.thumb_func
	.type	own_fmt_l, %function
own_fmt_l:
	movs	r3, #K_L
	b	fmt_core

	.global	own_fmt_dq
	.thumb_func
	.type	own_fmt_dq, %function
own_fmt_dq:
	movs	r3, #K_DQ
	b	fmt_core

	.global	own_fmt_th
	.thumb_func
	.type	own_fmt_th, %function
own_fmt_th:
	movs	r3, #K_TH
	b	fmt_core

@ ----------------------------------------------------------------------------
@ fmt_core - the wrappers' work (file header): s0 = value, r0 = text, r1 = unit text, r2 = index
@   word address, r3 = kind K_*. Register use: r4 text, r5 unit, r6 index address, r7 kind,
@   r8 OWN_FUNC, r9 marker; s16 the value, s17 its magnitude.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	fmt_core, %function
fmt_core:
	push	{r4, r5, r6, r7, r8, r9, r10, lr}
	vpush	{d8, d9}		@ 48 bytes: the stack stays 8-aligned for fn_08010370
	mov	r4, r0
	mov	r5, r1
	mov	r6, r2
	mov	r7, r3
	ldr	r8, =OWN_FUNC
	movs	r9, #0			@ r9 = marker
	str	r9, [r8, #MF_MARK]
	vmov.f32	s16, s0
	vabs.f32	s17, s0
	cmp	r7, #K_L
	bhi	.Lfc_plain		@ D, Q, theta: the vendor formatter as it is
	vmov	r0, s16
	and	r0, r0, #EXP_MASK
	cmp	r0, #EXP_MASK
	beq	.Lfc_ol			@ Inf or NaN: OL
	ldr	r1, =fmt_hard
	add	r1, r1, r7, lsl #2
	vldr	s1, [r1]
	vcmpe.f32	s17, s1
	vmrs	APSR_nzcv, fpscr
	bgt	.Lfc_ol			@ above the measurement range: OL
	bl	fmt_column		@ r0 = column 0..3 of the frequency now, or -1
	movs	r9, #1			@ no column (60 Hz): marked
	cmp	r0, #0
	blt	.Lfc_vendor
	ldr	r1, =fmt_spec
	add	r0, r0, r7, lsl #2	@ entry = 4 kind + column
	add	r1, r1, r0, lsl #3	@ 8 bytes per entry: lower, upper
	vldr	s1, [r1]
	vldr	s2, [r1, #4]
	vcmpe.f32	s17, s1
	vmrs	APSR_nzcv, fpscr
	blt	.Lfc_vendor		@ below the specified range: marked
	vcmpe.f32	s17, s2
	vmrs	APSR_nzcv, fpscr
	bgt	.Lfc_vendor		@ above it: marked
	movs	r9, #0			@ inside the accuracy table
.Lfc_vendor:
	vmov.f32	s0, s17		@ the vendor formatter gets the magnitude
	b	.Lfc_call
.Lfc_plain:
	vmov.f32	s0, s16
.Lfc_call:
	ldr	r3, =fmt_vendor
	ldr	r3, [r3, r7, lsl #2]
	mov	r0, r4
	mov	r1, r5
	mov	r2, r6
	blx	r3
	ldrb	r0, [r4, #0]
	cmp	r0, #'0'
	bne	.Lfc_digits
	ldrb	r0, [r4, #1]
	cmp	r0, #'L'
	beq	.Lfc_out_nomark		@ the vendor's own OL (D / Q at 1e5, theta at 360)
.Lfc_digits:
	bl	fmt_reduce		@ S2.4
	cmp	r7, #K_L
	bhi	.Lfc_mark		@ D, Q, theta: no sign of ours (theta keeps the vendor's)
	vcmpe.f32	s16, #0
	vmrs	APSR_nzcv, fpscr
	bge	.Lfc_mark		@ not negative: no sign
	mov	r0, r4
	bl	fmt_len			@ r0 = length
	cmp	r0, #7
	bhs	.Lfc_ol			@ no room for the sign in 7 characters: OL
	add	r1, r4, r0		@ r1 = the terminating 0
.Lfc_shift:
	ldrb	r2, [r1]
	strb	r2, [r1, #1]		@ one place right, the 0 first
	cmp	r1, r4
	beq	.Lfc_sign
	subs	r1, r1, #1
	b	.Lfc_shift
.Lfc_sign:
	movs	r0, #'-'
	strb	r0, [r4]
.Lfc_mark:
	str	r9, [r8, #MF_MARK]
	b	.Lfc_ret
.Lfc_ol:
	ldr	r0, =0x20204C30		@ "0L  "
	str	r0, [r4]
	movs	r0, #0
	strb	r0, [r4, #4]
	strb	r0, [r5]		@ unit text empty
	str	r0, [r6]		@ index 0 (the callers hide the unit picture)
.Lfc_out_nomark:
	movs	r0, #0
	str	r0, [r8, #MF_MARK]
.Lfc_ret:
	vpop	{d8, d9}
	pop	{r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ fmt_column - r0 = the accuracy-table column of the frequency word 0x20001144: 0 for 100 and
@   120 Hz, 1 for 1 kHz, 2 for 10 kHz, 3 for 100 kHz, -1 for any other (60 Hz). Changes r1..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	fmt_column, %function
fmt_column:
	ldr	r1, =V_FREQ
	ldr	r1, [r1]
	ldr	r2, =fmt_freqs
	movs	r0, #0
.Lcl_next:
	ldr	r3, [r2, r0, lsl #2]
	cmp	r3, r1
	beq	.Lcl_found
	adds	r0, r0, #1
	cmp	r0, #5
	blo	.Lcl_next
	mov	r0, #-1
	bx	lr
.Lcl_found:
	ldr	r2, =fmt_cols
	ldrb	r0, [r2, r0]
	bx	lr

@ ----------------------------------------------------------------------------
@ fmt_len - r0 = the length of the 0-terminated text at r0. Changes r1, r2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	fmt_len, %function
fmt_len:
	mov	r1, r0
.Lln_next:
	ldrb	r2, [r1], #1
	cmp	r2, #0
	bne	.Lln_next
	subs	r0, r1, r0
	subs	r0, r0, #1
	bx	lr

@ ----------------------------------------------------------------------------
@ fmt_reduce - S2.4 on the text at r4 (fmt_core's registers: r6 index address, r7 kind, s16 / s17
@   value / magnitude): N = the digits of the text read as one integer, d = the digits after its
@   point. N > 19,999 and d > 0: the text is printed again with d - 1 decimals from the value in
@   the unit the vendor formatter chose (its index word: fmt_scale; the magnitude for R, C, L, the
@   value for D, Q, theta), by fn_08010370 as the vendor formatters print. An index without an
@   entry (0xFF) leaves the text. Changes r0..r3, r10, r12, s0..s2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	fmt_reduce, %function
fmt_reduce:
	push	{r3, lr}		@ 8 bytes: the stack stays 8-aligned
	movs	r0, #0			@ r0 = N
	movs	r1, #0			@ r1 = decimals
	movs	r2, #0			@ r2 = 1 after the point
	mov	r12, r4
.Lrd_ch:
	ldrb	r3, [r12], #1
	cbz	r3, .Lrd_end
	cmp	r3, #'.'
	bne	.Lrd_dig
	movs	r2, #1
	b	.Lrd_ch
.Lrd_dig:
	subs	r3, r3, #'0'
	cmp	r3, #9
	bhi	.Lrd_ch			@ '-' or another character: not a digit
	movs	r10, #10
	mla	r0, r0, r10, r3		@ N = 10 N + digit
	adds	r1, r1, r2
	b	.Lrd_ch
.Lrd_end:
	movw	r3, #MAX_COUNT
	cmp	r0, r3
	bls	.Lrd_ret		@ 19,999 counts or less: kept
	cmp	r1, #0
	beq	.Lrd_ret		@ no decimal left to drop
	cmp	r1, #4
	bhi	.Lrd_ret		@ more than the vendor's 4 decimals: not a vendor text
	ldr	r0, [r6]		@ the unit index the formatter stored
	cmp	r0, #7
	bhi	.Lrd_ret
	ldr	r2, =fmt_scale
	add	r2, r2, r7, lsl #3	@ 8 entries per kind
	ldrb	r0, [r2, r0]		@ r0 = scale code
	cmp	r0, #3
	bhi	.Lrd_ret		@ no entry
	vmov.f32	s0, s17		@ R, C, L: the magnitude
	cmp	r7, #K_L
	bls	.Lrd_scale
	vmov.f32	s0, s16		@ D, Q, theta: the value
.Lrd_scale:
	ldr	r2, =fmt_kilo
	vldr	s1, [r2]		@ 1000
	vldr	s2, [r2, #4]		@ 1e6
	cmp	r0, #1
	bne	.Lrd_s2
	vdiv.f32	s0, s0, s1	@ / 1000 (kohm, uF, mH)
	b	.Lrd_print
.Lrd_s2:
	cmp	r0, #2
	bne	.Lrd_s3
	vdiv.f32	s0, s0, s2	@ / 1e6 (Mohm, mF, H)
	b	.Lrd_print
.Lrd_s3:
	cmp	r0, #3
	bne	.Lrd_print		@ code 0: the base unit
	vmul.f32	s0, s0, s1	@ * 1000 (pF)
.Lrd_print:
	subs	r1, r1, #1		@ one decimal less
	ldr	r2, =fmt_formats
	add	r10, r2, r1, lsl #3	@ r10 = "%0.<d-1>f"
	vmov	r0, s0
	bl	float_to_double
	mov	r2, r0
	mov	r3, r1			@ r2:r3 = the double (as the vendor formatters pass it)
	mov	r1, r10
	mov	r0, r4
	bl	fn_08010370
.Lrd_ret:
	pop	{r3, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ own_row_draw - replaces bl fn_0800d14c at 0x0800D380 (row 1) and 0x0800D4B8 (row 0):
@   r0 = row 0 / 1, r1 = text. fn_0800d14c(row, text), then by MF_MARK (the formatter of this
@   row ran just before, in fn_0800d3d8 / fn_0800d294): 1 - every non-zero glyph object of the
@   row gets image recolour colour amber and opacity 0xFF, and MF_ROW<row> = its object 0;
@   0 - when MF_ROW<row> is the row's object 0 now (coloured by us), opacity 0 on every glyph and
@   MF_ROW<row> = 0. MF_MARK is cleared after it is read (a row without a formatter call, the
@   vendor's default case, is then never marked by a stale value). AAPCS.
@ ----------------------------------------------------------------------------
	.global	own_row_draw
	.thumb_func
	.type	own_row_draw, %function
own_row_draw:
	push	{r3, r4, r5, r6, r7, r8, r9, lr}	@ 32 bytes (8-aligned)
	mov	r4, r0			@ r4 = row
	bl	fn_0800d14c
	ldr	r5, =OWN_FUNC
	ldr	r6, [r5, #MF_MARK]	@ r6 = marker of this row's value
	movs	r0, #0
	str	r0, [r5, #MF_MARK]
	ldr	r7, =GLYPHS
	add	r7, r7, r4, lsl #5	@ r7 = the row's 8 object words
	add	r5, r5, r4, lsl #2	@ r5 + MF_ROW0 = this row's word
	ldr	r8, [r7]		@ r8 = object 0 now
	cmp	r6, #0
	beq	.Lrw_clear
	movs	r2, #0x1B
	movs	r1, #0xD0
	movs	r0, #0xFD
	bl	rgb_to_565_0801d792	@ the vendor's highlight colour (ui_43.s 1146-1149)
	mov	r6, r0			@ r6 = RGB565
	movs	r4, #0
.Lrw_on:
	ldr	r0, [r7, r4, lsl #2]
	cbz	r0, .Lrw_on_next
	mov	r1, r6
	movs	r2, #0
	bl	fn_080265dc		@ key 0x47: the recolour colour
	ldr	r0, [r7, r4, lsl #2]
	movs	r1, #0xFF
	movs	r2, #0
	bl	fn_080265f4		@ key 0x48: recolour on
.Lrw_on_next:
	adds	r4, r4, #1
	cmp	r4, #7
	blo	.Lrw_on
	str	r8, [r5, #MF_ROW0]
	b	.Lrw_ret
.Lrw_clear:
	ldr	r0, [r5, #MF_ROW0]
	cmp	r0, #0
	beq	.Lrw_ret		@ nothing of ours on this row
	cmp	r0, r8
	bne	.Lrw_forget		@ another object now (the screen was built again)
	movs	r4, #0
.Lrw_off:
	ldr	r0, [r7, r4, lsl #2]
	cbz	r0, .Lrw_off_next
	movs	r1, #0
	movs	r2, #0
	bl	fn_080265f4		@ key 0x48: recolour off
.Lrw_off_next:
	adds	r4, r4, #1
	cmp	r4, #7
	blo	.Lrw_off
.Lrw_forget:
	movs	r0, #0
	str	r0, [r5, #MF_ROW0]
.Lrw_ret:
	pop	{r3, r4, r5, r6, r7, r8, r9, pc}

	.ltorg

@ ============================================================================
@ Tables
@ ============================================================================
	.section .rodata.own.fmt,"a",%progbits
	.p2align 2

@ the vendor formatters by kind
fmt_vendor:
	.word	fn_0800e028, fn_0800db24, fn_0800de2c, fn_0800dd44, fn_0800dfc4

@ upper end of the measurement range by kind R, C, L (UM 1543): 1e7 ohm, 1e8 nF, 1e8 uH; also
@ read by cmp.s own_cmp_judge (compare quantity 1 R, 2 C, 3 L)
	.global	fmt_hard
fmt_hard:
	.word	0x4B189680, 0x4CBEBC20, 0x4CBEBC20

@ the accuracy table (design S2.1, from UM 1596-1646): {lower, upper} per kind and column
@ (columns 100 / 1k / 10k / 100k Hz; units ohm, nF, uH)
fmt_spec:
	.word	0x3C23D70A, 0x4B189680		@ R  100 Hz: 10 mohm .. 10 Mohm
	.word	0x3C23D70A, 0x4B189680		@ R  1 kHz:  10 mohm .. 10 Mohm
	.word	0x3C23D70A, 0x49742400		@ R  10 kHz: 10 mohm .. 1 Mohm
	.word	0x3C23D70A, 0x49742400		@ R  100 kHz: 10 mohm .. 1 Mohm
	.word	0x447A0000, 0x4CBEBC20		@ C  100 Hz: 1 uF .. 100 mF
	.word	0x3A83126F, 0x4CBEBC20		@ C  1 kHz:  1 pF .. 100 mF
	.word	0x3A83126F, 0x49742400		@ C  10 kHz: 1 pF .. 1 mF
	.word	0x3A83126F, 0x49742400		@ C  100 kHz: 1 pF .. 1 mF
	.word	0x41200000, 0x4CBEBC20		@ L  100 Hz: 10 uH .. 100 H
	.word	0x3F800000, 0x4CBEBC20		@ L  1 kHz:  1 uH .. 100 H
	.word	0x3F800000, 0x49742400		@ L  10 kHz: 1 uH .. 1 H
	.word	0x3F800000, 0x49742400		@ L  100 kHz: 1 uH .. 1 H

@ the five vendor frequencies and their accuracy-table columns (120 Hz: the 100 Hz column)
fmt_freqs:
	.word	100, 120, 1000, 10000, 100000
fmt_cols:
	.byte	0, 0, 1, 2, 3
	.p2align 2

@ scale code of the value in the unit of each vendor unit index (fmt_reduce), 8 per kind:
@ 0 base unit, 1 / 1000, 2 / 1e6, 3 * 1000, 0xFF no such index (the indices of the ui_42.s
@ headers: ohm 5 / 6 / 7; C 1 pF, 2 nF, 3 uF, 4 mF; L 3 uH, 4 mH, 5 H; D / Q and theta store 0
@ and 1)
fmt_scale:
	.byte	0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 1, 2		@ ohm
	.byte	0xFF, 3, 0, 1, 2, 0xFF, 0xFF, 0xFF		@ C
	.byte	0xFF, 0xFF, 0xFF, 0, 1, 2, 0xFF, 0xFF		@ L
	.byte	0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF	@ D / Q
	.byte	0, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF	@ theta

@ 1000 and 1e6 (the vendor formatters' divisors, ui_42.s headers)
fmt_kilo:
	.word	0x447A0000, 0x49742400

@ the formats of 0 .. 3 decimals, 8 bytes each
fmt_formats:
	.asciz	"%0.0f"
	.byte	0, 0
	.asciz	"%0.1f"
	.byte	0, 0
	.asciz	"%0.2f"
	.byte	0, 0
	.asciz	"%0.3f"
	.byte	0, 0
