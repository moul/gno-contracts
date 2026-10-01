package gnovet

import (
	"regexp"
	"strings"
)

// Rules is every rule, each one a finding that happened before it was a rule.
//
// To add one: fix the defect first, then write the rule with the pull request
// and review comment in Finding, a Bad that fires and a Good that does not, and
// run `make gnovet-update`. The test suite refuses a rule missing any of those.
var Rules = []Rule{
	sliceInPlaceRemove,
	ceilDivOverflow,
	avlInNewCode,
	pageOffsetOverflow,
	placeholderPath,
}

// ---------------------------------------------------------------------------

// sliceRemoveRe matches the idiomatic Go element removal, append(s[:i],
// s[i+1:]...), in any spacing. The two slice expressions must name the same
// identifier, which the regexp enforces with a backreference-free trick: it
// captures both and the Check compares them.
var sliceRemoveRe = regexp.MustCompile(`append\(\s*([A-Za-z_]\w*(?:\.\w+)*)\s*\[\s*:[^\]]*\]\s*,\s*([A-Za-z_]\w*(?:\.\w+)*)\s*\[[^\]]*:\s*\]\s*\.\.\.\s*\)`)

var sliceInPlaceRemove = Rule{
	ID:   "slice-inplace-remove",
	What: "removes an element with append(s[:i], s[i+1:]...), which frees no storage",
	Why: "A slice is ONE persisted object and the storage deposit comes back when that " +
		"object is dropped, at no other time. Shortening in place keeps the peak allocation " +
		"charged: a bucket that grew to 1,000 entries and shrank to 1 still pays for 1,000. " +
		"Measured: removing every element one by one costs 22.5M extra gas and ends 216 bytes " +
		"HEAVIER than never deleting anything.",
	Fix: "Allocate a fresh slice of the exact size and copy into it, which drops the old " +
		"array. Same O(n) as the memmove it replaces, and it actually refunds.",
	Finding: "gno-contracts#289, Copilot review comment 4154919649, 2026-10-01",
	Bad:     "package x\n\nfunc f() {\n\te.ids = append(e.ids[:pos], e.ids[pos+1:]...)\n}\n",
	Good: "package x\n\nfunc f() {\n\tt := make([]int, 0, len(e.ids)-1)\n\t" +
		"t = append(t, e.ids[:pos]...)\n\tt = append(t, e.ids[pos+1:]...)\n}\n",
	Check: func(f File) []int {
		var out []int
		for i, ln := range f.Code {
			for _, m := range sliceRemoveRe.FindAllStringSubmatch(ln, -1) {
				if m[1] == m[2] {
					out = append(out, i)
					break
				}
			}
		}
		return out
	},
}

// ---------------------------------------------------------------------------

// ceilDivRe matches the ceiling-division idiom (a + b - 1) / b, which overflows
// when b is near the integer limit. The divisor must be the same identifier the
// numerator added, which Check compares.
var ceilDivRe = regexp.MustCompile(`\(\s*[A-Za-z_]\w*\s*\+\s*([A-Za-z_]\w*)\s*-\s*1\s*\)\s*/\s*([A-Za-z_]\w*)`)

var ceilDivOverflow = Rule{
	ID:   "ceil-div-overflow",
	What: "computes a ceiling as (n + size - 1) / size, which wraps at the integer limit",
	Why: "With n = 2 and size = maxInt the addition wraps negative and the division " +
		"returns 0, so a function documented to return 'at least 1' returns zero and the " +
		"page picker that divides by it panics. The result cannot overflow; the way of " +
		"computing it can.",
	Fix:     "1 + (n-1)/size, guarded on n == 0, which cannot overflow.",
	Finding: "gno-contracts#289, Copilot review comment 4154919727, 2026-10-01",
	Bad:     "package x\n\nfunc f(n, size int) int {\n\treturn (n + size - 1) / size\n}\n",
	Good:    "package x\n\nfunc f(n, size int) int {\n\tif n == 0 {\n\t\treturn 1\n\t}\n\treturn 1 + (n-1)/size\n}\n",
	Check: func(f File) []int {
		var out []int
		for i, ln := range f.Code {
			for _, m := range ceilDivRe.FindAllStringSubmatch(ln, -1) {
				if m[1] == m[2] {
					out = append(out, i)
					break
				}
			}
		}
		return out
	},
}

// ---------------------------------------------------------------------------

var avlInNewCode = Rule{
	ID:   "avl-in-new-code",
	What: "imports p/nt/avl, which is dominated on every axis measured",
	Why: "At n = 1,000 with string values: avl costs 2,029 bytes per entry against a " +
		"bptree-at-fanout-128's 592 and a native map's 153, 418k gas per insert against " +
		"153k, and 47k gas per entry iterated against 8k. 100,000 entries in an avl locks " +
		"20,290 GNOT of storage deposit; in a map, 1,530. It is the ecosystem default and " +
		"it should not be.",
	Fix: "A native gno map when nothing navigates it by key order (gno maps iterate " +
		"deterministically, in insertion order), or p/nt/bptree at fanout 128 when " +
		"something does. EFFECTIVE_GNO.md sections 2.3 to 2.5.",
	Finding: "EFFECTIVE_GNO.md section 2.3 (gno-contracts#270), from the storage benchmark " +
		"of 2026-09-29 against gno master 1fc4c140e; promoted to a rule 2026-10-01",
	Bad:  "package x\n\nimport \"gno.land/p/nt/avl/v0\"\n\nvar t = avl.NewTree()\n",
	Good: "package x\n\nimport \"gno.land/p/nt/bptree/v0\"\n\nvar t = bptree.NewBPTreeN(128)\n",
	// Raw, not Code: an import path IS a string literal, so the blanked view
	// has nothing to match. This is the one rule that legitimately reads Raw,
	// and it is narrow enough that a mention in prose cannot reach it: the line
	// has to be an import.
	Check: func(f File) []int {
		var out []int
		inBlock := false
		for i, ln := range f.Raw {
			t := strings.TrimSpace(ln)
			switch {
			case strings.HasPrefix(t, "import ("):
				inBlock = true
				continue
			case inBlock && t == ")":
				inBlock = false
				continue
			case !inBlock && !strings.HasPrefix(t, "import "):
				continue
			}
			if strings.Contains(t, `"gno.land/p/nt/avl/`) {
				out = append(out, i)
			}
		}
		return out
	},
}

// ---------------------------------------------------------------------------

// pageOffsetRe matches (page - 1) * size, the offset of a 1-based page. Check
// keeps only the matches whose first operand is named like a page number, so
// (floor-1)*2 in an ASCII tree does not fire.
var pageOffsetRe = regexp.MustCompile(`\(\s*([A-Za-z_]\w*)\s*-\s*1\s*\)\s*\*\s*[A-Za-z_]\w*`)

var pageNameRe = regexp.MustCompile(`(?i)^(p|pg|pn|n?page\w*|\w*page)$`)

var pageOffsetOverflow = Rule{
	ID:   "page-offset-overflow",
	What: "computes a page offset as (page - 1) * size, which wraps for a page past the end",
	Why: "The page number arrives from a Render path or a call argument, so it reaches " +
		"maxInt for free. (page-1)*size then wraps negative, and the iterators clamp a " +
		"negative offset to 0: ?page=9223372036854775807 silently returns page 1 instead " +
		"of nothing. Found by review twice, in two different packages, on the same day.",
	Fix: "Bound the page first, on a quantity that cannot overflow: " +
		"if page < 1 || page-1 > (total-1)/size { return nothing }, then multiply. " +
		"Where a bound already precedes it, say so with //gnovet:ignore.",
	Finding: "gno-contracts#289, Copilot review comment 4154919693, 2026-10-01; " +
		"the same defect again in gno-contracts#311 (\"Overflowing page numbers " +
		"incorrectly reset to page 1\"), 2026-10-01",
	Bad: "package x\n\nfunc f(page, size int) int {\n\treturn (page - 1) * size\n}\n",
	Good: "package x\n\nfunc f(page, size, total int) int {\n\t" +
		"if page < 1 || page-1 > (total-1)/size {\n\t\treturn -1\n\t}\n\t" +
		"return size * (page - 1)\n}\n",
	Check: func(f File) []int {
		var out []int
		for i, ln := range f.Code {
			for _, m := range pageOffsetRe.FindAllStringSubmatch(ln, -1) {
				if pageNameRe.MatchString(m[1]) {
					out = append(out, i)
					break
				}
			}
		}
		return out
	},
}

// ---------------------------------------------------------------------------

// placeholderRe matches a generator template's unsubstituted placeholder.
var placeholderRe = regexp.MustCompile(`\bREPLACE_[A-Z][A-Z0-9_]*\b`)

var placeholderPath = Rule{
	ID:   "placeholder-path",
	What: "ships a template placeholder (REPLACE_ADDR) inside a string the realm renders",
	Why: "A placeholder in a rendered link is a dead link on a permanent path: the " +
		"realm is live, the page cannot be edited, and every visitor clicks through to " +
		"/r/REPLACE_ADDR/... Three realms shipped exactly this from one code generator, " +
		"and a test pinning the Render output pinned the dead link along with it.",
	Fix: "The realm's own absolute path (/r/moul/x/daily/<name>/v0), written out, or a " +
		"constant derived from it. Never a token a generator was meant to replace.",
	Finding: "r/moul/x/daily/{linktree,polls,blog}, shipped by the generated corpus of " +
		"gno-contracts#20 and found live on mainnet by a tree-wide link sweep, " +
		"2026-09-30; confirmed by the agent review sweep of 2026-10-01",
	Bad:  "package x\n\nfunc Render(string) string {\n\treturn \"[back](/r/REPLACE_ADDR/blog)\"\n}\n",
	Good: "package x\n\n// Render once read [back](/r/REPLACE_ADDR/blog).\nfunc Render(string) string {\n\treturn \"[back](/r/moul/x/daily/blog/v0)\"\n}\n",
	// Literal, not Code: the placeholder IS string content, which Code blanks;
	// Literal still blanks comments, so the Good above (a comment quoting the
	// old link) stays silent.
	Check: func(f File) []int {
		var out []int
		for i, ln := range f.Literal {
			if placeholderRe.MatchString(ln) {
				out = append(out, i)
			}
		}
		return out
	},
}
