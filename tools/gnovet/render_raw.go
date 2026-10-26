package gnovet

import (
	"regexp"
	"sort"
	"strings"
)

// RenderPathRaw is the detector behind the render_markdown_escape audit
// family, and it is exported rather than listed in [Rules] on purpose.
//
// The family is upstream's: tools/auditpattern mirrors its scanner byte for
// byte, and that scanner flags a line in Render that says `return` and `path`
// and not the word `escape`. On this tree it was wrong 45 times out of 45 (34
// dispatch lines like `return renderCase(parseID(path))`, 11 that already
// escaped through md.InlineCode or ui.Inline) and blind to the one real case,
// a heading built from the path with WriteString (gno-contracts#359). The
// mirror is not ours to edit, so `gnocontracts audit-patterns` runs this in
// that family's slot instead, and its debt stays in that family's baseline.
// The real fix is the same detector upstream.
//
// What it asks is EFFECTIVE_GNO.md section 3.3: does a value derived from
// Render's path reach markdown without going through an escaper? It does not
// keep a list of escapers. Any call that is not a known pass-through (trim,
// split, a local helper that hands the string back) ends the trail, which is
// generous on purpose: soundex.Normalize(q) is not an escaper, but a lexical
// tool cannot tell, and a guard that demands a rename to pass is the defect
// this one replaces.
var RenderPathRaw = Rule{
	ID:   "render-path-raw",
	What: "writes a value derived from Render's path argument into markdown without escaping it",
	Why: "The path is whatever the visitor typed into the URL. Written raw, it is markdown the " +
		"realm appears to have authored: a link, an image, a heading, a table that breaks its " +
		"own column, on a page that looks first-party. A public path is immutable, so a realm " +
		"that ships it keeps it.",
	Fix: "Wrap it once where the markdown is built: ui.Inline for a sentence or a heading, " +
		"ui.Cell for a table cell, md.InlineCode for a code span. Where the value is validated " +
		"before it gets there, say so with //gnovet:ignore render-path-raw <why>.",
	Finding: "gno-contracts#359, 2026-10-26: r/moul/x/daily/soundexdemo writes parseArg(path) " +
		"into a heading, and the mirrored render_markdown_escape rule could not see it",
	Bad: "package x\n\nfunc Render(path string) string {\n\tvar b strings.Builder\n\t" +
		"if q := parseArg(path); q != \"\" {\n\t\tb.WriteString(\"## \")\n\t\tb.WriteString(q)\n\t}\n\t" +
		"return b.String()\n}\n\nfunc parseArg(path string) string {\n\t" +
		"s := strings.TrimPrefix(path, \"/\")\n\treturn s\n}\n",
	Good: "package x\n\nfunc Render(path string) string {\n\tif path != \"\" {\n\t\t" +
		"v := pools.Get(path)\n\t\tif v == nil {\n\t\t\t" +
		"return \"# 404\\n\\nNo pool \" + md.InlineCode(path) + \".\\n\"\n\t\t}\n\t\t" +
		"return renderPool(v)\n\t}\n\treturn renderCase(parseID(path))\n}\n",
	Check: renderPathRawLines,
}

var (
	// rawSinkCallRe opens a call whose arguments end up in the page as
	// written. md.Link and md.InlineCode are absent because they escape;
	// md.Link's url goes through sanitize.URL.
	rawSinkCallRe = regexp.MustCompile(`(?:\.WriteString|\bSprintf|\bmd\.(?:Bold|Italic|Strikethrough|H[1-6]|BulletItem|TodoItem|Blockquote|Paragraph|CollapsibleSection))\s*\(`)
	// stmtAssignRe is assignRe that also reads `if q := …;` and `for _, x := range …`.
	stmtAssignRe = regexp.MustCompile(`^\s*(?:if\s+|for\s+|switch\s+)?(\w+(?:\s*,\s*\w+)*)\s*:?=\s*(?:range\s+)?([^;]+)`)
	stringFuncRe = regexp.MustCompile(`^\s*func\s+(\w+)\s*\([^)]*\)\s*string\s*\{`)
	returnRe     = regexp.MustCompile(`^\s*return\s+(.+)$`)
	appendAsgRe  = regexp.MustCompile(`^\s*\w+(?:\.\w+)*\s*\+=\s*(.+)$`)
	callOpenRe   = regexp.MustCompile(`([A-Za-z_]\w*)\s*\($`)
)

// rawPass is the pass-through set for this rule: passThrough without Get. A
// lookup keyed by the path (duels.Get(id)) returns what the realm stored, and
// counting it made every field of every stored record look like the path.
var rawPass = func() map[string]bool {
	m := map[string]bool{}
	for k := range passThrough {
		if k != "Get" {
			m[k] = true
		}
	}
	return m
}()

// rawFunc is one top-level func: its name, its parameter names, the lines of
// its body, and what is tainted inside it.
type rawFunc struct {
	name     string
	params   []string
	from, to int // the declaration line and the closing brace, inclusive
	taint    map[string]bool
}

// rawFuncs splits a gofmt'd file into its top-level funcs: a `func` at column
// 0 opens one and a `}` at column 0 closes it.
func rawFuncs(code []string) []*rawFunc {
	var out []*rawFunc
	for i := 0; i < len(code); i++ {
		if !strings.HasPrefix(code[i], "func ") {
			continue
		}
		fn := &rawFunc{from: i, to: i, taint: map[string]bool{}}
		if m := funcDeclRe.FindStringSubmatch(code[i]); m != nil {
			fn.name = m[1]
			for _, p := range strings.Split(m[2], ",") {
				if fl := strings.Fields(p); len(fl) > 0 {
					fn.params = append(fn.params, fl[0])
				} else {
					fn.params = append(fn.params, "")
				}
			}
		}
		if m := renderFuncRe.FindStringSubmatch(code[i]); m != nil {
			fn.taint[m[1]] = true
		}
		if !strings.HasSuffix(strings.TrimSpace(code[i]), "}") {
			for j := i + 1; j < len(code); j++ {
				if strings.HasPrefix(code[j], "}") {
					fn.to = j
					break
				}
			}
		}
		out = append(out, fn)
		i = fn.to
	}
	return out
}

// renderPathRawLines is the Check. It takes the taint idea of
// render-path-in-code-span and scopes it to a function: a name is tainted in
// the func that derived it, not everywhere the same short name (s, id, key)
// appears in the file. Taint crosses a call into a local func's parameter, and
// back out of a local func returning string that hands it back (parseArg).
func renderPathRawLines(f File) []int {
	code := f.Code
	funcs := rawFuncs(code)
	local := rawTaint(code, funcs)

	seen := map[int]bool{}
	var out []int
	add := func(i int) {
		if !seen[i] {
			seen[i] = true
			out = append(out, i)
		}
	}
	for _, fn := range funcs {
		if len(fn.taint) == 0 {
			continue
		}
		bare := func(expr string) bool { return hasBareTainted(stripCalls(expr, local), fn.taint) }

		// Calls: joined, because a Sprintf's arguments wrap.
		joined := strings.Join(code[fn.from:fn.to+1], "\n")
		for _, m := range rawSinkCallRe.FindAllStringIndex(joined, -1) {
			open := m[1] - 1
			end := matchParen(joined, open)
			if end < 0 {
				continue
			}
			if bare(joined[open+1 : end]) {
				add(fn.from + strings.Count(joined[:open], "\n"))
			}
		}

		// Concatenation with a string literal, returned or appended: that
		// string is the page, or a piece of it. A plain assignment is not a
		// sink, only a step: the write that follows it is. Render returning
		// the bare value is one too, concatenation or not. Literal is read
		// only to know a quote is there; Code is what gets matched.
		isRender := renderFuncRe.MatchString(code[fn.from])
		for i := fn.from + 1; i <= fn.to; i++ {
			ln := code[i]
			var expr string
			if m := returnRe.FindStringSubmatch(ln); m != nil {
				expr = m[1]
			} else if m := appendAsgRe.FindStringSubmatch(ln); m != nil {
				expr = m[1]
			} else {
				continue
			}
			lit := f.Literal[i]
			concat := strings.Contains(expr, "+") && (strings.Contains(lit, `"`) || strings.Contains(lit, "`"))
			if (concat || isRender) && bare(expr) {
				add(i)
			}
		}
	}
	sort.Ints(out)
	return out
}

// rawTaint runs the per-func taint to a fixed point and returns the local
// funcs that hand a tainted string back to their caller.
func rawTaint(code []string, funcs []*rawFunc) map[string]bool {
	byName := map[string]*rawFunc{}
	for _, fn := range funcs {
		if fn.name != "" {
			byName[fn.name] = fn
		}
	}
	local := map[string]bool{}
	for changed := true; changed; {
		changed = false
		for _, fn := range funcs {
			if len(fn.taint) == 0 {
				continue
			}
			mentions := func(expr string) bool { return hasBareTainted(stripCalls(expr, local), fn.taint) }
			returnsString := stringFuncRe.MatchString(code[fn.from])
			for i := fn.from; i <= fn.to; i++ {
				ln := code[i]
				if i > fn.from {
					if m := stmtAssignRe.FindStringSubmatch(ln); m != nil && mentions(m[2]) {
						for _, id := range identRe.FindAllString(m[1], -1) {
							if id != "_" && !fn.taint[id] {
								fn.taint[id], changed = true, true
							}
						}
					}
					// A hand-back, not a builder: `return s`, never
					// `return "# " + s`, or every render helper would pass
					// taint into its caller and one flow would report twice.
					if returnsString && !local[fn.name] {
						if m := returnRe.FindStringSubmatch(ln); m != nil &&
							!strings.Contains(m[1], "+") && mentions(m[1]) {
							local[fn.name], changed = true, true
						}
					}
				}
				for _, c := range callRe.FindAllStringSubmatch(ln, -1) {
					callee, ok := byName[c[1]]
					if !ok || callee == fn {
						continue
					}
					for k, a := range strings.Split(c[2], ",") {
						if k < len(callee.params) && callee.params[k] != "" &&
							!callee.taint[callee.params[k]] && mentions(a) {
							callee.taint[callee.params[k]], changed = true, true
						}
					}
				}
			}
		}
	}
	return local
}

// stripCalls blanks what a value cannot carry raw out of an expression: the
// whole of any call that is not a pass-through, and the inside of an index
// (byKey[q] is the realm's data, not q). A pass-through call keeps its
// arguments, so strings.TrimPrefix(path, "/") still shows path.
func stripCalls(expr string, local map[string]bool) string {
	b := []byte(expr)
	for i := 0; i < len(b); i++ {
		switch b[i] {
		case '(':
			end := matchParen(string(b), i)
			if end < 0 {
				return string(b)
			}
			m := callOpenRe.FindStringSubmatch(string(b[:i+1]))
			if m == nil || rawPass[m[1]] || local[m[1]] {
				continue // grouping parens or a pass-through: look inside
			}
			start := i - len(m[0]) + 1
			for j := start; j <= end; j++ {
				b[j] = ' '
			}
			i = end
		case '[':
			end := matchBracket(string(b), i)
			if end < 0 {
				return string(b)
			}
			for j := i + 1; j < end; j++ {
				b[j] = ' '
			}
			i = end
		}
	}
	return string(b)
}

// hasBareTainted reports a tainted identifier that is a value of its own, not
// the member half of a selector (c.path is a field, not the variable path).
func hasBareTainted(expr string, t map[string]bool) bool {
	for _, loc := range identRe.FindAllStringIndex(expr, -1) {
		if !t[expr[loc[0]:loc[1]]] {
			continue
		}
		if p := strings.TrimRight(expr[:loc[0]], " \t"); strings.HasSuffix(p, ".") {
			continue
		}
		return true
	}
	return false
}

func matchParen(s string, open int) int   { return matchPair(s, open, '(', ')') }
func matchBracket(s string, open int) int { return matchPair(s, open, '[', ']') }

func matchPair(s string, open int, l, r byte) int {
	depth := 0
	for i := open; i < len(s); i++ {
		switch s[i] {
		case l:
			depth++
		case r:
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}
