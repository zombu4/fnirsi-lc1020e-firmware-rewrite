@ usb_09.s - USB device control-transfer helpers: endpoint status handlers, USB register save/restore, packet memory copy and the USB interrupt service routine
@ Part of the FNIRSI LC1020E firmware rewrite: port of the stock bootloader (Thumb-2 assembly).
@
@ Hardware used by this file: the USB device registers at 0x40005C00..0x40005C44
@ (USB_EP0..USB_EP7 at 0x40005C00 + 4*n, USB_CTRL at 0x40005C40, USB_STS at
@ 0x40005C44) and the USB packet memory at 0x40006000.. . In USB_EPn the bits
@ used here are: bit 15 CTRS_RX, bit 14 DATTOG_RX, bits 13:12 STS_RX, bit 11
@ SETUP, bit 7 CTRS_TX, bit 6 DATTOG_TX, bits 5:4 STS_TX, bits 3:0 EA.
@ The code reaches the registers as base 0x40005000 plus the offset 0xC00.
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080023ec - handler for a request that takes a length byte: checks it and
@ passes it on.
@   Let P = the pointer held at RAM word 0x2000006C (request block). Returns 2
@   (request refused) when P[3] is greater than the byte at 0x200000E1, or
@   P[2] is not zero, or the halfword at P+4 is not zero. Otherwise copies
@   P[3] to P[10] and calls the function whose address is stored at offset 4
@   of the table pointed to by the word at 0x20000074, then returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080023ec,"ax",%progbits
	.p2align 2
	.global fn_080023ec
	.thumb_func
	.type fn_080023ec, %function
fn_080023ec:
	ldr	r0, .L08002418		@ r0 = address of the pointer word 0x2000006C
	push	{r4, lr}
	ldr	r0, [r0]		@ r0 = P
	ldr	r2, .L0800241c		@ r2 = 0x200000E0
	ldrb	r1, [r0, #3]		@ r1 = P[3]
	ldrb	r2, [r2, #1]		@ r2 = byte at 0x200000E1
	cmp	r1, r2
	bhi.n	.L08002404		@ P[3] above the limit: refuse
	ldrb	r2, [r0, #2]
	cbnz	r2, .L08002404		@ P[2] not zero: refuse
	ldrh	r2, [r0, #4]
	cbz	r2, .L08002408		@ halfword at P+4 zero: accept
.L08002404:
	movs	r0, #2			@ return 2 (refused)
	pop	{r4, pc}
.L08002408:
	strb	r1, [r0, #0xa]		@ P[10] = P[3]
	ldr	r0, .L08002420		@ r0 = address of the table pointer word 0x20000074
	ldr	r0, [r0]
	ldr	r0, [r0, #4]		@ function at table offset 4
	blx	r0
	movs	r0, #0			@ return 0 (done)
	pop	{r4, pc}
	.short	0x0000			@ padding
.L08002418:
	.word	0x2000006c
.L0800241c:
	.word	0x200000e0
.L08002420:
	.word	0x20000074

@ ----------------------------------------------------------------------------
@ fn_08002424 - sets bit 5 (0x20) in byte 9 of the request block and calls a
@ table function.
@   Let P = the pointer held at RAM word 0x2000006C. Sets bit 0x20 in P[9],
@   then calls the function stored at offset 0x1C of the table pointed to by
@   the word at 0x20000074. Returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002424,"ax",%progbits
	.p2align 2
	.global fn_08002424
	.thumb_func
	.type fn_08002424, %function
fn_08002424:
	ldr	r0, .L08002440		@ r0 = address of the pointer word 0x2000006C
	push	{r4, lr}
	ldr	r0, [r0]		@ r0 = P
	ldrb	r1, [r0, #9]
	orr.w	r1, r1, #0x20		@ set bit 5 of P[9]
	strb	r1, [r0, #9]
	ldr	r0, .L08002444		@ r0 = address of the table pointer word 0x20000074
	ldr	r0, [r0]
	ldr	r0, [r0, #0x1c]		@ function at table offset 0x1C
	blx	r0
	movs	r0, #0			@ return 0
	pop	{r4, pc}
	.short	0x0000			@ padding
.L08002440:
	.word	0x2000006c
.L08002444:
	.word	0x20000074

@ ----------------------------------------------------------------------------
@ fn_08002448 - toggles an endpoint's stall state in its USB_EPn register.
@   Let P = the pointer held at RAM word 0x2000006C; P[5] is an endpoint
@   address (bit 7 = direction, bits 6:0 = endpoint number n). The register is
@   USB_EPn at 0x40005000 + 0xC00 + 4*n. With bit 7 set the TX status field
@   (bits 5:4) is read, otherwise the RX status field (bits 13:12); the field
@   is kept in its bit position. Returns 2 (refused) when n is not below the
@   byte at 0x200000E0, or the halfword at P+2 is not zero, or the status
@   field is zero, or P[10] is zero. Otherwise, with bit 7 set it writes
@   (EPn & 0x8FBF) ^ 0x10 | 0x8080, else (EPn & 0xBF8F) ^ 0x1000 | 0x8080
@   (the 0x8080 bits keep CTRS_RX and CTRS_TX unchanged when written, the
@   toggle bits are flipped by the xor), then calls the function at offset
@   0x18 of the table pointed to by the word at 0x20000074 and returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002448,"ax",%progbits
	.p2align 2
	.global fn_08002448
	.thumb_func
	.type fn_08002448, %function
fn_08002448:
	push	{r4, r5, r6, lr}
	ldr	r0, .L080024c0		@ r0 = address of the pointer word 0x2000006C
	ldr	r5, .L080024c4		@ r5 = 0x40005000
	ldr	r3, [r0]		@ r3 = P
	ldrb	r1, [r3, #5]		@ r1 = endpoint address
	bic.w	r0, r1, #0x80		@ r0 = endpoint number
	add.w	r0, r5, r0, lsl #2
	lsls	r4, r1, #0x18		@ sets N from direction bit 7
	ldr.w	r4, [r0, #0xc00]	@ r4 = USB_EPn
	bic.w	r2, r1, #0x80		@ r2 = endpoint number
	bpl.n	.L0800246e
	ubfx	r4, r4, #4, #2		@ TX: STS_TX field
	lsls	r4, r4, #4
	b.n	.L08002474
.L0800246e:
	ubfx	r4, r4, #0xc, #2	@ RX: STS_RX field
	lsls	r4, r4, #0xc
.L08002474:
	ldr	r5, .L080024c8		@ r5 = 0x200000E0
	ldrb	r5, [r5]
	cmp	r5, r2
	bls.n	.L0800249e		@ number not below the limit: refuse
	ldrh	r2, [r3, #2]
	cbnz	r2, .L0800249e
	cbz	r4, .L0800249e		@ status field zero: refuse
	ldrb	r2, [r3, #0xa]
	cbz	r2, .L0800249e		@ P[10] zero: refuse
	lsls	r1, r1, #0x18
	ldr.w	r1, [r0, #0xc00]	@ r1 = USB_EPn
	movw	r2, #0x8080
	bpl.n	.L080024a2
	movw	r3, #0x8fbf
	ands	r1, r3
	eor.w	r1, r1, #0x10		@ TX direction: flip bit 4 of STS_TX
	b.n	.L080024ac
.L0800249e:
	movs	r0, #2			@ return 2 (refused)
	pop	{r4, r5, r6, pc}
.L080024a2:
	movw	r3, #0xbf8f
	ands	r1, r3
	eor.w	r1, r1, #0x1000		@ RX direction: flip bit 12 of STS_RX
.L080024ac:
	orrs	r1, r2
	str.w	r1, [r0, #0xc00]	@ write back USB_EPn
	ldr	r0, .L080024cc		@ r0 = address of the table pointer word 0x20000074
	ldr	r0, [r0]
	ldr	r0, [r0, #0x18]		@ function at table offset 0x18
	blx	r0
	movs	r0, #0			@ return 0
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L080024c0:
	.word	0x2000006c
.L080024c4:
	.word	0x40005000
.L080024c8:
	.word	0x200000e0
.L080024cc:
	.word	0x20000074

@ ----------------------------------------------------------------------------
@ fn_080024d0 - checks a request through a callback and, if accepted, runs a
@ table function and records the request.
@   Let P = the pointer held at RAM word 0x2000006C. Calls the function at
@   offset 0x18 of the table pointed to by the word at 0x20000070 with
@   r0 = P[5] and r1 = P[3]. Returns 2 (refused) when P[10] is zero, or that
@   call returned non-zero, or P[4] is non-zero, or P[2] is non-zero.
@   Otherwise calls the function at offset 0xC of the table pointed to by the
@   word at 0x20000074, copies P[5] to P[11] and P[3] to P[12], and returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080024d0,"ax",%progbits
	.p2align 2
	.global fn_080024d0
	.thumb_func
	.type fn_080024d0, %function
fn_080024d0:
	push	{r4, lr}
	ldr	r4, .L0800250c		@ r4 = address of the pointer word 0x2000006C
	ldr	r2, .L08002510		@ r2 = address of the table pointer word 0x20000070
	ldr	r0, [r4]		@ r0 = P
	ldr	r2, [r2]
	ldrb	r1, [r0, #3]		@ second argument = P[3]
	ldr	r2, [r2, #0x18]		@ callback at table offset 0x18
	ldrb	r0, [r0, #5]		@ first argument = P[5]
	blx	r2
	ldr	r1, [r4]		@ r1 = P
	ldrb	r2, [r1, #0xa]
	cbz	r2, .L080024f2		@ P[10] zero: refuse
	cbnz	r0, .L080024f2		@ callback result non-zero: refuse
	ldrb	r0, [r1, #4]
	cbnz	r0, .L080024f2
	ldrb	r0, [r1, #2]
	cbz	r0, .L080024f6
.L080024f2:
	movs	r0, #2			@ return 2 (refused)
	pop	{r4, pc}
.L080024f6:
	ldr	r0, .L08002514		@ r0 = address of the table pointer word 0x20000074
	ldr	r0, [r0]
	ldr	r0, [r0, #0xc]		@ function at table offset 0xC
	blx	r0
	ldr	r0, [r4]		@ r0 = P
	ldrb	r1, [r0, #5]
	strb	r1, [r0, #0xb]		@ P[11] = P[5]
	ldrb	r1, [r0, #3]
	strb	r1, [r0, #0xc]		@ P[12] = P[3]
	movs	r0, #0			@ return 0
	pop	{r4, pc}
.L0800250c:
	.word	0x2000006c
.L08002510:
	.word	0x20000070
.L08002514:
	.word	0x20000074

@ ----------------------------------------------------------------------------
@ fn_08002518 - saves the eight USB_EPn registers, resets the USB block through
@ USB_CTRL and restores them.
@   1. Reads USB_CTRL (0x40005C40) and keeps its low 16 bits.
@   2. Copies the low 16 bits of USB_EP0..USB_EP7 (0x40005C00..) to the word
@      array at 0x20000294.
@   3. Writes USB_CTRL = saved | 0x400, then | 0x401, then clears bit 0 again.
@   4. Polls USB_STS (0x40005C44) until bit 10 (0x400) is set, then writes
@      0xFBFF to USB_STS (clears that flag).
@   5. Copies the eight saved values back to USB_EP0..USB_EP7.
@   6. Writes USB_CTRL = (value from step 3 without bit 0) | 8, then reads it
@      back and writes (low 16 bits) | 4.
@   No parameters, no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002518,"ax",%progbits
	.p2align 2
	.global fn_08002518
	.thumb_func
	.type fn_08002518, %function
fn_08002518:
	push	{r4, r5, r6, lr}
	ldr	r1, .L08002588		@ r1 = 0x40005C40 (USB_CTRL)
	movs	r0, #0
	ldr	r2, [r1]
	ldr	r3, .L0800258c		@ r3 = 0x40005000
	uxth	r4, r2			@ r4 = low 16 bits of USB_CTRL
	ldr	r2, .L08002590		@ r2 = 0x20000294 (save area)
	nop
.L08002528:
	add.w	r5, r3, r0, lsl #2
	ldr.w	r5, [r5, #0xc00]	@ r5 = USB_EPn
	uxth	r5, r5
	str.w	r5, [r2, r0, lsl #2]	@ save[n] = USB_EPn
	.inst.n 0x1c40			@ adds r0, r0, #1
	cmp	r0, #8
	bcc.n	.L08002528
	orr.w	r0, r4, #0x400
	str	r0, [r1]		@ USB_CTRL = saved | 0x400
	orr.w	r0, r0, #1
	str	r0, [r1]		@ USB_CTRL |= 1
	bic.w	r4, r0, #1
	str	r4, [r1]		@ USB_CTRL &= ~1
	ldr	r0, .L08002588		@ r0 = 0x40005C40
	.inst.n 0x1d00			@ adds r0, r0, #4 (r0 = 0x40005C44, USB_STS)
.L08002552:
	ldr	r5, [r0]
	lsls	r5, r5, #0x15
	bpl.n	.L08002552		@ wait for USB_STS bit 10
	movw	r5, #0xfbff
	str	r5, [r0]		@ USB_STS = 0xFBFF
	movs	r0, #0
.L08002560:
	ldr.w	r5, [r2, r0, lsl #2]	@ r5 = save[n]
	add.w	r6, r3, r0, lsl #2
	uxth	r5, r5
	str.w	r5, [r6, #0xc00]	@ USB_EPn = save[n]
	.inst.n 0x1c40			@ adds r0, r0, #1
	cmp	r0, #8
	bcc.n	.L08002560
	orr.w	r0, r4, #8
	str	r0, [r1]		@ USB_CTRL = value | 8
	ldr	r0, [r1]
	uxth	r0, r0
	orr.w	r0, r0, #4
	str	r0, [r1]		@ USB_CTRL = low 16 bits | 4
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L08002588:
	.word	0x40005c40
.L0800258c:
	.word	0x40005000
.L08002590:
	.word	0x20000294

@ ----------------------------------------------------------------------------
@ swap_bytes16 - swaps the two low bytes of a value.
@   r0 = input; returns (r0 >> 8) | ((r0 & 0xFF) << 8) in r0.
@ ----------------------------------------------------------------------------
	.section .text.swap_bytes16,"ax",%progbits
	.p2align 2
	.global swap_bytes16
	.thumb_func
	.type swap_bytes16, %function
swap_bytes16:
	uxtb	r1, r0
	lsrs	r0, r0, #8
	orr.w	r0, r0, r1, lsl #8
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08002978 - re-arms the receive side of an endpoint after a SETUP-type
@ event.
@   r0 = endpoint number n. Reads USB_EPn (0x40005C00 + 4*n). If bit 14
@   (DATTOG_RX) is set, writes (USB_EPn & 0x8F8F) | 0xC080 back; otherwise
@   does nothing. No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002978,"ax",%progbits
	.p2align 2
	.global fn_08002978
	.thumb_func
	.type fn_08002978, %function
fn_08002978:
	lsls	r1, r0, #2		@ r1 = 4*n
	ldr	r0, .L0800299c		@ r0 = 0x40005000
	add	r0, r1
	ldr.w	r1, [r0, #0xc00]	@ r1 = USB_EPn
	lsls	r1, r1, #0x11		@ N = bit 14
	bpl.n	.L0800299a
	ldr.w	r1, [r0, #0xc00]
	movw	r2, #0x8f8f
	ands	r1, r2
	movw	r2, #0xc080
	orrs	r1, r2
	str.w	r1, [r0, #0xc00]	@ write back USB_EPn
.L0800299a:
	bx	lr
.L0800299c:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_080029a0 - re-arms the transmit side of an endpoint.
@   r0 = endpoint number n. Reads USB_EPn (0x40005C00 + 4*n). If bit 6
@   (DATTOG_TX) is set, writes (USB_EPn & 0x8F8F) | 0x80C0 back; otherwise
@   does nothing. No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080029a0,"ax",%progbits
	.p2align 2
	.global fn_080029a0
	.thumb_func
	.type fn_080029a0, %function
fn_080029a0:
	lsls	r1, r0, #2		@ r1 = 4*n
	ldr	r0, .L080029c4		@ r0 = 0x40005000
	add	r0, r1
	ldr.w	r1, [r0, #0xc00]	@ r1 = USB_EPn
	lsls	r1, r1, #0x19		@ N = bit 6
	bpl.n	.L080029c2
	ldr.w	r1, [r0, #0xc00]
	movw	r2, #0x8f8f
	ands	r1, r2
	movw	r2, #0x80c0
	orrs	r1, r2
	str.w	r1, [r0, #0xc00]	@ write back USB_EPn
.L080029c2:
	bx	lr
.L080029c4:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_080029c8 - rewrites an endpoint register with its status fields masked.
@   r0 = endpoint number n. Writes (USB_EPn & 0x8E8F) | 0x8080 to USB_EPn
@   (0x40005C00 + 4*n). No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080029c8,"ax",%progbits
	.p2align 2
	.global fn_080029c8
	.thumb_func
	.type fn_080029c8, %function
fn_080029c8:
	lsls	r1, r0, #2		@ r1 = 4*n
	ldr	r0, .L080029e4		@ r0 = 0x40005000
	add	r1, r0
	ldr.w	r0, [r1, #0xc00]	@ r0 = USB_EPn
	movw	r2, #0x8e8f
	ands	r0, r2
	movw	r2, #0x8080
	orrs	r0, r2
	str.w	r0, [r1, #0xc00]	@ write back USB_EPn
	bx	lr
.L080029e4:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_080029e8 - copies bytes from USB packet memory to RAM.
@   r0 = destination (halfword pointer), r1 = packet memory offset, r2 = byte
@   count. Source = 0x40006000 + 2*r1; each iteration moves one halfword and
@   advances the source by 4 bytes (packet memory halfwords are 4 bytes
@   apart). Copies (r2 + 1) >> 1 halfwords and stores the updated destination
@   pointer to the RAM word 0x20000080 after each one. No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080029e8,"ax",%progbits
	.p2align 2
	.global fn_080029e8
	.thumb_func
	.type fn_080029e8, %function
fn_080029e8:
	ldr	r3, .L08002a08		@ r3 = 0x40006000 (packet memory)
	push	{r4, lr}
	.inst.n 0x1c52			@ adds r2, r2, #1
	lsrs	r2, r2, #1		@ r2 = halfword count
	add.w	r1, r3, r1, lsl #1	@ r1 = source address
	beq.n	.L08002a06
	ldr	r3, .L08002a0c		@ r3 = 0x20000080
.L080029f8:
	ldrh.w	r4, [r1], #4		@ read one halfword, source += 4
	strh.w	r4, [r0], #2		@ store one halfword, destination += 2
	str	r0, [r3]		@ 0x20000080 = destination
	.inst.n 0x1e52			@ subs r2, r2, #1
	bne.n	.L080029f8
.L08002a06:
	pop	{r4, pc}
.L08002a08:
	.word	0x40006000
.L08002a0c:
	.word	0x20000080

@ ----------------------------------------------------------------------------
@ fn_08002a10 - copies bytes from RAM to USB packet memory.
@   r0 = source (byte pointer), r1 = packet memory offset, r2 = byte count.
@   Destination = 0x40006000 + 2*r1; each iteration combines two source bytes
@   (low byte first) into a halfword, stores it and advances the destination
@   by 4 bytes. Copies (r2 + 1) >> 1 halfwords and stores the updated source
@   pointer to the RAM word 0x20000084 after each one. No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002a10,"ax",%progbits
	.p2align 2
	.global fn_08002a10
	.thumb_func
	.type fn_08002a10, %function
fn_08002a10:
	push	{r4, r5, lr}
	ldr	r3, .L08002a38		@ r3 = 0x40006000 (packet memory)
	.inst.n 0x1c52			@ adds r2, r2, #1
	lsrs	r2, r2, #1		@ r2 = halfword count
	add.w	r1, r3, r1, lsl #1	@ r1 = destination address
	beq.n	.L08002a36
	ldr	r4, .L08002a3c		@ r4 = 0x20000080
.L08002a20:
	ldrb.w	r3, [r0], #1		@ low byte
	.inst.n 0x1e52			@ subs r2, r2, #1
	ldrb.w	r5, [r0], #1		@ high byte
	orr.w	r3, r3, r5, lsl #8
	strh.w	r3, [r1], #4		@ store halfword, destination += 4
	str	r0, [r4, #4]		@ 0x20000084 = source
	bne.n	.L08002a20
.L08002a36:
	pop	{r4, r5, pc}
.L08002a38:
	.word	0x40006000
.L08002a3c:
	.word	0x20000080

@ ----------------------------------------------------------------------------
@ fn_08002a40 - USB correct-transfer service loop (called from the USB
@ interrupt handler fn_08002ca4 while USB_STS bit 15 CTRS is set).
@   Registers: r10 = USB_STS (0x40005C44), r5 = USB_EP0 (0x40005C00),
@   r4 = 0x2000007A, r9 = 0x200000A4. A halfword on the stack holds a copy of
@   the endpoint register being served.
@   Loop: reads USB_STS and stores its low halfword to 0x200000A4. When bit 15
@   (CTRS) is clear the function returns. Otherwise the endpoint number
@   EP_ID (bits 3:0) is stored as a byte to 0x20000068.
@   - EP_ID <> 0: reads USB_EPn. If its bit 15 (CTRS_RX) is set, writes it
@     back masked with 0x0F8F and calls the function whose address is stored
@     at 0x200000C0 + 4*n. Then, if the saved copy has bit 7 (CTRS_TX) set,
@     reads EP_ID again from 0x20000068, writes USB_EPn masked with 0x8F0F and
@     calls the function whose address is stored at 0x200000A4 + 4*n.
@   - EP_ID = 0: saves USB_EP0 & 0x3000 to the halfword 0x2000007A and
@     USB_EP0 & 0x30 to 0x2000007C, then writes USB_EP0 = ((EP0 & 0xBFBF)
@     ^ 0x2020) | 0x8080. If USB_STS bit 4 (DIR) is clear (IN transfer done)
@     it writes USB_EP0 & 0x8F0F and calls fn_08002d3c. Otherwise, if
@     USB_EP0 bit 11 (SETUP) is set it writes USB_EP0 & 0x0F8F and calls
@     fn_08002e28; else, if bit 15 (CTRS_RX) is set it writes USB_EP0 &
@     0x0F8F and calls fn_08002d9c; else it goes on with the loop. After a
@     call it rereads USB_EP0 & 0xBFBF, toggles bits 12 and 13 when the same
@     bits are set in the halfword at 0x2000007A (as it may have been
@     changed by the call) and bits 4 and 5 when set in the halfword at
@     0x2000007C, writes the result | 0x8080 to USB_EP0 and returns.
@   No parameters, no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002a40,"ax",%progbits
	.p2align 2
	.global fn_08002a40
	.thumb_func
	.type fn_08002a40, %function
fn_08002a40:
	push.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	movs	r0, #0
	strh.w	r0, [sp]		@ saved endpoint register copy = 0
	ldr.w	r10, .L08002b80		@ r10 = 0x40005C00
	movw	r6, #0xbfbf
	movw	r7, #0x8080
	ldr	r5, .L08002b80		@ r5 = 0x40005C00 (USB_EP0)
	ldr	r4, .L08002b84		@ r4 = 0x2000007A
	movw	r8, #0xf8f
	movw	r11, #0x8f0f
	ldr.w	r9, .L08002b88		@ r9 = 0x200000A4
	add.w	r10, r10, #0x44		@ r10 = 0x40005C44 (USB_STS)
	b.n	.L08002ad0
.L08002a6c:
	ldrh	r0, [r1]		@ r0 = USB_STS low halfword
	ldr	r2, .L08002b8c		@ r2 = 0x20000068
	ands.w	r0, r0, #0xf		@ EP_ID
	strb	r0, [r2]		@ 0x20000068 = EP_ID
	beq.n	.L08002ae2		@ endpoint 0
	ldr	r1, .L08002b90		@ r1 = 0x40005000
	add.w	r1, r1, r0, lsl #2
	ldr.w	r2, [r1, #0xc00]	@ r2 = USB_EPn
	strh.w	r2, [sp]		@ keep a copy
	ldrh.w	r2, [sp]
	lsls	r2, r2, #0x10		@ N = bit 15 (CTRS_RX)
	bpl.n	.L08002aa6
	ldr.w	r2, [r1, #0xc00]
	and.w	r2, r2, r8		@ 0x0F8F
	str.w	r2, [r1, #0xc00]	@ clear CTRS_RX
	ldr	r1, .L08002b94		@ r1 = 0x200000C4
	add.w	r0, r1, r0, lsl #2
	ldr.w	r0, [r0, #-0x4]		@ function pointer at 0x200000C0 + 4*n
	blx	r0
.L08002aa6:
	ldrh.w	r0, [sp]
	lsls	r0, r0, #0x18		@ N = bit 7 (CTRS_TX)
	bpl.n	.L08002ad0
	ldr	r0, .L08002b8c		@ r0 = 0x20000068
	ldr	r1, .L08002b90		@ r1 = 0x40005000
	ldrb	r0, [r0]		@ r0 = EP_ID
	add.w	r1, r1, r0, lsl #2
	ldr.w	r2, [r1, #0xc00]
	and.w	r2, r2, r11		@ 0x8F0F
	str.w	r2, [r1, #0xc00]	@ clear CTRS_TX
	ldr	r1, .L08002b98		@ r1 = 0x200000A8
	add.w	r0, r1, r0, lsl #2
	ldr.w	r0, [r0, #-0x4]		@ function pointer at 0x200000A4 + 4*n
	blx	r0
.L08002ad0:
	ldr.w	r0, [r10]		@ r0 = USB_STS
	mov	r1, r9
	strh.w	r0, [r9]		@ 0x200000A4 = USB_STS low halfword
	lsls	r0, r0, #0x10		@ N = bit 15 (CTRS)
	bmi.n	.L08002a6c
.L08002ade:
	pop.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08002ae2:
	ldr	r0, [r5]		@ r0 = USB_EP0
	strh	r0, [r4]		@ 0x2000007A = EP0
	ldrh	r0, [r4]
	and.w	r0, r0, #0x30
	strh	r0, [r4, #2]		@ 0x2000007C = EP0 & 0x30
	ldrh	r0, [r4]
	and.w	r0, r0, #0x3000
	strh	r0, [r4]		@ 0x2000007A = EP0 & 0x3000
	ldr	r0, [r5]
	ands	r0, r6			@ & 0xBFBF
	eor.w	r0, r0, #0x2000
	eor.w	r0, r0, #0x20
	orrs	r0, r7			@ | 0x8080
	str	r0, [r5]		@ write USB_EP0
	ldrh	r0, [r1]		@ r1 = 0x200000A4: saved USB_STS
	lsls	r0, r0, #0x1b		@ N = bit 4 (DIR)
	ldr	r0, [r5]		@ r0 = USB_EP0
	bmi.n	.L08002b3a
	and.w	r0, r0, r11		@ 0x8F0F
	str	r0, [r5]
	bl	fn_08002d3c
	b.n	.L08002b68
.L08002b1a:
	ldrh	r1, [r4]
	lsls	r1, r1, #0x12		@ N = bit 13 of the saved value
	bpl.n	.L08002b24
	eor.w	r0, r0, #0x2000
.L08002b24:
	ldrh	r1, [r4, #2]
	lsls	r1, r1, #0x1b		@ N = bit 4 of the saved value
	bmi.n	.L08002b78
.L08002b2a:
	ldrh	r1, [r4, #2]
	lsls	r1, r1, #0x1a		@ N = bit 5 of the saved value
	bpl.n	.L08002b34
	eor.w	r0, r0, #0x20
.L08002b34:
	orrs	r0, r7			@ | 0x8080
	str	r0, [r5]		@ write USB_EP0
	b.n	.L08002ade
.L08002b3a:
	strh.w	r0, [sp]		@ keep a copy of USB_EP0
	ldrh.w	r0, [sp]
	lsls	r0, r0, #0x14		@ N = bit 11 (SETUP)
	bpl.n	.L08002b54
	ldr	r0, [r5]
	and.w	r0, r0, r8		@ 0x0F8F
	str	r0, [r5]
	bl	fn_08002e28
	b.n	.L08002b68
.L08002b54:
	ldrh.w	r0, [sp]
	lsls	r0, r0, #0x10		@ N = bit 15 (CTRS_RX)
	bpl.n	.L08002ad0
	ldr	r0, [r5]
	and.w	r0, r0, r8		@ 0x0F8F
	str	r0, [r5]
	bl	fn_08002d9c
.L08002b68:
	ldr	r0, [r5]
	ldrh	r1, [r4]
	ands	r0, r6			@ & 0xBFBF
	lsls	r1, r1, #0x13		@ N = bit 12 of the saved value
	bpl.n	.L08002b1a
	eor.w	r0, r0, #0x1000
	b.n	.L08002b1a
.L08002b78:
	eor.w	r0, r0, #0x10
	b.n	.L08002b2a
	.short	0x0000			@ padding
.L08002b80:
	.word	0x40005c00
.L08002b84:
	.word	0x2000007a
.L08002b88:
	.word	0x200000a4
.L08002b8c:
	.word	0x20000068
.L08002b90:
	.word	0x40005000
.L08002b94:
	.word	0x200000c4
.L08002b98:
	.word	0x200000a8

@ ----------------------------------------------------------------------------
@ fn_08002b9c - reads the receive buffer address of an endpoint from the
@ buffer description table.
@   r0 = endpoint number n. Reads USB_BUFTAB (0x40005C50), takes its low 16
@   bits B and returns the halfword at 0x40006008 + 2*(B + 8*n) (the
@   ADDRn_RX entry of the table, at table offset 16*n + 8) in r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002b9c,"ax",%progbits
	.p2align 2
	.global fn_08002b9c
	.thumb_func
	.type fn_08002b9c, %function
fn_08002b9c:
	ldr	r1, .L08002bb4		@ r1 = 0x40005C50 (USB_BUFTAB)
	ldr	r1, [r1]
	uxth	r1, r1
	add.w	r0, r1, r0, lsl #3
	ldr	r1, .L08002bb8		@ r1 = 0x40006000
	add.w	r0, r1, r0, lsl #1
	ldrh	r0, [r0, #8]
	uxth	r0, r0
	bx	lr
	.short	0x0000			@ padding
.L08002bb4:
	.word	0x40005c50
.L08002bb8:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_08002bbc - reads the received byte count of an endpoint from the buffer
@ description table.
@   r0 = endpoint number n. Reads USB_BUFTAB (0x40005C50), takes its low 16
@   bits B and returns the low 10 bits of the halfword at
@   0x4000600C + 2*(B + 8*n) (the CNTn_RX entry, table offset 16*n + 0xC).
@ ----------------------------------------------------------------------------
	.section .text.fn_08002bbc,"ax",%progbits
	.p2align 2
	.global fn_08002bbc
	.thumb_func
	.type fn_08002bbc, %function
fn_08002bbc:
	ldr	r1, .L08002bd4		@ r1 = 0x40005C50 (USB_BUFTAB)
	ldr	r1, [r1]
	uxth	r1, r1
	add.w	r0, r1, r0, lsl #3
	ldr	r1, .L08002bd8		@ r1 = 0x40006000
	add.w	r0, r1, r0, lsl #1
	ldrh	r0, [r0, #0xc]
	ubfx	r0, r0, #0, #0xa	@ keep the low 10 bits
	bx	lr
.L08002bd4:
	.word	0x40005c50
.L08002bd8:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_08002bdc - returns the receive status field of an endpoint.
@   r0 = endpoint number n. Returns USB_EPn (0x40005C00 + 4*n) & 0x3000
@   (STS_RX, bits 13:12) in r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002bdc,"ax",%progbits
	.p2align 2
	.global fn_08002bdc
	.thumb_func
	.type fn_08002bdc, %function
fn_08002bdc:
	ldr	r1, .L08002bf0		@ r1 = 0x40005000
	add.w	r0, r1, r0, lsl #2
	ldr.w	r0, [r0, #0xc00]	@ r0 = USB_EPn
	ubfx	r0, r0, #0xc, #2	@ STS_RX field
	lsls	r0, r0, #0xc		@ back into bits 13:12
	bx	lr
	.short	0x0000			@ padding
.L08002bf0:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_08002bf4 - reads the transmit buffer address of an endpoint from the
@ buffer description table.
@   r0 = endpoint number n. Reads USB_BUFTAB (0x40005C50), takes its low 16
@   bits B and returns the halfword at 0x40006000 + 2*(B + 8*n) (the
@   ADDRn_TX entry, table offset 16*n) in r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002bf4,"ax",%progbits
	.p2align 2
	.global fn_08002bf4
	.thumb_func
	.type fn_08002bf4, %function
fn_08002bf4:
	ldr	r1, .L08002c08		@ r1 = 0x40005C50 (USB_BUFTAB)
	ldr	r1, [r1]
	uxth	r1, r1
	add.w	r0, r1, r0, lsl #3
	ldr	r1, .L08002c0c		@ r1 = 0x40006000
	ldrh.w	r0, [r1, r0, lsl #1]
	uxth	r0, r0
	bx	lr
.L08002c08:
	.word	0x40005c50
.L08002c0c:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_08002c10 - sets up the USB driver's RAM structures and starts it.
@   Stores 0x20000278 to the word at 0x2000006C (request block pointer),
@   writes the byte 2 to 0x20000280 (offset 8 of that block), stores 0x200000F8
@   to the word at 0x20000070 and 0x20000150 to the word at 0x20000074 (two
@   function tables). Then calls the function whose address is the first word
@   of the table at 0x200000F8, and sets bit 28 (0x10000000) of the word at
@   0x40001820. No parameters, no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002c10,"ax",%progbits
	.p2align 2
	.global fn_08002c10
	.thumb_func
	.type fn_08002c10, %function
fn_08002c10:
	ldr	r0, .L08002c38		@ r0 = address of the pointer word 0x2000006C
	push	{r4, lr}
	ldr	r1, .L08002c34		@ r1 = 0x20000278
	movs	r2, #2
	str	r1, [r0]		@ 0x2000006C = 0x20000278
	strb	r2, [r1, #8]		@ 0x20000280 = 2
	ldr	r2, .L08002c40		@ r2 = 0x20000150
	ldr	r1, .L08002c3c		@ r1 = 0x200000F8
	strd	r1, r2, [r0, #4]	@ 0x20000070 = 0x200000F8, 0x20000074 = 0x20000150
	ldr	r0, [r1]
	blx	r0			@ call the first function of the table at 0x200000F8
	ldr	r0, .L08002c44		@ r0 = 0x40001820
	ldr	r1, [r0]
	orr.w	r1, r1, #0x10000000
	str	r1, [r0]		@ set bit 28
	pop	{r4, pc}
.L08002c34:
	.word	0x20000278
.L08002c38:
	.word	0x2000006c
.L08002c3c:
	.word	0x200000f8
.L08002c40:
	.word	0x20000150
.L08002c44:
	.word	0x40001820

@ ----------------------------------------------------------------------------
@ fn_08002ca4 - USB interrupt service routine body (called by irq20_handler).
@   Reads USB_STS (0x40005C44), keeps its low halfword at 0x200000A4 and
@   masks it with the halfword at 0x20000078, then tests, in this order:
@   - bit 15 (CTRS): calls fn_08002a40.
@   - bit 10 (RST): writes 0xFBFF to USB_STS and calls the function whose
@     address is the second word (offset 4) of the table at 0x200000F8.
@   - bit 12 (WKUP): writes 0xEFFF to USB_STS and calls fn_08001c84(0).
@   - bit 11 (SUSPD): if the byte at 0x20000178 is zero calls fn_08001c84(2),
@     otherwise calls fn_08002518; then writes 0xF7FF to USB_STS.
@   - bit 9 (SOF): writes 0xFDFF to USB_STS and increments the byte at
@     0x200000A2.
@   Each flag is tested again against a fresh read of the masked copy at
@   0x200000A4. No parameters, no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002ca4,"ax",%progbits
	.p2align 2
	.global fn_08002ca4
	.thumb_func
	.type fn_08002ca4, %function
fn_08002ca4:
	push	{r4, r5, r6, lr}
	ldr	r6, .L08002d24		@ r6 = 0x40005C44 (USB_STS)
	ldr	r0, [r6]
	ldr	r4, .L08002d28		@ r4 = 0x200000A2
	strh	r0, [r4, #2]		@ 0x200000A4 = USB_STS low halfword
	ldrh	r0, [r4, #2]
	ldr	r5, .L08002d2c		@ r5 = 0x20000078 (interrupt mask halfword)
	ldrh	r1, [r5]
	ands	r0, r1
	lsls	r0, r0, #0x10		@ N = bit 15 (CTRS)
	bpl.n	.L08002cbe
	bl	fn_08002a40
.L08002cbe:
	ldrh	r0, [r4, #2]
	ldrh	r1, [r5]
	ands	r0, r1
	lsls	r0, r0, #0x15		@ N = bit 10 (RST)
	bpl.n	.L08002cd4
	movw	r0, #0xfbff
	str	r0, [r6]		@ clear the flag
	ldr	r0, .L08002d30		@ r0 = 0x200000F8
	ldr	r0, [r0, #4]		@ second function of the table
	blx	r0
.L08002cd4:
	ldrh	r0, [r4, #2]
	ldrh	r1, [r5]
	ands	r0, r1
	lsls	r0, r0, #0x13		@ N = bit 12 (WKUP)
	bpl.n	.L08002cea
	movw	r0, #0xefff
	str	r0, [r6]		@ clear the flag
	movs	r0, #0
	bl	fn_08001c84
.L08002cea:
	ldrh	r0, [r4, #2]
	ldrh	r1, [r5]
	ands	r0, r1
	lsls	r0, r0, #0x14		@ N = bit 11 (SUSPD)
	bpl.n	.L08002d0c
	ldr	r0, .L08002d34		@ r0 = 0x20000178
	ldrb	r0, [r0]
	cbz	r0, .L08002d00
	bl	fn_08002518
	b.n	.L08002d06
.L08002d00:
	movs	r0, #2
	bl	fn_08001c84
.L08002d06:
	movw	r0, #0xf7ff
	str	r0, [r6]		@ clear the flag
.L08002d0c:
	ldrh	r0, [r4, #2]
	ldrh	r1, [r5]
	ands	r0, r1
	lsls	r0, r0, #0x16		@ N = bit 9 (SOF)
	bpl.n	.L08002d22
	movw	r0, #0xfdff
	str	r0, [r6]		@ clear the flag
	ldrb	r0, [r4]
	.inst.n 0x1c40			@ adds r0, r0, #1
	strb	r0, [r4]		@ 0x200000A2 += 1
.L08002d22:
	pop	{r4, r5, r6, pc}
.L08002d24:
	.word	0x40005c44
.L08002d28:
	.word	0x200000a2
.L08002d2c:
	.word	0x20000078
.L08002d30:
	.word	0x200000f8
.L08002d34:
	.word	0x20000178

@ ----------------------------------------------------------------------------
@ irq20_handler - interrupt 20 vector target; jumps to fn_08002ca4 (the USB
@ interrupt service routine body) with a plain branch.
@ ----------------------------------------------------------------------------
	.section .text.irq20_handler,"ax",%progbits
	.p2align 2
	.global irq20_handler
	.thumb_func
	.type irq20_handler, %function
irq20_handler:
	b.w	fn_08002ca4

@ ----------------------------------------------------------------------------
@ fn_08002d3c - finishes a control transfer after an IN transfer completed.
@   Let P = the pointer held at RAM word 0x2000006C and S = P[8] (transfer
@   state). S = 2 or 4: calls fn_080009ec and keeps the state; S = 6: when
@   P[1] = 5 and (P[0] & 0x7F) = 0 calls fn_08002ea0(P[3]) and the function at
@   offset 0x20 of the table pointed to by the word at 0x20000074, then calls
@   the function at offset 8 of the table pointed to by the word at
@   0x20000070, and sets S = 8; any other S becomes 8. The state is stored
@   back to P[8] and fn_08002de4 is entered by a tail branch.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002d3c,"ax",%progbits
	.p2align 2
	.global fn_08002d3c
	.thumb_func
	.type fn_08002d3c, %function
fn_08002d3c:
	push	{r4, lr}
	ldr	r4, .L08002d8c		@ r4 = address of the pointer word 0x2000006C
	ldr	r0, [r4]		@ r0 = P
	ldrb	r1, [r0, #8]		@ r1 = S
	cmp	r1, #2
	beq.n	.L08002d52
	cmp	r1, #4
	beq.n	.L08002d52
	cmp	r1, #6
	beq.n	.L08002d5c
	b.n	.L08002d7e
.L08002d52:
	bl	fn_080009ec
	ldr	r0, [r4]
	ldrb	r0, [r0, #8]		@ state unchanged
	b.n	.L08002d80
.L08002d5c:
	ldrb	r1, [r0, #1]
	cmp	r1, #5
	bne.n	.L08002d76
	ldrb	r1, [r0]
	lsls	r1, r1, #0x19		@ low 7 bits of P[0]
	bne.n	.L08002d76
	ldrb	r0, [r0, #3]
	bl	fn_08002ea0		@ argument P[3]
	ldr	r0, .L08002d90		@ r0 = address of the table pointer word 0x20000074
	ldr	r0, [r0]
	ldr	r0, [r0, #0x20]		@ function at table offset 0x20
	blx	r0
.L08002d76:
	ldr	r0, .L08002d94		@ r0 = address of the table pointer word 0x20000070
	ldr	r0, [r0]
	ldr	r0, [r0, #8]		@ function at table offset 8
	blx	r0
.L08002d7e:
	movs	r0, #8			@ new state 8
.L08002d80:
	ldr	r1, [r4]
	strb	r0, [r1, #8]		@ P[8] = state
	pop.w	{r4, lr}
	b.w	fn_08002de4
.L08002d8c:
	.word	0x2000006c
.L08002d90:
	.word	0x20000074
.L08002d94:
	.word	0x20000070

@ ----------------------------------------------------------------------------
@ fn_08002d98 - empty function; returns at once. Two bytes of padding follow.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002d98,"ax",%progbits
	.p2align 2
	.global fn_08002d98
	.thumb_func
	.type fn_08002d98, %function
fn_08002d98:
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08002d9c - finishes a control transfer after an OUT transfer completed.
@   Let P = the pointer held at RAM word 0x2000006C and S = P[8] (transfer
@   state). S = 3 or 5: calls fn_08000aa0 and reloads the state from P[8];
@   S = 7: calls the function at offset 0xC of the table pointed to by the
@   word at 0x20000070 and sets S = 8; S = 2 or 4 and any other value: S = 8.
@   The state is stored back to P[8] and fn_08002de4 is entered by a tail
@   branch.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002d9c,"ax",%progbits
	.p2align 2
	.global fn_08002d9c
	.thumb_func
	.type fn_08002d9c, %function
fn_08002d9c:
	push	{r4, lr}
	ldr	r4, .L08002ddc		@ r4 = address of the pointer word 0x2000006C
	ldr	r0, [r4]
	ldrb	r0, [r0, #8]		@ r0 = S
	cmp	r0, #2
	beq.n	.L08002dcc
	cmp	r0, #4
	beq.n	.L08002dcc
	cmp	r0, #3
	beq.n	.L08002dba
	cmp	r0, #5
	beq.n	.L08002dba
	cmp	r0, #7
	beq.n	.L08002dc4
	b.n	.L08002dcc
.L08002dba:
	bl	fn_08000aa0
	ldr	r0, [r4]
	ldrb	r0, [r0, #8]		@ state reloaded
	b.n	.L08002dce
.L08002dc4:
	ldr	r0, .L08002de0		@ r0 = address of the table pointer word 0x20000070
	ldr	r0, [r0]
	ldr	r0, [r0, #0xc]		@ function at table offset 0xC
	blx	r0
.L08002dcc:
	movs	r0, #8			@ new state 8
.L08002dce:
	ldr	r1, [r4]
	strb	r0, [r1, #8]		@ P[8] = state
	pop.w	{r4, lr}
	b.w	fn_08002de4
	.short	0x0000			@ padding
.L08002ddc:
	.word	0x2000006c
.L08002de0:
	.word	0x20000070

@ ----------------------------------------------------------------------------
@ fn_08002de4 - sets the receive count of endpoint 0 and checks the transfer
@ state.
@   Calls fn_08002f08(0, byte at 0x20000124) (the byte at offset 0x2C of the
@   structure at 0x200000F8). Then reads the state S = P[8], P being the
@   pointer held at RAM word 0x2000006C. S = 8: stores 0x1000 to the halfword
@   at 0x2000007A and 0x10 to the halfword at 0x2000007C and returns 0.
@   S = 9: returns 1. Any other S: returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002de4,"ax",%progbits
	.p2align 2
	.global fn_08002de4
	.thumb_func
	.type fn_08002de4, %function
fn_08002de4:
	ldr	r0, .L08002e18		@ r0 = 0x200000F8
	push	{r4, lr}
	ldrb.w	r1, [r0, #0x2c]		@ r1 = byte at 0x20000124
	movs	r0, #0
	bl	fn_08002f08		@ (endpoint 0, byte)
	ldr	r0, .L08002e1c		@ r0 = address of the pointer word 0x2000006C
	ldr	r0, [r0]
	ldrb	r0, [r0, #8]
	cmp	r0, #8
	beq.n	.L08002e02
	cmp	r0, #9
	beq.n	.L08002e14
	b.n	.L08002e10
.L08002e02:
	ldr	r1, .L08002e20		@ r1 = 0x2000007A
	mov.w	r0, #0x1000
	strh	r0, [r1]		@ 0x2000007A = 0x1000
	ldr	r1, .L08002e24		@ r1 = 0x2000007C
	movs	r0, #0x10
	strh	r0, [r1]		@ 0x2000007C = 0x10
.L08002e10:
	movs	r0, #0			@ return 0
	pop	{r4, pc}
.L08002e14:
	movs	r0, #1			@ return 1
	pop	{r4, pc}
.L08002e18:
	.word	0x200000f8
.L08002e1c:
	.word	0x2000006c
.L08002e20:
	.word	0x2000007a
.L08002e24:
	.word	0x2000007c

@ ----------------------------------------------------------------------------
@ fn_08002e28 - handles a received SETUP packet on endpoint 0.
@   Reads USB_BUFTAB (0x40005C50), finds the endpoint 0 receive buffer
@   address in the buffer description table (halfword at 0x40006008 +
@   2*(BUFTAB low 16 bits)) and the packet at 0x40006000 + 2*that address.
@   Let P = the pointer held at RAM word 0x2000006C. When P[8] is not 9 it
@   copies the packet into P: P[0] = packet byte 0, P[1] = packet byte 1,
@   halfword P+2 = swap_bytes16(halfword at packet+4), halfword P+4 =
@   swap_bytes16(halfword at packet+8), halfword P+6 = halfword at
@   packet+12. Sets P[8] = 1. When the halfword at P+6 is non-zero calls
@   fn_08000b44, otherwise fn_0800197c; then enters fn_08002de4 by a tail
@   branch.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002e28,"ax",%progbits
	.p2align 2
	.global fn_08002e28
	.thumb_func
	.type fn_08002e28, %function
fn_08002e28:
	push	{r4, r5, r6, lr}
	ldr	r0, .L08002e84		@ r0 = 0x40005C50 (USB_BUFTAB)
	ldr	r0, [r0]
	ldr	r5, .L08002e8c		@ r5 = address of the pointer word 0x2000006C
	lsls	r0, r0, #0x10
	lsrs	r1, r0, #0xf		@ r1 = 2 * (BUFTAB low 16 bits)
	ldr	r0, .L08002e88		@ r0 = 0x40006000
	add	r1, r0
	ldrh	r1, [r1, #8]		@ receive buffer address of endpoint 0
	uxth	r1, r1
	add.w	r4, r0, r1, lsl #1	@ r4 = packet address
	ldr	r0, [r5]
	ldrb	r1, [r0, #8]
	cmp	r1, #9
	beq.n	.L08002e68
	ldrb	r1, [r4]
	strb	r1, [r0]		@ P[0]
	ldrb	r1, [r4, #1]
	strb	r1, [r0, #1]		@ P[1]
	ldrh	r0, [r4, #4]
	bl	swap_bytes16
	ldr	r1, [r5]
	strh	r0, [r1, #2]		@ halfword P+2
	ldrh	r0, [r4, #8]
	bl	swap_bytes16
	ldr	r1, [r5]
	strh	r0, [r1, #4]		@ halfword P+4
	ldrh	r0, [r4, #0xc]
	strh	r0, [r1, #6]		@ halfword P+6
.L08002e68:
	ldr	r0, [r5]
	movs	r1, #1
	strb	r1, [r0, #8]		@ P[8] = 1
	ldrh	r0, [r0, #6]
	cbz	r0, .L08002e7e
	bl	fn_08000b44
.L08002e76:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08002de4
.L08002e7e:
	bl	fn_0800197c
	b.n	.L08002e76
.L08002e84:
	.word	0x40005c50
.L08002e88:
	.word	0x40006000
.L08002e8c:
	.word	0x2000006c

@ ----------------------------------------------------------------------------
@ fn_08002e90 - sets the packet buffer description table address.
@   r0 = value. Writes r0 & 0xFFFFFFF8 to USB_BUFTAB (0x40005C50).
@ ----------------------------------------------------------------------------
	.section .text.fn_08002e90,"ax",%progbits
	.p2align 2
	.global fn_08002e90
	.thumb_func
	.type fn_08002e90, %function
fn_08002e90:
	ldr	r1, .L08002e9c		@ r1 = 0x40005C50 (USB_BUFTAB)
	bic.w	r0, r0, #7
	str	r0, [r1]
	bx	lr
	.short	0x0000			@ padding
.L08002e9c:
	.word	0x40005c50

@ ----------------------------------------------------------------------------
@ fn_08002ea0 - enables the endpoints and sets the device address.
@   r0 = address value. For n = 0 .. (byte at 0x200000E0) - 1 writes
@   USB_EPn (0x40005C00 + 4*n) = (USB_EPn & 0x8F8F) | n | 0x8080 (endpoint
@   address field set to n). Then writes USB_ADDR (0x40005C4C) = r0 | 0x80.
@   No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002ea0,"ax",%progbits
	.p2align 2
	.global fn_08002ea0
	.thumb_func
	.type fn_08002ea0, %function
fn_08002ea0:
	push	{r4, r5, r6, r7, lr}
	ldr	r1, .L08002edc		@ r1 = 0x200000E0
	ldr	r5, .L08002ee0		@ r5 = 0x40005000
	movw	r7, #0x8f8f
	ldrb	r3, [r1]		@ r3 = number of endpoints
	movs	r1, #0			@ n = 0
	movw	r12, #0x8080
	b.n	.L08002ecc
.L08002eb4:
	uxtb	r6, r1
	add.w	r4, r5, r6, lsl #2
	ldr.w	r2, [r4, #0xc00]	@ r2 = USB_EPn
	ands	r2, r7
	orrs	r2, r6
	orr.w	r2, r2, r12
	str.w	r2, [r4, #0xc00]	@ write USB_EPn
	.inst.n 0x1c49			@ adds r1, r1, #1
.L08002ecc:
	cmp	r1, r3
	bcc.n	.L08002eb4
	ldr	r1, .L08002ee4		@ r1 = 0x40005C4C (USB_ADDR)
	orr.w	r0, r0, #0x80
	str	r0, [r1]
	pop	{r4, r5, r6, r7, pc}
	.short	0x0000			@ padding
.L08002edc:
	.word	0x200000e0
.L08002ee0:
	.word	0x40005000
.L08002ee4:
	.word	0x40005c4c

@ ----------------------------------------------------------------------------
@ fn_08002ee8 - writes the receive buffer address of an endpoint into the
@ buffer description table.
@   r0 = endpoint number n, r1 = address. Reads USB_BUFTAB (0x40005C50), takes
@   its low 16 bits B and stores r1 & 0xFFFFFFFE as a word at
@   0x40006008 + 2*(B + 8*n) (the ADDRn_RX entry, table offset 16*n + 8).
@ ----------------------------------------------------------------------------
	.section .text.fn_08002ee8,"ax",%progbits
	.p2align 2
	.global fn_08002ee8
	.thumb_func
	.type fn_08002ee8, %function
fn_08002ee8:
	ldr	r2, .L08002f00		@ r2 = 0x40005C50 (USB_BUFTAB)
	bic.w	r1, r1, #1
	ldr	r2, [r2]
	uxth	r2, r2
	add.w	r0, r2, r0, lsl #3
	ldr	r2, .L08002f04		@ r2 = 0x40006000
	add.w	r0, r2, r0, lsl #1
	str	r1, [r0, #8]
	bx	lr
.L08002f00:
	.word	0x40005c50
.L08002f04:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_08002f08 - writes the receive byte-count entry of an endpoint.
@   r0 = endpoint number n, r1 = buffer size in bytes. Reads USB_BUFTAB
@   (0x40005C50), takes its low 16 bits B and stores a word at
@   0x4000600C + 2*(B + 8*n) (the CNTn_RX entry, table offset 16*n + 0xC):
@   - r1 <= 0x3E: value = ((r1 >> 1) + (r1 & 1)) << 10;
@   - r1 > 0x3E: value = 0x8000 | ((r1 >> 5) - (1 if (r1 & 0x1F) = 0 else 0))
@     << 10 (the second count is masked to 16 bits before the shift).
@ ----------------------------------------------------------------------------
	.section .text.fn_08002f08,"ax",%progbits
	.p2align 2
	.global fn_08002f08
	.thumb_func
	.type fn_08002f08, %function
fn_08002f08:
	ldr	r2, .L08002f40		@ r2 = 0x40005C50 (USB_BUFTAB)
	ldr	r2, [r2]
	cmp	r1, #0x3e
	uxth	r2, r2
	add.w	r0, r2, r0, lsl #3
	ldr	r2, .L08002f44		@ r2 = 0x4000600C
	add.w	r2, r2, r0, lsl #1	@ r2 = address of the CNTn_RX entry
	bls.n	.L08002f30
	lsrs	r0, r1, #5
	lsls	r1, r1, #0x1b		@ Z = (r1 & 0x1F) == 0
	bne.n	.L08002f26
	.inst.n 0x1e40			@ subs r0, r0, #1
	uxth	r0, r0
.L08002f26:
	mov.w	r1, #0x8000
	orr.w	r0, r1, r0, lsl #10
	b.n	.L08002f3a
.L08002f30:
	lsrs	r0, r1, #1
	lsls	r1, r1, #0x1f		@ Z = (r1 & 1) == 0
	beq.n	.L08002f38
	.inst.n 0x1c40			@ adds r0, r0, #1
.L08002f38:
	lsls	r0, r0, #0xa
.L08002f3a:
	str	r0, [r2]
	bx	lr
	.short	0x0000			@ padding
.L08002f40:
	.word	0x40005c50
.L08002f44:
	.word	0x4000600c

@ ----------------------------------------------------------------------------
@ fn_08002f48 - sets both status fields of an endpoint register by toggling.
@   r0 = endpoint number n. Writes USB_EPn (0x40005C00 + 4*n) =
@   (((USB_EPn & 0xBF8F) ^ 0x3000) | 0x8080). No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002f48,"ax",%progbits
	.p2align 2
	.global fn_08002f48
	.thumb_func
	.type fn_08002f48, %function
fn_08002f48:
	lsls	r1, r0, #2		@ r1 = 4*n
	ldr	r0, .L08002f68		@ r0 = 0x40005000
	add	r1, r0
	ldr.w	r0, [r1, #0xc00]	@ r0 = USB_EPn
	movw	r2, #0xbf8f
	ands	r0, r2
	eor.w	r0, r0, #0x3000
	movw	r2, #0x8080
	orrs	r0, r2
	str.w	r0, [r1, #0xc00]	@ write back USB_EPn
	bx	lr
.L08002f68:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_08002f6c - writes the transmit buffer address of an endpoint into the
@ buffer description table.
@   r0 = endpoint number n, r1 = address. Reads USB_BUFTAB (0x40005C50), takes
@   its low 16 bits B and stores r1 & 0xFFFFFFFE as a word at
@   0x40006000 + 2*(B + 8*n) (the ADDRn_TX entry, table offset 16*n).
@ ----------------------------------------------------------------------------
	.section .text.fn_08002f6c,"ax",%progbits
	.p2align 2
	.global fn_08002f6c
	.thumb_func
	.type fn_08002f6c, %function
fn_08002f6c:
	ldr	r2, .L08002f84		@ r2 = 0x40005C50 (USB_BUFTAB)
	bic.w	r1, r1, #1
	ldr	r2, [r2]
	uxth	r2, r2
	add.w	r0, r2, r0, lsl #3
	ldr	r2, .L08002f88		@ r2 = 0x40006000
	str.w	r1, [r2, r0, lsl #1]
	bx	lr
	.short	0x0000			@ padding
.L08002f84:
	.word	0x40005c50
.L08002f88:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_08002f8c - writes the transmit byte-count entry of an endpoint.
@   r0 = endpoint number n, r1 = count. Reads USB_BUFTAB (0x40005C50), takes
@   its low 16 bits B and stores r1 as a word at 0x40006004 + 2*(B + 8*n)
@   (the CNTn_TX entry, table offset 16*n + 4).
@ ----------------------------------------------------------------------------
	.section .text.fn_08002f8c,"ax",%progbits
	.p2align 2
	.global fn_08002f8c
	.thumb_func
	.type fn_08002f8c, %function
fn_08002f8c:
	ldr	r2, .L08002fa0		@ r2 = 0x40005C50 (USB_BUFTAB)
	ldr	r2, [r2]
	uxth	r2, r2
	add.w	r0, r2, r0, lsl #3
	ldr	r2, .L08002fa4		@ r2 = 0x40006000
	add.w	r0, r2, r0, lsl #1
	str	r1, [r0, #4]
	bx	lr
.L08002fa0:
	.word	0x40005c50
.L08002fa4:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_08002fa8 - keeps bits 15, 11, 7 and 3:0 of an endpoint register and ORs
@ in new bits.
@   r0 = endpoint number n, r1 = bits to set. Writes USB_EPn
@   (0x40005C00 + 4*n) = (USB_EPn & 0x898F) | r1. No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002fa8,"ax",%progbits
	.p2align 2
	.global fn_08002fa8
	.thumb_func
	.type fn_08002fa8, %function
fn_08002fa8:
	lsls	r2, r0, #2		@ r2 = 4*n
	ldr	r0, .L08002fc0		@ r0 = 0x40005000
	add	r2, r0
	ldr.w	r0, [r2, #0xc00]	@ r0 = USB_EPn
	movw	r3, #0x898f
	ands	r0, r3
	orrs	r0, r1
	str.w	r0, [r2, #0xc00]	@ write back USB_EPn
	bx	lr
.L08002fc0:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_08002fc4 - copies a received packet out of packet memory.
@   r0 = endpoint address (bit 7 ignored), r1 = destination pointer. With
@   n = r0 & 0x7F: gets the received count from fn_08002bbc(n) and the receive
@   buffer address from fn_08002b9c(n), calls fn_080029e8(destination,
@   address, count) and returns the count in r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002fc4,"ax",%progbits
	.p2align 2
	.global fn_08002fc4
	.thumb_func
	.type fn_08002fc4, %function
fn_08002fc4:
	push	{r4, r5, r6, lr}
	and.w	r6, r0, #0x7f		@ r6 = n
	mov	r5, r1			@ r5 = destination
	mov	r0, r6
	bl	fn_08002bbc		@ r0 = received count
	mov	r4, r0
	mov	r0, r6
	bl	fn_08002b9c		@ r0 = receive buffer address
	mov	r1, r0
	mov	r2, r4
	mov	r0, r5
	bl	fn_080029e8
	mov	r0, r4			@ return the count
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08002fe8 - copies a packet into packet memory and sets the transmit count.
@   r0 = endpoint address (bit 7 ignored), r1 = source pointer, r2 = byte
@   count (low 16 bits used). With n = r0 & 0x7F: gets the transmit buffer
@   address from fn_08002bf4(n), calls fn_08002a10(source, address, count),
@   then fn_08002f8c(n, count). Returns 0 in r0. Two bytes of padding follow.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002fe8,"ax",%progbits
	.p2align 2
	.global fn_08002fe8
	.thumb_func
	.type fn_08002fe8, %function
fn_08002fe8:
	push	{r4, r5, r6, lr}
	and.w	r5, r0, #0x7f		@ r5 = n
	mov	r4, r2			@ r4 = count
	mov	r6, r1			@ r6 = source
	mov	r0, r5
	bl	fn_08002bf4		@ r0 = transmit buffer address
	mov	r1, r0
	uxth	r2, r4
	mov	r0, r6
	bl	fn_08002a10
	uxth	r1, r4
	mov	r0, r5
	bl	fn_08002f8c
	movs	r0, #0			@ return 0
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
