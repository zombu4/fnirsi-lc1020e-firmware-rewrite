@ app_01.s - application functions 0x080093b8..0x0800b000 (output-bit drivers, key scan and key handlers)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_080093b8 - drives two output bits from a mode value.
@ Parameter: r0 = mode; no return value.
@ Calls fn_08008350(port, mask, value) twice (the second call is a tail call):
@   mode 3: (0x40011000, 8, 0), (0x40010800, 1, 0)
@   mode 2: (0x40011000, 8, 0), (0x40010800, 1, 1)
@   mode 1: (0x40011000, 8, 1), (0x40010800, 1, 0)
@   any other mode: (0x40011000, 8, 1), (0x40010800, 1, 1)
@ r3 = 0x40011000 and r4 = 0x40010800 come from the literal pool at the end.
@ ----------------------------------------------------------------------------
	.section .text.fn_080093b8,"ax",%progbits
	.p2align 2
	.global fn_080093b8
	.thumb_func
	.type fn_080093b8, %function
fn_080093b8:
	push {r4, lr}
	ldr r3, .L080093f8              @ r3 = 0x40011000
	ldr r4, .L080093fc              @ r4 = 0x40010800
	cmp r0, #3
	beq.n .L080093d0
	cmp r0, #2
	beq.n .L080093de
	cmp r0, #1
	mov.w r2, #1                    @ value 1 for the other modes
	beq.n .L080093d2
	b.n .L080093e0
.L080093d0:
	movs r2, #0
.L080093d2:
	movs r1, #8
	mov r0, r3
	bl fn_08008350                  @ (0x40011000, 8, r2)
	movs r2, #0
	b.n .L080093ea
.L080093de:
	movs r2, #0
.L080093e0:
	movs r1, #8
	mov r0, r3
	bl fn_08008350                  @ (0x40011000, 8, r2)
	movs r2, #1
.L080093ea:
	mov r0, r4
	pop.w {r4, lr}
	movs r1, #1
	b.w fn_08008350                 @ tail call (0x40010800, 1, r2)
	.short 0x0000                   @ padding
.L080093f8:
	.word 0x40011000
.L080093fc:
	.word 0x40010800

@ ----------------------------------------------------------------------------
@ fn_08009400 - handles a pending key event.
@ No parameters, no return value.
@ Does nothing while halfword 0x20001192 (event code) is 0.
@ Otherwise clears word 0x2000511c, then by event code:
@   code 1: calls fn_08009614 (screen state word 0x20001168 = 1 or 2),
@     fn_08009974 (3) or fn_080095f0 (0), then fn_08008120(0x32)
@   code 0xfe: when halfword 0x20001194 (key mask) = 1 and halfword
@     0x20001190 = 0: stores 1 to 0x20001190, calls fn_08014b94,
@     fn_08008120(200), fn_0800b274; when the key mask is not 1 it calls
@     fn_08009614 or fn_08009974 by the screen state 0x20001168
@   code 0xff: stores 0 to halfword 0x20001190
@ Finally stores 0 to the event code 0x20001192.
@ r4 = 0x2000057c (literal), the fields are at offsets 0xc14..0xc18 from it.
@ ----------------------------------------------------------------------------
	.section .text.fn_08009400,"ax",%progbits
	.p2align 2
	.global fn_08009400
	.thumb_func
	.type fn_08009400, %function
fn_08009400:
	push {r4, r5, r6, lr}
	ldr r4, .L0800949c              @ r4 = 0x2000057c
	ldrh.w r1, [r4, #0xc16]         @ r1 = event code (0x20001192)
	cmp r1, #0
	beq.n .L08009498
	add.w r0, r4, #0x4000
	movs r5, #0
	str.w r5, [r0, #0xba0]          @ word 0x2000511c = 0
	mov r0, r4
	cmp r1, #1
	ldr.w r0, [r0, #0xbec]          @ r0 = screen state (0x20001168)
	beq.n .L0800942a
	cmp r1, #0xfe
	beq.n .L08009452
	cmp r1, #0xff
	beq.n .L08009490
	b.n .L08009494
.L0800942a:
	cmp r0, #1
	beq.n .L0800943a
	cmp r0, #2
	beq.n .L0800943a
	cmp r0, #3
	beq.n .L08009440
	cbz r0, .L08009446
	b.n .L0800944a
.L0800943a:
	bl fn_08009614
	b.n .L0800944a
.L08009440:
	bl fn_08009974
	b.n .L0800944a
.L08009446:
	bl fn_080095f0
.L0800944a:
	movs r0, #0x32
	bl fn_08008120
	b.n .L08009494
.L08009452:
	ldrh.w r1, [r4, #0xc18]         @ r1 = key mask (0x20001194)
	cmp r1, #1
	beq.n .L08009468
	cmp r0, #1
	beq.n .L08009484
	cmp r0, #2
	beq.n .L08009484
	cmp r0, #3
	beq.n .L0800948a
	b.n .L08009494
.L08009468:
	ldrh.w r0, [r4, #0xc14]         @ r0 = halfword 0x20001190
	cbnz r0, .L08009494
	movs r0, #1
	strh.w r0, [r4, #0xc14]         @ 0x20001190 = 1
.ifdef OWN
	bl own_save                     @ 0x08009474: our save (own/save.s)
.else
	bl fn_08014b94
.endif
	movs r0, #0xc8
	bl fn_08008120
	bl fn_0800b274
	b.n .L08009494
.L08009484:
	bl fn_08009614
	b.n .L08009494
.L0800948a:
	bl fn_08009974
	b.n .L08009494
.L08009490:
	strh.w r5, [r4, #0xc14]         @ 0x20001190 = 0
.L08009494:
	strh.w r5, [r4, #0xc16]         @ event code 0x20001192 = 0
.L08009498:
	pop {r4, r5, r6, pc}
	.short 0x0000                   @ padding
.L0800949c:
	.word 0x2000057c

@ ----------------------------------------------------------------------------
@ fn_080094a0 - scans 14 key inputs and turns changes into key events.
@ No parameters, no return value.
@ Reads 14 inputs with fn_080081fa(port, mask) and builds a bit mask in r4
@ (a bit is set when the input reads zero; the one exception is input
@ 0x40010c00 mask 0x80, which sets bit 0x200 when it reads nonzero):
@   bit 0x1 port 0x40011000 mask 0x40     bit 0x2 port 0x40011000 mask 0x80
@   bit 0x4 port 0x40011000 mask 0x100    bit 0x8 port 0x40011000 mask 0x200
@   bit 0x10 port 0x40011000 mask 0x400   bit 0x20 port 0x40010800 mask 0x8000
@   bit 0x40 port 0x40011000 mask 0x800   bit 0x80 port 0x40011000 mask 0x1000
@   bit 0x100 port 0x40010c00 mask 0x20   bit 0x200 port 0x40010c00 mask 0x80
@   bit 0x400 port 0x40011800 mask 0x40   bit 0x800 port 0x40010c00 mask 0x100
@   bit 0x1000 port 0x40010c00 mask 0x200 bit 0x2000 port 0x40011800 mask 1
@ The mask replaces halfword 0x20000008 (the old value is kept in r3).
@ New bits = mask and not old; released bits = mask xor new xor old.
@ Any new bit stores 0 to the counter halfword 0x20001196. A nonzero mask
@ increments the counter; when its old value was above 99 it stores 0xfe to
@ the event code 0x20001192 and the mask to the key mask 0x20001194.
@ Released bits with the counter above 2 store 1 (counter below 100) or
@ 0xff in the event code 0x20001192 and the released bits in 0x20001194.
@ Literal pool: 0x40011000, 0x40010800, 0x40010c00, 0x40011800,
@ 0x20000008 and 0x2000057c (counter and event fields at offsets 0xc16..0xc1a).
@ ----------------------------------------------------------------------------
	.section .text.fn_080094a0,"ax",%progbits
	.p2align 2
	.global fn_080094a0
	.thumb_func
	.type fn_080094a0, %function
fn_080094a0:
	push.w {r4, r5, r6, r7, r8, lr}
	ldr r5, .L080095d8              @ r5 = 0x40011000
	movs r4, #0
	movs r1, #0x40
	mov r0, r5
	bl fn_080081fa
	cbnz r0, .L080094b4
	movs r4, #1
.L080094b4:
	movs r1, #0x80
	mov r0, r5
	bl fn_080081fa
	cbnz r0, .L080094c2
	orr.w r4, r4, #2
.L080094c2:
	mov.w r6, #0x100
	mov r1, r6
	mov r0, r5
	bl fn_080081fa
	cbnz r0, .L080094d4
	orr.w r4, r4, #4
.L080094d4:
	mov.w r8, #0x200
	mov r1, r8
	mov r0, r5
	bl fn_080081fa
	cbnz r0, .L080094e6
	orr.w r4, r4, #8
.L080094e6:
	mov.w r1, #0x400
	mov r0, r5
	bl fn_080081fa
	cbnz r0, .L080094f6
	orr.w r4, r4, #0x10
.L080094f6:
	mov.w r1, #0x8000
	ldr r0, .L080095dc              @ r0 = 0x40010800
	bl fn_080081fa
	cbnz r0, .L08009506
	orr.w r4, r4, #0x20
.L08009506:
	mov.w r1, #0x800
	mov r0, r5
	bl fn_080081fa
	cbnz r0, .L08009516
	orr.w r4, r4, #0x40
.L08009516:
	mov.w r1, #0x1000
	mov r0, r5
	bl fn_080081fa
	cbnz r0, .L08009526
	orr.w r4, r4, #0x80
.L08009526:
	ldr r5, .L080095e0              @ r5 = 0x40010c00
	movs r1, #0x20
	mov r0, r5
	bl fn_080081fa
	cbnz r0, .L08009536
	orr.w r4, r4, #0x100
.L08009536:
	movs r1, #0x80
	mov r0, r5
	bl fn_080081fa
	cbz r0, .L08009544              @ this input sets its bit when nonzero
	orr.w r4, r4, #0x200
.L08009544:
	ldr r7, .L080095e4              @ r7 = 0x40011800
	movs r1, #0x40
	mov r0, r7
	bl fn_080081fa
	cbnz r0, .L08009554
	orr.w r4, r4, #0x400
.L08009554:
	mov r1, r6
	mov r0, r5
	bl fn_080081fa
	cbnz r0, .L08009562
	orr.w r4, r4, #0x800
.L08009562:
	mov r1, r8
	mov r0, r5
	bl fn_080081fa
	cbnz r0, .L08009570
	orr.w r4, r4, #0x1000
.L08009570:
	movs r1, #1
	mov r0, r7
	bl fn_080081fa
	cbnz r0, .L0800957e
	orr.w r4, r4, #0x2000
.L0800957e:
	ldr r0, .L080095e8              @ r0 = 0x20000008
	ldrh r3, [r0, #0]               @ r3 = old mask
	strh r4, [r0, #0]               @ store the new mask
	bics.w r2, r4, r3               @ r2 = new bits
	eor.w r1, r4, r2
	ldr r0, .L080095ec              @ r0 = 0x2000057c
	eor.w r1, r1, r3                @ r1 = released bits
	beq.n .L0800959a
	movs r2, #0
	strh.w r2, [r0, #0xc1a]         @ counter 0x20001196 = 0
.L0800959a:
	cbz r4, .L080095b4
	ldrh.w r2, [r0, #0xc1a]
	adds r3, r2, #1
	strh.w r3, [r0, #0xc1a]         @ counter + 1
	cmp r2, #0x63
	bls.n .L080095b4
	movs r2, #0xfe
	strh.w r2, [r0, #0xc16]         @ event code 0x20001192 = 0xfe
	strh.w r4, [r0, #0xc18]         @ key mask 0x20001194 = mask
.L080095b4:
	cmp r1, #0
	beq.n .L080095d2
	ldrh.w r2, [r0, #0xc1a]
	cmp r2, #2
	bls.n .L080095d2
	strh.w r1, [r0, #0xc18]         @ key mask 0x20001194 = released bits
	cmp r2, #0x63
	bls.n .L080095cc
	movs r1, #0xff
	b.n .L080095ce
.L080095cc:
	movs r1, #1
.L080095ce:
	strh.w r1, [r0, #0xc16]         @ event code 0x20001192 = 1 or 0xff
.L080095d2:
	pop.w {r4, r5, r6, r7, r8, pc}
	.short 0x0000                   @ padding
.L080095d8:
	.word 0x40011000
.L080095dc:
	.word 0x40010800
.L080095e0:
	.word 0x40010c00
.L080095e4:
	.word 0x40011800
.L080095e8:
	.word 0x20000008
.L080095ec:
	.word 0x2000057c

@ ----------------------------------------------------------------------------
@ fn_080095f0 - key handler for screen state 0.
@ No parameters, no return value of its own.
@ r0 = 0x2000057c (literal); returns unless the event code halfword
@ 0x20001192 (r0 + 0xc16) equals 1.
@ Then loads the key mask halfword 0x20001194 (r0 + 0xc18); when it is 8,
@ 0x10 or 4 it tail-calls fn_0800d8f0, otherwise it returns.
@ It does not clear the event code 0x20001192.
@ ----------------------------------------------------------------------------
	.section .text.fn_080095f0,"ax",%progbits
	.p2align 2
	.global fn_080095f0
	.thumb_func
	.type fn_080095f0, %function
fn_080095f0:
	ldr r0, .L08009610              @ r0 = 0x2000057c
	ldrh.w r1, [r0, #0xc16]
	cmp r1, #1
	bne.n .L0800960e
	ldrh.w r0, [r0, #0xc18]         @ r0 = key mask
	cmp r0, #8
	beq.n .L0800960a
	cmp r0, #0x10
	beq.n .L0800960a
	cmp r0, #4
	bne.n .L0800960e
.L0800960a:
	b.w fn_0800d8f0                 @ tail call with r0 = key mask
.L0800960e:
	bx lr
.L08009610:
	.word 0x2000057c

@ ----------------------------------------------------------------------------
@ fn_08009614 - key handler for screen states 1 and 2.
@ No parameters. Every path ends in pop pc or a tail call (b.w).
@ r4 = 0x2000057c (literal), r5 = 0x200001d4 (literal). Event code = halfword
@ 0x20001192 (r4 + 0xc16), key mask r0 = halfword 0x20001194 (r4 + 0xc18).
@ Halfword 0x20001190 (r4 + 0xc14) is a busy flag. Code 1 goes to 0x08009670,
@ code 0xfe continues at 0x0800963a, any other code returns at 0x080097de
@ without clearing 0x20001192.
@ Code 0xfe: stores 0 to halfword 0x20001192.
@   mask 8: returns when halfword 0x20001190 is nonzero; otherwise stores 1 to
@     it, calls fn_08008120(0x32) and fn_08023690(word [0x200001d8]), copies
@     word 0x20001168 into word 0x200011bc and tail-calls fn_0800d6e4.
@   mask 0x400: returns when 0x20001190 is nonzero; otherwise stores 1 to it,
@     calls fn_08008120(0x32) and fn_08023690(word [0x200001d8]); with word
@     0x20001168 = 1 it tail-calls fn_0800d50c, otherwise fn_0800ca2c.
@   mask 0x1000: returns when 0x20001190 is nonzero; otherwise stores 1 to it,
@     calls fn_08008120(0x32), increments word 0x20001154 (r4 + 0xbd8; stored
@     0 when the result is above 2) and tail-calls fn_08021c14(word
@     [0x200001e4], p) with p = 0x0803cdc4 (value 0 or 3 and above), 0x0803cff4
@     (value 1) or 0x0803d224 (value 2).
@   mask 0x80: stores 1 to halfword 0x20001190 when it was 0 and returns.
@   mask 0x20 calls fn_0800d940(0xffffffff) and tail-calls fn_0800da6c; any
@     other mask returns.
@ Code 1: stores 0 to halfword 0x20001192.
@   mask 8: returns.
@   mask 0x400: when word 0x200011a4 (r4 + 0xc28) is 0 it stores 1 to it and
@     tail-calls fn_08023558(word [0x200001dc], 1); when it is nonzero it stores
@     0 to it, calls fn_08023050(word [0x200001dc], 1) and stores 1 to byte
@     0x200011c4.
@   mask 0x200: increments word 0x20001148 (stored 0 when above 4). Values 1..4
@     store the value to byte 0x200011e4 and word 0x200011e8 and call
@     fn_08021c14(word [0x200001fc], p) then fn_08021c14(word [0x200001e8], q)
@     with (p, q) = (0x0803da44, 0x0803d2fc), (0x0803dd04, 0x0803d3d4),
@     (0x0803de64, 0x0803d584), (0x0803dfc4, 0x0803d8e4). Value 0 (after the
@     reset) calls only fn_08021c14(word [0x200001fc], 0x0803dba4). Then
@     fn_080228d0(word [0x200001f0], "%s", word [0x20000258 + word[0x2000115c]
@     * 24 + word[0x20001148] * 4]) sets the text, fn_08009f10 is called, and
@     with word 0x20001168 = 2: word 0x20001148 = 2 stores 2 and = 3 stores 3
@     to word 0x20001178; any other value stores 1 to word 0x20001178, 1 to
@     byte 0x200011e4 and to 0x20001148 and sets the texts again from row
@     entry 1 (fn_080228d0 and the fn_08021c14 calls with 0x0803da44,
@     0x0803d2fc). Every path then tail-calls fn_0800f854.
@   mask 0x40: increments word 0x200011e8 (stored 0 when above 4) and
@     tail-calls fn_0800f854.
@   mask 0x1000: increments word 0x20001150 (stored 0 when above 2); r2 = word
@     0x2000115c; calls fn_08021c14(word [0x200001e0], p) with p = 0x08040f10
@     (value 0, r2 nonzero), 0x0803c690 (0, r2 = 0), 0x08041184 (1, r2
@     nonzero), 0x0803c91c (1, r2 = 0), 0x08040c9c (2, r2 nonzero), 0x0803cba8
@     (2, r2 = 0); then tail-calls fn_08009f10.
@   other masks: 0x80, 0x2000, 0x800 and 0x100 store 3, 0, 1 and 2 to word
@     0x200011a8 (r4 + 0xc2c) and call fn_0800d940(1); mask 2 calls
@     fn_0800d940(1); mask 0x20 calls fn_0800d940(0xffffffff); mask 0x10
@     (word 0x200011a8 decremented when above 0) and mask 4 (incremented when
@     below 3) change 0x200011a8 without calling fn_0800d940; after these
@     masks it tail-calls fn_0800da6c; other masks return.
@ Literal words of this function are at 0x08009920..0x08009973 (outside the
@ body range 0x08009614..0x0800991f): the two base addresses, text and table
@ pointers, and the string "%s".
@ ----------------------------------------------------------------------------
	.section .text.fn_08009614,"ax",%progbits
	.p2align 2
	.global fn_08009614
	.thumb_func
	.type fn_08009614, %function
fn_08009614:
	push.w {r4, r5, r6, r7, r8, r9, r10, lr}
	ldr r4, .L08009920              @ r4 = 0x2000057c
	mov.w r2, #0x400
	mov r0, r4
	ldrh.w r3, [r4, #0xc16]         @ r3 = event code
	lsls r1, r2, #2                 @ r1 = 0x1000
	movs r6, #1
	ldr r5, .L08009924              @ r5 = 0x200001d4
	ldrh.w r0, [r0, #0xc18]         @ r0 = key mask
	mov.w r8, #0
	cmp r3, #1
	beq.n .L08009670
	cmp r3, #0xfe
	bne.n .L08009720
	mov r3, r4
	strh.w r8, [r4, #0xc16]         @ event code = 0
	ldrh.w r3, [r3, #0xc14]         @ r3 = busy flag
	cmp r0, #8
	beq.n .L08009722
	cmp r0, r2
	bne.n .L08009724
	cmp r3, #0
	bne.n .L08009720
	strh.w r6, [r4, #0xc14]         @ busy flag = 1
	movs r0, #0x32
	bl fn_08008120
	ldr r0, [r5, #4]                @ word 0x200001d8
	bl fn_08023690
	ldr.w r0, [r4, #0xbec]          @ screen state 0x20001168
	cmp r0, #1
	beq.n .L0800974c
	pop.w {r4, r5, r6, r7, r8, r9, r10, lr}
	b.w fn_0800ca2c
.L08009670:
	strh.w r8, [r4, #0xc16]         @ event code = 0
	cmp r0, #8
	beq.n .L08009720
	movs r7, #2
	mov.w r9, #3
	cmp.w r0, #0x200
	beq.n .L080096ae
	cmp r0, #0x40
	beq.n .L08009784
	cmp r0, r2
	bne.n .L08009786
	ldr.w r0, [r4, #0xc28]          @ word 0x200011a4
	cmp r0, #0
	beq.n .L08009788
	movs r1, #0
.L08009696:
	ldr r0, .L08009924              @ r0 = 0x200001d4
	str.w r1, [r4, #0xc28]          @ word 0x200011a4 = r1
	cmp r1, #0
	ldr r0, [r0, #8]                @ word 0x200001dc
	mov.w r1, #1
	beq.n .L0800978a
	pop.w {r4, r5, r6, r7, r8, r9, r10, lr}
	b.w fn_08023558
.L080096ae:
	ldr.w r1, [r4, #0xbcc]          @ word 0x20001148
	ldr r0, .L08009924              @ r0 = 0x200001d4
	.inst.n 0x1c49                  @ adds r1, r1, #1
	str.w r1, [r4, #0xbcc]
	ldr r0, [r0, #0x28]             @ word 0x200001fc
	cmp r1, #4
	ble.n .L080096c6
	str.w r8, [r4, #0xbcc]          @ above 4: back to 0
	b.n .L080096d6
.L080096c6:
	cmp r1, #1
	beq.n .L0800970e
	cmp r1, #2
	beq.n .L08009726
	cmp r1, #3
	beq.n .L0800973a
	cmp r1, #4
	beq.n .L0800974e
.L080096d6:
	ldr r1, .L08009928              @ r1 = 0x0803dba4
.L080096d8:
	bl fn_08021c14
	ldr.w r0, [r4, #0xbe0]          @ word 0x2000115c
	ldr.w r8, .L08009924            @ r8 = 0x200001d4
	add.w r1, r0, r0, lsl #1
	add.w r8, r8, #0x84             @ r8 = 0x20000258
	add.w r0, r8, r1, lsl #3
	ldr.w r1, [r4, #0xbcc]          @ word 0x20001148
	ldr.w r2, [r0, r1, lsl #2]
	adr r1, .L0800992c              @ r1 = "%s"
	ldr r0, [r5, #0x1c]             @ word 0x200001f0
	bl fn_080228d0
	bl fn_08009f10
	ldr.w r0, [r4, #0xbec]          @ screen state 0x20001168
	cmp r0, #2
	beq.n .L08009762
	b.n .L080097ca
.L0800970e:
	strb.w r6, [r4, #0xc68]         @ byte 0x200011e4 = 1
	ldr r1, .L08009930              @ r1 = 0x0803da44
	str.w r6, [r4, #0xc6c]          @ word 0x200011e8 = 1
	bl fn_08021c14
	ldr r1, .L08009934              @ r1 = 0x0803d2fc
	b.n .L08009736
.L08009720:
	b.n .L080097de
.L08009722:
	b.n .L080098a2
.L08009724:
	b.n .L080098ce
.L08009726:
	strb.w r7, [r4, #0xc68]         @ byte 0x200011e4 = 2
	ldr r1, .L08009938              @ r1 = 0x0803dd04
	str.w r7, [r4, #0xc6c]          @ word 0x200011e8 = 2
	bl fn_08021c14
	ldr r1, .L0800993c              @ r1 = 0x0803d3d4
.L08009736:
	ldr r0, [r5, #0x14]             @ word 0x200001e8
	b.n .L080096d8
.L0800973a:
	strb.w r9, [r4, #0xc68]         @ byte 0x200011e4 = 3
	ldr r1, .L08009940              @ r1 = 0x0803de64
	str.w r9, [r4, #0xc6c]          @ word 0x200011e8 = 3
	bl fn_08021c14
	ldr r1, .L08009944              @ r1 = 0x0803d584
	b.n .L08009736
.L0800974c:
	b.n .L080098c6
.L0800974e:
	movs r1, #4
	strb.w r1, [r4, #0xc68]         @ byte 0x200011e4 = 4
	str.w r1, [r4, #0xc6c]          @ word 0x200011e8 = 4
	ldr r1, .L08009948              @ r1 = 0x0803dfc4
	bl fn_08021c14
	ldr r1, .L0800994c              @ r1 = 0x0803d8e4
	b.n .L08009736
.L08009762:
	ldr.w r0, [r4, #0xbcc]          @ word 0x20001148
	cmp r0, #2
	beq.n .L080097ac
	cmp r0, #3
	beq.n .L080097b2
	str.w r6, [r4, #0xbfc]          @ word 0x20001178 = 1
	strb.w r6, [r4, #0xc68]         @ byte 0x200011e4 = 1
	str.w r6, [r4, #0xbcc]          @ word 0x20001148 = 1
	ldr.w r0, [r4, #0xbe0]          @ word 0x2000115c
	add.w r1, r0, r0, lsl #1
	b.n .L0800978c
.L08009784:
	b.n .L080097b8
.L08009786:
	b.n .L080097e2
.L08009788:
	b.n .L080097d2
.L0800978a:
	b.n .L080097d6
.L0800978c:
	add.w r0, r8, r1, lsl #3
	adr r1, .L0800992c              @ r1 = "%s"
	ldr r2, [r0, #4]                @ row entry 1
	ldr r0, [r5, #0x1c]             @ word 0x200001f0
	bl fn_080228d0
	ldr r1, .L08009930              @ r1 = 0x0803da44
	ldr r0, [r5, #0x28]             @ word 0x200001fc
	bl fn_08021c14
	ldr r1, .L08009934              @ r1 = 0x0803d2fc
	ldr r0, [r5, #0x14]             @ word 0x200001e8
	bl fn_08021c14
	b.n .L080097ca
.L080097ac:
	str.w r7, [r4, #0xbfc]          @ word 0x20001178 = 2
	b.n .L080097ca
.L080097b2:
	str.w r9, [r4, #0xbfc]          @ word 0x20001178 = 3
	b.n .L080097ca
.L080097b8:
	ldr.w r0, [r4, #0xc6c]          @ word 0x200011e8
	.inst.n 0x1c40                  @ adds r0, r0, #1
	str.w r0, [r4, #0xc6c]
	cmp r0, #4
	ble.n .L080097ca
	str.w r8, [r4, #0xc6c]          @ above 4: back to 0
.L080097ca:
	pop.w {r4, r5, r6, r7, r8, r9, r10, lr}
	b.w fn_0800f854
.L080097d2:
	movs r1, #1
	b.n .L08009696
.L080097d6:
	bl fn_08023050
	strb.w r6, [r4, #0xc48]         @ byte 0x200011c4 = 1
.L080097de:
	pop.w {r4, r5, r6, r7, r8, r9, r10, pc}
.L080097e2:
	cmp r0, r1
	bne.n .L08009838
	ldr.w r1, [r4, #0xbd4]          @ word 0x20001150
	ldr r0, .L08009920              @ r0 = 0x2000057c
	.inst.n 0x1c49                  @ adds r1, r1, #1
	str.w r1, [r4, #0xbd4]
	ldr.w r2, [r0, #0xbe0]          @ r2 = word 0x2000115c
	ldr r0, .L08009924              @ r0 = 0x200001d4
	cmp r1, #2
	ldr r0, [r0, #0xc]              @ word 0x200001e0
	ble.n .L08009804
	str.w r8, [r4, #0xbd4]          @ above 2: back to 0
	b.n .L08009810
.L08009804:
	cbz r1, .L08009810
	cmp r1, #1
	beq.n .L0800981a
	cmp r1, #2
	beq.n .L08009824
	b.n .L0800982c
.L08009810:
	cbz r2, .L08009816
	ldr r1, .L08009950              @ r1 = 0x08040f10
	b.n .L08009828
.L08009816:
	ldr r1, .L08009954              @ r1 = 0x0803c690
	b.n .L08009828
.L0800981a:
	cbz r2, .L08009820
	ldr r1, .L08009958              @ r1 = 0x08041184
	b.n .L08009828
.L08009820:
	ldr r1, .L0800995c              @ r1 = 0x0803c91c
	b.n .L08009828
.L08009824:
	cbz r2, .L08009834
	ldr r1, .L08009960              @ r1 = 0x08040c9c
.L08009828:
	bl fn_08021c14
.L0800982c:
	pop.w {r4, r5, r6, r7, r8, r9, r10, lr}
	b.w fn_08009f10
.L08009834:
	ldr r1, .L08009964              @ r1 = 0x0803cba8
	b.n .L08009828
.L08009838:
	cmp r0, #0x80
	beq.n .L0800986e
	cmp.w r0, #0x2000
	beq.n .L08009874
	cmp.w r0, #0x800
	beq.n .L0800987c
	cmp.w r0, #0x100
	beq.n .L08009882
	ldr r1, .L08009920              @ r1 = 0x2000057c
	cmp r0, #0x10
	ldr.w r1, [r1, #0xc2c]          @ r1 = word 0x200011a8
	beq.n .L08009888
	cmp r0, #4
	beq.n .L08009890
	cmp r0, #2
	beq.n .L08009878
	cmp r0, #0x20
.L08009862:
	bne.n .L080097de
	mov.w r0, #-1
.L08009868:
	bl fn_0800d940
	b.n .L0800989a
.L0800986e:
	str.w r9, [r4, #0xc2c]          @ word 0x200011a8 = 3
	b.n .L08009878
.L08009874:
	str.w r8, [r4, #0xc2c]          @ word 0x200011a8 = 0
.L08009878:
	movs r0, #1
	b.n .L08009868
.L0800987c:
	str.w r6, [r4, #0xc2c]          @ word 0x200011a8 = 1
	b.n .L08009878
.L08009882:
	str.w r7, [r4, #0xc2c]          @ word 0x200011a8 = 2
	b.n .L08009878
.L08009888:
	cmp r1, #0
	ble.n .L0800989a
	.inst.n 0x1e49                  @ subs r1, r1, #1
	b.n .L08009896
.L08009890:
	cmp r1, #3
	bge.n .L0800989a
	.inst.n 0x1c49                  @ adds r1, r1, #1
.L08009896:
	str.w r1, [r4, #0xc2c]          @ word 0x200011a8 = r1
.L0800989a:
	pop.w {r4, r5, r6, r7, r8, r9, r10, lr}
	b.w fn_0800da6c
.L080098a2:
	cmp r3, #0
	bne.n .L080097de
	strh.w r6, [r4, #0xc14]         @ busy flag = 1
	movs r0, #0x32
	addw r4, r4, #0xbec             @ r4 = 0x20001168
	bl fn_08008120
	ldr r0, [r5, #4]                @ word 0x200001d8
	bl fn_08023690
	ldr r0, [r4, #0]                @ word 0x20001168
	str r0, [r4, #0x54]             @ word 0x200011bc
	pop.w {r4, r5, r6, r7, r8, r9, r10, lr}
	b.w fn_0800d6e4
.L080098c6:
	pop.w {r4, r5, r6, r7, r8, r9, r10, lr}
	b.w fn_0800d50c
.L080098ce:
	cmp r0, r1
	bne.n .L08009912
	cmp r3, #0
	bne.n .L080097de
	strh.w r6, [r4, #0xc14]         @ busy flag = 1
	movs r0, #0x32
	bl fn_08008120
	ldr.w r0, [r4, #0xbd8]          @ word 0x20001154
	.inst.n 0x1c40                  @ adds r0, r0, #1
	str.w r0, [r4, #0xbd8]
	cmp r0, #2
	ble.n .L080098f4
	str.w r8, [r4, #0xbd8]          @ above 2: back to 0
	b.n .L0800990a
.L080098f4:
	cbz r0, .L0800990a
	cmp r0, #1
	beq.n .L0800990e
	cmp r0, #2
	bne.n .L08009862
	ldr r1, .L08009968              @ r1 = 0x0803d224
.L08009900:
	ldr r0, [r5, #0x10]             @ word 0x200001e4
	pop.w {r4, r5, r6, r7, r8, r9, r10, lr}
	b.w fn_08021c14
.L0800990a:
	ldr r1, .L0800996c              @ r1 = 0x0803cdc4
	b.n .L08009900
.L0800990e:
	ldr r1, .L08009970              @ r1 = 0x0803cff4
	b.n .L08009900
.L08009912:
	cmp r0, #0x80
	bne.n .L08009862
	cmp r3, #0
	bne.n .L08009862
	strh.w r6, [r4, #0xc14]         @ busy flag = 1
	b.n .L080097de
.L08009920:
	.word 0x2000057c
.L08009924:
	.word 0x200001d4
.L08009928:
	.word d_0803dba4
.L0800992c:
	.asciz "%s"
	.byte 0x00                      @ padding
.L08009930:
	.word d_0803da44
.L08009934:
	.word d_0803d2fc
.L08009938:
	.word d_0803dd04
.L0800993c:
	.word d_0803d3d4
.L08009940:
	.word d_0803de64
.L08009944:
	.word d_0803d584
.L08009948:
	.word d_0803dfc4
.L0800994c:
	.word d_0803d8e4
.L08009950:
	.word d_08040f10
.L08009954:
.ifdef OWN
	.word d_08040f10                @ our build: the English icon for language 0 too
.else
	.word d_0803c690
.endif
.L08009958:
	.word d_08041184
.L0800995c:
.ifdef OWN
	.word d_08041184                @ our build: the English icon for language 0 too
.else
	.word d_0803c91c
.endif
.L08009960:
	.word d_08040c9c
.L08009964:
.ifdef OWN
	.word d_08040c9c                @ our build: the English icon for language 0 too
.else
	.word d_0803cba8
.endif
.L08009968:
	.word d_0803d224
.L0800996c:
	.word d_0803cdc4
.L08009970:
	.word d_0803cff4

@ ----------------------------------------------------------------------------
@ fn_08009974 - key handler for screen state 3.
@ No parameters, no return value.
@ r4 = 0x2000057c (literal), r5 = 0x2000000c (literal); event code = halfword
@ 0x20001192 (r4 + 0xc16), key mask = halfword 0x20001194 (r4 + 0xc18). Codes
@ other than 1 and 0xfe return.
@ Code 0xfe: returns unless the mask is 8 and halfword 0x20001190 is 0; then
@   stores 1 to that halfword and calls fn_08008120(0x32). When word
@   0x200011ac = 1 it goes to piece 0x08009aa2; otherwise it calls
@   fn_08023690(word 0x20000014) and tail-jumps to fn_0800d50c when word
@   0x200011bc = 2 (piece 0x08009abc / 0x08009ae6), else to fn_0800ca2c
@   (0x08009a7a).
@   Piece 0x08009aa2: byte 0x2000000c nonzero: clears it and tail-jumps to
@   fn_0800e6c8; zero: clears words 0x200011ac and 0x200011b0, r0 = word
@   0x20000018, calls fn_08023520(r0) and fn_0800f294(0, 0), r2 = word
@   0x2000002c + 4 * word 0x2000115c, r3 = 0x08009b08 when word 0x200011c0 = 2
@   else 0x08009afc, then joins the tail 0x08009a2a.
@ Code 1: r1 = word 0x200011ac, r0 = mask. Masks 0x10 and 4 tail-jump to
@   fn_0800f5e8(mask). Mask 2: r1 = 0 tail-jumps to fn_0800f294(0, -1), else to
@   fn_0800f5e8(2). Mask 0x20: r1 = 0 tail-jumps to fn_0800f294(0, 1), else to
@   fn_0800f5e8(0x20). Other masks return.
@   Mask 8 with word 0x200011a8 in r0: r1 = 0 and r0 in {0, 5, 6}: sets word
@   0x200011ac = 1, calls fn_0800f5e8(8), sets word 0x200011b0 = 1, r2 = word
@   [0x20000054 + 36 * word 0x2000115c + 4 * word 0x200011a8], r3 = 0x08009b08
@   when word 0x200011c0 = 2 else 0x08009afc, then the tail 0x08009a2a: r0 =
@   word 0x2000001c, r1 = 0x08009b00 (string "%s%s"), tail-jump to
@   fn_080228d0(r0, r1, r2, r3) (merged piece 0x08009a2a). r1 = 0 with any
@   other r0 returns.
@   r1 nonzero: r0 = 0 sets byte 0x2000000c = 1; r0 = 6 with byte 0x2000000c = 0
@   sets it to 1 and clears word 0x200011b4; r0 = 6 with the byte nonzero and
@   word 0x200011b4 = 1 calls fn_0800b4c8 (argument 0, or 1 when word
@   0x200011c0 = 2), fn_08009e60(word 0x20001158), fn_08023690(word
@   0x20000014) and tail-jumps to fn_0800ca2c; r0 = 6 with the byte nonzero and
@   word 0x200011b4 not 1 clears the byte. Every r1 nonzero case except the one
@   that tail-jumps to fn_0800ca2c, including r0 not 0 and not 6 (0x080099f2),
@   then clears word 0x200011b8 and tail-jumps to fn_0800f5e8(8) (0x08009a4e).
@ The instruction at 0x08009a88 (b 0x08009aa2) is entered by no instruction;
@ piece 0x08009ae6 pops and tail-jumps to fn_0800d50c.
@ String data: 0x08009afc = empty string, 0x08009b00 = "%s%s", 0x08009b08 =
@ "(" + the six bytes e5 8e 82 e5 ae b6 + ")" + NUL.
@ Literal words: 0x2000057c and 0x2000000c at 0x08009af4 / 0x08009af8.
@ ----------------------------------------------------------------------------
	.section .text.fn_08009974,"ax",%progbits
	.p2align 2
	.global fn_08009974
	.thumb_func
	.type fn_08009974, %function
fn_08009974:
	push.w {r4, r5, r6, r7, r8, lr}
	ldr r4, .L08009af4              @ r4 = 0x2000057c
	movs r7, #1
	mov r0, r4
	ldrh.w r1, [r4, #0xc16]         @ r1 = event code
	movs r6, #0
	ldrh.w r0, [r0, #0xc18]         @ r0 = key mask
	ldr r5, .L08009af8              @ r5 = 0x2000000c
	cmp r1, #1
	beq.n .L080099c0
	cmp r1, #0xfe
	bne.n .L08009a86
	cmp r0, #8
	bne.n .L08009a86
	ldrh.w r0, [r4, #0xc14]         @ busy flag 0x20001190
	cmp r0, #0
	bne.n .L08009a86
	strh.w r7, [r4, #0xc14]         @ busy flag = 1
	movs r0, #0x32
	bl fn_08008120
	ldr.w r0, [r4, #0xc30]          @ word 0x200011ac
	cmp r0, #1
	beq.n .L08009aa2
	ldr r0, [r5, #8]                @ word 0x20000014
	bl fn_08023690
	ldr.w r0, [r4, #0xc40]          @ word 0x200011bc
	cmp r0, #2
	beq.n .L08009abc
	b.n .L08009a7a
.L080099c0:
	ldr r1, .L08009af4              @ r1 = 0x2000057c
	cmp r0, #8
	ldr.w r1, [r1, #0xc30]          @ r1 = word 0x200011ac
	beq.n .L080099e4
	cmp r0, #0x10
	beq.n .L080099dc
	cmp r0, #4
	beq.n .L080099dc
	cmp r0, #2
	beq.n .L08009a8a
	cmp r0, #0x20
	bne.n .L08009a86
	cbz r1, .L08009a3a
.L080099dc:
	pop.w {r4, r5, r6, r7, r8, lr}
	b.w fn_0800f5e8
.L080099e4:
	ldr r0, .L08009af4              @ r0 = 0x2000057c
	ldr.w r0, [r0, #0xc2c]          @ r0 = word 0x200011a8
	cbz r1, .L080099f4
	cbz r0, .L08009a3c
	cmp r0, #6
	beq.n .L08009a40
	b.n .L08009a4e
.L080099f4:
	cbz r0, .L080099fe
	cmp r0, #5
	beq.n .L080099fe
	cmp r0, #6
	bne.n .L08009aee
.L080099fe:
	str.w r7, [r4, #0xc30]          @ word 0x200011ac = 1
	movs r0, #8
	add.w r4, r4, #0xbe0            @ r4 = 0x2000115c
	bl fn_0800f5e8
	str r7, [r4, #0x54]             @ word 0x200011b0 = 1
	ldr r0, [r4, #0]                @ word 0x2000115c
	ldr r1, .L08009af8              @ r1 = 0x2000000c
	add.w r0, r0, r0, lsl #3
	adds r1, #0x48                  @ r1 = 0x20000054
	add.w r0, r1, r0, lsl #2
	ldr r1, [r4, #0x4c]             @ word 0x200011a8
	ldr.w r2, [r0, r1, lsl #2]
	ldr r0, [r4, #0x64]             @ word 0x200011c0
	cmp r0, #2
	beq.n .L08009a36
	adr r3, .L08009afc              @ r3 = empty string
.L08009a2a:
	ldr r0, [r5, #0x10]             @ word 0x2000001c
	pop.w {r4, r5, r6, r7, r8, lr}
	adr r1, .L08009b00              @ r1 = "%s%s"
	b.w fn_080228d0
.L08009a36:
	adr r3, .L08009b08
	b.n .L08009a2a
.L08009a3a:
	b.n .L08009a96
.L08009a3c:
	strb r7, [r5, #0]               @ byte 0x2000000c = 1
	b.n .L08009a4e
.L08009a40:
	ldrb r0, [r5, #0]
	cbz r0, .L08009a56
	ldr.w r0, [r4, #0xc38]          @ word 0x200011b4
	cmp r0, #1
	beq.n .L08009a5e
	strb r6, [r5, #0]               @ byte 0x2000000c = 0
.L08009a4e:
	movs r0, #8
	str.w r6, [r4, #0xc3c]          @ word 0x200011b8 = 0
	b.n .L080099dc
.L08009a56:
	strb r7, [r5, #0]               @ byte 0x2000000c = 1
	str.w r6, [r4, #0xc38]          @ word 0x200011b4 = 0
	b.n .L08009a4e
.L08009a5e:
	ldr.w r0, [r4, #0xc44]          @ word 0x200011c0
	cmp r0, #2
.ifdef OWN
	nop.n                           @ 0x08009A64: restore with mode 0 also in factory mode (S1.9)
.else
	beq.n .L08009a82
.endif
	movs r0, #0
.L08009a68:
.ifdef OWN
	bl own_restore_guard            @ 0x08009A68: not while injected (own/ctl.s)
.else
	bl fn_0800b4c8
.endif
	ldr.w r0, [r4, #0xbdc]          @ word 0x20001158
	bl fn_08009e60
	ldr r0, [r5, #8]                @ word 0x20000014
	bl fn_08023690
.L08009a7a:
	pop.w {r4, r5, r6, r7, r8, lr}
	b.w fn_0800ca2c
.L08009a82:
	movs r0, #1
	b.n .L08009a68
.L08009a86:
	b.n .L08009aee
	b.n .L08009aa2                  @ entered by no instruction
.L08009a8a:
	cbz r1, .L08009a90
	movs r0, #2
	b.n .L080099dc
.L08009a90:
	mov.w r1, #-1
	b.n .L08009a98
.L08009a96:
	movs r1, #1
.L08009a98:
	pop.w {r4, r5, r6, r7, r8, lr}
	movs r0, #0
	b.w fn_0800f294                 @ (0, r1)
.L08009aa2:
	ldrb r0, [r5, #0]               @ byte 0x2000000c
	cbz r0, .L08009ab0
	strb r6, [r5, #0]               @ byte 0x2000000c = 0
	pop.w {r4, r5, r6, r7, r8, lr}
	b.w fn_0800e6c8
.L08009ab0:
	str.w r6, [r4, #0xc30]          @ word 0x200011ac = 0
	str.w r6, [r4, #0xc34]          @ word 0x200011b0 = 0
	ldr r0, [r5, #0xc]              @ word 0x20000018
	b.n .L08009abe
.L08009abc:
	b.n .L08009ae6
.L08009abe:
	bl fn_08023520
	movs r1, #0
	mov r0, r1
	bl fn_0800f294                  @ (0, 0)
	ldr.w r0, [r4, #0xc44]          @ word 0x200011c0
	cmp r0, #2
	beq.n .L08009ae2
	adr r3, .L08009afc              @ r3 = empty string
.L08009ad4:
	ldr r1, .L08009af8              @ r1 = 0x2000000c
	ldr.w r0, [r4, #0xbe0]          @ word 0x2000115c
	adds r1, #0x20                  @ r1 = 0x2000002c
	ldr.w r2, [r1, r0, lsl #2]
	b.n .L08009a2a
.L08009ae2:
	adr r3, .L08009b08
	b.n .L08009ad4
.L08009ae6:
	pop.w {r4, r5, r6, r7, r8, lr}
	b.w fn_0800d50c
.L08009aee:
	pop.w {r4, r5, r6, r7, r8, pc}
	.short 0x0000                   @ padding
.L08009af4:
	.word 0x2000057c
.L08009af8:
	.word 0x2000000c
.L08009afc:
	.byte 0x00, 0x00, 0x00, 0x00    @ empty string
.L08009b00:
	.asciz "%s%s"
	.byte 0x00, 0x00, 0x00          @ padding
.L08009b08:
.ifdef OWN
	.asciz "(FACT)"                     @ our build: factory-mode suffix in English (font
	.byte 0x00, 0x00, 0x00, 0x00, 0x00  @ 0x0802f0d8 holds ( ) A C F T), same 12 bytes
.else
	.asciz "(\345\216\202\345\256\266)"
	.byte 0x00, 0x00, 0x00          @ padding
.endif

@ ----------------------------------------------------------------------------
@ fn_0800af58 - drives three output bits from a pattern number.
@ No parameters.
@ Selects by byte 0x200011c6 (0..6, other values act as 7) a 3-bit pattern and
@ calls fn_08008350 with base 0x40010800, masks 2, 4 and 8 and values 0 or 1:
@ 0 = 000, 1 = 001, 2 = 010, 3 = 011, 4 = 100, 5 = 101, 6 = 110, otherwise
@ 111 (bit 2 goes to mask 2, bit 1 to mask 4, bit 0 to mask 8). The last call
@ (mask 8) is a tail call.
@ r0 = 0x2000057c and r4 = 0x40010800 come from the literal pool at the end;
@ the byte is at offset 0xc4a from 0x2000057c.
@ ----------------------------------------------------------------------------
	.section .text.fn_0800af58,"ax",%progbits
	.p2align 2
	.global fn_0800af58
	.thumb_func
	.type fn_0800af58, %function
fn_0800af58:
	ldr r0, .L0800aff8              @ r0 = 0x2000057c
	push {r4, lr}
	ldrb.w r1, [r0, #0xc4a]         @ r1 = pattern byte 0x200011c6
	ldr r4, .L0800affc              @ r4 = 0x40010800
	cbz r1, .L0800af9a
	ldrb.w r1, [r0, #0xc4a]
	cmp r1, #1
	beq.n .L0800af9e
	ldrb.w r1, [r0, #0xc4a]
	cmp r1, #2
	beq.n .L0800afa2
	ldrb.w r1, [r0, #0xc4a]
	cmp r1, #3
	beq.n .L0800afba
	ldrb.w r1, [r0, #0xc4a]
	cmp r1, #4
	beq.n .L0800afdc
	ldrb.w r1, [r0, #0xc4a]
	cmp r1, #5
	beq.n .L0800afea
	ldrb.w r0, [r0, #0xc4a]
	mov.w r2, #1
	cmp r0, #6
	beq.n .L0800afa4
	b.n .L0800afbc
.L0800af9a:
	movs r2, #0
	b.n .L0800afde
.L0800af9e:
	movs r2, #0
	b.n .L0800afec
.L0800afa2:
	movs r2, #0
.L0800afa4:
	movs r1, #2
	mov r0, r4
	bl fn_08008350                  @ (0x40010800, 2, r2)
	movs r2, #1
.L0800afae:
	movs r1, #4
	mov r0, r4
	bl fn_08008350                  @ (0x40010800, 4, r2)
	movs r2, #0
	b.n .L0800afd0
.L0800afba:
	movs r2, #0
.L0800afbc:
	movs r1, #2
	mov r0, r4
	bl fn_08008350                  @ (0x40010800, 2, r2)
	movs r2, #1
.L0800afc6:
	movs r1, #4
	mov r0, r4
	bl fn_08008350                  @ (0x40010800, 4, r2)
	movs r2, #1
.L0800afd0:
	mov r0, r4
	pop.w {r4, lr}
	movs r1, #8
	b.w fn_08008350                 @ tail call (0x40010800, 8, r2)
.L0800afdc:
	movs r2, #1
.L0800afde:
	movs r1, #2
	mov r0, r4
	bl fn_08008350                  @ (0x40010800, 2, r2)
	movs r2, #0
	b.n .L0800afae
.L0800afea:
	movs r2, #1
.L0800afec:
	movs r1, #2
	mov r0, r4
	bl fn_08008350                  @ (0x40010800, 2, r2)
	movs r2, #0
	b.n .L0800afc6
.L0800aff8:
	.word 0x2000057c
.L0800affc:
	.word 0x40010800

