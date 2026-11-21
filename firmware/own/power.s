@ power.s - automatic power-off of our build: the Off Time setting and the low-voltage countdown.
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ Two vendor defects of V1.1 (VENDOR_FIXES_DESIGN.md F2, F3; NOTES.md "User functions, settings
@ and measured values of V1.1"):
@ - F2: the menu setting Off Time (word 0x20001164: 0 off, 1 5 min, 2 15 min, 3 30 min) is stored
@   and shown, but nothing reads it.
@ - F3: 0x0800C724 shows the popup "Shutdown Countdown" with 10 when the supply voltage float
@   0x20005100 is at its floor 3.2 V, but nothing counts the word 0x20005118 down and nothing
@   switches the meter off; 0x0800C724 (and with it the voltage refresh 0x080092CC) runs only
@   when a screen is built (0x0800C848).
@
@ pwr_step is called once per main-loop pass by ctl_loop (ctl.s), after job_step and before
@ inj_post. Rules:
@ - Nothing at all once the meter's power-off path has run (ctl.s CF_OFF_WAIT) or in the
@   powered-off mode (CF_OFF).
@ - Idle time: the tick of the last activity is kept. Activity, checked every pass: an event in
@   the slot 0x20001192 (before inj_post only the key scan 0x080094A0 posts there: every event
@   it held was consumed by 0x08009400 in the previous pass's key_step, 0x08009494) or a key
@   held now (halfword 0x20000008, written only by the scan); an answer frame left since the
@   last pass (ctl.s CT_ANS_T changed: every request is answered, a request that runs as a job
@   while the job is active). Held (the tick is taken every pass): while the host holds DTR
@   (usb_dtr: a connected companion keeps the meter on), while a calibration runs (word
@   0x200050E4 != 0) and while a job of ctl.s is active (CT_J_ACTIVE).
@ - Once a second (on a 1000 ms grid of the GUI tick 0x20000480; a pass more than 2 s late, a
@   flash save, restarts the grid):
@   (a) the power-off requested before (below) and not yet started: started now when no key
@       injection is in flight;
@   (b) low voltage: 0x080092CC refreshes 0x20005100 (128-sample mean of the ADC4 buffer
@       0x20005D38 * 6.6 / 4095, stored only when it moved by more than 0.02 V). At or below
@       3.2 V (the word compared as a signed integer with 0x404CCCCD, as 0x0800C724 does):
@       no countdown yet (0x20005118 = 0): as 0x0800C7B4..0x0800C7C4 (the log line 0x0800C7B0
@       left out):
@       0 to 0x20005110 and 0x20005114 (the main loop skips one call of 0x0800A7EC and of
@       0x0800BD5C), 10 to 0x20005118, the popup built by 0x0800CF68(1, 10); a countdown
@       running: 0x20005118 - 1 stored and shown (0x0800CF68(0, n): the number text only);
@       at 0 the power-off is requested. Above 3.2 V with a countdown running (0x20005118 !=
@       0): 0x20005118 = 0 and the popup removed as 0x0800C7D8..0x0800C7E8 (0x08023690 of the
@       objects 0x20000290 and 0x20000294), each only while it still exists (below);
@   (c) Off Time 1 / 2 / 3 (other values: never) and the idle time at 5 / 15 / 30 min: the
@       power-off is requested. Before (c), after (b): the battery icon (F8, pwr_icon_step):
@       0x0800C724 sets the icon's picture only when a screen is built, so while the icon exists
@       (PF_ICON, set by own_batt_icon at fn_0800c848, cleared by pwr_obj_del when it or an
@       ancestor is deleted) every 30 s its level is worked out again and the picture changed
@       only when the level differs (owner, 2026-11-21: 30 s, not every second).
@   A requested power-off is final: it is started with ctl.s power_path (event 0xFE with mask 1
@   and the guard off, the path of POWER_OFF: 0x08009452 save through own_save, beep, 0x0800B274
@   PA8 low; on USB power off_step's powered-off mode), again once a second while it has not
@   run (an injection in flight, or 0x20001190 set: 0x08009468 then does nothing).
@
@ Popup objects (0x0800CF68 with r0 != 0; words from 0x2000028C): +4 = 0x20000290 the
@ background, created on the display record's word +0x10 (0x0801DD5C), which is the active
@ screen (fix.s: 0x08023690 clears +0x10 when it deletes it); +8 = 0x20000294 the panel, on the
@ record's word +0x1C (0x0801DD38); +0x18 = 0x200002A4 the number text, a descendant of
@ 0x20000294. A screen change deletes the old screen with 0x08023690 and with it the background:
@ the word 0x20000290 then names freed memory, and the vendor's own removal (0x0800C724 at a
@ screen build above 3.2 V with 0x20005118 != 0, bl at 0x0800C7DE) deletes it a second time. So
@ the existence of both objects is tracked (PW_LIVE): set when the popup is built (by pwr_step,
@ or by 0x0800C724 at a screen build: then 0x20005118 != 0 is found while nothing is tracked),
@ cleared per object by pwr_obj_del, which fix.s own_obj_del calls at every entry of 0x08023690,
@ when the object being deleted is the tracked object or one of its ancestors (parent word +4,
@ fn_08023FA4); the vendor's call from 0x0800C7DE for a background that is gone is not carried
@ out (pwr_obj_del returns r12 = 1). 0x08023690 is the only removal that can reach them:
@ the other one, the child removal 0x08023520, is called only for 0x20000018 (a child of the
@ settings root, ui_42.s fn_0800d6e4) and the objects 0x20005918[i] (children of 0x200058F0[i],
@ ui_44.s fn_0800f294), never for a screen or a record-word object. The number is redrawn
@ only while the panel exists.
@
@ RAM: the area O_PWR of own.inc (offsets below); ctl.s's words (ctl.inc) are read only.
@ Flash: nothing here addresses the flash controller; the save of the power-off path is own_save
@ (save.s).
@ Calling convention: AAPCS; r0..r3, r12, the flags and s0..s15 clobbered, r4..r11 kept;
@ pwr_obj_del keeps r0, r3 (see there).

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"
	.include "own/ctl.inc"

@ RAM of power.s (offsets from OWN_PWR; own_start clears it)
	.equ	PW_FLAGS,	0x00		@ PF_* bits
	.equ	PW_IDLE_T,	0x04		@ tick of the last activity
	.equ	PW_SEC_T,	0x08		@ tick of the last once-a-second step
	.equ	PW_ANS_SEEN,	0x0C		@ ctl.s CT_ANS_T as read in the last pass
	.equ	PW_LIVE,	0x10		@ PL_* bits: popup objects that exist
	.equ	PW_REASON,	0x14		@ why the power-off was requested: RS_*
	.equ	PW_STARTS,	0x18		@ number of power_path calls
	.equ	PW_ICON_T,	0x1C		@ tick of the last battery icon check (F8)
	.equ	PW_END,		0x20

	.if	PW_END > PWR_SIZE
	.error	"power.s: its RAM does not fit O_PWR"
	.endif

	.equ	PF_PRIMED,	0x01		@ first pass done (ticks taken)
	.equ	PF_REQ,		0x02		@ power-off requested
	.equ	PF_ICON,	0x100		@ the battery icon object 0x2000028C exists (F8)
	.equ	PF_LVL_SHIFT,	9		@ bits 9..11: the level the icon shows, 0..4
	.equ	PF_LVL_MASK,	0xE00
	.equ	PL_BG,		0x01		@ 0x20000290 exists
	.equ	PL_PANEL,	0x02		@ 0x20000294 exists
	.equ	PL_TRACK,	0x80		@ the popup is tracked
	.equ	PL_ALL,		PL_TRACK | PL_BG | PL_PANEL
	.equ	RS_NONE,	0
	.equ	RS_OFFTIME,	1		@ Off Time reached
	.equ	RS_LOWV,	2		@ low-voltage countdown at 0

	.equ	SEC_MS,		1000		@ the once-a-second period, GUI tick ms
	.equ	ICON_MS,	30000		@ the battery icon period (owner, 2026-11-21)
	.equ	LOWV_FLOOR,	0x404CCCCD	@ 3.2f (0x0800C7FC, literal of 0x0800C724)
	.equ	LOWV_COUNT,	10		@ start of the countdown (0x0800C7B8)
	.equ	LR_VENDOR_DEL,	0x0800C7E3	@ return address of the bl fn_08023690 at 0x0800C7DE
						@ (background removal of 0x0800C724), Thumb bit set

	.section .text.own.power,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ pwr_step - one pass, rules in the file header.
@ ----------------------------------------------------------------------------
	.global	pwr_step
	.thumb_func
	.type	pwr_step, %function
pwr_step:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =OWN_PWR
	ldr	r5, =OWN_CTL
	ldr	r0, [r5, #CT_FLAGS]
	tst	r0, #(CF_OFF | CF_OFF_WAIT)
	bne	.Lps_out		@ the power-off path ran: nothing more
	ldr	r6, [r4, #PW_FLAGS]
	tst	r6, #PF_PRIMED
	bne	.Lps_track
	bl	now			@ first pass: idle from now, the grid starts now
	str	r0, [r4, #PW_IDLE_T]
	str	r0, [r4, #PW_SEC_T]
	ldr	r0, [r5, #CT_ANS_T]
	str	r0, [r4, #PW_ANS_SEEN]
	orr	r6, r6, #PF_PRIMED
	str	r6, [r4, #PW_FLAGS]
@ popup tracking
.Lps_track:
	ldr	r0, =V_LOWV_POPUP
	ldr	r0, [r0]
	cmp	r0, #0
	bne	.Lps_shown
	str	r0, [r4, #PW_LIVE]	@ no countdown: nothing tracked
	b	.Lps_act
.Lps_shown:
	ldr	r0, [r4, #PW_LIVE]
	tst	r0, #PL_TRACK
	bne	.Lps_act
	movw	r0, #PL_ALL		@ built by 0x0800C724 at a screen build
	str	r0, [r4, #PW_LIVE]
@ activity and the held conditions
.Lps_act:
	ldr	r0, [r5, #CT_ANS_T]
	ldr	r1, [r4, #PW_ANS_SEEN]
	str	r0, [r4, #PW_ANS_SEEN]
	cmp	r0, r1
	bne	.Lps_reset		@ an answer left since the last pass
	ldr	r0, =V_KEY_CODE
	ldrh	r0, [r0]
	cmp	r0, #0
	bne	.Lps_reset		@ a key event of the scan
	ldr	r0, =V_KEYS_DOWN
	ldrh	r0, [r0]
	cmp	r0, #0
	bne	.Lps_reset		@ a key held
	ldr	r0, [r5, #CT_J_ACTIVE]
	cmp	r0, #0
	bne	.Lps_reset		@ a job runs
	ldr	r0, =V_CAL_RUN
	ldr	r0, [r0]
	cmp	r0, #0
	bne	.Lps_reset		@ a calibration runs
	bl	usb_dtr
	cmp	r0, #0
	beq	.Lps_second
.Lps_reset:
	bl	now
	str	r0, [r4, #PW_IDLE_T]
@ once a second
.Lps_second:
	ldr	r0, [r4, #PW_SEC_T]
	bl	since
	movw	r1, #SEC_MS
	cmp	r0, r1
	blo	.Lps_out
	ldr	r2, [r4, #PW_SEC_T]
	add	r2, r2, r1		@ next point of the grid
	cmp	r0, r1, lsl #1
	blo	.Lps_grid
	bl	now			@ more than 2 s late: the grid restarts now
	mov	r2, r0
.Lps_grid:
	str	r2, [r4, #PW_SEC_T]
	ldr	r6, [r4, #PW_FLAGS]
	tst	r6, #PF_REQ
	bne	.Lps_start		@ (a)
@ (b) low voltage
	bl	fn_080092cc		@ 0x20005100 refreshed
	ldr	r0, =V_SUPPLY
	ldr	r0, [r0]
	ldr	r1, =LOWV_FLOOR
	ldr	r7, =V_LOWV_POPUP
	ldr	r8, [r7]		@ r8 = countdown word 0x20005118
	cmp	r0, r1
	bgt	.Lps_above
	cmp	r8, #0
	bne	.Lps_count
	ldr	r0, =V_CMP_DUE		@ start, as 0x0800C7B0..0x0800C7C4
	movs	r1, #0
	str	r1, [r0]		@ 0x20005110 = 0
	ldr	r0, =V_SWEEP_ON
	str	r1, [r0]		@ 0x20005114 = 0
	movs	r1, #LOWV_COUNT
	str	r1, [r7]		@ 0x20005118 = 10
	movs	r0, #1
	bl	fn_0800cf68		@ build the popup, number 10
	movw	r0, #PL_ALL
	str	r0, [r4, #PW_LIVE]
	b	.Lps_idle
.Lps_count:
	sub	r8, r8, #1
	str	r8, [r7]		@ 0x20005118 - 1
	ldr	r0, [r4, #PW_LIVE]
	tst	r0, #PL_PANEL
	beq	.Lps_counted		@ the panel is gone: no number to redraw
	movs	r0, #0
	mov	r1, r8
	bl	fn_0800cf68		@ the number text only
.Lps_counted:
	cmp	r8, #0
	bne	.Lps_idle
	movs	r0, #RS_LOWV
	b	.Lps_request
.Lps_above:
	cmp	r8, #0
	beq	.Lps_idle
	bl	pwr_popup_off
@ (c) Off Time; before it the battery icon (F8, every 30 s)
.Lps_idle:
	bl	pwr_icon_step
	ldr	r0, =V_OFFTIME
	ldr	r0, [r0]
	subs	r0, r0, #1		@ 1..3 -> 0..2; 0 (off) wraps above 2
	cmp	r0, #2
	bhi	.Lps_out
	ldr	r1, =pwr_off_ms
	ldr	r7, [r1, r0, lsl #2]	@ r7 = limit in ms
	ldr	r0, [r4, #PW_IDLE_T]
	bl	since
	cmp	r0, r7
	blo	.Lps_out
	movs	r0, #RS_OFFTIME
.Lps_request:
	str	r0, [r4, #PW_REASON]
	ldr	r6, [r4, #PW_FLAGS]
	orr	r6, r6, #PF_REQ
	str	r6, [r4, #PW_FLAGS]
@ (a) start the requested power-off
.Lps_start:
	ldr	r0, [r5, #CT_I_STATE]
	cmp	r0, #IS_IDLE
	bne	.Lps_out		@ an injection in flight: the next second
	ldr	r0, [r4, #PW_STARTS]
	adds	r0, r0, #1
	str	r0, [r4, #PW_STARTS]
	bl	power_path
.Lps_out:
	pop	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ pwr_popup_off - the countdown stops: 0x20005118 = 0, then the popup objects removed with
@   0x08023690 as 0x0800C7D8..0x0800C7E8 does (background 0x20000290, then panel 0x20000294),
@   each only while PW_LIVE says it exists (re-read after the first removal: pwr_obj_del
@   clears the bits of the objects it takes along). Nothing tracked afterwards.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	pwr_popup_off, %function
pwr_popup_off:
	push	{r4, lr}
	ldr	r4, =OWN_PWR
	ldr	r0, =V_LOWV_POPUP
	movs	r1, #0
	str	r1, [r0]		@ as 0x0800C7D8
	ldr	r0, [r4, #PW_LIVE]
	tst	r0, #PL_BG
	beq	.Lpo_panel
	ldr	r0, =V_POPUP_OBJS
	ldr	r0, [r0, #4]
	bl	fn_08023690		@ background
.Lpo_panel:
	ldr	r0, [r4, #PW_LIVE]
	tst	r0, #PL_PANEL
	beq	.Lpo_done
	ldr	r0, =V_POPUP_OBJS
	ldr	r0, [r0, #8]
	bl	fn_08023690		@ panel with its number
.Lpo_done:
	movs	r0, #0
	str	r0, [r4, #PW_LIVE]
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ pwr_obj_del - called by fix.s own_obj_del at the entry of 0x08023690, r0 = the object about
@   to be deleted (still intact, unless named by a stale word), r1 = the return address of the
@   call of 0x08023690. Returns r12 = 1 when the deletion must not be carried out, else 0.
@   - r1 = 0x0800C7E3 (0x0800C724 removes the background 0x20000290) while the popup is tracked
@     and the background is gone: r12 = 1 (r0 names freed memory).
@   - When 0x20005118 != 0 and nothing is tracked, the popup was built by 0x0800C724 since the
@     last pass: both objects are tracked from here.
@   - For each tracked object the chain object, parent (+4), ... up to 0 is walked (every object
@     on it exists: the tracked one does, and so do its ancestors); when r0 is on it, the object
@     goes away with r0 and its bit is cleared.
@   Uses r1, r2, r12 and the flags; r0 and r3 kept.
@ ----------------------------------------------------------------------------
	.global	pwr_obj_del
	.thumb_func
	.type	pwr_obj_del, %function
pwr_obj_del:
	ldr	r2, =LR_VENDOR_DEL
	cmp	r1, r2
	ldr	r1, =OWN_PWR
	ldr	r2, [r1, #PW_LIVE]
	bne	.Lpd_track		@ flags of the cmp: another caller
	and	r12, r2, #(PL_TRACK | PL_BG)
	cmp	r12, #PL_TRACK
	bne	.Lpd_track
	movs	r12, #1			@ the vendor's removal of a background that is gone
	bx	lr
.Lpd_track:
	tst	r2, #PL_TRACK
	bne	.Lpd_bg
	ldr	r12, =V_LOWV_POPUP
	ldr	r12, [r12]
	cmp	r12, #0
	beq	.Lpd_out		@ no popup
	movw	r2, #PL_ALL
.Lpd_bg:
	tst	r2, #PL_BG
	beq	.Lpd_panel
	ldr	r12, =V_POPUP_OBJS
	ldr	r12, [r12, #4]		@ background
.Lpd_bg_up:
	cmp	r12, #0
	beq	.Lpd_panel
	cmp	r12, r0
	beq	.Lpd_bg_gone
	ldr	r12, [r12, #4]		@ its parent
	b	.Lpd_bg_up
.Lpd_bg_gone:
	bic	r2, r2, #PL_BG
.Lpd_panel:
	tst	r2, #PL_PANEL
	beq	.Lpd_store
	ldr	r12, =V_POPUP_OBJS
	ldr	r12, [r12, #8]		@ panel
.Lpd_panel_up:
	cmp	r12, #0
	beq	.Lpd_store
	cmp	r12, r0
	beq	.Lpd_panel_gone
	ldr	r12, [r12, #4]		@ its parent
	b	.Lpd_panel_up
.Lpd_panel_gone:
	bic	r2, r2, #PL_PANEL
.Lpd_store:
	str	r2, [r1, #PW_LIVE]
.Lpd_out:				@ every exit that carries out the deletion (r1 = OWN_PWR)
	ldr	r2, [r1, #PW_FLAGS]
	tst	r2, #PF_ICON
	beq	.Lpd_done
	ldr	r12, =V_POPUP_OBJS
	ldr	r12, [r12]		@ the battery icon
.Lpd_icon_up:
	cmp	r12, #0
	beq	.Lpd_done
	cmp	r12, r0
	beq	.Lpd_icon_gone
	ldr	r12, [r12, #4]		@ its parent
	b	.Lpd_icon_up
.Lpd_icon_gone:
	bic	r2, r2, #PF_ICON	@ goes away with r0
	str	r2, [r1, #PW_FLAGS]
.Lpd_done:
	movs	r12, #0			@ carry out the deletion
	bx	lr

@ ----------------------------------------------------------------------------
@ own_batt_icon - replaces the tail call `b.w fn_0800c724` of fn_0800c848 (ui_41.s, .ifdef OWN):
@   fn_0800c848 has just made the battery icon object 0x2000028C (on a build of the measure
@   screen or of the first screen). fn_0800c724 runs as before (voltage refreshed, the icon
@   picture of its level, the low-voltage popup); then the icon is marked as existing (PF_ICON)
@   with the level it shows (from 0x20005100 as fn_0800c724 left it, batt_level: the same
@   compares), and the 30 s period of pwr_icon_step starts now. Returns fn_0800c724's r0.
@ ----------------------------------------------------------------------------
	.global	own_batt_icon
	.thumb_func
	.type	own_batt_icon, %function
own_batt_icon:
	push	{r4, r5, r6, lr}
	bl	fn_0800c724
	mov	r5, r0			@ its result
	ldr	r0, =V_SUPPLY
	ldr	r0, [r0]
	bl	batt_level
	ldr	r4, =OWN_PWR
	ldr	r1, [r4, #PW_FLAGS]
	bic	r1, r1, #(PF_ICON | PF_LVL_MASK)
	orr	r1, r1, r0, lsl #PF_LVL_SHIFT
	orr	r1, r1, #PF_ICON
	str	r1, [r4, #PW_FLAGS]
	bl	now
	str	r0, [r4, #PW_ICON_T]
	mov	r0, r5
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ pwr_icon_step - from pwr_step's once-a-second step (b), after the voltage refresh: while the
@   icon exists (PF_ICON), every 30 s (since(PW_ICON_T) >= 30000; the next point 30 s on, or
@   now when 60 s or more have passed) the level is worked out from 0x20005100 (batt_level);
@   only when it differs from the level shown, the icon gets the picture of the new level
@   (fn_08021c14(object, picture), as fn_0800c724 at 0x0800C786; it invalidates the old and the
@   new area itself) and the shown level is stored. pwr_step and the GUI's timer walk both run
@   in the main loop, so this never meets a half-done GUI call. AAPCS.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	pwr_icon_step, %function
pwr_icon_step:
	push	{r4, lr}
	ldr	r4, =OWN_PWR
	ldr	r0, [r4, #PW_FLAGS]
	tst	r0, #PF_ICON
	beq	.Lpi_out		@ no icon on this screen
	ldr	r0, [r4, #PW_ICON_T]
	bl	since
	movw	r1, #ICON_MS
	cmp	r0, r1
	blo	.Lpi_out
	ldr	r2, [r4, #PW_ICON_T]
	add	r2, r2, r1		@ next point of the 30 s grid
	cmp	r0, r1, lsl #1
	blo	.Lpi_grid
	bl	now			@ 60 s or more: the grid restarts now
	mov	r2, r0
.Lpi_grid:
	str	r2, [r4, #PW_ICON_T]
	ldr	r0, =V_SUPPLY
	ldr	r0, [r0]
	bl	batt_level
	ldr	r1, [r4, #PW_FLAGS]
	ubfx	r2, r1, #PF_LVL_SHIFT, #3
	cmp	r0, r2
	beq	.Lpi_out		@ the icon shows this level already
	bic	r1, r1, #PF_LVL_MASK
	orr	r1, r1, r0, lsl #PF_LVL_SHIFT
	str	r1, [r4, #PW_FLAGS]
	ldr	r1, =pwr_icon_pics
	ldr	r1, [r1, r0, lsl #2]	@ picture of the level
	ldr	r0, =V_POPUP_OBJS
	ldr	r0, [r0]		@ the icon object
	bl	fn_08021c14
.Lpi_out:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ batt_level - r0 = supply voltage float bits (0x20005100) -> r0 = icon level 0..4: the number
@   of the thresholds 3.4, 3.6, 3.8, 4.0 V (cmd.s tab_batt) the value is above, compared as
@   signed integers as 0x0800C724 does. Uses r1, r2, r12.
@ ----------------------------------------------------------------------------
	.global	batt_level
	.thumb_func
	.type	batt_level, %function
batt_level:
	ldr	r1, =tab_batt
	movs	r2, #0
.Lbl_next:
	ldr	r12, [r1, r2, lsl #2]
	cmp	r0, r12
	ble	.Lbl_done
	adds	r2, r2, #1
	cmp	r2, #4
	blo	.Lbl_next
.Lbl_done:
	mov	r0, r2
	bx	lr

	.ltorg

	.section .rodata.own.power,"a",%progbits
	.p2align 2
@ Off Time limits in ms for the settings 1, 2, 3 (texts "5min / 15min / 30min", T_OFFTIME)
pwr_off_ms:
	.word	5 * 60000, 15 * 60000, 30 * 60000
@ battery icon pictures of the levels 0..4, as 0x0800C724 picks them (app_02.s, descriptors in
@ rodata_02.s)
pwr_icon_pics:
	.word	d_08044440, d_0804459c, d_080446e8, d_08044844, d_08044990
