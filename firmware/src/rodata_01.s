@ rodata_01.s - read-only data part 1 of 4: number and lookup tables, USB descriptors, font and bitmap data (0x0802ae94..0x080371f3)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.section .rodata.fixed.0802ae94,"a",%progbits
	.global rodata_start
rodata_start:

@ ----------------------------------------------------------------------------
@ 0x0802ae94: table of five 32-bit words (100, 120, 1000, 10000, 100000).
@ A function at 0x080090a4 copies these 20 bytes to the stack and compares
@ each word with its argument. The table starts with the 2 bytes of 100
@ below, the rest follows in the next piece; a second identical 5-word
@ table follows at 0x0802aea8 (no reader recorded).
@ ----------------------------------------------------------------------------
	.global d_0802ae94
d_0802ae94:
	.byte 0x64, 0x00		@ low half of the word 100
	.byte 0x00, 0x00		@ high half of the word 100
	.word 120
	.word 1000
	.word 10000
	.word 100000
	.word 100			@ second identical table at 0x0802aea8
	.word 120
	.word 1000
	.word 10000
	.word 100000

@ 0x0802aebc: 20-byte table of words 100, 120, 1000, 10000, 100000, copied to the stack
@ by the function at 0x0800901c and compared with its argument.
	.global d_0802aebc
d_0802aebc:
	.byte 0x64, 0x00
	.byte 0x00, 0x00, 0x78, 0x00, 0x00, 0x00, 0xe8, 0x03
	.byte 0x00, 0x00, 0x10, 0x27, 0x00, 0x00, 0xa0, 0x86
	.byte 0x01, 0x00

@ 0x0802aed0: 20-byte table of words 100, 120, 1000, 10000, 100000, copied to the stack
@ by the function at 0x08008f94 and compared with its argument.
	.global d_0802aed0
d_0802aed0:
	.byte 0x64, 0x00
	.byte 0x00, 0x00, 0x78, 0x00, 0x00, 0x00, 0xe8, 0x03
	.byte 0x00, 0x00, 0x10, 0x27, 0x00, 0x00, 0xa0, 0x86
	.byte 0x01, 0x00

@ 0x0802aee4: byte table 1, 2, 4, 8, 0x10, 0x20, 0x40, 0x80 (powers of two 2^0..2^7),
@ indexed by the function at 0x0800a068 and converted to float.
	.global d_0802aee4
d_0802aee4:
	.byte 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

@ 0x0802aeec: table of the words 100, 1000, 10000, 100000, indexed by the function at
@ 0x0800a068 (ldr with index shifted left by 2) and converted to float.
	.global d_0802aeec
d_0802aeec:
	.byte 0x64, 0x00
	.byte 0x00, 0x00, 0xe8, 0x03, 0x00, 0x00, 0x10, 0x27
	.byte 0x00, 0x00, 0xa0, 0x86, 0x01, 0x00

@ 0x0802aefc: byte table of right-shift counts indexed 0..15, read by the function at 0x0800b364
@ with the index (word at 0x40021004 >> 4) & 0xf.
	.global d_0802aefc
d_0802aefc:
	.byte 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04
	.byte 0x01, 0x02, 0x03, 0x04, 0x06, 0x07, 0x08, 0x09

@ 0x0802af0c: byte divisor table indexed 0..15 (1, 2, 4, 6, 8, 10, 12, 16, then 32 eight times),
@ read by the function at 0x0800b364.
	.byte 0x01, 0x02, 0x04, 0x06, 0x08, 0x0a, 0x0c, 0x10
	.byte 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20

@ 0x0802af1c: 16 halfwords 1, 2, 4, 6, 8, 10, 12, 16, 32, 64, 128, 256 and four more 256
@ (indexed by the function at 0x0800b364), followed by the device descriptor
@ bytes: 12 01 00 02 00 00 00 40 f5 19 40 57 00 02 01 02 03 01.
	.short 0x0001, 0x0002, 0x0004, 0x0006, 0x0008, 0x000a, 0x000c, 0x0010
	.short 0x0020, 0x0040, 0x0080, 0x0100, 0x0100, 0x0100, 0x0100, 0x0100
	.byte 0x12, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x40	@ USB device descriptor, 18 bytes
	.byte 0xf5, 0x19, 0x40, 0x57, 0x00, 0x02, 0x01, 0x02
	.byte 0x03, 0x01

@ 0x0802af4e: USB configuration descriptor (09 02 20 00 01 01 00 c0 64): total length 0x20,
@ one interface, configuration value 1, attributes 0xc0, bMaxPower 0x64 (0x64 follows in
@ the next piece).
	.global d_0802af4e
d_0802af4e:
	.byte 0x09, 0x02, 0x20, 0x00, 0x01, 0x01, 0x00

	.byte 0xc0			@ configuration descriptor attributes

@ 0x0802af56: rest of the USB descriptor set (bMaxPower, interface and endpoint descriptors,
@ string descriptors).
	.incbin "assets/vendor/0802af56.bin"

@ 0x0802afd8: glyph bitmap block of the font whose descriptor is at 0x0802ce44.
	.incbin "assets/vendor/0802afd8.bin"

@ 0x0802c2a4: glyph entry table (8 bytes per glyph) of the font at 0x0802ce44.
	.incbin "assets/vendor/0802c2a4.bin"

@ 0x0802c700: halfword 0x000a (text 0x0a, 0x00).
	.byte 0x0a, 0x00

@ 0x0802c702: font data block (header and glyph range tables).
	.incbin "assets/vendor/0802c702.bin"

@ 0x0802c78c: font index table.
	.incbin "assets/vendor/0802c78c.bin"

@ 0x0802c80a: font index table.
	.incbin "assets/vendor/0802c80a.bin"

@ 0x0802c888: data block referenced by the first word of the descriptor at 0x0802ce34.
	.incbin "assets/vendor/0802c888.bin"

@ 0x0802ce34: font descriptor, pointer words into the font data above.
	.word 0x0802c888
	.word 0x0802c78c
	.word 0x0802c80a
	.word 0x0000212c
	.word 0x0802afd8		@ glyph bitmaps
	.word 0x0802c2a4		@ glyph entries
	.word 0x0802c700
	.word 0x0802ce34
	.byte 0x10, 0x00, 0x07, 0x24, 0x44, 0x04, 0x00, 0x20

@ 0x0802ce5c: object with two function pointers followed by its fields.
	.global d_0802ce5c
d_0802ce5c:
	.word fn_08020968
	.word fn_08020894
	.byte 0x12, 0x00, 0x04, 0x00, 0x00, 0xfe, 0x01, 0x00
	.byte 0x44, 0xce, 0x02, 0x08, 0x00, 0x00, 0x00, 0x00
	.byte 0x00, 0x00, 0x00, 0x00

@ 0x0802ce78: data block referenced by the descriptor at 0x0802ce5c.
	.incbin "assets/vendor/0802ce78.bin"

@ 0x0802d1bf: string of 14 equals signs plus NUL.
	.asciz "=============="

@ 0x0802d1ce: bitmap data.
	.incbin "assets/vendor/0802d1ce.bin"

@ 0x0802e790: glyph entry table.
	.incbin "assets/vendor/0802e790.bin"

@ 0x0802eb74: halfword 0x000a.
	.byte 0x0a, 0x00

@ 0x0802eb76: font data block.
	.incbin "assets/vendor/0802eb76.bin"

@ 0x0802ebd8: font index table.
	.incbin "assets/vendor/0802ebd8.bin"

@ 0x0802ec48: font index table.
	.incbin "assets/vendor/0802ec48.bin"

@ 0x0802ecb8: font offset data.
	.incbin "assets/vendor/0802ecb8.bin"

@ 0x0802f0b0: font descriptor pointer words.
	.word 0x0802ecb8
	.word 0x0802ebd8
	.word 0x0802ec48
	.word 0x00001a27
	.word 0x0802ce78
	.word 0x0802e790
	.word 0x0802eb74
	.word 0x0802f0b0
	.byte 0x10, 0x00, 0x05, 0x24, 0x4c, 0x04, 0x00, 0x20

@ 0x0802f0d8: object with two function pointers followed by its fields.
	.global d_0802f0d8
d_0802f0d8:
	.word fn_08020968
	.word fn_08020894
	.byte 0x16, 0x00, 0x04, 0x00, 0x00, 0xfe, 0x01, 0x00
	.byte 0xc0, 0xf0, 0x02, 0x08, 0x00, 0x00, 0x00, 0x00
	.byte 0x00, 0x00, 0x00, 0x00

@ 0x0802f0f4: bitmap data.
	.incbin "assets/vendor/0802f0f4.bin"

@ 0x0802f550: glyph entry table.
	.incbin "assets/vendor/0802f550.bin"

@ 0x0802f5bc: halfword 0x002e.
	.byte 0x2e, 0x00

@ 0x0802f5be: font descriptor fields.
	.byte 0x00, 0x00, 0x0c, 0x00, 0x01, 0x00, 0x00, 0x00
	.byte 0x00, 0x00, 0xb0, 0xf5, 0x02, 0x08, 0x0c, 0x00
	.byte 0x00, 0x00

@ 0x0802f5d0: pointer words into the font data above.
	.word 0x0802f0f4
	.word 0x0802f550
	.word 0x0802f5bc
	.byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x04
	.byte 0x54, 0x04, 0x00, 0x20

@ 0x0802f5e8: object with two function pointers followed by a bitmap image (header and pixel data).
	.global d_0802f5e8
d_0802f5e8:
	.word fn_08020968
	.word fn_08020894
	.incbin "assets/vendor/0802f5f0.bin"

@ 0x0802ff28: bitmap image.
	.global d_0802ff28
d_0802ff28:
	.incbin "assets/vendor/0802ff28.bin"

@ 0x08030858: bitmap image.
	.global d_08030858
d_08030858:
	.incbin "assets/vendor/08030858.bin"

@ 0x08031188: bitmap image.
	.global d_08031188
d_08031188:
	.incbin "assets/vendor/08031188.bin"

@ 0x08031ab8: bitmap image.
	.global d_08031ab8
d_08031ab8:
	.incbin "assets/vendor/08031ab8.bin"

@ 0x080323e8: bitmap image.
	.global d_080323e8
d_080323e8:
	.incbin "assets/vendor/080323e8.bin"

@ 0x08032d18: bitmap image.
	.global d_08032d18
d_08032d18:
	.incbin "assets/vendor/08032d18.bin"

@ 0x08033648: bitmap image.
	.global d_08033648
d_08033648:
	.incbin "assets/vendor/08033648.bin"

@ 0x08033f78: bitmap image.
	.global d_08033f78
d_08033f78:
	.incbin "assets/vendor/08033f78.bin"

@ 0x080348a8: bitmap image.
	.global d_080348a8
d_080348a8:
	.incbin "assets/vendor/080348a8.bin"

@ 0x080351d8: bitmap image.
	.global d_080351d8
d_080351d8:
	.incbin "assets/vendor/080351d8.bin"

@ 0x080352b4: bitmap image.
	.global d_080352b4
d_080352b4:
	.incbin "assets/vendor/080352b4.bin"

@ 0x08035710: bitmap image.
	.global d_08035710
d_08035710:
	.incbin "assets/vendor/08035710.bin"

@ 0x08036040: bitmap image.
	.global d_08036040
d_08036040:
	.incbin "assets/vendor/08036040.bin"

@ 0x08036970: bitmap image.
	.global d_08036970
d_08036970:
	.incbin "assets/vendor/08036970.bin"

@ 0x08036b24: bitmap image.
	.global d_08036b24
d_08036b24:
	.incbin "assets/vendor/08036b24.bin"

@ 0x08036cd8: bitmap image.
	.global d_08036cd8
d_08036cd8:
	.incbin "assets/vendor/08036cd8.bin"

@ 0x08036e8c: bitmap image.
	.global d_08036e8c
d_08036e8c:
	.incbin "assets/vendor/08036e8c.bin"

@ 0x08037040: bitmap image (ends the part at 0x080371f3).
	.global d_08037040
d_08037040:
	.incbin "assets/vendor/08037040.bin"
