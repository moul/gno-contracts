// A freestanding RV32IM guest for gno.land: no libc, no runtime, three
// syscalls. It reads the call input, hashes it with FNV-1a, and writes the
// hash back as eight hex digits.
//
// The point is not the hash. It is that this file is compiled by clang and
// optimized by LLVM, and the emulator on the other side was never told what it
// was going to be handed.

#define SYS_READ  63
#define SYS_WRITE 64
#define SYS_EXIT  93

// The RISC-V Linux syscall convention: a7 selects, a0..a2 carry, a0 returns.
static inline long syscall3(long n, long a, long b, long c) {
	register long a7 __asm__("a7") = n;
	register long a0 __asm__("a0") = a;
	register long a1 __asm__("a1") = b;
	register long a2 __asm__("a2") = c;
	__asm__ volatile("ecall" : "+r"(a0) : "r"(a7), "r"(a1), "r"(a2) : "memory");
	return a0;
}

// Globals land in .bss, which the linker script puts well above the text
// segment. That matters: the host makes the text read-only, so a guest whose
// writable data shared a page with its code would trap on its first store.
static unsigned char in[256];
static char out[8];

__attribute__((section(".text.start"), used)) void _start(void)
{
	long n = syscall3(SYS_READ, 0, (long)in, sizeof(in));
	if (n < 0)
		n = 0;

	// FNV-1a. The multiply is why this is rv32im and not rv32i.
	unsigned int h = 2166136261u;
	for (long i = 0; i < n; i++) {
		h ^= in[i];
		h *= 16777619u;
	}

	for (int i = 0; i < 8; i++) {
		unsigned int nib = (h >> (28 - i * 4)) & 0xF;
		out[i] = (char)(nib < 10 ? '0' + nib : 'a' + (nib - 10));
	}

	syscall3(SYS_WRITE, 1, (long)out, 8);
	syscall3(SYS_EXIT, 0, 0, 0);
	__builtin_unreachable();
}
