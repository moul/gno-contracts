ENTRY(_start)
SECTIONS {
  . = 0x1000;
  .text : { *(.text.init) *(.text .text.*) *(.rodata .rodata.*) *(.srodata .srodata.*) }
  . = 0x40000;
  .data : { *(.data .data.* .sdata .sdata.*) }
  .bss (NOLOAD) : { *(.sbss .sbss.* .bss .bss.* COMMON) }
}
