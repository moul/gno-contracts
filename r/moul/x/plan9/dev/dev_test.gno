package dev

import (
	"chain/runtime"
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"

	ninep "gno.land/p/moul/x/plan9/ninep/v0"

	nsrealm "gno.land/r/moul/x/plan9/ns/v0"
)

func read(t *testing.T, name string) string {
	t.Helper()
	f, err := tree.Root().Walk(name)
	if err != nil {
		t.Fatalf("walk %s: %v", name, err)
	}
	data, err := ninep.ReadAll(f)
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	return data
}

func TestDevicesFollowTheChain(t *testing.T) {
	if got, want := read(t, "sysname"), runtime.ChainID(); got != want {
		t.Errorf("sysname: got %q, want %q", got, want)
	}
	if got, want := read(t, "domain"), runtime.ChainDomain(); got != want {
		t.Errorf("domain: got %q, want %q", got, want)
	}
	if got, want := read(t, "height"), strconv.FormatInt(runtime.ChainHeight(), 10); got != want {
		t.Errorf("height: got %q, want %q", got, want)
	}

	// A device is code, not storage: advance the chain and the file follows.
	before := read(t, "height")
	testing.SkipHeights(5)
	after := read(t, "height")
	if before == after {
		t.Errorf("height did not move: %q", after)
	}
	b, _ := strconv.ParseInt(before, 10, 64)
	a, _ := strconv.ParseInt(after, 10, 64)
	if a-b != 5 {
		t.Errorf("height moved by %d, want 5", a-b)
	}
}

func TestRandomIsBlockDeterministic(t *testing.T) {
	a := read(t, "random")
	if len(a) != 64 {
		t.Errorf("a sha256 in hex is 64 characters, got %d", len(a))
	}
	if a != read(t, "random") {
		t.Error("two reads in the same block must agree, or Render is a consensus bug")
	}
	testing.SkipHeights(1)
	if a == read(t, "random") {
		t.Error("the value should change with the block")
	}
}

func TestNullAndZero(t *testing.T) {
	if got := read(t, "null"); got != "" {
		t.Errorf("null: %q", got)
	}
	f, _ := tree.Root().Walk("zero")
	got, _ := f.Read(0, 4)
	if got != "\x00\x00\x00\x00" {
		t.Errorf("zero: %q", got)
	}
	// An endless file must not answer an unbounded read with an endless value.
	if got, _ := f.Read(0, -1); got != "" {
		t.Errorf("unbounded read of /dev/zero: %d bytes", len(got))
	}
	if got, _ := f.Read(0, 1<<20); len(got) != 4096 {
		t.Errorf("a huge read should cap at 4096, got %d", len(got))
	}
}

func TestSessionReportsAPlainKey(t *testing.T) {
	got := read(t, "session")
	if got != "session no\nscope full\n" {
		t.Errorf("a plain key has no session scope: %q", got)
	}
}

func TestDriversListsEveryDevice(t *testing.T) {
	got := read(t, "drivers")
	ents, err := tree.Root().ReadDir()
	if err != nil {
		t.Fatalf("readdir: %v", err)
	}
	for _, e := range ents {
		if !strings.Contains(got, e.Name+"\t") {
			t.Errorf("/dev/drivers does not document %q", e.Name)
		}
	}
	if len(ents) != len(docs) {
		t.Errorf("%d devices but %d documented", len(ents), len(docs))
	}
}

func TestTreeIsReadOnly(t *testing.T) {
	var f ninep.File = tree.Root()
	if _, ok := f.(ninep.Mutable); ok {
		t.Error("a device tree handed to other realms must not be Mutable")
	}
}

// TestPostedAtDeployTime is the cross-realm claim the whole suite rests on:
// this realm pushed an interface value into another realm at init, and that
// realm can call it back later from a read.
func TestPostedAtDeployTime(t *testing.T) {
	found := false
	for _, s := range nsrealm.Services() {
		if s == "dev" {
			found = true
		}
	}
	if !found {
		t.Fatalf("dev is not posted in /srv: %v", nsrealm.Services())
	}
}

func TestAFreshNamespaceHasDevBound(cur realm, t *testing.T) {
	user := testutils.TestAddress("glenda")
	testing.SetRealm(testing.NewUserRealm(user))
	nsrealm.Reset(cross(cur))
	// Touch the namespace so it is built with /dev already bound.
	nsrealm.Exec(cross(cur), "echo hi > /tmp/hi")

	out, err := nsrealm.Run(user.String(), "ls /dev")
	if err != nil {
		t.Fatalf("ls /dev: %v", err)
	}
	for _, d := range docs {
		if !strings.Contains(out, d[0]) {
			t.Errorf("ls /dev is missing %q: %q", d[0], out)
		}
	}
	got, err := nsrealm.Run(user.String(), "cat /dev/sysname")
	if err != nil {
		t.Fatalf("cat: %v", err)
	}
	if got != runtime.ChainID() {
		t.Errorf("reading this realm's device through another realm's namespace: %q", got)
	}
	// And the mount table says where it came from.
	if ns := nsrealm.Namespace(user.String()); !strings.Contains(ns, "bind /srv/dev /dev") {
		t.Errorf("mount table: %q", ns)
	}
}
