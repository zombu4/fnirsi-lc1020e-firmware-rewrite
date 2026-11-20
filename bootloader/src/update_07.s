@ update_07.s - update drive: SCSI command handlers, status/data replies, boot-sector and directory images, firmware file receive and flash write
@ Part of the FNIRSI LC1020E firmware rewrite: port of the stock bootloader (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08001db4 - send the reply data of a command that returns a sense-like
@ block (the 0x200001a1 block or the 0x2000019c block).
@ No parameters. The command block copy is at 0x200002f4: bit 0 of its byte
@ at +0x10 (0x20000304) and the byte at +0x13 (0x20000307, the requested
@ length) decide.
@   bit 0 set:   buffer 0x2000019c, length 5.
@   bit 0 clear: buffer 0x200001a1, length = the requested length limited to
@                0x24.
@ Then tail calls fn_08002854(buffer, length), which sends the data.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001db4,"ax",%progbits
	.p2align 2
	.global fn_08001db4
	.thumb_func
	.type fn_08001db4, %function
fn_08001db4:
	ldr	r1, .L08001dd0		@ r1 = 0x200002f4 (command block copy)
	ldrb	r0, [r1, #0x10]		@ byte at 0x20000304
	lsls	r0, r0, #0x1f		@ test bit 0
	beq.n	.L08001dc2
	ldr	r0, .L08001dd4		@ r0 = 0x2000019c
	movs	r1, #5			@ length 5
	b.n	.L08001dcc
.L08001dc2:
	ldrb	r1, [r1, #0x13]		@ requested length (0x20000307)
	ldr	r0, .L08001dd8		@ r0 = 0x200001a1
	cmp	r1, #0x24
	bls.n	.L08001dcc
	movs	r1, #0x24		@ limit the length to 0x24
.L08001dcc:
	b.w	fn_08002854		@ tail call fn_08002854(buffer, length)
.L08001dd0:
	.word	0x200002f4
.L08001dd4:
	.word	0x2000019c
.L08001dd8:
	.word	0x200001a1

@ ----------------------------------------------------------------------------
@ fn_08001ddc - fail the current command with a 'medium' sense pair and
@ report a failed status.
@ No parameters. In the command block copy at 0x200002f4 the word at +8
@ (0x200002fc, the transfer length) and the bit 7 of the byte at +0xc
@ (0x20000300, the data direction flag) choose the argument of fn_08000772:
@ 2 when the length is not 0 and bit 7 is clear, else 0.
@ Calls fn_08000772(argument), then fn_080021d0(5, 0x20) (stores the two
@ sense bytes), then tail calls fn_08002194(1, 0) (status 1 without data).
@ ----------------------------------------------------------------------------
	.section .text.fn_08001ddc,"ax",%progbits
	.p2align 2
	.global fn_08001ddc
	.thumb_func
	.type fn_08001ddc, %function
fn_08001ddc:
	ldr	r0, .L08001e08		@ r0 = 0x200002f4
	push	{r4, lr}
	ldr	r1, [r0, #8]		@ 0x200002fc
	cbz	r1, .L08001dea
	ldrb	r0, [r0, #0xc]		@ 0x20000300
	lsls	r0, r0, #0x18		@ test bit 7
	bpl.n	.L08001dee
.L08001dea:
	movs	r0, #0
	b.n	.L08001df0
.L08001dee:
	movs	r0, #2
.L08001df0:
	bl	fn_08000772
	movs	r1, #0x20
	movs	r0, #5
	bl	fn_080021d0		@ fn_080021d0(5, 0x20)
	movs	r1, #0
	pop.w	{r4, lr}
	movs	r0, #1
	b.w	fn_08002194		@ tail call fn_08002194(1, 0)
.L08001e08:
	.word	0x200002f4

@ ----------------------------------------------------------------------------
@ fn_08001e0c - send 8 bytes from the buffer at 0x200001c9.
@ No parameters. Tail calls fn_08002854(0x200001c9, 8).
@ ----------------------------------------------------------------------------
	.section .text.fn_08001e0c,"ax",%progbits
	.p2align 2
	.global fn_08001e0c
	.thumb_func
	.type fn_08001e0c, %function
fn_08001e0c:
	movs	r1, #8
	ldr	r0, .L08001e14		@ r0 = 0x200001c9
	b.w	fn_08002854		@ tail call fn_08002854(0x200001c9, 8)
.L08001e14:
	.word	0x200001c9

@ ----------------------------------------------------------------------------
@ fn_08001e18 - send 4 bytes from the buffer at 0x200001c5.
@ No parameters. Tail calls fn_08002854(0x200001c5, 4).
@ ----------------------------------------------------------------------------
	.section .text.fn_08001e18,"ax",%progbits
	.p2align 2
	.global fn_08001e18
	.thumb_func
	.type fn_08001e18, %function
fn_08001e18:
	movs	r1, #4
	ldr	r0, .L08001e20		@ r0 = 0x200001c5
	b.w	fn_08002854		@ tail call fn_08002854(0x200001c5, 4)
.L08001e20:
	.word	0x200001c5

@ ----------------------------------------------------------------------------
@ fn_08001e24 - handler of the read command (opcode 0x28): start or continue
@ a read transfer.
@ In: r0 = first block number, r1 = number of blocks (as parsed from the
@ command block). Returns nothing.
@ State byte at 0x20000184:
@   0:    checks the command with fn_08001d2c(0x28, r0, r1); when that
@         returns 0 the function returns. If bit 7 of the byte at 0x20000300
@         is clear it fails the command: fn_08000772(), fn_080021d0(5, 0x24),
@         fn_08002194(1, 1). If the bit is set it stores 2 in 0x20000184
@         and continues as for state 2.
@   2:    tail calls fn_08001bdc(r0, r1), which reads blocks of the update
@         drive and sends them.
@   other: returns at once.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001e24,"ax",%progbits
	.p2align 2
	.global fn_08001e24
	.thumb_func
	.type fn_08001e24, %function
fn_08001e24:
	push	{r4, r5, r6, lr}
	ldr	r4, .L08001e7c		@ r4 = 0x20000184
	mov	r5, r1
	mov	r6, r0
	ldrb	r1, [r4, #0]		@ state
	cbz	r1, .L08001e3e
	cmp	r1, #2
	bne.n	.L08001e78
	mov	r1, r5
.L08001e36:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001bdc		@ tail call fn_08001bdc(r0, r1)
.L08001e3e:
	mov	r1, r0
	mov	r2, r5
	movs	r0, #0x28
	bl	fn_08001d2c		@ fn_08001d2c(0x28, block, count)
	cmp	r0, #0
	beq.n	.L08001e78
	ldr	r0, .L08001e80		@ r0 = 0x200002f4
	ldrb	r0, [r0, #0xc]		@ 0x20000300
	lsls	r0, r0, #0x18		@ test bit 7
	mov.w	r0, #2			@ (does not change the flags)
	bpl.n	.L08001e60
	strb	r0, [r4, #0]		@ state = 2
	mov	r1, r5
	mov	r0, r6
	b.n	.L08001e36
.L08001e60:
	bl	fn_08000772
	movs	r1, #0x24
	movs	r0, #5
	bl	fn_080021d0		@ fn_080021d0(5, 0x24)
	pop.w	{r4, r5, r6, lr}
	movs	r1, #1
	mov	r0, r1
	b.w	fn_08002194		@ tail call fn_08002194(1, 1)
.L08001e78:
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L08001e7c:
	.word	0x20000184
.L08001e80:
	.word	0x200002f4

@ ----------------------------------------------------------------------------
@ fn_08001e84 - reply with the last block number and the block size (8 bytes,
@ big-endian), as the answer to a capacity query.
@ No parameters. Calls fn_0800159c(); when that returns non-zero it fails
@ the command: fn_080021d0(2, 0x3a), fn_08002194(1, 1), then tail calls
@ fn_08000772(0). Otherwise it stores (the word at 0x20000198 minus 1) as
@ four bytes, most significant first, at 0x200001e3..0x200001e6 and the word
@ at 0x20000194 as four bytes at 0x200001e7..0x200001ea, then tail calls
@ fn_08002854(0x200001e3, 8).
@ ----------------------------------------------------------------------------
	.section .text.fn_08001e84,"ax",%progbits
	.p2align 2
	.global fn_08001e84
	.thumb_func
	.type fn_08001e84, %function
fn_08001e84:
	push	{r4, lr}
	bl	fn_0800159c
	cbz	r0, .L08001ea6
	movs	r1, #0x3a
	movs	r0, #2
	bl	fn_080021d0		@ fn_080021d0(2, 0x3a)
	movs	r1, #1
	mov	r0, r1
	bl	fn_08002194		@ fn_08002194(1, 1)
	pop.w	{r4, lr}
	movs	r0, #0
	b.w	fn_08000772		@ tail call fn_08000772(0)
.L08001ea6:
	ldr	r0, .L08001ed8		@ r0 = 0x20000198
	ldr	r1, [r0, #0]
	ldr	r0, .L08001edc		@ r0 = 0x200001e3
	.inst.n	0x1e49			@ subs r1, r1, #1
	lsrs	r2, r1, #0x18
	strb	r2, [r0, #0]
	lsrs	r2, r1, #0x10
	strb	r2, [r0, #1]
	lsrs	r2, r1, #8
	strb	r2, [r0, #2]
	strb	r1, [r0, #3]
	ldr	r1, .L08001ee0		@ r1 = 0x20000194
	ldr	r1, [r1, #0]
	lsrs	r2, r1, #0x18
	strb	r2, [r0, #4]
	lsrs	r2, r1, #0x10
	strb	r2, [r0, #5]
	lsrs	r2, r1, #8
	strb	r2, [r0, #6]
	strb	r1, [r0, #7]
	pop.w	{r4, lr}
	movs	r1, #8
	b.w	fn_08002854		@ tail call fn_08002854(0x200001e3, 8)
.L08001ed8:
	.word	0x20000198
.L08001edc:
	.word	0x200001e3
.L08001ee0:
	.word	0x20000194

@ ----------------------------------------------------------------------------
@ fn_08001ee4 - reply with a 12-byte block of geometry values, big-endian.
@ No parameters. Calls fn_0800159c(); when that returns non-zero it fails
@ the command: fn_080021d0(2, 0x3a), fn_08002194(1, 1), then tail calls
@ fn_08000772(0). Otherwise it stores the word at 0x20000198 as four bytes,
@ most significant first, at 0x200001ef..0x200001f2, the word at 0x20000194
@ as its upper three bytes at 0x200001f4..0x200001f6, and then tail calls
@ fn_08002854(0x200001eb, 0xc). The bytes of the block that are not stored
@ here keep the values already in RAM.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001ee4,"ax",%progbits
	.p2align 2
	.global fn_08001ee4
	.thumb_func
	.type fn_08001ee4, %function
fn_08001ee4:
	push	{r4, lr}
	bl	fn_0800159c
	cbz	r0, .L08001f06
	movs	r1, #0x3a
	movs	r0, #2
	bl	fn_080021d0		@ fn_080021d0(2, 0x3a)
	movs	r1, #1
	mov	r0, r1
	bl	fn_08002194		@ fn_08002194(1, 1)
	pop.w	{r4, lr}
	movs	r0, #0
	b.w	fn_08000772		@ tail call fn_08000772(0)
.L08001f06:
	ldr	r0, .L08001f34		@ r0 = 0x20000198
	ldr	r1, [r0, #0]
	ldr	r0, .L08001f38		@ r0 = 0x200001eb
	lsrs	r2, r1, #0x18
	strb	r2, [r0, #4]		@ 0x200001ef
	lsrs	r2, r1, #0x10
	strb	r2, [r0, #5]
	lsrs	r2, r1, #8
	strb	r2, [r0, #6]
	strb	r1, [r0, #7]		@ 0x200001f2
	ldr	r1, .L08001f3c		@ r1 = 0x20000194
	ldr	r1, [r1, #0]
	lsrs	r2, r1, #0x10
	strb	r2, [r0, #9]		@ 0x200001f4
	lsrs	r2, r1, #8
	strb	r2, [r0, #0xa]
	strb	r1, [r0, #0xb]		@ 0x200001f6
	pop.w	{r4, lr}
	movs	r1, #0xc
	b.w	fn_08002854		@ tail call fn_08002854(0x200001eb, 0xc)
	.short	0x0000			@ padding
.L08001f34:
	.word	0x20000198
.L08001f38:
	.word	0x200001eb
.L08001f3c:
	.word	0x20000194

@ ----------------------------------------------------------------------------
@ fn_08001f40 - send the buffer at 0x200001d1, at most 0x12 bytes.
@ No parameters. The length is the requested length, the byte at 0x20000307
@ (command block copy 0x200002f4 + 0x13), limited to 0x12. Tail calls
@ fn_08002854(0x200001d1, length).
@ ----------------------------------------------------------------------------
	.section .text.fn_08001f40,"ax",%progbits
	.p2align 2
	.global fn_08001f40
	.thumb_func
	.type fn_08001f40, %function
fn_08001f40:
	ldr	r0, .L08001f50		@ r0 = 0x200002f4
	ldrb	r1, [r0, #0x13]		@ requested length
	cmp	r1, #0x12
	bls.n	.L08001f4a
	movs	r1, #0x12		@ limit to 0x12
.L08001f4a:
	ldr	r0, .L08001f54		@ r0 = 0x200001d1
	b.w	fn_08002854
.L08001f50:
	.word	0x200002f4
.L08001f54:
	.word	0x200001d1

@ ----------------------------------------------------------------------------
@ fn_08001f58 - report success: tail calls fn_08002194(0, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_08001f58,"ax",%progbits
	.p2align 2
	.global fn_08001f58
	.thumb_func
	.type fn_08001f58, %function
fn_08001f58:
	movs	r1, #1
	movs	r0, #0
	b.w	fn_08002194		@ tail call fn_08002194(0, 1)

@ ----------------------------------------------------------------------------
@ fn_08001f60 - handler of a command that needs the drive geometry.
@ No parameters. Calls fn_0800159c(); when it returns 0 it tail calls
@ fn_08002194(0, 1) (success). Otherwise it fails the command:
@ fn_080021d0(2, 0x3a), fn_08002194(1, 1), then tail calls fn_08000772(0).
@ The two bytes at the end are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001f60,"ax",%progbits
	.p2align 2
	.global fn_08001f60
	.thumb_func
	.type fn_08001f60, %function
fn_08001f60:
	push	{r4, lr}
	bl	fn_0800159c
	cbz	r0, .L08001f82
	movs	r1, #0x3a
	movs	r0, #2
	bl	fn_080021d0		@ fn_080021d0(2, 0x3a)
	movs	r1, #1
	mov	r0, r1
	bl	fn_08002194		@ fn_08002194(1, 1)
	pop.w	{r4, lr}
	movs	r0, #0
	b.w	fn_08000772		@ tail call fn_08000772(0)
.L08001f82:
	movs	r1, #1
	pop.w	{r4, lr}
	movs	r0, #0
	b.w	fn_08002194		@ tail call fn_08002194(0, 1)
	.short	0x0000			@ padding

@ ----------------------------------------------------------------------------
@ fn_08001f90 - handler of a command that is accepted only when the transfer
@ length is zero and a flag is clear.
@ No parameters. In the command block copy at 0x200002f4: the word at +8
@ (0x200002fc) must be 0 and bit 2 of the byte at +0x10 (0x20000304) must be
@ clear; then it tail calls fn_08002194(0, 1) (success). Otherwise it calls
@ fn_08000772(2), fn_080021d0(5, 0x24) and tail calls fn_08002194(1, 0)
@ (failed status without data).
@ The two bytes before the literal are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001f90,"ax",%progbits
	.p2align 2
	.global fn_08001f90
	.thumb_func
	.type fn_08001f90, %function
fn_08001f90:
	ldr	r0, .L08001fc0		@ r0 = 0x200002f4
	push	{r4, lr}
	ldr	r1, [r0, #8]
	cbnz	r1, .L08001fa4
	ldrb	r0, [r0, #0x10]
	lsls	r0, r0, #0x1d		@ test bit 2
	bmi.n	.L08001fa4
	movs	r1, #1
	movs	r0, #0
	b.n	.L08001fb6
.L08001fa4:
	movs	r0, #2
	bl	fn_08000772
	movs	r1, #0x24
	movs	r0, #5
	bl	fn_080021d0		@ fn_080021d0(5, 0x24)
	movs	r1, #0
	movs	r0, #1
.L08001fb6:
	pop.w	{r4, lr}
	b.w	fn_08002194		@ tail call fn_08002194(r0, r1)
	.short	0x0000			@ padding
.L08001fc0:
	.word	0x200002f4

@ ----------------------------------------------------------------------------
@ fn_08001fc4 - handler of the write command (opcode 0x2a): start or continue
@ a write transfer.
@ In: r0 = first block number, r1 = number of blocks. Returns nothing.
@ State byte at 0x20000184:
@   0:    checks the command with fn_08001d2c(0x2a, r0, r1); when that
@         returns 0 it returns. If bit 7 of the byte at 0x20000300 is set it
@         fails the command (fn_08000772(0), fn_080021d0(5, 0x24),
@         fn_08002194(1, 0)); otherwise it stores 1 in 0x20000184 and tail
@         calls fn_08002064(2, 0x3000) (starts the receive of the data).
@   1:    tail calls fn_0800302c(r0, r1), which collects the received data.
@   other: returns at once.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001fc4,"ax",%progbits
	.p2align 2
	.global fn_08001fc4
	.thumb_func
	.type fn_08001fc4, %function
fn_08001fc4:
	push	{r4, lr}
	ldr	r4, .L0800201c		@ r4 = 0x20000184
	ldrb	r2, [r4, #0]		@ state
	cbz	r2, .L08001fd8
	cmp	r2, #1
	bne.n	.L0800201a
	pop.w	{r4, lr}
	b.w	fn_0800302c		@ tail call fn_0800302c(r0, r1)
.L08001fd8:
	mov	r2, r1
	mov	r1, r0
	movs	r0, #0x2a
	bl	fn_08001d2c		@ fn_08001d2c(0x2a, block, count)
	cmp	r0, #0
	beq.n	.L0800201a
	ldr	r0, .L08002020		@ r0 = 0x200002f4
	ldrb	r0, [r0, #0xc]		@ 0x20000300
	lsls	r0, r0, #0x18		@ test bit 7
	bmi.n	.L08002000
	movs	r0, #1
	strb	r0, [r4, #0]		@ state = 1
	pop.w	{r4, lr}
	mov.w	r1, #0x3000
	movs	r0, #2
	b.w	fn_08002064		@ tail call fn_08002064(2, 0x3000)
.L08002000:
	movs	r0, #0
	bl	fn_08000772
	movs	r1, #0x24
	movs	r0, #5
	bl	fn_080021d0		@ fn_080021d0(5, 0x24)
	movs	r1, #0
	pop.w	{r4, lr}
	movs	r0, #1
	b.w	fn_08002194		@ tail call fn_08002194(1, 0)
.L0800201a:
	pop	{r4, pc}
.L0800201c:
	.word	0x20000184
.L08002020:
	.word	0x200002f4

@ ----------------------------------------------------------------------------
@ fn_08002194 - send the 13-byte status block that ends a command, and
@ optionally prepare the receive of the next command.
@ In: r0 = status byte, r1 = flag. Returns nothing.
@ Writes the signature 0x53425355 ("USBS") to 0x20000314 and the status
@ byte to 0x20000320 (offset 0xc of the block), calls fn_08002fe8(0x81,
@ 0x20000314, 0xd) to send the block and sets the state byte at 0x20000184
@ to 5. When the flag (r1) is not 0 it sets the state to 4 and tail calls
@ fn_08002094(1, 0x30).
@ ----------------------------------------------------------------------------
	.section .text.fn_08002194,"ax",%progbits
	.p2align 2
	.global fn_08002194
	.thumb_func
	.type fn_08002194, %function
fn_08002194:
	push	{r4, lr}
	mov	r4, r1
	ldr	r1, .L080021c8		@ r1 = 0x20000314
	ldr	r2, .L080021c4		@ r2 = 0x53425355
	str	r2, [r1, #0]
	strb	r0, [r1, #0xc]		@ status byte at 0x20000320
	movs	r2, #0xd
	movs	r0, #0x81
	bl	fn_08002fe8		@ fn_08002fe8(0x81, 0x20000314, 0xd)
	ldr	r0, .L080021cc		@ r0 = 0x20000184
	movs	r1, #5
	cmp	r4, #0
	strb	r1, [r0, #0]		@ state = 5
	beq.n	.L080021c2
	movs	r1, #4
	strb	r1, [r0, #0]		@ state = 4
	movs	r1, #0x30
	pop.w	{r4, lr}
	movs	r0, #1
	b.w	fn_08002094		@ tail call fn_08002094(1, 0x30)
.L080021c2:
	pop	{r4, pc}
.L080021c4:
	.word	0x53425355
.L080021c8:
	.word	0x20000314
.L080021cc:
	.word	0x20000184

@ ----------------------------------------------------------------------------
@ fn_080021d0 - store the two sense bytes.
@ In: r0 = byte stored to 0x200001d3, r1 = byte stored to 0x200001dd
@ (0x200001d1 + 2 and + 0xc). Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_080021d0,"ax",%progbits
	.p2align 2
	.global fn_080021d0
	.thumb_func
	.type fn_080021d0, %function
fn_080021d0:
	ldr	r2, .L080021d8		@ r2 = 0x200001d1
	strb	r0, [r2, #2]
	strb	r1, [r2, #0xc]
	bx	lr
.L080021d8:
	.word	0x200001d1

@ ----------------------------------------------------------------------------
@ fn_08002854 - send data to the host and arm the receive of the next packet.
@ In: r0 = buffer, r1 = length. Returns nothing.
@ Calls fn_08002fe8(0x81, buffer, length), fn_08002094(1, 0x30), sets the
@ state byte at 0x20000184 to 3, subtracts the length from the word at
@ 0x2000031c (0x20000314 + 8) and clears the byte at 0x20000320
@ (0x20000314 + 0xc). The two bytes before the literals are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08002854,"ax",%progbits
	.p2align 2
	.global fn_08002854
	.thumb_func
	.type fn_08002854, %function
fn_08002854:
	push	{r4, lr}
	mov	r4, r1
	mov	r2, r1
	mov	r1, r0
	movs	r0, #0x81
	bl	fn_08002fe8		@ fn_08002fe8(0x81, buffer, length)
	movs	r1, #0x30
	movs	r0, #1
	bl	fn_08002094		@ fn_08002094(1, 0x30)
	ldr	r1, .L08002880		@ r1 = 0x20000184
	movs	r0, #3
	strb	r0, [r1, #0]		@ state = 3
	ldr	r0, .L08002884		@ r0 = 0x20000314
	ldr	r1, [r0, #8]
	subs	r1, r1, r4
	str	r1, [r0, #8]		@ 0x2000031c -= length
	movs	r1, #0
	strb	r1, [r0, #0xc]		@ 0x20000320 = 0
	pop	{r4, pc}
	.short	0x0000			@ padding
.L08002880:
	.word	0x20000184
.L08002884:
	.word	0x20000314

@ ----------------------------------------------------------------------------
@ fn_0800302c - collect the data of a write transfer and write it to the
@ update drive.
@ In: r0 = first block number, r1 = number of blocks (used in phase 0 only).
@ Returns nothing.
@ State block at 0x200001f8: byte +0 = phase, +8 (0x20000200) = fill count of
@ the buffer 0x20000324, +0x14 (0x2000020c) = byte position, +0x18
@ (0x20000210) = bytes left, +0x20 (0x20000218) = bytes copied in this call.
@ The block size is the word at 0x20000194, the received packet size the
@ halfword at 0x20000186, the received packet is at 0x200002b4.
@ Phase 0: position = block size * r0, bytes left = block size * r1, phase 1.
@ Phase 1: copies the received packet into the buffer 0x20000324 (up to
@ 0x40 bytes more than the fill count held on entry), adds the packet size to
@ the position and subtracts it from the bytes left; when the bytes left are
@ a multiple of the block size it clears the fill count and calls
@ fn_080015c2(position - block size, 0x20000324, block size as 16 bits);
@ subtracts the packet size from the word at 0x2000031c and calls
@ fn_08002064(2, 0x3000) to receive the next packet.
@ Any other phase skips this step. When no bytes are left (or the state
@ byte at 0x20000184 is 4) it clears the fill count, calls fn_08002194(0, 1)
@ and sets the phase to 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800302c,"ax",%progbits
	.p2align 2
	.global fn_0800302c
	.thumb_func
	.type fn_0800302c, %function
fn_0800302c:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r4, .L080030e0		@ r4 = 0x200001f8 (state block)
	ldr	r2, [r4, #8]		@ fill count
	ldr	r3, .L080030e4		@ r3 = 0x20000194
	ldrb	r5, [r4, #0]		@ phase
	movs	r6, #0
	ldr	r3, [r3, #0]		@ block size
	adds	r2, #0x40		@ fill count + 0x40
	cbz	r5, .L08003046
	cmp	r5, #1
	beq.n	.L08003052
	b.n	.L080030c4
.L08003046:
	muls	r0, r3, r0		@ block size * first block
	muls	r1, r3, r1		@ block size * number of blocks
	strd	r0, r1, [r4, #0x14]	@ position, bytes left
	movs	r0, #1
	strb	r0, [r4, #0]		@ phase = 1
.L08003052:
	mov	r5, r6			@ copied = 0
	ldr	r1, .L080030e8		@ r1 = 0x200002b4 (received packet)
	ldr	r0, .L080030ec		@ r0 = 0x20000324 (buffer)
	mov	lr, r4
	str	r6, [r4, #0x20]
	b.n	.L08003074
.L0800305e:
	ldrb	r7, [r1, r5]		@ next received byte
	ldr.w	ip, [lr, #8]
	strb.w	r7, [r0, ip]		@ buffer[fill count] = byte
	ldr.w	r7, [lr, #8]
	.inst.n	0x1c7f			@ adds r7, r7, #1
	str.w	r7, [lr, #8]		@ fill count + 1
	.inst.n	0x1c6d			@ adds r5, r5, #1
.L08003074:
	ldr.w	r7, [lr, #8]
	cmp	r7, r2
	bcc.n	.L0800305e		@ until the fill count reaches the limit
	ldr	r7, .L080030f0		@ r7 = 0x20000186
	str.w	r5, [lr, #0x20]		@ bytes copied
	ldr.w	r1, [lr, #0x14]
	ldrh	r0, [r7, #0]		@ received packet size
	add	r1, r0			@ position += packet size
	str.w	r1, [lr, #0x14]
	ldr.w	r2, [lr, #0x18]
	subs	r0, r2, r0		@ bytes left -= packet size
	udiv	r2, r0, r3
	str.w	r0, [lr, #0x18]
	mls	r0, r3, r2, r0		@ bytes left modulo block size
	cbnz	r0, .L080030b0
	str.w	r6, [lr, #8]		@ fill count = 0
	subs	r0, r1, r3		@ position - block size
	uxth	r2, r3			@ block size as 16 bits
	ldr	r1, .L080030ec		@ r1 = 0x20000324
	bl	fn_080015c2		@ fn_080015c2(position - block size, buffer, size)
.L080030b0:
	ldr	r0, .L080030f4		@ r0 = 0x20000314
	ldrh	r2, [r7, #0]
	ldr	r1, [r0, #8]
	subs	r1, r1, r2
	str	r1, [r0, #8]		@ 0x2000031c -= packet size
	mov.w	r1, #0x3000
	movs	r0, #2
	bl	fn_08002064		@ fn_08002064(2, 0x3000)
.L080030c4:
	ldr	r0, [r4, #0x18]		@ bytes left
	cbz	r0, .L080030d0
	ldr	r0, .L080030f8		@ r0 = 0x20000184
	ldrb	r0, [r0, #0]
	cmp	r0, #4
	bne.n	.L080030dc
.L080030d0:
	str	r6, [r4, #8]		@ fill count = 0
	movs	r1, #1
	movs	r0, #0
	bl	fn_08002194		@ fn_08002194(0, 1)
	strb	r6, [r4, #0]		@ phase = 0
.L080030dc:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L080030e0:
	.word	0x200001f8
.L080030e4:
	.word	0x20000194
.L080030e8:
	.word	0x200002b4
.L080030ec:
	.word	0x20000324
.L080030f0:
	.word	0x20000186
.L080030f4:
	.word	0x20000314
.L080030f8:
	.word	0x20000184

@ ----------------------------------------------------------------------------
@ fn_08003b10 - take the directory entry of the file the host is writing.
@ In: r0 unused, r1 = pointer to the received directory sector, r2 = number
@ of valid bytes in it. Returns r2 unchanged (the byte count).
@ Starts at the third 32-byte entry of the sector (offset 0x40) and steps
@ over entries (at most 0x200 of them, while the offset is below the byte
@ count) until it finds one whose attribute byte (+0xb) is 0x20 and whose
@ next entry's attribute byte (+0x2b) is 0.
@ If such an entry exists: copies its 32 bytes (copy_bytes) to 0x20000230.
@ If the flag byte at 0x20000008 is 1, it clears the flag and, when the
@ word at 0x2000024c is not 0 and not above the byte count at 0x20000270,
@ clears the count at 0x20000270, sets the state byte at 0x20000274 to 2 and
@ prints "upgrade finish\n" with fn_080031ac. Then it clears the halfwords
@ at 0x20000246 and 0x20000248 and the word at 0x20000270.
@ If no such entry exists: fills 0x20000230 with 32 zero bytes (fill_bytes).
@ The two bytes before the literals are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003b10,"ax",%progbits
	.p2align 2
	.global fn_08003b10
	.thumb_func
	.type fn_08003b10, %function
fn_08003b10:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r5, r2
	movs	r0, #2			@ entry counter
	movs	r2, #0x40		@ offset of the entry
	lsls	r4, r0, #8		@ limit 0x200
	adds	r1, #0x40
	b.n	.L08003b30
.L08003b20:
	ldrb	r3, [r1, #0xb]		@ attribute
	cmp	r3, #0x20
	bne.n	.L08003b2c
	ldrb.w	r3, [r1, #0x2b]		@ attribute of the next entry
	cbz	r3, .L08003b3c
.L08003b2c:
	adds	r1, #0x20
	adds	r2, #0x20
.L08003b30:
	mov	r3, r0
	.inst.n	0x1c40			@ adds r0, r0, #1
	cmp	r3, r4
	bcs.n	.L08003b3c
	cmp	r2, r5
	bcc.n	.L08003b20
.L08003b3c:
	cmp	r0, r4
	bhi.n	.L08003b7e
	cmp	r2, r5
	bcs.n	.L08003b7e
	movs	r2, #0x20
	ldr	r0, .L08003b90		@ r0 = 0x20000230
	bl	copy_bytes		@ copy_bytes(0x20000230, entry, 0x20)
	ldr	r0, .L08003b94		@ r0 = 0x20000008
	ldr	r7, .L08003b90		@ r7 = 0x20000230
	movs	r4, #0
	ldrb	r1, [r0, #0]
	add.w	r6, r7, #0x20		@ r6 = 0x20000250
	cmp	r1, #1
	bne.n	.L08003b76
	strb	r4, [r0, #0]		@ flag = 0
	ldr	r0, [r7, #0x1c]		@ 0x2000024c
	cbz	r0, .L08003b76
	ldr	r1, [r6, #0x20]		@ 0x20000270
	cmp	r1, r0
	bcc.n	.L08003b76
	movs	r0, #2
	str	r4, [r6, #0x20]		@ 0x20000270 = 0
	strb.w	r0, [r6, #0x24]		@ 0x20000274 = 2
	adr	r0, .L08003b98
	bl	fn_080031ac		@ fn_080031ac("upgrade finish\n")
.L08003b76:
	strh	r4, [r7, #0x18]		@ 0x20000248 = 0
	strh	r4, [r7, #0x16]		@ 0x20000246 = 0
	str	r4, [r6, #0x20]		@ 0x20000270 = 0
	b.n	.L08003b88
.L08003b7e:
	movs	r2, #0x20
	movs	r1, #0
	ldr	r0, .L08003b90		@ r0 = 0x20000230
	bl	fill_bytes		@ fill_bytes(0x20000230, 0, 0x20)
.L08003b88:
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, pc}
	.short	0x0000			@ padding
.L08003b90:
	.word	0x20000230
.L08003b94:
	.word	0x20000008
.L08003b98:
	.asciz	"upgrade finish\n"

@ ----------------------------------------------------------------------------
@ fn_08003ba8 - set the flash partition words used by the update.
@ No parameters. Stores to RAM at 0x20000250: +0x00 = 0x08000000 (flash
@ base), +0x04 (0x20000254) = 0x08006000 (start of the application),
@ +0x1c (0x2000026c) = 0x08006000 (write pointer), +0x08 (0x20000258) =
@ 0x62000, +0x0c (0x2000025c) = 0x5c000 (largest file accepted), +0x10
@ (0x20000260) = 0x800 (erase block size), +0x14 (0x20000264) = 0x7ff (block
@ mask).
@ The two bytes before the literals are padding.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003ba8,"ax",%progbits
	.p2align 2
	.global fn_08003ba8
	.thumb_func
	.type fn_08003ba8, %function
fn_08003ba8:
	ldr	r0, .L08003bd0		@ r0 = 0x20000250
	mov.w	r1, #0x8000000
	str	r1, [r0, #0]
	ldr	r1, .L08003bd4		@ r1 = 0x08006000
	str	r1, [r0, #4]
	str	r1, [r0, #0x1c]
	mov.w	r1, #0x62000
	str	r1, [r0, #8]
	mov.w	r1, #0x5c000
	str	r1, [r0, #0xc]
	mov.w	r1, #0x800
	str	r1, [r0, #0x10]
	.inst.n	0x1e49			@ subs r1, r1, #1
	str	r1, [r0, #0x14]
	bx	lr
	.short	0x0000			@ padding
.L08003bd0:
	.word	0x20000250
.L08003bd4:
	.word	0x08006000

@ ----------------------------------------------------------------------------
@ fn_08003bd8 - build the content of one 0x800-byte sector of the update
@ drive for a read.
@ In: r0 = byte offset of the sector in the drive, r1 = destination buffer.
@ Returns r0 = 0x800.
@   offset 0:             copy_bytes(buffer, 0x20000014, 0x3e) (boot sector
@                         fields), zero fill of the rest, bytes 0x55 and
@                         0xaa at +0x1fe and +0x1ff.
@   offset 0x3000/0x3800: copy_bytes(buffer, d_08004464, 4), zero fill of
@                         the rest.
@   offset 0x4000:        copy_bytes(buffer, 0x20000014 + 0x3e, 0xb) (the
@                         volume label), then copy_bytes(buffer + 0xb,
@                         d_08004464 + 4, 0x2f), zero fill of the rest.
@   any other offset:     zero fill of the whole sector.
@ The zero fill is fill_bytes(destination, 0, count).
@ ----------------------------------------------------------------------------
	.section .text.fn_08003bd8,"ax",%progbits
	.p2align 2
	.global fn_08003bd8
	.thumb_func
	.type fn_08003bd8, %function
fn_08003bd8:
	push	{r4, r5, r6, lr}
	mov	r4, r1
	mov.w	r5, #0x800
	cbz	r0, .L08003bfa
	cmp.w	r0, #0x3000
	beq.n	.L08003c20
	cmp.w	r0, #0x3800
	beq.n	.L08003c20
	cmp.w	r0, #0x4000
	beq.n	.L08003c2c
	mov	r2, r5
	mov	r0, r1
	b.n	.L08003c4e
.L08003bfa:
	movs	r2, #0x3e
	ldr	r1, .L08003c58		@ r1 = 0x20000014
	mov	r0, r4
	bl	copy_bytes
	.inst.n	0x1c80			@ adds r0, r0, #2
	rsb.w	r2, r0, #0x800
	add	r0, r4
	movs	r1, #0
	bl	fill_bytes
	movs	r0, #0x55
	strb.w	r0, [r4, #0x1fe]
	movs	r0, #0xaa
	strb.w	r0, [r4, #0x1ff]
	b.n	.L08003c54
.L08003c20:
	movs	r2, #4
	ldr	r1, .L08003c5c		@ r1 = d_08004464
	mov	r0, r4
	bl	copy_bytes
	b.n	.L08003c48
.L08003c2c:
	ldr	r1, .L08003c58		@ r1 = 0x20000014
	movs	r2, #0xb
	adds	r1, #0x3e
	mov	r0, r4
	bl	copy_bytes
	ldr	r1, .L08003c5c		@ r1 = d_08004464
	mov	r6, r0
	adds	r0, r4, r6
	movs	r2, #0x2f
	.inst.n	0x1d09			@ adds r1, r1, #4
	bl	copy_bytes
	add	r0, r6
.L08003c48:
	rsb.w	r2, r0, #0x800
	add	r0, r4
.L08003c4e:
	movs	r1, #0
	bl	fill_bytes
.L08003c54:
	mov	r0, r5
	pop	{r4, r5, r6, pc}
.L08003c58:
	.word	0x20000014
.L08003c5c:
	.word	d_08004464

@ ----------------------------------------------------------------------------
@ fn_08003c60 - receive one write of file data on the update drive and
@ program it into flash.
@ In: r0 unused, r1 = pointer to the received data, r2 = its length.
@ Returns r0 = the length (the number of bytes taken), or 0 when the
@ transfer already finished or failed (state 2, from the common return).
@ RAM used: 0x20000008 (flag byte), 0x2000000c / 0x20000010 (first two words
@ of the file, saved while both are 0), 0x20000238 (extension of the file
@ name), 0x2000024c (file size), 0x2000025c (largest size), 0x2000026c (write
@ pointer), 0x20000270 (byte count), 0x20000274 (state byte).
@ Data is accepted when the extension is "BIN" or "bin", or the first word
@ has 2 in its top nibble and the second word has 8 in its top byte (a valid
@ stack pointer and reset vector).
@ State 2 returns 0. File size 0: it is set to the largest size and the
@ flag byte is set to 1. State 0: the write pointer is set to 0x08006000 and
@ the state to 1. For a file not above the largest size the length is cut so
@ that the count does not pass the file size, fn_08003d88(write pointer +
@ count, data, length) programs the data, the count is advanced and
@ fn_0800155c(0x94, 0x78, "%d%%", count * 100 / size) shows the progress.
@ On a programming failure the count is cleared and the state set to 3; when
@ the count reaches the file size the count is cleared, the state set to 2
@ and the saved words cleared.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003c60,"ax",%progbits
	.p2align 2
	.global fn_08003c60
	.thumb_func
	.type fn_08003c60, %function
fn_08003c60:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr	r5, .L08003d40		@ r5 = 0x20000008
	mov	r7, r1
	mov	r6, r2
	ldrd	r0, r1, [r5, #4]	@ 0x2000000c, 0x20000010
	orrs	r0, r1
	bne.n	.L08003c7a
	ldr	r0, [r7, #0]
	str	r0, [r5, #4]		@ save the first word
	ldr	r0, [r7, #4]
	str	r0, [r5, #8]		@ save the second word
.L08003c7a:
	ldr	r0, .L08003d48		@ r0 = 0x20000238
	movs	r2, #3
	adr	r1, .L08003d44		@ "BIN"
	mov	r4, r0
	bl	bytes_differ
	mov.w	r8, #2
	cbz	r0, .L08003caa
	movs	r2, #3
	adr	r1, .L08003d4c		@ "bin"
	mov	r0, r4
	bl	bytes_differ
	cbz	r0, .L08003caa
	ldr	r1, [r5, #4]
	cmp.w	r8, r1, lsr #28		@ top nibble of the first word = 2
	bne.n	.L08003d28
	ldr	r0, [r5, #8]
	movs	r1, #8
	cmp.w	r1, r0, lsr #24		@ top byte of the second word = 8
	bne.n	.L08003d28
.L08003caa:
	ldr	r4, .L08003d48		@ r4 = 0x20000238
	adds	r4, #0x18		@ r4 = 0x20000250
	ldrb.w	r2, [r4, #0x24]		@ state byte 0x20000274
	cmp	r2, #2
	beq.n	.L08003cc2
	sub.w	r0, r4, #0x20		@ r0 = 0x20000230
	movs	r1, #1
	ldr	r3, [r0, #0x1c]		@ file size 0x2000024c
	cbz	r3, .L08003cc8
	b.n	.L08003cce
.L08003cc2:
	movs	r0, #0
.L08003cc4:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L08003cc8:
	ldr	r3, [r4, #0xc]		@ largest size 0x2000025c
	str	r3, [r0, #0x1c]		@ file size = largest size
	strb	r1, [r5, #0]		@ flag byte = 1
.L08003cce:
	cbnz	r2, .L08003cd8
	ldr	r2, .L08003d50		@ r2 = 0x08006000
	str	r2, [r4, #0x1c]		@ write pointer
	strb.w	r1, [r4, #0x24]		@ state = 1
.L08003cd8:
	ldr	r1, [r4, #0xc]		@ largest size
	mov	r2, r3
	cmp	r1, r2
	bcc.n	.L08003d28		@ file larger than allowed
	ldr	r1, [r4, #0x20]		@ byte count
	mov	r9, r0
	adds	r3, r1, r6
	cmp	r3, r2
	bcc.n	.L08003cec
	subs	r6, r2, r1		@ cut the length to the rest of the file
.L08003cec:
	ldr	r0, [r4, #0x1c]
	mov	r2, r6
	add	r0, r1
	mov	r1, r7
	bl	fn_08003d88		@ fn_08003d88(pointer + count, data, length)
	mov	r10, r0
	ldr	r0, [r4, #0x20]
	movs	r1, #0x64
	add	r0, r6
	str	r0, [r4, #0x20]		@ count += length
	muls	r0, r1, r0		@ count * 100
	ldr.w	r1, [r9, #0x1c]		@ file size
	mov	r7, r9
	udiv	r3, r0, r1
	adr	r2, .L08003d54		@ "%d%%"
	movs	r1, #0x78
	movs	r0, #0x94
	bl	fn_0800155c		@ fn_0800155c(0x94, 0x78, "%d%%", percent)
	movs	r0, #0
	cmp.w	r10, #0
	beq.n	.L08003d2c
	str	r0, [r4, #0x20]		@ failure: count = 0
	movs	r0, #3
	strb.w	r0, [r4, #0x24]		@ state = 3
.L08003d28:
	mov	r0, r6
	b.n	.L08003cc4
.L08003d2c:
	ldr	r1, [r4, #0x20]
	ldr	r2, [r7, #0x1c]
	cmp	r1, r2
	bcc.n	.L08003d28
	str	r0, [r4, #0x20]		@ finished: count = 0
	strb.w	r8, [r4, #0x24]		@ state = 2
	str	r0, [r5, #4]		@ clear the saved words
	str	r0, [r5, #8]
	b.n	.L08003d28
.L08003d40:
	.word	0x20000008
.L08003d44:
	.asciz	"BIN"
.L08003d48:
	.word	0x20000238
.L08003d4c:
	.asciz	"bin"
.L08003d50:
	.word	0x08006000
.L08003d54:
	.asciz	"%d%%"
	.byte	0, 0, 0			@ padding

@ ----------------------------------------------------------------------------
@ fn_08003d5c - dispatch a write of the update drive by byte offset.
@ In: r0 = byte offset in the drive, r1 unused, r2 = length. Returns r0 = the
@ length (r2).
@ Offsets 0, 0x3000 and 0x3800 are ignored. Offset 0x4000 calls fn_08003b10
@ (directory entry). Offsets of 0x8800 and above call fn_08003c60 (file
@ data). All other offsets (including 0x8000..0x87ff) are ignored.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003d5c,"ax",%progbits
	.p2align 2
	.global fn_08003d5c
	.thumb_func
	.type fn_08003d5c, %function
fn_08003d5c:
	push	{r4, lr}
	mov	r4, r2
	cbz	r0, .L08003d7e
	cmp.w	r0, #0x3000
	beq.n	.L08003d7e
	cmp.w	r0, #0x3800
	beq.n	.L08003d7e
	cmp.w	r0, #0x4000
	beq.n	.L08003d82
	cmp.w	r0, #0x8800
	bcc.n	.L08003d7e
	bl	fn_08003c60
.L08003d7e:
	mov	r0, r4
	pop	{r4, pc}
.L08003d82:
	bl	fn_08003b10
	b.n	.L08003d7e

@ ----------------------------------------------------------------------------
@ fn_08003d88 - program data into flash.
@ In: r0 = destination address, r1 = source pointer, r2 = length in bytes.
@ Returns r0 = 1 when destination + length is beyond the flash window
@ (word 0x20000250 + word 0x20000258), else 0.
@ Partition words at 0x20000250: +0x10 (0x20000260) = erase block size,
@ +0x14 (0x20000264) = block mask.
@ When the destination has no bits of the mask set (is block aligned) it
@ unlocks the flash with fn_08000efc, erases whole blocks with fn_08000e24
@ (one call per block size, and one more for the remaining part), and locks
@ again with fn_08000ea4. Then it unlocks again, programs the data word by
@ word with fn_08000eb4(destination + i, word) for i = 0, 4, ... while i is
@ below the length, and locks with fn_08000ea4.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003d88,"ax",%progbits
	.p2align 2
	.global fn_08003d88
	.thumb_func
	.type fn_08003d88, %function
fn_08003d88:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr	r4, .L08003dfc		@ r4 = 0x20000250
	mov	r9, r1
	mov	r8, r0
	ldr	r1, [r4, #8]
	ldr	r0, [r4, #0]
	mov	r7, r2
	add	r0, r1			@ end of the flash window
	add.w	r1, r8, r7		@ end of the data
	mov	r5, r2
	mov	r6, r8
	cmp	r0, r1
	bcs.n	.L08003dac
	movs	r0, #1
.L08003da8:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L08003dac:
	ldr	r0, [r4, #0x14]
	tst	r0, r6
	bne.n	.L08003dda
	bl	fn_08000efc		@ unlock
	ldr	r0, [r4, #0x10]
	cmp	r0, r7
	bcc.n	.L08003dca
	b.n	.L08003dd0
.L08003dbe:
	mov	r0, r6
	bl	fn_08000e24		@ erase one block
	ldr	r0, [r4, #0x10]
	add	r6, r0
	subs	r5, r5, r0
.L08003dca:
	cmp	r0, r5
	bls.n	.L08003dbe
	cbz	r5, .L08003dd6
.L08003dd0:
	mov	r0, r6
	bl	fn_08000e24		@ erase the last block
.L08003dd6:
	bl	fn_08000ea4		@ lock
.L08003dda:
	mov	r5, r8
	bl	fn_08000efc		@ unlock
	movs	r4, #0
	b.n	.L08003df0
.L08003de4:
	ldr.w	r1, [r9, r4]		@ word to program
	adds	r0, r5, r4		@ address
	bl	fn_08000eb4		@ program one word
	.inst.n	0x1d24			@ adds r4, r4, #4
.L08003df0:
	cmp	r4, r7
	bcc.n	.L08003de4
	bl	fn_08000ea4		@ lock
	movs	r0, #0
	b.n	.L08003da8
.L08003dfc:
	.word	0x20000250
