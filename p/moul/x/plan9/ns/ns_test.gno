package ns

import (
	"testing"

	memfs "gno.land/p/moul/x/plan9/memfs/v0"
	ninep "gno.land/p/moul/x/plan9/ninep/v0"
)

// newNs builds a namespace over a fresh ram tree seeded with files.
func newNs(t *testing.T, files ...string) (*Ns, *memfs.FS) {
	t.Helper()
	fs := memfs.New("glenda", 1)
	for _, f := range files {
		if err := fs.WriteFile(f, "contents of "+f+"\n", 1); err != nil {
			t.Fatalf("seed %s: %v", f, err)
		}
	}
	return New(fs.Root()), fs
}

func names(ents []ninep.Stat) []string {
	out := []string{}
	for _, e := range ents {
		out = append(out, e.Name)
	}
	return out
}

func eq(a, b []string) bool {
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

func TestResolveRoot(t *testing.T) {
	n, _ := newNs(t, "/bin/ls", "/bin/cat")
	st, err := n.Stat("/")
	if err != nil {
		t.Fatalf("stat root: %v", err)
	}
	if !st.IsDir() {
		t.Error("root is not a directory")
	}
	ents, err := n.ReadDir("/", false)
	if err != nil {
		t.Fatalf("readdir: %v", err)
	}
	if !eq(names(ents), []string{"bin"}) {
		t.Errorf("root listing: %v", names(ents))
	}
}

func TestReadFileAndMissing(t *testing.T) {
	n, _ := newNs(t, "/bin/ls")
	got, err := n.ReadFile("/bin/ls")
	if err != nil {
		t.Fatalf("readfile: %v", err)
	}
	if got != "contents of /bin/ls\n" {
		t.Errorf("got %q", got)
	}
	if _, err := n.ReadFile("/bin/absent"); err != ninep.ErrNotExist {
		t.Errorf("missing: got %v, want ErrNotExist", err)
	}
}

func TestDotDotIsLexical(t *testing.T) {
	n, _ := newNs(t, "/a/b/c")
	// /a/b/../b/c never asks a server about "..".
	if _, err := n.Stat("/a/b/../b/c"); err != nil {
		t.Fatalf("lexical dotdot: %v", err)
	}
	// Above the root stays at the root.
	if _, err := n.Stat("/../../a"); err != nil {
		t.Fatalf("dotdot above root: %v", err)
	}
}

func TestBindReplace(t *testing.T) {
	n, _ := newNs(t, "/bin/ls", "/usr/glenda/bin/rc")
	if err := n.Bind("/usr/glenda/bin", "/bin", MREPL); err != nil {
		t.Fatalf("bind: %v", err)
	}
	ents, _ := n.ReadDir("/bin", false)
	if !eq(names(ents), []string{"rc"}) {
		t.Errorf("after MREPL /bin should hold only rc, got %v", names(ents))
	}
	if _, err := n.Stat("/bin/ls"); err != ninep.ErrNotExist {
		t.Errorf("replaced file still reachable: %v", err)
	}
}

func TestBindAfterUnion(t *testing.T) {
	n, _ := newNs(t, "/bin/ls", "/usr/glenda/bin/rc")
	if err := n.Bind("/usr/glenda/bin", "/bin", MAFTER); err != nil {
		t.Fatalf("bind -a: %v", err)
	}
	ents, _ := n.ReadDir("/bin", false)
	if !eq(names(ents), []string{"ls", "rc"}) {
		t.Errorf("union order: got %v, want [ls rc]", names(ents))
	}
	if _, err := n.Stat("/bin/rc"); err != nil {
		t.Errorf("unioned file not reachable: %v", err)
	}
	if _, err := n.Stat("/bin/ls"); err != nil {
		t.Errorf("original file lost: %v", err)
	}
}

func TestBindBeforeUnion(t *testing.T) {
	n, _ := newNs(t, "/bin/ls", "/usr/glenda/bin/rc")
	if err := n.Bind("/usr/glenda/bin", "/bin", MBEFORE); err != nil {
		t.Fatalf("bind -b: %v", err)
	}
	ents, _ := n.ReadDir("/bin", false)
	if !eq(names(ents), []string{"rc", "ls"}) {
		t.Errorf("union order: got %v, want [rc ls]", names(ents))
	}
}

func TestUnionShadowingIsVisible(t *testing.T) {
	// Both directories hold a file called "ls". Plan 9 concatenates, so the
	// listing shows the duplicate and makes the shadowing visible.
	fs := memfs.New("glenda", 1)
	fs.WriteFile("/bin/ls", "system ls\n", 1)
	fs.WriteFile("/usr/glenda/bin/ls", "my ls\n", 1)
	n := New(fs.Root())

	if err := n.Bind("/usr/glenda/bin", "/bin", MBEFORE); err != nil {
		t.Fatalf("bind: %v", err)
	}
	ents, _ := n.ReadDir("/bin", false)
	if !eq(names(ents), []string{"ls", "ls"}) {
		t.Errorf("concatenation should show both: got %v", names(ents))
	}
	uniq, _ := n.ReadDir("/bin", true)
	if !eq(names(uniq), []string{"ls"}) {
		t.Errorf("unique listing: got %v", names(uniq))
	}
	// A walk reaches the first member, which is the one bound before.
	got, err := n.ReadFile("/bin/ls")
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if got != "my ls\n" {
		t.Errorf("shadowing: got %q, want my ls", got)
	}
}

func TestUnionIsTopLevelOnly(t *testing.T) {
	// /a and /b each hold a directory "sub", but only /a/sub/x exists.
	// Unioning /b onto /a does NOT union /a/sub with /b/sub.
	fs := memfs.New("glenda", 1)
	fs.WriteFile("/a/sub/x", "x\n", 1)
	fs.WriteFile("/b/sub/y", "y\n", 1)
	n := New(fs.Root())
	if err := n.Bind("/b", "/a", MAFTER); err != nil {
		t.Fatalf("bind: %v", err)
	}
	if _, err := n.Stat("/a/sub/x"); err != nil {
		t.Errorf("/a/sub/x should still resolve: %v", err)
	}
	if _, err := n.Stat("/a/sub/y"); err != ninep.ErrNotExist {
		t.Errorf("unions are top level only, /a/sub/y must not resolve: %v", err)
	}
}

func TestBindCapturesAChannelNotAName(t *testing.T) {
	fs := memfs.New("glenda", 1)
	fs.WriteFile("/one/f", "one\n", 1)
	fs.WriteFile("/two/f", "two\n", 1)
	n := New(fs.Root())

	if err := n.Bind("/one", "/mnt", MREPL); err != nil {
		// /mnt does not exist yet, so this must fail: see the next test.
		fs.MkdirAll("/mnt", 1)
		if err := n.Bind("/one", "/mnt", MREPL); err != nil {
			t.Fatalf("bind: %v", err)
		}
	}
	// Now rebind the SOURCE name elsewhere. The earlier bind captured the
	// directory, so /mnt must not follow.
	if err := n.Bind("/two", "/one", MREPL); err != nil {
		t.Fatalf("rebind source: %v", err)
	}
	got, _ := n.ReadFile("/mnt/f")
	if got != "one\n" {
		t.Errorf("bind should have captured the channel: /mnt/f is %q", got)
	}
	got, _ = n.ReadFile("/one/f")
	if got != "two\n" {
		t.Errorf("/one/f is %q, want two", got)
	}
}

func TestBindTargetMustExist(t *testing.T) {
	n, _ := newNs(t, "/bin/ls")
	if err := n.Bind("/bin", "/nowhere", MREPL); err != ninep.ErrNotExist {
		t.Errorf("bind onto a missing name: got %v, want ErrNotExist", err)
	}
	if err := n.Bind("/nowhere", "/bin", MREPL); err != ninep.ErrNotExist {
		t.Errorf("bind from a missing name: got %v, want ErrNotExist", err)
	}
}

func TestCreateTargetNeedsMCREATE(t *testing.T) {
	fs := memfs.New("glenda", 1)
	fs.MkdirAll("/bin", 1)
	fs.MkdirAll("/usr/glenda/bin", 1)
	n := New(fs.Root())

	// A plain directory takes creates with no flag at all.
	if _, err := n.CreateTarget("/bin"); err != nil {
		t.Fatalf("plain directory should accept a create: %v", err)
	}

	// Made into a union with no MCREATE anywhere, creation is refused.
	if err := n.Bind("/usr/glenda/bin", "/bin", MAFTER); err != nil {
		t.Fatalf("bind: %v", err)
	}
	if _, err := n.CreateTarget("/bin"); err != ninep.ErrNoCreate {
		t.Errorf("union without MCREATE: got %v, want ErrNoCreate", err)
	}

	// Rebinding with MCREATE picks that member.
	if err := n.Bind("/usr/glenda/bin", "/bin", MAFTER|MCREATE); err != nil {
		t.Fatalf("bind -ac: %v", err)
	}
	target, err := n.CreateTarget("/bin")
	if err != nil {
		t.Fatalf("union with MCREATE: %v", err)
	}
	if _, err := target.Create("new", ninep.FilePerm, 2); err != nil {
		t.Fatalf("create: %v", err)
	}
	// It landed in the MCREATE member, not in /bin's own directory.
	if _, err := ninep.Walk(fs.Root(), ninep.Elems("/usr/glenda/bin/new")); err != nil {
		t.Errorf("create went to the wrong member: %v", err)
	}
}

func TestUnmount(t *testing.T) {
	n, _ := newNs(t, "/bin/ls", "/usr/glenda/bin/rc")
	n.Bind("/usr/glenda/bin", "/bin", MAFTER)
	ents, _ := n.ReadDir("/bin", false)
	if len(ents) != 2 {
		t.Fatalf("setup: %v", names(ents))
	}

	if err := n.Unmount("/usr/glenda/bin", "/bin"); err != nil {
		t.Fatalf("unmount: %v", err)
	}
	ents, _ = n.ReadDir("/bin", false)
	if !eq(names(ents), []string{"ls"}) {
		t.Errorf("after unmount: %v", names(ents))
	}
	if err := n.Unmount("", "/bin"); err != ErrNotBound {
		t.Errorf("unmount of an unbound name: got %v, want ErrNotBound", err)
	}
}

func TestUnmountAll(t *testing.T) {
	n, _ := newNs(t, "/bin/ls", "/usr/glenda/bin/rc")
	n.Bind("/usr/glenda/bin", "/bin", MAFTER)
	if err := n.Unmount("", "/bin"); err != nil {
		t.Fatalf("unmount all: %v", err)
	}
	ents, _ := n.ReadDir("/bin", false)
	if !eq(names(ents), []string{"ls"}) {
		t.Errorf("name should be restored to its original contents: %v", names(ents))
	}
	if len(n.Ops()) != 0 {
		t.Errorf("ops should be gone: %v", n.Ops())
	}
}

func TestCd(t *testing.T) {
	n, _ := newNs(t, "/usr/glenda/lib/profile")
	if err := n.Cd("/usr/glenda"); err != nil {
		t.Fatalf("cd: %v", err)
	}
	if n.Cwd() != "/usr/glenda" {
		t.Errorf("cwd: %q", n.Cwd())
	}
	got, err := n.ReadFile("lib/profile")
	if err != nil {
		t.Fatalf("relative read: %v", err)
	}
	if got == "" {
		t.Error("relative read came back empty")
	}
	if err := n.Cd("lib/profile"); err != ninep.ErrNotDir {
		t.Errorf("cd into a file: got %v, want ErrNotDir", err)
	}
	if err := n.Cd("/nowhere"); err != ninep.ErrNotExist {
		t.Errorf("cd nowhere: got %v", err)
	}
}

func TestStringMatchesNsFormat(t *testing.T) {
	n, _ := newNs(t, "/bin/ls", "/usr/glenda/bin/rc", "/tmp/x")
	n.Bind("/usr/glenda/bin", "/bin", MAFTER|MCREATE)
	n.Bind("/tmp", "/usr/glenda", MBEFORE)
	n.Cd("/usr/glenda")

	want := "bind -ac /usr/glenda/bin /bin\n" +
		"bind -b /tmp /usr/glenda\n" +
		"cd /usr/glenda\n"
	if got := n.String(); got != want {
		t.Errorf("ns output:\ngot:\n%s\nwant:\n%s", got, want)
	}
}

func TestFlagString(t *testing.T) {
	tests := []struct {
		flag Flag
		want string
	}{
		{MREPL, ""},
		{MBEFORE, "-b"},
		{MAFTER, "-a"},
		{MCREATE, "-c"},
		{MAFTER | MCREATE, "-ac"},
		{MBEFORE | MCREATE, "-bc"},
	}
	for _, tt := range tests {
		if got := tt.flag.String(); got != tt.want {
			t.Errorf("Flag(%d): got %q, want %q", uint32(tt.flag), got, tt.want)
		}
	}
}

func TestUnionWidthIsBounded(t *testing.T) {
	fs := memfs.New("glenda", 1)
	fs.MkdirAll("/bin", 1)
	for i := 0; i < MaxUnion+2; i++ {
		fs.MkdirAll("/d"+string(rune('a'+i)), 1)
	}
	n := New(fs.Root())
	var err error
	for i := 0; i < MaxUnion+2; i++ {
		err = n.Bind("/d"+string(rune('a'+i)), "/bin", MAFTER)
		if err != nil {
			break
		}
	}
	if err != ErrWideUnion {
		t.Errorf("got %v, want ErrWideUnion", err)
	}
}

func TestReadDirOnAFile(t *testing.T) {
	n, _ := newNs(t, "/bin/ls")
	if _, err := n.ReadDir("/bin/ls", false); err != ninep.ErrNotDir {
		t.Errorf("got %v, want ErrNotDir", err)
	}
}

func TestDepthIsBounded(t *testing.T) {
	n, _ := newNs(t, "/a")
	p := ""
	for i := 0; i <= ninep.MaxDepth; i++ {
		p += "/x"
	}
	if _, err := n.Stat(p); err != ninep.ErrTooDeep {
		t.Errorf("got %v, want ErrTooDeep", err)
	}
}
