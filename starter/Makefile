# Build the starter (flash page 0, 0x08000000..0x080007FF).
#   make            -> build/STARTER.bin
#   make clean
AS      = arm-none-eabi-as
LD      = arm-none-eabi-ld
OBJCOPY = arm-none-eabi-objcopy

build/STARTER.bin: build/starter.elf
	$(OBJCOPY) -O binary $< $@
	@size=$$(wc -c < $@); echo "STARTER.bin $$size bytes"; \
	  if [ $$size -gt 2048 ]; then echo "starter larger than page 0"; rm -f $@; exit 1; fi

build/starter.elf: build/starter.o
	$(LD) -Ttext=0x08000000 -e reset -o $@ $<

build/starter.o: starter.s
	@mkdir -p build
	$(AS) -mcpu=cortex-m4 -mthumb -o $@ $<

clean:
	rm -rf build

.PHONY: clean
