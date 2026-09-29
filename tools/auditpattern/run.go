// Package auditpattern is a MIRROR of the scanning half of the upstream audit
// pattern harness, so this repository can run the same ten finding-family rules
// over its own contracts on every pull request.
//
// Source: gnolang/gno, misc/audit-pattern-harness/internal/auditpattern/run.go
// Commit: 132e9a0ece458c237e37df78eab532948a0ff9d6
// SHA256 of the whole upstream file: 89326f55d08e242f51f885c70f72a2716313d463f67330cb18e0996c04af6ccd
//
// It is a mirror and not an import because the upstream package is `internal/`
// inside a module of its own, so no amount of go.mod reaches it. The real fix is
// upstream: export the package. Until then `gnocontracts audit-patterns -drift
// <gnoroot>` re-hashes the upstream file and fails when it has moved, which is
// the only thing that keeps a copy honest.
//
// Dropped from the mirror: the fixture runner, the expected-record loader, the
// gno-test shell-out and the markdown report. Those belong to the harness's own
// job, which is proving the rules still fire on their fixtures. Kept: RunRule,
// the ten rule functions, and the go/scanner-based source reader they share, all
// of it byte for byte upstream's.
//
// Do not hand-edit below the imports. Re-mirror instead.

package auditpattern

import (
	"bytes"
	"fmt"
	"go/format"
	"go/scanner"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Rules is every rule RunRule accepts, in the order the upstream README lists
// them. It is this package's own, not upstream's: upstream enumerates them in
// its expected/ records, which the mirror does not carry.
var Rules = []string{
	"current_guard",
	"render_markdown_escape",
	"payment_user_call",
	"origin_caller_auth",
	"callback_param",
	"interface_realm_param",
	"exported_pointer_leak",
	"render_map_iteration",
	"unsafe_previous_realm",
	"pkg_mutable_pointer",
}

// UpstreamFile is the path, relative to a gnolang/gno checkout, that this file
// mirrors. UpstreamSHA256 is that file's digest at the mirrored commit.
const (
	UpstreamFile   = "misc/audit-pattern-harness/internal/auditpattern/run.go"
	UpstreamCommit = "132e9a0ece458c237e37df78eab532948a0ff9d6"
	UpstreamSHA256 = "89326f55d08e242f51f885c70f72a2716313d463f67330cb18e0996c04af6ccd"
)

var exportedPointerVarRE = regexp.MustCompile(`^var\s+[A-Z]\w*\s+\*`)
var exportedPointerFuncRE = regexp.MustCompile(`^func\s+([A-Z]\w*)\([^)]*\)\s+\*`)
var freshConstructorReturnRE = regexp.MustCompile(`return\s+&[A-Z]\w*\s*\{`)
var mapVarRE = regexp.MustCompile(`^(?:var\s+)?([A-Za-z_]\w*)\s*(?:=\s*)?map\[`)

// crossingFuncRE matches a crossing function declaration (top-level func or
// method) whose first parameter is the realm capability token `cur realm`.
var crossingFuncRE = regexp.MustCompile(`^func\s+(?:\([^)]*\)\s+)?\w+\(cur realm\b`)

// pkgMutablePointerTypeRE matches known /p/ types whose exported methods mutate
// the receiver, so a pointer to one is a live mutator handle. avl.Tree is the
// canonical example (Set/Remove/ReverseIterate); extend as more are documented.
var pkgMutablePointerTypeRE = `\*avl\.Tree\b`

// pkgMutableReturnRE matches an exported function returning a pointer to such a
// type (guide §5.1a). pkgMutableFieldRE matches an exported struct field or
// package var of that pointer type (guide §5.1b).
var pkgMutableReturnRE = regexp.MustCompile(`^func\s+(?:\([^)]*\)\s+)?[A-Z]\w*\([^)]*\)\s+` + pkgMutablePointerTypeRE)
var pkgMutableFieldRE = regexp.MustCompile(`^(?:var\s+)?[A-Z]\w*\s+` + pkgMutablePointerTypeRE)

type Hit struct {
	File string `json:"file"`
	Line int    `json:"line"`
	Text string `json:"text"`
}

func RunRule(rule, dir string) ([]Hit, error) {
	switch rule {
	case "current_guard":
		return currentGuardHits(dir)
	case "render_markdown_escape":
		return renderMarkdownEscapeHits(dir)
	case "payment_user_call":
		return paymentUserCallHits(dir)
	case "origin_caller_auth":
		return originCallerAuthHits(dir)
	case "callback_param":
		return callbackParamHits(dir)
	case "interface_realm_param":
		return interfaceRealmParamHits(dir)
	case "exported_pointer_leak":
		return exportedPointerLeakHits(dir)
	case "render_map_iteration":
		return renderMapIterationHits(dir)
	case "unsafe_previous_realm":
		return unsafePreviousRealmHits(dir)
	case "pkg_mutable_pointer":
		return pkgMutablePointerHits(dir)
	default:
		return nil, fmt.Errorf("unknown rule %q", rule)
	}
}

// unsafePreviousRealmHits flags any PreviousRealm() call in a file that also
// declares a crossing function (`func F(cur realm, ...)`). In a crossing
// function the caller must be derived from cur.Previous() under a
// cur.IsCurrent() guard; reaching for chain/runtime/unsafe.PreviousRealm()
// instead skips the frame check and ignores the cur token (guide §5.8).
func unsafePreviousRealmHits(dir string) ([]Hit, error) {
	files, err := gnoFiles(dir)
	if err != nil {
		return nil, err
	}

	var hits []Hit
	for _, file := range files {
		src, err := loadGnoSource(file)
		if err != nil {
			return nil, err
		}

		crossing := false
		for _, line := range src.code {
			if crossingFuncRE.MatchString(strings.TrimSpace(line)) {
				crossing = true
				break
			}
		}
		if !crossing {
			continue
		}

		for i, line := range src.code {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue
			}
			if strings.Contains(line, "PreviousRealm()") {
				hits = append(hits, src.hit(dir, file, i))
			}
		}
	}
	return hits, nil
}

// pkgMutablePointerHits flags a pointer to a /p/ type whose exported methods
// mutate the receiver (avl.Tree) exposed as an exported function return
// (guide §5.1a) or an exported struct field / package var (guide §5.1b).
// Readonly taint does not block method dispatch, so such a handle publishes
// the type's mutators under the realm's authority.
func pkgMutablePointerHits(dir string) ([]Hit, error) {
	files, err := gnoFiles(dir)
	if err != nil {
		return nil, err
	}

	var hits []Hit
	for _, file := range files {
		src, err := loadGnoSource(file)
		if err != nil {
			return nil, err
		}
		for i, line := range src.code {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue
			}
			if pkgMutableReturnRE.MatchString(trimmed) || pkgMutableFieldRE.MatchString(trimmed) {
				hits = append(hits, src.hit(dir, file, i))
			}
		}
	}
	return hits, nil
}

func currentGuardHits(dir string) ([]Hit, error) {
	files, err := gnoFiles(dir)
	if err != nil {
		return nil, err
	}

	var hits []Hit
	for _, file := range files {
		src, err := loadGnoSource(file)
		if err != nil {
			return nil, err
		}
		inFunc := false
		braceDepth := 0
		seenIsCurrent := false
		for i, line := range src.code {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "func ") {
				inFunc = true
				braceDepth = 0
				seenIsCurrent = false
			}
			if inFunc {
				braceDepth += strings.Count(line, "{")
				braceDepth -= strings.Count(line, "}")
			}
			if strings.Contains(line, ".IsCurrent()") {
				seenIsCurrent = true
			}
			if strings.Contains(line, ".Previous()") && !seenIsCurrent {
				hits = append(hits, src.hit(dir, file, i))
			}
			if inFunc && braceDepth <= 0 {
				inFunc = false
				seenIsCurrent = false
			}
		}
	}
	return hits, nil
}

func renderMarkdownEscapeHits(dir string) ([]Hit, error) {
	files, err := gnoFiles(dir)
	if err != nil {
		return nil, err
	}

	var hits []Hit
	for _, file := range files {
		src, err := loadGnoSource(file)
		if err != nil {
			return nil, err
		}
		inRender := false
		braceDepth := 0
		for i, line := range src.code {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "func Render(") {
				inRender = true
				braceDepth = 0
			}
			if inRender {
				braceDepth += strings.Count(line, "{")
				braceDepth -= strings.Count(line, "}")
				lower := strings.ToLower(line)
				if strings.Contains(line, "return") && strings.Contains(line, "path") && !strings.Contains(lower, "escape") {
					hits = append(hits, src.hit(dir, file, i))
				}
			}
			if inRender && braceDepth <= 0 {
				inRender = false
			}
		}
	}
	return hits, nil
}

func paymentUserCallHits(dir string) ([]Hit, error) {
	files, err := gnoFiles(dir)
	if err != nil {
		return nil, err
	}

	var hits []Hit
	for _, file := range files {
		src, err := loadGnoSource(file)
		if err != nil {
			return nil, err
		}
		inFunc := false
		braceDepth := 0
		seenUserCall := false
		for i, line := range src.code {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "func ") {
				inFunc = true
				braceDepth = 0
				seenUserCall = false
			}
			if inFunc {
				braceDepth += strings.Count(line, "{")
				braceDepth -= strings.Count(line, "}")
			}
			if strings.Contains(line, ".IsUserCall()") {
				seenUserCall = true
			}
			if strings.Contains(line, "OriginSend()") && !seenUserCall {
				hits = append(hits, src.hit(dir, file, i))
			}
			if inFunc && braceDepth <= 0 {
				inFunc = false
				seenUserCall = false
			}
		}
	}
	return hits, nil
}

func originCallerAuthHits(dir string) ([]Hit, error) {
	return lineContainsHits(dir, func(line string) bool {
		trimmed := strings.TrimSpace(line)
		return !strings.HasPrefix(trimmed, "//") &&
			strings.Contains(line, "OriginCaller()") &&
			!strings.Contains(line, "SetOriginCaller") &&
			(strings.Contains(line, "==") || strings.Contains(line, "!="))
	})
}

func callbackParamHits(dir string) ([]Hit, error) {
	// Use the original (non-trimmed) line so that function literals assigned
	// inside a body (which are always indented) are not matched as top-level
	// function declarations that accept callback parameters.
	return lineContainsHits(dir, func(line string) bool {
		return strings.HasPrefix(line, "func ") && strings.Contains(line, " func(")
	})
}

func interfaceRealmParamHits(dir string) ([]Hit, error) {
	files, err := gnoFiles(dir)
	if err != nil {
		return nil, err
	}

	var hits []Hit
	for _, file := range files {
		src, err := loadGnoSource(file)
		if err != nil {
			return nil, err
		}
		inInterface := false
		braceDepth := 0
		for i, line := range src.code {
			trimmed := strings.TrimSpace(line)
			if strings.Contains(trimmed, "interface {") {
				inInterface = true
				braceDepth = 0
			}
			if inInterface {
				braceDepth += strings.Count(line, "{")
				braceDepth -= strings.Count(line, "}")
				if strings.Contains(line, "realm") {
					hits = append(hits, src.hit(dir, file, i))
				}
			}
			if inInterface && braceDepth <= 0 {
				inInterface = false
			}
		}
	}
	return hits, nil
}

func exportedPointerLeakHits(dir string) ([]Hit, error) {
	files, err := gnoFiles(dir)
	if err != nil {
		return nil, err
	}

	var hits []Hit
	for _, file := range files {
		src, err := loadGnoSource(file)
		if err != nil {
			return nil, err
		}
		lines := src.code
		for i := range lines {
			line := lines[i]
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue
			}
			if exportedPointerVarRE.MatchString(trimmed) {
				hits = append(hits, src.hit(dir, file, i))
				continue
			}
			match := exportedPointerFuncRE.FindStringSubmatch(trimmed)
			if match == nil {
				continue
			}
			if strings.HasPrefix(match[1], "New") && returnsFreshPointer(lines[i:]) {
				continue
			}
			hits = append(hits, src.hit(dir, file, i))
		}
	}
	return hits, nil
}

func returnsFreshPointer(lines []string) bool {
	braceDepth := 0
	for i, line := range lines {
		braceDepth += strings.Count(line, "{")
		braceDepth -= strings.Count(line, "}")
		if freshConstructorReturnRE.MatchString(line) {
			return true
		}
		if i > 0 && braceDepth <= 0 {
			return false
		}
	}
	return false
}

func renderMapIterationHits(dir string) ([]Hit, error) {
	files, err := gnoFiles(dir)
	if err != nil {
		return nil, err
	}

	var hits []Hit
	for _, file := range files {
		src, err := loadGnoSource(file)
		if err != nil {
			return nil, err
		}

		mapRanges := make(map[string]*regexp.Regexp)
		for _, line := range src.code {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue
			}
			if match := mapVarRE.FindStringSubmatch(trimmed); match != nil {
				name := match[1]
				// Match "range <name>" only when <name> ends at a word
				// boundary, so a map "scores" does not flag "range scoresList"
				// (an unrelated slice).
				mapRanges[name] = regexp.MustCompile(`\brange\s+` + regexp.QuoteMeta(name) + `\b`)
			}
		}

		inRender := false
		braceDepth := 0
		for i, line := range src.code {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "func Render(") {
				inRender = true
				braceDepth = 0
			}
			if inRender {
				braceDepth += strings.Count(line, "{")
				braceDepth -= strings.Count(line, "}")
				if strings.Contains(line, "range ") {
					for _, re := range mapRanges {
						if re.MatchString(line) {
							hits = append(hits, src.hit(dir, file, i))
							break
						}
					}
				}
			}
			if inRender && braceDepth <= 0 {
				inRender = false
			}
		}
	}
	return hits, nil
}

func lineContainsHits(dir string, match func(string) bool) ([]Hit, error) {
	files, err := gnoFiles(dir)
	if err != nil {
		return nil, err
	}

	var hits []Hit
	for _, file := range files {
		src, err := loadGnoSource(file)
		if err != nil {
			return nil, err
		}
		for i, line := range src.code {
			if match(line) {
				hits = append(hits, src.hit(dir, file, i))
			}
		}
	}
	return hits, nil
}

func newHit(dir, file string, line int, text string) Hit {
	rel, err := filepath.Rel(dir, file)
	if err != nil {
		rel = file
	}
	return Hit{
		File: rel,
		Line: line,
		Text: strings.TrimSpace(text),
	}
}

// gnoSource is a .gno file prepared for line-based matching. Matchers scan
// code (the gofmt-normalized, literal/comment-blanked view) so irregular
// spacing and text inside strings/comments cannot defeat or fool them, but
// report hits against the original on-disk source via hit, so file:line and
// text always point at what the author actually wrote — even when the input
// was not gofmt-clean and formatting shifted line numbers.
type gnoSource struct {
	code   []string // gofmt-normalized + literal/comment-blanked, for matching
	orig   []string // raw on-disk lines, for reporting
	toOrig []int    // code line index -> orig line index (0-based)
}

// hit builds a Hit for a match on code line i, mapped back to the original
// source line and text.
func (s *gnoSource) hit(dir, file string, i int) Hit {
	o := i
	if i >= 0 && i < len(s.toOrig) {
		o = s.toOrig[i]
	}
	text := ""
	if o >= 0 && o < len(s.orig) {
		text = s.orig[o]
	}
	return newHit(dir, file, o+1, text)
}

// loadGnoSource reads a .gno file and prepares it for matching. It gofmt-
// normalizes the bytes so "func GetVault()*Vault{" becomes
// "func GetVault() *Vault {" before scanning (.gno uses Go syntax); if the
// source cannot be parsed (e.g. an intentionally broken fixture) the raw
// bytes are used unchanged. toOrig maps each normalized line back to the line
// it came from on disk so reported hits are never off by the formatter's line
// shifts.
func loadGnoSource(file string) (*gnoSource, error) {
	raw, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	formatted, err := format.Source(raw)
	if err != nil {
		formatted = raw
	}
	return &gnoSource{
		code:   codeLines(formatted),
		orig:   strings.Split(string(raw), "\n"),
		toOrig: lineMap(raw, formatted),
	}, nil
}

// lineMap returns, for each line of formatted, the 0-based index of the line
// in orig it originated from. gofmt only rewrites whitespace and comment
// layout — it never adds, drops, or reorders real tokens — so aligning the two
// token streams (ignoring the scanner's auto-inserted semicolons, whose count
// depends on line breaks) recovers the mapping even when formatting changed
// the line count. When orig and formatted are byte-identical (the common case:
// committed, gofmt-clean code) the map is the identity. If the streams cannot
// be aligned the last known original line is carried forward, which degrades
// to a best-effort nearby line rather than a wrong one.
func lineMap(orig, formatted []byte) []int {
	nf := strings.Count(string(formatted), "\n") + 1
	if bytes.Equal(orig, formatted) {
		m := make([]int, nf)
		for i := range m {
			m[i] = i
		}
		return m
	}
	origTokLines := tokenLines(orig)
	firstTok := firstTokenIndexByLine(formatted, nf)
	m := make([]int, nf)
	last := 0
	for f := range nf {
		if k := firstTok[f]; k >= 0 && k < len(origTokLines) {
			last = origTokLines[k]
		}
		m[f] = last
	}
	return m
}

// tokenLines returns the 0-based line of each real token in data, in scan
// order. The scanner's auto-inserted semicolons are skipped because their
// number depends on line breaks and would desynchronize the alignment.
func tokenLines(data []byte) []int {
	fset := token.NewFileSet()
	f := fset.AddFile("", fset.Base(), len(data))
	var s scanner.Scanner
	s.Init(f, data, nil, scanner.ScanComments)
	var lines []int
	for {
		pos, tok, _ := s.Scan()
		if tok == token.EOF {
			break
		}
		if tok == token.SEMICOLON {
			continue
		}
		lines = append(lines, fset.Position(pos).Line-1)
	}
	return lines
}

// firstTokenIndexByLine returns, for each of the nLines lines of data, the
// index (into the auto-semicolon-filtered token stream) of the first real
// token on that line, or -1 for lines with no token (blank/comment-shifted).
func firstTokenIndexByLine(data []byte, nLines int) []int {
	idx := make([]int, nLines)
	for i := range idx {
		idx[i] = -1
	}
	fset := token.NewFileSet()
	f := fset.AddFile("", fset.Base(), len(data))
	var s scanner.Scanner
	s.Init(f, data, nil, scanner.ScanComments)
	k := 0
	for {
		pos, tok, _ := s.Scan()
		if tok == token.EOF {
			break
		}
		if tok == token.SEMICOLON {
			continue
		}
		if line := fset.Position(pos).Line - 1; line >= 0 && line < nLines && idx[line] == -1 {
			idx[line] = k
		}
		k++
	}
	return idx
}

// codeLines splits gno source into lines with the contents of string/char
// literals and the bodies of comments blanked out (replaced with spaces),
// leaving delimiters and line structure intact. The line-based matchers run
// detection against this "code view" so that braces, keywords, or call
// expressions appearing inside a string or comment cannot fool them — e.g. a
// "}" in a string literal must not flip brace-depth tracking and turn a
// correctly guarded function into a false positive. Hits are still reported
// against the original source text. The returned slice has the same length as
// strings.Split(data, "\n").
func codeLines(data []byte) []string {
	blanked := append([]byte(nil), data...)
	fset := token.NewFileSet()
	file := fset.AddFile("", fset.Base(), len(data))
	var s scanner.Scanner
	s.Init(file, data, nil, scanner.ScanComments)
	for {
		pos, tok, lit := s.Scan()
		if tok == token.EOF {
			break
		}
		if tok != token.COMMENT && tok != token.STRING && tok != token.CHAR {
			continue
		}
		start := fset.Position(pos).Offset
		lo, hi := start, start+len(lit)
		if tok != token.COMMENT {
			lo, hi = start+1, hi-1 // preserve the surrounding quotes/backticks
		}
		for i := lo; i < hi && i < len(blanked); i++ {
			if blanked[i] != '\n' {
				blanked[i] = ' '
			}
		}
	}
	return strings.Split(string(blanked), "\n")
}

func gnoFiles(dir string) ([]string, error) {
	var files []string
	err := filepath.WalkDir(dir, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		if filepath.Ext(path) == ".gno" {
			files = append(files, path)
		}
		return nil
	})
	sort.Strings(files)
	return files, err
}
