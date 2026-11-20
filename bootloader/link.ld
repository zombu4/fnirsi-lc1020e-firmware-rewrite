/* link.ld - memory layout of the stock FNIRSI LC1020E bootloader, rebuilt from the assembly source.
 *
 * The rebuilt image must equal the stock bootloader byte for byte, so every function keeps its
 * original address: the vector table at 0x08000000 (src/vectors.s), then every function section
 * .text.<symbol> in the original address order from 0x08000198 (the KEEP list in
 * link_units.ld, shared with link_slot.ld), then the fixed data from 0x08003F64 (src/rodata.s: byte tables, strings, scatter-load region
 * table at 0x08004574, packed initial RAM image at 0x08004594) up to the image end 0x0800467C.
 *
 * FLASH is the bootloader's own range 0x08000000..0x08005FFF; the application starts at
 * 0x08006000 and is never linked over.  RAM addresses are absolute in the code: 0x20000000..
 * 0x2000021F get their initial values from the packed image at reset, 0x20000220..0x20002027
 * are zeroed, the initial stack pointer is 0x20002028.
 */
MEMORY
{
  FLASH (rx) : ORIGIN = 0x08000000, LENGTH = 0x6000
}
ENTRY(reset_handler)
SECTIONS
{
  .vectors 0x08000000 : { KEEP(*(.vectors)) } > FLASH
  ASSERT(. == 0x08000198, "vector table does not end at 0x08000198")

  .text 0x08000198 :
  {
    INCLUDE link_units.ld
  } > FLASH
  ASSERT(. == 0x08003F64, "code does not end at 0x08003F64")

  .rodata 0x08003F64 : { KEEP(*(.rodata.fixed)) } > FLASH
  ASSERT(. == 0x0800467C, "fixed data does not end at 0x0800467C")

  /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.ARM.exidx*) }
}
