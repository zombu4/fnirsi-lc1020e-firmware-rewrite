@ update_06.s - update-mode helpers: LED/state setter, SCSI command dispatcher, flash driver, update-drive handlers
@ Part of the FNIRSI LC1020E firmware rewrite: port of the stock bootloader (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08000772 - apply one of three presets to two helper calls.
@ In:  r0 = preset (0, 1 or 2). Returns nothing. Uses r4 (saved) as a holder
@      for the constant 0x1000.
@   0:    fn_08002094(1, 0x10), then return (tail call).
@   1:    fn_08002064(2, 0x1000) (tail call).
@   2:    fn_08002094(1, 0x10), then fn_08002064(2, 0x1000) (tail call).
@   other: nothing.
@ Both helpers take (r0 = index, r1 = value).
@ ----------------------------------------------------------------------------
	.section .text.fn_08000772,"ax",%progbits
	.global fn_08000772
	.thumb_func
	.type fn_08000772, %function
fn_08000772:
	push	{r4, lr}
	cbz	r0, .L08000796		@ preset 0
	mov.w	r4, #0x1000
	cmp	r0, #1
	beq.n	.L0800078a		@ preset 1
	cmp	r0, #2
	bne.n	.L080007a2		@ other: return
	movs	r1, #0x10		@ preset 2: first call
	movs	r0, #1
	bl	fn_08002094
.L0800078a:
	mov	r1, r4			@ r1 = 0x1000
	pop.w	{r4, lr}
	movs	r0, #2
	b.w	fn_08002064		@ tail call fn_08002064(2, 0x1000)
.L08000796:
	movs	r1, #0x10
	pop.w	{r4, lr}
	movs	r0, #1
	b.w	fn_08002094		@ tail call fn_08002094(1, 0x10)
.L080007a2:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08000834 - handle a received SCSI command block (USB mass-storage
@ update drive) and dispatch on its opcode.
@ Reads RAM 0x20000186 (16-bit length of the received data) and copies that
@ many bytes from 0x200002b4 to 0x200002f4 (command block copy: signature at
@ 0x200002f4, flags/length words at 0x200002f8 / 0x200002fc, opcode byte at
@ 0x20000303). Copies 0x200002f8 to 0x20000318 and 0x200002fc to 0x2000031c.
@ A length other than 0x1f: fn_08000772(2), clears the signature word at
@ 0x200002f4 and continues at the common ending with code 0x1a.
@ A length of 0x1f: if the opcode is 0x28 or 0x2a, builds a big-endian 32-bit
@ value from bytes 0x20000305..0x20000308 into 0x20000188 and a big-endian
@ 16-bit value from 0x2000030a into 0x2000018c. Then the signature must be
@ 0x43425355 ("USBC") and bytes at 0x20000301 / 0x20000302 must be 0 and 1..0x10,
@ else fn_08000772(2) and code 0x24; an unknown opcode gives fn_08000772(2)
@ and code 0x20. Opcodes (tail calls): 0x00 fn_08001f60, 0x03 fn_08001f40,
@ 0x04 fn_08001d8c, 0x12 fn_08001db4, 0x1a fn_08001e18, 0x1b / 0x1e fn_08001f58,
@ 0x23 fn_08001ee4, 0x25 fn_08001e84, 0x28 fn_08001e24(0x20000188, 0x2000018c),
@ 0x2a fn_08001fc4(0x20000188, 0x2000018c), 0x2f fn_08001f90, 0x5a fn_08001e0c;
@ opcodes 0x08, 0x0a, 0x15, 0x1d, 0x55, 0x88, 0x8a, 0x8f, 0x9e, 0xa8, 0xaa, 0xaf
@ all go to fn_08001ddc. The opcode 0x1a..0x23 range uses a tbb table.
@ Common ending: fn_080021d0(5, code), then tail call fn_08002194(1, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_08000834,"ax",%progbits
	.p2align 2
	.global fn_08000834
	.thumb_func
	.type fn_08000834, %function
fn_08000834:
	push	{r4, r5, r6, lr}
	ldr	r2, .L080009b4		@ r2 = 0x20000184
	ldr	r4, .L080009b8		@ r4 = 0x200002f4
	movs	r0, #0
	ldrh	r1, [r2, #2]		@ r1 = length at 0x20000186
	sub.w	r3, r4, #0x40		@ r3 = 0x200002b4
	b.n	.L0800084a
.L08000844:
	ldrb	r5, [r3, r0]
	strb	r5, [r4, r0]		@ copy byte
	.inst.n	0x1c40			@ adds r0, r0, #1
.L0800084a:
	mov	r5, r1			@ r5 = length
	cmp	r0, r1
	bcc.n	.L08000844
	ldr	r0, .L080009b8
	ldr	r3, [r4, #4]
	adds	r0, #0x20		@ r0 = 0x20000314
	cmp	r5, #0x1f
	str	r3, [r0, #4]		@ 0x20000318 = 0x200002f8
	ldr	r3, [r4, #8]
	str	r3, [r0, #8]		@ 0x2000031c = 0x200002fc
	beq.n	.L0800086e		@ length 0x1f: parse
	movs	r0, #2
	bl	fn_08000772
	movs	r0, #0
	movs	r1, #0x1a
	str	r0, [r4, #0]		@ clear the signature word
	b.n	.L080008ae
.L0800086e:
	ldrb	r0, [r4, #0xf]		@ opcode
	cmp	r0, #0x28
	beq.n	.L08000878
	cmp	r0, #0x2a
	bne.n	.L08000892
.L08000878:
	ldrh.w	r1, [r4, #0x11]
	ldrb	r3, [r4, #0x13]
	rev16	r1, r1
	lsls	r1, r1, #0x10
	orr.w	r1, r1, r3, lsl #8
	ldrb	r3, [r4, #0x14]
	orrs	r1, r3
	str	r1, [r2, #4]		@ 0x20000188 = big-endian value
	ldrh	r1, [r4, #0x16]
	rev16	r1, r1
	str	r1, [r2, #8]		@ 0x2000018c = big-endian 16-bit value
.L08000892:
	ldr	r3, .L080009bc		@ r3 = 0x43425355
	ldr	r1, [r4, #0]
	cmp	r1, r3
	bne.n	.L08000938		@ bad signature
	ldrb	r1, [r4, #0xd]
	cbnz	r1, .L080008a6
	ldrb	r1, [r4, #0xe]
	cbz	r1, .L080008a6
	cmp	r1, #0x10
	bls.n	.L080008c0
.L080008a6:
	movs	r0, #2
	bl	fn_08000772
	movs	r1, #0x24
.L080008ae:
	movs	r0, #5
	bl	fn_080021d0
	pop.w	{r4, r5, r6, lr}
	movs	r1, #0
	movs	r0, #1
	b.w	fn_08002194
.L080008c0:
	cmp	r0, #0x25
	beq.n	.L08000974
	bgt.n	.L080008fc
	cmp	r0, #0x15
	beq.n	.L080009ac
	bgt.n	.L080008e8
	cmp	r0, #8
	beq.n	.L080009ac
	bgt.n	.L080008de
	cbz	r0, .L08000942
	cmp	r0, #3
	beq.n	.L08000944
	cmp	r0, #4
	bne.n	.L08000938
	b.n	.L080009a4
.L080008de:
	cmp	r0, #0xa
	beq.n	.L080009ac
	cmp	r0, #0x12
	bne.n	.L08000938
	b.n	.L0800094c
.L080008e8:
	subs	r0, #0x1a		@ opcode 0x1a..0x23 -> index 0..9
	cmp	r0, #0xa
	bcs.n	.L08000938
	tbb	[pc, r0]
.L080008f2:
	.byte	(.L0800095c - .L080008f2)/2	@ 0x1a
	.byte	(.L08000954 - .L080008f2)/2	@ 0x1b
	.byte	(.L08000938 - .L080008f2)/2	@ 0x1c
	.byte	(.L080009ac - .L080008f2)/2	@ 0x1d
	.byte	(.L08000954 - .L080008f2)/2	@ 0x1e
	.byte	(.L08000938 - .L080008f2)/2	@ 0x1f
	.byte	(.L08000938 - .L080008f2)/2	@ 0x20
	.byte	(.L08000938 - .L080008f2)/2	@ 0x21
	.byte	(.L08000938 - .L080008f2)/2	@ 0x22
	.byte	(.L0800096c - .L080008f2)/2	@ 0x23
.L080008fc:
	cmp	r0, #0x8a
	beq.n	.L080009ac
	bgt.n	.L08000920
	cmp	r0, #0x55
	beq.n	.L080009ac
	bgt.n	.L08000916
	cmp	r0, #0x28
	beq.n	.L08000984
	cmp	r0, #0x2a
	beq.n	.L08000990
	cmp	r0, #0x2f
	bne.n	.L08000938
	b.n	.L0800099c
.L08000916:
	cmp	r0, #0x5a
	beq.n	.L08000964
	cmp	r0, #0x88
	bne.n	.L08000938
	b.n	.L080009ac
.L08000920:
	cmp	r0, #0xa8
	beq.n	.L080009ac
	bgt.n	.L08000930
	cmp	r0, #0x8f
	beq.n	.L080009ac
	cmp	r0, #0x9e
	bne.n	.L08000938
	b.n	.L080009ac
.L08000930:
	cmp	r0, #0xaa
	beq.n	.L080009ac
	cmp	r0, #0xaf
	beq.n	.L080009ac
.L08000938:
	movs	r0, #2			@ unknown opcode
	bl	fn_08000772
	movs	r1, #0x20
	b.n	.L080008ae
.L08000942:
	b.n	.L0800097c		@ opcode 0x00
.L08000944:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001f40		@ opcode 0x03
.L0800094c:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001db4		@ opcode 0x12
.L08000954:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001f58		@ opcodes 0x1b, 0x1e
.L0800095c:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001e18		@ opcode 0x1a
.L08000964:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001e0c		@ opcode 0x5a
.L0800096c:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001ee4		@ opcode 0x23
.L08000974:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001e84		@ opcode 0x25
.L0800097c:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001f60		@ opcode 0x00
.L08000984:
	ldrd	r0, r1, [r2, #4]
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001e24		@ opcode 0x28 (r0 = 0x20000188, r1 = 0x2000018c)
.L08000990:
	ldrd	r0, r1, [r2, #4]
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001fc4		@ opcode 0x2a
.L0800099c:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001f90		@ opcode 0x2f
.L080009a4:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001d8c		@ opcode 0x04
.L080009ac:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08001ddc		@ opcodes 0x08, 0x0a, 0x15, 0x1d, 0x55, ...
.L080009b4:
	.word	0x20000184
.L080009b8:
	.word	0x200002f4
.L080009bc:
	.word	0x43425355		@ command block signature

@ ----------------------------------------------------------------------------
@ fn_08000d90 - tail call to fn_080017cc (no arguments).
@ ----------------------------------------------------------------------------
	.section .text.fn_08000d90,"ax",%progbits
	.p2align 2
	.global fn_08000d90
	.thumb_func
	.type fn_08000d90, %function
fn_08000d90:
	b.w	fn_080017cc

@ ----------------------------------------------------------------------------
@ fn_08000d94 - tail call to fn_08001834 (no arguments).
@ ----------------------------------------------------------------------------
	.section .text.fn_08000d94,"ax",%progbits
	.p2align 2
	.global fn_08000d94
	.thumb_func
	.type fn_08000d94, %function
fn_08000d94:
	b.w	fn_08001834

@ ----------------------------------------------------------------------------
@ fn_08000e14 - OR a mask into FLASH_STS (0x4002200C).
@ In:  r0 = mask. Read-modify-write; the status flags are write-1-to-clear, so
@ the bits of the mask that are set are cleared (and the others are written
@ back as read). Returns nothing. Uses r1, r2.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000e14,"ax",%progbits
	.p2align 2
	.global fn_08000e14
	.thumb_func
	.type fn_08000e14, %function
fn_08000e14:
	ldr	r1, .L08000e20		@ r1 = 0x40022000 (flash interface)
	ldr	r2, [r1, #0xc]		@ FLASH_STS
	orrs	r2, r0
	str	r2, [r1, #0xc]
	bx	lr
	.short	0x0000			@ padding
.L08000e20:
	.word	0x40022000

@ ----------------------------------------------------------------------------
@ fn_08000e24 - erase one flash page.
@ In:  r0 = address of the page. Returns nothing.
@ Clears the status flags with fn_08000e14(0x7c) (bits 2..6), waits for the
@ flash to be idle with fn_08000f14(0xb0000) and, when that returned 6 (idle,
@ no error): sets PER (bit 1) in FLASH_CTRL (0x40022010), writes the address to
@ FLASH_ADD (0x40022014), sets START (bit 6), waits again with fn_08000f14
@ (0xb0000) and clears PER by and-ing FLASH_CTRL with 0x3ffd.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000e24,"ax",%progbits
	.p2align 2
	.global fn_08000e24
	.thumb_func
	.type fn_08000e24, %function
fn_08000e24:
	push	{r4, r5, r6, lr}
	mov	r5, r0			@ r5 = page address
	movs	r0, #0x7c
	bl	fn_08000e14
	mov.w	r6, #0xb0000		@ wait count
	mov	r0, r6
	bl	fn_08000f14
	cmp	r0, #6
	bne.n	.L08000e60
	ldr	r4, .L08000e64		@ r4 = 0x40022000
	ldr	r0, [r4, #0x10]
	orr.w	r0, r0, #2		@ PER
	str	r0, [r4, #0x10]
	str	r5, [r4, #0x14]		@ FLASH_ADD = address
	ldr	r0, [r4, #0x10]
	orr.w	r0, r0, #0x40		@ START
	str	r0, [r4, #0x10]
	mov	r0, r6
	bl	fn_08000f14
	ldr	r1, [r4, #0x10]
	movw	r2, #0x3ffd
	ands	r1, r2			@ clear PER
	str	r1, [r4, #0x10]
.L08000e60:
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L08000e64:
	.word	0x40022000

@ ----------------------------------------------------------------------------
@ fn_08000e68 - read FLASH_STS (0x4002200C) and return a state code in r0.
@ Tested in this order, the first set bit decides:
@   bit 0 (BUSY)  -> 1;  bit 2 (PGERR) -> 3;  bit 3 (PVERR) -> 4;
@   bit 4 (WRPERR) -> 5; bit 6 (EVERR) -> 7;  none of them -> 6.
@ FLASH_STS is read again for every test. Uses r1, r2.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000e68,"ax",%progbits
	.p2align 2
	.global fn_08000e68
	.thumb_func
	.type fn_08000e68, %function
fn_08000e68:
	ldr	r1, .L08000ea0		@ r1 = 0x40022000
	movs	r0, #6			@ default: no flag
	ldr	r2, [r1, #0xc]
	lsls	r2, r2, #0x1f
	beq.n	.L08000e76
	movs	r0, #1			@ BUSY
	bx	lr
.L08000e76:
	ldr	r2, [r1, #0xc]
	lsls	r2, r2, #0x1d
	bpl.n	.L08000e80
	movs	r0, #3			@ PGERR
	bx	lr
.L08000e80:
	ldr	r2, [r1, #0xc]
	lsls	r2, r2, #0x1c
	bpl.n	.L08000e8a
	movs	r0, #4			@ PVERR
	bx	lr
.L08000e8a:
	ldr	r2, [r1, #0xc]
	lsls	r2, r2, #0x1b
	bpl.n	.L08000e94
	movs	r0, #5			@ WRPERR
.L08000e92:
	bx	lr
.L08000e94:
	ldr	r1, [r1, #0xc]
	lsls	r1, r1, #0x19
	bpl.n	.L08000e92
	movs	r0, #7			@ EVERR
	bx	lr
	.short	0x0000			@ padding
.L08000ea0:
	.word	0x40022000

@ ----------------------------------------------------------------------------
@ fn_08000ea4 - set bit 7 (LOCK) in FLASH_CTRL (0x40022010), which locks the
@ flash control register again. Read-modify-write, returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000ea4,"ax",%progbits
	.p2align 2
	.global fn_08000ea4
	.thumb_func
	.type fn_08000ea4, %function
fn_08000ea4:
	ldr	r0, .L08000eb0		@ r0 = 0x40022000
	ldr	r1, [r0, #0x10]
	orr.w	r1, r1, #0x80
	str	r1, [r0, #0x10]
	bx	lr
.L08000eb0:
	.word	0x40022000

@ ----------------------------------------------------------------------------
@ fn_08000eb4 - program one 32-bit word into flash.
@ In:  r0 = address (must be word aligned), r1 = value.
@ Out: r0 = 9 when the address is not a multiple of 4; otherwise the state
@ code of the wait after programming (6 = done without error, see
@ fn_08000e68; fn_08000f14 returns 10 on a time-out). When the wait before
@ programming did not give 6, that code is returned and nothing is written.
@ Steps: fn_08000e14(0x7c) clears the error flags, fn_08000f14(0x2000) waits,
@ then PG (bit 0 of FLASH_CTRL, 0x40022010) is set, the word is stored to the
@ address, fn_08000f14(0x2000) waits, and PG is cleared (FLASH_CTRL and 0x3ffe).
@ ----------------------------------------------------------------------------
	.section .text.fn_08000eb4,"ax",%progbits
	.p2align 2
	.global fn_08000eb4
	.thumb_func
	.type fn_08000eb4, %function
fn_08000eb4:
	push	{r3, r4, r5, r6, r7, lr}
	mov	r5, r0			@ r5 = address
	movs	r0, #0
	str	r0, [sp, #0]
	mov	r6, r1			@ r6 = value
	lsls	r0, r5, #0x1e		@ test the low two address bits
	beq.n	.L08000ec6
	movs	r0, #9			@ not aligned
.L08000ec4:
	pop	{r3, r4, r5, r6, r7, pc}
.L08000ec6:
	movs	r0, #0x7c
	bl	fn_08000e14
	mov.w	r7, #0x2000		@ wait count
	mov	r0, r7
	bl	fn_08000f14
	cmp	r0, #6
	bne.n	.L08000ec4
	ldr	r4, .L08000ef8		@ r4 = 0x40022000
	ldr	r0, [r4, #0x10]
	orr.w	r0, r0, #1		@ PG
	str	r0, [r4, #0x10]
	str	r6, [r5, #0]		@ program the word
	mov	r0, r7
	bl	fn_08000f14
	ldr	r1, [r4, #0x10]
	movw	r2, #0x3ffe
	ands	r1, r2			@ clear PG
	str	r1, [r4, #0x10]
	pop	{r3, r4, r5, r6, r7, pc}
.L08000ef8:
	.word	0x40022000

@ ----------------------------------------------------------------------------
@ fn_08000efc - unlock the flash control register: writes the two key values
@ 0x45670123 and 0xCDEF89AB, in that order, to FLASH_KEY (0x40022004).
@ Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000efc,"ax",%progbits
	.p2align 2
	.global fn_08000efc
	.thumb_func
	.type fn_08000efc, %function
fn_08000efc:
	ldr	r0, .L08000f0c		@ r0 = 0x40022000
	ldr	r1, .L08000f08
	str	r1, [r0, #4]		@ first key
	ldr	r1, .L08000f10
	str	r1, [r0, #4]		@ second key
	bx	lr
.L08000f08:
	.word	0x45670123
.L08000f0c:
	.word	0x40022000
.L08000f10:
	.word	0xcdef89ab

@ ----------------------------------------------------------------------------
@ fn_08000f14 - wait until the flash is no longer busy, with a time-out.
@ In:  r0 = maximum number of polls. Out: r0 = state code of fn_08000e68
@ (anything but 1 ends the wait), or 10 when the count ran out first.
@ Calls fn_08000e68; while it returns 1 (BUSY) and the counter in r3 is not
@ zero, it decrements the counter and polls again.
@ ----------------------------------------------------------------------------
	.section .text.fn_08000f14,"ax",%progbits
	.p2align 2
	.global fn_08000f14
	.thumb_func
	.type fn_08000f14, %function
fn_08000f14:
	push	{lr}
	mov	r3, r0			@ r3 = poll counter
	bl	fn_08000e68
	b.n	.L08000f26
	.short	0xbf00			@ padding (nop)
.L08000f20:
	bl	fn_08000e68
	.inst.n	0x1e5b			@ subs r3, r3, #1
.L08000f26:
	cmp	r0, #1
	beq.n	.L08000f32		@ still busy
	cmp	r3, #0
	bne.n	.L08000f30
.L08000f2e:
	movs	r0, #0xa		@ time-out
.L08000f30:
	pop	{pc}
.L08000f32:
	cmp	r3, #0
	bne.n	.L08000f20
	b.n	.L08000f2e

@ ----------------------------------------------------------------------------
@ fn_0800159c - store the update-drive geometry in RAM and return 0.
@ Stores 0xc4 to 0x20000198, 0x800 to 0x20000194 and 0x62000 to 0x20000190.
@ Returns r0 = 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800159c,"ax",%progbits
	.p2align 2
	.global fn_0800159c
	.thumb_func
	.type fn_0800159c, %function
fn_0800159c:
	ldr	r0, .L080015b4		@ r0 = 0x20000190
	movs	r1, #0xc4
	str	r1, [r0, #8]		@ 0x20000198 = 0xc4
	mov.w	r1, #0x800
	str	r1, [r0, #4]		@ 0x20000194 = 0x800
	mov.w	r1, #0x62000
	str	r1, [r0, #0]		@ 0x20000190 = 0x62000
	movs	r0, #0
	bx	lr
	.short	0x0000			@ padding
.L080015b4:
	.word	0x20000190

@ ----------------------------------------------------------------------------
@ fn_080015b8 - call fn_08003bd8 and return 0.
@ Takes no arguments; the result of fn_08003bd8 is ignored.
@ ----------------------------------------------------------------------------
	.section .text.fn_080015b8,"ax",%progbits
	.global fn_080015b8
	.thumb_func
	.type fn_080015b8, %function
fn_080015b8:
	push	{r4, lr}
	bl	fn_08003bd8
	movs	r0, #0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_080015c2 - call fn_08003d5c and return 0.
@ Takes no arguments; the result of fn_08003d5c is ignored.
@ ----------------------------------------------------------------------------
	.section .text.fn_080015c2,"ax",%progbits
	.global fn_080015c2
	.thumb_func
	.type fn_080015c2, %function
fn_080015c2:
	push	{r4, lr}
	bl	fn_08003d5c
	movs	r0, #0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08001650 - check a received class request and start the update drive.
@ In:  r0 = request value. Out: r0 = 0 on success, 2 on failure.
@ The request pointer is the word at 0x2000006c. Succeeds only when
@ (first byte & 0x7f) == 0x21, r0 == 0xff and the halfwords at offsets 2, 4
@ and 6 are all zero. On success: fn_080029a0(1), fn_08002978(2), stores
@ 0x43425355 to 0x200002f4 and 0 to the byte at 0x20000184.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001650,"ax",%progbits
	.p2align 2
	.global fn_08001650
	.thumb_func
	.type fn_08001650, %function
fn_08001650:
	ldr	r1, .L08001690		@ r1 = 0x2000006c
	push	{r4, lr}
	ldr	r1, [r1, #0]		@ r1 = request pointer
	ldrb	r2, [r1, #0]
	and.w	r2, r2, #0x7f
	cmp	r2, #0x21
	bne.n	.L08001670
	cmp	r0, #0xff
	bne.n	.L08001670
	ldrh	r0, [r1, #2]
	cbnz	r0, .L08001670
	ldrh	r0, [r1, #4]
	cbnz	r0, .L08001670
	ldrh	r0, [r1, #6]
	cbz	r0, .L08001674
.L08001670:
	movs	r0, #2
	pop	{r4, pc}
.L08001674:
	movs	r0, #1
	bl	fn_080029a0
	movs	r0, #2
	bl	fn_08002978
	ldr	r1, .L08001698		@ r1 = 0x200002f4
	ldr	r0, .L08001694		@ r0 = 0x43425355
	str	r0, [r1, #0]
	ldr	r1, .L0800169c		@ r1 = 0x20000184
	movs	r0, #0
	strb	r0, [r1, #0]
	pop	{r4, pc}
	.short	0x0000			@ padding
.L08001690:
	.word	0x2000006c
.L08001694:
	.word	0x43425355
.L08001698:
	.word	0x200002f4
.L0800169c:
	.word	0x20000184

@ ----------------------------------------------------------------------------
@ fn_080016a0 - initialise the update drive endpoints and state. No arguments.
@ Clears the byte at 0x20000282 (0x20000278 + 0xa), stores the byte at
@ 0x080044ea + 7 into the byte at (word at 0x2000006c) + 9, then sets up the
@ endpoints with these helper calls (index, value):
@   fn_08002e90(0); fn_08002fa8(0, 0x200); fn_08002094(0, 0x20);
@   fn_08002ee8(0, 0x18); fn_08002f08(0, byte at 0x20000124);
@   fn_08002f6c(0, 0x58); fn_080029c8(0); fn_08002f48(0);
@   fn_08002fa8(1, 0); fn_08002f6c(1, 0x98); fn_08002094(1, 0x20);
@   fn_08002064(1, 0); fn_08002fa8(2, 0); fn_08002ee8(2, 0xd8);
@   fn_08002f08(2, byte at 0x200000f8); fn_08002064(2, 0x3000);
@   fn_08002094(2, 0); fn_08002ea0(0).
@ Finally stores 1 to 0x20000174, 0x43425355 to 0x200002f4 and 0 to the byte
@ at 0x20000184. Uses r4 (zero), r5 (pointer 0x20000124, then 0x200000f8 for
@ the second byte read; the first read is a pre-indexed ldrb at 0x200000f8 + 0x2c).
@ ----------------------------------------------------------------------------
	.section .text.fn_080016a0,"ax",%progbits
	.p2align 2
	.global fn_080016a0
	.thumb_func
	.type fn_080016a0, %function
fn_080016a0:
	push	{r4, r5, r6, lr}
	ldr	r0, .L08001754		@ r0 = 0x20000278
	movs	r4, #0
	ldr	r1, .L0800175c		@ r1 = 0x2000006c
	strb	r4, [r0, #0xa]		@ byte at 0x20000282 = 0
	ldr	r0, .L08001758		@ r0 = 0x080044ea
	ldr	r1, [r1, #0]
	ldrb	r0, [r0, #7]
	strb	r0, [r1, #9]
	mov	r0, r4
	bl	fn_08002e90
	mov.w	r1, #0x200
	movs	r0, #0
	bl	fn_08002fa8
	movs	r1, #0x20
	movs	r0, #0
	bl	fn_08002094
	movs	r1, #0x18
	movs	r0, #0
	bl	fn_08002ee8
	ldr	r5, .L08001760		@ r5 = 0x200000f8
	movs	r0, #0
	ldrb.w	r1, [r5, #0x2c]!	@ r5 = 0x20000124, r1 = byte there
	bl	fn_08002f08
	movs	r1, #0x58
	movs	r0, #0
	bl	fn_08002f6c
	movs	r0, #0
	bl	fn_080029c8
	movs	r0, #0
	bl	fn_08002f48
	movs	r1, #0
	movs	r0, #1
	bl	fn_08002fa8
	movs	r1, #0x98
	movs	r0, #1
	bl	fn_08002f6c
	movs	r1, #0x20
	movs	r0, #1
	bl	fn_08002094
	movs	r1, #0
	movs	r0, #1
	bl	fn_08002064
	movs	r1, #0
	movs	r0, #2
	bl	fn_08002fa8
	movs	r1, #0xd8
	movs	r0, #2
	bl	fn_08002ee8
	ldrb	r1, [r5, #0]		@ byte at 0x20000124
	movs	r0, #2
	bl	fn_08002f08
	mov.w	r1, #0x3000
	movs	r0, #2
	bl	fn_08002064
	movs	r1, #0
	movs	r0, #2
	bl	fn_08002094
	movs	r0, #0
	bl	fn_08002ea0
	ldr	r1, .L08001764		@ r1 = 0x20000174
	movs	r0, #1
	str	r0, [r1, #0]
	ldr	r1, .L0800176c		@ r1 = 0x200002f4
	ldr	r0, .L08001768		@ r0 = 0x43425355
	str	r0, [r1, #0]
	ldr	r0, .L08001770		@ r0 = 0x20000184
	strb	r4, [r0, #0]
	pop	{r4, r5, r6, pc}
.L08001754:
	.word	0x20000278
.L08001758:
	.word	d_080044ea
.L0800175c:
	.word	0x2000006c
.L08001760:
	.word	0x200000f8
.L08001764:
	.word	0x20000174
.L08001768:
	.word	0x43425355
.L0800176c:
	.word	0x200002f4
.L08001770:
	.word	0x20000184

@ ----------------------------------------------------------------------------
@ fn_080017b0 - if the word at 0x200002f4 is not 0x43425355, call
@ fn_08000772(2) (tail call); otherwise return. No arguments.
@ ----------------------------------------------------------------------------
	.section .text.fn_080017b0,"ax",%progbits
	.p2align 2
	.global fn_080017b0
	.thumb_func
	.type fn_080017b0, %function
fn_080017b0:
	ldr	r0, .L080017c4		@ r0 = 0x200002f4
	ldr	r1, .L080017c8		@ r1 = 0x43425355
	ldr	r0, [r0, #0]
	cmp	r0, r1
	beq.n	.L080017c0
	movs	r0, #2
	b.w	fn_08000772
.L080017c0:
	bx	lr
	.short	0x0000			@ padding
.L080017c4:
	.word	0x200002f4
.L080017c8:
	.word	0x43425355

@ ----------------------------------------------------------------------------
@ fn_080017cc - continue the update drive transfer according to the state
@ byte at 0x20000184. No arguments, returns nothing.
@   state 2: when the opcode byte at 0x20000303 is 0x28, tail call
@            fn_08001e24(word at 0x20000188, word at 0x2000018c).
@   state 3: fn_08002194(0, 1), then fn_08002064(2, 0x3000) (tail call).
@   state 4 or 5: clears the state byte, fn_08002064(2, 0x3000); when
@            fn_08002bdc(2) returns 0x1000, calls fn_08002064(2, 0x3000)
@            once more (tail call).
@   other: nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_080017cc,"ax",%progbits
	.p2align 2
	.global fn_080017cc
	.thumb_func
	.type fn_080017cc, %function
fn_080017cc:
	ldr	r0, .L0800182c		@ r0 = 0x20000184
	push	{r4, lr}
	ldrb	r1, [r0, #0]
	cmp	r1, #2
	beq.n	.L0800180a
	mov.w	r4, #0x3000
	cmp	r1, #3
	beq.n	.L0800181e
	cmp	r1, #4
	beq.n	.L080017e6
	cmp	r1, #5
	bne.n	.L08001828
.L080017e6:
	movs	r1, #0
	strb	r1, [r0, #0]		@ state = 0
	mov	r1, r4
	movs	r0, #2
	bl	fn_08002064
	movs	r0, #2
	bl	fn_08002bdc
	cmp.w	r0, #0x1000
	bne.n	.L08001828
.L080017fe:
	mov	r1, r4
	pop.w	{r4, lr}
	movs	r0, #2
	b.w	fn_08002064
.L0800180a:
	ldr	r1, .L08001830		@ r1 = 0x200002f4
	ldrb	r1, [r1, #0xf]		@ opcode byte at 0x20000303
	cmp	r1, #0x28
	bne.n	.L08001828
	ldr	r1, [r0, #8]
	ldr	r0, [r0, #4]
	pop.w	{r4, lr}
	b.w	fn_08001e24
.L0800181e:
	movs	r1, #1
	movs	r0, #0
	bl	fn_08002194
	b.n	.L080017fe
.L08001828:
	pop	{r4, pc}
	.short	0x0000			@ padding
.L0800182c:
	.word	0x20000184
.L08001830:
	.word	0x200002f4

@ ----------------------------------------------------------------------------
@ fn_08001834 - handle the data stage of a received command. No arguments.
@ Reads the opcode byte at 0x20000303, then stores the result of
@ fn_08002fc4(2, 0x200002b4) as a halfword at 0x20000186. Then on the state
@ byte at 0x20000184:
@   0: tail call fn_08000834 (parse the command block).
@   1: when the opcode is 0x2a, tail call fn_08001fc4(word at 0x20000188,
@      word at 0x2000018c); otherwise fn_08000772(1), fn_080021d0(5, 0x24),
@      tail call fn_08002194(2, 0).
@   other: fn_08000772(2), then the same fn_080021d0(5, 0x24) and
@      fn_08002194(2, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_08001834,"ax",%progbits
	.p2align 2
	.global fn_08001834
	.thumb_func
	.type fn_08001834, %function
fn_08001834:
	ldr	r0, .L08001888		@ r0 = 0x200002f4
	push	{r4, lr}
	ldrb	r4, [r0, #0xf]		@ opcode byte
	sub.w	r1, r0, #0x40		@ r1 = 0x200002b4
	movs	r0, #2
	bl	fn_08002fc4
	ldr	r2, .L0800188c		@ r2 = 0x20000184
	strh	r0, [r2, #2]		@ 0x20000186 = result
	ldrb	r0, [r2, #0]
	cbz	r0, .L08001854
	cmp	r0, #1
	beq.n	.L0800185c
	movs	r0, #2
	b.n	.L08001862
.L08001854:
	pop.w	{r4, lr}
	b.w	fn_08000834
.L0800185c:
	cmp	r4, #0x2a
	beq.n	.L0800187a
	movs	r0, #1
.L08001862:
	bl	fn_08000772
	movs	r1, #0x24
	movs	r0, #5
	bl	fn_080021d0
	movs	r1, #0
	pop.w	{r4, lr}
	movs	r0, #2
	b.w	fn_08002194
.L0800187a:
	ldrd	r0, r1, [r2, #4]
	pop.w	{r4, lr}
	b.w	fn_08001fc4
	.short	0x0000			@ padding
.L08001888:
	.word	0x200002f4
.L0800188c:
	.word	0x20000184

@ ----------------------------------------------------------------------------
@ fn_08001890 - when the byte at (word at 0x2000006c) + 10 is not zero, store
@ 5 to the word at 0x20000174, call fn_080029a0(1) and fn_08002978(2), and
@ clear the byte at 0x20000184. No arguments, returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001890,"ax",%progbits
	.p2align 2
	.global fn_08001890
	.thumb_func
	.type fn_08001890, %function
fn_08001890:
	ldr	r0, .L080018b8		@ r0 = 0x2000006c
	push	{r4, lr}
	ldr	r0, [r0, #0]
	ldrb	r0, [r0, #0xa]
	cmp	r0, #0
	beq.n	.L080018b4
	ldr	r1, .L080018bc		@ r1 = 0x20000174
	movs	r0, #5
	str	r0, [r1, #0]
	movs	r0, #1
	bl	fn_080029a0
	movs	r0, #2
	bl	fn_08002978
	ldr	r1, .L080018c0		@ r1 = 0x20000184
	movs	r0, #0
	strb	r0, [r1, #0]
.L080018b4:
	pop	{r4, pc}
	.short	0x0000			@ padding
.L080018b8:
	.word	0x2000006c
.L080018bc:
	.word	0x20000174
.L080018c0:
	.word	0x20000184

@ ----------------------------------------------------------------------------
@ fn_080018c4 - store 4 to the word at 0x20000174. No arguments, returns
@ nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_080018c4,"ax",%progbits
	.p2align 2
	.global fn_080018c4
	.thumb_func
	.type fn_080018c4, %function
fn_080018c4:
	ldr	r1, .L080018cc		@ r1 = 0x20000174
	movs	r0, #4
	str	r0, [r1, #0]
	bx	lr
.L080018cc:
	.word	0x20000174

@ ----------------------------------------------------------------------------
@ fn_08001bdc - read blocks of the update drive for a transfer in progress.
@ In:  r0 = first block number, r1 = number of blocks. Returns nothing.
@ State block at 0x200001f8: byte +0 = phase, word +4 (0x200001fc) = bytes
@ left in the current buffer, +0xc (0x20000204) = byte position, +0x10
@ (0x20000208) = bytes left in the transfer, +0x1c (0x20000214) = offset in
@ the buffer 0x20000324. The block size is the word at 0x20000194.
@ Phase 0: position = block size * r0, bytes left = block size * r1, phase = 1.
@ Phase 1: when the buffer is empty, calls fn_080015b8(position, 0x20000324,
@ block size as 16 bits), then sends 0x40 bytes with fn_08002fe8(0x81,
@ 0x20000324, 0x40) and sets the buffer count to the block size - 0x40;
@ otherwise sends the next 0x40 bytes at the offset (offset += 0x40, buffer
@ count -= 0x40). Then fn_08002f8c(1, 0x40), fn_08002094(1, 0x30), position
@ += 0x40, bytes left -= 0x40 and the word at 0x20000314 + 8 (0x2000031c) -= 0x40.
@ Any other phase skips this step. When no bytes are left it clears the state
@ block fields and sets the byte at 0x20000184 to 3.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001bdc,"ax",%progbits
	.p2align 2
	.global fn_08001bdc
	.thumb_func
	.type fn_08001bdc, %function
fn_08001bdc:
	push	{r4, r5, r6, lr}
	ldr	r4, .L08001c70		@ r4 = 0x200001f8
	ldr	r5, .L08001c74		@ r5 = 0x20000194
	ldrb	r3, [r4, #0]		@ phase
	ldr	r2, [r5, #0]		@ block size
	cbz	r3, .L08001bee
	cmp	r3, #1
	beq.n	.L08001bfa
	b.n	.L08001c3c
.L08001bee:
	muls	r0, r2, r0
	muls	r1, r2, r1
	strd	r0, r1, [r4, #0xc]
	movs	r0, #1
	strb	r0, [r4, #0]		@ phase = 1
.L08001bfa:
	ldr	r0, [r4, #4]
	cbz	r0, .L08001c52
	ldr	r0, .L08001c78		@ r0 = 0x20000324
	ldr	r1, [r4, #0x1c]
	movs	r2, #0x40
	add	r1, r0
	movs	r0, #0x81
	bl	fn_08002fe8
	ldr	r0, [r4, #4]
	subs	r0, #0x40
	str	r0, [r4, #4]
	ldr	r0, [r4, #0x1c]
	adds	r0, #0x40
.L08001c16:
	str	r0, [r4, #0x1c]
	movs	r1, #0x40
	movs	r0, #1
	bl	fn_08002f8c
	movs	r1, #0x30
	movs	r0, #1
	bl	fn_08002094
	ldr	r0, [r4, #0xc]
	adds	r0, #0x40
	str	r0, [r4, #0xc]
	ldr	r0, [r4, #0x10]
	subs	r0, #0x40
	str	r0, [r4, #0x10]
	ldr	r0, .L08001c7c		@ r0 = 0x20000314
	ldr	r1, [r0, #8]
	subs	r1, #0x40
	str	r1, [r0, #8]
.L08001c3c:
	ldr	r0, [r4, #0x10]
	cmp	r0, #0
	bne.n	.L08001c50
	str	r0, [r4, #4]
	str	r0, [r4, #0x1c]
	ldr	r2, .L08001c80		@ r2 = 0x20000184
	movs	r1, #3
	str	r0, [r4, #0xc]
	strb	r1, [r2, #0]		@ state = 3
	strb	r0, [r4, #0]		@ phase = 0
.L08001c50:
	pop	{r4, r5, r6, pc}
.L08001c52:
	uxth	r2, r2
	ldr	r1, .L08001c78
	ldr	r0, [r4, #0xc]
	bl	fn_080015b8
	movs	r2, #0x40
	ldr	r1, .L08001c78
	movs	r0, #0x81
	bl	fn_08002fe8
	ldr	r0, [r5, #0]
	subs	r0, #0x40
	str	r0, [r4, #4]
	movs	r0, #0x40
	b.n	.L08001c16
.L08001c70:
	.word	0x200001f8
.L08001c74:
	.word	0x20000194
.L08001c78:
	.word	0x20000324
.L08001c7c:
	.word	0x20000314
.L08001c80:
	.word	0x20000184

@ ----------------------------------------------------------------------------
@ fn_08001d2c - validate a read/write request against the drive size.
@ In:  r0 = opcode (0x2a or other), r1 = first block, r2 = block count.
@ Out: r0 = 1 when the request is valid, otherwise 0 after reporting the error.
@ When the word at 0x20000198 is below r1 + r2 (range too large): for opcode
@ 0x2a calls fn_08000772(2), then fn_08000772(0), error code 0x21.
@ Otherwise when the word at 0x200002fc equals the block size (word at
@ 0x20000194) times r2, returns 1. Otherwise calls fn_08000772(2) for opcode
@ 0x2a or fn_08000772(0) for the others, error code 0x24.
@ Error ending: fn_080021d0(5, code), fn_08002194(1, 0), returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08001d2c,"ax",%progbits
	.p2align 2
	.global fn_08001d2c
	.thumb_func
	.type fn_08001d2c, %function
fn_08001d2c:
	ldr	r3, .L08001d80		@ r3 = 0x20000198
	push	{r4, lr}
	ldr	r3, [r3, #0]
	add	r1, r2
	cmp	r1, r3
	bls.n	.L08001d4c
	cmp	r0, #0x2a
	bne.n	.L08001d42
	movs	r0, #2
	bl	fn_08000772
.L08001d42:
	movs	r0, #0
	bl	fn_08000772
	movs	r1, #0x21
	b.n	.L08001d66
.L08001d4c:
	ldr	r3, .L08001d88		@ r3 = 0x20000194
	ldr	r1, .L08001d84		@ r1 = 0x200002f4
	ldr	r3, [r3, #0]
	ldr	r1, [r1, #8]		@ word at 0x200002fc
	muls	r2, r3, r2
	cmp	r1, r2
	beq.n	.L08001d7c
	cmp	r0, #0x2a
	beq.n	.L08001d78
.L08001d5e:
	movs	r0, #0
.L08001d60:
	bl	fn_08000772
	movs	r1, #0x24
.L08001d66:
	movs	r0, #5
	bl	fn_080021d0
	movs	r1, #0
	movs	r0, #1
	bl	fn_08002194
	movs	r0, #0
	pop	{r4, pc}
.L08001d78:
	movs	r0, #2
	b.n	.L08001d60
.L08001d7c:
	movs	r0, #1
	pop	{r4, pc}
.L08001d80:
	.word	0x20000198
.L08001d84:
	.word	0x200002f4
.L08001d88:
	.word	0x20000194

@ ----------------------------------------------------------------------------
@ fn_08001d8c - handler for opcode 0x04. No arguments, returns nothing.
@ Calls fn_0800159c (sets the drive geometry). When it returns 0, returns.
@ Otherwise fn_080021d0(2, 0x3a), fn_08002194(1, 1) and a tail call to
@ fn_08000772(0).
@ ----------------------------------------------------------------------------
	.section .text.fn_08001d8c,"ax",%progbits
	.p2align 2
	.global fn_08001d8c
	.thumb_func
	.type fn_08001d8c, %function
fn_08001d8c:
	push	{r4, lr}
	bl	fn_0800159c
	cmp	r0, #0
	beq.n	.L08001db0
	movs	r1, #0x3a
	movs	r0, #2
	bl	fn_080021d0
	movs	r1, #1
	mov	r0, r1
	bl	fn_08002194
	pop.w	{r4, lr}
	movs	r0, #0
	b.w	fn_08000772
.L08001db0:
	pop	{r4, pc}
	.short	0x0000			@ padding
