package main

import (
	"flag"
	"fmt"
	"sort"
	"strings"
)

// Whether to spend a Copilot code review on this pull request.
//
// Copilot code review costs about 76 AI CREDITS per review, MEASURED, which is
// roughly six times the 13 GitHub publishes as the model multiplier. Do not
// trust the published figure; it is not what the billing page charges.
//
// The real budget, from the AI usage page's per-model breakdown on 2026-10-01:
//
//	plan              Copilot Pro
//	included          1,500 AI credits / month, resets the 1st
//	used              1,211 of 1,500 (81%), ON THE FIRST DAY OF THE CYCLE
//	of which          1,210.74 is the Code Review model. Essentially all of it.
//	additional usage  $0.00 of $0 budget, NOT ENABLED
//	credit price      $0.01
//
// Divide that by the 16 Copilot reviews requested across this repository that
// day (#274 x1, #289 x6, #295 x8, #296 x1; zero in any other repo) and a review
// costs 1210.74/16 = ~75.7 credits, about $0.76. Not 13.
//
// Three things follow, and the third is the one that actually matters.
//
// 1. The allowance is 1,500 and not the 300 the docs quote for Pro, which is
//    the older premium-request unit.
// 2. The failure mode is NOT a bill. Additional usage is disabled, so when the
//    1,500 runs out Copilot code review simply STOPS until the reset. A hard
//    cap. On 2026-10-01 that was 289 credits, under FOUR reviews, with 31 days
//    to go.
// 3. RE-REVIEWS ARE THE COST. Fourteen of those sixteen reviews were second and
//    later passes on two pull requests. Choosing which pull requests deserve a
//    review, which is all this file used to do, would have saved nothing on the
//    day that spent the month's budget. Capping passes per pull request is what
//    saves it.
//
// At ~76 credits a review the whole allowance is TWENTY REVIEWS A MONTH. This
// repository opened more than 100 pull requests in the fourteen days to
// 2026-10-01, roughly 215 a month, so reviewing all of them is not 9x the
// budget, it is 80x it. "Review everything" does not mean a bigger bill, it
// means the reviews stop on the second day and the next one that mattered does
// not happen.
//
// Even the triage below, at four reviewable pull requests per sixty, is 20% of
// the allowance for FIRST passes alone and 71% if each of them averages the
// three-and-a-half passes the two expensive pull requests took. The budget is
// tight either way, and the honest framing is a standing cap of about twenty
// reviews a month rather than a comfortable margin.
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

// creditsPerReview is MEASURED, not published: 1,210.74 credits charged to the
// Code Review model on 2026-10-01 divided by the 16 reviews requested that day.
//
// GitHub publishes 13 as the model multiplier for code review. The billing page
// charges about six times that. The measurement wins, and a figure this far off
// its documentation is worth re-measuring whenever the usage page is open.
const creditsPerReview = 76 // measured 2026-10-01: 1210.74 credits / 16 reviews

// maxPassesPerPR is the standing cap this policy recommends per pull request:
// the first review, plus one re-review after the findings are fixed.
//
// It is the lever that matters. On 2026-10-01, 14 of 16 reviews were third and
// later passes on two pull requests, and they are what spent the month.
const maxPassesPerPR = 2

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
	fmt.Printf("\ncost if requested: ~%d AI credits (measured) of a %d-a-month allowance,\n"+
		"which is about %d reviews a month in total. Additional usage is disabled, so\n"+
		"running out does not bill, it stops the reviews until the 1st.\n"+
		"At most %d passes per pull request: the first, and one after the fixes land.\n"+
		"Balance: https://github.com/settings/billing (AI usage)\n",
		creditsPerReview, monthlyCredits, monthlyCredits/creditsPerReview, maxPassesPerPR)
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
