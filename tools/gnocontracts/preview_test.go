package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
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

func readTestFile(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
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
