@ fix.s - corrections of vendor defects in our build.
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ own_obj_del - entered from the first instruction of the object delete fn_08023690 (gui_21.s,
@   .ifdef OWN), r0 = the object to delete.
@   The defect: an immediate screen load (fn_08026b88 with time 0) leaves the display record's
@   "screen to load" word (+0x18; the default display record is the word at 0x20000478) on the
@   new screen, because only the end of a load animation (fn_08029320, 0x08029364) clears it.
@   When that screen is deleted later (holding OK: fn_08009614 -> fn_08023690(word 0x200001D8)),
@   the word keeps the freed object, and the next screen load (fn_08026b88: +0x18 differs from the
@   active screen +0x10) sends events to the freed object (fn_0802939a -> fn_0802636a ->
@   fn_08025d34 -> fn_08023d54, which calls the handler read from the freed memory).
@   The fix: when +0x18 names the object being deleted, it is cleared to 0 first (no screen is then
@   waiting to be loaded, as after a completed animation). Then the two instructions that the
@   branch replaced (push {r4, r5, r6, lr}; mov r5, r0) and the rest of fn_08023690.
@   Before that, pwr_obj_del (power.s) is told of the deletion (r0, and r1 = the return address
@   of the call), so that the low-voltage popup objects are never deleted a second time (the
@   background 0x20000290 goes away with the screen it was built on); when it answers r12 = 1
@   (0x0800C724 removing a background that is already gone) fn_08023690 returns at once.
@   r1 and r2 are kept; r12 and the flags are changed (fn_08023690 sets the flags itself before
@   any use; r12 is a scratch register of every call under AAPCS, and fn_08023690 is reached
@   only through calls).

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

	.section .text.own.fix,"ax",%progbits
	.p2align 2
	.global	own_obj_del
	.thumb_func
	.type	own_obj_del, %function
own_obj_del:
	push	{r0, r1, r2, lr}
	mov	r1, lr			@ return address of the call of fn_08023690
	bl	pwr_obj_del		@ power.s: popup objects of the countdown (keeps r0)
	cmp	r12, #0
	bne	2f			@ the object is gone already: no deletion
	ldr	r1, =0x20000478		@ word: the default display record
	ldr	r1, [r1]
	cbz	r1, 1f			@ no display yet
	ldr	r2, [r1, #0x18]		@ screen to load
	cmp	r2, r0
	bne	1f
	movs	r2, #0
	str	r2, [r1, #0x18]		@ the object goes away: nothing waits to be loaded
1:	pop	{r0, r1, r2, lr}
	push	{r4, r5, r6, lr}	@ the two instructions of fn_08023690 the branch replaced
	mov	r5, r0
	b.w	own_obj_del_back
2:	pop	{r0, r1, r2, pc}	@ back to the caller of fn_08023690

@ ----------------------------------------------------------------------------
@ own_event_obj - entered from the first instruction of the event send fn_0802636a (gui_24.s,
@   .ifdef OWN): r0 = object, r1, r2 passed on; returns nothing.
@   The defect: a screen load (fn_08026b88) sends its events to the active screen (fn_08026b78,
@   display record +0x10); after the active screen was deleted (fn_08023690 clears +0x10) that is
@   object 0, and the event code then reads and writes at small addresses (fn_0801b418 stores at
@   object + 0x22), which on the chip lie in the boot alias of the flash (manual 3.1.3).
@   The fix: an event for object 0 is not sent (returns at once). Otherwise the two instructions
@   that the branch replaced (push {r4, r5, r6, lr}; mov r5, r2) and the rest of fn_0802636a.
@ ----------------------------------------------------------------------------
	.global	own_event_obj
	.thumb_func
	.type	own_event_obj, %function
own_event_obj:
	cbz	r0, 2f			@ object 0: nothing to send
	push	{r4, r5, r6, lr}
	mov	r5, r2
	b.w	own_event_obj_back
2:	bx	lr

@ ----------------------------------------------------------------------------
@ own_dma_rearm - replaces the three calls of fn_080087ce in the DMA2 channel 3 interrupt
@   fn_080085d0 (periph_34.s, .ifdef OWN): r0 = channel register block (CHCFG at +0, TXNUM at
@   +4: 0x40020008 DMA1 ch1, 0x40020094 DMA1 ch8, 0x40020458 DMA2 ch5), r1 = transfer count.
@   The defect: the handler writes the count and then enables the channel (fn_08008770) while an
@   acquisition may still run (128 samples at 127.9 kHz take 1.00089 ms against the 1 ms DAC
@   period at 1 kHz); the user manual (DMA chapter, end of transfer): "To start a new DMA transfer,
@   need to rewrite the transfer number in the DMA_TXNUMx register with the DMA channel disabled";
@   written while enabled, the count is lost and the channel is enabled with count 0: the
@   measurement stops (emulator, NOTES "Measurement path in the emulator").
@   The fix: CHCFG bit 0 (CHEN) cleared first (the acquisition still running is restarted, which is
@   what the request byte 0x200011C4 asks for), then the count as before; fn_08008770 enables it.
@   The re-arm generation (MEASUREMENT_FIX_DESIGN.md S1.4): for DMA1 channel 1 (r0 = 0x40020008,
@   the first of the three calls, periph_34.s; one call per re-arm, made only while the request
@   byte was set) the word OWN_MEAS + MO_G is incremented, so own_measure (meas.s) can tell its
@   own acquisition from one started by another writer of the request byte. Only this code writes
@   the word; it runs inside the interrupt, so the main loop never sees a half-done update.
@   Uses r2, r3 (fn_080085d0 loads r0 and r1 again before each call and keeps its own values in
@   r4..r6); r0, r1 as for fn_080087ce.
@ ----------------------------------------------------------------------------
	.global	own_dma_rearm
	.thumb_func
	.type	own_dma_rearm, %function
own_dma_rearm:
	ldr	r2, =DMA1_CH1
	cmp	r0, r2
	bne	1f			@ channels 8 and DMA2 5: no count
	ldr	r2, =OWN_MEAS
	ldr	r3, [r2, #MO_G]
	adds	r3, r3, #1		@ one more re-arm (wraps at 2^32; meas.s compares the
	str	r3, [r2, #MO_G]		@ signed difference)
1:	ldr	r2, [r0, #0]
	bic	r2, r2, #1		@ CHEN off: the count may be written now
	str	r2, [r0, #0]
	b.w	fn_080087ce

	.ltorg
