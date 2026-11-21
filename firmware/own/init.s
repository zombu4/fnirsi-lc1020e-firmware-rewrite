@ init.s - the copy handler of the initial RAM image in our build.
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ copy_init - region table handler of entry 0 (src/rodata_04.s d_08051510): copies the typed
@   initial RAM image d_08051530 (0x57C bytes) to 0x20000000. The same routine as the
@   bootloader's copy_init (bootloader/src/slot_10.s).
@   Called by __scatterload (0x0800784C) with r0 = source, r1 = destination, r2 = byte count
@   (a multiple of 4; 0x57C here), through blx to the table word with bit 0 set; its return
@   value is not used. Copies word by word; uses r0..r3 only (__scatterload keeps r4 / r5,
@   the table walk). It runs before any RAM is set up: no stack use, no FPU. copy_init_addr is
@   the even address the region table holds.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.section .text.own.init,"ax",%progbits
	.p2align 2

	.global copy_init_addr
copy_init_addr:
	.global copy_init
	.thumb_func
	.type copy_init, %function
copy_init:
	cbz	r2, 2f			@ nothing to copy
1:	ldr	r3, [r0], #4		@ next word of the image
	str	r3, [r1], #4		@ to RAM
	subs	r2, r2, #4
	bne	1b
2:	bx	lr
