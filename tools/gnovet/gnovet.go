// Package gnovet is this repository's own linter for gno contracts, and its
// defining property is where the rules come from.
//
// Every rule here was a FINDING FIRST. Something, usually a paid code review,
// noticed a real defect in real code in this repository; the defect was fixed;
// and then the shape of it was written down as a rule so that the next instance
// is caught for free, forever, by a binary that cannot forget and cannot be
// talked out of it. A rule with no Finding is not allowed (see Rule.Finding and
// the test that enforces it).
//
// That is the whole design. A code review costs ~76 AI credits (measured
// 2026-10-01; tools/gnocontracts/review_advice.go owns the figure) and finds a
// defect once. A rule costs nothing and finds it every time. The loop is:
//
//	review finds it  ->  fix it  ->  write the rule  ->  never pay for it again
//
// Three consequences worth stating, because they are what keeps this honest:
//
//   - A rule carries its provenance in the source. `Finding` names the pull
//     request and the review comment it came from, so anyone can read the
//     original argument rather than take the rule on faith, and a rule that
//     turns out to be wrong can be traced back to the reasoning that produced
//     it.
//   - Every rule ships a `Bad` and a `Good` fixture, and the test suite asserts
//     the rule fires on the first and is silent on the second. That is the
//     upstream audit-pattern harness's discipline, and it is the only thing
//     that stops a rule from quietly matching nothing after a refactor.
//   - Nothing here is gno-contracts specific. The engine takes a directory and
//     the rules read source text, so if this becomes useful to anybody else it
//     lifts out as a module without a rewrite. That is deliberate but it is not
//     yet a promise: these rules were learned from one repository's mistakes.
//
// It is a RATCHET over a baseline, like every other guard here, because the
// tree predates the rules.
package gnovet

import (
	"fmt"
	"go/scanner"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Rule is one thing worth catching, and the record of why anyone knows it.
type Rule struct {
	// ID is the stable name used in the baseline and in a nolint comment.
	ID string

	// What it catches, in one line, present tense.
	What string

	// Why it matters, in gno terms, on this chain. Not "this is bad style".
	Why string

	// Fix is the smallest thing that makes it go away.
	Fix string

	// Finding is where this came from: the pull request, the review, and the
	// date. REQUIRED. A rule nobody can trace is a rule nobody can argue with,
	// and TestEveryRuleCitesItsFinding fails without it.
	Finding string

	// Bad fires the rule, Good does not. Both are checked by the test suite.
	Bad, Good string

	// Check reports the 0-based line indices that violate the rule.
	//
	// It is given three views of the file. Use Code for anything matching
	// EXPRESSIONS: comments and string contents are blanked there, so a rule
	// looking for append( does not match a doc comment explaining the rule,
	// which is the trap a regexp over raw source falls into in a repository
	// whose comments discuss its own lints. Use Literal for what lives in a
	// string (a rendered link): comments are blanked there, strings kept. Use
	// Raw only for import paths.
	Check func(f File) []int
}

// File is one source file in three views.
type File struct {
	// Code has comments and string contents blanked to spaces, line numbers
	// preserved.
	Code []string
	// Literal has comments blanked and string contents KEPT, line numbers
	// preserved: what a rule about a rendered string matches, so that a doc
	// comment quoting the bad string does not fire it.
	Literal []string
	// Raw is the file as written.
	Raw []string
}

// Hit is one violation.
type Hit struct {
	Rule string
	File string
	Line int // 1-based
	Text string
}

// nolintRe is the opt-out, read from the line itself or the line above:
//
//	//gnovet:ignore <rule-id> <why>
//
// The reason is required and has a floor, for the same reason every other
// opt-out here does: "n/a" answers nothing.
const nolintPrefix = "//gnovet:ignore"

// MinIgnoreReason is the floor on an ignore reason, in characters.
const MinIgnoreReason = 20

// Run applies every rule to every non-test .gno file under dir.
func Run(dir string) ([]Hit, error) {
	return RunRules(dir, Rules)
}

// RunRules is [Run] with an explicit rule set, which is what the tests use.
func RunRules(dir string, rules []Rule) ([]Hit, error) {
	files, err := gnoFiles(dir)
	if err != nil {
		return nil, err
	}
	var hits []Hit
	for _, f := range files {
		src, err := os.ReadFile(f)
		if err != nil {
			return nil, err
		}
		code, literal, raw := codeLines(src)
		view := File{Code: code, Literal: literal, Raw: raw}
		rel, _ := filepath.Rel(dir, f)
		for _, r := range rules {
			for _, i := range r.Check(view) {
				if ignored(raw, i, r.ID) {
					continue
				}
				hits = append(hits, Hit{
					Rule: r.ID,
					File: filepath.ToSlash(rel),
					Line: i + 1,
					Text: strings.TrimSpace(raw[i]),
				})
			}
		}
	}
	sort.Slice(hits, func(i, j int) bool {
		if hits[i].File != hits[j].File {
			return hits[i].File < hits[j].File
		}
		if hits[i].Line != hits[j].Line {
			return hits[i].Line < hits[j].Line
		}
		return hits[i].Rule < hits[j].Rule
	})
	return hits, nil
}

// ignored reports whether line i opts out of rule, on the line itself or the
// line above it, with a reason long enough to mean something.
func ignored(raw []string, i int, rule string) bool {
	for _, n := range []int{i, i - 1} {
		if n < 0 || n >= len(raw) {
			continue
		}
		idx := strings.Index(raw[n], nolintPrefix)
		if idx < 0 {
			continue
		}
		rest := strings.TrimSpace(raw[n][idx+len(nolintPrefix):])
		if !strings.HasPrefix(rest, rule) {
			continue
		}
		why := strings.TrimSpace(strings.TrimPrefix(rest, rule))
		if len(why) >= MinIgnoreReason {
			return true
		}
	}
	return false
}

// ByID returns a rule by its ID.
func ByID(id string) (Rule, bool) {
	for _, r := range Rules {
		if r.ID == id {
			return r, true
		}
	}
	return Rule{}, false
}

// codeLines returns the file three times: with comments and string CONTENTS
// blanked, which is what most rules match against; with only comments blanked,
// for a rule about what a string says; and raw, for the message and the ignore
// comment.
//
// Blanking is why a rule can look for "append(" without matching the word in a
// doc comment that explains the rule, which is exactly the trap a regexp over
// raw source falls into in a repository whose comments discuss its own lints.
func codeLines(src []byte) (code, literal, raw []string) {
	raw = strings.Split(string(src), "\n")
	blanked := append([]byte(nil), src...)
	uncommented := append([]byte(nil), src...)

	fset := token.NewFileSet()
	f := fset.AddFile("", fset.Base(), len(src))
	var s scanner.Scanner
	s.Init(f, src, func(token.Position, string) {}, scanner.ScanComments)
	for {
		pos, tok, lit := s.Scan()
		if tok == token.EOF {
			break
		}
		if tok != token.COMMENT && tok != token.STRING && tok != token.CHAR {
			continue
		}
		off := f.Offset(pos)
		for j := off; j < off+len(lit) && j < len(blanked); j++ {
			if blanked[j] != '\n' {
				blanked[j] = ' '
				if tok == token.COMMENT {
					uncommented[j] = ' '
				}
			}
		}
	}
	return strings.Split(string(blanked), "\n"), strings.Split(string(uncommented), "\n"), raw
}

// gnoFiles lists the non-test .gno files under dir, in a stable order.
func gnoFiles(dir string) ([]string, error) {
	var out []string
	err := filepath.WalkDir(dir, func(p string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		name := d.Name()
		if !strings.HasSuffix(name, ".gno") ||
			strings.HasSuffix(name, "_test.gno") ||
			strings.HasSuffix(name, "filetest.gno") {
			return nil
		}
		out = append(out, p)
		return nil
	})
	sort.Strings(out)
	return out, err
}

// Describe renders a rule for a failure message.
func (r Rule) Describe() string {
	return fmt.Sprintf("%s: %s\n  why: %s\n  fix: %s\n  from: %s",
		r.ID, r.What, r.Why, r.Fix, r.Finding)
}
