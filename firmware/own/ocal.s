@ ocal.s - the own calibration area 0x08062000..0x08065FFF: load, atomic write, rollback, value
@ checks, the gain correction lookup (S4.3), the clip limits (S4.5), the settle times (S4.6),
@ the code lock, the raw window record, the settle trace and the level-monitor values (S4.8),
@ and the commands OCAL_INFO .. OCAL_TRACE (0x30..0x36).
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ Revision 3, integrated with these choices: capability bit 26 (CAP_OCAL), the MEASURE flags
@ byte 65, the state of OWN_OCAL 0xA0 bytes (the level-monitor snapshot added after OCS_KIND).
@
@ Flash (never-brick): the area is two slots of 0x2000 bytes (slot 0 0x08062000, slot 1
@ 0x08064000). Every erase and every program goes through save.s flash_erase_page /
@ flash_word, inside save.s gate_ok, which admits [OCAL_BASE, OCAL_END) only while
@ flash_ocal_gate has stored OCAL_BASE in SVO_OCAL. Every function here that opens the gate
@ closes it before it returns. This file holds no flash-controller address, no store to a
@ flash address, no literal of a vendor table or vendor function, and as flash
@ addresses only OCAL_BASE, OCAL_BASE + OCAL_SLOT and its own symbols (check_never_brick A6).
@ The serial (chip UID 0x1FFFF7F0..0x1FFFF7FB) is only read; the option bytes, the settings
@ copies, the calibration tables in RAM 0x2000057C..0x2000118F and OWN_STAGE are never written.
@
@ RAM: only OWN_OCAL (offsets below; own_start clears it to 0 at every start, which leaves the
@ gate word SVO_OCAL of save.s at 0, closed). Vendor words are only read: the frequency, level,
@ bias, screen, calibration-run words, the code bytes 0x200011C5 / C6 / C8, the ADC extremes
@ 0x200011CA..0x200011D9, the user table's short / open entries, the tick 0x20000480; meas.s's
@ state OWN_MEAS (window number, N, class, K, sums, the acquisition MO_X, noise powers) and
@ ctl.s's state (CT_FLAGS, the job words) are only read.
@
@ Record: header 0x40 bytes: magic 0x4C41434F, format u16 1, header size u16
@ 0x40, length u32 (0x40..0x2000, multiple of 4), sequence u32 (1..0xFFFFFFFE), chip UID 3
@ words, short / open CRC u32 (2.5), 0x20..0x37 zero, revoke word +0x38 (0xFFFFFFFF in force),
@ CRC-32 +0x3C over bytes 0x00..0x37 then 0x40..length-1 (the commit word, programmed last).
@ Body: sections {id u16, length u16, body}, ids strictly ascending: 0 META (32), 1 GAIN (6 x
@ 332), 2 CLIP (64), 3 SETTLE (84), 4 MONITOR (28), 5 BIAS (4); other ids are skipped.
@ Frequency index fi: 100, 120, 1000, 10000, 100000, 60 Hz -> 0..5 (word 0x20001144).
@
@ Calling convention of every exported function: AAPCS; r0..r3, r12, the flags and s0..s15
@ clobbered unless the function says less; r4..r11 and s16..s31 kept. The handlers h_ocal_*
@ follow cmd.s: r0 = request payload, r1 = its length, r2 = answer data (room for 511 bytes);
@ they return r0 = status (S_*) and r1 = data length.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"
	.include "own/ctl.inc"

@ ---- offsets in OWN_OCAL (OCS_KIND and OCS_TMAX are in own.inc: meas.s reads them) ----
	.equ	OCS_FLAGS,	0x00		@ load flags: OF_ACTIVE, OF_SLOT0_VALID, OF_SLOT1_VALID,
						@ OF_NEWER, OF_UID, OF_SECT
	.equ	OCS_ACT,	0x04		@ active slot 0 / 1, 0xFF none
	.equ	OCS_ASEQ,	0x08		@ sequence of the active record, 0 none
	.equ	OCS_OSEQ,	0x0C		@ other slot's sequence (0 when CRC-invalid); with no
						@ active record the higher CRC-valid sequence of both
	.equ	OCS_PRES,	0x1C		@ sections present: bit = id (ids 0..7) of the active
	.equ	OCS_REJ,	0x20		@ sections rejected at load: bit = id
	.equ	OCS_PTR,	0x24		@ 6 section pointers, id 0..5 at +4 id:
	.equ	OCS_META,	0x24		@   META body or 0
	.equ	OCS_GAIN,	0x28		@   GAIN body or 0
	.equ	OCS_CLIP,	0x2C		@   CLIP body (default ocal_def_clip)
	.equ	OCS_SETTLE,	0x30		@   SETTLE body (default ocal_def_settle)
	.equ	OCS_MON,	0x34		@   MONITOR body or 0
	.equ	OCS_BIAS,	0x38		@   BIAS body (default ocal_def_bias)
						@ 0x3C OCS_TMAX (own.inc): largest settle value in use
	.equ	OCS_GFREQ,	0x40		@ bit fi: some cell of fi has all four GAIN bits
	.equ	OCS_MFREQ,	0x44		@ bit fi: MONITOR kV calibrated
	.equ	OCS_LOCK,	0x48		@ 0, or c5 | c6 << 8 | c8 << 16 | 1 << 24 while locked
	.equ	OCS_LOCKT,	0x4C		@ tick of the last OCAL_LOCK / OCAL_RAW while locked
	.equ	OCS_XNEXT,	0x50		@ OCAL_WRITE: next expected offset
	.equ	OCS_XTOT,	0x54		@ OCAL_WRITE: body length of the transfer
	.equ	OCS_XCRC,	0x58		@ OCAL_WRITE: CRC-32 of the body the chunks carry
	.equ	OCS_XON,	0x5C		@ 1 while a transfer is open
	.equ	OCS_TST,	0x60		@ trace: 0 idle, 1 armed, 2 recording, 3 full
	.equ	OCS_TKIND,	0x64		@ trace: kind of the change
	.equ	OCS_TTICK,	0x68		@ trace: tick of the change
	.equ	OCS_TCNT,	0x6C		@ trace: entries recorded
	.equ	OCS_GFL,	0x70		@ MEASURE flags bits 0 / 1 of the last publish
	.equ	OCS_RFL,	0x74		@ raw flags since the last close: bit 0 saturated, bit 1
						@ overload published
	.equ	OCS_RST,	0x78		@ 1: a record was loaded, meas_watch restarts the settle
						@ 0x7C OCS_KIND (own.inc): byte, kind of the last meas_change
	.equ	OCS_MSEQ,	0x80		@ monitor snapshot of the last published window: number
	.equ	OCS_MCODES,	0x84		@   codes c5 | c6 << 8 | c8 << 16
	.equ	OCS_MAV,	0x88		@   A_V (float)
	.equ	OCS_MAI,	0x8C		@   A_I (float)
	.equ	OCS_MZN,	0x90		@   |zeta| applied (1.0 when the gain was not applied)
	.equ	OCS_MNU,	0x94		@   |nu| applied (1.0 likewise)
	.equ	OCS_MOK,	0x98		@   1 once a window was published since the start
	.equ	OCS_MFI,	0x9C		@   its frequency index, 0xFF none
	.equ	OCS_RAW,	0xA0		@ the OCAL_RAW record, 64 bytes
	.equ	OCS_TRACE,	0xE0		@ the trace, 32 entries of 16 bytes
	.equ	OCS_STAGE,	0x2E0		@ the staged record: header 0x40 + body up to 0x9C0
	.equ	OCS_END,	0xCE0
	.if	OCS_END > OCAL_SIZE
	.error	"ocal.s: the state does not fit O_OCAL"
	.endif
	.if	OCS_KIND != 0x7C || OCS_TMAX != 0x3C
	.error	"ocal.s: OCS_KIND / OCS_TMAX of own.inc do not match this layout"
	.endif

@ ---- the record ----
	.equ	REC_MAGIC,	0x4C41434F	@ "OCAL" little-endian
	.equ	RH_FMT,		0x04		@ u16 format; u16 header size at +0x06
	.equ	RH_HSIZE,	0x06
	.equ	RH_LEN,		0x08
	.equ	RH_SEQ,		0x0C
	.equ	RH_UID,		0x10
	.equ	RH_SOCRC,	0x1C
	.equ	RH_RES,		0x20		@ 0x20..0x37 reserved, 0
	.equ	RH_REVOKE,	0x38
	.equ	RH_CRC,		0x3C
	.equ	RH_SIZE,	0x40
	.equ	RH_FMTWORD,	0x00400001	@ format 1, header size 0x40
	.equ	BODY_MIN,	8
	.equ	BODY_MAX,	0x9C0		@ staging 0xA00 - header
	.equ	CHUNK_MAX,	502		@ 512-byte payload - 10 header bytes

@ slot classes of ocal_eval
	.equ	CL_VALID,	1		@ magic, sizes, sequence, CRC
	.equ	CL_OWN,		2		@ and this chip's UID
	.equ	CL_FORCE,	4		@ revoke word 0xFFFFFFFF
	.equ	CL_ALL,		7
@ scan table: per slot cls, seq, format, length
	.equ	SC_CLS,		0
	.equ	SC_SEQ,		4
	.equ	SC_FMT,		8
	.equ	SC_LEN,		12
	.equ	SC_SIZE,	16

@ OCAL_INFO flags
	.equ	OF_ACTIVE,	1 << 0
	.equ	OF_V0,		1 << 1		@ OF_SLOT0_VALID
	.equ	OF_V1,		1 << 2		@ OF_SLOT1_VALID
	.equ	OF_NEWER,	1 << 3
	.equ	OF_UID,		1 << 4
	.equ	OF_SECT,	1 << 5
	.equ	OF_RETAKE,	1 << 6
	.equ	OF_LOCK,	1 << 7
	.equ	OF_XFER,	1 << 8
	.equ	OF_TRACE,	1 << 9

@ section ids
	.equ	SID_META,	0
	.equ	SID_GAIN,	1
	.equ	SID_CLIP,	2
	.equ	SID_SETTLE,	3
	.equ	SID_MON,	4
	.equ	SID_BIAS,	5
	.equ	SID_LAST,	5
@ GAIN entry of one frequency (332 bytes)
	.equ	GE_ZM,		0		@ zeta magnitude mask u32, bit 8 c8 + c6
	.equ	GE_ZP,		4		@ zeta phase mask u32
	.equ	GE_NM,		8		@ nu magnitude mask u8, bit c5
	.equ	GE_NP,		9		@ nu phase mask u8
	.equ	GE_PAD,		10		@ u16, 0
	.equ	GE_ZETA,	12		@ zeta[8 c8 + c6] (re, im), 32 entries
	.equ	GE_NU,		268		@ nu[c5] (re, im), 8 entries
	.equ	GE_SIZE,	332
	.equ	GE_IDX,		41		@ entry index of a GAIN error: 41 fi + k (k 0..31 zeta,
						@ 32..39 nu, 40 the pad halfword)
	.equ	NFREQ,		6

@ OCAL_RAW record
	.equ	RW_WIN,		0
	.equ	RW_C5,		4
	.equ	RW_C6,		5
	.equ	RW_C8,		6
	.equ	RW_LOCK,	7
	.equ	RW_FREQ,	8
	.equ	RW_LEVEL,	12
	.equ	RW_BIAS,	16
	.equ	RW_N,		20
	.equ	RW_CLS,		22
	.equ	RW_FL,		23
	.equ	RW_ZR,		24
	.equ	RW_ZI,		28
	.equ	RW_AV,		32
	.equ	RW_AI,		36
	.equ	RW_SV,		40
	.equ	RW_SI,		44
	.equ	RW_MAX1,	48
	.equ	RW_MIN1,	50
	.equ	RW_MID1,	52
	.equ	RW_MAX2,	54
	.equ	RW_MIN2,	56
	.equ	RW_MID2,	58
	.equ	RW_PAD,		60
	.equ	RAW_SIZE,	64
@ trace entry (the OCAL_TRACE answer layout)
	.equ	TE_TICK,	0
	.equ	TE_ZR,		4
	.equ	TE_ZI,		8
	.equ	TE_FL,		12
	.equ	TE_C5,		13
	.equ	TE_C6,		14
	.equ	TE_C8,		15
	.equ	TE_SIZE,	16
	.equ	TRACE_N,	32
	.equ	TRACE_PER,	31		@ entries per OCAL_TRACE answer (8 + 31 x 16 = 504)
	.equ	INFO_LEN,	64
	.equ	LOCK_MS,	30000		@ lock released 30 s after the last OCAL_LOCK / OCAL_RAW
	.equ	LOCK_ON,	0x01000000

@ meas.s state words read here (meas.s header, offsets in OWN_MEAS)
	.equ	OM_SEQ,		0x2C		@ windows closed
	.equ	OM_CLS,		0x30		@ class 0 noise-limited, 1 resolved
	.equ	OM_N,		0x3C		@ accepted acquisitions of the window
	.equ	OM_K,		0x54		@ K of the window (float)
	.equ	OM_SUM,		0x6C		@ sum V'r, V'i, I'r, I'i
	.equ	OM_X,		0xD4		@ the acquisition: Vr, Vi, Ir, Ii
	.equ	OM_SIG,		0xEC		@ noise power of V and I

@ vendor RAM read here (meas.s VB_* / own.inc)
	.equ	V_C5B,		0x200011C5	@ byte: V gain code c5
	.equ	V_C6B,		0x200011C6	@ byte: I gain code c6
	.equ	V_C8B,		0x200011C8	@ byte: range code c8
	.equ	V_MAX1,		0x200011CA	@ halfwords: ADC1 max, min (+2), mid (+6); ADC2 max (+8),
						@ min (+10), mid (+14) (fn_08007fd4 / fn_08007f38)
	.equ	V_USER_TAB,	0x20000B20	@ user table: entry of point p (3 fi + li) at + 0x30 p,
						@ type t at + 4 t, its phase at + 0x2D0
	.equ	UT_OPEN,	0x2C		@ type 11 (open)
	.equ	UT_PHASE,	0x2D0

@ floats
	.equ	F_NAN,		0x7FC00000	@ quiet NaN
	.equ	F_ONE,		0x3F800000
	.equ	F_64,		0x42800000	@ 64.0
	.equ	F_1EM6,		0x358637BD	@ 1e-6
	.equ	EXP_BITS,	0x7F800000	@ exponent field: all ones = Inf or NaN

	.section .rodata.own.ocal,"a",%progbits
	.p2align 2
@ ocal_freqs - the frequency of each index fi (the host list order)
ocal_freqs:
	.word	100, 120, 1000, 10000, 100000, 60
@ ocal_defaults - the section pointers (no record, or the section absent /
@   rejected): META, GAIN, MONITOR none; CLIP, SETTLE, BIAS the stage-1 values below
ocal_defaults:
	.word	0, 0, ocal_def_clip, ocal_def_settle, 0, ocal_def_bias
@ ocal_def_clip - CLIP default: lo 0, hi 4095 for both channels and every gain code, which is
@   the stage-1 saturation test (a sample at 0 or 4095, meas.s meas_acq)
ocal_def_clip:
	.rept	16
	.short	0, 4095
	.endr
@ ocal_def_settle - SETTLE default [kind][fi]: kinds 0..4 (restart, frequency, level, bias,
@   speed) 26 ms, kinds 5, 6 (screen, codes) 5 ms (meas.s meas_watch, stage 1)
ocal_def_settle:
	.rept	30
	.short	26
	.endr
	.rept	12
	.short	5
	.endr
@ ocal_def_bias - BIAS default: the S4.4 constant BIAS_LIM of meas.s (4 counts), pad 0
ocal_def_bias:
	.short	4, 0
@ ocal_lens - the body length of each known id 0..5
ocal_lens:
	.short	32, 1992, 64, 84, 28, 4

	.section .text.own.ocal,"ax",%progbits
	.p2align 2

@ ============================================================================
@ Slots: evaluation, choice of the active record, write target and sequence
@ ============================================================================

@ ----------------------------------------------------------------------------
@ ocal_eval - r0 = slot base. Step 1 of the load, from flash: CRC-valid = magic, header size
@   0x40, length 0x40..0x2000 and a multiple of 4, sequence neither 0 nor 0xFFFFFFFF, CRC-32 of
@   bytes 0..0x37 and 0x40..length-1 equal to +0x3C; own = CRC-valid and UID equal to the
@   chip's three words; in force = revoke word 0xFFFFFFFF (only examined when CRC-valid).
@   Returns r0 = CL_* bits, r1 = sequence, r2 = format, r3 = length (the raw header words).
@   Reads flash only. Changes r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_eval, %function
ocal_eval:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r4, r0			@ r4 = slot base
	movs	r5, #0			@ r5 = class
	ldr	r6, [r4, #RH_SEQ]	@ r6 = sequence
	ldrh	r7, [r4, #RH_FMT]	@ r7 = format
	ldr	r8, [r4, #RH_LEN]	@ r8 = length
	ldr	r0, [r4, #0]
	ldr	r1, =REC_MAGIC
	cmp	r0, r1
	bne	.Lev_out
	ldrh	r0, [r4, #RH_HSIZE]
	cmp	r0, #RH_SIZE
	bne	.Lev_out
	cmp	r8, #RH_SIZE
	blo	.Lev_out
	cmp	r8, #OCAL_SLOT
	bhi	.Lev_out
	tst	r8, #3
	bne	.Lev_out
	cmp	r6, #0
	beq	.Lev_out
	adds	r0, r6, #1
	beq	.Lev_out		@ 0xFFFFFFFF
	mvn	r0, #0
	mov	r1, r4
	movs	r2, #RH_REVOKE		@ bytes 0x00..0x37
	bl	own_crc32_update
	add	r1, r4, #RH_SIZE
	sub	r2, r8, #RH_SIZE	@ bytes 0x40..length-1 (0 allowed)
	bl	own_crc32_update
	mvns	r0, r0
	ldr	r1, [r4, #RH_CRC]
	cmp	r0, r1
	bne	.Lev_out
	movs	r5, #CL_VALID
	ldr	r2, =CHIP_UID
	ldr	r0, [r4, #RH_UID]
	ldr	r1, [r2, #0]
	cmp	r0, r1
	bne	.Lev_force
	ldr	r0, [r4, #RH_UID + 4]
	ldr	r1, [r2, #4]
	cmp	r0, r1
	bne	.Lev_force
	ldr	r0, [r4, #RH_UID + 8]
	ldr	r1, [r2, #8]
	cmp	r0, r1
	it	eq
	orreq	r5, r5, #CL_OWN
.Lev_force:
	ldr	r0, [r4, #RH_REVOKE]
	adds	r0, r0, #1		@ zero only for exactly 0xFFFFFFFF
	it	eq
	orreq	r5, r5, #CL_FORCE
.Lev_out:
	mov	r0, r5
	mov	r1, r6
	mov	r2, r7
	mov	r3, r8
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ ocal_scan - r0 = scan table (2 x SC_SIZE bytes): both slots evaluated by ocal_eval, slot 0
@   at +0, slot 1 at +SC_SIZE. Reads flash only. Changes r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_scan, %function
ocal_scan:
	push	{r4, lr}
	mov	r4, r0
	ldr	r0, =OCAL_BASE
	bl	ocal_eval
	stm	r4, {r0, r1, r2, r3}	@ cls, seq, format, length of slot 0
	ldr	r0, =OCAL_BASE + OCAL_SLOT
	bl	ocal_eval
	add	r12, r4, #SC_SIZE
	stm	r12, {r0, r1, r2, r3}	@ slot 1
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ ocal_pick - r0 = scan table. Steps 2..3 of the load: candidates = own records in force; N =
@   the candidate with the higher sequence (slot 0 on equal sequences); N of format 1 is the
@   active record, another format gives none and OF_NEWER. Returns r0 = active slot 0 / 1 or
@   0xFF, r1 = 1 when N exists with another format, else 0. Changes r2, r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_pick, %function
ocal_pick:
	ldr	r1, [r0, #SC_CLS]
	ldr	r2, [r0, #SC_SIZE + SC_CLS]
	cmp	r1, #CL_ALL
	bne	.Lpk_one
	movs	r3, #0			@ r3 = N: slot 0 is a candidate
	cmp	r2, #CL_ALL
	bne	.Lpk_fmt
	ldr	r1, [r0, #SC_SEQ]
	ldr	r2, [r0, #SC_SIZE + SC_SEQ]
	cmp	r2, r1
	it	hi
	movhi	r3, #1			@ slot 1 only with the higher sequence
	b	.Lpk_fmt
.Lpk_one:
	cmp	r2, #CL_ALL
	bne	.Lpk_none
	movs	r3, #1
.Lpk_fmt:
	add	r12, r0, r3, lsl #4	@ the scan entry of N (SC_SIZE 16)
	ldr	r1, [r12, #SC_FMT]
	cmp	r1, #1
	bne	.Lpk_newer
	mov	r0, r3
	movs	r1, #0
	bx	lr
.Lpk_newer:
	movs	r0, #0xFF		@ a newer own record this firmware cannot read
	movs	r1, #1
	bx	lr
.Lpk_none:
	movs	r0, #0xFF
	movs	r1, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ ocal_target - r0 = scan table -> r0 = write target T (step 1 of the write):
@   (a) a record is active: the other slot; (b) a slot with
@   no CRC-valid record, slot 0 when both; (c) a slot whose record has another UID, then one
@   whose own record is revoked; both slots of the same class: the lower sequence, slot 0 on
@   equal sequences; (d) the lower sequence, slot 1 on equal sequences. Changes r1..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_target, %function
ocal_target:
	push	{r4, lr}
	mov	r4, r0
	bl	ocal_pick
	cmp	r0, #0xFF
	beq	.Ltg_b
	rsb	r0, r0, #1		@ (a) the other slot
	pop	{r4, pc}
.Ltg_b:
	ldr	r1, [r4, #SC_CLS]
	ldr	r2, [r4, #SC_SIZE + SC_CLS]
	tst	r1, #CL_VALID
	beq	.Ltg_0			@ (b) slot 0 holds no CRC-valid record
	tst	r2, #CL_VALID
	beq	.Ltg_1			@ (b) slot 1
	ldr	r12, [r4, #SC_SEQ]	@ r12 = sequence of slot 0
	ldr	r3, [r4, #SC_SIZE + SC_SEQ]	@ r3 = sequence of slot 1
	tst	r1, #CL_OWN
	bne	.Ltg_own0
	tst	r2, #CL_OWN
	bne	.Ltg_0			@ (c) only slot 0 foreign
	b	.Ltg_low0		@ (c) both foreign
.Ltg_own0:
	tst	r2, #CL_OWN
	beq	.Ltg_1			@ (c) only slot 1 foreign
	tst	r1, #CL_FORCE
	bne	.Ltg_force0
	tst	r2, #CL_FORCE
	bne	.Ltg_0			@ (c) only slot 0 revoked
	b	.Ltg_low0		@ (c) both revoked
.Ltg_force0:
	tst	r2, #CL_FORCE
	beq	.Ltg_1			@ (c) only slot 1 revoked
	cmp	r12, r3			@ (d) the lower sequence, slot 1 on equal sequences
	bhs	.Ltg_1
	b	.Ltg_0
.Ltg_low0:
	cmp	r3, r12			@ same class: slot 1 only with the lower sequence
	blo	.Ltg_1
.Ltg_0:
	movs	r0, #0
	pop	{r4, pc}
.Ltg_1:
	movs	r0, #1
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ ocal_nextseq - r0 = scan table, r1 = target T -> r0 = the sequence of the new record, or 0
@   when the write is refused (status 3). Step 2 of the write with G1: highest sequence of a
@   CRC-valid record in either slot + 1, 1 when none; when that would be 0xFFFFFFFF, O = the
@   record in the slot that is not T: O own and in force with 0xFFFFFFFE refuses; otherwise
@   O's sequence + 1 when O is CRC-valid and below 0xFFFFFFFE, else 1. Changes r1..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_nextseq, %function
ocal_nextseq:
	movs	r3, #0			@ r3 = highest CRC-valid sequence
	ldr	r2, [r0, #SC_CLS]
	tst	r2, #CL_VALID
	beq	.Lns_s1
	ldr	r3, [r0, #SC_SEQ]
.Lns_s1:
	ldr	r2, [r0, #SC_SIZE + SC_CLS]
	tst	r2, #CL_VALID
	beq	.Lns_q
	ldr	r2, [r0, #SC_SIZE + SC_SEQ]
	cmp	r2, r3
	it	hi
	movhi	r3, r2
.Lns_q:
	adds	r3, r3, #1		@ r3 = highest + 1
	adds	r2, r3, #1		@ zero when r3 = 0xFFFFFFFF
	bne	.Lns_ok
	rsb	r1, r1, #1		@ O = the slot that is not T
	add	r12, r0, r1, lsl #4
	ldr	r2, [r12, #SC_CLS]
	ldr	r3, [r12, #SC_SEQ]
	cmp	r2, #CL_ALL
	bne	.Lns_fb
	adds	r1, r3, #2		@ zero when O's sequence is 0xFFFFFFFE
	beq	.Lns_refuse		@ own, in force, 0xFFFFFFFE: a new record could not win
.Lns_fb:
	tst	r2, #CL_VALID
	beq	.Lns_one
	adds	r1, r3, #2
	beq	.Lns_one		@ 0xFFFFFFFE held by a foreign or revoked record
	adds	r0, r3, #1
	bx	lr
.Lns_one:
	movs	r0, #1
	bx	lr
.Lns_refuse:
	movs	r0, #0
	bx	lr
.Lns_ok:
	mov	r0, r3
	bx	lr

	.ltorg

@ ============================================================================
@ Load
@ ============================================================================

@ ----------------------------------------------------------------------------
@ ocal_walk - r0 = record base, r1 = record length L, r2 = table of 6 words (cleared by the
@   caller). Step 4 of the load: from o = 0x40 while o + 4 <= L: id and length s; stop with
@   OF_SECT when s is not a multiple of 4, o + 4 + s > L, or id is not above the previous id;
@   a known id (0..5) with exactly its length: table[id] = base + o + 4; a known id with another
@   length: ignored, OF_SECT and its rejected bit; any id below 8 sets its present bit; then
@   o += 4 + s. Every pointer lies in [base + 0x44, base + L). Reads only [base + 0x40,
@   base + L). Returns r0 = OF_SECT or 0, r1 = present bits, r2 = rejected bits. Changes r3,
@   r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_walk, %function
ocal_walk:
	push	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r4, r0			@ r4 = base
	mov	r5, r1			@ r5 = L
	mov	r6, r2			@ r6 = pointer table
	movs	r7, #RH_SIZE		@ r7 = o
	mvn	r8, #0			@ r8 = previous id, -1 before the first
	movs	r9, #0			@ r9 = present bits
	movs	r10, #0			@ r10 = rejected bits
	movs	r12, #0			@ r12 = OF_SECT when a rule stopped or rejected
.Lwk_next:
	adds	r0, r7, #4
	cmp	r0, r5
	bhi	.Lwk_end		@ o + 4 > L: the walk is complete
	ldrh	r1, [r4, r7]		@ r1 = id
	add	r2, r4, r7
	ldrh	r2, [r2, #2]		@ r2 = s
	tst	r2, #3
	bne	.Lwk_stop
	add	r0, r0, r2		@ r0 = o + 4 + s
	cmp	r0, r5
	bhi	.Lwk_stop		@ the body runs past the record
	cmp	r1, r8
	ble	.Lwk_stop		@ not strictly ascending (r8 signed: -1 first)
	mov	r8, r1
	cmp	r1, #8
	bhs	.Lwk_skip
	movs	r3, #1
	lsls	r3, r3, r1
	orr	r9, r9, r3		@ present
	cmp	r1, #SID_LAST
	bhi	.Lwk_skip		@ ids 6, 7: not known to this firmware
	ldr	r3, =ocal_lens
	ldrh	r3, [r3, r1, lsl #1]
	cmp	r2, r3
	beq	.Lwk_rec
	movs	r3, #1
	lsls	r3, r3, r1
	orr	r10, r10, r3		@ a known id with another length: rejected
	orr	r12, r12, #OF_SECT
	b	.Lwk_skip
.Lwk_rec:
	add	r3, r4, r7
	adds	r3, r3, #4
	str	r3, [r6, r1, lsl #2]	@ the body of this id
.Lwk_skip:
	mov	r7, r0			@ o = o + 4 + s
	b	.Lwk_next
.Lwk_stop:
	orr	r12, r12, #OF_SECT
.Lwk_end:
	mov	r0, r12
	mov	r1, r9
	mov	r2, r10
	pop	{r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ ocal_load - called by own_start after the clear of our RAM, and after every
@   commit and rollback. Both slots evaluated, the active record chosen (ocal_pick), the
@   section walk of the active record (ocal_walk), every recorded section checked by
@   ocal_validate_section (a failing one keeps its default, OF_SECT and its rejected bit), then
@   T_max (the largest SETTLE value in use, at least 26, the largest default), the GAIN and
@   MONITOR frequency bits, the flags. With no active record every pointer is its default.
@   Reads flash, writes only OWN_OCAL words 0x00..0x47 (the lock, the transfer, the trace, the
@   raw record and the snapshot are kept). Nothing is erased or programmed.
@ ----------------------------------------------------------------------------
	.global	ocal_load
	.thumb_func
	.type	ocal_load, %function
ocal_load:
	push	{r4, r5, r6, r7, r8, r9, r10, lr}
	sub	sp, #56			@ scan table at sp + 0 (32), walk table at sp + 32 (24)
	mov	r0, sp
	bl	ocal_scan
	ldr	r4, =OWN_OCAL
	mov	r0, sp
	bl	ocal_pick
	mov	r5, r0			@ r5 = active slot or 0xFF
	movs	r6, #0			@ r6 = flags
	cmp	r1, #0
	it	ne
	orrne	r6, r6, #OF_NEWER
	ldr	r0, [sp, #SC_CLS]
	ldr	r1, [sp, #SC_SIZE + SC_CLS]
	tst	r0, #CL_VALID
	it	ne
	orrne	r6, r6, #OF_V0
	tst	r1, #CL_VALID
	it	ne
	orrne	r6, r6, #OF_V1
	and	r2, r0, #CL_VALID | CL_OWN
	cmp	r2, #CL_VALID
	it	eq
	orreq	r6, r6, #OF_UID		@ slot 0: CRC-valid with another UID
	and	r2, r1, #CL_VALID | CL_OWN
	cmp	r2, #CL_VALID
	it	eq
	orreq	r6, r6, #OF_UID
	@ every pointer to its default; walk table (sp + 32 .. sp + 55) cleared
	ldr	r1, =ocal_defaults
	add	r2, r4, #OCS_PTR
	movs	r3, #6
.Lld_def:
	ldr	r0, [r1], #4
	str	r0, [r2], #4
	subs	r3, r3, #1
	bne	.Lld_def
	movs	r0, #0
	str	r0, [sp, #32]
	str	r0, [sp, #36]
	str	r0, [sp, #40]
	str	r0, [sp, #44]
	str	r0, [sp, #48]
	str	r0, [sp, #52]
	str	r0, [r4, #OCS_PRES]
	str	r0, [r4, #OCS_REJ]
	str	r5, [r4, #OCS_ACT]
	cmp	r5, #0xFF
	bne	.Lld_act
	@ no active record: sequence 0, "other" = the higher CRC-valid sequence of both slots
	str	r0, [r4, #OCS_ASEQ]
	movs	r3, #0
	ldr	r1, [sp, #SC_CLS]
	tst	r1, #CL_VALID
	it	ne
	ldrne	r3, [sp, #SC_SEQ]
	ldr	r1, [sp, #SC_SIZE + SC_CLS]
	ldr	r2, [sp, #SC_SIZE + SC_SEQ]
	tst	r1, #CL_VALID
	beq	.Lld_os
	cmp	r2, r3
	it	hi
	movhi	r3, r2
.Lld_os:
	str	r3, [r4, #OCS_OSEQ]
	b	.Lld_tail
.Lld_act:
	orr	r6, r6, #OF_ACTIVE
	add	r0, sp, r5, lsl #4
	ldr	r1, [r0, #SC_SEQ]
	str	r1, [r4, #OCS_ASEQ]
	ldr	r8, [r0, #SC_LEN]	@ r8 = L
	rsb	r2, r5, #1
	add	r0, sp, r2, lsl #4
	ldr	r1, [r0, #SC_CLS]
	ldr	r3, [r0, #SC_SEQ]
	tst	r1, #CL_VALID
	it	eq
	moveq	r3, #0
	str	r3, [r4, #OCS_OSEQ]
	ldr	r7, =OCAL_BASE
	add	r7, r7, r5, lsl #13	@ r7 = base of the active slot (OCAL_SLOT = 1 << 13)
	mov	r0, r7
	mov	r1, r8
	add	r2, sp, #32
	bl	ocal_walk
	orr	r6, r6, r0
	str	r1, [r4, #OCS_PRES]
	mov	r10, r2			@ r10 = rejected bits
	@ value checks of every recorded section (F4)
	movs	r9, #0			@ r9 = id
.Lld_chk:
	add	r0, sp, #32
	ldr	r1, [r0, r9, lsl #2]	@ r1 = recorded body or 0
	cmp	r1, #0
	beq	.Lld_nxt
	mov	r8, r1
	mov	r0, r9
	bl	ocal_validate_section
	cmp	r0, #0
	bne	.Lld_rej
	add	r0, r4, #OCS_PTR
	str	r8, [r0, r9, lsl #2]	@ in use
	b	.Lld_nxt
.Lld_rej:
	movs	r0, #1
	lsls	r0, r0, r9
	orr	r10, r10, r0
	orr	r6, r6, #OF_SECT	@ the default stays
.Lld_nxt:
	adds	r9, r9, #1
	cmp	r9, #SID_LAST
	bls	.Lld_chk
	str	r10, [r4, #OCS_REJ]
.Lld_tail:
	str	r6, [r4, #OCS_FLAGS]
	@ T_max: the largest SETTLE value in use, at least 26
	ldr	r1, [r4, #OCS_SETTLE]
	movs	r0, #26
	movs	r2, #42
.Lld_tmax:
	ldrh	r3, [r1], #2
	cmp	r3, r0
	it	hi
	movhi	r0, r3
	subs	r2, r2, #1
	bne	.Lld_tmax
	str	r0, [r4, #OCS_TMAX]
	@ GAIN frequencies: some zeta with both bits and some nu with both bits
	movs	r0, #0			@ r0 = bits
	ldr	r1, [r4, #OCS_GAIN]
	cmp	r1, #0
	beq	.Lld_gdone
	movs	r2, #0			@ r2 = fi
.Lld_gfi:
	ldr	r3, [r1, #GE_ZM]
	ldr	r12, [r1, #GE_ZP]
	ands	r3, r3, r12
	beq	.Lld_gnext
	ldrb	r3, [r1, #GE_NM]
	ldrb	r12, [r1, #GE_NP]
	ands	r3, r3, r12
	beq	.Lld_gnext
	movs	r3, #1
	lsls	r3, r3, r2
	orrs	r0, r0, r3
.Lld_gnext:
	add	r1, r1, #GE_SIZE
	adds	r2, r2, #1
	cmp	r2, #NFREQ
	blo	.Lld_gfi
.Lld_gdone:
	str	r0, [r4, #OCS_GFREQ]
	movs	r0, #0
	ldr	r1, [r4, #OCS_MON]
	cmp	r1, #0
	beq	.Lld_mdone
	ldr	r0, [r1]
	and	r0, r0, #0x3F		@ the validated mask: bits 0..5
.Lld_mdone:
	str	r0, [r4, #OCS_MFREQ]
	add	sp, #56
	pop	{r4, r5, r6, r7, r8, r9, r10, pc}

	.ltorg

@ ============================================================================
@ Value checks, shared by the write and the load
@ ============================================================================

@ ----------------------------------------------------------------------------
@ ocal_factor_ok - r0 = address of a factor (re f32, im f32) -> r0 = 1 when re and im are
@   finite, 0.25 <= re^2 + im^2 <= 4, re > 0 and 4 re^2 >= re^2 + im^2 (|arg| <= 60 degrees),
@   else 0. Unordered compares count as failures. Changes r1..r3, r12, s0..s4.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_factor_ok, %function
ocal_factor_ok:
	ldr	r1, [r0, #0]
	ldr	r2, [r0, #4]
	ldr	r3, =EXP_BITS
	and	r12, r1, r3
	cmp	r12, r3
	beq	.Lfo_no			@ re not finite
	and	r12, r2, r3
	cmp	r12, r3
	beq	.Lfo_no			@ im not finite
	vmov	s0, r1
	vmov	s1, r2
	vcmp.f32	s0, #0
	vmrs	APSR_nzcv, fpscr
	ble	.Lfo_no			@ re <= 0
	vmul.f32	s2, s0, s0	@ re^2
	vmul.f32	s3, s1, s1
	vadd.f32	s3, s3, s2	@ m = re^2 + im^2
	vmov.f32	s4, #0.25
	vcmpe.f32	s3, s4
	vmrs	APSR_nzcv, fpscr
	blt	.Lfo_no			@ m < 0.25
	vmov.f32	s4, #4.0
	vcmpe.f32	s3, s4
	vmrs	APSR_nzcv, fpscr
	bhi	.Lfo_no			@ m > 4 (or unordered)
	vmul.f32	s2, s2, s4	@ 4 re^2
	vcmpe.f32	s2, s3
	vmrs	APSR_nzcv, fpscr
	blt	.Lfo_no			@ |arg| > 60 degrees
	movs	r0, #1
	bx	lr
.Lfo_no:
	movs	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ ocal_validate_section - r0 = id, r1 = body (of the known length). The value rules of
@   that section. Returns r0 = 0 when the body passes (META and unknown ids always), else r0 = 1
@   and r1 = the entry index: GAIN 41 fi + k (k 0..31 zeta[k], 32..39 nu[k - 32], 40 the pad
@   halfword), CLIP 8 channel + code, SETTLE 6 kind + fi, MONITOR fi (6: mask bits above 5),
@   BIAS 0 the limit, 1 the pad. Changes r2, r3, r12, s0..s4.
@ ----------------------------------------------------------------------------
	.global	ocal_validate_section
	.thumb_func
	.type	ocal_validate_section, %function
ocal_validate_section:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r4, r1			@ r4 = body
	cmp	r0, #SID_GAIN
	beq	.Lvs_gain
	cmp	r0, #SID_CLIP
	beq	.Lvs_clip
	cmp	r0, #SID_SETTLE
	beq	.Lvs_settle
	cmp	r0, #SID_MON
	beq	.Lvs_mon
	cmp	r0, #SID_BIAS
	beq	.Lvs_bias
	b	.Lvs_ok			@ META, unknown ids: no value rule
.Lvs_gain:
	movs	r5, #0			@ r5 = fi
.Lvg_fi:
	movs	r7, #GE_IDX - 1		@ k = 40: the pad halfword
	ldrh	r0, [r4, #GE_PAD]
	cmp	r0, #0
	bne	.Lvg_bad
	ldr	r6, [r4, #GE_ZM]
	ldr	r0, [r4, #GE_ZP]
	orr	r6, r6, r0		@ r6 = zeta factors with a bit set
	movs	r7, #0			@ r7 = k
.Lvg_z:
	lsr	r0, r6, r7
	tst	r0, #1
	beq	.Lvg_zn
	add	r0, r4, #GE_ZETA
	add	r0, r0, r7, lsl #3
	bl	ocal_factor_ok
	cmp	r0, #0
	beq	.Lvg_bad
.Lvg_zn:
	adds	r7, r7, #1
	cmp	r7, #32
	blo	.Lvg_z
	ldrb	r6, [r4, #GE_NM]
	ldrb	r0, [r4, #GE_NP]
	orr	r6, r6, r0		@ r6 = nu factors with a bit set
	movs	r8, #0			@ r8 = c5
.Lvg_n:
	lsr	r0, r6, r8
	tst	r0, #1
	beq	.Lvg_nn
	add	r0, r4, #GE_NU
	add	r0, r0, r8, lsl #3
	bl	ocal_factor_ok
	cmp	r0, #0
	bne	.Lvg_nn
	add	r7, r8, #32		@ k = 32 + c5
	b	.Lvg_bad
.Lvg_nn:
	adds	r8, r8, #1
	cmp	r8, #8
	blo	.Lvg_n
	add	r4, r4, #GE_SIZE
	adds	r5, r5, #1
	cmp	r5, #NFREQ
	blo	.Lvg_fi
	b	.Lvs_ok
.Lvg_bad:
	movs	r1, #GE_IDX
	mul	r1, r5, r1
	add	r1, r1, r7		@ index 41 fi + k
	b	.Lvs_bad
.Lvs_clip:
	movs	r1, #0			@ r1 = 8 channel + code
.Lvc_next:
	ldrh	r2, [r4, r1, lsl #2]	@ lo
	add	r3, r4, r1, lsl #2
	ldrh	r3, [r3, #2]		@ hi
	movw	r12, #4095
	cmp	r3, r12
	bhi	.Lvs_bad		@ hi > 4095
	cmp	r2, r3
	bhs	.Lvs_bad		@ lo >= hi
	subs	r3, r3, r2
	movw	r12, #3600
	cmp	r3, r12
	bls	.Lvs_bad		@ hi - lo <= 3600
	adds	r1, r1, #1
	cmp	r1, #16
	blo	.Lvc_next
	b	.Lvs_ok
.Lvs_settle:
	movs	r1, #0			@ r1 = 6 kind + fi
.Lvt_next:
	ldrh	r2, [r4, r1, lsl #1]
	cmp	r2, #0
	beq	.Lvs_bad		@ 0 would skip the window reset (meas_watch cbz r7)
	cmp	r2, #500
	bhi	.Lvs_bad
	adds	r1, r1, #1
	cmp	r1, #42
	blo	.Lvt_next
	b	.Lvs_ok
.Lvs_mon:
	ldr	r5, [r4]		@ r5 = mask
	movs	r1, #NFREQ
	bics	r0, r5, #0x3F
	bne	.Lvs_bad		@ mask bits above 5: index 6
	movs	r1, #0			@ r1 = fi
.Lvm_next:
	lsr	r0, r5, r1
	tst	r0, #1
	beq	.Lvm_nn
	add	r0, r4, r1, lsl #2
	ldr	r0, [r0, #4]		@ kV[fi] bits
	ldr	r3, =EXP_BITS
	and	r12, r0, r3
	cmp	r12, r3
	beq	.Lvs_bad		@ not finite
	vmov	s0, r0
	ldr	r0, =F_1EM6
	vmov	s1, r0
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	blt	.Lvs_bad		@ below 1e-6
	vmov.f32	s1, #1.0
	vcmpe.f32	s0, s1
	vmrs	APSR_nzcv, fpscr
	bhi	.Lvs_bad		@ above 1
.Lvm_nn:
	adds	r1, r1, #1
	cmp	r1, #NFREQ
	blo	.Lvm_next
	b	.Lvs_ok
.Lvs_bias:
	movs	r1, #0
	ldrh	r2, [r4, #0]
	cmp	r2, #0
	beq	.Lvs_bad		@ limit 0
	movw	r12, #4095
	cmp	r2, r12
	bhi	.Lvs_bad
	movs	r1, #1
	ldrh	r2, [r4, #2]
	cmp	r2, #0
	bne	.Lvs_bad		@ pad not 0
.Lvs_ok:
	movs	r0, #0
	pop	{r4, r5, r6, r7, r8, pc}
.Lvs_bad:
	movs	r0, #1
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ ocal_validate - r0 = staged body, r1 = its length (8..0x9C0, multiple of 4). The value rules for a
@   write: the sections cover the body exactly, ids strictly ascending, each length a multiple
@   of 4, a known id with exactly its length, then the value rules of every known section.
@   Returns r0 = 0 when it passes; else r0 = 1, r1 = section id (0xFF: a header that crosses
@   the end), r2 = entry index (0xFFFF for a structure fault, else as ocal_validate_section).
@   Changes r3, r12, s0..s4.
@ ----------------------------------------------------------------------------
	.global	ocal_validate
	.thumb_func
	.type	ocal_validate, %function
ocal_validate:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r4, r0			@ r4 = body
	mov	r5, r1			@ r5 = length
	movs	r6, #0			@ r6 = o
	mvn	r7, #0			@ r7 = previous id
.Lva_next:
	cmp	r6, r5
	bhs	.Lva_ok			@ every byte covered
	movs	r1, #0xFF
	adds	r0, r6, #4
	cmp	r0, r5
	bhi	.Lva_struct		@ a header that crosses the end
	ldrh	r1, [r4, r6]		@ r1 = id
	add	r2, r4, r6
	ldrh	r8, [r2, #2]		@ r8 = s
	tst	r8, #3
	bne	.Lva_struct
	add	r0, r0, r8		@ o + 4 + s
	cmp	r0, r5
	bhi	.Lva_struct
	cmp	r1, r7
	ble	.Lva_struct		@ not strictly ascending
	mov	r7, r1
	cmp	r1, #SID_LAST
	bhi	.Lva_skip		@ unknown id: kept as it is
	ldr	r3, =ocal_lens
	ldrh	r3, [r3, r1, lsl #1]
	cmp	r8, r3
	bne	.Lva_struct
	mov	r0, r1
	add	r1, r4, r6
	adds	r1, r1, #4
	bl	ocal_validate_section
	cmp	r0, #0
	bne	.Lva_value
.Lva_skip:
	add	r6, r6, r8
	adds	r6, r6, #4
	b	.Lva_next
.Lva_value:
	mov	r2, r1			@ the entry index
	and	r1, r7, #0xFF		@ the section id
	b	.Lva_bad
.Lva_struct:
	and	r1, r1, #0xFF
	movw	r2, #0xFFFF
.Lva_bad:
	movs	r0, #1
	pop	{r4, r5, r6, r7, r8, pc}
.Lva_ok:
	movs	r0, #0
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ ocal_find - r0 = a body that passed ocal_validate, r1 = its length, r2 = id -> r0 = the
@   section body of that id, or 0. Changes r1..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_find, %function
ocal_find:
	add	r1, r1, r0		@ r1 = end
.Lfd_next:
	adds	r3, r0, #4
	cmp	r3, r1
	bhi	.Lfd_none
	ldrh	r12, [r0, #0]
	cmp	r12, r2
	beq	.Lfd_hit
	ldrh	r12, [r0, #2]
	add	r0, r3, r12		@ the next header
	b	.Lfd_next
.Lfd_hit:
	mov	r0, r3
	bx	lr
.Lfd_none:
	movs	r0, #0
	bx	lr

	.ltorg

@ ============================================================================
@ Short / open CRC and OF_RETAKE
@ ============================================================================

@ ----------------------------------------------------------------------------
@ ocal_shopen_crc - r0 = CRC-32 of the user table's short (type 0) and open (type 11) entries:
@   for each point p = 3 fi + li (0..14, entry at 0x20000B20 + 0x30 p, which is the
@   0x2000057C + 0x5A4 + 0x90 fi + 0x30 li) the four words magnitude t0,
@   magnitude t11, phase t0, phase t11 (+0, +0x2C, +0x2D0, +0x2FC), 60 words in that order.
@   Reads RAM only. Changes r1..r3, r12.
@ ----------------------------------------------------------------------------
	.global	ocal_shopen_crc
	.thumb_func
	.type	ocal_shopen_crc, %function
ocal_shopen_crc:
	push	{r4, r5, r6, lr}
	mvn	r6, #0			@ r6 = CRC register
	ldr	r4, =V_USER_TAB
	movs	r5, #15
.Lso_pt:
	mov	r0, r6
	mov	r1, r4
	movs	r2, #4
	bl	own_crc32_update
	add	r1, r4, #UT_OPEN
	movs	r2, #4
	bl	own_crc32_update
	add	r1, r4, #UT_PHASE
	movs	r2, #4
	bl	own_crc32_update
	add	r1, r4, #UT_PHASE + UT_OPEN
	movs	r2, #4
	bl	own_crc32_update
	mov	r6, r0
	adds	r4, r4, #0x30
	subs	r5, r5, #1
	bne	.Lso_pt
	mvns	r0, r6
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ ocal_retake - r0 = 1 when OF_RETAKE holds: the active record has a GAIN section in use and
@   its stored short / open CRC (+0x1C) equals ocal_shopen_crc now; else 0. Changes r1..r3,
@   r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_retake, %function
ocal_retake:
	push	{r4, lr}
	ldr	r4, =OWN_OCAL
	ldr	r0, [r4, #OCS_GAIN]
	cmp	r0, #0
	beq	.Lrt_no
	ldr	r0, [r4, #OCS_ACT]
	cmp	r0, #1
	bhi	.Lrt_no
	bl	ocal_shopen_crc
	ldr	r1, [r4, #OCS_ACT]
	ldr	r2, =OCAL_BASE
	add	r2, r2, r1, lsl #13
	ldr	r2, [r2, #RH_SOCRC]
	cmp	r0, r2
	bne	.Lrt_no
	movs	r0, #1
	pop	{r4, pc}
.Lrt_no:
	movs	r0, #0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ ocal_flags - r0 = the OCAL_INFO flags: the load flags plus OF_RETAKE (ocal_retake), OF_LOCK,
@   OF_XFER and OF_TRACE (trace not idle). Changes r1..r3, r12.
@ ----------------------------------------------------------------------------
	.global	ocal_flags
	.thumb_func
	.type	ocal_flags, %function
ocal_flags:
	push	{r4, lr}
	ldr	r4, =OWN_OCAL
	bl	ocal_retake
	ldr	r1, [r4, #OCS_FLAGS]
	cmp	r0, #0
	it	ne
	orrne	r1, r1, #OF_RETAKE
	ldr	r0, [r4, #OCS_LOCK]
	cmp	r0, #0
	it	ne
	orrne	r1, r1, #OF_LOCK
	ldr	r0, [r4, #OCS_XON]
	cmp	r0, #0
	it	ne
	orrne	r1, r1, #OF_XFER
	ldr	r0, [r4, #OCS_TST]
	cmp	r0, #0
	it	ne
	orrne	r1, r1, #OF_TRACE
	mov	r0, r1
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ ocal_meas_flags - r0 = MEASURE byte 65: bit 0 the gain was applied at the last
@   publish, bit 1 GAIN present for its frequency but not applied at its cell, bit 2 lock
@   active, bit 3 OF_RETAKE. Changes r1..r3, r12.
@ ----------------------------------------------------------------------------
	.global	ocal_meas_flags
	.thumb_func
	.type	ocal_meas_flags, %function
ocal_meas_flags:
	push	{r4, lr}
	ldr	r4, =OWN_OCAL
	bl	ocal_retake
	lsls	r0, r0, #3		@ bit 3
	ldr	r1, [r4, #OCS_GFL]
	and	r1, r1, #3
	orrs	r0, r0, r1
	ldr	r1, [r4, #OCS_LOCK]
	cmp	r1, #0
	it	ne
	orrne	r0, r0, #4
	pop	{r4, pc}

	.ltorg

@ ============================================================================
@ Values for meas.s and cmd.s
@ ============================================================================

@ ----------------------------------------------------------------------------
@ ocal_freq_index - r0 = the index fi 0..5 of the frequency word 0x20001144, 0xFF when it is
@   none of the six. Changes r1, r2, r12 (keeps r3).
@ ----------------------------------------------------------------------------
	.global	ocal_freq_index
	.thumb_func
	.type	ocal_freq_index, %function
ocal_freq_index:
	ldr	r1, =V_FREQ
	ldr	r1, [r1]
	ldr	r2, =ocal_freqs
	movs	r0, #0
.Lfi_next:
	ldr	r12, [r2, r0, lsl #2]
	cmp	r12, r1
	beq	.Lfi_out
	adds	r0, r0, #1
	cmp	r0, #NFREQ
	blo	.Lfi_next
	movs	r0, #0xFF
.Lfi_out:
	bx	lr

@ ----------------------------------------------------------------------------
@ ocal_settle - r0 = change kind 0..6 (0 restart, 1 frequency, 2 level, 3 bias, 4 speed,
@   5 screen, 6 range or gain code) -> r0 = its settle time in ms: SETTLE[kind][fi] of the
@   frequency set now; the defaults 26 (kinds 0..4) / 5 (kinds 5, 6) when the frequency is
@   none of the six (F8). Values are 1..500 (2.4). Changes r1, r2, r12 (keeps r3).
@ ----------------------------------------------------------------------------
	.global	ocal_settle
	.thumb_func
	.type	ocal_settle, %function
ocal_settle:
	push	{r4, lr}
	mov	r4, r0			@ r4 = kind
	bl	ocal_freq_index
	cmp	r0, #NFREQ
	bhs	.Lse_def
	movs	r1, #NFREQ
	mla	r0, r4, r1, r0		@ 6 kind + fi
	ldr	r1, =OWN_OCAL
	ldr	r1, [r1, #OCS_SETTLE]
	ldrh	r0, [r1, r0, lsl #1]
	pop	{r4, pc}
.Lse_def:
	movs	r0, #26
	cmp	r4, #5
	it	hs
	movhs	r0, #5
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ ocal_clip - S4.5: r0 = bit 0 when ADC1 (V) is saturated, bit 1 ADC2 (I): max
@   >= CLIP[channel][code].hi or min <= .lo, with code c5 (0x200011C5) for V and c6
@   (0x200011C6) for I and the extremes of the last peak scans (0x200011CA / CC, 0x200011D2 /
@   D4). A code above 7 takes 0 / 4095. With the default table this is the stage-1 test. Reads
@   RAM only. Changes r1..r3, r12.
@ ----------------------------------------------------------------------------
	.global	ocal_clip
	.thumb_func
	.type	ocal_clip, %function
ocal_clip:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_OCAL
	ldr	r4, [r4, #OCS_CLIP]	@ r4 = table [channel][code] {lo, hi}
	ldr	r5, =V_C5B
	movs	r6, #0			@ r6 = result
	ldrb	r0, [r5, #0]		@ c5
	ldrh	r1, [r5, #V_MAX1 - V_C5B]	@ 0x200011CA ADC1 max
	ldrh	r2, [r5, #V_MAX1 + 2 - V_C5B]	@ 0x200011CC ADC1 min
	ldr	r3, =4095 << 16		@ lo 0, hi 4095
	cmp	r0, #8
	it	lo
	ldrlo	r3, [r4, r0, lsl #2]
	uxth	r0, r3			@ lo
	lsrs	r3, r3, #16		@ hi
	cmp	r1, r3
	it	hs
	orrhs	r6, r6, #1
	cmp	r2, r0
	it	ls
	orrls	r6, r6, #1
	ldrb	r0, [r5, #V_C6B - V_C5B]	@ c6
	ldrh	r1, [r5, #V_MAX1 + 8 - V_C5B]	@ 0x200011D2 ADC2 max
	ldrh	r2, [r5, #V_MAX1 + 10 - V_C5B]	@ 0x200011D4 ADC2 min
	ldr	r3, =4095 << 16
	cmp	r0, #8
	itt	lo
	addlo	r0, r0, #8		@ channel 1 entries follow the 8 of channel 0
	ldrlo	r3, [r4, r0, lsl #2]
	uxth	r0, r3
	lsrs	r3, r3, #16
	cmp	r1, r3
	it	hs
	orrhs	r6, r6, #2
	cmp	r2, r0
	it	ls
	orrls	r6, r6, #2
	mov	r0, r6
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ ocal_bias_limit - r0 = the S4.4 DC-midpoint limit in counts (BIAS section, default 4).
@   Changes r1.
@ ----------------------------------------------------------------------------
	.global	ocal_bias_limit
	.thumb_func
	.type	ocal_bias_limit, %function
ocal_bias_limit:
	ldr	r1, =OWN_OCAL
	ldr	r1, [r1, #OCS_BIAS]
	ldrh	r0, [r1]
	bx	lr

@ ----------------------------------------------------------------------------
@ ocal_locked - r0 = the lock word (c5 | c6 << 8 | c8 << 16 | 1 << 24), 0 when not locked.
@ ocal_gain_on - r0 = 1 when the last publish applied the gain (MEASURE flags bit 0), else 0.
@ Both change r1 only.
@ ----------------------------------------------------------------------------
	.global	ocal_locked
	.thumb_func
	.type	ocal_locked, %function
ocal_locked:
	ldr	r1, =OWN_OCAL
	ldr	r0, [r1, #OCS_LOCK]
	bx	lr

	.global	ocal_gain_on
	.thumb_func
	.type	ocal_gain_on, %function
ocal_gain_on:
	ldr	r1, =OWN_OCAL
	ldr	r0, [r1, #OCS_GFL]
	and	r0, r0, #1
	bx	lr

@ ----------------------------------------------------------------------------
@ ocal_gain - S4.3 at meas_publish, after the quotient, on the path that publishes
@   (not under hold, not during the S4.4 wait). First the monitor snapshot of section 5 from
@   the raw record of this window (window number, codes, A_V, A_I, |zeta| = |nu| = 1, the
@   frequency index, OCS_MOK = 1). Then, when the GAIN pointer is set, fi is one of the six,
@   GAIN holds some cell of fi with all four bits (OCS_GFREQ) and the cell (c8, c6, c5) of the
@   codes 0x200011C8 / C6 / C5 has its zeta magnitude and phase bits and its nu magnitude and
@   phase bits: s0 / s1 = zeta nu (complex product), the snapshot's |zeta| / |nu| set, flags
@   bit 0 (applied), r0 = 1. GAIN present for fi but not this cell: flags bit 1, r0 = 0.
@   Otherwise flags 0, r0 = 0. Changes r1..r3, r12, s0..s3, s8..s11; keeps s4..s7 (meas.s
@   holds the quotient there).
@ ----------------------------------------------------------------------------
	.global	ocal_gain
	.thumb_func
	.type	ocal_gain, %function
ocal_gain:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_OCAL
	ldr	r0, [r4, #OCS_RAW + RW_WIN]
	str	r0, [r4, #OCS_MSEQ]
	ldr	r0, [r4, #OCS_RAW + RW_C5]	@ c5, c6, c8, lock bytes
	bic	r0, r0, #0xFF000000
	str	r0, [r4, #OCS_MCODES]
	ldr	r0, [r4, #OCS_RAW + RW_AV]
	str	r0, [r4, #OCS_MAV]
	ldr	r0, [r4, #OCS_RAW + RW_AI]
	str	r0, [r4, #OCS_MAI]
	ldr	r0, =F_ONE
	str	r0, [r4, #OCS_MZN]
	str	r0, [r4, #OCS_MNU]
	movs	r0, #1
	str	r0, [r4, #OCS_MOK]
	bl	ocal_freq_index
	str	r0, [r4, #OCS_MFI]
	movs	r5, #0			@ r5 = flags bits 0 / 1
	cmp	r0, #NFREQ
	bhs	.Lgn_out		@ F8: no gain outside the list
	ldr	r1, [r4, #OCS_GAIN]
	cmp	r1, #0
	beq	.Lgn_out
	ldr	r2, [r4, #OCS_GFREQ]
	lsrs	r2, r2, r0
	tst	r2, #1
	beq	.Lgn_out		@ no calibrated cell at fi
	movw	r2, #GE_SIZE
	mla	r1, r0, r2, r1		@ r1 = the entry of fi
	movs	r5, #2			@ present, not (yet) applied
	ldr	r3, [r4, #OCS_RAW + RW_C5]
	uxtb	r0, r3			@ r0 = c5
	ubfx	r2, r3, #8, #8		@ r2 = c6
	ubfx	r3, r3, #16, #8		@ r3 = c8
	cmp	r0, #8
	bhs	.Lgn_out
	cmp	r2, #8
	bhs	.Lgn_out
	cmp	r3, #4
	bhs	.Lgn_out
	add	r2, r2, r3, lsl #3	@ r2 = 8 c8 + c6
	ldr	r3, [r1, #GE_ZM]
	ldr	r12, [r1, #GE_ZP]
	and	r3, r3, r12
	lsrs	r3, r3, r2
	tst	r3, #1
	beq	.Lgn_out		@ zeta not identified in both parts
	ldrb	r3, [r1, #GE_NM]
	ldrb	r12, [r1, #GE_NP]
	and	r3, r3, r12
	lsrs	r3, r3, r0
	tst	r3, #1
	beq	.Lgn_out		@ nu not identified in both parts
	add	r2, r1, r2, lsl #3
	vldr	s0, [r2, #GE_ZETA]	@ zeta re
	vldr	s1, [r2, #GE_ZETA + 4]	@ zeta im
	add	r0, r1, r0, lsl #3
	vldr	s2, [r0, #GE_NU]	@ nu re
	vldr	s3, [r0, #GE_NU + 4]	@ nu im
	vmul.f32	s8, s0, s0
	vmla.f32	s8, s1, s1
	vsqrt.f32	s8, s8
	vstr	s8, [r4, #OCS_MZN]	@ |zeta|
	vmul.f32	s9, s2, s2
	vmla.f32	s9, s3, s3
	vsqrt.f32	s9, s9
	vstr	s9, [r4, #OCS_MNU]	@ |nu|
	vmul.f32	s10, s0, s2
	vmls.f32	s10, s1, s3	@ Re zeta nu
	vmul.f32	s11, s0, s3
	vmla.f32	s11, s1, s2	@ Im zeta nu
	vmov.f32	s0, s10
	vmov.f32	s1, s11
	movs	r5, #1			@ applied
.Lgn_out:
	str	r5, [r4, #OCS_GFL]
	and	r0, r5, #1
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ ocal_kv - r0 = fi -> r0 = 1 and s0 = kV[fi] when the MONITOR section calibrates fi, else
@   r0 = 0 (section 5). Changes r1, r2.
@ ocal_mon_get - the monitor snapshot of the last published window for the MONITOR handler of
@   cmd.s: r0 = codes c5 | c6 << 8 | c8 << 16, r1 = fi (0xFF none), r2 = window number,
@   r3 = bit 0 the gain was applied, bit 1 a window was published since the start; s0 = A_V,
@   s1 = A_I, s2 = |nu|, s3 = |zeta| (1 where the gain was not applied). Changes r12.
@ ----------------------------------------------------------------------------
	.global	ocal_kv
	.thumb_func
	.type	ocal_kv, %function
ocal_kv:
	cmp	r0, #NFREQ
	bhs	.Lkv_no
	ldr	r1, =OWN_OCAL
	ldr	r1, [r1, #OCS_MON]
	cmp	r1, #0
	beq	.Lkv_no
	ldr	r2, [r1]
	lsrs	r2, r2, r0
	tst	r2, #1
	beq	.Lkv_no
	add	r1, r1, r0, lsl #2
	vldr	s0, [r1, #4]
	movs	r0, #1
	bx	lr
.Lkv_no:
	movs	r0, #0
	bx	lr

	.global	ocal_mon_get
	.thumb_func
	.type	ocal_mon_get, %function
ocal_mon_get:
	ldr	r12, =OWN_OCAL
	vldr	s0, [r12, #OCS_MAV]
	vldr	s1, [r12, #OCS_MAI]
	vldr	s2, [r12, #OCS_MNU]
	vldr	s3, [r12, #OCS_MZN]
	ldr	r3, [r12, #OCS_GFL]
	and	r3, r3, #1
	ldr	r0, [r12, #OCS_MOK]
	cmp	r0, #0
	it	ne
	orrne	r3, r3, #2
	ldr	r0, [r12, #OCS_MCODES]
	ldr	r1, [r12, #OCS_MFI]
	ldr	r2, [r12, #OCS_MSEQ]
	bx	lr

	.ltorg

@ ============================================================================
@ Raw record, settle trace, notes from meas.s
@ ============================================================================

@ ----------------------------------------------------------------------------
@ ocal_raw - at every window close (meas_publish entry, before the hold test): the OCAL_RAW
@   record: window number MO_SEQ, codes, lock 0 / 1, frequency, level, bias, N, class, flags
@   (bit 0 a saturated acquisition since the previous close, bit 1 the overload set published
@   since then; both then cleared), Z_nom = K sum V' / sum I' (NaN when sum I' = 0),
@   A_V = |sum V'| / (64 N), A_I = |sum I'| / (64 N) (NaN for N = 0), the noise powers MO_SIG,
@   the ADC1 / ADC2 max, min, midpoint halfwords of the last acquisition. Changes r1..r3, r12,
@   s0..s10 (meas_publish loads its registers after the call).
@ ----------------------------------------------------------------------------
	.global	ocal_raw
	.thumb_func
	.type	ocal_raw, %function
ocal_raw:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_OCAL
	add	r5, r4, #OCS_RAW	@ r5 = record
	ldr	r6, =OWN_MEAS		@ r6 = meas.s state (read only)
	ldr	r0, [r6, #OM_SEQ]
	str	r0, [r5, #RW_WIN]
	ldr	r1, =V_C5B
	ldrb	r0, [r1, #0]
	strb	r0, [r5, #RW_C5]
	ldrb	r0, [r1, #V_C6B - V_C5B]
	strb	r0, [r5, #RW_C6]
	ldrb	r0, [r1, #V_C8B - V_C5B]
	strb	r0, [r5, #RW_C8]
	ldr	r0, [r4, #OCS_LOCK]
	cmp	r0, #0
	it	ne
	movne	r0, #1
	strb	r0, [r5, #RW_LOCK]
	ldr	r1, =V_FREQ
	ldr	r0, [r1]
	str	r0, [r5, #RW_FREQ]
	ldr	r1, =V_LEVEL
	ldr	r0, [r1]
	str	r0, [r5, #RW_LEVEL]
	ldr	r1, =V_BIAS
	ldr	r0, [r1]
	str	r0, [r5, #RW_BIAS]
	ldr	r0, [r6, #OM_N]
	strh	r0, [r5, #RW_N]
	ldr	r0, [r6, #OM_CLS]
	strb	r0, [r5, #RW_CLS]
	ldr	r0, [r4, #OCS_RFL]
	strb	r0, [r5, #RW_FL]
	movs	r0, #0
	str	r0, [r4, #OCS_RFL]
	str	r0, [r5, #RW_PAD]
	vldr	s0, [r6, #OM_SUM]	@ V'r
	vldr	s1, [r6, #OM_SUM + 4]	@ V'i
	vldr	s2, [r6, #OM_SUM + 8]	@ I'r
	vldr	s3, [r6, #OM_SUM + 12]	@ I'i
	vmul.f32	s4, s2, s2
	vmla.f32	s4, s3, s3	@ |I'|^2
	vcmp.f32	s4, #0
	vmrs	APSR_nzcv, fpscr
	bne	.Lrw_div
	ldr	r0, =F_NAN
	str	r0, [r5, #RW_ZR]
	str	r0, [r5, #RW_ZI]
	b	.Lrw_amp
.Lrw_div:
	vmul.f32	s5, s0, s2
	vmla.f32	s5, s1, s3	@ Re V' conj I'
	vmul.f32	s6, s1, s2
	vmls.f32	s6, s0, s3	@ Im V' conj I'
	vldr	s7, [r6, #OM_K]
	vdiv.f32	s5, s5, s4
	vdiv.f32	s6, s6, s4
	vmul.f32	s5, s5, s7
	vmul.f32	s6, s6, s7
	vstr	s5, [r5, #RW_ZR]
	vstr	s6, [r5, #RW_ZI]
.Lrw_amp:
	ldr	r0, [r6, #OM_N]
	cmp	r0, #0
	bne	.Lrw_n
	ldr	r0, =F_NAN
	str	r0, [r5, #RW_AV]
	str	r0, [r5, #RW_AI]
	b	.Lrw_sig
.Lrw_n:
	vmov	s8, r0
	vcvt.f32.u32	s8, s8
	ldr	r0, =F_64
	vmov	s9, r0
	vmul.f32	s8, s8, s9	@ 64 N
	vmul.f32	s9, s0, s0
	vmla.f32	s9, s1, s1
	vsqrt.f32	s9, s9		@ |sum V'|
	vsqrt.f32	s10, s4		@ |sum I'|
	vdiv.f32	s9, s9, s8
	vdiv.f32	s10, s10, s8
	vstr	s9, [r5, #RW_AV]
	vstr	s10, [r5, #RW_AI]
.Lrw_sig:
	ldr	r0, [r6, #OM_SIG]
	str	r0, [r5, #RW_SV]
	ldr	r0, [r6, #OM_SIG + 4]
	str	r0, [r5, #RW_SI]
	ldr	r1, =V_MAX1
	ldrh	r0, [r1, #0]		@ 0x200011CA
	strh	r0, [r5, #RW_MAX1]
	ldrh	r0, [r1, #2]		@ 0x200011CC
	strh	r0, [r5, #RW_MIN1]
	ldrh	r0, [r1, #6]		@ 0x200011D0
	strh	r0, [r5, #RW_MID1]
	ldrh	r0, [r1, #8]		@ 0x200011D2
	strh	r0, [r5, #RW_MAX2]
	ldrh	r0, [r1, #10]		@ 0x200011D4
	strh	r0, [r5, #RW_MIN2]
	ldrh	r0, [r1, #14]		@ 0x200011D8
	strh	r0, [r5, #RW_MID2]
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ ocal_sat_note - r0 = the saturation bits of an acquisition whose codes did not change
@   (meas_acq): any bit set marks the next raw record (flags bit 0). Changes r1.
@ ocal_ovl_note - the overload set was published (meas_acq): the next raw record's flags
@   bit 1. Changes r0, r1.
@ ocal_restart_take - r0 = 1 once after a commit or rollback loaded a record (meas_watch then
@   restarts the settle, kind 0), else 0; clears it. Changes r1.
@ ----------------------------------------------------------------------------
	.global	ocal_sat_note
	.thumb_func
	.type	ocal_sat_note, %function
ocal_sat_note:
	cmp	r0, #0
	beq	.Lsn_out
	ldr	r1, =OWN_OCAL
	ldr	r0, [r1, #OCS_RFL]
	orr	r0, r0, #1
	str	r0, [r1, #OCS_RFL]
.Lsn_out:
	bx	lr

	.global	ocal_ovl_note
	.thumb_func
	.type	ocal_ovl_note, %function
ocal_ovl_note:
	ldr	r1, =OWN_OCAL
	ldr	r0, [r1, #OCS_RFL]
	orr	r0, r0, #2
	str	r0, [r1, #OCS_RFL]
	bx	lr

	.global	ocal_restart_take
	.thumb_func
	.type	ocal_restart_take, %function
ocal_restart_take:
	push	{r2, lr}
	ldr	r1, =OWN_OCAL
	ldr	r0, [r1, #OCS_RST]
	movs	r2, #0
	str	r2, [r1, #OCS_RST]
	pop	{r2, pc}

@ ----------------------------------------------------------------------------
@ ocal_trace_change - at every meas_change (after its kind is stored in OCS_KIND): an armed
@   trace (state 1) starts recording: state 2, the change tick, the kind, 0 entries. Changes
@   r0..r3.
@ ocal_trace_on - r0 = 1 while the trace records and is not full, else 0. Changes r1.
@ ocal_trace_add - r0 = entry flags (bit 0 the settle rule discards it, bit 1 saturated, bit 2
@   the S1.6 band rule of meas.s meas_acq discards it), s0 = K of the codes now: while recording, one entry: tick, Zm = K V conj(I) / |I|^2 of
@   MO_X (NaN when |I|^2 = 0), flags, c5, c6, c8; the 32nd makes the trace full (state 3).
@   Changes r1..r3, s1..s7.
@ ----------------------------------------------------------------------------
	.global	ocal_trace_change
	.thumb_func
	.type	ocal_trace_change, %function
ocal_trace_change:
	ldr	r3, =OWN_OCAL
	ldr	r0, [r3, #OCS_TST]
	cmp	r0, #1
	bne	.Ltc_out
	movs	r0, #2
	str	r0, [r3, #OCS_TST]
	ldr	r0, =V_TICK
	ldr	r0, [r0]
	str	r0, [r3, #OCS_TTICK]
	ldrb	r0, [r3, #OCS_KIND]
	str	r0, [r3, #OCS_TKIND]
	movs	r0, #0
	str	r0, [r3, #OCS_TCNT]
.Ltc_out:
	bx	lr

	.global	ocal_trace_on
	.thumb_func
	.type	ocal_trace_on, %function
ocal_trace_on:
	ldr	r1, =OWN_OCAL
	ldr	r0, [r1, #OCS_TST]
	cmp	r0, #2
	bne	.Lto_no
	ldr	r0, [r1, #OCS_TCNT]
	cmp	r0, #TRACE_N
	bhs	.Lto_no
	movs	r0, #1
	bx	lr
.Lto_no:
	movs	r0, #0
	bx	lr

	.global	ocal_trace_add
	.thumb_func
	.type	ocal_trace_add, %function
ocal_trace_add:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_OCAL
	ldr	r1, [r4, #OCS_TST]
	cmp	r1, #2
	bne	.Lta_out
	ldr	r5, [r4, #OCS_TCNT]
	cmp	r5, #TRACE_N
	bhs	.Lta_out
	add	r6, r4, #OCS_TRACE
	add	r6, r6, r5, lsl #4	@ r6 = the entry (TE_SIZE 16)
	strb	r0, [r6, #TE_FL]
	ldr	r1, =V_TICK
	ldr	r1, [r1]
	str	r1, [r6, #TE_TICK]
	ldr	r1, =V_C5B
	ldrb	r2, [r1, #0]
	strb	r2, [r6, #TE_C5]
	ldrb	r2, [r1, #V_C6B - V_C5B]
	strb	r2, [r6, #TE_C6]
	ldrb	r2, [r1, #V_C8B - V_C5B]
	strb	r2, [r6, #TE_C8]
	ldr	r1, =OWN_MEAS
	vldr	s1, [r1, #OM_X]		@ Vr
	vldr	s2, [r1, #OM_X + 4]	@ Vi
	vldr	s3, [r1, #OM_X + 8]	@ Ir
	vldr	s4, [r1, #OM_X + 12]	@ Ii
	vmul.f32	s5, s3, s3
	vmla.f32	s5, s4, s4	@ |I|^2
	vcmp.f32	s5, #0
	vmrs	APSR_nzcv, fpscr
	beq	.Lta_nan
	vmul.f32	s6, s1, s3
	vmla.f32	s6, s2, s4	@ Re V conj I
	vmul.f32	s7, s2, s3
	vmls.f32	s7, s1, s4	@ Im V conj I
	vdiv.f32	s6, s6, s5
	vdiv.f32	s7, s7, s5
	vmul.f32	s6, s6, s0
	vmul.f32	s7, s7, s0
	vstr	s6, [r6, #TE_ZR]
	vstr	s7, [r6, #TE_ZI]
	b	.Lta_cnt
.Lta_nan:
	ldr	r1, =F_NAN
	str	r1, [r6, #TE_ZR]
	str	r1, [r6, #TE_ZI]
.Lta_cnt:
	adds	r5, r5, #1
	str	r5, [r4, #OCS_TCNT]
	cmp	r5, #TRACE_N
	itt	eq
	moveq	r1, #3
	streq	r1, [r4, #OCS_TST]	@ full
.Lta_out:
	pop	{r4, r5, r6, pc}

	.ltorg

@ ============================================================================
@ Lock release and refusals
@ ============================================================================

@ ----------------------------------------------------------------------------
@ ocal_unlock - the lock is released (ctl.s key_step at every key event that reaches the
@   meter's key handler: physical, injected by KEY or by a job step). Changes r0, r1.
@ ocal_step - once per ctl_loop pass: a lock is released when the screen is not 1 (any screen
@   change, also by SCREEN), a calibration runs (0x200050E4 != 0), the power-off path ran or
@   powered-off mode (CF_OFF_WAIT / CF_OFF), DTR is clear (also after a USB reset), or 30 s
@   passed since the last OCAL_LOCK / OCAL_RAW.
@ ----------------------------------------------------------------------------
	.global	ocal_unlock
	.thumb_func
	.type	ocal_unlock, %function
ocal_unlock:
	ldr	r1, =OWN_OCAL
	movs	r0, #0
	str	r0, [r1, #OCS_LOCK]
	bx	lr

	.global	ocal_step
	.thumb_func
	.type	ocal_step, %function
ocal_step:
	push	{r4, lr}
	ldr	r4, =OWN_OCAL
	ldr	r0, [r4, #OCS_LOCK]
	cmp	r0, #0
	beq	.Lsp_out
	ldr	r0, =V_SCREEN
	ldr	r0, [r0]
	cmp	r0, #1
	bne	.Lsp_rel
	ldr	r0, =V_CAL_RUN
	ldr	r0, [r0]
	cmp	r0, #0
	bne	.Lsp_rel
	ldr	r0, =OWN_CTL
	ldr	r0, [r0, #CT_FLAGS]
	tst	r0, #CF_OFF | CF_OFF_WAIT
	bne	.Lsp_rel
	bl	usb_dtr
	cmp	r0, #0
	beq	.Lsp_rel
	ldr	r0, [r4, #OCS_LOCKT]
	bl	since
	movw	r1, #LOCK_MS
	cmp	r0, r1
	blo	.Lsp_out
.Lsp_rel:
	movs	r0, #0
	str	r0, [r4, #OCS_LOCK]
.Lsp_out:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ ocal_cal_busy - r0 = 1 while a calibration runs: 0x200050E4 != 0, or the CALIBRATE job is
@   active (the test of ctl.s key_refused), else 0. Changes r1.
@ ocal_busy - the refusals in their order: r0 = S_NOT_NOW in powered-off mode
@   or after the power-off path ran, S_SAFETY while a calibration runs, S_BUSY while another
@   job runs or a rewrite of copy A is pending (SF_REWRITE_A), else 0. Changes r1.
@ ocal_lock_ok - the refusals of OCAL_LOCK: r0 = S_SAFETY while a calibration
@   runs, S_NOT_NOW in powered-off mode, after the power-off path ran or off screen 1, else 0.
@   Changes r1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_cal_busy, %function
ocal_cal_busy:
	ldr	r1, =V_CAL_RUN
	ldr	r0, [r1]
	cmp	r0, #0
	bne	.Lcb_yes
	ldr	r1, =OWN_CTL
	ldr	r0, [r1, #CT_J_ACTIVE]
	cmp	r0, #0
	beq	.Lcb_no
	ldr	r0, [r1, #CT_J_CMD]
	cmp	r0, #C_CALIBRATE
	beq	.Lcb_yes
.Lcb_no:
	movs	r0, #0
	bx	lr
.Lcb_yes:
	movs	r0, #1
	bx	lr

	.global	ocal_busy
	.thumb_func
	.type	ocal_busy, %function
ocal_busy:
	push	{r4, lr}
	ldr	r4, =OWN_CTL
	ldr	r0, [r4, #CT_FLAGS]
	tst	r0, #CF_OFF | CF_OFF_WAIT
	bne	.Lbz_3
	bl	ocal_cal_busy
	cmp	r0, #0
	bne	.Lbz_6
	ldr	r0, [r4, #CT_J_ACTIVE]
	cmp	r0, #0
	bne	.Lbz_4
	ldr	r0, =own_save_flags
	ldr	r0, [r0]
	tst	r0, #SF_REWRITE_A
	bne	.Lbz_4
	movs	r0, #0
	pop	{r4, pc}
.Lbz_3:
	movs	r0, #S_NOT_NOW
	pop	{r4, pc}
.Lbz_4:
	movs	r0, #S_BUSY
	pop	{r4, pc}
.Lbz_6:
	movs	r0, #S_SAFETY
	pop	{r4, pc}

	.thumb_func
	.type	ocal_lock_ok, %function
ocal_lock_ok:
	push	{r4, lr}
	bl	ocal_cal_busy
	cmp	r0, #0
	bne	.Llo_6
	ldr	r1, =OWN_CTL
	ldr	r0, [r1, #CT_FLAGS]
	tst	r0, #CF_OFF | CF_OFF_WAIT
	bne	.Llo_3
	ldr	r1, =V_SCREEN
	ldr	r0, [r1]
	cmp	r0, #1
	bne	.Llo_3
	movs	r0, #0
	pop	{r4, pc}
.Llo_3:
	movs	r0, #S_NOT_NOW
	pop	{r4, pc}
.Llo_6:
	movs	r0, #S_SAFETY
	pop	{r4, pc}

	.ltorg

@ ============================================================================
@ Write and rollback
@ ============================================================================

@ ----------------------------------------------------------------------------
@ ocal_revoke - r0 = slot base: the revoke word base + 0x38 programmed 0 (one flash_word with
@   the gate opened before and closed after, whatever the result). Returns r0 = the flash
@   result (FL_*).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_revoke, %function
ocal_revoke:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	ldr	r0, =OCAL_BASE
	bl	flash_ocal_gate		@ open
	add	r0, r4, #RH_REVOKE
	movs	r1, #0
	bl	flash_word
	mov	r5, r0
	movs	r0, #0
	bl	flash_ocal_gate		@ closed
	mov	r0, r5
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ ocal_write_rec - r0 = slot base T, r1 = staged record, r2 = its length L (gate open). Steps
@   4..7 of the write: every page of T the record spans erased (flash_erase_page feeds before and
@   after each), the words ascending from T + 0 to T + L - 4 except T + 0x38 (left 0xFFFFFFFF)
@   and T + 0x3C, own_feed after every 256 programmed words, then T + 0x3C (the commit word),
@   then the read-back: T CRC-valid, own and in force with the staged sequence, and every word
@   equal to the staged record. Returns r0 = FL_OK or the first failure (FL_VERIFY for the
@   read-back).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_write_rec, %function
ocal_write_rec:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r4, r0			@ r4 = T
	mov	r5, r1			@ r5 = staged record
	mov	r6, r2			@ r6 = L
	movs	r7, #0			@ r7 = page offset
.Lwr_erase:
	add	r0, r4, r7
	bl	flash_erase_page
	cmp	r0, #FL_OK
	bne	.Lwr_out
	add	r7, r7, #FLASH_PAGE
	cmp	r7, r6
	blo	.Lwr_erase
	movs	r7, #0			@ r7 = word offset
	movs	r8, #0			@ r8 = words since the last feed
.Lwr_word:
	cmp	r7, #RH_REVOKE
	beq	.Lwr_next		@ left erased: in force
	cmp	r7, #RH_CRC
	beq	.Lwr_next		@ programmed last
	add	r0, r4, r7
	ldr	r1, [r5, r7]
	bl	flash_word
	cmp	r0, #FL_OK
	bne	.Lwr_out
	adds	r8, r8, #1
	cmp	r8, #256
	bne	.Lwr_next
	bl	own_feed
	movs	r8, #0
.Lwr_next:
	adds	r7, r7, #4
	cmp	r7, r6
	blo	.Lwr_word
	add	r0, r4, #RH_CRC
	ldr	r1, [r5, #RH_CRC]
	bl	flash_word		@ the commit word
	cmp	r0, #FL_OK
	bne	.Lwr_out
	bl	own_feed
	mov	r0, r4
	bl	ocal_eval
	cmp	r0, #CL_ALL
	bne	.Lwr_verify
	ldr	r2, [r5, #RH_SEQ]
	cmp	r1, r2
	bne	.Lwr_verify
	movs	r7, #0
.Lwr_cmp:
	ldr	r0, [r4, r7]
	ldr	r1, [r5, r7]
	cmp	r0, r1
	bne	.Lwr_verify
	adds	r7, r7, #4
	cmp	r7, r6
	blo	.Lwr_cmp
	movs	r0, #FL_OK
	b	.Lwr_out
.Lwr_verify:
	movs	r0, #FL_VERIFY
.Lwr_out:
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ ocal_socrc_new - the short / open CRC of a new record (F20): the active record's
@   +0x1C when its GAIN section is in use and the staged body (OCS_XTOT bytes, validated) holds
@   a GAIN body byte-identical to it; else ocal_shopen_crc now. Returns r0. Changes r1..r3,
@   r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_socrc_new, %function
ocal_socrc_new:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_OCAL
	ldr	r5, [r4, #OCS_GAIN]	@ r5 = the active GAIN body or 0
	cmp	r5, #0
	beq	.Lsw_cur
	add	r0, r4, #OCS_STAGE + RH_SIZE
	ldr	r1, [r4, #OCS_XTOT]
	movs	r2, #SID_GAIN
	bl	ocal_find
	cmp	r0, #0
	beq	.Lsw_cur
	movw	r6, #GE_SIZE * NFREQ	@ 1992 bytes
.Lsw_cmp:
	ldr	r1, [r0], #4
	ldr	r2, [r5], #4
	cmp	r1, r2
	bne	.Lsw_cur		@ a new GAIN: the CRC of now
	subs	r6, r6, #4
	bne	.Lsw_cmp
	ldr	r1, [r4, #OCS_ACT]
	ldr	r0, =OCAL_BASE
	add	r0, r0, r1, lsl #13
	ldr	r0, [r0, #RH_SOCRC]	@ the GAIN is unchanged: its CRC is kept
	pop	{r4, r5, r6, pc}
.Lsw_cur:
	bl	ocal_shopen_crc
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ ocal_event - event 0x98 OCAL_CHANGED: active slot u8, sequence u32, flags u32 (ctl.s
@   ev_send, sent only while DTR is set).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_event, %function
ocal_event:
	push	{r4, lr}
	sub	sp, #16
	ldr	r4, =OWN_OCAL
	bl	ocal_flags
	str	r0, [sp, #5]
	ldr	r0, [r4, #OCS_ACT]
	strb	r0, [sp, #0]
	ldr	r0, [r4, #OCS_ASEQ]
	str	r0, [sp, #1]
	movs	r0, #E_OCAL
	mov	r1, sp
	movs	r2, #9
	bl	ev_send
	add	sp, #16
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ ocal_commit - r0 = answer data. The staged body (OCS_STAGE + 0x40, OCS_XTOT bytes) passed
@   ocal_validate and the refusals. The write: target T and sequence from flash (ocal_scan,
@   ocal_target, ocal_nextseq: 0 = status 3, nothing erased); the header staged (magic,
@   format 1, header size, length, sequence, UID, short / open CRC, reserved 0, revoke word
@   0xFFFFFFFF, CRC-32); the slots evaluated again and T compared with the active slot (equal:
@   status 5, result 1); flash_ocal_gate(OCAL_BASE); ocal_write_rec, once more on a failure;
@   flash_ocal_gate(0); ocal_load; on success the measurement restart (OCS_RST), the transfer
@   closed, event 0x98, and the active slot compared with T (differs: status 5, result 1).
@   Answer: result u8, active slot u8, sequence u32 (6 bytes) with status 0 or 5; status 3
@   without data. Returns r0 = status, r1 = data length.
@ ----------------------------------------------------------------------------
	.global	ocal_commit
	.thumb_func
	.type	ocal_commit, %function
ocal_commit:
	push	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #36			@ scan table at sp + 0
	mov	r11, r0			@ r11 = answer data
	ldr	r4, =OWN_OCAL
	add	r5, r4, #OCS_STAGE	@ r5 = staged record
	ldr	r6, [r4, #OCS_XTOT]
	adds	r6, r6, #RH_SIZE	@ r6 = L
	mov	r0, sp
	bl	ocal_scan
	mov	r0, sp
	bl	ocal_target
	mov	r7, r0			@ r7 = T
	mov	r0, sp
	mov	r1, r7
	bl	ocal_nextseq
	cmp	r0, #0
	beq	.Lcm_seq3
	mov	r8, r0			@ r8 = sequence
	ldr	r0, =REC_MAGIC
	str	r0, [r5, #0]
	ldr	r0, =RH_FMTWORD
	str	r0, [r5, #RH_FMT]
	str	r6, [r5, #RH_LEN]
	str	r8, [r5, #RH_SEQ]
	ldr	r1, =CHIP_UID
	ldr	r0, [r1, #0]
	str	r0, [r5, #RH_UID]
	ldr	r0, [r1, #4]
	str	r0, [r5, #RH_UID + 4]
	ldr	r0, [r1, #8]
	str	r0, [r5, #RH_UID + 8]
	bl	ocal_socrc_new
	str	r0, [r5, #RH_SOCRC]
	movs	r0, #0
	add	r1, r5, #RH_RES
	movs	r2, #6
.Lcm_res:
	str	r0, [r1], #4		@ 0x20..0x37 reserved, 0
	subs	r2, r2, #1
	bne	.Lcm_res
	mvn	r0, #0
	str	r0, [r5, #RH_REVOKE]	@ in force
	mvn	r0, #0
	mov	r1, r5
	movs	r2, #RH_REVOKE
	bl	own_crc32_update
	add	r1, r5, #RH_SIZE
	sub	r2, r6, #RH_SIZE
	bl	own_crc32_update
	mvns	r0, r0
	str	r0, [r5, #RH_CRC]
	mov	r0, sp			@ the second check, right before the first erase
	bl	ocal_scan
	mov	r0, sp
	bl	ocal_pick
	cmp	r0, r7
	beq	.Lcm_def
	ldr	r9, =OCAL_BASE
	add	r9, r9, r7, lsl #13	@ r9 = base of T
	ldr	r0, =OCAL_BASE
	bl	flash_ocal_gate		@ open the gate
	movs	r10, #2			@ r10 = attempts
.Lcm_try:
	mov	r0, r9
	mov	r1, r5
	mov	r2, r6
	bl	ocal_write_rec
	cmp	r0, #FL_OK
	beq	.Lcm_done
	subs	r10, r10, #1
	bne	.Lcm_try
	mov	r10, r0			@ r10 = the flash result of the second attempt
	movs	r0, #0
	bl	flash_ocal_gate		@ closed before the answer
	movs	r0, #0
	str	r0, [r4, #OCS_XON]
	bl	ocal_load
	strb	r10, [r11, #0]
	b	.Lcm_ans5
.Lcm_done:
	movs	r0, #0
	bl	flash_ocal_gate		@ closed before the load
	bl	ocal_load
	movs	r0, #1
	str	r0, [r4, #OCS_RST]	@ the measurement restarts its settle (2.3)
	movs	r0, #0
	str	r0, [r4, #OCS_XON]
	bl	ocal_event
	ldr	r0, [r4, #OCS_ACT]
	cmp	r0, r7
	bne	.Lcm_lost		@ G1: a commit that cannot take effect
	movs	r0, #FL_OK
	strb	r0, [r11, #0]
	ldr	r0, [r4, #OCS_ACT]
	strb	r0, [r11, #1]
	ldr	r0, [r4, #OCS_ASEQ]
	str	r0, [r11, #2]
	movs	r0, #S_OK
	movs	r1, #6
	b	.Lcm_ret
.Lcm_def:
	movs	r0, #0
	bl	flash_ocal_gate		@ closed (it was not opened)
.Lcm_lost:
	movs	r0, #FL_GATE
	strb	r0, [r11, #0]
.Lcm_ans5:
	ldr	r0, [r4, #OCS_ACT]
	strb	r0, [r11, #1]
	ldr	r0, [r4, #OCS_ASEQ]
	str	r0, [r11, #2]
	movs	r0, #S_STORAGE
	movs	r1, #6
	b	.Lcm_ret
.Lcm_seq3:
	movs	r0, #S_NOT_NOW
	movs	r1, #0
.Lcm_ret:
	add	sp, #36
	pop	{r4, r5, r6, r7, r8, r9, r10, r11, pc}

	.ltorg

@ ============================================================================
@ Command handlers 0x30..0x36 (cmd.s convention; MONITOR 0x37 is in cmd.s)
@ ============================================================================

@ ----------------------------------------------------------------------------
@ h_ocal_info - OCAL_INFO, 64 bytes: flags u32, active slot u8, format u8,
@   active length u16, active sequence u32, other sequence u32, active CRC u32, sections
@   present u8, gain frequencies u8, monitor frequencies u8, sections rejected u8, T_max u16,
@   pad u16, META time u32, META note 28 bytes, pad 4 (0).
@ ----------------------------------------------------------------------------
	.global	h_ocal_info
	.thumb_func
	.type	h_ocal_info, %function
h_ocal_info:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2			@ r6 = answer
	ldr	r4, =OWN_OCAL
	bl	ocal_flags
	str	r0, [r6, #0]
	ldr	r5, [r4, #OCS_ACT]
	strb	r5, [r6, #4]
	movs	r0, #0			@ format
	movs	r1, #0			@ length
	movs	r2, #0			@ CRC
	cmp	r5, #1
	bhi	.Lin_store
	ldr	r3, =OCAL_BASE
	add	r3, r3, r5, lsl #13
	ldrh	r0, [r3, #RH_FMT]
	ldr	r1, [r3, #RH_LEN]
	ldr	r2, [r3, #RH_CRC]
.Lin_store:
	strb	r0, [r6, #5]
	strh	r1, [r6, #6]
	str	r2, [r6, #16]
	ldr	r0, [r4, #OCS_ASEQ]
	str	r0, [r6, #8]
	ldr	r0, [r4, #OCS_OSEQ]
	str	r0, [r6, #12]
	ldr	r0, [r4, #OCS_PRES]
	strb	r0, [r6, #20]
	ldr	r0, [r4, #OCS_GFREQ]
	strb	r0, [r6, #21]
	ldr	r0, [r4, #OCS_MFREQ]
	strb	r0, [r6, #22]
	ldr	r0, [r4, #OCS_REJ]
	strb	r0, [r6, #23]
	ldr	r0, [r4, #OCS_TMAX]
	strh	r0, [r6, #24]
	movs	r0, #0
	strh	r0, [r6, #26]
	str	r0, [r6, #60]
	ldr	r1, [r4, #OCS_META]	@ META body: time u32, note 28 bytes
	add	r2, r6, #28
	movs	r3, #8
.Lin_meta:
	movs	r0, #0
	cmp	r1, #0
	it	ne
	ldrne	r0, [r1], #4
	str	r0, [r2], #4
	subs	r3, r3, #1
	bne	.Lin_meta
	movs	r0, #S_OK
	movs	r1, #INFO_LEN
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ h_ocal_read - OCAL_READ: slot u8 (0, 1), offset u16, length u16 (1..256), offset + length
@   <= 0x2000, exactly 5 bytes; else status 2. Answer: those bytes of the slot as in flash.
@ ----------------------------------------------------------------------------
	.global	h_ocal_read
	.thumb_func
	.type	h_ocal_read, %function
h_ocal_read:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #5
	bne	.Lrd_bad
	ldrb	r4, [r0, #0]		@ slot
	ldrh	r5, [r0, #1]		@ offset
	ldrh	r6, [r0, #3]		@ length
	cmp	r4, #1
	bhi	.Lrd_bad
	cmp	r6, #0
	beq	.Lrd_bad
	cmp	r6, #256
	bhi	.Lrd_bad
	add	r3, r5, r6
	cmp	r3, #OCAL_SLOT
	bhi	.Lrd_bad
	ldr	r1, =OCAL_BASE
	add	r1, r1, r4, lsl #13
	add	r1, r1, r5		@ r1 = first byte
	mov	r7, r6
.Lrd_copy:
	ldrb	r3, [r1], #1
	strb	r3, [r2], #1
	subs	r7, r7, #1
	bne	.Lrd_copy
	movs	r0, #S_OK
	mov	r1, r6
	pop	{r4, r5, r6, r7, r8, pc}
.Lrd_bad:
	movs	r0, #S_BAD_ARG
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ h_ocal_write - OCAL_WRITE: confirmation u16 0x4F4B, offset u16, total u16
@   (8..0x9C0, multiple of 4), CRC-32 u32 of the whole body, chunk = the bytes after byte 10
@   (1..502). A chunk at offset 0 starts a new transfer; another chunk must start at the
@   offset the previous answer named with the same total and CRC; a chunk ending beyond the
@   total: status 2 (no data), the transfer as it was. A chunk that does not complete the body:
@   answer the next offset u16. The last chunk: transfer CRC (status 7), ocal_validate (status
@   2 with section id u8 and entry index u16), ocal_busy (3 / 6 / 4), ocal_commit (0 / 5 with
@   result, slot, sequence; 3 when the sequence cannot win). A refused last chunk leaves the
@   transfer open at its offset.
@ ----------------------------------------------------------------------------
	.global	h_ocal_write
	.thumb_func
	.type	h_ocal_write, %function
h_ocal_write:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r7, r2			@ r7 = answer
	cmp	r1, #11
	blo	.Lwt_bad
	mov	r8, r0			@ r8 = payload
	sub	r6, r1, #10		@ r6 = chunk length
	cmp	r6, #CHUNK_MAX
	bhi	.Lwt_bad
	ldrh	r0, [r8, #0]
	movw	r1, #CONFIRM_OK
	cmp	r0, r1
	bne	.Lwt_bad
	ldrh	r5, [r8, #4]		@ r5 = total
	cmp	r5, #BODY_MIN
	blo	.Lwt_bad
	cmp	r5, #BODY_MAX
	bhi	.Lwt_bad
	tst	r5, #3
	bne	.Lwt_bad
	ldrh	r4, [r8, #2]		@ r4 = offset
	add	r0, r4, r6
	cmp	r0, r5
	bhi	.Lwt_bad		@ beyond the total
	ldr	r3, =OWN_OCAL
	ldr	r2, [r8, #6]		@ r2 = body CRC
	cmp	r4, #0
	beq	.Lwt_new
	ldr	r0, [r3, #OCS_XON]
	cmp	r0, #0
	beq	.Lwt_bad
	ldr	r0, [r3, #OCS_XNEXT]
	cmp	r0, r4
	bne	.Lwt_bad
	ldr	r0, [r3, #OCS_XTOT]
	cmp	r0, r5
	bne	.Lwt_bad
	ldr	r0, [r3, #OCS_XCRC]
	cmp	r0, r2
	bne	.Lwt_bad
	b	.Lwt_copy
.Lwt_new:
	movs	r0, #1
	str	r0, [r3, #OCS_XON]	@ a new transfer: the staged bytes start again
	str	r5, [r3, #OCS_XTOT]
	str	r2, [r3, #OCS_XCRC]
.Lwt_copy:
	add	r0, r3, #OCS_STAGE + RH_SIZE
	add	r0, r0, r4
	add	r1, r8, #10
	mov	r2, r6
.Lwt_byte:
	ldrb	r12, [r1], #1
	strb	r12, [r0], #1
	subs	r2, r2, #1
	bne	.Lwt_byte
	add	r0, r4, r6
	str	r0, [r3, #OCS_XNEXT]
	cmp	r0, r5
	beq	.Lwt_last
	strh	r0, [r7, #0]		@ the next expected offset
	movs	r0, #S_OK
	movs	r1, #2
	pop	{r4, r5, r6, r7, r8, pc}
.Lwt_last:
	add	r0, r3, #OCS_STAGE + RH_SIZE
	mov	r1, r5
	bl	own_crc32
	ldr	r3, =OWN_OCAL
	ldr	r1, [r3, #OCS_XCRC]
	cmp	r0, r1
	bne	.Lwt_crc
	add	r0, r3, #OCS_STAGE + RH_SIZE
	mov	r1, r5
	bl	ocal_validate
	cmp	r0, #0
	bne	.Lwt_inval
	bl	ocal_busy
	cmp	r0, #0
	bne	.Lwt_reopen
	mov	r0, r7
	bl	ocal_commit
	cmp	r0, #S_NOT_NOW
	beq	.Lwt_reopen
	pop	{r4, r5, r6, r7, r8, pc}	@ status 0 or 5, 6 bytes
.Lwt_reopen:
	ldr	r3, =OWN_OCAL
	str	r4, [r3, #OCS_XNEXT]	@ open at the offset of this chunk
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}
.Lwt_inval:
	strb	r1, [r7, #0]		@ section id
	strh	r2, [r7, #1]		@ entry index
	ldr	r3, =OWN_OCAL
	str	r4, [r3, #OCS_XNEXT]
	movs	r0, #S_BAD_ARG
	movs	r1, #3
	pop	{r4, r5, r6, r7, r8, pc}
.Lwt_crc:
	str	r4, [r3, #OCS_XNEXT]
	movs	r0, #S_XFER_CRC
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}
.Lwt_bad:
	movs	r0, #S_BAD_ARG
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ h_ocal_rollback - OCAL_ROLLBACK: confirmation u16 0x4F4B, mode u8, exactly 3
@   bytes (else status 2); the refusals of ocal_busy. Mode 0: the active record's revoke word
@   (status 3 when none is active). Mode 1: every own, in-force, format-1 record, the older
@   first (slot 1 first on equal sequences; status 3 when none qualifies). Then ocal_load, the
@   measurement restart, event 0x98. Answer: active slot u8, sequence u32, flags u32 with
@   status 0, or 5 when a revoke failed (the remaining one is not tried).
@ ----------------------------------------------------------------------------
	.global	h_ocal_rollback
	.thumb_func
	.type	h_ocal_rollback, %function
h_ocal_rollback:
	push	{r4, r5, r6, r7, r8, lr}
	sub	sp, #32			@ scan table
	mov	r7, r2			@ r7 = answer
	cmp	r1, #3
	bne	.Lrb_bad
	ldrh	r1, [r0, #0]
	movw	r2, #CONFIRM_OK
	cmp	r1, r2
	bne	.Lrb_bad
	ldrb	r4, [r0, #2]		@ r4 = mode
	cmp	r4, #1
	bhi	.Lrb_bad
	bl	ocal_busy
	cmp	r0, #0
	bne	.Lrb_status
	mov	r0, sp
	bl	ocal_scan
	ldr	r6, =OCAL_BASE		@ r6 = slot 0 base
	cmp	r4, #0
	bne	.Lrb_m1
	mov	r0, sp
	bl	ocal_pick
	cmp	r0, #0xFF
	beq	.Lrb_none
	add	r0, r6, r0, lsl #13
	bl	ocal_revoke
	mov	r5, r0			@ r5 = result
	b	.Lrb_done
.Lrb_m1:
	movs	r8, #0			@ r8 = bit 0 slot 0 qualifies, bit 1 slot 1
	ldr	r0, [sp, #SC_CLS]
	ldr	r1, [sp, #SC_FMT]
	cmp	r0, #CL_ALL
	bne	.Lrb_q1
	cmp	r1, #1
	it	eq
	orreq	r8, r8, #1
.Lrb_q1:
	ldr	r0, [sp, #SC_SIZE + SC_CLS]
	ldr	r1, [sp, #SC_SIZE + SC_FMT]
	cmp	r0, #CL_ALL
	bne	.Lrb_q2
	cmp	r1, #1
	it	eq
	orreq	r8, r8, #2
.Lrb_q2:
	cmp	r8, #0
	beq	.Lrb_none
	cmp	r8, #3
	beq	.Lrb_two
	subs	r0, r8, #1		@ the one slot: 0 or 1
	add	r0, r6, r0, lsl #13
	bl	ocal_revoke
	mov	r5, r0
	b	.Lrb_done
.Lrb_two:
	movs	r8, #1			@ r8 = first slot: slot 1 unless slot 0 is older
	ldr	r0, [sp, #SC_SEQ]
	ldr	r1, [sp, #SC_SIZE + SC_SEQ]
	cmp	r0, r1
	it	lo
	movlo	r8, #0
	add	r0, r6, r8, lsl #13
	bl	ocal_revoke		@ the older record first (G2)
	mov	r5, r0
	cmp	r5, #FL_OK
	bne	.Lrb_done
	rsb	r8, r8, #1
	add	r0, r6, r8, lsl #13
	bl	ocal_revoke
	mov	r5, r0
.Lrb_done:
	bl	ocal_load
	ldr	r4, =OWN_OCAL
	movs	r0, #1
	str	r0, [r4, #OCS_RST]
	bl	ocal_event
	ldr	r0, [r4, #OCS_ACT]
	strb	r0, [r7, #0]
	ldr	r0, [r4, #OCS_ASEQ]
	str	r0, [r7, #1]
	bl	ocal_flags
	str	r0, [r7, #5]
	movs	r0, #S_OK
	cmp	r5, #FL_OK
	it	ne
	movne	r0, #S_STORAGE
	movs	r1, #9
	b	.Lrb_ret
.Lrb_none:
	movs	r0, #S_NOT_NOW
	movs	r1, #0
	b	.Lrb_ret
.Lrb_bad:
	movs	r0, #S_BAD_ARG
.Lrb_status:
	movs	r1, #0
.Lrb_ret:
	add	sp, #32
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ h_ocal_lock - OCAL_LOCK: c5 u8 (0..7), c6 u8 (0..7), c8 u8 (0..3), exactly 3
@   bytes, or 0xFF 0xFF 0xFF to release (always allowed). A code out of range or another
@   length: status 2; then ocal_lock_ok (6 while a calibration runs; 3 powered off, after the
@   power-off path or off screen 1). The lock word stored and its tick noted (meas.s applies
@   the codes at the next acquisition). Answer: the OCAL_RAW record of the last window.
@ h_ocal_raw - OCAL_RAW: the raw record, 64 bytes (the request payload is not read); while
@   locked the 30 s lock timeout starts again.
@ ----------------------------------------------------------------------------
	.global	h_ocal_lock
	.thumb_func
	.type	h_ocal_lock, %function
h_ocal_lock:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r7, r2
	cmp	r1, #3
	bne	.Llk_bad
	ldrb	r4, [r0, #0]
	ldrb	r5, [r0, #1]
	ldrb	r6, [r0, #2]
	and	r1, r4, r5
	and	r1, r1, r6
	cmp	r1, #0xFF
	beq	.Llk_rel		@ 0xFF 0xFF 0xFF
	cmp	r4, #7
	bhi	.Llk_bad
	cmp	r5, #7
	bhi	.Llk_bad
	cmp	r6, #3
	bhi	.Llk_bad
	bl	ocal_lock_ok
	cmp	r0, #0
	bne	.Llk_refused
	orr	r0, r4, r5, lsl #8
	orr	r0, r0, r6, lsl #16
	orr	r0, r0, #LOCK_ON
	ldr	r4, =OWN_OCAL
	str	r0, [r4, #OCS_LOCK]
	bl	now
	str	r0, [r4, #OCS_LOCKT]
	b	.Llk_ans
.Llk_rel:
	bl	ocal_unlock
.Llk_ans:
	mov	r0, r7
	bl	ocal_raw_copy
	movs	r0, #S_OK
	movs	r1, #RAW_SIZE
	pop	{r4, r5, r6, r7, r8, pc}
.Llk_refused:
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}
.Llk_bad:
	movs	r0, #S_BAD_ARG
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}

	.global	h_ocal_raw
	.thumb_func
	.type	h_ocal_raw, %function
h_ocal_raw:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r7, r2
	ldr	r4, =OWN_OCAL
	ldr	r0, [r4, #OCS_LOCK]
	cmp	r0, #0
	beq	.Lrr_copy
	bl	now
	str	r0, [r4, #OCS_LOCKT]	@ the lock timeout starts again
.Lrr_copy:
	mov	r0, r7
	bl	ocal_raw_copy
	movs	r0, #S_OK
	movs	r1, #RAW_SIZE
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ ocal_raw_copy - r0 = destination (any alignment): the 64 raw-record bytes. Changes r1..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ocal_raw_copy, %function
ocal_raw_copy:
	ldr	r1, =OWN_OCAL + OCS_RAW
	movs	r2, #RAW_SIZE / 4
.Lrc_word:
	ldr	r3, [r1], #4
	str	r3, [r0], #4
	subs	r2, r2, #1
	bne	.Lrc_word
	bx	lr

@ ----------------------------------------------------------------------------
@ h_ocal_trace - OCAL_TRACE: op u8 (0 disarm, 1 arm, 2 read), start u8 (read
@   only, 0..31; absent = 0). Op 0: idle; op 1: armed, 0 entries. Every op answers state u8,
@   kind u8, change tick u32, count u8, n u8 (entries from start, at most 31) and the n
@   entries of 16 bytes. Op above 2 or start above 31: status 2.
@ ----------------------------------------------------------------------------
	.global	h_ocal_trace
	.thumb_func
	.type	h_ocal_trace, %function
h_ocal_trace:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r7, r2
	cmp	r1, #1
	blo	.Ltr_bad
	ldrb	r4, [r0, #0]		@ r4 = op
	movs	r5, #0			@ r5 = start
	cmp	r1, #2
	it	hs
	ldrbhs	r5, [r0, #1]
	cmp	r4, #2
	bhi	.Ltr_bad
	cmp	r5, #TRACE_N - 1
	bhi	.Ltr_bad
	ldr	r6, =OWN_OCAL
	cmp	r4, #2
	beq	.Ltr_ans
	str	r4, [r6, #OCS_TST]	@ 0 idle or 1 armed
	movs	r0, #0
	str	r0, [r6, #OCS_TCNT]
	movs	r5, #0
.Ltr_ans:
	ldr	r0, [r6, #OCS_TST]
	strb	r0, [r7, #0]
	ldr	r0, [r6, #OCS_TKIND]
	strb	r0, [r7, #1]
	ldr	r0, [r6, #OCS_TTICK]
	str	r0, [r7, #2]
	ldr	r1, [r6, #OCS_TCNT]
	strb	r1, [r7, #6]
	subs	r1, r1, r5		@ r1 = entries from start
	it	lt
	movlt	r1, #0
	cmp	r1, #TRACE_PER
	it	hi
	movhi	r1, #TRACE_PER
	strb	r1, [r7, #7]
	mov	r8, r1			@ r8 = n
	add	r0, r7, #8
	add	r2, r6, #OCS_TRACE
	add	r2, r2, r5, lsl #4
	lsls	r3, r1, #2		@ words to copy
	cmp	r3, #0
	beq	.Ltr_done
.Ltr_copy:
	ldr	r1, [r2], #4
	str	r1, [r0], #4
	subs	r3, r3, #1
	bne	.Ltr_copy
.Ltr_done:
	movs	r0, #S_OK
	lsls	r1, r8, #4
	adds	r1, r1, #8
	pop	{r4, r5, r6, r7, r8, pc}
.Ltr_bad:
	movs	r0, #S_BAD_ARG
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg
