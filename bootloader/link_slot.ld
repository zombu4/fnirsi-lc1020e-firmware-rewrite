/* link_slot.ld - the slot build of the bootloader (make slot): the same sections in the stock
 * order (link_units.ld), linked from SLOT_BASE + 0x200 instead of the stock fixed addresses,
 * followed by .text.slot (src/slot_10.s) and the fixed data.  SLOT_BASE comes from the command
 * line (--defsym): slot F 0x08069000, A 0x0806F000, B 0x08075000 (24 KiB each).  The first 0x200
 * bytes of a slot hold its header, which ../tools/slot_header.py puts in front of this image; the
 * vector table therefore starts on a 512-byte boundary, the alignment VTOR needs for 102 entries.
 *
 * Every function keeps its stock address modulo 4 (the slot changes keep each section's size
 * modulo 4, and the sections the slot build leaves out are multiples of 4); 16-bit literal loads
 * typed as .inst.n depend on it.  ../tools/slot_check.py checks it on the linked image.
 * RAM addresses stay absolute as in the stock image (0x20000000..0x20002027, stack top
 * 0x20002028); the slot code's own RAM is 0x20002100..0x20002AFF (src/slot.inc). */
ENTRY(reset_handler)
SECTIONS
{
  .vectors (SLOT_BASE + 0x200) : { KEEP(*(.vectors)) }
  ASSERT(SIZEOF(.vectors) == 0x198, "vector table must have 102 words")

  .text :
  {
    INCLUDE link_units.ld
    KEEP(*(.text.slot))
  }

  .rodata : ALIGN(4) { KEEP(*(.rodata.fixed)) }
  ASSERT(. <= SLOT_BASE + 0x6000, "image does not fit its slot (0x5E00 bytes after the header)")
  ASSERT((. & 3) == 0, "image length must be a multiple of 4")

  /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.ARM.exidx*) }
}
