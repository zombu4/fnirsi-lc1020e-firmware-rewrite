/* link.ld - memory layout of the FNIRSI LC1020E application V1.1, rebuilt from the assembly source.
 *
 * The rebuilt image must equal the vendor update file byte for byte, so every function keeps its
 * original address: the vector table at 0x08006000 (src/vectors.s), then every function section
 * .text.<symbol> in the original address order from 0x08006198 (the KEEP list in link_units.ld),
 * then the fixed data from 0x0802AE94 (src/rodata_NN.s, link_rodata.ld: tables, strings, fonts and
 * pictures, the scatter-load region table at 0x08051510, the packed initial RAM image at 0x08051530)
 * up to the image end 0x08051758.
 *
 * FLASH is the application area of the two-part bootloader, 0x08006000..0x08061FFF.  RAM
 * addresses are absolute in the code: 0x20000000..0x2000057B get their initial values from the
 * packed image at reset, 0x2000057C..0x200163A7 are zeroed, the initial stack pointer is
 * 0x200163A8.
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
  ASSERT(. == 0x08051758, "fixed data does not end at 0x08051758")

  /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.ARM.exidx*) }
}
