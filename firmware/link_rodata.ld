/* link_rodata.ld - the parts of the fixed data in address order (src/rodata_01.s .. rodata_04.s, one
 * section .rodata.fixed.<first address> each).  Included by link.ld.
 */
    KEEP(*(.rodata.fixed.0802ae94))
    KEEP(*(.rodata.fixed.080371f4))
    KEEP(*(.rodata.fixed.0804bbf8))
    KEEP(*(.rodata.fixed.0805113c))
