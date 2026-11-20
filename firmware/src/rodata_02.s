@ rodata_02.s - read-only data part 2 of 4: image descriptors and image data, 0x080371f4..0x0804bbf7
@ Part of the FNIRSI LC1020E firmware rewrite: port of the application V1.1 (Thumb-2 assembly).
@ The part holds 84484 bytes. Most of it is image data: 12-byte image descriptors (header word,
@ size word, data pointer word) followed by pixel and palette bytes, which the application
@ passes to its image-draw routine (0x08021c14) by address. The large blocks come in with
@ .incbin from the vendor data blocks; the small gaps between them are typed out below.
	.syntax unified
	.arch armv7e-m
	.fpu fpv4-sp-d16
	.thumb

	.section .rodata.fixed.080371f4,"a",%progbits

@ 0x080371f4: 436 bytes, image descriptor (width 33, height 21, 4-bit palette image) + pixel bytes + 3 padding bytes
	.global d_080371f4
d_080371f4:
	.incbin "assets/vendor/080371f4.bin"

@ 0x080373a8: 452 bytes, image descriptor (width 33, height 21, 4-bit palette image) + pixel bytes + 1 padding byte
	.global d_080373a8
d_080373a8:
	.incbin "assets/vendor/080373a8.bin"

@ 0x0803756c: 436 bytes, image descriptor (width 29, height 25, 4-bit palette image) + pixel bytes + 3 padding bytes
	.global d_0803756c
d_0803756c:
	.incbin "assets/vendor/0803756c.bin"

@ 0x08037720: 436 bytes, image descriptor (width 33, height 21, 4-bit palette image) + pixel bytes + 3 padding bytes
	.global d_08037720
d_08037720:
	.incbin "assets/vendor/08037720.bin"

@ 0x080378d4: 436 bytes, image descriptor (width 33, height 21, 4-bit palette image) + pixel bytes + 3 padding bytes
	.global d_080378d4
d_080378d4:
	.incbin "assets/vendor/080378d4.bin"

@ 0x08037a88: 436 bytes, image descriptor (width 33, height 21, 4-bit palette image) + pixel bytes + 3 padding bytes
	.global d_08037a88
d_08037a88:
	.incbin "assets/vendor/08037a88.bin"

@ 0x08037c3c: 4716 bytes, image descriptor + image data
	.global d_08037c3c
d_08037c3c:
	.incbin "assets/vendor/08037c3c.bin"

@ 0x08038ea8: 4716 bytes, image descriptor + image data
	.global d_08038ea8
d_08038ea8:
	.incbin "assets/vendor/08038ea8.bin"

@ 0x0803a114: 4168 bytes, image descriptor + image data
	.global d_0803a114
d_0803a114:
	.incbin "assets/vendor/0803a114.bin"

@ 0x0803b15c: 4168 bytes, image descriptor + image data
	.global d_0803b15c
d_0803b15c:
	.incbin "assets/vendor/0803b15c.bin"

@ 0x0803c1a4: 608 bytes, image descriptor + image data
	.global d_0803c1a4
d_0803c1a4:
	.incbin "assets/vendor/0803c1a4.bin"

@ 0x0803c404: 652 bytes, image descriptor + image data
	.global d_0803c404
d_0803c404:
	.incbin "assets/vendor/0803c404.bin"

@ 0x0803c690: 652 bytes, image descriptor + image data
	.global d_0803c690
d_0803c690:
	.incbin "assets/vendor/0803c690.bin"

@ 0x0803c91c: 652 bytes, image descriptor + image data
	.global d_0803c91c
d_0803c91c:
	.incbin "assets/vendor/0803c91c.bin"

@ 0x0803cba8: 540 bytes, image descriptor + image data
	.global d_0803cba8
d_0803cba8:
	.incbin "assets/vendor/0803cba8.bin"

@ 0x0803cdc4: 560 bytes, image descriptor + image data
	.global d_0803cdc4
d_0803cdc4:
	.incbin "assets/vendor/0803cdc4.bin"

@ 0x0803cff4: 560 bytes, image descriptor + image data
	.global d_0803cff4
d_0803cff4:
	.incbin "assets/vendor/0803cff4.bin"

@ 0x0803d224: 216 bytes, image descriptor + image data
	.global d_0803d224
d_0803d224:
	.incbin "assets/vendor/0803d224.bin"

@ 0x0803d2fc: 216 bytes, image descriptor + image data
	.global d_0803d2fc
d_0803d2fc:
	.incbin "assets/vendor/0803d2fc.bin"

@ 0x0803d3d4: 216 bytes, image descriptor + image data
	.global d_0803d3d4
d_0803d3d4:
	.incbin "assets/vendor/0803d3d4.bin"

@ 0x0803d4ac: 216 bytes, image descriptor + image data
	.global d_0803d4ac
d_0803d4ac:
	.incbin "assets/vendor/0803d4ac.bin"

@ 0x0803d584: 216 bytes, image descriptor + image data
	.global d_0803d584
d_0803d584:
	.incbin "assets/vendor/0803d584.bin"

@ 0x0803d65c: 216 bytes, image descriptor + image data
	.global d_0803d65c
d_0803d65c:
	.incbin "assets/vendor/0803d65c.bin"

@ 0x0803d734: 216 bytes, image descriptor + image data
	.global d_0803d734
d_0803d734:
	.incbin "assets/vendor/0803d734.bin"

@ 0x0803d80c: 216 bytes, image descriptor + image data
	.global d_0803d80c
d_0803d80c:
	.incbin "assets/vendor/0803d80c.bin"

@ 0x0803d8e4: 352 bytes, image descriptor + image data
	.global d_0803d8e4
d_0803d8e4:
	.incbin "assets/vendor/0803d8e4.bin"

@ 0x0803da44: 352 bytes, image descriptor + image data
	.global d_0803da44
d_0803da44:
	.incbin "assets/vendor/0803da44.bin"

@ 0x0803dba4: 352 bytes, image descriptor + image data
	.global d_0803dba4
d_0803dba4:
	.incbin "assets/vendor/0803dba4.bin"

@ 0x0803dd04: 352 bytes, image descriptor + image data
	.global d_0803dd04
d_0803dd04:
	.incbin "assets/vendor/0803dd04.bin"

@ 0x0803de64: 352 bytes, image descriptor + image data
	.global d_0803de64
d_0803de64:
	.incbin "assets/vendor/0803de64.bin"

@ 0x0803dfc4: 652 bytes, image descriptor + image data
	.global d_0803dfc4
d_0803dfc4:
	.incbin "assets/vendor/0803dfc4.bin"

@ 0x0803e250: 7600 bytes, image descriptor + image data (up to 0x08040000)
	.global d_0803e250
d_0803e250:
	.incbin "assets/vendor/0803e250.bin"

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

@ 0x0804095c: first 2 bytes of the 12-byte image descriptor at 0x0804095c (header 0x07C50009)
	.global d_0804095c
d_0804095c:
	.byte 0x09, 0x00

@ 0x0804095e: 202 bytes, rest of that descriptor + image data
	.incbin "assets/vendor/0804095e.bin"

@ 0x08040a28: first 3 bytes of the 12-byte image descriptor at 0x08040a28 (header 0x02004009)
	.global d_08040a28
d_08040a28:
	.byte 0x09, 0x40, 0x00

@ 0x08040a2b: 625 bytes, rest of that descriptor + image data
	.incbin "assets/vendor/08040a2b.bin"

@ 0x08040c9c: 628 bytes, image descriptor + image data
	.global d_08040c9c
d_08040c9c:
	.incbin "assets/vendor/08040c9c.bin"

@ 0x08040f10: 628 bytes, image descriptor + image data
	.global d_08040f10
d_08040f10:
	.incbin "assets/vendor/08040f10.bin"

@ 0x08041184: 12236 bytes, image descriptor + image data
	.global d_08041184
d_08041184:
	.incbin "assets/vendor/08041184.bin"

@ 0x08044150: first 2 bytes of the 12-byte image descriptor at 0x08044150 (header 0x0465000A)
	.global d_08044150
d_08044150:
	.byte 0x0a, 0x00

@ 0x08044152: 402 bytes, rest of that descriptor + image data
	.incbin "assets/vendor/08044152.bin"

@ 0x080442e4: 348 bytes, image descriptor + image data
	.global d_080442e4
d_080442e4:
	.incbin "assets/vendor/080442e4.bin"

@ 0x08044440: 348 bytes, image descriptor + image data
	.global d_08044440
d_08044440:
	.incbin "assets/vendor/08044440.bin"

@ 0x0804459c: 332 bytes, image descriptor + image data
	.global d_0804459c
d_0804459c:
	.incbin "assets/vendor/0804459c.bin"

@ 0x080446e8: first 3 bytes of the 12-byte image descriptor at 0x080446e8 (header 0x02007C09)
	.global d_080446e8
d_080446e8:
	.byte 0x09, 0x7c, 0x00

@ 0x080446eb: 74 bytes, rest of that descriptor + image data
	.incbin "assets/vendor/080446eb.bin"

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
	.incbin "assets/vendor/08044844.bin"

@ 0x08044990: first 3 bytes of the 12-byte image descriptor at 0x08044990 (header 0x02007C09)
	.global d_08044990
d_08044990:
	.byte 0x09, 0x7c, 0x00

@ 0x08044993: 9 bytes, rest of that descriptor (size 320, data pointer 0x08044850)
	.byte 0x02, 0x40, 0x01, 0x00, 0x00, 0x50, 0x48, 0x04, 0x08

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

@ 0x08048f3c: 613 bytes, image data
	.global d_08048f3c
d_08048f3c:
	.incbin "assets/vendor/08048f3c.bin"

@ 0x080491a1: 67 bytes, image data
	.incbin "assets/vendor/080491a1.bin"

@ 0x080491e4: 5080 bytes, image data
	.incbin "assets/vendor/080491e4.bin"

@ 0x0804a5bc: 5692 bytes, image descriptor + image data (last byte of the part is 0x0804bbf7)
	.global d_0804a5bc
d_0804a5bc:
	.incbin "assets/vendor/0804a5bc.bin"
