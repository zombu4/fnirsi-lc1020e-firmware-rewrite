@ board_02.s - board support: clock/peripheral-clock helpers, system clock setup, timer/USART helpers, delay
@ Part of the FNIRSI LC1020E firmware rewrite: port of the stock bootloader (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08001ad8 - set or clear bits in RCC_APB1PRST (0x40021010).
@ r0 = bit mask, r1 = flag. If r1 == 0 the bits of r0 are cleared in the
@ register, otherwise they are set. Read-modify-write, returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001ad8,"ax",%progbits
	.p2align 2
	.global fn_08001ad8
	.thumb_func
	.type fn_08001ad8, %function
fn_08001ad8:
	ldr	r2, .L08001aec		@ r2 = 0x40021000 (RCC base)
	cmp	r1, #0
	ldr	r1, [r2, #0x10]		@ RCC_APB1PRST
	beq.n	.L08001ae4
	orrs	r1, r0			@ flag set: set the bits
	b.n	.L08001ae6
.L08001ae4:
	bics	r1, r0			@ flag clear: clear the bits
.L08001ae6:
	str	r1, [r2, #0x10]
	bx	lr
	.short	0x0000			@ padding
.L08001aec:
	.word	0x40021000

@ ----------------------------------------------------------------------------
@ fn_08001af0 - set or clear bits in RCC_APB2PCLKEN (0x40021018).
@ r0 = bit mask, r1 = flag. If r1 == 0 the bits of r0 are cleared in the
@ register, otherwise they are set. Read-modify-write, returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001af0,"ax",%progbits
	.p2align 2
	.global fn_08001af0
	.thumb_func
	.type fn_08001af0, %function
fn_08001af0:
	ldr	r2, .L08001b04		@ r2 = 0x40021000 (RCC base)
	cmp	r1, #0
	ldr	r1, [r2, #0x18]		@ RCC_APB2PCLKEN
	beq.n	.L08001afc
	orrs	r1, r0			@ flag set: set the bits
	b.n	.L08001afe
.L08001afc:
	bics	r1, r0			@ flag clear: clear the bits
.L08001afe:
	str	r1, [r2, #0x18]
	bx	lr
	.short	0x0000			@ padding
.L08001b04:
	.word	0x40021000

@ ----------------------------------------------------------------------------
@ fn_08001b08 - set or clear bits in RCC_APB2PRST (0x4002100C).
@ r0 = bit mask, r1 = flag. If r1 == 0 the bits of r0 are cleared in the
@ register, otherwise they are set. Read-modify-write, returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001b08,"ax",%progbits
	.p2align 2
	.global fn_08001b08
	.thumb_func
	.type fn_08001b08, %function
fn_08001b08:
	ldr	r2, .L08001b1c		@ r2 = 0x40021000 (RCC base)
	cmp	r1, #0
	ldr	r1, [r2, #0xc]		@ RCC_APB2PRST
	beq.n	.L08001b14
	orrs	r1, r0			@ flag set: set the bits
	b.n	.L08001b16
.L08001b14:
	bics	r1, r0			@ flag clear: clear the bits
.L08001b16:
	str	r1, [r2, #0xc]
	bx	lr
	.short	0x0000			@ padding
.L08001b1c:
	.word	0x40021000

@ ----------------------------------------------------------------------------
@ fn_08001b20 - compute the clock frequencies from the RCC registers.
@ r0 = pointer to a result structure of six words:
@   [0] = system clock, [1] = AHB clock (system >> table[RCC_CFG bits 7:4]),
@   [2] = APB1 clock (AHB >> table[RCC_CFG bits 10:8]),
@   [3] = APB2 clock (AHB >> table[RCC_CFG bits 13:11]),
@   [4] = the computed PLL output divided by a halfword table entry indexed
@         by RCC_CFG2 (0x4002102C) bits 7:4,
@   [5] = AHB clock divided by a byte table entry indexed by RCC_CFG2 bits 3:0.
@ The PLL multiplier comes from RCC_CFG (0x40021004) masked with 0x083C0000
@ (shifted right by 18 and offset by 2, or by -0x1ef when the top masked bit
@ is set); the PLL input is 4000000 or 8000000 depending on RCC_CFG bits
@ 16 and 17. The switch status bits (RCC_CFG & 0xC): value 8 stores the PLL
@ result in [0], any other value stores 8000000. The shift tables are at
@ 0x08004498 (byte shifts; the table at +0x10 holds the divisors used for [5]
@ and the one at +0x20 is read as halfwords for [4]). Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001b20,"ax",%progbits
	.p2align 2
	.global fn_08001b20
	.thumb_func
	.type fn_08001b20, %function
fn_08001b20:
	push	{r4, r5, r6, lr}
	ldr	r1, .L08001bc8		@ r1 = 0x40021000 (RCC base)
	ldr	r2, [r1, #4]		@ RCC_CFG
	ldr	r3, .L08001bcc		@ mask 0x083C0000
	ands	r2, r3
	ldr	r3, [r1, #4]
	lsls	r4, r2, #4		@ sign bit = top masked bit
	and	r3, r3, #0x10000
	bmi.n	.L08001b38
	movs	r4, #2
	b.n	.L08001b3c
.L08001b38:
	mvn	r4, #0x1ee		@ r4 = -0x1ef
.L08001b3c:
	add.w	r2, r4, r2, lsr #18	@ PLL multiplier
	cbz	r3, .L08001b48
	ldr	r3, [r1, #4]
	lsls	r3, r3, #0xe		@ test RCC_CFG bit 17
	bpl.n	.L08001b4c
.L08001b48:
	ldr	r3, .L08001bd0		@ 4000000
	b.n	.L08001b4e
.L08001b4c:
	ldr	r3, .L08001bd4		@ 8000000
.L08001b4e:
	muls	r2, r3, r2		@ PLL output = input * multiplier
	ldr	r3, [r1, #4]
	ands	r4, r3, #0xc		@ clock switch status bits
	ldr	r3, .L08001bd4		@ 8000000
	beq.n	.L08001b62
	cmp	r4, #4
	beq.n	.L08001b62
	cmp	r4, #8
	beq.n	.L08001b66
.L08001b62:
	str	r3, [r0, #0]		@ system clock = 8000000
	b.n	.L08001b68
.L08001b66:
	str	r2, [r0, #0]		@ system clock = PLL output
.L08001b68:
	ldr	r3, [r1, #4]
	movs	r4, #0xf
	and.w	r3, r4, r3, lsr #4	@ RCC_CFG bits 7:4
	ldr	r4, .L08001bd8		@ r4 = 0x08004498 (shift table)
	ldrb	r5, [r4, r3]
	ldr	r3, [r0, #0]
	lsrs	r3, r5
	str	r3, [r0, #4]		@ AHB clock
	ldr	r5, [r1, #4]
	movs	r6, #7
	and.w	r5, r6, r5, lsr #8	@ RCC_CFG bits 10:8
	ldrb	r5, [r4, r5]
	lsr.w	r5, r3, r5
	str	r5, [r0, #8]		@ APB1 clock
	ldr	r5, [r1, #4]
	and.w	r5, r6, r5, lsr #0xb	@ RCC_CFG bits 13:11
	ldrb	r4, [r4, r5]
	lsr.w	r4, r3, r4
	str	r4, [r0, #0xc]		@ APB2 clock
	ldr	r4, [r1, #0x2c]		@ RCC_CFG2 (0x4002102C)
	ldr	r5, .L08001bd8
	and	r4, r4, #0xf
	adds	r5, #0x10		@ second table, 0x080044A8
	ldrb	r4, [r5, r4]
	udiv	r3, r3, r4
	str	r3, [r0, #0x14]
	ldr	r1, [r1, #0x2c]
	movs	r3, #0x1f
	and.w	r1, r3, r1, lsr #4
	and	r1, r1, #0xf		@ bits 7:4
	add.w	r3, r5, #0x10		@ third table, 0x080044B8 (halfwords)
	ldrh.w	r1, [r3, r1, lsl #1]
	udiv	r1, r2, r1
	str	r1, [r0, #0x10]
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L08001bc8:
	.word	0x40021000		@ RCC base
.L08001bcc:
	.word	0x083c0000		@ RCC_CFG mask
.L08001bd0:
	.word	0x003d0900		@ 4000000
.L08001bd4:
	.word	0x007a1200		@ 8000000
.L08001bd8:
	.word	d_08004498		@ shift/divisor tables in the read-only data

@ ----------------------------------------------------------------------------
@ fn_080020c4 - system clock setup.
@ Sets RCC_CTRL (0x40021000) bit 16 and polls bit 17 (up to 0x8000 reads).
@ If bit 17 never comes up, stores 8000000 to the RAM word at 0x20000060 and
@ returns. Otherwise: FLASH register at 0x40022000 has bits 2:0 cleared and
@ then bit 2 set; RCC_CFG (0x40021004) is rewritten with itself, bit 13 and
@ bits 10 and 8 set, bits 27 and 21:18 and 15:14 cleared (mask 0xF7C0FFFF) and
@ then bit 16 (PLLSRC: HSE) and the 0x08040000 pattern set (bits 27 and 18:
@ PLLMULFCT = 10001b, PLL input x 18; a register value, not an address);
@ RCC_CTRL bit 24 is set and
@ polled until bit 25 is set; RCC_CFG bits 1:0 are cleared and bit 1 set, and
@ the function waits until RCC_CFG bits 3:2 read 2. Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_080020c4,"ax",%progbits
	.p2align 2
	.global fn_080020c4
	.thumb_func
	.type fn_080020c4, %function
fn_080020c4:
	push	{r2, r3, lr}
	movs	r0, #0
	str	r0, [sp, #0]		@ local status byte = 0
	strb.w	r0, [sp, #0]
	str	r0, [sp, #4]		@ local timeout counter = 0
	ldr	r0, .L0800217c		@ r0 = 0x40021000 (RCC base)
	ldr	r1, [r0, #0]
	orr	r1, r1, #0x10000	@ RCC_CTRL bit 16
	str	r1, [r0, #0]
	mov.w	r2, #0x8000		@ timeout limit
.L080020de:
	ldr	r1, [r0, #0]
	ubfx	r1, r1, #0x11, #1	@ RCC_CTRL bit 17
	strb.w	r1, [sp, #0]
	ldr	r1, [sp, #4]
	.inst.n	0x1c49			@ adds r1, r1, #1
	str	r1, [sp, #4]
	ldrb.w	r1, [sp, #0]
	cbnz	r1, .L080020fa
	ldr	r1, [sp, #4]
	cmp	r1, r2
	bne.n	.L080020de
.L080020fa:
	ldr	r1, [r0, #0]
	ubfx	r1, r1, #0x11, #1
	strb.w	r1, [sp, #0]
	ldrb.w	r1, [sp, #0]
	cbz	r1, .L08002170		@ bit 17 never came up
	ldr	r1, .L08002180		@ r1 = 0x40022000
	ldr	r2, [r1, #0]
	bic	r2, r2, #7
	str	r2, [r1, #0]
	ldr	r2, [r1, #0]
	orr	r2, r2, #4
	str	r2, [r1, #0]
	ldr	r1, [r0, #4]		@ RCC_CFG, rewritten with itself
	str	r1, [r0, #4]
	ldr	r1, [r0, #4]
	orr	r1, r1, #0x2000
	str	r1, [r0, #4]
	ldr	r1, [r0, #4]
	orr	r1, r1, #0x500
	str	r1, [r0, #4]
	ldr	r1, [r0, #4]
	ldr	r2, .L08002184		@ mask 0xF7C0FFFF
	ands	r1, r2
	str	r1, [r0, #4]
	ldr	r1, [r0, #4]
	ldr	r2, .L08002188		@ 0x08040000: RCC_CFG PLLMULFCT bits 27 and 18 (x 18)
	orr	r1, r1, #0x10000
	orrs	r1, r2
	str	r1, [sp, #0]
	str	r1, [r0, #4]
	ldr	r1, [r0, #0]
	orr	r1, r1, #0x1000000	@ RCC_CTRL bit 24
	str	r1, [r0, #0]
.L0800214e:
	ldr	r1, [r0, #0]
	lsls	r1, r1, #6		@ RCC_CTRL bit 25 to the sign bit
	bpl.n	.L0800214e
	ldr	r1, [r0, #4]
	bic	r1, r1, #3
	str	r1, [r0, #4]
	ldr	r1, [r0, #4]
	orr	r1, r1, #2
	str	r1, [r0, #4]
.L08002164:
	ldr	r1, [r0, #4]
	ubfx	r1, r1, #2, #2		@ RCC_CFG bits 3:2
	cmp	r1, #2
	bne.n	.L08002164
.L0800216e:
	pop	{r2, r3, pc}
.L08002170:
	b.n	.L08002172
.L08002172:
	ldr	r1, .L08002190		@ r1 = 0x20000060 (RAM word)
	ldr	r0, .L0800218c		@ 8000000
	str	r0, [r1, #0]
	b.n	.L0800216e
	.short	0x0000			@ padding
.L0800217c:
	.word	0x40021000		@ RCC base
.L08002180:
	.word	0x40022000
.L08002184:
	.word	0xf7c0ffff
.L08002188:
	.word	0x08040000		@ RCC_CFG bits, not a flash address
.L0800218c:
	.word	0x007a1200		@ 8000000
.L08002190:
	.word	0x20000060

@ ----------------------------------------------------------------------------
@ fn_080021dc - calls fn_08001a98 with r0 = 3, then tail-calls fn_08001ac0
@ with r0 = 0x800000 (1 << 23). Returns whatever fn_08001ac0 returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_080021dc,"ax",%progbits
	.p2align 2
	.global fn_080021dc
	.thumb_func
	.type fn_080021dc, %function
fn_080021dc:
	push	{r4, lr}
	movs	r0, #3
	bl	fn_08001a98
	movs	r1, #1
	pop.w	{r4, lr}
	lsls	r0, r1, #0x17		@ r0 = 0x800000
	b.w	fn_08001ac0

@ ----------------------------------------------------------------------------
@ fn_08002598 - early system initialisation.
@ Sets 0xF00000 in the word at 0xE000ED88; sets RCC_CTRL (0x40021000) bit 0;
@ masks RCC_CFG (0x40021004) with 0xF8FFC000; masks RCC_CTRL with 0xFEF6FFFF
@ and clears its bit 18; masks RCC_CFG with 0xF700FFFF; clears the words at
@ 0x4002102C and 0x40021030; writes 0x9F0000 to 0x40021008 (RCC_CLKINT);
@ sets bit 28 of 0x4002101C (RCC_APB1PCLKEN); sets bit 0 of 0x4000700C;
@ clears bit 28 of 0x4002101C again; sets 0x90 in the word at 0x40022000;
@ calls fn_080020c4 (system clock setup); finally writes 0x08000000 to the
@ word at 0xE000ED08 (VTOR). Returns nothing.
@ Slot build: VTOR gets the address of this image's own vector table (slot +
@ 0x200), then interrupts are unmasked (cpsie i): the starter enters the slot
@ with PRIMASK set, and neither this code nor the application (no cps
@ instruction in V1.1) unmasks them otherwise.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002598,"ax",%progbits
	.p2align 2
	.global fn_08002598
	.thumb_func
	.type fn_08002598, %function
fn_08002598:
	ldr	r0, .L08002610		@ r0 = 0xE000ED88
	push	{r4, lr}
	ldr	r1, [r0, #0]
	orr	r1, r1, #0xf00000
	str	r1, [r0, #0]
	ldr	r0, .L08002614		@ r0 = 0x40021000 (RCC base)
	ldr	r1, [r0, #0]
	orr	r1, r1, #1
	str	r1, [r0, #0]
	ldr	r1, [r0, #4]
	ldr	r2, .L08002618		@ 0xF8FFC000
	ands	r1, r2
	str	r1, [r0, #4]
	ldr	r1, [r0, #0]
	ldr	r2, .L0800261c		@ 0xFEF6FFFF
	ands	r1, r2
	str	r1, [r0, #0]
	ldr	r1, [r0, #0]
	bic	r1, r1, #0x40000
	str	r1, [r0, #0]
	ldr	r1, [r0, #4]
	ldr	r2, .L08002620		@ 0xF700FFFF
	ands	r1, r2
	str	r1, [r0, #4]
	movs	r1, #0
	str	r1, [r0, #0x2c]
	str	r1, [r0, #0x30]
	mov.w	r1, #0x9f0000
	str	r1, [r0, #8]		@ RCC_CLKINT
	ldr	r1, [r0, #0x1c]		@ RCC_APB1PCLKEN
	orr	r1, r1, #0x10000000
	str	r1, [r0, #0x1c]
	ldr	r1, .L08002624		@ r1 = 0x40007000
	ldr	r2, [r1, #0xc]
	orr	r2, r2, #1
	str	r2, [r1, #0xc]
	ldr	r1, [r0, #0x1c]
	bic	r1, r1, #0x10000000
	str	r1, [r0, #0x1c]
	ldr	r0, .L08002628		@ r0 = 0x40022000
	ldr	r1, [r0, #0]
	orr	r1, r1, #0x90
	str	r1, [r0, #0]
	bl	fn_080020c4
	ldr	r1, .L08002610		@ r1 = 0xE000ED88
.ifdef SLOT
	ldr.n	r0, .Lslot_vectors	@ slot build: this image's own vector table
	subs	r1, #0x80		@ r1 = 0xE000ED08
	str	r0, [r1, #0]
	cpsie	i			@ the starter runs with interrupts masked; unmask them
.else
	mov.w	r0, #0x8000000
	subs	r1, #0x80		@ r1 = 0xE000ED08
	str	r0, [r1, #0]
.endif
	pop	{r4, pc}
	.short	0x0000			@ padding
.L08002610:
	.word	0xe000ed88
.L08002614:
	.word	0x40021000
.L08002618:
	.word	0xf8ffc000
.L0800261c:
	.word	0xfef6ffff
.L08002620:
	.word	0xf700ffff
.L08002624:
	.word	0x40007000
.L08002628:
	.word	0x40022000
.ifdef SLOT
.Lslot_vectors:
	.word	vectors			@ slot build: address of this image's vector table
.endif

@ ----------------------------------------------------------------------------
@ fn_0800262c - enable and then reset a peripheral by its base address.
@ r0 = peripheral base address. For each of the bases 0x40012C00 and
@ 0x40013400 the helper fn_08001b08 (RCC_APB2PRST) is called with the bit
@ mask 0x800 / 0x2000, first with flag 1 and then with flag 0 (a reset pulse).
@ For the bases 0x40000000, 0x40000400, 0x40000800, 0x40000C00, 0x40001000
@ and 0x40001400 the helper fn_08001ad8 (RCC_APB1PRST) is called with the
@ mask 1, 2, 4, 8, 0x10, 0x20 respectively, flag 1 and then flag 0. The mask
@ for the two APB2 cases is computed from the base address (asrs of r0 by
@ 19 and 17). Any other base address returns without doing anything.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800262c,"ax",%progbits
	.p2align 2
	.global fn_0800262c
	.thumb_func
	.type fn_0800262c, %function
fn_0800262c:
	ldr	r1, .L080026d8		@ 0x40012C00
	push	{r4, lr}
	cmp	r0, r1
	bne.n	.L0800263a
	movs	r1, #1
	asrs	r4, r0, #0x13		@ r4 = 0x40012C00 >> 19 = 0x800
	b.n	.L080026c2
.L0800263a:
	cmp.w	r0, #0x40000000
	beq.n	.L08002654
	ldr	r1, .L080026dc		@ 0x40000400
	cmp	r0, r1
	bne.n	.L08002662
	movs	r1, #1
	movs	r0, #2
	bl	fn_08001ad8
	movs	r1, #0
	movs	r0, #2
	b.n	.L080026b0
.L08002654:
	movs	r1, #1
	mov	r0, r1
	bl	fn_08001ad8
	movs	r1, #0
	movs	r0, #1
	b.n	.L080026b0
.L08002662:
	ldr	r1, .L080026e0		@ 0x40000800
	cmp	r0, r1
	bne.n	.L08002676
	movs	r1, #1
	movs	r0, #4
	bl	fn_08001ad8
	movs	r1, #0
	movs	r0, #4
	b.n	.L080026b0
.L08002676:
	ldr	r1, .L080026e4		@ 0x40000C00
	cmp	r0, r1
	bne.n	.L0800268a
	movs	r1, #1
	movs	r0, #8
	bl	fn_08001ad8
	movs	r1, #0
	movs	r0, #8
	b.n	.L080026b0
.L0800268a:
	ldr	r1, .L080026e8		@ 0x40001000
	cmp	r0, r1
	bne.n	.L0800269e
	movs	r1, #1
	movs	r0, #0x10
	bl	fn_08001ad8
	movs	r1, #0
	movs	r0, #0x10
	b.n	.L080026b0
.L0800269e:
	ldr	r1, .L080026ec		@ 0x40001400
	cmp	r0, r1
	bne.n	.L080026b8
	movs	r1, #1
	movs	r0, #0x20
	bl	fn_08001ad8
	movs	r1, #0
	movs	r0, #0x20
.L080026b0:
	pop.w	{r4, lr}
	b.w	fn_08001ad8
.L080026b8:
	ldr	r1, .L080026f0		@ 0x40013400
	cmp	r0, r1
	bne.n	.L080026d4
	movs	r1, #1
	asrs	r4, r0, #0x11		@ r4 = 0x40013400 >> 17 = 0x2000
.L080026c2:
	mov	r0, r4
	bl	fn_08001b08
	mov	r0, r4
	pop.w	{r4, lr}
	movs	r1, #0
	b.w	fn_08001b08
.L080026d4:
	pop	{r4, pc}
	.short	0x0000			@ padding
.L080026d8:
	.word	0x40012c00
.L080026dc:
	.word	0x40000400
.L080026e0:
	.word	0x40000800
.L080026e4:
	.word	0x40000c00
.L080026e8:
	.word	0x40001000
.L080026ec:
	.word	0x40001400
.L080026f0:
	.word	0x40013400

@ ----------------------------------------------------------------------------
@ fn_080026f4 - set or clear bit 0 of the word at r0.
@ r0 = pointer to the register, r1 = flag. If r1 == 0 bit 0 is cleared,
@ otherwise it is set. Read-modify-write, returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_080026f4,"ax",%progbits
	.p2align 2
	.global fn_080026f4
	.thumb_func
	.type fn_080026f4, %function
fn_080026f4:
	cmp	r1, #0
	ldr	r1, [r0, #0]
	beq.n	.L08002700
	orr	r1, r1, #1
	b.n	.L08002704
.L08002700:
	bic	r1, r1, #1
.L08002704:
	str	r1, [r0, #0]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08002708 - configure a timer-type peripheral from a settings block.
@ r0 = peripheral base address, r1 = pointer to a settings block:
@   +0x0 halfword -> base+0x28, +0x2 halfword -> bits 6:4 of base+0x00,
@   +0x4 halfword -> base+0x2C, +0x6 halfword -> bits 9:8 of base+0x00,
@   +0x8 byte -> base+0x30 (only bases 0x40012C00 and 0x40013400),
@   +0x9, +0xa, +0xb, +0xc, +0xd bytes -> flags (0 clears, non-zero sets)
@   for bits 11, 12, 13, 14, 15 of base+0x00, and +0xe byte -> flag for
@   bit 8 of base+0x04 (bases 0x40000000 and 0x40000800 only).
@ The base is compared with 0x40012C00, 0x40013400, 0x40000000, 0x40000400,
@ 0x40000800, 0x40000C00, 0x40001000 and 0x40001400; each field is applied
@ only for the bases the comparisons select. Writes 1 to base+0x14 between
@ the first and second write of base+0x00. Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002708,"ax",%progbits
	.p2align 2
	.global fn_08002708
	.thumb_func
	.type fn_08002708, %function
fn_08002708:
	push	{r4, r5, r6, r7, lr}
	ldr	r2, [r0, #0]
	ldr	r5, .L08002844		@ 0x40000400
	ldr	r4, .L08002838		@ 0x40012C00
	ldr	r6, .L0800283c		@ 0x40013400
	ldr.w	r12, .L08002840		@ 0x40000C00
	lsls	r7, r5, #0x14		@ r7 = 0x40000000
	ldr	r3, .L08002848		@ 0x40000800
	cmp	r0, r4
	beq.n	.L08002732
	cmp	r0, r6
	beq.n	.L08002732
	cmp	r0, r7
	beq.n	.L08002732
	cmp	r0, r5
	beq.n	.L08002732
	cmp	r0, r3
	beq.n	.L08002732
	cmp	r0, r12
	bne.n	.L0800273c
.L08002732:
	bic	lr, r2, #0x70
	ldrh	r2, [r1, #2]
	orr.w	r2, r2, lr
.L0800273c:
	ldr.w	lr, .L0800284c		@ 0x40001000
	cmp	r0, lr
	beq.n	.L08002756
	ldr.w	lr, .L08002850		@ 0x40001400
	cmp	r0, lr
	beq.n	.L08002756
	bic	lr, r2, #0x300
	ldrh	r2, [r1, #6]
	orr.w	r2, r2, lr
.L08002756:
	str	r2, [r0, #0]
	ldrh	r2, [r1, #4]
	strh	r2, [r0, #0x2c]
	ldrh	r2, [r1, #0]
	strh	r2, [r0, #0x28]
	cmp	r0, r4
	beq.n	.L08002768
	cmp	r0, r6
	bne.n	.L0800276c
.L08002768:
	ldrb	r2, [r1, #8]
	strh	r2, [r0, #0x30]
.L0800276c:
	movs	r2, #1
	strh	r2, [r0, #0x14]
	ldr	r2, [r0, #0]
	cmp	r0, r4
	beq.n	.L0800278a
	cmp	r0, r6
	beq.n	.L0800278a
	cmp	r0, r7
	beq.n	.L0800278a
	cmp	r0, r5
	beq.n	.L0800278a
	cmp	r0, r3
	beq.n	.L0800278a
	cmp	r0, r12
	bne.n	.L080027a2
.L0800278a:
	ldrb.w	lr, [r1, #9]
	cmp.w	lr, #0
	beq.n	.L0800279a
	orr	r2, r2, #0x800
	b.n	.L0800279e
.L0800279a:
	bic	r2, r2, #0x800
.L0800279e:
	cmp	r0, r7
	beq.n	.L080027ae
.L080027a2:
	cmp	r0, r5
	beq.n	.L080027ae
	cmp	r0, r3
	beq.n	.L080027ae
	cmp	r0, r12
	bne.n	.L080027da
.L080027ae:
	ldrb.w	r12, [r1, #0xa]
	cmp.w	r12, #0
	beq.n	.L080027be
	orr	r2, r2, #0x1000
	b.n	.L080027c2
.L080027be:
	bic	r2, r2, #0x1000
.L080027c2:
	ldrb.w	r12, [r1, #0xb]
	cmp.w	r12, #0
	beq.n	.L080027d2
	orr	r2, r2, #0x2000
	b.n	.L080027d6
.L080027d2:
	bic	r2, r2, #0x2000
.L080027d6:
	cmp	r0, r7
	beq.n	.L080027e2
.L080027da:
	cmp	r0, r5
	beq.n	.L080027e2
	cmp	r0, r3
	bne.n	.L080027f6
.L080027e2:
	ldrb.w	r12, [r1, #0xc]
	cmp.w	r12, #0
	beq.n	.L080027f2
	orr	r2, r2, #0x4000
	b.n	.L080027f6
.L080027f2:
	bic	r2, r2, #0x4000
.L080027f6:
	cmp	r0, r4
	beq.n	.L0800280a
	cmp	r0, r6
	beq.n	.L0800280a
	cmp	r0, r7
	beq.n	.L0800280a
	cmp	r0, r5
	beq.n	.L0800280a
	cmp	r0, r3
	bne.n	.L08002818
.L0800280a:
	ldrb	r4, [r1, #0xd]
	cbz	r4, .L08002814
	orr	r2, r2, #0x8000
	b.n	.L08002818
.L08002814:
	bic	r2, r2, #0x8000
.L08002818:
	str	r2, [r0, #0]
	ldr	r2, [r0, #4]
	cmp	r0, r7
	beq.n	.L08002824
	cmp	r0, r3
	bne.n	.L08002832
.L08002824:
	ldrb	r1, [r1, #0xe]
	cbz	r1, .L0800282e
	orr	r2, r2, #0x100
	b.n	.L08002832
.L0800282e:
	bic	r2, r2, #0x100
.L08002832:
	str	r2, [r0, #4]
	pop	{r4, r5, r6, r7, pc}
	.short	0x0000			@ padding
.L08002838:
	.word	0x40012c00
.L0800283c:
	.word	0x40013400
.L08002840:
	.word	0x40000c00
.L08002844:
	.word	0x40000400
.L08002848:
	.word	0x40000800
.L0800284c:
	.word	0x40001000
.L08002850:
	.word	0x40001400

@ ----------------------------------------------------------------------------
@ fn_08002888 - set or clear bit 13 of the halfword at r0+0xC.
@ r0 = peripheral base address, r1 = flag. If r1 == 0 bit 13 is cleared,
@ otherwise it is set. Read-modify-write, returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002888,"ax",%progbits
	.p2align 2
	.global fn_08002888
	.thumb_func
	.type fn_08002888, %function
fn_08002888:
	cmp	r1, #0
	ldrh	r1, [r0, #0xc]
	beq.n	.L08002894
	orr	r1, r1, #0x2000
	b.n	.L08002898
.L08002894:
	bic	r1, r1, #0x2000
.L08002898:
	strh	r1, [r0, #0xc]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0800289c - test flag bits in a halfword register.
@ r0 = pointer to the halfword, r1 = bit mask. Returns 1 in r0 if any bit of
@ the mask is set in the halfword, otherwise 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800289c,"ax",%progbits
	.p2align 2
	.global fn_0800289c
	.thumb_func
	.type fn_0800289c, %function
fn_0800289c:
	mov	r2, r0
	movs	r0, #0
	ldrh	r2, [r2, #0]
	tst	r2, r1
	beq.n	.L080028a8
	movs	r0, #1
.L080028a8:
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_080028ac - configure a serial peripheral (baud rate and control bits).
@ r0 = peripheral base address, r1 = pointer to a settings block:
@   +0x0 word = baud rate, +0x4 halfword, +0x6 halfword, +0x8 halfword,
@   +0xa halfword, +0xc halfword.
@ Writes the halfword at base+0x10 (bits 13:12 replaced by settings +0x6),
@ the halfword at base+0xC (bits masked with 0xE9F3, then OR of settings
@ +0x4, +0x8 and +0xa) and the halfword at base+0x14 (bits 9:8 replaced by
@ settings +0xC). It then calls fn_08001b20 with a 28-byte stack buffer to
@ obtain the clock frequencies and takes the word at buffer +0xC (for the
@ bases 0x40013800, 0x40015000 and 0x40015400) or +0x8 (all other bases).
@ With clock = that word, baud = settings +0x0: value = clock * 25 /
@ (baud * 4); the integer part is value / 100 and the fraction is
@ ((value % 100) * 16 + 50) / 100. If the fraction rounds up to 16 the
@ integer part is incremented. The halfword at base+0x8 receives
@ (integer << 4) | (fraction & 0xF). Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_080028ac,"ax",%progbits
	.p2align 2
	.global fn_080028ac
	.thumb_func
	.type fn_080028ac, %function
fn_080028ac:
	push	{r4, r5, lr}
	mov	r4, r0
	ldrh	r0, [r0, #0x10]
	sub	sp, #0x1c
	mov	r5, r1
	movw	r1, #0xcfff
	ands	r0, r1
	ldrh	r1, [r5, #6]
	orrs	r1, r0
	strh	r1, [r4, #0x10]
	ldrh	r1, [r4, #0xc]
	movw	r0, #0xe9f3
	ands	r1, r0
	ldrh	r0, [r5, #4]
	ldrh	r2, [r5, #8]
	orrs	r0, r2
	ldrh	r2, [r5, #0xa]
	orrs	r2, r1
	orrs	r0, r2
	strh	r0, [r4, #0xc]
	ldrh	r0, [r4, #0x14]
	movw	r1, #0xfcff
	ands	r0, r1
	ldrh	r1, [r5, #0xc]
	orrs	r1, r0
	strh	r1, [r4, #0x14]
	mov	r0, sp
	bl	fn_08001b20
	ldr	r0, .L08002950		@ 0x40013800
	cmp	r4, r0
	beq.n	.L080028fe
	ldr	r1, .L08002954		@ 0x40015000
	cmp	r4, r1
	beq.n	.L080028fe
	ldr	r1, .L08002958		@ 0x40015400
	cmp	r4, r1
	bne.n	.L08002902
.L080028fe:
	ldr	r0, [sp, #0xc]
	b.n	.L08002904
.L08002902:
	ldr	r0, [sp, #8]
.L08002904:
	movs	r2, #0x64
	add.w	r1, r0, r0, lsl #3	@ clock * 9
	add.w	r0, r1, r0, lsl #4	@ clock * 25
	ldr	r1, [r5, #0]
	mvn	r5, #0x18		@ r5 = -25
	lsls	r1, r1, #2
	udiv	r1, r0, r1		@ clock * 25 / (baud * 4)
	udiv	r0, r1, r2		@ / 100
	lsls	r0, r0, #4
	lsrs	r3, r0, #4
	muls	r3, r5, r3		@ integer * -25
	add.w	r3, r1, r3, lsl #2	@ value - integer * 100
	movs	r5, #0x32
	add.w	r3, r5, r3, lsl #4	@ remainder * 16 + 50
	udiv	r3, r3, r2
	movs	r5, #1
	cmp.w	r5, r3, lsr #4
	bne.n	.L08002942
	udiv	r0, r1, r2
	lsls	r0, r0, #4
	adds	r0, #0x10
.L08002942:
	and	r1, r3, #0xf
	orrs	r1, r0
	strh	r1, [r4, #8]
	add	sp, #0x1c
	pop	{r4, r5, pc}
	.short	0x0000			@ padding
.L08002950:
	.word	0x40013800
.L08002954:
	.word	0x40015000
.L08002958:
	.word	0x40015400

@ ----------------------------------------------------------------------------
@ fn_0800295c - write a 9-bit value to the halfword at r0+4.
@ r0 = peripheral base address, r1 = value; stores r1 & 0x1FF to base+4.
@ Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800295c,"ax",%progbits
	.p2align 2
	.global fn_0800295c
	.thumb_func
	.type fn_0800295c, %function
fn_0800295c:
	ubfx	r1, r1, #0, #9
	strh	r1, [r0, #4]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_080030fc - set or clear bit 0 of the word at r0.
@ r0 = pointer to the register, r1 = flag. If r1 == 0 bit 0 is cleared,
@ otherwise it is set. Read-modify-write, returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_080030fc,"ax",%progbits
	.p2align 2
	.global fn_080030fc
	.thumb_func
	.type fn_080030fc, %function
fn_080030fc:
	cmp	r1, #0
	ldr	r1, [r0, #0]
	beq.n	.L08003108
	orr	r1, r1, #1
	b.n	.L0800310c
.L08003108:
	bic	r1, r1, #1
.L0800310c:
	str	r1, [r0, #0]
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08003110 - configure a peripheral from a settings structure.
@ r0 = pointer to a structure: word 0 = peripheral base address, words 1..12
@ (offsets 0x4..0x30) are bit-field values, word 13 (+0x34) = pointer to a
@ second block of seven words, word 14 (+0x38) = pointer to a third block.
@ Writes the OR of words 1..12 to base+0x00; if word 2 (+0x8) equals 8, also
@ sets bit 6 of base+0x00. Writes the OR of the seven words of the second
@ block to base+0x04. If word 11 (+0x2C) equals 0x4000, writes to base+0x104
@ the OR of third-block words 0, 1, 4, 5, 6 and word 2 shifted left by 8;
@ otherwise writes 0x0FFFFFFF to base+0x104. Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003110,"ax",%progbits
	.p2align 2
	.global fn_08003110
	.thumb_func
	.type fn_08003110, %function
fn_08003110:
	push	{r4, lr}
	ldrd	r1, r2, [r0, #4]
	orrs	r1, r2
	ldrd	r2, r3, [r0, #0xc]
	orrs	r2, r3
	orrs	r1, r2
	ldr	r2, [r0, #0x14]
	orrs	r1, r2
	ldr	r2, [r0, #0x18]
	orrs	r1, r2
	ldr	r2, [r0, #0x1c]
	orrs	r1, r2
	ldr	r2, [r0, #0x20]
	orrs	r1, r2
	ldr	r2, [r0, #0x24]
	orrs	r1, r2
	ldr	r2, [r0, #0x28]
	orrs	r1, r2
	ldr	r2, [r0, #0x2c]
	orrs	r1, r2
	ldr	r2, [r0, #0x30]
	orrs	r1, r2
	ldr	r2, [r0, #0]
	str	r1, [r2, #0]
	ldr	r1, [r0, #8]
	cmp	r1, #8
	bne.n	.L08003154
	ldr	r1, [r0, #0]
	ldr	r2, [r1, #0]
	orr	r2, r2, #0x40
	str	r2, [r1, #0]
.L08003154:
	ldr	r1, [r0, #0x34]
	ldrd	r2, r3, [r1, #0]
	orrs	r2, r3
	ldrd	r3, r4, [r1, #8]
	orrs	r3, r4
	orrs	r2, r3
	ldr	r3, [r1, #0x10]
	orrs	r2, r3
	ldr	r3, [r1, #0x14]
	ldr	r1, [r1, #0x18]
	orrs	r2, r3
	orrs	r2, r1
	ldr	r1, [r0, #0]
	str	r2, [r1, #4]
	ldr	r1, [r0, #0x2c]
	cmp.w	r1, #0x4000
	beq.n	.L08003188
	ldr	r0, [r0, #0]
	mvn	r1, #0xf0000000		@ r1 = 0x0FFFFFFF
	str.w	r1, [r0, #0x104]
	pop	{r4, pc}
.L08003188:
	ldr	r1, [r0, #0x38]
	ldrd	r2, r3, [r1, #0]
	orrs	r2, r3
	ldr	r4, [r1, #8]
	ldr	r3, [r1, #0x10]
	ldr	r0, [r0, #0]
	orr.w	r3, r3, r4, lsl #8
	orrs	r2, r3
	ldr	r3, [r1, #0x14]
	ldr	r1, [r1, #0x18]
	orrs	r2, r3
	orrs	r2, r1
	str.w	r2, [r0, #0x104]
	pop	{r4, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0800320e - busy-wait delay.
@ r0 = count. Calls fn_08003224 with 1000 once for each of (count + 1)
@ iterations (the loop runs while the decremented counter does not borrow).
@ Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800320e,"ax",%progbits
	.global fn_0800320e
	.thumb_func
	.type fn_0800320e, %function
fn_0800320e:
	push	{r4, lr}
	mov	r3, r0
	mov.w	r4, #0x3e8
	b.n	.L0800321e
.L08003218:
	mov	r0, r4
	bl	fn_08003224
.L0800321e:
	.inst.n	0x1e5b			@ subs r3, r3, #1
	bcs.n	.L08003218
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08003224 - wait until a timer counter reaches a value.
@ r0 = limit. Writes 0 to the halfword at 0x40001424, then re-reads it until
@ its value (signed compare) is no longer below r0. Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003224,"ax",%progbits
	.p2align 2
	.global fn_08003224
	.thumb_func
	.type fn_08003224, %function
fn_08003224:
	ldr	r1, .L08003234		@ r1 = 0x40001424
	movs	r2, #0
	strh	r2, [r1, #0]
.L0800322a:
	ldrh	r2, [r1, #0]
	cmp	r2, r0
	blt.n	.L0800322a
	bx	lr
	.short	0x0000			@ padding
.L08003234:
	.word	0x40001424

@ ----------------------------------------------------------------------------
@ fn_08003e00 - send one byte on the serial port at 0x40013800 and wait.
@ r0 = byte (low 8 bits used). Calls fn_0800295c to store the byte to
@ base+4 of 0x40013800, then calls fn_0800289c with mask 0x80 on the
@ halfword at the base until it returns non-zero. Returns the original r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003e00,"ax",%progbits
	.p2align 2
	.global fn_08003e00
	.thumb_func
	.type fn_08003e00, %function
fn_08003e00:
	push	{r4, r5, r6, lr}
	ldr	r5, .L08003e20		@ r5 = 0x40013800
	mov	r4, r0
	uxtb	r1, r0
	mov	r0, r5
	bl	fn_0800295c
.L08003e0e:
	movs	r1, #0x80
	mov	r0, r5
	bl	fn_0800289c
	cmp	r0, #0
	beq.n	.L08003e0e
	mov	r0, r4
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L08003e20:
	.word	0x40013800
