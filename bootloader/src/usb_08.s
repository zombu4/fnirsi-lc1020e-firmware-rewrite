@ usb_08.s - USB device control-transfer and endpoint-0 handling routines of the stock bootloader (batch 8).
@ Part of the FNIRSI LC1020E firmware rewrite: port of the stock bootloader (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080009ec - endpoint 0 IN data stage: send the next chunk of the pending
@ control-transfer data.
@ The USB device state block is addressed by the pointer at 0x2000006C
@ (+0x08 state byte, +0x10 remaining length, +0x12 sent length, +0x14 packet
@ size, +0x18 data provider function pointer).
@ If nothing remains and the state byte is 4 (data stage done): when the flag
@ byte at 0x20000064 is zero, store 0x10 to 0x2000007C and set state 7;
@ otherwise clear the packet memory word at 0x40006004 + 2 * (halfword index
@ read from USB_BUFTAB (0x40005C50)), store 0x30 to 0x2000007C, clear
@ the flag and set state 4.
@ Otherwise: the chunk size is the smaller of remaining length and packet
@ size; state becomes 4 when the remaining length is not above the packet
@ size, else 2. The provider function (+0x18) is called with the chunk size,
@ its result and fn_08002bf4(0) are passed with the chunk size to
@ fn_08002a10, fn_08002f8c(0, chunk) is called, the remaining length is
@ reduced and the sent length increased by the chunk size, 0x30 is stored to
@ 0x2000007C and 0x3000 to the halfword at 0x2000007A.
@ Finally the state byte is written back.
@ ----------------------------------------------------------------------------
	.section .text.fn_080009ec,"ax",%progbits
	.p2align 2
	.global fn_080009ec
	.thumb_func
	.type fn_080009ec, %function
fn_080009ec:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr.w	r8, .L08000a88		@ r8 = &pointer to USB state block (0x2000006C)
	ldr	r7, .L08000a8c		@ r7 = 0x2000007C
	mov.w	r9, #0x30
	ldr.w	r1, [r8]		@ r1 = state block
	add.w	r5, r1, #0x10		@ r5 = &remaining length
	ldrh	r0, [r1, #0x10]		@ remaining length
	ldrb	r6, [r1, #8]		@ current state
	cbnz	r0, .L08000a0c
	cmp	r6, #4
	beq.n	.L08000a16
.L08000a0c:
	ldrh	r4, [r5, #4]		@ packet size
	cmp	r0, r4
	bhi.n	.L08000a3c
	movs	r6, #4
	b.n	.L08000a3e
.L08000a16:
	ldr	r0, .L08000a90		@ r0 = 0x20000064 (flag byte)
	ldrb	r1, [r0]
	cbz	r1, .L08000a34
	ldr	r2, .L08000a94		@ USB_BUFTAB (0x40005C50)
	movs	r1, #0
	ldr	r2, [r2]
	ldr	r3, .L08000a98		@ packet memory base 0x40006000
	lsls	r2, r2, #0x10
	add.w	r2, r3, r2, lsr #15	@ packet memory + 2 * (index & 0xffff)
	str	r1, [r2, #4]		@ clear the word at +4
	strh.w	r9, [r7]		@ 0x2000007C = 0x30
	strb	r1, [r0]		@ clear the flag
	b.n	.L08000a7c
.L08000a34:
	movs	r6, #7
	movs	r0, #0x10
	strh	r0, [r7]		@ 0x2000007C = 0x10
	b.n	.L08000a7c
.L08000a3c:
	movs	r6, #2
.L08000a3e:
	cmp	r4, r0
	bls.n	.L08000a44
	mov	r4, r0			@ chunk = min(remaining, packet size)
.L08000a44:
	ldr	r1, [r5, #8]		@ data provider function pointer
	mov	r0, r4
	blx	r1
	mov	r10, r0			@ provider result
	movs	r0, #0
	bl	fn_08002bf4
	mov	r1, r0
	mov	r2, r4
	mov	r0, r10
	bl	fn_08002a10
	mov	r1, r4
	movs	r0, #0
	bl	fn_08002f8c
	ldrh	r0, [r5]
	subs	r0, r0, r4		@ remaining -= chunk
	strh	r0, [r5]
	ldrh	r0, [r5, #2]
	add	r0, r4			@ sent += chunk
	strh	r0, [r5, #2]
	strh.w	r9, [r7]		@ 0x2000007C = 0x30
	ldr	r1, .L08000a9c		@ r1 = 0x2000007A
	mov.w	r0, #0x3000
	strh	r0, [r1]
.L08000a7c:
	ldr.w	r0, [r8]
	strb	r6, [r0, #8]		@ store the new state
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
	.short	0x0000			@ padding
.L08000a88:
	.word	0x2000006c
.L08000a8c:
	.word	0x2000007c
.L08000a90:
	.word	0x20000064
.L08000a94:
	.word	0x40005c50
.L08000a98:
	.word	0x40006000
.L08000a9c:
	.word	0x2000007a

@ ----------------------------------------------------------------------------
@ fn_08000aa0 - endpoint 0 OUT data stage: receive/consume the next chunk of
@ control-transfer data and update the state.
@ State block pointer at 0x2000006C (+0x08 state byte, +0x10 remaining length,
@ +0x12 transferred length, +0x14 packet size, +0x18 data handler function
@ pointer).
@ If a handler pointer is set and data remains: the chunk is the smaller of
@ remaining length and packet size; the handler is called with the chunk size,
@ remaining is reduced and the transferred length increased, then
@ fn_08002b9c(0) is called and fn_080029e8(handler result, that value, chunk)
@ is called.
@ If data still remains, 0x3000 is stored to the halfword at 0x2000007A,
@ fn_08002f8c(0, 0) is called and 0x30 stored to 0x2000007C.
@ Final state: 3 when remaining >= packet size; 5 when remaining is nonzero
@ and smaller; 6 when it is zero, in which case the packet memory word at
@ 0x40006004 + 2 * (halfword index read from USB_BUFTAB (0x40005C50))
@ is cleared and 0x30 stored to 0x2000007C.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000aa0,"ax",%progbits
	.p2align 2
	.global fn_08000aa0
	.thumb_func
	.type fn_08000aa0, %function
fn_08000aa0:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr	r6, .L08000b30		@ r6 = &pointer to USB state block (0x2000006C)
	ldr.w	r8, .L08000b34		@ r8 = 0x2000007C
	movs	r7, #0x30
	ldr	r5, [r6]
	ldrh.w	r0, [r5, #0x10]!	@ r5 = &remaining length, r0 = remaining
	ldr	r1, [r5, #8]		@ data handler function pointer
	cbz	r1, .L08000ae2
	cbz	r0, .L08000afa
	ldrh	r4, [r5, #4]		@ packet size
	cmp	r4, r0
	bls.n	.L08000ac0
	mov	r4, r0			@ chunk = min(remaining, packet size)
.L08000ac0:
	mov	r0, r4
	blx	r1
	mov	r9, r0			@ handler result
	ldrh	r0, [r5]
	subs	r0, r0, r4		@ remaining -= chunk
	strh	r0, [r5]
	ldrh	r0, [r5, #2]
	add	r0, r4			@ transferred += chunk
	strh	r0, [r5, #2]
	movs	r0, #0
	bl	fn_08002b9c
	mov	r1, r0
	mov	r2, r4
	mov	r0, r9
	bl	fn_080029e8
.L08000ae2:
	ldrh	r0, [r5]
	cbz	r0, .L08000afa
	ldr	r1, .L08000b38		@ r1 = 0x2000007A
	mov.w	r0, #0x3000
	strh	r0, [r1]
	movs	r1, #0
	mov	r0, r1
	bl	fn_08002f8c
	strh.w	r7, [r8]		@ 0x2000007C = 0x30
.L08000afa:
	ldrh	r0, [r5]
	ldrh	r1, [r5, #4]
	cmp	r0, r1
	bcc.n	.L08000b06
	movs	r0, #3
	b.n	.L08000b0a
.L08000b06:
	cbz	r0, .L08000b12
	movs	r0, #5
.L08000b0a:
	ldr	r1, [r6]
	strb	r0, [r1, #8]		@ store the new state
.L08000b0e:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L08000b12:
	ldr	r1, [r6]
	movs	r0, #6
	strb	r0, [r1, #8]		@ state 6
	ldr	r1, .L08000b3c		@ USB_BUFTAB (0x40005C50)
	movs	r0, #0
	ldr	r1, [r1]
	ldr	r2, .L08000b40		@ packet memory base 0x40006000
	lsls	r1, r1, #0x10
	add.w	r1, r2, r1, lsr #15	@ packet memory + 2 * (index & 0xffff)
	str	r0, [r1, #4]		@ clear the word at +4
	strh.w	r7, [r8]		@ 0x2000007C = 0x30
	b.n	.L08000b0e
	.short	0x0000			@ padding
.L08000b30:
	.word	0x2000006c
.L08000b34:
	.word	0x2000007c
.L08000b38:
	.word	0x2000007a
.L08000b3c:
	.word	0x40005c50
.L08000b40:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_08000b44 - process a received control-transfer setup request (endpoint 0).
@ The request packet is addressed by the pointer at 0x2000006C: byte +0 is
@ the request type (bit 7 = direction, bits 0..6 = type/recipient), byte +1
@ the request code, +2 and +4 hold the value and index fields, +6 the length;
@ the same block holds +0x08 state byte, +0x10 remaining length, +0x12
@ transferred length, +0x14 packet size, +0x18 data handler pointer.
@ The pointer at 0x20000070 addresses a table of function pointers: +0x10
@ default request handler, +0x18 and +0x1c/+0x20/+0x24 handlers, +0x2c a byte
@ holding the packet size.
@ Request code 6 with type bits 0: sub-code (value byte +2) 1, 2 or 3 selects
@ the table entry +0x1c, +0x20 or +0x24 as handler. Request code 0 with
@ value 0, length 2, index byte 0: for recipient 1 the table entry +0x18 is
@ called with the index byte (accepted if it returns 0 and byte +10 is
@ nonzero), for recipient 2 the endpoint register at 0x40005C00 + 4 * (index
@ & 0xf) is tested (status bits 0x30 for an IN endpoint, 0x3000 for an OUT
@ endpoint) against the endpoint count byte at 0x200000E0; accepted requests
@ use fn_08002358. Request code 8 with type bits 0 uses fn_080022ec.
@ Request code 10 with recipient 1, byte +10 nonzero, value 0, index 0 and
@ length 1: table entry +0x18 is called and, when it returns 0, fn_08002330
@ is the handler.
@ A selected handler is stored at +0x18, the transferred length cleared, and
@ called with 0; otherwise the default handler (table +0x10) is called with
@ the request code, and a result of 3 sets state 9 and returns.
@ Then, by remaining length: 0xffff sets state 9; a result of 2 or length 0
@ sets state 8; a host-to-device request (bit 7 clear) sets state 3 and
@ stores 0x3000 to the halfword at 0x2000007A; for a device-to-host request
@ the length is limited to the request length (+6), and when it is shorter
@ than the request length the byte flag at 0x20000064 is set to 1 if it is an
@ exact multiple of the packet size and cleared if below the packet size.
@ The packet size (+0x14) is loaded from the byte at table +0x2c and
@ execution continues in fn_080009ec (endpoint 0 IN data stage).
@ ----------------------------------------------------------------------------
	.section .text.fn_08000b44,"ax",%progbits
	.p2align 2
	.global fn_08000b44
	.thumb_func
	.type fn_08000b44, %function
fn_08000b44:
	push	{r3, r4, r5, r6, r7, lr}
	ldr	r4, .L08000cbc		@ r4 = &pointer to request block (0x2000006C)
	ldr	r5, .L08000cc0		@ r5 = &pointer to handler table (0x20000070)
	movs	r6, #9
	ldr	r0, [r4]		@ r0 = request block
	movs	r7, #0
	ldr	r1, [r5]		@ r1 = handler table
	ldrb	r2, [r0, #1]		@ request code
	cmp	r2, #6
	beq.n	.L08000b64
	cbz	r2, .L08000b86
	cmp	r2, #8
	beq.n	.L08000bfa
	cmp	r2, #0xa
	beq.n	.L08000c04
	b.n	.L08000c3c
.L08000b64:
	ldrb	r2, [r0]
	lsls	r2, r2, #0x19		@ test the type bits 0..6
	bne.n	.L08000c3c
	ldrb	r0, [r0, #2]		@ sub-code
	cmp	r0, #1
	beq.n	.L08000b7a
	cmp	r0, #2
	beq.n	.L08000b7e
	cmp	r0, #3
	beq.n	.L08000b82
	b.n	.L08000c3c
.L08000b7a:
	ldr	r1, [r1, #0x1c]
	b.n	.L08000c2c
.L08000b7e:
	ldr	r1, [r1, #0x20]
	b.n	.L08000c2c
.L08000b82:
	ldr	r1, [r1, #0x24]
	b.n	.L08000c2c
.L08000b86:
	ldrh	r2, [r0, #2]
	cbnz	r2, .L08000bf8
	ldrh	r2, [r0, #6]
	cmp	r2, #2
	bne.n	.L08000c3c
	ldrb	r2, [r0, #4]
	cbnz	r2, .L08000bf8
	ldrb	r2, [r0]
	lsls	r3, r2, #0x19
	bne.n	.L08000b9e
	ldrh	r3, [r0, #4]
	cbz	r3, .L08000bac
.L08000b9e:
	and	r2, r2, #0x7f
	cmp	r2, #1
	beq.n	.L08000bb0
	cmp	r2, #2
	beq.n	.L08000bc4
	b.n	.L08000c3c
.L08000bac:
	ldr	r1, .L08000cc4		@ r1 = handler fn_08002358
	b.n	.L08000c2c
.L08000bb0:
	ldr	r2, [r1, #0x18]
	ldrb	r0, [r0, #5]
	movs	r1, #0
	blx	r2
	cbnz	r0, .L08000bf8
	ldr	r0, [r4]
	ldrb	r0, [r0, #0xa]
	cmp	r0, #0
	bne.n	.L08000bac
	b.n	.L08000c3c
.L08000bc4:
	ldrb	r1, [r0, #5]
	and	r0, r1, #0xf		@ endpoint number
	and	r2, r1, #0x70
	lsls	r3, r1, #0x18		@ sets N from bit 7 (direction)
	ldr	r1, .L08000cc8		@ r1 = 0x40005000
	add.w	r1, r1, r0, lsl #2
	ldr.w	r1, [r1, #0xc00]	@ endpoint register 0x40005C00 + 4 * number
	bpl.n	.L08000be4
	ubfx	r1, r1, #4, #2
	lsls	r1, r1, #4		@ IN endpoint: bits 0x30
	b.n	.L08000bea
.L08000be4:
	ubfx	r1, r1, #0xc, #2
	lsls	r1, r1, #0xc		@ OUT endpoint: bits 0x3000
.L08000bea:
	ldr	r3, .L08000ccc		@ r3 = 0x200000E0 (endpoint count byte)
	ldrb	r3, [r3]
	cmp	r3, r0
	bls.n	.L08000c3c
	cbnz	r2, .L08000bf8
	cmp	r1, #0
	bne.n	.L08000bac
.L08000bf8:
	b.n	.L08000c3c
.L08000bfa:
	ldrb	r0, [r0]
	lsls	r0, r0, #0x19
	bne.n	.L08000c3c
	ldr	r1, .L08000cd0		@ r1 = handler fn_080022ec
	b.n	.L08000c2c
.L08000c04:
	ldrb	r2, [r0]
	and	r2, r2, #0x7f
	cmp	r2, #1
	bne.n	.L08000c3c
	ldrb	r2, [r0, #0xa]
	cbz	r2, .L08000c3c
	ldrh	r2, [r0, #2]
	cbnz	r2, .L08000c3c
	ldrb	r2, [r0, #4]
	cbnz	r2, .L08000c3c
	ldrh	r2, [r0, #6]
	cmp	r2, #1
	bne.n	.L08000c3c
	ldr	r2, [r1, #0x18]
	ldrb	r0, [r0, #5]
	movs	r1, #0
	blx	r2
	cbnz	r0, .L08000c3c
	ldr	r1, .L08000cd4		@ r1 = handler fn_08002330
.L08000c2c:
	cbz	r1, .L08000c3c
	ldr	r0, [r4]
	strh	r7, [r0, #0x12]		@ transferred length = 0
	str	r1, [r0, #0x18]		@ remember the handler
	movs	r0, #0
	blx	r1
	movs	r0, #0
	b.n	.L08000c4a
.L08000c3c:
	ldr	r1, [r5]
	ldr	r0, [r4]
	ldr	r1, [r1, #0x10]		@ default request handler
	ldrb	r0, [r0, #1]
	blx	r1
	cmp	r0, #3
	beq.n	.L08000c72
.L08000c4a:
	ldr	r1, [r4]
	ldrh	r2, [r1, #0x10]		@ remaining length
	sub.w	r3, r2, #0xff00
	subs	r3, #0xff		@ zero when the length is 0xffff
	beq.n	.L08000c6e
	cmp	r0, #2
	beq.n	.L08000c78
	cbz	r2, .L08000c78
	ldrb	r0, [r1]
	lsls	r0, r0, #0x18
	bpl.n	.L08000cb0
	ldrh	r0, [r1, #6]
	str	r0, [sp]
	cmp	r2, r0
	bls.n	.L08000c80
	strh	r0, [r1, #0x10]
	b.n	.L08000ca0
.L08000c6e:
	strb	r6, [r1, #8]		@ state 9
	pop	{r3, r4, r5, r6, r7, pc}
.L08000c72:
	ldr	r0, [r4]
	strb	r6, [r0, #8]		@ state 9
	pop	{r3, r4, r5, r6, r7, pc}
.L08000c78:
	mov.w	r0, #8
	strb	r0, [r1, #8]		@ state 8
	pop	{r3, r4, r5, r6, r7, pc}
.L08000c80:
	bcs.n	.L08000ca0
	ldr	r0, [r5]
	ldr	r3, .L08000cd8		@ r3 = 0x20000064 (flag byte)
	ldrb.w	r0, [r0, #0x2c]		@ packet size
	cmp	r2, r0
	bcs.n	.L08000c92
	strb	r7, [r3]		@ below the packet size: clear the flag
	b.n	.L08000ca0
.L08000c92:
	udiv	r4, r2, r0
	mls	r0, r0, r4, r2		@ remainder of length / packet size
	cbnz	r0, .L08000ca0
	movs	r0, #1
	strb	r0, [r3]		@ exact multiple: set the flag
.L08000ca0:
	ldr	r0, [r5]
	ldrb.w	r0, [r0, #0x2c]
	strh	r0, [r1, #0x14]		@ packet size
	pop.w	{r3, r4, r5, r6, r7, lr}
	b.w	fn_080009ec
.L08000cb0:
	movs	r0, #3
	strb	r0, [r1, #8]		@ state 3
	ldr	r1, .L08000cdc		@ r1 = 0x2000007A
	lsls	r0, r0, #0xc		@ 0x3000
	strh	r0, [r1]
	pop	{r3, r4, r5, r6, r7, pc}
.L08000cbc:
	.word	0x2000006c
.L08000cc0:
	.word	0x20000070
.L08000cc4:
	.word	fn_08002358
.L08000cc8:
	.word	0x40005000
.L08000ccc:
	.word	0x200000e0
.L08000cd0:
	.word	fn_080022ec
.L08000cd4:
	.word	fn_08002330
.L08000cd8:
	.word	0x20000064
.L08000cdc:
	.word	0x2000007a

@ ----------------------------------------------------------------------------
@ fn_080010e8 - handler: return a pointer or set a length of 1.
@ With r0 nonzero returns 0x200000E4. With r0 zero stores 1 to the halfword
@ at offset 0x10 (remaining length) of the state block addressed by the
@ pointer at 0x2000006C and returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_080010e8,"ax",%progbits
	.p2align 2
	.global fn_080010e8
	.thumb_func
	.type fn_080010e8, %function
fn_080010e8:
	cbz	r0, .L080010ee
	ldr	r0, .L080010fc		@ r0 = 0x200000E4
	bx	lr
.L080010ee:
	ldr	r1, .L08001100		@ r1 = &pointer to state block (0x2000006C)
	movs	r0, #1
	ldr	r1, [r1]
	strh	r0, [r1, #0x10]		@ remaining length = 1
	movs	r0, #0
	bx	lr
	.short	0x0000			@ padding
.L080010fc:
	.word	0x200000e4
.L08001100:
	.word	0x2000006c

@ ----------------------------------------------------------------------------
@ fn_080015cc - class request check (request code 0x21 in the low seven type
@ bits, argument 0xfe).
@ r0 = argument. The request block is addressed by the pointer at
@ 0x2000006C. If (type & 0x7f) == 0x21, r0 == 0xfe, the halfwords at +2 and
@ +4 are zero and the halfword at +6 equals 1: stores the address of
@ fn_080010e8 (0x080010E9) at +0x18, clears the halfword at +0x12, calls
@ fn_080010e8 and returns 0. Otherwise returns 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_080015cc,"ax",%progbits
	.p2align 2
	.global fn_080015cc
	.thumb_func
	.type fn_080015cc, %function
fn_080015cc:
	ldr	r1, .L08001604		@ r1 = &pointer to request block (0x2000006C)
	push	{lr}
	ldr	r1, [r1]
	ldrb	r2, [r1]
	and	r2, r2, #0x7f
	cmp	r2, #0x21
	bne.n	.L080015ee
	cmp	r0, #0xfe
	bne.n	.L080015ee
	ldrh	r0, [r1, #2]
	cbnz	r0, .L080015ee
	ldrh	r0, [r1, #4]
	cbnz	r0, .L080015ee
	ldrh	r0, [r1, #6]
	cmp	r0, #1
	beq.n	.L080015f2
.L080015ee:
	movs	r0, #2
	pop	{pc}
.L080015f2:
	ldr	r0, .L08001608		@ r0 = handler fn_080010e8
	str	r0, [r1, #0x18]
	movs	r0, #0
	strh	r0, [r1, #0x12]		@ transferred length = 0
	bl	fn_080010e8
	movs	r0, #0
	pop	{pc}
	.short	0x0000			@ padding
.L08001604:
	.word	0x2000006c
.L08001608:
	.word	fn_080010e8

@ ----------------------------------------------------------------------------
@ fn_0800160c - tail call: fn_08002314(r0, 0x200000F0). Passes the argument in
@ r0 unchanged and the address 0x200000F0 in r1.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800160c,"ax",%progbits
	.p2align 2
	.global fn_0800160c
	.thumb_func
	.type fn_0800160c, %function
fn_0800160c:
	ldr	r1, .L08001614		@ r1 = 0x200000F0
	b.w	fn_08002314
	.short	0x0000			@ padding
.L08001614:
	.word	0x200000f0

@ ----------------------------------------------------------------------------
@ fn_08001618 - tail call: fn_08002314(r0, 0x200000E8). Passes the argument in
@ r0 unchanged and the address 0x200000E8 in r1.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001618,"ax",%progbits
	.p2align 2
	.global fn_08001618
	.thumb_func
	.type fn_08001618, %function
fn_08001618:
	ldr	r1, .L08001620		@ r1 = 0x200000E8
	b.w	fn_08002314
	.short	0x0000			@ padding
.L08001620:
	.word	0x200000e8

@ ----------------------------------------------------------------------------
@ fn_08001624 - tail call with a table entry selected by an index byte.
@ The byte at offset 3 of the block addressed by the pointer at 0x2000006C is
@ the index. If it is above 5 returns 0. Otherwise tail calls
@ fn_08002314(r0, 0x20000128 + 8 * index).
@ ----------------------------------------------------------------------------
	.section .text.fn_08001624,"ax",%progbits
	.p2align 2
	.global fn_08001624
	.thumb_func
	.type fn_08001624, %function
fn_08001624:
	ldr	r1, .L0800163c		@ r1 = &pointer to block (0x2000006C)
	ldr	r1, [r1]
	ldrb	r1, [r1, #3]		@ index byte
	cmp	r1, #5
	bls.n	.L08001632
	movs	r0, #0
	bx	lr
.L08001632:
	ldr	r2, .L08001640		@ r2 = 0x20000128
	add.w	r1, r2, r1, lsl #3	@ r1 = 0x20000128 + 8 * index
	b.w	fn_08002314
.L0800163c:
	.word	0x2000006c
.L08001640:
	.word	0x20000128

@ ----------------------------------------------------------------------------
@ fn_08001644 - returns 2 if r1 is nonzero or r0 is nonzero, else 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001644,"ax",%progbits
	.p2align 2
	.global fn_08001644
	.thumb_func
	.type fn_08001644, %function
fn_08001644:
	cbnz	r1, .L0800164a
	cmp	r0, #0
	beq.n	.L0800164c
.L0800164a:
	movs	r0, #2
.L0800164c:
	bx	lr
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08001774 - empty function: returns at once.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001774,"ax",%progbits
	.global fn_08001774
	.thumb_func
	.type fn_08001774, %function
fn_08001774:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08001776 - empty function: returns at once.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001776,"ax",%progbits
	.global fn_08001776
	.thumb_func
	.type fn_08001776, %function
fn_08001776:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08001778 - clear the USB device interrupt state and enable the USB
@ interrupt sources.
@ Stores 0 to byte offset 10 of the block addressed by the pointer at
@ 0x2000006C, calls fn_08001a50, then stores 0 to USB_STS (0x40005C44), 0x9E00
@ to the halfword at 0x20000078 and 0x9E00 to USB_CTRL (0x40005C40), and
@ stores 0 to the word at 0x20000174.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001778,"ax",%progbits
	.p2align 2
	.global fn_08001778
	.thumb_func
	.type fn_08001778, %function
fn_08001778:
	ldr	r0, .L080017a0		@ r0 = &pointer to block (0x2000006C)
	push	{r4, lr}
	ldr	r0, [r0]
	movs	r4, #0
	strb	r4, [r0, #0xa]		@ byte at offset 10 = 0
	bl	fn_08001a50
	ldr	r0, .L080017a4		@ r0 = 0x40005C44 (USB_STS)
	str	r4, [r0]		@ USB_STS = 0
	ldr	r1, .L080017a8		@ r1 = 0x20000078
	mov.w	r0, #0x9e00
	strh	r0, [r1]		@ 0x20000078 = 0x9e00
	ldr	r1, .L080017a4
	.inst.n	0x1f09			@ subs r1, r1, #4 (r1 = 0x40005C40, USB_CTRL)
	str	r0, [r1]		@ USB_CTRL = 0x9e00
	ldr	r0, .L080017ac		@ r0 = 0x20000174
	str	r4, [r0]
	pop	{r4, pc}
	.short	0x0000			@ padding
.L080017a0:
	.word	0x2000006c
.L080017a4:
	.word	0x40005c44
.L080017a8:
	.word	0x20000078
.L080017ac:
	.word	0x20000174

@ ----------------------------------------------------------------------------
@ fn_0800197c - dispatch a standard setup request on endpoint 0.
@ The request block is addressed by the pointer at 0x2000006C: byte +0 request
@ type (bits 0..6 recipient), +1 request code, +2/+3 value bytes, +4 index,
@ +9 flag byte, +10 byte tested by the handlers, +8 state byte.
@ Recipient 0 (device): code 9 calls fn_080023ec; code 5 accepts a request
@ with value byte +3 below 0x80, byte +2 zero and index zero, the result being
@ the byte at +10; code 3 with value 1 and index 0 calls fn_08002424; code 1
@ with value 1, index 0 and bit 5 of the flag byte +9 set calls fn_080021f0.
@ Recipient 1 (interface): code 0xb calls fn_080024d0. Recipient 2 (endpoint):
@ code 1 calls fn_080021f0, code 3 calls fn_08002448.
@ A handler that returns zero ends in state 6, after clearing the packet
@ memory word at 0x40006004 + 2 * (USB_BUFTAB (0x40005C50) & 0xffff) and
@ storing 0x30 to 0x2000007C. Anything not handled is passed to the default
@ handler, table entry +0x14 of the table at the pointer 0x20000070, called
@ with the request code: result 3 gives state 9, nonzero gives state 8, zero
@ gives state 6 as above. The final state is stored at +8.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800197c,"ax",%progbits
	.p2align 2
	.global fn_0800197c
	.thumb_func
	.type fn_0800197c, %function
fn_0800197c:
	push	{r4, r5, r6, lr}
	ldr	r5, .L08001a3c		@ r5 = &pointer to request block (0x2000006C)
	ldr	r0, [r5]
	ldrb	r1, [r0]		@ request type
	ldrb	r4, [r0, #1]		@ request code
	lsls	r2, r1, #0x19
	beq.n	.L08001998
	and	r0, r1, #0x7f
	cmp	r0, #1
	beq.n	.L080019e4
	cmp	r0, #2
	beq.n	.L080019ee
	b.n	.L08001a04
.L08001998:
	cmp	r4, #9
	beq.n	.L080019aa
	cmp	r4, #5
	beq.n	.L080019b0
	cmp	r4, #3
	beq.n	.L080019c2
	cmp	r4, #1
	beq.n	.L080019d2
	b.n	.L08001a04
.L080019aa:
	bl	fn_080023ec
	b.n	.L08001a02
.L080019b0:
	ldrb	r1, [r0, #3]
	cmp	r1, #0x7f
	bhi.n	.L08001a14
	ldrb	r1, [r0, #2]
	cbnz	r1, .L08001a14
	ldrh	r1, [r0, #4]
	cbnz	r1, .L08001a14
	ldrb	r0, [r0, #0xa]
	b.n	.L08001a12
.L080019c2:
	ldrb	r1, [r0, #3]
	cmp	r1, #1
	bne.n	.L08001a04
	ldrh	r0, [r0, #4]
	cbnz	r0, .L08001a04
	bl	fn_08002424
	b.n	.L08001a02
.L080019d2:
	ldrb	r1, [r0, #3]
	cmp	r1, #1
	bne.n	.L08001a04
	ldrh	r1, [r0, #4]
	cbnz	r1, .L08001a04
	ldrb	r0, [r0, #9]
	lsls	r0, r0, #0x1a		@ test bit 5 of the flag byte
	bmi.n	.L080019f8
	b.n	.L08001a04
.L080019e4:
	cmp	r4, #0xb
	bne.n	.L08001a04
	bl	fn_080024d0
	b.n	.L08001a02
.L080019ee:
	cmp	r4, #1
	beq.n	.L080019f8
	cmp	r4, #3
	beq.n	.L080019fe
	b.n	.L08001a04
.L080019f8:
	bl	fn_080021f0
	b.n	.L08001a02
.L080019fe:
	bl	fn_08002448
.L08001a02:
	cbz	r0, .L08001a1c
.L08001a04:
	ldr	r1, .L08001a40		@ r1 = &pointer to handler table (0x20000070)
	mov	r0, r4
	ldr	r1, [r1]
	ldr	r1, [r1, #0x14]		@ default request handler
	blx	r1
	cmp	r0, #3
	beq.n	.L08001a18
.L08001a12:
	cbz	r0, .L08001a1c
.L08001a14:
	movs	r0, #8
	b.n	.L08001a34
.L08001a18:
	movs	r0, #9
	b.n	.L08001a34
.L08001a1c:
	ldr	r2, .L08001a44		@ r2 = 0x40005C50 (USB_BUFTAB)
	movs	r0, #6
	movs	r1, #0
	ldr	r2, [r2]
	ldr	r3, .L08001a48		@ r3 = packet memory base 0x40006000
	lsls	r2, r2, #0x10
	add.w	r2, r3, r2, lsr #15	@ packet memory + 2 * (value & 0xffff)
	str	r1, [r2, #4]		@ clear the word at +4
	ldr	r2, .L08001a4c		@ r2 = 0x2000007C
	movs	r1, #0x30
	strh	r1, [r2]
.L08001a34:
	ldr	r1, [r5]
	strb	r0, [r1, #8]		@ store the new state
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L08001a3c:
	.word	0x2000006c
.L08001a40:
	.word	0x20000070
.L08001a44:
	.word	0x40005c50
.L08001a48:
	.word	0x40006000
.L08001a4c:
	.word	0x2000007c

@ ----------------------------------------------------------------------------
@ fn_08001a50 - reset the USB device control state.
@ Stores 1 to USB_CTRL (0x40005C40), then 0 to USB_CTRL, 0 to USB_STS
@ (0x40005C44), 0x1C00 to the halfword at 0x20000078 and 0x1C00 to USB_CTRL.
@ Returns 0.
@ Slot build only: between USB_CTRL = 1 (PD cleared, FRST kept) and USB_CTRL = 0
@ (FRST cleared) a loop of 200 passes of subs / bne, at least 2 cycles each, so
@ at least 400 cycles (2.7 us at 144 MHz): the transceiver start-up time
@ tSTARTUP is 1 us (datasheet table 4-41). The stock build has no wait.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001a50,"ax",%progbits
	.p2align 2
	.global fn_08001a50
	.thumb_func
	.type fn_08001a50, %function
fn_08001a50:
	ldr	r0, .L08001a6c		@ r0 = 0x40005C40 (USB_CTRL)
	movs	r1, #1
	str	r1, [r0]		@ USB_CTRL = 1
.ifdef SLOT
	movs	r1, #200		@ wait passes (tSTARTUP)
.L08001a50_wait:
	subs	r1, r1, #1
	bne.n	.L08001a50_wait
.endif
	movs	r1, #0
	ldr	r2, .L08001a70		@ r2 = 0x20000078
	str	r1, [r0]		@ USB_CTRL = 0
	adds	r3, r0, #4		@ r3 = 0x40005C44 (USB_STS)
	str	r1, [r3]		@ USB_STS = 0
	mov.w	r1, #0x1c00
	strh	r1, [r2]		@ 0x20000078 = 0x1c00
	str	r1, [r0]		@ USB_CTRL = 0x1c00
	movs	r0, #0
	bx	lr
.ifdef SLOT
	.p2align 2			@ the literal words stay word aligned
.endif
.L08001a6c:
	.word	0x40005c40
.L08001a70:
	.word	0x20000078

@ ----------------------------------------------------------------------------
@ fn_08001c84 - USB power-state machine step.
@ r0 = new state (7 keeps the current state; any other value is stored to the
@ state byte at 0x2000017C). The countdown byte is at 0x2000017D; the word at
@ 0x20000180 is a flag. USB_CTRL is at 0x40005C40. A table branch on the
@ state byte (0..5; values from 6 up store state 6):
@  0: if the flag word is nonzero set state 5; else call fn_08001d14, state 6.
@  1: call fn_08001d14, state 4, flag word = 1.
@  2: countdown = 2, state 3.
@  3: decrement the countdown; at zero state 4.
@  4: USB_CTRL = (USB_CTRL & 0xffff) | 0x10, state 5, countdown = 10.
@  5: decrement the countdown; at zero USB_CTRL = (USB_CTRL & 0xffff) & ~0x10,
@     state 6, flag word = 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001c84,"ax",%progbits
	.p2align 2
	.global fn_08001c84
	.thumb_func
	.type fn_08001c84, %function
fn_08001c84:
	push	{r4, r5, r6, r7, lr}
	ldr	r2, .L08001d0c		@ r2 = 0x2000017C (state byte)
	cmp	r0, #7
	beq.n	.L08001c8e
	strb	r0, [r2]		@ store the new state
.L08001c8e:
	ldrb	r6, [r2]
	ldr	r3, .L08001d0c
	movs	r5, #6
	movs	r1, #5
	movs	r4, #4
	ldr	r0, .L08001d10		@ r0 = 0x40005C40 (USB_CTRL)
	cmp	r6, #6
	bcs.n	.L08001cb4
	tbb	[pc, r6]
.L08001ca2:
	.byte	(.L08001ca8 - .L08001ca2)/2
	.byte	(.L08001cb8 - .L08001ca2)/2
	.byte	(.L08001cc2 - .L08001ca2)/2
	.byte	(.L08001ccc - .L08001ca2)/2
	.byte	(.L08001cdc - .L08001ca2)/2
	.byte	(.L08001cee - .L08001ca2)/2
.L08001ca8:
	ldr	r0, [r3, #4]		@ flag word (0x20000180)
	cbz	r0, .L08001cb0
	strb	r1, [r2]		@ state 5
	pop	{r4, r5, r6, r7, pc}
.L08001cb0:
	bl	fn_08001d14
.L08001cb4:
	strb	r5, [r2]		@ state 6
	pop	{r4, r5, r6, r7, pc}
.L08001cb8:
	bl	fn_08001d14
	strb	r4, [r2]		@ state 4
	movs	r0, #1
	b.n	.L08001d08
.L08001cc2:
	movs	r0, #2
	strb	r0, [r2, #1]		@ countdown = 2
	movs	r0, #3
	strb	r0, [r2]		@ state 3
.L08001cca:
	pop	{r4, r5, r6, r7, pc}
.L08001ccc:
	ldrb	r0, [r2, #1]
	.inst.n	0x1e40			@ subs r0, r0, #1
	strb	r0, [r2, #1]
	ldrb	r0, [r2, #1]
	cmp	r0, #0
	bne.n	.L08001cca
	strb	r4, [r2]		@ state 4
	pop	{r4, r5, r6, r7, pc}
.L08001cdc:
	ldr	r3, [r0]		@ USB_CTRL
	uxth	r3, r3
	orr	r3, r3, #0x10
	str	r3, [r0]
	strb	r1, [r2]		@ state 5
	movs	r0, #0xa
	strb	r0, [r2, #1]		@ countdown = 10
.L08001cec:
	pop	{r4, r5, r6, r7, pc}
.L08001cee:
	ldrb	r1, [r2, #1]
	.inst.n	0x1e49			@ subs r1, r1, #1
	strb	r1, [r2, #1]
	ldrb	r1, [r2, #1]
	cmp	r1, #0
	bne.n	.L08001cec
	ldr	r1, [r0]		@ USB_CTRL
	uxth	r1, r1
	bic	r1, r1, #0x10
	str	r1, [r0]
	strb	r5, [r2]		@ state 6
	movs	r0, #0
.L08001d08:
	str	r0, [r3, #4]		@ flag word (0x20000180)
	pop	{r4, r5, r6, r7, pc}
.L08001d0c:
	.word	0x2000017c
.L08001d10:
	.word	0x40005c40

@ ----------------------------------------------------------------------------
@ fn_08001d14 - clear bit 2 of USB_CTRL and write 0x9E00 to it.
@ Reads USB_CTRL (0x40005C40), keeps the low 16 bits, clears bit 2, stores
@ the result, then stores 0x9E00 to USB_CTRL.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001d14,"ax",%progbits
	.p2align 2
	.global fn_08001d14
	.thumb_func
	.type fn_08001d14, %function
fn_08001d14:
	ldr	r0, .L08001d28		@ r0 = 0x40005C40 (USB_CTRL)
	ldr	r1, [r0]
	uxth	r1, r1
	bic	r1, r1, #4
	str	r1, [r0]
	mov.w	r1, #0x9e00
	str	r1, [r0]
	bx	lr
.L08001d28:
	.word	0x40005c40

@ ----------------------------------------------------------------------------
@ fn_08002064 - update an endpoint register's OUT status field.
@ r0 = endpoint number, r1 = flags. The endpoint register is at
@ 0x40005C00 + 4 * r0 (USB_EPn). Reads it, clears all bits except those in
@ 0xBF8F, toggles bit 12 (0x1000) if bit 12 of r1 is set and bit 13 (0x2000)
@ if bit 13 of r1 is set, sets bits 0x8080 and writes the value back.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002064,"ax",%progbits
	.p2align 2
	.global fn_08002064
	.thumb_func
	.type fn_08002064, %function
fn_08002064:
	lsls	r2, r0, #2
	ldr	r0, .L08002090		@ r0 = 0x40005000
	add	r2, r0
	ldr.w	r0, [r2, #0xc00]	@ endpoint register 0x40005C00 + 4 * number
	movw	r3, #0xbf8f
	ands	r0, r3
	lsls	r3, r1, #0x13
	bpl.n	.L0800207c
	eor	r0, r0, #0x1000
.L0800207c:
	lsls	r1, r1, #0x12
	bpl.n	.L08002084
	eor	r0, r0, #0x2000
.L08002084:
	movw	r1, #0x8080
	orrs	r0, r1
	str.w	r0, [r2, #0xc00]
	bx	lr
.L08002090:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_08002094 - update an endpoint register's IN status field.
@ r0 = endpoint number, r1 = flags. The endpoint register is at
@ 0x40005C00 + 4 * r0 (USB_EPn). Reads it, clears all bits except those in
@ 0x8FBF, toggles bit 4 (0x10) if bit 4 of r1 is set and bit 5 (0x20) if bit
@ 5 of r1 is set, sets bits 0x8080 and writes the value back.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002094,"ax",%progbits
	.p2align 2
	.global fn_08002094
	.thumb_func
	.type fn_08002094, %function
fn_08002094:
	lsls	r2, r0, #2
	ldr	r0, .L080020c0		@ r0 = 0x40005000
	add	r2, r0
	ldr.w	r0, [r2, #0xc00]	@ endpoint register 0x40005C00 + 4 * number
	movw	r3, #0x8fbf
	ands	r0, r3
	lsls	r3, r1, #0x1b
	bpl.n	.L080020ac
	eor	r0, r0, #0x10
.L080020ac:
	lsls	r1, r1, #0x1a
	bpl.n	.L080020b4
	eor	r0, r0, #0x20
.L080020b4:
	movw	r1, #0x8080
	orrs	r0, r1
	str.w	r0, [r2, #0xc00]
	bx	lr
.L080020c0:
	.word	0x40005000

@ ----------------------------------------------------------------------------
@ fn_080021f0 - request handler for the device (0) and endpoint (2) recipients.
@ The request block is addressed by the pointer at 0x2000006C (+0 request
@ type, +2 value, +4 index byte, +5 endpoint byte, +9 flag byte, +10 byte
@ tested below). Recipient 0 (device): clears bit 5 (0x20) of the flag byte +9
@ and returns 0. Recipient 2 (endpoint) with value 0 and index byte 0: the
@ endpoint number is the low bits of byte +5 (bit 7 = IN). If the number is
@ below the count byte at 0x200000E0, the endpoint register
@ (0x40005C00 + 4 * number) has a nonzero status field (0x30 for IN, 0x3000
@ for OUT) and byte +10 is nonzero: for IN with field value 1, fn_080029a0 is
@ called with the number and fn_08002094(number, 0x30) updates the register;
@ for OUT with field value 1, endpoint 0 calls fn_08002f08(0, byte at
@ 0x20000124) while other endpoints call fn_08002978(number), and in both
@ cases the register becomes ((reg & 0xBF8F) ^ 0x3000) | 0x8080. Then the
@ function at table entry +0x14 of the table at the pointer 0x20000074 is
@ called, and 0 is returned. Every other case returns 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_080021f0,"ax",%progbits
	.p2align 2
	.global fn_080021f0
	.thumb_func
	.type fn_080021f0, %function
fn_080021f0:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r0, .L080022d8		@ r0 = &pointer to request block (0x2000006C)
	ldr	r0, [r0]
	ldrb	r1, [r0]
	ands	r1, r1, #0x7f		@ recipient
	beq.n	.L08002206
	cmp	r1, #2
	beq.n	.L08002210
	b.n	.L080022d4
.L08002206:
	ldrb	r1, [r0, #9]
	and	r1, r1, #0xdf		@ clear bit 5 of the flag byte
	strb	r1, [r0, #9]
	b.n	.L080022ae
.L08002210:
	ldrh	r1, [r0, #2]
	cmp	r1, #0
	bne.n	.L080022d4
	ldrb	r1, [r0, #4]
	cbnz	r1, .L08002298
	ldrb	r1, [r0, #5]		@ endpoint byte
	ldr	r5, .L080022e0		@ r5 = 0x40005000
	bic	r4, r1, #0x80		@ r4 = endpoint number
	lsls	r2, r1, #0x18		@ N = direction bit
	add.w	r2, r5, r4, lsl #2
	ldr	r3, .L080022dc		@ r3 = 0x200000E0 (endpoint count byte)
	ldr.w	r2, [r2, #0xc00]	@ endpoint register
	bpl.n	.L08002238
	ubfx	r2, r2, #4, #2
	lsls	r2, r2, #4		@ IN status field (0x30)
	b.n	.L0800223e
.L08002238:
	ubfx	r2, r2, #0xc, #2
	lsls	r2, r2, #0xc		@ OUT status field (0x3000)
.L0800223e:
	ldrb	r6, [r3]
	mov	r3, r4
	cmp	r6, r4
	bls.n	.L080022d4
	cbz	r2, .L08002298
	ldrb	r0, [r0, #0xa]
	cbz	r0, .L08002298
	lsls	r0, r1, #0x18
	lsl.w	r0, r4, #2
	bpl.n	.L08002272
	add	r0, r5
	ldr.w	r0, [r0, #0xc00]
	ubfx	r0, r0, #4, #2
	cmp	r0, #1
	bne.n	.L080022a6
	mov	r0, r3
	bl	fn_080029a0
	mov	r0, r4
	movs	r1, #0x30
	bl	fn_08002094
	b.n	.L080022a6
.L08002272:
	adds	r6, r0, r5		@ r6 = 0x40005000 + 4 * number
	ldr.w	r0, [r6, #0xc00]
	ubfx	r0, r0, #0xc, #2
	cmp	r0, #1
	bne.n	.L080022a6
	movw	r7, #0xbf8f
	movw	r8, #0x8080
	cbz	r4, .L080022b4
	mov	r0, r3
	bl	fn_08002978
	ldr.w	r0, [r6, #0xc00]
	ands	r0, r7
	b.n	.L0800229a
.L08002298:
	b.n	.L080022d4
.L0800229a:
	eor	r0, r0, #0x3000
	orr.w	r0, r0, r8
	str.w	r0, [r6, #0xc00]
.L080022a6:
	ldr	r0, .L080022e4		@ r0 = &pointer to handler table (0x20000074)
	ldr	r0, [r0]
	ldr	r0, [r0, #0x14]
	blx	r0
.L080022ae:
	movs	r0, #0
.L080022b0:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L080022b4:
	ldr	r0, .L080022e8		@ r0 = 0x200000F8
	ldrb.w	r1, [r0, #0x2c]		@ byte at 0x20000124
	movs	r0, #0
	bl	fn_08002f08
	ldr.w	r0, [r5, #0xc00]	@ endpoint 0 register (0x40005C00)
	ands	r0, r7
	eor	r0, r0, #0x3000
	orr.w	r0, r0, r8
	str.w	r0, [r5, #0xc00]
	b.n	.L080022a6
.L080022d4:
	movs	r0, #2
	b.n	.L080022b0
.L080022d8:
	.word	0x2000006c
.L080022dc:
	.word	0x200000e0
.L080022e0:
	.word	0x40005000
.L080022e4:
	.word	0x20000074
.L080022e8:
	.word	0x200000f8

@ ----------------------------------------------------------------------------
@ fn_080022ec - data handler that returns the address of the byte at offset 10.
@ r0 = 0: stores 1 to the halfword at offset 0x10 (remaining length) of the
@ block addressed by the pointer at 0x2000006C and returns 0.
@ r0 nonzero: calls the function at word 0 of the table addressed by the
@ pointer at 0x20000074, then returns the block address + 10.
@ ----------------------------------------------------------------------------
	.section .text.fn_080022ec,"ax",%progbits
	.p2align 2
	.global fn_080022ec
	.thumb_func
	.type fn_080022ec, %function
fn_080022ec:
	push	{r4, lr}
	ldr	r4, .L0800230c		@ r4 = &pointer to block (0x2000006C)
	cbz	r0, .L08002300
	ldr	r0, .L08002310		@ r0 = &pointer to table (0x20000074)
	ldr	r0, [r0]
	ldr	r0, [r0]
	blx	r0
	ldr	r0, [r4]
	adds	r0, #0xa
	pop	{r4, pc}
.L08002300:
	ldr	r1, [r4]
	movs	r0, #1
	strh	r0, [r1, #0x10]		@ remaining length = 1
	movs	r0, #0
	pop	{r4, pc}
	.short	0x0000			@ padding
.L0800230c:
	.word	0x2000006c
.L08002310:
	.word	0x20000074

@ ----------------------------------------------------------------------------
@ fn_08002314 - data provider for a transfer described by a two-field block.
@ r0 = 0 or nonzero, r1 = pointer to a block whose word 0 is a data address
@ and halfword at +4 a total length. The sent length is the halfword at
@ offset 0x12 of the block addressed by the pointer at 0x2000006C.
@ r0 nonzero: returns word 0 of r1 plus the sent length.
@ r0 = 0: stores (total length - sent length) to the halfword at offset 0x10
@ of that block and returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002314,"ax",%progbits
	.p2align 2
	.global fn_08002314
	.thumb_func
	.type fn_08002314, %function
fn_08002314:
	ldr	r2, .L0800232c		@ r2 = &pointer to block (0x2000006C)
	ldr	r3, [r2]
	ldrh	r2, [r3, #0x12]		@ sent length
	cbz	r0, .L08002322
	ldr	r0, [r1]
	add	r0, r2
	bx	lr
.L08002322:
	ldrh	r0, [r1, #4]
	subs	r0, r0, r2
	strh	r0, [r3, #0x10]		@ remaining length
	movs	r0, #0
	bx	lr
.L0800232c:
	.word	0x2000006c

@ ----------------------------------------------------------------------------
@ fn_08002330 - handler like fn_080022ec using table entry +8.
@ r0 = 0: stores 1 to the halfword at offset 0x10 of the block addressed by
@ the pointer at 0x2000006C and returns 0.
@ r0 nonzero: calls the function at table entry +8 of the table addressed by
@ the pointer at 0x20000074, then returns the block address + 12.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002330,"ax",%progbits
	.p2align 2
	.global fn_08002330
	.thumb_func
	.type fn_08002330, %function
fn_08002330:
	push	{r4, lr}
	ldr	r4, .L08002350		@ r4 = &pointer to block (0x2000006C)
	cbz	r0, .L08002344
	ldr	r0, .L08002354		@ r0 = &pointer to table (0x20000074)
	ldr	r0, [r0]
	ldr	r0, [r0, #8]
	blx	r0
	ldr	r0, [r4]
	adds	r0, #0xc
	pop	{r4, pc}
.L08002344:
	ldr	r1, [r4]
	movs	r0, #1
	strh	r0, [r1, #0x10]		@ remaining length = 1
	movs	r0, #0
	pop	{r4, pc}
	.short	0x0000			@ padding
.L08002350:
	.word	0x2000006c
.L08002354:
	.word	0x20000074

@ ----------------------------------------------------------------------------
@ fn_08002358 - handler returning a two-byte status value.
@ r0 = 0: stores 2 to the halfword at offset 0x10 of the block addressed by
@ the pointer at 0x2000006C and returns 0.
@ r0 nonzero: clears the halfword at 0x20000066, then by the recipient (low
@ seven bits of the request type): recipient 0 sets bit 1 from bit 5 and bit 0
@ from bit 6 of the flag byte at offset 9 (also writing the result back into
@ the byte at 0x20000066), then calls table entry +0x10 of the table at the
@ pointer 0x20000074; recipient 1 returns 0x20000066 at once; recipient 2
@ sets bit 0 of the byte at 0x20000066 when the endpoint's status field
@ (0x40005C00 + 4 * (byte +5 & 0xf); bits 5:4 for IN, bits 13:12 for OUT)
@ equals 1, then calls the same table entry; other recipients return 0.
@ Returns 0x20000066 after the call.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002358,"ax",%progbits
	.p2align 2
	.global fn_08002358
	.thumb_func
	.type fn_08002358, %function
fn_08002358:
	ldr	r1, .L080023dc		@ r1 = &pointer to block (0x2000006C)
	push	{r4, lr}
	ldr	r1, [r1]
	cbz	r0, .L0800237a
	ldr	r0, .L080023e0		@ r0 = 0x20000066 (status halfword)
	movs	r2, #0
	strh	r2, [r0]
	ldrb	r2, [r1]
	lsls	r3, r2, #0x19
	beq.n	.L08002382
	and	r2, r2, #0x7f
	cmp	r2, #1
	beq.n	.L080023a2
	cmp	r2, #2
	beq.n	.L080023a6
	b.n	.L0800237e
.L0800237a:
	movs	r0, #2
	strh	r0, [r1, #0x10]		@ remaining length = 2
.L0800237e:
	movs	r0, #0
	pop	{r4, pc}
.L08002382:
	ldrb	r1, [r1, #9]
	lsls	r2, r1, #0x1a		@ N = bit 5 of the flag byte
	ldrb	r2, [r0]
	bpl.n	.L08002390
	orr	r2, r2, #2
	b.n	.L08002394
.L08002390:
	and	r2, r2, #0xfd
.L08002394:
	lsls	r1, r1, #0x19		@ N = bit 6 of the flag byte
	strb	r2, [r0]
	uxtb	r1, r2
	bmi.n	.L080023c0
	and	r1, r1, #0xfe
	b.n	.L080023c4
.L080023a2:
	ldr	r0, .L080023e0
	pop	{r4, pc}
.L080023a6:
	ldrb	r2, [r1, #5]		@ endpoint byte
	lsls	r1, r2, #0x1c
	lsls	r3, r2, #0x18		@ N = direction bit
	ldr	r2, .L080023e4		@ r2 = 0x40005000
	add.w	r1, r2, r1, lsr #26	@ 4 * (endpoint & 0xf)
	ldr.w	r1, [r1, #0xc00]	@ endpoint register
	bpl.n	.L080023c8
	ubfx	r1, r1, #4, #2		@ IN status field
	b.n	.L080023cc
.L080023be:
	ldrb	r1, [r0]
.L080023c0:
	orr	r1, r1, #1
.L080023c4:
	strb	r1, [r0]
	b.n	.L080023d0
.L080023c8:
	ubfx	r1, r1, #0xc, #2	@ OUT status field
.L080023cc:
	cmp	r1, #1
	beq.n	.L080023be
.L080023d0:
	ldr	r0, .L080023e8		@ r0 = &pointer to table (0x20000074)
	ldr	r0, [r0]
	ldr	r0, [r0, #0x10]
	blx	r0
	b.n	.L080023a2
	.short	0x0000			@ padding
.L080023dc:
	.word	0x2000006c
.L080023e0:
	.word	0x20000066
.L080023e4:
	.word	0x40005000
.L080023e8:
	.word	0x20000074
