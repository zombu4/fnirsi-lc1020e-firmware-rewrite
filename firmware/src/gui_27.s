@ gui_27.s - GUI object set-up function (fn_08029b34), its object initialiser and the helpers after it
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08029b34 - builds the object table of one GUI page and returns by a tail
@ jump to 0x080271ac.
@ r0 and r1 are not read; r2 and r3 are only saved by the push at entry (8 bytes
@ of local space below them) and restored by the ldmia at 0x0802a69a; the function
@ has no result value of its own.
@ Registers: r5 = 0x20014274, r4 = 0x2000051c, B = word at 0x20000528 (r4+12),
@ G = word at 0x20014280 (r5+12), c = byte at 0x2000051d (r4+1),
@ bit0 = bit 0 of the byte at 0x20014294 (r5+0x20); sz(n) = fn_0801dac6(G, n).
@ Every object is initialised with fn_0802a70c(B + offset) and then set up by
@ setter calls 0x0802xxxx(B + offset, value).
@ Halfwords it stores (through the stack word at [sp]):
@   bit0 == 0: 0x2000051e = fn_08026824(0x12, 4), 0x20000520 = fn_080267f4(0x12, 4),
@              0x20000522 = fn_0801da9e(), 0x20000524 = fn_08026824(0x12, 2)
@   bit0 == 1: 0x2000051e = rgb888_word_to_rgb565(0x15171a),
@              0x20000520 = fn_08026824(0x12, 5),
@              0x20000522 = rgb888_word_to_rgb565(0x282b30),
@              0x20000524 = rgb888_word_to_rgb565(0x2f3237)
@ Objects initialised, in this order of offsets: 0xd0, 0xd8, 0x8, 0x10, 0x0, 0x18,
@ 0xa0, 0xa8, 0x20, 0x58, 0x60, 0xc0, 0x80, 0x78, 0x88, 0x90, 0x98, 0x68, 0x70,
@ 0x28, 0x30, 0x38, 0x40, 0x48, 0x50, 0xb0, 0xb8, 0xc8, 0xf0, 0xe0, 0xe8, 0x100,
@ 0x108, 0x130, 0x128, 0x110, 0x118, 0x120, 0x140, 0x148, 0x138 (41 objects, no
@ object at 0xf8).
@ Styles: after offsets 0xd0 and 0xd8 are initialised, fn_0802741c(0x2001424c,
@ 0x08050d08, 0x0801c781, 0x50, stack 0x46, 0) and fn_0802741c(0x20014260,
@ 0x08050d08, 0x0801c781, 0x50, stack 0, 0) fill two records; then
@ fn_0802740c(B+0xd0, 0x2001424c), fn_0802740c(B+0xd8, 0x20014260) and later
@ fn_0802740c(B+8, 0x20014260).
@ Code pointers: stores 0x08014d91 at 0x2000052c and 0x0801b9bd at 0x20000534;
@ fn_080271c4(B+0x58, 0x2000052c), fn_080271cc(B+0x58, 0x23), fn_080271c4(B+0x60,
@ 0x20000534), fn_080271cc(B+0x60, 0x7f).
@ Size selectors by c (c == 1 / c == 2 / other): sz(14/12/10) for fn_0802726e and
@ fn_08027256 at B+0 and B+0x18; sz(12/8/8) for fn_0802738a(B+0x18); sz(24/20/16)
@ for fn_08027228(B+0x18), fn_0802725e and fn_08027266 (B+0x20) and B+0x80;
@ sz(16/12/8) for fn_0802738a(B+0x20); sz(14/12/10) for fn_08027276 and
@ fn_0802724e (B+0x20) and B+0x78; sz(8/6/2) for B+0x70.
@ Setter calls per object (h[a] = halfword at a, zero-extended):
@   0x0: fn_08027186(0xff), fn_08027170(h[0x2000051e]), fn_080273de(h[0x20000520]),
@        fn_0802726e and fn_08027256 with sz(14/12/10)
@   0x8: fn_08027170(bit0 ? fn_080267f4(0x12,2) : fn_08026858(0x12)),
@        fn_0802738a(0x7fff), fn_08027228(sz(7)), fn_08027414(sz(5)), fn_08027186(0x66)
@   0x10: fn_08027186(0xff)
@   0x18: fn_0802738a(sz(12 if c==1 else 8)), fn_08027186(0xff),
@        fn_08027170(h[0x20000522]), fn_0802718e(h[0x20000524]), fn_080271b4(sz(2)),
@        fn_080271a4(1), fn_080273de(h[0x20000520]), fn_08027228(sz(24/20/16)),
@        fn_0802726e and fn_08027256 (sz(14/12/10)), fn_080271dc(fn_08026858(0x12)),
@        fn_080271f2(sz(1))
@   0xa0: fn_080271fa(word 0x20014284), fn_08027220(sz(3)), fn_08027218(sz(3)),
@        fn_08027210(0x7f)
@   0xa8: fn_080271fa(h[0x20014286]), fn_08027220(sz(3)), fn_08027210(0x7f)
@   0x20: fn_0802738a(sz(16/12/8)), fn_08027186(0xff), fn_08027170(h[0x20000524]);
@        only when bit0 == 0: fn_08027392(fn_08026858(0x12)), fn_080273b8(1 when
@        3*X+80 < 320, else (3*X'+80)/160 signed, X = fn_0801dcd8(0)),
@        fn_080273b0(0x7f), fn_080273a8(sz(1 when 80+4*Y < 320, else (80+4*Y')/160
@        signed, Y = fn_0801dcd8(0))); in both cases fn_080273de(h[0x20000520]),
@        fn_0802725e and fn_08027266 (sz(24/20/16)), fn_08027276 and fn_0802724e
@        (sz(14/12/10)), fn_08027256(sz(5)), fn_0802726e(sz(5))
@   0x58 and 0x60 as above; 0xc0: fn_080271bc(1), fn_080271a4(1)
@   0x80: fn_08027228, fn_0802726e, fn_08027256 each with sz(24/20/16)
@   0x78: fn_08027228(sz(14/12/10)), fn_0802726e and fn_08027256 (sz(14/12/10))
@   0x88: fn_0802726e(sz(10)), fn_08027256(sz(10)); 0x90: fn_080273f4(sz(20))
@   0x98: fn_080273d6(2); 0x68: fn_08027228(0), fn_0802726e(0), fn_08027256(0)
@   0x70: fn_08027228, fn_0802726e, fn_08027256 each with sz(8/6/2)
@   0x28: fn_08027170(word 0x20014284), fn_080273de(fn_0801da9e()), fn_08027186(0xff)
@   0x30: fn_08027170(word 0x20014284), fn_080273de(word 0x20014284), fn_08027186(0x33)
@   0x38: fn_08027170(h[0x20014286]), fn_080273de(fn_0801da9e()), fn_08027186(0xff)
@   0x40: fn_08027170(h[0x20014286]), fn_080273de(h[0x20014286]), fn_08027186(0x33)
@   0x48: fn_08027170(h[0x20000524]), fn_08027186(0xff), fn_080273de(h[0x20000520])
@   0x50: fn_08027170(h[0x20000522]), fn_08027186(0xff), fn_080273de(h[0x20000520])
@   0xb0: fn_0802738a(0x7fff); 0xb8: fn_0802738a(0); 0xc8: fn_08027404(sz(3)),
@        fn_080273fc(sz(3))
@   0xf0: fn_08027170(word 0x20014284), fn_08027186(0xff), fn_08027228(sz(6)),
@        fn_0802738a(0x7fff)
@   0xe0: fn_08027142(0xc8); 0xe8: fn_08027142(0x78)
@   0x100: fn_0802714a(h[0x20000524]), fn_08027168(sz(15)), fn_08027160(1)
@   0x108: fn_0802714a(word 0x20014284)
@   0x130: fn_080271f2(1), fn_080271dc(h[0x20000520])
@   0x128: fn_080271a4(0), fn_08027256(sz(10)), fn_080271dc(h[0x20000524])
@   0x110: fn_080271f2(sz(3)), fn_0802738a(sz(3)), fn_080273c0(sz(8)), fn_08027256(sz(2))
@   0x118: fn_0802738a(0x7fff), fn_080273c0(sz(8)), fn_08027170(word 0x20014284),
@        fn_08027186(0xff)
@   0x120: fn_080271f2(sz(1)), fn_080271dc(h[0x20000520]), fn_08027228(sz(2)),
@        fn_080273de(fn_08026858(0x12))
@   0x140: fn_080271f2(sz(5)), fn_080271dc(h[0x20000520]), fn_080273c0(sz(20)),
@        fn_0802725e(sz(15))
@   0x148: fn_0802738a(0x7fff), fn_08027170(h[0x20000520]), fn_08027186(0xff),
@        fn_080273c0(sz(15))
@   0x138: fn_080271b4(sz(1)), fn_0802718e(h[0x20000524])
@ End (0x0802a698..0x0802a6a4): r0 = B + 0x138, r1 = 3, tail jump (b.w) to
@ 0x080271ac. The body has literal words inside (0x08029f34..0x08029f4f and
@ 0x0802a424..0x0802a42f).
@ ----------------------------------------------------------------------------
	.section .text.fn_08029b34,"ax",%progbits
	.p2align 2
	.global fn_08029b34
	.thumb_func
	.type fn_08029b34, %function
fn_08029b34:
	push.w {r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	ldr r5, .L08029f34                  @ r5 = 0x20014274
	ldr r4, .L08029f38                  @ r4 = 0x2000051c
	ldrb.w r0, [r5, #0x20]
	lsls r0, r0, #0x1f                  @ bit0 of byte 0x20014294
	beq.n .L08029b4c
	ldr r0, .L08029f3c                  @ 0x15171a
	bl rgb888_word_to_rgb565
	b.n .L08029b54
.L08029b4c:
	movs r1, #0x4
	movs r0, #0x12
	bl fn_08026824
.L08029b54:
	str r0, [sp, #0x0]
	ldrh.w r0, [sp, #0x0]
	strh r0, [r4, #0x2]                 @ halfword 0x2000051e
	ldrb.w r0, [r5, #0x20]
	lsls r0, r0, #0x1f
	beq.n .L08029b6e
	movs r1, #0x5
	movs r0, #0x12
	bl fn_08026824
	b.n .L08029b76
.L08029b6e:
	movs r1, #0x4
	movs r0, #0x12
	bl fn_080267f4
.L08029b76:
	str r0, [sp, #0x0]
	ldrh.w r0, [sp, #0x0]
	strh r0, [r4, #0x4]                 @ halfword 0x20000520
	ldrb.w r0, [r5, #0x20]
	lsls r0, r0, #0x1f
	beq.n .L08029b8e
	ldr r0, .L08029f40                  @ 0x282b30
	bl rgb888_word_to_rgb565
	b.n .L08029b92
.L08029b8e:
	bl fn_0801da9e
.L08029b92:
	str r0, [sp, #0x0]
	ldrh.w r0, [sp, #0x0]
	strh r0, [r4, #0x6]                 @ halfword 0x20000522
	ldrb.w r0, [r5, #0x20]
	lsls r0, r0, #0x1f
	beq.n .L08029baa
	ldr r0, .L08029f44                  @ 0x2f3237
	bl rgb888_word_to_rgb565
	b.n .L08029bb2
.L08029baa:
	movs r1, #0x2
	movs r0, #0x12
	bl fn_08026824
.L08029bb2:
	str r0, [sp, #0x0]
	ldrh.w r0, [sp, #0x0]
	strh r0, [r4, #0x8]                 @ halfword 0x20000524
	ldr r0, [r4, #0xc]                  @ B
	adds r0, #0xd0
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	adds r0, #0xd8
	bl fn_0802a70c
	movs r6, #0x0
	movs r0, #0x46
	strd r0, r6, [sp, #0x0]             @ stack arguments 0x46, 0
	ldr r0, .L08029f34
	movs r3, #0x50
	ldr r2, .L08029f48                  @ 0x0801c781
	ldr r1, .L08029f4c                  @ 0x08050d08
	subs r0, #0x28                      @ r0 = 0x2001424c
	bl fn_0802741c
	ldr r0, .L08029f34
	str r6, [sp, #0x0]
	movs r3, #0x50
	ldr r2, .L08029f48
	ldr r1, .L08029f4c
	subs r0, #0x14                      @ r0 = 0x20014260
	str r6, [sp, #0x4]
	bl fn_0802741c
	ldr r1, .L08029f34
	ldr r0, [r4, #0xc]
	subs r1, #0x28
	adds r0, #0xd0
	bl fn_0802740c
	ldr r1, .L08029f34
	ldr r0, [r4, #0xc]
	subs r1, #0x14
	adds r0, #0xd8
	bl fn_0802740c
	ldr r0, [r4, #0xc]
	adds r0, #0x8
	bl fn_0802a70c
	ldrb.w r0, [r5, #0x20]
	lsls r0, r0, #0x1f
	beq.n .L08029c24
	movs r1, #0x2
	movs r0, #0x12
	bl fn_080267f4
	b.n .L08029c2a
.L08029c24:
	movs r0, #0x12
	bl fn_08026858
.L08029c2a:
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x8
	bl fn_08027170
	ldr r0, [r4, #0xc]
	movw r10, #0x7fff
	mov r1, r10
	adds r0, #0x8
	bl fn_0802738a
	movs r1, #0x7
	ldr r0, [r5, #0xc]                  @ G
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x8
	bl fn_08027228
	movs r1, #0x5
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x8
	bl fn_08027414
	ldr r0, [r4, #0xc]
	movs r1, #0x66
	adds r0, #0x8
	bl fn_08027186
	ldr r1, .L08029f34
	ldr r0, [r4, #0xc]
	subs r1, #0x14
	adds r0, #0x8
	bl fn_0802740c
	ldr r0, [r4, #0xc]
	adds r0, #0x10
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	movs r1, #0xff
	adds r0, #0x10
	bl fn_08027186
	ldr r0, [r4, #0xc]                  @ object at offset 0
	bl fn_0802a70c
	movs r1, #0xff
	ldr r0, [r4, #0xc]
	bl fn_08027186
	ldrh r0, [r4, #0x2]
	strh.w r0, [sp, #0x0]
	ldr r1, [sp, #0x0]
	ldr r0, [r4, #0xc]
	bl fn_08027170
	ldrh r0, [r4, #0x4]
	strh.w r0, [sp, #0x0]
	ldr r1, [sp, #0x0]
	ldr r0, [r4, #0xc]
	bl fn_080273de
	ldrb r0, [r4, #0x1]                 @ c
	cmp r0, #0x1
	beq.n .L08029dbc
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L08029dbe
	movs.w r1, #0xa
.L08029cc8:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	bl fn_0802726e
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L08029dc0
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L08029dc2
	movs.w r1, #0xa
.L08029ce4:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	bl fn_08027256
	ldr r0, [r4, #0xc]
	adds r0, #0x18
	bl fn_0802a70c
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	ldr r0, [r5, #0xc]
	beq.n .L08029dfc
	movs.w r1, #0x8
.L08029d04:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x18
	bl fn_0802738a
	ldr r0, [r4, #0xc]
	movs r1, #0xff
	adds r0, #0x18
	bl fn_08027186
	ldrh r0, [r4, #0x6]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	adds r0, #0x18
	bl fn_08027170
	ldrh r0, [r4, #0x8]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	adds r0, #0x18
	bl fn_0802718e
	movs r1, #0x2
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x18
	bl fn_080271b4
	ldr r0, [r4, #0xc]
	movs r1, #0x1
	adds r0, #0x18
	bl fn_080271a4
	ldrh r0, [r4, #0x4]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	adds r0, #0x18
	bl fn_080273de
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L08029e6c
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L08029e6e
	movs.w r1, #0x10
.L08029d78:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x18
	bl fn_08027228
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L08029e70
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L08029e72
	movs r1, #0xa
.L08029d94:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x18
	bl fn_0802726e
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L08029e74
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L08029eac
	movs r1, #0xa
.L08029db0:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x18
	b.n .L08029dc4
.L08029dbc:
	b.n .L08029ebe
.L08029dbe:
	b.n .L08029ec4
.L08029dc0:
	b.n .L08029ec8
.L08029dc2:
	b.n .L08029ece
.L08029dc4:
	bl fn_08027256
	movs r0, #0x12
	bl fn_08026858
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x18
	bl fn_080271dc
	movs r1, #0x1
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x18
	bl fn_080271f2
	ldr r0, [r4, #0xc]
	adds r0, #0xa0
	bl fn_0802a70c
	ldr r6, .L08029f34
	ldr r0, [r4, #0xc]
	subs r6, #0x28                      @ r6 = 0x2001424c
	ldr r1, [r6, #0x38]                 @ word 0x20014284
	b.n .L08029dfe
.L08029dfc:
	b.n .L08029ed2
.L08029dfe:
	adds r0, #0xa0
	bl fn_080271fa
	movs r1, #0x3
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0xa0
	bl fn_08027220
	movs r1, #0x3
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0xa0
	bl fn_08027218
	ldr r0, [r4, #0xc]
	movs r1, #0x7f
	adds r0, #0xa0
	bl fn_08027210
	ldr r0, [r4, #0xc]
	adds r0, #0xa8
	bl fn_0802a70c
	ldrh r0, [r6, #0x3a]                @ halfword 0x20014286
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	adds r0, #0xa8
	bl fn_080271fa
	movs r1, #0x3
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0xa8
	bl fn_08027220
	ldr r0, [r4, #0xc]
	movs r1, #0x7f
	adds r0, #0xa8
	bl fn_08027210
	ldr r0, [r4, #0xc]
	adds r0, #0x20
	b.n .L08029e76
.L08029e6c:
	b.n .L08029ed6
.L08029e6e:
	b.n .L08029edc
.L08029e70:
	b.n .L08029ee0
.L08029e72:
	b.n .L08029ee6
.L08029e74:
	b.n .L08029eea
.L08029e76:
	bl fn_0802a70c
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L08029ef4
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L08029efa
	movs r1, #0x8
.L08029e88:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x20
	bl fn_0802738a
	ldr r0, [r4, #0xc]
	movs r1, #0xff
	adds r0, #0x20
	bl fn_08027186
	ldrh r0, [r4, #0x8]
	strh.w r0, [sp, #0x0]
	ldr r1, [sp, #0x0]
	ldr r0, [r4, #0xc]
	b.n .L08029eae
.L08029eac:
	b.n .L08029ef0
.L08029eae:
	adds r0, #0x20
	bl fn_08027170
	ldrb.w r0, [r5, #0x20]
	lsls r0, r0, #0x1f
	beq.n .L08029efe
	b.n .L08029fa0
.L08029ebe:
	movs r1, #0xe
	ldr r0, [r5, #0xc]
	b.n .L08029cc8
.L08029ec4:
	movs r1, #0xc
	b.n .L08029cc8
.L08029ec8:
	movs r1, #0xe
	ldr r0, [r5, #0xc]
	b.n .L08029ce4
.L08029ece:
	movs r1, #0xc
	b.n .L08029ce4
.L08029ed2:
	movs r1, #0xc
	b.n .L08029d04
.L08029ed6:
	movs r1, #0x18
	ldr r0, [r5, #0xc]
	b.n .L08029d78
.L08029edc:
	movs r1, #0x14
	b.n .L08029d78
.L08029ee0:
	movs r1, #0xe
	ldr r0, [r5, #0xc]
	b.n .L08029d94
.L08029ee6:
	movs r1, #0xc
	b.n .L08029d94
.L08029eea:
	movs r1, #0xe
	ldr r0, [r5, #0xc]
	b.n .L08029db0
.L08029ef0:
	movs r1, #0xc
	b.n .L08029db0
.L08029ef4:
	movs r1, #0x10
	ldr r0, [r5, #0xc]
	b.n .L08029e88
.L08029efa:
	movs r1, #0xc
	b.n .L08029e88
.L08029efe:
	movs r0, #0x12
	bl fn_08026858
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x20
	bl fn_08027392
	movs r0, #0x0
	bl fn_0801dcd8
	add.w r0, r0, r0, lsl #0x1          @ 3 * X
	mov.w r9, #0x140
	adds r0, #0x50
	mov.w r8, #0xa0
	cmp r0, r9
	blt.n .L08029f56
	movs r0, #0x0
	bl fn_0801dcd8
	add.w r0, r0, r0, lsl #0x1
	adds r0, #0x50
	b.n .L08029f50
.L08029f34:
	.word 0x20014274
.L08029f38:
	.word 0x2000051c
.L08029f3c:
	.word 0x0015171a
.L08029f40:
	.word 0x00282b30
.L08029f44:
	.word 0x002f3237
.L08029f48:
	.word fn_0801c780                   @ function pointer 0x0801c781
.L08029f4c:
	.word d_08050d08
.L08029f50:
	sdiv r0, r0, r8
	b.n .L08029f58
.L08029f56:
	movs r0, #0x1
.L08029f58:
	sxth r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x20
	bl fn_080273b8
	ldr r0, [r4, #0xc]
	movs r1, #0x7f
	adds r0, #0x20
	bl fn_080273b0
	movs r0, #0x0
	bl fn_0801dcd8
	movs r7, #0x50
	add.w r0, r7, r0, lsl #0x2          @ 80 + 4 * Y
	cmp r0, r9
	blt.n .L08029f8c
	movs r0, #0x0
	bl fn_0801dcd8
	add.w r1, r7, r0, lsl #0x2
	sdiv r0, r1, r8
	b.n .L08029f8e
.L08029f8c:
	movs r0, #0x1
.L08029f8e:
	sxth r1, r0
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x20
	bl fn_080273a8
.L08029fa0:
	ldrh r0, [r4, #0x4]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	adds r0, #0x20
	bl fn_080273de
	ldr r0, [r4, #0xc]
	add.w r8, r0, #0x20
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L0802a0b8
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L0802a0ba
	movs r1, #0x10
.L08029fc4:
	bl fn_0801dac6
	mov r7, r0
	mov r1, r0
	mov r0, r8
	bl fn_0802725e
	mov r1, r7
	mov r0, r8
	bl fn_08027266
	ldr r0, [r4, #0xc]
	add.w r8, r0, #0x20
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L0802a0bc
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L0802a0be
	movs.w r1, #0xa
.L08029ff0:
	bl fn_0801dac6
	mov r7, r0
	mov r1, r0
	mov r0, r8
	bl fn_08027276
	mov r1, r7
	mov r0, r8
	bl fn_0802724e
	movs r1, #0x5
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x20
	bl fn_08027256
	movs r1, #0x5
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x20
	bl fn_0802726e
	ldr r1, .L0802a428                  @ r1 = 0x2000052c
	ldr r0, .L0802a424                  @ 0x08014d91
	str r0, [r1, #0x0]
	adds r1, #0x8
	ldr r0, .L0802a42c                  @ 0x0801b9bd
	str r0, [r1, #0x0]                  @ word 0x20000534
	ldr r0, [r4, #0xc]
	adds r0, #0x58
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	ldr r1, .L0802a428
	adds r0, #0x58
	bl fn_080271c4
	ldr r0, [r4, #0xc]
	movs r1, #0x23
	adds r0, #0x58
	bl fn_080271cc
	ldr r0, [r4, #0xc]
	adds r0, #0x60
	bl fn_0802a70c
	ldr r1, .L0802a428
	ldr r0, [r4, #0xc]
	adds r1, #0x8
	adds r0, #0x60
	bl fn_080271c4
	ldr r0, [r4, #0xc]
	movs r1, #0x7f
	adds r0, #0x60
	bl fn_080271cc
	ldr r0, [r4, #0xc]
	adds r0, #0xc0
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	movs r1, #0x1
	adds r0, #0xc0
	bl fn_080271bc
	ldr r0, [r4, #0xc]
	movs r1, #0x1
	adds r0, #0xc0
	bl fn_080271a4
	ldr r0, [r4, #0xc]
	adds r0, #0x80
	bl fn_0802a70c
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L0802a198
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L0802a19a
	movs.w r1, #0x10
.L0802a0a4:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x80
	bl fn_08027228
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	b.n .L0802a0c0
.L0802a0b8:
	b.n .L0802a6a8
.L0802a0ba:
	b.n .L0802a6ae
.L0802a0bc:
	b.n .L0802a6b2
.L0802a0be:
	b.n .L0802a6b8
.L0802a0c0:
	beq.n .L0802a19c
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L0802a19e
	movs.w r1, #0x10
.L0802a0cc:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x80
	bl fn_0802726e
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L0802a1dc
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L0802a1de
	movs r1, #0x10
.L0802a0e8:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x80
	bl fn_08027256
	ldr r0, [r4, #0xc]
	adds r0, #0x78
	bl fn_0802a70c
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L0802a1e0
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L0802a1e2
	movs r1, #0xa
.L0802a10c:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x78
	bl fn_08027228
	ldr r0, [r4, #0xc]
	add.w r8, r0, #0x78
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L0802a224
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L0802a226
	movs.w r1, #0xa
.L0802a130:
	bl fn_0801dac6
	mov r7, r0
	mov r1, r0
	mov r0, r8
	bl fn_0802726e
	mov r1, r7
	mov r0, r8
	bl fn_08027256
	ldr r0, [r4, #0xc]
	adds r0, #0x88
	bl fn_0802a70c
	movs r1, #0xa
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x88
	bl fn_0802726e
	movs r1, #0xa
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x88
	bl fn_08027256
	ldr r0, [r4, #0xc]
	adds r0, #0x90
	bl fn_0802a70c
	movs r1, #0x14
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x90
	bl fn_080273f4
	ldr r0, [r4, #0xc]
	adds r0, #0x98
	bl fn_0802a70c
	movs r1, #0x2
	b.n .L0802a1a0
.L0802a198:
	b.n .L0802a6bc
.L0802a19a:
	b.n .L0802a6c2
.L0802a19c:
	b.n .L0802a6c6
.L0802a19e:
	b.n .L0802a6cc
.L0802a1a0:
	ldr r0, [r4, #0xc]
	adds r0, #0x98
	bl fn_080273d6
	ldr r0, [r4, #0xc]
	adds r0, #0x68
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	movs r1, #0x0
	adds r0, #0x68
	bl fn_08027228
	ldr r0, [r4, #0xc]
	movs r1, #0x0
	adds r0, #0x68
	bl fn_0802726e
	ldr r0, [r4, #0xc]
	movs r1, #0x0
	adds r0, #0x68
	bl fn_08027256
	ldr r0, [r4, #0xc]
	adds r0, #0x70
	bl fn_0802a70c
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	b.n .L0802a1e4
.L0802a1dc:
	b.n .L0802a6d0
.L0802a1de:
	b.n .L0802a6d6
.L0802a1e0:
	b.n .L0802a6da
.L0802a1e2:
	b.n .L0802a6e0
.L0802a1e4:
	beq.n .L0802a2e4
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L0802a2e6
	movs.w r1, #0x2
.L0802a1f0:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x70
	bl fn_08027228
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L0802a2e8
	cmp r0, #0x2
	ldr r0, [r5, #0xc]
	beq.n .L0802a2ea
	movs r1, #0x2
.L0802a20c:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x70
	bl fn_0802726e
	ldrb r0, [r4, #0x1]
	cmp r0, #0x1
	beq.n .L0802a2ec
	cmp r0, #0x2
	b.n .L0802a228
.L0802a224:
	b.n .L0802a6e4
.L0802a226:
	b.n .L0802a6ea
.L0802a228:
	ldr r0, [r5, #0xc]
	beq.n .L0802a328
	movs.w r1, #0x2
.L0802a230:
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x70
	bl fn_08027256
	ldr r0, [r4, #0xc]
	adds r0, #0x28
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	ldr r1, [r6, #0x38]                 @ word 0x20014284
	adds r0, #0x28
	bl fn_08027170
	bl fn_0801da9e
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x28
	bl fn_080273de
	ldr r0, [r4, #0xc]
	movs r1, #0xff
	adds r0, #0x28
	bl fn_08027186
	ldr r0, [r4, #0xc]
	adds r0, #0x30
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	ldr r1, [r6, #0x38]
	adds r0, #0x30
	bl fn_08027170
	ldr r0, [r4, #0xc]
	ldr r1, [r6, #0x38]
	adds r0, #0x30
	bl fn_080273de
	ldr r0, [r4, #0xc]
	movs r1, #0x33
	adds r0, #0x30
	bl fn_08027186
	ldr r0, [r4, #0xc]
	adds r0, #0x38
	bl fn_0802a70c
	ldrh r0, [r6, #0x3a]                @ halfword 0x20014286
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	adds r0, #0x38
	bl fn_08027170
	bl fn_0801da9e
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0x38
	bl fn_080273de
	ldr r0, [r4, #0xc]
	movs r1, #0xff
	adds r0, #0x38
	bl fn_08027186
	ldr r0, [r4, #0xc]
	adds r0, #0x40
	bl fn_0802a70c
	ldrh r0, [r6, #0x3a]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	adds r0, #0x40
	bl fn_08027170
	ldrh r0, [r6, #0x3a]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	adds r0, #0x40
	b.n .L0802a2ee
.L0802a2e4:
	b.n .L0802a6ee
.L0802a2e6:
	b.n .L0802a6f4
.L0802a2e8:
	b.n .L0802a6f8
.L0802a2ea:
	b.n .L0802a6fe
.L0802a2ec:
	b.n .L0802a702
.L0802a2ee:
	bl fn_080273de
	ldr r0, [r4, #0xc]
	movs r1, #0x33
	adds r0, #0x40
	bl fn_08027186
	ldr r0, [r4, #0xc]
	adds r0, #0x48
	bl fn_0802a70c
	ldrh r0, [r4, #0x8]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	adds r0, #0x48
	bl fn_08027170
	ldr r0, [r4, #0xc]
	movs r1, #0xff
	adds r0, #0x48
	bl fn_08027186
	ldrh r0, [r4, #0x4]
	strh.w r0, [sp, #0x0]
	ldr r1, [sp, #0x0]
	b.n .L0802a32a
.L0802a328:
	b.n .L0802a708
.L0802a32a:
	ldr r0, [r4, #0xc]
	adds r0, #0x48
	bl fn_080273de
	ldr r0, [r4, #0xc]
	adds r0, #0x50
	bl fn_0802a70c
	ldrh r0, [r4, #0x6]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	adds r0, #0x50
	bl fn_08027170
	ldr r0, [r4, #0xc]
	movs r1, #0xff
	adds r0, #0x50
	bl fn_08027186
	ldrh r0, [r4, #0x4]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	adds r0, #0x50
	bl fn_080273de
	ldr r0, [r4, #0xc]
	adds r0, #0xb0
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	mov r7, r10
	mov r1, r10
	adds r0, #0xb0
	bl fn_0802738a
	ldr r0, [r4, #0xc]
	adds r0, #0xb8
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	movs r1, #0x0
	adds r0, #0xb8
	bl fn_0802738a
	ldr r0, [r4, #0xc]
	adds r0, #0xc8
	bl fn_0802a70c
	movs r1, #0x3
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0xc8
	bl fn_08027404
	movs r1, #0x3
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0xc8
	bl fn_080273fc
	ldr r0, [r4, #0xc]
	adds r0, #0xf0
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	ldr r1, [r6, #0x38]
	adds r0, #0xf0
	bl fn_08027170
	ldr r0, [r4, #0xc]
	movs r1, #0xff
	adds r0, #0xf0
	bl fn_08027186
	movs r1, #0x6
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	adds r0, #0xf0
	bl fn_08027228
	ldr r0, [r4, #0xc]
	mov r1, r7                          @ 0x7fff
	adds r0, #0xf0
	bl fn_0802738a
	ldr r0, [r4, #0xc]
	adds r0, #0xe0
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	movs r1, #0xc8
	adds r0, #0xe0
	bl fn_08027142
	ldr r0, [r4, #0xc]
	adds r0, #0xe8
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	movs r1, #0x78
	adds r0, #0xe8
	bl fn_08027142
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x100
	bl fn_0802a70c
	ldrh r0, [r4, #0x8]
	strh.w r0, [sp, #0x0]
	b.n .L0802a430
.L0802a424:
	.word fn_08014d90                   @ function pointer 0x08014d91
.L0802a428:
	.word 0x2000052c
.L0802a42c:
	.word fn_0801b9bc                   @ function pointer 0x0801b9bd
.L0802a430:
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	add.w r0, r0, #0x100
	bl fn_0802714a
	movs r1, #0xf
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x100
	bl fn_08027168
	ldr r0, [r4, #0xc]
	movs r1, #0x1
	add.w r0, r0, #0x100
	bl fn_08027160
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x108
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	ldr r1, [r6, #0x38]
	add.w r0, r0, #0x108
	bl fn_0802714a
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x130
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	movs r1, #0x1
	add.w r0, r0, #0x130
	bl fn_080271f2
	ldrh r0, [r4, #0x4]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	add.w r0, r0, #0x130
	bl fn_080271dc
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x128
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	movs r1, #0x0
	add.w r0, r0, #0x128
	bl fn_080271a4
	movs r1, #0xa
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x128
	bl fn_08027256
	ldrh r0, [r4, #0x8]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	add.w r0, r0, #0x128
	bl fn_080271dc
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x110
	bl fn_0802a70c
	movs r1, #0x3
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x110
	bl fn_080271f2
	movs r1, #0x3
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x110
	bl fn_0802738a
	movs r1, #0x8
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x110
	bl fn_080273c0
	movs r1, #0x2
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x110
	bl fn_08027256
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x118
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	mov r1, r7
	add.w r0, r0, #0x118
	bl fn_0802738a
	movs r1, #0x8
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x118
	bl fn_080273c0
	ldr r0, [r4, #0xc]
	ldr r1, [r6, #0x38]
	add.w r0, r0, #0x118
	bl fn_08027170
	ldr r0, [r4, #0xc]
	movs r1, #0xff
	add.w r0, r0, #0x118
	bl fn_08027186
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x120
	bl fn_0802a70c
	movs r1, #0x1
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x120
	bl fn_080271f2
	ldrh r0, [r4, #0x4]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	add.w r0, r0, #0x120
	bl fn_080271dc
	movs r1, #0x2
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x120
	bl fn_08027228
	movs r0, #0x12
	bl fn_08026858
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x120
	bl fn_080273de
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x140
	bl fn_0802a70c
	movs r1, #0x5
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x140
	bl fn_080271f2
	ldrh r0, [r4, #0x4]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	add.w r0, r0, #0x140
	bl fn_080271dc
	movs r1, #0x14
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x140
	bl fn_080273c0
	movs r1, #0xf
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x140
	bl fn_0802725e
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x148
	bl fn_0802a70c
	ldr r0, [r4, #0xc]
	mov r1, r7
	add.w r0, r0, #0x148
	bl fn_0802738a
	ldrh r0, [r4, #0x4]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	add.w r0, r0, #0x148
	bl fn_08027170
	ldr r0, [r4, #0xc]
	movs r1, #0xff
	add.w r0, r0, #0x148
	bl fn_08027186
	movs r1, #0xf
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x148
	bl fn_080273c0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x138
	bl fn_0802a70c
	movs r1, #0x1
	ldr r0, [r5, #0xc]
	bl fn_0801dac6
	mov r1, r0
	ldr r0, [r4, #0xc]
	add.w r0, r0, #0x138
	bl fn_080271b4
	ldrh r0, [r4, #0x8]
	strh.w r0, [sp, #0x0]
	ldr r0, [r4, #0xc]
	ldr r1, [sp, #0x0]
	add.w r0, r0, #0x138
	bl fn_0802718e
	ldr r0, [r4, #0xc]
	pop.w {r2, r3, r4, r5, r6, r7, r8, r9, r10, lr}
	movs r1, #0x3
	add.w r0, r0, #0x138                @ r0 = B + 0x138
	b.w fn_080271ac                     @ tail jump; returns to the caller
.L0802a6a8:
	movs r1, #0x18
	ldr r0, [r5, #0xc]
	b.n .L08029fc4
.L0802a6ae:
	movs r1, #0x14
	b.n .L08029fc4
.L0802a6b2:
	movs r1, #0xe
	ldr r0, [r5, #0xc]
	b.n .L08029ff0
.L0802a6b8:
	movs r1, #0xc
	b.n .L08029ff0
.L0802a6bc:
	movs r1, #0x18
	ldr r0, [r5, #0xc]
	b.n .L0802a0a4
.L0802a6c2:
	movs r1, #0x14
	b.n .L0802a0a4
.L0802a6c6:
	movs r1, #0x18
	ldr r0, [r5, #0xc]
	b.n .L0802a0cc
.L0802a6cc:
	movs r1, #0x14
	b.n .L0802a0cc
.L0802a6d0:
	movs r1, #0x18
	ldr r0, [r5, #0xc]
	b.n .L0802a0e8
.L0802a6d6:
	movs r1, #0x14
	b.n .L0802a0e8
.L0802a6da:
	movs r1, #0xe
	ldr r0, [r5, #0xc]
	b.n .L0802a10c
.L0802a6e0:
	movs r1, #0xc
	b.n .L0802a10c
.L0802a6e4:
	movs r1, #0xe
	ldr r0, [r5, #0xc]
	b.n .L0802a130
.L0802a6ea:
	movs r1, #0xc
	b.n .L0802a130
.L0802a6ee:
	movs r1, #0x8
	ldr r0, [r5, #0xc]
	b.n .L0802a1f0
.L0802a6f4:
	movs r1, #0x6
	b.n .L0802a1f0
.L0802a6f8:
	movs r1, #0x8
	ldr r0, [r5, #0xc]
	b.n .L0802a20c
.L0802a6fe:
	movs r1, #0x6
	b.n .L0802a20c
.L0802a702:
	movs r1, #0x8
	ldr r0, [r5, #0xc]
	b.n .L0802a230
.L0802a708:
	movs r1, #0x6
	b.n .L0802a230

@ ----------------------------------------------------------------------------
@ fn_0802a70c - initialises a GUI object by the page mode.
@ Parameters: r0 = style object pointer, further arguments are passed through
@ unchanged to the callee. Reads the byte at 0x2000051c: when it is 0 tail-calls
@ fn_08026f0e, otherwise tail-calls fn_0802711a. No value of its own.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802a70c,"ax",%progbits
	.p2align 2
	.global fn_0802a70c
	.thumb_func
	.type fn_0802a70c, %function
fn_0802a70c:
	ldr r1, .L0802a71c                  @ r1 = 0x2000051c
	ldrb r1, [r1, #0x0]
	cbz r1, .L0802a716
	b.w fn_0802711a
.L0802a716:
	b.w fn_08026f0e
	.short 0x0000                       @ padding
.L0802a71c:
	.word 0x2000051c

@ ----------------------------------------------------------------------------
@ fn_0802a7a8 - applies one object's state to the object set of the current page.
@ Parameters: r0 unused, r1 = object pointer (kept in r9 as param_2).
@ Looks up the parent with fn_08023fa4(r1); when it is 0 calls
@ fn_080230c4(r1, base + offset, mask) with base = word 0x20000528 and
@ offset/mask 0x0/0, 0x8/0x10000, 0x10/0x10040. Otherwise compares r1 with the
@ tables at 0x0804fcfc, 0x0804fd58, 0x08050f68, 0x08050f14, 0x08050f4c and
@ 0x08050f30 through fn_080233b0 and, for the matching table, calls
@ fn_080230c4(r1, base + offset, mask) with these offset/mask pairs:
@   0x0804fcfc: 0x18/0, 0x8/0x10000, 0x10/0x10040
@   0x0804fd58: 0x130/0
@   0x08050f68: 0x18/0, 0x68/0, 0xb8/0, 0xa0/4, 0xa8/8, 0x8/0x10000, 0x10/0x10040,
@               0x50/0x50000, 0x138/0x50000, 0x80/0x50000, 0x58/0x50020,
@               0x28/0x50004, 0x38/0x50008
@   0x08050f14: 0x18/0, 0x78/0, 0x128/0, 0x8/0x10000, 0x10/0x10040, 0x110/0x50000,
@               0x118/0x20000, 0x120/0x60000, 0x110/0x70000
@   0x08050f4c: 0x100/0, 0x100/0x20000, 0x108/0x20000, 0xf0/0x30000
@   0x08050f30: 0x18/0, 0xb0/0, 0x148/0x20000
@ The last call of each path is a tail call (pop of r4..r10,lr then b.w to
@ fn_080230c4). Returns without a call when no table matches.
@ Registers: r4 = 0x2000051c (base word at r4+12 is 0x20000528's content),
@ r6 = 0x10000, r8 = 0x10040 (word read from the pool), r9 = object pointer.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802a7a8,"ax",%progbits
	.p2align 2
	.global fn_0802a7a8
	.thumb_func
	.type fn_0802a7a8, %function
fn_0802a7a8:
	push.w {r4, r5, r6, r7, r8, r9, r10, lr}
	mov r9, r1
	mov r0, r1
	bl fn_08023fa4
	ldr r4, .L0802a9bc                  @ r4 = 0x2000051c
	ldr.w r8, .L0802a9c0                @ r8 = 0x00010040
	mov.w r6, #0x10000
	cbz r0, .L0802a7ee
	ldr r1, .L0802a9c4                  @ table 0x0804fcfc
	mov r0, r9
	bl fn_080233b0
	cbz r0, .L0802a7f6
	ldr r1, [r4, #0xc]
	movs r2, #0x0
	mov r0, r9
	adds.w r1, r1, #0x18
.L0802a7d4:
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r6
	mov r0, r9
	adds r1, #0x8
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r8
	mov r0, r9
	adds r1, #0x10
	b.n .L0802a9b0
.L0802a7ee:
	movs r2, #0x0
	mov r0, r9
	ldr r1, [r4, #0xc]
	b.n .L0802a7d4
.L0802a7f6:
	ldr r1, .L0802a9c8                  @ table 0x0804fd58
	mov r0, r9
	bl fn_080233b0
	cbz r0, .L0802a80c
	ldr r1, [r4, #0xc]
	movs r2, #0x0
	mov r0, r9
	add.w r1, r1, #0x130
	b.n .L0802a9b0
.L0802a80c:
	ldr r1, .L0802a9cc                  @ table 0x08050f68
	mov r0, r9
	bl fn_080233b0
	mov.w r5, #0x50000
	cmp r0, #0x0
	beq.n .L0802a8ba
	ldr r1, [r4, #0xc]
	movs r2, #0x0
	mov r0, r9
	adds r1, #0x18
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	movs r2, #0x0
	mov r0, r9
	adds r1, #0x68
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	movs r2, #0x0
	mov r0, r9
	adds r1, #0xb8
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	movs r2, #0x4
	mov r0, r9
	adds r1, #0xa0
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	movs r2, #0x8
	mov r0, r9
	adds r1, #0xa8
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r6
	mov r0, r9
	adds r1, #0x8
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r8
	mov r0, r9
	adds r1, #0x10
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r5
	mov r0, r9
	adds r1, #0x50
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r5
	mov r0, r9
	add.w r1, r1, #0x138
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r5
	mov r0, r9
	adds r1, #0x80
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	ldr r2, .L0802a9d0                  @ 0x00050020
	mov r0, r9
	adds r1, #0x58
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	adds r2, r5, #0x4
	mov r0, r9
	adds r1, #0x28
	bl fn_080230c4
	ldr r2, .L0802a9d0
	ldr r1, [r4, #0xc]
	subs r2, #0x18                      @ 0x00050008
	mov r0, r9
	adds r1, #0x38
	b.n .L0802a9b0
.L0802a8ba:
	ldr r1, .L0802a9d4                  @ table 0x08050f14
	mov r0, r9
	bl fn_080233b0
	mov.w r7, #0x20000
	cbz r0, .L0802a940
	ldr r1, [r4, #0xc]
	movs r2, #0x0
	mov r0, r9
	adds r1, #0x18
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	movs r2, #0x0
	mov r0, r9
	adds r1, #0x78
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	movs r2, #0x0
	mov r0, r9
	add.w r1, r1, #0x128
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r6
	mov r0, r9
	adds r1, #0x8
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r8
	mov r0, r9
	adds r1, #0x10
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r5
	mov r0, r9
	add.w r1, r1, #0x110
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r7
	mov r0, r9
	add.w r1, r1, #0x118
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov.w r2, #0x60000
	mov r0, r9
	add.w r1, r1, #0x120
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov.w r2, #0x70000
	mov r0, r9
	add.w r1, r1, #0x110
	b.n .L0802a9b0
.L0802a940:
	b.n .L0802a942
.L0802a942:
	ldr r1, .L0802a9d8                  @ table 0x08050f4c
	mov r0, r9
	bl fn_080233b0
	cbz r0, .L0802a982
	ldr r1, [r4, #0xc]
	movs r2, #0x0
	mov r0, r9
	add.w r1, r1, #0x100
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r7
	mov r0, r9
	add.w r1, r1, #0x100
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r7
	mov r0, r9
	add.w r1, r1, #0x108
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov.w r2, #0x30000
	mov r0, r9
	adds r1, #0xf0
	b.n .L0802a9b0
.L0802a982:
	ldr r1, .L0802a9dc                  @ table 0x08050f30
	mov r0, r9
	bl fn_080233b0
	cmp r0, #0x0
	beq.n .L0802a9b8
	ldr r1, [r4, #0xc]
	movs r2, #0x0
	mov r0, r9
	adds r1, #0x18
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	movs r2, #0x0
	mov r0, r9
	adds r1, #0xb0
	bl fn_080230c4
	ldr r1, [r4, #0xc]
	mov r2, r7
	mov r0, r9
	add.w r1, r1, #0x148
.L0802a9b0:
	pop.w {r4, r5, r6, r7, r8, r9, r10, lr}
	b.w fn_080230c4                     @ tail call
.L0802a9b8:
	pop.w {r4, r5, r6, r7, r8, r9, r10, pc}
.L0802a9bc:
	.word 0x2000051c
.L0802a9c0:
	.word 0x00010040
.L0802a9c4:
	.word d_0804fcfc
.L0802a9c8:
	.word d_0804fd58
.L0802a9cc:
	.word d_08050f68
.L0802a9d0:
	.word 0x00050020
.L0802a9d4:
	.word d_08050f14
.L0802a9d8:
	.word d_08050f4c
.L0802a9dc:
	.word d_08050f30

@ ----------------------------------------------------------------------------
@ fn_0802aa00 - sets one animated property of an object for a blend amount.
@ Parameters: r0 = pointer to a 5-word record (object at +0, property id
@ halfword at +4, selector at +8, colour a at +0xc, colour b at +0x10),
@ r1 = blend amount 0..255, r2 = unused, r3 = unused (r3 is reused for the id).
@ Searches the 8-byte entries of the object (count = (halfword +0x22 & 0x1ff)
@ >> 3, array at word +0xc) for the entry whose second word has bit 25 set and
@ whose low 24 bits equal the selector; returns when none is found.
@ Value: property ids 0x20, 0x30, 0x44, 0x47, 0x55 and 0x36 use a per-channel
@ RGB565 mix (amount 0 or less selects a, 0xff and above selects b, otherwise
@ a + ((((amount & 0xff) + 4) >> 3) * (b - a) >> 5) on the patterns masked with
@ 0x07e0f81f); ids 0x33, 0x34, 0x57, 0x66 and 0x67 select b at amount 0xff or
@ above and a below; id 0x61 selects b when a is 0, a when b is 0, otherwise b at
@ amount 0x80 and above and a below; other ids use a + (amount * (b - a) >> 8)
@ (amount 0xff selects b, amount 0 selects a).
@ Then calls fn_08026dc4(entry object, id, sp+4) to read the stored value and
@ fn_08027280(entry object, id, value) to write the new one, and calls
@ fn_08025d34(object, selector, id) unless the stored value was equal.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802aa00,"ax",%progbits
	.p2align 2
	.global fn_0802aa00
	.thumb_func
	.type fn_0802aa00, %function
fn_0802aa00:
	push {r1, r2, r3, r4, r5, r6, r7, lr}
	mov r4, r0
	movs r5, #0x0                       @ entry index
	ldr r6, [r0, #0x0]                  @ object
	movs r0, #0x4
	b.n .L0802aa24
.L0802aa0c:
	ldr r2, [r6, #0xc]
	add.w r3, r0, r5, lsl #0x3
	ldr r2, [r2, r3]                    @ second word of entry r5
	lsls r3, r2, #0x6
	bpl.n .L0802aa22                    @ bit 25 clear
	ldr r3, [r4, #0x8]
	bic r2, r2, #0xff000000
	cmp r2, r3
	beq.n .L0802aa30
.L0802aa22:
	.inst.n 0x1c6d                      @ adds r5, r5, #1
.L0802aa24:
	ldrh r2, [r6, #0x22]
	ubfx r2, r2, #0x3, #0x6
	cmp r2, r5
	bhi.n .L0802aa0c
.L0802aa2e:
	pop {r1, r2, r3, r4, r5, r6, r7, pc}
.L0802aa30:
	ldrh r3, [r4, #0x4]                 @ property id
	cmp r3, #0x47
	beq.n .L0802aaea
	bgt.n .L0802aa56
	cmp r3, #0x34
	beq.n .L0802aad0
	bgt.n .L0802aa4c
	cmp r3, #0x20
	beq.n .L0802aaea
	cmp r3, #0x30
	beq.n .L0802aaea
	cmp r3, #0x33
	bne.n .L0802aa6e
	b.n .L0802aad0
.L0802aa4c:
	cmp r3, #0x36
	beq.n .L0802aaea
	cmp r3, #0x44
	bne.n .L0802aa6e
	b.n .L0802aaea
.L0802aa56:
	cmp r3, #0x61
	beq.n .L0802aad6
	bgt.n .L0802aa66
	cmp r3, #0x55
	beq.n .L0802aaea
	cmp r3, #0x57
	bne.n .L0802aa6e
	b.n .L0802aad0
.L0802aa66:
	cmp r3, #0x66
	beq.n .L0802aad0
	cmp r3, #0x67
	beq.n .L0802aad0
.L0802aa6e:
	cbz r1, .L0802aac8
	cmp r1, #0xff
	beq.n .L0802aacc
	ldrd r0, r2, [r4, #0xc]             @ a, b
	subs r2, r2, r0
	muls r2, r1, r2
	add.w r0, r0, r2, asr #0x8          @ a + (amount * (b - a) >> 8)
.L0802aa80:
	str r0, [sp, #0x0]
.L0802aa82:
	ldr r0, [r6, #0xc]
	movs r7, #0x1                       @ r7 = changed flag
	add r2, sp, #0x4
	ldr.w r0, [r0, r5, lsl #0x3]
	mov r1, r3
	bl fn_08026dc4
	cbz r0, .L0802aaaa
	ldrd r0, r1, [sp, #0x0]
	cmp r0, r1
	bne.n .L0802aaaa
	ldrh.w r0, [sp, #0x0]
	ldrh.w r1, [sp, #0x4]
	cmp r0, r1
	bne.n .L0802aaaa
	movs r7, #0x0                       @ stored value equals the new one
.L0802aaaa:
	ldr r0, [r6, #0xc]
	ldrh r1, [r4, #0x4]
	ldr r2, [sp, #0x0]
	ldr.w r0, [r0, r5, lsl #0x3]
	bl fn_08027280
	cmp r7, #0x0
	beq.n .L0802aa2e
	ldrh r2, [r4, #0x4]
	ldr r1, [r4, #0x8]
	ldr r0, [r4, #0x0]
	bl fn_08025d34
	pop {r1, r2, r3, r4, r5, r6, r7, pc}
.L0802aac8:
	ldr r0, [r4, #0xc]                  @ colour a
	b.n .L0802aa80
.L0802aacc:
	ldr r0, [r4, #0x10]                 @ colour b
	b.n .L0802aa80
.L0802aad0:
	cmp r1, #0xff
	bge.n .L0802aacc
	b.n .L0802aac8
.L0802aad6:
	ldr r0, [r4, #0xc]
	cmp r0, #0x0
	beq.n .L0802aacc
	ldr r2, [r4, #0x10]
	cmp r2, #0x0
	beq.n .L0802aa80
	cmp r1, #0x80
	blt.n .L0802aa80
	str r2, [sp, #0x0]
	b.n .L0802aa82
.L0802aaea:
	cmp r1, #0x0
	bgt.n .L0802aaf2
	ldrh r0, [r4, #0xc]
	b.n .L0802ab34
.L0802aaf2:
	cmp r1, #0xff
	blt.n .L0802aafa
	ldrh r0, [r4, #0x10]
	b.n .L0802ab34
.L0802aafa:
	uxtb r0, r1
	ldrh r2, [r4, #0x10]
	ldrh.w r12, [r4, #0xc]
	.inst.n 0x1d00                      @ adds r0, r0, #4
	lsrs r7, r0, #0x3                   @ weight 0..31
	ldr r1, .L0802ab3c                  @ 0x07e0f81f
	uxth.w r0, r12
	uxth r2, r2
	orr.w r0, r0, r0, lsl #0x10
	orr.w r2, r2, r2, lsl #0x10
	ands r0, r1
	ands r2, r1
	subs r2, r2, r0
	muls r2, r7, r2
	add.w r0, r0, r2, lsr #0x5
	ands r0, r1
	orr.w r0, r0, r0, lsr #0x10
	strh.w r0, [sp, #0x8]
	uxth r0, r0
	str r0, [sp, #0x8]
	ldrh.w r0, [sp, #0x8]
.L0802ab34:
	strh.w r0, [sp, #0x0]
	b.n .L0802aa82
	.short 0x0000                       @ padding
.L0802ab3c:
	.word 0x07e0f81f

@ ----------------------------------------------------------------------------
@ fn_0802ab40 - removes an animation record and clears its property.
@ Parameter: r0 = pointer to a pointer to an animation record (record: object at
@ +0, property id halfword at +4, selector at +8).
@ Walks the record list at 0x200080a4 (get_word_4_or_zero and
@ read_word_at_base_plus_offset_4) and returns when another record has the same
@ object, selector (+8) and property halfword (+4).
@ Otherwise finds, among the 8-byte entries of the object (count = (halfword
@ +0x22 & 0x1ff) >> 3, array at word +0xc), the entry whose second word has bit
@ 25 set and whose low 24 bits equal the selector. Unlinks the record with
@ fn_080126a2(0x200080a4, record), frees it with fn_08022c68, removes the property
@ id from the entry object with fn_0802705c(entry object, id) and, when
@ fn_08026f14(entry object) is not 0, tail-calls fn_08025ede(object, entry
@ object, entry flags & 0xffffff).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802ab40,"ax",%progbits
	.p2align 2
	.global fn_0802ab40
	.thumb_func
	.type fn_0802ab40, %function
fn_0802ab40:
	push.w {r4, r5, r6, r7, r8, lr}
	ldr r4, [r0, #0x0]                  @ record
	ldr r0, .L0802abe0                  @ list head 0x200080a4
	ldrh r6, [r4, #0x4]                 @ property id
	ldr r5, [r4, #0x0]                  @ object
	bl get_word_4_or_zero
	b.n .L0802ab74
.L0802ab52:
	cmp r1, r4
	beq.n .L0802ab6e
	ldr r0, [r1, #0x0]
	ldr r2, [r4, #0x0]
	cmp r0, r2
	bne.n .L0802ab6e
	ldr r0, [r1, #0x8]
	ldr r2, [r4, #0x8]
	cmp r0, r2
	bne.n .L0802ab6e
	ldrh r0, [r1, #0x4]
	ldrh r2, [r4, #0x4]
	cmp r0, r2
	beq.n .L0802abdc
.L0802ab6e:
	ldr r0, .L0802abe0
	bl read_word_at_base_plus_offset_4
.L0802ab74:
	movs r1, r0
	bne.n .L0802ab52
	ldrh r1, [r5, #0x22]
	movs r7, #0x0                       @ entry index
	movs r0, #0x4
	ubfx r1, r1, #0x3, #0x6             @ entry count
	b.n .L0802abd8
.L0802ab84:
	ldr r2, [r5, #0xc]
	add.w r3, r0, r7, lsl #0x3
	ldr r2, [r2, r3]                    @ second word of entry r7
	lsls r3, r2, #0x6
	bpl.n .L0802abd6                    @ bit 25 clear
	ldr r3, [r4, #0x8]
	bic r2, r2, #0xff000000
	cmp r2, r3
	bne.n .L0802abd6
	mov r1, r4
	ldr r0, .L0802abe0
	bl fn_080126a2
	mov r0, r4
	bl fn_08022c68
	ldr r0, [r5, #0xc]
	mov r1, r6
	add.w r4, r0, r7, lsl #0x3
	ldr r0, [r4, #0x0]
	bl fn_0802705c
	ldr r0, [r5, #0xc]
	ldr.w r0, [r0, r7, lsl #0x3]
	bl fn_08026f14
	cmp r0, #0x0
	beq.n .L0802abdc
	ldr r0, [r4, #0x4]
	ldr r1, [r4, #0x0]
	bic r2, r0, #0xff000000
	mov r0, r5
	pop.w {r4, r5, r6, r7, r8, lr}
	b.w fn_08025ede                     @ tail call
.L0802abd6:
	.inst.n 0x1c7f                      @ adds r7, r7, #1
.L0802abd8:
	cmp r1, r7
	bhi.n .L0802ab84
.L0802abdc:
	pop.w {r4, r5, r6, r7, r8, pc}
.L0802abe0:
	.word 0x200080a4

@ ----------------------------------------------------------------------------
@ fn_0802abe4 - refreshes an animation record from the live property value.
@ Parameter: r0 = pointer to a pointer to an animation record (object at +0,
@ property id halfword at +4, selector at +8, value word at +0xc).
@ Reads the property with fn_08024bac(object, selector & 0xff0000, id) into
@ record word +0xc, clears the halfword property id at +4 while calling
@ fn_0802ac24(object, selector & 0xff0000, id, record), restores it, looks up
@ fn_0801b910(object, selector) and tail-calls fn_08027280(*entry, id, value).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802abe4,"ax",%progbits
	.p2align 2
	.global fn_0802abe4
	.thumb_func
	.type fn_0802abe4, %function
fn_0802abe4:
	push {r4, r5, r6, lr}
	ldr r4, [r0, #0x0]                  @ record
	ldr r0, [r4, #0x8]
	ldrh r2, [r4, #0x4]
	and r6, r0, #0xff0000               @ selector & 0xff0000
	mov r1, r6
	ldr r0, [r4, #0x0]
	bl fn_08024bac
	str r0, [r4, #0xc]
	ldrh r5, [r4, #0x4]
	movs r0, #0x0
	strh r0, [r4, #0x4]                 @ clear the property id
	mov r3, r4
	mov r2, r5
	mov r1, r6
	ldr r0, [r4, #0x0]
	bl fn_0802ac24
	strh r5, [r4, #0x4]                 @ restore the property id
	ldr r1, [r4, #0x8]
	ldr r0, [r4, #0x0]
	bl fn_0801b910
	ldrh r1, [r4, #0x4]
	ldr r0, [r0, #0x0]
	ldr r2, [r4, #0xc]
	pop.w {r4, r5, r6, lr}
	b.w fn_08027280                     @ tail call

@ ----------------------------------------------------------------------------
@ fn_0802ac24 - removes the animation records that match an object, selector and
@ property id.
@ Parameters: r0 = object, r1 = selector, r2 = property id, r3 = stop record.
@ Returns r0 = 1 when a record was removed, else 0.
@ Walks the record list at 0x200080a4 from get_word_8_or_zero until the record
@ r3 (or the end). For each record with the same object whose selector equals r1
@ (or r1 is 0xf0000) and whose property id equals r2 (or r2 is 0xffff): clears the
@ property on every entry of the object that has bit 25 set and a low 24 bits
@ value equal to the selector (any entry when r1 is 0xf0000) with fn_0802705c,
@ calls fn_0801c688(record, 0), unlinks it with fn_080126a2 and frees it with
@ fn_08022c68.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802ac24,"ax",%progbits
	.p2align 2
	.global fn_0802ac24
	.thumb_func
	.type fn_0802ac24, %function
fn_0802ac24:
	push.w {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, lr}
	mov r7, r0                          @ object
	mov r10, r3                         @ stop record
	mov r6, r1                          @ selector
	movs r5, #0x0                       @ result
	ldr r0, .L0802acc8                  @ list head 0x200080a4
	bl get_word_8_or_zero
	mov r4, r0
	mov.w r8, #0xf0000
	mov.w r9, #0x4
	b.n .L0802acbc
.L0802ac42:
	cmp r4, r10
	beq.n .L0802acc0
	mov r1, r4
	ldr r0, .L0802acc8
	bl read_word_at_base_plus_offset
	mov r11, r0                         @ next record
	ldr r0, [r4, #0x0]
	cmp r0, r7
	bne.n .L0802acba
	ldr r0, [r4, #0x8]
	cmp r0, r6
	beq.n .L0802ac60
	cmp r6, r8
	bne.n .L0802acba
.L0802ac60:
	ldrh r1, [r4, #0x4]
	ldr r0, [sp, #0x8]                  @ property id (saved r2)
	cmp r1, r0
	beq.n .L0802ac70
	sub.w r1, r0, #0xff00
	subs r1, #0xff                      @ zero when the id is 0xffff
	bne.n .L0802acba
.L0802ac70:
	movs r5, #0x0                       @ entry index
	b.n .L0802ac98
.L0802ac74:
	ldr r0, [r7, #0xc]
	add.w r1, r9, r5, lsl #0x3
	ldr r1, [r0, r1]                    @ second word of entry r5
	lsls r2, r1, #0x6
	bpl.n .L0802ac96                    @ bit 25 clear
	cmp r6, r8
	beq.n .L0802ac8c
	bic r1, r1, #0xff000000
	cmp r1, r6
	bne.n .L0802ac96
.L0802ac8c:
	ldr.w r0, [r0, r5, lsl #0x3]
	ldrh r1, [r4, #0x4]
	bl fn_0802705c
.L0802ac96:
	.inst.n 0x1c6d                      @ adds r5, r5, #1
.L0802ac98:
	ldrh r0, [r7, #0x22]
	ubfx r0, r0, #0x3, #0x6
	cmp r0, r5
	bhi.n .L0802ac74
	movs r1, #0x0
	mov r0, r4
	bl fn_0801c688
	mov r1, r4
	ldr r0, .L0802acc8
	bl fn_080126a2
	mov r0, r4
	bl fn_08022c68
	movs r5, #0x1
.L0802acba:
	mov r4, r11
.L0802acbc:
	cmp r4, #0x0
	bne.n .L0802ac42
.L0802acc0:
	add sp, #0x10
	mov r0, r5
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, r12, pc}
.L0802acc8:
	.word 0x200080a4

@ ----------------------------------------------------------------------------
@ fn_0802accc - applies the transform of an object to a point and calls
@ fn_08026878.
@ Parameters: r0 = object, r1 = first argument of fn_08026878 (kept in r8),
@ r2 = invert flag, r3 = unused.
@ Reads the properties 0x6d, 0x6c, 0x6e and 0x6f of the object with
@ fn_08024bac(object, 0, id); returns without effect when property 0x6d is 0 and
@ property 0x6c is 0x100. Builds a point on the stack (property 0x6e + halfword
@ +0x14, property 0x6f + halfword +0x16) and calls fn_08026878(r1, angle, scale,
@ &point); when r2 is not 0 the angle is negated and the scale becomes
@ 0x10000 / scale (both sign-extended from 16 bits).
@ ----------------------------------------------------------------------------
	.section .text.fn_0802accc,"ax",%progbits
	.p2align 2
	.global fn_0802accc
	.thumb_func
	.type fn_0802accc, %function
fn_0802accc:
	push.w {r3, r4, r5, r6, r7, r8, r9, lr}
	mov r7, r2                          @ invert flag
	mov r8, r1
	mov r4, r0                          @ object
	movs r1, #0x0
	movs r2, #0x6d
	bl fn_08024bac
	sxth r6, r0                         @ angle
	mov r0, r4
	movs r1, #0x0
	movs r2, #0x6c
	bl fn_08024bac
	sxth r5, r0                         @ scale
	cbnz r6, .L0802acf4
	cmp.w r5, #0x100
	beq.n .L0802ad34
.L0802acf4:
	mov r0, r4
	movs r1, #0x0
	movs r2, #0x6e
	bl fn_08024bac
	ldrh r1, [r4, #0x14]
	movs r2, #0x6f
	add r0, r1
	strh.w r0, [sp, #0x0]               @ point x
	mov r0, r4
	movs r1, #0x0
	bl fn_08024bac
	ldrh r1, [r4, #0x16]
	add r0, r1
	strh.w r0, [sp, #0x2]               @ point y
	cbz r7, .L0802ad28
	rsbs r0, r6, #0
	sxth r6, r0
	mov.w r0, #0x10000
	sdiv r0, r0, r5
	sxth r5, r0
.L0802ad28:
	mov r3, sp
	mov r2, r5
	mov r1, r6
	mov r0, r8
	bl fn_08026878
.L0802ad34:
	pop.w {r3, r4, r5, r6, r7, r8, r9, pc}

@ ----------------------------------------------------------------------------
@ fn_0802ad38 - transforms a point (x, y) by a transform record.
@ Parameters: r0 = transform record, r1 = x, r2 = y, r3 = pointer to the result x,
@ stack (sp+0x14 after the push) = pointer to the result y.
@ Without rotation (word +0x1c = 0) and with scale (word +0x18) 0x100 the results
@ are x << 8 and y << 8. Otherwise subtracts the halfword origin at +0x28 and
@ +0x2a; without rotation each result = value * scale (+0x18) + offset (+0x20 for
@ x, +0x24 for y). With rotation and scale 0x100 it uses the words at +0x10 and
@ +0x14 (result x = +0x20 + ((x * w14 - w10 * y) >> 2), result y = +0x24 +
@ ((w14 * y + x * w10) >> 2)); with another scale the same sums are multiplied by
@ the scale (+0x18) and shifted right by 10.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802ad38,"ax",%progbits
	.global fn_0802ad38
	.thumb_func
	.type fn_0802ad38, %function
fn_0802ad38:
	push {r4, r5, r6, r7, lr}
	ldrd r4, r6, [r0, #0x18]            @ r4 = scale, r6 = rotation word
	ldr r5, [sp, #0x14]                 @ pointer to the result y
	mov.w r7, #0x100
	cbnz r6, .L0802ad52
	cmp r4, r7
	bne.n .L0802ad52
	lsls r0, r1, #0x8
	str r0, [r3, #0x0]
	lsls r0, r2, #0x8
	b.n .L0802adc6
.L0802ad52:
	ldrsh.w r12, [r0, #0x28]
	sub.w r1, r1, r12
	ldrsh.w r12, [r0, #0x2a]
	sub.w r2, r2, r12
	cbz r6, .L0802ad8c
	cmp r4, r7
	bne.n .L0802ad9e
	ldr r4, [r0, #0x14]
	ldr r6, [r0, #0x10]
	muls r4, r1, r4
	mls r4, r6, r2, r4
	ldr r6, [r0, #0x20]
	add.w r4, r6, r4, asr #0x2
	str r4, [r3, #0x0]
	ldr r3, [r0, #0x10]
	muls r3, r1, r3
	ldr r1, [r0, #0x14]
	ldr r0, [r0, #0x24]
	mla r1, r1, r2, r3
	add.w r0, r0, r1, asr #0x2
	b.n .L0802adc6
.L0802ad8c:
	ldr r6, [r0, #0x20]
	mla r1, r1, r4, r6
	str r1, [r3, #0x0]
	ldr r1, [r0, #0x24]
	ldr r0, [r0, #0x18]
	mla r0, r2, r0, r1
	b.n .L0802adc6
.L0802ad9e:
	ldr r6, [r0, #0x14]
	ldr r7, [r0, #0x10]
	muls r6, r1, r6
	mls r6, r7, r2, r6
	muls r6, r4, r6
	ldr r4, [r0, #0x20]
	add.w r4, r4, r6, asr #0xa
	str r4, [r3, #0x0]
	ldr r3, [r0, #0x10]
	muls r3, r1, r3
	ldr r1, [r0, #0x14]
	mla r1, r1, r2, r3
	ldr r2, [r0, #0x18]
	ldr r0, [r0, #0x24]
	muls r1, r2, r1
	add.w r0, r0, r1, asr #0xa
.L0802adc6:
	str r0, [r5, #0x0]
	pop {r4, r5, r6, r7, pc}

@ ----------------------------------------------------------------------------
@ fn_0802add2 - maps a value onto two halfword results of an object.
@ Parameter: r0 = object (kept in r4); no return value. Entered only by the tail
@ jump b.w at 0x0801cf88 (from 0x0801cf66), so it returns to the caller of
@ 0x0801cf66.
@ v = int16 [r4+0x2e]; v = -0x8000 returns. r3 = int16 [r4+0x2c], plus 0x168 when
@ uxth(r3) is below halfword [r4+0x2a] (unsigned); r5 = halfword [r4+0x2a].
@ Mode m = bits 1..2 of byte [r4+0x34]; m = 3 returns. "map" is
@ fn_08022b12(value, start, end, result at start, result at end as stack word),
@ which interpolates the value between start and end onto the two results.
@   m = 0: r5 = sxth(map(v, int16 [r4+0x30], int16 [r4+0x32], r5, stack r3));
@          fn_0801ce6a(r4, halfword [r4+0x2a], uxth(r5))
@   m = 2: r5 = sxth(map(v, int16 [r4+0x30], int16 [r4+0x32], r3, stack r5));
@          fn_0801ce6a(r4, uxth(r5), halfword [r4+0x2c])
@   m = 1: r6 = (r5 + r3) / 2 and r1 = (int16 [r4+0x30] + int16 [r4+0x32]) / 2
@          (add lsr #31, then sbfx #1,#16: round toward zero); v below r1:
@          r5 = sxth(map(v, int16 [r4+0x30], r1, r5, stack r6)),
@          fn_0801cef4(r4, uxth(r5)), fn_0801ce82(r4, uxth(r6)); v at or above r1:
@          r5 = sxth(map(v, r1, int16 [r4+0x32], r6, stack r3)),
@          fn_0801cef4(r4, uxth(r6)), fn_0801ce82(r4, uxth(r5))
@ Then halfword [r4+0x3c] = r5 (0x0802ae90), pop {r3..r7,pc}.
@ ----------------------------------------------------------------------------
	.section .text.fn_0802add2,"ax",%progbits
	.global fn_0802add2
	.thumb_func
	.type fn_0802add2, %function
fn_0802add2:
	push {r3, r4, r5, r6, r7, lr}
	mov r4, r0
	ldrsh.w r0, [r0, #0x2e]             @ v
	cmn.w r0, #0x8000
	beq.n .L0802ae92
	ldrsh.w r3, [r4, #0x2c]
	ldrh r5, [r4, #0x2a]
	uxth r1, r3
	cmp r1, r5
	bcs.n .L0802adf2
	add.w r1, r1, #0x168
	sxth r3, r1
.L0802adf2:
	ldrb.w r1, [r4, #0x34]
	ubfx r1, r1, #0x1, #0x2             @ mode
	cbz r1, .L0802ae72
	cmp r1, #0x1
	beq.n .L0802ae1c
	cmp r1, #0x2
	bne.n .L0802ae92
	str r5, [sp, #0x0]
	ldrsh.w r2, [r4, #0x32]
	ldrsh.w r1, [r4, #0x30]
	bl fn_08022b12
	sxth r5, r0
	mov r0, r4
	ldrh r2, [r4, #0x2c]
	uxth r1, r5
	b.n .L0802ae8c
.L0802ae1c:
	adds r1, r5, r3
	add.w r1, r1, r1, lsr #0x1f
	ldrsh.w r7, [r4, #0x30]
	ldrsh.w r2, [r4, #0x32]
	sbfx r6, r1, #0x1, #0x10            @ (r5 + r3) / 2
	adds r1, r7, r2
	add.w r1, r1, r1, lsr #0x1f
	sbfx r1, r1, #0x1, #0x10            @ (start + end) / 2
	cmp r0, r1
	bge.n .L0802ae56
	mov r2, r1
	mov r3, r5
	mov r1, r7
	str r6, [sp, #0x0]
	bl fn_08022b12
	sxth r5, r0
	uxth r1, r5
	mov r0, r4
	bl fn_0801cef4
	uxth r1, r6
	b.n .L0802ae6a
.L0802ae56:
	str r3, [sp, #0x0]
	mov r3, r6
	bl fn_08022b12
	sxth r5, r0
	uxth r1, r6
	mov r0, r4
	bl fn_0801cef4
	uxth r1, r5
.L0802ae6a:
	mov r0, r4
	bl fn_0801ce82
	b.n .L0802ae90
.L0802ae72:
	b.n .L0802ae74
.L0802ae74:
	str r3, [sp, #0x0]
	ldrsh.w r2, [r4, #0x32]
	ldrsh.w r1, [r4, #0x30]
	mov r3, r5
	bl fn_08022b12
	sxth r5, r0
	uxth r2, r5
	mov r0, r4
	ldrh r1, [r4, #0x2a]
.L0802ae8c:
	bl fn_0801ce6a
.L0802ae90:
	strh r5, [r4, #0x3c]
.L0802ae92:
	pop {r3, r4, r5, r6, r7, pc}
