# Makefile - build the FNIRSI LC1020E application from its assembly source and prove it byte for byte.
#
#   make vendor-data IMAGE=<LC1020E_V1.1_250702.bin>
#                 copy the vendor data blocks the source includes with .incbin (fonts, pictures,
#                 tables, the packed initial RAM image; listed with their SHA-256 in vendor_blobs.tsv)
#                 out of your own copy of the vendor update file into assets/vendor/; they are not
#                 part of this repository
#   make          build/APP.bin: assemble src/*.s, link with link.ld, 0x08006000..0x08051757
#                 (309080 bytes)
#   make check    build/APP.bin, then its size and SHA-256 compared with the vendor update file
#                 V1.1 (the byte proof of the port)
#   make uf2      build/APP.uf2 for the update drive of the slot bootloader (../tools/bin2uf2.py)
#   make own      our application build: src/*.s and own/*.s assembled with --defsym OWN=1 (the
#                 .ifdef OWN hooks in src/ and our modules), linked with link_own.ld (the port's
#                 code at its fixed addresses up to 0x0802AE94, then the packed data with the
#                 typed initial RAM image, then own/, end at or below 0x08062000, no RAM
#                 section), build/own/APP_OWN.bin and build/own/APP_OWN.uf2; check it with
#                 python3 -I ../tests/check_pack.py. Never-brick: own/
#                 reaches the flash controller only through own/save.s (flash_word,
#                 flash_erase_page and their gate); no other file of own/ addresses it.
#   make clean    remove build/
#
# Needs the GNU Arm Embedded binutils (arm-none-eabi-as, -ld, -objcopy), shasum and python3.

CROSS   ?= arm-none-eabi-
AS      := $(CROSS)as
LD      := $(CROSS)ld
OBJCOPY := $(CROSS)objcopy
ASFLAGS := -march=armv7e-m -mthumb -I .
SRC     := $(wildcard src/*.s)
OBJ     := $(patsubst src/%.s,build/%.o,$(SRC))
STAMP   := assets/vendor/.ok
OWN_SRC := $(wildcard own/*.s)
OWN_INC := $(wildcard own/*.inc)
OWN_OBJ := $(patsubst src/%.s,build/own/src/%.o,$(SRC)) $(patsubst own/%.s,build/own/mod/%.o,$(OWN_SRC))

# the vendor update file V1.1 (LC1020E_V1.1_250702.bin)
APP_SIZE   := 309080
APP_SHA256 := 3920cebfec0c249714ac6345996c97f7aba358fdbbe283d58027dfe9dc9033ff

all: build/APP.bin

$(STAMP):
	@echo "missing assets/vendor: run make vendor-data IMAGE=<LC1020E_V1.1_250702.bin> first"; exit 1

vendor-data:
	@test -n "$(IMAGE)" || { echo "usage: make vendor-data IMAGE=<LC1020E_V1.1_250702.bin>"; exit 1; }
	python3 -I ../tools/vendor_data.py "$(IMAGE)" vendor_blobs.tsv assets/vendor
	@touch $(STAMP)

build/own/src/%.o: src/%.s $(STAMP) | build/own/src
	$(AS) $(ASFLAGS) --defsym OWN=1 -o $@ $<

build/own/mod/%.o: own/%.s $(OWN_INC) | build/own/mod
	$(AS) $(ASFLAGS) --defsym OWN=1 -o $@ $<

build/%.o: src/%.s $(STAMP) | build
	$(AS) $(ASFLAGS) -o $@ $<

build/app.elf: $(OBJ) link.ld link_units.ld link_rodata.ld
	@test -n "$(OBJ)" || { echo "src/ holds no .s file"; exit 1; }
	$(LD) --no-warn-rwx-segments -T link.ld -Map build/app.map -o $@ $(OBJ)

build/APP.bin: build/app.elf
	$(OBJCOPY) -O binary $< $@

check: build/APP.bin
	@test `wc -c < $<` -eq $(APP_SIZE) || { echo "$<: size differs from $(APP_SIZE)"; exit 1; }
	@echo "$(APP_SHA256)  $<" | shasum -a 256 -c -

uf2: build/APP.bin
	python3 -I ../tools/bin2uf2.py $< build/APP.uf2

own: build/own/APP_OWN.bin build/own/APP_OWN.uf2

build/own/app_own.elf: $(OWN_OBJ) link_own.ld link_units.ld link_rodata.ld
	@test -n "$(OWN_SRC)" || { echo "own/ holds no .s file"; exit 1; }
	$(LD) --no-warn-rwx-segments -T link_own.ld -Map build/own/app_own.map -o $@ $(OWN_OBJ)

build/own/APP_OWN.bin: build/own/app_own.elf
	$(OBJCOPY) -O binary $< $@

build/own/APP_OWN.uf2: build/own/APP_OWN.bin
	python3 -I ../tools/bin2uf2.py $< $@

build:
	mkdir -p build

build/own/src build/own/mod:
	mkdir -p $@

clean:
	rm -rf build

.PHONY: all vendor-data check uf2 own clean
