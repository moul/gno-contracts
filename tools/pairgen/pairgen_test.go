package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSymbolOf(t *testing.T) {
	for _, tc := range []struct {
		in, want string
		wantErr  bool
	}{
		{"gno.land/r/moul/x/pairs/aaa/v0.AAA", "AAA", false},
		{"gno.land/r/gnoswap/gns.GNS.0000000", "0000000", false},
		{"gno.land/r/nt/foo20/v0", "", true},
		{"AAA", "", true},
	} {
		got, err := symbolOf(tc.in)
		if tc.wantErr {
			if err == nil {
				t.Errorf("symbolOf(%q) = %q, want an error", tc.in, got)
			}
			continue
		}
		if err != nil {
			t.Errorf("symbolOf(%q): %v", tc.in, err)
		} else if got != tc.want {
			t.Errorf("symbolOf(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestPkgName(t *testing.T) {
	for _, tc := range []struct{ a, b, want string }{
		{"AAA", "BBB", "aaabbb"},
		{"wr-app", "GNS", "wrappgns"},
		{"0X", "1Y", "pair0x1y"},
		{"--", "--", "pair"},
	} {
		if got := pkgName(tc.a, tc.b); got != tc.want {
			t.Errorf("pkgName(%q,%q) = %q, want %q", tc.a, tc.b, got, tc.want)
		}
	}
}

// TestInstanceCanonicalises pins the one property the generated file and the
// on-chain pair have to agree on: which token is the A side. pair.New sorts,
// so pairgen sorts, and the two argument orders produce the same instance.
func TestInstanceCanonicalises(t *testing.T) {
	a := "gno.land/r/x/zzz/v0.ZZZ"
	b := "gno.land/r/x/aaa/v0.AAA"
	one, err := instance(a, b, "ns")
	if err != nil {
		t.Fatal(err)
	}
	two, err := instance(b, a, "ns")
	if err != nil {
		t.Fatal(err)
	}
	if one != two {
		t.Fatalf("argument order changed the instance:\n%+v\n%+v", one, two)
	}
	if one.KeyA != b {
		t.Errorf("KeyA = %q, want the lexicographically smaller key %q", one.KeyA, b)
	}
}

func TestInstanceRejectsOneToken(t *testing.T) {
	if _, err := instance("gno.land/r/x/a/v0.A", "gno.land/r/x/a/v0.A", "ns"); err == nil {
		t.Fatal("a pair of one token was accepted")
	}
}

// TestRunWritesDeversionedLayout is the regression that matters: the version
// belongs in the module line, never in a directory name.
func TestRunWritesDeversionedLayout(t *testing.T) {
	dir := t.TempDir()
	out, err := os.CreateTemp(dir, "out")
	if err != nil {
		t.Fatal(err)
	}
	defer out.Close()
	err = run([]string{"-o", dir, "-namespace", "ns",
		"gno.land/r/x/aaa/v0.AAA", "gno.land/r/x/bbb/v0.BBB"}, out)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "aaabbb", "v0")); err == nil {
		t.Fatal("pairgen wrote a v0/ directory; the version lives in the module line")
	}
	mod, err := os.ReadFile(filepath.Join(dir, "aaabbb", "gnomod.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if want := `module = "gno.land/r/ns/aaabbb/v0"`; !strings.Contains(string(mod), want) {
		t.Errorf("gnomod.toml does not carry %s:\n%s", want, mod)
	}
	if !strings.Contains(string(mod), "# public:") {
		t.Errorf("gnomod.toml never answers the private question:\n%s", mod)
	}
	src, err := os.ReadFile(filepath.Join(dir, "aaabbb", "aaabbb.gno"))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"package aaabbb", `keyA = "gno.land/r/x/aaa/v0.AAA"`, "pairreg.Register"} {
		if !strings.Contains(string(src), want) {
			t.Errorf("generated source is missing %q", want)
		}
	}
}

func TestSizeForTracksGnopm(t *testing.T) {
	gas, fee := sizeFor(2500)
	if gas != 4_500_000 {
		t.Errorf("gas = %d, want 4500000", gas)
	}
	if fee != 45_000 {
		t.Errorf("fee = %d, want 45000", fee)
	}
	if _, fee := sizeFor(0); fee != 1 {
		t.Errorf("fee for an empty package = %d, want the 1ugnot floor", fee)
	}
}

// TestRunAcceptsFlagsAfterKeys pins the argument order the README documents.
// Go's flag package stops at the first non-flag word, so without the permute
// `pairgen keyA keyB -o dir` writes into the wrong directory and says nothing.
func TestRunAcceptsFlagsAfterKeys(t *testing.T) {
	dir := t.TempDir()
	out, err := os.CreateTemp(dir, "out")
	if err != nil {
		t.Fatal(err)
	}
	defer out.Close()
	err = run([]string{"gno.land/r/x/aaa/v0.AAA", "gno.land/r/x/bbb/v0.BBB",
		"-o", dir, "-namespace", "ns"}, out)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "aaabbb", "aaabbb.gno")); err != nil {
		t.Fatalf("-o after the keys was ignored: %v", err)
	}
}
