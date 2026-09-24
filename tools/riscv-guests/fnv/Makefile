# Build the flat text image that p/moul/x/vm/riscv ships as riscv.GuestFNV.
#
# There is no gno in this directory and nothing here is published. It exists so
# the compiled words in the gno package can be reproduced rather than trusted.

# Plain `:=`, deliberately, and neither `?=` nor an $(origin) test.
#
# `?=` never fires because make predefines CC. An $(origin CC) test for
# "default" does not fire either, because a nix-shell exports CC=gcc and that
# makes the origin "environment". Both failure modes are silent: the build
# reaches for the host gcc, which has no riscv32 target, and dies on
# -mabi=ilp32. A makefile assignment beats the environment and still loses to
# the command line, so `make CC=/path/to/clang` works.
CC := clang
LD := ld.lld
OBJCOPY := llvm-objcopy

CFLAGS = --target=riscv32-unknown-elf -march=rv32im -mabi=ilp32 \
         -nostdlib -ffreestanding -fno-pic -fno-builtin -mno-relax \
         -Os -Wall -Wextra

all: guest.bin

guest.o: guest.c
	$(CC) $(CFLAGS) -c $< -o $@

guest.elf: guest.o link.ld
	$(LD) -T link.ld --no-relax -o $@ guest.o

guest.bin: guest.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@

# words prints the image the way guests.gno holds it, four instructions a line,
# so a rebuild can be diffed against what is committed.
words: guest.bin
	@od -An -tx4 -v --endian=little guest.bin | \
	  awk '{for(i=1;i<=NF;i++) printf "0x%s, ", toupper($$i); print ""}'

clean:
	rm -f guest.o guest.elf guest.bin

.PHONY: all words clean
