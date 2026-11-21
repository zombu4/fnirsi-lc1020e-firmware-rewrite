/* link_own.ld - memory layout of our application build (make own): the port's code at its
 * fixed addresses, then the packed data, then our modules (firmware/own/*.s).
 *
 * 0x08006000 vector table, 0x08006198 every function of the port in its original address
 * order (link_units.ld), up to 0x0802AE94, as in link.ld: the .ifdef OWN hooks are same-size
 * changes, so every ported function keeps its address (the hook sites, own/power.s
 * LR_VENDOR_DEL and the 30 code pointers of the initial RAM image rely on it).
 *
 * From 0x0802AE94 the read-only data (link_rodata.ld: src/rodata_01.s .. rodata_04.s in V1.1
 * order), packed: each freed range of LANGUAGE_DESIGN.md (the CJK font tails, the Chinese
 * speed icons, the Chinese strings) is reduced to its size mod 4 bytes of 0xFF, so every
 * kept byte keeps its V1.1 address mod 4 and stays next to its V1.1 neighbours; every pointer
 * to the data is a label (code literals, descriptor and font words, the typed initial RAM
 * image), so the linker sets it. In this build a d_<address> name is the V1.1 address of its
 * data, no longer its address (tests/check_pack.py maps one to the other). The packed V1.1
 * RAM image is replaced by the typed image d_08051530 directly after the region table
 * d_08051510 (src/rodata_04.s): __scatterload compares the table walk against d_08051530
 * (unsigned, 0x08007860) and loads the table with ldm.w (0x08007858, faults on an unaligned
 * address), hence the ASSERTs below.
 *
 * Then the code (.text.own.*) and the constant data (.rodata.own.*) of own/*.s; their end
 * own_image_end must stay at or below 0x08062000, the end of the application area of the
 * two-part bootloader (bootloader/src/slot.inc APP_END).
 *
 * Our RAM 0x20018000..0x2001DFFF and the no-init words 0x2001FFF0..0x2001FFFF are absolute
 * addresses in own/own.inc: no section is placed in RAM, and the ASSERT below refuses an
 * image whose objects hold any .data or .bss bytes.
 */
MEMORY
{
  FLASH (rx) : ORIGIN = 0x08006000, LENGTH = 0x5C000
}
ENTRY(Reset_Handler)
SECTIONS
{
  .vectors 0x08006000 : { KEEP(*(.vectors)) } > FLASH
  ASSERT(. == 0x08006198, "vector table does not end at 0x08006198")

  .text 0x08006198 :
  {
    INCLUDE link_units.ld
  } > FLASH
  ASSERT(. == 0x0802AE94, "code does not end at 0x0802AE94")

  .rodata 0x0802AE94 :
  {
    INCLUDE link_rodata.ld
  } > FLASH
  ASSERT((d_08051510 & 3) == 0, "region table d_08051510 is not word aligned")
  ASSERT(d_08051530 - d_08051510 == 32, "the RAM image does not follow the region table")

  .own :
  {
    KEEP(*(.text.own.*))
    KEEP(*(.rodata.own.*))
    . = ALIGN(4);
    own_image_end = .;
  } > FLASH
  ASSERT(own_image_end <= 0x08062000, "our build does not end at or below 0x08062000")

  .ramcheck (NOLOAD) :
  {
    *(.data) *(.data.*) *(.bss) *(.bss.*) *(COMMON)
  }
  ASSERT(SIZEOF(.ramcheck) == 0, "an object holds .data or .bss: our RAM is absolute only")

  /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.ARM.exidx*) }
}
