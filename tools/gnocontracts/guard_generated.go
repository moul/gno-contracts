package main

import (
	"flag"
	"fmt"
	"strings"
)

// Generated paths a pull request must not carry. They are rewritten on `main`
// after merge, so a PR that commits them only creates a conflict with the next
// regeneration.
var generatedPaths = []string{"contracts.json", "_assets"}

// README.md is the special case: part generated (the contracts table, the
// dependency-graph section), part hand-written prose. Rejecting the whole file
// also blocked fixing stale prose, which the regenerator never touches — so
// only the generated REGIONS are compared. The region markers are the ones
// `readme` itself writes (tableBegin/tableEnd/graphHeading in readme.go): one
// owner, so the guard cannot drift from the generator it guards.
const regionSep = "\n<<<REGION>>>\n"

// cmdGuardGenerated fails if a pull request modifies generated artifacts.
//
//	go tool gnocontracts guard-generated -base <sha> -head <sha>
//
// The diff is three-dot (merge-base..head), i.e. only what THIS pull request
// changed: two-dot would also flag files that merely advanced on main (the
// regen bot's contracts.json), failing older branches for someone else's work.
func cmdGuardGenerated(root string, args []string) error {
	fs := flag.NewFlagSet("guard-generated", flag.ContinueOnError)
	base := fs.String("base", "origin/main", "base ref of the pull request")
	head := fs.String("head", "HEAD", "head ref of the pull request")
	if err := fs.Parse(args); err != nil {
		return err
	}

	changed := gitLines(root, append([]string{"diff", "--name-only", *base + "..." + *head, "--"}, generatedPaths...)...)
	if len(changed) > 0 {
		return failf("this PR modifies generated files, which are rewritten on `main` by the regen workflow", changed,
			"Fix: git checkout origin/main -- "+strings.Join(generatedPaths, " "))
	}

	if len(gitLines(root, "diff", "--name-only", *base+"..."+*head, "--", "README.md")) == 0 {
		fmt.Println("guard-generated: PR touches only source files")
		return nil
	}

	mergeBase := strings.TrimSpace(gitOut(root, "merge-base", *base, *head))
	if mergeBase == "" {
		mergeBase = *base
	}
	was := readmeRegions(gitOut(root, "show", mergeBase+":README.md"))
	is := readmeRegions(gitOut(root, "show", *head+":README.md"))
	if was != is {
		return failf("this PR changes the GENERATED regions of README.md (the contracts table and/or the dependency-graph section)",
			[]string{"README.md"},
			"Those are rewritten on `main` by the regen workflow, so committing them here only creates conflicts.\n"+
				"Fix: git checkout origin/main -- README.md, then re-apply only your prose edits.")
	}
	fmt.Println("guard-generated: README.md — only hand-written prose changed, allowed")
	return nil
}

// readmeRegions extracts the parts of README.md that `gnocontracts readme`
// rewrites: the contracts table (between its markers) and the body of the
// dependency-graph section. Everything else is prose, and a PR may edit it.
func readmeRegions(content string) string {
	var out []string
	if i := strings.Index(content, tableBegin); i >= 0 {
		if j := strings.Index(content, tableEnd); j > i {
			out = append(out, content[i:j+len(tableEnd)])
		}
	}
	if g := strings.Index(content, graphHeading); g >= 0 {
		rest := content[g+len(graphHeading):]
		end := len(content)
		if k := strings.Index(rest, "\n## "); k >= 0 {
			end = g + len(graphHeading) + k + 1
		}
		out = append(out, content[g:end])
	}
	return strings.Join(out, regionSep)
}

// gitLines runs a git command and returns its non-empty output lines.
func gitLines(root string, args ...string) []string {
	var out []string
	for _, ln := range strings.Split(gitOut(root, args...), "\n") {
		if ln = strings.TrimSpace(ln); ln != "" {
			out = append(out, ln)
		}
	}
	return out
}
