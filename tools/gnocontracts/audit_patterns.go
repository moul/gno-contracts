package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/moul/gno-contracts/tools/auditpattern"
)

// The audit patterns, and why this repository runs somebody else's rules.
//
// gnolang/gno ships an audit pattern harness under misc/audit-pattern-harness:
// ten finding families distilled from real audit work, each with a vulnerable
// fixture, a fixed fixture and a scanner that has to flag the first and leave
// the second alone. Upstream runs it against those fixtures, which proves the
// rules still fire. Nothing runs it against real contracts.
//
// This command does. The rules are mirrored verbatim in
// tools/auditpattern (see that package's doc comment for why a mirror), and
// this side supplies the two things a real tree needs and a fixture does not:
//
//   - a BASELINE, because 360 hits across 284 packages is not a number anybody
//     is going to drive to zero in one pull request, and a guard that is red on
//     arrival is a guard people learn to ignore.
//   - a RATCHET. The baseline records a count per (rule, package). A count that
//     goes up fails. A count that goes DOWN also fails, asking you to re-record
//     it, so the debt can only shrink and a fix cannot be quietly undone.
//
// What this is not: a proof of a vulnerability. Every rule is a lexical
// approximation and several of them (callback_param, exported_pointer_leak,
// current_guard) are generous on purpose, because a scanner that misses is
// worse than one that asks. A hit is a line for a human or an agent to look at
// before deciding. That is why the report prints file:line and why -json exists:
// it is the input to a review, not its conclusion.

// auditRealmOnly is the set of rules that are scanned in r/ and not in p/.
//
// Not a convenience: it is upstream's own framing. Its expected records title
// these rules "accepted by a REALM", "returned from a REALM", and its fixtures
// are realms. The same shape in a pure package is usually the package doing its
// job, and flagging it would bury the realm hits under them:
//
//   - callback_param: a p/ iterator takes a callback. That IS the API
//     (avl.Tree.Iterate, store.Each, fp.Map). A realm taking one is handing an
//     attacker its frame.
//   - exported_pointer_leak / pkg_mutable_pointer: a p/ constructor returns a
//     pointer, which is how you get a value at all with no generics. A realm
//     exporting one hands out a live mutation handle with no checks.
//   - render_markdown_escape / render_map_iteration: a p/ has no Render that a
//     reader loads, and guard-untrusted-render already owns the realm side.
//   - payment_user_call / origin_caller_auth / unsafe_previous_realm: a p/
//     cannot open a realm frame, so these read the caller's, which is the
//     documented way a threaded p/ works.
//
// current_guard and interface_realm_param are NOT here, deliberately. A p/ that
// threads `rlm realm` has exactly the question current_guard asks, and an
// interface leaking `cur realm` is worst in a p/, because that is where the
// interfaces live.
var auditRealmOnly = map[string]bool{
	"callback_param":         true,
	"exported_pointer_leak":  true,
	"pkg_mutable_pointer":    true,
	"render_markdown_escape": true,
	"render_map_iteration":   true,
	"payment_user_call":      true,
	"origin_caller_auth":     true,
	"unsafe_previous_realm":  true,
}

// auditBaselineFile is where the per-package counts live, relative to the root.
var auditBaselineFile = filepath.Join("tools", "gnocontracts", "audit-pattern-baseline.txt")

// auditHit is one finding, flattened for the report and for -json.
type auditHit struct {
	Rule string `json:"rule"`
	Dir  string `json:"dir"`
	File string `json:"file"`
	Line int    `json:"line"`
	Text string `json:"text"`
}

// auditKey identifies a baseline row: one rule, one package.
type auditKey struct {
	rule string
	dir  string
}

func (k auditKey) String() string { return k.rule + "\t" + k.dir }

func cmdAuditPatterns(root string, args []string) error {
	fs := flag.NewFlagSet("audit-patterns", flag.ContinueOnError)
	update := fs.Bool("update", false, "rewrite the baseline from what the tree contains now")
	asJSON := fs.Bool("json", false, "write every hit as JSON to stdout instead of a report")
	listRules := fs.Bool("rules", false, "list the rules and exit")
	drift := fs.String("drift", "", "path to a gnolang/gno checkout: re-hash the mirrored upstream file and fail if it moved")
	warn := fs.Bool("warn", false, "with -drift: report on stdout and exit 0 instead of failing")
	only := fs.String("rule", "", "run one rule only")
	pkg := fs.String("pkg", "", "only packages whose path contains this substring")
	if err := fs.Parse(args); err != nil {
		return err
	}

	if *listRules {
		for _, r := range auditpattern.Rules {
			fmt.Println(r)
		}
		return nil
	}
	if *drift != "" {
		// A drift is upstream's change, not this pull request's, so CI reports
		// it with -warn and lets the author merge. What must not happen is the
		// drift going unnoticed, which is the only failure mode a silent copy
		// has.
		err := auditCheckDrift(*drift)
		if err != nil && *warn {
			fmt.Println(err)
			return nil
		}
		return err
	}

	rules := auditpattern.Rules
	if *only != "" {
		if !auditKnownRule(*only) {
			return fmt.Errorf("unknown rule %q (see -rules)", *only)
		}
		rules = []string{*only}
	}

	dirs, err := contractDirs(root, false)
	if err != nil {
		return err
	}
	sort.Strings(dirs)

	var hits []auditHit
	counts := map[auditKey]int{}
	for _, dir := range dirs {
		if *pkg != "" && !strings.Contains(dir, *pkg) {
			continue
		}
		isRealm := strings.HasPrefix(dir, "r/")
		for _, rule := range rules {
			if auditRealmOnly[rule] && !isRealm {
				continue
			}
			before := len(hits)
			found, err := auditpattern.RunRule(rule, filepath.Join(root, filepath.FromSlash(dir)))
			if err != nil {
				return fmt.Errorf("%s in %s: %w", rule, dir, err)
			}
			for _, h := range found {
				// A test is not the deployed surface, and its `cur.Previous()`
				// or its callback is the author's own. guard-untrusted-render
				// draws the same line for the same reason. The mirror scans
				// every .gno because a fixture package IS its test; filtering
				// belongs here rather than in the copied rules.
				if isTestFile(filepath.Base(h.File)) {
					continue
				}
				hits = append(hits, auditHit{
					Rule: rule,
					Dir:  dir,
					File: filepath.ToSlash(h.File),
					Line: h.Line,
					Text: h.Text,
				})
			}
			if n := len(hits) - before; n > 0 {
				counts[auditKey{rule, dir}] = n
			}
		}
	}

	if *asJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(hits)
	}
	if *update {
		return auditWriteBaseline(root, counts)
	}
	// A filtered run cannot judge the baseline: the rows it did not visit would
	// all read as fixed. Report and stop.
	if *only != "" || *pkg != "" {
		auditPrintReport(hits, counts)
		return nil
	}
	return auditCompare(root, hits, counts)
}

func auditKnownRule(name string) bool {
	for _, r := range auditpattern.Rules {
		if r == name {
			return true
		}
	}
	return false
}

// auditCompare is the gate. It fails in three directions, and the third is the
// one that makes the file trustworthy over time.
func auditCompare(root string, hits []auditHit, counts map[auditKey]int) error {
	baseline, err := auditReadBaseline(root)
	if err != nil {
		return err
	}

	var grew, appeared, shrank []string
	for k, n := range counts {
		was, ok := baseline[k]
		switch {
		case !ok:
			appeared = append(appeared, fmt.Sprintf("%s  %s  %d hit(s)", k.rule, k.dir, n))
		case n > was:
			grew = append(grew, fmt.Sprintf("%s  %s  %d -> %d", k.rule, k.dir, was, n))
		case n < was:
			shrank = append(shrank, fmt.Sprintf("%s  %s  %d -> %d", k.rule, k.dir, was, n))
		}
	}
	for k, was := range baseline {
		if _, ok := counts[k]; !ok {
			shrank = append(shrank, fmt.Sprintf("%s  %s  %d -> 0", k.rule, k.dir, was))
		}
	}

	sort.Strings(appeared)
	sort.Strings(grew)
	sort.Strings(shrank)

	if len(appeared) > 0 || len(grew) > 0 {
		items := append(append([]string{}, appeared...), grew...)
		return failf("audit-patterns FAIL, new audit-pattern hits", items,
			auditHintFor(items, hits)+
				"\nEach rule is a heuristic and a hit is a line to look at, not a proven bug.\n"+
				"Read it. If the pattern really is safe here, say why in a comment beside it\n"+
				"and record the count with:\n"+
				"  make audit-patterns-update\n"+
				"The families, and why each one is a finding:\n"+
				"  EFFECTIVE_GNO.md section 5.7")
	}
	if len(shrank) > 0 {
		return failf("audit-patterns FAIL, the baseline is now too generous", shrank,
			"These improved, which is the point, and the baseline has to record it or it\n"+
				"silently permits the regression. Re-record with:\n"+
				"  make audit-patterns-update")
	}

	fmt.Printf("audit-patterns: %d hit(s) across %d (rule, package) rows, all at baseline\n",
		len(hits), len(counts))
	return nil
}

// auditHintFor names the files behind the failing rows, because a rule name
// plus a package is not enough to start reading.
func auditHintFor(items []string, hits []auditHit) string {
	want := map[auditKey]bool{}
	for _, it := range items {
		f := strings.Fields(it)
		if len(f) >= 2 {
			want[auditKey{f[0], f[1]}] = true
		}
	}
	var b strings.Builder
	shown := 0
	for _, h := range hits {
		if !want[auditKey{h.Rule, h.Dir}] {
			continue
		}
		if shown == 10 {
			b.WriteString("  ... (make audit-patterns ARGS=-json for the rest)\n")
			break
		}
		fmt.Fprintf(&b, "  %s:%d  %s\n", h.File, h.Line, h.Text)
		shown++
	}
	if shown == 0 {
		return ""
	}
	return "The lines:\n" + b.String()
}

func auditPrintReport(hits []auditHit, counts map[auditKey]int) {
	byRule := map[string]int{}
	for k, n := range counts {
		byRule[k.rule] += n
	}
	for _, r := range auditpattern.Rules {
		if byRule[r] == 0 {
			continue
		}
		fmt.Printf("%-24s %d\n", r, byRule[r])
	}
	for _, h := range hits {
		fmt.Printf("  %-24s %s:%d  %s\n", h.Rule, h.File, h.Line, h.Text)
	}
	fmt.Printf("total: %d hit(s)\n", len(hits))
}

func auditReadBaseline(root string) (map[auditKey]int, error) {
	b, err := os.ReadFile(filepath.Join(root, auditBaselineFile))
	if err != nil {
		if os.IsNotExist(err) {
			return map[auditKey]int{}, nil
		}
		return nil, err
	}
	out := map[auditKey]int{}
	for i, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Fields(line)
		if len(f) != 3 {
			return nil, fmt.Errorf("%s:%d: want `rule dir count`, got %q", auditBaselineFile, i+1, line)
		}
		n, err := strconv.Atoi(f[2])
		if err != nil {
			return nil, fmt.Errorf("%s:%d: %w", auditBaselineFile, i+1, err)
		}
		out[auditKey{f[0], f[1]}] = n
	}
	return out, nil
}

func auditWriteBaseline(root string, counts map[auditKey]int) error {
	keys := make([]auditKey, 0, len(counts))
	total := 0
	for k, n := range counts {
		keys = append(keys, k)
		total += n
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].rule != keys[j].rule {
			return keys[i].rule < keys[j].rule
		}
		return keys[i].dir < keys[j].dir
	})

	var b strings.Builder
	b.WriteString(auditBaselineHeader)
	for _, k := range keys {
		fmt.Fprintf(&b, "%s %s %d\n", k.rule, k.dir, counts[k])
	}
	out := filepath.Join(root, auditBaselineFile)
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(out, []byte(b.String()), 0o644); err != nil {
		return err
	}
	fmt.Printf("audit-patterns: baseline written, %d row(s), %d hit(s)\n", len(keys), total)
	return nil
}

const auditBaselineHeader = `# Audit-pattern hits this tree already has, one row per (rule, package).
#
# Format: <rule> <package dir> <count>
#
# This is a RATCHET, not an allowlist. The count may not go up, and it may not
# go down either without this file being re-recorded, so a fix cannot be quietly
# undone and debt can only shrink. Regenerate with:
#
#   make audit-patterns-update
#
# A row here is NOT a statement that the code is fine. It is a statement that
# the hit predates the guard. Every rule is a lexical approximation: read the
# line before you believe it, and read it before you clear it. The ten families
# and why each is a finding: EFFECTIVE_GNO.md section 5.7.
#
# Rules mirrored from gnolang/gno misc/audit-pattern-harness.

`

// auditCheckDrift re-hashes the upstream file the mirror was taken from. A
// mirror nobody can verify is a fork with a misleading comment on top.
func auditCheckDrift(gnoroot string) error {
	path := filepath.Join(gnoroot, filepath.FromSlash(auditpattern.UpstreamFile))
	got, err := sha256File(path)
	if err != nil {
		return fmt.Errorf("cannot read the upstream file at %s: %w", path, err)
	}
	if got == auditpattern.UpstreamSHA256 {
		fmt.Printf("audit-patterns: mirror matches upstream %s\n", auditpattern.UpstreamCommit[:12])
		return nil
	}
	return fmt.Errorf(`audit-patterns FAIL, the mirrored upstream file has changed

  file: %s
  mirrored at: %s
  want sha256: %s
  got  sha256: %s

Re-mirror tools/auditpattern/run.go from that file, keeping the rule functions
and the source reader byte for byte, and update the three constants at its top.
Then re-record the baseline: rules that changed will change their counts.`,
		auditpattern.UpstreamFile, auditpattern.UpstreamCommit, auditpattern.UpstreamSHA256, got)
}

// sha256File hashes a file's bytes.
func sha256File(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), nil
}
