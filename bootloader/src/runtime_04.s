@ runtime_04.s - formatted-output engine (fn_080033bc and its pad helpers), buffer-store callback, byte compare/copy/fill
@ Part of the FNIRSI LC1020E firmware rewrite: port of the stock bootloader (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080033bc - printf-style formatter.
@   r0 = format string (NUL terminated)
@   r1 = pointer to the argument list (va_list style: 32-bit slots, 64-bit
@        arguments are taken from an 8-byte aligned slot)
@   r2 = opaque value passed on unchanged to the output callback
@   r3 = output callback, called as callback(char in r0, r2-value in r1)
@ Returns in r0 the number of characters written (running total).
@
@ Register use: r4 = flag word, r5 = characters written so far, r6 = format
@ pointer, r7 = field width (later precision/length work value), r8 = argument
@ list pointer, r9 / r11 = work counters, r10 = callback. The caller's r2 is
@ kept at [sp, #0x5c] (the saved r2 slot of the entry push); [sp, #0xc] holds
@ the field width.
@
@ Flag word (r4): bit 0 ' ' flag, bit 1 width given, bit 2 precision given,
@ bit 3 '#' flag, bit 11 '+' flag, bit 13 '-' flag (left justify), bit 16 '0'
@ flag; bits 20..22 hold the length modifier (l, ll, h, hh, j, L, t, z).
@ The flag characters ' ' '#' '+' '-' '0' are recognised with the bit mask
@ 0x00012809 (one bit per character, indexed by character minus 0x20).
@
@ Behaviour: every character other than '%' is passed to the callback. After
@ '%' it reads the flags, width ('*' takes it from the argument list; a
@ negative value sets the left-justify flag), '.' precision ('*' allowed),
@ the length modifier, then the conversion character:
@   d i      signed decimal (64-bit when the length bits say so)
@   u o x X  unsigned decimal, octal, hexadecimal (lower or upper case digits)
@   p        hexadecimal with the '#' prefix handling and a minimum of 8 digits
@   c s      character, string (string stops at the precision)
@   n        stores the characters-written count through the argument pointer
@            (width of the store chosen by the length bits)
@   e E f F g G  floating point, using fn_08003238 to produce the digits
@   NUL      ends the format
@   others   the character itself is sent to the callback
@ Number digits are built backwards in a 32-byte stack buffer; 64-bit values
@ are divided with fn_08000208, the exponent digits with udiv32. Padding is
@ written by fn_08003a94 (spaces or '0') and fn_08003a70 (trailing spaces).
@ ----------------------------------------------------------------------------
	.section .text.fn_080033bc,"ax",%progbits
	.p2align 2
	.global fn_080033bc
	.thumb_func
	.type fn_080033bc, %function
fn_080033bc:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, sp, #0x54
	mov	r10, r3				@ r10 = output callback
	mov	r8, r1				@ r8 = argument list pointer
	mov	r6, r0				@ r6 = format pointer
	movs	r5, #0x0			@ r5 = characters written
	b.n	.L080037aa			@ go to the loop test
.L080033cc:
	cmp	r0, #0x25			@ '%' ?
	bne.n	.L080034c0			@ no: send the character as it is
	movs	r4, #0x0			@ flags = 0
	mov	r7, r4				@ precision = 0
	ldr	r2, .L080037bc			@ r2 = 0x00012809 flag-character mask
	movs	r1, #0x1
	str	r4, [sp, #0xc]			@ field width = 0
	b.n	.L080033de
.L080033dc:
	orrs	r4, r0				@ add the flag bit
.L080033de:
	ldrb.w	r3, [r6, #0x1]!			@ next format character
	subs	r3, #0x20
	lsl.w	r0, r1, r3			@ 1 << (char - 0x20)
	tst	r0, r2
	bne.n	.L080033dc			@ it is a flag character
	ldrb	r0, [r6, #0x0]
	cmp	r0, #0x2a			@ '*' : width from the argument list
	beq.n	.L08003416
	mvn	r3, #0x2f			@ r3 = -0x30
.L080033f6:
	ldrb	r0, [r6, #0x0]
	sub.w	r2, r0, #0x30
	cmp	r2, #0x9
	bhi.n	.L0800342e			@ not a digit: width done
	ldr	r2, [sp, #0xc]
	orr	r4, r4, #0x2			@ width given
	add.w	r2, r2, r2, lsl #0x2
	add.w	r2, r3, r2, lsl #0x1		@ width * 10 - 0x30
	add	r0, r2				@ + digit
	.inst.n	0x1c76				@ adds r6, r6, #1
	str	r0, [sp, #0xc]
	b.n	.L080033f6
.L08003416:
	ldr.w	r2, [r8], #0x4			@ width = next argument
	str	r2, [sp, #0xc]
	cmp	r2, #0x0
	bge.n	.L08003428
	rsbs	r0, r2, #0x0			@ negative width: use its magnitude
	orr	r4, r4, #0x2000			@ and left-justify
	str	r0, [sp, #0xc]
.L08003428:
	orr	r4, r4, #0x2			@ width given
	.inst.n	0x1c76				@ adds r6, r6, #1
.L0800342e:
	ldrb	r0, [r6, #0x0]
	cmp	r0, #0x2e			@ '.' : precision follows
	bne.n	.L08003462
	ldrb.w	r0, [r6, #0x1]!
	orr	r4, r4, #0x4			@ precision given
	cmp	r0, #0x2a			@ '*' : precision from the argument list
	beq.n	.L0800345c
	mvn	r2, #0x2f			@ r2 = -0x30
.L08003444:
	ldrb	r0, [r6, #0x0]
	sub.w	r3, r0, #0x30
	cmp	r3, #0x9
	bhi.n	.L08003462			@ not a digit: precision done
	add.w	r3, r7, r7, lsl #0x2
	add.w	r3, r2, r3, lsl #0x1		@ precision * 10 - 0x30
	adds	r7, r0, r3			@ + digit
	.inst.n	0x1c76				@ adds r6, r6, #1
	b.n	.L08003444
.L0800345c:
	ldr.w	r7, [r8], #0x4			@ precision = next argument
	.inst.n	0x1c76				@ adds r6, r6, #1
.L08003462:
	ldrb	r0, [r6, #0x0]			@ length modifier
	cmp	r0, #0x6c			@ 'l'
	beq.n	.L08003488
	bgt.n	.L08003478
	cmp	r0, #0x4c			@ 'L'
	beq.n	.L0800349e
	cmp	r0, #0x68			@ 'h'
	beq.n	.L0800348e
	cmp	r0, #0x6a			@ 'j'
	bne.n	.L080034a0
	b.n	.L08003482
.L08003478:
	cmp	r0, #0x74			@ 't'
	beq.n	.L0800349e
	cmp	r0, #0x7a			@ 'z'
	bne.n	.L080034a0
	b.n	.L0800349e
.L08003482:
	orr	r4, r4, #0x200000		@ length bits = 2 ('j')
	b.n	.L0800349e
.L08003488:
	orr	r4, r4, #0x100000		@ length bits = 1 ('l')
	b.n	.L08003492
.L0800348e:
	orr	r4, r4, #0x300000		@ length bits = 3 ('h')
.L08003492:
	ldrb	r2, [r6, #0x1]			@ doubled modifier ("ll", "hh")?
	cmp	r2, r0
	bne.n	.L0800349e
	add.w	r4, r4, #0x100000		@ add one to the length bits
	.inst.n	0x1c76				@ adds r6, r6, #1
.L0800349e:
	.inst.n	0x1c76				@ adds r6, r6, #1
.L080034a0:
	ldrb	r0, [r6, #0x0]			@ conversion character
	cmp	r0, #0x66			@ 'f'
.L080034a4:
	beq.n	.L080034be
	bgt.n	.L080034d0
	cmp	r0, #0x58			@ 'X'
	beq.n	.L0800359c
	bgt.n	.L080034c2
	cmp	r0, #0x0			@ end of string
	beq.n	.L0800359e
	cmp	r0, #0x45			@ 'E'
	beq.n	.L080034a4
	cmp	r0, #0x46			@ 'F'
	beq.n	.L080034a4
	cmp	r0, #0x47			@ 'G'
	bne.n	.L080034f4
.L080034be:
	b.n	.L080037e8			@ floating point conversions
.L080034c0:
	b.n	.L080034f4
.L080034c2:
	cmp	r0, #0x63			@ 'c'
	beq.n	.L08003532
	cmp	r0, #0x64			@ 'd'
	beq.n	.L080035be
	cmp	r0, #0x65			@ 'e'
	bne.n	.L080034f4
	b.n	.L080037e8
.L080034d0:
	cmp	r0, #0x70			@ 'p'
	beq.n	.L080035bc
	bgt.n	.L080034e8
	cmp	r0, #0x67			@ 'g'
	beq.n	.L080034be
	cmp	r0, #0x69			@ 'i'
	beq.n	.L080035be
	cmp	r0, #0x6e			@ 'n'
	beq.n	.L080034fe
	cmp	r0, #0x6f			@ 'o'
	bne.n	.L080034f4
	b.n	.L08003642
.L080034e8:
	cmp	r0, #0x73			@ 's'
	beq.n	.L08003546
	cmp	r0, #0x75			@ 'u'
	beq.n	.L080035da
	cmp	r0, #0x78			@ 'x'
	beq.n	.L0800359c
.L080034f4:
	mov	r2, r10				@ send the character through the callback
	ldr	r1, [sp, #0x5c]
	blx	r2
	.inst.n	0x1c6d				@ adds r5, r5, #1
	b.n	.L080037a8
.L080034fe:
	ubfx	r0, r4, #0x14, #0x3		@ 'n': length bits select the store width
	cmp	r0, #0x2
	beq.n	.L0800351a
	cmp	r0, #0x3
	beq.n	.L08003526
	ldr.w	r1, [r8, #0x0]
	cmp	r0, #0x4
	beq.n	.L0800352e
	str	r5, [r1, #0x0]			@ 32-bit store of the count
.L08003514:
	add.w	r8, r8, #0x4
	b.n	.L080037a8
.L0800351a:
	ldr.w	r1, [r8, #0x0]
	asrs	r2, r5, #0x1f
	strd	r5, r2, [r1, #0x0]		@ 64-bit store of the count
	b.n	.L08003514
.L08003526:
	ldr.w	r1, [r8, #0x0]
	strh	r5, [r1, #0x0]			@ 16-bit store of the count
	b.n	.L08003514
.L0800352e:
	strb	r5, [r1, #0x0]			@ 8-bit store of the count
	b.n	.L08003514
.L08003532:
	ldrb.w	r1, [r8], #0x4			@ 'c': the character from the argument list
	strb.w	r1, [sp, #0x0]			@ one-character string at [sp]
	movs	r0, #0x0
	strb.w	r0, [sp, #0x1]
	mov	r11, sp				@ r11 = string pointer
	movs	r0, #0x1			@ r0 = length limit 1
	b.n	.L0800354e
.L08003546:
	ldr.w	r11, [r8], #0x4			@ 's': string pointer from the argument list
	mov.w	r0, #0xffffffff			@ no length limit
.L0800354e:
	lsls	r1, r4, #0x1d			@ precision given?
	mov.w	r1, #0x0			@ r1 = length counter
	bmi.n	.L0800355c
	b.n	.L08003574
.L08003558:
	add.w	r1, r9, #0x1
.L0800355c:
	mov	r9, r1				@ count up to the precision, the limit or the NUL
	cmp	r1, r7
	bge.n	.L08003582
	cmp	r9, r0
	blt.n	.L08003558
	ldrb.w	r1, [r11, r9]
	cmp	r1, #0x0
	bne.n	.L08003558
	b.n	.L08003582
.L08003570:
	add.w	r1, r9, #0x1
.L08003574:
	mov	r9, r1				@ count up to the limit or the NUL
	cmp	r1, r0
	blt.n	.L08003570
	ldrb.w	r1, [r11, r9]
	cmp	r1, #0x0
	bne.n	.L08003570
.L08003582:
	ldr	r0, [sp, #0xc]
	mov	r3, r10
	sub.w	r7, r0, r9			@ padding = width - length
	mov	r1, r4
	mov	r0, r7
	ldr	r2, [sp, #0x5c]
	bl	fn_08003a94			@ leading pad (when not left-justified)
	add	r0, r5
	add.w	r5, r0, r9			@ count the pad and the string
	b.n	.L080035ac
.L0800359c:
	b.n	.L08003628
.L0800359e:
	b.n	.L080037b2
	b.n	.L080035be			@ not reached from inside this function
.L080035a2:
	ldrb.w	r0, [r11], #0x1			@ send the string bytes
	mov	r2, r10
	ldr	r1, [sp, #0x5c]
	blx	r2
.L080035ac:
	subs.w	r9, r9, #0x1
	bcs.n	.L080035a2
	mov	r3, r10				@ trailing pad (when left-justified)
	mov	r1, r4
	mov	r0, r7
	ldr	r2, [sp, #0x5c]
	b.n	.L080037a2
.L080035bc:
	b.n	.L08003632
.L080035be:
	movs	r1, #0xa			@ 'd' / 'i': base 10
	ubfx	r2, r4, #0x14, #0x3		@ length bits
	mov.w	r11, #0x0
	str	r1, [sp, #0x0]			@ base (low word)
	cmp	r2, #0x2
	beq.n	.L080035dc
	ldr.w	r0, [r8], #0x4			@ 32-bit argument
	asrs	r1, r0, #0x1f
	cmp	r2, #0x3
	beq.n	.L080035ec
	b.n	.L080035f0
.L080035da:
	b.n	.L08003624
.L080035dc:
	add.w	r0, r8, #0x7			@ 64-bit argument from an 8-byte aligned slot
	bic	r2, r0, #0x7
	ldrd	r0, r1, [r2], #0x8
	mov	r8, r2
	b.n	.L080035f8
.L080035ec:
	sxth	r0, r0				@ 'h': sign-extend 16 bits
	asrs	r1, r0, #0x1f
.L080035f0:
	cmp	r2, #0x4
	bne.n	.L080035f8
	sxtb	r0, r0				@ 'hh': sign-extend 8 bits
	asrs	r1, r0, #0x1f
.L080035f8:
	cmp	r1, #0x0
	bge.n	.L0800360a
	mov	r2, r1				@ negative: negate the 64-bit value
	movs	r1, #0x0
	rsbs	r0, r0, #0x0
	sbc.w	r1, r1, r2
	movs	r2, #0x2d			@ sign character '-'
	b.n	.L08003610
.L0800360a:
	lsls	r2, r4, #0x14			@ '+' flag?
	bpl.n	.L08003618
	movs	r2, #0x2b			@ sign character '+'
.L08003610:
	strb.w	r2, [sp, #0x4]			@ prefix buffer at [sp, #4]
	movs	r2, #0x1			@ prefix length 1
	b.n	.L08003620
.L08003618:
	lsls	r2, r4, #0x1f			@ ' ' flag?
	beq.n	.L08003620
	movs	r2, #0x20			@ sign character ' '
	b.n	.L08003610
.L08003620:
	mov	r9, r2				@ r9 = prefix length
	b.n	.L080036d4
.L08003624:
	movs	r1, #0xa			@ 'u': base 10
	b.n	.L0800362a
.L08003628:
	movs	r1, #0x10			@ 'x' / 'X': base 16
.L0800362a:
	mov.w	r11, #0x0
	str	r1, [sp, #0x0]
	b.n	.L0800364a
.L08003632:
	movs	r1, #0x10			@ 'p': base 16, precision flag set, minimum 8
	mov.w	r11, #0x0
	orr	r4, r4, #0x4
	movs	r7, #0x8
	str	r1, [sp, #0x0]
	b.n	.L0800364a
.L08003642:
	movs	r0, #0x8			@ 'o': base 8
	mov.w	r11, #0x0
	str	r0, [sp, #0x0]
.L0800364a:
	ubfx	r2, r4, #0x14, #0x3		@ length bits
	cmp	r2, #0x2
	beq.n	.L0800365e
	ldr.w	r0, [r8], #0x4			@ 32-bit unsigned argument
	movs	r1, #0x0
	cmp	r2, #0x3
	beq.n	.L0800366e
	b.n	.L08003670
.L0800365e:
	add.w	r0, r8, #0x7			@ 64-bit argument from an 8-byte aligned slot
	bic	r2, r0, #0x7
	ldrd	r0, r1, [r2], #0x8
	mov	r8, r2
	b.n	.L08003676
.L0800366e:
	uxth	r0, r0				@ 'h': zero-extend 16 bits
.L08003670:
	cmp	r2, #0x4
	bne.n	.L08003676
	uxtb	r0, r0				@ 'hh': zero-extend 8 bits
.L08003676:
	mov.w	r9, #0x0			@ prefix length 0
	lsls	r2, r4, #0x1c			@ '#' flag?
	bpl.n	.L080036d4
	ldrb	r2, [r6, #0x0]
	cmp	r2, #0x70			@ 'p'
	beq.n	.L08003694
	ldr.w	r12, [sp, #0x0]
	eor	r12, r12, #0x10
	orrs.w	r12, r12, r11
	beq.n	.L0800369e			@ base 16
	b.n	.L080036b2
.L08003694:
	movs	r2, #0x40			@ prefix "@" for 'p'
	strb.w	r2, [sp, #0x4]
	movs	r2, #0x1
	b.n	.L080036b0
.L0800369e:
	orrs.w	r3, r0, r1
	beq.n	.L080036b2			@ value zero: no prefix
	movs	r3, #0x30			@ prefix "0x" or "0X"
	strb.w	r3, [sp, #0x4]
	strb.w	r2, [sp, #0x5]
	movs	r2, #0x2
.L080036b0:
	mov	r9, r2
.L080036b2:
	ldr	r3, [sp, #0x0]
	eor	r3, r3, #0x8
	orrs.w	r3, r3, r11
	bne.n	.L080036d4			@ not base 8
	orrs.w	r2, r0, r1
	bne.n	.L080036c8
	lsls	r2, r4, #0x1d
	bpl.n	.L080036d4
.L080036c8:
	movs	r2, #0x30			@ octal prefix "0"
	strb.w	r2, [sp, #0x4]
	mov.w	r9, #0x1
	.inst.n	0x1e7f				@ subs r7, r7, #1
.L080036d4:
	ldrb	r2, [r6, #0x0]
	cmp	r2, #0x58			@ 'X' selects upper-case digits
	beq.n	.L080036e4
	adr	r2, .L080037c0			@ "0123456789abcdef"
.L080036dc:
	str	r2, [sp, #0x30]			@ digit table pointer
	add	r2, sp, #0x30
	str	r2, [sp, #0x8]			@ digit write pointer (digits are built backwards)
	b.n	.L080036fc
.L080036e4:
	adr	r2, .L080037d4			@ "0123456789ABCDEF"
	b.n	.L080036dc
.L080036e8:
	mov	r3, r11
	ldr	r2, [sp, #0x0]
	bl	fn_08000208			@ 64-bit divide by the base; remainder in r2
	ldr	r3, [sp, #0x30]
	ldrb	r3, [r3, r2]
	ldr	r2, [sp, #0x8]
	.inst.n	0x1e52				@ subs r2, r2, #1
	str	r2, [sp, #0x8]
	strb	r3, [r2, #0x0]			@ store the digit
.L080036fc:
	orrs.w	r2, r0, r1
	bne.n	.L080036e8			@ more digits while the value is non-zero
	ldr	r0, [sp, #0x8]
	add	r1, sp, #0x10
	subs	r0, r1, r0
	add.w	r11, r0, #0x20			@ r11 = number of digits
	lsls	r0, r4, #0x1d			@ precision given?
	bpl.n	.L08003716
	bic	r4, r4, #0x10000		@ yes: the '0' flag is ignored
	b.n	.L08003718
.L08003716:
	movs	r7, #0x1			@ no: minimum one digit
.L08003718:
	cmp	r7, r11
	ble.n	.L08003722
	sub.w	r0, r7, r11			@ zeros to add = precision - digits
	b.n	.L08003724
.L08003722:
	movs	r0, #0x0
.L08003724:
	add.w	r1, r0, r11
	str	r0, [sp, #0x0]			@ zero count
	ldr	r0, [sp, #0xc]
	add	r1, r9				@ + prefix length
	subs	r0, r0, r1
	str	r0, [sp, #0xc]			@ remaining pad width
	lsls	r0, r4, #0xf			@ '0' flag?
	bmi.n	.L08003744
	mov	r3, r10
	mov	r1, r4
	ldr	r2, [sp, #0x5c]
	ldr	r0, [sp, #0xc]
	bl	fn_08003a94			@ leading pad
	add	r5, r0
.L08003744:
	movs	r7, #0x0
	b.n	.L08003756
.L08003748:
	add	r0, sp, #0x4
	mov	r2, r10
	ldrb	r0, [r0, r7]
	ldr	r1, [sp, #0x5c]
	blx	r2				@ send the sign or prefix characters
	.inst.n	0x1c6d				@ adds r5, r5, #1
	.inst.n	0x1c7f				@ adds r7, r7, #1
.L08003756:
	cmp	r7, r9
	blt.n	.L08003748
	lsls	r0, r4, #0xf
	bpl.n	.L08003778
	mov	r3, r10
	mov	r1, r4
	ldr	r2, [sp, #0x5c]
	ldr	r0, [sp, #0xc]
	bl	fn_08003a94			@ zero fill after the prefix
	add	r5, r0
	b.n	.L08003778
.L0800376e:
	movs	r0, #0x30			@ send the leading zeros
	mov	r2, r10
	ldr	r1, [sp, #0x5c]
	blx	r2
	.inst.n	0x1c6d				@ adds r5, r5, #1
.L08003778:
	ldr	r1, [sp, #0x0]
	subs	r0, r1, #0x1
	str	r0, [sp, #0x0]
	cmp	r1, #0x0
	bgt.n	.L0800376e
	b.n	.L08003796
.L08003784:
	ldr	r0, [sp, #0x8]
	ldr	r1, [sp, #0x8]
	mov	r2, r10
	ldrb	r0, [r0, #0x0]
	.inst.n	0x1c49				@ adds r1, r1, #1
	str	r1, [sp, #0x8]
	ldr	r1, [sp, #0x5c]
	blx	r2				@ send one digit
	.inst.n	0x1c6d				@ adds r5, r5, #1
.L08003796:
	subs.w	r1, r11, #0x0
	sub.w	r11, r11, #0x1
	bgt.n	.L08003784
	b.n	.L08003a5a
.L080037a2:
	bl	fn_08003a70			@ trailing pad
	add	r5, r0
.L080037a8:
	.inst.n	0x1c76				@ adds r6, r6, #1
.L080037aa:
	ldrb	r0, [r6, #0x0]
	cmp	r0, #0x0
	bne.w	.L080033cc			@ next format character
.L080037b2:
	add	sp, #0x64
	mov	r0, r5				@ return the count
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short	0x0000				@ padding
.L080037bc:
	.word	0x00012809			@ flag-character bit mask
.L080037c0:
	.ascii	"0123456789abcdef"		@ lower-case digit table
.L080037d0:
	.byte	0x00				@ terminator, also used as an empty string
	.byte	0x00, 0x00, 0x00		@ padding
.L080037d4:
	.ascii	"0123456789ABCDEF"		@ upper-case digit table
	.byte	0x00				@ terminator
	.byte	0x00, 0x00, 0x00		@ padding
@ floating point conversions (e E f F g G): [sp, #0x4c] gets the sign string
@ pointer, [sp, #0x30] the digit string from fn_08003238
.L080037e8:
	lsls	r0, r4, #0x1d			@ precision given?
	bmi.n	.L080037ee
	movs	r7, #0x6			@ default precision 6
.L080037ee:
	add.w	r0, r8, #0x7			@ 64-bit double from an 8-byte aligned slot
	bic	r0, r0, #0x7
	ldrd	r2, r3, [r0], #0x8
	mov	r8, r0
	and	r12, r3, #0x80000000		@ sign bit
	movs.w	r0, r12
	beq.n	.L0800380a
	adr	r0, .L08003a64			@ "-"
	b.n	.L0800381e
.L0800380a:
	lsls	r0, r4, #0x14			@ '+' flag?
	bpl.n	.L08003812
	adr	r0, .L08003a68			@ "+"
	b.n	.L0800381e
.L08003812:
	lsls	r0, r4, #0x1f			@ ' ' flag?
	beq.n	.L0800381a
	adr	r0, .L08003a6c			@ " "
	b.n	.L0800381e
.L0800381a:
	adr.w	r0, .L080037d0			@ "" (empty string)
.L0800381e:
	str	r0, [sp, #0x4c]			@ sign string pointer
	ldrb	r0, [r6, #0x0]
	bic	r3, r3, #0x80000000		@ drop the sign from the double
	cmp	r0, #0x65			@ 'e'
	beq.n	.L08003844
	bgt.n	.L0800383a
	cmp	r0, #0x45			@ 'E'
	beq.n	.L08003844
	cmp	r0, #0x46			@ 'F'
	beq.n	.L08003870
	cmp	r0, #0x47			@ 'G'
	bne.n	.L08003938
	b.n	.L080038b2
.L0800383a:
	cmp	r0, #0x66			@ 'f'
	beq.n	.L08003870
	cmp	r0, #0x67			@ 'g'
	bne.n	.L08003938
	b.n	.L080038b2
.L08003844:
	movs	r1, #0x0			@ 'e' / 'E' : exponent form
	cmp	r7, #0x11
	blt.n	.L0800384e
	movs	r0, #0x11			@ at most 17 digits
	b.n	.L08003850
.L0800384e:
	adds	r0, r7, #0x1
.L08003850:
	strd	r0, r1, [sp, #0x0]
	add	r1, sp, #0x10
	add	r0, sp, #0x30
	bl	fn_08003238			@ convert the double to digits
	ldrd	r0, r1, [sp, #0x34]
	ldr	r2, [sp, #0x30]
	mov.w	r11, #0x0
	add.w	r9, r7, #0x1
	str	r2, [sp, #0x40]
	str	r1, [sp, #0x0]
	b.n	.L0800390e
.L08003870:
	mov.w	r0, #0x80000000			@ 'f' / 'F' : fixed form
	str	r7, [sp, #0x0]
	strd	r1, r0, [sp, #0x4]
	add	r1, sp, #0x10
	add	r0, sp, #0x30
	bl	fn_08003238
	ldrd	r0, r2, [sp, #0x34]
	ldr	r3, [sp, #0x30]
	ldr	r1, [sp, #0x3c]
	mov.w	r11, #0x0
	mov	r9, r2
	str	r3, [sp, #0x40]
	str	r2, [sp, #0x0]
	cbnz	r1, .L0800389c
	adds	r1, r7, #0x1
	add.w	r9, r0, r1
.L0800389c:
	subs.w	r0, r7, r9
	bmi.n	.L080038aa
	rsb.w	r11, r0, #0xffffffff
	add.w	r9, r7, #0x1
.L080038aa:
	sub.w	r0, r9, r7
	str	r0, [sp, #0x4]
	b.n	.L08003938
.L080038b2:
	cmp	r7, #0x1			@ 'g' / 'G' : shortest form
	bge.n	.L080038b8
	movs	r7, #0x1			@ precision at least 1
.L080038b8:
	movs	r1, #0x0
	cmp	r7, #0x11
	ble.n	.L080038c2
	movs	r0, #0x11			@ at most 17 digits
	b.n	.L080038c4
.L080038c2:
	mov	r0, r7
.L080038c4:
	strd	r0, r1, [sp, #0x0]
	add	r1, sp, #0x10
	add	r0, sp, #0x30
	bl	fn_08003238
	ldrd	r0, r1, [sp, #0x34]
	ldr	r2, [sp, #0x30]
	str	r1, [sp, #0x0]
	mov.w	r11, #0x0
	mov	r9, r7
	str	r2, [sp, #0x40]
	lsls	r1, r4, #0x1c			@ '#' flag keeps trailing zeros
	bmi.n	.L08003904
	ldr	r2, [sp, #0x0]
	cmp	r2, r9
	bge.n	.L080038f2
	mov	r9, r2
	b.n	.L080038f2
.L080038ee:
	sub.w	r9, r9, #0x1			@ strip a trailing zero digit
.L080038f2:
	cmp.w	r9, #0x1
	ble.n	.L08003904
	ldr	r2, [sp, #0x40]
	sub.w	r1, r9, #0x1
	ldrb	r1, [r2, r1]
	cmp	r1, #0x30
	beq.n	.L080038ee
.L08003904:
	cmp	r0, r7
	bge.n	.L0800390e
	cmn.w	r0, #0x4
	bge.n	.L08003916
.L0800390e:
	movs	r1, #0x1
	strd	r1, r0, [sp, #0x4]
	b.n	.L08003938
.L08003916:
	cmp	r0, #0x0
	bgt.n	.L08003922
	add	r11, r0
	sub.w	r1, r9, r0
	b.n	.L08003928
.L08003922:
	adds	r1, r0, #0x1
	cmp	r1, r9
	ble.n	.L0800392a
.L08003928:
	mov	r9, r1
.L0800392a:
	sub.w	r0, r0, r11
	.inst.n	0x1c40				@ adds r0, r0, #1
	str	r0, [sp, #0x4]
	mov.w	r0, #0x80000000
	str	r0, [sp, #0x8]
.L08003938:
	lsls	r0, r4, #0x1c
	bmi.n	.L08003948
	ldr	r0, [sp, #0x4]
	cmp	r0, r9
	blt.n	.L08003948
	mov.w	r0, #0xffffffff
	str	r0, [sp, #0x4]
.L08003948:
	movs	r0, #0x0
	strb.w	r0, [sp, #0x4b]			@ NUL at the end of the exponent text
	ldr	r0, [sp, #0x8]
	add.w	r7, sp, #0x4b
	cmp.w	r0, #0x80000000
	beq.n	.L080039a6			@ no exponent for this form
	movs	r0, #0x2
	str	r0, [sp, #0x30]			@ at least two exponent digits
	movs	r0, #0x2b
	str	r0, [sp, #0x34]			@ exponent sign '+'
	ldr	r0, [sp, #0x8]
	cmp	r0, #0x0
	bge.n	.L08003982
	rsbs	r0, r0, #0x0
	str	r0, [sp, #0x8]
	movs	r0, #0x2d
	str	r0, [sp, #0x34]			@ exponent sign '-'
	b.n	.L08003982
.L08003972:
	movs	r1, #0xa
	ldr	r0, [sp, #0x8]
	bl	udiv32				@ exponent / 10; remainder in r1
	adds	r1, #0x30
	str	r0, [sp, #0x8]
	strb.w	r1, [r7, #-0x1]!		@ store the exponent digit
.L08003982:
	ldr	r1, [sp, #0x30]
	subs	r0, r1, #0x1
	str	r0, [sp, #0x30]
	cmp	r1, #0x0
	bgt.n	.L08003972
	ldr	r0, [sp, #0x8]
	cmp	r0, #0x0
	bne.n	.L08003972
	subs	r1, r7, #0x1
	ldr	r0, [sp, #0x34]
	strb	r0, [r1, #0x0]			@ exponent sign
	ldrb	r0, [r6, #0x0]
	and	r0, r0, #0x20
	orr	r0, r0, #0x45
	strb.w	r0, [r7, #-0x2]!		@ 'e' or 'E' according to the conversion
.L080039a6:
	add	r0, sp, #0x44
	subs	r0, r0, r7
	.inst.n	0x1dc0				@ adds r0, r0, #7
	str	r0, [sp, #0x8]			@ exponent text length
	ldr	r0, [sp, #0x4c]
	ldrb	r0, [r0, #0x0]
	cbz	r0, .L080039b6
	movs	r0, #0x1			@ sign present: one character
.L080039b6:
	add.w	r1, r0, r9
	ldr	r0, [sp, #0x4]
	add.w	r1, r1, r0, asr #0x1f
	ldr	r0, [sp, #0x8]
	add	r1, r0
	ldr	r0, [sp, #0xc]
	subs	r0, r0, r1
	.inst.n	0x1e40				@ subs r0, r0, #1
	str	r0, [sp, #0xc]			@ remaining pad width
	lsls	r0, r4, #0xf
	bmi.n	.L080039de
	mov	r3, r10
	mov	r1, r4
	ldr	r2, [sp, #0x5c]
	ldr	r0, [sp, #0xc]
	bl	fn_08003a94			@ leading pad
	add	r5, r0
.L080039de:
	ldr	r0, [sp, #0x4c]
	ldrb	r0, [r0, #0x0]
	cbz	r0, .L080039ec
	mov	r2, r10
	ldr	r1, [sp, #0x5c]
	blx	r2				@ send the sign
	.inst.n	0x1c6d				@ adds r5, r5, #1
.L080039ec:
	lsls	r0, r4, #0xf
	bpl.n	.L08003a38
	mov	r3, r10
	mov	r1, r4
	ldr	r2, [sp, #0x5c]
	ldr	r0, [sp, #0xc]
	bl	fn_08003a94			@ zero fill after the sign
	add	r5, r0
	b.n	.L08003a38
.L08003a00:
	cmp.w	r11, #0x0			@ send the digits, '0' outside the digit string
	blt.n	.L08003a16
	ldr	r0, [sp, #0x0]
	cmp	r0, r11
	ble.n	.L08003a16
	ldr	r0, [sp, #0x40]
	ldr	r1, [sp, #0x5c]
	ldrb.w	r0, [r0, r11]
	b.n	.L08003a1a
.L08003a16:
	ldr	r1, [sp, #0x5c]
	movs	r0, #0x30
.L08003a1a:
	mov	r2, r10
	blx	r2
	ldr	r0, [sp, #0x4]
	add.w	r11, r11, #0x1
	.inst.n	0x1e40				@ subs r0, r0, #1
	add.w	r5, r5, #0x1
	str	r0, [sp, #0x4]
	bne.n	.L08003a38
	movs	r0, #0x2e			@ decimal point
	mov	r2, r10
	ldr	r1, [sp, #0x5c]
	blx	r2
	.inst.n	0x1c6d				@ adds r5, r5, #1
.L08003a38:
	subs.w	r1, r9, #0x0
	sub.w	r9, r9, #0x1
	bgt.n	.L08003a00
	b.n	.L08003a50
.L08003a44:
	ldrb.w	r0, [r7], #0x1			@ send the exponent text
	mov	r2, r10
	ldr	r1, [sp, #0x5c]
	blx	r2
	.inst.n	0x1c6d				@ adds r5, r5, #1
.L08003a50:
	ldr	r1, [sp, #0x8]
	subs	r0, r1, #0x1
	str	r0, [sp, #0x8]
	cmp	r1, #0x0
	bgt.n	.L08003a44
.L08003a5a:
	mov	r3, r10
	mov	r1, r4
	ldr	r2, [sp, #0x5c]
	ldr	r0, [sp, #0xc]
	b.n	.L080037a2			@ trailing pad, then the next character
.L08003a64:
	.byte	0x2d				@ "-"
	.byte	0x00, 0x00, 0x00		@ padding
.L08003a68:
	.ascii	"+"
	.byte	0x00				@ terminator
	.short	0x0000				@ padding
.L08003a6c:
	.ascii	" "
	.byte	0x00				@ terminator
	.short	0x0000				@ padding

@ ----------------------------------------------------------------------------
@ fn_08003a70 - writes trailing spaces for a left-justified field.
@   r0 = remaining pad count, r1 = flag word, r2 = value passed to the
@   callback, r3 = output callback (called as callback(0x20, r2)).
@ When bit 13 of the flag word (left justify) is set it decrements the count
@ and calls the callback while the decremented count stays non-negative;
@ otherwise nothing is written.
@ Returns in r0 the number of characters written.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003a70,"ax",%progbits
	.p2align 2
	.global fn_08003a70
	.thumb_func
	.type fn_08003a70, %function
fn_08003a70:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r4, r0				@ r4 = pad count
	movs	r5, #0x0			@ r5 = characters written
	mov	r6, r3				@ r6 = callback
	mov	r7, r2				@ r7 = callback value
	lsls	r0, r1, #0x12			@ bit 13 (left justify) set?
	bmi.n	.L08003a8a
	b.n	.L08003a8e
.L08003a82:
	mov	r1, r7
	movs	r0, #0x20			@ a space
	blx	r6
	.inst.n	0x1c6d				@ adds r5, r5, #1
.L08003a8a:
	.inst.n	0x1e64				@ subs r4, r4, #1
	bpl.n	.L08003a82
.L08003a8e:
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_08003a94 - writes leading pad characters for a right-justified field.
@   r0 = remaining pad count, r1 = flag word, r2 = value passed to the
@   callback, r3 = output callback (called as callback(pad char, r2)).
@ The pad character is '0' (0x30) when bit 16 of the flag word is set, else a
@ space (0x20). Nothing is written when bit 13 (left justify) is set.
@ Otherwise it calls the callback once per count in r0 (counting down while
@ the decremented counter stays non-negative).
@ Returns in r0 the number of characters written.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003a94,"ax",%progbits
	.global fn_08003a94
	.thumb_func
	.type fn_08003a94, %function
fn_08003a94:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r4, r0				@ r4 = pad count
	movs	r5, #0x0			@ r5 = characters written
	mov	r6, r3				@ r6 = callback
	mov	r8, r2				@ r8 = callback value
	lsls	r0, r1, #0xf			@ bit 16 ('0' flag) set?
	bpl.n	.L08003aa8
	movs	r7, #0x30			@ pad with '0'
	b.n	.L08003aaa
.L08003aa8:
	movs	r7, #0x20			@ pad with ' '
.L08003aaa:
	lsls	r0, r1, #0x12			@ bit 13 (left justify) set?
	bpl.n	.L08003ab8
	b.n	.L08003abc
.L08003ab0:
	mov	r1, r8
	mov	r0, r7
	blx	r6
	.inst.n	0x1c6d				@ adds r5, r5, #1
.L08003ab8:
	.inst.n	0x1e64				@ subs r4, r4, #1
	bpl.n	.L08003ab0
.L08003abc:
	mov	r0, r5
	pop.w	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_08003ac2 - output callback that stores one byte into a memory buffer.
@   r0 = byte to store, r1 = pointer to a buffer-pointer variable.
@ Reads the buffer pointer from [r1], stores r0 at that address and writes the
@ incremented pointer back to [r1]. Returns nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_08003ac2,"ax",%progbits
	.global fn_08003ac2
	.thumb_func
	.type fn_08003ac2, %function
fn_08003ac2:
	ldr	r2, [r1, #0x0]
	adds	r3, r2, #0x1
	str	r3, [r1, #0x0]
	strb	r0, [r2, #0x0]
	bx	lr

@ ----------------------------------------------------------------------------
@ bytes_differ - compares two byte ranges.
@   r0 = first address, r1 = second address, r2 = length in bytes.
@ Returns in r0: 1 at the first byte that differs, 0 when all r2 bytes are
@ equal (also 0 for length 0).
@ ----------------------------------------------------------------------------
	.section .text.bytes_differ,"ax",%progbits
	.p2align 2
	.global bytes_differ
	.thumb_func
	.type bytes_differ, %function
bytes_differ:
	push	{r4, r5, lr}
	movs	r3, #0x0			@ r3 = index
	b.n	.L08003ae0
.L08003ad2:
	ldrb	r4, [r0, r3]
	ldrb	r5, [r1, r3]
	cmp	r4, r5
	beq.n	.L08003ade
	movs	r0, #0x1			@ bytes differ
	pop	{r4, r5, pc}
.L08003ade:
	.inst.n	0x1c5b				@ adds r3, r3, #1
.L08003ae0:
	cmp	r3, r2
	bcc.n	.L08003ad2
	movs	r0, #0x0			@ all bytes equal
	pop	{r4, r5, pc}

@ ----------------------------------------------------------------------------
@ copy_bytes - copies bytes forward, one at a time.
@   r0 = destination address, r1 = source address, r2 = length in bytes.
@ Returns nothing (r0 is used as the index and ends equal to the length).
@ ----------------------------------------------------------------------------
	.section .text.copy_bytes,"ax",%progbits
	.p2align 2
	.global copy_bytes
	.thumb_func
	.type copy_bytes, %function
copy_bytes:
	push	{r4, lr}
	mov	r3, r0				@ r3 = destination
	movs	r0, #0x0			@ r0 = index
	b.n	.L08003af6
.L08003af0:
	ldrb	r4, [r1, r0]
	strb	r4, [r3, r0]
	.inst.n	0x1c40				@ adds r0, r0, #1
.L08003af6:
	cmp	r0, r2
	bcc.n	.L08003af0
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fill_bytes - fills a memory range with one byte value.
@   r0 = destination address, r1 = fill value (low 8 bits used), r2 = length
@   in bytes.
@ Returns nothing (r0 is used as the index and ends equal to the length).
@ ----------------------------------------------------------------------------
	.section .text.fill_bytes,"ax",%progbits
	.p2align 2
	.global fill_bytes
	.thumb_func
	.type fill_bytes, %function
fill_bytes:
	mov	r3, r0				@ r3 = destination
	movs	r0, #0x0			@ r0 = index
	uxtb	r1, r1				@ fill value
	b.n	.L08003b08
.L08003b04:
	strb	r1, [r3, r0]
	.inst.n	0x1c40				@ adds r0, r0, #1
.L08003b08:
	cmp	r0, r2
	bcc.n	.L08003b04
	bx	lr
	.short	0x0000				@ padding
