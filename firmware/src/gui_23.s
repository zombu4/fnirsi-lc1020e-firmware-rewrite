@ gui_23.s - GUI object accessors (key lookups through fn_08024bac) and the rectangle transform
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08024c40 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0xb and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024c40,"ax",%progbits
	.p2align 2
	.global fn_08024c40
	.thumb_func
	.type fn_08024c40, %function
fn_08024c40:
	push	{r4, lr}
	movs	r2, #0xb		@ key 0xb
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024c4c - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x41 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024c4c,"ax",%progbits
	.p2align 2
	.global fn_08024c4c
	.thumb_func
	.type fn_08024c4c, %function
fn_08024c4c:
	push	{r4, lr}
	movs	r2, #0x41		@ key 0x41
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024c58 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x42 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024c58,"ax",%progbits
	.p2align 2
	.global fn_08024c58
	.thumb_func
	.type fn_08024c58, %function
fn_08024c58:
	push	{r4, lr}
	movs	r2, #0x42		@ key 0x42
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024c64 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x45 and returns the low byte of
@ its result (zero-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024c64,"ax",%progbits
	.p2align 2
	.global fn_08024c64
	.thumb_func
	.type fn_08024c64, %function
fn_08024c64:
	push	{r4, lr}
	movs	r2, #0x45		@ key 0x45
	bl	fn_08024bac
	uxtb	r0, r0			@ low byte of the result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024c70 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x43 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024c70,"ax",%progbits
	.p2align 2
	.global fn_08024c70
	.thumb_func
	.type fn_08024c70, %function
fn_08024c70:
	push	{r4, lr}
	movs	r2, #0x43		@ key 0x43
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024c7c - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x40 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024c7c,"ax",%progbits
	.p2align 2
	.global fn_08024c7c
	.thumb_func
	.type fn_08024c7c, %function
fn_08024c7c:
	push	{r4, lr}
	movs	r2, #0x40		@ key 0x40
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024c88 - r0 = object, r1 = second argument.
@ Reads key 0x55 with fn_08024bac (0x08024bac), then tail-calls fn_08012786
@ (0x08012786) with r0 = object, r1 = second argument, r2 = the value read.
@ Callers 0x0802501a and 0x0802516e use the returned 16-bit value.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024c88,"ax",%progbits
	.global fn_08024c88
	.thumb_func
	.type fn_08024c88, %function
fn_08024c88:
	push	{r4, r5, r6, lr}
	mov	r4, r1			@ keep second argument
	mov	r5, r0			@ keep object
	movs	r2, #0x55		@ key 0x55
	bl	fn_08024bac
	mov	r2, r0			@ value read becomes the third argument
	mov	r1, r4
	mov	r0, r5
	pop.w	{r4, r5, r6, lr}
	b.w	fn_08012786

@ ----------------------------------------------------------------------------
@ fn_08024ca2 - r0 = object, r1 = second argument of fn_08024bac.
@ Tail-calls fn_08024bac (0x08024bac) with key 0x57; returns r0 as left by
@ fn_08024bac (no conversion).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024ca2,"ax",%progbits
	.global fn_08024ca2
	.thumb_func
	.type fn_08024ca2, %function
fn_08024ca2:
	movs	r2, #0x57		@ key 0x57
	b.w	fn_08024bac

@ ----------------------------------------------------------------------------
@ fn_08024ca8 - r0 = object, r1 = second argument of fn_08024bac.
@ Tail-calls fn_08024bac (0x08024bac) with key 0x57; returns r0 as left by
@ fn_08024bac (no conversion).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024ca8,"ax",%progbits
	.global fn_08024ca8
	.thumb_func
	.type fn_08024ca8, %function
fn_08024ca8:
	movs	r2, #0x57		@ key 0x57
	b.w	fn_08024bac

@ ----------------------------------------------------------------------------
@ fn_08024cae - r0 = object, r1 = second argument of fn_08024bac.
@ Tail-calls fn_08024bac (0x08024bac) with key 0x57; returns r0 as left by
@ fn_08024bac (no conversion).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024cae,"ax",%progbits
	.global fn_08024cae
	.thumb_func
	.type fn_08024cae, %function
fn_08024cae:
	movs	r2, #0x57		@ key 0x57
	b.w	fn_08024bac

@ ----------------------------------------------------------------------------
@ fn_08024cb4 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x58 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024cb4,"ax",%progbits
	.p2align 2
	.global fn_08024cb4
	.thumb_func
	.type fn_08024cb4, %function
fn_08024cb4:
	push	{r4, lr}
	movs	r2, #0x58		@ key 0x58
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024cc0 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x58 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024cc0,"ax",%progbits
	.p2align 2
	.global fn_08024cc0
	.thumb_func
	.type fn_08024cc0, %function
fn_08024cc0:
	push	{r4, lr}
	movs	r2, #0x58		@ key 0x58
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024ccc - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x59 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024ccc,"ax",%progbits
	.p2align 2
	.global fn_08024ccc
	.thumb_func
	.type fn_08024ccc, %function
fn_08024ccc:
	push	{r4, lr}
	movs	r2, #0x59		@ key 0x59
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024cd8 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x59 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024cd8,"ax",%progbits
	.p2align 2
	.global fn_08024cd8
	.thumb_func
	.type fn_08024cd8, %function
fn_08024cd8:
	push	{r4, lr}
	movs	r2, #0x59		@ key 0x59
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024ce4 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x69 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024ce4,"ax",%progbits
	.p2align 2
	.global fn_08024ce4
	.thumb_func
	.type fn_08024ce4, %function
fn_08024ce4:
	push	{r4, lr}
	movs	r2, #0x69		@ key 0x69
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024cf0 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x68 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024cf0,"ax",%progbits
	.p2align 2
	.global fn_08024cf0
	.thumb_func
	.type fn_08024cf0, %function
fn_08024cf0:
	push	{r4, lr}
	movs	r2, #0x68		@ key 0x68
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024cfc - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x1 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024cfc,"ax",%progbits
	.p2align 2
	.global fn_08024cfc
	.thumb_func
	.type fn_08024cfc, %function
fn_08024cfc:
	push	{r4, lr}
	movs	r2, #0x1		@ key 0x1
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024d08 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x1 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024d08,"ax",%progbits
	.p2align 2
	.global fn_08024d08
	.thumb_func
	.type fn_08024d08, %function
fn_08024d08:
	push	{r4, lr}
	movs	r2, #0x1		@ key 0x1
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024d14 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x1 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024d14,"ax",%progbits
	.p2align 2
	.global fn_08024d14
	.thumb_func
	.type fn_08024d14, %function
fn_08024d14:
	push	{r4, lr}
	movs	r2, #0x1		@ key 0x1
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024d20 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x1 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024d20,"ax",%progbits
	.p2align 2
	.global fn_08024d20
	.thumb_func
	.type fn_08024d20, %function
fn_08024d20:
	push	{r4, lr}
	movs	r2, #0x1		@ key 0x1
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024d2c - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x1 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024d2c,"ax",%progbits
	.p2align 2
	.global fn_08024d2c
	.thumb_func
	.type fn_08024d2c, %function
fn_08024d2c:
	push	{r4, lr}
	movs	r2, #0x1		@ key 0x1
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024d38 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x7 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024d38,"ax",%progbits
	.p2align 2
	.global fn_08024d38
	.thumb_func
	.type fn_08024d38, %function
fn_08024d38:
	push	{r4, lr}
	movs	r2, #0x7		@ key 0x7
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024d44 - r0 = object, r1 = second argument of fn_08024bac.
@ Calls fn_08024bac (0x08024bac) with key 0x8 and returns its result as a
@ signed 16-bit value (sign-extended).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024d44,"ax",%progbits
	.p2align 2
	.global fn_08024d44
	.thumb_func
	.type fn_08024d44, %function
fn_08024d44:
	push	{r4, lr}
	movs	r2, #0x8		@ key 0x8
	bl	fn_08024bac
	sxth	r0, r0			@ signed 16-bit result
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_08024d50 - r0 = object, r1 = pointer to a rectangle (x1, y1, x2, y2 as
@ four halfwords), r2 and r3 passed on unchanged.
@ Copies the four corner points (x1,y1), (x1,y2), (x2,y1) and (x2,y2) to a
@ 16-byte stack area, passes each through fn_08026762 (0x08026762) together
@ with the object, then writes the minimum and maximum of x and of y over the
@ four results back into the rectangle (offsets 0 and 4 = x min and max,
@ 2 and 6 = y min and max). Ends with a tail call of rect_grow (0x0801d082)
@ with the rectangle and 5. Registers kept: r7 = object, r4 = rectangle,
@ r6 = r2, r5 = r3.
@ ----------------------------------------------------------------------------
	.section .text.fn_08024d50,"ax",%progbits
	.global fn_08024d50
	.thumb_func
	.type fn_08024d50, %function
fn_08024d50:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, lr}
	mov	r7, r0
	ldrh	r0, [r1, #0x0]
	strh.w	r0, [sp, #0x0]		@ corner 0: x1
	ldrh	r0, [r1, #0x2]
	strh.w	r0, [sp, #0x2]		@ corner 0: y1
	ldrh	r0, [r1, #0x0]
	strh.w	r0, [sp, #0x4]		@ corner 1: x1
	ldrh	r0, [r1, #0x6]
	strh.w	r0, [sp, #0x6]		@ corner 1: y2
	ldrh	r0, [r1, #0x4]
	strh.w	r0, [sp, #0x8]		@ corner 2: x2
	ldrh	r0, [r1, #0x2]
	mov	r4, r1
	strh.w	r0, [sp, #0xa]		@ corner 2: y1
	ldrh	r0, [r4, #0x4]
	strh.w	r0, [sp, #0xc]		@ corner 3: x2
	ldrh	r0, [r4, #0x6]
	strh.w	r0, [sp, #0xe]		@ corner 3: y2
	mov	r5, r3
	mov	r6, r2
	mov	r1, sp
	mov	r0, r7
	bl	fn_08026762		@ transform corner 0
	mov	r3, r5
	mov	r2, r6
	mov	r0, r7
	add	r1, sp, #0x4
	bl	fn_08026762		@ transform corner 1
	mov	r3, r5
	mov	r2, r6
	mov	r0, r7
	add	r1, sp, #0x8
	bl	fn_08026762		@ transform corner 2
	mov	r3, r5
	mov	r2, r6
	mov	r0, r7
	add	r1, sp, #0xc
	bl	fn_08026762		@ transform corner 3
	@ minimum x of the four corners -> rectangle offset 0
	ldrsh.w	r3, [sp, #0x0]
	ldrsh.w	r0, [sp, #0x4]
	cmp	r3, r0
	bge	.L08024dc8
	mov	r5, r3
	b	.L08024dca
.L08024dc8:
	mov	r5, r0
.L08024dca:
	ldrsh.w	r1, [sp, #0x8]
	ldrsh.w	r2, [sp, #0xc]
	cmp	r1, r2
	bge	.L08024dda
	mov	r6, r1
	b	.L08024ddc
.L08024dda:
	mov	r6, r2
.L08024ddc:
	cmp	r5, r6
	bge	.L08024dec
	cmp	r3, r0
	bge	.L08024de8
	mov	r2, r3
	b	.L08024df2
.L08024de8:
	mov	r2, r0
	b	.L08024df2
.L08024dec:
	cmp	r1, r2
	bge	.L08024df2
	mov	r2, r1
.L08024df2:
	strh	r2, [r4, #0x0]
	@ maximum x of the four corners -> rectangle offset 4
	ldrsh.w	r3, [sp, #0x0]
	ldrsh.w	r1, [sp, #0x4]
	cmp	r3, r1
	ble	.L08024e04
	mov	r5, r3
	b	.L08024e06
.L08024e04:
	mov	r5, r1
.L08024e06:
	ldrsh.w	r0, [sp, #0x8]
	ldrsh.w	r2, [sp, #0xc]
	cmp	r0, r2
	ble	.L08024e16
	mov	r6, r0
	b	.L08024e18
.L08024e16:
	mov	r6, r2
.L08024e18:
	cmp	r5, r6
	ble	.L08024e28
	cmp	r3, r1
	ble	.L08024e24
	mov	r2, r3
	b	.L08024e2e
.L08024e24:
	mov	r2, r1
	b	.L08024e2e
.L08024e28:
	cmp	r0, r2
	ble	.L08024e2e
	mov	r2, r0
.L08024e2e:
	strh	r2, [r4, #0x4]
	@ minimum y of the four corners -> rectangle offset 2
	ldrsh.w	r3, [sp, #0x2]
	ldrsh.w	r2, [sp, #0x6]
	cmp	r3, r2
	bge	.L08024e40
	mov	r5, r3
	b	.L08024e42
.L08024e40:
	mov	r5, r2
.L08024e42:
	ldrsh.w	r1, [sp, #0xa]
	ldrsh.w	r0, [sp, #0xe]
	cmp	r1, r0
	bge	.L08024e52
	mov	r6, r1
	b	.L08024e54
.L08024e52:
	mov	r6, r0
.L08024e54:
	cmp	r5, r6
	bge	.L08024e64
	cmp	r3, r2
	bge	.L08024e60
	mov	r0, r3
	b	.L08024e6a
.L08024e60:
	mov	r0, r2
	b	.L08024e6a
.L08024e64:
	cmp	r1, r0
	bge	.L08024e6a
	mov	r0, r1
.L08024e6a:
	strh	r0, [r4, #0x2]
	@ maximum y of the four corners -> rectangle offset 6
	ldrsh.w	r3, [sp, #0x2]
	ldrsh.w	r1, [sp, #0x6]
	cmp	r3, r1
	ble	.L08024e7c
	mov	r5, r3
	b	.L08024e7e
.L08024e7c:
	mov	r5, r1
.L08024e7e:
	ldrsh.w	r0, [sp, #0xa]
	ldrsh.w	r2, [sp, #0xe]
	cmp	r0, r2
	ble	.L08024e8e
	mov	r6, r0
	b	.L08024e90
.L08024e8e:
	mov	r6, r2
.L08024e90:
	cmp	r5, r6
	ble	.L08024ea0
	cmp	r3, r1
	ble	.L08024e9c
	mov	r0, r3
	b	.L08024ea6
.L08024e9c:
	mov	r0, r1
	b	.L08024ea6
.L08024ea0:
	cmp	r0, r2
	bgt	.L08024ea6
	mov	r0, r2
.L08024ea6:
	strh	r0, [r4, #0x6]
	movs	r2, #0x5		@ r2 = 5
	mov	r1, r2			@ r1 = 5
	mov	r0, r4			@ r0 = rectangle
	bl	rect_grow		@ rect_grow (0x0801d082) with (rectangle, 5)
	pop.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ rect_width_plus_one - r0 = object. Returns the signed 16-bit value
@ halfword(object+0x18) - halfword(object+0x14) + 1.
@ ----------------------------------------------------------------------------
	.section .text.rect_width_plus_one,"ax",%progbits
	.global rect_width_plus_one
	.thumb_func
	.type rect_width_plus_one, %function
rect_width_plus_one:
	ldrh	r1, [r0, #0x18]
	ldrh	r0, [r0, #0x14]
	subs	r0, r1, r0
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth	r0, r0			@ signed 16-bit result
	bx	lr

@ ----------------------------------------------------------------------------
@ all_flag_bits_set - r0 = object, r1 = mask. Returns 1 when every bit of the
@ mask is set in the word at object+0x1c (mask & ~word == 0), else 0.
@ ----------------------------------------------------------------------------
	.section .text.all_flag_bits_set,"ax",%progbits
	.global all_flag_bits_set
	.thumb_func
	.type all_flag_bits_set, %function
all_flag_bits_set:
	ldr	r0, [r0, #0x1c]
	bics	r1, r0			@ mask & ~word
	beq.n	.L08024ecc
	movs	r0, #0x0
	bx	lr
.L08024ecc:
	movs	r0, #0x1
	bx	lr

@ ----------------------------------------------------------------------------
@ any_flag_bit_set - r0 = object, r1 = mask. Returns 1 when (word at
@ object+0x1c & mask) is nonzero, else 0.
@ ----------------------------------------------------------------------------
	.section .text.any_flag_bit_set,"ax",%progbits
	.global any_flag_bit_set
	.thumb_func
	.type any_flag_bit_set, %function
any_flag_bit_set:
	ldr	r0, [r0, #0x1c]
	ands	r0, r1			@ word & mask
	beq.n	.L08024ed8
	movs	r0, #0x1
.L08024ed8:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08024eda - r0 = object, r1 = flag, r2 = output record (halfwords),
@ r3 unused; no return value.
@ Reads key 0x50 with fn_08024bac (0x08024bac) into out[1] (halfword at
@ out+2); when nonzero, reads key 0x53 into the byte at out+0xc. When that
@ byte is above 2: with flag nonzero it is scaled by fn_08024a38 (0x08024a38)
@ / 256 (set to 0 and return when fn_08024a38 is below 3; no scaling when it
@ is 0xfd or more). Then stores fn_08012786 (0x08012786) of key 0x52 into
@ out[0], key 0x54 into the word at out+8, bit 2 of the byte at out+0xd from
@ key 0x51 (nonzero -> 1), and with flag nonzero bits 0-1 of that byte from
@ fn_08024968 (0x08024968).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024eda,"ax",%progbits
	.global fn_08024eda
	.thumb_func
	.type fn_08024eda, %function
fn_08024eda:
	push	{r3, r4, r5, r6, r7, lr}
	mov	r5, r2			@ r5 = output record
	mov	r4, r1			@ r4 = flag
	mov	r6, r0			@ r6 = object
	movs	r2, #0x50		@ key 0x50
	bl	fn_08024bac
	sxth	r0, r0
	strh	r0, [r5, #0x2]		@ out[1]
	cmp	r0, #0x0
	beq.n	.L08024f14
	mov	r0, r6
	mov	r1, r4
	movs	r2, #0x53		@ key 0x53
	bl	fn_08024bac
	uxtb	r0, r0
	strb	r0, [r5, #0xc]
	cmp	r0, #0x2
	bls.n	.L08024f14
	cbz	r4, .L08024f24
	mov	r1, r4
	mov	r0, r6
	bl	fn_08024a38
	cmp	r0, #0x2
	bhi.n	.L08024f16
	movs	r0, #0x0
	strb	r0, [r5, #0xc]
.L08024f14:
	pop	{r3, r4, r5, r6, r7, pc}
.L08024f16:
	cmp	r0, #0xfd
	bhs.n	.L08024f24
	ldrb	r1, [r5, #0xc]
	smulbb	r0, r1, r0		@ byte * fn_08024a38 result
	lsrs	r0, r0, #0x8		@ / 256
	strb	r0, [r5, #0xc]
.L08024f24:
	movs	r2, #0x52		@ key 0x52
	mov	r1, r4
	mov	r0, r6
	bl	fn_08024bac
	mov	r2, r0
	mov	r1, r4
	mov	r0, r6
	bl	fn_08012786
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r5, #0x0]		@ out[0]
	mov	r0, r6
	mov	r1, r4
	movs	r2, #0x54		@ key 0x54
	bl	fn_08024bac
	str	r0, [r5, #0x8]
	mov	r0, r6
	mov	r1, r4
	movs	r2, #0x51		@ key 0x51
	bl	fn_08024bac
	cbz	r0, .L08024f5a
	movs	r0, #0x1
.L08024f5a:
	ldrb	r1, [r5, #0xd]
	cmp	r4, #0x0
	bfi	r1, r0, #0x2, #0x1	@ bit 2 = (key 0x51 != 0)
	strb	r1, [r5, #0xd]
	beq.n	.L08024f14
	mov	r1, r4
	mov	r0, r6
	bl	fn_08024968
	ldrb	r1, [r5, #0xd]
	bfi	r1, r0, #0x0, #0x2	@ bits 0-1 = fn_08024968 result
	strb	r1, [r5, #0xd]
	pop	{r3, r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_08024f78 - r0 = object, r1 = flag, r2 = output record (halfwords),
@ r3 unused; no return value.
@ Reads key 0x46 into the byte at out+0xb; returns when it is 2 or below.
@ Otherwise, with flag nonzero, scales it by fn_08024a38 (0x08024a38) / 256
@ (0 and return when that is below 3; no scaling when 0xfd or more).
@ Stores out[0] = 0, out[1] = 0x100, out[2] = width/2 and out[3] = height/2
@ of the object (halfwords object+0x14..0x1a, signed division by 2 rounding
@ toward zero), key 0x48 into the byte at out+0xa and, when that is nonzero,
@ fn_08012786 (0x08012786) of key 0x47 into out[4]; with flag nonzero the
@ byte at out+0xc = fn_08024968 (0x08024968).
@ ----------------------------------------------------------------------------
	.section .text.fn_08024f78,"ax",%progbits
	.global fn_08024f78
	.thumb_func
	.type fn_08024f78, %function
fn_08024f78:
	push	{r3, r4, r5, r6, r7, lr}
	mov	r4, r2			@ r4 = output record
	mov	r6, r1			@ r6 = flag
	mov	r5, r0			@ r5 = object
	movs	r2, #0x46		@ key 0x46
	bl	fn_08024bac
	uxtb	r0, r0
	strb	r0, [r4, #0xb]
	cmp	r0, #0x2
	bls.n	.L08024fa0
	movs	r7, #0x0
	cbz	r6, .L08024fb0
	mov	r1, r6
	mov	r0, r5
	bl	fn_08024a38
	cmp	r0, #0x2
	bhi.n	.L08024fa2
	strb	r7, [r4, #0xb]
.L08024fa0:
	pop	{r3, r4, r5, r6, r7, pc}
.L08024fa2:
	cmp	r0, #0xfd
	bhs.n	.L08024fb0
	ldrb	r1, [r4, #0xb]
	smulbb	r0, r1, r0		@ byte * fn_08024a38 result
	lsrs	r0, r0, #0x8		@ / 256
	strb	r0, [r4, #0xb]
.L08024fb0:
	strh	r7, [r4, #0x0]		@ out[0] = 0
	mov.w	r0, #0x100
	strh	r0, [r4, #0x2]		@ out[1] = 0x100
	ldrh	r0, [r5, #0x18]
	ldrh	r1, [r5, #0x14]
	movs	r2, #0x48		@ key 0x48
	subs	r0, r0, r1
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth	r0, r0
	add.w	r0, r0, r0, lsr #0x1f	@ signed divide by 2: add sign bit,
	asrs	r0, r0, #0x1		@ then arithmetic shift right
	strh	r0, [r4, #0x4]		@ out[2] = width / 2
	ldrh	r0, [r5, #0x1a]
	ldrh	r1, [r5, #0x16]
	subs	r0, r0, r1
	.inst.n 0x1c40			@ adds r0, r0, #1
	sxth	r0, r0
	add.w	r0, r0, r0, lsr #0x1f
	asrs	r0, r0, #0x1
	strh	r0, [r4, #0x6]		@ out[3] = height / 2
	mov	r0, r5
	mov	r1, r6
	bl	fn_08024bac		@ r2 = 0x48 set above
	ands	r0, r0, #0xff
	strb	r0, [r4, #0xa]
	beq.n	.L0802500a
	movs	r2, #0x47		@ key 0x47
	mov	r1, r6
	mov	r0, r5
	bl	fn_08024bac
	mov	r2, r0
	mov	r1, r6
	mov	r0, r5
	bl	fn_08012786
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0x8]		@ out[4]
.L0802500a:
	cmp	r6, #0x0
	beq.n	.L08024fa0
	mov	r1, r6
	mov	r0, r5
	bl	fn_08024968
	strb	r0, [r4, #0xc]
	pop	{r3, r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_0802501a - r0 = object, r1 = flag, r2 = output record, r3 unused; no
@ return value.
@ Reads key 0x56 into the byte at out+0x1a and returns when it is below 3.
@ With flag nonzero scales it by fn_08024a38 (0x08024a38) / 256 (0 and return
@ when that is below 3; no scaling when 0xfd or more).
@ Stores fn_08024c88 (0x08024c88) into the halfword at out+0xc, keys 0x58
@ and 0x59 into the halfwords at out+0x14 and out+0x12, key 0x5a (3 bits)
@ into the byte at out+0x1e (bits 0-2), with flag nonzero fn_08024968
@ (0x08024968) into bits 3-5 of that byte, fn_08024ca8 (0x08024ca8) into the
@ word at out+0, and key 0x5b into the byte at out+0x1c.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802501a,"ax",%progbits
	.global fn_0802501a
	.thumb_func
	.type fn_0802501a, %function
fn_0802501a:
	push	{r3, r4, r5, r6, r7, lr}
	mov	r4, r2			@ r4 = output record
	mov	r5, r1			@ r5 = flag
	mov	r6, r0			@ r6 = object
	movs	r2, #0x56		@ key 0x56
	bl	fn_08024bac
	uxtb	r0, r0
	strb	r0, [r4, #0x1a]
	cmp	r0, #0x2
	bls.n	.L08025042
	cbz	r5, .L08025052
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024a38
	cmp	r0, #0x2
	bhi.n	.L08025044
	movs	r0, #0x0
	strb	r0, [r4, #0x1a]
.L08025042:
	pop	{r3, r4, r5, r6, r7, pc}
.L08025044:
	cmp	r0, #0xfd
	bhs.n	.L08025052
	ldrb	r1, [r4, #0x1a]
	smulbb	r0, r1, r0		@ byte * fn_08024a38 result
	lsrs	r0, r0, #0x8		@ / 256
	strb	r0, [r4, #0x1a]
.L08025052:
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024c88
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0xc]
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x58		@ key 0x58
	bl	fn_08024bac
	strh	r0, [r4, #0x14]
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x59		@ key 0x59
	bl	fn_08024bac
	strh	r0, [r4, #0x12]
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x5a		@ key 0x5a
	bl	fn_08024bac
	ldrb	r1, [r4, #0x1e]
	bfi	r1, r0, #0x0, #0x3	@ bits 0-2 of out+0x1e
	strb	r1, [r4, #0x1e]
	cbz	r5, .L0802509e
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024968
	ldrb	r1, [r4, #0x1e]
	bfi	r1, r0, #0x3, #0x3	@ bits 3-5 of out+0x1e
	strb	r1, [r4, #0x1e]
.L0802509e:
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024ca8
	str	r0, [r4, #0x0]
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x5b		@ key 0x5b
	bl	fn_08024bac
	strb	r0, [r4, #0x1c]
	pop	{r3, r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_080250b6 - r0 = object, r1 = flag, r2 = output record (halfwords), r3
@ unused; no return value.
@ Reads key 0x4e into the byte at out+8; when it is above 2 (scaled by
@ fn_08024a38 (0x08024a38) / 256 when flag is nonzero; 0 and return when that
@ is below 3) reads key 0x49 into out[1]. When out[1] is nonzero stores
@ fn_08012786 (0x08012786) of key 0x4d into out[0], key 0x4a into out[2], key
@ 0x4b into out[3] (only when out[2] is nonzero), key 0x4c (nonzero -> 1) as
@ bits 2 and 3 of the byte at out+9, and with flag nonzero fn_08024968
@ (0x08024968) in bits 0-1 of that byte.
@ ----------------------------------------------------------------------------
	.section .text.fn_080250b6,"ax",%progbits
	.global fn_080250b6
	.thumb_func
	.type fn_080250b6, %function
fn_080250b6:
	push	{r3, r4, r5, r6, r7, lr}
	mov	r5, r2			@ r5 = output record
	mov	r4, r1			@ r4 = flag
	mov	r6, r0			@ r6 = object
	movs	r2, #0x4e		@ key 0x4e
	bl	fn_08024bac
	uxtb	r0, r0
	strb	r0, [r5, #0x8]
	cmp	r0, #0x2
	bls.n	.L080250de
	cbz	r4, .L080250ee
	mov	r1, r4
	mov	r0, r6
	bl	fn_08024a38
	cmp	r0, #0x2
	bhi.n	.L080250e0
	movs	r0, #0x0
	strb	r0, [r5, #0x8]
.L080250de:
	pop	{r3, r4, r5, r6, r7, pc}
.L080250e0:
	cmp	r0, #0xfd
	bhs.n	.L080250ee
	ldrb	r1, [r5, #0x8]
	smulbb	r0, r1, r0		@ byte * fn_08024a38 result
	lsrs	r0, r0, #0x8		@ / 256
	strb	r0, [r5, #0x8]
.L080250ee:
	mov	r0, r6
	mov	r1, r4
	movs	r2, #0x49		@ key 0x49
	bl	fn_08024bac
	sxth	r0, r0
	strh	r0, [r5, #0x2]		@ out[1]
	cmp	r0, #0x0
	beq.n	.L080250de
	movs	r2, #0x4d		@ key 0x4d
	mov	r1, r4
	mov	r0, r6
	bl	fn_08024bac
	mov	r2, r0
	mov	r1, r4
	mov	r0, r6
	bl	fn_08012786
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r5, #0x0]		@ out[0]
	mov	r0, r6
	mov	r1, r4
	movs	r2, #0x4a		@ key 0x4a
	bl	fn_08024bac
	sxth	r0, r0
	strh	r0, [r5, #0x4]		@ out[2]
	cbz	r0, .L08025138
	mov	r0, r6
	mov	r1, r4
	movs	r2, #0x4b		@ key 0x4b
	bl	fn_08024bac
	strh	r0, [r5, #0x6]		@ out[3]
.L08025138:
	mov	r0, r6
	mov	r1, r4
	movs	r2, #0x4c		@ key 0x4c
	bl	fn_08024bac
	cbz	r0, .L08025148
	movs	r1, #0x1
	b.n	.L0802514a
.L08025148:
	movs	r1, #0x0
.L0802514a:
	ldrb	r0, [r5, #0x9]
	bfi	r0, r1, #0x2, #0x1	@ bit 2 = (key 0x4c != 0)
	lsrs	r1, r0, #0x2
	bfi	r0, r1, #0x3, #0x1	@ bit 3 = bit 2
	strb	r0, [r5, #0x9]
	cmp	r4, #0x0
	beq.n	.L080250de
	mov	r1, r4
	mov	r0, r6
	bl	fn_08024968
	ldrb	r1, [r5, #0x9]
	bfi	r1, r0, #0x0, #0x2	@ bits 0-1 = fn_08024968 result
	strb	r1, [r5, #0x9]
	pop	{r3, r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_0802516e - r0 = object, r1 = flag, r2 = output record (halfword array);
@ no return value.
@ r7 = alpha: 0xff, or with flag nonzero the result of fn_08024a38
@ (0x08024a38). If alpha is below 3 the bytes at out+3, out+0x1a, out+0x22,
@ out+0x2a and out+0x36 are cleared and the function returns; otherwise
@ fn_08024968 (0x08024968) is stored at out+2.
@ Stores key 0xb in out[0] (via fn_08024bac 0x08024bac), then fills the
@ sections guarded by these bytes of the record:
@  - out+3: key 0x21 (above 2 to continue), fn_08024942 (0x08024942) into
@    out[2]; key 0x26 gives a pointer: when it is nonzero and bits 0-2 of its
@    byte +9 are nonzero, 10 bytes are copied from it to out+6 with
@    copy_bytes_08022ce0 (0x08022ce0); otherwise key 0x23 (3 bits) goes to
@    bits 0-2 of out+0xf and, when nonzero, fn_08024942 into out[3],
@    fn_08012786 (0x08012786) of key 0x22 into out[5], key 0x24 into out+8,
@    key 0x25 into out+0xc; then key 0x27 into bits 3-5 of out+0xf.
@  - out+0x22: key 0x32 into out[0x10]; when nonzero and the guard byte is
@    nonzero, key 0x31 into the guard byte, and above 2: key 0x33 into bits
@    1-5 of out+0x23 and fn_08012786 of key 0x30 into out[0xf].
@  - out+0x2a: fn_08024a74 (0x08024a74) into out[0x13]; when nonzero and the
@    guard byte is nonzero, fn_08024a5c (0x08024a5c) into the guard byte, and
@    above 2: fn_08024a68 (0x08024a68) into out[0x14] and fn_08012786 of key
@    0x36 into out[0x12].
@  - out+0x1a: key 0x28 into the word at out+0x10; when nonzero, key 0x29 into
@    the guard byte, and above 2: when fn_08021d60 (0x08021d60) of the word
@    returns 2, fn_08024ca8 into the word at out+0x14 and fn_08024c88 into
@    out[0xc]; else fn_08012786 of key 0x2a into out[0xc], key 0x2b into the
@    byte at out+0x1b and key 0x2c (nonzero -> 1) into the byte at out+0x1c.
@  - out+0x36: fn_08024c7c (0x08024c7c) into out[0x17]; when nonzero and the
@    guard byte is above 2, fn_08024c64 into the guard byte, and above 2:
@    fn_08024c4c, fn_08024c58 and fn_08024c70 into out[0x18], out[0x19] and
@    out[0x1a], fn_08012786 of key 0x44 into out[0x16].
@ At the end, with flag nonzero and alpha below 0xfd, byte(out+0x36) * alpha
@ / 256 is stored into the five guard bytes.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802516e,"ax",%progbits
	.global fn_0802516e
	.thumb_func
	.type fn_0802516e, %function
fn_0802516e:
	push	{r3, r4, r5, r6, r7, lr}
	mov	r4, r2			@ r4 = output record
	movs	r5, r1			@ r5 = flag (sets Z)
	mov	r6, r0			@ r6 = object
	mov.w	r7, #0xff		@ alpha = 0xff (mov.w does not change Z)
	beq.n	.L08025194
	bl	fn_08024a38
	mov	r7, r0			@ alpha
	cmp	r0, #0x2
	bhi.n	.L0802518a
	movs	r0, #0x0
	b.n	.L080253d2
.L0802518a:
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024968
	strb	r0, [r4, #0x2]
.L08025194:
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0xb		@ key 0xb
	bl	fn_08024bac
	strh	r0, [r4, #0x0]		@ out[0]
	ldrb	r0, [r4, #0x3]
	cmp	r0, #0x0
	beq.n	.L08025252
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x21		@ key 0x21
	bl	fn_08024bac
	uxtb	r0, r0
	strb	r0, [r4, #0x3]
	cmp	r0, #0x2
	bls.n	.L08025252
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024942
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0x4]		@ out[2]
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x26		@ key 0x26
	bl	fn_08024bac
	movs	r1, r0
	beq.n	.L080251e6
	ldrb	r0, [r1, #0x9]
	lsls	r0, r0, #0x1d		@ isolate bits 0-2 of the byte
	beq.n	.L080251e6
	movs	r2, #0xa		@ 10 bytes
	adds	r0, r4, #0x6		@ destination out+6
	bl	copy_bytes_08022ce0
	b.n	.L08025252
.L080251e6:
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x23		@ key 0x23
	bl	fn_08024bac
	ldrb	r1, [r4, #0xf]
	bfi	r1, r0, #0x0, #0x3	@ bits 0-2 of out+0xf
	strb	r1, [r4, #0xf]
	lsls	r0, r1, #0x1d
	beq.n	.L08025240
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024942
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0x6]		@ out[3]
	movs	r2, #0x22		@ key 0x22
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024bac
	mov	r2, r0
	mov	r1, r5
	mov	r0, r6
	bl	fn_08012786
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0xa]		@ out[5]
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x24		@ key 0x24
	bl	fn_08024bac
	strb	r0, [r4, #0x8]
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x25		@ key 0x25
	bl	fn_08024bac
	strb	r0, [r4, #0xc]
.L08025240:
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x27		@ key 0x27
	bl	fn_08024bac
	ldrb	r1, [r4, #0xf]
	bfi	r1, r0, #0x3, #0x3	@ bits 3-5 of out+0xf
	strb	r1, [r4, #0xf]
.L08025252:
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x32		@ key 0x32
	bl	fn_08024bac
	sxth	r0, r0
	strh	r0, [r4, #0x20]		@ out[0x10]
	cbz	r0, .L080252ae
	ldrb.w	r0, [r4, #0x22]
	cbz	r0, .L080252ae
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x31		@ key 0x31
	bl	fn_08024bac
	uxtb	r0, r0
	strb.w	r0, [r4, #0x22]
	cmp	r0, #0x2
	bls.n	.L080252ae
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x33		@ key 0x33
	bl	fn_08024bac
	ldrb.w	r1, [r4, #0x23]
	movs	r2, #0x30		@ key 0x30 for the call below
	bfi	r1, r0, #0x1, #0x5	@ bits 1-5 of out+0x23
	strb.w	r1, [r4, #0x23]
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024bac
	mov	r2, r0
	mov	r1, r5
	mov	r0, r6
	bl	fn_08012786
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0x1e]		@ out[0xf]
.L080252ae:
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024a74
	strh	r0, [r4, #0x26]		@ out[0x13]
	cbz	r0, .L080252f6
	ldrb.w	r0, [r4, #0x2a]
	cbz	r0, .L080252f6
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024a5c
	strb.w	r0, [r4, #0x2a]
	cmp	r0, #0x2
	bls.n	.L080252f6
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024a68
	strh	r0, [r4, #0x28]		@ out[0x14]
	movs	r2, #0x36		@ key 0x36
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024bac
	mov	r2, r0
	mov	r1, r5
	mov	r0, r6
	bl	fn_08012786
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0x24]		@ out[0x12]
.L080252f6:
	ldrb	r0, [r4, #0x1a]
	cbz	r0, .L0802535c
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x28		@ key 0x28
	bl	fn_08024bac
	str	r0, [r4, #0x10]
	cbz	r0, .L0802535c
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x29		@ key 0x29
	bl	fn_08024bac
	uxtb	r0, r0
	strb	r0, [r4, #0x1a]
	cmp	r0, #0x2
	bls.n	.L0802535c
	ldr	r0, [r4, #0x10]
	bl	fn_08021d60
	cmp	r0, #0x2
	beq.n	.L080253e4
	movs	r2, #0x2a		@ key 0x2a
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024bac
	mov	r2, r0
	mov	r1, r5
	mov	r0, r6
	bl	fn_08012786
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0x18]		@ out[0xc]
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x2b		@ key 0x2b
	bl	fn_08024bac
	strb	r0, [r4, #0x1b]
	mov	r0, r6
	mov	r1, r5
	movs	r2, #0x2c		@ key 0x2c
	bl	fn_08024bac
	cbz	r0, .L0802535a
	movs	r0, #0x1
.L0802535a:
	strb	r0, [r4, #0x1c]
.L0802535c:
	ldrb.w	r0, [r4, #0x36]
	cbz	r0, .L080253c0
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024c7c
	strh	r0, [r4, #0x2e]		@ out[0x17]
	cbz	r0, .L080253c0
	ldrb.w	r0, [r4, #0x36]
	cmp	r0, #0x2
	bls.n	.L080253c0
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024c64
	strb.w	r0, [r4, #0x36]
	cmp	r0, #0x2
	bls.n	.L080253c0
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024c4c
	strh	r0, [r4, #0x30]		@ out[0x18]
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024c58
	strh	r0, [r4, #0x32]		@ out[0x19]
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024c70
	strh	r0, [r4, #0x34]		@ out[0x1a]
	movs	r2, #0x44		@ key 0x44
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024bac
	mov	r2, r0
	mov	r1, r5
	mov	r0, r6
	bl	fn_08012786
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0x2c]		@ out[0x16]
.L080253c0:
	cmp	r5, #0x0
	beq.n	.L080253e2
	cmp	r7, #0xfd
	bhs.n	.L080253e2
	ldrb.w	r0, [r4, #0x36]
	smulbb	r0, r0, r7		@ byte(out+0x36) * alpha
	lsrs	r0, r0, #0x8		@ / 256
.L080253d2:
	strb	r0, [r4, #0x3]		@ the five guard bytes get the same value
	strb	r0, [r4, #0x1a]
	strb.w	r0, [r4, #0x22]
	strb.w	r0, [r4, #0x2a]
	strb.w	r0, [r4, #0x36]
.L080253e2:
	pop	{r3, r4, r5, r6, r7, pc}
.L080253e4:
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024ca8
	str	r0, [r4, #0x14]
	mov	r1, r5
	mov	r0, r6
	bl	fn_08024c88
	str	r0, [sp, #0x0]
	ldrh.w	r0, [sp, #0x0]
	strh	r0, [r4, #0x18]		@ out[0xc]
	b.n	.L0802535c

@ ----------------------------------------------------------------------------
@ fn_08025400 - r0 = object; r2/r3 scratch for the rectangle; no return
@ value.
@ Gets fn_08012726 (0x08012726) (a 16-bit margin), copies the object
@ rectangle (object+0x14) to a stack rectangle with copy_rect_0801cfa0
@ (0x0801cfa0), subtracts the margin from the first two halfwords and adds it
@ to the last two, and calls fn_08025446 (0x08025446) with (object,
@ rectangle).
@ ----------------------------------------------------------------------------
	.section .text.fn_08025400,"ax",%progbits
	.global fn_08025400
	.thumb_func
	.type fn_08025400, %function
fn_08025400:
	push	{r2, r3, r4, r5, r6, lr}
	mov	r5, r0			@ r5 = object
	bl	fn_08012726
	mov	r4, r0			@ r4 = margin
	add.w	r1, r5, #0x14		@ source: object rectangle
	mov	r0, sp			@ destination: stack rectangle
	bl	copy_rect_0801cfa0
	ldrh.w	r0, [sp, #0x0]
	mov	r1, sp
	subs	r0, r0, r4
	strh.w	r0, [sp, #0x0]		@ x1 - margin
	ldrh.w	r0, [sp, #0x2]
	subs	r0, r0, r4
	strh.w	r0, [sp, #0x2]		@ y1 - margin
	ldrh.w	r0, [sp, #0x4]
	add	r0, r4
	strh.w	r0, [sp, #0x4]		@ x2 + margin
	ldrh.w	r0, [sp, #0x6]
	add	r0, r4
	strh.w	r0, [sp, #0x6]		@ y2 + margin
	mov	r0, r5
	bl	fn_08025446
	pop	{r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08025446 - r0 = object, r1 = rectangle pointer, r2/r3 scratch; no
@ return value.
@ Calls fn_08023ebc (0x08023ebc) with the object and passes its result on to
@ fn_0801ddb4 (0x0801ddb4); when that returns nonzero, copies the rectangle
@ with copy_rect_0801cfa0 (0x0801cfa0) and, when fn_080231c8 (0x080231c8) of
@ (object, copy) is nonzero, calls fn_080124d8 (0x080124d8) with the result
@ of fn_08023ebc (object) and the copy.
@ ----------------------------------------------------------------------------
	.section .text.fn_08025446,"ax",%progbits
	.global fn_08025446
	.thumb_func
	.type fn_08025446, %function
fn_08025446:
	push	{r2, r3, r4, r5, r6, lr}
	mov	r4, r1			@ r4 = rectangle
	mov	r5, r0			@ r5 = object
	bl	fn_08023ebc
	bl	fn_0801ddb4
	cmp	r0, #0x0
	beq.n	.L08025478
	mov	r1, r4
	mov	r0, sp
	bl	copy_rect_0801cfa0
	mov	r1, sp
	mov	r0, r5
	bl	fn_080231c8
	cmp	r0, #0x0
	beq.n	.L08025478
	mov	r0, r5
	bl	fn_08023ebc
	mov	r1, sp
	bl	fn_080124d8
.L08025478:
	pop	{r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_0802547a - r0 = object; returns 1 or 0.
@ Follows the chain of first words starting at the object; skips nodes whose
@ byte at +0x18 has bits 0-1 clear; returns 1 when those bits of the first
@ other node equal 1, else 0; returns 0 at the end of the chain.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802547a,"ax",%progbits
	.global fn_0802547a
	.thumb_func
	.type fn_0802547a, %function
fn_0802547a:
	ldr	r0, [r0, #0x0]
	cmp	r0, #0x0
	beq.n	.L08025492
	ldrb	r1, [r0, #0x18]
	lsls	r1, r1, #0x1e		@ isolate bits 0-1
	beq.n	fn_0802547a
	ldrb	r0, [r0, #0x18]
	and	r0, r0, #0x3
	cmp	r0, #0x1
	beq.n	.L08025492
	movs	r0, #0x0
.L08025492:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_08025494 - r0 = object; returns 1 or 0.
@ Follows the chain of first words starting at the object; skips nodes whose
@ byte at +0x18 has bits 2-3 clear; returns 1 when bits 2-3 of that byte of
@ the first other node equal 1, else 0; returns 0 at the end of the chain.
@ ----------------------------------------------------------------------------
	.section .text.fn_08025494,"ax",%progbits
	.p2align 2
	.global fn_08025494
	.thumb_func
	.type fn_08025494, %function
fn_08025494:
	ldr	r0, [r0, #0x0]
	cmp	r0, #0x0
	beq.n	.L080254ae
	ldrb	r1, [r0, #0x18]
	tst	r1, #0xc
	beq.n	fn_08025494
	ldrb	r0, [r0, #0x18]
	ubfx	r0, r0, #0x2, #0x2
	cmp	r0, #0x1
	beq.n	.L080254ae
	movs	r0, #0x0
.L080254ae:
	bx	lr

@ ----------------------------------------------------------------------------
@ fn_080254b0 - r0 = object; returns 1 or 0.
@ Returns 1 only when any_flag_bit_set (0x08024ed0) of the object with mask
@ 0x60001 is zero, the parent (fn_08023fa4, 0x08023fa4) is nonzero and
@ fn_08024a08 (0x08024a08) of the parent with 0 is nonzero.
@ ----------------------------------------------------------------------------
	.section .text.fn_080254b0,"ax",%progbits
	.p2align 2
	.global fn_080254b0
	.thumb_func
	.type fn_080254b0, %function
fn_080254b0:
	push	{r4, lr}
	mov	r4, r0			@ r4 = object
	ldr	r1, .L080254d8		@ r1 = mask 0x60001
	bl	any_flag_bit_set
	cbz	r0, .L080254c0
	movs	r0, #0x0
.L080254be:
	pop	{r4, pc}
.L080254c0:
	mov	r0, r4
	bl	fn_08023fa4		@ parent
	cmp	r0, #0x0
	beq.n	.L080254be
	movs	r1, #0x0
	bl	fn_08024a08
	cmp	r0, #0x0
	beq.n	.L080254be
	movs	r0, #0x1
	pop	{r4, pc}
.L080254d8:
	.word 0x00060001		@ mask for any_flag_bit_set

@ ----------------------------------------------------------------------------
@ fn_080254dc - r0 = object, r2/r3 scratch for the rectangle; no return
@ value.
@ Same as fn_08025400 (0x08025400) but passes the grown rectangle to
@ fn_080231c8 (0x080231c8) instead of fn_08025446 (0x08025446): margin from
@ fn_08012726 (0x08012726), the object rectangle (object+0x14) copied with
@ copy_rect_0801cfa0 (0x0801cfa0), first two halfwords decreased and last
@ two halfwords increased by the margin.
@ ----------------------------------------------------------------------------
	.section .text.fn_080254dc,"ax",%progbits
	.global fn_080254dc
	.thumb_func
	.type fn_080254dc, %function
fn_080254dc:
	push	{r2, r3, r4, r5, r6, lr}
	mov	r5, r0			@ r5 = object
	bl	fn_08012726
	mov	r4, r0			@ r4 = margin
	add.w	r1, r5, #0x14		@ source: object rectangle
	mov	r0, sp			@ destination: stack rectangle
	bl	copy_rect_0801cfa0
	ldrh.w	r0, [sp, #0x0]
	mov	r1, sp
	subs	r0, r0, r4
	strh.w	r0, [sp, #0x0]		@ x1 - margin
	ldrh.w	r0, [sp, #0x2]
	subs	r0, r0, r4
	strh.w	r0, [sp, #0x2]		@ y1 - margin
	ldrh.w	r0, [sp, #0x4]
	add	r0, r4
	strh.w	r0, [sp, #0x4]		@ x2 + margin
	ldrh.w	r0, [sp, #0x6]
	add	r0, r4
	strh.w	r0, [sp, #0x6]		@ y2 + margin
	mov	r0, r5
	bl	fn_080231c8
	pop	{r2, r3, r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08025522 - r0 = object; no return value.
@ Sets bit 0 of the halfword at object+0x22, sets bit 1 of the halfword at
@ +0x22 of the top object (fn_08023fac, 0x08023fac), calls fn_08023ebc
@ (0x08023ebc) and, when the word at +4 of its result is nonzero, tail-calls
@ record_clear_flag (0x08027980).
@ ----------------------------------------------------------------------------
	.section .text.fn_08025522,"ax",%progbits
	.global fn_08025522
	.thumb_func
	.type fn_08025522, %function
fn_08025522:
	push	{r4, lr}
	ldrh	r1, [r0, #0x22]
	orr	r1, r1, #0x1
	strh	r1, [r0, #0x22]		@ object flag halfword |= 1
	bl	fn_08023fac
	ldrh	r1, [r0, #0x22]
	orr	r1, r1, #0x2
	strh	r1, [r0, #0x22]		@ top object flag halfword |= 2
	bl	fn_08023ebc
	ldr	r0, [r0, #0x4]
	cmp	r0, #0x0
	beq.n	.L0802554a
	pop.w	{r4, lr}
	b.w	record_clear_flag
.L0802554a:
	pop	{r4, pc}

@ ----------------------------------------------------------------------------
@ fn_0802554c - r0 = object, r1 = dx, r2 = dy, r3 = flag; no return value.
@ For each child in the list at [[object+8]] (count from fn_08023da4,
@ 0x08023da4): when flag is 0 or all_flag_bits_set (0x08024ec2) of the child
@ with 0x40000 is clear, adds dx to the halfwords at child+0x14 and +0x18 and
@ dy to the halfwords at child+0x16 and +0x1a, then recurses on the child
@ with flag 0.
@ Registers: r10 = object, r8 = dx, r7 = dy, r9 = flag, r6 = count,
@ r5 = index, r4 = child.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802554c,"ax",%progbits
	.global fn_0802554c
	.thumb_func
	.type fn_0802554c, %function
fn_0802554c:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r9, r3
	mov	r7, r2
	mov	r8, r1
	mov	r10, r0
	bl	fn_08023da4
	mov	r6, r0			@ child count
	movs	r5, #0x0		@ index = 0
	b.n	.L080255aa
	nop				@ padding
.L08025564:
	ldr.w	r0, [r10, #0x8]		@ loop body (entered from .L080255aa)
	cmp.w	r9, #0x0
	ldr	r0, [r0, #0x0]
	ldr.w	r4, [r0, r5, lsl #0x2]	@ child = list[index]
	beq.n	.L08025580
	mov.w	r1, #0x40000
	mov	r0, r4
	bl	all_flag_bits_set
	cbnz	r0, .L080255a8
.L08025580:
	ldrh	r1, [r4, #0x14]
	movs	r3, #0x0		@ flag for the recursion
	add.w	r0, r1, r8
	strh	r0, [r4, #0x14]		@ x1 += dx
	ldrh	r0, [r4, #0x16]
	mov	r2, r7
	add	r0, r7
	strh	r0, [r4, #0x16]		@ y1 += dy
	ldrh	r1, [r4, #0x18]
	add.w	r0, r1, r8
	strh	r0, [r4, #0x18]		@ x2 += dx
	ldrh	r0, [r4, #0x1a]
	mov	r1, r8
	add	r0, r7
	strh	r0, [r4, #0x1a]		@ y2 += dy
	mov	r0, r4
	bl	fn_0802554c
.L080255a8:
	.inst.n 0x1c6d			@ adds r5, r5, #1
.L080255aa:
	cmp	r5, r6
	blo.n	.L08025564
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ fn_080255b2 - r0 = object O (kept in r4), r1 = x (r7), r2 = y (r6); no
@ return value. Body 0x080255b2..0x080256cb (push of r0-r9, r10, lr; the
@ matching pop at 0x080256bc). Reached only by the b.w at 0x080259c4 inside
@ 0x08025844.
@ r5 = P = word [O+4] (parent). When P is nonzero: r8 = fn_08024ae0 (P, 0),
@ r9 = fn_08024b70 (P, 0); when all_flag_bits_set (0x08024ec2) of O with
@ 0x40000 is nonzero: x = sxth(x + r8 + halfword [P+0x14]) and
@ y = sxth(y + r9 + halfword [P+0x16]); otherwise
@ x = sxth(x + (halfword [P+0x14] + r8 - fn_08024216(P))) and
@ y = sxth(y + (halfword [P+0x16] + r9 - fn_08024224(P))). Then
@ s = fn_08024984 (P, 0) is added to both, both are sign-extended to 16 bits.
@ dx = sxth(x - halfword [O+0x14]), dy = sxth(y - halfword [O+0x16]); when
@ both are 0 the function returns.
@ Otherwise: fn_08025400 (O); fn_08023eb0 (O, sp+8) copies a rectangle of O
@ to sp+8; f = 0 and, when P is nonzero, fn_08023dec (P, sp),
@ f = fn_08011e9c (sp+8, sp, 0), and fn_080262c4 (P) is called when f is 0.
@ Halfwords [O+0x14] and [O+0x18] += dx, [O+0x16] and [O+0x1a] += dy;
@ fn_0802554c (O, dx, dy, 0) is called. With P = 0 fn_08025400 (O) is called
@ and the function returns. With P nonzero: fn_080207f4 (P, 0x22, O),
@ fn_08025400 (O), g = fn_08011e9c (O+0x14, sp, 0); fn_080262c4 (P) is called
@ when f or g is nonzero.
@ ----------------------------------------------------------------------------
	.section .text.fn_080255b2,"ax",%progbits
	.global fn_080255b2
	.thumb_func
	.type fn_080255b2, %function
fn_080255b2:
	push.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	ldr	r5, [r0, #0x4]		@ r5 = P
	mov	r6, r2
	mov	r7, r1
	mov	r4, r0
	cbz	r5, .L08025628
	movs	r1, #0x0
	mov	r0, r5
	bl	fn_08024ae0
	mov	r8, r0
	movs	r1, #0x0
	mov	r0, r5
	bl	fn_08024b70
	mov	r9, r0
	mov.w	r1, #0x40000
	mov	r0, r4
	bl	all_flag_bits_set
	cbz	r0, .L080255f4
	ldrh	r1, [r5, #0x14]
	add.w	r0, r7, r8
	add	r0, r1
	sxth	r7, r0
	ldrh	r1, [r5, #0x16]
	add.w	r0, r6, r9
	add	r0, r1
	b.n	.L08025616
.L080255f4:
	mov	r0, r5
	bl	fn_08024216
	ldrh	r2, [r5, #0x14]
	add.w	r1, r2, r8
	subs	r0, r1, r0
	add	r0, r7
	sxth	r7, r0
	mov	r0, r5
	bl	fn_08024224
	ldrh	r2, [r5, #0x16]
	add.w	r1, r2, r9
	subs	r0, r1, r0
	add	r0, r6
.L08025616:
	sxth	r6, r0
	movs	r1, #0x0
	mov	r0, r5
	bl	fn_08024984
	adds	r1, r7, r0
	add	r0, r6
	sxth	r7, r1
	sxth	r6, r0
.L08025628:
	ldrh	r0, [r4, #0x14]
	subs	r0, r7, r0
	sxth	r7, r0			@ dx
	ldrh	r0, [r4, #0x16]
	subs	r0, r6, r0
	sxth	r6, r0			@ dy
	cbnz	r7, .L0802563a
	cmp	r6, #0x0
	beq.n	.L080256bc
.L0802563a:
	mov	r0, r4
	bl	fn_08025400
	add	r1, sp, #0x8
	mov	r0, r4
	bl	fn_08023eb0
	mov.w	r8, #0x0		@ f = 0
	cbz	r5, .L0802566c
	mov	r1, sp
	mov	r0, r5
	bl	fn_08023dec
	movs	r2, #0x0
	mov	r1, sp
	add	r0, sp, #0x8
	bl	fn_08011e9c
	movs.w	r8, r0			@ f
	bne.n	.L0802566c
	mov	r0, r5
	bl	fn_080262c4
.L0802566c:
	ldrh	r0, [r4, #0x14]
	mov	r2, r6
	add	r0, r7
	strh	r0, [r4, #0x14]		@ x1 += dx
	ldrh	r0, [r4, #0x16]
	mov	r1, r7
	add	r0, r6
	strh	r0, [r4, #0x16]		@ y1 += dy
	ldrh	r0, [r4, #0x18]
	movs	r3, #0x0
	add	r0, r7
	strh	r0, [r4, #0x18]		@ x2 += dx
	ldrh	r0, [r4, #0x1a]
	add	r0, r6
	strh	r0, [r4, #0x1a]		@ y2 += dy
	mov	r0, r4
	bl	fn_0802554c
	cbz	r5, .L080256b6
	mov	r2, r4
	movs	r1, #0x22
	mov	r0, r5
	bl	fn_080207f4
	mov	r0, r4
	bl	fn_08025400
	movs	r2, #0x0
	mov	r1, sp
	add.w	r0, r4, #0x14
	bl	fn_08011e9c		@ g
	cmp.w	r8, #0x0
	bne.n	.L080256c4
	b.n	.L080256c0
.L080256b6:
	mov	r0, r4
	bl	fn_08025400
.L080256bc:
	pop.w	{r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, pc}
.L080256c0:
	cmp	r0, #0x0
	beq.n	.L080256bc
.L080256c4:
	mov	r0, r5
	bl	fn_080262c4
	b.n	.L080256bc

@ ----------------------------------------------------------------------------
@ fn_080256cc - r0 = object, r1 = mode passed on; no return value.
@ When fn_080241fa (0x080241fa) returns 0, takes a = fn_08024208
@ (0x08024208) and b = fn_08023fbc (0x08023fbc); when b < 0 < a scrolls
@ vertically by the smaller of a and -b (as a signed 16-bit value) with
@ fn_08026014 (0x08026014)(object, 0, amount, mode).
@ When fn_080241ec (0x080241ec) returns 0, takes c = fn_08024070
@ (0x08024070) and d = fn_08024130 (0x08024130); when fn_08024912
@ (0x08024912)(object, 0) equals 1 and c < 0 < d it scrolls horizontally by
@ c with fn_08026014 (object, c, 0, mode); otherwise when d < 0 < c it
@ scrolls horizontally by the smaller of c and -d, as a signed 16-bit value,
@ with fn_08026014 (object, amount, 0, mode). Registers: r6 = object,
@ r5 = mode, r4 = first value, r7 = second value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080256cc,"ax",%progbits
	.global fn_080256cc
	.thumb_func
	.type fn_080256cc, %function
fn_080256cc:
	push.w	{r4, r5, r6, r7, r8, lr}
	mov	r5, r1			@ r5 = mode
	mov	r6, r0			@ r6 = object
	bl	fn_080241fa
	cbnz	r0, .L08025704
	mov	r0, r6
	bl	fn_08024208
	mov	r4, r0
	mov	r0, r6
	bl	fn_08023fbc
	cmp	r0, #0x0
	bge.n	.L08025704
	cmp	r4, #0x0
	ble.n	.L08025704
	rsbs	r0, r0, #0		@ -b
	cmp	r4, r0
	blt.n	.L080256f8
	mov	r4, r0			@ smaller magnitude
.L080256f8:
	sxth	r2, r4
	mov	r3, r5
	movs	r1, #0x0
	mov	r0, r6
	bl	fn_08026014
.L08025704:
	mov	r0, r6
	bl	fn_080241ec
	cmp	r0, #0x0
	bne.n	.L0802575a
	mov	r0, r6
	bl	fn_08024070
	mov	r4, r0
	mov	r0, r6
	bl	fn_08024130
	mov	r7, r0
	movs	r1, #0x0
	mov	r0, r6
	bl	fn_08024912
	cmp	r0, #0x1
	beq.n	.L08025742
	cmp	r7, #0x0
	bge.n	.L0802575a
	cmp	r4, #0x0
	ble.n	.L0802575a
	rsbs	r0, r7, #0		@ -d
	cmp	r4, r0
	blt.n	.L0802573a
	mov	r4, r0			@ smaller magnitude
.L0802573a:
	sxth	r1, r4
	mov	r3, r5
	movs	r2, #0x0
	b.n	.L08025750
.L08025742:
	cmp	r4, #0x0
	bge.n	.L0802575a
	cmp	r7, #0x0
	ble.n	.L0802575a
	mov	r3, r5
	movs	r2, #0x0
	mov	r1, r4
.L08025750:
	mov	r0, r6
	pop.w	{r4, r5, r6, r7, r8, lr}
	b.w	fn_08026014
.L0802575a:
	pop.w	{r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ fn_0802575e - r0 = context record (word at +8 = clip rectangle pointer),
@ r1 = object; no return value.
@ Saves the clip pointer (r6), copies the object rectangle with fn_08023eb0
@ (0x08023eb0) to sp+8, grows it by the margin from fn_08012726
@ (0x08012726) with rect_grow (0x0801d082) and intersects it with the saved
@ clip using rect_intersect (0x08011e4c) into sp+0x10. When the intersection
@ is nonempty, or all_flag_bits_set (0x08024ec2) with 0x80000 is true, stores
@ the pointer to it at context+8 and sends the messages 0x14, 0x15 and 0x16
@ to the object with fn_080207f4 (0x080207f4) (r8 = 1; else r8 = 0).
@ Then, with flag 0x80000 set, copies the saved clip (two words) to sp, else
@ intersects the saved clip with object+0x14 into sp (nothing more is done
@ when that is empty). Stores sp at context+8 and calls fn_08028ed4
@ (0x08028ed4)(context, child) for each child of the object (count from
@ fn_08023da4 0x08023da4; list at [[object+8]]). Afterwards, when r8 is
@ nonzero, stores the pointer to the sp+0x10 rectangle at context+8 and sends
@ messages 0x17, 0x18 and 0x19. Finally restores the saved clip pointer to
@ context+8.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802575e,"ax",%progbits
	.global fn_0802575e
	.thumb_func
	.type fn_0802575e, %function
fn_0802575e:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	mov	r9, r1			@ r9 = object
	sub	sp, #0x18
	mov	r4, r0			@ r4 = context record
	ldr	r6, [r0, #0x8]		@ r6 = saved clip pointer
	add	r1, sp, #0x8
	mov	r0, r9
	bl	fn_08023eb0
	mov	r0, r9
	bl	fn_08012726
	mov	r1, r0
	mov	r2, r0
	add	r0, sp, #0x8
	bl	rect_grow
	add	r2, sp, #0x8
	mov	r1, r6
	add	r0, sp, #0x10
	bl	rect_intersect
	mov.w	r5, #0x80000		@ flag mask
	add.w	r10, sp, #0x10
	cbnz	r0, .L080257a0
	mov	r1, r5
	mov	r0, r9
	bl	all_flag_bits_set
	cbz	r0, .L080257c8
.L080257a0:
	mov.w	r8, #0x1
	mov	r2, r4
	movs	r1, #0x14
	mov	r0, r9
	str.w	r10, [r4, #0x8]
	bl	fn_080207f4		@ message 0x14
	mov	r2, r4
	movs	r1, #0x15
	mov	r0, r9
	bl	fn_080207f4		@ message 0x15
	mov	r2, r4
	movs	r1, #0x16
	mov	r0, r9
	bl	fn_080207f4		@ message 0x16
	b.n	.L080257cc
.L080257c8:
	mov.w	r8, #0x0
.L080257cc:
	mov	r1, r5
	mov	r0, r9
	bl	all_flag_bits_set
	cbz	r0, .L080257e0
	ldr	r0, [r6, #0x0]
	str	r0, [sp, #0x0]		@ copy the saved clip (first word)
	ldr	r0, [r6, #0x4]
	str	r0, [sp, #0x4]		@ copy the saved clip (second word)
	b.n	.L080257ee
.L080257e0:
	add.w	r2, r9, #0x14
	mov	r1, r6
	mov	r0, sp
	bl	rect_intersect
	cbz	r0, .L08025814
.L080257ee:
	str.w	sp, [r4, #0x8]
	mov	r0, r9
	bl	fn_08023da4
	mov	r7, r0			@ child count
	movs	r5, #0x0		@ index = 0
	b.n	.L08025810
.L080257fe:
	ldr.w	r0, [r9, #0x8]
	ldr	r0, [r0, #0x0]
	ldr.w	r1, [r0, r5, lsl #0x2]	@ child = list[index]
	mov	r0, r4
	bl	fn_08028ed4
	.inst.n 0x1c6d			@ adds r5, r5, #1
.L08025810:
	cmp	r5, r7
	blo.n	.L080257fe
.L08025814:
	cmp.w	r8, #0x0
	beq.n	.L0802583c
	mov	r2, r4
	movs	r1, #0x17
	mov	r0, r9
	str.w	r10, [r4, #0x8]
	bl	fn_080207f4		@ message 0x17
	mov	r2, r4
	movs	r1, #0x18
	mov	r0, r9
	bl	fn_080207f4		@ message 0x18
	mov	r2, r4
	movs	r1, #0x19
	mov	r0, r9
	bl	fn_080207f4		@ message 0x19
.L0802583c:
	str	r6, [r4, #0x8]		@ restore the saved clip pointer
	add	sp, #0x18
	pop.w	{r4, r5, r6, r7, r8, r9, r10, pc}

@ ----------------------------------------------------------------------------
@ fn_08025844 - r0 = object O (saved at [sp+8]); no return value (ends in a
@ tail call, or returns at once).
@ Returns when fn_080254b0 (0x080254b0)(O) is nonzero. Otherwise the parent
@ P = fn_08023fa4 (O) is saved at [sp]; x = fn_08024d38 (O, 0) in r10 and
@ y = fn_08024d44 (O, 0) in r7.
@ P = 0: x and y go unchanged to the tail call. Otherwise r9 =
@ fn_08023e7c (P) (width) and r5 = fn_08023e48 (P) (height).
@ A value v counts as a percentage when bits 14..13 of v equal 1 (ubfx
@ #13, #2) and p = v with bits 0x6000 cleared is not above 2000 (signed):
@ when p > 1000 then p = 1000 - p; v becomes sxth(p * size / 100) (mul, sdiv
@ by 100, r11 = 100); x uses r9, y uses r5.
@ Offsets x2 = sxth(fn_08024bac (O, 0, 0x6a)) and y2 = sxth(fn_08024bac
@ (O, 0, 0x6b)) get the same conversion with r8 = rect_width_plus_one
@ (0x08024eb6)(O) and r4 = rect_height_plus_one (0x08023f22)(O); then
@ x = sxth(x + x2) and y = sxth(y + y2).
@ a = fn_080248d8 (O, 0): a = 0 calls fn_08024906 (P, 0) and adds r9 - r8 to
@ x when it returns 1; a = 1 and a above 9 change nothing; a = 2..9 go
@ through the tbb table at 0x08025972 (entry = byte, target = 0x08025972 +
@ 2 * byte):
@   2: x += r9/2 - r8/2
@   3: x += r9 - r8
@   4: y += r5 - r4
@   5: x as 2, then y += r5 - r4
@   6: x += r9 - r8, then y += r5 - r4
@   7: y += r5/2 - r4/2
@   8: x += r9 - r8, then y as 7
@   9: x as 2, then y as 7
@ (halves round toward zero: add the sign bit, asr 1; results are
@ sign-extended to 16 bits).
@ Ends by restoring r4..r11 and lr and tail-calling fn_080255b2 (O, x, y)
@ (b.w at 0x080259c4).
@ ----------------------------------------------------------------------------
	.section .text.fn_08025844,"ax",%progbits
	.p2align 2
	.global fn_08025844
	.thumb_func
	.type fn_08025844, %function
fn_08025844:
	push.w	{r0, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub	sp, #0x8
	ldr	r0, [sp, #0x8]
	bl	fn_080254b0
	cmp	r0, #0x0
	bne.n	.L0802594e
	ldr	r0, [sp, #0x8]
	bl	fn_08023fa4
	str	r0, [sp, #0x0]		@ P
	movs	r1, #0x0
	ldr	r0, [sp, #0x8]
	bl	fn_08024d38
	mov	r10, r0			@ x
	movs	r1, #0x0
	ldr	r0, [sp, #0x8]
	bl	fn_08024d44
	mov	r7, r0			@ y
	ldr	r0, [sp, #0x0]
	cbz	r0, .L08025890
	bl	fn_08023e7c
	mov	r9, r0			@ parent width
	ldr	r0, [sp, #0x0]
	bl	fn_08023e48
	mov	r5, r0			@ parent height
	ubfx	r0, r10, #0xd, #0x2
	mov.w	r11, #0x64
	cmp	r0, #0x1
	beq.n	.L08025896
	b.n	.L080258b6
.L08025890:
	mov	r2, r7
	mov	r1, r10
	b.n	.L080259bc
.L08025896:
	bic	r0, r10, #0x6000
	cmp.w	r0, #0x7d0
	bgt.n	.L080258b6
	cmp.w	r0, #0x3e8
	ble.n	.L080258aa
	rsb.w	r0, r0, #0x3e8
.L080258aa:
	mul	r0, r0, r9
	sdiv	r0, r0, r11
	sxth.w	r10, r0
.L080258b6:
	ubfx	r0, r7, #0xd, #0x2
	cmp	r0, #0x1
	bne.n	.L080258da
	bic	r0, r7, #0x6000
	cmp.w	r0, #0x7d0
	bgt.n	.L080258da
	cmp.w	r0, #0x3e8
	ble.n	.L080258d2
	rsb.w	r0, r0, #0x3e8
.L080258d2:
	muls	r0, r5, r0
	sdiv	r0, r0, r11
	sxth	r7, r0
.L080258da:
	movs	r1, #0x0
	movs	r2, #0x6a		@ key 0x6a
	ldr	r0, [sp, #0x8]
	bl	fn_08024bac
	sxth	r6, r0			@ x2
	movs	r1, #0x0
	movs	r2, #0x6b		@ key 0x6b
	ldr	r0, [sp, #0x8]
	bl	fn_08024bac
	sxth	r2, r0			@ y2
	ldr	r0, [sp, #0x8]
	bl	rect_width_plus_one
	mov	r8, r0
	ldr	r0, [sp, #0x8]
	bl	rect_height_plus_one
	mov	r4, r0
	ubfx	r0, r6, #0xd, #0x2
	cmp	r0, #0x1
	bne.n	.L08025928
	bic	r0, r6, #0x6000
	cmp.w	r0, #0x7d0
	bgt.n	.L08025928
	cmp.w	r0, #0x3e8
	ble.n	.L0802591e
	rsb.w	r0, r0, #0x3e8
.L0802591e:
	mul	r0, r0, r8
	sdiv	r0, r0, r11
	sxth	r6, r0
.L08025928:
	ubfx	r0, r2, #0xd, #0x2
	cmp	r0, #0x1
	bne.n	.L0802594c
	bic	r0, r2, #0x6000
	cmp.w	r0, #0x7d0
	bgt.n	.L0802594c
	cmp.w	r0, #0x3e8
	ble.n	.L08025944
	rsb.w	r0, r0, #0x3e8
.L08025944:
	muls	r0, r4, r0
	sdiv	r0, r0, r11
	sxth	r2, r0
.L0802594c:
	b.n	.L08025950
.L0802594e:
	b.n	.L080259fc
.L08025950:
	add.w	r0, r10, r6
	sxth	r6, r0			@ x = sxth(x + x2)
	adds	r0, r7, r2
	sxth	r7, r0			@ y = sxth(y + y2)
	movs	r1, #0x0
	ldr	r0, [sp, #0x8]
	bl	fn_080248d8
	cbz	r0, .L0802597a
	cmp	r0, #0x1
	beq.n	.L080259b8
	.inst.n 0x1e80			@ subs r0, r0, #2
	cmp	r0, #0x8
	bhs.n	.L080259b8
	tbb	[pc, r0]
.L08025972:
	.byte (.L08025988 - .L08025972)/2	@ a = 2
	.byte (.L08025998 - .L08025972)/2	@ a = 3
	.byte (.L080259b2 - .L08025972)/2	@ a = 4
	.byte (.L080259c8 - .L08025972)/2	@ a = 5
	.byte (.L080259d8 - .L08025972)/2	@ a = 6
	.byte (.L080259a2 - .L08025972)/2	@ a = 7
	.byte (.L080259e2 - .L08025972)/2	@ a = 8
	.byte (.L080259e8 - .L08025972)/2	@ a = 9
.L0802597a:
	movs	r1, #0x0
	ldr	r0, [sp, #0x0]
	bl	fn_08024906
	cmp	r0, #0x1
	beq.n	.L08025998
	b.n	.L080259b8
.L08025988:
	add.w	r1, r9, r9, lsr #0x1f
	asrs	r1, r1, #0x1		@ r9 / 2
	add.w	r0, r8, r8, lsr #0x1f
	sub.w	r0, r1, r0, asr #0x1	@ r9/2 - r8/2
	b.n	.L0802599c
.L08025998:
	sub.w	r0, r9, r8		@ r9 - r8
.L0802599c:
	add	r0, r6
	sxth	r6, r0
	b.n	.L080259b8
.L080259a2:
	add.w	r0, r5, r5, lsr #0x1f
	asrs	r0, r0, #0x1		@ r5 / 2
	add.w	r1, r4, r4, lsr #0x1f
	sub.w	r0, r0, r1, asr #0x1	@ r5/2 - r4/2
	b.n	.L080259b4
.L080259b2:
	subs	r0, r5, r4		@ r5 - r4
.L080259b4:
	add	r0, r7
	sxth	r7, r0
.L080259b8:
	mov	r2, r7
	mov	r1, r6
.L080259bc:
	ldr	r0, [sp, #0x8]
	add	sp, #0xc
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w	fn_080255b2
.L080259c8:
	add.w	r1, r9, r9, lsr #0x1f
	asrs	r1, r1, #0x1
	add.w	r0, r8, r8, lsr #0x1f
	sub.w	r0, r1, r0, asr #0x1
	b.n	.L080259dc
.L080259d8:
	sub.w	r0, r9, r8
.L080259dc:
	add	r0, r6
	sxth	r6, r0
	b.n	.L080259b2
.L080259e2:
	sub.w	r0, r9, r8
	b.n	.L080259f6
.L080259e8:
	add.w	r1, r9, r9, lsr #0x1f
	asrs	r1, r1, #0x1
	add.w	r0, r8, r8, lsr #0x1f
	sub.w	r0, r1, r0, asr #0x1
.L080259f6:
	add	r0, r6
	sxth	r6, r0
	b.n	.L080259a2
.L080259fc:
	pop.w	{r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
