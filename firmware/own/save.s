@ save.s - settings / calibration storage of our build: load, save, recovery, flash primitives
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ Replaces the vendor copy 0x08014B74 (bl at 0x08028030) and the vendor save 0x08014B94 (bl at
@ 0x08009474, 0x0800B5C0, 0x0800BD1A, 0x0800D922) by a save to two copies that checks
@ every status and reads back (revision 4). The vendor save erased the only copy first and programmed it without a status
@ check or read-back; its word program 0x08008DC0 lacks the five NOPs of the N32G45x user manual
@ 3.2.1.4.2.
@
@ Flash layout (own.inc): copy A 0x0807F000..0x0807FFFF (block 0x0807F000..0x0807FC13 in the
@ vendor format, trailer 0x0807FFF8 sequence, 0x0807FFFC CRC-32), copy B 0x08066000..0x08066FFF
@ (same offsets). CRC-32 (reflected, polynomial 0xEDB88320, initial and final XOR 0xFFFFFFFF, as
@ starter/starter.s crc32) over the 0xC14 block bytes, then the 4 sequence bytes.
@ A copy is valid when its first and last block words are 0x12345678 and its trailer CRC
@ matches; copy A is also valid with both trailer words 0xFFFFFFFF (vendor format).
@
@ Flash primitives: every erase and program goes through flash_erase_page / flash_word, which
@ refuse every address outside the gate: the four settings pages 0x08066000, 0x08066800,
@ 0x0807F000, 0x0807F800, and, only while ctl.s has opened it with flash_boot_gate, slot A
@ 0x0806F000..0x08074FFF or slot B 0x08075000..0x0807AFFF and the record pages
@ 0x08068000..0x08068FFF, and, only while ocal.s has opened it with flash_ocal_gate (SVO_OCAL =
@ OCAL_BASE exactly), the own calibration area 0x08062000..0x08065FFF.
@ Page 0, the application area, slot F and the option bytes are never reachable. FLASH_CTRL is written as a whole value (SMPSEL 0: SMP1 refuses a word that is not
@ erased; no interrupt enable: the vendor code sets none, it only ORs PG / PER / START / LOCK
@ and ANDs them away, periph_34.s fn_08008d30 / fn_08008dc0 / fn_08008db0). Each primitive
@ leaves the controller locked.
@
@ Watchdog: own_feed before and after every page erase and after every 256 words. In this file
@ feeds happen only inside saves, recovery calls and save_resume, which all run from the main loop
@ after V1.1 started the IWDG (0x08010178, system_40.s fn_08027ff4 after the load). own_feed's
@ other callers: own_start (ctl.s, only with the hand-over bit HO_WDG: the slot's IWDG already
@ runs), xtal_fault (xtal.s, every 10 ms on the crystal-fault screen) and the own calibration
@ write (ocal.s, after every 256 words and after the commit word, from the main loop). The vendor
@ start-up feeds as well: its wait fn_08011c68 (periph_35.s) writes 0xAAAA after every TIM7 wait
@ of 1000 counts, before the IWDG start. own_load writes no
@ flash and feeds nothing: it runs at 0x08028030, before that start, and the manual leaves open
@ whether 0xAAAA starts a stopped IWDG (16.4.1 says it does, the description before 16.3.1 says
@ 0xCCCC does; V1.1 itself writes 0xAAAA just before 0xCCCC, 0x08010178). The rewrite
@ of an interrupted copy A, which belongs to the load, is therefore done by save_resume, which
@ ctl_loop calls once per pass.
@
@ RAM (own.inc): the staging buffer OWN_STAGE (0xC14 bytes) and the save.s words at OWN_SAVE;
@ own_injected (ctl.s) is only read. No section of RAM is defined here.
@
@ Stage 2 / 2F (revision 6): own_save skips the write when both copies
@ already hold the staged block (S2.10, SV_SAME); own_load repairs invalid setting words of the
@ loaded block in RAM only (S2.11, load_fix; the calibration tables are not examined); every block
@ our firmware stages for a write from RAM or from the host holds 100, never 60, as its frequency
@ (S2.12 D60-a, stage_freq_fix in own_save, save_accept_defaults and save_write_block).
@ Stage 3 (revision 7): while the calibration sweep of cal.s runs, own_save and
@ save_accept_defaults stage the frequency, level, bias, speed and 0x200010C0 words of before the
@ sweep (stage_cal_fix, from cal.s's recording), so no saved copy holds the sweep's settings.
@
@ Calling convention of every exported function: AAPCS; r0..r3, r12 and the flags clobbered,
@ r4..r11 kept, no FPU register used. Stack: at most 72 bytes below the caller's SP.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

@ copy_check result bits
	.equ	CK_MARKERS,	0x01		@ first and last block word 0x12345678
	.equ	CK_CRC,		0x02		@ trailer CRC matches (only checked with markers)
	.equ	CK_BLANK,	0x04		@ both trailer words 0xFFFFFFFF

@ eval_copies result bits
	.equ	EV_A_VALID,	0x01
	.equ	EV_A_VENDOR,	0x02		@ A valid in the vendor format (no trailer)
	.equ	EV_A_MARKERS,	0x04		@ A has both markers (valid or not)
	.equ	EV_B_VALID,	0x08

@ save_stage modes
	.equ	MODE_ORDER,	0		@ order of step 3 (from own_save_flags)
	.equ	MODE_A,		1		@ copy A only
	.equ	MODE_B,		2		@ copy B only
	.equ	MODE_BA,	3		@ B, then A

	.section .rodata.own.save,"a",%progbits
	.p2align 2
@ gate_ranges - the settings pages, [start, end) pairs: copy B, then copy A.
gate_ranges:
	.word	SET_B, SET_B + SET_SIZE
	.word	SET_A, SET_A + SET_SIZE
@ load_freqs - the five frequencies a loaded block may hold (load_fix, S2.11)
load_freqs:
	.word	100, 120, 1000, 10000, 100000
@ load_levels - load_fix's floats: the levels 0.1, 0.3, 0.6 (fn_0800d940 mode 1), the default
@   nominal 1000.0, the tolerance limit 99.9 and the default tolerance 5.0 (fn_0800b4c8)
load_levels:
	.word	0x3DCCCCCD, 0x3E99999A, 0x3F19999A, 0x447A0000, 0x42C7CCCD, 0x40A00000

	.section .text.own.save,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ own_feed - reload the independent watchdog: 0xAAAA to IWDG_KEY 0x40003000
@   (as V1.1 0x08009390). No arguments, no result. Uses r0, r1 only.
@ ----------------------------------------------------------------------------
	.global	own_feed
	.thumb_func
	.type	own_feed, %function
own_feed:
	ldr	r0, =IWDG_KEY
	movw	r1, #IWDG_FEED
	str	r1, [r0]
	bx	lr

@ ----------------------------------------------------------------------------
@ own_crc32_update - run bytes through the CRC-32 register.
@   r0 = register (0xFFFFFFFF at the start), r1 = address, r2 = byte count
@   (0 allowed). Returns r0 = the new register (the CRC-32 is its complement),
@   r1 = address after the bytes, r2 = 0. Uses r3, r12.
@ own_crc32 - r0 = address, r1 = byte count -> r0 = CRC-32 of those bytes.
@   Uses r1..r3, r12.
@ ----------------------------------------------------------------------------
	.global	own_crc32_update
	.thumb_func
	.type	own_crc32_update, %function
own_crc32_update:
	cmp	r2, #0
	beq	.Lcu_out
	ldr	r12, =0xEDB88320
.Lcu_byte:
	ldrb	r3, [r1], #1
	eors	r0, r0, r3
	movs	r3, #8
.Lcu_bit:
	lsrs	r0, r0, #1		@ carry = bit shifted out
	it	cs
	eorcs	r0, r0, r12
	subs	r3, r3, #1
	bne	.Lcu_bit
	subs	r2, r2, #1
	bne	.Lcu_byte
.Lcu_out:
	bx	lr

	.global	own_crc32
	.thumb_func
	.type	own_crc32, %function
own_crc32:
	push	{r4, lr}
	mov	r2, r1
	mov	r1, r0
	mvn	r0, #0
	bl	own_crc32_update
	mvns	r0, r0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ gate_ok - r0 = start address, r1 = length in bytes (> 0).
@   Returns r0 = FL_OK when [start, start + length) lies inside one settings
@   copy, or, while own_gate_slot holds SLOT_A or SLOT_B, inside that slot or
@   inside the record pages; or, while own_ocal_gate holds OCAL_BASE, inside
@   [OCAL_BASE, OCAL_END); otherwise FL_GATE. Any other value of
@   own_gate_slot / own_ocal_gate counts as closed. Uses r1..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	gate_ok, %function
gate_ok:
	adds	r1, r0, r1		@ r1 = end (exclusive)
	bcs	.Lg_no			@ wraps past 0xFFFFFFFF
	ldr	r2, =gate_ranges
	ldr	r3, [r2, #0]
	cmp	r0, r3
	blo	.Lg_set_a
	ldr	r3, [r2, #4]
	cmp	r1, r3
	bls	.Lg_yes
.Lg_set_a:
	ldr	r3, [r2, #8]
	cmp	r0, r3
	blo	.Lg_ocal
	ldr	r3, [r2, #12]
	cmp	r1, r3
	bls	.Lg_yes
.Lg_ocal:
	ldr	r2, =own_ocal_gate
	ldr	r2, [r2]		@ r2 = OCAL_BASE while ocal.s may write the area
	ldr	r3, =OCAL_BASE
	cmp	r2, r3
	bne	.Lg_boot		@ any other value counts as closed
	cmp	r0, r3
	blo	.Lg_boot
	ldr	r3, =OCAL_END
	cmp	r1, r3
	bls	.Lg_yes			@ [start, end) inside 0x08062000..0x08065FFF
.Lg_boot:
	ldr	r2, =own_gate_slot
	ldr	r2, [r2]		@ r2 = slot the BOOT writer may write
	ldr	r3, =SLOT_A
	cmp	r2, r3
	beq	.Lg_slot
	ldr	r3, =SLOT_B
	cmp	r2, r3
	bne	.Lg_no
.Lg_slot:
	cmp	r0, r2
	blo	.Lg_rec
	add	r3, r2, #SLOT_SIZE
	cmp	r1, r3
	bls	.Lg_yes
.Lg_rec:
	ldr	r3, =REC0
	cmp	r0, r3
	blo	.Lg_no
	ldr	r3, =REC_END
	cmp	r1, r3
	bls	.Lg_yes
.Lg_no:
	movs	r0, #FL_GATE
	bx	lr
.Lg_yes:
	movs	r0, #FL_OK
	bx	lr

@ ----------------------------------------------------------------------------
@ flash_boot_gate - open or close the BOOT part of the gate.
@   r0 = SLOT_A or SLOT_B: that slot and the record pages become writable;
@   r0 = 0: closed. Returns r0 = FL_OK; any other r0 closes the gate and
@   returns FL_GATE. Whether the slot is the free one
@   is decided by the caller (ctl.s). Uses r1, r2.
@ ----------------------------------------------------------------------------
	.global	flash_boot_gate
	.thumb_func
	.type	flash_boot_gate, %function
flash_boot_gate:
	ldr	r1, =own_gate_slot
	ldr	r2, =SLOT_A
	cmp	r0, r2
	beq	.Lbg_open
	ldr	r2, =SLOT_B
	cmp	r0, r2
	beq	.Lbg_open
	movs	r2, #0
	str	r2, [r1]
	cmp	r0, #0
	bne	.Lbg_bad
	movs	r0, #FL_OK
	bx	lr
.Lbg_bad:
	movs	r0, #FL_GATE
	bx	lr
.Lbg_open:
	str	r0, [r1]
	movs	r0, #FL_OK
	bx	lr

@ ----------------------------------------------------------------------------
@ flash_ocal_gate - open or close the own calibration area.
@   r0 = OCAL_BASE: 0x08062000..0x08065FFF becomes writable; r0 = 0: closed.
@   Returns r0 = FL_OK; any other r0 closes the gate and returns FL_GATE. Only
@   ocal.s calls it (ocal_commit, ocal_revoke), each closing it before it
@   returns. Uses r1, r2.
@ ----------------------------------------------------------------------------
	.global	flash_ocal_gate
	.thumb_func
	.type	flash_ocal_gate, %function
flash_ocal_gate:
	ldr	r1, =own_ocal_gate
	ldr	r2, =OCAL_BASE
	cmp	r0, r2
	beq	.Log_open
	movs	r2, #0
	str	r2, [r1]
	cmp	r0, #0
	bne	.Log_bad
	movs	r0, #FL_OK
	bx	lr
.Log_bad:
	movs	r0, #FL_GATE
	bx	lr
.Log_open:
	str	r0, [r1]
	movs	r0, #FL_OK
	bx	lr

@ ----------------------------------------------------------------------------
@ fl_unlock - clear FLASH_CTRL.LOCK when it is set (KEY1, then KEY2 to
@   FLASH_KEY; manual 3.2.1.3). The keys are written only while LOCK reads 1,
@   so no key is ever written to an unlocked controller. Returns r0 = FL_OK,
@   or FL_LOCKED when LOCK still reads 1. Uses r1.
@ fl_wait - wait until FLASH_STS.BUSY reads 0; returns r0 = FLASH_STS.
@   Uses r1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	fl_unlock, %function
fl_unlock:
	ldr	r0, =FLASH_BASE
	ldr	r1, [r0, #FL_CTRL]
	tst	r1, #CTRL_LOCK
	beq	.Lul_ok
	ldr	r1, =FLASH_KEY1
	str	r1, [r0, #FL_KEY]
	ldr	r1, =FLASH_KEY2
	str	r1, [r0, #FL_KEY]
	ldr	r1, [r0, #FL_CTRL]
	tst	r1, #CTRL_LOCK
	bne	.Lul_locked
.Lul_ok:
	movs	r0, #FL_OK
	bx	lr
.Lul_locked:
	movs	r0, #FL_LOCKED
	bx	lr

	.thumb_func
	.type	fl_wait, %function
fl_wait:
	ldr	r1, =FLASH_BASE
.Lfw_poll:
	ldr	r0, [r1, #FL_STS]
	tst	r0, #STS_BUSY
	bne	.Lfw_poll
	bx	lr

	.ltorg

@ ----------------------------------------------------------------------------
@ flash_erase_page - erase one 2 KiB page and check it (manual 3.2.1.4.1).
@   r0 = page base (multiple of 0x800, inside the gate).
@   Feeds the watchdog, unlocks, waits for BUSY 0, clears the STS flags,
@   CTRL = PER, ADD = page, CTRL = PER | START, waits, CTRL = LOCK, feeds
@   again, then checks STS (PGERR, PVERR, WRPERR, EVERR, ECCERR) and that all
@   512 words read 0xFFFFFFFF.
@   Returns r0 = FL_OK, FL_GATE (nothing done), FL_LOCKED, FL_HWERR or
@   FL_BLANK.
@ ----------------------------------------------------------------------------
	.global	flash_erase_page
	.thumb_func
	.type	flash_erase_page, %function
flash_erase_page:
	push	{r4, r5, r6, lr}
	mov	r4, r0			@ r4 = page base
	lsls	r1, r4, #21		@ low 11 address bits
	bne	.Le_gate
	mov	r1, #FLASH_PAGE
	bl	gate_ok
	cmp	r0, #FL_OK
	bne	.Le_out
	bl	own_feed
	bl	fl_unlock
	cmp	r0, #FL_OK
	bne	.Le_out
	bl	fl_wait
	ldr	r5, =FLASH_BASE
	movs	r0, #STS_CLEAR
	str	r0, [r5, #FL_STS]
	movs	r0, #CTRL_PER		@ SMPSEL 0, PER only
	str	r0, [r5, #FL_CTRL]
	str	r4, [r5, #FL_ADD]
	movs	r0, #CTRL_PER | CTRL_START
	str	r0, [r5, #FL_CTRL]
	bl	fl_wait
	mov	r6, r0			@ r6 = FLASH_STS after the erase
	movs	r0, #CTRL_LOCK		@ PER off, controller locked
	str	r0, [r5, #FL_CTRL]
	bl	own_feed
	tst	r6, #STS_ERASE_ERR
	bne	.Le_hw
	mov	r0, r4
	add	r1, r4, #FLASH_PAGE
.Le_check:
	ldr	r2, [r0], #4
	adds	r2, r2, #1		@ zero only for 0xFFFFFFFF
	bne	.Le_blank
	cmp	r0, r1
	blo	.Le_check
	movs	r0, #FL_OK
	pop	{r4, r5, r6, pc}
.Le_gate:
	movs	r0, #FL_GATE
	pop	{r4, r5, r6, pc}
.Le_hw:
	movs	r0, #FL_HWERR
	pop	{r4, r5, r6, pc}
.Le_blank:
	movs	r0, #FL_BLANK
.Le_out:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ flash_word - program one word and read it back (manual 3.2.1.4.2).
@   r0 = word address (multiple of 4, inside the gate), r1 = value.
@   A word that already holds the value is left as it is (FL_OK). A word that
@   holds another value and is not 0xFFFFFFFF is refused (FL_NOT_ERASED): SMP1
@   would refuse it too (PGERR). Otherwise: unlock, wait for BUSY 0, clear
@   the STS flags, CTRL = PG (SMPSEL 0), then with interrupts masked (an
@   exception entry reads the vector table from flash) the store, five NOPs
@   and the wait for BUSY 0; CTRL = LOCK; STS checked (PGERR, PVERR, WRPERR,
@   ECCERR); the word read back.
@   Returns r0 = FL_OK, FL_GATE, FL_NOT_ERASED, FL_LOCKED, FL_HWERR or
@   FL_VERIFY. PRIMASK is restored to its value at entry.
@ ----------------------------------------------------------------------------
	.global	flash_word
	.thumb_func
	.type	flash_word, %function
flash_word:
	push	{r4, r5, r6, lr}
	mov	r4, r0			@ r4 = address
	mov	r5, r1			@ r5 = value
	tst	r4, #3
	bne	.Lp_gate
	movs	r1, #4
	bl	gate_ok
	cmp	r0, #FL_OK
	bne	.Lp_out
	ldr	r0, [r4]
	cmp	r0, r5
	beq	.Lp_ok			@ already holds the value
	adds	r0, r0, #1
	bne	.Lp_used		@ neither the value nor erased
	bl	fl_unlock
	cmp	r0, #FL_OK
	bne	.Lp_out
	bl	fl_wait
	ldr	r6, =FLASH_BASE
	movs	r0, #STS_CLEAR
	str	r0, [r6, #FL_STS]
	movs	r0, #CTRL_PG		@ SMPSEL 0 (SMP1), PG only
	str	r0, [r6, #FL_CTRL]
	mrs	r3, PRIMASK
	cpsid	i
	str	r5, [r4]
	nop				@ five NOPs after the store: no flash read while
	nop				@ the word programs (manual 3.2.1.4.2)
	nop
	nop
	nop
	bl	fl_wait			@ keeps r3
	msr	PRIMASK, r3
	mov	r2, r0			@ r2 = FLASH_STS after programming
	movs	r0, #CTRL_LOCK		@ PG off, controller locked
	str	r0, [r6, #FL_CTRL]
	tst	r2, #STS_PROG_ERR
	bne	.Lp_hw
	ldr	r0, [r4]
	cmp	r0, r5
	bne	.Lp_verify
.Lp_ok:
	movs	r0, #FL_OK
	pop	{r4, r5, r6, pc}
.Lp_gate:
	movs	r0, #FL_GATE
	pop	{r4, r5, r6, pc}
.Lp_used:
	movs	r0, #FL_NOT_ERASED
	pop	{r4, r5, r6, pc}
.Lp_hw:
	movs	r0, #FL_HWERR
	pop	{r4, r5, r6, pc}
.Lp_verify:
	movs	r0, #FL_VERIFY
.Lp_out:
	pop	{r4, r5, r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ copy_check - r0 = copy base (SET_A or SET_B).
@   Returns r0 = CK_* bits, r1 = the trailer sequence word. The CRC is only
@   computed when both markers are present. Uses r2, r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	copy_check, %function
copy_check:
	push	{r4, r5, r6, lr}
	mov	r4, r0			@ r4 = copy base
	movs	r5, #0			@ r5 = CK_* bits
	ldr	r6, =BLK_MARKER
	ldr	r0, [r4, #0]
	cmp	r0, r6
	bne	.Lc_trailer
	ldr	r0, [r4, #BLK_MARK_END]
	cmp	r0, r6
	bne	.Lc_trailer
	movs	r5, #CK_MARKERS
	mvn	r0, #0
	mov	r1, r4
	movw	r2, #BLK_SIZE
	bl	own_crc32_update
	addw	r1, r4, #TRL_SEQ
	movs	r2, #4
	bl	own_crc32_update
	mvns	r0, r0
	ldr	r1, [r4, #TRL_CRC]
	cmp	r0, r1
	bne	.Lc_trailer
	orr	r5, r5, #CK_CRC
.Lc_trailer:
	ldr	r0, [r4, #TRL_SEQ]
	ldr	r1, [r4, #TRL_CRC]
	and	r2, r0, r1
	adds	r2, r2, #1		@ zero only when both are 0xFFFFFFFF
	bne	.Lc_out
	orr	r5, r5, #CK_BLANK
.Lc_out:
	mov	r1, r0
	mov	r0, r5
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ eval_copies - validity of both copies as they are in flash now.
@   Returns r0 = EV_* bits, r1 = sequence of A (0 when A is invalid or in the
@   vendor format), r2 = sequence of B (0 when B is invalid). Uses r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	eval_copies, %function
eval_copies:
	push	{r4, r5, r6, lr}
	ldr	r0, =SET_A
	bl	copy_check
	movs	r4, #0			@ r4 = EV_* bits
	movs	r5, #0			@ r5 = sequence of A
	tst	r0, #CK_MARKERS
	beq	.Lev_b
	orr	r4, r4, #EV_A_MARKERS
	tst	r0, #CK_BLANK
	beq	.Lev_a_crc
	orr	r4, r4, #EV_A_VALID | EV_A_VENDOR
	b	.Lev_b
.Lev_a_crc:
	tst	r0, #CK_CRC
	beq	.Lev_b
	orr	r4, r4, #EV_A_VALID
	mov	r5, r1
.Lev_b:
	ldr	r0, =SET_B
	bl	copy_check
	movs	r6, #0			@ r6 = sequence of B
	tst	r0, #CK_CRC		@ set only together with CK_MARKERS
	beq	.Lev_out
	orr	r4, r4, #EV_B_VALID
	mov	r6, r1
.Lev_out:
	mov	r0, r4
	mov	r1, r5
	mov	r2, r6
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ stage_copy - r0 = source address: copies 0xC14 bytes word by word into
@   OWN_STAGE. Uses r1..r3.
@ stage_markers - r0 = 0 when both markers of OWN_STAGE are 0x12345678.
@   Uses r1, r2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	stage_copy, %function
stage_copy:
	ldr	r1, =OWN_STAGE
	movw	r2, #BLK_SIZE
.Lsc_word:
	ldr	r3, [r0], #4
	str	r3, [r1], #4
	subs	r2, r2, #4
	bne	.Lsc_word
	bx	lr

	.thumb_func
	.type	stage_markers, %function
stage_markers:
	ldr	r1, =OWN_STAGE
	ldr	r2, =BLK_MARKER
	ldr	r0, [r1, #0]
	cmp	r0, r2
	bne	.Lsm_bad
	ldr	r0, [r1, #BLK_MARK_END]
	cmp	r0, r2
	bne	.Lsm_bad
	movs	r0, #0
	bx	lr
.Lsm_bad:
	movs	r0, #1
	bx	lr

@ ----------------------------------------------------------------------------
@ stage_freq_fix - S2.12 (D60-a): the frequency word of the staged block (OWN_STAGE + 0xBC8, the
@   offset of 0x20001144) 60 -> 100, any other value kept, so no copy our firmware writes holds
@   60 and the meter (and V1.1 after a downgrade) starts at 100 Hz. Uses r1, r2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	stage_freq_fix, %function
stage_freq_fix:
	ldr	r1, =OWN_STAGE + (V_FREQ - V_BLOCK)
	ldr	r2, [r1]
	cmp	r2, #60
	bne	.Lff_out
	movs	r2, #100
	str	r2, [r1]
.Lff_out:
	bx	lr

@ ----------------------------------------------------------------------------
@ stage_cal_fix - stage 3: while a sweep of
@   cal.s runs (OWN_CAL CAO_ON != 0, with a recording CAO_REC != 0) the staged block gets back the
@   words the calibration start changed: frequency, level, bias and speed (block offsets 0xBC8,
@   0xBBC, 0xBC0, 0xBD4) and the 0x78 bytes at block offset 0xB44 (0x200010C0) from the recording
@   (CAO_SFREQ .. CAO_SSPEED, CAO_REL). A save during the sweep (power key, low voltage, host)
@   then writes the settings of before the sweep; the calibration tables are not touched (cal.s
@   stores them only at the end). Called before stage_freq_fix, so a recorded 60 Hz is saved as
@   100. OWN_CAL is only read. Uses r0..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	stage_cal_fix, %function
stage_cal_fix:
	ldr	r2, =OWN_CAL
	ldr	r0, [r2, #CAO_ON]
	cmp	r0, #0
	beq	.Lcf_out
	ldr	r0, [r2, #CAO_REC]
	cmp	r0, #0
	beq	.Lcf_out
	ldr	r1, =OWN_STAGE
	ldr	r0, [r2, #CAO_SFREQ]
	str	r0, [r1, #V_FREQ - V_BLOCK]
	ldr	r0, [r2, #CAO_SLEVEL]
	str	r0, [r1, #V_LEVEL - V_BLOCK]
	ldr	r0, [r2, #CAO_SBIAS]
	str	r0, [r1, #V_BIAS - V_BLOCK]
	ldr	r0, [r2, #CAO_SSPEED]
	str	r0, [r1, #V_SPEED - V_BLOCK]
	add	r1, r1, #V_CAL_WORK - V_BLOCK
	add	r2, r2, #CAO_REL
	movs	r3, #30
.Lcf_copy:
	ldr	r0, [r2], #4
	str	r0, [r1], #4
	subs	r3, r3, #1
	bne	.Lcf_copy
.Lcf_out:
	bx	lr

@ ----------------------------------------------------------------------------
@ stage_same - S2.10: r0 = 1 when copy A is valid with its trailer (not the vendor format) and
@   copy B is valid, and both hold exactly the 0xC14 staged bytes; else 0. Every other case saves
@   as before (A in the vendor format gets its trailer; a stale or differing B is written; a
@   copy marked for rewrite fails its CRC and is never valid). Uses r1..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	stage_same, %function
stage_same:
	push	{r4, lr}
	bl	eval_copies
	and	r0, r0, #EV_A_VALID | EV_A_VENDOR | EV_B_VALID
	cmp	r0, #EV_A_VALID | EV_B_VALID
	bne	.Lsa_no
	ldr	r0, =SET_A
	bl	stage_equal
	cmp	r0, #0
	beq	.Lsa_no
	ldr	r0, =SET_B
	bl	stage_equal
	pop	{r4, pc}
.Lsa_no:
	movs	r0, #0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ stage_equal - r0 = copy base: r0 = 1 when its 0xC14 block bytes equal OWN_STAGE, else 0.
@   Uses r1..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	stage_equal, %function
stage_equal:
	ldr	r1, =OWN_STAGE
	movw	r2, #BLK_SIZE
.Lse_word:
	ldr	r3, [r0], #4
	ldr	r12, [r1], #4
	cmp	r3, r12
	bne	.Lse_diff
	subs	r2, r2, #4
	bne	.Lse_word
	movs	r0, #1
	bx	lr
.Lse_diff:
	movs	r0, #0
	bx	lr

@ ----------------------------------------------------------------------------
@ load_fix - S2.11, after own_load copied a valid block to 0x2000057C: each setting word outside
@   its valid values takes the value of fn_0800b4c8's defaults, in RAM only (nothing is written
@   to flash at load; the calibration tables are not examined):
@   frequency 0x20001144: 100, 120, 1000, 10000, 100000; 60 (never saved by our firmware, D60-a)
@     becomes 100, any other value 1000;
@   level 0x20001138: the floats 0.1, 0.3, 0.6, else 0.6; bias 0x2000113C: 0.0 or 0.5, else 0.0;
@     bias 0.5 with level 0.6 (the meter's keys never make it, fn_0800d940 mode 2): level 0.3;
@   Func 0x20001148 0..4 and range 0x2000114C 0..4, else 0; circuit 0x20001154 0..2, else 0;
@   compare quantity 0x20001178 1..3, else 1;
@   nominal 0x20001184: finite and above 0, else 1000.0;
@   tolerance 0x20001188: 0.0 .. 99.9, else 5.0.
@   (Speed, brightness, volume and language: the vendor's start-up clamp 0x08028046.. after the
@   load, system_40.s.) Uses r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	load_fix, %function
load_fix:
	ldr	r0, =V_BLOCK
	ldr	r1, [r0, #V_FREQ - V_BLOCK]
	cmp	r1, #60
	bne	.Llf_f5
	movs	r1, #100
	b	.Llf_fset
.Llf_f5:
	ldr	r2, =load_freqs
	movs	r3, #0
.Llf_fnext:
	ldr	r12, [r2, r3, lsl #2]
	cmp	r12, r1
	beq	.Llf_level		@ one of the five: kept
	adds	r3, r3, #1
	cmp	r3, #5
	blo	.Llf_fnext
	mov	r1, #1000
.Llf_fset:
	str	r1, [r0, #V_FREQ - V_BLOCK]
.Llf_level:
	ldr	r1, [r0, #V_LEVEL - V_BLOCK]
	ldr	r2, =load_levels
	ldr	r3, [r2, #0]
	cmp	r1, r3
	beq	.Llf_bias
	ldr	r3, [r2, #4]
	cmp	r1, r3
	beq	.Llf_bias
	ldr	r3, [r2, #8]
	cmp	r1, r3
	beq	.Llf_bias
	str	r3, [r0, #V_LEVEL - V_BLOCK]	@ the default 0.6
.Llf_bias:
	ldr	r1, [r0, #V_BIAS - V_BLOCK]
	cmp	r1, #0
	beq	.Llf_ints
	cmp	r1, #0x3F000000		@ 0.5
	beq	.Llf_bias5
	movs	r1, #0
	str	r1, [r0, #V_BIAS - V_BLOCK]
	b	.Llf_ints
.Llf_bias5:
	ldr	r1, [r0, #V_LEVEL - V_BLOCK]
	ldr	r3, [r2, #8]		@ 0.6
	cmp	r1, r3
	bne	.Llf_ints
	ldr	r3, [r2, #4]		@ 0.3, as the bias key sets it
	str	r3, [r0, #V_LEVEL - V_BLOCK]
.Llf_ints:
	ldr	r1, [r0, #V_FUNC - V_BLOCK]
	cmp	r1, #4
	bls	.Llf_range
	movs	r1, #0
	str	r1, [r0, #V_FUNC - V_BLOCK]
.Llf_range:
	ldr	r1, [r0, #V_RANGE - V_BLOCK]
	cmp	r1, #4
	bls	.Llf_circ
	movs	r1, #0
	str	r1, [r0, #V_RANGE - V_BLOCK]
.Llf_circ:
	ldr	r1, [r0, #V_CIRCUIT - V_BLOCK]
	cmp	r1, #2
	bls	.Llf_cmp
	movs	r1, #0
	str	r1, [r0, #V_CIRCUIT - V_BLOCK]
.Llf_cmp:
	ldr	r1, [r0, #V_CMP_TYPE - V_BLOCK]
	subs	r1, r1, #1
	cmp	r1, #2
	bls	.Llf_nom
	movs	r1, #1
	str	r1, [r0, #V_CMP_TYPE - V_BLOCK]
.Llf_nom:
	ldr	r1, [r0, #V_NOMINAL - V_BLOCK]
	cmp	r1, #0
	ble	.Llf_nom_def		@ 0, -0.0 and negative (sign bit set)
	cmp	r1, #0x7F800000
	blo	.Llf_tol		@ finite and positive (below +Inf)
.Llf_nom_def:
	ldr	r1, [r2, #12]		@ 1000.0
	str	r1, [r0, #V_NOMINAL - V_BLOCK]
.Llf_tol:
	ldr	r1, [r0, #V_TOLERANCE - V_BLOCK]
	cmp	r1, #0
	blt	.Llf_tol_def		@ negative
	ldr	r3, [r2, #16]		@ 99.9
	cmp	r1, r3
	bls	.Llf_out		@ 0.0 .. 99.9 (positive floats order as their bits)
.Llf_tol_def:
	ldr	r1, [r2, #20]		@ 5.0
	str	r1, [r0, #V_TOLERANCE - V_BLOCK]
.Llf_out:
	bx	lr

	.ltorg

@ ----------------------------------------------------------------------------
@ set_english - r0 = block base (V_BLOCK or OWN_STAGE): the words at block
@   offsets 0xBC4 (first-start flag) and 0xBE0 (language) set to 1, so that no
@   path starts the language chooser 0x0800C86C or selects the Chinese row.
@   Uses r1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	set_english, %function
set_english:
	movs	r1, #1
	str	r1, [r0, #BLK_LANG_SET]
	str	r1, [r0, #BLK_LANGUAGE]
	bx	lr

@ ----------------------------------------------------------------------------
@ stage_seal - r0 = sequence: sets the language words of the staged block to 1
@   (set_english: every copy written, by every save and recovery path, holds
@   1 / 1), then stores the sequence in SVO_SEQ and the CRC-32 of the staged
@   block followed by those 4 sequence bytes in SVO_CRC. Uses r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	stage_seal, %function
stage_seal:
	push	{r4, lr}
	ldr	r4, =OWN_SAVE
	str	r0, [r4, #SVO_SEQ]
	ldr	r0, =OWN_STAGE
	bl	set_english
	mvn	r0, #0
	ldr	r1, =OWN_STAGE
	movw	r2, #BLK_SIZE
	bl	own_crc32_update
	add	r1, r4, #SVO_SEQ
	movs	r2, #4
	bl	own_crc32_update
	mvns	r0, r0
	str	r0, [r4, #SVO_CRC]
	pop	{r4, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ write_copy - write the staged block to one copy.
@   r0 = copy base (SET_A or SET_B); SVO_SEQ / SVO_CRC sealed by stage_seal.
@   (a) copy A in the vendor format (both markers, both trailer words
@       0xFFFFFFFF): its trailer sequence word is programmed first; on any
@       failure the copy is left before any erase (SV_MARK, step 4 (a));
@   (b) erase the first page, check it; erase the second page, check it;
@   (c) trailer sequence, the block in ascending order (a feed after every
@       256 words and after the last), the CRC word last;
@   (d) the whole copy read back: block, 0xFF from block end to the trailer,
@       sequence, CRC.
@   A failure in (b)..(d) repeats once from (b), then returns.
@   Returns r0 = SV_OK, or SV_* | step << 8.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	write_copy, %function
write_copy:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r4, r0			@ r4 = copy base
	ldr	r7, =OWN_SAVE
	ldr	r0, =SET_A
	cmp	r4, r0
	bne	.Lw_start
	bl	copy_check		@ r0 = SET_A
	and	r0, r0, #CK_MARKERS | CK_BLANK
	cmp	r0, #CK_MARKERS | CK_BLANK
	bne	.Lw_start
	addw	r0, r4, #TRL_SEQ	@ (a) mark: A is no longer the vendor format
	ldr	r1, [r7, #SVO_SEQ]
	bl	flash_word
	cmp	r0, #FL_OK
	bne	.Lw_mark_fail
.Lw_start:
	mov	r8, #2			@ r8 = attempts from (b)
.Lw_try:
	mov	r0, r4			@ (b)
	bl	flash_erase_page
	cmp	r0, #FL_OK
	bne	.Lw_erase_fail
	add	r0, r4, #FLASH_PAGE
	bl	flash_erase_page
	cmp	r0, #FL_OK
	bne	.Lw_erase_fail
	addw	r0, r4, #TRL_SEQ	@ (c)
	ldr	r1, [r7, #SVO_SEQ]
	bl	flash_word
	cmp	r0, #FL_OK
	bne	.Lw_prog_fail
	ldr	r6, =OWN_STAGE
	movs	r5, #0			@ r5 = block offset
.Lw_word:
	add	r0, r4, r5
	ldr	r1, [r6, r5]
	bl	flash_word
	cmp	r0, #FL_OK
	bne	.Lw_prog_fail
	adds	r5, r5, #4
	tst	r5, #0x3FC		@ offset a multiple of 0x400: 256 words done
	bne	.Lw_next
	bl	own_feed
.Lw_next:
	movw	r0, #BLK_SIZE
	cmp	r5, r0
	blo	.Lw_word
	bl	own_feed
	addw	r0, r4, #TRL_CRC
	ldr	r1, [r7, #SVO_CRC]
	bl	flash_word
	cmp	r0, #FL_OK
	bne	.Lw_prog_fail
	movs	r5, #0			@ (d) block
.Lw_rb_block:
	ldr	r0, [r4, r5]
	ldr	r1, [r6, r5]
	cmp	r0, r1
	bne	.Lw_verify_fail
	adds	r5, r5, #4
	movw	r0, #BLK_SIZE
	cmp	r5, r0
	blo	.Lw_rb_block
.Lw_rb_blank:				@ block end .. trailer: erased
	ldr	r0, [r4, r5]
	adds	r0, r0, #1
	bne	.Lw_verify_fail
	adds	r5, r5, #4
	movw	r0, #TRL_SEQ
	cmp	r5, r0
	blo	.Lw_rb_blank
	ldr	r0, [r4, #TRL_SEQ]
	ldr	r1, [r7, #SVO_SEQ]
	cmp	r0, r1
	bne	.Lw_verify_fail
	ldr	r0, [r4, #TRL_CRC]
	ldr	r1, [r7, #SVO_CRC]
	cmp	r0, r1
	bne	.Lw_verify_fail
	movs	r0, #SV_OK
	pop	{r4, r5, r6, r7, r8, pc}
.Lw_mark_fail:
	movw	r0, #SV_MARK | STEP_MARK << 8
	pop	{r4, r5, r6, r7, r8, pc}
.Lw_erase_fail:
	movw	r5, #SV_ERASE | STEP_ERASE << 8
	b	.Lw_retry
.Lw_prog_fail:
	movw	r5, #SV_PROGRAM | STEP_PROGRAM << 8
	b	.Lw_retry
.Lw_verify_fail:
	movw	r5, #SV_VERIFY | STEP_VERIFY << 8
.Lw_retry:
	subs	r8, r8, #1
	bne	.Lw_try
	mov	r0, r5
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ save_stage - write the staged block.
@   r0 = mode: MODE_ORDER (step 3: A only while SF_A_ONLY or SF_DIFFERS is
@   set, else B then A), MODE_A, MODE_B or MODE_BA.
@   r1 = sequence for the copies, or 0: highest valid sequence + 1 (copy A in
@   the vendor format counts 0).
@   B is written first in MODE_BA; when it fails, A is not touched.
@   Returns r0 = SV_OK, or SV_* | step << 8 | copy << 16.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	save_stage, %function
save_stage:
	push	{r4, r5, r6, lr}
	mov	r4, r0			@ r4 = mode
	mov	r5, r1			@ r5 = sequence
	cmp	r5, #0
	bne	.Lss_seal
	bl	eval_copies		@ r1 = sequence of A, r2 = sequence of B
	cmp	r1, r2
	it	lo
	movlo	r1, r2
	adds	r5, r1, #1
.Lss_seal:
	mov	r0, r5
	bl	stage_seal
	cmp	r4, #MODE_ORDER
	bne	.Lss_mode
	movs	r4, #MODE_BA
	ldr	r0, =own_save_flags
	ldr	r0, [r0]
	tst	r0, #SF_A_ONLY | SF_DIFFERS
	beq	.Lss_mode
	movs	r4, #MODE_A
.Lss_mode:
	cmp	r4, #MODE_A
	beq	.Lss_a
	ldr	r0, =SET_B
	bl	write_copy
	cmp	r0, #SV_OK
	bne	.Lss_fail_b
	cmp	r4, #MODE_B
	beq	.Lss_ok
.Lss_a:
	ldr	r0, =SET_A
	bl	write_copy
	cmp	r0, #SV_OK
	bne	.Lss_fail_a
.Lss_ok:
	movs	r0, #SV_OK
	pop	{r4, r5, r6, pc}
.Lss_fail_b:
	orr	r0, r0, #COPY_B << 16
	pop	{r4, r5, r6, pc}
.Lss_fail_a:
	orr	r0, r0, #COPY_A << 16
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ finish - r0 = status: stored in own_save_status, own_save_count + 1;
@   SV_OK clears SF_FAILED, SV_MARK..SV_VERIFY set it, other codes leave it.
@   Returns r0 unchanged. Uses r1..r3.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	finish, %function
finish:
	ldr	r1, =OWN_SAVE
	str	r0, [r1, #SVO_STATUS]
	ldr	r2, [r1, #SVO_COUNT]
	adds	r2, r2, #1
	str	r2, [r1, #SVO_COUNT]
	ldr	r2, [r1, #SVO_FLAGS]
	uxtb	r3, r0
	cmp	r3, #SV_OK
	bne	.Lf_fail
	bic	r2, r2, #SF_FAILED
	b	.Lf_store
.Lf_fail:
	cmp	r3, #SV_MARK
	blo	.Lf_out
	cmp	r3, #SV_VERIFY
	bhi	.Lf_out
	orr	r2, r2, #SF_FAILED
.Lf_store:
	str	r2, [r1, #SVO_FLAGS]
.Lf_out:
	bx	lr

@ ----------------------------------------------------------------------------
@ flags_ok - r0 = status, r1 = SF_* bits to clear, r2 = SF_* bits to set:
@   applied to own_save_flags only when r0 = SV_OK. Returns r0 unchanged.
@   Uses r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	flags_ok, %function
flags_ok:
	cmp	r0, #SV_OK
	bne	.Lfo_out
	ldr	r12, =own_save_flags
	ldr	r3, [r12]
	bic	r3, r3, r1
	orr	r3, r3, r2
	str	r3, [r12]
.Lfo_out:
	bx	lr

	.ltorg

@ ----------------------------------------------------------------------------
@ own_load - replaces bl copy_flash_block_to_ram at 0x08028030 (system_40.s
@   fn_08027ff4; the block was zero-filled just before, 0x4BA4 bytes from
@   0x2000057C). No arguments, no result. Writes no flash.
@   Closes the BOOT gate, clears own_save_status, then:
@   - A and B valid: A when A is in the vendor format or sequence A >= B,
@     else B; SF_DIFFERS when block offsets 0x04..0xB43 of the two copies
@     differ;
@   - only A valid: A;
@   - only B valid: B; A's first word 0xFFFFFFFF (interrupted rewrite):
@     SF_REWRITE_A (done by save_resume); A with both markers (damaged, not
@     erased): SF_HELD | SF_A_DAMAGED;
@   - B loaded: SF_A_ONLY;
@   - neither: SF_HELD | SF_NOVALID, nothing copied, first block word 0, so
@     the check 0x08028034..0x08028048 calls 0x0800B4C8(1), whose save
@     (0x0800B5C0) is held.
@   The chosen copy's 0xC14 bytes go to 0x2000057C, then its first-start flag
@   and language words are set to 1 (set_english) and its invalid setting
@   words repaired in RAM (load_fix, S2.11); own_save_flags and
@   own_save_loaded are written whole.
@ ----------------------------------------------------------------------------
	.global	own_load
	.thumb_func
	.type	own_load, %function
own_load:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =OWN_SAVE
	movs	r0, #0
	str	r0, [r4, #SVO_GATE]	@ BOOT gate closed
	str	r0, [r4, #SVO_STATUS]
	bl	eval_copies		@ r0 = EV_*, r1 = sequence A, r2 = sequence B
	mov	r5, r0			@ r5 = EV_* bits
	movs	r6, #0			@ r6 = new own_save_flags
	tst	r5, #EV_A_VALID
	beq	.Ll_no_a
	movs	r7, #COPY_A		@ r7 = copy to load
	tst	r5, #EV_B_VALID
	beq	.Ll_copy
	tst	r5, #EV_A_VENDOR
	bne	.Ll_compare
	cmp	r2, r1
	bls	.Ll_compare		@ sequence B <= A: A (equal: A)
	movs	r7, #COPY_B
	orr	r6, r6, #SF_A_ONLY
.Ll_compare:
	ldr	r0, =SET_A + BLK_CAL_LO
	ldr	r1, =SET_B + BLK_CAL_LO
	movw	r2, #BLK_CAL_LEN
.Ll_cmp_word:
	ldr	r3, [r0], #4
	ldr	r12, [r1], #4
	cmp	r3, r12
	bne	.Ll_differs
	subs	r2, r2, #4
	bne	.Ll_cmp_word
	b	.Ll_copy
.Ll_differs:
	orr	r6, r6, #SF_DIFFERS
	b	.Ll_copy
.Ll_no_a:
	tst	r5, #EV_B_VALID
	beq	.Ll_none
	movs	r7, #COPY_B
	orr	r6, r6, #SF_A_ONLY
	ldr	r0, =SET_A
	ldr	r0, [r0]
	adds	r0, r0, #1		@ zero when A's first word is 0xFFFFFFFF
	bne	.Ll_a_used
	orr	r6, r6, #SF_REWRITE_A
	b	.Ll_copy
.Ll_a_used:
	tst	r5, #EV_A_MARKERS
	beq	.Ll_copy
	orr	r6, r6, #SF_HELD | SF_A_DAMAGED
	b	.Ll_copy
.Ll_none:
	movs	r7, #COPY_NONE
	movs	r6, #SF_HELD | SF_NOVALID
	ldr	r0, =V_BLOCK
	movs	r1, #0
	str	r1, [r0]		@ first marker 0: defaults at 0x08028046
	b	.Ll_store
.Ll_copy:
	ldr	r0, =SET_A
	cmp	r7, #COPY_A
	beq	.Ll_src
	ldr	r0, =SET_B
.Ll_src:
	ldr	r1, =V_BLOCK
	movw	r2, #BLK_SIZE
.Ll_cp_word:
	ldr	r3, [r0], #4
	str	r3, [r1], #4
	subs	r2, r2, #4
	bne	.Ll_cp_word
	ldr	r0, =V_BLOCK
	bl	set_english		@ a copy with 0 / 0 (V1.1, chooser not run) starts English
	bl	load_fix		@ S2.11: invalid setting words repaired in RAM
.Ll_store:
	str	r6, [r4, #SVO_FLAGS]
	str	r7, [r4, #SVO_LOADED]
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ own_save - replaces the four bl fn_08014b94 (r0 not used; the vendor
@   callers ignore the result).
@   First, in every case: the first-start flag and the language word of the RAM
@   block set to 1 (set_english; the defaults 0x0800B4C8 store language 0 at
@   0x0800B4FE and leave the flag 0 before their save 0x0800B5C0, so the
@   start-up chooser 0x080281F8 and the Chinese rows are never reached).
@   Writes nothing and returns SV_REFUSED while own_injected is set (guard)
@   and SV_HELD while SF_HELD or SF_RESTART is
@   set. Otherwise: snapshot of the RAM block 0x2000057C into OWN_STAGE, the
@   settings of before a running calibration sweep (stage_cal_fix, stage 3), its
@   frequency 60 -> 100 (stage_freq_fix, S2.12); when both copies already
@   hold exactly that block (stage_same, S2.10): SV_SAME, nothing erased or
@   programmed; else save_stage(MODE_ORDER, highest valid sequence + 1).
@   SV_OK clears SF_REWRITE_A (every successful save writes A).
@   Returns r0 = status, also in own_save_status; own_save_count + 1.
@ ----------------------------------------------------------------------------
	.global	own_save
	.thumb_func
	.type	own_save, %function
own_save:
	push	{r4, lr}
	ldr	r0, =V_BLOCK
	bl	set_english
	ldr	r0, =own_injected
	ldr	r0, [r0]
	cmp	r0, #0
	bne	.Lsv_refused
	ldr	r0, =own_save_flags
	ldr	r0, [r0]
	tst	r0, #SF_HELD | SF_RESTART
	bne	.Lsv_held
	ldr	r0, =V_BLOCK		@ step 1: snapshot
	bl	stage_copy
	bl	stage_cal_fix		@ stage 3: a sweep in progress saves the settings of before it
	bl	stage_freq_fix		@ S2.12: 60 Hz is saved as 100 Hz
	bl	stage_same		@ S2.10: both copies hold it already?
	cmp	r0, #0
	bne	.Lsv_same
	movs	r0, #MODE_ORDER
	movs	r1, #0
	bl	save_stage
	movs	r1, #SF_REWRITE_A
	movs	r2, #0
	bl	flags_ok
	b	.Lsv_done
.Lsv_same:
	movs	r0, #SV_SAME		@ nothing erased, nothing programmed
	b	.Lsv_done
.Lsv_refused:
	movs	r0, #SV_REFUSED
	b	.Lsv_done
.Lsv_held:
	movs	r0, #SV_HELD
.Lsv_done:
	bl	finish
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ save_resume - called by ctl_loop once per main-loop pass. When
@   SF_REWRITE_A is set (A looked interrupted at load, B was loaded) it
@   clears it (one attempt only), stages B's block from flash and writes it
@   to A with B's sequence (equal sequences load A). B no longer valid:
@   SV_BADCOPY. Returns r0 = status (also own_save_status, own_save_count
@   + 1), or 0xFFFFFFFF when there was nothing to do.
@ ----------------------------------------------------------------------------
	.global	save_resume
	.thumb_func
	.type	save_resume, %function
save_resume:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_SAVE
	ldr	r0, [r4, #SVO_FLAGS]
	tst	r0, #SF_REWRITE_A
	beq	.Lr_none
	bic	r0, r0, #SF_REWRITE_A
	str	r0, [r4, #SVO_FLAGS]
	tst	r0, #SF_HELD | SF_RESTART
	bne	.Lr_none
	bl	eval_copies
	tst	r0, #EV_B_VALID
	beq	.Lr_badcopy
	mov	r5, r2			@ r5 = sequence of B
	ldr	r0, =SET_B
	bl	stage_copy
	movs	r0, #MODE_A
	mov	r1, r5
	bl	save_stage
	b	.Lr_done
.Lr_badcopy:
	movw	r0, #SV_BADCOPY | STEP_CHECK << 8
.Lr_done:
	bl	finish
	pop	{r4, r5, r6, pc}
.Lr_none:
	mvn	r0, #0
	pop	{r4, r5, r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ Recovery (held saves).
@ Each returns r0 = status (also own_save_status, own_save_count + 1):
@ SV_REFUSED when its condition does not hold (nothing written), SV_BADCOPY
@ when its source copy is not valid, else the result of save_stage. A
@ function that leaves flash different from the RAM block sets SF_RESTART:
@ saves are then held until the caller restarts the meter (soft_restart), which
@ loads the new copies through own_load.
@ ----------------------------------------------------------------------------

@ save_accept_b - SETTINGS_ACCEPT_B: only while SF_A_DAMAGED is set. B's
@   block (the loaded copy) is written to A with B's sequence. SV_OK clears
@   SF_HELD, SF_A_DAMAGED, SF_REWRITE_A.
	.global	save_accept_b
	.thumb_func
	.type	save_accept_b, %function
save_accept_b:
	push	{r4, r5, r6, lr}
	ldr	r0, =own_save_flags
	ldr	r0, [r0]
	tst	r0, #SF_A_DAMAGED
	beq	.Lab_refused
	bl	eval_copies
	tst	r0, #EV_B_VALID
	beq	.Lab_badcopy
	mov	r5, r2			@ r5 = sequence of B
	ldr	r0, =SET_B
	bl	stage_copy
	movs	r0, #MODE_A
	mov	r1, r5
	bl	save_stage
	movs	r1, #SF_HELD | SF_A_DAMAGED | SF_REWRITE_A
	movs	r2, #0
	bl	flags_ok
	b	.Lab_done
.Lab_refused:
	movs	r0, #SV_REFUSED
	b	.Lab_done
.Lab_badcopy:
	movw	r0, #SV_BADCOPY | STEP_CHECK << 8
.Lab_done:
	bl	finish
	pop	{r4, r5, r6, pc}

@ save_accept_defaults - SETTINGS_ACCEPT_DEFAULTS: only while SF_NOVALID is
@   set. The RAM block (the defaults 0x0800B4C8(1) wrote at start-up, plus
@   any change since) is staged, its markers checked (SV_BADBLOCK), and
@   written B, then A, with sequence highest valid + 1. SV_OK clears SF_HELD
@   and SF_NOVALID.
	.global	save_accept_defaults
	.thumb_func
	.type	save_accept_defaults, %function
save_accept_defaults:
	push	{r4, lr}
	ldr	r0, =own_save_flags
	ldr	r0, [r0]
	tst	r0, #SF_NOVALID
	beq	.Lad_refused
	ldr	r0, =V_BLOCK
	bl	stage_copy
	bl	stage_cal_fix		@ stage 3: a sweep in progress saves the settings of before it
	bl	stage_freq_fix		@ S2.12: 60 Hz is saved as 100 Hz
	bl	stage_markers
	cmp	r0, #0
	bne	.Lad_badblock
	movs	r0, #MODE_BA
	movs	r1, #0
	bl	save_stage
	movs	r1, #SF_HELD | SF_NOVALID
	movs	r2, #0
	bl	flags_ok
	b	.Lad_done
.Lad_refused:
	movs	r0, #SV_REFUSED
	b	.Lad_done
.Lad_badblock:
	movw	r0, #SV_BADBLOCK | STEP_CHECK << 8
.Lad_done:
	bl	finish
	pop	{r4, pc}

	.ltorg

@ save_write_block - SETTINGS_WRITE_BLOCK: r0 = CRC-32 the host gave for the
@   0xC14 bytes that ctl.s placed in OWN_STAGE. The CRC-32 of OWN_STAGE must
@   equal r0 and both markers must be present (else SV_BADBLOCK, nothing
@   written); then save_stage(MODE_ORDER, highest valid + 1), whose stage_seal
@   sets the two language words to 1 after these checks (the host's CRC covers
@   the bytes as received). SV_OK clears SF_HELD, SF_NOVALID, SF_A_DAMAGED,
@   SF_REWRITE_A and sets SF_RESTART.
	.global	save_write_block
	.thumb_func
	.type	save_write_block, %function
save_write_block:
	push	{r4, lr}
	mov	r4, r0			@ r4 = CRC-32 from the host
	ldr	r0, =OWN_STAGE
	movw	r1, #BLK_SIZE
	bl	own_crc32
	cmp	r0, r4
	bne	.Lwb_badblock
	bl	stage_markers
	cmp	r0, #0
	bne	.Lwb_badblock
	bl	stage_freq_fix		@ S2.12: after the host's CRC check, before the seal
	movs	r0, #MODE_ORDER
	movs	r1, #0
	bl	save_stage
	movs	r1, #SF_HELD | SF_NOVALID | SF_A_DAMAGED | SF_REWRITE_A
	movs	r2, #SF_RESTART
	bl	flags_ok
	b	.Lwb_done
.Lwb_badblock:
	movw	r0, #SV_BADBLOCK | STEP_CHECK << 8
.Lwb_done:
	bl	finish
	pop	{r4, pc}

@ save_restore_b - SETTINGS_RESTORE_B: refused while SF_HELD is set or when
@   neither SF_DIFFERS nor SF_A_ONLY is set. B's block is written to A only
@   (B already holds it) with B's sequence. SV_OK clears SF_DIFFERS,
@   SF_A_ONLY, SF_REWRITE_A, and sets SF_RESTART when A was the loaded copy
@   (the RAM block then differs from both copies).
	.global	save_restore_b
	.thumb_func
	.type	save_restore_b, %function
save_restore_b:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_SAVE
	ldr	r0, [r4, #SVO_FLAGS]
	tst	r0, #SF_HELD
	bne	.Lrb_refused
	tst	r0, #SF_DIFFERS | SF_A_ONLY
	beq	.Lrb_refused
	bl	eval_copies
	tst	r0, #EV_B_VALID
	beq	.Lrb_badcopy
	mov	r5, r2			@ r5 = sequence of B
	ldr	r0, =SET_B
	bl	stage_copy
	movs	r0, #MODE_A
	mov	r1, r5
	bl	save_stage
	movs	r2, #0
	ldr	r1, [r4, #SVO_LOADED]
	cmp	r1, #COPY_A
	bne	.Lrb_flags
	movs	r2, #SF_RESTART
.Lrb_flags:
	movs	r1, #SF_DIFFERS | SF_A_ONLY | SF_REWRITE_A
	bl	flags_ok
	b	.Lrb_done
.Lrb_refused:
	movs	r0, #SV_REFUSED
	b	.Lrb_done
.Lrb_badcopy:
	movw	r0, #SV_BADCOPY | STEP_CHECK << 8
.Lrb_done:
	bl	finish
	pop	{r4, r5, r6, pc}

	.ltorg

@ save_accept_a - SETTINGS_ACCEPT_A: refused while SF_HELD is set or when
@   neither SF_DIFFERS nor SF_A_ONLY is set. A's block is written to B only
@   (A is kept) with A's sequence (equal sequences load A); A in the vendor
@   format has none, then highest valid + 1. SV_OK clears SF_DIFFERS and
@   SF_A_ONLY, and sets SF_RESTART when B was the loaded copy.
	.global	save_accept_a
	.thumb_func
	.type	save_accept_a, %function
save_accept_a:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_SAVE
	ldr	r0, [r4, #SVO_FLAGS]
	tst	r0, #SF_HELD
	bne	.Laa_refused
	tst	r0, #SF_DIFFERS | SF_A_ONLY
	beq	.Laa_refused
	bl	eval_copies
	tst	r0, #EV_A_VALID
	beq	.Laa_badcopy
	mov	r5, r1			@ r5 = sequence of A (0: vendor format)
	ldr	r0, =SET_A
	bl	stage_copy
	movs	r0, #MODE_B
	mov	r1, r5
	bl	save_stage
	movs	r2, #0
	ldr	r1, [r4, #SVO_LOADED]
	cmp	r1, #COPY_B
	bne	.Laa_flags
	movs	r2, #SF_RESTART
.Laa_flags:
	movs	r1, #SF_DIFFERS | SF_A_ONLY
	bl	flags_ok
	b	.Laa_done
.Laa_refused:
	movs	r0, #SV_REFUSED
	b	.Laa_done
.Laa_badcopy:
	movw	r0, #SV_BADCOPY | STEP_CHECK << 8
.Laa_done:
	bl	finish
	pop	{r4, r5, r6, pc}

	.ltorg
