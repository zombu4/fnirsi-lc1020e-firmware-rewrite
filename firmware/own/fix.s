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
@   V and I together: in the call for ch1 the CHEN bits of ch1 (ADC1, V) and ch8 (ADC2, I) are
@   cleared by two consecutive stores with interrupts masked (the call for ch8 then finds CHEN
@   0). A conversion that ends while a channel is off leaves its request held and served as the
@   first item when the channel is enabled again (measure_model.py header: "held, one at a
@   time"); when ch1 was off and ch8 still on for that conversion, ch8 took it into the old
@   transfer and only ch1 began with it: I one sample behind V (own_dma_enable, below, has the
@   numbers). Off and on together, both channels hold the same conversion or neither does.
@   Uses r2, r3, r12 and r4 saved (fn_080085d0 loads r0 and r1 again before each call and keeps
@   its own values in r4..r6); r0, r1 as for fn_080087ce.
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
	push	{r4}			@ r4 holds PRIMASK across the two stores
	ldr	r2, [r0, #0]
	bic	r2, r2, #1		@ r2 = ch1 CHCFG with CHEN 0
	ldr	r3, =DMA1_CH8
	ldr	r12, [r3, #0]
	bic	r12, r12, #1		@ r12 = ch8 CHCFG with CHEN 0
	mrs	r4, PRIMASK		@ r4 = PRIMASK as found
	cpsid	i			@ no interrupt between the two stores
	str	r2, [r0, #0]		@ ch1 off
	str	r12, [r3, #0]		@ ch8 off, the next instruction
	msr	PRIMASK, r4		@ PRIMASK as it was
	pop	{r4}
	b.w	fn_080087ce		@ the count of ch1 (r0, r1 unchanged)
1:	ldr	r2, [r0, #0]
	bic	r2, r2, #1		@ CHEN off: the count may be written now
	str	r2, [r0, #0]
	b.w	fn_080087ce

@ ----------------------------------------------------------------------------
@ own_dma_enable - replaces the three fn_08008770(channel, 1) calls at the end of fn_080085d0
@   (periph_34.s 0x0800860C, .ifdef OWN; the tail after pop.w {r4, r5, r6, lr}): r0 = DMA1 ch1,
@   r1 = DMA1 ch8, r2 = DMA2 ch5 register block (CHCFG at +0). The defect: the vendor enables
@   the three channels one after the other while TIM1 keeps triggering the ADCs, so a CC3
@   trigger between the enable of ch1 (ADC1, V) and ch8 (ADC2, I) gives buffers one sample apart
@   (MEASUREMENT_FIX_DESIGN.md 2 "offset by one sample"); in the emulator 386 of 1531
@   acquisitions at 10 kHz had theta 11.25 deg (= 360 / 32, one sample) below the others
@   (2026-11-22, a calibration sweep point), and the outlier rule then reset the window on
@   every such run. The fix: both CHCFG words are computed first (each as fn_08008770 does:
@   CHCFG | 1) and stored by two consecutive instructions with interrupts masked, so the gap a
@   trigger can fall into is one store instead of two calls (TIM1 keeps running: stopping it
@   was tried and made the first sample of an acquisition early when a conversion was in flight,
@   a non-uniform buffer: m02 at 100 kHz |Z| 5.33e-3 off, bound 1.64e-3, 2026-11-22); a single
@   skewed acquisition left is an outlier of the window (meas_outlier), three in a row are not
@   expected. Then DMA2 ch5 as before. Uses r3, r12; r4 saved (PRIMASK).
@ ----------------------------------------------------------------------------
	.global	own_dma_enable
	.thumb_func
	.type	own_dma_enable, %function
own_dma_enable:
	push	{r4, lr}		@ r4 holds PRIMASK across the two stores
	ldr	r3, [r0]
	orr	r3, r3, #1		@ r3 = DMA1 ch1 CHCFG with CHEN (ADC1, V)
	ldr	r12, [r1]
	orr	r12, r12, #1		@ r12 = DMA1 ch8 CHCFG with CHEN (ADC2, I)
	mrs	r4, PRIMASK		@ r4 = PRIMASK as found
	cpsid	i			@ no interrupt between the two stores
	str	r3, [r0]		@ ch1 on
	str	r12, [r1]		@ ch8 on, the next instruction
	msr	PRIMASK, r4		@ PRIMASK as it was
	ldr	r3, [r2]
	orr	r3, r3, #1
	str	r3, [r2]		@ DMA2 ch5 CHEN (ADC3)
	pop	{r4, pc}

	.ltorg
