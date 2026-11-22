@ own.inc - shared constants of our own modules (firmware/own/*.s), included by every one of them.
@ Part of the FNIRSI LC1020E firmware rewrite (assembly).
@
@ One place for: vendor RAM words of V1.1 (each with its evidence in NOTES.md), the no-init words,
@ the registers our modules touch (IWDG, FLASH, USB, NVIC, RCC, EXTI), the flash layout of the
@ settings copies, records and slots, the save and flash result codes, the frame format, status
@ codes, command and event numbers of USB_CONTROL_DESIGN.md section 4, and the layout of our RAM.
@ Only .equ lines: nothing here emits code, data or a section.

@ ============================================================================
@ Vendor RAM words (V1.1 port, firmware/src). Section names refer to NOTES.md.
@ ============================================================================

@ Settings / calibration block ("Internal-flash storage used by the application"): 0xC14 bytes,
@ copied from 0x0807F000 by 0x08014B74 (literals 0x08014B8C / 0x08014B90), written back by
@ 0x08014B94; first and last word 0x12345678 (start-up check 0x08028034..0x08028048).
        .equ    V_BLOCK,        0x2000057C      @ block in RAM
        .equ    BLK_SIZE,       0xC14           @ bytes (movw #0xc14 at 0x08014B7C / 0x08014BAE)
        .equ    BLK_MARK_END,   0xC10           @ offset of the last word (0x2000118C)
        .equ    BLK_MARKER,     0x12345678      @ value of the first and the last word
        .equ    BLK_CAL_LO,     0x04            @ calibration tables: offsets 0x04..0xB43
        .equ    BLK_CAL_LEN,    0xB40           @ ("User functions ...": factory table
                                                @ 0x04..0x5A3, user table 0x5A4..0xB43)
        .equ    V_FACTORY_TAB,  0x20000580      @ block +0x04, 0x5A0 bytes (0x0800B4C8 mode 1
                                                @ fills it; 0x0800BCD8 copies over it)
        .equ    V_CAL_COPY,     0x20000B20      @ block +0x5A4, 0x5A0 bytes: source of the copy
                                                @ 0x20000B20 -> 0x20000580 of 0x0800BCD8
        .equ    BLK_LANG_SET,   0xBC4           @ first-start flag (V_LANG_SET), 1 in our build
        .equ    BLK_LANGUAGE,   0xBE0           @ language (V_LANGUAGE), 1 in our build
        .equ    V_ZERO_LEN,     0x4BA4          @ zero fill from V_BLOCK at start-up (system_40.s,
                                                @ fn_08027ff4, before copy_flash_block_to_ram)
        .equ    V_STACK_TOP,    0x200163A8      @ top of the vendor stack (USB_CONTROL_DESIGN 3)

@ Settings inside the block ("User functions, settings and measured values of V1.1")
        .equ    V_LANG_SET,     0x20001140      @ 1 once the first-start language was chosen
        .equ    V_FREQ,         0x20001144      @ frequency, Hz: 100 / 120 / 1000 / 10000 / 100000
        .equ    V_LEVEL,        0x20001138      @ level, float volts: 0.1 / 0.3 / 0.6
        .equ    V_BIAS,         0x2000113C      @ bias, float volts: 0.0 / 0.5
        .equ    V_FUNC,         0x20001148      @ Func: 0 AUTO, 1 R, 2 C, 3 L, 4 Z
        .equ    V_RANGE,        0x2000114C      @ 0 AUTO, 1 100 ohm, 2 1 k, 3 10 k, 4 100 k
        .equ    V_SPEED,        0x20001150      @ 0..2
        .equ    V_CIRCUIT,      0x20001154      @ 0 auto, 1 series, 2 parallel
        .equ    V_BRIGHT,       0x20001158      @ backlight percent, 10..100 step 10
        .equ    V_LANGUAGE,     0x2000115C      @ 0 Chinese, 1 English
        .equ    V_VOLUME,       0x20001160      @ beep level
        .equ    V_OFFTIME,      0x20001164      @ off / 5 / 15 / 30 min (no consumer in V1.1;
                                                @ ours: power.s)
        .equ    V_SCREEN,       0x20001168      @ screen state: 0 language chooser, 1 measure,
                                                @ 2 compare, 3 settings
        .equ    V_WARN_TYPE,    0x2000116C
        .equ    V_WARN_SOUND,   0x20001170
        .equ    V_WARN_LED,     0x20001174
        .equ    V_CMP_TYPE,     0x20001178      @ compare quantity: 1 R, 2 C, 3 L
        .equ    V_NOMINAL,      0x20001184      @ float, default 1000
        .equ    V_TOLERANCE,    0x20001188      @ float percent, default 5, at most 99.9
        .equ    V_PREV_SCREEN,  0x200011BC      @ screen before the settings screen

@ Keys ("Display, keys, power, measurement state of V1.1")
        .equ    V_KEYS_DOWN,    0x20000008      @ halfword: mask of keys held now
        .equ    V_KEY_BUSY,     0x20001190      @ hold busy flag
        .equ    V_KEY_CODE,     0x20001192      @ halfword: 0 none, 1 short release,
                                                @ 0xFE held > 99 ticks, 0xFF release after hold
        .equ    V_KEY_MASK,     0x20001194      @ halfword: key mask of the event
        .equ    V_KEY_TICKS,    0x20001196      @ halfword: tick counter of the held key
        .equ    KEY_POWER,      0x0001          @ PC6
        .equ    KEY_UP,         0x0002          @ PC7
        .equ    KEY_0004,       0x0004          @ PC8
        .equ    KEY_OK,         0x0008          @ PC9
        .equ    KEY_0010,       0x0010          @ PC10
        .equ    KEY_0020,       0x0020          @ PA15
        .equ    KEY_0040,       0x0040          @ PC11 (secondary +1)
        .equ    KEY_0080,       0x0080          @ PC12
        .equ    KEY_0100,       0x0100          @ PB5
        .equ    KEY_0200,       0x0200          @ PB7, active high (Func +1)
        .equ    KEY_0400,       0x0400          @ PE6 (hold / long: screen 1 <-> 2)
        .equ    KEY_0800,       0x0800          @ PB8
        .equ    KEY_1000,       0x1000          @ PB9 (speed / long: circuit mode)
        .equ    KEY_2000,       0x2000          @ PE0

@ Words the key dispatchers read (USB_CONTROL_DESIGN.md 4.3); their meaning beyond that design
@ text is not established in NOTES.md.
        .equ    V_DISP_A8,      0x200011A8
        .equ    V_DIALOG,       0x200011AC      @ != 0 while a dialog is open (design 4.3)
        .equ    V_DISP_B0,      0x200011B0
        .equ    V_DISP_B4,      0x200011B4
        .equ    V_BYTE_000C,    0x2000000C      @ byte read by the condition of 0x08009A40

@ RAM-only state ("User functions ...", "Display, keys, ...")
        .equ    V_HOLD,         0x200011A4      @ hold toggle (key 0x400)
        .equ    V_CORR_FLAG,    0x200011A0      @ only read, never written (vendor defect)
        .equ    V_FACTORY,      0x200011C0      @ 0, 1 or 2 (2 = factory mode), from keys held
                                                @ at power-on
        .equ    V_MAIN_ROW,     0x200011E4      @ byte: main row of the display
        .equ    V_SECONDARY,    0x200011E8      @ 0 R/ESR, 1 X, 2 D, 3 Q, 4 theta
        .equ    V_AVERAGING,    0x200011F0      @ averaging count (0x08009F10)
        .equ    V_NO_READING,   0x20001208      @ 1 after 200 ticks without a reading
        .equ    V_NO_READ_CNT,  0x2000120C      @ its tick counter

@ Measurement and calibration
        .equ    V_X_RAW,        0x20005098      @ X (float)
        .equ    V_R,            0x200050B8      @ displayed R, ohm (float)
        .equ    V_C,            0x200050BC      @ displayed C, nF
        .equ    V_L,            0x200050C0      @ displayed L, uH
        .equ    V_Z,            0x200050C4      @ |Z|
        .equ    V_X,            0x200050C8      @ displayed X
        .equ    V_THETA,        0x200050CC      @ theta, degrees
        .equ    V_Q,            0x200050D0
        .equ    V_D,            0x200050D4
        .equ    V_DEVIATION,    0x200050D8      @ compare deviation, percent
        .equ    V_CMP_VALUE,    0x200050DC      @ compare value
        .equ    V_CAL_TYPE,     0x200050E0      @ 0 short, 11 open, 1..10 factory references
        .equ    V_CAL_RUN,      0x200050E4      @ != 0 while a calibration runs (design 4.3)
        .equ    V_CAL_STEP,     0x200050E8
        .equ    V_CAL_STATUS,   0x200050EC      @ 0 start, 1 busy, 2 finish, 3 fail
        .equ    V_PASS_COUNT,   0x200050F0      @ compare pass counter (RAM only)
        .equ    V_FAIL_COUNT,   0x200050F4      @ compare fail counter (RAM only)
        .equ    V_SUPPLY,       0x20005100      @ float volts: 128-sample mean * 6.6 / 4095
        .equ    V_CMP_DUE,      0x20005110      @ +1 every 50 SysTicks (fn_0802a720); the main
                                                @ loop clears it and calls 0x0800A7EC once
        .equ    V_SWEEP_ON,     0x20005114      @ main loop calls the sweep 0x0800BD5C while set
                                                @ (+1 every 100 SysTicks, fn_0802a720; cleared
                                                @ before the call)
        .equ    V_LOWV_POPUP,   0x20005118      @ low-voltage countdown (set to 10, shown)
        .equ    V_POPUP_OBJS,   0x2000028C      @ objects of 0x0800C848 / 0x0800CF68: +0 battery
                                                @ icon, +4 popup background (child of the
                                                @ display record word +0x10), +8 popup panel
                                                @ (child of the record word +0x1C), +0x18 the
                                                @ popup's number text (0x080228D0 "%d")
        .equ    V_DISP_DEFAULT, 0x20000478      @ word: the default display record (fix.s)

@ Display ("Display, keys, power, measurement state of V1.1")
        .equ    V_DRAW_BUF,     0x20006700      @ draw buffer, 0xC80 pixels (10 rows of 320)
        .equ    V_DRAW_DESC,    0x200066E4      @ draw buffer descriptor
        .equ    V_DISPLAY,      0x20008000      @ display record (flush 0x08014F9C)
        .equ    LCD_CMD,        0x6001FFFE      @ command port of the panel
        .equ    LCD_DATA,       0x60020000      @ data port of the panel
        .equ    V_SYSTICK_RLD,  0x200002B0      @ word 144000000 in the initial RAM; / 100

@ ============================================================================
@ No-init words: absolute addresses at the top of main SRAM, never in a section and never
@ cleared by any start code (bootloader/src/slot.inc, USB_CONTROL_DESIGN.md section 6).
@ ============================================================================
        .equ    FAULT_FLAG,     0x2001FFF0      @ the starter's fault flag
        .equ    FAULT_MAGIC,    0x464C5446      @ value that sends the next start to slot F
        .equ    REQ_WORD,       0x2001FFF4      @ update request, written by our application
        .equ    REQ_MAGIC,      0x55504454      @ "UPDT": the slot (version 2) enters update mode
        .equ    REQ_RESTART,    0x52535452      @ "RSTR": normal start after a soft restart (both
                                                @ make the slot, version 2, feed the running IWDG)
        .equ    HANDOVER_WORD,  0x2001FFF8      @ written by the slot before the application start
        .equ    HANDOVER_TAG,   0x534C0000      @ "SL" << 16; low byte = slot index (0 F, 1 A, 2 B)
        .equ    HO_WDG,         0x00000100      @ bit 8: the IWDG runs (trial start, soft restart)
        .equ    HO_SOFT,        0x00000200      @ bit 9: this start is a soft restart (UPDT / RSTR)
        .equ    RESULT_WORD,    0x2001FFFC      @ written by the slot before the reset after an
                                                @ update
        .equ    RESULT_TAG,     0x5552          @ "UR": tag << 16 | result << 8 | ~result & 0xFF
        .equ    RES_NONE,       0               @ results (INFO, design 4.1)
        .equ    RES_OK,         1               @ update written and checked
        .equ    RES_IMAGE,      2               @ image check failed
        .equ    RES_PROGRAM,    3               @ programming failed

@ ============================================================================
@ Registers (N32G45x user manual V3.5.0, docs/; ARMv7-M architecture for the NVIC / SCB)
@ ============================================================================

@ Independent watchdog (16.5): KEY 0x5555 unlocks PREDIV / RELV, 0xAAAA reloads, 0xCCCC starts.
@ V1.1 starts it at 0x08010178 (PREDIV 2 = LSI / 16, RELV 0x9C4) and feeds it once per main-loop
@ pass at 0x08010174; period 0.67..1.33 s for LSI 30..60 kHz (SETTINGS_SAVE_DESIGN.md).
        .equ    IWDG_KEY,       0x40003000
        .equ    IWDG_PREDIV,    0x40003004
        .equ    IWDG_RELV,      0x40003008
        .equ    IWDG_STS,       0x4000300C      @ PVU bit 0, CRVU bit 1
        .equ    IWDG_FEED,      0xAAAA
        .equ    IWDG_UNLOCK,    0x5555
        .equ    IWDG_START,     0xCCCC
        .equ    IWDG_PR,        2
        .equ    IWDG_RL,        0x9C4

@ Flash controller (3.2.5): registers as offsets from FLASH_BASE.
        .equ    FLASH_BASE,     0x40022000
        .equ    FL_AC,          0x00
        .equ    FL_KEY,         0x04            @ KEY1, then KEY2 clears CTRL.LOCK (3.2.1.3);
                                                @ a wrong sequence locks it until reset
        .equ    FL_OPTKEY,      0x08
        .equ    FL_STS,         0x0C
        .equ    FL_CTRL,        0x10
        .equ    FL_ADD,         0x14
        .equ    FL_OB,          0x1C
        .equ    FL_WRP,         0x20
        .equ    FLASH_KEY1,     0x45670123
        .equ    FLASH_KEY2,     0xCDEF89AB
        .equ    STS_BUSY,       0x01            @ bit 0
        .equ    STS_PGERR,      0x04            @ bit 2: word to program was not 0xFFFFFFFF
        .equ    STS_PVERR,      0x08            @ bit 3: programming verification error
        .equ    STS_WRPERR,     0x10            @ bit 4: write protection error
        .equ    STS_EOP,        0x20            @ bit 5: end of operation
        .equ    STS_EVERR,      0x40            @ bit 6: erase check error
        .equ    STS_ECCERR,     0x80            @ bit 7: ECC error
        .equ    STS_CLEAR,      0xFC            @ bits 2..7, each cleared by writing 1
        .equ    STS_PROG_ERR,   0x9C            @ PGERR | PVERR | WRPERR | ECCERR
        .equ    STS_ERASE_ERR,  0xDC            @ PGERR | PVERR | WRPERR | EVERR | ECCERR
        .equ    CTRL_PG,        0x01            @ bit 0 program
        .equ    CTRL_PER,       0x02            @ bit 1 page erase
        .equ    CTRL_START,     0x40            @ bit 6 start the erase
        .equ    CTRL_LOCK,      0x80            @ bit 7 lock (write 1 only)
        .equ    CTRL_SMPSEL,    0x100           @ bit 8: 0 = SMP1 (a word that is not erased is
                                                @ refused, PGERR), 1 = SMP2
        .equ    FLASH_PAGE,     0x800           @ erase unit (2 KiB)

@ USB device (19.5; base 0x40005C00, packet memory 0x40006000..0x400063FF): endpoint registers
@ USB_EP0..7 at +0x00..+0x1C, USB_CTRL +0x40, USB_STS +0x44, USB_FN +0x48, USB_ADDR +0x4C,
@ USB_BUFTAB +0x50. The bootloader addresses packet-memory byte offset n at 0x40006000 + 2 * n
@ (bootloader/src/usb_08.s fn_08000aa0: add.w r2, r3, r2, lsr #15).
        .equ    USB_BASE,       0x40005C00
        .equ    USB_EP0R,       0x00
        .equ    USB_EP1R,       0x04
        .equ    USB_EP2R,       0x08
        .equ    USB_EP3R,       0x0C
        .equ    USB_CTRL,       0x40
        .equ    USB_STS,        0x44
        .equ    USB_FN,         0x48
        .equ    USB_ADDR,       0x4C
        .equ    USB_BUFTAB,     0x50
        .equ    USB_PMA,        0x40006000
        .equ    USB_PULLUP,     0x40001820      @ bit 28: D+ pull-up; no other bit may change
                                                @ (19.4.5.1.1 note 1)
        .equ    USB_PULLUP_BIT, 0x10000000
@ Packet-memory layout (USB_CONTROL_DESIGN.md section 3; byte offsets in the 512-byte PMA)
        .equ    PMA_BTABLE,     0x000           @ buffer table, 4 endpoints x 8 bytes
        .equ    PMA_EP0_RX,     0x040           @ 64 bytes
        .equ    PMA_EP0_TX,     0x080           @ 64 bytes
        .equ    PMA_EP1_TX,     0x0C0           @ bulk IN 0x81, 64 bytes
        .equ    PMA_EP2_RX,     0x100           @ bulk OUT 0x02, 64 bytes
        .equ    PMA_EP3_TX,     0x140           @ interrupt IN 0x83, 16 bytes

@ RCC (6.3): CFG +0x04 (SCLKSTS bits 3:2, 10 = PLL; USBPRES bits 23:22, 11 = PLL / 3),
@ APB1PRST +0x10, APB1PCLKEN +0x1C (USBEN bit 23).
        .equ    RCC_BASE,       0x40021000
        .equ    RCC_CFG,        0x40021004
        .equ    RCC_APB1PRST,   0x40021010
        .equ    RCC_APB1PCLKEN, 0x4002101C
        .equ    RCC_USBEN,      0x00800000
        .equ    RCC_USBPRES,    0x00C00000
        .equ    RCC_SCLKSTS,    0x0000000C
        .equ    RCC_SCLK_PLL,   0x00000008

@ EXTI pending register: line 18 (USB wake-up) cleared by writing 0x40000 (as 0x0800FB40 ->
@ 0x08008D14, USB_CONTROL_DESIGN.md section 3)
        .equ    EXTI_PEND,      0x40010414
        .equ    EXTI_LINE18,    0x00040000

@ NVIC and SCB (ARMv7-M): IRQ 20 USB_LP, IRQ 42 USBWKUP (manual vector table, 0x90 / 0xE8)
        .equ    NVIC_ISER0,     0xE000E100      @ IRQ 0..31
        .equ    NVIC_ISER1,     0xE000E104      @ IRQ 32..63
        .equ    NVIC_ICER0,     0xE000E180      @ ICER0..2 cover IRQ 0..95 (the vector table
        .equ    NVIC_ICER1,     0xE000E184      @ ends with IRQ 85)
        .equ    NVIC_ICPR0,     0xE000E280      @ ICPR0..2 likewise
        .equ    NVIC_ICPR1,     0xE000E284
        .equ    NVIC_IPR,       0xE000E400      @ one priority byte per IRQ
        .equ    IRQ_USB_LP,     20
        .equ    IRQ_USB_WKUP,   42
        .equ    SYST_CSR,       0xE000E010      @ SysTick control: 0 stops it
        .equ    SCB_ICSR,       0xE000ED04
        .equ    ICSR_PEND_CLR,  0x0A000000      @ PENDSVCLR (bit 27) | PENDSTCLR (bit 25)
        .equ    SCB_VTOR,       0xE000ED08
        .equ    BOOT_SPACE,     0x00000000      @ boot space = main flash from 0x08000000: the
                                                @ starter's vector table (SP, reset entry)

@ DMA (manual 8.5.4): DMA_CHCFGx at controller base + 0x08 + 20 * (x - 1), CHEN bit 0; DMA1
@ 0x40020000, DMA2 0x40020400. The channels the application enables (fn_08008770(block, 1)):
@ DMA1 channels 1 and 8, DMA2 channel 5 (fn_08007bdc, measure_32.s, and the DMA2 interrupt
@ fn_080085d0, periph_34.s), DMA2 channel 8 (fn_08008024) and DMA2 channel 3 (fn_08008814).
        .equ    DMA1_CH1,       0x40020008
        .equ    DMA1_CH8,       0x40020094
        .equ    DMA2_CH3,       0x40020430
        .equ    DMA2_CH5,       0x40020458
        .equ    DMA2_CH8,       0x40020494
        .equ    DMA_CHEN,       0x00000001

@ ============================================================================
@ Flash layout
@ ============================================================================

@ Settings copies (SETTINGS_SAVE_DESIGN.md "Layout"): two pages each; the block from the copy
@ base, the trailer in the last two words of the second page.
        .equ    SET_A,          0x0807F000      @ copy A (vendor place): 0x0807F000, 0x0807F800
        .equ    SET_B,          0x08066000      @ copy B: 0x08066000, 0x08066800
        .equ    SET_SIZE,       0x1000          @ two pages
        .equ    TRL_SEQ,        0xFF8           @ trailer: sequence number (u32)
        .equ    TRL_CRC,        0xFFC           @ trailer: CRC-32 of the block, then the sequence

@ Application, records and slots (bootloader/src/slot.inc, starter/starter.s)
        .equ    APP_BASE,       0x08006000      @ application vector table
        .equ    APP_END,        0x08062000      @ end of the application area (exclusive)
        .equ    REC0,           0x08068000      @ control record page 0
        .equ    REC1,           0x08068800      @ control record page 1
        .equ    REC_END,        0x08069000      @ end of the record pages (exclusive)
        .equ    REC_TAG,        0x4C52          @ record word 0 bits 31..16
        .equ    ST_INSTALL,     1               @ record states
        .equ    ST_TRIAL,       2
        .equ    ST_OK,          3
        .equ    SLOT_F,         0x08069000      @ slots: 24 KiB each, header + image
        .equ    SLOT_A,         0x0806F000
        .equ    SLOT_B,         0x08075000
        .equ    SLOT_SIZE,      0x6000
        .equ    SLOT_ROOM,      0x5E00          @ largest image (starter.s ROOM)
        .equ    HDR_MAGIC,      0x544F4C53      @ slot header +0 "SLOT"; +4 length, +8 image
                                                @ CRC-32, +12 version, +16 link address
                                                @ (slot + 0x200), +28 CRC-32 of bytes 0..27

@ ============================================================================
@ Save and flash results (save.s)
@ ============================================================================

@ own_save_flags bits
        .equ    SF_HELD,        0x01            @ saves held (SETTINGS_SAVE_DESIGN "Held saves")
        .equ    SF_DIFFERS,     0x02            @ backup differs: B valid, its calibration
                                                @ tables differ from A's
        .equ    SF_NOVALID,     0x04            @ no valid settings copy at load
        .equ    SF_FAILED,      0x08            @ the last save failed
        .equ    SF_A_ONLY,      0x10            @ copy B was loaded: ordinary saves write A only
        .equ    SF_A_DAMAGED,   0x20            @ A: both markers, CRC wrong, B valid
        .equ    SF_REWRITE_A,   0x40            @ A looked interrupted: rewrite from B pending
        .equ    SF_RESTART,     0x80            @ flash differs from RAM: saves held until reset

@ own_save_status: result | step << 8 | copy << 16
        .equ    SV_OK,          0
        .equ    SV_HELD,        1               @ saves held: nothing written
        .equ    SV_REFUSED,     2               @ guard set, or not applicable now
        .equ    SV_MARK,        3               @ trailer mark of A failed (stopped before erase)
        .equ    SV_ERASE,       4               @ a page erase or its check failed
        .equ    SV_PROGRAM,     5               @ a word failed to program
        .equ    SV_VERIFY,      6               @ the copy read back differs
        .equ    SV_BADBLOCK,    7               @ staged block: markers or transfer CRC wrong
        .equ    SV_BADCOPY,     8               @ the source copy of a recovery is not valid
        .equ    SV_SAME,        9               @ own_save: both copies valid and equal to the
                                                @ block: nothing written (S2.10)
        .equ    STEP_MARK,      0x41            @ steps of SETTINGS_SAVE_DESIGN "Save" 4 (a)..(d)
        .equ    STEP_ERASE,     0x42
        .equ    STEP_PROGRAM,   0x43
        .equ    STEP_VERIFY,    0x44
        .equ    STEP_CHECK,     0x01            @ the check before any write
        .equ    COPY_NONE,      0               @ own_save_loaded / status copy field
        .equ    COPY_A,         1
        .equ    COPY_B,         2

@ flash_word / flash_erase_page results
        .equ    FL_OK,          0
        .equ    FL_GATE,        1               @ outside the gate or misaligned: nothing done
        .equ    FL_NOT_ERASED,  2               @ word holds another value and is not erased
        .equ    FL_LOCKED,      3               @ the controller stayed locked after the keys
        .equ    FL_HWERR,       4               @ FLASH_STS error bit after the operation
        .equ    FL_VERIFY,      5               @ word read back differs
        .equ    FL_BLANK,       6               @ page does not read all 0xFF after its erase

@ ============================================================================
@ Frames, status codes, commands (USB_CONTROL_DESIGN.md sections 2 and 4)
@ ============================================================================
        .equ    FR_SYNC,        0xA5
        .equ    FR_MAX_PAYLOAD, 512
        .equ    FR_LEN_MIN,     3               @ length field: seq .. payload, 3..515
        .equ    FR_LEN_MAX,     515
        .equ    FR_MAX,         520             @ sync + length + 515 + CRC-16
        .equ    FR_REQUEST,     1               @ frame types
        .equ    FR_ANSWER,      2
        .equ    FR_STREAM,      3
        .equ    FR_EVENT,       4
        .equ    CRC16_POLY,     0x1021          @ CRC-16/CCITT-FALSE over length .. payload
        .equ    CRC16_INIT,     0xFFFF
        .equ    PROTO_VERSION,  1
        .equ    USB_VID,        0x19F5
        .equ    USB_PID,        0x1020
        .equ    CHIP_UID,       0x1FFFF7F0      @ 96 bits (serial number string)

        .equ    S_OK,           0               @ answer status codes
        .equ    S_UNKNOWN,      1               @ unknown command
        .equ    S_BAD_ARG,      2               @ bad length / argument
        .equ    S_NOT_NOW,      3               @ not allowed now
        .equ    S_BUSY,         4
        .equ    S_STORAGE,      5               @ storage error
        .equ    S_SAFETY,       6               @ refused for safety
        .equ    S_XFER_CRC,     7               @ CRC / length mismatch of transferred data

        .equ    C_INFO,         0x00            @ 4.1 device
        .equ    C_PING,         0x01
        .equ    C_RESET,        0x02
        .equ    C_BATTERY,      0x03
        .equ    C_POWER_OFF,    0x05
        .equ    C_FACTORY_MODE, 0x06
        .equ    C_STATE,        0x10            @ 4.2 state
        .equ    C_STREAM,       0x11
        .equ    C_SCREEN,       0x12
        .equ    C_KEY,          0x13
        .equ    C_LCR_TABLES,   0x20            @ 4.4 measurement
        .equ    C_LCR_SET,      0x21
        .equ    C_MEASURE,      0x22
        .equ    C_MEASURE_STREAM, 0x23
        .equ    C_COMPARE,      0x24
        .equ    C_COMPARE_SET,  0x25
        .equ    C_HOLD,         0x26
        .equ    C_CALIBRATE,    0x27
        .equ    C_TOL_SET,      0x28            @ tolerance modes (S2.9, RAM only)
        .equ    C_SET_TABLES,   0x50            @ 4.5 settings, screen, diagnostics
        .equ    C_SET_SET,      0x51
        .equ    C_SET_SAVE,     0x52
        .equ    C_CAL_READ,     0x53
        .equ    C_RESTORE_DEF,  0x54
        .equ    C_SET_RESTORE_B, 0x55
        .equ    C_SET_ACCEPT_A, 0x56
        .equ    C_SET_WRITE_BLOCK, 0x57
        .equ    C_SETUP_LANGUAGE, 0x58          @ no handler (English only): status 1
        .equ    C_SET_ACCEPT_B, 0x59
        .equ    C_SET_ACCEPT_DEF, 0x5A
        .equ    C_SCREENSHOT,   0x60
        .equ    C_MEM_READ,     0xF0
        .equ    C_UPDATE_MODE,  0x84            @ 4.6 updates (0x80..0x83 reserved)
        .equ    C_BOOT_BEGIN,   0x85
        .equ    C_BOOT_DATA,    0x86
        .equ    C_BOOT_END,     0x87
        .equ    C_BOOT_INSTALL, 0x88
        .equ    C_BOOT_STATUS,  0x89
        .equ    E_KEY,          0x90            @ events (type 4, while DTR is set)
        .equ    E_SCREEN,       0x91
        .equ    E_SETTING,      0x93
        .equ    E_POWERED_OFF,  0x94
        .equ    E_MEASURE_DONE, 0x95
        .equ    E_SAVE_RESULT,  0x96
        .equ    E_CALIBRATION,  0x97
        .equ    CONFIRM_POWER_OFF, 0x4F46       @ confirmation of POWER_OFF

@ Capability bits (4.8)
        .equ    CAP_STATE,      1 << 0
        .equ    CAP_SCREEN,     1 << 1
        .equ    CAP_KEY,        1 << 2
        .equ    CAP_LCR,        1 << 3
        .equ    CAP_MEASURE,    1 << 4
        .equ    CAP_COMPARE,    1 << 5
        .equ    CAP_HOLD,       1 << 6
        .equ    CAP_CALIBRATE,  1 << 7
        .equ    CAP_SETTINGS,   1 << 8
        .equ    CAP_CAL_READ,   1 << 9
        .equ    CAP_SCREENSHOT, 1 << 10
        .equ    CAP_MEM_READ,   1 << 11
        .equ    CAP_EVENTS,     1 << 12
        .equ    CAP_UPDATE,     1 << 13
        .equ    CAP_BOOT,       1 << 14
        .equ    CAP_BATTERY,    1 << 15
        .equ    CAP_POWER_OFF,  1 << 16
        .equ    CAP_RESTORE,    1 << 17
        .equ    CAP_RECOVERY,   1 << 18
        .equ    CAP_FACTORY,    1 << 19
        .equ    CAP_LANGUAGE,   1 << 20         @ not set (SETUP_LANGUAGE has no handler)
        .equ    CAP_F60,        1 << 22         @ frequency index 5 = 60 Hz (S2.12)
        .equ    CAP_TOL,        1 << 23         @ TOLERANCE_SET, the COMPARE tail, the judgement
                                                @ of S2.8 / S2.9
        .equ    CAP_DISP2,      1 << 24         @ MEASURE byte 64 (S2.1 markers), signed values,
                                                @ save result SV_SAME (S2.1, S2.2, S2.10)

@ ============================================================================
@ Our RAM: 0x20018000..0x2001DFFF (24 KiB above the vendor stack top 0x200163A8, below the
@ no-init words 0x2001FFF0..0x2001FFFF), absolute addresses only (no section is placed there),
@ cleared by own_start. Every module owns one area and writes only inside it; another module's
@ words are read, never written (ctl.s's own_injected is read by save.s).
@ ============================================================================
        .equ    OWN_RAM,        0x20018000
        .equ    OWN_RAM_SIZE,   0x6000

        .equ    O_RX_RING,      0x0000          @ usb.s: received bytes, 1 KiB
        .equ    RX_RING_SIZE,   0x400
        .equ    O_TX_RING,      0x0400          @ usb.s: bytes to send, 8 KiB
        .equ    TX_RING_SIZE,   0x2000
        .equ    O_STAGE,        0x2400          @ save.s: save snapshot / staging buffer, 0xC14
                                                @ bytes (SETTINGS_WRITE_BLOCK fills it through
                                                @ ctl.s, then calls save_write_block)
        .equ    O_SAVE,         0x3020          @ save.s state, 0x40 bytes
        .equ    SAVE_SIZE,      0x40
        .equ    O_USB,          0x3060          @ usb.s state, 0x80 bytes
        .equ    USB_SIZE,       0x80
        .equ    O_SCREEN,       0x30E0          @ screen.s state, 0x40 bytes
        .equ    SCREEN_SIZE,    0x40
        .equ    O_CTL,          0x3120          @ ctl.s state, 0x2CC0 bytes (frame and answer
                                                @ buffers, event queue, the previous copy of the
                                                @ settings block for SETTING_CHANGED)
        .equ    CTL_SIZE,       0x2CC0
        .equ    O_FUNC,         0x5DE0          @ the instrument functions (fmt.s, cmp.s and the
                                                @ stage-2 words of meas.s), 0x100 bytes
                                                @ (MEASUREMENT_FIX_DESIGN.md stages 2 / 2F / 2G,
                                                @ revision 6): from the unused end of O_CTL
        .equ    FUNC_SIZE,      0x100
        .equ    O_MEAS,         0x5EE0          @ meas.s state, 0x100 bytes (the measurement core,
                                                @ MEASUREMENT_FIX_DESIGN.md section 0 "RAM": taken
                                                @ from the unused end of the former O_CTL area)
        .equ    MEAS_SIZE,      0x100
        .equ    O_PWR,          0x5FE0          @ power.s state, the last 0x20 bytes
        .equ    PWR_SIZE,       0x20

        .equ    OWN_RX_RING,    OWN_RAM + O_RX_RING
        .equ    OWN_TX_RING,    OWN_RAM + O_TX_RING
        .equ    OWN_STAGE,      OWN_RAM + O_STAGE
        .equ    OWN_SAVE,       OWN_RAM + O_SAVE
        .equ    OWN_USB,        OWN_RAM + O_USB
        .equ    OWN_SCREEN,     OWN_RAM + O_SCREEN
        .equ    OWN_CTL,        OWN_RAM + O_CTL
        .equ    OWN_MEAS,       OWN_RAM + O_MEAS
        .equ    OWN_FUNC,       OWN_RAM + O_FUNC
        .equ    OWN_PWR,        OWN_RAM + O_PWR

@ OWN_FUNC words, each written only by the module named (cleared to 0 by own_start at every
@ start; nothing of it is saved, design D7)
        .equ    MF_MARK,        0x00            @ fmt.s: 1 when the value formatted last lies
                                                @ outside the accuracy table (S2.1), else 0
        .equ    MF_ROW0,        0x04            @ fmt.s: glyph object 0 of row 0 last marked, or 0
        .equ    MF_ROW1,        0x08            @ fmt.s: the same for row 1
        .equ    MF_SP,          0x0C            @ meas.s S2.6: 0 undecided, 1 series, 2 parallel
        .equ    MF_AUTO,        0x10            @ cmp.s S2.5: AUTO class 0 undecided, 1 R, 2 C,
                                                @ 3 L (meas.s sets 0 at a setting change)
        .equ    MF_HOLDP,       0x14            @ meas.s S2.7: 1 while a hold is latched
        .equ    MF_HL,          0x18            @ meas.s S2.7: 6 words latched at hold 0 -> 1
                                                @ (frequency, level, bias, range, speed, circuit)
        .equ    MF_PSEQ,        0x30            @ meas.s: publishes made (meas_tail)
        .equ    MF_TMODE,       0x34            @ cmp.s S2.9: tolerance mode 0 vendor +- %, 1 %
                                                @ limits, 2 absolute pF limits, 3 preset letter
        .equ    MF_TLO,         0x38            @ cmp.s: float lower limit (% or pF), modes 1 / 2
        .equ    MF_THI,         0x3C            @ cmp.s: float upper limit
        .equ    MF_TLET,        0x40            @ cmp.s: preset letter (ASCII) of mode 3
        .equ    MF_SKIND,       0x44            @ cmp.s: secondary limit 0 none, 1 D max, 2 Q min,
                                                @ 3 ESR max
        .equ    MF_SVAL,        0x48            @ cmp.s: its float value
        .equ    MF_TOLW,        0x4C            @ cmp.s: bits of 0x20001188 when the mode was set
        .equ    MF_RES,         0x50            @ cmp.s S2.8: result of the last judgement (CR_*)
        .equ    MF_DEV,         0x54            @ cmp.s: its signed deviation (float, % or pF)
        .equ    MF_EMODE,       0x58            @ cmp.s: its effective mode 0 vendor, 1 %, 2 pF
        .equ    MF_ELO,         0x5C            @ cmp.s: its effective lower limit (% or pF)
        .equ    MF_EHI,         0x60            @ cmp.s: its effective upper limit
        .equ    MF_PREV,        0x64            @ cmp.s: compare value of the previous publish
        .equ    MF_PVSEQ,       0x68            @ cmp.s: its publish number
        .equ    MF_PVOK,        0x6C            @ cmp.s: 1 when MF_PREV holds a present value
        .equ    MF_LED,         0x70            @ cmp.s: 0 LEDs idle, 1 OK level, 2 NG level
        .equ    MF_BEEPN,       0x74            @ cmp.s: beeps still to sound
        .equ    MF_BEEPT,       0x78            @ cmp.s: tick of the next beeper step
        .equ    MF_BEEPS,       0x7C            @ cmp.s: 0 idle, 1 beeper on, 2 gap
        .equ    MF_END,         0x80
        .if     MF_END > FUNC_SIZE
        .error  "own.inc: the OWN_FUNC words do not fit O_FUNC"
        .endif

@ compare results (MF_RES; COMPARE record offset 39)
        .equ    CR_NONE,        0               @ no part present: "---"
        .equ    CR_IN,          1               @ within the limits
        .equ    CR_HI,          2               @ above the upper limit
        .equ    CR_LO,          3               @ below the lower limit
        .equ    CR_SEC,         4               @ primary within, the secondary limit failed
        .equ    CR_OUT,         5               @ a reading above the presence limit (not counted)
        .equ    CR_UNST,        6               @ a part present, the reading not yet stable: "---"

@ meas.s words written by another module (offsets in its area; the others: meas.s header)
        .equ    MO_G,           0x00            @ re-arm generation: +1 per re-arm of DMA1 channel 1,
                                                @ written only by own_dma_rearm (fix.s) inside the
                                                @ DMA2 channel 3 interrupt; meas.s only reads it

@ save.s words (offsets in its area)
        .equ    SVO_FLAGS,      0x00            @ own_save_flags (SF_*)
        .equ    SVO_STATUS,     0x04            @ own_save_status (SV_* | step << 8 | copy << 16)
        .equ    SVO_COUNT,      0x08            @ own_save_count: +1 per finished save or
                                                @ recovery call (SAVE_RESULT event source)
        .equ    SVO_LOADED,     0x0C            @ own_save_loaded: COPY_NONE / COPY_A / COPY_B
        .equ    SVO_GATE,       0x10            @ own_gate_slot: 0 closed, SLOT_A or SLOT_B
        .equ    SVO_SEQ,        0x14            @ sequence of the copy being written
        .equ    SVO_CRC,        0x18            @ CRC-32 of the staged block and SVO_SEQ
        .equ    own_save_flags,  OWN_SAVE + SVO_FLAGS
        .equ    own_save_status, OWN_SAVE + SVO_STATUS
        .equ    own_save_count,  OWN_SAVE + SVO_COUNT
        .equ    own_save_loaded, OWN_SAVE + SVO_LOADED
        .equ    own_gate_slot,   OWN_SAVE + SVO_GATE

@ ctl.s words read by other modules (offsets in its area)
        .equ    CTO_INJECTED,   0x00            @ own_injected: != 0 while 0x08009400 handles an
                                                @ injected key event (USB_CONTROL_DESIGN 4.3)
        .equ    own_injected,   OWN_CTL + CTO_INJECTED

@ ---- screen.s block begin: screenshot (scr_start argument, band end results) ----
        .equ    SCR_BANDS,      24              @ bands of 10 rows (240 / 10)
        .equ    SCR_ALL,        0xFF            @ scr_start argument: every band, 0..23
        .equ    SCR_RES_DONE,   0               @ band end frame result: all 10 rows sent
        .equ    SCR_RES_NOROOM, 1               @ a frame did not fit the TX ring: ask again
        .equ    SCR_RES_NOREFRESH, 2            @ no full redraw of the band after 3 requests
@ ---- screen.s block end ----

@ ---- usb.s block begin: USB driver registers, bits and usb_reserve arguments ----
@ NVIC set-pending register (ARMv7-M): usb.s pends IRQ 20 from the main loop so that every
@ endpoint register write happens inside the USB interrupt.
        .equ    NVIC_ISPR0,     0xE000E200      @ IRQ 0..31
@ Priority byte of IRQ 20 and IRQ 42. The DMA interrupt IRQ 58 (vector 74 -> 0x080085D0) gets
@ byte 0x00 (measure_32.s: fn_0800ad68 with preemption 0, sub 0), SysTick 0xF0 (periph_34.s
@ fn_08008504, byte 0xE000ED23). With the grouping 5 that the slot bootloader writes
@ (bootloader/src/system_05.s: fn_08001968(0x500)) their group fields are 0, 2 and 3.
        .equ    USB_IRQ_PRIO,   0x80
@ usb_reserve arguments
        .equ    USB_RES_OFF,    0
        .equ    USB_RES_ON,     1
        .equ    USB_RES_QUERY,  2

@ USB_CTRL (19.5.3): reset value 0x0003 (PD | FRST)
        .equ    USB_CTRL_FRST,  0x0001          @ force reset
        .equ    USB_CTRL_PD,    0x0002          @ power down
        .equ    USB_CTRL_RSTM,  0x0400          @ USB reset interrupt enable
        .equ    USB_CTRL_CTRSM, 0x8000          @ correct transfer interrupt enable
@ USB_STS (19.5.4): flags other than CTRS are cleared by writing 0, writing 1 has no effect
        .equ    USB_STS_EPID,   0x000F          @ endpoint of the correct transfer
        .equ    USB_STS_RST,    0x0400          @ USB reset seen
        .equ    USB_STS_CTRS,   0x8000          @ correct transfer (read only)
@ USB_EPn (19.5.2): CTRS_RX / CTRS_TX are cleared by writing 0 (1 has no effect); DATTOG_RX,
@ STS_RX, DATTOG_TX, STS_TX toggle where a 1 is written (0 has no effect); SETUP is read only.
        .equ    EP_CTRS_RX,     0x8000
        .equ    EP_SETUP,       0x0800
        .equ    EP_CTRS_TX,     0x0080
        .equ    EP_T_BULK,      0x0000          @ EP_TYPE bits 10:9
        .equ    EP_T_CONTROL,   0x0200
        .equ    EP_T_INTERRUPT, 0x0600
        .equ    EP_RX_STALL,    0x1000          @ STS_RX bits 13:12 (Table 19-6)
        .equ    EP_RX_NAK,      0x2000
        .equ    EP_RX_VALID,    0x3000
        .equ    EP_TX_STALL,    0x0010          @ STS_TX bits 5:4 (Table 19-7)
        .equ    EP_TX_NAK,      0x0020
        .equ    EP_TX_VALID,    0x0030
@ Masks of the read-modify-write helpers (bootloader/src/usb_08.s fn_08002064 0xBF8F,
@ fn_08002094 0x8FBF, usb_09.s fn_08002a40 0xBFBF and 0x8080)
        .equ    EP_KEEP_RX,     0xBF8F          @ write toggles STS_RX only
        .equ    EP_KEEP_TX,     0x8FBF          @ write toggles STS_TX only
        .equ    EP_KEEP_BOTH,   0xBFBF          @ write toggles both status fields
        .equ    EP_KEEP_INIT,   0x7070          @ both DATTOG and both status fields
        .equ    EP_KEEP_CLR,    0x0F0F          @ SETUP, EP_TYPE, EP_KIND, EPADDR only
        .equ    EP_NO_CLR,      0x8080          @ both CTRS bits written as 1
@ USB_ADDR (19.5.6)
        .equ    USB_ADDR_EFUC,  0x80            @ module enable; ADDR in bits 6:0
@ Buffer description table (19.6): entry of endpoint n at CPU address USB_PMA + 16 * n
@ (packet-memory offset 8 * n) with BUFTAB 0
        .equ    BT_ADDR_TX,     0x0
        .equ    BT_CNT_TX,      0x4
        .equ    BT_ADDR_RX,     0x8
        .equ    BT_CNT_RX,      0xC
        .equ    BT_STRIDE,      0x10
        .equ    BT_RX_64,       0x8400          @ CNT_RX: BLSIZE 1 (32-byte blocks), NUM_BLK 1 =
                                                @ 64 bytes (bootloader usb_09.s fn_08002f08, 0x40)
        .equ    USB_EP_SIZE,    64              @ EP0, EP1 IN and EP2 OUT packet size
@ ---- usb.s block end ----
