package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The one invariant the whole tool rests on: the hash computed here and the
// hash computed in r/moul/blog/blog.gno must be the same number, or status
// reports a stale post as up to date and the fix is never pushed.
//
// Pinned as a literal on both sides rather than compared at run time, because
// nothing can run gno and Go in the same test. r/moul/blog/blog_test.go
// asserts the same record for the same fields; this asserts the digest.
func TestRecordHashIsPinnedAgainstTheRealm(t *testing.T) {
	const want = "f7f21778c13782f147643acd7c9df51400272e216248c0fca69e7884cfdf0039"
	got := hashOf(record("A", "2026-01-01", "tooling", "Body A."))
	if got != want {
		t.Fatalf("record hash drifted: got %s, want %s\n"+
			"If this is deliberate, r/moul/blog/blog.gno's record() changed too and "+
			"every post on chain now reads as outdated.", got, want)
	}
}

func TestParsePost(t *testing.T) {
	for _, tc := range []struct {
		name    string
		slug    string
		raw     string
		wantErr string
		title   string
		date    string
		tags    string
		body    string
	}{
		{
			name:  "full",
			slug:  "hello",
			raw:   "---\ntitle: Hello\ndate: 2026-09-23\ntags: Gno, TOOLING, gno\n---\n\nThe body.\n\n",
			title: "Hello", date: "2026-09-23", tags: "gno,tooling", body: "The body.",
		},
		{
			name:  "no tags",
			slug:  "hello",
			raw:   "---\ntitle: Hello\ndate: 2026-09-23\n---\nBody.\n",
			title: "Hello", date: "2026-09-23", tags: "", body: "Body.",
		},
		{name: "no front matter", slug: "x", raw: "Body.\n", wantErr: "no front matter"},
		{name: "unclosed", slug: "x", raw: "---\ntitle: X\n", wantErr: "never closed"},
		{name: "no title", slug: "x", raw: "---\ndate: 2026-09-23\n---\nBody.\n", wantErr: "no `title:`"},
		{name: "bad date", slug: "x", raw: "---\ntitle: X\ndate: 23/09/2026\n---\nBody.\n", wantErr: "YYYY-MM-DD"},
		{name: "no body", slug: "x", raw: "---\ntitle: X\ndate: 2026-09-23\n---\n\n", wantErr: "no body"},
		{name: "bad slug", slug: "Caps", raw: "---\ntitle: X\ndate: 2026-09-23\n---\nBody.\n", wantErr: "not a valid slug"},
		{name: "reserved slug", slug: "intro", raw: "---\ntitle: X\ndate: 2026-09-23\n---\nBody.\n", wantErr: "reserved"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parsePost(tc.slug, "/tmp/"+tc.slug+".md", tc.raw)
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("got err %v, want one containing %q", err, tc.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got.title != tc.title || got.date != tc.date || got.tags != tc.tags || got.body != tc.body {
				t.Fatalf("got %+v, want title=%q date=%q tags=%q body=%q",
					got, tc.title, tc.date, tc.tags, tc.body)
			}
		})
	}
}

// A body must reach the chain byte for byte. Normalization strips trailing
// newlines and NOTHING else, because anything else it strips is a hash the
// realm will not agree with.
func TestNormalizeOnlyTrimsTrailingNewlines(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"a\n", "a"},
		{"a\n\n\n", "a"},
		{"a  \n", "a  "},         // trailing spaces survive
		{"\n\na\nb", "\n\na\nb"}, // leading and interior newlines survive
	} {
		if got := normalize(tc.in); got != tc.want {
			t.Fatalf("normalize(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func writeContent(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestLoadPostsSeparatesTheIntro(t *testing.T) {
	dir := writeContent(t, map[string]string{
		"intro.md":  "# moul\n\nHi.\n",
		"hello.md":  "---\ntitle: Hello\ndate: 2026-09-01\n---\nOne.\n",
		"later.md":  "---\ntitle: Later\ndate: 2026-09-23\n---\nTwo.\n",
		"notes.txt": "ignored",
	})
	posts, err := loadPosts(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(posts) != 3 {
		t.Fatalf("got %d entries, want 3 (two posts and the intro)", len(posts))
	}
	if countPosts(posts) != 2 {
		t.Fatalf("countPosts = %d, want 2: the intro is not a post", countPosts(posts))
	}
}

func TestNewestFirst(t *testing.T) {
	dir := writeContent(t, map[string]string{
		"intro.md": "Header.\n",
		"a.md":     "---\ntitle: A\ndate: 2026-01-01\n---\nOne.\n",
		"b.md":     "---\ntitle: B\ndate: 2026-09-23\n---\nTwo.\n",
		"c.md":     "---\ntitle: C\ndate: 2026-09-23\n---\nThree.\n",
	})
	posts, err := loadPosts(dir)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, p := range newestFirst(posts) {
		got = append(got, p.slug)
	}
	// Same date: the slug breaks the tie, descending, exactly as the realm's
	// "<date>/<slug>" key does when walked in reverse.
	want := []string{"c", "b", "a"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("order = %v, want %v", got, want)
	}
}

func TestDiff(t *testing.T) {
	local := []postFile{
		{slug: "same", body: "x", hash: "h1"},
		{slug: "changed", body: "y", hash: "h2-local"},
		{slug: "new", body: "z", hash: "h3"},
	}
	remote := map[string]remotePost{
		"same":    {hash: "h1"},
		"changed": {hash: "h2-chain"},
		"gone":    {hash: "h4", size: 9},
		introKey:  {hash: "hi"},
	}
	got := map[string]string{}
	for _, c := range diff(local, remote) {
		got[c.slug] = c.kind
	}
	want := map[string]string{"changed": kindOutdated, "new": kindMissing, "gone": kindExtra}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for slug, kind := range want {
		if got[slug] != kind {
			t.Fatalf("%s: got %q, want %q", slug, got[slug], kind)
		}
	}
	if _, ok := got[introKey]; ok {
		t.Fatal("the intro row must never be reported as an extra: there is no Delete for it")
	}
}

func TestParseManifest(t *testing.T) {
	raw := "!intro\t0\t\t7\thi\nhello\t3\t2026-09-01\t42\tdeadbeef\n"
	got, err := parseManifest(raw)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("got %d rows, want 2", len(got))
	}
	p := got["hello"]
	if p.rev != 3 || p.date != "2026-09-01" || p.size != 42 || p.hash != "deadbeef" {
		t.Fatalf("hello = %+v", p)
	}
	if _, err := parseManifest("too\tfew\tfields\n"); err == nil {
		t.Fatal("a short manifest line must be an error, not a silently empty post")
	}
}

func TestMsgForCarriesEveryField(t *testing.T) {
	cfg := config{realm: defaultRealm, owner: defaultOwner}
	p := postFile{slug: "hello", title: "Hello", date: "2026-09-23", tags: "gno", body: "Body."}

	m := msgFor(cfg, change{kind: kindMissing, slug: p.slug, post: p}, txOptions{})
	if m.Func != "Set" {
		t.Fatalf("Func = %q, want Set", m.Func)
	}
	want := []string{"hello", "Hello", "2026-09-23", "gno", "Body."}
	if strings.Join(m.Args, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("args = %q, want %q", m.Args, want)
	}

	intro := postFile{slug: introKey, body: "# Header"}
	mi := msgFor(cfg, change{kind: kindMissing, slug: introKey, post: intro}, txOptions{})
	if mi.Func != "SetIntro" || len(mi.Args) != 1 || mi.Args[0] != "# Header" {
		t.Fatalf("intro message = %+v, want SetIntro with the body alone", mi)
	}

	md := msgFor(cfg, change{kind: kindExtra, slug: "gone"}, txOptions{})
	if md.Func != "Delete" || len(md.Args) != 1 || md.Args[0] != "gone" {
		t.Fatalf("delete message = %+v", md)
	}
}

// The body travels as a JSON string, which is the whole reason tx emits a
// document instead of a shell command: a post is kilobytes of markdown full of
// quotes, backticks and newlines, and none of it is quoted for a shell.
func TestBatchBodySurvivesJSON(t *testing.T) {
	body := "A line with 'quotes', \"doubles\", `backticks`, $(not a command) and\ntwo lines.\n\nAnd a $VAR."
	cfg := config{realm: defaultRealm, owner: defaultOwner}
	p := postFile{slug: "tricky", title: "T", date: "2026-09-23", body: normalize(body)}

	doc, _, err := buildBatch(cfg, []change{{kind: kindMissing, slug: p.slug, post: p}}, txOptions{})
	if err != nil {
		t.Fatal(err)
	}
	var m callMsg
	if err := json.Unmarshal(doc.Msg[0], &m); err != nil {
		t.Fatal(err)
	}
	if m.Args[4] != normalize(body) {
		t.Fatalf("body round-trip lost bytes:\n got %q\nwant %q", m.Args[4], normalize(body))
	}
}

func TestBuildBatchIsEmptyWhenNothingChanged(t *testing.T) {
	doc, _, err := buildBatch(config{}, nil, txOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if doc != nil {
		t.Fatal("no changes must produce no document, so nothing gets signed for nothing")
	}
}

func TestFeeTracksGas(t *testing.T) {
	// The mempool enforces the ratio, so the fee must move with the ceiling.
	if got := feeFor(gasFor(0)); got != "25000ugnot" {
		t.Fatalf("fee for an empty body = %s, want 25000ugnot", got)
	}
	if feeFor(gasFor(10_000)) == feeFor(gasFor(0)) {
		t.Fatal("a larger body must cost more gas, and therefore more fee")
	}
	if feeFor(1) != "1ugnot" {
		t.Fatal("the fee must never round down to zero")
	}
}

func TestPreviewOrderMatchesTheRealm(t *testing.T) {
	dir := writeContent(t, map[string]string{
		"intro.md": "# moul\n",
		"old.md":   "---\ntitle: Old\ndate: 2026-01-01\n---\n# Heading\n\nOld prose.\n",
		"new.md":   "---\ntitle: New\ndate: 2026-09-23\ntags: gno\n---\nNew prose.\n",
	})
	posts, err := loadPosts(dir)
	if err != nil {
		t.Fatal(err)
	}
	out := preview(posts, "")
	iNew, iOld := strings.Index(out, "New"), strings.Index(out, "Old")
	if iNew < 0 || iOld < 0 || iNew > iOld {
		t.Fatalf("the newer post must render first:\n%s", out)
	}
	if !strings.Contains(out, "# moul") {
		t.Fatal("intro.md must render as the header")
	}
	if !strings.Contains(out, "Old prose.") || strings.Contains(out, "## [Old](/r/moul/blog:old)\n\n2026-01-01\n\n# Heading") {
		t.Fatal("the excerpt must skip the post's own heading")
	}
	if !strings.Contains(out, "[#gno](/r/moul/blog:t/gno)") {
		t.Fatal("tags must render as links into the tag view")
	}
}

// --- publishing, not printing ------------------------------------------------

// gnoblog tx has to sign and broadcast, not hand back two lines to paste. The
// paste is what makes a document go stale: the signature covers the account
// sequence, so anything else this key signs between the read and the paste
// voids it.
func TestRunClientRunsSignThenBroadcast(t *testing.T) {
	prev := startClient
	t.Cleanup(func() { startClient = prev })

	var ran [][]string
	startClient = func(name string, args []string) error {
		if name != "gnokey" {
			t.Fatalf("ran %q, want gnokey", name)
		}
		ran = append(ran, append([]string(nil), args...))
		return nil
	}
	cmds := []clientCmd{
		{what: "sign x", name: "gnokey", args: []string{"sign", "-tx-path", "/tmp/x.json"}},
		{what: "broadcast x", name: "gnokey", args: []string{"broadcast", "/tmp/x.json"}},
	}
	if err := runClient(cmds); err != nil {
		t.Fatal(err)
	}
	if len(ran) != 2 || ran[0][0] != "sign" || ran[1][0] != "broadcast" {
		t.Fatalf("ran %v, want sign then broadcast", ran)
	}
}

// A failed sign must not be followed by a broadcast. `gnokey broadcast` does
// not refuse an unsigned document locally: it sends it and lets the chain
// reject it, which is a pointless round trip for a mistake visible on disk.
func TestRunClientStopsAfterAFailedSign(t *testing.T) {
	prev := startClient
	t.Cleanup(func() { startClient = prev })

	calls := 0
	startClient = func(string, []string) error {
		calls++
		return errors.New("no such key")
	}
	err := runClient([]clientCmd{
		{what: "sign x", name: "gnokey", args: []string{"sign"}},
		{what: "broadcast x", name: "gnokey", args: []string{"broadcast"}},
	})
	if err == nil {
		t.Fatal("a failed sign reported success")
	}
	if calls != 1 {
		t.Fatalf("ran %d command(s) after a failed sign, want 1", calls)
	}
	if !strings.Contains(err.Error(), "step 1 of 2") {
		t.Fatalf("the error must say which step failed, got: %v", err)
	}
}

func TestQuoteAll(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"sign", "sign"},
		{"/tmp/x.json", "/tmp/x.json"},
		{"", "''"},
		{"a b", "'a b'"},
		{"$(x)", "'$(x)'"},
	} {
		if got := quoteAll([]string{tc.in})[0]; got != tc.want {
			t.Fatalf("quoteAll(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
