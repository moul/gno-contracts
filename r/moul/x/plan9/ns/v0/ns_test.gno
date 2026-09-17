package ns

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"

	ninep "gno.land/p/moul/x/plan9/ninep/v0"
	synfs "gno.land/p/moul/x/plan9/synfs/v0"
)

// probe is a tiny read-only server, standing in for another realm's tree.
func probe(name, contents string) ninep.File {
	t := synfs.New(name, "sys", func() int64 { return 1 })
	t.Root().Add("value", func() string { return contents })
	return t.Root()
}

func TestDemoNamespaceIsSeeded(t *testing.T) {
	seedDemo()
	out, err := Run(DemoKey, "ls -u /bin")
	if err != nil {
		t.Fatalf("ls: %v", err)
	}
	if out != "ls\nrc\n" {
		t.Errorf("the demo /bin should be a union of two directories: %q", out)
	}
	if got := Namespace(DemoKey); !strings.Contains(got, "bind -ac /usr/glenda/bin /bin") {
		t.Errorf("mount table: %q", got)
	}
	if got, _ := Run(DemoKey, "cat /tmp/greeting"); got != "hello from a namespace\n" {
		t.Errorf("greeting: %q", got)
	}
}

func TestRunIsReadOnly(t *testing.T) {
	seedDemo()
	if _, err := Run(DemoKey, "echo x > /tmp/f"); err == nil {
		t.Fatal("Render's shell must refuse a write")
	}
	if _, err := Run(DemoKey, "rm /tmp/greeting"); err == nil {
		t.Fatal("Render's shell must refuse a remove")
	}
	if _, err := Run("nobody", "ls /"); err == nil {
		t.Fatal("an unknown namespace should not be created by a read")
	}
}

func TestPostAndBind(cur realm, t *testing.T) {
	services.Remove("probe")
	Post(cross(cur), "probe", probe("probe", "42"))

	found := false
	for _, s := range Services() {
		if s == "probe" {
			found = true
		}
	}
	if !found {
		t.Fatalf("probe is not in /srv: %v", Services())
	}

	// A fresh namespace sees it through /srv without importing anything.
	spaces.Remove("tester")
	spaceFor("tester")
	defer spaces.Remove("tester")
	out, err := Run("tester", "cat /srv/probe/value")
	if err != nil {
		t.Fatalf("cat through /srv: %v", err)
	}
	if out != "42" {
		t.Errorf("got %q, want 42", out)
	}
	services.Remove("probe")
}

func TestExecWritesToTheCallersOwnNamespace(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")
	spaces.Remove(alice.String())
	spaces.Remove(bob.String())

	testing.SetRealm(testing.NewUserRealm(alice))
	Exec(cross(cur), "echo 'alice was here' > /tmp/note")

	testing.SetRealm(testing.NewUserRealm(bob))
	Exec(cross(cur), "echo 'bob was here' > /tmp/note")

	got, err := Run(alice.String(), "cat /tmp/note")
	if err != nil {
		t.Fatalf("alice: %v", err)
	}
	if got != "alice was here\n" {
		t.Errorf("alice's namespace: %q", got)
	}
	if got, _ = Run(bob.String(), "cat /tmp/note"); got != "bob was here\n" {
		t.Errorf("bob's namespace: %q", got)
	}

	// Reset throws a namespace away; the next use rebuilds the default.
	testing.SetRealm(testing.NewUserRealm(alice))
	Reset(cross(cur))
	if _, err := Run(alice.String(), "cat /tmp/note"); err == nil {
		t.Error("the namespace should be gone after Reset")
	}
	spaces.Remove(alice.String())
	spaces.Remove(bob.String())
}

func TestExecBindsIntoTheCallersNamespace(cur realm, t *testing.T) {
	services.Remove("probe")
	Post(cross(cur), "probe", probe("probe", "42"))
	defer services.Remove("probe")

	erin := testutils.TestAddress("erin")
	spaces.Remove(erin.String())
	testing.SetRealm(testing.NewUserRealm(erin))
	Exec(cross(cur), "bind /srv/probe /dev")

	if got := mustRun(t, erin.String(), "cat /dev/value"); got != "42" {
		t.Errorf("read through the mount: %q", got)
	}
	if ns := Namespace(erin.String()); !strings.Contains(ns, "bind /srv/probe /dev") {
		t.Errorf("mount table: %q", ns)
	}
	spaces.Remove(erin.String())
}

func TestSrvListingUsesThePostedName(cur realm, t *testing.T) {
	services.Remove("aliased")
	// The server calls its own root "probe"; /srv must show it as "aliased".
	Post(cross(cur), "aliased", probe("probe", "x"))
	defer services.Remove("aliased")

	spaces.Remove("lister")
	spaceFor("lister")
	out := mustRun(t, "lister", "ls /srv")
	if !strings.Contains(out, "aliased") {
		t.Errorf("ls /srv: %q", out)
	}
	if strings.Contains(out, "probe") {
		t.Errorf("/srv leaked the server's own root name: %q", out)
	}
	spaces.Remove("lister")
}

func mustRun(t *testing.T, key, line string) string {
	t.Helper()
	out, err := Run(key, line)
	if err != nil {
		t.Fatalf("%s: %v", line, err)
	}
	return out
}

// --- the boundary. Three properties the suite would be unsafe without. -------

// A /srv name belongs to the realm that posted it: first come, first served,
// and then locked.
func TestPostRejectsASecondOwner(cur realm, t *testing.T) {
	services.Remove("taken")
	Post(cross(cur), "taken", probe("taken", "first"))
	defer services.Remove("taken")

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/other/thing/v0"))
	uassert.AbortsWithMessage(t, cur,
		"post: taken is already posted by gno.land/r/moul/x/plan9/ns/v0",
		func() { Post(cross(cur), "taken", probe("taken", "second")) })
}

// Grafting another realm's tree into your namespace gives you reads and
// nothing else. ninep.File has no mutating method, so there is no route from a
// mount to a write against the realm that posted it.
func TestMountedTreesAreReadOnly(cur realm, t *testing.T) {
	services.Remove("probe")
	Post(cross(cur), "probe", probe("probe", "read me"))
	defer services.Remove("probe")

	frank := testutils.TestAddress("frank")
	spaces.Remove(frank.String())
	defer spaces.Remove(frank.String())

	testing.SetRealm(testing.NewUserRealm(frank))
	Exec(cross(cur), "bind /srv/probe /dev")
	uassert.Equal(t, "read me", mustRun(t, frank.String(), "cat /dev/value"))
	uassert.AbortsWithMessage(t, cur, "echo: read-only file server",
		func() { Exec(cross(cur), "echo nope > /dev/value") })
}

// A command line stops at the first error and the error leaves the realm as an
// abort, so a half-applied Exec reverts with its transaction instead of
// leaving a namespace nobody asked for.
func TestExecAbortsAtTheFirstError(cur realm, t *testing.T) {
	grace := testutils.TestAddress("grace")
	spaces.Remove(grace.String())
	defer spaces.Remove(grace.String())

	testing.SetRealm(testing.NewUserRealm(grace))
	uassert.AbortsWithMessage(t, cur, "cat: file does not exist",
		func() { Exec(cross(cur), "echo ok > /tmp/a; cat /absent; echo never > /tmp/b") })
}

func TestRenderUnknownCommand(t *testing.T) {
	if got := Render("nope/x"); !strings.Contains(got, "404") {
		t.Errorf("got %q", got)
	}
}
