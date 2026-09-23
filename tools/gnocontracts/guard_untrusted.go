package main

import (
	"fmt"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// The escaping question, and why a guard asks it rather than a review.
//
// A realm's Render output is markdown that a reader's browser turns into a
// page. Anything a caller typed and the realm stored is attacker-controlled
// text, and concatenating it into that markdown lets the caller write the page:
// a link, an image, a table that breaks its own column, a bidi run that
// reverses the sentence around it.
//
// The standard already exists in two layers, so this guard enforces rather than
// invents. `p/nt/markdown/sanitize/v0` upstream has one helper per markdown
// slot; `p/moul/kit/ui` wraps the two used most, `ui.Inline` and `ui.Cell`.
//
// What makes it a guard and not a convention is that the miss is permanent. A
// public package path is immutable: AddPackage refuses a path already occupied
// unless the live package is private, so a realm that ships an unescaped Render
// keeps it forever and the fix is a new version at a new path. Escaping is a
// pre-deploy gate or it is nothing.
//
// It was a convention until 2026-09-22, and the convention lost: `r/moul/x/reaper`
// shipped a board that rendered a caller's note body raw, one PR after 25 other
// realms were ported to `ui.*`. Measured over the tree that day, 36 of 49
// realms that both declare Render and take a caller string escaped nothing.

// sanitizers are the call prefixes that count as escaping. Any one of them
// appearing anywhere in a realm is enough: this is a lexical approximation, and
// it is deliberately generous, because its job is to catch the realm that
// escapes NOTHING rather than to audit each call site. A realm that escapes one
// string and forgets another is a code review's problem, not a guard's.
var sanitizers = []string{"sanitize", "ui"}

// sanitizerFuncs are the member names that make a `sanitizers` receiver count.
// Without this, `ui.Empty` or a local variable named `ui` would pass a realm
// that escapes nothing.
var sanitizerFuncs = map[string]bool{
	// p/moul/kit/ui
	"Inline": true, "Cell": true, "Action": true, "ActionIn": true,
	// p/nt/markdown/sanitize, used directly
	"InlineText": true, "Block": true, "TableCell": true, "URL": true, "CodeBlock": true,
}

// untrustedOptOutRe matches the opt-out: a `// untrusted-render: <why>` comment.
//
// A realm whose stored strings are all validated at write time (one letter, an
// enum, a semver, a charset-checked word) has nothing to escape, and saying so
// in the file is cheaper than an allowlist in the tool that nobody revisits.
var untrustedOptOutRe = regexp.MustCompile(`//[[:space:]]*untrusted-render:[[:space:]]*(\S.*?)[[:space:]]*$`)

// minUntrustedReason is the floor on an opt-out reason, in characters. "n/a"
// and "validated" answer nothing; the real ones name the validation.
const minUntrustedReason = 20

// cmdGuardUntrusted fails when a realm renders a page, stores a string its
// caller chose, and never escapes anything.
//
// The three conditions are all lexical approximations, and each is chosen to
// under-report rather than over-report:
//
//   - renders: a package-level `func Render(`, the same test cmdGuardRender uses.
//   - takes a caller string: an exported function with a `string` parameter.
//     A realm that takes no string from anyone cannot render one.
//   - escapes nothing: no call to any name in sanitizerFuncs on a `sanitizers`
//     receiver, anywhere in the package.
func cmdGuardUntrusted(root string) error {
	renders := map[string]bool{}
	takesString := map[string]bool{}
	escapes := map[string]bool{}
	optOut := map[string]string{}

	err := walkGno(root, []string{"r/moul"}, func(rel string, toks []gnoTok) error {
		dir := filepath.ToSlash(filepath.Dir(rel))
		if !fileExists(filepath.Join(root, filepath.FromSlash(dir), "gnomod.toml")) {
			return nil // loose file, not a package
		}
		if isTestFile(filepath.Base(rel)) {
			return nil // a test is not the page, and its strings are the author's
		}
		for i := range toks {
			switch {
			case toks[i].tok == token.COMMENT:
				if m := untrustedOptOutRe.FindStringSubmatch(toks[i].lit); m != nil {
					optOut[dir] = m[1]
				}
			case toks[i].tok == token.FUNC && i+2 < len(toks) &&
				toks[i+1].tok == token.IDENT && toks[i+2].tok == token.LPAREN:
				name := toks[i+1].lit
				if name == "Render" {
					renders[dir] = true
				}
				// Render itself is excluded: its `path string` is a
				// caller string too, but every realm has one, and counting
				// it would flag the whole tree and mean nothing. What this
				// guard is about is a string a caller WROTE INTO the realm,
				// which arrives through a crossing function.
				if name != "Render" && isExportedName(name) && storesCallerString(toks, i+2) {
					takesString[dir] = true
				}
			case toks[i].tok == token.IDENT && isSanitizerCall(toks, i):
				escapes[dir] = true
			}
		}
		return nil
	})
	if err != nil {
		return err
	}

	baseline, err := readUntrustedBaseline(root)
	if err != nil {
		return err
	}

	var bad, thin []string
	var stale []string
	for dir := range renders {
		if !takesString[dir] || escapes[dir] {
			continue
		}
		ignored, err := moduleIgnored(filepath.Join(root, filepath.FromSlash(dir), "gnomod.toml"))
		if err != nil {
			return err
		}
		if ignored {
			continue
		}
		if baseline[dir] {
			continue
		}
		if why, ok := optOut[dir]; ok {
			if len(why) < minUntrustedReason {
				thin = append(thin, fmt.Sprintf("%s (reason is %d chars, need %d): %s",
					dir, len(why), minUntrustedReason, why))
			}
			continue
		}
		bad = append(bad, dir)
	}
	// A baseline entry that no longer describes the tree is worse than no
	// baseline: it silences a realm that has since been fixed, or one that no
	// longer exists, and nobody notices until the next miss hides behind it.
	for dir := range baseline {
		if !renders[dir] || !takesString[dir] || escapes[dir] {
			stale = append(stale, dir)
		}
	}
	if len(stale) > 0 {
		sort.Strings(stale)
		return failf("guard-untrusted-render FAIL — baseline entries that no longer apply", stale,
			"Each of these either escapes now, no longer renders a caller's string, or is gone.\n"+
				"Delete the line from tools/gnocontracts/untrusted-render-baseline.txt.")
	}
	if len(thin) > 0 {
		sort.Strings(thin)
		return failf("guard-untrusted-render FAIL — opt-out reasons that answer nothing", thin,
			"Name the validation that makes escaping unnecessary, e.g.\n"+
				"// untrusted-render: every stored word is checked against the a-z charset at write time")
	}
	if len(bad) > 0 {
		sort.Strings(bad)
		return failf("guard-untrusted-render FAIL — realms that render a caller's string raw", bad,
			"Wrap it once, at the call site that builds the markdown:\n"+
				"  ui.Inline(s)  a sentence, a list item, a link title\n"+
				"  ui.Cell(s)    a table cell, which must not open a new column\n"+
				"Or, if every stored string is validated at write time, say so in the file:\n"+
				"  // untrusted-render: <what validates it>\n"+
				"A live realm cannot be fixed in place: a public path is immutable, so this\n"+
				"is a pre-deploy gate and a miss ships forever.")
	}
	fmt.Printf("guard-untrusted-render: every realm that renders a caller's string escapes it (%d grandfathered)\n", len(baseline))
	return nil
}

// readUntrustedBaseline loads the grandfathered realms. A missing file is an
// empty baseline rather than an error: the guard is meaningful without one, and
// a repo that has no legacy should not need to carry an empty file.
func readUntrustedBaseline(root string) (map[string]bool, error) {
	b, err := os.ReadFile(filepath.Join(root, "tools", "gnocontracts", "untrusted-render-baseline.txt"))
	if err != nil {
		if os.IsNotExist(err) {
			return map[string]bool{}, nil
		}
		return nil, err
	}
	out := map[string]bool{}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		out[line] = true
	}
	return out, nil
}

// isExportedName reports whether a Go identifier is exported.
func isExportedName(s string) bool {
	return s != "" && s[0] >= 'A' && s[0] <= 'Z'
}

// storesCallerString reports whether the parameter list opening at toks[open]
// is a crossing function that takes a string: `(cur realm, ..., s string)`.
//
// Both halves matter. `string` alone is every getter and every Render. `cur
// realm` alone is every state change. Together they are the shape that puts a
// caller's text into realm state, which is the only text a later Render can
// echo back at a reader.
//
// The list is read to its matching `)` and no further, so a function that
// merely RETURNS a string does not count: a realm hands its own strings out
// constantly, and only the ones it takes in are the caller's.
func storesCallerString(toks []gnoTok, open int) bool {
	depth, crossing, str := 0, false, false
	for i := open; i < len(toks); i++ {
		switch toks[i].tok {
		case token.LPAREN:
			depth++
		case token.RPAREN:
			depth--
			if depth == 0 {
				return crossing && str
			}
		case token.IDENT:
			switch toks[i].lit {
			case "string":
				str = true
			case "realm":
				crossing = true
			}
		}
	}
	return false
}

// isSanitizerCall reports whether toks[i] starts `<pkg>.<Func>(` where pkg is
// one of sanitizers and Func one of sanitizerFuncs.
func isSanitizerCall(toks []gnoTok, i int) bool {
	if i+3 >= len(toks) {
		return false
	}
	if !isSanitizerPkg(toks[i].lit) {
		return false
	}
	return toks[i+1].tok == token.PERIOD &&
		toks[i+2].tok == token.IDENT && sanitizerFuncs[toks[i+2].lit] &&
		toks[i+3].tok == token.LPAREN
}

func isSanitizerPkg(s string) bool {
	ss := sanitizers
	for _, x := range ss {
		if x == s {
			return true
		}
	}
	return false
}
