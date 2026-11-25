@ usb.s - USB device driver of our build: CDC ACM serial port (one control, one data interface)
@ Part of the FNIRSI LC1020E firmware rewrite (Thumb-2 assembly).
@
@ The register handling follows the slot
@ bootloader's driver, which enumerates on this meter (bootloader/src/usb_08.s, usb_09.s,
@ update_06.s), and the N32G45x user manual
@ V3.5.0 chapter 19 (docs/).
@
@ Device: VID 0x19F5, PID 0x1020, class 0x02 (no IAD), strings 1 "FNIRSI", 2 "LC1020E", 3 the
@ chip UID 0x1FFFF7F0..0x1FFFF7FB (manual "UID register", 96 bits) as 24 hex digits, the byte at
@ 0x1FFFF7F0 first, high nibble first, digits 0-9 A-F. Configuration 1: interface 0 (class 2,
@ subclass 2, protocol 1: header 1.10, call management capabilities 0 data interface 1, ACM
@ capabilities 0x02, union 0 -> 1, endpoint 0x83 interrupt IN 16 bytes interval 16), interface 1
@ (class 0x0A: endpoint 0x81 bulk IN 64, endpoint 0x02 bulk OUT 64). bmAttributes 0xC0 (self
@ powered: the meter runs from its battery), bMaxPower 0x32 (100 mA).
@
@ Bring-up (usb_start): only when RCC_CFG SCLKSTS = PLL (the application's
@ clock 144 MHz); USBPRES = 11 (PLL / 3 = 48 MHz) before USBEN (manual: USBPRES must be
@ valid before the USB clock is enabled), both by read-modify-write; USB_CTRL = FRST (PD
@ cleared), at least 1 us (datasheet Table 4-41: transceiver start-up time tSTARTUP 1 us), then
@ USB_CTRL = 0 (manual 19.4.5.1.1), USB_STS = 0, BUFTAB = 0, our state and the endpoints set
@ up, USB_CTRL = CTRSM | RSTM, NVIC priorities and enables, then the D+ pull-up: bit 28 of
@ 0x40001820 by read-modify-write, no other bit (manual 19.4.5.1.1 note 1).
@
@ Packet memory (512 bytes, CPU address 0x40006000 + 2 * offset, 16-bit accesses only at a 4-byte
@ stride: manual 19.4.1; the bootloader's 32-bit stores and byte loads there are not used):
@ buffer table 0x00..0x1F, EP0 RX 0x40, EP0 TX 0x80, EP1 TX 0xC0, EP2 RX 0x100 (64 bytes each),
@ EP3 TX 0x140 (16 bytes).
@
@ Interrupts: IRQ 20 (usb_irq20_handler) for every USB event; only CTRS and RST are enabled.
@ SUSPD / WKUP / SOF are not enabled: the device never enters suspend (FSUSPD), which the
@ manual allows for self-powered devices (19.4.5.2.1). IRQ 42 (usb_irq42_handler) only clears
@ EXTI pending bit 18 (0x40000 to 0x40010414, as 0x0800FB40 -> 0x08008D14); this driver does
@ not set up EXTI line 18. Priority byte 0x80 for both (own.inc USB_IRQ_PRIO).
@ Every endpoint register write happens inside IRQ 20: the main-loop functions only move bytes
@ between the caller and the rings, update their own ring index and pend IRQ 20 (NVIC_ISPR0)
@ when the interrupt has something to start. Each ring index has one writer: RX head and TX tail
@ the interrupt, RX tail and TX head the main loop (aligned word stores).
@
@ Endpoints:
@ - EP0: standard requests GET_STATUS, CLEAR_FEATURE / SET_FEATURE (endpoint halt of 0x81, 0x02,
@   0x83), SET_ADDRESS (applied after the status stage), GET_DESCRIPTOR (device, configuration,
@   string 0..3), GET_CONFIGURATION, SET_CONFIGURATION (0 / 1), GET_INTERFACE / SET_INTERFACE
@   (interface 0 / 1, alternate setting 0); CDC requests to interface 0: SET_LINE_CODING (7-byte
@   OUT data stage, stored), GET_LINE_CODING (returns it; 115200 8N1 until the host sets one),
@   SET_CONTROL_LINE_STATE (wValue bit 0 = DTR). Every other request: STALL on both directions.
@   Between transfers both directions are STALL; a SETUP is received in that state (manual
@   19.4.4 control transfer, note 2).
@ - EP2 OUT: copied into the RX ring; re-armed (VALID) only while the ring has at least 64 bytes
@   free, else it stays NAK and is re-armed by the interrupt once usb_rx_get has freed 64 bytes.
@ - EP1 IN: packets of up to 64 bytes from the TX ring; the ring tail moves when the packet has
@   gone (CTRS_TX), so a packet cut by a bus reset, a halt or SET_CONFIGURATION is sent again.
@   A burst that ends with a full 64-byte packet is closed by a zero-length packet.
@ - EP3 IN (notification): configured NAK, never armed; no notification is ever sent.
@ A USB reset drops the bytes waiting in the TX ring (the host that queued for them is gone),
@ clears DTR and the configuration; the RX ring is left to the reader.
@
@ RAM: OWN_USB (0x80 bytes, UO_* below), OWN_RX_RING (1 KiB), OWN_TX_RING (8 KiB); no section.
@
@ Exports. Calling convention: AAPCS; r0..r3, r12 and the flags clobbered, r4..r11 kept, no FPU
@ register used.
@   usb_start() -> r0 = 0 started (or already started), 1 not started (system clock is not the
@     PLL). Every call before the device is up clears OWN_USB. Main context, once, from ctl_loop's first pass. Stack 16 bytes
@     plus 16 (helpers).
@   usb_irq20_handler - vector word 36 (IRQ 20). Stack 16 bytes plus at most 16 (helpers), not
@     counting the exception frame.
@   usb_irq42_handler - vector word 58 (IRQ 42). No stack.
@   usb_rx_get() -> r0 = next received byte 0..255, or -1 when the RX ring is empty. No stack.
@   usb_rx_count() -> r0 = bytes in the RX ring. No stack.
@   usb_tx_put(r0 = source, r1 = length) -> r0 = bytes taken (min(length, usb_tx_free)), in
@     order, never part of a byte. Stack 16 bytes.
@   usb_tx_free() -> r0 = bytes the TX ring can take now (0..8191). No stack.
@   usb_tx_empty() -> r0 = 1 when the TX ring is empty and EP1 has no packet (or zero-length
@     packet) in flight or due, else 0. No stack.
@   usb_dtr() -> r0 = DTR (0 / 1) from the last SET_CONTROL_LINE_STATE; 0 after a USB reset
@     and while not configured. No stack.
@   usb_reserve(r0 = USB_RES_OFF, USB_RES_ON or USB_RES_QUERY) -> r0 = reservation after the
@     call (0 / 1). The screenshot holds it during a capture (screen.s); the driver itself does
@     not change any other function's behaviour while it is held. No stack.
@
@ Internal routines: r4 = USB_BASE and r5 = OWN_USB on entry and kept; r0..r3, r12 clobbered.

	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.include "own/own.inc"

@ OWN_USB layout (offsets)
	.equ	UO_RX_HEAD,	0x00		@ word: RX ring write index (interrupt)
	.equ	UO_RX_TAIL,	0x04		@ word: RX ring read index (main loop)
	.equ	UO_TX_HEAD,	0x08		@ word: TX ring write index (main loop)
	.equ	UO_TX_TAIL,	0x0C		@ word: TX ring read index (interrupt)
	.equ	UO_CONFIG,	0x10		@ byte: configuration value 0 / 1
	.equ	UO_LINE,	0x11		@ byte: control line state (bit 0 DTR, bit 1 RTS)
	.equ	UO_EP1_BUSY,	0x12		@ byte: 1 while an EP1 packet is armed
	.equ	UO_EP1_LEN,	0x13		@ byte: length of that packet
	.equ	UO_EP1_ZLP,	0x14		@ byte: 1 when the last EP1 packet that went was 64 bytes
	.equ	UO_EP2_PAUSED,	0x15		@ byte: 1 while EP2 waits (NAK) for 64 free bytes
	.equ	UO_HALT,	0x16		@ byte: bit n = endpoint n halted (n = 1, 2, 3)
	.equ	UO_EP0_STATE,	0x17		@ byte: E0_*
	.equ	UO_ADDR,	0x18		@ byte: address | 0x80 to set after the status stage, 0 none
	.equ	UO_RESERVE,	0x19		@ byte: usb_reserve state
	.equ	UO_EP0_ZLP,	0x1A		@ byte: IN data stage shorter than wLength (end it short)
	.equ	UO_STARTED,	0x1B		@ byte: 1 once usb_start brought the device up
	.equ	UO_EP0_LEFT,	0x1C		@ halfword: bytes of the IN data stage not yet armed
	.equ	UO_REPLY,	0x1E		@ halfword: answer of GET_STATUS / _CONFIGURATION / _INTERFACE
	.equ	UO_EP0_PTR,	0x20		@ word: next byte of the IN data stage
	.equ	UO_SETUP,	0x24		@ 8 bytes: the SETUP packet (+0 bmRequestType, +1 bRequest,
					@ +2 wValue, +4 wIndex, +6 wLength)
	.equ	UO_LINECODE,	0x2C		@ 7 bytes: line coding (rate u32, stop, parity, data bits)
	.equ	UO_SERIAL,	0x34		@ 50 bytes: string descriptor 3
	.equ	UO_END,		0x66

	.if	UO_END > USB_SIZE
	.error	"usb.s state does not fit O_USB"
	.endif

@ EP0 states
	.equ	E0_IDLE,	0		@ no transfer (both directions STALL)
	.equ	E0_IN,		1		@ IN data stage running
	.equ	E0_STATUS_OUT,	2		@ IN data sent, waiting for the status OUT
	.equ	E0_OUT,		3		@ waiting for the OUT data stage (line coding)
	.equ	E0_STATUS_IN,	4		@ zero-length status IN armed

@ halt bits (UO_HALT) = 1 << endpoint number
	.equ	HALT_EP1,	0x02
	.equ	HALT_EP2,	0x04
	.equ	HALT_EP3,	0x08

@ rings: sizes are powers of two, the index wraps with ubfx
	.equ	RX_BITS,	10
	.equ	TX_BITS,	13
	.if	(1 << RX_BITS) != RX_RING_SIZE
	.error	"RX_RING_SIZE is not 1 << RX_BITS"
	.endif
	.if	(1 << TX_BITS) != TX_RING_SIZE
	.error	"TX_RING_SIZE is not 1 << TX_BITS"
	.endif

@ standard requests (USB 2.0 table 9-4) and CDC PSTN requests
	.equ	REQ_GET_STATUS,	0
	.equ	REQ_CLEAR_FEATURE, 1
	.equ	REQ_SET_FEATURE, 3
	.equ	REQ_SET_ADDRESS, 5
	.equ	REQ_GET_DESCRIPTOR, 6
	.equ	REQ_GET_CONFIGURATION, 8
	.equ	REQ_SET_CONFIGURATION, 9
	.equ	REQ_GET_INTERFACE, 10
	.equ	REQ_SET_INTERFACE, 11
	.equ	CDC_SET_LINE_CODING, 0x20
	.equ	CDC_GET_LINE_CODING, 0x21
	.equ	CDC_SET_CONTROL_LINE_STATE, 0x22

@ packet buffers as CPU addresses
	.equ	PMA_CPU_EP0_RX,	USB_PMA + 2 * PMA_EP0_RX
	.equ	PMA_CPU_EP0_TX,	USB_PMA + 2 * PMA_EP0_TX
	.equ	PMA_CPU_EP1_TX,	USB_PMA + 2 * PMA_EP1_TX
	.equ	PMA_CPU_EP2_RX,	USB_PMA + 2 * PMA_EP2_RX

	.equ	DESC_DEVICE_LEN, 18
	.equ	DESC_CONFIG_LEN, 67
	.equ	SERIAL_LEN,	2 + 24 * 2	@ string descriptor 3: header + 24 UTF-16 digits
	.equ	LINE_RATE,	115200		@ line coding until SET_LINE_CODING
	.equ	FRST_WAIT,	200		@ loop passes after FRST: at least 2 cycles each,
					@ 400 cycles = 2.8 us at 144 MHz

	.section .rodata.own.usb,"a",%progbits
	.p2align 2

@ desc_device - device descriptor (USB 2.0 table 9-8)
desc_device:
	.byte	DESC_DEVICE_LEN, 1		@ bLength, DEVICE
	.byte	0x00, 0x02			@ bcdUSB 2.00
	.byte	0x02, 0x00, 0x00		@ class communications, subclass 0, protocol 0
	.byte	USB_EP_SIZE			@ bMaxPacketSize0
	.byte	USB_VID & 0xFF, USB_VID >> 8	@ idVendor 0x19F5
	.byte	USB_PID & 0xFF, USB_PID >> 8	@ idProduct 0x1020
	.byte	0x00, 0x01			@ bcdDevice 1.00
	.byte	1, 2, 3				@ iManufacturer, iProduct, iSerialNumber
	.byte	1				@ bNumConfigurations

@ desc_config - configuration descriptor with its interfaces, functional descriptors and
@ endpoints (USB 2.0 9.6.3; CDC 1.10 5.2.3; PSTN 1.20 5.3)
desc_config:
	.byte	9, 2, DESC_CONFIG_LEN, 0	@ CONFIGURATION, wTotalLength 67
	.byte	2, 1, 0				@ 2 interfaces, bConfigurationValue 1, no string
	.byte	0xC0, 0x32			@ self powered, 100 mA
	@ interface 0: communications, ACM, AT commands protocol 1
	.byte	9, 4, 0, 0, 1, 0x02, 0x02, 0x01, 0
	.byte	5, 0x24, 0x00, 0x10, 0x01	@ header, bcdCDC 1.10
	.byte	5, 0x24, 0x01, 0x00, 0x01	@ call management: capabilities 0, data interface 1
	.byte	4, 0x24, 0x02, 0x02		@ ACM: line coding and serial state requests
	.byte	5, 0x24, 0x06, 0x00, 0x01	@ union: master 0, slave 1
	.byte	7, 5, 0x83, 0x03, 16, 0, 16	@ endpoint 0x83 interrupt, 16 bytes, 16 ms
	@ interface 1: data
	.byte	9, 4, 1, 0, 2, 0x0A, 0x00, 0x00, 0
	.byte	7, 5, 0x81, 0x02, USB_EP_SIZE, 0, 0	@ endpoint 0x81 bulk IN, 64 bytes
	.byte	7, 5, 0x02, 0x02, USB_EP_SIZE, 0, 0	@ endpoint 0x02 bulk OUT, 64 bytes
desc_config_end:
	.if	desc_config_end - desc_config != DESC_CONFIG_LEN
	.error	"configuration descriptor length"
	.endif

@ string descriptors 0..2 (string 3 is built in RAM by usb_start)
desc_str0:
	.byte	4, 3, 0x09, 0x04		@ language 0x0409
desc_str1:
	.byte	14, 3
	.byte	'F', 0, 'N', 0, 'I', 0, 'R', 0, 'S', 0, 'I', 0
desc_str2:
	.byte	16, 3
	.byte	'L', 0, 'C', 0, '1', 0, '0', 0, '2', 0, '0', 0, 'E', 0

hex_digits:
	.ascii	"0123456789ABCDEF"

	.p2align 2
@ string_table - address of string descriptor n; its length is its first byte
string_table:
	.word	desc_str0, desc_str1, desc_str2, OWN_USB + UO_SERIAL

	.section .text.own.usb,"ax",%progbits
	.p2align 2

@ ----------------------------------------------------------------------------
@ usb_start - bring the USB device up (see the header). No arguments.
@   Returns r0 = 0 started or already started, 1 not started (SCLKSTS is not the PLL).
@ ----------------------------------------------------------------------------
	.global	usb_start
	.thumb_func
	.type	usb_start, %function
usb_start:
	push	{r4, r5, r6, lr}
	ldr	r5, =OWN_USB
	ldrb	r0, [r5, #UO_STARTED]
	cmp	r0, #0
	bne	.Lst_ok				@ brought up before: nothing again
@ our state: cleared, string 3 and the line coding built
	movs	r0, #0
	movs	r1, #USB_SIZE
.Lst_clear:
	subs	r1, r1, #4
	str	r0, [r5, r1]
	bne	.Lst_clear
	add	r0, r5, #UO_SERIAL
	movs	r1, #SERIAL_LEN
	strb	r1, [r0]			@ bLength 50
	movs	r1, #3
	strb	r1, [r0, #1]			@ STRING
	adds	r0, r0, #2
	ldr	r1, =CHIP_UID
	ldr	r3, =hex_digits
	movs	r2, #12				@ UID bytes
.Lst_uid:
	ldrb	r6, [r1], #1
	lsr	r12, r6, #4
	ldrb	r12, [r3, r12]
	strh	r12, [r0], #2			@ high nibble digit, UTF-16LE
	and	r6, r6, #0xF
	ldrb	r6, [r3, r6]
	strh	r6, [r0], #2			@ low nibble digit
	subs	r2, r2, #1
	bne	.Lst_uid
	ldr	r0, =LINE_RATE
	str	r0, [r5, #UO_LINECODE]		@ dwDTERate; stop bits 0 (1), parity 0 (none)
	movs	r0, #8
	strb	r0, [r5, #UO_LINECODE + 6]	@ bDataBits 8
@ clock: only from the PLL
	ldr	r0, =RCC_CFG
	ldr	r1, [r0]
	and	r1, r1, #RCC_SCLKSTS
	cmp	r1, #RCC_SCLK_PLL
	bne	.Lst_noclock
	ldr	r1, [r0]
	orr	r1, r1, #RCC_USBPRES		@ USBPRES = 11: PLL / 3
	str	r1, [r0]
	ldr	r0, =RCC_APB1PCLKEN
	ldr	r1, [r0]
	orr	r1, r1, #RCC_USBEN		@ USB clock on
	str	r1, [r0]
	ldr	r1, [r0]			@ read back: the write has completed
@ the USB module out of power-down and reset
	ldr	r4, =USB_BASE
	movs	r1, #USB_CTRL_FRST
	str	r1, [r4, #USB_CTRL]		@ PD = 0, FRST kept
	movs	r0, #FRST_WAIT
.Lst_wait:
	subs	r0, r0, #1
	bne	.Lst_wait
	movs	r1, #0
	str	r1, [r4, #USB_CTRL]		@ FRST = 0, no interrupt enabled yet
	str	r1, [r4, #USB_STS]		@ pending flags cleared
	str	r1, [r4, #USB_BUFTAB]		@ buffer table at packet-memory offset 0
	bl	usb_bus_reset			@ buffer table, EP0, EP1..3 off, address 0 enabled
	movw	r1, #(USB_CTRL_CTRSM | USB_CTRL_RSTM)
	str	r1, [r4, #USB_CTRL]
@ NVIC: priority bytes, stale pending bits cleared, then enabled
	ldr	r0, =NVIC_IPR
	movs	r1, #USB_IRQ_PRIO
	strb	r1, [r0, #IRQ_USB_LP]
	strb	r1, [r0, #IRQ_USB_WKUP]
	ldr	r0, =NVIC_ICPR0
	mov	r1, #(1 << IRQ_USB_LP)
	mov	r2, #(1 << (IRQ_USB_WKUP - 32))
	str	r1, [r0]			@ ICPR0
	str	r2, [r0, #4]			@ ICPR1
	ldr	r0, =NVIC_ISER0
	str	r1, [r0]			@ ISER0
	str	r2, [r0, #4]			@ ISER1
@ D+ pull-up: the host sees the device from here on
	ldr	r0, =USB_PULLUP
	ldr	r1, [r0]
	orr	r1, r1, #USB_PULLUP_BIT
	str	r1, [r0]
	movs	r0, #1
	strb	r0, [r5, #UO_STARTED]
.Lst_ok:
	movs	r0, #0
	pop	{r4, r5, r6, pc}
.Lst_noclock:
	movs	r0, #1
	pop	{r4, r5, r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ usb_irq42_handler - IRQ 42 (USB wake-up): clears EXTI pending bit 18 (writing 1 clears it).
@ ----------------------------------------------------------------------------
	.global	usb_irq42_handler
	.thumb_func
	.type	usb_irq42_handler, %function
usb_irq42_handler:
	ldr	r0, =EXTI_PEND
	mov	r1, #EXTI_LINE18
	str	r1, [r0]
	bx	lr

@ ----------------------------------------------------------------------------
@ usb_irq20_handler - IRQ 20: USB reset, then every correct transfer while USB_STS.CTRS is
@   set (endpoint from EP_ID, as bootloader usb_09.s fn_08002a40), then usb_kick (EP2 re-arm,
@   next EP1 packet). Also entered when the main loop pends IRQ 20.
@ ----------------------------------------------------------------------------
	.global	usb_irq20_handler
	.thumb_func
	.type	usb_irq20_handler, %function
usb_irq20_handler:
	push	{r4, r5, r6, lr}
	ldr	r4, =USB_BASE
	ldr	r5, =OWN_USB
	ldr	r0, [r4, #USB_STS]
	tst	r0, #USB_STS_RST
	beq	.Lirq_ctr
	movw	r0, #(0xFFFF & ~USB_STS_RST)
	str	r0, [r4, #USB_STS]		@ RST cleared (0xFBFF, as fn_08002ca4)
	bl	usb_bus_reset
.Lirq_ctr:
	ldr	r0, [r4, #USB_STS]
	tst	r0, #USB_STS_CTRS
	beq	.Lirq_kick
	and	r6, r0, #USB_STS_EPID		@ r6 = endpoint number
	cmp	r6, #0
	beq	.Lirq_ep0
@ endpoints 1..7: CTRS_RX (EP2 data), then CTRS_TX (EP1 packet gone); others only cleared
	add	r1, r4, r6, lsl #2
	ldr	r1, [r1]			@ USB_EPn
	tst	r1, #EP_CTRS_RX
	beq	.Lirq_tx
	mov	r0, r6
	movs	r1, #EP_CTRS_TX
	bl	ep_clr				@ CTRS_RX cleared
	cmp	r6, #2
	bne	.Lirq_tx
	bl	ep2_rx
.Lirq_tx:
	add	r1, r4, r6, lsl #2
	ldr	r1, [r1]
	tst	r1, #EP_CTRS_TX
	beq	.Lirq_ctr
	mov	r0, r6
	mov	r1, #EP_CTRS_RX
	bl	ep_clr				@ CTRS_TX cleared
	cmp	r6, #1
	bne	.Lirq_ctr
	bl	ep1_done
	b	.Lirq_ctr
@ endpoint 0: a finished IN first (it is the older event), then SETUP or OUT. r6 = USB_EP0
@ before the flags are cleared: SETUP stays valid while CTRS_RX is set.
.Lirq_ep0:
	ldr	r6, [r4, #USB_EP0R]
	tst	r6, #EP_CTRS_TX
	beq	.Lirq_e0rx
	movs	r0, #0
	mov	r1, #EP_CTRS_RX
	bl	ep_clr				@ CTRS_TX cleared
	bl	ep0_in_done
.Lirq_e0rx:
	tst	r6, #EP_CTRS_RX
	beq	.Lirq_ctr
	movs	r0, #0
	movs	r1, #EP_CTRS_TX
	bl	ep_clr				@ CTRS_RX cleared
	tst	r6, #EP_SETUP
	beq	.Lirq_e0out
	bl	ep0_setup
	b	.Lirq_ctr
.Lirq_e0out:
	bl	ep0_out
	b	.Lirq_ctr
.Lirq_kick:
	bl	usb_kick
	pop	{r4, r5, r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ Endpoint register helpers (r4 = USB_BASE; the register of endpoint n is USB_BASE + 4 * n).
@ ep_clr(r0 = n, r1 = EP_CTRS_TX to clear CTRS_RX, EP_CTRS_RX to clear CTRS_TX): writes
@   (USB_EPn & 0x0F0F) | r1: the other flag is written as 1 (no effect), no status or toggle
@   bit is written as 1.
@ ep_tx / ep_rx / ep_both(r0 = n, r1 = wanted STS_TX / STS_RX / both): writes
@   ((USB_EPn & mask) ^ r1) | 0x8080, mask 0x8FBF / 0xBF8F / 0xBFBF: a field that is kept
@   toggles from its value to r1's, nothing else toggles, both CTRS bits written as 1.
@ ep_init(r0 = n, r1 = EP_TYPE | EPADDR, r2 = wanted STS_RX | STS_TX): writes
@   ((USB_EPn & 0x7070) ^ r2) | r1 | 0x8080: both status fields to r2's, both DATTOG to 0
@   (DATA0), type and address written.
@ Use r0..r3, r12.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ep_clr, %function
ep_clr:
	add	r3, r4, r0, lsl #2
	ldr	r0, [r3]
	movw	r2, #EP_KEEP_CLR
	ands	r0, r0, r2
	orrs	r0, r0, r1
	str	r0, [r3]
	bx	lr

	.thumb_func
	.type	ep_tx, %function
ep_tx:
	movw	r2, #EP_KEEP_TX
	b	ep_sts

	.thumb_func
	.type	ep_rx, %function
ep_rx:
	movw	r2, #EP_KEEP_RX
	b	ep_sts

	.thumb_func
	.type	ep_both, %function
ep_both:
	movw	r2, #EP_KEEP_BOTH
@ ep_sts: r2 = mask (falls through from ep_both)
	.thumb_func
	.type	ep_sts, %function
ep_sts:
	add	r3, r4, r0, lsl #2
	ldr	r0, [r3]
	ands	r0, r0, r2
	eors	r0, r0, r1
	movw	r12, #EP_NO_CLR
	orr	r0, r0, r12
	str	r0, [r3]
	bx	lr

	.thumb_func
	.type	ep_init, %function
ep_init:
	add	r3, r4, r0, lsl #2
	ldr	r0, [r3]
	movw	r12, #EP_KEEP_INIT
	and	r0, r0, r12
	eors	r0, r0, r2
	orrs	r0, r0, r1
	movw	r12, #EP_NO_CLR
	orr	r0, r0, r12
	str	r0, [r3]
	bx	lr

@ ----------------------------------------------------------------------------
@ Packet-memory copies (16-bit accesses, the next halfword 4 bytes higher, as bootloader
@ usb_09.s fn_080029e8 / fn_08002a10; low byte first).
@ pma_put(r0 = packet buffer CPU address, r1 = source base, r2 = source index, r3 = count,
@   r12 = index mask (0x1FFF for the TX ring, 0xFFFFFFFF for a plain buffer)). An odd count
@   writes 0 as the last high byte. Uses r6, r7 (saved).
@ pma_get(r0 = packet buffer CPU address, r1 = destination base, r2 = destination index,
@   r3 = count, r12 = index mask) -> r0 = destination index after the bytes. Uses r6 (saved).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	pma_put, %function
pma_put:
	push	{r6, r7}
	b	.Lpp_test
.Lpp_loop:
	ldrb	r6, [r1, r2]			@ low byte
	adds	r2, r2, #1
	and	r2, r2, r12
	subs	r3, r3, #1
	beq	.Lpp_store			@ odd count: high byte 0
	ldrb	r7, [r1, r2]			@ high byte
	adds	r2, r2, #1
	and	r2, r2, r12
	orr	r6, r6, r7, lsl #8
	subs	r3, r3, #1
.Lpp_store:
	strh	r6, [r0], #4
.Lpp_test:
	cmp	r3, #0
	bne	.Lpp_loop
	pop	{r6, r7}
	bx	lr

	.thumb_func
	.type	pma_get, %function
pma_get:
	push	{r6}
	b	.Lpg_test
.Lpg_loop:
	ldrh	r6, [r0], #4
	strb	r6, [r1, r2]			@ low byte
	adds	r2, r2, #1
	and	r2, r2, r12
	subs	r3, r3, #1
	beq	.Lpg_done
	lsrs	r6, r6, #8
	strb	r6, [r1, r2]			@ high byte
	adds	r2, r2, #1
	and	r2, r2, r12
	subs	r3, r3, #1
.Lpg_test:
	cmp	r3, #0
	bne	.Lpg_loop
.Lpg_done:
	mov	r0, r2
	pop	{r6}
	bx	lr

@ ----------------------------------------------------------------------------
@ usb_bus_reset - state after a USB reset (manual 19.4.5.1.2) and at usb_start: buffer table
@   (BUFTAB 0), EP0 control (RX VALID, TX NAK), EP1..3 off (cfg_off), EP0 state idle, no
@   pending address, the TX ring emptied (tail = head), USB_ADDR = EFUC (address 0).
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	usb_bus_reset, %function
usb_bus_reset:
	push	{r6, lr}
	ldr	r0, =USB_PMA
	movs	r1, #PMA_EP0_TX
	strh	r1, [r0, #(0 * BT_STRIDE + BT_ADDR_TX)]
	movs	r1, #PMA_EP0_RX
	strh	r1, [r0, #(0 * BT_STRIDE + BT_ADDR_RX)]
	movs	r1, #PMA_EP1_TX
	strh	r1, [r0, #(1 * BT_STRIDE + BT_ADDR_TX)]
	movw	r1, #PMA_EP2_RX
	strh	r1, [r0, #(2 * BT_STRIDE + BT_ADDR_RX)]
	movw	r1, #PMA_EP3_TX
	strh	r1, [r0, #(3 * BT_STRIDE + BT_ADDR_TX)]
	movw	r1, #BT_RX_64
	strh	r1, [r0, #(0 * BT_STRIDE + BT_CNT_RX)]
	strh	r1, [r0, #(2 * BT_STRIDE + BT_CNT_RX)]
	movs	r1, #0
	strh	r1, [r0, #(0 * BT_STRIDE + BT_CNT_TX)]
	strh	r1, [r0, #(1 * BT_STRIDE + BT_CNT_TX)]
	strh	r1, [r0, #(1 * BT_STRIDE + BT_ADDR_RX)]
	strh	r1, [r0, #(1 * BT_STRIDE + BT_CNT_RX)]
	strh	r1, [r0, #(2 * BT_STRIDE + BT_ADDR_TX)]
	strh	r1, [r0, #(2 * BT_STRIDE + BT_CNT_TX)]
	strh	r1, [r0, #(3 * BT_STRIDE + BT_CNT_TX)]
	strh	r1, [r0, #(3 * BT_STRIDE + BT_ADDR_RX)]
	strh	r1, [r0, #(3 * BT_STRIDE + BT_CNT_RX)]
	movs	r0, #0
	mov	r1, #EP_T_CONTROL
	movw	r2, #(EP_RX_VALID | EP_TX_NAK)
	bl	ep_init				@ EP0
	bl	cfg_off				@ EP1..3 off, not configured, DTR 0
	movs	r0, #0
	strb	r0, [r5, #UO_EP0_STATE]
	strb	r0, [r5, #UO_ADDR]
	strb	r0, [r5, #UO_EP0_ZLP]
	ldr	r0, [r5, #UO_TX_HEAD]
	str	r0, [r5, #UO_TX_TAIL]		@ bytes queued before the reset dropped
	movs	r0, #USB_ADDR_EFUC
	str	r0, [r4, #USB_ADDR]		@ enabled, address 0
	pop	{r6, pc}

@ ----------------------------------------------------------------------------
@ cfg_off - not configured: EP1..3 disabled (STS 00, DATTOG 0), DTR / line state 0, EP1 idle,
@   no halt, EP2 not waiting.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	cfg_off, %function
cfg_off:
	push	{r6, lr}
	movs	r0, #0
	strb	r0, [r5, #UO_CONFIG]
	strb	r0, [r5, #UO_LINE]
	strb	r0, [r5, #UO_EP1_BUSY]
	strb	r0, [r5, #UO_EP1_LEN]
	strb	r0, [r5, #UO_EP1_ZLP]
	strb	r0, [r5, #UO_EP2_PAUSED]
	strb	r0, [r5, #UO_HALT]
	movs	r0, #1
	movs	r1, #(EP_T_BULK | 1)
	movs	r2, #0
	bl	ep_init
	movs	r0, #2
	movs	r1, #(EP_T_BULK | 2)
	movs	r2, #0
	bl	ep_init
	movs	r0, #3
	movw	r1, #(EP_T_INTERRUPT | 3)
	movs	r2, #0
	bl	ep_init
	pop	{r6, pc}

@ ----------------------------------------------------------------------------
@ ep_reinit(r0 = halt bit of endpoint 1, 2 or 3) - endpoint set up as configured with DATA0 and
@   its halt cleared (SET_CONFIGURATION 1, CLEAR_FEATURE endpoint halt, SET_INTERFACE):
@   EP1 bulk TX NAK and idle (a packet not yet gone is sent again from the ring tail); EP2 bulk
@   RX NAK, then ep2_arm; EP3 interrupt TX NAK (never armed).
@ ep_halt(r0 = halt bit) - SET_FEATURE endpoint halt: the endpoint's direction STALL; EP1 idle.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ep_reinit, %function
ep_reinit:
	push	{r6, lr}
	mov	r6, r0
	ldrb	r1, [r5, #UO_HALT]
	bic	r1, r1, r0
	strb	r1, [r5, #UO_HALT]
	cmp	r6, #HALT_EP2
	beq	.Lri_ep2
	cmp	r6, #HALT_EP3
	beq	.Lri_ep3
	movs	r0, #0				@ EP1
	strb	r0, [r5, #UO_EP1_BUSY]
	strb	r0, [r5, #UO_EP1_LEN]
	strb	r0, [r5, #UO_EP1_ZLP]
	movs	r0, #1
	movs	r1, #(EP_T_BULK | 1)
	movs	r2, #EP_TX_NAK
	bl	ep_init
	pop	{r6, pc}
.Lri_ep2:
	movs	r0, #2
	movs	r1, #(EP_T_BULK | 2)
	mov	r2, #EP_RX_NAK
	bl	ep_init
	bl	ep2_arm
	pop	{r6, pc}
.Lri_ep3:
	movs	r0, #3
	movw	r1, #(EP_T_INTERRUPT | 3)
	movs	r2, #EP_TX_NAK
	bl	ep_init
	pop	{r6, pc}

	.thumb_func
	.type	ep_halt, %function
ep_halt:
	push	{r6, lr}
	ldrb	r1, [r5, #UO_HALT]
	orrs	r1, r1, r0
	strb	r1, [r5, #UO_HALT]
	cmp	r0, #HALT_EP2
	beq	.Lh_ep2
	cmp	r0, #HALT_EP3
	beq	.Lh_ep3
	movs	r0, #0				@ EP1: the packet is sent again after the halt
	strb	r0, [r5, #UO_EP1_BUSY]
	strb	r0, [r5, #UO_EP1_LEN]
	strb	r0, [r5, #UO_EP1_ZLP]
	movs	r0, #1
	movs	r1, #EP_TX_STALL
	bl	ep_tx
	pop	{r6, pc}
.Lh_ep2:
	movs	r0, #2
	mov	r1, #EP_RX_STALL
	bl	ep_rx
	pop	{r6, pc}
.Lh_ep3:
	movs	r0, #3
	movs	r1, #EP_TX_STALL
	bl	ep_tx
	pop	{r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ ep2_rx - EP2 OUT packet received: its bytes (count from CNT2_RX, at most 64) appended to the
@   RX ring, then ep2_arm. ep2_arm only armed EP2 with 64 bytes free, so they fit.
@ ep2_arm - EP2 RX VALID (CNT2_RX written again) when the RX ring has at least 64 bytes free
@   and EP2 is not halted; with less free space UO_EP2_PAUSED = 1 and EP2 stays NAK.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ep2_rx, %function
ep2_rx:
	push	{r6, lr}
	ldr	r0, =USB_PMA
	ldrh	r3, [r0, #(2 * BT_STRIDE + BT_CNT_RX)]
	ubfx	r3, r3, #0, #10			@ bytes received
	cmp	r3, #USB_EP_SIZE
	it	hi
	movhi	r3, #USB_EP_SIZE
	ldr	r0, =PMA_CPU_EP2_RX
	ldr	r1, =OWN_RX_RING
	ldr	r2, [r5, #UO_RX_HEAD]
	movw	r12, #(RX_RING_SIZE - 1)
	bl	pma_get
	str	r0, [r5, #UO_RX_HEAD]		@ index after the bytes: the reader sees them now
	pop	{r6, lr}
	@ falls through to ep2_arm

	.thumb_func
	.type	ep2_arm, %function
ep2_arm:
	ldrb	r0, [r5, #UO_HALT]
	tst	r0, #HALT_EP2
	bne	.La2_out			@ halted: stays STALL
	ldr	r0, [r5, #UO_RX_HEAD]
	ldr	r1, [r5, #UO_RX_TAIL]
	subs	r0, r0, r1
	ubfx	r0, r0, #0, #RX_BITS		@ bytes in the ring
	movw	r1, #(RX_RING_SIZE - 1)
	subs	r1, r1, r0			@ bytes free
	cmp	r1, #USB_EP_SIZE
	blo	.La2_pause
	movs	r0, #0
	strb	r0, [r5, #UO_EP2_PAUSED]
	ldr	r0, =USB_PMA
	movw	r1, #BT_RX_64
	strh	r1, [r0, #(2 * BT_STRIDE + BT_CNT_RX)]
	movs	r0, #2
	mov	r1, #EP_RX_VALID
	b	ep_rx
.La2_pause:
	movs	r0, #1
	strb	r0, [r5, #UO_EP2_PAUSED]
.La2_out:
	bx	lr

@ ----------------------------------------------------------------------------
@ ep1_done - EP1 packet gone: the ring tail moves past its bytes; UO_EP1_ZLP = 1 when it was a
@   full 64-byte packet (usb_kick closes the burst with a zero-length packet if no byte
@   follows); EP1 idle.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ep1_done, %function
ep1_done:
	ldrb	r0, [r5, #UO_EP1_LEN]
	ldr	r1, [r5, #UO_TX_TAIL]
	add	r1, r1, r0
	ubfx	r1, r1, #0, #TX_BITS
	str	r1, [r5, #UO_TX_TAIL]
	cmp	r0, #USB_EP_SIZE
	ite	eq
	moveq	r1, #1
	movne	r1, #0
	strb	r1, [r5, #UO_EP1_ZLP]
	movs	r1, #0
	strb	r1, [r5, #UO_EP1_LEN]
	strb	r1, [r5, #UO_EP1_BUSY]
	bx	lr

@ ----------------------------------------------------------------------------
@ usb_kick - end of every IRQ 20 run, configured only: EP2 re-armed when it waits and 64 bytes
@   are free; when EP1 is idle and not halted: the next packet (up to 64 bytes from the TX ring
@   tail), or the zero-length packet that closes a burst ending with a full packet.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	usb_kick, %function
usb_kick:
	push	{r6, lr}
	ldrb	r0, [r5, #UO_CONFIG]
	cmp	r0, #0
	beq	.Lk_out
	ldrb	r0, [r5, #UO_EP2_PAUSED]
	cmp	r0, #0
	beq	.Lk_tx
	bl	ep2_arm
.Lk_tx:
	ldrb	r0, [r5, #UO_EP1_BUSY]
	cmp	r0, #0
	bne	.Lk_out
	ldrb	r0, [r5, #UO_HALT]
	tst	r0, #HALT_EP1
	bne	.Lk_out
	ldr	r2, [r5, #UO_TX_TAIL]
	ldr	r3, [r5, #UO_TX_HEAD]
	subs	r3, r3, r2
	ubfx	r3, r3, #0, #TX_BITS		@ bytes waiting
	cmp	r3, #0
	bne	.Lk_send
	ldrb	r0, [r5, #UO_EP1_ZLP]
	cmp	r0, #0
	beq	.Lk_out				@ nothing to send
.Lk_send:
	cmp	r3, #USB_EP_SIZE
	it	hi
	movhi	r3, #USB_EP_SIZE		@ r3 = packet length (0 = zero-length packet)
	strb	r3, [r5, #UO_EP1_LEN]
	movs	r0, #0
	strb	r0, [r5, #UO_EP1_ZLP]
	movs	r0, #1
	strb	r0, [r5, #UO_EP1_BUSY]
	ldr	r0, =USB_PMA
	strh	r3, [r0, #(1 * BT_STRIDE + BT_CNT_TX)]
	ldr	r0, =PMA_CPU_EP1_TX
	ldr	r1, =OWN_TX_RING
	movw	r12, #(TX_RING_SIZE - 1)
	bl	pma_put				@ r2 = tail index, r3 = length
	movs	r0, #1
	movs	r1, #EP_TX_VALID
	bl	ep_tx
.Lk_out:
	pop	{r6, pc}

	.ltorg

@ ----------------------------------------------------------------------------
@ EP0 transfer routines (all end the interrupt's call: entered by b, return by bx lr).
@ ep0_stall - EP0 both directions STALL, state idle: the answer to an unsupported request (a
@   SETUP is still received, manual 19.4.4 note 2).
@ ep0_idle - EP0 RX VALID, TX NAK, state idle: the state after a completed transfer (manual
@   19.4.4 "Control transfer": after the Status stage the Rx direction is VALID, ready for a new
@   request, and the Tx direction NAK, so an IN that arrives before the next SETUP is handled is
@   answered NAK and repeated by the host, not STALL).
@ ep0_status_in - zero-length status IN armed (RX STALL), state E0_STATUS_IN.
@ ep0_recv - OUT data stage expected: RX VALID, TX NAK (manual 19.4.4: the status IN cannot
@   start before the data has arrived), state E0_OUT.
@ ep0_send(r0 = data, r1 = length) - IN data stage of min(length, wLength) bytes, packets of
@   64; ended by a short or zero-length packet when shorter than wLength. RX VALID during the
@   stage: the host may end it with the status OUT.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ep0_stall, %function
ep0_stall:
	movs	r0, #E0_IDLE
	strb	r0, [r5, #UO_EP0_STATE]
	movs	r0, #0
	movw	r1, #(EP_RX_STALL | EP_TX_STALL)
	b	ep_both

	.thumb_func
	.type	ep0_idle, %function
ep0_idle:
	movs	r0, #E0_IDLE
	strb	r0, [r5, #UO_EP0_STATE]
	movs	r0, #0
	movw	r1, #(EP_RX_VALID | EP_TX_NAK)
	b	ep_both

	.thumb_func
	.type	ep0_status_in, %function
ep0_status_in:
	movs	r0, #E0_STATUS_IN
	strb	r0, [r5, #UO_EP0_STATE]
	ldr	r0, =USB_PMA
	movs	r1, #0
	strh	r1, [r0, #(0 * BT_STRIDE + BT_CNT_TX)]
	movs	r0, #0
	movw	r1, #(EP_RX_STALL | EP_TX_VALID)
	b	ep_both

	.thumb_func
	.type	ep0_recv, %function
ep0_recv:
	movs	r0, #E0_OUT
	strb	r0, [r5, #UO_EP0_STATE]
	movs	r0, #0
	movw	r1, #(EP_RX_VALID | EP_TX_NAK)
	b	ep_both

	.thumb_func
	.type	ep0_send, %function
ep0_send:
	ldrh	r2, [r5, #(UO_SETUP + 6)]	@ wLength
	movs	r3, #0
	cmp	r1, r2
	ite	hs
	movhs	r1, r2				@ at most wLength bytes
	movlo	r3, #1				@ shorter: end with a short or empty packet
	str	r0, [r5, #UO_EP0_PTR]
	strh	r1, [r5, #UO_EP0_LEFT]
	strb	r3, [r5, #UO_EP0_ZLP]
	movs	r0, #E0_IN
	strb	r0, [r5, #UO_EP0_STATE]
	@ falls through to ep0_next

@ ep0_next - arms the next packet of the IN data stage. A packet shorter than 64 is the last.
	.thumb_func
	.type	ep0_next, %function
ep0_next:
	push	{r6, lr}
	ldr	r1, [r5, #UO_EP0_PTR]
	ldrh	r3, [r5, #UO_EP0_LEFT]
	cmp	r3, #USB_EP_SIZE
	blo	.Ln_short
	movs	r3, #USB_EP_SIZE
	b	.Ln_go
.Ln_short:
	movs	r0, #0
	strb	r0, [r5, #UO_EP0_ZLP]		@ this packet ends the stage
.Ln_go:
	ldrh	r0, [r5, #UO_EP0_LEFT]
	subs	r0, r0, r3
	strh	r0, [r5, #UO_EP0_LEFT]
	adds	r0, r1, r3
	str	r0, [r5, #UO_EP0_PTR]
	ldr	r0, =USB_PMA
	strh	r3, [r0, #(0 * BT_STRIDE + BT_CNT_TX)]
	ldr	r0, =PMA_CPU_EP0_TX
	movs	r2, #0
	mvn	r12, #0
	bl	pma_put				@ r1 = data, r3 = length
	pop	{r6, lr}
	movs	r0, #0
	movw	r1, #(EP_RX_VALID | EP_TX_VALID)
	b	ep_both

@ ----------------------------------------------------------------------------
@ ep0_in_done - EP0 IN packet gone. E0_IN: next packet, or (all sent) RX VALID / TX NAK for the
@   status OUT, state E0_STATUS_OUT. E0_STATUS_IN: a SET_ADDRESS address takes effect now
@   (as bootloader usb_09.s fn_08002d3c after the status stage), then idle.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ep0_in_done, %function
ep0_in_done:
	ldrb	r0, [r5, #UO_EP0_STATE]
	cmp	r0, #E0_IN
	beq	.Lid_in
	cmp	r0, #E0_STATUS_IN
	bne	.Lid_out
	ldrb	r0, [r5, #UO_ADDR]
	cmp	r0, #0
	beq	ep0_idle			@ transfer over
	str	r0, [r4, #USB_ADDR]		@ EFUC | new address
	movs	r0, #0
	strb	r0, [r5, #UO_ADDR]
	b	ep0_idle
.Lid_in:
	ldrh	r0, [r5, #UO_EP0_LEFT]
	ldrb	r1, [r5, #UO_EP0_ZLP]
	orrs	r0, r0, r1
	bne	ep0_next			@ more to send
	movs	r0, #E0_STATUS_OUT
	strb	r0, [r5, #UO_EP0_STATE]
	movs	r0, #0
	movw	r1, #(EP_RX_VALID | EP_TX_NAK)
	b	ep_both
.Lid_out:
	bx	lr

@ ----------------------------------------------------------------------------
@ ep0_out - EP0 OUT packet (not SETUP). E0_OUT: the line coding (exactly 7 bytes), then the
@   status IN. Any other state: the status OUT of an IN transfer, or an OUT nobody asked for:
@   idle.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ep0_out, %function
ep0_out:
	push	{r6, lr}
	ldr	r6, =USB_PMA
	ldrh	r3, [r6, #(0 * BT_STRIDE + BT_CNT_RX)]
	ubfx	r3, r3, #0, #10			@ bytes received
	movw	r0, #BT_RX_64
	strh	r0, [r6, #(0 * BT_STRIDE + BT_CNT_RX)]	@ buffer size written again
	ldrb	r0, [r5, #UO_EP0_STATE]
	cmp	r0, #E0_OUT
	bne	.Lo_end
	cmp	r3, #7
	bne	.Lo_end
	ldr	r0, =PMA_CPU_EP0_RX
	add	r1, r5, #UO_LINECODE
	movs	r2, #0
	mvn	r12, #0
	bl	pma_get
	pop	{r6, lr}
	b	ep0_status_in
.Lo_end:
	pop	{r6, lr}
	b	ep0_idle			@ status OUT done (or an OUT nobody asked for)

	.ltorg

@ ----------------------------------------------------------------------------
@ ep0_setup - SETUP packet on EP0 (8 bytes, else STALL): copied to UO_SETUP, a pending address
@   dropped, then dispatched. Entry of every request handler: r0 = bmRequestType,
@   r1 = bRequest; each ends in ep0_send, ep0_recv, ep0_status_in or ep0_stall.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ep0_setup, %function
ep0_setup:
	push	{r6, lr}
	ldr	r6, =USB_PMA
	ldrh	r3, [r6, #(0 * BT_STRIDE + BT_CNT_RX)]
	ubfx	r3, r3, #0, #10			@ bytes received
	movw	r0, #BT_RX_64
	strh	r0, [r6, #(0 * BT_STRIDE + BT_CNT_RX)]	@ buffer size written again
	movs	r0, #0
	strb	r0, [r5, #UO_ADDR]
	strb	r0, [r5, #UO_EP0_STATE]
	cmp	r3, #8
	bne	.Lsu_bad
	ldr	r0, =PMA_CPU_EP0_RX
	add	r1, r5, #UO_SETUP
	movs	r2, #0
	mvn	r12, #0
	bl	pma_get
	pop	{r6, lr}
	ldrb	r0, [r5, #UO_SETUP]		@ bmRequestType
	ldrb	r1, [r5, #(UO_SETUP + 1)]	@ bRequest
	and	r2, r0, #0x60			@ type: 0 standard, 0x20 class
	cmp	r2, #0x20
	beq	.Lsu_class
	cmp	r2, #0
	bne	ep0_stall
	cmp	r1, #REQ_GET_STATUS
	beq	rq_get_status
	cmp	r1, #REQ_CLEAR_FEATURE
	beq	rq_feature
	cmp	r1, #REQ_SET_FEATURE
	beq	rq_feature
	cmp	r1, #REQ_SET_ADDRESS
	beq	rq_set_address
	cmp	r1, #REQ_GET_DESCRIPTOR
	beq	rq_get_descriptor
	cmp	r1, #REQ_GET_CONFIGURATION
	beq	rq_get_config
	cmp	r1, #REQ_SET_CONFIGURATION
	beq	rq_set_config
	cmp	r1, #REQ_GET_INTERFACE
	beq	rq_get_interface
	cmp	r1, #REQ_SET_INTERFACE
	beq	rq_set_interface
	b	ep0_stall
.Lsu_bad:
	pop	{r6, lr}
	b	ep0_stall
@ CDC requests: interface 0 only
.Lsu_class:
	ldrh	r3, [r5, #(UO_SETUP + 4)]	@ wIndex
	cmp	r3, #0
	bne	ep0_stall
	ldrh	r2, [r5, #(UO_SETUP + 6)]	@ wLength
	cmp	r1, #CDC_SET_LINE_CODING
	beq	.Lcl_set
	cmp	r1, #CDC_GET_LINE_CODING
	beq	.Lcl_get
	cmp	r1, #CDC_SET_CONTROL_LINE_STATE
	bne	ep0_stall
	cmp	r0, #0x21
	bne	ep0_stall
	cmp	r2, #0
	bne	ep0_stall
	ldrb	r2, [r5, #(UO_SETUP + 2)]	@ wValue: bit 0 DTR, bit 1 RTS
	strb	r2, [r5, #UO_LINE]
	b	ep0_status_in
.Lcl_set:
	cmp	r0, #0x21
	bne	ep0_stall
	cmp	r2, #7
	bne	ep0_stall
	b	ep0_recv
.Lcl_get:
	cmp	r0, #0xA1
	bne	ep0_stall
	add	r0, r5, #UO_LINECODE
	movs	r1, #7
	b	ep0_send

@ ----------------------------------------------------------------------------
@ ep_bit(r0 = endpoint address) -> r0 = 1 << number for 0x81, 0x02, 0x83, else 0. Uses r1.
@ ----------------------------------------------------------------------------
	.thumb_func
	.type	ep_bit, %function
ep_bit:
	cmp	r0, #0x81
	beq	.Lbit_ok
	cmp	r0, #0x02
	beq	.Lbit_ok
	cmp	r0, #0x83
	beq	.Lbit_ok
	movs	r0, #0
	bx	lr
.Lbit_ok:
	and	r0, r0, #0xF
	movs	r1, #1
	lsl	r0, r1, r0
	bx	lr

@ ----------------------------------------------------------------------------
@ Standard request handlers (USB 2.0 9.4). r0 = bmRequestType, r1 = bRequest.
@ ----------------------------------------------------------------------------

@ GET_STATUS: device 0x0001 (self powered, no remote wake-up); interface 0 / 1 (configured)
@ 0x0000; endpoint 0 0x0000; endpoint 0x81 / 0x02 / 0x83 (configured) its halt bit.
	.thumb_func
	.type	rq_get_status, %function
rq_get_status:
	ldrh	r3, [r5, #(UO_SETUP + 4)]	@ wIndex
	cmp	r0, #0x80
	beq	.Lgs_dev
	cmp	r0, #0x81
	beq	.Lgs_if
	cmp	r0, #0x82
	bne	ep0_stall
	tst	r3, #0x7F
	beq	.Lgs_zero			@ endpoint 0 (0x00 / 0x80)
	ldrb	r2, [r5, #UO_CONFIG]
	cmp	r2, #0
	beq	ep0_stall
	push	{r6, lr}
	mov	r0, r3
	bl	ep_bit
	pop	{r6, lr}
	cmp	r0, #0
	beq	ep0_stall
	ldrb	r1, [r5, #UO_HALT]
	tst	r1, r0
	ite	ne
	movne	r2, #1
	moveq	r2, #0
	b	.Lgs_reply
.Lgs_if:
	ldrb	r2, [r5, #UO_CONFIG]
	cmp	r2, #0
	beq	ep0_stall
	cmp	r3, #2
	bhs	ep0_stall
.Lgs_zero:
	movs	r2, #0
	b	.Lgs_reply
.Lgs_dev:
	movs	r2, #1
.Lgs_reply:
	strh	r2, [r5, #UO_REPLY]
	add	r0, r5, #UO_REPLY
	movs	r1, #2
	b	ep0_send

@ CLEAR_FEATURE / SET_FEATURE: ENDPOINT_HALT (wValue 0) of 0x81, 0x02, 0x83 while configured.
@ Device features (remote wake-up, test mode) are not offered: STALL.
	.thumb_func
	.type	rq_feature, %function
rq_feature:
	cmp	r0, #0x02
	bne	ep0_stall
	ldrh	r2, [r5, #(UO_SETUP + 2)]	@ wValue
	cmp	r2, #0
	bne	ep0_stall
	ldrb	r2, [r5, #UO_CONFIG]
	cmp	r2, #0
	beq	ep0_stall
	push	{r6, lr}
	mov	r6, r1				@ r6 = bRequest
	ldrh	r0, [r5, #(UO_SETUP + 4)]	@ wIndex: endpoint address
	bl	ep_bit
	cmp	r0, #0
	beq	.Lft_stall
	cmp	r6, #REQ_SET_FEATURE
	beq	.Lft_set
	bl	ep_reinit			@ clear: DATA0, halt off
	b	.Lft_ok
.Lft_set:
	bl	ep_halt
.Lft_ok:
	pop	{r6, lr}
	b	ep0_status_in
.Lft_stall:
	pop	{r6, lr}
	b	ep0_stall

@ SET_ADDRESS: address 0..127, kept until the status stage is done (ep0_in_done).
	.thumb_func
	.type	rq_set_address, %function
rq_set_address:
	cmp	r0, #0x00
	bne	ep0_stall
	ldrh	r2, [r5, #(UO_SETUP + 2)]	@ wValue
	cmp	r2, #0x7F
	bhi	ep0_stall
	orr	r2, r2, #USB_ADDR_EFUC
	strb	r2, [r5, #UO_ADDR]
	b	ep0_status_in

@ GET_DESCRIPTOR: device, configuration 0, string 0..3; anything else (device qualifier
@ included: a full-speed-only device answers it with a request error, USB 2.0 9.6.2) STALL.
	.thumb_func
	.type	rq_get_descriptor, %function
rq_get_descriptor:
	cmp	r0, #0x80
	bne	ep0_stall
	ldrb	r2, [r5, #(UO_SETUP + 3)]	@ descriptor type
	ldrb	r3, [r5, #(UO_SETUP + 2)]	@ descriptor index
	cmp	r2, #1
	beq	.Lgd_dev
	cmp	r2, #2
	beq	.Lgd_cfg
	cmp	r2, #3
	bne	ep0_stall
	cmp	r3, #4
	bhs	ep0_stall
	ldr	r0, =string_table
	ldr	r0, [r0, r3, lsl #2]
	ldrb	r1, [r0]			@ bLength
	b	ep0_send
.Lgd_dev:
	ldr	r0, =desc_device
	movs	r1, #DESC_DEVICE_LEN
	b	ep0_send
.Lgd_cfg:
	cmp	r3, #0
	bne	ep0_stall
	ldr	r0, =desc_config
	movs	r1, #DESC_CONFIG_LEN
	b	ep0_send

@ GET_CONFIGURATION: one byte, 0 or 1.
	.thumb_func
	.type	rq_get_config, %function
rq_get_config:
	cmp	r0, #0x80
	bne	ep0_stall
	ldrb	r2, [r5, #UO_CONFIG]
	@ falls through to reply_byte

@ reply_byte(r2 = value) - one-byte IN data stage.
reply_byte:
	strh	r2, [r5, #UO_REPLY]
	add	r0, r5, #UO_REPLY
	movs	r1, #1
	b	ep0_send

@ SET_CONFIGURATION: 1 sets EP1..3 up with DATA0 (and arms EP2), 0 turns them off.
	.thumb_func
	.type	rq_set_config, %function
rq_set_config:
	cmp	r0, #0x00
	bne	ep0_stall
	ldrh	r2, [r5, #(UO_SETUP + 2)]	@ wValue
	cmp	r2, #1
	bhi	ep0_stall
	push	{r6, lr}
	cmp	r2, #0
	beq	.Lsc_off
	movs	r0, #1
	strb	r0, [r5, #UO_CONFIG]
	movs	r0, #HALT_EP1
	bl	ep_reinit
	movs	r0, #HALT_EP2
	bl	ep_reinit
	movs	r0, #HALT_EP3
	bl	ep_reinit
	b	.Lsc_done
.Lsc_off:
	bl	cfg_off
.Lsc_done:
	pop	{r6, lr}
	b	ep0_status_in

@ GET_INTERFACE: interface 0 / 1 while configured: alternate setting 0.
	.thumb_func
	.type	rq_get_interface, %function
rq_get_interface:
	cmp	r0, #0x81
	bne	ep0_stall
	ldrb	r2, [r5, #UO_CONFIG]
	cmp	r2, #0
	beq	ep0_stall
	ldrh	r3, [r5, #(UO_SETUP + 4)]	@ wIndex
	cmp	r3, #2
	bhs	ep0_stall
	movs	r2, #0
	b	reply_byte

@ SET_INTERFACE: alternate setting 0 of interface 0 / 1 while configured; the interface's
@ endpoints restart with DATA0 (interface 0: EP3, interface 1: EP1 and EP2).
	.thumb_func
	.type	rq_set_interface, %function
rq_set_interface:
	cmp	r0, #0x01
	bne	ep0_stall
	ldrb	r2, [r5, #UO_CONFIG]
	cmp	r2, #0
	beq	ep0_stall
	ldrh	r2, [r5, #(UO_SETUP + 2)]	@ wValue: alternate setting
	cmp	r2, #0
	bne	ep0_stall
	ldrh	r3, [r5, #(UO_SETUP + 4)]	@ wIndex
	cmp	r3, #2
	bhs	ep0_stall
	push	{r6, lr}
	cmp	r3, #0
	beq	.Lsi_if0
	movs	r0, #HALT_EP1
	bl	ep_reinit
	movs	r0, #HALT_EP2
	bl	ep_reinit
	b	.Lsi_done
.Lsi_if0:
	movs	r0, #HALT_EP3
	bl	ep_reinit
.Lsi_done:
	pop	{r6, lr}
	b	ep0_status_in

	.ltorg

@ ----------------------------------------------------------------------------
@ Main-loop functions (see the header for the conventions).
@ ----------------------------------------------------------------------------

@ usb_rx_get() -> r0 = next byte or -1. When EP2 waits and the ring now has 64 bytes free,
@   IRQ 20 is pended: the interrupt re-arms EP2 (usb_kick).
	.global	usb_rx_get
	.thumb_func
	.type	usb_rx_get, %function
usb_rx_get:
	ldr	r3, =OWN_USB
	ldr	r1, [r3, #UO_RX_TAIL]
	ldr	r2, [r3, #UO_RX_HEAD]
	cmp	r1, r2
	beq	.Lrg_none
	ldr	r12, =OWN_RX_RING
	ldrb	r0, [r12, r1]			@ the byte, before the index moves
	adds	r1, r1, #1
	ubfx	r1, r1, #0, #RX_BITS
	str	r1, [r3, #UO_RX_TAIL]
	ldrb	r12, [r3, #UO_EP2_PAUSED]
	cmp	r12, #0
	beq	.Lrg_out
	subs	r2, r2, r1
	ubfx	r2, r2, #0, #RX_BITS		@ bytes still in the ring
	movw	r12, #(RX_RING_SIZE - 1 - USB_EP_SIZE)
	cmp	r2, r12
	bhi	.Lrg_out			@ less than 64 free
	ldr	r1, =NVIC_ISPR0
	mov	r2, #(1 << IRQ_USB_LP)
	str	r2, [r1]
.Lrg_out:
	bx	lr
.Lrg_none:
	mvn	r0, #0				@ -1: empty
	bx	lr

@ usb_rx_count() -> r0 = bytes in the RX ring.
	.global	usb_rx_count
	.thumb_func
	.type	usb_rx_count, %function
usb_rx_count:
	ldr	r3, =OWN_USB
	ldr	r0, [r3, #UO_RX_HEAD]
	ldr	r1, [r3, #UO_RX_TAIL]
	subs	r0, r0, r1
	ubfx	r0, r0, #0, #RX_BITS
	bx	lr

@ usb_tx_put(r0 = source, r1 = length) -> r0 = bytes taken. Copies them behind the TX ring
@   head, moves the head, pends IRQ 20 (the interrupt starts EP1 when it is idle).
	.global	usb_tx_put
	.thumb_func
	.type	usb_tx_put, %function
usb_tx_put:
	push	{r4, r5, r6, lr}
	ldr	r5, =OWN_USB
	ldr	r2, [r5, #UO_TX_HEAD]
	ldr	r3, [r5, #UO_TX_TAIL]
	subs	r3, r2, r3
	ubfx	r3, r3, #0, #TX_BITS		@ bytes in the ring
	movw	r12, #(TX_RING_SIZE - 1)
	sub	r3, r12, r3			@ bytes free
	cmp	r1, r3
	it	hi
	movhi	r1, r3				@ r1 = bytes taken
	mov	r6, r1
	cmp	r1, #0
	beq	.Ltp_out
	ldr	r4, =OWN_TX_RING
.Ltp_copy:
	ldrb	r3, [r0], #1
	strb	r3, [r4, r2]
	adds	r2, r2, #1
	and	r2, r2, r12
	subs	r1, r1, #1
	bne	.Ltp_copy
	str	r2, [r5, #UO_TX_HEAD]		@ after the bytes: the interrupt sees them now
	ldr	r0, =NVIC_ISPR0
	mov	r1, #(1 << IRQ_USB_LP)
	str	r1, [r0]
.Ltp_out:
	mov	r0, r6
	pop	{r4, r5, r6, pc}

@ usb_tx_free() -> r0 = bytes the TX ring can take (8191 when empty).
	.global	usb_tx_free
	.thumb_func
	.type	usb_tx_free, %function
usb_tx_free:
	ldr	r3, =OWN_USB
	ldr	r0, [r3, #UO_TX_HEAD]
	ldr	r1, [r3, #UO_TX_TAIL]
	subs	r0, r0, r1
	ubfx	r0, r0, #0, #TX_BITS		@ bytes in the ring
	movw	r1, #(TX_RING_SIZE - 1)
	sub	r0, r1, r0
	bx	lr

@ usb_tx_empty() -> r0 = 1 when nothing is left to send: ring empty (its tail moves only when a
@   packet has gone), no zero-length packet in flight or due.
	.global	usb_tx_empty
	.thumb_func
	.type	usb_tx_empty, %function
usb_tx_empty:
	ldr	r3, =OWN_USB
	ldr	r0, [r3, #UO_TX_HEAD]
	ldr	r1, [r3, #UO_TX_TAIL]
	cmp	r0, r1
	bne	.Lte_no
	ldrb	r0, [r3, #UO_EP1_BUSY]
	ldrb	r1, [r3, #UO_EP1_ZLP]
	orrs	r0, r0, r1
	bne	.Lte_no
	movs	r0, #1
	bx	lr
.Lte_no:
	movs	r0, #0
	bx	lr

@ usb_dtr() -> r0 = DTR bit.
	.global	usb_dtr
	.thumb_func
	.type	usb_dtr, %function
usb_dtr:
	ldr	r3, =OWN_USB
	ldrb	r0, [r3, #UO_LINE]
	and	r0, r0, #1
	bx	lr

@ usb_reserve(r0 = USB_RES_OFF / USB_RES_ON / USB_RES_QUERY) -> r0 = reservation (0 / 1).
	.global	usb_reserve
	.thumb_func
	.type	usb_reserve, %function
usb_reserve:
	ldr	r3, =OWN_USB
	cmp	r0, #USB_RES_QUERY
	beq	.Lrs_query
	cmp	r0, #USB_RES_OFF
	it	ne
	movne	r0, #USB_RES_ON
	strb	r0, [r3, #UO_RESERVE]
.Lrs_query:
	ldrb	r0, [r3, #UO_RESERVE]
	bx	lr

	.ltorg
