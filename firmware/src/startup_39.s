@ startup_39.s - start-up code: reset handler, scatter-load call, jump to the main entry, default branch-to-self handlers.
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08006258 - second stage of the start-up. No parameters, never returns.
@ Loads sp from the literal at 0x0800626c (word 0x200163a8), then calls
@ __scatterload (0x0800784c), which does not return. The code falls into
@ fn_08006260 (0x08006260). Entered from Reset_Handler through the word
@ 0x08006259 at 0x08006290.
@ ----------------------------------------------------------------------------
	.section .text.fn_08006258,"ax",%progbits
	.p2align 2
	.global fn_08006258
	.thumb_func
	.type fn_08006258, %function
fn_08006258:
	ldr.w	sp, .L0800626c
	bl	__scatterload

@ ----------------------------------------------------------------------------
@ fn_08006260 - jump to the main entry. No parameters, never returns.
@ Loads r0 from the literal at 0x08006264 (word 0x08027ff5, the address of
@ fn_08027ff4 with the Thumb bit) and jumps there with bx r0. The words after
@ the code are: 0x08006268 four bytes af f3 00 80, 0x0800626c the initial
@ stack pointer value 0x200163a8 used by fn_08006258.
@ ----------------------------------------------------------------------------
	.global fn_08006260
	.thumb_func
	.type fn_08006260, %function
fn_08006260:
	ldr	r0, .L08006264
	bx	r0
.L08006264:
	.word	fn_08027ff4
	.byte	0xaf, 0xf3, 0x00, 0x80
.L0800626c:
	.word	0x200163a8

@ ----------------------------------------------------------------------------
@ Reset_Handler - reset entry, reached through vector table word 1
@ (0x08006271). No parameters, never returns.
@ Calls fn_0800c274 (address from the literal at 0x0800628c) with blx, then
@ jumps with bx to the word at 0x08006290 (0x08006259 = fn_08006258).
@ Our build (.ifdef OWN at the literal 0x0800628C): the call goes to own_reset
@ (own/boot.s: progress word, SCLKSW = HSI alone with a bounded wait for SCLKSTS,
@ then fn_0800c274; MEASUREMENT_FIX_DESIGN.md revision 17).
@ ----------------------------------------------------------------------------
	.section .text.Reset_Handler,"ax",%progbits
	.p2align 2
	.global Reset_Handler
	.thumb_func
	.type Reset_Handler, %function
Reset_Handler:
	ldr	r0, .L0800628c
	blx	r0
	ldr	r0, .L08006290
	bx	r0

@ ----------------------------------------------------------------------------
@ branch_to_self_08006278 - one instruction that branches to itself
@ (infinite loop). No parameters.
@ ----------------------------------------------------------------------------
	.global branch_to_self_08006278
	.thumb_func
	.type branch_to_self_08006278, %function
branch_to_self_08006278:
	b.n	branch_to_self_08006278

@ ----------------------------------------------------------------------------
@ branch_to_self_0800627a - one instruction that branches to itself
@ (infinite loop). No parameters.
@ ----------------------------------------------------------------------------
	.global branch_to_self_0800627a
	.thumb_func
	.type branch_to_self_0800627a, %function
branch_to_self_0800627a:
	b.n	branch_to_self_0800627a

@ ----------------------------------------------------------------------------
@ branch_to_self_0800627c - one instruction that branches to itself
@ (infinite loop). No parameters.
@ ----------------------------------------------------------------------------
	.global branch_to_self_0800627c
	.thumb_func
	.type branch_to_self_0800627c, %function
branch_to_self_0800627c:
	b.n	branch_to_self_0800627c

@ ----------------------------------------------------------------------------
@ branch_to_self_0800627e - one instruction that branches to itself
@ (infinite loop). No parameters.
@ ----------------------------------------------------------------------------
	.global branch_to_self_0800627e
	.thumb_func
	.type branch_to_self_0800627e, %function
branch_to_self_0800627e:
	b.n	branch_to_self_0800627e

@ ----------------------------------------------------------------------------
@ branch_to_self_08006280 - one instruction that branches to itself
@ (infinite loop). No parameters.
@ ----------------------------------------------------------------------------
	.global branch_to_self_08006280
	.thumb_func
	.type branch_to_self_08006280, %function
branch_to_self_08006280:
	b.n	branch_to_self_08006280

@ ----------------------------------------------------------------------------
@ branch_to_self_08006282 - one instruction that branches to itself
@ (infinite loop). No parameters.
@ ----------------------------------------------------------------------------
	.global branch_to_self_08006282
	.thumb_func
	.type branch_to_self_08006282, %function
branch_to_self_08006282:
	b.n	branch_to_self_08006282

@ ----------------------------------------------------------------------------
@ branch_to_self_08006284 - one instruction that branches to itself
@ (infinite loop). No parameters.
@ ----------------------------------------------------------------------------
	.global branch_to_self_08006284
	.thumb_func
	.type branch_to_self_08006284, %function
branch_to_self_08006284:
	b.n	branch_to_self_08006284

@ ----------------------------------------------------------------------------
@ branch_to_self_08006286 - one instruction that branches to itself
@ (infinite loop). No parameters.
@ ----------------------------------------------------------------------------
	.global branch_to_self_08006286
	.thumb_func
	.type branch_to_self_08006286, %function
branch_to_self_08006286:
	b.n	branch_to_self_08006286

@ ----------------------------------------------------------------------------
@ branch_to_self_08006288 - one instruction that branches to itself
@ (infinite loop). No parameters.
@ ----------------------------------------------------------------------------
	.global branch_to_self_08006288
	.thumb_func
	.type branch_to_self_08006288, %function
branch_to_self_08006288:
	b.n	branch_to_self_08006288

@ ----------------------------------------------------------------------------
@ branch_to_self_0800628a - one instruction that branches to itself
@ (infinite loop). No parameters. Followed by the two words used by
@ Reset_Handler: 0x0800628c holds 0x0800c275 (fn_0800c274 with the Thumb
@ bit), 0x08006290 holds 0x08006259 (fn_08006258 with the Thumb bit).
@ ----------------------------------------------------------------------------
	.global branch_to_self_0800628a
	.thumb_func
	.type branch_to_self_0800628a, %function
branch_to_self_0800628a:
	b.n	branch_to_self_0800628a
.L0800628c:
.ifdef OWN
	.word	own_reset		@ 0x0800628C: own/boot.s, which then calls fn_0800c274
.else
	.word	fn_0800c274
.endif
.L08006290:
	.word	fn_08006258
