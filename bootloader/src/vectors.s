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
@ ----------------------------------------------------------------------------
	.section .vectors,"a",%progbits
	.global vectors
vectors:
	.word 0x20002028		@ 0 initial main stack pointer (top of the bootloader stack in RAM)
	.word reset_handler		@ 1 Reset
	.word nmi_handler		@ 2 NMI
	.word hardfault_handler		@ 3 HardFault
	.word memmanage_handler		@ 4 MemManage
	.word busfault_handler		@ 5 BusFault
	.word usagefault_handler	@ 6 UsageFault
	.word 0x00000000		@ 7 reserved
	.word 0x00000000		@ 8 reserved
	.word 0x00000000		@ 9 reserved
	.word 0x00000000		@ 10 reserved
	.word svc_handler		@ 11 SVCall
	.word debugmon_handler		@ 12 DebugMonitor
	.word 0x00000000		@ 13 reserved
	.word pendsv_handler		@ 14 PendSV
	.word systick_handler		@ 15 SysTick
	.word default_handler		@ 16 external interrupt 0
	.word default_handler		@ 17 external interrupt 1
	.word default_handler		@ 18 external interrupt 2
	.word default_handler		@ 19 external interrupt 3
	.word default_handler		@ 20 external interrupt 4
	.word default_handler		@ 21 external interrupt 5
	.word default_handler		@ 22 external interrupt 6
	.word default_handler		@ 23 external interrupt 7
	.word default_handler		@ 24 external interrupt 8
	.word default_handler		@ 25 external interrupt 9
	.word default_handler		@ 26 external interrupt 10
	.word default_handler		@ 27 external interrupt 11
	.word default_handler		@ 28 external interrupt 12
	.word default_handler		@ 29 external interrupt 13
	.word default_handler		@ 30 external interrupt 14
	.word default_handler		@ 31 external interrupt 15
	.word default_handler		@ 32 external interrupt 16
	.word default_handler		@ 33 external interrupt 17
	.word default_handler		@ 34 external interrupt 18
	.word default_handler		@ 35 external interrupt 19
	.word irq20_handler		@ 36 external interrupt 20
	.word default_handler		@ 37 external interrupt 21
	.word default_handler		@ 38 external interrupt 22
	.word default_handler		@ 39 external interrupt 23
	.word default_handler		@ 40 external interrupt 24
	.word default_handler		@ 41 external interrupt 25
	.word default_handler		@ 42 external interrupt 26
	.word default_handler		@ 43 external interrupt 27
	.word default_handler		@ 44 external interrupt 28
	.word default_handler		@ 45 external interrupt 29
	.word default_handler		@ 46 external interrupt 30
	.word default_handler		@ 47 external interrupt 31
	.word default_handler		@ 48 external interrupt 32
	.word default_handler		@ 49 external interrupt 33
	.word default_handler		@ 50 external interrupt 34
	.word default_handler		@ 51 external interrupt 35
	.word default_handler		@ 52 external interrupt 36
	.word default_handler		@ 53 external interrupt 37
	.word default_handler		@ 54 external interrupt 38
	.word default_handler		@ 55 external interrupt 39
	.word default_handler		@ 56 external interrupt 40
	.word default_handler		@ 57 external interrupt 41
	.word irq42_handler		@ 58 external interrupt 42
	.word default_handler		@ 59 external interrupt 43
	.word default_handler		@ 60 external interrupt 44
	.word default_handler		@ 61 external interrupt 45
	.word default_handler		@ 62 external interrupt 46
	.word default_handler		@ 63 external interrupt 47
	.word default_handler		@ 64 external interrupt 48
	.word default_handler		@ 65 external interrupt 49
	.word default_handler		@ 66 external interrupt 50
	.word default_handler		@ 67 external interrupt 51
	.word default_handler		@ 68 external interrupt 52
	.word default_handler		@ 69 external interrupt 53
	.word default_handler		@ 70 external interrupt 54
	.word default_handler		@ 71 external interrupt 55
	.word default_handler		@ 72 external interrupt 56
	.word default_handler		@ 73 external interrupt 57
	.word default_handler		@ 74 external interrupt 58
	.word default_handler		@ 75 external interrupt 59
	.word default_handler		@ 76 external interrupt 60
	.word default_handler		@ 77 external interrupt 61
	.word default_handler		@ 78 external interrupt 62
	.word default_handler		@ 79 external interrupt 63
	.word default_handler		@ 80 external interrupt 64
	.word default_handler		@ 81 external interrupt 65
	.word default_handler		@ 82 external interrupt 66
	.word default_handler		@ 83 external interrupt 67
	.word default_handler		@ 84 external interrupt 68
	.word default_handler		@ 85 external interrupt 69
	.word default_handler		@ 86 external interrupt 70
	.word default_handler		@ 87 external interrupt 71
	.word default_handler		@ 88 external interrupt 72
	.word default_handler		@ 89 external interrupt 73
	.word default_handler		@ 90 external interrupt 74
	.word default_handler		@ 91 external interrupt 75
	.word default_handler		@ 92 external interrupt 76
	.word default_handler		@ 93 external interrupt 77
	.word default_handler		@ 94 external interrupt 78
	.word default_handler		@ 95 external interrupt 79
	.word default_handler		@ 96 external interrupt 80
	.word default_handler		@ 97 external interrupt 81
	.word default_handler		@ 98 external interrupt 82
	.word default_handler		@ 99 external interrupt 83
	.word default_handler		@ 100 external interrupt 84
	.word default_handler		@ 101 external interrupt 85
