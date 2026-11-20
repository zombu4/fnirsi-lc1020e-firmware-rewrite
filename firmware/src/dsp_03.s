@ dsp_03.s - signal processing functions 0x08006198..0x080070dc (table permutation, sine, complex magnitude, FFT passes, maximum search)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ fn_08006198 - exchanges 8-byte elements of an array, driven by a table of
@ halfword byte offsets.
@ Parameters: r0 = base address, r1 = count, r2 = table of halfwords;
@ no return value.
@ Returns at once when count + 1 < 2 (unsigned compare of r3 = count + 1 with 1).
@ Otherwise runs (count + 1) >> 2 passes. The table pointer starts at r2 + 2 and
@ advances by 8 bytes (4 halfwords) per pass. In each pass the four halfwords
@ t[-1], t[0], t[1], t[2] are byte offsets added to the base r0:
@   the 8-byte elements (two words each) at t[1] and t[2] are exchanged,
@   then the elements at t[-1] and t[0] are exchanged.
@ Registers r4..r9 are saved and restored.
@ ----------------------------------------------------------------------------
	.section .text.fn_08006198,"ax",%progbits
	.global fn_08006198
	.thumb_func
	.type fn_08006198, %function
fn_08006198:
	adds r3, r1, #1                 @ r3 = count + 1
	cmp r3, #1
	it ls
	bxls lr                         @ count + 1 <= 1: nothing to do
	push.w {r4, r5, r6, r7, r8, r9}
	adds r1, r2, #2                 @ r1 = table + 2
	lsrs r3, r3, #2                 @ r3 = pass count
.L080061a8:
	ldrh.w r8, [r1, #4]            @ t[2]
	ldrh.w r9, [r1, #2]            @ t[1]
	ldrh r2, [r1]                  @ t[0]
	ldrh.w r12, [r1, #-2]          @ t[-1]
	add r8, r0                     @ element addresses = base + offset
	add r9, r0
	add r2, r0
	add r12, r0
	ldr.w r7, [r9]                 @ first words of the four elements
	ldr.w r6, [r8]
	ldr r5, [r2]
	ldr.w r4, [r12]
	str.w r6, [r9]                 @ exchange t[1] and t[2], then t[-1] and t[0]
	str.w r7, [r8]
	str.w r5, [r12]
	str r4, [r2]
	ldr.w r7, [r9, #4]             @ second words of the four elements
	ldr.w r6, [r8, #4]
	ldr r5, [r2, #4]
	ldr.w r4, [r12, #4]
	str.w r6, [r9, #4]
	str.w r7, [r8, #4]
	str.w r5, [r12, #4]
	str r4, [r2, #4]
	adds r1, #8                    @ next four table entries
	.inst.n 0x1e5b                 @ subs r3, r3, #1
	bne.n .L080061a8
	pop.w {r4, r5, r6, r7, r8, r9}
	bx lr

@ ----------------------------------------------------------------------------
@ fn_08006202 - exchanges 4-byte words of an array, driven by a table of
@ halfwords (each halfword shifted right by 1 is the byte offset).
@ Parameters: r0 = base address, r1 = count, r2 = table of halfwords;
@ no return value. Flagged unreached: nothing in the image refers to
@ 0x08006202.
@ Returns at once when count + 1 < 2. Otherwise runs (count + 1) >> 2 passes,
@ the table pointer starts at r2 + 2 and advances by 8 bytes per pass. Each of
@ t[-1], t[0], t[1], t[2] shifted right by 1 is a byte offset added to r0:
@   the words at t[1]>>1 and t[2]>>1 are exchanged,
@   then the words at t[-1]>>1 and t[0]>>1 are exchanged.
@ Registers r4..r9 are saved and restored.
@ ----------------------------------------------------------------------------
	.section .text.fn_08006202,"ax",%progbits
	.global fn_08006202
	.thumb_func
	.type fn_08006202, %function
fn_08006202:
	adds r3, r1, #1                 @ r3 = count + 1
	cmp r3, #1
	it ls
	bxls lr                         @ count + 1 <= 1: nothing to do
	push.w {r4, r5, r6, r7, r8, r9}
	adds r1, r2, #2                 @ r1 = table + 2
	lsrs r3, r3, #2                 @ r3 = pass count
.L08006212:
	ldrh.w r8, [r1, #4]            @ t[2]
	ldrh.w r9, [r1, #2]            @ t[1]
	ldrh r2, [r1]                  @ t[0]
	ldrh.w r12, [r1, #-2]          @ t[-1]
	add.w r8, r0, r8, lsr #1       @ word addresses = base + (offset >> 1)
	add.w r9, r0, r9, lsr #1
	add.w r2, r0, r2, lsr #1
	add.w r12, r0, r12, lsr #1
	ldr.w r7, [r9]
	ldr.w r6, [r8]
	ldr r5, [r2]
	ldr.w r4, [r12]
	str.w r6, [r9]                 @ exchange t[1] and t[2], then t[-1] and t[0]
	str.w r7, [r8]
	str.w r5, [r12]
	str r4, [r2]
	adds r1, #8                    @ next four table entries
	.inst.n 0x1e5b                 @ subs r3, r3, #1
	bne.n .L08006212
	pop.w {r4, r5, r6, r7, r8, r9}
	bx lr

@ ----------------------------------------------------------------------------
@ sine_radians - table-interpolated sine of an angle in radians.
@ Parameter: s0 = angle in radians (float). Return: s0 = result (float).
@ t = angle * 0.15915494 (0x3E22F983, 1/(2*pi)); the integer part of t is taken
@ by truncation (vcvt.s32.f32) and decremented when the angle is negative
@ (compare of s0 with 0), then frac = (t - that integer) * 512.0 (0x44000000).
@ index = (unsigned int)frac & 0x1ff; f = frac - (float)index;
@ result = (1.0 - f) * T[index] + f * T[index + 1], where T is the float table
@ at 0x08050314 (literal at .L08006304; 512 entries plus the closing entry at
@ 0x08050B14; in the image T[0] = 0, T[128] = 1.0, T[256] = 0, T[384] = -1.0).
@ Uses r0 and r1 as scratch, s0..s3.
@ ----------------------------------------------------------------------------
	.section .text.sine_radians,"ax",%progbits
	.p2align 2
	.global sine_radians
	.thumb_func
	.type sine_radians, %function
sine_radians:
	vldr s1, .L080062fc            @ s1 = 0.15915494
	vcmpe.f32 s0, #0
	vmul.f32 s1, s0, s1            @ t = angle * 1/(2*pi)
	vcvt.s32.f32 s2, s1            @ truncated integer part
	vmov r0, s2
	vmrs apsr_nzcv, fpscr          @ flags of the compare with 0
	it cc
	.inst.n 0x1e40                 @ subcc r0, r0, #1 (angle < 0: round down)
	vmov s0, r0
	ldr r1, .L08006304             @ r1 = table T at 0x08050314
	vmov.f32 s3, #1.0
	vcvt.f32.s32 s0, s0
	vsub.f32 s0, s1, s0            @ t - floor(t)
	vldr s1, .L08006300            @ s1 = 512.0
	vmul.f32 s1, s0, s1            @ frac = (t - floor(t)) * 512
	vcvt.u32.f32 s0, s1
	vmov r0, s0
	ubfx r0, r0, #0, #9            @ index = (unsigned int)frac & 0x1ff
	vmov s0, r0
	add.w r0, r1, r0, lsl #2       @ r0 = &T[index]
	vcvt.f32.u32 s0, s0            @ (float)index
	vldr s2, [r0, #4]              @ T[index + 1]
	vsub.f32 s1, s1, s0            @ f = frac - index
	vldr s0, [r0]                  @ T[index]
	vsub.f32 s3, s3, s1            @ 1.0 - f
	vmul.f32 s0, s3, s0
	vmla.f32 s0, s1, s2            @ + f * T[index + 1]
	bx lr
.L080062fc:
	.word 0x3e22f983               @ 0.15915494 (1/(2*pi))
.L08006300:
	.word 0x44000000               @ 512.0
.L08006304:
	.word d_08050314               @ sine table (float)

@ ----------------------------------------------------------------------------
@ complex_magnitude_f32 - magnitude of an array of complex float pairs.
@ Parameters: r0 = source array of float pairs (re, im), r1 = destination
@ float array, r2 = number of pairs; no return value.
@ For each pair writes sqrt(re*re + im*im) to the destination when the sum is
@ greater than 0.0 (vcmpe with 0, vsqrt under condition gt), else writes
@ 0.0 (word at .L08006400, held in s0).
@ The main loop handles 4 pairs per pass (r2 >> 2 passes, counter in r12),
@ then the remaining r2 & 3 pairs are handled one at a time.
@ Uses r0..r3, r12, s0..s2.
@ ----------------------------------------------------------------------------
	.section .text.complex_magnitude_f32,"ax",%progbits
	.p2align 2
	.global complex_magnitude_f32
	.thumb_func
	.type complex_magnitude_f32, %function
complex_magnitude_f32:
	vldr s0, .L08006400            @ s0 = 0.0
	lsrs.w r12, r2, #2             @ r12 = number of groups of four pairs
	beq.n .L080063c2
	nop
.L08006314:
	vldr s1, [r0]                  @ pair 1: re, im
	vldr s2, [r0, #4]
	adds r3, r1, #4                @ r3 = next destination
	vmul.f32 s1, s1, s1
	adds r0, #8
	vmla.f32 s1, s2, s2            @ re*re + im*im
	vcmpe.f32 s1, #0
	vmrs apsr_nzcv, fpscr
	itte gt
	vsqrtgt.f32 s2, s1
	vstrgt s2, [r1]
	vstrle s0, [r1]
	vldr s1, [r0]                  @ pair 2
	vldr s2, [r0, #4]
	adds r1, r3, #4
	vmul.f32 s1, s1, s1
	adds r0, #8
	vmla.f32 s1, s2, s2
	vcmpe.f32 s1, #0
	vmrs apsr_nzcv, fpscr
	itte gt
	vsqrtgt.f32 s2, s1
	vstrgt s2, [r3]
	vstrle s0, [r3]
	vldr s1, [r0]                  @ pair 3
	vldr s2, [r0, #4]
	adds r3, r1, #4
	vmul.f32 s1, s1, s1
	adds r0, #8
	vmla.f32 s1, s2, s2
	vcmpe.f32 s1, #0
	vmrs apsr_nzcv, fpscr
	itte gt
	vsqrtgt.f32 s2, s1
	vstrgt s2, [r1]
	vstrle s0, [r1]
	vldr s2, [r0]                  @ pair 4
	vldr s1, [r0, #4]
	adds r1, r3, #4
	vmul.f32 s2, s2, s2
	adds r0, #8
	vmla.f32 s2, s1, s1
	vcmpe.f32 s2, #0
	vmrs apsr_nzcv, fpscr
	itte gt
	vsqrtgt.f32 s1, s2
	vstrgt s1, [r3]
	vstrle s0, [r3]
	subs.w r12, r12, #1
	bne.n .L08006314
.L080063c2:
	ands.w r2, r2, #3              @ remaining pairs
	it eq
	bxeq lr
	nop
.L080063cc:
	vldr s1, [r0]                  @ one pair: re, im
	vldr s2, [r0, #4]
	mov r3, r1                     @ r3 = this destination
	vmul.f32 s1, s1, s1
	.inst.n 0x1d09                 @ adds r1, r1, #4
	adds r0, #8
	vmla.f32 s1, s2, s2
	vcmpe.f32 s1, #0
	vmrs apsr_nzcv, fpscr
	itte gt
	vsqrtgt.f32 s2, s1
	vstrgt s2, [r3]
	vstrle s0, [r3]
	.inst.n 0x1e52                 @ subs r2, r2, #1
	bne.n .L080063cc
	bx lr
	.short 0x0000                  @ padding
.L08006400:
	.word 0x00000000               @ 0.0

@ ----------------------------------------------------------------------------
@ fn_08006404 - first radix-4 style butterfly pass over a complex float array,
@ then two calls of fn_08006c00 for the two halves.
@ Parameters: r0 = pointer to a descriptor (halfword at +0 = length n, word at
@ +4 = twiddle table pointer), r1 = float data array (complex, interleaved);
@ no return value.
@ Four sections start at r1, r1 + (n/2) floats, r1 + n floats and
@ r1 + 3n/2 floats (r1, r0, r4, r2 at 0x0800642c). The loop runs n/2 >> 2
@ passes (lsrs at 0x08006424); each pass handles 4 floats (2 complex values)
@ of every section and advances every section pointer by 16 bytes. Sums of the
@ section values go back to the first and third section; the differences
@ multiplied by twiddle pairs (4 floats read from the table in r3 per pass,
@ table pointer advanced by 16 bytes at 0x08006554) go to the second and
@ fourth section.
@ Afterwards fn_08006c00 is called twice with (data, n/2, twiddle pointer, 2),
@ once for the first half (bl at 0x0800657a) and once for the second half
@ (tail call b.w at 0x0800658e, r0 = data + n floats).
@ Registers r4..r8 and d8 are saved and restored.
@ ----------------------------------------------------------------------------
	.section .text.fn_08006404,"ax",%progbits
	.global fn_08006404
	.thumb_func
	.type fn_08006404, %function
fn_08006404:
	push.w {r4, r5, r6, r7, r8, lr}
	mov r6, r0                     @ r6 = descriptor
	vpush {d8}
	mov r12, r1                    @ r12 = data array
	ldrh r0, [r0]                  @ r0 = n
	ldr r3, [r6, #4]               @ r3 = twiddle table
	add.w r4, r1, r0, lsl #2       @ r4 = data + n floats
	lsrs r5, r0, #1                @ r5 = n / 2
	mov r7, r4                     @ r7 = data + n floats (second half)
	add.w r0, r1, r5, lsl #2       @ r0 = data + n/2 floats
	add.w r2, r4, r5, lsl #2       @ r2 = data + 3n/2 floats
	lsrs.w r8, r5, #2              @ r8 = pass count
	beq.n .L08006526
	nop
.L0800642c:
	vldr s7, [r1]
	vldr s3, [r4]
	vldr s4, [r1, #4]
	vldr s6, [r4, #4]
	vadd.f32 s13, s7, s3
	vldr s8, [r1, #8]
	vldr s2, [r1, #0xc]
	vldr s5, [r4, #8]
	vldr s11, [r4, #0xc]
	vldr s16, [r0]
	vldr s14, [r0, #4]
	vldr s0, [r0, #8]
	vldr s12, [r0, #0xc]
	vldr s10, [r2]
	vldr s9, [r2, #4]
	vldr s15, [r2, #8]
	vldr s1, [r2, #0xc]
	vstr s13, [r1]
	vadd.f32 s13, s4, s6
	vsub.f32 s7, s7, s3
	vsub.f32 s3, s9, s14
	vstr s13, [r1, #4]
	vadd.f32 s13, s8, s5
	vsub.f32 s5, s8, s5
	vsub.f32 s8, s15, s0
	vstr s13, [r1, #8]
	vadd.f32 s13, s2, s11
	vstr s13, [r1, #0xc]
	vsub.f32 s13, s4, s6
	vsub.f32 s4, s2, s11
	vadd.f32 s2, s16, s10
	vsub.f32 s6, s10, s16
	vstr s2, [r0]
	vadd.f32 s2, s14, s9
	vstr s2, [r0, #4]
	vadd.f32 s2, s0, s15
	vstr s2, [r0, #8]
	vadd.f32 s2, s12, s1
	vstr s2, [r0, #0xc]
	vsub.f32 s2, s1, s12
	vldr s0, [r3]                  @ twiddle pair 1: re, im
	vldr s1, [r3, #4]
	vmul.f32 s9, s7, s0
	vmul.f32 s10, s13, s1
	vmul.f32 s11, s13, s0
	vmul.f32 s7, s7, s1
	vadd.f32 s9, s9, s10
	vsub.f32 s7, s11, s7
	vstr s9, [r4]
	vmul.f32 s9, s6, s1
	vstr s7, [r4, #4]
	vmul.f32 s7, s3, s0
	vmul.f32 s1, s3, s1
	vmul.f32 s0, s6, s0
	vsub.f32 s3, s9, s7
	vadd.f32 s0, s1, s0
	vstr s3, [r2]
	vstr s0, [r2, #4]
	vldr s0, [r3, #8]              @ twiddle pair 2: re, im
	vldr s1, [r3, #0xc]
	vmul.f32 s7, s5, s0
	vmul.f32 s6, s4, s1
	b.n .L08006528
.L08006526:
	b.n .L08006572                 @ pass count is zero: skip the loop
.L08006528:
	vmul.f32 s3, s5, s1
	vmul.f32 s4, s4, s0
	vadd.f32 s5, s7, s6
	adds r0, #0x10
	adds r1, #0x10
	vsub.f32 s3, s4, s3
	vstr s5, [r4, #8]
	vmul.f32 s4, s8, s1
	vstr s3, [r4, #0xc]
	vmul.f32 s3, s2, s0
	vmul.f32 s1, s2, s1
	vmul.f32 s0, s8, s0
	adds r3, #0x10
	vsub.f32 s2, s4, s3
	adds r4, #0x10
	vadd.f32 s0, s1, s0
	vstr s2, [r2, #8]
	vstr s0, [r2, #0xc]
	adds r2, #0x10
	subs.w r8, r8, #1
	bne.w .L0800642c
.L08006572:
	mov r1, r5                     @ length n/2
	movs r3, #2
	mov r0, r12                    @ first half of the data
	ldr r2, [r6, #4]               @ twiddle table
	bl fn_08006c00
	ldr r2, [r6, #4]
	mov r1, r5
	vpop {d8}
	mov r0, r7                     @ second half of the data
	pop.w {r4, r5, r6, r7, r8, lr}
	movs r3, #2
	b.w fn_08006c00                @ tail call

@ ----------------------------------------------------------------------------
@ fn_08006592 - second butterfly pass over a complex float array (four
@ quarters, forward and backward walking pointers), then four calls of
@ fn_08006c00, one per quarter.
@ Parameters: r0 = pointer to a descriptor (halfword at +0 = length n, word at
@ +4 = twiddle table pointer; the descriptor pointer is kept at [sp, #0x2c]),
@ r1 = float data array (complex, interleaved); no return value.
@ Frame: push of r0, r1, r4..r11, lr, vpush of d8/d9 and sub sp, #0x1c.
@ Stored at [sp]: quarter 4 start, quarter 3 start, quarter 2 start, data
@ start (strd at 0x080065ae and 0x080065be); [sp, #0x10] = n >> 2 (r9 =
@ (n >> 1) >> 1); [sp, #0x14] = 4.
@ Four quarters of n >> 1 floats each start at r1, r1 + (n>>1)*4,
@ r1 + (n>>1)*8 and r1 + (n>>1)*12 bytes (pointers r1, r0, r6, r5).
@ First the four-point sums and differences of element 0 of the four quarters
@ (0x080065d0..0x08006676).
@ Then a loop of (([sp, #0x10] - 2) >> 1) passes (count computed at
@ 0x08006686..0x0800668a, loop 0x08006694..0x0800689a): each pass handles one complex element walking
@ forwards from the quarter starts (pointers r1, r0, r5, r6, +8 bytes per pass)
@ and one walking backwards (pointers r4, r12, r2, r3, -8 bytes per pass), with
@ three twiddle table pointers (r10, r11, r8) advanced by 2, 4 and 6 floats per
@ pass (add 8 bytes at 0x08006814, add lr << 2 with lr = 4 at 0x08006808, add
@ r7 << 2 with r7 = 6 at 0x0800684a).
@ Then one more element at the forward pointers (0x080068a0..0x08006996).
@ Then fn_08006c00 is called four times (one per quarter, length [sp, #0x10],
@ twiddle pointer from the descriptor, fourth argument 4); the last call is a
@ tail call (b.w at 0x080069d8).
@ ----------------------------------------------------------------------------
	.section .text.fn_08006592,"ax",%progbits
	.global fn_08006592
	.thumb_func
	.type fn_08006592, %function
fn_08006592:
	push.w {r0, r1, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	vpush {d8, d9}
	sub sp, #0x1c
	ldr r0, [sp, #0x2c]            @ r0 = descriptor
	ldrh r0, [r0]                  @ r0 = n
	lsrs r7, r0, #1                @ r7 = n >> 1
	add.w r0, r1, r7, lsl #2       @ quarter 2 start
	add.w r6, r0, r7, lsl #2       @ quarter 3 start
	add.w r5, r6, r7, lsl #2       @ quarter 4 start
	strd r5, r6, [sp]
	ldr.w r8, [sp, #0x2c]
	sub.w r12, r5, #4              @ backward pointer, quarter 4
	add.w r3, r12, r7, lsl #2
	strd r0, r1, [sp, #8]
	lsr.w r9, r7, #1
	ldr.w r8, [r8, #4]             @ r8 = twiddle table
	movs r7, #4
	strd r9, r7, [sp, #0x10]
	vldr s1, [r1]
	vldr s0, [r6]
	vldr s2, [r0, #4]
	vldr s6, [r5, #4]
	vadd.f32 s5, s1, s0
	vsub.f32 s7, s1, s0
	vldr s1, [r1, #4]
	vldr s0, [r6, #4]
	subs r4, r0, #4
	subs r2, r6, #4
	vadd.f32 s4, s1, s0
	vsub.f32 s3, s1, s0
	vadd.f32 s0, s2, s7
	vldr s1, [r0]
	vsub.f32 s10, s4, s2
	vsub.f32 s2, s7, s2
	vsub.f32 s8, s0, s6
	vsub.f32 s9, s3, s1
	vldr s0, [r5]
	vadd.f32 s3, s1, s3
	vsub.f32 s10, s10, s6
	vadd.f32 s11, s9, s0
	vsub.f32 s9, s5, s1
	vadd.f32 s1, s1, s5
	vsub.f32 s3, s3, s0
	vadd.f32 s2, s2, s6
	vsub.f32 s9, s9, s0
	vadd.f32 s0, s1, s0
	movs r7, #6
	add.w r10, r8, #8
	vstr s0, [r1]
	vldr s0, [r0, #4]
	vldr s1, [r5, #4]
	add.w r11, r8, #0x10
	vadd.f32 s0, s0, s4
	add.w r8, r8, #0x18
	vadd.f32 s0, s0, s1
	vstr s0, [r1, #4]
	vstr s8, [r0]
	vstr s11, [r0, #4]
	vstr s9, [r6]
	vstr s10, [r6, #4]
	vstr s2, [r5]
	vstr s3, [r5, #4]
	ldr.w r9, [sp, #0x10]
	adds r0, #8
	adds r1, #8
	adds r5, #8
	adds r6, #8
	sub.w r9, r9, #2
	lsrs.w r9, r9, #1              @ r9 = pass count
	beq.w .L080068a0
	nop
.L08006694:
	vldr s1, [r1]
	vldr s0, [r6]
	vldr s3, [r0, #4]
	vldr s9, [r5, #4]
	vadd.f32 s4, s1, s0
	vsub.f32 s10, s1, s0
	vldr s1, [r1, #4]
	vldr s0, [r6, #4]
	vadd.f32 s5, s1, s0
	vsub.f32 s2, s1, s0
	vadd.f32 s0, s3, s10
	vldr s1, [r5]
	vsub.f32 s8, s0, s9
	vldr s0, [r0]
	vsub.f32 s6, s2, s0
	vadd.f32 s2, s0, s2
	vadd.f32 s11, s6, s1
	vsub.f32 s6, s4, s0
	vadd.f32 s0, s0, s4
	vsub.f32 s2, s2, s1
	vsub.f32 s7, s6, s1
	vadd.f32 s0, s0, s1
	vsub.f32 s6, s5, s3
	vsub.f32 s3, s10, s3
	vstr s0, [r1]
	vldr s0, [r0, #4]
	vldr s1, [r5, #4]
	vsub.f32 s6, s6, s9
	vadd.f32 s0, s0, s5
	vadd.f32 s3, s3, s9
	vadd.f32 s0, s0, s1
	vstr s0, [r1, #4]
	vldr s5, [r4]                  @ backward walking pointers
	vldr s9, [r12]
	vldr s1, [r4, #-4]
	vldr s0, [r12, #-4]
	vadd.f32 s14, s5, s9
	vsub.f32 s18, s5, s9
	vsub.f32 s5, s5, s9
	vldr s17, [r2, #-4]
	vadd.f32 s15, s1, s0
	vsub.f32 s4, s1, s0
	vsub.f32 s5, s5, s17
	vldr s1, [r2]
	vldr s0, [r3]
	vldr s16, [r3, #-4]
	vsub.f32 s10, s1, s0
	vadd.f32 s13, s5, s16
	vsub.f32 s5, s15, s17
	vadd.f32 s12, s10, s4
	vsub.f32 s10, s5, s16
	vsub.f32 s5, s14, s1
	vsub.f32 s9, s5, s0
	vsub.f32 s5, s1, s0
	vadd.f32 s1, s1, s14
	vsub.f32 s5, s5, s4
	vadd.f32 s0, s1, s0
	vsub.f32 s4, s16, s17
	vstr s0, [r4]
	vldr s0, [r2, #-4]
	vldr s1, [r3, #-4]
	vsub.f32 s4, s4, s18
	vadd.f32 s0, s0, s15
	vadd.f32 s0, s0, s1
	vstr s0, [r4, #-4]
	vldr s0, [r10]                 @ twiddle pair for the second quarter
	vldr s1, [r10, #4]
	vmul.f32 s15, s8, s0
	vmul.f32 s14, s11, s1
	vmul.f32 s11, s11, s0
	vmul.f32 s8, s8, s1
	vadd.f32 s14, s15, s14
	vsub.f32 s8, s11, s8
	vstr s14, [r0]
	vstr s8, [r0, #4]
	vmul.f32 s8, s13, s1
	vmul.f32 s11, s12, s0
	vmul.f32 s1, s12, s1
	vmul.f32 s0, s13, s0
	adds r0, #8
	vsub.f32 s8, s8, s11
	adds r1, #8
	vadd.f32 s0, s1, s0
	vstr s8, [r2]
	subs r4, #8
	vstr s0, [r2, #-4]
	vldr s0, [r11]                 @ twiddle pair for the third quarter
	vldr s1, [r11, #4]
	ldr.w lr, [sp, #0x14]          @ lr = 4
	vmul.f32 s8, s7, s0
	vmul.f32 s11, s6, s1
	vmul.f32 s6, s6, s0
	vmul.f32 s7, s7, s1
	subs r2, #8
	vadd.f32 s8, s8, s11
	add.w r11, r11, lr, lsl #2
	vsub.f32 s6, s6, s7
	vstr s8, [r6]
	add.w r10, r10, #8
	vstr s6, [r6, #4]
	vneg.f32 s6, s9
	adds r6, #8
	vmul.f32 s7, s6, s0
	vmul.f32 s6, s10, s1
	vmul.f32 s0, s10, s0
	vmul.f32 s1, s9, s1
	vsub.f32 s6, s7, s6
	vsub.f32 s0, s1, s0
	vstr s6, [r12]
	vstr s0, [r12, #-4]
	vldr s0, [r8]                  @ twiddle pair for the fourth quarter
	vldr s1, [r8, #4]
	add.w r8, r8, r7, lsl #2       @ r7 = 6
	vmul.f32 s7, s3, s0
	vmul.f32 s6, s2, s1
	vmul.f32 s2, s2, s0
	vmul.f32 s3, s3, s1
	sub.w r12, r12, #8
	vadd.f32 s6, s7, s6
	vsub.f32 s2, s2, s3
	vstr s6, [r5]
	vmul.f32 s3, s5, s0
	vstr s2, [r5, #4]
	vmul.f32 s2, s4, s1
	vmul.f32 s1, s5, s1
	vmul.f32 s0, s4, s0
	adds r5, #8
	vsub.f32 s2, s2, s3
	vadd.f32 s0, s1, s0
	vstr s2, [r3]
	vstr s0, [r3, #-4]
	subs r3, #8
	subs.w r9, r9, #1
	bne.w .L08006694
	nop
.L080068a0:
	vldr s1, [r1]                  @ last element at the forward pointers
	vldr s0, [r6]
	vldr s2, [r1, #4]
	vldr s11, [r0, #4]
	vadd.f32 s4, s1, s0
	vsub.f32 s1, s1, s0
	vldr s0, [r6, #4]
	vldr s10, [r5, #4]
	movs r3, #4
	vadd.f32 s3, s2, s0
	vsub.f32 s9, s2, s0
	vadd.f32 s0, s11, s1
	vldr s2, [r0]
	vsub.f32 s8, s3, s11
	vsub.f32 s1, s1, s11
	vsub.f32 s6, s0, s10
	vldr s0, [r5]
	vsub.f32 s8, s8, s10
	vadd.f32 s10, s1, s10
	vsub.f32 s5, s9, s2
	vsub.f32 s7, s4, s2
	vadd.f32 s1, s2, s9
	vadd.f32 s2, s2, s4
	vadd.f32 s5, s5, s0
	vsub.f32 s7, s7, s0
	vsub.f32 s1, s1, s0
	vadd.f32 s0, s2, s0
	vstr s0, [r1]
	vldr s0, [r0, #4]
	vldr s2, [r5, #4]
	vadd.f32 s0, s0, s3
	vadd.f32 s0, s0, s2
	vstr s0, [r1, #4]
	vldr s0, [r10]
	vldr s2, [r10, #4]
	vmul.f32 s3, s6, s0
	vmul.f32 s4, s5, s2
	vmul.f32 s0, s5, s0
	vmul.f32 s2, s6, s2
	vadd.f32 s3, s3, s4
	vsub.f32 s0, s0, s2
	vstr s3, [r0]
	vstr s0, [r0, #4]
	vldr s0, [r11]
	vldr s2, [r11, #4]
	vmul.f32 s3, s7, s0
	vmul.f32 s4, s8, s2
	vmul.f32 s0, s8, s0
	vmul.f32 s2, s7, s2
	vadd.f32 s3, s3, s4
	vsub.f32 s0, s0, s2
	vstr s3, [r6]
	vstr s0, [r6, #4]
	vldr s0, [r8, #4]
	vldr s2, [r8]
	vmul.f32 s3, s1, s0
	vmul.f32 s4, s10, s2
	vmul.f32 s1, s1, s2
	vmul.f32 s0, s10, s0
	vadd.f32 s2, s4, s3
	vsub.f32 s0, s1, s0
	vstr s2, [r5]
	vstr s0, [r5, #4]
	ldr r0, [sp, #0x2c]            @ call 1: data start ([sp, #0xc]), length [sp, #0x10]
	ldr r2, [r0, #4]
	ldrd r0, r1, [sp, #0xc]
	bl fn_08006c00
	ldr r0, [sp, #0x2c]            @ call 2: quarter at [sp, #8]
	movs r3, #4
	ldr r1, [sp, #0x10]
	ldr r2, [r0, #4]
	ldr r0, [sp, #8]
	bl fn_08006c00
	ldr r0, [sp, #0x2c]            @ call 3: quarter at [sp, #4]
	movs r3, #4
	ldr r1, [sp, #0x10]
	ldr r2, [r0, #4]
	ldr r0, [sp, #4]
	bl fn_08006c00
	ldr r0, [sp, #0x2c]            @ call 4: quarter at [sp]
	ldr r1, [sp, #0x10]
	movs r3, #4
	ldr r2, [r0, #4]
	ldr r0, [sp]
	add sp, #0x1c
	vpop {d8, d9}
	add sp, #8
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, lr}
	b.w fn_08006c00                @ tail call

@ ----------------------------------------------------------------------------
@ fn_080069dc - transform driver for a complex float array of 16..4096 points.
@ Parameters: r0 = pointer to a descriptor (halfword at +0 = length n, word at
@ +4 = twiddle table, word at +8 = bit-reverse table, halfword at +12 =
@ bit-reverse count), r1 = float data array (complex, interleaved),
@ r2 = direction flag (1 = negate the imaginary parts before and after and
@ scale by 1/n), r3 = apply-bit-reverse flag; no return value.
@ Steps:
@   - if r2 == 1, negates every imaginary float of the n complex values;
@   - dispatches on n: 0x10, 0x80, 0x400 call fn_08006404(descriptor, data);
@     0x20, 0x100, 0x800 call fn_08006592(descriptor, data); 0x40, 0x200,
@     0x1000 call fn_08006c00(data, n, twiddle table, 1); any other value
@     calls nothing;
@   - if r3 != 0 calls fn_08006198(data, halfword at +12, table at +8);
@   - if r2 != 1 returns; otherwise multiplies every real part by 1/n
@     (1.0 / (float)n, computed with vdiv) and every imaginary part by -1/n
@     (negate, then multiply); returns early when n == 0.
@ Saved registers r4..r8, lr; r4 = n, r5 = data, r6 = descriptor, r7 = r2,
@ r8 = r3.
@ ----------------------------------------------------------------------------
	.section .text.fn_080069dc,"ax",%progbits
	.p2align 2
	.global fn_080069dc
	.thumb_func
	.type fn_080069dc, %function
fn_080069dc:
	push.w {r4, r5, r6, r7, r8, lr}
	ldrh r4, [r0]                  @ r4 = n
	mov r8, r3
	mov r7, r2
	mov r5, r1
	mov r6, r0
	cmp r2, #1
	bne.n .L08006a30
	adds r0, r5, #4                @ r0 = &imaginary part of element 0
	cbz r4, .L08006a30
	sub.w r1, r0, #8
	tst.w r4, #1
	beq.n .L08006a0a
	vldr s0, [r1, #8]              @ odd n: negate the first imaginary part
	vneg.f32 s0, s0
	vstr s0, [r1, #8]
	adds r1, #8
.L08006a0a:
	lsrs.w r12, r4, #1             @ pairs of elements
	beq.n .L08006a30
.L08006a10:
	vldr s0, [r1, #8]              @ negate two imaginary parts per pass
	vneg.f32 s0, s0
	vstr s0, [r1, #8]
	vldr s0, [r1, #0x10]
	vneg.f32 s0, s0
	vstr s0, [r1, #0x10]
	adds r1, #0x10
	subs.w r12, r12, #1
	bne.n .L08006a10
.L08006a30:
	cmp.w r4, #0x100               @ dispatch on n
	beq.n .L08006a6e
	bgt.n .L08006a4a
	cmp r4, #0x10
	beq.n .L08006a64
	cmp r4, #0x20
	beq.n .L08006a6e
	cmp r4, #0x40
	beq.n .L08006a78
	cmp r4, #0x80
	beq.n .L08006a64
	b.n .L08006a84
.L08006a4a:
	cmp.w r4, #0x200
	beq.n .L08006a78
	cmp.w r4, #0x400
	beq.n .L08006a64
	cmp.w r4, #0x800
	beq.n .L08006a6e
	cmp.w r4, #0x1000
	beq.n .L08006a78
	b.n .L08006a84
.L08006a64:
	mov r1, r5                     @ n = 0x10, 0x80, 0x400
	mov r0, r6
	bl fn_08006404
	b.n .L08006a84
.L08006a6e:
	mov r1, r5                     @ n = 0x20, 0x100, 0x800
	mov r0, r6
	bl fn_08006592
	b.n .L08006a84
.L08006a78:
	mov r1, r4                     @ n = 0x40, 0x200, 0x1000
	movs r3, #1
	mov r0, r5
	ldr r2, [r6, #4]               @ twiddle table
	bl fn_08006c00
.L08006a84:
	cmp.w r8, #0
	beq.n .L08006a94
	ldrh r1, [r6, #0xc]            @ bit-reverse count
	mov r0, r5
	ldr r2, [r6, #8]               @ bit-reverse table
	bl fn_08006198
.L08006a94:
	cmp r7, #1
	it ne
	popne.w {r4, r5, r6, r7, r8, pc}
	vmov s0, r4
	vmov.f32 s2, #1.0
	cmp r4, #0
	vcvt.f32.u32 s1, s0            @ (float)n
	vdiv.f32 s0, s2, s1            @ s0 = 1.0 / n
	it eq
	popeq.w {r4, r5, r6, r7, r8, pc}
	sub.w r0, r5, #8
	tst.w r4, #1
	beq.n .L08006adc
	vldr s1, [r0, #8]              @ odd n: scale the first element
	vmul.f32 s1, s1, s0            @ real part * (1/n)
	vstr s1, [r0, #8]
	vldr s1, [r0, #0xc]
	vneg.f32 s1, s1
	vmul.f32 s1, s1, s0            @ imaginary part * (-1/n)
	vstr s1, [r0, #0xc]
	adds r0, #8
.L08006adc:
	lsrs r1, r4, #1                @ pairs of elements
	it eq
	popeq.w {r4, r5, r6, r7, r8, pc}
.L08006ae4:
	vldr s1, [r0, #8]              @ two elements per pass
	vmul.f32 s1, s1, s0
	vstr s1, [r0, #8]
	vldr s1, [r0, #0xc]
	vneg.f32 s1, s1
	vmul.f32 s1, s1, s0
	vstr s1, [r0, #0xc]
	vldr s1, [r0, #0x10]
	vmul.f32 s1, s1, s0
	vstr s1, [r0, #0x10]
	vldr s1, [r0, #0x14]
	vneg.f32 s1, s1
	vmul.f32 s1, s1, s0
	vstr s1, [r0, #0x14]
	adds r0, #0x10
	.inst.n 0x1e49                 @ subs r1, r1, #1
	bne.n .L08006ae4
	pop.w {r4, r5, r6, r7, r8, pc}
	.short 0x0000                  @ padding

@ ----------------------------------------------------------------------------
@ float_array_max_with_index - maximum of a float array and its index.
@ Parameters: r0 = float array, r1 = element count, r2 = pointer receiving the
@ maximum (float), r3 = pointer receiving its index (int); no return value.
@ Starts with element 0 as the maximum (s0, loaded by vldmia) and index 0
@ (r4), scans the elements 1..count-1 (4 per pass with the counter r5 =
@ (count - 1) >> 2 and the running index base r12, then the remaining
@ (count - 1) & 3 elements) and replaces maximum and index only when an
@ element is strictly greater. Stores the maximum to *r2 and the index to *r3.
@ Registers r4..r6 are saved and restored.
@ ----------------------------------------------------------------------------
	.section .text.float_array_max_with_index,"ax",%progbits
	.p2align 2
	.global float_array_max_with_index
	.thumb_func
	.type float_array_max_with_index, %function
float_array_max_with_index:
	push {r4, r5, r6}
	mov.w r12, #0                  @ r12 = index of the next group of four - 1
	vldmia r0!, {s0}               @ s0 = element 0 = maximum so far
	subs r6, r1, #1                @ r6 = count - 1
	mov r4, r12                    @ r4 = index of the maximum
	lsrs r5, r6, #2                @ r5 = groups of four
	beq.n .L08006b9e
	nop
.L08006b3c:
	vldr s1, [r0]                  @ elements 1 and 2 of the group
	vldr s2, [r0, #4]
	adds r0, #8
	vcmpe.f32 s0, s1
	vmrs apsr_nzcv, fpscr
	itt cc
	vmovcc.f32 s0, s1
	addcc.w r4, r12, #1
	vldmia r0!, {s1}               @ element 3
	vcmpe.f32 s0, s2
	vmrs apsr_nzcv, fpscr
	itt cc
	vmovcc.f32 s0, s2
	addcc.w r4, r12, #2
	vldmia r0!, {s2}               @ element 4
	vcmpe.f32 s0, s1
	vmrs apsr_nzcv, fpscr
	itt cc
	vmovcc.f32 s0, s1
	addcc.w r4, r12, #3
	vcmpe.f32 s0, s2
	vmrs apsr_nzcv, fpscr
	itt cc
	vmovcc.f32 s0, s2
	addcc.w r4, r12, #4
	.inst.n 0x1e6d                 @ subs r5, r5, #1
	add.w r12, r12, #4
	bne.n .L08006b3c
.L08006b9e:
	and.w r12, r6, #3              @ remaining elements
	movs.w r6, r12
	beq.n .L08006bd8
	cmp.w r6, #0x80000000
	bcs.n .L08006be2
	cmp r6, #0
	it gt
	movgt r5, #0
	ble.n .L08006bd8
	nop
.L08006bb8:
	vldr s1, [r0]
	vcmpe.f32 s1, s0
	vmrs apsr_nzcv, fpscr
	ble.n .L08006bd0
	adds r4, r1, r5                @ index = count + r5 - r12
	vmov.f32 s0, s1
	sub.w r4, r4, r12
.L08006bd0:
	.inst.n 0x1d00                 @ adds r0, r0, #4
	.inst.n 0x1c6d                 @ adds r5, r5, #1
	.inst.n 0x1e76                 @ subs r6, r6, #1
	bne.n .L08006bb8
.L08006bd8:
	vstr s0, [r2]                  @ *r2 = maximum
	str r4, [r3]                   @ *r3 = index
	pop {r4, r5, r6}
	bx lr
.L08006be2:
	vldmia r0!, {s1}               @ remainder count has the top bit set (unsigned)
	vcmpe.f32 s0, s1
	vmrs apsr_nzcv, fpscr
	itt cc
	vmovcc.f32 s0, s1
	subcc.w r4, r1, r12
	subs.w r12, r12, #1
	bne.n .L08006be2
	b.n .L08006bd8

@ ----------------------------------------------------------------------------
@ fn_08006c00 - multi-stage radix-8 butterfly passes over a complex float array.
@ Parameters: r0 = float data array (complex, 8 bytes per element), r1 = length
@ n, r2 = twiddle table pointer (8 bytes per entry: re, im), r3 = twiddle step
@ (read back from [sp, #0x54] after the push of r0..r11 and lr, the vpush of
@ d8..d15 and sub sp, #8); no return value.
@ Stage loop with section length L (first stage L = n, in r1/r4, next stages
@ L = s) and spacing s = L >> 3 (lsrs at 0x08006c12, kept in r3):
@   - First loop (0x08006c18..0x08006db8): for ip = 0, L, 2L, ... while ip < n
@     (r12 += r4, compare with r1), an 8-point butterfly on the eight elements
@     ip + m*s (m = 0..7) without twiddle factors: sums, differences and
@     products with 0.70710677 (word 0x3f3504f3 at .L08007004, loaded into
@     s30 by the first instruction).
@   - When s < 8 the function returns after this loop (cmp r3, #8 at
@     0x08006dbc, conditional epilogue).
@   - Otherwise the second loop (0x08006ddc..0x080070b6): for k = 1..s-1
@     ([sp] = k), the accumulator [sp, #4] += step selects seven twiddle
@     entries (re, im) at element indexes m*k*step, m = 1..7, and the same
@     8-point butterfly is applied to the elements k + ip + m*s for
@     ip = 0, L, 2L, ... while ip < n, multiplying seven outputs by the twiddle
@     entries.
@   - Then step = (step << 3) & 0xffff (0x080070ba..0x080070c6) and, when
@     s > 7 (cmp r3, #7 at 0x080070ca), the next stage runs with L = s
@     (b.w to 0x08006c10).
@ Registers r4..r11, lr and d8..d15 are saved and restored.
@ ----------------------------------------------------------------------------
	.section .text.fn_08006c00,"ax",%progbits
	.p2align 2
	.global fn_08006c00
	.thumb_func
	.type fn_08006c00, %function
fn_08006c00:
	push.w {r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}
	vpush {d8, d9, d10, d11, d12, d13, d14, d15}
	sub sp, #8
	vldr s30, .L08007004           @ s30 = 0.70710677
	mov r3, r1
.L08006c10:
	mov r4, r3                     @ r4 = L (section length)
	lsrs r3, r3, #3                @ r3 = s = L >> 3
	mov.w r12, #0                  @ ip = 0
.L08006c18:
	add.w r5, r12, r3
	add.w r8, r5, r3
	add.w r9, r8, r3
	add.w r6, r9, r3
	add.w r10, r6, r3
	add.w r7, r0, r12, lsl #3
	add.w r6, r0, r6, lsl #3
	vldr s2, [r7]
	vldr s1, [r6]
	add.w r11, r10, r3
	add.w r5, r0, r5, lsl #3
	add.w r10, r0, r10, lsl #3
	vadd.f32 s0, s2, s1
	vsub.f32 s3, s2, s1
	vldr s4, [r5]
	vldr s1, [r10]
	add.w lr, r11, r3
	add.w r8, r0, r8, lsl #3
	vadd.f32 s2, s4, s1
	add.w r11, r0, r11, lsl #3
	vsub.f32 s4, s4, s1
	vldr s5, [r8]
	vldr s1, [r11]
	add.w r9, r0, r9, lsl #3
	add.w lr, r0, lr, lsl #3
	vldr s6, [r9]
	vldr s8, [lr]
	vadd.f32 s7, s5, s1
	vsub.f32 s5, s5, s1
	vadd.f32 s1, s6, s8
	vsub.f32 s6, s6, s8
	vsub.f32 s13, s0, s7
	vadd.f32 s7, s0, s7
	vsub.f32 s0, s2, s1
	vadd.f32 s1, s2, s1
	vadd.f32 s2, s7, s1
	vsub.f32 s1, s7, s1
	vstr s2, [r7]
	vstr s1, [r6]
	vldr s2, [r7, #4]
	vldr s1, [r6, #4]
	vldr s7, [r5, #4]
	vldr s8, [r8, #4]
	vadd.f32 s12, s2, s1
	vsub.f32 s1, s2, s1
	vldr s2, [r10, #4]
	vldr s10, [r9, #4]
	vadd.f32 s9, s7, s2
	vsub.f32 s7, s7, s2
	vldr s2, [r11, #4]
	vadd.f32 s14, s8, s2
	vsub.f32 s2, s8, s2
	vldr s8, [lr, #4]
	vadd.f32 s11, s10, s8
	vsub.f32 s8, s10, s8
	vsub.f32 s10, s12, s14
	vadd.f32 s12, s12, s14
	vsub.f32 s14, s9, s11
	vadd.f32 s9, s9, s11
	vadd.f32 s11, s12, s9
	vsub.f32 s9, s12, s9
	vstr s11, [r7, #4]
	vstr s9, [r6, #4]
	vadd.f32 s9, s13, s14
	vstr s9, [r8]
	vsub.f32 s9, s13, s14
	vstr s9, [r11]
	vsub.f32 s9, s10, s0
	vadd.f32 s0, s10, s0
	vstr s9, [r8, #4]
	vstr s0, [r11, #4]
	vsub.f32 s0, s4, s6
	vadd.f32 s4, s4, s6
	vmul.f32 s0, s0, s30
	vmul.f32 s9, s4, s30
	vsub.f32 s4, s7, s8
	add r12, r4                    @ ip += L
	cmp r12, r1
	vmul.f32 s6, s4, s30
	vadd.f32 s4, s7, s8
	vsub.f32 s8, s1, s6
	vmul.f32 s7, s4, s30
	vadd.f32 s6, s1, s6
	vsub.f32 s4, s3, s0
	vadd.f32 s0, s3, s0
	vsub.f32 s1, s2, s7
	vadd.f32 s2, s2, s7
	vsub.f32 s3, s5, s9
	vadd.f32 s5, s5, s9
	vadd.f32 s7, s0, s2
	vsub.f32 s0, s0, s2
	vstr s7, [r5]
	vstr s0, [lr]
	vadd.f32 s0, s4, s1
	vstr s0, [r10]
	vsub.f32 s0, s4, s1
	vstr s0, [r9]
	vsub.f32 s0, s6, s5
	vstr s0, [r5, #4]
	vadd.f32 s0, s6, s5
	vstr s0, [lr, #4]
	vsub.f32 s0, s8, s3
	vstr s0, [r10, #4]
	vadd.f32 s0, s8, s3
	vstr s0, [r9, #4]
	bcc.w .L08006c18
	cmp r3, #8
	itttt cc
	addcc sp, #8
	vpopcc {d8, d9, d10, d11, d12, d13, d14, d15}
	addcc sp, #0x10
	popcc.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
	mov.w r12, #0
	str.w r12, [sp, #4]
	mov.w r12, #1
	str.w r12, [sp]
.L08006ddc:
	ldr.w r12, [sp, #4]
	ldr r5, [sp, #0x54]            @ twiddle step
	add r12, r5
	lsl.w r5, r12, #2
	add.w r7, r5, r12
	str.w r12, [sp, #4]
	add.w r9, r7, r12
	lsl.w r8, r12, #1
	add.w r6, r8, r12
	add.w r10, r9, r12
	add.w r12, r2, r12, lsl #3
	add.w r8, r2, r8, lsl #3
	add.w r6, r2, r6, lsl #3
	add.w r5, r2, r5, lsl #3
	add.w r7, r2, r7, lsl #3
	add.w r9, r2, r9, lsl #3
	add.w r10, r2, r10, lsl #3
	vldr s26, [r12]                @ seven twiddle entries (re, im)
	vldr s16, [r12, #4]
	vldr s25, [r8]
	vldr s24, [r6]
	vldr s23, [r5]
	vldr s22, [r7]
	vldr s21, [r9]
	vldr s17, [r10]
	vldr s15, [r8, #4]
	vldr s20, [r6, #4]
	vldr s14, [r5, #4]
	vldr s13, [r7, #4]
	vldr s12, [r9, #4]
	vldr s19, [r10, #4]
	ldr.w r12, [sp]                @ r12 = k
.L08006e58:
	add.w r7, r12, r3
	adds r5, r7, r3
	add.w r10, r5, r3
	add.w r8, r10, r3
	add.w r6, r8, r3
	add.w r11, r6, r3
	add.w r9, r0, r12, lsl #3
	add.w r8, r0, r8, lsl #3
	vldr s1, [r9]
	vldr s0, [r8]
	add.w r7, r0, r7, lsl #3
	add.w r6, r0, r6, lsl #3
	vldr s3, [r7]
	vldr s2, [r6]
	vadd.f32 s7, s1, s0
	add.w lr, r11, r3
	vsub.f32 s1, s1, s0
	vadd.f32 s0, s3, s2
	add.w r5, r0, r5, lsl #3
	add.w r11, r0, r11, lsl #3
	vsub.f32 s2, s3, s2
	vldr s3, [r5]
	vldr s4, [r11]
	add.w r10, r0, r10, lsl #3
	add.w lr, r0, lr, lsl #3
	vadd.f32 s8, s3, s4
	vsub.f32 s3, s3, s4
	vldr s4, [r10]
	vldr s5, [lr]
	vadd.f32 s6, s4, s5
	vsub.f32 s4, s4, s5
	vsub.f32 s5, s7, s8
	vadd.f32 s7, s7, s8
	vsub.f32 s10, s0, s6
	vadd.f32 s0, s0, s6
	vadd.f32 s6, s7, s0
	vsub.f32 s27, s7, s0
	vstr s6, [r9]
	vldr s0, [r9, #4]
	vldr s6, [r8, #4]
	vldr s7, [r7, #4]
	vldr s8, [r5, #4]
	vadd.f32 s29, s0, s6
	vsub.f32 s6, s0, s6
	vldr s0, [r6, #4]
	vldr s28, [r10, #4]
	vldr s9, [lr, #4]
	vadd.f32 s18, s7, s0
	vsub.f32 s7, s7, s0
	vldr s0, [r11, #4]
	vadd.f32 s11, s8, s0
	vsub.f32 s8, s8, s0
	vadd.f32 s0, s28, s9
	vsub.f32 s9, s28, s9
	vsub.f32 s28, s29, s11
	vadd.f32 s11, s29, s11
	vsub.f32 s29, s18, s0
	vadd.f32 s18, s18, s0
	vadd.f32 s0, s5, s29
	vsub.f32 s5, s5, s29
	vadd.f32 s29, s11, s18
	vsub.f32 s18, s11, s18
	vsub.f32 s11, s28, s10
	vstr s29, [r9, #4]
	vadd.f32 s10, s28, s10
	vmul.f32 s28, s23, s27
	vmul.f32 s29, s14, s18
	vmul.f32 s18, s23, s18
	vmul.f32 s27, s14, s27
	vadd.f32 s28, s28, s29
	vsub.f32 s18, s18, s27
	vstr s28, [r8]
	vmul.f32 s27, s15, s11
	vstr s18, [r8, #4]
	vmul.f32 s18, s25, s0
	vmul.f32 s11, s25, s11
	vmul.f32 s0, s15, s0
	vadd.f32 s18, s18, s27
	vsub.f32 s0, s11, s0
	vstr s18, [r5]
	vmul.f32 s11, s12, s10
	vstr s0, [r5, #4]
	vmul.f32 s0, s21, s5
	vmul.f32 s10, s21, s10
	vmul.f32 s5, s12, s5
	vadd.f32 s0, s0, s11
	vstr s0, [r11]
	vsub.f32 s0, s10, s5
	vadd.f32 s5, s7, s9
	vstr s0, [r11, #4]
	vsub.f32 s0, s2, s4
	vadd.f32 s2, s2, s4
	vsub.f32 s4, s7, s9
	vmul.f32 s7, s5, s30
	vmul.f32 s0, s0, s30
	vmul.f32 s2, s2, s30
	vmul.f32 s4, s4, s30
	vsub.f32 s5, s1, s0
	vadd.f32 s0, s1, s0
	vsub.f32 s1, s3, s2
	vadd.f32 s3, s3, s2
	vsub.f32 s2, s6, s4
	vadd.f32 s4, s6, s4
	vsub.f32 s6, s8, s7
	vadd.f32 s8, s8, s7
	vadd.f32 s7, s0, s8
	vsub.f32 s8, s0, s8
	b.n .L08007008
.L08007004:
	.word 0x3f3504f3               @ 0.70710677
.L08007008:
	vadd.f32 s9, s5, s6
	vsub.f32 s5, s5, s6
	vsub.f32 s6, s4, s3
	vadd.f32 s0, s4, s3
	vsub.f32 s3, s2, s1
	vadd.f32 s1, s2, s1
	vmul.f32 s4, s26, s7
	vmul.f32 s2, s16, s6
	vmul.f32 s6, s26, s6
	vmul.f32 s7, s16, s7
	add r12, r4
	vadd.f32 s2, s4, s2
	vmul.f32 s4, s17, s8
	cmp r12, r1
	vstr s2, [r7]
	vsub.f32 s2, s6, s7
	vmul.f32 s6, s19, s8
	vstr s2, [r7, #4]
	vmul.f32 s2, s19, s0
	vmul.f32 s0, s17, s0
	vadd.f32 s2, s4, s2
	vsub.f32 s0, s0, s6
	vmul.f32 s4, s13, s9
	vstr s2, [lr]
	vstr s0, [lr, #4]
	vmul.f32 s0, s22, s9
	vmul.f32 s2, s13, s3
	vmul.f32 s3, s22, s3
	vadd.f32 s0, s0, s2
	vmul.f32 s2, s24, s5
	vstr s0, [r6]
	vsub.f32 s0, s3, s4
	vmul.f32 s3, s20, s5
	vstr s0, [r6, #4]
	vmul.f32 s0, s20, s1
	vmul.f32 s1, s24, s1
	vadd.f32 s0, s2, s0
	vstr s0, [r10]
	vsub.f32 s0, s1, s3
	vstr s0, [r10, #4]
	bcc.w .L08006e58
	ldr.w r12, [sp]
	add.w r12, r12, #1
	str.w r12, [sp]
	cmp r3, r12
	bhi.w .L08006ddc
	ldr.w r12, [sp, #0x54]
	movw r4, #0xffff
	and.w r12, r4, r12, lsl #3
	str.w r12, [sp, #0x54]
	cmp r3, #7
	bhi.w .L08006c10
	add sp, #8
	vpop {d8, d9, d10, d11, d12, d13, d14, d15}
	add sp, #0x10
	pop.w {r4, r5, r6, r7, r8, r9, r10, r11, pc}
