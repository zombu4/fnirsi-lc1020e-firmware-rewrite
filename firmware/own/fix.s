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
@   0), inside the quiet part of a TIM1 period (tq_pair, below). A conversion that
@   ends while one channel is already off and the other still on is taken by the second into
@   its old transfer and not by the first; whether the DMA then keeps the first one's request
@   for its enable (the emulator does: measure_model.py header, "held, one at a time") or drops
@   it, the manual does not say, and with a held request V starts one conversion before I.
@   With no conversion end between the two stores both channels are in the same state when
@   the enable (own_dma_enable, also in a quiet part) starts them: both see the same
@   conversions from here on.
@   Uses r2, r3, r12; r4 saved (fn_080085d0 loads r0 and r1 again before each call and keeps
@   its own values in r4..r6); r0, r1 as for fn_080087ce, kept on the stack across tq_pair.
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
	push	{r0, r1, r4, lr}	@ r4 PRIMASK
	mrs	r4, PRIMASK		@ r4 = PRIMASK as found
	cpsid	i			@ no interrupt from reading CHCFG to the end of the pair
	ldr	r1, [r0, #0]
	bic	r1, r1, #1		@ r1 = ch1 CHCFG with CHEN 0
	ldr	r2, =DMA1_CH8
	ldr	r3, [r2, #0]
	bic	r3, r3, #1		@ r3 = ch8 CHCFG with CHEN 0
	bl	tq_pair			@ ch1 off, ch8 off, in the quiet part of a TIM1 period
	msr	PRIMASK, r4		@ PRIMASK as it was
	pop	{r0, r1, r4, lr}
	b.w	fn_080087ce		@ the count of ch1 (r0, r1 as on entry)
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
@   every such run. The fix: both CHCFG words are computed (each as fn_08008770 does: CHCFG | 1)
@   and stored by two consecutive instructions with interrupts masked, inside the quiet part of
@   a TIM1 period (tq_pair, below), so no conversion ends between the two stores.
@   Revision 16 had the two stores alone: their position in the TIM1 period is fixed by where
@   the DMA2 ch3 interrupt comes in it, and that is set at each start of the generator
@   (fn_08009f10) by the instruction times of the start-up path: one TIM6 update (40 ticks of
@   72 MHz) earlier or later moves it by 0.178 of the 10-kHz conversion period. Revision 17's
@   start-up put the pair on the conversion end, and the entry jitter of the interrupt (the
@   instruction it waits for) split it in 54 of 1269 acquisitions in 2 s (L 10 mH, 10 kHz,
@   theta 11.25 deg low each; test_own_measure m02 failed when one of them entered a window).
@   TIM1 keeps running: stopping it was tried and made the first sample of an acquisition early
@   when a conversion was in flight, a non-uniform buffer (m02 at 100 kHz |Z| 5.33e-3 off,
@   bound 1.64e-3, 2026-11-22). Then DMA2 ch5 as before (ADC3: only its peak-to-peak value is
@   used, fn_0800b000). Uses r0..r3, r12; r4 saved, r5 pushed for an 8-byte aligned stack, r2
@   (the DMA2 ch5 block) kept on the stack across tq_pair.
@ ----------------------------------------------------------------------------
	.global	own_dma_enable
	.thumb_func
	.type	own_dma_enable, %function
own_dma_enable:
	push	{r2, r4, r5, lr}	@ r2 the DMA2 ch5 block, r4 PRIMASK
	mrs	r4, PRIMASK		@ r4 = PRIMASK as found
	cpsid	i			@ no interrupt from reading CHCFG to the end of the pair
	mov	r2, r1			@ r2 = DMA1 ch8 block
	ldr	r1, [r0]
	orr	r1, r1, #1		@ r1 = DMA1 ch1 CHCFG with CHEN (ADC1, V)
	ldr	r3, [r2]
	orr	r3, r3, #1		@ r3 = DMA1 ch8 CHCFG with CHEN (ADC2, I)
	bl	tq_pair			@ ch1 on, ch8 on, in the quiet part of a TIM1 period
	msr	PRIMASK, r4		@ PRIMASK as it was
	ldr	r2, [sp, #0]		@ r2 = DMA2 ch5 block
	ldr	r3, [r2]
	orr	r3, r3, #1
	str	r3, [r2]		@ DMA2 ch5 CHEN (ADC3)
	pop	{r2, r4, r5, pc}

@ ----------------------------------------------------------------------------
@ tq_pair - the CHEN store pair of DMA1 channels 1 and 8 (own_dma_rearm: both off,
@   own_dma_enable: both on), stored where no conversion end of ADC1 / ADC2 can split it.
@   r0 = ch1 register block, r1 = its CHCFG word, r2 = ch8 register block, r3 = its CHCFG word.
@   Called with interrupts masked (the caller restores PRIMASK). Facts used: every regular conversion of ADC1 and ADC2 starts on the TIM1_CC3 event
@   (CTRL2 EXTRSEL 010, measure_model.py header; manual table 9-5), which is the match of the
@   counter with CCDAT3 = 1 (meas.s own_tim1_setup, the channel block of fn_08007e7c: mode
@   0x70 PWM mode 2, pulse 1, CC3 an output), once per period of
@   P = AR + 1 timer ticks; at that match STS CC3ITF is set by hardware (manual 11.4.6:
@   "set by hardware when the counter value is the same as the compare value"; cleared by
@   writing 0, rc_w0). A conversion of 1.5 sample cycles takes 3 + 1.5 + 12.5 = 17 ADC clocks
@   (manual 9, "Programmable channel sampling time": TCONV = sampling time + 12.5 cycles, "an
@   additional 3 cycles ... for each conversion in single conversion mode"; CTRL2 CTU 0, sample
@   time code 0 for ADC1 channel 3 and ADC2 channel 4), 34 TIM1 ticks with the ADC at
@   HCLK / 2 and TIM1 at HCLK (RCC_CFG2 ADCHPRES 1, APB2 / 2: measure_model.py header); the
@   smallest P is 180 (100 kHz: AR = 144000000 / (8 f) - 1 = 179), so a conversion triggered at
@   CNT = 1 ends, with its DMA request, before CNT = P / 2 by at least 55 ticks (the manual
@   gives no trigger or DMA latency; that margin is the part not stated by it).
@   Procedure: CC3ITF cleared, then CNT read, until one such read finds CNT in [P / 2, 3 P / 4):
@   then the latest match lies at CNT = 1 of this period, at least P / 2 - 1 ticks before the
@   read, and its conversion has ended. The two stores follow that read after three
@   instructions (subs, cmp, the taken blo), and STS is read right after them: CC3ITF 0 proves
@   that no match, so no conversion, came between the window read and the second store. The
@   window ends at 3 P / 4 so that the five instructions normally end before the next period
@   (a match during them is caught by the STS read; in the emulator, 5 cycles per instruction,
@   they take 25 ticks against the 45 left at 100 kHz). CC3ITF 1, or no window within TQ_POLLS
@   reads (with TIM1 counting it comes within one period, at most 65536 ticks, while each read
@   takes at least 4 core cycles at the TIM1 clock or faster; the pair is then stored anyway):
@   not proven, MO_G + 1 more, so own_measure (meas.s step 1, G - G_exp > 0) does not use this
@   acquisition and re-arms; MO_G is changed only inside the DMA2 channel 3 interrupt, as by
@   own_dma_rearm. TIM1 not counting (CTRL1 CNTEN 0): no match, no conversion: the pair at
@   once (interrupts are masked, so nothing starts TIM1 before the stores).
@   The first version (tq_open before the CHCFG reads, tq_close called after the stores) had 16
@   instructions between the window read and the flag read, 80 emulated ticks: at 100 kHz every
@   pair saw the next match and was marked, no acquisition was used (diagnostic, 2026-11-24).
@   Uses r0..r3, r12; r4..r8 saved.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	tq_pair, %function
tq_pair:
	push	{r4, r5, r6, r7, r8, lr}
	ldr	r4, =TIM1_BASE
	ldr	r5, [r4, #TIM_CTRL1]
	tst	r5, #TIM_CNTEN
	beq	.Ltq_free		@ TIM1 stopped: no CC3 match, no conversion
	ldr	r5, [r4, #TIM_AR]
	adds	r5, r5, #1		@ r5 = P = AR + 1
	lsrs	r6, r5, #2		@ r6 = P / 4, the width of the window
	lsrs	r5, r5, #1		@ r5 = P / 2, its start
	ldr	r7, =TIM_STS_CC3CLR
	movw	r8, #TQ_POLLS		@ r8 = reads left
.Ltq_poll:
	str	r7, [r4, #TIM_STS]	@ CC3ITF 0, the other flags as they are
	ldr	r12, [r4, #TIM_CNT]	@ the window read
	subs	r12, r12, r5		@ CNT - P / 2 (below P / 2: a large unsigned value)
	cmp	r12, r6
	blo	.Ltq_quiet		@ P / 2 <= CNT < 3 P / 4
	subs	r8, r8, #1
	bne	.Ltq_poll
	str	r1, [r0]		@ no window within TQ_POLLS reads: the pair all the same,
	str	r3, [r2]
	b	.Ltq_mark		@ not proven
.Ltq_quiet:
	str	r1, [r0]		@ ch1
	str	r3, [r2]		@ ch8, the next instruction
	ldr	r12, [r4, #TIM_STS]
	tst	r12, #TIM_CC3ITF
	beq	.Ltq_ret		@ no match since the window read: proven
.Ltq_mark:
	ldr	r4, =OWN_MEAS
	ldr	r5, [r4, #MO_G]
	adds	r5, r5, #1		@ the acquisition is marked foreign: not used
	str	r5, [r4, #MO_G]
	b	.Ltq_ret
.Ltq_free:
	str	r1, [r0]		@ ch1
	str	r3, [r2]		@ ch8
.Ltq_ret:
	pop	{r4, r5, r6, r7, r8, pc}

	.ltorg
