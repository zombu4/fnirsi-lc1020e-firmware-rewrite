@ ctl.s - control core of our build: start-up, the main-loop step, frames, key injection with
@ its refusal and guard, events, streams, the command state machine and the BOOT_* page erase.
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ Specification: USB_CONTROL_DESIGN.md revision 4 (section 9 decisions first), the 2C53T frame
@ format (PROTOCOL.md of the 2C53T rewrite). The commands themselves are in own/cmd.s.
@
@ Hooks (each a same-size change inside .ifdef OWN in the ported source):
@ - own_start replaces the bl fn_0801031c at 0x08028018 (system_40.s fn_08027ff4, the print of
@   "\n\nstart\n" right after the clock set-up 0x08008504, the 1000-count wait 0x08011C68 and the
@   power latch 0x08028012, before the zero fill and the load 0x08028030).
@ - ctl_loop replaces the bl fn_08009400 at 0x080281D0 (main loop, after the watchdog feed
@   0x08010174 and the timer walk 0x08027830, before the measurement 0x0800A068).
@ - own_restore_guard replaces the bl fn_0800b4c8 at 0x08009A68 (menu restore of defaults).
@ - own_pa8_level replaces the bl fn_08008350 at 0x08008210 (periph_34.s fn_08008200: PA8
@   driven low at the start; kept high after a soft restart).
@
@ One pass of ctl_loop (design section 3; every step bounded, none waits):
@   on the first pass only usb_start, then ev_prime (sets CF_PRIMED); every pass save_resume (save.s), the pending action (restart / power-off after an answer), the
@   USB-powered power-off check, one step of the calibration sweep (cal_step, own/cal.s; before
@   the job, so OP_WAITCAL sees its finish in the same pass), (1) one step of the running job, the automatic power-off step
@   (pwr_step, own/power.s: Off Time, low-voltage countdown), (2) a pending key injection is
@   posted, (3) the guard flag is set when the event in the slot is the injected one, 0x08009400
@   runs, the flag is cleared; or, in a pass with no event in the slot and no key down, a
@   pending direct change runs instead (dset.s ds_run, DIRECT_SET_DESIGN.md revision 2: 0x08009400
@   returns at once with the slot at 0), (4) events, the screenshot step, the streams, (5) received bytes
@   are parsed (one request per pass, none while an answer, a job or an action is pending or a
@   screenshot runs), (6) the pending answer is queued.
@
@ Frames (all numbers little-endian): sync 0xA5, length (u16: seq .. payload, 3..515), seq,
@ type (1 request, 2 answer, 3 stream, 4 event), cmd, payload (<= 512), CRC-16/CCITT-FALSE
@ (polynomial 0x1021, initial 0xFFFF) over length .. payload. The first payload byte of an
@ answer is its status. A frame is put into the TX ring whole or not at all (usb_tx_free first;
@ only the USB interrupt takes bytes out, so the free room can only grow in between).
@
@ Key injection (design 4.3): a short press posts code 1 with the mask into the event slot
@ 0x20001192 / 0x20001194 with PRIMASK set around the check and both stores, only while the
@ slot is empty and no physical key is down (0x20000008 = 0). A hold of n ms posts nothing
@ before 1000 ms (0x080094A0 posts 0xFE only from a tick counter above 99), then one 0xFE per
@ pass while the slot is empty, then 0xFF with the mask; a hold below 1000 ms is a short press
@ at its end, as the scan makes it. A physical key during a hold ends it with 0xFF. Every
@ injected key goes through key_refused (in cmd.s callers' jobs) unless the job's own path
@ runs with the guard off (CALIBRATE, POWER_OFF).
@ Guard: own_injected (own.inc, word 0 of our area) is 1 only while 0x08009400 handles the
@ injected event; own_save (save.s) and own_restore_guard return without acting then, and the
@ job's answer gets status 6.
@
@ Events (type 4, only while DTR is set): 0x90 KEY (mask u16, code u8, source u8: 0 physical,
@ 1 injected), 0x91 SCREEN_CHANGED (screen u8, previous u8), 0x93 SETTING_CHANGED (id u16 =
@ address - 0x2000057C, value u32; id 0xFFFE: words changed in the calibration tables, value =
@ their number), 0x94 POWERED_OFF (no data), 0x95 MEASURE_DONE (result number u32), 0x96
@ SAVE_RESULT (own_save_status u32, own_save_flags u32), 0x97 CALIBRATION (status u8, step u8,
@ type u8). While a screenshot runs they wait in a queue of 16; a frame without room is dropped
@ and counted (STATE).
@
@ Never-brick: this file contains no access to the flash controller. Flash is written only
@ through save.s (own_save, the recovery functions, flash_erase_page, flash_word with the gate
@ flash_boot_gate); the BOOT_* writer opens the gate for the free slot around each call only.
@
@ RAM: the area O_CTL of own.inc (offsets in own/ctl.inc); no section of RAM is defined.
@ Calling convention of every function: AAPCS; r0..r3, r12, the flags and s0..s15 clobbered,
@ r4..r11 kept.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"
	.include "own/ctl.inc"

	.section .text.own.ctl,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ now - r0 = GUI tick word 0x20000480 (+10 per SysTick; ms while SysTick runs at 10 ms).
@   One aligned word load (single-copy atomic). Uses r0 only.
@ since - r0 = earlier tick -> r0 = now - r0. Uses r0, r1.
@ ----------------------------------------------------------------------------
	.global	now
	.thumb_func
	.type	now, %function
now:
	ldr	r0, =V_TICK
	ldr	r0, [r0]
	bx	lr

	.global	since
	.thumb_func
	.type	since, %function
since:
	ldr	r1, =V_TICK
	ldr	r1, [r1]
	subs	r0, r1, r0
	bx	lr

@ ----------------------------------------------------------------------------
@ own_pa8_level - replaces bl fn_08008350 at 0x08008210 (fn_08008200, the first call of main
@   0x08027FF4: r0 = GPIOA, r1 = 0x100, r2 = 0, PA8 output low). V1.1 keeps PA8, the power
@   latch, low from here until main sets it high after 0x08011C68(1000) (NOTES "Power latch
@   PA8"): at a power-on the held power key keeps the meter on meanwhile, after a soft restart
@   nothing does (a released latch switches the meter off, NOTES 2026-11-20). So when the
@   hand-over word 0x2001FFF8 (written by the slot, version 2, read here before own_start
@   clears it) has the tag 0x534C and bit 9 (HO_SOFT: the slot found UPDT / RSTR), r2 = 1:
@   fn_08008350 writes the pin mask to PBSC and PA8 stays high. The same when the system clock
@   is not the PLL (RCC_CFG SCLKSTS: the crystal did not start, VENDOR_FIXES_DESIGN.md F4): the
@   start-up then runs on the 8 MHz HSI up to xtal_fault, and the key need not be held through
@   it. Otherwise the call is the original one. Tail call; uses r2, r3, r12 before it.
@ ----------------------------------------------------------------------------
	.global	own_pa8_level
	.thumb_func
	.type	own_pa8_level, %function
own_pa8_level:
	ldr	r3, =RCC_CFG		@ crystal failure (system clock not the PLL, xtal.s): PA8
	ldr	r3, [r3]		@ high at once, the meter stays on through the slow start-up
	and	r3, r3, #RCC_SCLKSTS	@ up to xtal_fault without the key held
	cmp	r3, #RCC_SCLK_PLL
	it	ne
	movne	r2, #1
	ldr	r3, =HANDOVER_WORD
	ldr	r3, [r3]
	movw	r12, #HANDOVER_TAG >> 16
	cmp	r12, r3, lsr #16
	bne	.Lpl_call		@ no hand-over of a slot
	tst	r3, #HO_SOFT
	it	ne
	movne	r2, #1			@ soft restart: PA8 output high (PBSC)
.Lpl_call:
	b	fn_08008350

@ ----------------------------------------------------------------------------
@ own_start - replaces bl fn_0801031c at 0x08028018 (r0 = the "\n\nstart\n" text).
@   Runs the original call, then: own RAM 0x20018000..0x2001DFFF cleared (every module's
@   area: own_load at 0x08028030 then writes save.s's words); the hand-over word 0x2001FFF8
@   read and cleared (tag 0x534C in bits 31..16, slot index 0..2 in bits 7..0, bit 8 = the
@   watchdog runs, started by the slot for a trial or left running by soft_restart: then the
@   IWDG is fed here, before the application's own start 0x08010178; bit 9 = soft restart,
@   read by own_pa8_level); the result word 0x2001FFFC read and cleared (tag 0x5552, result byte and its
@   complement); the request word 0x2001FFF4 cleared; ocal_load (ocal.s). USB is started by ctl_loop's first
@   pass, not here: the vendor start-up after this call took 2 s on a meter, and a port
@   present before requests are served leaves a host's first request unanswered. Last: when
@   the system clock is not the PLL (the crystal did not start), xtal_fault (xtal.s, F4), which
@   does not return. (The per-language text
@   tables need no step here: their row 0 equals row 1 in the initial RAM image of our
@   build, src/rodata_04.s ram_image.)
@ ----------------------------------------------------------------------------
	.global	own_start
	.thumb_func
	.type	own_start, %function
own_start:
	push	{r4, lr}
	bl	fn_0801031c		@ the original call
	ldr	r0, =OWN_RAM
	movs	r1, #0
	movw	r2, #OWN_RAM_SIZE
.Lst_clear:
	str	r1, [r0], #4
	subs	r2, r2, #4
	bne	.Lst_clear
	ldr	r4, =OWN_CTL
	ldr	r0, =HANDOVER_WORD
	ldr	r1, [r0]
	str	r1, [r4, #CT_HAND_WORD]
	movs	r2, #0
	str	r2, [r0]		@ read once: a later start through a version-1 slot finds 0
	movs	r2, #0xFF		@ r2 = running slot, unknown
	lsrs	r3, r1, #16
	movw	r12, #HANDOVER_TAG >> 16
	cmp	r3, r12
	bne	.Lst_slot
	uxtb	r3, r1
	cmp	r3, #2
	bhi	.Lst_slot
	mov	r2, r3
	tst	r1, #HO_WDG
	beq	.Lst_slot
	bl	own_feed		@ trial start: the slot's watchdog runs (uses r0, r1)
.Lst_slot:
	str	r2, [r4, #CT_HAND_SLOT]
	bl	ocal_load		@ the own calibration record (OWN_CAL_DESIGN.md 1.3): flash reads
					@ only, writes OWN_OCAL only; before the first own_measure call
	ldr	r0, =RESULT_WORD
	ldr	r1, [r0]
	movs	r2, #0
	str	r2, [r0]
	lsrs	r3, r1, #16
	movw	r12, #RESULT_TAG
	cmp	r3, r12
	bne	.Lst_result
	ubfx	r3, r1, #8, #8		@ result
	uxtb	r12, r1			@ its complement
	eor	r12, r12, r3
	cmp	r12, #0xFF
	bne	.Lst_result
	mov	r2, r3
.Lst_result:
	str	r2, [r4, #CT_RESULT]
	ldr	r0, =REQ_WORD
	movs	r1, #0
	str	r1, [r0]
	mvn	r0, #0
	str	r0, [r4, #CT_W_NEXT]	@ no SETTINGS_WRITE_BLOCK transfer
	ldr	r0, =RCC_CFG
	ldr	r0, [r0]
	and	r0, r0, #RCC_SCLKSTS
	cmp	r0, #RCC_SCLK_PLL
	bne.w	xtal_fault		@ the crystal did not start: the fault screen (xtal.s), no return
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ own_restore_guard - replaces bl fn_0800b4c8 at 0x08009A68 (menu restore of the defaults;
@   r0 = mode 0, or 1 in factory mode). While own_injected is set the defaults routine is not
@   called (guard, design 4.3) and the job is marked (status 6); otherwise tail call with r0.
@ ----------------------------------------------------------------------------
	.global	own_restore_guard
	.thumb_func
	.type	own_restore_guard, %function
own_restore_guard:
	ldr	r1, =own_injected
	ldr	r2, [r1]
	cmp	r2, #0
	bne	.Lrg_refuse
	b.w	fn_0800b4c8
.Lrg_refuse:
	ldr	r1, =OWN_CTL
	movs	r2, #1
	str	r2, [r1, #CT_J_GUARD]
	bx	lr

	.ltorg

@ ----------------------------------------------------------------------------
@ ctl_loop - replaces bl fn_08009400 at 0x080281D0; one pass as in the file header.
@ ----------------------------------------------------------------------------
	.global	ctl_loop
	.thumb_func
	.type	ctl_loop, %function
ctl_loop:
	push	{r4, lr}
	ldr	r4, =OWN_CTL
	ldr	r0, [r4, #CT_FLAGS]
	tst	r0, #CF_PRIMED
	bne	.Lcl_run
	bl	usb_start		@ first pass: the host sees the device only from here, when
					@ requests are served (the start-up before took 2 s on a meter
					@ with the port present and silent, NOTES "USB start")
	bl	ev_prime		@ first pass: previous values = current values; sets CF_PRIMED
.Lcl_run:
	bl	save_resume		@ rewrite of an interrupted copy A (save.s)
	bl	act_step
	bl	off_step
	bl	cal_step		@ the calibration sweep (cal.s, MEASUREMENT_FIX_DESIGN stage 3)
	bl	ocal_step		@ the OCAL_LOCK release rules (ocal.s, OWN_CAL_DESIGN.md 2.2)
	bl	job_step		@ (1)
	bl	pwr_step		@ Off Time and low-voltage power-off (power.s); here, before
					@ inj_post, the event slot holds only events of the key scan
	bl	inj_post		@ (2)
	bl	key_step		@ (3)
	bl	ev_detect		@ (4)
	bl	scr_step
	bl	stream_step
	bl	own_cmp_step		@ the compare beeper / LED steps (cmp.s, S2.8)
	bl	rx_poll			@ (5)
	bl	ans_step		@ (6)
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ crc16_update - r0 = CRC register, r1 = address, r2 = byte count (0 allowed)
@   -> r0 = new register (CRC-16/CCITT-FALSE: byte into bits 15..8, eight shifts left, XOR
@   0x1021 when bit 16 comes out). Uses r1..r3, r12.
@ ----------------------------------------------------------------------------
	.global	crc16_update
	.thumb_func
	.type	crc16_update, %function
crc16_update:
	cmp	r2, #0
	beq	.Lcr_out
	movw	r12, #CRC16_POLY
	movt	r12, #1			@ r12 = 0x11021: clears bit 16 and applies the polynomial
.Lcr_byte:
	ldrb	r3, [r1], #1
	eor	r0, r0, r3, lsl #8
	movs	r3, #8
.Lcr_bit:
	lsls	r0, r0, #1
	tst	r0, #0x10000
	it	ne
	eorne	r0, r0, r12
	subs	r3, r3, #1
	bne	.Lcr_bit
	subs	r2, r2, #1
	bne	.Lcr_byte
.Lcr_out:
	bx	lr

@ ----------------------------------------------------------------------------
@ frame_out - one frame into the TX ring, whole or not at all.
@   r0 = type | cmd << 8 | seq << 16, r1 = first part of the payload, r2 = its length,
@   r3 = second part, [sp] = its length (0 allowed for both parts).
@   Returns r0 = 0 queued, 1 nothing queued (payload above 512 bytes or no room).
@   The header is built on the stack: no buffer of ours is held across the call, so the
@   function may run inside a GUI flush (ctl_stream_frame) while ctl_loop is in step 3.
@   Stack: 32 bytes plus usb_tx_free / usb_tx_put.
@ ----------------------------------------------------------------------------
	.global	frame_out
	.thumb_func
	.type	frame_out, %function
frame_out:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r8, [sp, #24]		@ r8 = length of the second part
	mov	r4, r1			@ r4, r5 = first part
	mov	r5, r2
	mov	r6, r3			@ r6, r8 = second part
	adds	r7, r5, r8		@ r7 = payload length
	cmp	r7, #FR_MAX_PAYLOAD
	bhi	.Lfo_no
	sub	sp, #8			@ [sp] sync, length, seq, type, cmd; [sp + 6] CRC
	movs	r1, #FR_SYNC
	strb	r1, [sp, #0]
	adds	r1, r7, #3
	strb	r1, [sp, #1]
	lsrs	r1, r1, #8
	strb	r1, [sp, #2]
	lsrs	r1, r0, #16
	strb	r1, [sp, #3]		@ seq
	strb	r0, [sp, #4]		@ type
	lsrs	r1, r0, #8
	strb	r1, [sp, #5]		@ cmd
	bl	usb_tx_free
	adds	r1, r7, #8		@ frame size: 6 header bytes, payload, 2 CRC bytes
	cmp	r0, r1
	blo	.Lfo_room
	movw	r0, #CRC16_INIT
	add	r1, sp, #1
	movs	r2, #5
	bl	crc16_update		@ length, seq, type, cmd
	mov	r1, r4
	mov	r2, r5
	bl	crc16_update
	mov	r1, r6
	mov	r2, r8
	bl	crc16_update
	strb	r0, [sp, #6]
	lsrs	r0, r0, #8
	strb	r0, [sp, #7]
	mov	r0, sp
	movs	r1, #6
	bl	usb_tx_put
	cmp	r5, #0
	beq	.Lfo_second
	mov	r0, r4
	mov	r1, r5
	bl	usb_tx_put
.Lfo_second:
	cmp	r8, #0
	beq	.Lfo_crc
	mov	r0, r6
	mov	r1, r8
	bl	usb_tx_put
.Lfo_crc:
	add	r0, sp, #6
	movs	r1, #2
	bl	usb_tx_put
	add	sp, #8
	movs	r0, #0
	pop	{r4, r5, r6, r7, r8, pc}
.Lfo_room:
	add	sp, #8
.Lfo_no:
	movs	r0, #1
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ next_seq - r0 = running seq of stream / event frames (low byte used), counter + 1.
@   Uses r0..r2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	next_seq, %function
next_seq:
	ldr	r1, =OWN_CTL
	ldr	r0, [r1, #CT_TX_SEQ]
	adds	r2, r0, #1
	str	r2, [r1, #CT_TX_SEQ]
	uxtb	r0, r0
	bx	lr

@ ----------------------------------------------------------------------------
@ ctl_stream_frame - for screen.s: one stream frame (type 3) with the next running seq.
@   r0 = cmd, r1 = head, r2 = head length, r3 = data, [sp] = data length (0 allowed).
@   Returns r0 = 0 queued, nonzero nothing queued (no room). Not affected by the screenshot
@   reservation; re-entrant with respect to ctl_loop (see frame_out).
@ ----------------------------------------------------------------------------
	.global	ctl_stream_frame
	.thumb_func
	.type	ctl_stream_frame, %function
ctl_stream_frame:
	push	{r4, r5, r6, r7, lr}
	sub	sp, #12
	ldr	r4, [sp, #32]		@ data length (the caller's [sp])
	mov	r5, r1
	mov	r6, r2
	mov	r7, r3
	lsls	r3, r0, #8		@ r3 = cmd << 8
	bl	next_seq
	orr	r0, r3, r0, lsl #16
	orr	r0, r0, #FR_STREAM
	str	r4, [sp]
	mov	r1, r5
	mov	r2, r6
	mov	r3, r7
	bl	frame_out
	add	sp, #12
	pop	{r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ out_counted - r0 = type (FR_STREAM / FR_EVENT), r1 = cmd, r2 = payload, r3 = length:
@   one frame with the next running seq; a frame without room is counted in CT_DROPPED.
@   Uses r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	out_counted, %function
out_counted:
	push	{r4, r5, r6, r7, lr}
	sub	sp, #12
	mov	r4, r0
	mov	r5, r1
	mov	r6, r2
	mov	r7, r3
	bl	next_seq
	lsls	r0, r0, #16
	orr	r0, r0, r5, lsl #8
	orr	r0, r0, r4
	movs	r3, #0
	str	r3, [sp]
	mov	r1, r6
	mov	r2, r7
	bl	frame_out
	cmp	r0, #0
	beq	.Loc_out
	ldr	r1, =OWN_CTL
	ldr	r0, [r1, #CT_DROPPED]
	adds	r0, r0, #1
	str	r0, [r1, #CT_DROPPED]
.Loc_out:
	add	sp, #12
	pop	{r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ ans_set - r0 = status, r1 = length of the answer data at CT_ANSB + 1: the answer becomes
@   pending (queued by ans_step). Uses r2.
@ ----------------------------------------------------------------------------
	.global	ans_set
	.thumb_func
	.type	ans_set, %function
ans_set:
	ldr	r2, =OWN_CTL
	strb	r0, [r2, #CT_ANSB]
	adds	r1, r1, #1
	str	r1, [r2, #CT_ANS_LEN]
	bx	lr

@ ----------------------------------------------------------------------------
@ ans_step - step (6): the pending answer is queued when the whole frame fits; it stays
@   pending otherwise (no waiting inside the pass).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ans_step, %function
ans_step:
	push	{r4, lr}
	sub	sp, #8
	ldr	r4, =OWN_CTL
	ldr	r2, [r4, #CT_ANS_LEN]
	cmp	r2, #0
	beq	.Las_out
	ldr	r0, [r4, #CT_REQ_SEQ]
	uxtb	r0, r0
	lsls	r0, r0, #16
	ldr	r1, [r4, #CT_REQ_CMD]
	uxtb	r1, r1
	orr	r0, r0, r1, lsl #8
	orr	r0, r0, #FR_ANSWER
	addw	r1, r4, #CT_ANSB
	movs	r3, #0
	str	r3, [sp]
	bl	frame_out
	cmp	r0, #0
	bne	.Las_out
	str	r0, [r4, #CT_ANS_LEN]	@ sent
	bl	now
	str	r0, [r4, #CT_ANS_T]
	ldr	r0, [r4, #CT_FLAGS]
	orr	r0, r0, #CF_ANS_LEFT
	str	r0, [r4, #CT_FLAGS]
.Las_out:
	add	sp, #8
	pop	{r4, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ act_set - r0 = ACT_*: the action runs after the answer has left (act_step).
@   Uses r0..r2.
@ ----------------------------------------------------------------------------
	.global	act_set
	.thumb_func
	.type	act_set, %function
act_set:
	ldr	r2, =OWN_CTL
	str	r0, [r2, #CT_ACT]
	ldr	r0, [r2, #CT_FLAGS]
	bic	r0, r0, #CF_ANS_LEFT
	str	r0, [r2, #CT_FLAGS]
	ldr	r0, =V_TICK
	ldr	r0, [r0]
	str	r0, [r2, #CT_ACT_T0]
	bx	lr

@ ----------------------------------------------------------------------------
@ soft_restart - restart through the starter without a system reset (USB_CONTROL_DESIGN.md
@   6b: an AIRCR reset releases the power latch PA8 and switches the meter off, NOTES
@   2026-11-20). r0 = request word value (REQ_RESTART or REQ_MAGIC). Called in thread mode
@   from the main loop. Never returns. In this order:
@   - PRIMASK set; REQ_WORD = r0 (the slot, version 2, clears it and feeds the IWDG);
@   - only while the USB clock is on (RCC_APB1PCLKEN USBEN; usb_start sets it only with the
@     PLL running): D+ pull-up off (bit 28 of 0x40001820 cleared by read-modify-write), USB_CTRL
@     = FRST | PD (the host sees the device leave), USBEN cleared (its reset value: the
@     next usb_start or the slot's fn_080021dc sets USBPRES before USBEN again);
@   - NVIC: every interrupt disabled (ICER0..2) and its pending bit cleared (ICPR0..2);
@     SysTick CTRL = 0; the SysTick and PendSV pending bits cleared (ICSR);
@   - CHEN cleared on the five DMA channels the application enables (own.inc DMA1_CH1 ..);
@   - flash controller locked (fn_08008db0, the application's own LOCK routine, so this file
@     still addresses no flash register; no operation runs here: save.s waits for BUSY = 0
@     before it returns);
@   - the system clock stays the PLL (144 MHz, LATENCY 4): the starter's image CRC (about
@     913000 instructions for a 20 KiB slot, tests/test_own_control.py k09) runs fast
@     enough for the IWDG period. The slot (version 2) switches to HSI and waits for
@     SCLKSTS before its own clock set-up (bootloader/src/board_02.s fn_08002598, slot
@     build: its stock sequence clears PLLEN without a wait, manual 6.3.2 / 6.2.7);
@   - BASEPRI = 0, CONTROL = 0 (MSP, no FP context), as after a reset;
@   - the IWDG fed (it runs in the application from 0x08010178 on), so the starter and the
@     slot start with a whole period;
@   - VTOR = 0, MSP = word 0x00000000, branch to word 0x00000004: the boot space, where the
@     meter maps main flash (the starter at 0x08000000 runs at power-on from there), so these
@     are the starter's stack pointer and reset entry, read as a reset reads them; PRIMASK
@     stays set (the starter sets it first anyway).
@   GPIOA is not written: PA8 stays driven high; the starter writes it high again.
@ ----------------------------------------------------------------------------
	.global	soft_restart
	.thumb_func
	.type	soft_restart, %function
soft_restart:
	cpsid	i
	ldr	r1, =REQ_WORD
	str	r0, [r1]
	ldr	r2, =RCC_APB1PCLKEN
	ldr	r3, [r2]
	tst	r3, #RCC_USBEN
	beq	.Lsr_nousb
	ldr	r0, =USB_PULLUP
	ldr	r1, [r0]
	bic	r1, r1, #USB_PULLUP_BIT
	str	r1, [r0]		@ D+ pull-up off
	ldr	r0, =USB_BASE
	movs	r1, #(USB_CTRL_FRST | USB_CTRL_PD)
	str	r1, [r0, #USB_CTRL]	@ USB core in reset and powered down
	bic	r3, r3, #RCC_USBEN
	str	r3, [r2]		@ USB clock off
.Lsr_nousb:
	mvn	r1, #0
	ldr	r0, =NVIC_ICER0
	str	r1, [r0]
	str	r1, [r0, #4]
	str	r1, [r0, #8]
	ldr	r0, =NVIC_ICPR0
	str	r1, [r0]
	str	r1, [r0, #4]
	str	r1, [r0, #8]
	ldr	r0, =SYST_CSR
	movs	r1, #0
	str	r1, [r0]		@ SysTick stopped
	ldr	r0, =SCB_ICSR
	mov	r1, #ICSR_PEND_CLR
	str	r1, [r0]
	adr	r0, .Lsr_dma
	movs	r2, #5
.Lsr_dma_next:
	ldr	r1, [r0], #4
	ldr	r3, [r1]
	bic	r3, r3, #DMA_CHEN
	str	r3, [r1]		@ channel stopped
	subs	r2, r2, #1
	bne	.Lsr_dma_next
	bl	fn_08008db0		@ flash locked (FLASH_CTRL LOCK, read-modify-write)
	movs	r0, #0
	msr	basepri, r0
	msr	control, r0
	isb
	ldr	r0, =IWDG_KEY
	movw	r1, #IWDG_FEED
	str	r1, [r0]
	ldr	r0, =SCB_VTOR
	movs	r1, #BOOT_SPACE
	str	r1, [r0]		@ VTOR = 0, its value after a reset
	dsb
	isb
	ldr	r0, [r1, #0]		@ the starter's stack pointer
	ldr	r2, [r1, #4]		@ its reset entry
	msr	msp, r0
	bx	r2

	.p2align 2
.Lsr_dma:
	.word	DMA1_CH1, DMA1_CH8, DMA2_CH3, DMA2_CH5, DMA2_CH8

@ ----------------------------------------------------------------------------
@ act_step - the pending action: once the answer has left and the TX ring is empty, or
@   ACT_WAIT_MS after the answer left, or ACT_LIMIT_MS after the action was set (USB gone).
@   ACT_RESET: soft_restart with REQ_RESTART. ACT_UPDATE: soft_restart with REQ_MAGIC (the
@   slot enters update mode).
@   ACT_POWER_OFF: the meter's own path, event 0xFE with mask 1 posted with the guard off
@   (0x08009452: save, beep, 0x0800B274 PA8 low).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	act_step, %function
act_step:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_CTL
	ldr	r5, [r4, #CT_ACT]
	cmp	r5, #ACT_NONE
	beq	.Lat_out
	ldr	r0, [r4, #CT_ACT_T0]
	bl	since
	movw	r1, #ACT_LIMIT_MS
	cmp	r0, r1
	bhs	.Lat_do
	ldr	r0, [r4, #CT_ANS_LEN]
	cmp	r0, #0
	bne	.Lat_out		@ the answer is still pending
	ldr	r0, [r4, #CT_FLAGS]
	tst	r0, #CF_ANS_LEFT
	beq	.Lat_out
	bl	usb_tx_empty
	cmp	r0, #0
	bne	.Lat_do
	ldr	r0, [r4, #CT_ANS_T]
	bl	since
	cmp	r0, #ACT_WAIT_MS
	blo	.Lat_out
.Lat_do:
	cmp	r5, #ACT_POWER_OFF
	beq	.Lat_power
	ldr	r0, =REQ_RESTART
	cmp	r5, #ACT_UPDATE
	it	eq
	ldreq	r0, =REQ_MAGIC
	b	soft_restart		@ never returns
.Lat_power:
	movs	r0, #ACT_NONE
	str	r0, [r4, #CT_ACT]
	bl	power_path
.Lat_out:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ power_path - starts the meter's own power-off path: the injection of event 0xFE with mask 1,
@   guard off (IS_POWER: inj_post posts it once the slot is empty and no physical key is down;
@   0x08009452: save through own_save, beep, 0x0800B274 PA8 low; key_step notes it and
@   off_step enters the powered-off mode when the meter still runs, USB power). Replaces any
@   injection not yet started. Used by act_step (POWER_OFF) and power.s pwr_step. Uses r0..r3.
@ ----------------------------------------------------------------------------
	.global	power_path
	.thumb_func
	.type	power_path, %function
power_path:
	push	{r4, lr}
	movs	r0, #KEY_POWER
	movs	r1, #0
	movs	r2, #1			@ guard off
	bl	inj_start
	ldr	r3, =OWN_CTL
	movs	r0, #IS_POWER
	str	r0, [r3, #CT_I_STATE]
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ off_step - the meter's power-off path ran (key_step saw event 0xFE, mask 1, 0x20001190 =
@   0) and the meter still runs OFF_WAIT_MS later (powered through USB): powered-off mode
@   (CF_OFF): backlight off (fn_08009e60(0), as 0x0800B274 ends), keys ignored except the
@   power key, which restarts the meter (key_step, soft_restart); event POWERED_OFF.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	off_step, %function
off_step:
	push	{r4, lr}
	ldr	r4, =OWN_CTL
	ldr	r0, [r4, #CT_FLAGS]
	tst	r0, #CF_OFF_WAIT
	beq	.Lof_out
	tst	r0, #CF_OFF
	bne	.Lof_out
	ldr	r0, [r4, #CT_OFF_T]
	bl	since
	movw	r1, #OFF_WAIT_MS
	cmp	r0, r1
	blo	.Lof_out
	ldr	r0, [r4, #CT_FLAGS]
	bic	r0, r0, #CF_OFF_WAIT
	orr	r0, r0, #CF_OFF
	str	r0, [r4, #CT_FLAGS]
	movs	r0, #0
	bl	fn_08009e60		@ backlight off
	movs	r0, #E_POWERED_OFF
	movs	r1, #0
	movs	r2, #0
	bl	ev_send
.Lof_out:
	pop	{r4, pc}

	.ltorg

@ ============================================================================
@ Key injection
@ ============================================================================

@ ----------------------------------------------------------------------------
@ inj_start - r0 = key mask, r1 = hold in ms (0 = short press), r2 = 1: guard off.
@   Uses r0..r3.
@ ----------------------------------------------------------------------------
	.global	inj_start
	.thumb_func
	.type	inj_start, %function
inj_start:
	ldr	r3, =OWN_CTL
	str	r0, [r3, #CT_I_MASK]
	str	r1, [r3, #CT_I_HOLD]
	str	r2, [r3, #CT_I_GOFF]
	movs	r0, #0
	str	r0, [r3, #CT_I_RESULT]
	str	r0, [r3, #CT_I_POSTED]
	str	r0, [r3, #CT_I_FECNT]
	ldr	r0, =V_TICK
	ldr	r0, [r0]
	str	r0, [r3, #CT_I_T0]
	movs	r0, #IS_SHORT
	cmp	r1, #0
	it	ne
	movne	r0, #IS_HOLD
	str	r0, [r3, #CT_I_STATE]
	bx	lr

@ ----------------------------------------------------------------------------
@ post_try - r0 = event code, r1 = 1: only while no physical key is down.
@   With PRIMASK set: when the slot 0x20001192 is empty (and, with r1 = 1, 0x20000008 is 0)
@   stores the injected mask to 0x20001194, then the code to 0x20001192, and notes the code
@   in CT_I_POSTED. PRIMASK is restored. Returns r0 = 1 posted, 0 not. Uses r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	post_try, %function
post_try:
	ldr	r2, =V_KEY_CODE
	ldr	r3, =OWN_CTL
	mrs	r12, PRIMASK
	cpsid	i
	push	{r4}
	ldrh	r4, [r2, #0]
	cmp	r4, #0
	bne	.Lpt_no
	cmp	r1, #0
	beq	.Lpt_post
	ldr	r4, =V_KEYS_DOWN
	ldrh	r4, [r4]
	cmp	r4, #0
	bne	.Lpt_no
.Lpt_post:
	ldr	r4, [r3, #CT_I_MASK]
	strh	r4, [r2, #2]		@ mask to 0x20001194
	strh	r0, [r2, #0]		@ then the code to 0x20001192
	str	r0, [r3, #CT_I_POSTED]
	pop	{r4}
	msr	PRIMASK, r12
	movs	r0, #1
	bx	lr
.Lpt_no:
	pop	{r4}
	msr	PRIMASK, r12
	movs	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ inj_post - step (2): one action of the injection by its state.
@   IS_SHORT: code 1 (slot empty, no physical key) -> IS_WAIT.
@   IS_HOLD: a physical key down ends it (result 1); at the hold time below HOLD_FE_MS it
@     becomes IS_SHORT; from HOLD_FE_MS on IS_HOLD_FE.
@   IS_HOLD_FE: a physical key down -> IS_RELEASE (result 1); the hold time reached after at
@     least one consumed 0xFE -> IS_RELEASE; else 0xFE when the slot is empty.
@   IS_RELEASE: 0xFF (slot empty; a physical key may be down) -> IS_WAIT.
@   IS_POWER: 0xFE with mask 1 (slot empty, no physical key) -> IS_WAIT.
@   In powered-off mode an injection ends at once (result 1).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	inj_post, %function
inj_post:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_CTL
	ldr	r5, [r4, #CT_I_STATE]
	cmp	r5, #IS_IDLE
	beq	.Lip_out
	cmp	r5, #IS_WAIT
	beq	.Lip_out
	ldr	r0, [r4, #CT_FLAGS]
	tst	r0, #CF_OFF
	bne	.Lip_end
	ldr	r0, [r4, #CT_I_T0]
	bl	since
	mov	r6, r0			@ r6 = ms since the start of the injection
	cmp	r5, #IS_SHORT
	beq	.Lip_short
	cmp	r5, #IS_POWER
	beq	.Lip_power
	cmp	r5, #IS_RELEASE
	beq	.Lip_release
	ldr	r0, =V_KEYS_DOWN
	ldrh	r0, [r0]
	cmp	r5, #IS_HOLD_FE
	beq	.Lip_fe
@ IS_HOLD
	cmp	r0, #0
	bne	.Lip_end		@ a physical key: nothing was posted yet
	ldr	r1, [r4, #CT_I_HOLD]
	cmp	r6, r1
	blo	.Lip_hold_wait
	movw	r2, #HOLD_FE_MS
	cmp	r1, r2
	bhs	.Lip_to_fe
	movs	r0, #IS_SHORT		@ shorter than the 100th tick: a short release
	str	r0, [r4, #CT_I_STATE]
	b	.Lip_short
.Lip_hold_wait:
	movw	r2, #HOLD_FE_MS
	cmp	r6, r2
	blo	.Lip_out
.Lip_to_fe:
	movs	r0, #IS_HOLD_FE
	str	r0, [r4, #CT_I_STATE]
	b	.Lip_post_fe
.Lip_fe:
	cmp	r0, #0
	bne	.Lip_interrupt
	ldr	r1, [r4, #CT_I_HOLD]
	cmp	r6, r1
	blo	.Lip_post_fe
	ldr	r0, [r4, #CT_I_FECNT]
	cmp	r0, #0
	bne	.Lip_to_release
.Lip_post_fe:
	movs	r0, #KEY_CODE_HELD
	movs	r1, #1
	bl	post_try
	b	.Lip_out
.Lip_interrupt:
	movs	r0, #1
	str	r0, [r4, #CT_I_RESULT]
.Lip_to_release:
	movs	r0, #IS_RELEASE
	str	r0, [r4, #CT_I_STATE]
.Lip_release:
	movs	r0, #KEY_CODE_REL
	movs	r1, #0			@ a physical key may be down
	bl	post_try
	cmp	r0, #0
	beq	.Lip_out
	b	.Lip_waiting
.Lip_short:
	movs	r0, #KEY_CODE_SHORT
	movs	r1, #1
	bl	post_try
	cmp	r0, #0
	beq	.Lip_out
	b	.Lip_waiting
.Lip_power:
	movs	r0, #KEY_CODE_HELD
	movs	r1, #1
	bl	post_try
	cmp	r0, #0
	beq	.Lip_out
.Lip_waiting:
	movs	r0, #IS_WAIT
	str	r0, [r4, #CT_I_STATE]
	b	.Lip_out
.Lip_end:
	movs	r0, #1
	str	r0, [r4, #CT_I_RESULT]
	movs	r0, #IS_IDLE
	str	r0, [r4, #CT_I_STATE]
.Lip_out:
	pop	{r4, r5, r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ key_step - step (3). With PRIMASK set the slot is read: when it holds the posted code with
@   the injected mask, the event is the injected one and own_injected = 1 (unless the guard is
@   off for it); a different event in its place ends the injection (result 1). Then event
@   KEY, the OCAL_LOCK released (ocal_unlock), the power-off path noted (code 0xFE, mask 1, 0x20001190 = 0: 0x08009452), own_save's
@   count noted, 0x08009400 runs, own_injected = 0; a save refused by the guard during the
@   call marks the job (status 6). IS_WAIT ends when its code was consumed.
@   Direct change (CT_DS_OP != 0): when the slot is empty and no key is down (0x20000008 = 0),
@   both read with PRIMASK set, dset.s ds_run makes the change in place of 0x08009400 (which
@   returns at once with the slot at 0, app_01.s 85-86); otherwise the change waits.
@   Powered-off mode: 0x08009400 is not run; a power key event restarts the meter
@   (soft_restart, REQ_RESTART: the starter drives PA8 high again), any other event is cleared.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	key_step, %function
key_step:
	push	{r4, r5, r6, r7, r8, lr}
	sub	sp, #8
	ldr	r4, =OWN_CTL
	ldr	r5, =V_KEY_CODE
	ldr	r0, [r4, #CT_FLAGS]
	tst	r0, #CF_OFF
	bne	.Lk_off
	movs	r6, #0			@ r6 = 1: the event is the injected one
	cpsid	i
	ldrh	r7, [r5, #0]		@ r7 = code
	ldrh	r8, [r5, #2]		@ r8 = mask
	ldr	r0, [r4, #CT_I_POSTED]
	cmp	r0, #0
	beq	.Lk_read
	movs	r1, #0
	str	r1, [r4, #CT_I_POSTED]	@ consumed now, or replaced
	cmp	r7, r0
	bne	.Lk_taken
	ldr	r1, [r4, #CT_I_MASK]
	cmp	r8, r1
	bne	.Lk_taken
	movs	r6, #1
	cmp	r7, #KEY_CODE_HELD
	bne	.Lk_guard
	ldr	r1, [r4, #CT_I_FECNT]
	adds	r1, r1, #1
	str	r1, [r4, #CT_I_FECNT]
.Lk_guard:
	ldr	r1, [r4, #CT_I_GOFF]
	cmp	r1, #0
	bne	.Lk_read
	movs	r1, #1
	str	r1, [r4, #CTO_INJECTED]	@ guard on for this event
	b	.Lk_read
.Lk_taken:
	movs	r1, #1			@ another event replaced the injected one
	str	r1, [r4, #CT_I_RESULT]
	movs	r1, #IS_IDLE
	str	r1, [r4, #CT_I_STATE]
.Lk_read:
	cmp	r7, #0			@ an event in the slot (PRIMASK still set)?
	bne	.Lk_event		@ yes: the key path
	ldr	r0, [r4, #CT_DS_OP]	@ a direct change pending?
	cmp	r0, #0			@ none:
	beq	.Lk_quiet		@ 0x08009400 as usual (it returns at once)
	ldr	r0, =V_KEYS_DOWN	@ a key held down now (the scan's mask, read
	ldrh	r0, [r0]		@ with PRIMASK set like the slot)?
	cmp	r0, #0			@ a key down:
	bne	.Lk_quiet		@ the change waits for a pass without one
	cpsie	i			@ interrupts on again
	bl	ds_run			@ the change in place of 0x08009400 (dset.s)
	b	.Lk_wait		@ the injection state as after a call
.Lk_quiet:
	cpsie	i			@ interrupts on again
	b	.Lk_call		@ 0x08009400 with the empty slot
.Lk_event:
	cpsie	i			@ interrupts on again
	bl	ocal_unlock		@ any key event that reaches the key handler ends OCAL_LOCK (2.2)
	strh	r8, [sp, #0]		@ event KEY: mask, code, source
	strb	r7, [sp, #2]
	strb	r6, [sp, #3]
	movs	r0, #E_KEY
	mov	r1, sp
	movs	r2, #4
	bl	ev_send
	cmp	r7, #KEY_CODE_HELD	@ the meter's power-off path (0x08009452..0x08009468)
	bne	.Lk_call
	cmp	r8, #KEY_POWER
	bne	.Lk_call
	ldrh	r0, [r5, #-2]		@ 0x20001190
	cmp	r0, #0
	bne	.Lk_call
	ldr	r0, [r4, #CT_FLAGS]
	tst	r0, #CF_OFF_WAIT
	bne	.Lk_call
	orr	r0, r0, #CF_OFF_WAIT
	str	r0, [r4, #CT_FLAGS]
	bl	now
	str	r0, [r4, #CT_OFF_T]
.Lk_call:
	mov	r0, r7
	mov	r1, r8
	bl	own_cmp_key		@ the counter reset of screen 2 (cmp.s, S2.8 / D16)
	ldr	r0, =own_save_count
	ldr	r0, [r0]
	str	r0, [r4, #CT_SAVES_SEEN]
	bl	fn_08009400
	movs	r0, #0
	bl	own_sec_pick		@ the secondary-key mark of own_cmp_key ends (cmp.s)
	movs	r0, #0
	str	r0, [r4, #CTO_INJECTED]	@ guard off
	ldr	r0, =own_save_count
	ldr	r0, [r0]
	ldr	r1, [r4, #CT_SAVES_SEEN]
	cmp	r0, r1
	beq	.Lk_wait
	cmp	r6, #0
	beq	.Lk_wait
	ldr	r0, =own_save_status
	ldrb	r0, [r0]
	cmp	r0, #SV_REFUSED
	bne	.Lk_wait
	movs	r0, #1
	str	r0, [r4, #CT_J_GUARD]	@ the guard refused a save of the injected event
.Lk_wait:
	ldr	r0, [r4, #CT_I_STATE]
	cmp	r0, #IS_WAIT
	bne	.Lk_out
	ldr	r0, [r4, #CT_I_POSTED]
	cmp	r0, #0
	bne	.Lk_out
	movs	r0, #IS_IDLE
	str	r0, [r4, #CT_I_STATE]
	b	.Lk_out
.Lk_off:
	ldrh	r0, [r5, #0]
	cmp	r0, #0
	beq	.Lk_out
	ldrh	r1, [r5, #2]
	tst	r1, #KEY_POWER
	beq	.Lk_off_clear
	ldr	r0, =REQ_RESTART
	b	soft_restart		@ power key in powered-off mode: start normally (never returns)
.Lk_off_clear:
	movs	r0, #0
	strh	r0, [r5, #0]		@ event consumed without action
.Lk_out:
	add	sp, #8
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ key_refused - r0 = key mask, r1 = 1 for a hold. Returns r0 = 1 when the injection is
@   refused before dispatch (design 4.3), else 0. Read from the words the dispatchers read:
@   - screen 0 (0x20001168): every key (the first-start chooser stores 0x20001140 and saves;
@     not reached in our build, save.s set_english keeps 0x20001140 at 1);
@   - a calibration running (cal.s cal_busy: 0x200050E4 != 0 or a sweep of cal.s in progress) or
@     the CALIBRATE job active: every key;
@   - a hold of the power key (mask 1);
@   - key 8 in screen 3 on menu item 6 while a dialog is open (0x200011AC != 0: restore).
@   Key 8 on menu item 5 (the calibration dialog and its start, 0x0800F740..) is not refused
@   (MEASUREMENT_FIX_DESIGN revision 10 item 4): the host drives that menu as the meter's keys
@   do, and the calibration it starts is the sweep of cal.s, as one started by the key or by
@   CALIBRATE. Uses r0..r3, r12.
@ ----------------------------------------------------------------------------
	.global	key_refused
	.thumb_func
	.type	key_refused, %function
key_refused:
	push	{r4, r5, r6, lr}
	mov	r4, r0			@ r4 = key mask
	mov	r5, r1			@ r5 = 1 for a hold
	bl	cal_busy		@ r0 = 1 while a calibration runs
	ldr	r2, =V_SCREEN
	ldr	r2, [r2]
	cmp	r2, #0
	beq	.Lkr_yes
	cmp	r0, #0
	bne	.Lkr_yes
	ldr	r3, =OWN_CTL
	ldr	r12, [r3, #CT_J_ACTIVE]
	cmp	r12, #0
	beq	.Lkr_power
	ldr	r12, [r3, #CT_J_CMD]
	cmp	r12, #C_CALIBRATE
	beq	.Lkr_yes
.Lkr_power:
	cmp	r5, #0
	beq	.Lkr_ok_key
	tst	r4, #KEY_POWER
	bne	.Lkr_yes
.Lkr_ok_key:
	tst	r4, #KEY_OK
	beq	.Lkr_no
	cmp	r2, #3
	bne	.Lkr_no
	ldr	r3, =V_DISP_A8
	ldr	r3, [r3]		@ menu item
	cmp	r3, #6
	bne	.Lkr_no
	ldr	r3, =V_DIALOG
	ldr	r3, [r3]
	cmp	r3, #0
	bne	.Lkr_yes
.Lkr_no:
	movs	r0, #0
	pop	{r4, r5, r6, pc}
.Lkr_yes:
	movs	r0, #1
	pop	{r4, r5, r6, pc}

	.ltorg

@ ============================================================================
@ Jobs: commands that need the meter to act run as a program of steps, one step per pass
@ ============================================================================

@ ----------------------------------------------------------------------------
@ prog_reset - empty program. prog_add - r0 = op | kind << 8 | max << 16 (bits 24..31 0),
@   r1 = key a | key b << 16, r2 = arg, r3 = target: one step appended (ignored when
@   PROG_MAX steps are there; every program of cmd.s has fewer). Use r0..r3, r12.
@ ----------------------------------------------------------------------------
	.global	prog_reset
	.thumb_func
	.type	prog_reset, %function
prog_reset:
	ldr	r0, =OWN_CTL
	movs	r1, #0
	str	r1, [r0, #CT_J_NSTEPS]
	bx	lr

	.global	prog_add
	.thumb_func
	.type	prog_add, %function
prog_add:
	push	{r4, r5}
	ldr	r4, =OWN_CTL
	ldr	r5, [r4, #CT_J_NSTEPS]
	cmp	r5, #PROG_MAX
	bhs	.Lpa_out
	add	r12, r4, r5, lsl #4
	add	r12, r12, #CT_PROG
	str	r0, [r12, #0]
	str	r1, [r12, #4]
	str	r2, [r12, #8]
	str	r3, [r12, #12]
	adds	r5, r5, #1
	str	r5, [r4, #CT_J_NSTEPS]
.Lpa_out:
	pop	{r4, r5}
	bx	lr

@ ----------------------------------------------------------------------------
@ job_start - r0 = command, r1 = AN_* answer kind, r2 = time limit in ms: the program built
@   with prog_reset / prog_add starts at its first step. Uses r0..r3.
@ ----------------------------------------------------------------------------
	.global	job_start
	.thumb_func
	.type	job_start, %function
job_start:
	ldr	r3, =OWN_CTL
	str	r0, [r3, #CT_J_CMD]
	str	r1, [r3, #CT_J_ANSWER]
	str	r2, [r3, #CT_J_LIMIT]
	movs	r0, #0
	str	r0, [r3, #CT_J_PC]
	str	r0, [r3, #CT_J_STATUS]
	str	r0, [r3, #CT_J_GUARD]
	str	r0, [r3, #CT_J_PRESSED]
	str	r0, [r3, #CT_J_SWAP]
	mvn	r0, #0
	str	r0, [r3, #CT_J_COUNT]
	ldr	r0, =V_TICK
	ldr	r0, [r0]
	str	r0, [r3, #CT_J_T0]
	str	r0, [r3, #CT_J_STEPT]
	movs	r0, #1
	str	r0, [r3, #CT_J_ACTIVE]
	bx	lr

@ ----------------------------------------------------------------------------
@ job_press - r0 = key mask, r1 = kind (KB_*), r2 = hold ms (0: LONG_MS for KB_LONG, else a
@   short press). Without KB_GOFF the injection is checked by key_refused first.
@   Returns r0 = 0 started, 1 refused. Marks CT_J_PRESSED.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	job_press, %function
job_press:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	mov	r5, r1
	mov	r6, r2
	cmp	r6, #0
	bne	.Ljp_check
	tst	r5, #KB_LONG
	beq	.Ljp_check
	movw	r6, #LONG_MS
.Ljp_check:
	tst	r5, #KB_GOFF
	bne	.Ljp_go
	mov	r0, r4
	subs	r1, r6, #0
	it	ne
	movne	r1, #1
	bl	key_refused
	cmp	r0, #0
	bne	.Ljp_refused
.Ljp_go:
	mov	r0, r4
	mov	r1, r6
	ands	r2, r5, #KB_GOFF
	it	ne
	movne	r2, #1
	bl	inj_start
	ldr	r0, =OWN_CTL
	movs	r1, #1
	str	r1, [r0, #CT_J_PRESSED]
	movs	r0, #0
	pop	{r4, r5, r6, pc}
.Ljp_refused:
	movs	r0, #1
	pop	{r4, r5, r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ job_step - step (1): one step of the running program, only while no key is in flight.
@   Ends the job with status 4 (busy) when a physical key ended its injection or the time
@   limit passed (an injection still waiting is dropped then, a hold that sent 0xFE is
@   ended with 0xFF first), status 3 in powered-off mode. Each op either waits, presses one key, or
@   moves to the next step (one step per pass).
@   OP_SCREEN: target screen reached -> next; screen 1 / 2 -> long key 0x400 (1 <-> 2) or
@     long key 8 (settings); screen 3 -> long key 8 (closes a dialog, then leaves the menu to
@     the previous screen), on menu item 5 without a dialog first key 2 (item - 1; written when
@     key 8 on item 5 was refused, kept: the only programs with OP_SCREEN, CALIBRATE's, press
@     with the guard off, and the way out of the menu is the same); screen 0 or another: status
@     3. At most PS_MAX presses.
@   OP_PRESS: done when the word at PS_ARG equals the target; else key a, or with a key b:
@     key a to raise, key b to lower the value, swapped when a press left the value unchanged
@     or moved it away. PS_MAX presses, then status 3.
@   OP_KEY: one press of key a (hold PS_ARG ms, or by the kind), then next.
@   OP_CHECK: the word at PS_ARG = target, else the status in key a.
@   OP_NODIALOG: long key 8 until 0x200011AC = 0, PS_MAX presses.
@   OP_WAITCAL: calibration status 0x200050EC 2 -> next (status 0), 3 -> next (status 3);
@     0x200050E4 = 0 for 1000 ms without one of them -> next (status 3).
@   OP_ERASE: one page of the BOOT slot per pass through flash_erase_page with the gate open
@     for that slot only; a failure: status 5. After the 12th page BS_ERASED, next.
@   OP_DIRECT (the only step of a direct change, dset.s ds_request): CT_DS_OP = 0 (ds_run made
@     the change or refused it, its status in CT_J_STATUS) -> the answer; the meter's power-off
@     path ran (CF_OFF_WAIT) -> status 3; else wait (key_step runs the change in a pass without
@     a key event).
@   Past the last step: the answer of the job's kind (cmd.s job_answer). Every end of a job
@   clears CT_DS_OP, so a change dropped by the time limit never runs later.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	job_step, %function
job_step:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =OWN_CTL
	ldr	r0, [r4, #CT_J_ACTIVE]
	cmp	r0, #0
	beq	.Lj_out
	ldr	r0, [r4, #CT_J_T0]
	bl	since
	ldr	r1, [r4, #CT_J_LIMIT]
	cmp	r0, r1
	bls	.Lj_intime
	ldr	r0, [r4, #CT_I_STATE]	@ time limit passed: end the injection first
	cmp	r0, #IS_IDLE
	beq	.Lj_busy
	cmp	r0, #IS_WAIT
	beq	.Lj_out			@ consumed in this pass's step 3
	cmp	r0, #IS_RELEASE
	beq	.Lj_out			@ 0xFF goes out at the next empty slot
	movs	r1, #1
	str	r1, [r4, #CT_I_RESULT]
	cmp	r0, #IS_HOLD_FE
	bne	.Lj_drop
	movs	r0, #IS_RELEASE		@ a hold that sent 0xFE ends with 0xFF
	str	r0, [r4, #CT_I_STATE]
	b	.Lj_out
.Lj_drop:
	movs	r0, #IS_IDLE		@ nothing of it was posted yet
	str	r0, [r4, #CT_I_STATE]
	b	.Lj_busy
.Lj_intime:
	ldr	r0, [r4, #CT_I_STATE]
	cmp	r0, #IS_IDLE
	bne	.Lj_out			@ a key is in flight
	ldr	r0, [r4, #CT_J_PRESSED]
	cmp	r0, #0
	beq	.Lj_alive
	ldr	r0, [r4, #CT_I_RESULT]
	cmp	r0, #0
	bne	.Lj_busy		@ a physical key ended the injection
.Lj_alive:
	ldr	r0, [r4, #CT_FLAGS]
	tst	r0, #CF_OFF
	bne	.Lj_notnow
	ldr	r5, [r4, #CT_J_PC]
	ldr	r0, [r4, #CT_J_NSTEPS]
	cmp	r5, r0
	bhs	.Lj_finish
	add	r5, r4, r5, lsl #4
	add	r5, r5, #CT_PROG	@ r5 = the step
	ldrb	r0, [r5, #PS_OP]
	cmp	r0, #OP_PRESS
	beq	.Lj_press
	cmp	r0, #OP_KEY
	beq	.Lj_key
	cmp	r0, #OP_CHECK
	beq	.Lj_check
	cmp	r0, #OP_SCREEN
	beq	.Lj_screen
	cmp	r0, #OP_NODIALOG
	beq	.Lj_nodialog
	cmp	r0, #OP_WAITCAL
	beq	.Lj_waitcal
	cmp	r0, #OP_ERASE
	beq	.Lj_erase
	cmp	r0, #OP_DIRECT		@ a direct change
	beq	.Lj_direct
	b	.Lj_finish		@ OP_END

@ OP_DIRECT
.Lj_direct:
	ldr	r0, [r4, #CT_DS_OP]	@ change still pending?
	cmp	r0, #0			@ no: made or refused by ds_run (status in CT_J_STATUS):
	beq	.Lj_finish		@ the answer (the program has this one step)
	ldr	r0, [r4, #CT_FLAGS]	@ the meter's power-off path ran meanwhile:
	tst	r0, #CF_OFF_WAIT	@ a change now would be lost after its save
	bne	.Lj_notnow		@ status 3 (CT_DS_OP cleared at the finish)
	b	.Lj_out			@ wait for a pass without a key event (key_step)

@ OP_PRESS
.Lj_press:
	ldr	r1, [r5, #PS_ARG]	@ address of the word
	ldr	r6, [r1]		@ r6 = value now
	ldr	r7, [r5, #PS_TARGET]	@ r7 = target
	ldr	r0, [r4, #CT_J_PRESSED]
	cmp	r0, #0
	beq	.Lj_eval
	movs	r0, #0
	str	r0, [r4, #CT_J_PRESSED]
	ldrh	r0, [r5, #PS_KEYS + 2]
	cmp	r0, #0
	beq	.Lj_eval		@ one key: no direction
	ldr	r0, [r4, #CT_J_LAST]
	subs	r1, r6, r0		@ change made by the last press
	beq	.Lj_swap
	subs	r2, r7, r0		@ distance before that press
	eors	r1, r1, r2
	bpl	.Lj_eval		@ same sign: towards the target
.Lj_swap:
	ldr	r0, [r4, #CT_J_SWAP]
	eor	r0, r0, #1
	str	r0, [r4, #CT_J_SWAP]
.Lj_eval:
	subs	r8, r7, r6		@ r8 = target - value
	beq	.Lj_next		@ reached: next step
	bl	job_count		@ r0 = 0: no press left
	cmp	r0, #0
	beq	.Lj_notnow
	ldrh	r0, [r5, #PS_KEYS]	@ key a
	ldrh	r1, [r5, #PS_KEYS + 2]	@ key b
	cmp	r1, #0
	beq	.Lj_press_go
	ldr	r2, [r4, #CT_J_SWAP]
	cmp	r8, #0
	ite	gt
	movgt	r3, #0			@ raise
	movle	r3, #1			@ lower
	eors	r3, r3, r2
	it	ne
	movne	r0, r1			@ key b
.Lj_press_go:
	str	r6, [r4, #CT_J_LAST]
	ldrb	r1, [r5, #PS_KIND]
	movs	r2, #0
	bl	job_press
	cmp	r0, #0
	bne	.Lj_safety
	b	.Lj_out

@ OP_KEY
.Lj_key:
	ldr	r0, [r4, #CT_J_COUNT]
	adds	r0, r0, #1
	bne	.Lj_next		@ pressed already: next step
	str	r0, [r4, #CT_J_COUNT]	@ 0
	ldrh	r0, [r5, #PS_KEYS]
	ldrb	r1, [r5, #PS_KIND]
	ldr	r2, [r5, #PS_ARG]
	bl	job_press
	cmp	r0, #0
	bne	.Lj_safety
	b	.Lj_out

@ OP_CHECK
.Lj_check:
	ldr	r1, [r5, #PS_ARG]	@ address of the word
	ldr	r0, [r1]		@ r0 = its value
	ldr	r1, [r5, #PS_TARGET]
	cmp	r0, r1
	beq	.Lj_next
	ldrh	r0, [r5, #PS_KEYS]	@ status of the failed check
	b	.Lj_fail

@ OP_SCREEN
.Lj_screen:
	ldr	r0, =V_SCREEN
	ldr	r6, [r0]		@ r6 = screen now
	ldr	r7, [r5, #PS_TARGET]
	cmp	r6, r7
	beq	.Lj_next
	bl	job_count
	cmp	r0, #0
	beq	.Lj_notnow
	cmp	r6, #1
	beq	.Lj_scr_meas
	cmp	r6, #2
	beq	.Lj_scr_meas
	cmp	r6, #3
	bne	.Lj_notnow		@ screen 0 (the chooser; never reached, save.s) or unknown
	ldr	r0, =V_DIALOG
	ldr	r0, [r0]
	cmp	r0, #0
	bne	.Lj_scr_long8
	ldr	r0, =V_DISP_A8
	ldr	r0, [r0]
	cmp	r0, #5
	bne	.Lj_scr_long8
	movs	r0, #KEY_UP		@ item 5 -> 4 (0x08009A8A: fn_0800f294(0, -1))
	movs	r1, #0
	b	.Lj_scr_press
.Lj_scr_meas:
	cmp	r7, #3
	beq	.Lj_scr_long8
	mov	r0, #KEY_0400		@ long: 1 <-> 2 (0x08009614 code 0xFE)
	b	.Lj_scr_long
.Lj_scr_long8:
	movs	r0, #KEY_OK
.Lj_scr_long:
	movs	r1, #KB_LONG
.Lj_scr_press:
	ldrb	r2, [r5, #PS_KIND]
	and	r2, r2, #KB_GOFF
	orr	r1, r1, r2
	movs	r2, #0
	bl	job_press
	cmp	r0, #0
	bne	.Lj_safety
	b	.Lj_out

@ OP_NODIALOG
.Lj_nodialog:
	ldr	r0, =V_DIALOG
	ldr	r0, [r0]
	cmp	r0, #0
	beq	.Lj_next
	bl	job_count
	cmp	r0, #0
	beq	.Lj_notnow
	movs	r0, #KEY_OK
	ldrb	r1, [r5, #PS_KIND]
	and	r1, r1, #KB_GOFF
	orr	r1, r1, #KB_LONG
	movs	r2, #0
	bl	job_press
	cmp	r0, #0
	bne	.Lj_safety
	b	.Lj_out

@ OP_WAITCAL
.Lj_waitcal:
	ldr	r0, =V_CAL_STATUS
	ldr	r0, [r0]
	cmp	r0, #2
	beq	.Lj_next		@ finished (status stays 0)
	cmp	r0, #3
	beq	.Lj_cal_fail
	ldr	r0, =V_CAL_RUN
	ldr	r0, [r0]
	cmp	r0, #0
	bne	.Lj_out
	ldr	r0, [r4, #CT_J_STEPT]
	bl	since
	movw	r1, #1000
	cmp	r0, r1
	blo	.Lj_out
.Lj_cal_fail:
	movs	r0, #S_NOT_NOW
	str	r0, [r4, #CT_J_STATUS]
	b	.Lj_next

@ OP_ERASE
.Lj_erase:
	ldr	r6, [r4, #CT_B_PAGE]
	cmp	r6, #SLOT_PAGES
	bhs	.Lj_erased
	ldr	r0, [r4, #CT_B_SLOT]
	bl	flash_boot_gate		@ the free slot and the record pages only
	ldr	r0, [r4, #CT_B_SLOT]
	add	r0, r0, r6, lsl #11	@ page base (0x800 bytes per page)
	bl	flash_erase_page	@ watchdog fed before and after (save.s)
	mov	r7, r0
	movs	r0, #0
	bl	flash_boot_gate		@ closed again
	cmp	r7, #FL_OK
	bne	.Lj_erase_fail
	adds	r6, r6, #1
	str	r6, [r4, #CT_B_PAGE]
	b	.Lj_out
.Lj_erased:
	movs	r0, #BS_ERASED
	str	r0, [r4, #CT_B_STATE]
	b	.Lj_next
.Lj_erase_fail:
	movs	r0, #BS_NONE
	str	r0, [r4, #CT_B_STATE]
	movs	r0, #S_STORAGE
	b	.Lj_fail

.Lj_next:
	ldr	r0, [r4, #CT_J_PC]
	adds	r0, r0, #1
	str	r0, [r4, #CT_J_PC]
	mvn	r0, #0
	str	r0, [r4, #CT_J_COUNT]
	movs	r0, #0
	str	r0, [r4, #CT_J_PRESSED]
	str	r0, [r4, #CT_J_SWAP]
	bl	now
	str	r0, [r4, #CT_J_STEPT]
	b	.Lj_out
.Lj_busy:
	movs	r0, #S_BUSY
	b	.Lj_fail
.Lj_notnow:
	movs	r0, #S_NOT_NOW
	b	.Lj_fail
.Lj_safety:
	movs	r0, #S_SAFETY
.Lj_fail:
	str	r0, [r4, #CT_J_STATUS]
.Lj_finish:
	movs	r0, #0
	str	r0, [r4, #CT_J_ACTIVE]
	str	r0, [r4, #CT_DS_OP]	@ no direct change survives its job
	ldr	r1, [r4, #CT_J_STATUS]
	ldr	r0, [r4, #CT_J_GUARD]
	cmp	r0, #0
	it	ne
	movne	r1, #S_SAFETY		@ the guard refused an action of an injected key
	ldr	r0, [r4, #CT_J_ANSWER]
	bl	job_answer
.Lj_out:
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ job_count - presses left in the step: a new step takes PS_MAX of the step at r5.
@   Returns r0 = 0 when none is left, else 1 and one press taken. Uses r0, r1; r4 = OWN_CTL,
@   r5 = step (from job_step).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	job_count, %function
job_count:
	ldr	r0, [r4, #CT_J_COUNT]
	adds	r1, r0, #1
	bne	.Ljc_have
	ldrb	r0, [r5, #PS_MAX]	@ new step
.Ljc_have:
	cmp	r0, #0
	beq	.Ljc_none
	subs	r0, r0, #1
	str	r0, [r4, #CT_J_COUNT]
	movs	r0, #1
	bx	lr
.Ljc_none:
	str	r0, [r4, #CT_J_COUNT]
	bx	lr

	.ltorg

@ ============================================================================
@ Number helpers of COMPARE_SET (cmd.s h_compare_set, dset.s cs_diff)
@ ============================================================================

@ ----------------------------------------------------------------------------
@ tenths - r0 = float bits (tolerance, >= 0) -> r0 = trunc(value * 10 + 0.5). Uses s0, s1.
@ ----------------------------------------------------------------------------
	.global	tenths
	.thumb_func
	.type	tenths, %function
tenths:
	vmov	s0, r0
	vmov.f32 s1, #10.0
	vmul.f32 s0, s0, s1
	vmov.f32 s1, #0.5
	vadd.f32 s0, s0, s1
	vcvt.s32.f32 s0, s0
	vmov	r0, s0
	bx	lr

@ ----------------------------------------------------------------------------
@ nom_count - r0 = sorting nominal (float bits), r1 = scale index -> r0 = the 5-digit count
@   fn_0800e224 edits: round(nominal * 100 / scale) with scale 0.001, 1.0, 1000.0, 1e6 (index
@   3 and above), computed as 0x0800E2E4..0x0800E2FE does it (vmul, vdiv, float_to_double,
@   fn_080116a0, double_to_int32). Uses r0..r3, r12, s0..s15, d0.
@ ----------------------------------------------------------------------------
	.global	nom_count
	.thumb_func
	.type	nom_count, %function
nom_count:
	push	{r4, lr}
	cmp	r1, #3
	it	hi
	movhi	r1, #3
	ldr	r2, =tab_scale
	ldr	r2, [r2, r1, lsl #2]
	vmov	s0, r0
	vmov	s1, r2			@ scale
	ldr	r3, =0x42C80000		@ 100.0
	vmov	s2, r3
	vmul.f32 s3, s0, s2
	vdiv.f32 s0, s3, s1
	vmov	r0, s0
	bl	float_to_double
	vmov	d0, r0, r1
	bl	fn_080116a0		@ rounding as the editor does it
	vmov	r0, r1, d0
	bl	double_to_int32
	pop	{r4, pc}

	.ltorg

@ ============================================================================
@ Events
@ ============================================================================

@ ----------------------------------------------------------------------------
@ ev_send - r0 = event cmd, r1 = data, r2 = length (<= 14). Nothing while DTR is clear.
@   While a screenshot runs the event waits in the queue (16 entries; full: dropped and
@   counted); else it is sent now (no room: dropped and counted).
@ ----------------------------------------------------------------------------
	.global	ev_send
	.thumb_func
	.type	ev_send, %function
ev_send:
	push	{r4, r5, r6, lr}
	mov	r4, r0
	mov	r5, r1
	mov	r6, r2
	bl	usb_dtr
	cmp	r0, #0
	beq	.Les_out
	bl	scr_busy
	cmp	r0, #0
	bne	.Les_queue
	movs	r0, #FR_EVENT
	mov	r1, r4
	mov	r2, r5
	mov	r3, r6
	bl	out_counted
	b	.Les_out
.Les_queue:
	ldr	r3, =OWN_CTL
	ldr	r0, [r3, #CT_EQ_COUNT]
	cmp	r0, #EVQ_N
	bhs	.Les_drop
	ldr	r1, [r3, #CT_EQ_HEAD]
	add	r1, r1, r0
	and	r1, r1, #EVQ_N - 1
	adds	r0, r0, #1
	str	r0, [r3, #CT_EQ_COUNT]
	add	r1, r3, r1, lsl #4
	add	r1, r1, #CT_EVQ		@ r1 = entry
	strb	r4, [r1, #0]		@ cmd
	strb	r6, [r1, #1]		@ length
	adds	r1, r1, #2
.Les_copy:
	cmp	r6, #0
	beq	.Les_out
	ldrb	r0, [r5], #1
	strb	r0, [r1], #1
	subs	r6, r6, #1
	b	.Les_copy
.Les_drop:
	ldr	r0, [r3, #CT_DROPPED]
	adds	r0, r0, #1
	str	r0, [r3, #CT_DROPPED]
.Les_out:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ ev_drain - the queued events go out once no screenshot runs (DTR clear: discarded).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ev_drain, %function
ev_drain:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_CTL
	ldr	r0, [r4, #CT_EQ_COUNT]
	cmp	r0, #0
	beq	.Led_out
	bl	scr_busy
	cmp	r0, #0
	bne	.Led_out
	bl	usb_dtr
	cmp	r0, #0
	beq	.Led_clear
.Led_next:
	ldr	r0, [r4, #CT_EQ_COUNT]
	cmp	r0, #0
	beq	.Led_out
	subs	r0, r0, #1
	str	r0, [r4, #CT_EQ_COUNT]
	ldr	r5, [r4, #CT_EQ_HEAD]
	adds	r0, r5, #1
	and	r0, r0, #EVQ_N - 1
	str	r0, [r4, #CT_EQ_HEAD]
	add	r5, r4, r5, lsl #4
	add	r5, r5, #CT_EVQ
	movs	r0, #FR_EVENT
	ldrb	r1, [r5, #0]
	adds	r2, r5, #2
	ldrb	r3, [r5, #1]
	bl	out_counted
	b	.Led_next
.Led_clear:
	movs	r0, #0
	str	r0, [r4, #CT_EQ_COUNT]
	str	r0, [r4, #CT_EQ_HEAD]
.Led_out:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ ev_prime - the previous values of every compared word set to the current ones (first
@   pass, before any event): screen, save count, calibration status / step, measurement flag
@   and |Z| / theta, the four RAM-only words, the settings block.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ev_prime, %function
ev_prime:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_CTL
	ldr	r0, =V_SCREEN
	ldr	r0, [r0]
	str	r0, [r4, #CT_PREV_SCREEN]
	ldr	r0, =own_save_count
	ldr	r0, [r0]
	str	r0, [r4, #CT_PREV_SAVES]
	ldr	r0, =V_CAL_STATUS
	ldr	r0, [r0]
	str	r0, [r4, #CT_PREV_CALST]
	ldr	r0, =V_CAL_STEP
	ldr	r0, [r0]
	str	r0, [r4, #CT_PREV_CALSTP]
	ldr	r0, =V_MEAS_NEW
	ldr	r0, [r0]
	str	r0, [r4, #CT_MEAS_FLAG]
	ldr	r0, =V_Z
	ldr	r0, [r0]
	str	r0, [r4, #CT_MEAS_Z]
	ldr	r0, =V_THETA
	ldr	r0, [r0]
	str	r0, [r4, #CT_MEAS_TH]
	ldr	r5, =ram_words
	movs	r6, #0
.Lpr_ram:
	bl	ram_word		@ r0 = value of entry r6
	add	r1, r4, r6, lsl #2
	str	r0, [r1, #CT_PREV_RAM]
	adds	r6, r6, #1
	cmp	r6, #4
	blo	.Lpr_ram
	ldr	r0, =V_BLOCK
	addw	r1, r4, #CT_PREVBLK
	movw	r2, #BLK_SIZE
.Lpr_blk:
	ldr	r3, [r0], #4
	str	r3, [r1], #4
	subs	r2, r2, #4
	bne	.Lpr_blk
	ldr	r0, [r4, #CT_FLAGS]
	orr	r0, r0, #CF_PRIMED
	str	r0, [r4, #CT_FLAGS]
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ ram_word - r5 = ram_words, r6 = entry 0..3 -> r0 = the word (byte for 0x200011E4).
@   Uses r0, r1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ram_word, %function
ram_word:
	ldr	r1, [r5, r6, lsl #2]
	cmp	r6, #2
	beq	.Lrw_byte
	ldr	r0, [r1]
	bx	lr
.Lrw_byte:
	ldrb	r0, [r1]
	bx	lr

	.ltorg

@ ----------------------------------------------------------------------------
@ ev_detect - step (4): the queue first, then every comparison with the previous pass
@   (previous values are updated with or without DTR, so a host that sets DTR gets only
@   changes from then on):
@   SCREEN_CHANGED (0x20001168); SAVE_RESULT (own_save_count changed); CALIBRATION
@   (0x200050EC or 0x200050E8 changed); MEASURE_DONE: 0x20001200 was set in the previous
@   pass and is 0 now (0x0800A068 consumed it at 0x080090F8.. or fn_08009f10 cleared it), or
@   the words |Z| 0x200050C4 / theta 0x200050CC changed (in our build own_measure writes them,
@   meas.s; cal_commit, cal.s, writes the calibration results there for fn_0800bb64 and puts
@   the published words back within its call, earlier in the same pass, so they are not seen);
@   SETTING_CHANGED for 0x200011A4, 0x200011A8, byte 0x200011E4, 0x200011E8 and for every
@   changed word of the 0xC14-byte block (one compare of the block per pass; words of the
@   calibration tables 0x04..0xB43 as one event with their number).
@   The block compare takes 4 words at a time (two ldm, one compare chain): a group with no
@   change is passed over at once; otherwise the next word goes through the per-word compare,
@   which sends its event, and the groups go on from the word after it. So every changed word
@   still gets its event, in the order of the offsets, and the calibration count is the same;
@   the 773-word block costs about 4 instructions per word instead of 8 when nothing changed
@   (19.4 % of all instructions in the profile of a screen change, NOTES).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ev_detect, %function
ev_detect:
	push	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #20			@ 16 bytes of event data, 8-byte stack alignment kept
	ldr	r4, =OWN_CTL
	bl	ev_drain
@ screen
	ldr	r0, =V_SCREEN
	ldr	r0, [r0]
	ldr	r1, [r4, #CT_PREV_SCREEN]
	cmp	r0, r1
	beq	.Ld_saves
	str	r0, [r4, #CT_PREV_SCREEN]
	strb	r0, [sp, #0]
	strb	r1, [sp, #1]
	movs	r0, #E_SCREEN
	mov	r1, sp
	movs	r2, #2
	bl	ev_send
.Ld_saves:
	ldr	r0, =own_save_count
	ldr	r0, [r0]
	ldr	r1, [r4, #CT_PREV_SAVES]
	cmp	r0, r1
	beq	.Ld_cal
	str	r0, [r4, #CT_PREV_SAVES]
	ldr	r0, =own_save_status
	ldr	r0, [r0]
	str	r0, [sp, #0]
	ldr	r0, =own_save_flags
	ldr	r0, [r0]
	str	r0, [sp, #4]
	movs	r0, #E_SAVE_RESULT
	mov	r1, sp
	movs	r2, #8
	bl	ev_send
.Ld_cal:
	ldr	r0, =V_CAL_STATUS
	ldr	r5, [r0]
	ldr	r0, =V_CAL_STEP
	ldr	r6, [r0]
	ldr	r0, [r4, #CT_PREV_CALST]
	ldr	r1, [r4, #CT_PREV_CALSTP]
	cmp	r5, r0
	bne	.Ld_cal_ev
	cmp	r6, r1
	beq	.Ld_meas
.Ld_cal_ev:
	str	r5, [r4, #CT_PREV_CALST]
	str	r6, [r4, #CT_PREV_CALSTP]
	strb	r5, [sp, #0]
	strb	r6, [sp, #1]
	ldr	r0, =V_CAL_TYPE
	ldr	r0, [r0]
	strb	r0, [sp, #2]
	movs	r0, #E_CALIBRATION
	mov	r1, sp
	movs	r2, #3
	bl	ev_send
.Ld_meas:
	movs	r7, #0			@ r7 = 1: a new result
	ldr	r0, =V_MEAS_NEW
	ldr	r0, [r0]
	ldr	r1, [r4, #CT_MEAS_FLAG]
	str	r0, [r4, #CT_MEAS_FLAG]
	cmp	r1, #0
	beq	.Ld_meas_vals
	cmp	r0, #0
	it	eq
	moveq	r7, #1			@ set before, consumed now
.Ld_meas_vals:
	ldr	r0, =V_Z
	ldr	r0, [r0]
	ldr	r1, [r4, #CT_MEAS_Z]
	str	r0, [r4, #CT_MEAS_Z]
	cmp	r0, r1
	it	ne
	movne	r7, #1
	ldr	r0, =V_THETA
	ldr	r0, [r0]
	ldr	r1, [r4, #CT_MEAS_TH]
	str	r0, [r4, #CT_MEAS_TH]
	cmp	r0, r1
	it	ne
	movne	r7, #1
	cmp	r7, #0
	beq	.Ld_ram
	ldr	r0, [r4, #CT_MEAS_SEQ]
	adds	r0, r0, #1
	str	r0, [r4, #CT_MEAS_SEQ]
	str	r0, [sp, #0]
	ldr	r0, [r4, #CT_FLAGS]
	orr	r0, r0, #CF_MS_DUE
	str	r0, [r4, #CT_FLAGS]
	movs	r0, #E_MEASURE_DONE
	mov	r1, sp
	movs	r2, #4
	bl	ev_send
.Ld_ram:
	ldr	r5, =ram_words
	movs	r6, #0
.Ld_ram_next:
	bl	ram_word
	add	r1, r4, r6, lsl #2
	ldr	r2, [r1, #CT_PREV_RAM]
	cmp	r0, r2
	beq	.Ld_ram_same
	str	r0, [r1, #CT_PREV_RAM]
	str	r0, [sp, #4]		@ value (bytes 4..7), id at bytes 2..3
	ldr	r1, [r5, r6, lsl #2]
	ldr	r2, =V_BLOCK
	subs	r1, r1, r2
	strh	r1, [sp, #2]
	movs	r0, #E_SETTING
	add	r1, sp, #2
	movs	r2, #6
	bl	ev_send
.Ld_ram_same:
	adds	r6, r6, #1
	cmp	r6, #4
	blo	.Ld_ram_next
@ settings block
	ldr	r5, =V_BLOCK
	addw	r6, r4, #CT_PREVBLK
	movs	r7, #0			@ r7 = offset
	movs	r8, #0			@ r8 = changed words of the calibration tables
.Ld_blk:
	movw	r0, #BLK_SIZE
	cmp	r7, r0
	bhs	.Ld_blk_done		@ the whole block compared
	subs	r0, r0, #16
	cmp	r7, r0
	bhi	.Ld_blk_word		@ fewer than 4 words left: one by one
	add	r0, r5, r7
	ldm	r0, {r0, r1, r2, r3}	@ 4 words now
	add	lr, r6, r7
	ldm	lr, {r9, r10, r11, r12}	@ the same 4 of the previous pass
	cmp	r0, r9
	ittt	eq
	cmpeq	r1, r10
	cmpeq	r2, r11
	cmpeq	r3, r12
	bne	.Ld_blk_word		@ a change among them: the next word one by one
	adds	r7, r7, #16
	b	.Ld_blk
.Ld_blk_word:
	ldr	r0, [r5, r7]
	ldr	r1, [r6, r7]
	cmp	r0, r1
	beq	.Ld_blk_next
	str	r0, [r6, r7]
	cmp	r7, #BLK_CAL_LO
	blo	.Ld_blk_one
	movw	r1, #BLK_CAL_LO + BLK_CAL_LEN
	cmp	r7, r1
	bhs	.Ld_blk_one
	adds	r8, r8, #1
	b	.Ld_blk_next
.Ld_blk_one:
	str	r0, [sp, #4]
	strh	r7, [sp, #2]
	movs	r0, #E_SETTING
	add	r1, sp, #2
	movs	r2, #6
	bl	ev_send
.Ld_blk_next:
	adds	r7, r7, #4
	b	.Ld_blk
.Ld_blk_done:
	cmp	r8, #0
	beq	.Ld_out
	str	r8, [sp, #4]
	movw	r0, #ID_CAL_TABLES
	strh	r0, [sp, #2]
	movs	r0, #E_SETTING
	add	r1, sp, #2
	movs	r2, #6
	bl	ev_send
.Ld_out:
	add	sp, #20
	pop	{r4, r5, r6, r7, r8, r9, r10, r11, pc}

	.ltorg

@ ============================================================================
@ Streams and the frame parser
@ ============================================================================

@ ----------------------------------------------------------------------------
@ stream_step - STATE stream frames (cmd 0x10) every CT_ST_PERIOD ms, MEASURE stream frames
@   (cmd 0x22) on every new result (mode 1) or every CT_MS_PERIOD ms (mode 2); both pause
@   while a screenshot runs. A frame without room is dropped and counted.
@   Called from ctl_loop and from own_flush (screen.s) at every GUI flush: the vendor refresh
@   timer fn_08012188 redraws the screen from the main loop's timer walk fn_08027830, outside
@   ctl_loop, for up to 3.37 M instructions (NOTES, k12), with 12 flushes per redraw. No
@   CT_FLAGS update in ctl.s spans a call, and CT_REC has no user but this function, so the
@   call inside a flush meets no half-done state.
@ ----------------------------------------------------------------------------
	.global	stream_step
	.thumb_func
	.type	stream_step, %function
stream_step:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_CTL
	bl	scr_busy
	cmp	r0, #0
	bne	.Lss_out
	ldr	r5, [r4, #CT_ST_PERIOD]
	cmp	r5, #0
	beq	.Lss_meas
	ldr	r0, [r4, #CT_ST_NEXT]
	bl	since
	cmp	r0, #0
	blt	.Lss_meas		@ not due yet
	mov	r6, r0			@ r6 = how late this frame is
	ldr	r0, [r4, #CT_ST_NEXT]
	add	r0, r0, r5		@ next point of the period grid (the average rate is kept)
	cmp	r6, r5
	blo	.Lss_grid
	bl	now			@ more than one period late: the grid restarts from now
	add	r0, r0, r5		@ (no burst of frames to catch up)
.Lss_grid:
	str	r0, [r4, #CT_ST_NEXT]
	addw	r0, r4, #CT_REC
	bl	rec_state
	mov	r3, r0
	addw	r2, r4, #CT_REC
	movs	r1, #C_STATE
	movs	r0, #FR_STREAM
	bl	out_counted
.Lss_meas:
	ldr	r5, [r4, #CT_MS_MODE]
	ldr	r6, [r4, #CT_FLAGS]
	bic	r0, r6, #CF_MS_DUE
	str	r0, [r4, #CT_FLAGS]
	cmp	r5, #1
	beq	.Lss_every
	cmp	r5, #2
	bne	.Lss_out
	ldr	r0, [r4, #CT_MS_NEXT]
	bl	since
	cmp	r0, #0
	blt	.Lss_out
	mov	r6, r0			@ r6 = how late this frame is
	ldr	r1, [r4, #CT_MS_PERIOD]
	ldr	r0, [r4, #CT_MS_NEXT]
	add	r0, r0, r1		@ next point of the period grid
	cmp	r6, r1
	blo	.Lss_mgrid
	mov	r6, r1
	bl	now			@ more than one period late: the grid restarts from now
	add	r0, r0, r6
.Lss_mgrid:
	str	r0, [r4, #CT_MS_NEXT]
	b	.Lss_send
.Lss_every:
	tst	r6, #CF_MS_DUE
	beq	.Lss_out
.Lss_send:
	addw	r0, r4, #CT_REC
	bl	rec_measure
	mov	r3, r0
	addw	r2, r4, #CT_REC
	movs	r1, #C_MEASURE
	movs	r0, #FR_STREAM
	bl	out_counted
.Lss_out:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ rx_poll - step (5): received bytes through the frame parser, at most RX_BUDGET bytes and
@   one request per pass. Not run while an answer is pending, a job or an action is set or a
@   screenshot runs: the bytes stay in the RX ring (the driver NAKs when it is full).
@   CT_RXB holds the length bytes, seq .. payload and the CRC bytes. A frame with a bad CRC
@   or another type than request is dropped without an answer; the parser then looks for the
@   next 0xA5.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	rx_poll, %function
rx_poll:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =OWN_CTL
	ldr	r0, [r4, #CT_ANS_LEN]
	ldr	r1, [r4, #CT_J_ACTIVE]
	orrs	r0, r0, r1
	ldr	r1, [r4, #CT_ACT]
	orrs	r0, r0, r1
	bne	.Lrx_out
	bl	scr_busy
	cmp	r0, #0
	bne	.Lrx_out
	addw	r5, r4, #CT_RXB		@ r5 = frame buffer
	movw	r6, #RX_BUDGET		@ r6 = bytes left for this pass
.Lrx_byte:
	cmp	r6, #0
	beq	.Lrx_out
	subs	r6, r6, #1
	bl	usb_rx_get
	cmp	r0, #0
	blt	.Lrx_out		@ ring empty
	ldr	r1, [r4, #CT_RX_STATE]
	cmp	r1, #RX_SYNC
	beq	.Lrx_sync
	cmp	r1, #RX_LEN0
	beq	.Lrx_len0
	cmp	r1, #RX_LEN1
	beq	.Lrx_len1
@ RX_BODY: seq .. payload, then the CRC
	ldr	r2, [r4, #CT_RX_POS]
	strb	r0, [r5, r2]
	adds	r2, r2, #1
	str	r2, [r4, #CT_RX_POS]
	ldr	r3, [r4, #CT_RX_END]
	cmp	r2, r3
	blo	.Lrx_byte
	movs	r0, #RX_SYNC		@ frame complete
	str	r0, [r4, #CT_RX_STATE]
	subs	r7, r3, #2		@ r7 = bytes covered by the CRC
	movw	r0, #CRC16_INIT
	mov	r1, r5
	mov	r2, r7
	bl	crc16_update
	ldrb	r1, [r5, r7]
	adds	r2, r7, #1
	ldrb	r2, [r5, r2]
	orr	r1, r1, r2, lsl #8
	cmp	r0, r1
	bne	.Lrx_byte		@ bad CRC: dropped
	ldrb	r0, [r5, #3]		@ type
	cmp	r0, #FR_REQUEST
	bne	.Lrx_byte
	ldrb	r0, [r5, #2]		@ seq
	ldrb	r1, [r5, #4]		@ cmd
	adds	r2, r5, #5		@ payload
	subs	r3, r7, #5		@ payload length
	bl	cmd_dispatch
	b	.Lrx_out		@ one request per pass
.Lrx_sync:
	cmp	r0, #FR_SYNC
	bne	.Lrx_byte
	movs	r0, #RX_LEN0
	str	r0, [r4, #CT_RX_STATE]
	b	.Lrx_byte
.Lrx_len0:
	strb	r0, [r5, #0]
	movs	r0, #RX_LEN1
	str	r0, [r4, #CT_RX_STATE]
	b	.Lrx_byte
.Lrx_len1:
	strb	r0, [r5, #1]
	ldrb	r1, [r5, #0]
	orr	r1, r1, r0, lsl #8	@ r1 = length
	movs	r0, #RX_SYNC
	str	r0, [r4, #CT_RX_STATE]
	cmp	r1, #FR_LEN_MIN
	blo	.Lrx_byte
	movw	r2, #FR_LEN_MAX
	cmp	r1, r2
	bhi	.Lrx_byte
	adds	r1, r1, #4		@ length bytes + body + CRC bytes
	str	r1, [r4, #CT_RX_END]
	movs	r0, #2
	str	r0, [r4, #CT_RX_POS]
	movs	r0, #RX_BODY
	str	r0, [r4, #CT_RX_STATE]
	b	.Lrx_byte
.Lrx_out:
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ============================================================================
@ Tables
@ ============================================================================
	.section .rodata.own.ctl,"a",%progbits
	.p2align 2
@ level floats 0.1, 0.3, 0.6 V (fn_0800d940 mode 1 values, fn_0800b4c8 default 0x3f19999a)
	.global	tab_level
tab_level:
	.word	0x3DCCCCCD, 0x3E99999A, 0x3F19999A
@ bias floats 0.0, 0.5 V (fn_0800d940 mode 2)
	.global	tab_bias
tab_bias:
	.word	0x00000000, 0x3F000000
@ frequencies in Hz (fn_0800d940 mode 0 cycle), index 5 = 60 Hz appended (S2.12, meas.s
@ own_freq_step; the hosts' indices 0..4 unchanged)
	.global	tab_freq
tab_freq:
	.word	100, 120, 1000, 10000, 100000, 60
@ sorting scales 0.001, 1.0, 1000.0, 1e6 (fn_0800e224 literals 0x0800E484.., s3); also read by
@ dset.s ds_compare
	.global	tab_scale
tab_scale:
	.word	0x3A83126F, 0x3F800000, 0x447A0000, 0x49742400
@ RAM-only words compared for SETTING_CHANGED (entry 2 is a byte)
ram_words:
	.word	V_HOLD, V_DISP_A8, V_MAIN_ROW, V_SECONDARY
