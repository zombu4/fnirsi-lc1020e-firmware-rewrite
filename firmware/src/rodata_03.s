@ rodata_03.s - read-only data 0x0804bbf8..0x0805113b: image records, class records, FFT and sine tables, double-precision math tables, strings
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
@ Every pointer word is a label. The addresses in labels and comments are those of V1.1; in our
@ build (make own) the part sits lower (link_own.ld).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.section .rodata.fixed.0804bbf8,"a",%progbits

@ ----------------------------------------------------------------------------
@ Image records and image data (0x0804bbf8..0x0804fcdf). Each record is a 12-byte
@ descriptor: header word (bits 0-4, bits 10-20, bits 21-31 hold three fields),
@ a size field and a data pointer to the pixel data stored just before the
@ record. The code passes a record address in r1 to the function at 0x08021c14,
@ which stores it at [object+0x24] when 0x08021d60 returns 0. The descriptor
@ words are typed (the data pointer as the label of the data); each vendor
@ block follows from offset 12 (or 9 after a typed 3-byte start).
@ ----------------------------------------------------------------------------

@ 300 bytes: descriptor 0x0804bbf8 (header 0x0484E009, size 5680, data pointer
@ 0x0804a5c8) followed by the 288 data bytes of the next record. Loaded in the
@ function at 0x0800f294.
	.global d_0804bbf8
d_0804bbf8:
	.word 0x0484e009		@ cf 9, 312 x 36
	.word 5680			@ size
	.word d_0804a5c8		@ data
	.global d_0804bc04
d_0804bc04:
	.incbin "assets/vendor/0804bbf8.bin", 12

@ 92 bytes: descriptor 0x0804bd24 (header 0x01C07C09, size 288, data pointer
@ 0x0804bc04) followed by 80 bytes of data of the record at 0x0804bda4.
	.global d_0804bd24
d_0804bd24:
	.word 0x01c07c09		@ cf 9, 31 x 14
	.word 288			@ size
	.word d_0804bc04		@ data
	.global d_0804bd30
d_0804bd30:
	.incbin "assets/vendor/0804bd24.bin", 12

@ Five words 0x20000000 (no reference proves an address; written as numbers)
	.word 0x20000000
	.word 0x20000000
	.word 0x20000000
	.word 0x20000000
	.word 0x20000000

@ 16 bytes of image data (inside the data of the record at 0x0804bda4), reached
@ only through the data pointer stored in that record
	.byte 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x10
	.byte 0x00, 0x00, 0x00, 0x10, 0x44, 0x44, 0x44, 0x50

@ 3356 bytes: descriptor 0x0804bda4 (header 0x01A01C09, size 116, data pointer
@ 0x0804bd30) followed by the 3344 data bytes of the record at 0x0804cac0.
	.global d_0804bda4
d_0804bda4:
	.word 0x01a01c09		@ cf 9, 7 x 13
	.word 116			@ size
	.word d_0804bd30		@ data
	.global d_0804bdb0
d_0804bdb0:
	.incbin "assets/vendor/0804bda4.bin", 12

@ 180 bytes: descriptor 0x0804cac0 (header 0x0281D00A, size 3344, data pointer
@ 0x0804bdb0) followed by the 168 data bytes of the record at 0x0804cb74.
@ Loaded in the function at 0x0800e6c8.
	.global d_0804cac0
d_0804cac0:
	.word 0x0281d00a		@ cf 10, 116 x 20
	.word 3344			@ size
	.word d_0804bdb0		@ data
	.global d_0804cacc
d_0804cacc:
	.incbin "assets/vendor/0804cac0.bin", 12

@ 204 bytes: descriptor 0x0804cb74 (header 0x01A04009, size 168, data pointer
@ 0x0804cacc) followed by the 192 data bytes of the record at 0x0804cc40.
	.global d_0804cb74
d_0804cb74:
	.word 0x01a04009		@ cf 9, 16 x 13
	.word 168			@ size
	.word d_0804cacc		@ data
	.global d_0804cb80
d_0804cb80:
	.incbin "assets/vendor/0804cb74.bin", 12

@ Descriptor at 0x0804cc40 (header 0x02004009, size 192, data pointer
@ 0x0804cb80), typed; the block 0804cc43.bin holds its last 9 bytes and then
@ the 3396 data bytes of the record at 0x0804d990
	.global d_0804cc40
d_0804cc40:
	.word 0x02004009		@ cf 9, 16 x 16
	.word 192			@ size
	.word d_0804cb80		@ data
	.global d_0804cc4c
d_0804cc4c:
	.incbin "assets/vendor/0804cc43.bin", 9

@ 204 bytes: descriptor 0x0804d990 (header 0x08818809, size 3396, data pointer
@ 0x0804cc4c) followed by the 190 data bytes of the record at 0x0804da5c.
	.global d_0804d990
d_0804d990:
	.word 0x08818809		@ cf 9, 98 x 68
	.word 3396			@ size
	.word d_0804cc4c		@ data
	.global d_0804d99c
d_0804d99c:
	.incbin "assets/vendor/0804d990.bin", 12

@ 7668 bytes: descriptor 0x0804da5c (header 0x02403409, size 190, data pointer
@ 0x0804d99c) followed by the 7656 data bytes of the record at 0x0804f850.
	.global d_0804da5c
d_0804da5c:
	.word 0x02403409		@ cf 9, 13 x 18
	.word 190			@ size
	.word d_0804d99c		@ data
	.global d_0804da68
d_0804da68:
	.incbin "assets/vendor/0804da5c.bin", 12

@ 584 bytes: descriptor 0x0804f850 (header 0x0D024809, size 7656, data pointer
@ 0x0804da68) followed by the 570 data bytes of the record at 0x0804fa98.
	.global d_0804f850
d_0804f850:
	.word 0x0d024809		@ cf 9, 146 x 104
	.word 7656			@ size
	.word d_0804da68		@ data
	.global d_0804f85c
d_0804f85c:
	.incbin "assets/vendor/0804f850.bin", 12

@ 80 bytes: descriptor 0x0804fa98 (header 0x02E0B009, size 570, data pointer
@ 0x0804f85c) followed by 68 bytes of data of the record at 0x0804fce0.
	.global d_0804fa98
d_0804fa98:
	.word 0x02e0b009		@ cf 9, 44 x 23
	.word 570			@ size
	.word d_0804f85c		@ data
	.global d_0804faa4
d_0804faa4:
	.incbin "assets/vendor/0804fa98.bin", 12

@ 16 bytes of image data: "Fgwwwwwwwwwwvd " and a NUL
	.ascii "Fgwwwwwwwwwwvd "
	.byte 0x00

@ 468 bytes of image data (inside the data of the record at 0x0804fce0)
	.incbin "assets/vendor/0804faf8.bin"

@ 16 bytes of image data: "Fwwwwwwwwwwwvd " and a NUL
	.ascii "Fwwwwwwwwwwwvd "
	.byte 0x00

@ Last 2 data bytes of the record at 0x0804fce0 plus 2 padding bytes
	.word 0x00000000

@ 12 bytes: descriptor 0x0804fce0 (header 0x02E0B009, size 570, data pointer
@ 0x0804faa4). Loaded in the function at 0x0800e6c8.
	.global d_0804fce0
d_0804fce0:
	.word 0x02e0b009		@ cf 9, 44 x 23
	.word 0x0000023a		@ size 570
	.word d_0804faa4		@ data

@ ----------------------------------------------------------------------------
@ FFT descriptor (0x0804fcec): halfword +0 length n = 128, word +4 twiddle table
@ (0x0804fd74, 256 floats cos/sin of 2*pi*k/128), word +8 bit-reverse table
@ (0x08050174, 208 halfwords), halfword +12 bit-reverse count = 208. Loaded by
@ the function at 0x0800a068, followed by a call of 0x080069dc.
@ ----------------------------------------------------------------------------
	.global d_0804fcec
d_0804fcec:
	.short 0x0080
	.short 0x0000
	.word d_0804fd74		@ +4 twiddle table
	.word d_08050174		@ +8 bit-reverse table
	.word 0x000000d0

@ ----------------------------------------------------------------------------
@ Class records. Word +0 is the parent class record (0 for the base class),
@ word +4 and +8 are function pointers, word +0x10 is read by the function at
@ 0x08023d54, word +0x18 holds the object size ((word & 0xfffff) >> 4) read by
@ the function at 0x080233c4.
@ ----------------------------------------------------------------------------

@ Base class record (28 bytes): no parent, object size 0x24 bytes
	.global d_0804fcfc
d_0804fcfc:
	.word 0x00000000
	.word fn_08023604
	.word fn_080236fc
	.word 0x00000000
	.word fn_08023a28
	.short 0x008f
	.short 0x008f
	.word 0x0000024a

@ Two words 0xE0010000 and 0x0000E001 (no reference proves an address)
	.global d_0804fd18
d_0804fd18:
	.word 0xe0010000
@ (0x0804fd1c)
	.word 0x0000e001

@ Class record at 0x0804fd20 (parent 0x0804fcfc), object size 0x3C bytes
	.global d_0804fd20
d_0804fd20:
	.word d_0804fcfc		@ +0 parent: the base class record
	.word fn_080211cc
	.word fn_080219b6
	.word 0x00000000
	.word fn_080219e0
	.word 0x27d127d1
	.word 0x000003c0

@ Class record at 0x0804fd3c (parent 0x0804fcfc), object size 0x4C bytes
	.global d_0804fd3c
d_0804fd3c:
	.word d_0804fcfc		@ +0 parent: the base class record
	.word fn_08021ef8
	.word fn_08021f74
	.word 0x00000000
	.word fn_08021fb8
	.word 0x27d127d1
	.word 0x000004c0

@ Class record at 0x0804fd58 (parent 0x0804fcfc), object size 0x2C bytes, then
@ the FFT tables: 256 floats (cos and sin of 2*pi*k/128, k = 0..127) from
@ 0x0804fd74 and 208 halfwords (bit-reverse table, values 8..1008) from
@ 0x08050174 up to 0x08050314
	.global d_0804fd58
d_0804fd58:
	.word d_0804fcfc		@ +0 parent: the base class record
	.word fn_08022950
	.word 0x00000000
	.word 0x00000000
	.word fn_0802297c
@ the first 8 bytes of the blob finish the record (0x27D127D1, 0x000002C0),
@ the rest is the FFT tables (1440 bytes from 0x0804fd74)
	.incbin "assets/vendor/0804fd6c.bin", 0, 8
	.global d_0804fd74
d_0804fd74:				@ 256 floats (FFT descriptor +4)
	.incbin "assets/vendor/0804fd6c.bin", 8, 0x400
	.global d_08050174
d_08050174:				@ 208 halfwords (FFT descriptor +8)
	.incbin "assets/vendor/0804fd6c.bin", 0x408

@ ----------------------------------------------------------------------------
@ Sine table of sine_radians: 513 floats T[k] = sin(2*pi*k/512), k = 0..512.
@ T[0] = 0.0 is read separately (vldr s0,[r0]), T[1]..T[512] follow.
@ ----------------------------------------------------------------------------
	.global d_08050314
d_08050314:
	.word 0x00000000

@ T[1]..T[512] (2048 bytes)
	.incbin "assets/vendor/08050318.bin"

@ ----------------------------------------------------------------------------
@ Three halfword tables of 192 halfwords in total (0x08050b18..0x08050c97) read
@ by the functions at 0x08026858, 0x08026824 and 0x080267f4.
@ ----------------------------------------------------------------------------
@ Table 1: 19 halfwords (first 0xF206), indexed by r0 < 19
	.global d_08050b18
d_08050b18:
	.byte 0x06, 0xf2, 0xec, 0xe8, 0x36, 0x99, 0xd6, 0x61
	.byte 0x96, 0x3a, 0xbe, 0x24, 0x5e, 0x05, 0xfa, 0x05
	.byte 0xb1, 0x04, 0x6a, 0x4d, 0x09, 0x8e, 0xe7, 0xce
	.byte 0x47, 0xff, 0x00, 0xfe, 0xc0, 0xfc, 0xa4, 0xfa
	.byte 0xa9, 0x7a, 0xf1, 0x63, 0xf3, 0x9c

@ Table 2: 19 rows of 5 halfwords (190 bytes) at 0x08050b3e
	.global d_08050b3e
d_08050b3e:
	.incbin "assets/vendor/08050b3e.bin"

@ Table 3: 19 rows of 4 halfwords (152 bytes) at 0x08050bfc, then two halfwords
@ 0x0000 (156 bytes in all)
	.global d_08050bfc
d_08050bfc:
	.incbin "assets/vendor/08050bfc.bin"

@ Byte table of 112 entries indexed 0..111 (read by the function at 0x08012b10)
	.global d_08050c98
d_08050c98:
	.incbin "assets/vendor/08050c98.bin"

@ UTF-16LE string u"! hikjlmba" with terminating zero halfword (22 bytes)
	.global d_08050d08
d_08050d08:
	.short 0x0021, 0x0020, 0x0068, 0x0069, 0x006b, 0x006a
	.short 0x006c, 0x006d, 0x0062, 0x0061, 0x0000

@ 91 signed halfwords round(32767 * sin(k degrees)), k = 0..90, read by
@ sine_q15_degrees (08027ba8), followed by 22 bytes of coverage tables read by
@ the function at 0x080169ac as base 0x08050dea minus an offset
	.global d_08050d1e
d_08050d1e:
	.incbin "assets/vendor/08050d1e.bin"

@ Entry 0 of the 256-byte identity table (entries 1..255 follow)
	.global d_08050dea
d_08050dea:
	.byte 0x00

@ Identity table entries 1..255 (0x01, 0x02, ... 0xFF)
	.incbin "assets/vendor/08050deb.bin"

@ 34 bytes: 33 table bytes round(128 * sqrt(1 + (i/32)^2)), i = 0..32, read by
@ the function at 0x08016de0 with ldrb r0,[r2,r0], and a final zero byte
	.global d_08050eea
d_08050eea:
	.byte 0x80, 0x80, 0x80, 0x81, 0x81, 0x82, 0x82, 0x83
	.byte 0x84, 0x85, 0x86, 0x87, 0x89, 0x8a, 0x8c, 0x8d
	.byte 0x8f, 0x91, 0x93, 0x95, 0x97, 0x99, 0x9b, 0x9e
	.byte 0xa0, 0xa2, 0xa5, 0xa7, 0xaa, 0xad, 0xaf, 0xb2
	.byte 0xb5, 0x00

@ Two words 0x1FFF1FFF and 0xE001E001 (0x08050f10)
	.global d_08050f0c
d_08050f0c:
	.word 0x1fff1fff
	.word 0xe001e001

@ Class record at 0x08050f14 (parent 0x0804fcfc), object size 0x8C bytes
	.global d_08050f14
d_08050f14:
	.word d_0804fcfc		@ +0 parent: the base class record
	.word fn_0801d1b8
	.word fn_0801d210
	.word 0x00000000
	.word fn_0801d274
	.word 0x011e2064
	.word 0x000008c0

@ Class record at 0x08050f30 (parent 0x0804fcfc), object size 0x3C bytes
	.global d_08050f30
d_08050f30:
	.word d_0804fcfc		@ +0 parent: the base class record
	.word fn_08022f28
	.word fn_08022f44
	.word 0x00000000
	.word fn_08022f5c
	.word 0x00000000
	.word 0x000003c0

@ Class record at 0x08050f4c (parent 0x0804fcfc), object size 0x40 bytes
	.global d_08050f4c
d_08050f4c:
	.word d_0804fcfc		@ +0 parent: the base class record
	.word fn_0801c83c
	.word 0x00000000
	.word 0x00000000
	.word fn_0801ca5c
	.word 0x00000000
	.word 0x00000401

@ Class record at 0x08050f68 (parent 0x0804fcfc), object size 0x38 bytes, and
@ 4 zero bytes of padding to the 8-aligned double table at 0x08050f88
	.global d_08050f68
d_08050f68:
	.word d_0804fcfc		@ +0 parent: the base class record
	.word fn_0802744c
	.word fn_08027488
	.word 0x00000000
	.word fn_080274d4
	.word 0x27d127d1
	.word 0x00000385
	.word 0x00000000

@ Doubles 1.0 (0x3FF0000000000000) and 1.5 (0x3FF8000000000000): table indexed
@ by r4 in double_power (08010a50)
	.global d_08050f88
d_08050f88:
	.word 0x00000000, 0x3ff00000
	.word 0x00000000, 0x3ff80000

@ Doubles 0.0 and 0.5849624872207642 (0x3FE2B80340000000): table indexed by r4
@ in double_power
	.global d_08050f98
d_08050f98:
	.word 0x00000000, 0x00000000
	.word 0x40000000, 0x3fe2b803

@ Doubles 0.0 and 1.350039202129749e-08 (0x3E4CFDEB43CFD006): table indexed by r4
@ in double_power
	.global d_08050fa8
d_08050fa8:
	.word 0x00000000, 0x00000000
	.word 0x43cfd006, 0x3e4cfdeb

@ 6 doubles: polynomial coefficients 0.5999999999999946, 0.4285714285785502,
@ 0.33333332981837743, 0.272728123808534, 0.23066074577556175,
@ 0.20697501780033842 (double_power, evaluated through 0x08011910)
	.global d_08050fb8
d_08050fb8:
	.byte 0x03, 0x33, 0x33, 0x33, 0x33, 0x33, 0xe3, 0x3f
	.byte 0xff, 0xab, 0x6f, 0xdb, 0xb6, 0x6d, 0xdb, 0x3f
	.byte 0x4d, 0x26, 0x8f, 0x51, 0x55, 0x55, 0xd5, 0x3f
	.byte 0x01, 0x41, 0x1d, 0xa9, 0x60, 0x74, 0xd1, 0x3f
	.byte 0x65, 0xdb, 0xc9, 0x93, 0x4a, 0x86, 0xcd, 0x3f
	.byte 0xef, 0x4e, 0x45, 0x4a, 0x28, 0x7e, 0xca, 0x3f

@ 4 doubles: polynomial coefficients 0.16666666666666602,
@ -0.0027777777777015593, 6.613756321437934e-05, -1.6533902205465252e-06
@ (double_power)
	.global d_08050fe8
d_08050fe8:
	.byte 0x3e, 0x55, 0x55, 0x55, 0x55, 0x55, 0xc5, 0x3f
	.byte 0x93, 0xbd, 0xbe, 0x16, 0x6c, 0xc1, 0x66, 0xbf
	.byte 0x2c, 0xde, 0x25, 0xaf, 0x6a, 0x56, 0x11, 0x3f
	.byte 0xf1, 0x6b, 0xd2, 0xc5, 0x41, 0xbd, 0xbb, 0xbe

@ Double 4.1381367970572385e-08 (0x3E66376972BEA4D0): fifth coefficient
@ following the 4 doubles above
	.word 0x72bea4d0, 0x3e663769

@ 3 doubles atan(0.5), atan(1.0), atan(1.5) = 0.4636476090008061,
@ 0.7853981633974483, 0.982793723247329 (atan_f64, indexed by r4)
	.global d_08051010
d_08051010:
	.byte 0x4f, 0xbb, 0x61, 0x05, 0x67, 0xac, 0xdd, 0x3f
	.byte 0x18, 0x2d, 0x44, 0x54, 0xfb, 0x21, 0xe9, 0x3f
	.byte 0x9b, 0xf6, 0x81, 0xd2, 0x0b, 0x73, 0xef, 0x3f

@ Double pi/2 = 1.5707963267948966 (0x3FF921FB54442D18), fourth entry of the
@ atan table
	.word 0x54442d18, 0x3ff921fb

@ 4 doubles: low-part companions of the atan table (2.2698777452961687e-17,
@ 3.061616997868383e-17, 1.3903311031230998e-17, 6.123233995736766e-17)
	.global d_08051030
d_08051030:
	.byte 0xe2, 0x65, 0x2f, 0x22, 0x7f, 0x2b, 0x7a, 0x3c
	.byte 0x07, 0x5c, 0x14, 0x33, 0x26, 0xa6, 0x81, 0x3c
	.byte 0xbd, 0xcb, 0xf0, 0x7a, 0x88, 0x07, 0x70, 0x3c
	.byte 0x07, 0x5c, 0x14, 0x33, 0x26, 0xa6, 0x91, 0x3c

@ 5 doubles: coefficients -0.19999999999876483, -0.11111110405462356,
@ -0.0769187620504483, -0.058335701337905735, -0.036531572744216916 (atan_f64,
@ evaluated through 0x08011910 with a count of 5)
	.global d_08051050
d_08051050:
	.byte 0xc4, 0xeb, 0x98, 0x99, 0x99, 0x99, 0xc9, 0xbf
	.byte 0x71, 0x16, 0x23, 0xfe, 0xc6, 0x71, 0xbc, 0xbf
	.byte 0x6d, 0x9a, 0x74, 0xaf, 0xf2, 0xb0, 0xb3, 0xbf
	.byte 0x9a, 0xfd, 0xde, 0x52, 0x2d, 0xde, 0xad, 0xbf
	.byte 0x2f, 0x6c, 0x6a, 0x2c, 0x44, 0xb4, 0xa2, 0xbf

@ 6 doubles: coefficients 0.3333333333333293, 0.14285714272503466,
@ 0.09090887133436507, 0.06661073137387531, 0.049768779946159324,
@ 0.016285820115365782 (atan_f64, evaluated through 0x08011910 with a count of 6)
	.global d_08051078
d_08051078:
	.byte 0x0d, 0x55, 0x55, 0x55, 0x55, 0x55, 0xd5, 0x3f
	.byte 0xff, 0x83, 0x00, 0x92, 0x24, 0x49, 0xc2, 0x3f
	.byte 0x6e, 0x20, 0x4c, 0xc5, 0xcd, 0x45, 0xb7, 0x3f
	.byte 0x51, 0x3d, 0xd0, 0xa0, 0x66, 0x0d, 0xb1, 0x3f
	.byte 0xeb, 0x0d, 0x76, 0x24, 0x4b, 0x7b, 0xa9, 0x3f
	.byte 0x11, 0xda, 0x22, 0xe3, 0x3a, 0xad, 0x90, 0x3f

@ Double 0.0 (8 zero bytes)
	.global d_080510a8
d_080510a8:
	.word 0x00000000, 0x00000000

@ Table of 32-bit words read by the function at 0x08011ae8 (add r4,pc, then
@ ldr.w r4,[r4,r5,lsl #2]): 0x00000000, 0xA2F9836E, 0x4E441529, 0xFC2757D1,
@ 0xF534DDC0, 0xDB629599, 0x3C439041, 0xFE5163AB
	.global d_080510b0
d_080510b0:
	.byte 0x00, 0x00, 0x00, 0x00, 0x6e, 0x83, 0xf9, 0xa2
	.byte 0x29, 0x15, 0x44, 0x4e, 0xd1, 0x57, 0x27, 0xfc

@ Remaining four words of the table
	.global d_080510c0
d_080510c0:
	.word 0xf534ddc0
	.word 0xdb629599
	.word 0x3c439041
	.word 0xfe5163ab

@ Strings from here on are read through the pointer tables of the initial RAM image; the
@ English ones carry a label with their V1.1 address, which the typed image of our build
@ (rodata_04.s ram_image) names. The Chinese ones are reached only through row 0 of the
@ packed V1.1 image.
@ String "Version:V1.1" and NUL
	.global d_080510d0
d_080510d0:
	.asciz "Version:V1.1"

@ 3 zero bytes padding to the next 4-byte boundary
	.byte 0x00, 0x00, 0x00

@ String: UTF-8 bytes of the Chinese word for "version" (E7 89 88 E6 9C AC),
@ then ":V1.1" and NUL (0x080510e0, row 0 of the RAM table 0x20000194). Our build: freed
@ (12 bytes, 12 mod 4 = 0 bytes left).
.ifndef OWN
	.byte 0xe7, 0x89, 0x88, 0xe6, 0x9c, 0xac
	.asciz ":V1.1"
.endif

@ String "LED" and NUL
	.global d_080510ec
d_080510ec:
	.asciz "LED"

@ String "Model:LC1020E" and NUL
	.global d_080510f0
d_080510f0:
	.asciz "Model:LC1020E"

@ 2 zero bytes padding
	.byte 0x00, 0x00

@ String: UTF-8 bytes of the Chinese word for "model" (E5 9E 8B E5 8F B7),
@ then ":LC1020E" and NUL (0x08051100, row 0 of the RAM table 0x20000194), 1 zero byte
@ padding. Our build: freed (16 bytes, 0 bytes left).
.ifndef OWN
	.byte 0xe5, 0x9e, 0x8b, 0xe5, 0x8f, 0xb7
	.asciz ":LC1020E"
	.byte 0x00
.endif

@ String "OFF" and NUL
	.global d_08051110
d_08051110:
	.asciz "OFF"

@ Unit strings "mF", "nF", "pF", "uF" (each 2 characters plus 2 zero bytes)
@ and "SETTING" with NUL; read through RAM pointers
	.global d_08051114
d_08051114:
	.asciz "mF"
	.byte 0x00
	.global d_08051118
d_08051118:
	.asciz "nF"
	.byte 0x00
	.global d_0805111c
d_0805111c:
	.asciz "pF"
	.byte 0x00
	.global d_08051120
d_08051120:
	.asciz "uF"
	.byte 0x00
	.global d_08051124
d_08051124:
	.asciz "SETTING"

@ String "NG" and NUL, 1 zero byte padding
	.global d_0805112c
d_0805112c:
	.asciz "NG"
	.byte 0x00

@ String "mH" and NUL, 1 zero byte padding
	.global d_08051130
d_08051130:
	.asciz "mH"
	.byte 0x00

@ String "nH" and NUL, 1 zero byte padding
	.global d_08051134
d_08051134:
	.asciz "nH"
	.byte 0x00

@ String "uH" and NUL, 1 zero byte padding
	.global d_08051138
d_08051138:
	.asciz "uH"
	.byte 0x00
