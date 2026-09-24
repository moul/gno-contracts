// A riscv-tests environment for a machine with no CSRs and no privilege modes.
//
// The official env/p sets up mtvec, delegates traps, and returns to the test
// through mret. None of that exists on this hart: there is one privilege level
// and the only way out is ecall. So this header keeps the parts of the contract
// the tests actually rely on (the _start symbol, TESTNUM in gp, and the exit
// convention) and drops the machine-mode ceremony.
//
// The exit convention is the env's own and is unchanged: pass leaves a0 = 0,
// fail leaves a0 = (testnum << 1) | 1. env/p already spells both with
// `li a7, 93; ecall`, which is this host's exit syscall, so the harness reads
// a0 out of the halted machine and needs no tohost region at all.

#ifndef _ENV_GNO_RISCV_TEST_H
#define _ENV_GNO_RISCV_TEST_H

#define RVTEST_RV32U     .macro init; .endm
#define RVTEST_RV64U     .macro init; .endm
#define RVTEST_RV32M     .macro init; .endm
#define RVTEST_RV64M     .macro init; .endm
#define RVTEST_RV32S     .macro init; .endm
#define RVTEST_RV64S     .macro init; .endm

#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align 6;                                                       \
        .globl _start;                                                  \
_start:                                                                 \
        li TESTNUM, 0;                                                  \
        init;                                                           \
        j 1f;                                                           \
        .align 2;                                                       \
1:

// A test that runs off its own end has neither passed nor failed, and must not
// be allowed to wander into whatever follows. An unknown word traps here, which
// the harness reports as a trap rather than as a pass.
#define RVTEST_CODE_END                                                 \
        .word 0

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li TESTNUM, 1;                                                  \
        li a7, 93;                                                      \
        li a0, 0;                                                       \
        ecall

#define RVTEST_FAIL                                                     \
        fence;                                                          \
1:      beqz TESTNUM, 1b;                                               \
        sll TESTNUM, TESTNUM, 1;                                        \
        or TESTNUM, TESTNUM, 1;                                         \
        li a7, 93;                                                      \
        addi a0, TESTNUM, 0;                                            \
        ecall

// No tohost and no fromhost: nothing here communicates through memory.
#define EXTRA_DATA
#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .align 4; .global begin_signature; begin_signature:
#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
