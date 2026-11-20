@ board_01.s - board support: GPIO helpers, GPIO/USART1/TIM7 setup, LCD bus helpers, text output, RCC clock enable helpers
@ Part of the FNIRSI LC1020E firmware rewrite: port of the stock bootloader (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080007a4 - read a GPIO input-data register under a mask.
@ r0 = GPIO port base address, r1 = bit mask.
@ Returns r0 = GPIOx_PID (offset 0x08 of the port) AND mask.
@ The two bytes after the return are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_080007a4,"ax",%progbits
	.p2align 2
	.global fn_080007a4
	.thumb_func
	.type fn_080007a4, %function
fn_080007a4:
	ldr	r0, [r0, #8]		@ GPIOx_PID of the port in r0
	ands	r0, r1			@ keep only the masked bits
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_080007ac - one-time setup of the pins the board uses on GPIOB (0x40010C00)
@ and GPIOC (0x40011000).
@ Steps, in order:
@   1. fn_0800080c(GPIOB, 0x10, 0): store 0x10 to GPIOB offset 0x14 (GPIOx_PBC).
@   2. fn_080007f4(GPIOB, 0x10, 0x10): configure pin mask 0x10 of GPIOB with mode byte 0x10.
@   3. fn_08000f38(0x00300200, 1): pin configuration through the AFIO helper with the
@      packed pin descriptor 0x00300200 and enable flag 1.
@   4. fn_080007f4(GPIOC, 0x40, 0x48) and fn_080007f4(GPIOC, 0x80, 0x48): configure
@      pin masks 0x40 and 0x80 of GPIOC with mode byte 0x48; the second call is a tail
@      call (the saved r4 and lr are restored first, the call is a plain branch).
@ r3 keeps the GPIOB base across the calls (callees do not change it).
@ ----------------------------------------------------------------------------
	.section .text.fn_080007ac,"ax",%progbits
	.p2align 2
	.global fn_080007ac
	.thumb_func
	.type fn_080007ac, %function
fn_080007ac:
	ldr	r3, .L080007e8		@ r3 = 0x40010C00 (GPIOB)
	push	{r4, lr}
	movs	r2, #0
	movs	r1, #0x10
	mov	r0, r3
	bl	fn_0800080c		@ GPIOB PBC (offset 0x14) = 0x10
	movs	r2, #0x10
	mov	r1, r2
	mov	r0, r3
	bl	fn_080007f4		@ GPIOB, mask 0x10, mode byte 0x10
	movs	r1, #1
	ldr	r0, .L080007ec		@ r0 = 0x00300200
	bl	fn_08000f38		@ pin descriptor 0x00300200, flag 1
	ldr	r4, .L080007f0		@ r4 = 0x40011000 (GPIOC)
	movs	r2, #0x48
	movs	r1, #0x40
	mov	r0, r4
	bl	fn_080007f4		@ GPIOC, mask 0x40, mode byte 0x48
	mov	r0, r4
	movs	r2, #0x48
	pop.w	{r4, lr}
	movs	r1, #0x80
	b.w	fn_080007f4		@ tail call: GPIOC, mask 0x80, mode byte 0x48
	.short	0x0000			@ padding
.L080007e8:
	.word	0x40010c00		@ GPIOB base
.L080007ec:
	.word	0x00300200		@ packed pin descriptor for fn_08000f38
.L080007f0:
	.word	0x40011000		@ GPIOC base

@ ----------------------------------------------------------------------------
@ fn_080007f4 - configure GPIO pins from a mask and a mode byte.
@ r0 = GPIO port base address, r1 = 16-bit pin mask, r2 = mode byte.
@ Builds an 8-byte-aligned record on the stack:
@   halfword at +0 = pin mask, byte at +2 = 3, byte at +3 = mode byte,
@ and calls fn_08001044(port, record), which writes the 4-bit pin configuration
@ fields and the set/clear registers of the port.
@ ----------------------------------------------------------------------------
	.section .text.fn_080007f4,"ax",%progbits
	.p2align 2
	.global fn_080007f4
	.thumb_func
	.type fn_080007f4, %function
fn_080007f4:
	push	{r3, lr}		@ r3 only keeps the stack 8-byte aligned
	strh.w	r1, [sp]		@ record +0: pin mask
	strb.w	r2, [sp, #3]		@ record +3: mode byte
	movs	r1, #3
	strb.w	r1, [sp, #2]		@ record +2: 3
	mov	r1, sp			@ r1 = address of the record
	bl	fn_08001044
	pop	{r3, pc}

@ ----------------------------------------------------------------------------
@ fn_0800080c - drive GPIO output bits.
@ r0 = GPIO port base address, r1 = bit mask, r2 = selector.
@ If r2 is zero, stores r1 to offset 0x14 of the port (GPIOx_PBC); otherwise
@ stores r1 to offset 0x10 (GPIOx_PBSC).
@ The two bytes after the second return are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800080c,"ax",%progbits
	.p2align 2
	.global fn_0800080c
	.thumb_func
	.type fn_0800080c, %function
fn_0800080c:
	cbz	r2, .L08000812
	str	r1, [r0, #0x10]		@ GPIOx_PBSC
	bx	lr
.L08000812:
	str	r1, [r0, #0x14]		@ GPIOx_PBC
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08000cfc - set up GPIOA (0x40010800) pin 9 area and USART1 (0x40013800).
@ Steps, in order:
@   1. Fills a 4-byte record on the stack (pin mask 0x200, 3, mode byte 0x18) and
@      calls fn_08001044(GPIOA, record).
@   2. Fills a 16-byte record on the stack: word 0 = 0x1C200 (115200), halfwords
@      at +4, +6, +8, +12 = 0, halfword at +10 = 8, and calls
@      fn_080028ac(USART1, record).
@   3. Calls fn_08002888(USART1, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_08000cfc,"ax",%progbits
	.p2align 2
	.global fn_08000cfc
	.thumb_func
	.type fn_08000cfc, %function
fn_08000cfc:
	push	{r4, lr}
	sub	sp, #0x18
	mov.w	r0, #0x200
	strh.w	r0, [sp, #0x10]		@ GPIO record: pin mask 0x200
	movs	r0, #3
	strb.w	r0, [sp, #0x12]		@ GPIO record: 3
	movs	r0, #0x18
	strb.w	r0, [sp, #0x13]		@ GPIO record: mode byte 0x18
	add	r1, sp, #0x10
	ldr	r0, .L08000d50		@ r0 = 0x40010800 (GPIOA)
	bl	fn_08001044
	mov.w	r0, #0x1c200
	str	r0, [sp]		@ USART record word 0 = 0x1C200
	movs	r0, #0
	strh.w	r0, [sp, #4]
	strh.w	r0, [sp, #6]
	strh.w	r0, [sp, #8]
	strh.w	r0, [sp, #0xc]
	movs	r0, #8
	ldr	r4, .L08000d54		@ r4 = 0x40013800 (USART1)
	strh.w	r0, [sp, #0xa]		@ USART record halfword +10 = 8
	mov	r1, sp
	mov	r0, r4
	bl	fn_080028ac
	movs	r1, #1
	mov	r0, r4
	bl	fn_08002888
	add	sp, #0x18
	pop	{r4, pc}
.L08000d50:
	.word	0x40010800		@ GPIOA base
.L08000d54:
	.word	0x40013800		@ USART1 base

@ ----------------------------------------------------------------------------
@ fn_08000d58 - set up and start the timer at 0x40001400 (TIM7).
@ The four argument registers are saved on the stack as a scratch record.
@ Steps, in order:
@   1. fn_0800262c(0x40001400).
@   2. Stack record: halfword +0 = 0x47, +2 = 0, +4 = 0xFFFF, +6 = 0.
@   3. fn_08002708(0x40001400, record).
@   4. fn_080026f4(0x40001400, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_08000d58,"ax",%progbits
	.p2align 2
	.global fn_08000d58
	.thumb_func
	.type fn_08000d58, %function
fn_08000d58:
	push	{r0, r1, r2, r3, r4, lr}
	ldr	r4, .L08000d8c		@ r4 = 0x40001400 (TIM7)
	mov	r0, r4
	bl	fn_0800262c
	movw	r0, #0xffff
	strh.w	r0, [sp, #4]		@ record +4 = 0xFFFF
	movs	r0, #0x47
	strh.w	r0, [sp]		@ record +0 = 0x47
	movs	r1, #0
	strh.w	r1, [sp, #6]		@ record +6 = 0
	strh.w	r1, [sp, #2]		@ record +2 = 0
	mov	r1, sp
	mov	r0, r4
	bl	fn_08002708
	movs	r1, #1
	mov	r0, r4
	bl	fn_080026f4
	pop	{r0, r1, r2, r3, r4, pc}
.L08000d8c:
	.word	0x40001400		@ TIM7 base

@ ----------------------------------------------------------------------------
@ fn_08000f38 - configure one pin through a packed descriptor and the AFIO block.
@ r0 = packed descriptor, r1 = enable flag (0 = clear, nonzero = set).
@ The code reads and writes four words of the block at 0x40010000: offsets
@ 0x04, 0x20, 0x24, 0x28. Descriptor bits 30, 29, 28 (tested with lsls #1, #2, #3)
@ choose offset 0x20, 0x24 or 0x28; if none is set offset 0x04 is used. The chosen
@ word is read first and written back at the end (label .L0800101e onward).
@ Other descriptor fields used:
@   bits 0..15  = bit pattern (r6); shifted left by 16 when bit 21 is set, giving r4
@   (descriptor AND 0x70300000) == 0x00300000: special case, clears bits 24..27 of the
@               chosen word and of offset 0x04, rewrites offset 0x04, then ORs r4 into
@               the chosen word when the flag is nonzero
@   bit 20 set: bits 16..19 give a shift count s; the mask 3 << s (shifted left a
@               further 16 when bit 21 is set) is cleared in the chosen word
@   bits 24, 26, 27, 29, 25 (tested with lsls #7, #5, #4 (via #0x1c), #0x1d, #6) select
@               the other paths: bit 24 set selects the path that updates bit 0 of
@               offset 0x04, bit 26 set (bit 24 clear) the path that updates bit 3;
@               those paths clear the pattern in the chosen word, then clear or set
@               the bit in offset 0x04 according to the flag and OR 0xF000000 into it.
@   when none of the above applies the pattern is cleared in the chosen word, and
@   0xF000000 is ORed into it if descriptor bits 28..30 are all clear.
@ Literal words: 0x40010000 (block base) and 0x70300000 (descriptor mask).
@ The two bytes before the literals are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000f38,"ax",%progbits
	.p2align 2
	.global fn_08000f38
	.thumb_func
	.type fn_08000f38, %function
fn_08000f38:
	push	{r4, r5, r6, r7, lr}
	ldr	r3, .L0800103c		@ r3 = 0x40010000
	lsls	r2, r0, #1
	bpl.n	.L08000f44
	ldr	r2, [r3, #0x20]
	b.n	.L08000f56
.L08000f44:
	lsls	r2, r0, #2
	bpl.n	.L08000f4c
	ldr	r2, [r3, #0x24]
	b.n	.L08000f56
.L08000f4c:
	lsls	r2, r0, #3
	bpl.n	.L08000f54
	ldr	r2, [r3, #0x28]
	b.n	.L08000f56
.L08000f54:
	ldr	r2, [r3, #4]
.L08000f56:
	ldr	r4, .L08001040		@ r4 = 0x70300000
	uxth	r6, r0
	and.w	r7, r0, r4
	ubfx	r4, r0, #0x15, #1
	lsls	r5, r4, #4
	uxth	r4, r0
	lsls	r4, r5			@ r4 = low 16 bits << (16 * bit 21)
	cmp.w	r7, #0x300000
	beq.n	.L08000f88
	lsls	r7, r0, #0xb
	bpl.n	.L08000f94
	lsls	r6, r0, #0xa
	mov.w	r5, #3
	ubfx	r7, r0, #0x10, #4
	lsl.w	r5, r5, r7		@ r5 = 3 << bits 16..19
	bpl.n	.L08000f84
	lsls	r5, r5, #0x10
.L08000f84:
	bics	r2, r5
	b.n	.L08001010
.L08000f88:
	ldr	r5, [r3, #4]
	bic	r2, r2, #0xf000000
	bic	r5, r5, #0xf000000
	b.n	.L08000ff4
.L08000f94:
	lsls	r7, r0, #7
	bpl.n	.L08000fc8
	lsls	r7, r0, #0x1d
	bpl.n	.L08000fbe
	lsls	r5, r0, #6
	bic.w	r2, r2, r4
	bpl.n	.L08000fb6
.L08000fa4:
	cmp	r1, #0
	ldr	r1, [r3, #4]
	beq.n	.L08000fb0
	orr	r1, r1, #1
	b.n	.L08000fe2
.L08000fb0:
	bic	r1, r1, #1
	b.n	.L08001006
.L08000fb6:
	ldr	r5, [r3, #4]
	bic	r5, r5, #1
	b.n	.L08000ff0
.L08000fbe:
	orr	r6, r6, #4
	lsls	r6, r5
	bics	r2, r6
	b.n	.L08000fa4
.L08000fc8:
	lsls	r7, r0, #5
	bpl.n	.L0800100e
	lsls	r7, r0, #0x1c
	bpl.n	.L08000ff8
	lsls	r5, r0, #6
	bic.w	r2, r2, r4
	bpl.n	.L08000fea
.L08000fd8:
	cmp	r1, #0
	ldr	r1, [r3, #4]
	beq.n	.L08001002
	orr	r1, r1, #8
.L08000fe2:
	orr	r1, r1, #0xf000000
	str	r1, [r3, #4]
	b.n	.L0800101c
.L08000fea:
	ldr	r5, [r3, #4]
	bic	r5, r5, #8
.L08000ff0:
	orr	r5, r5, #0xf000000
.L08000ff4:
	str	r5, [r3, #4]
	b.n	.L0800101a
.L08000ff8:
	orr	r6, r6, #8
	lsls	r6, r5
	bics	r2, r6
	b.n	.L08000fd8
.L08001002:
	bic	r1, r1, #8
.L08001006:
	orr	r1, r1, #0xf000000
	str	r1, [r3, #4]
	b.n	.L0800101e
.L0800100e:
	bics	r2, r4
.L08001010:
	tst.w	r0, #0x70000000
	bne.n	.L0800101a
	orr	r2, r2, #0xf000000
.L0800101a:
	cbz	r1, .L0800101e
.L0800101c:
	orrs	r2, r4
.L0800101e:
	lsls	r1, r0, #1
	bpl.n	.L08001026
	str	r2, [r3, #0x20]
	pop	{r4, r5, r6, r7, pc}
.L08001026:
	lsls	r1, r0, #2
	bpl.n	.L0800102e
	str	r2, [r3, #0x24]
	pop	{r4, r5, r6, r7, pc}
.L0800102e:
	lsls	r0, r0, #3
	bpl.n	.L08001036
	str	r2, [r3, #0x28]
	pop	{r4, r5, r6, r7, pc}
.L08001036:
	str	r2, [r3, #4]
	pop	{r4, r5, r6, r7, pc}
	.short	0x0000			@ padding
.L0800103c:
	.word	0x40010000		@ register block base
.L08001040:
	.word	0x70300000		@ descriptor mask

@ ----------------------------------------------------------------------------
@ fn_08001044 - write the pin configuration of a GPIO port from a 4-byte record.
@ r0 = GPIO port base, r1 = record: halfword +0 = pin mask, byte +2 = extra
@ configuration bits, byte +3 = mode byte.
@ Computes the 4-bit field value: (mode byte & 0xF), OR-ed with the byte at +2 when
@ bit 4 of the mode byte is set.
@ Low half: if the low mask byte is not zero, read GPIOx_PL_CFG (offset 0); for each of
@ pins 0..7 whose mask bit is set, replace its 4-bit field with the value; when the
@ mode byte is 0x28 store the pin bit to offset 0x14 (GPIOx_PBC), when it is 0x48 store
@ it to offset 0x10 (GPIOx_PBSC); write PL_CFG back.
@ High half: if the mask is above 0xFF, do the same for pins 8..15 with GPIOx_PH_CFG
@ (offset 4); the pin bit written to PBC / PBSC is the mask bit 8..15.
@ The two bytes after the return are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001044,"ax",%progbits
	.p2align 2
	.global fn_08001044
	.thumb_func
	.type fn_08001044, %function
fn_08001044:
	push	{r4, r5, r6, r7, lr}
	ldrb	r2, [r1, #3]		@ mode byte
	movs	r5, #0			@ pin counter
	and	r3, r2, #0xf		@ r3 = field value
	lsls	r2, r2, #0x1b
	bpl.n	.L08001056
	ldrb	r2, [r1, #2]
	orrs	r3, r2
.L08001056:
	ldrb	r2, [r1]		@ low mask byte
	mov.w	lr, #0xf		@ 4-bit field mask
	tst.w	r2, #0xff
	mov.w	r2, #1
	beq.n	.L080010a0
	ldr	r4, [r0]		@ GPIOx_PL_CFG
.L08001068:
	ldrh	r7, [r1]
	lsl.w	r6, r2, r5		@ r6 = 1 << pin
	ands	r7, r6
	cmp	r7, r6
	bne.n	.L08001098
	lsl.w	ip, r5, #2		@ ip = 4 * pin
	lsl.w	r7, lr, ip
	bic.w	r7, r4, r7		@ clear the pin's field
	lsl.w	r4, r3, ip
	orrs	r4, r7			@ insert the new field
	ldrb	r7, [r1, #3]
	cmp	r7, #0x28
	beq.n	.L08001092
	cmp	r7, #0x48
	beq.n	.L08001096
	b.n	.L08001098
.L08001092:
	str	r6, [r0, #0x14]		@ GPIOx_PBC
	b.n	.L08001098
.L08001096:
	str	r6, [r0, #0x10]		@ GPIOx_PBSC
.L08001098:
	.inst.n	0x1c6d			@ adds r5, r5, #1
	cmp	r5, #8
	bcc.n	.L08001068
	str	r4, [r0]		@ write GPIOx_PL_CFG
.L080010a0:
	ldrh	r4, [r1]
	cmp	r4, #0xff
	bls.n	.L080010e4
	ldr	r4, [r0, #4]		@ GPIOx_PH_CFG
	movs.w	r6, #0			@ pin counter (pins 8..15)
.L080010ac:
	add.w	r7, r6, #8
	lsl.w	r5, r2, r7		@ r5 = 1 << (pin + 8)
	ldrh	r7, [r1]
	ands	r7, r5
	cmp	r7, r5
	bne.n	.L080010dc
	lsl.w	ip, r6, #2
	lsl.w	r7, lr, ip
	bics	r4, r7
	lsl.w	r7, r3, ip
	orrs	r4, r7
	ldrb	r7, [r1, #3]
	cmp	r7, #0x28
	bne.n	.L080010d4
	str	r5, [r0, #0x14]		@ GPIOx_PBC
.L080010d4:
	ldrb	r7, [r1, #3]
	cmp	r7, #0x48
	bne.n	.L080010dc
	str	r5, [r0, #0x10]		@ GPIOx_PBSC
.L080010dc:
	.inst.n	0x1c76			@ adds r6, r6, #1
	cmp	r6, #8
	bcc.n	.L080010ac
	str	r4, [r0, #4]		@ write GPIOx_PH_CFG
.L080010e4:
	pop	{r4, r5, r6, r7, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_080011e8 - set a drawing window on the LCD and write one pixel value.
@ r0 = x, r1 = y, r2 = 16-bit colour.
@ Calls fn_080012a4(x, y, x + 1, y + 1) to select the window, then stores the colour
@ halfword to 0x60020000 (the LCD data port). The two bytes before the literal are
@ padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_080011e8,"ax",%progbits
	.p2align 2
	.global fn_080011e8
	.thumb_func
	.type fn_080011e8, %function
fn_080011e8:
	push	{r4, lr}
	mov	r4, r2			@ keep the colour
	adds	r3, r1, #1		@ y + 1
	adds	r2, r0, #1		@ x + 1
	bl	fn_080012a4
	ldr	r0, .L080011fc		@ r0 = 0x60020000
	strh	r4, [r0]
	pop	{r4, pc}
	.short	0x0000			@ padding
.L080011fc:
	.word	0x60020000		@ LCD data port address

@ ----------------------------------------------------------------------------
@ fn_08001200 - draw a zero-terminated string of 8-pixel-wide characters.
@ r0 = x, r1 = y, r2 = pointer to the string.
@ For every character until the NUL: calls fn_080012d4(x, y, character) and adds
@ 8 to x. Returns nothing (the loop test is at .L08001216, entered first).
@ ----------------------------------------------------------------------------
	.section .text.fn_08001200,"ax",%progbits
	.global fn_08001200
	.thumb_func
	.type fn_08001200, %function
fn_08001200:
	push	{r4, r5, r6, lr}
	mov	r4, r2			@ r4 = string pointer
	mov	r6, r1			@ r6 = y
	mov	r5, r0			@ r5 = x
	b.n	.L08001216
.L0800120a:
	mov	r1, r6
	mov	r0, r5
	bl	fn_080012d4		@ draw the character in r2
	.inst.n	0x1c64			@ adds r4, r4, #1
	adds	r5, #8			@ next character cell
.L08001216:
	ldrb	r2, [r4]
	cmp	r2, #0
	bne.n	.L0800120a
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_0800121e - set up the external memory controller and clock for the LCD bus.
@ Calls fn_08001aa8(0x100, 1) (set bit 8 of RCC_AHBPCLKEN, 0x40021014), then builds
@ a 0x58-byte configuration block on the stack and calls fn_08003110(block), then
@ fn_080030fc(0xA0000000, 1).
@ Stack block words (offset: value): 0x00: 0xA0000000, 0x04: 0, 0x08: 0,
@ 0x0C: 0x10, 0x10: 0, 0x14: 0, 0x18: 0, 0x1C: 0, 0x20: 0, 0x24: 0x1000, 0x28: 0,
@ 0x2C: 0x4000, 0x30: 0, 0x34: address of the word at 0x3C, 0x38: address of the
@ word at 0x3C, 0x3C: 0, 0x40: 0, 0x44: 2, 0x48: 0, 0x4C: 0x100000, 0x50: 0,
@ 0x54: 0.
@ The unit starts 2 bytes past a word boundary; the two bytes at its end are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800121e,"ax",%progbits
	.global fn_0800121e
	.thumb_func
	.type fn_0800121e, %function
fn_0800121e:
	push	{r4, lr}
	movs	r1, #1
	sub	sp, #0x58
	lsls	r0, r1, #8		@ r0 = 0x100
	bl	fn_08001aa8
	movs	r1, #0
	movs	r0, #2
	strd	r1, r0, [sp, #0x40]
	lsls	r0, r0, #0x13		@ r0 = 0x100000
	strd	r1, r0, [sp, #0x48]
	movs	r0, #0x10
	strd	r1, r0, [sp, #8]
	str	r1, [sp, #0x3c]
	str	r1, [sp, #0x50]
	mov.w	r4, #0xa0000000
	str	r1, [sp, #0x54]
	strd	r4, r1, [sp]
	str	r1, [sp, #0x10]
	lsls	r0, r0, #8		@ r0 = 0x1000
	strd	r1, r0, [sp, #0x20]
	str	r1, [sp, #0x18]
	str	r1, [sp, #0x14]
	lsls	r0, r0, #2		@ r0 = 0x4000
	strd	r1, r0, [sp, #0x28]
	add	r0, sp, #0x3c
	str	r1, [sp, #0x1c]
	strd	r1, r0, [sp, #0x30]
	str	r0, [sp, #0x38]
	mov	r0, sp
	bl	fn_08003110
	movs	r1, #1
	mov	r0, r4
	bl	fn_080030fc
	add	sp, #0x58
	pop	{r4, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0800127c - fill a rectangle of the LCD with one colour.
@ r0 = x0, r1 = y0, r2 = x1, r3 = y1, stack argument at [sp] = 16-bit colour.
@ Calls fn_080012a4(x0, y0, x1, y1) to select the window, then stores the colour
@ halfword (width * height) times to 0x60020002 (the LCD data port, written through
@ a pointer offset by 2), with width = x1 - x0 + 1 and height = y1 - y0 + 1.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800127c,"ax",%progbits
	.p2align 2
	.global fn_0800127c
	.thumb_func
	.type fn_0800127c, %function
fn_0800127c:
	push	{r4, r5, r6, lr}
	subs	r4, r2, r0		@ x1 - x0
	subs	r6, r3, r1		@ y1 - y0
	.inst.n	0x1c64			@ adds r4, r4, #1
	.inst.n	0x1c76			@ adds r6, r6, #1
	muls	r4, r6, r4		@ r4 = pixel count
	ldr	r5, [sp, #0x10]		@ r5 = colour (stack argument)
	bl	fn_080012a4
	movs	r0, #0
	ldr	r1, .L080012a0		@ r1 = 0x60020000
	b.n	.L0800129a
.L08001294:
	str.w	r5, [r1, #2]		@ store the colour at 0x60020002
	.inst.n	0x1c40			@ adds r0, r0, #1
.L0800129a:
	cmp	r0, r4
	blt.n	.L08001294
	pop	{r4, r5, r6, pc}
.L080012a0:
	.word	0x60020000		@ LCD data port base

@ ----------------------------------------------------------------------------
@ fn_080012a4 - select a drawing window on the LCD.
@ r0 = x0, r1 = y0, r2 = x1, r3 = y1.
@ Writes halfwords to the address pair 0x6001FFFE / 0x60020000 (the first is the
@ register-index port, the second the data port):
@   index 0x2A, then x0 high byte, x0, x1 high byte, x1;
@   index 0x2B, then y0 high byte, y0, y1 high byte, y1;
@   index 0x2C (start of pixel data).
@ ----------------------------------------------------------------------------
	.section .text.fn_080012a4,"ax",%progbits
	.p2align 2
	.global fn_080012a4
	.thumb_func
	.type fn_080012a4, %function
fn_080012a4:
	push	{r4, r5, r6, lr}
	ldr	r5, .L080012d0		@ r5 = 0x6001FFFE
	movs	r4, #0x2a
	strh	r4, [r5]		@ index 0x2A
	lsrs	r6, r0, #8
	adds	r4, r5, #2		@ r4 = 0x60020000
	strh	r6, [r4]
	strh	r0, [r4]
	lsrs	r0, r2, #8
	strh	r0, [r4]
	strh	r2, [r4]
	movs	r0, #0x2b
	strh	r0, [r5]		@ index 0x2B
	lsrs	r0, r1, #8
	strh	r0, [r4]
	strh	r1, [r4]
	lsrs	r0, r3, #8
	strh	r0, [r4]
	strh	r3, [r4]
	movs	r0, #0x2c
	strh	r0, [r5]		@ index 0x2C
	pop	{r4, r5, r6, pc}
.L080012d0:
	.word	0x6001fffe		@ index port address

@ ----------------------------------------------------------------------------
@ fn_080012d4 - draw one 8 x 16 character cell.
@ r0 = x, r1 = y, r2 = character code.
@ Glyph bytes come from the table at 0x08003F64 (d_08003f64): 16 bytes per character,
@ row index = 0..15, entry for the character = table + (code - 0x25) * 16. For each
@ of the 16 rows and each of the 8 columns (bit 7 first) calls
@ fn_080011e8(x + column, y + row, colour) with colour 0xFFFF when the glyph bit is
@ set and 0 when it is clear.
@ ----------------------------------------------------------------------------
	.section .text.fn_080012d4,"ax",%progbits
	.p2align 2
	.global fn_080012d4
	.thumb_func
	.type fn_080012d4, %function
fn_080012d4:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov	r7, r1			@ r7 = y (advances per row)
	subs	r2, #0x25
	mov	r6, r0			@ r6 = x (advances per column)
	mov	r10, r0			@ r10 = x at the start of each row
	ldr	r1, .L08001328		@ r1 = glyph table base
	uxtb	r0, r2
	movs	r5, #0			@ row counter
	add.w	r8, r1, r0, lsl #4	@ r8 = glyph bytes of this character
	mov.w	r9, #0x80		@ bit 7 mask
	movw	r11, #0xffff		@ set-pixel colour
.L080012f2:
	movs	r4, #0			@ column counter
.L080012f4:
	ldrb.w	r1, [r8, r5]		@ glyph row byte
	lsr.w	r0, r9, r4		@ mask of this column
	tst	r1, r0
	beq.n	.L08001304
	mov	r2, r11
	b.n	.L08001306
.L08001304:
	movs	r2, #0
.L08001306:
	mov	r1, r7
	mov	r0, r6
	bl	fn_080011e8
	.inst.n	0x1c64			@ adds r4, r4, #1
	uxtb	r4, r4
	.inst.n	0x1c76			@ adds r6, r6, #1
	cmp	r4, #8
	bcc.n	.L080012f4
	.inst.n	0x1c6d			@ adds r5, r5, #1
	uxtb	r5, r5
	.inst.n	0x1c7f			@ adds r7, r7, #1
	mov	r6, r10			@ back to the first column
	cmp	r5, #0x10
	bcc.n	.L080012f2
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08001328:
	.word	d_08003f64		@ glyph table

@ ----------------------------------------------------------------------------
@ fn_0800132c - fill the whole 320 x 240 screen with one colour.
@ r0 = 16-bit colour. Calls fn_0800127c(0, 0, 0x13F, 0xEF, colour); the colour is
@ passed on the stack.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800132c,"ax",%progbits
	.p2align 2
	.global fn_0800132c
	.thumb_func
	.type fn_0800132c, %function
fn_0800132c:
	push	{r3, lr}
	movs	r1, #0
	str	r0, [sp]		@ fifth argument: colour
	movs	r3, #0xef
	movw	r2, #0x13f
	mov	r0, r1
	bl	fn_0800127c
	pop	{r3, pc}

@ ----------------------------------------------------------------------------
@ fn_08001340 - initialise the LCD pins and send the panel start-up sequence.
@ Steps, in order:
@   1. fn_080007f4(port, mask, 0x18) for GPIOD (0x40011400) masks 0x10, 0x20, 0x80,
@      0x800, 0x4000, 0x8000, 1, 2, then GPIOE (0x40011800) masks 0x80, 0x100, 0x200,
@      0x400, 0x800, 0x1000, 0x2000, 0x4000, 0x8000, then GPIOD masks 0x100, 0x200,
@      0x400 (mode byte 0x18 each time; some masks are kept in registers or derived
@      address for reuse).
@   2. fn_0800121e() (bus and clock setup).
@   3. fn_080007f4(GPIOD, 0x40, 0x10); fn_0800080c(GPIOD, 0x40, 0) (clear);
@      fn_0800320e(1); fn_0800080c(GPIOD, 0x40, 1) (set); fn_0800320e(0x64).
@   4. Index-port (0x6001FFFE) and data-port (0x60020000) writes, halfwords:
@      index 0x11, wait fn_0800320e(0x78); index 0x36 data 0xA0; index 0x3A data 5;
@      index 0xB2 data 0xC 0xC 0 0x33 0x33; index 0xB7 data 0x35; index 0xBB data 0x28;
@      index 0xC0 data 0x2C; index 0xC2 data 1; index 0xC3 data 0xB; index 0xC4 data
@      0x20; index 0xC6 data 0xF; index 0xD0 data 0xA4 0xA1;
@      index 0xE0 data 0xD0 1 8 0xF 0x11 0x2A 0x36 0x55 0x44 0x3A 0xB 6 0x11 0x20;
@      index 0xE1 data 0xD0 2 7 0xA 0xB 0x18 0x34 0x43 0x4A 0x2B 0x1B 0x1C 0x22 0x1F;
@      index 0x29.
@   5. Tail call fn_0800132c(0): fill the screen with colour 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001340,"ax",%progbits
	.p2align 2
	.global fn_08001340
	.thumb_func
	.type fn_08001340, %function
fn_08001340:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	ldr	r4, .L08001550		@ r4 = 0x40011400 (GPIOD)
	movs	r2, #0x18
	movs	r1, #0x10
	mov	r0, r4
	bl	fn_080007f4
	movs	r2, #0x18
	movs	r1, #0x20
	mov	r0, r4
	bl	fn_080007f4
	movs	r2, #0x18
	movs	r1, #0x80
	mov	r0, r4
	bl	fn_080007f4
	asrs	r5, r4, #0x13		@ r5 = 0x800
	movs	r2, #0x18
	mov	r1, r5
	mov	r0, r4
	bl	fn_080007f4
	lsls	r6, r5, #3		@ r6 = 0x4000
	movs	r2, #0x18
	mov	r1, r6
	mov	r0, r4
	bl	fn_080007f4
	lsls	r7, r5, #4		@ r7 = 0x8000
	movs	r2, #0x18
	mov	r1, r7
	mov	r0, r4
	bl	fn_080007f4
	movs	r2, #0x18
	movs	r1, #1
	mov	r0, r4
	bl	fn_080007f4
	movs	r2, #0x18
	movs	r1, #2
	mov	r0, r4
	bl	fn_080007f4
	ldr.w	r8, .L08001554		@ r8 = 0x40011800 (GPIOE)
	movs	r2, #0x18
	movs	r1, #0x80
	mov	r0, r8
	bl	fn_080007f4
	mov.w	r9, #0x100
	movs	r2, #0x18
	mov	r1, r9
	mov	r0, r8
	bl	fn_080007f4
	mov.w	r10, #0x200
	movs	r2, #0x18
	mov	r1, r10
	mov	r0, r8
	bl	fn_080007f4
	mov.w	r11, #0x400
	movs	r2, #0x18
	mov	r1, r11
	mov	r0, r8
	bl	fn_080007f4
	movs	r2, #0x18
	mov	r1, r5
	mov	r0, r8
	bl	fn_080007f4
	movs	r2, #0x18
	asrs	r1, r4, #0x12		@ r1 = 0x1000
	mov	r0, r8
	bl	fn_080007f4
	movs	r2, #0x18
	asrs	r1, r4, #0x11		@ r1 = 0x2000
	mov	r0, r8
	bl	fn_080007f4
	movs	r2, #0x18
	mov	r1, r6
	mov	r0, r8
	bl	fn_080007f4
	movs	r2, #0x18
	mov	r1, r7
	mov	r0, r8
	bl	fn_080007f4
	movs	r2, #0x18
	mov	r1, r9
	mov	r0, r4
	bl	fn_080007f4
	movs	r2, #0x18
	mov	r1, r10
	mov	r0, r4
	bl	fn_080007f4
	movs	r2, #0x18
	mov	r1, r11
	mov	r0, r4
	bl	fn_080007f4
	bl	fn_0800121e
	movs	r2, #0x10
	movs	r1, #0x40
	mov	r0, r4
	bl	fn_080007f4
	movs	r2, #0
	movs	r1, #0x40
	mov	r0, r4
	bl	fn_0800080c
	movs	r0, #1
	bl	fn_0800320e
	movs	r2, #1
	movs	r1, #0x40
	mov	r0, r4
	bl	fn_0800080c
	movs	r0, #0x64
	bl	fn_0800320e
	ldr	r4, .L08001558		@ r4 = 0x6001FFFE (index port)
	movs	r0, #0x11
	strh	r0, [r4]
	movs	r0, #0x78
	bl	fn_0800320e
	movs	r0, #0x36
	strh	r0, [r4]
	movs	r1, #0xa0
	adds	r0, r4, #2		@ r0 = 0x60020000 (data port)
	strh	r1, [r0]
	movs	r1, #0x3a
	strh	r1, [r4]
	movs	r1, #5
	strh	r1, [r0]
	movs	r1, #0xb2
	strh	r1, [r4]
	movs	r1, #0xc
	strh	r1, [r0]
	strh	r1, [r0]
	movs	r1, #0
	strh	r1, [r0]
	movs	r1, #0x33
	strh	r1, [r0]
	strh	r1, [r0]
	movs	r1, #0xb7
	strh	r1, [r4]
	movs	r1, #0x35
	strh	r1, [r0]
	movs	r1, #0xbb
	strh	r1, [r4]
	movs	r1, #0x28
	strh	r1, [r0]
	movs	r1, #0xc0
	strh	r1, [r4]
	movs	r1, #0x2c
	strh	r1, [r0]
	movs	r1, #0xc2
	strh	r1, [r4]
	movs	r1, #1
	strh	r1, [r0]
	movs	r1, #0xc3
	strh	r1, [r4]
	movs	r1, #0xb
	strh	r1, [r0]
	movs	r1, #0xc4
	strh	r1, [r4]
	movs	r1, #0x20
	strh	r1, [r0]
	movs	r1, #0xc6
	strh	r1, [r4]
	movs	r1, #0xf
	strh	r1, [r0]
	movs	r1, #0xd0
	strh	r1, [r4]
	movs	r1, #0xa4
	strh	r1, [r0]
	movs	r1, #0xa1
	strh	r1, [r0]
	movs	r1, #0xe0
	strh	r1, [r4]
	movs	r1, #0xd0
	strh	r1, [r0]
	movs	r1, #1
	strh	r1, [r0]
	movs	r1, #8
	strh	r1, [r0]
	movs	r1, #0xf
	strh	r1, [r0]
	movs	r1, #0x11
	strh	r1, [r0]
	movs	r1, #0x2a
	strh	r1, [r0]
	movs	r1, #0x36
	strh	r1, [r0]
	movs	r1, #0x55
	strh	r1, [r0]
	movs	r1, #0x44
	strh	r1, [r0]
	movs	r1, #0x3a
	strh	r1, [r0]
	movs	r1, #0xb
	strh	r1, [r0]
	movs	r1, #6
	strh	r1, [r0]
	movs	r1, #0x11
	strh	r1, [r0]
	movs	r1, #0x20
	strh	r1, [r0]
	movs	r1, #0xe1
	strh	r1, [r4]
	movs	r1, #0xd0
	strh	r1, [r0]
	movs	r1, #2
	strh	r1, [r0]
	movs	r1, #7
	strh	r1, [r0]
	movs	r1, #0xa
	strh	r1, [r0]
	movs	r1, #0xb
	strh	r1, [r0]
	movs	r1, #0x18
	strh	r1, [r0]
	movs	r1, #0x34
	strh	r1, [r0]
	movs	r1, #0x43
	strh	r1, [r0]
	movs	r1, #0x4a
	strh	r1, [r0]
	movs	r1, #0x2b
	strh	r1, [r0]
	movs	r1, #0x1b
	strh	r1, [r0]
	movs	r1, #0x1c
	strh	r1, [r0]
	movs	r1, #0x22
	strh	r1, [r0]
	movs	r1, #0x1f
	strh	r1, [r0]
	movs	r0, #0x29
	strh	r0, [r4]		@ index 0x29
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	movs	r0, #0
	b.w	fn_0800132c		@ tail call: fill the screen with colour 0
	.short	0x0000			@ padding
.L08001550:
	.word	0x40011400		@ GPIOD base
.L08001554:
	.word	0x40011800		@ GPIOE base
.L08001558:
	.word	0x6001fffe		@ index port address

@ ----------------------------------------------------------------------------
@ fn_0800155c - formatted text output (printf style) to the LCD.
@ r0 = x, r1 = y, r2 = format string, r3 and the stack hold the variable arguments.
@ The four argument registers are pushed so the variable arguments are contiguous on
@ the stack; a 0x84-byte buffer is formatted by fn_080031cc(buffer, format,
@ pointer to the first variable argument), then fn_08001200(x, y, buffer) draws it.
@ The return pops the saved registers and discards the 4 pushed argument words with
@ a post-indexed load into pc.
@ The two bytes at the end are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800155c,"ax",%progbits
	.p2align 2
	.global fn_0800155c
	.thumb_func
	.type fn_0800155c, %function
fn_0800155c:
	push	{r0, r1, r2, r3}
	push	{r4, r5, lr}
	sub	sp, #0x84
	mov	r4, r1			@ y
	mov	r5, r0			@ x
	add	r2, sp, #0x9c		@ pointer to the variable arguments
	mov	r0, sp			@ output buffer
	ldr	r1, [sp, #0x98]		@ format string
	bl	fn_080031cc
	mov	r2, sp
	mov	r1, r4
	mov	r0, r5
	bl	fn_08001200
	add	sp, #0x84
	pop	{r4, r5}
	ldr.w	pc, [sp], #0x14		@ return and drop the pushed argument words
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08001a98 - write a value and its half to the bit-band region at 0x424200D8.
@ r0 = value. Stores r0 to 0x424200D8 and r0 >> 1 to 0x424200DC.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001a98,"ax",%progbits
	.p2align 2
	.global fn_08001a98
	.thumb_func
	.type fn_08001a98, %function
fn_08001a98:
	ldr	r1, .L08001aa4		@ r1 = 0x42420000
	str.w	r0, [r1, #0xd8]!	@ 0x424200D8 = value, r1 = 0x424200D8
	lsrs	r0, r0, #1
	str	r0, [r1, #4]		@ 0x424200DC = value >> 1
	bx	lr
.L08001aa4:
	.word	0x42420000

@ ----------------------------------------------------------------------------
@ fn_08001aa8 - set or clear bits of RCC_AHBPCLKEN (0x40021014).
@ r0 = bit mask, r1 = selector: zero clears the masked bits, nonzero sets them.
@ The two bytes before the literal are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001aa8,"ax",%progbits
	.p2align 2
	.global fn_08001aa8
	.thumb_func
	.type fn_08001aa8, %function
fn_08001aa8:
	ldr	r2, .L08001abc		@ r2 = 0x40021000 (RCC)
	cmp	r1, #0
	ldr	r1, [r2, #0x14]		@ RCC_AHBPCLKEN
	beq.n	.L08001ab4
	orrs	r1, r0			@ set the bits
	b.n	.L08001ab6
.L08001ab4:
	bics	r1, r0			@ clear the bits
.L08001ab6:
	str	r1, [r2, #0x14]
	bx	lr
	.short	0x0000			@ padding
.L08001abc:
	.word	0x40021000		@ RCC base

@ ----------------------------------------------------------------------------
@ fn_08001ac0 - set or clear bits of RCC_APB1PCLKEN (0x4002101C).
@ r0 = bit mask, r1 = selector: zero clears the masked bits, nonzero sets them.
@ The two bytes before the literal are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001ac0,"ax",%progbits
	.p2align 2
	.global fn_08001ac0
	.thumb_func
	.type fn_08001ac0, %function
fn_08001ac0:
	ldr	r2, .L08001ad4		@ r2 = 0x40021000 (RCC)
	cmp	r1, #0
	ldr	r1, [r2, #0x1c]		@ RCC_APB1PCLKEN
	beq.n	.L08001acc
	orrs	r1, r0			@ set the bits
	b.n	.L08001ace
.L08001acc:
	bics	r1, r0			@ clear the bits
.L08001ace:
	str	r1, [r2, #0x1c]
	bx	lr
	.short	0x0000			@ padding
.L08001ad4:
	.word	0x40021000		@ RCC base
