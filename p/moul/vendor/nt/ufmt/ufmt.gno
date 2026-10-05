package ufmt

import (
	"io"
	"strings"
)

// State is what a Formatter's Format method is handed: the flags, width and
// precision of the verb being printed, and somewhere to write.
type State interface {
	// Write emits formatted output.
	Write(b []byte) (n int, err error)
	// Width returns the width and whether one was set.
	Width() (wid int, ok bool)
	// Precision returns the precision and whether one was set.
	Precision() (prec int, ok bool)
	// Flag reports whether the flag c, a character, was set.
	Flag(c int) bool
}

// Formatter is implemented by a value that formats itself. Format is called
// for every verb, and its output replaces what ufmt would have printed.
type Formatter interface {
	Format(f State, verb rune)
}

// Stringer is implemented by a value that has a natural string form. It is
// used for %v, %s, %q, %x and %X, and by Print.
type Stringer interface {
	String() string
}

// GoStringer is implemented by a value that has a Go-syntax form, used for %#v.
type GoStringer interface {
	GoString() string
}

// Sprintf formats according to a format specifier and returns the string.
func Sprintf(format string, a ...any) string {
	p := newPrinter()
	p.doPrintf(format, a)
	return string(p.buf)
}

// Appendf formats according to a format specifier and appends the result to b.
func Appendf(b []byte, format string, a ...any) []byte {
	p := newPrinter()
	p.doPrintf(format, a)
	return append(b, p.buf...)
}

// Fprintf formats according to a format specifier and writes to w.
func Fprintf(w io.Writer, format string, a ...any) (n int, err error) {
	p := newPrinter()
	p.doPrintf(format, a)
	return w.Write(p.buf)
}

// Printf formats according to a format specifier and prints the result with
// the print builtin, which is what a test or a filetest captures.
func Printf(format string, a ...any) (n int, err error) {
	return printOut(Sprintf(format, a...))
}

// Sprint formats its operands with %v and returns the string. A space is added
// between two operands when neither is a string.
func Sprint(a ...any) string {
	p := newPrinter()
	p.doPrint(a)
	return string(p.buf)
}

// Append formats its operands as Sprint does and appends the result to b.
func Append(b []byte, a ...any) []byte {
	p := newPrinter()
	p.doPrint(a)
	return append(b, p.buf...)
}

// Fprint formats its operands as Sprint does and writes to w.
func Fprint(w io.Writer, a ...any) (n int, err error) {
	p := newPrinter()
	p.doPrint(a)
	return w.Write(p.buf)
}

// Print formats its operands as Sprint does and prints the result.
func Print(a ...any) (n int, err error) {
	return printOut(Sprint(a...))
}

// Sprintln formats its operands with %v, always separated by a space, and
// appends a newline.
func Sprintln(a ...any) string {
	p := newPrinter()
	p.doPrintln(a)
	return string(p.buf)
}

// Appendln formats its operands as Sprintln does and appends the result to b.
func Appendln(b []byte, a ...any) []byte {
	p := newPrinter()
	p.doPrintln(a)
	return append(b, p.buf...)
}

// Fprintln formats its operands as Sprintln does and writes to w.
func Fprintln(w io.Writer, a ...any) (n int, err error) {
	p := newPrinter()
	p.doPrintln(a)
	return w.Write(p.buf)
}

// Println formats its operands as Sprintln does and prints the result.
func Println(a ...any) (n int, err error) {
	return printOut(Sprintln(a...))
}

func printOut(s string) (int, error) {
	var sb strings.Builder
	n, err := sb.WriteString(s)
	print(sb.String())
	return n, err
}

// Errorf formats according to a format specifier and returns the string as an
// error. Each %w operand must be an error; it is printed as %v and returned by
// the error's Unwrap method, so errors.Is and errors.Unwrap can find it. One %w
// gives an Unwrap() error, several give an Unwrap() []error, as in Go.
func Errorf(format string, a ...any) error {
	p := newPrinter()
	p.wrapErrs = true
	p.doPrintf(format, a)
	s := string(p.buf)

	switch len(p.wrapped) {
	case 0:
		return &errorString{s}
	case 1:
		w := &wrapError{msg: s}
		w.err, _ = a[p.wrapped[0]].(error)
		return w
	default:
		if p.reordered {
			sortInts(p.wrapped)
		}
		var errs []error
		for i, argNum := range p.wrapped {
			if i > 0 && p.wrapped[i-1] == argNum {
				continue
			}
			if e, ok := a[argNum].(error); ok {
				errs = append(errs, e)
			}
		}
		return &wrapErrors{s, errs}
	}
}

type errorString struct {
	s string
}

func (e *errorString) Error() string { return e.s }

type wrapError struct {
	msg string
	err error
}

func (e *wrapError) Error() string { return e.msg }
func (e *wrapError) Unwrap() error { return e.err }

type wrapErrors struct {
	msg  string
	errs []error
}

func (e *wrapErrors) Error() string   { return e.msg }
func (e *wrapErrors) Unwrap() []error { return e.errs }

// sortInts is an insertion sort: the slice holds one entry per %w.
func sortInts(a []int) {
	for i := 1; i < len(a); i++ {
		for j := i; j > 0 && a[j] < a[j-1]; j-- {
			a[j], a[j-1] = a[j-1], a[j]
		}
	}
}
