@ cmp.s - AUTO L / C / R with hysteresis (MEASUREMENT_FIX_DESIGN.md S2.5), the tolerance modes
@ (S2.9) and the compare judgement with its non-blocking beeper / LED (stage 2G, S2.8).
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ Entry points and their callers:
@ - own_auto_class: fn_0800f854 (src/ui_44.s 0x0800F874, .ifdef OWN) in place of the vendor's
@   AUTO decision block (ui_44.s 800-850), when Func 0x20001148 = 0;
@ - own_cmp_judge: meas_tail (own/meas.s) at every publish, after the compare value 0x200050DC
@   and before fn_0800f854; it replaces the vendor's 0.5-s routine fn_0800a7ec, whose call in the
@   main loop (system_40.s 0x080281E2) is a nop.w in our build;
@ - own_cmp_show: fn_0800f854 (ui_44.s 0x0800F8FC) in place of the vendor's compare-screen block
@   (deviation, OK / NG, the nominal), on screen 2;
@ - own_cmp_step: ctl_loop (own/ctl.s) once per main-loop pass: the beeper steps and the LED idle
@   level off screen 2;
@ - own_cmp_key: key_step (own/ctl.s) before fn_08009400: the counter reset (long key 0x100 on
@   screen 2, design D16);
@ - own_tol_set: TOLERANCE_SET (own/cmd.s h_tol_set).
@
@ The judgement (S2.8, S2.9), on screen 2 only:
@ - present: |Z| 0x200050C4 not above fn_0800a030() / 10 (the vendor's presence rule, fn_0800a7ec
@   measure_33.s 0x0800A7F4..0x0800A822, kept). Not present: the vendor latch 0x200001D5 and ring
@   index 0x200001D4 are cleared, the LEDs go idle; the result is "no part" (CR_NONE) for the
@   no-reading / overload set (theta -400) and a value outside the measurement range, else "out of
@   range" (CR_OUT: a reading above the presence limit, not counted);
@ - present: deviation D = (v - nominal) * 100 / nominal in %, or (v - nominal) * 1000 in pF for
@   the absolute mode; IN when lower <= D <= upper, HI above, LO below; IN with a secondary limit
@   that fails (D above its maximum, Q below its minimum, Rs above the ESR maximum) is CR_SEC;
@   compared unclamped (FN 2.5);
@ - stable: the publish directly after the previous one (publish number + 1) of a present part
@   and |v - previous| <= min(band / 4, 0.1 %) of |v| (band = the smaller limit magnitude, as a
@   fraction: FN 2.3, J); not stable: CR_UNST ("---");
@ - counted once per insertion: the first stable judgement with the vendor latch 0x200001D5 = 0
@   sets it and counts IN in 0x200050F0, every other result in 0x200050F4, each at most 999; the
@   alarm follows the vendor's WarnType 0x2000116C (1: on IN, 0: on any other result, fn_0800a7ec
@   0x0800A8A0 / 0x0800A8F2): LED word 0x20001174 set: PB13 / PB12 (GPIOB 0x40010C00 through
@   fn_08008350) to the vendor's levels (IN: PB13 low, PB12 high; other: PB13 high, PB12 low;
@   idle both high), held until the part is removed or the screen is left (FN 2.4); sound word
@   0x20001170 set: the vendor's beeps, 1 (IN) or 2 (other) of 200 ms with 150 ms between them
@   (fn_08008120(200), fn_08011c68(150); fn_08011c68 counts 1 ms per unit: TIM7 0x40001400 with
@   prescaler 0x47 = 71 at fn_08008CD4 on the 72 MHz APB1 timer clock gives 1 MHz, and
@   wait_halfword_40001424_reaches_count waits for 1000 counts; a desk fact, design 8.1 Q6),
@   timed by the tick word 0x20000480 in own_cmp_step. The beeper is TIM2 0x40000000 compare
@   +0x38 (fn_0800c6ec): the volume halfword 0x20001160 on, 0 off, as fn_08008120.
@ - the vendor word 0x200050D8 keeps its meaning and its arithmetic (cmp_vdev: |v - nominal| * 100
@   / nominal in double, 99.99 above 99.0), formed at every judgement and every own_cmp_show call
@   on screen 2, as the vendor's fn_0800f854 formed it at every call.
@ Tolerance modes (RAM only, D7): 0 the vendor's symmetric % 0x20001188 (the default after every
@ start), 1 lower / upper %, 2 lower / upper pF (compare quantity C only), 3 an IEC 60062 letter
@ (B C D F G J K M: +-0.1 / 0.25 / 0.5 / 1 / 2 / 5 / 10 / 20 %; Z -20 / +80 %; B / C / D are
@ +-0.1 / 0.25 / 0.5 pF for a C nominal below 10 pF, design S2.9 [P5]), resolved at each
@ judgement. Any change of 0x20001188 (the meter's sorting editor, COMPARE_SET) after the mode was
@ set returns to mode 0 (one tolerance in force; J). A secondary limit: none, D max, Q min, ESR max.
@
@ RAM: OWN_FUNC MF_AUTO, MF_TMODE .. MF_BEEPS (own.inc); vendor words 0x200001D4 / D5,
@ 0x200050D8, 0x200050F0 / F4, 0x20001190 (the busy halfword, as the vendor's long presses),
@ 0x200011E4 / E8 (AUTO). Never-brick: no flash, no save; the only peripherals are GPIOB BSRR /
@ BRR through fn_08008350 and the TIM2 compare through fn_0800c6ec, as fn_0800a7ec / fn_08008120.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

	.equ	V_RES,		0x20004D7C	@ base of the result words (fn_0800a068's r5)
	.equ	VR_RS,		0x324		@ 0x200050A0 Rs
	.equ	VR_CS,		0x32C		@ 0x200050A8 Cs, nF
	.equ	VR_L,		0x344		@ 0x200050C0 L, uH
	.equ	VR_Z,		0x348		@ 0x200050C4 |Z|
	.equ	VR_TH,		0x350		@ 0x200050CC theta
	.equ	VR_Q,		0x354		@ 0x200050D0 Q
	.equ	VR_D,		0x358		@ 0x200050D4 D
	.equ	VR_DEV,		0x35C		@ 0x200050D8 vendor deviation, %
	.equ	VR_CMPV,	0x360		@ 0x200050DC compare value
	.equ	VR_PASS,	0x374		@ 0x200050F0 pass counter
	.equ	VR_FAIL,	0x378		@ 0x200050F4 fail counter
	.equ	OBJS,		0x200001D4	@ screen objects (fn_0800f854's r6); bytes +0 / +1 the
					@ vendor's compare ring index and latch
	.equ	OB_AUTO,	0x14		@ +0x14 the AUTO mode picture (fn_0800f854)
	.equ	OB_NOMINAL,	0x34		@ +0x34 the nominal text
	.equ	OB_PASS,	0x38		@ +0x38 / +0x3C the counters (fn_0800a7ec)
	.equ	OB_FAIL,	0x3C
	.equ	OB_RESULT,	0x40		@ +0x40 OK / NG text
	.equ	OB_DEV,		0x44		@ +0x44 deviation text
	.equ	F_M400,		0xC3C80000	@ -400: theta of the overload / no-reading set
	.equ	EXP_MASK,	0x7F800000
	.equ	GPIOB,		0x40010C00
	.equ	TIM2,		0x40000000
	.equ	LED_A,		0x2000		@ PB13
	.equ	LED_B,		0x1000		@ PB12
	.equ	CNT_MAX,	999
	.equ	T_BEEP,		200		@ ms (fn_08008120(200) in fn_0800a7ec)
	.equ	T_GAP,		150		@ ms (fn_08011c68(0x96))
	.equ	KEY_RESET,	0x0100		@ the counter reset: long press of this mask
	.equ	TOL_LEN,	15		@ TOLERANCE_SET payload bytes
	.equ	MS_TICK,	0x20000480	@ GUI tick, +10 per 10-ms SysTick (ctl.inc V_TICK)
@ offsets in the float table cmp_k
	.equ	CK_180,		0
	.equ	CK_T,		4
	.equ	CK_TH,		8
	.equ	CK_TL,		12
	.equ	CK_100,		16
	.equ	CK_1000,	20
	.equ	CK_1EM3,	24
	.equ	CK_10PF,	28
	.equ	CK_9999P,	32
	.equ	CK_99995,	36

	.section .text.own.cmp,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ own_auto_class - S2.5 (D3: T = 10 degrees, H = 2). Class MF_AUTO: 0 undecided (after a setting
@   change, meas.s), 1 R, 2 C, 3 L. Validity windows of the vendor (ui_44.s 800-846, kept): C when
@   bits(Cs 0x200050A8) + 0xC5FCED90 < 0x133BA9B0 (0.5 pF <= Cs < 0.2 F), L when bits(L 0x200050C0)
@   + 0xC0FFFFFF < 0x0DBEBC1F (0.5 uH < L < 1e8 uH). With theta 0x200050CC:
@   |theta| > 180 (the -400 set): the class is kept (undecided: R);
@   undecided: C when theta < -10 and C valid, L when theta > 10 and L valid, else R;
@   R: C when theta < -11 and C valid, L when theta > 11 and L valid, else R;
@   C: R when theta > -9 or C not valid, else C; L: R when theta < 9 or L not valid, else L
@   (C and L change only through R). Then, when the class differs from the one before (a change, or
@   the first decision after a setting change or restart, which leave it undecided) or the main row
@   byte 0x200011E4 differs from the class's (the vendor's test, ui_44.s 817 / 833 / 842), with the
@   class's secondary (R: 1 / 4 theta, D3; C: 2 / 2 D; L: 3 / 3 Q; a secondary the user picked with
@   its key is kept while the class stays): the class
@   picture (R d_0803d2fc, C d_0803d3d4, L d_0803d584, the vendor's) on the object [0x200001E8] by
@   fn_08021c14, and the two words stored. AAPCS (fn_0800f854 keeps its r4..r7).
@ ----------------------------------------------------------------------------
	.global	own_auto_class
	.thumb_func
	.type	own_auto_class, %function
own_auto_class:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_FUNC
	ldr	r5, =V_RES
	ldr	r6, [r4, #MF_AUTO]	@ r6 = class now
	vldr	s0, [r5, #VR_TH]
	vabs.f32	s1, s0
	ldr	r0, =cmp_k
	vldr	s2, [r0, #CK_180]
	vcmpe.f32	s1, s2
	vmrs	APSR_nzcv, fpscr
	ble	.Lac_valid
	movs	r0, r6			@ no angle: kept
	bne	.Lac_set
	movs	r0, #1			@ undecided: R
	b	.Lac_set
.Lac_valid:
	ldr	r1, [r5, #VR_CS]
	ldr	r2, =0xC5FCED90
	add	r1, r1, r2
	ldr	r2, =0x133BA9B0
	cmp	r1, r2
	ite	lo
	movlo	r2, #1
	movhs	r2, #0			@ r2 = 1: C valid
	ldr	r1, [r5, #VR_L]
	ldr	r3, =0xC0FFFFFF
	add	r1, r1, r3
	ldr	r3, =0x0DBEBC1F
	cmp	r1, r3
	ite	lo
	movlo	r3, #1
	movhs	r3, #0			@ r3 = 1: L valid
	ldr	r0, =cmp_k
	cmp	r6, #2
	beq	.Lac_from_c
	cmp	r6, #3
	beq	.Lac_from_l
	vldr	s2, [r0, #CK_T]		@ undecided: T
	cbz	r6, .Lac_from_r
	vldr	s2, [r0, #CK_TH]	@ R: T + H / 2
.Lac_from_r:
	movs	r0, #1			@ R unless
	vneg.f32	s3, s2
	vcmpe.f32	s0, s3
	vmrs	APSR_nzcv, fpscr
	it	lt
	movlt	r0, #2			@ theta < -threshold: C
	cmp	r0, #2
	bne	.Lac_r_l
	cmp	r2, #0
	it	eq
	moveq	r0, #1			@ C not valid: R
	b	.Lac_set
.Lac_r_l:
	vcmpe.f32	s0, s2
	vmrs	APSR_nzcv, fpscr
	ble	.Lac_set		@ R
	cmp	r3, #0
	it	ne
	movne	r0, #3			@ theta > threshold and L valid: L
	b	.Lac_set
.Lac_from_c:
	vldr	s2, [r0, #CK_TL]	@ T - H / 2
	movs	r0, #2
	cmp	r2, #0
	it	eq
	moveq	r0, #1			@ C no longer valid: R
	vneg.f32	s3, s2
	vcmpe.f32	s0, s3
	vmrs	APSR_nzcv, fpscr
	it	gt
	movgt	r0, #1			@ theta > -(T - H / 2): R
	b	.Lac_set
.Lac_from_l:
	vldr	s2, [r0, #CK_TL]
	movs	r0, #3
	cmp	r3, #0
	it	eq
	moveq	r0, #1			@ L no longer valid: R
	vcmpe.f32	s0, s2
	vmrs	APSR_nzcv, fpscr
	it	lt
	movlt	r0, #1			@ theta < T - H / 2: R
.Lac_set:
	str	r0, [r4, #MF_AUTO]
	ldr	r1, =auto_sec
	ldrb	r5, [r1, r0]		@ r5 = the class's secondary
	cmp	r6, r0
	ldr	r6, =V_BLOCK
	bne	.Lac_draw		@ the class was (re)decided: its row and secondary
	ldrsb	r1, [r6, #V_MAIN_ROW - V_BLOCK]
	cmp	r1, r0
	beq	.Lac_ret		@ shown already (the main row, the vendor's test; a secondary
					@ the user chose with its key stays while the class stays)
.Lac_draw:
	mov	r4, r0			@ r4 = class
	ldr	r1, =auto_pics
	ldr	r1, [r1, r0, lsl #2]
	ldr	r0, =OBJS
	ldr	r0, [r0, #OB_AUTO]
	bl	fn_08021c14
	strb	r4, [r6, #V_MAIN_ROW - V_BLOCK]
	str	r5, [r6, #V_SECONDARY - V_BLOCK]
.Lac_ret:
	pop	{r4, r5, r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ cmp_effective - the limits in force (header "Tolerance modes"): MF_EMODE (0 vendor %, 1 %,
@   2 pF), MF_ELO / MF_EHI (float). Mode 0: -tol / +tol of 0x20001188; a mode set while
@   0x20001188 has changed since (MF_TOLW) becomes 0 first; mode 2 with a quantity other than C
@   is taken as mode 0. Also called by cmd.s rec_compare. Changes r0..r3, r12, s0, s1.
@ ----------------------------------------------------------------------------
	.global	cmp_effective
	.thumb_func
	.type	cmp_effective, %function
cmp_effective:
	ldr	r0, =OWN_FUNC
	ldr	r1, [r0, #MF_TMODE]
	ldr	r2, =V_TOLERANCE
	ldr	r2, [r2]
	cmp	r1, #0
	beq	.Lef_vendor
	ldr	r3, [r0, #MF_TOLW]
	cmp	r2, r3
	beq	.Lef_mode
	movs	r1, #0
	str	r1, [r0, #MF_TMODE]	@ the vendor tolerance changed: back to mode 0
	b	.Lef_vendor
.Lef_mode:
	cmp	r1, #3
	beq	.Lef_letter
	ldr	r3, =V_CMP_TYPE
	ldr	r3, [r3]
	cmp	r1, #2
	bne	.Lef_own		@ mode 1
	cmp	r3, #2
	bne	.Lef_vendor		@ pF limits need the quantity C
.Lef_own:
	str	r1, [r0, #MF_EMODE]
	ldr	r1, [r0, #MF_TLO]
	str	r1, [r0, #MF_ELO]
	ldr	r1, [r0, #MF_THI]
	str	r1, [r0, #MF_EHI]
	bx	lr
.Lef_letter:
	ldrb	r1, [r0, #MF_TLET]
	ldr	r2, =tol_letters
	movs	r3, #0
.Lef_find:
	ldrb	r12, [r2, r3]
	cmp	r12, r1
	beq	.Lef_found
	adds	r3, r3, #1
	cmp	r3, #9
	blo	.Lef_find
	ldr	r2, =V_TOLERANCE	@ not a letter (never stored by own_tol_set): mode 0
	ldr	r2, [r2]
	b	.Lef_vendor
.Lef_found:
	cmp	r3, #3
	bhs	.Lef_pct		@ F .. Z: always %
	ldr	r1, =V_CMP_TYPE
	ldr	r1, [r1]
	cmp	r1, #2
	bne	.Lef_pct		@ B / C / D of R or L: %
	ldr	r1, =V_NOMINAL
	vldr	s0, [r1]
	ldr	r1, =cmp_k
	vldr	s1, [r1, #CK_10PF]
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	bge	.Lef_pct		@ a nominal of 10 pF or more: %
	movs	r1, #2
	ldr	r2, =tol_pf
	b	.Lef_table
.Lef_pct:
	movs	r1, #1
	ldr	r2, =tol_pct
.Lef_table:
	str	r1, [r0, #MF_EMODE]
	add	r2, r2, r3, lsl #3
	ldr	r1, [r2]
	str	r1, [r0, #MF_ELO]
	ldr	r1, [r2, #4]
	str	r1, [r0, #MF_EHI]
	bx	lr
.Lef_vendor:
	movs	r1, #0
	str	r1, [r0, #MF_EMODE]
	vmov	s0, r2
	vneg.f32	s1, s0
	vstr	s1, [r0, #MF_ELO]
	str	r2, [r0, #MF_EHI]
	bx	lr

	.ltorg

@ ----------------------------------------------------------------------------
@ own_cmp_judge - the judgement of one publish (file header). No arguments; AAPCS. Registers:
@   r4 OWN_FUNC, r5 V_RES, r6 the result code, r7 the publish number, r8 presence;
@   s16 v, s17 nominal, s18 the signed deviation, s19 |Z|.
@ ----------------------------------------------------------------------------
	.global	own_cmp_judge
	.thumb_func
	.type	own_cmp_judge, %function
own_cmp_judge:
	push	{r4, r5, r6, r7, r8, r9, r10, lr}
	vpush	{d8, d9, d10, d11}
	ldr	r0, =V_SCREEN
	ldr	r0, [r0]
	cmp	r0, #2
	bne	.Lj_ret			@ the judgement belongs to the compare screen
	ldr	r4, =OWN_FUNC
	ldr	r5, =V_RES
	ldr	r7, [r4, #MF_PSEQ]
	bl	cmp_effective
	vldr	s16, [r5, #VR_CMPV]	@ v
	ldr	r0, =V_NOMINAL
	vldr	s17, [r0]		@ nominal
	vldr	s19, [r5, #VR_Z]
	bl	cmp_vdev		@ the vendor's deviation word 0x200050D8
	ldr	r0, =cmp_k
	@ the signed deviation in the unit of the mode
	vsub.f32	s18, s16, s17
	ldr	r1, [r4, #MF_EMODE]
	cmp	r1, #2
	bne	.Lj_pct
	vldr	s1, [r0, #CK_1000]
	vmul.f32	s18, s18, s1	@ nF -> pF
	b	.Lj_presence
.Lj_pct:
	vldr	s1, [r0, #CK_100]
	vmul.f32	s18, s18, s1
	vdiv.f32	s18, s18, s17	@ %
.Lj_presence:
	vstr	s18, [r4, #MF_DEV]
	bl	fn_0800a030		@ the open limit of this frequency
	movs	r1, #10
	sdiv	r0, r0, r1
	vmov	s0, r0
	vcvt.f32.s32	s0, s0
	vcmpe.f32	s0, s19
	vmrs	APSR_nzcv, fpscr
	bcs	.Lj_present		@ limit >= |Z| (as fn_0800a7ec): present
	@ no part, or a reading above the presence limit
	ldr	r0, =OBJS
	movs	r1, #0
	strb	r1, [r0, #0]		@ the vendor's ring index
	strb	r1, [r0, #1]		@ and latch: the next insertion counts
	str	r1, [r4, #MF_PVOK]
	movs	r0, #0
	bl	cmp_led			@ the result LED goes idle with the part
	movs	r6, #CR_NONE
	ldr	r0, [r5, #VR_TH]
	ldr	r1, =F_M400
	cmp	r0, r1
	beq	.Lj_store		@ the overload / no-reading set
	vmov	r0, s16
	and	r0, r0, #EXP_MASK
	cmp	r0, #EXP_MASK
	beq	.Lj_store		@ not finite
	ldr	r0, =V_CMP_TYPE
	ldr	r0, [r0]
	subs	r0, r0, #1
	cmp	r0, #2
	bhi	.Lj_store
	ldr	r1, =fmt_hard
	add	r1, r1, r0, lsl #2
	vldr	s1, [r1]
	vabs.f32	s0, s16
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	bgt	.Lj_store		@ outside the measurement range (OL)
	movs	r6, #CR_OUT
	b	.Lj_store
.Lj_present:
	@ primary limits
	movs	r6, #CR_IN
	vldr	s0, [r4, #MF_EHI]
	vcmpe.f32	s18, s0
	vmrs	APSR_nzcv, fpscr
	it	gt
	movgt	r6, #CR_HI
	vldr	s0, [r4, #MF_ELO]
	vcmpe.f32	s18, s0
	vmrs	APSR_nzcv, fpscr
	it	lt
	movlt	r6, #CR_LO
	cmp	r6, #CR_IN
	bne	.Lj_stable
	bl	cmp_secondary		@ r0 = 1 when the secondary limit fails
	cmp	r0, #0
	it	ne
	movne	r6, #CR_SEC
.Lj_stable:
	@ stable: the previous publish, a present part, within the stability limit
	movs	r8, #0			@ r8 = 1: stable
	ldr	r0, [r4, #MF_PVOK]
	cbz	r0, .Lj_prev
	ldr	r0, [r4, #MF_PVSEQ]
	adds	r0, r0, #1
	cmp	r0, r7
	bne	.Lj_prev
	bl	cmp_stab_lim		@ s0 = the allowed |v - previous|
	vldr	s1, [r4, #MF_PREV]
	vsub.f32	s1, s16, s1
	vabs.f32	s1, s1
	vcmpe.f32	s1, s0
	vmrs	APSR_nzcv, fpscr
	it	ls
	movls	r8, #1
.Lj_prev:
	vstr	s16, [r4, #MF_PREV]
	str	r7, [r4, #MF_PVSEQ]
	movs	r0, #1
	str	r0, [r4, #MF_PVOK]
	cmp	r8, #0
	bne	.Lj_count
	movs	r6, #CR_UNST		@ not stable yet: "---"
	b	.Lj_store
.Lj_count:
	ldr	r0, =OBJS
	ldrb	r1, [r0, #1]
	cmp	r1, #0
	bne	.Lj_store		@ counted already for this insertion
	movs	r1, #1
	strb	r1, [r0, #1]		@ the latch
	cmp	r6, #CR_IN
	ite	eq
	moveq	r1, #VR_PASS
	movne	r1, #VR_FAIL
	ldr	r0, [r5, r1]
	movw	r2, #CNT_MAX
	cmp	r0, r2
	it	lo
	addlo	r0, r0, #1		@ saturates at 999
	str	r0, [r5, r1]
	bl	cmp_counters
	mov	r0, r6
	bl	cmp_alarm
.Lj_store:
	str	r6, [r4, #MF_RES]
.Lj_ret:
	vpop	{d8, d9, d10, d11}
	pop	{r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ cmp_vdev - the vendor's deviation word 0x200050D8 exactly as fn_0800f854 forms it on every call
@   on screen 2 (ui_44.s 871-896, the block own_cmp_show replaces): d = double(nominal
@   0x20001184); double(|v - nominal| in float, v = 0x200050DC) * 100.0 (double_multiply) / d
@   (double_divide), double_to_float; above 99.0 as a signed bit compare (bgt): 99.99. Called by
@   own_cmp_judge and own_cmp_show. Changes r0..r3, r12, s0..s15.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cmp_vdev, %function
cmp_vdev:
	push	{r4, r5, r6, lr}
	ldr	r0, =V_NOMINAL
	ldr	r0, [r0]
	vmov	s0, r0			@ the nominal
	bl	float_to_double
	mov	r4, r0
	mov	r5, r1			@ r4:r5 = double(nominal)
	ldr	r6, =V_RES
	vldr	s0, [r6, #VR_CMPV]
	ldr	r0, =V_NOMINAL
	vldr	s1, [r0]
	vsub.f32	s0, s0, s1
	vabs.f32	s0, s0
	vmov	r0, s0
	bl	float_to_double
	movs	r2, #0
	ldr	r3, =0x40590000		@ 100.0 as a double (.L0800fa38)
	bl	double_multiply
	mov	r2, r4
	mov	r3, r5
	bl	double_divide
	bl	double_to_float
	ldr	r1, =0x42C60000		@ 99.0
	cmp	r0, r1
	it	gt
	ldrgt	r0, =0x42C7FAE1		@ 99.99
	str	r0, [r6, #VR_DEV]
	pop	{r4, r5, r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ cmp_secondary - r0 = 1 when the secondary limit fails (MF_SKIND 1: D 0x200050D4 above MF_SVAL;
@   2: Q 0x200050D0 below it; 3: Rs 0x200050A0 above it), else 0. Changes r0, r1, s0, s1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cmp_secondary, %function
cmp_secondary:
	ldr	r1, =OWN_FUNC
	ldr	r0, [r1, #MF_SKIND]
	vldr	s1, [r1, #MF_SVAL]
	ldr	r1, =V_RES
	cmp	r0, #1
	beq	.Lsc_d
	cmp	r0, #2
	beq	.Lsc_q
	cmp	r0, #3
	beq	.Lsc_esr
	movs	r0, #0
	bx	lr
.Lsc_d:
	vldr	s0, [r1, #VR_D]
	b	.Lsc_max
.Lsc_esr:
	vldr	s0, [r1, #VR_RS]
.Lsc_max:
	movs	r0, #0
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	it	gt
	movgt	r0, #1
	bx	lr
.Lsc_q:
	vldr	s0, [r1, #VR_Q]
	movs	r0, #0
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	it	lt
	movlt	r0, #1
	bx	lr

@ ----------------------------------------------------------------------------
@ cmp_stab_lim - s0 = the stability limit for v = s16, nominal s17 (own_cmp_judge's registers):
@   min(band / 4, 0.001 |v|), band = min(|MF_ELO|, |MF_EHI|) as a value: % of |nominal| / 100 in
@   the % modes, pF / 1000 (nF) in the pF mode. Changes r0, r1, s0..s3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cmp_stab_lim, %function
cmp_stab_lim:
	ldr	r1, =OWN_FUNC
	vldr	s0, [r1, #MF_ELO]
	vabs.f32	s0, s0
	vldr	s1, [r1, #MF_EHI]
	vabs.f32	s1, s1
	vcmpe.f32	s1, s0
	vmrs	APSR_nzcv, fpscr
	it	lt
	vmovlt.f32	s0, s1		@ s0 = the smaller limit magnitude
	ldr	r0, [r1, #MF_EMODE]
	ldr	r1, =cmp_k
	cmp	r0, #2
	bne	.Lsl_pct
	vldr	s2, [r1, #CK_1000]
	vdiv.f32	s0, s0, s2	@ pF -> nF
	b	.Lsl_quarter
.Lsl_pct:
	vldr	s2, [r1, #CK_100]
	vdiv.f32	s0, s0, s2
	vabs.f32	s3, s17
	vmul.f32	s0, s0, s3	@ % of the nominal as a value
.Lsl_quarter:
	vmov.f32	s2, #0.25
	vmul.f32	s0, s0, s2
	vabs.f32	s3, s16
	vldr	s2, [r1, #CK_1EM3]
	vmul.f32	s3, s3, s2	@ 0.1 % of |v|
	vcmpe.f32	s3, s0
	vmrs	APSR_nzcv, fpscr
	it	lt
	vmovlt.f32	s0, s3
	bx	lr

	.ltorg

@ ----------------------------------------------------------------------------
@ cmp_alarm - r0 = the counted result: the vendor's WarnType choice (header) decides whether it
@   alarms; then the LED level (LED word set) and the beeps (sound word set: 1 for IN, 2 for any
@   other result; the first starts now, own_cmp_step times the rest). Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cmp_alarm, %function
cmp_alarm:
	push	{r4, r5, r6, lr}
	cmp	r0, #CR_IN
	ite	eq
	moveq	r4, #1			@ r4 = 1 IN, 2 other
	movne	r4, #2
	ldr	r5, =V_WARN_TYPE
	ldr	r0, [r5, #0]		@ WarnType: 1 alarm on IN, 0 on the others
	cmp	r4, #1
	bne	.Lal_ng
	cmp	r0, #1
	bne	.Lal_ret
	b	.Lal_go
.Lal_ng:
	cmp	r0, #0
	bne	.Lal_ret
.Lal_go:
	ldr	r0, [r5, #V_WARN_LED - V_WARN_TYPE]
	cbz	r0, .Lal_sound
	mov	r0, r4
	bl	cmp_led
.Lal_sound:
	ldr	r0, [r5, #V_WARN_SOUND - V_WARN_TYPE]
	cbz	r0, .Lal_ret
	ldr	r6, =OWN_FUNC
	str	r4, [r6, #MF_BEEPN]	@ 1 or 2 beeps
	bl	cmp_beeper_on
	movs	r0, #1
	str	r0, [r6, #MF_BEEPS]
	ldr	r0, =MS_TICK
	ldr	r0, [r0]
	adds	r0, r0, #T_BEEP
	str	r0, [r6, #MF_BEEPT]
.Lal_ret:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ cmp_led - r0 = level: 0 idle (PB13 and PB12 high), 1 IN (PB13 low, PB12 high), 2 other (PB13
@   high, PB12 low), the vendor's levels (fn_0800a7ec, fn_08008350 flag 0 = BRR low, 1 = BSRR
@   high); MF_LED = the level. Level 0 is written only when MF_LED is not 0. Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cmp_led, %function
cmp_led:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	ldr	r5, =OWN_FUNC
	cbnz	r4, .Lld_set
	ldr	r0, [r5, #MF_LED]
	cbz	r0, .Lld_ret		@ idle already
.Lld_set:
	str	r4, [r5, #MF_LED]
	ldr	r6, =GPIOB
	cmp	r4, #1
	ite	eq
	moveq	r2, #0			@ IN: PB13 low
	movne	r2, #1			@ else high
	mov	r1, #LED_A
	mov	r0, r6
	bl	fn_08008350
	cmp	r4, #2
	ite	eq
	moveq	r2, #0			@ other: PB12 low
	movne	r2, #1			@ else high
	mov	r1, #LED_B
	mov	r0, r6
	bl	fn_08008350
.Lld_ret:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ cmp_beeper_on / cmp_beeper_off - TIM2 compare +0x38 (fn_0800c6ec) = the volume halfword
@   0x20001160 / 0, as fn_08008120 starts and ends a beep. Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cmp_beeper_on, %function
cmp_beeper_on:
	ldr	r1, =V_VOLUME
	ldrh	r1, [r1]
	mov	r0, #TIM2
	b	fn_0800c6ec

	.thumb_func
	.type	cmp_beeper_off, %function
cmp_beeper_off:
	movs	r1, #0
	mov	r0, #TIM2
	b	fn_0800c6ec

@ ----------------------------------------------------------------------------
@ cmp_counters - on screen 2: the two counters printed "%03d" on their objects (+0x38 pass,
@   +0x3C fail), as fn_0800a7ec ends. Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cmp_counters, %function
cmp_counters:
	push	{r4, lr}
	ldr	r0, =V_SCREEN
	ldr	r0, [r0]
	cmp	r0, #2
	bne	.Lco_ret
	ldr	r4, =OBJS
	ldr	r2, =V_PASS_COUNT
	ldr	r2, [r2]
	ldr	r1, =txt_03d
	ldr	r0, [r4, #OB_PASS]
	bl	fn_080228d0
	ldr	r2, =V_FAIL_COUNT
	ldr	r2, [r2]
	ldr	r1, =txt_03d
	ldr	r0, [r4, #OB_FAIL]
	bl	fn_080228d0
.Lco_ret:
	pop	{r4, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ own_cmp_step - once per main-loop pass (ctl_loop): off screen 2 the LEDs go idle; a beep
@   sequence steps when the tick word 0x20000480 reaches MF_BEEPT (signed difference): beeper on
@   -> off, one beep less, a gap of T_GAP when beeps remain; gap -> on for T_BEEP. AAPCS.
@ ----------------------------------------------------------------------------
	.global	own_cmp_step
	.thumb_func
	.type	own_cmp_step, %function
own_cmp_step:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_FUNC
	ldr	r0, =V_SCREEN
	ldr	r0, [r0]
	cmp	r0, #2
	beq	.Lcs_beep
	movs	r0, #0
	bl	cmp_led			@ idle (written only when it was set)
.Lcs_beep:
	ldr	r5, [r4, #MF_BEEPS]
	cmp	r5, #0
	beq	.Lcs_ret		@ no beep sequence
	ldr	r6, =MS_TICK
	ldr	r6, [r6]		@ r6 = now
	ldr	r0, [r4, #MF_BEEPT]
	subs	r0, r6, r0
	bmi	.Lcs_ret		@ not yet
	cmp	r5, #1
	bne	.Lcs_gap
	bl	cmp_beeper_off
	ldr	r0, [r4, #MF_BEEPN]
	subs	r0, r0, #1
	str	r0, [r4, #MF_BEEPN]
	cmp	r0, #0
	ble	.Lcs_done
	movs	r0, #2
	str	r0, [r4, #MF_BEEPS]
	adds	r0, r6, #T_GAP
	str	r0, [r4, #MF_BEEPT]
	b	.Lcs_ret
.Lcs_done:
	movs	r0, #0
	str	r0, [r4, #MF_BEEPS]
	b	.Lcs_ret
.Lcs_gap:
	bl	cmp_beeper_on
	movs	r0, #1
	str	r0, [r4, #MF_BEEPS]
	adds	r0, r6, #T_BEEP
	str	r0, [r4, #MF_BEEPT]
.Lcs_ret:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ own_cmp_key - r0 = event code, r1 = key mask of the event slot (key_step, before fn_08009400):
@   code 0xFE (held) with mask 0x100 on screen 2 while the busy halfword 0x20001190 is 0: busy = 1
@   (one reset per hold, as the vendor's long presses; the release 0xFF clears it, app_01.s
@   0x08009490), both counters 0 and printed. V1.1 does nothing with this long press on screens 1
@   and 2 (MEASUREMENT_DESIGN.md 4: free 0xFE masks). AAPCS.
@ ----------------------------------------------------------------------------
	.global	own_cmp_key
	.thumb_func
	.type	own_cmp_key, %function
own_cmp_key:
	cmp	r0, #0xFE
	bne	.Lck_ret
	cmp	r1, #KEY_RESET
	bne	.Lck_ret
	ldr	r0, =V_SCREEN
	ldr	r0, [r0]
	cmp	r0, #2
	bne	.Lck_ret
	ldr	r0, =V_KEY_BUSY
	ldrh	r1, [r0]
	cbnz	r1, .Lck_ret
	movs	r1, #1
	strh	r1, [r0]		@ busy: once per hold
	movs	r1, #0
	ldr	r0, =V_PASS_COUNT
	str	r1, [r0]
	ldr	r0, =V_FAIL_COUNT
	str	r1, [r0]
	b	cmp_counters		@ printed (tail call)
.Lck_ret:
	bx	lr

	.ltorg

@ ----------------------------------------------------------------------------
@ own_cmp_show - the compare-screen part of fn_0800f854 (in its place at 0x0800F8FC, screen 2):
@   result text on [0x20000214] with its colour (fn_08026694, key 0x55): "---" white for no part
@   or not stable, "IN" green, "HI" / "LO" red, the failed secondary "DHI" / "QLO" / "RHI" red,
@   "OUT" amber; deviation text on [0x20000218]: "---" without a part, else the sign and |D| with
@   2 decimals (1 from 99.995, limited to 999.9) and "pF" in the pF mode; the nominal on
@   [0x20000208] as the vendor (fn_0800e028 / fn_0800db24 / fn_0800de2c by 0x20001178, "%s%s").
@   AAPCS.
@ ----------------------------------------------------------------------------
	.global	own_cmp_show
	.thumb_func
	.type	own_cmp_show, %function
own_cmp_show:
	push	{r4, r5, r6, r7, r8, lr}
	sub	sp, sp, #0x28		@ sp: index word, sp+4 text, sp+0xC unit, sp+0x14 own text
	bl	cmp_vdev		@ 0x200050D8 at every call, as the vendor block did
	ldr	r4, =OWN_FUNC
	ldr	r5, =OBJS
	ldr	r6, [r4, #MF_RES]
	cmp	r6, #CR_UNST
	bls	.Lsh_res
	movs	r6, #CR_NONE
.Lsh_res:
	ldr	r1, =res_texts
	ldr	r2, [r1, r6, lsl #2]	@ the result text
	cmp	r6, #CR_SEC
	bne	.Lsh_text
	ldr	r0, [r4, #MF_SKIND]
	ldr	r1, =sec_texts
	ldr	r2, [r1, r0, lsl #2]
.Lsh_text:
	ldr	r1, =txt_s
	ldr	r0, [r5, #OB_RESULT]
	bl	fn_080228d0
	ldr	r1, =res_colors
	add	r1, r1, r6, lsl #2
	ldrb	r0, [r1, #0]
	ldrb	r2, [r1, #2]
	ldrb	r1, [r1, #1]
	bl	rgb_to_565_0801d7c2	@ as fn_0800f854 forms its OK / NG colours
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r5, #OB_RESULT]
	bl	fn_08026694
	@ deviation
	add	r7, sp, #0x14		@ r7 = own text (20 bytes)
	cmp	r6, #CR_NONE
	bne	.Lsh_dev
	ldr	r2, =res_none
	b	.Lsh_dev_out
.Lsh_dev:
	vldr	s0, [r4, #MF_DEV]
	movs	r0, #'+'
	vcmpe.f32	s0, #0
	vmrs	APSR_nzcv, fpscr
	it	lt
	movlt	r0, #'-'
	strb	r0, [r7]
	vabs.f32	s0, s0
	ldr	r0, =cmp_k
	vldr	s1, [r0, #CK_9999P]
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	it	gt
	vmovgt.f32	s0, s1		@ limited to 999.9
	ldr	r8, =txt_2f
	vldr	s1, [r0, #CK_99995]
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	it	ge
	ldrge	r8, =txt_1f
	vmov	r0, s0
	bl	float_to_double
	mov	r2, r0
	mov	r3, r1
	mov	r1, r8
	adds	r0, r7, #1
	bl	fn_08010370		@ |D| after the sign
	ldr	r0, [r4, #MF_EMODE]
	cmp	r0, #2
	bne	.Lsh_dev_txt
	mov	r0, r7
.Lsh_end:
	ldrb	r1, [r0], #1
	cmp	r1, #0
	bne	.Lsh_end
	movs	r1, #'p'
	strb	r1, [r0, #-1]
	movs	r1, #'F'
	strb	r1, [r0]
	movs	r1, #0
	strb	r1, [r0, #1]
.Lsh_dev_txt:
	mov	r2, r7
.Lsh_dev_out:
	ldr	r1, =txt_s
	ldr	r0, [r5, #OB_DEV]
	bl	fn_080228d0
	@ the nominal, as the vendor
	movs	r0, #0
	str	r0, [sp, #0]
	str	r0, [sp, #4]
	str	r0, [sp, #8]
	str	r0, [sp, #0xC]
	str	r0, [sp, #0x10]
	ldr	r0, =V_CMP_TYPE
	ldr	r0, [r0]
	subs	r0, r0, #1
	cmp	r0, #2
	bhi	.Lsh_nom_txt		@ no quantity: an empty text, as the vendor
	ldr	r1, =nom_fmt
	ldr	r3, [r1, r0, lsl #2]
	ldr	r0, =V_NOMINAL
	vldr	s0, [r0]
	mov	r2, sp
	add	r1, sp, #0xC
	add	r0, sp, #4
	blx	r3
.Lsh_nom_txt:
	add	r3, sp, #0xC
	add	r2, sp, #4
	ldr	r1, =txt_ss
	ldr	r0, [r5, #OB_NOMINAL]
	bl	fn_080228d0
	add	sp, sp, #0x28
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ own_tol_set - TOLERANCE_SET: r0 = payload, r1 = its length -> r0 = status (S_OK, S_BAD_ARG,
@   S_NOT_NOW). Payload (15 bytes): mode u8 (0 vendor +- %, 1 % limits, 2 pF limits, 3 letter),
@   lower i32 and upper i32 (mode 1: 0.01 % steps, -9999..99990; mode 2: 0.01 pF steps,
@   -99999..99999; lower <= upper), letter u8 (mode 3: B C D F G J K M Z), secondary kind u8
@   (0 none, 1 D max, 2 Q min, 3 ESR max), secondary value f32 (finite, >= 0, kind != 0).
@   Fields a mode does not use are not checked. Mode 2 needs the compare quantity C (else
@   S_NOT_NOW). On S_OK: the mode, its limits / letter, the secondary limit, MF_TOLW = 0x20001188
@   now, and the stability chain restarts (MF_PVOK = 0). Changes r0..r3, r12, s0, s1.
@ ----------------------------------------------------------------------------
	.global	own_tol_set
	.thumb_func
	.type	own_tol_set, %function
own_tol_set:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #TOL_LEN
	blo	.Lts_bad
	mov	r4, r0
	ldrb	r5, [r4, #0]		@ r5 = mode
	ldr	r6, [r4, #1]		@ r6 = lower (unaligned word: allowed for normal memory)
	ldr	r7, [r4, #5]		@ r7 = upper
	ldrb	r8, [r4, #10]		@ r8 = secondary kind
	cmp	r8, #3
	bhi	.Lts_bad
	cmp	r8, #0
	beq	.Lts_mode
	ldr	r0, [r4, #11]		@ the secondary value
	and	r1, r0, #EXP_MASK
	cmp	r1, #EXP_MASK
	beq	.Lts_bad		@ not finite
	cmp	r0, #0
	blt	.Lts_bad		@ negative (sign bit)
.Lts_mode:
	cmp	r5, #0
	beq	.Lts_ok
	cmp	r5, #3
	beq	.Lts_letter
	bhi	.Lts_bad
	cmp	r6, r7
	bgt	.Lts_bad		@ lower above upper
	cmp	r5, #2
	beq	.Lts_pf
	ldr	r0, =-9999
	cmp	r6, r0
	blt	.Lts_bad
	ldr	r0, =99990
	cmp	r7, r0
	bgt	.Lts_bad
	b	.Lts_limits
.Lts_pf:
	ldr	r0, =V_CMP_TYPE
	ldr	r0, [r0]
	cmp	r0, #2
	bne	.Lts_notnow
	ldr	r0, =-99999
	cmp	r6, r0
	blt	.Lts_bad
	ldr	r0, =99999
	cmp	r7, r0
	bgt	.Lts_bad
.Lts_limits:
	ldr	r0, =cmp_k
	vldr	s1, [r0, #CK_100]
	ldr	r1, =OWN_FUNC
	vmov	s0, r6
	vcvt.f32.s32	s0, s0
	vdiv.f32	s0, s0, s1
	vstr	s0, [r1, #MF_TLO]
	vmov	s0, r7
	vcvt.f32.s32	s0, s0
	vdiv.f32	s0, s0, s1
	vstr	s0, [r1, #MF_THI]
	b	.Lts_ok
.Lts_letter:
	ldrb	r0, [r4, #9]
	ldr	r1, =tol_letters
	movs	r2, #0
.Lts_find:
	ldrb	r3, [r1, r2]
	cmp	r3, r0
	beq	.Lts_let_ok
	adds	r2, r2, #1
	cmp	r2, #9
	blo	.Lts_find
	b	.Lts_bad
.Lts_let_ok:
	ldr	r1, =OWN_FUNC
	str	r0, [r1, #MF_TLET]
.Lts_ok:
	ldr	r1, =OWN_FUNC
	str	r5, [r1, #MF_TMODE]
	str	r8, [r1, #MF_SKIND]
	movs	r0, #0
	cmp	r8, #0
	beq	.Lts_sval
	ldr	r0, [r4, #11]
.Lts_sval:
	str	r0, [r1, #MF_SVAL]
	ldr	r0, =V_TOLERANCE
	ldr	r0, [r0]
	str	r0, [r1, #MF_TOLW]
	movs	r0, #0
	str	r0, [r1, #MF_PVOK]	@ the stability chain starts again
	movs	r0, #S_OK
	pop	{r4, r5, r6, r7, r8, pc}
.Lts_notnow:
	movs	r0, #S_NOT_NOW
	pop	{r4, r5, r6, r7, r8, pc}
.Lts_bad:
	movs	r0, #S_BAD_ARG
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ============================================================================
@ Tables
@ ============================================================================
	.section .rodata.own.cmp,"a",%progbits
	.p2align 2

@ floats (offsets CK_*, defined at the top)
cmp_k:
	.word	0x43340000		@ 180: |theta| above it is no angle (the -400 set)
	.word	0x41200000		@ 10 = T (D3)
	.word	0x41300000		@ 11 = T + H / 2
	.word	0x41100000		@ 9 = T - H / 2
	.word	0x42C80000		@ 100
	.word	0x447A0000		@ 1000: nF -> pF
	.word	0x3A83126F		@ 0.001: the 0.1 % stability floor
	.word	0x3C23D70A		@ 0.01 nF = 10 pF: the absolute-pF presets' nominal limit
	.word	0x4479F99A		@ 999.9: the deviation display limit
	.word	0x42C7FD71		@ 99.995: from here 1 decimal

@ AUTO class -> secondary word (R theta, C D, L Q) and picture (ui_44.s .L0800fa30 / 20 / 2c)
auto_sec:
	.byte	4, 4, 2, 3
auto_pics:
	.word	d_0803d2fc, d_0803d2fc, d_0803d3d4, d_0803d584

@ the IEC 60062 letters and their limits (lower, upper): % and, for B / C / D, pF
tol_letters:
	.ascii	"BCDFGJKMZ"
	.p2align 2
tol_pct:
	.word	0xBDCCCCCD, 0x3DCCCCCD		@ B +-0.1 %
	.word	0xBE800000, 0x3E800000		@ C +-0.25 %
	.word	0xBF000000, 0x3F000000		@ D +-0.5 %
	.word	0xBF800000, 0x3F800000		@ F +-1 %
	.word	0xC0000000, 0x40000000		@ G +-2 %
	.word	0xC0A00000, 0x40A00000		@ J +-5 %
	.word	0xC1200000, 0x41200000		@ K +-10 %
	.word	0xC1A00000, 0x41A00000		@ M +-20 %
	.word	0xC1A00000, 0x42A00000		@ Z -20 / +80 %
tol_pf:
	.word	0xBDCCCCCD, 0x3DCCCCCD		@ B +-0.1 pF
	.word	0xBE800000, 0x3E800000		@ C +-0.25 pF
	.word	0xBF000000, 0x3F000000		@ D +-0.5 pF

@ result texts and colours (R, G, B; rgb_to_565_0801d7c2 as fn_0800f854) by CR_*
res_texts:
	.word	res_none, res_in, res_hi, res_lo, res_hi, res_out, res_none
sec_texts:
	.word	res_none, res_dhi, res_qlo, res_rhi
res_colors:
	.byte	0xFF, 0xFF, 0xFF, 0		@ no part: white
	.byte	0x00, 0xFF, 0x00, 0		@ IN: green (the vendor's OK)
	.byte	0xFF, 0x00, 0x00, 0		@ HI: red (the vendor's NG)
	.byte	0xFF, 0x00, 0x00, 0		@ LO
	.byte	0xFF, 0x00, 0x00, 0		@ secondary
	.byte	0xFD, 0xD0, 0x1B, 0		@ out of range: amber (fmt.s's marker colour)
	.byte	0xFF, 0xFF, 0xFF, 0		@ not stable: white

@ the formatters of the nominal by quantity 1 R, 2 C, 3 L (ui_44.s 930-948)
nom_fmt:
	.word	fn_0800e028, fn_0800db24, fn_0800de2c

res_none:
	.asciz	"---"
res_in:
	.asciz	"IN"
res_hi:
	.asciz	"HI"
res_lo:
	.asciz	"LO"
res_out:
	.asciz	"OUT"
res_dhi:
	.asciz	"DHI"
res_qlo:
	.asciz	"QLO"
res_rhi:
	.asciz	"RHI"
txt_s:
	.asciz	"%s"
txt_ss:
	.asciz	"%s%s"
txt_2f:
	.asciz	"%0.2f"
txt_1f:
	.asciz	"%0.1f"
txt_03d:
	.asciz	"%03d"
