# Makefile - build the FNIRSI LC1020E stock bootloader from its assembly source and prove it byte for byte.
#
#   make vendor-data DUMP=<bootloader dump>
#                 copy the three vendor data blocks the source includes with .incbin (font table,
#                 a 130-byte table, the packed initial RAM image) out of your own meter's bootloader
#                 dump (0x6000 bytes read from 0x08000000) into assets/vendor/; they are not part of
#                 this repository; each block is checked against its SHA-256 below
#   make          build/BOOT.bin: assemble src/*.s, link with link.ld, 0x08000000..0x0800467B
#                 (0x467C = 18044 bytes)
#   make check    build/BOOT.bin, then its size and SHA-256 compared with bytes 0x0000..0x467B of the
#                 stock bootloader (the byte proof of the port)
#   make slot     the slot bootloader: build/slot/BOOT_F.bin, BOOT_A.bin, BOOT_B.bin, each the
#                 0x200-byte slot header (../tools/slot_header.py, version SLOT_VERSION, default 2)
#                 and the image assembled with
#                 --defsym SLOT=1 (src/slot_10.s and every .ifdef SLOT change) and the slot index,
#                 linked for slot + 0x200 (link_slot.ld); then ../tools/slot_check.py: functions at
#                 their stock address modulo 4, no word in 0x08000000..0x08005FFF, each image at
#                 most 0x5E00 bytes
#   make slot-check RWDATA=<file>
#                 make slot, plus the typed initial RAM image compared with the stock one
#                 (0x220 bytes unpacked from a dump, not part of this repository) with its 39
#                 pointers moved to the slot addresses and the drive's sector count changed
#   make clean    remove build/
#
# Needs the GNU Arm Embedded binutils (arm-none-eabi-as, -ld, -objcopy, -nm), shasum and python3.
# The application area from 0x08006000 is not part of this image and is never linked
# (link.ld ends FLASH at 0x08006000).

CROSS   ?= arm-none-eabi-
AS      := $(CROSS)as
LD      := $(CROSS)ld
OBJCOPY := $(CROSS)objcopy
ASFLAGS := -march=armv7e-m -mthumb -I .
SRC     := $(wildcard src/*.s)
OBJ     := $(patsubst src/%.s,build/%.o,$(SRC))

# vendor data blocks: <dump offset> <length> <SHA-256>
BLOB_08003f65 := 0x3F65 1279 8b8dace0e4a127fd61f3b2b42f6a09affaed76bf5e330c5709ca8f80b58f1093
BLOB_080044f2 := 0x44F2 130  928f887276153a4a05bf6eedcec2c60537d9807e5a942178802c6c069daed1e4
BLOB_08004594 := 0x4594 231  159e3a7670bf685d770ab5426936c11da4d93f65bece362e37bf691f6787339c
BLOBS   := assets/vendor/08003f65.bin assets/vendor/080044f2.bin assets/vendor/08004594.bin

# SHA-256 of bytes 0x0000..0x467B (0x467C bytes) of the stock bootloader flash 0x08000000..
BOOT_SIZE   := 18044
BOOT_SHA256 := b2780c2b0d07363be0730684ee96e6c2bc6019e38abc3d38b0ad7759c8fa93f8

all: build/BOOT.bin

$(BLOBS):
	@echo "missing $@: run make vendor-data DUMP=<bootloader dump of your meter> first"; exit 1

vendor-data:
	@test -n "$(DUMP)" || { echo "usage: make vendor-data DUMP=<bootloader dump>"; exit 1; }
	@test `wc -c < "$(DUMP)"` -eq 24576 || { echo "$(DUMP) is not a 0x6000-byte bootloader dump"; exit 1; }
	mkdir -p assets/vendor
	@for b in 08003f65 080044f2 08004594; do \
	  case $$b in \
	    08003f65) set -- $(BLOB_08003f65);; \
	    080044f2) set -- $(BLOB_080044f2);; \
	    08004594) set -- $(BLOB_08004594);; \
	  esac; \
	  dd if="$(DUMP)" of=assets/vendor/$$b.bin bs=1 skip=$$(($$1)) count=$$2 2>/dev/null; \
	  echo "$$3  assets/vendor/$$b.bin" | shasum -a 256 -c - || { rm -f assets/vendor/$$b.bin; exit 1; }; \
	done

build/%.o: src/%.s $(BLOBS) | build
	$(AS) $(ASFLAGS) -o $@ $<

build/boot.elf: $(OBJ) link.ld link_units.ld
	@test -n "$(OBJ)" || { echo "src/ holds no .s file"; exit 1; }
	$(LD) --no-warn-rwx-segments -T link.ld -Map build/boot.map -o $@ $(OBJ)

build/BOOT.bin: build/boot.elf
	$(OBJCOPY) -O binary $< $@

build:
	mkdir -p $@

check: build/BOOT.bin
	@test `wc -c < build/BOOT.bin` -eq $(BOOT_SIZE) || { echo "BOOT.bin is not $(BOOT_SIZE) bytes"; exit 1; }
	@echo "$(BOOT_SHA256)  build/BOOT.bin" | shasum -a 256 -c -

# ---- slot build ----
# slot index (fixed per image) and slot base; the header goes at the base, the image at base + 0x200
SLOT_INDEX_F := 0
SLOT_BASE_F  := 0x08069000
SLOT_INDEX_A := 1
SLOT_BASE_A  := 0x0806F000
SLOT_INDEX_B := 2
SLOT_BASE_B  := 0x08075000
# feature version in the slot header word +12: 2 = update request, hand-over and result words,
# watchdog of a trial start (src/slot_10.s); the slot images built before it carry 1
SLOT_VERSION ?= 2
SLOT_BLOBS   := assets/vendor/08003f65.bin assets/vendor/080044f2.bin
SLOT_BOOTS   := build/slot/BOOT_F.bin build/slot/BOOT_A.bin build/slot/BOOT_B.bin
SLOT_SPECS    = $(foreach s,F A B,$(SLOT_BASE_$(s)):build/slot/$(s)/boot.elf:build/slot/BOOT_$(s).bin)

define SLOT_RULES
build/slot/$(1)/%.o: src/%.s src/slot.inc $$(SLOT_BLOBS) | build/slot/$(1)
	$$(AS) $$(ASFLAGS) --defsym SLOT=1 --defsym SLOT_INDEX=$$(SLOT_INDEX_$(1)) -o $$@ $$<

build/slot/$(1)/boot.elf: $$(patsubst src/%.s,build/slot/$(1)/%.o,$$(SRC)) link_slot.ld link_units.ld
	$$(LD) --no-warn-rwx-segments -T link_slot.ld --defsym SLOT_BASE=$$(SLOT_BASE_$(1)) \
		-Map build/slot/$(1)/boot.map -o $$@ $$(patsubst src/%.s,build/slot/$(1)/%.o,$$(SRC))

build/slot/$(1)/image.bin: build/slot/$(1)/boot.elf
	$$(OBJCOPY) -O binary $$< $$@

build/slot/BOOT_$(1).bin: build/slot/$(1)/image.bin ../tools/slot_header.py
	python3 -I ../tools/slot_header.py $$< $$(SLOT_BASE_$(1)) $$(SLOT_VERSION) $$@

build/slot/$(1):
	mkdir -p $$@
endef
$(eval $(call SLOT_RULES,F))
$(eval $(call SLOT_RULES,A))
$(eval $(call SLOT_RULES,B))

slot: $(SLOT_BOOTS) build/boot.elf ../tools/slot_check.py
	python3 -I ../tools/slot_check.py build/boot.elf src/slot.inc $(SLOT_SPECS)

slot-check: $(SLOT_BOOTS) build/boot.elf ../tools/slot_check.py
	@test -n "$(RWDATA)" || { echo "usage: make slot-check RWDATA=<stock initial RAM image, 0x220 bytes>"; exit 1; }
	python3 -I ../tools/slot_check.py build/boot.elf src/slot.inc --rwdata "$(RWDATA)" $(SLOT_SPECS)

.PRECIOUS: build/slot/%/boot.elf build/slot/%/image.bin

clean:
	rm -rf build

.PHONY: all vendor-data check slot slot-check clean
