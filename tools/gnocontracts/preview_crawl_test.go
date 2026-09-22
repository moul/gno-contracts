package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSplitGnowebURL(t *testing.T) {
	cases := []struct{ in, base, args, query string }{
		{"/r/x/y", "/r/x/y", "", ""},
		{"/r/x/y$source&file=a.gno", "/r/x/y", "", "source&file=a.gno"},
		{"/r/x/y:p/about$source", "/r/x/y", "p/about", "source"},
		{"/r/x/y/", "/r/x/y/", "", ""}, // the listing view keeps its slash
	}
	for _, c := range cases {
		base, args, query := splitGnowebURL(c.in)
		if base != c.base || args != c.args || query != c.query {
			t.Errorf("splitGnowebURL(%q) = %q,%q,%q want %q,%q,%q", c.in, base, args, query, c.base, c.args, c.query)
		}
	}
}

func TestCanonicalURLGivesOneSpellingPerPage(t *testing.T) {
	a := canonicalURL("/r/x/y$source&file=a.gno")
	b := canonicalURL("/r/x/y$file=a.gno&source")
	if a != b {
		t.Fatalf("gnoweb emits both orders and they canonicalize differently: %q vs %q", a, b)
	}
}

// The two ways a slug can silently destroy a page: escaping the realm's own
// directory, and folding two different URLs onto one file.
func TestURLToFileNeverTraversesOrCollides(t *testing.T) {
	if got := urlToFile("/r/x/y:.."); strings.Contains(got, "..") {
		t.Fatalf("urlToFile(:..) = %q, which climbs out of the package directory", got)
	}
	if urlToFile("/r/x/y:..") == urlToFile("/r/x/y") {
		t.Fatal("a `:..` argument folds onto the package's own render page")
	}
	seen := map[string]string{}
	for _, u := range []string{"/r/x/y:p/a-b", "/r/x/y:p/a/b", "/r/x/y:p/a&b"} {
		f := urlToFile(u)
		if prev, ok := seen[f]; ok {
			t.Fatalf("%q and %q both write %q", prev, u, f)
		}
		seen[f] = u
	}
	// The render and the listing are different pages of different sizes.
	if urlToFile("/r/x/y") == urlToFile("/r/x/y/") {
		t.Fatal("the listing view overwrites the render view")
	}
	// A plain tab stays readable rather than becoming a digest.
	if got, want := urlToFile("/r/x/y$source"), "r/x/y/_t/source/index.html"; got != want {
		t.Fatalf("urlToFile = %q, want %q", got, want)
	}
	// No output path may ever carry a character a static host chokes on.
	for _, u := range []string{"/r/x/y:p/a&b$source", "/r/x/y$source&file=a.gno"} {
		if strings.ContainsAny(urlToFile(u), "$:&") {
			t.Fatalf("urlToFile(%q) = %q keeps a URL-only character", u, urlToFile(u))
		}
	}
}

func TestInScopeSkipsWhatEnumeratesRatherThanDescribes(t *testing.T) {
	c := &Crawler{Paths: []string{"gno.land/r/moul/hello/v0"}}
	in := []string{
		"/r/moul/hello/v0",
		"/r/moul/hello/v0$source",
		"/r/moul/hello/v0$help",
		"/r/moul/hello/v0:p/about",
	}
	out := []string{
		"/r/moul/hello/v0$state",           // the whole object graph
		"/r/moul/hello/v0$state&oid=1",     // and its drill-down
		"/r/moul/hello/v0$help&func=Hello", // $help already lists them all
		"/r/moul/hello/v0$download&file=a", // raw bytes, not a page
		"/r/moul/hello/v0:p/about$source",  // byte-identical to $source
		"/r/moul/hello/v0/",                // the listing, left to the live site
		"/r/moul/other/v0",                 // not selected
	}
	for _, u := range in {
		if !c.inScope(u) {
			t.Errorf("inScope(%q) = false, want true", u)
		}
	}
	for _, u := range out {
		if c.inScope(u) {
			t.Errorf("inScope(%q) = true, want false", u)
		}
	}
}

// A per-file source page is kept for a file the pull request changed, and
// dropped for one it did not.
func TestPerFileSourcePagesFollowTheChangedSet(t *testing.T) {
	c := &Crawler{
		Paths:        []string{"gno.land/r/moul/hello/v0"},
		ChangedFiles: map[string][]string{"gno.land/r/moul/hello/v0": {"hello.gno"}},
	}
	if !c.inScope("/r/moul/hello/v0$source&file=hello.gno") {
		t.Error("the changed file's source page was dropped")
	}
	if c.inScope("/r/moul/hello/v0$source&file=other.gno") {
		t.Error("an unchanged file's source page was kept")
	}
	// The site snapshot keeps every file.
	all := &Crawler{Paths: c.Paths, FileBudget: unlimitedFiles}
	if !all.inScope("/r/moul/hello/v0$source&file=other.gno") {
		t.Error("the site snapshot dropped a file")
	}
}

func TestSetNoindexReplacesGnowebsOwnTag(t *testing.T) {
	body := `<html><head><meta name="robots" content="index, follow"><title>x</title></head></html>`
	got := setNoindex(body)
	if strings.Contains(got, "index, follow") {
		t.Errorf("gnoweb's index directive survived:\n%s", got)
	}
	if n := strings.Count(got, `name="robots"`); n != 1 {
		t.Errorf("%d robots tags, want exactly 1 — two conflicting directives leave the outcome to the crawler", n)
	}
	// A page without one still gets it.
	if !strings.Contains(setNoindex("<html><head></head></html>"), "noindex") {
		t.Error("no robots tag added to a page that had none")
	}
}

// The crawl, the rewrite and the asset copy, against a stub gnoweb.
func TestCrawlerWritesASelfContainedTree(t *testing.T) {
	mux := http.NewServeMux()
	page := func(body string) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(body)) }
	}
	mux.HandleFunc("/r/moul/hello/v0", page(
		`<html><head><meta name="robots" content="index, follow"></head>`+
			`<link href="/public/css/main.css"><a href="/r/moul/hello/v0$source">src</a>`+
			`<a href="/r/moul/other/v0">elsewhere</a></html>`))
	mux.HandleFunc("/r/moul/hello/v0$source", page(`<html>source view</html>`))
	mux.HandleFunc("/r/moul/hello/v0$help", page(`<html>help</html>`))
	mux.HandleFunc("/r/moul", page(`<html>dir</html>`))
	srv := httptest.NewServer(mux)
	defer srv.Close()

	// A stand-in for gnoweb's public/ tree, including the hardcoded prefix that
	// has to be relativized or every interactive control 404s.
	assets := t.TempDir()
	os.MkdirAll(filepath.Join(assets, "js"), 0o755)
	os.WriteFile(filepath.Join(assets, "js", "index.js"), []byte(`import("/public/js/controller-x.js")`), 0o644)

	out := t.TempDir()
	c := &Crawler{Base: srv.URL, Paths: []string{"gno.land/r/moul/hello/v0"}, Live: "https://gno.land"}
	if err := c.Run(); err != nil {
		t.Fatal(err)
	}
	if err := c.Write(out, assets); err != nil {
		t.Fatal(err)
	}

	got := readTestFile(t, filepath.Join(out, "r/moul/hello/v0/index.html"))
	if !strings.Contains(got, `href="../../../../public/css/main.css"`) {
		t.Errorf("asset path not relativized:\n%s", got)
	}
	// A link we captured goes to the captured copy...
	if !strings.Contains(got, `href="../../../../r/moul/hello/v0/_t/source/"`) {
		t.Errorf("captured link not pointed at the snapshot:\n%s", got)
	}
	// ...and one we did not goes to the live site rather than 404ing.
	if !strings.Contains(got, `href="https://gno.land/r/moul/other/v0"`) {
		t.Errorf("uncaptured link not sent to the live site:\n%s", got)
	}
	if strings.Contains(got, "index, follow") {
		t.Error("the snapshot is still asking to be indexed")
	}
	js := readTestFile(t, filepath.Join(out, "public/js/index.js"))
	if strings.Contains(js, "/public/js/controller-") {
		t.Errorf("the controller prefix was not relativized: %s", js)
	}
}

// One page that 404s must not cost the whole crawl.
func TestCrawlerSurvivesAMissingPage(t *testing.T) {
	srv := httptest.NewServer(http.NotFoundHandler())
	defer srv.Close()
	c := &Crawler{Base: srv.URL, Paths: []string{"gno.land/r/moul/gone/v0"}}
	if err := c.Run(); err != nil {
		t.Fatalf("a 404 was fatal: %v", err)
	}
	if c.Pages() != 0 {
		t.Fatalf("captured %d pages from a server that has none", c.Pages())
	}
}

// --- planning --------------------------------------------------------------

func previewFixture() []Contract {
	return []Contract{
		{PkgPath: "gno.land/p/moul/md/v1", Dir: "p/moul/md", Kind: "p"},
		{PkgPath: "gno.land/p/moul/kit/v0", Dir: "p/moul/kit", Kind: "p", Deps: []string{"gno.land/p/moul/md/v1"}},
		{PkgPath: "gno.land/r/moul/home/v0", Dir: "r/moul/home", Kind: "r", Deps: []string{"gno.land/p/moul/kit/v0"}},
		{PkgPath: "gno.land/r/moul/hello/v0", Dir: "r/moul/hello", Kind: "r"},
		{PkgPath: "gno.land/r/moul/old/v0", Dir: "r/moul/old", Kind: "r", Ignored: true},
	}
}

func TestSiteModePreviewsEveryLivePackage(t *testing.T) {
	plan, err := buildPreviewPlan(previewFixture(), true, "", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	if plan.Mode != "site" {
		t.Fatalf("mode = %q", plan.Mode)
	}
	if len(plan.Paths) != 4 {
		t.Fatalf("previewing %v, want the four non-archived packages", plan.Paths)
	}
	for _, p := range plan.Paths {
		if strings.Contains(p, "/old/") {
			t.Error("an `ignore = true` package was previewed; it does not build")
		}
	}
}

// A pure package changing is the case the old preview missed entirely: nothing
// under r/ changed, so nothing was rendered, even though two realms render
// differently now.
func TestPullRequestModeFollowsReverseDeps(t *testing.T) {
	changed := filepath.Join(t.TempDir(), "changed.txt")
	os.WriteFile(changed, []byte("p/moul/md/md.gno\n"), 0o644)

	plan, err := buildPreviewPlan(previewFixture(), false, changed, nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"gno.land/p/moul/md/v1"}; !equalStrings(plan.Changed, want) {
		t.Fatalf("changed = %v, want %v", plan.Changed, want)
	}
	// kit imports md, home imports kit: the walk is transitive.
	if !contains(plan.Dependents, "gno.land/r/moul/home/v0") || !contains(plan.Dependents, "gno.land/p/moul/kit/v0") {
		t.Fatalf("dependents = %v, want the transitive closure", plan.Dependents)
	}
	if contains(plan.Paths, "gno.land/r/moul/hello/v0") {
		t.Error("an unrelated realm was previewed")
	}
	if got := plan.ChangedFiles["gno.land/p/moul/md/v1"]; !equalStrings(got, []string{"md.gno"}) {
		t.Fatalf("changed files = %v, want [md.gno]", got)
	}
}

func TestChangedPathsIgnoreTestsAndPickTheDeepestPackage(t *testing.T) {
	got := changedPackages(previewFixture(), []string{
		"r/moul/home/home_test.gno",   // a test cannot change what renders
		"r/moul/home/filetests/x.gno", // nor a filetest
		"r/moul/home/README.md",       // but any other file in the package can
	})
	if _, ok := got["gno.land/r/moul/home/v0"]; !ok {
		t.Fatalf("README change did not select the package: %v", got)
	}
	if files := got["gno.land/r/moul/home/v0"]; len(files) != 0 {
		t.Fatalf("test files leaked into the per-file source set: %v", files)
	}
}

func TestTheCapNeverDropsAChangedPackage(t *testing.T) {
	changed := filepath.Join(t.TempDir(), "changed.txt")
	os.WriteFile(changed, []byte("p/moul/md/md.gno\n"), 0o644)
	plan, err := buildPreviewPlan(previewFixture(), false, changed, nil, 1)
	if err != nil {
		t.Fatal(err)
	}
	if !equalStrings(plan.Paths, []string{"gno.land/p/moul/md/v1"}) {
		t.Fatalf("paths = %v, want just the changed package", plan.Paths)
	}
	if plan.Dropped != 2 {
		t.Fatalf("dropped = %d, want 2 — a silent drop is the bug", plan.Dropped)
	}
}

func TestPreviewCommentLinksWhatWasRendered(t *testing.T) {
	plan := &previewPlan{
		Mode:       "pr",
		Changed:    []string{"gno.land/r/moul/home/v0"},
		Dependents: []string{"gno.land/r/moul/hello/v0"},
		New:        []string{"gno.land/r/moul/home/v0"},
		Dropped:    3,
	}
	got := previewComment(plan, "https://moul.github.io/gno-contracts-previews/pr-7/")
	for _, want := range []string{
		"https://moul.github.io/gno-contracts-previews/pr-7/r/moul/home/v0/",
		"/_t/source/",
		"**new**",
		"imports what changed",
		"3 more affected package(s) not rendered",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("comment fragment missing %q:\n%s", want, got)
		}
	}
	// The base URL is joined exactly once, however the caller spelled it.
	if strings.Contains(got, "pr-7//") {
		t.Errorf("double slash in a link:\n%s", got)
	}
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func contains(s []string, v string) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}

// A realm is free to link a page per value it knows about; the preview is not
// obliged to follow. Without this budget one realm in this repository produced
// 4,065 pages and 220 MB on its own.
func TestRenderArgumentsAreCappedPerPackage(t *testing.T) {
	c := &Crawler{Paths: []string{"gno.land/r/moul/x/daily/romannumdemo/v0"}, ArgBudget: 2}
	for i, u := range []string{"/r/moul/x/daily/romannumdemo/v0:1", "/r/moul/x/daily/romannumdemo/v0:2"} {
		if !c.charge(u) {
			t.Fatalf("argument page %d was dropped while the budget had room", i)
		}
	}
	if c.charge("/r/moul/x/daily/romannumdemo/v0:3") {
		t.Fatal("the argument budget did not stop the third page")
	}
	// The package's own render page is never an argument page, so it is free.
	if !c.charge("/r/moul/x/daily/romannumdemo/v0") {
		t.Fatal("the render page itself was charged as an argument page")
	}
	// And a zero budget is no cap at all, like MaxPages, so a Crawler nobody
	// configured behaves as if the budget did not exist.
	free := &Crawler{Paths: c.Paths}
	if !free.charge("/r/moul/x/daily/romannumdemo/v0:1") || !free.charge("/r/moul/x/daily/romannumdemo/v0:2") {
		t.Fatal("a zero ArgBudget dropped argument pages instead of meaning no cap")
	}
}

// The Makefile and CI both invoke this as `go -C tools tool gnocontracts`,
// which runs the tool IN tools/. A path resolved against the process working
// directory therefore lands one level too deep: the CI render wrote six pages
// and a screenshot into tools/_preview and the next step could not find them.
func TestRelativePathsResolveAgainstTheRepositoryRoot(t *testing.T) {
	if got, want := underRoot("/repo", "_preview"), filepath.Join("/repo", "_preview"); got != want {
		t.Fatalf("underRoot = %q, want %q", got, want)
	}
	if got := underRoot("/repo", "/tmp/changed.txt"); got != "/tmp/changed.txt" {
		t.Fatalf("an absolute path was rewritten: %q", got)
	}
	if got := underRoot("/repo", "-"); got != "-" {
		t.Fatalf("stdin was rewritten: %q", got)
	}
	if got := underRoot("/repo", ""); got != "" {
		t.Fatalf("an unset flag was rewritten: %q", got)
	}
}

// The detail file is optional, so a path that does not resolve looks exactly
// like "no preview yet". That is why it goes through underRoot: read from
// tools/, `_preview/preview.md` is always missing and the comment silently
// loses its preview section, which is what happened on PR #185.
func TestPreviewDetailIsReadFromTheRepositoryRoot(t *testing.T) {
	root := t.TempDir()
	os.MkdirAll(filepath.Join(root, "_preview"), 0o755)
	os.WriteFile(filepath.Join(root, "_preview", "preview.md"), []byte("- [`x`](u)\n"), 0o644)
	if got := readPreviewDetail(underRoot(root, "_preview/preview.md")); got != "- [`x`](u)" {
		t.Fatalf("detail = %q, want the file contents", got)
	}
	if got := readPreviewDetail(""); got != "" {
		t.Fatalf("an unset flag read something: %q", got)
	}
}

// A superseded version is pinned by hash to a commit in this repository's
// history: nobody can change what it renders, so previewing it reviews
// nothing, and it renders whatever was true at that commit. One of them still
// carries a local path in its README that main stopped shipping long ago, and
// rendering it published that path to a public site.
//
// It still has to LOAD, because packages in the tree import it. Only the crawl
// skips it.
func TestSupersededVersionsAreLoadedButNeverCrawled(t *testing.T) {
	contracts := append(previewFixture(), Contract{
		PkgPath: "gno.land/r/moul/old/v0", Dir: "r/moul/old", Kind: "r", Superseded: true,
		Commit: "4f2df83869b80470eb81c48a82fdbe82256b8113",
	})
	plan, err := buildPreviewPlan(contracts, true, "", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	if contains(plan.Paths, "gno.land/r/moul/old/v0") {
		t.Fatalf("a history-pinned version was crawled: %v", plan.Paths)
	}
	// And it is not dragged in as a dependent either.
	dep := append(previewFixture(), Contract{
		PkgPath: "gno.land/r/moul/old/v0", Dir: "r/moul/old", Kind: "r", Superseded: true,
		Deps: []string{"gno.land/p/moul/md/v1"},
	})
	changed := filepath.Join(t.TempDir(), "changed.txt")
	os.WriteFile(changed, []byte("p/moul/md/md.gno\n"), 0o644)
	plan, err = buildPreviewPlan(dep, false, changed, nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	if contains(plan.Paths, "gno.land/r/moul/old/v0") {
		t.Fatalf("a history-pinned version was pulled in as a dependent: %v", plan.Paths)
	}
}
