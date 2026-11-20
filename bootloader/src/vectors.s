@ vectors.s - Cortex-M4 exception and interrupt vector table of the bootloader (102 words)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the stock bootloader (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ vectors - vector table at the start of flash (0x08000000..0x08000197).
@ Word 0 is the initial main stack pointer, words 1..15 are the system
@ exception entries (Reset, NMI, HardFault, MemManage, BusFault, UsageFault,
@ SVCall, DebugMonitor, PendSV, SysTick; the reserved slots hold zero), words
@ 16..101 are external interrupts 0..85. Only external interrupts 20 and 42
@ have their own handlers; every other external interrupt points at
@ default_handler. Code entries carry the Thumb bit (bit 0 set).
@ Slot build: the four fault vectors, PendSV and every vector that points at
@ default_handler point at slot_fault instead (it sets the starter's fault
@ flag and resets; the stock handlers end in an endless loop).
@ ----------------------------------------------------------------------------
.ifdef SLOT
	.set	unused_vector, slot_fault
.else
	.set	unused_vector, default_handler
.endif
	.section .vectors,"a",%progbits
	.global vectors
vectors:
	.word 0x20002028		@ 0 initial main stack pointer (top of the bootloader stack in RAM)
	.word reset_handler		@ 1 Reset
	.word nmi_handler		@ 2 NMI
.ifdef SLOT
	.word slot_fault		@ 3 HardFault
	.word slot_fault		@ 4 MemManage
	.word slot_fault		@ 5 BusFault
	.word slot_fault		@ 6 UsageFault
.else
	.word hardfault_handler		@ 3 HardFault
	.word memmanage_handler		@ 4 MemManage
	.word busfault_handler		@ 5 BusFault
	.word usagefault_handler	@ 6 UsageFault
.endif
	.word 0x00000000		@ 7 reserved
	.word 0x00000000		@ 8 reserved
	.word 0x00000000		@ 9 reserved
	.word 0x00000000		@ 10 reserved
	.word svc_handler		@ 11 SVCall
	.word debugmon_handler		@ 12 DebugMonitor
	.word 0x00000000		@ 13 reserved
.ifdef SLOT
	.word slot_fault		@ 14 PendSV
.else
	.word pendsv_handler		@ 14 PendSV
.endif
	.word systick_handler		@ 15 SysTick
	.word unused_vector		@ 16 external interrupt 0
	.word unused_vector		@ 17 external interrupt 1
	.word unused_vector		@ 18 external interrupt 2
	.word unused_vector		@ 19 external interrupt 3
	.word unused_vector		@ 20 external interrupt 4
	.word unused_vector		@ 21 external interrupt 5
	.word unused_vector		@ 22 external interrupt 6
	.word unused_vector		@ 23 external interrupt 7
	.word unused_vector		@ 24 external interrupt 8
	.word unused_vector		@ 25 external interrupt 9
	.word unused_vector		@ 26 external interrupt 10
	.word unused_vector		@ 27 external interrupt 11
	.word unused_vector		@ 28 external interrupt 12
	.word unused_vector		@ 29 external interrupt 13
	.word unused_vector		@ 30 external interrupt 14
	.word unused_vector		@ 31 external interrupt 15
	.word unused_vector		@ 32 external interrupt 16
	.word unused_vector		@ 33 external interrupt 17
	.word unused_vector		@ 34 external interrupt 18
	.word unused_vector		@ 35 external interrupt 19
	.word irq20_handler		@ 36 external interrupt 20
	.word unused_vector		@ 37 external interrupt 21
	.word unused_vector		@ 38 external interrupt 22
	.word unused_vector		@ 39 external interrupt 23
	.word unused_vector		@ 40 external interrupt 24
	.word unused_vector		@ 41 external interrupt 25
	.word unused_vector		@ 42 external interrupt 26
	.word unused_vector		@ 43 external interrupt 27
	.word unused_vector		@ 44 external interrupt 28
	.word unused_vector		@ 45 external interrupt 29
	.word unused_vector		@ 46 external interrupt 30
	.word unused_vector		@ 47 external interrupt 31
	.word unused_vector		@ 48 external interrupt 32
	.word unused_vector		@ 49 external interrupt 33
	.word unused_vector		@ 50 external interrupt 34
	.word unused_vector		@ 51 external interrupt 35
	.word unused_vector		@ 52 external interrupt 36
	.word unused_vector		@ 53 external interrupt 37
	.word unused_vector		@ 54 external interrupt 38
	.word unused_vector		@ 55 external interrupt 39
	.word unused_vector		@ 56 external interrupt 40
	.word unused_vector		@ 57 external interrupt 41
	.word irq42_handler		@ 58 external interrupt 42
	.word unused_vector		@ 59 external interrupt 43
	.word unused_vector		@ 60 external interrupt 44
	.word unused_vector		@ 61 external interrupt 45
	.word unused_vector		@ 62 external interrupt 46
	.word unused_vector		@ 63 external interrupt 47
	.word unused_vector		@ 64 external interrupt 48
	.word unused_vector		@ 65 external interrupt 49
	.word unused_vector		@ 66 external interrupt 50
	.word unused_vector		@ 67 external interrupt 51
	.word unused_vector		@ 68 external interrupt 52
	.word unused_vector		@ 69 external interrupt 53
	.word unused_vector		@ 70 external interrupt 54
	.word unused_vector		@ 71 external interrupt 55
	.word unused_vector		@ 72 external interrupt 56
	.word unused_vector		@ 73 external interrupt 57
	.word unused_vector		@ 74 external interrupt 58
	.word unused_vector		@ 75 external interrupt 59
	.word unused_vector		@ 76 external interrupt 60
	.word unused_vector		@ 77 external interrupt 61
	.word unused_vector		@ 78 external interrupt 62
	.word unused_vector		@ 79 external interrupt 63
	.word unused_vector		@ 80 external interrupt 64
	.word unused_vector		@ 81 external interrupt 65
	.word unused_vector		@ 82 external interrupt 66
	.word unused_vector		@ 83 external interrupt 67
	.word unused_vector		@ 84 external interrupt 68
	.word unused_vector		@ 85 external interrupt 69
	.word unused_vector		@ 86 external interrupt 70
	.word unused_vector		@ 87 external interrupt 71
	.word unused_vector		@ 88 external interrupt 72
	.word unused_vector		@ 89 external interrupt 73
	.word unused_vector		@ 90 external interrupt 74
	.word unused_vector		@ 91 external interrupt 75
	.word unused_vector		@ 92 external interrupt 76
	.word unused_vector		@ 93 external interrupt 77
	.word unused_vector		@ 94 external interrupt 78
	.word unused_vector		@ 95 external interrupt 79
	.word unused_vector		@ 96 external interrupt 80
	.word unused_vector		@ 97 external interrupt 81
	.word unused_vector		@ 98 external interrupt 82
	.word unused_vector		@ 99 external interrupt 83
	.word unused_vector		@ 100 external interrupt 84
	.word unused_vector		@ 101 external interrupt 85
