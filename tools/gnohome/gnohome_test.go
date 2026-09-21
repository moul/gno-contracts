package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestNormalizeMakesCatFaithful(t *testing.T) {
	// The whole point: `"$(cat file)"` eats trailing newlines and nothing else,
	// so normalize must do exactly the same. Anything more aggressive makes the
	// local hash and the chain's disagree forever.
	cases := map[string]string{
		"hello\n":     "hello",
		"hello\n\n\n": "hello",
		"":            "",
		"\n":          "",
		// Trailing spaces are KEPT: `cat` would send them, so stripping them
		// here would make the local hash disagree with the chain's forever.
		"trailing  \t ": "trailing  \t ",
		"a\nb  \n":      "a\nb  ",
	}
	for in, want := range cases {
		if got := normalize(in); got != want {
			t.Errorf("normalize(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestValidSlugMatchesTheRealm(t *testing.T) {
	ok := []string{"bio", "now", "latest_packages", "now.2026-09", strings.Repeat("a", maxSlugLen)}
	for _, s := range ok {
		if !validSlug(s) {
			t.Errorf("validSlug(%q) = false, want true", s)
		}
	}
	bad := []string{"", "Bio", "a b", "a:b", "a/b", strings.Repeat("a", maxSlugLen+1)}
	for _, s := range bad {
		if validSlug(s) {
			t.Errorf("validSlug(%q) = true, want false", s)
		}
	}
}

func TestLoadSlotsRejectsCarriageReturns(t *testing.T) {
	// CRLF cannot round-trip through the emitted "$(cat …)", so it is refused
	// at load time rather than silently folded into a permanent diff.
	dir := t.TempDir()
	write(t, dir, "bio.md", "a\r\nb\r\n")
	if _, err := loadSlots(dir); err == nil || !strings.Contains(err.Error(), "carriage return") {
		t.Fatalf("loadSlots error = %v, want a 'carriage return' error", err)
	}
}

func TestLoadSlotsRejectsReservedNames(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "height.md", "boom")
	if _, err := loadSlots(dir); err == nil || !strings.Contains(err.Error(), "reserved") {
		t.Fatalf("loadSlots error = %v, want a 'reserved' error", err)
	}
}

func TestLoadSlotsSkipsNonMarkdown(t *testing.T) {
	dir := t.TempDir()
	write(t, dir, "bio.md", "hi\n")
	write(t, dir, "notes.txt", "ignored")
	if err := os.Mkdir(filepath.Join(dir, "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	write(t, filepath.Join(dir, "sub"), "nested.md", "ignored too")

	slots, err := loadSlots(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(slots) != 1 || slots[0].slug != "bio" || slots[0].body != "hi" {
		t.Fatalf("got %+v, want a single normalized bio slot", slots)
	}
}

func TestRenderMirrorsTheRealm(t *testing.T) {
	slots := []slotFile{
		{slug: "bio", body: "Building on gno."},
		{slug: "layout", body: "# :owner:\n\n:bio:\n\n:missing:\n"},
	}
	got := render(slots, env{owner: "g1abc", realm: "gno.land/r/moul/home", chainID: "gnoland-1"})
	want := "# g1abc\n\nBuilding on gno.\n\n:missing:\n"
	if got != want {
		t.Errorf("render() = %q, want %q", got, want)
	}
}

func TestRenderDoesNotRecurse(t *testing.T) {
	// Same guarantee the realm gives: one pass, so a body that looks like a
	// placeholder stays as written.
	slots := []slotFile{
		{slug: "a", body: ":b:"},
		{slug: "b", body: "should not appear"},
		{slug: "layout", body: ":a:"},
	}
	if got := render(slots, env{}); got != ":b:" {
		t.Errorf("render() = %q, want %q", got, ":b:")
	}
}

func TestRenderFallsBackToTheDefaultLayout(t *testing.T) {
	got := render(nil, env{chainID: "gnoland-1"})
	if !strings.Contains(got, "No layout slot yet") {
		t.Errorf("render() without a layout slot = %q", got)
	}
	for _, p := range []string{":slots:", ":rev:", ":height:", ":chainid:"} {
		if strings.Contains(got, p) {
			t.Errorf("the default layout left %s unresolved", p)
		}
	}
}

func TestParseManifest(t *testing.T) {
	raw := "alpha\t3\t0\te3b0\nbio\t7\t5\t2cf2\n"
	got, err := parseManifest(raw)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("got %d entries, want 2", len(got))
	}
	if got["bio"] != (remoteSlot{rev: 7, size: 5, hash: "2cf2"}) {
		t.Errorf("bio = %+v", got["bio"])
	}
	if _, err := parseManifest("too\tfew\n"); err == nil {
		t.Error("a malformed line must be an error, not a silent skip")
	}
}

func TestUnwrapString(t *testing.T) {
	got, err := unwrapString("(\"a\\tb\\n\" string)")
	if err != nil {
		t.Fatal(err)
	}
	if got != "a\tb\n" {
		t.Errorf("unwrapString = %q", got)
	}
	if _, err := unwrapString("not a value"); err == nil {
		t.Error("an unexpected shape must be an error")
	}
}

func TestDiffClassifies(t *testing.T) {
	local := []slotFile{
		{slug: "same", body: "x", hash: "aaaa"},
		{slug: "changed", body: "y", hash: "bbbb"},
		{slug: "new", body: "z", hash: "cccc"},
	}
	remote := map[string]remoteSlot{
		"same":    {hash: "aaaa", size: 1, rev: 1},
		"changed": {hash: "ffff", size: 1, rev: 2},
		"gone":    {hash: "dddd", size: 4, rev: 3},
	}
	got := diff(local, remote)
	want := map[string]string{"changed": kindOutdated, "new": kindMissing, "gone": kindExtra}
	if len(got) != len(want) {
		t.Fatalf("got %d changes, want %d: %+v", len(got), len(want), got)
	}
	for _, c := range got {
		if want[c.slug] != c.kind {
			t.Errorf("%s classified as %s, want %s", c.slug, c.kind, want[c.slug])
		}
	}
}

func TestCommandQuotesAndTargetsTheRightFunc(t *testing.T) {
	cfg := config{realm: "gno.land/r/moul/home", chainID: "gnoland-1", remote: "https://rpc.gno.land:443", key: "moul"}

	set := command(cfg, change{kind: kindMissing, slug: "bio", detail: "new",
		slot: slotFile{slug: "bio", path: "/tmp/it's here/bio.md", body: "hi"}}, txOptions{gasFee: "1000000ugnot"})
	if !strings.Contains(set, "-func Set") {
		t.Error("a missing slot must emit Set")
	}
	if !strings.Contains(set, `"$(/bin/cat '/tmp/it'\''s here/bio.md')"`) {
		t.Errorf("the path must be shell-quoted, got:\n%s", set)
	}
	if !strings.HasSuffix(set, "  moul\n") {
		t.Errorf("the command must end with the key name, got:\n%s", set)
	}

	del := command(cfg, change{kind: kindExtra, slug: "gone", detail: "orphan"}, txOptions{gasFee: "1000000ugnot"})
	if !strings.Contains(del, "-func Delete") {
		t.Error("an extra slot must emit Delete")
	}
	if strings.Contains(del, "$(/bin/cat") {
		t.Error("Delete takes no body")
	}

	inline := command(cfg, change{kind: kindOutdated, slug: "bio", detail: "changed",
		slot: slotFile{slug: "bio", body: "it's\nmultiline"}}, txOptions{inline: true, gasFee: "1000000ugnot"})
	if !strings.Contains(inline, `'it'\''s`+"\nmultiline'") {
		t.Errorf("an inline body must be shell-quoted verbatim, got:\n%s", inline)
	}
}

func TestGasGrowsWithTheBody(t *testing.T) {
	if gasFor(0) >= gasFor(1000) {
		t.Error("gas must grow with the body size")
	}
}

func write(t *testing.T, dir, name, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// testCatalog is a miniature contracts.json exercising every branch of the
// packages generator: a two-version family, a family whose latest version is
// NOT deployed, a nested name, a name that collides on its last segment, an
// x/daily entry of each kind, and a contract on no network at all.
func testCatalog() *catalog {
	entry := func(path, kind, name, version string, nets ...string) catalogEntry {
		e := catalogEntry{PkgPath: path, Kind: kind, Name: name, Version: version}
		e.Published = map[string]struct {
			Uploaded bool `json:"uploaded"`
		}{}
		for _, n := range nets {
			e.Published[n] = struct {
				Uploaded bool `json:"uploaded"`
			}{Uploaded: true}
		}
		return e
	}
	return &catalog{Contracts: []catalogEntry{
		entry("gno.land/p/moul/addrset/v0", "p", "addrset", "v0", "mainnet"),
		entry("gno.land/p/moul/addrset/v1", "p", "addrset", "v1", "mainnet"),
		// v10 must beat v9: a string sort gets this backwards.
		entry("gno.land/p/moul/md/v9", "p", "md", "v9", "mainnet"),
		entry("gno.land/p/moul/md/v10", "p", "md", "v10", "mainnet"),
		// The newest version is only on pearl, so mainnet must show v0.
		entry("gno.land/p/moul/svg/v0", "p", "svg", "v0", "mainnet"),
		entry("gno.land/p/moul/svg/v1", "p", "svg", "v1", "pearl"),
		entry("gno.land/p/moul/ulist/lplist/v0", "p", "ulist/lplist", "v0", "mainnet"),
		entry("gno.land/r/moul/hello/v0", "r", "hello", "v0", "mainnet"),
		entry("gno.land/r/moul/demo/hello/v0", "r", "demo/hello", "v0", "mainnet"),
		entry("gno.land/p/moul/x/daily/b58/v0", "p", "x/daily/b58", "v0", "mainnet"),
		entry("gno.land/r/moul/x/daily/counter/v0", "r", "x/daily/counter", "v0", "mainnet"),
		entry("gno.land/r/moul/x/daily/wordle/v0", "r", "x/daily/wordle", "v0", "mainnet"),
		// Deployed nowhere: must not be counted or listed.
		entry("gno.land/r/moul/unreleased/v0", "r", "unreleased", "v0"),
	}}
}

func TestLatestOnNetworkPicksHighestDeployedVersion(t *testing.T) {
	got := map[string]string{}
	for _, e := range latestOnNetwork(testCatalog(), "mainnet") {
		got[e.Kind+"/"+e.Name] = e.Version
	}
	want := map[string]string{
		"p/addrset":         "v1",
		"p/md":              "v10", // numeric, not lexical: v10 > v9
		"p/svg":             "v0",  // v1 is on pearl only
		"p/ulist/lplist":    "v0",
		"r/hello":           "v0",
		"r/demo/hello":      "v0",
		"p/x/daily/b58":     "v0",
		"r/x/daily/counter": "v0",
		"r/x/daily/wordle":  "v0",
	}
	if len(got) != len(want) {
		t.Fatalf("got %d families %v, want %d", len(got), got, len(want))
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %q, want %q", k, got[k], v)
		}
	}
}

func TestRenderPackagesCountsAndLabels(t *testing.T) {
	body := renderPackages(testCatalog(), "mainnet")

	// 4 libraries (addrset, md, svg, ulist/lplist) + 2 realms (hello,
	// demo/hello) + 3 experiments = 9, with the undeployed one excluded.
	for _, want := range []string{
		"9 packages of mine are live on mainnet",
		"**Libraries** (4):",
		"**Realms** (2):",
		// One experiment library, so the noun is singular.
		"**Daily experiments** (3): one package a day, 1 library and 2 realms",
		"[addrset](/p/moul/addrset/v1)",
		"[ulist/lplist](/p/moul/ulist/lplist/v0)",
		// The two hellos must stay distinguishable.
		"[hello](/r/moul/hello/v0)",
		"[demo/hello](/r/moul/demo/hello/v0)",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("missing %q in:\n%s", want, body)
		}
	}
	for _, unwanted := range []string{"unreleased", "x/daily/counter", "/p/moul/md/v9"} {
		if strings.Contains(body, unwanted) {
			t.Errorf("unexpected %q in:\n%s", unwanted, body)
		}
	}
	if strings.HasSuffix(body, "\n") {
		t.Error("body must not end in a newline: normalize() would strip it and the hashes would disagree")
	}
}

// The generated slot is pushed on chain, so two runs over an unchanged catalog
// have to produce identical bytes. Map iteration order is the hazard.
func TestRenderPackagesIsDeterministic(t *testing.T) {
	first := renderPackages(testCatalog(), "mainnet")
	for i := 0; i < 20; i++ {
		if got := renderPackages(testCatalog(), "mainnet"); got != first {
			t.Fatalf("run %d differs:\n%s\n---\n%s", i, first, got)
		}
	}
}

func TestVersionNum(t *testing.T) {
	cases := map[string]int{"v0": 0, "v1": 1, "v10": 10, "": -1, "v": -1, "vx": -1, "1": -1}
	for in, want := range cases {
		if got := versionNum(in); got != want {
			t.Errorf("versionNum(%q) = %d, want %d", in, got, want)
		}
	}
}

func TestLoadCatalogRejectsGarbage(t *testing.T) {
	dir := t.TempDir()
	empty := filepath.Join(dir, "empty.json")
	if err := os.WriteFile(empty, []byte(`{"contracts":[]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := loadCatalog(empty); err == nil {
		t.Error("an empty catalog must be an error, not a silently blank slot")
	}
	bad := filepath.Join(dir, "bad.json")
	if err := os.WriteFile(bad, []byte(`{`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := loadCatalog(bad); err == nil {
		t.Error("malformed JSON must be an error")
	}
}

// The fee is a ratio against gas-wanted, not an absolute: the mempool compares
// fee/gas_wanted (EnsureSufficientMempoolFees), the accepted floor on mainnet
// is 0.001 ugnot/gas, and gas_fee is deducted in full and never refunded. Ten
// times the floor is the target.
func TestFeeForTracksTheCeiling(t *testing.T) {
	cases := map[int64]string{
		10_000_000: "100000ugnot",
		53_683_200: "536832ugnot",
		1_000:      "10ugnot",
		1:          "1ugnot", // never zero: a zero fee is rejected outright
		0:          "1ugnot",
	}
	for gas, want := range cases {
		if got := feeFor(gas); got != want {
			t.Errorf("feeFor(%d) = %s, want %s", gas, got, want)
		}
	}
	// The ratio must sit an order of magnitude above the floor, not at it.
	const gas = 20_000_000
	fee, err := strconv.ParseInt(strings.TrimSuffix(feeFor(gas), "ugnot"), 10, 64)
	if err != nil {
		t.Fatal(err)
	}
	if ratio := float64(fee) / float64(gas); ratio < 0.009 || ratio > 0.011 {
		t.Errorf("ratio %.4f ugnot/gas, want ~0.01", ratio)
	}
}

// One transaction carrying every change, so the whole page updates on one
// signature. Unit tests could not see the two things that matter here, so
// they are asserted against the shape gnokey actually emitted: the message
// type string and the field names. Both were captured from
// `gnokey maketx call -broadcast=false`, and a two-message merge of that
// output was signed successfully before this was written.
func TestBuildBatchIsOneTxForEveryChange(t *testing.T) {
	cfg := config{realm: "gno.land/r/moul/home", owner: "g1owner", key: "moul"}
	changes := []change{
		{kind: kindMissing, slug: "bio", slot: slotFile{slug: "bio", body: "hello\nworld"}},
		{kind: kindOutdated, slug: "now", slot: slotFile{slug: "now", body: "x"}},
		{kind: kindExtra, slug: "gone"},
	}
	doc, gas, err := buildBatch(cfg, changes, txOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if len(doc.Msg) != 3 {
		t.Fatalf("got %d messages, want one per change", len(doc.Msg))
	}
	var msgs []callMsg
	for _, raw := range doc.Msg {
		var m callMsg
		if err := json.Unmarshal(raw, &m); err != nil {
			t.Fatal(err)
		}
		msgs = append(msgs, m)
	}
	if msgs[0].Type != "/vm.m_call" {
		t.Errorf("type = %q, want /vm.m_call", msgs[0].Type)
	}
	if msgs[0].Caller != "g1owner" || msgs[0].PkgPath != "gno.land/r/moul/home" {
		t.Errorf("msg = %+v", msgs[0])
	}
	// The body travels verbatim: no shell, so the newline that command
	// substitution would have eaten is still there. That is the whole reason
	// this path is safer than the one-command-per-slot path.
	if got := msgs[0].Args; len(got) != 2 || got[0] != "bio" || got[1] != "hello\nworld" {
		t.Errorf("args = %q, want the slug and the body byte for byte", got)
	}
	// A slot on chain with no local file is a Delete, and carries no body.
	if msgs[2].Func != "Delete" {
		t.Errorf("extra slot func = %q, want Delete", msgs[2].Func)
	}
	if len(msgs[2].Args) != 1 {
		t.Errorf("Delete args = %q, want just the slug", msgs[2].Args)
	}
	// Gas is the sum: the chain meters the transaction, not the message.
	want := gasFor(len("hello\nworld")) + gasFor(len("x")) + gasFor(0)
	if gas != want {
		t.Errorf("gas = %d, want the sum %d", gas, want)
	}
	if doc.Fee.GasWanted != strconv.FormatInt(gas, 10) {
		t.Errorf("fee.gas_wanted = %q, want %d", doc.Fee.GasWanted, gas)
	}
	if doc.Fee.GasFee != feeFor(gas) {
		t.Errorf("fee.gas_fee = %q, want %q", doc.Fee.GasFee, feeFor(gas))
	}
	if doc.Signatures != nil {
		t.Error("a document gnopm writes must be unsigned")
	}
}

func TestBuildBatchOnNoChangesIsNoDocument(t *testing.T) {
	doc, _, err := buildBatch(config{}, nil, txOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if doc != nil {
		t.Error("no changes must produce no document, not an empty transaction")
	}
}
