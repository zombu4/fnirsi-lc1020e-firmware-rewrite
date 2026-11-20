# Makefile - assemble sram_dumper.s into sram_dumper.bin (load address 0x08006000).
#
#   make        build sram_dumper.bin and print its size and SHA-256
#   make clean  remove the build output
#
# Needs the GNU Arm Embedded binutils (arm-none-eabi-as, -ld, -objcopy).

PREFIX ?= arm-none-eabi-
LOAD   := 0x08006000

all: sram_dumper.bin
	@ls -l sram_dumper.bin
	@shasum -a 256 sram_dumper.bin

sram_dumper.o: sram_dumper.s
	$(PREFIX)as -mcpu=cortex-m4 -mthumb -o $@ $<

sram_dumper.elf: sram_dumper.o
	$(PREFIX)ld -Ttext=$(LOAD) -e reset -o $@ $<

sram_dumper.bin: sram_dumper.elf
	$(PREFIX)objcopy -O binary $< $@

clean:
	rm -f sram_dumper.o sram_dumper.elf sram_dumper.bin

.PHONY: all clean
