ENTRY(_start)
SECTIONS {
  /* Nothing here unwinds, and a flat image must begin with the entry point:
     .eh_frame sorts before .text and would otherwise be the first thing the
     host executed. */
  /DISCARD/ : { *(.eh_frame) *(.eh_frame_hdr) *(.comment) }

  . = 0x1000;
  .text : {
    *(.text.init)
    *(.text._start)
    *(.text .text.*)
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  }

  . = 0x40000;
  .data : { *(.data .data.* .sdata .sdata.*) }
  .bss (NOLOAD) : { *(.sbss .sbss.* .bss .bss.* COMMON) }
}
