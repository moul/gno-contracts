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
	rootRelativeLink,
	uncallableCrossingArg,
	originSendUnguarded,
	colonRelativeLink,
	escaperInCodeSpan,
	trimSpaceAsValidity,
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
		"deterministically, in insertion order), or p/nt/bptree when something does, at " +
		"fanout 128 if entries are only added and 32 if they are removed. EFFECTIVE_GNO.md " +
		"sections 2.3 to 2.5.",
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

// pageOffsetRe matches (page - 1) * size, the offset of a 1-based page, in
// either operand order. Check keeps only the matches whose decremented operand
// is named like a page number, so (floor-1)*2 in an ASCII tree does not fire.
var pageOffsetRe = regexp.MustCompile(`\(\s*([A-Za-z_]\w*)\s*-\s*1\s*\)\s*\*\s*[A-Za-z_]\w*|[A-Za-z_]\w*\s*\*\s*\(\s*([A-Za-z_]\w*)\s*-\s*1\s*\)`)

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
	Bad: "package x\n\nfunc f(page, size int) int {\n\treturn (page - 1) * size\n}\n\n" +
		"func g(pageNumber, size int) int {\n\treturn size * (pageNumber - 1)\n}\n",
	// The Good is silent because it SAYS it is bounded, not because it found a
	// spelling the regexp misses: the rule cannot see a bound, so a bounded
	// multiply carries the ignore, as p/moul/kit/index does.
	Good: "package x\n\nfunc f(page, size, total int) int {\n\t" +
		"if page < 1 || page-1 > (total-1)/size {\n\t\treturn -1\n\t}\n\t" +
		"//gnovet:ignore page-offset-overflow bounded by total on the line above\n\t" +
		"return size * (page - 1)\n}\n",
	Check: func(f File) []int {
		var out []int
		for i, ln := range f.Code {
			for _, m := range pageOffsetRe.FindAllStringSubmatch(ln, -1) {
				if pageNameRe.MatchString(m[1]) || pageNameRe.MatchString(m[2]) {
					out = append(out, i)
					break
				}
			}
		}
		return out
	},
}

// ---------------------------------------------------------------------------

// placeholderRe matches a generator template's unsubstituted placeholder as a
// PATH segment, which is the only place it has ever shipped. A bare word
// (a "REPLACE_ALL" mode name in a string) is not a link and does not fire.
var placeholderRe = regexp.MustCompile(`/REPLACE_[A-Z][A-Z0-9_]*\b`)

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
	Good: "package x\n\n// Render once read [back](/r/REPLACE_ADDR/blog).\nfunc Render(string) string {\n\treturn \"[back](/r/moul/x/daily/blog/v0) REPLACE_ALL\"\n}\n",
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

// ---------------------------------------------------------------------------

// rootRelativeLink finds a markdown link target starting with "/" that is not
// a realm, package or user path. Go's regexp has no lookahead, so the check is
// by hand on what follows "](/".
var rootRelativeLink = Rule{
	ID:   "root-relative-link",
	What: "renders a link to /something that is not /r/, /p/ or /u/, which leaves the realm",
	Why: "gnoweb resolves a root-relative target against the domain, not the realm: " +
		"[moul](/moul) is gno.land/moul and (/r:x) is the malformed gno.land/r:x. Each " +
		"was meant to be this realm's own subpage, renders as a dead link on a permanent " +
		"path, and passed its ExampleRender because the dead link is in the expected " +
		"output too.",
	Fix: "The realm's own absolute path: (/r/moul/x/daily/<name>/v0:<sub>). A link that " +
		"is computed (\"](/\" + x) needs x to carry the r/ or p/ itself.",
	Finding: "r/moul/x/daily/{handles,urlshort,vault}, found live on mainnet by putting " +
		"real rows into ten realms and reading what they rendered, 2026-09-30; " +
		"collatz and connect4 found by this rule's first run, 2026-10-01",
	Bad:  "package x\n\nfunc Render(string) string {\n\treturn \"[moul](/moul)\"\n}\n",
	Good: "package x\n\nfunc Render(string) string {\n\treturn \"[moul](/r/moul/x/daily/handles/v1:moul) [h](/u/moul) [$](/$help)\"\n}\n",
	Check: func(f File) []int {
		var out []int
		for i, ln := range f.Literal {
			rest := ln
			for {
				j := strings.Index(rest, "](/")
				if j < 0 {
					break
				}
				rest = rest[j+3:]
				if !strings.HasPrefix(rest, "r/") && !strings.HasPrefix(rest, "p/") &&
					!strings.HasPrefix(rest, "u/") && !strings.HasPrefix(rest, "$") &&
					!strings.HasPrefix(rest, "#") {
					out = append(out, i)
					break
				}
			}
		}
		return out
	},
}

// ---------------------------------------------------------------------------

// crossingFuncRe matches an exported top-level crossing function, capturing
// its parameter list. The list is first joined across lines (see joinParams),
// because a long signature is written one parameter per line.
var crossingFuncRe = regexp.MustCompile(`^func\s+[A-Z]\w*\s*\(\s*\w+\s+realm\b([^)]*)\)`)

// joinParams returns line i with the rest of its parameter list folded in,
// up to the parenthesis that closes it.
func joinParams(code []string, i int) string {
	ln := code[i]
	open := strings.Index(ln, "(")
	if open < 0 {
		return ln
	}
	depth := 0
	var b strings.Builder
	for j := i; j < len(code); j++ {
		seg := code[j]
		if j == i {
			seg = seg[open:]
			b.WriteString(ln[:open])
		}
		for k := 0; k < len(seg); k++ {
			c := seg[k]
			b.WriteByte(c)
			switch c {
			case '(':
				depth++
			case ')':
				depth--
				if depth == 0 {
					return b.String()
				}
			}
		}
		b.WriteByte(' ')
	}
	return b.String()
}

// typeDeclRe finds the named types a file declares that the VM cannot decode
// either: a struct, and a named slice, map, pointer, func or interface. A
// named string or integer type (type Mode string) is decoded, and not listed.
var typeDeclRe = regexp.MustCompile(`^type\s+([A-Za-z_]\w*)\s+(struct\b|interface\b|func\b|map\[|\*|\[\](\s*\w+)?)`)

// encodable is every parameter type MsgCall can carry, by the switch in
// gno.land/pkg/sdk/vm/convert.go.
var encodable = map[string]bool{
	"string": true, "bool": true, "address": true, "byte": true, "rune": true,
	"int": true, "int8": true, "int16": true, "int32": true, "int64": true,
	"uint": true, "uint8": true, "uint16": true, "uint32": true, "uint64": true,
	"float32": true, "float64": true, "[]byte": true, "[]uint8": true,
}

// unencodable reports why a parameter type cannot be decoded from a MsgCall
// argument, or "" when it can or when this file cannot tell.
func unencodable(typ string, structs map[string]bool) string {
	t := strings.TrimSpace(typ)
	t = strings.TrimPrefix(t, "...")
	switch {
	case t == "" || encodable[t]:
		return ""
	case strings.HasPrefix(t, "[]"), strings.HasPrefix(t, "map["),
		strings.HasPrefix(t, "*"), strings.HasPrefix(t, "func"),
		strings.HasPrefix(t, "interface"), strings.HasPrefix(t, "chan"):
		return t
	case strings.Contains(t, "."):
		return t // another package's type: in this tree, always a struct
	case structs[t]:
		return t
	}
	return ""
}

// undecodable lists the named types in a file that unencodable must refuse.
// A named []byte stays decodable, as the VM decodes its base type.
func undecodable(code []string) map[string]bool {
	out := map[string]bool{}
	for _, ln := range code {
		m := typeDeclRe.FindStringSubmatch(ln)
		if m == nil {
			continue
		}
		if elt := strings.TrimSpace(m[3]); elt == "byte" || elt == "uint8" {
			continue
		}
		out[m[1]] = true
	}
	return out
}

var uncallableCrossingArg = Rule{
	ID:   "uncallable-crossing-arg",
	What: "an exported crossing function takes a struct, pointer, slice or map, which no wallet can encode",
	Why: "MsgCall carries every argument as a string, and the VM's convertArgToGno " +
		"(gno.land/pkg/sdk/vm/convert.go) decodes primitives, named primitives and " +
		"[]byte only: anything else panics (\"unexpected slice type\", \"unexpected type " +
		"in contract arg\"). gnokey, every wallet and every session key are refused, " +
		"MsgRun is gated by run_submitters on mainnet, and the function is unreachable " +
		"on a permanent path. r/moul/gns shipped its Register this way, so no name can " +
		"be registered on mainnet.",
	Fix: "Flat parameters, or a delimited string split in the realm, as x/daily/ballot " +
		"(proposalNamesCSV) and x/daily/multisig (ownersCSV) already do. If the function " +
		"is meant for other realms only, say so with //gnovet:ignore.",
	Finding: "r/moul/agents/jury/v0 OpenCase(cur realm, subject string, jurors []address), " +
		"refused by simulation on gnoland-1 while seeding the agent realms, 2026-09-30; " +
		"r/moul/gns Register(cur realm, request RegisterRequest), found by the agent " +
		"review sweep, 2026-10-01",
	Bad: "package x\n\ntype Req struct{ Name string }\n\ntype Panel []address\n\n" +
		"func OpenCase(cur realm, subject string, jurors []address) uint64 {\n\treturn 0\n}\n\n" +
		"func Register(cur realm, r Req) {}\n\nfunc Seat(cur realm, p Panel) {}\n\n" +
		"func Long(\n\tcur realm,\n\tjurors []address,\n) {\n}\n",
	Good: "package x\n\ntype Mode string\n\ntype Blob []byte\n\n" +
		"func OpenCase(cur realm, subject, jurorsCSV string) uint64 {\n\treturn 0\n}\n\n" +
		"func SetRecord(cur realm, name string, value []byte, m Mode, b Blob) {}\n\nfunc helper(xs []address) {}\n\n" +
		"func Long(\n\tcur realm,\n\tsubject string,\n) {\n}\n",
	Check: func(f File) []int {
		structs := undecodable(f.Code)
		var out []int
		for i, ln := range f.Code {
			if !strings.HasPrefix(ln, "func ") {
				continue
			}
			m := crossingFuncRe.FindStringSubmatch(joinParams(f.Code, i))
			if m == nil {
				continue
			}
			for _, param := range strings.Split(m[1], ",") {
				// "name type" carries a type; a bare "name" takes the next one's.
				fields := strings.Fields(param)
				if len(fields) < 2 {
					continue
				}
				if unencodable(strings.Join(fields[1:], " "), structs) != "" {
					out = append(out, i)
					break
				}
			}
		}
		return out
	},
}

// ---------------------------------------------------------------------------

// originSendRe matches a read of the coins sent with the transaction, directly
// or through p/moul/x/envelope.
var originSendRe = regexp.MustCompile(`\bOriginSend\s*\(|\benvelope\.(Require|RequireAtLeast|RequireExactly|Amount|Only|All)\s*\(`)

var crossingDeclRe = regexp.MustCompile(`^func\s+\w+\s*\(\s*\w+\s+realm\b`)

var originSendUnguarded = Rule{
	ID:   "origin-send-unguarded",
	What: "a crossing function trusts OriginSend without checking the caller is a user",
	Why: "OriginSend is what the SIGNER attached to the transaction, not what reached " +
		"this realm. A realm the user called receives those coins itself, then calls in " +
		"here, as many times as it likes: r/moul/grant's Fund recorded 5 donations of " +
		"1 GNOT from one 1 GNOT send, with nothing in the treasury.",
	Fix: "if !cur.Previous().IsUserCall() { panic(...) } before the read, or measure the " +
		"realm's own balance delta instead.",
	Finding: "r/moul/grant Fund, reproduced by a scratch test in the agent review sweep " +
		"of 2026-10-01; the same shape in r/moul/faucet Fund and r/moul/x/nativeify Unwrap",
	Bad: "package x\n\nfunc Fund(cur realm) {\n\tsent := unsafe.OriginSend()\n\t_ = sent\n}\n\n" +
		"func Late(cur realm) {\n\tsent := unsafe.OriginSend()\n\tcredit(sent)\n\t" +
		"if !cur.Previous().IsUserCall() {\n\t\tpanic(\"late\")\n\t}\n}\n",
	Good: "package x\n\nfunc Fund(cur realm) {\n\tif !cur.Previous().IsUserCall() {\n\t\t" +
		"panic(\"users only\")\n\t}\n\tsent := unsafe.OriginSend()\n\t_ = sent\n}\n\n" +
		"func Amount(denom string) int64 {\n\treturn unsafe.OriginSend().AmountOf(denom)\n}\n",
	// A function body runs from its "func" line to the next top-level one.
	// Only crossing functions: a non-crossing helper (p/moul/x/envelope itself)
	// cannot check the caller, and the guard belongs to whoever calls it.
	Check: func(f File) []int {
		var out []int
		for i := 0; i < len(f.Code); i++ {
			if !crossingDeclRe.MatchString(f.Code[i]) {
				continue
			}
			end := i + 1
			for end < len(f.Code) && !strings.HasPrefix(f.Code[end], "func ") {
				end++
			}
			// The guard has to come BEFORE the first read: a check after
			// the coins were credited guards nothing.
			body := strings.Join(f.Code[i:end], "\n")
			if loc := originSendRe.FindStringIndex(body); loc != nil {
				if g := strings.Index(body, "IsUserCall"); g < 0 || g > loc[0] {
					out = append(out, i)
				}
			}
			i = end - 1
		}
		return out
	},
}

// ---------------------------------------------------------------------------

var colonRelativeLink = Rule{
	ID:   "colon-relative-link",
	What: "renders a link whose target starts with a colon, (:sub), which gnoweb drops",
	Why: "A target of :ns parses as a URL with an empty scheme, so gnoweb renders it as " +
		"<!-- invalid link --> and a browser would resolve it to .../ns/v0/:ns anyway. " +
		"Every navigation link on r/moul/x/plan9/ns and plan9/dev is dead this way, on " +
		"public paths.",
	Fix: "The realm's own absolute path: (/r/moul/x/plan9/ns/v0:ns).",
	Finding: "r/moul/x/plan9/{ns,dev}, the live page at gno.land/r/moul/x/plan9/ns/v0 " +
		"checked by the agent review sweep, 2026-10-01",
	Bad:  "package x\n\nfunc Render(string) string {\n\treturn \"[ns](:ns)\"\n}\n",
	Good: "package x\n\nfunc Render(string) string {\n\treturn \"[ns](/r/moul/x/plan9/ns/v0:ns) a:b\"\n}\n",
	Check: func(f File) []int {
		var out []int
		for i, ln := range f.Literal {
			if strings.Contains(ln, "](:") {
				out = append(out, i)
			}
		}
		return out
	},
}

// ---------------------------------------------------------------------------

// escaperInCodeSpanRe matches a backtick-only string literal concatenated with
// a call to one of the markdown escapers, in either order. It runs over
// Literal, not Code, because the backtick being matched lives INSIDE a string
// literal and Code blanks those.
var escaperInCodeSpanRe = regexp.MustCompile(
	"(\"`\"\\s*\\+\\s*\\w+\\.(?:Inline|Cell|Escape)\\()" +
		"|((?:Inline|Cell|Escape)\\([^)]*\\)\\s*\\+\\s*\"`)")

var escaperInCodeSpan = Rule{
	ID:   "escaper-in-code-span",
	What: "builds a code span by hand around a markdown escaper's output",
	Why: "Markdown escapes do not apply inside a code span, so the backslashes the escaper " +
		"added are inert and reach the reader: `gno\\.land\\_x\\-y` renders with every " +
		"backslash visible. Worse, an escaped backtick still CLOSES the span, so a caller " +
		"who puts a backtick in the value chooses where the monospace region ends and pulls " +
		"the realm's own sentence out of it.",
	Fix: "Use md.InlineCode, which sizes the fence past any backtick run in the content, " +
		"pads a leading or trailing space, returns \"\" for empty input, and applies no " +
		"inline escapes.",
	Finding: "gno-contracts#324, post-merge review 2026-10-07; the same shape was still live " +
		"in r/moul/vesting/render.gno:35 after the PR fixed riscvdemo and bfdemo",
	Bad: "package x\n\nfunc f() string {\n\t" +
		"return ui.Empty(\"`\" + ui.Inline(target) + \"` is not an address.\")\n}\n",
	Good: "package x\n\nfunc f() string {\n\t" +
		"return ui.Empty(md.InlineCode(target) + \" is not an address.\")\n}\n",
	Check: func(f File) []int {
		var out []int
		for i, ln := range f.Literal {
			if escaperInCodeSpanRe.MatchString(ln) {
				out = append(out, i)
			}
		}
		return out
	},
}

// ---------------------------------------------------------------------------

// trimSpaceValidityRe matches strings.TrimSpace(x) compared directly against
// the empty string. The comparison must follow the closing paren immediately,
// so ui.Inline(strings.TrimSpace(s)) != "" (the fix) does not match.
//
// It runs over Literal, not Code: Code blanks a string literal INCLUDING its
// quotes, so "" becomes two spaces there and the rule could never fire. Found
// by watching the Bad fixture stay silent.
var trimSpaceValidityRe = regexp.MustCompile(`strings\.TrimSpace\([^()]*\)\s*[!=]=\s*""`)

var trimSpaceAsValidity = Rule{
	ID:   "trimspace-as-validity",
	What: "decides a required field is present with strings.TrimSpace(s) != \"\"",
	Why: "strings.TrimSpace uses unicode.IsSpace, which does NOT include U+200B and the " +
		"other zero-width characters, while every escaper on the output side calls " +
		"StripBidiAndZeroWidth, which does. So a field of zero-width characters is stored " +
		"as present and renders as nothing. Where that field is the only link title in a " +
		"table row, the record becomes unreachable from its own index.",
	Fix: "Validate against the RENDERED form: ui.Inline(strings.TrimSpace(s)) != \"\". " +
		"What the reader will see is the thing that has to be non-empty.",
	Finding: "gno-contracts#325, post-merge review 2026-10-07; seven sites in one PR, " +
		"crew.gno:566 and :587, vouch.gno:386, patron.gno:467, threads.gno:293, " +
		"curated.gno:593 and :574",
	Bad: "package x\n\nfunc ValidName(s string) bool {\n\t" +
		"return strings.TrimSpace(s) != \"\"\n}\n",
	Good: "package x\n\nfunc ValidName(s string) bool {\n\t" +
		"return ui.Inline(strings.TrimSpace(s)) != \"\"\n}\n",
	Check: func(f File) []int {
		var out []int
		for i, ln := range f.Literal {
			if trimSpaceValidityRe.MatchString(ln) {
				out = append(out, i)
			}
		}
		return out
	},
}
