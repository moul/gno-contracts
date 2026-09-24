# Rebuild the RISC-V conformance corpus that p/moul/x/vm/riscv embeds in
# conformance_test.gno.
#
# See ../fnv/Makefile for why these are `:=` and not `?=`.
CC := clang
LD := ld.lld
OBJCOPY := llvm-objcopy

TESTS ?= /tmp/riscv-tests
OUT   ?= out

CFLAGS = --target=riscv32-unknown-elf -march=rv32im -mabi=ilp32 -nostdlib -mno-relax \
         -x assembler-with-cpp -I . -I $(TESTS)/isa/macros/scalar

SRCS := $(wildcard $(TESTS)/isa/rv32ui/*.S) $(wildcard $(TESTS)/isa/rv32um/*.S)

# clone fetches the suite. It is not vendored: what this repository commits is
# the built corpus, and the point of this directory is that it can be rebuilt.
clone:
	git clone --depth 1 --recurse-submodules \
	  https://github.com/riscv-software-src/riscv-tests.git $(TESTS)

build:
	@mkdir -p $(OUT)
	@for t in $(SRCS); do \
	  n=$$(basename $$t .S); d=$$(basename $$(dirname $$t)); \
	  $(CC) $(CFLAGS) -c $$t -o $(OUT)/$$d-$$n.o || exit 1; \
	  $(LD) -T link.ld --no-relax -o $(OUT)/$$d-$$n.elf $(OUT)/$$d-$$n.o || exit 1; \
	  $(OBJCOPY) -O binary --only-section=.text $(OUT)/$$d-$$n.elf $(OUT)/$$d-$$n.text.bin; \
	  $(OBJCOPY) -O binary --only-section=.data $(OUT)/$$d-$$n.elf $(OUT)/$$d-$$n.data.bin \
	    2>/dev/null || : > $(OUT)/$$d-$$n.data.bin; \
	done
	@echo "built $$(ls $(OUT)/*.text.bin | wc -l) cases into $(OUT)/"

# gen prints the corpus in the form conformance_test.gno holds it.
gen: build
	@python3 gen.py $(OUT)

clean:
	rm -rf $(OUT)

.PHONY: clone build gen clean
