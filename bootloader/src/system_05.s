@ system_05.s - startup entry, fault handlers, scatter loader, decompressor, EXTI and NVIC helpers, application start, main loop and tick handler
@ Part of the FNIRSI LC1020E firmware rewrite: port of the stock bootloader (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08000198 - startup stage after the reset handler's setup call.
@   Loads the main stack pointer with the word at .L080001ac (0x20002028) and
@   calls scatterload, which never returns. No parameters, no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000198,"ax",%progbits
	.p2align 2
	.global fn_08000198
	.thumb_func
	.type fn_08000198, %function
fn_08000198:
	ldr.w	sp, .L080001ac
	bl	scatterload

@ ----------------------------------------------------------------------------
@ fn_080001a0 - hand-over to main.
@   Loads the address of main from the literal at .L080001a4 and jumps to it
@   with bx. Never returns. Behind the code sit the literal for main, a four
@   byte data item (bytes af f3 00 80) and the initial stack pointer value
@   0x20002028 that fn_08000198 loads.
@ ----------------------------------------------------------------------------
	.global fn_080001a0
	.thumb_func
	.type fn_080001a0, %function
fn_080001a0:
	ldr	r0, .L080001a4
	bx	r0
.L080001a4:
	.word main
	.byte 0xaf, 0xf3, 0x00, 0x80	@ data item following the literal
.L080001ac:
	.word 0x20002028	@ initial main stack pointer

@ ----------------------------------------------------------------------------
@ set_msp - write the main stack pointer.
@   r0 = new MSP value. Executes msr msp, r0 and returns. Padding follows.
@ ----------------------------------------------------------------------------
	.section .text.set_msp,"ax",%progbits
	.p2align 2
	.global set_msp
	.thumb_func
	.type set_msp, %function
set_msp:
	msr	msp, r0
	bx	lr
	.short 0x0000	@ padding

@ ----------------------------------------------------------------------------
@ reset_handler - reset vector entry.
@   Calls the function at 0x08002598 (fn_08002598, address with thumb bit
@   0x08002599) and then jumps to fn_08000198 (0x08000199). Never returns.
@
@ The units after it in this section are the default exception handlers:
@   fn_080001c0, fn_080001c2, fn_080001c4, fn_080001c6, fn_080001c8,
@   fn_080001ca, fn_080001cc, pendsv_handler, fn_080001d0 and default_handler
@ each consist of a single branch to themselves (endless loop). The two
@ literals behind default_handler belong to reset_handler.
@ ----------------------------------------------------------------------------
	.section .text.reset_handler,"ax",%progbits
	.p2align 2
	.global reset_handler
	.thumb_func
	.type reset_handler, %function
reset_handler:
	ldr	r0, .L080001d4
	blx	r0
	ldr	r0, .L080001d8
	bx	r0

@ fn_080001c0 - endless loop (branch to itself).
	.global fn_080001c0
	.thumb_func
	.type fn_080001c0, %function
fn_080001c0:
	b.n	fn_080001c0

@ fn_080001c2 - endless loop (branch to itself).
	.global fn_080001c2
	.thumb_func
	.type fn_080001c2, %function
fn_080001c2:
	b.n	fn_080001c2

@ fn_080001c4 - endless loop (branch to itself).
	.global fn_080001c4
	.thumb_func
	.type fn_080001c4, %function
fn_080001c4:
	b.n	fn_080001c4

@ fn_080001c6 - endless loop (branch to itself).
	.global fn_080001c6
	.thumb_func
	.type fn_080001c6, %function
fn_080001c6:
	b.n	fn_080001c6

@ fn_080001c8 - endless loop (branch to itself).
	.global fn_080001c8
	.thumb_func
	.type fn_080001c8, %function
fn_080001c8:
	b.n	fn_080001c8

@ fn_080001ca - endless loop (branch to itself).
	.global fn_080001ca
	.thumb_func
	.type fn_080001ca, %function
fn_080001ca:
	b.n	fn_080001ca

@ fn_080001cc - endless loop (branch to itself).
	.global fn_080001cc
	.thumb_func
	.type fn_080001cc, %function
fn_080001cc:
	b.n	fn_080001cc

@ pendsv_handler - PendSV exception handler: endless loop (branch to itself).
	.global pendsv_handler
	.thumb_func
	.type pendsv_handler, %function
pendsv_handler:
	b.n	pendsv_handler

@ fn_080001d0 - endless loop (branch to itself).
	.global fn_080001d0
	.thumb_func
	.type fn_080001d0, %function
fn_080001d0:
	b.n	fn_080001d0

@ default_handler - default exception handler: endless loop (branch to itself).
@ The two words behind it are the literals of reset_handler.
	.global default_handler
	.thumb_func
	.type default_handler, %function
default_handler:
	b.n	default_handler
.L080001d4:
	.word fn_08002598	@ function pointer (thumb) called first by reset_handler
.L080001d8:
	.word fn_08000198	@ function pointer (thumb) jumped to by reset_handler

@ ----------------------------------------------------------------------------
@ scatterload - scatter-load loop.
@   Walks the region table from 0x08004574 up to (not including) 0x08004594 in
@   16-byte entries. For each entry it loads the handler address from offset
@   0xc, sets the thumb bit, loads the first three words of the entry into
@   r0, r1, r2 and calls the handler with them. When the table is finished it
@   branches to fn_080001a0 (hand-over to main). Never returns.
@ ----------------------------------------------------------------------------
	.section .text.scatterload,"ax",%progbits
	.p2align 2
	.global scatterload
	.thumb_func
	.type scatterload, %function
scatterload:
	ldr	r4, .L080005f8
	ldr	r5, .L080005fc
	b.n	.L080005f0
.L080005e2:
	ldr	r0, [r4, #0xc]
	orr.w	r3, r0, #1
	ldm.w	r4, {r0, r1, r2}
	blx	r3
	adds	r4, #0x10
.L080005f0:
	cmp	r4, r5
	bcc.n	.L080005e2
	bl	fn_080001a0
.L080005f8:
	.word d_08004574	@ start of the region table
.L080005fc:
	.word d_08004594	@ end of the region table

@ ----------------------------------------------------------------------------
@ decompress - byte-oriented run decompressor (region table handler).
@   r0 = source pointer, r1 = destination pointer, r2 = destination length.
@   Returns 0 in r0. Registers r4..r6 are saved.
@   The loop ends when the destination pointer reaches destination + length.
@   Each step reads a token byte r5 from the source:
@     r3 = r5 & 7 literal count; when 0 the next byte is the count.
@     r2 = r5 >> 4 (arithmetic) run length; when 0 the next byte is the length.
@     The literal part copies (r3 - 1) bytes from the source to the destination.
@     If bit 3 of the token is set, one more byte gives a back distance: the
@       destination minus that distance is the copy source, and r2 + 2 bytes are
@       copied from there to the destination (overlapping copy allowed).
@     Otherwise r2 + 1 zero bytes are stored to the destination.
@ decompress_addr is the plain label the region table holds as its even
@ handler address.
@ ----------------------------------------------------------------------------
	.section .text.decompress,"ax",%progbits
	.global decompress_addr
decompress_addr:				@ before .thumb_func: a plain (even) address
	.global decompress
	.thumb_func
	.type decompress, %function
decompress:
	push	{r4, r5, r6, lr}
	adds	r4, r1, r2		@ end of destination
.L08000720:
	ldrb.w	r5, [r0], #1		@ token byte
	ands	r3, r5, #7		@ literal count field
	bne.n	.L0800072e
	ldrb.w	r3, [r0], #1		@ count taken from the next byte
.L0800072e:
	asrs	r2, r5, #4		@ run length field
	bne.n	.L08000740
	ldrb.w	r2, [r0], #1		@ run length taken from the next byte
	b.n	.L08000740
.L08000738:
	ldrb.w	r6, [r0], #1		@ copy one literal byte
	strb.w	r6, [r1], #1
.L08000740:
	.inst.n 0x1e5b		@ subs r3, r3, #1
	bne.n	.L08000738
	lsls	r3, r5, #0x1c		@ bit 3 of the token to the sign flag
	bmi.n	.L08000754
	movs	r3, #0
.L0800074a:
	.inst.n 0x1e52		@ subs r2, r2, #1
	bmi.n	.L0800076a
	strb.w	r3, [r1], #1		@ store a zero byte
	b.n	.L0800074a
.L08000754:
	ldrb.w	r3, [r0], #1		@ back distance
	subs	r3, r1, r3		@ copy source = destination - distance
	.inst.n 0x1c92		@ adds r2, r2, #2
	b.n	.L08000766
.L0800075e:
	ldrb.w	r5, [r3], #1		@ copy one byte from the back reference
	strb.w	r5, [r1], #1
.L08000766:
	.inst.n 0x1e52		@ subs r2, r2, #1
	bpl.n	.L0800075e
.L0800076a:
	cmp	r1, r4
	bcc.n	.L08000720
	movs	r0, #0
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ busfault_handler - BusFault exception handler.
@   Passes the address of the text "BusFault_Handler\n" to fn_080031ac and then
@   loops forever. Never returns.
@ ----------------------------------------------------------------------------
	.section .text.busfault_handler,"ax",%progbits
	.p2align 2
	.global busfault_handler
	.thumb_func
	.type busfault_handler, %function
busfault_handler:
	adr	r0, .L08000820
	bl	fn_080031ac
.L0800081e:
	b.n	.L0800081e
.L08000820:
	.asciz "BusFault_Handler\n"
	.short 0x0000		@ padding

@ ----------------------------------------------------------------------------
@ fn_080009c0 - peripheral clock setup.
@   Calls fn_08001ac0(0x20, 1), then fn_08001af0(0x1c, 1), fn_08001af0(0x61, 1)
@   and fn_08001af0(0x6000, 1), and finishes by branching to fn_080007ac
@   (tail call). No parameters, no return value of its own.
@ ----------------------------------------------------------------------------
	.section .text.fn_080009c0,"ax",%progbits
	.p2align 2
	.global fn_080009c0
	.thumb_func
	.type fn_080009c0, %function
fn_080009c0:
	push	{r4, lr}
	movs	r1, #1
	movs	r0, #0x20
	bl	fn_08001ac0
	movs	r1, #1
	movs	r0, #0x1c
	bl	fn_08001af0
	movs	r1, #1
	movs	r0, #0x61
	bl	fn_08001af0
	movs	r1, #1
	mov.w	r0, #0x6000
	bl	fn_08001af0
	pop.w	{r4, lr}
	b.w	fn_080007ac

@ ----------------------------------------------------------------------------
@ debugmon_handler - DebugMonitor exception handler.
@   Passes the address of the text "DebugMon_Handler\n" to fn_080031ac by a
@   tail call (branch). Padding bytes surround the text.
@ ----------------------------------------------------------------------------
	.section .text.debugmon_handler,"ax",%progbits
	.p2align 2
	.global debugmon_handler
	.thumb_func
	.type debugmon_handler, %function
debugmon_handler:
	adr	r0, .L08000ce8
	b.w	fn_080031ac
	.short 0x0000		@ padding
.L08000ce8:
	.asciz "DebugMon_Handler\n"
	.short 0x0000		@ padding

@ ----------------------------------------------------------------------------
@ fn_08000d98 - write the EXTI pending register.
@   r0 = value stored to EXTI_PEND (0x40010414), whose address the code loads
@   from its literal. No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000d98,"ax",%progbits
	.p2align 2
	.global fn_08000d98
	.thumb_func
	.type fn_08000d98, %function
fn_08000d98:
	ldr	r1, .L08000da0
	str	r0, [r1, #0]
	bx	lr
	.short 0x0000		@ padding
.L08000da0:
	.word 0x40010414	@ EXTI_PEND

@ ----------------------------------------------------------------------------
@ fn_08000da4 - EXTI line configuration from a descriptor.
@   r0 = pointer to a descriptor: word 0 = line mask, byte 4 = register offset
@   (first one), byte 5 = register offset (second one, 0x10 means the special
@   case below), byte 6 = mode flag. Register block base 0x40010400 (EXTI:
@   EXTI_IMASK +0x00, EXTI_EMASK +0x04, EXTI_RT_CFG +0x08, EXTI_FT_CFG +0x0c).
@   Mode flag 0: clears the mask bits in the register at base + byte 4.
@   Mode flag nonzero: clears the mask bits in +0x00 and +0x04, sets them in
@   the register at base + byte 4, clears them in +0x08 and +0x0c, then, when
@   byte 5 is 0x10, sets them in both +0x08 and +0x0c, otherwise sets them in
@   the register at base + byte 5.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000da4,"ax",%progbits
	.p2align 2
	.global fn_08000da4
	.thumb_func
	.type fn_08000da4, %function
fn_08000da4:
	push	{r4, r5, lr}
	ldr	r1, .L08000e10
	ldrb	r3, [r0, #6]
	ldr	r2, [r0, #0]
	cbz	r3, .L08000e04
	ldr	r3, [r1, #0]
	bics	r3, r2
	str	r3, [r1, #0]
	adds	r2, r1, #4
	ldr	r3, [r2, #0]
	ldr	r4, [r0, #0]
	bics	r3, r4
	str	r3, [r2, #0]
	ldrb	r2, [r0, #4]
	add	r2, r1
	ldr	r3, [r2, #0]
	ldr	r4, [r0, #0]
	orrs	r3, r4
	str	r3, [r2, #0]
	ldr	r2, .L08000e10
	adds	r2, #8
	ldr	r3, [r2, #0]
	ldr	r4, [r0, #0]
	bics	r3, r4
	str	r3, [r2, #0]
	adds	r3, r2, #4
	ldr	r4, [r3, #0]
	ldr	r5, [r0, #0]
	bics	r4, r5
	str	r4, [r3, #0]
	ldrb	r4, [r0, #5]
	cmp	r4, #0x10
	beq.n	.L08000df2
	add	r1, r4
	ldr	r2, [r1, #0]
	ldr	r0, [r0, #0]
	orrs	r2, r0
	str	r2, [r1, #0]
	pop	{r4, r5, pc}
.L08000df2:
	ldr	r1, [r2, #0]
	ldr	r4, [r0, #0]
	orrs	r1, r4
	str	r1, [r2, #0]
	ldr	r1, [r3, #0]
	ldr	r0, [r0, #0]
	orrs	r1, r0
	str	r1, [r3, #0]
	pop	{r4, r5, pc}
.L08000e04:
	ldrb	r0, [r0, #4]
	add	r0, r1
	ldr	r1, [r0, #0]
	bics	r1, r2
	str	r1, [r0, #0]
	pop	{r4, r5, pc}
.L08000e10:
	.word 0x40010400	@ EXTI base (EXTI_IMASK)

@ ----------------------------------------------------------------------------
@ hardfault_handler - HardFault exception handler.
@   Passes the address of the text "HardFault_Handler\n" to fn_080031ac and
@   loops forever. Never returns.
@ ----------------------------------------------------------------------------
	.section .text.hardfault_handler,"ax",%progbits
	.p2align 2
	.global hardfault_handler
	.thumb_func
	.type hardfault_handler, %function
hardfault_handler:
	adr	r0, .L0800110c
	bl	fn_080031ac
.L0800110a:
	b.n	.L0800110a
.L0800110c:
	.asciz "HardFault_Handler\n"
	.byte 0x00		@ padding

@ ----------------------------------------------------------------------------
@ start_application - start an application image.
@   r0 = pointer to the image's vector table (word 0 = initial stack pointer,
@   word 1 = reset vector). When word 0 with its top four bits cleared is
@   below 0x80000, the function stores r0 to 0xE000ED08 (Cortex-M vector table
@   offset register), stores word 1 to the RAM word at 0x20000004, loads the
@   main stack pointer with word 0 through set_msp and jumps to the address
@   in the RAM word. Otherwise it returns without doing anything.
@ ----------------------------------------------------------------------------
	.section .text.start_application,"ax",%progbits
	.p2align 2
	.global start_application
	.thumb_func
	.type start_application, %function
start_application:
	push	{r4, lr}
	ldr	r1, [r0, #0]
	bic	r1, r1, #0xf0000000
	cmp.w	r1, #0x80000
	bcs.n	.L08001146
	ldr	r1, .L08001148
	str	r0, [r1, #0]
	ldr	r1, [r0, #4]
	ldr	r4, .L0800114c
	str	r1, [r4, #0]
	ldr	r0, [r0, #0]
	bl	set_msp
	ldr	r0, [r4, #0]
	pop.w	{r4, lr}
	bx	r0
.L08001146:
	pop	{r4, pc}
.L08001148:
	.word 0xe000ed08	@ vector table offset register
.L0800114c:
	.word 0x20000004	@ RAM word holding the application's reset vector

@ ----------------------------------------------------------------------------
@ fn_08001150 - button event dispatcher.
@   Reads the byte at 0x20000228 (base 0x20000220 + 8). When it is nonzero:
@   if it is 1 and the byte at 0x20000229 is also 1, calls fn_08001a74; then
@   clears the byte at 0x20000228. Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001150,"ax",%progbits
	.p2align 2
	.global fn_08001150
	.thumb_func
	.type fn_08001150, %function
fn_08001150:
	push	{r4, lr}
	ldr	r4, .L08001170
	ldrb	r0, [r4, #8]
	cmp	r0, #0
	beq.n	.L0800116c
	cmp	r0, #1
	bne.n	.L08001168
	ldrb	r0, [r4, #9]
	cmp	r0, #1
	bne.n	.L08001168
	bl	fn_08001a74
.L08001168:
	movs	r0, #0
	strb	r0, [r4, #8]
.L0800116c:
	pop	{r4, pc}
	.short 0x0000		@ padding
.L08001170:
	.word 0x20000220	@ RAM variable block

@ ----------------------------------------------------------------------------
@ fn_08001174 - key sampling and debounce, called every tick.
@   Calls fn_080007a4(0x40011000, 0x40) and fn_080007a4(0x40011000, 0x80)
@   (0x40011000 is the GPIOC base) and builds a state byte: bit 0 is set when
@   the first call returned 0, bit 3 when the second returned 0. The previous
@   state byte at 0x20000000 is replaced by the new one. From the old and new
@   states it derives the bits that changed to set (r1 = new & ~old) and to
@   cleared (r2 = new ^ r1 ^ old). Counter halfword at 0x2000022c
@   (0x20000220 + 0xc):
@     - bits newly set: counter = 0
@     - state nonzero: counter += 1; when the old counter was above 99 the
@       bytes at 0x20000228 / 0x20000229 receive 0xfe and the state
@     - bits cleared and counter above 2: byte 0x20000229 = cleared bits,
@       byte 0x20000228 = 1 when the counter is below 100, else 0xff.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001174,"ax",%progbits
	.p2align 2
	.global fn_08001174
	.thumb_func
	.type fn_08001174, %function
fn_08001174:
	push	{r4, r5, r6, lr}
	ldr	r5, .L080011dc
	movs	r4, #0
	movs	r1, #0x40
	mov	r0, r5
	bl	fn_080007a4
	cbnz	r0, .L08001186
	movs	r4, #1
.L08001186:
	movs	r1, #0x80
	mov	r0, r5
	bl	fn_080007a4
	cbnz	r0, .L08001194
	orr.w	r4, r4, #8
.L08001194:
	ldr	r3, .L080011e0
	ldrb	r2, [r3, #0]
	strb	r4, [r3, #0]
	bics.w	r1, r4, r2
	eor.w	r0, r4, r1
	eor.w	r2, r0, r2
	ldr	r0, .L080011e4
	beq.n	.L080011ae
	movs	r1, #0
	strh	r1, [r0, #0xc]
.L080011ae:
	cbz	r4, .L080011c0
	ldrh	r1, [r0, #0xc]
	adds	r3, r1, #1
	strh	r3, [r0, #0xc]
	cmp	r1, #0x63
	bls.n	.L080011c0
	movs	r1, #0xfe
	strb	r1, [r0, #8]
	strb	r4, [r0, #9]
.L080011c0:
	cmp	r2, #0
	beq.n	.L080011d8
	ldrh	r1, [r0, #0xc]
	cmp	r1, #2
	bls.n	.L080011d8
	strb	r2, [r0, #9]
	cmp	r1, #0x63
	bls.n	.L080011d4
	movs	r1, #0xff
	b.n	.L080011d6
.L080011d4:
	movs	r1, #1
.L080011d6:
	strb	r1, [r0, #8]
.L080011d8:
	pop	{r4, r5, r6, pc}
	.short 0x0000		@ padding
.L080011dc:
	.word 0x40011000	@ GPIOC base
.L080011e0:
	.word 0x20000000	@ previous key state byte
.L080011e4:
	.word 0x20000220	@ RAM variable block

@ ----------------------------------------------------------------------------
@ fn_08001584 - countdown step.
@   Loads the word at 0x20000224 (0x20000220 + 4). When it is nonzero it is
@   decremented and stored back; when the result is zero the function branches
@   to fn_08001a74 (tail call). Otherwise it returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001584,"ax",%progbits
	.p2align 2
	.global fn_08001584
	.thumb_func
	.type fn_08001584, %function
fn_08001584:
	ldr	r1, .L08001598
	ldr	r0, [r1, #4]
	cmp	r0, #0
	beq.n	.L08001596
	.inst.n 0x1e40		@ subs r0, r0, #1
	str	r0, [r1, #4]
	bne.n	.L08001596
	b.w	fn_08001a74
.L08001596:
	bx	lr
.L08001598:
	.word 0x20000220	@ RAM variable block

@ ----------------------------------------------------------------------------
@ memmanage_handler - MemManage exception handler.
@   Passes the address of the text "MemManage_Handler\n" to fn_080031ac and
@   loops forever. Never returns.
@ ----------------------------------------------------------------------------
	.section .text.memmanage_handler,"ax",%progbits
	.p2align 2
	.global memmanage_handler
	.thumb_func
	.type memmanage_handler, %function
memmanage_handler:
	adr	r0, .L080018d8
	bl	fn_080031ac
.L080018d6:
	b.n	.L080018d6
.L080018d8:
	.asciz "MemManage_Handler\n"
	.byte 0x00		@ padding

@ ----------------------------------------------------------------------------
@ nmi_handler - NMI exception handler.
@   Passes the address of the text "NMI_Handler\n" to fn_080031ac by a tail
@   call (branch).
@ ----------------------------------------------------------------------------
	.section .text.nmi_handler,"ax",%progbits
	.p2align 2
	.global nmi_handler
	.thumb_func
	.type nmi_handler, %function
nmi_handler:
	adr	r0, .L080018f4
	b.w	fn_080031ac
	.short 0x0000		@ padding
.L080018f4:
	.asciz "NMI_Handler\n"
	.byte 0x00, 0x00, 0x00	@ padding

@ ----------------------------------------------------------------------------
@ fn_08001904 - NVIC interrupt enable / disable.
@   r0 = pointer to a descriptor of four bytes: byte 0 = interrupt number,
@   byte 1 = preemption priority, byte 2 = sub priority, byte 3 = enable flag.
@   Byte 3 zero: writes 1 << (number & 0x1f) to NVIC_ICER (0xE000E180 +
@   (number >> 5) * 4), disabling the interrupt.
@   Byte 3 nonzero: reads the priority grouping field of 0xE000ED0C (SCB
@   AIRCR, mask 0x700), computes g = (0x700 - field) >> 8, builds
@   ((sub & (0xf >> g)) | (preemption << (4 - g))) << 4 and stores it to the
@   priority byte 0xE000E400 + number, then writes 1 << (number & 0x1f) to
@   NVIC_ISER (0xE000E100 + (number >> 5) * 4), enabling the interrupt.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001904,"ax",%progbits
	.p2align 2
	.global fn_08001904
	.thumb_func
	.type fn_08001904, %function
fn_08001904:
	push	{r4, r5, r6, lr}
	movs	r3, #0xf
	ldrb	r4, [r0, #3]
	ldrb	r1, [r0, #0]
	movs	r2, #1
	cbz	r4, .L0800194e
	ldr	r4, .L08001964
	ldr	r4, [r4, #0]
	ldrb	r5, [r0, #1]
	and	r4, r4, #0x700
	rsb.w	r4, r4, #0x700
	lsrs	r4, r4, #8
	rsb.w	r6, r4, #4
	lsrs	r3, r4
	ldrb	r4, [r0, #2]
	lsls	r5, r6
	ands	r4, r3
	orrs	r4, r5
	add.w	r1, r1, #0xe000e000
	lsls	r3, r4, #4
	strb.w	r3, [r1, #0x400]
	ldrb	r0, [r0, #0]
	and	r1, r0, #0x1f
	lsls	r2, r1
	lsrs	r0, r0, #5
	lsls	r0, r0, #2
	add.w	r0, r0, #0xe000e000
	str.w	r2, [r0, #0x100]
	pop	{r4, r5, r6, pc}
.L0800194e:
	and	r0, r1, #0x1f
	lsls	r2, r0
	lsrs	r0, r1, #5
	lsls	r0, r0, #2
	add.w	r0, r0, #0xe000e000
	str.w	r2, [r0, #0x180]
	pop	{r4, r5, r6, pc}
	.short 0x0000		@ padding
.L08001964:
	.word 0xe000ed0c	@ application interrupt and reset control register

@ ----------------------------------------------------------------------------
@ fn_08001968 - set the priority grouping.
@   r0 = grouping value. Stores (r0 | 0x05fa0000) to 0xE000ED0C (SCB AIRCR;
@   0x05fa is the register write key). No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001968,"ax",%progbits
	.p2align 2
	.global fn_08001968
	.thumb_func
	.type fn_08001968, %function
fn_08001968:
	ldr	r1, .L08001974
	orrs	r0, r1
	ldr	r1, .L08001978
	str	r0, [r1, #0]
	bx	lr
	.short 0x0000		@ padding
.L08001974:
	.word 0x05fa0000	@ register write key
.L08001978:
	.word 0xe000ed0c	@ application interrupt and reset control register

@ ----------------------------------------------------------------------------
@ fn_08001a74 - two calls to fn_0800080c with a zero third argument.
@   Calls fn_0800080c(0x40010800, 0x100, 0) (GPIOA base, mask 0x100) and then
@   by tail call fn_0800080c(0x40010c00, 0x10, 0) (GPIOB base, mask 0x10).
@ ----------------------------------------------------------------------------
	.section .text.fn_08001a74,"ax",%progbits
	.p2align 2
	.global fn_08001a74
	.thumb_func
	.type fn_08001a74, %function
fn_08001a74:
	push	{lr}
	movs	r2, #0
	mov.w	r1, #0x100
	ldr	r0, .L08001a90
	bl	fn_0800080c
	movs	r2, #0
	movs	r1, #0x10
	ldr	r0, .L08001a94
	pop.w	{lr}
	b.w	fn_0800080c
.L08001a90:
	.word 0x40010800	@ GPIOA base
.L08001a94:
	.word 0x40010c00	@ GPIOB base

@ ----------------------------------------------------------------------------
@ svc_handler - SVCall exception handler.
@   Passes the address of the text "SVC_Handler\n" to fn_080031ac by a tail
@   call (branch).
@ ----------------------------------------------------------------------------
	.section .text.svc_handler,"ax",%progbits
	.p2align 2
	.global svc_handler
	.thumb_func
	.type svc_handler, %function
svc_handler:
	adr	r0, .L0800202c
	b.w	fn_080031ac
	.short 0x0000		@ padding
.L0800202c:
	.asciz "SVC_Handler\n"
	.byte 0x00, 0x00, 0x00	@ padding

@ ----------------------------------------------------------------------------
@ system_reset - request a system reset.
@   Sets FAULTMASK (msr faultmask, 1), executes a data synchronisation
@   barrier, reads 0xE000ED0C (SCB AIRCR), keeps the priority grouping bits
@   (mask 0x700), ORs in 0x05fa0004 (write key and SYSRESETREQ bit) and
@   stores it back, executes another barrier and waits in an endless loop.
@   Never returns.
@ ----------------------------------------------------------------------------
	.section .text.system_reset,"ax",%progbits
	.p2align 2
	.global system_reset
	.thumb_func
	.type system_reset, %function
system_reset:
	movs	r0, #1
	msr	faultmask, r0
	dsb	sy
	ldr	r0, .L0800205c
	ldr	r1, [r0, #0]
	ldr	r2, .L08002060
	and	r1, r1, #0x700
	orrs	r1, r2
	str	r1, [r0, #0]
	dsb	sy
.L08002058:
	nop
	b.n	.L08002058
.L0800205c:
	.word 0xe000ed0c	@ application interrupt and reset control register
.L08002060:
	.word 0x05fa0004	@ write key and system reset request

@ ----------------------------------------------------------------------------
@ systick_handler - SysTick exception handler.
@   Branches to fn_08003f40 (tail call).
@ ----------------------------------------------------------------------------
	.section .text.systick_handler,"ax",%progbits
	.p2align 2
	.global systick_handler
	.thumb_func
	.type systick_handler, %function
systick_handler:
	b.w	fn_08003f40

@ ----------------------------------------------------------------------------
@ irq42_handler - handler of interrupt 42 (vector slot).
@   Calls fn_08000d98(0x40000) by a tail call (branch), which writes 0x40000
@   to the EXTI pending register at 0x40010414.
@ ----------------------------------------------------------------------------
	.section .text.irq42_handler,"ax",%progbits
	.p2align 2
	.global irq42_handler
	.thumb_func
	.type irq42_handler, %function
irq42_handler:
	mov.w	r0, #0x40000
	b.w	fn_08000d98

@ ----------------------------------------------------------------------------
@ fn_08002c48 - interrupt and EXTI initialisation.
@   Calls fn_08001968(0x500) (priority grouping), then through the NVIC
@   descriptor routine fn_08001904 enables interrupt 0x14 (preemption
@   priority 1, sub priority 0) and interrupt 0x2a (preemption priority 0,
@   sub priority 0, enable flag 1). Then calls fn_08000d98(0x40000) and
@   fn_08000da4 with a descriptor on the stack: line mask 0x40000, byte 4 = 0,
@   byte 5 = 8, byte 6 = 1. The incoming r1..r3 are pushed only to reserve the
@   descriptor space. No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002c48,"ax",%progbits
	.p2align 2
	.global fn_08002c48
	.thumb_func
	.type fn_08002c48, %function
fn_08002c48:
	push	{r1, r2, r3, r4, r5, r6, r7, lr}
	mov.w	r0, #0x500
	bl	fn_08001968
	movs	r0, #0x14
	strb.w	r0, [sp, #0]
	movs	r4, #1
	strb.w	r4, [sp, #1]
	movs	r5, #0
	strb.w	r5, [sp, #2]
	strb.w	r4, [sp, #3]
	mov	r0, sp
	bl	fn_08001904
	movs	r0, #0x2a
	strb.w	r0, [sp, #0]
	strb.w	r5, [sp, #1]
	strb.w	r4, [sp, #3]
	mov	r0, sp
	bl	fn_08001904
	lsls	r6, r4, #0x12
	mov	r0, r6
	bl	fn_08000d98
	strb.w	r5, [sp, #8]
	movs	r0, #8
	strb.w	r0, [sp, #9]
	str	r6, [sp, #4]
	strb.w	r4, [sp, #0xa]
	add	r0, sp, #4
	bl	fn_08000da4
	pop	{r1, r2, r3, r4, r5, r6, r7, pc}
	.short 0x0000		@ padding

@ ----------------------------------------------------------------------------
@ usagefault_handler - UsageFault exception handler.
@   Passes the address of the text "UsageFault_Handler\n" to fn_080031ac and
@   loops forever. Never returns.
@ ----------------------------------------------------------------------------
	.section .text.usagefault_handler,"ax",%progbits
	.p2align 2
	.global usagefault_handler
	.thumb_func
	.type usagefault_handler, %function
usagefault_handler:
	adr	r0, .L08003018
	bl	fn_080031ac
.L08003016:
	b.n	.L08003016
.L08003018:
	.asciz "UsageFault_Handler\n"

@ ----------------------------------------------------------------------------
@ zero_fill - zero-fill region handler (region table entry).
@   r1 = destination pointer, r2 = byte count (multiple of 4). Stores a zero
@   word to the destination and advances by 4 while the count is nonzero.
@   r0 is used as the zero value. No return value.
@ zero_fill_addr is the plain label the region table holds as its even
@ handler address.
@ ----------------------------------------------------------------------------
	.section .text.zero_fill,"ax",%progbits
	.global zero_fill_addr
zero_fill_addr:					@ before .thumb_func: a plain (even) address
	.global zero_fill
	.thumb_func
	.type zero_fill, %function
zero_fill:
	movs	r0, #0
	b.n	.L08003208
.L08003204:
	stmia	r1!, {r0}
	.inst.n 0x1f12		@ subs r2, r2, #4
.L08003208:
	cmp	r2, #0
	bne.n	.L08003204
	bx	lr

@ ----------------------------------------------------------------------------
@ main - bootloader main routine. Never returns.
@   1. Calls fn_080009c0, fn_08000d58 and fn_08000cfc (hardware setup).
@   2. Calls fn_080007a4(0x40011000, 0x80) (0x40011000 is the GPIOC base). If
@      it returns nonzero and the word at 0x08006000 masked with 0x2ffe0000
@      equals 0x20000000, calls start_application(0x08006000) and, should it
@      return, continues.
@   3. Calls fn_0800320e(100); fn_0800080c(0x40010800, 0x100, 1) and
@      fn_080007f4(0x40010800, 0x100, 0x10) (GPIOA base).
@   4. Clears the words at 0x20000220, 0x20000228 and 0x2000022c, stores 300
@      to the word at 0x20000224, calls fn_08001340, draws the text
@      "BootLoader" with fn_0800155c(0x78, 100, text) and the text "0%%" with
@      fn_0800155c(0x94, 0x78, text), calls fn_0800320e(100) and
@      fn_0800080c(0x40010c00, 0x10, 1) (GPIOB base).
@   5. Polls fn_080007a4(0x40011000, 0x40) until it returns nonzero, then
@      clears the halfword at 0x2000022c and the bytes at 0x20000228 / 9.
@   6. Reads the word at 0x20000060, divides it by 100 and subtracts 1. When
@      the result is below 0x1000000 it writes it to 0xE000E014 (SysTick
@      reload), 0xf0 to the byte at 0xE000ED23 (system handler priority of
@      SysTick), 0 to 0xE000E018 (SysTick current value) and 7 to 0xE000E010
@      (SysTick control).
@   7. Calls fn_08003ba8, fn_08002c48, fn_080021dc and fn_08002c10, then
@      loops calling fn_08001150 until the byte at 0x20000274 (0x20000250 +
@      0x24) equals 2, calls fn_0800320e(1000) and system_reset.
@ Slot build: step 2 calls slot_app_start instead of the SP test (its checks,
@ the OK record, flash lock, start_application); step 7 calls uf2_init in
@ place of fn_08003ba8 and slot_confirm after fn_08002c10 (OK record after the
@ USB start); the alignment nop before the loop and the two literals of the
@ SP test are left out.
@ ----------------------------------------------------------------------------
	.section .text.main,"ax",%progbits
	.p2align 2
	.global main
	.thumb_func
	.type main, %function
main:
	bl	fn_080009c0
	bl	fn_08000d58
	bl	fn_08000cfc
	ldr	r6, .L08003f0c
	movs	r1, #0x80
	mov	r0, r6
	bl	fn_080007a4
	cbz	r0, .L08003e4e
.ifdef SLOT
	bl	slot_app_start		@ slot build: checks, OK record, flash lock, start
.else
	ldr	r0, .L08003f10
	ldr	r1, [r0, #0]
	ldr	r2, .L08003f14
	ands	r1, r2
	cmp.w	r1, #0x20000000
	bne.n	.L08003e4e
	bl	start_application
.endif
.L08003e4e:
	movs	r0, #0x64
	bl	fn_0800320e
	movs	r2, #1
	ldr	r5, .L08003f18
	lsls	r4, r2, #8
	mov	r1, r4
	mov	r0, r5
	bl	fn_0800080c
	movs	r2, #0x10
	mov	r1, r4
	mov	r0, r5
	bl	fn_080007f4
	ldr	r4, .L08003f1c
	movs	r5, #0
	mov.w	r0, #0x12c
	str	r5, [r4, #0]
	str	r5, [r4, #8]
	str	r5, [r4, #0xc]
	str	r0, [r4, #4]
	bl	fn_08001340
	adr	r2, .L08003f20
	movs	r1, #0x64
	movs	r0, #0x78
	bl	fn_0800155c
	adr	r2, .L08003f2c
	movs	r1, #0x78
	movs	r0, #0x94
	bl	fn_0800155c
	movs	r0, #0x64
	bl	fn_0800320e
	movs	r2, #1
	movs	r1, #0x10
	ldr	r0, .L08003f30
	bl	fn_0800080c
.L08003ea4:
	movs	r1, #0x40
	mov	r0, r6
	bl	fn_080007a4
	cmp	r0, #0
	beq.n	.L08003ea4
	strh	r5, [r4, #0xc]
	ldr	r0, .L08003f34
	strb	r5, [r4, #8]
	strb	r5, [r4, #9]
	ldr	r0, [r0, #0]
	movs	r1, #0x64
	udiv	r0, r0, r1
	.inst.n 0x1e40		@ subs r0, r0, #1
	cmp.w	r0, #0x1000000
	bcs.n	.L08003edc
	mov.w	r1, #0xe000e000
	str	r0, [r1, #0x14]
	ldr	r2, .L08003f38
	movs	r0, #0xf0
	strb.w	r0, [r2, #0xd14]
	str	r5, [r1, #0x18]
	movs	r0, #7
	str	r0, [r1, #0x10]
.L08003edc:
.ifdef SLOT
	bl	uf2_init		@ slot build: clear the UF2 transfer state
	bl	fn_08002c48
	bl	fn_080021dc
	bl	fn_08002c10
	bl	slot_confirm		@ slot build: OK record after the USB start
	ldr	r4, .L08003f3c
	mov.w	r5, #0x3e8
.else
	bl	fn_08003ba8
	bl	fn_08002c48
	bl	fn_080021dc
	bl	fn_08002c10
	ldr	r4, .L08003f3c
	mov.w	r5, #0x3e8
	nop
.endif
.L08003ef4:
	bl	fn_08001150
	ldrb.w	r0, [r4, #0x24]
	cmp	r0, #2
	bne.n	.L08003ef4
	mov	r0, r5
	bl	fn_0800320e
	bl	system_reset
	b.n	.L08003ef4
.L08003f0c:
	.word 0x40011000	@ GPIOC base
.ifndef SLOT
.L08003f10:
	.word 0x08006000	@ word tested for an application stack pointer
.L08003f14:
	.word 0x2ffe0000	@ mask applied to that word
.endif
.L08003f18:
	.word 0x40010800	@ GPIOA base
.L08003f1c:
	.word 0x20000220	@ RAM variable block
.L08003f20:
	.asciz "BootLoader"
	.byte 0x00		@ padding
.L08003f2c:
	.asciz "0%%"
.L08003f30:
	.word 0x40010c00	@ GPIOB base
.L08003f34:
	.word 0x20000060	@ RAM word divided by 100 for the SysTick reload
.L08003f38:
	.word 0xe000e00f	@ base for the SysTick priority byte at 0xE000ED23
.L08003f3c:
	.word 0x20000250	@ RAM variable block

@ ----------------------------------------------------------------------------
@ fn_08003f40 - SysTick tick work (called by systick_handler).
@   Increments the word at 0x20000220. When it is above 99 the word is reset
@   to 0 and fn_08001584 is called. Then it branches to fn_08001174 (tail
@   call).
@ ----------------------------------------------------------------------------
	.section .text.fn_08003f40,"ax",%progbits
	.p2align 2
	.global fn_08003f40
	.thumb_func
	.type fn_08003f40, %function
fn_08003f40:
	ldr	r1, .L08003f60
	push	{r4, lr}
	ldr	r0, [r1, #0]
	.inst.n 0x1c40		@ adds r0, r0, #1
	str	r0, [r1, #0]
	cmp	r0, #0x63
	bls.n	.L08003f56
	movs	r0, #0
	str	r0, [r1, #0]
	bl	fn_08001584
.L08003f56:
	pop.w	{r4, lr}
	b.w	fn_08001174
	.short 0x0000		@ padding
.L08003f60:
	.word 0x20000220	@ RAM variable block
