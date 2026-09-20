package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestMatchesSelector(t *testing.T) {
	cases := []struct {
		dir, sel string
		want     bool
	}{
		{"r/moul/hello/v0", "./...", true},
		{"r/moul/hello/v0", "./r/moul/hello/v0", true},
		{"r/moul/hello/v0", "./r/moul/hello", true}, // parent directory
		{"r/moul/hello/v0", "./r/moul/...", true},   // recursive
		{"r/moul/hello/v0", "./r/moul/hell", false}, // prefix, not a path component
		{"r/moul/hello/v0", "./r/other/...", false},
		{"r/moul/hello/v0", "r/moul/hello/v0/", true}, // no ./, trailing /
	}
	for _, c := range cases {
		if got := matchesSelector(c.dir, []string{c.sel}); got != c.want {
			t.Errorf("matchesSelector(%q, %q) = %v, want %v", c.dir, c.sel, got, c.want)
		}
	}
}

func TestRelPrefixAndCSSRel(t *testing.T) {
	if got, want := relPrefix("/r/moul/hello/v0"), "../../../../"; got != want {
		t.Errorf("relPrefix = %q, want %q", got, want)
	}
	if got, want := relPrefix("/r/moul"), "../../"; got != want {
		t.Errorf("relPrefix = %q, want %q", got, want)
	}
	// A stylesheet at /public/main.css sits in public/, so /public/x is just x.
	if got := cssRel("/public/main.css"); got != "" {
		t.Errorf("cssRel(/public/main.css) = %q, want \"\"", got)
	}
	// One directory deeper, it has to climb back out.
	if got, want := cssRel("/public/css/main.css"), "../"; got != want {
		t.Errorf("cssRel(/public/css/main.css) = %q, want %q", got, want)
	}
}

func TestRewritePageMakesAppPathsRelative(t *testing.T) {
	html := `<link href="/public/main.css"><a href="/r/moul/other/v0">x</a>` +
		`<a href="/p/moul/md/v0">y</a><link rel="icon" href="/favicon.ico">` +
		`<a href="https://example.org/r/keep/absolute">z</a>`
	got := rewritePage(html, "../../../../")
	for _, want := range []string{
		`href="../../../../public/main.css"`,
		`href="../../../../r/moul/other/v0"`,
		`href="../../../../p/moul/md/v0"`,
		`href="../../../../favicon.ico"`,
		`href="https://example.org/r/keep/absolute"`, // an external URL is left alone
	} {
		if !strings.Contains(got, want) {
			t.Errorf("rewritePage missing %q in:\n%s", want, got)
		}
	}
}

func TestPreviewRealmsSkipsArchivedAndPurePackages(t *testing.T) {
	root := fixture(t, map[string]string{
		"r/moul/live/gnomod.toml": "module = \"gno.land/r/moul/live/v1\"\ngno = \"0.9\"\n",
		"r/moul/old/gnomod.toml":  "module = \"gno.land/r/moul/old/v0\"\nignore = true\n",
		"p/moul/lib/gnomod.toml":  "module = \"gno.land/p/moul/lib/v0\"\n",
	})
	got, err := previewRealms(root, []string{"./..."})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].pkgPath != "gno.land/r/moul/live/v1" {
		t.Fatalf("previewRealms = %+v, want just the live realm", got)
	}
	// The URL carries the version even though the directory no longer does.
	if want := "/r/moul/live/v1"; got[0].urlPath() != want {
		t.Fatalf("urlPath = %q, want %q", got[0].urlPath(), want)
	}
}

// renderPreview against a stub gnoweb: the whole crawl, rewrite and layout,
// without a gno toolchain.
func TestRenderPreviewWritesASelfContainedTree(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/r/moul/hello/v0", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`<html><link href="/public/css/main.css"><img src="/public/logo.png"><a href="/r/moul/other/v0">o</a></html>`))
	})
	mux.HandleFunc("/public/css/main.css", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`@font-face{src:url(/public/fonts/f.woff2)}body{background:url(/public/bg.png)}`))
	})
	mux.HandleFunc("/public/logo.png", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("PNG")) })
	mux.HandleFunc("/public/fonts/f.woff2", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("WOFF")) })
	mux.HandleFunc("/public/bg.png", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("BG")) })
	srv := httptest.NewServer(mux)
	defer srv.Close()

	out := t.TempDir()
	realms := []previewRealm{{pkgPath: "gno.land/r/moul/hello/v0", dir: "r/moul/hello"}}
	if err := renderPreview(srv.URL, out, realms); err != nil {
		t.Fatal(err)
	}

	page := readTestFile(t, filepath.Join(out, "r/moul/hello/v0/index.html"))
	if !strings.Contains(page, `href="../../../../public/css/main.css"`) {
		t.Errorf("page keeps an absolute asset path:\n%s", page)
	}
	if !strings.Contains(page, `href="../../../../r/moul/other/v0"`) {
		t.Errorf("page keeps an absolute realm link:\n%s", page)
	}

	// The CSS was followed for its url()s, and rewritten relative to itself.
	css := readTestFile(t, filepath.Join(out, "public/css/main.css"))
	if !strings.Contains(css, "url(../fonts/f.woff2)") || !strings.Contains(css, "url(../bg.png)") {
		t.Errorf("css not rewritten relative to its own directory:\n%s", css)
	}
	for _, asset := range []string{"public/logo.png", "public/fonts/f.woff2", "public/bg.png"} {
		if !fileExists(filepath.Join(out, asset)) {
			t.Errorf("asset %s not fetched (transitive url() not followed?)", asset)
		}
	}

	index := readTestFile(t, filepath.Join(out, "index.html"))
	if !strings.Contains(index, `href="r/moul/hello/v0/index.html"`) {
		t.Errorf("index does not link the realm:\n%s", index)
	}
}

// A realm that 404s is reported and skipped, not fatal: one broken realm must
// not cost the preview of every other one.
func TestRenderPreviewSurvivesAMissingRealm(t *testing.T) {
	srv := httptest.NewServer(http.NotFoundHandler())
	defer srv.Close()
	out := t.TempDir()
	err := renderPreview(srv.URL, out, []previewRealm{{pkgPath: "gno.land/r/moul/gone/v0", dir: "r/moul/gone"}})
	if err != nil {
		t.Fatalf("a 404 realm was fatal: %v", err)
	}
	if !fileExists(filepath.Join(out, "index.html")) {
		t.Error("no index written")
	}
}

func readTestFile(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestPreviewIndexListsEveryRealm(t *testing.T) {
	got := previewIndex([]previewRealm{
		{pkgPath: "gno.land/r/moul/a/v0"},
		{pkgPath: "gno.land/r/moul/b/v1"},
	})
	if n := strings.Count(got, "<li>"); n != 2 {
		t.Fatalf("index has %d entries, want 2:\n%s", n, got)
	}
}

func TestEnvOr(t *testing.T) {
	t.Setenv("GNOPREVIEW_TEST", "")
	if got := envOr("GNOPREVIEW_TEST", "fallback"); got != "fallback" {
		t.Errorf("envOr with an empty value = %q", got)
	}
	t.Setenv("GNOPREVIEW_TEST", "set")
	if got := envOr("GNOPREVIEW_TEST", "fallback"); got != "set" {
		t.Errorf("envOr = %q", got)
	}
}

func TestWriteLinesRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "out.txt")
	if err := writeLines(path, []string{"--add-label", "p"}); err != nil {
		t.Fatal(err)
	}
	if got, want := readTestFile(t, path), "--add-label\np\n"; got != want {
		t.Fatalf("writeLines = %q, want %q", got, want)
	}
	// An empty path is a no-op, not an error: the flag is optional.
	if err := writeLines("", []string{"x"}); err != nil {
		t.Fatal(err)
	}
	if err := writeLines(path, nil); err != nil {
		t.Fatal(err)
	}
	if got := readTestFile(t, path); got != "" {
		t.Fatalf("writeLines(nil) = %q, want empty", got)
	}
}

func TestProbeClassification(t *testing.T) {
	if !containsAny("dial tcp: connection refused", transportErrors) {
		t.Error("a refused connection is not classified as a transport error")
	}
	if containsAny("package not found", transportErrors) {
		t.Error("a clean 'not found' answer classified as a transport error")
	}
	if !containsAny("query failed: package not found", absentAnswers) {
		t.Error("'not found' not classified as an absent answer")
	}
	// The old implementation matched the bare word "error", which every
	// transport failure also contains — that is how an unreachable chain came
	// to be recorded as hosting nothing.
	if containsAny("error: dial tcp 1.2.3.4:443: i/o timeout", absentAnswers) {
		t.Error("a transport failure classified as proof of absence")
	}
}

func TestNetReachableRejectsAnythingButAChainAnswer(t *testing.T) {
	ok := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/status" {
			t.Errorf("probed %s, want /status", r.URL.Path)
		}
		w.Write([]byte(`{"jsonrpc":"2.0","result":{"node_info":{}}}`))
	}))
	defer ok.Close()
	if !netReachable(ok.URL) {
		t.Error("a chain answering /status reported unreachable")
	}
	if !netReachable(ok.URL + "/") {
		t.Error("a trailing slash in the RPC URL broke the probe")
	}

	down := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "bad gateway", http.StatusBadGateway)
	}))
	defer down.Close()
	if netReachable(down.URL) {
		t.Error("a 502 reported reachable")
	}

	blank := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	defer blank.Close()
	if netReachable(blank.URL) {
		t.Error("an empty 200 reported reachable")
	}
}

func TestSetPublishedLabelsProvenance(t *testing.T) {
	ours := &Contract{PkgPath: "gno.land/r/moul/hello/v0"}
	ours.setPublished("mainnet", true)
	if got := ours.Published["mainnet"]; !got.Uploaded || got.Which != "ours" {
		t.Fatalf("published = %+v, want uploaded/ours", got)
	}
	mirrored := &Contract{PkgPath: "gno.land/p/moul/md/v0", Upstream: "gno.land/p/moul/md"}
	mirrored.setPublished("mainnet", true)
	if got := mirrored.Published["mainnet"]; got.Which != "monorepo" {
		t.Fatalf("which = %q, want monorepo", got.Which)
	}
	mirrored.setPublished("mainnet", false)
	if got := mirrored.Published["mainnet"]; got.Uploaded || got.Which != "" {
		t.Fatalf("published = %+v, want absent with no provenance", got)
	}
}

func TestProbeStatesAreDistinct(t *testing.T) {
	if reflect.DeepEqual(probeAbsent, probeUnknown) {
		t.Fatal("absent and unknown are the same value: the whole point is that they are not")
	}
}
