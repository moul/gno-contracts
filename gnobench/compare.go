package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
)

// cmdCompare diffs two result files and prints what moved. This is what a pull
// request gets: not "here are 900 numbers" but "these rows changed, by this
// much, and here is the one that got worse".
func cmdCompare(args []string) error {
	fs := flag.NewFlagSet("compare", flag.ExitOnError)
	var (
		base   = fs.String("base", "", "the result file before the change")
		head   = fs.String("head", "", "the result file after it")
		thresh = fs.Float64("threshold", 2, "percent change worth reporting")
		fail   = fs.Float64("fail-over", 0, "exit 1 if any row regresses by more than this percent (0 disables)")
		title  = fs.String("title", "gnobench", "heading for the output")
	)
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *head == "" {
		return fmt.Errorf("-head is required")
	}
	hf, err := readRows(*head)
	if err != nil {
		return err
	}
	bf, err := readRows(*base)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	fmt.Printf("## %s\n\n", *title)
	if bf == nil {
		fmt.Printf("No baseline for this machine yet: recording %d rows as the first one.\n", len(hf))
		return nil
	}

	type change struct {
		key             string
		gasB, gasH      int64
		byB, byH        int64
		gasPct, bytePct float64
		newRow, goneRow bool
	}
	var changes []change
	for k, h := range hf {
		b, ok := bf[k]
		if !ok {
			changes = append(changes, change{key: k, gasH: h.DGas, byH: h.DBytes, newRow: true})
			continue
		}
		gp := pct(b.DGas, h.DGas)
		bp := pct(b.DBytes, h.DBytes)
		if abs(gp) < *thresh && abs(bp) < *thresh {
			continue
		}
		changes = append(changes, change{key: k, gasB: b.DGas, gasH: h.DGas, byB: b.DBytes, byH: h.DBytes, gasPct: gp, bytePct: bp})
	}
	for k, b := range bf {
		if _, ok := hf[k]; !ok {
			changes = append(changes, change{key: k, gasB: b.DGas, byB: b.DBytes, goneRow: true})
		}
	}
	if len(changes) == 0 {
		fmt.Printf("No row moved by more than %.1f%%. %d rows compared.\n", *thresh, len(hf))
		return nil
	}
	sort.Slice(changes, func(i, j int) bool { return abs(changes[i].gasPct) > abs(changes[j].gasPct) })

	fmt.Printf("%d row(s) moved by more than %.1f%%, out of %d compared.\n\n", len(changes), *thresh, len(hf))
	fmt.Println("| scenario | gas before | gas after | gas | bytes before | bytes after | bytes |")
	fmt.Println("|---|--:|--:|--:|--:|--:|--:|")
	worst := 0.0
	shown := 0
	for _, c := range changes {
		if shown >= 60 {
			fmt.Printf("\n_...and %d more._\n", len(changes)-shown)
			break
		}
		shown++
		switch {
		case c.newRow:
			fmt.Printf("| `%s` | | %d | **new** | | %d | |\n", c.key, c.gasH, c.byH)
		case c.goneRow:
			fmt.Printf("| `%s` | %d | | **gone** | %d | | |\n", c.key, c.gasB, c.byB)
		default:
			if c.gasPct > worst {
				worst = c.gasPct
			}
			fmt.Printf("| `%s` | %d | %d | %s | %d | %d | %s |\n",
				c.key, c.gasB, c.gasH, sign(c.gasPct), c.byB, c.byH, sign(c.bytePct))
		}
	}
	if *fail > 0 && worst > *fail {
		fmt.Printf("\n**A row regressed by %.1f%%, over the %.1f%% limit.**\n", worst, *fail)
		os.Exit(1)
	}
	return nil
}

func readRows(path string) (map[string]Row, error) {
	if path == "" {
		return nil, os.ErrNotExist
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var f File
	if err := json.Unmarshal(b, &f); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	out := map[string]Row{}
	for k, r := range f.Rows {
		if r.Skip == "" && r.Err == "" {
			out[k] = r
		}
	}
	return out, nil
}

func pct(before, after int64) float64 {
	if before == 0 {
		if after == 0 {
			return 0
		}
		return 100
	}
	return float64(after-before) / float64(abs64(before)) * 100
}

func abs(f float64) float64 {
	if f < 0 {
		return -f
	}
	return f
}

func abs64(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}

func sign(p float64) string {
	if p > 0 {
		return fmt.Sprintf("+%.1f%%", p)
	}
	return fmt.Sprintf("%.1f%%", p)
}

// cmdAffected turns a list of changed file paths into a -filter regexp, so a
// pull request measures the candidates it could actually have changed instead
// of the whole suite. Paths come on stdin, one per line, as `git diff --name-only`
// prints them.
func cmdAffected(args []string) error {
	fs := flag.NewFlagSet("affected", flag.ExitOnError)
	suite := fs.String("suite", "storage", "which suite")
	if err := fs.Parse(args); err != nil {
		return err
	}
	s, ok := suites[*suite]
	if !ok {
		return fmt.Errorf("unknown suite %q", *suite)
	}
	var paths []string
	sc := bufio.NewScanner(os.Stdin)
	for sc.Scan() {
		if p := strings.TrimSpace(sc.Text()); p != "" {
			paths = append(paths, p)
		}
	}
	// A change to the harness itself, or to the vendored dependencies,
	// invalidates everything: measure the lot.
	for _, p := range paths {
		if strings.HasPrefix(p, "gnobench/") || strings.HasPrefix(p, "vendor/") {
			fmt.Println("")
			return nil
		}
	}
	var hit []string
	for _, st := range s.Structures {
		for _, imp := range st.Imports {
			mod := strings.Trim(imp, `"`)
			// "gno.land/p/moul/ulist/v1" -> the repository path "p/moul/ulist"
			rel := strings.TrimPrefix(mod, "gno.land/")
			rel = trimVersion(rel)
			for _, p := range paths {
				if strings.HasPrefix(p, rel+"/") || p == rel {
					hit = append(hit, regexp.QuoteMeta(st.Name))
				}
			}
		}
	}
	hit = dedupe(hit)
	if len(hit) == 0 {
		// Nothing a candidate depends on changed. Exit 3 so a workflow can
		// tell "measure nothing" apart from "measure everything".
		os.Exit(3)
	}
	sort.Strings(hit)
	fmt.Println("^(" + strings.Join(hit, "|") + ")/")
	return nil
}

var versionSuffix = regexp.MustCompile(`/v[0-9]+$`)

func trimVersion(p string) string { return versionSuffix.ReplaceAllString(p, "") }

func dedupe(ss []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range ss {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}
