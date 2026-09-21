package main

import (
	"fmt"
	"go/scanner"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Lexical guards over the contract trees.
//
// A .gno file is lexically a Go file: same tokens, same comment and string
// rules. So these read it with go/scanner instead of with regexps. That is
// what makes them exact about the two things a regexp keeps getting wrong — a
// `//` inside a string literal ("https://…"), and an identifier that merely
// ends in the name being looked for (`printRender`) — with no hand-written
// lexer. Nothing here depends on gno's *grammar*, only on its tokens, so a
// gno-only construct can never confuse it (the scanner never sees a
// production, and its errors are ignored on purpose).

// gnoTok is one lexical token of a .gno file.
type gnoTok struct {
	tok  token.Token
	lit  string
	line int
}

// scanGno tokenizes a .gno file, comments included. Scan errors are ignored:
// `gno lint` is what judges whether a file is well-formed, and a guard that
// refused to run on a file it could not fully parse would be weaker, not
// stronger.
func scanGno(path string) ([]gnoTok, error) {
	src, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	fset := token.NewFileSet()
	f := fset.AddFile(path, fset.Base(), len(src))
	var s scanner.Scanner
	s.Init(f, src, nil, scanner.ScanComments)

	var out []gnoTok
	for {
		pos, t, lit := s.Scan()
		if t == token.EOF {
			break
		}
		out = append(out, gnoTok{tok: t, lit: lit, line: f.Line(pos)})
	}
	return out, nil
}

// outputDirectiveRe mirrors go/doc's own: an example's output block is the
// comment `// Output:` or `// Unordered output:`, case-insensitively.
var outputDirectiveRe = regexp.MustCompile(`(?i)^//[[:space:]]*(unordered[[:space:]]+)?output[[:space:]]*:`)

// isTestFile reports whether a .gno file holds tests (normal or filetest).
func isTestFile(name string) bool {
	return strings.HasSuffix(name, "_test.gno") || strings.HasSuffix(name, "filetest.gno")
}

// funcSig reports whether toks[i] starts `func <Name>() {` — a top-level,
// zero-argument function declaration — and returns its name.
func funcSig(toks []gnoTok, i int) (string, bool) {
	if toks[i].tok != token.FUNC || i+4 >= len(toks) {
		return "", false
	}
	if toks[i+1].tok != token.IDENT ||
		toks[i+2].tok != token.LPAREN ||
		toks[i+3].tok != token.RPAREN ||
		toks[i+4].tok != token.LBRACE {
		return "", false
	}
	return toks[i+1].lit, true
}

// bodyComments returns the comments between the `{` at toks[open] and its
// matching `}`.
func bodyComments(toks []gnoTok, open int) []string {
	var out []string
	depth := 0
	for j := open; j < len(toks); j++ {
		switch toks[j].tok {
		case token.LBRACE:
			depth++
		case token.RBRACE:
			if depth--; depth == 0 {
				return out
			}
		case token.COMMENT:
			out = append(out, toks[j].lit)
		}
	}
	return out
}

// walkGno calls fn for every .gno file under the given trees, in a stable order.
func walkGno(root string, trees []string, fn func(rel string, toks []gnoTok) error) error {
	for _, tree := range trees {
		base := filepath.Join(root, filepath.FromSlash(tree))
		if !fileExists(base) {
			continue
		}
		err := filepath.WalkDir(base, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() || !strings.HasSuffix(d.Name(), ".gno") {
				return err
			}
			toks, err := scanGno(path)
			if err != nil {
				return err
			}
			rel, _ := filepath.Rel(root, path)
			return fn(filepath.ToSlash(rel), toks)
		})
		if err != nil {
			return err
		}
	}
	return nil
}

// cmdGuardExamples fails if any gno Example* test lacks an `// Output:` block.
//
// gno SILENTLY SKIPS an example function that has no output directive, so such
// an "ExampleRender" is a false-green test that asserts nothing. Every Example*
// must pin its output.
//
//	go tool gnocontracts guard-examples
func cmdGuardExamples(root string) error {
	var bad []string
	err := walkGno(root, []string{"p/moul", "r/moul"}, func(rel string, toks []gnoTok) error {
		if !strings.HasSuffix(rel, "_test.gno") {
			return nil
		}
		for i := range toks {
			name, ok := funcSig(toks, i)
			if !ok || !strings.HasPrefix(name, "Example") {
				continue
			}
			pinned := false
			for _, c := range bodyComments(toks, i+4) {
				if outputDirectiveRe.MatchString(c) {
					pinned = true
					break
				}
			}
			if !pinned {
				bad = append(bad, fmt.Sprintf("%s:%d:%s", rel, toks[i].line, name))
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	if len(bad) > 0 {
		sort.Strings(bad)
		return failf("guard-examples FAIL — Example* tests with NO `// Output:` (gno skips them silently → false green)", bad, "")
	}
	fmt.Println("guard-examples: every Example* test pins an // Output: block")
	return nil
}

// cmdGuardRender fails if a realm declares `func Render` but no test calls it.
//
// A realm's Render is its whole public surface, and in gno a Render whose
// output varies is a consensus bug — so it must be pinned by a test. Coverage
// counts from either a normal `_test.gno` or a `_filetest.gno`, and the call
// may be bare (`Render(`) or qualified (`home.Render(`). Archived packages
// (`ignore = true`) are skipped, as the toolchain skips them too.
//
//	go tool gnocontracts guard-render
func cmdGuardRender(root string) error {
	// declares[dir] — a non-test file declares Render; calls[dir] — a test calls it.
	declares, calls := map[string]bool{}, map[string]bool{}
	err := walkGno(root, []string{"r/moul"}, func(rel string, toks []gnoTok) error {
		dir := filepath.ToSlash(filepath.Dir(rel))
		if !fileExists(filepath.Join(root, filepath.FromSlash(dir), "gnomod.toml")) {
			return nil // loose file, not a package
		}
		test := isTestFile(filepath.Base(rel))
		for i := range toks {
			if !test {
				// `func Render(` — FUNC, then the name, then `(`. A method
				// (`func (r T) Render(`) has `(` right after FUNC and so
				// never matches, which is the intent: only a package-level
				// Render is a realm's entry point.
				if toks[i].tok == token.FUNC && i+2 < len(toks) &&
					toks[i+1].tok == token.IDENT && toks[i+1].lit == "Render" &&
					toks[i+2].tok == token.LPAREN {
					declares[dir] = true
				}
				continue
			}
			// A call is the identifier Render immediately followed by `(`.
			// The scanner yields whole identifiers, so `printRender(` is one
			// IDENT and cannot match.
			if toks[i].tok == token.IDENT && toks[i].lit == "Render" &&
				i+1 < len(toks) && toks[i+1].tok == token.LPAREN {
				calls[dir] = true
			}
		}
		return nil
	})
	if err != nil {
		return err
	}

	var bad []string
	for dir := range declares {
		if calls[dir] {
			continue
		}
		ignored, err := moduleIgnored(filepath.Join(root, filepath.FromSlash(dir), "gnomod.toml"))
		if err != nil {
			return err
		}
		if !ignored {
			bad = append(bad, dir)
		}
	}
	if len(bad) > 0 {
		sort.Strings(bad)
		return failf("guard-render FAIL — realms declaring Render that no test ever calls", bad,
			"Add an ExampleRender with a pinned `// Output:` block (preferred), or\n"+
				"assert with uassert.Equal when the output has consecutive blank lines.")
	}
	fmt.Println("guard-render: every realm's Render is exercised by a test")
	return nil
}

// ignoreRe matches the `ignore = true` line of a gnomod.toml.
var ignoreRe = regexp.MustCompile(`(?m)^[[:space:]]*ignore[[:space:]]*=[[:space:]]*true`)

// moduleIgnored reports whether a gnomod.toml marks its package archived.
func moduleIgnored(gnomod string) (bool, error) {
	b, err := os.ReadFile(gnomod)
	if err != nil {
		return false, err
	}
	return ignoreRe.Match(b), nil
}

// failf formats a guard failure: a headline, the offending items, and an
// optional hint.
func failf(headline string, items []string, hint string) error {
	var b strings.Builder
	b.WriteString(headline)
	b.WriteString(":\n")
	for _, it := range items {
		b.WriteString("  - " + it + "\n")
	}
	if hint != "" {
		b.WriteString("\n" + hint + "\n")
	}
	return fmt.Errorf("%s", strings.TrimRight(b.String(), "\n"))
}
