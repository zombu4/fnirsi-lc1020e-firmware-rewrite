@ periph_35.s - peripheral helper functions: pin configuration, register field writes, watchdog and NVIC access, RCC register updates
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0800911c - configure one pin from a pin descriptor word.
@ r0 = pin descriptor word, r1 = flag; no return value.
@ Bits 30, 29, 28 of r0 select the word 0x40010020, 0x40010024 or
@ 0x40010028 (base 0x40010000 from the literal, offsets 0x20, 0x24, 0x28);
@ none set selects the word 0x40010004.
@ shift = bit 21 of r0 * 16; mask = (r0 & 0xffff) << shift.
@ When (r0 & 0x70300000) == 0x300000 it clears 0xf000000 in the selected word
@ and in the word 0x40010004. Otherwise it tests bits 20, 21, 24, 25, 26, 2
@ and 3 of r0 to choose clearing, setting or writing 0xf000000 and bits 0 or
@ 3 of the word 0x40010004.
@ r1 == 0 skips the final or of the mask; the result is written back to the
@ selected word.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800911c,"ax",%progbits
	.p2align 2
	.global fn_0800911c
	.thumb_func
	.type fn_0800911c, %function
fn_0800911c:
	push {r4, r5, r6, r7, lr}
	ldr r3, .L08009220               @ r3 = 0x40010000
	lsls r2, r0, #1                  @ bit 30 of r0
	bpl.n .L08009128
	ldr r2, [r3, #0x20]
	b.n .L0800913a
.L08009128:
	lsls r2, r0, #2                  @ bit 29 of r0
	bpl.n .L08009130
	ldr r2, [r3, #0x24]
	b.n .L0800913a
.L08009130:
	lsls r2, r0, #3                  @ bit 28 of r0
	bpl.n .L08009138
	ldr r2, [r3, #0x28]
	b.n .L0800913a
.L08009138:
	ldr r2, [r3, #0x4]
.L0800913a:
	ldr r4, .L08009224               @ r4 = 0x70300000
	uxth r6, r0                      @ r6 = r0 & 0xffff
	and.w r7, r0, r4
	ubfx r4, r0, #0x15, #0x1         @ bit 21 of r0
	lsls r5, r4, #4                  @ shift = bit 21 * 16
	uxth r4, r0
	lsls r4, r5                      @ r4 = (r0 & 0xffff) << shift
	cmp.w r7, #0x300000
	beq.n .L0800916c
	lsls r7, r0, #0xb                @ bit 20 of r0
	bpl.n .L08009178
	lsls r6, r0, #0xa                @ bit 21 of r0 (flag N)
	mov.w r5, #0x3
	ubfx r7, r0, #0x10, #0x4
	lsl.w r5, r5, r7                 @ r5 = 3 << bits 16..19
	bpl.n .L08009168
	lsls r5, r5, #0x10
.L08009168:
	bics r2, r5
	b.n .L080091f4
.L0800916c:
	ldr r5, [r3, #0x4]
	bic r2, r2, #0xf000000
	bic r5, r5, #0xf000000
	b.n .L080091d8
.L08009178:
	lsls r7, r0, #0x7                @ bit 24 of r0
	bpl.n .L080091ac
	lsls r7, r0, #0x1d               @ bit 2 of r0
	bpl.n .L080091a2
	lsls r5, r0, #0x6                @ bit 25 of r0
	bic.w r2, r2, r4
	bpl.n .L0800919a
.L08009188:
	cmp r1, #0x0
	ldr r1, [r3, #0x4]
	beq.n .L08009194
	orr r1, r1, #0x1
	b.n .L080091c6
.L08009194:
	bic r1, r1, #0x1
	b.n .L080091ea
.L0800919a:
	ldr r5, [r3, #0x4]
	bic r5, r5, #0x1
	b.n .L080091d4
.L080091a2:
	orr r6, r6, #0x4
	lsls r6, r5
	bics r2, r6
	b.n .L08009188
.L080091ac:
	lsls r7, r0, #0x5                @ bit 26 of r0
	bpl.n .L080091f2
	lsls r7, r0, #0x1c               @ bit 3 of r0
	bpl.n .L080091dc
	lsls r5, r0, #0x6                @ bit 25 of r0
	bic.w r2, r2, r4
	bpl.n .L080091ce
.L080091bc:
	cmp r1, #0x0
	ldr r1, [r3, #0x4]
	beq.n .L080091e6
	orr r1, r1, #0x8
.L080091c6:
	orr r1, r1, #0xf000000
	str r1, [r3, #0x4]
	b.n .L08009200
.L080091ce:
	ldr r5, [r3, #0x4]
	bic r5, r5, #0x8
.L080091d4:
	orr r5, r5, #0xf000000
.L080091d8:
	str r5, [r3, #0x4]
	b.n .L080091fe
.L080091dc:
	orr r6, r6, #0x8
	lsls r6, r5
	bics r2, r6
	b.n .L080091bc
.L080091e6:
	bic r1, r1, #0x8
.L080091ea:
	orr r1, r1, #0xf000000
	str r1, [r3, #0x4]
	b.n .L08009202
.L080091f2:
	bics r2, r4
.L080091f4:
	tst.w r0, #0x70000000
	bne.n .L080091fe
	orr r2, r2, #0xf000000
.L080091fe:
	cbz r1, .L08009202
.L08009200:
	orrs r2, r4
.L08009202:
	lsls r1, r0, #1                  @ write the result back to the selected word
	bpl.n .L0800920a
	str r2, [r3, #0x20]
	pop {r4, r5, r6, r7, pc}
.L0800920a:
	lsls r1, r0, #2
	bpl.n .L08009212
	str r2, [r3, #0x24]
	pop {r4, r5, r6, r7, pc}
.L08009212:
	lsls r0, r0, #3
	bpl.n .L0800921a
	str r2, [r3, #0x28]
	pop {r4, r5, r6, r7, pc}
.L0800921a:
	str r2, [r3, #0x4]
	pop {r4, r5, r6, r7, pc}
	.short 0x0000                    @ padding
.L08009220:
	.word 0x40010000
.L08009224:
	.word 0x70300000

@ ----------------------------------------------------------------------------
@ fn_08009228 - write a 4-bit field into one or two configuration words.
@ r0 = pointer to a register block, r1 = pointer to a block (halfword bit
@ mask, byte 3 = mode); no return value.
@ n = mode & 0xf, or-ed with the block byte at +2 when bit 4 of the mode is
@ set.
@ Low 8 mask bits: sets the 4-bit field i of the word [r0+0] to n for every
@ mask bit i set; high 8 mask bits: the same for the word [r0+4].
@ Mode 0x28 also stores the bit to the word [r0+0x14], mode 0x48 to the word
@ [r0+0x10].
@ ----------------------------------------------------------------------------
	.section .text.fn_08009228,"ax",%progbits
	.p2align 2
	.global fn_08009228
	.thumb_func
	.type fn_08009228, %function
fn_08009228:
	push {r4, r5, r6, r7, lr}
	ldrb r2, [r1, #0x3]              @ mode
	movs r5, #0x0
	and r3, r2, #0xf                 @ n = mode & 0xf
	lsls r2, r2, #0x1b               @ bit 4 of the mode
	bpl.n .L0800923a
	ldrb r2, [r1, #0x2]
	orrs r3, r2
.L0800923a:
	ldrb r2, [r1, #0x0]              @ low 8 mask bits
	mov.w lr, #0xf
	tst.w r2, #0xff
	mov.w r2, #0x1
	beq.n .L08009284
	ldr r4, [r0, #0x0]
.L0800924c:
	ldrh r7, [r1, #0x0]
	lsl.w r6, r2, r5                 @ r6 = 1 << i
	ands r7, r6
	cmp r7, r6
	bne.n .L0800927c
	lsl.w r12, r5, #2                @ r12 = 4 * i
	lsl.w r7, lr, r12
	bic.w r7, r4, r7
	lsl.w r4, r3, r12
	orrs r4, r7
	ldrb r7, [r1, #0x3]
	cmp r7, #0x28
	beq.n .L08009276
	cmp r7, #0x48
	beq.n .L0800927a
	b.n .L0800927c
.L08009276:
	str r6, [r0, #0x14]
	b.n .L0800927c
.L0800927a:
	str r6, [r0, #0x10]
.L0800927c:
	.inst.n 0x1c6d                   @ adds r5, r5, #1
	cmp r5, #0x8
	bcc.n .L0800924c
	str r4, [r0, #0x0]
.L08009284:
	ldrh r4, [r1, #0x0]
	cmp r4, #0xff
	bls.n .L080092c8                 @ no high mask bits
	ldr r4, [r0, #0x4]
	movs.w r6, #0x0
.L08009290:
	add.w r7, r6, #0x8
	lsl.w r5, r2, r7                 @ r5 = 1 << (i + 8)
	ldrh r7, [r1, #0x0]
	ands r7, r5
	cmp r7, r5
	bne.n .L080092c0
	lsl.w r12, r6, #2
	lsl.w r7, lr, r12
	bics r4, r7
	lsl.w r7, r3, r12
	orrs r4, r7
	ldrb r7, [r1, #0x3]
	cmp r7, #0x28
	bne.n .L080092b8
	str r5, [r0, #0x14]
.L080092b8:
	ldrb r7, [r1, #0x3]
	cmp r7, #0x48
	bne.n .L080092c0
	str r5, [r0, #0x10]
.L080092c0:
	.inst.n 0x1c76                   @ adds r6, r6, #1
	cmp r6, #0x8
	bcc.n .L08009290
	str r4, [r0, #0x4]
.L080092c8:
	pop {r4, r5, r6, r7, pc}
	.short 0x0000                    @ padding

@ ----------------------------------------------------------------------------
@ fn_08009374 - store r0 to the word 0x40003008.
@ r0 = value; no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08009374,"ax",%progbits
	.p2align 2
	.global fn_08009374
	.thumb_func
	.type fn_08009374, %function
fn_08009374:
	ldr r1, .L0800937c
	str r0, [r1, #0x8]
	bx lr
	.short 0x0000                    @ padding
.L0800937c:
	.word 0x40003000

@ ----------------------------------------------------------------------------
@ store_0xcccc_at_40003000 - store 0x0000cccc to the word 0x40003000.
@ No parameters, no return value. The only effect is one 32-bit store to the
@ peripheral register at 0x40003000.
@ ----------------------------------------------------------------------------
	.section .text.store_0xcccc_at_40003000,"ax",%progbits
	.p2align 2
	.global store_0xcccc_at_40003000
	.thumb_func
	.type store_0xcccc_at_40003000, %function
store_0xcccc_at_40003000:
	ldr r1, .L0800938c
	movw r0, #0xcccc
	str r0, [r1, #0x0]
	bx lr
	.short 0x0000                    @ padding
.L0800938c:
	.word 0x40003000

@ ----------------------------------------------------------------------------
@ fn_08009390 - store 0x0000aaaa to the word 0x40003000.
@ No parameters, no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08009390,"ax",%progbits
	.p2align 2
	.global fn_08009390
	.thumb_func
	.type fn_08009390, %function
fn_08009390:
	ldr r1, .L0800939c
	movw r0, #0xaaaa
	str r0, [r1, #0x0]
	bx lr
	.short 0x0000                    @ padding
.L0800939c:
	.word 0x40003000

@ ----------------------------------------------------------------------------
@ fn_080093a0 - store r0 to the word 0x40003004.
@ r0 = value; no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080093a0,"ax",%progbits
	.p2align 2
	.global fn_080093a0
	.thumb_func
	.type fn_080093a0, %function
fn_080093a0:
	ldr r1, .L080093a8
	str r0, [r1, #0x4]
	bx lr
	.short 0x0000                    @ padding
.L080093a8:
	.word 0x40003000

@ ----------------------------------------------------------------------------
@ fn_080093ac - store r0 to the word 0x40003000.
@ r0 = value; no return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080093ac,"ax",%progbits
	.p2align 2
	.global fn_080093ac
	.thumb_func
	.type fn_080093ac, %function
fn_080093ac:
	ldr r1, .L080093b4
	str r0, [r1, #0x0]
	bx lr
	.short 0x0000                    @ padding
.L080093b4:
	.word 0x40003000

@ ----------------------------------------------------------------------------
@ fn_0800ad68 - set up or disable one interrupt in the NVIC.
@ r0 = pointer to a 4-byte descriptor (byte 0 = interrupt number n, byte 1 =
@ preemption value, byte 2 = sub value, byte 3 = enable flag); no return
@ value.
@ When byte 3 is 0 it writes 1 << (n & 0x1f) to the word at 0xE000E180 +
@ (n >> 5) * 4.
@ Otherwise it reads the priority grouping field of the word 0xE000ED0C
@ (mask 0x700), computes the group shift as (0x700 - field) >> 8, stores
@ ((byte2 & (0xf >> shift)) | (byte1 << (4 - shift))) << 4 to the byte
@ 0xE000E400 + n, then writes 1 << (n & 0x1f) to the word at 0xE000E100 +
@ (n >> 5) * 4.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ad68,"ax",%progbits
	.p2align 2
	.global fn_0800ad68
	.thumb_func
	.type fn_0800ad68, %function
fn_0800ad68:
	push {r4, r5, r6, lr}
	movs r3, #0xf
	ldrb r4, [r0, #0x3]              @ enable flag
	ldrb r1, [r0, #0x0]              @ interrupt number
	movs r2, #0x1
	cbz r4, .L0800adb2
	ldr r4, .L0800adc8               @ r4 = 0xE000ED0C
	ldr r4, [r4, #0x0]
	ldrb r5, [r0, #0x1]
	and r4, r4, #0x700
	rsb.w r4, r4, #0x700
	lsrs r4, r4, #0x8                @ group shift
	rsb.w r6, r4, #0x4
	lsrs r3, r4
	ldrb r4, [r0, #0x2]
	lsls r5, r6
	ands r4, r3
	orrs r4, r5
	add.w r1, r1, #0xe000e000
	lsls r3, r4, #0x4
	strb.w r3, [r1, #0x400]          @ priority byte 0xE000E400 + n
	ldrb r0, [r0, #0x0]
	and r1, r0, #0x1f
	lsls r2, r1
	lsrs r0, r0, #0x5
	lsls r0, r0, #0x2
	add.w r0, r0, #0xe000e000
	str.w r2, [r0, #0x100]           @ word 0xE000E100 + (n >> 5) * 4
	pop {r4, r5, r6, pc}
.L0800adb2:
	and r0, r1, #0x1f
	lsls r2, r0
	lsrs r0, r1, #0x5
	lsls r0, r0, #0x2
	add.w r0, r0, #0xe000e000
	str.w r2, [r0, #0x180]           @ word 0xE000E180 + (n >> 5) * 4
	pop {r4, r5, r6, pc}
	.short 0x0000                    @ padding
.L0800adc8:
	.word 0xe000ed0c

@ ----------------------------------------------------------------------------
@ init_four_byte_record - store default values into a 4-byte record.
@ r0 = pointer to 4 bytes; no return value.
@ Stores 0 at offset 2, 1 at offset 1, 0 at offset 0, 4 at offset 3.
@ ----------------------------------------------------------------------------
	.section .text.init_four_byte_record,"ax",%progbits
	.p2align 2
	.global init_four_byte_record
	.thumb_func
	.type init_four_byte_record, %function
init_four_byte_record:
	movs r1, #0x0
	strb r1, [r0, #0x2]
	movs r2, #0x1
	strb r2, [r0, #0x1]
	strb r1, [r0, #0x0]
	movs r1, #0x4
	strb r1, [r0, #0x3]
	bx lr

@ ----------------------------------------------------------------------------
@ fn_0800b290 - replace the field of bits 10..15 in the word 0x4002102c.
@ r0, r1 = bit values.
@ Word 0x4002102c = (word & 0xffff03ff) | r0 | r1; the address is
@ RCC base 0x40021000 + 0x2c.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b290,"ax",%progbits
	.p2align 2
	.global fn_0800b290
	.thumb_func
	.type fn_0800b290, %function
fn_0800b290:
	ldr r3, .L0800b2a0
	ldr r2, [r3, #0x2c]
	bic r2, r2, #0xfc00
	orrs r2, r0
	orrs r2, r1
	str r2, [r3, #0x2c]
	bx lr
.L0800b2a0:
	.word 0x40021000

@ ----------------------------------------------------------------------------
@ fn_0800b2a4 - replace the low 4 bits of the word 0x4002102c.
@ r0 = bits.
@ Word 0x4002102c = (word & 0xfffffff0) | r0; the address is RCC base
@ 0x40021000 + 0x2c.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b2a4,"ax",%progbits
	.p2align 2
	.global fn_0800b2a4
	.thumb_func
	.type fn_0800b2a4, %function
fn_0800b2a4:
	ldr r2, .L0800b2b4
	ldr r1, [r2, #0x2c]
	bic r1, r1, #0xf
	orrs r1, r0
	str r1, [r2, #0x2c]
	bx lr
	.short 0x0000                    @ padding
.L0800b2b4:
	.word 0x40021000

@ ----------------------------------------------------------------------------
@ fn_0800b2b8 - replace bits 4..8 of the word 0x4002102c.
@ r0 = bits, r1 = flag.
@ When r1 is 0 it clears bit 0x100 of r0.
@ Word 0x4002102c = (word & 0xfffffe0f) | r0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b2b8,"ax",%progbits
	.p2align 2
	.global fn_0800b2b8
	.thumb_func
	.type fn_0800b2b8, %function
fn_0800b2b8:
	ldr r3, .L0800b2d0
	ldr r2, [r3, #0x2c]
	bic r2, r2, #0x1f0
	orr.w r2, r2, r0
	cbnz r1, .L0800b2ca
	bic r2, r2, #0x100
.L0800b2ca:
	str r2, [r3, #0x2c]
	bx lr
	.short 0x0000                    @ padding
.L0800b2d0:
	.word 0x40021000

@ ----------------------------------------------------------------------------
@ set_or_clear_bits_40021014 - set or clear bits in the word 0x40021014.
@ r0 = bit mask, r1 = flag.
@ Word 0x40021014 = word | r0 when r1 is non-zero, word & ~r0 when r1 is 0.
@ ----------------------------------------------------------------------------
	.section .text.set_or_clear_bits_40021014,"ax",%progbits
	.p2align 2
	.global set_or_clear_bits_40021014
	.thumb_func
	.type set_or_clear_bits_40021014, %function
set_or_clear_bits_40021014:
	ldr r2, .L0800b2e8
	cmp r1, #0x0
	ldr r1, [r2, #0x14]
	beq.n .L0800b2e0
	orrs r1, r0
	b.n .L0800b2e2
.L0800b2e0:
	bics r1, r0
.L0800b2e2:
	str r1, [r2, #0x14]
	bx lr
	.short 0x0000                    @ padding
.L0800b2e8:
	.word 0x40021000

@ ----------------------------------------------------------------------------
@ set_or_clear_bits_40021028 - set or clear bits in the word 0x40021028.
@ r0 = bit mask, r1 = flag.
@ Word 0x40021028 = word | r0 when r1 is non-zero, word & ~r0 when r1 is 0.
@ ----------------------------------------------------------------------------
	.section .text.set_or_clear_bits_40021028,"ax",%progbits
	.p2align 2
	.global set_or_clear_bits_40021028
	.thumb_func
	.type set_or_clear_bits_40021028, %function
set_or_clear_bits_40021028:
	ldr r2, .L0800b300
	cmp r1, #0x0
	ldr r1, [r2, #0x28]
	beq.n .L0800b2f8
	orrs r1, r0
	b.n .L0800b2fa
.L0800b2f8:
	bics r1, r0
.L0800b2fa:
	str r1, [r2, #0x28]
	bx lr
	.short 0x0000                    @ padding
.L0800b300:
	.word 0x40021000

@ ----------------------------------------------------------------------------
@ set_or_clear_bits_4002101c - set or clear bits in the word 0x4002101c.
@ r0 = bit mask, r1 = flag.
@ Word 0x4002101c = word | r0 when r1 is non-zero, word & ~r0 when r1 is 0.
@ ----------------------------------------------------------------------------
	.section .text.set_or_clear_bits_4002101c,"ax",%progbits
	.p2align 2
	.global set_or_clear_bits_4002101c
	.thumb_func
	.type set_or_clear_bits_4002101c, %function
set_or_clear_bits_4002101c:
	ldr r2, .L0800b318
	cmp r1, #0x0
	ldr r1, [r2, #0x1c]
	beq.n .L0800b310
	orrs r1, r0
	b.n .L0800b312
.L0800b310:
	bics r1, r0
.L0800b312:
	str r1, [r2, #0x1c]
	bx lr
	.short 0x0000                    @ padding
.L0800b318:
	.word 0x40021000

@ ----------------------------------------------------------------------------
@ set_or_clear_bits_40021010 - set or clear bits in the word 0x40021010.
@ r0 = bit mask, r1 = flag.
@ Word 0x40021010 = word | r0 when r1 is non-zero, word & ~r0 when r1 is 0.
@ ----------------------------------------------------------------------------
	.section .text.set_or_clear_bits_40021010,"ax",%progbits
	.p2align 2
	.global set_or_clear_bits_40021010
	.thumb_func
	.type set_or_clear_bits_40021010, %function
set_or_clear_bits_40021010:
	ldr r2, .L0800b330
	cmp r1, #0x0
	ldr r1, [r2, #0x10]
	beq.n .L0800b328
	orrs r1, r0
	b.n .L0800b32a
.L0800b328:
	bics r1, r0
.L0800b32a:
	str r1, [r2, #0x10]
	bx lr
	.short 0x0000                    @ padding
.L0800b330:
	.word 0x40021000

@ ----------------------------------------------------------------------------
@ set_or_clear_bits_40021018 - set or clear bits in the word 0x40021018.
@ r0 = bit mask, r1 = flag.
@ Word 0x40021018 = word | r0 when r1 is non-zero, word & ~r0 when r1 is 0.
@ ----------------------------------------------------------------------------
	.section .text.set_or_clear_bits_40021018,"ax",%progbits
	.p2align 2
	.global set_or_clear_bits_40021018
	.thumb_func
	.type set_or_clear_bits_40021018, %function
set_or_clear_bits_40021018:
	ldr r2, .L0800b348
	cmp r1, #0x0
	ldr r1, [r2, #0x18]
	beq.n .L0800b340
	orrs r1, r0
	b.n .L0800b342
.L0800b340:
	bics r1, r0
.L0800b342:
	str r1, [r2, #0x18]
	bx lr
	.short 0x0000                    @ padding
.L0800b348:
	.word 0x40021000

@ ----------------------------------------------------------------------------
@ set_or_clear_bits_4002100c - set or clear bits in the word 0x4002100c.
@ r0 = bit mask, r1 = flag.
@ Word 0x4002100c = word | r0 when r1 is non-zero, word & ~r0 when r1 is 0.
@ ----------------------------------------------------------------------------
	.section .text.set_or_clear_bits_4002100c,"ax",%progbits
	.p2align 2
	.global set_or_clear_bits_4002100c
	.thumb_func
	.type set_or_clear_bits_4002100c, %function
set_or_clear_bits_4002100c:
	ldr r2, .L0800b360
	cmp r1, #0x0
	ldr r1, [r2, #0xc]
	beq.n .L0800b358
	orrs r1, r0
	b.n .L0800b35a
.L0800b358:
	bics r1, r0
.L0800b35a:
	str r1, [r2, #0xc]
	bx lr
	.short 0x0000                    @ padding
.L0800b360:
	.word 0x40021000

@ ----------------------------------------------------------------------------
@ fn_0800b364 - read the clock configuration and store six frequency values.
@ r0 = pointer to a 6-word result.
@ Reads the word 0x40021004: multiplier = ((w & 0x83c0000) >> 0x12) + 2, or
@ the same shifted value - 0x1ef when bit 0x8000000 of the masked word is
@ set; base = 4000000 (0x003d0900) unless bit 0x10000 of the word is set and
@ bit 0x20000 of the word is clear, then 8000000 (0x007a1200).
@ uVar1 = base * multiplier.
@ Field (w & 0xc): 8 stores uVar1 to word 0, anything else stores 8000000.
@ Word 1 = word0 >> byte table 0x0802aefc[(w >> 4) & 0xf]; word 2 = word1 >>
@ table[(w >> 8) & 7]; word 3 = word1 >> table[(w >> 0xb) & 7]; word 5 =
@ word1 / byte table 0x0802af0c[word 0x4002102c & 0xf]; word 4 = uVar1 /
@ halfword table 0x0802af1c[(word 0x4002102c >> 4) & 0xf].
@ ----------------------------------------------------------------------------
	.section .text.fn_0800b364,"ax",%progbits
	.p2align 2
	.global fn_0800b364
	.thumb_func
	.type fn_0800b364, %function
fn_0800b364:
	push {r4, r5, r6, lr}
	ldr r1, .L0800b40c               @ r1 = 0x40021000
	ldr r2, [r1, #0x4]
	ldr r3, .L0800b410               @ r3 = 0x083c0000
	ands r2, r3
	ldr r3, [r1, #0x4]
	lsls r4, r2, #0x4                @ bit 0x8000000 of the masked word
	and r3, r3, #0x10000
	bmi.n .L0800b37c
	movs r4, #0x2
	b.n .L0800b380
.L0800b37c:
	mvn r4, #0x1ee                   @ r4 = -0x1ef
.L0800b380:
	add.w r2, r4, r2, lsr #0x12
	cbz r3, .L0800b38c
	ldr r3, [r1, #0x4]
	lsls r3, r3, #0xe                @ bit 0x20000 of the word
	bpl.n .L0800b390
.L0800b38c:
	ldr r3, .L0800b414               @ r3 = 4000000
	b.n .L0800b392
.L0800b390:
	ldr r3, .L0800b418               @ r3 = 8000000
.L0800b392:
	muls r2, r3, r2                  @ uVar1 = base * multiplier
	ldr r3, [r1, #0x4]
	ands r4, r3, #0xc
	ldr r3, .L0800b418
	beq.n .L0800b3a6
	cmp r4, #0x4
	beq.n .L0800b3a6
	cmp r4, #0x8
	beq.n .L0800b3aa
.L0800b3a6:
	str r3, [r0, #0x0]               @ word 0 = 8000000
	b.n .L0800b3ac
.L0800b3aa:
	str r2, [r0, #0x0]               @ word 0 = uVar1
.L0800b3ac:
	ldr r3, [r1, #0x4]
	movs r4, #0xf
	and.w r3, r4, r3, lsr #0x4
	ldr r4, .L0800b41c               @ r4 = 0x0802aefc
	ldrb r5, [r4, r3]
	ldr r3, [r0, #0x0]
	lsrs r3, r5
	str r3, [r0, #0x4]               @ word 1
	ldr r5, [r1, #0x4]
	movs r6, #0x7
	and.w r5, r6, r5, lsr #0x8
	ldrb r5, [r4, r5]
	lsr.w r5, r3, r5
	str r5, [r0, #0x8]               @ word 2
	ldr r5, [r1, #0x4]
	and.w r5, r6, r5, lsr #0xb
	ldrb r4, [r4, r5]
	lsr.w r4, r3, r4
	str r4, [r0, #0xc]               @ word 3
	ldr r4, [r1, #0x2c]
	ldr r5, .L0800b41c
	and r4, r4, #0xf
	adds r5, #0x10                   @ r5 = 0x0802af0c
	ldrb r4, [r5, r4]
	udiv r3, r3, r4
	str r3, [r0, #0x14]              @ word 5
	ldr r1, [r1, #0x2c]
	movs r3, #0x1f
	and.w r1, r3, r1, lsr #0x4
	and r1, r1, #0xf
	add.w r3, r5, #0x10              @ r3 = 0x0802af1c
	ldrh.w r1, [r3, r1, lsl #0x1]
	udiv r1, r2, r1
	str r1, [r0, #0x10]              @ word 4
	pop {r4, r5, r6, pc}
	.short 0x0000                    @ padding
.L0800b40c:
	.word 0x40021000
.L0800b410:
	.word 0x083c0000
.L0800b414:
	.word 0x003d0900
.L0800b418:
	.word 0x007a1200
.L0800b41c:
	.word d_0802aefc

@ ----------------------------------------------------------------------------
@ set_or_clear_bit_7 - set or clear bit 7 of a word.
@ r0 = pointer to a word, r1 = flag.
@ Sets bit 0x80 of the word when r1 is non-zero, clears it when r1 is 0.
@ ----------------------------------------------------------------------------
	.section .text.set_or_clear_bit_7,"ax",%progbits
	.p2align 2
	.global set_or_clear_bit_7
	.thumb_func
	.type set_or_clear_bit_7, %function
set_or_clear_bit_7:
	cmp r1, #0x0
	ldr r1, [r0, #0x0]
	beq.n .L0800c314
	orr r1, r1, #0x80
	b.n .L0800c318
.L0800c314:
	bic r1, r1, #0x80
.L0800c318:
	str r1, [r0, #0x0]
	bx lr

@ ----------------------------------------------------------------------------
@ fn_0800c31c - replace bit 3 of the halfword at base + 0x18.
@ r0 = base address, r1 = bits.
@ Halfword at r0 + 0x18 = (halfword & 0xfff7) | r1.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c31c,"ax",%progbits
	.p2align 2
	.global fn_0800c31c
	.thumb_func
	.type fn_0800c31c, %function
fn_0800c31c:
	ldrh r2, [r0, #0x18]
	bic r2, r2, #0x8
	orrs r2, r1
	strh r2, [r0, #0x18]
	bx lr

@ ----------------------------------------------------------------------------
@ fn_0800c328 - replace bit 11 of the halfword at base + 0x18.
@ r0 = base address, r1 = value.
@ Halfword at r0 + 0x18 = ((r1 << 8) & 0xffff) | (halfword & 0xf7ff).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c328,"ax",%progbits
	.p2align 2
	.global fn_0800c328
	.thumb_func
	.type fn_0800c328, %function
fn_0800c328:
	ldrh r2, [r0, #0x18]
	movw r3, #0xffff
	bic r2, r2, #0x800
	and.w r1, r3, r1, lsl #0x8
	orrs r1, r2
	strh r1, [r0, #0x18]
	bx lr

@ ----------------------------------------------------------------------------
@ fn_0800c33c - pulse the reset bit of the peripheral at base r0.
@ r0 = peripheral base address; no return value.
@ Compares r0 with 0x40012c00 and 0x40013400 (bits 0x800 and 0x2000 in the
@ word 0x4002100c: set, then cleared, via set_or_clear_bits_4002100c) and with
@ 0x40000000, 0x40000400, 0x40000800, 0x40000c00, 0x40001000, 0x40001400
@ (bits 1, 2, 4, 8, 0x10, 0x20 in the word 0x40021010: set, then cleared, via
@ set_or_clear_bits_40021010). Other values do nothing.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c33c,"ax",%progbits
	.p2align 2
	.global fn_0800c33c
	.thumb_func
	.type fn_0800c33c, %function
fn_0800c33c:
	ldr r1, .L0800c3e8               @ r1 = 0x40012c00
	push {r4, lr}
	cmp r0, r1
	bne.n .L0800c34a
	movs r1, #0x1
	asrs r4, r0, #0x13               @ r4 = 0x800
	b.n .L0800c3d2
.L0800c34a:
	cmp.w r0, #0x40000000
	beq.n .L0800c364
	ldr r1, .L0800c3ec               @ r1 = 0x40000400
	cmp r0, r1
	bne.n .L0800c372
	movs r1, #0x1
	movs r0, #0x2
	bl set_or_clear_bits_40021010
	movs r1, #0x0
	movs r0, #0x2
	b.n .L0800c3c0
.L0800c364:
	movs r1, #0x1
	mov r0, r1
	bl set_or_clear_bits_40021010
	movs r1, #0x0
	movs r0, #0x1
	b.n .L0800c3c0
.L0800c372:
	ldr r1, .L0800c3f0               @ r1 = 0x40000800
	cmp r0, r1
	bne.n .L0800c386
	movs r1, #0x1
	movs r0, #0x4
	bl set_or_clear_bits_40021010
	movs r1, #0x0
	movs r0, #0x4
	b.n .L0800c3c0
.L0800c386:
	ldr r1, .L0800c3f4               @ r1 = 0x40000c00
	cmp r0, r1
	bne.n .L0800c39a
	movs r1, #0x1
	movs r0, #0x8
	bl set_or_clear_bits_40021010
	movs r1, #0x0
	movs r0, #0x8
	b.n .L0800c3c0
.L0800c39a:
	ldr r1, .L0800c3f8               @ r1 = 0x40001000
	cmp r0, r1
	bne.n .L0800c3ae
	movs r1, #0x1
	movs r0, #0x10
	bl set_or_clear_bits_40021010
	movs r1, #0x0
	movs r0, #0x10
	b.n .L0800c3c0
.L0800c3ae:
	ldr r1, .L0800c3fc               @ r1 = 0x40001400
	cmp r0, r1
	bne.n .L0800c3c8
	movs r1, #0x1
	movs r0, #0x20
	bl set_or_clear_bits_40021010
	movs r1, #0x0
	movs r0, #0x20
.L0800c3c0:
	pop.w {r4, lr}
	b.w set_or_clear_bits_40021010   @ clear step, tail call
.L0800c3c8:
	ldr r1, .L0800c400               @ r1 = 0x40013400
	cmp r0, r1
	bne.n .L0800c3e4
	movs r1, #0x1
	asrs r4, r0, #0x11               @ r4 = 0x2000
.L0800c3d2:
	mov r0, r4
	bl set_or_clear_bits_4002100c
	mov r0, r4
	pop.w {r4, lr}
	movs r1, #0x0
	b.w set_or_clear_bits_4002100c   @ clear step, tail call
.L0800c3e4:
	pop {r4, pc}
	.short 0x0000                    @ padding
.L0800c3e8:
	.word 0x40012c00
.L0800c3ec:
	.word 0x40000400
.L0800c3f0:
	.word 0x40000800
.L0800c3f4:
	.word 0x40000c00
.L0800c3f8:
	.word 0x40001000
.L0800c3fc:
	.word 0x40001400
.L0800c400:
	.word 0x40013400

@ ----------------------------------------------------------------------------
@ set_or_clear_bit_0_0800c404 - set or clear bit 0 of a word.
@ r0 = pointer to a word, r1 = flag.
@ Sets bit 0 of the word when r1 is non-zero, clears it otherwise.
@ ----------------------------------------------------------------------------
	.section .text.set_or_clear_bit_0_0800c404,"ax",%progbits
	.p2align 2
	.global set_or_clear_bit_0_0800c404
	.thumb_func
	.type set_or_clear_bit_0_0800c404, %function
set_or_clear_bit_0_0800c404:
	cmp r1, #0x0
	ldr r1, [r0, #0x0]
	beq.n .L0800c410
	orr r1, r1, #0x1
	b.n .L0800c414
.L0800c410:
	bic r1, r1, #0x1
.L0800c414:
	str r1, [r0, #0x0]
	bx lr

@ ----------------------------------------------------------------------------
@ fn_0800c418 - set or clear bit 15 of the halfword at base + 0x44.
@ r0 = base address, r1 = flag.
@ Sets bit 0x8000 of the halfword at r0 + 0x44 when r1 is non-zero, clears
@ it otherwise.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c418,"ax",%progbits
	.p2align 2
	.global fn_0800c418
	.thumb_func
	.type fn_0800c418, %function
fn_0800c418:
	cmp r1, #0x0
	ldrh.w r1, [r0, #0x44]!
	beq.n .L0800c426
	orr r1, r1, #0x8000
	b.n .L0800c42a
.L0800c426:
	ubfx r1, r1, #0x0, #0xf          @ clear bit 15
.L0800c42a:
	strh r1, [r0, #0x0]
	bx lr
	.short 0x0000                    @ padding

@ ----------------------------------------------------------------------------
@ fn_0800c430 - set up one output channel of a timer-like peripheral.
@ r0 = base address, r1 = pointer to 8 halfwords.
@ Clears bit 0 of the word r0 + 0x20.
@ Builds the word at r0 + 0x20 from halfwords 1 and 4, adds halfwords 2 and 5
@ (with bits 3 and 2 cleared) when r0 is 0x40012c00 or 0x40013400; in that
@ case it also builds the word r0 + 4 = (word & 0xfffffcff) | halfwords 7 and
@ 6.
@ Halfword at r0 + 0x18 = halfword 0 | (old & 0xff8c); halfword at r0 + 0x34
@ = halfword 3.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c430,"ax",%progbits
	.p2align 2
	.global fn_0800c430
	.thumb_func
	.type fn_0800c430, %function
fn_0800c430:
	push {r4, r5, lr}
	ldr r2, [r0, #0x20]
	bic r2, r2, #0x1
	str r2, [r0, #0x20]
	ldr r2, [r0, #0x20]
	ldr r3, [r0, #0x4]
	ldrh r4, [r0, #0x18]
	bic r2, r2, #0x2
	bic r5, r4, #0x73
	ldrh r4, [r1, #0x0]
	orrs r4, r5
	ldrh r5, [r1, #0x8]
	orrs r5, r2
	ldrh r2, [r1, #0x2]
	orrs r2, r5
	ldr r5, .L0800c488               @ r5 = 0x40012c00
	cmp r0, r5
	beq.n .L0800c460
	ldr r5, .L0800c48c               @ r5 = 0x40013400
	cmp r0, r5
	bne.n .L0800c47c
.L0800c460:
	bic r5, r2, #0x8
	ldrh r2, [r1, #0xa]
	bic r3, r3, #0x300
	orrs r2, r5
	bic r5, r2, #0x4
	ldrh r2, [r1, #0x4]
	orrs r2, r5
	ldrh r5, [r1, #0xc]
	orrs r5, r3
	ldrh r3, [r1, #0xe]
	orrs r3, r5
.L0800c47c:
	str r3, [r0, #0x4]
	strh r4, [r0, #0x18]
	ldrh r1, [r1, #0x6]
	strh r1, [r0, #0x34]
	str r2, [r0, #0x20]
	pop {r4, r5, pc}
.L0800c488:
	.word 0x40012c00
.L0800c48c:
	.word 0x40013400

@ ----------------------------------------------------------------------------
@ fn_0800c490 - set up the second output channel of a timer-like peripheral.
@ r0 = base address, r1 = pointer to 8 halfwords.
@ Same shape as fn_0800c430 for the second channel: clears bit 4 of the word
@ r0 + 0x20, ors halfwords 4 and 1 shifted left by 4; for 0x40012c00 and
@ 0x40013400 also halfwords 5 and 2 (shift 4) and halfwords 6 and 7 (shift
@ 2) into the word r0 + 4.
@ Halfword at r0 + 0x18 = (halfword 0 << 8) | (old & 0x8cff); halfword at
@ r0 + 0x38 = halfword 3.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c490,"ax",%progbits
	.p2align 2
	.global fn_0800c490
	.thumb_func
	.type fn_0800c490, %function
fn_0800c490:
	push {r4, r5, r6, lr}
	ldr r2, [r0, #0x20]
	bic r2, r2, #0x10
	str r2, [r0, #0x20]
	ldr r3, [r0, #0x20]
	ldr r2, [r0, #0x4]
	ldrh r4, [r0, #0x18]
	movw r6, #0xffff
	bic r5, r4, #0x7300
	ldrh r4, [r1, #0x0]
	bic r3, r3, #0x20
	and.w r4, r6, r4, lsl #0x8
	orrs r4, r5
	ldrh r5, [r1, #0x8]
	orr.w r3, r3, r5, lsl #0x4
	ldrh r5, [r1, #0x2]
	orr.w r3, r3, r5, lsl #0x4
	ldr r5, .L0800c4fc               @ r5 = 0x40012c00
	cmp r0, r5
	beq.n .L0800c4cc
	ldr r5, .L0800c500               @ r5 = 0x40013400
	cmp r0, r5
	bne.n .L0800c4f0
.L0800c4cc:
	ldrh r5, [r1, #0xa]
	bic r3, r3, #0x80
	orr.w r3, r3, r5, lsl #0x4
	ldrh r5, [r1, #0x4]
	bic r3, r3, #0x40
	orr.w r3, r3, r5, lsl #0x4
	ldrh r5, [r1, #0xc]
	bic r2, r2, #0xc00
	orr.w r2, r2, r5, lsl #0x2
	ldrh r5, [r1, #0xe]
	orr.w r2, r2, r5, lsl #0x2
.L0800c4f0:
	str r2, [r0, #0x4]
	strh r4, [r0, #0x18]
	ldrh r1, [r1, #0x6]
	strh r1, [r0, #0x38]
	str r3, [r0, #0x20]
	pop {r4, r5, r6, pc}
.L0800c4fc:
	.word 0x40012c00
.L0800c500:
	.word 0x40013400

@ ----------------------------------------------------------------------------
@ fn_0800c504 - set up the third output channel of a timer-like peripheral.
@ r0 = base address, r1 = pointer to 8 halfwords.
@ Third channel version: clears bit 8 of the word r0 + 0x20, ors halfwords 4
@ and 1 shifted left by 8; for 0x40012c00 and 0x40013400 also halfwords 5 and
@ 2 (shift 8) and halfwords 6 and 7 (shift 4).
@ Halfword at r0 + 0x1c = halfword 0 | (old & 0xff8c); halfword at r0 + 0x3c
@ = halfword 3.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c504,"ax",%progbits
	.p2align 2
	.global fn_0800c504
	.thumb_func
	.type fn_0800c504, %function
fn_0800c504:
	push {r4, r5, lr}
	ldr r2, [r0, #0x20]
	bic r2, r2, #0x100
	str r2, [r0, #0x20]
	ldr r3, [r0, #0x20]
	ldr r2, [r0, #0x4]
	ldrh r4, [r0, #0x1c]
	bic r3, r3, #0x200
	bic r5, r4, #0x73
	ldrh r4, [r1, #0x0]
	orrs r4, r5
	ldrh r5, [r1, #0x8]
	orr.w r3, r3, r5, lsl #0x8
	ldrh r5, [r1, #0x2]
	orr.w r3, r3, r5, lsl #0x8
	ldr r5, .L0800c568               @ r5 = 0x40012c00
	cmp r0, r5
	beq.n .L0800c538
	ldr r5, .L0800c56c               @ r5 = 0x40013400
	cmp r0, r5
	bne.n .L0800c55c
.L0800c538:
	ldrh r5, [r1, #0xa]
	bic r3, r3, #0x800
	orr.w r3, r3, r5, lsl #0x8
	ldrh r5, [r1, #0x4]
	bic r3, r3, #0x400
	orr.w r3, r3, r5, lsl #0x8
	ldrh r5, [r1, #0xc]
	bic r2, r2, #0x3000
	orr.w r2, r2, r5, lsl #0x4
	ldrh r5, [r1, #0xe]
	orr.w r2, r2, r5, lsl #0x4
.L0800c55c:
	str r2, [r0, #0x4]
	strh r4, [r0, #0x1c]
	ldrh r1, [r1, #0x6]
	strh r1, [r0, #0x3c]
	str r3, [r0, #0x20]
	pop {r4, r5, pc}
.L0800c568:
	.word 0x40012c00
.L0800c56c:
	.word 0x40013400

@ ----------------------------------------------------------------------------
@ init_eleven_field_record - store default values into a record.
@ r0 = pointer to a record.
@ Stores halfword 0xffff at offset 4, 0 at offsets 0, 2 and 6, and bytes 0 at
@ offsets 8, 9, 10, 11, 12, 13 and 14.
@ ----------------------------------------------------------------------------
	.section .text.init_eleven_field_record,"ax",%progbits
	.p2align 2
	.global init_eleven_field_record
	.thumb_func
	.type init_eleven_field_record, %function
init_eleven_field_record:
	movw r1, #0xffff
	strh r1, [r0, #0x4]
	movs r1, #0x0
	strh r1, [r0, #0x0]
	strh r1, [r0, #0x6]
	strh r1, [r0, #0x2]
	strb r1, [r0, #0x8]
	strb r1, [r0, #0x9]
	strb r1, [r0, #0xa]
	strb r1, [r0, #0xb]
	strb r1, [r0, #0xc]
	strb r1, [r0, #0xd]
	strb r1, [r0, #0xe]
	bx lr
	.short 0x0000                    @ padding

@ ----------------------------------------------------------------------------
@ fn_0800c590 - write the base configuration of a timer-like peripheral.
@ r0 = peripheral base address, r1 = pointer to a configuration record.
@ Builds the control word at r0 from r1 halfwords: halfword 1 (mask
@ 0xffffff8f) for the bases 0x40012c00, 0x40013400, 0x40000000, 0x40000400,
@ 0x40000800, 0x40000c00; halfword 3 (mask 0xfffffcff) except for 0x40001000
@ and 0x40001400.
@ Stores halfword 2 to r0 + 0x2c and halfword 0 to r0 + 0x28, the byte at
@ r1 + 8 to r0 + 0x30 for 0x40012c00 and 0x40013400, and 1 to r0 + 0x14.
@ The bytes of r1 at offsets 9, 10, 11 and 12, 13 and 14 set or clear the
@ bits 0x800, 0x1000, 0x2000, 0x4000, 0x8000 depending on the base.
@ Writes the control word, and for 0x40000000 and 0x40000800 sets or clears
@ bit 0x100 of the word r0 + 4 from the byte at offset 14.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c590,"ax",%progbits
	.p2align 2
	.global fn_0800c590
	.thumb_func
	.type fn_0800c590, %function
fn_0800c590:
	push {r4, r5, r6, r7, lr}
	ldr r2, [r0, #0x0]               @ control word
	ldr r5, .L0800c6cc               @ r5 = 0x40000400
	ldr r4, .L0800c6c0               @ r4 = 0x40012c00
	ldr r6, .L0800c6c4               @ r6 = 0x40013400
	ldr.w r12, .L0800c6c8            @ r12 = 0x40000c00
	lsls r7, r5, #0x14               @ r7 = 0x40000000
	ldr r3, .L0800c6d0               @ r3 = 0x40000800
	cmp r0, r4
	beq.n .L0800c5ba
	cmp r0, r6
	beq.n .L0800c5ba
	cmp r0, r7
	beq.n .L0800c5ba
	cmp r0, r5
	beq.n .L0800c5ba
	cmp r0, r3
	beq.n .L0800c5ba
	cmp r0, r12
	bne.n .L0800c5c4
.L0800c5ba:
	bic lr, r2, #0x70
	ldrh r2, [r1, #0x2]
	orr.w r2, r2, lr
.L0800c5c4:
	ldr.w lr, .L0800c6d4             @ lr = 0x40001000
	cmp r0, lr
	beq.n .L0800c5de
	ldr.w lr, .L0800c6d8             @ lr = 0x40001400
	cmp r0, lr
	beq.n .L0800c5de
	bic lr, r2, #0x300
	ldrh r2, [r1, #0x6]
	orr.w r2, r2, lr
.L0800c5de:
	str r2, [r0, #0x0]
	ldrh r2, [r1, #0x4]
	strh r2, [r0, #0x2c]
	ldrh r2, [r1, #0x0]
	strh r2, [r0, #0x28]
	cmp r0, r4
	beq.n .L0800c5f0
	cmp r0, r6
	bne.n .L0800c5f4
.L0800c5f0:
	ldrb r2, [r1, #0x8]
	strh r2, [r0, #0x30]
.L0800c5f4:
	movs r2, #0x1
	strh r2, [r0, #0x14]
	ldr r2, [r0, #0x0]
	cmp r0, r4
	beq.n .L0800c612
	cmp r0, r6
	beq.n .L0800c612
	cmp r0, r7
	beq.n .L0800c612
	cmp r0, r5
	beq.n .L0800c612
	cmp r0, r3
	beq.n .L0800c612
	cmp r0, r12
	bne.n .L0800c62a
.L0800c612:
	ldrb.w lr, [r1, #0x9]
	cmp.w lr, #0x0
	beq.n .L0800c622
	orr r2, r2, #0x800
	b.n .L0800c626
.L0800c622:
	bic r2, r2, #0x800
.L0800c626:
	cmp r0, r7
	beq.n .L0800c636
.L0800c62a:
	cmp r0, r5
	beq.n .L0800c636
	cmp r0, r3
	beq.n .L0800c636
	cmp r0, r12
	bne.n .L0800c662
.L0800c636:
	ldrb.w r12, [r1, #0xa]
	cmp.w r12, #0x0
	beq.n .L0800c646
	orr r2, r2, #0x1000
	b.n .L0800c64a
.L0800c646:
	bic r2, r2, #0x1000
.L0800c64a:
	ldrb.w r12, [r1, #0xb]
	cmp.w r12, #0x0
	beq.n .L0800c65a
	orr r2, r2, #0x2000
	b.n .L0800c65e
.L0800c65a:
	bic r2, r2, #0x2000
.L0800c65e:
	cmp r0, r7
	beq.n .L0800c66a
.L0800c662:
	cmp r0, r5
	beq.n .L0800c66a
	cmp r0, r3
	bne.n .L0800c67e
.L0800c66a:
	ldrb.w r12, [r1, #0xc]
	cmp.w r12, #0x0
	beq.n .L0800c67a
	orr r2, r2, #0x4000
	b.n .L0800c67e
.L0800c67a:
	bic r2, r2, #0x4000
.L0800c67e:
	cmp r0, r4
	beq.n .L0800c692
	cmp r0, r6
	beq.n .L0800c692
	cmp r0, r7
	beq.n .L0800c692
	cmp r0, r5
	beq.n .L0800c692
	cmp r0, r3
	bne.n .L0800c6a0
.L0800c692:
	ldrb r4, [r1, #0xd]
	cbz r4, .L0800c69c
	orr r2, r2, #0x8000
	b.n .L0800c6a0
.L0800c69c:
	bic r2, r2, #0x8000
.L0800c6a0:
	str r2, [r0, #0x0]
	ldr r2, [r0, #0x4]
	cmp r0, r7
	beq.n .L0800c6ac
	cmp r0, r3
	bne.n .L0800c6ba
.L0800c6ac:
	ldrb r1, [r1, #0xe]
	cbz r1, .L0800c6b6
	orr r2, r2, #0x100
	b.n .L0800c6ba
.L0800c6b6:
	bic r2, r2, #0x100
.L0800c6ba:
	str r2, [r0, #0x4]
	pop {r4, r5, r6, r7, pc}
	.short 0x0000                    @ padding
.L0800c6c0:
	.word 0x40012c00
.L0800c6c4:
	.word 0x40013400
.L0800c6c8:
	.word 0x40000c00
.L0800c6cc:
	.word 0x40000400
.L0800c6d0:
	.word 0x40000800
.L0800c6d4:
	.word 0x40001000
.L0800c6d8:
	.word 0x40001400

@ ----------------------------------------------------------------------------
@ fn_0800c6dc - replace bits 4..6 of the word at base + 4.
@ r0 = base address, r1 = bits.
@ Word at r0 + 4 = (word & 0xffffff8f), stored; then the word | r1, stored.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c6dc,"ax",%progbits
	.p2align 2
	.global fn_0800c6dc
	.thumb_func
	.type fn_0800c6dc, %function
fn_0800c6dc:
	ldr r2, [r0, #0x4]
	bic r2, r2, #0x70
	str r2, [r0, #0x4]
	ldr r2, [r0, #0x4]
	orrs r2, r1
	str r2, [r0, #0x4]
	bx lr

@ ----------------------------------------------------------------------------
@ fn_0800c6ec - store a halfword at base + 0x38.
@ r0 = base address, r1 = value.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c6ec,"ax",%progbits
	.p2align 2
	.global fn_0800c6ec
	.thumb_func
	.type fn_0800c6ec, %function
fn_0800c6ec:
	strh r1, [r0, #0x38]
	bx lr

@ ----------------------------------------------------------------------------
@ set_or_clear_halfword_bit_13 - set or clear bit 13 of the halfword at
@ base + 0xc.
@ r0 = base address, r1 = flag.
@ Sets bit 0x2000 when r1 is non-zero, clears it otherwise.
@ ----------------------------------------------------------------------------
	.section .text.set_or_clear_halfword_bit_13,"ax",%progbits
	.p2align 2
	.global set_or_clear_halfword_bit_13
	.thumb_func
	.type set_or_clear_halfword_bit_13, %function
set_or_clear_halfword_bit_13:
	cmp r1, #0x0
	ldrh r1, [r0, #0xc]
	beq.n .L0800fa70
	orr r1, r1, #0x2000
	b.n .L0800fa74
.L0800fa70:
	bic r1, r1, #0x2000
.L0800fa74:
	strh r1, [r0, #0xc]
	bx lr

@ ----------------------------------------------------------------------------
@ test_halfword_bits - test bits of a halfword.
@ r0 = pointer to a halfword, r1 = mask; returns 1 when (halfword & r1) is
@ non-zero, otherwise 0.
@ ----------------------------------------------------------------------------
	.section .text.test_halfword_bits,"ax",%progbits
	.p2align 2
	.global test_halfword_bits
	.thumb_func
	.type test_halfword_bits, %function
test_halfword_bits:
	mov r2, r0
	movs r0, #0x0
	ldrh r2, [r2, #0x0]
	tst r2, r1
	beq.n .L0800fa84
	movs r0, #0x1
.L0800fa84:
	bx lr
	.short 0x0000                    @ padding

@ ----------------------------------------------------------------------------
@ fn_0800fa88 - set up a serial-style peripheral from a record.
@ r0 = base address, r1 = pointer to words (word 0 = divisor, then halfword
@ fields); no return value.
@ Halfword at r0 + 0x10 = halfword at r1 + 6 | (old & 0xcfff); halfword at
@ r0 + 0xc = halfword at r1 + 4 | halfword at r1 + 8 | halfword at r1 + 10 |
@ (old & 0xe9f3); halfword at r0 + 0x14 = halfword at r1 + 12 | (old &
@ 0xfcff).
@ Calls fn_0800b364 with a 28-byte stack buffer and takes clock word 3 (stack
@ offset 0xc), or word 2 (stack offset 8) unless r0 is 0x40013800,
@ 0x40015000 or 0x40015400.
@ q = (clock * 0x19) / (word 0 of r1 << 2); halfword at r0 + 8 = ((((q %
@ 100) * 16 + 0x32) / 100) & 0xf) | ((q / 100) << 4), with the quotient carry
@ (value 0x10 added to the integer part) when that rounded fraction reaches
@ 0x10.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fa88,"ax",%progbits
	.p2align 2
	.global fn_0800fa88
	.thumb_func
	.type fn_0800fa88, %function
fn_0800fa88:
	push {r4, r5, lr}
	mov r4, r0
	ldrh r0, [r0, #0x10]
	sub sp, #0x1c
	mov r5, r1
	movw r1, #0xcfff
	ands r0, r1
	ldrh r1, [r5, #0x6]
	orrs r1, r0
	strh r1, [r4, #0x10]
	ldrh r1, [r4, #0xc]
	movw r0, #0xe9f3
	ands r1, r0
	ldrh r0, [r5, #0x4]
	ldrh r2, [r5, #0x8]
	orrs r0, r2
	ldrh r2, [r5, #0xa]
	orrs r2, r1
	orrs r0, r2
	strh r0, [r4, #0xc]
	ldrh r0, [r4, #0x14]
	movw r1, #0xfcff
	ands r0, r1
	ldrh r1, [r5, #0xc]
	orrs r1, r0
	strh r1, [r4, #0x14]
	mov r0, sp
	bl fn_0800b364
	ldr r0, .L0800fb2c              @ r0 = 0x40013800
	cmp r4, r0
	beq.n .L0800fada
	ldr r1, .L0800fb30              @ r1 = 0x40015000
	cmp r4, r1
	beq.n .L0800fada
	ldr r1, .L0800fb34              @ r1 = 0x40015400
	cmp r4, r1
	bne.n .L0800fade
.L0800fada:
	ldr r0, [sp, #0xc]
	b.n .L0800fae0
.L0800fade:
	ldr r0, [sp, #0x8]
.L0800fae0:
	movs r2, #0x64
	add.w r1, r0, r0, lsl #0x3
	add.w r0, r1, r0, lsl #0x4       @ r0 = clock * 0x19
	ldr r1, [r5, #0x0]
	mvn r5, #0x18                    @ r5 = -0x19
	lsls r1, r1, #0x2
	udiv r1, r0, r1                  @ q
	udiv r0, r1, r2                  @ q / 100
	lsls r0, r0, #0x4
	lsrs r3, r0, #0x4
	muls r3, r5, r3                  @ -0x19 * (q / 100)
	add.w r3, r1, r3, lsl #0x2       @ q - 100 * (q / 100) = q % 100
	movs r5, #0x32
	add.w r3, r5, r3, lsl #0x4
	udiv r3, r3, r2                  @ rounded fraction
	movs r5, #0x1
	cmp.w r5, r3, lsr #0x4
	bne.n .L0800fb1e
	udiv r0, r1, r2
	lsls r0, r0, #0x4
	adds r0, #0x10
.L0800fb1e:
	and r1, r3, #0xf
	orrs r1, r0
	strh r1, [r4, #0x8]
	add sp, #0x1c
	pop {r4, r5, pc}
	.short 0x0000                    @ padding
.L0800fb2c:
	.word 0x40013800
.L0800fb30:
	.word 0x40015000
.L0800fb34:
	.word 0x40015400

@ ----------------------------------------------------------------------------
@ fn_0800fb38 - store the low 9 bits of r1 as a halfword at base + 4.
@ r0 = base address, r1 = value.
@ Halfword at r0 + 4 = r1 & 0x1ff.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fb38,"ax",%progbits
	.p2align 2
	.global fn_0800fb38
	.thumb_func
	.type fn_0800fb38, %function
fn_0800fb38:
	ubfx r1, r1, #0x0, #0x9
	strh r1, [r0, #0x4]
	bx lr

@ ----------------------------------------------------------------------------
@ fn_0800fb40 - write 0x40000 to the word 0x40010414.
@ No parameters. Loads 0x40000 into r0 and tail-jumps to
@ write_word_40010414.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800fb40,"ax",%progbits
	.p2align 2
	.global fn_0800fb40
	.thumb_func
	.type fn_0800fb40, %function
fn_0800fb40:
	mov.w r0, #0x40000
	b.w write_word_40010414

@ ----------------------------------------------------------------------------
@ fn_08010174 - tail jump to fn_08009390.
@ No parameters. The instruction is b.w to fn_08009390, which stores 0xaaaa
@ to the word 0x40003000.
@ ----------------------------------------------------------------------------
	.section .text.fn_08010174,"ax",%progbits
	.p2align 2
	.global fn_08010174
	.thumb_func
	.type fn_08010174, %function
fn_08010174:
	b.w fn_08009390

@ ----------------------------------------------------------------------------
@ fn_08010178 - run a fixed sequence of stores to the word block at
@ 0x40003000.
@ No parameters. Calls fn_080093ac(0x5555), fn_080093a0(2),
@ fn_08009374(0x9c4), fn_08009390(), then tail-jumps to
@ store_0xcccc_at_40003000.
@ ----------------------------------------------------------------------------
	.section .text.fn_08010178,"ax",%progbits
	.p2align 2
	.global fn_08010178
	.thumb_func
	.type fn_08010178, %function
fn_08010178:
	push {r4, lr}
	movw r0, #0x5555
	bl fn_080093ac
	movs r0, #0x2
	bl fn_080093a0
	movw r0, #0x9c4
	bl fn_08009374
	bl fn_08009390
	pop.w {r4, lr}
	b.w store_0xcccc_at_40003000

@ ----------------------------------------------------------------------------
@ set_or_clear_bit_0_0801026c - set or clear bit 0 of a word.
@ r0 = pointer to a word, r1 = flag.
@ Sets bit 0 of the word when r1 is non-zero, clears it otherwise.
@ ----------------------------------------------------------------------------
	.section .text.set_or_clear_bit_0_0801026c,"ax",%progbits
	.p2align 2
	.global set_or_clear_bit_0_0801026c
	.thumb_func
	.type set_or_clear_bit_0_0801026c, %function
set_or_clear_bit_0_0801026c:
	cmp r1, #0x0
	ldr r1, [r0, #0x0]
	beq.n .L08010278
	orr r1, r1, #0x1
	b.n .L0801027c
.L08010278:
	bic r1, r1, #0x1
.L0801027c:
	str r1, [r0, #0x0]
	bx lr

@ ----------------------------------------------------------------------------
@ fn_08010280 - write a register block from a record of bit fields.
@ r0 = pointer to a record (word 0 = base address, words 1..12 = bit fields,
@ words 0xd and 0xe = pointers to field lists); no return value.
@ Writes the OR of the words 1..12 to the word at the base, ors 0x40 when
@ word 2 is 8.
@ Writes the OR of the first 7 words of the list at word 0xd to base + 4.
@ When word 0xb equals 0x4000 it writes (list 0xe words 0, 1, 4, 5, 6 and
@ word 2 << 8, ored) to base + 0x104, otherwise it writes 0xfffffff to
@ base + 0x104.
@ ----------------------------------------------------------------------------
	.section .text.fn_08010280,"ax",%progbits
	.p2align 2
	.global fn_08010280
	.thumb_func
	.type fn_08010280, %function
fn_08010280:
	push {r4, lr}
	ldrd r1, r2, [r0, #0x4]
	orrs r1, r2
	ldrd r2, r3, [r0, #0xc]
	orrs r2, r3
	orrs r1, r2
	ldr r2, [r0, #0x14]
	orrs r1, r2
	ldr r2, [r0, #0x18]
	orrs r1, r2
	ldr r2, [r0, #0x1c]
	orrs r1, r2
	ldr r2, [r0, #0x20]
	orrs r1, r2
	ldr r2, [r0, #0x24]
	orrs r1, r2
	ldr r2, [r0, #0x28]
	orrs r1, r2
	ldr r2, [r0, #0x2c]
	orrs r1, r2
	ldr r2, [r0, #0x30]
	orrs r1, r2
	ldr r2, [r0, #0x0]
	str r1, [r2, #0x0]
	ldr r1, [r0, #0x8]
	cmp r1, #0x8
	bne.n .L080102c4
	ldr r1, [r0, #0x0]
	ldr r2, [r1, #0x0]
	orr r2, r2, #0x40
	str r2, [r1, #0x0]
.L080102c4:
	ldr r1, [r0, #0x34]              @ list of word 0xd
	ldrd r2, r3, [r1, #0x0]
	orrs r2, r3
	ldrd r3, r4, [r1, #0x8]
	orrs r3, r4
	orrs r2, r3
	ldr r3, [r1, #0x10]
	orrs r2, r3
	ldr r3, [r1, #0x14]
	ldr r1, [r1, #0x18]
	orrs r2, r3
	orrs r2, r1
	ldr r1, [r0, #0x0]
	str r2, [r1, #0x4]
	ldr r1, [r0, #0x2c]              @ word 0xb
	cmp.w r1, #0x4000
	beq.n .L080102f8
	ldr r0, [r0, #0x0]
	mvn r1, #0xf0000000              @ r1 = 0x0fffffff
	str.w r1, [r0, #0x104]
	pop {r4, pc}
.L080102f8:
	ldr r1, [r0, #0x38]              @ list of word 0xe
	ldrd r2, r3, [r1, #0x0]
	orrs r2, r3
	ldr r4, [r1, #0x8]
	ldr r3, [r1, #0x10]
	ldr r0, [r0, #0x0]
	orr.w r3, r3, r4, lsl #0x8
	orrs r2, r3
	ldr r3, [r1, #0x14]
	ldr r1, [r1, #0x18]
	orrs r2, r3
	orrs r2, r1
	str.w r2, [r0, #0x104]
	pop {r4, pc}
	.short 0x0000                    @ padding

@ ----------------------------------------------------------------------------
@ set_word_20000578 - store r0 to the word at 0x20000578.
@ r0 = value; no return value.
@ ----------------------------------------------------------------------------
	.section .text.set_word_20000578,"ax",%progbits
	.p2align 2
	.global set_word_20000578
	.thumb_func
	.type set_word_20000578, %function
set_word_20000578:
	ldr r1, .L08011c64
	str r0, [r1, #0x0]
	bx lr
	.short 0x0000                    @ padding
.L08011c64:
	.word 0x20000578

@ ----------------------------------------------------------------------------
@ fn_08011c68 - repeat a wait and a store a number of times.
@ r0 = count; no return value.
@ Repeats count times: calls wait_halfword_40001424_reaches_count(1000
@ (0x3e8)), then calls fn_08009390 (stores 0xaaaa to the word 0x40003000).
@ Returns when the counter underflows (subs r4, r4, #1).
@ ----------------------------------------------------------------------------
	.section .text.fn_08011c68,"ax",%progbits
	.p2align 2
	.global fn_08011c68
	.thumb_func
	.type fn_08011c68, %function
fn_08011c68:
	push {r4, r5, r6, lr}
	mov r4, r0
	mov.w r5, #0x3e8
	b.n .L08011c7c
.L08011c72:
	mov r0, r5
	bl wait_halfword_40001424_reaches_count
	bl fn_08009390
.L08011c7c:
	.inst.n 0x1e64                   @ subs r4, r4, #1
	bcs.n .L08011c72
	pop {r4, r5, r6, pc}
	.short 0x0000                    @ padding

@ ----------------------------------------------------------------------------
@ wait_halfword_40001424_reaches_count - clear a halfword, then wait until it
@ reaches a count.
@ r0 = count; no return value.
@ Writes halfword 0 to 0x40001424, then spins reading the halfword at
@ 0x40001424 until it is no longer below r0 (signed compare).
@ ----------------------------------------------------------------------------
	.section .text.wait_halfword_40001424_reaches_count,"ax",%progbits
	.p2align 2
	.global wait_halfword_40001424_reaches_count
	.thumb_func
	.type wait_halfword_40001424_reaches_count, %function
wait_halfword_40001424_reaches_count:
	ldr r1, .L08011c94
	movs r2, #0x0
	strh r2, [r1, #0x0]
.L08011c8a:
	ldrh r2, [r1, #0x0]
	cmp r2, r0
	blt.n .L08011c8a
	bx lr
	.short 0x0000                    @ padding
.L08011c94:
	.word 0x40001424
