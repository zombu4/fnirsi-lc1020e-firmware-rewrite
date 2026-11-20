@ rodata.s - fixed read-only data of the bootloader: font bitmaps, lookup tables, USB descriptors, region table, packed initial RAM image
@ Part of the FNIRSI LC1020E firmware rewrite: port of the stock bootloader (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

@ ----------------------------------------------------------------------------
@ rodata_start - the read-only data block, 0x08003F64..0x0800467B (1816 bytes),
@ placed after the last code unit. Pieces in address order: a one-byte table,
@ the glyph bitmap blob, a word, a string, an identification block, lookup
@ tables, the USB descriptors, the startup region table, the compressed initial
@ RAM image and one byte of padding. image_end is the address right after the
@ last byte (0x0800467C).
@ ----------------------------------------------------------------------------
	.section .rodata.fixed,"a",%progbits
.ifdef SLOT
	.include "src/slot.inc"
	.p2align 2			@ slot build: the region table is read with ldm
.endif
	.global rodata_start
rodata_start:

@ 0x08003F64: one byte, 0x00. The routine at 0x080012d4 reads it (ldrb.w r1,[r8,r5])
@ with the following glyph blob, so this byte is the entry before glyph data.
	.global d_08003f64
d_08003f64:
	.byte 0x00

@ 0x08003F65: 1279-byte glyph bitmap blob (bytes taken verbatim from the stock
@ image; read by the routine at 0x080012d4 as ldrb.w r1,[r8,r5]).
	.incbin "assets/vendor/08003f65.bin"

@ 0x08004464: the word 0xFFFFFFF8 (-8). Loaded by the routine at 0x08003bd8
@ (ldr r1,[0x08003c5c] refers to this address).
	.global d_08004464
d_08004464:
	.byte 0xf8, 0xff, 0xff, 0xff

@ 0x08004468: the string " " (one space and the terminating NUL).
	.asciz " "

@ 0x0800446A: 46-byte block with no direct reference. It holds the text
@ "LC1020E-IAP" (the application-update identification string) between
@ binary bytes; the other bytes are kept as they are in the stock image.
	.byte 0x4b, 0x9c, 0x42, 0x92, 0x38, 0x92, 0x38, 0x00	@ binary bytes
	.byte 0x00, 0x9d, 0x42, 0x92, 0x38, 0x00, 0x00, 0x00	@ binary bytes
	.byte 0x00, 0x00, 0x00					@ zero bytes
	.ascii "LC1020E-IAP"					@ identification text
	.byte 0x08						@ byte after the text
	.byte 0x00, 0x00, 0x00, 0x00, 0x00			@ zero bytes
	.byte 0x00, 0x00, 0x00, 0x00, 0x00			@ zero bytes
	.byte 0x9d, 0x42, 0x92, 0x38, 0x00			@ binary bytes

@ 0x08004498: 16-byte lookup table, indexed by byte (ldrb r5,[r4,r3],
@ ldrb r5,[r4,r5], ldrb r4,[r4,r5]) by the routine at 0x08001b20.
	.global d_08004498
d_08004498:
	.byte 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04
	.byte 0x01, 0x02, 0x03, 0x04, 0x06, 0x07, 0x08, 0x09

@ 0x080044A8: 16-byte lookup table, indexed by byte (ldrb r4,[r5,r4]) by the
@ routine at 0x08001b20: 1, 2, 4, 6, 8, 10, 12, 16, then eight times 0x20.
	.byte 0x01, 0x02, 0x04, 0x06, 0x08, 0x0a, 0x0c, 0x10
	.byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20

@ 0x080044B8: table of 16-bit values, indexed by halfword (ldrh.w
@ r1,[r3,r1,lsl #1]) by the routine at 0x08001b20: 1, 2, 4, 6, 8, 10, 12, 16,
@ 0x20, 0x40, 0x80, then five times 0x100.
	.short 0x0001, 0x0002, 0x0004, 0x0006, 0x0008, 0x000a, 0x000c, 0x0010
	.short 0x0020, 0x0040, 0x0080, 0x0100, 0x0100, 0x0100, 0x0100, 0x0100

@ 0x080044D8: USB device descriptor (18 bytes).
.ifdef SLOT
usb_device_desc:			@ slot build: named for the typed RAM image
.endif
	.byte 0x12			@ bLength
	.byte 0x01			@ bDescriptorType: device
	.short 0x0200			@ bcdUSB
	.byte 0x00			@ bDeviceClass
	.byte 0x00			@ bDeviceSubClass
	.byte 0x00			@ bDeviceProtocol
	.byte 0x40			@ bMaxPacketSize0: 64
	.short 0x19f5			@ idVendor
	.short 0x5740			@ idProduct
	.short 0x0200			@ bcdDevice
	.byte 0x01			@ iManufacturer: string index 1
	.byte 0x02			@ iProduct: string index 2
	.byte 0x03			@ iSerialNumber: string index 3
	.byte 0x01			@ bNumConfigurations

@ 0x080044EA: USB configuration descriptor (9 bytes, with the attribute byte
@ at 0x080044F1 and the power byte at the start of the next blob).
	.global d_080044ea
d_080044ea:
	.byte 0x09			@ bLength
	.byte 0x02			@ bDescriptorType: configuration
	.short 0x0020			@ wTotalLength: 32 (configuration, interface, two endpoints)
	.byte 0x01			@ bNumInterfaces
	.byte 0x01			@ bConfigurationValue
	.byte 0x00			@ iConfiguration

@ 0x080044F1: bmAttributes of the configuration descriptor (0xC0: self powered).
	.byte 0xc0

@ 0x080044F2: 130-byte blob: bMaxPower (0x64) of the configuration descriptor,
@ the interface descriptor (class 8, subclass 6, protocol 0x50), the two
@ endpoint descriptors (0x81 bulk IN and 0x02 bulk OUT, 64 bytes) and the USB
@ string descriptors (language ID and the strings), verbatim from the stock image.
	.incbin "assets/vendor/080044f2.bin"

@ 0x08004574: startup region table. Each entry has four words: source address,
@ destination address, size, handler address (the handler entry address is even).
@ Entry 0 unpacks the compressed initial RAM image into RAM at 0x20000000
@ (0x220 bytes) with the decompress handler.
	.global d_08004574
d_08004574:
	.word d_08004594		@ entry 0 source: compressed initial RAM image
	.word 0x20000000		@ entry 0 destination: start of RAM
	.word 0x00000220		@ entry 0 size: 0x220 bytes
.ifdef SLOT
	.word copy_init_addr		@ entry 0 handler (slot build): copy of the typed image
.else
	.word decompress_addr		@ entry 0 handler: decompress
.endif
@ Entry 1 clears the next RAM range with the zero-fill handler.
	.word image_end			@ entry 1 source: end of the image
	.word 0x20000220		@ entry 1 destination: RAM right after the unpacked image
	.word 0x00001e08		@ entry 1 size: 0x1E08 bytes
	.word zero_fill_addr		@ entry 1 handler: zero fill

@ 0x08004594: 231-byte compressed initial RAM image, input of the decompress
@ handler (region table entry 0); it unpacks to 0x220 bytes at 0x20000000. After
@ unpacking, 33 RAM words hold code entry addresses, so every code unit has to
@ stay at its original address.
	.global d_08004594
d_08004594:
.ifdef SLOT
@ Slot build: the initial RAM image typed out (0x220 bytes for 0x20000000..
@ 0x2000021F, copied by copy_init). It equals the unpacked stock image except
@ that its 39 flash pointers are symbols (they follow the code and data to the
@ slot's link address) and the FAT sector count is DRIVE_SECTORS.
ram_image:
	@ 0x20000000: application reset vector holder (start_application), flag
	@ byte 0x20000008, two saved words 0x2000000C / 0x20000010
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
	.word 0x00000000
	@ 0x20000014: boot sector fields of the update drive (0x3E bytes, copied
	@ to sector 0 by fn_08003bd8)
	.byte 0xeb, 0x3c, 0x90		@ jump instruction
	.ascii "MSDOS5.0"		@ OEM name
	.short 0x0800			@ bytes per sector
	.byte 0x01			@ sectors per cluster
	.short 0x0006			@ reserved sectors (FATs at 0x3000 / 0x3800)
	.byte 0x02			@ number of FATs
	.short 0x0200			@ root entries (root at 0x4000, data at 0x8000)
	.short DRIVE_SECTORS		@ total sectors (stock 0x00C4)
	.byte 0xf8			@ media descriptor
	.short 0x0001			@ sectors per FAT
	.short 0x0001			@ sectors per track
	.short 0x0001			@ heads
	.word 0x00000000		@ hidden sectors
	.word 0x00000000		@ total sectors, 32-bit field
	.byte 0x00			@ drive number
	.byte 0x00			@ reserved
	.byte 0x29			@ extended boot signature
	.byte 0x96, 0x16, 0x66, 0xd3	@ volume serial number
	.ascii "           "		@ volume label field (11 spaces)
	.ascii "FAT16   "		@ file system type text
	@ 0x20000052: name of the first root entry (fn_08003bd8)
	.ascii "Ready   TXT"
	.byte 0x00, 0x00, 0x00
	@ 0x20000060: core clock in Hz (144 MHz; main divides it by 100 for SysTick)
	.word 0x08954400
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
	.word 0x00000000
	@ 0x20000088: USB string descriptor in RAM (0x1A bytes, "QPLCR5 ")
	.word 0x0051031a, 0x004c0050, 0x00520043, 0x00200035
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
	@ 0x200000A8: 14 handler pointers
	.word fn_08000d90, fn_08002d98, fn_08002d98, fn_08002d98
	.word fn_08002d98, fn_08002d98, fn_08002d98, fn_08002d98
	.word fn_08000d94, fn_08002d98, fn_08002d98, fn_08002d98
	.word fn_08002d98, fn_08002d98
	@ 0x200000E0
	.word 0x00000103, 0x00000000
	@ 0x200000E8: descriptor table: {address, length} pairs
	.word usb_device_desc, 0x00000012		@ device descriptor
	.word d_080044ea, 0x00000020			@ configuration descriptor
	@ 0x200000F8: function table (fn_08002c10 stores 0x200000F8 to 0x20000070)
	.word fn_08001778, fn_080016a0, fn_08001774, fn_08001776
	.word fn_080015cc, fn_08001650, fn_08001644, fn_08001618
	.word fn_0800160c, fn_08001624
	.word 0x00000000, 0x00000040
	@ 0x20000128: string descriptors {address, length}
	.word d_080044ea + 0x20, 0x00000004		@ 0x0800450A language ID
	.word d_080044ea + 0x24, 0x00000026		@ 0x0800450E string 1
	.word d_080044ea + 0x4a, 0x00000026		@ 0x08004534 string 2
	.word 0x20000088, 0x0000001a			@ string 3, in RAM
	.word d_080044ea + 0x70, 0x0000001a		@ 0x0800455A
	@ 0x20000150: function table (fn_08002c10 stores 0x20000150 to 0x20000074)
	.word fn_08002d98, fn_08001890, fn_08002d98, fn_08002d98
	.word fn_08002d98, fn_080017b0, fn_08002d98, fn_08002d98
	.word fn_080018c4
	.word 0x00000000, 0x00000001, 0x00000000
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
	@ 0x200001A0
	.byte 0x00
	@ 0x200001A1: SCSI INQUIRY data (36 bytes)
	.byte 0x00, 0x80, 0x02, 0x02, 0x20, 0x00, 0x00, 0x00
	.ascii "FNIRSI  "			@ vendor
	.ascii "HRM-10   IAP    "		@ product
	.ascii "1.0 "				@ revision
	@ 0x200001C5
	.byte 0x03, 0x00, 0x00
	.word 0x00060000, 0x00000000
	.word 0x00007000, 0x00000000, 0x0000000a, 0x00000000
	.word 0x00000000, 0x00000000, 0x00000000, 0x00080000
	.word 0x02000000, 0x00000000, 0x00000000, 0x00000000
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
	.if . - ram_image != 0x220
	.error "the typed RAM image must be 0x220 bytes"
	.endif
.else
	.incbin "assets/vendor/08004594.bin"

@ 0x0800467B: one padding byte (0x00) that aligns the end of the image to 4 bytes.
	.byte 0x00
.endif

	.global image_end
image_end:
