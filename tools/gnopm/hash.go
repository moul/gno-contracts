package main

import (
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// hashPrefix tags the algorithm. Carried in the lock so the algorithm can be
// replaced later without a format bump: a reader that meets an unknown prefix
// knows it cannot verify rather than comparing two incomparable strings.
const hashPrefix = "h1:"

// hashFiles computes the h1 content hash of a named set of files.
//
// Deliberately identical in construction to Go's golang.org/x/mod/sumdb/dirhash
// Hash1: sha256 over a sorted manifest of "<sha256 of content>  <name>\n"
// lines. Same properties, same reasoning, and anybody who has read a go.sum
// already knows what an h1: means.
//
// The hashed set is every *git-tracked* file in the package directory, with
// names relative to that directory. Tracked-ness is what makes it reproducible:
// it is the same set whether the code is read out of the working tree or out of
// `git archive`, and it dodges the "is _test.gno part of the package" judgement
// call entirely by not making one.
func hashFiles(names []string, open func(string) (io.ReadCloser, error)) (string, error) {
	sorted := append([]string(nil), names...)
	sort.Strings(sorted)
	h := sha256.New()
	for _, name := range sorted {
		if strings.Contains(name, "\n") {
			return "", fmt.Errorf("file name %q contains a newline", name)
		}
		rc, err := open(name)
		if err != nil {
			return "", err
		}
		hf := sha256.New()
		_, err = io.Copy(hf, rc)
		rc.Close()
		if err != nil {
			return "", err
		}
		fmt.Fprintf(h, "%x  %s\n", hf.Sum(nil), name)
	}
	return hashPrefix + base64.StdEncoding.EncodeToString(h.Sum(nil)), nil
}

// hashDirFiles hashes the given relative names read from disk under dir.
func hashDirFiles(dir string, names []string) (string, error) {
	return hashFiles(names, func(name string) (io.ReadCloser, error) {
		return os.Open(filepath.Join(dir, filepath.FromSlash(name)))
	})
}

// hashString hashes a blob, used for the .gnopm stamp.
func hashString(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hashPrefix + base64.StdEncoding.EncodeToString(sum[:])
}
