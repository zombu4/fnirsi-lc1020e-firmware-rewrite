@ ui_42.s - user-interface code: screen builders fn_0800d50c, fn_0800d6e4, fn_0800d850 and the units that follow in the address range 0x0800d50c..0x0800e224
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0800d50c - builds a screen: no parameters, no return value.
@ Calls fn_0800ca2c, then stores 2 to the words 0x20001178 and 0x20001168.
@ If the word 0x20001148 is 2, stores r1 (= 2) to the word 0x20001178 and the
@ byte 0x200011e4 (.L0800d698). If it is 3, stores 3 there. Otherwise stores 1
@ to the words 0x20001178 and 0x20001148 and to the byte 0x200011e4, prints "%s"
@ of the entry word[0x2000025c + word[0x2000115c] * 24 + 4] through
@ fn_080228d0 on the object in 0x200001f0, then sets the texts of the objects in
@ 0x200001fc and 0x200001e8 with fn_08021c14.
@ Then calls fn_08023050(object, 1) on the objects in 0x200001f8, the eight
@ words 0x200059c8..0x200059e4 and the object in 0x20000220.
@ Creates the objects stored in 0x20000204, 0x20000208, 0x20000218,
@ 0x20000214, 0x2000020c and 0x20000210 (fn_0802122c, fn_08021f5c), positions
@ them with fn_08023170, sets colours with rgb_to_565_0801d7c2(0xff, 0) and
@ rgb_to_565_0801d7c2(0, 0xff) through fn_08026694, writes the text "00.00" to
@ 0x20000218 and "%03d" of the words 0x200050f0 and 0x200050f4 to the objects
@ 0x2000020c and 0x20000210. Ends with a tail call to fn_0800f854.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800d50c,"ax",%progbits
	.p2align 2
	.global fn_0800d50c
	.thumb_func
	.type fn_0800d50c, %function
fn_0800d50c:
	push	{r4, r5, r6, lr}
	bl	fn_0800ca2c
	ldr	r0, .L0800d6a8		@ 0x2000057c
	movs	r1, #2
	ldr	r4, .L0800d6ac		@ 0x200001d4
	str.w	r1, [r0, #0xbec]	@ word 0x20001168 = 2
	ldr.w	r2, [r0, #0xbcc]	@ word 0x20001148
	cmp	r2, #2
	beq.n	.L0800d620
	cmp	r2, #3
	beq.n	.L0800d622
	movs	r1, #1
	str.w	r1, [r0, #0xbfc]	@ word 0x20001178 = 1
	strb.w	r1, [r0, #0xc68]	@ byte 0x200011e4 = 1
	str.w	r1, [r0, #0xbcc]	@ word 0x20001148 = 1
	ldr.w	r0, [r0, #0xbe0]	@ word 0x2000115c
	add.w	r1, r4, #0x84		@ table 0x2000025c
	add.w	r0, r0, r0, lsl #1
	add.w	r0, r1, r0, lsl #3	@ table + index * 24
	adr	r1, .L0800d6b0		@ "%s"
	ldr	r2, [r0, #4]
	ldr	r0, [r4, #0x1c]		@ object 0x200001f0
	bl	fn_080228d0
	ldr	r1, .L0800d6b4
	ldr	r0, [r4, #0x28]		@ object 0x200001fc
	bl	fn_08021c14
	ldr	r1, .L0800d6b8
	ldr	r0, [r4, #0x14]		@ object 0x200001e8
	bl	fn_08021c14
.L0800d560:
	movs	r1, #1
	ldr	r0, [r4, #0x24]		@ object 0x200001f8
	bl	fn_08023050
	ldr	r6, .L0800d6bc		@ 0x200059a8
	movs	r5, #0
.L0800d56c:
	add.w	r0, r6, r5, lsl #2
	movs	r1, #1
	ldr	r0, [r0, #0x20]		@ words 0x200059c8..0x200059e4
	bl	fn_08023050
	.inst.n	0x1c6d		@ adds r5, r5, #1
	cmp	r5, #8
	blt.n	.L0800d56c
	ldr	r0, .L0800d6ac
	movs	r1, #1
	adds	r0, #0x48
	ldr	r0, [r0, #4]		@ object 0x20000220
	bl	fn_08023050
	ldr	r0, [r4, #4]		@ object 0x200001d8
	bl	fn_0802122c
	movs	r3, #0x28
	movs	r2, #0
	movs	r1, #9
	str	r0, [r4, #0x30]		@ 0x20000204
	bl	fn_08023170
	ldr	r1, .L0800d6c0
	ldr	r0, [r4, #0x30]
	bl	fn_08021c14
	ldr	r0, [r4, #0x30]
	bl	fn_08021f5c
	mvn	r3, #6
	lsls	r2, r3, #3		@ -56
	movs	r1, #5
	str	r0, [r4, #0x34]		@ 0x20000208
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800d6c4
	ldr	r0, [r4, #0x34]
	bl	fn_080266ac
	ldr	r0, [r4, #4]
	bl	fn_08021f5c
	mvn	r3, #0x59
	mvn	r2, #0x62
	movs	r1, #6
	str	r0, [r4, #0x44]		@ 0x20000218
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800d6c8
	ldr	r0, [r4, #0x44]
	bl	fn_080266ac
	adr	r2, .L0800d6cc		@ "00.00"
	adr	r1, .L0800d6b0		@ "%s"
	ldr	r0, [r4, #0x44]
	bl	fn_080228d0
	ldr	r0, [r4, #0x30]
	bl	fn_08021f5c
	str	r0, [r4, #0x40]		@ 0x20000214
	ldr	r0, [r4, #0x30]
	bl	fn_08021f5c
	str	r0, [r4, #0x38]		@ 0x2000020c
	ldr	r0, [r4, #0x30]
	bl	fn_08021f5c
	str	r0, [r4, #0x3c]		@ 0x20000210
	mvn	r3, #0x11
	movs	r2, #0x86
	movs	r1, #9
	ldr	r0, [r4, #0x40]
	bl	fn_08023170
	movs	r3, #0xf
	movs	r2, #0x86
	movs	r1, #9
	ldr	r0, [r4, #0x38]
	bl	fn_08023170
	b.n	.L0800d624
.L0800d620:
	b.n	.L0800d698
.L0800d622:
	b.n	.L0800d6a2
.L0800d624:
	movs	r3, #0xf
	movs	r2, #0x5a
	movs	r1, #9
	ldr	r0, [r4, #0x3c]
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800d6d4
	ldr	r0, [r4, #0x40]
	bl	fn_080266ac
	movs	r2, #0
	mov	r1, r2
	movs	r0, #0xff
	bl	rgb_to_565_0801d7c2
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r4, #0x40]
	bl	fn_08026694
	movs	r2, #0
	mov	r1, r2
	movs	r0, #0xff
	bl	rgb_to_565_0801d7c2
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r4, #0x3c]
	bl	fn_08026694
	movs	r2, #0
	movs	r1, #0xff
	mov	r0, r2
	bl	rgb_to_565_0801d7c2
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r4, #0x38]
	bl	fn_08026694
	ldr	r5, .L0800d6d8		@ 0x2000457c
	adr	r1, .L0800d6dc		@ "%03d"
	ldr	r0, [r4, #0x38]
	ldr.w	r2, [r5, #0xb74]	@ word 0x200050f0
	bl	fn_080228d0
	adr	r1, .L0800d6dc
	ldr.w	r2, [r5, #0xb78]	@ word 0x200050f4
	ldr	r0, [r4, #0x3c]
	bl	fn_080228d0
	pop.w	{r4, r5, r6, lr}
	b.w	fn_0800f854
.L0800d698:
	str.w	r1, [r0, #0xbfc]	@ word 0x20001178 = r1
	strb.w	r1, [r0, #0xc68]	@ byte 0x200011e4 = r1
	b.n	.L0800d560
.L0800d6a2:
	movs	r1, #3
	b.n	.L0800d698
	.short	0x0000			@ padding
.L0800d6a8:
	.word	0x2000057c
.L0800d6ac:
	.word	0x200001d4
.L0800d6b0:
	.asciz	"%s"
	.byte	0x00			@ padding
.L0800d6b4:
	.word	d_0803da44
.L0800d6b8:
	.word	d_0803d2fc
.L0800d6bc:
	.word	0x200059a8
.L0800d6c0:
	.word	d_0804095c
.L0800d6c4:
	.word	d_0802ce5c
.L0800d6c8:
	.word	d_0802f5e8
.L0800d6cc:
	.asciz	"00.00"
	.short	0x0000			@ padding
.L0800d6d4:
	.word	d_0802f0d8
.L0800d6d8:
	.word	0x2000457c
.L0800d6dc:
	.asciz	"%03d"
	.byte	0x00, 0x00, 0x00	@ padding

@ ----------------------------------------------------------------------------
@ fn_0800d6e4 - builds the first screen: no parameters; ends with a tail call
@ to fn_0800c848 with the screen object in r0.
@ Calls fn_08008350(0x40010c00, 0x2000, 1) and fn_08008350(0x40010c00, 0x1000, 1).
@ Stores 3 to the word 0x20001168, 0 to the words 0x2000114c, 0x200011a8,
@ 0x200011ac, 0x200011b0, 0x200011b4, 0x200011b8 and 0 to the byte 0x2000000c.
@ Creates object P = fn_08023678() (stored to 0x20000014), sets its colour from
@ rgb_to_565_0801d792(0, 0, 0) with fn_0802657a(P, c, 0), calls fn_0801ddd0(P),
@ creates the child objects a = fn_0802122c(P) (positioned with fn_08023170
@ (a, 2, 0, 0), text at 0x08044150), b = fn_0802122c(a) (positioned (b, 9,
@ -113, 0), text at 0x080442e4) and T = fn_08021f5c(a) (stored to 0x2000001c,
@ positioned (T, 7, 0x28, 2), fn_080266ac(T, 0x0802f0d8, 0)).
@ Prints with fn_080228d0(T, "%s%s", word[0x2000002c + word[0x2000115c] * 4], s)
@ where s is the string at .L0800d844 (bytes 28 e5 8e 82 e5 ae b6 29, the UTF-8
@ text "(" two characters ")") when the word 0x200011c0 is 2, else the empty
@ string at .L0800d838.
@ Then fn_0800f294(1, 0); Q = fn_08023678(P) is stored to 0x20000018 and set with
@ fn_08023170(Q, 5, 0, 0), fn_080263a8(Q, 320, 205), fn_08026592, fn_08026680,
@ fn_080265be, fn_0802662a (each (Q, 0, 0)) and fn_08026380(Q, 0); finally
@ tail-calls fn_0800c848(P).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800d6e4,"ax",%progbits
	.p2align 2
	.global fn_0800d6e4
	.thumb_func
	.type fn_0800d6e4, %function
fn_0800d6e4:
	push	{r3, r4, r5, r6, r7, lr}
	ldr	r4, .L0800d820		@ 0x40010c00
	movs	r2, #1
	lsls	r1, r2, #0xd		@ 0x2000
	mov	r0, r4
	bl	fn_08008350
	movs	r2, #1
	lsls	r1, r2, #0xc		@ 0x1000
	mov	r0, r4
	bl	fn_08008350
	ldr	r5, .L0800d824		@ 0x2000057c
	movs	r0, #3
	ldr	r4, .L0800d828		@ 0x2000000c
	str.w	r0, [r5, #0xbec]	@ word 0x20001168 = 3
	movs	r0, #0
	str.w	r0, [r5, #0xbd0]	@ word 0x2000114c = 0
	str.w	r0, [r5, #0xc2c]	@ word 0x200011a8 = 0
	str.w	r0, [r5, #0xc30]	@ word 0x200011ac = 0
	str.w	r0, [r5, #0xc34]	@ word 0x200011b0 = 0
	str.w	r0, [r5, #0xc38]	@ word 0x200011b4 = 0
	str.w	r0, [r5, #0xc3c]	@ word 0x200011b8 = 0
	strb	r0, [r4]		@ byte 0x2000000c = 0
	add.w	r5, r5, #0xbd0		@ r5 = 0x2000114c
	bl	fn_08023678
	movs	r2, #0
	str	r0, [r4, #8]		@ word 0x20000014 = P
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d792
	str	r0, [sp]
	ldrh.w	r1, [sp]
	movs	r2, #0
	ldr	r0, [r4, #8]
	bl	fn_0802657a
	ldr	r0, [r4, #8]
	bl	fn_0801ddd0
	ldr	r0, [r4, #8]
	bl	fn_0802122c
	movs	r3, #0
	mov	r7, r0
	mov	r2, r3
	movs	r1, #2
	bl	fn_08023170
	ldr	r1, .L0800d82c
	mov	r0, r7
	bl	fn_08021c14
	mov	r0, r7
	bl	fn_0802122c
	mov	r6, r0
	movs	r3, #0
	mvn	r2, #0x8e
	movs	r1, #9
	bl	fn_08023170
	ldr	r1, .L0800d830
	mov	r0, r6
	bl	fn_08021c14
	mov	r0, r7
	bl	fn_08021f5c
	movs	r3, #2
	movs	r2, #0x28
	movs	r1, #7
	str	r0, [r4, #0x10]		@ word 0x2000001c = T
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800d834
	ldr	r0, [r4, #0x10]
	bl	fn_080266ac
	ldr	r0, [r5, #0x74]		@ word 0x200011c0
	sub.w	r5, r5, #0xbd0		@ r5 = 0x2000057c
	cmp	r0, #2
	beq.n	.L0800d81c
	adr	r3, .L0800d838		@ empty string
.L0800d7a8:
	ldr	r1, .L0800d828
	ldr.w	r0, [r5, #0xbe0]	@ word 0x2000115c
	adds	r1, #0x20		@ table 0x2000002c
	ldr.w	r2, [r1, r0, lsl #2]
	adr	r1, .L0800d83c		@ "%s%s"
	ldr	r0, [r4, #0x10]
	bl	fn_080228d0
	movs	r1, #0
	movs	r0, #1
	bl	fn_0800f294
	ldr	r0, [r4, #8]
	bl	fn_08023678
	movs	r3, #0
	mov	r2, r3
	movs	r1, #5
	str	r0, [r4, #0xc]		@ word 0x20000018 = Q
	bl	fn_08023170
	movs	r2, #0xcd
	mov.w	r1, #0x140
	ldr	r0, [r4, #0xc]
	bl	fn_080263a8
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r4, #0xc]
	bl	fn_08026592
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r4, #0xc]
	bl	fn_08026680
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r4, #0xc]
	bl	fn_080265be
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r4, #0xc]
	bl	fn_0802662a
	movs	r1, #0
	ldr	r0, [r4, #0xc]
	bl	fn_08026380
	ldr	r0, [r4, #8]
	pop.w	{r3, r4, r5, r6, r7, lr}
	b.w	fn_0800c848
.L0800d81c:
	adr	r3, .L0800d844		@ the UTF-8 text in brackets
	b.n	.L0800d7a8
.L0800d820:
	.word	0x40010c00
.L0800d824:
	.word	0x2000057c
.L0800d828:
	.word	0x2000000c
.L0800d82c:
	.word	d_08044150
.L0800d830:
	.word	d_080442e4
.L0800d834:
	.word	d_0802f0d8
.L0800d838:
	.word	0x00000000		@ empty string
.L0800d83c:
	.asciz	"%s%s"
	.byte	0x00, 0x00, 0x00	@ padding
.L0800d844:
	.asciz	"(\345\216\202\345\256\266)"
	.byte	0x00, 0x00, 0x00	@ padding

@ ----------------------------------------------------------------------------
@ fn_0800d850 - sets the colours of two pairs of objects: no parameters; the
@ result is what the tail call fn_08026694 returns.
@ Prints the word 0x2000115c with the format "Sys.Config.Lang:%d\n" through
@ fn_0801031c. With r6 = 0x20005a08 and r7 = 0x20005a18, for i = 0 and 1:
@ c = rgb_to_565_0801d7f2(0x54, 0x54, 0x54), fn_0802659c(word[r6 + i*4], c, 0);
@ c = rgb_to_565_0801d7f2(0xff, 0xff, 0xff), fn_08026694(word[r7 + i*4], c, 0).
@ Then c = rgb_to_565_0801d7f2(0xfd, 0xd0, 0x1b), fn_0802659c(word[r6 +
@ word[0x2000115c] * 4], c, 0), and again c with the same colour and a tail call
@ to fn_08026694(word[r7 + word[0x2000115c] * 4], c, 0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800d850,"ax",%progbits
	.p2align 2
	.global fn_0800d850
	.thumb_func
	.type fn_0800d850, %function
fn_0800d850:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r5, .L0800d8d4		@ 0x2000057c
	adr	r0, .L0800d8d8		@ "Sys.Config.Lang:%d\n"
	ldr.w	r1, [r5, #0xbe0]	@ word 0x2000115c
	bl	fn_0801031c
	ldr	r6, .L0800d8ec		@ 0x20005a08
	movs	r4, #0
	add.w	r7, r6, #0x10		@ 0x20005a18
.L0800d868:
	movs	r2, #0x54
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d7f2
	mov	r1, r0
	ldr.w	r0, [r6, r4, lsl #2]
	movs	r2, #0
	bl	fn_0802659c
	movs	r2, #0xff
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d7f2
	mov	r1, r0
	ldr.w	r0, [r7, r4, lsl #2]
	movs	r2, #0
	bl	fn_08026694
	.inst.n	0x1c64		@ adds r4, r4, #1
	cmp	r4, #2
	blt.n	.L0800d868
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	bl	rgb_to_565_0801d7f2
	mov	r1, r0
	ldr.w	r0, [r5, #0xbe0]
	movs	r2, #0
	ldr.w	r0, [r6, r0, lsl #2]
	bl	fn_0802659c
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	bl	rgb_to_565_0801d7f2
	mov	r1, r0
	ldr.w	r0, [r5, #0xbe0]
	movs	r2, #0
	ldr.w	r0, [r7, r0, lsl #2]
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08026694
	.short	0x0000			@ padding
.L0800d8d4:
	.word	0x2000057c
.L0800d8d8:
	.asciz	"Sys.Config.Lang:%d\n"
.L0800d8ec:
	.word	0x20005a08

@ ----------------------------------------------------------------------------
@ fn_0800d8f0 - key handler: r0 = key mask; no return value of its own.
@ r1 = 0x2000057c (literal .L0800d938).
@ Mask 8: stores 1 to the word 0x20001140, calls fn_08014b94, calls
@ fn_08023690(word[0x20000288]) and tail-calls fn_0800ca2c.
@ Mask 0x10 or 4: increments the word 0x2000115c, stores 0 to it when the result
@ is above 1, then tail-calls fn_0800d850.
@ Any other mask returns.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800d8f0,"ax",%progbits
	.p2align 2
	.global fn_0800d8f0
	.thumb_func
	.type fn_0800d8f0, %function
fn_0800d8f0:
	push	{r4, lr}
	ldr	r1, .L0800d938		@ 0x2000057c
	cmp	r0, #8
	beq.n	.L0800d91c
	cmp	r0, #0x10
	beq.n	.L0800d900
	cmp	r0, #4
	bne.n	.L0800d936
.L0800d900:
	ldr.w	r0, [r1, #0xbe0]	@ word 0x2000115c
	.inst.n	0x1c40		@ adds r0, r0, #1
	str.w	r0, [r1, #0xbe0]
	cmp	r0, #1
	ble.n	.L0800d914
	movs	r0, #0
	str.w	r0, [r1, #0xbe0]	@ wraps back to 0
.L0800d914:
	pop.w	{r4, lr}
	b.w	fn_0800d850
.L0800d91c:
	movs	r0, #1
	str.w	r0, [r1, #0xbc4]	@ word 0x20001140 = 1
	bl	fn_08014b94
	ldr	r0, .L0800d93c		@ 0x20000288
	ldr	r0, [r0]
	bl	fn_08023690
	pop.w	{r4, lr}
	b.w	fn_0800ca2c
.L0800d936:
	pop	{r4, pc}
.L0800d938:
	.word	0x2000057c
.L0800d93c:
	.word	0x20000288

@ ----------------------------------------------------------------------------
@ fn_0800d940 - steps a setting: r0 = step (negative, 0 or positive).
@ The word 0x200011a8 selects the mode:
@ 0: steps the word 0x20001144 through the cycle 100 -> 0x78 -> 1000 -> 10000 ->
@    100000 -> 100 (step above 0) and 100000 -> 10000 -> 1000 -> 0x78 -> 100
@    (step below 0).
@ 1: switches the float 0x20001138 between 0x3f19999a, 0x3dcccccd and
@    0x3e99999a depending on its range and on the float 0x2000113c (compared
@    with 0x3dcccccd).
@ 2: when r0 is non-zero stores 0 to the float 0x2000113c (when it is above
@    0x3dcccccc) or 0x3f000000 to it, and 0x3e99999a to 0x20001138 when that is
@    above 0x3f000000.
@ 3: adds r0 to the word 0x2000114c, wraps 5 to 0 and below 0 to 4.
@ After a change in the modes 0 to 2 it tail-calls fn_08009f10.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800d940,"ax",%progbits
	.p2align 2
	.global fn_0800d940
	.thumb_func
	.type fn_0800d940, %function
fn_0800d940:
	push	{r4, r5, r6, r7}
	ldr	r2, .L0800da4c		@ 0x2000057c
	ldr.w	r6, [r2, #0xc2c]	@ word 0x200011a8 (mode)
	cbz	r6, .L0800d97a
	vldr	s0, .L0800da50		@ 0x3e99999a
	add.w	r1, r2, #0x800
	ldr	r5, .L0800da54		@ 0x3dcccccd
	ldrd	r3, r4, [r1, #0x3bc]	@ r3 = 0x20001138, r4 = 0x2000113c
	mov.w	r7, #0x3f000000
	cmp	r6, #1
	beq.n	.L0800d9dc
	cmp	r6, #2
	beq.n	.L0800da1c
	cmp	r6, #3
	bne.n	.L0800da48
	ldr.w	r1, [r2, #0xbd0]	@ word 0x2000114c
	add	r0, r1
	str.w	r0, [r2, #0xbd0]
	cmp	r0, #4
	ble.n	.L0800da3e
	movs	r0, #0
	b.n	.L0800da44
.L0800d97a:
	ldr	r1, .L0800da4c
	movs	r5, #0x64
	movs	r7, #0x78
	ldr	r3, .L0800da58		@ 100000
	ldr.w	r1, [r1, #0xbc8]	@ word 0x20001144
	mov.w	r6, #0x3e8
	movw	r4, #0x2710
	cmp	r0, #0
	ble.n	.L0800d9c4
	cmp	r1, #0x64
	beq.n	.L0800d9a4
	cmp	r1, #0x78
	beq.n	.L0800d9aa
	cmp	r1, r6
	bne.n	.L0800d9b0
.L0800d99e:
	str.w	r4, [r2, #0xbc8]	@ 10000
	b.n	.L0800da38
.L0800d9a4:
	str.w	r7, [r2, #0xbc8]	@ 0x78
	b.n	.L0800da38
.L0800d9aa:
	str.w	r6, [r2, #0xbc8]	@ 1000
	b.n	.L0800da38
.L0800d9b0:
	cmp	r1, r4
	bne.n	.L0800d9ba
.L0800d9b4:
	str.w	r3, [r2, #0xbc8]	@ 100000
	b.n	.L0800da38
.L0800d9ba:
	cmp	r1, r3
	bne.n	.L0800da38
.L0800d9be:
	str.w	r5, [r2, #0xbc8]	@ 100
	b.n	.L0800da38
.L0800d9c4:
	bge.n	.L0800da38
	cmp	r1, r3
	beq.n	.L0800d99e
	cmp	r1, r4
	beq.n	.L0800d9aa
	cmp	r1, r6
	beq.n	.L0800d9a4
	cmp	r1, #0x78
	beq.n	.L0800d9be
	cmp	r1, #0x64
	beq.n	.L0800d9b4
	b.n	.L0800da38
.L0800d9dc:
	ldr	r2, .L0800da5c		@ 0x3e4ccccd
	vldr	s2, .L0800da60		@ 0x3f19999a
	vldr	s1, .L0800da64		@ 0x3dcccccd
	cmp	r0, #0
	ble.n	.L0800da0c
	cmp	r3, r2
	bge.n	.L0800d9f6
	nop
.L0800d9f0:
	vstr	s0, [r1, #0x3bc]	@ float 0x20001138 = 0x3e99999a
	b.n	.L0800da38
.L0800d9f6:
	cmp	r3, r7
	bge.n	.L0800da06
	cmp	r4, r5
	bge.n	.L0800da06
	nop
.L0800da00:
	vstr	s2, [r1, #0x3bc]	@ float 0x20001138 = 0x3f19999a
	b.n	.L0800da38
.L0800da06:
	vstr	s1, [r1, #0x3bc]	@ float 0x20001138 = 0x3dcccccd
	b.n	.L0800da38
.L0800da0c:
	bge.n	.L0800da38
	cmp	r3, r7
	bgt.n	.L0800d9f0
	cmp	r3, r2
	bgt.n	.L0800da06
	cmp	r4, r5
	blt.n	.L0800da00
	b.n	.L0800d9f0
.L0800da1c:
	cbz	r0, .L0800da38
	cmp	r4, r5
	bge.n	.L0800da30
	vmov.f32	s1, #0.5
	vstr	s1, [r1, #0x3c0]	@ float 0x2000113c = 0x3f000000
	cmp	r3, r7
	bgt.n	.L0800d9f0
	b.n	.L0800da38
.L0800da30:
	vldr	s0, .L0800da68		@ 0
	vstr	s0, [r1, #0x3c0]	@ float 0x2000113c = 0
.L0800da38:
	pop	{r4, r5, r6, r7}
	b.w	fn_08009f10
.L0800da3e:
	cmp	r0, #0
	bge.n	.L0800da48
	movs	r0, #4
.L0800da44:
	str.w	r0, [r2, #0xbd0]	@ word 0x2000114c
.L0800da48:
	pop	{r4, r5, r6, r7}
	bx	lr
.L0800da4c:
	.word	0x2000057c
.L0800da50:
	.word	0x3e99999a
.L0800da54:
	.word	0x3dcccccd
.L0800da58:
	.word	0x000186a0
.L0800da5c:
	.word	0x3e4ccccd
.L0800da60:
	.word	0x3f19999a
.L0800da64:
	.word	0x3dcccccd
.L0800da68:
	.word	0x00000000

@ ----------------------------------------------------------------------------
@ fn_0800da6c - redraws the setting screen: no parameters, no return value.
@ For i = 0..3 sets the text of the object word[0x200059e8 + i * 4] with
@ fn_08021c14 to the data at 0x0803a114 when the word 0x200011a8 equals i, else
@ to the data at 0x08038ea8.
@ Prints the word 0x20001144 into the object in 0x200059f8 as "%dHz" below 1000,
@ else value / 1000 as "%dKHz". Converts the float 0x20001138 with
@ float_to_double and prints it as "%0.1fV" into the object in 0x200059fc, the
@ same for the float 0x2000113c into the object in 0x20005a00. Finally prints the
@ string from the table 0x20000244[word 0x2000114c] into the object in
@ 0x20005a04 (tail call of fn_080228d0).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800da6c,"ax",%progbits
	.p2align 2
	.global fn_0800da6c
	.thumb_func
	.type fn_0800da6c, %function
fn_0800da6c:
	push	{r4, r5, r6, lr}
	ldr	r6, .L0800daf8		@ 0x200059e8
	ldr	r5, .L0800dafc		@ 0x2000057c
	movs	r4, #0
.L0800da74:
	ldr.w	r0, [r5, #0xc2c]	@ word 0x200011a8
	cmp	r0, r4
	ldr.w	r0, [r6, r4, lsl #2]
	bne.n	.L0800da84
	ldr	r1, .L0800db00
	b.n	.L0800da86
.L0800da84:
	ldr	r1, .L0800db04
.L0800da86:
	bl	fn_08021c14
	.inst.n	0x1c64		@ adds r4, r4, #1
	cmp	r4, #4
	blt.n	.L0800da74
	ldr	r4, .L0800daf8
	ldr.w	r2, [r5, #0xbc8]	@ word 0x20001144
	mov.w	r0, #0x3e8
	adds	r4, #0x10		@ 0x200059f8
	cmp	r2, r0
	bge.n	.L0800daa6
	adr	r1, .L0800db08		@ "%dHz"
	ldr	r0, [r4]
	b.n	.L0800daae
.L0800daa6:
	sdiv	r2, r2, r0
	adr	r1, .L0800db10		@ "%dKHz"
	ldr	r0, [r4]
.L0800daae:
	bl	fn_080228d0
	ldr	r6, .L0800dafc
	ldr.w	r0, [r6, #0xbbc]	@ float 0x20001138
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800db18		@ "%0.1fV"
	vmov	r2, r3, d0
	ldr	r0, [r4, #4]
	bl	fn_080228d0
	ldr.w	r0, [r6, #0xbc0]	@ float 0x2000113c
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800db18
	vmov	r2, r3, d0
	ldr	r0, [r4, #8]
	bl	fn_080228d0
	ldr	r1, .L0800db20		@ table 0x20000244
	ldr.w	r0, [r5, #0xbd0]	@ word 0x2000114c
	ldr.w	r1, [r1, r0, lsl #2]
	ldr	r0, [r4, #0xc]
	pop.w	{r4, r5, r6, lr}
	b.w	fn_080228d0
.L0800daf8:
	.word	0x200059e8
.L0800dafc:
	.word	0x2000057c
.L0800db00:
	.word	d_0803a114
.L0800db04:
	.word	d_08038ea8
.L0800db08:
	.asciz	"%dHz"
	.byte	0x00, 0x00, 0x00	@ padding
.L0800db10:
	.asciz	"%dKHz"
	.short	0x0000			@ padding
.L0800db18:
	.asciz	"%0.1fV"
	.byte	0x00			@ padding
.L0800db20:
	.word	0x20000244

@ ----------------------------------------------------------------------------
@ fn_0800db24 - formats a capacitance value: s0 = float value, r0 = text buffer,
@ r1 = unit text buffer, r2 = pointer to a unit index word.
@ If the value as an integer is above 0xbb03126f: prints "0L  " with
@ fn_08010370, stores unit byte 0 and index 0.
@ Otherwise takes the absolute value: below 0x3f4ccccd prints value * 1000 as
@ "%0.1f" with unit "pF" (string_copy), index 1. Below 0x41000000 "%0.4f", below
@ 0x42a00000 "%0.3f", below 0x44480000 "%0.2f", all with unit "nF" (index 2).
@ Then value / 1000: "%0.4f" below 0x45fa0000, "%0.3f" below 0x479c4000, "%0.2f"
@ below 0x49435000, "%0.1f" below 0x4af42400, with unit "uF" (index 3). Then
@ value / 1e6 (the constant 0x49742400 = 1e6 is loaded from the pool): "%0.2f"
@ below 0x4c989680 and "%0.1f" below 0x4ce4e1c0, with unit "mF" (index 4).
@ At or above 0x4ce4e1c0: "0L  ", unit byte 0, index 0.
@ The value is converted with float_to_double and printed with fn_08010370.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800db24,"ax",%progbits
	.p2align 2
	.global fn_0800db24
	.thumb_func
	.type fn_0800db24, %function
fn_0800db24:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r7, r0			@ text buffer
	mov	r6, r1			@ unit buffer
	vmov	r0, s0
	ldr	r1, .L0800dcdc		@ 0xbb03126f
	mov	r4, r2			@ index pointer
	mov.w	r8, #0
	cmp	r0, r1
	bls.n	.L0800db4c
.L0800db3c:
	adr	r1, .L0800dce0		@ "0L  "
	mov	r0, r7
	bl	fn_08010370
	mov	r0, r8
	strb.w	r8, [r6]
	b.n	.L0800db8e
.L0800db4c:
	vcmpe.f32	s0, #0.0
	vmrs	APSR_nzcv, fpscr
	bcs.n	.L0800db5a
	vneg.f32	s0, s0
.L0800db5a:
	vmov	r0, s0
	ldr	r1, .L0800dce8		@ 0x3f4ccccd
	vldr	s1, .L0800dcec		@ 1000.0 (0x447a0000)
	cmp	r0, r1
	bge.n	.L0800db94
	vmul.f32	s0, s0, s1
	vmov	r0, s0
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800dcf0		@ "%0.1f"
	vmov	r2, r3, d0
	mov	r0, r7
	bl	fn_08010370
	adr	r1, .L0800dcf8		@ "pF"
	mov	r0, r6
	bl	string_copy
	movs	r0, #1
.L0800db8e:
	str	r0, [r4]
.L0800db90:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0800db94:
	vmov	r0, s0
	movs	r5, #2
	cmp.w	r0, #0x41000000
	vmov	r0, s0
	bge.n	.L0800dbb4
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800dcfc		@ "%0.4f"
	vmov	r2, r3, d0
	b.n	.L0800dbcc
.L0800dbb4:
	ldr	r1, .L0800dd04		@ 0x42a00000
	cmp	r0, r1
	vmov	r0, s0
	bge.n	.L0800dbde
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800dd08		@ "%0.3f"
	vmov	r2, r3, d0
.L0800dbcc:
	mov	r0, r7
	bl	fn_08010370
	adr	r1, .L0800dd10		@ "nF"
.L0800dbd4:
	mov	r0, r6
	bl	string_copy
	str	r5, [r4]
	b.n	.L0800db90
.L0800dbde:
	ldr	r1, .L0800dd14		@ 0x44480000
	cmp	r0, r1
	vmov	r0, s0
	bge.n	.L0800dbf8
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800dd18		@ "%0.2f"
	vmov	r2, r3, d0
	b.n	.L0800dbcc
.L0800dbf8:
	ldr	r1, .L0800dd20		@ 0x45fa0000
	movs	r5, #3
	cmp	r0, r1
	bge.n	.L0800dc18
	vdiv.f32	s2, s0, s1
	vmov	r0, s2
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800dcfc		@ "%0.4f"
	vmov	r2, r3, d0
	b.n	.L0800dc7c
.L0800dc18:
	vmov	r0, s0
	ldr	r1, .L0800dd24		@ 0x479c4000
	cmp	r0, r1
	bge.n	.L0800dc3a
	vdiv.f32	s2, s0, s1
	vmov	r0, s2
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800dd08		@ "%0.3f"
	vmov	r2, r3, d0
	b.n	.L0800dc7c
.L0800dc3a:
	vmov	r0, s0
	ldr	r1, .L0800dd28		@ 0x49435000
	cmp	r0, r1
	bge.n	.L0800dc5c
	vdiv.f32	s2, s0, s1
	vmov	r0, s2
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800dd18		@ "%0.2f"
	vmov	r2, r3, d0
	b.n	.L0800dc7c
.L0800dc5c:
	vmov	r0, s0
	ldr	r1, .L0800dd2c		@ 0x4af42400
	cmp	r0, r1
	bge.n	.L0800dc86
	vdiv.f32	s2, s0, s1
	vmov	r0, s2
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800dcf0		@ "%0.1f"
	vmov	r2, r3, d0
.L0800dc7c:
	mov	r0, r7
	bl	fn_08010370
	adr	r1, .L0800dd30		@ "uF"
	b.n	.L0800dbd4
.L0800dc86:
	vmov	r0, s0
	ldr	r1, .L0800dd34		@ 0x4c989680
	vldr	s2, .L0800dd38		@ 0x49742400 (1e6)
	movs	r5, #4
	cmp	r0, r1
	bge.n	.L0800dcae
	vdiv.f32	s1, s0, s2
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800dd18		@ "%0.2f"
	vmov	r2, r3, d0
	b.n	.L0800dcd0
.L0800dcae:
	vmov	r0, s0
	ldr	r1, .L0800dd3c		@ 0x4ce4e1c0
	cmp	r0, r1
	bge.w	.L0800db3c
	vdiv.f32	s1, s0, s2
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800dcf0		@ "%0.1f"
	vmov	r2, r3, d0
.L0800dcd0:
	mov	r0, r7
	bl	fn_08010370
	adr	r1, .L0800dd40		@ "mF"
	b.n	.L0800dbd4
	.short	0x0000			@ padding
.L0800dcdc:
	.word	0xbb03126f
.L0800dce0:
	.asciz	"0L  "
	.byte	0x00, 0x00, 0x00	@ padding
.L0800dce8:
	.word	0x3f4ccccd
.L0800dcec:
	.word	0x447a0000
.L0800dcf0:
	.asciz	"%0.1f"
	.short	0x0000			@ padding
.L0800dcf8:
	.asciz	"pF"
	.byte	0x00			@ padding
.L0800dcfc:
	.asciz	"%0.4f"
	.short	0x0000			@ padding
.L0800dd04:
	.word	0x42a00000
.L0800dd08:
	.asciz	"%0.3f"
	.short	0x0000			@ padding
.L0800dd10:
	.asciz	"nF"
	.byte	0x00			@ padding
.L0800dd14:
	.word	0x44480000
.L0800dd18:
	.asciz	"%0.2f"
	.short	0x0000			@ padding
.L0800dd20:
	.word	0x45fa0000
.L0800dd24:
	.word	0x479c4000
.L0800dd28:
	.word	0x49435000
.L0800dd2c:
	.word	0x4af42400
.L0800dd30:
	.asciz	"uF"
	.byte	0x00			@ padding
.L0800dd34:
	.word	0x4c989680
.L0800dd38:
	.word	0x49742400
.L0800dd3c:
	.word	0x4ce4e1c0
.L0800dd40:
	.asciz	"mF"
	.byte	0x00			@ padding

@ ----------------------------------------------------------------------------
@ fn_0800dd44 - formats a plain value: s0 = float value, r0 = text buffer,
@ r1 = unit buffer, r2 = pointer to an index word.
@ Prints the value (float_to_double, then fn_08010370) with "%0.4f" below
@ 0x41200000, "%0.3f" below 0x42c80000, "%0.2f" below 0x447a0000, "%0.1f" below
@ 0x461c4000, "%0.0f" below 0x47c35000, otherwise prints "0L  ".
@ Stores 0 in the first byte of r1 and 0 in the word at r2.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800dd44,"ax",%progbits
	.p2align 2
	.global fn_0800dd44
	.thumb_func
	.type fn_0800dd44, %function
fn_0800dd44:
	push	{r4, r5, r6, lr}
	mov	r5, r1			@ unit buffer
	mov	r6, r0			@ text buffer
	vmov	r1, s0
	ldr	r0, .L0800dde8		@ 0x41200000
	mov	r4, r2			@ index pointer
	cmp	r1, r0
	vmov	r0, s0
	bge.n	.L0800dd6a
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800ddec		@ "%0.4f"
	vmov	r2, r3, d0
	b.n	.L0800ddd0
.L0800dd6a:
	ldr	r1, .L0800ddf4		@ 0x42c80000
	cmp	r0, r1
	vmov	r0, s0
	bge.n	.L0800dd84
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800ddf8		@ "%0.3f"
	vmov	r2, r3, d0
	b.n	.L0800ddd0
.L0800dd84:
	ldr	r1, .L0800de00		@ 0x447a0000
	cmp	r0, r1
	vmov	r0, s0
	bge.n	.L0800dd9e
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800de04		@ "%0.2f"
	vmov	r2, r3, d0
	b.n	.L0800ddd0
.L0800dd9e:
	ldr	r1, .L0800de0c		@ 0x461c4000
	cmp	r0, r1
	vmov	r0, s0
	bge.n	.L0800ddb8
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800de10		@ "%0.1f"
	vmov	r2, r3, d0
	b.n	.L0800ddd0
.L0800ddb8:
	ldr	r1, .L0800de18		@ 0x47c35000
	cmp	r0, r1
	bge.n	.L0800ddd8
	vmov	r0, s0
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800de1c		@ "%0.0f"
	vmov	r2, r3, d0
.L0800ddd0:
	mov	r0, r6
	bl	fn_08010370
	b.n	.L0800dde0
.L0800ddd8:
	adr	r1, .L0800de24		@ "0L  "
	mov	r0, r6
	bl	fn_08010370
.L0800dde0:
	movs	r0, #0
	strb	r0, [r5]
	str	r0, [r4]
	pop	{r4, r5, r6, pc}
.L0800dde8:
	.word	0x41200000
.L0800ddec:
	.asciz	"%0.4f"
	.short	0x0000			@ padding
.L0800ddf4:
	.word	0x42c80000
.L0800ddf8:
	.asciz	"%0.3f"
	.short	0x0000			@ padding
.L0800de00:
	.word	0x447a0000
.L0800de04:
	.asciz	"%0.2f"
	.short	0x0000			@ padding
.L0800de0c:
	.word	0x461c4000
.L0800de10:
	.asciz	"%0.1f"
	.short	0x0000			@ padding
.L0800de18:
	.word	0x47c35000
.L0800de1c:
	.asciz	"%0.0f"
	.short	0x0000			@ padding
.L0800de24:
	.asciz	"0L  "
	.byte	0x00, 0x00, 0x00	@ padding

@ ----------------------------------------------------------------------------
@ fn_0800de2c - formats an inductance value: s0 = float value, r0 = text
@ buffer, r1 = unit buffer, r2 = pointer to an index word.
@ Takes the absolute value. Below 0x42a00000 prints "%0.1f" with the unit "uH"
@ (index 3); below 0x44480000 "%0.2f" with "uH". Value / 1000 (from the pool,
@ 0x447a0000) with "%0.4f" below 0x45fa0000, "%0.3f" below 0x479c4000, "%0.2f"
@ below 0x49435000, with the unit "mH" (index 4). Value / 1e6 (0x49742400) with
@ "%0.4f" below 0x4af42400 and "%0.2f" below 0x4ce4e1c0, with the unit byte
@ 0x48 "H" and a zero byte (index 5). At or above 0x4ce4e1c0: "0L  ", unit byte
@ 0, index 0. Prints with fn_08010370 after float_to_double and copies the unit
@ with string_copy.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800de2c,"ax",%progbits
	.p2align 2
	.global fn_0800de2c
	.thumb_func
	.type fn_0800de2c, %function
fn_0800de2c:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r7, r0			@ text buffer
	vabs.f32	s0, s0
	vmov	r0, s0
	movs	r6, #3			@ index 3
	mov	r4, r2			@ index pointer
	mov	r5, r1			@ unit buffer
	cmp.w	r0, #0x41000000
	blt.n	.L0800de50
	vmov	r0, s0
	ldr	r1, .L0800df6c		@ 0x42a00000
	cmp	r0, r1
	bge.n	.L0800de64
.L0800de50:
	vmov	r0, s0
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800df70		@ "%0.1f"
	vmov	r2, r3, d0
	b.n	.L0800de80
.L0800de64:
	vmov	r0, s0
	ldr	r1, .L0800df78		@ 0x44480000
	cmp	r0, r1
	vmov	r0, s0
	bge.n	.L0800de94
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800df7c		@ "%0.2f"
	vmov	r2, r3, d0
.L0800de80:
	mov	r0, r7
	bl	fn_08010370
	adr	r1, .L0800df84		@ "uH"
.L0800de88:
	mov	r0, r5
	bl	string_copy
.L0800de8e:
	str	r6, [r4]
.L0800de90:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0800de94:
	ldr	r1, .L0800df88		@ 0x45fa0000
	vldr	s1, .L0800df8c		@ 1000.0 (0x447a0000)
	movs	r6, #4			@ index 4
	cmp	r0, r1
	bge.n	.L0800deb8
	vdiv.f32	s2, s0, s1
	vmov	r0, s2
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800df90		@ "%0.4f"
	vmov	r2, r3, d0
	b.n	.L0800defa
.L0800deb8:
	vmov	r0, s0
	ldr	r1, .L0800df98		@ 0x479c4000
	cmp	r0, r1
	bge.n	.L0800deda
	vdiv.f32	s2, s0, s1
	vmov	r0, s2
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800df9c		@ "%0.3f"
	vmov	r2, r3, d0
	b.n	.L0800defa
.L0800deda:
	vmov	r0, s0
	ldr	r1, .L0800dfa4		@ 0x49435000
	cmp	r0, r1
	bge.n	.L0800df04
	vdiv.f32	s2, s0, s1
	vmov	r0, s2
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800df7c		@ "%0.2f"
	vmov	r2, r3, d0
.L0800defa:
	mov	r0, r7
	bl	fn_08010370
	adr	r1, .L0800dfa8		@ "mH"
	b.n	.L0800de88
.L0800df04:
	vmov	r0, s0
	ldr	r1, .L0800dfac		@ 0x4af42400
	vldr	s2, .L0800dfb0		@ 0x49742400 (1e6)
	movs	r6, #5			@ index 5
	cmp	r0, r1
	bge.n	.L0800df2c
	vdiv.f32	s1, s0, s2
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800df90		@ "%0.4f"
	vmov	r2, r3, d0
	b.n	.L0800df4c
.L0800df2c:
	vmov	r0, s0
	ldr	r1, .L0800dfb4		@ 0x4ce4e1c0
	cmp	r0, r1
	bge.n	.L0800df5a
	vdiv.f32	s1, s0, s2
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800df7c		@ "%0.2f"
	vmov	r2, r3, d0
.L0800df4c:
	mov	r0, r7
	bl	fn_08010370
	adr	r0, .L0800dfb8		@ halfword 0x0048: byte 0x48 and a zero byte
	ldrh	r0, [r0]
	strh	r0, [r5]		@ unit buffer = "H"
	b.n	.L0800de8e
.L0800df5a:
	adr	r1, .L0800dfbc		@ "0L  "
	mov	r0, r7
	bl	fn_08010370
	movs	r0, #0
	strb	r0, [r5]
	str	r0, [r4]		@ index 0
	b.n	.L0800de90
	.short	0x0000			@ padding
.L0800df6c:
	.word	0x42a00000
.L0800df70:
	.asciz	"%0.1f"
	.short	0x0000			@ padding
.L0800df78:
	.word	0x44480000
.L0800df7c:
	.asciz	"%0.2f"
	.short	0x0000			@ padding
.L0800df84:
	.asciz	"uH"
	.byte	0x00			@ padding
.L0800df88:
	.word	0x45fa0000
.L0800df8c:
	.word	0x447a0000
.L0800df90:
	.asciz	"%0.4f"
	.short	0x0000			@ padding
.L0800df98:
	.word	0x479c4000
.L0800df9c:
	.asciz	"%0.3f"
	.short	0x0000			@ padding
.L0800dfa4:
	.word	0x49435000
.L0800dfa8:
	.asciz	"mH"
	.byte	0x00			@ padding
.L0800dfac:
	.word	0x4af42400
.L0800dfb0:
	.word	0x49742400
.L0800dfb4:
	.word	0x4ce4e1c0
.L0800dfb8:
	.short	0x0048
	.short	0x0000			@ padding
.L0800dfbc:
	.asciz	"0L  "
	.byte	0x00, 0x00, 0x00	@ padding

@ ----------------------------------------------------------------------------
@ fn_0800dfc4 - formats a value with a two-byte unit string: s0 = float value,
@ r0 = text buffer, r1 = unit buffer, r2 = pointer to a word.
@ When the absolute value as an integer is above 0x43b3ffff prints "0L  " with
@ fn_08010370 and stores 0 in the first unit byte; otherwise prints "%0.2f" of
@ float_to_double(value) and copies the string at .L0800e01c (bytes c2 b0) with
@ string_copy. Stores 1 at r2 when the value is within range, 0 otherwise.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800dfc4,"ax",%progbits
	.p2align 2
	.global fn_0800dfc4
	.thumb_func
	.type fn_0800dfc4, %function
fn_0800dfc4:
	push	{r4, r5, r6, lr}
	mov	r6, r0			@ text buffer
	vabs.f32	s1, s0
	mov	r5, r1			@ unit buffer
	vmov	r0, s1
	ldr	r1, .L0800e010		@ 0x43b40000
	mov	r4, r2
	cmp	r0, r1
	bge.n	.L0800dffe
	vmov	r0, s0
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e014		@ "%0.2f"
	vmov	r2, r3, d0
	mov	r0, r6
	bl	fn_08010370
	adr	r1, .L0800e01c		@ unit string (c2 b0)
	mov	r0, r5
	bl	string_copy
	movs	r0, #1
	b.n	.L0800e00a
.L0800dffe:
	adr	r1, .L0800e020		@ "0L  "
	mov	r0, r6
	bl	fn_08010370
	movs	r0, #0
	strb	r0, [r5]
.L0800e00a:
	str	r0, [r4]
	pop	{r4, r5, r6, pc}
	.short	0x0000			@ padding
.L0800e010:
	.word	0x43b40000
.L0800e014:
	.asciz	"%0.2f"
	.short	0x0000			@ padding
.L0800e01c:
	.byte	0xc2, 0xb0, 0x00
	.byte	0x00			@ padding
.L0800e020:
	.asciz	"0L  "
	.byte	0x00, 0x00, 0x00	@ padding

@ ----------------------------------------------------------------------------
@ fn_0800e028 - formats a value with a prefix and a unit string: s0 = float
@ value, r0 = text buffer, r1 = unit buffer, r2 = pointer to an index word.
@ Stores 1 to the word 0x20001198 and negates the value when it is negative and
@ the word 0x20001198 is not 2; otherwise stores 0 to the word 0x20001198.
@ Below 0x40ffff97 prints "%0.4f" (index 5), below 0x429fffbe "%0.3f", below
@ 0x4447ffae "%0.2f", with the unit string at .L0800e1dc (bytes ce a9).
@ Value / 1000 (0x447a0000) with "%0.4f" below 0x45f9ff9a (index 6), "%0.3f"
@ below 0x479c3fc0, "%0.2f" below 0x49434fb0, with the unit string "K" followed
@ by the bytes ce a9. Value / 1e6 (0x49742400, index 7) with "%0.3f" below
@ 0x4af42018, "%0.2f" below 0x4cbeb9af, "%0.1f" below 0x4ce4e1c0, with the unit
@ string "M" followed by the bytes ce a9. Above that "0L  ", unit byte 0,
@ index 0. Prints with fn_08010370 after float_to_double and copies the unit
@ with string_copy.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800e028,"ax",%progbits
	.p2align 2
	.global fn_0800e028
	.thumb_func
	.type fn_0800e028, %function
fn_0800e028:
	push.w	{r4, r5, r6, r7, r8, lr}
	vcmpe.f32	s0, #0.0
	movs	r5, #0
	mov	r4, r2			@ index pointer
	vmrs	APSR_nzcv, fpscr
	ldr	r2, .L0800e1c0		@ 0x2000057c
	mov	r6, r1			@ unit buffer
	mov	r8, r0			@ text buffer
	bcs.n	.L0800e054
	ldr.w	r0, [r2, #0xc1c]	@ word 0x20001198
	cmp	r0, #2
	beq.n	.L0800e054
	movs	r0, #1
	vneg.f32	s0, s0
	str.w	r0, [r2, #0xc1c]	@ word 0x20001198 = 1
	b.n	.L0800e058
.L0800e054:
	str.w	r5, [r2, #0xc1c]	@ word 0x20001198 = 0
.L0800e058:
	vabs.f32	s1, s0
	vmov	r0, s1
	ldr	r1, .L0800e1c4		@ 0x40ffff97
	movs	r7, #5			@ index 5
	cmp	r0, r1
	bge.n	.L0800e07c
	vmov	r0, s0
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e1c8		@ "%0.4f"
	vmov	r2, r3, d0
	b.n	.L0800e098
.L0800e07c:
	vmov	r0, s1
	ldr	r1, .L0800e1d0		@ 0x429fffbe
	cmp	r0, r1
	bge.n	.L0800e0ac
	vmov	r0, s0
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e1d4		@ "%0.3f"
	vmov	r2, r3, d0
.L0800e098:
	mov	r0, r8
	bl	fn_08010370
	adr	r1, .L0800e1dc		@ unit string (ce a9)
.L0800e0a0:
	mov	r0, r6
	bl	string_copy
	str	r7, [r4]
.L0800e0a8:
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0800e0ac:
	vmov	r0, s1
	ldr	r1, .L0800e1e0		@ 0x4447ffae
	cmp	r0, r1
	bge.n	.L0800e0ca
	vmov	r0, s0
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e1e4		@ "%0.2f"
	vmov	r2, r3, d0
	b.n	.L0800e098
.L0800e0ca:
	vmov	r0, s1
	ldr	r1, .L0800e1ec		@ 0x45f9ff9a
	vldr	s2, .L0800e1f0		@ 1000.0 (0x447a0000)
	movs	r7, #6			@ index 6
	cmp	r0, r1
	bge.n	.L0800e0f2
	vdiv.f32	s1, s0, s2
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e1c8		@ "%0.4f"
	vmov	r2, r3, d0
	b.n	.L0800e134
.L0800e0f2:
	vmov	r0, s1
	ldr	r1, .L0800e1f4		@ 0x479c3fc0
	cmp	r0, r1
	bge.n	.L0800e114
	vdiv.f32	s1, s0, s2
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e1d4		@ "%0.3f"
	vmov	r2, r3, d0
	b.n	.L0800e134
.L0800e114:
	vmov	r0, s1
	ldr	r1, .L0800e1f8		@ 0x49434fb0
	cmp	r0, r1
	bge.n	.L0800e13e
	vdiv.f32	s1, s0, s2
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e1e4		@ "%0.2f"
	vmov	r2, r3, d0
.L0800e134:
	mov	r0, r8
	bl	fn_08010370
	adr	r1, .L0800e1fc		@ "K" + ce a9
	b.n	.L0800e0a0
.L0800e13e:
	vmov	r0, s1
	ldr	r1, .L0800e200		@ 0x4af42018
	vldr	s2, .L0800e204		@ 1e6 (0x49742400)
	movs	r7, #7			@ index 7
	cmp	r0, r1
	bge.n	.L0800e166
	vdiv.f32	s1, s0, s2
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e1d4		@ "%0.3f"
	vmov	r2, r3, d0
	b.n	.L0800e1a8
.L0800e166:
	vmov	r0, s1
	ldr	r1, .L0800e208		@ 0x4cbeb9af
	cmp	r0, r1
	bge.n	.L0800e188
	vdiv.f32	s1, s0, s2
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e1e4		@ "%0.2f"
	vmov	r2, r3, d0
	b.n	.L0800e1a8
.L0800e188:
	vmov	r0, s1
	ldr	r1, .L0800e20c		@ 0x4ce4e1c0
	cmp	r0, r1
	bge.n	.L0800e1b2
	vdiv.f32	s1, s0, s2
	vmov	r0, s1
	bl	float_to_double
	vmov	d0, r0, r1
	adr	r1, .L0800e210		@ "%0.1f"
	vmov	r2, r3, d0
.L0800e1a8:
	mov	r0, r8
	bl	fn_08010370
	adr	r1, .L0800e218		@ "M" + ce a9
	b.n	.L0800e0a0
.L0800e1b2:
	adr	r1, .L0800e21c		@ "0L  "
	mov	r0, r8
	bl	fn_08010370
	strb	r5, [r6]
	str	r5, [r4]		@ index 0
	b.n	.L0800e0a8
.L0800e1c0:
	.word	0x2000057c
.L0800e1c4:
	.word	0x40ffff97
.L0800e1c8:
	.asciz	"%0.4f"
	.short	0x0000			@ padding
.L0800e1d0:
	.word	0x429fffbe
.L0800e1d4:
	.asciz	"%0.3f"
	.short	0x0000			@ padding
.L0800e1dc:
	.byte	0xce, 0xa9, 0x00
	.byte	0x00			@ padding
.L0800e1e0:
	.word	0x4447ffae
.L0800e1e4:
	.asciz	"%0.2f"
	.short	0x0000			@ padding
.L0800e1ec:
	.word	0x45f9ff9a
.L0800e1f0:
	.word	0x447a0000
.L0800e1f4:
	.word	0x479c3fc0
.L0800e1f8:
	.word	0x49434fb0
.L0800e1fc:
	.byte	0x4b, 0xce, 0xa9, 0x00
.L0800e200:
	.word	0x4af42018
.L0800e204:
	.word	0x49742400
.L0800e208:
	.word	0x4cbeb9af
.L0800e20c:
	.word	0x4ce4e1c0
.L0800e210:
	.asciz	"%0.1f"
	.short	0x0000			@ padding
.L0800e218:
	.byte	0x4d, 0xce, 0xa9, 0x00
.L0800e21c:
	.asciz	"0L  "
	.byte	0x00, 0x00, 0x00	@ padding
