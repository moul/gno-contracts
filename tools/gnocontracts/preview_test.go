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

// The three answers below are verbatim gnokey output, captured against
// gnoland-1 on 2026-09-28. The parked one is the case a vm/qfile probe could
// not see at all: it reported "not available", the same as a path nobody ever
// published.
func TestParsePkgMetaReadsTheThreeChainStates(t *testing.T) {
	for _, tc := range []struct {
		name   string
		out    string
		status string
		ok     bool
	}{
		{
			name:   "live",
			out:    "height: 0\ndata: {\"path\":\"gno.land/p/moul/md/v0\",\"status\":\"live\",\"creator\":\"g1manfred47kzduec920z88wfr64ylksmdcedlf5\"}\n",
			status: "live", ok: true,
		},
		{
			name:   "parked behind the submission policy",
			out:    "height: 0\ndata: {\"path\":\"gno.land/r/x/bazaar/genesis\",\"status\":\"inert\",\"height\":344670,\"max_deposit\":\"40000000ugnot\",\"reason\":\"waiting for a package approver to enable it\",\"pending\":true}\n",
			status: "inert", ok: true,
		},
		{
			name:   "absent",
			out:    "height: 0\ndata: {\"path\":\"gno.land/p/moul/nope/v0\",\"status\":\"absent\"}\n",
			status: "absent", ok: true,
		},
		{name: "a chain that does not implement the query", out: "unknown request: vm/qpkgmeta_json\n"},
		{name: "empty", out: ""},
		{name: "json without a status field", out: "data: {\"path\":\"gno.land/p/moul/md/v0\"}"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m, ok := parsePkgMeta([]byte(tc.out))
			if ok != tc.ok {
				t.Fatalf("parsePkgMeta ok = %v, want %v", ok, tc.ok)
			}
			if m.Status != tc.status {
				t.Fatalf("status = %q, want %q", m.Status, tc.status)
			}
		})
	}
}

// Anything unparseable must read as unknown, never as absent: recording an
// absence we did not observe is what wipes a network's whole column.
func TestQueryPkgStatusMapsEveryState(t *testing.T) {
	for out, want := range map[string]probe{
		`data: {"path":"p","status":"live"}`:                 probePresent,
		`data: {"path":"p","status":"inert","pending":true}`: probeParked,
		`data: {"path":"p","status":"absent"}`:               probeAbsent,
		`data: {"path":"p","status":"something-new"}`:        probeUnknown,
		`unknown request`:                                    probeUnknown,
	} {
		m, ok := parsePkgMeta([]byte(out))
		got := probeUnknown
		if ok {
			switch m.Status {
			case "live":
				got = probePresent
			case "inert":
				got = probeParked
			case "absent":
				got = probeAbsent
			}
		}
		if got != want {
			t.Errorf("%s -> %v, want %v", out, got, want)
		}
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
	ours.setPublished("mainnet", probePresent)
	if got := ours.Published["mainnet"]; !got.Uploaded || got.Which != "ours" {
		t.Fatalf("published = %+v, want uploaded/ours", got)
	}
	mirrored := &Contract{PkgPath: "gno.land/p/moul/md/v0", Upstream: "gno.land/p/moul/md"}
	mirrored.setPublished("mainnet", probePresent)
	if got := mirrored.Published["mainnet"]; got.Which != "monorepo" {
		t.Fatalf("which = %q, want monorepo", got.Which)
	}
	mirrored.setPublished("mainnet", probeAbsent)
	if got := mirrored.Published["mainnet"]; got.Uploaded || got.Which != "" || got.State != "" {
		t.Fatalf("published = %+v, want absent with no provenance", got)
	}

	// A parked package is not live, so it carries no provenance and no link,
	// but it is emphatically not the same as never having been sent.
	queued := &Contract{PkgPath: "gno.land/r/moul/queued/v0"}
	queued.setPublished("mainnet", probeParked)
	if got := queued.Published["mainnet"]; got.Uploaded || got.State != "inert" || got.Which != "" {
		t.Fatalf("published = %+v, want a parked entry", got)
	}
}

// gnokey prints "height: N" then "data: " followed by the FIRST path, with the
// rest on their own lines. Captured from gnoland-1 on 2026-09-28.
func TestQueryPathSetReadsGnokeyListOutput(t *testing.T) {
	out := "height: 0\ndata: gno.land/p/moul/md/v0\ngno.land/r/moul/hello/v0\nbufio\n\n"
	set, ok := parsePathSet(out)
	if !ok {
		t.Fatal("a well formed list read as a failure")
	}
	if len(set) != 3 {
		t.Fatalf("got %d paths, want 3 (the stdlib entry is kept, it cannot collide with a full pkgpath)", len(set))
	}
	for _, want := range []string{"gno.land/p/moul/md/v0", "gno.land/r/moul/hello/v0", "bufio"} {
		if !set[want] {
			t.Errorf("%q missing from the set", want)
		}
	}

	// An empty answer is a real answer: a chain with nothing parked returns a
	// "data:" line with nothing after it, and that must not read as a failure,
	// or every package on it would be recorded parked-unknown.
	empty, ok := parsePathSet("height: 0\ndata: \n")
	if !ok {
		t.Fatal("an empty set read as a failure")
	}
	if len(empty) != 0 {
		t.Fatalf("empty set has %d entries", len(empty))
	}

	// No data marker at all means the chain did not answer this query.
	if _, ok := parsePathSet("--= Error =--\nunknown request\n"); ok {
		t.Fatal("an error read as an answer: every contract would be classified from it")
	}
}

// A chain index classifies from two disjoint sets, and anything in neither is
// absent. That last case is the whole reason two queries can replace one per
// package.
func TestChainIndexLookupCoversAllThree(t *testing.T) {
	idx := chainIndex{
		live:   map[string]bool{"gno.land/p/moul/md/v0": true},
		parked: map[string]bool{"gno.land/r/moul/queued/v0": true},
	}
	for path, want := range map[string]probe{
		"gno.land/p/moul/md/v0":     probePresent,
		"gno.land/r/moul/queued/v0": probeParked,
		"gno.land/r/moul/never/v0":  probeAbsent,
	} {
		if got := idx.lookup(path); got != want {
			t.Errorf("lookup(%s) = %v, want %v", path, got, want)
		}
	}
}

func TestProbeStatesAreDistinct(t *testing.T) {
	if reflect.DeepEqual(probeAbsent, probeUnknown) {
		t.Fatal("absent and unknown are the same value: the whole point is that they are not")
	}
	seen := map[probe]bool{}
	for _, p := range []probe{probeAbsent, probePresent, probeUnknown, probeParked} {
		if seen[p] {
			t.Fatalf("two probe states share the value %d", p)
		}
		seen[p] = true
	}
}
