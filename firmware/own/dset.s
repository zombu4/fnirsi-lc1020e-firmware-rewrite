@ dset.s - the direct changes of SCREEN, LCR_SET, HOLD, SETTINGS_SET and COMPARE_SET: the value
@ requested by the host is set at once, with the follow-up work of the meter's key handler for
@ the press that lands on that value, without key presses, beeps or intermediate values.
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ Specification: DIRECT_SET_DESIGN.md revision 2 (the facts of the key path in its section 1,
@ the changes in 2.3, the refusals in 2.2, the differences from the old jobs in 2.4).
@
@ Flow (2.1): the handler of the command (own/cmd.s) checks the arguments, stores the command in
@ CT_DS_OP and its arguments in CT_DS_A .. CT_DS_D, and calls ds_request: ds_check refused it or
@ found nothing to change -> the answer at once (job_answer); else a job of one step OP_DIRECT
@ (own/ctl.s job_step). key_step (ctl.s, main-loop step 3) calls ds_run in place of 0x08009400
@ in a pass with no event in the event slot and no key down; ds_run checks again, makes the
@ change and clears CT_DS_OP; job_step then answers in the next pass. Every end of a job clears
@ CT_DS_OP (ctl.s .Lj_finish), so a change dropped by the time limit never runs later.
@
@ Arguments per command (CT_DS_OP):
@   C_SCREEN      A = screen 1..3
@   C_LCR_SET     A = setting id 0..7, B = the value word (the index, or the list's value:
@                 frequency in Hz, level / bias as float bits)
@   C_HOLD        A = 0 off, 1 on
@   C_SET_SET     A = setting id 0..5, B = value, C = address of the setting's word
@   C_COMPARE_SET A = count 100..99999, B = tolerance in tenths 0..999, C = warn type | sound
@                 << 8 | LED << 16, D = scale index 0..3
@
@ Never-brick: no access to the flash controller. Nothing here reaches a save or the flash
@ (DIRECT_SET_DESIGN.md 1.6: the call-graph closure of every vendor routine called here holds
@ neither own_save, fn_08014b94, fn_0800b4c8 nor an address 0x40022xxx); ds_run sets the guard
@ own_injected around the change anyway, so a save would be refused and the answer get status 6.
@ RAM: only the words named per routine below (and the vendor routines' own writes).
@ Calling convention of every function: AAPCS; r0..r3, r12, the flags and s0..s15 clobbered,
@ r4..r11 kept.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"
	.include "own/ctl.inc"

@ offsets in the block 0x2000057C (V_BLOCK) of the words written here (own.inc, ctl.inc)
	.equ	B_LEVEL,	V_LEVEL - V_BLOCK	@ 0xBBC level float
	.equ	B_BIAS,		V_BIAS - V_BLOCK	@ 0xBC0 bias float
	.equ	B_FREQ,		V_FREQ - V_BLOCK	@ 0xBC8 frequency
	.equ	B_FUNC,		V_FUNC - V_BLOCK	@ 0xBCC Func
	.equ	B_RANGE,	V_RANGE - V_BLOCK	@ 0xBD0 range
	.equ	B_LANGUAGE,	V_LANGUAGE - V_BLOCK	@ 0xBE0 language
	.equ	B_SCREEN,	V_SCREEN - V_BLOCK	@ 0xBEC screen
	.equ	B_CMP_TYPE,	V_CMP_TYPE - V_BLOCK	@ 0xBFC compare quantity
	.equ	B_CURSOR,	V_DISP_A8 - V_BLOCK	@ 0xC2C cursor / menu item
	.equ	B_DIALOG,	V_DIALOG - V_BLOCK	@ 0xC30 dialog open
	.equ	B_MAIN_ROW,	V_MAIN_ROW - V_BLOCK	@ 0xC68 byte: main row
	.equ	B_SECONDARY,	V_SECONDARY - V_BLOCK	@ 0xC6C secondary

	.section .text.own.dset,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ ds_request - r0 = command (C_*), r1 = answer kind (AN_*); the arguments are in CT_DS_A ..
@   CT_DS_D. Stores CT_DS_OP and runs ds_check: DS_GO -> a job of the one step OP_DIRECT
@   (time limit DS_LIMIT_MS); DS_SAME -> answer status 0 now; a refusal -> answer with that
@   status now (CT_DS_OP cleared). The answers carry the record of the kind (job_answer).
@   Returns r0 = ST_DEFER, r1 = 0 (the answer is pending or comes from the job).
@ ----------------------------------------------------------------------------
	.global	ds_request
	.thumb_func
	.type	ds_request, %function
ds_request:
	push	{r4, r5, r6, lr}	@ keep r4..r6, the return address
	ldr	r4, =OWN_CTL		@ r4 = control core RAM
	mov	r5, r0			@ r5 = command
	mov	r6, r1			@ r6 = answer kind
	str	r5, [r4, #CT_DS_OP]	@ the change is pending
	bl	ds_check		@ r0 = DS_GO, DS_SAME or a status
	cmp	r0, #DS_GO		@ a change to make?
	bne	.Lrq_now		@ no: the answer now
	bl	prog_reset		@ the program: one step OP_DIRECT
	movs	r0, #OP_DIRECT		@ op word
	movs	r1, #0			@ no keys
	movs	r2, #0			@ no address
	movs	r3, #0			@ no target
	bl	prog_add		@ appended
	mov	r0, r5			@ the command
	mov	r1, r6			@ its answer kind
	movw	r2, #DS_LIMIT_MS	@ a key held this long: status 4
	bl	job_start		@ job_step waits for ds_run, then answers
	b	.Lrq_out		@ to the common return
.Lrq_now:
	cmp	r0, #DS_SAME		@ nothing to change:
	it	eq			@ (then)
	moveq	r0, #S_OK		@ status 0
	mov	r1, r0			@ r1 = status
	movs	r0, #0			@ 0:
	str	r0, [r4, #CT_DS_OP]	@ no change pending
	mov	r0, r6			@ r0 = answer kind
	bl	job_answer		@ the record with the status, pending now
.Lrq_out:
	movs	r0, #ST_DEFER		@ the handler makes no answer of its own
	movs	r1, #0			@ no data of its own
	pop	{r4, r5, r6, pc}	@ back to the handler

@ ----------------------------------------------------------------------------
@ ds_run - from key_step (ctl.s step 3) in a pass with the event slot empty and no key down:
@   the guard on (own_injected = 1, own_save_count noted), ds_check again (a physical key in
@   between may have changed the screen or a value): DS_GO -> word 0x2000511C = 0 (as 0x08009400
@   does for every event, app_01.s 89) and the change (ds_apply); a refusal -> its status in
@   CT_J_STATUS. Then the guard off; a changed own_save_count (a save was reached: own_save
@   refuses while own_injected is set) sets CT_J_GUARD (status 6). CT_DS_OP = 0: job_step
@   answers. Stack: 8 bytes plus the routine (at most 16) plus the vendor routines; the screen
@   builders are tail calls of ds_screen.
@ ----------------------------------------------------------------------------
	.global	ds_run
	.thumb_func
	.type	ds_run, %function
ds_run:
	push	{r4, lr}		@ keep r4, the return address
	ldr	r4, =OWN_CTL		@ r4 = control core RAM
	ldr	r0, =own_save_count	@ saves so far:
	ldr	r0, [r0]		@ the count
	str	r0, [r4, #CT_SAVES_SEEN]	@ noted
	movs	r0, #1			@ 1:
	str	r0, [r4, #CTO_INJECTED]	@ guard on: own_save and own_restore_guard refuse
	bl	ds_check		@ r0 = DS_GO, DS_SAME or a status
	cmp	r0, #DS_GO		@ a change to make?
	beq	.Lrn_go			@ yes
	cmp	r0, #DS_SAME		@ nothing to change: status stays 0
	beq	.Lrn_end		@ to the guard off
	str	r0, [r4, #CT_J_STATUS]	@ refused now: the answer's status
	b	.Lrn_end		@ to the guard off
.Lrn_go:
	ldr	r0, =V_EVENT_511C	@ word 0x2000511C = 0, as 0x08009400 for every event
	movs	r1, #0			@ 0
	str	r1, [r0]		@ stored
	bl	ds_apply		@ the change
.Lrn_end:
	movs	r0, #0			@ 0:
	str	r0, [r4, #CTO_INJECTED]	@ guard off
	ldr	r0, =own_save_count	@ a save reached during the change?
	ldr	r0, [r0]		@ the count now
	ldr	r1, [r4, #CT_SAVES_SEEN]	@ the count before
	cmp	r0, r1			@ the same?
	beq	.Lrn_clear		@ yes: no save
	movs	r0, #1			@ a save (refused by the guard):
	str	r0, [r4, #CT_J_GUARD]	@ status 6
.Lrn_clear:
	movs	r0, #0			@ 0:
	str	r0, [r4, #CT_DS_OP]	@ done: job_step answers in the next pass
	pop	{r4, pc}		@ back to key_step

@ ----------------------------------------------------------------------------
@ ds_check - the pending change (CT_DS_OP, CT_DS_A ..) against the state now. Returns r0 =
@   DS_GO (a change to make), DS_SAME (the value is set already), or the status of a refusal:
@   - S_NOT_NOW: powered-off mode (CF_OFF) or the meter's power-off path ran (CF_OFF_WAIT: a
@     change after its save would be lost); the screen word 0x20001168 not 1..3 (screen 0: the
@     chooser's root object is another one, ui_42.s fn_0800d8f0); LCR_SET and HOLD in screen 3;
@     LCR_SET level 0.6 V while the bias bits are 0x3DCCCCCD or more (signed, the key path's own
@     compare ui_42.s .L0800d9f6: 0.3 V -> 0.1 V there, 0.6 V is never reached); LCR_SET Func
@     0 or 4 in screen 2 (the key path forces Func 1 there, app_01.s 565-575);
@   - S_SAFETY: a calibration runs (0x200050E4 != 0, as key_refused); SCREEN from screen 3 with
@     a dialog open (0x200011AC != 0) on menu item 5 or 6 (0x200011A8): the result of the old job
@     there (key_refused refused its long key 8, ctl.s .Lkr_ok_key).
@   The equality check of a command comes before its refusals, as the old job's first step did.
@   Uses r0..r3, r12, s0..s15 (cs_diff).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ds_check, %function
ds_check:
	push	{r4, r5, r6, lr}	@ keep r4..r6, the return address
	ldr	r4, =OWN_CTL		@ r4 = control core RAM
	ldr	r0, [r4, #CT_FLAGS]	@ the flags:
	tst	r0, #CF_OFF | CF_OFF_WAIT	@ powered off, or the power-off path ran
	bne	.Lck_notnow		@ refused: 3
	ldr	r0, =V_CAL_RUN		@ a calibration runs?
	ldr	r0, [r0]		@ its word
	cmp	r0, #0			@ running:
	bne	.Lck_safety		@ refused: 6
	ldr	r5, =V_SCREEN		@ the screen word
	ldr	r5, [r5]		@ r5 = screen
	subs	r0, r5, #1		@ screens 1..3 -> 0..2
	cmp	r0, #2			@ any other (0, the chooser): refused
	bhi	.Lck_notnow		@ 3
	ldr	r6, [r4, #CT_DS_A]	@ r6 = first argument
	ldr	r0, [r4, #CT_DS_OP]	@ r0 = command
	cmp	r0, #C_SCREEN		@ SCREEN?
	beq	.Lck_screen
	cmp	r0, #C_SET_SET		@ SETTINGS_SET?
	beq	.Lck_set
	cmp	r0, #C_COMPARE_SET	@ COMPARE_SET?
	beq	.Lck_compare
	cmp	r5, #3			@ LCR_SET and HOLD: screens 1 and 2 only
	beq	.Lck_notnow		@ screen 3: 3
	cmp	r0, #C_HOLD		@ HOLD?
	beq	.Lck_hold
@ LCR_SET: r6 = id, CT_DS_B = the value word
	ldr	r1, =lcr_ds		@ {address, routine} per id
	ldr	r1, [r1, r6, lsl #3]	@ address of the setting's word
	ldr	r1, [r1]		@ its value now
	ldr	r2, [r4, #CT_DS_B]	@ the requested value
	cmp	r1, r2			@ set already
	beq	.Lck_same
	cmp	r6, #0			@ Func?
	bne	.Lck_level		@ no
	cmp	r5, #2			@ Func in screen 2:
	bne	.Lck_go			@ (screen 1: any value)
	cmp	r2, #0			@ AUTO not reached there
	beq	.Lck_notnow		@ 3
	cmp	r2, #4			@ Z not reached there
	beq	.Lck_notnow		@ 3
	b	.Lck_go			@ R, C, L
.Lck_level:
	cmp	r6, #3			@ level?
	bne	.Lck_go			@ no: any value of the list
	ldr	r0, =0x3F19999A		@ 0.6 V requested?
	cmp	r2, r0
	bne	.Lck_go			@ no
	ldr	r0, =V_BIAS		@ the bias bits
	ldr	r0, [r0]		@ now
	ldr	r1, =0x3DCCCCCD		@ against 0.1 V, signed as the key path compares
	cmp	r0, r1
	bge	.Lck_notnow		@ 0.1 V or more: 0.6 V not reached
	b	.Lck_go			@ below: reached
.Lck_hold:
	ldr	r0, =V_HOLD		@ hold now
	ldr	r0, [r0]		@ its word
	cmp	r0, r6			@ set already
	beq	.Lck_same
	b	.Lck_go			@ else a change
.Lck_screen:
	cmp	r5, r6			@ on that screen already
	beq	.Lck_same
	cmp	r5, #3			@ from screen 1 / 2: always
	bne	.Lck_go
	ldr	r0, =V_DIALOG		@ screen 3: a dialog open?
	ldr	r0, [r0]		@ its word
	cmp	r0, #0			@ none:
	beq	.Lck_go			@ a change
	ldr	r0, =V_DISP_A8		@ its menu item
	ldr	r0, [r0]		@ the word
	cmp	r0, #5			@ calibration dialog: refused
	beq	.Lck_safety		@ 6
	cmp	r0, #6			@ restore-defaults dialog: refused
	beq	.Lck_safety		@ 6
	b	.Lck_go			@ the sorting dialog: closed by ds_screen
.Lck_set:
	ldr	r1, [r4, #CT_DS_C]	@ the setting's word
	ldr	r1, [r1]		@ its value now
	ldr	r2, [r4, #CT_DS_B]	@ the requested value
	cmp	r1, r2			@ set already
	beq	.Lck_same
	b	.Lck_go			@ else a change
.Lck_compare:
	bl	cs_diff			@ r0 = the parts that differ
	cmp	r0, #0			@ none
	beq	.Lck_same
.Lck_go:
	movs	r0, #DS_GO		@ a change to make
	pop	{r4, r5, r6, pc}	@ back
.Lck_same:
	movs	r0, #DS_SAME		@ nothing to change
	pop	{r4, r5, r6, pc}	@ back
.Lck_notnow:
	movs	r0, #S_NOT_NOW		@ refused: 3
	pop	{r4, r5, r6, pc}	@ back
.Lck_safety:
	movs	r0, #S_SAFETY		@ refused: 6
	pop	{r4, r5, r6, pc}	@ back

	.ltorg

@ ----------------------------------------------------------------------------
@ cs_diff - the parts of the pending COMPARE_SET that differ from the state now. Returns r0:
@   bit 0 the nominal (the scale word 0x2000119C is not the requested index, or the count of the
@   nominal 0x20001184 at the scale word now, nom_count, is not the requested count), bit 1 the
@   tolerance (tenths of 0x20001188 is not the requested number), bit 2 a warn word
@   (0x2000116C / 0x20001170 / 0x20001174 not the requested 0 / 1). Uses r0..r3, r12, s0..s15.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cs_diff, %function
cs_diff:
	push	{r4, r5, r6, lr}	@ keep r4..r6, the return address
	ldr	r4, =OWN_CTL		@ r4 = control core RAM
	movs	r5, #0			@ r5 = parts that differ
	ldr	r1, =V_SCALE		@ the scale word now
	ldr	r1, [r1]		@ r1 = its value
	ldr	r2, [r4, #CT_DS_D]	@ the requested scale index
	cmp	r1, r2			@ another scale:
	bne	.Lcd_nominal		@ the nominal changes
	ldr	r0, =V_NOMINAL		@ the nominal now
	ldr	r0, [r0]		@ its bits
	bl	nom_count		@ r0 = its count at the scale now (r1)
	ldr	r1, [r4, #CT_DS_A]	@ the requested count
	cmp	r0, r1			@ the same:
	beq	.Lcd_tol		@ the nominal stays
.Lcd_nominal:
	orr	r5, r5, #1		@ bit 0: the nominal
.Lcd_tol:
	ldr	r0, =V_TOLERANCE	@ the tolerance now
	ldr	r0, [r0]		@ its bits
	bl	tenths			@ r0 = round(tolerance * 10)
	ldr	r1, [r4, #CT_DS_B]	@ the requested tenths
	cmp	r0, r1			@ others:
	it	ne			@ (then)
	orrne	r5, r5, #2		@ bit 1: the tolerance
	ldr	r0, =V_WARN_TYPE	@ the three warn words
	ldr	r1, [r0, #0]		@ type now
	ldrb	r2, [r4, #CT_DS_C]	@ requested
	cmp	r1, r2			@ other:
	it	ne			@ (then)
	orrne	r5, r5, #4		@ bit 2
	ldr	r1, [r0, #4]		@ sound now
	ldrb	r2, [r4, #CT_DS_C + 1]	@ requested
	cmp	r1, r2			@ other:
	it	ne			@ (then)
	orrne	r5, r5, #4		@ bit 2
	ldr	r1, [r0, #8]		@ LED now
	ldrb	r2, [r4, #CT_DS_C + 2]	@ requested
	cmp	r1, r2			@ other:
	it	ne			@ (then)
	orrne	r5, r5, #4		@ bit 2
	mov	r0, r5			@ the result
	pop	{r4, r5, r6, pc}	@ back

@ ----------------------------------------------------------------------------
@ ds_apply - the change of CT_DS_OP with r0 = CT_DS_A, r1 = CT_DS_B: a tail branch to its
@   routine (LCR_SET: the routine of the id from lcr_ds with r0 = the value word).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ds_apply, %function
ds_apply:
	ldr	r3, =OWN_CTL		@ control core RAM
	ldr	r0, [r3, #CT_DS_A]	@ r0 = first argument
	ldr	r1, [r3, #CT_DS_B]	@ r1 = second argument
	ldr	r2, [r3, #CT_DS_OP]	@ r2 = command
	cmp	r2, #C_SCREEN		@ SCREEN
	beq	ds_screen
	cmp	r2, #C_HOLD		@ HOLD
	beq	ds_hold
	cmp	r2, #C_SET_SET		@ SETTINGS_SET
	beq	ds_set
	cmp	r2, #C_COMPARE_SET	@ COMPARE_SET
	beq	ds_compare
	ldr	r2, =lcr_ds + 4		@ LCR_SET: the routine of id r0
	ldr	r2, [r2, r0, lsl #3]	@ from the table
	mov	r0, r1			@ r0 = the value word
	bx	r2			@ to the routine (it returns to ds_run)

@ ----------------------------------------------------------------------------
@ The LCR_SET routines, r0 = the value word (DIRECT_SET_DESIGN.md 1.1 / 2.3: what 0x08009614
@ does after the store of the press that lands on that value).
@
@ ds_func - Func 0x20001148 = r0, then: r0 = 0: fn_08021c14([0x200001FC], 0x0803DBA4) only
@   (app_01.s 507); r0 = 1..4: byte 0x200011E4 = word 0x200011E8 = r0, fn_08021c14
@   ([0x200001FC], p), fn_08021c14([0x200001E8], q) with (p, q) of func_pics (app_01.s
@   526-562); then the Func text fn_080228d0([0x200001F0], "%s", word [0x20000258 + 24 lang +
@   4 Func]), fn_08009f10; in screen 2: Func 2 / 3 -> 0x20001178 = Func, else 0x20001178 = 1,
@   byte 0x200011E4 = 1, Func = 1, the text of entry 1, fn_08021c14 with 0x0803DA44 /
@   0x0803D2FC (app_01.s 565-600); last fn_0800f854 (tail call). Stack: 16 bytes.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ds_func, %function
ds_func:
	push	{r4, r5, r6, lr}	@ keep r4..r6, the return address
	ldr	r4, =V_BLOCK		@ r4 = block base
	ldr	r6, =V_OBJS		@ r6 = object words of the measure screens
	mov	r5, r0			@ r5 = Func
	str	r5, [r4, #B_FUNC]	@ Func = value
	cbnz	r5, .Ldf_row		@ 1..4: the row and the secondary too
	ldr	r0, [r6, #OB_FUNC_PIC]	@ AUTO: the Func picture only
	ldr	r1, =d_0803dba4		@ the AUTO picture
	bl	fn_08021c14		@ set as its source
	b	.Ldf_text		@ to the text
.Ldf_row:
	strb	r5, [r4, #B_MAIN_ROW]	@ main row = Func
	str	r5, [r4, #B_SECONDARY]	@ secondary = Func (R -> X, C -> D, L -> Q, Z -> theta)
	ldr	r1, =func_pics - 8	@ pair of Func 1 at func_pics
	ldr	r1, [r1, r5, lsl #3]	@ p
	ldr	r0, [r6, #OB_FUNC_PIC]	@ the Func picture
	bl	fn_08021c14		@ p as its source
	ldr	r1, =func_pics - 4	@ second word of the pairs
	ldr	r1, [r1, r5, lsl #3]	@ q
	ldr	r0, [r6, #OB_SECOND]	@ the secondary picture
	bl	fn_08021c14		@ q as its source
.Ldf_text:
	ldr	r0, [r4, #B_FUNC]	@ the Func text of the value
	bl	func_text		@ set
	bl	fn_08009f10		@ the measurement restart
	ldr	r0, [r4, #B_SCREEN]	@ screen 2: its rule
	cmp	r0, #2			@ compare screen?
	bne	.Ldf_tail		@ no
	ldr	r0, [r4, #B_FUNC]	@ Func now
	cmp	r0, #2			@ C and L are kept as the compare quantity
	beq	.Ldf_keep
	cmp	r0, #3
	beq	.Ldf_keep
	movs	r0, #1			@ any other: R
	str	r0, [r4, #B_CMP_TYPE]	@ compare quantity 1
	strb	r0, [r4, #B_MAIN_ROW]	@ main row 1
	str	r0, [r4, #B_FUNC]	@ Func 1
	bl	func_text		@ the text of entry 1
	ldr	r0, [r6, #OB_FUNC_PIC]	@ the R pictures: the Func picture
	ldr	r1, =d_0803da44		@ R
	bl	fn_08021c14		@ set
	ldr	r0, [r6, #OB_SECOND]	@ the secondary picture
	ldr	r1, =d_0803d2fc		@ X
	bl	fn_08021c14		@ set
	b	.Ldf_tail		@ to the result display
.Ldf_keep:
	str	r0, [r4, #B_CMP_TYPE]	@ compare quantity = Func
.Ldf_tail:
	pop	{r4, r5, r6, lr}	@ restore
	b.w	fn_0800f854		@ the result display (tail call)

@ func_text - r0 = entry 0..4 of the Func names: fn_080228d0([0x200001F0], "%s", word
@   [0x20000258 + 24 * language + 4 * r0]) (tail call). Uses r0..r3, r12.
	.thumb_func
	.type	func_text, %function
func_text:
	ldr	r1, =V_LANGUAGE		@ language
	ldr	r1, [r1]		@ its word
	add	r1, r1, r1, lsl #1	@ * 3
	ldr	r2, =T_FUNC		@ table + 24 * language
	add	r2, r2, r1, lsl #3	@ (3 * 8)
	ldr	r2, [r2, r0, lsl #2]	@ the text of the entry
	ldr	r1, =txt_fmt_s		@ "%s"
	ldr	r0, =V_OBJS		@ object words
	ldr	r0, [r0, #OB_FUNC_TXT]	@ the Func text object
	b.w	fn_080228d0		@ the text set (tail call)

@ ds_secondary - secondary 0x200011E8 = r0; fn_0800f854 (tail call; app_01.s 604-613).
	.thumb_func
	.type	ds_secondary, %function
ds_secondary:
	ldr	r1, =V_SECONDARY	@ the word
	str	r0, [r1]		@ secondary = value
	b.w	fn_0800f854		@ the result display

@ ds_freq - cursor 0x200011A8 = 0, frequency 0x20001144 = r0, fn_08009f10, fn_0800da6c (tail
@   call; app_01.s 696 + fn_0800d940 mode 0, ui_42.s 541).
	.thumb_func
	.type	ds_freq, %function
ds_freq:
	ldr	r1, =V_FREQ		@ the word
	movs	r2, #0			@ cursor 0
	b	ds_cursor		@ the common part

@ ds_level - cursor 1, level 0x20001138 = r0 (float bits), fn_08009f10, fn_0800da6c (tail
@   call; app_01.s 701 + fn_0800d940 mode 1).
	.thumb_func
	.type	ds_level, %function
ds_level:
	ldr	r1, =V_LEVEL		@ the word
	movs	r2, #1			@ cursor 1
	b	ds_cursor		@ the common part

@ ds_cursor - r0 = value, r1 = address of the word, r2 = cursor: cursor 0x200011A8 = r2,
@   [r1] = r0, fn_08009f10, fn_0800da6c (tail call). Stack: 8 bytes.
	.thumb_func
	.type	ds_cursor, %function
ds_cursor:
	push	{r4, lr}		@ keep r4, the return address
	ldr	r3, =V_DISP_A8		@ the cursor word
	str	r2, [r3]		@ cursor under the value
	str	r0, [r1]		@ the value
	bl	fn_08009f10		@ the measurement restart
	pop	{r4, lr}		@ restore
	b.w	fn_0800da6c		@ the cursor labels and values redrawn

@ ds_bias - cursor 2, bias 0x2000113C = r0 (0 or 0x3F000000); with 0.5 V and the level bits
@   above 0x3F000000 (signed, ui_42.s .L0800da1c): level = 0x3E99999A (0.3 V); fn_08009f10,
@   fn_0800da6c (tail call; app_01.s 704 + fn_0800d940 mode 2). Stack: 8 bytes.
	.thumb_func
	.type	ds_bias, %function
ds_bias:
	push	{r4, lr}		@ keep r4, the return address
	ldr	r4, =V_BLOCK		@ r4 = block base
	movs	r1, #2			@ cursor 2:
	str	r1, [r4, #B_CURSOR]	@ stored
	str	r0, [r4, #B_BIAS]	@ the bias
	cbz	r0, .Ldb_restart	@ 0 V: the level stays
	ldr	r1, [r4, #B_LEVEL]	@ 0.5 V: the level bits
	cmp	r1, #0x3F000000		@ above 0.5 V (signed)?
	ble	.Ldb_restart		@ no: the level stays
	ldr	r1, =0x3E99999A		@ yes: 0.3 V
	str	r1, [r4, #B_LEVEL]	@ stored
.Ldb_restart:
	bl	fn_08009f10		@ the measurement restart
	pop	{r4, lr}		@ restore
	b.w	fn_0800da6c		@ the cursor labels and values redrawn

@ ds_range - cursor 3, range 0x2000114C = r0, fn_0800da6c (tail call; fn_0800d940 mode 3 calls
@   no fn_08009f10, ui_42.s 665).
	.thumb_func
	.type	ds_range, %function
ds_range:
	ldr	r1, =V_BLOCK		@ block base
	movs	r2, #3			@ cursor 3:
	str	r2, [r1, #B_CURSOR]	@ stored
	str	r0, [r1, #B_RANGE]	@ the range
	b.w	fn_0800da6c		@ the cursor labels and values redrawn

@ ds_speed - speed 0x20001150 = r0, fn_08021c14([0x200001E0], picture of r0), fn_08009f10
@   (tail call; app_01.s 622-664, the English pictures of our build). Stack: 8 bytes.
	.thumb_func
	.type	ds_speed, %function
ds_speed:
	push	{r4, lr}		@ keep r4, the return address
	ldr	r1, =V_SPEED		@ the word
	str	r0, [r1]		@ speed = value
	ldr	r1, =speed_pics		@ the pictures
	ldr	r1, [r1, r0, lsl #2]	@ its picture
	ldr	r0, =V_OBJS		@ object words
	ldr	r0, [r0, #OB_SPEED]	@ the speed icon
	bl	fn_08021c14		@ the picture as its source
	pop	{r4, lr}		@ restore
	b.w	fn_08009f10		@ the measurement restart

@ ds_circuit - circuit mode 0x20001154 = r0, fn_08021c14([0x200001E4], picture of r0) (tail
@   call; app_01.s 736-770 without the busy halfword and the beep: nothing else).
	.thumb_func
	.type	ds_circuit, %function
ds_circuit:
	ldr	r1, =V_CIRCUIT		@ the word
	str	r0, [r1]		@ circuit mode = value
	ldr	r1, =circuit_pics	@ the pictures
	ldr	r1, [r1, r0, lsl #2]	@ its picture
	ldr	r0, =V_OBJS		@ object words
	ldr	r0, [r0, #OB_CIRCUIT]	@ the circuit icon
	b.w	fn_08021c14		@ the picture as its source (tail call)

@ ----------------------------------------------------------------------------
@ ds_hold - hold 0x200011A4 = r0 (DIRECT_SET_DESIGN.md 1.2, app_01.s 475-486, 617-619):
@   1: fn_08023558([0x200001DC], 1) shows the HOLD object (tail call); 0: fn_08023050
@   ([0x200001DC], 1) hides it, byte 0x200011C4 = 1 (the measurement restart request of the
@   DMA interrupt). Stack: 8 bytes. Also called by meas.s meas_hold (S2.7: a hold ends at a
@   change of its settings).
@ ----------------------------------------------------------------------------
	.global	ds_hold
	.thumb_func
	.type	ds_hold, %function
ds_hold:
	ldr	r1, =V_HOLD		@ the word
	str	r0, [r1]		@ hold = value
	ldr	r2, =V_OBJS		@ object words
	ldr	r2, [r2, #OB_HOLD]	@ r2 = the HOLD object
	cbz	r0, .Ldh_off		@ off: hidden
	mov	r0, r2			@ on: the object
	movs	r1, #1			@ flag 1
	b.w	fn_08023558		@ shown (tail call)
.Ldh_off:
	push	{r4, lr}		@ keep r4, the return address
	mov	r0, r2			@ the object
	movs	r1, #1			@ flag 1
	bl	fn_08023050		@ hidden
	ldr	r0, =V_MEAS_RESTART	@ the measurement restarts:
	movs	r1, #1			@ 1
	strb	r1, [r0]		@ the request byte
	pop	{r4, pc}		@ back

@ ----------------------------------------------------------------------------
@ ds_screen - r0 = screen 1..3 (another than the screen now; DIRECT_SET_DESIGN.md 1.3 / 2.3):
@   from 1 / 2 to 3: fn_08023690([0x200001D8]) (the measure screen's objects freed),
@     0x200011BC = the screen now, fn_0800d6e4 (app_01.s 720-733);
@   1 -> 2: fn_08023690([0x200001D8]), fn_0800d50c; 2 -> 1: fn_08023690([0x200001D8]),
@     fn_0800ca2c (app_01.s 448-462);
@   from 3: with a dialog open (0x200011AC = 1, the condition of 0x08009974): the byte
@     0x2000000C and the words 0x200011AC, 0x200011B0, 0x200011B4, 0x200011B8 = 0 (the stores of
@     piece 0x08009AA2 and of fn_0800f294(0, 0); their redraws are left out: fn_08023690 frees
@     those objects right after); then fn_08023690([0x20000014]) (the settings root with the
@     dialog, a child of it) and fn_0800d50c for screen 2, fn_0800ca2c for screen 1
@     (app_01.s 899-907, 1021-1055).
@   The builders are tail calls (stack 8 bytes before them). No beep, no busy halfword.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ds_screen, %function
ds_screen:
	push	{r4, lr}		@ keep r4, the return address
	mov	r4, r0			@ r4 = target screen
	ldr	r1, =V_SCREEN		@ the screen now
	ldr	r1, [r1]		@ its word
	cmp	r1, #3			@ the settings screen?
	beq	.Lsc_from3		@ yes
	ldr	r0, =V_ROOT_MEAS	@ from 1 / 2: the measure screen freed
	ldr	r0, [r0]		@ its root object
	bl	fn_08023690		@ removed with its children
	cmp	r4, #3			@ to the settings?
	bne	.Lsc_build		@ no: 1 <-> 2
	ldr	r0, =V_SCREEN		@ the screen it came from
	ldr	r0, [r0]		@ its word
	ldr	r1, =V_PREV_SCREEN	@ 0x200011BC
	str	r0, [r1]		@ = it (the way back)
	pop	{r4, lr}		@ restore
	b.w	fn_0800d6e4		@ the settings screen
.Lsc_from3:
	ldr	r0, =V_DIALOG		@ a dialog open?
	ldr	r1, [r0]		@ its word
	cmp	r1, #1			@ open (the key path's test)
	bne	.Lsc_leave		@ no
	movs	r1, #0			@ closed:
	str	r1, [r0, #0]		@ 0x200011AC
	str	r1, [r0, #4]		@ 0x200011B0
	str	r1, [r0, #8]		@ 0x200011B4
	str	r1, [r0, #12]		@ 0x200011B8
	ldr	r0, =V_EDIT		@ the editing byte
	strb	r1, [r0]		@ byte 0x2000000C: no row being edited
.Lsc_leave:
	ldr	r0, =V_ROOT_SET		@ the settings screen freed
	ldr	r0, [r0]		@ its root object
	bl	fn_08023690		@ removed with its children (the dialog too)
.Lsc_build:
	cmp	r4, #2			@ compare screen?
	pop	{r4, lr}		@ restore (the flags stay)
	beq	.Lsc_two		@ yes
	b.w	fn_0800ca2c		@ the measure screen
.Lsc_two:
	b.w	fn_0800d50c		@ the compare screen

@ ----------------------------------------------------------------------------
@ ds_set - r0 = SETTINGS_SET id, r1 = value, the address of the word in CT_DS_C: the word =
@   value; id 0 (brightness): fn_08009e60(value) (the backlight, as fn_0800f5e8 item 2); in
@   screen 3: fn_0800f294(0, 0) and fn_0800e6c8 (tail call), the redraws with which
@   fn_0800f5e8 ends (each returns at once in the state the other draws: dialog open / closed).
@   Other screens: no GUI call (the menu objects exist only in screen 3). Stack: 8 bytes.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ds_set, %function
ds_set:
	push	{r4, lr}		@ keep r4, the return address
	ldr	r2, =OWN_CTL		@ control core RAM
	ldr	r2, [r2, #CT_DS_C]	@ the setting's word
	str	r1, [r2]		@ = value
	cmp	r0, #0			@ brightness?
	bne	.Lst_menu		@ no
	mov	r0, r1			@ the value
	bl	fn_08009e60		@ the backlight at the value
.Lst_menu:
	ldr	r0, =V_SCREEN		@ settings screen?
	ldr	r0, [r0]		@ the screen word
	cmp	r0, #3
	bne	.Lst_out		@ no: done
	movs	r0, #0			@ the menu rows redrawn (no create,
	movs	r1, #0			@ no step)
	bl	fn_0800f294		@ (own_menu in our build)
	pop	{r4, lr}		@ restore
	b.w	fn_0800e6c8		@ an open dialog redrawn
.Lst_out:
	pop	{r4, pc}		@ back

@ ----------------------------------------------------------------------------
@ ds_compare - the pending COMPARE_SET (cs_diff decides the parts): nominal -> scale word
@   0x2000119C = the index, nominal 0x20001184 = float(count) / 100.0 * scale (vcvt, vdiv, vmul:
@   the digit press of fn_0800e224, ui_43.s .L0800E3D4); tolerance -> 0x20001188 =
@   float(tenths) / 10.0; the warn words 0x2000116C / 0x20001170 / 0x20001174 = the requested
@   0 / 1. Then screen 3 with the sorting dialog open (0x200011AC != 0, item 0): fn_0800e6c8
@   (tail call; it rewrites 0x2000119C from the nominal's range, the same classes); screen 2:
@   fn_0800f854 (tail call: deviation, OK / NG, the nominal). Stack: 16 bytes.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ds_compare, %function
ds_compare:
	push	{r4, r5, r6, lr}	@ keep r4..r6, the return address
	ldr	r4, =OWN_CTL		@ r4 = control core RAM
	bl	cs_diff			@ the parts to change
	mov	r5, r0			@ r5 = them
	tst	r5, #1			@ the nominal?
	beq	.Lcp_tol		@ no
	ldr	r0, [r4, #CT_DS_D]	@ scale index
	ldr	r1, =V_SCALE		@ the scale word
	str	r0, [r1]		@ = the index
	ldr	r1, =tab_scale		@ the scales
	ldr	r1, [r1, r0, lsl #2]	@ the scale
	vmov	s2, r1			@ s2 = scale
	ldr	r0, [r4, #CT_DS_A]	@ the count
	vmov	s0, r0			@ s0 = count
	vcvt.f32.s32 s0, s0		@ as float
	ldr	r0, =0x42C80000		@ 100.0
	vmov	s1, r0			@ s1 = 100.0
	vdiv.f32 s0, s0, s1		@ / 100
	vmul.f32 s0, s0, s2		@ * scale
	ldr	r0, =V_NOMINAL		@ the nominal word
	vstr	s0, [r0]		@ = the result
.Lcp_tol:
	tst	r5, #2			@ the tolerance?
	beq	.Lcp_warn		@ no
	ldr	r0, [r4, #CT_DS_B]	@ tenths
	vmov	s0, r0			@ s0 = tenths
	vcvt.f32.s32 s0, s0		@ as float
	vmov.f32 s1, #10.0		@ s1 = 10.0
	vdiv.f32 s0, s0, s1		@ / 10
	ldr	r0, =V_TOLERANCE	@ the tolerance word
	vstr	s0, [r0]		@ = the result
.Lcp_warn:
	ldr	r0, =V_WARN_TYPE	@ the warn words
	ldrb	r1, [r4, #CT_DS_C]	@ type requested
	str	r1, [r0, #0]		@ type
	ldrb	r1, [r4, #CT_DS_C + 1]	@ sound requested
	str	r1, [r0, #4]		@ sound
	ldrb	r1, [r4, #CT_DS_C + 2]	@ LED requested
	str	r1, [r0, #8]		@ LED
	ldr	r0, =V_SCREEN		@ the screen now
	ldr	r0, [r0]		@ its word
	cmp	r0, #2			@ compare screen: its display
	beq	.Lcp_compare
	cmp	r0, #3			@ settings screen:
	bne	.Lcp_out		@ (screen 1: done)
	ldr	r0, =V_DIALOG		@ with a dialog open
	ldr	r0, [r0]		@ its word
	cmp	r0, #0			@ none:
	beq	.Lcp_out		@ done
	ldr	r0, =V_DISP_A8		@ on item 0 (Sorting)
	ldr	r0, [r0]		@ the menu item
	cmp	r0, #0			@ another dialog:
	bne	.Lcp_out		@ done
	pop	{r4, r5, r6, lr}	@ restore
	b.w	fn_0800e6c8		@ the sorting dialog redrawn
.Lcp_compare:
	pop	{r4, r5, r6, lr}	@ restore
	b.w	fn_0800f854		@ deviation, OK / NG and the nominal redrawn
.Lcp_out:
	pop	{r4, r5, r6, pc}	@ back

	.ltorg

@ ============================================================================
@ Tables
@ ============================================================================
	.section .rodata.own.dset,"a",%progbits
	.p2align 2
@ LCR_SET per setting id (the lists of cmd.s lcr_lists): {address of the word, routine}
lcr_ds:
	.word	V_FUNC, ds_func			@ 0 Func
	.word	V_SECONDARY, ds_secondary	@ 1 secondary
	.word	V_FREQ, ds_freq			@ 2 frequency
	.word	V_LEVEL, ds_level		@ 3 level
	.word	V_BIAS, ds_bias			@ 4 bias
	.word	V_RANGE, ds_range		@ 5 range
	.word	V_SPEED, ds_speed		@ 6 speed
	.word	V_CIRCUIT, ds_circuit		@ 7 circuit mode
@ Func 1..4: {Func picture, secondary picture} (app_01.s 526-562, literals 0x08009930..)
func_pics:
	.word	d_0803da44, d_0803d2fc		@ 1 R, X
	.word	d_0803dd04, d_0803d3d4		@ 2 C, D
	.word	d_0803de64, d_0803d584		@ 3 L, Q
	.word	d_0803dfc4, d_0803d8e4		@ 4 Z, theta
@ speed 0..2: the icon (app_01.s literals 0x08009950.., our build's English pictures)
speed_pics:
	.word	d_08040f10, d_08041184, d_08040c9c	@ 0, 1, 2
@ circuit mode 0..2: the icon (app_01.s literals 0x08009968.. : auto, series, parallel)
circuit_pics:
	.word	d_0803cdc4, d_0803cff4, d_0803d224	@ auto, series, parallel
@ the format of the Func text (app_01.s .L0800992c)
txt_fmt_s:
	.asciz	"%s"				@ one string argument
