@ slot_10.s - code of the slot build only: initial-RAM copy, fault handler, flash gate, control
@ records, application start, UF2 update path and the update drive's status file
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ Everything below assembles only with --defsym SLOT=1 (make slot); the stock build (make check)
@ gets an empty object from this file. The stock code calls into this file at these places, each
@ one under .ifdef SLOT there:
@   rodata.s      region table entry 0 -> copy_init (the initial RAM image is typed data)
@   vectors.s     HardFault, MemManage, BusFault, UsageFault, PendSV, every unused vector
@                 -> slot_fault
@   board_02.s    fn_08002598: SYSCLK switched to HSI and SCLKSTS waited for first (a soft
@                 restart enters with the PLL running); VTOR = this image's own vector
@                 table, interrupts enabled; fn_080020c4: a slot copy with the bounded
@                 PLL-lock and switch waits (feature version 3, below)
@   update_06.s   fn_08000e24 / fn_08000eb4 (page erase / word program) -> flash_gate first;
@                 fn_0800159c: drive size DRIVE_SECTORS; fn_080015b8 -> slot_read_sector;
@                 fn_080015c2 -> uf2_sector
@   system_05.s   main: first -> slot_trial_wdg; key read -> slot_key_check; application start
@                 -> slot_app_start; before the USB start -> uf2_init; after the USB start ->
@                 slot_confirm; every pass of the update-mode loop -> slot_feed; state 2 ->
@                 slot_finish
@ Feature version 2 (USB_CONTROL_DESIGN.md section 6, items a..e, and 6b): the request word
@ (slot_key_check: UPDT update mode, UPDT / RSTR the application's IWDG runs), the hand-over
@ word (slot_app_start), the result word and the soft restart after an update (slot_finish,
@ slot_soft_restart), the watchdog of a trial start (slot_trial_wdg) and its feeds (slot_feed:
@ slot_confirm, slot_app_start, the update-mode loop, slot_finish, slot_soft_restart,
@ uf2_erase_page, uf2_program, uf2_finish).
@ Feature version 3: the three clock waits of the start-up code end after CLK_POLLS reads
@ (slot.inc; board_02.s fn_08002598 .Lslot_hsi, and the slot copy of fn_080020c4, .Lslot_pll,
@ .Lslot_sw / .Lslot_back). They run before main, before any watchdog of a start from power-on;
@ no code of this file is involved.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

.ifdef SLOT
	.include "src/slot.inc"

	.section .text.slot,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ copy_init - region table handler of entry 0: copies the initial RAM image.
@   r0 = source, r1 = destination, r2 = byte count (a multiple of 4). Copies
@   word by word; uses r0..r3 only (scatterload keeps r4 / r5). copy_init_addr
@   is the even address the region table holds (scatterload sets bit 0).
@ ----------------------------------------------------------------------------
	.global copy_init_addr
copy_init_addr:
	.global copy_init
	.thumb_func
	.type copy_init, %function
copy_init:
	cbz	r2, 2f
1:	ldr	r3, [r0], #4
	str	r3, [r1], #4
	subs	r2, r2, #4
	bne	1b
2:	bx	lr

@ ----------------------------------------------------------------------------
@ slot_fault - handler of every fault and every vector without a handler.
@   Writes FAULT_MAGIC to the starter's fault flag FAULT_FLAG (0x2001FFF0) and
@   requests a system reset (AIRCR 0xE000ED0C = 0x05FA0004); the starter then
@   clears the flag and starts slot F. Never returns.
@ ----------------------------------------------------------------------------
	.global slot_fault
	.thumb_func
	.type slot_fault, %function
slot_fault:
	ldr	r0, =FAULT_FLAG
	ldr	r1, =FAULT_MAGIC
	str	r1, [r0]
	dsb
	ldr	r0, =AIRCR
	ldr	r1, =AIRCR_RESET
	str	r1, [r0]
	dsb
3:	b	3b

@ ----------------------------------------------------------------------------
@ flash_gate - the only flash addresses the slot may erase or program.
@   r0 = flash address. Returns r0 = 0 when it lies in the application area
@   0x08006000..0x08061FFF or in the record pages 0x08068000..0x08068FFF,
@   otherwise 8 (fn_08000eb4 passes the 8 on as its result). Uses r1 only.
@   Called first by fn_08000e24 (page erase) and fn_08000eb4 (word program).
@ ----------------------------------------------------------------------------
	.global flash_gate
	.thumb_func
	.type flash_gate, %function
flash_gate:
	ldr	r1, =APP_BASE
	cmp	r0, r1
	blo	5f
	ldr	r1, =APP_END
	cmp	r0, r1
	blo	4f
	ldr	r1, =REC0
	cmp	r0, r1
	blo	5f
	ldr	r1, =REC_END
	cmp	r0, r1
	bhs	5f
4:	movs	r0, #0
	bx	lr
5:	movs	r0, #8
	bx	lr

@ ----------------------------------------------------------------------------
@ crc32_update - run bytes through the CRC-32 (zlib polynomial, reflected).
@   r0 = CRC register (0xFFFFFFFF at the start), r1 = address, r2 = byte
@   count (0 allowed). Returns r0 = the new register; the CRC-32 is its
@   complement. Uses r1..r3; r1 is left at address + count (uf2_finish
@   goes on from there).
@ crc32 - r0 = address, r1 = byte count -> r0 = CRC-32 of those bytes.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type crc32_update, %function
crc32_update:
	push	{r4, r5}
	ldr	r4, =0xEDB88320
	cbz	r2, 8f
6:	ldrb	r3, [r1], #1
	eors	r0, r0, r3
	movs	r5, #8
7:	lsrs	r0, r0, #1
	it	cs
	eorcs	r0, r0, r4
	subs	r5, r5, #1
	bne	7b
	subs	r2, r2, #1
	bne	6b
8:	pop	{r4, r5}
	bx	lr

	.thumb_func
	.type crc32, %function
crc32:
	push	{lr}
	mov	r2, r1
	mov	r1, r0
	mvn	r0, #0
	bl	crc32_update
	mvns	r0, r0
	pop	{pc}

	.ltorg

@ ============================================================================
@ Control records: the starter's format and rules (starter/starter.s), typed
@ here for this slot. Two pages REC0 / REC1, 16-byte cells:
@   +0 REC_TAG << 16 | slot << 8 | state, +4 version, +8 sequence number,
@   +12 CRC-32 of bytes 0..11. An erased cell is never valid (CRC word
@   0xFFFFFFFF, CRC-32 of twelve 0xFF bytes 0xBB99FF8A).
@ ============================================================================

@ ----------------------------------------------------------------------------
@ rec_cell_valid - r0 = cell address -> r0 = 1 when tag and CRC match, else 0.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type rec_cell_valid, %function
rec_cell_valid:
	push	{r4, lr}
	mov	r4, r0
	ldr	r1, [r4, #0]
	lsrs	r1, r1, #16
	movw	r2, #REC_TAG
	cmp	r1, r2
	bne	9f
	movs	r1, #12
	bl	crc32
	ldr	r1, [r4, #12]
	cmp	r0, r1
	bne	9f
	movs	r0, #1
	pop	{r4, pc}
9:	movs	r0, #0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ rec_scan - fill TAB with the newest valid record of each slot.
@   TAB (0x20002100): per slot {sequence, state, version, cell address}.
@   Returns r0 = slot of the newest record over both pages, or -1 when there
@   is none.
@ ----------------------------------------------------------------------------
	.global rec_scan
	.thumb_func
	.type rec_scan, %function
rec_scan:
	push	{r4, r5, r6, r7, lr}
	ldr	r0, =TAB
	movs	r1, #0
	movs	r2, #12
10:	str	r1, [r0], #4
	subs	r2, r2, #1
	bne	10b
	ldr	r4, =REC0		@ r4 = cell address
11:	mov	r0, r4
	bl	rec_cell_valid
	cmp	r0, #0
	beq	12f
	ldr	r1, [r4, #0]
	ubfx	r5, r1, #8, #8		@ r5 = slot
	uxtb	r6, r1			@ r6 = state
	cmp	r5, #3
	bhs	12f
	cmp	r6, #ST_INSTALL
	blo	12f
	cmp	r6, #ST_OK
	bhi	12f
	ldr	r7, =TAB
	add	r7, r7, r5, lsl #4
	ldr	r1, [r4, #8]		@ sequence number
	ldr	r2, [r7, #0]
	cmp	r1, r2
	bls	12f
	str	r1, [r7, #0]
	str	r6, [r7, #4]
	ldr	r1, [r4, #4]
	str	r1, [r7, #8]
	str	r4, [r7, #12]
12:	adds	r4, r4, #16
	ldr	r1, =REC_END
	cmp	r4, r1
	blo	11b
	@ newest over the three slots
	mvn	r0, #0
	movs	r1, #0			@ best sequence
	movs	r2, #0			@ slot i
	ldr	r3, =TAB
13:	add	r12, r3, r2, lsl #4
	ldr	r12, [r12, #0]
	cmp	r12, r1
	bls	14f
	mov	r1, r12
	mov	r0, r2
14:	adds	r2, r2, #1
	cmp	r2, #3
	blo	13b
	pop	{r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ rec_append - r0 = slot, r1 = state, r2 = version.
@   Writes the next record after the last used cell of the page holding the
@   newest record; when that page has no free cell, erases the other page and
@   writes the record as its first cell. The cell is read back; when it
@   differs, the record is written again in the next free cell (three
@   attempts in all). Called only after rec_scan found a record (TAB holds a
@   cell address).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type rec_append, %function
rec_append:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =CELL
	movw	r3, #REC_TAG
	orr	r3, r1, r3, lsl #16
	orr	r3, r3, r0, lsl #8
	str	r3, [r4, #0]
	str	r2, [r4, #4]
	@ sequence = highest + 1; r6 = cell address of the newest record
	ldr	r3, =TAB
	movs	r5, #0
	movs	r6, #0
	movs	r7, #0
15:	add	r2, r3, r7, lsl #4
	ldr	r1, [r2, #0]
	cmp	r1, r5
	bls	16f
	mov	r5, r1
	ldr	r6, [r2, #12]
16:	adds	r7, r7, #1
	cmp	r7, #3
	blo	15b
	adds	r5, r5, #1
	str	r5, [r4, #8]
	mov	r0, r4
	movs	r1, #12
	bl	crc32
	str	r0, [r4, #12]
	@ page of the newest record; free cell above its last used cell
	bic	r6, r6, #0x7F0
	bic	r6, r6, #0xF		@ r6 = page base
	mov	r8, #3			@ write attempts; a cell that fails its read-back
					@ stays used (not all 0xFF) and fails its CRC
60:	mov	r5, r6			@ r5 = first cell above the last used one
	mov	r7, r6			@ r7 = cell being looked at
17:	ldm	r7, {r0, r1, r2, r3}
	and	r0, r0, r1
	and	r2, r2, r3
	and	r0, r0, r2
	adds	r0, r0, #1		@ zero only when all four words are 0xFFFFFFFF
	beq	18f
	add	r5, r7, #16
18:	adds	r7, r7, #16
	add	r1, r6, #FLASH_PAGE
	cmp	r7, r1
	blo	17b
	add	r1, r6, #FLASH_PAGE
	cmp	r5, r1
	blo	19f
	@ page full: erase the other page and write there first
	ldr	r1, =REC0
	cmp	r6, r1
	ite	eq
	ldreq	r5, =REC1
	ldrne	r5, =REC0
	mov	r0, r5
	bl	rec_flash_erase
19:	bl	rec_flash_unlock
	movs	r7, #0
20:	add	r0, r5, r7
	ldr	r1, [r4, r7]
	bl	rec_flash_word
	adds	r7, r7, #4
	cmp	r7, #16
	blo	20b
	ldr	r0, =FLASH_CTRL
	movs	r1, #0x80
	str	r1, [r0]
	@ read back the cell; on a difference write the record again in the next free cell
	movs	r7, #0
61:	ldr	r0, [r5, r7]
	ldr	r1, [r4, r7]
	cmp	r0, r1
	bne	62f
	adds	r7, r7, #4
	cmp	r7, #16
	blo	61b
	b	63f
62:	subs	r8, r8, #1
	bne	60b
63:	pop	{r4, r5, r6, r7, r8, pc}

@ ---- record flash primitives; every address outside REC0..REC_END is refused ----
	.thumb_func
	.type rec_flash_unlock, %function
rec_flash_unlock:
	ldr	r0, =FLASH_KEY
	ldr	r1, =KEY1
	str	r1, [r0]
	ldr	r1, =KEY2
	str	r1, [r0]
	bx	lr

	.thumb_func
	.type rec_flash_wait, %function
rec_flash_wait:
	ldr	r2, =FLASH_STS
21:	ldr	r3, [r2]
	tst	r3, #1
	bne	21b
	movs	r3, #0xFC		@ clear EOP and the error flags (write 1 to clear)
	str	r3, [r2]
	bx	lr

@ rec_flash_erase: r0 = page base inside the record pages
	.thumb_func
	.type rec_flash_erase, %function
rec_flash_erase:
	push	{r4, lr}
	mov	r4, r0
	ldr	r1, =REC0
	cmp	r4, r1
	blo	22f
	ldr	r1, =REC_END
	cmp	r4, r1
	bhs	22f
	bl	rec_flash_unlock
	bl	rec_flash_wait
	ldr	r0, =FLASH_CTRL
	movs	r1, #0x02
	str	r1, [r0]
	ldr	r1, =FLASH_ADD
	str	r4, [r1]
	movs	r1, #0x42
	str	r1, [r0]
	bl	rec_flash_wait
	ldr	r0, =FLASH_CTRL
	movs	r1, #0x80
	str	r1, [r0]
22:	pop	{r4, pc}

@ rec_flash_word: r0 = word address inside the record pages, r1 = value (flash already unlocked)
	.thumb_func
	.type rec_flash_word, %function
rec_flash_word:
	push	{r4, r5, lr}
	mov	r4, r0
	mov	r5, r1
	ldr	r1, =REC0
	cmp	r4, r1
	blo	23f
	ldr	r1, =REC_END
	cmp	r4, r1
	bhs	23f
	bl	rec_flash_wait
	ldr	r0, =FLASH_CTRL
	movs	r1, #0x01
	str	r1, [r0]
	str	r5, [r4]
	nop				@ five NOPs after the store: no flash read while
	nop				@ the word programs (N32G45x user manual 3.2.1.4.2)
	nop
	nop
	nop
	bl	rec_flash_wait
	ldr	r0, =FLASH_CTRL
	movs	r1, #0x00
	str	r1, [r0]
23:	pop	{r4, r5, pc}

@ ----------------------------------------------------------------------------
@ slot_confirm - record OK for this slot when its start was a trial.
@   Scans the records; only when the newest record is TRIAL for SLOT_INDEX
@   it appends OK for SLOT_INDEX with that record's version. Any other state
@   writes nothing. Called just before the application start and right after
@   the USB start in update mode. The watchdog of a trial start is fed first,
@   so the record append (at most one page erase and three cell writes) has a
@   whole period; the trial window of slot_trial_wdg ends here.
@ ----------------------------------------------------------------------------
	.global slot_confirm
	.thumb_func
	.type slot_confirm, %function
slot_confirm:
	push	{r4, lr}
	bl	slot_feed
	bl	rec_scan
	cmp	r0, #SLOT_INDEX
	bne	24f
	ldr	r4, =TAB + SLOT_INDEX * 16
	ldr	r1, [r4, #4]
	cmp	r1, #ST_TRIAL
	bne	24f
	movs	r0, #SLOT_INDEX
	movs	r1, #ST_OK
	ldr	r2, [r4, #8]
	bl	rec_append
24:	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ slot_app_start - start the application when its vector table checks.
@   Initial SP (word 0x08006000) above 0x20000000 and at most 0x20024000;
@   reset vector (word 0x08006004) odd and inside 0x08006000..0x08061FFF.
@   Then the OK record (slot_confirm), a watchdog feed (a trial start hands a
@   whole period to the application's start-up), the hand-over word
@   HANDOVER_WORD = HANDOVER_TAG | WDG_ON << 8 | SLOT_INDEX (bit 8: the
@   watchdog runs, trial start or soft restart; bit 9: soft restart, so the
@   application keeps PA8 high; the application reads and clears it), the
@   flash locked (fn_08000ea4) and the hand-over: VTOR = 0x08006000,
@   MSP and PC from its table. When a check fails it returns and main goes to
@   update mode.
@   The vector page is the last page an update writes, so an update cut short
@   leaves 0x08006000 erased and the first check fails.
@ ----------------------------------------------------------------------------
	.global slot_app_start
	.thumb_func
	.type slot_app_start, %function
slot_app_start:
	push	{r4, lr}
	ldr	r4, =APP_BASE
	ldr	r0, [r4, #0]		@ initial SP
	mov	r1, #SRAM_LO
	cmp	r0, r1
	bls	25f
	ldr	r1, =SRAM_HI
	cmp	r0, r1
	bhi	25f
	ldr	r0, [r4, #4]		@ reset vector
	tst	r0, #1
	beq	25f
	bic	r0, r0, #1
	cmp	r0, r4
	blo	25f
	ldr	r1, =APP_END
	cmp	r0, r1
	bhs	25f
	bl	slot_confirm
	bl	slot_feed
	ldr	r0, =HANDOVER_WORD
	ldr	r2, =WDG_ON
	ldr	r2, [r2]		@ 0, 1 (trial) or 3 (soft restart)
	ldr	r1, =HANDOVER_TAG | SLOT_INDEX
	orr	r1, r1, r2, lsl #8	@ bit 8: watchdog running (the application may feed it),
					@ bit 9: soft restart
	str	r1, [r0]
	bl	fn_08000ea4		@ lock the flash
	ldr	r1, =0xE000ED08		@ VTOR = the application's table
	str	r4, [r1]
	dsb
	isb
	ldr	r0, [r4, #0]		@ MSP and PC from that table; no stack is used after
	ldr	r1, [r4, #4]		@ the switch (the stock start_application popped two
	msr	msp, r0			@ words from the new stack, so the application began
	bx	r1			@ with SP 8 bytes above its table value)
25:	pop	{r4, pc}

	.ltorg

@ ============================================================================
@ Feature version 2: the no-init words and the watchdog (USB_CONTROL_DESIGN.md
@ section 6). The words lie at 0x2001FFF4..0x2001FFFF (slot.inc), outside the
@ RAM every start code clears; the slot clears REQ_WORD only.
@ ============================================================================

@ ----------------------------------------------------------------------------
@ slot_trial_wdg - start the independent watchdog when this start is a trial.
@   First call of main. WDG_ON = 0; then the records are read as slot_confirm
@   reads them (rec_scan): only when the newest record is TRIAL for SLOT_INDEX
@   (the starter appended it for this start, starter/starter.s: INSTALL ->
@   TRIAL -> start) the watchdog is started with the application's own
@   sequence (V1.1 0x08010178..0x08010198): KEY 0x5555, PREDIV 2, RELV 0x9C4,
@   KEY 0xAAAA, KEY 0xCCCC, and WDG_ON = 1. Starting it forces the LSI on
@   (user manual 6.2.10, "the LSI oscillator will be forced ON").
@   No wait for STS PVU / CRVU (16.4.2 step 2): STS resets to 0 (table 16-2),
@   a system reset sets every register except RCC_CTRLSTS and the backup
@   domain to its reset value (6.1.2), and nothing writes PREDIV / RELV
@   between the reset and this point (starter: no IWDG access). After a soft
@   restart (BOOT_INSTALL: the starter trials this slot with the
@   application's IWDG running) the last PREDIV / RELV writes are the
@   application's start-up ones, long done, and these write the same values.
@   A trial slot that hangs before slot_confirm is reset by the watchdog and
@   the starter, finding TRIAL newest, starts the newest other OK slot or F.
@   Once started the watchdog runs until the next reset; slot_feed keeps it
@   fed in the update path, the application's own start-up rewrites the same
@   values and feeds it. Uses r0..r3, r12.
@ ----------------------------------------------------------------------------
	.global slot_trial_wdg
	.thumb_func
	.type slot_trial_wdg, %function
slot_trial_wdg:
	push	{r4, lr}
	ldr	r4, =WDG_ON
	movs	r0, #0
	str	r0, [r4]
	bl	rec_scan		@ r0 = slot of the newest record, or -1
	cmp	r0, #SLOT_INDEX
	bne	64f
	ldr	r1, =TAB + SLOT_INDEX * 16
	ldr	r1, [r1, #4]		@ its state
	cmp	r1, #ST_TRIAL
	bne	64f
	ldr	r0, =IWDG_KEY
	movw	r1, #IWDG_UNLOCK
	str	r1, [r0, #0]		@ PREDIV / RELV writable
	movs	r1, #IWDG_PREDIV
	str	r1, [r0, #4]		@ LSI / 16
	movw	r1, #IWDG_RELV
	str	r1, [r0, #8]		@ reload 2500
	movw	r1, #IWDG_RELOAD
	str	r1, [r0, #0]		@ counter = reload
	movw	r1, #IWDG_START
	str	r1, [r0, #0]		@ watchdog running
	movs	r1, #1
	str	r1, [r4]		@ WDG_ON = 1
64:	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ slot_feed - reload the watchdog (KEY 0xAAAA) when it runs (WDG_ON not 0:
@   trial start or soft restart); otherwise nothing is written to it. Keeps every
@   register and the flags (push / pop, ldr, cbz and str do not set flags), so
@   a call can go anywhere, in thread or interrupt code.
@ ----------------------------------------------------------------------------
	.global slot_feed
	.thumb_func
	.type slot_feed, %function
slot_feed:
	push	{r0, r1}
	ldr	r0, =WDG_ON
	ldr	r0, [r0]
	cbz	r0, 65f
	ldr	r0, =IWDG_KEY
	movw	r1, #IWDG_RELOAD
	str	r1, [r0, #0]
65:	pop	{r0, r1}
	bx	lr

@ ----------------------------------------------------------------------------
@ slot_key_check - the start check of main with the request word added.
@   r0 = GPIOC base, r1 = 0x80 (pin 7, the up key), as main passes them to
@   fn_080007a4. Reads REQ_WORD and clears it at every start. REQ_MAGIC
@   ("UPDT") and REQ_RESTART ("RSTR") come from the application's soft restart
@   (USB_CONTROL_DESIGN.md 6b), which leaves its IWDG running (it cannot be
@   stopped, manual 16): both set WDG_ON = 3 (bit 0: slot_feed then feeds it
@   in every wait, as on a trial start; bit 1: soft restart, hand-over bit 9;
@   slot_trial_wdg cleared it before) and feed it once here. REQ_MAGIC
@   returns r0 = 0 (as the key held: main goes to update
@   mode); every other value tail-calls fn_080007a4 with r0 / r1 unchanged
@   (its result: 0 key held, nonzero key up). Uses r2, r3, r12 before the
@   tail call.
@ ----------------------------------------------------------------------------
	.global slot_key_check
	.thumb_func
	.type slot_key_check, %function
slot_key_check:
	ldr	r2, =REQ_WORD
	ldr	r12, [r2]		@ r12 = request word
	movs	r3, #0
	str	r3, [r2]		@ cleared at every start
	ldr	r3, =REQ_MAGIC
	cmp	r12, r3
	beq	69f
	ldr	r3, =REQ_RESTART
	cmp	r12, r3
	bne	70f
69:	ldr	r2, =WDG_ON
	movs	r3, #3
	str	r3, [r2]		@ WDG_ON = 3: the application's watchdog runs, soft restart
	ldr	r2, =IWDG_KEY
	movw	r3, #IWDG_RELOAD
	str	r3, [r2, #0]		@ fed
	ldr	r3, =REQ_MAGIC
	cmp	r12, r3
	beq	66f
70:	b.w	fn_080007a4		@ key PC7 (tail call)
66:	movs	r0, #0			@ update request: as the key held
	bx	lr

@ ----------------------------------------------------------------------------
@ slot_finish - an update was written and checked (state 2, 0x20000274 = 2):
@   RESULT_WORD = RESULT_TAG << 16 | RES_OK << 8 | (~RES_OK & 0xFF), then the
@   wait as ten fn_0800320e(99) calls (1000 fn_08003224(1000) waits; the stock
@   fn_0800320e(1000) makes 1001) with a watchdog feed before each, then the
@   soft restart (slot_soft_restart; a system reset would switch the meter
@   off, NOTES 2026-11-20). When WDG_ON is not 0 (the IWDG runs) REQ_WORD =
@   REQ_RESTART first, so the next start feeds it; with WDG_ON = 0 (update
@   mode entered by the key at power-on, no IWDG) no word is written, so the
@   next start writes nothing to the stopped IWDG (the manual is
@   contradictory on whether 0xAAAA starts it). Never returns.
@ ----------------------------------------------------------------------------
	.global slot_finish
	.thumb_func
	.type slot_finish, %function
slot_finish:
	ldr	r0, =RESULT_WORD
	ldr	r1, =(RESULT_TAG << 16) | (RES_OK << 8) | (~RES_OK & 0xFF)
	str	r1, [r0]
	movs	r4, #10
67:	bl	slot_feed
	movs	r0, #99
	bl	fn_0800320e		@ 99 + 1 passes of fn_08003224(1000)
	subs	r4, r4, #1
	bne	67b
	ldr	r0, =WDG_ON
	ldr	r0, [r0]
	cbz	r0, 71f
	ldr	r0, =REQ_WORD
	ldr	r1, =REQ_RESTART
	str	r1, [r0]		@ the next start feeds the running watchdog
71:	b.w	slot_soft_restart

@ ----------------------------------------------------------------------------
@ slot_soft_restart - restart through the starter without a system reset
@   (USB_CONTROL_DESIGN.md 6b; the same steps as soft_restart of the
@   application, firmware/own/ctl.s, without the DMA: the slot enables no DMA
@   channel). Thread mode, called from main. Never returns. In this order:
@   - PRIMASK set;
@   - only while the USB clock is on (RCC_APB1PCLKEN USBEN, set by fn_080021dc
@     in update mode): D+ pull-up off (bit 28 of 0x40001820, read-modify-write),
@     USB_CTRL = FRST | PD (the host sees the drive leave), USBEN cleared;
@   - NVIC ICER0..2 and ICPR0..2 all ones (IRQ 20 / 42 of fn_08002c48
@     disabled, nothing pending); SysTick CTRL = 0 (main starts it in update
@     mode); the SysTick and PendSV pending bits cleared (ICSR);
@   - flash locked (fn_08000ea4);
@   - the system clock stays the PLL (the starter's record scan and image CRC
@     run at 144 MHz, inside the IWDG period); the next slot start switches to
@     HSI first (board_02.s fn_08002598, slot build);
@   - BASEPRI = 0, CONTROL = 0 (MSP), as after a reset;
@   - slot_feed (feeds only when WDG_ON is not 0);
@   - VTOR = 0, MSP = word 0x00000000, branch to word 0x00000004: the boot
@     space, where the meter maps main flash (the starter runs from there at
@     power-on), read as a reset reads it; PRIMASK stays set. (No value in
@     0x08000000..0x08005FFF is built: tests/check_never_brick.py W4.)
@   GPIOA is not written: PA8 stays driven high.
@ ----------------------------------------------------------------------------
	.global slot_soft_restart
	.thumb_func
	.type slot_soft_restart, %function
slot_soft_restart:
	cpsid	i
	ldr	r2, =SR_APB1PCLKEN
	ldr	r3, [r2]
	tst	r3, #SR_USBEN
	beq	72f
	ldr	r0, =SR_PULLUP
	ldr	r1, [r0]
	bic	r1, r1, #SR_PULLUP_BIT
	str	r1, [r0]		@ D+ pull-up off
	ldr	r0, =SR_USB_CTRL
	movs	r1, #SR_USB_OFF
	str	r1, [r0]		@ USB core in reset and powered down
	bic	r3, r3, #SR_USBEN
	str	r3, [r2]		@ USB clock off
72:	mvn	r1, #0
	ldr	r0, =SR_ICER0
	str	r1, [r0, #0]
	str	r1, [r0, #4]
	str	r1, [r0, #8]
	ldr	r0, =SR_ICPR0
	str	r1, [r0, #0]
	str	r1, [r0, #4]
	str	r1, [r0, #8]
	ldr	r0, =SR_SYST_CSR
	movs	r1, #0
	str	r1, [r0]		@ SysTick stopped
	ldr	r0, =SR_ICSR
	mov	r1, #SR_PEND_CLR
	str	r1, [r0]
	bl	fn_08000ea4		@ flash locked
	movs	r0, #0
	msr	basepri, r0
	msr	control, r0
	isb
	bl	slot_feed
	ldr	r0, =SR_VTOR
	movs	r1, #SR_BOOT_SPACE
	str	r1, [r0]		@ VTOR = 0, its value after a reset
	dsb
	isb
	ldr	r0, [r1, #0]		@ the starter's stack pointer
	ldr	r2, [r1, #4]		@ its reset entry
	msr	msp, r0
	bx	r2

	.ltorg

@ ============================================================================
@ UF2 update path. The host copies a .uf2 file (tools/bin2uf2.py) to the drive;
@ fn_0800302c collects every written 0x800-byte sector in 0x20000324 and
@ fn_080015c2 hands it to uf2_sector, whatever its LBA. Every 512-byte part
@ that is a valid LC1020E UF2 block is taken; everything else (directory,
@ FAT, metadata files, other files) is ignored.
@ State at U_BASE (0x20002140, slot.inc): state, error, the transfer key
@ (block count, image length, image CRC-32 from the extension tag), the
@ number of blocks taken, the erased-page and taken-block bitmaps; the
@ application vector page is collected in VBUF (0x20002300) and written last.
@ ============================================================================

@ ----------------------------------------------------------------------------
@ uf2_init - clear the transfer state (state idle). Called by main before the
@ USB start; RAM above 0x20002028 is not cleared by the start-up code.
@ ----------------------------------------------------------------------------
	.global uf2_init
	.thumb_func
	.type uf2_init, %function
uf2_init:
	ldr	r0, =U_BASE
	movs	r1, #0
	movs	r2, #U_SIZE / 4
26:	str	r1, [r0], #4
	subs	r2, r2, #1
	bne	26b
	bx	lr

@ ----------------------------------------------------------------------------
@ uf2_sector - one written sector of the update drive.
@   r0 = byte offset in the drive (not used: UF2 blocks carry their target),
@   r1 = data, r2 = length (0x800). Passes every whole 512-byte part to
@   uf2_block, then shows the state (uf2_show). Returns r0 = the length.
@ ----------------------------------------------------------------------------
	.global uf2_sector
	.thumb_func
	.type uf2_sector, %function
uf2_sector:
	push	{r4, r5, r6, lr}
	mov	r4, r1			@ r4 = part
	mov	r6, r2			@ r6 = length
	add	r5, r1, r2		@ r5 = end
	b	28f
27:	mov	r0, r4
	bl	uf2_block
	add	r4, r4, #512
28:	add	r0, r4, #512
	cmp	r0, r5
	bls	27b
	bl	uf2_show
	mov	r0, r6
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ uf2_block - examine one 512-byte part and take it when it is a block of the
@   transfer. r0 = the part. Nothing happens once the state is written (2) or
@   failed (3). A part is taken only when:
@     magic 0 / magic 1 / end magic match, flags have neither 0x1 (not main
@     flash) nor 0x1000 (file container) and have both 0x2000 (family ID) and
@     0x8000 (extension tags), family ID = UF2_FAMILY, payload size 256,
@     1 <= block count <= 1472, block number < block count, target =
@     0x08006000 + 256 * block number, the extension tag at byte 288 is
@     UF2_TAG with image length L (byte 292, L > 0, block count =
@     (L + 255) / 256) and image CRC-32 (byte 296).
@   A block whose key (count, L, CRC) differs from the transfer in progress
@   (or the first block) starts a new transfer (uf2_start). A block taken
@   before (bitmap) is skipped. Blocks for the vector page go to VBUF, the
@   others are programmed (uf2_program). When every block number has been
@   taken, uf2_finish checks the CRC and writes the vector page.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type uf2_block, %function
uf2_block:
	push	{r4, r5, r6, r7, r8, lr}
	mov	r5, r0			@ r5 = block
	ldr	r4, =U_BASE
	ldr	r0, [r4, #U_STATE]
	cmp	r0, #UST_DONE
	bhs	33f			@ written or failed: ignore everything
	ldr	r0, [r5, #0]
	ldr	r1, =UF2_MAGIC0
	cmp	r0, r1
	bne	33f
	ldr	r0, [r5, #4]
	ldr	r1, =UF2_MAGIC1
	cmp	r0, r1
	bne	33f
	ldr.w	r0, [r5, #508]
	ldr	r1, =UF2_MAGIC_END
	cmp	r0, r1
	bne	33f
	ldr	r0, [r5, #8]		@ flags
	tst	r0, #0x1		@ not main flash
	bne	33f
	tst	r0, #0x1000		@ file container
	bne	33f
	tst	r0, #0x2000		@ family ID present
	beq	33f
	tst	r0, #0x8000		@ extension tags present
	beq	33f
	ldr	r0, [r5, #28]
	ldr	r1, =UF2_FAMILY
	cmp	r0, r1
	bne	33f
	ldr	r0, [r5, #16]		@ payload size
	cmp	r0, #256
	bne	33f
	ldr	r6, [r5, #20]		@ r6 = block number
	ldr	r7, [r5, #24]		@ r7 = block count
	cmp	r7, #0
	beq	33f
	cmp	r7, #UF2_MAX_BLOCKS
	bhi	33f
	cmp	r6, r7
	bhs	33f
	ldr	r1, =APP_BASE
	add	r1, r1, r6, lsl #8	@ 0x08006000 + 256 * block number
	ldr	r0, [r5, #12]		@ target address
	cmp	r0, r1
	bne	33f
	ldr.w	r0, [r5, #288]		@ extension tag header
	ldr	r1, =UF2_TAG
	cmp	r0, r1
	bne	33f
	ldr.w	r8, [r5, #292]		@ r8 = image length
	ldr.w	r3, [r5, #296]		@ r3 = image CRC-32
	cmp	r8, #0
	beq	33f
	add	r0, r8, #255
	cmp	r7, r0, lsr #8		@ block count = (L + 255) / 256
	bne	33f
	@ the transfer key
	ldr	r0, [r4, #U_STATE]
	cmp	r0, #UST_RECEIVE
	bne	29f
	ldr	r0, [r4, #U_NUM]
	cmp	r0, r7
	bne	29f
	ldr	r0, [r4, #U_LEN]
	cmp	r0, r8
	bne	29f
	ldr	r0, [r4, #U_CRC]
	cmp	r0, r3
	beq	30f
29:	mov	r0, r7
	mov	r1, r8
	mov	r2, r3
	bl	uf2_start		@ r0 = 0 when the new transfer is set up
	cmp	r0, #0
	bne	33f
30:	@ r7 = bitmap word of this block, r8 = its bit
	add	r7, r4, #U_BLOCKS
	lsrs	r0, r6, #5
	add	r7, r7, r0, lsl #2
	and	r0, r6, #31
	movs	r1, #1
	lsl	r8, r1, r0
	ldr	r0, [r7]
	tst	r0, r8
	bne	33f			@ taken before
	ldr	r0, [r5, #12]		@ target
	add	r1, r5, #32		@ payload
	ldr	r2, =APP_VEC_END
	cmp	r0, r2
	bhs	31f
	ldr	r2, =APP_BASE		@ vector page: into VBUF
	subs	r0, r0, r2
	ldr	r2, =VBUF
	add	r0, r0, r2
	mov	r2, #256
	bl	copy_bytes
	b	32f
31:	bl	uf2_program		@ r0 = 0, or the error code
	cbz	r0, 32f
	bl	uf2_fail
	b	33f
32:	ldr	r0, [r7]		@ mark the block taken
	orr	r0, r0, r8
	str	r0, [r7]
	ldr	r0, [r4, #U_COUNT]
	adds	r0, r0, #1
	str	r0, [r4, #U_COUNT]
	ldr	r1, [r4, #U_NUM]
	cmp	r0, r1
	bne	33f
	bl	uf2_finish		@ every block taken
33:	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ uf2_start - start a new transfer. r0 = block count, r1 = image length,
@   r2 = image CRC-32 (the key). Stores the key, clears the count and both
@   bitmaps, fills VBUF with 0xFF, sets the state to receiving and erases the
@   application vector page 0x08006000 (checked all 0xFF). Returns r0 = 0, or
@   the error code after uf2_fail when the erase check failed.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type uf2_start, %function
uf2_start:
	push	{r4, lr}
	ldr	r4, =U_BASE
	str	r0, [r4, #U_NUM]
	str	r1, [r4, #U_LEN]
	str	r2, [r4, #U_CRC]
	movs	r0, #0
	str	r0, [r4, #U_COUNT]
	add	r1, r4, #U_PAGES
	movs	r2, #(U_SIZE - U_PAGES) / 4
34:	str	r0, [r1], #4		@ both bitmaps
	subs	r2, r2, #1
	bne	34b
	ldr	r1, =VBUF
	mvn	r0, #0
	mov	r2, #FLASH_PAGE / 4
35:	str	r0, [r1], #4
	subs	r2, r2, #1
	bne	35b
	movs	r0, #UST_RECEIVE
	str	r0, [r4, #U_STATE]
	ldr	r0, =APP_BASE
	bl	uf2_erase_page		@ the vector page first: 0x08006000 erased from here on
	cbnz	r0, 36f
	ldr	r1, [r4, #U_PAGES]
	orr	r1, r1, #1		@ page 0 erased
	str	r1, [r4, #U_PAGES]
	pop	{r4, pc}
36:	bl	uf2_fail
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ uf2_fail - r0 = error code (ERR_*): state failed, error stored. Further
@   blocks are ignored until the next reset. Returns r0 = the code.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type uf2_fail, %function
uf2_fail:
	ldr	r1, =U_BASE
	str	r0, [r1, #U_ERR]
	movs	r2, #UST_FAIL
	str	r2, [r1, #U_STATE]
	bx	lr

@ ----------------------------------------------------------------------------
@ uf2_erase_page - r0 = page base in the application area. Feeds the
@   watchdog (slot_feed: one page erase takes up to 100 ms), unlocks the
@   flash (fn_08000efc), erases the page (fn_08000e24, gated), locks it
@   (fn_08000ea4) and reads the page back. Returns r0 = 0 when all 512
@   words are 0xFFFFFFFF, else ERR_ERASE.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type uf2_erase_page, %function
uf2_erase_page:
	push	{r4, lr}
	bl	slot_feed
	mov	r4, r0
	bl	fn_08000efc		@ unlock
	mov	r0, r4
	bl	fn_08000e24		@ page erase
	bl	fn_08000ea4		@ lock
	mov	r1, #FLASH_PAGE / 4
37:	ldr	r0, [r4], #4
	adds	r0, r0, #1		@ zero only for 0xFFFFFFFF
	bne	38f
	subs	r1, r1, #1
	bne	37b
	movs	r0, #0
	pop	{r4, pc}
38:	movs	r0, #ERR_ERASE
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ uf2_program - program one block outside the vector page.
@   r0 = target (256-aligned, 0x08006800..0x08061F00), r1 = 256-byte payload.
@   Erases the target's page first when the erased-page bitmap does not have
@   it yet (uf2_erase_page, then the bit is set). Programs the 64 words with
@   fn_08000eb4 (gated; 6 = done; words 0xFFFFFFFF are left erased) and reads
@   every word back. Returns r0 = 0,
@   ERR_ERASE or ERR_PROGRAM. The flash is locked again in every case.
@   The watchdog is fed first (slot_feed), once per block of 64 words, and
@   again by uf2_erase_page before a page erase.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type uf2_program, %function
uf2_program:
	push	{r4, r5, r6, r7, r8, lr}
	bl	slot_feed
	mov	r4, r0			@ r4 = target
	mov	r5, r1			@ r5 = payload
	ldr	r1, =APP_BASE
	subs	r0, r4, r1
	lsrs	r0, r0, #11		@ page index
	ldr	r2, =U_BASE + U_PAGES
	lsrs	r1, r0, #5
	add	r7, r2, r1, lsl #2	@ r7 = bitmap word of the page
	and	r0, r0, #31
	movs	r1, #1
	lsl	r8, r1, r0		@ r8 = its bit
	ldr	r0, [r7]
	tst	r0, r8
	bne	39f
	lsrs	r0, r4, #11
	lsls	r0, r0, #11		@ page base
	bl	uf2_erase_page
	cbnz	r0, 41f
	ldr	r0, [r7]
	orr	r0, r0, r8
	str	r0, [r7]
39:	bl	fn_08000efc		@ unlock
	movs	r6, #0			@ r6 = byte offset in the block
40:	ldr	r1, [r5, r6]
	adds	r0, r1, #1		@ 0xFFFFFFFF: the erased word holds it already
	beq	56f
	adds	r0, r4, r6
	bl	fn_08000eb4		@ program one word
	cmp	r0, #6
	bne	42f
56:	ldr	r0, [r4, r6]		@ read it back
	ldr	r1, [r5, r6]
	cmp	r0, r1
	bne	42f
	adds	r6, r6, #4
	cmp	r6, #256
	blo	40b
	bl	fn_08000ea4		@ lock
	movs	r0, #0
41:	pop	{r4, r5, r6, r7, r8, pc}
42:	bl	fn_08000ea4		@ lock
	movs	r0, #ERR_PROGRAM
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ uf2_finish - every block has been taken.
@   CRC-32 over the image length L: the first min(L, 0x800) bytes from VBUF,
@   the rest from flash at 0x08006800 in parts of 2 KiB with a watchdog feed
@   before each (slot_feed). A CRC other than the key's -> failed
@   (ERR_CRC), 0x08006000 stays erased. Otherwise programs the vector page
@   from VBUF in two passes (words still 0xFFFFFFFF are left erased): words
@   2..511 from the last one down, read back; then the reset vector and the
@   initial SP, read back. So the two words that make the application
@   startable are written only after the rest of the page is verified. Any
@   failure there erases the
@   vector page again and fails with ERR_VECTOR. Success: state written and
@   the stock state byte 0x20000274 = 2 (main waits 1000 ms and resets).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type uf2_finish, %function
uf2_finish:
	push	{r4, r5, r6, lr}
	ldr	r4, =U_BASE
	ldr	r6, =VBUF
	ldr	r5, [r4, #U_LEN]
	mvn	r0, #0
	mov	r1, r6
	mov	r2, r5
	cmp	r2, #FLASH_PAGE
	it	hi
	movhi	r2, #FLASH_PAGE
	bl	crc32_update		@ the vector page part, from RAM
	subs	r5, r5, #FLASH_PAGE	@ r5 = bytes left, from flash
	bls	43f
	ldr	r1, =APP_VEC_END
68:	bl	slot_feed		@ one feed per 2 KiB of the CRC
	mov	r2, r5
	cmp	r2, #FLASH_PAGE
	it	hi
	movhi	r2, #FLASH_PAGE
	subs	r5, r5, r2
	bl	crc32_update		@ the rest, from flash; r1 moves on by r2
	cmp	r5, #0
	bne	68b
43:	mvns	r0, r0
	ldr	r1, [r4, #U_CRC]
	cmp	r0, r1
	beq	44f
	movs	r0, #ERR_CRC
	bl	uf2_fail
	pop	{r4, r5, r6, pc}
44:	bl	slot_feed		@ the vector page writes get a whole period
	bl	fn_08000efc		@ unlock
	movw	r5, #FLASH_PAGE - 4	@ pass 1: words 2..511, last word first
45:	bl	vpage_word
	cmp	r0, #6
	bne	48f
	subs	r5, r5, #4
	cmp	r5, #8
	bhs	45b
	movs	r0, #8			@ read back words 2..511 before the vector words
	mov	r1, #(FLASH_PAGE - 8) / 4
	bl	vpage_verify
	cmp	r0, #0
	bne	48f
	movs	r5, #4			@ pass 2: reset vector, then initial SP
46:	bl	vpage_word
	cmp	r0, #6
	bne	48f
	subs	r5, r5, #4
	bpl	46b
	bl	fn_08000ea4		@ lock
	movs	r0, #0			@ read back words 0..1
	movs	r1, #2
	bl	vpage_verify
	cmp	r0, #0
	bne	49f
	movs	r0, #UST_DONE
	str	r0, [r4, #U_STATE]
	ldr	r1, =BOOT_STATE
	strb	r0, [r1]		@ 2: main waits 1000 ms and resets the chip
	pop	{r4, r5, r6, pc}
48:	bl	fn_08000ea4		@ lock
49:	ldr	r0, =APP_BASE
	bl	uf2_erase_page		@ leave 0x08006000 erased
	movs	r0, #ERR_VECTOR
	bl	uf2_fail
	pop	{r4, r5, r6, pc}

@ vpage_word - program the vector-page word at offset r5 from VBUF (r6); a value
@   of 0xFFFFFFFF is left erased. Returns r0 = 6 (the gated programming routine's
@   success code) or its error code. r5 and r6 are kept.
	.thumb_func
	.type vpage_word, %function
vpage_word:
	push	{lr}
	ldr	r1, [r6, r5]
	adds	r0, r1, #1		@ 0xFFFFFFFF: nothing to program
	beq	50f
	ldr	r0, =APP_BASE
	add	r0, r0, r5
	bl	fn_08000eb4
	pop	{pc}
50:	movs	r0, #6
	pop	{pc}

@ vpage_verify - compare r1 words of the vector page from offset r0 with VBUF
@   (r6). Returns r0 = 0 when equal, 1 at the first difference.
	.thumb_func
	.type vpage_verify, %function
vpage_verify:
	ldr	r2, =APP_BASE
	add	r2, r2, r0
	add	r3, r6, r0
51:	ldr	r0, [r2], #4
	ldr	r12, [r3], #4
	cmp	r0, r12
	bne	52f
	subs	r1, r1, #1
	bne	51b
	movs	r0, #0
	bx	lr
52:	movs	r0, #1
	bx	lr

@ ----------------------------------------------------------------------------
@ uf2_show - the transfer state on the display, where the stock code shows
@   its percentage (fn_0800155c at x 0x94, y 0x78): receiving / written ->
@   "<blocks taken * 100 / block count>%"; failed -> "Err<code>"; idle ->
@   nothing. The font covers the characters 0x25..0x74 only.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type uf2_show, %function
uf2_show:
	push	{r4, lr}
	ldr	r4, =U_BASE
	ldr	r0, [r4, #U_STATE]
	cmp	r0, #UST_FAIL
	beq	50f
	cbz	r0, 51f
	ldr	r0, [r4, #U_COUNT]
	movs	r1, #100
	muls	r0, r1, r0
	ldr	r1, [r4, #U_NUM]
	udiv	r3, r0, r1
	adr	r2, pct_text
	movs	r1, #0x78
	movs	r0, #0x94
	bl	fn_0800155c
	pop	{r4, pc}
50:	ldr	r3, [r4, #U_ERR]
	adr	r2, err_text
	movs	r1, #0x78
	movs	r0, #0x94
	bl	fn_0800155c
51:	pop	{r4, pc}
	.p2align 2
pct_text:
	.asciz	"%d%%"
	.p2align 2
err_text:
	.asciz	"Err%d"
	.p2align 2

@ ----------------------------------------------------------------------------
@ slot_read_sector - a read of the update drive: the stock sector image
@   (fn_08003bd8) with the status file added. r0 = byte offset, r1 = 0x800
@   byte buffer. Returns r0 = 0x800.
@     0x3000 / 0x3800 (both FATs): byte 4 = 0x0F, so the FAT12 entry of
@       cluster 2 is 0xFFF (end of chain);
@     0x4000 (root): entry 0 (Ready.TXT) gets first cluster 2 and size 32;
@     0x8000 (cluster 2): the 32-byte status text of the transfer state, the
@       error code as a digit at byte 28 when failed (rest of the sector is
@       the stock zero fill).
@   The drive has DRIVE_SECTORS sectors, so FAT12 (under 4085 clusters).
@ ----------------------------------------------------------------------------
	.global slot_read_sector
	.thumb_func
	.type slot_read_sector, %function
slot_read_sector:
	push	{r4, r5, r6, lr}
	mov	r4, r0			@ r4 = offset
	mov	r5, r1			@ r5 = buffer
	bl	fn_08003bd8		@ stock sector image
	cmp	r4, #0x3000
	beq	52f
	cmp	r4, #0x3800
	beq	52f
	cmp	r4, #0x4000
	beq	53f
	cmp	r4, #0x8000
	beq	54f
	b	55f
52:	movs	r0, #0x0F
	strb	r0, [r5, #4]		@ cluster 2: 0xFFF
	b	55f
53:	movs	r0, #2
	strh	r0, [r5, #26]		@ Ready.TXT: first cluster 2
	movs	r0, #STATUS_LEN
	str	r0, [r5, #28]		@ Ready.TXT: size
	b	55f
54:	ldr	r6, =U_BASE
	ldr	r0, [r6, #U_STATE]
	adr	r1, status_text
	add	r1, r1, r0, lsl #5	@ text of this state (32 bytes each)
	mov	r0, r5
	movs	r2, #STATUS_LEN
	bl	copy_bytes
	ldr	r0, [r6, #U_STATE]
	cmp	r0, #UST_FAIL
	bne	55f
	ldr	r0, [r6, #U_ERR]
	adds	r0, r0, #'0'
	strb	r0, [r5, #28]		@ the error digit
55:	mov	r0, #0x800
	pop	{r4, r5, r6, pc}

	.ltorg

	.p2align 2
status_text:				@ one text per state, STATUS_LEN bytes each
	.ascii	"LC1020E-IAP ready, copy a .uf2\r\n"	@ 0 idle
	.ascii	"LC1020E-IAP receiving the .uf2\r\n"	@ 1 receiving
	.ascii	"LC1020E-IAP update written, OK\r\n"	@ 2 written
	.ascii	"LC1020E-IAP update failed, E0 \r\n"	@ 3 failed (digit at byte 28)
	.if	. - status_text != 4 * STATUS_LEN
	.error	"status texts must be STATUS_LEN bytes each"
	.endif

.endif
