@ screen.s - screenshot of our build: the screen sent band by band as stream frames over USB.
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ The panel has no read-back used by V1.1 and there is no frame buffer: the GUI draws into the draw buffer 0x20006700 (0xC80
@ pixels = 10 rows of 320) and hands each finished rectangle to the flush 0x08014F9C, which sets
@ the panel window (fn_08009e30 x1, y1, x2, y2) and writes the (x2 - x1 + 1) * (y2 - y1 + 1)
@ halfwords row by row to 0x60020000, then ends in b.w 0x0801DCC0 (clears words +0x10 and +0x14
@ of the draw buffer descriptor 0x200066E4: the "flushing" words read by 0x08015D28).
@ The screenshot therefore asks the GUI to redraw one band of 10 rows and copies the pixels of
@ every flush that falls into that band, exactly as the panel gets them, into stream frames.
@
@ How the GUI redraws a region (from the code):
@ - fn_080124d8 (gui_15.s) adds a rectangle to the redraw list of a display record: r0 = display
@   record (0 takes the default one, fn_0801dccc: word 0x20000478, which 0x0801DB6C sets to the
@   record it creates for the driver record 0x20008000), r1 = rectangle (x1, y1, x2, y2 signed
@   halfwords). It returns without effect while the use count word +0x154 is not above 0
@   (fn_0801ddb4) or bit 2 of byte +0x28 is set; r1 = 0 clears the list (halfword +0x150 = 0).
@   It clips the rectangle to {0, 0, width - 1, height - 1} (rect_intersect), stores it at
@   +0x30 + 8 * n unless a stored one already contains it (fn_08011e9c), takes the whole screen
@   when 0x20 entries are full, and clears word +0x14 of the refresh timer record (word +4,
@   record_clear_flag), which 0x08012188 set when it ran (record_set_flag): the timer runs again.
@   Its only direct caller is fn_08025446 (gui_23.s), the object path.
@ - The refresh timer 0x08012188 (period 0x1E, created by 0x0801DB6C with fn_080277c8) is run
@   by the timer walk fn_08027830, called by the main loop at 0x080281CC, before the bl at
@   0x080281D0 that ctl_loop replaces; so scr_step never runs inside a refresh. 0x08012188 merges
@   the list (fn_08026ab8), draws it (fn_08028e1c), then clears the list (0x100 bytes at +0x30,
@   0x20 at +0x130, halfword +0x150 = 0).
@ - The flush is reached through 0x08015D28 -> call_with_offset_rect, which adds the driver's
@   offsets (halfwords +8 / +0xA, 0 from fn_0801db1c) and calls word +0x14 of the driver record
@   with r0 = driver record, r1 = rectangle, r2 = pixels (kept in r2 by its push {r2..}).
@   Driver word +0x10: fn_0801db1c clears the record and sets bit 3, fn_080269f0 clears bits 4..5
@   and sets bit 2, so bits 0 and 1 are 0 and the rotation field (bits 4..5) is 0: the path of
@   0x08015D28 that calls call_with_offset_rect directly, no rotation copy. The rounder word +0x18
@   stays 0 from the clear. One draw buffer (fn_0801dafc second buffer 0).
@ - The flush pointer literal 0x08026A3C (gui_25.s) is the only place that names fn_08014f9c;
@   the hook (`.ifdef OWN`) puts own_flush there.
@
@ Capture of one band b (rows 10 b .. 10 b + 9):
@ 1. scr_step waits (one check per main-loop pass, no loop) until the TX ring has SCR_ROOM bytes
@    free, then calls fn_080124d8(0, {0, 10 b, 319, 10 b + 9}) and clears the row mask.
@ 2. own_flush, for every flush while the band is captured: clips the rectangle to the band's
@    rows; when something is left, sends it in frames of at most 240 pixels and, when the piece
@    spans the full width (x1 <= 0, x2 >= 319) and all its frames were queued, sets its rows in
@    the row mask. Then it runs the vendor flush with the same r0..r2. It never waits.
@ 3. scr_step: all 10 rows in the mask -> band done. No complete mask within SCR_T_REFRESH GUI
@    ticks -> the band is requested again (from step 1), at most SCR_TRIES times, then it ends
@    with SCR_RES_NOREFRESH. A frame that did not fit ends the band with SCR_RES_NOROOM at once.
@ 4. scr_step sends the band end frame (result byte), then goes to the next band or finishes.
@ DTR cleared, or the ring not drained within SCR_T_ROOM ticks: the capture stops (no end frame).
@ The USB reservation (usb_reserve 1) is on from scr_start until the capture ends.
@
@ Stream frames (type 3, cmd 0x60), payload little-endian:
@   pixel frame: band (u8), offset (u16), x1, y1, x2, y2 (u16 each, the clipped rectangle),
@                then (count) RGB565 halfwords as the panel gets them, count <= 240. offset = index
@                of the first of them in the rectangle, row-major with width x2 - x1 + 1.
@   band end:    band (u8), 0xFFFF, 0, 10 b, 319, 10 b + 9, result (u8: SCR_RES_*).
@ A band may hold content drawn later than an earlier band; within a band a later frame of the
@ same pixel is the newer one.
@
@ GUI tick: word 0x20000480 (fn_080277a0), +10 per SysTick (0x0802A720 ->
@ add_to_word_20000480_clear_byte_2000047c), SysTick 10 ms while word 0x200002B0 holds
@ 144000000: 1 tick = 1 ms under that condition.
@
@ Exports (AAPCS: r0..r3, r12 and the flags clobbered, r4..r11 kept, no FPU register used):
@   scr_start(r0 = band 0..23, or SCR_ALL) -> r0 = S_OK, S_BUSY (a capture runs), S_NOT_NOW
@     (DTR clear) or S_BAD_ARG; with S_OK also r1 = number of bands that follow (1 or 24).
@   scr_step() - one step, once per main-loop pass from ctl_loop (outside any refresh).
@   scr_busy() -> r0 = 1 while a capture runs, else 0.
@   own_flush(r0 = driver record, r1 = rectangle, r2 = pixels) - the flush pointer; ends in the
@     vendor flush (b.w fn_08014f9c) with r0..r2 as received.
@ Calls: usb_dtr, usb_tx_free, usb_reserve (usb.s), ctl_stream_frame (ctl.s), fn_080124d8,
@   fn_080277a0, ticks_since (port). ctl_stream_frame(r0 = cmd, r1 = head, r2 = head length,
@   r3 = data, [sp] = data length) -> r0 = 0 queued, nonzero nothing queued (no room).
@ Stack: own_flush 48 bytes, scr_step 24 bytes, scr_start 16 bytes, plus the callee's use.
@ RAM: OWN_SCREEN, 0x20 of its 0x40 bytes (offsets below). No flash is written here.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

@ Words in the screen.s area (offsets from OWN_SCREEN)
	.equ	SCO_STATE,	0x00		@ byte: SS_*
	.equ	SCO_BAND,	0x01		@ byte: band being captured
	.equ	SCO_LAST,	0x02		@ byte: last band of this capture
	.equ	SCO_TRIES,	0x03		@ byte: redraw requests of the band so far, minus 1
	.equ	SCO_RESULT,	0x04		@ byte: SCR_RES_* of the band
	.equ	SCO_Y0,		0x08		@ word: first row of the band (10 * band)
	.equ	SCO_ROWS,	0x0C		@ word: bit n = row y0 + n received in full width
	.equ	SCO_T0,		0x10		@ word: GUI tick at the start of the current wait
	.equ	SCO_HEAD,	0x14		@ 12 bytes: frame head (11) + result byte of the end

@ States
	.equ	SS_IDLE,	0		@ no capture
	.equ	SS_ROOM,	1		@ waiting for ring room, then the redraw request
	.equ	SS_CAPTURE,	2		@ redraw requested: own_flush copies the band
	.equ	SS_END,		3		@ band ended: end frame to send

@ Sizes and limits
	.equ	SCR_W,		320		@ panel width (fn_080269f0 halfword +0 = 0x140)
	.equ	SCR_ROWS,	10		@ rows per band (0xC80 / 320)
	.equ	SCR_ROWS_ALL,	0x3FF		@ row mask of a complete band
	.equ	SCR_FRAME_PIX,	240		@ pixels per frame (480 bytes)
	.equ	SCR_HEAD_LEN,	11		@ band, offset, x1, y1, x2, y2
	.equ	SCR_FRAME_OVH,	8 + SCR_HEAD_LEN	@ sync, length, seq, type, cmd, CRC + head
	.equ	SCR_ROOM,	SCR_W * SCR_ROWS * 2 + 26 * SCR_FRAME_OVH + 8 + SCR_HEAD_LEN + 1
						@ 6400 + 26 pieces x 19 + the end frame (20) = 6914
	.equ	SCR_T_REFRESH,	250		@ ticks for one redraw request (timer period 0x1E)
	.equ	SCR_T_ROOM,	2000		@ ticks the ring may take to drain
	.equ	SCR_TRIES,	3		@ redraw requests per band

@ put16 - store the low halfword of \val at the byte address \base + \off, little-endian, by
@   bytes (the frame head has its halfwords at odd offsets). \tmp is clobbered, flags too.
	.macro	put16 base, off, val, tmp
	strb	\val, [\base, #\off]
	lsrs	\tmp, \val, #8
	strb	\tmp, [\base, #\off + 1]
	.endm

	.section .text.own.screen,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ scr_start - begin a capture.
@   r0 = band 0..23, or SCR_ALL for bands 0..23. Returns r0 = S_OK / S_BUSY / S_NOT_NOW /
@   S_BAD_ARG; with S_OK, r1 = number of bands that follow. Uses r0..r3, r12.
@ ----------------------------------------------------------------------------
	.global	scr_start
	.thumb_func
	.type	scr_start, %function
scr_start:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_SCREEN
	mov	r5, r0				@ r5 = requested band
	ldrb	r1, [r4, #SCO_STATE]
	cmp	r1, #SS_IDLE
	bne	.Lb_busy
	bl	usb_dtr
	cmp	r0, #0
	beq	.Lb_notnow
	cmp	r5, #SCR_ALL
	bne	.Lb_one
	movs	r5, #0				@ all: bands 0 .. 23
	movs	r6, #SCR_BANDS - 1
	b	.Lb_go
.Lb_one:
	cmp	r5, #SCR_BANDS
	bhs	.Lb_bad
	mov	r6, r5				@ one band
.Lb_go:
	strb	r5, [r4, #SCO_BAND]
	strb	r6, [r4, #SCO_LAST]
	add	r0, r5, r5, lsl #2
	lsls	r0, r0, #1			@ 10 * band
	str	r0, [r4, #SCO_Y0]
	movs	r0, #0
	strb	r0, [r4, #SCO_TRIES]
	strb	r0, [r4, #SCO_RESULT]
	str	r0, [r4, #SCO_ROWS]
	bl	fn_080277a0			@ GUI tick
	str	r0, [r4, #SCO_T0]
	movs	r0, #1
	bl	usb_reserve			@ reservation on for the whole capture
	movs	r0, #SS_ROOM
	strb	r0, [r4, #SCO_STATE]
	subs	r1, r6, r5
	adds	r1, #1				@ r1 = bands that follow
	movs	r0, #S_OK
	pop	{r4, r5, r6, pc}
.Lb_busy:
	movs	r0, #S_BUSY
	pop	{r4, r5, r6, pc}
.Lb_notnow:
	movs	r0, #S_NOT_NOW
	pop	{r4, r5, r6, pc}
.Lb_bad:
	movs	r0, #S_BAD_ARG
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ scr_busy - r0 = 1 while a capture runs, else 0. Uses r0 only.
@ ----------------------------------------------------------------------------
	.global	scr_busy
	.thumb_func
	.type	scr_busy, %function
scr_busy:
	ldr	r0, =OWN_SCREEN
	ldrb	r0, [r0, #SCO_STATE]
	cmp	r0, #SS_IDLE
	it	ne
	movne	r0, #1
	bx	lr

@ ----------------------------------------------------------------------------
@ scr_step - one step of the capture; called once per main-loop pass by ctl_loop.
@   No arguments, no result. Each call does at most one check, one redraw request or one
@   end frame; it never waits.
@ ----------------------------------------------------------------------------
	.global	scr_step
	.thumb_func
	.type	scr_step, %function
scr_step:
	push	{r4, r5, r6, lr}
	ldr	r4, =OWN_SCREEN
	ldrb	r5, [r4, #SCO_STATE]
	cmp	r5, #SS_IDLE
	beq	.Ls_done
	bl	usb_dtr
	cmp	r0, #0
	beq	.Ls_stop			@ host closed the port: stop
	cmp	r5, #SS_ROOM
	beq	.Ls_room
	cmp	r5, #SS_CAPTURE
	beq	.Ls_capture
	b	.Ls_end				@ SS_END

@ SS_ROOM: request the redraw once the ring can take the whole band.
.Ls_room:
	bl	usb_tx_free
	movw	r1, #SCR_ROOM
	cmp	r0, r1
	bhs	.Ls_request
	ldr	r0, [r4, #SCO_T0]
	bl	ticks_since
	movw	r1, #SCR_T_ROOM
	cmp	r0, r1
	bhs	.Ls_stop			@ the host does not read: stop
	b	.Ls_done
.Ls_request:
	sub	sp, #8				@ rectangle {0, y0, 319, y0 + 9}
	ldr	r0, [r4, #SCO_Y0]
	movs	r1, #0
	strh	r1, [sp, #0]
	strh	r0, [sp, #2]
	movw	r1, #SCR_W - 1
	strh	r1, [sp, #4]
	adds	r0, #SCR_ROWS - 1
	strh	r0, [sp, #6]
	mov	r1, sp
	movs	r0, #0				@ default display record (fn_0801dccc)
	bl	fn_080124d8
	add	sp, #8
	movs	r0, #0
	str	r0, [r4, #SCO_ROWS]		@ only flushes from now on count
	strb	r0, [r4, #SCO_RESULT]
	bl	fn_080277a0
	str	r0, [r4, #SCO_T0]
	movs	r0, #SS_CAPTURE
	strb	r0, [r4, #SCO_STATE]
	b	.Ls_done

@ SS_CAPTURE: band complete, or the redraw did not come in time.
.Ls_capture:
	ldr	r0, [r4, #SCO_ROWS]
	movw	r1, #SCR_ROWS_ALL
	cmp	r0, r1
	beq	.Ls_ended			@ all 10 rows received (result stays DONE)
	ldr	r0, [r4, #SCO_T0]
	bl	ticks_since
	cmp	r0, #SCR_T_REFRESH
	blo	.Ls_done
	ldrb	r0, [r4, #SCO_TRIES]
	adds	r0, #1
	strb	r0, [r4, #SCO_TRIES]
	cmp	r0, #SCR_TRIES
	bhs	.Ls_norefresh
	movs	r0, #SS_ROOM			@ request the band again
	strb	r0, [r4, #SCO_STATE]
	bl	fn_080277a0
	str	r0, [r4, #SCO_T0]
	b	.Ls_done
.Ls_norefresh:
	movs	r0, #SCR_RES_NOREFRESH
	strb	r0, [r4, #SCO_RESULT]
.Ls_ended:
	movs	r0, #SS_END
	strb	r0, [r4, #SCO_STATE]
	bl	fn_080277a0
	str	r0, [r4, #SCO_T0]

@ SS_END: band end frame, then the next band or the end of the capture.
.Ls_end:
	add	r5, r4, #SCO_HEAD
	ldrb	r0, [r4, #SCO_BAND]
	strb	r0, [r5, #0]			@ band
	movs	r0, #0xFF
	strb	r0, [r5, #1]			@ offset 0xFFFF marks the end frame
	strb	r0, [r5, #2]
	movs	r0, #0
	strb	r0, [r5, #3]			@ x1 = 0
	strb	r0, [r5, #4]
	ldr	r0, [r4, #SCO_Y0]
	put16	r5, 5, r0, r1			@ y1 = y0
	adds	r0, #SCR_ROWS - 1
	put16	r5, 9, r0, r1			@ y2 = y0 + 9
	movw	r0, #SCR_W - 1
	put16	r5, 7, r0, r1			@ x2 = 319
	ldrb	r0, [r4, #SCO_RESULT]
	strb	r0, [r5, #11]			@ result
	sub	sp, #8
	movs	r0, #0
	str	r0, [sp, #0]			@ data length 0
	movs	r3, #0
	movs	r2, #SCR_HEAD_LEN + 1
	mov	r1, r5
	movs	r0, #C_SCREENSHOT
	bl	ctl_stream_frame
	add	sp, #8
	cbnz	r0, .Ls_endwait			@ no room: again next pass
	ldrb	r0, [r4, #SCO_BAND]
	ldrb	r1, [r4, #SCO_LAST]
	cmp	r0, r1
	bhs	.Ls_stop			@ last band sent: capture finished
	adds	r0, #1
	strb	r0, [r4, #SCO_BAND]
	add	r0, r0, r0, lsl #2
	lsls	r0, r0, #1			@ 10 * band
	str	r0, [r4, #SCO_Y0]
	movs	r0, #0
	strb	r0, [r4, #SCO_TRIES]
	movs	r0, #SS_ROOM
	strb	r0, [r4, #SCO_STATE]
	bl	fn_080277a0
	str	r0, [r4, #SCO_T0]
	b	.Ls_done
.Ls_endwait:
	ldr	r0, [r4, #SCO_T0]
	bl	ticks_since
	movw	r1, #SCR_T_ROOM
	cmp	r0, r1
	blo	.Ls_done
.Ls_stop:
	movs	r0, #SS_IDLE			@ capture over: own_flush passes everything
	strb	r0, [r4, #SCO_STATE]
	movs	r0, #0
	bl	usb_reserve			@ reservation off
.Ls_done:
	pop	{r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ own_flush - the GUI's flush (driver record word +0x14 via the literal 0x08026A3C).
@   r0 = driver record 0x20008000, r1 = rectangle (x1, y1, x2, y2 signed halfwords),
@   r2 = pixels ((x2 - x1 + 1) * (y2 - y1 + 1) halfwords, row-major), as call_with_offset_rect
@   passes them to fn_08014f9c. While a band is captured, the rows of the rectangle inside the
@   band are sent first; then the vendor flush runs with r0..r2 unchanged (b.w, its return goes
@   to our caller). r3 and r12 are clobbered (the vendor flush overwrites r3 itself).
@   First the due stream frames (stream_step, ctl.s): a redraw can run for 3.37 M instructions
@   outside ctl_loop, so the streams are also served here (stream_step stops while a band is
@   captured, scr_busy).
@ ----------------------------------------------------------------------------
	.global	own_flush
	.thumb_func
	.type	own_flush, %function
own_flush:
	push	{r0, r1, r2, lr}
	bl	stream_step
	pop	{r0, r1, r2, lr}
	ldr	r3, =OWN_SCREEN
	ldrb	r3, [r3, #SCO_STATE]
	cmp	r3, #SS_CAPTURE
	beq	.Lf_capture
	b.w	fn_08014f9c			@ no capture: the vendor flush only

.Lf_capture:
	push	{r0, r1, r2, r4, r5, r6, r7, r8, r9, lr}
	sub	sp, #8				@ [sp] = data length argument
	ldr	r7, =OWN_SCREEN
	ldr	r8, [r7, #SCO_Y0]		@ r8 = first row of the band
	ldrsh.w	r3, [r1, #2]			@ y1
	ldrsh.w	r4, [r1, #6]			@ y2
	add.w	r5, r8, #SCR_ROWS - 1		@ last row of the band
	cmp	r3, r8
	it	lt
	movlt	r3, r8				@ r3 = first row inside the band
	cmp	r4, r5
	it	gt
	movgt	r4, r5				@ r4 = last row inside the band
	cmp	r3, r4
	bgt	.Lf_pass			@ no row of the band
	ldrsh.w	r5, [r1, #0]			@ x1
	ldrsh.w	r6, [r1, #4]			@ x2
	subs	r9, r6, r5
	adds	r9, r9, #1			@ r9 = width
	ble	.Lf_pass			@ empty rectangle
	add	r0, r7, #SCO_HEAD		@ head: band, (offset), x1, y1, x2, y2
	ldrb	r2, [r7, #SCO_BAND]
	strb	r2, [r0, #0]
	put16	r0, 3, r5, r2
	put16	r0, 5, r3, r2
	put16	r0, 7, r6, r2
	put16	r0, 9, r4, r2
	movs	r2, #0				@ r2 = rows covered in full width
	cmp	r5, #0
	bgt	.Lf_nomask
	movw	r0, #SCR_W - 1
	cmp	r6, r0
	blt	.Lf_nomask
	subs	r0, r4, r3
	adds	r0, #1				@ rows of the piece (1..10)
	movs	r2, #1
	lsls	r2, r2, r0
	subs	r2, #1
	sub.w	r0, r3, r8			@ first row relative to the band
	lsls	r2, r2, r0
.Lf_nomask:
	mov	r8, r2				@ r8 = row bits of this piece
	subs	r5, r4, r3
	adds	r5, #1
	mul	r5, r5, r9			@ r5 = pixels of the piece
	ldr	r1, [sp, #12]			@ rectangle
	ldrsh.w	r0, [r1, #2]			@ y1
	subs	r0, r3, r0			@ rows above the band (>= 0)
	mul	r0, r0, r9
	ldr	r4, [sp, #16]			@ pixels
	add.w	r4, r4, r0, lsl #1		@ r4 = first pixel of the piece
	movs	r6, #0				@ r6 = offset of the next frame in the piece
.Lf_loop:
	mov	r9, r5
	cmp	r9, #SCR_FRAME_PIX
	it	hi
	movhi	r9, #SCR_FRAME_PIX		@ r9 = pixels of this frame
	add	r0, r7, #SCO_HEAD
	strb	r6, [r0, #1]			@ offset (u16)
	lsrs	r1, r6, #8
	strb	r1, [r0, #2]
	lsl	r1, r9, #1
	str	r1, [sp, #0]			@ data length in bytes
	mov	r1, r0
	movs	r2, #SCR_HEAD_LEN
	mov	r3, r4
	movs	r0, #C_SCREENSHOT
	bl	ctl_stream_frame
	cbnz	r0, .Lf_lost
	add.w	r4, r4, r9, lsl #1
	add	r6, r9
	subs	r5, r5, r9
	bne	.Lf_loop
	ldr	r0, [r7, #SCO_ROWS]		@ whole piece queued: its rows count
	orr	r0, r0, r8
	str	r0, [r7, #SCO_ROWS]
	b	.Lf_pass
.Lf_lost:
	movs	r0, #SCR_RES_NOROOM		@ a frame did not fit: the band ends here
	strb	r0, [r7, #SCO_RESULT]
	movs	r0, #SS_END
	strb	r0, [r7, #SCO_STATE]
.Lf_pass:
	add	sp, #8
	pop	{r0, r1, r2, r4, r5, r6, r7, r8, r9, lr}
	b.w	fn_08014f9c			@ the vendor flush with r0..r2 as received

	.ltorg
