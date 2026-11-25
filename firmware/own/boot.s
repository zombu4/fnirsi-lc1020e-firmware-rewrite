@ boot.s - the safe clock start-up and the start-up progress word of our build.
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ Two parts: the clock waits and the progress word (revision 17). Manual = N32G45x user manual V3.5.0 (docs/), datasheet = N32G455 datasheet (docs/).
@
@ Hooks (each a same-size change inside .ifdef OWN in the ported source):
@ - own_reset: the literal 0x0800628C of Reset_Handler (src/startup_39.s) names it instead of
@   fn_0800c274; Reset_Handler calls it with blx and jumps to fn_08006258 (the scatter-load) after
@   it returns.
@ - own_pll_wait: fn_0800ba4c 0x0800BAD6 (src/system_40.s), `bl own_pll_wait; beq.n .L0800baf8`
@   in place of the unbounded PLLRDF wait.
@ - own_sw_wait: fn_0800ba4c 0x0800BAEC, `bl own_sw_wait; beq.n .L0800baf8; nop.w` in place of
@   the unbounded wait for SCLKSTS = PLL.
@ - own_stg_*: the bl of the main function fn_08027ff4 (src/system_40.s) at 0x08028030 (own_load),
@   0x0802817C, 0x08028180, 0x0802818A, 0x0802818E, 0x08028192, 0x08028196: each stores its stage,
@   then tail-calls the original; own_stg_first replaces the load at 0x0802819A (stage 12 or 13).
@   Stages 3, 4 and 14 are stored by own_pa8_level, own_start and ctl_loop (own/ctl.s).
@
@ The clock. The slot bootloader starts the application with the PLL as the system clock
@ (bootloader/src/board_02.s fn_080020c4). fn_0800c274 writes SCLKSW = 00 together with the
@ prescalers and clears PLLEN / HSEEN two instructions later; manual 6.3.2: PLLEN "cannot be
@ cleared when PLL is used as the system clock", HSEEN likewise; 6.2.4: the PLL parameters cannot
@ be changed while it is enabled; 6.2.7: a switch occurs only when the target is ready. So
@ own_reset first switches to the HSI alone and waits until SCLKSTS (RCC_CFG bits 3:2) reads 00,
@ as the slot does for itself (board_02.s fn_08002598, .ifdef SLOT), then calls fn_0800c274.
@ Every wait is bounded by CLK_POLLS (0x8000, the bound of fn_0800ba4c's own HSE wait) polls of
@ at least 4 instructions: at least 0.91 ms at 144 MHz, at least 15 ms at 8.3 MHz, against
@ tSU(HSI) <= 5 us and tLOCK <= 150 us (datasheet tables 4-17, 4-20). When a bound runs out:
@ - HSI switch: the PLL still runs the core and nothing of the clock may be changed; fn_0800c274
@   is not called, only its other two stores are made (CPACR |= 0xF00000, VTOR = 0x08006000).
@   The core keeps the slot's set-up, which is fn_0800c274 / fn_0800ba4c instruction for
@   instruction (fn_08002598 / fn_080020c4): 144 MHz, LATENCY 4. Flag CLKF_HSI.
@ - PLL lock: PLLEN cleared (SCLKSW is still 00: the PLL is not the system clock), the APB
@   prescalers fn_0800ba4c set before the wait cleared again, r1 = 0, and fn_0800ba4c leaves by
@   its HSE-failure exit .L0800baf8 (clock word 8 MHz): the core stays on the HSI with the
@   prescalers of V1.1's crystal-fault start, own_pa8_level latches the power and own_start ends
@   in xtal_fault (the crystal did not start). Flag CLKF_PLL.
@ - Switch to the PLL: SCLKSW = 00 again, a bounded wait for SCLKSTS = 00, then the prescalers
@   as above, r1 = 0, the same exit and xtal_fault path. Flag CLKF_SW.
@   What still differs from V1.1's crystal-fault start on these two exits: FLASH_AC LATENCY 4
@   (stored before the PLL is enabled; more wait states than 8 MHz needs, manual 3.2.5.2.1, and
@   nothing here touches the flash controller), the PLL fields of RCC_CFG (bits 27, 21:16; no
@   clock uses them while the PLL is not the system clock), and on CLKF_SW the PLL left enabled.
@ The slot bootloader runs first on every start; its own clock waits (board_02.s fn_08002598
@ .Lslot_hsi, fn_080020c4 .Lslot_pll / .Lslot_sw) are bounded the same way from slot version 3;
@ in version 2 they have no bound.
@
@ The progress word: BOOT_PROG 0x2001FFEC = BOOT_TAG << 16 | clock flags << 8 | stage;
@ own_reset first copies the word the previous start left into BOOT_PREV 0x2001FFE8 (0 when its
@ tag is not BOOT_TAG), then writes tag, flags 0, stage 1; every later stage stores byte 0 only,
@ a clock flag ors into byte 1. Both words lie outside every area a start code writes (own.inc).
@ INFO answers both (cmd.s h_info, bytes 46..53).
@
@ RAM: BOOT_PREV and BOOT_PROG only (absolute, no section); stack only otherwise. Flash: nothing
@ here addresses the flash controller (FLASH_AC stays written by fn_0800c274 / fn_0800ba4c).

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

	.section .text.own.boot,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ own_reset - the reset handler's clock set-up (Reset_Handler blx, literal 0x0800628C). No
@   parameters, no result. BOOT_PREV = the previous progress word (0 without our tag),
@   BOOT_PROG = tag | stage 1; RCC_CTRL HSIEN set (fn_0800c274's first RCC store), RCC_CFG
@   SCLKSW = 00 alone; up to CLK_POLLS reads until SCLKSTS = 00, then fn_0800c274. On the
@   timeout: flag CLKF_HSI, CPACR |= 0xF00000, VTOR = vectors (file header). Last: stage 2.
@   Runs before the scatter-load: no RAM but the two no-init words and the stack. AAPCS.
@ ----------------------------------------------------------------------------
	.global	own_reset
	.thumb_func
	.type	own_reset, %function
own_reset:
	push	{r4, lr}
	ldr	r0, =BOOT_PROG
	ldr	r1, [r0]		@ the word the previous start left (or power-on contents)
	lsrs	r2, r1, #16
	movw	r3, #BOOT_TAG
	cmp	r2, r3
	it	ne
	movne	r1, #0			@ not ours: reported as 0
	ldr	r2, =BOOT_PREV
	str	r1, [r2]
	ldr	r1, =(BOOT_TAG << 16) | STG_RESET
	str	r1, [r0]		@ tag, no clock flag, stage 1
	ldr	r0, =RCC_CTRL
	ldr	r1, [r0]
	orr	r1, r1, #RCC_HSIEN
	str	r1, [r0]		@ HSI on (it is: it runs the core after a reset, or the slot
					@ never turned it off)
	ldr	r1, [r0, #4]
	bic	r1, r1, #RCC_SCLKSW
	str	r1, [r0, #4]		@ SCLKSW = 00 (HSI), nothing else of RCC_CFG changed
	mov	r2, #CLK_POLLS
.Lor_hsi:
	ldr	r1, [r0, #4]
	tst	r1, #RCC_SCLKSTS
	beq	.Lor_setup		@ SCLKSTS = 00: the HSI runs the core
	subs	r2, r2, #1
	bne	.Lor_hsi
	movs	r0, #CLKF_HSI		@ the switch did not happen: the PLL still runs the core
	bl	boot_clk_flag
	ldr	r0, =SCB_CPACR
	ldr	r1, [r0]
	orr	r1, r1, #CPACR_FPU
	str	r1, [r0]		@ fn_0800c274's first store: FPU access
	ldr	r0, =SCB_VTOR
	ldr	r1, =vectors
	str	r1, [r0]		@ and its last: this image's vector table
	b	.Lor_done
.Lor_setup:
	bl	fn_0800c274		@ the vendor's clock set-up, now from the HSI
.Lor_done:
	ldr	r0, =BOOT_PROG
	movs	r1, #STG_CLOCK
	strb	r1, [r0]
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ own_pll_wait - fn_0800ba4c 0x0800BAD6, after PLLEN was set. r0 = RCC_CTRL (kept). Up to
@   CLK_POLLS reads until PLLRDF (bit 25): returns r1 = RCC_CTRL as read (bit 25 set, not 0).
@   Timeout: PLLEN cleared (the PLL is not the system clock, SCLKSW is still 00), then the two
@   APB prescaler fields fn_0800ba4c set before the wait cleared again (RCC_APB2_DIV2,
@   RCC_APB1_DIV4: bits 13:8 back to 0, as fn_0800c274's mask left them and as V1.1's
@   HSE-failure exit 0x0800BA90 -> 0x0800BAF8 leaves them, which branches before the ors), flag
@   CLKF_PLL, r1 = 0. The core runs on the HSI here (own_reset saw SCLKSTS = 00 before
@   fn_0800c274), so PCLK1 / PCLK2 = HCLK = 8 MHz and the timers run at 8 MHz again (manual
@   line 5692: timer clock = PCLK when the APB prescaler is 1, else 2 x PCLK; with APB1 / 4
@   TIM7 of fn_08011c68 would run at 4 MHz). Returns the flags of cmp r1, #0: Z set only on the
@   timeout, so the caller's beq.n goes to the HSE-failure exit .L0800baf8 then. Uses r1, r2
@   (fn_0800ba4c holds nothing in r2 here; its pop restores r2 / r3), flags.
@ ----------------------------------------------------------------------------
	.global	own_pll_wait
	.thumb_func
	.type	own_pll_wait, %function
own_pll_wait:
	mov	r2, #CLK_POLLS
.Lpw_poll:
	ldr	r1, [r0]
	tst	r1, #RCC_PLLRDF
	bne	.Lpw_ret		@ locked: r1 not 0
	subs	r2, r2, #1
	bne	.Lpw_poll
	bic	r1, r1, #RCC_PLLEN
	str	r1, [r0]		@ PLL off again
	ldr	r1, [r0, #4]
	bic	r1, r1, #RCC_APB2_DIV2
	bic	r1, r1, #RCC_APB1_DIV4
	str	r1, [r0, #4]		@ APB2 / APB1 not divided again (HCLK = SYSCLK = HSI)
	push	{r0, lr}
	movs	r0, #CLKF_PLL
	bl	boot_clk_flag
	pop	{r0, lr}
	movs	r1, #0
.Lpw_ret:
	cmp	r1, #0			@ the caller's beq.n: Z set only on the timeout (r1 = 0)
	bx	lr

@ ----------------------------------------------------------------------------
@ own_sw_wait - fn_0800ba4c 0x0800BAEC, after SCLKSW = 10 (PLL). r0 = RCC_CTRL (kept). Up to
@   CLK_POLLS reads of RCC_CFG until SCLKSTS = 10: returns r1 = 8. Timeout: SCLKSW = 00 again
@   (the HSI is ready: own_reset saw it run the core), then up to CLK_POLLS reads until SCLKSTS
@   = 00; once it reads 00 the two APB prescaler fields of fn_0800ba4c are cleared again (as in
@   own_pll_wait: the state of V1.1's HSE-failure exit, timers at 8 MHz). Should SCLKSTS not
@   read 00 within the bound (a switch to the PLL that came after the last poll and is not yet
@   undone), the prescalers stay: they are the ones the PLL's 144 MHz needs (PCLK2 <= 72 MHz,
@   PCLK1 <= 36 MHz, manual lines 6294 / 6302). Flag CLKF_SW, r1 = 0. Returns the flags of
@   cmp r1, #0: Z set only on the timeout (the caller's beq.n then goes to .L0800baf8). Uses
@   r1, r2, flags.
@ ----------------------------------------------------------------------------
	.global	own_sw_wait
	.thumb_func
	.type	own_sw_wait, %function
own_sw_wait:
	mov	r2, #CLK_POLLS
.Lsw_poll:
	ldr	r1, [r0, #4]
	and	r1, r1, #RCC_SCLKSTS
	cmp	r1, #RCC_SCLK_PLL
	beq	.Lsw_ret		@ switched: r1 = 8
	subs	r2, r2, #1
	bne	.Lsw_poll
	ldr	r1, [r0, #4]
	bic	r1, r1, #RCC_SCLKSW
	str	r1, [r0, #4]		@ back to the HSI
	mov	r2, #CLK_POLLS
.Lsw_hsi:
	ldr	r1, [r0, #4]
	tst	r1, #RCC_SCLKSTS
	beq	.Lsw_pres		@ SCLKSTS = 00: the HSI runs the core
	subs	r2, r2, #1
	bne	.Lsw_hsi
	b	.Lsw_flag		@ not 00 within the bound: the prescalers stay
.Lsw_pres:
	bic	r1, r1, #RCC_APB2_DIV2
	bic	r1, r1, #RCC_APB1_DIV4
	str	r1, [r0, #4]		@ APB2 / APB1 not divided again (HCLK = SYSCLK = HSI)
.Lsw_flag:
	push	{r0, lr}
	movs	r0, #CLKF_SW
	bl	boot_clk_flag
	pop	{r0, lr}
	movs	r1, #0
.Lsw_ret:
	cmp	r1, #0			@ the caller's beq.n: Z set only on the timeout (r1 = 0)
	bx	lr

@ ----------------------------------------------------------------------------
@ boot_clk_flag - r0 = clock flag: ors it into byte 1 of BOOT_PROG. Uses r1, r2.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	boot_clk_flag, %function
boot_clk_flag:
	ldr	r1, =BOOT_PROG + 1
	ldrb	r2, [r1]
	orrs	r2, r2, r0
	strb	r2, [r1]
	bx	lr

@ ----------------------------------------------------------------------------
@ The stage wrappers of the main function fn_08027ff4. Each: byte 0 of BOOT_PROG = its stage,
@   then a tail call of the function the bl named in V1.1, with r0..r3 and LR as the caller left
@   them (r0, r1 saved around the store; flags changed, which no callee reads at its entry).
@ ----------------------------------------------------------------------------

@ own_stg_load - 0x08028030: stage 5, then own_load (own/save.s; the hook of V1.1's
@   copy_flash_block_to_ram).
	.global	own_stg_load
	.thumb_func
	.type	own_stg_load, %function
own_stg_load:
	push	{r0, r1}
	ldr	r0, =BOOT_PROG
	movs	r1, #STG_LOAD
	strb	r1, [r0]
	pop	{r0, r1}
	b.w	own_load

@ own_stg_814c - 0x0802817C: stage 6, then fn_0800814c (TIM2 and GPIOB set-up).
	.global	own_stg_814c
	.thumb_func
	.type	own_stg_814c, %function
own_stg_814c:
	push	{r0, r1}
	ldr	r0, =BOOT_PROG
	movs	r1, #STG_814C
	strb	r1, [r0]
	pop	{r0, r1}
	b.w	fn_0800814c

@ own_stg_lcd - 0x08028180: stage 7, then fn_08009c14 (LCD set-up).
	.global	own_stg_lcd
	.thumb_func
	.type	own_stg_lcd, %function
own_stg_lcd:
	push	{r0, r1}
	ldr	r0, =BOOT_PROG
	movs	r1, #STG_LCD
	strb	r1, [r0]
	pop	{r0, r1}
	b.w	fn_08009c14

@ own_stg_logo - 0x0802818A: stage 8, then fn_0800ce54 (the start-up animation; its first
@   instruction branches to own_logo, own/logo.s).
	.global	own_stg_logo
	.thumb_func
	.type	own_stg_logo, %function
own_stg_logo:
	push	{r0, r1}
	ldr	r0, =BOOT_PROG
	movs	r1, #STG_LOGO
	strb	r1, [r0]
	pop	{r0, r1}
	b.w	fn_0800ce54

@ own_stg_b0d8 - 0x0802818E: stage 9, then fn_0800b0d8 (two port groups and the selection
@   state).
	.global	own_stg_b0d8
	.thumb_func
	.type	own_stg_b0d8, %function
own_stg_b0d8:
	push	{r0, r1}
	ldr	r0, =BOOT_PROG
	movs	r1, #STG_B0D8
	strb	r1, [r0]
	pop	{r0, r1}
	b.w	fn_0800b0d8

@ own_stg_87d4 - 0x08028192: stage 10, then fn_080087d4 (the word 0x40007400, fn_08008814).
	.global	own_stg_87d4
	.thumb_func
	.type	own_stg_87d4, %function
own_stg_87d4:
	push	{r0, r1}
	ldr	r0, =BOOT_PROG
	movs	r1, #STG_87D4
	strb	r1, [r0]
	pop	{r0, r1}
	b.w	fn_080087d4

@ own_stg_8024 - 0x08028196: stage 11, then fn_08008024 (the channel block 0x40020494 and the
@   register block 0x40021C00 with its two waits, measure_32.s).
	.global	own_stg_8024
	.thumb_func
	.type	own_stg_8024, %function
own_stg_8024:
	push	{r0, r1}
	ldr	r0, =BOOT_PROG
	movs	r1, #STG_8024
	strb	r1, [r0]
	pop	{r0, r1}
	b.w	fn_08008024

@ own_stg_first - 0x0802819A, in place of `ldr.w r0, [r4, #0xbc4]` (r4 = 0x2000057C there):
@   returns r0 = the word 0x20001140 (the same load, by its address) and stores stage 12 when it
@   is not 0 (fn_0800ca2c follows) or 13 when it is 0 (the cbz to 0x080281F8, fn_0800c86c,
@   follows). The calls after both, fn_08008120(50), the IWDG start fn_08010178 and the print
@   "loop", get no stage of their own: they lie inside the span of that cbz, where the asm rule
@   (a cbz at most 31 lines from its target) admits no further hook line; stage 14 (ctl_loop)
@   follows them. Uses r0, r12, flags.
	.global	own_stg_first
	.thumb_func
	.type	own_stg_first, %function
own_stg_first:
	ldr	r12, =BOOT_PROG
	ldr	r0, =V_LANG_SET
	ldr	r0, [r0]
	cmp	r0, #0
	ite	ne
	movne	r0, #STG_CA2C
	moveq	r0, #STG_C86C
	strb	r0, [r12]
	ldr	r0, =V_LANG_SET
	ldr	r0, [r0]		@ r0 = the word again, for the caller's cbz
	bx	lr

	.ltorg
