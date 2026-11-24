@ cal.s - the calibration sweep of our build (MEASUREMENT_FIX_DESIGN.md stage 3: CAL_SETTLE_DESIGN.md
@ section 2 with every item of its critique, on the measurement core of meas.s).
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ The vendor sweep fn_0800bd5c (app_02.s) counts 45 one-second steps and stores whatever the
@ averaging holds at the counts 3, 6 .. 45, so a point can store the previous point's result or a
@ single sample (CAL_SETTLE_DESIGN 1). In our build its running test reads 0 (the .ifdef OWN at
@ 0x0800BDBA, app_02.s) and cal_step, called by ctl_loop once per main-loop pass between off_step
@ and job_step, runs the sweep instead:
@ - guard: screen 0x20001168 = 3, menu item 0x200011A8 = 5, dialog 0x200011AC != 0 (as
@   fn_0800bd5c). While idle under the guard cal_step records the words the vendor start (key 8,
@   ui_44.s 0x0800F740) changes: frequency, level, bias, speed, the calibration type 0x200050E0 and
@   the 0x78 bytes 0x200010C0.. (it zero-fills them);
@ - begin: the running word 0x200050E4 != 0 seen while idle: point 0 is set;
@ - a point p (frequency index p / 3, level index p mod 3, the vendor's order 100, 120, 1000,
@   10000, 100000 Hz at 0.1 / 0.3 / 0.6 V): the frequency and level words, fn_08009f10, then every
@   window meas.s publishes (MF_PSEQ + 1) is one window of the point. Each published window holds
@   only acquisitions after the last change and its settle time (meas.s, S1.4), so none is
@   discarded for settling;
@ - a no-reading or overload window (theta -400 or |Z| 1e10) or a non-finite one is never used
@   (cal_usable). In a short or reference point (type != 11) it starts the point's windows again
@   (critique item 1); in an open point it is skipped and the windows taken stay (revision 10);
@ - short and reference points (type != 11): the last 3 windows: the median of |Z|, theta of the
@   same window (no unwrap, items 6 / 7). The point is accepted when each of the 3 lies within a
@   factor 2 of the median (|Zi| <= 2 |Zm| and 2 |Zi| >= |Zm|: CAL_SETTLE_DESIGN 4.2's limit,
@   design 8.1 for D9); otherwise the oldest is dropped and the next window taken;
@ - open points (type 11, MEASUREMENT_FIX_DESIGN revision 10): every usable window is kept in
@   CAO_OWIN; the point ends at its CA_NO_OPEN-th usable window or at its time limit CA_POINT_MS,
@   whichever comes first, with the lower median window of what it has (cal_omed: |Z| and theta of
@   one window; the order of |Z| is the reverse order of the admittance |Y| = 1 / (|Z| + the
@   short), so the median window is the median of the admittance too). An open point never fails
@   by its time; with no usable window at all it is stored "not resolved": |Z| 1e10 and theta
@   +400 (S4.1 then uses the short only at that point, meas.s meas_comp);
@ - open validity: an open point needs |Zo| = |Z| + the point's short entry >= 100 kohm ([S10]
@   p.5), else the sweep fails naming the point;
@ - results stay in OWN_CAL; the table is written only at the end (item 4), point by point
@   through the vendor's fn_0800bb64 (its checks, then its store at 0x20000B20 + 0x90 fi + 0x30 li
@   + 4 type, phase + 0x2D0); the 30 words of the type are kept before and written back when any
@   store fails. A save during the sweep (power key, low voltage) therefore holds the old table, and
@   save.s stage_cal_fix replaces the settings the start changed by the recorded ones in the
@   staged block;
@ - finish (D10, S1.9): status 0x200050EC = 2, beep fn_08008120(0x32), the running word 0, the
@   recorded frequency, level, speed, bias, type and 0x200010C0 bytes back, fn_08009f10, own_save,
@   the vendor's status text. No factory-table copy in any mode;
@ - fails (status 3, the vendor's beeps fn_08008120 / fn_08011c68 / fn_08008120 (0x32), the
@   settings back, nothing stored or saved, the point and reason in the dialog): no change of the
@   re-arm generation MO_G for 1.5 s (stall, item 8), the point not accepted within CA_POINT_MS
@   (20 s [J]; M0-3's figure replaces it after the flash; the time does not run while meas.s
@   holds publication for the S4.4 bias wait, MF_BIASP != 0, which the start's bias change to 0
@   begins and BIAS_MAX_MS = 30 s bounds; an open point ends there instead, see above), an open
@   below 100 kohm, the vendor's check at the store;
@ - the frequency, level or step word not the one cal_step set (the vendor start ran again by a
@   physical key 8, item 2): the sweep begins again at point 0 (nothing was stored, so nothing is
@   restored; the recording is kept);
@ - the running word cleared by a key (type keys 4 / 0x10, ui_44.s 0x0800F70A..) or the guard
@   lost (long key 8 closes the dialog, item 3): the settings and the type back (item 5),
@   0x200050E4 / E8 / EC = 0, nothing stored.
@ Progress: the step word 0x200050E8 = 3 x point + held windows (0..2; an open point: its usable
@ windows, at most 2 counted), 3 x (point + 1) once a point is accepted, 45 at the store (the
@ CALIBRATION event), and the dialog status text (word 0x20005960) "n/15" with the point's
@ frequency and level, in font F1 (d_0802ce5c: it has '/' and '.', the dialog's F2 has letters,
@ digits, space, '%', '(' and ')' only, RESOURCE_FACTS 1c cmap ranges). Every line of these texts
@ is at most 75 pixels wide in F1 (the sum of the glyph advances of d_0802ce5c; revision 10 item
@ 6), less than the 80-pixel width of the panel D that holds the text object (fn_0800e6c8 mode 5,
@ ui_43.s header). The names of revision 7 were 84 and 93 pixels wide ("100kHz 0.1V"), wider
@ than the panel; the meter showed "3/15" for "13/15" (owner, 2026-11-23).
@
@ RAM: OWN_CAL (own.inc CAO_*, 0x200 bytes), cleared by own_start. Calling convention: AAPCS; each
@ function states the registers it changes beyond r0..r3, r12, s0..s15 and the flags.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

	.equ	CA_PTS,		15		@ points of a sweep
	.equ	CA_NO_OPEN,	7		@ usable windows that end an open point [J]: the median of 7
						@ stands with up to 3 outliers (own.inc CAO_OWIN holds 7)
	.if	CAO_OWIN + 8 * CA_NO_OPEN > CAO_END
	.error	"cal.s: CA_NO_OPEN windows do not fit CAO_OWIN"
	.endif
	.equ	CA_STALL_MS,	1500		@ no re-arm for this long: stall (critique item 8 asks 2 s; 1.5 s
						@ [J] so that the stall is seen before meas.s publishes the
						@ no-reading set after 2 s, whose re-arm changes MO_G again)
	.equ	CA_POINT_MS,	20000		@ time limit of one point [J], CAL_LIMIT_MS = 15 x this
						@ + 30 s (ctl.inc)
	.equ	CA_BEEP,	0x32		@ argument of the vendor's beeps (fn_0800bb64, fn_0800bcd8)
	.equ	CA_STEP_ALL,	45		@ step word at the store: 3 x 15
	.equ	F_M400,		0xC3C80000	@ -400.0: theta of the no-reading / overload set
	.equ	F_1E10,		0x501502F9	@ 1e10: |Z| of that set
	.equ	F_P400,		0x43C80000	@ +400.0: theta stored for an open "not resolved"
	.equ	F_1E5,		0x47C35000	@ 1e5: the open limit, ohm
	.equ	EXPM,		0x7F800000	@ exponent field: all ones = Inf or NaN
	.equ	V_TYPE_TXT,	0x20005958	@ word: the dialog's type text object (fn_0800e6c8 mode 5)
	.equ	V_STAT_TXT,	0x20005960	@ word: the dialog's status text object
	.equ	V_TYPE_NAMES,	0x2000009C	@ type names [12 language + type] (fn_0800e6c8 mode 5)
	.equ	V_STAT_NAMES,	0x200000FC	@ status texts [4 language + status] (fn_0800bb64)
	.equ	VB_FREQ,	0xBC8		@ block offsets (from V_BLOCK) of 0x20001144
	.equ	VB_LEVEL,	0xBBC		@ 0x20001138
	.equ	VB_BIAS,	0xBC0		@ 0x2000113C
	.equ	VB_SPEED,	0xBD4		@ 0x20001150

@ ============================================================================
@ cal_step - one pass of the sweep (file header). No arguments, no result.
@   Keeps r4..r11, s16..s31.
@ ============================================================================
	.section .text.own.cal,"ax",%progbits
	.p2align 2
	.global	cal_step
	.thumb_func
	.type	cal_step, %function
cal_step:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =OWN_CAL
	bl	cal_guard
	mov	r6, r0			@ r6 = 1: screen 3, item 5, dialog open
	ldr	r0, =V_CAL_RUN
	ldr	r7, [r0]		@ r7 = the running word 0x200050E4
	ldr	r0, [r4, #CAO_ON]
	cmp	r0, #0
	bne	.Lcs_on
	cmp	r6, #0
	beq	.Lcs_ret		@ idle, no dialog: nothing
	cmp	r7, #0
	bne	.Lcs_begin
	bl	cal_record		@ idle in the dialog: what a start changes
	b	.Lcs_ret
.Lcs_begin:
	ldr	r0, [r4, #CAO_REC]
	cbnz	r0, .Lcs_go
	bl	cal_record		@ no recording yet: the words as they are now
.Lcs_go:
	movs	r0, #1
	str	r0, [r4, #CAO_ON]
	movs	r0, #0xFF
	str	r0, [r4, #CAO_FAILP]	@ no failed point
	movs	r0, #CAL_R_NONE
	str	r0, [r4, #CAO_WHY]
	movs	r0, #0
	bl	cal_point		@ point 0
	b	.Lcs_ret
.Lcs_on:
	cmp	r6, #0
	beq	.Lcs_close		@ the dialog closed or the screen left (item 3)
	cmp	r7, #0
	beq	.Lcs_abort		@ the running word cleared by a key (item 5)
	bl	cal_same
	cmp	r0, #0
	bne	.Lcs_stall
	movs	r0, #0
	bl	cal_point		@ the vendor start ran again (item 2): from point 0
	b	.Lcs_ret
.Lcs_close:
	movs	r0, #0
	bl	cal_abort		@ no text: the dialog's objects are gone
	b	.Lcs_ret
.Lcs_abort:
	movs	r0, #1
	bl	cal_abort		@ the dialog stays: its type text set again
	b	.Lcs_ret
.Lcs_stall:
	ldr	r1, =OWN_MEAS
	ldr	r0, [r1, #MO_G]
	ldr	r1, [r4, #CAO_G]
	cmp	r0, r1
	beq	.Lcs_still
	str	r0, [r4, #CAO_G]	@ a re-arm since the last pass
	bl	now
	str	r0, [r4, #CAO_TG]
	b	.Lcs_pub
.Lcs_still:
	ldr	r0, [r4, #CAO_TG]
	bl	since
	movw	r1, #CA_STALL_MS
	cmp	r0, r1
	bls	.Lcs_pub
	movs	r0, #CAL_R_STALL
	bl	cal_fail		@ no acquisition for 1.5 s
	b	.Lcs_ret
.Lcs_pub:
	ldr	r1, =OWN_FUNC
	ldr	r0, [r1, #MF_PSEQ]
	ldr	r1, [r4, #CAO_PSEQ]
	cmp	r0, r1
	beq	.Lcs_time		@ no new window
	str	r0, [r4, #CAO_PSEQ]
	subs	r0, r0, r1		@ r0 = publishes since the last pass
	bl	cal_window
	cmp	r0, #0
	bne	.Lcs_ret		@ the point was accepted (next point, store or fail done)
.Lcs_time:
	ldr	r1, =OWN_FUNC		@ the S4.4 bias wait of meas.s holds publication (the start
	ldr	r0, [r1, #MF_BIASP]	@ moved the bias to 0): MF_BIASP != 0
	cbz	r0, .Lcs_limit		@ no wait: the point's time runs
	bl	now			@ while it holds, the point's time starts again each pass,
	str	r0, [r4, #CAO_TPT]	@ so the wait (at most BIAS_MAX_MS) is not counted as the point's
	b	.Lcs_word		@ time; then the step word as usual
.Lcs_limit:
	ldr	r0, [r4, #CAO_TPT]
	bl	since
	movw	r1, #CA_POINT_MS
	cmp	r0, r1
	bls	.Lcs_word
	ldr	r0, =V_CAL_TYPE
	ldr	r0, [r0]
	cmp	r0, #11
	bne	.Lcs_lfail
	bl	cal_oend		@ an open point ends with the windows it has (revision 10)
	b	.Lcs_ret
.Lcs_lfail:
	ldr	r0, [r4, #CAO_NW]
	cmp	r0, #3
	ite	eq
	moveq	r0, #CAL_R_SPREAD	@ 3 windows, never agreeing
	movne	r0, #CAL_R_TIME		@ fewer than 3 windows
	bl	cal_fail
	b	.Lcs_ret
.Lcs_word:
	bl	cal_step_word
.Lcs_ret:
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ cal_guard - r0 = 1 when screen 0x20001168 = 3, item 0x200011A8 = 5 and dialog 0x200011AC != 0
@   (the condition of fn_0800bd5c, app_02.s), else 0. Changes r0, r1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_guard, %function
cal_guard:
	ldr	r1, =V_SCREEN
	ldr	r0, [r1]
	cmp	r0, #3
	bne	.Lcg_no
	ldr	r1, =V_DISP_A8
	ldr	r0, [r1]
	cmp	r0, #5
	bne	.Lcg_no
	ldr	r1, =V_DIALOG
	ldr	r0, [r1]
	cmp	r0, #0
	beq	.Lcg_no
	movs	r0, #1
	bx	lr
.Lcg_no:
	movs	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ cal_busy - r0 = 1 while a calibration runs: the running word 0x200050E4 != 0, or a sweep of
@   cal.s in progress (CAO_ON != 0; it ends in the next pass when the running word was cleared),
@   else 0. The test of ctl.s key_refused and dset.s ds_check (revision 10 item 4). Changes r0,
@   r1.
@ ----------------------------------------------------------------------------
	.global	cal_busy
	.thumb_func
	.type	cal_busy, %function
cal_busy:
	ldr	r1, =V_CAL_RUN
	ldr	r0, [r1]
	cmp	r0, #0
	bne	.Lcb_yes
	ldr	r1, =OWN_CAL
	ldr	r0, [r1, #CAO_ON]
	cmp	r0, #0
	bne	.Lcb_yes
	bx	lr			@ r0 = 0
.Lcb_yes:
	movs	r0, #1
	bx	lr

@ ----------------------------------------------------------------------------
@ cal_record - the words a calibration start changes, recorded into OWN_CAL: frequency, level,
@   bias, speed, the type 0x200050E0 and the 30 words 0x200010C0..0x20001137; CAO_REC = 1.
@   Changes r0..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_record, %function
cal_record:
	ldr	r2, =OWN_CAL
	ldr	r1, =V_BLOCK
	ldr	r0, [r1, #VB_FREQ]
	str	r0, [r2, #CAO_SFREQ]
	ldr	r0, [r1, #VB_LEVEL]
	str	r0, [r2, #CAO_SLEVEL]
	ldr	r0, [r1, #VB_BIAS]
	str	r0, [r2, #CAO_SBIAS]
	ldr	r0, [r1, #VB_SPEED]
	str	r0, [r2, #CAO_SSPEED]
	ldr	r1, =V_CAL_TYPE
	ldr	r0, [r1]
	str	r0, [r2, #CAO_STYPE]
	movs	r0, #1
	str	r0, [r2, #CAO_REC]
	ldr	r1, =V_CAL_WORK
	add	r2, r2, #CAO_REL
	movs	r3, #30
.Lrc_copy:
	ldr	r0, [r1], #4
	str	r0, [r2], #4
	subs	r3, r3, #1
	bne	.Lrc_copy
	bx	lr

@ ----------------------------------------------------------------------------
@ cal_restore - the recorded words back (frequency, level, bias, speed, type, the 30 words at
@   0x200010C0), then fn_08009f10 (the signal set up for the restored frequency and level).
@   Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_restore, %function
cal_restore:
	push	{r4, lr}
	ldr	r4, =OWN_CAL
	ldr	r1, =V_BLOCK
	ldr	r0, [r4, #CAO_SFREQ]
	str	r0, [r1, #VB_FREQ]
	ldr	r0, [r4, #CAO_SLEVEL]
	str	r0, [r1, #VB_LEVEL]
	ldr	r0, [r4, #CAO_SBIAS]
	str	r0, [r1, #VB_BIAS]
	ldr	r0, [r4, #CAO_SSPEED]
	str	r0, [r1, #VB_SPEED]
	ldr	r0, [r4, #CAO_STYPE]
	ldr	r1, =V_CAL_TYPE
	str	r0, [r1]
	add	r1, r4, #CAO_REL
	ldr	r2, =V_CAL_WORK
	movs	r3, #30
.Lrs_copy:
	ldr	r0, [r1], #4
	str	r0, [r2], #4
	subs	r3, r3, #1
	bne	.Lrs_copy
	bl	fn_08009f10		@ DAC, TIM1, ADC for the restored settings
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ cal_settings - r0 = point 0..14: frequency word 0x20001144 = cal_freqs[point / 3], level word
@   0x20001138 = cal_levels[point mod 3] (the literals of app_02.s 760-806). Changes r0..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_settings, %function
cal_settings:
	movs	r1, #3
	udiv	r2, r0, r1		@ r2 = frequency index
	mls	r3, r2, r1, r0		@ r3 = level index
	ldr	r1, =cal_freqs
	ldr	r1, [r1, r2, lsl #2]
	ldr	r0, =V_FREQ
	str	r1, [r0]
	ldr	r1, =cal_levels
	ldr	r1, [r1, r3, lsl #2]
	ldr	r0, =V_LEVEL
	str	r1, [r0]
	bx	lr

@ ----------------------------------------------------------------------------
@ cal_expect - r0 = the step word cal_step keeps: 3 x CAO_PT + min(held, 2), held = CAO_NO for an
@   open (type 11), else CAO_NW. Changes r0, r1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_expect, %function
cal_expect:
	ldr	r1, =V_CAL_TYPE
	ldr	r0, [r1]
	ldr	r1, =OWN_CAL
	cmp	r0, #11
	ite	eq
	ldreq	r0, [r1, #CAO_NO]	@ an open: its usable windows
	ldrne	r0, [r1, #CAO_NW]	@ else the windows held for the agreeing three
	cmp	r0, #2
	it	hi
	movhi	r0, #2
	ldr	r1, [r1, #CAO_PT]
	add	r1, r1, r1, lsl #1
	add	r0, r0, r1
	bx	lr

@ ----------------------------------------------------------------------------
@ cal_step_word - the step word 0x200050E8 = cal_expect. Changes r0..r2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_step_word, %function
cal_step_word:
	push	{r3, lr}
	bl	cal_expect
	ldr	r2, =V_CAL_STEP
	str	r0, [r2]
	pop	{r3, pc}

@ ----------------------------------------------------------------------------
@ cal_same - r0 = 1 when the frequency and level words hold the point's values and the step word
@   holds cal_expect (the vendor start, ui_44.s 0x0800F740, sets 100 Hz / 0.1 V and step 0), else
@   0. Changes r0..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_same, %function
cal_same:
	push	{r4, lr}
	bl	cal_expect
	ldr	r1, =V_CAL_STEP
	ldr	r1, [r1]
	cmp	r0, r1
	bne	.Lsa_no
	ldr	r4, =OWN_CAL
	ldr	r0, [r4, #CAO_PT]
	movs	r1, #3
	udiv	r2, r0, r1
	mls	r3, r2, r1, r0
	ldr	r1, =cal_freqs
	ldr	r1, [r1, r2, lsl #2]
	ldr	r0, =V_FREQ
	ldr	r0, [r0]
	cmp	r0, r1
	bne	.Lsa_no
	ldr	r1, =cal_levels
	ldr	r1, [r1, r3, lsl #2]
	ldr	r0, =V_LEVEL
	ldr	r0, [r0]
	cmp	r0, r1
	bne	.Lsa_no
	movs	r0, #1
	pop	{r4, pc}
.Lsa_no:
	movs	r0, #0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ cal_point - r0 = point: it becomes the point in progress. Frequency and level words
@   (cal_settings), fn_08009f10 (the signal and a measurement restart, which meas.s sees as a
@   change: its window starts again after the 26-ms settle), no window held (CAO_NW and CAO_NO
@   0), the publish count, the generation and the ticks taken now, the step word, the progress
@   text. Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_point, %function
cal_point:
	push	{r4, lr}
	ldr	r4, =OWN_CAL
	str	r0, [r4, #CAO_PT]
	bl	cal_settings
	bl	fn_08009f10
	movs	r0, #0
	str	r0, [r4, #CAO_NW]
	str	r0, [r4, #CAO_NO]
	ldr	r1, =OWN_FUNC
	ldr	r0, [r1, #MF_PSEQ]
	str	r0, [r4, #CAO_PSEQ]	@ windows published from now on belong to this point
	ldr	r1, =OWN_MEAS
	ldr	r0, [r1, #MO_G]
	str	r0, [r4, #CAO_G]
	bl	now
	str	r0, [r4, #CAO_TPT]
	str	r0, [r4, #CAO_TG]
	bl	cal_step_word
	bl	cal_text_point
	pop	{r4, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ cal_window - r0 = publishes since the last pass (>= 1); the window is the published |Z|
@   0x200050C4 and theta 0x200050CC. It is not used when more than one publish came (never with
@   one own_measure call per pass; then one of them would be unseen) or cal_usable refuses it
@   (the no-reading / overload set, a non-finite word).
@   Open point (type 11): a window not used is skipped; a used one goes into CAO_OWIN (CAO_NO + 1)
@   and the CA_NO_OPEN-th ends the point (cal_oend).
@   Other types: a window not used drops the point's held windows (CAO_NW = 0); a used one is held
@   (the oldest of 3 dropped first) and, with 3 held, judged (cal_judge): agreeing gives
@   cal_accept of the median window, else the next window is waited for.
@   Returns r0 = 1 when cal_accept ran, else 0. Changes r0..r3, r12, s0..s5.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_window, %function
cal_window:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =OWN_CAL
	mov	r7, r0			@ r7 = publishes since the last pass
	ldr	r1, =V_Z
	ldr	r5, [r1]		@ r5 = |Z| bits
	ldr	r1, =V_THETA
	ldr	r6, [r1]		@ r6 = theta bits
	mov	r0, r5
	mov	r1, r6
	bl	cal_usable		@ r0 = 1: a window that can be used
	cmp	r7, #1
	it	ne
	movne	r0, #0			@ more than one publish: not used
	ldr	r1, =V_CAL_TYPE
	ldr	r1, [r1]
	cmp	r1, #11
	beq	.Lcw_open
	cmp	r0, #0
	beq	.Lcw_drop		@ a short / reference point starts its windows again
	ldr	r0, [r4, #CAO_NW]
	cmp	r0, #3
	bne	.Lcw_put
	add	r1, r4, #CAO_WIN	@ 3 held: the oldest out
	ldrd	r2, r3, [r1, #8]
	strd	r2, r3, [r1, #0]
	ldrd	r2, r3, [r1, #16]
	strd	r2, r3, [r1, #8]
	movs	r0, #2
.Lcw_put:
	add	r1, r4, #CAO_WIN
	add	r1, r1, r0, lsl #3
	strd	r5, r6, [r1]
	adds	r0, r0, #1
	str	r0, [r4, #CAO_NW]
	cmp	r0, #3
	bne	.Lcw_no
	bl	cal_judge		@ r0 = median slot, r1 = 1 agreeing
	cmp	r1, #0
	beq	.Lcw_no			@ not agreeing: wait for the next window
	add	r2, r4, #CAO_WIN
	add	r2, r2, r0, lsl #3
	ldrd	r0, r1, [r2]		@ the median window
	bl	cal_accept
	movs	r0, #1
	pop	{r4, r5, r6, r7, r8, pc}
.Lcw_open:
	cmp	r0, #0
	beq	.Lcw_no			@ an open point skips it; its windows stay
	ldr	r0, [r4, #CAO_NO]
	add	r1, r4, #CAO_OWIN
	add	r1, r1, r0, lsl #3
	strd	r5, r6, [r1]
	adds	r0, r0, #1
	str	r0, [r4, #CAO_NO]
	cmp	r0, #CA_NO_OPEN
	blo	.Lcw_no
	bl	cal_oend		@ CA_NO_OPEN usable windows: the point's result
	movs	r0, #1
	pop	{r4, r5, r6, r7, r8, pc}
.Lcw_drop:
	movs	r0, #0
	str	r0, [r4, #CAO_NW]	@ the point's windows start again
.Lcw_no:
	movs	r0, #0
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ cal_usable - r0 = |Z| bits, r1 = theta bits of a published window: r0 = 1 when it can be used,
@   0 for the no-reading / overload set of meas.s (theta -400 or |Z| 1e10) and for a non-finite
@   word (critique item 1). Changes r0..r2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_usable, %function
cal_usable:
	ldr	r2, =F_M400
	cmp	r1, r2
	beq	.Lcu_no			@ theta of the no-reading / overload set
	ldr	r2, =F_1E10
	cmp	r0, r2
	beq	.Lcu_no			@ |Z| of that set
	ldr	r2, =EXPM
	and	r0, r0, r2
	cmp	r0, r2
	beq	.Lcu_no			@ |Z| Inf or NaN
	and	r1, r1, r2
	cmp	r1, r2
	beq	.Lcu_no			@ theta Inf or NaN
	movs	r0, #1
	bx	lr
.Lcu_no:
	movs	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ cal_oend - the end of an open point (type 11; at its CA_NO_OPEN-th usable window or at its time
@   limit): with CAO_NO >= 1 windows the lower median window (cal_omed), with none "not
@   resolved", |Z| 1e10 and theta +400; then cal_accept (its open validity check, the next point
@   or the store). Keeps r4..r11; changes r0..r3, r12 and what cal_accept's callees change
@   (s0..s15 at the store, cal_commit).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_oend, %function
cal_oend:
	push	{r4, lr}
	ldr	r4, =OWN_CAL
	ldr	r0, [r4, #CAO_NO]
	cbz	r0, .Loe_none
	bl	cal_omed		@ r0 / r1 = the median window
	b	.Loe_acc
.Loe_none:
	ldr	r0, =F_1E10		@ no usable window at all: "not resolved"
	ldr	r1, =F_P400
.Loe_acc:
	bl	cal_accept
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ cal_omed - the CAO_NO (1..CA_NO_OPEN) windows in CAO_OWIN, every |Z| finite (cal_usable): r0 /
@   r1 = |Z| bits / theta bits of the window whose |Z| is the k-th smallest, k = (n - 1) / 2 (the
@   median for odd n, the lower median for even n; signed compare; of equal |Z| the first held).
@   Window i is the k-th when (windows below it) <= k < (windows at or below it). Finite floats
@   are totally ordered, so one i always qualifies; the fall-through to window 0 only keeps the
@   result defined. Changes r0..r3, s0, s1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_omed, %function
cal_omed:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r5, =OWN_CAL
	add	r4, r5, #CAO_OWIN	@ r4 = the windows
	ldr	r5, [r5, #CAO_NO]	@ r5 = n
	subs	r6, r5, #1
	lsrs	r6, r6, #1		@ r6 = k
	movs	r7, #0			@ r7 = i
.Lom_i:
	add	r0, r4, r7, lsl #3
	vldr	s0, [r0]		@ |Z| of window i
	movs	r1, #0			@ r1 = windows below it
	movs	r2, #0			@ r2 = windows at or below it
	movs	r3, #0			@ r3 = j
.Lom_j:
	add	r0, r4, r3, lsl #3
	vldr	s1, [r0]
	vcmpe.f32	s1, s0
	vmrs	APSR_nzcv, fpscr
	it	lt
	addlt	r1, r1, #1
	it	le
	addle	r2, r2, #1
	adds	r3, r3, #1
	cmp	r3, r5
	blo	.Lom_j
	cmp	r1, r6
	bhi	.Lom_next		@ more than k below: above the k-th
	cmp	r2, r6
	bhi	.Lom_take		@ k below at most and more than k at or below: the k-th
.Lom_next:
	adds	r7, r7, #1
	cmp	r7, r5
	blo	.Lom_i
	movs	r7, #0
.Lom_take:
	add	r0, r4, r7, lsl #3
	ldrd	r0, r1, [r0]
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ cal_judge - the 3 held windows (CAO_WIN; |Z| finite): r0 = slot 0..2 of the median |Z| (signed
@   compare), r1 = 1 when every |Zi| <= 2 |Zm| and 2 |Zi| >= |Zm|, else 0. Changes r0..r3,
@   s0..s5.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_judge, %function
cal_judge:
	ldr	r3, =OWN_CAL + CAO_WIN
	vldr	s0, [r3, #0]
	vldr	s1, [r3, #8]
	vldr	s2, [r3, #16]
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	bgt	.Ljg_gt
	vcmpe.f32	s1, s2		@ z0 <= z1
	vmrs	APSR_nzcv, fpscr
	ble	.Ljg_m1			@ z0 <= z1 <= z2
	vcmpe.f32	s0, s2
	vmrs	APSR_nzcv, fpscr
	ble	.Ljg_m2			@ z0 <= z2 < z1
	b	.Ljg_m0			@ z2 < z0 <= z1
.Ljg_gt:
	vcmpe.f32	s0, s2		@ z1 < z0
	vmrs	APSR_nzcv, fpscr
	ble	.Ljg_m0			@ z1 < z0 <= z2
	vcmpe.f32	s1, s2
	vmrs	APSR_nzcv, fpscr
	ble	.Ljg_m2			@ z1 <= z2 < z0
.Ljg_m1:
	movs	r0, #1			@ z2 < z1 < z0, or z0 <= z1 <= z2
	b	.Ljg_have
.Ljg_m0:
	movs	r0, #0
	b	.Ljg_have
.Ljg_m2:
	movs	r0, #2
.Ljg_have:
	add	r2, r3, r0, lsl #3
	vldr	s3, [r2]
	vabs.f32	s3, s3		@ s3 = |Zm|
	vadd.f32	s4, s3, s3	@ s4 = 2 |Zm|
	vabs.f32	s0, s0
	vabs.f32	s1, s1
	vabs.f32	s2, s2
	movs	r1, #0
	vcmpe.f32	s0, s4
	vmrs	APSR_nzcv, fpscr
	bgt	.Ljg_ret
	vcmpe.f32	s1, s4
	vmrs	APSR_nzcv, fpscr
	bgt	.Ljg_ret
	vcmpe.f32	s2, s4
	vmrs	APSR_nzcv, fpscr
	bgt	.Ljg_ret
	vadd.f32	s5, s0, s0
	vcmpe.f32	s5, s3
	vmrs	APSR_nzcv, fpscr
	blt	.Ljg_ret
	vadd.f32	s5, s1, s1
	vcmpe.f32	s5, s3
	vmrs	APSR_nzcv, fpscr
	blt	.Ljg_ret
	vadd.f32	s5, s2, s2
	vcmpe.f32	s5, s3
	vmrs	APSR_nzcv, fpscr
	blt	.Ljg_ret
	movs	r1, #1
.Ljg_ret:
	bx	lr

@ ----------------------------------------------------------------------------
@ cal_accept - r0 = |Z| bits, r1 = theta bits: the result of the point in progress. An open
@   (type 11) needs |Z| + the point's short entry (cal_entry) >= 1e5, else cal_fail(CAL_R_OPEN).
@   The result is kept in CAO_RES; then the next point, or the store at the last (cal_commit).
@   Changes r0..r3, r12, s0, s1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_accept, %function
cal_accept:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_CAL
	mov	r5, r0
	mov	r6, r1
	ldr	r0, =V_CAL_TYPE
	ldr	r0, [r0]
	cmp	r0, #11
	bne	.Lac_keep
	ldr	r0, [r4, #CAO_PT]
	bl	cal_entry		@ r0 = the point's type-0 (short) entry
	vldr	s0, [r0]
	vmov	s1, r5
	vadd.f32	s0, s0, s1	@ |Zo| = |Z| (published minus the short) + the short
	ldr	r0, =F_1E5
	vmov	s1, r0
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	bge	.Lac_keep
	movs	r0, #CAL_R_OPEN
	bl	cal_fail		@ an open below 100 kohm
	pop	{r4, r5, r6, pc}
.Lac_keep:
	ldr	r0, [r4, #CAO_PT]
	add	r1, r4, #CAO_RES
	add	r1, r1, r0, lsl #3
	strd	r5, r6, [r1]
	adds	r0, r0, #1
	cmp	r0, #CA_PTS
	bhs	.Lac_store
	bl	cal_point		@ the next point
	pop	{r4, r5, r6, pc}
.Lac_store:
	bl	cal_commit		@ all 15: the table, then the finish
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ cal_entry - r0 = point: r0 = 0x20000B20 + 0x90 (point / 3) + 0x30 (point mod 3), the type-0
@   word of its user-table row (fn_0800bb64's offsets, app_02.s header). Changes r0..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_entry, %function
cal_entry:
	movs	r1, #3
	udiv	r2, r0, r1		@ frequency index
	mls	r3, r2, r1, r0		@ level index
	movs	r1, #0x90
	mul	r2, r2, r1
	movs	r1, #0x30
	mla	r2, r3, r1, r2
	ldr	r0, =V_CAL_COPY
	add	r0, r0, r2
	bx	lr

	.ltorg

@ ----------------------------------------------------------------------------
@ cal_commit - the store of the 15 results (critique item 4). Step word 45; the published |Z| /
@   theta words kept; the type 0x200050E0 = the recorded type (item 5); its 30 entries copied to
@   CAO_SNAP; for each point: frequency and level words (no fn_08009f10), |Z| / theta words = the
@   result, fn_0800bb64 (the vendor checks and store). r0 = 0 from it (it has set status 3,
@   cleared 0x200050E4 / E8, beeped and set its text): the 30 entries written back, the words back,
@   the reason CAL_R_CHECK with the point, the settings back (cal_restore), the fail text. All
@   stored: the words back, cal_finish. ev_detect (ctl.s, later in the same pass) never sees the
@   results in the words. Changes r0..r3, r12, s0..s15.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_commit, %function
cal_commit:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =OWN_CAL
	ldr	r0, =V_CAL_STEP
	movs	r1, #CA_STEP_ALL
	str	r1, [r0]
	ldr	r0, =V_Z
	ldr	r7, [r0]		@ r7 = |Z| word of the last publish
	ldr	r0, =V_THETA
	ldr	r8, [r0]		@ r8 = theta word
	ldr	r0, [r4, #CAO_STYPE]
	ldr	r1, =V_CAL_TYPE
	str	r0, [r1]
	movs	r0, #0
	bl	cal_snap		@ r0 = 0: the entries into CAO_SNAP
	movs	r5, #0			@ r5 = point
.Lcm_next:
	mov	r0, r5
	bl	cal_settings		@ the row fn_0800bb64 indexes (fn_0800a004, fn_08009fe0)
	add	r0, r4, #CAO_RES
	add	r0, r0, r5, lsl #3
	ldrd	r1, r2, [r0]
	ldr	r0, =V_Z
	str	r1, [r0]
	ldr	r0, =V_THETA
	str	r2, [r0]
	bl	fn_0800bb64
	cmp	r0, #0
	beq	.Lcm_fail
	adds	r5, r5, #1
	cmp	r5, #CA_PTS
	blo	.Lcm_next
	ldr	r0, =V_Z
	str	r7, [r0]
	ldr	r0, =V_THETA
	str	r8, [r0]
	bl	cal_finish
	pop	{r4, r5, r6, r7, r8, pc}
.Lcm_fail:
	movs	r0, #1
	bl	cal_snap		@ r0 = 1: the entries written back
	ldr	r0, =V_Z
	str	r7, [r0]
	ldr	r0, =V_THETA
	str	r8, [r0]
	str	r5, [r4, #CAO_FAILP]
	movs	r0, #CAL_R_CHECK
	str	r0, [r4, #CAO_WHY]
	bl	cal_restore
	movs	r0, #0
	str	r0, [r4, #CAO_ON]
	bl	cal_text_fail
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ cal_snap - r0 = 0: the 15 |Z| entries and the 15 theta entries (+0x2D0) of the type
@   CAO_STYPE, point by point, copied into CAO_SNAP; r0 = 1: copied back from it into the user
@   table (the only write of cal.s into the table). Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_snap, %function
cal_snap:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r8, r0			@ r8 = direction
	ldr	r4, =OWN_CAL
	ldr	r6, [r4, #CAO_STYPE]
	lsls	r6, r6, #2		@ r6 = 4 x type
	add	r5, r4, #CAO_SNAP	@ r5 = snapshot slot
	movs	r7, #0			@ r7 = point
.Lsn_next:
	mov	r0, r7
	bl	cal_entry
	add	r0, r0, r6		@ r0 = the type's |Z| entry of the point
	cmp	r8, #0
	bne	.Lsn_back
	ldr	r1, [r0]
	str	r1, [r5, #0]
	ldr	r1, [r0, #0x2D0]
	str	r1, [r5, #4]
	b	.Lsn_step
.Lsn_back:
	ldr	r1, [r5, #0]
	str	r1, [r0]
	ldr	r1, [r5, #4]
	str	r1, [r0, #0x2D0]
.Lsn_step:
	adds	r5, r5, #8
	adds	r7, r7, #1
	cmp	r7, #CA_PTS
	blo	.Lsn_next
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ cal_finish - the finish (design D10, S1.9; fn_0800bcd8's steps without its 1 kHz / 0.6 V and its
@   factory copy): status 0x200050EC = 2, fn_08008120(0x32), the running word 0, the recorded
@   settings back (cal_restore, with fn_08009f10), CAO_ON = 0, own_save (one save; cal_save_ret is
@   the return address the emulator's named-save gate expects), the vendor's status text in F2.
@   Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_finish, %function
cal_finish:
	push	{r4, lr}
	ldr	r4, =OWN_CAL
	ldr	r0, =V_CAL_STATUS
	movs	r1, #2
	str	r1, [r0]
	movs	r0, #CA_BEEP
	bl	fn_08008120		@ one beep, as fn_0800bcd8
	ldr	r0, =V_CAL_RUN
	movs	r1, #0
	str	r1, [r0]
	bl	cal_restore
	movs	r0, #0
	str	r0, [r4, #CAO_ON]
	bl	own_save
	.global	cal_save_ret
cal_save_ret:
	bl	cal_text_status
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ cal_fail - r0 = reason CAL_R_*: the sweep fails at the point in progress, as fn_0800bb64's fail
@   path (app_02.s .L0800bc06): 0x200050E4 = 0, 0x200050E8 = 0, status 3, fn_08008120(0x32),
@   fn_08011c68(0x32), fn_08008120(0x32); then the settings back (cal_restore), CAO_ON = 0, the
@   point and the reason in the dialog. Nothing is stored or saved. Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_fail, %function
cal_fail:
	push	{r4, lr}
	ldr	r4, =OWN_CAL
	str	r0, [r4, #CAO_WHY]
	ldr	r0, [r4, #CAO_PT]
	str	r0, [r4, #CAO_FAILP]
	movs	r1, #0
	ldr	r0, =V_CAL_RUN
	str	r1, [r0]
	ldr	r0, =V_CAL_STEP
	str	r1, [r0]
	ldr	r0, =V_CAL_STATUS
	movs	r1, #3
	str	r1, [r0]
	movs	r0, #CA_BEEP
	bl	fn_08008120
	movs	r0, #CA_BEEP
	bl	fn_08011c68
	movs	r0, #CA_BEEP
	bl	fn_08008120
	bl	cal_restore
	movs	r0, #0
	str	r0, [r4, #CAO_ON]
	bl	cal_text_fail
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ cal_abort - r0 = 1 when the dialog is still open: the sweep ends without a result (a type key
@   cleared the running word, or the dialog / the screen was left). 0x200050E4, E8 and EC = 0, the
@   reason CAL_R_ABORT with the point, the settings and the type back (cal_restore), CAO_ON = 0;
@   with the dialog open its type text set again from the restored type (the key handler drew the
@   new one: fn_080228d0(word 0x20005958, word 0x2000009C[12 language + type]), as fn_0800e6c8
@   mode 5 prints it). Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_abort, %function
cal_abort:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_CAL
	mov	r5, r0
	movs	r1, #0
	ldr	r0, =V_CAL_RUN
	str	r1, [r0]
	ldr	r0, =V_CAL_STEP
	str	r1, [r0]
	ldr	r0, =V_CAL_STATUS
	str	r1, [r0]
	movs	r0, #CAL_R_ABORT
	str	r0, [r4, #CAO_WHY]
	ldr	r0, [r4, #CAO_PT]
	str	r0, [r4, #CAO_FAILP]
	bl	cal_restore
	movs	r0, #0
	str	r0, [r4, #CAO_ON]
	cmp	r5, #0
	beq	.Lab_ret
	ldr	r0, =V_TYPE_TXT
	ldr	r0, [r0]
	cmp	r0, #0
	beq	.Lab_ret
	ldr	r1, =V_LANGUAGE
	ldr	r1, [r1]
	add	r1, r1, r1, lsl #1	@ 3 language
	ldr	r2, =V_CAL_TYPE
	ldr	r2, [r2]
	add	r2, r2, r1, lsl #2	@ 12 language + type
	ldr	r1, =V_TYPE_NAMES
	ldr	r1, [r1, r2, lsl #2]
	bl	fn_080228d0
.Lab_ret:
	pop	{r4, r5, r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ cal_text_point - the dialog status text "n/15" and the point's frequency and level (cal_names),
@   two lines, font F1. Nothing when the object word 0x20005960 is 0. Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_text_point, %function
cal_text_point:
	push	{r4, lr}
	bl	cal_font_f1		@ r0 = the object, or 0
	cmp	r0, #0
	beq	.Ltp_ret
	ldr	r4, =OWN_CAL
	ldr	r3, [r4, #CAO_PT]
	adds	r2, r3, #1		@ n = point + 1
	ldr	r1, =cal_names
	ldr	r3, [r1, r3, lsl #2]
	ldr	r1, =txt_point
	bl	fn_080228d0
.Ltp_ret:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ cal_text_fail - the dialog status text "Fail n/15" and the reason (cal_why), two lines, font
@   F1 (FN 1.5: the point and the reason). Nothing when the object word is 0. Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_text_fail, %function
cal_text_fail:
	push	{r4, lr}
	bl	cal_font_f1
	cmp	r0, #0
	beq	.Ltf_ret
	ldr	r4, =OWN_CAL
	ldr	r2, [r4, #CAO_FAILP]
	adds	r2, r2, #1		@ n = point + 1
	ldr	r3, [r4, #CAO_WHY]
	ldr	r1, =cal_why
	ldr	r3, [r1, r3, lsl #2]
	ldr	r1, =txt_fail
	bl	fn_080228d0
.Ltf_ret:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ cal_text_status - the vendor's status text of the finish: font F2 (d_0802f0d8, the dialog's
@   own) and fn_080228d0(word 0x20005960, word 0x200000FC[4 language + status 0x200050EC]) as
@   fn_0800bcd8 ends. Nothing when the object word is 0. Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_text_status, %function
cal_text_status:
	push	{r4, lr}
	ldr	r4, =V_STAT_TXT
	ldr	r0, [r4]
	cmp	r0, #0
	beq	.Lts_ret
	ldr	r1, =d_0802f0d8
	movs	r2, #0
	bl	fn_080266ac		@ the font back to F2
	ldr	r1, =V_LANGUAGE
	ldr	r1, [r1]
	ldr	r2, =V_CAL_STATUS
	ldr	r2, [r2]
	add	r2, r2, r1, lsl #2
	ldr	r1, =V_STAT_NAMES
	ldr	r1, [r1, r2, lsl #2]
	ldr	r0, [r4]
	bl	fn_080228d0
.Lts_ret:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ cal_font_f1 - r0 = the status text object (word 0x20005960); when it is not 0 its font is set
@   to F1 (fn_080266ac(object, d_0802ce5c, 0): style key 0x57, an existing key is replaced,
@   fn_08027294). Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cal_font_f1, %function
cal_font_f1:
	push	{r4, lr}
	ldr	r4, =V_STAT_TXT
	ldr	r0, [r4]
	cmp	r0, #0
	beq	.Lff_ret
	ldr	r1, =d_0802ce5c
	movs	r2, #0
	bl	fn_080266ac
	ldr	r0, [r4]
.Lff_ret:
	pop	{r4, pc}

	.ltorg

@ ============================================================================
@ Constant data
@ ============================================================================
	.section .rodata.own.cal,"a",%progbits
	.p2align 2
@ the frequency words of the points by frequency index (app_02.s 760-806)
cal_freqs:
	.word	100, 120, 1000, 10000, 100000
@ the level words by level index: 0.1, 0.3, 0.6 V (0x3DCCCCCD, 0x3E99999A, 0x3F19999A, the
@ literals of fn_0800bd5c)
cal_levels:
	.word	0x3DCCCCCD, 0x3E99999A, 0x3F19999A
@ the names of the 15 points (second line of the progress text): frequency in Hz, k for 1000, then
@ the level in V; each at most 73 pixels wide in F1 (cal.s header, revision 10 item 6)
cal_names:
	.word	nm_p00, nm_p01, nm_p02, nm_p03, nm_p04, nm_p05, nm_p06, nm_p07
	.word	nm_p08, nm_p09, nm_p10, nm_p11, nm_p12, nm_p13, nm_p14
@ the reasons CAL_R_NONE .. CAL_R_ABORT (second line of the fail text)
cal_why:
	.word	why_none, why_stall, why_time, why_open, why_check, why_spread, why_abort
nm_p00:	.asciz	"100 0.1V"
nm_p01:	.asciz	"100 0.3V"
nm_p02:	.asciz	"100 0.6V"
nm_p03:	.asciz	"120 0.1V"
nm_p04:	.asciz	"120 0.3V"
nm_p05:	.asciz	"120 0.6V"
nm_p06:	.asciz	"1k 0.1V"
nm_p07:	.asciz	"1k 0.3V"
nm_p08:	.asciz	"1k 0.6V"
nm_p09:	.asciz	"10k 0.1V"
nm_p10:	.asciz	"10k 0.3V"
nm_p11:	.asciz	"10k 0.6V"
nm_p12:	.asciz	"100k 0.1V"
nm_p13:	.asciz	"100k 0.3V"
nm_p14:	.asciz	"100k 0.6V"
why_none:	.asciz	""
why_stall:	.asciz	"no signal"
why_time:	.asciz	"time limit"
why_open:	.asciz	"open low"
why_check:	.asciz	"check"
why_spread:	.asciz	"spread"
why_abort:	.asciz	"aborted"
@ the format strings of fn_080228d0 (r2 = n, r3 = the second line)
txt_point:	.asciz	"%d/15\n%s"
txt_fail:	.asciz	"Fail %d/15\n%s"
