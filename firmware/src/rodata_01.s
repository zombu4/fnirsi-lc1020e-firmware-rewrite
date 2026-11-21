@ rodata_01.s - read-only data part 1 of 4: number and lookup tables, USB descriptors, font and descriptor data blocks (0x0802ae94..0x080371f3)
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
@ Every pointer word of the data is a label (.word d_<address>), so the linker sets it. The
@ addresses in the labels and comments are those of V1.1; in our build (make own) every freed
@ range shrinks to its size mod 4 bytes of 0xFF and the data after it sits lower (link_own.ld).
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

@ ----------------------------------------------------------------------------
@ Font 0x0802ce5c (F1): glyph bitmaps, glyph entries, code lists, range table,
@ kerning class maps and pair values, kerning record, font record, font object.
@ ----------------------------------------------------------------------------

@ 0x0802afd8: glyph bitmap block of the font whose descriptor is at 0x0802ce44 (record +0).
	.global d_0802afd8
d_0802afd8:
.ifdef OWN
@ Our build keeps the bitmaps of glyphs 0..75 (offsets 0..0x72a; glyph 76 starts at 0x72b).
@ Those of the CJK glyphs 76..125 (0x0802b703..0x0802c2a3, 2977 bytes) are freed: with the
@ code count of range 6 (0x0802c788) set to 1, no glyph id above 75 is produced. The freed
@ range keeps 2977 mod 4 = 1 byte of 0xFF, so every later byte keeps its address mod 4.
	.incbin "assets/vendor/0802afd8.bin", 0, 0x72b
	.fill	1, 1, 0xff
.else
	.incbin "assets/vendor/0802afd8.bin"
.endif

@ 0x0802c2a4: glyph entry table (8 bytes per glyph) of the font at 0x0802ce44 (record +4),
@ then the sorted code lists of range 0 (0x0802c694, 3 codes) and range 6 (0x0802c69a, 51
@ codes).
	.global d_0802c2a4
d_0802c2a4:
.ifdef OWN
@ Our build: entries 0..75 kept; entries 76..125 (0x0802c504..0x0802c693, 400 bytes) freed,
@ 400 mod 4 = 0 bytes left; the code lists 0x0802c694..0x0802c69b kept (range 0: 3 codes;
@ range 6: its first code, U+03A9); the 50 CJK codes of range 6 (0x0802c69c..0x0802c6ff,
@ 100 bytes) freed, 0 bytes left.
	.incbin "assets/vendor/0802c2a4.bin", 0, 0x260
	.global d_0802c694
d_0802c694:
	.incbin "assets/vendor/0802c2a4.bin", 0x3f0, 6
	.global d_0802c69a
d_0802c69a:
	.incbin "assets/vendor/0802c2a4.bin", 0x3f6, 2
.else
	.incbin "assets/vendor/0802c2a4.bin", 0, 0x3f0
	.global d_0802c694
d_0802c694:
	.incbin "assets/vendor/0802c2a4.bin", 0x3f0, 6
	.global d_0802c69a
d_0802c69a:
	.incbin "assets/vendor/0802c2a4.bin", 0x3f6
.endif

@ 0x0802c700: range table of the font record 0x0802ce44 (record +8): 7 records of 20 bytes
@ (+0 first code, +4 length, +6 first glyph id, +8 sorted code list, +0xc id list, +0x10 list
@ count, +0x12 type). Ranges 0 and 6 are of type 3 and hold a code list pointer at +8.
	.global d_0802c700
d_0802c700:
	.byte 0x0a, 0x00		@ range 0 +0: first code 0x0a (low half)
	.incbin "assets/vendor/0802c702.bin", 0, 6	@ range 0 +2..+7
	.word d_0802c694		@ range 0 +8: sorted code list (3 codes)
	.incbin "assets/vendor/0802c702.bin", 10, 0x74	@ range 0 +0xc .. range 6 +7
	.word d_0802c69a		@ range 6 +8: sorted code list
.ifdef OWN
@ Our build: the code count of range 6 (halfword 0x0802c788, vendor 0x33) is 1, so the range
@ holds only U+03A9 (glyph 75).
	.incbin "assets/vendor/0802c702.bin", 0x82, 4	@ range 6 +0xc
	.short	0x0001			@ range 6 +0x10: code count
	.incbin "assets/vendor/0802c702.bin", 0x88, 2	@ range 6 +0x12: type
.else
	.incbin "assets/vendor/0802c702.bin", 0x82	@ range 6 +0xc .. +0x13
.endif

@ 0x0802c78c: left kerning class map, one byte per glyph id (kerning record +4).
	.global d_0802c78c
d_0802c78c:
.ifdef OWN
@ Our build: entries 0..75 kept, 76..125 (0x0802c7d8..0x0802c809, 50 bytes) freed; 50 mod 4 =
@ 2 bytes of 0xFF left.
	.incbin "assets/vendor/0802c78c.bin", 0, 0x4c
	.fill	2, 1, 0xff
.else
	.incbin "assets/vendor/0802c78c.bin"
.endif

@ 0x0802c80a: right kerning class map, one byte per glyph id (kerning record +8).
	.global d_0802c80a
d_0802c80a:
.ifdef OWN
@ Our build: entries 0..75 kept, 76..125 (0x0802c856..0x0802c887, 50 bytes) freed; 2 bytes
@ of 0xFF left.
	.incbin "assets/vendor/0802c80a.bin", 0, 0x4c
	.fill	2, 1, 0xff
.else
	.incbin "assets/vendor/0802c80a.bin"
.endif

@ 0x0802c888: kerning pair values, 44 x 33 signed bytes (kerning record +0).
	.global d_0802c888
d_0802c888:
	.incbin "assets/vendor/0802c888.bin"

@ 0x0802ce34: kerning record of the font record 0x0802ce44 (record +0xc).
	.global d_0802ce34
d_0802ce34:
	.word d_0802c888		@ +0 pair values
	.word d_0802c78c		@ +4 left class map
	.word d_0802c80a		@ +8 right class map
	.word 0x0000212c		@ +0xc left count 0x2c, +0xd right count 0x21
@ 0x0802ce44: font record of the font object 0x0802ce5c (object +0x10).
	.global d_0802ce44
d_0802ce44:
	.word d_0802afd8		@ +0 glyph bitmaps
	.word d_0802c2a4		@ +4 glyph entries
	.word d_0802c700		@ +8 range table
	.word d_0802ce34		@ +0xc kerning record
	.byte 0x10, 0x00, 0x07, 0x24	@ +0x10 kern scale 0x10, +0x12 0x2407 (7 ranges, bits 9..15)
	.word 0x20000444		@ +0x14 8-byte glyph cache in RAM (a RAM address, a number)

@ 0x0802ce5c: font object F1 (two function pointers followed by its fields).
	.global d_0802ce5c
d_0802ce5c:
	.word fn_08020968
	.word fn_08020894
	.byte 0x12, 0x00, 0x04, 0x00, 0x00, 0xfe, 0x01, 0x00	@ +8 line height 0x12, +0xa base
					@ line 4, +0xc subpx 0, +0xd underline 0xfe, +0xe 1
	.word d_0802ce44		@ +0x10 font record
	.word 0x00000000		@ +0x14 next font: none
	.word 0x00000000		@ +0x18

@ ----------------------------------------------------------------------------
@ Font 0x0802f0d8 (F2), the same layout.
@ ----------------------------------------------------------------------------

@ 0x0802ce78: glyph bitmap block of the font at 0x0802f0d8 (record +0).
	.global d_0802ce78
d_0802ce78:
	.incbin "assets/vendor/0802ce78.bin"

@ 0x0802d1bf: string of 14 equals signs plus NUL.
	.asciz "=============="

@ 0x0802d1ce: rest of the glyph bitmap block that starts at 0x0802ce78 (font at 0x0802f0d8),
@ read as [dsc+0] + bitmap_index by fn_08020894.
.ifdef OWN
@ Our build keeps the bitmaps of glyphs 0..68 (glyph 69 starts at bitmap offset 0x9d7,
@ 0x0802d84f). Those of the CJK glyphs 69..111 (0x0802d84f..0x0802e78f, 3905 bytes) are freed:
@ with the code count of range 4 (0x0802ebd4) set to 1, no glyph id above 68 is produced;
@ 3905 mod 4 = 1 byte of 0xFF left.
	.incbin "assets/vendor/0802d1ce.bin", 0, 0x681
	.fill	1, 1, 0xff
.else
	.incbin "assets/vendor/0802d1ce.bin"
.endif

@ 0x0802e790: glyph entry table (record +4), then the code lists of range 0 (0x0802eb10, 5
@ codes) and range 4 (0x0802eb1a, 44 codes) and 2 bytes.
	.global d_0802e790
d_0802e790:
.ifdef OWN
@ Our build: entries 0..68 kept; entries 69..111 (0x0802e9b8..0x0802eb0f, 344 bytes) freed, 0
@ bytes left; the code lists 0x0802eb10..0x0802eb1b kept (range 0: 5 codes; range 4: its first
@ code, U+03A9); the 43 CJK codes of range 4 (0x0802eb1c..0x0802eb71, 86 bytes) freed, 2 bytes
@ of 0xFF left; 0x0802eb72..0x0802eb73 kept.
	.incbin "assets/vendor/0802e790.bin", 0, 0x228
	.global d_0802eb10
d_0802eb10:
	.incbin "assets/vendor/0802e790.bin", 0x380, 10
	.global d_0802eb1a
d_0802eb1a:
	.incbin "assets/vendor/0802e790.bin", 0x38a, 2
	.fill	2, 1, 0xff
	.incbin "assets/vendor/0802e790.bin", 0x3e2, 2
.else
	.incbin "assets/vendor/0802e790.bin", 0, 0x380
	.global d_0802eb10
d_0802eb10:
	.incbin "assets/vendor/0802e790.bin", 0x380, 10
	.global d_0802eb1a
d_0802eb1a:
	.incbin "assets/vendor/0802e790.bin", 0x38a
.endif

@ 0x0802eb74: range table of the font record 0x0802f0c0 (record +8): 5 records of 20 bytes,
@ the layout of 0x0802c700. Ranges 0 and 4 are of type 3 and hold a code list pointer at +8.
	.global d_0802eb74
d_0802eb74:
	.byte 0x0a, 0x00		@ range 0 +0: first code 0x0a (low half)
	.incbin "assets/vendor/0802eb76.bin", 0, 6	@ range 0 +2..+7
	.word d_0802eb10		@ range 0 +8: sorted code list (5 codes)
	.incbin "assets/vendor/0802eb76.bin", 10, 0x4c	@ range 0 +0xc .. range 4 +7
	.word d_0802eb1a		@ range 4 +8: sorted code list
.ifdef OWN
@ Our build: the code count of range 4 (halfword 0x0802ebd4, vendor 0x2c) is 1, so the range
@ holds only U+03A9 (glyph 68).
	.incbin "assets/vendor/0802eb76.bin", 0x5a, 4	@ range 4 +0xc
	.short	0x0001			@ range 4 +0x10: code count
	.incbin "assets/vendor/0802eb76.bin", 0x60, 2	@ range 4 +0x12: type
.else
	.incbin "assets/vendor/0802eb76.bin", 0x5a	@ range 4 +0xc .. +0x13
.endif

@ 0x0802ebd8: left kerning class map, one byte per glyph id (kerning record +4).
	.global d_0802ebd8
d_0802ebd8:
.ifdef OWN
@ Our build: entries 0..68 kept, 69..111 (0x0802ec1d..0x0802ec47, 43 bytes) freed; 43 mod 4 =
@ 3 bytes of 0xFF left.
	.incbin "assets/vendor/0802ebd8.bin", 0, 0x45
	.fill	3, 1, 0xff
.else
	.incbin "assets/vendor/0802ebd8.bin"
.endif

@ 0x0802ec48: right kerning class map (kerning record +8).
	.global d_0802ec48
d_0802ec48:
.ifdef OWN
@ Our build: entries 0..68 kept, 69..111 (0x0802ec8d..0x0802ecb7, 43 bytes) freed; 3 bytes of
@ 0xFF left.
	.incbin "assets/vendor/0802ec48.bin", 0, 0x45
	.fill	3, 1, 0xff
.else
	.incbin "assets/vendor/0802ec48.bin"
.endif

@ 0x0802ecb8: kerning pair values, 39 x 26 signed bytes and 2 bytes (kerning record +0).
	.global d_0802ecb8
d_0802ecb8:
	.incbin "assets/vendor/0802ecb8.bin"

@ 0x0802f0b0: kerning record of the font record 0x0802f0c0 (record +0xc).
	.global d_0802f0b0
d_0802f0b0:
	.word d_0802ecb8		@ +0 pair values
	.word d_0802ebd8		@ +4 left class map
	.word d_0802ec48		@ +8 right class map
	.word 0x00001a27		@ +0xc left count 0x27, +0xd right count 0x1a
@ 0x0802f0c0: font record of the font object 0x0802f0d8 (object +0x10).
	.global d_0802f0c0
d_0802f0c0:
	.word d_0802ce78		@ +0 glyph bitmaps
	.word d_0802e790		@ +4 glyph entries
	.word d_0802eb74		@ +8 range table
	.word d_0802f0b0		@ +0xc kerning record
	.byte 0x10, 0x00, 0x05, 0x24	@ +0x10 kern scale 0x10, +0x12 0x2405 (5 ranges, bits 9..15)
	.word 0x2000044c		@ +0x14 8-byte glyph cache in RAM (a RAM address, a number)

@ 0x0802f0d8: font object F2 (two function pointers followed by its fields).
	.global d_0802f0d8
d_0802f0d8:
	.word fn_08020968
	.word fn_08020894
	.byte 0x16, 0x00, 0x04, 0x00, 0x00, 0xfe, 0x01, 0x00	@ +8 line height 0x16, +0xa base
					@ line 4, +0xc subpx 0, +0xd underline 0xfe, +0xe 1
	.word d_0802f0c0		@ +0x10 font record
	.word 0x00000000		@ +0x14 next font: none
	.word 0x00000000		@ +0x18

@ ----------------------------------------------------------------------------
@ Font 0x0802f5e8 (F3): glyph bitmaps, 12 glyph entries, the glyph id offset list, one range,
@ the font record and the object.
@ ----------------------------------------------------------------------------

@ 0x0802f0f4: glyph bitmap block of the font at 0x0802f5e8 (record +0), read as [dsc+0] +
@ bitmap_index by fn_08020894.
	.global d_0802f0f4
d_0802f0f4:
	.incbin "assets/vendor/0802f0f4.bin"

@ 0x0802f550: glyph entry table (record +4, 12 entries), then the 12-byte glyph id offset
@ list 0x0802f5b0 (range +0xc, type 0: read as byte[list + offset] at 0x0801B208).
	.global d_0802f550
d_0802f550:
	.incbin "assets/vendor/0802f550.bin", 0, 0x60
	.global d_0802f5b0
d_0802f5b0:
	.incbin "assets/vendor/0802f550.bin", 0x60

@ 0x0802f5bc: range record of the font record 0x0802f5d0 (record +8), the 20-byte layout of
@ 0x0802c700: first code 0x2e, length 12, glyph ids from 1, type 0 with the offset list at
@ +0xc.
	.global d_0802f5bc
d_0802f5bc:
	.word 0x0000002e		@ +0 first code
	.short 0x000c, 0x0001		@ +4 length, +6 first glyph id
	.word 0x00000000		@ +8 no code list
	.word d_0802f5b0		@ +0xc glyph id offset list
	.short 0x000c, 0x0000		@ +0x10 list count, +0x12 type 0

@ 0x0802f5d0: font record of the font object 0x0802f5e8 (object +0x10).
	.global d_0802f5d0
d_0802f5d0:
	.word d_0802f0f4		@ +0 glyph bitmaps
	.word d_0802f550		@ +4 glyph entries
	.word d_0802f5bc		@ +8 range table
	.word 0x00000000		@ +0xc no kerning record
	.byte 0x00, 0x00, 0x01, 0x04	@ +0x10 kern scale 0, +0x12 0x0401 (1 range, bits 9..15)
	.word 0x20000454		@ +0x14 8-byte glyph cache in RAM (a RAM address, a number)

@ 0x0802f5e8: font object F3: two function pointers (fn_08020968, fn_08020894) and its
@ fields; the record pointer +0x10 is typed, the other field bytes come from the block
@ 0802f5f0.bin, which then holds the 2340 data bytes of the descriptor at 0x0802ff28. The
@ address is passed as r1 to the call 0x080266ac.
	.global d_0802f5e8
d_0802f5e8:
	.word fn_08020968
	.word fn_08020894
	.incbin "assets/vendor/0802f5f0.bin", 0, 8	@ +8 line height 0x1b, +0xa base line 6,
					@ +0xc subpx 0, +0xd underline 0xfe, +0xe 2
	.word d_0802f5d0		@ +0x10 font record
	.incbin "assets/vendor/0802f5f0.bin", 12, 8	@ +0x14 next font (0), +0x18 (0)
	.global d_0802f604
d_0802f604:				@ data of the image 0x0802ff28
	.incbin "assets/vendor/0802f5f0.bin", 0x14

@ ----------------------------------------------------------------------------
@ Images. Each image is its data (palette and pixel bytes) followed by 0..3 padding bytes
@ and its 12-byte descriptor: header word (bits 0..4 colour format cf, bits 10..20 width,
@ bits 21..31 height), size word, data pointer word (the label of the data). The code holds
@ the descriptor address; each vendor block begins with a descriptor and goes on with the
@ data of the next image, so the descriptor words are typed and the block follows from
@ offset 12.
@ ----------------------------------------------------------------------------

@ 0x0802ff28: data block of 2352 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x0802f604) followed by 2340 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 0; the block is passed as r1 to fn_08021c14.
	.global d_0802ff28
d_0802ff28:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_0802f604		@ data
	.global d_0802ff34
d_0802ff34:
	.incbin "assets/vendor/0802ff28.bin", 12

@ 0x08030858: data block of 2352 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x0802ff34) followed by 2340 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 1.
	.global d_08030858
d_08030858:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_0802ff34		@ data
	.global d_08030864
d_08030864:
	.incbin "assets/vendor/08030858.bin", 12

@ 0x08031188: data block of 2352 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x08030864) followed by 2340 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 2.
	.global d_08031188
d_08031188:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_08030864		@ data
	.global d_08031194
d_08031194:
	.incbin "assets/vendor/08031188.bin", 12

@ 0x08031ab8: data block of 2352 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x08031194) followed by 2340 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 3.
	.global d_08031ab8
d_08031ab8:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_08031194		@ data
	.global d_08031ac4
d_08031ac4:
	.incbin "assets/vendor/08031ab8.bin", 12

@ 0x080323e8: data block of 2352 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x08031ac4) followed by 2340 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 4.
	.global d_080323e8
d_080323e8:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_08031ac4		@ data
	.global d_080323f4
d_080323f4:
	.incbin "assets/vendor/080323e8.bin", 12

@ 0x08032d18: data block of 2352 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x080323f4) followed by 2340 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 5.
	.global d_08032d18
d_08032d18:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_080323f4		@ data
	.global d_08032d24
d_08032d24:
	.incbin "assets/vendor/08032d18.bin", 12

@ 0x08033648: data block of 2352 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x08032d24) followed by 2340 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 6.
	.global d_08033648
d_08033648:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_08032d24		@ data
	.global d_08033654
d_08033654:
	.incbin "assets/vendor/08033648.bin", 12

@ 0x08033f78: data block of 2352 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x08033654) followed by 2340 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 7.
	.global d_08033f78
d_08033f78:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_08033654		@ data
	.global d_08033f84
d_08033f84:
	.incbin "assets/vendor/08033f78.bin", 12

@ 0x080348a8: data block of 2352 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x08033f84) followed by 2340 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 8.
	.global d_080348a8
d_080348a8:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_08033f84		@ data
	.global d_080348b4
d_080348b4:
	.incbin "assets/vendor/080348a8.bin", 12

@ 0x080351d8: data block of 220 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x080348b4) followed by 208 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 9.
	.global d_080351d8
d_080351d8:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_080348b4		@ data
	.global d_080351e4
d_080351e4:
	.incbin "assets/vendor/080351d8.bin", 12

@ 0x080352b4: data block of 1116 bytes: 12-byte descriptor (words 0x05e01809, 205,
@ 0x080351e4) followed by 1104 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 11.
	.global d_080352b4
d_080352b4:
	.word 0x05e01809		@ cf 9, 6 x 47
	.word 205			@ size
	.word d_080351e4		@ data
	.global d_080352c0
d_080352c0:
	.incbin "assets/vendor/080352b4.bin", 12

@ 0x08035710: data block of 2352 bytes: 12-byte descriptor (words 0x00c0340a, 1102,
@ 0x080352c0) followed by 2340 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 12.
	.global d_08035710
d_08035710:
	.word 0x00c0340a		@ cf 10, 13 x 6
	.word 1102			@ size
	.word d_080352c0		@ data
	.global d_0803571c
d_0803571c:
	.incbin "assets/vendor/08035710.bin", 12

@ 0x08036040: data block of 2352 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x0803571c) followed by 2340 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 13.
	.global d_08036040
d_08036040:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_0803571c		@ data
	.global d_0803604c
d_0803604c:
	.incbin "assets/vendor/08036040.bin", 12

@ 0x08036970: data block of 436 bytes: 12-byte descriptor (words 0x05e0700a, 2340,
@ 0x0803604c) followed by 424 bytes. fn_0800d14c stores the address as the table entry
@ for glyph index 10.
	.global d_08036970
d_08036970:
	.word 0x05e0700a		@ cf 10, 28 x 47
	.word 2340			@ size
	.word d_0803604c		@ data
	.global d_0803697c
d_0803697c:
	.incbin "assets/vendor/08036970.bin", 12

@ 0x08036b24: data block of 436 bytes: 12-byte descriptor (words 0x02a08409, 421,
@ 0x0803697c) followed by 424 bytes. Loaded by fn_0800d294 and fn_0800d3d8 and passed as
@ r1 to fn_08021c14.
	.global d_08036b24
d_08036b24:
	.word 0x02a08409		@ cf 9, 33 x 21
	.word 421			@ size
	.word d_0803697c		@ data
	.global d_08036b30
d_08036b30:
	.incbin "assets/vendor/08036b24.bin", 12

@ 0x08036cd8: data block of 436 bytes: 12-byte descriptor (words 0x02a08409, 421,
@ 0x08036b30) followed by 424 bytes. Loaded by fn_0800d294 and fn_0800d3d8 and passed as
@ r1 to fn_08021c14.
	.global d_08036cd8
d_08036cd8:
	.word 0x02a08409		@ cf 9, 33 x 21
	.word 421			@ size
	.word d_08036b30		@ data
	.global d_08036ce4
d_08036ce4:
	.incbin "assets/vendor/08036cd8.bin", 12

@ 0x08036e8c: data block of 436 bytes: 12-byte descriptor (words 0x02a08409, 421,
@ 0x08036ce4) followed by 424 bytes. Loaded by fn_0800d294 and fn_0800d3d8 and passed as
@ r1 to fn_08021c14.
	.global d_08036e8c
d_08036e8c:
	.word 0x02a08409		@ cf 9, 33 x 21
	.word 421			@ size
	.word d_08036ce4		@ data
	.global d_08036e98
d_08036e98:
	.incbin "assets/vendor/08036e8c.bin", 12

@ 0x08037040: data block of 436 bytes: 12-byte descriptor (words 0x02a08409, 421,
@ 0x08036e98) followed by 424 bytes (ends the part at 0x080371f3). Loaded by fn_0800d294
@ and fn_0800d3d8 and passed as r1 to fn_08021c14.
	.global d_08037040
d_08037040:
	.word 0x02a08409		@ cf 9, 33 x 21
	.word 421			@ size
	.word d_08036e98		@ data
	.global d_0803704c
d_0803704c:
	.incbin "assets/vendor/08037040.bin", 12
