package ns

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"

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

func TestRenderUnknownCommand(t *testing.T) {
	if got := Render("nope/x"); !strings.Contains(got, "404") {
		t.Errorf("got %q", got)
	}
}
