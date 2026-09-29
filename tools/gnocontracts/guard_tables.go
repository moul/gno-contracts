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

// The table question, and why it is the guard this repository needed most.
//
// A markdown table built by concatenating pipes gets four things wrong, every
// time, and none of them is visible in a diff:
//
//   - a cell containing "|" silently opens a column nobody asked for, which is
//     the cheapest way for a caller's string to rewrite the page around it;
//   - a row with fewer cells than headers silently drops its data, rather than
//     padding;
//   - an empty table renders as a header with no body, instead of a sentence;
//   - the separator row has to match the header count, and nothing checks it.
//
// p/moul/kit/ui's Table does all four. It was written because 102 files here
// were doing it by hand, and the package that tells everyone else not to is one
// of them: p/moul/pilot, which cannot be fixed, because p/moul/pilot/v0 is live
// on mainnet and a public package path is immutable.
//
// That is the whole reason this is a guard and not a cleanup task. 329 of the
// 331 contracts in the catalog are live. The baseline below is not a backlog, it
// is a record: almost none of it can ever be cleared in place. What the guard
// buys is the 101st file.
//
// Why a separator row is the thing detected, rather than "| " anywhere: it is
// the one part of a GFM table that cannot be anything else. A line of dashes and
// pipes is a table header separator or it is nothing, so a hit is never a
// coincidence, and a string like "| a | b |" alone is genuinely ambiguous with
// prose. The cost is that a file assembling a table WITHOUT a separator is
// missed, which is a table that does not render anyway.
//
// It is a RATCHET over a baseline rather than a gate, because 102 files is not a
// number anybody drives to zero, and because nearly all of them are already live
// on a chain where their Render can never be replaced.

// tableSepRe matches a GFM header separator: pipes and runs of three or more
// dashes, with optional alignment colons and spaces. `|---|`, `| --- |`,
// `|:---|---:|` all match; a `---` horizontal rule and an `a---b` identifier do
// not, because a pipe is required on one side of the run.
var tableSepRe = regexp.MustCompile(`(\|[[:space:]]*:?-{3,}:?[[:space:]]*)|([[:space:]]*:?-{3,}:?[[:space:]]*\|)`)

// tableOptOutRe matches the opt-out comment, `// handrolled-table: <why>`.
var tableOptOutRe = regexp.MustCompile(`//[[:space:]]*handrolled-table:[[:space:]]*(\S.*?)[[:space:]]*$`)

// minTableReason is the floor on an opt-out reason, in characters. The real
// reasons name what the table is ("the README footer", "a gnoweb column layout
// ui.Table cannot express"); "n/a" and "needed" name nothing.
const minTableReason = 20

// tableExempt are the packages that are allowed to emit a separator row,
// because emitting one correctly is what they are for. Everything else goes
// through one of these.
var tableExempt = map[string]bool{
	"p/moul/kit/ui":   true, // the house table
	"p/moul/mdtable":  true, // the frozen monorepo mirror
	"p/moul/md":       true, // Columns() lays a table out as a grid
	"p/moul/mdlist":   true,
	"p/moul/template": true, // a table can arrive as a user's template string
}

// tableBaselineFile lists the packages that already build tables by hand.
var tableBaselineFile = filepath.Join("tools", "gnocontracts", "handrolled-table-baseline.txt")

// cmdGuardTables fails when a package builds a markdown table separator row in
// its own source and is not recorded as already doing so.
func cmdGuardTables(root string, args []string) error {
	update := len(args) > 0 && args[0] == "-update"

	found := map[string]bool{} // dir -> builds a separator by hand
	optOut := map[string]string{}
	where := map[string]string{} // dir -> first file:line, for the failure message

	err := walkGno(root, []string{"p/moul", "r/moul"}, func(rel string, toks []gnoTok) error {
		dir := filepath.ToSlash(filepath.Dir(rel))
		if tableExempt[dir] {
			return nil
		}
		if !fileExists(filepath.Join(root, filepath.FromSlash(dir), "gnomod.toml")) {
			return nil // a loose file, not a package
		}
		// The opt-out is read from EVERY file, tests included; the separator is
		// detected only outside them. Asymmetric on purpose: a test's own
		// dashes are the author's fixture and not a page anyone loads, while a
		// package whose production source is already live on a public path can
		// never be edited again, so a comment in its test file is the only
		// place a true opt-out can still be written. p/moul/x/daily/cowsay is
		// exactly that case.
		isTest := isTestFile(filepath.Base(rel))
		for _, tk := range toks {
			switch tk.tok {
			case token.COMMENT:
				if m := tableOptOutRe.FindStringSubmatch(tk.lit); m != nil {
					optOut[dir] = m[1]
				}
			case token.STRING:
				if !isTest && tableSepRe.MatchString(tk.lit) && !found[dir] {
					found[dir] = true
					where[dir] = fmt.Sprintf("%s:%d", rel, tk.line)
				}
			}
		}
		return nil
	})
	if err != nil {
		return err
	}

	// An opted-out package is out of the baseline entirely: the comment beside
	// the code is the record, and carrying both would mean two mechanisms
	// answering for one package and neither one going stale when it is fixed.
	for dir := range optOut {
		delete(found, dir)
	}

	if update {
		return writeTableBaseline(root, found, where)
	}

	baseline, err := readTableBaseline(root)
	if err != nil {
		return err
	}

	var bad, thin, stale []string
	for dir := range found {
		if baseline[dir] {
			continue
		}
		bad = append(bad, dir+"  "+where[dir])
	}
	// A reason under the floor answers nothing, whether or not the package was
	// grandfathered, so this is checked over every opt-out and not just the new
	// ones.
	for dir, why := range optOut {
		if len(why) < minTableReason {
			thin = append(thin, fmt.Sprintf("%s (reason is %d chars, need %d): %s",
				dir, len(why), minTableReason, why))
		}
	}

	// A baseline entry for a package that no longer builds a table by hand
	// silences the next one that does. It comes out the moment it is fixed.
	for dir := range baseline {
		if !found[dir] {
			stale = append(stale, dir)
		}
	}

	sort.Strings(bad)
	sort.Strings(thin)
	sort.Strings(stale)

	if len(stale) > 0 {
		return failf("guard-tables FAIL, baseline entries that no longer apply", stale,
			"These no longer build a table by hand: they use p/moul/kit/ui now, or\n"+
				"they said what the dashes really are with a handrolled-table comment.\n"+
				"Drop the line so the next hand-rolled table is not hidden behind it:\n"+
				"  make guard-tables-update")
	}
	if len(thin) > 0 {
		return failf("guard-tables FAIL, opt-out reasons that answer nothing", thin,
			"Name what the table is and why ui.Table cannot express it, e.g.\n"+
				"// handrolled-table: the generated README footer, not a rendered page")
	}
	if len(bad) > 0 {
		return failf("guard-tables FAIL, markdown tables built by hand", bad,
			"Use p/moul/kit/ui, which pads short rows, escapes a cell that would\n"+
				"open a new column, and says something when the table is empty:\n\n"+
				"  t := ui.NewTable(\"path\", \"state\")\n"+
				"  t.Row(md.InlineCode(p), ui.Cell(state))\n"+
				"  return t.OrEmpty(\"Nothing here yet.\")\n\n"+
				"Or, if this really is not a rendered table, say what it is:\n"+
				"  // handrolled-table: <what it is>\n\n"+
				"Why: EFFECTIVE_GNO.md section 3.2")
	}
	fmt.Printf("guard-tables: no new hand-rolled markdown tables (%d grandfathered)\n", len(baseline))
	return nil
}

func readTableBaseline(root string) (map[string]bool, error) {
	b, err := os.ReadFile(filepath.Join(root, tableBaselineFile))
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
		out[strings.Fields(line)[0]] = true
	}
	return out, nil
}

func writeTableBaseline(root string, found map[string]bool, where map[string]string) error {
	dirs := make([]string, 0, len(found))
	for d := range found {
		dirs = append(dirs, d)
	}
	sort.Strings(dirs)

	var b strings.Builder
	b.WriteString(tableBaselineHeader)
	for _, d := range dirs {
		fmt.Fprintf(&b, "%s\t%s\n", d, where[d])
	}
	out := filepath.Join(root, tableBaselineFile)
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(out, []byte(b.String()), 0o644); err != nil {
		return err
	}
	fmt.Printf("guard-tables: baseline written, %d package(s)\n", len(dirs))
	return nil
}

const tableBaselineHeader = `# Packages that build a markdown table separator row by hand, and the first
# line in each where they do.
#
# A RATCHET, not an allowlist. A package not listed here may not start; a
# package listed here that stops must be removed, or it hides the next one.
# Regenerate with:
#
#   make guard-tables-update
#
# The fix is p/moul/kit/ui: it pads a short row instead of dropping its data,
# escapes a cell that would open a new column, and renders a sentence instead of
# an empty header. Why each of those matters: EFFECTIVE_GNO.md section 3.2.
#
# Nearly all of these are already live on a chain, where a public path is
# immutable and Render can never be replaced: 329 of the 331 contracts in the
# catalog are on mainnet. So this file is a record, not a backlog. What the guard
# buys is the next one, before it is deployed.

`
