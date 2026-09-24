ENTRY(_start)
SECTIONS {
  /* The text segment starts at the host's conventional entry point and holds
     read-only data too: the host refuses stores into it, which is exactly what
     .rodata wants anyway. */
  . = 0x1000;
  .text : {
    *(.text.start)
    *(.text .text.*)
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  }

  /* Writable data lives far above the image, in memory the host zeroes and
     never marks as code. Nothing is copied in at load: everything here starts
     at zero, which is why the guest has no initialized data. */
  . = 0x40000;
  .bss (NOLOAD) : {
    *(.sbss .sbss.* .bss .bss.* COMMON)
  }
}
