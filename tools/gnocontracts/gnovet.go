package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/moul/gno-contracts/tools/gnovet"
)

// The loop this closes.
//
// A Copilot code review costs 13 premium requests and finds a defect once. A
// rule costs nothing and finds it every time. So every confirmed finding worth
// generalising becomes a rule in tools/gnovet, with the pull request and the
// review comment cited in its source, and the thing stops being discoverable by
// anyone ever again:
//
//	review finds it -> fix it -> write the rule -> never pay for it twice
//
// That is also the only honest way to grow a house linter. A rule invented from
// taste is a rule somebody argues with; a rule that cites the morning it cost
// real money is not.
//
// Ratchet over a baseline, like guard-tables and audit-patterns, because the
// tree predates the rules: a new hit fails, and a FIXED one fails too until the
// baseline is re-recorded, so a fix cannot be quietly undone.

var gnovetBaselineFile = filepath.Join("tools", "gnocontracts", "gnovet-baseline.txt")

func cmdGnovet(root string, args []string) error {
	fs := flag.NewFlagSet("gnovet", flag.ContinueOnError)
	update := fs.Bool("update", false, "re-record the baseline from what the tree contains now")
	list := fs.Bool("rules", false, "print every rule, with why it exists and where it came from")
	only := fs.String("rule", "", "run one rule only")
	if err := fs.Parse(args); err != nil {
		return err
	}

	if *list {
		for _, r := range gnovet.Rules {
			fmt.Println(r.Describe())
			fmt.Println()
		}
		return nil
	}

	rules := gnovet.Rules
	if *only != "" {
		r, ok := gnovet.ByID(*only)
		if !ok {
			return fmt.Errorf("unknown rule %q (see -rules)", *only)
		}
		rules = []gnovet.Rule{r}
	}

	dirs, err := contractDirs(root, false)
	if err != nil {
		return err
	}
	sort.Strings(dirs)

	var hits []gnovet.Hit
	for _, dir := range dirs {
		found, err := gnovet.RunRules(filepath.Join(root, filepath.FromSlash(dir)), rules)
		if err != nil {
			return err
		}
		for _, h := range found {
			h.File = dir + "/" + h.File
			hits = append(hits, h)
		}
	}

	if *update {
		return writeGnovetBaseline(root, hits)
	}
	if *only != "" {
		for _, h := range hits {
			fmt.Printf("%-22s %s:%d  %s\n", h.Rule, h.File, h.Line, h.Text)
		}
		fmt.Printf("%d hit(s)\n", len(hits))
		return nil
	}
	return compareGnovet(root, hits)
}

// gnovetKey identifies a baseline row. The LINE is deliberately not part of it:
// a rule that moved down a file is the same debt, and a baseline that churns on
// every unrelated edit is a baseline nobody keeps accurate.
type gnovetKey struct{ rule, file string }

func compareGnovet(root string, hits []gnovet.Hit) error {
	baseline, err := readGnovetBaseline(root)
	if err != nil {
		return err
	}
	counts := map[gnovetKey]int{}
	byKey := map[gnovetKey][]gnovet.Hit{}
	for _, h := range hits {
		k := gnovetKey{h.Rule, h.File}
		counts[k]++
		byKey[k] = append(byKey[k], h)
	}

	var appeared, grew, shrank []string
	for k, n := range counts {
		switch was, ok := baseline[k]; {
		case !ok:
			appeared = append(appeared, fmt.Sprintf("%s  %s  %d hit(s)", k.rule, k.file, n))
		case n > was:
			grew = append(grew, fmt.Sprintf("%s  %s  %d -> %d", k.rule, k.file, was, n))
		case n < was:
			shrank = append(shrank, fmt.Sprintf("%s  %s  %d -> %d", k.rule, k.file, was, n))
		}
	}
	for k, was := range baseline {
		if _, ok := counts[k]; !ok {
			shrank = append(shrank, fmt.Sprintf("%s  %s  %d -> 0", k.rule, k.file, was))
		}
	}
	sort.Strings(appeared)
	sort.Strings(grew)
	sort.Strings(shrank)

	if len(appeared) > 0 || len(grew) > 0 {
		items := append(append([]string{}, appeared...), grew...)
		return failf("gnovet FAIL, new house-rule hits", items,
			gnovetHint(items, byKey))
	}
	if len(shrank) > 0 {
		return failf("gnovet FAIL, the baseline is now too generous", shrank,
			"These improved, which is the point, and the baseline has to record it or it\n"+
				"silently permits the regression. Re-record with:\n"+
				"  make gnovet-update")
	}
	fmt.Printf("gnovet: %d hit(s) across %d row(s), all at baseline (%d rule(s))\n",
		len(hits), len(counts), len(gnovet.Rules))
	return nil
}

// gnovetHint prints the offending lines and then the rule itself, because a
// rule id is not an argument and the whole value of the citation is that a
// reader can go and check it.
func gnovetHint(items []string, byKey map[gnovetKey][]gnovet.Hit) string {
	var b strings.Builder
	seen := map[string]bool{}
	for _, it := range items {
		f := strings.Fields(it)
		if len(f) < 2 {
			continue
		}
		k := gnovetKey{f[0], f[1]}
		for i, h := range byKey[k] {
			if i == 5 {
				b.WriteString("  ...\n")
				break
			}
			fmt.Fprintf(&b, "  %s:%d  %s\n", h.File, h.Line, h.Text)
		}
		if !seen[k.rule] {
			seen[k.rule] = true
			if r, ok := gnovet.ByID(k.rule); ok {
				fmt.Fprintf(&b, "\n%s\n\n", r.Describe())
			}
		}
	}
	b.WriteString("If it is genuinely right here, say why beside it:\n")
	b.WriteString("  //gnovet:ignore <rule-id> <why, at least 20 characters>\n\n")
	b.WriteString("Every rule was a real defect in this repository before it was a rule;\n")
	b.WriteString("`from:` cites the review that found it. Re-record with: make gnovet-update")
	return b.String()
}

func readGnovetBaseline(root string) (map[gnovetKey]int, error) {
	b, err := os.ReadFile(filepath.Join(root, gnovetBaselineFile))
	if err != nil {
		if os.IsNotExist(err) {
			return map[gnovetKey]int{}, nil
		}
		return nil, err
	}
	out := map[gnovetKey]int{}
	for i, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Fields(line)
		if len(f) != 3 {
			return nil, fmt.Errorf("%s:%d: want `rule file count`, got %q", gnovetBaselineFile, i+1, line)
		}
		var n int
		if _, err := fmt.Sscanf(f[2], "%d", &n); err != nil {
			return nil, fmt.Errorf("%s:%d: %w", gnovetBaselineFile, i+1, err)
		}
		out[gnovetKey{f[0], f[1]}] = n
	}
	return out, nil
}

func writeGnovetBaseline(root string, hits []gnovet.Hit) error {
	counts := map[gnovetKey]int{}
	for _, h := range hits {
		counts[gnovetKey{h.Rule, h.File}]++
	}
	keys := make([]gnovetKey, 0, len(counts))
	for k := range counts {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].rule != keys[j].rule {
			return keys[i].rule < keys[j].rule
		}
		return keys[i].file < keys[j].file
	})

	var b strings.Builder
	b.WriteString(gnovetBaselineHeader)
	for _, k := range keys {
		fmt.Fprintf(&b, "%s %s %d\n", k.rule, k.file, counts[k])
	}
	out := filepath.Join(root, gnovetBaselineFile)
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(out, []byte(b.String()), 0o644); err != nil {
		return err
	}
	fmt.Printf("gnovet: baseline written, %d row(s), %d hit(s)\n", len(keys), len(hits))
	return nil
}

const gnovetBaselineHeader = `# House-rule hits this tree already has, one row per (rule, file).
#
# Format: <rule> <file> <count>
#
# A RATCHET. The count may not go up, and it may not go down either without
# this file being re-recorded, so a fix cannot be quietly undone. Regenerate:
#
#   make gnovet-update
#
# A row here is NOT a statement that the code is fine. It is a statement that
# the hit predates the rule, and almost all of it is unfixable in place: 331 of
# 333 contracts are live on mainnet and a public path is immutable. What this
# file buys is the next one, before it ships.
#
# Every rule was a real defect found in this repository before it became a rule.
# ` + "`make gnovet ARGS=-rules`" + ` prints each one with the review that found it.

`
