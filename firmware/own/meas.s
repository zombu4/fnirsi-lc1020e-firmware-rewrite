@ meas.s - the measurement core of our build (MEASUREMENT_FIX_DESIGN.md stage 1, S1.1 to S1.8).
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ own_measure replaces the vendor routine fn_0800a068 (measure_33.s) in the main loop
@ (system_40.s 0x080281D4, .ifdef OWN). fn_0800a068 stays in the image and is no longer called.
@ What it does differently, each item with its section of the design:
@ - S1.1 coherent sampling: own_tim1_setup (TIM1 period AR = 144 MHz / (k f) - 1, so the 128
@   samples are exactly 1, 4 or 16 signal periods) and own_dac_setup (150 table entries at 120 Hz,
@   so the DAC period is exactly 1 / 120 s);
@ - S1.2 one known DFT bin per channel (k = 1 below 10 kHz, 4 below 100 kHz, 16 above: the bin
@   the TIM1 timing puts the signal in) and the noise power of the residual after removing the
@   mean and the fitted bin-k sine;
@ - S1.3 a complex window estimate: Zbar = K * sum(V u) / sum(I u) with u = conj(X_ref) / |X_ref|
@   of a reference channel chosen once per window, the median-of-3 start, the outlier and
@   part-change rules for resolved acquisitions, no distance test for noise-limited ones, a window
@   that closes at the first accepted acquisition at least T_win after its first one;
@ - S1.4 an acquisition handshake by a re-arm generation word (MO_G, counted by own_dma_rearm in
@   fix.s) and a settle time after every change of a setting, of the codes or a restart;
@ - S1.5 saturation (a sample at code 0 or 4095) steps the range, three overload acquisitions in
@   a row publish the overload set;
@ - S1.7 the vendor's magnitude compensation (short, decade interpolation) on screens 1 and 2,
@   the raw value for the calibration store on screen 3;
@ - S1.8 theta not folded, the derived values from the complex Zbar, D and Q without NaN, the
@   no-reading set after 2 s without an in-band acquisition.
@ While hold (0x200011A4) is set the measurement runs on and windows close, but nothing is
@ published (the display freeze of design decision D1).
@ Stage 2 (revision 6): S2.6 series / parallel with hysteresis (meas_serpar), S2.7 a hold that
@ ends at a change of frequency, level, bias, range, speed or circuit (meas_hold, D2), the
@ publish number MF_PSEQ and the compare judgement call in meas_tail (S2.8), 60 Hz (S2.12:
@ own_dac_setup n = 150, the 100 Hz calibration entry, own_freq_step for the frequency key).
@ A window always holds at least 3 accepted acquisitions: it closes at the first addition with
@ N >= 3 and T_win passed (meas_add), so a window that would hold fewer in T_win is extended
@ until the third (the A6 D bound of the design's fix 4 needs N >= 3; revision 6).
@ Stage 4 (revision 7, design 8.1): S4.1 the complex open / short compensation with S4.2 option
@ (K), the references kept as magnitude breakpoints through the compensation, on screens 1 and 2
@ only (meas_comp; never on screen 3, so fn_0800bb64 stores the V1.1 format); S4.4 the bias
@ transient: after a bias change a window is published only once the DC midpoints are steady
@ (meas_bias_wait). S4.7 needs no code: ADC1 IN3 / ADC2 IN4 are fast channels (user manual
@ figure 9-3), so the 1.5-cycle sample time stays.
@ The words of OWN_FUNC this file writes: MF_SP, MF_HOLDP, MF_HL, MF_PSEQ, MF_BIASP, MF_BMID,
@ MF_BT0, and MF_AUTO = 0 at a setting change (own.inc).
@
@ Vendor RAM words written here (each also written by fn_0800a068 in V1.1, same meaning unless
@ the design's section 2 table says otherwise): 0x20005090 / 94 (|Zm| / theta of the last
@ acquisition), 0x20005098..0x200050B4 (Xs, Xp, Rs, Rp, Cs, Cp, Ls, Lp), 0x200050B8 / BC / C0
@ (R, C, L by series / parallel), 0x200050C4 |Z|, 0x200050C8 X (= Xs in both modes), 0x200050CC
@ theta, 0x200050D0 Q, 0x200050D4 D, 0x200050DC (compare value), 0x200011EC (0 series,
@ 1 parallel), 0x200011F4 (accepted count of the open window), 0x200011FC (1 at the end of every
@ call with a measuring screen: finding 0 means fn_08009f10 ran since), 0x20001200 (1, then 0, at
@ every publish), 0x20001208 / 0x2000120C (no reading), bytes 0x2000000A (consecutive
@ rejected acquisitions) and 0x2000000B (presence, with word 0x2000511C), byte 0x200011C4 (the
@ re-arm request of the DMA interrupt fn_080085d0). The gain and range bytes 0x200011C5 / C6 /
@ C8 change only through the vendor ranging calls fn_0800b20c / fn_0800b000 and, while OCAL_LOCK
@ holds them (ocal.s), through meas_lockset (the vendor setters fn_0800b164 / fn_0800af58 /
@ fn_080093b8).
@ OWN_CAL_DESIGN.md revision 3: S4.3 the gain correction zeta nu at meas_publish (ocal_gain; where
@ it is applied the decade interpolation and the S4.2 (K) references are skipped), S4.5 the clip
@ limits (ocal_clip), S4.6 the settle times per kind and frequency (ocal_settle, the maximum rule
@ of meas_watch, the kind in r1 of meas_change, the bound T_max + 10), S4.4's limit from the BIAS
@ section (ocal_bias_limit), the lock, the raw record at every close (ocal_raw, before the hold
@ test) and the settle trace (meas_ocal_acq). The only word of OWN_OCAL meas.s writes is the byte
@ OCS_KIND.
@
@ The state (OWN_MEAS, 0x100 bytes; own_start clears it to 0 at every start). Offsets:
@   0x00 MO_G       re-arm generation (own.inc; written only by own_dma_rearm)
@   0x04 MO_GEXP    the generation our own last request will produce (G + 1 when we set it)
@   0x08 MO_TARM    tick word 0x20000480 when we last set the request byte
@   0x0C MO_SETL    1 while a settle time is pending
@   0x10 MO_TSET    tick from which an acquisition may be used (change tick + T + 10)
@   0x14 MO_FREQ, 0x18 MO_LEVEL, 0x1C MO_BIAS, 0x20 MO_SPEED, 0x24 MO_SCREEN: the watched words
@        as last seen; 0x28 MO_CODES: c5 | c6 << 8 | c8 << 16 as last seen
@   0x2C MO_SEQ     number of windows closed (published or, under hold, suppressed)
@   0x30 MO_CLS     class of the window: 0 noise-limited, 1 resolved
@   0x34 MO_OVL     consecutive overload acquisitions (at most 4)
@   0x38..0x8B      the window (cleared by meas_reset):
@   0x38 MO_CLSN    consecutive acquisitions of the other class
@   0x3C MO_N       accepted acquisitions
@   0x40 MO_PH      phase: 0 the start triple is collected, 1 resolved start test, 2 steady
@   0x44 MO_ST      slots of MO_BUF in use (phase 0: the start triple; phase 2: held outliers)
@   0x48 MO_REF     reference channel as a slot offset: 0 V, 8 I
@   0x4C MO_DROP    consecutive drops of the start test
@   0x50 MO_TFIRST  tick of the first accepted acquisition
@   0x54 MO_K       K = R[c8] G[c6] / G[c5] of the window (float)
@   0x58 MO_ZREF    Zref (re, im) of the start test
@   0x60 MO_MU      running mean of the accepted Zm (re, im)
@   0x68 MO_M2      sum of the squared complex distances (Welford)
@   0x6C MO_SUM     sum V'r, V'i, I'r, I'i; 0x7C MO_KAH: their Kahan compensations
@   0x8C MO_BUF     three slots of 24 bytes: Vr, Vi, Ir, Ii, Zr, Zi
@   0xD4 MO_X       the acquisition being processed, as a slot
@   0xEC MO_SIG     noise power of V and I (count^2, float)
@   0xF4 MO_S1      sum of the 128 codes of V and I (integer)
@   0xFC MO_FL      bit 0: Zm defined, bit 1: resolved (the acquisition being processed); bit 2:
@                   MO_TFIRST holds the tick of the previous window's close (set by meas_publish,
@                   cleared by meas_reset and by the first addition that uses it)
@
@ Register use: own_measure keeps r4 = OWN_MEAS and r5 = 0x2000057C (V_BLOCK) for all the
@ helpers below, which may also use s16..s31 freely (own_measure saves d8..d15); each helper
@ states the other registers it changes. Every vendor routine called keeps r4..r11 and s16..s31
@ (AAPCS; fn_08010700 pushes d8 / d9 itself).

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

@ ---- offsets in OWN_MEAS (MO_G in own.inc) ----
	.equ	MO_GEXP,	0x04
	.equ	MO_TARM,	0x08
	.equ	MO_SETL,	0x0C
	.equ	MO_TSET,	0x10
	.equ	MO_FREQ,	0x14
	.equ	MO_LEVEL,	0x18
	.equ	MO_BIAS,	0x1C
	.equ	MO_SPEED,	0x20
	.equ	MO_SCREEN,	0x24
	.equ	MO_CODES,	0x28
	.equ	MO_SEQ,		0x2C
	.equ	MO_CLS,		0x30
	.equ	MO_OVL,		0x34
	.equ	MO_CLSN,	0x38
	.equ	MO_N,		0x3C
	.equ	MO_PH,		0x40
	.equ	MO_ST,		0x44
	.equ	MO_REF,		0x48
	.equ	MO_DROP,	0x4C
	.equ	MO_TFIRST,	0x50
	.equ	MO_K,		0x54
	.equ	MO_ZREF,	0x58
	.equ	MO_MU,		0x60
	.equ	MO_M2,		0x68
	.equ	MO_SUM,		0x6C
	.equ	MO_KAH,		0x7C
	.equ	MO_BUF,		0x8C
	.equ	MO_X,		0xD4
	.equ	MO_SIG,		0xEC
	.equ	MO_S1,		0xF4
	.equ	MO_FL,		0xFC
	.equ	WIN_WORDS,	21		@ 0x38..0x8B: the words meas_reset clears
	.equ	SLOT,		24		@ bytes of one slot (Vr, Vi, Ir, Ii, Zr, Zi)
	.equ	FL_ANCHOR,	4		@ MO_FL bit 2: MO_TFIRST is the previous close

	.if	MO_FL + 4 > MEAS_SIZE
	.error	"meas.s: the state does not fit O_MEAS"
	.endif

@ ---- vendor words, as offsets from V_BLOCK = 0x2000057C ----
	.equ	VB_LEVEL,	0xBBC		@ 0x20001138 level (float volts)
	.equ	VB_BIAS,	0xBC0		@ 0x2000113C bias (float volts)
	.equ	VB_FREQ,	0xBC8		@ 0x20001144 frequency, Hz
	.equ	VB_SPEED,	0xBD4		@ 0x20001150 speed 0 / 1 / 2
	.equ	VB_RANGE,	0xBD0		@ 0x2000114C range 0 auto, 1..4 forced
	.equ	VB_CIRCUIT,	0xBD8		@ 0x20001154 circuit 0 auto, 1 series, 2 parallel
	.equ	VB_SCREEN,	0xBEC		@ 0x20001168 screen
	.equ	VB_CMP,		0xBFC		@ 0x20001178 compare quantity 1 R, 2 C, 3 L
	.equ	VB_HOLD,	0xC28		@ 0x200011A4 hold
	.equ	VB_C4,		0xC48		@ byte 0x200011C4 re-arm request (fn_080085d0)
	.equ	VB_C5,		0xC49		@ byte 0x200011C5 V gain code (fn_0800b20c)
	.equ	VB_C6,		0xC4A		@ byte 0x200011C6 I gain code (fn_0800b000)
	.equ	VB_C8,		0xC4C		@ byte 0x200011C8 range code (fn_0800b000)
	.equ	VB_MAX1,	0xC4E		@ halfword 0x200011CA ADC1 maximum (fn_08007fd4)
	.equ	VB_MIN1,	0xC50		@ halfword 0x200011CC ADC1 minimum
	.equ	VB_MAX2,	0xC56		@ halfword 0x200011D2 ADC2 maximum (fn_08007f38)
	.equ	VB_MIN2,	0xC58		@ halfword 0x200011D4 ADC2 minimum
	.equ	VB_MIDV,	0xC54		@ halfword 0x200011D0 ADC1 (min + max) / 2 (fn_08007fd4)
	.equ	VB_MIDI,	0xC5C		@ halfword 0x200011D8 ADC2 (min + max) / 2 (fn_08007f38)
	.equ	VB_SERPAR,	0xC70		@ 0x200011EC 0 series, 1 parallel values in use
	.equ	VB_RING,	0xC78		@ 0x200011F4 accepted count of the open window
	.equ	VB_MARK,	0xC80		@ 0x200011FC restart marker (fn_08009f10 clears it)
	.equ	VB_NEW,		0xC84		@ 0x20001200 new result
	.equ	VB_NR,		0xC8C		@ 0x20001208 no reading
	.equ	VB_NRCNT,	0xC90		@ 0x2000120C SysTick count without a reading
@ ---- result words, as offsets from V_RES = 0x20004D7C (the base fn_0800a068 uses) ----
	.equ	V_RES,		0x20004D7C
	.equ	VR_ZRAW,	0x314		@ 0x20005090 |Zm| of the last acquisition
	.equ	VR_THRAW,	0x318		@ 0x20005094 theta of the last acquisition
	.equ	VR_XS,		0x31C		@ 0x20005098
	.equ	VR_XP,		0x320		@ 0x2000509C
	.equ	VR_RS,		0x324		@ 0x200050A0
	.equ	VR_RP,		0x328		@ 0x200050A4
	.equ	VR_CS,		0x32C		@ 0x200050A8 nF
	.equ	VR_CP,		0x330		@ 0x200050AC
	.equ	VR_LS,		0x334		@ 0x200050B0 uH
	.equ	VR_LP,		0x338		@ 0x200050B4
	.equ	VR_R,		0x33C		@ 0x200050B8
	.equ	VR_C,		0x340		@ 0x200050BC
	.equ	VR_L,		0x344		@ 0x200050C0
	.equ	VR_Z,		0x348		@ 0x200050C4
	.equ	VR_X,		0x34C		@ 0x200050C8
	.equ	VR_TH,		0x350		@ 0x200050CC
	.equ	VR_Q,		0x354		@ 0x200050D0
	.equ	VR_D,		0x358		@ 0x200050D4
	.equ	VR_CMPV,	0x360		@ 0x200050DC
	.equ	VR_CALT,	0x364		@ 0x200050E0 calibration type (0 short)
	.equ	VR_511C,	0x3A0		@ 0x2000511C
@ ---- other addresses ----
	.equ	MS_TICK,	0x20000480	@ GUI tick, +10 per 10-ms SysTick (system_40.s 764-765)
	.equ	MS_REJ,		0x2000000A	@ byte: consecutive rejects; +1: presence byte
	.equ	MS_BUF_V,	0x20005A38	@ ADC1 buffer (DMA1 ch1): the DUT voltage
	.equ	MS_BUF_I,	0x20005B38	@ ADC2 buffer (DMA1 ch8): the DUT current
	.equ	DMA1_STS,	0x40020000	@ INTSTS; INTCLR at +4; DMA2 at +0x400
	.equ	DMA1_TXN1,	0x4002000C	@ TXNUM of DMA1 ch1; ch8 at +0x8C (0x40020098)
	.equ	DMA2_TXN5,	0x4002045C	@ TXNUM of DMA2 ch5
	.equ	TC_DMA1,	0x20000002	@ TXCF1 (bit 1) | TXCF8 (bit 29), as fn_08007e24 tests
	.equ	TC_DMA2,	0x00020000	@ TXCF5 (bit 17)
	.equ	EXP_MASK,	0x7F800000	@ exponent field of a float: all ones = Inf or NaN
	.equ	F_1E10,		0x501502F9	@ 1e10, the vendor's "0L" value (measure_33.s .L0800a7e4)
	.equ	F_M400,		0xC3C80000	@ -400.0, its theta (.L0800a7e0)
	.equ	F_OPEN,		0x4CD1CEF0	@ 1.1e8: the vendor's open exemption (fn_08008ea8)
	.equ	F_OPENDEF,	0x5368D4A5	@ 1e12: the default open entry (app_02.s .L0800b630)
	.equ	PH_OFF,		0x2D0		@ phase entries: + 0x2D0 from the |Z| entries (0x20000DF0)
	.equ	BIAS_LIM,	4		@ S4.4: midpoint counts for "steady" [J], marked for M6
	.equ	BIAS_MAX_MS,	30000		@ S4.4: publication resumes at the latest after this [J]
@ ---- offsets in the float table meas_ck (stage 4) ----
	.equ	CK_180,		0		@ 180.0
	.equ	CK_D2R,		4		@ pi / 180
	.equ	CK_1E5,		8		@ 1e5: the smallest usable open, ohm ([S10] p.5)
	.equ	CK_1EM12,	12		@ 1e-12 = (1e-6)^2: the guard of S4.1
@ ---- offsets in the float table meas_k ----
	.equ	K_Q12,		0		@ 1/12
	.equ	K_T12,		4		@ 64 * 12^2
	.equ	K_T8,		8		@ 64 * 8^2
	.equ	K_I128,		12		@ 1/128
	.equ	K_I64,		16		@ 1/64
	.equ	K_125,		20		@ 125
	.equ	K_1EM4,		24		@ 1e-4
	.equ	K_W,		28		@ 2 pi
	.equ	K_M1E9,		32		@ -1e9
	.equ	K_1E6,		36		@ 1e6
	.equ	K_SP1K,		40		@ 1000: parallel -> series below it (S2.6)
	.equ	K_SP10K,	44		@ 10000: series -> parallel above it
	.equ	K_SPMID,	48		@ 3162.28: the undecided start

@ ============================================================================
@ own_measure - one step of the measurement, called once per main-loop pass instead of
@   fn_0800a068. No arguments, no result; keeps every register AAPCS requires.
@   Order (S1.4): screen test; change and restart detection (meas_watch); the no-reading test;
@   then the acquisition handshake:
@   step 1: accept only when the request byte 0x200011C4 is 0, the generation G equals G_exp
@     (exactly one re-arm since our own request: the signed difference G - G_exp is 0), the three
@     counts TXNUM (DMA1 ch1, ch8, DMA2 ch5) are 0 and the three transfer-complete flags are set;
@     G - G_exp < 0 (ours not yet served) or anything not complete: return, test again next call;
@     G - G_exp > 0 (a foreign re-arm came after ours): the buffers are not ours, re-arm now;
@   step 2 / 3 (meas_acq): every use of the buffers, then G read again: changed = discarded;
@   step 4 (meas_arm): flags cleared, t_arm, G_exp = G + 1, request byte 1 (after an accepted or
@     discarded acquisition, after a restart and after the no-reading publish).
@   Returns at once, without the restart marker, when the screen word 0x20001168 is not 1, 2 or
@   3 (V1.1 dc:6085-6087).
@ ============================================================================
	.section .text.own.meas,"ax",%progbits
	.p2align 2
	.global	own_measure
	.thumb_func
	.type	own_measure, %function
own_measure:
	push	{r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	vpush	{d8, d9, d10, d11, d12, d13, d14, d15}
	ldr	r5, =V_BLOCK
	ldr	r4, =OWN_MEAS
	ldr	r0, [r5, #VB_SCREEN]
	subs	r0, r0, #1
	cmp	r0, #2
	bhi	.Lom_ret		@ screen 0 or another: nothing measured
	bl	meas_hold		@ S2.7: a latched hold ends at a change of its settings
	bl	meas_watch		@ r0 = 1: fn_08009f10 ran since the last call
	cmp	r0, #0
	bne	.Lom_arm		@ restart: our own request first (step 4)
	ldr	r0, [r5, #VB_NRCNT]
	cmp	r0, #200
	bls	.Lom_step1		@ 200 SysTicks = 2 s (V1.1 dc:6097-6098)
	movs	r0, #1
	str	r0, [r5, #VB_NR]	@ 0x20001208 = 1, as V1.1
	bl	meas_pub_nr		@ the no-reading set, 0x20001208 / 120C cleared, window reset
	b	.Lom_arm		@ and a fresh request (a stalled acquisition restarts)
.Lom_step1:
	ldrb	r0, [r5, #VB_C4]
	cmp	r0, #0
	bne	.Lom_mark		@ a re-arm is still requested: wait
	ldr	r6, [r4, #MO_G]		@ r6 = G, read once for this step
	ldr	r1, [r4, #MO_GEXP]
	subs	r1, r6, r1		@ d = G - G_exp (signed, wrap-safe)
	bmi	.Lom_mark		@ d < 0: our re-arm not served yet
	bne	.Lom_arm		@ d > 0: a foreign re-arm after ours: not our acquisition
	ldr	r0, =DMA1_TXN1
	ldr	r1, [r0]		@ DMA1 ch1 TXNUM
	ldr	r2, [r0, #0x8C]		@ DMA1 ch8 TXNUM (0x40020098)
	orrs	r1, r1, r2
	ldr	r2, =DMA2_TXN5
	ldr	r2, [r2]		@ DMA2 ch5 TXNUM
	orrs	r1, r1, r2
	bne	.Lom_mark		@ still transferring
	ldr	r0, =DMA1_STS
	ldr	r1, [r0]		@ DMA1 INTSTS
	ldr	r2, =TC_DMA1
	ands	r1, r1, r2
	cmp	r1, r2
	bne	.Lom_mark		@ TXCF1 or TXCF8 not set
	ldr	r1, [r0, #0x400]	@ DMA2 INTSTS
	tst	r1, #TC_DMA2
	beq	.Lom_mark		@ TXCF5 not set
	bl	meas_acq		@ steps 2 and 3 and the window
.Lom_arm:
	bl	meas_arm		@ step 4
.Lom_mark:
	movs	r0, #1
	str	r0, [r5, #VB_MARK]	@ 0x200011FC = 1: no restart since this call
.Lom_ret:
	vpop	{d8, d9, d10, d11, d12, d13, d14, d15}
	pop	{r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}

@ ----------------------------------------------------------------------------
@ meas_watch - change detection (S1.4 "Watched settings", "Restart detection", "On a change";
@   OWN_CAL_DESIGN.md 2.3). Compares frequency, level, bias, speed, screen and the codes c5 / c6
@   / c8 with the values seen last and stores the new ones; the restart marker 0x200011FC = 0,
@   and a calibration record loaded by a commit or rollback (ocal_restart_take), count as a
@   restart. Each change kind k (0 restart, 1 frequency, 2 level, 3 bias, 4 speed, 5 screen,
@   6 codes) takes SETTLE[k][fi] (ocal_settle; defaults 26 / 5 ms) and the longest wins
@   (meas_wkind: r7 = the time, r8 = its kind, the first found on a tie). Any change:
@   meas_change with r0 = the time, r1 = the kind (window reset, new settle deadline); a change
@   of kinds 0..4 also lets the AUTO class and series / parallel decide anew. A bias change
@   also starts the S4.4 wait (MF_BIASP = 1, MF_BT0 = the tick; meas_bias_wait).
@   Returns r0 = 1 when the restart marker was 0. Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_watch, %function
meas_watch:
	push	{r6, r7, r8, r9, r10, lr}	@ r10 only keeps the stack 8-byte aligned
	movs	r7, #0			@ r7 = settle time of the changes found, ms
	movs	r8, #0			@ r8 = the kind of r7
	movs	r9, #0			@ r9 = 1: a change of kinds 0..4
	ldr	r0, [r5, #VB_MARK]
	clz	r6, r0
	lsrs	r6, r6, #5		@ r6 = 1 when the marker is 0 (a restart)
	bl	ocal_restart_take	@ r0 = 1 once after a new calibration record
	orrs	r0, r0, r6
	beq	.Lmw_freq
	movs	r0, #0
	bl	meas_wkind		@ kind 0: restart
.Lmw_freq:
	ldr	r0, [r5, #VB_FREQ]
	ldr	r1, [r4, #MO_FREQ]
	cmp	r0, r1
	beq	.Lmw_level
	str	r0, [r4, #MO_FREQ]
	movs	r0, #1
	bl	meas_wkind		@ kind 1: frequency (SETTLE of the new one)
.Lmw_level:
	ldr	r0, [r5, #VB_LEVEL]
	ldr	r1, [r4, #MO_LEVEL]
	cmp	r0, r1
	beq	.Lmw_bias
	str	r0, [r4, #MO_LEVEL]
	movs	r0, #2
	bl	meas_wkind		@ kind 2: level
.Lmw_bias:
	ldr	r0, [r5, #VB_BIAS]
	ldr	r1, [r4, #MO_BIAS]
	cmp	r0, r1
	beq	.Lmw_speed
	str	r0, [r4, #MO_BIAS]
	movs	r0, #3
	bl	meas_wkind		@ kind 3: bias
	ldr	r1, =OWN_FUNC		@ S4.4: publication waits for steady DC midpoints
	movs	r0, #1
	str	r0, [r1, #MF_BIASP]
	ldr	r0, =MS_TICK
	ldr	r0, [r0]
	str	r0, [r1, #MF_BT0]
.Lmw_speed:
	ldr	r0, [r5, #VB_SPEED]
	ldr	r1, [r4, #MO_SPEED]
	cmp	r0, r1
	beq	.Lmw_screen
	str	r0, [r4, #MO_SPEED]
	movs	r0, #4
	bl	meas_wkind		@ kind 4: speed
.Lmw_screen:
	ldr	r0, [r5, #VB_SCREEN]
	ldr	r1, [r4, #MO_SCREEN]
	cmp	r0, r1
	beq	.Lmw_codes
	str	r0, [r4, #MO_SCREEN]
	movs	r0, #5
	bl	meas_wkind		@ kind 5: screen (the analog path is unchanged)
.Lmw_codes:
	bl	meas_codes
	ldr	r1, [r4, #MO_CODES]
	cmp	r0, r1
	beq	.Lmw_done
	str	r0, [r4, #MO_CODES]
	movs	r0, #6
	bl	meas_wkind		@ kind 6: range or gain ([S12] p.35)
.Lmw_done:
	cbz	r7, .Lmw_ret
	cmp	r9, #0
	beq	.Lmw_change
	ldr	r0, =OWN_FUNC		@ a setting change or a restart (S2.5, S2.6): AUTO class
	movs	r1, #0			@ and series / parallel decide anew
	str	r1, [r0, #MF_SP]
	str	r1, [r0, #MF_AUTO]
.Lmw_change:
	mov	r0, r7
	mov	r1, r8			@ the kind (meas_change stores it for the trace)
	bl	meas_change
.Lmw_ret:
	mov	r0, r6
	pop	{r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ meas_wkind - the maximum rule of meas_watch (OWN_CAL_DESIGN.md 2.3): r0 = change kind 0..6.
@   r7 = SETTLE[kind][fi] and r8 = the kind when that value is larger than r7 (so the first kind
@   found wins a tie); kinds 0..4 set r9 = 1. Works on meas_watch's r7..r9 and is called only
@   from it. Changes r0..r2, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_wkind, %function
meas_wkind:
	push	{r6, lr}
	mov	r6, r0
	cmp	r6, #5
	it	lo
	movlo	r9, #1
	bl	ocal_settle		@ r0 = ms (1..500; 26 / 5 for a frequency outside the list)
	cmp	r0, r7
	itt	hi
	movhi	r7, r0
	movhi	r8, r6
	pop	{r6, pc}

@ ----------------------------------------------------------------------------
@ meas_hold - S2.7 (design D1 / D2). Hold 0x200011A4 = 0: MF_HOLDP = 0. Hold set and MF_HOLDP 0
@   (hold went 0 -> 1, by the key 0x400, app_01.s 475-481, or HOLD, dset.s ds_hold): frequency,
@   level, bias, range, speed and circuit (0x20001144 / 38 / 3C / 4C / 50 / 54) latched in MF_HL,
@   MF_HOLDP = 1. Hold set and MF_HOLDP 1: any of the six differing from its latched value ends
@   the hold through ds_hold(0) (the HOLD object hidden, the restart request byte, as the key
@   release does) and MF_HOLDP = 0. Func and secondary are not watched (they show the held
@   measurement in another quantity). Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_hold, %function
meas_hold:
	push	{r6, r7, r8, lr}
	ldr	r6, =OWN_FUNC
	ldr	r0, [r5, #VB_HOLD]
	cbnz	r0, .Lmh_on
	str	r0, [r6, #MF_HOLDP]	@ no hold: nothing latched
	pop	{r6, r7, r8, pc}
.Lmh_on:
	ldr	r7, =hold_words
	add	r8, r6, #MF_HL
	ldr	r0, [r6, #MF_HOLDP]
	cbnz	r0, .Lmh_cmp
	movs	r2, #6
.Lmh_latch:
	ldrh	r1, [r7], #2		@ block offset of the word
	ldr	r0, [r5, r1]
	str	r0, [r8], #4
	subs	r2, r2, #1
	bne	.Lmh_latch
	movs	r0, #1
	str	r0, [r6, #MF_HOLDP]
	pop	{r6, r7, r8, pc}
.Lmh_cmp:
	movs	r2, #6
.Lmh_next:
	ldrh	r1, [r7], #2
	ldr	r0, [r5, r1]
	ldr	r3, [r8], #4
	cmp	r0, r3
	bne	.Lmh_end
	subs	r2, r2, #1
	bne	.Lmh_next
	pop	{r6, r7, r8, pc}	@ unchanged: the hold stays
.Lmh_end:
	movs	r0, #0
	str	r0, [r6, #MF_HOLDP]
	bl	ds_hold			@ r0 = 0: hold off (dset.s)
	pop	{r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ meas_codes - r0 = c5 | c6 << 8 | c8 << 16 (bytes 0x200011C5, C6, C8). Changes r0..r2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_codes, %function
meas_codes:
	ldrb	r0, [r5, #VB_C5]
	ldrb	r1, [r5, #VB_C6]
	ldrb	r2, [r5, #VB_C8]
	orr	r0, r0, r1, lsl #8
	orr	r0, r0, r2, lsl #16
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_change - a change: r0 = its settle time T in ms, r1 = its kind 0..6 (stored first in
@   the byte OCS_KIND of OWN_OCAL for the settle trace; an armed trace starts here,
@   ocal_trace_change). The deadline is now + T + 10 (the tick moves in steps of 10 once per
@   10 ms, so t_arm >= deadline means more than T ms really passed, S1.4). A deadline still
@   pending (1..T_max + 10 ms ahead of now, the longest a deadline can be ahead; T_max from
@   ocal_load, 26 with the defaults) that lies later is kept. Then the window is reset
@   (meas_reset, tail call). Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_change, %function
meas_change:
	ldr	r2, =OWN_OCAL + OCS_KIND
	strb	r1, [r2]		@ the kind of this change (OWN_CAL_DESIGN.md 2.3, G7)
	push	{r0, lr}
	bl	ocal_trace_change	@ changes r0..r3
	pop	{r0, lr}
	ldr	r1, =MS_TICK
	ldr	r1, [r1]		@ r1 = now
	adds	r0, r0, #10		@ r0 = T + 10
	ldr	r2, [r4, #MO_SETL]
	cbz	r2, .Lmc_new		@ nothing pending
	ldr	r2, [r4, #MO_TSET]
	subs	r2, r2, r1		@ r2 = old deadline - now
	subs	r3, r2, #1
	ldr	r12, =OWN_OCAL + OCS_TMAX
	ldr	r12, [r12]
	add	r12, r12, #10		@ T_max + 10
	cmp	r3, r12
	bhs	.Lmc_new		@ not 1..T_max + 10 ahead: the old one has passed
	cmp	r2, r0
	bgt	.Lmc_reset		@ the old deadline is later: kept
.Lmc_new:
	add	r1, r1, r0
	str	r1, [r4, #MO_TSET]
	movs	r1, #1
	str	r1, [r4, #MO_SETL]
.Lmc_reset:
	b	meas_reset

@ ----------------------------------------------------------------------------
@ meas_reset - the window starts again: MO_CLSN..MO_KAH cleared (counts, phase, start slots,
@   reference channel, drops, sums, mean, spread, first tick), the anchor bit of MO_FL cleared,
@   0x200011F4 = 0 and the reject byte 0x2000000A = 0. The class MO_CLS, the overload count and
@   the settle state are kept. Changes r0..r2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_reset, %function
meas_reset:
	movs	r0, #0
	add	r1, r4, #MO_CLSN
	movs	r2, #WIN_WORDS
.Lmr_clr:
	str	r0, [r1], #4
	subs	r2, r2, #1
	bne	.Lmr_clr
	ldr	r1, [r4, #MO_FL]
	bic	r1, r1, #FL_ANCHOR
	str	r1, [r4, #MO_FL]	@ the window starts at its first acquisition
	str	r0, [r5, #VB_RING]	@ 0x200011F4 = 0
	ldr	r1, =MS_REJ
	strb	r0, [r1]		@ 0x2000000A = 0
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_arm - step 4 of S1.4: the transfer-complete flags of DMA1 ch1 / ch8 (INTCLR 0x40020004)
@   and DMA2 ch5 (0x40020404) cleared, t_arm = tick, then with interrupts masked G_exp = G + 1
@   and the request byte 0x200011C4 = 1 (so the generation the next re-arm produces is exactly
@   the one expected; PRIMASK restored afterwards). Changes r0..r2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_arm, %function
meas_arm:
	ldr	r0, =DMA1_STS
	ldr	r1, =TC_DMA1
	str	r1, [r0, #4]		@ DMA1 INTCLR: TXCF1, TXCF8
	mov	r1, #TC_DMA2
	str	r1, [r0, #0x404]	@ DMA2 INTCLR: TXCF5
	ldr	r1, =MS_TICK
	ldr	r1, [r1]
	str	r1, [r4, #MO_TARM]	@ t_arm
	mrs	r2, PRIMASK
	cpsid	i
	ldr	r0, [r4, #MO_G]
	adds	r0, r0, #1
	str	r0, [r4, #MO_GEXP]	@ G_exp = G + 1
	movs	r0, #1
	strb	r0, [r5, #VB_C4]	@ request: the DMA interrupt re-arms at the next DAC period
	msr	PRIMASK, r2
	bx	lr

	.ltorg

@ ----------------------------------------------------------------------------
@ meas_acq - steps 2 and 3 for an acquisition that passed step 1; r6 = G as read in step 1.
@   The peak scans fn_08007f84 (ADC3), fn_08007fd4 (ADC1, r0 = p-p), fn_08007f38 (ADC2), then
@   saturation (ocal_clip: maximum >= CLIP hi or minimum <= CLIP lo, defaults 4095 / 0, S1.5, S4.5) with p-p 4095 for
@   the saturated channel, while OCAL_LOCK holds the codes meas_lockset, else the ranging calls fn_0800b20c (V) and, when it made no change,
@   fn_0800b000 (I and range).
@   Codes changed: a change of kind 6 with SETTLE[6][fi] (default 5 ms; the overload count ends).
@   Codes unchanged (in band, or no step left): 0x2000120C = 0, then
@   - saturated: one more overload acquisition; at the third in a row the window is reset and
@     the overload set published;
@   - not saturated after three or more overload acquisitions: a change (kind 6);
@   - a pending settle not yet over (t_arm before the deadline): discarded;
@   - else the two DFT bins (meas_dft), step 3 (G read again: a re-arm during the reads
@     discards it) and the window (meas_win).
@   Changes r0..r3, r12, s0..s31.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_acq, %function
meas_acq:
	push	{r7, r8, r9, r10, r11, lr}
	bl	fn_08007f84		@ ADC3: 0x200011DA..E0 (fn_0800b000 reads the p-p)
	bl	fn_08007fd4		@ ADC1: 0x200011CA..D0, r0 = p-p
	mov	r7, r0
	bl	fn_08007f38		@ ADC2: 0x200011D2..D8, r0 = p-p
	mov	r8, r0
	bl	ocal_clip		@ S4.5: r0 = bit 0 ADC1, bit 1 ADC2 saturated (CLIP limits;
	mov	r9, r0			@ the defaults 0 / 4095 are the stage-1 test)
	movw	r2, #4095
	tst	r9, #1
	it	ne
	movne	r7, r2			@ saturated V: "too big" for the ranging
	tst	r9, #2
	it	ne
	movne	r8, r2			@ saturated I
	bl	meas_codes
	mov	r10, r0			@ r10 = codes before the ranging
	bl	ocal_locked		@ r0 = the OCAL_LOCK word, 0 when not locked
	cbz	r0, .Lac_auto
	bl	meas_lockset		@ the locked codes; no ranging call (OWN_CAL_DESIGN.md 2.2)
	b	.Lac_ranged
.Lac_auto:
	mov	r0, r7
	bl	fn_0800b20c		@ V gain; 0 = it changed c5
	cbz	r0, .Lac_ranged
	mov	r0, r8
	bl	fn_0800b000		@ I gain and range
.Lac_ranged:
	bl	meas_codes
	cmp	r0, r10
	beq	.Lac_same
	str	r0, [r4, #MO_CODES]	@ our own ranging (or the lock): a change
	movs	r0, #0
	str	r0, [r4, #MO_OVL]
	movs	r0, #6
	bl	ocal_settle		@ S4.6: SETTLE[6][fi]
	movs	r1, #6			@ kind 6
	bl	meas_change
	b	.Lac_ret
.Lac_same:
	mov	r0, r9
	bl	meas_ocal_acq		@ the saturation note and the settle trace (2.2)
	movs	r0, #0
	str	r0, [r5, #VB_NRCNT]	@ an in-band acquisition: 0x2000120C = 0
	cmp	r9, #0
	beq	.Lac_unsat
	ldr	r0, [r4, #MO_OVL]
	adds	r0, r0, #1
	cmp	r0, #4
	it	hi
	movhi	r0, #4			@ counted up to 4 (3 = publish once)
	str	r0, [r4, #MO_OVL]
	cmp	r0, #3
	bne	.Lac_ret
	bl	meas_reset
	bl	meas_pub_ovl		@ the overload set, once
	bl	ocal_ovl_note		@ the next OCAL_RAW record: flags bit 1
	b	.Lac_ret
.Lac_unsat:
	ldr	r0, [r4, #MO_OVL]
	cbz	r0, .Lac_settle
	movs	r1, #0
	str	r1, [r4, #MO_OVL]
	cmp	r0, #3
	blo	.Lac_settle		@ a short run of saturated ones: no change
	movs	r0, #6
	bl	ocal_settle		@ S4.6: SETTLE[6][fi]
	movs	r1, #6			@ kind 6
	bl	meas_change		@ the overload ends: a change
	b	.Lac_ret
.Lac_settle:
	ldr	r0, [r4, #MO_SETL]
	cbz	r0, .Lac_dft
	ldr	r0, [r4, #MO_TARM]
	ldr	r1, [r4, #MO_TSET]
	subs	r0, r0, r1
	bmi	.Lac_ret		@ started before the settle time was over
	movs	r0, #0
	str	r0, [r4, #MO_SETL]
.Lac_dft:
	bl	meas_dft
	ldr	r0, [r4, #MO_G]
	subs	r0, r0, r6		@ step 3: G again
	bne	.Lac_ret		@ re-armed during the reads: discarded
	bl	meas_win
.Lac_ret:
	pop	{r7, r8, r9, r10, r11, pc}

@ ----------------------------------------------------------------------------
@ meas_lockset - OCAL_LOCK (OWN_CAL_DESIGN.md 2.2): r0 = the lock word (c5 | c6 << 8 | c8 << 16 |
@   1 << 24). Each code that differs from its byte is stored and its vendor setter called:
@   fn_0800b164 (c5 from 0x200011C5, src/app_02.s 221-224), fn_0800af58 (c6 from 0x200011C6,
@   src/app_01.s 1096-1099), fn_080093b8 (r0 = c8 after 0x200011C8 is stored, src/app_01.s
@   23-31). Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_lockset, %function
meas_lockset:
	push	{r6, lr}
	mov	r6, r0
	uxtb	r0, r6
	ldrb	r1, [r5, #VB_C5]
	cmp	r0, r1
	beq	.Lls_c6
	strb	r0, [r5, #VB_C5]
	bl	fn_0800b164		@ V gain from the byte
.Lls_c6:
	ubfx	r0, r6, #8, #8
	ldrb	r1, [r5, #VB_C6]
	cmp	r0, r1
	beq	.Lls_c8
	strb	r0, [r5, #VB_C6]
	bl	fn_0800af58		@ I gain from the byte
.Lls_c8:
	ubfx	r0, r6, #16, #8
	ldrb	r1, [r5, #VB_C8]
	cmp	r0, r1
	beq	.Lls_out
	strb	r0, [r5, #VB_C8]
	bl	fn_080093b8		@ the range, r0 = c8
.Lls_out:
	pop	{r6, pc}

@ ----------------------------------------------------------------------------
@ meas_kval - s0 = K = R[c8] G[c6] / G[c5] of the codes now (the tables of meas_win). Changes
@   r0, r1, s1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_kval, %function
meas_kval:
	ldrb	r0, [r5, #VB_C8]
	ldr	r1, =d_0802aeec		@ range resistors 100, 1k, 10k, 100k (words)
	ldr	r0, [r1, r0, lsl #2]
	vmov	s0, r0
	vcvt.f32.u32	s0, s0
	ldr	r1, =d_0802aee4		@ gains 1, 2, 4 .. 128 (bytes)
	ldrb	r0, [r5, #VB_C6]
	ldrb	r0, [r1, r0]
	vmov	s1, r0
	vcvt.f32.u32	s1, s1
	vmul.f32	s0, s0, s1
	ldrb	r0, [r5, #VB_C5]
	ldrb	r0, [r1, r0]
	vmov	s1, r0
	vcvt.f32.u32	s1, s1
	vdiv.f32	s0, s0, s1
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_ocal_acq - an acquisition whose codes did not change (meas_acq .Lac_same), r0 = its
@   saturation bits: ocal_sat_note; while the settle trace records (ocal_trace_on), meas_dft
@   for this acquisition (also when the settle rule will discard it; the window is not fed) and
@   one trace entry with K of the codes (meas_kval) and the flags bit 0 the settle rule
@   discards it (MO_SETL set and t_arm before MO_TSET), bit 1 saturated. Changes r0..r3, r12,
@   s0..s13.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_ocal_acq, %function
meas_ocal_acq:
	push	{r6, lr}
	mov	r6, r0
	bl	ocal_sat_note
	bl	ocal_trace_on
	cbz	r0, .Loa_out
	bl	meas_dft
	bl	meas_kval		@ s0 = K
	movs	r0, #0
	cmp	r6, #0
	it	ne
	movne	r0, #2			@ saturated
	ldr	r1, [r4, #MO_SETL]
	cbz	r1, .Loa_add
	ldr	r1, [r4, #MO_TARM]
	ldr	r2, [r4, #MO_TSET]
	subs	r1, r1, r2
	it	mi
	orrmi	r0, r0, #1		@ the settle rule discards it
.Loa_add:
	bl	ocal_trace_add
.Loa_out:
	pop	{r6, pc}

@ ----------------------------------------------------------------------------
@ meas_dft - S1.2 for both buffers: the bin k (1 below 10 kHz, 4 below 100 kHz, else 16, the
@   thresholds of fn_08007e7c) of V (0x20005A38) and I (0x20005B38) into MO_X (Vr, Vi, Ir, Ii),
@   their noise powers into MO_SIG and their code sums into MO_S1. Changes r0..r3, r12,
@   s0..s13.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_dft, %function
meas_dft:
	push	{r7, lr}
	ldr	r0, [r5, #VB_FREQ]
	movs	r7, #1
	movw	r1, #10000
	cmp	r0, r1
	blt	.Ldf_k
	movs	r7, #4
	ldr	r1, =100000
	cmp	r0, r1
	blt	.Ldf_k
	movs	r7, #16
.Ldf_k:
	ldr	r0, =MS_BUF_V
	mov	r1, r7
	bl	meas_bin
	vstr	s0, [r4, #MO_X]
	vstr	s1, [r4, #MO_X + 4]
	vstr	s2, [r4, #MO_SIG]
	str	r0, [r4, #MO_S1]
	ldr	r0, =MS_BUF_I
	mov	r1, r7
	bl	meas_bin
	vstr	s0, [r4, #MO_X + 8]
	vstr	s1, [r4, #MO_X + 12]
	vstr	s2, [r4, #MO_SIG + 4]
	str	r0, [r4, #MO_S1 + 4]
	pop	{r7, pc}

@ ----------------------------------------------------------------------------
@ meas_bin - one channel: r0 = 128 signed halfwords (the right-aligned 12-bit codes), r1 = k.
@   Pass 1: S1 = sum of the codes (integer, < 2^24) and the mean m = S1 / 128 (exact in float).
@   Pass 2: X = sum (x[n] - m) (cos(2 pi k n / 128) - j sin(2 pi k n / 128)), with
@     cos = c[j], sin = c[(j - 32) & 127], j = k n & 127 (table meas_cos); x - m is exact, so a
@     constant buffer gives X = 0 exactly; the mean does not change bin k >= 1 (orthogonal over
@     128 samples).
@   Pass 3: sigma^2 = sum e[n]^2 / 125, e = (x - m) - (Xr c[j] - Xi s[j]) / 64 (the residual
@     after the mean and the fitted bin-k sine; a sum of rounded squares, never negative).
@   Returns s0 = Xr, s1 = Xi, s2 = sigma^2, r0 = S1. Changes r1..r3, r12, s0..s13.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_bin, %function
meas_bin:
	push	{r4, r5, r6, lr}
	movs	r4, #0			@ r4 = S1
	movs	r3, #0			@ r3 = n
.Lbn_sum:
	ldrsh	r5, [r0, r3, lsl #1]
	adds	r4, r4, r5
	adds	r3, r3, #1
	cmp	r3, #128
	blo	.Lbn_sum
	ldr	r6, =meas_k
	vmov	s8, r4
	vcvt.f32.s32	s8, s8
	vldr	s9, [r6, #K_I128]
	vmul.f32	s8, s8, s9	@ s8 = m = S1 / 128
	vldr	s10, [r6, #K_I64]	@ s10 = 1 / 64
	ldr	r2, =meas_cos
	movs	r6, #0
	vmov	s4, r6			@ s4 = Xr
	vmov	s5, r6			@ s5 = sum (x - m) sin = -Xi
	movs	r3, #0			@ r3 = j
	mov	r12, #0			@ r12 = n
.Lbn_bin:
	ldrsh	r5, [r0, r12, lsl #1]
	vmov	s6, r5
	vcvt.f32.s32	s6, s6
	vsub.f32	s6, s6, s8	@ x - m
	add	r6, r2, r3, lsl #2
	vldr	s7, [r6]		@ cos
	vmla.f32	s4, s6, s7
	sub	r6, r3, #32
	and	r6, r6, #127
	add	r6, r2, r6, lsl #2
	vldr	s7, [r6]		@ sin
	vmla.f32	s5, s6, s7
	add	r3, r3, r1
	and	r3, r3, #127
	add	r12, r12, #1
	cmp	r12, #128
	blo	.Lbn_bin
	movs	r6, #0
	vmov	s11, r6			@ s11 = sum e^2
	movs	r3, #0
	mov	r12, #0
.Lbn_res:
	ldrsh	r5, [r0, r12, lsl #1]
	vmov	s6, r5
	vcvt.f32.s32	s6, s6
	vsub.f32	s6, s6, s8	@ x - m
	add	r6, r2, r3, lsl #2
	vldr	s7, [r6]		@ cos
	sub	r6, r3, #32
	and	r6, r6, #127
	add	r6, r2, r6, lsl #2
	vldr	s12, [r6]		@ sin
	vmul.f32	s13, s4, s7
	vmla.f32	s13, s5, s12	@ Xr cos - Xi sin (Xi = -s5)
	vmul.f32	s13, s13, s10	@ / 64: the fitted sine
	vsub.f32	s6, s6, s13	@ e
	vmla.f32	s11, s6, s6
	add	r3, r3, r1
	and	r3, r3, #127
	add	r12, r12, #1
	cmp	r12, #128
	blo	.Lbn_res
	ldr	r6, =meas_k
	vldr	s12, [r6, #K_125]
	vdiv.f32	s2, s11, s12	@ sigma^2 = sum e^2 / 125 (128 - 3 fitted values)
	vmov.f32	s0, s4
	vneg.f32	s1, s5
	mov	r0, r4
	pop	{r4, r5, r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ meas_win - S1.3 for the acquisition in MO_X.
@   K = R[c8] G[c6] / G[c5] (tables 0x0802AEEC, 0x0802AEE4, as measure_33.s .L0800a28e).
@   Class: resolved when |X|^2 >= 64 T^2 max(sigma^2, 1/12) on both channels, T = 12 to enter
@   and 8 to stay (window class resolved), and Zm is defined.
@   Zm = K V conj(I) / |I|^2 when |I|^2 > 0 and the result is finite, else 0 and not defined;
@   0x20005090 = |Zm| and 0x20005094 = its angle in degrees (only when defined).
@   An empty window takes the acquisition's class. Otherwise an acquisition of the other class
@   is not used; the third in a row is a part change (class set, window reset).
@   Then by phase: 0 the acquisition is held in the next start slot (the third completes the
@   start, meas_start); 1 the start test (meas_test); 2 added (noise-limited) or the outlier
@   rule (meas_outlier). Changes r0..r3, r12, s0..s31.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_win, %function
meas_win:
	push	{r6, r7, r8, lr}
	ldr	r8, =meas_k
	ldrb	r0, [r5, #VB_C8]
	ldr	r1, =d_0802aeec		@ range resistors 100, 1k, 10k, 100k (words)
	ldr	r0, [r1, r0, lsl #2]
	vmov	s0, r0
	vcvt.f32.u32	s0, s0
	ldr	r1, =d_0802aee4		@ gains 1, 2, 4 .. 128 (bytes)
	ldrb	r0, [r5, #VB_C6]
	ldrb	r0, [r1, r0]
	vmov	s1, r0
	vcvt.f32.u32	s1, s1
	vmul.f32	s0, s0, s1
	ldrb	r0, [r5, #VB_C5]
	ldrb	r0, [r1, r0]
	vmov	s1, r0
	vcvt.f32.u32	s1, s1
	vdiv.f32	s16, s0, s1	@ s16 = K
	vstr	s16, [r4, #MO_K]
	@ class of this acquisition
	ldr	r0, [r4, #MO_CLS]
	vldr	s2, [r8, #K_T12]	@ 64 * 12^2
	cbz	r0, .Lwn_thr
	vldr	s2, [r8, #K_T8]		@ 64 * 8^2: stay resolved
.Lwn_thr:
	vldr	s3, [r8, #K_Q12]	@ 1/12
	movs	r6, #1			@ r6 = 1 while resolved
	add	r7, r4, #MO_X
	vldr	s4, [r4, #MO_SIG]
	vldr	s5, [r7, #0]
	vldr	s6, [r7, #4]
	bl	meas_snr		@ V
	vldr	s4, [r4, #MO_SIG + 4]
	vldr	s5, [r7, #8]
	vldr	s6, [r7, #12]
	bl	meas_snr		@ I
	@ Zm
	vldr	s0, [r7, #0]		@ Vr
	vldr	s1, [r7, #4]		@ Vi
	vldr	s2, [r7, #8]		@ Ir
	vldr	s3, [r7, #12]		@ Ii
	movs	r0, #0
	vmov	s5, r0
	vmov	s6, r0			@ Zm = 0 until it is defined
	vmul.f32	s4, s2, s2
	vmla.f32	s4, s3, s3	@ |I|^2
	vcmp.f32	s4, #0
	vmrs	APSR_nzcv, fpscr
	beq	.Lwn_nozm
	vmul.f32	s5, s0, s2
	vmla.f32	s5, s1, s3	@ Re V conj(I) = Vr Ir + Vi Ii
	vmul.f32	s6, s1, s2
	vmls.f32	s6, s0, s3	@ Im V conj(I) = Vi Ir - Vr Ii
	vdiv.f32	s5, s5, s4
	vdiv.f32	s6, s6, s4
	vmul.f32	s5, s5, s16	@ Zr
	vmul.f32	s6, s6, s16	@ Zi
	vmov	r0, s5
	and	r0, r0, #EXP_MASK
	cmp	r0, #EXP_MASK
	beq	.Lwn_inf
	vmov	r0, s6
	and	r0, r0, #EXP_MASK
	cmp	r0, #EXP_MASK
	beq	.Lwn_inf
	vstr	s5, [r7, #16]
	vstr	s6, [r7, #20]
	ldr	r1, =V_RES
	vmul.f32	s7, s5, s5
	vmla.f32	s7, s6, s6
	vsqrt.f32	s7, s7
	vstr	s7, [r1, #VR_ZRAW]	@ 0x20005090 = |Zm|
	movs	r0, #0
	vmov	s0, r0			@ angle 0 for Zm = 0
	vcmp.f32	s7, #0
	vmrs	APSR_nzcv, fpscr
	beq	.Lwn_th
	vmov.f32	s0, s6
	vmov.f32	s1, s5
	bl	meas_deg
.Lwn_th:
	ldr	r1, =V_RES
	vstr	s0, [r1, #VR_THRAW]	@ 0x20005094 = angle of Zm
	movs	r0, #1			@ r0 = 1: Zm defined
	b	.Lwn_fl
.Lwn_inf:
	movs	r0, #0
	vmov	s5, r0
	vmov	s6, r0
.Lwn_nozm:
	vstr	s5, [r7, #16]
	vstr	s6, [r7, #20]
	movs	r0, #0
.Lwn_fl:
	and	r6, r6, r0		@ resolved needs Zm
	ldr	r1, [r4, #MO_FL]
	bic	r1, r1, #3
	orr	r1, r1, r0
	orr	r1, r1, r6, lsl #1
	str	r1, [r4, #MO_FL]	@ bits 0 / 1 of this acquisition, the anchor bit kept
	@ class of the window
	ldr	r0, [r4, #MO_N]
	ldr	r1, [r4, #MO_ST]
	orrs	r0, r0, r1
	ldr	r1, [r4, #MO_PH]
	orrs	r0, r0, r1
	bne	.Lwn_cls
	str	r6, [r4, #MO_CLS]	@ an empty window takes this class
	b	.Lwn_phase
.Lwn_cls:
	ldr	r0, [r4, #MO_CLS]
	cmp	r0, r6
	beq	.Lwn_same
	ldr	r0, [r4, #MO_CLSN]
	adds	r0, r0, #1
	str	r0, [r4, #MO_CLSN]
	cmp	r0, #3
	blo	.Lwn_ret		@ another class: not used
	str	r6, [r4, #MO_CLS]	@ held 3 times: a part change
	bl	meas_reset
	b	.Lwn_ret
.Lwn_same:
	movs	r0, #0
	str	r0, [r4, #MO_CLSN]
.Lwn_phase:
	ldr	r0, [r4, #MO_PH]
	cmp	r0, #1
	beq	.Lwn_test
	bhi	.Lwn_steady
	ldr	r6, [r4, #MO_ST]	@ phase 0: hold it in slot MO_ST
	add	r1, r4, #MO_BUF
	add	r2, r6, r6, lsl #1
	add	r1, r1, r2, lsl #3
	mov	r0, r7
	movs	r2, #6
	bl	meas_copyw
	adds	r6, r6, #1
	str	r6, [r4, #MO_ST]
	cmp	r6, #3
	blo	.Lwn_ret
	bl	meas_start
	b	.Lwn_ret
.Lwn_test:
	mov	r0, r7
	bl	meas_test
	b	.Lwn_ret
.Lwn_steady:
	ldr	r0, [r4, #MO_CLS]
	cbnz	r0, .Lwn_res
	mov	r0, r7
	bl	meas_add		@ noise-limited: every one counts
	b	.Lwn_ret
.Lwn_res:
	bl	meas_outlier
.Lwn_ret:
	pop	{r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ meas_snr - one channel of the class test: s2 = 64 T^2, s3 = 1/12, s4 = sigma^2, s5 / s6 =
@   Xr / Xi. Clears r6 when |X|^2 < 64 T^2 max(sigma^2, 1/12) (S/N below T). Changes s4, s7.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_snr, %function
meas_snr:
	vcmpe.f32	s4, s3
	vmrs	APSR_nzcv, fpscr
	it	lt
	vmovlt.f32	s4, s3		@ the 1-count quantiser floor
	vmul.f32	s4, s4, s2
	vmul.f32	s7, s5, s5
	vmla.f32	s7, s6, s6
	vcmpe.f32	s7, s4
	vmrs	APSR_nzcv, fpscr
	it	lt
	movlt	r6, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_start - the three start slots MO_BUF are complete (S1.3 "Start of a window"): the
@   reference channel is the one with the larger sum |X| over them (V on a tie). Resolved
@   class: Zref = their component-wise median, phase 1, each slot through the start test.
@   Noise-limited class: phase 2, all three added. MO_ST = 0 first (in phase 2 it counts held
@   outliers). Changes r0..r3, r12, s0..s31.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_start, %function
meas_start:
	push	{r6, r7, r8, lr}
	add	r6, r4, #MO_BUF
	movs	r0, #0
	vmov	s16, r0			@ s16 = sum |XV|
	vmov	s17, r0			@ s17 = sum |XI|
	mov	r7, r6
	movs	r8, #3
.Lst_ref:
	vldr	s0, [r7, #0]
	vldr	s1, [r7, #4]
	vmul.f32	s2, s0, s0
	vmla.f32	s2, s1, s1
	vsqrt.f32	s2, s2
	vadd.f32	s16, s16, s2
	vldr	s0, [r7, #8]
	vldr	s1, [r7, #12]
	vmul.f32	s2, s0, s0
	vmla.f32	s2, s1, s1
	vsqrt.f32	s2, s2
	vadd.f32	s17, s17, s2
	adds	r7, r7, #SLOT
	subs	r8, r8, #1
	bne	.Lst_ref
	vcmpe.f32	s16, s17
	vmrs	APSR_nzcv, fpscr
	ite	ge
	movge	r0, #0			@ V
	movlt	r0, #8			@ I
	str	r0, [r4, #MO_REF]
	movs	r0, #0
	str	r0, [r4, #MO_ST]
	movs	r7, #0			@ r7 = slot index
	ldr	r0, [r4, #MO_CLS]
	cbz	r0, .Lst_noise
	mov	r0, r6
	bl	meas_median
	vstr	s0, [r4, #MO_ZREF]
	vstr	s1, [r4, #MO_ZREF + 4]
	movs	r0, #1
	str	r0, [r4, #MO_PH]
.Lst_test:
	add	r0, r7, r7, lsl #1
	add	r0, r6, r0, lsl #3
	bl	meas_test
	cbnz	r0, .Lst_ret		@ the start was reset
	adds	r7, r7, #1
	cmp	r7, #3
	blo	.Lst_test
	b	.Lst_ret
.Lst_noise:
	movs	r0, #2
	str	r0, [r4, #MO_PH]
.Lst_add:
	add	r0, r7, r7, lsl #1
	add	r0, r6, r0, lsl #3
	bl	meas_add
	cbnz	r0, .Lst_ret		@ the window closed
	adds	r7, r7, #1
	cmp	r7, #3
	blo	.Lst_add
.Lst_ret:
	pop	{r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ meas_test - the start test of the resolved class for the slot r0: it passes when |Zm| is at
@   least 1.1e8 (the vendor's open exemption) or |Zm - Zref| <= 0.5 |Zref| (the 50 % rule of
@   fn_08008ea8, complex); a pass is added (the start ends at 3 accepted: phase 2), a drop
@   counts, and the third drop in a row resets the window (a new start, Zref and reference).
@   Returns r0 = 1 when the window was reset or closed (the caller stops), else 0.
@   Changes r1..r3, r12, s0..s31.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_test, %function
meas_test:
	push	{r6, lr}
	mov	r6, r0
	bl	meas_exempt
	cbnz	r0, .Lts_pass
	mov	r0, r6
	add	r1, r4, #MO_ZREF
	bl	meas_dist2		@ s0 = |Zm - Zref|^2
	vldr	s2, [r4, #MO_ZREF]
	vldr	s3, [r4, #MO_ZREF + 4]
	vmul.f32	s1, s2, s2
	vmla.f32	s1, s3, s3
	vmov.f32	s2, #0.25
	vmul.f32	s1, s1, s2	@ (0.5 |Zref|)^2
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	bls	.Lts_pass
	bl	meas_rej_inc
	ldr	r0, [r4, #MO_DROP]
	adds	r0, r0, #1
	str	r0, [r4, #MO_DROP]
	cmp	r0, #3
	blo	.Lts_open
	bl	meas_reset		@ 3 drops in a row: the start begins again
	movs	r0, #1
	pop	{r6, pc}
.Lts_pass:
	movs	r0, #0
	str	r0, [r4, #MO_DROP]
	ldr	r1, =MS_REJ
	strb	r0, [r1]
	mov	r0, r6
	bl	meas_add
	cbnz	r0, .Lts_stop
	ldr	r0, [r4, #MO_N]
	cmp	r0, #3
	blo	.Lts_open
	movs	r0, #2
	str	r0, [r4, #MO_PH]	@ 3 accepted: the start is over
.Lts_open:
	movs	r0, #0
	pop	{r6, pc}
.Lts_stop:
	movs	r0, #1
	pop	{r6, pc}

@ ----------------------------------------------------------------------------
@ meas_outlier - phase 2 of the resolved class for MO_X (S1.3 "Resolved acquisitions"): with
@   L^2 = max(25 s^2, 1e-4 |mu|^2), an acquisition with |Zm| >= 1.1e8 or |Zm - mu|^2 <= L^2 is
@   added; else it is an outlier, held in slot MO_ST. The third held outlier: when all three lie
@   within L of their component-wise median it is a part change (window reset, the three are the
@   new start: meas_start); else the oldest is dropped (slots 1, 2 move to 0, 1).
@   Changes r0..r3, r12, s0..s31.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_outlier, %function
meas_outlier:
	push	{r6, r7, r8, lr}
	add	r7, r4, #MO_X
	mov	r0, r7
	bl	meas_exempt
	cmp	r0, #0
	bne	.Lou_in
	bl	meas_lim2
	vmov.f32	s16, s0		@ s16 = L^2
	mov	r0, r7
	add	r1, r4, #MO_MU
	bl	meas_dist2
	vcmpe.f32	s0, s16
	vmrs	APSR_nzcv, fpscr
	bls	.Lou_in
	bl	meas_rej_inc		@ an outlier: not in the sums
	ldr	r6, [r4, #MO_ST]
	add	r1, r4, #MO_BUF
	add	r2, r6, r6, lsl #1
	add	r1, r1, r2, lsl #3
	mov	r0, r7
	movs	r2, #6
	bl	meas_copyw
	adds	r6, r6, #1
	str	r6, [r4, #MO_ST]
	cmp	r6, #3
	blo	.Lou_ret
	add	r0, r4, #MO_BUF
	bl	meas_median
	sub	sp, sp, #8
	vstr	s0, [sp]
	vstr	s1, [sp, #4]		@ their median
	movs	r6, #0
.Lou_chk:
	add	r0, r6, r6, lsl #1
	add	r0, r4, r0, lsl #3
	add	r0, r0, #MO_BUF
	mov	r1, sp
	bl	meas_dist2
	vcmpe.f32	s0, s16
	vmrs	APSR_nzcv, fpscr
	bhi	.Lou_keep		@ not all within L: no part change
	adds	r6, r6, #1
	cmp	r6, #3
	blo	.Lou_chk
	add	sp, sp, #8
	bl	meas_reset		@ a part change: the three start the new window
	movs	r0, #3
	str	r0, [r4, #MO_ST]
	bl	meas_start
	b	.Lou_ret
.Lou_keep:
	add	sp, sp, #8
	add	r0, r4, #MO_BUF + SLOT
	add	r1, r4, #MO_BUF
	movs	r2, #12
	bl	meas_copyw		@ the oldest dropped
	movs	r0, #2
	str	r0, [r4, #MO_ST]
	b	.Lou_ret
.Lou_in:
	movs	r0, #0
	str	r0, [r4, #MO_ST]
	ldr	r1, =MS_REJ
	strb	r0, [r1]
	mov	r0, r7
	bl	meas_add
.Lou_ret:
	pop	{r6, r7, r8, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ meas_add - adds the slot r0 to the window (S1.3): u = conj(X_ref) / |X_ref| of the reference
@   channel (1 when |X_ref| = 0), V' = V u and I' = I u into the four Kahan sums; in the resolved
@   class Zm into the running mean and spread (Welford, complex distance); N + 1 (also to
@   0x200011F4); the window's start tick: the tick of its first addition, or, for a window that
@   follows a close directly (MO_FL anchor bit), the tick of that close (so the publish's display
@   update, about 0.12 s of main-loop time in the emulator, does not lengthen the period); at
@   N >= 3 and T_win (1000 / 500 / 250 ms for speed 0 / 1 / other, the manual's 1 / 2 / 4
@   readings per second) since the start tick: meas_publish.
@   Returns r0 = 1 when the window closed (published and reset), else 0.
@   Changes r1..r3, r12, s0..s31.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_add, %function
meas_add:
	push	{r6, lr}
	mov	r6, r0
	ldr	r1, [r4, #MO_REF]
	add	r1, r6, r1
	vldr	s0, [r1]		@ reference re
	vldr	s1, [r1, #4]		@ reference im
	vmul.f32	s2, s0, s0
	vmla.f32	s2, s1, s1
	vsqrt.f32	s2, s2
	vcmp.f32	s2, #0
	vmrs	APSR_nzcv, fpscr
	bne	.Lad_u
	vmov.f32	s0, #1.0	@ u = 1
	movs	r0, #0
	vmov	s1, r0
	b	.Lad_rot
.Lad_u:
	vdiv.f32	s0, s0, s2	@ ur = re / |X_ref|
	vdiv.f32	s1, s1, s2
	vneg.f32	s1, s1		@ ui = -im / |X_ref|
.Lad_rot:
	vldr	s2, [r6, #0]		@ Vr
	vldr	s3, [r6, #4]		@ Vi
	vmul.f32	s4, s2, s0
	vmls.f32	s4, s3, s1	@ V'r = Vr ur - Vi ui
	vmul.f32	s5, s2, s1
	vmla.f32	s5, s3, s0	@ V'i = Vr ui + Vi ur
	vldr	s2, [r6, #8]		@ Ir
	vldr	s3, [r6, #12]		@ Ii
	vmul.f32	s6, s2, s0
	vmls.f32	s6, s3, s1	@ I'r
	vmul.f32	s7, s2, s1
	vmla.f32	s7, s3, s0	@ I'i
	sub	sp, sp, #16
	vstmia	sp, {s4-s7}
	add	r0, r4, #MO_SUM
	mov	r1, sp
	movs	r2, #4
.Lad_kahan:
	vldr	s8, [r1]		@ v
	vldr	s9, [r0]		@ sum
	vldr	s10, [r0, #MO_KAH - MO_SUM]	@ c
	vsub.f32	s11, s8, s10	@ y = v - c
	vadd.f32	s12, s9, s11	@ t = sum + y
	vsub.f32	s13, s12, s9
	vsub.f32	s10, s13, s11	@ c = (t - sum) - y
	vstr	s12, [r0]
	vstr	s10, [r0, #MO_KAH - MO_SUM]
	adds	r0, r0, #4
	adds	r1, r1, #4
	subs	r2, r2, #1
	bne	.Lad_kahan
	add	sp, sp, #16
	ldr	r0, [r4, #MO_N]
	adds	r0, r0, #1
	str	r0, [r4, #MO_N]
	str	r0, [r5, #VB_RING]	@ 0x200011F4 = N
	ldr	r1, [r4, #MO_CLS]
	cbz	r1, .Lad_time
	vmov	s0, r0
	vcvt.f32.u32	s0, s0		@ n
	vldr	s1, [r6, #16]
	vldr	s2, [r6, #20]
	vldr	s3, [r4, #MO_MU]
	vldr	s4, [r4, #MO_MU + 4]
	vsub.f32	s5, s1, s3	@ d = z - mu
	vsub.f32	s6, s2, s4
	vdiv.f32	s7, s5, s0
	vdiv.f32	s8, s6, s0
	vadd.f32	s3, s3, s7	@ mu + d / n
	vadd.f32	s4, s4, s8
	vstr	s3, [r4, #MO_MU]
	vstr	s4, [r4, #MO_MU + 4]
	vsub.f32	s7, s1, s3	@ d2 = z - new mu
	vsub.f32	s8, s2, s4
	vldr	s9, [r4, #MO_M2]
	vmla.f32	s9, s5, s7
	vmla.f32	s9, s6, s8	@ M2 + Re(d conj(d2))
	vstr	s9, [r4, #MO_M2]
.Lad_time:
	ldr	r1, =MS_TICK
	ldr	r1, [r1]
	cmp	r0, #1
	bne	.Lad_close
	ldr	r2, [r4, #MO_FL]
	tst	r2, #FL_ANCHOR
	bne	.Lad_anchor		@ follows a close: timed from that close
	str	r1, [r4, #MO_TFIRST]	@ the first one
	b	.Lad_close
.Lad_anchor:
	bic	r2, r2, #FL_ANCHOR
	str	r2, [r4, #MO_FL]
.Lad_close:
	cmp	r0, #3
	blo	.Lad_open
	ldr	r2, [r4, #MO_TFIRST]
	subs	r1, r1, r2		@ time since the first one
	ldr	r2, [r5, #VB_SPEED]
	movw	r3, #1000
	cbz	r2, .Lad_win
	movw	r3, #500
	cmp	r2, #1
	beq	.Lad_win
	movs	r3, #250
.Lad_win:
	cmp	r1, r3
	blo	.Lad_open
	bl	meas_publish
	movs	r0, #1
	pop	{r6, pc}
.Lad_open:
	movs	r0, #0
	pop	{r6, pc}

@ ----------------------------------------------------------------------------
@ meas_publish - the window closes (S1.3 "Publish", S1.7, S1.8). MO_SEQ + 1. Under hold
@   nothing is written, nor while S4.4 waits for steady DC midpoints after a bias change
@   (meas_bias_wait). Else: sum I' = 0 gives the no-reading set; Zbar = K sum V' / sum I';
@   with OCAL GAIN for the cell (ocal_gain) Zbar = K zeta nu sum V' / sum I' and no decade
@   interpolation / S4.2 (K) references; the OCAL_RAW record is taken first (ocal_raw);
@   Re, Im or |Zbar| not finite gives the overload set; theta = atan2(Im, Re) in degrees (0 for
@   Zbar = 0, cos 1, sin 0), cos = Re / |Zbar|, sin = Im / |Zbar|. On screens 1 and 2 the
@   complex open / short compensation of stage 4 (meas_comp, S4.1 with S4.2 option (K)) gives
@   |Z|c, theta, cos and sin from Zdut, or the overload set at its guard; where it cannot be
@   used (meas_comp r0 = 0) and on screen 3 the magnitude chain of
@   fn_0800a068: |Z|c = |Zbar| on screen 3 with calibration type 0, else |Zbar| minus the short
@   entry of fn_080090a4(frequency, level), and on screens 1 and 2 the decade interpolation
@   (meas_interp). Then |Z|c to 0x200050C4, theta to 0x200050CC, Rs = |Z|c cos, Xs = |Z|c sin,
@   Rp = |Z|c / cos, Xp = |Z|c / sin (signed infinity for a zero divisor), Cs / Cp = -1e9 /
@   (w Xs / Xp), Ls / Lp = Xs / Xp 1e6 / w (w = 2 pi f), Q = 0 for Xs = 0, +Inf for Rs = 0, else
@   |Xs / Rs|; D = 0 for Rs = 0, +Inf for Xs = 0, else |Rs / Xs|; series / parallel: circuit 1
@   series, 2 parallel, 0 by meas_serpar (S2.6, with hysteresis); the calibration entry of 60 Hz
@   is the 100 Hz entry of the level (S2.12); then meas_tail. Always ends with meas_reset, then MO_TFIRST = the tick now and the anchor bit set
@   (the next window is timed from this close). Changes r0..r3, r12, s0..s31.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_publish, %function
meas_publish:
	push	{r6, r7, r8, lr}
	ldr	r0, [r4, #MO_SEQ]
	adds	r0, r0, #1
	str	r0, [r4, #MO_SEQ]
	bl	ocal_raw		@ the OCAL_RAW record of every close, also under hold (2.2)
	ldr	r0, [r5, #VB_HOLD]
	cmp	r0, #0
	bne	.Lpb_reset		@ hold: the display keeps its values
	bl	meas_bias_wait		@ S4.4: r0 = 1 while the DC midpoints still move
	cmp	r0, #0
	bne	.Lpb_reset		@ the window is not published
	vldr	s0, [r4, #MO_SUM]	@ V'r
	vldr	s1, [r4, #MO_SUM + 4]	@ V'i
	vldr	s2, [r4, #MO_SUM + 8]	@ I'r
	vldr	s3, [r4, #MO_SUM + 12]	@ I'i
	vcmp.f32	s2, #0
	vmrs	APSR_nzcv, fpscr
	bne	.Lpb_div
	vcmp.f32	s3, #0
	vmrs	APSR_nzcv, fpscr
	bne	.Lpb_div
	bl	meas_pub_nr		@ no current at all: no reading
	b	.Lpb_reset
.Lpb_div:
	vmul.f32	s4, s2, s2
	vmla.f32	s4, s3, s3	@ |I'|^2
	vmul.f32	s5, s0, s2
	vmla.f32	s5, s1, s3
	vmul.f32	s6, s1, s2
	vmls.f32	s6, s0, s3
	vldr	s7, [r4, #MO_K]
	vdiv.f32	s5, s5, s4
	vdiv.f32	s6, s6, s4
	bl	ocal_gain		@ S4.3: r0 = 1, s0 / s1 = zeta nu of the cell (keeps s4..s7)
	cbz	r0, .Lpb_nom
	vmul.f32	s2, s7, s0	@ Kr = K Re(zeta nu)
	vmul.f32	s3, s7, s1	@ Ki = K Im(zeta nu)
	vmul.f32	s16, s5, s2
	vmls.f32	s16, s6, s3	@ s16 = Re Z_inst = s5 Kr - s6 Ki
	vmul.f32	s17, s5, s3
	vmla.f32	s17, s6, s2	@ s17 = Im Z_inst = s5 Ki + s6 Kr
	b	.Lpb_mag
.Lpb_nom:
	vmul.f32	s16, s5, s7	@ s16 = Re Zbar (the stage-1 instructions, bit-identical)
	vmul.f32	s17, s6, s7	@ s17 = Im Zbar
.Lpb_mag:
	vmul.f32	s0, s16, s16
	vmla.f32	s0, s17, s17
	vsqrt.f32	s18, s0		@ s18 = |Zbar|
	vmov	r0, s16
	and	r0, r0, #EXP_MASK
	cmp	r0, #EXP_MASK
	beq	.Lpb_ovl
	vmov	r0, s17
	and	r0, r0, #EXP_MASK
	cmp	r0, #EXP_MASK
	beq	.Lpb_ovl
	vmov	r0, s18
	and	r0, r0, #EXP_MASK
	cmp	r0, #EXP_MASK
	beq	.Lpb_ovl
	vcmp.f32	s18, #0
	vmrs	APSR_nzcv, fpscr
	bne	.Lpb_angle
	movs	r0, #0
	vmov	s19, r0			@ theta = 0
	vmov.f32	s20, #1.0	@ cos
	vmov	s21, r0			@ sin
	b	.Lpb_comp
.Lpb_angle:
	vdiv.f32	s20, s16, s18	@ s20 = cos theta
	vdiv.f32	s21, s17, s18	@ s21 = sin theta
	vmov.f32	s0, s17
	vmov.f32	s1, s16
	bl	meas_deg
	vmov.f32	s19, s0		@ s19 = theta, degrees
.Lpb_comp:
	ldr	r0, [r5, #VB_FREQ]
	cmp	r0, #60
	it	eq
	moveq	r0, #100		@ S2.12: 60 Hz takes the 100 Hz entry of its level
	ldr	r1, [r5, #VB_LEVEL]
	vmov	s0, r1
	bl	fn_080090a4		@ r0 = table entry of this frequency and level
	mov	r7, r0
	ldr	r0, [r5, #VB_SCREEN]
	cmp	r0, #3
	beq	.Lpb_s1			@ screen 3: never compensated (S4.1): the store format of V1.1
	bl	meas_comp		@ S4.1 / S4.2 (K): r0 = 1 done, 2 overload, 0 stage 1
	cmp	r0, #1
	bne	.Lpb_c2
	ldr	r6, =V_RES
	b	.Lpb_out		@ s19..s22 from the compensated Zdut
.Lpb_c2:
	cmp	r0, #2
	beq	.Lpb_ovl		@ the guard of S4.1 or a non-finite Zdut: the overload set
.Lpb_s1:
	vmov.f32	s22, s18	@ s22 = |Z|c
	ldr	r6, =V_RES
	ldr	r0, [r5, #VB_SCREEN]
	cmp	r0, #3
	bne	.Lpb_short
	ldr	r1, [r6, #VR_CALT]
	cbz	r1, .Lpb_out		@ screen 3, type 0: the raw value for the store
.Lpb_short:
	vldr	s0, [r7]
	vsub.f32	s22, s22, s0	@ minus the short entry
	cmp	r0, #3
	beq	.Lpb_out		@ screen 3: no interpolation
	bl	ocal_gain_on		@ the gain applied: no decade interpolation (2.1)
	cmp	r0, #0
	bne	.Lpb_out
	vmov.f32	s0, s22
	mov	r0, r7
	bl	meas_interp
	vmov.f32	s22, s0
.Lpb_out:
	vstr	s22, [r6, #VR_Z]
	vstr	s19, [r6, #VR_TH]
	vmul.f32	s23, s22, s20	@ Rs
	vmul.f32	s24, s22, s21	@ Xs
	vstr	s23, [r6, #VR_RS]
	vstr	s24, [r6, #VR_XS]
	vmov.f32	s0, s22
	vmov.f32	s1, s20
	bl	meas_divinf
	vmov.f32	s25, s0		@ Rp
	vstr	s25, [r6, #VR_RP]
	vmov.f32	s0, s22
	vmov.f32	s1, s21
	bl	meas_divinf
	vmov.f32	s26, s0		@ Xp
	vstr	s26, [r6, #VR_XP]
	ldr	r8, =meas_k
	ldr	r0, [r5, #VB_FREQ]
	vmov	s0, r0
	vcvt.f32.s32	s0, s0
	vldr	s1, [r8, #K_W]
	vmul.f32	s27, s0, s1	@ w = 2 pi f
	vldr	s2, [r8, #K_M1E9]
	vldr	s3, [r8, #K_1E6]
	vmul.f32	s0, s27, s24
	vdiv.f32	s28, s2, s0	@ Cs = -1e9 / (w Xs)
	vmul.f32	s0, s27, s26
	vdiv.f32	s29, s2, s0	@ Cp
	vmul.f32	s0, s24, s3
	vdiv.f32	s30, s0, s27	@ Ls = Xs 1e6 / w
	vmul.f32	s0, s26, s3
	vdiv.f32	s31, s0, s27	@ Lp
	vstr	s28, [r6, #VR_CS]
	vstr	s29, [r6, #VR_CP]
	vstr	s30, [r6, #VR_LS]
	vstr	s31, [r6, #VR_LP]
	ldr	r0, =EXP_MASK
	vmov	s2, r0			@ s2 = +Inf
	movs	r0, #0
	vmov	s3, r0			@ s3 = 0
	vmov.f32	s0, s3		@ Q
	vcmp.f32	s24, #0
	vmrs	APSR_nzcv, fpscr
	beq	.Lpb_qst		@ Xs = 0: Q = 0
	vmov.f32	s0, s2
	vcmp.f32	s23, #0
	vmrs	APSR_nzcv, fpscr
	beq	.Lpb_qst		@ Rs = 0: Q = +Inf
	vdiv.f32	s0, s24, s23
	vabs.f32	s0, s0
.Lpb_qst:
	vstr	s0, [r6, #VR_Q]
	vmov.f32	s0, s3		@ D
	vcmp.f32	s23, #0
	vmrs	APSR_nzcv, fpscr
	beq	.Lpb_dst		@ Rs = 0: D = 0
	vmov.f32	s0, s2
	vcmp.f32	s24, #0
	vmrs	APSR_nzcv, fpscr
	beq	.Lpb_dst		@ Xs = 0: D = +Inf
	vdiv.f32	s0, s23, s24
	vabs.f32	s0, s0
.Lpb_dst:
	vstr	s0, [r6, #VR_D]
	ldr	r0, [r5, #VB_CIRCUIT]
	cbz	r0, .Lpb_auto
	cmp	r0, #1
	beq	.Lpb_ser
	b	.Lpb_par
.Lpb_auto:
	bl	meas_serpar		@ S2.6: r0 = 0 series, 1 parallel
	cmp	r0, #0
	bne	.Lpb_par
.Lpb_ser:
	movs	r0, #0
	str	r0, [r5, #VB_SERPAR]
	vstr	s23, [r6, #VR_R]
	vstr	s28, [r6, #VR_C]
	vstr	s30, [r6, #VR_L]
	b	.Lpb_x
.Lpb_par:
	movs	r0, #1
	str	r0, [r5, #VB_SERPAR]
	vstr	s25, [r6, #VR_R]
	vstr	s29, [r6, #VR_C]
	vstr	s31, [r6, #VR_L]
.Lpb_x:
	vstr	s24, [r6, #VR_X]	@ X = Xs in both modes, as V1.1
	bl	meas_tail
	b	.Lpb_reset
.Lpb_ovl:
	bl	meas_pub_set		@ not finite: the overload set
.Lpb_reset:
	bl	meas_reset
	ldr	r0, =MS_TICK
	ldr	r0, [r0]
	str	r0, [r4, #MO_TFIRST]	@ the next window is timed from this close
	ldr	r0, [r4, #MO_FL]
	orr	r0, r0, #FL_ANCHOR
	str	r0, [r4, #MO_FL]
	pop	{r6, r7, r8, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ meas_divinf - s0 = s0 / s1, or for s1 = 0 an infinity with the sign of s0 (no 0 / 0).
@   Changes r0, r1, s0.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_divinf, %function
meas_divinf:
	vcmp.f32	s1, #0
	vmrs	APSR_nzcv, fpscr
	bne	.Ldv_div
	vmov	r1, s0
	ldr	r0, =EXP_MASK
	tst	r1, #0x80000000
	it	ne
	orrne	r0, r0, #0x80000000
	vmov	s0, r0
	bx	lr
.Ldv_div:
	vdiv.f32	s0, s0, s1
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_serpar - S2.6 (design D4): r0 = 0 series, 1 parallel for |Z|c = s22, with the state
@   MF_SP (0 undecided after a setting change or restart, meas_watch; 1 series; 2 parallel):
@   series goes parallel above 10 kohm, parallel goes series below 1 kohm, in between the mode is
@   kept; undecided: series below sqrt(1 kohm * 10 kohm) = 3162.28 ohm, else parallel ([J] of the
@   design). Replaces V1.1's single compare at 1.1 Mohm. Changes r0..r2, s0, s1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_serpar, %function
meas_serpar:
	ldr	r1, =OWN_FUNC
	ldr	r0, [r1, #MF_SP]
	ldr	r2, =meas_k
	cmp	r0, #1
	beq	.Lsp_series
	cmp	r0, #2
	beq	.Lsp_par
	vldr	s1, [r2, #K_SPMID]	@ undecided: 3162.28
	b	.Lsp_cmp
.Lsp_series:
	vldr	s1, [r2, #K_SP10K]	@ series: parallel above 10 kohm
	b	.Lsp_cmp
.Lsp_par:
	vldr	s1, [r2, #K_SP1K]	@ parallel: series below 1 kohm
	vcmpe.f32	s22, s1
	vmrs	APSR_nzcv, fpscr
	bge	.Lsp_isp
	b	.Lsp_iss
.Lsp_cmp:
	vcmpe.f32	s22, s1
	vmrs	APSR_nzcv, fpscr
	ble	.Lsp_iss		@ not above: series
.Lsp_isp:
	movs	r0, #2
	str	r0, [r1, #MF_SP]
	movs	r0, #1			@ parallel
	bx	lr
.Lsp_iss:
	movs	r0, #1
	str	r0, [r1, #MF_SP]
	movs	r0, #0			@ series
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_pub_set - the overload / no-reading set of V1.1 (measure_33.s 0x0800a712): theta
@   0x200050CC = -400, |Z|, X, R, C, L, D, Q (0x200050C4 / C8 / B8 / BC / C0 / D4 / D0) =
@   1e10; then meas_tail (tail call). Changes r0..r3, r12, s0..s15.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_pub_set, %function
meas_pub_set:
	ldr	r0, =V_RES
	ldr	r1, =F_M400
	str	r1, [r0, #VR_TH]
	ldr	r1, =F_1E10
	str	r1, [r0, #VR_Z]
	str	r1, [r0, #VR_X]
	str	r1, [r0, #VR_R]
	str	r1, [r0, #VR_C]
	str	r1, [r0, #VR_L]
	str	r1, [r0, #VR_D]
	str	r1, [r0, #VR_Q]
	b	meas_tail

@ ----------------------------------------------------------------------------
@ meas_pub_ovl - S1.5: the overload set, unless hold is set. Changes r0..r3, r12, s0..s15.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_pub_ovl, %function
meas_pub_ovl:
	ldr	r0, [r5, #VB_HOLD]
	cmp	r0, #0
	beq	meas_pub_set
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_pub_nr - S1.8 "No reading": the no-reading set (unless hold is set), then 0x20001208 and
@   0x2000120C cleared and the window reset. Changes r0..r3, r12, s0..s15.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_pub_nr, %function
meas_pub_nr:
	push	{r6, lr}
	ldr	r0, [r5, #VB_HOLD]
	cbnz	r0, .Lnr_clr
	bl	meas_pub_set
.Lnr_clr:
	movs	r0, #0
	str	r0, [r5, #VB_NR]
	str	r0, [r5, #VB_NRCNT]
	bl	meas_reset
	pop	{r6, pc}

@ ----------------------------------------------------------------------------
@ meas_tail - the end of every publish, as fn_0800a068 (measure_33.s .L0800a740..): presence
@   (byte 0x2000000B = 1 when float(fn_0800a030() / 10) < |Z| 0x200050C4; else, when it was 1,
@   0 and word 0x2000511C = 0), the compare value 0x200050DC from R / C / L by the word
@   0x20001178 = 1 / 2 / 3, the publish number MF_PSEQ + 1 and the compare judgement
@   (own_cmp_judge, cmp.s; S2.8: it replaces fn_0800a7ec), fn_0800f854 (the AUTO function and the
@   display), 0x20001208 = 0, and the new-result word 0x20001200 written 1 then 0 (set and
@   cleared within the call, as V1.1). Changes r0..r3, r12, s0..s15.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_tail, %function
meas_tail:
	push	{r6, lr}
	ldr	r0, =OWN_FUNC
	ldr	r1, [r0, #MF_PSEQ]
	adds	r1, r1, #1
	str	r1, [r0, #MF_PSEQ]	@ one more publish
	bl	fn_0800a030		@ the open limit of this frequency
	movs	r1, #10
	sdiv	r0, r0, r1
	vmov	s0, r0
	vcvt.f32.s32	s0, s0
	ldr	r6, =V_RES
	vldr	s1, [r6, #VR_Z]
	ldr	r2, =MS_REJ
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	bcs	.Ltl_low		@ limit >= |Z| (or unordered)
	movs	r1, #1
	strb	r1, [r2, #1]		@ 0x2000000B = 1
	b	.Ltl_cmp
.Ltl_low:
	ldrb	r1, [r2, #1]
	cmp	r1, #1
	bne	.Ltl_cmp
	movs	r1, #0
	strb	r1, [r2, #1]		@ 0x2000000B = 0
	str	r1, [r6, #VR_511C]	@ 0x2000511C = 0
.Ltl_cmp:
	ldr	r0, [r5, #VB_CMP]
	cmp	r0, #1
	beq	.Ltl_r
	cmp	r0, #2
	beq	.Ltl_c
	cmp	r0, #3
	bne	.Ltl_auto
	vldr	s0, [r6, #VR_L]
	b	.Ltl_store
.Ltl_r:
	vldr	s0, [r6, #VR_R]
	b	.Ltl_store
.Ltl_c:
	vldr	s0, [r6, #VR_C]
.Ltl_store:
	vstr	s0, [r6, #VR_CMPV]	@ 0x200050DC
.Ltl_auto:
	bl	own_cmp_judge		@ S2.8 on screen 2 (cmp.s)
	bl	fn_0800f854
	movs	r0, #0
	str	r0, [r5, #VB_NR]	@ 0x20001208 = 0
	movs	r0, #1
	str	r0, [r5, #VB_NEW]	@ 0x20001200 = 1 ...
	movs	r0, #0
	str	r0, [r5, #VB_NEW]	@ ... and consumed by this publish
	pop	{r6, pc}

@ ----------------------------------------------------------------------------
@ meas_deg - s0 = atan2(s0, s1) in degrees, as fn_0800a068 forms a phase: the two floats as
@   doubles, fn_08010700(d0 = y, d1 = x), times 180.0, divided by the double of the float pi
@   (0x400921FB60000000), back to float. Changes r0..r3, r12, s0..s15.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_deg, %function
meas_deg:
	push	{r6, r7, r8, lr}
	vmov	r6, s1			@ x
	vmov	r0, s0
	bl	float_to_double
	mov	r7, r0
	mov	r8, r1			@ r7:r8 = y
	mov	r0, r6
	bl	float_to_double
	vmov	d1, r0, r1		@ x
	vmov	d0, r7, r8		@ y
	bl	fn_08010700		@ d0 = atan2(y, x), radians
	vmov	r0, r1, d0
	movs	r2, #0
	ldr	r3, =0x40668000		@ 180.0
	bl	double_multiply
	ldr	r2, =0x60000000
	ldr	r3, =0x400921FB		@ the float pi as a double
	bl	double_divide
	bl	double_to_float
	vmov	s0, r0
	pop	{r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ meas_interp - the decade interpolation of fn_0800a068 (measure_33.s 0x0800a376..0x0800a55c),
@   written again from its formulas: s0 = |Z| minus the short entry, r0 = table entry (b1..b10
@   at +4..+0x28). Below b1: s0 / b1 * 0.01; in [b_k, b_k+1) for k = 1..8 and from b9 on (k = 9,
@   up to b10): (s0 - b_k) * S_k / (b_k+1 - b_k) + B_k with B_k = 0.01 * 10^(k-1) and S_k =
@   9 B_k (table meas_ib), the same operations in the same order as the vendor. Returns s0.
@   Changes r0..r3, s0..s5.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_interp, %function
meas_interp:
	vldr	s1, [r0, #4]		@ b1
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	bcs	.Lin_up
	vdiv.f32	s0, s0, s1
	ldr	r1, =meas_ib
	vldr	s2, [r1]		@ 0.01
	vmul.f32	s0, s0, s2
	bx	lr
.Lin_up:
	adds	r1, r0, #4		@ r1 = &b_k
	ldr	r2, =meas_ib		@ r2 = &(B_k, S_k)
	movs	r3, #1			@ r3 = k
.Lin_next:
	vldr	s1, [r1]		@ b_k
	vldr	s2, [r1, #4]		@ b_k+1
	cmp	r3, #9
	beq	.Lin_use		@ the last interval: from b9 up
	vcmpe.f32	s0, s2
	vmrs	APSR_nzcv, fpscr
	bcc	.Lin_use		@ below b_k+1
	adds	r1, r1, #4
	adds	r2, r2, #8
	adds	r3, r3, #1
	b	.Lin_next
.Lin_use:
	vsub.f32	s3, s0, s1
	vldr	s4, [r2, #4]		@ S_k
	vmul.f32	s3, s3, s4
	vsub.f32	s5, s2, s1
	vdiv.f32	s3, s3, s5
	vldr	s4, [r2]		@ B_k
	vadd.f32	s0, s3, s4
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_exempt - r0 = 1 when |Zm| of the slot r0 (Zr, Zi at +16, +20) is at least 1.1e8 as a
@   signed bit compare (bits >= 0x4CD1CEF0, fn_08008ea8), else 0. Changes r0, r1, s0..s2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_exempt, %function
meas_exempt:
	vldr	s0, [r0, #16]
	vldr	s1, [r0, #20]
	vmul.f32	s2, s0, s0
	vmla.f32	s2, s1, s1
	vsqrt.f32	s2, s2
	vmov	r0, s2
	ldr	r1, =F_OPEN
	cmp	r0, r1
	ite	ge
	movge	r0, #1
	movlt	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_dist2 - s0 = |Z - P|^2 for the slot r0 (Z at +16, +20) and the point r1 (re, im).
@   Changes s0..s3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_dist2, %function
meas_dist2:
	vldr	s0, [r0, #16]
	vldr	s1, [r0, #20]
	vldr	s2, [r1]
	vldr	s3, [r1, #4]
	vsub.f32	s0, s0, s2
	vsub.f32	s1, s1, s3
	vmul.f32	s0, s0, s0
	vmla.f32	s0, s1, s1
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_lim2 - s0 = L^2 = max(25 s^2, 1e-4 |mu|^2), s^2 = MO_M2 / MO_N (the RMS spread of the
@   accepted Zm; N >= 3 in phase 2). Changes r0, s0..s3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_lim2, %function
meas_lim2:
	vldr	s0, [r4, #MO_M2]
	ldr	r0, [r4, #MO_N]
	vmov	s1, r0
	vcvt.f32.u32	s1, s1
	vdiv.f32	s0, s0, s1	@ s^2
	vmov.f32	s1, #25.0
	vmul.f32	s0, s0, s1	@ (5 s)^2
	vldr	s2, [r4, #MO_MU]
	vldr	s3, [r4, #MO_MU + 4]
	vmul.f32	s1, s2, s2
	vmla.f32	s1, s3, s3
	ldr	r0, =meas_k
	vldr	s2, [r0, #K_1EM4]
	vmul.f32	s1, s1, s2	@ (0.01 |mu|)^2
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	it	lt
	vmovlt.f32	s0, s1
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_median - s0 / s1 = the component-wise median of Zr / Zi of the three slots from r0.
@   Changes s0..s4.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_median, %function
meas_median:
	push	{r0, lr}
	vldr	s0, [r0, #16]
	vldr	s1, [r0, #16 + SLOT]
	vldr	s2, [r0, #16 + 2 * SLOT]
	bl	meas_med3
	vmov.f32	s4, s0
	ldr	r0, [sp]
	vldr	s0, [r0, #20]
	vldr	s1, [r0, #20 + SLOT]
	vldr	s2, [r0, #20 + 2 * SLOT]
	bl	meas_med3
	vmov.f32	s1, s0
	vmov.f32	s0, s4
	pop	{r0, pc}

@ ----------------------------------------------------------------------------
@ meas_med3 - s0 = the median of s0, s1, s2: max(min(a, b), min(max(a, b), c)).
@   Changes s0..s3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_med3, %function
meas_med3:
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	ittt	gt
	vmovgt.f32	s3, s0
	vmovgt.f32	s0, s1
	vmovgt.f32	s1, s3		@ s0 = min(a, b), s1 = max(a, b)
	vcmpe.f32	s1, s2
	vmrs	APSR_nzcv, fpscr
	it	gt
	vmovgt.f32	s1, s2		@ s1 = min(max(a, b), c)
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	it	lt
	vmovlt.f32	s0, s1
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_copyw - copies r2 words from r0 to r1 (forward). Changes r0..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_copyw, %function
meas_copyw:
	ldr	r3, [r0], #4
	str	r3, [r1], #4
	subs	r2, r2, #1
	bne	meas_copyw
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_rej_inc - the reject byte 0x2000000A + 1, at most 255. Changes r0, r1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_rej_inc, %function
meas_rej_inc:
	ldr	r1, =MS_REJ
	ldrb	r0, [r1]
	adds	r0, r0, #1
	cmp	r0, #255
	it	hi
	movhi	r0, #255
	strb	r0, [r1]
	bx	lr

	.ltorg

@ ============================================================================
@ own_tim1_setup - S1.1: fn_08007e7c (measure_32.s) written again with one change, called by
@   fn_08007bdc at 0x08007C00 (.ifdef OWN). r0 = frequency (word 0x20001144); no result.
@   The scaled value r4 = 128 f (f < 10000), 32 f (f < 100000) or 8 f, as the vendor; TIM1
@   0x40012C00 through fn_0800c33c, init_eleven_field_record and fn_0800c590 with the period
@   halfword (+4) = 144000000 / r4 - 1 (the vendor has no - 1: the timer period is AR + 1 ticks,
@   so the vendor's 128 samples spanned 1.00089 periods at 1 kHz; here exactly 1, 4 or 16, as
@   144e6 / (k f) is an integer for all five frequencies: 11250, 9375, 1125, 450, 180, and for
@   60 Hz of S2.12: 18750, AR 18749), then the
@   channel block (0x70, 1, 1, 0) through fn_0800c504, as the vendor.
@ ============================================================================
	.global	own_tim1_setup
	.thumb_func
	.type	own_tim1_setup, %function
own_tim1_setup:
	push	{r4, r5, r6, lr}
	movw	r1, #10000
	lsls	r4, r0, #7		@ r4 = f * 128
	sub	sp, sp, #0x20
	cmp	r0, r1
	blt	.Lt1_div
	ldr	r2, =100000
	sbfx	r1, r0, #24, #1		@ sign of r4 (rounding toward zero, as the vendor)
	cmp	r0, r2
	bge	.Lt1_16
	add	r0, r4, r1, lsr #30
	asrs	r4, r0, #2		@ f * 32
	b	.Lt1_div
.Lt1_16:
	add	r0, r4, r1, lsr #28
	asrs	r4, r0, #4		@ f * 8
.Lt1_div:
	ldr	r6, =0x40012C00		@ TIM1
	mov	r0, r6
	bl	fn_0800c33c
	mov	r0, sp
	bl	init_eleven_field_record
	ldr	r0, =144000000
	movs	r5, #0
	udiv	r0, r0, r4
	subs	r0, r0, #1		@ AR = 144 MHz / (k f) - 1: a period of exactly k f
	strh	r5, [sp, #6]
	strh	r5, [sp, #2]
	strh	r0, [sp, #4]
	strh	r5, [sp]
	mov	r1, sp
	mov	r0, r6
	bl	fn_0800c590
	movs	r0, #0x70
	strh	r0, [sp, #0x10]
	movs	r1, #1
	strh	r1, [sp, #0x12]
	strh	r1, [sp, #0x16]
	strh	r5, [sp, #0x18]
	add	r1, sp, #0x10
	mov	r0, r6
	bl	fn_0800c504
	add	sp, sp, #0x20
	pop	{r4, r5, r6, pc}

	.ltorg

@ ============================================================================
@ own_dac_setup - S1.1: fn_08008814 (measure_32.s) written again with one change, called by
@   fn_08009f10 (0x08009F20) and fn_080087d4 (0x08008808) instead of it (.ifdef OWN).
@   r0 = frequency, s0 = amplitude (the level float); no result.
@   n = 180 entries and divisor 2.34 below 100 kHz, n = 36 and 2.1 from 100 kHz, as the vendor,
@   except n = 150 at 120 Hz: TIM6 then counts 72e6 / 120 / 150 = 4000 exactly (AR 3999), where
@   the vendor's 72e6 / 120 / 180 = 3333 (truncated) gave 120.012 Hz; and n = 150 at 60 Hz
@   (S2.12): 72e6 / 60 / 150 = 8000 (AR 7999), exactly 60.0000 Hz. The table 0x20005120
@   (room for 180 halfwords) holds one period, so the DMA2 ch3 interrupt still comes once per
@   period. Table entry i = (short)(sin(2 pi i / n) * 2047.5 * amplitude / divisor + bias float
@   0x2000113C * 620.0 + 2047.5); DMA2 ch3 0x40020430 (0x40007408 DAC_DR12CH1, the table, 0x10,
@   n, 0, 0x80, 0x100, 0x400, 0x20, 0x2000, 0), set_or_clear_bits(block, 2, 1), enabled;
@   fn_0800ad68(0x3A, 0, 0, 1); TIM6 0x40001000 with period 72000000 / f / n - 1, fn_0800c6dc(
@   TIM6, 0x20), set_or_clear_bit_0_0800c404(TIM6, 1): the vendor's sequence.
@ ============================================================================
	.global	own_dac_setup
	.thumb_func
	.type	own_dac_setup, %function
own_dac_setup:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r1, .Lds_100k
	mov	r8, r0			@ r8 = frequency
	vpush	{d8, d9}
	sub	sp, sp, #0x40
	cmp	r0, r1
	bhs	.Lds_hi
	movs	r4, #180		@ n = 180
	vldr	s1, .Lds_234		@ 2.34
	cmp	r0, #120
	beq	.Lds_150
	cmp	r0, #60
	bne	.Lds_n
.Lds_150:
	movs	r4, #150		@ 120 Hz and 60 Hz (S2.12): n = 150
	b	.Lds_n
.Lds_hi:
	movs	r4, #36			@ n = 36
	vldr	s1, .Lds_21		@ 2.1
.Lds_n:
	movs	r5, #0			@ r5 = i
	vdiv.f32	s16, s0, s1	@ s16 = amplitude / divisor
	vldr	s18, .Lds_2pi
	vldr	s17, .Lds_2047
	ldr	r6, .Lds_d7c		@ 0x20000D7C
	vldr	s19, .Lds_620
	ldr	r7, .Lds_tab		@ 0x20005120, halfword table
.Lds_fill:
	vmov	s0, r5
	vcvt.f32.s32	s0, s0
	vmul.f32	s1, s0, s18
	vmov	s0, r4
	vcvt.f32.s32	s2, s0
	vdiv.f32	s0, s1, s2	@ 2 pi i / n
	bl	sine_radians
	vmul.f32	s0, s0, s17
	vldr	s1, [r6, #0x3c0]	@ bias float 0x2000113C
	vmul.f32	s0, s0, s16
	vmla.f32	s0, s1, s19
	vadd.f32	s0, s0, s17
	vcvt.s32.f32	s0, s0
	vmov	r0, s0
	strh	r0, [r7, r5, lsl #1]
	adds	r5, r5, #1
	cmp	r5, r4
	blt	.Lds_fill
	ldr	r6, .Lds_ch3		@ 0x40020430, DMA2 channel 3
	mov	r0, r6
	bl	fn_0800864c
	ldr	r0, .Lds_dac		@ 0x40007408
	strd	r0, r7, [sp]
	add	r1, sp, #8
	movs	r0, #0x10
	movs	r5, #0
	stm	r1, {r0, r4, r5}
	movs	r0, #0x80
	str	r0, [sp, #0x14]
	lsls	r0, r0, #1		@ 0x100
	str	r0, [sp, #0x18]
	lsls	r0, r0, #2		@ 0x400
	str	r0, [sp, #0x1c]
	movs	r0, #0x20
	str	r0, [sp, #0x20]
	lsls	r0, r0, #8		@ 0x2000
	strd	r0, r5, [sp, #0x24]
	mov	r1, sp
	mov	r0, r6
	bl	fn_08008794
	movs	r2, #1
	movs	r1, #2
	mov	r0, r6
	bl	set_or_clear_bits
	movs	r1, #1
	mov	r0, r6
	bl	fn_08008770
	movs	r0, #0x3a
	strb	r0, [sp, #0x3c]
	strb	r5, [sp, #0x3d]
	strb	r5, [sp, #0x3e]
	movs	r0, #1
	strb	r0, [sp, #0x3f]
	add	r0, sp, #0x3c
	bl	fn_0800ad68
	add	r0, sp, #0x2c
	bl	init_eleven_field_record
	ldr	r1, .Lds_72m		@ 72000000
	strh	r5, [sp, #0x2c]
	udiv	r0, r1, r8
	udiv	r0, r0, r4
	subs	r0, r0, #1
	strh	r0, [sp, #0x30]		@ TIM6 period: 72e6 / f / n - 1
	ldr	r4, .Lds_tim6		@ 0x40001000
	strh	r5, [sp, #0x32]
	strh	r5, [sp, #0x2e]
	add	r1, sp, #0x2c
	mov	r0, r4
	bl	fn_0800c590
	movs	r1, #0x20
	mov	r0, r4
	bl	fn_0800c6dc
	movs	r1, #1
	mov	r0, r4
	bl	set_or_clear_bit_0_0800c404
	add	sp, sp, #0x40
	vpop	{d8, d9}
	pop	{r4, r5, r6, r7, r8, pc}
	.p2align 2
.Lds_100k:
	.word	100000
.Lds_234:
	.word	0x4015C28F		@ 2.34
.Lds_21:
	.word	0x40066666		@ 2.1
.Lds_2pi:
	.word	0x40C90FDB		@ 2 pi
.Lds_2047:
	.word	0x44FFF000		@ 2047.5
.Lds_d7c:
	.word	0x20000D7C
.Lds_620:
	.word	0x441B0000		@ 620.0
.Lds_tab:
	.word	0x20005120
.Lds_ch3:
	.word	0x40020430
.Lds_dac:
	.word	0x40007408
.Lds_72m:
	.word	72000000
.Lds_tim6:
	.word	0x40001000

@ ============================================================================
@ own_freq_step - S2.12: the frequency step of fn_0800d940 mode 0, entered by b.w at 0x0800D97A
@   (src/ui_42.s, .ifdef OWN) with r0 = step, r2 = 0x2000057C and {r4, r5, r6, r7} pushed by
@   fn_0800d940 (ui_42.s 542-545). The word 0x20001144 steps through freq_cycle, both directions
@   wrapping as the vendor's (up 60 -> 100 -> 120 -> 1000 -> 10000 -> 100000 -> 60; down the
@   reverse, 100000 -> 10000 -> 1000 -> 120 -> 100 -> 60 -> 100000); step 0 or a word not in the
@   cycle: no change. Then the vendor's exit .L0800da38: pop {r4, r5, r6, r7}, b.w fn_08009f10
@   (the measurement restarts at the new frequency).
@ ============================================================================
	.global	own_freq_step
	.thumb_func
	.type	own_freq_step, %function
own_freq_step:
	ldr	r1, [r2, #VB_FREQ]
	ldr	r3, =freq_cycle
	movs	r4, #0			@ r4 = index (r4..r7 are fn_0800d940's, restored below)
.Lfs_find:
	ldr	r5, [r3, r4, lsl #2]
	cmp	r5, r1
	beq	.Lfs_found
	adds	r4, r4, #1
	cmp	r4, #6
	blo	.Lfs_find
	b	.Lfs_out		@ unknown word: left as it is
.Lfs_found:
	cmp	r0, #0
	beq	.Lfs_out		@ step 0
	blt	.Lfs_down
	adds	r4, r4, #1
	cmp	r4, #6
	it	eq
	moveq	r4, #0			@ 100000 -> 60
	b	.Lfs_store
.Lfs_down:
	subs	r4, r4, #1
	it	mi
	movmi	r4, #5			@ 60 -> 100000
.Lfs_store:
	ldr	r1, [r3, r4, lsl #2]
	str	r1, [r2, #VB_FREQ]
.Lfs_out:
	pop	{r4, r5, r6, r7}
	b.w	fn_08009f10

@ ----------------------------------------------------------------------------
@ meas_bias_wait - S4.4, the bias transient (design 8.1: built with the DC-midpoint rule; the
@   count limit BIAS_LIM and the time bound BIAS_MAX_MS are [J], marked for M6). After a bias change
@   (MF_BIASP != 0, set by meas_watch) a window is published only when the DC midpoints of ADC1 and
@   ADC2 (halfwords 0x200011D0 / 0x200011D8, written by fn_08007fd4 / fn_08007f38 for the
@   acquisition that closed the window) each differ by at most BIAS_LIM counts from those at the
@   previous window close (steady over two windows), or once BIAS_MAX_MS have passed since the
@   change. Returns r0 = 1 for a window not to be published (its midpoints kept in MF_BMID for the
@   next close, MF_BIASP = 2), r0 = 0 to publish (MF_BIASP = 0). Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_bias_wait, %function
meas_bias_wait:
	push	{r6, lr}
	ldr	r6, =OWN_FUNC
	ldr	r0, [r6, #MF_BIASP]
	cmp	r0, #0
	beq	.Lbw_ret		@ r0 = 0: no transient pending
	ldrh	r1, [r5, #VB_MIDV]
	ldrh	r2, [r5, #VB_MIDI]
	orr	r1, r1, r2, lsl #16	@ r1 = the midpoints of this close
	cmp	r0, #2
	bne	.Lbw_keep		@ the first close after the change: nothing to compare with
	ldr	r2, [r6, #MF_BMID]
	uxth	r0, r1
	uxth	r3, r2
	subs	r0, r0, r3
	it	mi
	rsbmi	r0, r0, #0		@ |delta V midpoint|
	push	{r0, r1}
	bl	ocal_bias_limit		@ S4.4 limit: BIAS section, default 4 = BIAS_LIM (r0, r1)
	mov	r12, r0
	pop	{r0, r1}
	cmp	r0, r12
	bhi	.Lbw_keep
	lsrs	r0, r1, #16
	lsrs	r3, r2, #16
	subs	r0, r0, r3
	it	mi
	rsbmi	r0, r0, #0		@ |delta I midpoint|
	push	{r0, r1}
	bl	ocal_bias_limit		@ S4.4 limit: BIAS section, default 4 = BIAS_LIM (r0, r1)
	mov	r12, r0
	pop	{r0, r1}
	cmp	r0, r12
	bls	.Lbw_done		@ both steady over two windows
.Lbw_keep:
	str	r1, [r6, #MF_BMID]
	movs	r0, #2
	str	r0, [r6, #MF_BIASP]
	ldr	r0, [r6, #MF_BT0]
	ldr	r1, =MS_TICK
	ldr	r1, [r1]
	subs	r0, r1, r0		@ ms since the change (unsigned difference)
	ldr	r1, =BIAS_MAX_MS
	cmp	r0, r1
	bhs	.Lbw_done		@ the time bound: published from now on
	movs	r0, #1
	pop	{r6, pc}
.Lbw_done:
	movs	r0, #0
	str	r0, [r6, #MF_BIASP]
.Lbw_ret:
	pop	{r6, pc}

@ ----------------------------------------------------------------------------
@ meas_comp - stage 4 on screens 1 and 2: S4.1, the complex open / short compensation, with
@   S4.2 option (K) (design 8.1: D11 = (K), computed per reading, 0 RAM). r7 = the user-table
@   entry of the frequency and level (fn_080090a4: type t at +4 t, its phase at +0x2D0 + 4 t),
@   s16 / s17 = Re / Im Zbar.
@   - Zs = |t0| e^(j theta0) (type 0 is stored raw). |t0| or theta0 not finite, or |theta0| > 180:
@     r0 = 0 (the stage-1 chain);
@   - Zo = (t11 + |t0|) e^(j theta11) (type 11 is stored as |Zm| - |Zs| of its time). The open is
@     unusable, and the compensation short-only (Zdut = Zm - Zs), when t11 is exactly 1e12 with
@     theta 0 (the default), 1e10 (no reading), theta11 not finite or beyond +-180 (-400 the
@     no-reading set, +400 an open "not resolved" by cal.s), t11 not finite, or |Zo| below 1e5 or
@     Zo = Zs; else Yo = 1 / (Zo - Zs) and Zdut = (Zm - Zs) / (1 - (Zm - Zs) Yo) (meas_cz);
@   - (K): b'_k = |comp((b_k + |t0|) e^(j theta_k))| for the references k = 1..10 (assumption A1
@     of the design: b_k was stored as |Zm_k| - |t0|). One not finite, a guard at one, or b'_k not
@     strictly increasing: r0 = 0 (the stage-1 chain for this reading); skipped where the OCAL
@     gain was applied (ocal_gain_on): |Z|c = |Zdut| then;
@   - Zdut = comp(Zbar): the guard |1 - (Zm - Zs) Yo| < 1e-6, or Zdut not finite: r0 = 2 (the
@     overload set). Else |Z|c = the decade interpolation (meas_interp) of |Zdut| against b'_k
@     (every reference reads its nominal by construction), theta = atan2(Im, Re) of Zdut in
@     degrees, cos / sin = Re / Im over |Zdut| (|Zdut| = 0: theta 0, cos 1, sin 0) into s19..s22,
@     r0 = 1.
@   Changes r0..r3, r12, s0..s15, s23..s31 (s16..s18 kept; s19..s22 only with r0 = 1).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_comp, %function
meas_comp:
	push	{r6, r8, r9, r10, r11, lr}
	sub	sp, #48			@ b'_k at sp + 4 k, k = 1..10 (the layout meas_interp reads)
	vldr	s0, [r7]		@ t0
	bl	meas_fin
	cmp	r0, #0
	beq	.Lco_none
	vldr	s0, [r7]
	vabs.f32	s23, s0		@ s23 = |t0|
	vldr	s0, [r7, #PH_OFF]	@ theta0
	bl	meas_angok
	cmp	r0, #0
	beq	.Lco_none
	vldr	s0, [r7, #PH_OFF]
	bl	meas_cis		@ s0 = cos theta0, s1 = sin theta0
	vmul.f32	s24, s23, s0	@ s24 = Re Zs
	vmul.f32	s25, s23, s1	@ s25 = Im Zs
	movs	r8, #0			@ r8 = 1: the open is usable
	ldr	r0, [r7, #0x2C]		@ t11 bits
	ldr	r1, [r7, #PH_OFF + 0x2C]	@ theta11 bits
	ldr	r2, =F_OPENDEF
	cmp	r0, r2
	bne	.Lco_o1
	cmp	r1, #0
	beq	.Lco_refs		@ the default open, 1e12 at 0 degrees
.Lco_o1:
	ldr	r2, =F_1E10
	cmp	r0, r2
	beq	.Lco_refs		@ the no-reading value
	vmov	s0, r0
	bl	meas_fin
	cmp	r0, #0
	beq	.Lco_refs
	vldr	s0, [r7, #PH_OFF + 0x2C]
	bl	meas_angok
	cmp	r0, #0
	beq	.Lco_refs		@ -400, +400 ("not resolved") or not finite
	vldr	s0, [r7, #0x2C]
	vadd.f32	s28, s0, s23	@ s28 = |Zo| = t11 + |t0|
	ldr	r0, =meas_ck
	vldr	s1, [r0, #CK_1E5]
	vcmpe.f32	s28, s1
	vmrs	APSR_nzcv, fpscr
	blt	.Lco_refs		@ below 100 kohm (or not ordered)
	vldr	s0, [r7, #PH_OFF + 0x2C]
	bl	meas_cis
	vmul.f32	s2, s28, s0
	vsub.f32	s2, s2, s24	@ Re (Zo - Zs)
	vmul.f32	s3, s28, s1
	vsub.f32	s3, s3, s25	@ Im (Zo - Zs)
	vmul.f32	s4, s2, s2
	vmla.f32	s4, s3, s3	@ |Zo - Zs|^2
	vmov	r0, s4
	ldr	r1, =EXP_MASK
	and	r0, r0, r1
	cmp	r0, r1
	beq	.Lco_refs		@ not finite
	vcmp.f32	s4, #0
	vmrs	APSR_nzcv, fpscr
	beq	.Lco_refs		@ Zo = Zs
	vdiv.f32	s26, s2, s4	@ s26 = Re Yo
	vdiv.f32	s27, s3, s4
	vneg.f32	s27, s27	@ s27 = Im Yo
	movs	r8, #1
.Lco_refs:
	bl	ocal_gain_on		@ the gain applied: no S4.2 (K) references (OWN_CAL_DESIGN 2.1)
	cmp	r0, #0
	bne	.Lco_zdut
	movs	r9, #1			@ r9 = k
.Lco_ref:
	add	r10, r7, r9, lsl #2	@ r10 = &b_k
	vldr	s0, [r10]
	bl	meas_fin
	cmp	r0, #0
	beq	.Lco_none
	vldr	s0, [r10, #PH_OFF]
	bl	meas_angok
	cmp	r0, #0
	beq	.Lco_none
	vldr	s0, [r10]
	vadd.f32	s30, s0, s23	@ s30 = |Zm_k| = b_k + |t0|
	vldr	s0, [r10, #PH_OFF]
	bl	meas_cis
	vmul.f32	s2, s30, s1
	vmul.f32	s0, s30, s0	@ Re Zm_k
	vmov.f32	s1, s2		@ Im Zm_k
	bl	meas_cz
	cmp	r0, #0
	bne	.Lco_none		@ the guard at a reference
	vmul.f32	s2, s0, s0
	vmla.f32	s2, s1, s1
	vsqrt.f32	s0, s2		@ b'_k
	bl	meas_fin
	cmp	r0, #0
	beq	.Lco_none
	cmp	r9, #1
	beq	.Lco_put
	vcmpe.f32	s0, s29
	vmrs	APSR_nzcv, fpscr
	ble	.Lco_none		@ not strictly increasing (or not ordered)
.Lco_put:
	vmov.f32	s29, s0		@ s29 = b'_k for the next test
	add	r0, sp, r9, lsl #2
	vstr	s0, [r0]
	adds	r9, r9, #1
	cmp	r9, #10
	bls	.Lco_ref
.Lco_zdut:
	vmov.f32	s0, s16
	vmov.f32	s1, s17
	bl	meas_cz			@ Zdut of the window
	cmp	r0, #0
	bne	.Lco_ovl
	vmov.f32	s30, s0		@ s30 = Re Zdut
	vmov.f32	s31, s1		@ s31 = Im Zdut
	vmul.f32	s2, s0, s0
	vmla.f32	s2, s1, s1
	vsqrt.f32	s28, s2		@ s28 = |Zdut|
	vmov.f32	s0, s28
	bl	meas_fin
	cmp	r0, #0
	beq	.Lco_ovl
	vmov.f32	s0, s28
	bl	ocal_gain_on		@ changes r0, r1 only
	cmp	r0, #0
	bne	.Lco_noint		@ the gain applied: |Z|c = |Zdut|
	vmov.f32	s0, s28
	mov	r0, sp
	bl	meas_interp		@ against b'_k (S4.2 (K))
.Lco_noint:
	vmov.f32	s22, s0		@ s22 = |Z|c
	vcmp.f32	s28, #0
	vmrs	APSR_nzcv, fpscr
	bne	.Lco_ang
	movs	r0, #0
	vmov	s19, r0			@ theta = 0
	vmov.f32	s20, #1.0	@ cos
	vmov	s21, r0			@ sin
	b	.Lco_done
.Lco_ang:
	vdiv.f32	s20, s30, s28	@ s20 = cos theta
	vdiv.f32	s21, s31, s28	@ s21 = sin theta
	vmov.f32	s0, s31
	vmov.f32	s1, s30
	bl	meas_deg
	vmov.f32	s19, s0		@ s19 = theta, degrees
.Lco_done:
	movs	r0, #1
	b	.Lco_ret
.Lco_ovl:
	movs	r0, #2
	b	.Lco_ret
.Lco_none:
	movs	r0, #0
.Lco_ret:
	add	sp, #48
	pop	{r6, r8, r9, r10, r11, pc}

@ ----------------------------------------------------------------------------
@ meas_cz - comp(Zm) of S4.1 for s0 / s1 = Re / Im Zm, with s24 / s25 = Zs, s26 / s27 = Yo and
@   r8 = 1 when the open is usable (meas_comp): D = Zm - Zs; r8 = 0: Zdut = D; else W = 1 - D Yo,
@   |W|^2 < 1e-12 (|W| < 1e-6, or not ordered) is the guard (r0 = 1), else Zdut = D / W =
@   D conj(W) / |W|^2. Returns s0 / s1 = Zdut, r0 = 0. A leaf; changes r0, s0..s7.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_cz, %function
meas_cz:
	vsub.f32	s0, s0, s24	@ Re D
	vsub.f32	s1, s1, s25	@ Im D
	cmp	r8, #0
	beq	.Lcz_ok			@ short only
	vmul.f32	s2, s0, s26
	vmls.f32	s2, s1, s27	@ Re (D Yo)
	vmul.f32	s3, s0, s27
	vmla.f32	s3, s1, s26	@ Im (D Yo)
	vmov.f32	s4, #1.0
	vsub.f32	s4, s4, s2	@ Re W
	vneg.f32	s5, s3		@ Im W
	vmul.f32	s6, s4, s4
	vmla.f32	s6, s5, s5	@ |W|^2
	ldr	r0, =meas_ck
	vldr	s7, [r0, #CK_1EM12]
	vcmpe.f32	s6, s7
	vmrs	APSR_nzcv, fpscr
	blt	.Lcz_guard
	vmul.f32	s2, s0, s4
	vmla.f32	s2, s1, s5	@ Re D Re W + Im D Im W
	vmul.f32	s3, s1, s4
	vmls.f32	s3, s0, s5	@ Im D Re W - Re D Im W
	vdiv.f32	s0, s2, s6
	vdiv.f32	s1, s3, s6
.Lcz_ok:
	movs	r0, #0
	bx	lr
.Lcz_guard:
	movs	r0, #1
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_cis - s0 = an angle in degrees: s0 = cos, s1 = sin of it (radians = degrees * pi / 180,
@   then the vendor's single-precision cosine fn_08010900 and sine fn_08011780, runtime_37.s /
@   runtime_38.s; the angle is finite, meas_angok). Keeps s16..s31 (s16 / s17 saved around the
@   calls). Changes r0..r3, r12, s0..s15.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_cis, %function
meas_cis:
	push	{r3, lr}
	vpush	{d8}
	ldr	r0, =meas_ck
	vldr	s1, [r0, #CK_D2R]
	vmul.f32	s0, s0, s1	@ s0 = radians
	vmov.f32	s16, s0		@ kept for the sine
	bl	fn_08010900		@ cos
	vmov.f32	s17, s0
	vmov.f32	s0, s16
	bl	fn_08011780		@ sin
	vmov.f32	s1, s0
	vmov.f32	s0, s17
	vpop	{d8}
	pop	{r3, pc}

@ ----------------------------------------------------------------------------
@ meas_angok - r0 = 1 when s0 is a finite angle with |s0| <= 180 degrees (an ordered compare:
@   NaN and the infinities give 0), else 0. A leaf; changes r0, s1, s2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_angok, %function
meas_angok:
	ldr	r0, =meas_ck
	vldr	s1, [r0, #CK_180]
	vabs.f32	s2, s0
	vcmpe.f32	s2, s1
	vmrs	APSR_nzcv, fpscr
	ite	ls
	movls	r0, #1
	movhi	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ meas_fin - r0 = 1 when s0 is finite (exponent field not all ones), else 0. A leaf; changes r0.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	meas_fin, %function
meas_fin:
	vmov	r0, s0
	and	r0, r0, #EXP_MASK
	cmp	r0, #EXP_MASK
	ite	ne
	movne	r0, #1
	moveq	r0, #0
	bx	lr

	.ltorg

@ ============================================================================
@ Constant data
@ ============================================================================
	.section .rodata.own.meas,"a",%progbits
	.p2align 2

@ meas_k - floats of the measurement core (offsets K_*, defined at the top)
meas_k:
	.word	0x3DAAAAAB		@ 1/12: variance of a 1-count quantiser
	.word	0x46100000		@ 9216 = 64 * 12^2: S/N 12 to become resolved
	.word	0x45800000		@ 4096 = 64 * 8^2: S/N 8 to stay resolved
	.word	0x3C000000		@ 1/128
	.word	0x3C800000		@ 1/64
	.word	0x42FA0000		@ 125 = 128 - 3 fitted values
	.word	0x38D1B717		@ 1e-4 = 0.01^2: the 1 % floor of the outlier limit
	.word	0x40C90FDB		@ 6.2831855 = 2 pi (as measure_33.s .L0800a7d4)
	.word	0xCE6E6B28		@ -1e9 (.L0800a7d8)
	.word	0x49742400		@ 1e6 (.L0800a4ac)
	.word	0x447A0000		@ 1000 (S2.6, D4)
	.word	0x461C4000		@ 10000
	.word	0x4545A471		@ 3162.2776 = sqrt(1000 * 10000)

@ meas_ck - floats of stage 4 (offsets CK_*, defined at the top)
meas_ck:
	.word	0x43340000		@ 180.0
	.word	0x3C8EFA35		@ 0.017453292 = pi / 180
	.word	0x47C35000		@ 100000.0
	.word	0x2B8CBCCC		@ 1e-12

@ freq_cycle - the frequency key cycle of own_freq_step (S2.12), Hz
freq_cycle:
	.word	60, 100, 120, 1000, 10000, 100000

@ hold_words - block offsets of the six words a hold latches (meas_hold, S2.7 / D2): frequency,
@   level, bias, range, speed, circuit
hold_words:
	.short	VB_FREQ, VB_LEVEL, VB_BIAS, VB_RANGE, VB_SPEED, VB_CIRCUIT
	.p2align 2

@ meas_ib - (B_k, S_k) of the decade interpolation, k = 1..9 (measure_33.s literals)
meas_ib:
	.word	0x3C23D70A, 0x3DB851EC	@ 0.01, 0.09
	.word	0x3DCCCCCD, 0x3F666666	@ 0.1, 0.9
	.word	0x3F800000, 0x41100000	@ 1, 9
	.word	0x41200000, 0x42B40000	@ 10, 90
	.word	0x42C80000, 0x44610000	@ 100, 900
	.word	0x447A0000, 0x460CA000	@ 1000, 9000
	.word	0x461C4000, 0x47AFC800	@ 10000, 90000
	.word	0x47C35000, 0x495BBA00	@ 100000, 900000
	.word	0x49742400, 0x4B095440	@ 1000000, 9000000

@ meas_cos - c[m] = cos(2 pi m / 128), m = 0..127, float32 rounded to nearest; c[32] = c[96] =
@   0 and c[64 - m] = -c[m], c[128 - m] = c[m] exactly (the 33 values of m = 0..32 with signs).
@   sin(2 pi m / 128) = c[(m - 32) & 127].
meas_cos:
	.word	0x3F800000		@  0  1.000000000
	.word	0x3F7FB10F		@  1  0.998795456
	.word	0x3F7EC46D		@  2  0.995184727
	.word	0x3F7D3AAC		@  3  0.989176510
	.word	0x3F7B14BE		@  4  0.980785280
	.word	0x3F7853F8		@  5  0.970031253
	.word	0x3F74FA0B		@  6  0.956940336
	.word	0x3F710908		@  7  0.941544065
	.word	0x3F6C835E		@  8  0.923879533
	.word	0x3F676BD8		@  9  0.903989293
	.word	0x3F61C598		@ 10  0.881921264
	.word	0x3F5B941A		@ 11  0.857728610
	.word	0x3F54DB31		@ 12  0.831469612
	.word	0x3F4D9F02		@ 13  0.803207531
	.word	0x3F45E403		@ 14  0.773010453
	.word	0x3F3DAEF9		@ 15  0.740951125
	.word	0x3F3504F3		@ 16  0.707106781
	.word	0x3F2BEB4A		@ 17  0.671558955
	.word	0x3F226799		@ 18  0.634393284
	.word	0x3F187FC0		@ 19  0.595699304
	.word	0x3F0E39DA		@ 20  0.555570233
	.word	0x3F039C3D		@ 21  0.514102744
	.word	0x3EF15AEA		@ 22  0.471396737
	.word	0x3EDAE880		@ 23  0.427555093
	.word	0x3EC3EF15		@ 24  0.382683432
	.word	0x3EAC7CD4		@ 25  0.336889853
	.word	0x3E94A031		@ 26  0.290284677
	.word	0x3E78CFCC		@ 27  0.242980180
	.word	0x3E47C5C2		@ 28  0.195090322
	.word	0x3E164083		@ 29  0.146730474
	.word	0x3DC8BD36		@ 30  0.098017140
	.word	0x3D48FB30		@ 31  0.049067674
	.word	0x00000000		@ 32  0
	.word	0xBD48FB30		@ 33 -0.049067674
	.word	0xBDC8BD36		@ 34 -0.098017140
	.word	0xBE164083		@ 35 -0.146730474
	.word	0xBE47C5C2		@ 36 -0.195090322
	.word	0xBE78CFCC		@ 37 -0.242980180
	.word	0xBE94A031		@ 38 -0.290284677
	.word	0xBEAC7CD4		@ 39 -0.336889853
	.word	0xBEC3EF15		@ 40 -0.382683432
	.word	0xBEDAE880		@ 41 -0.427555093
	.word	0xBEF15AEA		@ 42 -0.471396737
	.word	0xBF039C3D		@ 43 -0.514102744
	.word	0xBF0E39DA		@ 44 -0.555570233
	.word	0xBF187FC0		@ 45 -0.595699304
	.word	0xBF226799		@ 46 -0.634393284
	.word	0xBF2BEB4A		@ 47 -0.671558955
	.word	0xBF3504F3		@ 48 -0.707106781
	.word	0xBF3DAEF9		@ 49 -0.740951125
	.word	0xBF45E403		@ 50 -0.773010453
	.word	0xBF4D9F02		@ 51 -0.803207531
	.word	0xBF54DB31		@ 52 -0.831469612
	.word	0xBF5B941A		@ 53 -0.857728610
	.word	0xBF61C598		@ 54 -0.881921264
	.word	0xBF676BD8		@ 55 -0.903989293
	.word	0xBF6C835E		@ 56 -0.923879533
	.word	0xBF710908		@ 57 -0.941544065
	.word	0xBF74FA0B		@ 58 -0.956940336
	.word	0xBF7853F8		@ 59 -0.970031253
	.word	0xBF7B14BE		@ 60 -0.980785280
	.word	0xBF7D3AAC		@ 61 -0.989176510
	.word	0xBF7EC46D		@ 62 -0.995184727
	.word	0xBF7FB10F		@ 63 -0.998795456
	.word	0xBF800000		@ 64 -1.000000000
	.word	0xBF7FB10F		@ 65 -0.998795456
	.word	0xBF7EC46D		@ 66 -0.995184727
	.word	0xBF7D3AAC		@ 67 -0.989176510
	.word	0xBF7B14BE		@ 68 -0.980785280
	.word	0xBF7853F8		@ 69 -0.970031253
	.word	0xBF74FA0B		@ 70 -0.956940336
	.word	0xBF710908		@ 71 -0.941544065
	.word	0xBF6C835E		@ 72 -0.923879533
	.word	0xBF676BD8		@ 73 -0.903989293
	.word	0xBF61C598		@ 74 -0.881921264
	.word	0xBF5B941A		@ 75 -0.857728610
	.word	0xBF54DB31		@ 76 -0.831469612
	.word	0xBF4D9F02		@ 77 -0.803207531
	.word	0xBF45E403		@ 78 -0.773010453
	.word	0xBF3DAEF9		@ 79 -0.740951125
	.word	0xBF3504F3		@ 80 -0.707106781
	.word	0xBF2BEB4A		@ 81 -0.671558955
	.word	0xBF226799		@ 82 -0.634393284
	.word	0xBF187FC0		@ 83 -0.595699304
	.word	0xBF0E39DA		@ 84 -0.555570233
	.word	0xBF039C3D		@ 85 -0.514102744
	.word	0xBEF15AEA		@ 86 -0.471396737
	.word	0xBEDAE880		@ 87 -0.427555093
	.word	0xBEC3EF15		@ 88 -0.382683432
	.word	0xBEAC7CD4		@ 89 -0.336889853
	.word	0xBE94A031		@ 90 -0.290284677
	.word	0xBE78CFCC		@ 91 -0.242980180
	.word	0xBE47C5C2		@ 92 -0.195090322
	.word	0xBE164083		@ 93 -0.146730474
	.word	0xBDC8BD36		@ 94 -0.098017140
	.word	0xBD48FB30		@ 95 -0.049067674
	.word	0x00000000		@ 96  0
	.word	0x3D48FB30		@ 97  0.049067674
	.word	0x3DC8BD36		@ 98  0.098017140
	.word	0x3E164083		@ 99  0.146730474
	.word	0x3E47C5C2		@ 100 0.195090322
	.word	0x3E78CFCC		@ 101 0.242980180
	.word	0x3E94A031		@ 102 0.290284677
	.word	0x3EAC7CD4		@ 103 0.336889853
	.word	0x3EC3EF15		@ 104 0.382683432
	.word	0x3EDAE880		@ 105 0.427555093
	.word	0x3EF15AEA		@ 106 0.471396737
	.word	0x3F039C3D		@ 107 0.514102744
	.word	0x3F0E39DA		@ 108 0.555570233
	.word	0x3F187FC0		@ 109 0.595699304
	.word	0x3F226799		@ 110 0.634393284
	.word	0x3F2BEB4A		@ 111 0.671558955
	.word	0x3F3504F3		@ 112 0.707106781
	.word	0x3F3DAEF9		@ 113 0.740951125
	.word	0x3F45E403		@ 114 0.773010453
	.word	0x3F4D9F02		@ 115 0.803207531
	.word	0x3F54DB31		@ 116 0.831469612
	.word	0x3F5B941A		@ 117 0.857728610
	.word	0x3F61C598		@ 118 0.881921264
	.word	0x3F676BD8		@ 119 0.903989293
	.word	0x3F6C835E		@ 120 0.923879533
	.word	0x3F710908		@ 121 0.941544065
	.word	0x3F74FA0B		@ 122 0.956940336
	.word	0x3F7853F8		@ 123 0.970031253
	.word	0x3F7B14BE		@ 124 0.980785280
	.word	0x3F7D3AAC		@ 125 0.989176510
	.word	0x3F7EC46D		@ 126 0.995184727
	.word	0x3F7FB10F		@ 127 0.998795456
