@ cmd.s - the commands of the control channel: dispatch, device, state and key, measurement,
@ settings, diagnostics and update commands, the records (STATE, MEASURE, COMPARE), the option
@ tables, and the reading and appending of the starter's records for the BOOT_* writer.
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ Specification: USB_CONTROL_DESIGN.md revision 4 (section 9 decisions first) and
@ SETTINGS_SAVE_DESIGN.md revision 4; the records of the starter: starter/starter.s.
@ Frame handling, the job engine and the key injection are in own/ctl.s; the direct changes of
@ SCREEN, LCR_SET, HOLD, SETTINGS_SET and COMPARE_SET in own/dset.s (DIRECT_SET_DESIGN.md
@ revision 2).
@
@ Handlers: r0 = request payload, r1 = its length, r2 = answer data (after the status byte,
@ room for 511 bytes). They return r0 = status (S_*) and r1 = data length, or r0 = ST_DEFER
@ when a job was started (ctl.s job_step answers through job_answer) or the answer was made
@ pending already (dset.s ds_request through job_answer). Every handler pushes
@ {r4..r8, lr} so that the common exits h_* can pop it.
@ All numbers are little-endian. Records and answers are byte-packed; their words and
@ halfwords are stored with str / strh at any address (ARMv7-M allows unaligned word and
@ halfword accesses to normal memory while CCR.UNALIGN_TRP is 0, its reset value; no store to
@ CCR 0xE000ED14 is in the port, src/*.s). The payload is read the same way.
@
@ Records (grow only at the end):
@ STATE (32 bytes): screen u8 (0x20001168), flags u16 (bit 0 hold 0x200011A4, 1 compare
@   screen, 2 DTR, 3 power off requested or done, 4 save failed, 5 backup differs, 6
@   calibration running 0x200050E4, 7 factory mode 0x200011C0 = 2, 8 saves held, 9 restart
@   pending (flash differs from RAM), 10 powered-off mode), Func u8 (0x20001148), main row u8
@   (byte 0x200011E4), secondary u8 (0x200011E8), frequency u32 (0x20001144), level f32
@   (0x20001138), bias f32 (0x2000113C), range u8 (0x2000114C), speed u8 (0x20001150),
@   circuit mode u8 (0x20001154), cursor u8 (0x200011A8 in screens 1 / 2, else 0xFF), dialog
@   u8 (0x200011AC), menu item u8 (0x200011A8 in screen 3, else 0xFF: the vendor item
@   number 0, 2..6, never 1, lang.s own_menu), language u8 (0x2000115C, 1 in our build,
@   save.s set_english), dropped frames u16, save status u8 (low byte of own_save_status), time u32
@   (tick 0x20000480).
@ MEASURE (66 bytes): result number u32, time u32; main row u8 (1 R, 2 C, 3 L, 4 Z) and its
@   value block; secondary u8 (0 R, 1 X, 2 D, 3 Q, 4 theta) and its value block; series /
@   parallel u8 (0x200011EC: 0 series, 1 parallel); |Z| f32 (0x200050C4); theta f32
@   (0x200050CC); frequency u32, level f32, bias f32, range u8, speed u8, circuit mode u8;
@   markers u8 (bit 0 main, bit 1 secondary: the value lies outside the manual's accuracy
@   table, fmt.s MF_MARK; MEASUREMENT_FIX_DESIGN.md S2.1); OCAL flags u8 (bit 0 the gain
@   correction applied, bit 1 GAIN present for the frequency but not at this cell, bit 2
@   OCAL_LOCK active, bit 3 OF_RETAKE; ocal.s ocal_meas_flags, OWN_CAL_DESIGN.md 2.8).
@   Value block (15 bytes): value f32 as the display formats it (R ohm, C nF, L uH, Z / X
@   ohm, D / Q none, theta degree), unit code u8 of the display text (0 none, 1 ohm, 2 kohm,
@   3 Mohm, 4 pF, 5 nF, 6 uF, 7 mF, 8 uH, 9 mH, 10 H, 11 degree), decimals u8 (digits after
@   the point of the text), validity u8 (0 valid, 1 "0L" from the formatter, 2 no reading:
@   tick counter 0x2000120C above 200, 3 held), display text 8 bytes (the formatter's text,
@   zero padded). The texts come from the display's formatters, our wrappers of fmt.s
@   (own_fmt_r ohm, own_fmt_c C, own_fmt_l L, own_fmt_dq D / Q, own_fmt_th theta: OL, sign and
@   digits as the display shows them) with the inputs 0x0800D3D8 / 0x0800D294 give them; the
@   secondary R is the signed 0x200050B8 (S2.2).
@ COMPARE (50 bytes): quantity u8 (0x20001178), nominal f32 (0x20001184), tolerance f32
@   (0x20001188), deviation f32 (0x200050D8), OK u8 (1 when the judgement is IN, cmp.s),
@   pass u32 (0x200050F0), fail u32 (0x200050F4), compare value f32 (0x200050DC), warn type
@   u8, warn sound u8, warn LED u8; then (S2.8 / S2.9, cmp.s) mode u8 in force (MF_EMODE: 0
@   vendor %, 1 %, 2 pF), set mode u8 (MF_TMODE 0..3), letter u8, lower f32, upper f32 (the
@   limits in force, MF_ELO / MF_EHI), result u8 (CR_*), signed deviation f32 (MF_DEV),
@   secondary kind u8, secondary value f32.
@
@ Never-brick: no access to the flash controller here. Settings are written only by the
@ save.s functions; the BOOT_* writer writes the free slot and the record pages only through
@ flash_word / flash_erase_page (save.s), with flash_boot_gate opened for that slot around
@ each command and closed after it. The own calibration area is written only by ocal.s (OCAL_WRITE,
@ OCAL_ROLLBACK, its handlers h_ocal_*), through the same primitives and flash_ocal_gate.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"
	.include "own/ctl.inc"

@ formatter kinds of fmt_value
	.equ	FK_OHM,		0
	.equ	FK_C,		1
	.equ	FK_L,		2
	.equ	FK_PLAIN,	3
	.equ	FK_DEG,		4
	.equ	FK_NONE,	5
	.equ	FK_OHM_X,	6		@ ohm with 0x20001198 = 2 around the call (as
						@ 0x0800D294 formats X: the sign is kept)
	.equ	VB_SIZE,	15		@ value block of MEASURE
	.equ	STATE_SIZE,	32
	.equ	MEASURE_SIZE,	66		@ 64 + the marker byte (S2.1) + the OCAL flags byte
					@ (OWN_CAL_DESIGN.md 2.8)
	.equ	COMPARE_SIZE,	50		@ 29 + the S2.8 / S2.9 tail
	.equ	INFO_SIZE,	46
	.equ	LCR_LISTS,	8
	.equ	SET_IDS,	6		@ set_tab entries
	.equ	SET_ENTRY,	28		@ bytes per set_tab entry
	.equ	DATA_MAX,	511		@ answer data after the status byte
	.equ	SET_A_IDX,	1		@ slot indices of the records
	.equ	SET_B_IDX,	2

@ STEP - one program step with constant fields (ctl.s prog_add).
	.macro	STEP op, kind, max, keya, keyb, arg, target
	ldr	r0, =(\op) | ((\kind) << 8) | ((\max) << 16)	@ op word
	ldr	r1, =(\keya) | ((\keyb) << 16)			@ keys
	ldr	r2, =\arg					@ address / hold
	ldr	r3, =\target					@ target
	bl	prog_add					@ appended
	.endm

@ STEPT - the same with the target in a register r4..r11.
	.macro	STEPT op, kind, max, keya, keyb, arg, treg
	mov	r3, \treg					@ target
	ldr	r0, =(\op) | ((\kind) << 8) | ((\max) << 16)	@ op word
	ldr	r1, =(\keya) | ((\keyb) << 16)			@ keys
	ldr	r2, =\arg					@ address / hold
	bl	prog_add					@ appended
	.endm

	.section .text.own.cmd,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ cmd_dispatch - r0 = seq, r1 = cmd, r2 = payload, r3 = payload length (from ctl.s rx_poll).
@   Notes seq and cmd for the answer, runs the handler from cmd_table (unknown: status 1)
@   and makes its answer pending unless a job will answer.
@ ----------------------------------------------------------------------------
	.global	cmd_dispatch
	.thumb_func
	.type	cmd_dispatch, %function
cmd_dispatch:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_CTL
	str	r0, [r4, #CT_REQ_SEQ]
	str	r1, [r4, #CT_REQ_CMD]
	ldr	r5, =cmd_table
.Ld_find:
	ldrh	r6, [r5, #0]
	movw	r12, #0xFFFF
	cmp	r6, r12
	beq	.Ld_unknown
	cmp	r6, r1
	beq	.Ld_found
	adds	r5, r5, #8
	b	.Ld_find
.Ld_found:
	ldr	r6, [r5, #4]
	mov	r0, r2
	mov	r1, r3
	addw	r2, r4, #CT_ANSB + 1
	blx	r6
	cmp	r0, #ST_DEFER
	beq	.Ld_out
	bl	ans_set
	b	.Ld_out
.Ld_unknown:
	movs	r0, #S_UNKNOWN
	movs	r1, #0
	bl	ans_set
.Ld_out:
	pop	{r4, r5, r6, pc}

@ Common exits of the handlers (they pushed {r4..r8, lr}).
h_bad:
	movs	r0, #S_BAD_ARG
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}
h_notnow:
	movs	r0, #S_NOT_NOW
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}
h_busy:
	movs	r0, #S_BUSY
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}
h_safety:
	movs	r0, #S_SAFETY
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}
h_xfer:
	movs	r0, #S_XFER_CRC
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}
h_storage:
	movs	r0, #S_STORAGE
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}
h_ok0:
	movs	r0, #S_OK
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}
h_defer:
	movs	r0, #ST_DEFER
	movs	r1, #0
	pop	{r4, r5, r6, r7, r8, pc}
h_ret:
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ confirm_ok - r0 = payload, r1 = length -> r0 = 1 when the first u16 is 0x4F4B ("OK").
@   Uses r0, r1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	confirm_ok, %function
confirm_ok:
	cmp	r1, #2
	blo	.Lco_no
	ldrh	r0, [r0]
	movw	r1, #CONFIRM_OK
	cmp	r0, r1
	bne	.Lco_no
	movs	r0, #1
	bx	lr
.Lco_no:
	movs	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ mem_copy - r0 = destination, r1 = source, r2 = bytes (0 allowed), byte by byte.
@   Returns r0 = destination end. Uses r0..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	mem_copy, %function
mem_copy:
	cmp	r2, #0
	beq	.Lmc_out
	ldrb	r3, [r1], #1
	strb	r3, [r0], #1
	subs	r2, r2, #1
	b	mem_copy
.Lmc_out:
	bx	lr

@ ----------------------------------------------------------------------------
@ sv_map - r0 = own_save_status -> r0 = answer status: SV_OK and SV_SAME (nothing needed
@   writing, S2.10) 0, SV_HELD / SV_REFUSED 3, SV_BADBLOCK 7, every other failure 5. Uses r0.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	sv_map, %function
sv_map:
	uxtb	r0, r0
	cmp	r0, #SV_OK
	beq	.Lsm_out
	cmp	r0, #SV_SAME
	beq	.Lsm_same
	cmp	r0, #SV_HELD
	beq	.Lsm_notnow
	cmp	r0, #SV_REFUSED
	beq	.Lsm_notnow
	cmp	r0, #SV_BADBLOCK
	beq	.Lsm_xfer
	movs	r0, #S_STORAGE
	bx	lr
.Lsm_notnow:
	movs	r0, #S_NOT_NOW
	bx	lr
.Lsm_xfer:
	movs	r0, #S_XFER_CRC
	bx	lr
.Lsm_same:
	movs	r0, #S_OK
.Lsm_out:
	bx	lr

	.ltorg

@ ============================================================================
@ 4.1 Device
@ ============================================================================

@ INFO - protocol version u8, capability bits u32, firmware version text 16 bytes, chip UID
@ 12 bytes (0x1FFFF7F0), running slot u8 (hand-over word: 0 F, 1 A, 2 B, 0xFF unknown), slot
@ bootloader version u32 (header word +12 of the running slot, 0 when unknown), application
@ size u32 (end of this image - 0x08006000), last update result u32 (result word).
	.thumb_func
	.type	h_info, %function
h_info:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	movs	r0, #PROTO_VERSION
	strb	r0, [r6, #0]
	ldr	r0, =CAPS_ALL
	str	r0, [r6, #1]
	adds	r0, r6, #5
	ldr	r1, =fw_version
	movs	r2, #16
	bl	mem_copy
	adds	r0, r6, #21
	ldr	r1, =CHIP_UID
	movs	r2, #12
	bl	mem_copy
	ldr	r4, =OWN_CTL
	ldr	r0, [r4, #CT_HAND_SLOT]
	strb	r0, [r6, #33]
	bl	slot_version
	str	r0, [r6, #34]
	ldr	r0, =own_image_end
	ldr	r1, =APP_BASE
	subs	r0, r0, r1
	str	r0, [r6, #38]
	ldr	r0, [r4, #CT_RESULT]
	str	r0, [r6, #42]
	movs	r0, #S_OK
	movs	r1, #INFO_SIZE
	b	h_ret

@ PING - the request bytes back (at most 511).
	.thumb_func
	.type	h_ping, %function
h_ping:
	push	{r4, r5, r6, r7, r8, lr}
	movw	r3, #DATA_MAX
	cmp	r1, r3
	bhi	h_bad
	mov	r4, r1
	mov	r3, r0
	mov	r0, r2
	mov	r1, r3
	mov	r2, r4
	bl	mem_copy
	movs	r0, #S_OK
	mov	r1, r4
	b	h_ret

@ RESET - answer, then the soft restart after the answer has left (ctl.s act_step,
@   soft_restart: the meter stays on). Refused (status 6, no data) unless the slot the starter
@   will start next is feature version >= 2, as UPDATE_MODE: a version-1 slot does not feed the
@   running watchdog after a soft restart (USB_CONTROL_DESIGN.md 6b), so the meter would end up
@   off.
	.thumb_func
	.type	h_reset, %function
h_reset:
	push	{r4, r5, r6, r7, r8, lr}
	bl	rec_scan
	bl	next_slot
	bl	slot_base
	ldr	r5, [r0, #12]		@ version
	cmp	r5, #2
	blo	.Lrs_refused
	adds	r0, r5, #1
	beq	.Lrs_refused		@ erased header word
	movs	r0, #ACT_RESET
	bl	act_set
	b	h_ok0
.Lrs_refused:
	movs	r0, #S_SAFETY
	movs	r1, #0
	b	h_ret

@ BATTERY - supply f32 (0x20005100), icon level u8 (0..4: the number of the thresholds 3.4,
@ 3.6, 3.8, 4.0 V the value is above, signed compares of the float bits as 0x0800C724),
@ low-voltage popup u8 (0x20005118 != 0).
	.thumb_func
	.type	h_battery, %function
h_battery:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r0, =V_SUPPLY
	ldr	r0, [r0]
	str	r0, [r2, #0]
	ldr	r1, =tab_batt
	movs	r3, #0			@ level
.Lhb_loop:
	ldr	r12, [r1, r3, lsl #2]
	cmp	r0, r12
	ble	.Lhb_done
	adds	r3, r3, #1
	cmp	r3, #4
	blo	.Lhb_loop
.Lhb_done:
	strb	r3, [r2, #4]
	ldr	r0, =V_LOWV_POPUP
	ldr	r0, [r0]
	cmp	r0, #0
	it	ne
	movne	r0, #1
	strb	r0, [r2, #5]
	movs	r0, #S_OK
	movs	r1, #6
	b	h_ret

@ POWER_OFF - confirmation 0x4F46; the meter's own path after the answer (ctl.s act_step,
@ key_step, off_step). Refused in powered-off mode (3) and while a calibration runs (6: the
@ injected 0xFE is a key of 4.3).
	.thumb_func
	.type	h_power_off, %function
h_power_off:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #2
	blo	h_bad
	ldrh	r0, [r0]
	movw	r1, #CONFIRM_POWER_OFF
	cmp	r0, r1
	bne	h_bad
	ldr	r0, =OWN_CTL
	ldr	r0, [r0, #CT_FLAGS]
	tst	r0, #CF_OFF
	bne	h_notnow
	ldr	r0, =V_CAL_RUN
	ldr	r0, [r0]
	cmp	r0, #0
	bne	h_safety
	movs	r0, #ACT_POWER_OFF
	bl	act_set
	b	h_ok0

@ FACTORY_MODE - u8 0x200011C0 (0, 1 or 2), read only.
	.thumb_func
	.type	h_factory, %function
h_factory:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r0, =V_FACTORY
	ldr	r0, [r0]
	strb	r0, [r2, #0]
	movs	r0, #S_OK
	movs	r1, #1
	b	h_ret

	.ltorg

@ ============================================================================
@ 4.2 State and events
@ ============================================================================

@ STATE - the STATE record.
	.thumb_func
	.type	h_state, %function
h_state:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r0, r2
	bl	rec_state
	mov	r1, r0
	movs	r0, #S_OK
	b	h_ret

@ STREAM - period u16 in ms (0 stop): STATE records as stream frames (cmd 0x10).
	.thumb_func
	.type	h_stream, %function
h_stream:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #2
	blo	h_bad
	ldrh	r5, [r0]
	ldr	r4, =OWN_CTL
	str	r5, [r4, #CT_ST_PERIOD]
	bl	now
	str	r0, [r4, #CT_ST_NEXT]
	b	h_ok0

@ SCREEN - screen u8 (1 measure, 2 compare, 3 settings), built directly by the key path's own
@ builders without a key press (dset.s ds_screen; an open sorting dialog is closed first).
@ Answer STATE with every status but 2; the refusals are those of dset.s ds_check.
	.thumb_func
	.type	h_screen, %function
h_screen:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #1			@ the screen byte is required
	blo	h_bad
	ldrb	r4, [r0]		@ r4 = screen
	cmp	r4, #1			@ 1..3 only
	blo	h_bad
	cmp	r4, #3
	bhi	h_bad
	ldr	r0, =OWN_CTL		@ control core RAM
	str	r4, [r0, #CT_DS_A]	@ argument of the change: the screen
	movs	r0, #C_SCREEN		@ the change
	movs	r1, #AN_STATE		@ its answer kind
	bl	ds_request		@ refused or nothing to do: answered now; else a job
	b	h_ret			@ r0 = ST_DEFER, r1 = 0

@ KEY - key bit u8 (0..13), hold u16 in ms (optional, 0 = short press); answer STATE after
@ the meter handled it, status 6 when refused before dispatch or when the guard acted.
	.thumb_func
	.type	h_key, %function
h_key:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #1
	blo	h_bad
	ldrb	r4, [r0]
	cmp	r4, #13
	bhi	h_bad
	movs	r5, #0			@ r5 = hold
	cmp	r1, #3
	blo	.Lhk_prog
	ldrh	r5, [r0, #1]
.Lhk_prog:
	movs	r0, #1
	lsl	r4, r0, r4		@ r4 = mask
	bl	prog_reset
	movs	r0, #OP_KEY
	mov	r1, r4
	mov	r2, r5
	movs	r3, #0
	bl	prog_add
	movs	r0, #C_KEY
	movs	r1, #AN_STATE
	movw	r2, #JOB_LIMIT_MS
	add	r2, r2, r5
	bl	job_start
	b	h_defer

	.ltorg

@ ============================================================================
@ 4.4 Measurement
@ ============================================================================

@ LCR_TABLES - list id u8 -> list (lcr_lists): id u8, count u8, value type u8 (0 index, 1
@ u32, 2 f32), name (zero-terminated, English), unit text, then per entry value u32 and its
@ text (English). Without an id: the number of lists u8.
	.thumb_func
	.type	h_lcr_tables, %function
h_lcr_tables:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	cmp	r1, #1
	bhs	.Lht_list
	movs	r0, #LCR_LISTS
	strb	r0, [r6]
	movs	r0, #S_OK
	movs	r1, #1
	b	h_ret
.Lht_list:
	ldrb	r4, [r0]		@ r4 = list id
	cmp	r4, #LCR_LISTS
	bhs	h_bad
	ldr	r5, =lcr_lists
	add	r5, r5, r4, lsl #2
	add	r5, r5, r4, lsl #4	@ r5 = descriptor (20 bytes)
	movw	r8, #DATA_MAX
	add	r8, r8, r6		@ r8 = end of the answer data
	strb	r4, [r6, #0]
	ldrb	r0, [r5, #0]
	strb	r0, [r6, #1]		@ count
	ldrb	r0, [r5, #1]
	strb	r0, [r6, #2]		@ value type
	adds	r7, r6, #3		@ r7 = write pointer
	ldrb	r0, [r5, #2]		@ name kind
	ldr	r1, [r5, #4]
	cmp	r0, #0
	it	ne
	ldrne	r1, [r1]		@ table entry: the text
	mov	r0, r7
	mov	r2, r8
	bl	put_text
	ldr	r1, [r5, #16]		@ unit text
	mov	r2, r8
	bl	put_text
	mov	r7, r0
	movs	r4, #0			@ r4 = entry
.Lht_entry:
	ldrb	r0, [r5, #0]
	cmp	r4, r0
	bhs	.Lht_done
	adds	r0, r7, #4
	cmp	r0, r8
	bhi	.Lht_done
	ldr	r1, [r5, #12]		@ values
	mov	r0, r4
	cmp	r1, #0
	it	ne
	ldrne	r0, [r1, r4, lsl #2]
	str	r0, [r7], #4
	bl	lcr_text
	adds	r4, r4, #1
	b	.Lht_entry
.Lht_done:
	subs	r1, r7, r6
	movs	r0, #S_OK
	b	h_ret

@ lcr_text - r4 = entry, r5 = descriptor, r7 = write pointer, r8 = end (h_lcr_tables): the
@   entry's text written, r7 advanced. Uses r0..r3, r12.
	.thumb_func
	.type	lcr_text, %function
lcr_text:
	push	{r6, lr}
	ldrb	r1, [r5, #3]		@ entry kind
	ldr	r2, [r5, #8]
	cmp	r1, #0
	bne	.Llt_table
	mov	r0, r2			@ own texts: entry r4 of the list
	mov	r1, r4
	bl	z_nth
	mov	r1, r0
	b	.Llt_put
.Llt_table:
	ldr	r1, [r2, r4, lsl #2]	@ English pointer table: entry r4
.Llt_put:
	mov	r0, r7
	mov	r2, r8
	bl	put_text
	mov	r7, r0
	pop	{r6, pc}

@ LCR_SET - setting id u8 (0 Func, 1 secondary, 2 frequency, 3 level, 4 bias, 5 range,
@ 6 speed, 7 circuit mode: the lists of LCR_TABLES, lcr_lists), value index u8 below the list's
@ count; the value is the list's value word (frequency, level, bias) or the index. Set directly
@ with the follow-up work of the meter's handler 0x08009614 for the press that lands on it
@ (dset.s lcr_ds). Screens 1 and 2 only; a value the meter's keys do not reach (0.6 V with the
@ bias at 0.1 V or more, Func 0 / 4 in the compare screen): status 3, nothing changed (dset.s
@ ds_check). Answer MEASURE with every status but 2.
	.thumb_func
	.type	h_lcr_set, %function
h_lcr_set:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #2			@ id and index are required
	blo	h_bad
	ldrb	r4, [r0, #0]		@ r4 = id
	ldrb	r5, [r0, #1]		@ r5 = value index
	cmp	r4, #LCR_LISTS		@ id 0..7
	bhs	h_bad
	ldr	r6, =lcr_lists		@ the lists
	add	r6, r6, r4, lsl #2	@ + 4 id
	add	r6, r6, r4, lsl #4	@ + 16 id: r6 = descriptor (20 bytes)
	ldrb	r0, [r6, #0]		@ number of values
	cmp	r5, r0			@ index below it
	bhs	h_bad			@ else status 2
	cmp	r4, #5			@ range (0x2000114C) while OCAL_LOCK holds the codes:
	bne	.Llr_go			@ status 3, nothing changed (OWN_CAL_DESIGN.md 2.2)
	bl	ocal_locked
	cmp	r0, #0
	bne	h_notnow
.Llr_go:
	ldr	r1, [r6, #12]		@ values of the list, 0: the index is the value
	mov	r0, r5			@ r0 = the index
	cmp	r1, #0			@ a value table?
	it	ne			@ (then)
	ldrne	r0, [r1, r5, lsl #2]	@ r0 = the value word of the index
	ldr	r1, =OWN_CTL		@ control core RAM
	str	r4, [r1, #CT_DS_A]	@ arguments of the change: id
	str	r0, [r1, #CT_DS_B]	@ and the value word
	movs	r0, #C_LCR_SET		@ the change
	movs	r1, #AN_MEASURE		@ its answer kind
	bl	ds_request		@ refused or nothing to do: answered now; else a job
	b	h_ret			@ r0 = ST_DEFER, r1 = 0

@ MONITOR - the DUT level (OWN_CAL_DESIGN.md section 5), 25 bytes: V rms f32, I rms f32,
@   A_V,ref f32, A_I,ref f32, flags u8 (bit 0 kV calibrated at the window's frequency, bit 1
@   gain applied, bit 2 no reading or overload, bit 3 OCAL_LOCK), DC midpoint ADC1 u16, ADC2 u16
@   (0x200011D0 / 0x200011D8, counts), window u32. From the window MEASURE published last
@   (ocal_mon_get): A_V,ref = A_V |nu| / G[c5], A_I,ref = A_I / (G[c6] R[c8] |zeta|) with G from
@   d_0802aee4 (bytes 1..128) and R from d_0802aeec (words, ohm), |nu| = |zeta| = 1 where the gain
@   was not applied; V = kV A_V,ref, I = kV A_I,ref (ocal_kv). NaN (0x7FC00000) for V and I
@   without kV or outside the six frequencies; NaN for all four when no window was published
@   or the published |Z| 0x200050C4 is 1e10 (the overload and no-reading sets).
	.thumb_func
	.type	h_monitor, %function
h_monitor:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2			@ r6 = answer
	bl	ocal_mon_get		@ r0 codes, r1 fi, r2 window, r3 bits; s0 A_V, s1 A_I, s2 |nu|,
	str	r2, [r6, #21]		@ s3 |zeta|
	mov	r4, r0			@ r4 = codes
	mov	r5, r1			@ r5 = fi
	movs	r7, #0			@ r7 = flags
	tst	r3, #1
	it	ne
	orrne	r7, r7, #2		@ gain applied
	ldr	r0, =V_Z
	ldr	r0, [r0]
	ldr	r1, =0x501502F9		@ 1e10: the overload / no-reading set
	cmp	r0, r1
	it	eq
	biceq	r3, r3, #2
	tst	r3, #2
	bne	.Lmon_ref
	orr	r7, r7, #4		@ no reading or overload: all NaN
	ldr	r0, =0x7FC00000
	str	r0, [r6, #0]
	str	r0, [r6, #4]
	str	r0, [r6, #8]
	str	r0, [r6, #12]
	b	.Lmon_tail
.Lmon_ref:
	ldr	r1, =d_0802aee4		@ gains 1, 2 .. 128 (bytes)
	uxtb	r0, r4			@ c5
	cmp	r0, #8
	bhs	.Lmon_nan4
	ldrb	r0, [r1, r0]
	vmov	s4, r0
	vcvt.f32.u32	s4, s4		@ G[c5]
	vmul.f32	s5, s0, s2	@ A_V |nu|
	vdiv.f32	s5, s5, s4	@ A_V,ref
	ubfx	r0, r4, #8, #8		@ c6
	cmp	r0, #8
	bhs	.Lmon_nan4
	ldrb	r0, [r1, r0]
	vmov	s4, r0
	vcvt.f32.u32	s4, s4		@ G[c6]
	ubfx	r0, r4, #16, #8		@ c8
	cmp	r0, #4
	bhs	.Lmon_nan4
	ldr	r1, =d_0802aeec		@ range resistors 100, 1k, 10k, 100k (words)
	ldr	r0, [r1, r0, lsl #2]
	vmov	s6, r0
	vcvt.f32.u32	s6, s6		@ R[c8]
	vmul.f32	s4, s4, s6
	vmul.f32	s4, s4, s3	@ G[c6] R[c8] |zeta|
	vdiv.f32	s6, s1, s4	@ A_I,ref
	vmov	r0, s5
	str	r0, [r6, #8]
	vmov	r0, s6
	str	r0, [r6, #12]
	mov	r0, r5
	bl	ocal_kv			@ r0 = 1 and s0 = kV (changes r1, r2 only; s5, s6 kept)
	cmp	r0, #0
	beq	.Lmon_nan2
	orr	r7, r7, #1
	vmul.f32	s1, s0, s5	@ V
	vmul.f32	s2, s0, s6	@ I
	vmov	r0, s1
	str	r0, [r6, #0]
	vmov	r0, s2
	str	r0, [r6, #4]
	b	.Lmon_tail
.Lmon_nan4:
	orr	r7, r7, #4
	ldr	r0, =0x7FC00000
	str	r0, [r6, #8]
	str	r0, [r6, #12]
.Lmon_nan2:
	ldr	r0, =0x7FC00000
	str	r0, [r6, #0]
	str	r0, [r6, #4]
.Lmon_tail:
	bl	ocal_locked
	cmp	r0, #0
	it	ne
	orrne	r7, r7, #8
	strb	r7, [r6, #16]
	ldr	r1, =0x200011D0		@ ADC1 midpoint (fn_08007fd4)
	ldrh	r0, [r1]
	strh	r0, [r6, #17]
	ldrh	r0, [r1, #8]		@ 0x200011D8 ADC2 midpoint (fn_08007f38)
	strh	r0, [r6, #19]
	movs	r0, #S_OK
	movs	r1, #25
	b	h_ret

@ MEASURE - the MEASURE record.
	.thumb_func
	.type	h_measure, %function
h_measure:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r0, r2
	bl	rec_measure
	mov	r1, r0
	movs	r0, #S_OK
	b	h_ret

@ MEASURE_STREAM - period u16: 0 every new result, 0xFFFF stop, else ms.
	.thumb_func
	.type	h_mstream, %function
h_mstream:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #2
	blo	h_bad
	ldrh	r5, [r0]
	ldr	r4, =OWN_CTL
	movs	r0, #0			@ mode 0: off
	movw	r1, #0xFFFF
	cmp	r5, r1
	beq	.Lmsx_store
	movs	r0, #1			@ mode 1: every result
	cmp	r5, #0
	beq	.Lmsx_store
	movs	r0, #2			@ mode 2: period
.Lmsx_store:
	str	r0, [r4, #CT_MS_MODE]
	str	r5, [r4, #CT_MS_PERIOD]
	bl	now
	str	r0, [r4, #CT_MS_NEXT]
	b	h_ok0

@ COMPARE - the COMPARE record.
	.thumb_func
	.type	h_compare, %function
h_compare:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r0, r2
	bl	rec_compare
	mov	r1, r0
	movs	r0, #S_OK
	b	h_ret

@ TOLERANCE_SET - mode u8, lower i32, upper i32, letter u8, secondary kind u8, secondary value
@ f32 (15 bytes; cmp.s own_tol_set checks and stores them, RAM only, S2.9). Answer COMPARE with
@ every status (the record as it is after the request: unchanged unless the status is 0).
	.thumb_func
	.type	h_tol_set, %function
h_tol_set:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r4, r2			@ r4 = answer data
	bl	own_tol_set		@ r0 = status
	mov	r5, r0
	mov	r0, r4
	bl	rec_compare
	mov	r1, r0
	mov	r0, r5
	b	h_ret

@ HOLD - on u8 (0 / 1), set directly as the meter's key 0x400 handler sets it (dset.s ds_hold);
@ screens 1 / 2 only (else status 3). Answer STATE with every status but 2.
	.thumb_func
	.type	h_hold, %function
h_hold:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #1			@ the byte is required
	blo	h_bad
	ldrb	r4, [r0]		@ r4 = 0 off, 1 on
	cmp	r4, #1
	bhi	h_bad
	ldr	r0, =OWN_CTL		@ control core RAM
	str	r4, [r0, #CT_DS_A]	@ argument of the change
	movs	r0, #C_HOLD		@ the change
	movs	r1, #AN_STATE		@ its answer kind
	bl	ds_request		@ refused or nothing to do: answered now; else a job
	b	h_ret			@ r0 = ST_DEFER, r1 = 0

	.ltorg

@ add_menu - r0 = menu item: step "menu item 0x200011A8 to r0" (screen 3, no dialog: key 0x20
@   = fn_0800f294(0, +1), key 2 = fn_0800f294(0, -1), 0x080099D2..0x08009A9E; in our build
@   own_menu, lang.s, which steps through the visible items 0, 2, 3, 4, 5, 6), r1 = kind.
@   The only caller passes item 5 (h_calibrate); item 1 is never shown, so no command targets it.
	.thumb_func
	.type	add_menu, %function
add_menu:
	push	{r4, lr}
	mov	r3, r0
	lsls	r0, r1, #8
	ldr	r2, =OP_PRESS | (10 << 16)	@ op, at most 10 presses
	orr	r0, r0, r2
	ldr	r1, =KEY_0020 | (KEY_UP << 16)
	ldr	r2, =V_DISP_A8
	bl	prog_add
	pop	{r4, pc}

@ add_settings - r0 = kind: steps "screen 3" and "no dialog open".
	.thumb_func
	.type	add_settings, %function
add_settings:
	push	{r4, lr}
	mov	r4, r0
	ldr	r1, =OP_SCREEN | (8 << 16)
	orr	r0, r1, r4, lsl #8
	movs	r1, #0
	movs	r2, #0
	movs	r3, #3
	bl	prog_add
	ldr	r1, =OP_NODIALOG | (4 << 16)
	orr	r0, r1, r4, lsl #8
	movs	r1, #0
	movs	r2, #0
	movs	r3, #0
	bl	prog_add
	pop	{r4, pc}

	.ltorg

@ COMPARE_SET - nominal f32 (0.001 <= nominal < 1e9, the ranges of fn_0800e4f8), tolerance
@ f32 (0..99.9), warn type u8, warn sound u8, warn LED u8 (0 / 1 each), set directly (dset.s
@ ds_compare) as the sorting editor stores them: the scale index of the nominal's range
@ (fn_0800e4f8 classes) and the count round(nominal * 100 / scale) (nom_count, the editor's
@ split) limited to 100..99999 (the editor sets the third digit to 1 when the three highest are
@ 0), nominal = float(count) / 100.0 * scale (the digit press's formula); the tolerance in
@ tenths of a percent, round(tolerance * 10) at most 999, stored as float(tenths) / 10.0. In any
@ screen 1..3, RAM only. Answer COMPARE with every status but 2.
	.thumb_func
	.type	h_compare_set, %function
h_compare_set:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #11			@ all 11 bytes are required
	blo	h_bad
	mov	r4, r0			@ r4 = payload
	ldr	r5, [r4, #0]		@ r5 = nominal bits
	ldr	r0, =0x3A83126F		@ 0.001
	cmp	r5, r0			@ signed compare of the bits: negative, below 0.001
	blt	h_bad
	ldr	r0, =0x4E6E6B28		@ fn_0800e4f8 upper limit (about 1e9)
	cmp	r5, r0			@ at or above it, infinity, NaN
	bge	h_bad
	ldr	r6, [r4, #4]		@ r6 = tolerance bits
	cmp	r6, #0			@ negative (-0.0 included)
	blt	h_bad
	ldr	r0, =0x42C7CCCD		@ 99.9 (fn_0800e224 limit)
	cmp	r6, r0			@ above it, infinity, NaN
	bgt	h_bad
	ldrb	r0, [r4, #8]		@ warn type 0 / 1
	cmp	r0, #1
	bhi	h_bad
	ldrb	r0, [r4, #9]		@ warn sound 0 / 1
	cmp	r0, #1
	bhi	h_bad
	ldrb	r0, [r4, #10]		@ warn LED 0 / 1
	cmp	r0, #1
	bhi	h_bad
	movs	r7, #0			@ r7 = scale index (fn_0800e4f8 ranges)
	ldr	r0, =0x3F800000
	cmp	r5, r0
	blt	.Lcs_scale
	movs	r7, #1
	ldr	r0, =0x447A0000
	cmp	r5, r0
	blt	.Lcs_scale
	movs	r7, #2
	ldr	r0, =0x49742400
	cmp	r5, r0
	it	ge
	movge	r7, #3
.Lcs_scale:
	mov	r0, r5			@ nominal
	mov	r1, r7			@ scale index
	bl	nom_count		@ r0 = count
	movs	r1, #100		@ at least 100
	cmp	r0, r1
	it	lt
	movlt	r0, r1
	movw	r1, #0x869F		@ at most 99999 = 0x1869F
	movt	r1, #1
	cmp	r0, r1
	it	gt
	movgt	r0, r1
	mov	r8, r0			@ r8 = count
	mov	r0, r6			@ tolerance
	bl	tenths			@ r0 = round(tolerance * 10)
	movw	r1, #999		@ at most 999 (99.9 %)
	cmp	r0, r1
	it	gt
	movgt	r0, r1
	ldr	r6, =OWN_CTL		@ control core RAM
	str	r8, [r6, #CT_DS_A]	@ arguments of the change: the count
	str	r0, [r6, #CT_DS_B]	@ the tolerance in tenths
	ldrb	r0, [r4, #8]		@ the warn words: type in bits 0..7
	ldrb	r1, [r4, #9]		@ sound
	orr	r0, r0, r1, lsl #8	@ in bits 8..15
	ldrb	r1, [r4, #10]		@ LED
	orr	r0, r0, r1, lsl #16	@ in bits 16..23
	str	r0, [r6, #CT_DS_C]	@ the third argument
	str	r7, [r6, #CT_DS_D]	@ the scale index
	movs	r0, #C_COMPARE_SET	@ the change
	movs	r1, #AN_COMPARE		@ its answer kind
	bl	ds_request		@ refused or nothing to do: answered now; else a job
	b	h_ret			@ r0 = ST_DEFER, r1 = 0

	.ltorg

@ CALIBRATE - type u8 (0 short, 11 open; 1..10 only in factory mode 0x200011C0 = 2),
@ confirmation u16 0x4F4B. Refused while saves are held (3: the result could not be saved)
@ and while a calibration runs (4). The meter's procedure with the guard off: settings, menu
@ item 5, key 8 (dialog), keys 4 / 0x10 to the type (0x200050E0), key 8 (start: 0x200050E4
@ = 1); then the sweep (cal_step, cal.s; MEASUREMENT_FIX_DESIGN stage 3) runs from the main
@ loop until status 0x200050EC is 2 (finish, saved by cal_finish) or 3. Progress as events
@ 0x97. Answer: status u8, type u8, own_save_status u32, failed point u8 (0xFF none), reason u8
@ (CAL_R_*; capability bit 25).
	.thumb_func
	.type	h_calibrate, %function
h_calibrate:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #3
	blo	h_bad
	ldrb	r4, [r0, #0]		@ type
	ldrh	r1, [r0, #1]
	movw	r2, #CONFIRM_OK
	cmp	r1, r2
	bne	h_bad
	cmp	r4, #0
	beq	.Lca_type_ok
	cmp	r4, #11
	beq	.Lca_type_ok
	cmp	r4, #10
	bhi	h_bad
	ldr	r0, =V_FACTORY
	ldr	r0, [r0]
	cmp	r0, #2
	bne	h_bad
.Lca_type_ok:
	ldr	r0, =own_save_flags
	ldr	r0, [r0]
	tst	r0, #SF_HELD | SF_RESTART
	bne	h_notnow
	ldr	r0, =V_CAL_RUN
	ldr	r0, [r0]
	cmp	r0, #0
	bne	h_busy
	bl	prog_reset
	movs	r0, #KB_GOFF
	bl	add_settings
	movs	r0, #5
	movs	r1, #KB_GOFF
	bl	add_menu
	STEP	OP_KEY, KB_GOFF, 0, KEY_OK, 0, 0, 0			@ key 8: the dialog
	STEP	OP_CHECK, 0, 0, S_NOT_NOW, 0, V_DIALOG, 1		@ it opened, else 3
	STEPT	OP_PRESS, KB_GOFF, 16, KEY_0004, KEY_0010, V_CAL_TYPE, r4	@ the type
	STEP	OP_KEY, KB_GOFF, 0, KEY_OK, 0, 0, 0			@ key 8: the start
	STEP	OP_CHECK, 0, 0, S_NOT_NOW, 0, V_CAL_RUN, 1		@ it started, else 3
	STEP	OP_WAITCAL, 0, 0, 0, 0, 0, 0				@ the sweep's end
	movs	r0, #C_CALIBRATE
	movs	r1, #AN_CAL
	ldr	r2, =CAL_LIMIT_MS
	bl	job_start
	b	h_defer

	.ltorg

@ ============================================================================
@ 4.5 Settings, screen, diagnostics
@ ============================================================================

@ SETTINGS_TABLES - id u8 (set_tab) -> id u8, kind u8 (0 choices, 1 range), current u32,
@ min u32, max u32, step u32, name (English), number of choices u8, then per choice its text
@ (English). Without an id: the number of settings u8.
	.thumb_func
	.type	h_set_tables, %function
h_set_tables:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	cmp	r1, #1
	bhs	.Lst_one
	movs	r0, #SET_IDS
	strb	r0, [r6]
	movs	r0, #S_OK
	movs	r1, #1
	b	h_ret
.Lst_one:
	ldrb	r4, [r0]
	cmp	r4, #SET_IDS
	bhs	h_bad
	ldr	r5, =set_tab
	movs	r0, #SET_ENTRY
	mla	r5, r4, r0, r5		@ r5 = descriptor
	movw	r8, #DATA_MAX
	add	r8, r8, r6
	strb	r4, [r6, #0]
	ldrb	r0, [r5, #0]
	strb	r0, [r6, #1]		@ kind
	ldr	r0, [r5, #4]
	ldr	r0, [r0]
	str	r0, [r6, #2]		@ current
	ldr	r0, [r5, #8]
	str	r0, [r6, #6]		@ min
	ldr	r0, [r5, #12]
	str	r0, [r6, #10]		@ max
	ldr	r0, [r5, #16]
	str	r0, [r6, #14]		@ step
	add	r0, r6, #18
	ldr	r1, [r5, #20]		@ name: English table entry
	ldr	r1, [r1]
	mov	r2, r8
	bl	put_text
	mov	r7, r0
	ldrb	r0, [r5, #1]		@ choices
	strb	r0, [r7], #1
	movs	r4, #0			@ r4 = choice
.Lst_choice:
	ldrb	r0, [r5, #1]
	cmp	r4, r0
	bhs	.Lst_done
	ldr	r1, [r5, #24]		@ English pointer table of the choices
	ldr	r1, [r1, r4, lsl #2]
	mov	r0, r7
	mov	r2, r8
	bl	put_text
	mov	r7, r0
	adds	r4, r4, #1
	b	.Lst_choice
.Lst_done:
	subs	r1, r7, r6
	movs	r0, #S_OK
	b	h_ret

@ SETTINGS_SET - id u8 (set_tab), value u16, inside the setting's min / max / step: set
@ directly in any screen 1..3 (dset.s ds_set: the word, for brightness the backlight
@ fn_08009e60, in screen 3 the menu's redraws fn_0800f294(0, 0) and fn_0800e6c8 as
@ fn_0800f5e8 ends), RAM only. Ids 0..2 brightness, volume, off time (vendor items 2..4);
@ ids 3..5 warn type, sound, LED (sorting dialog rows 2..4). Answer STATE with every status
@ but 2.
	.thumb_func
	.type	h_set_set, %function
h_set_set:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #3
	blo	h_bad
	ldrb	r4, [r0, #0]		@ id
	ldrh	r6, [r0, #1]		@ value
	cmp	r4, #SET_IDS
	bhs	h_bad
	ldr	r5, =set_tab
	movs	r0, #SET_ENTRY
	mla	r5, r4, r0, r5
	ldr	r0, [r5, #8]		@ min
	cmp	r6, r0
	blo	h_bad
	ldr	r1, [r5, #12]		@ max
	cmp	r6, r1
	bhi	h_bad
	subs	r0, r6, r0
	ldr	r1, [r5, #16]		@ step
	udiv	r2, r0, r1
	mls	r0, r1, r2, r0
	cmp	r0, #0
	bne	h_bad
	ldr	r7, [r5, #4]		@ r7 = address of the setting
	ldr	r0, =OWN_CTL		@ control core RAM
	str	r4, [r0, #CT_DS_A]	@ arguments of the change: id
	str	r6, [r0, #CT_DS_B]	@ the value
	str	r7, [r0, #CT_DS_C]	@ the setting's word
	movs	r0, #C_SET_SET		@ the change
	movs	r1, #AN_STATE		@ its answer kind
	bl	ds_request		@ refused or nothing to do: answered now; else a job
	b	h_ret			@ r0 = ST_DEFER, r1 = 0

	.ltorg

@ save_answer - r6 = answer data: own_save_status u32, own_save_flags u32 written;
@   returns r0 = status (sv_map), r1 = 8. Uses r0..r3.
	.thumb_func
	.type	save_answer, %function
save_answer:
	ldr	r0, =own_save_status
	ldr	r0, [r0]
	str	r0, [r6, #0]
	ldr	r1, =own_save_flags
	ldr	r1, [r1]
	str	r1, [r6, #4]
	push	{r4, lr}
	bl	sv_map
	movs	r1, #8
	pop	{r4, pc}

@ SETTINGS_SAVE - confirmation: own_save (guard off: ctl_loop step 5); its status (up to
@ 1.5 s inside this pass, save.s feeds the watchdog). Answer: status u32, flags u32.
	.thumb_func
	.type	h_set_save, %function
h_set_save:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	bl	confirm_ok
	cmp	r0, #0
	beq	h_bad
	bl	own_save
	bl	save_answer
	b	h_ret

@ CAL_READ - copy u8 (0 A 0x0807F000, 1 B 0x08066000), offset u16, length u16 (1..256),
@ inside the copy's two pages (0x1000 bytes).
	.thumb_func
	.type	h_cal_read, %function
h_cal_read:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #5
	blo	h_bad
	ldrb	r3, [r0, #0]
	ldrh	r4, [r0, #1]		@ offset
	ldrh	r5, [r0, #3]		@ length
	cmp	r5, #0
	beq	h_bad
	cmp	r5, #256
	bhi	h_bad
	adds	r1, r4, r5
	cmp	r1, #SET_SIZE
	bhi	h_bad
	ldr	r1, =SET_A
	cmp	r3, #0
	beq	.Lcr_copy
	cmp	r3, #1
	bne	h_bad
	ldr	r1, =SET_B
.Lcr_copy:
	add	r1, r1, r4
	mov	r0, r2
	mov	r2, r5
	bl	mem_copy
	movs	r0, #S_OK
	mov	r1, r5
	b	h_ret

@ RESTORE_DEFAULTS - confirmation: 0x0800B4C8(0) with the guard off (it saves once itself,
@ 0x0800B5C0), then the redraw of the menu path 0x08009A6C..0x08009A7E: backlight
@ (fn_08009e60(0x20001158)), the screen's root object removed (fn_08023690: 0x20000014 in
@ screen 3, 0x200001D8 in screens 1 / 2, as 0x08009614 does), the measure screen built
@ (fn_0800ca2c). Refused (3) while saves are held or a restart is pending, in screen 0 and
@ while a calibration runs. Answer: status u32, flags u32.
	.thumb_func
	.type	h_restore_def, %function
h_restore_def:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	bl	confirm_ok
	cmp	r0, #0
	beq	h_bad
	ldr	r0, =own_save_flags
	ldr	r0, [r0]
	tst	r0, #SF_HELD | SF_RESTART
	bne	h_notnow
	ldr	r0, =V_CAL_RUN
	ldr	r0, [r0]
	cmp	r0, #0
	bne	h_notnow
	ldr	r0, =V_SCREEN
	ldr	r5, [r0]		@ r5 = screen before the defaults clear it
	cmp	r5, #0
	beq	h_notnow
	cmp	r5, #3
	bhi	h_notnow
	movs	r0, #0
	bl	fn_0800b4c8
	ldr	r0, =V_BRIGHT
	ldr	r0, [r0]
	bl	fn_08009e60
	ldr	r0, =V_ROOT_MEAS
	cmp	r5, #3
	bne	.Lrd_root
	ldr	r0, =V_ROOT_SET
.Lrd_root:
	ldr	r0, [r0]
	bl	fn_08023690
	bl	fn_0800ca2c
	bl	save_answer
	b	h_ret

@ Settings recovery (SETTINGS_SAVE_DESIGN.md "Held saves", design 4.5): confirmation, the
@ save.s function, answer status u32 and flags u32. A restart (soft_restart after the answer)
@ follows when the function set SF_RESTART (flash differs from the RAM block), and after
@ every successful SETTINGS_RESTORE_B and SETTINGS_WRITE_BLOCK (design 9).
@ recovery - r4 = function, r5 = 1: restart after SV_OK; r0 / r1 = payload, length;
@   r6 = answer data. Ends the handler.
	.thumb_func
	.type	h_restore_b, %function
h_restore_b:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =save_restore_b
	movs	r5, #1
	b	recovery

	.thumb_func
	.type	h_accept_a, %function
h_accept_a:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =save_accept_a
	movs	r5, #0
	b	recovery

	.thumb_func
	.type	h_accept_b, %function
h_accept_b:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =save_accept_b
	movs	r5, #0
	b	recovery

	.thumb_func
	.type	h_accept_def, %function
h_accept_def:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =save_accept_defaults
	movs	r5, #0
recovery:
	mov	r6, r2
	bl	confirm_ok
	cmp	r0, #0
	beq	h_bad
	blx	r4
	mov	r7, r0			@ r7 = save.s status
restart_check:
	ldr	r0, =own_save_flags
	ldr	r0, [r0]
	tst	r0, #SF_RESTART
	bne	.Lrc_restart
	cmp	r5, #0
	beq	.Lrc_answer
	uxtb	r0, r7
	cmp	r0, #SV_OK
	bne	.Lrc_answer
.Lrc_restart:
	movs	r0, #ACT_RESET
	bl	act_set
.Lrc_answer:
	bl	save_answer
	b	h_ret

@ SETTINGS_WRITE_BLOCK - confirmation u16, offset u16, total u16 (0xC14), CRC-32 u32 of the
@ whole block (the same in every chunk), chunk bytes. Chunks in order from offset 0 into
@ the staging buffer OWN_STAGE; after the last one save_write_block (markers and CRC checked
@ there, then saved by the save rules) and, on SV_OK, the restart. A save in between (it
@ snapshots into the same buffer) makes the CRC check fail (status 7). Answer for a chunk:
@ next offset u16; after the last: status u32, flags u32.
	.thumb_func
	.type	h_write_block, %function
h_write_block:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	mov	r7, r0			@ r7 = payload
	cmp	r1, #11
	blo	h_bad
	sub	r8, r1, #10		@ r8 = chunk length
	bl	confirm_ok
	cmp	r0, #0
	beq	h_bad
	ldrh	r4, [r7, #2]		@ offset
	ldrh	r0, [r7, #4]		@ total
	movw	r1, #BLK_SIZE
	cmp	r0, r1
	bne	h_bad
	adds	r0, r4, r8
	cmp	r0, r1
	bhi	h_bad
	ldr	r5, =OWN_CTL
	ldr	r0, [r7, #6]		@ CRC-32
	cmp	r4, #0
	bne	.Lwb_more
	str	r0, [r5, #CT_W_CRC]	@ a new transfer
	b	.Lwb_copy
.Lwb_more:
	ldr	r1, [r5, #CT_W_NEXT]
	cmp	r4, r1
	bne	h_bad
	ldr	r1, [r5, #CT_W_CRC]
	cmp	r0, r1
	bne	h_bad
.Lwb_copy:
	ldr	r0, =OWN_STAGE
	add	r0, r0, r4
	add	r1, r7, #10
	mov	r2, r8
	bl	mem_copy
	add	r4, r4, r8
	str	r4, [r5, #CT_W_NEXT]
	movw	r1, #BLK_SIZE
	cmp	r4, r1
	beq	.Lwb_last
	strh	r4, [r6, #0]
	movs	r0, #S_OK
	movs	r1, #2
	b	h_ret
.Lwb_last:
	mvn	r0, #0
	str	r0, [r5, #CT_W_NEXT]
	ldr	r0, [r5, #CT_W_CRC]
	bl	save_write_block
	mov	r7, r0
	movs	r5, #1
	b	restart_check

	.ltorg

@ SETUP_LANGUAGE (0x58) has no handler in our build (LANGUAGE_DESIGN.md: English only; the
@ first-start chooser, screen 0, is never reached, save.s set_english): cmd_dispatch answers
@ status 1 (unknown command), and INFO clears its capability bit 20.

@ SCREENSHOT - band u8 (0..23, 0xFF or no payload: all), screen.s scr_start; answer width
@ u16 320, height u16 240, format u8 0 (RGB565 as the panel gets it), bands u8. The bands
@ follow as stream frames cmd 0x60 (screen.s).
	.thumb_func
	.type	h_screenshot, %function
h_screenshot:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	movs	r4, #SCR_ALL
	cmp	r1, #1
	blo	.Lsh_start
	ldrb	r4, [r0]
.Lsh_start:
	mov	r0, r4
	bl	scr_start
	cmp	r0, #S_OK
	bne	.Lsh_fail
	mov	r0, #320
	strh	r0, [r6, #0]
	movs	r0, #240
	strh	r0, [r6, #2]
	movs	r0, #0
	strb	r0, [r6, #4]
	strb	r1, [r6, #5]
	movs	r0, #S_OK
	movs	r1, #6
	b	h_ret
.Lsh_fail:
	movs	r1, #0
	b	h_ret

@ MEM_READ - address u32, length u16 (1..256); the whole range inside one of mem_ranges
@ (flash, system memory, system configuration and option bytes, main RAM).
	.thumb_func
	.type	h_mem_read, %function
h_mem_read:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #6
	blo	h_bad
	ldr	r4, [r0, #0]		@ address
	ldrh	r5, [r0, #4]		@ length
	cmp	r5, #0
	beq	h_bad
	cmp	r5, #256
	bhi	h_bad
	adds	r7, r4, r5		@ end
	bcs	h_bad
	ldr	r3, =mem_ranges
	movs	r1, #4
.Lmr_range:
	ldr	r0, [r3], #4		@ first address
	ldr	r12, [r3], #4		@ end
	cmp	r4, r0
	blo	.Lmr_next
	cmp	r7, r12
	bls	.Lmr_copy
.Lmr_next:
	subs	r1, r1, #1
	bne	.Lmr_range
	b	h_bad
.Lmr_copy:
	mov	r0, r2
	mov	r1, r4
	mov	r2, r5
	bl	mem_copy
	movs	r0, #S_OK
	mov	r1, r5
	b	h_ret

	.ltorg

@ ============================================================================
@ 4.6 Updates
@ ============================================================================

@ UPDATE_MODE - refused (6) unless the slot the starter will start next (next_slot) has
@ feature version 2 or more (header word +12); then answer, request word, reset (act_step).
@ Answer: predicted slot u8, its version u32, running slot u8 (hand-over word, the cross
@ check).
	.thumb_func
	.type	h_update_mode, %function
h_update_mode:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	bl	rec_scan
	bl	next_slot
	mov	r4, r0
	strb	r4, [r6, #0]
	bl	slot_base
	ldr	r5, [r0, #12]		@ version
	str	r5, [r6, #1]
	ldr	r0, =OWN_CTL
	ldr	r0, [r0, #CT_HAND_SLOT]
	strb	r0, [r6, #5]
	cmp	r5, #2
	blo	.Lum_refused
	adds	r0, r5, #1
	beq	.Lum_refused		@ erased header word
	movs	r0, #ACT_UPDATE
	bl	act_set
	movs	r0, #S_OK
	movs	r1, #6
	b	h_ret
.Lum_refused:
	movs	r0, #S_SAFETY
	movs	r1, #6
	b	h_ret

@ BOOT_BEGIN - slot u8 (1 A, 2 B: must be the free slot), length u32 (0x208..0x6000, a
@ multiple of 4: the slot file from the slot start, header at +0, image at +0x200), CRC-32
@ u32 of the file. The slot is erased one page per main-loop pass (OP_ERASE); answer when
@ all 12 pages read 0xFF.
	.thumb_func
	.type	h_boot_begin, %function
h_boot_begin:
	push	{r4, r5, r6, r7, r8, lr}
	cmp	r1, #9
	blo	h_bad
	ldrb	r4, [r0, #0]		@ slot
	ldr	r5, [r0, #1]		@ length
	ldr	r6, [r0, #5]		@ CRC-32
	cmp	r4, #SET_A_IDX
	blo	h_bad
	cmp	r4, #SET_B_IDX
	bhi	h_bad
	movw	r0, #SLOT_FILE_MIN
	cmp	r5, r0
	blo	h_bad
	cmp	r5, #SLOT_SIZE
	bhi	h_bad
	tst	r5, #3
	bne	h_bad
	bl	rec_scan
	bl	free_slot
	cmp	r0, r4
	bne	h_notnow
	mov	r0, r4
	bl	slot_base
	ldr	r7, =OWN_CTL
	str	r0, [r7, #CT_B_SLOT]
	str	r5, [r7, #CT_B_LEN]
	str	r6, [r7, #CT_B_CRC]
	movs	r0, #0
	str	r0, [r7, #CT_B_PAGE]
	movs	r0, #BS_ERASING
	str	r0, [r7, #CT_B_STATE]
	bl	prog_reset
	STEP	OP_ERASE, 0, 0, 0, 0, 0, 0		@ one page erase per pass
	movs	r0, #C_BOOT_BEGIN
	movs	r1, #AN_NONE
	movw	r2, #ERASE_LIMIT_MS
	bl	job_start
	b	h_defer

@ BOOT_DATA - offset u32 (multiple of 4), chunk of 4..256 bytes (a multiple of 4) inside the
@ length of BOOT_BEGIN; every word through flash_word (read back there). A failure: status
@ 5 with flash result u8 and the word's offset u32.
	.thumb_func
	.type	h_boot_data, %function
h_boot_data:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	cmp	r1, #8
	blo	h_bad
	subs	r5, r1, #4		@ r5 = chunk length
	cmp	r5, #256
	bhi	h_bad
	tst	r5, #3
	bne	h_bad
	ldr	r4, [r0, #0]		@ r4 = offset
	adds	r8, r0, #4		@ r8 = chunk
	tst	r4, #3
	bne	h_bad
	ldr	r7, =OWN_CTL
	adds	r0, r4, r5
	bcs	h_bad
	ldr	r1, [r7, #CT_B_LEN]
	cmp	r0, r1
	bhi	h_bad
	ldr	r0, [r7, #CT_B_STATE]
	cmp	r0, #BS_ERASED
	beq	.Lbd_go
	cmp	r0, #BS_CHECKED
	bne	h_notnow
	movs	r0, #BS_ERASED		@ new data: BOOT_END again
	str	r0, [r7, #CT_B_STATE]
.Lbd_go:
	ldr	r0, [r7, #CT_B_SLOT]
	bl	flash_boot_gate
	ldr	r0, [r7, #CT_B_SLOT]
	add	r4, r4, r0		@ r4 = flash address
.Lbd_word:
	mov	r0, r4
	ldr	r1, [r8], #4
	bl	flash_word
	cmp	r0, #FL_OK
	bne	.Lbd_fail
	adds	r4, r4, #4
	subs	r5, r5, #4
	bne	.Lbd_word
	movs	r0, #0
	bl	flash_boot_gate
	b	h_ok0
.Lbd_fail:
	strb	r0, [r6, #0]
	movs	r0, #0
	bl	flash_boot_gate
	ldr	r0, [r7, #CT_B_SLOT]
	subs	r0, r4, r0
	str	r0, [r6, #1]
	movs	r0, #S_STORAGE
	movs	r1, #5
	b	h_ret

@ BOOT_END - the slot checked: CRC-32 of the file = the one of BOOT_BEGIN, then as the
@ starter checks it (hdr_ok: magic, header CRC, link address = slot + 0x200, length, image
@ CRC, initial SP, reset vector), and the image inside the file. Answer: version u32.
	.thumb_func
	.type	h_boot_end, %function
h_boot_end:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	ldr	r7, =OWN_CTL
	ldr	r0, [r7, #CT_B_STATE]
	cmp	r0, #BS_ERASED
	beq	.Lbe_go
	cmp	r0, #BS_CHECKED
	bne	h_notnow
.Lbe_go:
	ldr	r4, [r7, #CT_B_SLOT]
	mov	r0, r4
	ldr	r1, [r7, #CT_B_LEN]
	bl	own_crc32
	ldr	r1, [r7, #CT_B_CRC]
	cmp	r0, r1
	bne	h_xfer
	mov	r0, r4
	bl	hdr_ok
	cmp	r0, #0
	beq	h_xfer
	ldr	r0, [r4, #4]		@ image length
	add	r0, r0, #0x200
	ldr	r1, [r7, #CT_B_LEN]
	cmp	r0, r1
	bhi	h_xfer
	movs	r0, #BS_CHECKED
	str	r0, [r7, #CT_B_STATE]
	ldr	r0, [r4, #12]
	str	r0, [r6, #0]
	movs	r0, #S_OK
	movs	r1, #4
	b	h_ret

@ BOOT_INSTALL - after BOOT_END: the slot is still the free one and still checks; an INSTALL
@ record appended as starter.s append_record does it (rec_append), then reset after the
@ answer. Status 5 when the record did not read back in three attempts.
	.thumb_func
	.type	h_boot_install, %function
h_boot_install:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r7, =OWN_CTL
	ldr	r0, [r7, #CT_B_STATE]
	cmp	r0, #BS_CHECKED
	bne	h_notnow
	bl	rec_scan
	bl	free_slot
	mov	r4, r0			@ r4 = slot index
	bl	slot_base
	ldr	r5, [r7, #CT_B_SLOT]
	cmp	r0, r5
	bne	h_notnow
	mov	r0, r5
	bl	hdr_ok
	cmp	r0, #0
	beq	h_xfer
	mov	r0, r5
	bl	flash_boot_gate		@ this slot and the record pages
	mov	r0, r4
	movs	r1, #ST_INSTALL
	ldr	r2, [r5, #12]		@ version
	bl	rec_append
	mov	r6, r0
	movs	r0, #0
	bl	flash_boot_gate
	cmp	r6, #0
	bne	h_storage
	movs	r0, #BS_NONE
	str	r0, [r7, #CT_B_STATE]
	movs	r0, #ACT_RESET
	bl	act_set
	b	h_ok0

	.ltorg

@ BOOT_STATUS - per slot F, A, B: version u32, length u32, image CRC u32 (header words +12,
@ +4, +8 as stored), check u8 (hdr_ok); newest record: slot u8 (0xFF none), state u8,
@ sequence u32; the slot that will start next u8 (next_slot); the free slot u8 (free_slot).
	.thumb_func
	.type	h_boot_status, %function
h_boot_status:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r6, r2
	bl	rec_scan
	mov	r8, r0			@ r8 = newest slot or -1
	movs	r4, #0
	mov	r7, r6
.Lbs_slot:
	mov	r0, r4
	bl	slot_base
	mov	r5, r0
	ldr	r0, [r5, #12]
	str	r0, [r7, #0]
	ldr	r0, [r5, #4]
	str	r0, [r7, #4]
	ldr	r0, [r5, #8]
	str	r0, [r7, #8]
	mov	r0, r5
	bl	hdr_ok
	strb	r0, [r7, #12]
	adds	r7, r7, #13
	adds	r4, r4, #1
	cmp	r4, #3
	blo	.Lbs_slot
	movs	r0, #0xFF
	movs	r1, #0
	movs	r2, #0
	cmp	r8, #0
	blt	.Lbs_newest
	mov	r0, r8
	ldr	r3, =OWN_CTL + CT_TAB
	add	r3, r3, r8, lsl #4
	ldr	r1, [r3, #4]		@ state
	ldr	r2, [r3, #0]		@ sequence
.Lbs_newest:
	strb	r0, [r6, #39]
	strb	r1, [r6, #40]
	str	r2, [r6, #41]
	bl	next_slot
	strb	r0, [r6, #45]
	bl	free_slot
	strb	r0, [r6, #46]
	movs	r0, #S_OK
	movs	r1, #47
	b	h_ret

	.ltorg

@ ============================================================================
@ Records
@ ============================================================================

@ ----------------------------------------------------------------------------
@ job_answer - r0 = AN_* kind, r1 = status: the answer data of the kind built at
@   CT_ANSB + 1 and made pending (ans_set). AN_CAL: status u8 0x200050EC, type u8
@   0x200050E0, own_save_status u32, failed point u8 and reason u8 (OWN_CAL CAO_FAILP / CAO_WHY,
@   cal.s). AN_SAVE: own_save_status u32, own_save_flags u32, STATE.
@ ----------------------------------------------------------------------------
	.global	job_answer
	.thumb_func
	.type	job_answer, %function
job_answer:
	push	{r4, r5, r6, lr}
	mov	r5, r1
	ldr	r4, =OWN_CTL + CT_ANSB + 1
	cmp	r0, #AN_STATE
	bne	.Lja_measure
	mov	r0, r4
	bl	rec_state
	b	.Lja_set
.Lja_measure:
	cmp	r0, #AN_MEASURE
	bne	.Lja_compare
	mov	r0, r4
	bl	rec_measure
	b	.Lja_set
.Lja_compare:
	cmp	r0, #AN_COMPARE
	bne	.Lja_cal
	mov	r0, r4
	bl	rec_compare
	b	.Lja_set
.Lja_cal:
	cmp	r0, #AN_CAL
	bne	.Lja_save
	ldr	r0, =V_CAL_STATUS
	ldr	r0, [r0]
	strb	r0, [r4, #0]
	ldr	r0, =V_CAL_TYPE
	ldr	r0, [r0]
	strb	r0, [r4, #1]
	ldr	r0, =own_save_status
	ldr	r0, [r0]
	str	r0, [r4, #2]
	ldr	r1, =OWN_CAL
	ldr	r0, [r1, #CAO_FAILP]
	strb	r0, [r4, #6]		@ the point that failed, 0xFF none (cal.s)
	ldr	r0, [r1, #CAO_WHY]
	strb	r0, [r4, #7]		@ its reason CAL_R_*
	movs	r0, #8
	b	.Lja_set
.Lja_save:
	cmp	r0, #AN_SAVE
	bne	.Lja_none
	ldr	r0, =own_save_status
	ldr	r0, [r0]
	str	r0, [r4, #0]
	ldr	r0, =own_save_flags
	ldr	r0, [r0]
	str	r0, [r4, #4]
	adds	r0, r4, #8
	bl	rec_state
	adds	r0, r0, #8
	b	.Lja_set
.Lja_none:
	movs	r0, #0
.Lja_set:
	mov	r1, r0
	mov	r0, r5
	bl	ans_set
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ rec_state - r0 = destination -> r0 = STATE_SIZE (layout in the file header).
@ ----------------------------------------------------------------------------
	.global	rec_state
	.thumb_func
	.type	rec_state, %function
rec_state:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r4, r0
	ldr	r5, =OWN_CTL
	ldr	r0, =V_SCREEN
	ldr	r6, [r0]		@ r6 = screen
	strb	r6, [r4, #0]
	movs	r7, #0			@ r7 = flags
	ldr	r0, =V_HOLD
	ldr	r0, [r0]
	cmp	r0, #0
	it	ne
	orrne	r7, r7, #0x001
	cmp	r6, #2
	it	eq
	orreq	r7, r7, #0x002
	bl	usb_dtr
	cmp	r0, #0
	it	ne
	orrne	r7, r7, #0x004
	ldr	r0, [r5, #CT_FLAGS]
	tst	r0, #CF_OFF | CF_OFF_WAIT
	it	ne
	orrne	r7, r7, #0x008
	tst	r0, #CF_OFF
	it	ne
	orrne	r7, r7, #0x400
	ldr	r0, [r5, #CT_ACT]
	cmp	r0, #ACT_POWER_OFF
	it	eq
	orreq	r7, r7, #0x008
	ldr	r0, =own_save_flags
	ldr	r0, [r0]
	tst	r0, #SF_FAILED
	it	ne
	orrne	r7, r7, #0x010
	tst	r0, #SF_DIFFERS
	it	ne
	orrne	r7, r7, #0x020
	tst	r0, #SF_HELD
	it	ne
	orrne	r7, r7, #0x100
	tst	r0, #SF_RESTART
	it	ne
	orrne	r7, r7, #0x200
	ldr	r0, =V_CAL_RUN
	ldr	r0, [r0]
	cmp	r0, #0
	it	ne
	orrne	r7, r7, #0x040
	ldr	r0, =V_FACTORY
	ldr	r0, [r0]
	cmp	r0, #2
	it	eq
	orreq	r7, r7, #0x080
	strh	r7, [r4, #1]
	ldr	r0, =V_FUNC
	ldr	r0, [r0]
	strb	r0, [r4, #3]
	ldr	r0, =V_MAIN_ROW
	ldrb	r0, [r0]
	strb	r0, [r4, #4]
	ldr	r0, =V_SECONDARY
	ldr	r0, [r0]
	strb	r0, [r4, #5]
	ldr	r0, =V_FREQ
	ldr	r0, [r0]
	str	r0, [r4, #6]
	ldr	r0, =V_LEVEL
	ldr	r0, [r0]
	str	r0, [r4, #10]
	ldr	r0, =V_BIAS
	ldr	r0, [r0]
	str	r0, [r4, #14]
	ldr	r0, =V_RANGE
	ldr	r0, [r0]
	strb	r0, [r4, #18]
	ldr	r0, =V_SPEED
	ldr	r0, [r0]
	strb	r0, [r4, #19]
	ldr	r0, =V_CIRCUIT
	ldr	r0, [r0]
	strb	r0, [r4, #20]
	ldr	r0, =V_DISP_A8
	ldr	r0, [r0]
	movs	r1, #0xFF		@ cursor
	movs	r2, #0xFF		@ menu item
	cmp	r6, #3
	ite	eq
	moveq	r2, r0
	movne	r1, r0
	cmp	r6, #0
	it	eq
	moveq	r1, #0xFF
	strb	r1, [r4, #21]
	strb	r2, [r4, #23]
	ldr	r0, =V_DIALOG
	ldr	r0, [r0]
	strb	r0, [r4, #22]
	ldr	r0, =V_LANGUAGE
	ldr	r0, [r0]
	strb	r0, [r4, #24]
	ldr	r0, [r5, #CT_DROPPED]
	strh	r0, [r4, #25]
	ldr	r0, =own_save_status
	ldr	r0, [r0]
	strb	r0, [r4, #27]
	bl	now
	str	r0, [r4, #28]
	movs	r0, #STATE_SIZE
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ rec_measure - r0 = destination -> r0 = MEASURE_SIZE (layout in the file header).
@   Main row by byte 0x200011E4 (0x0800D3D8): 1 R 0x200050B8 / 4 Z 0x200050C4 (ohm), 2 C
@   0x200050BC, 3 L 0x200050C0. Secondary by 0x200011E8 (0x0800D294): 0 R (ohm, signed as the
@   display shows it, S2.2), 1 X 0x200050C8 (ohm, sign kept), 2 D 0x200050D4, 3 Q 0x200050D0,
@   4 theta 0x200050CC. Byte 64: the two markers fmt_value returns (bit 0 main, 1 secondary).
@ ----------------------------------------------------------------------------
	.global	rec_measure
	.thumb_func
	.type	rec_measure, %function
rec_measure:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	ldr	r5, =OWN_CTL
	ldr	r0, [r5, #CT_MEAS_SEQ]
	str	r0, [r4, #0]
	bl	now
	str	r0, [r4, #4]
	ldr	r0, =V_MAIN_ROW
	ldrb	r6, [r0]
	strb	r6, [r4, #8]
	movs	r1, #FK_NONE
	movs	r2, #0
	cmp	r6, #1
	beq	.Lrm_r
	cmp	r6, #2
	beq	.Lrm_c
	cmp	r6, #3
	beq	.Lrm_l
	cmp	r6, #4
	bne	.Lrm_main
	movs	r1, #FK_OHM
	ldr	r2, =V_Z
	b	.Lrm_main_ld
.Lrm_r:
	movs	r1, #FK_OHM
	ldr	r2, =V_R
	b	.Lrm_main_ld
.Lrm_c:
	movs	r1, #FK_C
	ldr	r2, =V_C
	b	.Lrm_main_ld
.Lrm_l:
	movs	r1, #FK_L
	ldr	r2, =V_L
.Lrm_main_ld:
	ldr	r2, [r2]
.Lrm_main:
	add	r0, r4, #9
	bl	fmt_value
	mov	r5, r0			@ r5 = marker of the main value
	ldr	r0, =V_SECONDARY
	ldr	r6, [r0]
	strb	r6, [r4, #24]
	movs	r1, #FK_NONE
	movs	r2, #0
	cmp	r6, #0
	beq	.Lrm_sr
	cmp	r6, #1
	beq	.Lrm_sx
	cmp	r6, #2
	beq	.Lrm_sd
	cmp	r6, #3
	beq	.Lrm_sq
	cmp	r6, #4
	bne	.Lrm_sec
	movs	r1, #FK_DEG
	ldr	r2, =V_THETA
	b	.Lrm_sec_ld
.Lrm_sr:
	ldr	r2, =V_R
	ldr	r2, [r2]		@ signed: the display's own_fmt_rs takes this word (S2.2)
	movs	r1, #FK_OHM
	b	.Lrm_sec
.Lrm_sx:
	movs	r1, #FK_OHM_X
	ldr	r2, =V_X
	b	.Lrm_sec_ld
.Lrm_sd:
	movs	r1, #FK_PLAIN
	ldr	r2, =V_D
	b	.Lrm_sec_ld
.Lrm_sq:
	movs	r1, #FK_PLAIN
	ldr	r2, =V_Q
.Lrm_sec_ld:
	ldr	r2, [r2]
.Lrm_sec:
	add	r0, r4, #25
	bl	fmt_value
	orr	r5, r5, r0, lsl #1	@ marker of the secondary value: bit 1
	strb	r5, [r4, #64]
	ldr	r0, =V_SERPAR
	ldr	r0, [r0]
	strb	r0, [r4, #40]
	ldr	r0, =V_Z
	ldr	r0, [r0]
	str	r0, [r4, #41]
	ldr	r0, =V_THETA
	ldr	r0, [r0]
	str	r0, [r4, #45]
	ldr	r0, =V_FREQ
	ldr	r0, [r0]
	str	r0, [r4, #49]
	ldr	r0, =V_LEVEL
	ldr	r0, [r0]
	str	r0, [r4, #53]
	ldr	r0, =V_BIAS
	ldr	r0, [r0]
	str	r0, [r4, #57]
	ldr	r0, =V_RANGE
	ldr	r0, [r0]
	strb	r0, [r4, #61]
	ldr	r0, =V_SPEED
	ldr	r0, [r0]
	strb	r0, [r4, #62]
	ldr	r0, =V_CIRCUIT
	ldr	r0, [r0]
	strb	r0, [r4, #63]
	bl	ocal_meas_flags		@ OCAL flags: gain applied, GAIN not at this cell, lock,
	strb	r0, [r4, #65]		@ OF_RETAKE (ocal.s)
	movs	r0, #MEASURE_SIZE
	pop	{r4, r5, r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ fmt_value - r0 = value block, r1 = FK_* kind, r2 = float bits: value, unit code, decimals,
@   validity and the 8-byte text from the display's formatter (fmt_fn) called with s0 = the
@   value, r0 = text buffer, r1 = unit buffer, r2 = index word (CT_FMT_*). FK_OHM_X stores 2
@   to 0x20001198 around the call and 0 after it, as 0x0800D294 does for X.
@   Returns r0 = the formatter's marker (fmt.s MF_MARK: 1 outside the accuracy table; 0 for
@   FK_NONE), and leaves MF_MARK at 0 (a display row without a formatter call then reads 0).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	fmt_value, %function
fmt_value:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r4, r0
	mov	r5, r1
	mov	r6, r2
	ldr	r0, =OWN_FUNC
	movs	r1, #0
	str	r1, [r0, #MF_MARK]	@ FK_NONE: no marker
	str	r6, [r4, #0]
	ldr	r7, =OWN_CTL + CT_FMT_TXT
	movs	r0, #0
	movs	r1, #0
.Lfv_clear:
	str	r0, [r7, r1]		@ text 16, unit 8, index word
	adds	r1, r1, #4
	cmp	r1, #28
	blo	.Lfv_clear
	movs	r8, #0			@ r8 = unit code
	cmp	r5, #FK_NONE
	beq	.Lfv_text
	cmp	r5, #FK_OHM_X
	bne	.Lfv_call
	ldr	r0, =V_SIGN_MODE
	movs	r1, #2
	str	r1, [r0]
.Lfv_call:
	ldr	r3, =fmt_fn
	ldr	r3, [r3, r5, lsl #2]
	vmov	s0, r6
	mov	r0, r7
	add	r1, r7, #16
	add	r2, r7, #24
	blx	r3
	cmp	r5, #FK_OHM_X
	bne	.Lfv_unit
	ldr	r0, =V_SIGN_MODE
	movs	r1, #0
	str	r1, [r0]
.Lfv_unit:
	ldr	r0, [r7, #24]		@ index the formatter returned
	ldr	r1, =fmt_units
	add	r1, r1, r5, lsl #2	@ {first, last, add} of this kind
	ldrb	r2, [r1, #0]
	cmp	r0, r2
	blo	.Lfv_text
	ldrb	r2, [r1, #1]
	cmp	r0, r2
	bhi	.Lfv_text
	ldrsb	r2, [r1, #2]
	add	r8, r0, r2
.Lfv_text:
	strb	r8, [r4, #4]
	movs	r0, #0			@ decimals: digits after the point
	mov	r1, r7
.Lfv_point:
	ldrb	r2, [r1], #1
	cmp	r2, #0
	beq	.Lfv_dec
	cmp	r2, #'.'
	bne	.Lfv_point
.Lfv_digit:
	ldrb	r2, [r1], #1
	sub	r2, r2, #'0'
	cmp	r2, #9
	bhi	.Lfv_dec
	adds	r0, r0, #1
	b	.Lfv_digit
.Lfv_dec:
	strb	r0, [r4, #5]
	movs	r0, #3			@ validity: held
	ldr	r1, =V_HOLD
	ldr	r1, [r1]
	cmp	r1, #0
	bne	.Lfv_valid
	movs	r0, #2			@ no reading for 200 ticks
	ldr	r1, =V_NO_READ_CNT
	ldr	r1, [r1]
	cmp	r1, #200
	bhi	.Lfv_valid
	movs	r0, #0
	cmp	r5, #FK_NONE
	beq	.Lfv_valid
	ldrb	r1, [r7, #0]
	cmp	r1, #'0'
	bne	.Lfv_valid
	ldrb	r1, [r7, #1]
	cmp	r1, #'L'
	it	eq
	moveq	r0, #1			@ "0L" from the formatter
.Lfv_valid:
	strb	r0, [r4, #6]
	adds	r0, r4, #7
	mov	r1, r7
	movs	r2, #8
	bl	mem_copy
	ldr	r1, =OWN_FUNC
	ldr	r0, [r1, #MF_MARK]	@ the marker of this value
	movs	r2, #0
	str	r2, [r1, #MF_MARK]
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ rec_compare - r0 = destination -> r0 = COMPARE_SIZE (layout in the file header).
@ ----------------------------------------------------------------------------
	.global	rec_compare
	.thumb_func
	.type	rec_compare, %function
rec_compare:
	push	{r4, lr}
	mov	r4, r0
	bl	cmp_effective		@ the limits in force now (cmp.s), also off screen 2
	ldr	r0, =V_CMP_TYPE
	ldr	r0, [r0]
	strb	r0, [r4, #0]
	ldr	r0, =V_NOMINAL
	ldr	r0, [r0]
	str	r0, [r4, #1]
	ldr	r0, =V_TOLERANCE
	ldr	r1, [r0]
	str	r1, [r4, #5]
	ldr	r0, =V_DEVIATION
	ldr	r0, [r0]
	str	r0, [r4, #9]
	ldr	r1, =OWN_FUNC
	ldr	r0, [r1, #MF_RES]
	cmp	r0, #CR_IN
	ite	eq
	moveq	r0, #1			@ the judgement is IN (cmp.s)
	movne	r0, #0
	strb	r0, [r4, #13]
	ldr	r0, =V_PASS_COUNT
	ldr	r0, [r0]
	str	r0, [r4, #14]
	ldr	r0, =V_FAIL_COUNT
	ldr	r0, [r0]
	str	r0, [r4, #18]
	ldr	r0, =V_CMP_VALUE
	ldr	r0, [r0]
	str	r0, [r4, #22]
	ldr	r0, =V_WARN_TYPE
	ldr	r0, [r0]
	strb	r0, [r4, #26]
	ldr	r0, =V_WARN_SOUND
	ldr	r0, [r0]
	strb	r0, [r4, #27]
	ldr	r0, =V_WARN_LED
	ldr	r0, [r0]
	strb	r0, [r4, #28]
	ldr	r1, =OWN_FUNC		@ the tail (S2.8 / S2.9, cmp.s)
	ldr	r0, [r1, #MF_EMODE]
	strb	r0, [r4, #29]
	ldr	r0, [r1, #MF_TMODE]
	strb	r0, [r4, #30]
	ldr	r0, [r1, #MF_TLET]
	strb	r0, [r4, #31]
	ldr	r0, [r1, #MF_ELO]
	str	r0, [r4, #32]
	ldr	r0, [r1, #MF_EHI]
	str	r0, [r4, #36]
	ldr	r0, [r1, #MF_RES]
	strb	r0, [r4, #40]
	ldr	r0, [r1, #MF_DEV]
	str	r0, [r4, #41]
	ldr	r0, [r1, #MF_SKIND]
	strb	r0, [r4, #45]
	ldr	r0, [r1, #MF_SVAL]
	str	r0, [r4, #46]
	movs	r0, #COMPARE_SIZE
	pop	{r4, pc}

	.ltorg

@ ============================================================================
@ Texts
@ ============================================================================

@ ----------------------------------------------------------------------------
@ put_text - r0 = destination, r1 = zero-terminated text, r2 = end of the answer data:
@   at most TXT_MAX bytes of the text and its zero copied, never past the end (the zero is
@   always written while room is left). A text pointer outside the application flash
@   0x08006000..0x08061FFF and the RAM 0x20000000..0x2001FFFF is taken as an empty text.
@   Returns r0 = position after the zero. Uses r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	put_text, %function
put_text:
	ldr	r3, =APP_BASE
	cmp	r1, r3
	blo	.Lpt_ram
	ldr	r3, =APP_END
	cmp	r1, r3
	blo	.Lpt_go
.Lpt_ram:
	ldr	r3, =0x20000000
	cmp	r1, r3
	blo	.Lpt_empty
	ldr	r3, =0x20020000
	cmp	r1, r3
	blo	.Lpt_go
.Lpt_empty:
	ldr	r1, =txt_empty
.Lpt_go:
	movs	r12, #TXT_MAX
.Lpt_byte:
	cmp	r0, r2
	bhs	.Lpt_out
	ldrb	r3, [r1], #1
	subs	r12, r12, #1
	it	mi
	movmi	r3, #0			@ longer than TXT_MAX: cut
	strb	r3, [r0], #1
	cmp	r3, #0
	bne	.Lpt_byte
.Lpt_out:
	bx	lr

@ ----------------------------------------------------------------------------
@ z_nth - r0 = list of zero-terminated texts, r1 = index -> r0 = text r1. Uses r0..r2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	z_nth, %function
z_nth:
	cmp	r1, #0
	beq	.Lzn_out
.Lzn_skip:
	ldrb	r2, [r0], #1
	cmp	r2, #0
	bne	.Lzn_skip
	subs	r1, r1, #1
	bne	.Lzn_skip
.Lzn_out:
	bx	lr

	.ltorg

@ ============================================================================
@ Records and slots of the starter (starter/starter.s, bootloader/src/slot.inc)
@ ============================================================================

@ ----------------------------------------------------------------------------
@ slot_base - r0 = slot index 0..2 -> r0 = SLOT_F + index * 0x6000. Uses r0, r1.
@ slot_version - r0 = slot index -> r0 = header word +12 when the slot's magic is
@   "SLOT", else 0 (index above 2: 0). Uses r0, r1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	slot_base, %function
slot_base:
	mov	r1, #SLOT_SIZE
	muls	r0, r1, r0
	ldr	r1, =SLOT_F
	add	r0, r0, r1
	bx	lr

	.thumb_func
	.type	slot_version, %function
slot_version:
	cmp	r0, #2
	bhi	.Lsv_none
	push	{r4, lr}
	bl	slot_base
	ldr	r1, [r0, #0]
	ldr	r4, =HDR_MAGIC
	cmp	r1, r4
	ldr	r0, [r0, #12]
	it	ne
	movne	r0, #0
	pop	{r4, pc}
.Lsv_none:
	movs	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ hdr_ok - r0 = slot base -> r0 = 1 when the starter would start it (starter.s header_ok:
@   magic, CRC-32 of header bytes 0..27 = word +28, link address = base + 0x200, 8 <=
@   length <= 0x5E00 and a multiple of 4, image CRC-32 = word +8, initial SP above
@   0x20000000 and at most 0x20024000, reset vector odd and inside the image), else 0.
@ ----------------------------------------------------------------------------
	.global	hdr_ok
	.thumb_func
	.type	hdr_ok, %function
hdr_ok:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	ldr	r1, [r4, #0]
	ldr	r2, =HDR_MAGIC
	cmp	r1, r2
	bne	.Lho_no
	mov	r0, r4
	movs	r1, #28
	bl	own_crc32
	ldr	r1, [r4, #28]
	cmp	r0, r1
	bne	.Lho_no
	ldr	r1, [r4, #16]
	add	r5, r4, #0x200		@ r5 = image start
	cmp	r1, r5
	bne	.Lho_no
	ldr	r6, [r4, #4]		@ r6 = length
	cmp	r6, #8
	blo	.Lho_no
	cmp	r6, #SLOT_ROOM
	bhi	.Lho_no
	tst	r6, #3
	bne	.Lho_no
	mov	r0, r5
	mov	r1, r6
	bl	own_crc32
	ldr	r1, [r4, #8]
	cmp	r0, r1
	bne	.Lho_no
	ldr	r1, [r5, #0]		@ initial SP
	ldr	r2, =SRAM_LO
	cmp	r1, r2
	bls	.Lho_no
	ldr	r2, =SRAM_HI
	cmp	r1, r2
	bhi	.Lho_no
	ldr	r1, [r5, #4]		@ reset vector
	tst	r1, #1
	beq	.Lho_no
	bic	r1, r1, #1
	cmp	r1, r5
	blo	.Lho_no
	add	r2, r5, r6
	cmp	r1, r2
	bhs	.Lho_no
	movs	r0, #1
	pop	{r4, r5, r6, pc}
.Lho_no:
	movs	r0, #0
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ cell_valid - r0 = cell address -> r0 = 1 when word 0 bits 31..16 are 0x4C52 and word +12
@   is the CRC-32 of bytes 0..11 (starter.s cell_valid), else 0.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cell_valid, %function
cell_valid:
	push	{r4, lr}
	mov	r4, r0
	ldr	r1, [r4, #0]
	lsrs	r1, r1, #16
	movw	r2, #REC_TAG
	cmp	r1, r2
	bne	.Lcv_no
	movs	r1, #12
	bl	own_crc32
	ldr	r1, [r4, #12]
	cmp	r0, r1
	bne	.Lcv_no
	movs	r0, #1
	pop	{r4, pc}
.Lcv_no:
	movs	r0, #0
	pop	{r4, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ rec_scan - CT_TAB = the newest valid record of each slot (starter.s scan_records: every
@   16-byte cell of both record pages, slot < 3, state 1..3, highest sequence per slot).
@   Returns r0 = slot of the newest record over the three slots, or -1.
@ ----------------------------------------------------------------------------
	.global	rec_scan
	.thumb_func
	.type	rec_scan, %function
rec_scan:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r8, =OWN_CTL + CT_TAB
	movs	r0, #0
	movs	r1, #0
.Lrs_clear:
	str	r0, [r8, r1]
	adds	r1, r1, #4
	cmp	r1, #48
	blo	.Lrs_clear
	ldr	r4, =REC0		@ r4 = cell
.Lrs_cell:
	mov	r0, r4
	bl	cell_valid
	cmp	r0, #0
	beq	.Lrs_next
	ldr	r1, [r4, #0]
	ubfx	r5, r1, #8, #8		@ slot
	uxtb	r6, r1			@ state
	cmp	r5, #3
	bhs	.Lrs_next
	cmp	r6, #ST_INSTALL
	blo	.Lrs_next
	cmp	r6, #ST_OK
	bhi	.Lrs_next
	add	r7, r8, r5, lsl #4
	ldr	r1, [r4, #8]		@ sequence
	ldr	r2, [r7, #0]
	cmp	r1, r2
	bls	.Lrs_next
	str	r1, [r7, #0]
	str	r6, [r7, #4]
	ldr	r1, [r4, #4]
	str	r1, [r7, #8]
	str	r4, [r7, #12]
.Lrs_next:
	adds	r4, r4, #16
	ldr	r1, =REC_END
	cmp	r4, r1
	blo	.Lrs_cell
	mov	r0, #-1			@ newest over the three slots
	movs	r1, #0
	movs	r2, #0
.Lrs_best:
	add	r3, r8, r2, lsl #4
	ldr	r3, [r3, #0]
	cmp	r3, r1
	bls	.Lrs_best_next
	mov	r1, r3
	mov	r0, r2
.Lrs_best_next:
	adds	r2, r2, #1
	cmp	r2, #3
	blo	.Lrs_best
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ newest - r0 = slot of the highest sequence in CT_TAB (as rec_scan returns it), or -1.
@   Uses r0..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	newest, %function
newest:
	ldr	r3, =OWN_CTL + CT_TAB
	mov	r0, #-1
	movs	r1, #0
	movs	r2, #0
.Lnw_loop:
	add	r12, r3, r2, lsl #4
	ldr	r12, [r12, #0]
	cmp	r12, r1
	bls	.Lnw_next
	mov	r1, r12
	mov	r0, r2
.Lnw_next:
	adds	r2, r2, #1
	cmp	r2, #3
	blo	.Lnw_loop
	bx	lr

@ ----------------------------------------------------------------------------
@ free_slot - from CT_TAB (rec_scan first): the one of A (1) / B (2) that is not the newest
@   slot recorded OK; when neither A nor B is recorded OK: A unless the newest record names
@   A, then B (design 4.6). Returns r0 = 1 or 2.
@ ----------------------------------------------------------------------------
	.global	free_slot
	.thumb_func
	.type	free_slot, %function
free_slot:
	push	{r4, lr}
	ldr	r3, =OWN_CTL + CT_TAB
	ldr	r0, [r3, #16 + 4]	@ state of A
	ldr	r1, [r3, #32 + 4]	@ state of B
	cmp	r0, #ST_OK
	bne	.Lfs_a_not
	cmp	r1, #ST_OK
	bne	.Lfs_b		@ only A OK: B is free
	ldr	r0, [r3, #16]		@ both OK: the older one is free
	ldr	r1, [r3, #32]
	cmp	r0, r1
	bhi	.Lfs_b
	b	.Lfs_a
.Lfs_a_not:
	cmp	r1, #ST_OK
	beq	.Lfs_a			@ only B OK: A is free
	bl	newest
	cmp	r0, #SET_A_IDX
	beq	.Lfs_b
.Lfs_a:
	movs	r0, #SET_A_IDX
	pop	{r4, pc}
.Lfs_b:
	movs	r0, #SET_B_IDX
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ next_slot - the slot the starter will start at the next reset (design 4.6, starter.s
@   reset): fault flag 0x2001FFF0 = 0x464C5446 -> F; no record -> F; newest record TRIAL
@   -> the newest other slot recorded OK whose header checks, else F; INSTALL or OK -> that
@   slot when its header checks, else F. CT_TAB from rec_scan. Returns r0 = 0..2.
@ ----------------------------------------------------------------------------
	.global	next_slot
	.thumb_func
	.type	next_slot, %function
next_slot:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r0, =FAULT_FLAG
	ldr	r0, [r0]
	ldr	r1, =FAULT_MAGIC
	cmp	r0, r1
	beq	.Lns_f
	bl	newest
	cmp	r0, #0
	blt	.Lns_f
	mov	r4, r0			@ r4 = newest slot
	ldr	r8, =OWN_CTL + CT_TAB
	add	r0, r8, r4, lsl #4
	ldr	r0, [r0, #4]
	cmp	r0, #ST_TRIAL
	beq	.Lns_trial
	mov	r0, r4
	bl	slot_base
	bl	hdr_ok
	cmp	r0, #0
	beq	.Lns_f
	mov	r0, r4
	pop	{r4, r5, r6, r7, r8, pc}
.Lns_trial:
	mov	r5, #-1			@ r5 = best slot
	movs	r6, #0			@ r6 = its sequence
	movs	r7, #0			@ r7 = slot
.Lns_loop:
	cmp	r7, r4
	beq	.Lns_next
	add	r0, r8, r7, lsl #4
	ldr	r1, [r0, #4]
	cmp	r1, #ST_OK
	bne	.Lns_next
	ldr	r1, [r0, #0]
	cmp	r1, r6
	bls	.Lns_next
	mov	r0, r7
	bl	slot_base
	bl	hdr_ok
	cmp	r0, #0
	beq	.Lns_next
	add	r0, r8, r7, lsl #4
	ldr	r6, [r0, #0]
	mov	r5, r7
.Lns_next:
	adds	r7, r7, #1
	cmp	r7, #3
	blo	.Lns_loop
	cmp	r5, #0
	blt	.Lns_f
	mov	r0, r5
	pop	{r4, r5, r6, r7, r8, pc}
.Lns_f:
	movs	r0, #0
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ rec_append - r0 = slot index, r1 = state, r2 = version: one record appended as starter.s
@   append_record does it (CT_TAB from rec_scan; the caller has opened the gate with
@   flash_boot_gate for its slot, which admits the record pages):
@   cell = {0x4C52 << 16 | slot << 8 | state, version, highest sequence + 1, CRC-32 of the
@   12 bytes}; the page of the newest record (REC0 when there is no record: the starter
@   itself appends only after a record exists); the first cell above its last used cell;
@   page full -> the other page erased (flash_erase_page, which feeds the watchdog) and its
@   first cell taken; the four words through flash_word; the cell read back; on a
@   difference again from the page scan (three attempts, the failed cell stays used).
@   Returns r0 = 0 written and read back, 1 not.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	rec_append, %function
rec_append:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =OWN_CTL + CT_CELL
	movw	r3, #REC_TAG
	orr	r3, r1, r3, lsl #16
	orr	r3, r3, r0, lsl #8
	str	r3, [r4, #0]
	str	r2, [r4, #4]
	ldr	r3, =OWN_CTL + CT_TAB
	movs	r5, #0			@ highest sequence
	ldr	r6, =REC0		@ cell of the newest record
	movs	r7, #0
.Lra_high:
	add	r2, r3, r7, lsl #4
	ldr	r1, [r2, #0]
	cmp	r1, r5
	bls	.Lra_high_next
	mov	r5, r1
	ldr	r6, [r2, #12]
.Lra_high_next:
	adds	r7, r7, #1
	cmp	r7, #3
	blo	.Lra_high
	adds	r5, r5, #1
	str	r5, [r4, #8]
	mov	r0, r4
	movs	r1, #12
	bl	own_crc32
	str	r0, [r4, #12]
	bic	r6, r6, #0x7F0
	bic	r6, r6, #0xF		@ r6 = page base
	mov	r8, #3			@ attempts
.Lra_try:
	mov	r5, r6			@ r5 = first cell above the last used one
	mov	r7, r6			@ r7 = cell looked at
.Lra_scan:
	ldm	r7, {r0, r1, r2, r3}
	and	r0, r0, r1
	and	r2, r2, r3
	and	r0, r0, r2
	adds	r0, r0, #1		@ zero only when all four words are 0xFFFFFFFF
	beq	.Lra_free
	add	r5, r7, #16
.Lra_free:
	adds	r7, r7, #16
	add	r1, r6, #FLASH_PAGE
	cmp	r7, r1
	blo	.Lra_scan
	cmp	r5, r1
	blo	.Lra_write
	ldr	r1, =REC0		@ page full: the other page
	cmp	r6, r1
	ite	eq
	ldreq	r5, =REC1
	ldrne	r5, =REC0
	mov	r0, r5
	bl	flash_erase_page
.Lra_write:
	movs	r7, #0
.Lra_word:
	add	r0, r5, r7
	ldr	r1, [r4, r7]
	bl	flash_word
	cmp	r0, #FL_OK
	bne	.Lra_check
	adds	r7, r7, #4
	cmp	r7, #16
	blo	.Lra_word
.Lra_check:
	movs	r7, #0
.Lra_rb:
	ldr	r0, [r5, r7]
	ldr	r1, [r4, r7]
	cmp	r0, r1
	bne	.Lra_again
	adds	r7, r7, #4
	cmp	r7, #16
	blo	.Lra_rb
	movs	r0, #0
	pop	{r4, r5, r6, r7, r8, pc}
.Lra_again:
	subs	r8, r8, #1
	bne	.Lra_try
	movs	r0, #1
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ============================================================================
@ Tables and texts
@ ============================================================================
	.section .rodata.own.cmd,"a",%progbits
	.p2align 2

@ cmd_table - {cmd u16, 0 u16, handler}; ended by 0xFFFF.
cmd_table:
	.short	C_INFO, 0
	.word	h_info
	.short	C_PING, 0
	.word	h_ping
	.short	C_RESET, 0
	.word	h_reset
	.short	C_BATTERY, 0
	.word	h_battery
	.short	C_POWER_OFF, 0
	.word	h_power_off
	.short	C_FACTORY_MODE, 0
	.word	h_factory
	.short	C_STATE, 0
	.word	h_state
	.short	C_STREAM, 0
	.word	h_stream
	.short	C_SCREEN, 0
	.word	h_screen
	.short	C_KEY, 0
	.word	h_key
	.short	C_LCR_TABLES, 0
	.word	h_lcr_tables
	.short	C_LCR_SET, 0
	.word	h_lcr_set
	.short	C_MEASURE, 0
	.word	h_measure
	.short	C_MEASURE_STREAM, 0
	.word	h_mstream
	.short	C_COMPARE, 0
	.word	h_compare
	.short	C_COMPARE_SET, 0
	.word	h_compare_set
	.short	C_HOLD, 0
	.word	h_hold
	.short	C_CALIBRATE, 0
	.word	h_calibrate
	.short	C_TOL_SET, 0
	.word	h_tol_set
	.short	C_OCAL_INFO, 0
	.word	h_ocal_info
	.short	C_OCAL_READ, 0
	.word	h_ocal_read
	.short	C_OCAL_WRITE, 0
	.word	h_ocal_write
	.short	C_OCAL_ROLLBACK, 0
	.word	h_ocal_rollback
	.short	C_OCAL_LOCK, 0
	.word	h_ocal_lock
	.short	C_OCAL_RAW, 0
	.word	h_ocal_raw
	.short	C_OCAL_TRACE, 0
	.word	h_ocal_trace
	.short	C_MONITOR, 0
	.word	h_monitor
	.short	C_SET_TABLES, 0
	.word	h_set_tables
	.short	C_SET_SET, 0
	.word	h_set_set
	.short	C_SET_SAVE, 0
	.word	h_set_save
	.short	C_CAL_READ, 0
	.word	h_cal_read
	.short	C_RESTORE_DEF, 0
	.word	h_restore_def
	.short	C_SET_RESTORE_B, 0
	.word	h_restore_b
	.short	C_SET_ACCEPT_A, 0
	.word	h_accept_a
	.short	C_SET_WRITE_BLOCK, 0
	.word	h_write_block
	.short	C_SET_ACCEPT_B, 0
	.word	h_accept_b
	.short	C_SET_ACCEPT_DEF, 0
	.word	h_accept_def
	.short	C_SCREENSHOT, 0
	.word	h_screenshot
	.short	C_MEM_READ, 0
	.word	h_mem_read
	.short	C_UPDATE_MODE, 0
	.word	h_update_mode
	.short	C_BOOT_BEGIN, 0
	.word	h_boot_begin
	.short	C_BOOT_DATA, 0
	.word	h_boot_data
	.short	C_BOOT_END, 0
	.word	h_boot_end
	.short	C_BOOT_INSTALL, 0
	.word	h_boot_install
	.short	C_BOOT_STATUS, 0
	.word	h_boot_status
	.short	0xFFFF, 0

@ battery icon thresholds 3.4, 3.6, 3.8, 4.0 V (0x0800C724, signed compares of the bits); also
@ read by power.s batt_level
	.global	tab_batt
tab_batt:
	.word	0x4059999A, 0x40666666, 0x40733333, 0x40800000

@ MEM_READ ranges [first, end): flash, system memory, system configuration area and option
@ bytes (user manual 2721..2724, 2891..2893), main SRAM (the parity SRAM from 0x20020000 is
@ excluded, manual 3740)
mem_ranges:
	.word	0x08000000, 0x08080000
	.word	0x1FFF0000, 0x1FFF4000
	.word	0x1FFFF000, 0x1FFFF812
	.word	0x20000000, 0x20020000

@ display formatters by FK_* kind (FK_NONE has none): the wrappers of fmt.s, which the display
@ rows call too (S2.1 / S2.2 / S2.4: the host text equals the display text)
fmt_fn:
	.word	own_fmt_r, own_fmt_c, own_fmt_l, own_fmt_dq, own_fmt_th, 0
	.word	own_fmt_r
@ unit codes by kind: {first index, last index, added to the index, 0}: ohm 5..7 -> 1..3,
@ C 1..4 -> 4..7, L 3..5 -> 8..10, D / Q none, theta 1 -> 11 (the indices the formatters
@ store, 0x0800E028 / 0x0800DB24 / 0x0800DE2C / 0x0800DFC4)
fmt_units:
	.byte	5, 7, -4, 0
	.byte	1, 4, 3, 0
	.byte	3, 5, 5, 0
	.byte	1, 0, 0, 0
	.byte	1, 1, 10, 0
	.byte	1, 0, 0, 0
	.byte	5, 7, -4, 0

@ LCR_TABLES lists, 20 bytes each: {count, value type, name kind (0 own text, 1 table),
@ entry kind (0 own texts, 1 table)}, name (own text, or the English table entry), entries
@ (own list, or English pointer table), values (0: the index), unit text. English = row 1
@ of a per-language table (row 0 holds the same pointers in our build, lang.s). LCR_SET takes
@ the count and the values from here too (h_lcr_set).
	.p2align 2
lcr_lists:
	.byte	5, 0, 0, 1		@ 0 Func: names from 0x20000270 (row 1 of 0x20000258)
	.word	txt_func, T_FUNC + 24, 0, txt_empty
	.byte	5, 0, 0, 0		@ 1 secondary
	.word	txt_secondary, txt_sec_list, 0, txt_empty
	.byte	6, 1, 1, 0		@ 2 frequency: label 0x20000234 (row 1 of 0x20000224); index 5
					@ = 60 Hz (S2.12, appended: the hosts' 0..4 unchanged)
	.word	T_CURSOR + 16, txt_freq_list, tab_freq, txt_hz
	.byte	3, 2, 1, 0		@ 3 level
	.word	T_CURSOR + 20, txt_level_list, tab_level, txt_v
	.byte	2, 2, 1, 0		@ 4 bias
	.word	T_CURSOR + 24, txt_bias_list, tab_bias, txt_v
	.byte	5, 0, 1, 1		@ 5 range: names from 0x20000244 (one table)
	.word	T_CURSOR + 28, T_RANGE, 0, txt_ohm
	.byte	3, 0, 0, 0		@ 6 speed (names not established: digits)
	.word	txt_speed, txt_speed_list, 0, txt_empty
	.byte	3, 0, 0, 0		@ 7 circuit mode
	.word	txt_circuit, txt_circuit_list, 0, txt_empty

@ SETTINGS_TABLES / SETTINGS_SET, SET_ENTRY (28) bytes each: {kind (0 choices, 1 range),
@ choices, 0, 0}, address, min, max, step, name (English table entry), choice pointer table
@ (English row) or 0. English rows: menu labels 0x20000078 (row 1 of 0x20000054, vendor item
@ n at +4 n), sorting rows 0x20000130 (row 1 of 0x2000011C), off times 0x20000184 (row 1 of
@ 0x20000174), warn types 0x2000014C (row 1 of 0x20000144). The language (vendor item 1)
@ has no id: our build is English only (LANGUAGE_DESIGN.md).
	.p2align 2
set_tab:
	.byte	1, 0, 0, 0		@ 0 brightness: item 2, 10..100 step 10 (fn_0800f5e8)
	.word	V_BRIGHT, 10, 100, 10, T_MENU + 36 + 8, 0
	.byte	1, 0, 0, 0		@ 1 volume: item 3
	.word	V_VOLUME, 10, 100, 10, T_MENU + 36 + 12, 0
	.byte	0, 4, 0, 0		@ 2 off time: item 4, 0..3
	.word	V_OFFTIME, 0, 3, 1, T_MENU + 36 + 16, T_OFFTIME + 16
	.byte	0, 2, 0, 0		@ 3 warn type: sorting row 2
	.word	V_WARN_TYPE, 0, 1, 1, T_SORTROW + 20 + 8, T_WARNTYPE + 8
	.byte	1, 0, 0, 0		@ 4 warn sound: row 3, 0 / 1 (pictures, no text)
	.word	V_WARN_SOUND, 0, 1, 1, T_SORTROW + 20 + 12, 0
	.byte	1, 0, 0, 0		@ 5 warn LED: row 4
	.word	V_WARN_LED, 0, 1, 1, T_SORTROW + 20 + 16, 0

@ firmware version text of INFO (16 bytes)
fw_version:
	.ascii	"LC1020E V1.1 OWN"

@ own texts (where the vendor shows pictures or nothing)
txt_empty:
	.asciz	""
txt_func:
	.asciz	"Func"
txt_secondary:
	.asciz	"Secondary"
txt_sec_list:
	.asciz	"R"
	.asciz	"X"
	.asciz	"D"
	.asciz	"Q"
	.asciz	"theta"
txt_freq_list:
	.asciz	"100Hz"
	.asciz	"120Hz"
	.asciz	"1kHz"
	.asciz	"10kHz"
	.asciz	"100kHz"
	.asciz	"60Hz"
txt_level_list:
	.asciz	"0.1V"
	.asciz	"0.3V"
	.asciz	"0.6V"
txt_bias_list:
	.asciz	"0V"
	.asciz	"0.5V"
txt_speed:
	.asciz	"Speed"
txt_speed_list:
	.asciz	"0"
	.asciz	"1"
	.asciz	"2"
txt_circuit:
	.asciz	"Circuit"
txt_circuit_list:
	.asciz	"AUTO"
	.asciz	"SERIES"
	.asciz	"PARALLEL"
txt_hz:
	.asciz	"Hz"
txt_v:
	.asciz	"V"
txt_ohm:
	.asciz	"ohm"
