package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestCommittedFilesAreGenerated is the point of this package: the files in
// p/moul/xmath say "DO NOT EDIT", and this asserts that claim is true. If it
// fails, either someone hand-edited a generated file or the generator changed
// without `go -C tools run ./xmathgen` being re-run.
func TestCommittedFilesAreGenerated(t *testing.T) {
	for name, want := range map[string]string{
		"xmath.gen.gno":      genSource(),
		"xmath.gen_test.gno": genTest(),
	} {
		p := filepath.Join("..", "..", "p", "moul", "xmath", name)
		got, err := os.ReadFile(p)
		if err != nil {
			t.Fatalf("%s: %v", p, err)
		}
		if string(got) != want {
			t.Errorf("%s is stale; re-run `go -C tools run ./xmathgen`", p)
		}
	}
}

func TestUnsignedTypesHaveNoAbsOrSign(t *testing.T) {
	src := genSource()
	for _, name := range []string{"Uint8", "Uint16", "Uint32", "Uint64", "Uint"} {
		for _, fn := range []string{"Abs", "Sign"} {
			if strings.Contains(src, "func "+fn+name+"(") {
				t.Errorf("generated %s%s, but unsigned types must not get one", fn, name)
			}
		}
	}
}

func TestEverySignedTypeGetsFiveFunctions(t *testing.T) {
	src := genSource()
	for _, ty := range types {
		fns := []string{"Max", "Min", "Clamp"}
		if ty.Signed {
			fns = append(fns, "Abs", "Sign")
		}
		for _, fn := range fns {
			if !strings.Contains(src, "func "+fn+ty.Name+"(") {
				t.Errorf("missing func %s%s", fn, ty.Name)
			}
		}
	}
}

// TestGeneratedGnoHasNoTrailingBlankLine guards the formatting detail that made
// the first reconstruction of this generator differ from the committed file: a
// type's comment is followed immediately by its first function, with no blank
// line between them.
func TestTypeCommentIsFollowedByItsFunction(t *testing.T) {
	if !strings.Contains(genSource(), "// Int8 helpers\nfunc MaxInt8(") {
		t.Error("a blank line crept in between the type comment and its first function")
	}
}
