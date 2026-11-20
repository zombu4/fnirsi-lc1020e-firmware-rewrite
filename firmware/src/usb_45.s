@ usb_45.s - USB device and mass-storage code: bulk-transfer state machine, control-request dispatcher, SCSI command dispatcher, flash-drive sector accessors
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080081c8 - selects which of two calls are made, from the selector in r0
@ (no return value).
@ r0 == 0: calls fn_0800ba1c(1, 0x10).
@ r0 == 1: calls fn_0800b9ec(2, 0x1000).
@ r0 == 2: calls fn_0800ba1c(1, 0x10), then fn_0800b9ec(2, 0x1000).
@ Any other value returns at once. Both calls are tail branches (b.w) after
@ the registers are restored. r4 holds 0x1000 for the second call.
@ ----------------------------------------------------------------------------
	.section .text.fn_080081c8,"ax",%progbits
	.global fn_080081c8
	.thumb_func
	.type fn_080081c8, %function
fn_080081c8:
	push	{r4, lr}
	cbz	r0, .L080081ec
	mov.w	r4, #0x1000
	cmp	r0, #1
	beq.n	.L080081e0
	cmp	r0, #2
	bne.n	.L080081f8
	movs	r1, #0x10
	movs	r0, #1
	bl	fn_0800ba1c
.L080081e0:
	mov	r1, r4
	pop.w	{r4, lr}
	movs	r0, #2
	b.w	fn_0800b9ec
.L080081ec:
	movs	r1, #0x10
	pop.w	{r4, lr}
	movs	r0, #1
	b.w	fn_0800ba1c
.L080081f8:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08008378 - handler of a received 31-byte command block of the mass-storage
@ class (bulk-only transport); no parameters, no return value. Every path ends
@ in a tail branch (b.w); the pop.w that restores r4, r5, r6 and lr is always
@ followed by one, and no instruction of the body pops pc.
@ r2 = 0x20000438, r4 = 0x200066b4. r1 = halfword 0x2000043a (the received
@ length). Copies r1 bytes (unsigned loop) from 0x20006674 to 0x200066b4 and
@ copies the words 0x200066b8 and 0x200066bc to 0x200066d8 and 0x200066dc.
@ Length != 0x1f: calls fn_080081c8(2), stores 0 to word 0x200066b4 and goes to
@ the error exit with r1 = 0x1a.
@ Length == 0x1f: r0 = byte 0x200066c3 (the command byte). When it is 0x28 or
@ 0x2a the big-endian 32-bit value of the bytes 0x200066c5..0x200066c8 (ldrh,
@ rev16, shift left 16, or with the bytes at +19 and +20) is stored at word
@ 0x2000043c and the big-endian halfword of the bytes 0x200066ca..0x200066cb
@ (rev16) at word 0x20000440.
@ The word 0x200066b4 must equal 0x43425355 (bytes 55 53 42 43, ASCII "USBC"),
@ else .L0800847c (calls fn_080081c8(2), r1 = 0x20, error
@ exit). Byte 0x200066c1 must be 0 and byte 0x200066c2 must be 1..0x10, else
@ .L080083ea (calls fn_080081c8(2), r1 = 0x24, error exit).
@ Error exit .L080083f2: calls store_two_bytes(5, r1), restores the registers
@ and tail-branches to fn_0800bb1c(1, 0).
@ Dispatch on the command byte c (compare ladder 0x08008404..0x08008478 and a
@ tbb at 0x08008432 for c - 0x1a below 10, target = table + 2 * byte); each
@ target restores the registers and tail-branches:
@ c = 0x03 fn_0800b8f0; 0x04 fn_0800b73c; 0x00 fn_0800b910; 0x12 fn_0800b764;
@ 0x1a fn_0800b7c8; 0x1b and 0x1e fn_0800b908; 0x23 fn_0800b894; 0x25
@ fn_0800b834; 0x28 fn_0800b7d4(r0 = word 0x2000043c, r1 = word 0x20000440);
@ 0x2a fn_0800b974(r0 = word 0x2000043c, r1 = word 0x20000440); 0x2f
@ fn_0800b940; 0x5a fn_0800b7bc; 0x08, 0x0a, 0x15, 0x1d, 0x55, 0x88, 0x8a,
@ 0x8f, 0x9e, 0xa8, 0xaa and 0xaf fn_0800b78c; every other value (including
@ 0x1c, 0x1f..0x22, 0x24) goes to .L0800847c.
@ Literals: 0x080084f8 = 0x20000438, 0x080084fc = 0x200066b4, 0x08008500 =
@ 0x43425355.
@ The code matches the USB mass-storage bulk-only command block (31 bytes,
@ signature "USBC", command bytes from offset 15) and the standard SCSI
@ operation codes: 0x00 TEST UNIT READY, 0x03 REQUEST SENSE, 0x12 INQUIRY,
@ 0x1a MODE SENSE(6), 0x25 READ CAPACITY(10), 0x28 READ(10), 0x2a WRITE(10),
@ 0x5a MODE SENSE(10). The drive area is at 0x08068000.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008378,"ax",%progbits
	.p2align 2
	.global fn_08008378
	.thumb_func
	.type fn_08008378, %function
fn_08008378:
	push	{r4, r5, r6, lr}
	ldr	r2, .L080084f8
	ldr	r4, .L080084fc
	movs	r0, #0
	ldrh	r1, [r2, #2]
	sub.w	r3, r4, #0x40
	b.n	.L0800838e
.L08008388:
	ldrb	r5, [r3, r0]
	strb	r5, [r4, r0]
	.inst.n	0x1c40	@ adds r0, r0, #1
.L0800838e:
	mov	r5, r1
	cmp	r0, r1
	bcc.n	.L08008388
	ldr	r0, .L080084fc
	ldr	r3, [r4, #4]
	adds	r0, #0x20
	cmp	r5, #0x1f
	str	r3, [r0, #4]
	ldr	r3, [r4, #8]
	str	r3, [r0, #8]
	beq.n	.L080083b2
	movs	r0, #2
	bl	fn_080081c8
	movs	r0, #0
	movs	r1, #0x1a
	str	r0, [r4]
	b.n	.L080083f2
.L080083b2:
	ldrb	r0, [r4, #0xf]
	cmp	r0, #0x28
	beq.n	.L080083bc
	cmp	r0, #0x2a
	bne.n	.L080083d6
.L080083bc:
	ldrh.w	r1, [r4, #0x11]
	ldrb	r3, [r4, #0x13]
	rev16	r1, r1
	lsls	r1, r1, #0x10
	orr.w	r1, r1, r3, lsl #8
	ldrb	r3, [r4, #0x14]
	orrs	r1, r3
	str	r1, [r2, #4]
	ldrh	r1, [r4, #0x16]
	rev16	r1, r1
	str	r1, [r2, #8]
.L080083d6:
	ldr	r3, .L08008500
	ldr	r1, [r4]
	cmp	r1, r3
	bne.n	.L0800847c
	ldrb	r1, [r4, #0xd]
	cbnz	r1, .L080083ea
	ldrb	r1, [r4, #0xe]
	cbz	r1, .L080083ea
	cmp	r1, #0x10
	bls.n	.L08008404
.L080083ea:
	movs	r0, #2
	bl	fn_080081c8
	movs	r1, #0x24
.L080083f2:
	movs	r0, #5
	bl	store_two_bytes
	pop.w	{r4, r5, r6, lr}
	movs	r1, #0
	movs	r0, #1
	b.w	fn_0800bb1c
.L08008404:
	cmp	r0, #0x25
	beq.n	.L080084b8
	bgt.n	.L08008440
	cmp	r0, #0x15
	beq.n	.L080084f0
	bgt.n	.L0800842c
	cmp	r0, #8
	beq.n	.L080084f0
	bgt.n	.L08008422
	cbz	r0, .L08008486
	cmp	r0, #3
	beq.n	.L08008488
	cmp	r0, #4
	bne.n	.L0800847c
	b.n	.L080084e8
.L08008422:
	cmp	r0, #0xa
	beq.n	.L080084f0
	cmp	r0, #0x12
	bne.n	.L0800847c
	b.n	.L08008490
.L0800842c:
	subs	r0, #0x1a
	cmp	r0, #0xa
	bcs.n	.L0800847c
	tbb	[pc, r0]
.L08008436:
	.byte	(.L080084a0 - .L08008436)/2	@ c = 0x1a
	.byte	(.L08008498 - .L08008436)/2	@ c = 0x1b
	.byte	(.L0800847c - .L08008436)/2	@ c = 0x1c
	.byte	(.L080084f0 - .L08008436)/2	@ c = 0x1d
	.byte	(.L08008498 - .L08008436)/2	@ c = 0x1e
	.byte	(.L0800847c - .L08008436)/2	@ c = 0x1f
	.byte	(.L0800847c - .L08008436)/2	@ c = 0x20
	.byte	(.L0800847c - .L08008436)/2	@ c = 0x21
	.byte	(.L0800847c - .L08008436)/2	@ c = 0x22
	.byte	(.L080084b0 - .L08008436)/2	@ c = 0x23
.L08008440:
	cmp	r0, #0x8a
	beq.n	.L080084f0
	bgt.n	.L08008464
	cmp	r0, #0x55
	beq.n	.L080084f0
	bgt.n	.L0800845a
	cmp	r0, #0x28
	beq.n	.L080084c8
	cmp	r0, #0x2a
	beq.n	.L080084d4
	cmp	r0, #0x2f
	bne.n	.L0800847c
	b.n	.L080084e0
.L0800845a:
	cmp	r0, #0x5a
	beq.n	.L080084a8
	cmp	r0, #0x88
	bne.n	.L0800847c
	b.n	.L080084f0
.L08008464:
	cmp	r0, #0xa8
	beq.n	.L080084f0
	bgt.n	.L08008474
	cmp	r0, #0x8f
	beq.n	.L080084f0
	cmp	r0, #0x9e
	bne.n	.L0800847c
	b.n	.L080084f0
.L08008474:
	cmp	r0, #0xaa
	beq.n	.L080084f0
	cmp	r0, #0xaf
	beq.n	.L080084f0
.L0800847c:
	movs	r0, #2
	bl	fn_080081c8
	movs	r1, #0x20
	b.n	.L080083f2
.L08008486:
	b.n	.L080084c0
.L08008488:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b8f0
.L08008490:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b764
.L08008498:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b908
.L080084a0:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b7c8
.L080084a8:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b7bc
.L080084b0:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b894
.L080084b8:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b834
.L080084c0:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b910
.L080084c8:
	ldrd	r0, r1, [r2, #4]
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b7d4
.L080084d4:
	ldrd	r0, r1, [r2, #4]
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b974
.L080084e0:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b940
.L080084e8:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b73c
.L080084f0:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b78c
.L080084f8:
	.word	0x20000438
.L080084fc:
	.word	0x200066b4
.L08008500:
	.word	0x43425355

@ ----------------------------------------------------------------------------
@ fn_08008968 - sends the next data packet of an in-progress control or bulk
@ transfer through the USB packet memory; no parameters, no return value.
@ s = pointer at 0x200002bc; len = halfword [s+0x10] (bytes left).
@ When len == 0 and byte [s+8] == 4: with byte 0x200002b4 == 0 sets the state 7
@ and stores 0x10 to halfword 0x200002cc; otherwise clears the word at
@ 0x40006004 + 2 * (halfword 0x40005c50 value) (USB packet memory, addressed
@ from the USB_BUFTAB register at 0x40005c50), stores 0x30 to 0x200002cc,
@ clears byte 0x200002b4 and sets the state 4.
@ Otherwise n = min(len, halfword [s+0x14]); calls the function pointer
@ [s+0x18](n), then fn_0800fdd0(0), then copy_halfwords_to_40006000(result,
@ that value, n), then fn_080100d4(0, n); subtracts n from [s+0x10], adds n to
@ [s+0x12], stores 0x30 to halfword 0x200002cc and 0x3000 to halfword
@ 0x200002ca; the state is 2 when [s+0x14] < len, else 4.
@ Stores the state byte to [s+8].
@ Registers: r8 = &0x200002bc, r7 = &0x200002cc, r9 = 0x30.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008968,"ax",%progbits
	.p2align 2
	.global fn_08008968
	.thumb_func
	.type fn_08008968, %function
fn_08008968:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr.w	r8, .L08008a04
	ldr	r7, .L08008a08
	mov.w	r9, #0x30
	ldr.w	r1, [r8]
	add.w	r5, r1, #0x10
	ldrh	r0, [r1, #0x10]
	ldrb	r6, [r1, #8]
	cbnz	r0, .L08008988
	cmp	r6, #4
	beq.n	.L08008992
.L08008988:
	ldrh	r4, [r5, #4]
	cmp	r0, r4
	bhi.n	.L080089b8
	movs	r6, #4
	b.n	.L080089ba
.L08008992:
	ldr	r0, .L08008a0c
	ldrb	r1, [r0]
	cbz	r1, .L080089b0
	ldr	r2, .L08008a10
	movs	r1, #0
	ldr	r2, [r2]
	ldr	r3, .L08008a14
	lsls	r2, r2, #0x10
	add.w	r2, r3, r2, lsr #0xf
	str	r1, [r2, #4]
	strh.w	r9, [r7]
	strb	r1, [r0]
	b.n	.L080089f8
.L080089b0:
	movs	r6, #7
	movs	r0, #0x10
	strh	r0, [r7]
	b.n	.L080089f8
.L080089b8:
	movs	r6, #2
.L080089ba:
	cmp	r4, r0
	bls.n	.L080089c0
	mov	r4, r0
.L080089c0:
	ldr	r1, [r5, #8]
	mov	r0, r4
	blx	r1
	mov	r10, r0
	movs	r0, #0
	bl	fn_0800fdd0
	mov	r1, r0
	mov	r2, r4
	mov	r0, r10
	bl	copy_halfwords_to_40006000
	mov	r1, r4
	movs	r0, #0
	bl	fn_080100d4
	ldrh	r0, [r5]
	subs	r0, r0, r4
	strh	r0, [r5]
	ldrh	r0, [r5, #2]
	add	r0, r4
	strh	r0, [r5, #2]
	strh.w	r9, [r7]
	ldr	r1, .L08008a18
	mov.w	r0, #0x3000
	strh	r0, [r1]
.L080089f8:
	ldr.w	r0, [r8]
	strb	r6, [r0, #8]
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
	.short	0x0000	@ padding
.L08008a04:
	.word	0x200002bc
.L08008a08:
	.word	0x200002cc
.L08008a0c:
	.word	0x200002b4
.L08008a10:
	.word	0x40005c50
.L08008a14:
	.word	0x40006000
.L08008a18:
	.word	0x200002ca

@ ----------------------------------------------------------------------------
@ fn_08008a1c - receives the next data packet of an in-progress transfer from
@ the USB packet memory; no parameters, no return value.
@ s = pointer at 0x200002bc; len = halfword [s+0x10].
@ With a function pointer in [s+0x18]: when len != 0 calls it with
@ n = min(len, halfword [s+0x14]), subtracts n from [s+0x10], adds n to
@ [s+0x12], calls fn_0800fd78(0) and copy_halfwords_from_40006000(result of the
@ pointer, that value, n).
@ When the remaining length is not 0 stores 0x3000 to halfword 0x200002ca,
@ calls fn_080100d4(0, 0) and stores 0x30 to halfword 0x200002cc.
@ Then, when the remaining length is below [s+0x14]: length 0 sets the state
@ byte [s+8] = 6, clears the word at 0x40006004 + 2 * (halfword 0x40005c50,
@ the USB_BUFTAB register) and stores 0x30 to 0x200002cc; otherwise state 5.
@ When the remaining length is not below [s+0x14]: state 3.
@ Registers: r6 = &0x200002bc, r8 = &0x200002cc, r7 = 0x30.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008a1c,"ax",%progbits
	.p2align 2
	.global fn_08008a1c
	.thumb_func
	.type fn_08008a1c, %function
fn_08008a1c:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr	r6, .L08008aac
	ldr.w	r8, .L08008ab0
	movs	r7, #0x30
	ldr	r5, [r6]
	ldrh.w	r0, [r5, #0x10]!
	ldr	r1, [r5, #8]
	cbz	r1, .L08008a5e
	cbz	r0, .L08008a76
	ldrh	r4, [r5, #4]
	cmp	r4, r0
	bls.n	.L08008a3c
	mov	r4, r0
.L08008a3c:
	mov	r0, r4
	blx	r1
	mov	r9, r0
	ldrh	r0, [r5]
	subs	r0, r0, r4
	strh	r0, [r5]
	ldrh	r0, [r5, #2]
	add	r0, r4
	strh	r0, [r5, #2]
	movs	r0, #0
	bl	fn_0800fd78
	mov	r1, r0
	mov	r2, r4
	mov	r0, r9
	bl	copy_halfwords_from_40006000
.L08008a5e:
	ldrh	r0, [r5]
	cbz	r0, .L08008a76
	ldr	r1, .L08008ab4
	mov.w	r0, #0x3000
	strh	r0, [r1]
	movs	r1, #0
	mov	r0, r1
	bl	fn_080100d4
	strh.w	r7, [r8]
.L08008a76:
	ldrh	r0, [r5]
	ldrh	r1, [r5, #4]
	cmp	r0, r1
	bcc.n	.L08008a82
	movs	r0, #3
	b.n	.L08008a86
.L08008a82:
	cbz	r0, .L08008a8e
	movs	r0, #5
.L08008a86:
	ldr	r1, [r6]
	strb	r0, [r1, #8]
.L08008a8a:
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L08008a8e:
	ldr	r1, [r6]
	movs	r0, #6
	strb	r0, [r1, #8]
	ldr	r1, .L08008ab8
	movs	r0, #0
	ldr	r1, [r1]
	ldr	r2, .L08008abc
	lsls	r1, r1, #0x10
	add.w	r1, r2, r1, lsr #0xf
	str	r0, [r1, #4]
	strh.w	r7, [r8]
	b.n	.L08008a8a
	.short	0x0000	@ padding
.L08008aac:
	.word	0x200002bc
.L08008ab0:
	.word	0x200002cc
.L08008ab4:
	.word	0x200002ca
.L08008ab8:
	.word	0x40005c50
.L08008abc:
	.word	0x40006000

@ ----------------------------------------------------------------------------
@ fn_08008ac0 - control-request dispatcher: decides how a received SETUP
@ request is answered and starts the data stage; no parameters, no return
@ value. s = pointer at 0x200002bc (the request record), table = pointer at
@ 0x200002c0. Dispatches on the request byte [s+1]; the default path
@ (.L08008bb8) calls [table+0x10]([s+1]).
@ 6: when ([s] & 0x7f) == 0 and [s+2] = 1, 2, 3 selects the function pointer
@ [table+0x1c], [table+0x20], [table+0x24].
@ 0: when halfword [s+2] == 0, halfword [s+6] == 2 and byte [s+4] == 0:
@ ([s] & 0x7f) == 0 with halfword [s+4] == 0 selects fn_0800c034; ([s] & 0x7f)
@ == 1 calls [table+0x18]([s+5], 0) and selects fn_0800c034 when it returns 0
@ and byte [s+10] is not 0; ([s] & 0x7f) == 2 forms n = [s+5] & 0xf, reads the
@ word at 0x40005000 + 0xc00 + 4 * n (= 0x40005c00 + 4 * n, the USB endpoint
@ register n), takes its bits 4..5 as the 0x30 mask when bit 7 of [s+5] is set,
@ else its bits 12..13 as the 0x3000 mask, and selects fn_0800c034 when byte
@ 0x20000330 is above n, ([s+5] & 0x70) == 0 and the extracted mask is not 0.
@ 8: when ([s] & 0x7f) == 0 selects fn_0800bfc8.
@ 10: when ([s] & 0x7f) == 1, byte [s+10] is not 0, halfword [s+2] == 0, byte
@ [s+4] == 0, halfword [s+6] == 1 and [table+0x18]([s+5], 0) returns 0 selects
@ fn_0800c00c.
@ A nonzero selected pointer: clears halfword [s+0x12], stores it at [s+0x18],
@ calls it with 0, result 0; otherwise the default path.
@ Default: calls [table+0x10]([s+1]); a result 3 stores the state 9 to [s+8].
@ Then, by length L = halfword [s+0x10]: L == 0xffff -> state 9; result 2 or
@ L == 0 -> state 8; bit 7 of [s] clear -> state 3 (and 0x3000 stored to
@ halfword 0x200002ca); else L is limited to halfword [s+6] when that is
@ smaller, or when it is larger byte 0x200002b4 is set to 0 (L below byte
@ [table+0x2c]) or to 1 (L a multiple of it); [table+0x2c] is stored to [s+0x14]
@ and fn_08008968 is entered by a tail branch.
@ Registers: r4 = &0x200002bc, r5 = &0x200002c0, r6 = 9, r7 = 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008ac0,"ax",%progbits
	.p2align 2
	.global fn_08008ac0
	.thumb_func
	.type fn_08008ac0, %function
fn_08008ac0:
	push	{r3, r4, r5, r6, r7, lr}
	ldr	r4, .L08008c38
	ldr	r5, .L08008c3c
	movs	r6, #9
	ldr	r0, [r4]
	movs	r7, #0
	ldr	r1, [r5]
	ldrb	r2, [r0, #1]
	cmp	r2, #6
	beq.n	.L08008ae0
	cbz	r2, .L08008b02
	cmp	r2, #8
	beq.n	.L08008b76
	cmp	r2, #0xa
	beq.n	.L08008b80
	b.n	.L08008bb8
.L08008ae0:
	ldrb	r2, [r0]
	lsls	r2, r2, #0x19
	bne.n	.L08008bb8
	ldrb	r0, [r0, #2]
	cmp	r0, #1
	beq.n	.L08008af6
	cmp	r0, #2
	beq.n	.L08008afa
	cmp	r0, #3
	beq.n	.L08008afe
	b.n	.L08008bb8
.L08008af6:
	ldr	r1, [r1, #0x1c]
	b.n	.L08008ba8
.L08008afa:
	ldr	r1, [r1, #0x20]
	b.n	.L08008ba8
.L08008afe:
	ldr	r1, [r1, #0x24]
	b.n	.L08008ba8
.L08008b02:
	ldrh	r2, [r0, #2]
	cbnz	r2, .L08008b74
	ldrh	r2, [r0, #6]
	cmp	r2, #2
	bne.n	.L08008bb8
	ldrb	r2, [r0, #4]
	cbnz	r2, .L08008b74
	ldrb	r2, [r0]
	lsls	r3, r2, #0x19
	bne.n	.L08008b1a
	ldrh	r3, [r0, #4]
	cbz	r3, .L08008b28
.L08008b1a:
	and.w	r2, r2, #0x7f
	cmp	r2, #1
	beq.n	.L08008b2c
	cmp	r2, #2
	beq.n	.L08008b40
	b.n	.L08008bb8
.L08008b28:
	ldr	r1, .L08008c40
	b.n	.L08008ba8
.L08008b2c:
	ldr	r2, [r1, #0x18]
	ldrb	r0, [r0, #5]
	movs	r1, #0
	blx	r2
	cbnz	r0, .L08008b74
	ldr	r0, [r4]
	ldrb	r0, [r0, #0xa]
	cmp	r0, #0
	bne.n	.L08008b28
	b.n	.L08008bb8
.L08008b40:
	ldrb	r1, [r0, #5]
	and.w	r0, r1, #0xf
	and.w	r2, r1, #0x70
	lsls	r3, r1, #0x18
	ldr	r1, .L08008c44
	add.w	r1, r1, r0, lsl #2
	ldr.w	r1, [r1, #0xc00]
	bpl.n	.L08008b60
	ubfx	r1, r1, #4, #2
	lsls	r1, r1, #4
	b.n	.L08008b66
.L08008b60:
	ubfx	r1, r1, #0xc, #2
	lsls	r1, r1, #0xc
.L08008b66:
	ldr	r3, .L08008c48
	ldrb	r3, [r3]
	cmp	r3, r0
	bls.n	.L08008bb8
	cbnz	r2, .L08008b74
	cmp	r1, #0
	bne.n	.L08008b28
.L08008b74:
	b.n	.L08008bb8
.L08008b76:
	ldrb	r0, [r0]
	lsls	r0, r0, #0x19
	bne.n	.L08008bb8
	ldr	r1, .L08008c4c
	b.n	.L08008ba8
.L08008b80:
	ldrb	r2, [r0]
	and.w	r2, r2, #0x7f
	cmp	r2, #1
	bne.n	.L08008bb8
	ldrb	r2, [r0, #0xa]
	cbz	r2, .L08008bb8
	ldrh	r2, [r0, #2]
	cbnz	r2, .L08008bb8
	ldrb	r2, [r0, #4]
	cbnz	r2, .L08008bb8
	ldrh	r2, [r0, #6]
	cmp	r2, #1
	bne.n	.L08008bb8
	ldr	r2, [r1, #0x18]
	ldrb	r0, [r0, #5]
	movs	r1, #0
	blx	r2
	cbnz	r0, .L08008bb8
	ldr	r1, .L08008c50
.L08008ba8:
	cbz	r1, .L08008bb8
	ldr	r0, [r4]
	strh	r7, [r0, #0x12]
	str	r1, [r0, #0x18]
	movs	r0, #0
	blx	r1
	movs	r0, #0
	b.n	.L08008bc6
.L08008bb8:
	ldr	r1, [r5]
	ldr	r0, [r4]
	ldr	r1, [r1, #0x10]
	ldrb	r0, [r0, #1]
	blx	r1
	cmp	r0, #3
	beq.n	.L08008bee
.L08008bc6:
	ldr	r1, [r4]
	ldrh	r2, [r1, #0x10]
	sub.w	r3, r2, #0xff00
	subs	r3, #0xff
	beq.n	.L08008bea
	cmp	r0, #2
	beq.n	.L08008bf4
	cbz	r2, .L08008bf4
	ldrb	r0, [r1]
	lsls	r0, r0, #0x18
	bpl.n	.L08008c2c
	ldrh	r0, [r1, #6]
	str	r0, [sp]
	cmp	r2, r0
	bls.n	.L08008bfc
	strh	r0, [r1, #0x10]
	b.n	.L08008c1c
.L08008bea:
	strb	r6, [r1, #8]
	pop	{r3, r4, r5, r6, r7, pc}
.L08008bee:
	ldr	r0, [r4]
	strb	r6, [r0, #8]
	pop	{r3, r4, r5, r6, r7, pc}
.L08008bf4:
	mov.w	r0, #8
	strb	r0, [r1, #8]
	pop	{r3, r4, r5, r6, r7, pc}
.L08008bfc:
	bcs.n	.L08008c1c
	ldr	r0, [r5]
	ldr	r3, .L08008c54
	ldrb.w	r0, [r0, #0x2c]
	cmp	r2, r0
	bcs.n	.L08008c0e
	strb	r7, [r3]
	b.n	.L08008c1c
.L08008c0e:
	udiv	r4, r2, r0
	mls	r0, r0, r4, r2
	cbnz	r0, .L08008c1c
	movs	r0, #1
	strb	r0, [r3]
.L08008c1c:
	ldr	r0, [r5]
	ldrb.w	r0, [r0, #0x2c]
	strh	r0, [r1, #0x14]
	pop.w	{r3, r4, r5, r6, r7, lr}
	b.w	fn_08008968
.L08008c2c:
	movs	r0, #3
	strb	r0, [r1, #8]
	ldr	r1, .L08008c58
	lsls	r0, r0, #0xc
	strh	r0, [r1]
	pop	{r3, r4, r5, r6, r7, pc}
.L08008c38:
	.word	0x200002bc
.L08008c3c:
	.word	0x200002c0
.L08008c40:
	.word	fn_0800c034	@ function pointer (Thumb address 0x0800c035)
.L08008c44:
	.word	0x40005000
.L08008c48:
	.word	0x20000330
.L08008c4c:
	.word	fn_0800bfc8	@ function pointer (Thumb address 0x0800bfc9)
.L08008c50:
	.word	fn_0800c00c	@ function pointer (Thumb address 0x0800c00d)
.L08008c54:
	.word	0x200002b4
.L08008c58:
	.word	0x200002ca

@ ----------------------------------------------------------------------------
@ fn_08008d0c - one instruction, a tail branch (b.w) to fn_0800ac70, which is
@ not part of this function. fn_0800ac70 reads byte 0x20000438 (v) and
@ dispatches: v = 2: reads byte 0x200066c3, returns unless it equals 0x28,
@ else loads r1 = word 0x20000440, r0 = word 0x2000043c and tail-branches to
@ fn_0800b7d4(r0, r1); v = 3: calls fn_0800bb1c(0, 1), then tail-branches to
@ fn_0800b9ec(2, 0x3000); v = 4 or 5: stores 0 in byte 0x20000438, calls
@ fn_0800b9ec(2, 0x3000), calls fn_0800fdb8(2) and, when that returns 0x1000,
@ tail-branches to fn_0800b9ec(2, 0x3000); any other v returns at once.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008d0c,"ax",%progbits
	.p2align 2
	.global fn_08008d0c
	.thumb_func
	.type fn_08008d0c, %function
fn_08008d0c:
	b.w	fn_0800ac70

@ ----------------------------------------------------------------------------
@ fn_08008d10 - one instruction, a tail branch (b.w) to fn_0800acd8 with r0-r3
@ and lr unchanged, so fn_0800acd8 returns to the caller of this function.
@ fn_0800acd8 is a function of its own, reached only by this tail call.
@ ----------------------------------------------------------------------------
	.section .text.fn_08008d10,"ax",%progbits
	.p2align 2
	.global fn_08008d10
	.thumb_func
	.type fn_08008d10, %function
fn_08008d10:
	b.w	fn_0800acd8

@ ----------------------------------------------------------------------------
@ fn_0800933c - r0 = flag; returns a pointer.
@ r0 == 0: stores 1 to the halfword [word 0x200002bc + 0x10] and returns 0;
@ otherwise returns 0x20000334.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800933c,"ax",%progbits
	.p2align 2
	.global fn_0800933c
	.thumb_func
	.type fn_0800933c, %function
fn_0800933c:
	cbz	r0, .L08009342
	ldr	r0, .L08009350
	bx	lr
.L08009342:
	ldr	r1, .L08009354
	movs	r0, #1
	ldr	r1, [r1]
	strh	r0, [r1, #0x10]
	movs	r0, #0
	bx	lr
	.short	0x0000	@ padding
.L08009350:
	.word	0x20000334
.L08009354:
	.word	0x200002bc

@ ----------------------------------------------------------------------------
@ fn_0800a9ec - no parameters; returns 0. Writes 0x2e to word 0x200003b4 and
@ 0x800 to word 0x200003b0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800a9ec,"ax",%progbits
	.p2align 2
	.global fn_0800a9ec
	.thumb_func
	.type fn_0800a9ec, %function
fn_0800a9ec:
	ldr	r0, .L0800a9fc
	movs	r1, #0x2e
	str	r1, [r0, #4]
	mov.w	r1, #0x800
	str	r1, [r0]
	movs	r0, #0
	bx	lr
.L0800a9fc:
	.word	0x200003b0

@ ----------------------------------------------------------------------------
@ copy_words_from_0x08068000_plus_offset - r0 = offset, r1 = destination,
@ r2 = byte count; returns 0. Loop in steps of 4 from 0 below r2: copies the
@ word at (r0 + 0x08068000 + i) to (r1 + i). 0x08068000 is the drive area read
@ through the mass-storage interface.
@ ----------------------------------------------------------------------------
	.section .text.copy_words_from_0x08068000_plus_offset,"ax",%progbits
	.p2align 2
	.global copy_words_from_0x08068000_plus_offset
	.thumb_func
	.type copy_words_from_0x08068000_plus_offset, %function
copy_words_from_0x08068000_plus_offset:
	push	{r4, r5, r6, lr}
	movs	r3, #0
	ldr	r5, .L0800aa1c
	b.n	.L0800aa14
.L0800aa08:
	bic.w	r4, r3, #3
	adds	r6, r4, r0
	ldr	r6, [r6, r5]
	str	r6, [r1, r4]
	.inst.n	0x1d1b	@ adds r3, r3, #4
.L0800aa14:
	cmp	r3, r2
	blt.n	.L0800aa08
	movs	r0, #0
	pop	{r4, r5, r6, pc}
.L0800aa1c:
	.word	0x08068000

@ ----------------------------------------------------------------------------
@ fn_0800aa20 - writes a buffer into the drive area at 0x08068000;
@ r0 = offset, r1 = source buffer, r2 = byte count; returns 0.
@ Loop 1 in steps of 0x800 below r2: calls fn_08008e1c(100000), calls
@ fn_08008d20(0x34) when the result is not 10, then calls
@ fn_08008d30(r0 + i + 0x08068000).
@ Loop 2 in steps of 4 below r2: the same fn_08008e1c / fn_08008d20 check,
@ then calls fn_08008dc0(r0 + i + 0x08068000, word at r1 + i).
@ Registers: r6 = r2, r9 = r1, r7 = r0, r8 = 100000 (0x186a0), r5 = 0x08068000.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800aa20,"ax",%progbits
	.p2align 2
	.global fn_0800aa20
	.thumb_func
	.type fn_0800aa20, %function
fn_0800aa20:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r6, r2
	mov	r9, r1
	mov	r7, r0
	movs	r4, #0
	ldr.w	r8, .L0800aa84
	ldr	r5, .L0800aa88
	b.n	.L0800aa50
.L0800aa34:
	mov	r0, r8
	bl	fn_08008e1c
	cmp	r0, #0xa
	beq.n	.L0800aa44
	movs	r0, #0x34
	bl	fn_08008d20
.L0800aa44:
	adds	r0, r7, r4
	add	r0, r5
	bl	fn_08008d30
	add.w	r4, r4, #0x800
.L0800aa50:
	cmp	r4, r6
	blt.n	.L0800aa34
	movs	r4, #0
	b.n	.L0800aa7a
.L0800aa58:
	mov	r0, r8
	bl	fn_08008e1c
	cmp	r0, #0xa
	beq.n	.L0800aa68
	movs	r0, #0x34
	bl	fn_08008d20
.L0800aa68:
	bic.w	r1, r4, #3
	adds	r0, r7, r4
	ldr.w	r1, [r9, r1]
	add	r0, r5
	bl	fn_08008dc0
	.inst.n	0x1d24	@ adds r4, r4, #4
.L0800aa7a:
	cmp	r4, r6
	blt.n	.L0800aa58
	movs	r0, #0
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}
.L0800aa84:
	.word	0x000186a0
.L0800aa88:
	.word	0x08068000

@ ----------------------------------------------------------------------------
@ fn_0800aa8c - handler of one vendor control request (SETUP request type
@ masked with 0x7f equal to 0x21); r0 = request value; returns 0 or 2.
@ Taken only when the request byte at the pointer in 0x200002bc masked with
@ 0x7f is 0x21, r0 is 0xfe, the halfwords at offsets 2 and 4 are 0 and the
@ halfword at offset 6 is 1. Then stores the function pointer fn_0800933c
@ (0x0800933d) to offsets 0x18..0x1b, 0 to the halfword at offset 0x12, calls
@ fn_0800933c(0) and returns 0. Otherwise returns 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800aa8c,"ax",%progbits
	.p2align 2
	.global fn_0800aa8c
	.thumb_func
	.type fn_0800aa8c, %function
fn_0800aa8c:
	ldr	r1, .L0800aac4
	push	{lr}
	ldr	r1, [r1]
	ldrb	r2, [r1]
	and.w	r2, r2, #0x7f
	cmp	r2, #0x21
	bne.n	.L0800aaae
	cmp	r0, #0xfe
	bne.n	.L0800aaae
	ldrh	r0, [r1, #2]
	cbnz	r0, .L0800aaae
	ldrh	r0, [r1, #4]
	cbnz	r0, .L0800aaae
	ldrh	r0, [r1, #6]
	cmp	r0, #1
	beq.n	.L0800aab2
.L0800aaae:
	movs	r0, #2
	pop	{pc}
.L0800aab2:
	ldr	r0, .L0800aac8
	str	r0, [r1, #0x18]
	movs	r0, #0
	strh	r0, [r1, #0x12]
	bl	fn_0800933c
	movs	r0, #0
	pop	{pc}
	.short	0x0000	@ padding
.L0800aac4:
	.word	0x200002bc
.L0800aac8:
	.word	fn_0800933c	@ function pointer (Thumb address 0x0800933d)

@ ----------------------------------------------------------------------------
@ fn_0800aacc - r0 = value; tail-jumps (b.w) to fn_0800bff0(r0, 0x20000340)
@ and returns its result.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800aacc,"ax",%progbits
	.p2align 2
	.global fn_0800aacc
	.thumb_func
	.type fn_0800aacc, %function
fn_0800aacc:
	ldr	r1, .L0800aad4
	b.w	fn_0800bff0
	.short	0x0000	@ padding
.L0800aad4:
	.word	0x20000340

@ ----------------------------------------------------------------------------
@ fn_0800aad8 - r0 = value; tail-jumps (b.w) to fn_0800bff0(r0, 0x20000338)
@ and returns its result.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800aad8,"ax",%progbits
	.p2align 2
	.global fn_0800aad8
	.thumb_func
	.type fn_0800aad8, %function
fn_0800aad8:
	ldr	r1, .L0800aae0
	b.w	fn_0800bff0
	.short	0x0000	@ padding
.L0800aae0:
	.word	0x20000338

@ ----------------------------------------------------------------------------
@ fn_0800aae4 - r0 = value; returns the result of fn_0800bff0 or 0.
@ When the byte at offset 3 of the structure pointed to by 0x200002bc is below
@ 6: tail-jumps (b.w) to fn_0800bff0(r0, 0x20000378 + byte * 8) and returns its
@ result; otherwise returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800aae4,"ax",%progbits
	.p2align 2
	.global fn_0800aae4
	.thumb_func
	.type fn_0800aae4, %function
fn_0800aae4:
	ldr	r1, .L0800aafc
	ldr	r1, [r1]
	ldrb	r1, [r1, #3]
	cmp	r1, #5
	bls.n	.L0800aaf2
	movs	r0, #0
	bx	lr
.L0800aaf2:
	ldr	r2, .L0800ab00
	add.w	r1, r2, r1, lsl #3
	b.w	fn_0800bff0
.L0800aafc:
	.word	0x200002bc
.L0800ab00:
	.word	0x20000378

@ ----------------------------------------------------------------------------
@ return_2_unless_both_zero - r0, r1; returns 0 when r1 is 0 and r0 is 0,
@ otherwise 2.
@ ----------------------------------------------------------------------------
	.section .text.return_2_unless_both_zero,"ax",%progbits
	.p2align 2
	.global return_2_unless_both_zero
	.thumb_func
	.type return_2_unless_both_zero, %function
return_2_unless_both_zero:
	cbnz	r1, .L0800ab0a
	cmp	r0, #0
	beq.n	.L0800ab0c
.L0800ab0a:
	movs	r0, #2
.L0800ab0c:
	bx	lr
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_0800ab10 - handler of one vendor control request (request type masked
@ with 0x7f equal to 0x21); r0 = request value; returns 0 or 2.
@ Taken only when the byte at the pointer in 0x200002bc masked with 0x7f is
@ 0x21, r0 is 0xff and the halfwords at offsets 2, 4 and 6 are all 0. Then
@ calls fn_0800fb7c(1) and fn_0800fb54(2), stores 0x43425355 to word
@ 0x200066b4 and 0 to byte 0x20000438, returns 0. Otherwise returns 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ab10,"ax",%progbits
	.p2align 2
	.global fn_0800ab10
	.thumb_func
	.type fn_0800ab10, %function
fn_0800ab10:
	ldr	r1, .L0800ab50
	push	{r4, lr}
	ldr	r1, [r1]
	ldrb	r2, [r1]
	and.w	r2, r2, #0x7f
	cmp	r2, #0x21
	bne.n	.L0800ab30
	cmp	r0, #0xff
	bne.n	.L0800ab30
	ldrh	r0, [r1, #2]
	cbnz	r0, .L0800ab30
	ldrh	r0, [r1, #4]
	cbnz	r0, .L0800ab30
	ldrh	r0, [r1, #6]
	cbz	r0, .L0800ab34
.L0800ab30:
	movs	r0, #2
	pop	{r4, pc}
.L0800ab34:
	movs	r0, #1
	bl	fn_0800fb7c
	movs	r0, #2
	bl	fn_0800fb54
	ldr	r1, .L0800ab58
	ldr	r0, .L0800ab54
	str	r0, [r1]
	ldr	r1, .L0800ab5c
	movs	r0, #0
	strb	r0, [r1]
	pop	{r4, pc}
	.short	0x0000	@ padding
.L0800ab50:
	.word	0x200002bc
.L0800ab54:
	.word	0x43425355
.L0800ab58:
	.word	0x200066b4
.L0800ab5c:
	.word	0x20000438

@ ----------------------------------------------------------------------------
@ fn_0800ab60 - sets up the USB device endpoints and the mass-storage state
@ after a bus reset; no parameters.
@ Stores 0 to byte 0x20005e42 (offset 0xa of the record at 0x20005e38) and the
@ byte at 0x0802af4e + 7 to offset 9 of the structure at 0x200002bc.
@ Calls fn_0800ffd8(0), fn_080100f0(0, 0x200), fn_0800ba1c(0, 0x20),
@ fn_08010030(0, 0x18), fn_08010050(0, byte 0x20000374), fn_080100b4(0, 0x58),
@ fn_0800fba4(0), fn_08010090(0), fn_080100f0(1, 0), fn_080100b4(1, 0x98),
@ fn_0800ba1c(1, 0x20), fn_0800b9ec(1, 0), fn_080100f0(2, 0),
@ fn_08010030(2, 0xd8), fn_08010050(2, byte 0x20000374), fn_0800b9ec(2, 0x3000),
@ fn_0800ba1c(2, 0), fn_0800ffe8(0).
@ Then stores 1 to word 0x200003a0, 0x43425355 to word 0x200066b4 and 0 to
@ byte 0x20000438. r5 = 0x20000348 + 0x2c = 0x20000374 (write-back load).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ab60,"ax",%progbits
	.p2align 2
	.global fn_0800ab60
	.thumb_func
	.type fn_0800ab60, %function
fn_0800ab60:
	push	{r4, r5, r6, lr}
	ldr	r0, .L0800ac14
	movs	r4, #0
	ldr	r1, .L0800ac1c
	strb	r4, [r0, #0xa]
	ldr	r0, .L0800ac18
	ldr	r1, [r1]
	ldrb	r0, [r0, #7]
	strb	r0, [r1, #9]
	mov	r0, r4
	bl	fn_0800ffd8
	mov.w	r1, #0x200
	movs	r0, #0
	bl	fn_080100f0
	movs	r1, #0x20
	movs	r0, #0
	bl	fn_0800ba1c
	movs	r1, #0x18
	movs	r0, #0
	bl	fn_08010030
	ldr	r5, .L0800ac20
	movs	r0, #0
	ldrb.w	r1, [r5, #0x2c]!
	bl	fn_08010050
	movs	r1, #0x58
	movs	r0, #0
	bl	fn_080100b4
	movs	r0, #0
	bl	fn_0800fba4
	movs	r0, #0
	bl	fn_08010090
	movs	r1, #0
	movs	r0, #1
	bl	fn_080100f0
	movs	r1, #0x98
	movs	r0, #1
	bl	fn_080100b4
	movs	r1, #0x20
	movs	r0, #1
	bl	fn_0800ba1c
	movs	r1, #0
	movs	r0, #1
	bl	fn_0800b9ec
	movs	r1, #0
	movs	r0, #2
	bl	fn_080100f0
	movs	r1, #0xd8
	movs	r0, #2
	bl	fn_08010030
	ldrb	r1, [r5]
	movs	r0, #2
	bl	fn_08010050
	mov.w	r1, #0x3000
	movs	r0, #2
	bl	fn_0800b9ec
	movs	r1, #0
	movs	r0, #2
	bl	fn_0800ba1c
	movs	r0, #0
	bl	fn_0800ffe8
	ldr	r1, .L0800ac24
	movs	r0, #1
	str	r0, [r1]
	ldr	r1, .L0800ac2c
	ldr	r0, .L0800ac28
	str	r0, [r1]
	ldr	r0, .L0800ac30
	strb	r4, [r0]
	pop	{r4, r5, r6, pc}
.L0800ac14:
	.word	0x20005e38
.L0800ac18:
	.word	d_0802af4e
.L0800ac1c:
	.word	0x200002bc
.L0800ac20:
	.word	0x20000348
.L0800ac24:
	.word	0x200003a0
.L0800ac28:
	.word	0x43425355
.L0800ac2c:
	.word	0x200066b4
.L0800ac30:
	.word	0x20000438

@ ----------------------------------------------------------------------------
@ return_only_0800ac34 - no parameters; returns at once.
@ ----------------------------------------------------------------------------
	.section .text.return_only_0800ac34,"ax",%progbits
	.global return_only_0800ac34
	.thumb_func
	.type return_only_0800ac34, %function
return_only_0800ac34:
	bx	lr

@ ----------------------------------------------------------------------------
@ return_only_0800ac36 - no parameters; returns at once.
@ ----------------------------------------------------------------------------
	.section .text.return_only_0800ac36,"ax",%progbits
	.global return_only_0800ac36
	.thumb_func
	.type return_only_0800ac36, %function
return_only_0800ac36:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_0800ac38 - resets the USB device registers; no parameters.
@ Stores 0 to offset 10 of the structure at 0x200002bc, calls fn_0800b250(),
@ writes 0 to USB_STS (0x40005c44), 0x9e00 to halfword 0x200002c8 and to
@ USB_CTRL (0x40005c40), and 0 to word 0x200003a0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ac38,"ax",%progbits
	.p2align 2
	.global fn_0800ac38
	.thumb_func
	.type fn_0800ac38, %function
fn_0800ac38:
	ldr	r0, .L0800ac60
	push	{r4, lr}
	ldr	r0, [r0]
	movs	r4, #0
	strb	r4, [r0, #0xa]
	bl	fn_0800b250
	ldr	r0, .L0800ac64
	str	r4, [r0]
	ldr	r1, .L0800ac68
	mov.w	r0, #0x9e00
	strh	r0, [r1]
	ldr	r1, .L0800ac64
	.inst.n	0x1f09	@ subs r1, r1, #4
	str	r0, [r1]
	ldr	r0, .L0800ac6c
	str	r4, [r0]
	pop	{r4, pc}
	.short	0x0000	@ padding
.L0800ac60:
	.word	0x200002bc
.L0800ac64:
	.word	0x40005c44
.L0800ac68:
	.word	0x200002c8
.L0800ac6c:
	.word	0x200003a0

@ ----------------------------------------------------------------------------
@ fn_0800ac70 - bulk-transfer state step, entered by the b.w at 0x08008d0c;
@ no parameters, no return value (every path ends in pop {r4,pc} or a tail
@ jump). r0 = 0x20000438, r1 = byte [0x20000438] (the dispatch value v),
@ r4 = 0x3000 is loaded before every compare except the first.
@ v = 2: byte 0x200066c3 (0x200066b4 + 0xf) must equal 0x28, else return; then
@ r1 = word 0x20000440, r0 = word 0x2000043c, pops r4/lr and tail-calls
@ fn_0800b7d4(r0, r1).
@ v = 3: calls fn_0800bb1c(0, 1), then joins .L0800aca2.
@ v = 4 or 5: byte 0x20000438 = 0, calls fn_0800b9ec(2, 0x3000), calls
@ fn_0800fdb8(2) and joins .L0800aca2 only when the result equals 0x1000,
@ otherwise returns.
@ .L0800aca2: pops r4/lr and tail-calls fn_0800b9ec(2, 0x3000).
@ v = 0, 1 or above 5: returns at once (.L0800accc).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ac70,"ax",%progbits
	.p2align 2
	.global fn_0800ac70
	.thumb_func
	.type fn_0800ac70, %function
fn_0800ac70:
	ldr	r0, .L0800acd0
	push	{r4, lr}
	ldrb	r1, [r0]
	cmp	r1, #2
	beq.n	.L0800acae
	mov.w	r4, #0x3000
	cmp	r1, #3
	beq.n	.L0800acc2
	cmp	r1, #4
	beq.n	.L0800ac8a
	cmp	r1, #5
	bne.n	.L0800accc
.L0800ac8a:
	movs	r1, #0
	strb	r1, [r0]
	mov	r1, r4
	movs	r0, #2
	bl	fn_0800b9ec
	movs	r0, #2
	bl	fn_0800fdb8
	cmp.w	r0, #0x1000
	bne.n	.L0800accc
.L0800aca2:
	mov	r1, r4
	pop.w	{r4, lr}
	movs	r0, #2
	b.w	fn_0800b9ec
.L0800acae:
	ldr	r1, .L0800acd4
	ldrb	r1, [r1, #0xf]
	cmp	r1, #0x28
	bne.n	.L0800accc
	ldr	r1, [r0, #8]
	ldr	r0, [r0, #4]
	pop.w	{r4, lr}
	b.w	fn_0800b7d4
.L0800acc2:
	movs	r1, #1
	movs	r0, #0
	bl	fn_0800bb1c
	b.n	.L0800aca2
.L0800accc:
	pop	{r4, pc}
	.short	0x0000	@ padding
.L0800acd0:
	.word	0x20000438
.L0800acd4:
	.word	0x200066b4

@ ----------------------------------------------------------------------------
@ fn_0800acd8 - receives a command block from the bulk-out endpoint and starts
@ its handling; no parameters, no return value (all paths end in a tail
@ branch). Also entered by the 4-byte b.w at 0x08008d10.
@ r4 = byte 0x200066c3 (0x200066b4 + 15); calls fn_0801010c(2, 0x20006674)
@ (r1 = 0x200066b4 - 0x40) and stores the low halfword of its result at
@ 0x2000043a. Reads byte 0x20000438 (v).
@ v = 0: restores r4, lr and tail-calls fn_08008378.
@ v = 1 and r4 = 0x2a: loads r0 = word 0x2000043c, r1 = word 0x20000440 (ldrd)
@ and tail-calls fn_0800b974(r0, r1).
@ v = 1 with another r4: calls fn_080081c8(1).
@ Any other v: calls fn_080081c8(2).
@ Both of the last two then call store_two_bytes(5, 0x24) and tail-call
@ fn_0800bb1c(2, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800acd8,"ax",%progbits
	.p2align 2
	.global fn_0800acd8
	.thumb_func
	.type fn_0800acd8, %function
fn_0800acd8:
	ldr	r0, .L0800ad2c
	push	{r4, lr}
	ldrb	r4, [r0, #0xf]
	sub.w	r1, r0, #0x40
	movs	r0, #2
	bl	fn_0801010c
	ldr	r2, .L0800ad30
	strh	r0, [r2, #2]
	ldrb	r0, [r2]
	cbz	r0, .L0800acf8
	cmp	r0, #1
	beq.n	.L0800ad00
	movs	r0, #2
	b.n	.L0800ad06
.L0800acf8:
	pop.w	{r4, lr}
	b.w	fn_08008378
.L0800ad00:
	cmp	r4, #0x2a
	beq.n	.L0800ad1e
	movs	r0, #1
.L0800ad06:
	bl	fn_080081c8
	movs	r1, #0x24
	movs	r0, #5
	bl	store_two_bytes
	movs	r1, #0
	pop.w	{r4, lr}
	movs	r0, #2
	b.w	fn_0800bb1c
.L0800ad1e:
	ldrd	r0, r1, [r2, #4]
	pop.w	{r4, lr}
	b.w	fn_0800b974
	.short	0x0000	@ padding
.L0800ad2c:
	.word	0x200066b4
.L0800ad30:
	.word	0x20000438

@ ----------------------------------------------------------------------------
@ fn_0800adcc - standard control-request dispatcher: decides how a SETUP
@ request is answered; no parameters, no return value.
@ Reads request bytes through the pointer in 0x200002bc: byte 1 (r, kept in
@ r4) and byte 0 masked with 0x7f (type).
@ Type 0: r = 9 calls fn_0800c0c8; r = 5 with byte 3 not above 0x7f, byte 2 = 0
@ and halfword at 4 = 0 loads byte 10 (zero gives the state 6 as below,
@ non-zero gives 8), any other r = 5 request gives 8; r = 3 with byte 3 = 1 and
@ halfword at 4 = 0 calls fn_0800c100; r = 1 with byte 3 = 1, halfword at 4 = 0
@ and bit 5 of byte 9 set calls fn_0800becc; every other type 0 request calls
@ the function at [[0x200002c0] + 0x14] with r.
@ Type 1: r = 0xb calls fn_0800c1ac, else the indirect call.
@ Type 2: r = 1 calls fn_0800becc, r = 3 calls fn_0800c124, else the indirect
@ call. Types above 2: the indirect call.
@ A non-zero result of a direct call is followed by the indirect call too
@ (cbz r0 at 0x0800ae52 falls through to 0x0800ae54).
@ Indirect result 3 stores 9, other non-zero results store 8; zero stores 6,
@ writes 0 to the word at 0x40006004 + (word 0x40005c50 & 0xffff) * 2 (USB
@ packet memory, addressed from the USB_BUFTAB register) and 0x30 to halfword
@ 0x200002cc. The chosen value is stored in byte 8 of the structure at
@ 0x200002bc (r5 holds the address 0x200002bc).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800adcc,"ax",%progbits
	.p2align 2
	.global fn_0800adcc
	.thumb_func
	.type fn_0800adcc, %function
fn_0800adcc:
	push	{r4, r5, r6, lr}
	ldr	r5, .L0800ae8c
	ldr	r0, [r5]
	ldrb	r1, [r0]
	ldrb	r4, [r0, #1]
	lsls	r2, r1, #0x19
	beq.n	.L0800ade8
	and.w	r0, r1, #0x7f
	cmp	r0, #1
	beq.n	.L0800ae34
	cmp	r0, #2
	beq.n	.L0800ae3e
	b.n	.L0800ae54
.L0800ade8:
	cmp	r4, #9
	beq.n	.L0800adfa
	cmp	r4, #5
	beq.n	.L0800ae00
	cmp	r4, #3
	beq.n	.L0800ae12
	cmp	r4, #1
	beq.n	.L0800ae22
	b.n	.L0800ae54
.L0800adfa:
	bl	fn_0800c0c8
	b.n	.L0800ae52
.L0800ae00:
	ldrb	r1, [r0, #3]
	cmp	r1, #0x7f
	bhi.n	.L0800ae64
	ldrb	r1, [r0, #2]
	cbnz	r1, .L0800ae64
	ldrh	r1, [r0, #4]
	cbnz	r1, .L0800ae64
	ldrb	r0, [r0, #0xa]
	b.n	.L0800ae62
.L0800ae12:
	ldrb	r1, [r0, #3]
	cmp	r1, #1
	bne.n	.L0800ae54
	ldrh	r0, [r0, #4]
	cbnz	r0, .L0800ae54
	bl	fn_0800c100
	b.n	.L0800ae52
.L0800ae22:
	ldrb	r1, [r0, #3]
	cmp	r1, #1
	bne.n	.L0800ae54
	ldrh	r1, [r0, #4]
	cbnz	r1, .L0800ae54
	ldrb	r0, [r0, #9]
	lsls	r0, r0, #0x1a
	bmi.n	.L0800ae48
	b.n	.L0800ae54
.L0800ae34:
	cmp	r4, #0xb
	bne.n	.L0800ae54
	bl	fn_0800c1ac
	b.n	.L0800ae52
.L0800ae3e:
	cmp	r4, #1
	beq.n	.L0800ae48
	cmp	r4, #3
	beq.n	.L0800ae4e
	b.n	.L0800ae54
.L0800ae48:
	bl	fn_0800becc
	b.n	.L0800ae52
.L0800ae4e:
	bl	fn_0800c124
.L0800ae52:
	cbz	r0, .L0800ae6c
.L0800ae54:
	ldr	r1, .L0800ae90
	mov	r0, r4
	ldr	r1, [r1]
	ldr	r1, [r1, #0x14]
	blx	r1
	cmp	r0, #3
	beq.n	.L0800ae68
.L0800ae62:
	cbz	r0, .L0800ae6c
.L0800ae64:
	movs	r0, #8
	b.n	.L0800ae84
.L0800ae68:
	movs	r0, #9
	b.n	.L0800ae84
.L0800ae6c:
	ldr	r2, .L0800ae94
	movs	r0, #6
	movs	r1, #0
	ldr	r2, [r2]
	ldr	r3, .L0800ae98
	lsls	r2, r2, #0x10
	add.w	r2, r3, r2, lsr #0xf
	str	r1, [r2, #4]
	ldr	r2, .L0800ae9c
	movs	r1, #0x30
	strh	r1, [r2]
.L0800ae84:
	ldr	r1, [r5]
	strb	r0, [r1, #8]
	pop	{r4, r5, r6, pc}
	.short	0x0000	@ padding
.L0800ae8c:
	.word	0x200002bc
.L0800ae90:
	.word	0x200002c0
.L0800ae94:
	.word	0x40005c50
.L0800ae98:
	.word	0x40006000
.L0800ae9c:
	.word	0x200002cc

@ ----------------------------------------------------------------------------
@ fn_0800aea0 - r0 = index, r1 = flag. Reads the word at 0x40002000 + r0 * 4
@ (0x40002000 is the OPAMP block of the N32G455 memory map), clears bit 0 when
@ r1 is 0 and sets bit 0 otherwise, writes it back.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800aea0,"ax",%progbits
	.p2align 2
	.global fn_0800aea0
	.thumb_func
	.type fn_0800aea0, %function
fn_0800aea0:
	ldr	r2, .L0800aebc
	cmp	r1, #0
	add.w	r0, r2, r0, lsl #2
	ldr	r1, [r0]
	beq.n	.L0800aeb2
	orr.w	r1, r1, #1
	b.n	.L0800aeb6
.L0800aeb2:
	bic.w	r1, r1, #1
.L0800aeb6:
	str	r1, [r0]
	bx	lr
	.short	0x0000	@ padding
.L0800aebc:
	.word	0x40002000

@ ----------------------------------------------------------------------------
@ fn_0800aec0 - r0 = index, r1 = pointer to 4 bytes; no return value.
@ Reads the word w at 0x40002000 + r0 * 4 (OPAMP block) and keeps it in a
@ stack slot [sp]. Clears bits 0x38 and ors byte 2 of r1. Byte 1 = 1 sets bit
@ 0x8000, otherwise it is cleared. Byte 0 = 1 sets bit 0x10000, otherwise it is
@ cleared. Clears bits 0x6, ors byte 3 and writes the word back to
@ 0x40002000 + r0 * 4.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800aec0,"ax",%progbits
	.p2align 2
	.global fn_0800aec0
	.thumb_func
	.type fn_0800aec0, %function
fn_0800aec0:
	ldr	r2, .L0800af0c
	push	{r3, lr}
	add.w	r0, r2, r0, lsl #2
	ldr	r2, [r0]
	str	r2, [sp]
	ldrb	r3, [r1, #2]
	bic.w	r2, r2, #0x38
	orrs	r2, r3
	str	r2, [sp]
	ldrb	r2, [r1, #1]
	cmp	r2, #1
	ldr	r2, [sp]
	beq.n	.L0800af00
	bic.w	r2, r2, #0x8000
.L0800aee2:
	str	r2, [sp]
	ldrb	r2, [r1]
	cmp	r2, #1
	ldr	r2, [sp]
	beq.n	.L0800af06
	bic.w	r2, r2, #0x10000
.L0800aef0:
	str	r2, [sp]
	ldrb	r1, [r1, #3]
	bic.w	r2, r2, #6
	orrs	r2, r1
	str	r2, [sp]
	str	r2, [r0]
	pop	{r3, pc}
.L0800af00:
	orr.w	r2, r2, #0x8000
	b.n	.L0800aee2
.L0800af06:
	orr.w	r2, r2, #0x10000
	b.n	.L0800aef0
.L0800af0c:
	.word	0x40002000

@ ----------------------------------------------------------------------------
@ fn_0800af10 - r0 = index, r1 = bits. Word at 0x40002000 + r0 * 4 (OPAMP
@ block) = (word & 0xffffff3f) | r1; the value is also kept in a stack slot.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800af10,"ax",%progbits
	.p2align 2
	.global fn_0800af10
	.thumb_func
	.type fn_0800af10, %function
fn_0800af10:
	ldr	r2, .L0800af28
	push	{r3, lr}
	add.w	r0, r2, r0, lsl #2
	ldr	r2, [r0]
	bic.w	r2, r2, #0xc0
	orrs	r2, r1
	str	r2, [sp]
	str	r2, [r0]
	pop	{r3, pc}
	.short	0x0000	@ padding
.L0800af28:
	.word	0x40002000

@ ----------------------------------------------------------------------------
@ fn_0800af2c - r0 = index, r1 = bits. Word at 0x40002000 + r0 * 4 (OPAMP
@ block) = (word & 0xfffff8ff) | r1; the value is also kept in a stack slot.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800af2c,"ax",%progbits
	.p2align 2
	.global fn_0800af2c
	.thumb_func
	.type fn_0800af2c, %function
fn_0800af2c:
	ldr	r2, .L0800af44
	push	{r3, lr}
	add.w	r0, r2, r0, lsl #2
	ldr	r2, [r0]
	bic.w	r2, r2, #0x700
	orrs	r2, r1
	str	r2, [sp]
	str	r2, [r0]
	pop	{r3, pc}
	.short	0x0000	@ padding
.L0800af44:
	.word	0x40002000

@ ----------------------------------------------------------------------------
@ fn_0800b250 - resets the USB device registers; no parameters; returns 0.
@ Writes 1 then 0 to USB_CTRL (0x40005c40), 0 to USB_STS (0x40005c44), then
@ 0x1c00 to halfword 0x200002c8 and to USB_CTRL (0x40005c40).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b250,"ax",%progbits
	.p2align 2
	.global fn_0800b250
	.thumb_func
	.type fn_0800b250, %function
fn_0800b250:
	ldr	r0, .L0800b26c
	movs	r1, #1
	str	r1, [r0]
	movs	r1, #0
	ldr	r2, .L0800b270
	str	r1, [r0]
	adds	r3, r0, #4
	str	r1, [r3]
	mov.w	r1, #0x1c00
	strh	r1, [r2]
	str	r1, [r0]
	movs	r0, #0
	bx	lr
.L0800b26c:
	.word	0x40005c40
.L0800b270:
	.word	0x200002c8

@ ----------------------------------------------------------------------------
@ fn_0800b274 - no parameters. Calls fn_08008350(0x40010800, 0x100, 0)
@ (0x40010800 is GPIOA; r1 = 0x100 = pin 8) and then tail-branches (b.w) to
@ fn_08009e60(0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b274,"ax",%progbits
	.p2align 2
	.global fn_0800b274
	.thumb_func
	.type fn_0800b274, %function
fn_0800b274:
	push	{r4, lr}
	movs	r2, #0
	mov.w	r1, #0x100
	ldr	r0, .L0800b28c
	bl	fn_08008350
	pop.w	{r4, lr}
	movs	r0, #0
	b.w	fn_08009e60
.L0800b28c:
	.word	0x40010800

@ ----------------------------------------------------------------------------
@ fn_0800b420 - sends the next 0x40-byte block of a read of the drive area
@ (0x08068000) to the bulk-in endpoint; r0 = first value, r1 = second value,
@ no return value. Entered by the tail branch at 0x0800b7ea of fn_0800b7d4.
@ r4 = 0x200003b8 (state byte st), r5 = 0x200003b0 (word k); literals
@ 0x0800b4b4..0x0800b4c4 = 0x200003b8, 0x200003b0, 0x20005e74, 0x200066d4,
@ 0x20000438.
@ st = 0: r0 = r0 * k, r1 = r1 * k, strd stores them as words 0x200003c4 (+12)
@ and 0x200003c8 (+16), stores 1 in st, then continues as st = 1.
@ st = 1: when word 0x200003bc (+4) is nonzero: calls fn_08010130(0x81,
@ 0x20005e74 + word 0x200003d4 (+28), 0x40), subtracts 0x40 from word +4 and
@ adds 0x40 to word +28; when word +4 is 0 (.L0800b496): calls
@ copy_words_from_0x08068000_plus_offset(word +12, 0x20005e74, uxth(k)), calls
@ fn_08010130(0x81, 0x20005e74, 0x40), stores k - 0x40 in word +4 and 0x40 in
@ word +28 (r0 = 0x40, then b to .L0800b45a, which skips the adds at
@ 0x0800b458 and stores r0 into word +28 as it is).
@ Both st = 1 cases then call fn_080100d4(1, 0x40) and fn_0800ba1c(1, 0x30),
@ add 0x40 to word +12, subtract 0x40 from word +16 and from word 0x200066dc
@ (0x200066d4 + 8). Any other st skips all of that and goes to the final test.
@ Final test (.L0800b480): when word +16 (0x200003c8) is 0: clears words +4,
@ +28 and +12, stores 3 in byte 0x20000438 and 0 in st; returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b420,"ax",%progbits
	.p2align 2
	.global fn_0800b420
	.thumb_func
	.type fn_0800b420, %function
fn_0800b420:
	push	{r4, r5, r6, lr}
	ldr	r4, .L0800b4b4
	ldr	r5, .L0800b4b8
	ldrb	r3, [r4]
	ldr	r2, [r5]
	cbz	r3, .L0800b432
	cmp	r3, #1
	beq.n	.L0800b43e
	b.n	.L0800b480
.L0800b432:
	muls	r0, r2, r0
	muls	r1, r2, r1
	strd	r0, r1, [r4, #0xc]
	movs	r0, #1
	strb	r0, [r4]
.L0800b43e:
	ldr	r0, [r4, #4]
	cbz	r0, .L0800b496
	ldr	r0, .L0800b4bc
	ldr	r1, [r4, #0x1c]
	movs	r2, #0x40
	add	r1, r0
	movs	r0, #0x81
	bl	fn_08010130
	ldr	r0, [r4, #4]
	subs	r0, #0x40
	str	r0, [r4, #4]
	ldr	r0, [r4, #0x1c]
	adds	r0, #0x40
.L0800b45a:
	str	r0, [r4, #0x1c]
	movs	r1, #0x40
	movs	r0, #1
	bl	fn_080100d4
	movs	r1, #0x30
	movs	r0, #1
	bl	fn_0800ba1c
	ldr	r0, [r4, #0xc]
	adds	r0, #0x40
	str	r0, [r4, #0xc]
	ldr	r0, [r4, #0x10]
	subs	r0, #0x40
	str	r0, [r4, #0x10]
	ldr	r0, .L0800b4c0
	ldr	r1, [r0, #8]
	subs	r1, #0x40
	str	r1, [r0, #8]
.L0800b480:
	ldr	r0, [r4, #0x10]
	cmp	r0, #0
	bne.n	.L0800b494
	str	r0, [r4, #4]
	str	r0, [r4, #0x1c]
	ldr	r2, .L0800b4c4
	movs	r1, #3
	str	r0, [r4, #0xc]
	strb	r1, [r2]
	strb	r0, [r4]
.L0800b494:
	pop	{r4, r5, r6, pc}
.L0800b496:
	uxth	r2, r2
	ldr	r1, .L0800b4bc
	ldr	r0, [r4, #0xc]
	bl	copy_words_from_0x08068000_plus_offset
	movs	r2, #0x40
	ldr	r1, .L0800b4bc
	movs	r0, #0x81
	bl	fn_08010130
	ldr	r0, [r5]
	subs	r0, #0x40
	str	r0, [r4, #4]
	movs	r0, #0x40
	b.n	.L0800b45a
.L0800b4b4:
	.word	0x200003b8
.L0800b4b8:
	.word	0x200003b0
.L0800b4bc:
	.word	0x20005e74
.L0800b4c0:
	.word	0x200066d4
.L0800b4c4:
	.word	0x20000438

@ ----------------------------------------------------------------------------
@ fn_0800b634 - small state machine on byte 0x200003a8; r0 = state or 7.
@ Unless r0 is 7 stores r0 in byte 0x200003a8, then by that state (a tbb for
@ states below 6):
@ 0 = when word 0x200003ac is non-zero stores 5, otherwise calls fn_0800b6c4
@     and stores 6.
@ 1 = calls fn_0800b6c4, stores 4 in the byte and writes 1 to the word
@     0x200003ac.
@ 2 = stores 3 in the state byte and 2 in byte 0x200003a9.
@ 3 = decrements byte 0x200003a9 and, only when it reaches 0, stores 4 in the
@     state byte.
@ 4 = sets bit 0x10 in USB_CTRL (0x40005c40, the word is first limited to its
@     low 16 bits), stores 10 in 0x200003a9 and 5 in the state.
@ 5 = counts 0x200003a9 down; at 0 clears bit 0x10 of 0x40005c40 (low 16 bits
@     kept), stores 6 in the state byte and writes 0 to word 0x200003ac.
@ Other states store 6.
@ Registers: r2 = r3 = 0x200003a8, r0 = 0x40005c40, r5 = 6, r1 = 5, r4 = 4.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b634,"ax",%progbits
	.p2align 2
	.global fn_0800b634
	.thumb_func
	.type fn_0800b634, %function
fn_0800b634:
	push	{r4, r5, r6, r7, lr}
	ldr	r2, .L0800b6bc
	cmp	r0, #7
	beq.n	.L0800b63e
	strb	r0, [r2]
.L0800b63e:
	ldrb	r6, [r2]
	ldr	r3, .L0800b6bc
	movs	r5, #6
	movs	r1, #5
	movs	r4, #4
	ldr	r0, .L0800b6c0
	cmp	r6, #6
	bcs.n	.L0800b664
	tbb	[pc, r6]
.L0800b652:
	.byte	(.L0800b658 - .L0800b652)/2	@ state 0
	.byte	(.L0800b668 - .L0800b652)/2	@ state 1
	.byte	(.L0800b672 - .L0800b652)/2	@ state 2
	.byte	(.L0800b67c - .L0800b652)/2	@ state 3
	.byte	(.L0800b68c - .L0800b652)/2	@ state 4
	.byte	(.L0800b69e - .L0800b652)/2	@ state 5
.L0800b658:
	ldr	r0, [r3, #4]
	cbz	r0, .L0800b660
	strb	r1, [r2]
	pop	{r4, r5, r6, r7, pc}
.L0800b660:
	bl	fn_0800b6c4
.L0800b664:
	strb	r5, [r2]
	pop	{r4, r5, r6, r7, pc}
.L0800b668:
	bl	fn_0800b6c4
	strb	r4, [r2]
	movs	r0, #1
	b.n	.L0800b6b8
.L0800b672:
	movs	r0, #2
	strb	r0, [r2, #1]
	movs	r0, #3
	strb	r0, [r2]
.L0800b67a:
	pop	{r4, r5, r6, r7, pc}
.L0800b67c:
	ldrb	r0, [r2, #1]
	.inst.n	0x1e40	@ subs r0, r0, #1
	strb	r0, [r2, #1]
	ldrb	r0, [r2, #1]
	cmp	r0, #0
	bne.n	.L0800b67a
	strb	r4, [r2]
	pop	{r4, r5, r6, r7, pc}
.L0800b68c:
	ldr	r3, [r0]
	uxth	r3, r3
	orr.w	r3, r3, #0x10
	str	r3, [r0]
	strb	r1, [r2]
	movs	r0, #0xa
	strb	r0, [r2, #1]
.L0800b69c:
	pop	{r4, r5, r6, r7, pc}
.L0800b69e:
	ldrb	r1, [r2, #1]
	.inst.n	0x1e49	@ subs r1, r1, #1
	strb	r1, [r2, #1]
	ldrb	r1, [r2, #1]
	cmp	r1, #0
	bne.n	.L0800b69c
	ldr	r1, [r0]
	uxth	r1, r1
	bic.w	r1, r1, #0x10
	str	r1, [r0]
	strb	r5, [r2]
	movs	r0, #0
.L0800b6b8:
	str	r0, [r3, #4]
	pop	{r4, r5, r6, r7, pc}
.L0800b6bc:
	.word	0x200003a8
.L0800b6c0:
	.word	0x40005c40

@ ----------------------------------------------------------------------------
@ fn_0800b6c4 - no parameters. Clears bit 0x4 of USB_CTRL (0x40005c40, the word
@ is first limited to its low 16 bits), then writes 0x9e00 to it.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b6c4,"ax",%progbits
	.p2align 2
	.global fn_0800b6c4
	.thumb_func
	.type fn_0800b6c4, %function
fn_0800b6c4:
	ldr	r0, .L0800b6d8
	ldr	r1, [r0]
	uxth	r1, r1
	bic.w	r1, r1, #4
	str	r1, [r0]
	mov.w	r1, #0x9e00
	str	r1, [r0]
	bx	lr
.L0800b6d8:
	.word	0x40005c40

@ ----------------------------------------------------------------------------
@ fn_0800b6dc - checks a block range of a read or write command; r0 = command
@ (0x2a or other), r1 = start block, r2 = block count; returns 0 or 1.
@ When r1 + r2 exceeds word 0x200003b4: calls fn_080081c8(2) if r0 = 0x2a, then
@ fn_080081c8(0), code 0x21.
@ Otherwise, when word 0x200066bc equals word 0x200003b0 * r2 returns 1.
@ Otherwise calls fn_080081c8 with 2 (r0 = 0x2a) or 0, code 0x24.
@ Then calls store_two_bytes(5, code) and fn_0800bb1c(1, 0); returns 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b6dc,"ax",%progbits
	.p2align 2
	.global fn_0800b6dc
	.thumb_func
	.type fn_0800b6dc, %function
fn_0800b6dc:
	ldr	r3, .L0800b730
	push	{r4, lr}
	ldr	r3, [r3]
	add	r1, r2
	cmp	r1, r3
	bls.n	.L0800b6fc
	cmp	r0, #0x2a
	bne.n	.L0800b6f2
	movs	r0, #2
	bl	fn_080081c8
.L0800b6f2:
	movs	r0, #0
	bl	fn_080081c8
	movs	r1, #0x21
	b.n	.L0800b716
.L0800b6fc:
	ldr	r3, .L0800b738
	ldr	r1, .L0800b734
	ldr	r3, [r3]
	ldr	r1, [r1, #8]
	muls	r2, r3, r2
	cmp	r1, r2
	beq.n	.L0800b72c
	cmp	r0, #0x2a
	beq.n	.L0800b728
	movs	r0, #0
.L0800b710:
	bl	fn_080081c8
	movs	r1, #0x24
.L0800b716:
	movs	r0, #5
	bl	store_two_bytes
	movs	r1, #0
	movs	r0, #1
	bl	fn_0800bb1c
	movs	r0, #0
	pop	{r4, pc}
.L0800b728:
	movs	r0, #2
	b.n	.L0800b710
.L0800b72c:
	movs	r0, #1
	pop	{r4, pc}
.L0800b730:
	.word	0x200003b4
.L0800b734:
	.word	0x200066b4
.L0800b738:
	.word	0x200003b0

@ ----------------------------------------------------------------------------
@ fn_0800b73c - no parameters; returns with r0 = 0 when fn_0800a9ec() gave 0,
@ otherwise whatever fn_080081c8(0) returns (tail call). Entered by the b.w at
@ 0x080084ec in fn_08008378.
@ Calls fn_0800a9ec(); when it returns 0 returns (pop {r4,pc}). Otherwise calls
@ store_two_bytes(2, 0x3a), calls fn_0800bb1c(1, 1) (r0 = r1 = 1), pops r4/lr
@ and tail-calls fn_080081c8(0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b73c,"ax",%progbits
	.p2align 2
	.global fn_0800b73c
	.thumb_func
	.type fn_0800b73c, %function
fn_0800b73c:
	push	{r4, lr}
	bl	fn_0800a9ec
	cmp	r0, #0
	beq.n	.L0800b760
	movs	r1, #0x3a
	movs	r0, #2
	bl	store_two_bytes
	movs	r1, #1
	mov	r0, r1
	bl	fn_0800bb1c
	pop.w	{r4, lr}
	movs	r0, #0
	b.w	fn_080081c8
.L0800b760:
	pop	{r4, pc}
	.short	0x0000	@ padding

@ ----------------------------------------------------------------------------
@ fn_0800b764 - no parameters, no return value; entered only by the tail jump
@ b.w at 0x08008494 (from fn_08008378); ends with a tail jump to
@ fn_0800c6f0(r0 = buffer address, r1 = byte count), so it returns to the
@ caller of fn_08008378.
@ r1 = 0x200066b4; r0 = byte [r1+0x10]; lsls #31 tests bit 0.
@ Bit 0 set: r0 = 0x200003dc, r1 = 5.
@ Bit 0 clear: r1 = byte [0x200066b4 + 0x13]; r0 = 0x200003e1; r1 above 0x24
@ is replaced by 0x24, so r1 = min(byte, 0x24).
@ Then b.w fn_0800c6f0(r0, r1).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b764,"ax",%progbits
	.p2align 2
	.global fn_0800b764
	.thumb_func
	.type fn_0800b764, %function
fn_0800b764:
	ldr	r1, .L0800b780
	ldrb	r0, [r1, #0x10]
	lsls	r0, r0, #0x1f
	beq.n	.L0800b772
	ldr	r0, .L0800b784
	movs	r1, #5
	b.n	.L0800b77c
.L0800b772:
	ldrb	r1, [r1, #0x13]
	ldr	r0, .L0800b788
	cmp	r1, #0x24
	bls.n	.L0800b77c
	movs	r1, #0x24
.L0800b77c:
	b.w	fn_0800c6f0
.L0800b780:
	.word	0x200066b4
.L0800b784:
	.word	0x200003dc
.L0800b788:
	.word	0x200003e1

@ ----------------------------------------------------------------------------
@ fn_0800b78c - no parameters; returns what fn_0800bb1c returns (tail call).
@ r0 = 0x200066b4; r1 = word 0x200066bc ([r0+8]); r0 = 0 when r1 is 0 or bit 7
@ of byte 0x200066c0 ([r0+12]) is set, else r0 = 2; calls fn_080081c8(r0), then
@ store_two_bytes(5, 0x20), then tail-calls fn_0800bb1c(1, 0) (b.w).
@ Entered by the b.w at 0x080084f4 in fn_08008378.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b78c,"ax",%progbits
	.p2align 2
	.global fn_0800b78c
	.thumb_func
	.type fn_0800b78c, %function
fn_0800b78c:
	ldr	r0, .L0800b7b8
	push	{r4, lr}
	ldr	r1, [r0, #8]
	cbz	r1, .L0800b79a
	ldrb	r0, [r0, #0xc]
	lsls	r0, r0, #0x18
	bpl.n	.L0800b79e
.L0800b79a:
	movs	r0, #0
	b.n	.L0800b7a0
.L0800b79e:
	movs	r0, #2
.L0800b7a0:
	bl	fn_080081c8
	movs	r1, #0x20
	movs	r0, #5
	bl	store_two_bytes
	movs	r1, #0
	pop.w	{r4, lr}
	movs	r0, #1
	b.w	fn_0800bb1c
.L0800b7b8:
	.word	0x200066b4

@ ----------------------------------------------------------------------------
@ fn_0800b7bc - no parameters; returns what fn_0800c6f0 returns (tail call).
@ r1 = 8, r0 = 0x20000409; tail-calls fn_0800c6f0(0x20000409, 8) (b.w).
@ Entered only by the b.w at 0x080084ac in fn_08008378, so it returns to the
@ caller of fn_08008378.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b7bc,"ax",%progbits
	.p2align 2
	.global fn_0800b7bc
	.thumb_func
	.type fn_0800b7bc, %function
fn_0800b7bc:
	movs	r1, #8
	ldr	r0, .L0800b7c4
	b.w	fn_0800c6f0
.L0800b7c4:
	.word	0x20000409

@ ----------------------------------------------------------------------------
@ fn_0800b7c8 - no parameters, no return value; entered only by the tail jump
@ b.w at 0x080084a4 (from fn_08008378). r1 = 4, r0 = 0x20000405; b.w
@ fn_0800c6f0(0x20000405, 4), so it returns to the caller of fn_08008378.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b7c8,"ax",%progbits
	.p2align 2
	.global fn_0800b7c8
	.thumb_func
	.type fn_0800b7c8, %function
fn_0800b7c8:
	movs	r1, #4
	ldr	r0, .L0800b7d0
	b.w	fn_0800c6f0
.L0800b7d0:
	.word	0x20000405

@ ----------------------------------------------------------------------------
@ fn_0800b7d4 - read-command step; r0 = first value (kept in r6), r1 = second
@ value (kept in r5); no return value. Reads byte 0x20000438 (v).
@ v = 2: restores r4..r6, lr and tail-calls fn_0800b420(r6, r5) (b.w at
@ 0x0800b7ea).
@ v = 0: calls fn_0800b6dc(0x28, r6, r5) and returns when it returns 0;
@ otherwise tests bit 7 of byte 0x200066c0 (0x200066b4 + 12): bit set stores 2
@ in byte 0x20000438 and tail-calls fn_0800b420(r6, r5); bit clear calls
@ fn_080081c8(2), store_two_bytes(5, 0x24) and tail-calls fn_0800bb1c(1, 1).
@ Any other v returns at once (.L0800b828).
@ Literals: 0x0800b82c = 0x20000438, 0x0800b830 = 0x200066b4.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b7d4,"ax",%progbits
	.p2align 2
	.global fn_0800b7d4
	.thumb_func
	.type fn_0800b7d4, %function
fn_0800b7d4:
	push	{r4, r5, r6, lr}
	ldr	r4, .L0800b82c
	mov	r5, r1
	mov	r6, r0
	ldrb	r1, [r4]
	cbz	r1, .L0800b7ee
	cmp	r1, #2
	bne.n	.L0800b828
	mov	r1, r5
.L0800b7e6:
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800b420
.L0800b7ee:
	mov	r1, r0
	mov	r2, r5
	movs	r0, #0x28
	bl	fn_0800b6dc
	cmp	r0, #0
	beq.n	.L0800b828
	ldr	r0, .L0800b830
	ldrb	r0, [r0, #0xc]
	lsls	r0, r0, #0x18
	mov.w	r0, #2
	bpl.n	.L0800b810
	strb	r0, [r4]
	mov	r1, r5
	mov	r0, r6
	b.n	.L0800b7e6
.L0800b810:
	bl	fn_080081c8
	movs	r1, #0x24
	movs	r0, #5
	bl	store_two_bytes
	pop.w	{r4, r5, r6, lr}
	movs	r1, #1
	mov	r0, r1
	b.w	fn_0800bb1c
.L0800b828:
	pop	{r4, r5, r6, pc}
	.short	0x0000	@ padding
.L0800b82c:
	.word	0x20000438
.L0800b830:
	.word	0x200066b4

@ ----------------------------------------------------------------------------
@ fn_0800b834 - no parameters; returns what its tail target returns. Entered by
@ the b.w at 0x080084bc in fn_08008378.
@ Calls fn_0800a9ec() (it stores 0x2e to word 0x200003b4 and 0x800 to word
@ 0x200003b0 and returns 0).
@ Result nonzero (.L0800b83a falls through): store_two_bytes(2, 0x3a),
@ fn_0800bb1c(1, 1), tail-call fn_080081c8(0) (b.w at 0x0800b852).
@ Result 0 (.L0800b856): stores word 0x200003b4 minus 1 as four bytes, most
@ significant first, to 0x20000423..0x20000426, stores word 0x200003b0 as four
@ bytes, most significant first, to 0x20000427..0x2000042a, then tail-calls
@ fn_0800c6f0(0x20000423, 8) (b.w at 0x0800b884).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b834,"ax",%progbits
	.p2align 2
	.global fn_0800b834
	.thumb_func
	.type fn_0800b834, %function
fn_0800b834:
	push	{r4, lr}
	bl	fn_0800a9ec
	cbz	r0, .L0800b856
	movs	r1, #0x3a
	movs	r0, #2
	bl	store_two_bytes
	movs	r1, #1
	mov	r0, r1
	bl	fn_0800bb1c
	pop.w	{r4, lr}
	movs	r0, #0
	b.w	fn_080081c8
.L0800b856:
	ldr	r0, .L0800b888
	ldr	r1, [r0]
	ldr	r0, .L0800b88c
	.inst.n	0x1e49	@ subs r1, r1, #1
	lsrs	r2, r1, #0x18
	strb	r2, [r0]
	lsrs	r2, r1, #0x10
	strb	r2, [r0, #1]
	lsrs	r2, r1, #8
	strb	r2, [r0, #2]
	strb	r1, [r0, #3]
	ldr	r1, .L0800b890
	ldr	r1, [r1]
	lsrs	r2, r1, #0x18
	strb	r2, [r0, #4]
	lsrs	r2, r1, #0x10
	strb	r2, [r0, #5]
	lsrs	r2, r1, #8
	strb	r2, [r0, #6]
	strb	r1, [r0, #7]
	pop.w	{r4, lr}
	movs	r1, #8
	b.w	fn_0800c6f0
.L0800b888:
	.word	0x200003b4
.L0800b88c:
	.word	0x20000423
.L0800b890:
	.word	0x200003b0
