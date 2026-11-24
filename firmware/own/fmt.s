@ fmt.s - the measured-value formatters of our build (MEASUREMENT_FIX_DESIGN.md stage 2: S2.1 OL
@ and the specified range, S2.2 signs, S2.4 digits).
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ The seven measured-value formatter calls of the two display rows (src/ui_41.s, .ifdef OWN:
@ 0x0800D2E4 secondary R, 0x0800D32A X, 0x0800D356 D / Q, 0x0800D378 theta, 0x0800D43C R or |Z|,
@ 0x0800D452 C, 0x0800D48C L) and the host's table fmt_fn (own/cmd.s) call the wrappers here; the
@ two row draws (0x0800D380 row 1, 0x0800D4B8 row 0) call own_row_draw. Each wrapper has the
@ vendor formatter's interface: s0 = value, r0 = text buffer (8 bytes), r1 = unit text buffer, r2 =
@ address of the unit index word; it writes the same three outputs. The two shared calls get the
@ address of their value word in r3 instead of s0, set by the case that chose it (own_fmt_rz: |Z|
@ 0x200050C4 or R 0x200050B8; own_fmt_dqs: D 0x200050D4 or Q 0x200050D0; the `addw` of ui_41.s),
@ so the quantity is told by the call site, not by a RAM word. The outputs:
@ - every wrapper: OL (the vendor's text "0L  ", unit text empty, index 0, MF_MARK 0) at the test
@   frequencies 60, 100 and 120 Hz when the published |Z| 0x200050C4 lies above 1e7 ohm, the
@   highest impedance the manual specifies in its 100 Hz column (design revision 14 rule 2,
@   fmt_lowz);
@ - R, |Z|, X (ohm), C (nF) and L (uH):
@   - OL when the value is not finite or its magnitude lies above the manual's measurement range
@     (UM 1543: R 0..10 Mohm, C 0..100 mF, L 0..100 H; |Z| and X by the R row, design S2.1 "The
@     other quantities");
@   - a finite negative value by its quantity (revision 14 rule 1, owner 2026-11-24; it corrects
@     revision 13, which showed every negative as 0): the true value lies at one end of its range.
@     Quantities proportional to a near-zero component, series R (Rs = Re Z), parallel C (Cp = Im
@     Y / w), series L (Ls = Xs / w): 0, the vendor formatter's own text of 0 ("0.0000" ohm, index
@     5; "0.0" pF, index 1; "0.0" uH, index 3), marked (0 lies below every lower limit of the
@     accuracy table). Reciprocals of a near-zero component, parallel R (Rp = 1 / Re Y), series C
@     (Cs = -1 / (w Xs)), parallel L (Lp = -1 / (w Bp)): OL. Series or parallel is the word
@     0x200011EC (0 / 1), which meas_publish writes in the same block as R, C and L (its only
@     writer besides the start-up zero fill; design revision 14.1). |Z| (own_fmt_z) takes 0 and is
@     never negative (revision 10). X (own_fmt_x) keeps its sign;
@   - else the vendor formatter (0x0800E028 ohm, 0x0800DB24 C, 0x0800DE2C L) on the magnitude, one
@     decimal less where its text would exceed 19,999 counts (S2.4, D5; C 2000.0 .. 7999.9 uF
@     goes to mF with 3 decimals instead, fmt_reduce), and a '-' in front for a negative X (S2.2;
@     X, which the vendor formats signed itself only with 0x20001198 = 2, is signed once, as the
@     vendor gets the magnitude); a text of more than 7 characters with its sign is OL (never
@     reached by the vendor formats: at most 6 characters);
@   - MF_MARK = 1 when the magnitude lies outside the accuracy table of the manual for the
@     frequency now (UM 1596-1646 as read in design S2.1; 120 Hz in the 100 Hz column; 60 Hz has no
@     column: always marked), else 0 (design D6: the value is shown, with a marker);
@ - D, Q (0x0800DD44) and theta (0x0800DFC4): the vendor formatter on the value, the S2.4 decimal
@   rule, MF_MARK = 0 (no table entry, design S2.1); a D below 0 is given to it as +0 ("0.0000",
@   "%0.4f" below 10), a Q below 0 is OL (revision 14 rule 1; meas_publish stores both as
@   magnitudes, so neither is negative there today); theta keeps its sign. Beside a main row C or L
@   whose text is 0 ("0.0" pF / uH, fmt_dq), D is OL and Q is "0.0000" (revision 15).
@ own_row_draw draws the row's text with the vendor's fn_0800d14c and then, when MF_MARK is 1, puts
@ an amber multiply cover over each of the row's seven glyph objects (0x200059A8 + 32 row + 4 i,
@ i = 0..6; ui_41.s 1111, 274), so the digits are drawn amber with their shapes; an unmarked row
@ hides the covers again (own_row_draw below: why the image recolour cannot do it).
@
@ RAM: only MF_MARK, MF_ROW0, MF_ROW1 (OWN_FUNC, own.inc) written; read: 0x20001144 (frequency),
@ 0x200050C4 (|Z|), 0x200011EC (series / parallel), 0x200050B8 (R, own_fmt_rs), 0x200011E4 (main
@ row) and 0x200050BC / 0x200050C0 (C, L; fmt_dq); the covers are GUI
@ objects on the GUI heap. Never-brick: no flash, no save.

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
	.equ	K_MASK,		7		@ the kind bits of fmt_core's r3
	.equ	F_ZERO,		8		@ r3 flag: a finite negative value is shown as 0
	.equ	F_OL,		16		@ r3 flag: a finite negative value is shown as OL
	.equ	F_NEG,		F_ZERO + F_OL	@ the two rules for a negative value
	.equ	F_SP,		32		@ r3 flag: F_ZERO / F_OL is the series rule; swapped when
						@ 0x200011EC is not 0 (parallel values in use)
	.equ	EXP_MASK,	0x7F800000	@ exponent field: all ones = Inf or NaN
	.equ	GLYPHS,		0x200059A8	@ 2 rows x 8 glyph objects (ui_41.s 274)
	.equ	MAX_COUNT,	19999		@ D5: 4 1/2 digits

	.section .text.own.fmt,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ The wrappers (file header; design revision 14.2). All: r0 = text, r1 = unit text, r2 = index
@   word address (the vendor interface); s0 = the value, except own_fmt_rz / own_fmt_dqs (r3 =
@   the address of the value word) and own_fmt_rs (0x200050B8). AAPCS: r0..r3, r12, s0..s15
@   changed.
@   own_fmt_rz - 0x0800D43C, the call row 0's cases 4 and 1 share (fn_0800d3d8): r3 = 0x200050C4
@     (|Z|, `addw` at 0x0800D406) or 0x200050B8 (R, `addw` at 0x0800D432): s0 = the word, then
@     own_fmt_z for 0x200050C4, else own_fmt_r.
@   own_fmt_rs - 0x0800D2E4, the secondary R: s0 = 0x200050B8 (the caller made s0 absolute,
@     ui_41.s 1350-1352; S2.2 takes the signed word), then own_fmt_r.
@   own_fmt_r - R in ohm (main row by own_fmt_rz, secondary, fmt_fn FK_OHM): a finite negative
@     value 0 in series, OL in parallel (0x200011EC).
@   own_fmt_z - |Z| in ohm (own_fmt_rz, fmt_fn FK_Z): a finite negative value 0 (never negative
@     on screens 1 and 2, revision 10).
@   own_fmt_x - X in ohm, signed (called only at 0x0800D32A, case 1 of 0x200011E8 with s0 =
@     0x200050C8, and by fmt_fn's FK_OHM_X, own/cmd.s).
@   own_fmt_c - C in nF: a finite negative value OL in series (Cs), 0 in parallel (Cp).
@   own_fmt_l - L in uH: a finite negative value 0 in series (Ls), OL in parallel (Lp).
@   own_fmt_dqs - 0x0800D356, the call row 1's cases 2 and 3 share (fn_0800d294): r3 = 0x200050D4
@     (D, `addw` at 0x0800D340) or 0x200050D0 (Q, `addw` at 0x0800D34C): s0 = the word, then
@     own_fmt_d for 0x200050D4, else own_fmt_q.
@   own_fmt_d - D: a negative value 0. own_fmt_q - Q: a negative value OL. Both through fmt_dq:
@     beside a main row C or L shown as 0, D OL and Q 0. own_fmt_th - theta, signed.
@ ----------------------------------------------------------------------------
	.global	own_fmt_rz
	.thumb_func
	.type	own_fmt_rz, %function
own_fmt_rz:
	vldr	s0, [r3]		@ the word the case chose
	ldr	r12, =V_Z
	cmp	r3, r12
	beq	own_fmt_z		@ case 4: |Z|
	b	own_fmt_r		@ case 1: R

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
	movs	r3, #K_R + F_ZERO + F_SP	@ Rs below 0: 0; Rp below 0: OL
	b	fmt_core

	.global	own_fmt_z
	.thumb_func
	.type	own_fmt_z, %function
own_fmt_z:
	movs	r3, #K_R + F_ZERO	@ |Z|: a negative shown as 0
	b	fmt_core

	.global	own_fmt_x
	.thumb_func
	.type	own_fmt_x, %function
own_fmt_x:
	movs	r3, #K_R		@ X: ohm, the sign kept
	b	fmt_core

	.global	own_fmt_c
	.thumb_func
	.type	own_fmt_c, %function
own_fmt_c:
	movs	r3, #K_C + F_OL + F_SP	@ Cs below 0: OL; Cp below 0: 0
	b	fmt_core

	.global	own_fmt_l
	.thumb_func
	.type	own_fmt_l, %function
own_fmt_l:
	movs	r3, #K_L + F_ZERO + F_SP	@ Ls below 0: 0; Lp below 0: OL
	b	fmt_core

	.global	own_fmt_dqs
	.thumb_func
	.type	own_fmt_dqs, %function
own_fmt_dqs:
	vldr	s0, [r3]		@ the word the case chose
	ldr	r12, =V_D
	cmp	r3, r12
	bne	own_fmt_q		@ case 3: Q
	.global	own_fmt_d		@ case 2: D
	.thumb_func
	.type	own_fmt_d, %function
own_fmt_d:
	movs	r3, #K_DQ + F_ZERO	@ D below 0: 0
	b	fmt_dq

	.global	own_fmt_q
	.thumb_func
	.type	own_fmt_q, %function
own_fmt_q:
	movs	r3, #K_DQ + F_OL	@ Q below 0: OL
					@ fall through to fmt_dq

@ ----------------------------------------------------------------------------
@ fmt_dq - D and Q beside a C or L shown as 0 (revision 15, owner 2026-11-24): own_fmt_d /
@   own_fmt_q's registers (s0 = D or Q, r0..r2 the vendor interface, r3 = K_DQ and its rule).
@   When the main row (byte 0x200011E4, fn_0800d3d8's case: 2 C, 3 L) is C or L, that value
@   (0x200050BC / 0x200050C0) is formatted by own_fmt_c / own_fmt_l into buffers on the stack;
@   when its text is a '0' followed only by '0' and '.' (the value shown as 0: a negative one by
@   the revision 14 rule, or one below the last place), D is given as +Inf and Q as 0, the limits
@   of D = 1 / Q as C or L goes to 0: the vendor's D / Q formatter 0x0800DD44 makes OL of +Inf
@   (bits 0x7F800000 >= 0x47C35000, "0L  ") and "0.0000" of 0. Otherwise D or Q as published.
@   Then fmt_core. The inner own_fmt_c / own_fmt_l call writes MF_MARK, which fmt_core writes
@   again. Stack: 24 bytes pushed + 24 bytes of buffers (text 8 at sp, unit 8 at sp + 8, index
@   word at sp + 16, the D / Q value at sp + 20), 8-aligned for fn_08010370.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	fmt_dq, %function
fmt_dq:
	push	{r0, r1, r2, r3, r4, lr}
	sub	sp, sp, #24
	vstr	s0, [sp, #20]		@ D or Q as published
	ldr	r0, =V_MAIN_ROW
	ldrsb	r4, [r0]
	cmp	r4, #2
	beq	.Ldq_c
	cmp	r4, #3
	bne	.Ldq_own		@ main row R or |Z|: D, Q as published
	ldr	r0, =V_L
	vldr	s0, [r0]
	mov	r0, sp
	add	r1, sp, #8
	add	r2, sp, #16
	bl	own_fmt_l		@ L as the main row shows it
	b	.Ldq_test
.Ldq_c:
	ldr	r0, =V_C
	vldr	s0, [r0]
	mov	r0, sp
	add	r1, sp, #8
	add	r2, sp, #16
	bl	own_fmt_c		@ C as the main row shows it
.Ldq_test:
	mov	r0, sp
	ldrb	r1, [r0], #1
	cmp	r1, #'0'
	bne	.Ldq_own		@ a digit 1..9 first (or a '-'): not 0
.Ldq_ch:
	ldrb	r1, [r0], #1
	cbz	r1, .Ldq_zero		@ the end: only '0' and '.' met
	cmp	r1, #'0'
	beq	.Ldq_ch
	cmp	r1, #'.'
	beq	.Ldq_ch
	b	.Ldq_own		@ another digit, or 'L' (OL): not 0
.Ldq_zero:
	ldr	r3, [sp, #36]		@ the pushed r3: K_DQ and its rule
	movs	r0, #0
	vmov	s0, r0			@ Q of a C or L shown as 0: 0
	tst	r3, #F_OL
	bne	.Ldq_go			@ Q (own_fmt_q's F_OL)
	mov	r0, #EXP_MASK
	vmov	s0, r0			@ D: +Inf, the vendor's OL
	b	.Ldq_go
.Ldq_own:
	vldr	s0, [sp, #20]		@ D or Q as published
.Ldq_go:
	add	sp, sp, #24
	pop	{r0, r1, r2, r3, r4, lr}
	b	fmt_core

	.global	own_fmt_th
	.thumb_func
	.type	own_fmt_th, %function
own_fmt_th:
	movs	r3, #K_TH
	b	fmt_core

@ ----------------------------------------------------------------------------
@ fmt_core - the wrappers' work (file header): s0 = value, r0 = text, r1 = unit text, r2 = index
@   word address, r3 = kind K_* plus the rule for a negative value, F_ZERO (0) or F_OL (OL) or
@   none (X, theta), plus F_SP for R, C, L (the rule is the series one; with 0x200011EC not 0 the
@   two are swapped). Register use: r4 text, r5 unit, r6 index address, r7 kind, r8 OWN_FUNC, r9
@   marker, r10 the rule F_ZERO / F_OL / 0 (until the vendor call; fmt_reduce changes r10); s16
@   the value, s17 its magnitude. First fmt_lowz (revision 14 rule 2): OL for every kind at 60 /
@   100 / 120 Hz with |Z| above 1e7. Then, for R, C, L: not finite is OL (no number to show); a
@   finite value below 0 is OL with F_OL; with F_ZERO it is replaced by +0 in s16 and s17 before
@   the range test, so all that follows sees 0: not OL (0 <= fmt_hard), marked (0 lies below every
@   fmt_spec lower limit, and 60 Hz is always marked), the vendor's text of 0 (0x0800E028: 0 <
@   0x40ffff97, "%0.4f", "0.0000", index 5; 0x0800DB24: 0 <= 0xbb03126f and 0 < 0x3f4ccccd, 0 *
@   1000 with "%0.1f", "0.0", "pF", index 1; 0x0800DE2C: 0 below 80, "%0.1f", "0.0", "uH", index
@   3), fmt_reduce keeps it (0 counts), and no '-' (s16 = 0 is not below 0). D, Q at .Lfc_plain
@   the same with the vendor's text of 0 "0.0000". -0.0 is not below 0 either way: it was already
@   shown without a sign.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	fmt_core, %function
fmt_core:
	push	{r4, r5, r6, r7, r8, r9, r10, lr}
	vpush	{d8, d9}		@ 48 bytes: the stack stays 8-aligned for fn_08010370
	mov	r4, r0
	mov	r5, r1
	mov	r6, r2
	and	r7, r3, #K_MASK		@ r7 = kind
	and	r10, r3, #F_NEG		@ r10 = F_ZERO, F_OL or 0
	tst	r3, #F_SP
	beq	.Lfc_rule		@ no series / parallel pair (|Z|, X, D, Q, theta)
	ldr	r0, =V_SERPAR
	ldr	r0, [r0]
	cbz	r0, .Lfc_rule		@ series values in use: the rule as given
	eor	r10, r10, #F_NEG	@ parallel (Rp, Cp, Lp): 0 and OL swapped
.Lfc_rule:
	ldr	r8, =OWN_FUNC
	movs	r9, #0			@ r9 = marker
	str	r9, [r8, #MF_MARK]
	vmov.f32	s16, s0
	vabs.f32	s17, s0
	bl	fmt_lowz		@ r0 = 1: 60 / 100 / 120 Hz and |Z| above 1e7
	cmp	r0, #0
	bne	.Lfc_ol			@ beyond the specified impedance: OL (revision 14 rule 2)
	cmp	r7, #K_L
	bhi	.Lfc_plain		@ D, Q, theta: the vendor formatter as it is
	vmov	r0, s16
	and	r0, r0, #EXP_MASK
	cmp	r0, #EXP_MASK
	beq	.Lfc_ol			@ Inf or NaN: OL
	cmp	r10, #0
	beq	.Lfc_range		@ X: the sign is kept
	vcmpe.f32	s16, #0
	vmrs	APSR_nzcv, fpscr
	bge	.Lfc_range		@ R, C, L not below 0: as they are
	tst	r10, #F_OL
	bne	.Lfc_ol			@ Rp, Cs, Lp below 0: OL (revision 14 rule 1)
	movs	r0, #0
	vmov	s16, r0			@ Rs, Cp, Ls, |Z| below 0: shown as +0
	vmov	s17, r0
.Lfc_range:
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
	cmp	r10, #0
	beq	.Lfc_plainv		@ theta: the sign kept
	vcmpe.f32	s16, #0
	vmrs	APSR_nzcv, fpscr
	bpl	.Lfc_plainv		@ D, Q not below 0 (or NaN: N clear): as they are
	tst	r10, #F_OL
	bne	.Lfc_ol			@ Q below 0: OL (revision 14 rule 1)
	movs	r0, #0
	vmov	s16, r0			@ D below 0: shown as +0 ("0.0000", fn_0800dd44 "%0.4f")
.Lfc_plainv:
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
	bge	.Lfc_mark		@ not negative (R, C, L, |Z| always: 0 or OL above): no sign
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
@ fmt_lowz - revision 14 rule 2: r0 = 1 when the frequency word 0x20001144 is 60, 100 or 120 and
@   the published |Z| 0x200050C4 lies above 1e7 ohm (fmt_spec's R upper limit of the 100 Hz
@   column, the highest impedance the manual specifies at 100 Hz; 120 Hz takes that column and 60
@   Hz has none), else 0 (an unordered compare, a NaN |Z|, gives 0). A leaf; changes r0, r1, s1,
@   s2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	fmt_lowz, %function
fmt_lowz:
	ldr	r1, =V_FREQ
	ldr	r1, [r1]
	movs	r0, #0
	cmp	r1, #60
	beq	.Llz_z
	cmp	r1, #100
	beq	.Llz_z
	cmp	r1, #120
	bne	.Llz_ret		@ 1 kHz .. 100 kHz: the manual specifies down to 1 pF
.Llz_z:
	ldr	r1, =V_Z
	vldr	s1, [r1]
	ldr	r1, =fmt_spec
	vldr	s2, [r1, #4]		@ 1e7: R upper limit, 100 Hz column
	vcmpe.f32	s1, s2
	vmrs	APSR_nzcv, fpscr
	it	gt
	movgt	r0, #1
.Llz_ret:
	bx	lr

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
@   value for D, Q, theta), by fn_08010370 as the vendor formatters print, into the text cleared
@   to 8 zero bytes first. One exception: C in uF with 1 decimal (the vendor's "%0.1f" range,
@   2000.0 .. 7999.9 uF above 19,999 counts) would be left without a '.', which fn_0800d14c
@   places 33 px further right, over the unit picture (meter, 2026-11-23); it is printed in mF
@   with 3 decimals, unit text "mF" at r5 and index 4 at r6, as the vendor's next range. An
@   index without an entry (0xFF) leaves the text. Changes r0..r3, r10, r12, s0..s2.
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
	cmp	r7, #K_C
	bne	.Lrd_val
	cmp	r0, #1
	bne	.Lrd_val
	cmp	r1, #1
	bne	.Lrd_val
	movs	r0, #'m'		@ C in uF with one decimal (2000.0 .. 7999.9 uF, the vendor's
	strb	r0, [r5, #0]		@ "%0.1f" range): no decimal would be left and the row draw
	movs	r0, #'F'		@ fn_0800d14c places a text without '.' 33 px further right,
	strb	r0, [r5, #1]		@ over the unit picture; printed in mF with 3 decimals
	movs	r0, #0			@ instead (the vendor's next unit: text "mF", index 4)
	strb	r0, [r5, #2]
	movs	r0, #4
	str	r0, [r6]
	movs	r0, #2			@ scale code 2: / 1e6
	movs	r1, #4			@ 3 decimals after the decrement below
.Lrd_val:
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
	movs	r0, #0			@ all 8 text bytes 0 first: the shorter text leaves no
	movs	r2, #7			@ bytes of the old one after its terminating 0 (the row
.Lrd_clr:				@ draw reads all 7 places, the host record sends 8)
	strb	r0, [r4, r2]
	subs	r2, r2, #1
	bpl	.Lrd_clr
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
@   row ran just before, in fn_0800d3d8 / fn_0800d294):
@   1 - every non-zero glyph object of the row (0x200059A8 + 32 row + 4 i, i = 0..6) gets an
@     amber multiply cover shown, except a glyph showing the blank image d_08036040 (index 13 of
@     fn_0800d14c, the places after the text; every pixel alpha 0), whose cover is hidden: there
@     the cover would multiply what lies under the glyph (the unit picture 0x2000021C, f30,
@     2026-11-22); MF_ROW<row> = 1;
@   0 - when MF_ROW<row> is 1, the cover of every glyph that has one is hidden; MF_ROW<row> = 0.
@   MF_MARK is cleared after it is read (a row without a formatter call, the vendor's default
@   case, is then never marked by a stale value). AAPCS.
@ Why a cover and not the image recolour (keys 0x47 / 0x48, fn_08024f78): the digit images
@   0..9 and "L" of fn_0800d14c are cf 10, 256-entry palettes whose every used entry has alpha
@   0xFF and a black background (rodata_01.s descriptors 0x05E0700A; the palette alpha becomes
@   the mask byte in fn_080214b4 / fn_080215f4), and the recolour of fn_0801f980 turns every
@   pixel into (colour w + pixel (255 - w)) 0x8081 >> 23 per channel without touching the mask:
@   at w = 0xFF the whole 28 x 47 rectangle is the colour (the meter's solid blocks, 2026-11-22),
@   and no w keeps the black black (pixel 0 gives colour w / 255).
@ The cover: a base object (fn_08023678, class 0x0804FCFC: bits 2-3 of its class byte +0x18 are
@   2, so fn_08025494 gives 0 and fn_080234ac puts it in no key group) as the only child of the
@   glyph (fn_0800ca2c creates the glyphs without children, fn_0800d14c gives them none):
@   background colour amber (key 0x20, rgb_to_565_0801d792(0xFD, 0xD0, 0x1B), the vendor's
@   highlight of ui_43.s 1146-1149), background opacity 0xFF (key 0x21), radius 0 (key 0x0B),
@   border width 0 (key 0x32) and blend mode 3 (key 0x67, fn_08026342). Key 0x67 carries the
@   layer flag 0x10 (d_08050c98), so fn_08025d34 sets layer type 1; fn_08028ed4 then draws the
@   cover into a layer and blends it with the key 0x67 value, which fn_0801f980 / fn_0801f75c
@   hand to fn_080283c8: mode 3 is fn_08014a9a, the multiply (src R dst R) >> 5, (src G dst G)
@   >> 6, (src B dst B) >> 5. fn_0802575e draws the children of the glyph after its image and
@   clipped to its rectangle, so every pixel of the drawn digit is multiplied by amber: black
@   stays black, white 0xFFFF becomes 0xF662, the grey edges scale with it. The cover takes the
@   glyph's image size (halfwords +0x2C / +0x2E, fn_08021c14) at every marked draw, and shows
@   or hides through flag 1 (fn_08023050 / fn_08023558; fn_08028ed4 skips an object with it).
@   A cover that cannot be allocated leaves that glyph white. The covers are deleted with their
@   glyphs when the screen is deleted; none is ever addressed by a stored pointer.
@ ----------------------------------------------------------------------------
	.equ	OBJ_ATTR,	0x08		@ object word: its attribute block (children list +0,
						@ count +4; fn_080233c4, fn_08023da4)
	.equ	IMG_SRC,	0x24		@ image object word: the image descriptor (fn_08021c14)
	.equ	IMG_W,		0x2C		@ image object halfwords: the image width, height
	.equ	IMG_H,		0x2E		@ (fn_08021c14)
	.equ	OBJ_HIDDEN,	0x01		@ object flag word +0x1C bit 0: not drawn (fn_08028ed4)
	.equ	K_BLEND,	0x67		@ style key: blend mode (fn_08028ed4)
	.equ	BLEND_MUL,	3		@ fn_080283c8 mode 3: fn_08014a9a multiply

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
	cmp	r6, #0
	bne	.Lrw_mark
	ldr	r0, [r5, #MF_ROW0]
	cmp	r0, #0
	beq	.Lrw_ret		@ no cover of this row shown
	movs	r4, #0
.Lrw_off:
	ldr	r0, [r7, r4, lsl #2]
	bl	row_cover_hide
	adds	r4, r4, #1
	cmp	r4, #7
	blo	.Lrw_off
	movs	r0, #0
	str	r0, [r5, #MF_ROW0]
	b	.Lrw_ret
.Lrw_mark:
	movs	r2, #0x1B
	movs	r1, #0xD0
	movs	r0, #0xFD
	bl	rgb_to_565_0801d792	@ the vendor's highlight colour (ui_43.s 1146-1149)
	uxth	r6, r0			@ r6 = RGB565
	movs	r4, #0
.Lrw_on:
	ldr	r8, [r7, r4, lsl #2]	@ r8 = glyph object
	cmp	r8, #0
	beq	.Lrw_on_next
	ldr	r0, [r8, #IMG_SRC]
	ldr	r1, =d_08036040
	cmp	r0, r1
	bne	.Lrw_cover
	mov	r0, r8			@ the blank image (alpha 0): no cover, it would
	bl	row_cover_hide		@ multiply what lies under the glyph (the unit picture)
	b	.Lrw_on_next
.Lrw_cover:
	mov	r0, r8
	bl	row_cover_of
	mov	r9, r0			@ r9 = cover
	cmp	r0, #0
	bne	.Lrw_size
	mov	r0, r8
	bl	fn_08023678		@ a base object, child of the glyph
	mov	r9, r0
	cmp	r0, #0
	beq	.Lrw_on_next		@ no memory: this glyph stays white
	mov	r1, r6
	movs	r2, #0
	bl	fn_0802657a		@ key 0x20: background colour amber
	mov	r0, r9
	movs	r1, #0xFF
	movs	r2, #0
	bl	fn_08026592		@ key 0x21: background opacity 0xFF
	mov	r0, r9
	movs	r1, #0
	movs	r2, #0
	bl	fn_08026680		@ key 0x0B: radius 0
	mov	r0, r9
	movs	r1, #0
	movs	r2, #0
	bl	fn_080265be		@ key 0x32: border width 0
	mov	r0, r9
	movs	r1, #K_BLEND
	movs	r2, #BLEND_MUL
	movs	r3, #0
	bl	fn_08026342		@ key 0x67: blend mode multiply (layer type 1)
.Lrw_size:
	mov	r0, r9
	ldrh	r1, [r8, #IMG_W]
	ldrh	r2, [r8, #IMG_H]
	movs	r3, #0
	bl	fn_080263a8		@ width, height = the glyph image's (set only when changed)
	mov	r0, r9
	movs	r1, #OBJ_HIDDEN
	bl	all_flag_bits_set
	cbz	r0, .Lrw_on_next	@ shown already
	mov	r0, r9
	movs	r1, #OBJ_HIDDEN
	bl	fn_08023558		@ show it
.Lrw_on_next:
	adds	r4, r4, #1
	cmp	r4, #7
	blo	.Lrw_on
	movs	r0, #1
	str	r0, [r5, #MF_ROW0]
.Lrw_ret:
	pop	{r3, r4, r5, r6, r7, r8, r9, pc}

@ ----------------------------------------------------------------------------
@ row_cover_of - r0 = glyph object or 0; returns r0 = its first child (the cover of
@   own_row_draw) or 0 when it has none. Changes r1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	row_cover_of, %function
row_cover_of:
	cbz	r0, .Lco_ret
	ldr	r0, [r0, #OBJ_ATTR]	@ attribute block (0: never had a child)
	cbz	r0, .Lco_ret
	ldr	r1, [r0, #4]		@ child count
	cbz	r1, .Lco_none
	ldr	r0, [r0]		@ children list
	ldr	r0, [r0]		@ child 0
	bx	lr
.Lco_none:
	movs	r0, #0
.Lco_ret:
	bx	lr

@ ----------------------------------------------------------------------------
@ row_cover_hide - r0 = glyph object or 0: sets flag 1 (fn_08023050) on its cover when it has one
@   that is shown. AAPCS.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	row_cover_hide, %function
row_cover_hide:
	push	{r4, lr}
	bl	row_cover_of
	cbz	r0, .Lch_ret
	mov	r4, r0
	movs	r1, #OBJ_HIDDEN
	bl	all_flag_bits_set
	cbnz	r0, .Lch_ret		@ hidden already
	mov	r0, r4
	movs	r1, #OBJ_HIDDEN
	bl	fn_08023050
.Lch_ret:
	pop	{r4, pc}

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
@ (columns 100 / 1k / 10k / 100k Hz; units ohm, nF, uH); the R upper limit of the 100 Hz column
@ (fmt_spec + 4) is also fmt_lowz's limit of |Z|
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
