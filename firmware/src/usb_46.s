@ usb_46.s - USB device code of the application: mass-storage status/data helpers, endpoint register helpers, standard request handlers, USB register save/restore and bulk transfer helpers
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ USB register block used by this file (N32G455 user manual, USB chapter): base
@ 0x40005C00. USB_EPn (n = 0..7) is the word at 0x40005C00 + 4*n. Bits of USB_EPn:
@ CTRS_RX 15, DATTOG_RX 14, STS_RX[1:0] 13:12, SETUP 11, EP_TYPE[1:0] 10:9,
@ EP_KIND 8, CTRS_TX 7, DATTOG_TX 6, STS_TX[1:0] 5:4, EPADDR[3:0] 3:0.
@ USB_CTRL is at 0x40005C40, USB_STS at 0x40005C44. The packet buffer memory
@ (USB SRAM) starts at 0x40006000. Code that reaches USB_EPn adds 0xC00 to the
@ base 0x40005000 held in a literal.

@ ----------------------------------------------------------------------------
@ fn_0800b894 - handler that sends a 12-byte block built from words 0x200003B4 and
@ 0x200003B0 or, when fn_0800a9ec returns non-zero, a short failure answer.
@ No parameters, no return value. Entered only by the tail jump b.w at 0x080084B4
@ (from 0x08008378); it returns to the caller of 0x08008378.
@ Calls fn_0800a9ec, which writes word 0x200003B4 = 0x2E and word 0x200003B0 = 0x800
@ and returns 0 on its only path.
@ Result non-zero: store_two_bytes(2, 0x3A), fn_0800bb1c(1, 1), then tail jump to
@ fn_080081c8(0).
@ Result zero: loads word 0x200003B4 and stores it big-endian into bytes +4..+7 of
@ the buffer 0x2000042B (byte +4 = bits 31..24, +5 = bits 23..16, +6 = bits 15..8,
@ +7 = bits 7..0); loads word 0x200003B0 and stores bits 23..16, 15..8, 7..0 into
@ bytes +9, +10, +11 (bytes +0..+3 and +8 are not written). Then tail jump to
@ fn_0800c6f0(0x2000042B, 12), which sends the 12 bytes on endpoint 0x81.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b894,"ax",%progbits
	.p2align 2
	.global fn_0800b894
	.thumb_func
	.type fn_0800b894, %function
fn_0800b894:
	push	{r4, lr}
	bl	fn_0800a9ec
	cbz	r0, .L0800b8b6		@ zero: build the 12-byte answer
	movs	r1, #0x3a
	movs	r0, #0x2
	bl	store_two_bytes
	movs	r1, #0x1
	mov	r0, r1
	bl	fn_0800bb1c
	pop.w	{r4, lr}
	movs	r0, #0x0
	b.w	fn_080081c8
.L0800b8b6:
	ldr	r0, .L0800b8e4		@ r0 = 0x200003B4
	ldr	r1, [r0, #0x0]
	ldr	r0, .L0800b8e8		@ r0 = 0x2000042B
	lsrs	r2, r1, #0x18
	strb	r2, [r0, #0x4]
	lsrs	r2, r1, #0x10
	strb	r2, [r0, #0x5]
	lsrs	r2, r1, #0x8
	strb	r2, [r0, #0x6]
	strb	r1, [r0, #0x7]
	ldr	r1, .L0800b8ec		@ r1 = 0x200003B0
	ldr	r1, [r1, #0x0]
	lsrs	r2, r1, #0x10
	strb	r2, [r0, #0x9]
	lsrs	r2, r1, #0x8
	strb	r2, [r0, #0xa]
	strb	r1, [r0, #0xb]
	pop.w	{r4, lr}
	movs	r1, #0xc
	b.w	fn_0800c6f0
	.short	0x0000			@ padding
.L0800b8e4:
	.word	0x200003b4
.L0800b8e8:
	.word	0x2000042b
.L0800b8ec:
	.word	0x200003b0

@ ----------------------------------------------------------------------------
@ fn_0800b8f0 - sends the bytes at 0x20000411, at most 0x12 of them, on endpoint 0x81.
@ No parameters, no return value (ends in a tail branch).
@ r1 = byte 0x200066C7 (0x200066B4 + 0x13), limited to 0x12 (unsigned compare).
@ Tail-calls fn_0800c6f0(0x20000411, r1). fn_0800c6f0 calls fn_08010130(0x81, pointer,
@ length) and fn_0800ba1c(1, 0x30), stores 3 in byte 0x20000438, subtracts the length
@ from word 0x200066DC and stores 0 in byte 0x200066E0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b8f0,"ax",%progbits
	.p2align 2
	.global fn_0800b8f0
	.thumb_func
	.type fn_0800b8f0, %function
fn_0800b8f0:
	ldr	r0, .L0800b900		@ r0 = 0x200066B4
	ldrb	r1, [r0, #0x13]
	cmp	r1, #0x12
	bls.n	.L0800b8fa
	movs	r1, #0x12		@ limit the length to 0x12
.L0800b8fa:
	ldr	r0, .L0800b904		@ r0 = 0x20000411
	b.w	fn_0800c6f0
.L0800b900:
	.word	0x200066b4
.L0800b904:
	.word	0x20000411

@ ----------------------------------------------------------------------------
@ fn_0800b908 - tail-calls fn_0800bb1c(0, 1).
@ No parameters, no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b908,"ax",%progbits
	.p2align 2
	.global fn_0800b908
	.thumb_func
	.type fn_0800b908, %function
fn_0800b908:
	movs	r1, #0x1
	movs	r0, #0x0
	b.w	fn_0800bb1c

@ ----------------------------------------------------------------------------
@ fn_0800b910 - mass-storage handler: calls fn_0800a9ec; on success answers with
@ fn_0800bb1c(0, 1), on failure with the 0x3A pair and fn_0800bb1c(1, 1).
@ No parameters, no return value. Entered only by the tail jump b.w at 0x080084C4
@ (from 0x08008378); it returns to the caller of 0x08008378.
@ fn_0800a9ec writes word 0x200003B4 = 0x2E and word 0x200003B0 = 0x800 and returns 0
@ on its only path.
@ Result non-zero: store_two_bytes(2, 0x3A); fn_0800bb1c(1, 1); tail jump to
@ fn_080081c8(0).
@ Result zero: tail jump to fn_0800bb1c(0, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b910,"ax",%progbits
	.p2align 2
	.global fn_0800b910
	.thumb_func
	.type fn_0800b910, %function
fn_0800b910:
	push	{r4, lr}
	bl	fn_0800a9ec
	cbz	r0, .L0800b932
	movs	r1, #0x3a
	movs	r0, #0x2
	bl	store_two_bytes
	movs	r1, #0x1
	mov	r0, r1
	bl	fn_0800bb1c
	pop.w	{r4, lr}
	movs	r0, #0x0
	b.w	fn_080081c8
.L0800b932:
	movs	r1, #0x1
	pop.w	{r4, lr}
	movs	r0, #0x0
	b.w	fn_0800bb1c
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0800b940 - decides between the idle answer and the error answer from the
@ state at 0x200066B4. No parameters, no return value (ends with a tail call of
@ fn_0800bb1c). Entered by the b.w at 0x080084E4 in 0x08008378.
@ r0 = 0x200066B4; r1 = word 0x200066BC ([r0, #8]). If r1 is non-zero, or bit 2 of
@ byte 0x200066C4 ([r0, #0x10]) is set, goes to the error path.
@ Both clear: r1 = 1, r0 = 0, then pop r4/lr and tail-call fn_0800bb1c(0, 1).
@ Error path: fn_080081c8(2), store_two_bytes(5, 0x24), then r1 = 0, r0 = 1 and
@ tail-call fn_0800bb1c(1, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b940,"ax",%progbits
	.p2align 2
	.global fn_0800b940
	.thumb_func
	.type fn_0800b940, %function
fn_0800b940:
	ldr	r0, .L0800b970		@ r0 = 0x200066B4
	push	{r4, lr}
	ldr	r1, [r0, #0x8]
	cbnz	r1, .L0800b954
	ldrb	r0, [r0, #0x10]
	lsls	r0, r0, #0x1d		@ bit 2 of the byte to the sign
	bmi.n	.L0800b954
	movs	r1, #0x1
	movs	r0, #0x0
	b.n	.L0800b966
.L0800b954:
	movs	r0, #0x2
	bl	fn_080081c8
	movs	r1, #0x24
	movs	r0, #0x5
	bl	store_two_bytes
	movs	r1, #0x0
	movs	r0, #0x1
.L0800b966:
	pop.w	{r4, lr}
	b.w	fn_0800bb1c
	.short	0x0000			@ padding
.L0800b970:
	.word	0x200066b4

@ ----------------------------------------------------------------------------
@ fn_0800b974 - state machine on byte 0x20000438 for a two-argument command.
@ r0 = first value, r1 = second value. Returns what the tail target returns, or r0
@ unchanged from entry when byte 0x20000438 is neither 0 nor 1. Tail-called function
@ (formerly merged into 0x08008D10), entered by the b.w at 0x080084DC and at 0x0800AD26.
@ r4 = 0x20000438, r2 = byte [r4].
@ Byte = 1: tail-calls fn_0801019c(r0, r1) unchanged.
@ Byte other than 0 and 1: returns.
@ Byte = 0: r0 = fn_0800b6dc(0x2A, r0, r1); result 0 returns. Otherwise, when bit 7 of
@ byte 0x200066C0 ([0x200066B4 + 0xC]) is clear: stores 1 to byte 0x20000438 and
@ tail-calls fn_0800b9ec(2, 0x3000). When bit 7 is set: fn_080081c8(0),
@ store_two_bytes(5, 0x24), tail-calls fn_0800bb1c(1, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b974,"ax",%progbits
	.p2align 2
	.global fn_0800b974
	.thumb_func
	.type fn_0800b974, %function
fn_0800b974:
	push	{r4, lr}
	ldr	r4, .L0800b9cc		@ r4 = 0x20000438
	ldrb	r2, [r4, #0x0]
	cbz	r2, .L0800b988
	cmp	r2, #0x1
	bne.n	.L0800b9ca
	pop.w	{r4, lr}
	b.w	fn_0801019c
.L0800b988:
	mov	r2, r1
	mov	r1, r0
	movs	r0, #0x2a
	bl	fn_0800b6dc
	cmp	r0, #0x0
	beq.n	.L0800b9ca
	ldr	r0, .L0800b9d0		@ r0 = 0x200066B4
	ldrb	r0, [r0, #0xc]
	lsls	r0, r0, #0x18		@ bit 7 to the sign
	bmi.n	.L0800b9b0
	movs	r0, #0x1
	strb	r0, [r4, #0x0]
	pop.w	{r4, lr}
	mov.w	r1, #0x3000
	movs	r0, #0x2
	b.w	fn_0800b9ec
.L0800b9b0:
	movs	r0, #0x0
	bl	fn_080081c8
	movs	r1, #0x24
	movs	r0, #0x5
	bl	store_two_bytes
	movs	r1, #0x0
	pop.w	{r4, lr}
	movs	r0, #0x1
	b.w	fn_0800bb1c
.L0800b9ca:
	pop	{r4, pc}
.L0800b9cc:
	.word	0x20000438
.L0800b9d0:
	.word	0x200066b4

@ ----------------------------------------------------------------------------
@ fn_0800b9ec - rewrites one endpoint register from a flag word.
@ r0 = index n, r1 = flags. Reads USB_EPn (0x40005C00 + n*4) = word, masks it with
@ 0xBF8F (clears bit 14 DATTOG_RX and bits 6:4 DATTOG_TX / STS_TX), toggles 0x1000
@ when bit 12 of r1 is set and 0x2000 when bit 13 of r1 is set (STS_RX bits), ORs
@ 0x8080 (CTRS_RX and CTRS_TX bits) and writes the word back. No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b9ec,"ax",%progbits
	.p2align 2
	.global fn_0800b9ec
	.thumb_func
	.type fn_0800b9ec, %function
fn_0800b9ec:
	lsls	r2, r0, #0x2
	ldr	r0, .L0800ba18		@ r0 = 0x40005000
	add	r2, r0
	ldr.w	r0, [r2, #0xc00]	@ USB_EPn
	movw	r3, #0xbf8f
	ands	r0, r3
	lsls	r3, r1, #0x13		@ bit 12 of r1 to the sign
	bpl.n	.L0800ba04
	eor.w	r0, r0, #0x1000
.L0800ba04:
	lsls	r1, r1, #0x12		@ bit 13 of r1 to the sign
	bpl.n	.L0800ba0c
	eor.w	r0, r0, #0x2000
.L0800ba0c:
	movw	r1, #0x8080
	orrs	r0, r1
	str.w	r0, [r2, #0xc00]	@ write USB_EPn
	bx	lr
.L0800ba18:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_0800ba1c - like fn_0800b9ec for the low status bits of an endpoint register.
@ r0 = index n, r1 = flags. Reads USB_EPn (0x40005C00 + n*4), masks it with 0x8FBF
@ (clears bits 14:12 and bit 6), toggles 0x10 when bit 4 of r1 is set and 0x20 when
@ bit 5 of r1 is set (STS_TX bits), ORs 0x8080 and writes the word back. No return
@ value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ba1c,"ax",%progbits
	.p2align 2
	.global fn_0800ba1c
	.thumb_func
	.type fn_0800ba1c, %function
fn_0800ba1c:
	lsls	r2, r0, #0x2
	ldr	r0, .L0800ba48		@ r0 = 0x40005000
	add	r2, r0
	ldr.w	r0, [r2, #0xc00]	@ USB_EPn
	movw	r3, #0x8fbf
	ands	r0, r3
	lsls	r3, r1, #0x1b		@ bit 4 of r1 to the sign
	bpl.n	.L0800ba34
	eor.w	r0, r0, #0x10
.L0800ba34:
	lsls	r1, r1, #0x1a		@ bit 5 of r1 to the sign
	bpl.n	.L0800ba3c
	eor.w	r0, r0, #0x20
.L0800ba3c:
	movw	r1, #0x8080
	orrs	r0, r1
	str.w	r0, [r2, #0xc00]	@ write USB_EPn
	bx	lr
.L0800ba48:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_0800bb1c - builds the 13-byte status block at 0x200066D4 and sends it on endpoint 0x81.
@ r0 = byte value, r1 = flag. Stores 0x53425355 to word 0x200066D4 (the bytes
@ 55 53 42 53) and r0 to byte 0x200066E0, calls fn_08010130(0x81, 0x200066D4, 0xD),
@ stores 5 to byte 0x20000438. When r1 is non-zero, stores 4 to byte 0x20000438 and
@ tail-calls fn_0800ba1c(1, 0x30). No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800bb1c,"ax",%progbits
	.p2align 2
	.global fn_0800bb1c
	.thumb_func
	.type fn_0800bb1c, %function
fn_0800bb1c:
	push	{r4, lr}
	mov	r4, r1
	ldr	r1, .L0800bb50		@ r1 = 0x200066D4
	ldr	r2, .L0800bb4c		@ r2 = 0x53425355
	str	r2, [r1, #0x0]
	strb	r0, [r1, #0xc]
	movs	r2, #0xd
	movs	r0, #0x81
	bl	fn_08010130
	ldr	r0, .L0800bb54		@ r0 = 0x20000438
	movs	r1, #0x5
	cmp	r4, #0x0
	strb	r1, [r0, #0x0]
	beq.n	.L0800bb4a
	movs	r1, #0x4
	strb	r1, [r0, #0x0]
	movs	r1, #0x30
	pop.w	{r4, lr}
	movs	r0, #0x1
	b.w	fn_0800ba1c
.L0800bb4a:
	pop	{r4, pc}
.L0800bb4c:
	.word	0x53425355
.L0800bb50:
	.word	0x200066d4
.L0800bb54:
	.word	0x20000438

@ ----------------------------------------------------------------------------
@ store_two_bytes - stores r0 to byte 0x20000413 and r1 to byte 0x2000041D
@ (base 0x20000411, offsets +2 and +0xC). No return value.
@ ----------------------------------------------------------------------------
	.section .text.store_two_bytes,"ax",%progbits
	.p2align 2
	.global store_two_bytes
	.thumb_func
	.type store_two_bytes, %function
store_two_bytes:
	ldr	r2, .L0800bb60		@ r2 = 0x20000411
	strb	r0, [r2, #0x2]
	strb	r1, [r2, #0xc]
	bx	lr
.L0800bb60:
	.word	0x20000411

@ ----------------------------------------------------------------------------
@ fn_0800becc - handler of a request that names an endpoint, for the request
@ structure whose address is in word 0x200002BC.
@ No parameters; returns 0 or 2 (r0). Request type = byte 0 of the structure & 0x7F.
@ Type 0: clears bit 5 of byte 9 and returns 0.
@ Type 2 with the halfword at offset 2 = 0 and byte 4 = 0: endpoint number
@ n = byte 5 & 0x7F, bit 7 of byte 5 selects the direction; reads USB_EPn
@ (0x40005C00 + n*4) masked with 0x30 (bit 7 set, STS_TX) or 0x3000 (STS_RX). When n
@ is below byte 0x20000330, that field is non-zero and byte 10 is non-zero:
@  - bit 7 set: when STS_TX == 1 calls fn_0800fb7c(n) and fn_0800ba1c(n, 0x30);
@  - bit 7 clear: when STS_RX == 1: for n = 0 calls fn_08010050(0, byte [0x20000348 +
@    0x2C]) and rewrites USB_EP0 as ((word & 0xBF8F) ^ 0x3000) | 0x8080; for n != 0
@    calls fn_0800fb54(n) and rewrites USB_EPn the same way;
@  then calls the function at [[0x200002C4] + 0x14] and returns 0.
@ Any other case returns 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800becc,"ax",%progbits
	.p2align 2
	.global fn_0800becc
	.thumb_func
	.type fn_0800becc, %function
fn_0800becc:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r0, .L0800bfb4		@ r0 = 0x200002BC
	ldr	r0, [r0, #0x0]
	ldrb	r1, [r0, #0x0]
	ands.w	r1, r1, #0x7f
	beq.n	.L0800bee2
	cmp	r1, #0x2
	beq.n	.L0800beec
	b.n	.L0800bfb0
.L0800bee2:
	ldrb	r1, [r0, #0x9]
	and.w	r1, r1, #0xdf		@ clear bit 5 of byte 9
	strb	r1, [r0, #0x9]
	b.n	.L0800bf8a
.L0800beec:
	ldrh	r1, [r0, #0x2]
	cmp	r1, #0x0
	bne.n	.L0800bfb0
	ldrb	r1, [r0, #0x4]
	cbnz	r1, .L0800bf74
	ldrb	r1, [r0, #0x5]
	ldr	r5, .L0800bfbc		@ r5 = 0x40005000
	bic.w	r4, r1, #0x80		@ r4 = endpoint number
	lsls	r2, r1, #0x18		@ bit 7 to the sign
	add.w	r2, r5, r4, lsl #0x2
	ldr	r3, .L0800bfb8		@ r3 = 0x20000330
	ldr.w	r2, [r2, #0xc00]	@ USB_EPn
	bpl.n	.L0800bf14
	ubfx	r2, r2, #0x4, #0x2	@ STS_TX
	lsls	r2, r2, #0x4
	b.n	.L0800bf1a
.L0800bf14:
	ubfx	r2, r2, #0xc, #0x2	@ STS_RX
	lsls	r2, r2, #0xc
.L0800bf1a:
	ldrb	r6, [r3, #0x0]
	mov	r3, r4
	cmp	r6, r4
	bls.n	.L0800bfb0
	cbz	r2, .L0800bf74
	ldrb	r0, [r0, #0xa]
	cbz	r0, .L0800bf74
	lsls	r0, r1, #0x18
	lsl.w	r0, r4, #0x2
	bpl.n	.L0800bf4e
	add	r0, r5
	ldr.w	r0, [r0, #0xc00]
	ubfx	r0, r0, #0x4, #0x2
	cmp	r0, #0x1
	bne.n	.L0800bf82
	mov	r0, r3
	bl	fn_0800fb7c
	mov	r0, r4
	movs	r1, #0x30
	bl	fn_0800ba1c
	b.n	.L0800bf82
.L0800bf4e:
	adds	r6, r0, r5
	ldr.w	r0, [r6, #0xc00]
	ubfx	r0, r0, #0xc, #0x2
	cmp	r0, #0x1
	bne.n	.L0800bf82
	movw	r7, #0xbf8f
	movw	r8, #0x8080
	cbz	r4, .L0800bf90
	mov	r0, r3
	bl	fn_0800fb54
	ldr.w	r0, [r6, #0xc00]
	ands	r0, r7
	b.n	.L0800bf76
.L0800bf74:
	b.n	.L0800bfb0
.L0800bf76:
	eor.w	r0, r0, #0x3000
	orr.w	r0, r0, r8
	str.w	r0, [r6, #0xc00]
.L0800bf82:
	ldr	r0, .L0800bfc0		@ r0 = 0x200002C4
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0x14]
	blx	r0
.L0800bf8a:
	movs	r0, #0x0
.L0800bf8c:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0800bf90:
	ldr	r0, .L0800bfc4		@ r0 = 0x20000348
	ldrb.w	r1, [r0, #0x2c]
	movs	r0, #0x0
	bl	fn_08010050
	ldr.w	r0, [r5, #0xc00]	@ USB_EP0
	ands	r0, r7
	eor.w	r0, r0, #0x3000
	orr.w	r0, r0, r8
	str.w	r0, [r5, #0xc00]
	b.n	.L0800bf82
.L0800bfb0:
	movs	r0, #0x2
	b.n	.L0800bf8c
.L0800bfb4:
	.word	0x200002bc
.L0800bfb8:
	.word	0x20000330
.L0800bfbc:
	.word	0x40005000
.L0800bfc0:
	.word	0x200002c4
.L0800bfc4:
	.word	0x20000348

@ ----------------------------------------------------------------------------
@ fn_0800bfc8 - request handler with a flag in r0.
@ r0 = flag; returns 0 or a pointer.
@ r0 = 0: stores halfword 1 at offset 0x10 of the structure whose address is in word
@ 0x200002BC and returns 0.
@ Otherwise calls the function at [[0x200002C4] + 0] and returns (word 0x200002BC) + 10.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800bfc8,"ax",%progbits
	.p2align 2
	.global fn_0800bfc8
	.thumb_func
	.type fn_0800bfc8, %function
fn_0800bfc8:
	push	{r4, lr}
	ldr	r4, .L0800bfe8		@ r4 = 0x200002BC
	cbz	r0, .L0800bfdc
	ldr	r0, .L0800bfec		@ r0 = 0x200002C4
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0x0]
	blx	r0
	ldr	r0, [r4, #0x0]
	adds	r0, #0xa
	pop	{r4, pc}
.L0800bfdc:
	ldr	r1, [r4, #0x0]
	movs	r0, #0x1
	strh	r0, [r1, #0x10]
	movs	r0, #0x0
	pop	{r4, pc}
	.short	0x0000			@ padding
.L0800bfe8:
	.word	0x200002bc
.L0800bfec:
	.word	0x200002c4

@ ----------------------------------------------------------------------------
@ fn_0800bff0 - request handler with a flag in r0 and a pointer to two words in r1.
@ r0 = flag, r1 = pointer; returns 0 or an address.
@ r0 = 0: stores (low 16 bits of word 1 of [r1]) - (halfword at offset 0x12 of the
@ structure whose address is in word 0x200002BC) to the halfword at offset 0x10 and
@ returns 0.
@ Otherwise returns word 0 of [r1] + the halfword at offset 0x12.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800bff0,"ax",%progbits
	.p2align 2
	.global fn_0800bff0
	.thumb_func
	.type fn_0800bff0, %function
fn_0800bff0:
	ldr	r2, .L0800c008		@ r2 = 0x200002BC
	ldr	r3, [r2, #0x0]
	ldrh	r2, [r3, #0x12]
	cbz	r0, .L0800bffe
	ldr	r0, [r1, #0x0]
	add	r0, r2
	bx	lr
.L0800bffe:
	ldrh	r0, [r1, #0x4]
	subs	r0, r0, r2
	strh	r0, [r3, #0x10]
	movs	r0, #0x0
	bx	lr
.L0800c008:
	.word	0x200002bc

@ ----------------------------------------------------------------------------
@ fn_0800c00c - request handler with a flag in r0.
@ r0 = flag; returns 0 or a pointer.
@ r0 = 0: stores halfword 1 at offset 0x10 of the structure whose address is in word
@ 0x200002BC and returns 0.
@ Otherwise calls the function at [[0x200002C4] + 8] and returns (word 0x200002BC) + 0xC.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c00c,"ax",%progbits
	.p2align 2
	.global fn_0800c00c
	.thumb_func
	.type fn_0800c00c, %function
fn_0800c00c:
	push	{r4, lr}
	ldr	r4, .L0800c02c		@ r4 = 0x200002BC
	cbz	r0, .L0800c020
	ldr	r0, .L0800c030		@ r0 = 0x200002C4
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0x8]
	blx	r0
	ldr	r0, [r4, #0x0]
	adds	r0, #0xc
	pop	{r4, pc}
.L0800c020:
	ldr	r1, [r4, #0x0]
	movs	r0, #0x1
	strh	r0, [r1, #0x10]
	movs	r0, #0x0
	pop	{r4, pc}
	.short	0x0000			@ padding
.L0800c02c:
	.word	0x200002bc
.L0800c030:
	.word	0x200002c4

@ ----------------------------------------------------------------------------
@ fn_0800c034 - builds the two-byte answer at 0x200002B6 from the request structure.
@ r0 = flag; returns 0 or the pointer 0x200002B6.
@ r0 = 0: stores halfword 2 at offset 0x10 of the structure whose address is in word
@ 0x200002BC and returns 0.
@ Otherwise clears halfword 0x200002B6, then by type (byte 0 & 0x7F):
@  type 0: bit 1 of byte 0x200002B6 = bit 5 of byte 9, bit 0 = bit 6 of byte 9
@          (value 0..3), then calls the function at [[0x200002C4] + 0x10] and
@          returns 0x200002B6;
@  type 1: returns 0x200002B6 without a call;
@  type 2: reads USB_EPn with n = byte 5 & 0xF, status field STS_TX (bits 5:4) when
@          bit 7 of byte 5 is set, STS_RX (bits 13:12) otherwise; status 1 sets
@          bit 0 of byte 0x200002B6; then calls the function at [[0x200002C4] + 0x10]
@          and returns 0x200002B6;
@  types above 2: returns 0 without a call.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c034,"ax",%progbits
	.p2align 2
	.global fn_0800c034
	.thumb_func
	.type fn_0800c034, %function
fn_0800c034:
	ldr	r1, .L0800c0b8		@ r1 = 0x200002BC
	push	{r4, lr}
	ldr	r1, [r1, #0x0]
	cbz	r0, .L0800c056
	ldr	r0, .L0800c0bc		@ r0 = 0x200002B6
	movs	r2, #0x0
	strh	r2, [r0, #0x0]
	ldrb	r2, [r1, #0x0]
	lsls	r3, r2, #0x19
	beq.n	.L0800c05e
	and.w	r2, r2, #0x7f
	cmp	r2, #0x1
	beq.n	.L0800c07e
	cmp	r2, #0x2
	beq.n	.L0800c082
	b.n	.L0800c05a
.L0800c056:
	movs	r0, #0x2
	strh	r0, [r1, #0x10]
.L0800c05a:
	movs	r0, #0x0
	pop	{r4, pc}
.L0800c05e:
	ldrb	r1, [r1, #0x9]
	lsls	r2, r1, #0x1a		@ bit 5 of byte 9 to the sign
	ldrb	r2, [r0, #0x0]
	bpl.n	.L0800c06c
	orr.w	r2, r2, #0x2
	b.n	.L0800c070
.L0800c06c:
	and.w	r2, r2, #0xfd
.L0800c070:
	lsls	r1, r1, #0x19		@ bit 6 of byte 9 to the sign
	strb	r2, [r0, #0x0]
	uxtb	r1, r2
	bmi.n	.L0800c09c
	and.w	r1, r1, #0xfe
	b.n	.L0800c0a0
.L0800c07e:
	ldr	r0, .L0800c0bc		@ r0 = 0x200002B6
	pop	{r4, pc}
.L0800c082:
	ldrb	r2, [r1, #0x5]
	lsls	r1, r2, #0x1c
	lsls	r3, r2, #0x18		@ bit 7 of byte 5 to the sign
	ldr	r2, .L0800c0c0		@ r2 = 0x40005000
	add.w	r1, r2, r1, lsr #0x1a	@ r2 + (byte 5 & 0xF) * 4
	ldr.w	r1, [r1, #0xc00]	@ USB_EPn
	bpl.n	.L0800c0a4
	ubfx	r1, r1, #0x4, #0x2	@ STS_TX
	b.n	.L0800c0a8
.L0800c09a:
	ldrb	r1, [r0, #0x0]
.L0800c09c:
	orr.w	r1, r1, #0x1
.L0800c0a0:
	strb	r1, [r0, #0x0]
	b.n	.L0800c0ac
.L0800c0a4:
	ubfx	r1, r1, #0xc, #0x2	@ STS_RX
.L0800c0a8:
	cmp	r1, #0x1
	beq.n	.L0800c09a
.L0800c0ac:
	ldr	r0, .L0800c0c4		@ r0 = 0x200002C4
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0x10]
	blx	r0
	b.n	.L0800c07e
	.short	0x0000			@ padding
.L0800c0b8:
	.word	0x200002bc
.L0800c0bc:
	.word	0x200002b6
.L0800c0c0:
	.word	0x40005000
.L0800c0c4:
	.word	0x200002c4

@ ----------------------------------------------------------------------------
@ fn_0800c0c8 - stores a value from the request structure and calls a handler.
@ No parameters; returns 0 or 2.
@ Structure = the one whose address is in word 0x200002BC. Returns 2 when byte 3 is
@ above byte 0x20000331 (0x20000330 + 1), or byte 2 is non-zero, or the halfword at
@ offset 4 is non-zero. Otherwise copies byte 3 to byte 10, calls the function at
@ [[0x200002C4] + 4] and returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c0c8,"ax",%progbits
	.p2align 2
	.global fn_0800c0c8
	.thumb_func
	.type fn_0800c0c8, %function
fn_0800c0c8:
	ldr	r0, .L0800c0f4		@ r0 = 0x200002BC
	push	{r4, lr}
	ldr	r0, [r0, #0x0]
	ldr	r2, .L0800c0f8		@ r2 = 0x20000330
	ldrb	r1, [r0, #0x3]
	ldrb	r2, [r2, #0x1]
	cmp	r1, r2
	bhi.n	.L0800c0e0
	ldrb	r2, [r0, #0x2]
	cbnz	r2, .L0800c0e0
	ldrh	r2, [r0, #0x4]
	cbz	r2, .L0800c0e4
.L0800c0e0:
	movs	r0, #0x2
	pop	{r4, pc}
.L0800c0e4:
	strb	r1, [r0, #0xa]
	ldr	r0, .L0800c0fc		@ r0 = 0x200002C4
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0x4]
	blx	r0
	movs	r0, #0x0
	pop	{r4, pc}
	.short	0x0000			@ padding
.L0800c0f4:
	.word	0x200002bc
.L0800c0f8:
	.word	0x20000330
.L0800c0fc:
	.word	0x200002c4

@ ----------------------------------------------------------------------------
@ fn_0800c100 - sets bit 5 of byte 9 of the request structure and calls a handler.
@ No parameters; returns 0. Sets bit 0x20 in byte 9 of the structure whose address is
@ in word 0x200002BC and calls the function at [[0x200002C4] + 0x1C].
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c100,"ax",%progbits
	.p2align 2
	.global fn_0800c100
	.thumb_func
	.type fn_0800c100, %function
fn_0800c100:
	ldr	r0, .L0800c11c		@ r0 = 0x200002BC
	push	{r4, lr}
	ldr	r0, [r0, #0x0]
	ldrb	r1, [r0, #0x9]
	orr.w	r1, r1, #0x20
	strb	r1, [r0, #0x9]
	ldr	r0, .L0800c120		@ r0 = 0x200002C4
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0x1c]
	blx	r0
	movs	r0, #0x0
	pop	{r4, pc}
	.short	0x0000			@ padding
.L0800c11c:
	.word	0x200002bc
.L0800c120:
	.word	0x200002c4

@ ----------------------------------------------------------------------------
@ fn_0800c124 - toggles the status of the endpoint named in byte 5 of the request.
@ No parameters; returns 0 or 2.
@ n = byte 5 & 0x7F of the structure whose address is in word 0x200002BC; bit 7 of
@ byte 5 selects the status mask of USB_EPn (0x40005C00 + n*4): 0x30 (STS_TX) when set,
@ 0x3000 (STS_RX) when clear. Returns 2 when n is not below byte 0x20000330, the
@ halfword at offset 2 is non-zero, the masked field is 0, or byte 10 is 0.
@ Otherwise writes ((word & 0x8FBF) ^ 0x10) | 0x8080 (bit 7 set) or
@ ((word & 0xBF8F) ^ 0x1000) | 0x8080 (bit 7 clear) to USB_EPn, calls the function at
@ [[0x200002C4] + 0x18] and returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c124,"ax",%progbits
	.p2align 2
	.global fn_0800c124
	.thumb_func
	.type fn_0800c124, %function
fn_0800c124:
	push	{r4, r5, r6, lr}
	ldr	r0, .L0800c19c		@ r0 = 0x200002BC
	ldr	r5, .L0800c1a0		@ r5 = 0x40005000
	ldr	r3, [r0, #0x0]
	ldrb	r1, [r3, #0x5]
	bic.w	r0, r1, #0x80
	add.w	r0, r5, r0, lsl #0x2
	lsls	r4, r1, #0x18		@ bit 7 to the sign
	ldr.w	r4, [r0, #0xc00]	@ USB_EPn
	bic.w	r2, r1, #0x80
	bpl.n	.L0800c14a
	ubfx	r4, r4, #0x4, #0x2	@ STS_TX
	lsls	r4, r4, #0x4
	b.n	.L0800c150
.L0800c14a:
	ubfx	r4, r4, #0xc, #0x2	@ STS_RX
	lsls	r4, r4, #0xc
.L0800c150:
	ldr	r5, .L0800c1a4		@ r5 = 0x20000330
	ldrb	r5, [r5, #0x0]
	cmp	r5, r2
	bls.n	.L0800c17a
	ldrh	r2, [r3, #0x2]
	cbnz	r2, .L0800c17a
	cbz	r4, .L0800c17a
	ldrb	r2, [r3, #0xa]
	cbz	r2, .L0800c17a
	lsls	r1, r1, #0x18
	ldr.w	r1, [r0, #0xc00]
	movw	r2, #0x8080
	bpl.n	.L0800c17e
	movw	r3, #0x8fbf
	ands	r1, r3
	eor.w	r1, r1, #0x10
	b.n	.L0800c188
.L0800c17a:
	movs	r0, #0x2
	pop	{r4, r5, r6, pc}
.L0800c17e:
	movw	r3, #0xbf8f
	ands	r1, r3
	eor.w	r1, r1, #0x1000
.L0800c188:
	orrs	r1, r2
	str.w	r1, [r0, #0xc00]	@ write USB_EPn
	ldr	r0, .L0800c1a8		@ r0 = 0x200002C4
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0x18]
	blx	r0
	movs	r0, #0x0
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L0800c19c:
	.word	0x200002bc
.L0800c1a0:
	.word	0x40005000
.L0800c1a4:
	.word	0x20000330
.L0800c1a8:
	.word	0x200002c4

@ ----------------------------------------------------------------------------
@ fn_0800c1ac - handler that validates a request with the function at
@ [[0x200002C0] + 0x18] and then calls the function at [[0x200002C4] + 0xC].
@ No parameters; returns 0 or 2.
@ Calls the function at [[0x200002C0] + 0x18] with r0 = byte 5 and r1 = byte 3 of the
@ structure whose address is in word 0x200002BC. Returns 2 when byte 10 is 0, the
@ call result is non-zero, byte 4 is non-zero, or byte 2 is non-zero. Otherwise calls
@ the function at [[0x200002C4] + 0xC], copies byte 5 to offset 0xB and byte 3 to
@ offset 0xC, and returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c1ac,"ax",%progbits
	.p2align 2
	.global fn_0800c1ac
	.thumb_func
	.type fn_0800c1ac, %function
fn_0800c1ac:
	push	{r4, lr}
	ldr	r4, .L0800c1e8		@ r4 = 0x200002BC
	ldr	r2, .L0800c1ec		@ r2 = 0x200002C0
	ldr	r0, [r4, #0x0]
	ldr	r2, [r2, #0x0]
	ldrb	r1, [r0, #0x3]
	ldr	r2, [r2, #0x18]
	ldrb	r0, [r0, #0x5]
	blx	r2
	ldr	r1, [r4, #0x0]
	ldrb	r2, [r1, #0xa]
	cbz	r2, .L0800c1ce
	cbnz	r0, .L0800c1ce
	ldrb	r0, [r1, #0x4]
	cbnz	r0, .L0800c1ce
	ldrb	r0, [r1, #0x2]
	cbz	r0, .L0800c1d2
.L0800c1ce:
	movs	r0, #0x2
	pop	{r4, pc}
.L0800c1d2:
	ldr	r0, .L0800c1f0		@ r0 = 0x200002C4
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0xc]
	blx	r0
	ldr	r0, [r4, #0x0]
	ldrb	r1, [r0, #0x5]
	strb	r1, [r0, #0xb]
	ldrb	r1, [r0, #0x3]
	strb	r1, [r0, #0xc]
	movs	r0, #0x0
	pop	{r4, pc}
.L0800c1e8:
	.word	0x200002bc
.L0800c1ec:
	.word	0x200002c0
.L0800c1f0:
	.word	0x200002c4

@ ----------------------------------------------------------------------------
@ fn_0800c1f4 - resets the USB module and restores the endpoint registers.
@ No parameters, no return value.
@ Saves the low 16 bits of USB_EP0..USB_EP7 (0x40005C00 + i*4) to 0x20005E54 + i*4.
@ Takes USB_CTRL (0x40005C40) low 16 bits, writes it with 0x400 (RSTM), then also
@ with bit 0 (FRST) set, then with bit 0 cleared. Waits until bit 10 (RST) of USB_STS
@ (0x40005C44) is set, writes 0xFBFF to USB_STS (clears RST). Copies the saved eight
@ values back to USB_EP0..USB_EP7 (low 16 bits), then writes USB_CTRL = value | 8
@ (FSUSPD), then USB_CTRL = (low 16 bits of USB_CTRL) | 4 (LP_MODE).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c1f4,"ax",%progbits
	.p2align 2
	.global fn_0800c1f4
	.thumb_func
	.type fn_0800c1f4, %function
fn_0800c1f4:
	push	{r4, r5, r6, lr}
	ldr	r1, .L0800c264		@ r1 = 0x40005C40 (USB_CTRL)
	movs	r0, #0x0
	ldr	r2, [r1, #0x0]
	ldr	r3, .L0800c268		@ r3 = 0x40005000
	uxth	r4, r2
	ldr	r2, .L0800c26c		@ r2 = 0x20005E54 (saved copies)
	nop
.L0800c204:
	add.w	r5, r3, r0, lsl #0x2
	ldr.w	r5, [r5, #0xc00]	@ USB_EPi
	uxth	r5, r5
	str.w	r5, [r2, r0, lsl #0x2]
	.inst.n	0x1c40			@ adds r0, r0, #1
	cmp	r0, #0x8
	bcc.n	.L0800c204
	orr.w	r0, r4, #0x400
	str	r0, [r1, #0x0]
	orr.w	r0, r0, #0x1
	str	r0, [r1, #0x0]
	bic.w	r4, r0, #0x1
	str	r4, [r1, #0x0]
	ldr	r0, .L0800c264		@ r0 = 0x40005C40
	.inst.n	0x1d00			@ adds r0, r0, #4 (r0 = 0x40005C44, USB_STS)
.L0800c22e:
	ldr	r5, [r0, #0x0]
	lsls	r5, r5, #0x15		@ bit 10 (RST) to the sign
	bpl.n	.L0800c22e
	movw	r5, #0xfbff
	str	r5, [r0, #0x0]
	movs	r0, #0x0
.L0800c23c:
	ldr.w	r5, [r2, r0, lsl #0x2]
	add.w	r6, r3, r0, lsl #0x2
	uxth	r5, r5
	str.w	r5, [r6, #0xc00]	@ USB_EPi
	.inst.n	0x1c40			@ adds r0, r0, #1
	cmp	r0, #0x8
	bcc.n	.L0800c23c
	orr.w	r0, r4, #0x8
	str	r0, [r1, #0x0]
	ldr	r0, [r1, #0x0]
	uxth	r0, r0
	orr.w	r0, r0, #0x4
	str	r0, [r1, #0x0]
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L0800c264:
	.word	0x40005c40
.L0800c268:
	.word	0x40005000
.L0800c26c:
	.word	0x20005e54

@ ----------------------------------------------------------------------------
@ fn_0800c6f0 - starts a transmit on endpoint 0x81 and updates the transfer state.
@ r0 = pointer, r1 = length; no return value.
@ Calls fn_08010130(0x81, pointer, length), then fn_0800ba1c(1, 0x30), stores 3 in
@ byte 0x20000438, subtracts the length from word 0x200066DC ([0x200066D4 + 8]) and
@ stores 0 in byte 0x200066E0 ([0x200066D4 + 0xC]). Entered by the b.w instructions at
@ 0x0800B77C, 0x0800B7C0, 0x0800B7CC, 0x0800B884, 0x0800B8DE and 0x0800B8FC.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c6f0,"ax",%progbits
	.p2align 2
	.global fn_0800c6f0
	.thumb_func
	.type fn_0800c6f0, %function
fn_0800c6f0:
	push	{r4, lr}
	mov	r4, r1
	mov	r2, r1
	mov	r1, r0
	movs	r0, #0x81
	bl	fn_08010130
	movs	r1, #0x30
	movs	r0, #0x1
	bl	fn_0800ba1c
	ldr	r1, .L0800c71c		@ r1 = 0x20000438
	movs	r0, #0x3
	strb	r0, [r1, #0x0]
	ldr	r0, .L0800c720		@ r0 = 0x200066D4
	ldr	r1, [r0, #0x8]
	subs	r1, r1, r4
	str	r1, [r0, #0x8]
	movs	r1, #0x0
	strb	r1, [r0, #0xc]
	pop	{r4, pc}
	.short	0x0000			@ padding
.L0800c71c:
	.word	0x20000438
.L0800c720:
	.word	0x200066d4

@ ----------------------------------------------------------------------------
@ swap_bytes_16 - swaps the two low bytes of a value.
@ r0 = value; returns (r0 >> 8) | ((r0 & 0xFF) << 8) in r0.
@ ----------------------------------------------------------------------------
	.section .text.swap_bytes_16,"ax",%progbits
	.p2align 2
	.global swap_bytes_16
	.thumb_func
	.type swap_bytes_16, %function
swap_bytes_16:
	uxtb	r1, r0
	lsrs	r0, r0, #0x8
	orr.w	r0, r0, r1, lsl #0x8
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0800fb54 - rewrites an endpoint register when its bit 14 is set.
@ r0 = index n; no return value. When bit 14 (DATTOG_RX) of USB_EPn
@ (0x40005C00 + n*4) is set, writes (word & 0x8F8F) | 0xC080 back to USB_EPn.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fb54,"ax",%progbits
	.p2align 2
	.global fn_0800fb54
	.thumb_func
	.type fn_0800fb54, %function
fn_0800fb54:
	lsls	r1, r0, #0x2
	ldr	r0, .L0800fb78		@ r0 = 0x40005000
	add	r0, r1
	ldr.w	r1, [r0, #0xc00]	@ USB_EPn
	lsls	r1, r1, #0x11		@ bit 14 to the sign
	bpl.n	.L0800fb76
	ldr.w	r1, [r0, #0xc00]
	movw	r2, #0x8f8f
	ands	r1, r2
	movw	r2, #0xc080
	orrs	r1, r2
	str.w	r1, [r0, #0xc00]
.L0800fb76:
	bx	lr
.L0800fb78:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_0800fb7c - rewrites an endpoint register when its bit 6 is set.
@ r0 = index n; no return value. When bit 6 (DATTOG_TX) of USB_EPn
@ (0x40005C00 + n*4) is set, writes (word & 0x8F8F) | 0x80C0 back to USB_EPn.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fb7c,"ax",%progbits
	.p2align 2
	.global fn_0800fb7c
	.thumb_func
	.type fn_0800fb7c, %function
fn_0800fb7c:
	lsls	r1, r0, #0x2
	ldr	r0, .L0800fba0		@ r0 = 0x40005000
	add	r0, r1
	ldr.w	r1, [r0, #0xc00]	@ USB_EPn
	lsls	r1, r1, #0x19		@ bit 6 to the sign
	bpl.n	.L0800fb9e
	ldr.w	r1, [r0, #0xc00]
	movw	r2, #0x8f8f
	ands	r1, r2
	movw	r2, #0x80c0
	orrs	r1, r2
	str.w	r1, [r0, #0xc00]
.L0800fb9e:
	bx	lr
.L0800fba0:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_0800fba4 - masks an endpoint register with 0x8E8F and sets 0x8080.
@ r0 = index n; no return value. USB_EPn (0x40005C00 + n*4) =
@ (word & 0x8E8F) | 0x8080.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fba4,"ax",%progbits
	.p2align 2
	.global fn_0800fba4
	.thumb_func
	.type fn_0800fba4, %function
fn_0800fba4:
	lsls	r1, r0, #0x2
	ldr	r0, .L0800fbc0		@ r0 = 0x40005000
	add	r1, r0
	ldr.w	r0, [r1, #0xc00]	@ USB_EPn
	movw	r2, #0x8e8f
	ands	r0, r2
	movw	r2, #0x8080
	orrs	r0, r2
	str.w	r0, [r1, #0xc00]
	bx	lr
.L0800fbc0:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ copy_halfwords_from_40006000 - copies halfwords out of the USB packet memory.
@ r0 = destination, r1 = source offset, r2 = byte count; no return value.
@ Copies (r2 + 1) >> 1 halfwords. Source address = 0x40006000 + r1 * 2, advancing 4
@ bytes per halfword (each halfword occupies a 32-bit slot); the destination
@ advances 2 bytes per halfword. The running destination pointer is stored in
@ word 0x200002D0 after every halfword.
@ ----------------------------------------------------------------------------
	.section .text.copy_halfwords_from_40006000,"ax",%progbits
	.p2align 2
	.global copy_halfwords_from_40006000
	.thumb_func
	.type copy_halfwords_from_40006000, %function
copy_halfwords_from_40006000:
	ldr	r3, .L0800fbe4		@ r3 = 0x40006000
	push	{r4, lr}
	.inst.n	0x1c52			@ adds r2, r2, #1
	lsrs	r2, r2, #0x1
	add.w	r1, r3, r1, lsl #0x1
	beq.n	.L0800fbe2
	ldr	r3, .L0800fbe8		@ r3 = 0x200002D0
.L0800fbd4:
	ldrh.w	r4, [r1], #0x4
	strh.w	r4, [r0], #0x2
	str	r0, [r3, #0x0]
	.inst.n	0x1e52			@ subs r2, r2, #1
	bne.n	.L0800fbd4
.L0800fbe2:
	pop	{r4, pc}
.L0800fbe4:
	.word	0x40006000
.L0800fbe8:
	.word	0x200002d0

@ ----------------------------------------------------------------------------
@ copy_halfwords_to_40006000 - copies bytes into the USB packet memory as halfwords.
@ r0 = source, r1 = destination offset, r2 = byte count; no return value.
@ Copies (r2 + 1) >> 1 halfwords: reads two bytes from r0 (advancing 2 bytes), joins
@ them little-endian and stores the halfword at 0x40006000 + r1 * 2, advancing 4 bytes
@ per halfword. The running source pointer is stored in word 0x200002D4
@ (0x200002D0 + 4) after every halfword.
@ ----------------------------------------------------------------------------
	.section .text.copy_halfwords_to_40006000,"ax",%progbits
	.p2align 2
	.global copy_halfwords_to_40006000
	.thumb_func
	.type copy_halfwords_to_40006000, %function
copy_halfwords_to_40006000:
	push	{r4, r5, lr}
	ldr	r3, .L0800fc14		@ r3 = 0x40006000
	.inst.n	0x1c52			@ adds r2, r2, #1
	lsrs	r2, r2, #0x1
	add.w	r1, r3, r1, lsl #0x1
	beq.n	.L0800fc12
	ldr	r4, .L0800fc18		@ r4 = 0x200002D0
.L0800fbfc:
	ldrb.w	r3, [r0], #0x1
	.inst.n	0x1e52			@ subs r2, r2, #1
	ldrb.w	r5, [r0], #0x1
	orr.w	r3, r3, r5, lsl #0x8
	strh.w	r3, [r1], #0x4
	str	r0, [r4, #0x4]
	bne.n	.L0800fbfc
.L0800fc12:
	pop	{r4, r5, pc}
.L0800fc14:
	.word	0x40006000
.L0800fc18:
	.word	0x200002d0

@ ----------------------------------------------------------------------------
@ fn_0800fc1c - correct-transfer service loop of the USB interrupt.
@ No parameters, no return value.
@ r10 = 0x40005C44 (USB_STS), r5 = 0x40005C00 (USB_EP0), r4 = 0x200002CA,
@ r9 = 0x200002F4, r6 = 0xBFBF, r7 = 0x8080, r8 = 0xF8F, r11 = 0x8F0F.
@ Loop: reads USB_STS into halfword 0x200002F4 and returns when bit 15 (CTRS) is
@ clear. n = value & 0xF is stored in byte 0x200002B8.
@ n non-zero: reads USB_EPn (0x40005C00 + n*4) into a stack halfword. Bit 15 set
@ (CTRS_RX): USB_EPn = word & 0xF8F and calls the function at word 0x20000310 + n*4
@ (read as [0x20000314 + n*4 - 4]). Bit 7 set (CTRS_TX): USB_EPn = word & 0x8F0F
@ and calls the function at word 0x200002F4 + n*4 (read as [0x200002F8 + n*4 - 4]).
@ n = 0: saves bits 0x30 of USB_EP0 to halfword 0x200002CC and bits 0x3000 to halfword
@ 0x200002CA, writes USB_EP0 = ((word & 0xBFBF) ^ 0x2020) | 0x8080. Then: bit 4 of
@ the stored status (DIR) clear: USB_EP0 = word & 0x8F0F and calls fn_0800fe84; else
@ bit 11 (SETUP) of USB_EP0 set: USB_EP0 = word & 0xF8F and calls fn_0800ff70; else
@ bit 15 set: USB_EP0 = word & 0xF8F and calls fn_0800fee4.
@ Afterwards (0x0800FD44) restores the saved bits: USB_EP0 = word & 0xBFBF, toggled
@ by 0x1000 / 0x2000 / 0x10 / 0x20 according to bits 12, 13 of halfword 0x200002CA and
@ bits 4, 5 of halfword 0x200002CC, ORed with 0x8080.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fc1c,"ax",%progbits
	.p2align 2
	.global fn_0800fc1c
	.thumb_func
	.type fn_0800fc1c, %function
fn_0800fc1c:
	push.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	movs	r0, #0x0
	strh.w	r0, [sp, #0x0]
	ldr.w	r10, .L0800fd5c		@ r10 = 0x40005C00
	movw	r6, #0xbfbf
	movw	r7, #0x8080
	ldr	r5, .L0800fd5c		@ r5 = 0x40005C00 (USB_EP0)
	ldr	r4, .L0800fd60		@ r4 = 0x200002CA
	movw	r8, #0xf8f
	movw	r11, #0x8f0f
	ldr.w	r9, .L0800fd64		@ r9 = 0x200002F4
	add.w	r10, r10, #0x44		@ r10 = 0x40005C44 (USB_STS)
	b.n	.L0800fcac
.L0800fc48:
	ldrh	r0, [r1, #0x0]
	ldr	r2, .L0800fd68		@ r2 = 0x200002B8
	ands.w	r0, r0, #0xf
	strb	r0, [r2, #0x0]
	beq.n	.L0800fcbe
	ldr	r1, .L0800fd6c		@ r1 = 0x40005000
	add.w	r1, r1, r0, lsl #0x2
	ldr.w	r2, [r1, #0xc00]	@ USB_EPn
	strh.w	r2, [sp, #0x0]
	ldrh.w	r2, [sp, #0x0]
	lsls	r2, r2, #0x10		@ bit 15 (CTRS_RX) to the sign
	bpl.n	.L0800fc82
	ldr.w	r2, [r1, #0xc00]
	and.w	r2, r2, r8
	str.w	r2, [r1, #0xc00]
	ldr	r1, .L0800fd70		@ r1 = 0x20000314
	add.w	r0, r1, r0, lsl #0x2
	ldr.w	r0, [r0, #-0x4]
	blx	r0
.L0800fc82:
	ldrh.w	r0, [sp, #0x0]
	lsls	r0, r0, #0x18		@ bit 7 (CTRS_TX) to the sign
	bpl.n	.L0800fcac
	ldr	r0, .L0800fd68		@ r0 = 0x200002B8
	ldr	r1, .L0800fd6c		@ r1 = 0x40005000
	ldrb	r0, [r0, #0x0]
	add.w	r1, r1, r0, lsl #0x2
	ldr.w	r2, [r1, #0xc00]
	and.w	r2, r2, r11
	str.w	r2, [r1, #0xc00]
	ldr	r1, .L0800fd74		@ r1 = 0x200002F8
	add.w	r0, r1, r0, lsl #0x2
	ldr.w	r0, [r0, #-0x4]
	blx	r0
.L0800fcac:
	ldr.w	r0, [r10, #0x0]		@ USB_STS
	mov	r1, r9
	strh.w	r0, [r9, #0x0]
	lsls	r0, r0, #0x10		@ bit 15 (CTRS) to the sign
	bmi.n	.L0800fc48
.L0800fcba:
	pop.w	{r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0800fcbe:
	ldr	r0, [r5, #0x0]		@ USB_EP0
	strh	r0, [r4, #0x0]
	ldrh	r0, [r4, #0x0]
	and.w	r0, r0, #0x30
	strh	r0, [r4, #0x2]		@ halfword 0x200002CC = EP0 bits 0x30
	ldrh	r0, [r4, #0x0]
	and.w	r0, r0, #0x3000
	strh	r0, [r4, #0x0]		@ halfword 0x200002CA = EP0 bits 0x3000
	ldr	r0, [r5, #0x0]
	ands	r0, r6
	eor.w	r0, r0, #0x2000
	eor.w	r0, r0, #0x20
	orrs	r0, r7
	str	r0, [r5, #0x0]
	ldrh	r0, [r1, #0x0]		@ stored USB_STS value
	lsls	r0, r0, #0x1b		@ bit 4 (DIR) to the sign
	ldr	r0, [r5, #0x0]
	bmi.n	.L0800fd16
	and.w	r0, r0, r11
	str	r0, [r5, #0x0]
	bl	fn_0800fe84
	b.n	.L0800fd44
.L0800fcf6:
	ldrh	r1, [r4, #0x0]
	lsls	r1, r1, #0x12		@ bit 13 of the saved bits to the sign
	bpl.n	.L0800fd00
	eor.w	r0, r0, #0x2000
.L0800fd00:
	ldrh	r1, [r4, #0x2]
	lsls	r1, r1, #0x1b		@ bit 4 of the saved bits to the sign
	bmi.n	.L0800fd54
.L0800fd06:
	ldrh	r1, [r4, #0x2]
	lsls	r1, r1, #0x1a		@ bit 5 of the saved bits to the sign
	bpl.n	.L0800fd10
	eor.w	r0, r0, #0x20
.L0800fd10:
	orrs	r0, r7
	str	r0, [r5, #0x0]
	b.n	.L0800fcba
.L0800fd16:
	strh.w	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	lsls	r0, r0, #0x14		@ bit 11 (SETUP) to the sign
	bpl.n	.L0800fd30
	ldr	r0, [r5, #0x0]
	and.w	r0, r0, r8
	str	r0, [r5, #0x0]
	bl	fn_0800ff70
	b.n	.L0800fd44
.L0800fd30:
	ldrh.w	r0, [sp, #0x0]
	lsls	r0, r0, #0x10		@ bit 15 (CTRS_RX) to the sign
	bpl.n	.L0800fcac
	ldr	r0, [r5, #0x0]
	and.w	r0, r0, r8
	str	r0, [r5, #0x0]
	bl	fn_0800fee4
.L0800fd44:
	ldr	r0, [r5, #0x0]
	ldrh	r1, [r4, #0x0]
	ands	r0, r6
	lsls	r1, r1, #0x13		@ bit 12 of the saved bits to the sign
	bpl.n	.L0800fcf6
	eor.w	r0, r0, #0x1000
	b.n	.L0800fcf6
.L0800fd54:
	eor.w	r0, r0, #0x10
	b.n	.L0800fd06
	.short	0x0000			@ padding
.L0800fd5c:
	.word	0x40005c00
.L0800fd60:
	.word	0x200002ca
.L0800fd64:
	.word	0x200002f4
.L0800fd68:
	.word	0x200002b8
.L0800fd6c:
	.word	0x40005000
.L0800fd70:
	.word	0x20000314
.L0800fd74:
	.word	0x200002f8

@ ----------------------------------------------------------------------------
@ fn_0800fd78 - reads a halfword of the packet buffer table entry of an endpoint.
@ r0 = index n; returns in r0 the halfword at 0x40006008 +
@ ((word 0x40005C50 & 0xFFFF) + n * 8) * 2. Word 0x40005C50 is USB_BUFTAB.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fd78,"ax",%progbits
	.p2align 2
	.global fn_0800fd78
	.thumb_func
	.type fn_0800fd78, %function
fn_0800fd78:
	ldr	r1, .L0800fd90		@ r1 = 0x40005C50 (USB_BUFTAB)
	ldr	r1, [r1, #0x0]
	uxth	r1, r1
	add.w	r0, r1, r0, lsl #0x3
	ldr	r1, .L0800fd94		@ r1 = 0x40006000
	add.w	r0, r1, r0, lsl #0x1
	ldrh	r0, [r0, #0x8]
	uxth	r0, r0
	bx	lr
	.short	0x0000			@ padding
.L0800fd90:
	.word	0x40005c50
.L0800fd94:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_0800fd98 - reads the 10-bit length field of the packet buffer table entry.
@ r0 = index n; returns in r0 (halfword at 0x4000600C +
@ ((word 0x40005C50 & 0xFFFF) + n * 8) * 2) & 0x3FF. Word 0x40005C50 is USB_BUFTAB.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fd98,"ax",%progbits
	.p2align 2
	.global fn_0800fd98
	.thumb_func
	.type fn_0800fd98, %function
fn_0800fd98:
	ldr	r1, .L0800fdb0		@ r1 = 0x40005C50 (USB_BUFTAB)
	ldr	r1, [r1, #0x0]
	uxth	r1, r1
	add.w	r0, r1, r0, lsl #0x3
	ldr	r1, .L0800fdb4		@ r1 = 0x40006000
	add.w	r0, r1, r0, lsl #0x1
	ldrh	r0, [r0, #0xc]
	ubfx	r0, r0, #0x0, #0xa
	bx	lr
.L0800fdb0:
	.word	0x40005c50
.L0800fdb4:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_0800fdb8 - returns the receive status field of an endpoint register.
@ r0 = index n; returns USB_EPn (0x40005C00 + n*4) & 0x3000 (STS_RX).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fdb8,"ax",%progbits
	.p2align 2
	.global fn_0800fdb8
	.thumb_func
	.type fn_0800fdb8, %function
fn_0800fdb8:
	ldr	r1, .L0800fdcc		@ r1 = 0x40005000
	add.w	r0, r1, r0, lsl #0x2
	ldr.w	r0, [r0, #0xc00]	@ USB_EPn
	ubfx	r0, r0, #0xc, #0x2	@ STS_RX
	lsls	r0, r0, #0xc
	bx	lr
	.short	0x0000			@ padding
.L0800fdcc:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_0800fdd0 - reads a halfword of the packet buffer table entry of an endpoint.
@ r0 = index n; returns in r0 the halfword at 0x40006000 +
@ ((word 0x40005C50 & 0xFFFF) + n * 8) * 2. Word 0x40005C50 is USB_BUFTAB.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fdd0,"ax",%progbits
	.p2align 2
	.global fn_0800fdd0
	.thumb_func
	.type fn_0800fdd0, %function
fn_0800fdd0:
	ldr	r1, .L0800fde4		@ r1 = 0x40005C50 (USB_BUFTAB)
	ldr	r1, [r1, #0x0]
	uxth	r1, r1
	add.w	r0, r1, r0, lsl #0x3
	ldr	r1, .L0800fde8		@ r1 = 0x40006000
	ldrh.w	r0, [r1, r0, lsl #0x1]
	uxth	r0, r0
	bx	lr
.L0800fde4:
	.word	0x40005c50
.L0800fde8:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_0800fdec - USB interrupt service routine body.
@ No parameters, no return value. Reached only by the b.w in fn_0800fe80 (word
@ 0x08006090 holds 0x0800FE81).
@ r6 = 0x40005C44 (USB_STS), r4 = 0x200002F2, r5 = 0x200002C8; halfword 0x200002F4 =
@ low half of USB_STS. Five tests, each (halfword 0x200002F4 AND halfword
@ 0x200002C8) with one bit moved to the sign, in this order:
@  bit 15 (CTRS): calls fn_0800fc1c (no write to USB_STS);
@  bit 10 (RST): USB_STS = 0xFBFF, then calls the function whose address is the word at
@                0x2000034C ([0x20000348 + 4]);
@  bit 12 (WKUP): USB_STS = 0xEFFF, calls fn_0800b634(0);
@  bit 11 (SUSPD): when byte 0x200003A4 is non-zero calls fn_0800c1f4, otherwise
@                fn_0800b634(2); then in both cases USB_STS = 0xF7FF;
@  bit 9 (SOF): USB_STS = 0xFDFF and byte 0x200002F2 is incremented.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fdec,"ax",%progbits
	.p2align 2
	.global fn_0800fdec
	.thumb_func
	.type fn_0800fdec, %function
fn_0800fdec:
	push	{r4, r5, r6, lr}
	ldr	r6, .L0800fe6c		@ r6 = 0x40005C44 (USB_STS)
	ldr	r0, [r6, #0x0]
	ldr	r4, .L0800fe70		@ r4 = 0x200002F2
	strh	r0, [r4, #0x2]		@ halfword 0x200002F4
	ldrh	r0, [r4, #0x2]
	ldr	r5, .L0800fe74		@ r5 = 0x200002C8
	ldrh	r1, [r5, #0x0]
	ands	r0, r1
	lsls	r0, r0, #0x10		@ bit 15 (CTRS)
	bpl.n	.L0800fe06
	bl	fn_0800fc1c
.L0800fe06:
	ldrh	r0, [r4, #0x2]
	ldrh	r1, [r5, #0x0]
	ands	r0, r1
	lsls	r0, r0, #0x15		@ bit 10 (RST)
	bpl.n	.L0800fe1c
	movw	r0, #0xfbff
	str	r0, [r6, #0x0]
	ldr	r0, .L0800fe78		@ r0 = 0x20000348
	ldr	r0, [r0, #0x4]
	blx	r0
.L0800fe1c:
	ldrh	r0, [r4, #0x2]
	ldrh	r1, [r5, #0x0]
	ands	r0, r1
	lsls	r0, r0, #0x13		@ bit 12 (WKUP)
	bpl.n	.L0800fe32
	movw	r0, #0xefff
	str	r0, [r6, #0x0]
	movs	r0, #0x0
	bl	fn_0800b634
.L0800fe32:
	ldrh	r0, [r4, #0x2]
	ldrh	r1, [r5, #0x0]
	ands	r0, r1
	lsls	r0, r0, #0x14		@ bit 11 (SUSPD)
	bpl.n	.L0800fe54
	ldr	r0, .L0800fe7c		@ r0 = 0x200003A4
	ldrb	r0, [r0, #0x0]
	cbz	r0, .L0800fe48
	bl	fn_0800c1f4
	b.n	.L0800fe4e
.L0800fe48:
	movs	r0, #0x2
	bl	fn_0800b634
.L0800fe4e:
	movw	r0, #0xf7ff
	str	r0, [r6, #0x0]
.L0800fe54:
	ldrh	r0, [r4, #0x2]
	ldrh	r1, [r5, #0x0]
	ands	r0, r1
	lsls	r0, r0, #0x16		@ bit 9 (SOF)
	bpl.n	.L0800fe6a
	movw	r0, #0xfdff
	str	r0, [r6, #0x0]
	ldrb	r0, [r4, #0x0]
	.inst.n	0x1c40			@ adds r0, r0, #1
	strb	r0, [r4, #0x0]
.L0800fe6a:
	pop	{r4, r5, r6, pc}
.L0800fe6c:
	.word	0x40005c44
.L0800fe70:
	.word	0x200002f2
.L0800fe74:
	.word	0x200002c8
.L0800fe78:
	.word	0x20000348
.L0800fe7c:
	.word	0x200003a4

@ ----------------------------------------------------------------------------
@ fn_0800fe80 - tail jump to fn_0800fdec. No parameters; returns to the caller of
@ 0x0800FE80. Word 0x08006090 of the image holds 0x0800FE81 (this entry with the
@ Thumb bit).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fe80,"ax",%progbits
	.p2align 2
	.global fn_0800fe80
	.thumb_func
	.type fn_0800fe80, %function
fn_0800fe80:
	b.w	fn_0800fdec

@ ----------------------------------------------------------------------------
@ fn_0800fe84 - state handler for endpoint 0 (called from fn_0800fc1c when bit 4
@ (DIR) of the stored USB_STS value is clear).
@ No parameters, no return value. r4 = 0x200002BC; structure = [0x200002BC]; byte 8
@ of it is the state.
@ State 2 or 4: calls fn_08008968, then re-reads byte 8 and stores it back.
@ State 6: when byte 1 = 5 and (byte 0 & 0x7F) = 0 calls fn_0800ffe8(byte 3) and the
@ function at [[0x200002C4] + 0x20]; in every case then calls the function at
@ [[0x200002C0] + 8] and stores 8 in byte 8.
@ Other states: store 8 in byte 8.
@ Ends with a tail jump to fn_0800ff2c.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fe84,"ax",%progbits
	.p2align 2
	.global fn_0800fe84
	.thumb_func
	.type fn_0800fe84, %function
fn_0800fe84:
	push	{r4, lr}
	ldr	r4, .L0800fed4		@ r4 = 0x200002BC
	ldr	r0, [r4, #0x0]
	ldrb	r1, [r0, #0x8]
	cmp	r1, #0x2
	beq.n	.L0800fe9a
	cmp	r1, #0x4
	beq.n	.L0800fe9a
	cmp	r1, #0x6
	beq.n	.L0800fea4
	b.n	.L0800fec6
.L0800fe9a:
	bl	fn_08008968
	ldr	r0, [r4, #0x0]
	ldrb	r0, [r0, #0x8]
	b.n	.L0800fec8
.L0800fea4:
	ldrb	r1, [r0, #0x1]
	cmp	r1, #0x5
	bne.n	.L0800febe
	ldrb	r1, [r0, #0x0]
	lsls	r1, r1, #0x19		@ bits 6..0 of byte 0 to the top
	bne.n	.L0800febe
	ldrb	r0, [r0, #0x3]
	bl	fn_0800ffe8
	ldr	r0, .L0800fed8		@ r0 = 0x200002C4
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0x20]
	blx	r0
.L0800febe:
	ldr	r0, .L0800fedc		@ r0 = 0x200002C0
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0x8]
	blx	r0
.L0800fec6:
	movs	r0, #0x8
.L0800fec8:
	ldr	r1, [r4, #0x0]
	strb	r0, [r1, #0x8]
	pop.w	{r4, lr}
	b.w	fn_0800ff2c
.L0800fed4:
	.word	0x200002bc
.L0800fed8:
	.word	0x200002c4
.L0800fedc:
	.word	0x200002c0

@ ----------------------------------------------------------------------------
@ return_only_0800fee0 - empty function: returns at once.
@ ----------------------------------------------------------------------------
	.section .text.return_only_0800fee0,"ax",%progbits
	.p2align 2
	.global return_only_0800fee0
	.thumb_func
	.type return_only_0800fee0, %function
return_only_0800fee0:
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0800fee4 - state handler for endpoint 0 (called from fn_0800fc1c when bit 4 of
@ the stored USB_STS value is set, bit 11 (SETUP) of USB_EP0 is clear and bit 15 is set).
@ No parameters, no return value. r4 = 0x200002BC; byte 8 of the structure [r4] is
@ the state.
@ State 2 or 4: stores 8 in byte 8.
@ State 3 or 5: calls fn_08008a1c and stores the re-read byte 8.
@ State 7: calls the function at [[0x200002C0] + 0xC] and stores 8.
@ Other states: store 8.
@ Ends with a tail jump to fn_0800ff2c.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fee4,"ax",%progbits
	.p2align 2
	.global fn_0800fee4
	.thumb_func
	.type fn_0800fee4, %function
fn_0800fee4:
	push	{r4, lr}
	ldr	r4, .L0800ff24		@ r4 = 0x200002BC
	ldr	r0, [r4, #0x0]
	ldrb	r0, [r0, #0x8]
	cmp	r0, #0x2
	beq.n	.L0800ff14
	cmp	r0, #0x4
	beq.n	.L0800ff14
	cmp	r0, #0x3
	beq.n	.L0800ff02
	cmp	r0, #0x5
	beq.n	.L0800ff02
	cmp	r0, #0x7
	beq.n	.L0800ff0c
	b.n	.L0800ff14
.L0800ff02:
	bl	fn_08008a1c
	ldr	r0, [r4, #0x0]
	ldrb	r0, [r0, #0x8]
	b.n	.L0800ff16
.L0800ff0c:
	ldr	r0, .L0800ff28		@ r0 = 0x200002C0
	ldr	r0, [r0, #0x0]
	ldr	r0, [r0, #0xc]
	blx	r0
.L0800ff14:
	movs	r0, #0x8
.L0800ff16:
	ldr	r1, [r4, #0x0]
	strb	r0, [r1, #0x8]
	pop.w	{r4, lr}
	b.w	fn_0800ff2c
	.short	0x0000			@ padding
.L0800ff24:
	.word	0x200002bc
.L0800ff28:
	.word	0x200002c0

@ ----------------------------------------------------------------------------
@ fn_0800ff2c - writes the endpoint 0 length word and returns a result from the state.
@ No parameters; returns 0 or 1 in r0.
@ Calls fn_08010050(0, byte [0x20000348 + 0x2C]) (byte 0x20000374). Byte 8 of the
@ structure [0x200002BC] = 8: stores 0x1000 to halfword 0x200002CA and 0x10 to
@ halfword 0x200002CC and returns 0; = 9 returns 1; other values return 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ff2c,"ax",%progbits
	.p2align 2
	.global fn_0800ff2c
	.thumb_func
	.type fn_0800ff2c, %function
fn_0800ff2c:
	ldr	r0, .L0800ff60		@ r0 = 0x20000348
	push	{r4, lr}
	ldrb.w	r1, [r0, #0x2c]
	movs	r0, #0x0
	bl	fn_08010050
	ldr	r0, .L0800ff64		@ r0 = 0x200002BC
	ldr	r0, [r0, #0x0]
	ldrb	r0, [r0, #0x8]
	cmp	r0, #0x8
	beq.n	.L0800ff4a
	cmp	r0, #0x9
	beq.n	.L0800ff5c
	b.n	.L0800ff58
.L0800ff4a:
	ldr	r1, .L0800ff68		@ r1 = 0x200002CA
	mov.w	r0, #0x1000
	strh	r0, [r1, #0x0]
	ldr	r1, .L0800ff6c		@ r1 = 0x200002CC
	movs	r0, #0x10
	strh	r0, [r1, #0x0]
.L0800ff58:
	movs	r0, #0x0
	pop	{r4, pc}
.L0800ff5c:
	movs	r0, #0x1
	pop	{r4, pc}
.L0800ff60:
	.word	0x20000348
.L0800ff64:
	.word	0x200002bc
.L0800ff68:
	.word	0x200002ca
.L0800ff6c:
	.word	0x200002cc

@ ----------------------------------------------------------------------------
@ fn_0800ff70 - copies the 8-byte request out of the packet memory into the structure.
@ No parameters, no return value.
@ Byte offset o = 2 * halfword at 0x40006008 + (word 0x40005C50 & 0xFFFF) * 2 (the
@ entry of endpoint 0 in the table at USB_BUFTAB). Unless byte 8 of the structure
@ [0x200002BC] is 9: copies bytes 0 and 1 from 0x40006000 + o, the halfword at
@ 0x40006004 + o to offset 2 and the halfword at 0x40006008 + o to offset 4 (both
@ byte-swapped with swap_bytes_16), and the halfword at 0x4000600C + o to offset 6.
@ Stores 1 in byte 8. When the halfword at offset 6 is 0 calls fn_0800adcc, otherwise
@ fn_08008ac0. Ends with a tail jump to fn_0800ff2c.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ff70,"ax",%progbits
	.p2align 2
	.global fn_0800ff70
	.thumb_func
	.type fn_0800ff70, %function
fn_0800ff70:
	push	{r4, r5, r6, lr}
	ldr	r0, .L0800ffcc		@ r0 = 0x40005C50 (USB_BUFTAB)
	ldr	r0, [r0, #0x0]
	ldr	r5, .L0800ffd4		@ r5 = 0x200002BC
	lsls	r0, r0, #0x10
	lsrs	r1, r0, #0xf		@ r1 = (USB_BUFTAB & 0xFFFF) * 2
	ldr	r0, .L0800ffd0		@ r0 = 0x40006000
	add	r1, r0
	ldrh	r1, [r1, #0x8]
	uxth	r1, r1
	add.w	r4, r0, r1, lsl #0x1	@ r4 = 0x40006000 + o
	ldr	r0, [r5, #0x0]
	ldrb	r1, [r0, #0x8]
	cmp	r1, #0x9
	beq.n	.L0800ffb0
	ldrb	r1, [r4, #0x0]
	strb	r1, [r0, #0x0]
	ldrb	r1, [r4, #0x1]
	strb	r1, [r0, #0x1]
	ldrh	r0, [r4, #0x4]
	bl	swap_bytes_16
	ldr	r1, [r5, #0x0]
	strh	r0, [r1, #0x2]
	ldrh	r0, [r4, #0x8]
	bl	swap_bytes_16
	ldr	r1, [r5, #0x0]
	strh	r0, [r1, #0x4]
	ldrh	r0, [r4, #0xc]
	strh	r0, [r1, #0x6]
.L0800ffb0:
	ldr	r0, [r5, #0x0]
	movs	r1, #0x1
	strb	r1, [r0, #0x8]
	ldrh	r0, [r0, #0x6]
	cbz	r0, .L0800ffc6
	bl	fn_08008ac0
.L0800ffbe:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800ff2c
.L0800ffc6:
	bl	fn_0800adcc
	b.n	.L0800ffbe
.L0800ffcc:
	.word	0x40005c50
.L0800ffd0:
	.word	0x40006000
.L0800ffd4:
	.word	0x200002bc

@ ----------------------------------------------------------------------------
@ fn_0800ffd8 - writes the packet buffer table address.
@ r0 = value; no return value. Writes r0 & 0xFFFFFFF8 to word 0x40005C50
@ (USB_BUFTAB).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ffd8,"ax",%progbits
	.p2align 2
	.global fn_0800ffd8
	.thumb_func
	.type fn_0800ffd8, %function
fn_0800ffd8:
	ldr	r1, .L0800ffe4		@ r1 = 0x40005C50 (USB_BUFTAB)
	bic.w	r0, r0, #0x7
	str	r0, [r1, #0x0]
	bx	lr
	.short	0x0000			@ padding
.L0800ffe4:
	.word	0x40005c50

@ ----------------------------------------------------------------------------
@ fn_0800ffe8 - initialises all endpoint registers and writes the device address.
@ r0 = value; no return value.
@ For i = 0 to byte 0x20000330 - 1: USB_EPi (0x40005C00 + i*4) =
@ (word & 0x8F8F) | i | 0x8080 (i goes into EPADDR, bits 3:0). Then writes r0 | 0x80
@ to word 0x40005C4C (USB_ADDR).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ffe8,"ax",%progbits
	.p2align 2
	.global fn_0800ffe8
	.thumb_func
	.type fn_0800ffe8, %function
fn_0800ffe8:
	push	{r4, r5, r6, r7, lr}
	ldr	r1, .L08010024		@ r1 = 0x20000330
	ldr	r5, .L08010028		@ r5 = 0x40005000
	movw	r7, #0x8f8f
	ldrb	r3, [r1, #0x0]
	movs	r1, #0x0
	movw	r12, #0x8080
	b.n	.L08010014
.L0800fffc:
	uxtb	r6, r1
	add.w	r4, r5, r6, lsl #0x2
	ldr.w	r2, [r4, #0xc00]	@ USB_EPi
	ands	r2, r7
	orrs	r2, r6
	orr.w	r2, r2, r12
	str.w	r2, [r4, #0xc00]
	.inst.n	0x1c49			@ adds r1, r1, #1
.L08010014:
	cmp	r1, r3
	bcc.n	.L0800fffc
	ldr	r1, .L0801002c		@ r1 = 0x40005C4C (USB_ADDR)
	orr.w	r0, r0, #0x80
	str	r0, [r1, #0x0]
	pop	{r4, r5, r6, r7, pc}
	.short	0x0000			@ padding
.L08010024:
	.word	0x20000330
.L08010028:
	.word	0x40005000
.L0801002c:
	.word	0x40005c4c

@ ----------------------------------------------------------------------------
@ fn_08010030 - writes the second word of a packet buffer table entry.
@ r0 = index n, r1 = value; no return value. Writes r1 & 0xFFFFFFFE to the word at
@ 0x40006008 + ((word 0x40005C50 & 0xFFFF) + n * 8) * 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_08010030,"ax",%progbits
	.p2align 2
	.global fn_08010030
	.thumb_func
	.type fn_08010030, %function
fn_08010030:
	ldr	r2, .L08010048		@ r2 = 0x40005C50 (USB_BUFTAB)
	bic.w	r1, r1, #0x1
	ldr	r2, [r2, #0x0]
	uxth	r2, r2
	add.w	r0, r2, r0, lsl #0x3
	ldr	r2, .L0801004c		@ r2 = 0x40006000
	add.w	r0, r2, r0, lsl #0x1
	str	r1, [r0, #0x8]
	bx	lr
.L08010048:
	.word	0x40005c50
.L0801004c:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_08010050 - writes the length word of a packet buffer table entry.
@ r0 = index n, r1 = byte count; no return value.
@ v = r1 below 0x3F: ((r1 >> 1) + (r1 & 1)) << 10; otherwise
@ ((r1 >> 5) - 1 when (r1 & 0x1F) = 0, uxth) << 10 | 0x8000. Writes v to the word at
@ 0x4000600C + ((word 0x40005C50 & 0xFFFF) + n * 8) * 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_08010050,"ax",%progbits
	.p2align 2
	.global fn_08010050
	.thumb_func
	.type fn_08010050, %function
fn_08010050:
	ldr	r2, .L08010088		@ r2 = 0x40005C50 (USB_BUFTAB)
	ldr	r2, [r2, #0x0]
	cmp	r1, #0x3e
	uxth	r2, r2
	add.w	r0, r2, r0, lsl #0x3
	ldr	r2, .L0801008c		@ r2 = 0x4000600C
	add.w	r2, r2, r0, lsl #0x1
	bls.n	.L08010078
	lsrs	r0, r1, #0x5
	lsls	r1, r1, #0x1b		@ r1 & 0x1F to the top
	bne.n	.L0801006e
	.inst.n	0x1e40			@ subs r0, r0, #1
	uxth	r0, r0
.L0801006e:
	mov.w	r1, #0x8000
	orr.w	r0, r1, r0, lsl #0xa
	b.n	.L08010082
.L08010078:
	lsrs	r0, r1, #0x1
	lsls	r1, r1, #0x1f		@ r1 & 1 to the top
	beq.n	.L08010080
	.inst.n	0x1c40			@ adds r0, r0, #1
.L08010080:
	lsls	r0, r0, #0xa
.L08010082:
	str	r0, [r2, #0x0]
	bx	lr
	.short	0x0000			@ padding
.L08010088:
	.word	0x40005c50
.L0801008c:
	.word	0x4000600c

@ ----------------------------------------------------------------------------
@ fn_08010090 - toggles the receive status of an endpoint register.
@ r0 = index n; no return value. USB_EPn (0x40005C00 + n*4) =
@ (((word & 0xBF8F) ^ 0x3000) | 0x8080).
@ ----------------------------------------------------------------------------
	.section .text.fn_08010090,"ax",%progbits
	.p2align 2
	.global fn_08010090
	.thumb_func
	.type fn_08010090, %function
fn_08010090:
	lsls	r1, r0, #0x2
	ldr	r0, .L080100b0		@ r0 = 0x40005000
	add	r1, r0
	ldr.w	r0, [r1, #0xc00]	@ USB_EPn
	movw	r2, #0xbf8f
	ands	r0, r2
	eor.w	r0, r0, #0x3000
	movw	r2, #0x8080
	orrs	r0, r2
	str.w	r0, [r1, #0xc00]
	bx	lr
.L080100b0:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_080100b4 - writes the first word of a packet buffer table entry.
@ r0 = index n, r1 = value; no return value. Writes r1 & 0xFFFFFFFE to the word at
@ 0x40006000 + ((word 0x40005C50 & 0xFFFF) + n * 8) * 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_080100b4,"ax",%progbits
	.p2align 2
	.global fn_080100b4
	.thumb_func
	.type fn_080100b4, %function
fn_080100b4:
	ldr	r2, .L080100cc		@ r2 = 0x40005C50 (USB_BUFTAB)
	bic.w	r1, r1, #0x1
	ldr	r2, [r2, #0x0]
	uxth	r2, r2
	add.w	r0, r2, r0, lsl #0x3
	ldr	r2, .L080100d0		@ r2 = 0x40006000
	str.w	r1, [r2, r0, lsl #0x1]
	bx	lr
	.short	0x0000			@ padding
.L080100cc:
	.word	0x40005c50
.L080100d0:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_080100d4 - writes the second word group of a packet buffer table entry.
@ r0 = index n, r1 = value; no return value. Writes r1 to the word at
@ 0x40006004 + ((word 0x40005C50 & 0xFFFF) + n * 8) * 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_080100d4,"ax",%progbits
	.p2align 2
	.global fn_080100d4
	.thumb_func
	.type fn_080100d4, %function
fn_080100d4:
	ldr	r2, .L080100e8		@ r2 = 0x40005C50 (USB_BUFTAB)
	ldr	r2, [r2, #0x0]
	uxth	r2, r2
	add.w	r0, r2, r0, lsl #0x3
	ldr	r2, .L080100ec		@ r2 = 0x40006000
	add.w	r0, r2, r0, lsl #0x1
	str	r1, [r0, #0x4]
	bx	lr
.L080100e8:
	.word	0x40005c50
.L080100ec:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_080100f0 - replaces the control bits of an endpoint register.
@ r0 = index n, r1 = bits; no return value. USB_EPn (0x40005C00 + n*4) =
@ (word & 0x898F) | r1.
@ ----------------------------------------------------------------------------
	.section .text.fn_080100f0,"ax",%progbits
	.p2align 2
	.global fn_080100f0
	.thumb_func
	.type fn_080100f0, %function
fn_080100f0:
	lsls	r2, r0, #0x2
	ldr	r0, .L08010108		@ r0 = 0x40005000
	add	r2, r0
	ldr.w	r0, [r2, #0xc00]	@ USB_EPn
	movw	r3, #0x898f
	ands	r0, r3
	orrs	r0, r1
	str.w	r0, [r2, #0xc00]
	bx	lr
.L08010108:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_0801010c - reads the received packet of an endpoint into a buffer.
@ r0 = endpoint (low 7 bits used), r1 = destination buffer; returns the byte count
@ in r0. Calls fn_0800fd98(r0 & 0x7F) for the count, fn_0800fd78(r0 & 0x7F) for the
@ offset and copy_halfwords_from_40006000(r1, offset, count).
@ ----------------------------------------------------------------------------
	.section .text.fn_0801010c,"ax",%progbits
	.p2align 2
	.global fn_0801010c
	.thumb_func
	.type fn_0801010c, %function
fn_0801010c:
	push	{r4, r5, r6, lr}
	and.w	r6, r0, #0x7f
	mov	r5, r1
	mov	r0, r6
	bl	fn_0800fd98
	mov	r4, r0
	mov	r0, r6
	bl	fn_0800fd78
	mov	r1, r0
	mov	r2, r4
	mov	r0, r5
	bl	copy_halfwords_from_40006000
	mov	r0, r4
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08010130 - writes a packet from a buffer to the packet memory of an endpoint.
@ r0 = endpoint (low 7 bits used), r1 = source buffer, r2 = byte count; returns 0.
@ Calls fn_0800fdd0(r0 & 0x7F) for the offset, copy_halfwords_to_40006000(r1, offset,
@ uxth(r2)) and fn_080100d4(r0 & 0x7F, uxth(r2)).
@ ----------------------------------------------------------------------------
	.section .text.fn_08010130,"ax",%progbits
	.p2align 2
	.global fn_08010130
	.thumb_func
	.type fn_08010130, %function
fn_08010130:
	push	{r4, r5, r6, lr}
	and.w	r5, r0, #0x7f
	mov	r4, r2
	mov	r6, r1
	mov	r0, r5
	bl	fn_0800fdd0
	mov	r1, r0
	uxth	r2, r4
	mov	r0, r6
	bl	copy_halfwords_to_40006000
	uxth	r1, r4
	mov	r0, r5
	bl	fn_080100d4
	movs	r0, #0x0
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_0801019c - copies 0x40 bytes from 0x20006674 into the buffer at 0x20005E74 and
@ passes a completed block to fn_0800aa20.
@ r0, r1 = two values, both multiplied by word 0x200003B0 in state 0 only; no return
@ value. Tail-called function, reached only by the b.w at 0x0800B984.
@ r4 = 0x200003B8 (state byte s = byte [r4]), r3 = word 0x200003B0 (fn_0800a9ec
@ writes 0x800 there), r2 = word 0x200003C0 ([r4 + 8]) + 0x40, r6 = 0.
@ s = 0: word 0x200003CC = r0 * r3 and word 0x200003D0 = r1 * r3 (strd at [r4 + 0x14]),
@ byte 0x200003B8 = 1, then continues as s = 1.
@ s = 1: word 0x200003D8 = 0 ([r4 + 0x20]); copies bytes from 0x20006674 (index r5 =
@ 0, 1, ...) to 0x20005E74 + word 0x200003C0 while word 0x200003C0 is below r2
@ (unsigned), incrementing word 0x200003C0 per byte, i.e. 0x40 bytes; stores the
@ byte count r5 in word 0x200003D8. Word 0x200003CC += halfword 0x2000043A;
@ word 0x200003D0 -= halfword 0x2000043A; when the new word 0x200003D0 is an exact
@ multiple of r3 (udiv, mls) word 0x200003C0 = 0 and fn_0800aa20(word 0x200003CC - r3,
@ 0x20005E74, uxth(r3)) is called. Then word 0x200066DC ([0x200066D4 + 8]) -=
@ halfword 0x2000043A and fn_0800b9ec(2, 0x3000) is called.
@ Any other s skips straight to 0x08010234.
@ 0x08010234 (all states): when word 0x200003D0 is 0, or byte 0x20000438 equals 4,
@ word 0x200003C0 = 0, fn_0800bb1c(0, 1) is called and byte 0x200003B8 = 0;
@ otherwise returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801019c,"ax",%progbits
	.p2align 2
	.global fn_0801019c
	.thumb_func
	.type fn_0801019c, %function
fn_0801019c:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r4, .L08010250		@ r4 = 0x200003B8
	ldr	r2, [r4, #0x8]
	ldr	r3, .L08010254		@ r3 = 0x200003B0
	ldrb	r5, [r4, #0x0]
	movs	r6, #0x0
	ldr	r3, [r3, #0x0]
	adds	r2, #0x40
	cbz	r5, .L080101b6
	cmp	r5, #0x1
	beq.n	.L080101c2
	b.n	.L08010234
.L080101b6:
	muls	r0, r3, r0
	muls	r1, r3, r1
	strd	r0, r1, [r4, #0x14]
	movs	r0, #0x1
	strb	r0, [r4, #0x0]
.L080101c2:
	mov	r5, r6
	ldr	r1, .L08010258		@ r1 = 0x20006674
	ldr	r0, .L0801025c		@ r0 = 0x20005E74
	mov	lr, r4
	str	r6, [r4, #0x20]
	b.n	.L080101e4
.L080101ce:
	ldrb	r7, [r1, r5]
	ldr.w	r12, [lr, #0x8]
	strb.w	r7, [r0, r12]
	ldr.w	r7, [lr, #0x8]
	.inst.n	0x1c7f			@ adds r7, r7, #1
	str.w	r7, [lr, #0x8]
	.inst.n	0x1c6d			@ adds r5, r5, #1
.L080101e4:
	ldr.w	r7, [lr, #0x8]
	cmp	r7, r2
	bcc.n	.L080101ce
	ldr	r7, .L08010260		@ r7 = 0x2000043A
	str.w	r5, [lr, #0x20]
	ldr.w	r1, [lr, #0x14]
	ldrh	r0, [r7, #0x0]
	add	r1, r0
	str.w	r1, [lr, #0x14]
	ldr.w	r2, [lr, #0x18]
	subs	r0, r2, r0
	udiv	r2, r0, r3
	str.w	r0, [lr, #0x18]
	mls	r0, r3, r2, r0
	cbnz	r0, .L08010220
	str.w	r6, [lr, #0x8]
	subs	r0, r1, r3
	uxth	r2, r3
	ldr	r1, .L0801025c		@ r1 = 0x20005E74
	bl	fn_0800aa20
.L08010220:
	ldr	r0, .L08010264		@ r0 = 0x200066D4
	ldrh	r2, [r7, #0x0]
	ldr	r1, [r0, #0x8]
	subs	r1, r1, r2
	str	r1, [r0, #0x8]
	mov.w	r1, #0x3000
	movs	r0, #0x2
	bl	fn_0800b9ec
.L08010234:
	ldr	r0, [r4, #0x18]
	cbz	r0, .L08010240
	ldr	r0, .L08010268		@ r0 = 0x20000438
	ldrb	r0, [r0, #0x0]
	cmp	r0, #0x4
	bne.n	.L0801024c
.L08010240:
	str	r6, [r4, #0x8]
	movs	r1, #0x1
	movs	r0, #0x0
	bl	fn_0800bb1c
	strb	r6, [r4, #0x0]
.L0801024c:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L08010250:
	.word	0x200003b8
.L08010254:
	.word	0x200003b0
.L08010258:
	.word	0x20006674
.L0801025c:
	.word	0x20005e74
.L08010260:
	.word	0x2000043a
.L08010264:
	.word	0x200066d4
.L08010268:
	.word	0x20000438
