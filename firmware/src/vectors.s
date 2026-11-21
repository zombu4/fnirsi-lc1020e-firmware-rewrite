@ vectors.s - exception and interrupt vector table of the application (102 words at 0x08006000)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
@ Word 0 is the initial stack pointer, words 1..15 are the Cortex-M exception entries, words
@ 16..101 are external interrupts 0..85 (names from the N32G455 user manual vector table).
@ Handler addresses carry bit 0 set (Thumb), as the symbols are Thumb functions.
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.section .vectors,"a",%progbits
	.global vectors
vectors:
	.word 0x200163a8              @ 0  initial stack pointer
	.word Reset_Handler           @ 1  Reset
	.word fn_0800ad50             @ 2  NMI
	.word fn_08009358             @ 3  HardFault
	.word fn_0800ad34             @ 4  MemManage
	.word fn_0800835c             @ 5  BusFault
	.word fn_08010158             @ 6  UsageFault
	.word 0x00000000              @ 7  reserved
	.word 0x00000000              @ 8  reserved
	.word 0x00000000              @ 9  reserved
	.word 0x00000000              @ 10 reserved
	.word fn_0800b9d4             @ 11 SVCall
	.word fn_08008c5c             @ 12 DebugMonitor
	.word 0x00000000              @ 13 reserved
	.word branch_to_self_08006286 @ 14 PendSV
	.word systick_handler         @ 15 SysTick
	.word branch_to_self_0800628a @ 16 external interrupt 0 (WWDG)
	.word branch_to_self_0800628a @ 17 external interrupt 1 (PVD)
	.word branch_to_self_0800628a @ 18 external interrupt 2 (TAMPER)
	.word branch_to_self_0800628a @ 19 external interrupt 3 (RTC_WKUP)
	.word branch_to_self_0800628a @ 20 external interrupt 4 (FLASH)
	.word branch_to_self_0800628a @ 21 external interrupt 5 (RCC)
	.word branch_to_self_0800628a @ 22 external interrupt 6 (EXTI0)
	.word branch_to_self_0800628a @ 23 external interrupt 7 (EXTI1)
	.word branch_to_self_0800628a @ 24 external interrupt 8 (EXTI2)
	.word branch_to_self_0800628a @ 25 external interrupt 9 (EXTI3)
	.word branch_to_self_0800628a @ 26 external interrupt 10 (EXTI4)
	.word branch_to_self_0800628a @ 27 external interrupt 11 (DMA1)
	.word branch_to_self_0800628a @ 28 external interrupt 12 (DMA1)
	.word branch_to_self_0800628a @ 29 external interrupt 13 (DMA1)
	.word branch_to_self_0800628a @ 30 external interrupt 14 (DMA1)
	.word branch_to_self_0800628a @ 31 external interrupt 15 (DMA1)
	.word branch_to_self_0800628a @ 32 external interrupt 16 (DMA1)
	.word branch_to_self_0800628a @ 33 external interrupt 17 (DMA1)
	.word branch_to_self_0800628a @ 34 external interrupt 18 (ADC1_2)
	.word branch_to_self_0800628a @ 35 external interrupt 19 (USB_HP_CAN1_TX)
.ifdef OWN
	.word usb_irq20_handler       @ 36 external interrupt 20 (USB_LP): own/usb.s
.else
	.word fn_0800fe80             @ 36 external interrupt 20 (USB_LP_CAN1_RX0)
.endif
	.word branch_to_self_0800628a @ 37 external interrupt 21 (CAN1_RX1)
	.word branch_to_self_0800628a @ 38 external interrupt 22 (CAN_SCE)
	.word branch_to_self_0800628a @ 39 external interrupt 23 (EXTI9_5)
	.word branch_to_self_0800628a @ 40 external interrupt 24 (TIM1_BRK)
	.word branch_to_self_0800628a @ 41 external interrupt 25 (TIM1_UP)
	.word branch_to_self_0800628a @ 42 external interrupt 26 (TIM1_TRG_COM)
	.word branch_to_self_0800628a @ 43 external interrupt 27 (TIM1_CC)
	.word branch_to_self_0800628a @ 44 external interrupt 28 (TIM2)
	.word branch_to_self_0800628a @ 45 external interrupt 29 (TIM3)
	.word branch_to_self_0800628a @ 46 external interrupt 30 (TIM4)
	.word branch_to_self_0800628a @ 47 external interrupt 31 (I2C1_EV)
	.word branch_to_self_0800628a @ 48 external interrupt 32 (I2C1_ER)
	.word branch_to_self_0800628a @ 49 external interrupt 33 (I2C2_EV)
	.word branch_to_self_0800628a @ 50 external interrupt 34 (I2C2_ER)
	.word branch_to_self_0800628a @ 51 external interrupt 35 (SPI1)
	.word branch_to_self_0800628a @ 52 external interrupt 36 (SPI2_I2S2)
	.word branch_to_self_0800628a @ 53 external interrupt 37 (USART1)
	.word branch_to_self_0800628a @ 54 external interrupt 38 (USART2)
	.word branch_to_self_0800628a @ 55 external interrupt 39 (USART3)
	.word branch_to_self_0800628a @ 56 external interrupt 40 (EXTI15_10)
	.word branch_to_self_0800628a @ 57 external interrupt 41 (RTCAlarm)
.ifdef OWN
	.word usb_irq42_handler       @ 58 external interrupt 42 (USBWKUP): own/usb.s
.else
	.word fn_0800fb40             @ 58 external interrupt 42 (USBWKUP)
.endif
	.word branch_to_self_0800628a @ 59 external interrupt 43 (TIM8_BRK)
	.word branch_to_self_0800628a @ 60 external interrupt 44 (TIM8_UP)
	.word branch_to_self_0800628a @ 61 external interrupt 45 (TIM8_TRG_COM)
	.word branch_to_self_0800628a @ 62 external interrupt 46 (TIM8_CC)
	.word branch_to_self_0800628a @ 63 external interrupt 47 (ADC3_4)
	.word branch_to_self_0800628a @ 64 external interrupt 48 (reserved)
	.word branch_to_self_0800628a @ 65 external interrupt 49 (SDIO)
	.word branch_to_self_0800628a @ 66 external interrupt 50 (TIM5)
	.word branch_to_self_0800628a @ 67 external interrupt 51 (SPI3_I2S3)
	.word branch_to_self_0800628a @ 68 external interrupt 52 (UART4)
	.word branch_to_self_0800628a @ 69 external interrupt 53 (UART5)
	.word branch_to_self_0800628a @ 70 external interrupt 54 (TIM6)
	.word branch_to_self_0800628a @ 71 external interrupt 55 (TIM7)
	.word branch_to_self_0800628a @ 72 external interrupt 56 (DMA2)
	.word branch_to_self_0800628a @ 73 external interrupt 57 (DMA2)
	.word fn_080085d0             @ 74 external interrupt 58 (DMA2)
	.word branch_to_self_0800628a @ 75 external interrupt 59 (DMA2)
	.word branch_to_self_0800628a @ 76 external interrupt 60 (DMA2)
	.word branch_to_self_0800628a @ 77 external interrupt 61 (ETH)
	.word branch_to_self_0800628a @ 78 external interrupt 62 (ETH_WKUP)
	.word branch_to_self_0800628a @ 79 external interrupt 63 (CAN2_TX)
	.word branch_to_self_0800628a @ 80 external interrupt 64 (CAN2_RX0)
	.word branch_to_self_0800628a @ 81 external interrupt 65 (CAN2_RX1)
	.word branch_to_self_0800628a @ 82 external interrupt 66 (CAN2_SCE)
	.word branch_to_self_0800628a @ 83 external interrupt 67 (QSPI)
	.word branch_to_self_0800628a @ 84 external interrupt 68 (DMA2)
	.word branch_to_self_0800628a @ 85 external interrupt 69 (DMA2)
	.word branch_to_self_0800628a @ 86 external interrupt 70 (I2C3_EV)
	.word branch_to_self_0800628a @ 87 external interrupt 71 (I2C3_ER)
	.word branch_to_self_0800628a @ 88 external interrupt 72 (I2C4_EV)
	.word branch_to_self_0800628a @ 89 external interrupt 73 (I2C4_ER)
	.word branch_to_self_0800628a @ 90 external interrupt 74 (UART6)
	.word branch_to_self_0800628a @ 91 external interrupt 75 (UART7)
	.word branch_to_self_0800628a @ 92 external interrupt 76 (DMA1)
	.word branch_to_self_0800628a @ 93 external interrupt 77 (DMA2)
	.word branch_to_self_0800628a @ 94 external interrupt 78 (DVP)
	.word branch_to_self_0800628a @ 95 external interrupt 79 (BAG)
	.word branch_to_self_0800628a @ 96 external interrupt 80 (MMU)
	.word branch_to_self_0800628a @ 97 external interrupt 81 (reserved)
	.word branch_to_self_0800628a @ 98 external interrupt 82 (COMP_1_2_3)
	.word branch_to_self_0800628a @ 99 external interrupt 83 (COMP_4_5_6)
	.word branch_to_self_0800628a @ 100 external interrupt 84 (COMP7)
	.word branch_to_self_0800628a @ 101 external interrupt 85 (R-SRAM)
