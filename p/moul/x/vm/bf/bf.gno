// Package bf is a Brainfuck machine for gno.land, and the measuring stick the
// rest of the guest-VM work is calibrated against.
//
// It ships two things that look alike and are not:
//
//   - [Execute], the naive interpreter: a switch over the source bytes, a
//     brace matcher that rescans the program on every loop edge. It is kept
//     verbatim as rung 0 of the optimization ladder, because a baseline you
//     have edited is not a baseline.
//   - [Compile] plus [Machine], the real one: the program is compiled to an
//     op array with resolved jumps, runs of identical operators are fused,
//     the common loop idioms become single ops, and execution is metered by
//     a caller-supplied fuel budget against a
//     [vmkit](/p/moul/x/vm/vmkit/v0) Host, so a program can pause when it
//     runs out and resume in a later transaction.
//
// The ladder between them is measured, not asserted: see the README for the
// table, and ladder_test.gno for the harness that produces it.
//
// Live demo: [r/moul/x/vm/bfdemo](/r/moul/x/vm/bfdemo/v0).
package bf

import "strings"

// NaiveTapeSize is the tape length used by [Execute]. It is 30,000 because
// that is what the original had, and rung 0 is not allowed to drift.
const NaiveTapeSize = 30000

// Execute runs code on a fresh tape and returns everything it wrote, using
// the original 2023 implementation: no compilation step, one switch per
// source byte, and a brace matcher that rescans the source every time a loop
// opens or closes.
//
// It is rung 0 of the ladder and exists to be measured. Two of its properties
// are bugs that are deliberately preserved, and are the reason nothing should
// call it on untrusted input:
//
//   - `,` panics with "unsupported": there is no input.
//   - unbalanced brackets run the scan off the end of the source and panic
//     with an index out of range.
//
// Use [Compile] and [Machine] for anything real: they reject a malformed
// program up front, read input from the host, and cannot run unbounded.
func Execute(code string) string {
	var (
		memory  = make([]byte, NaiveTapeSize) // memory tape
		pointer = 0                           // initial memory pointer
		buf     strings.Builder
	)

	// Loop through each character in the code
	for i := 0; i < len(code); i++ {
		switch code[i] {
		case '>':
			// Increment memory pointer
			pointer++
			if pointer >= NaiveTapeSize {
				pointer = 0
			}
		case '<':
			// Decrement memory pointer
			pointer--
			if pointer < 0 {
				pointer = NaiveTapeSize - 1
			}
		case '+':
			// Increment the byte at the memory pointer
			memory[pointer]++
		case '-':
			// Decrement the byte at the memory pointer
			memory[pointer]--
		case '.':
			// Output the byte at the memory pointer
			buf.WriteByte(memory[pointer])
		case ',':
			// Input a byte and store it in the memory
			panic("unsupported")
		case '[':
			// Jump forward past the matching ']' if the byte at the memory pointer is zero
			if memory[pointer] == 0 {
				braceCount := 1
				for braceCount > 0 {
					i++
					if code[i] == '[' {
						braceCount++
					} else if code[i] == ']' {
						braceCount--
					}
				}
			}
		case ']':
			// Jump backward to the matching '[' if the byte at the memory pointer is nonzero
			if memory[pointer] != 0 {
				braceCount := 1
				for braceCount > 0 {
					i--
					if code[i] == ']' {
						braceCount++
					} else if code[i] == '[' {
						braceCount--
					}
				}
				i-- // Move back one more to compensate for the upcoming increment in the loop
			}
		}
	}
	return buf.String()
}
