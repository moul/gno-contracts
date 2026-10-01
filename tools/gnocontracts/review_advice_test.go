package main

import (
	"strings"
	"testing"
)

// pkg builds one changed package for the analysis.
func pkg(dir, path string, changedGo bool) *pkgAgg {
	return &pkgAgg{dir: dir, pkgPath: path, changedGo: changedGo}
}

// analysis assembles a prAnalysis without touching git, which is the point of
// adviseReview being pure.
func analysis(paths []string, pkgs []*pkgAgg, live map[string]bool) *prAnalysis {
	a := &prAnalysis{paths: paths, byDir: map[string]*Contract{}}
	for _, p := range pkgs {
		a.updPkgs = append(a.updPkgs, p)
		a.byDir[p.dir] = &Contract{
			PkgPath:   p.pkgPath,
			Dir:       p.dir,
			Published: map[string]Pub{"mainnet": {Uploaded: live[p.dir]}},
		}
	}
	return a
}

// The rule: a package not yet live is the last moment a finding can be acted
// on in place.
func TestAdviseReviewsAPackageThatIsNotYetLive(t *testing.T) {
	a := analysis(
		[]string{"p/moul/kit/index/index.gno"},
		[]*pkgAgg{pkg("p/moul/kit/index", "gno.land/p/moul/kit/index/v0", true)},
		map[string]bool{"p/moul/kit/index": false},
	)
	v := adviseReview(a)
	if !v.review {
		t.Fatalf("want REVIEW for an unpublished package, got SKIP: %v", v.skips)
	}
	if !strings.Contains(strings.Join(v.reasons, "\n"), "NOT yet live") {
		t.Errorf("want the permanence reason, got %v", v.reasons)
	}
}

// The inverse, which is where the money is saved: 331 of 333 contracts are
// live, and a finding against one of those cannot be acted on in place.
func TestAdviseSkipsAPackageAlreadyLive(t *testing.T) {
	a := analysis(
		[]string{"r/moul/home/render.gno"},
		[]*pkgAgg{pkg("r/moul/home", "gno.land/r/moul/home", true)},
		map[string]bool{"r/moul/home": true},
	)
	v := adviseReview(a)
	if v.review {
		t.Fatalf("want SKIP for a live package, got REVIEW: %v", v.reasons)
	}
	if !strings.Contains(strings.Join(v.skips, "\n"), "immutable path") {
		t.Errorf("want the immutability reason, got %v", v.skips)
	}
}

// One unpublished package among live ones is still the last moment for that
// one, so the whole PR is worth reviewing.
func TestAdviseReviewsAMixedDiff(t *testing.T) {
	a := analysis(
		[]string{"p/a/a.gno", "r/b/b.gno"},
		[]*pkgAgg{
			pkg("p/a", "gno.land/p/a/v0", true),
			pkg("r/b", "gno.land/r/b/v0", true),
		},
		map[string]bool{"p/a": true, "r/b": false},
	)
	if v := adviseReview(a); !v.review {
		t.Fatalf("one unpublished package is enough, got SKIP: %v", v.skips)
	}
}

func TestAdviseSkipsADiffWithNoPackage(t *testing.T) {
	a := analysis([]string{"README.md", "Makefile"}, nil, nil)
	v := adviseReview(a)
	if v.review {
		t.Fatalf("want SKIP with no package changed, got REVIEW: %v", v.reasons)
	}
	if !strings.Contains(strings.Join(v.skips, "\n"), "no p/ or r/ package changed") {
		t.Errorf("want the no-package reason, got %v", v.skips)
	}
}

// A README or a gnomod comment inside a package is not something a review
// reads.
func TestAdviseSkipsAPackageWhoseGnoDidNotChange(t *testing.T) {
	a := analysis(
		[]string{"p/moul/kit/index/README.md"},
		[]*pkgAgg{pkg("p/moul/kit/index", "gno.land/p/moul/kit/index/v0", false)},
		map[string]bool{"p/moul/kit/index": false},
	)
	if v := adviseReview(a); v.review {
		t.Fatalf("want SKIP when no .gno changed, got REVIEW: %v", v.reasons)
	}
}

// The second trigger, and it exists because of a counterexample rather than
// for symmetry: #274 changed only these files, would have been skipped by the
// permanence rule, and its review found three real defects in them.
func TestAdviseReviewsAChangeToTheReviewConfig(t *testing.T) {
	for _, path := range []string{
		".github/copilot-instructions.md",
		".github/instructions/gno.instructions.md",
	} {
		t.Run(path, func(t *testing.T) {
			v := adviseReview(analysis([]string{path}, nil, nil))
			if !v.review {
				t.Fatalf("want REVIEW when %s changes, got SKIP: %v", path, v.skips)
			}
			if !strings.Contains(strings.Join(v.reasons, "\n"), "governs every later review") {
				t.Errorf("want the config reason, got %v", v.reasons)
			}
		})
	}
}

// A workflow or an unrelated .github file is not the reviewer's configuration.
func TestAdviseDoesNotTreatEveryGithubFileAsConfig(t *testing.T) {
	a := analysis([]string{".github/workflows/ci.yml", ".github/ci-internals.md"}, nil, nil)
	if v := adviseReview(a); v.review {
		t.Fatalf("want SKIP for an unrelated .github file, got REVIEW: %v", v.reasons)
	}
}

// A package missing from the catalog is new, and new is the case this policy
// most wants reviewed. Reading it as "live" would skip exactly the wrong PR.
func TestAnAbsentCatalogEntryIsNotLive(t *testing.T) {
	if liveOnMainnet(nil) {
		t.Fatal("a package with no catalog entry must not read as live")
	}
	if liveOnMainnet(&Contract{Published: map[string]Pub{}}) {
		t.Fatal("a package with no mainnet entry must not read as live")
	}
	if !liveOnMainnet(&Contract{Published: map[string]Pub{"mainnet": {Uploaded: true}}}) {
		t.Fatal("an uploaded package is live")
	}
}
