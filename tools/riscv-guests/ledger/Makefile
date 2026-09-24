# Build the flat text image that p/moul/x/vm/riscv ships as riscv.GuestLedger.
#
# See ../fnv/Makefile for why these are `:=` and not `?=`.
RUSTC   := rustc
LD      := ld.lld
OBJCOPY := llvm-objcopy

TARGET := riscv32im-unknown-none-elf

# core and compiler_builtins are linked from the installed target, which is the
# normal way a bare-metal Rust binary is built: the guest calls neither
# directly, but a bounds check reaches core::panicking and a 64-bit divide
# reaches compiler_builtins' __udivdi3, because RV32 has no 64-bit divide.
SYSROOT := $(shell $(RUSTC) --print sysroot)
LIBDIR  := $(SYSROOT)/lib/rustlib/$(TARGET)/lib

RUSTFLAGS = --target $(TARGET) -C opt-level=s -C panic=abort -C relocation-model=static

all: guest.bin

guest.o: guest.rs
	$(RUSTC) $(RUSTFLAGS) --emit=obj -o $@ $<

# --gc-sections is not optional: without it the whole of core is linked and the
# image is 250 KB instead of 8 KB, which no realm would accept.
guest.elf: guest.o link.ld
	$(LD) -T link.ld --no-relax --gc-sections -o $@ guest.o \
	  $(wildcard $(LIBDIR)/libcore-*.rlib) \
	  $(wildcard $(LIBDIR)/libcompiler_builtins-*.rlib)

guest.bin: guest.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@

words: guest.bin
	@od -An -tx4 -v --endian=little guest.bin | \
	  awk '{for(i=1;i<=NF;i++) printf "0x%s, ", toupper($$i); print ""}'

# The entry point must be the first byte of the image, or a flat load starts in
# the middle of something.
check: guest.elf
	@llvm-readelf -h guest.elf | grep -q "Entry point address:               0x1000" \
	  && llvm-nm guest.elf | grep -q "^00001000 T _start" \
	  && echo "entry ok: _start is at 0x1000" \
	  || (echo "entry WRONG: _start is not at 0x1000"; exit 1)

clean:
	rm -f guest.o guest.elf guest.bin

.PHONY: all words check clean
