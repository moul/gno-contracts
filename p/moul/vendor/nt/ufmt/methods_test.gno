package ufmt

import (
	"errors"
	"strings"
	"testing"
)

type str struct{ s string }

func (v str) String() string { return v.s }

type errT struct{}

func (errT) Error() string  { return "boom" }
func (errT) String() string { return "stringer" }

type goStr struct{}

func (goStr) GoString() string { return "goStr{}" }
func (goStr) String() string   { return "plain" }

type formatter struct{}

func (formatter) Format(f State, verb rune) {
	w, wok := f.Width()
	p, pok := f.Precision()
	Fprintf(f, "F[%c w=%d/%t p=%d/%t minus=%t plus=%t sharp=%t]",
		verb, w, wok, p, pok, f.Flag('-'), f.Flag('+'), f.Flag('#'))
}

type panicky struct{}

func (panicky) String() string { panic("nope") }

type opaque struct{ n int }

// Every want below is what Go's fmt prints for the same call (go1.27.1),
// except where a comment says gno cannot see what Go sees.
func TestMethods(t *testing.T) {
	cases := []struct{ got, want string }{
		{Sprintf("%v|%s|%q|%x|%10s|%-6v|", str{"hi"}, str{"hi"}, str{"hi"}, str{"hi"}, str{"hi"}, str{"hi"}),
			`hi|hi|"hi"|6869|        hi|hi    |`},
		{Sprintf("%v %s", errT{}, errT{}), "boom boom"}, // Error wins over String
		{Sprintf("%#v %v", goStr{}, goStr{}), "goStr{} plain"},
		{Sprintf("%v|%-8.3s|%+#x", formatter{}, formatter{}, formatter{}),
			"F[v w=0/false p=0/false minus=false plus=false sharp=false]|" +
				"F[s w=8/true p=3/true minus=true plus=false sharp=false]|" +
				"F[x w=0/false p=0/false minus=false plus=true sharp=true]"},
		{Sprintf("%v", panicky{}), "%!v(PANIC=String method: nope)"},
		{Sprintf("%v", []any{str{"a"}, errT{}}), "[a boom]"},
		{Sprintf("%s", []error{errors.New("base"), errT{}}), "[base boom]"},
		{Sprint("a", 1, 2, "b", "c", 3.5, true, nil), "a1 2bc3.5 true <nil>"},
		{Sprint(str{"x"}, str{"y"}), "x y"},
		{Sprintln("a", 1, 2, "b"), "a 1 2 b\n"},

		// Go reflects into the struct and prints "{%!d(string=hi)}" and
		// "{7}"; gno has no reflect, so v2 says so instead of guessing.
		{Sprintf("%d", str{"hi"}), "%!d(unhandled)"},
		{Sprintf("%v", opaque{7}), "(unhandled)"},
		{Sprintf("%T", opaque{7}), "unknown"},
		// Go prints "%!w(*errors.errorString=&{base})": the type is not
		// nameable here either.
		{Sprintf("%w", errors.New("base")), "%!w(unhandled)"},
	}
	for i, c := range cases {
		if c.got != c.want {
			t.Errorf("case %d: got %q, want %q", i, c.got, c.want)
		}
	}
}

func TestErrorf(t *testing.T) {
	base := errors.New("base")

	e := Errorf("wrap: %w", base)
	if e.Error() != "wrap: base" || !errors.Is(e, base) || errors.Unwrap(e) != base {
		t.Errorf("single %%w: %q, Is=%t", e.Error(), errors.Is(e, base))
	}

	e2 := Errorf("two: %w and %w", base, errT{})
	if e2.Error() != "two: base and boom" || !errors.Is(e2, base) || errors.Unwrap(e2) != nil {
		t.Errorf("two %%w: %q, Is=%t", e2.Error(), errors.Is(e2, base))
	}

	if got := Errorf("%w", "notanerror").Error(); got != "%!w(string=notanerror)" {
		t.Errorf("non-error %%w: %q", got)
	}

	plain := Errorf("plain %d", 1)
	if plain.Error() != "plain 1" || errors.Unwrap(plain) != nil {
		t.Errorf("plain: %q", plain.Error())
	}
}

func TestWriters(t *testing.T) {
	var sb strings.Builder
	n, err := Fprintf(&sb, "%04d|", 7)
	Fprint(&sb, "a", 1)
	Fprintln(&sb, "!", 2)
	if sb.String() != "0007|a1! 2\n" || n != 5 || err != nil {
		t.Errorf("Fprint*: %q n=%d err=%v", sb.String(), n, err)
	}

	b := Appendf([]byte("x="), "%x", 255)
	b = Append(b, " ", true)
	b = Appendln(b, "", 1)
	if string(b) != "x=ff true 1\n" {
		t.Errorf("Append*: %q", string(b))
	}
}

// The register dump that v0 could not print: "0x(unhandled verb: %X)".
func TestRegisterDump(t *testing.T) {
	got := Sprintf("0x%08X %08x", uint32(0x1004), uint32(0xa00513))
	if got != "0x00001004 00a00513" {
		t.Errorf("got %q", got)
	}
}
