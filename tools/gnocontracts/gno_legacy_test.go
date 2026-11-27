package main

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestLegacyGnoFollowsExactProductionSource(t *testing.T) {
	root := t.TempDir()
	const module = "gno.land/p/moul/example/v0"
	dir := "p/moul/example"
	mkpkg(t, root, dir, module, "")
	fingerprint, err := gnoProductionHash(filepath.Join(root, dir))
	if err != nil {
		t.Fatal(err)
	}
	baseline := fmt.Sprintf("# known compiler failure\n%s %s\n", module, fingerprint)

	oldDir := ".gnopm/" + module
	mkpkg(t, root, oldDir, module, "")
	writeFile(t, filepath.Join(root, oldDir), "x_test.gno", "package x\n// updated unit test\n")
	writeFile(t, filepath.Join(root, oldDir), "x_filetest.gno", "package main\n// updated filetest\n")
	writeFile(t, filepath.Join(root, oldDir), "README.md", "Updated documentation.\n")

	// The old version stays eligible when materialized from history. The new
	// version goes to the current toolchain even with identical Gno files.
	mkpkg(t, root, dir, "gno.land/p/moul/example/v1", "")
	dirs := []string{dir, oldDir}
	current, legacy, err := partitionGnoPackages(root, dirs, baseline)
	if err != nil || !slices.Equal(current, []string{dir}) || !slices.Equal(legacy, []string{oldDir}) {
		t.Fatalf("partition = %v, %v, %v; want v1 current and v0 legacy", current, legacy, err)
	}

	for _, tc := range []struct {
		name string
		file string
		data string
	}{
		{"production edit", "x.gno", "package x\nfunc F() {}\n"},
		{"production addition", "extra.gno", "package x\n"},
		{"module metadata edit", "gnomod.toml", `module = "` + module + `"` + "\ngno = \"0.9\"\nprivate = true\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			mkpkg(t, root, dir, module, "")
			writeFile(t, filepath.Join(root, dir), tc.file, tc.data)
			current, legacy, err := partitionGnoPackages(root, []string{dir}, baseline)
			if err != nil || !slices.Equal(current, []string{dir}) || len(legacy) != 0 {
				t.Fatalf("partition = %v, %v, %v; want current after a production change", current, legacy, err)
			}
		})
	}

	if err := os.Remove(filepath.Join(root, oldDir, "x.gno")); err != nil {
		t.Fatal(err)
	}
	current, legacy, err = partitionGnoPackages(root, dirs, baseline)
	if err != nil || !slices.Equal(current, dirs) || len(legacy) != 0 {
		t.Fatalf("partition = %v, %v, %v; want current after removing a production file", current, legacy, err)
	}
}
