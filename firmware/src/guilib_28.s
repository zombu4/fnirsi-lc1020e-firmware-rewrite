@ guilib_28.s - gui library functions 0x08011e1c..0x08013594 (list headers, text width, formatted output helpers)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08011e1c - initialises the header at 0x20008080 and a handler slot.
@ No parameters, no return value.
@ Calls init_header_aligned4(0x20008080, 0x44), then stores the result of
@ fn_080277c8(fn_08013648, 0x1e, 0) in the word 0x200004c4, calls fn_08013594
@ and stores the byte 0 at 0x200004bc.
@ The literal pool at the end holds 0x20008080, the function pointer
@ fn_08013648 and 0x200004bc (r4 = 0x200004bc, the word is at r4 + 8).
@ ----------------------------------------------------------------------------
	.section .text.fn_08011e1c,"ax",%progbits
	.p2align 2
	.global fn_08011e1c
	.thumb_func
	.type fn_08011e1c, %function
fn_08011e1c:
	push {r4, lr}
	movs r1, #0x44
	ldr r0, .L08011e40              @ r0 = 0x20008080
	bl init_header_aligned4         @ (0x20008080, 0x44)
	movs r2, #0
	movs r1, #0x1e
	ldr r0, .L08011e44              @ r0 = fn_08013648
	bl fn_080277c8                  @ (fn_08013648, 0x1e, 0)
	ldr r4, .L08011e48              @ r4 = 0x200004bc
	str r0, [r4, #8]                @ 0x200004c4 = result
	bl fn_08013594
	movs r0, #0
	strb r0, [r4, #0]               @ 0x200004bc = 0
	pop {r4, pc}
	.short 0x0000                   @ padding
.L08011e40:
	.word 0x20008080
.L08011e44:
	.word fn_08013648
.L08011e48:
	.word 0x200004bc

@ ----------------------------------------------------------------------------
@ fn_080125a2 - frees every node of a list.
@ Parameter: r0 = list header.
@ it = get_word_4_or_zero(list) (r0 as passed); while it is nonzero:
@ next = read_word_at_base_plus_offset_4(list, it), fn_080126a2(list, it)
@ (unlinks the node), fn_08022c68(it) (frees the node), it = next.
@ No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080125a2,"ax",%progbits
	.global fn_080125a2
	.thumb_func
	.type fn_080125a2, %function
fn_080125a2:
	push {r4, r5, r6, lr}
	mov r5, r0                      @ r5 = list
	bl get_word_4_or_zero
	mov r4, r0                      @ r4 = first node
	b.n .L080125c8
.L080125ae:
	mov r1, r4
	mov r0, r5
	bl read_word_at_base_plus_offset_4
	mov r6, r0                      @ r6 = next node
	mov r1, r4
	mov r0, r5
	bl fn_080126a2                  @ (list, node)
	mov r0, r4
	bl fn_08022c68                  @ (node)
	mov r4, r6
.L080125c8:
	cmp r4, #0
	bne.n .L080125ae
	pop {r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ get_word_4_or_zero - returns the word at pointer + 4, or 0 for a null pointer.
@ Parameter: r0 = pointer.
@ Returns 0 when r0 is 0, otherwise the word at r0 + 4.
@ ----------------------------------------------------------------------------
	.section .text.get_word_4_or_zero,"ax",%progbits
	.global get_word_4_or_zero
	.thumb_func
	.type get_word_4_or_zero, %function
get_word_4_or_zero:
	cmp r0, #0
	beq.n .L080125d4
	ldr r0, [r0, #4]
.L080125d4:
	bx lr

@ ----------------------------------------------------------------------------
@ fn_080125d6 - counts the nodes of a list.
@ Parameter: r0 = list header.
@ Starts with get_word_4_or_zero(list); for every node it adds 1 to a counter
@ (starting at 0, kept in r2) and fetches the next node with
@ read_word_at_base_plus_offset_4(list, node). Returns the counter.
@ ----------------------------------------------------------------------------
	.section .text.fn_080125d6,"ax",%progbits
	.global fn_080125d6
	.thumb_func
	.type fn_080125d6, %function
fn_080125d6:
	push {lr}
	mov r3, r0                      @ r3 = list
	movs r2, #0                     @ r2 = counter
	bl get_word_4_or_zero
	b.n .L080125ea
.L080125e2:
	mov r0, r3
	.inst.n 0x1c52                  @ adds r2, r2, #1
	bl read_word_at_base_plus_offset_4
.L080125ea:
	movs r1, r0                     @ r1 = node, sets the flags
	bne.n .L080125e2
	mov r0, r2
	pop {pc}

@ ----------------------------------------------------------------------------
@ read_word_at_base_plus_offset_4 - reads a word from a table pointed to by a pointer.
@ Parameters: r0 = pointer to the base, r1 = offset.
@ Returns the word at *r0 + r1 + 4.
@ ----------------------------------------------------------------------------
	.section .text.read_word_at_base_plus_offset_4,"ax",%progbits
	.global read_word_at_base_plus_offset_4
	.thumb_func
	.type read_word_at_base_plus_offset_4, %function
read_word_at_base_plus_offset_4:
	ldr r0, [r0, #0]
	.inst.n 0x1d09                  @ adds r1, r1, #4
	ldr r0, [r0, r1]
	bx lr

@ ----------------------------------------------------------------------------
@ read_word_at_base_plus_offset - reads a word from a table pointed to by a pointer.
@ Parameters: r0 = pointer to the base, r1 = offset.
@ Returns the word at *r0 + r1.
@ ----------------------------------------------------------------------------
	.section .text.read_word_at_base_plus_offset,"ax",%progbits
	.global read_word_at_base_plus_offset
	.thumb_func
	.type read_word_at_base_plus_offset, %function
read_word_at_base_plus_offset:
	ldr r0, [r0, #0]
	ldr r0, [r0, r1]
	bx lr

@ ----------------------------------------------------------------------------
@ get_word_8_or_zero - returns the word at pointer + 8, or 0 for a null pointer.
@ Parameter: r0 = pointer.
@ Returns 0 when r0 is 0, otherwise the word at r0 + 8.
@ ----------------------------------------------------------------------------
	.section .text.get_word_8_or_zero,"ax",%progbits
	.p2align 2
	.global get_word_8_or_zero
	.thumb_func
	.type get_word_8_or_zero, %function
get_word_8_or_zero:
	cmp r0, #0
	beq.n .L08012606
	ldr r0, [r0, #8]
.L08012606:
	bx lr

@ ----------------------------------------------------------------------------
@ init_header_aligned4 - initialises a list header.
@ Parameters: r0 = header, r1 = element size.
@ header[1] = 0; header[2] = 0; header[0] = (size + 3) & 0xfffffffc.
@ ----------------------------------------------------------------------------
	.section .text.init_header_aligned4,"ax",%progbits
	.p2align 2
	.global init_header_aligned4
	.thumb_func
	.type init_header_aligned4, %function
init_header_aligned4:
	movs r2, #0
	str r2, [r0, #4]
	.inst.n 0x1cc9                  @ adds r1, r1, #3
	bic.w r1, r1, #3
	str r2, [r0, #8]
	str r1, [r0, #0]
	bx lr

@ ----------------------------------------------------------------------------
@ fn_08012618 - allocates a node and links it at the head of the list.
@ Parameter: r0 = list header (r4).
@ node = fn_08022b50(header[0] + 8); returns 0 when that is 0. Otherwise:
@   store_word_if_offset_nonzero(header, node, 0);
@   store_word_plus4_if_offset_nonzero(header, node, header[1]);
@   when header[1] is nonzero: store_word_if_offset_nonzero(header, header[1], node);
@   header[1] = node; header[2] = node when header[2] is 0.
@ Returns node.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012618,"ax",%progbits
	.p2align 2
	.global fn_08012618
	.thumb_func
	.type fn_08012618, %function
fn_08012618:
	push {r4, r5, r6, lr}
	mov r4, r0                      @ r4 = header
	ldr r0, [r0, #0]
	adds r0, #8
	bl fn_08022b50                  @ allocate header[0] + 8 bytes
	movs r5, r0                     @ r5 = node
	beq.n .L08012650
	mov r1, r0
	movs r2, #0
	mov r0, r4
	bl store_word_if_offset_nonzero
	mov r1, r5
	mov r0, r4
	ldr r2, [r4, #4]
	bl store_word_plus4_if_offset_nonzero
	ldr r1, [r4, #4]
	cbz r1, .L08012648
	mov r2, r5
	mov r0, r4
	bl store_word_if_offset_nonzero
.L08012648:
	str r5, [r4, #4]
	ldr r0, [r4, #8]
	cbnz r0, .L08012650
	str r5, [r4, #8]
.L08012650:
	mov r0, r5
	pop {r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08012654 - allocates a node and links it at the tail of the list.
@ Parameter: r0 = list header (r4).
@ node = fn_08022b50(header[0] + 8); returns 0 when that is 0. Otherwise:
@   store_word_plus4_if_offset_nonzero(header, node, 0);
@   store_word_if_offset_nonzero(header, node, header[2]);
@   when header[2] is nonzero: store_word_plus4_if_offset_nonzero(header, header[2], node);
@   header[2] = node; header[1] = node when header[1] is 0.
@ Returns node.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012654,"ax",%progbits
	.p2align 2
	.global fn_08012654
	.thumb_func
	.type fn_08012654, %function
fn_08012654:
	push {r4, r5, r6, lr}
	mov r4, r0                      @ r4 = header
	ldr r0, [r0, #0]
	adds r0, #8
	bl fn_08022b50                  @ allocate header[0] + 8 bytes
	movs r5, r0                     @ r5 = node
	beq.n .L0801268c
	mov r1, r0
	movs r2, #0
	mov r0, r4
	bl store_word_plus4_if_offset_nonzero
	mov r1, r5
	mov r0, r4
	ldr r2, [r4, #8]
	bl store_word_if_offset_nonzero
	ldr r1, [r4, #8]
	cbz r1, .L08012684
	mov r2, r5
	mov r0, r4
	bl store_word_plus4_if_offset_nonzero
.L08012684:
	str r5, [r4, #8]
	ldr r0, [r4, #4]
	cbnz r0, .L0801268c
	str r5, [r4, #4]
.L0801268c:
	mov r0, r5
	pop {r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ fn_08012690 - tests whether a list is empty.
@ Parameter: r0 = list header.
@ Returns 1 when r0 is 0 or both header words [1] and [2] are 0, otherwise 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012690,"ax",%progbits
	.global fn_08012690
	.thumb_func
	.type fn_08012690, %function
fn_08012690:
	cbz r0, .L0801269e
	ldr r1, [r0, #4]
	cbnz r1, .L0801269a
	ldr r0, [r0, #8]
	cbz r0, .L0801269e
.L0801269a:
	movs r0, #0
	bx lr
.L0801269e:
	movs r0, #1
	bx lr

@ ----------------------------------------------------------------------------
@ fn_080126a2 - unlinks a node from a list.
@ Parameters: r0 = list header (r4), r1 = node.
@ Returns at once when r0 is 0. Uses get_word_4_or_zero, get_word_8_or_zero and
@ read_word_at_base_plus_offset_4 on the links at *header + offset:
@   node is the first node (get_word_4_or_zero(header) == node): header[1] =
@   next node; when that is 0, header[2] = 0 and return; otherwise
@   store_word_if_offset_nonzero(header, next, 0).
@   node is the last node (get_word_8_or_zero(header) == node): header[2] = the
@   previous link; when that is 0, header[1] = 0 and return; otherwise
@   store_word_plus4_if_offset_nonzero(header, previous, 0) (tail call).
@   otherwise the neighbours are patched with store_word_plus4_if_offset_nonzero
@   and store_word_if_offset_nonzero (tail call).
@ No return value.
@ ----------------------------------------------------------------------------
	.section .text.fn_080126a2,"ax",%progbits
	.global fn_080126a2
	.thumb_func
	.type fn_080126a2, %function
fn_080126a2:
	push {r4, r5, r6, lr}
	movs r4, r0                     @ r4 = header
	beq.n .L080126c4
	bl get_word_4_or_zero
	movs r2, #0
	cmp r0, r1
	mov r0, r4
	bne.n .L080126c6
	bl read_word_at_base_plus_offset_4
	str r0, [r4, #4]                @ header[1] = next node
	subs r1, r0, #0
	beq.n .L080126c2
	movs r2, #0
	b.n .L08012700
.L080126c2:
	str r2, [r4, #8]                @ header[2] = 0
.L080126c4:
	pop {r4, r5, r6, pc}
.L080126c6:
	bl get_word_8_or_zero
	cmp r0, r1
	ldr r0, [r4, #0]
	add r0, r1
	bne.n .L080126e8
	ldr r1, [r0, #0]
	str r1, [r4, #8]                @ header[2] = previous link
	cbz r1, .L080126e4
	mov r0, r4
	pop.w {r4, r5, r6, lr}
	movs r2, #0
	b.w store_word_plus4_if_offset_nonzero
.L080126e4:
	str r2, [r4, #4]                @ header[1] = 0
	pop {r4, r5, r6, pc}
.L080126e8:
	ldr r5, [r0, #0]
	mov r0, r4
	bl read_word_at_base_plus_offset_4
	mov r6, r0
	mov r2, r0
	mov r1, r5
	mov r0, r4
	bl store_word_plus4_if_offset_nonzero
	mov r2, r5
	mov r1, r6
.L08012700:
	mov r0, r4
	pop.w {r4, r5, r6, lr}
	b.w store_word_if_offset_nonzero

@ ----------------------------------------------------------------------------
@ init_header_200080a4 - initialises the header at 0x200080a4.
@ No parameters, no return value.
@ Tail call init_header_aligned4(0x200080a4, 0x14).
@ ----------------------------------------------------------------------------
	.section .text.init_header_200080a4,"ax",%progbits
	.p2align 2
	.global init_header_200080a4
	.thumb_func
	.type init_header_200080a4, %function
init_header_200080a4:
	movs r1, #0x14
	ldr r0, .L08012900              @ r0 = 0x200080a4
	b.w init_header_aligned4
.L08012900:
	.word 0x200080a4

@ ----------------------------------------------------------------------------
@ field_1ff_shr4_max7 - extracts a 3-bit style field limited to 7.
@ Parameter: r0 = value.
@ Returns bits 4..8 of r0 ((r0 & 0x1ff) >> 4), limited to 7.
@ ----------------------------------------------------------------------------
	.section .text.field_1ff_shr4_max7,"ax",%progbits
	.global field_1ff_shr4_max7
	.thumb_func
	.type field_1ff_shr4_max7, %function
field_1ff_shr4_max7:
	ubfx r0, r0, #4, #5
	cmp r0, #7
	bls.n .L08012b0c
	movs r0, #7
.L08012b0c:
	bx lr
	.short 0x0000                   @ padding

@ ----------------------------------------------------------------------------
@ fn_08012b10 - returns a byte from one of two tables by index.
@ Parameter: r0 = index.
@ Index 0xffff returns 0x1f; index 0 returns 0.
@ Index below 0x70: returns the byte at 0x08050c98 + index (d_08050c98).
@ Otherwise index - 0x70 (16 bit): returns 0 when the pointer at 0x200004e8 is 0
@ or the index is not below the word 0x20000500, else the byte at
@ *0x200004e8 + index.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012b10,"ax",%progbits
	.p2align 2
	.global fn_08012b10
	.thumb_func
	.type fn_08012b10, %function
fn_08012b10:
	sub.w r1, r0, #0xff00
	subs r1, #0xff                  @ zero when the index is 0xffff
	beq.n .L08012b24
	cmp r0, #0
	beq.n .L08012b26
	cmp r0, #0x70
	bhs.n .L08012b28
	ldr r1, .L08012b44              @ r1 = d_08050c98
	b.n .L08012b3a
.L08012b24:
	movs r0, #0x1f
.L08012b26:
	bx lr
.L08012b28:
	ldr r1, .L08012b48              @ r1 = 0x200004e8
	subs r0, #0x70
	uxth r0, r0
	ldr r1, [r1, #0]                @ r1 = pointer in 0x200004e8
	cbz r1, .L08012b3e
	ldr r2, .L08012b4c              @ r2 = 0x200004fc
	ldr r2, [r2, #4]                @ word at 0x20000500
	cmp r0, r2
	bhs.n .L08012b3e
.L08012b3a:
	ldrb r0, [r1, r0]
	bx lr
.L08012b3e:
	movs r0, #0
	bx lr
	.short 0x0000                   @ padding
.L08012b44:
	.word d_08050c98
.L08012b48:
	.word 0x200004e8
.L08012b4c:
	.word 0x200004fc

@ ----------------------------------------------------------------------------
@ fn_08012b50 - initialises the header at 0x20008050.
@ No parameters, no return value.
@ Calls init_header_aligned4(0x20008050, 0x18) and stores the byte 1 at
@ 0x20000484.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012b50,"ax",%progbits
	.p2align 2
	.global fn_08012b50
	.thumb_func
	.type fn_08012b50, %function
fn_08012b50:
	push {r4, lr}
	movs r1, #0x18
	ldr r0, .L08012b64              @ r0 = 0x20008050
	bl init_header_aligned4
	ldr r1, .L08012b68              @ r1 = 0x20000484
	movs r0, #1
	strb r0, [r1, #0]
	pop {r4, pc}
	.short 0x0000                   @ padding
.L08012b64:
	.word 0x20008050
.L08012b68:
	.word 0x20000484

@ ----------------------------------------------------------------------------
@ fn_08012b6c - calls the function pointer at 0x20000508 twice.
@ Parameters: r0 = source (r7), r1 = result pointer (r6), r2 = second result
@ pointer (r8), r3 = length pointer (r4).
@ r = (*word 0x20000508)(r0, r3); *r1 = r; when r is nonzero *r2 =
@ (*word 0x20000508)(*r3 + r0, 0), otherwise *r2 = 0.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012b6c,"ax",%progbits
	.p2align 2
	.global fn_08012b6c
	.thumb_func
	.type fn_08012b6c, %function
fn_08012b6c:
	push.w {r4, r5, r6, r7, r8, lr}
	ldr r5, .L08012b98              @ r5 = 0x20000504
	mov r8, r2
	mov r6, r1
	ldr r2, [r5, #4]                @ function pointer at 0x20000508
	mov r4, r3
	mov r7, r0
	mov r1, r3
	blx r2
	str r0, [r6, #0]
	cbz r0, .L08012b8e
	ldr r0, [r4, #0]
	ldr r2, [r5, #4]
	add r0, r7
	movs r1, #0
	blx r2
.L08012b8e:
	str.w r0, [r8, #0]
	pop.w {r4, r5, r6, r7, r8, pc}
	.short 0x0000                   @ padding
.L08012b98:
	.word 0x20000504

@ ----------------------------------------------------------------------------
@ fn_08012b9c - measures how many characters of a text fit and their width.
@ Parameters: r0 = text (r4), r1 = r10, r2 = r11, r3 = maximum width (r7),
@ stack: output short pointer (r5), flags (r8).
@ Returns the number of characters consumed (r0).
@ Clears *output when given; returns 0 for a null or empty text or r1 = 0.
@ Flags & 6 nonzero: scans from index 0 to the first 0x0a, 0x0d or 0, returns
@ index + 1 when it stopped at 0x0a or 0x0d and the index when it stopped at 0,
@ and stores -1 in *output when given.
@ The instruction at 0x08012bfc (width limit 0x1fff when flags bit 1 is set, test
@ at 0x08012bf6) is never executed because every path with flags & 6 nonzero
@ returns at 0x08012bc8-0x08012bf4 before it.
@ Loop: calls fn_08027bfc(text + offset, r1, r2, width, flags, &w, &tmp,
@ offset == 0), adds w to the total, reduces the width by w, stops when it
@ returns 0, on a 0x0a or 0x0d in the first byte, or after a 0x0a or 0x0d, or
@ when the byte at the new offset is 0 or the remaining width is not above 0.
@ When nothing was consumed it uses (*word 0x20000508)(text, &n) and
@ fn_08020a0a(r1, result, 0) for the width.
@ Stores the total width in *output.
@ Locals: [sp+0x10] = offset, [sp+0x14] = tmp byte, [sp+0x18] = w.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012b9c,"ax",%progbits
	.p2align 2
	.global fn_08012b9c
	.thumb_func
	.type fn_08012b9c, %function
fn_08012b9c:
	push.w {r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0x1c
	mov r10, r1
	ldrd r5, r8, [sp, #0x40]        @ r5 = output pointer, r8 = flags
	mov r7, r3
	mov r11, r2
	mov r4, r0
	movs r1, #0
	cbz r5, .L08012bb4
	strh r1, [r5, #0]               @ *output = 0
.L08012bb4:
	cbz r4, .L08012bce
	ldrb r0, [r4, #0]
	cmp r0, #0
	beq.n .L08012bd0
	cmp.w r10, #0
	beq.n .L08012bce
	movs r6, #0                     @ r6 = total width
	tst.w r8, #6
	beq.n .L08012bf6
	movs r0, #0
	b.n .L08012bd8
.L08012bce:
	movs r0, #0
.L08012bd0:
	add sp, #0x1c
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08012bd6:
	.inst.n 0x1c40                  @ adds r0, r0, #1
.L08012bd8:
	ldrb r1, [r4, r0]
	cmp r1, #0xa
	beq.n .L08012be8
	cmp r1, #0xd
	beq.n .L08012be8
	cmp r1, #0
	bne.n .L08012bd6
	b.n .L08012bea
.L08012be8:
	.inst.n 0x1c40                  @ adds r0, r0, #1
.L08012bea:
	cmp r5, #0
	beq.n .L08012bd0
	mov.w r1, #0xffffffff
	strh r1, [r5, #0]               @ *output = -1
	b.n .L08012bd0
.L08012bf6:
	lsls.w r0, r8, #30
	bpl.n .L08012c00
	movw r7, #0x1fff                @ never executed (see above)
.L08012c00:
	mov r9, r1
	mov r0, r1
	strb.w r1, [sp, #0x14]
	str r1, [sp, #0x10]             @ offset = 0
	b.n .L08012c5c
.L08012c0c:
	ldr r0, [sp, #0x10]
	str.w r9, [sp, #0x18]           @ w = 0
	cbz r0, .L08012c70
	mov.w r12, #0
.L08012c18:
	add r2, sp, #0x14
	add r3, sp, #0x18
	str.w r12, [sp, #0xc]           @ 8th argument: offset == 0 flag
	str.w r8, [sp, #0]              @ 5th argument: flags
	strd r3, r2, [sp, #4]           @ 6th argument &w, 7th argument &tmp
	add r0, r4
	mov r3, r7
	mov r2, r11
	mov r1, r10
	bl fn_08027bfc
	ldr r1, [sp, #0x18]
	subs r2, r7, r1
	add r1, r6
	sxth r7, r2                     @ remaining width -= w
	sxth r6, r1                     @ total width += w
	cbz r0, .L08012c64
	ldr r1, [sp, #0x10]
	add r1, r0
	str r1, [sp, #0x10]             @ offset += consumed
	ldrb r0, [r4, #0]
	cmp r0, #0xa
	beq.n .L08012c64
	cmp r0, #0xd
	beq.n .L08012c64
	ldrb r0, [r4, r1]
	cmp r0, #0xa
	beq.n .L08012c76
	cmp r0, #0xd
	beq.n .L08012c76
	mov r0, r1
.L08012c5c:
	ldrb r0, [r4, r0]
	cbz r0, .L08012c64
	cmp r7, #0
	bgt.n .L08012c0c
.L08012c64:
	ldr r0, [sp, #0x10]
	cbz r0, .L08012c7c
	cbz r5, .L08012c6c
.L08012c6a:
	strh r6, [r5, #0]               @ *output = total width
.L08012c6c:
	ldr r0, [sp, #0x10]
	b.n .L08012bd0
.L08012c70:
	mov.w r12, #1
	b.n .L08012c18
.L08012c76:
	adds r0, r1, #1
	str r0, [sp, #0x10]
	b.n .L08012c64
.L08012c7c:
	ldr r2, .L08012c98              @ r2 = 0x20000504
	add r1, sp, #0x10
	mov r0, r4
	ldr r2, [r2, #4]                @ function pointer at 0x20000508
	blx r2                          @ (text, &offset)
	cmp r5, #0
	beq.n .L08012c6c
	mov r1, r0
	movs r2, #0
	mov r0, r10
	bl fn_08020a0a
	sxth r6, r0
	b.n .L08012c6a
.L08012c98:
	.word 0x20000504

@ ----------------------------------------------------------------------------
@ fn_08012c9c - small state machine on a state byte.
@ Parameters: r0 = pointer to the state byte, r1 = character code.
@ r1 = 0x23: state 0 becomes 1 and returns 1; state 1 becomes 0 and returns 0;
@ state 2 becomes 0 and returns 1; other states return 0.
@ r1 not 0x23: a state other than 1 returns 0; state 1 returns 1 and for
@ r1 = 0x20 stores state 2.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012c9c,"ax",%progbits
	.global fn_08012c9c
	.thumb_func
	.type fn_08012c9c, %function
fn_08012c9c:
	movs r3, #0
	ldrb r2, [r0, #0]
	cmp r1, #0x23
	beq.n .L08012caa
	cmp r2, #1
	beq.n .L08012cc4
	b.n .L08012cca
.L08012caa:
	cbz r2, .L08012cb8
	movs r1, #0
	cmp r2, #1
	beq.n .L08012cbc
	cmp r2, #2
	beq.n .L08012cc0
	b.n .L08012cca
.L08012cb8:
	movs r1, #1
	b.n .L08012cc0
.L08012cbc:
	strb r1, [r0, #0]
	b.n .L08012cca
.L08012cc0:
	strb r1, [r0, #0]
	b.n .L08012cc8
.L08012cc4:
	cmp r1, #0x20
	beq.n .L08012cce
.L08012cc8:
	movs r3, #1
.L08012cca:
	mov r0, r3
	bx lr
.L08012cce:
	movs r1, #2
	b.n .L08012cc0

@ ----------------------------------------------------------------------------
@ fn_08012cd2 - formats into a newly allocated buffer.
@ Parameters: r0 = format (r8), r1 = argument list (r6).
@ n = fn_08010398(0, 0, format, args); buf = fn_08022b50(n + 1); returns 0 when
@ buf is 0. Stores 0 at buf + n and fills the buffer with
@ fn_08010398(buf, n + 1, format, args). Returns buf.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012cd2,"ax",%progbits
	.global fn_08012cd2
	.thumb_func
	.type fn_08012cd2, %function
fn_08012cd2:
	push.w {r4, r5, r6, r7, r8, lr}
	mov r6, r1
	mov r8, r0
	mov r2, r0
	movs r1, #0
	mov r3, r6
	mov r0, r1
	bl fn_08010398                  @ (0, 0, format, args): length
	mov r4, r0                      @ r4 = n
	movs r7, #0
	.inst.n 0x1c40                  @ adds r0, r0, #1
	bl fn_08022b50                  @ allocate n + 1 bytes
	movs r5, r0                     @ r5 = buf
	beq.n .L08012d06
	strb r7, [r5, r4]               @ buf[n] = 0
	mov r3, r6
	mov r2, r8
	adds r1, r4, #1
	bl fn_08010398                  @ (buf, n + 1, format, args)
	mov r0, r5
.L08012d02:
	pop.w {r4, r5, r6, r7, r8, pc}
.L08012d06:
	movs r0, #0
	b.n .L08012d02
	.short 0x0000                   @ padding

@ ----------------------------------------------------------------------------
@ binary_search_with_compare - binary search with a compare function.
@ Parameters: r0 = key (r10), r1 = base (r5), r2 = element count (r4),
@ r3 = element size (r6), stack: compare function (r9).
@ Loop: count 0 returns 0; mid = base + (count >> 1) * size; c = compare(key,
@ mid); c < 0 halves the count; c > 0 sets base = mid + size and count = count -
@ (count >> 1) - 1; c = 0 returns mid.
@ ----------------------------------------------------------------------------
	.section .text.binary_search_with_compare,"ax",%progbits
	.p2align 2
	.global binary_search_with_compare
	.thumb_func
	.type binary_search_with_compare, %function
binary_search_with_compare:
	push.w {r4, r5, r6, r7, r8, r9, r10, lr}
	mov r6, r3
	mov r4, r2
	mov r5, r1
	mov r10, r0
	ldr.w r9, [sp, #0x20]
	b.n .L08012d4a
	nop                             @ padding
.L08012d20:
	lsr.w r8, r4, #1
	mla r7, r8, r6, r5
	mov r1, r7
	mov r0, r10
	mov r2, r9
	blx r2                          @ compare(key, mid)
	cmp r0, #0
	ble.n .L08012d46
	sbfx r0, r4, #0, #1
	rsb r4, r0, r4, lsr #1
	add.w r5, r7, r6
	sub.w r4, r4, #1
	b.n .L08012d4a
.L08012d46:
	bge.n .L08012d54
	mov r4, r8
.L08012d4a:
	cmp r4, #0
	bne.n .L08012d20
	mov r0, r4
.L08012d50:
	pop.w {r4, r5, r6, r7, r8, r9, r10, pc}
.L08012d54:
	mov r0, r7
	b.n .L08012d50

@ ----------------------------------------------------------------------------
@ fn_08012d58 - printf style formatter with an output callback.
@ Parameters: r0 = format string pointer (kept in r6), r1 = pointer to the
@ argument words (kept in r8, read with post-increment 4; 8-byte items first
@ align r8 to 8 with (r8 + 7) & ~7), r2 = context word (stored at [sp + 0x5c]),
@ r3 = output callback (kept in r10, called as callback(r0 = character,
@ r1 = context)). Returns r0 = number of characters output (r5).
@ Entry: pushes r0-r11 and lr, sub sp #0x54, r5 = 0, branches to the loop test
@ at .L08013146.
@ Loop (.L08013144 advances the format pointer, .L08013146 tests the byte):
@ reads the next format byte; 0 ends (.L0801314e: add sp #0x64, r0 = r5, pop pc);
@ a byte other than 0x25 and an unknown conversion character are output through
@ the callback (.L08012e90, r5 += 1).
@ After 0x25: flags r4 = 0, width [sp + 0xc] = 0, precision r7 = 0. Flag
@ characters are those whose bit (c - 0x20) is set in the mask 0x00012809 (loaded
@ from the literal pool): ' ' sets 0x1, '#' sets 0x8, '+' sets 0x800, '-' sets
@ 0x2000, '0' sets 0x10000. Width: '*' takes a word argument (negative sets
@ 0x2000 and negates), digits accumulate w = 10 * w + (c - 0x30); either sets 0x2.
@ '.' sets 0x4 and takes '*' (word argument) or digits for r7. Length: 'l' =
@ 0x100000 (a second 'l' adds 0x100000), 'h' = 0x300000 (a second 'h' adds
@ 0x100000), 'j' = 0x200000, 'L', 't' and 'z' set nothing; the length class is
@ bits 20..22 of r4 (ubfx #0x14, #3): 2 = 64-bit, 3 = 16-bit, 4 = 8-bit,
@ otherwise 32-bit.
@ Conversion dispatch (.L08012e3c): e E f F g G -> .L08013184; d i -> .L08012f5a;
@ u -> .L08012fc0 (radix 10); x X -> .L08012fc4 (radix 16); o -> .L08012fde
@ (radix 8); p -> .L08012fce (radix 16, sets 0x4 and precision 8); c ->
@ .L08012ece; s -> .L08012ee2; n -> .L08012e9a; NUL -> return; others are output
@ as the character.
@ n (.L08012e9a): stores r5 at the pointer argument: 64-bit (r5 and r5 >> 31) for
@ class 2, halfword for 3, byte for 4, word otherwise.
@ c / s (.L08012ece, string length loops .L08012ef4 and .L08012f0c): c takes the
@ low byte of a word argument as a 1-byte string, s takes a string pointer; the
@ length (r9) stops at a NUL or at the precision when 0x4 is set; the pad count =
@ width - length is written through write_pad_chars_if_flag_bit13_clear(count,
@ flags, context, callback) (pad character 0x30 when flag 0x10000 else 0x20,
@ only when flag 0x2000 is clear), the string bytes through the callback, then
@ write_spaces_if_flag_bit13_set(pad, flags, context, callback) (spaces, only
@ when flag 0x2000 is set) via .L0801313e; r5 += every written count.
@ d / i (.L08012f5a): value fetched as 64-bit (class 2), sxth (3), sxtb (4) or a
@ 32-bit word sign-extended; a negative value is negated as 64-bit and r9 = 1
@ with '-' at [sp + 4]; otherwise '+' when flag 0x800, ' ' when flag 0x1, else
@ r9 = 0.
@ u o x X p (.L08012fe6): fetched as 64-bit (class 2), uxth (3), uxtb (4) or a
@ 32-bit word zero-extended.
@ Prefix with flag 0x8 (.L08013016): conversion p stores '@' (0x40) at [sp + 4],
@ r9 = 1; radix 16 with a nonzero value stores '0' and the conversion character
@ (r9 = 2); radix 8 with a nonzero value, or a zero value with precision given,
@ stores '0', r9 = 1 and decrements r7.
@ Digits (.L08013070): table .L0801315c "0123456789abcdef" or, for conversion X,
@ table .L08013170 "0123456789ABCDEF"; while the 64-bit value is nonzero calls
@ unsigned_divide_64(value, radix) (quotient r0:r1, remainder r2) and stores
@ table[remainder] backwards from [sp + 0x30].
@ Layout (.L0801309e): r11 = digit count; with precision (flag 0x4) clears flag
@ 0x10000, otherwise r7 = 1; zeros = max(r7 - digits, 0); remaining pad = width -
@ (zeros + digits + r9); pad through write_pad_chars_if_flag_bit13_clear first
@ when flag 0x10000 is clear, then the r9 prefix bytes, then the pad when flag
@ 0x10000 is set, then zeros ('0' through the callback), then the digits, then
@ write_spaces_if_flag_bit13_set for the trailing pad (.L080133f6, .L0801313e).
@ Floating conversions (.L08013184): precision r7 = 6 unless flag 0x4; reads an
@ 8-byte item (r2 low, r3 high), sign string pointer = "-" (.L08013400, sign bit
@ set), "+" (.L08013404, flag 0x800), " " (.L08013408, flag 0x1) or the empty
@ string at .L0801316c, high word has the sign bit cleared; e / E: digit count
@ min(r7 + 1, 17); f / F: precision r7; g / G: r7 raised to at least 1, digit
@ count min(r7, 17); calls fn_08011c98 with the result words at [sp + 0x30..0x3c]
@ and removes trailing '0' digits for g / G unless flag 0x8; the e form writes the
@ letter (conversion character & 0x20 | 0x45 pattern), the sign and at least 2
@ exponent digits; the width pad uses the two pad functions as above; the digit
@ loop writes digits or '0' and writes '.' (0x2e) when its counter reaches 0.
@ Dead piece: .L08012f3c (b.n .L08012f5a, one instruction) is entered by no
@ instruction.
@ The strings 0x0801315c..0x0801317f and the sign strings 0x08013400..0x0801340b
@ are data inside this unit.
@ ----------------------------------------------------------------------------
	.section .text.fn_08012d58,"ax",%progbits
	.p2align 2
	.global fn_08012d58
	.thumb_func
	.type fn_08012d58, %function
fn_08012d58:
	push.w {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	sub sp, #0x54
	mov r10, r3                     @ r10 = output callback
	mov r8, r1                      @ r8 = argument words
	mov r6, r0                      @ r6 = format pointer
	movs r5, #0                     @ r5 = characters output
	b.n .L08013146
.L08012d68:
	cmp r0, #0x25
	bne.n .L08012e5c
	movs r4, #0                     @ r4 = flags
	mov r7, r4                      @ r7 = precision
	ldr r2, .L08013158              @ r2 = flag character mask 0x00012809
	movs r1, #1
	str r4, [sp, #0xc]              @ width = 0
	b.n .L08012d7a
.L08012d78:
	orrs r4, r0                     @ add the flag bit
.L08012d7a:
	ldrb.w r3, [r6, #1]!
	subs r3, #0x20
	lsl.w r0, r1, r3
	tst r0, r2
	bne.n .L08012d78
	ldrb r0, [r6, #0]
	cmp r0, #0x2a
	beq.n .L08012db2
	mvn r3, #0x2f                   @ r3 = -0x30
.L08012d92:
	ldrb r0, [r6, #0]
	sub.w r2, r0, #0x30
	cmp r2, #9
	bhi.n .L08012dca
	ldr r2, [sp, #0xc]
	orr.w r4, r4, #2
	add.w r2, r2, r2, lsl #2
	add.w r2, r3, r2, lsl #1
	add r0, r2
	.inst.n 0x1c76                  @ adds r6, r6, #1
	str r0, [sp, #0xc]              @ width = 10 * width + digit
	b.n .L08012d92
.L08012db2:
	ldr.w r2, [r8], #4              @ width from the arguments
	str r2, [sp, #0xc]
	cmp r2, #0
	bge.n .L08012dc4
	rsbs r0, r2, #0
	orr.w r4, r4, #0x2000
	str r0, [sp, #0xc]
.L08012dc4:
	orr.w r4, r4, #2
	.inst.n 0x1c76                  @ adds r6, r6, #1
.L08012dca:
	ldrb r0, [r6, #0]
	cmp r0, #0x2e
	bne.n .L08012dfe
	ldrb.w r0, [r6, #1]!
	orr.w r4, r4, #4
	cmp r0, #0x2a
	beq.n .L08012df8
	mvn r2, #0x2f                   @ r2 = -0x30
.L08012de0:
	ldrb r0, [r6, #0]
	sub.w r3, r0, #0x30
	cmp r3, #9
	bhi.n .L08012dfe
	add.w r3, r7, r7, lsl #2
	add.w r3, r2, r3, lsl #1
	adds r7, r0, r3                 @ precision = 10 * precision + digit
	.inst.n 0x1c76                  @ adds r6, r6, #1
	b.n .L08012de0
.L08012df8:
	ldr.w r7, [r8], #4              @ precision from the arguments
	.inst.n 0x1c76                  @ adds r6, r6, #1
.L08012dfe:
	ldrb r0, [r6, #0]
	cmp r0, #0x6c
	beq.n .L08012e24
	bgt.n .L08012e14
	cmp r0, #0x4c
	beq.n .L08012e3a
	cmp r0, #0x68
	beq.n .L08012e2a
	cmp r0, #0x6a
	bne.n .L08012e3c
	b.n .L08012e1e
.L08012e14:
	cmp r0, #0x74
	beq.n .L08012e3a
	cmp r0, #0x7a
	bne.n .L08012e3c
	b.n .L08012e3a
.L08012e1e:
	orr.w r4, r4, #0x200000
	b.n .L08012e3a
.L08012e24:
	orr.w r4, r4, #0x100000
	b.n .L08012e2e
.L08012e2a:
	orr.w r4, r4, #0x300000
.L08012e2e:
	ldrb r2, [r6, #1]
	cmp r2, r0
	bne.n .L08012e3a
	add.w r4, r4, #0x100000
	.inst.n 0x1c76                  @ adds r6, r6, #1
.L08012e3a:
	.inst.n 0x1c76                  @ adds r6, r6, #1
.L08012e3c:
	ldrb r0, [r6, #0]
	cmp r0, #0x66
.L08012e40:
	beq.n .L08012e5a
	bgt.n .L08012e6c
	cmp r0, #0x58
	beq.n .L08012f38
	bgt.n .L08012e5e
	cmp r0, #0
	beq.n .L08012f3a
	cmp r0, #0x45
	beq.n .L08012e40
	cmp r0, #0x46
	beq.n .L08012e40
	cmp r0, #0x47
	bne.n .L08012e90
.L08012e5a:
	b.n .L08013184
.L08012e5c:
	b.n .L08012e90
.L08012e5e:
	cmp r0, #0x63
	beq.n .L08012ece
	cmp r0, #0x64
	beq.n .L08012f5a
	cmp r0, #0x65
	bne.n .L08012e90
	b.n .L08013184
.L08012e6c:
	cmp r0, #0x70
	beq.n .L08012f58
	bgt.n .L08012e84
	cmp r0, #0x67
	beq.n .L08012e5a
	cmp r0, #0x69
	beq.n .L08012f5a
	cmp r0, #0x6e
	beq.n .L08012e9a
	cmp r0, #0x6f
	bne.n .L08012e90
	b.n .L08012fde
.L08012e84:
	cmp r0, #0x73
	beq.n .L08012ee2
	cmp r0, #0x75
	beq.n .L08012f76
	cmp r0, #0x78
	beq.n .L08012f38
.L08012e90:
	mov r2, r10
	ldr r1, [sp, #0x5c]
	blx r2                          @ callback(character, context)
	.inst.n 0x1c6d                  @ adds r5, r5, #1
	b.n .L08013144
.L08012e9a:
	ubfx r0, r4, #0x14, #3          @ length class
	cmp r0, #2
	beq.n .L08012eb6
	cmp r0, #3
	beq.n .L08012ec2
	ldr.w r1, [r8, #0]
	cmp r0, #4
	beq.n .L08012eca
	str r5, [r1, #0]
.L08012eb0:
	add.w r8, r8, #4
	b.n .L08013144
.L08012eb6:
	ldr.w r1, [r8, #0]
	asrs r2, r5, #31
	strd r5, r2, [r1, #0]
	b.n .L08012eb0
.L08012ec2:
	ldr.w r1, [r8, #0]
	strh r5, [r1, #0]
	b.n .L08012eb0
.L08012eca:
	strb r5, [r1, #0]
	b.n .L08012eb0
.L08012ece:
	ldrb.w r1, [r8], #4             @ 'c': low byte of the word argument
	strb.w r1, [sp, #0]
	movs r0, #0
	strb.w r0, [sp, #1]
	mov r11, sp                     @ r11 = string pointer
	movs r0, #1                     @ r0 = string length limit
	b.n .L08012eea
.L08012ee2:
	ldr.w r11, [r8], #4             @ 's': string pointer
	mov.w r0, #0xffffffff
.L08012eea:
	lsls r1, r4, #0x1d
	mov.w r1, #0
	bmi.n .L08012ef8
	b.n .L08012f10
.L08012ef4:
	add.w r1, r9, #1
.L08012ef8:
	mov r9, r1
	cmp r1, r7
	bge.n .L08012f1e
	cmp r9, r0
	blt.n .L08012ef4
	ldrb.w r1, [r11, r9]
	cmp r1, #0
	bne.n .L08012ef4
	b.n .L08012f1e
.L08012f0c:
	add.w r1, r9, #1
.L08012f10:
	mov r9, r1
	cmp r1, r0
	blt.n .L08012f0c
	ldrb.w r1, [r11, r9]
	cmp r1, #0
	bne.n .L08012f0c
.L08012f1e:
	ldr r0, [sp, #0xc]
	mov r3, r10
	sub.w r7, r0, r9                @ pad count = width - length
	mov r1, r4
	mov r0, r7
	ldr r2, [sp, #0x5c]
	bl write_pad_chars_if_flag_bit13_clear
	add r0, r5
	add.w r5, r0, r9
	b.n .L08012f48
.L08012f38:
	b.n .L08012fc4
.L08012f3a:
	b.n .L0801314e
	b.n .L08012f5a                  @ dead: entered by no instruction
.L08012f3e:
	ldrb.w r0, [r11], #1
	mov r2, r10
	ldr r1, [sp, #0x5c]
	blx r2                          @ callback(string byte, context)
.L08012f48:
	subs.w r9, r9, #1
	bhs.n .L08012f3e
	mov r3, r10
	mov r1, r4
	mov r0, r7
	ldr r2, [sp, #0x5c]
	b.n .L0801313e
.L08012f58:
	b.n .L08012fce
.L08012f5a:
	movs r1, #0xa
	ubfx r2, r4, #0x14, #3
	mov.w r11, #0
	str r1, [sp, #0]                @ radix 10
	cmp r2, #2
	beq.n .L08012f78
	ldr.w r0, [r8], #4
	asrs r1, r0, #31
	cmp r2, #3
	beq.n .L08012f88
	b.n .L08012f8c
.L08012f76:
	b.n .L08012fc0
.L08012f78:
	add.w r0, r8, #7
	bic.w r2, r0, #7
	ldrd r0, r1, [r2], #8
	mov r8, r2
	b.n .L08012f94
.L08012f88:
	sxth r0, r0
	asrs r1, r0, #31
.L08012f8c:
	cmp r2, #4
	bne.n .L08012f94
	sxtb r0, r0
	asrs r1, r0, #31
.L08012f94:
	cmp r1, #0
	bge.n .L08012fa6
	mov r2, r1
	movs r1, #0
	rsbs r0, r0, #0
	sbc.w r1, r1, r2                @ negate the 64-bit value
	movs r2, #0x2d                  @ '-'
	b.n .L08012fac
.L08012fa6:
	lsls r2, r4, #0x14
	bpl.n .L08012fb4
	movs r2, #0x2b                  @ '+'
.L08012fac:
	strb.w r2, [sp, #4]
	movs r2, #1
	b.n .L08012fbc
.L08012fb4:
	lsls r2, r4, #0x1f
	beq.n .L08012fbc
	movs r2, #0x20                  @ ' '
	b.n .L08012fac
.L08012fbc:
	mov r9, r2
	b.n .L08013070
.L08012fc0:
	movs r1, #0xa
	b.n .L08012fc6
.L08012fc4:
	movs r1, #0x10
.L08012fc6:
	mov.w r11, #0
	str r1, [sp, #0]                @ radix
	b.n .L08012fe6
.L08012fce:
	movs r1, #0x10
	mov.w r11, #0
	orr.w r4, r4, #4
	movs r7, #8                     @ precision 8 for 'p'
	str r1, [sp, #0]
	b.n .L08012fe6
.L08012fde:
	movs r0, #8
	mov.w r11, #0
	str r0, [sp, #0]                @ radix 8
.L08012fe6:
	ubfx r2, r4, #0x14, #3
	cmp r2, #2
	beq.n .L08012ffa
	ldr.w r0, [r8], #4
	movs r1, #0
	cmp r2, #3
	beq.n .L0801300a
	b.n .L0801300c
.L08012ffa:
	add.w r0, r8, #7
	bic.w r2, r0, #7
	ldrd r0, r1, [r2], #8
	mov r8, r2
	b.n .L08013012
.L0801300a:
	uxth r0, r0
.L0801300c:
	cmp r2, #4
	bne.n .L08013012
	uxtb r0, r0
.L08013012:
	mov.w r9, #0
	lsls r2, r4, #0x1c
	bpl.n .L08013070
	ldrb r2, [r6, #0]
	cmp r2, #0x70
	beq.n .L08013030
	ldr.w r12, [sp, #0]
	eor.w r12, r12, #0x10
	orrs.w r12, r12, r11
	beq.n .L0801303a
	b.n .L0801304e
.L08013030:
	movs r2, #0x40                  @ '@'
	strb.w r2, [sp, #4]
	movs r2, #1
	b.n .L0801304c
.L0801303a:
	orrs.w r3, r0, r1
	beq.n .L0801304e
	movs r3, #0x30                  @ '0'
	strb.w r3, [sp, #4]
	strb.w r2, [sp, #5]             @ conversion character
	movs r2, #2
.L0801304c:
	mov r9, r2
.L0801304e:
	ldr r3, [sp, #0]
	eor.w r3, r3, #8
	orrs.w r3, r3, r11
	bne.n .L08013070
	orrs.w r2, r0, r1
	bne.n .L08013064
	lsls r2, r4, #0x1d
	bpl.n .L08013070
.L08013064:
	movs r2, #0x30                  @ '0'
	strb.w r2, [sp, #4]
	mov.w r9, #1
	.inst.n 0x1e7f                  @ subs r7, r7, #1
.L08013070:
	ldrb r2, [r6, #0]
	cmp r2, #0x58
	beq.n .L08013080
	adr r2, .L0801315c              @ lower case digit table
.L08013078:
	str r2, [sp, #0x30]
	add r2, sp, #0x30
	str r2, [sp, #8]
	b.n .L08013098
.L08013080:
	adr r2, .L08013170              @ upper case digit table
	b.n .L08013078
.L08013084:
	mov r3, r11
	ldr r2, [sp, #0]
	bl unsigned_divide_64           @ value / radix: quotient r0:r1, remainder r2
	ldr r3, [sp, #0x30]
	ldrb r3, [r3, r2]
	ldr r2, [sp, #8]
	.inst.n 0x1e52                  @ subs r2, r2, #1
	str r2, [sp, #8]
	strb r3, [r2, #0]               @ store the digit backwards
.L08013098:
	orrs.w r2, r0, r1
	bne.n .L08013084
	ldr r0, [sp, #8]
	add r1, sp, #0x10
	subs r0, r1, r0
	add.w r11, r0, #0x20            @ r11 = digit count
	lsls r0, r4, #0x1d
	bpl.n .L080130b2
	bic.w r4, r4, #0x10000
	b.n .L080130b4
.L080130b2:
	movs r7, #1
.L080130b4:
	cmp r7, r11
	ble.n .L080130be
	sub.w r0, r7, r11
	b.n .L080130c0
.L080130be:
	movs r0, #0
.L080130c0:
	add.w r1, r0, r11
	str r0, [sp, #0]                @ zeros
	ldr r0, [sp, #0xc]
	add r1, r9
	subs r0, r0, r1
	str r0, [sp, #0xc]              @ remaining pad
	lsls r0, r4, #15
	bmi.n .L080130e0
	mov r3, r10
	mov r1, r4
	ldr r2, [sp, #0x5c]
	ldr r0, [sp, #0xc]
	bl write_pad_chars_if_flag_bit13_clear
	add r5, r0
.L080130e0:
	movs r7, #0
	b.n .L080130f2
.L080130e4:
	add r0, sp, #4
	mov r2, r10
	ldrb r0, [r0, r7]
	ldr r1, [sp, #0x5c]
	blx r2                          @ callback(prefix byte, context)
	.inst.n 0x1c6d                  @ adds r5, r5, #1
	.inst.n 0x1c7f                  @ adds r7, r7, #1
.L080130f2:
	cmp r7, r9
	blt.n .L080130e4
	lsls r0, r4, #15
	bpl.n .L08013114
	mov r3, r10
	mov r1, r4
	ldr r2, [sp, #0x5c]
	ldr r0, [sp, #0xc]
	bl write_pad_chars_if_flag_bit13_clear
	add r5, r0
	b.n .L08013114
.L0801310a:
	movs r0, #0x30
	mov r2, r10
	ldr r1, [sp, #0x5c]
	blx r2                          @ callback('0', context)
	.inst.n 0x1c6d                  @ adds r5, r5, #1
.L08013114:
	ldr r1, [sp, #0]
	subs r0, r1, #1
	str r0, [sp, #0]
	cmp r1, #0
	bgt.n .L0801310a
	b.n .L08013132
.L08013120:
	ldr r0, [sp, #8]
	ldr r1, [sp, #8]
	mov r2, r10
	ldrb r0, [r0, #0]
	.inst.n 0x1c49                  @ adds r1, r1, #1
	str r1, [sp, #8]
	ldr r1, [sp, #0x5c]
	blx r2                          @ callback(digit, context)
	.inst.n 0x1c6d                  @ adds r5, r5, #1
.L08013132:
	subs.w r1, r11, #0
	sub.w r11, r11, #1
	bgt.n .L08013120
	b.n .L080133f6
.L0801313e:
	bl write_spaces_if_flag_bit13_set
	add r5, r0
.L08013144:
	.inst.n 0x1c76                  @ adds r6, r6, #1
.L08013146:
	ldrb r0, [r6, #0]
	cmp r0, #0
	bne.w .L08012d68
.L0801314e:
	add sp, #0x64
	mov r0, r5
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
	.short 0x0000                   @ padding
.L08013158:
	.word 0x00012809                @ flag character mask
.L0801315c:
	.ascii "0123456789abcdef"
.L0801316c:
	.byte 0x00, 0x00, 0x00, 0x00    @ empty sign string
.L08013170:
	.ascii "0123456789ABCDEF"
	.byte 0x00
	.byte 0x00, 0x00, 0x00          @ padding
.L08013184:
	lsls r0, r4, #0x1d
	bmi.n .L0801318a
	movs r7, #6                     @ default precision 6
.L0801318a:
	add.w r0, r8, #7
	bic.w r0, r0, #7
	ldrd r2, r3, [r0], #8           @ r2 = low word, r3 = high word of the value
	mov r8, r0
	and.w r12, r3, #0x80000000
	movs.w r0, r12
	beq.n .L080131a6
	adr r0, .L08013400              @ "-"
	b.n .L080131ba
.L080131a6:
	lsls r0, r4, #0x14
	bpl.n .L080131ae
	adr r0, .L08013404              @ "+"
	b.n .L080131ba
.L080131ae:
	lsls r0, r4, #0x1f
	beq.n .L080131b6
	adr r0, .L08013408              @ " "
	b.n .L080131ba
.L080131b6:
	adr.w r0, .L0801316c            @ empty string
.L080131ba:
	str r0, [sp, #0x4c]             @ sign string pointer
	ldrb r0, [r6, #0]
	bic.w r3, r3, #0x80000000
	cmp r0, #0x65
	beq.n .L080131e0
	bgt.n .L080131d6
	cmp r0, #0x45
	beq.n .L080131e0
	cmp r0, #0x46
	beq.n .L0801320c
	cmp r0, #0x47
	bne.n .L080132d4
	b.n .L0801324e
.L080131d6:
	cmp r0, #0x66
	beq.n .L0801320c
	cmp r0, #0x67
	bne.n .L080132d4
	b.n .L0801324e
.L080131e0:
	movs r1, #0
	cmp r7, #0x11
	blt.n .L080131ea
	movs r0, #0x11
	b.n .L080131ec
.L080131ea:
	adds r0, r7, #1
.L080131ec:
	strd r0, r1, [sp, #0]
	add r1, sp, #0x10
	add r0, sp, #0x30
	bl fn_08011c98
	ldrd r0, r1, [sp, #0x34]
	ldr r2, [sp, #0x30]
	mov.w r11, #0
	add.w r9, r7, #1
	str r2, [sp, #0x40]
	str r1, [sp, #0]
	b.n .L080132aa
.L0801320c:
	mov.w r0, #0x80000000
	str r7, [sp, #0]
	strd r1, r0, [sp, #4]
	add r1, sp, #0x10
	add r0, sp, #0x30
	bl fn_08011c98
	ldrd r0, r2, [sp, #0x34]
	ldr r3, [sp, #0x30]
	ldr r1, [sp, #0x3c]
	mov.w r11, #0
	mov r9, r2
	str r3, [sp, #0x40]
	str r2, [sp, #0]
	cbnz r1, .L08013238
	adds r1, r7, #1
	add.w r9, r0, r1
.L08013238:
	subs.w r0, r7, r9
	bmi.n .L08013246
	rsb.w r11, r0, #0xffffffff
	add.w r9, r7, #1
.L08013246:
	sub.w r0, r9, r7
	str r0, [sp, #4]
	b.n .L080132d4
.L0801324e:
	cmp r7, #1
	bge.n .L08013254
	movs r7, #1
.L08013254:
	movs r1, #0
	cmp r7, #0x11
	ble.n .L0801325e
	movs r0, #0x11
	b.n .L08013260
.L0801325e:
	mov r0, r7
.L08013260:
	strd r0, r1, [sp, #0]
	add r1, sp, #0x10
	add r0, sp, #0x30
	bl fn_08011c98
	ldrd r0, r1, [sp, #0x34]
	ldr r2, [sp, #0x30]
	str r1, [sp, #0]
	mov.w r11, #0
	mov r9, r7
	str r2, [sp, #0x40]
	lsls r1, r4, #0x1c
	bmi.n .L080132a0
	ldr r2, [sp, #0]
	cmp r2, r9
	bge.n .L0801328e
	mov r9, r2
	b.n .L0801328e
.L0801328a:
	sub.w r9, r9, #1                @ drop one trailing zero digit
.L0801328e:
	cmp.w r9, #1
	ble.n .L080132a0
	ldr r2, [sp, #0x40]
	sub.w r1, r9, #1
	ldrb r1, [r2, r1]
	cmp r1, #0x30
	beq.n .L0801328a
.L080132a0:
	cmp r0, r7
	bge.n .L080132aa
	cmn.w r0, #4
	bge.n .L080132b2
.L080132aa:
	movs r1, #1
	strd r1, r0, [sp, #4]
	b.n .L080132d4
.L080132b2:
	cmp r0, #0
	bgt.n .L080132be
	add r11, r0
	sub.w r1, r9, r0
	b.n .L080132c4
.L080132be:
	adds r1, r0, #1
	cmp r1, r9
	ble.n .L080132c6
.L080132c4:
	mov r9, r1
.L080132c6:
	sub.w r0, r0, r11
	.inst.n 0x1c40                  @ adds r0, r0, #1
	str r0, [sp, #4]
	mov.w r0, #0x80000000
	str r0, [sp, #8]
.L080132d4:
	lsls r0, r4, #0x1c
	bmi.n .L080132e4
	ldr r0, [sp, #4]
	cmp r0, r9
	blt.n .L080132e4
	mov.w r0, #0xffffffff
	str r0, [sp, #4]
.L080132e4:
	movs r0, #0
	strb.w r0, [sp, #0x4b]          @ terminator of the exponent text
	ldr r0, [sp, #8]
	add.w r7, sp, #0x4b
	cmp.w r0, #0x80000000
	beq.n .L08013342
	movs r0, #2
	str r0, [sp, #0x30]             @ minimum exponent digit count
	movs r0, #0x2b                  @ '+'
	str r0, [sp, #0x34]
	ldr r0, [sp, #8]
	cmp r0, #0
	bge.n .L0801331e
	rsbs r0, r0, #0
	str r0, [sp, #8]
	movs r0, #0x2d                  @ '-'
	str r0, [sp, #0x34]
	b.n .L0801331e
.L0801330e:
	movs r1, #0xa
	ldr r0, [sp, #8]
	bl unsigned_divide_32           @ exponent / 10: quotient r0, remainder r1
	adds r1, #0x30
	str r0, [sp, #8]
	strb.w r1, [r7, #-1]!           @ store the exponent digit backwards
.L0801331e:
	ldr r1, [sp, #0x30]
	subs r0, r1, #1
	str r0, [sp, #0x30]
	cmp r1, #0
	bgt.n .L0801330e
	ldr r0, [sp, #8]
	cmp r0, #0
	bne.n .L0801330e
	subs r1, r7, #1
	ldr r0, [sp, #0x34]
	strb r0, [r1, #0]               @ exponent sign
	ldrb r0, [r6, #0]
	and.w r0, r0, #0x20
	orr.w r0, r0, #0x45
	strb.w r0, [r7, #-2]!           @ exponent letter
.L08013342:
	add r0, sp, #0x44
	subs r0, r0, r7
	.inst.n 0x1dc0                  @ adds r0, r0, #7
	str r0, [sp, #8]
	ldr r0, [sp, #0x4c]
	ldrb r0, [r0, #0]
	cbz r0, .L08013352
	movs r0, #1
.L08013352:
	add.w r1, r0, r9
	ldr r0, [sp, #4]
	add.w r1, r1, r0, asr #31
	ldr r0, [sp, #8]
	add r1, r0
	ldr r0, [sp, #0xc]
	subs r0, r0, r1
	.inst.n 0x1e40                  @ subs r0, r0, #1
	str r0, [sp, #0xc]
	lsls r0, r4, #15
	bmi.n .L0801337a
	mov r3, r10
	mov r1, r4
	ldr r2, [sp, #0x5c]
	ldr r0, [sp, #0xc]
	bl write_pad_chars_if_flag_bit13_clear
	add r5, r0
.L0801337a:
	ldr r0, [sp, #0x4c]
	ldrb r0, [r0, #0]
	cbz r0, .L08013388
	mov r2, r10
	ldr r1, [sp, #0x5c]
	blx r2                          @ callback(sign character, context)
	.inst.n 0x1c6d                  @ adds r5, r5, #1
.L08013388:
	lsls r0, r4, #15
	bpl.n .L080133d4
	mov r3, r10
	mov r1, r4
	ldr r2, [sp, #0x5c]
	ldr r0, [sp, #0xc]
	bl write_pad_chars_if_flag_bit13_clear
	add r5, r0
	b.n .L080133d4
.L0801339c:
	cmp.w r11, #0
	blt.n .L080133b2
	ldr r0, [sp, #0]
	cmp r0, r11
	ble.n .L080133b2
	ldr r0, [sp, #0x40]
	ldr r1, [sp, #0x5c]
	ldrb.w r0, [r0, r11]
	b.n .L080133b6
.L080133b2:
	ldr r1, [sp, #0x5c]
	movs r0, #0x30                  @ '0'
.L080133b6:
	mov r2, r10
	blx r2                          @ callback(digit or '0', context)
	ldr r0, [sp, #4]
	add.w r11, r11, #1
	.inst.n 0x1e40                  @ subs r0, r0, #1
	add.w r5, r5, #1
	str r0, [sp, #4]
	bne.n .L080133d4
	movs r0, #0x2e                  @ '.'
	mov r2, r10
	ldr r1, [sp, #0x5c]
	blx r2
	.inst.n 0x1c6d                  @ adds r5, r5, #1
.L080133d4:
	subs.w r1, r9, #0
	sub.w r9, r9, #1
	bgt.n .L0801339c
	b.n .L080133ec
.L080133e0:
	ldrb.w r0, [r7], #1
	mov r2, r10
	ldr r1, [sp, #0x5c]
	blx r2                          @ callback(exponent text byte, context)
	.inst.n 0x1c6d                  @ adds r5, r5, #1
.L080133ec:
	ldr r1, [sp, #8]
	subs r0, r1, #1
	str r0, [sp, #8]
	cmp r1, #0
	bgt.n .L080133e0
.L080133f6:
	mov r3, r10
	mov r1, r4
	ldr r2, [sp, #0x5c]
	ldr r0, [sp, #0xc]
	b.n .L0801313e
.L08013400:
	.byte 0x2d                      @ "-"
	.byte 0x00, 0x00, 0x00          @ padding
.L08013404:
	.asciz "+"
	.short 0x0000                   @ padding
.L08013408:
	.asciz " "
	.short 0x0000                   @ padding

@ ----------------------------------------------------------------------------
@ write_spaces_if_flag_bit13_set - writes trailing padding spaces.
@ Parameters: r0 = number of padding characters (r4), r1 = flag word, r2 =
@ callback context (r7), r3 = output callback (r6, called as callback(0x20,
@ context)). Returns the number of characters written (r0).
@ Does nothing and returns 0 unless flag bit 13 (0x2000, lsls r0, r1, #18) is
@ set. When it is set it decrements r0 and, while the result is not negative,
@ calls the callback with 0x20 and increments the count, so it writes r0 spaces
@ for r0 >= 0. Saves r4-r8 and lr.
@ ----------------------------------------------------------------------------
	.section .text.write_spaces_if_flag_bit13_set,"ax",%progbits
	.p2align 2
	.global write_spaces_if_flag_bit13_set
	.thumb_func
	.type write_spaces_if_flag_bit13_set, %function
write_spaces_if_flag_bit13_set:
	push.w {r4, r5, r6, r7, r8, lr}
	mov r4, r0
	movs r5, #0                     @ r5 = count
	mov r6, r3
	mov r7, r2
	lsls r0, r1, #18                @ flag bit 13 into the sign
	bmi.n .L08013426
	b.n .L0801342a
.L0801341e:
	mov r1, r7
	movs r0, #0x20
	blx r6                          @ callback(0x20, context)
	.inst.n 0x1c6d                  @ adds r5, r5, #1
.L08013426:
	.inst.n 0x1e64                  @ subs r4, r4, #1
	bpl.n .L0801341e
.L0801342a:
	mov r0, r5
	pop.w {r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ write_pad_chars_if_flag_bit13_clear - writes leading padding characters.
@ Parameters: r0 = number of padding characters (r4), r1 = flag word, r2 =
@ callback context (r8), r3 = output callback (r6, called as callback(char,
@ context)). Returns the number of characters written (r0).
@ The pad character (r7) is 0x30 when flag bit 16 (0x10000, lsls r0, r1, #15) is
@ set, otherwise 0x20. It is written r0 times through the callback only when
@ flag bit 13 (0x2000) is clear, otherwise none are written.
@ ----------------------------------------------------------------------------
	.section .text.write_pad_chars_if_flag_bit13_clear,"ax",%progbits
	.global write_pad_chars_if_flag_bit13_clear
	.thumb_func
	.type write_pad_chars_if_flag_bit13_clear, %function
write_pad_chars_if_flag_bit13_clear:
	push.w {r4, r5, r6, r7, r8, lr}
	mov r4, r0
	movs r5, #0                     @ r5 = count
	mov r6, r3
	mov r8, r2
	lsls r0, r1, #15                @ flag bit 16 into the sign
	bpl.n .L08013444
	movs r7, #0x30
	b.n .L08013446
.L08013444:
	movs r7, #0x20
.L08013446:
	lsls r0, r1, #18                @ flag bit 13 into the sign
	bpl.n .L08013454
	b.n .L08013458
.L0801344c:
	mov r1, r8
	mov r0, r7
	blx r6                          @ callback(pad character, context)
	.inst.n 0x1c6d                  @ adds r5, r5, #1
.L08013454:
	.inst.n 0x1e64                  @ subs r4, r4, #1
	bpl.n .L0801344c
.L08013458:
	mov r0, r5
	pop.w {r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------------------
@ store_byte_advance_pointer_if_space_left - stores a byte into a bounded buffer.
@ Parameters: r0 = character, r1 = pointer to a 2-word record (word 0 = write
@ pointer, word 1 = remaining space); no return value.
@ When the remaining space is not 0 it stores the byte at the write pointer,
@ advances the pointer by 1 and decrements the remaining space by 1; when it is
@ 0 nothing is written.
@ ----------------------------------------------------------------------------
	.section .text.store_byte_advance_pointer_if_space_left,"ax",%progbits
	.global store_byte_advance_pointer_if_space_left
	.thumb_func
	.type store_byte_advance_pointer_if_space_left, %function
store_byte_advance_pointer_if_space_left:
	ldr r2, [r1, #4]
	cmp r2, #0
	beq.n .L08013472
	ldr r2, [r1, #0]
	adds r3, r2, #1
	str r3, [r1, #0]
	strb r0, [r2, #0]
	ldr r0, [r1, #4]
	.inst.n 0x1e40                  @ subs r0, r0, #1
	str r0, [r1, #4]
.L08013472:
	bx lr

@ ----------------------------------------------------------------------------
@ store_byte_advance_pointer - stores a byte and advances the write pointer.
@ Parameters: r0 = character, r1 = pointer to a record whose word 0 is the write
@ pointer; no return value.
@ Stores the byte r0 at the write pointer and advances the pointer by 1, with no
@ bounds check.
@ ----------------------------------------------------------------------------
	.section .text.store_byte_advance_pointer,"ax",%progbits
	.global store_byte_advance_pointer
	.thumb_func
	.type store_byte_advance_pointer, %function
store_byte_advance_pointer:
	ldr r2, [r1, #0]
	adds r3, r2, #1
	str r3, [r1, #0]
	strb r0, [r2, #0]
	bx lr

@ ----------------------------------------------------------------------------
@ fn_0801347e - rounds a size up to an alignment, limited to 0xc..0xffff.
@ Parameters: r0 = size, r1 = alignment; returns the rounded size or 0.
@ Returns 0 when r0 is 0. Loops forever (branch to itself) when r1 is not a power
@ of two (test r1 & (r1 - 1)). Computes (r0 + r1 - 1) & ~(r1 - 1); returns 0
@ when the result is 0x10000 or more, returns 12 (0xc) when the result is below
@ 13, otherwise returns the result.
@ ----------------------------------------------------------------------------
	.section .text.fn_0801347e,"ax",%progbits
	.global fn_0801347e
	.thumb_func
	.type fn_0801347e, %function
fn_0801347e:
	push {r4, lr}
	movs r2, r0
	mov.w r0, #0
	beq.n .L080134a2
	subs r3, r1, #1                 @ r3 = alignment - 1
	tst r1, r3
	beq.n .L08013490
.L0801348e:
	b.n .L0801348e                  @ endless loop: alignment is not a power of two
.L08013490:
	add r2, r1
	.inst.n 0x1e52                  @ subs r2, r2, #1
	bics r2, r3
	cmp.w r2, #0x10000
	bhs.n .L080134a2
	cmp r2, #0xc
	bls.n .L080134a4
	mov r0, r2
.L080134a2:
	pop {r4, pc}
.L080134a4:
	movs r0, #0xc
	pop {r4, pc}

@ ----------------------------------------------------------------------------
@ align_up_pow2 - rounds a value up to a power-of-two alignment.
@ Parameters: r0 = value, r1 = alignment (power of two); returns (r0 + r1 - 1) &
@ ~(r1 - 1). Loops forever (branch to itself) when r1 & (r1 - 1) is not 0.
@ ----------------------------------------------------------------------------
	.section .text.align_up_pow2,"ax",%progbits
	.p2align 2
	.global align_up_pow2
	.thumb_func
	.type align_up_pow2, %function
align_up_pow2:
	add r0, r1
	subs r2, r1, #1                 @ r2 = alignment - 1
	.inst.n 0x1e40                  @ subs r0, r0, #1
	bics r0, r2
	tst r1, r2
	beq.n .L080134b6
.L080134b4:
	b.n .L080134b4                  @ endless loop: alignment is not a power of two
.L080134b6:
	bx lr

@ ----------------------------------------------------------------------------
@ fn_080134b8 - allocates and fills a block header from a pool.
@ Parameters: r0 = object pointer (r9), r1 = size A (r7), r2 = size B; r3 is not
@ used as an input (it is overwritten at 0x080134ec); no return value.
@ Selects r1 as the second size value (r8) when the low 3 bits of the byte at
@ r0 + 9 equal 2, otherwise r2. The larger of r1 and r2 (signed, r6) is the size;
@ the byte count r5 is ((size * 2 + 3) & ~3) + 0x10.
@ Uses the words at 0x20000570 (current pointer), 0x200004e4 (base pointer) and
@ 0x2000056c (limit), reached through r4 = 0x20000568 (+8, +4) and r2 =
@ 0x200004e4: when the used amount plus the byte count reaches the limit and the
@ byte count exceeds the limit it allocates a new block with fn_08022b50 and
@ returns without change when that returns 0; while the used amount plus the byte
@ count exceeds the limit it calls find_record_by_callback(fn_0801a9fc,
@ &local, 0) and find_record_by_callback(fn_0801c17c, &local, 0) (local = -1 at
@ [sp]).
@ Fills the block: word 0 = r0 ^ (second size value) ^ (r1 >> 1), the
@ half-words at offset 0xc and 0xe = size and the second size value, word 1
@ first gets bit 31 set when the block was allocated with fn_08022b50 or cleared
@ when it comes from the pool, then word 1 = ((word 1 & 0xc0000000) + 1) &
@ 0xbfffffff, word 2 = pointer to block + 0x10, and when the block comes from
@ the pool the pointer at 0x20000570 advances by the byte count.
@ ----------------------------------------------------------------------------
	.section .text.fn_080134b8,"ax",%progbits
	.p2align 2
	.global fn_080134b8
	.thumb_func
	.type fn_080134b8, %function
fn_080134b8:
	push.w {r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	mov r9, r0
	ldrb r0, [r0, #9]
	mov r7, r1
	and.w r0, r0, #7
	cmp r0, #2
	beq.n .L080134fe
	mov r0, r2
.L080134cc:
	mov r8, r0                      @ r8 = second size value
	cmp r7, r2
	ble.n .L080134d4
	mov r2, r7
.L080134d4:
	mov r6, r2                      @ r6 = size
	movs r0, #3
	ldr r4, .L08013584              @ r4 = 0x20000568
	ldr r2, .L08013588              @ r2 = 0x200004e4
	add.w r0, r0, r6, lsl #1
	bic.w r5, r0, #3
	ldr r0, [r4, #8]                @ current pointer (0x20000570)
	ldr r1, [r2, #0]                @ base pointer (0x200004e4)
	adds r5, #0x10                  @ r5 = byte count
	subs r1, r0, r1
	ldr r3, [r4, #4]                @ limit (0x2000056c)
	add.w r12, r5, r1
	cmp r12, r3
	bhs.n .L08013502
.L080134f6:
	ldr r1, [r0, #4]
	bic.w r1, r1, #0x80000000
	b.n .L0801354a
.L080134fe:
	mov r0, r1
	b.n .L080134cc
.L08013502:
	cmp r5, r3
	bhi.n .L0801353a
	mov r10, r2
	mov.w r11, #0xffffffff
.L0801350c:
	adds r0, r1, r5
	ldr r1, [r4, #4]
	cmp r0, r1
	bls.n .L08013536
	movs r2, #0
	mov r1, sp
	ldr r0, .L0801358c              @ r0 = fn_0801a9fc
	str.w r11, [sp, #0]
	bl find_record_by_callback
	movs r2, #0
	mov r1, sp
	ldr r0, .L08013590              @ r0 = fn_0801c17c
	bl find_record_by_callback
	ldr r1, [r4, #8]
	ldr.w r0, [r10, #0]
	subs r1, r1, r0
	b.n .L0801350c
.L08013536:
	ldr r0, [r4, #8]
	b.n .L080134f6
.L0801353a:
	mov r0, r5
	bl fn_08022b50                  @ allocate the byte count
	cmp r0, #0
	beq.n .L08013572
	ldr r1, [r0, #4]
	orr.w r1, r1, #0x80000000       @ block comes from the allocator
.L0801354a:
	eor.w r2, r8, r7, asr #1
	str r1, [r0, #4]
	eor.w r1, r9, r2
	str r1, [r0, #0]
	ldr r1, [r0, #4]
	and.w r1, r1, #0xc0000000
	.inst.n 0x1c49                  @ adds r1, r1, #1
	bics.w r1, r1, #0x40000000
	str r1, [r0, #4]
	strh r6, [r0, #0xc]
	strh.w r8, [r0, #0xe]
	bpl.n .L08013576
	add.w r1, r0, #0x10
	str r1, [r0, #8]
.L08013572:
	pop.w {r3, r4, r5, r6, r7, r8, r9, r10, r11, pc}
.L08013576:
	ldr r1, [r4, #8]
	add.w r2, r1, #0x10
	add r1, r5
	str r2, [r0, #8]
	str r1, [r4, #8]                @ advance the pool pointer by the byte count
	b.n .L08013572
.L08013584:
	.word 0x20000568
.L08013588:
	.word 0x200004e4
.L0801358c:
	.word fn_0801a9fc
.L08013590:
	.word fn_0801c17c
