package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// untrustedFixture builds a workspace of realms. Each entry is
// "<dir>": "<the realm's single .gno file>", and every dir gets a gnomod.
func untrustedFixture(t *testing.T, realms map[string]string, baseline string) string {
	t.Helper()
	root := t.TempDir()
	writeFile(t, root, "gnowork.toml", "")
	for dir, body := range realms {
		full := filepath.Join(root, filepath.FromSlash(dir))
		if err := os.MkdirAll(full, 0o755); err != nil {
			t.Fatal(err)
		}
		writeFile(t, full, "gnomod.toml", mod("gno.land/"+dir+"/v0"))
		writeFile(t, full, "realm.gno", body)
	}
	if baseline != "" {
		full := filepath.Join(root, "tools", "gnocontracts")
		if err := os.MkdirAll(full, 0o755); err != nil {
			t.Fatal(err)
		}
		writeFile(t, full, "untrusted-render-baseline.txt", baseline)
	}
	return root
}

const rawRealm = `package x

var note string

func Set(cur realm, s string) { note = s }

func Render(path string) string { return "# " + note }
`

// The whole point: a caller writes a string, Render echoes it, nothing escapes.
func TestGuardUntrustedCatchesARawRender(t *testing.T) {
	root := untrustedFixture(t, map[string]string{"r/moul/x/raw": rawRealm}, "")
	err := cmdGuardUntrusted(root)
	if err == nil {
		t.Fatal("a realm that renders a caller's string raw must fail the guard")
	}
	if !strings.Contains(err.Error(), "r/moul/x/raw") {
		t.Errorf("the failure does not name the realm: %v", err)
	}
}

func TestGuardUntrustedAcceptsEscaped(t *testing.T) {
	const escaped = `package x

import "gno.land/p/moul/kit/ui/v0"

var note string

func Set(cur realm, s string) { note = s }

func Render(path string) string { return "# " + ui.Inline(note) }
`
	root := untrustedFixture(t, map[string]string{"r/moul/x/safe": escaped}, "")
	if err := cmdGuardUntrusted(root); err != nil {
		t.Fatalf("a realm that escapes must pass: %v", err)
	}
}

// Render's own `path string` is a caller string too, but every realm has one.
// Counting it would flag the whole tree and mean nothing.
func TestGuardUntrustedIgnoresRendersOwnPath(t *testing.T) {
	const readOnly = `package x

func Render(path string) string { return "# " + path }
`
	root := untrustedFixture(t, map[string]string{"r/moul/x/ro": readOnly}, "")
	if err := cmdGuardUntrusted(root); err != nil {
		t.Fatalf("a realm that stores nothing must pass: %v", err)
	}
}

// A getter returning a string is not a caller writing one in.
func TestGuardUntrustedIgnoresNonCrossingFunctions(t *testing.T) {
	const getter = `package x

var note = "fixed"

func Note() string { return note }

func Render(path string) string { return "# " + note }
`
	root := untrustedFixture(t, map[string]string{"r/moul/x/get": getter}, "")
	if err := cmdGuardUntrusted(root); err != nil {
		t.Fatalf("a realm with no crossing string setter must pass: %v", err)
	}
}

func TestGuardUntrustedOptOutNeedsARealReason(t *testing.T) {
	thin := strings.Replace(rawRealm, "var note string", "// untrusted-render: n/a\nvar note string", 1)
	root := untrustedFixture(t, map[string]string{"r/moul/x/thin": thin}, "")
	err := cmdGuardUntrusted(root)
	if err == nil || !strings.Contains(err.Error(), "answer nothing") {
		t.Fatalf("a three-character opt-out reason must fail: %v", err)
	}

	good := strings.Replace(rawRealm, "var note string",
		"// untrusted-render: every stored word is checked against the a-z charset at write time\nvar note string", 1)
	root = untrustedFixture(t, map[string]string{"r/moul/x/ok": good}, "")
	if err := cmdGuardUntrusted(root); err != nil {
		t.Fatalf("a reasoned opt-out must pass: %v", err)
	}
}

// A live realm cannot be fixed in place, so the baseline grandfathers it. The
// guard's job is the next one, not the ones the chain has already frozen.
func TestGuardUntrustedBaselineGrandfathers(t *testing.T) {
	root := untrustedFixture(t, map[string]string{"r/moul/x/raw": rawRealm},
		"# a comment\n\nr/moul/x/raw\n")
	if err := cmdGuardUntrusted(root); err != nil {
		t.Fatalf("a baselined realm must pass: %v", err)
	}
}

// A baseline entry that no longer describes the tree silences a realm nobody is
// watching any more, so it is itself a failure.
func TestGuardUntrustedRejectsAStaleBaseline(t *testing.T) {
	root := untrustedFixture(t, map[string]string{"r/moul/x/raw": rawRealm},
		"r/moul/x/raw\nr/moul/x/gone\n")
	err := cmdGuardUntrusted(root)
	if err == nil || !strings.Contains(err.Error(), "no longer apply") {
		t.Fatalf("a baseline entry for a realm that does not exist must fail: %v", err)
	}
	if !strings.Contains(err.Error(), "r/moul/x/gone") {
		t.Errorf("the failure does not name the stale entry: %v", err)
	}
}
