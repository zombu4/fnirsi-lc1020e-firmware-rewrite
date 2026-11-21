@ rodata_02.s - read-only data part 2 of 4: image descriptors and image data, 0x080371f4..0x0804bbf7
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
@ The part holds 84484 bytes. Most of it is image data: 12-byte image descriptors (header word,
@ size word, data pointer word) followed by pixel and palette bytes, which the application
@ passes to its image-draw routine (0x08021c14) by address. The large blocks come in with
@ .incbin from the vendor data blocks; the small gaps between them are typed out below.
@ An image is its data (palette and pixels), 0..3 padding bytes and its descriptor: header
@ word (bits 0..4 colour format cf, bits 10..20 width, bits 21..31 height), size word, data
@ pointer word. Each vendor block begins with a descriptor and goes on with the data of the
@ next image, so the descriptor words are typed (the data pointer as the label of the data)
@ and the block follows from offset 12. The addresses in labels and comments are those of
@ V1.1; in our build (make own) the part sits lower (link_own.ld).
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.section .rodata.fixed.080371f4,"a",%progbits

@ 0x080371f4: 436 bytes, image descriptor (width 33, height 21, 4-bit palette image) + pixel bytes + 3 padding bytes
	.global d_080371f4
d_080371f4:
	.word 0x02a08409		@ cf 9, 33 x 21
	.word 421			@ size
	.word d_0803704c		@ data
	.global d_08037200
d_08037200:
	.incbin "assets/vendor/080371f4.bin", 12

@ 0x080373a8: 452 bytes, image descriptor (width 33, height 21, 4-bit palette image) + pixel bytes + 1 padding byte
	.global d_080373a8
d_080373a8:
	.word 0x02a08409		@ cf 9, 33 x 21
	.word 421			@ size
	.word d_08037200		@ data
	.global d_080373b4
d_080373b4:
	.incbin "assets/vendor/080373a8.bin", 12

@ 0x0803756c: 436 bytes, image descriptor (width 29, height 25, 4-bit palette image) + pixel bytes + 3 padding bytes
	.global d_0803756c
d_0803756c:
	.word 0x03207409		@ cf 9, 29 x 25
	.word 439			@ size
	.word d_080373b4		@ data
	.global d_08037578
d_08037578:
	.incbin "assets/vendor/0803756c.bin", 12

@ 0x08037720: 436 bytes, image descriptor (width 33, height 21, 4-bit palette image) + pixel bytes + 3 padding bytes
	.global d_08037720
d_08037720:
	.word 0x02a08409		@ cf 9, 33 x 21
	.word 421			@ size
	.word d_08037578		@ data
	.global d_0803772c
d_0803772c:
	.incbin "assets/vendor/08037720.bin", 12

@ 0x080378d4: 436 bytes, image descriptor (width 33, height 21, 4-bit palette image) + pixel bytes + 3 padding bytes
	.global d_080378d4
d_080378d4:
	.word 0x02a08409		@ cf 9, 33 x 21
	.word 421			@ size
	.word d_0803772c		@ data
	.global d_080378e0
d_080378e0:
	.incbin "assets/vendor/080378d4.bin", 12

@ 0x08037a88: 436 bytes, image descriptor (width 33, height 21, 4-bit palette image) + pixel bytes + 3 padding bytes
	.global d_08037a88
d_08037a88:
	.word 0x02a08409		@ cf 9, 33 x 21
	.word 421			@ size
	.word d_080378e0		@ data
	.global d_08037a94
d_08037a94:
	.incbin "assets/vendor/08037a88.bin", 12

@ 0x08037c3c: 4716 bytes, image descriptor + image data
	.global d_08037c3c
d_08037c3c:
	.word 0x02a08409		@ cf 9, 33 x 21
	.word 421			@ size
	.word d_08037a94		@ data
	.global d_08037c48
d_08037c48:
	.incbin "assets/vendor/08037c3c.bin", 12

@ 0x08038ea8: 4716 bytes, image descriptor + image data
	.global d_08038ea8
d_08038ea8:
	.word 0x05c1400a		@ cf 10, 80 x 46
	.word 4704			@ size
	.word d_08037c48		@ data
	.global d_08038eb4
d_08038eb4:
	.incbin "assets/vendor/08038ea8.bin", 12

@ 0x0803a114: 4168 bytes, image descriptor + image data
	.global d_0803a114
d_0803a114:
	.word 0x05c1400a		@ cf 10, 80 x 46
	.word 4704			@ size
	.word d_08038eb4		@ data
	.global d_0803a120
d_0803a120:
	.incbin "assets/vendor/0803a114.bin", 12

@ 0x0803b15c: 4168 bytes, image descriptor + image data
	.global d_0803b15c
d_0803b15c:
	.word 0x0740d80a		@ cf 10, 54 x 58
	.word 4156			@ size
	.word d_0803a120		@ data
	.global d_0803b168
d_0803b168:
	.incbin "assets/vendor/0803b15c.bin", 12

@ 0x0803c1a4: 608 bytes, image descriptor + image data
	.global d_0803c1a4
d_0803c1a4:
	.word 0x0740d80a		@ cf 10, 54 x 58
	.word 4156			@ size
	.word d_0803b168		@ data
	.global d_0803c1b0
d_0803c1b0:
	.incbin "assets/vendor/0803c1a4.bin", 12

@ 0x0803c404: 652 bytes, image descriptor + image data
	.global d_0803c404
d_0803c404:
	.word 0x02e0b809		@ cf 9, 46 x 23
	.word 593			@ size
	.word d_0803c1b0		@ data
.ifdef OWN
@ Our build: the descriptor 0x0803c404..0x0803c40f kept; from 0x0803c410 up to 0x0803cbb3 the
@ Chinese speed icons of language 0 are freed (1956 bytes; 1956 mod 4 = 0 bytes left): the
@ data of d_0803c690 (0x0803c410..0x0803c68f) and the images d_0803c690, d_0803c91c and the
@ descriptor d_0803cba8 below (the pool words 0x08009954.. / 0x0800ce00.. name the English
@ icons d_08040f10 / d_08041184 / d_08040c9c instead).
.else
	.global d_0803c410
d_0803c410:
	.incbin "assets/vendor/0803c404.bin", 12

@ 0x0803c690: 652 bytes, image descriptor + image data
	.global d_0803c690
d_0803c690:
	.word 0x0300c009		@ cf 9, 48 x 24
	.word 640			@ size
	.word d_0803c410		@ data
	.global d_0803c69c
d_0803c69c:
	.incbin "assets/vendor/0803c690.bin", 12

@ 0x0803c91c: 652 bytes, image descriptor + image data
	.global d_0803c91c
d_0803c91c:
	.word 0x0300c009		@ cf 9, 48 x 24
	.word 640			@ size
	.word d_0803c69c		@ data
	.global d_0803c928
d_0803c928:
	.incbin "assets/vendor/0803c91c.bin", 12

@ 0x0803cba8: 540 bytes, image descriptor + image data
	.global d_0803cba8
d_0803cba8:
	.word 0x0300c009		@ cf 9, 48 x 24
	.word 640			@ size
	.word d_0803c928		@ data
.endif
@ 0x0803cbb4: the data of the picture d_0803cdc4 (rest of the block 0803cba8.bin).
	.global d_0803cbb4
d_0803cbb4:
	.incbin "assets/vendor/0803cba8.bin", 12

@ 0x0803cdc4: 560 bytes, image descriptor + image data
	.global d_0803cdc4
d_0803cdc4:
	.word 0x02c0a809		@ cf 9, 42 x 22
	.word 526			@ size
	.word d_0803cbb4		@ data
	.global d_0803cdd0
d_0803cdd0:
	.incbin "assets/vendor/0803cdc4.bin", 12

@ 0x0803cff4: 560 bytes, image descriptor + image data
	.global d_0803cff4
d_0803cff4:
	.word 0x02c0ac09		@ cf 9, 43 x 22
	.word 548			@ size
	.word d_0803cdd0		@ data
	.global d_0803d000
d_0803d000:
	.incbin "assets/vendor/0803cff4.bin", 12

@ 0x0803d224: 216 bytes, image descriptor + image data
	.global d_0803d224
d_0803d224:
	.word 0x02c0ac09		@ cf 9, 43 x 22
	.word 548			@ size
	.word d_0803d000		@ data
	.global d_0803d230
d_0803d230:
	.incbin "assets/vendor/0803d224.bin", 12

@ 0x0803d2fc: 216 bytes, image descriptor + image data
	.global d_0803d2fc
d_0803d2fc:
	.word 0x02803809		@ cf 9, 14 x 20
	.word 204			@ size
	.word d_0803d230		@ data
	.global d_0803d308
d_0803d308:
	.incbin "assets/vendor/0803d2fc.bin", 12

@ 0x0803d3d4: 216 bytes, image descriptor + image data
	.global d_0803d3d4
d_0803d3d4:
	.word 0x02803809		@ cf 9, 14 x 20
	.word 204			@ size
	.word d_0803d308		@ data
	.global d_0803d3e0
d_0803d3e0:
	.incbin "assets/vendor/0803d3d4.bin", 12

@ 0x0803d4ac: 216 bytes, image descriptor + image data
	.global d_0803d4ac
d_0803d4ac:
	.word 0x02803809		@ cf 9, 14 x 20
	.word 204			@ size
	.word d_0803d3e0		@ data
	.global d_0803d4b8
d_0803d4b8:
	.incbin "assets/vendor/0803d4ac.bin", 12

@ 0x0803d584: 216 bytes, image descriptor + image data
	.global d_0803d584
d_0803d584:
	.word 0x02803809		@ cf 9, 14 x 20
	.word 204			@ size
	.word d_0803d4b8		@ data
	.global d_0803d590
d_0803d590:
	.incbin "assets/vendor/0803d584.bin", 12

@ 0x0803d65c: 216 bytes, image descriptor + image data
	.global d_0803d65c
d_0803d65c:
	.word 0x02803809		@ cf 9, 14 x 20
	.word 204			@ size
	.word d_0803d590		@ data
	.global d_0803d668
d_0803d668:
	.incbin "assets/vendor/0803d65c.bin", 12

@ 0x0803d734: 216 bytes, image descriptor + image data
	.global d_0803d734
d_0803d734:
	.word 0x02803809		@ cf 9, 14 x 20
	.word 204			@ size
	.word d_0803d668		@ data
	.global d_0803d740
d_0803d740:
	.incbin "assets/vendor/0803d734.bin", 12

@ 0x0803d80c: 216 bytes, image descriptor + image data
	.global d_0803d80c
d_0803d80c:
	.word 0x02803809		@ cf 9, 14 x 20
	.word 204			@ size
	.word d_0803d740		@ data
	.global d_0803d818
d_0803d818:
	.incbin "assets/vendor/0803d80c.bin", 12

@ 0x0803d8e4: 352 bytes, image descriptor + image data
	.global d_0803d8e4
d_0803d8e4:
	.word 0x02803809		@ cf 9, 14 x 20
	.word 204			@ size
	.word d_0803d818		@ data
	.global d_0803d8f0
d_0803d8f0:
	.incbin "assets/vendor/0803d8e4.bin", 12

@ 0x0803da44: 352 bytes, image descriptor + image data
	.global d_0803da44
d_0803da44:
	.word 0x02e05c09		@ cf 9, 23 x 23
	.word 340			@ size
	.word d_0803d8f0		@ data
	.global d_0803da50
d_0803da50:
	.incbin "assets/vendor/0803da44.bin", 12

@ 0x0803dba4: 352 bytes, image descriptor + image data
	.global d_0803dba4
d_0803dba4:
	.word 0x02e05c09		@ cf 9, 23 x 23
	.word 340			@ size
	.word d_0803da50		@ data
	.global d_0803dbb0
d_0803dbb0:
	.incbin "assets/vendor/0803dba4.bin", 12

@ 0x0803dd04: 352 bytes, image descriptor + image data
	.global d_0803dd04
d_0803dd04:
	.word 0x02e05c09		@ cf 9, 23 x 23
	.word 340			@ size
	.word d_0803dbb0		@ data
	.global d_0803dd10
d_0803dd10:
	.incbin "assets/vendor/0803dd04.bin", 12

@ 0x0803de64: 352 bytes, image descriptor + image data
	.global d_0803de64
d_0803de64:
	.word 0x02e05c09		@ cf 9, 23 x 23
	.word 340			@ size
	.word d_0803dd10		@ data
	.global d_0803de70
d_0803de70:
	.incbin "assets/vendor/0803de64.bin", 12

@ 0x0803dfc4: 652 bytes, image descriptor + image data
	.global d_0803dfc4
d_0803dfc4:
	.word 0x02e05c09		@ cf 9, 23 x 23
	.word 340			@ size
	.word d_0803de70		@ data
	.global d_0803dfd0
d_0803dfd0:
	.incbin "assets/vendor/0803dfc4.bin", 12

@ 0x0803e250: 7600 bytes, image descriptor + image data (up to 0x08040000)
	.global d_0803e250
d_0803e250:
	.word 0x0300bc09		@ cf 9, 47 x 24
	.word 640			@ size
	.word d_0803dfd0		@ data
	.global d_0803e25c
d_0803e25c:				@ data of the image 0x0804095c (9984 bytes, to 0x0804095b)
	.incbin "assets/vendor/0803e250.bin", 12

@ 0x08040000: 1757 bytes, image data (continuation of the block above)
	.global d_08040000
d_08040000:
	.incbin "assets/vendor/08040000.bin"

@ 0x080406dd: 31 bytes, image data: 26 bytes 0x44, then 0x40 and 4 zero bytes
	.byte 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44
	.byte 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44
	.byte 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44
	.byte 0x44, 0x44, 0x40, 0x00, 0x00, 0x00, 0x00

@ 0x080406fc: 48 bytes, all zero (image data)
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
	.word 0x00000000, 0x00000000, 0x00000000, 0x00000000

@ 0x0804072c: 28 bytes, image data: 26 bytes 0x44, then 0x40 and 0x00
	.byte 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44
	.byte 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44
	.byte 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44
	.byte 0x44, 0x44, 0x40, 0x00

@ 0x08040748: 532 bytes, image data (end of the image data block that ends at 0x0804095c)
	.incbin "assets/vendor/08040748.bin"

@ 0x0804095c: 12-byte image descriptor (cf 9, 320 x 62), typed; the block 0804095e.bin holds
@ its last 10 bytes and then the data of the image 0x08040a28.
	.global d_0804095c
d_0804095c:
	.word 0x07c50009		@ cf 9, 320 x 62
	.word 9984			@ size
	.word d_0803e25c		@ data
	.global d_08040968
d_08040968:
	.incbin "assets/vendor/0804095e.bin", 10

@ 0x08040a28: 12-byte image descriptor (cf 9, 16 x 16), typed; the block 08040a2b.bin holds
@ its last 9 bytes and then the data of the image 0x08040c9c.
	.global d_08040a28
d_08040a28:
	.word 0x02004009		@ cf 9, 16 x 16
	.word 192			@ size
	.word d_08040968		@ data
	.global d_08040a34
d_08040a34:
	.incbin "assets/vendor/08040a2b.bin", 9

@ 0x08040c9c: 628 bytes, image descriptor + image data
	.global d_08040c9c
d_08040c9c:
	.word 0x02e0c009		@ cf 9, 48 x 23
	.word 616			@ size
	.word d_08040a34		@ data
	.global d_08040ca8
d_08040ca8:
	.incbin "assets/vendor/08040c9c.bin", 12

@ 0x08040f10: 628 bytes, image descriptor + image data
	.global d_08040f10
d_08040f10:
	.word 0x02e0c009		@ cf 9, 48 x 23
	.word 616			@ size
	.word d_08040ca8		@ data
	.global d_08040f1c
d_08040f1c:
	.incbin "assets/vendor/08040f10.bin", 12

@ 0x08041184: 12236 bytes, image descriptor + image data
	.global d_08041184
d_08041184:
	.word 0x02e0c009		@ cf 9, 48 x 23
	.word 616			@ size
	.word d_08040f1c		@ data
	.global d_08041190
d_08041190:
	.incbin "assets/vendor/08041184.bin", 12

@ 0x08044150: 12-byte image descriptor (cf 10, 320 x 35), typed; the block 08044152.bin holds
@ its last 10 bytes and then the data of the image 0x080442e4.
	.global d_08044150
d_08044150:
	.word 0x0465000a		@ cf 10, 320 x 35
	.word 12224			@ size
	.word d_08041190		@ data
	.global d_0804415c
d_0804415c:
	.incbin "assets/vendor/08044152.bin", 10

@ 0x080442e4: 348 bytes, image descriptor + image data
	.global d_080442e4
d_080442e4:
	.word 0x03206409		@ cf 9, 25 x 25
	.word 389			@ size
	.word d_0804415c		@ data
	.global d_080442f0
d_080442f0:
	.incbin "assets/vendor/080442e4.bin", 12

@ 0x08044440: 348 bytes, image descriptor + image data
	.global d_08044440
d_08044440:
	.word 0x02207c09		@ cf 9, 31 x 17
	.word 336			@ size
	.word d_080442f0		@ data
	.global d_0804444c
d_0804444c:
	.incbin "assets/vendor/08044440.bin", 12

@ 0x0804459c: 332 bytes, image descriptor + image data
	.global d_0804459c
d_0804459c:
	.word 0x02207c09		@ cf 9, 31 x 17
	.word 336			@ size
	.word d_0804444c		@ data
	.global d_080445a8
d_080445a8:
	.incbin "assets/vendor/0804459c.bin", 12

@ 0x080446e8: 12-byte image descriptor (cf 9, 31 x 16), typed; the block 080446eb.bin holds
@ its last 9 bytes and then the first data bytes of the image 0x08044844.
	.global d_080446e8
d_080446e8:
	.word 0x02007c09		@ cf 9, 31 x 16
	.word 320			@ size
	.word d_080445a8		@ data
	.global d_080446f4
d_080446f4:
	.incbin "assets/vendor/080446eb.bin", 9

@ 0x08044735: 15 bytes, image data: twelve 0x66, 0x62, two zero bytes
	.byte 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66
	.byte 0x66, 0x66, 0x66, 0x66, 0x62, 0x00, 0x00

@ 0x08044744: 16 bytes, image data
	.byte 0x53, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33
	.byte 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x50, 0x00

@ 0x08044754: 16 bytes, image data
	.byte 0x53, 0x36, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66
	.byte 0x66, 0x66, 0x66, 0x66, 0x66, 0x33, 0x70, 0x00

@ 0x08044764: 224 bytes, image data (end of the image data block that ends at 0x08044844)
	.incbin "assets/vendor/08044764.bin"

@ 0x08044844: 332 bytes, image descriptor + image data
	.global d_08044844
d_08044844:
	.word 0x02207c09		@ cf 9, 31 x 17
	.word 336			@ size
	.word d_080446f4		@ data
	.global d_08044850
d_08044850:
	.incbin "assets/vendor/08044844.bin", 12

@ 0x08044990: 12-byte image descriptor (cf 9, 31 x 16; size 320, data 0x08044850)
	.global d_08044990
d_08044990:
	.word 0x02007c09		@ cf 9, 31 x 16
	.word 320			@ size
	.word d_08044850		@ data

@ 0x0804499c: 8960 bytes, image data
	.global d_0804499c
d_0804499c:
	.incbin "assets/vendor/0804499c.bin"

@ 0x08046c9c: 8640 bytes, image data
	.global d_08046c9c
d_08046c9c:
	.incbin "assets/vendor/08046c9c.bin"

@ 0x08048e5c: 128 bytes, image data
	.global d_08048e5c
d_08048e5c:
	.incbin "assets/vendor/08048e5c.bin"

@ 0x08048edc: 96 bytes, image data
	.global d_08048edc
d_08048edc:
	.incbin "assets/vendor/08048edc.bin"

@ 0x08048f3c: 613 bytes: an 80-byte RGB565 array (5 x 8, fn_0800ce54 -> fn_08009ba0), then
@ the first data bytes of the image 0x0804a5bc (from 0x08048f8c)
	.global d_08048f3c
d_08048f3c:
	.incbin "assets/vendor/08048f3c.bin", 0, 0x50
	.global d_08048f8c
d_08048f8c:
	.incbin "assets/vendor/08048f3c.bin", 0x50

@ 0x080491a1: 67 bytes, image data
	.incbin "assets/vendor/080491a1.bin"

@ 0x080491e4: 5080 bytes, image data
	.incbin "assets/vendor/080491e4.bin"

@ 0x0804a5bc: 5692 bytes, image descriptor + image data (last byte of the part is 0x0804bbf7)
	.global d_0804a5bc
d_0804a5bc:
	.word 0x0484e009		@ cf 9, 312 x 36
	.word 5680			@ size
	.word d_08048f8c		@ data
	.global d_0804a5c8
d_0804a5c8:
	.incbin "assets/vendor/0804a5bc.bin", 12
