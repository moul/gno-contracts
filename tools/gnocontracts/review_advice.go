package main

import (
	"flag"
	"fmt"
	"sort"
	"strings"
)

// Whether to spend a Copilot code review on this pull request.
//
// Copilot code review costs 13 AI CREDITS per review (GitHub's published model
// multiplier for code review since 2026-06-01, where the unit used to be called
// a premium request).
//
// The real budget, read off moul's billing page on 2026-10-01 rather than from
// the docs, and it is not what the docs implied:
//
//	plan              Copilot Pro
//	included          1,500 AI credits / month, resets the 1st
//	used that day     1,211 of 1,500 (81%)
//	additional usage  $0.00 of $0 budget, NOT ENABLED
//
// Two corrections to what this file said before. The allowance on Pro is 1,500
// and not 300: the 300 figure is the older premium-request number and it is
// wrong for this account. And the failure mode is NOT a surprise bill, because
// additional usage is disabled: when the 1,500 runs out, Copilot code review
// simply STOPS until the reset. A hard cap, not a meter.
//
// That inverts the risk. The thing to protect is not moul's money, it is the
// ability to get a review at the moment one is actually worth having, which on
// 2026-10-01 was 289 credits away, about 22 reviews, with 31 days to go and the
// rest of the budget being spent by Copilot in his editor.
//
// This repository opened more than 100 pull requests in the fourteen days to
// 2026-10-01, roughly 215 a month. Reviewing all of them is ~2,800 AI credits a
// month against an allowance of 1,500 that is already 81% spent on other
// things. "Review everything" does not mean a bigger bill, it means the reviews
// stop part-way through the month and the next one that mattered does not
// happen.
//
// So the rule is not "review the big diffs" or "review when unsure". It is one
// sentence, and it comes from this repository's own central fact:
//
//	REVIEW EXACTLY WHAT IS ABOUT TO BECOME PERMANENT.
//
// 331 of the 333 contracts in the catalog are live on mainnet, and a public
// package path is immutable: AddPackage refuses an occupied path unless the
// live package is private. A finding against a package that is already live
// cannot be acted on in place at all; it needs a new version at a new path and
// every importer moved, which is a decision a human makes and not something a
// review unblocks. Spending 13 premium requests to learn that is spending them
// for nothing.
//
// The inverse is the whole value: a package that is NOT yet live is one merge
// from being frozen forever, and that is the only moment a review changes the
// outcome. There are two such packages today, so this policy is cheap by
// construction rather than by restraint.
//
// It is advice, never a gate: it exits 0 and prints a verdict. A human or an
// agent reads the line and decides. A tool that silently refused to review
// something would be worse than the cost it saves.

// creditsPerReview is GitHub's published model multiplier for Copilot code
// review. Dated because it is a product figure and will move.
//
// NOT verified against moul's own billing page: that page reports a total, not
// a per-feature breakdown, and its "View details" view is the only thing that
// would confirm the 13. Treat it as the best published figure and not as a
// measurement.
const creditsPerReview = 13 // as published 2026-10-01, effective 2026-06-01

// monthlyCredits is the Copilot Pro allowance, read off the billing page on
// 2026-10-01. The older docs say 300 premium requests for Pro; that is the
// previous unit and it is wrong for this account.
const monthlyCredits = 1500

type reviewVerdict struct {
	review  bool
	reasons []string
	skips   []string
}

func cmdReviewAdvice(root string, args []string) error {
	fs := flag.NewFlagSet("review-advice", flag.ContinueOnError)
	base := fs.String("base", "origin/main", "base ref to diff against")
	quiet := fs.Bool("quiet", false, "print only REVIEW or SKIP")
	if err := fs.Parse(args); err != nil {
		return err
	}

	a, err := analyzePR(root, *base)
	if err != nil {
		return err
	}
	v := adviseReview(a)

	if *quiet {
		fmt.Println(verdictWord(v.review))
		return nil
	}

	fmt.Printf("%s\n\n", verdictWord(v.review))
	if len(v.reasons) > 0 {
		fmt.Println("why:")
		for _, r := range v.reasons {
			fmt.Printf("  - %s\n", r)
		}
	}
	if len(v.skips) > 0 {
		fmt.Println("not a reason to review:")
		for _, s := range v.skips {
			fmt.Printf("  - %s\n", s)
		}
	}
	fmt.Printf("\nthe rule:\n%s\n", indentLines(reviewAdviceHint(), "  "))
	fmt.Printf("\ncost if requested: %d AI credit(s) of the %d-a-month Copilot Pro allowance.\n"+
		"Additional usage is disabled, so running out does not bill, it stops the reviews.\n"+
		"Balance: https://github.com/settings/billing\n",
		creditsPerReview, monthlyCredits)
	if v.review {
		fmt.Println("\n  gh pr edit <N> --add-reviewer @copilot")
	}
	return nil
}

func verdictWord(review bool) string {
	if review {
		return "REVIEW"
	}
	return "SKIP"
}

// adviseReview decides from an already-computed diff analysis, so it is pure
// and testable: no git, no network, no clock.
func adviseReview(a *prAnalysis) reviewVerdict {
	var v reviewVerdict

	// The reviewer's own configuration is the second thing worth 13 premium
	// requests, and it is not a contract.
	//
	// Evidence, not symmetry: #274 added these files, touched no .gno, and
	// would have been skipped by the permanence rule alone. Its review found
	// three real defects in them, each with file and line evidence. A wrong
	// instruction does not produce one wrong finding, it produces wrong
	// findings on every later review until somebody notices, which is a
	// permanence of its own and the only other kind this repository has.
	if cfg := changedReviewConfig(a.paths); len(cfg) > 0 {
		for _, f := range cfg {
			v.reasons = append(v.reasons,
				f+" governs every later review, so a defect in it is permanent until caught")
		}
		v.review = true
	}

	pkgs := append(append([]*pkgAgg{}, a.newPkgs...), a.updPkgs...)
	if len(pkgs) == 0 {
		if !v.review {
			v.skips = append(v.skips, "no p/ or r/ package changed")
		}
		return v
	}

	var permanent, live, testsOnly []string
	for _, p := range pkgs {
		name := p.dir
		if p.pkgPath != "" {
			name = p.pkgPath
		}
		switch {
		case !p.changedGo:
			// A README, a gnomod.toml comment: nothing a review reads.
			testsOnly = append(testsOnly, name+" (no .gno changed)")
		case !liveOnMainnet(a.byDir[p.dir]):
			permanent = append(permanent, name)
		default:
			live = append(live, name)
		}
	}
	sort.Strings(permanent)
	sort.Strings(live)
	sort.Strings(testsOnly)

	for _, p := range permanent {
		v.reasons = append(v.reasons,
			p+" is NOT yet live on mainnet: this is the last moment a finding can be acted on in place")
	}
	for _, p := range live {
		v.skips = append(v.skips,
			p+" is already live on an immutable path, so a finding needs a vN+1 and a human decision, not a review")
	}
	v.skips = append(v.skips, testsOnly...)

	v.review = v.review || len(permanent) > 0
	return v
}

// liveOnMainnet reads the catalog rather than the chain. contracts.json is
// regenerated on main hourly, so it is current within the hour and costs no
// network call, and a package missing from it entirely is new and therefore not
// live.
func liveOnMainnet(c *Contract) bool {
	if c == nil {
		return false
	}
	st, ok := c.Published["mainnet"]
	if !ok {
		return false
	}
	return st.Uploaded
}

// reviewAdviceHint is the one-paragraph version, for a human who asked why.
func reviewAdviceHint() string {
	return strings.TrimSpace(`
Review exactly what is about to become permanent. A package already live on
mainnet cannot be fixed in place, so a finding against it needs a vN+1 and a
human decision; a package not yet live is one merge from being frozen forever,
and that is the only moment a review changes the outcome.`)
}

// indentLines prefixes every line, so the rule reads as a block under a heading.
func indentLines(s, prefix string) string {
	lines := strings.Split(s, "\n")
	for i := range lines {
		lines[i] = prefix + lines[i]
	}
	return strings.Join(lines, "\n")
}

// reviewConfigPaths are the files that decide what every later review says.
var reviewConfigPaths = []string{
	".github/copilot-instructions.md",
	".github/instructions/",
}

func changedReviewConfig(paths []string) []string {
	var out []string
	for _, p := range paths {
		for _, pre := range reviewConfigPaths {
			if p == pre || strings.HasPrefix(p, pre) {
				out = append(out, p)
				break
			}
		}
	}
	sort.Strings(out)
	return out
}
