@ ui_41.s - user-interface code: screen object-tree builders and display-row updaters at 0x0800c848..0x0800d50c
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_0800c848 - no parameters of its own.
@ Calls 0x0802122c with r0 passed through unchanged, stores the result to the
@ word 0x2000028c, calls 0x08023170(result, 3, -3, 10), then tail-calls
@ fn_0800c724, which returns to the caller of this function.
@ Callers: bl at 0x0800cd76, b.w at 0x0800d818.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c848,"ax",%progbits
	.p2align 2
	.global fn_0800c848
	.thumb_func
	.type fn_0800c848, %function
fn_0800c848:
	push	{r4, lr}
	bl	fn_0802122c
	ldr	r1, .L0800c868
	movs	r3, #0xa
	mvn	r2, #2
	str	r0, [r1]
	movs	r1, #3
	bl	fn_08023170
	pop.w	{r4, lr}
	b.w	fn_0800c724
	.short	0x0000	@ padding
.L0800c868:
	.word	0x2000028c

@ ----------------------------------------------------------------------------
@ fn_0800c86c - no parameters, no return value (ends with a tail call to
@ 0x0802285c). Builds the object tree of a two-entry selector screen.
@ r9 = 0x2000057c (base of the words addressed with offsets).
@ Stores 0 to the words 0x20001168 (r9+0xbec), 0x200011a8 (+0xc2c),
@ 0x200011b4 (+0xc38) and 0x200011b8 (+0xc3c).
@ Root object: r0 = 0x08023678(0) stored to the word 0x20000288; then
@ 0x0801ddd0, 0x080263a8(root, 0x140, 0xf0), 0x0801d7f2(0,0,0) giving a colour
@ value v used in 0x0802657a(root, v, 0), then 0x08026680(root, 0, 0),
@ 0x08026380(root, 0) and 0x080265b4(root, 0, 0).
@ Loop i = 0..1 (r4; r8 = 0x20000288, r5 = 0x20005a08, r6 = r5+0x10 =
@ 0x20005a18, r7 = r5+0x20 = 0x20005a28):
@   object A = 0x08023678([root]) stored to 0x20005a08[i]; 0x080263a8(A, 0x78,
@   0x32); 0x08023170(A, 9, sxth(0x8c*i - 0x46), 0); 0x0801d7f2(0,0,0) ->
@   0x0802657a(A, v, 0); 0x08026380(A, 0); 0x0801d7f2(0x54,0x54,0x54) ->
@   0x0802659c(A, v, 0).
@   object B = 0x08023678(A) stored to 0x20005a18[i]; 0x080263a8(B, 0x70,
@   0x2a); 0x08023170(B, 9, 0, 0); 0x0801d7f2(0x54,0x54,0x54) ->
@   0x0802657a(B, v, 0); 0x080265be(B, 0, 0); 0x08026680(B, 4, 0).
@   object C = 0x08021f5c(B) stored to 0x20005a28[i]; 0x08023170(C, 9, 0, 0);
@   0x080266ac(C, 0x0802f0d8, 0).
@ After the loop: 0x0801d7f2(0xfd, 0xd0, 0x1b) twice; the first result goes to
@ 0x0802659c(0x20005a08[w], v, 0), the second to 0x08026694(0x20005a18[w], v,
@ 0), where w is the word 0x2000115c (r9+0xbe0).
@ Finally 0x0802285c(word 0x20005a28, the 6 UTF-8 bytes at 0x0800ca1c) and, as
@ tail call, 0x0802285c(word 0x20005a2c, the string "English").
@ ----------------------------------------------------------------------------
	.section .text.fn_0800c86c,"ax",%progbits
	.p2align 2
	.global fn_0800c86c
	.thumb_func
	.type fn_0800c86c, %function
fn_0800c86c:
	push.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	ldr.w	r9, .L0800ca0c
	movs	r1, #0
	mov	r0, r1
	str.w	r1, [r9, #0xbec]
	str.w	r1, [r9, #0xc2c]
	str.w	r1, [r9, #0xc38]
	str.w	r1, [r9, #0xc3c]
	bl	fn_08023678
	ldr	r5, .L0800ca10
	str	r0, [r5]
	bl	fn_0801ddd0
	movs	r2, #0xf0
	mov.w	r1, #0x140
	ldr	r0, [r5]
	bl	fn_080263a8
	movs	r2, #0
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d7f2
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r5]
	bl	fn_0802657a
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r5]
	bl	fn_08026680
	movs	r1, #0
	ldr	r0, [r5]
	bl	fn_08026380
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r5]
	bl	fn_080265b4
	mov	r8, r5
	ldr	r5, .L0800ca14
	movs	r4, #0
	mvn	r10, #0x45
	add.w	r6, r5, #0x10
	add.w	r7, r5, #0x20
	nop
.L0800c8e4:
	ldr.w	r0, [r8]
	bl	fn_08023678
	str.w	r0, [r5, r4, lsl #2]
	movs	r2, #0x32
	movs	r1, #0x78
	bl	fn_080263a8
	rsb	r0, r4, r4, lsl #3
	add.w	r1, r0, r0, lsl #2
	add.w	r0, r10, r1, lsl #2
	sxth	r2, r0
	ldr.w	r0, [r5, r4, lsl #2]
	movs	r3, #0
	movs	r1, #9
	bl	fn_08023170
	movs	r2, #0
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d7f2
	mov	r1, r0
	ldr.w	r0, [r5, r4, lsl #2]
	movs	r2, #0
	bl	fn_0802657a
	ldr.w	r0, [r5, r4, lsl #2]
	movs	r1, #0
	bl	fn_08026380
	movs	r2, #0x54
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d7f2
	ldr.w	r3, [r5, r4, lsl #2]
	mov	r1, r0
	movs	r2, #0
	mov	r0, r3
	bl	fn_0802659c
	ldr.w	r0, [r5, r4, lsl #2]
	bl	fn_08023678
	str.w	r0, [r6, r4, lsl #2]
	movs	r2, #0x2a
	movs	r1, #0x70
	bl	fn_080263a8
	movs	r3, #0
	ldr.w	r0, [r6, r4, lsl #2]
	mov	r2, r3
	movs	r1, #9
	bl	fn_08023170
	movs	r2, #0x54
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d7f2
	mov	r1, r0
	ldr.w	r0, [r6, r4, lsl #2]
	movs	r2, #0
	bl	fn_0802657a
	movs	r2, #0
	ldr.w	r0, [r6, r4, lsl #2]
	mov	r1, r2
	bl	fn_080265be
	ldr.w	r0, [r6, r4, lsl #2]
	movs	r2, #0
	movs	r1, #4
	bl	fn_08026680
	ldr.w	r0, [r6, r4, lsl #2]
	bl	fn_08021f5c
	movs	r3, #0
	str.w	r0, [r7, r4, lsl #2]
	mov	r2, r3
	movs	r1, #9
	bl	fn_08023170
	ldr.w	r0, [r7, r4, lsl #2]
	movs	r2, #0
	ldr	r1, .L0800ca18
	bl	fn_080266ac
	.inst.n	0x1c64	@ adds r4, r4, #1
	cmp	r4, #2
	blt.n	.L0800c8e4
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	bl	rgb_to_565_0801d7f2
	mov	r1, r0
	ldr.w	r0, [r9, #0xbe0]
	mov	r4, r9
	movs	r2, #0
	ldr.w	r0, [r5, r0, lsl #2]
	bl	fn_0802659c
	movs	r2, #0x1b
	movs	r1, #0xd0
	movs	r0, #0xfd
	bl	rgb_to_565_0801d7f2
	mov	r1, r0
	ldr.w	r0, [r4, #0xbe0]
	movs	r2, #0
	ldr.w	r0, [r6, r0, lsl #2]
	bl	fn_08026694
	adr	r1, .L0800ca1c
	ldr	r0, [r7]
	bl	fn_0802285c
	ldr	r0, [r7, #4]
	pop.w	{r4, r5, r6, r7, r8, r9, r10, lr}
	adr	r1, .L0800ca24
	b.w	fn_0802285c
.L0800ca0c:
	.word	0x2000057c
.L0800ca10:
	.word	0x20000288
.L0800ca14:
	.word	0x20005a08
.L0800ca18:
	.word	d_0802f0d8
.L0800ca1c:
	.byte	0xe4, 0xb8, 0xad, 0xe6, 0x96, 0x87, 0x00	@ UTF-8 text (6 bytes) + NUL
	.byte	0x00	@ padding
.L0800ca24:
	.asciz	"English"

@ ----------------------------------------------------------------------------
@ fn_0800ca2c - no parameters, no return value. Builds the object tree of a
@ settings screen.
@ Writes 1 to the word 0x20001168, calls 0x08009f10, then 0x08008350(0x40010c00,
@ 0x2000, 1) and 0x08008350(0x40010c00, 0x1000, 1), then 0x0800b164. Clears the
@ words 0x200011a8, 0x200011a4 and 0x200011b4.
@ Root object = 0x08023678(0) stored to the word 0x200001d8 (0x200001d4+4);
@ 0x0802657a(root, low 16 bits of 0x0801d7c2(0,0,0), 0), 0x08026380(root, 0),
@ 0x0801ddd0(root).
@ Container A = 0x0802122c(root), placed with 0x08023170(A, 2, 0, 0); its source
@ is set with 0x08021c14(A, 0x08044150). Children of A, in order:
@   word 0x200001fc = 0x0802122c(A), placed (9, -143, 0)
@   word 0x200001f0 = 0x08021f5c(A), placed (9, -96, 2), 0x080266ac(obj,
@   0x0802ce5c, 0), 0x080228d0(obj, "%s", word[0x20000258 + word[0x2000115c]*0x18
@   + word[0x20001148]*4])
@   word 0x200001dc = 0x0802122c(A), placed (9, -38, 0), source 0x0803c404,
@   0x08023050(obj, 1)
@   word 0x200001e0 = 0x0802122c(A), placed (9, 10, 1); its source depends on the
@   word 0x20001150 and on whether the word 0x2000115c is zero: 0x20001150 = 0
@   gives 0x0803c690 (zero) or 0x08040f10 (non-zero), 1 gives 0x0803c91c or
@   0x08041184, 2 gives 0x0803cba8 or 0x08040c9c, other values set no source
@   word 0x20000200 = 0x0802122c(A), placed (9, 0x3a, 0), source 0x0803e250, then
@   0x08023050(obj, 1) when the word 0x200011a0 is 0, else 0x08023558(obj, 1)
@   word 0x200001e4 = 0x0802122c(A), placed (9, 0x68, 0), source selected by the
@   word 0x20001154: 0 gives 0x0803cdc4, 1 gives 0x0803cff4, 2 gives 0x0803d224,
@   other values set none
@ Loop i = 0..3: H = 0x0802122c(root) stored at 0x200059e8[i]; I = 0x08021f5c(H)
@ kept in a stack slot (sp+8+4*i); 0x080266ac(I, 0x0802ce5c, 0);
@ 0x080228d0(I, "%s", word[0x20000224 + word[0x2000115c]*16 + 4*i]); I placed
@ (9, 0, -11); J = 0x08021f5c(H) stored at 0x200059f8[i], placed (9, 0, 12),
@ 0x080266ac(J, 0x0802ce5c, 0).
@ Then 0x200059e8[0..3] are placed with 0x08023170(obj, 5, x, 0) for x = -120,
@ -40, 40, 120; then fn_0800da6c is called.
@ Words 0x200001f4 and 0x200001f8 = 0x0802122c(root), placed (7, 10, -40) and
@ (7, 10, 30), sources 0x0803b15c and 0x0803c1a4; words 0x200001e8 =
@ 0x0802122c(object of 0x200001f4) and 0x200001ec = 0x0802122c(object of
@ 0x200001f8), each placed (9, 0, 10).
@ Words 0x2000021c and 0x20000220 = 0x0802122c(root), placed (9, 134, -26) and
@ (9, 134, 42).
@ Array 0x200059a8[2][8]: each element = 0x0802122c(root), placed (8, 0, -40)
@ for row 0 and (8, 0, 30) for row 1.
@ Switch on the word 0x20001148: values 1, 2, 3, 4 store the value to the byte
@ 0x200011e4 and to the word 0x200011e8 and set the sources of 0x200001fc and
@ 0x200001e8 to (0x0803da44, 0x0803d2fc), (0x0803dd04, 0x0803d3d4), (0x0803de64,
@ 0x0803d584), (0x0803dfc4, 0x0803d8e4); any other value sets only the source of
@ 0x200001fc to 0x0803dba4.
@ Ends with fn_0800c848(word 0x200001d8) and fn_0800f854().
@ r6 holds 0x2000057c (+0xbcc = 0x20001148) for the first part of the body.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ca2c,"ax",%progbits
	.p2align 2
	.global fn_0800ca2c
	.thumb_func
	.type fn_0800ca2c, %function
fn_0800ca2c:
	push.w	{r4, r5, r6, r7, r8, r9, r10, r11, lr}
	ldr	r6, .L0800cde0
	sub	sp, #0x24
	mov.w	r10, #1
	str.w	r10, [r6, #0xbec]
	addw	r6, r6, #0xbcc
	bl	fn_08009f10
	ldr	r4, .L0800cde4
	movs	r2, #1
	lsls	r1, r2, #13
	mov	r0, r4
	bl	fn_08008350
	movs	r2, #1
	lsls	r1, r2, #12
	mov	r0, r4
	bl	fn_08008350
	bl	fn_0800b164
	movs	r0, #0
	str	r0, [r6, #0x60]
	str	r0, [r6, #0x5c]
	str	r0, [r6, #0x6c]
	bl	fn_08023678
	ldr	r4, .L0800cde8
	movs	r2, #0
	mov	r1, r2
	str	r0, [r4, #4]
	mov	r0, r2
	bl	rgb_to_565_0801d7c2
	str	r0, [sp]
	ldrh.w	r1, [sp]
	movs	r2, #0
	ldr	r0, [r4, #4]
	bl	fn_0802657a
	movs	r1, #0
	ldr	r0, [r4, #4]
	bl	fn_08026380
	ldr	r0, [r4, #4]
	bl	fn_0801ddd0
	ldr	r0, [r4, #4]
	bl	fn_0802122c
	movs	r3, #0
	mov	r5, r0
	mov	r2, r3
	movs	r1, #2
	bl	fn_08023170
	ldr	r1, .L0800cdec
	mov	r0, r5
	bl	fn_08021c14
	mov	r0, r5
	bl	fn_0802122c
	movs	r3, #0
	mvn	r2, #0x8e
	movs	r1, #9
	str	r0, [r4, #0x28]
	bl	fn_08023170
	mov	r0, r5
	bl	fn_08021f5c
	movs	r3, #2
	mvn	r2, #0x5f
	movs	r1, #9
	str	r0, [r4, #0x1c]
	bl	fn_08023170
	movs	r2, #0
	ldr	r1, .L0800cdf0
	ldr	r0, [r4, #0x1c]
	bl	fn_080266ac
	ldr	r0, [r6, #0x14]
	add.w	r1, r4, #0x84
	add.w	r0, r0, r0, lsl #1
	add.w	r0, r1, r0, lsl #3
	ldr	r1, [r6]
	ldr.w	r2, [r0, r1, lsl #2]
	adr	r1, .L0800cdf4
	ldr	r0, [r4, #0x1c]
	bl	fn_080228d0
	mov	r0, r5
	bl	fn_0802122c
	movs	r3, #0
	mvn	r2, #0x25
	movs	r1, #9
	str	r0, [r4, #8]
	bl	fn_08023170
	ldr	r1, .L0800cdf8
	ldr	r0, [r4, #8]
	bl	fn_08021c14
	movs	r1, #1
	ldr	r0, [r4, #8]
	bl	fn_08023050
	mov	r0, r5
	bl	fn_0802122c
	movs	r3, #1
	movs	r2, #0xa
	movs	r1, #9
	str	r0, [r4, #0xc]
	bl	fn_08023170
	ldr	r0, [r6, #8]
	subw	r6, r6, #0xbcc
	cbz	r0, .L0800cb44
	cmp	r0, #1
	beq.n	.L0800cb52
	cmp	r0, #2
	beq.n	.L0800cb60
	b.n	.L0800cb6e
.L0800cb44:
	ldr.w	r0, [r6, #0xbe0]
	cbz	r0, .L0800cb4e
	ldr	r1, .L0800cdfc
	b.n	.L0800cb68
.L0800cb4e:
	ldr	r1, .L0800ce00
	b.n	.L0800cb68
.L0800cb52:
	ldr.w	r0, [r6, #0xbe0]
	cbz	r0, .L0800cb5c
	ldr	r1, .L0800ce04
	b.n	.L0800cb68
.L0800cb5c:
	ldr	r1, .L0800ce08
	b.n	.L0800cb68
.L0800cb60:
	ldr.w	r0, [r6, #0xbe0]
	cbz	r0, .L0800cb9c
	ldr	r1, .L0800ce0c
.L0800cb68:
	ldr	r0, [r4, #0xc]
	bl	fn_08021c14
.L0800cb6e:
	mov	r0, r5
	bl	fn_0802122c
	movs	r3, #0
	movs	r2, #0x3a
	movs	r1, #9
	str	r0, [r4, #0x2c]
	bl	fn_08023170
	ldr	r1, .L0800ce10
	ldr	r0, [r4, #0x2c]
	bl	fn_08021c14
	ldr.w	r0, [r6, #0xc24]
	mov.w	r1, #1
	cmp	r0, #0
	ldr	r0, [r4, #0x2c]
	beq.n	.L0800cba0
	bl	fn_08023558
	b.n	.L0800cba4
.L0800cb9c:
	ldr	r1, .L0800ce14
	b.n	.L0800cb68
.L0800cba0:
	bl	fn_08023050
.L0800cba4:
	mov	r0, r5
	bl	fn_0802122c
	movs	r3, #0
	movs	r2, #0x68
	movs	r1, #9
	str	r0, [r4, #0x10]
	bl	fn_08023170
	ldr.w	r0, [r6, #0xbd8]
	cbz	r0, .L0800cbc6
	cmp	r0, #1
	beq.n	.L0800cbca
	cmp	r0, #2
	beq.n	.L0800cbce
	b.n	.L0800cbd6
.L0800cbc6:
	ldr	r1, .L0800ce18
	b.n	.L0800cbd0
.L0800cbca:
	ldr	r1, .L0800ce1c
	b.n	.L0800cbd0
.L0800cbce:
	ldr	r1, .L0800ce20
.L0800cbd0:
	ldr	r0, [r4, #0x10]
	bl	fn_08021c14
.L0800cbd6:
	ldr.w	r8, .L0800ce24
	movs	r5, #0
	add	r7, sp, #8
	add.w	r11, r8, #0x10
	mov	r9, r6
.L0800cbe4:
	ldr	r0, [r4, #4]
	bl	fn_0802122c
	mov	r6, r8
	str.w	r0, [r8, r5, lsl #2]
	bl	fn_08021f5c
	str.w	r0, [r7, r5, lsl #2]
	movs	r2, #0
	ldr	r1, .L0800cdf0
	bl	fn_080266ac
	ldr	r0, .L0800cde8
	ldr.w	r1, [r9, #0xbe0]
	adds	r0, #0x50
	add.w	r0, r0, r1, lsl #4
	adr	r1, .L0800cdf4
	ldr.w	r2, [r0, r5, lsl #2]
	ldr.w	r0, [r7, r5, lsl #2]
	bl	fn_080228d0
	ldr.w	r0, [r7, r5, lsl #2]
	mvn	r3, #0xa
	movs	r2, #0
	movs	r1, #9
	bl	fn_08023170
	ldr.w	r0, [r6, r5, lsl #2]
	bl	fn_08021f5c
	mov	r6, r11
	str.w	r0, [r11, r5, lsl #2]
	movs	r3, #0xc
	movs	r2, #0
	movs	r1, #9
	bl	fn_08023170
	ldr.w	r0, [r6, r5, lsl #2]
	movs	r2, #0
	ldr	r1, .L0800cdf0
	bl	fn_080266ac
	.inst.n	0x1c6d	@ adds r5, r5, #1
	cmp	r5, #4
	blt.n	.L0800cbe4
	mov	r5, r8
	movs	r3, #0
	mvn	r2, #0x77
	movs	r1, #5
	ldr.w	r0, [r8]
	bl	fn_08023170
	mvn	r6, #0x27
	movs	r3, #0
	mov	r2, r6
	movs	r1, #5
	ldr	r0, [r5, #4]
	bl	fn_08023170
	movs	r3, #0
	movs	r2, #0x28
	movs	r1, #5
	ldr	r0, [r5, #8]
	bl	fn_08023170
	movs	r3, #0
	movs	r2, #0x78
	movs	r1, #5
	ldr	r0, [r5, #0xc]
	bl	fn_08023170
	bl	fn_0800da6c
	ldr	r0, [r4, #4]
	bl	fn_0802122c
	str	r0, [r4, #0x20]
	ldr	r0, [r4, #4]
	bl	fn_0802122c
	str	r0, [r4, #0x24]
	mov	r3, r6
	movs	r2, #0xa
	movs	r1, #7
	ldr	r0, [r4, #0x20]
	bl	fn_08023170
	movs	r3, #0x1e
	movs	r2, #0xa
	movs	r1, #7
	ldr	r0, [r4, #0x24]
	bl	fn_08023170
	ldr	r1, .L0800ce28
	ldr	r0, [r4, #0x20]
	bl	fn_08021c14
	ldr	r1, .L0800ce2c
	ldr	r0, [r4, #0x24]
	bl	fn_08021c14
	ldr	r0, [r4, #0x20]
	bl	fn_0802122c
	str	r0, [r4, #0x14]
	ldr	r0, [r4, #0x24]
	bl	fn_0802122c
	str	r0, [r4, #0x18]
	movs	r3, #0xa
	movs	r2, #0
	movs	r1, #9
	ldr	r0, [r4, #0x14]
	bl	fn_08023170
	movs	r3, #0xa
	movs	r2, #0
	movs	r1, #9
	ldr	r0, [r4, #0x18]
	bl	fn_08023170
	ldr	r0, [r4, #4]
	bl	fn_0802122c
	ldr	r5, .L0800cde8
	adds	r5, #0x48
	str	r0, [r5]
	ldr	r0, [r4, #4]
	bl	fn_0802122c
	str	r0, [r5, #4]
	mvn	r3, #0x19
	movs	r2, #0x86
	movs	r1, #9
	ldr	r0, [r5]
	bl	fn_08023170
	movs	r3, #0x2a
	movs	r2, #0x86
	movs	r1, #9
	ldr	r0, [r5, #4]
	bl	fn_08023170
	ldr.w	r11, .L0800ce24
	movs	r5, #0
	sub.w	r11, r11, #0x40
	mov	r8, r6
.L0800cd2c:
	movs	r6, #0
	add.w	r7, r11, r5, lsl #5
.L0800cd32:
	ldr	r0, [r4, #4]
	bl	fn_0802122c
	str.w	r0, [r7, r6, lsl #2]
	cbz	r5, .L0800cd84
	movs	r3, #0x1e
.L0800cd40:
	movs	r2, #0
	movs	r1, #8
	bl	fn_08023170
	.inst.n	0x1c76	@ adds r6, r6, #1
	cmp	r6, #8
	blt.n	.L0800cd32
	.inst.n	0x1c6d	@ adds r5, r5, #1
	cmp	r5, #2
	blt.n	.L0800cd2c
	ldr.w	r1, [r9, #0xbcc]
	mov	r0, r9
	cmp	r1, #1
	beq.n	.L0800cd88
	cmp	r1, #2
	beq.n	.L0800cd9c
	cmp	r1, #3
	beq.n	.L0800cdb4
	cmp	r1, #4
	beq.n	.L0800cdca
	ldr	r1, .L0800ce30
	ldr.w	r0, [r4, #0x28]
.L0800cd70:
	bl	fn_08021c14
	ldr	r0, [r4, #4]
	bl	fn_0800c848
	bl	fn_0800f854
	add	sp, #0x24
	pop.w	{r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L0800cd84:
	mov	r3, r8
	b.n	.L0800cd40
.L0800cd88:
	strb.w	r10, [r0, #0xc68]
	str.w	r10, [r9, #0xc6c]
	ldr	r1, .L0800ce34
	ldr	r0, [r4, #0x28]
	bl	fn_08021c14
	ldr	r1, .L0800ce38
	b.n	.L0800cdb0
.L0800cd9c:
	movs	r1, #2
	strb.w	r1, [r0, #0xc68]
	str.w	r1, [r9, #0xc6c]
	ldr	r1, .L0800ce3c
	ldr	r0, [r4, #0x28]
	bl	fn_08021c14
	ldr	r1, .L0800ce40
.L0800cdb0:
	ldr	r0, [r4, #0x14]
	b.n	.L0800cd70
.L0800cdb4:
	movs	r1, #3
	strb.w	r1, [r0, #0xc68]
	str.w	r1, [r9, #0xc6c]
	ldr	r1, .L0800ce44
	ldr	r0, [r4, #0x28]
	bl	fn_08021c14
	ldr	r1, .L0800ce48
	b.n	.L0800cdb0
.L0800cdca:
	movs	r1, #4
	strb.w	r1, [r0, #0xc68]
	str.w	r1, [r9, #0xc6c]
	ldr	r1, .L0800ce4c
	ldr	r0, [r4, #0x28]
	bl	fn_08021c14
	ldr	r1, .L0800ce50
	b.n	.L0800cdb0
.L0800cde0:
	.word	0x2000057c
.L0800cde4:
	.word	0x40010c00
.L0800cde8:
	.word	0x200001d4
.L0800cdec:
	.word	d_08044150
.L0800cdf0:
	.word	d_0802ce5c
.L0800cdf4:
	.asciz	"%s"
	.byte	0x00	@ padding
.L0800cdf8:
	.word	d_0803c404
.L0800cdfc:
	.word	d_08040f10
.L0800ce00:
	.word	d_0803c690
.L0800ce04:
	.word	d_08041184
.L0800ce08:
	.word	d_0803c91c
.L0800ce0c:
	.word	d_08040c9c
.L0800ce10:
	.word	d_0803e250
.L0800ce14:
	.word	d_0803cba8
.L0800ce18:
	.word	d_0803cdc4
.L0800ce1c:
	.word	d_0803cff4
.L0800ce20:
	.word	d_0803d224
.L0800ce24:
	.word	0x200059e8
.L0800ce28:
	.word	d_0803b15c
.L0800ce2c:
	.word	d_0803c1a4
.L0800ce30:
	.word	d_0803dba4
.L0800ce34:
	.word	d_0803da44
.L0800ce38:
	.word	d_0803d2fc
.L0800ce3c:
	.word	d_0803dd04
.L0800ce40:
	.word	d_0803d3d4
.L0800ce44:
	.word	d_0803de64
.L0800ce48:
	.word	d_0803d584
.L0800ce4c:
	.word	d_0803dfc4
.L0800ce50:
	.word	d_0803d8e4

@ ----------------------------------------------------------------------------
@ fn_0800ce54 - no parameters; ends with a tail call to 0x080269f0 (after
@ popping r1..r7 and lr), so the return value and the return to the caller are
@ those of 0x080269f0.
@ Calls 0x08009ba0(0x50, 0x6a, 0xa0, 0x1b, stack: 0, 0, 0x08046c9c). Then a loop
@ r5 = 0.. while the signed word 0x20001158 (0x2000057c+0xbdc) is greater than
@ r5: 0x08011c68(2), 0x08009e60(r5).
@ Three loops with r6 = 1..0x69 (r5 = 1 and r4 = 0 from 0x0800ce8c); each pass
@ calls 0x08009ba0(x, r6-1, w, 8, stack: 1, 0, data), then 0x08009ba0(x, r6, w,
@ 8, stack: 0, 0, data), then 0x08011c68(2):
@   x = 0xdd, w = 8, data = 0x08048e5c
@   x = 0xe5, w = 6, data = 0x08048edc
@   x = 0xeb, w = 5, data = 0x08048f3c
@ Finally 0x08009ba0(0x50, 0x69, 0xa0, 0x1c, stack: 0, 1, 0x0804499c),
@ 0x08011c68(0x1f4), 0x08021e98(), then pop and b.w 0x080269f0.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800ce54,"ax",%progbits
	.p2align 2
	.global fn_0800ce54
	.thumb_func
	.type fn_0800ce54, %function
fn_0800ce54:
	push	{r1, r2, r3, r4, r5, r6, r7, lr}
	ldr	r0, .L0800cf50
	movs	r4, #0
	str	r4, [sp]
	strd	r4, r0, [sp, #4]
	movs	r3, #0x1b
	movs	r2, #0xa0
	movs	r1, #0x6a
	movs	r0, #0x50
	bl	fn_08009ba0
	movs	r5, #0
	ldr	r6, .L0800cf54
	b.n	.L0800ce80
.L0800ce72:
	movs	r0, #2
	bl	fn_08011c68
	mov	r0, r5
	bl	fn_08009e60
	.inst.n	0x1c6d	@ adds r5, r5, #1
.L0800ce80:
	ldr.w	r0, [r6, #0xbdc]
	cmp	r0, r5
	bgt.n	.L0800ce72
	movs	r6, #1
	ldr	r7, .L0800cf58
	mov	r5, r6
.L0800ce8e:
	strd	r5, r4, [sp]
	movs	r3, #8
	mov	r2, r3
	subs	r1, r6, #1
	movs	r0, #0xdd
	str	r7, [sp, #8]
	bl	fn_08009ba0
	str	r4, [sp]
	strd	r4, r7, [sp, #4]
	movs	r3, #8
	mov	r2, r3
	mov	r1, r6
	movs	r0, #0xdd
	bl	fn_08009ba0
	movs	r0, #2
	bl	fn_08011c68
	.inst.n	0x1c76	@ adds r6, r6, #1
	cmp	r6, #0x6a
	blt.n	.L0800ce8e
	ldr	r7, .L0800cf5c
	movs	r6, #1
.L0800cec2:
	strd	r5, r4, [sp]
	movs	r3, #8
	movs	r2, #6
	subs	r1, r6, #1
	movs	r0, #0xe5
	str	r7, [sp, #8]
	bl	fn_08009ba0
	str	r4, [sp]
	strd	r4, r7, [sp, #4]
	movs	r3, #8
	movs	r2, #6
	mov	r1, r6
	movs	r0, #0xe5
	bl	fn_08009ba0
	movs	r0, #2
	bl	fn_08011c68
	.inst.n	0x1c76	@ adds r6, r6, #1
	cmp	r6, #0x6a
	blt.n	.L0800cec2
	ldr	r7, .L0800cf60
	movs	r6, #1
.L0800cef6:
	strd	r5, r4, [sp]
	movs	r3, #8
	movs	r2, #5
	subs	r1, r6, #1
	movs	r0, #0xeb
	str	r7, [sp, #8]
	bl	fn_08009ba0
	str	r4, [sp]
	strd	r4, r7, [sp, #4]
	movs	r3, #8
	movs	r2, #5
	mov	r1, r6
	movs	r0, #0xeb
	bl	fn_08009ba0
	movs	r0, #2
	bl	fn_08011c68
	.inst.n	0x1c76	@ adds r6, r6, #1
	cmp	r6, #0x6a
	blt.n	.L0800cef6
	ldr	r0, .L0800cf64
	str	r4, [sp]
	strd	r5, r0, [sp, #4]
	movs	r3, #0x1c
	movs	r2, #0xa0
	movs	r1, #0x69
	movs	r0, #0x50
	bl	fn_08009ba0
	mov.w	r0, #0x1f4
	bl	fn_08011c68
	bl	fn_08021e98
	pop.w	{r1, r2, r3, r4, r5, r6, r7, lr}
	b.w	fn_080269f0
	.short	0x0000	@ padding
.L0800cf50:
	.word	d_08046c9c
.L0800cf54:
	.word	0x2000057c
.L0800cf58:
	.word	d_08048e5c
.L0800cf5c:
	.word	d_08048edc
.L0800cf60:
	.word	d_08048f3c
.L0800cf64:
	.word	d_0804499c

@ ----------------------------------------------------------------------------
@ fn_0800cf68 - r0 = create flag, r1 = number (kept in r8).
@ When r0 is non-zero it builds the pop-up objects: calls 0x0801dccc, 0x0801dd5c
@ and 0x0801dd38 and creates objects with 0x08023678 stored to the words
@ 0x20000290, 0x20000294, 0x20000298 and 0x2000029c, and objects with 0x08021f5c
@ stored to 0x200002a0 and 0x200002a4 (r4 = 0x2000028c, the words are at
@ offsets 4..0x18). Sizes (0x080263a8): 0x140 x 0xf0, 0xa0 x 0x50, 0xa0 x 0x1e,
@ 0xa0 x 0x32. Positions and styles are set with 0x08023170, 0x08026380,
@ 0x080265be, 0x08026680, 0x0801d822, 0x0802657a, 0x08026592(.., 0xcc),
@ 0x08026662, 0x0802666c, 0x08026676, 0x08026658, 0x080265c8, 0x08026694 and
@ 0x080266ac(.., 0x0802f0d8, 0); the text of the object 0x200002a0 is set with
@ 0x0802285c from the pointer table at 0x200002a8, indexed by the word
@ 0x2000115c (0x2000057c+0xbe0).
@ In every case it ends by tail-calling 0x080228d0(word 0x200002a4, "%d", r1).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800cf68,"ax",%progbits
	.p2align 2
	.global fn_0800cf68
	.thumb_func
	.type fn_0800cf68, %function
fn_0800cf68:
	push.w	{r4, r5, r6, r7, r8, lr}
	ldr	r4, .L0800d13c
	mov	r8, r1
	cmp	r0, #0
	beq.n	.L0800d06e
	bl	fn_0801dccc
	bl	fn_0801dd5c
	bl	fn_08023678
	str	r0, [r4, #4]
	bl	fn_0801dccc
	bl	fn_0801dd38
	bl	fn_08023678
	str	r0, [r4, #8]
	bl	fn_08023678
	str	r0, [r4, #0xc]
	ldr	r0, [r4, #8]
	bl	fn_08023678
	str	r0, [r4, #0x10]
	ldr	r0, [r4, #0xc]
	bl	fn_08021f5c
	str	r0, [r4, #0x14]
	ldr	r0, [r4, #0x10]
	bl	fn_08021f5c
	str	r0, [r4, #0x18]
	movs	r2, #0xf0
	mov.w	r1, #0x140
	ldr	r0, [r4, #4]
	bl	fn_080263a8
	movs	r2, #0x50
	movs	r1, #0xa0
	ldr	r0, [r4, #8]
	bl	fn_080263a8
	movs	r2, #0x1e
	movs	r1, #0xa0
	ldr	r0, [r4, #0xc]
	bl	fn_080263a8
	movs	r2, #0x32
	movs	r1, #0xa0
	ldr	r0, [r4, #0x10]
	bl	fn_080263a8
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	ldr	r0, [r4, #8]
	bl	fn_08023170
	movs	r3, #0
	mov	r2, r3
	movs	r1, #2
	ldr	r0, [r4, #0xc]
	bl	fn_08023170
	movs	r3, #0
	mov	r2, r3
	movs	r1, #5
	ldr	r0, [r4, #0x10]
	bl	fn_08023170
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	ldr	r0, [r4, #0x14]
	bl	fn_08023170
	movs	r3, #0
	mov	r2, r3
	movs	r1, #9
	ldr	r0, [r4, #0x18]
	bl	fn_08023170
	movs	r1, #0
	ldr	r0, [r4, #4]
	bl	fn_08026380
	movs	r1, #0
	ldr	r0, [r4, #8]
	bl	fn_08026380
	movs	r1, #0
	ldr	r0, [r4, #0xc]
	bl	fn_08026380
	movs	r1, #0
	ldr	r0, [r4, #0x10]
	bl	fn_08026380
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r4, #4]
	bl	fn_080265be
	movs	r2, #0
	movs	r1, #1
	ldr	r0, [r4, #8]
	bl	fn_080265be
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r4, #0xc]
	bl	fn_080265be
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r4, #0x10]
	bl	fn_080265be
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r4, #4]
	bl	fn_08026680
	movs	r2, #0
	movs	r1, #5
	ldr	r0, [r4, #8]
	b.n	.L0800d070
.L0800d06e:
	b.n	.L0800d12e
.L0800d070:
	bl	fn_08026680
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r4, #0xc]
	bl	fn_08026680
	movs	r2, #0
	mov	r1, r2
	ldr	r0, [r4, #0x10]
	bl	fn_08026680
	movs	r2, #0x32
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d822
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r4, #4]
	bl	fn_0802657a
	movs	r2, #0
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d822
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r4, #0x10]
	bl	fn_0802657a
	movs	r2, #0
	movs	r1, #0xcc
	ldr	r0, [r4, #4]
	bl	fn_08026592
	movs	r6, #0
	ldr	r7, [r4, #8]
	mov	r5, r6
	mov	r2, r5
	mov	r1, r6
	mov	r0, r7
	bl	fn_08026662
	mov	r2, r5
	mov	r1, r6
	mov	r0, r7
	bl	fn_0802666c
	mov	r2, r5
	mov	r1, r6
	mov	r0, r7
	bl	fn_08026676
	mov	r2, r5
	mov	r1, r6
	mov	r0, r7
	bl	fn_08026658
	movs	r2, #0
	movs	r1, #1
	ldr	r0, [r4, #8]
	bl	fn_080265c8
	movs	r2, #0
	mov	r1, r2
	mov	r0, r2
	bl	rgb_to_565_0801d822
	mov	r1, r0
	movs	r2, #0
	ldr	r0, [r4, #0x14]
	bl	fn_08026694
	movs	r2, #0
	ldr	r1, .L0800d140
	ldr	r0, [r4, #0x14]
	bl	fn_080266ac
	movs	r2, #0
	ldr	r1, .L0800d140
	ldr	r0, [r4, #0x18]
	bl	fn_080266ac
	ldr	r0, .L0800d144
	add.w	r1, r4, #0x1c
	ldr.w	r0, [r0, #0xbe0]
	ldr.w	r1, [r1, r0, lsl #2]
	ldr	r0, [r4, #0x14]
	bl	fn_0802285c
.L0800d12e:
	mov	r2, r8
	ldr	r0, [r4, #0x18]
	pop.w	{r4, r5, r6, r7, r8, lr}
	adr	r1, .L0800d148
	b.w	fn_080228d0
.L0800d13c:
	.word	0x2000028c
.L0800d140:
	.word	d_0802f0d8
.L0800d144:
	.word	0x2000057c
.L0800d148:
	.asciz	"%d"
	.byte	0x00	@ padding

@ ----------------------------------------------------------------------------
@ fn_0800d14c - r0 = row (0 or 1), r1 = pointer to a text.
@ Stores 14 image pointers into a stack table: 0x0802ff28, 0x08030858,
@ 0x08031188, 0x08031ab8, 0x080323e8, 0x08032d18, 0x08033648, 0x08033f78,
@ 0x080348a8, 0x080351d8 (glyphs 0..9), 0x08036970 (index 10), 0x080352b4
@ (index 11), 0x08035710 (index 12), 0x08036040 (index 13).
@ Only when string_length(text) (0x08007124) returns 2..7: x = (6 - length) *
@ 0x24 - 0xcc. For each of 7 positions i = 0..6: when byte i of the text is "."
@ it subtracts 0x1b from x before drawing; the table index is chosen from the
@ byte ("0".."9" = 0..9, "L" = 10, "." = 11, "-" = 12, anything else = 13);
@ then 0x08021c14(object at 0x200059a8[row * 8 + i], image) and
@ 0x08026700(object, sxth(x)); afterwards x += 0x1e after a "." and x += 0x24
@ otherwise.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800d14c,"ax",%progbits
	.p2align 2
	.global fn_0800d14c
	.thumb_func
	.type fn_0800d14c, %function
fn_0800d14c:
	push.w	{r4, r5, r6, r7, r8, lr}
	sub	sp, #0x38
	mov	r7, r0
	ldr	r0, .L0800d258
	str	r0, [sp]
	ldr	r0, .L0800d25c
	str	r0, [sp, #4]
	ldr	r0, .L0800d260
	str	r0, [sp, #8]
	ldr	r0, .L0800d264
	str	r0, [sp, #0xc]
	ldr	r0, .L0800d268
	str	r0, [sp, #0x10]
	ldr	r0, .L0800d26c
	str	r0, [sp, #0x14]
	ldr	r0, .L0800d270
	str	r0, [sp, #0x18]
	ldr	r0, .L0800d274
	str	r0, [sp, #0x1c]
	ldr	r0, .L0800d278
	str	r0, [sp, #0x20]
	ldr	r0, .L0800d27c
	str	r0, [sp, #0x24]
	ldr	r0, .L0800d280
	str	r0, [sp, #0x28]
	ldr	r0, .L0800d284
	str	r0, [sp, #0x2c]
	ldr	r0, .L0800d288
	str	r0, [sp, #0x30]
	ldr	r0, .L0800d28c
	str	r0, [sp, #0x34]
	mov	r6, r1
	mov	r0, r1
	bl	string_length
	subs	r2, r0, #2
	mvn	r1, #0xcb
	cmp	r2, #6
	bcs.n	.L0800d218
	rsb.w	r0, r0, #6
	add.w	r0, r0, r0, lsl #3
	add.w	r5, r1, r0, lsl #2
	ldr	r0, .L0800d290
	movs	r4, #0
	mov	r8, sp
	add.w	r7, r0, r7, lsl #5
.L0800d1b4:
	ldrb	r0, [r6, r4]
	cmp	r0, #0x2e
	bne.n	.L0800d1bc
	subs	r5, #0x1b
.L0800d1bc:
	cmp	r0, #0x30
	beq.n	.L0800d21e
	cmp	r0, #0x31
	beq.n	.L0800d222
	cmp	r0, #0x32
	beq.n	.L0800d226
	cmp	r0, #0x33
	beq.n	.L0800d22a
	cmp	r0, #0x34
	beq.n	.L0800d22e
	cmp	r0, #0x35
	beq.n	.L0800d232
	cmp	r0, #0x36
	beq.n	.L0800d236
	cmp	r0, #0x37
	beq.n	.L0800d23a
	cmp	r0, #0x38
	beq.n	.L0800d23e
	cmp	r0, #0x39
	beq.n	.L0800d242
	cmp	r0, #0x4c
	beq.n	.L0800d246
	cmp	r0, #0x2e
	beq.n	.L0800d24a
	cmp	r0, #0x2d
	beq.n	.L0800d24e
	movs.w	r1, #0xd
.L0800d1f4:
	ldr.w	r0, [r7, r4, lsl #2]
	ldr.w	r1, [r8, r1, lsl #2]
	bl	fn_08021c14
	ldr.w	r0, [r7, r4, lsl #2]
	sxth	r1, r5
	bl	fn_08026700
	ldrb	r0, [r6, r4]
	cmp	r0, #0x2e
	beq.n	.L0800d252
	adds	r5, #0x24
.L0800d212:
	.inst.n	0x1c64	@ adds r4, r4, #1
	cmp	r4, #7
	blt.n	.L0800d1b4
.L0800d218:
	add	sp, #0x38
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0800d21e:
	movs	r1, #0
	b.n	.L0800d1f4
.L0800d222:
	movs	r1, #1
	b.n	.L0800d1f4
.L0800d226:
	movs	r1, #2
	b.n	.L0800d1f4
.L0800d22a:
	movs	r1, #3
	b.n	.L0800d1f4
.L0800d22e:
	movs	r1, #4
	b.n	.L0800d1f4
.L0800d232:
	movs	r1, #5
	b.n	.L0800d1f4
.L0800d236:
	movs	r1, #6
	b.n	.L0800d1f4
.L0800d23a:
	movs	r1, #7
	b.n	.L0800d1f4
.L0800d23e:
	movs	r1, #8
	b.n	.L0800d1f4
.L0800d242:
	movs	r1, #9
	b.n	.L0800d1f4
.L0800d246:
	movs	r1, #0xa
	b.n	.L0800d1f4
.L0800d24a:
	movs	r1, #0xb
	b.n	.L0800d1f4
.L0800d24e:
	movs	r1, #0xc
	b.n	.L0800d1f4
.L0800d252:
	adds	r5, #0x1e
	b.n	.L0800d212
	.short	0x0000	@ padding
.L0800d258:
	.word	d_0802ff28
.L0800d25c:
	.word	d_08030858
.L0800d260:
	.word	d_08031188
.L0800d264:
	.word	d_08031ab8
.L0800d268:
	.word	d_080323e8
.L0800d26c:
	.word	d_08032d18
.L0800d270:
	.word	d_08033648
.L0800d274:
	.word	d_08033f78
.L0800d278:
	.word	d_080348a8
.L0800d27c:
	.word	d_080351d8
.L0800d280:
	.word	d_08036970
.L0800d284:
	.word	d_080352b4
.L0800d288:
	.word	d_08035710
.L0800d28c:
	.word	d_08036040
.L0800d290:
	.word	0x200059a8

@ ----------------------------------------------------------------------------
@ fn_0800d294 - no parameters. Updates the second display row (row 1).
@ r6 = 0x2000057c, r8 = 0x200001d4, r5 = r6+0x4800 (0x2000 5d7c, base of the
@ float values), r4 = r8+0x48 (object table at 0x2000021c).
@ Zeroes the five stack words [sp+0..0x10]. The switch is on the word 0x200011e8
@ (0x2000057c+0xc6c):
@   0: 0x08021c14(word 0x200001ec, image 0x0803d2fc), then
@      0x0800e028(abs(float 0x200050b8), sp+4, sp+0xc, sp)
@   1: 0x08021c14(0x200001ec, image 0x0803d80c), sets the word 0x20001198 to 2
@      around 0x0800e028(float 0x200050c8, ...) and then writes 0 back
@   2: 0x08021c14(0x200001ec, image 0x0803d4ac), 0x0800dd44(float 0x200050d4,
@      ...)
@   3: 0x08021c14(0x200001ec, image 0x0803d734), 0x0800dd44(float 0x200050d0,
@      ...)
@   4: 0x08021c14(word 0x20000220, 0x08040a28), 0x08021c14(0x200001ec,
@      0x0803d65c), then 0x0800dfc4(float 0x200050cc, ...)
@ For the modes 0 and 1 the unit index [sp] = 4..7 selects the images 0x08036b24,
@ 0x08036cd8, 0x08036e8c, 0x08037040 for the object 0x20000220 (word at r4+4).
@ Then calls fn_0800d14c(1, text at sp+4) and, when the unit index is 0,
@ 0x08023050(0x20000220, 1); otherwise, when the word 0x20001168 equals 1,
@ 0x08023558(0x20000220, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800d294,"ax",%progbits
	.p2align 2
	.global fn_0800d294
	.thumb_func
	.type fn_0800d294, %function
fn_0800d294:
	push.w	{r4, r5, r6, r7, r8, lr}
	sub	sp, #0x18
	movs	r7, #0
	ldr	r6, .L0800d3a8
	ldr.w	r8, .L0800d3ac
	str	r7, [sp]
	str	r7, [sp, #4]
	str	r7, [sp, #8]
	str	r7, [sp, #0xc]
	str	r7, [sp, #0x10]
	ldr.w	r1, [r6, #0xc6c]
	ldr.w	r0, [r8, #0x18]
	add.w	r5, r6, #0x4800
	add.w	r4, r8, #0x48
	cbz	r1, .L0800d2d0
	cmp	r1, #1
	beq.n	.L0800d314
	cmp	r1, #2
	beq.n	.L0800d33a
	cmp	r1, #3
	beq.n	.L0800d346
	cmp	r1, #4
	beq.n	.L0800d35c
	b.n	.L0800d37c
.L0800d2d0:
	ldr	r1, .L0800d3b0
	bl	fn_08021c14
	vldr	s0, [r5, #0x33c]
	mov	r2, sp
	add	r1, sp, #0xc
	vabs.f32	s0, s0
	add	r0, sp, #4
	bl	fn_0800e028
	b.n	.L0800d332
.L0800d2ea:
	ldr	r1, .L0800d3b4
	ldr	r0, [r4, #4]
	b.n	.L0800d30e
.L0800d2f0:
	cmp	r0, #5
	beq.n	.L0800d2fe
	cmp	r0, #6
	beq.n	.L0800d304
	cmp	r0, #7
	beq.n	.L0800d30a
	b.n	.L0800d37c
.L0800d2fe:
	ldr	r1, .L0800d3b8
	ldr	r0, [r4, #4]
	b.n	.L0800d30e
.L0800d304:
	ldr	r1, .L0800d3bc
	ldr	r0, [r4, #4]
	b.n	.L0800d30e
.L0800d30a:
	ldr	r1, .L0800d3c0
	ldr	r0, [r4, #4]
.L0800d30e:
	bl	fn_08021c14
	b.n	.L0800d37c
.L0800d314:
	ldr	r1, .L0800d3c4
	bl	fn_08021c14
	movs	r0, #2
	str.w	r0, [r6, #0xc1c]
	vldr	s0, [r5, #0x34c]
	mov	r2, sp
	add	r1, sp, #0xc
	add	r0, sp, #4
	bl	fn_0800e028
	str.w	r7, [r6, #0xc1c]
.L0800d332:
	ldr	r0, [sp]
	cmp	r0, #4
	bne.n	.L0800d2f0
	b.n	.L0800d2ea
.L0800d33a:
	ldr	r1, .L0800d3c8
	bl	fn_08021c14
	vldr	s0, [r5, #0x358]
	b.n	.L0800d350
.L0800d346:
	ldr	r1, .L0800d3cc
	bl	fn_08021c14
	vldr	s0, [r5, #0x354]
.L0800d350:
	mov	r2, sp
	add	r1, sp, #0xc
	add	r0, sp, #4
	bl	fn_0800dd44
	b.n	.L0800d37c
.L0800d35c:
	ldr	r1, .L0800d3d0
	ldr	r0, [r4, #4]
	bl	fn_08021c14
	ldr	r1, .L0800d3d4
	ldr.w	r0, [r8, #0x18]
	bl	fn_08021c14
	vldr	s0, [r5, #0x350]
	mov	r2, sp
	add	r1, sp, #0xc
	add	r0, sp, #4
	bl	fn_0800dfc4
.L0800d37c:
	add	r1, sp, #4
	movs	r0, #1
	bl	fn_0800d14c
	ldr	r0, [sp]
	cbz	r0, .L0800d39e
	ldr.w	r0, [r6, #0xbec]
	cmp	r0, #1
	bne.n	.L0800d398
	movs	r1, #1
	ldr	r0, [r4, #4]
	bl	fn_08023558
.L0800d398:
	add	sp, #0x18
	pop.w	{r4, r5, r6, r7, r8, pc}
.L0800d39e:
	movs	r1, #1
	ldr	r0, [r4, #4]
	bl	fn_08023050
	b.n	.L0800d398
.L0800d3a8:
	.word	0x2000057c
.L0800d3ac:
	.word	0x200001d4
.L0800d3b0:
	.word	d_0803d2fc
.L0800d3b4:
	.word	d_08036b24
.L0800d3b8:
	.word	d_08036cd8
.L0800d3bc:
	.word	d_08036e8c
.L0800d3c0:
	.word	d_08037040
.L0800d3c4:
	.word	d_0803d80c
.L0800d3c8:
	.word	d_0803d4ac
.L0800d3cc:
	.word	d_0803d734
.L0800d3d0:
	.word	d_08040a28
.L0800d3d4:
	.word	d_0803d65c

@ ----------------------------------------------------------------------------
@ fn_0800d3d8 - no parameters. Updates the first display row (row 0).
@ r4 = 0x2000021c (object of row 0). Zeroes the five stack words [sp+0..0x10].
@ The switch is on the signed byte 0x200011e4 (0x2000057c+0xc68):
@   4: 0x0800e028(float 0x200050c4, sp+4, sp+0xc, sp)
@   1: 0x0800e028(float 0x200050b8, ...)
@      (for 1 and 4 the unit index [sp] = 4..7 selects the images 0x08036b24,
@      0x08036cd8, 0x08036e8c, 0x08037040)
@   2: 0x0800db24(float 0x200050bc, ...); unit index 1..4 selects the images
@      0x080371f4, 0x080373a8, 0x0803756c, 0x08037720
@   3: 0x0800de2c(float 0x200050c0, ...); unit index 3..5 selects the images
@      0x080378d4, 0x08037a88, 0x08037c3c
@ The chosen image is set on the object 0x2000021c with 0x08021c14, then
@ fn_0800d14c(0, text at sp+4) is called, and 0x08023050(object, 1) when the
@ unit index is 0, otherwise 0x08023558(object, 1).
@ ----------------------------------------------------------------------------
	.section .text.fn_0800d3d8,"ax",%progbits
	.p2align 2
	.global fn_0800d3d8
	.thumb_func
	.type fn_0800d3d8, %function
fn_0800d3d8:
	push	{r4, lr}
	sub	sp, #0x18
	movs	r0, #0
	str	r0, [sp]
	str	r0, [sp, #4]
	str	r0, [sp, #8]
	str	r0, [sp, #0xc]
	str	r0, [sp, #0x10]
	ldr	r0, .L0800d4d8
	ldr	r4, .L0800d4dc
	ldrsb.w	r1, [r0, #0xc68]
	add.w	r0, r0, #0x4800
	cmp	r1, #4
	beq.n	.L0800d406
	cmp	r1, #1
	beq.n	.L0800d432
	cmp	r1, #2
	beq.n	.L0800d448
	cmp	r1, #3
	beq.n	.L0800d482
	b.n	.L0800d4b4
.L0800d406:
	vldr	s0, [r0, #0x348]
	b.n	.L0800d436
.L0800d40c:
	ldr	r1, .L0800d4e0
	ldr	r0, [r4]
	b.n	.L0800d4b0
.L0800d412:
	cmp	r0, #5
	beq.n	.L0800d420
	cmp	r0, #6
	beq.n	.L0800d426
	cmp	r0, #7
	beq.n	.L0800d42c
	b.n	.L0800d4b4
.L0800d420:
	ldr	r1, .L0800d4e4
	ldr	r0, [r4]
	b.n	.L0800d4b0
.L0800d426:
	ldr	r1, .L0800d4e8
	ldr	r0, [r4]
	b.n	.L0800d4b0
.L0800d42c:
	ldr	r1, .L0800d4ec
	ldr	r0, [r4]
	b.n	.L0800d4b0
.L0800d432:
	vldr	s0, [r0, #0x33c]
.L0800d436:
	mov	r2, sp
	add	r1, sp, #0xc
	add	r0, sp, #4
	bl	fn_0800e028
	ldr	r0, [sp]
	cmp	r0, #4
	bne.n	.L0800d412
	b.n	.L0800d40c
.L0800d448:
	vldr	s0, [r0, #0x340]
	mov	r2, sp
	add	r1, sp, #0xc
	add	r0, sp, #4
	bl	fn_0800db24
	ldr	r0, [sp]
	cmp	r0, #1
	beq.n	.L0800d46a
	cmp	r0, #2
	beq.n	.L0800d470
	cmp	r0, #3
	beq.n	.L0800d476
	cmp	r0, #4
	beq.n	.L0800d47c
	b.n	.L0800d4b4
.L0800d46a:
	ldr	r1, .L0800d4f0
	ldr	r0, [r4]
	b.n	.L0800d4b0
.L0800d470:
	ldr	r1, .L0800d4f4
	ldr	r0, [r4]
	b.n	.L0800d4b0
.L0800d476:
	ldr	r1, .L0800d4f8
	ldr	r0, [r4]
	b.n	.L0800d4b0
.L0800d47c:
	ldr	r1, .L0800d4fc
	ldr	r0, [r4]
	b.n	.L0800d4b0
.L0800d482:
	vldr	s0, [r0, #0x344]
	mov	r2, sp
	add	r1, sp, #0xc
	add	r0, sp, #4
	bl	fn_0800de2c
	ldr	r0, [sp]
	cmp	r0, #3
	beq.n	.L0800d4a0
	cmp	r0, #4
	beq.n	.L0800d4a6
	cmp	r0, #5
	beq.n	.L0800d4ac
	b.n	.L0800d4b4
.L0800d4a0:
	ldr	r1, .L0800d500
	ldr	r0, [r4]
	b.n	.L0800d4b0
.L0800d4a6:
	ldr	r1, .L0800d504
	ldr	r0, [r4]
	b.n	.L0800d4b0
.L0800d4ac:
	ldr	r1, .L0800d508
	ldr	r0, [r4]
.L0800d4b0:
	bl	fn_08021c14
.L0800d4b4:
	add	r1, sp, #4
	movs	r0, #0
	bl	fn_0800d14c
	ldr	r0, [sp]
	mov.w	r1, #1
	cmp	r0, #0
	ldr	r0, [r4]
	beq.n	.L0800d4d0
	bl	fn_08023558
.L0800d4cc:
	add	sp, #0x18
	pop	{r4, pc}
.L0800d4d0:
	bl	fn_08023050
	b.n	.L0800d4cc
	.short	0x0000	@ padding
.L0800d4d8:
	.word	0x2000057c
.L0800d4dc:
	.word	0x2000021c
.L0800d4e0:
	.word	d_08036b24
.L0800d4e4:
	.word	d_08036cd8
.L0800d4e8:
	.word	d_08036e8c
.L0800d4ec:
	.word	d_08037040
.L0800d4f0:
	.word	d_080371f4
.L0800d4f4:
	.word	d_080373a8
.L0800d4f8:
	.word	d_0803756c
.L0800d4fc:
	.word	d_08037720
.L0800d500:
	.word	d_080378d4
.L0800d504:
	.word	d_08037a88
.L0800d508:
	.word	d_08037c3c
